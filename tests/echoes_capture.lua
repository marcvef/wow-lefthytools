-- Echoes' capture (Path.lua, Events.lua, Changes.lua): a session starting, the path's store rule,
-- every travel mode, segments and what caused them, instances; every event kind as its exact line;
-- secret values skipped, nothing in combat that must wait, a /reload, recording with Chronicle, the
-- Bestiary and Beacon off, the beta not recording; a whole session read back by the format's rules.
-- Needs: no other file (it switches Echoes on and off itself, and puts back the mock's world it changes).
local suite = ...
local check, section, ns, LT = suite.check, suite.section, suite.ns, suite.LT
local afk, anna, catchErrors = suite.afk, suite.anna, suite.catchErrors
local E = ns.Echoes
local C = E.capture

---------------------------------------------------------------------------
-- The capture's own mock: what the game answers that mock.lua doesn't have (put back at the end)
---------------------------------------------------------------------------

local was = {} -- global -> what it was (false: nothing)
local function mock(name, value)
	if was[name] == nil then
		was[name] = _G[name]
		if was[name] == nil then
			was[name] = false
		end
	end
	_G[name] = value
end
-- Knobs: my speed as the game tells it (GetUnitSpeed; nil: 7 yd/s walking, 14 mounted, 0 standing), my form (GetShapeshiftFormID), the group's
-- size, the hearthstone's place, honorable kills, who won a battleground, my pet, /played's answer,
-- quests done, factions, professions, worn items' links.
UNIT_SPEED, FORM_ID, GROUP_MEMBERS, BIND, HONOR, BG_WINNER, PET_GUID = nil, nil, 0, nil, 0, nil, nil
PLAYED, QUESTS_DONE, FACTIONS, SKILLS, GEAR_LINKS = { total = 7200, requests = 0 }, {}, {}, {}, {}
mock("GetUnitSpeed", function(unit)
	if unit == "player" then return UNIT_SPEED or (STATE.moving and (TRAVEL.mounted and 14 or 7) or 0), 7, 7, 4.72 end
end)
mock("GetShapeshiftFormID", function() return FORM_ID end)
mock("IsResting", function() return STATE.resting == true end)
mock("RequestTimePlayed", function()
	PLAYED.requests = PLAYED.requests + 1
	C_Timer.After(0.5, function() Fire("TIME_PLAYED_MSG", PLAYED.total, 600) end)
end)
mock("GetNumGroupMembers", function() return GROUP_MEMBERS end)
mock("GetBindLocation", function() return BIND end)
mock("GetPVPSessionStats", function() return HONOR, 0 end)
mock("GetBattlefieldWinner", function() return BG_WINNER end)
mock("UnitPlayerControlled", function(u) return MOBS[u] ~= nil and MOBS[u].controlled == true end)
local baseGUID, baseInstanceInfo, baseItemLink, baseAFK = UnitGUID, GetInstanceInfo, GetInventoryItemLink, UnitIsAFK
mock("UnitGUID", function(u) if u == "pet" then return PET_GUID end return baseGUID(u) end)
-- (INSTANCE.id and .difficulty: GetInstanceInfo's instance ID and difficulty; .unreadable: the ID a secret)
mock("GetInstanceInfo", function()
	if INSTANCE then
		return INSTANCE.name, INSTANCE.type, INSTANCE.difficulty or 0, "", 5, 0, false, INSTANCE.unreadable and SECRET or INSTANCE.id or 0, 5
	end
	return ZONE, "none", 0, "", 0, 0, false, 0, 0
end)
-- (LINK_PENDING[slot]: its link isn't there yet, GetInventoryItemID says the item all the same)
LINK_PENDING = {}
mock("GetInventoryItemLink", function(unit, slot)
	if LINK_PENDING[slot] then return nil end
	return GEAR_LINKS[slot] or baseItemLink(unit, slot)
end)
-- (FACTIONS[i].collapsed: under a closed header, so not listed; known by its ID all the same)
local function listed()
	local list = {}
	for _, f in ipairs(FACTIONS) do if not f.collapsed then list[#list + 1] = f end end
	return list
end
mock("C_Reputation", {
	GetNumFactions = function() return #listed() end,
	GetFactionDataByIndex = function(i) local f = listed()[i]; return f and { factionID = f.id, reaction = f.reaction, isHeader = f.header == true } end,
	GetFactionDataByID = function(id) for _, f in ipairs(FACTIONS) do if f.id == id then return { factionID = id, reaction = f.reaction } end end end,
})
mock("C_SkillInfo", { GetSkillLineInfoByID = function(id) local s = SKILLS[id]; return s and { skillID = id, rank = s[1], maxRank = s[2] } end })
local questFlagged = C_QuestLog.IsQuestFlaggedCompleted
C_QuestLog.IsQuestFlaggedCompleted = function(id) return QUESTS_DONE[id] == true end
local newItems = { [2770] = { name = "Copper Ore", quality = 1 }, [2835] = { name = "Rough Stone", quality = 1 },
	[2447] = { name = "Peacebloom", quality = 1 }, [2318] = { name = "Light Leather", quality = 1 },
	[6303] = { name = "Raw Slitherskin Mackerel", quality = 1 }, [6125] = { name = "Brawler's Pants", quality = 2 } }
for id, item in pairs(newItems) do ITEMS[id] = item end
-- A chat frame that shows /played's answer (Blizzard's register TIME_PLAYED_MSG): ChatFrame3.
local chatWindows = NUM_CHAT_WINDOWS
NUM_CHAT_WINDOWS = 3
local chat = CreateFrame("Frame", "ChatFrame3")
local chatHas, chatGot = false, 0
local register, unregister = chat.RegisterEvent, chat.UnregisterEvent
function chat:IsEventRegistered(event) return event == "TIME_PLAYED_MSG" and chatHas end
function chat:RegisterEvent(event) chatHas = chatHas or event == "TIME_PLAYED_MSG"; return register(self, event) end
function chat:UnregisterEvent(event) chatHas = chatHas and event ~= "TIME_PLAYED_MSG"; return unregister(self, event) end
chat:SetScript("OnEvent", function(_, event) if event == "TIME_PLAYED_MSG" then chatGot = chatGot + 1 end end)
chat:RegisterEvent("TIME_PLAYED_MSG")

-- What other files left in the mock's world, put back at the end.
local keep = { map = PLAYER_MAP, pos = PLAYER_POS, equipped = EQUIPPED, quests = QUESTS, travel = {}, state = {}, xp = {},
	instance = INSTANCE, group = GROUP, world = LT.world, loot = LOOT, fishing = LOOT_FISHING, taxiNodes = TAXI_MAP_NODES }
for k, v in pairs(TRAVEL) do keep.travel[k] = v end
for _, k in ipairs({ "moving", "dead", "ghost", "combat", "afk", "resting", "inInstance" }) do keep.state[k] = STATE[k] end
for k, v in pairs(XP) do keep.xp[k] = v end
EQUIPPED, QUESTS, INSTANCE, GROUP = {}, {}, nil, "none"
TRAVEL.taxi, TRAVEL.swimming, TRAVEL.mounted, TRAVEL.flying = false, false, false, false
STATE.moving, STATE.dead, STATE.ghost, STATE.inInstance, STATE.resting = false, false, false, false, false

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- Echoes switched off and on again, on the client world says.
local function restart(world)
	LT:SetModuleEnabled("echoes", false)
	LT.world = world
	LT:SetModuleEnabled("echoes", true)
end

-- Every line written while listening: the line, its kind, its time, the position written after it.
local heard, listening = {}, false
E.OnLine(function(line, kind)
	if listening then
		local s = E.state
		heard[#heard + 1] = { line = line, kind = kind, t = s.t, c = s.continent, n = s.north, w = s.west, mode = s.mode }
	end
end)
local function listen()
	wipe(heard)
	listening = true
end

local function split(line)
	local f = {}
	for x in (line .. ";"):gmatch("([^;]*);") do f[#f + 1] = x end
	return f
end

-- The capture's lines, without the pages' (the header, the character, a page's end, clock lines, a
-- new page's anchor and the zone after it), as heard.
local function mine()
	local out, afterPage = {}, false
	for _, h in ipairs(heard) do
		local kind = h.kind
		local newPage = kind == "@" and split(h.line)[6] == "c"
		local pages = (kind == nil and not h.line:find("^%d")) or kind == "C" or kind == "." or kind == "!" or newPage
			or (kind == "z" and afterPage)
		afterPage = newPage
		if not pages then out[#out + 1] = h end
	end
	return out
end

-- A line without its dt: "@;0;500;500;f;s", ",3,-4" (a point), "o;1".
local function body(line)
	if line:find("^%d") then
		return (line:gsub("^%d+", ""))
	end
	return (line:gsub("^(.)%d+", "%1"))
end

-- The capture's lines since listen(), each without its dt, one space apart (unnamed: without the
-- names, which come once per page: whether a page started in between doesn't matter then).
local function seq(unnamed)
	local list = {}
	for _, h in ipairs(mine()) do
		if not (unnamed and h.kind == "=") then list[#list + 1] = body(h.line) end
	end
	return table.concat(list, " ")
end

-- The points among them: { dt, dn, dw, t, n, w } (n, w: the position after it).
local function points()
	local list = {}
	for _, h in ipairs(mine()) do
		local dt, dn, dw = h.line:match("^(%d+),(%-?%d+),(%-?%d+)$")
		if dt then list[#list + 1] = { dt = tonumber(dt), dn = tonumber(dn), dw = tonumber(dw), t = h.t, n = h.n, w = h.w } end
	end
	return list
end

local function count(pattern)
	local n = 0
	for _, h in ipairs(mine()) do if body(h.line):find(pattern) then n = n + 1 end end
	return n
end

-- Where I stand (Elwynn Forest, 1429: north and west from 0 to 1000 yd; also inside an instance,
-- where the game doesn't say).
local spot = { 500, 500 }
local function at(north, west)
	PLAYER_MAP = 1429
	PLAYER_POS = { (1000 - west) / 1000, (1000 - north) / 1000 }
	spot[1], spot[2] = north, west
end
local function here()
	return spot[1], spot[2]
end

-- Walking (or carried: still, IsPlayerMoving false) in a straight line, speed yd/s, 0.1 s a step.
local function walk(north, west, speed, still)
	local n0, w0 = here()
	local steps = math.max(1, math.ceil(math.sqrt((north - n0) ^ 2 + (west - w0) ^ 2) / (speed or 7) / 0.1))
	if not still and not STATE.moving then
		STATE.moving = true
		Fire("PLAYER_STARTED_MOVING")
	end
	for i = 1, steps do
		at(n0 + (north - n0) * i / steps, w0 + (west - w0) * i / steps)
		Advance(0.1)
	end
end
local function halt()
	if STATE.moving then
		STATE.moving = false
		Fire("PLAYER_STOPPED_MOVING")
	end
end

-- A loading screen: from here to wherever setup() puts me.
local function loading(setup, initial, reload)
	Fire("PLAYER_LEAVING_WORLD")
	setup()
	Fire("PLAYER_ENTERING_WORLD", initial == true, reload == true)
	Advance(0.3)
end

local function cap() return C.Cap() end
local function now() return E.Now() end

---------------------------------------------------------------------------
section("Echoes capture: a session starts")
---------------------------------------------------------------------------
do
	wipe(LefthyToolsEchoesDB.capture)
	wipe(LefthyToolsEchoesDB.friends)
	at(500, 500)
	listen()
	restart("release")
	check(seq() == "", "switched on: nothing yet (the anchor comes on the tick)")
	Advance(0.3)
	check(seq() == "@;0;500;500;f;s z;1429;Goldshire o;1 x;19;1500;6000;1200;0",
		"switched on: an anchor where I stand (why s), the zone, the session (o1), the XP, got\n" .. seq())
	check(cap() == LefthyToolsEchoesDB.capture["Player-1-0"] and cap().xp == "19:1500:6000:1200:0",
		"what's compared later is kept per character, by GUID")
	listen()
	Advance(10)
	check(seq() == "", "standing still: nothing written, got " .. seq())
	-- A login: PLAYER_LOGIN switches Echoes on, then the first loading screen ends.
	listen()
	LT:SetModuleEnabled("echoes", false)
	check(seq() == "o;0", "switched off: the session ends (o0), got " .. seq())
	listen()
	LT:SetModuleEnabled("echoes", true)
	Fire("PLAYER_ENTERING_WORLD", true, false)
	Advance(0.3)
	check(seq():find("^@;0;500;500;f;s z;1429;Goldshire o;1") ~= nil, "a login: the same, got " .. seq())
	Advance(2)
	PLAYED.requests = 0
end

---------------------------------------------------------------------------
section("Echoes capture: the store rule")
---------------------------------------------------------------------------
do
	-- 60 yd north at 7 yd/s: a point every 25 yd, the stop.
	at(500, 500)
	Advance(2)
	listen()
	local startAt = now()
	walk(560, 500)
	halt()
	Advance(0.3)
	local p = points()
	check(#p == 4 and p[1].dn == 0 and p[1].dw == 0 and p[1].t - startAt <= 1, "moving again: first the old spot once more, now (the idle crawl fix), got " .. seq())
	check(p[2] and p[2].dn >= 25 and p[2].dn <= 30 and p[3] and p[3].dn >= 25 and p[3].dn <= 30, "a point at 25 yd from the last (the first poll past it)")
	check(p[4] and p[4].n == 560 and p[4].w == 500, "the stop: where I stopped")
	local stopAt = p[4] and p[4].t
	check(stopAt and stopAt - startAt <= 10, "the stop point comes at once (PLAYER_STOPPED_MOVING: the next tick)")

	-- Standing 30 s, then on: the old spot again with the time I left it, so the dot waits there.
	Advance(30)
	listen()
	local leftAt = now()
	walk(560, 488)
	walk(572, 488)
	halt()
	Advance(0.3)
	p = points()
	check(#p == 3 and p[1].dn == 0 and p[1].dw == 0 and p[1].dt >= 30 and p[1].t - leftAt <= 1,
		"30 s standing: the same spot again when I leave it, dt " .. tostring(p[1] and p[1].dt))
	-- A bend: 12 yd east, then 12 north: a point at the corner (the sample before the bend was seen).
	check(p[2] and math.abs(p[2].n - 560) <= 4 and math.abs(p[2].w - 488) <= 4, "a bend of more than 3 yd: a point at the corner, got "
		.. tostring(p[2] and (p[2].n .. "," .. p[2].w)))
	check(p[3] and p[3].n == 572 and p[3].w == 488, "and the stop")

	-- Walking a gentle curve (less than 3 yd off the line): no bend point.
	listen()
	walk(578, 489)
	walk(584, 488)
	halt()
	Advance(0.3)
	p = points()
	check(#p == 1 and p[1].n == 584 and p[1].w == 488,
		"less than 3 yd off the line: no point but the stop (on at once after stopping: no start point), got " .. seq())

	-- An event comes: the path brought up to now first (more than 3 yd from the last point).
	listen()
	walk(594, 488)
	Fire("NEW_TOY_ADDED", 1234)
	Advance(0.1)
	halt()
	Advance(0.3)
	local list = mine()
	local toy
	for i, h in ipairs(list) do if h.kind == "n" then toy = i end end
	check(toy and toy > 1 and list[toy - 1].line:find("^%d") and math.abs(list[toy - 1].n - 594) <= 1,
		"an event: a point where I am first (its spot is the path's), got " .. seq())
	check(body(list[toy].line) == "n;t;1234", "the event's line")

	-- The cost: standing, one look a second; moving, two.
	local calls = UNIT_POSITION_CALLS
	local beacon, chronicle = LT:GetModule("beacon"), LT:GetModule("chronicle")
	LT:SetModuleEnabled("beacon", false)
	LT:SetModuleEnabled("chronicle", false)
	calls = UNIT_POSITION_CALLS
	Advance(10)
	local still = UNIT_POSITION_CALLS - calls
	calls = UNIT_POSITION_CALLS
	walk(594, 418)
	local moving = UNIT_POSITION_CALLS - calls
	halt()
	Advance(1)
	check(still >= 9 and still <= 11, "standing still: UnitPosition about once a second, got " .. still)
	check(moving >= 18 and moving <= 24, "moving (10 s): about twice a second, got " .. moving)
	LT:SetModuleEnabled("beacon", true)
	LT:SetModuleEnabled("chronicle", true)
	check(beacon.enabled and chronicle.enabled, "(Beacon and Chronicle on again)")
end

---------------------------------------------------------------------------
section("Echoes capture: travel modes")
---------------------------------------------------------------------------
do
	at(300, 300)
	Advance(1.2)
	Advance(2)
	-- Mounting while standing: nothing until I move (the mode is read where the position changed).
	listen()
	TRAVEL.mounted = true
	Advance(3)
	check(seq() == "", "mounted, standing: nothing yet")
	walk(300, 260, 14)
	halt()
	Advance(0.3)
	check(seq():find("^,0,0 ,%-?%d+,%-?%d+ m;m") ~= nil and count("^m;") == 1,
		"moving mounted: the start, a point, then the mode (m), got " .. seq())
	listen()
	TRAVEL.mounted = false
	Advance(2)
	walk(300, 250)
	halt()
	Advance(0.3)
	check(count("^m;f$") == 1, "off the mount: on foot (f), got " .. seq())

	-- Swimming flickers at the surface: one poll isn't enough, two are.
	listen()
	STATE.moving = true
	Fire("PLAYER_STARTED_MOVING")
	walk(300, 240)
	TRAVEL.swimming = true
	walk(300, 236)
	TRAVEL.swimming = false
	walk(300, 226)
	check(count("^m;") == 0, "swimming for one poll: no mode change, got " .. seq())
	TRAVEL.swimming = true
	walk(300, 210)
	check(count("^m;s$") == 1, "swimming for two polls and more: s, got " .. seq())
	TRAVEL.swimming = false
	walk(300, 196)
	halt()
	Advance(0.3)
	check(count("^m;f$") == 1 and count("^m;") == 2, "out of the water: on foot again, got " .. seq())

	-- Travel form and Ghost Wolf: v.
	listen()
	FORM_ID = 3
	walk(300, 180)
	FORM_ID = 16
	walk(300, 160)
	FORM_ID = nil
	walk(300, 150)
	halt()
	Advance(0.3)
	check(count("^m;v$") == 1 and count("^m;f$") == 1 and count("^m;") == 2, "Travel Form, then Ghost Wolf: v once; back on foot, got " .. seq())

	-- A flight path: t at once, a point every 100 yd, polled once a second.
	listen()
	TRAVEL.taxi = true
	walk(600, 150, 30, true)
	local p = points()
	check(count("^m;t$") == 1, "on a flight path: t, got " .. seq())
	local spaced = #p >= 3
	for i = 2, #p - 1 do
		spaced = spaced and math.sqrt(p[i + 1].dn ^ 2 + p[i + 1].dw ^ 2) >= 100
	end
	check(spaced and #p <= 5, "points 100 yd apart on a flight path, got " .. seq())
	-- An event there, more than 50 yd past the last point (no jump: polled a moment ago): a point
	-- where I am first.
	while spot[1] - E.state.north < 60 do
		walk(spot[1] + 3, 150, 30, true)
	end
	listen()
	Fire("NEW_TOY_ADDED", 4242)
	Advance(0.3)
	local list = mine()
	check(#list >= 2 and list[1].line:find("^%d") and math.abs(list[1].n - spot[1]) <= 1 and body(list[2].line) == "n;t;4242",
		"an event on a flight path, 60 yd past the last point: a point where I am first, got " .. seq())
	TRAVEL.taxi = false
	Advance(2)
	listen()
	walk(600, 140)
	halt()
	Advance(0.3)
	check(count("^m;f$") == 1, "landed and walking: on foot, got " .. seq())

	-- Carried: moving 10 yd/s while the game says I don't move (a boat): c, after two polls.
	listen()
	UNIT_SPEED = 0
	walk(600, 40, 10, true)
	check(count("^m;c$") == 1, "carried (measured speed 3 yd/s and more above my own): c, got " .. seq())
	UNIT_SPEED = nil
	walk(610, 40)
	halt()
	Advance(0.3)
	check(count("^m;f$") == 1, "walking off the boat: on foot, got " .. seq())
	UNIT_SPEED = nil

	-- Not carried: the stop (the game says speed 0, however far it came since the last poll), then
	-- a Blink (20 yd at once, standing); two Blinks with polls standing still between them.
	listen()
	walk(640, 40)
	halt()
	Advance(2)
	at(640, 60)
	Advance(1.2)
	Advance(5)
	at(640, 80)
	Advance(1.2)
	Advance(2)
	check(count("^m;") == 0, "a stop, then Blinks standing: still on foot (the guess needs two polls in a row), got " .. seq())

	-- The game's speed a secret: no carried guess (a secret can't be compared).
	listen()
	UNIT_SPEED = SECRET
	walk(640, 200, 10, true)
	UNIT_SPEED = nil
	Advance(1.2)
	check(count("^m;") == 0 and #points() >= 4, "carried, the speed a secret: no guess, the path all the same, got " .. seq())

	-- On a boat across a loading screen: its last point, an anchor (why l; not carried yet), carried
	-- again after two polls; walking off it.
	listen()
	UNIT_SPEED = 0
	walk(640, 260, 10, true)
	Fire("PLAYER_LEAVING_WORLD")
	at(700, 300)
	Fire("PLAYER_ENTERING_WORLD", false, false)
	Advance(0.3)
	walk(700, 360, 10, true)
	UNIT_SPEED = nil
	walk(710, 360)
	halt()
	Advance(0.3)
	local boat = seq()
	local before, after = boat:match("^(.-)@;0;700;300;f;l(.*)$")
	check(before and before:find("m;c") and before:find(",%-?%d+,%-?%d+ $") and select(2, after:gsub("m;c", "")) == 1
		and after:find("m;f"),
		"a boat across a loading screen: carried, its last point, the anchor on foot, carried again, off it, got " .. boat)
end

---------------------------------------------------------------------------
section("Echoes capture: segments and their causes")
---------------------------------------------------------------------------
do
	at(500, 500)
	Advance(1.2)
	Advance(1)
	-- A jump (more than 50 + 40 yd a second between two polls): a new segment, why j.
	listen()
	at(500, 100)
	Advance(1.2)
	check(seq() == "@;0;500;100;f;j", "a jump: an anchor there (no line drawn), why j, got " .. seq())
	-- The hearthstone: its cast (8690) within 20 s explains the jump.
	listen()
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 8690)
	Advance(5)
	at(800, 800)
	Advance(1.2)
	check(seq() == "@;0;800;800;f;h;8690", "the hearthstone: why h with the spell, got " .. seq())
	-- A cast 25 s before doesn't explain it any more.
	listen()
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 8690)
	Advance(25)
	at(100, 100)
	Advance(1.2)
	check(seq() == "@;0;100;100;f;j", "a hearthstone 25 s before: another jump (j), got " .. seq())
	-- A teleport spell (Teleport: Stormwind), a summon (accepted up to 120 s before): only one you
	-- accepted counts, not one offered and declined, or not answered (someone's portal meanwhile).
	listen()
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", 3561)
	Advance(1)
	at(900, 100)
	Advance(1.2)
	SUMMON_LEFT = 120
	Fire("CONFIRM_SUMMON", 0, false)
	Advance(5)
	C_SummonInfo.CancelSummon()
	Fire("CANCEL_SUMMON")
	Advance(5)
	at(100, 900)
	Advance(1.2)
	SUMMON_LEFT = 120
	Fire("CONFIRM_SUMMON", 0, false)
	Advance(5)
	at(900, 900)
	Advance(1.2)
	Advance(30)
	C_SummonInfo.ConfirmSummon()
	Advance(60)
	at(100, 100)
	Advance(1.2)
	check(seq() == "@;0;900;100;f;p;3561 @;0;100;900;f;j @;0;900;900;f;j @;0;100;100;f;u",
		"a teleport spell: p with the spell; a summon declined, or not answered yet: j; accepted: u, got " .. seq())
	-- A summon accepted across a loading screen: u; with a teleport spell too: the spell.
	listen()
	SUMMON_LEFT = 120
	Fire("CONFIRM_SUMMON", 0, false)
	C_SummonInfo.ConfirmSummon()
	loading(function() at(500, 500) end)
	SUMMON_LEFT = 120
	Fire("CONFIRM_SUMMON", 0, false)
	C_SummonInfo.ConfirmSummon()
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-12", 3562)
	loading(function() at(100, 100) end)
	check(seq() == "@;0;500;500;f;u @;0;100;100;f;p;3562", "over a loading screen: u; a teleport spell as well: p, got " .. seq())
	-- Another continent: a new segment there, and the zone.
	listen()
	PLAYER_MAP, PLAYER_POS = 1414, { 0.5, 0.5 }
	Advance(1.2)
	check(seq() == "@;1;0;0;f;j z;1414;Goldshire", "another continent: an anchor on it, the zone, got " .. seq())
	-- A loading screen: the last point before it at once, then the anchor where it ends (why l).
	at(500, 500)
	loading(function() end)
	Advance(2)
	listen()
	walk(510, 500)
	Fire("PLAYER_LEAVING_WORLD")
	check(seq() == ",0,0 ,10,0", "a loading screen begins: the last point at once, got " .. seq())
	PLAYER_MAP, PLAYER_POS = 1414, { 0.4, 0.4 }
	Fire("PLAYER_ENTERING_WORLD", false, false)
	halt()
	Advance(0.3)
	check(seq() == ",0,0 ,10,0 @;1;400;400;f;l z;1414;Goldshire", "and ends: an anchor (why l), got " .. seq())

	-- A dungeon: no positions inside (an anchor without one, its instance's map), entered and left.
	listen()
	loading(function() INSTANCE, STATE.inInstance = { name = "The Deadmines", type = "party", id = 36, difficulty = 1 }, true; at(450, 450) end)
	check(seq() == "@;36;;;f;i z;1429;Goldshire d;e;36;1",
		"a dungeon entered: an anchor without a position (why i, its map), the zone, the dungeon (d e), got " .. seq())
	listen()
	walk(450, 450)
	halt()
	Fire("ENCOUNTER_END", 1234, "Edwin VanCleef", 1, 5, 1)
	Advance(0.3)
	Fire("BOSS_KILL", 1234, "Edwin VanCleef")
	Fire("ENCOUNTER_END", 1235, "Cookie", 1, 5, 0)
	Advance(0.3)
	check(seq() == "B;1234", "inside: no points; a boss (B) once, not a failed one, got " .. seq())
	listen()
	loading(function() INSTANCE, STATE.inInstance = nil, false; at(500, 500) end)
	check(seq() == "@;0;500;500;f;o d;x;36;1", "left: an anchor (why o), the dungeon left (d x), got " .. seq())
	-- Out by hearthstone: h, not o.
	loading(function() INSTANCE, STATE.inInstance = { name = "The Deadmines", type = "party", id = 36, difficulty = 1 }, true end)
	listen()
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-4", 8690)
	loading(function() INSTANCE, STATE.inInstance = nil, false; at(600, 600) end)
	check(seq() == "@;0;600;600;f;h;8690 d;x;36;1", "out of a dungeon by hearthstone: why h, got " .. seq())

	-- The position going outdoors (the game hides it) and coming back.
	Advance(1)
	listen()
	STATE.inInstance = true
	Advance(1.2)
	STATE.inInstance = false
	Advance(1.2)
	check(seq() == "@;0;;;f;j @;0;600;600;f;j", "the position gone: an anchor without one; back: an anchor, got " .. seq())
	-- From Kalimdor through a loading screen to where the game hides the position (not an
	-- instance): after 3 s an anchor without one, on the continent the game says now.
	PLAYER_MAP, PLAYER_POS = 1414, { 0.5, 0.5 }
	Advance(1.2)
	listen()
	loading(function() STATE.inInstance = true end)
	Advance(4)
	STATE.inInstance = false
	at(600, 600)
	Advance(1.2)
	check(seq() == "@;0;;;f;l @;0;600;600;f;j z;1429;Goldshire",
		"a loading screen to no position: an anchor without one, its continent from GetInstanceInfo, got " .. seq())

	-- Released to the graveyard: the ghost starts a segment there (r); the corpse run; back to life.
	listen()
	STATE.dead = true
	Fire("PLAYER_DEAD")
	Advance(0.3)
	STATE.ghost = true
	Fire("PLAYER_ALIVE")
	at(640, 600)
	Advance(1.2)
	walk(610, 600)
	halt()
	Advance(0.3) -- (at the corpse)
	STATE.ghost, STATE.dead = false, false
	Fire("PLAYER_UNGHOST")
	Advance(1.2)
	check(seq():find("^D;19;%-;;;;0 @;0;640;600;g;r ,0,0 .* r;c m;f$") ~= nil and points()[#points()].n == 610,
		"died, released: an anchor at the graveyard (why r, ghost); the run back; alive at the corpse (r c), on foot, got " .. seq())
	Advance(11)
	-- An event a moment before a loading screen (no tick between): written before it, where it was.
	listen()
	Fire("NEW_TOY_ADDED", 4321)
	loading(function() at(800, 800) end)
	Advance(1)
	check(seq() == "n;t;4321 @;0;800;800;f;l", "an event just before a loading screen: written there, before the anchor, got " .. seq())
	-- The hearthstone, an event in its last moment, and the game already says the destination when
	-- the loading screen begins: the event where I was, the hearthstone for the anchor after it.
	listen()
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-11", 8690)
	Advance(1)
	Fire("NEW_TOY_ADDED", 4322)
	at(400, 900)
	Fire("PLAYER_LEAVING_WORLD")
	Fire("PLAYER_ENTERING_WORLD", false, false)
	Advance(1)
	check(seq() == "n;t;4322 @;0;400;900;f;h;8690", "and a hearthstone just before it: the anchor after it says so, got " .. seq())
	loading(function() at(610, 600) end)
	Advance(2)
end

---------------------------------------------------------------------------
section("Echoes capture: level-ups, /played, XP")
---------------------------------------------------------------------------
do
	-- /played: asked once per login, silently (the chat frames don't get it), out of combat.
	-- A login's heavy checks run one per tick, on the ticks after the anchor's (the XP is read there):
	-- the gear (19 slots), professions, the reputation scan, /played; never two in one tick.
	PLAYED.requests, chatGot = 0, 0
	local first, undo = {}, {} -- what -> GetTime() of its first call
	local function spy(t, k, what)
		local f = t[k]
		t[k] = function(...)
			first[what] = first[what] or GetTime()
			return f(...)
		end
		undo[#undo + 1] = function() t[k] = f end
	end
	spy(_G, "GetXPExhaustion", "x")
	spy(_G, "GetInventoryItemLink", "G")
	spy(C_SkillInfo, "GetSkillLineInfoByID", "s")
	spy(C_Reputation, "GetNumFactions", "R")
	spy(_G, "RequestTimePlayed", "played")
	listen()
	Fire("PLAYER_ENTERING_WORLD", true, false)
	Advance(1.5)
	for i = #undo, 1, -1 do undo[i]() end
	local order, spread = { "x", "G", "s", "R", "played" }, true
	for i = 2, #order do
		local a, b = first[order[i - 1]], first[order[i]]
		spread = spread and a and b and b - a > 0.2 and b - a < 0.3
	end
	check(spread, ("a login's checks one per tick: XP (the anchor's tick), then gear, professions, reputation, /played, got %s %s %s %s %s")
		:format(tostring(first.x), tostring(first.G), tostring(first.s), tostring(first.R), tostring(first.played)))
	check(PLAYED.requests == 1 and not chatHas, "a login: /played asked, the chat frames don't get its answer")
	Advance(1)
	check(chatGot == 0 and chatHas and cap().played >= 7200 and cap().played < 7202, "its answer: the time played; the chat frames get it again")
	local askedAt = GetTime() - 0.5
	Advance(30)
	Fire("PLAYER_LEVEL_UP", 20)
	Advance(0.3)
	local line = mine()[#mine()]
	local played = tonumber(line.line:match("^L%d+;20;(%d+)$"))
	check(played and math.abs(played - (7200 + GetTime() - askedAt)) <= 1, "a level-up: L with the level and the time played, got " .. line.line)
	Fire("PLAYER_ENTERING_WORLD", false, false)
	Advance(0.3)
	check(PLAYED.requests == 1, "a loading screen: /played isn't asked again")
	-- XP: when it changed, at most once a minute; at once when resting changes.
	listen()
	XP.current = 1600
	Advance(61)
	XP.current, XP.rested = 1700, 1300
	Advance(30)
	STATE.resting = true
	Fire("PLAYER_UPDATE_RESTING")
	Advance(0.3)
	check(seq() == "x;19;1600;6000;1200;0 x;19;1700;6000;1300;1",
		"XP: level, xp, max, rested, resting; each minute when it changed, at once when resting changes, got " .. seq())
	-- In an inn: the rested XP grows every minute, the resting flag goes off and on; only that is
	-- written at most every 10 minutes (the last state then); XP gained at once again.
	listen()
	for _ = 1, 9 do
		XP.rested = XP.rested + 10
		Advance(60)
	end
	STATE.resting = false
	Fire("PLAYER_UPDATE_RESTING")
	Advance(0.3)
	STATE.resting = true
	Fire("PLAYER_UPDATE_RESTING")
	Advance(0.3)
	local quiet = seq()
	Advance(61)
	local tenMinutes = seq()
	listen()
	XP.current, STATE.resting = 1750, false
	Advance(61)
	check(quiet == "" and tenMinutes == "x;19;1700;6000;1390;1" and seq() == "x;19;1750;6000;1390;0",
		"only rested XP or resting: at most every 10 minutes; XP gained: at once, got " .. quiet .. " | " .. tenMinutes .. " | " .. seq())
	STATE.resting = false
end

---------------------------------------------------------------------------
section("Echoes capture: quests")
---------------------------------------------------------------------------
do
	QUESTS = { { id = 7, title = "Kobold Camp Cleanup", objectives = {} } }
	listen()
	Fire("QUEST_ACCEPTED", 7)
	Advance(0.3)
	QUESTS = {}
	Fire("QUEST_TURNED_IN", 7, 250, 40)
	Fire("QUEST_REMOVED", 7, false)
	Advance(2)
	check(seq() == "=;q;7;Kobold Camp Cleanup a;7 Q;7;250;40", "accepted (its title once per page), turned in with XP and money, got " .. seq())
	listen()
	Fire("QUEST_ACCEPTED", 8)
	Fire("QUEST_REMOVED", 8, false)
	Advance(1)
	check(seq() == "a;8", "removed: decided a moment later, got " .. seq())
	Advance(1)
	QUESTS_DONE[9] = true
	Fire("QUEST_REMOVED", 9, false)
	Advance(2)
	check(seq() == "a;8 A;8 Q;9", "removed, not done: abandoned (A); removed and done without QUEST_TURNED_IN: turned in, got " .. seq())
	-- Removed first, turned in a moment later (which comes first is still to be seen in game): one Q,
	-- with its XP and money.
	listen()
	Fire("QUEST_ACCEPTED", 10)
	Advance(0.3)
	Fire("QUEST_REMOVED", 10, false)
	Advance(0.5)
	QUESTS_DONE[10] = true
	Fire("QUEST_TURNED_IN", 10, 300, 50)
	Advance(2)
	check(seq() == "a;10 Q;10;300;50", "removed, then turned in: one Q with XP and money, got " .. seq())
	-- One Q per turn-in, however far apart the two events come: turned in 3 s after the removal was
	-- decided (done: Q); removed 40 s after it was turned in. A quest turned in again (accepted
	-- again, or a repeatable one that never was in the log) counts again.
	listen()
	Fire("QUEST_ACCEPTED", 11)
	Advance(0.3)
	QUESTS_DONE[11] = true
	Fire("QUEST_REMOVED", 11, false)
	Advance(3)
	Fire("QUEST_TURNED_IN", 11, 400, 60)
	Advance(0.5)
	Fire("QUEST_TURNED_IN", 12, 500, 70)
	Advance(40)
	QUESTS_DONE[12] = true
	Fire("QUEST_REMOVED", 12, false)
	Advance(2)
	check(seq() == "a;11 Q;11 Q;12;500;70", "turned in long after its removal, removed long after it was turned in: one Q each, got " .. seq())
	listen()
	Fire("QUEST_TURNED_IN", 13, 100, 5)
	Fire("QUEST_REMOVED", 13, false)
	Advance(2)
	Fire("QUEST_ACCEPTED", 13)
	Fire("QUEST_TURNED_IN", 13, 100, 5)
	Fire("QUEST_REMOVED", 13, false)
	Advance(2)
	Fire("QUEST_TURNED_IN", 14, 50, 0)
	Advance(0.5)
	Fire("QUEST_TURNED_IN", 14, 50, 0)
	Advance(2)
	check(seq() == "Q;13;100;5 a;13 Q;13;100;5 Q;14;50;0 Q;14;50;0", "a quest turned in again, a repeatable one twice: a Q each time, got " .. seq())
	listen()
	Fire("QUEST_ACCEPTED", SECRET)
	Fire("QUEST_REMOVED", SECRET)
	Advance(2)
	check(seq() == "", "a secret quest: nothing")
end

---------------------------------------------------------------------------
section("Echoes capture: deaths and coming back")
---------------------------------------------------------------------------
do
	-- Killed by a creature I fought: its ID, level, classification (elite); its name once per page.
	MOBS.target = { name = "Kobold Vermin", level = 5, class = "elite", guid = "Creature-0-1-0-1-327-000000AA" }
	listen()
	EnterCombat()
	Advance(0.3)
	STATE.dead = true
	Fire("PLAYER_DEAD")
	Advance(0.3)
	Fire("PLAYER_DEAD")
	Advance(0.3)
	LeaveCombat()
	check(seq() == "=;c;327;Kobold Vermin D;19;c;327;5;e;0", "a death: the killer creature, its level and classification, not pvp; once, got " .. seq())
	-- A player brings me back.
	listen()
	Fire("RESURRECT_REQUEST", "Anna")
	STATE.dead = false
	Fire("PLAYER_ALIVE")
	Advance(0.3)
	check(seq() == "r;p", "a player's resurrection before releasing: r p, got " .. seq())
	Advance(11)
	-- Killed by a player: class and level only, pvp; back at the spirit healer.
	MOBS.target = { player = true, classFile = "MAGE", level = 14, guid = "Player-1-99" }
	listen()
	EnterCombat()
	Advance(0.3)
	STATE.dead = true
	Fire("PLAYER_DEAD")
	Advance(0.3)
	LeaveCombat()
	STATE.ghost = true
	Fire("PLAYER_ALIVE")
	Advance(2.5)
	Fire("CONFIRM_XP_LOSS")
	STATE.ghost, STATE.dead = false, false
	Fire("PLAYER_UNGHOST")
	Advance(1.2)
	check(seq() == "D;19;p;MAGE;14;;1 @;0;610;600;g;r r;s m;f",
		"killed by a player: class and level, pvp; released where I died; the spirit healer: r s, got " .. seq())
	Advance(11)
	-- The killer's GUID secret (the game restricts who's who): not known.
	MOBS.target = { name = "Defias Pillager", level = 15, guid = SECRET }
	listen()
	EnterCombat()
	Advance(0.3)
	STATE.dead = true
	Fire("PLAYER_DEAD")
	Advance(0.3)
	LeaveCombat()
	MOBS.target = nil
	STATE.dead = false
	Fire("PLAYER_ALIVE")
	Advance(0.3)
	check(seq() == "D;19;-;;;;0 r;c", "a killer that's a secret: unknown (-), got " .. seq())
	Advance(11)
	-- Killed by a player's totem (a creature's GUID), pet or guardian: player-controlled, so a player
	-- killed me (pvp): its owner's class and level when the owner has a nameplate, else unknown.
	local function diedTo(mob)
		MOBS.target = mob
		EnterCombat()
		Advance(0.3)
		STATE.dead = true
		Fire("PLAYER_DEAD")
		Advance(0.3)
		LeaveCombat()
		MOBS.target = nil
		STATE.dead = false
		Fire("PLAYER_ALIVE")
		Advance(0.3)
		Advance(11)
	end
	mock("UnitIsOwnerOrControllerOfUnit", function(owner, unit) return MOBS[owner] ~= nil and MOBS[owner].owns == unit end)
	listen()
	diedTo({ name = "Searing Totem", level = 20, guid = "Creature-0-1-0-1-2523-000000AC", controlled = true })
	MOBS.nameplate4 = { player = true, classFile = "SHAMAN", level = 22, guid = "Player-1-98", owns = "target", friendly = false }
	diedTo({ name = "Searing Totem", level = 20, guid = "Creature-0-1-0-1-2523-000000AD", controlled = true })
	MOBS.nameplate4 = nil
	diedTo({ name = "Wolf", level = 21, guid = "Pet-0-1-0-1-1234-000000AE", controlled = true })
	check(seq() == "D;19;p;;;;1 r;c D;19;p;SHAMAN;22;;1 r;c D;19;p;;;;1 r;c",
		"killed by a player's totem or pet: a player (p, pvp), the owner's class and level when it has a nameplate, got " .. seq())
	-- No fight for 15 s before: unknown.
	MOBS.target = { name = "Kobold Vermin", level = 5, guid = "Creature-0-1-0-1-327-000000AB" }
	EnterCombat()
	Advance(0.3)
	LeaveCombat()
	MOBS.target = nil
	Advance(16)
	listen()
	STATE.dead = true
	Fire("PLAYER_DEAD")
	Advance(0.3)
	STATE.dead = false
	Fire("PLAYER_ALIVE")
	Advance(0.3)
	check(seq() == "D;19;-;;;;0 r;c", "the last fight more than 15 s before: no killer, got " .. seq())
	Advance(11)
	-- Logged in dead (no PLAYER_DEAD for it), then released 57 yd away (no jump): the graveyard
	-- still starts a segment (r); the spirit healer.
	at(610, 600)
	STATE.dead = true
	listen()
	LT:SetModuleEnabled("echoes", false)
	LT:SetModuleEnabled("echoes", true)
	Fire("PLAYER_ENTERING_WORLD", true, false)
	Advance(2)
	STATE.ghost = true
	Fire("PLAYER_ALIVE")
	at(650, 560)
	Advance(1.2)
	Advance(1)
	Fire("CONFIRM_XP_LOSS")
	STATE.ghost, STATE.dead = false, false
	Fire("PLAYER_UNGHOST")
	Advance(1.2)
	check(seq():find("^o;0 @;0;610;600;f;s z;1429;Goldshire o;1 .*@;0;650;560;g;r r;s m;f$") ~= nil and count("^D;") == 0,
		"logged in dead: released, an anchor at the graveyard (r); the spirit healer, got " .. seq())
	Advance(11)
	-- Died, /reload: PLAYER_DEAD again after it is the same death.
	listen()
	STATE.dead = true
	Fire("PLAYER_DEAD")
	Advance(0.3)
	Fire("PLAYER_LEAVING_WORLD")
	Fire("PLAYER_LOGOUT")
	C.Reset()
	Fire("PLAYER_ENTERING_WORLD", false, true)
	Fire("PLAYER_DEAD")
	Advance(2)
	STATE.dead = false
	Fire("PLAYER_ALIVE")
	Advance(0.3)
	check(count("^D;") == 1 and count("^r;c$") == 1, "a /reload while dead: the death once, then back to life, got " .. seq())
	Advance(11)
	-- Released, then PLAYER_ALIVE again as a ghost: one segment for the release.
	listen()
	STATE.dead = true
	Fire("PLAYER_DEAD")
	Advance(0.3)
	STATE.ghost = true
	Fire("PLAYER_ALIVE")
	at(700, 560)
	Advance(1.2)
	Advance(5)
	Fire("PLAYER_ALIVE")
	Advance(2)
	STATE.ghost, STATE.dead = false, false
	Fire("PLAYER_UNGHOST")
	Advance(1.2)
	check(seq() == "D;19;-;;;;0 @;0;700;560;g;r r;c m;f", "PLAYER_ALIVE twice as a ghost: released once, got " .. seq())
	Advance(11)
	-- Back to life in water, standing still: swimming then (the mode read on two polls: swimming
	-- needs two in a row), at the corpse in a lake and after a player's resurrection there.
	listen()
	STATE.dead = true
	Fire("PLAYER_DEAD")
	Advance(0.3)
	STATE.ghost = true
	Fire("PLAYER_ALIVE")
	at(760, 560)
	Advance(1.2)
	Advance(2)
	TRAVEL.swimming = true
	STATE.ghost, STATE.dead = false, false
	Fire("PLAYER_UNGHOST")
	Advance(3)
	local unghost = seq()
	TRAVEL.swimming = false
	walk(770, 560)
	walk(780, 560)
	halt()
	Advance(11)
	listen()
	STATE.dead = true
	Fire("PLAYER_DEAD")
	Advance(0.3)
	TRAVEL.swimming = true
	Fire("RESURRECT_REQUEST", "Anna")
	STATE.dead = false
	Fire("PLAYER_ALIVE")
	Advance(3)
	local rez = seq()
	TRAVEL.swimming = false
	walk(790, 560)
	walk(800, 560)
	halt()
	Advance(11)
	check(unghost == "D;19;-;;;;0 @;0;760;560;g;r r;c m;s" and rez == "D;19;-;;;;0 r;p m;s" and E.state.mode == "f",
		"back to life in water, standing still: swimming (s), at the corpse and resurrected, got " .. unghost .. " | " .. rez)
end

---------------------------------------------------------------------------
section("Echoes capture: kills")
---------------------------------------------------------------------------
do
	MOBS.nameplate7 = { name = "Defias Bandit", level = 12, class = "rare", guid = "Creature-0-1-0-1-116-000000B1" }
	MOBS.nameplate8 = { name = "Mother Fang", level = 10, class = "rareelite", guid = "Creature-0-1-0-1-471-000000B2" }
	Fire("NAME_PLATE_UNIT_ADDED", "nameplate7")
	Fire("NAME_PLATE_UNIT_ADDED", "nameplate8")
	MOBS.nameplate7, MOBS.nameplate8 = nil, nil
	PET_GUID = "Pet-0-1-0-1-416-000000C1"
	GROUP_GUIDS["Player-1-11"] = true
	listen()
	Fire("PARTY_KILL", "Player-1-0", "Creature-0-1-0-1-116-000000B1")
	Fire("PARTY_KILL", "Player-1-0", "Creature-0-1-0-1-116-000000B1")
	Fire("PARTY_KILL", PET_GUID, "Creature-0-1-0-1-471-000000B2")
	Fire("PARTY_KILL", "Player-1-11", "Creature-0-1-0-1-116-000000B3")
	Fire("PARTY_KILL", "Player-1-50", "Creature-0-1-0-1-116-000000B4")
	Fire("PARTY_KILL", "Player-1-0", "Player-1-60")
	Fire("PARTY_KILL", SECRET, SECRET)
	Fire("PARTY_KILL", "Player-1-0", SECRET)
	Advance(0.3)
	check(seq() == "=;c;116;Defias Bandit k;116;12;r;m =;c;471;Mother Fang k;471;10;x;p k;116;;;g",
		"kills: mine, my pet's, my group's (level and classification as seen, the name once); each corpse once; not "
		.. "someone else's, a player's or a secret, got " .. seq())
	GROUP_GUIDS["Player-1-11"], PET_GUID = nil, nil
	-- A mob known whole (level, classification, name) is only looked up again: one call per
	-- nameplate (a raid pull's 40). One seen at "??" (-1: far above me) is read again: its level
	-- once it shows. (Calls counted from Events.lua only: other modules watch nameplates too.)
	local calls, undo = 0, {}
	for _, name in ipairs({ "UnitGUID", "UnitIsPlayer", "UnitLevel", "UnitClassification", "UnitName" }) do
		local f = _G[name]
		_G[name] = function(...)
			if debug.traceback():find("Echoes/Events.lua", 1, true) then calls = calls + 1 end
			return f(...)
		end
		undo[name] = f
	end
	MOBS.nameplate7 = { name = "Defias Bandit", level = 12, class = "normal", guid = "Creature-0-1-0-1-116-000000B5" }
	Fire("NAME_PLATE_UNIT_ADDED", "nameplate7")
	local firstLook = calls
	calls = 0
	for _ = 1, 40 do Fire("NAME_PLATE_UNIT_ADDED", "nameplate7") end
	local again = calls
	MOBS.nameplate8 = { name = "Hogger", level = -1, class = "elite", guid = "Creature-0-1-0-1-448-000000B6" }
	Fire("NAME_PLATE_UNIT_ADDED", "nameplate8")
	MOBS.nameplate8.level = 11
	Fire("NAME_PLATE_UNIT_ADDED", "nameplate8")
	MOBS.nameplate7, MOBS.nameplate8 = nil, nil
	for name, f in pairs(undo) do _G[name] = f end
	listen()
	Fire("PARTY_KILL", "Player-1-0", "Creature-0-1-0-1-448-000000B6")
	Advance(0.3)
	check(firstLook >= 5 and again == 40, "a mob known whole: one call per nameplate (first look " .. firstLook .. " calls, then " .. again .. " for 40)")
	check(seq() == "=;c;448;Hogger k;448;11;e;m", "a mob seen at ?? first: its level once it shows, got " .. seq())
	-- A nameplate whose unit is a secret, a secret mouseover: nothing, no error.
	local reported, restore = catchErrors()
	listen()
	Fire("NAME_PLATE_UNIT_ADDED", SECRET)
	MOBS.mouseover = { name = "Defias Bandit", level = 12, guid = SECRET }
	Fire("UPDATE_MOUSEOVER_UNIT")
	MOBS.mouseover = nil
	Advance(0.3)
	restore()
	check(#reported == 0 and seq() == "", "a secret nameplate unit or GUID: nothing, got " .. seq() .. " " .. table.concat(reported, " "))
	Fire("NAME_PLATE_UNIT_REMOVED", SECRET) -- (gone again: the Misc Tweaks' aggro tags keep nameplates in a group fight)
end

---------------------------------------------------------------------------
section("Echoes capture: loot and gathering")
---------------------------------------------------------------------------
do
	local corpse = "Creature-0-1-0-1-116-000000B1"
	listen()
	LOOT = { { type = 1, id = 2075, quantity = 1, source = corpse }, { type = 1, id = 2589, quantity = 2, source = corpse } }
	Fire("LOOT_READY", false)
	Fire("CHAT_MSG_LOOT", "You receive loot: " .. ItemLink(2075) .. ".", "Lefthy")
	Fire("CHAT_MSG_LOOT", "You receive loot: " .. ItemLink(2589) .. "x2.", "Lefthy")
	Fire("CHAT_MSG_LOOT", "You receive item: " .. ItemLink(1155) .. ".", "Lefthy")
	Fire("CHAT_MSG_LOOT", "Anna receives loot: " .. ItemLink(19019) .. ".", "Anna")
	Fire("CHAT_MSG_LOOT", SECRET, "Lefthy")
	Advance(0.3)
	LOOT = {}
	check(seq() == "=;i;2075;Priest's Mace l;2075;1;2;l;116 =;i;1155;Rod of the Sleepwalker l;1155;1;3;p",
		"loot, green and better: looted from the corpse the loot window said, pushed (a reward); not white, "
		.. "not someone else's, not a secret, got " .. seq())
	listen()
	Advance(6)
	Fire("CHAT_MSG_LOOT", "You receive loot: " .. ItemLink(6125) .. "x3.", "Lefthy")
	Advance(0.3)
	check(seq() == "=;i;6125;Brawler's Pants l;6125;3;2;l", "the loot window long gone: no corpse; the count, got " .. seq())
	-- An item the game hasn't cached yet: its quality from the link's colour (Forever's links: |cff...).
	listen()
	Fire("CHAT_MSG_LOOT", "You receive loot: |cff0070dd|Hitem:90020::::::::20:::::|h[Unseen Blade]|h|r.", "Lefthy")
	Fire("CHAT_MSG_LOOT", "You receive loot: |cffffffff|Hitem:90021::::::::20:::::|h[Unseen Rag]|h|r.", "Lefthy")
	Advance(0.3)
	check(seq() == "=;i;90020;Unseen Blade l;90020;1;3;l", "an item not cached yet: its quality from the link's colour (blue: written; white: not), got " .. seq())

	-- Gathering: the spell, then the loot window within 1.5 s; the node (a game object, the skinned creature).
	listen()
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-5", 2575)
	LOOT = { { type = 1, id = 2770, quantity = 2, source = "GameObject-0-1-0-1-1731-000000D1" },
		{ type = 1, id = 2835, quantity = 1, source = "GameObject-0-1-0-1-1731-000000D1" }, { type = 2, source = "GameObject-0-1-0-1-1731-000000D1" } }
	Fire("LOOT_READY", true)
	Fire("LOOT_READY", true)
	Advance(2)
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-6", 2575)
	Fire("LOOT_READY", true)
	Advance(0.3)
	check(seq() == "h;o;1731;2770:2;2835:1", "ore: the node and each item with its count (one field each); each node once, got " .. seq())
	listen()
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-7", 2366)
	LOOT = { { type = 1, id = 2447, quantity = 1, source = "GameObject-0-1-0-1-1617-000000D2" } }
	Fire("LOOT_READY", true)
	Advance(2)
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-8", 8613)
	LOOT = { { type = 1, id = 2318, quantity = 1, source = "Creature-0-1-0-1-113-000000D3" } }
	Fire("LOOT_READY", true)
	Advance(2)
	LOOT, LOOT_FISHING = { { type = 1, id = 6303, quantity = 1, source = "GameObject-0-1-0-1-35591-000000D4" } }, true
	Fire("LOOT_READY", true)
	Advance(2)
	LOOT = { { type = 1, id = 6303, quantity = 2, source = "GameObject-0-1-0-1-35591-000000D6" } } -- (the next cast's bobber)
	Fire("LOOT_READY", true)
	Advance(2)
	LOOT_FISHING = false
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-9", 2366)
	Advance(2)
	LOOT = { { type = 1, id = 2447, quantity = 1, source = "GameObject-0-1-0-1-1617-000000D5" } }
	Fire("LOOT_READY", true)
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", SECRET, SECRET)
	Advance(0.3)
	LOOT = {}
	check(seq() == "h;h;1617;2447:1 h;s;113;2318:1 h;f;;6303:1 h;f;;6303:2",
		"herbs (h), skinning (s: the creature), fishing (f: no node, the loot's source is the bobber; each cast once); a loot window "
		.. "2 s after the spell isn't a node's, got " .. seq())

	-- A rank not in the list is known by its name. The listed spells' names may not be loaded when
	-- they're first asked (C_Spell.GetSpellName answers nothing): asked again once they come
	-- (SPELLS_CHANGED), else on a miss at most every 10 s; once known, never again.
	local LISTED = { [2366] = true, [2368] = true, [3570] = true, [11993] = true, [2575] = true, [2576] = true, [3564] = true,
		[10248] = true, [8613] = true, [8617] = true, [8618] = true, [10768] = true }
	local spellNames, asked = { [133] = "Fireball" }, 0
	C_Spell.GetSpellName = function(id) if LISTED[id] then asked = asked + 1 end return spellNames[id] end
	listen()
	for i = 1, 20 do
		Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-F" .. i, 133)
		Advance(0.2)
	end
	local first = asked
	spellNames[2366], spellNames[2575], spellNames[8613], spellNames[99001] = "Herb Gathering", "Mining", "Skinning", "Mining"
	Fire("SPELLS_CHANGED")
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-13", 99001) -- (Mining, a rank of a later build)
	LOOT = { { type = 1, id = 2770, quantity = 3, source = "GameObject-0-1-0-1-1731-000000D7" } }
	Fire("LOOT_READY", true)
	Advance(0.3)
	local known = asked
	for i = 1, 20 do
		Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-G" .. i, 133)
		Advance(0.6)
	end
	LOOT, C_Spell.GetSpellName = {}, nil
	check(seq() == "h;o;1731;2770:3", "a rank not listed, by its name: the names asked again once they came, got " .. seq())
	check(first <= 12 and known <= 24 and asked == known, "the names asked at most every 10 s while missing (" .. first
		.. "), then once more (" .. known .. "), never again once known (" .. asked .. ")")
end

---------------------------------------------------------------------------
section("Echoes capture: the group")
---------------------------------------------------------------------------
do
	anna("H2") -- (a friend with LefthyTools, through Beacon: known on its next tick)
	Advance(2)
	listen()
	GROUP, GROUP_MEMBERS = "party", 3
	PARTY.party1, PARTY.party2 = { guid = "Player-1-11" }, { guid = "Player-1-77" }
	Fire("GROUP_ROSTER_UPDATE")
	Fire("GROUP_ROSTER_UPDATE")
	Advance(2)
	Fire("GROUP_ROSTER_UPDATE")
	Advance(2)
	check(seq() == "g;3;1;Player-1-11:Anna-Realmy", "a group: its size, the others, each LefthyTools friend as GUID:Name-Realm; only changes, got " .. seq())
	check(LefthyToolsEchoesDB.friends["Player-1-11"] == "Anna-Realmy", "the friend is remembered")
	-- Beacon off: the friend is still named (remembered).
	LT:SetModuleEnabled("beacon", false)
	listen()
	GROUP_MEMBERS, PARTY.party2 = 2, nil
	Fire("GROUP_ROSTER_UPDATE")
	Advance(2)
	check(seq() == "g;2;0;Player-1-11:Anna-Realmy", "Beacon off: the friend remembered, got " .. seq())
	LT:SetModuleEnabled("beacon", true)
	listen()
	PARTY.party1 = { guid = SECRET }
	Fire("GROUP_ROSTER_UPDATE")
	Advance(2)
	GROUP, GROUP_MEMBERS, PARTY.party1 = "none", 0, nil
	Fire("GROUP_ROSTER_UPDATE")
	Advance(2)
	check(seq() == "g;2;1 g;0;0", "a member whose GUID is secret: one of the others; left the group: g 0 0, got " .. seq())
	-- A friend Beacon learns of only after the group was looked at (not remembered yet): named
	-- within 15 s, without another roster change.
	LT:SetModuleEnabled("beacon", false)
	LefthyToolsEchoesDB.friends["Player-1-11"] = nil
	listen()
	GROUP, GROUP_MEMBERS, PARTY.party1 = "party", 2, { guid = "Player-1-11" }
	Fire("GROUP_ROSTER_UPDATE")
	Advance(2)
	LT:SetModuleEnabled("beacon", true)
	anna("H2")
	Advance(16)
	check(seq() == "g;2;1 g;2;0;Player-1-11:Anna-Realmy", "a friend Beacon learns of later: named then, got " .. seq())
	GROUP, GROUP_MEMBERS, PARTY.party1 = "none", 0, nil
	Fire("GROUP_ROSTER_UPDATE")
	Advance(2)

	-- A friend's realm the way my character's key has it (GetRealmName: "Realmy Vale"), whatever form
	-- the game gave it in ("RealmyVale"); another realm's as Battle.net shows it ("Stone Realm").
	local realmName, bob = GetRealmName, BN_FRIENDS[2][1]
	GetRealmName = function() return "Realmy Vale" end
	KNOWN_PLAYERS["Player-1-11"], KNOWN_PLAYERS["Player-1-12"] = { "Anna", "RealmyVale" }, { "Bob", "StoneRealm" }
	bob.realmName, bob.realmDisplayName = "StoneRealm", "Stone Realm"
	anna("H2")
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "H2", "WHISPER", 12)
	Advance(2)
	listen()
	GROUP, GROUP_MEMBERS, PARTY.party1, PARTY.party2 = "party", 3, { guid = "Player-1-11" }, { guid = "Player-1-12" }
	Fire("GROUP_ROSTER_UPDATE")
	Advance(2)
	local both = seq()
	-- Remembered in another form (from before), Beacon off: written, and kept, in my realm's.
	LT:SetModuleEnabled("beacon", false)
	LefthyToolsEchoesDB.friends["Player-1-11"] = "Anna-Realmy-Vale"
	listen()
	GROUP_MEMBERS, PARTY.party2 = 2, nil
	Fire("GROUP_ROSTER_UPDATE")
	Advance(2)
	LT:SetModuleEnabled("beacon", true)
	check(both == "g;3;0;Player-1-11:Anna-Realmy Vale;Player-1-12:Bob-Stone Realm" and seq() == "g;2;0;Player-1-11:Anna-Realmy Vale"
		and LefthyToolsEchoesDB.friends["Player-1-11"] == "Anna-Realmy Vale",
		"friends' realms as my own character's key writes them; another realm as Battle.net shows it, got " .. both .. " | " .. seq())
	GROUP, GROUP_MEMBERS, PARTY.party1 = "none", 0, nil
	Fire("GROUP_ROSTER_UPDATE")
	Advance(2)
	GetRealmName, bob.realmName, bob.realmDisplayName = realmName, "Realmy", nil
	KNOWN_PLAYERS["Player-1-11"], KNOWN_PLAYERS["Player-1-12"] = nil, nil
	LefthyToolsEchoesDB.friends["Player-1-11"], LefthyToolsEchoesDB.friends["Player-1-12"] = "Anna-Realmy", nil

	-- A roster that changes all the time (a raid: GROUP_ROSTER_UPDATE many times a second): looked
	-- at at most every 2 s. In combat only once its size changed; another member, same size, when the
	-- fight is over.
	local looks, members = 0, GetNumGroupMembers
	GetNumGroupMembers = function() looks = looks + 1 return members() end
	GROUP, GROUP_MEMBERS, PARTY.party1 = "party", 2, { guid = "Player-1-77" }
	Fire("GROUP_ROSTER_UPDATE")
	Advance(2)
	listen()
	looks = 0
	for _ = 1, 40 do
		Fire("GROUP_ROSTER_UPDATE")
		Advance(0.25)
	end
	local burst = looks
	EnterCombat()
	PARTY.party1 = { guid = "Player-1-11" }
	Fire("GROUP_ROSTER_UPDATE")
	Advance(5)
	local inCombat = seq()
	LeaveCombat()
	Advance(2.5)
	local over = seq()
	listen()
	EnterCombat()
	GROUP_MEMBERS, PARTY.party2 = 3, { guid = "Player-1-77" }
	Fire("GROUP_ROSTER_UPDATE")
	Advance(2.5)
	local grown = seq()
	LeaveCombat()
	GetNumGroupMembers = members
	check(burst <= 6, "a roster changing every tick for 10 s: looked at at most every 2 s, " .. burst .. " times (40 before)")
	check(inCombat == "" and over == "g;2;0;Player-1-11:Anna-Realmy" and grown == "g;3;1;Player-1-11:Anna-Realmy",
		"in combat: another member (same size) waits for the fight's end; a new size doesn't, got " .. inCombat .. " | " .. over .. " | " .. grown)
	GROUP, GROUP_MEMBERS, PARTY.party1, PARTY.party2 = "none", 0, nil, nil
	Fire("GROUP_ROSTER_UPDATE")
	Advance(2)
end

---------------------------------------------------------------------------
section("Echoes capture: gear, AFK, reputation, professions, the hearthstone, honor")
---------------------------------------------------------------------------
do
	listen()
	EQUIPPED[16] = 19019
	Fire("PLAYER_EQUIPMENT_CHANGED", 16, true)
	GEAR_LINKS[7] = "|cff1eff00|Hitem:6125:15:0:0:0:0:1199:0:20|h[Brawler's Pants]|h|r"
	Fire("PLAYER_EQUIPMENT_CHANGED", 7, true)
	Advance(0.3)
	EQUIPPED[16] = nil
	Fire("PLAYER_EQUIPMENT_CHANGED", 16, false)
	Fire("PLAYER_EQUIPMENT_CHANGED", 7, true)
	Advance(0.3)
	check(seq() == "=;i;19019;Thunderfury G;16;19019;0;0 G;7;6125;15;1199 G;16;0",
		"gear: slot, item, enchant, suffix (the name once per page); taken off: item 0; only changes, got " .. seq())

	listen()
	afk(true)
	Advance(0.3)
	UnitIsAFK = function() return SECRET end
	afk(false)
	Advance(0.3)
	UnitIsAFK = baseAFK
	afk(false)
	Advance(0.3)
	check(seq() == "f;1 f;0", "AFK: f 1, f 0; a secret answer keeps the last state, got " .. seq())

	-- Reputation: the first scan is the baseline (no lines); then each change.
	FACTIONS = { { id = 1118, header = true, reaction = 0 }, { id = 72, reaction = 5 }, { id = 47, reaction = 5 } }
	listen()
	Fire("UPDATE_FACTION")
	Advance(0.3)
	check(seq() == "" and cap().reps[72] == 5 and cap().repsKnown, "reputation: the first scan is the baseline, got " .. seq())
	FACTIONS[2].reaction = 6
	Fire("FACTION_STANDING_CHANGED", 72, 6)
	Advance(0.3)
	FACTIONS[3].reaction = 6
	FACTIONS[4] = { id = 69, reaction = 4 }
	Fire("UPDATE_FACTION")
	Advance(0.3)
	check(seq() == "R;72;6", "a standing changed: R with the faction and the standing; a rescan waits 10 s, got " .. seq())
	Advance(10)
	check(seq() == "R;72;6 R;47;6" and cap().reps[69] == 4,
		"the rescan (UPDATE_FACTION): what changed; a faction listed for the first time is a baseline, got " .. seq())
	-- Under closed headers: one changes (FACTION_STANDING_CHANGED names it: R), then the headers open
	-- (listed for the first time: no lines, not even for one never seen before).
	listen()
	FACTIONS[5] = { id = 21, reaction = 6, collapsed = true }
	FACTIONS[6] = { id = 93, reaction = 4, collapsed = true }
	Fire("FACTION_STANDING_CHANGED", 21, 6)
	Advance(0.3)
	FACTIONS[5].collapsed, FACTIONS[6].collapsed = nil, nil
	Fire("UPDATE_FACTION")
	Advance(10.3)
	check(seq() == "R;21;6" and cap().reps[93] == 4,
		"a faction under a closed header changed: R; the headers opened: nothing more, got " .. seq())

	listen()
	SKILLS[186] = { 1, 75 }
	Fire("SKILL_LINES_CHANGED")
	Advance(0.3)
	SKILLS[186] = { 2, 75 }
	Fire("SKILL_LINES_CHANGED")
	Advance(0.3)
	SKILLS[186] = { 0, 0 }
	Fire("SKILL_LINES_CHANGED")
	Advance(0.3)
	check(seq() == "s;186;1;75 s;186;2;75 s;186;0;0", "a profession: skill line, rank, maximum; unlearned: 0, got " .. seq())

	listen()
	BIND = "Inn; Goldshire"
	Fire("HEARTHSTONE_BOUND")
	Advance(0.3)
	Fire("HEARTHSTONE_BOUND")
	Advance(0.3)
	check(seq() == "H;Inn%3B Goldshire", "the hearthstone bound: the place (escaped), once, got " .. seq())

	listen()
	HONOR = 2
	Fire("PLAYER_PVP_KILLS_CHANGED", "player")
	Advance(0.3)
	HONOR = 3
	Fire("PLAYER_PVP_KILLS_CHANGED", "player")
	Advance(0.3)
	check(seq() == "p;2 p;1", "honorable kills: how many more, got " .. seq())

	-- Gear at a login: a worn item whose link isn't there yet (GetInventoryItemID says one is) isn't
	-- taken off: looked at again every second, 10 times; then the item alone, if it isn't the one
	-- written before. Only an empty slot is taken off.
	EQUIPPED[16], EQUIPPED[1] = 19019, 1155
	Fire("PLAYER_EQUIPMENT_CHANGED", 16, true)
	Fire("PLAYER_EQUIPMENT_CHANGED", 1, true)
	Advance(0.3)
	listen()
	LINK_PENDING[16], LINK_PENDING[5], LINK_PENDING[1] = true, true, true
	EQUIPPED[5], GEAR_LINKS[7] = 2075, nil -- (put on and taken off while logged out)
	LT:SetModuleEnabled("echoes", false)
	LT:SetModuleEnabled("echoes", true)
	Fire("PLAYER_ENTERING_WORLD", true, false)
	Advance(2.5)
	local early = count("^G;")
	LINK_PENDING[16] = nil
	Advance(12)
	check(early == 1 and count("^G;7;0$") == 1 and count("^G;16;") == 0 and count("^G;1;") == 0 and count("^G;5;2075$") == 1 and count("^G;") == 2,
		"a login, links not there yet: not taken off; the same item once its link comes: nothing; a link that never comes: the item "
		.. "alone if it changed; an empty slot: taken off, got " .. seq())
	listen()
	LINK_PENDING[5], LINK_PENDING[1], EQUIPPED[5], EQUIPPED[1] = nil, nil, nil, nil
	Fire("PLAYER_EQUIPMENT_CHANGED", 5, false)
	Fire("PLAYER_EQUIPMENT_CHANGED", 1, false)
	Advance(0.3)
	check(seq() == "G;5;0 G;1;0" or seq() == "G;1;0 G;5;0", "(taken off again, got " .. seq() .. ")")
end

---------------------------------------------------------------------------
section("Echoes capture: battlegrounds, collections, flights")
---------------------------------------------------------------------------
do
	at(500, 500)
	Advance(1.2)
	listen()
	loading(function() INSTANCE = { name = "Warsong Gulch", type = "pvp", id = 489 } end)
	Advance(60)
	Fire("PVP_MATCH_COMPLETE", 1, 600)
	Advance(0.3)
	Fire("PVP_MATCH_COMPLETE", 1, 600)
	Advance(0.3)
	loading(function() INSTANCE = nil end)
	check(seq():find("^@;0;500;500;f;i b;489;e b;489;w;600 @;0;500;500;f;o b;489;x;6%d$") ~= nil,
		"a battleground (positions inside): entered, won with its length, left after a minute, got " .. seq())
	listen()
	loading(function() INSTANCE = { name = "Warsong Gulch", type = "pvp", id = 489 } end)
	BG_WINNER = 0
	Advance(6)
	BG_WINNER = nil
	loading(function() INSTANCE = nil end)
	check(seq():find("b;489;l;%d+ ") ~= nil, "who won from GetBattlefieldWinner: lost (the Horde), got " .. seq())
	-- Logged out inside after a minute, logged in outside 5 minutes later: it lasted about a minute.
	listen()
	loading(function() INSTANCE = { name = "Warsong Gulch", type = "pvp", id = 489 } end)
	Advance(60)
	LT:SetModuleEnabled("echoes", false)
	INSTANCE = nil
	Advance(300)
	LT:SetModuleEnabled("echoes", true)
	Fire("PLAYER_ENTERING_WORLD", true, false)
	Advance(2)
	local lasted = tonumber(seq():match("o;1 .*b;489;x;(%d+)"))
	check(lasted and lasted >= 55 and lasted <= 61, "left while logged out: how long until the logout, got " .. seq())

	listen()
	Fire("NEW_MOUNT_ADDED", 6)
	Fire("NEW_PET_ADDED", "BattlePet-0-000000000001")
	Fire("NEW_TOY_ADDED", 1234)
	Fire("ACHIEVEMENT_EARNED", 6, false)
	Fire("ACHIEVEMENT_EARNED", 7, true)
	Fire("NEW_RECIPE_LEARNED", 2538)
	Advance(0.3)
	check(seq() == "n;m;6 n;p;40 n;t;1234 n;a;6 n;r;2538", "new mount, pet (its species), toy, achievement (not one earned before), recipe, got " .. seq())

	listen()
	TAXI_MAP_NODES = {
		{ nodeID = 2, name = "Stormwind, Elwynn", state = 0, slotIndex = 1, position = CreateVector2D(0.5, 0.5) },
		{ nodeID = 4, name = "Sentinel Hill, Westfall", state = 1, slotIndex = 3, position = CreateVector2D(0.45, 0.6) },
	}
	TAXI_NODES[3] = "Sentinel Hill, Westfall"
	TakeTaxiNode(3)
	Advance(0.3)
	check(seq() == "F;2;4", "a flight path picked: from and to taxi nodes, got " .. seq())
end

---------------------------------------------------------------------------
section("Echoes capture: nothing in combat that must wait")
---------------------------------------------------------------------------
do
	PLAYED.requests, chatGot = 0, 0
	EnterCombat()
	listen()
	Fire("PLAYER_ENTERING_WORLD", true, false)
	EQUIPPED[1] = 2075
	Fire("PLAYER_EQUIPMENT_CHANGED", 1, true)
	SKILLS[186] = { 3, 75 }
	Fire("SKILL_LINES_CHANGED")
	FACTIONS[2].reaction = 7
	Fire("FACTION_STANDING_CHANGED", 72, 7)
	Advance(5)
	check(PLAYED.requests == 0 and chatHas and count("^[GsR];") == 0,
		"in combat: no /played (no chat frame touched), no gear, profession or reputation read, got " .. seq())
	check(seq():find("^@;0;500;500;f;s z;1429;Goldshire o;1") ~= nil, "(the login's path and session lines don't wait)")
	LeaveCombat()
	Advance(1.3) -- (gear, professions, reputation, /played: one a tick)
	check(PLAYED.requests == 1 and not chatHas, "the fight over: /played asked")
	Advance(1)
	check(chatHas and chatGot == 0, "and its answer kept from the chat frames")
	check(count("^G;1;2075;0;0$") == 1 and count("^s;186;3;75$") == 1 and count("^R;72;7$") == 1, "and what waited is written, got " .. seq())
end

---------------------------------------------------------------------------
section("Echoes capture: a /reload")
---------------------------------------------------------------------------
do
	-- Inside a dungeon, in a group with a friend, AFK known, gear and XP written.
	loading(function() INSTANCE, STATE.inInstance = { name = "The Deadmines", type = "party", id = 36, difficulty = 1 }, true end)
	GROUP, GROUP_MEMBERS, PARTY.party1 = "party", 2, { guid = "Player-1-11" }
	Fire("GROUP_ROSTER_UPDATE")
	Advance(1)
	PLAYED.requests = 0
	listen()
	-- /reload: the loading screen begins, PLAYER_LOGOUT (it can't be told from logging out), the
	-- interface loads again (the capture forgets what it held; E.state comes back with the open page).
	Fire("PLAYER_LEAVING_WORLD")
	Fire("PLAYER_LOGOUT")
	C.Reset()
	Fire("PLAYER_ENTERING_WORLD", false, true)
	Advance(2)
	check(seq() == "o;0 @;36;;;f;l z;1429;Goldshire o;1", "a /reload: o0, then an anchor (why l), the zone, o1; nothing "
		.. "written again (the dungeon, the group, gear, XP: kept per character), got " .. seq())
	check(PLAYED.requests == 0, "and no /played (not a login)")
	-- A /reload inside where the game can't say which instance this is (GetInstanceInfo fails), or
	-- what kind (a secret): the dungeon isn't left; read again a few seconds later, still the same.
	for _, unreadable in ipairs({ "info", "kind" }) do
		listen()
		INSTANCE.unreadable = unreadable == "info" or nil
		INSTANCE.type = unreadable == "kind" and SECRET or "party"
		Fire("PLAYER_LEAVING_WORLD")
		Fire("PLAYER_LOGOUT")
		C.Reset()
		Fire("PLAYER_ENTERING_WORLD", false, true)
		Advance(2)
		INSTANCE.unreadable, INSTANCE.type = nil, "party"
		Advance(6)
		check(seq() == "o;0 @;36;;;f;l z;1429;Goldshire o;1", "a /reload inside, the instance's " .. unreadable
			.. " not readable: nothing left; readable again: nothing new, got " .. seq())
	end
	-- Into another dungeon whose ID can't be read at first: written once it can (looked at every 5 s).
	listen()
	loading(function() INSTANCE = { name = "Shadowfang Keep", type = "party", id = 33, difficulty = 1, unreadable = true } end)
	Advance(3)
	INSTANCE.unreadable = nil
	Advance(5)
	check(seq() == "@;36;;;f;l d;x;36;1 d;e;33;1", "another dungeon, its ID readable only later: left and entered then, got " .. seq())
	loading(function() INSTANCE = { name = "The Deadmines", type = "party", id = 36, difficulty = 1 } end)
	Advance(1)
	-- Left the dungeon while logged out: at the next login it's left.
	listen()
	LT:SetModuleEnabled("echoes", false)
	INSTANCE, STATE.inInstance = nil, false
	at(500, 500)
	LT:SetModuleEnabled("echoes", true)
	Fire("PLAYER_ENTERING_WORLD", true, false)
	Advance(2)
	check(seq():find("^o;0 @;0;500;500;f;s z;1429;Goldshire o;1 d;x;36;1") ~= nil, "logged in outside: the dungeon left, got " .. seq())
	GROUP, GROUP_MEMBERS, PARTY.party1 = "none", 0, nil
	Fire("GROUP_ROSTER_UPDATE")
	Advance(1)
	-- A /reload where the game doesn't say the position yet, then a loading screen before it does:
	-- still the /reload's anchor and session (o1).
	listen()
	Fire("PLAYER_LEAVING_WORLD")
	Fire("PLAYER_LOGOUT")
	C.Reset()
	STATE.inInstance = true
	Fire("PLAYER_ENTERING_WORLD", false, true)
	Advance(1)
	Fire("PLAYER_LEAVING_WORLD")
	STATE.inInstance = false
	Fire("PLAYER_ENTERING_WORLD", false, false)
	Advance(1)
	check(seq() == "o;0 @;0;500;500;f;l z;1429;Goldshire o;1", "a /reload, a loading screen before its anchor: the session goes on, got " .. seq())
end

---------------------------------------------------------------------------
section("Echoes capture: with Chronicle, the Bestiary and Beacon off")
---------------------------------------------------------------------------
do
	for _, key in ipairs({ "chronicle", "bestiary", "beacon" }) do LT:SetModuleEnabled(key, false) end
	Advance(1) -- (the start point needs a second since the last line)
	listen()
	walk(500, 450)
	halt()
	MOBS.nameplate7 = { name = "Defias Bandit", level = 12, class = "normal", guid = "Creature-0-1-0-1-116-000000E1" }
	Fire("NAME_PLATE_UNIT_ADDED", "nameplate7")
	MOBS.nameplate7 = nil
	Fire("PARTY_KILL", "Player-1-0", "Creature-0-1-0-1-116-000000E1")
	LOOT = { { type = 1, id = 2075, quantity = 1, source = "Creature-0-1-0-1-116-000000E1" } }
	Fire("LOOT_READY", false)
	Fire("CHAT_MSG_LOOT", "You receive loot: " .. ItemLink(2075) .. ".", "Lefthy")
	LOOT = {}
	GROUP, GROUP_MEMBERS, PARTY.party1 = "party", 2, { guid = "Player-1-11" }
	Fire("GROUP_ROSTER_UPDATE")
	Advance(0.5)
	local w1, w2 = seq(true):match("^,0,0 ,0,%-(%d+) ,0,%-(%d+) k;116;12;n;m l;2075;1;2;l;116 g;2;0;Player%-1%-11:Anna%-Realmy$")
	check(w1 and tonumber(w1) >= 25 and tonumber(w1) + tonumber(w2) == 50,
		"the path (a point past 25 yd, the stop), kills, loot and friends without them, got " .. seq())
	GROUP, GROUP_MEMBERS, PARTY.party1 = "none", 0, nil
	Fire("GROUP_ROSTER_UPDATE")
	Advance(0.5)
	for _, key in ipairs({ "chronicle", "bestiary", "beacon" }) do LT:SetModuleEnabled(key, true) end
end

---------------------------------------------------------------------------
section("Echoes capture: the beta doesn't record")
---------------------------------------------------------------------------
do
	listen()
	restart("beta")
	local ended = seq()
	listen()
	walk(500, 400)
	halt()
	Fire("PARTY_KILL", "Player-1-0", "Creature-0-1-0-1-116-000000E2")
	Fire("PLAYER_LEVEL_UP", 20)
	Fire("PLAYER_ENTERING_WORLD", true, false)
	TakeTaxiNode(3)
	Advance(2)
	check(ended == "o;0" and #heard == 0 and not E.recording, "on the beta: the session ends, then nothing is recorded, got " .. seq())
end

---------------------------------------------------------------------------
section("Echoes capture: a whole session, read back")
---------------------------------------------------------------------------
do
	-- A login, a walk, a fight, loot, a quest, a ride, the hearthstone, a dungeon, a logout. On a
	-- page of its own (the last one's last line more than 10 minutes old): a page starting halfway
	-- would start its times from its header.
	Advance(601)
	at(500, 500)
	QUESTS = { { id = 176, title = "Wanted: \"Hogger\"", objectives = {} } }
	MOBS.nameplate3 = { name = "Hogger", level = 11, class = "elite", guid = "Creature-0-1-0-1-448-000000F1" }
	listen()
	restart("release")
	Fire("PLAYER_ENTERING_WORLD", true, false)
	Advance(3)
	walk(540, 470)
	halt()
	Fire("QUEST_ACCEPTED", 176)
	Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
	EnterCombat()
	Advance(4)
	Fire("PARTY_KILL", "Player-1-0", "Creature-0-1-0-1-448-000000F1")
	LeaveCombat()
	LOOT = { { type = 1, id = 1155, quantity = 1, source = "Creature-0-1-0-1-448-000000F1" } }
	Fire("LOOT_READY", false)
	Fire("CHAT_MSG_LOOT", "You receive loot: " .. ItemLink(1155) .. ".", "Lefthy")
	LOOT = {}
	Advance(2)
	TRAVEL.mounted = true
	walk(640, 420, 14)
	halt()
	TRAVEL.mounted = false
	Fire("QUEST_TURNED_IN", 176, 1450, 1200)
	Advance(2)
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-10", 8690)
	Advance(10)
	at(300, 700)
	Advance(1.2)
	loading(function() INSTANCE, STATE.inInstance = { name = "The Deadmines", type = "party", id = 36, difficulty = 1 }, true end)
	Advance(5)
	loading(function() INSTANCE, STATE.inInstance = nil, false; at(310, 700) end)
	Advance(2)
	Fire("PLAYER_LOGOUT")
	listening = false
	MOBS.nameplate3, QUESTS = nil, {}

	-- Read back as the format says (docs/echoes.md): every line's dt adds up to the time it was
	-- written, every point's deltas to the position written.
	local list = mine()
	local t, n, w, c = list[1].t - tonumber(list[1].line:match("^.(%d+)")), nil, nil, nil
	local ok, bad = true, nil
	for _, h in ipairs(list) do
		local line = h.line
		if line:find("^%d") then
			local dt, dn, dw = line:match("^(%d+),(%-?%d+),(%-?%d+)$")
			t, n, w = t + tonumber(dt), n + tonumber(dn), w + tonumber(dw)
		else
			t = t + tonumber(line:match("^.(%d+)"))
			if h.kind == "@" then
				local f = split(line)
				c, n, w = tonumber(f[2]), tonumber(f[3]), tonumber(f[4])
			end
		end
		if t ~= h.t or n ~= h.n or w ~= h.w or c ~= h.c then
			ok, bad = false, bad or line
		end
	end
	check(ok, "a whole session: the times and positions add up, line after line (wrong from " .. tostring(bad) .. ")")
	local kinds = {}
	for i, h in ipairs(list) do kinds[i] = h.kind or "." end
	kinds = table.concat(kinds)
	check(kinds:find("^@zo") and kinds:find("=a") and kinds:find("=k=?l") and kinds:find("m") and kinds:find("Q")
		and kinds:find("@", 2, true) and kinds:find("d") and kinds:find("o$"), "every part of it is there, got " .. kinds)

	-- For the exporter: the page and what it must read from it, as
	-- "<line>\t<absolute time>\t<continent>,<north>,<west>" (a tool outside this repo parses it).
	local text, expect = {}, {}
	local t0 = list[1].t - tonumber(list[1].line:match("^.(%d+)"))
	text[1] = "E1;1a2b3c4d;9f3a61c2;1;" .. t0 .. ";enUS;70532;test"
	text[2] = "C0;Lefthy-Realmy;Lefthy;Player-1-0;ROGUE;Human;3;19;Alliance"
	for i, h in ipairs(list) do
		text[#text + 1] = h.line
		expect[i] = h.line .. "\t" .. h.t .. "\t" .. tostring(h.c) .. "," .. tostring(h.n) .. "," .. tostring(h.w)
	end
	ECHOES_CAPTURE_SESSION = { page = table.concat(text, "\n") .. "\n", expect = table.concat(expect, "\n") }
end

---------------------------------------------------------------------------
-- Put back what this file changed
---------------------------------------------------------------------------

restart("beta")
LT.world = keep.world
listening = false
for name, value in pairs(was) do _G[name] = value or nil end
C_QuestLog.IsQuestFlaggedCompleted = questFlagged
for id in pairs(newItems) do ITEMS[id] = nil end
UNIT_SPEED, FORM_ID, GROUP_MEMBERS, BIND, HONOR, BG_WINNER, PET_GUID = nil, nil, nil, nil, nil, nil, nil
PLAYED, QUESTS_DONE, FACTIONS, SKILLS, GEAR_LINKS, LINK_PENDING = nil, nil, nil, nil, nil, nil
chat:UnregisterEvent("TIME_PLAYED_MSG")
ChatFrame3, NUM_CHAT_WINDOWS = nil, chatWindows
PLAYER_MAP, PLAYER_POS, EQUIPPED, QUESTS, INSTANCE, GROUP = keep.map, keep.pos, keep.equipped, keep.quests, keep.instance, keep.group
LOOT, LOOT_FISHING, TAXI_MAP_NODES = keep.loot, keep.fishing, keep.taxiNodes
for k, v in pairs(keep.travel) do TRAVEL[k] = v end
for k, v in pairs(keep.state) do STATE[k] = v end
for k, v in pairs(keep.xp) do XP[k] = v end
