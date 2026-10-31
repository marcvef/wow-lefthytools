local _, ns = ...
local LT = ns.LT
local E = ns.Echoes

-- The path: where you go, as anchors ("@": a new segment), points (whole yards, deltas) and travel
-- modes ("m"), and the zone ("z"); the session lines ("o"). Written through the line encoder
-- (Lines.lua; docs/echoes.md, Recording). Events.lua writes everything else and asks this file for
-- a spot first (E.capture.Spot), so every event sits on the path.
--
-- Polls LT.Position every 0.5 s while moving (IsPlayerMoving, or moved 0.5 yd since the last poll),
-- every 1 s standing still or on a flight path (boats and teleports fire no movement events). The
-- store rule, from A (the last point written, E.state.north / west):
--   * distance: a point at 25 yd from A (100 on a flight path);
--   * bend: a sample since A more than 3 yd off the line from A to here (6 carried, 10 on a flight
--     path): the sample before this one is stored (at most 8 samples kept);
--   * start: moving again after standing still: the old spot once more, now (else the site's dot
--     would crawl from it through all the time you stood there);
--   * stop: the spot where you stopped (PLAYER_STOPPED_MOVING makes the next tick poll);
--   * a travel mode change: a point, then the "m" line;
--   * before an event: a point if you're more than STALE yd from A.
-- A new segment (an anchor) on a loading screen, a continent change, a jump of more than 50 + 40 *
-- seconds between two polls, the position going (an instance) or coming back, and the release to
-- the graveyard. Its why: hearthstone (h), a teleport spell (p), a summon (u), the release (r), an
-- instance entered (i) or left (o), login (s), a loading screen (l), another jump (j).
--
-- Never lags the client: handlers only note things (PLAYER_LEAVING_WORLD and PLAYER_LOGOUT write
-- their last point and line at once: no tick comes before the loading screen); a poll is a handful
-- of calls, at most a start point and one point, and makes no tables (the sample buffer is two
-- arrays of 8 numbers).

local issecret = LT.IsSecret
local Value = LT.Value
local floor, sqrt = math.floor, math.sqrt

local POLL_MOVING, POLL_STILL = 0.5, 1 -- seconds between polls
local MOVED = 0.5                       -- yards since the last poll: moving
local FAR, FAR_TAXI = 25, 100           -- yards from the last point: a point
local BEND, BEND_CARRIED, BEND_TAXI = 3, 6, 10 -- yards off the line: a point at the bend
local BUFFER = 8                        -- samples since the last point, for the bends
local JUMP, JUMP_PER_SECOND = 50, 40    -- farther between two polls: a jump (a new segment)
local CARRIED = 3                       -- yd/s faster than you move yourself: carried (a boat)
local STALE = 3                         -- yards from the last point: an event stores one first
local CAUSE_SPELL, CAUSE_SUMMON, CAUSE_RELEASE = 20, 120, 20 -- seconds a noted cause explains a jump
local RELEASE_WAIT = 1                  -- seconds the release's anchor waits for the ghost to move
local LOADING_WAIT = 3                  -- seconds after a loading screen to wait for a position
local ZONE_EVERY = 10                   -- seconds: the zone is checked at least this often
local HEARTHSTONE = 8690
local TRAVEL_FORMS = { [3] = true, [16] = true } -- GetShapeshiftFormID: Travel Form, Ghost Wolf

-- What Path.lua, Events.lua and Changes.lua share (the capture): Spot, NoteCause, Ready, Cap, ...
local C = E.capture or {}
E.capture = C

---------------------------------------------------------------------------
-- What's kept per character across sessions: E.data.capture[<GUID>] (Changes.lua's baselines: gear,
-- reputation, professions, bind, group, XP, dungeon, battleground, played). E.data.friends: a
-- LefthyTools friend's GUID -> "Name-Realm", remembered from Beacon (Changes.lua).
---------------------------------------------------------------------------

table.insert(LT.onLoad, function()
	local data = E.data
	if not data then
		return
	end
	data.capture = type(data.capture) == "table" and data.capture or {}
	for key, cap in pairs(data.capture) do
		if type(cap) ~= "table" then
			data.capture[key] = nil
		end
	end
	data.friends = type(data.friends) == "table" and data.friends or {}
end)

-- This character's capture table (made when first asked), or nil while its GUID isn't known.
function C.Cap()
	if C.cap then
		return C.cap
	end
	local data, guid = E.data, Value(UnitGUID, "player")
	if not (data and type(data.capture) == "table" and type(guid) == "string") then
		return nil
	end
	local cap = data.capture[guid]
	if type(cap) ~= "table" then
		cap = {}
		data.capture[guid] = cap
	end
	C.cap = cap
	return cap
end

---------------------------------------------------------------------------
-- What a poll remembers (S). Reset at load, at every start, and by E.capture.Reset (what a /reload
-- forgets; for tests).
---------------------------------------------------------------------------

local S = {}
local bn, bw = {}, {} -- the samples since the last point (north, west), oldest first
local resets = {}

local function Reset()
	S.pending = nil       -- an anchor to write on the next tick: "s" (a session starts), "reload", "load"
	S.pendingAt = 0       -- (GetTime) when it was noted
	S.loading = false     -- between PLAYER_LEAVING_WORLD and PLAYER_ENTERING_WORLD
	S.wasInstance = false -- in an instance before the loading screen
	S.inInstance = false  -- in an instance at the last anchor
	S.polledAt = -math.huge
	S.havePrev = false    -- the last poll's sample: S.pn, S.pw (north, west), S.pMoving
	S.pn, S.pw, S.pMoving = nil, nil, false
	S.lastAt = -math.huge -- E.Now() of the last point or anchor written
	S.count = 0           -- samples in bn / bw
	S.pendingMode = nil   -- a mode seen once (swimming and carried need two polls)
	S.modeCheck = false   -- read the mode on the next poll, moved or not
	S.pollNow = false     -- poll on the next tick (started or stopped moving, ...)
	S.stopped = false     -- PLAYER_STOPPED_MOVING since the last poll: that poll is the stop
	S.zoneDirty, S.zoneAt = false, 0
	S.spotAt = nil        -- (GetTime) of the last spot: once per tick is enough
	S.hearthAt, S.teleportAt, S.teleportSpell, S.summonAt, S.releasedAt = nil, nil, nil, nil, nil
	C.cap = nil
end
Reset()
resets[1] = Reset

-- What a /reload forgets (the capture's memory; the saved tables and E.state stay): for tests.
function C.Reset()
	for _, fn in ipairs(resets) do
		fn()
	end
end
C.resets = resets -- (Events.lua and Changes.lua add their own)

---------------------------------------------------------------------------
-- Reading the world
---------------------------------------------------------------------------

local function Round(v)
	return floor(v + 0.5)
end

local function Distance(n1, w1, n2, w2)
	local dn, dw = n2 - n1, w2 - w1
	return sqrt(dn * dn + dw * dw)
end

local function Yes(f, ...)
	return Value(f, ...) == true
end

-- The instance map I'm on: GetInstanceInfo's eighth answer, outside instances the continent's (0
-- Eastern Kingdoms, 1 Kalimdor); nil when it isn't readable.
local function MapID()
	local got, _, _, _, _, _, _, _, id = pcall(GetInstanceInfo)
	return got and type(id) == "number" and not issecret(id) and id or nil
end

-- In an instance (a dungeon, a raid, a battleground), and the instance's map ID.
local function Instance()
	local ok, inInstance = pcall(IsInInstance)
	if not (ok and inInstance == true) then
		return false
	end
	return true, MapID()
end
C.Instance = Instance

-- The travel mode as the game says it now (docs/echoes.md: t g c s m v f, in this order). d and dt:
-- the yards moved since the last poll and the seconds it took (nil at an anchor: never carried).
local function RawMode(d, dt)
	if Yes(UnitOnTaxi, "player") then
		return "t"
	elseif Yes(UnitIsGhost, "player") then
		return "g"
	end
	local speed = d and dt and dt > 0 and Value(GetUnitSpeed, "player")
	if type(speed) == "number" and d / dt > speed + CARRIED then
		return "c" -- (no transport API: carried, a boat or a zeppelin, guessed by the speed)
	elseif Yes(IsSwimming) then
		return "s"
	elseif Yes(IsMounted) then
		return "m"
	end
	local form = Value(GetShapeshiftFormID)
	if type(form) == "number" and TRAVEL_FORMS[form] then
		return "v"
	end
	return "f"
end

-- The mode to change to, or nil. Swimming flickers at the surface and the carried guess can be a
-- moment's knockback: changing to or from either needs the same answer on two polls in a row.
local function NextMode(raw)
	local mode = E.state.mode or "f"
	if raw == mode then
		S.pendingMode = nil
		return nil
	end
	local slow = raw == "c" or raw == "s" or ((mode == "c" or mode == "s") and raw ~= "t" and raw ~= "g")
	if slow and S.pendingMode ~= raw then
		S.pendingMode = raw
		return nil
	end
	S.pendingMode = nil
	return raw
end

---------------------------------------------------------------------------
-- Writing the path
---------------------------------------------------------------------------

-- A point at north, west; not when it's where the last one is (whole yards), unless always (the
-- start point: the same spot, later). true if written.
local function Store(north, west, always)
	local state = E.state
	if not always and state.north and Round(north) == state.north and Round(west) == state.west then
		return false
	end
	if E.Point(north, west) then
		S.lastAt = E.Now()
		S.count = 0
		return true
	end
	return false
end

local function Push(north, west)
	if S.count == BUFFER then
		for i = 1, BUFFER - 1 do
			bn[i], bw[i] = bn[i + 1], bw[i + 1]
		end
	else
		S.count = S.count + 1
	end
	bn[S.count], bw[S.count] = north, west
end

-- Does a sample since the last point lie more than bend yd off the line from it to here?
local function Bent(north, west, bend)
	local state = E.state
	local an, aw = state.north, state.west
	local dn, dw = north - an, west - aw
	local len = sqrt(dn * dn + dw * dw)
	for i = 1, S.count do
		local off
		if len < 0.001 then
			off = Distance(an, aw, bn[i], bw[i])
		else
			off = math.abs(dn * (bw[i] - aw) - dw * (bn[i] - an)) / len
		end
		if off > bend then
			return true
		end
	end
	return false
end

-- What caused a jump, from what was noted shortly before it (the noted causes go: they're used).
local function Cause()
	local now = GetTime()
	local why, spell
	if S.hearthAt and now - S.hearthAt <= CAUSE_SPELL then
		why, spell = "h", HEARTHSTONE
	elseif S.teleportAt and now - S.teleportAt <= CAUSE_SPELL then
		why, spell = "p", S.teleportSpell
	elseif S.summonAt and now - S.summonAt <= CAUSE_SUMMON then
		why = "u"
	elseif S.releasedAt and now - S.releasedAt <= CAUSE_RELEASE then
		why = "r"
	end
	if why then
		S.hearthAt, S.teleportAt, S.teleportSpell, S.summonAt, S.releasedAt = nil, nil, nil, nil, nil
	end
	return why, spell
end

-- Something that explains a jump coming: "h" (hearthstone), "p" (a teleport spell: spell), "u" (a
-- summon offered), "r" (released to the graveyard: the next poll starts a segment there).
function C.NoteCause(why, spell)
	local now = GetTime()
	if why == "h" then
		S.hearthAt = now
	elseif why == "p" then
		S.teleportAt, S.teleportSpell = now, spell
	elseif why == "u" then
		S.summonAt = now
	elseif why == "r" then
		S.releasedAt = now -- (polled every tick until its anchor is written)
	end
end

-- The travel mode is read on the next tick's poll, moved or not (back to life: no longer a ghost).
function C.CheckMode()
	S.modeCheck, S.pollNow = true, true
end

-- The zone ("z"), when it changed (force: written anyway, after a session's anchor).
local function Zone(force)
	S.zoneDirty, S.zoneAt = false, GetTime() + ZONE_EVERY
	local map = C_Map and Value(C_Map.GetBestMapForUnit, "player")
	local sub = Value(GetSubZoneText)
	if map == nil and sub == nil then
		return
	end
	local state = E.state
	if force or map ~= state.map or sub ~= state.sub then
		if not force then
			C.Spot()
		end
		E.Zone(map, sub)
	end
end

-- A new segment here (north, west nil: no position, in an instance), the mode as it is now.
local function Anchor(continent, north, west, why, spell)
	E.Anchor(continent, north, west, RawMode(), why, spell)
	S.lastAt, S.count, S.pendingMode = E.Now(), 0, nil
	S.inInstance = (Instance())
	S.havePrev, S.pn, S.pw, S.pMoving = north ~= nil, north, west, false
	S.zoneDirty = true
end

-- Not near the last point (STALE yd or more, but no jump: the next poll handles that): one here.
local function StaleCheck(north, west)
	local state = E.state
	if not (state.anchored and state.north) then
		return false
	end
	if not north then
		local continent
		continent, north, west = LT.Position()
		if not north or continent ~= state.continent then
			return false
		end
	end
	local d = Distance(state.north, state.west, north, west)
	return d >= STALE and d <= JUMP and Store(north, west)
end

-- One poll: the position, then the store rule. spot: an event follows, so it must have a spot.
local function Poll(now, spot)
	local state = E.state
	local since = now - S.polledAt
	if since < 0.05 then -- (polled this very moment: only the spot)
		if spot then
			StaleCheck()
		end
		return
	end
	S.polledAt = now
	local continent, north, west = LT.Position()
	if north == nil then -- no position here (an instance, or the game hides it)
		if state.anchored and state.north ~= nil then
			local _, map = Instance()
			Anchor(map or state.continent, nil, nil, (Cause()) or "j")
		end
		S.havePrev = false
		return
	end
	if not state.anchored then -- (a new page that didn't go on from the last: E.Continue)
		Anchor(continent, north, west, "c")
		return
	elseif state.north == nil or continent ~= state.continent then -- the position is back, another continent
		local why, spell = Cause()
		Anchor(continent, north, west, why or "j", spell)
		return
	end
	if not S.havePrev then
		S.pn, S.pw, S.pMoving, since = state.north, state.west, false, math.max(since, POLL_STILL)
	end
	local d = Distance(S.pn, S.pw, north, west)
	local released = S.releasedAt and now - S.releasedAt <= CAUSE_RELEASE
	if released and (d > MOVED or now - S.releasedAt > RELEASE_WAIT) then -- the ghost at the graveyard
		Cause()
		Anchor(continent, north, west, "r")
		return
	elseif d > JUMP + JUMP_PER_SECOND * math.min(since, 5) then
		local why, spell = Cause()
		Anchor(continent, north, west, why or "j", spell)
		return
	end
	-- (MOVED yards per poll; a poll sooner, for an event, at the same pace. The poll after
	-- PLAYER_STOPPED_MOVING is the stop, however far it came since the last.)
	local stop = S.stopped
	local moving = Yes(IsPlayerMoving) or (not stop and d >= MOVED * math.min(1, since / POLL_MOVING))
	S.stopped = false
	local mode
	if d > 0.05 or S.modeCheck then -- (the mode only where the position changed)
		S.modeCheck = false
		-- (Not carried on the stop's poll: the game says speed 0 by then, however far it came.)
		mode = NextMode(RawMode(not stop and d or nil, since))
	else
		S.pendingMode = nil -- (two polls in a row: one that doesn't look breaks the row)
	end
	local stored = false
	if moving and not S.pMoving and E.Now() > S.lastAt then
		Store(S.pn, S.pw, true) -- start: the old spot once more, now
	end
	if mode then
		stored = Store(north, west)
		E.Mode(mode)
	elseif S.pMoving and not moving then
		stored = Store(north, west) -- stop
	elseif moving then
		local current = state.mode
		local far = current == "t" and FAR_TAXI or FAR
		local bend = current == "t" and BEND_TAXI or current == "c" and BEND_CARRIED or BEND
		if Bent(north, west, bend) then
			stored = Store(S.pn, S.pw) -- the sample before the bend
			Push(north, west)
		elseif Distance(state.north, state.west, north, west) >= far then
			stored = Store(north, west)
		else
			Push(north, west)
		end
	end
	S.pn, S.pw, S.pMoving, S.havePrev = north, west, moving, true
	if spot and not stored then
		StaleCheck(north, west)
	end
end

-- Before an event: the path brought up to now, so the event's spot is where you are (once per tick).
function C.Spot()
	if not E.recording or S.pending or S.loading then
		return
	end
	local now = GetTime()
	if S.spotAt == now then
		return
	end
	S.spotAt = now
	Poll(now, true)
end

-- The capture writes (anchors and events) only once the session's anchor is there.
function C.Ready()
	return E.recording and not S.pending and not S.loading
end

-- The last point before a loading screen, a logout or switching off (no tick comes before it).
local function LastPoint()
	local state = E.state
	if not (E.recording and state.anchored and state.north) or S.loading then
		return
	end
	local continent, north, west = LT.Position()
	if north and continent == state.continent and Distance(state.north, state.west, north, west) <= JUMP then
		Store(north, west)
	end
end

-- After a loading screen or when a session starts: the anchor (when the game says where you are,
-- at most LOADING_WAIT seconds after it), the zone, the session line.
local function Arrive(now)
	local continent, north, west = LT.Position()
	local inInstance, map = Instance()
	if north == nil and not inInstance and now - S.pendingAt < LOADING_WAIT then
		return -- (not there yet)
	end
	local pending, why, spell = S.pending, nil, nil
	if pending == "load" then
		why, spell = Cause()
		if not why then
			why = (inInstance and not S.wasInstance and "i") or (S.wasInstance and not inInstance and "o") or "l"
		end
	else
		why = pending == "reload" and "l" or "s"
		Cause() -- (a cause from before doesn't explain a login)
	end
	S.pending, S.polledAt = nil, now
	if north == nil then -- (an instance's map; where the game hides the position, the continent it says)
		Anchor(map or MapID() or E.state.continent, nil, nil, why, spell)
	else
		Anchor(continent, north, west, why, spell)
	end
	Zone(pending ~= "load")
	if pending ~= "load" then
		E.Line("o", 1) -- (also after a /reload: PLAYER_LOGOUT can't tell one from logging out, so it wrote o0)
	end
	C.arrived = pending -- (Changes.lua: dungeons and battlegrounds entered or left; a session's checks)
end

E.OnTick(function(now)
	if S.loading then
		return
	elseif S.pending then
		return Arrive(now)
	end
	local interval = (S.pMoving and E.state.mode ~= "t") and POLL_MOVING or POLL_STILL
	local released = S.releasedAt and now - S.releasedAt <= CAUSE_RELEASE -- (its anchor: polled every tick)
	if S.pollNow or released or now - S.polledAt >= interval - 0.01 then
		S.pollNow = false
		Poll(now)
	end
	if S.zoneDirty or now >= S.zoneAt then
		Zone(false)
	end
end)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

E.On("PLAYER_STARTED_MOVING", function()
	S.pollNow = true
end)
E.On("PLAYER_STOPPED_MOVING", function()
	S.pollNow, S.stopped = true, true
end)

local function ZoneSoon()
	S.zoneDirty = true
end
E.On("ZONE_CHANGED", ZoneSoon)
E.On("ZONE_CHANGED_INDOORS", ZoneSoon)
E.On("ZONE_CHANGED_NEW_AREA", ZoneSoon)

-- A loading screen begins: its last point now (no tick comes before it).
E.On("PLAYER_LEAVING_WORLD", function()
	LastPoint()
	S.wasInstance = S.inInstance
	S.loading = true
end)

-- And ends: the anchor on the next tick (a login: "s"; a /reload: "l", the session goes on; else
-- what caused it). A session whose anchor isn't written yet stays one through another loading screen.
E.On("PLAYER_ENTERING_WORLD", function(isInitialLogin, isReloadingUi)
	S.loading = false
	S.pendingAt = GetTime()
	if isInitialLogin == true then
		S.pending = "s"
	elseif isReloadingUi == true then
		S.pending = "reload"
	elseif S.pending ~= "s" and S.pending ~= "reload" then
		S.pending = "load"
	end
end)

-- The session ends: the last point, whatever Events.lua still holds, "o0". Not when it hasn't
-- started yet (its anchor and "o1" not written).
local function End()
	if S.pending == "s" or S.pending == "reload" then
		return
	end
	LastPoint()
	if C.Flush then
		C.Flush() -- Events.lua: what's noted and not written yet
	end
	E.Line("o", 0)
end

E.On("PLAYER_LOGOUT", End)

-- Recording starts (login, or switched on): a session starts on the next tick, unless a loading
-- screen's end says otherwise first (a /reload). Switched off: it ends.
E.When("start", function()
	C.Reset()
	S.pending, S.pendingAt = "s", GetTime()
end)

E.When("stop", End)
