local _, ns = ...
local B = ns.Beacon
local S = B.Stream

-- What's around you, for the fight stream: one picture, looked at every LOOK_GAP while someone
-- needs it (your own window, a friend watching you), nothing otherwise.
--
-- S.Sensed() -> picture = {
--   me = true, looked (GetTime of the last look), name, classFile, level, where, north, west,
--   continent, mapID, facing (radians, counterclockwise from north), combat, dead, ghost,
--   power = { token, frac } or nil, form = { spellID, icon, name } or nil,
--   cast = { name, icon, spellID, start, finish (GetTime seconds), channel } or nil,
--   recent = { { name, icon, spellID, at }, ... } (newest first),
--   mobs = { { key, name, level, class, dead, combat, attacking, casting (a name), castID, target,
--            yards, beyond, sure (0-1), bearing (radians clockwise from north), remembered, fade,
--            age }, ... } }
--
-- Learning where the mobs are: the game gives addons no direction to a mob (nameplates can't be
-- measured), but every look says something, and that adds up. Each mob is a cloud of SPOTS
-- possible places in the world (kept by GUID); every look keeps only the places that fit what's
-- known now:
--   * how far it is: between the longest range it's beyond and the shortest it's within (with
--     SLACK: ranges count from the mob's edge);
--   * a mob with a nameplate is on your screen: within VIEW of where you face (the camera mostly
--     looks where your character faces); your target's nameplate says nothing (the game keeps it
--     up while it's behind you);
--   * your target without a nameplate, nearer than nameplates reach: outside that view;
--   * the soft target (gamepad mode: the enemy the game picks in front of you): within its arc;
--   * a spell you just cast at your target: in front; "Target needs to be in front of you": behind;
--   * a mob that left your screen (remembered REMEMBER seconds): outside the view.
-- Your own place and facing are exact, so walking and turning narrow the cloud down. Between looks
-- every place drifts a little (mobs move; one attacking you comes closer). When too few places fit
-- any more, the cloud starts over from what's known now. Its middle is the mob's direction; how
-- closely its places point one way is how sure.
--
-- Cost: nothing while nobody needs it. Then a look at up to 40 nameplate units every half second
-- (range checks, 48 places each), and the cast events of "player".

local Value, issecret = S.Value, S.issecret
local SPOTS = 48
local VIEW = math.rad(50)   -- the camera's view, either side of where you face, with some slack
local SOFT_ARCS = { [0] = math.rad(15), [1] = math.rad(35) } -- SoftTargetEnemyArc: 0 narrow, 1 front, 2 anywhere
local FRONT = math.rad(110) -- a spell you cast at it needs it in front (180 degrees), with slack
local HINT_TIME = 1.5       -- seconds a cast (or "not in front") still counts
local SLACK = 2             -- yards
local FAR = 60              -- yards: further than anything is looked at
local DRIFT = 1             -- yards a place may wander per look
local CHASE = 3             -- yards a mob attacking you comes closer per look, at most
local REMEMBER = 8          -- seconds a mob that left your screen stays, fading
local MIN_KEPT = 6          -- fewer places still fit: start over
local RECENT = 5            -- the last spells you cast
local POWER_LETTERS = { MANA = "M", RAGE = "R", ENERGY = "E", FOCUS = "F" }
local atan2 = math.atan2 or math.atan -- (Lua 5.1 / 5.3)

local picture = { me = true, mobs = {}, recent = {} }
local castNow, powerNow, formNow = {}, {}, {}
local checks                -- the range checks, read when the sensor starts
local plateReach = 40       -- nameplateMaxDistance
local soft                  -- the soft target's arc (nil: wide or off, tells nothing)
local pinned = 1            -- nameplateTargetRadialPosition (2: every mob's nameplate kept in combat)
local hint                  -- { side = "front" or "back", at }: from your own casts at your target
local clouds = {}           -- mob key -> { north = {}, west = {}, seenAt, info, ghost }
local looks = {}            -- reused mob tables, one per nameplate
local here = {}             -- this look: north, west, cos, sin (of your facing), facing, combat, now
local users = {}            -- who needs the sensor: "me" (your window), "stream" (friends watching)
local castUsers = {}        -- who needs your casts: the sensor's users and "test"
local listeners = {}        -- functions(picture), after every look (StreamNet.lua)
local ticker = CreateFrame("Frame")
local castWatch = CreateFrame("Frame")
local castDirty = false

function S.Sensed()
	return picture
end

function S.OnSensed(fn)
	listeners[#listeners + 1] = fn
end

---------------------------------------------------------------------------
-- Learning where the mobs are
---------------------------------------------------------------------------

-- A place in the world as seen from here, where you face up: x (right), y (ahead). The same turn as
-- the minimap's (Dots.lua, B.MinimapOffset).
local function Relative(north, west)
	local east, up = here.west - west, north - here.north
	return east * here.cos + up * here.sin, up * here.cos - east * here.sin
end

-- And back: x (right), y (ahead) from here, as a place in the world.
local function World(x, y)
	local east, up = x * here.cos - y * here.sin, x * here.sin + y * here.cos
	return here.north + up, here.west - east
end

-- Does a place (x, y from here) fit what's known: between lo and hi yards away, and on the side
-- ("view", "soft", "front", "back", "away" or nil: any)?
local function Fits(x, y, lo, hi, side)
	local d = math.sqrt(x * x + y * y)
	if d < lo or d > hi then
		return false
	elseif not (side and here.facing) then
		return true
	end
	local off = math.abs(atan2(x, y)) -- 0 straight ahead, pi behind
	if side == "soft" then
		return off <= soft
	elseif side == "view" then
		return off <= VIEW
	elseif side == "front" then
		return off <= FRONT
	elseif side == "back" then
		return off >= math.pi - FRONT
	end
	return off >= VIEW * 0.8 -- "away"
end

-- A new place that fits.
local function Seed(cloud, i, lo, hi, side)
	local d = lo + math.random() * (hi - lo)
	local a
	if side == "soft" then
		a = (math.random() * 2 - 1) * soft
	elseif side == "view" then
		a = (math.random() * 2 - 1) * VIEW
	elseif side == "front" then
		a = (math.random() * 2 - 1) * FRONT
	elseif side == "back" then
		a = math.pi + (math.random() * 2 - 1) * FRONT
	elseif side == "away" then
		a = VIEW + math.random() * (2 * math.pi - 2 * VIEW)
	else
		a = (math.random() * 2 - 1) * math.pi
	end
	cloud.north[i], cloud.west[i] = World(math.sin(a) * d, math.cos(a) * d)
end

-- One look: drift, keep what fits, refill from that (or start over).
local function Learn(cloud, lo, hi, side, chase)
	local north, west = cloud.north, cloud.west
	local kept = 0
	for i = 1, #north do
		local x, y = Relative(north[i] + (math.random() * 2 - 1) * DRIFT, west[i] + (math.random() * 2 - 1) * DRIFT)
		local d = math.sqrt(x * x + y * y)
		if chase and d > 4 then -- (attacking you: on its way)
			local step = math.min(CHASE, d - 3) / d
			x, y = x - x * step, y - y * step
		end
		if Fits(x, y, lo, hi, side) then
			kept = kept + 1
			north[kept], west[kept] = World(x, y)
		end
	end
	if kept < MIN_KEPT then
		for i = 1, SPOTS do
			Seed(cloud, i, lo, hi, side)
		end
		return
	end
	for i = kept + 1, SPOTS do
		local j = math.random(kept)
		north[i], west[i] = north[j] + (math.random() - 0.5), west[j] + (math.random() - 0.5)
	end
end

-- The cloud's middle: direction (radians, right of where you face), mean distance, and how sure,
-- 0 to 1: how closely its places point the same way (spread over the whole view, about 50 degrees
-- either side, is still unsure; within about 15 degrees, sure).
local function Estimate(cloud)
	local sx, sy, sd, n = 0, 0, 0, #cloud.north
	for i = 1, n do
		local x, y = Relative(cloud.north[i], cloud.west[i])
		local d = math.sqrt(x * x + y * y)
		if d > 0 then
			sx, sy = sx + x / d, sy + y / d
		end
		sd = sd + d
	end
	local together = math.sqrt(sx * sx + sy * sy) / n -- 1: all one way, 0: all around
	return atan2(sx, sy), sd / n, math.max(0, math.min(1, (together - 0.85) / 0.14))
end

-- What a mob's distance says: lo to hi yards.
local function Band(near, far, onScreen)
	local lo = far and math.max(0, far - SLACK) or 0
	local hi = near and near + SLACK or onScreen and plateReach + 5 or FAR
	if lo > hi then
		lo = math.max(0, hi - SLACK)
	end
	return lo, hi
end

-- This look's place and facing (no place, in an instance: learning goes by turning only).
local function Here()
	local ok, north, west, _, continent = pcall(UnitPosition, "player")
	if not ok or issecret(north) or issecret(west) or not north then
		north, west, continent = 0, 0, nil
	end
	local facing = Value("GetPlayerFacing")
	here.north, here.west, here.facing = north, west, facing
	here.combat, here.now = Value("UnitAffectingCombat", "player") == true, GetTime()
	here.cos, here.sin = math.cos(facing or 0), math.sin(facing or 0)
	return continent and not issecret(continent) and continent or nil
end

-- A mob seen now: its cloud learns, and it gets its direction and how sure that is.
local function LearnSeen(mob, now)
	local cloud = clouds[mob.key]
	if not cloud then
		cloud = { north = {}, west = {} }
		clouds[mob.key] = cloud
	end
	cloud.seenAt = now
	local lo, hi = Band(mob.near, mob.far, mob.onScreen)
	local plateSays = mob.onScreen and not mob.target and not (here.combat and mob.combat and pinned >= 2)
	local side
	if mob.target and hint and here.now - hint.at <= HINT_TIME then
		side = hint.side
	elseif mob.soft and soft then
		side = "soft"
	elseif plateSays then
		side = "view"
	elseif not mob.onScreen and mob.yards and not mob.beyond and mob.yards < plateReach then
		side = "away" -- (your target, without a nameplate though near: you turned away from it)
	end
	if #cloud.north == 0 then
		-- (a far target without a nameplate: most likely where you look; your target: anywhere)
		local seed = side or (not mob.onScreen and mob.beyond and "view") or nil
		for i = 1, SPOTS do
			Seed(cloud, i, lo, hi, seed)
		end
	end
	Learn(cloud, lo, hi, side, mob.attacking)
	local angle
	angle, mob.est, mob.sure = Estimate(cloud)
	mob.bearing = angle - (here.facing or 0) -- (north up: facing turns counterclockwise, angles go clockwise)
	local info = cloud.info or {} -- (its own copy: the look's tables are reused)
	cloud.info = info
	info.name, info.level, info.class, info.combat, info.attacking = mob.name, mob.level, mob.class, mob.combat, mob.attacking
	info.dead, info.est = mob.dead, mob.est
end

-- Mobs that left your screen (not dead): remembered a while, outside your view, fading. Appended
-- to the picture's mobs from n + 1; returns the new count.
local function Remember(mobs, n, now)
	for key, cloud in pairs(clouds) do
		if cloud.seenAt ~= now then
			local age = now - cloud.seenAt
			local info = cloud.info
			if age > REMEMBER or info.dead or n >= S.MAX_MOBS then
				clouds[key] = nil
			else
				Learn(cloud, 0, FAR, info.est and info.est < plateReach - 3 and "away" or nil, false)
				local ghost = cloud.ghost or {}
				cloud.ghost = ghost
				ghost.key, ghost.name, ghost.level, ghost.class = key, info.name, info.level, info.class
				ghost.combat, ghost.attacking, ghost.target, ghost.casting, ghost.castID, ghost.dead =
					info.combat, info.attacking, false, nil, nil, false
				local angle
				angle, ghost.est, ghost.sure = Estimate(cloud)
				ghost.bearing = angle - (here.facing or 0)
				ghost.yards, ghost.beyond, ghost.remembered, ghost.age = ghost.est, nil, true, age
				ghost.fade = 1 - age / REMEMBER
				n = n + 1
				mobs[n] = ghost
			end
		end
	end
	return n
end

---------------------------------------------------------------------------
-- What you're doing: your cast, your last spells, power, form
---------------------------------------------------------------------------

-- The spell being cast or channelled now (none, or hidden by the game: nil).
local function ReadCast()
	picture.cast, castDirty = nil, false
	for _, path in ipairs({ "UnitCastingInfo", "UnitChannelInfo" }) do
		local f = S.Api(path)
		local ok, name, _, icon, startMs, endMs, a, b, c, d
		if f then
			ok, name, _, icon, startMs, endMs, a, b, c, d = pcall(f, "player")
		end
		if ok and name and startMs and endMs and not (issecret(name) or issecret(icon) or issecret(startMs) or issecret(endMs)) then
			local channel = path == "UnitChannelInfo"
			local spellID = channel and c or d -- (UnitCastingInfo: 9th, UnitChannelInfo: 8th)
			castNow.name, castNow.icon, castNow.start, castNow.finish = name, icon, startMs / 1000, endMs / 1000
			castNow.channel, castNow.spellID = channel, not issecret(spellID) and spellID or nil
			picture.cast = castNow
			return
		end
	end
end
S.ReadCast = ReadCast

-- A spell cast: in front of the recent ones (list: the picture's, or a preview's).
function S.AddRecent(list, spellID, at)
	local info = Value("C_Spell.GetSpellInfo", spellID)
	if type(info) ~= "table" or not info.name or issecret(info.name) or issecret(info.iconID) then
		return
	end
	local entry = #list >= RECENT and table.remove(list) or {}
	entry.name, entry.icon, entry.spellID, entry.at = info.name, info.iconID, spellID, at or GetTime()
	table.insert(list, 1, entry)
end

local function ReadPower()
	local ok, kind, token = pcall(UnitPowerType, "player")
	local cur, max = Value("UnitPower", "player"), Value("UnitPowerMax", "player")
	if ok and token and not issecret(token) and POWER_LETTERS[token] and cur and max and max > 0 then
		powerNow.token, powerNow.frac = token, math.max(0, math.min(1, cur / max))
		picture.power = powerNow
	else
		picture.power = nil
	end
end
S.POWER_LETTERS = POWER_LETTERS

local function ReadForm()
	local index = Value("GetShapeshiftForm")
	local spellID = index and index > 0 and select(4, pcall(GetShapeshiftFormInfo, index))
	picture.form = nil
	if spellID and not issecret(spellID) then
		local info = Value("C_Spell.GetSpellInfo", spellID)
		if type(info) == "table" and info.name and not issecret(info.name) then
			formNow.spellID, formNow.icon, formNow.name = spellID, info.iconID, info.name
			picture.form = formNow
		end
	end
end

-- Your own casts at your target tell where it is: a harmful spell that went off needed it in front
-- of you; "Target needs to be in front of you" (or facing the wrong way) means it's behind. The
-- test notes what came (to see that these events answer, and the errors' exact words).
castWatch:SetScript("OnEvent", function(_, event, a, b, c)
	local side
	if event ~= "UNIT_SPELLCAST_SUCCEEDED" and event ~= "UI_ERROR_MESSAGE" then
		castDirty = castDirty or a == "player" -- (a cast started or stopped: read on the next frame)
		if castDirty and next(users) then
			ticker:Show()
		end
		return
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then -- unit, castGUID, spellID
		if a ~= "player" then
			return
		end
		if next(users) and not issecret(c) and c then
			S.AddRecent(picture.recent, c)
		end
		local harmful = not issecret(c) and c and Value("C_Spell.IsSpellHarmful", c)
		if harmful and Value("UnitExists", "target") and Value("UnitCanAttack", "player", "target") then
			side = "front"
		end
		S.TestNote("your casts: UNIT_SPELLCAST_SUCCEEDED (true: harmful, at a hostile target)",
			issecret(c) and "hidden" or tostring(side == "front"), not issecret(c) and c and Value("C_Spell.GetSpellName", c) or nil)
	else -- UI_ERROR_MESSAGE: errorType, message
		if not issecret(b) and b and (b == SPELL_FAILED_UNIT_NOT_INFRONT or b == ERR_BADATTACKFACING) then
			side = "back"
		end
		S.TestNote("the game's error messages: UI_ERROR_MESSAGE (true: not in front)",
			issecret(b) and "hidden" or tostring(side == "back"), not issecret(b) and b or nil)
	end
	if side then
		hint = hint or {}
		hint.side, hint.at = side, GetTime()
	end
end)

local CAST_EVENTS = { "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
	"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" }

-- Your casts are listened to while the sensor runs or a test does.
function S.SenseCasts(who, on)
	castUsers[who] = on or nil
	castWatch:UnregisterAllEvents()
	if next(castUsers) or next(users) then
		for _, event in ipairs(CAST_EVENTS) do
			castWatch:RegisterUnitEvent(event, "player")
		end
		castWatch:RegisterEvent("UI_ERROR_MESSAGE")
	end
end

---------------------------------------------------------------------------
-- A look
---------------------------------------------------------------------------

local function Fill(n, unit, unitTarget, targetKey, onScreen, now)
	local mob = looks[n] or {}
	looks[n] = mob
	mob.key = Value("UnitGUID", unit) or unit
	mob.name = Value("UnitName", unit) or "?"
	mob.level = Value("UnitLevel", unit)
	mob.class = Value("UnitClassification", unit)
	mob.dead = Value("UnitIsDead", unit) == true
	mob.combat = Value("UnitAffectingCombat", unit) == true
	mob.attacking = Value("UnitIsUnit", unitTarget, "player") == true
	local ok, castName, _, _, _, _, _, _, _, castID = pcall(UnitCastingInfo, unit)
	if not ok or issecret(castName) or not castName then
		local okChannel, channelName, _, _, _, _, _, _, channelID = pcall(UnitChannelInfo, unit)
		castName, castID = okChannel and not issecret(channelName) and channelName or nil, channelID
	end
	mob.casting, mob.castID = castName, castName and not issecret(castID) and castID or nil
	mob.near, mob.far = S.Bounds(unit, checks)
	mob.yards, mob.beyond = S.YardsFrom(mob.near, mob.far)
	mob.onScreen, mob.soft = onScreen, Value("UnitIsUnit", unit, "softenemy") == true
	mob.target = targetKey ~= nil and mob.key == targetKey
	mob.remembered, mob.fade, mob.age = nil, nil, nil
	LearnSeen(mob, now)
	picture.mobs[n] = mob
	return mob.target
end

local function Look()
	local now = GetTime()
	picture.continent = Here()
	picture.north, picture.west, picture.facing, picture.combat = here.north, here.west, here.facing or 0, here.combat
	picture.mapID = Value("C_Map.GetBestMapForUnit", "player")
	picture.name = UnitName("player")
	local _, classFile = UnitClass("player")
	picture.classFile, picture.level = classFile, UnitLevel("player")
	local sub = GetSubZoneText()
	picture.where = sub ~= "" and sub or GetRealZoneText()
	picture.dead = Value("UnitIsDeadOrGhost", "player") == true
	picture.ghost = Value("UnitIsGhost", "player") == true
	local n, targetShown = 0, false
	local targetKey = Value("UnitExists", "target") and Value("UnitCanAttack", "player", "target")
		and (Value("UnitGUID", "target") or "target") or nil
	for i = 1, S.MAX_UNITS do
		local unit = S.UNITS[i]
		if n < S.MAX_MOBS and Value("UnitExists", unit) and Value("UnitCanAttack", "player", unit) then
			n = n + 1
			targetShown = Fill(n, unit, S.TARGETS[i], targetKey, true, now) or targetShown
		end
	end
	if targetKey and not targetShown and n < S.MAX_MOBS then
		n = n + 1
		Fill(n, "target", "targettarget", targetKey, false, now)
	end
	n = Remember(picture.mobs, n, now)
	for i = #picture.mobs, n + 1, -1 do
		picture.mobs[i] = nil
	end
	ReadCast()
	ReadPower()
	ReadForm()
	picture.looked = now -- (your window redraws when this changes)
	for _, listener in ipairs(listeners) do
		local ok, err = pcall(listener, picture)
		if not ok then
			geterrorhandler()(err)
		end
	end
end

local nextLook = 0
ticker:Hide()
ticker:SetScript("OnUpdate", function(self)
	local now = GetTime()
	if not next(users) then
		self:Hide()
		return
	end
	if now >= nextLook then
		nextLook = now + S.LOOK_GAP
		Look()
	elseif castDirty then
		ReadCast() -- (a cast just started or stopped)
	end
end)

-- Who needs the sensor: "me" (your window), "stream" (friends watching you). The first one starts
-- it fresh, the last one stops it.
function S.SenseNeed(who, on)
	local wasRunning = next(users) ~= nil
	users[who] = on or nil
	local running = next(users) ~= nil
	if running and not wasRunning then
		checks, plateReach = S.RangeChecks(), tonumber(GetCVar("nameplateMaxDistance")) or 40
		soft = GetCVar("SoftTargetEnemy") == "1" and SOFT_ARCS[tonumber(GetCVar("SoftTargetEnemyArc"))] or nil
		pinned, hint = tonumber(GetCVar("nameplateTargetRadialPosition")) or 1, nil
		wipe(clouds)
		wipe(picture.recent)
		wipe(picture.mobs)
		picture.cast = nil
		nextLook = 0
		ticker:Show()
	elseif not running and wasRunning then
		ticker:Hide()
		wipe(clouds)
	end
	S.SenseCasts("sensor", running)
	if running then
		ticker:Show()
	end
end

function S.SenseRunning()
	return next(users) ~= nil
end

