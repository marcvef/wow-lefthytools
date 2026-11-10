-- Lodestar: the quest browser's two views (Views.lua): My quests (my quest log organised: ready to
-- turn in first, then by zone with mine first and the nearest first, by level or by storyline; a
-- line per quest with its chain's "2/4", its first objective not done or "Ready to turn in", where
-- it's turned in; a click opens it in the window, a right-click sets the map pin; "Continue your
-- storylines": the chains I've started whose next step I can take now, at most 8) and the level path
-- (the zones with something for my levels or friends there, all of them with a toggle, as bars
-- across the levels, shaded per level, my level, sorted by what there is for my level, a click opens
-- the zone). Registering with the window's registry once it's there (the module's enable), building
-- on the registry's build(parent), the counts made a slice a frame and only again when the data or
-- my progress changes, events only while a view is shown, moving, pools, no data, the controller.
-- Data.lua and Engine.lua are in the build: the quests go in through Q.SetTestData. The window's
-- registry (Q.RegisterBrowserView) and Q.SelectZone come from the big window's part in parallel:
-- here the registry is a stand-in that records what's registered, put in for the checks and the
-- real one (if there is one) put back; Q.OpenBrowser, Q.SelectZone and Q.Waypoint are recorders
-- while this file runs. The data part's Q.Objectives and the new Q.InRange (in my log; else minimum
-- level reached, not grey, at most Q.RANGE_RED levels above me) are stand-ins with the contract's
-- meaning (the data part builds them in parallel; its own tests check them).
-- Whatever it replaces is put back at its end.
-- Needs: no other file.

local suite = ...
local check, section, ns, LT = suite.check, suite.section, suite.ns, suite.LT
local Q = ns.Lodestar
local M = LT:GetModule("lodestar")

local replaced = {}
local function Replace(name, fn)
	if replaced[name] == nil then
		replaced[name] = Q[name] or false
	end
	Q[name] = fn
end

local waited = 0 -- (the clock goes on by whole seconds, for the files after this one)
local function Wait(s)
	Advance(s)
	waited = waited + s
end

local function plain(text)
	return (((text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")):match("^%s*(.-)%s*$"))
end

local function tipHas(text)
	for _, line in ipairs(TOOLTIP.lines) do
		if plain(line):find(text, 1, true) then return true end
	end
	return false
end

---------------------------------------------------------------------------
-- The world: four zones of my side on two continents, one of the Horde
---------------------------------------------------------------------------

local ELWYNN, WESTFALL, REDRIDGE, DUROTAR, DARKSHORE = 1429, 1436, 1433, 1411, 1439
local EK, KALIMDOR = 1415, 1414
local savedNames = { [REDRIDGE] = MAP_NAMES[REDRIDGE], [DUROTAR] = MAP_NAMES[DUROTAR], [DARKSHORE] = MAP_NAMES[DARKSHORE] }
MAP_NAMES[REDRIDGE], MAP_NAMES[DUROTAR], MAP_NAMES[DARKSHORE] = "Redridge Mountains", "Durotar", "Darkshore"

local function Npc(id, name, map, x, y) return { kind = "npc", id = id, name = name, points = { { map = map, x = x, y = y } } } end
local DUGHAN, GRYAN, KAT = Npc(1, "Marshal Dughan", ELWYNN, 0.42, 0.66), Npc(2, "Gryan Stoutmantle", WESTFALL, 0.56, 0.47), Npc(3, "Magistrate Solomon", REDRIDGE, 0.3, 0.45)
local SALDEAN, THERYLUNE = Npc(4, "Farmer Saldean", WESTFALL, 0.56, 0.31), Npc(5, "Gwennyth Bly'Leggonde", DARKSHORE, 0.38, 0.44)
local function Quest(id, title, level, minLevel, zone, extra)
	local q = { id = id, title = title, level = level, minLevel = minLevel, zone = zone, starts = { DUGHAN }, ends = {} }
	for k, v in pairs(extra or {}) do q[k] = v end
	return q
end
local QUESTS_DATA = {
	-- Elwynn: a chain done, a chain with a step ready to turn in, a grey one alone.
	[1001] = Quest(1001, "A Threat Within", 2, 1, ELWYNN),
	[1002] = Quest(1002, "Kobold Camp Cleanup", 3, 1, ELWYNN, { pre = { 1001 } }),
	[1003] = Quest(1003, "Investigate Echo Ridge", 5, 3, ELWYNN, { pre = { 1002 } }),
	[1010] = Quest(1010, "Princess Must Die", 6, 4, ELWYNN),
	[1011] = Quest(1011, "Bounty on Murlocs", 7, 5, ELWYNN, { pre = { 1010 }, ends = { DUGHAN } }),
	[1020] = Quest(1020, "Wolves Across the Border", 4, 2, ELWYNN),
	-- Westfall: a long chain on into Darkshore (its second step in my log), a chain whose next step
	-- I can take, one alone in my log, one alone too high.
	[1100] = Quest(1100, "The People's Militia", 10, 9, WESTFALL, { starts = { GRYAN }, ends = { GRYAN } }),
	[1101] = Quest(1101, "The Defias Brotherhood", 12, 10, WESTFALL, { pre = { 1100 }, starts = { GRYAN }, ends = { GRYAN } }),
	[1102] = Quest(1102, "The Coast Isn't Clear", 14, 12, WESTFALL, { pre = { 1101 }, starts = { GRYAN } }),
	[1103] = Quest(1103, "Red Leather Bandanas", 16, 14, WESTFALL, { pre = { 1102 }, starts = { GRYAN } }),
	[1110] = Quest(1110, "Westfall Stew", 11, 9, WESTFALL, { starts = { SALDEAN } }),
	[1111] = Quest(1111, "Goretusk Liver Pie", 13, 10, WESTFALL, { pre = { 1110 }, starts = { SALDEAN } }),
	[1120] = Quest(1120, "Poor Old Blanchy", 12, 10, WESTFALL, { starts = { SALDEAN }, ends = { SALDEAN } }),
	[1121] = Quest(1121, "Keeper of the Flame", 18, 16, WESTFALL, { starts = { GRYAN } }),
	-- Redridge: a chain started whose next step is too high for me now.
	[1200] = Quest(1200, "Encroaching Gnolls", 17, 15, REDRIDGE, { starts = { KAT } }),
	[1201] = Quest(1201, "Assessing the Threat", 19, 16, REDRIDGE, { pre = { 1200 }, starts = { KAT } }),
	[1210] = Quest(1210, "Redridge Goulash", 15, 13, REDRIDGE, { starts = { KAT } }),
	-- Durotar: the Horde's.
	[1300] = Quest(1300, "Your Place in the World", 2, 1, DUROTAR, { faction = "Horde" }),
	[1301] = Quest(1301, "Cutting Teeth", 3, 1, DUROTAR, { faction = "Horde", pre = { 1300 } }),
	-- Darkshore: a chain of its own (its first step in my log, turned in at Westfall), and the
	-- Westfall chain's last step.
	[1400] = Quest(1400, "The Red Crystal", 12, 10, DARKSHORE, { starts = { THERYLUNE }, ends = { SALDEAN } }),
	[1401] = Quest(1401, "As Water Cascades", 14, 11, DARKSHORE, { pre = { 1400 } }),
	[1402] = Quest(1402, "The Absent Minded Prospector", 18, 15, DARKSHORE, { pre = { 1103 } }),
}
local ZONES = {
	{ map = ELWYNN, name = "Elwynn Forest", continent = EK, minLevel = 1, maxLevel = 10 },
	{ map = WESTFALL, name = "Westfall", continent = EK, minLevel = 9, maxLevel = 18 },
	{ map = REDRIDGE, name = "Redridge Mountains", continent = EK, minLevel = 15, maxLevel = 25 },
	{ map = DUROTAR, name = "Durotar", continent = KALIMDOR, minLevel = 1, maxLevel = 10 },
	{ map = DARKSHORE, name = "Darkshore", continent = KALIMDOR, minLevel = 11, maxLevel = 19 },
}

-- What the data part knows of the objectives (Q.Objectives; a stand-in while it's missing).
local OBJECTIVES = {
	[1101] = { { kind = "kill", id = 590, name = "Defias Looter", count = 10, sources = {
		{ kind = "npc", id = 590, name = "Defias Looter", points = { { map = WESTFALL, x = 0.45, y = 0.3, r = 0.05 } } } } } },
	[1120] = { { kind = "item", id = 2539, name = "Handful of Oats", count = 8, sources = {
		{ kind = "object", id = 300, name = "Oat Sack", chance = 100, points = { { map = WESTFALL, x = 0.6, y = 0.6, r = 0.04 } } } } } },
	[1400] = { { kind = "object", id = 400, name = "Red Crystal", count = 1, sources = {
		{ kind = "object", id = 400, name = "Red Crystal", points = { { map = DARKSHORE, x = 0.5, y = 0.2, r = 0.02 } } } } } },
}
-- (Always the stand-in: the test quests have no objectives in the data's own format; the data part's
-- Q.Objectives has its tests in lodestar_data.)
Replace("Objectives", function(id) return OBJECTIVES[id] or {} end)
-- The contract's Q.InRange (the data part's tests check the engine's own; here what the views do
-- with it): in my log; else my level reached, not grey, at most 4 levels above me (a level -1 / 0:
-- mine).
Replace("InRange", function(id)
	local q = Q.Quest(id)
	if not q then return false end
	if Q.Status(id) == "active" then return true end
	if Q.IsTrivial(id) then return false end
	local me = UnitLevel("player")
	if q.minLevel and q.minLevel > me then return false end
	local level = (q.level and q.level > 0) and q.level or me
	return level <= me + (Q.RANGE_RED or 4)
end)

-- My progress: completed quests and the quest log ({ id, ... } or { { id, complete } }), with the
-- quest log's objectives.
local LOG_OBJECTIVES = {
	[1101] = { { text = "Defias Looter slain: 2/10", type = "monster", numFulfilled = 2, numRequired = 10, finished = false } },
	[1120] = { { text = "Handful of Oats: 3/8", type = "item", numFulfilled = 3, numRequired = 8, finished = false } },
	[1400] = { { text = "Red Crystal: 0/1", type = "object", numFulfilled = 0, numRequired = 1, finished = false } },
}
local completed = { [1001] = true, [1002] = true, [1003] = true, [1010] = true, [1100] = true, [1110] = true, [1200] = true }
local savedCompleted = C_QuestLog.GetAllCompletedQuestIDs
C_QuestLog.GetAllCompletedQuestIDs = function()
	local list = {}
	for id in pairs(completed) do list[#list + 1] = id end
	return list
end
local savedQuests, savedMap, savedLevel, savedPos = QUESTS, PLAYER_MAP, PLAYER_LEVEL, { PLAYER_POS[1], PLAYER_POS[2] }
local savedFormat = QUEST_MONSTERS_KILLED
QUEST_MONSTERS_KILLED = "%s slain: %d/%d"
local function Log(list)
	QUESTS = {}
	for _, e in ipairs(list) do
		local id = type(e) == "table" and e[1] or e
		QUESTS[#QUESTS + 1] = { id = id, title = QUESTS_DATA[id] and QUESTS_DATA[id].title or ("Quest " .. id),
			complete = type(e) == "table" and e[2] or false, objectives = LOG_OBJECTIVES[id] or {} }
	end
end
local function Progress() -- the engine reads my progress again (as after a loading screen)
	Fire("PLAYER_ENTERING_WORLD", false, false)
	Fire("QUEST_LOG_UPDATE")
end

-- The jumps into the window and the map pins, recorded.
local opened, selected, pins = {}, {}, {}
Replace("OpenBrowser", function(id) opened[#opened + 1] = id end)
Replace("SelectZone", function(map) selected[#selected + 1] = map end)
Replace("Waypoint", function(map, x, y) pins[#pins + 1] = { map = map, x = x, y = y } return true end)

-- Friends: Beacon's (where they are) and their quest progress (QuestShare.lua's).
local beacon = LT:GetModule("beacon")
local savedPeers, savedBeaconOn = beacon and rawget(beacon, "GetPeers"), beacon and beacon.enabled
local PEERS = {
	[11] = { name = "Anna Brook", classFile = "MAGE", level = 13, area = "Westfall" },
	[12] = { name = "Bob", classFile = "WARRIOR", level = 18, area = "Redridge Mountains" },
	[13] = { name = "Cleo", classFile = "PRIEST", level = 9, area = "Elwynn Forest" },
}
if beacon then
	beacon.GetPeers = function() return PEERS end
	beacon.enabled = true
end
local savedFriends = Q.friends
local FRIENDS = {
	[11] = { name = "Anna Brook", classFile = "MAGE", done = { [1001] = true, [1002] = true, [1100] = true }, active = {} },
	[13] = { name = "Cleo", classFile = "PRIEST", done = { [1001] = true }, active = {} },
}
Q.friends = FRIENDS
if Q.FriendProgress then
	Replace("FriendProgress", function(id) if id then return FRIENDS[id] end return FRIENDS end)
end

PLAYER_LEVEL, PLAYER_MAP, PLAYER_POS[1], PLAYER_POS[2] = 12, WESTFALL, 0.5, 0.5
Q.SetTestData(QUESTS_DATA, ZONES)
Log({ { 1011, true }, 1101, 1120, 1400 })
Progress()

local state = Q.ViewsState()
local census, K = state.census, state.K
local startsBefore = census.starts

---------------------------------------------------------------------------
section("Lodestar views: registering with the window")
---------------------------------------------------------------------------
-- A stand-in for the window's registry (the big window's part makes the real one): it records.
local registry = {}
local realRegistry = Q.RegisterBrowserView
do
	Q.ViewsState(true) -- (forget an earlier registration: the real registry's at load, if there is one)
	Q.RegisterBrowserView = nil
	M:OnEnable()
	check(not Q.ViewsState().registered, "no registry: nothing registered, no error")
	Q.RegisterBrowserView = function(key, label, build) registry[#registry + 1] = { key = key, label = label, build = build } end
	M:OnEnable()
	M:OnEnable()
	local keys = {}
	for _, r in ipairs(registry) do keys[#keys + 1] = r.key .. "=" .. r.label end
	check(Q.ViewsState().registered and table.concat(keys, ", ") == "myquests=My quests, levelpath=Level path",
		"the registry there: the two views registered once, on the module's enable, got " .. table.concat(keys, ", "))
	check(Q.BuildView("storylines", UIParent) == nil and Q.BuildView("continents", UIParent) == nil, "the storylines' grid and the continents are gone")
	check(census.starts == startsBefore, "nothing counted before a view is shown")
end

local function BuildOn(index, w, h)
	local parent = CreateFrame("Frame", nil, UIParent)
	parent:SetSize(w or 1000, h or 600)
	local view = registry[index].build(parent)
	view.frame:Hide() -- (the registry shows a view when its tab is picked)
	return view, parent
end
local mine, levelpath = BuildOn(1), BuildOn(2)
check(type(mine.frame) == "table" and type(mine.Refresh) == "function" and type(mine.OnShow) == "function"
	and type(mine.OnHide) == "function" and mine.frame:GetParent() ~= nil, "build(parent): { frame, Refresh, OnShow, OnHide } in the parent")

-- Shown the way the registry does it.
local function Show(view)
	view.frame:Show()
	view:OnShow()
end
local function Hide(view)
	view.frame:Hide()
	view:OnHide()
end

-- What the list shows: "kind:text" per entry ("h:Westfall (2)", "q:1101", "n:1110", "note:...").
local function Entries(view)
	local out = {}
	for _, e in ipairs(view.list.entries) do
		if e.kind == "head" then out[#out + 1] = "h:" .. plain(e.text) .. (e.note and (" " .. plain(e.note)) or "")
		elseif e.kind == "quest" then out[#out + 1] = "q:" .. e.e.id
		elseif e.kind == "next" then out[#out + 1] = "n:" .. e.n.id
		else out[#out + 1] = e.key end
	end
	return table.concat(out, ", ")
end
local function RowOf(view, key) return view.list:Row(key) end

---------------------------------------------------------------------------
section("Lodestar views: the quest log's objectives (Q.LogObjectives)")
---------------------------------------------------------------------------
do
	local list = Q.LogObjectives(1101)
	check(#list == 1 and list[1].name == "Defias Looter" and list[1].have == 2 and list[1].need == 10 and not list[1].done
		and list[1].data == OBJECTIVES[1101][1], "an objective: its name without the count (the game's format), its numbers, the data's (by kind)")
	LOG_OBJECTIVES[9901] = { { text = "Wolf Fang: 1/4", finished = false }, { text = "Gnoll Paws: 4/4", finished = true } }
	OBJECTIVES[9901] = { { kind = "item", name = "Gnoll Paws", sources = {} }, { kind = "item", name = "Wolf Fang", sources = {} } }
	Log({ 9901 })
	list = Q.LogObjectives(9901)
	check(list[1].name == "Wolf Fang" and list[1].have == 1 and list[1].need == 4 and list[1].data == OBJECTIVES[9901][2]
		and list[2].done and list[2].data == OBJECTIVES[9901][1], "without the client's numbers and kinds: from the text, the data's by name")
	local format = QUEST_MONSTERS_KILLED
	QUEST_MONSTERS_KILLED = "%1$s getötet: %2$d/%3$d"
	LOG_OBJECTIVES[9901] = { { text = "Defias-Plünderer getötet: 2/10", type = "monster", numFulfilled = 2, numRequired = 10 } }
	Log({ 9901 })
	check(Q.LogObjectives(9901)[1].name == "Defias-Plünderer", "a German client's format (positional)")
	QUEST_MONSTERS_KILLED = format
	check(#Q.LogObjectives(4242) == 0, "not in my log: none")
	local spot, objective = Q.ObjectiveSpot(1400, DARKSHORE, 0.5, 0.5)
	check(spot and spot.y == 0.2 and objective.name == "Red Crystal", "where to go for it: the nearest area of an objective not done")
	LOG_OBJECTIVES[9901], OBJECTIVES[9901] = nil, nil
	Log({ { 1011, true }, 1101, 1120, 1400 })
end

---------------------------------------------------------------------------
section("Lodestar views: my quests")
---------------------------------------------------------------------------
do
	local slice = K.SLICE
	K.SLICE = 5
	Show(mine)
	check(census.work and not census.data and not mine.Message:IsShown() and mine.list.scroll:IsShown() and RowOf(mine, "q1101"),
		"shown: my quest log at once, while the storylines are counted (a few quests a frame)")
	check(Entries(mine):find("h:Continue your storylines started, the next step for your level, counting", 1, true) and plain(RowOf(mine, "counting").Text:GetText()) == "Looking through your storylines...",
		"meanwhile Continue says it's looking")
	local slices = census.slices
	Wait(1)
	check(census.data and census.slices - slices > 3 and not census.work and not census.pulse:IsShown(),
		"counted over several frames (" .. (census.slices - slices) .. "), then nothing runs")
	K.SLICE = slice
	check(mine.sorts.zone.on and M.db.views.mySort == "zone", "sorted by zone at first")
	check(Entries(mine) == "h:Ready to turn in (1), q:1011, h:Westfall (2)  you're here, q:1120, q:1101, h:Darkshore (1), q:1400, "
		.. "h:Continue your storylines started, the next step for your level, n:1111",
		"ready to turn in first (every zone), then my zone (the nearest objective first), then the others; then Continue: " .. Entries(mine))
	check(plain(mine.Head:GetText()) == "4 quests in your log · 1 ready to turn in", "on top: how many, how many ready")
	-- A quest's line.
	local row = RowOf(mine, "q1101")
	check(plain(row.Title:GetText()) == "[12] The Defias Brotherhood" and plain(row.Badge:GetText()) == "2/5"
		and plain(row.Todo:GetText()):find("^2/10 Defias Looter · ") and plain(row.Right:GetText()) == "Gryan Stoutmantle",
		"a line: [12] Title, its chain's 2/5, its first objective with progress and how far, its turn-in: "
		.. plain(row.Todo:GetText()) .. " | " .. plain(row.Right:GetText()))
	check(row._kind == "Button" and row:GetHeight() <= 24, "one line, a Button")
	local oats = RowOf(mine, "q1120")
	check(plain(oats.Badge:GetText()) == "" and plain(oats.Todo:GetText()):find("^3/8 Handful of Oats"), "a quest in no chain: no badge")
	local ready = RowOf(mine, "q1011")
	check(plain(ready.Todo:GetText()) == "Ready to turn in" and plain(ready.Right:GetText()) == "Marshal Dughan, Elwynn Forest"
		and plain(ready.Badge:GetText()) == "2/2", "ready: says so, its turn-in with its zone (not mine)")
	local crystal = RowOf(mine, "q1400")
	check(plain(crystal.Right:GetText()) == "Farmer Saldean, Westfall" and plain(crystal.Todo:GetText()) == "0/1 Red Crystal",
		"turned in in another zone than its own: the zone said; far away: no distance")
	-- Its tooltip, click and right-click.
	row._scripts.OnEnter(row)
	check(plain(TOOLTIP.title) == "[12] The Defias Brotherhood" and tipHas("In your quest log") and tipHas("Westfall")
		and tipHas("Step 2 of 5 · The People's Militia") and tipHas("- Defias Looter slain: 2/10") and tipHas("Turn in: Gryan Stoutmantle")
		and tipHas("Click: open it in the quest browser") and tipHas("Right-click: map pin at Defias Looter"),
		"its tooltip: status, zone, step, every objective, turn-in, what the clicks do")
	row._scripts.OnLeave(row)
	oats._scripts.OnEnter(oats)
	check(tipHas("- Handful of Oats: 3/8 (from Oat Sack, 100%)"), "an item's objective: where it comes from")
	oats._scripts.OnLeave(oats)
	row:Click()
	check(opened[#opened] == 1101, "a click opens it in the quest browser")
	row:Click("RightButton")
	check(pins[#pins] and pins[#pins].map == WESTFALL and pins[#pins].x == 0.45, "a right-click: the map pin at its objective's area")
	ready:Click("RightButton")
	check(pins[#pins].map == ELWYNN and pins[#pins].x == 0.42, "a ready one: at its turn-in")
	-- Continue your storylines.
	local nxt = RowOf(mine, "n1111")
	check(nxt and plain(nxt.Text:GetText()) == "Westfall Stew - next: [13] Goretusk Liver Pie, Farmer Saldean (Westfall)"
		and plain(nxt.Right:GetText()) == "1/2", "Continue: a chain I've started whose next step I can take, its giver and zone")
	check(not Entries(mine):find("n:1201", 1, true) and not Entries(mine):find("n:1102", 1, true),
		"not a chain whose next step is too high for me (Redridge), nor one whose next step needs the one in my log")
	nxt._scripts.OnEnter(nxt)
	check(TOOLTIP.title == "Westfall Stew" and tipHas("1 of 2 steps done") and tipHas("From Farmer Saldean, Westfall"), "its tooltip")
	nxt._scripts.OnLeave(nxt)
	nxt:Click()
	check(opened[#opened] == 1111, "a click opens its next step")
	nxt:Click("RightButton")
	check(pins[#pins].x == 0.56 and pins[#pins].y == 0.31, "a right-click: the map pin at its giver")
	-- Sorting, kept.
	mine.sorts.level:Click()
	check(M.db.views.mySort == "level" and Entries(mine):find("^h:Ready to turn in %(1%), q:1011, h:In progress %(3%), q:1120, q:1101, q:1400, h:Continue"),
		"by level: ready first, then the lowest level first: " .. Entries(mine))
	mine.sorts.chain:Click()
	check(M.db.views.mySort == "chain" and Entries(mine):find("^h:Ready to turn in %(1%), q:1011, h:The People's Militia 1/5, q:1101, h:The Red Crystal 0/2, q:1400, h:Not in a storyline %(1%), q:1120, h:Continue"),
		"by storyline: each with its steps done, the quests in none last: " .. Entries(mine))
	mine.sorts.zone:Click()
	check(M.db.views.mySort == "zone", "and by zone again")
	M.db.views = { show = "all", sort = "worth" }
	mine:Refresh()
	Wait(0.1)
	check(mine.sorts.zone.on and M.db.views.mySort == "zone", "the storylines' saved filter and sort of the builds before: by zone")
end

---------------------------------------------------------------------------
section("Lodestar views: events while shown, moving, turning in, the data changing")
---------------------------------------------------------------------------
do
	local starts, draws = census.starts, mine.draws
	LOG_OBJECTIVES[1101][1] = { text = "Defias Looter slain: 3/10", type = "monster", numFulfilled = 3, numRequired = 10, finished = false }
	Fire("QUEST_LOG_UPDATE")
	Fire("QUEST_LOG_UPDATE")
	check(mine.draws == draws, "an event: nothing at once")
	Wait(0.6)
	check(mine.draws == draws + 1 and census.starts == starts and plain(RowOf(mine, "q1101").Todo:GetText()):find("^3/10 Defias Looter"),
		"drawn half a second later, once, with the progress; the log alone doesn't count again")
	-- Walking: the nearest first.
	draws = mine.draws
	PLAYER_POS[1], PLAYER_POS[2] = 0.45, 0.32
	Wait(2.1)
	check(mine.draws == draws + 1 and Entries(mine):find("you're here, q:1101, q:1120", 1, true), "walked near the looters: drawn again, they come first")
	draws = mine.draws
	Wait(4.1)
	check(mine.draws == draws, "standing still: nothing")
	PLAYER_POS[1], PLAYER_POS[2] = 0.5, 0.5
	-- Turning one in.
	completed[1120] = true
	Log({ { 1011, true }, 1101, 1400 })
	Fire("QUEST_TURNED_IN", 1120, 0, 0)
	Wait(0.6)
	check(census.starts == starts + 1 and not RowOf(mine, "q1120") and plain(mine.Head:GetText()) == "3 quests in your log · 1 ready to turn in",
		"a quest turned in: counted again, gone from the list")
	-- Refresh (the window's): drawn on the next frame, counted again only if something changed.
	draws, starts = mine.draws, census.starts
	mine:Refresh()
	Wait(0.1)
	check(mine.draws == draws + 1 and census.starts == starts, "Refresh: drawn again, nothing counted again")
	-- An empty log.
	Log({})
	Progress()
	mine:Refresh()
	Wait(0.6)
	check(Entries(mine):find("^empty, h:Continue") and plain(RowOf(mine, "empty").Text:GetText()):find("Your quest log is empty", 1, true),
		"an empty log: says so, Continue under it: " .. Entries(mine))
	Log({ { 1011, true }, 1101, 1400 })
	Progress()
	Wait(0.6)
	Hide(mine)
end

---------------------------------------------------------------------------
section("Lodestar views: the level path")
---------------------------------------------------------------------------
local function Rows(view)
	local out = {}
	for _, e in ipairs(view.list.entries) do out[#out + 1] = e.zone.name end
	return table.concat(out, ", ")
end
local function ZoneRow(view, map) return view.list:Row("z" .. map) end
do
	Show(levelpath)
	Wait(0.6)
	check(Rows(levelpath) == "Westfall, Darkshore, Elwynn Forest, Redridge Mountains",
		"the zones of my side (not the Horde's) with something for my levels or a friend there, the most for my level first: " .. Rows(levelpath))
	check(plain(levelpath.Head:GetText()) == "Best next: Westfall, 3 quests for your level", "the best next zone on top: " .. plain(levelpath.Head:GetText()))
	local row = ZoneRow(levelpath, WESTFALL)
	local e = row.entry
	local function runs(entry)
		local out = {}
		for _, r in ipairs(entry.runs) do out[#out + 1] = r[1] .. "-" .. r[2] .. " " .. r[3] end
		return table.concat(out, ", ")
	end
	check(runs(e) == "9-12 done, 13-13 open, 14-18 later" or runs(e) == "9-11 done, 12-13 open, 14-18 later",
		"Westfall's levels: done, open, later: " .. runs(e))
	check(e.here and row.Here:IsShown() and plain(row.Name:GetText()) == "Westfall", "the zone I'm in: a faint band, only its name")
	check(plain(row.Right:GetText()) == "3 for your level" and not row.Sub and not row.Band and not row.Dots,
		"the row: its name, its bar, what's there for my level (not what's too high: no coming up); nothing else")
	check(plain(ZoneRow(levelpath, REDRIDGE).Right:GetText()) == "", "nothing for my level (Bob is there): nothing at the right")
	local me = levelpath.x0 + (12 - 1) * levelpath.per + levelpath.per / 2
	check(math.abs(select(4, row.Me:GetPoint(1)) - me) < 0.01 and plain(levelpath.Axis.You:GetText()) == "You (12)", "a line at my level")
	row._scripts.OnEnter(row)
	check(TOOLTIP.title == "Westfall" and tipHas("3 for your level") and tipHas("1 you can take now") and tipHas("1 in your quest log")
		and tipHas("3 of 8 done") and tipHas("Anna Brook level 13") and tipHas("You're here.") and tipHas("Click: open this zone"),
		"its tooltip: the rest (done, what I can take, in my log, friends there)")
	row._scripts.OnLeave(row)
	row:Click()
	check(selected[#selected] == WESTFALL, "a click opens the zone in the window")
	-- Without Q.SelectZone: the zone's first quest.
	local select = Q.SelectZone
	Q.SelectZone = nil
	ZoneRow(levelpath, ELWYNN):Click()
	Q.SelectZone = select
	check(opened[#opened] == 1001, "without Q.SelectZone: the window opens on the zone's first quest")
	-- Friends' setting off: Redridge (only Bob there) goes; "All zones" brings it back, kept.
	M.db.friends = false
	levelpath:Refresh()
	Wait(0.1)
	check(Rows(levelpath) == "Westfall, Darkshore, Elwynn Forest" and not levelpath.All.on, "no friends: only the zones with something for my levels")
	levelpath.All:Click()
	check(Rows(levelpath) == "Westfall, Darkshore, Elwynn Forest, Redridge Mountains" and levelpath.All.on and M.db.views.allZones == true,
		"All zones: every zone of my side; kept")
	levelpath.All:Click()
	check(Rows(levelpath) == "Westfall, Darkshore, Elwynn Forest" and M.db.views.allZones == nil, "and off again")
	M.db.friends = true
	-- A level up: counted again, the order follows.
	PLAYER_LEVEL = 18
	Fire("PLAYER_LEVEL_UP", 18)
	Wait(0.6)
	check(Rows(levelpath) == "Westfall, Darkshore, Redridge Mountains, Elwynn Forest" and plain(levelpath.Axis.You:GetText()) == "You (18)",
		"a level up: Redridge's quests are for my level now, my line moves: " .. Rows(levelpath))
	check(plain(ZoneRow(levelpath, REDRIDGE).Right:GetText()) == "2 for your level", "Redridge: 2 now")
	Log({})
	Progress()
	PLAYER_LEVEL = 30
	Fire("PLAYER_LEVEL_UP", 30)
	Wait(0.6)
	check(Rows(levelpath) == "Redridge Mountains, Westfall, Elwynn Forest" and levelpath.Message:IsShown() == false
		and plain(levelpath.Head:GetText()) == "Nothing for your level.", "far above them all (" .. Rows(levelpath) .. ", " .. plain(levelpath.Head:GetText()) .. "): only where friends are, the nearest my level first, nothing for my level: says so")
	M.db.friends = false
	levelpath:Refresh()
	Wait(0.1)
	check(levelpath.Message:IsShown() and plain(levelpath.Message:GetText()) == "No zone has quests for your level." and levelpath.Guide:IsShown(),
		"no zone left: says so, with a way to all of them")
	levelpath.Guide:Click()
	check(Rows(levelpath):find("Westfall", 1, true) and not levelpath.Message:IsShown(), "its button: all zones")
	levelpath.All:Click()
	M.db.friends = true
	Log({ { 1011, true }, 1101, 1400 })
	Progress()
	PLAYER_LEVEL = 12
	Fire("PLAYER_LEVEL_UP", 12)
	Wait(0.6)
end

---------------------------------------------------------------------------
section("Lodestar views: hidden, nothing runs; shown again, counted if needed")
---------------------------------------------------------------------------
do
	Hide(levelpath)
	check(not census.listening and not census.pulse:IsShown(), "no view shown: no events, no OnUpdate")
	local starts, draws = census.starts, levelpath.draws
	completed[1101] = true
	Log({ { 1011, true }, 1400 })
	Fire("QUEST_TURNED_IN", 1101, 0, 0)
	Wait(1)
	check(census.starts == starts and levelpath.draws == draws, "an event while hidden: nothing")
	Show(levelpath)
	Wait(0.2)
	check(census.starts == starts + 1 and plain(ZoneRow(levelpath, WESTFALL).Right:GetText()) == "2 for your level", "shown again: counted again, as it is now")
	-- The data changing while shown.
	starts = census.starts
	Q.SetTestData(QUESTS_DATA, ZONES)
	Wait(0.2)
	check(census.starts == starts + 1, "the data changed: counted again")
	Hide(levelpath)
end

---------------------------------------------------------------------------
section("Lodestar views: a full quest log, many storylines, only the rows in sight")
---------------------------------------------------------------------------
do
	local many = {}
	for id, q in pairs(QUESTS_DATA) do many[id] = q end
	local log = {}
	for i = 1, 300 do
		local a, b = 5000 + 2 * i, 5001 + 2 * i
		many[a] = Quest(a, "Chain " .. i, 10, 9, WESTFALL, { starts = { GRYAN } })
		many[b] = Quest(b, "Chain " .. i .. " part two", 11 + i % 2, 9, WESTFALL, { pre = { a }, starts = { GRYAN } })
		completed[a] = true
		if i <= 25 then log[#log + 1] = 6000 + i end
	end
	for i = 1, 25 do many[6000 + i] = Quest(6000 + i, "Errand " .. i, 10 + i % 3, 9, WESTFALL) end
	Q.SetTestData(many, { ZONES[1], ZONES[2] })
	Log(log)
	Progress()
	local small = BuildOn(1, 1000, 300)
	Show(small)
	Wait(1)
	local list = small.list
	local nexts = 0
	for _, e in ipairs(list.entries) do nexts = nexts + (e.kind == "next" and 1 or 0) end
	check(#small.quests == 25 and nexts == 8, "25 quests in my log; 300 storylines to go on with: the first 8 (" .. nexts .. ")")
	check(list.made < #list.entries and list.made <= 24, "only the rows near sight are made: " .. list.made .. " of " .. #list.entries)
	local key = list.entries[3].key
	local kept = list:Row(key)
	list.scroll:SetVerticalScroll(30)
	list.scroll._scripts.OnVerticalScroll(list.scroll, 30)
	check(list:Row(key) == kept and kept.entry.key == key, "scrolled a bit: a row stays on its entry (a controller's cursor stays on it)")
	list.scroll:SetVerticalScroll(600)
	list.scroll._scripts.OnVerticalScroll(list.scroll, 600)
	check(list:Row(list.entries[#list.entries].key) and not list:Row(key), "scrolled to the end: the rows go round (" .. list.made .. " made)")
	Hide(small)
	for i = 1, 300 do completed[5000 + 2 * i] = nil end
	Q.SetTestData(QUESTS_DATA, ZONES)
	Log({ { 1011, true }, 1400 })
	Progress()
end

---------------------------------------------------------------------------
section("Lodestar views: no data, the controller, a fight")
---------------------------------------------------------------------------
do
	local load = Q.Load
	Replace("Load", function() return false end)
	Show(levelpath)
	check(levelpath.Message:IsShown() and plain(levelpath.Message:GetText()):find("The quest data isn't there", 1, true)
		and not levelpath.list.scroll:IsShown(), "no data: says so")
	Hide(levelpath)
	Show(mine)
	check(mine.Message:IsShown() and not mine.list.scroll:IsShown(), "my quests too")
	Hide(mine)
	Q.Load = load
	Show(levelpath)
	Wait(0.5)
	check(not levelpath.Message:IsShown() and levelpath.list.scroll:IsShown(), "the data there again: the rows")
	Hide(levelpath)
	-- The registry's OnShow before the frame shows: drawn all the same.
	local draws = levelpath.draws
	levelpath:OnShow()
	check(levelpath.draws == draws + 1 and not levelpath.frame:IsShown(), "OnShow before its frame shows: drawn all the same")
	levelpath.frame:Show()
	Wait(0.1)
	check(levelpath.draws == draws + 1, "and once")
	Hide(levelpath)
	-- Every row and chip is a Button of ours; nothing of Blizzard's on our frames.
	Show(mine)
	Show(levelpath)
	Wait(0.5)
	local buttons, count = true, 0
	for _, list in ipairs({ mine.list, levelpath.list }) do
		for _, row in pairs(list.used) do
			if row.kind == "quest" or row.kind == "next" or row.kind == "zone" then
				buttons = buttons and row._kind == "Button"
				count = count + 1
			end
		end
	end
	for _, chip in pairs(mine.sorts) do buttons = buttons and chip._kind == "Button" end
	buttons = buttons and levelpath.Guide._kind == "Button" and levelpath.All._kind == "Button"
	check(buttons and count >= 5, "every quest, storyline and zone row, chip and button is a Button the controller reaches (" .. count .. ")")
	local blizzard = false
	for _, v in ipairs({ mine, levelpath }) do
		for _, f in ipairs({ v.frame, v.list.scroll, v.list.child }) do
			blizzard = blizzard or f.useCustomNavigation ~= nil or f.smartNavigationIgnored ~= nil
		end
	end
	check(not blizzard, "nothing of Blizzard's on our frames")
	local blocked = #BLOCKED
	EnterCombat()
	mine.sorts.level:Click()
	ZoneRow(levelpath, WESTFALL):Click()
	RowOf(mine, "q1011"):Click("RightButton")
	LeaveCombat()
	check(#BLOCKED == blocked and selected[#selected] == WESTFALL, "in a fight too")
	mine.sorts.zone:Click()
	Hide(mine)
	Hide(levelpath)
	Wait(0.1)
	check(not census.pulse:IsShown() and not census.listening, "all hidden: nothing runs")
end

-- Back as it was.
for name, fn in pairs(replaced) do
	Q[name] = fn or nil
end
Q.RegisterBrowserView = realRegistry -- (the real one, if there is one, has had them since the load)
Q.friends = savedFriends
if beacon then
	beacon.GetPeers = savedPeers
	beacon.enabled = savedBeaconOn
end
for map, name in pairs(savedNames) do MAP_NAMES[map] = name end
C_QuestLog.GetAllCompletedQuestIDs = savedCompleted
QUESTS, PLAYER_MAP, PLAYER_LEVEL = savedQuests, savedMap, savedLevel
PLAYER_POS[1], PLAYER_POS[2] = savedPos[1], savedPos[2]
QUEST_MONSTERS_KILLED = savedFormat
M.db.views = nil
Progress()
Wait(math.ceil(waited) - waited + 1)
