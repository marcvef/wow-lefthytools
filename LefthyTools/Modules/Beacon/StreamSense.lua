local _, ns = ...
local LT = ns.LT
local L = ns.L
local B = ns.Beacon
local S = B.Stream

-- What's around you, for the fight stream: one picture, looked at every LOOK_GAP while someone
-- needs it (your own window, a friend watching you), nothing otherwise.
--
-- S.Sensed() -> picture = {
--   me = true, looked (GetTime of the last look), name, classFile, level, where, north, west,
--   continent, mapID, facing (radians, counterclockwise from north), combat, dead, ghost,
--   health (0-1, estimated: "Your health, estimated" below; nil while unknown), healthWhy (then:
--   "max" or "wait", S.HealthWhy),
--   power = { token, frac } or nil, form = { spellID, icon, name } or nil,
--   cast = { name, icon, spellID, start, finish (GetTime seconds), channel } or nil,
--   recent = { { name, icon, spellID, at }, ... } (newest first),
--   moments = { what just happened to you: "What happens to you" below } (newest first),
--   mobs = { { key, name, level, class, dead, combat, attacking, casting (a name), castID (its spell
--            ID), target, yards, beyond, sure (0-1), bearing (radians clockwise from north),
--            remembered, fade, age, unit (at the look), creature (its ID), health (0-1, estimated;
--            nil: unknown), player, classFile, friendly, group (a player in your group: placed
--            exactly, exact = how many yards away),
--            engaged (fighting you: you're on its threat list, or it attacks you), aggro (in a
--            group, who has its aggro: their role, "TANK", "HEALER", "DAMAGER", "NONE", "PET" or
--            "OUTSIDER"; nil: not known), aggroName, aggroSelf (it's you) },
--            ... } }
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
-- (range checks, 48 places each; in a group, who has aggro on the five you fight first), the cast
-- events of "player" and (a word each) of mobs, XP, kills and loot; the mobs' health
-- (StreamHealth.lua). Apart from that, your health is estimated while Beacon is on (a handful of
-- your own events; StreamHealth.lua).

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

local picture = { me = true, mobs = {}, recent = {}, moments = {} }
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
	if not ok or issecret(north) or issecret(west) or issecret(continent) or not north then
		north, west, continent = 0, 0, nil
	end
	local facing = Value("GetPlayerFacing")
	here.north, here.west, here.facing = north, west, facing
	here.combat, here.now = Value("UnitAffectingCombat", "player") == true, GetTime()
	here.cos, here.sin = math.cos(facing or 0), math.sin(facing or 0)
	return continent -- (nil in an instance; secret ones were dropped above)
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
	info.player, info.classFile, info.friendly = mob.player, mob.classFile, mob.friendly
	info.creature, info.health, info.engaged = mob.creature, mob.health, mob.engaged
	info.aggro, info.aggroName, info.aggroSelf = mob.aggro, mob.aggroName, mob.aggroSelf -- (set after the look: Holders)
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
				ghost.player, ghost.classFile, ghost.friendly, ghost.group = info.player, info.classFile, info.friendly, false
				ghost.combat, ghost.attacking, ghost.target, ghost.casting, ghost.castID, ghost.dead =
					info.combat, info.attacking, false, nil, nil, false
				ghost.unit, ghost.creature, ghost.health, ghost.engaged = nil, info.creature, info.health, info.engaged
				ghost.aggro, ghost.aggroName, ghost.aggroSelf = info.aggro, info.aggroName, info.aggroSelf -- (as last seen)
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
		-- (Secret first: a hidden value mustn't be tested as true or false.)
		if ok and not (issecret(name) or issecret(icon) or issecret(startMs) or issecret(endMs)) and name and startMs and endMs then
			local channel = path == "UnitChannelInfo"
			local spellID -- (UnitCastingInfo: 9th, UnitChannelInfo: 8th)
			if channel then
				spellID = c
			else
				spellID = d
			end
			castNow.name, castNow.icon, castNow.start, castNow.finish = name, icon, startMs / 1000, endMs / 1000
			castNow.channel, castNow.spellID = channel, not issecret(spellID) and spellID or nil
			picture.cast = castNow
			return
		end
	end
end

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
	if ok and not issecret(token) and token and POWER_LETTERS[token] and cur and max and max > 0 then
		powerNow.token, powerNow.frac = token, math.max(0, math.min(1, cur / max))
		picture.power = powerNow
	else
		picture.power = nil
	end
end
S.POWER_LETTERS = POWER_LETTERS

local function ReadForm()
	local index = Value("GetShapeshiftForm")
	-- (pcall's first return is ok: icon, active, castable, spellID come after it, so the spell is 5th)
	local spellID = index and index > 0 and select(5, pcall(GetShapeshiftFormInfo, index))
	picture.form = nil
	if not issecret(spellID) and type(spellID) == "number" then
		local info = Value("C_Spell.GetSpellInfo", spellID)
		if type(info) == "table" and info.name and not issecret(info.name) then
			formNow.spellID, formNow.icon, formNow.name = spellID, info.iconID, info.name
			picture.form = formNow
		end
	end
end

---------------------------------------------------------------------------
-- What happens to you, for whoever watches
---------------------------------------------------------------------------

-- Moments (picture.moments, newest first): hits and heals (UNIT_COMBAT, added up per look; big:
-- BIG of your maximum or more), what you avoided (a miss, dodge, parry, ...), XP (with the mob it
-- came from, if it died just then), your killing blows (PARTY_KILL), loot (green and better).
-- Each gets a number (1-99, going round) and stays MOMENT_KEEP seconds: a friend's frames carry
-- the recent ones (a frame replaced in the queue loses none), and the windows show each number
-- once. Only while the sensor runs.
--   { seq, kind ("hurt", "heal", "avoid", "xp", "kill", "loot"), at, amount, big, avoid (MISS,
--     DODGE, ...), key (the mob's: XP from a kill, a killing blow), item, quality }

local MOMENT_KEEP = 2.5
local BIG = 0.15
local XP_FROM_KILL = 1.5   -- seconds: XP this close to a kill came from it
-- What UNIT_COMBAT says when nothing got through (and its letter in a friend's frame).
S.AVOIDED = { MISS = "m", DODGE = "d", PARRY = "p", BLOCK = "b", RESIST = "r", IMMUNE = "i", EVADE = "e",
	DEFLECT = "f", REFLECT = "x", ABSORB = "a" }

local pending = { hurt = 0, heal = 0 } -- since the last look (and avoid: the last word)
local seq = 0
local lastKill = { at = -math.huge }
local xpWas = {}
local momentWatch = CreateFrame("Frame")

local function Moment(kind)
	seq = seq % 99 + 1
	local moment = { seq = seq, kind = kind, at = GetTime() }
	table.insert(picture.moments, 1, moment)
	return moment
end

-- A UNIT_COMBAT on you (from the health estimate's events).
function S.Happened(kind, flags, amount)
	if issecret(kind) or issecret(flags) or issecret(amount) then
		return
	end
	if (kind == "WOUND" or kind == "HEAL") and type(amount) == "number" and amount > 0 then
		local field = kind == "WOUND" and "hurt" or "heal"
		pending[field] = pending[field] + amount
	elseif kind == "WOUND" then -- (nothing got through: absorbed, blocked, resisted, else missed)
		pending.avoid = S.AVOIDED[flags] and flags or "MISS"
	elseif S.AVOIDED[kind] then
		pending.avoid = kind
	end
end

-- Every look: what came since becomes moments; old ones go.
local function Flush(now)
	local max = S.HealthMax()
	for _, field in ipairs({ "hurt", "heal" }) do
		local amount = pending[field]
		if amount > 0 then
			local moment = Moment(field)
			moment.amount, moment.big = amount, max ~= nil and amount >= BIG * max
			pending[field] = 0
		end
	end
	if pending.avoid then
		Moment("avoid").avoid = pending.avoid
		pending.avoid = nil
	end
	local moments = picture.moments
	while moments[1] and now - moments[#moments].at > MOMENT_KEEP do
		moments[#moments] = nil
	end
end

local function ReadXP()
	local xp, max, level = Value("UnitXP", "player"), Value("UnitXPMax", "player"), Value("UnitLevel", "player")
	if type(xp) ~= "number" or type(max) ~= "number" then
		return nil
	end
	local gained = xpWas.xp and (level == xpWas.level and xp - xpWas.xp or (xpWas.max - xpWas.xp) + xp)
	xpWas.xp, xpWas.max, xpWas.level = xp, max, level
	return gained
end

momentWatch:SetScript("OnEvent", function(_, event, a, b)
	local now = GetTime()
	if event == "PLAYER_XP_UPDATE" then
		local gained = ReadXP()
		if gained and gained > 0 then
			local moment = Moment("xp")
			moment.amount = gained
			if now - lastKill.at <= XP_FROM_KILL then
				moment.key = lastKill.key
			end
		end
	elseif event == "PARTY_KILL" then -- attackerGUID, targetGUID (yours or your group's)
		if issecret(a) or issecret(b) or type(b) ~= "string" then
			return
		end
		lastKill.key, lastKill.at = b, now
		S.MobDied(b) -- (its kind's maximum learns, if its whole fight was seen)
		for _, moment in ipairs(picture.moments) do
			if moment.kind == "xp" and not moment.key and now - moment.at <= XP_FROM_KILL then
				moment.key = b -- (the XP came first)
			end
		end
		if a == Value("UnitGUID", "player") then
			Moment("kill").key = b
		end
	elseif event == "CHAT_MSG_LOOT" then
		local _, itemID, _, quality = LT.OwnLoot(a)
		if itemID and quality and quality >= 2 then
			local moment = Moment("loot")
			moment.item, moment.quality = itemID, quality
		end
	end
end)

-- Listened to while the sensor runs.
local function SenseMoments(on)
	momentWatch:UnregisterAllEvents()
	wipe(picture.moments)
	pending.hurt, pending.heal, pending.avoid = 0, 0, nil
	if on then
		for _, event in ipairs({ "PLAYER_XP_UPDATE", "PARTY_KILL", "CHAT_MSG_LOOT" }) do
			momentWatch:RegisterEvent(event)
		end
		xpWas.xp = nil
		ReadXP()
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

-- Mobs casting: the game hides what a mob casts (UnitCastingInfo: name, times, whether it can be
-- interrupted, all secret on Forever), but not that it began or ended: the cast events of
-- nameplates and your target, without their spells. Kept per mob while the sensor runs; a cast
-- not seen to end is over after CAST_LONGEST.
local CAST_LONGEST = 10
local MOB_CAST_EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_STOP",
	"UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED" }
local CAST_BEGINS = { UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_CHANNEL_START = true }
local castingSince = {} -- mob key -> when its cast began
local mobCasts = CreateFrame("Frame")

mobCasts:SetScript("OnEvent", function(_, event, unit)
	if type(unit) ~= "string" or issecret(unit) or (unit ~= "target" and unit:sub(1, 9) ~= "nameplate") then
		return
	end
	local key = Value("UnitGUID", unit) or unit -- (as a look keys it)
	castingSince[key] = CAST_BEGINS[event] and GetTime() or nil
end)

local function SenseMobCasts(on)
	mobCasts:UnregisterAllEvents()
	wipe(castingSince)
	if on then
		for _, event in ipairs(MOB_CAST_EVENTS) do
			mobCasts:RegisterEvent(event)
		end
	end
end

-- Casts not seen to end (the nameplate went first) are forgotten, now and then.
local function ForgetCasts(now)
	for key, began in pairs(castingSince) do
		if now - began > CAST_LONGEST then
			castingSince[key] = nil
		end
	end
end

-- The mobs fought (in your picture or a friend's): not dead, not players, fighting them (on whose
-- threat list they are, or attacking them) or their target; the target first, then the ones
-- attacking, then the nearest. Not every mob in combat: those may fight someone else. Into list,
-- at most max.
local function FoeFirst(a, b)
	local at, bt = a.target and true or false, b.target and true or false
	if at ~= bt then
		return at
	end
	local aa, ba = a.attacking and true or false, b.attacking and true or false
	if aa ~= ba then
		return aa
	end
	return (a.yards or 999) < (b.yards or 999)
end

function S.Foes(mobs, list, max)
	wipe(list)
	for _, mob in ipairs(mobs) do
		if not mob.dead and not mob.player and not mob.friendly and (mob.target or mob.engaged) then
			list[#list + 1] = mob
		end
	end
	table.sort(list, FoeFirst)
	for i = #list, max + 1, -1 do
		list[i] = nil
	end
	return list
end

-- Who has aggro on the mobs you fight, in a group: Misc Tweaks' reading for the nameplates
-- (Aggro.lua: the mob's target and the group's threat, the holder's role), also with that tweak off.
-- At the look, for the first AGGRO_FOES of them only (the battle row shows four, friends get five):
-- a few calls each. A mob that left your screen keeps what was last known.
local AGGRO_FOES = 5
local aggroList = {}
local function Holders(mobs)
	if not (ns.AggroHolder and IsInGroup and IsInGroup()) then
		return
	end
	for _, mob in ipairs(S.Foes(mobs, aggroList, AGGRO_FOES)) do
		if mob.unit and mob.combat then
			mob.aggro, mob.aggroName, mob.aggroSelf = ns.AggroHolder(mob.unit)
			local info = clouds[mob.key] and clouds[mob.key].info
			if info then
				info.aggro, info.aggroName, info.aggroSelf = mob.aggro, mob.aggroName, mob.aggroSelf
			end
		end
	end
end

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

-- A player's class file (nil: not a player, or hidden).
local function ClassOf(unit)
	local ok, _, classFile = pcall(UnitClass, unit)
	return ok and type(classFile) == "string" and not issecret(classFile) and classFile or nil
end

-- My group's members: their place is known exactly (UnitPosition answers for group members), so
-- they need no learning: the nearest MAX_GROUP within GROUP_FAR yards (further than the outer ring:
-- on its rim). Appended to the picture's mobs from n + 1; returns the new count. inGroup: their
-- GUIDs, so their nameplates aren't counted again.
local MAX_GROUP, GROUP_FAR, MAX_FRIENDLY = 8, 120, 6
local groupLooks, inGroup, nearby, nearbyPool = {}, {}, {}, {}

local function Group(n)
	wipe(inGroup)
	wipe(nearby)
	local continent = picture.continent
	if not continent then
		return n -- (no place of mine: in an instance, positions are hidden anyway)
	end
	local raid = IsInRaid and IsInRaid()
	for i = 1, raid and 40 or 4 do
		local unit = (raid and "raid" or "party") .. i
		if Value("UnitExists", unit) and not Value("UnitIsUnit", unit, "player") then
			local key = Value("UnitGUID", unit) or unit
			inGroup[key] = true
			local ok, north, west, _, instance = pcall(UnitPosition, unit)
			if ok and not (issecret(north) or issecret(west) or issecret(instance)) and north and west and instance == continent then
				local dNorth, dEast = north - here.north, here.west - west
				local yards = math.sqrt(dNorth * dNorth + dEast * dEast)
				if yards <= GROUP_FAR then
					local found = nearbyPool[#nearby + 1] or {}
					nearbyPool[#nearby + 1] = found
					found.unit, found.key, found.yards, found.bearing = unit, key, yards, atan2(dEast, dNorth)
					nearby[#nearby + 1] = found
				end
			end
		end
	end
	table.sort(nearby, function(a, b) return a.yards < b.yards end)
	for i = 1, math.min(#nearby, MAX_GROUP) do
		local found = nearby[i]
		local unit = found.unit
		local mob = groupLooks[i] or {}
		groupLooks[i] = mob
		mob.key, mob.name, mob.level = found.key, Value("UnitName", unit) or "?", Value("UnitLevel", unit)
		mob.class, mob.player, mob.classFile, mob.friendly, mob.group = nil, true, ClassOf(unit), true, true
		mob.dead = Value("UnitIsDeadOrGhost", unit) == true
		mob.combat = Value("UnitAffectingCombat", unit) == true
		mob.attacking, mob.target, mob.soft, mob.onScreen = false, false, false, nil
		mob.unit, mob.creature, mob.health, mob.engaged = unit, nil, nil, false
		local ok, castName, _, _, _, _, _, _, _, castID = pcall(UnitCastingInfo, unit)
		mob.casting = ok and not issecret(castName) and castName or nil
		mob.castID = mob.casting and not issecret(castID) and castID or nil
		mob.yards, mob.exact = math.min(found.yards, S.OUTER_YARDS), math.floor(found.yards + 0.5)
		mob.beyond = found.yards > S.OUTER_YARDS and mob.exact or nil
		mob.sure, mob.bearing = 1, found.bearing
		mob.remembered, mob.fade, mob.age = nil, nil, nil
		n = n + 1
		picture.mobs[n] = mob
	end
	return n
end

-- friendly: a player with a friendly nameplate (not in my group: those come exactly, above).
local function Fill(n, unit, unitTarget, targetKey, onScreen, now, friendly)
	local mob = looks[n] or {}
	looks[n] = mob
	mob.key = Value("UnitGUID", unit) or unit
	mob.name = Value("UnitName", unit) or "?"
	mob.level = Value("UnitLevel", unit)
	mob.class = Value("UnitClassification", unit)
	mob.player = Value("UnitIsPlayer", unit) == true
	mob.classFile = mob.player and ClassOf(unit) or nil
	mob.friendly, mob.group = friendly or false, false
	mob.dead = Value("UnitIsDead", unit) == true
	mob.combat = Value("UnitAffectingCombat", unit) == true
	mob.attacking = not friendly and Value("UnitIsUnit", unitTarget, "player") == true
	mob.exact = nil
	mob.unit = unit -- (your window: its real health, its model)
	mob.creature = not mob.player and S.CreatureOf(mob.key) or nil
	mob.health = not mob.player and S.MobHealth(mob, now) or nil -- (StreamHealth.lua)
	-- Fighting you: you're on its threat list (hidden where the game restricts it), or it attacks you.
	mob.engaged = not friendly and (type(Value("UnitThreatSituation", "player", unit)) == "number" or mob.attacking) or false
	mob.aggro, mob.aggroName, mob.aggroSelf = nil, nil, nil -- (read after the look, for the mobs fought: Holders)
	local ok, castName, _, _, _, _, _, _, _, castID = pcall(UnitCastingInfo, unit)
	if not ok or issecret(castName) or not castName then
		local okChannel, channelName, _, _, _, _, _, _, channelID = pcall(UnitChannelInfo, unit)
		castName, castID = okChannel and not issecret(channelName) and channelName or nil, channelID
	end
	mob.casting, mob.castID = castName, castName and not issecret(castID) and castID or nil
	local began = not castName and castingSince[mob.key]
	if began and now - began <= CAST_LONGEST then
		mob.casting = L["a spell"] -- (what it is, the game hides)
	end
	mob.near, mob.far = S.Bounds(unit, checks)
	mob.yards, mob.beyond = S.YardsFrom(mob.near, mob.far)
	mob.onScreen, mob.soft = onScreen, Value("UnitIsUnit", unit, "softenemy") == true
	mob.target = targetKey ~= nil and mob.key == targetKey
	mob.remembered, mob.fade, mob.age = nil, nil, nil
	LearnSeen(mob, now)
	picture.mobs[n] = mob
	return mob.target
end

local forgotAt = 0
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
	n = Group(n)
	local players = 0
	for i = 1, S.MAX_UNITS do
		local unit = S.UNITS[i]
		if n < S.MAX_MOBS and Value("UnitExists", unit) then
			if Value("UnitCanAttack", "player", unit) then
				n = n + 1
				targetShown = Fill(n, unit, S.TARGETS[i], targetKey, true, now) or targetShown
			elseif players < MAX_FRIENDLY and Value("UnitIsPlayer", unit) and not inGroup[Value("UnitGUID", unit) or ""] then
				-- Another player with a friendly nameplate: learned like a mob.
				n, players = n + 1, players + 1
				Fill(n, unit, S.TARGETS[i], nil, true, now, true)
			end
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
	Holders(picture.mobs)
	ReadCast()
	ReadPower()
	ReadForm()
	picture.health = S.Health()
	picture.healthWhy = not picture.health and S.HealthWhy() or nil
	Flush(now)
	if now - forgotAt >= 30 then
		forgotAt = now
		S.ForgetMobHealth(now)
		ForgetCasts(now)
	end
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
		SenseMoments(true)
		SenseMobCasts(true)
		S.SenseMobHealth(true)
		if ns.AggroWatch then
			ns.AggroWatch(true) -- (Aggro.lua: the group's roster kept fresh, for who has aggro)
		end
		ticker:Show()
	elseif not running and wasRunning then
		ticker:Hide()
		wipe(clouds)
		SenseMoments(false)
		SenseMobCasts(false)
		S.SenseMobHealth(false)
		if ns.AggroWatch then
			ns.AggroWatch(false)
		end
	end
	S.SenseCasts("sensor", running)
	if running then
		ticker:Show()
	end
end

function S.SenseRunning()
	return next(users) ~= nil
end

-- For tests: the sensor's books on mobs, and the pass that forgets what's stale in them (now: as if
-- it were then).
function S.MobBooks()
	local lost, hits = S.MobHealthBooks()
	return { lost = lost, hitAt = hits, casting = castingSince }, function(now)
		S.ForgetMobHealth(now)
		ForgetCasts(now)
	end
end

