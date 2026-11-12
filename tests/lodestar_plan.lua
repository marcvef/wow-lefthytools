-- Lodestar: the plan (Plan.lua): the quests a player picked, in their order, kept per character
-- (add, toggle, move, remove, clear, a copy for callers, nonsense IDs); its stops (a quest not taken:
-- giver, objectives, turn-in; taken: the giver done, objectives done as the quest log says; ready: all;
-- a stop without a spot left out; an item that starts it: where it drops; each stop's spot the nearest
-- to the stop before it, its label that spot's person); a quest turned in leaving it (the event, and
-- one done before); Q.PlanRev moving only when the plan or its stops change; the next stop and skipping
-- it; a suggested route (Route.lua's Q.SuggestRoute: a stand-in here, its own part builds it in
-- parallel) in use, kept, dropped by an edit and said so, back to the order, none possible; the
-- callbacks once on the next frame; events only while the plan has quests and Lodestar is on; words
-- (a stop, the briefing); the "+" button. Then the Plan tab (Views.lua): empty, the quests numbered
-- with their status, chain badge, up, down and remove, the clicks (details, Ctrl: the map, right: the
-- chain, Shift: the map pin), the route's stops numbered with the next one marked, what it saves,
-- "Clear" asking first, no counting for it, the controller.
-- Data.lua and Engine.lua are in the build: the quests go in through Q.SetTestData; Q.Objectives is a
-- stand-in (the test quests have none in the data's own format). Q.ShowDetails, Q.ShowOnMap (the big
-- window's part makes them in parallel), Q.OpenChain and Q.Waypoint record; Q.SuggestRoute and
-- Q.RouteYards are stand-ins. Whatever it replaces is put back at its end.
-- Needs: no other file.

local suite = ...
local check, section, ns, LT = suite.check, suite.section, suite.ns, suite.LT
local Q = ns.Lodestar
local M = LT:GetModule("lodestar")
local P = Q.PlanState()

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
-- The world: Elwynn Forest (1429) and Westfall (1436)
---------------------------------------------------------------------------

local ELWYNN, WESTFALL = 1429, 1436
local function Npc(id, name, map, x, y) return { kind = "npc", id = id, name = name, points = { { map = map, x = x, y = y } } } end
local DUGHAN, PESTLE, MAYBELL = Npc(1, "Marshal Dughan", ELWYNN, 0.42, 0.66), Npc(2, "William Pestle", ELWYNN, 0.52, 0.48), Npc(3, "Maybell", ELWYNN, 0.6, 0.6)
local SALDEAN, GRYAN = Npc(4, "Farmer Saldean", WESTFALL, 0.56, 0.31), Npc(5, "Gryan Stoutmantle", WESTFALL, 0.56, 0.47)
-- A guard in two places: the one nearer the stop before is chosen.
local GUARD = { kind = "npc", id = 6, name = "Guard Thomas", points = { { map = ELWYNN, x = 0.9, y = 0.1 }, { map = ELWYNN, x = 0.27, y = 0.78 } } }
local function Quest(id, title, level, minLevel, zone, extra)
	local q = { id = id, title = title, level = level, minLevel = minLevel, zone = zone, starts = { DUGHAN }, ends = { DUGHAN } }
	for k, v in pairs(extra or {}) do q[k] = v end
	return q
end
local QUESTS_DATA = {
	[7001] = Quest(7001, "Wanted: Hogger", 11, 8, ELWYNN, { ends = { GUARD } }),
	[7002] = Quest(7002, "Kobold Candles", 9, 6, ELWYNN, { starts = { PESTLE }, ends = { MAYBELL } }),
	[7003] = Quest(7003, "Westfall Stew", 11, 9, WESTFALL, { starts = { SALDEAN }, ends = { SALDEAN } }),
	[7004] = Quest(7004, "A Dusty Letter", 12, 10, WESTFALL, { starts = { { kind = "item", id = 7000, name = "Dusty Letter", points = {}, drops = {
		{ kind = "npc", id = 950, name = "Defias Pillager", chance = 12, points = { { map = WESTFALL, x = 0.4, y = 0.5, r = 0.1 } } } } } },
		ends = { GRYAN } }),
	[7005] = Quest(7005, "Hogger's Lair", 12, 10, ELWYNN, { pre = { 7001 } }),
	[7006] = Quest(7006, "Far Too High", 25, 20, ELWYNN),
	[7007] = Quest(7007, "The Last Step", 12, 10, ELWYNN, { pre = { 7005 } }),
}
local ZONES = {
	{ map = ELWYNN, name = "Elwynn Forest", continent = 1415, minLevel = 1, maxLevel = 12 },
	{ map = WESTFALL, name = "Westfall", continent = 1415, minLevel = 9, maxLevel = 18 },
}
local function Area(name, map, x, y) return { kind = "npc", id = 900, name = name, points = { { map = map, x = x, y = y, r = 0.05 } } } end
local OBJECTIVES = {
	[7001] = { { kind = "kill", id = 448, name = "Hogger", count = 1, sources = { Area("Hogger", ELWYNN, 0.25, 0.8) } } },
	[7002] = { { kind = "item", id = 772, name = "Large Candle", count = 8, sources = { Area("Kobold Tunneler", ELWYNN, 0.7, 0.2),
		Area("Kobold Miner", ELWYNN, 0.45, 0.62) } },
		{ kind = "item", id = 773, name = "Wick", count = 1, provided = true, sources = {} } },
	[7003] = { { kind = "kill", id = 454, name = "Young Goretusk", count = 4, sources = { Area("Young Goretusk", WESTFALL, 0.5, 0.5) } },
		{ kind = "item", id = 774, name = "Stringy Vulture Meat", count = 3, sources = {} } },
}
Replace("Objectives", function(id) return OBJECTIVES[id] or {} end)

-- My progress: completed quests and the quest log ({ id, ... } or { { id, complete } }), with the
-- quest log's objectives.
local LOG_OBJECTIVES = {
	[7002] = { { text = "Large Candle: 2/8", type = "item", numFulfilled = 2, numRequired = 8, finished = false } },
	[7003] = { { text = "Young Goretusk slain: 1/4", type = "monster", numFulfilled = 1, numRequired = 4, finished = false } },
}
local completed = {}
local savedCompleted = C_QuestLog.GetAllCompletedQuestIDs
C_QuestLog.GetAllCompletedQuestIDs = function()
	local list = {}
	for id in pairs(completed) do list[#list + 1] = id end
	return list
end
local savedQuests, savedMap, savedLevel, savedPos, savedGuid = QUESTS, PLAYER_MAP, PLAYER_LEVEL, { PLAYER_POS[1], PLAYER_POS[2] }, MY_GUID
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
local details, onMap, chained, pins = {}, {}, {}, {}
Replace("ShowDetails", function(id) details[#details + 1] = id return true end)
Replace("ShowOnMap", function(id, spot) onMap[#onMap + 1] = { id, spot } return true end)
Replace("OpenChain", function(id) chained[#chained + 1] = id return true end)
Replace("Waypoint", function(map, x, y, share) pins[#pins + 1] = { map = map, x = x, y = y, share = share } return true end)
Replace("SuggestRoute", nil)
Replace("RouteYards", nil)

PLAYER_LEVEL, PLAYER_MAP, PLAYER_POS[1], PLAYER_POS[2], MY_GUID = 12, ELWYNN, 0.5, 0.5, nil
Q.SetTestData(QUESTS_DATA, ZONES)
Log({})
Progress()
Q.PlanClear()
Wait(0.1)

local function Keys(stops)
	local out = {}
	for _, s in ipairs(stops or Q.PlanStops()) do out[#out + 1] = s.key .. (s.done and "+" or "") end
	return table.concat(out, ", ")
end

---------------------------------------------------------------------------
section("Lodestar plan: the list, kept per character")
---------------------------------------------------------------------------
do
	local notes = 0
	Q.OnPlanChanged(function() notes = notes + 1 end)
	check(#Q.PlanList() == 0 and not Q.PlanHas(7001) and Q.PlanNext() == nil and #Q.PlanStops() == 0, "empty at first")
	check(not P.listening, "an empty plan: no events listened to")
	local rev = Q.PlanRev()
	check(Q.PlanAdd(7001) and Q.PlanAdd(7002) and not Q.PlanAdd(7001) and not Q.PlanAdd("x") and not Q.PlanAdd(-3) and not Q.PlanAdd(1.5),
		"added at the end, each once; nonsense isn't")
	check(table.concat(Q.PlanList(), ",") == "7001,7002" and Q.PlanHas(7002) and Q.PlanRev() ~= rev, "in order; the rev moved")
	check(notes == 0, "the callbacks not at once ...")
	Wait(0.1)
	check(notes == 1, "... but once on the next frame, for both")
	check(P.listening, "with quests in it: the quest log's events")
	local saved = LefthyToolsDB.lodestar.plans["Player-1-0"]
	check(saved and table.concat(saved.list, ",") == "7001,7002", "kept in the saved variables under the character's GUID")
	local copy = Q.PlanList()
	copy[1] = 9999
	check(Q.PlanList()[1] == 7001, "PlanList gives a copy")
	check(Q.PlanToggle(7003) == true and Q.PlanToggle(7003) == false and not Q.PlanHas(7003), "toggle: in, then out")
	Q.PlanAdd(7003)
	check(Q.PlanMove(7003, 1) and table.concat(Q.PlanList(), ",") == "7003,7001,7002", "moved to the top")
	check(Q.PlanMove(7003, 99) and table.concat(Q.PlanList(), ",") == "7001,7002,7003", "beyond the end: the end")
	check(not Q.PlanMove(7003, 3) and not Q.PlanMove(4242, 1), "not moved: already there, or not in it")
	check(Q.PlanRemove(7003) and not Q.PlanRemove(7003) and table.concat(Q.PlanList(), ",") == "7001,7002", "removed")
	-- Another character: its own plan.
	MY_GUID = "Player-1-2"
	check(#Q.PlanList() == 0 and not Q.PlanHas(7001), "another character: an empty plan of its own")
	Q.PlanAdd(7003)
	check(table.concat(LefthyToolsDB.lodestar.plans["Player-1-2"].list, ",") == "7003", "kept for it")
	Q.PlanClear()
	MY_GUID = nil
	check(table.concat(Q.PlanList(), ",") == "7001,7002", "back: the first one's plan")
	-- What a broken saved plan gives.
	LefthyToolsDB.lodestar.plans["Player-1-3"] = { list = { 7001, "x", 7001, 0, 7002 }, route = "nonsense" }
	MY_GUID = "Player-1-3"
	check(table.concat(Q.PlanList(), ",") == "7001,7002" and LefthyToolsDB.lodestar.plans["Player-1-3"].route == nil, "a saved plan made sane once")
	LefthyToolsDB.lodestar.plans["Player-1-3"] = nil
	MY_GUID = nil
	Wait(0.1)
end

---------------------------------------------------------------------------
section("Lodestar plan: the stops")
---------------------------------------------------------------------------
do
	-- Not taken: the giver, the objectives with an area (not the one the giver provides), the turn-in.
	local stops = Q.PlanStops()
	check(Keys(stops) == "7001:start:0, 7001:objective:1, 7001:end:0, 7002:start:0, 7002:objective:1, 7002:end:0",
		"each quest's giver, objectives (with an area) and turn-in, in the plan's order: " .. Keys(stops))
	local s = stops[1]
	check(s.quest == 7001 and s.kind == "start" and s.label == "Marshal Dughan" and s.spot.map == ELWYNN and s.spot.x == 0.42 and #s.spots == 1
		and not s.done, "a stop: its quest, kind, label, its spots and the one chosen")
	check(stops[2].label == "Kill Hogger" and stops[2].index == 1 and stops[2].spot.x == 0.25, "an objective: what to do, which one")
	check(stops[3].label == "Guard Thomas" and stops[3].spot.x == 0.27 and #stops[3].spots == 2,
		"a turn-in in two places: the one nearer the stop before it (Hogger's area)")
	check(stops[5].label == "Collect 8 x Large Candle" and stops[5].spot.x == 0.45, "an item's areas: the one nearer the giver before it")
	check(Q.PlanStops() == stops, "kept while nothing changes")
	check(select(2, Q.PlanNext()) == 1 and Q.PlanNext() == stops[1], "next: the first stop not done")
	check(Q.PlanStopText(stops[1]) == "Pick up Wanted: Hogger at Marshal Dughan" and Q.PlanStopText(stops[2]) == "Kill Hogger"
		and Q.PlanStopText(stops[3]) == "Turn in at Guard Thomas" and Q.PlanStopText(stops[3], true) == "Turn in Wanted: Hogger at Guard Thomas"
		and Q.PlanStopText(stops[2], true) == "Kill Hogger · Wanted: Hogger", "a stop in words")
	-- Taken: its giver done; its objectives as the quest log says; the rev moves only when they do.
	local rev = Q.PlanRev()
	Log({ 7002 })
	Progress()
	stops = Q.PlanStops()
	check(Keys(stops) == "7001:start:0, 7001:objective:1, 7001:end:0, 7002:start:0+, 7002:objective:1, 7002:end:0" and Q.PlanRev() ~= rev,
		"taken: its giver done, the rest not: " .. Keys(stops))
	check(stops[5].label == "Collect 8 x Large Candle" and stops[5].have == 2 and stops[5].need == 8, "its objective with my progress")
	rev = Q.PlanRev()
	Fire("QUEST_LOG_UPDATE")
	check(Q.PlanRev() == rev, "the quest log changed, the stops didn't: the same rev")
	LOG_OBJECTIVES[7002][1] = { text = "Large Candle: 8/8", type = "item", numFulfilled = 8, numRequired = 8, finished = true }
	Log({ 7002 })
	Fire("QUEST_LOG_UPDATE")
	check(Q.PlanStops()[5].done and Q.PlanRev() ~= rev, "an objective done: that stop done, the rev moved")
	Log({ { 7002, true } })
	Progress()
	stops = Q.PlanStops()
	check(stops[5].done and not stops[6].done and select(2, Q.PlanNext()) == 1, "ready: only the turn-in left")
	-- Skipped for now.
	check(Q.PlanSkip(Q.PlanNext()) and select(2, Q.PlanNext()) == 2 and Q.PlanStops()[1].skipped and not Q.PlanSkip(Q.PlanStops()[1]),
		"a stop skipped: done for now, the next one comes up")
	-- Turned in: it leaves the plan.
	local notes = 0
	Q.OnPlanChanged(function() notes = notes + 1 end)
	completed[7002] = true
	Log({})
	Fire("QUEST_TURNED_IN", 7002, 0, 0)
	Progress()
	check(table.concat(Q.PlanList(), ",") == "7001" and not Keys():find("7002", 1, true), "a quest turned in leaves the plan")
	Wait(0.1)
	check(notes == 1, "the callbacks say so")
	-- One done some other way (before the plan was looked at): gone when the stops are made.
	Q.PlanAdd(7003)
	completed[7003] = true
	Progress()
	check(table.concat(Q.PlanList(), ",") == "7001,7003", "a quest done some other way: still listed ...")
	Q.PlanStops()
	check(table.concat(Q.PlanList(), ",") == "7001", "... until the stops are made: then it leaves too")
	completed[7003] = nil
	Progress()
	-- An item that starts it: where it drops; a quest the data doesn't know: no stops, still listed.
	Q.PlanAdd(7004)
	Q.PlanAdd(4242)
	stops = Q.PlanStops()
	local letter = stops[#stops - 1]
	check(letter.quest == 7004 and letter.kind == "start" and letter.spot.x == 0.4 and letter.label == "Dusty Letter (drops from Defias Pillager)"
		and stops[#stops].label == "Gryan Stoutmantle", "an item that starts it: where it drops")
	check(Q.PlanHas(4242) and not Keys():find("4242", 1, true), "a quest the data doesn't know: in the plan, no stops")
	Q.PlanRemove(4242)
	-- The briefing.
	local brief = Q.PlanBriefing()
	check(brief and brief.title == "Your plan" and plain(brief.lines[1]) == "Next (2/5): Kill Hogger · Wanted: Hogger · Elwynn Forest"
		and brief.lines[2] == "Zones: Elwynn Forest, Westfall" and brief.lines[3] == "2 quests · 5 stops",
		"the briefing: next, the zones, the counts: " .. table.concat(brief and brief.lines or {}, " | "))
	Wait(0.1)
end

---------------------------------------------------------------------------
section("Lodestar plan: a suggested route")
---------------------------------------------------------------------------
do
	check(Q.PlanSuggest() == nil and not Q.PlanRouteInfo().active, "without Route.lua: no route")
	local asked
	Replace("SuggestRoute", function(stops, here)
		asked = { stops = stops, here = here }
		local order = {}
		for i = #stops, 1, -1 do
			local s = stops[i]
			if not s.done then
				s.spot = s.spots[1]
				order[#order + 1] = s
			end
		end
		return { order = order, before = 2000, after = 800 }
	end)
	local rev = Q.PlanRev()
	local result = Q.PlanSuggest()
	check(result and asked and asked.here and asked.here.map == ELWYNN and asked.here.x == 0.5 and #asked.stops == 5,
		"asked with every stop and where I am")
	local info = Q.PlanRouteInfo()
	check(info.active and info.before == 2000 and info.after == 800 and info.saves == 1200 and not info.good and not info.dropped and Q.PlanRev() ~= rev,
		"in use: what it saves")
	check(Keys() == "7001:start:0+, 7004:end:0, 7004:start:0, 7001:end:0, 7001:objective:1" and select(2, Q.PlanNext()) == 2,
		"the stops in the route's order, the done ones first: " .. Keys())
	check(Q.PlanStops()[4].spot.x == 0.9, "each with the spot the route chose (kept)")
	local saved = LefthyToolsDB.lodestar.plans["Player-1-0"].route
	check(saved and #saved.keys == 4 and saved.spots["7001:end:0"] == "1429:0.9000:0.1000", "kept in the saved plan: " .. tostring(saved and #saved.keys) .. " " .. tostring(saved and saved.spots["7001:end:0"]))
	Fire("QUEST_LOG_UPDATE")
	check(Keys() == "7001:start:0+, 7004:end:0, 7004:start:0, 7001:end:0, 7001:objective:1", "made again: the same order")
	-- Back to my order, and again.
	Q.PlanUseOrder()
	check(not Q.PlanRouteInfo().active and Keys() == "7001:start:0+, 7001:objective:1, 7001:end:0, 7004:start:0, 7004:end:0", "back to my order")
	Q.PlanSuggest()
	-- Any change of the plan drops it, and says so.
	Q.PlanAdd(7003)
	info = Q.PlanRouteInfo()
	check(not info.active and info.dropped and Keys():find("^7001:start:0%+, 7001:objective:1"), "an edit: back to the quest order, dropped said")
	Q.PlanSuggest()
	check(Q.PlanRouteInfo().active and not Q.PlanRouteInfo().dropped, "suggested again")
	-- A quest turned in leaves, the route stays.
	completed[7003] = true
	Fire("QUEST_TURNED_IN", 7003, 0, 0)
	Progress()
	check(Q.PlanRouteInfo().active and not Q.PlanHas(7003), "a quest turned in: the route stays")
	completed[7003] = nil
	Progress()
	-- Hardly better: the order was good.
	Replace("SuggestRoute", function(stops) return { order = { stops[2] }, before = 1000, after = 990 } end)
	Q.PlanSuggest()
	check(Q.PlanRouteInfo().good and Q.PlanRouteInfo().saves == 10, "saves next to nothing: the order was good already")
	-- None possible: what was in use stays.
	Replace("SuggestRoute", function() return nil end)
	check(Q.PlanSuggest() == nil and Q.PlanRouteInfo().active, "no route possible: nil, the one in use stays")
	Replace("SuggestRoute", function() error("a bug in the route") end)
	local errors = #ERRORS
	check(Q.PlanSuggest() == nil and Q.PlanRouteInfo().active and #ERRORS == errors + 1 and ERRORS[#ERRORS]:find("a bug in the route", 1, true),
		"an error in it: reported, nothing changes")
	table.remove(ERRORS) -- (the test's own)
	Q.PlanUseOrder()
	Wait(0.1)
end

---------------------------------------------------------------------------
section("Lodestar plan: the + button, the events, switched off")
---------------------------------------------------------------------------
do
	local b = Q.NewPlanButton(UIParent)
	check(b._kind == "Button" and not b:IsShown(), "a Button, hidden until it has a quest")
	b:SetQuest(7005)
	check(b:IsShown() and not b.has and b.Icon.path == "Interface\\Buttons\\UI-PlusButton-Up", "a + for a quest not in the plan: " .. tostring(b.Icon.path))
	b._scripts.OnEnter(b)
	check(TOOLTIP.title == "Add to plan", "its tooltip")
	b:Click()
	check(Q.PlanHas(7005) and b.has and TOOLTIP.title == "In your plan" and tipHas("Click: remove it from your plan"), "a click: in the plan, a check")
	b:Click()
	check(not Q.PlanHas(7005) and not b.has, "again: out")
	b._scripts.OnLeave(b)
	b:SetQuest(nil)
	check(not b:IsShown(), "no quest: hidden")
	-- Events only while the plan has quests and Lodestar is on.
	check(P.listening, "a plan: listening")
	LT:SetModuleEnabled("lodestar", false)
	check(not P.listening, "Lodestar off: nothing")
	LT:SetModuleEnabled("lodestar", true)
	check(P.listening, "on again: listening")
	local list = Q.PlanList()
	Q.PlanClear()
	check(not P.listening and #Q.PlanList() == 0, "cleared: nothing listened to")
	for _, id in ipairs(list) do Q.PlanAdd(id) end
	Wait(0.1)
end

---------------------------------------------------------------------------
section("Lodestar plan: the Plan tab")
---------------------------------------------------------------------------
local census = Q.ViewsState().census
local parent = CreateFrame("Frame", nil, UIParent)
parent:SetSize(1000, 600)
local view = Q.BuildView("plan", parent)
view.frame:Hide()
local function Show() view.frame:Show() view:OnShow() end
local function Hide() view.frame:Hide() view:OnHide() end
local function Entries()
	local out = {}
	for _, e in ipairs(view.list.entries) do out[#out + 1] = e.key end
	return table.concat(out, ", ")
end
local function RowOf(key) return view.list:Row(key) end
do
	check(view and view.noCensus and type(view.Refresh) == "function", "built by the views' registry (Q.BuildView)")
	local starts = census.starts
	Q.PlanClear()
	Show()
	check(view.Message:IsShown() and plain(view.Message:GetText()):find("^Your plan is empty%. Add quests with the %+")
		and not view.ClearChip:IsShown() and not view.RouteChip:IsShown(), "empty: how to add, no buttons")
	check(census.starts == starts and not census.work, "nothing counted for it")
	Q.PlanAdd(7001)
	Q.PlanAdd(7004)
	Q.PlanAdd(7006)
	Q.PlanAdd(7005)
	Wait(0.1)
	check(not view.Message:IsShown() and plain(view.Head:GetText()) == "4 quests · 9 stops", "the plan changed: drawn again, the counts on top: " .. plain(view.Head:GetText()))
	check(Entries() == "next, brief2, hquests, q7001, q7004, q7006, q7005", "the next stop, the zones, then the quests in order: " .. Entries())
	local nextRow = RowOf("next")
	check(plain(nextRow.Text:GetText()) == "Next (1/9): Pick up Wanted: Hogger at Marshal Dughan" and plain(nextRow.Right:GetText()) == "Elwynn Forest"
		and nextRow.Band:IsShown(), "the next stop: what to do, its zone: " .. plain(nextRow.Text:GetText()))
	check(plain(RowOf("brief2").Text:GetText()) == "Zones: Elwynn Forest, Westfall", "the zones it covers")
	local row = RowOf("q7001")
	check(plain(row.Num:GetText()) == "1." and plain(row.Title:GetText()) == "[11] Wanted: Hogger"
		and plain(row.Status:GetText()) == "Pick up at Marshal Dughan · Elwynn Forest" and row.Badge:IsShown() and plain(row.Badge.Text:GetText()) == "1/3",
		"a quest: its number, [11] Title, its chain's 1/3, where it stands")
	check(plain(RowOf("q7006").Status:GetText()) == "Your level is too low: from level 20" and plain(RowOf("q7005").Status:GetText()) == "Needs Wanted: Hogger",
		"why one can't be taken yet")
	check(row.Remove._kind == "Button" and row.Up == nil and row.Down == nil and row._dragButtons and row._dragButtons[1] == "LeftButton",
		"remove: a Button; moved by dragging the row (no up and down)")
	-- Moving: dragged (the cursor at a row's top, or near its bottom), and removing.
	local scroll = view.list.scroll
	scroll.GetTop = function() return 500 end
	local function Drag(key, toKey, low)
		local r = RowOf(key)
		r._scripts.OnDragStart(r)
		local e = RowOf(toKey).entry
		CURSOR.y = 500 - (e.y + (low and e.h - 2 or 2) - scroll:GetVerticalScroll())
		view.Dragger._scripts.OnUpdate(view.Dragger, 0)
		return r
	end
	local r = Drag("q7004", "q7001")
	check(view.Dragger:IsShown() and view.DropLine:IsShown() and r._alpha == 0.4 and select(5, view.DropLine:GetPoint(1)) == 1 - RowOf("q7001").entry.y,
		"dragged: dim, the gold line where it would land")
	r._scripts.OnDragStop(r)
	Wait(0.1)
	check(table.concat(Q.PlanList(), ",") == "7004,7001,7006,7005" and Entries():find("q7004, q7001", 1, true) and not view.DropLine:IsShown()
		and not view.Dragger:IsShown() and RowOf("q7004")._alpha == 1, "let go above the first: the first")
	r = Drag("q7004", "q7005", true)
	r._scripts.OnDragStop(r)
	Wait(0.1)
	check(table.concat(Q.PlanList(), ",") == "7001,7006,7005,7004", "below the last: the last")
	r = Drag("q7004", "q7006")
	view.Dragger:Hide()
	check(table.concat(Q.PlanList(), ",") == "7001,7006,7005,7004" and not view.DropLine:IsShown() and r._alpha == 1, "given up (the view hidden): as it was")
	r = Drag("q7004", "q7004", true)
	r._scripts.OnDragStop(r)
	check(table.concat(Q.PlanList(), ",") == "7001,7006,7005,7004", "let go where it was: no change")
	r = Drag("q7004", "q7006")
	r._scripts.OnDragStop(r)
	Wait(0.1)
	check(table.concat(Q.PlanList(), ",") == "7001,7004,7006,7005", "above another: before it")
	RowOf("q7006").Remove:Click()
	Wait(0.1)
	check(table.concat(Q.PlanList(), ",") == "7001,7004,7005", "removed")
	-- The clicks.
	row = RowOf("q7001")
	row:Click()
	check(details[#details] == 7001, "a click: its details (Q.ShowDetails), the tab stays")
	STATE.ctrl = true
	row:Click()
	STATE.ctrl = false
	check(onMap[#onMap][1] == 7001 and onMap[#onMap][2] == nil, "Ctrl-click: on the map (Q.ShowOnMap)")
	row:Click("RightButton")
	check(chained[#chained] == 7001, "right-click: its chain")
	STATE.shift = true
	row:Click()
	STATE.shift = false
	check(pins[#pins].x == 0.42 and pins[#pins].map == ELWYNN, "Shift-click: the map pin at its next stop")
	row._scripts.OnEnter(row)
	check(plain(TOOLTIP.title) == "[11] Wanted: Hogger" and tipHas("Pick up at Marshal Dughan") and tipHas("Step 1 of 3")
		and tipHas("- Pick up Wanted: Hogger at Marshal Dughan · Elwynn Forest") and tipHas("Click: its details")
		and tipHas("Ctrl-click: show it on the map") and tipHas("Right-click (or 1/3): open the chain") and tipHas("Alt-click: remove from plan")
		and tipHas("Drag: move it in your order"), "its tooltip: where it stands, its stops, the clicks")
	row._scripts.OnLeave(row)
	STATE.alt = true
	RowOf("q7005"):Click()
	STATE.alt = false
	Wait(0.1)
	check(table.concat(Q.PlanList(), ",") == "7001,7004" and details[#details] ~= 7005, "Alt-click: out of the plan (as on the map's pins)")
	Q.PlanAdd(7005)
	Wait(0.1)
	-- A route.
	Replace("SuggestRoute", nil)
	view:Refresh()
	Wait(0.1)
	check(not view.RouteChip:IsShown(), "without Route.lua: no Suggest a route: " .. tostring(Q.SuggestRoute))
	Replace("SuggestRoute", function(stops) -- (the quests the other way round)
		local byQuest, quests, order = {}, {}, {}
		for _, s in ipairs(stops) do
			if not byQuest[s.quest] then byQuest[s.quest] = {}; quests[#quests + 1] = s.quest end
			if not s.done then table.insert(byQuest[s.quest], s) end
		end
		for i = #quests, 1, -1 do for _, s in ipairs(byQuest[quests[i]]) do order[#order + 1] = s end end
		return { order = order, before = 2340, after = 1100 }
	end)
	view:Refresh()
	Wait(0.1)
	check(view.RouteChip:IsShown() and plain(view.RouteChip.Text:GetText()) == "Suggest a route" and plain(view.Sub:GetText()):find("^Your order"),
		"with it: Suggest a route")
	view.RouteChip:Click()
	check(Q.PlanRouteInfo().active and plain(view.RouteChip.Text:GetText()) == "Back to my order"
		and plain(view.Sub:GetText()) == "Suggested route · Saves about 1200 yards", "suggested: what it saves (rounded)")
	check(Entries():find("^s7005:start:0, s7005:end:0, s7004:start:0, s7004:end:0") and not Entries():find("q7001", 1, true), "the route's stops instead of the quests: " .. Entries())
	local first = RowOf("s7005:start:0")
	check(plain(first.Num:GetText()) == "1." and first.Band:IsShown() and plain(first.Text:GetText()) == "Pick up Hogger's Lair at Marshal Dughan",
		"numbered, the next one marked")
	first._scripts.OnEnter(first)
	check(plain(TOOLTIP.title) == "1. Pick up Hogger's Lair at Marshal Dughan" and tipHas("Next") and tipHas("Alt-click: remove from plan"),
		"a stop's tooltip: what it is, the next one, the clicks")
	first._scripts.OnLeave(first)
	local turnin = RowOf("s7004:end:0")
	check(plain(turnin.Text:GetText()) == "Turn in at Gryan Stoutmantle · [12] A Dusty Letter" and plain(turnin.Right:GetText()) == "Westfall",
		"a turn-in: where, which quest, its zone")
	STATE.ctrl = true
	turnin:Click()
	STATE.ctrl = false
	check(onMap[#onMap][1] == 7004 and onMap[#onMap][2] and onMap[#onMap][2].x == 0.56, "Ctrl-click a stop: that spot on the map")
	turnin:Click()
	check(details[#details] == 7004, "a click: the quest's details")
	-- A change drops it.
	Q.PlanRemove(7005)
	Wait(0.1)
	check(not Q.PlanRouteInfo().active and plain(view.Sub:GetText()) == "The plan changed: back to your order." and Entries():find("q7001", 1, true),
		"the plan changed: back to the order, and it says so")
	view.RouteChip:Click()
	view.RouteChip:Click()
	check(not Q.PlanRouteInfo().active and plain(view.Sub:GetText()):find("^Your order"), "Back to my order")
	-- Clear asks first.
	view.ClearChip:Click()
	check(view.Ask:IsShown() and view.Yes:IsShown() and view.No:IsShown() and not view.ClearChip:IsShown() and plain(view.Ask:GetText()) == "Clear your whole plan?",
		"Clear asks first (ours, not a Blizzard popup)")
	view.No:Click()
	check(not view.Ask:IsShown() and #Q.PlanList() == 2, "Cancel: nothing gone")
	view.ClearChip:Click()
	view.Yes:Click()
	check(#Q.PlanList() == 0 and view.Message:IsShown(), "Clear it: empty")
	-- The controller: every new thing a Button; nothing of Blizzard's.
	Q.PlanAdd(7001)
	Wait(0.1)
	row = RowOf("q7001")
	check(view.RouteChip._kind == "Button" and view.ClearChip._kind == "Button" and view.Yes._kind == "Button" and row._kind == "Button"
		and row.Badge._kind == "Button" and view.frame.useCustomNavigation == nil, "every button a Button the controller reaches")
	Hide()
	Wait(0.1)
	check(not census.pulse:IsShown() and not census.listening, "hidden: nothing runs")
end

-- Back as it was.
Q.PlanClear()
for name, fn in pairs(replaced) do
	Q[name] = fn or nil
end
C_QuestLog.GetAllCompletedQuestIDs = savedCompleted
QUESTS, PLAYER_MAP, PLAYER_LEVEL, MY_GUID = savedQuests, savedMap, savedLevel, savedGuid
PLAYER_POS[1], PLAYER_POS[2] = savedPos[1], savedPos[2]
QUEST_MONSTERS_KILLED = savedFormat
LefthyToolsDB.lodestar.plans = nil
Progress()
Wait(math.ceil(waited) - waited + 1)
