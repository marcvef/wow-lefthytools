local _, ns = ...
local LT = ns.LT
local L = ns.L
local M = LT:GetModule("beacon")
local B = ns.Beacon
local S = B.Stream

-- The fight stream between friends: watching a friend's fight, and friends watching yours. One
-- message kind, "O" (older builds ignore it), with a word after it:
--
--   O2;h;<1|0>          I can be watched (my setting streamShare), with every answer and when it
--                       changes. Only friends who said 1 can be watched.
--   O2;w;<1|0>          to a friend: I watch your fight, again every KEEPALIVE seconds while I do
--                       (0: I stopped). A watcher not heard from for WATCHER_TIMEOUT is gone.
--   O2;f;<frame>        to my watchers: what's around me now, twice a second (less with many
--                       watchers, every QUIET_GAP when nothing's going on). Waiting frames are
--                       replaced, never piled up. The frame, ";"-separated:
--                         continent; uiMapID; north; west (yards, empty in instances); facing
--                         (degrees); state (c combat, d dead, g ghost); power (M/R/E/F + percent);
--                         form (its spell ID); cast (spellID,elapsed,total in tenths of a second,
--                         c if channelled); recent (spellID,seconds ago/...); mobs:
--                         id,degrees,yards,sure 0-9,flags[,cast spellID]/... (degrees clockwise
--                         from north; flags: a attacking me, c in combat, t my target, d dead,
--                         e elite, x rare elite, r rare, m off my screen, b beyond: yards is the
--                         longest range it's beyond, s casting, p a player, f friendly, g in my
--                         group: placed exactly). As many as fit, the ones that matter first.
--   O2;n;<id>;<level>;<name>
--                       a mob's name, once per watcher before the first frame with that id
--   O2;u;<id>;<level>;<classFile>;<name>
--                       the same for a player (their class colours the dot; older builds ignore
--                       it and show the player as an unnamed mob)
--
-- Spells go as IDs: the watcher's client names them, in its own language. Nothing runs while
-- nobody watches and you watch nobody; the sensor (StreamSense.lua) runs while someone watches you.

local VERSION = B.VERSION
local KEEPALIVE = 5
local WATCHER_TIMEOUT = 12
local FRAME_GAP = 0.5         -- a frame per watcher at most this often ...
local FRAMES_PER_SECOND = 4   -- ... and all watchers together at most this many
local QUIET_GAP = 1           -- nothing going on: a frame this often (place and facing; 2 felt slow)
local MAX_FRAME = 245         -- bytes of a frame (the message: 250)
local RECENT_TIME = 12
local NAME_BYTES = 40
local MAX_NAMES = 200         -- a friend's mob names kept at most
local STOP_GAP = 10           -- frames from someone I don't watch: tell them, at most this often
local MAX_ID = 999
local TICK = 1
local issecret = S.issecret

local watchers = {}   -- gameAccountID -> { at (last heard), sentAt (last frame), names = { [id] = key } }
local watching = {}   -- gameAccountID -> { sentAt (last keepalive) }
local streams = {}    -- gameAccountID -> { payload, at, read, names = { [id] = { name, level } } }
local stopSaid = {}   -- gameAccountID -> when I last said "I don't watch you"
local gone = {}       -- gameAccountID -> { why = "stopped" | "away", name }: closed (and said) on the tick
local idFor, keyFor, idUsed, lastId = {}, {}, {}, 0
local ticker = CreateFrame("Frame")
ticker:Hide()
local indicator

local function Message(word, rest)
	return ("O%s;%s;%s"):format(VERSION, word, rest)
end

local function Share()
	return M.enabled and M.db.streamShare
end

local function Count(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end

local function Wake()
	if next(watchers) or next(watching) or next(gone) then
		ticker:Show()
	end
end

---------------------------------------------------------------------------
-- Being watched: the small red dot and the count, right of the calendar button
---------------------------------------------------------------------------

local function IndicatorOnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
	GameTooltip:SetText(L["Watching your fights"], 1, 0.3, 0.25)
	for id in pairs(watchers) do
		local peer = B.peers[id]
		if peer and peer.name then
			GameTooltip:AddLine(LT.Window.ClassColorCode(peer.classFile) .. peer.name .. "|r")
		end
	end
	GameTooltip:AddLine(L["Beacon settings: Friends can watch my fights."], 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

local function UpdateIndicator()
	local count = Count(watchers)
	if count == 0 or not M.db.streamWatchedDot then
		if indicator then
			indicator:Hide()
		end
		return
	end
	if not indicator then
		-- Narrow: the dot with the number under it, so it fits between the calendar button and the
		-- screen's edge (side by side ran off the screen); kept on screen whatever the layout.
		indicator = CreateFrame("Frame", "LefthyToolsStreamWatched", UIParent)
		indicator:SetSize(10, 20)
		indicator:SetFrameStrata("MEDIUM")
		indicator:SetClampedToScreen(true)
		local anchor = _G.GameTimeFrame
		if anchor then
			indicator:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 0, -1)
		elseif _G.Minimap then
			indicator:SetPoint("BOTTOMLEFT", Minimap, "TOPRIGHT", 0, 0)
		else
			indicator:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -8, -8)
		end
		local dot = indicator:CreateTexture(nil, "OVERLAY")
		dot:SetSize(6, 6)
		dot:SetPoint("TOP", 0, -1)
		dot:SetColorTexture(1, 0.15, 0.1, 1)
		local mask = indicator:CreateMaskTexture()
		mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(dot)
		dot:AddMaskTexture(mask)
		indicator.Dot = dot
		indicator.Count = indicator:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
		indicator.Count:SetPoint("TOP", dot, "BOTTOM", 0, -1)
		indicator:EnableMouse(true)
		indicator:SetScript("OnEnter", IndicatorOnEnter)
		indicator:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	indicator.Count:SetText(tostring(count))
	indicator:Show()
end
S.UpdateIndicator = UpdateIndicator

local function WatchersChanged()
	S.SenseNeed("stream", next(watchers) ~= nil)
	UpdateIndicator()
	Wake()
end

---------------------------------------------------------------------------
-- Sending my fight
---------------------------------------------------------------------------

-- A small number for a mob (its GUID is too long for a frame), kept while it's around.
local function IdFor(key, now)
	local id = idFor[key]
	if not id then
		for _ = 1, MAX_ID do
			lastId = lastId % MAX_ID + 1
			local old = keyFor[lastId]
			if not old or now - (idUsed[lastId] or 0) > 60 then
				if old then
					idFor[old] = nil
				end
				id = lastId
				break
			end
		end
		if not id then
			return nil
		end
		idFor[key], keyFor[id] = id, key
	end
	idUsed[id] = now
	return id
end

local function Int(v)
	return tostring(math.floor(v + 0.5))
end

-- Radians as whole degrees, 0-359.
local function Deg(radians)
	return math.floor(math.deg(radians or 0) + 0.5) % 360
end

local FLAG_CLASS = { elite = "e", worldboss = "e", rareelite = "x", rare = "r" }

-- Which mobs go first when not all fit: my target, the ones attacking me, in combat, the nearest.
local function Weight(mob)
	return (mob.target and 1000 or 0) + (mob.attacking and 300 or 0) + (mob.group and 150 or 0) + (mob.combat and 100 or 0)
		- (mob.yards or 50)
		- (mob.remembered and 50 or 0) - (mob.dead and 200 or 0)
end

local order = {}
local function ByWeight(a, b)
	return a.weight > b.weight
end

-- The frame (without names) and the ids used in it, in order.
local function Encode(picture, now)
	local parts = {}
	if picture.continent and picture.north then
		parts[1], parts[3], parts[4] = tostring(picture.continent), Int(picture.north), Int(picture.west)
	else
		parts[1], parts[3], parts[4] = "", "", ""
	end
	parts[2] = picture.mapID and tostring(picture.mapID) or ""
	parts[5] = tostring(Deg(picture.facing))
	parts[6] = (picture.combat and "c" or "") .. (picture.ghost and "g" or picture.dead and "d" or "")
	local power = picture.power
	parts[7] = power and S.POWER_LETTERS[power.token] and (S.POWER_LETTERS[power.token] .. Int(power.frac * 100)) or ""
	parts[8] = picture.form and picture.form.spellID and tostring(picture.form.spellID) or ""
	local cast = picture.cast
	if cast and cast.spellID and now <= cast.finish then
		parts[9] = ("%d,%d,%d%s"):format(cast.spellID, math.max(0, math.floor((now - cast.start) * 10)),
			math.max(1, math.floor((cast.finish - cast.start) * 10 + 0.5)), cast.channel and ",c" or "")
	else
		parts[9] = ""
	end
	local recent = {}
	for _, entry in ipairs(picture.recent) do
		local age = now - entry.at
		if entry.spellID and age < RECENT_TIME then
			recent[#recent + 1] = ("%d,%d"):format(entry.spellID, math.floor(age))
		end
	end
	parts[10] = table.concat(recent, "/")
	local head = table.concat(parts, ";") .. ";"
	wipe(order)
	for _, mob in ipairs(picture.mobs) do
		mob.weight = Weight(mob)
		order[#order + 1] = mob
	end
	table.sort(order, ByWeight)
	local mobs, ids, size = {}, {}, #head
	for _, mob in ipairs(order) do
		local id = IdFor(mob.key, now)
		if id then
			local flags = (mob.attacking and "a" or "") .. (mob.combat and "c" or "") .. (mob.target and "t" or "")
				.. (mob.dead and "d" or "") .. (FLAG_CLASS[mob.class] or "") .. (mob.remembered and "m" or "")
				.. (mob.beyond and "b" or "") .. (mob.casting and "s" or "") .. (mob.player and "p" or "")
				.. (mob.friendly and "f" or "") .. (mob.group and "g" or "")
			local yards = mob.beyond or mob.yards
			local entry = ("%d,%d,%s,%d,%s"):format(id, Deg(mob.bearing),
				yards and Int(math.min(yards, 99)) or "", math.floor(math.max(0, math.min(1, mob.sure or 1)) * 9 + 0.5), flags)
			if mob.casting and mob.castID then
				entry = entry .. "," .. mob.castID
			end
			if size + #entry + 1 > MAX_FRAME then
				break
			end
			size = size + #entry + 1
			mobs[#mobs + 1] = entry
			ids[#ids + 1] = { id, mob }
		end
	end
	return head .. table.concat(mobs, "/"), ids
end

-- After every look of the sensor: a frame for each watcher whose turn it is.
S.OnSensed(function(picture)
	if not next(watchers) or not Share() then
		return
	end
	local now = GetTime()
	local busy = picture.combat or picture.cast or #picture.mobs > 0
	local gap = busy and math.max(FRAME_GAP, Count(watchers) / FRAMES_PER_SECOND) or QUIET_GAP
	local frame, ids
	for id, watcher in pairs(watchers) do
		if now - watcher.sentAt >= gap - 0.05 then
			if not frame then
				frame, ids = Encode(picture, now)
			end
			watcher.sentAt = now
			local named = false
			for _, pair in ipairs(ids) do
				local mobId, mob = pair[1], pair[2]
				if watcher.names[mobId] ~= mob.key then
					watcher.names[mobId] = mob.key
					named = true
					local level = mob.level and not issecret(mob.level) and tostring(mob.level) or ""
					if mob.player then
						B.Queue(id, Message("u", ("%d;%s;%s;%s"):format(mobId, level, mob.classFile or "", B.Clean(mob.name, NAME_BYTES))))
					else
						B.Queue(id, Message("n", ("%d;%s;%s"):format(mobId, level, B.Clean(mob.name, NAME_BYTES))))
					end
				end
			end
			B.QueueLatest(id, Message("f", frame), "O" .. VERSION .. ";f;", named)
		end
	end
end)

---------------------------------------------------------------------------
-- Receiving (from Beacon.lua's OnMessage: only noted here, the rest on the tick or when drawn)
---------------------------------------------------------------------------

function B.ReceiveStream(senderID, word, rest)
	local peer = B.peers[senderID]
	if not peer then
		return
	end
	local now = GetTime()
	if word == "h" then
		local can = rest == "1"
		if peer.streamable and not can and watching[senderID] then
			gone[senderID] = { why = "stopped", name = peer.name }
		end
		peer.streamable = can
	elseif word == "w" then
		if rest == "1" then
			if not Share() then
				return
			end
			local watcher = watchers[senderID]
			if not watcher then
				watchers[senderID] = { at = now, sentAt = -math.huge, names = {} }
				WatchersChanged()
			else
				watcher.at = now
			end
		elseif rest == "0" and watchers[senderID] then
			watchers[senderID] = nil
			WatchersChanged()
		end
	elseif word == "f" then
		if watching[senderID] then
			local stream = streams[senderID]
			if not stream then
				stream = { names = {}, count = 0 }
				streams[senderID] = stream
			end
			stream.payload, stream.at = rest, now
		elseif not stopSaid[senderID] or now - stopSaid[senderID] >= STOP_GAP then
			stopSaid[senderID] = now -- (they think I watch: after my /reload, say)
			B.Queue(senderID, Message("w", "0"))
		end
	elseif word == "n" or word == "u" then
		local stream = streams[senderID]
		local id, level, classFile, name
		if word == "u" then
			id, level, classFile, name = rest:match("^(%d+);(%-?%d*);(%u*);([^;]+)$")
		else
			id, level, name = rest:match("^(%d+);(%-?%d*);([^;]+)$")
		end
		if not (watching[senderID] and id) then
			return
		end
		if not stream then
			stream = { names = {}, count = 0 }
			streams[senderID] = stream
		end
		id = tonumber(id)
		if not stream.names[id] then
			if stream.count >= MAX_NAMES then
				wipe(stream.names) -- (a long session: start over; frames bring them again)
				stream.count = 0
			end
			stream.count = stream.count + 1
		end
		stream.names[id] = { name = B.Clean(name, NAME_BYTES), level = tonumber(level), classFile = classFile ~= "" and classFile or nil }
	end
end

-- With every answer to a friend's hello (and to everyone when the setting changes).
function B.StreamHello()
	return Message("h", Share() and "1" or "0")
end

-- A friend went offline or switched Beacon off (peer: what was known about them, or nil).
function B.StreamForget(id, peer)
	if watchers[id] then
		watchers[id] = nil
		WatchersChanged()
	end
	if watching[id] then
		gone[id] = { why = "away", name = peer and peer.name }
		Wake()
	end
end

---------------------------------------------------------------------------
-- Watching a friend
---------------------------------------------------------------------------

function S.FriendName(id)
	local peer = B.peers[id]
	return peer and peer.name or "?"
end

function S.CanWatch(id)
	local peer = B.peers[id]
	return M.enabled and peer ~= nil and peer.name ~= nil and peer.streamable == true
end
B.StreamCanWatch = S.CanWatch

-- Start or stop watching (StreamView.lua, as a window opens or closes).
function S.Watch(id, on)
	if on then
		watching[id] = { sentAt = GetTime() }
		streams[id] = nil
		gone[id] = nil
		B.Queue(id, Message("w", "1"))
	elseif watching[id] then
		watching[id] = nil
		streams[id] = nil
		if B.peers[id] then
			B.Queue(id, Message("w", "0"))
		end
	end
	Wake()
end

local POWER_TOKENS = { M = "MANA", R = "RAGE", E = "ENERGY", F = "FOCUS" }
local CLASS_FLAGS = { e = "elite", x = "rareelite", r = "rare" }

local function SpellName(id)
	local info = id and S.Value("C_Spell.GetSpellInfo", id)
	return type(info) == "table" and type(info.name) == "string" and info.name or nil
end

local function Fields(payload)
	local fields = {}
	for field in (payload .. ";"):gmatch("([^;]*);") do
		fields[#fields + 1] = field
	end
	return fields
end

-- A frame into a view's picture; false if it isn't one.
local function Decode(stream, picture)
	local f = Fields(stream.payload)
	if #f ~= 11 then
		return false
	end
	local at = stream.at
	picture.continent, picture.mapID = tonumber(f[1]), tonumber(f[2])
	picture.north, picture.west = tonumber(f[3]), tonumber(f[4])
	if not (picture.continent and picture.north and picture.west) then
		picture.continent, picture.north, picture.west = nil, nil, nil
	end
	picture.facing = math.rad(tonumber(f[5]) or 0)
	picture.combat = f[6]:find("c", 1, true) ~= nil
	picture.ghost = f[6]:find("g", 1, true) ~= nil
	picture.dead = picture.ghost or f[6]:find("d", 1, true) ~= nil
	local letter, percent = f[7]:match("^(%u)(%d+)$")
	if letter and POWER_TOKENS[letter] then
		picture.power = picture.power or {}
		picture.power.token, picture.power.frac = POWER_TOKENS[letter], math.min(100, tonumber(percent)) / 100
	else
		picture.power = nil
	end
	local formID = tonumber(f[8])
	local formInfo = formID and S.Value("C_Spell.GetSpellInfo", formID)
	if type(formInfo) == "table" and formInfo.iconID then
		picture.form = picture.form or {}
		picture.form.spellID, picture.form.icon, picture.form.name = formID, formInfo.iconID, formInfo.name
	else
		picture.form = nil
	end
	local castID, elapsed, total, channel = f[9]:match("^(%d+),(%d+),(%d+)(,?c?)$")
	local castInfo = castID and S.Value("C_Spell.GetSpellInfo", tonumber(castID))
	if type(castInfo) == "table" and castInfo.name then
		local cast = picture.friendCast or {}
		picture.friendCast = cast
		cast.name, cast.icon, cast.spellID, cast.channel = castInfo.name, castInfo.iconID, tonumber(castID), channel == ",c"
		cast.start = at - tonumber(elapsed) / 10
		cast.finish = cast.start + tonumber(total) / 10
		picture.cast = cast
	else
		picture.cast = nil
	end
	wipe(picture.recent)
	for spellID, age in f[10]:gmatch("(%d+),(%d+)") do
		if #picture.recent < 5 then
			S.AddRecent(picture.recent, tonumber(spellID), at - tonumber(age))
		end
	end
	table.sort(picture.recent, function(a, b) return a.at > b.at end) -- (newest first)
	local mobs = picture.mobs
	picture.pool = picture.pool or {}
	local n = 0
	for entry in f[11]:gmatch("[^/]+") do
		local id, deg, yards, sure, flags, cast = entry:match("^(%d+),(%d+),(%d*),(%d),(%l*),?(%d*)$")
		if id then
			n = n + 1
			local mob = picture.pool[n] or {}
			picture.pool[n] = mob
			id = tonumber(id)
			local name = stream.names[id]
			mob.key = id
			mob.name = name and name.name or "?"
			mob.level = name and name.level and name.level > 0 and name.level or nil
			mob.class = nil
			for flag, class in pairs(CLASS_FLAGS) do
				if flags:find(flag, 1, true) then
					mob.class = class
				end
			end
			mob.attacking = flags:find("a", 1, true) ~= nil
			mob.combat = flags:find("c", 1, true) ~= nil
			mob.target = flags:find("t", 1, true) ~= nil
			mob.dead = flags:find("d", 1, true) ~= nil
			mob.remembered = flags:find("m", 1, true) ~= nil
			mob.player = flags:find("p", 1, true) ~= nil
			mob.friendly = flags:find("f", 1, true) ~= nil
			mob.group = flags:find("g", 1, true) ~= nil
			mob.classFile = name and name.classFile
			mob.fade = mob.remembered and 0.6 or nil
			mob.age = nil
			mob.casting = flags:find("s", 1, true) and (SpellName(tonumber(cast)) or L["a spell"]) or nil
			mob.bearing = math.rad(tonumber(deg))
			mob.sure = tonumber(sure) / 9
			yards = tonumber(yards)
			if flags:find("b", 1, true) then
				mob.beyond, mob.yards = yards or 30, math.min((yards or 30) + 5, S.OUTER_YARDS)
			else
				mob.beyond, mob.yards = nil, yards and math.min(yards, S.OUTER_YARDS)
			end
			mob.exact = mob.group and yards or nil
			mobs[n] = mob
		end
	end
	for i = #mobs, n + 1, -1 do
		mobs[i] = nil
	end
	return true
end

-- The newest frame from a friend into the picture (only when there's a new one): whether it was
-- new, and how old it is (nil: none yet).
function S.ReadFriend(id, picture)
	local peer = B.peers[id]
	if peer then
		picture.name, picture.classFile, picture.level = peer.name, peer.classFile, peer.level
		local where = peer.subzone ~= "" and peer.subzone or peer.area
		picture.where = where
	end
	local stream = streams[id]
	if not (stream and stream.payload) then
		return false, nil
	end
	local fresh = stream.read ~= stream.at
	if fresh then
		stream.read = stream.at
		if not Decode(stream, picture) then
			fresh = false
		end
	end
	return fresh, GetTime() - stream.at
end

-- /lefthy stream watch <name>
function S.WatchByName(name)
	name = strtrim(name or ""):lower()
	if name == "" then
		M:Print("/lefthy stream watch <name> - whose fight? (or click their dot on the world map)")
		return
	end
	for id, peer in pairs(B.peers) do
		if peer.name and peer.name:lower() == name then
			if not S.CanWatch(id) then
				M:Print(("%s can't be watched: their LefthyTools is older, or they don't share their fights."):format(peer.name))
			else
				S.OpenFriend(id, "command")
			end
			return
		end
	end
	M:Print(("no friend called %s online with LefthyTools."):format(name))
end

-- /lefthy stream stop [<name>]
function S.StopWatching(name)
	name = strtrim(name or ""):lower()
	for id in pairs(watching) do
		local peer = B.peers[id]
		if name == "" or (peer and peer.name and peer.name:lower() == name) then
			S.CloseView(id)
		end
	end
end

-- Open or close a friend's stream; true if it's open now.
function B.StreamToggle(id, origin)
	if not S.CanWatch(id) and not S.IsWatching(id) then
		return false
	end
	return S.ToggleFriend(id, origin)
end

function B.StreamIsWatching(id)
	return S.IsWatching(id)
end

-- A flight starts: one friend's stream, the one with the most going on (in combat, with the most
-- mobs on them; else anyone who can be watched, picked at random).
function B.StreamFlightStart()
	if not (M.enabled and M.db.streamFlights) then
		return nil
	end
	local best, bestScore, any = nil, 0, {}
	for id, peer in pairs(B.peers) do
		if S.CanWatch(id) then
			any[#any + 1] = id
			local score = (peer.combat and not peer.dead and 10 or 0) + (peer.combat and peer.mobs or 0)
			if score > bestScore then
				best, bestScore = id, score
			end
		end
	end
	best = best or (#any > 0 and any[math.random(#any)]) or nil
	if best and not S.IsWatching(best) then
		S.OpenFriend(best, "flight")
	end
	return best
end

-- The flight is over: its streams close.
function B.StreamFlightEnd()
	S.CloseFlightViews()
end

---------------------------------------------------------------------------
-- The tick: keepalives, watchers gone quiet, friends who stopped sharing
---------------------------------------------------------------------------

local sinceTick = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
	sinceTick = sinceTick + elapsed
	if sinceTick < TICK then
		return
	end
	sinceTick = 0
	local now = GetTime()
	for id, left in pairs(gone) do
		gone[id] = nil
		if watching[id] then
			local name = left.name or "?" -- (taken when it happened: a friend gone is forgotten by now)
			S.CloseView(id)
			M:Print(left.why == "stopped" and ("%s stopped sharing their fights."):format(name)
				or ("%s went offline: their stream closed."):format(name))
		end
	end
	for id, w in pairs(watching) do
		if not B.peers[id] then
			S.CloseView(id)
		elseif now - w.sentAt >= KEEPALIVE then
			w.sentAt = now
			B.Queue(id, Message("w", "1"))
		end
	end
	local changed = false
	for id, watcher in pairs(watchers) do
		if now - watcher.at > WATCHER_TIMEOUT or not B.peers[id] then
			watchers[id] = nil
			changed = true
		end
	end
	if changed then
		WatchersChanged()
	end
	if not (next(watchers) or next(watching) or next(gone)) then
		self:Hide()
	end
end)

---------------------------------------------------------------------------
-- Settings, switching off
---------------------------------------------------------------------------

-- Beacon switched on: what friends were last told is what the setting says now.
local shared
function B.StreamStart()
	shared = M.db.streamShare and true or false
	C_Timer.After(0, function() S.UpdateButton() end) -- (StreamButton.lua: the minimap button)
end

-- A setting changed: friends hear whether they can watch me; not sharing any more drops my watchers.
function B.StreamSettingChanged()
	local share = M.db.streamShare and true or false
	if share ~= shared and M.enabled then
		B.QueueToPeers(B.StreamHello())
	end
	shared = share
	if not share and next(watchers) then
		wipe(watchers)
		WatchersChanged()
	end
	UpdateIndicator()
	S.UpdateButton()
end

-- Beacon switched off: every stream closes, nobody watches me any more.
function B.StreamStop()
	S.CloseAllViews()
	wipe(watching)
	wipe(watchers)
	wipe(streams)
	wipe(gone)
	S.SenseNeed("stream", false)
	UpdateIndicator()
	ticker:Hide()
	shared = nil
	S.UpdateButton()
end

-- For tests.
function S.Watchers()
	return watchers
end
