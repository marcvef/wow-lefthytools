-- Questtree: the big window (Browser.lua), against a small made-up world. The data and engine (Q.Load,
-- Q.Quest, Q.Zones, Q.Status, Q.Chain, ...), the small window (Q.ShowQuest, Q.IsSmallShown) and the
-- small map (Q.NewMiniMap) are stand-ins installed here, so every row is certain; the real ones are put
-- back at the end. The empty window without the data, the zones by continent with their counts, the
-- tree (columns, lines, statuses, other zones, folding), the details (title from the client,
-- requirements, givers, the map, Needs first and Leads to across zones, friends, the small window),
-- the search staying through clicks, events and data changes redrawn on the next frame only while
-- it's open, the pools, a small screen, the controller's buttons.
-- Needs: no other file.
local suite = ...
local check, section, ns, LT = suite.check, suite.section, suite.ns, suite.LT
local Q = ns.Questtree

local function plain(text)
	return ((text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
end

local waited = 0 -- (the clock goes on by whole seconds, for the files after this one)
local function Wait(s)
	Advance(s)
	waited = waited + s
end

-- The world: three zones on two continents and a dungeon.
local ELWYNN, WESTFALL, DUROTAR, STV = 1429, 1436, 1411, 1434
local EK, KALIMDOR = 1415, 1414
MAP_NAMES[WESTFALL], MAP_NAMES[DUROTAR], MAP_NAMES[STV] = "Westfall", "Durotar", "Stranglethorn Vale"
local function at(map, x, y) return { map = map, x = x, y = y } end
local DUGHAN = { kind = "npc", id = 240, name = "Marshal Dughan", points = { at(ELWYNN, 0.42, 0.66) } }
local QUESTS_DATA = {
	[101] = { id = 101, title = "A Threat Within", level = 1, minLevel = 1, zone = ELWYNN, opens = { 102 } },
	[102] = { id = 102, title = "Kobold Camp Cleanup", level = 2, minLevel = 1, zone = ELWYNN, pre = { 101 }, opens = { 103, 104 } },
	[103] = { id = 103, title = "Investigate Echo Ridge", level = 3, minLevel = 2, zone = ELWYNN, pre = { 102 }, opens = { 105 } },
	[104] = { id = 104, title = "Brotherhood of Thieves", level = 4, minLevel = 2, zone = ELWYNN, pre = { 102 },
		races = 77, classes = 1, skill = { id = 165, value = 50 }, rep = { faction = 72, min = 3000 }, repeatable = true, new = true,
		starts = { DUGHAN, { kind = "object", id = 9, name = "Wanted Poster", points = { at(ELWYNN, 0.45, 0.6) } } },
		ends = { { kind = "npc", id = 241, name = "Deputy Willem", points = { at(ELWYNN, 0.48, 0.42) } } } },
	[105] = { id = 105, title = "Skirmish at Echo Ridge", level = 5, minLevel = 3, zone = ELWYNN, pre = { 103 }, opens = { 201 } },
	[110] = { id = 110, title = "Wolves Across the Border", level = 2, minLevel = 1, zone = ELWYNN },
	[111] = { id = 111, title = "Princess Must Die", level = 9, minLevel = 7, zone = ELWYNN },
	[112] = { id = 112, title = "A Horde Errand", level = 5, minLevel = 4, zone = ELWYNN, faction = "Horde" },
	[201] = { id = 201, title = "The People's Militia", level = 10, minLevel = 9, zone = WESTFALL, pre = { 105 } },
	[202] = { id = 202, title = "The Defias Brotherhood", level = 14, minLevel = 12, zone = WESTFALL, pre = { 301 } },
	[301] = { id = 301, title = "Red Silk Bandanas", level = 17, minLevel = 14, zone = WESTFALL, dungeon = "The Deadmines" },
	[401] = { id = 401, title = "Your Place in the World", level = 1, minLevel = 1, zone = DUROTAR, faction = "Horde", source = "learned" },
}
local ZONES = {
	{ map = ELWYNN, name = "Elwynn Forest", continent = EK, minLevel = 1, maxLevel = 10 },
	{ map = WESTFALL, name = "Westfall", continent = EK, minLevel = 9, maxLevel = 18 },
	{ map = DUROTAR, name = "Durotar", continent = KALIMDOR, minLevel = 1, maxLevel = 10 },
}
local ZONE_QUESTS = { [ELWYNN] = { 101, 102, 103, 104, 105, 110, 111, 112 }, [WESTFALL] = { 201, 202 }, [DUROTAR] = { 401 } }
local DUNGEON_QUESTS = { ["The Deadmines"] = { 301 } }
local CHAIN = { 101, 102, 103, 104, 105, 201 }
local STATUS_OF = { [101] = "done", [102] = "done", [103] = "active", [104] = "available", [105] = "locked", [110] = "available",
	[111] = "level", [112] = "other", [201] = "locked", [202] = "locked", [301] = "level", [401] = "other" }
local MISSING = { [105] = { { id = 103, status = "active" } }, [201] = { { id = 103, status = "active" }, { id = 105, status = "locked" } },
	[202] = { { id = 301, status = "level" } } }
local FRIENDS = { [104] = { { name = "Anna Brook", classFile = "MAGE", status = "done" }, { name = "Bob", classFile = "WARRIOR", status = "active" } } }

local loaded, dataCallbacks, shownInSmall, smallOpen, maps, calls = false, {}, {}, false, {}, { Status = 0, Chain = 0 }
local stand = {
	Load = function() return loaded end,
	HasData = function() return loaded end,
	Quest = function(id) return QUESTS_DATA[id] end,
	Zones = function() return ZONES end,
	Dungeons = function() return { { name = "The Deadmines", minLevel = 17, maxLevel = 24, count = 1 } } end,
	ZoneQuests = function(map) return ZONE_QUESTS[map] or {} end,
	DungeonQuests = function(name) return DUNGEON_QUESTS[name] or {} end,
	Search = function(text)
		local out = {}
		for _, list in ipairs({ ZONE_QUESTS[ELWYNN], ZONE_QUESTS[WESTFALL], ZONE_QUESTS[DUROTAR], ZONE_QUESTS[STV] or {} }) do
			for _, id in ipairs(list) do
				if QUESTS_DATA[id].title:lower():find(text:lower(), 1, true) then out[#out + 1] = id end
			end
		end
		return out
	end,
	Status = function(id) calls.Status = calls.Status + 1; return STATUS_OF[id] or "available" end,
	Missing = function(id) return MISSING[id] or {} end,
	Opens = function(id) return QUESTS_DATA[id] and QUESTS_DATA[id].opens or {} end,
	Chain = function(id)
		calls.Chain = calls.Chain + 1
		for _, c in ipairs(CHAIN) do if c == id then return CHAIN end end
		return { id }
	end,
	Friends = function(id) return FRIENDS[id] or {} end,
	OnDataChanged = function(fn) dataCallbacks[#dataCallbacks + 1] = fn end,
	ShowQuest = function(id) shownInSmall[#shownInSmall + 1] = id end,
	IsSmallShown = function() return smallOpen end,
	NewMiniMap = function(parent)
		local m = { parent = parent }
		function m:Show(map, points) maps[#maps + 1] = { map = map, points = points } end
		return m
	end,
}
local saved, questLogBefore, blockedBefore = {}, QUESTS, #BLOCKED
QUESTS = {} -- (the quest log: the client's titles)
for key, fn in pairs(stand) do
	saved[key] = Q[key] or false
	Q[key] = fn
end

-- Whatever an earlier file left of the window: from the start.
do
	local view, st = Q.BrowserView()
	if view then Q.HideBrowser(); view.Box:SetText("") end
	st.where, st.picked, st.query, st.results, st.drilled, st.places, st.opened = nil, nil, "", nil, false, nil, nil
	wipe(st.folded); wipe(st.trees); wipe(st.counts)
end

local view, st, win
local function refs() view, st, win = Q.BrowserView() end
local function zoneRow(id)
	for _, row in pairs(view.zones.rows) do
		local e = row:IsShown() and row.entry
		if e and (e.id == id or e.key == id) then return row end
	end
end
local function treeRow(match)
	for _, row in pairs(view.tree.rows) do
		local e = row:IsShown() and row.entry
		if e and (e.quest == match or e.key == match or (match == "back" and e.back) or (match == "search" and e.search)) then return row end
	end
end
-- The middle as words: "#" a header, a quest's ID after ">" per column it's in.
local function outline()
	local out = {}
	for _, e in ipairs(view.tree.entries) do
		out[#out + 1] = e.header and (e.back and "#back" or "#") or ((">"):rep(e.depth) .. e.quest)
	end
	return table.concat(out, " ")
end
local function zonesOutline()
	local out = {}
	for _, e in ipairs(view.zones.entries) do out[#out + 1] = e.header and ("#" .. e.label) or e.name end
	return table.concat(out, ", ")
end
local function rails(e)
	local out = {}
	for col = 0, 3 do out[#out + 1] = tostring(e.rails and e.rails[col] or 0) end
	return table.concat(out) .. (e.stub and ("s" .. e.stub) or "")
end
local function entryOf(id) for _, e in ipairs(view.tree.entries) do if e.quest == id then return e end end end

section("Questtree: the big window without the data")
do
	Q.OpenBrowser()
	refs()
	check(win == LefthyToolsQuesttreeBrowser and win:IsShown() and win.TitleContainer.TitleText:GetText() == "Questtree",
		"it opens, called Questtree (never translated)")
	check(view.Empty:IsShown() and not view.root:IsShown() and not view.Box:IsShown() and not view.Legend:IsShown()
		and plain(view.Empty:GetText()):find("LefthyTools_QuestData", 1, true),
		"no data addon: a line saying so, no panes, no search")
	check(#dataCallbacks == 1 or st.listening, "it listens for data changes")
	local found
	for _, name in ipairs(UISpecialFrames) do found = found or name == "LefthyToolsQuesttreeBrowser" end
	check(found, "Escape closes it (UISpecialFrames)")
	Q.ToggleBrowser()
	check(not win:IsShown(), "toggled: closed")
end

section("Questtree: the big window, zones on the left")
do
	loaded = true
	Q.ToggleBrowser()
	check(win:IsShown() and view.root:IsShown() and not view.Empty:IsShown() and view.Box:IsShown(), "with the data: the panes")
	check(win:GetWidth() == 1200 and win:GetHeight() == 760 and win:GetScale() == 1, "1200 x 760, not scaled on a big screen")
	check(zonesOutline() == "#Eastern Kingdoms, Elwynn Forest, Westfall, #Kalimdor, Durotar, #Dungeons, The Deadmines",
		"by continent, then the dungeons, got: " .. zonesOutline())
	check(st.where == "z:1429" and zoneRow("z:1429").Picked:IsShown() and not zoneRow("z:1436").Picked:IsShown(),
		"the zone I'm in is chosen at first")
	local elwynn = zoneRow("z:1429")
	check(elwynn.Name:GetText() == "Elwynn Forest" and elwynn.Range:GetText() == "1-10" and plain(elwynn.Count:GetText()) == "2 of 7",
		"name, level range, done of those for me (the Horde quest isn't counted), got " .. tostring(plain(elwynn.Count:GetText())))
	check(plain(zoneRow("z:1411").Count:GetText()) == "-" and zoneRow("d:The Deadmines").Range:GetText() == "17-24", "Durotar: nothing for me; the dungeon's range")
	check(plain(view.Head:GetText()) == "Elwynn Forest  Level 1-10   2 of 7 done", "the middle's title, got " .. plain(view.Head:GetText()))
	zoneRow("c:1415"):Click()
	check(zonesOutline() == "#Eastern Kingdoms, #Kalimdor, Durotar, #Dungeons, The Deadmines" and zoneRow("c:1415").Toggle.path:find("Plus", 1, true),
		"a continent folds")
	zoneRow("c:1415"):Click()
	check(zonesOutline():find("Elwynn Forest", 1, true), "and opens again")
	local legend = plain(view.Legend:GetText())
	check(legend:find("Completed", 1, true) and legend:find("In your quest log", 1, true) and legend:find("Locked", 1, true)
		and legend:find("Level too low", 1, true) and legend:find("Not for you", 1, true), "the legend names every status, got " .. legend)
end

section("Questtree: the big window, the tree")
do
	check(outline() == "# 101 102 >103 >105 >201 >104 # 110 112 111", "the chain in the order it's done: one next step stays in its column, "
		.. "a branch goes one in; then the quests without a chain by level, got: " .. outline())
	local e = view.tree.entries
	check(rails(e[2]) == "2000" and rails(e[3]) == "3000" and rails(e[4]) == "3200s0"
		and rails(e[5]) == "3300" and rails(e[6]) == "3100" and rails(e[7]) == "1000s0",
		"the lines: down from each step, through the rows between, a stub to a branch, got "
		.. rails(e[2]) .. " " .. rails(e[3]) .. " " .. rails(e[4]) .. " " .. rails(e[5]) .. " " .. rails(e[6]) .. " " .. rails(e[7]))
	local chain = treeRow("z:1429:101")
	check(plain(chain.Name:GetText()) == "A Threat Within" and chain.Right:GetText() == "2/6" and chain.Toggle.path:find("Minus", 1, true),
		"a chain's header: its first quest, done of total, open")
	check(plain(treeRow("z:1429:single").Name:GetText()) == "Quests without a chain" and treeRow("z:1429:single").Right:GetText() == "0/2",
		"the rest under a header of their own")
	local done, active, locked, level, other = treeRow(101), treeRow(103), treeRow(105), treeRow(111), treeRow(112)
	check(done.Name:GetText() == "[1] A Threat Within" and done.Name.color[1] == 0.3 and done.Name.color[2] == 0.85 and done.Marker.vertex[2] == 0.85,
		"a row: [level] title, done in green")
	check(active.Name.color[1] == 1 and active.Name.color[2] == 0.85 and level.Name.color[2] == 0.55 and other.Name.color[1] == 0.42,
		"in the log yellow, level too low orange, not for me dim")
	check(locked.Lock.shown and not locked.Marker.shown and locked.Name.color[1] == 0.6, "locked: grey with a lock")
	check(select(4, active.Marker:GetPoint(1)) == 10 + 14 and select(4, done.Marker:GetPoint(1)) == 10, "a column further in: 14 px")
	check(plain(treeRow(201).Right:GetText()) == "Westfall" and treeRow(105).Right:GetText() == "", "a step in another zone says which")
	chain:Click()
	check(outline() == "# # 110 112 111" and treeRow("z:1429:101").Toggle.path:find("Plus", 1, true), "a chain folds")
	treeRow("z:1429:101"):Click()
	check(outline():find("# 101 102", 1, true) == 1, "and opens")
	treeRow(103)._scripts.OnEnter(treeRow(103))
	check(TOOLTIP.shown and TOOLTIP.title == "Investigate Echo Ridge" and TOOLTIP.lines[1] == "In your quest log" and TOOLTIP.lines[3] == "Click: details",
		"hovering: a tooltip, title, status, where")
	treeRow(103)._scripts.OnLeave(treeRow(103))
	check(not TOOLTIP.shown, "gone when the mouse leaves")
end

section("Questtree: the big window, the details")
do
	check(view.d.Hint:IsShown() and not view.d.Body:IsShown() and not view.d.Small:IsShown(), "nothing chosen: a hint")
	local saveMap = Q.NewMiniMap
	Q.NewMiniMap = nil
	treeRow(104):Click()
	check(view.d.Body:IsShown() and not view.d.MapBox:IsShown() and #maps == 0, "no small map without Q.NewMiniMap")
	treeRow(105):Click()
	check(st.picked == 105 and treeRow(105).Picked:IsShown() and not treeRow(104).Picked:IsShown(), "a click: its row marked")
	check(plain(view.d.Title:GetText()) == "Skirmish at Echo Ridge" and plain(view.d.Sub:GetText()):find("Locked: an earlier quest comes first", 1, true)
		and plain(view.d.Sub:GetText()):find("Level 5, from level 3", 1, true) and plain(view.d.Sub:GetText()):find("Step 5 of 6 in its chain", 1, true),
		"title, status, level, the step, got " .. plain(view.d.Sub:GetText()))
	check(view.d.NeedsHead:IsShown() and view.d.links[1]:IsShown() and view.d.links[1].quest == 103
		and plain(view.d.links[1].Text:GetText()) == "[3] Investigate Echo Ridge", "Needs first: a button to the quest")
	check(view.d.LeadsHead:IsShown() and view.d.links[2].quest == 201 and plain(view.d.links[2].Text:GetText()) == "[10] The People's Militia - Westfall",
		"Leads to: the next one, its zone named")
	check(#shownInSmall == 0, "the small window closed: it isn't asked")
	view.d.links[1]:Click()
	check(st.picked == 103 and st.where == "z:1429" and plain(view.d.Title:GetText()) == "Investigate Echo Ridge" and treeRow(103).Picked:IsShown(),
		"a link opens that quest")

	-- The client's title (another language), requirements, givers, the map, friends.
	Q.NewMiniMap = saveMap
	QUESTS = { { id = 104, title = "Bruderschaft der Diebe", objectives = {} } }
	smallOpen = true
	treeRow(104):Click()
	check(shownInSmall[1] == 104, "the small window open: it shows the quest too")
	check(plain(view.d.Title:GetText()) == "Bruderschaft der Diebe" and plain(treeRow(104).Name:GetText()) == "[4] Bruderschaft der Diebe",
		"the client's title when it knows the quest")
	local req = plain(view.d.Req:GetText())
	check(req:find("Races: Human, Dwarf, Night Elf, Gnome", 1, true) and req:find("Classes: Warrior", 1, true) and req:find("Skill: Leatherworking 50", 1, true)
		and req:find("Reputation: #72, Friendly", 1, true), "requirements: races, classes, skill, reputation, got " .. req)
	check(plain(view.d.Sub:GetText()):find("New in WoW: Forever, Repeatable", 1, true), "new and repeatable")
	local places = plain(view.d.Places:GetText())
	check(places == "Starts at: Marshal Dughan - Elwynn Forest, Wanted Poster (an object) - Elwynn Forest\nTurn in at: Deputy Willem - Elwynn Forest",
		"who gives it and where to turn it in, got " .. places)
	local map = maps[#maps]
	check(view.d.MapBox:IsShown() and map and map.map == ELWYNN and #map.points == 3 and map.points[1].kind == "start" and map.points[3].kind == "end"
		and map.points[1].label == "Marshal Dughan" and map.points[1].x == 0.42, "the small map: the zone, givers and the ender")
	check(view.d.map.parent == view.d.MapBox, "made once, in the details")
	check(plain(view.d.Friends:GetText()) == "Friends\nAnna Brook (Completed), Bob (In your quest log)", "friends, got " .. plain(view.d.Friends:GetText()))
	check(view.d.Small:IsShown() and view.d.Small:GetText() == "Show in the small window", "a button for the small window")
	smallOpen = false
	view.d.Small:Click()
	check(shownInSmall[2] == 104, "... which shows it there")
	QUESTS = {}
	treeRow(101):Click()
	check(not view.d.Req:IsShown() and not view.d.Places:IsShown() and not view.d.MapBox:IsShown() and not view.d.Friends:IsShown()
		and not view.d.NeedsHead:IsShown() and view.d.LeadsHead:IsShown(), "a plain quest: only what it has")
end

section("Questtree: the big window, across zones")
do
	zoneRow("z:1436"):Click()
	check(st.where == "z:1436" and outline() == "# 101 102 >103 >105 >201 >104 # 202", "another zone: its tree, the whole chain, got " .. outline())
	check(plain(treeRow(201).Right:GetText()) == "" and plain(treeRow(101).Right:GetText()) == "Elwynn Forest", "the steps elsewhere say where")
	treeRow(202):Click()
	view.d.links[1]:Click()
	check(st.where == "d:The Deadmines" and st.picked == 301 and zoneRow("d:The Deadmines").Picked:IsShown() and outline() == "# 301",
		"Needs first in a dungeon: there, got " .. tostring(st.where) .. " " .. outline())
	zoneRow("c:1414"):Click()
	check(not zoneRow("z:1411"), "Kalimdor folded")
	Q.OpenBrowser(401)
	check(win:IsShown() and st.where == "z:1411" and st.picked == 401 and zoneRow("z:1411") and zoneRow("z:1411").Picked:IsShown(),
		"Q.OpenBrowser(id): its zone, its continent opened")
	check(plain(view.d.Sub:GetText()):find("Not for you", 1, true) and plain(view.d.Sub:GetText()):find("Learned while playing", 1, true)
		and plain(view.d.Req:GetText()):find("Faction: Horde", 1, true), "not for me: faction and where it came from")
	Q.OpenBrowser(103)
	check(st.where == "z:1429" and st.picked == 103 and treeRow(103):IsShown(), "back in Elwynn")
end

section("Questtree: the big window, the search")
do
	view.Box:SetText("echo")
	check(view.Clear:IsShown() and st.query == "", "typing: not searched yet")
	Wait(0.5)
	check(st.query == "echo" and outline() == "# 103 105" and plain(view.Head:GetText()) == "Search results"
		and treeRow("search").Right:GetText() == "2", "searched after a moment: the results replace the tree, got " .. outline())
	check(plain(treeRow(105).Right:GetText()) == "Elwynn Forest", "a result says its zone")
	treeRow(105):Click()
	check(st.drilled and st.picked == 105 and view.Box:GetText() == "echo" and outline():find("#back # 101", 1, true) == 1,
		"a result clicked: its zone's tree, a way back on top, the search stays")
	check(plain(treeRow("back").Name:GetText()) == "Back to the search results", "the back row says so")
	treeRow("back"):Click()
	check(not st.drilled and outline() == "# 103 105", "back: the results")
	zoneRow("z:1436"):Click()
	check(st.drilled and st.where == "z:1436" and outline():find("#back", 1, true) == 1, "a zone clicked during a search: its tree, inside the search")
	view.Box:SetText("e")
	Wait(0.5)
	check(view.Message:IsShown() and view.Message:GetText() == "Type at least two letters." and #view.tree.entries == 0, "one letter: not searched")
	view.Box:SetText("401")
	Wait(0.5)
	check(outline() == "# 401", "a quest's ID finds it")
	view.Box:SetText("zzz")
	Wait(0.5)
	check(view.Message:IsShown() and view.Message:GetText() == "Nothing found", "nothing found: says so")
	view.Clear:Click()
	check(st.query == "" and not view.Clear:IsShown() and not outline():find("#back", 1, true) and st.where == "z:1436", "cleared: the tree, where I was")
	view.Box:SetText("militia")
	Q.ToggleBrowser()
	Wait(0.5)
	check(st.query == "" and win:GetScript("OnUpdate") == nil, "closed right after typing: nothing runs")
	Q.ToggleBrowser()
	Wait(0.1)
	check(st.query == "militia" and outline() == "# 201", "opened again: searched then")
	view.Clear:Click()
end

section("Questtree: the big window, quests changing")
do
	Q.OpenBrowser(103)
	check(st.where == "z:1436" and st.picked == 103 and treeRow(103):IsShown(), "a quest in the tree shown (Westfall's chain): it stays there")
	zoneRow("z:1429"):Click()
	local draws = st.draws
	STATUS_OF[103] = "done"
	STATUS_OF[105] = "available"
	Fire("QUEST_TURNED_IN", 103, 100, 0)
	Fire("QUEST_ACCEPTED", 105)
	check(st.draws == draws and treeRow(103).Name.color[2] == 0.85 and treeRow(103).Name.color[1] == 1, "not in the event: nothing drawn yet")
	Wait(0.5)
	check(st.draws == draws + 1, "the next frame: drawn once for both, got " .. (st.draws - draws))
	check(treeRow(103).Name.color[1] == 0.3 and treeRow(105).Marker.shown and plain(zoneRow("z:1429").Count:GetText()) == "3 of 7"
		and treeRow("z:1429:101").Right:GetText() == "3/6", "the statuses, the zone's count and the chain's follow")
	Fire("PLAYER_LEVEL_UP", 10)
	Wait(0.1)
	Fire("QUEST_REMOVED", 105)
	Wait(0.6)
	check(st.draws == draws + 3, "two more events half a second apart: drawn for each, got " .. (st.draws - draws))
	Fire("QUEST_ACCEPTED", 104)
	Fire("QUEST_ACCEPTED", 110)
	Wait(0.6)
	check(st.draws == draws + 4, "two right after each other: one drawing")
	check(win:GetScript("OnUpdate") == nil, "nothing due: no OnUpdate")

	-- Closed: nothing heard, nothing runs; opened: as it is now.
	Q.ToggleBrowser()
	draws = st.draws
	STATUS_OF[104] = "done"
	Fire("QUEST_TURNED_IN", 104, 100, 0)
	Wait(1)
	check(st.draws == draws and win:GetScript("OnUpdate") == nil and not st.listening, "closed: events aren't listened to")
	Q.ToggleBrowser()
	check(plain(zoneRow("z:1429").Count:GetText()) == "4 of 7" and treeRow(104).Name.color[1] == 0.3, "opened again: the counts and statuses of now")

	-- The client's title coming in later: the rows in sight follow.
	local asked = {}
	C_QuestLog.RequestLoadQuestByID = function(id) asked[#asked + 1] = id end
	st.asked[110] = nil
	view.tree:Lay()
	view.tree:Lay()
	local times = 0
	for _, id in ipairs(asked) do times = times + (id == 110 and 1 or 0) end
	check(times == 1, "a title the client doesn't know: asked for, once, got " .. times)
	QUESTS = { { id = 110, title = "Wölfe über der Grenze", objectives = {} } }
	Fire("QUEST_DATA_LOAD_RESULT", 110, true)
	Wait(0.5)
	check(plain(treeRow(110).Name:GetText()) == "[2] Wölfe über der Grenze", "it came: the row shows it")
	QUESTS = {}
	C_QuestLog.RequestLoadQuestByID = nil
end

section("Questtree: the big window, the data changing")
do
	local _, _, _, changed = Q.BrowserView()
	QUESTS_DATA[113] = { id = 113, title = "Lost Necklace", level = 6, minLevel = 5, zone = ELWYNN }
	ZONE_QUESTS[ELWYNN][#ZONE_QUESTS[ELWYNN] + 1] = 113
	local built = st.trees_built
	changed()
	check(st.trees_built == built and not entryOf(113), "in the callback: nothing drawn")
	Wait(0.5)
	check(st.trees_built == built + 1 and entryOf(113) and outline():find("# 110 112 113 111", 1, true), "the next frame: worked out again, got " .. outline())
	Q.ToggleBrowser()
	ZONE_QUESTS[ELWYNN][#ZONE_QUESTS[ELWYNN]] = nil
	QUESTS_DATA[113] = nil
	changed()
	Wait(0.5)
	check(win:GetScript("OnUpdate") == nil, "closed: nothing runs for it")
	Q.ToggleBrowser()
	check(not entryOf(113), "it comes when the window opens")
	local before = st.trees_built
	zoneRow("z:1436"):Click()
	zoneRow("z:1429"):Click()
	check(st.trees_built == before + 1, "a tree is worked out once, then kept")
end

section("Questtree: the big window, a big zone")
do
	local list = {}
	for i = 1, 400 do
		local id = 5000 + i
		QUESTS_DATA[id] = { id = id, title = "Bloodsail Business " .. i, level = 30 + i % 10, zone = STV }
		list[i] = id
	end
	ZONE_QUESTS[STV] = list
	table.insert(ZONES, 3, { map = STV, name = "Stranglethorn Vale", continent = EK, minLevel = 30, maxLevel = 45 }) -- (by continent, then level)
	local _, _, _, changed = Q.BrowserView()
	changed()
	Wait(0.5)
	zoneRow("z:1434"):Click()
	local tree = view.tree
	check(#tree.entries == 401 and tree.made <= tree.pool and tree.pool == math.ceil(tree.height / 20) + 1 + 4,
		"400 quests: no more rows than a screen and a few, got " .. tree.made .. " of " .. tree.pool)
	local sight = math.ceil(tree.height / 20) + 1
	check(tree.rows[sight + 1] and tree.rows[sight + 1]:IsShown() and tree.rows[sight + 1].index == sight + 1,
		"rows below sight are laid too (the controller's next one)")
	local statuses = calls.Status
	tree.scroll:SetVerticalScroll(20 * 200)
	tree.scroll._scripts.OnVerticalScroll(tree.scroll, 20 * 200)
	check(calls.Status - statuses <= tree.pool, "scrolled: only the rows in sight read their status")
	local row = tree.rows[(210 - 1) % tree.pool + 1]
	check(row.index == 210 and row.entry == tree.entries[210] and row:IsShown(), "each entry keeps its row (a controller's cursor stays on its quest)")
	tree.scroll:SetVerticalScroll(20 * 201)
	tree.scroll._scripts.OnVerticalScroll(tree.scroll, 20 * 201)
	check(row.index == 210 and row.entry == tree.entries[210], "... also one row further")
	table.remove(ZONES, 3)
	ZONE_QUESTS[STV] = nil
	for i = 1, 400 do QUESTS_DATA[5000 + i] = nil end
	changed()
	Wait(0.5)
	check(st.where == "z:1429", "the zone gone: back to mine")
end

section("Questtree: the big window, a small screen and the controller")
do
	local width, height = GetScreenWidth, GetScreenHeight
	GetScreenWidth, GetScreenHeight = function() return 1024 end, function() return 768 end
	Q.ToggleBrowser()
	Q.ToggleBrowser()
	check(math.abs(win:GetScale() - (1024 - 40) / 1200) < 1e-6, "a small screen: scaled to fit, got " .. win:GetScale())
	GetScreenWidth, GetScreenHeight = width, height
	Q.ToggleBrowser()
	Q.ToggleBrowser()
	check(win:GetScale() == 1, "a big one: full size")
	local buttons = true
	for _, list in ipairs({ view.zones.rows, view.tree.rows, view.d.links }) do
		for _, b in pairs(list) do buttons = buttons and b._kind == "Button" end
	end
	check(buttons and view.d.Small._kind == "Button" and view.Clear._kind == "Button", "every row and link is a button the controller reaches")
	local blizzard = false
	for _, f in ipairs({ win, view.root, view.zones.scroll, view.tree.scroll, view.d.Scroll }) do
		blizzard = blizzard or f.useCustomNavigation ~= nil or f.smartNavigationIgnored ~= nil
	end
	check(not blizzard, "nothing of Blizzard's on our frames")
	GAMEPAD_STATE.ui = true
	Q.ToggleBrowser()
	Q.ToggleBrowser()
	check(win:IsShown() and view.root:IsShown(), "it opens in gamepad mode")
	GAMEPAD_STATE.ui = false
	EnterCombat()
	Q.ToggleBrowser()
	Q.ToggleBrowser()
	treeRow(101):Click()
	check(win:IsShown() and st.picked == 101 and #BLOCKED == blockedBefore, "and in a fight")
	LeaveCombat()
end

-- Back as it was: the window closed, the real functions.
Q.HideBrowser()
for key, fn in pairs(saved) do
	Q[key] = fn or nil
end
MAP_NAMES[WESTFALL], MAP_NAMES[DUROTAR], MAP_NAMES[STV] = nil, nil, nil
QUESTS = questLogBefore
Wait(math.ceil(waited) - waited + 1)
