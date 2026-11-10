-- Questtree: the quest browser's three views (Views.lua): storylines (every chain for me as cards,
-- filters, sorted by worth or level, a click opens the chain), the level path (zones of my side as
-- bars across the levels, shaded per level, my level, friends' dots, sorted by what I can take
-- around my level, a click opens the zone) and continents (a tile per zone by how much is done,
-- available and ready counts, friends' progress). Registering with the window's registry once it's
-- there (the module's enable), building on the registry's build(parent), the counts made a slice a
-- frame and only again when the data or my progress changes, events only while a view is shown,
-- pools, no data, the controller.
-- Data.lua and Engine.lua are in the build: the quests go in through Q.SetTestData. The window's
-- registry (Q.RegisterBrowserView) and Q.SelectZone come from the big window's part in parallel:
-- here the registry is a stand-in that records what's registered, put in for the checks and the
-- real one (if there is one) put back; Q.OpenBrowser and Q.SelectZone are recorders while this file
-- runs. Whatever it replaces is put back at its end.
-- Needs: no other file.

local suite = ...
local check, section, ns, LT = suite.check, suite.section, suite.ns, suite.LT
local tooltipHas = suite.tooltipHas
local Q = ns.Questtree
local M = LT:GetModule("questtree")

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
	return ((text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
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
	[1011] = Quest(1011, "Bounty on Murlocs", 7, 5, ELWYNN, { pre = { 1010 } }),
	[1020] = Quest(1020, "Wolves Across the Border", 4, 2, ELWYNN),
	-- Westfall: a long chain on into Darkshore, a chain I'm on, two alone.
	[1100] = Quest(1100, "The People's Militia", 10, 9, WESTFALL, { starts = { GRYAN } }),
	[1101] = Quest(1101, "The Defias Brotherhood", 12, 10, WESTFALL, { pre = { 1100 }, starts = { GRYAN } }),
	[1102] = Quest(1102, "The Coast Isn't Clear", 14, 12, WESTFALL, { pre = { 1101 }, starts = { GRYAN } }),
	[1103] = Quest(1103, "Red Leather Bandanas", 16, 14, WESTFALL, { pre = { 1102 }, starts = { GRYAN } }),
	[1110] = Quest(1110, "Westfall Stew", 11, 9, WESTFALL, { starts = { GRYAN } }),
	[1111] = Quest(1111, "Goretusk Liver Pie", 13, 10, WESTFALL, { pre = { 1110 }, starts = { GRYAN } }),
	[1120] = Quest(1120, "Poor Old Blanchy", 12, 10, WESTFALL, { starts = { GRYAN } }),
	[1121] = Quest(1121, "Keeper of the Flame", 18, 16, WESTFALL, { starts = { GRYAN } }),
	-- Redridge: too high for me now.
	[1200] = Quest(1200, "Encroaching Gnolls", 17, 15, REDRIDGE, { starts = { KAT } }),
	[1201] = Quest(1201, "Assessing the Threat", 19, 16, REDRIDGE, { pre = { 1200 }, starts = { KAT } }),
	[1210] = Quest(1210, "Redridge Goulash", 15, 13, REDRIDGE, { starts = { KAT } }),
	-- Durotar: the Horde's.
	[1300] = Quest(1300, "Your Place in the World", 2, 1, DUROTAR, { faction = "Horde" }),
	[1301] = Quest(1301, "Cutting Teeth", 3, 1, DUROTAR, { faction = "Horde", pre = { 1300 } }),
	-- Darkshore: a chain of its own, and the Westfall chain's last step.
	[1400] = Quest(1400, "The Red Crystal", 12, 10, DARKSHORE),
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

-- My progress: completed quests and the quest log ({ id, ... } or { { id, complete } }).
local completed = { [1001] = true, [1002] = true, [1003] = true, [1010] = true }
local savedCompleted = C_QuestLog.GetAllCompletedQuestIDs
C_QuestLog.GetAllCompletedQuestIDs = function()
	local list = {}
	for id in pairs(completed) do list[#list + 1] = id end
	return list
end
local savedQuests, savedMap, savedLevel = QUESTS, PLAYER_MAP, PLAYER_LEVEL
local function Log(list)
	QUESTS = {}
	for _, e in ipairs(list) do
		local id = type(e) == "table" and e[1] or e
		QUESTS[#QUESTS + 1] = { id = id, title = QUESTS_DATA[id].title, complete = type(e) == "table" and e[2] or false, objectives = {} }
	end
end
local function Progress() -- the engine reads my progress again (as after a loading screen)
	Fire("PLAYER_ENTERING_WORLD", false, false)
	Fire("QUEST_LOG_UPDATE")
end

-- The jumps into the window, recorded.
local opened, selected = {}, {}
Replace("OpenBrowser", function(id) opened[#opened + 1] = id end)
Replace("SelectZone", function(map) selected[#selected + 1] = map end)

-- Friends: Beacon's (where they are) and their quest progress (QuestShare.lua's).
local beacon = LT:GetModule("beacon")
local savedPeers, savedBeaconOn = beacon and rawget(beacon, "GetPeers"), beacon and beacon.enabled
local PEERS = {
	[11] = { name = "Anna Brook", classFile = "MAGE", level = 13, area = "Westfall" },
	[12] = { name = "Bob", classFile = "WARRIOR", level = 30, area = "Stranglethorn Vale" },
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

PLAYER_LEVEL, PLAYER_MAP = 12, WESTFALL
Q.SetTestData(QUESTS_DATA, ZONES)
Log({ { 1011, true }, 1110 })
Progress()

local state = Q.ViewsState()
local census, K = state.census, state.K
local startsBefore = census.starts

---------------------------------------------------------------------------
section("Questtree views: registering with the window")
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
	check(Q.ViewsState().registered and table.concat(keys, ", ") == "storylines=Storylines, levelpath=Level path, continents=Continents",
		"the registry there: the three views registered once, on the module's enable, got " .. table.concat(keys, ", "))
	check(census.starts == startsBefore, "nothing counted before a view is shown")
end

local function BuildOn(index)
	local parent = CreateFrame("Frame", nil, UIParent)
	parent:SetSize(1000, 600)
	local view = registry[index].build(parent)
	view.frame:Hide() -- (the registry shows a view when its tab is picked)
	return view, parent
end
local storylines, levelpath, continents = BuildOn(1), BuildOn(2), BuildOn(3)
check(type(storylines.frame) == "table" and type(storylines.Refresh) == "function" and type(storylines.OnShow) == "function"
	and type(storylines.OnHide) == "function" and storylines.frame:GetParent() ~= nil, "build(parent): { frame, Refresh, OnShow, OnHide } in the parent")

-- Shown the way the registry does it.
local function Show(view)
	view.frame:Show()
	view:OnShow()
end
local function Hide(view)
	view.frame:Hide()
	view:OnHide()
end

---------------------------------------------------------------------------
section("Questtree views: storylines")
---------------------------------------------------------------------------
local cards
local function Cards(view)
	local out = {}
	for _, e in ipairs(view.list.entries) do
		local row = view.list:Row(e.key)
		for i, c in ipairs(e.chains) do out[#out + 1] = { chain = c, card = row and row.cards[i] } end
	end
	return out
end
local function Titles(view)
	local out = {}
	for _, c in ipairs(Cards(view)) do out[#out + 1] = c.chain.title end
	return table.concat(out, ", ")
end
local function CardOf(view, first)
	for _, c in ipairs(Cards(view)) do if c.chain.first == first then return c.card, c.chain end end
end
do
	local slice = K.SLICE
	K.SLICE = 5
	Show(storylines)
	local slices = census.slices
	check(census.work and not census.data and storylines.Message:IsShown()
		and plain(storylines.Message:GetText()):find("Counting the quests of every zone", 1, true),
		"shown: counting starts, a few quests a frame; meanwhile it says so")
	Wait(1)
	check(census.data and census.slices - slices > 3 and not census.work and not census.pulse:IsShown(),
		"counted over several frames (" .. (census.slices - slices) .. "), then nothing runs")
	K.SLICE = slice
	check(not storylines.Message:IsShown() and storylines.list.scroll:IsShown(), "then the cards")
	check(Titles(storylines) == "The People's Militia, The Red Crystal, Westfall Stew, Encroaching Gnolls, Princess Must Die, A Threat Within",
		"every chain for me, by worth (what's left, by level; done ones last): " .. Titles(storylines))
	local chips = storylines.chips
	check(plain(chips.all.Text:GetText()) == "All (6)" and plain(chips.progress.Text:GetText()) == "In progress (2)"
		and plain(chips.ready.Text:GetText()) == "Ready to turn in (1)" and plain(chips.level.Text:GetText()) == "For your level (2)"
		and plain(chips.done.Text:GetText()) == "Done (1)" and chips.all.on, "the filters with their counts, All picked")
	local card, chain = CardOf(storylines, 1100)
	check(card and plain(card.Title:GetText()) == "The People's Militia" and plain(card.Meta:GetText()) == "Westfall  ·  [10-18]"
		and plain(card.Steps:GetText()) == "0/5 steps" and plain(card.Next:GetText()) == "Next: [10] The People's Militia"
		and card.state == "available", "a card: title, its zone (most of its steps) and levels, steps, the next one")
	check(chain.zoneList[2] == DARKSHORE and #chain.ids == 5, "a chain across zones is one storyline")
	card._scripts.OnEnter(card)
	check(TOOLTIP.title == "The People's Militia" and tipHas("Westfall, Darkshore") and tipHas("0 of 5 steps done")
		and tipHas("From Gryan Stoutmantle") and tipHas("Worth: 5 quests left for you") and tipHas("Click: open this storyline"),
		"its tooltip: zones, steps, the giver of the next step, what it's worth")
	card._scripts.OnLeave(card)
	card:Click()
	check(opened[#opened] == 1100, "a click opens the chain in the window on its next step")
	local ready = CardOf(storylines, 1010)
	check(ready.state == "ready" and plain(ready.Next:GetText()) == "Turn in: [7] Bounty on Murlocs", "a step ready to turn in says so")
	ready:Click()
	check(opened[#opened] == 1011, "its click: the quest to turn in")
	local done = CardOf(storylines, 1001)
	check(done.state == "done" and plain(done.Next:GetText()) == "All done" and done.Bar.fraction == 1, "a chain done: all done, a full bar")
	-- Filters and sorting, kept in the module's settings.
	chips.ready:Click()
	check(Titles(storylines) == "Princess Must Die" and M.db.views.filter == "ready" and chips.ready.on, "Ready to turn in: only that one; kept")
	chips.progress:Click()
	check(Titles(storylines) == "Westfall Stew, Princess Must Die", "In progress: started, not finished")
	chips.level:Click()
	check(Titles(storylines) == "The People's Militia, The Red Crystal", "For your level: a step I can take that isn't grey")
	chips.all:Click()
	storylines.sorts.level:Click()
	check(Titles(storylines) == "Princess Must Die, The People's Militia, Westfall Stew, The Red Crystal, Encroaching Gnolls, A Threat Within"
		and M.db.views.sort == "level", "sorted by the next step's level (done ones last): " .. Titles(storylines))
	storylines.sorts.worth:Click()
	check(M.db.views.sort == "worth", "and by worth again")
end

---------------------------------------------------------------------------
section("Questtree views: events while shown, turning in, the data changing")
---------------------------------------------------------------------------
do
	local starts, draws = census.starts, storylines.draws
	Fire("QUEST_LOG_UPDATE")
	Fire("QUEST_LOG_UPDATE")
	check(storylines.draws == draws, "an event: nothing at once")
	Wait(0.6)
	check(storylines.draws == draws + 1 and census.starts == starts, "drawn half a second later, once; the log alone doesn't count again")
	completed[1011] = true
	Log({ 1110 })
	Fire("QUEST_TURNED_IN", 1011, 0, 0)
	Wait(0.6)
	check(census.starts == starts + 1 and plain(storylines.chips.done.Text:GetText()) == "Done (2)"
		and plain(storylines.chips.ready.Text:GetText()) == "Ready to turn in (0)", "a quest turned in: counted again, the chain done")
	storylines.chips.ready:Click()
	check(storylines.Message:IsShown() and plain(storylines.Message:GetText()) == "No storyline matches this filter."
		and storylines.Guide:IsShown(), "a filter with nothing: says so, with a way back")
	storylines.Guide:Click()
	check(M.db.views.filter == "all" and not storylines.Message:IsShown(), "the button shows them all again")
	-- Refresh (the window's): drawn on the next frame, counted again only if something changed.
	draws, starts = storylines.draws, census.starts
	storylines:Refresh()
	Wait(0.1)
	check(storylines.draws == draws + 1 and census.starts == starts, "Refresh: drawn again, nothing counted again")
end

---------------------------------------------------------------------------
section("Questtree views: the level path")
---------------------------------------------------------------------------
local function Rows(view)
	local out = {}
	for _, e in ipairs(view.list.entries) do out[#out + 1] = e.zone.name end
	return table.concat(out, ", ")
end
local function RowOf(view, map) return view.list:Row("z" .. map), view.list.entries end
do
	Hide(storylines)
	Show(levelpath)
	check(Rows(levelpath) == "Westfall, Darkshore, Elwynn Forest, Redridge Mountains",
		"the zones of my side (not the Horde's), most to take around my level first: " .. Rows(levelpath))
	check(plain(levelpath.Head:GetText()) == "Best next: Westfall, 2 quests for your level", "the best next zone on top")
	local row = RowOf(levelpath, WESTFALL)
	local e = row.entry
	local function runs(entry)
		local out = {}
		for _, r in ipairs(entry.runs) do out[#out + 1] = r[1] .. "-" .. r[2] .. " " .. r[3] end
		return table.concat(out, ", ")
	end
	check(runs(e) == "9-18 open" or runs(e) == "9-12 open, 13-18 later", "Westfall's levels: open, then later: " .. runs(e))
	local elwynn = RowOf(levelpath, ELWYNN).entry
	check(runs(elwynn) == "1-3 done, 4-4 open, 5-10 done", "Elwynn's: done, one open, done: " .. runs(elwynn))
	check(e.here and row.Here:IsShown() and plain(row.Name:GetText()) == "Westfall (you're here)", "the zone I'm in is marked")
	check(plain(row.Right:GetText()) == "2 for your level" and plain(row.Sub:GetText()) == "[9-18]  0 of 8 done", "its counts")
	check(row.friendDots == 1 and #e.friends == 1 and e.friends[1].name == "Anna Brook", "a friend there: a dot at her level")
	local me = levelpath.x0 + (12 - 1) * levelpath.per + levelpath.per / 2
	check(math.abs(select(4, row.Me:GetPoint(1)) - me) < 0.01 and plain(levelpath.Axis.You:GetText()) == "You (12)", "a line at my level")
	row._scripts.OnEnter(row)
	check(TOOLTIP.title == "Westfall" and tipHas("2 you can take now, 2 of them within 3 levels of yours") and tipHas("1 in your quest log")
		and tipHas("Anna Brook level 13") and tipHas("You're here.") and tipHas("Click: open this zone"), "its tooltip")
	row._scripts.OnLeave(row)
	row:Click()
	check(selected[#selected] == WESTFALL, "a click opens the zone in the window")
	-- Without Q.SelectZone: the zone's first quest.
	local select = Q.SelectZone
	Q.SelectZone = nil
	RowOf(levelpath, ELWYNN):Click()
	Q.SelectZone = select
	check(opened[#opened] == 1001, "without Q.SelectZone: the window opens on the zone's first quest")
	-- A level up: counted again, the order follows.
	PLAYER_LEVEL = 15
	Fire("PLAYER_LEVEL_UP", 15)
	Wait(0.6)
	check(Rows(levelpath) == "Redridge Mountains, Westfall, Darkshore, Elwynn Forest" and plain(levelpath.Axis.You:GetText()) == "You (15)",
		"a level up: Redridge comes first, my line moves: " .. Rows(levelpath))
	PLAYER_LEVEL = 12
	Fire("PLAYER_LEVEL_UP", 12)
	Wait(0.6)
	-- Friends' setting off: no dots.
	M.db.friends = false
	levelpath:Refresh()
	Wait(0.1)
	check(RowOf(levelpath, WESTFALL).friendDots == 0, "friends off: no dots")
	M.db.friends = true
end

---------------------------------------------------------------------------
section("Questtree views: continents")
---------------------------------------------------------------------------
local function TileOf(view, map)
	for _, e in ipairs(view.list.entries) do
		local row = view.list:Row(e.key)
		for i, t in ipairs(e.tiles or {}) do
			if t.zone.map == map then return row and row.tiles[i], t end
		end
	end
end
do
	Hide(levelpath)
	Show(continents)
	local outline = {}
	for _, e in ipairs(continents.list.entries) do
		if e.kind == "head" then
			outline[#outline + 1] = "#" .. e.name .. " " .. e.done .. "/" .. e.total
		else
			for _, t in ipairs(e.tiles) do outline[#outline + 1] = t.zone.name end
		end
	end
	check(table.concat(outline, ", ") == "#Kalimdor 0/3, Darkshore, #Eastern Kingdoms 5/17, Elwynn Forest, Westfall, Redridge Mountains",
		"by continent (in the data's order) with their counts, a tile per zone with quests for me: " .. table.concat(outline, ", "))
	check(plain(continents.Head:GetText()) == "Every zone: 5 of 20 quests done (25%)", "all of it on top")
	local tile = TileOf(continents, ELWYNN)
	check(tile and plain(tile.Pct:GetText()) == "83%" and plain(tile.Counts:GetText()) == "1 available" and math.abs(tile.Bar.fraction - 5 / 6) < 1e-6,
		"a tile: how much is done, what I can take, a bar")
	check(tile.FBar.Back:IsShown() and math.abs(tile.FBar.fraction - 2 / 6) < 1e-6, "friends' progress: the one furthest along, a second bar")
	tile._scripts.OnEnter(tile)
	check(TOOLTIP.title == "Elwynn Forest" and tipHas("5 of 6 done") and tipHas("Anna Brook 2 done (that you know of)") and tipHas("Cleo 1 done"),
		"its tooltip names the friends")
	tile._scripts.OnLeave(tile)
	-- Ready to turn in, from the quest log.
	Log({ { 1110, true } })
	Fire("QUEST_LOG_UPDATE")
	Wait(0.6)
	local west = TileOf(continents, WESTFALL)
	check(plain(west.Counts:GetText()) == "2 available  1 ready" and not TileOf(continents, DUROTAR), "ready to turn in counted; the Horde's zone isn't there")
	west:Click()
	check(selected[#selected] == WESTFALL, "a click opens the zone")
	Log({ 1110 })
end

---------------------------------------------------------------------------
section("Questtree views: hidden, nothing runs; shown again, counted if needed")
---------------------------------------------------------------------------
do
	Hide(continents)
	check(not census.listening and not census.pulse:IsShown(), "no view shown: no events, no OnUpdate")
	local starts, draws = census.starts, continents.draws
	completed[1100] = true
	Fire("QUEST_TURNED_IN", 1100, 0, 0)
	Wait(1)
	check(census.starts == starts and continents.draws == draws, "an event while hidden: nothing")
	Show(continents)
	Wait(0.2)
	check(census.starts == starts + 1 and plain(TileOf(continents, WESTFALL).Pct:GetText()) == "12%", "shown again: counted again, as it is now")
	-- The data changing while shown.
	starts = census.starts
	Q.SetTestData(QUESTS_DATA, ZONES)
	Wait(0.2)
	check(census.starts == starts + 1, "the data changed: counted again")
	Hide(continents)
end

---------------------------------------------------------------------------
section("Questtree views: many storylines, only the cards in sight")
---------------------------------------------------------------------------
do
	local STV = 1434
	local many = {}
	for id, q in pairs(QUESTS_DATA) do many[id] = q end
	for i = 1, 300 do
		local a, b = 5000 + 2 * i, 5001 + 2 * i
		many[a] = Quest(a, "Chain " .. i, 30 + i % 20, 30, STV)
		many[b] = Quest(b, "Chain " .. i .. " part two", 31 + i % 20, 30, STV, { pre = { a } })
	end
	local zones = { ZONES[1], ZONES[2], { map = STV, name = "Stranglethorn Vale", continent = EK, minLevel = 30, maxLevel = 45 } }
	Q.SetTestData(many, zones)
	Show(storylines)
	local slices = census.slices
	Wait(1)
	local list = storylines.list
	check(#storylines.shown == 306 and #list.entries == 102 and census.slices - slices >= 4,
		"306 storylines in rows of 3, counted over " .. (census.slices - slices) .. " frames")
	check(list.made <= 12, "only the rows near sight are made: " .. list.made)
	local key = list.entries[2].key
	local kept = list:Row(key)
	list.scroll:SetVerticalScroll(60)
	list.scroll._scripts.OnVerticalScroll(list.scroll, 60)
	check(list:Row(key) == kept and kept.entry.key == key, "scrolled a bit: a row stays on its entry (a controller's cursor stays on it)")
	list.scroll:SetVerticalScroll(4000)
	list.scroll._scripts.OnVerticalScroll(list.scroll, 4000)
	check(list:Row(list.entries[50].key) and not list:Row(key) and list.made <= 14, "scrolled far: the rows go round")
	Hide(storylines)
	Q.SetTestData(QUESTS_DATA, ZONES)
end

---------------------------------------------------------------------------
section("Questtree views: no data, the controller, a fight")
---------------------------------------------------------------------------
do
	local load = Q.Load
	Replace("Load", function() return false end)
	Show(continents)
	check(continents.Message:IsShown() and plain(continents.Message:GetText()):find("The quest data isn't there", 1, true)
		and not continents.list.scroll:IsShown(), "no data: says so")
	Hide(continents)
	Q.Load = load
	Show(continents)
	Wait(0.5)
	check(not continents.Message:IsShown() and continents.list.scroll:IsShown(), "the data there again: the tiles")
	Hide(continents)
	-- The registry's OnShow before the frame shows: drawn all the same.
	local draws = continents.draws
	continents:OnShow()
	check(continents.draws == draws + 1 and not continents.frame:IsShown(), "OnShow before its frame shows: drawn all the same")
	continents.frame:Show()
	Wait(0.1)
	check(continents.draws == draws + 1, "and once")
	Hide(continents)
	-- Every card, row, tile and chip is a Button of ours; nothing of Blizzard's on our frames.
	Show(storylines)
	Show(levelpath)
	Wait(0.5)
	local buttons, count = true, 0
	local function Each(list, field)
		for _, row in pairs(list.used) do
			if field then
				for _, b in ipairs(row[field] or {}) do buttons = buttons and b._kind == "Button"; count = count + 1 end
			else
				buttons = buttons and row._kind == "Button"
				count = count + 1
			end
		end
	end
	Each(storylines.list, "cards")
	Each(levelpath.list)
	for _, chip in pairs(storylines.chips) do buttons = buttons and chip._kind == "Button" end
	buttons = buttons and storylines.sorts.worth._kind == "Button" and storylines.Guide._kind == "Button"
	Show(continents)
	Wait(0.5)
	Each(continents.list, "tiles")
	check(buttons and count > 10, "every card, row, tile, chip and button is a Button the controller reaches")
	local blizzard = false
	for _, v in ipairs({ storylines, levelpath, continents }) do
		for _, f in ipairs({ v.frame, v.list.scroll, v.list.child }) do
			blizzard = blizzard or f.useCustomNavigation ~= nil or f.smartNavigationIgnored ~= nil
		end
	end
	check(not blizzard, "nothing of Blizzard's on our frames")
	local blocked = #BLOCKED
	EnterCombat()
	storylines.chips.done:Click()
	RowOf(levelpath, WESTFALL):Click()
	LeaveCombat()
	check(#BLOCKED == blocked and selected[#selected] == WESTFALL, "in a fight too")
	storylines.chips.all:Click()
	Hide(storylines)
	Hide(levelpath)
	Hide(continents)
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
M.db.views = nil
Progress()
Wait(math.ceil(waited) - waited + 1)
