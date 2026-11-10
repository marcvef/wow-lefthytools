-- Questtree: the big window (Browser.lua), against a small made-up world. The data and engine (Q.Load,
-- Q.Quest, Q.Zones, Q.Status, Q.Chain, ...), the iterations' ones (Q.ZoneCount, Q.ChainStep,
-- Q.LevelColor, Q.Races, Q.ZoneGiven, Q.Available, Q.IsTrivial, Q.InRange in its new meaning: from my
-- level on, not grey, not red; Q.WhyOther, Q.Needs), this round's Q.Objectives and Q.Rewards (Data.lua
-- makes them in parallel: stand-ins of the shared contract here), the small window (Q.ShowQuest,
-- Q.IsSmallShown) are stand-ins installed here, so every card is certain; the real ones are put back
-- at the end. Without some of them the window works too (counted here, the step from Q.Chain, the
-- level against mine, no objectives or rewards). The empty window without the data, its size (wider
-- on a big screen), the zones by continent with their counts (far ones dimmed); the zone page: the
-- zone's map filling the middle (pins grouped with a count, the game's icons, what each pin is in its
-- tooltip, a pin's quests in a list of ours to pick one, right-click or Shift-click: the game's map
-- pin, a chain's thread only while hovered or picked, the wheel zooming where the cursor is, -, +,
-- Fit, my arrow), the quest picked on it (its giver ringed, its turn-in, its objectives' areas in its
-- chain's colour, the way between them, an objective's line lighting its area), one line under it, a
-- zone to go to when there's nothing; the right pane: the zone's briefing (levels, how far along,
-- what's for my level, turn in now, in progress here, the chains' two-line cards, the done ones
-- folded, a line saying how many more, hovering a card or a pin lights the other), a chain's
-- briefing (its steps), the details (the way back, the reason, the chain's steps around it,
-- objectives with my progress, giver and turn-in, rewards with the game's item tooltips, the map
-- pin, the companion), never empty; a chain opened (every level, stages, centred, lanes, lines that
-- never run through a card or look joined when they aren't, their colours, "one of", dashed lead-ins,
-- stubs for other zones and a click on one, the way back to a locked quest across zones, the pulse,
-- the line under it); the filters (all levels, not for me, a skipped quest stays), the canvas (pools,
-- scrolling, zoom, a card the controller reaches out of sight), the quest list (groups, the skipped
-- with the done ones, reasons; a dungeon's Zone tab), the search, the views other files register
-- (lazily built, shown, hidden, refreshed, Q.ShowBrowserView, Q.SelectZone, Q.OpenBrowser from one,
-- one that fails), events and data changes redrawn on the next frame only while it's open (my
-- progress in the quest log, items the client learns), a small screen, the controller's buttons.
-- Needs: no other file.
local suite = ...
local check, section, ns, LT = suite.check, suite.section, suite.ns, suite.LT
local Q = ns.Questtree

local function plain(text)
	return ((text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", ""))
end

local waited = 0 -- (the clock goes on by whole seconds, for the files after this one)
local function Wait(s)
	Advance(s)
	waited = waited + s
end

-- The world: four zones on two continents and a dungeon.
local ELWYNN, WESTFALL, DUROTAR, STV, REDRIDGE = 1429, 1436, 1411, 1434, 1433
local EK, KALIMDOR = 1415, 1414
MAP_NAMES[DUROTAR], MAP_NAMES[STV], MAP_NAMES[REDRIDGE] = "Durotar", "Stranglethorn Vale", "Redridge Mountains"
local function at(map, x, y) return { map = map, x = x, y = y } end
local DUGHAN = { kind = "npc", id = 240, name = "Marshal Dughan", points = { at(ELWYNN, 0.42, 0.66) } }
local WILLEM = { kind = "npc", id = 241, name = "Deputy Willem", points = { at(ELWYNN, 0.48, 0.42) } }
local ROBERTS = { kind = "npc", id = 243, name = "Guard Roberts", points = { at(ELWYNN, 0.2, 0.2) } }
local FANG = { kind = "item", id = 7001, name = "Wolf Fang", points = {}, drops = {
	{ kind = "npc", id = 300, name = "Young Wolf", chance = 12, points = { at(ELWYNN, 0.3, 0.7) } },
	{ kind = "npc", id = 301, name = "Timber Wolf", chance = 0.5, points = { at(ELWYNN, 0.6, 0.8) } } } }
local QUESTS_DATA = {
	[101] = { id = 101, title = "A Threat Within", level = 1, minLevel = 1, zone = ELWYNN, opens = { 102 }, starts = { DUGHAN }, ends = { WILLEM } },
	[102] = { id = 102, title = "Kobold Camp Cleanup", level = 2, minLevel = 1, zone = ELWYNN, pre = { 101 }, opens = { 103, 104 } },
	[103] = { id = 103, title = "Investigate Echo Ridge", level = 3, minLevel = 2, zone = ELWYNN, pre = { 102 }, opens = { 105 }, ends = { WILLEM } },
	[104] = { id = 104, title = "Brotherhood of Thieves", level = 4, minLevel = 2, zone = ELWYNN, pre = { 102 }, excl = { 106 },
		races = 77, classes = 1, skill = { id = 165, value = 50 }, rep = { faction = 72, min = 3000 }, repeatable = true, new = true,
		starts = { DUGHAN, { kind = "object", id = 9, name = "Wanted Poster", points = { at(ELWYNN, 0.45, 0.6) } } },
		ends = { WILLEM } },
	[105] = { id = 105, title = "Skirmish at Echo Ridge", level = 5, minLevel = 3, zone = ELWYNN, pre = { 103 }, opens = { 201 }, starts = { WILLEM } },
	[106] = { id = 106, title = "Report to Goldshire", level = 6, minLevel = 4, zone = ELWYNN, preAny = { 103, 104 } },
	[107] = { id = 107, title = "Speak with Willem", level = 2, minLevel = 1, zone = ELWYNN, breadcrumbFor = 103, opens = { 103 }, starts = { ROBERTS } },
	[108] = { id = 108, title = "Bounty on Murlocs", level = 7, minLevel = 5, zone = ELWYNN, pre = { 102, 105 } },
	[110] = { id = 110, title = "Wolves Across the Border", level = 2, minLevel = 1, zone = ELWYNN, starts = { FANG } },
	[111] = { id = 111, title = "Princess Must Die", level = 9, minLevel = 7, zone = ELWYNN,
		starts = { { kind = "npc", id = 250, name = "Remy", points = { at(ELWYNN, 0.7, 0.3) } } } },
	[112] = { id = 112, title = "A Horde Errand", level = 5, minLevel = 4, zone = ELWYNN, faction = "Horde" },
	[201] = { id = 201, title = "The People's Militia", level = 10, minLevel = 9, zone = WESTFALL, pre = { 105 } },
	[202] = { id = 202, title = "The Defias Brotherhood", level = 17, minLevel = 12, zone = WESTFALL, pre = { 301 } },
	[301] = { id = 301, title = "Red Silk Bandanas", level = 17, minLevel = 14, zone = WESTFALL, dungeon = "The Deadmines", opens = { 202 } },
	[401] = { id = 401, title = "Your Place in the World", level = 1, minLevel = 1, zone = DUROTAR, faction = "Horde", source = "learned",
		races = 2 ^ 31 + 1 },
	[501] = { id = 501, title = "Encroaching Gnolls", level = 16, minLevel = 14, zone = REDRIDGE },
}
local ZONES = {
	{ map = ELWYNN, name = "Elwynn Forest", continent = EK, minLevel = 1, maxLevel = 10 },
	{ map = WESTFALL, name = "Westfall", continent = EK, minLevel = 9, maxLevel = 18 },
	{ map = REDRIDGE, name = "Redridge Mountains", continent = EK, minLevel = 15, maxLevel = 25 },
	{ map = DUROTAR, name = "Durotar", continent = KALIMDOR, minLevel = 1, maxLevel = 10 },
}
local ZONE_QUESTS = { [ELWYNN] = { 101, 102, 103, 104, 105, 106, 107, 108, 110, 111, 112 }, [WESTFALL] = { 201, 202 }, [DUROTAR] = { 401 },
	[REDRIDGE] = { 501 } }
local DUNGEON_QUESTS = { ["The Deadmines"] = { 301 } }
local CHAINS = { { 101, 102, 107, 103, 104, 105, 106, 108, 201 }, { 301, 202 } }
local STATUS_OF = { [101] = "done", [102] = "done", [103] = "active", [104] = "available", [105] = "locked", [106] = "locked",
	[107] = "available", [108] = "locked", [110] = "available", [111] = "level", [112] = "other", [201] = "locked", [202] = "locked",
	[301] = "level", [401] = "other", [501] = "available" }
local MISSING = { [105] = { { id = 103, status = "active" } }, [201] = { { id = 103, status = "active" }, { id = 105, status = "locked" } },
	[202] = { { id = 301, status = "level" } }, [106] = { { id = 103, status = "active" } },
	[108] = { { id = 103, status = "active" }, { id = 105, status = "locked" } } }
local FRIENDS = { [104] = { { name = "Anna Brook", classFile = "MAGE", status = "done" }, { name = "Bob", classFile = "WARRIOR", status = "active" } } }
local TRIVIAL = { [107] = true }
local FAR = { [111] = true } -- (more than 2 levels above mine: with TRIVIAL, outside my levels: Q.InRange)
local WHY = { [112] = "faction", [401] = "race" } -- (why an "other" one isn't for me: Q.WhyOther)
local NEEDS = {} -- (a reputation or profession rank a locked one needs: Q.Needs)
-- Q.Objectives and Q.Rewards as the shared contract has them (Data.lua's are made in parallel).
local function area(map, x, y, r) return { map = map, x = x, y = y, r = r } end
local OBJECTIVES = {
	[103] = {
		{ kind = "kill", id = 6, name = "Kobold Vermin", count = 10, sources = {
			{ kind = "npc", id = 6, name = "Kobold Vermin", points = { area(ELWYNN, 0.4, 0.5, 0.03), area(ELWYNN, 0.56, 0.46, 0.02) } } } },
		{ kind = "item", id = 7002, name = "Gold Dust", count = 8, sources = {
			{ kind = "npc", id = 40, name = "Kobold Miner", chance = 32, points = { area(ELWYNN, 0.6, 0.55, 0.04) } },
			{ kind = "object", id = 41, name = "Old Chest", chance = 5, points = { area(WESTFALL, 0.5, 0.5, 0.02) } } } },
	},
	[104] = { { kind = "object", id = 30, name = "Wanted Poster", count = 1, sources = {
		{ kind = "object", id = 30, name = "Wanted Poster", points = { area(ELWYNN, 0.47, 0.58, 0.01) } } } } },
}
local REWARDS = { [104] = { choice = { { id = 2075, count = 1 }, { id = 1155, count = 1 } }, items = { { id = 2589, count = 5 } }, money = 12050, xp = 1250 } }
local function ChainOf(id)
	for _, chain in ipairs(CHAINS) do
		for _, c in ipairs(chain) do if c == id then return chain end end
	end
end
local function Count(map) -- (what Data's Q.ZoneCount answers: every quest for me, any level)
	local done, total = 0, 0
	for _, id in ipairs(ZONE_QUESTS[map] or DUNGEON_QUESTS[map] or {}) do
		if STATUS_OF[id] ~= "other" then
			total = total + 1
			done = done + (STATUS_OF[id] == "done" and 1 or 0)
		end
	end
	return done, total
end

local loaded, dataCallbacks, shownInSmall, smallOpen, calls = false, {}, {}, false, { Status = 0, Chain = 0, ZoneCount = 0, Available = 0 }
local stand = {
	Load = function() return loaded end,
	HasData = function() return loaded end,
	Quest = function(id) return QUESTS_DATA[id] end,
	Zones = function() return ZONES end,
	Dungeons = function() return { { name = "The Deadmines", minLevel = 17, maxLevel = 24, count = 1 } } end,
	ZoneQuests = function(map) return ZONE_QUESTS[map] or {} end,
	DungeonQuests = function(name) return DUNGEON_QUESTS[name] or {} end,
	ZoneGiven = function(map) return map == WESTFALL and { 301 } or {} end,
	Search = function(text)
		local out = {}
		for _, list in ipairs({ ZONE_QUESTS[ELWYNN], ZONE_QUESTS[WESTFALL], ZONE_QUESTS[DUROTAR], ZONE_QUESTS[REDRIDGE], ZONE_QUESTS[STV] or {} }) do
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
		return ChainOf(id) or { id }
	end,
	ZoneCount = function(map) calls.ZoneCount = calls.ZoneCount + 1; return Count(map) end,
	ChainStep = function(id)
		local chain = ChainOf(id)
		if not chain then return nil end
		for i, c in ipairs(chain) do
			if c == id then return i, #chain, chain[1] == 101 and "Elwynn's Kobolds" or QUESTS_DATA[chain[1]].title, chain[1] end
		end
	end,
	LevelColor = function(level) return { r = 0.2, g = 0.4, b = 0.6, hex = "ff336699", key = "test" } end,
	Races = function() return { { id = 1, bit = 1, name = "Human" }, { id = 2, bit = 2, name = "Orc" }, { id = 95, bit = 32, name = "High Order Skyborne" } } end,
	Available = function(map)
		calls.Available = calls.Available + 1
		local out = {}
		for _, id in ipairs(ZONE_QUESTS[map] or {}) do if STATUS_OF[id] == "available" then out[#out + 1] = id end end
		return out
	end,
	IsTrivial = function(id) return TRIVIAL[id] == true end,
	InRange = function(id) -- (this round's: in my log, or from my level on, not grey, at most 4 above me)
		local q = QUESTS_DATA[id]
		local my = UnitLevel("player")
		return STATUS_OF[id] == "active" or not (TRIVIAL[id] or FAR[id] or (q and q.minLevel and q.minLevel > my) or (q and q.level and q.level > my + 4))
	end,
	Objectives = function(id) return OBJECTIVES[id] or {} end,
	Rewards = function(id) return REWARDS[id] end,
	WhyOther = function(id)
		local w = STATUS_OF[id] == "other" and WHY[id]
		if type(w) == "table" then return w[1], w[2] end
		return w or nil
	end,
	Needs = function(id) return NEEDS[id] end,
	Friends = function(id) return FRIENDS[id] or {} end,
	OnDataChanged = function(fn) dataCallbacks[#dataCallbacks + 1] = fn end,
	ShowQuest = function(id) shownInSmall[#shownInSmall + 1] = id end,
	IsSmallShown = function() return smallOpen end,
}
local saved, questLogBefore, blockedBefore = {}, QUESTS, #BLOCKED
QUESTS = {} -- (the quest log: the client's titles)
for key, fn in pairs(stand) do
	saved[key] = Q[key] or false
	Q[key] = fn
end
local M = LT:GetModule("questtree")
local browserSaved = M and M.db and M.db.browser
if M and M.db then M.db.browser = nil end

-- Whatever an earlier file left of the window: from the start.
do
	local view, st = Q.BrowserView()
	if view then Q.HideBrowser(); view.Box:SetText("") end
	st.where, st.picked, st.query, st.results, st.drilled, st.places, st.opened, st.tab, st.chain = nil, nil, "", nil, false, nil, nil, "zone", nil
	wipe(st.folded); wipe(st.trees); wipe(st.counts); wipe(st.layouts); wipe(st.infos); wipe(st.spots)
	if st.why then wipe(st.why); wipe(st.range) end
end

local view, st, win, filters, registry
local function refs()
	local v, s, w, _, f, r = Q.BrowserView()
	view, st, win, filters, registry = v, s, w, f, r
end
local function zoneRow(id)
	for _, row in pairs(view.zones.rows) do
		local e = row:IsShown() and row.entry
		if e and (e.id == id or e.key == id) then return row end
	end
end
local function listRow(match)
	for _, row in pairs(view.list.rows) do
		local e = row:IsShown() and row.entry
		if e and (e.quest == match or e.key == match or (match == "search" and e.search) or (match == "more" and e.more)) then return row end
	end
end
local function chainCard(key) -- a chain's card in the zone's briefing (its key: "z:1429:101")
	for _, card in ipairs(view.b.cards) do
		local e = card:IsShown() and view.b.Scroll:IsShown() and card.entry
		if e and e.key == key then return card end
	end
end
local function cardsOutline()
	local out = {}
	for _, card in ipairs(view.b.cards) do
		if card:IsShown() and card.entry then out[#out + 1] = card.entry.key end
	end
	return table.concat(out, " ")
end
local function briefRows() -- the briefing's quest rows: "id" each, "id:sub" with a line under it
	local out = {}
	for _, row in ipairs(view.b.rows) do
		if row:IsShown() and row.quest then out[#out + 1] = tostring(row.quest) end
	end
	return table.concat(out, " ")
end
local function heads(pool) -- the section heads shown, in order
	local list = {}
	for _, h in ipairs(pool) do
		if h:IsShown() then list[#list + 1] = { y = -h._points[1][3], text = plain(h.Text:GetText()) } end
	end
	table.sort(list, function(a, b) return a.y < b.y end)
	local out = {}
	for _, h in ipairs(list) do out[#out + 1] = h.text end
	return table.concat(out, " | ")
end
local function detailHeads()
	local d = view.d
	return heads({ d.ChainHead, d.ObjHead, d.WhereHead, d.RewardHead, d.ReqHead, d.NeedsHead, d.LeadsHead, d.FriendsHead })
end
local function unpick() if view.d.Panel:IsShown() then view.d.Back:Click() end end
-- The game's map pin API (the mock has none): pins set are recorded; off() takes it away again.
local function pinStubs()
	local pins = {}
	C_Map.SetUserWaypoint = function(point) pins[#pins + 1] = point end
	C_Map.CanSetUserWaypointOnMap = function(map) return map == ELWYNN end
	UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { uiMapID = map, x = x, y = y } end }
	C_SuperTrack.SetSuperTrackedUserWaypoint = function(on) pins.tracked = on end
	function pins.off()
		C_Map.SetUserWaypoint, C_Map.CanSetUserWaypointOnMap, UiMapPoint, C_SuperTrack.SetSuperTrackedUserWaypoint = nil, nil, nil, nil
	end
	return pins
end
local function zonesOutline()
	local out = {}
	for _, e in ipairs(view.zones.entries) do out[#out + 1] = e.header and ("#" .. e.label) or e.name end
	return table.concat(out, ", ")
end
local function listOutline()
	local out = {}
	for _, e in ipairs(view.list.entries) do out[#out + 1] = e.header and ("#" .. e.label) or e.more and ("+" .. e.n) or tostring(e.quest) end
	return table.concat(out, " ")
end
local function lay() return view.g.layout end
local function item(id) return lay().byQuest[id] end
local function card(id) return view.g.cards[id] end
-- A chain's page as words: each card "id@stage" in the layout's order (a stub "id@stage*").
local function graphOutline()
	local out = {}
	for _, it in ipairs(lay().cards) do
		out[#out + 1] = (it.stage and (it.quest .. "@" .. it.stage) or tostring(it.quest)) .. (it.stub and "*" or "")
	end
	return table.concat(out, " ")
end
local function segsOf(fromId, toId) -- an edge's segments
	local list = {}
	for _, s in ipairs(lay().segs) do
		if s.from == fromId and s.to == toId then list[#list + 1] = s end
	end
	return list
end
local function marker(label)
	local m = view.zp.map
	for i = 1, m.shown do
		for _, spot in ipairs(m.markers[i].spots) do
			if (spot.label or ""):find(label, 1, true) then return m.markers[i] end
		end
	end
end
local function openChain(key) chainCard(key):Click() end
local CHAIN1, SINGLES = "z:1429:101", "z:1429:single"

section("Questtree: the big window without the data")
do
	Q.OpenBrowser()
	refs()
	check(win == LefthyToolsQuesttreeBrowser and win:IsShown() and win.TitleContainer.TitleText:GetText() == "Questtree",
		"it opens, called Questtree (never translated)")
	check(view.Empty:IsShown() and not view.root:IsShown() and not view.Box:IsShown() and not view.filters.allLevels:IsShown()
		and plain(view.Empty:GetText()):find("LefthyTools_QuestData", 1, true),
		"no data addon: a line saying so, no panes, no search, no filters")
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
	check(win:GetWidth() == 1700 and win:GetHeight() == 868 and view.W == 1700 and win:GetScale() == 1,
		"a big screen (1920 x 1080): wider (1700), as high as the map needs (868), not scaled, got " .. win:GetWidth() .. " x " .. win:GetHeight())
	check(zonesOutline() == "#Eastern Kingdoms, Elwynn Forest, Westfall, Redridge Mountains, #Kalimdor, Durotar, #Dungeons, The Deadmines",
		"by continent, then the dungeons, got: " .. zonesOutline())
	check(st.where == "z:1429" and zoneRow("z:1429").Picked:IsShown() and not zoneRow("z:1436").Picked:IsShown(),
		"the zone I'm in is chosen at first")
	local elwynn = zoneRow("z:1429")
	check(elwynn.Name:GetText() == "Elwynn Forest" and elwynn.Range:GetText() == "1-10" and plain(elwynn.Count:GetText()) == "2 of 10"
		and calls.ZoneCount > 0, "name, level range, done of every quest for me at any level (Q.ZoneCount), got " .. tostring(plain(elwynn.Count:GetText())))
	check(elwynn.Bar:IsShown() and math.abs(elwynn.Bar.width - (elwynn:GetWidth() - 24) * 2 / 10) < 0.01, "a thin bar: how far along")
	check(plain(zoneRow("z:1411").Count:GetText()) == "-" and zoneRow("d:The Deadmines").Range:GetText() == "17-24"
		and plain(zoneRow("d:The Deadmines").Count:GetText()) == "0 of 1", "Durotar: nothing for me; the dungeon by its name")
	-- Without Q.ZoneCount (Data.lua before iteration 2): counted here, the same.
	Q.ZoneCount = nil
	wipe(st.counts)
	view.zones:Lay()
	check(plain(zoneRow("z:1429").Count:GetText()) == "2 of 10", "without Q.ZoneCount: counted here, got " .. plain(zoneRow("z:1429").Count:GetText()))
	Q.ZoneCount = stand.ZoneCount
	zoneRow("c:1415"):Click()
	check(zonesOutline() == "#Eastern Kingdoms, #Kalimdor, Durotar, #Dungeons, The Deadmines" and zoneRow("c:1415").Toggle.path:find("Plus", 1, true),
		"a continent folds")
	zoneRow("c:1415"):Click()
	check(zonesOutline():find("Elwynn Forest", 1, true), "and opens again")
	check(not view.Legend:IsShown(), "no legend of the statuses on the zone page (they say their reason themselves)")
	check(not zoneRow("z:1429").Name:GetText():find("|c", 1, true) and not zoneRow("d:The Deadmines").Name:GetText():find("|c", 1, true),
		"zones near my level (19): not dimmed")
end

section("Questtree: the big window, the tab bar")
do
	check(view.tabs.zone and view.tabs.overview and view.tabs.zone:IsShown() and view.tabs.overview:IsShown()
		and plain(view.tabs.zone.Text:GetText()) == "Zone" and plain(view.tabs.overview.Text:GetText()) == "Quest list"
		and view.tabs.zone.Line:IsShown() and not view.tabs.overview.Line:IsShown(), "the zone page's tab first, then the quest list (key overview)")
	local x1 = view.tabs.zone._points[1][2]
	local x2 = view.tabs.overview._points[1][2]
	check(x1 == 0 and x2 == view.tabs.zone:GetWidth() + 4, "side by side")
	check(st.tab == "zone" and view.zp:IsShown() and not view.g.frame:IsShown() and not view.list.scroll:IsShown()
		and not view.head:IsShown(), "the zone page shows, right under the tabs (no head: the briefing on the right has it)")
end

section("Questtree: the big window, the zone page's map")
do
	local m = view.zp.map
	check(m.frame:IsShown() and m.map == ELWYNN and m.width == 1012 and m.height == 674 and m.shown == 5,
		"the zone's map fills the middle (1012 x 674, 3:2): givers, turn-ins, drop areas within my levels, got "
		.. m.width .. " x " .. m.height .. ", " .. m.shown)
	check(plain(m.Zone:GetText()) == "Elwynn Forest  1-10" and m.buttons.minus._kind == "Button" and m.buttons.plus._kind == "Button"
		and m.buttons.fit._kind == "Button" and view.zp.Line._points[1][3] == -(674 + 4), "its strip: the zone, its levels, -, + and Fit; a line under it")
	check(not marker("Guard Roberts") and not marker("Remy"), "a low level quest and one far above me: not by default (Q.InRange)")
	view.filters.allLevels:Click()
	check(filters.allLevels and m.shown == 7 and M.db.browser.allLevels == true, "all levels: they're there too, kept in the settings, got " .. m.shown)
	local roberts, remy = marker("Guard Roberts"), marker("Remy")
	check(roberts and roberts.look == "trivial" and roberts.Icon.atlas == "TrivialQuests", "a low level quest: the game's grey-ish !")
	check(remy and remy.look == "level" and remy.Icon.desaturated and remy.Icon.width == 18, "later ones: a smaller grey !")
	remy._scripts.OnEnter(remy)
	check(plain(TOOLTIP.lines[1]) == "  [9] Princess Must Die · Needs level 7" and TOOLTIP.lines[2] == "Click: show Princess Must Die"
		and TOOLTIP.lines[3] == "Right-click or Shift-click: map pin", "a pin's tooltip says what it is (no legend), what a click does, got " .. plain(TOOLTIP.lines[1]))
	remy._scripts.OnLeave(remy)
	roberts._scripts.OnEnter(roberts)
	check(plain(TOOLTIP.lines[1]) == "  [2] Speak with Willem · low level", "a low level one's")
	roberts._scripts.OnLeave(roberts)
	view.filters.allLevels:Click()
	check(not filters.allLevels and m.shown == 5, "off again")
	local dughan, poster, willem, wolf = marker("Marshal Dughan"), marker("Wanted Poster"), marker("Deputy Willem"), marker("drops here (12%)")
	check(poster and poster.look == "daily" and poster.Icon.atlas == "QuestDaily" and poster.Back:IsShown() and poster.Icon.width == 24,
		"a repeatable quest's giver: the blue !, full size, on a dark disc")
	check(dughan and dughan.look == "daily" and #dughan.quests == 2 and dughan.quests[1] == 104 and dughan.quests[2] == 101
		and not dughan.Badge:IsShown(), "a giver: the quest to do first first, the done one there too; one to do: no count")
	check(willem and willem.look == "progress" and willem.Icon.atlas == "QuestTurnin" and willem.Icon.desaturated == true
		and willem.Badge:IsShown() and willem.Badge:GetText() == "2" and willem.BadgeBack:IsShown(),
		"a turn-in of a quest still in progress: a grey ?, and a count: two quests to do there")
	check(wolf and wolf.look == "drop" and wolf.Icon.path == "Interface\\CharacterFrame\\TempPortraitAlphaMask" and not wolf.Badge:IsShown(),
		"where an item drops: a soft circle")
	check(not view.zp.Legend, "no legend under the map")
	-- My arrow: where I am, the way I face, moved while I'm on this map (else nothing runs).
	FACING = 1.5
	Wait(0.2)
	check(m.You:IsShown() and m.Top:IsShown() and m.You.rotation == 1.5 and m.You.points[1][4] == 0.5 * m.artW,
		"my arrow on the map, turned the way I face, got " .. tostring(m.You.rotation))
	STATE.inInstance = true
	Wait(0.2)
	check(not m.You:IsShown() and not m.Top:IsShown(), "off the map (or the game won't say): gone, and its frame hidden (nothing runs)")
	STATE.inInstance = false
	Fire("ZONE_CHANGED_NEW_AREA")
	Wait(1.1)
	check(m.You:IsShown() and m.Top:IsShown(), "back in the zone: there again (looked at after a zone change)")
	FACING = 0
	-- Threads: each chain's colour, giver -> turn-in -> the next giver; only for the chain hovered or picked.
	local lines = 0
	for i = 1, m.linesShown do
		if m.lines[i].key == CHAIN1 then lines = lines + 1 end
	end
	check(lines == 2 and m.linesShown == 2 and not m.lines[1]:IsShown() and not m.lines[2]:IsShown(),
		"the chain's thread: from Dughan to Willem (two quests), not shown while nothing of it is picked, got " .. m.linesShown)
	dughan._scripts.OnEnter(dughan)
	check(TOOLTIP.title == "Marshal Dughan" and plain(TOOLTIP.lines[1]) == "  [4] Brotherhood of Thieves · repeatable"
		and plain(TOOLTIP.lines[2]) == "  [1] A Threat Within · Completed" and TOOLTIP.lines[3] == "Click: choose one of its 2 quests"
		and TOOLTIP.lines[4] == "Right-click or Shift-click: map pin", "its tooltip: the giver and each quest, what it is, got " .. plain(TOOLTIP.lines[1]))
	check(m.lines[1]:IsShown() and m.lines[1].thickness == 3.5 and wolf:GetAlpha() == 0.3 and dughan:GetAlpha() == 1,
		"hovering a pin: its chain lit on the map (its thread, its pins), the others dim")
	dughan._scripts.OnLeave(dughan)
	check(not m.lines[1]:IsShown() and wolf:GetAlpha() == 1, "left: as before")
	-- A pin with several quests: a list of ours beside it to pick one.
	dughan:Click()
	local list = m.chooser
	check(list and list:IsShown() and st.picked == nil and list.rows[1].kind == "title" and plain(list.rows[1].Text:GetText()) == "Marshal Dughan"
		and list.rows[2].value == 104 and list.rows[3].value == 101 and not list.rows[4]
		and strtrim(plain(list.rows[2].Text:GetText())) == "[4] Brotherhood of Thieves · repeatable" and list:GetParent() == view.zp,
		"a click on a pin with two quests: a list of them beside it (on the page, not clipped by the map), nothing picked yet")
	dughan:Click()
	check(not list:IsShown(), "the pin clicked again: closed")
	dughan:Click()
	list.rows[2]:Click()
	check(st.picked == 104 and not list:IsShown() and dughan.Ring:IsShown() and plain(view.d.Title:GetText()) == "[4] Brotherhood of Thieves"
		and view.d.Panel:IsShown() and not view.b.Scroll:IsShown(), "a quest of the list clicked: picked, its pin ringed, its details on the right")
	-- The quest picked on the map: its objectives' areas in its chain's colour, its turn-in, the way between.
	local color = m.lines[1].color
	check(m.lines[1]:IsShown() and m.lines[2]:IsShown(), "its chain picked: its thread shows")
	local done = m.lines[1].done and m.lines[1] or m.lines[2]
	local open = m.lines[1].done and m.lines[2] or m.lines[1]
	check(math.abs(done.color[4] - 0.25 * 0.6) < 1e-9 and math.abs(open.color[4] - 0.7 * 0.6) < 1e-9 and open.thickness == 2,
		"a done step's thread fainter; both fainter while the quest's own way shows, got " .. done.color[4] .. ", " .. open.color[4])
	local a = m.areas[1]
	check(m.areasShown == 1 and a.spec.objective == 1 and a.spec.label == "Use Wanted Poster" and a.Fill:IsShown() and a.Glow.blend == "ADD"
		and a.Fill.vertex[1] == color[1] and a.Fill.vertex[2] == color[2] and a.Fill.vertex[4] == 0.22 and a.Button._kind == "Button",
		"its objective's area: a soft circle in its chain's colour, a button at its middle")
	local finish = m.ends[2]
	check(finish and finish:IsShown() and finish.spec.label == "Deputy Willem" and finish.Icon.atlas == "QuestTurnin" and finish.Icon.desaturated == true
		and not (m.ends[1] and m.ends[1]:IsShown()), "its turn-in, where no pin of it is (a grey ?: not done yet); its giver has its own pin")
	check(m.routeShown >= 3 and m.route[1].color[1] == color[1] and math.abs(m.route[1].from[1] - 0.42 * m.artW) < 0.01
		and math.abs(m.route[1].from[2] + 0.66 * m.artH) < 0.01, "the way from its giver to the objective to its turn-in, dashed, in its colour, got " .. m.routeShown)
	a.Button._scripts.OnEnter(a.Button)
	check(TOOLTIP.title == "Use Wanted Poster" and TOOLTIP.lines[#TOOLTIP.lines] == "Click: put a map pin there" and a.Fill.vertex[4] == 0.42,
		"an area's button: what's to do there, lit")
	a.Button._scripts.OnLeave(a.Button)
	-- Right-click or Shift-click: the game's map pin there (nothing picked).
	local pins = pinStubs()
	willem:Click("RightButton")
	STATE.shift = true
	wolf:Click()
	STATE.shift = false
	a.Button:Click()
	check(#pins == 3 and pins[1].x == 0.48 and pins[1].y == 0.42 and pins[2].x == 0.3 and pins[3].x == 0.47 and pins.tracked == true and st.picked == 104,
		"right-click, Shift-click a pin, a click on an area: the game's map pin there, tracked; the quest picked stays")
	pins.off()
	-- A pin with one quest: picked at once.
	wolf:Click()
	check(st.picked == 110 and m.areasShown == 0 and not (m.ends[2]:IsShown()), "a pin with one quest: picked at once (nothing of it to show but its pin)")
	dughan:Click()
	list.rows[2]:Click()
	check(not view.d.map.frame:IsShown(), "the details' small map: not while the zone's map is in sight")
	-- Zoom: the wheel where the cursor is, -, +, Fit; dragging.
	local px = marker("Marshal Dughan").px
	CURSOR.x, CURSOR.y = 300, -200
	local fx, fy = (300 - m.ox) / m.artW, (200 - m.oy) / m.artH
	m.frame._scripts.OnMouseWheel(m.frame, 1)
	check(m.zoom == 1.35 and math.abs(marker("Marshal Dughan").px - px * 1.35) < 0.01 and plain(m.ZoomText:GetText()) == "135%"
		and math.abs((300 - m.ox) / m.artW - fx) < 0.002 and math.abs((200 - m.oy) / m.artH - fy) < 0.002,
		"the wheel zooms in where the cursor is (that spot stays under it)")
	check(m.linesShown == 2 and math.abs(m.lines[1].from[1] - 0.42 * m.artW) < 0.01 and math.abs(m.artW - 1011 * 1.35) < 0.01
		and math.abs(m.areas[1].Fill.points[1][4] - 0.47 * m.artW) < 0.01, "the threads and areas follow, got " .. m.artW)
	m.buttons.plus:Click()
	check(math.abs(m.zoom - 1.35 * 1.35) < 1e-9, "+ zooms in further")
	m.buttons.minus:Click()
	check(math.abs(m.zoom - 1.35) < 1e-9, "- out again")
	local ox = m.ox
	CURSOR.x, CURSOR.y = 500, 500
	m.frame._scripts.OnDragStart(m.frame)
	CURSOR.x = 450
	m.frame:GetScript("OnUpdate")(m.frame, 0.01)
	m.frame._scripts.OnDragStop(m.frame)
	check(m.ox == ox - 50 and m.frame:GetScript("OnUpdate") == nil, "dragging moves it (an OnUpdate only while it's held)")
	m.buttons.fit:Click()
	check(m.zoom == 1 and plain(m.ZoomText:GetText()) == "", "Fit: the whole zone")
	-- Ready to turn in: the ? turns yellow (QUEST_LOG_UPDATE, looked at a second later).
	unpick()
	QUESTS = { { id = 103, title = "Investigate Echo Ridge", objectives = {}, complete = true } }
	Fire("QUEST_LOG_UPDATE")
	Fire("QUEST_LOG_UPDATE")
	check(marker("Deputy Willem").look == "progress", "not in the event")
	Wait(1.1)
	check(marker("Deputy Willem").look == "ready" and not marker("Deputy Willem").Icon.desaturated, "a moment later: ready to turn in, a yellow ?")
	check(plain(view.zp.Counts:GetText()) == "1 ready to turn in · 2 available" and view.zp.Hint:IsShown()
		and plain(view.zp.Hint:GetText()) == "Wheel: zoom · drag: move · right-click a pin: map pin",
		"and under the map, how the map works at its right, got " .. plain(view.zp.Counts:GetText()))
	check(briefRows() == "103" and heads(view.b.heads) == "Turn in now (1) | Quest chains"
		and plain(view.b.rows[1].Sub:GetText()) == "Turn in at Deputy Willem" and view.b.rows[1].Icon.atlas == "QuestTurnin",
		"the briefing too: turn in now, at whom, got " .. heads(view.b.heads))
	QUESTS = {}
	Fire("QUEST_LOG_UPDATE")
	Wait(1.1)
	check(marker("Deputy Willem").look == "progress" and heads(view.b.heads) == "In progress here (1) | Quest chains", "and back")
end

section("Questtree: the big window, the zone's briefing")
do
	local b = view.b
	check(b.Scroll:IsShown() and not view.d.Panel:IsShown() and plain(b.Title:GetText()) == "Elwynn Forest"
		and plain(b.Sub:GetText()) == "Level 1-10 · Eastern Kingdoms" and plain(b.Count:GetText()) == "2 of 10 done" and b.BarBack:IsShown()
		and math.abs(b.Bar.width - b.BarBack.width * 2 / 10) < 0.01,
		"nothing picked: the zone's briefing on the right: its name, levels, continent, how far along with a bar")
	check(plain(b.Line:GetText()) == "6 for your level · 2 to pick up now", "what's for my level here, what I can take now, got " .. plain(b.Line:GetText()))
	check(briefRows() == "103" and plain(b.rows[1].Text:GetText()) == "[3] Investigate Echo Ridge" and plain(b.rows[1].Sub:GetText()) == "In your quest log"
		and b.rows[1].Icon.atlas == "SideInProgressquesticon", "in progress here: my quest of this zone, a line under it")
	check(cardsOutline() == CHAIN1 .. " " .. SINGLES, "then the zone's chains as cards, then the quests without a chain, got " .. cardsOutline())
	local c = chainCard(CHAIN1)
	check(c._kind == "Button" and c.Title:GetText() == "Elwynn's Kobolds" and c.Count:GetText() == "2/9" and math.abs(c.Bar.width - 56 * 2 / 9) < 0.01
		and c:GetWidth() == 400 - 24 - 4, "a chain's card: its name (Q.ChainStep), how far along, a bar; as wide as the pane")
	check(plain(c.Next:GetText()) == "In your log: Investigate Echo Ridge" and c.Next:GetText():find("|cff888888", 1, true) and not c.Strip and not c.Meta
		and c:GetHeight() == 48, "what's next in grey, two lines (48 px), no strip, no third line")
	check(c.Dots[1]:IsShown() and not c.Dots[2]:IsShown() and c.Dots[1].vertex[4] == 1,
		"friends: a dot only for those who've done some of it")
	local s = chainCard(SINGLES)
	check(s.Title:GetText() == "Quests without a chain" and plain(s.Next:GetText()) == "1 to pick up now" and s.Count:GetText() == "0/2",
		"the quests without a chain, got " .. plain(s.Next:GetText()))
	check(plain(view.zp.Counts:GetText()) == "1 in progress · 2 available" and not view.zp.Guide:IsShown(),
		"under the map one line: in progress, available within my levels (nothing ready, nothing of the rest), got " .. plain(view.zp.Counts:GetText()))
	-- Hovering a card: its pins and thread lit, the rest dim.
	local m = view.zp.map
	c._scripts.OnEnter(c)
	local lit, dim = marker("Marshal Dughan"), marker("drops here (12%)")
	local thread
	for i = 1, m.linesShown do if m.lines[i].key == CHAIN1 then thread = m.lines[i] end end
	check(lit:GetAlpha() == 1 and dim:GetAlpha() == 0.3 and thread.thickness == 3.5 and thread.color[4] == 1,
		"hovering a chain's card: its pins and thread light up, the others dim")
	check(TOOLTIP.title == "Elwynn's Kobolds" and TOOLTIP.lines[#TOOLTIP.lines] == "Click: open the chain", "its tooltip")
	local tip = table.concat(TOOLTIP.lines, "|")
	check(tip:find("2 of 9 steps done", 1, true) and tip:find("Anna Brook", 1, true) and tip:find("Bob", 1, true) and tip:find("Level 1-10", 1, true)
		and tip:find("Doing it opens 4 more of the chain", 1, true) and tip:find("1 steps elsewhere", 1, true),
		"how far along, its levels, what the next step opens, steps elsewhere, friends (all of them), got " .. tip)
	c._scripts.OnLeave(c)
	check(dim:GetAlpha() == 1 and not thread:IsShown(), "left: all as before")
	-- Hovering a pin: its chains' cards lit.
	dim._scripts.OnEnter(dim)
	check(chainCard(SINGLES).Glow:IsShown() and chainCard(SINGLES):GetAlpha() == 1 and chainCard(CHAIN1):GetAlpha() == 0.4,
		"hovering a pin: its chain's card lights up, the others dim")
	dim._scripts.OnLeave(dim)
	check(chainCard(CHAIN1):GetAlpha() == 1 and not chainCard(SINGLES).Glow:IsShown(), "left: as before")
	-- A row clicked: picked (the map stays), the way back to the briefing.
	b.rows[1]:Click()
	check(st.picked == 103 and view.zp:IsShown() and view.d.Panel:IsShown() and plain(view.d.Back.Text:GetText()) == "Elwynn Forest"
		and view.d.Back._kind == "Button", "a quest of the briefing clicked: picked on the map, its details with the way back on top")
	view.d.Back:Click()
	check(st.picked == nil and b.Scroll:IsShown() and not view.d.Panel:IsShown() and view.zp.map.areasShown == 0, "back: the briefing, nothing on the map")
	-- Nothing to take in Westfall: a zone that has some.
	local elwynnColor = chainCard(CHAIN1).Dot.vertex
	zoneRow("z:1436"):Click()
	check(st.where == "z:1436" and cardsOutline() == "z:1436:101 z:1436:301" and plain(b.Title:GetText()) == "Westfall", "Westfall: its briefing, its chains, got " .. cardsOutline())
	check(view.zp.Guide:IsShown() and plain(view.zp.Guide:GetText()) == "Nothing for you to pick up here right now." and not view.zp.Hint:IsShown()
		and view.zp.Suggest:IsShown() and plain(view.zp.Suggest.Text:GetText()) == "Redridge Mountains has 1 for your level  >",
		"nothing to take here: says so, and where there is (my level, give or take 3), on the line under the map")
	local westfallColor = chainCard("z:1436:101").Dot.vertex
	check(westfallColor[1] == elwynnColor[1] and westfallColor[2] == elwynnColor[2] and westfallColor[3] == elwynnColor[3],
		"a chain has its colour in every zone (its first quest's ID)")
	local before = calls.Available
	view.zones:Lay()
	view.zp.Suggest:Click()
	check(st.where == "z:1433" and plain(b.Title:GetText()) == "Redridge Mountains" and zoneRow("z:1433").Picked:IsShown(),
		"a click: that zone")
	zoneRow("z:1436"):Click()
	check(calls.Available == before, "the zone to go to is kept (worked out again after a status change)")
	-- A dungeon: no map; its Zone tab is its quest list, its briefing on the right.
	zoneRow("d:The Deadmines"):Click()
	check(not view.zp:IsShown() and view.list.scroll:IsShown() and view.head:IsShown() and view.head.Title:GetText() == "The Deadmines"
		and view.Legend:IsShown() and plain(view.Legend:GetText()):find("Dungeon quests", 1, true) and listOutline() == "#Coming up 301"
		and cardsOutline() == "d:The Deadmines:301" and plain(b.Sub:GetText()) == "Level 17-24 · Dungeon",
		"a dungeon: its quest list (no map), says why, its chain in its briefing, got " .. listOutline())
	zoneRow("z:1429"):Click()
	check(view.zp.map.frame:IsShown() and view.zp:IsShown() and not view.head:IsShown(), "back in Elwynn")
end

section("Questtree: the big window, a chain opened")
do
	openChain(CHAIN1)
	check(st.chain == CHAIN1 and view.g.frame:IsShown() and not view.zp:IsShown() and view.tabs.zone.Line:IsShown(), "a click on its card: the chain's page")
	local h = view.head
	check(h.Back:IsShown() and plain(h.Back.Text:GetText()) == "Elwynn Forest" and h.Title:GetText() == "Elwynn's Kobolds" and h.Dot:IsShown()
		and plain(h.Count:GetText()) == "2 of 9 steps done" and plain(h.Sub:GetText()) == "In your log: Investigate Echo Ridge",
		"its head: back to the zone, its colour, name, how far along, what's next")
	check(graphOutline() == "101@0 107@0 102@1 104@2 103@2 106@3 105@3 108@4 201@4*",
		"a row per stage, side by side where it forks, ordered by where what leads to them is; another zone's step a stub, got " .. graphOutline())
	local a, b, c, d = item(101), item(102), item(103), item(104)
	check(b.y == a.y + 82 and c.y == d.y and c.x == d.x + 170 + 14 + 22 + 14 and view.g.w == 1012,
		"82 apart in stages, 14 between cards (a line's slot between), the middle's width, got " .. (c.x - d.x))
	-- The right pane: the chain's briefing (its steps).
	local br = view.b
	check(br.Scroll:IsShown() and br.Dot:IsShown() and plain(br.Title:GetText()) == "Elwynn's Kobolds" and br.Title._points[1][2] == 16
		and plain(br.Sub:GetText()) == "Level 1-10 · 9 quests · 1 steps elsewhere" and plain(br.Count:GetText()) == "2 of 9 steps done"
		and plain(br.Line:GetText()) == "In your log: Investigate Echo Ridge" and heads(br.heads) == "Steps | Friends",
		"nothing picked: the chain's briefing on the right: its colour, name, levels, how far along, what's next, got " .. plain(br.Sub:GetText()))
	check(briefRows() == "101 102 107 103 104 105 106 108 201" and plain(br.rows[1].Text:GetText()) == "1. [1] A Threat Within"
		and plain(br.rows[1].Right:GetText()) == "Completed" and br.rows[1].Icon.atlas == "common-icon-checkmark"
		and plain(br.rows[5].Right:GetText()) == "Marshal Dughan" and plain(br.rows[6].Right:GetText()) == "Needs Investigate Echo Ridge",
		"its steps, each a row: done ones ticked, the giver for one I can take, else the reason, got " .. briefRows())
	check(plain(br.Friends:GetText()) == "Anna Brook  1 of 9\nBob  0 of 9", "friends on it, got " .. plain(br.Friends:GetText()))
	br.rows[6]:Click()
	check(st.picked == 105 and st.chain == CHAIN1 and view.g.frame:IsShown() and plain(view.d.Back.Text:GetText()) == "Elwynn's Kobolds",
		"a step clicked: picked on the chain's page, the way back says the chain")
	view.d.Back:Click()
	check(st.picked == nil and br.Scroll:IsShown() and st.chain == CHAIN1, "back: the chain's briefing")
	-- No line runs through a card; lines that aren't joined never share a stretch.
	local through, joined = 0, 0
	for _, s in ipairs(lay().segs) do
		for _, it in ipairs(lay().cards) do
			if s.maxX > it.x + 1 and s.minX < it.x + 170 - 1 and s.maxY > it.y + 1 and s.minY < it.y + 48 - 1 then
				through = through + 1
			end
		end
		for _, t in ipairs(lay().segs) do
			local across = s.y1 == s.y2 and t.y1 == t.y2 and math.abs(s.y1 - t.y1) < 0.5 and s.maxX > t.minX + 1 and t.maxX > s.minX + 1
			local down = s.x1 == s.x2 and t.x1 == t.x2 and math.abs(s.x1 - t.x1) < 3 and s.maxY > t.minY - 1 and t.maxY > s.minY - 1
			if s ~= t and (across or down) and s.to ~= t.to and s.from ~= t.from then
				joined = joined + 1
			end
		end
	end
	check(#lay().segs > 10 and through == 0 and joined == 0, "no line through a card, none looking joined, got " .. through .. ", " .. joined)
	local green, amber, grey = segsOf(101, 102)[1], segsOf(102, 103)[1], segsOf(105, 201)[1]
	check(green and green.tone == 2 and amber and amber.tone == 1 and grey and grey.tone == 0,
		"lines: green between done ones, amber from a done one, grey otherwise")
	local dashed = segsOf(107, 103)
	check(#dashed > 3 and dashed[1].dashed and dashed[1].faint and not amber.dashed, "a lead-in that isn't needed first: dashed and dim")
	local kinds = {}
	for _, p in ipairs(lay().pills) do kinds[#kinds + 1] = p.quest .. ":" .. p.kind end
	check(table.concat(kinds, " ") == "106:any", "where any one of several is enough: one of (where each is needed, no label), got " .. table.concat(kinds, " "))
	local pills = {}
	for _, f in ipairs(view.g.pills) do if f:IsShown() then pills[#pills + 1] = plain(f.Text:GetText()) end end
	check(table.concat(pills, ",") == "one of", "drawn, got " .. table.concat(pills, ","))
	check(view.Legend:IsShown() and plain(view.Legend:GetText()) == "dashed: lead-in · one of: any one is enough · orange: the way to a locked quest",
		"under it one short line on its lines")
	local p106 = lay().pills[1]
	check(p106.x == (item(106).inX or item(106).cx) and p106.y == item(106).y - 7, "just above the quest, where the lines meet")
	-- The cards.
	local done, active, avail, lead, stub = card(101), card(103), card(104), card(107), card(201)
	check(plain(done.Title:GetText()) == "[1] A Threat Within" and plain(done.Info:GetText()) == "Marshal Dughan" and done.Check:IsShown()
		and done.Strip.color[2] == 0.73 and done.Bg.vertex[4] == 0.3, "a done card: [level] and title, the giver only, a check, the green strip and tone")
	check(done.Title:GetText():find("|cff336699[1]|r", 1, true), "the level in its difficulty colour (Q.LevelColor)")
	check(done.Icon.atlas == "QuestNormal" and done.Icon.desaturated == true and avail.Icon.atlas == "QuestDaily" and avail.Icon.desaturated == false
		and lead.Icon.atlas == "TrivialQuests", "the start: the giver's ! (a repeatable one's blue, a low one's), bright only when I can take it")
	check(active.Icon.atlas == "SideInProgressquesticon", "in my log: in progress")
	check(not card(105).Check:IsShown() and card(105).Bg.vertex[1] == 0.1 and card(105).Edges[1].color[1] == 0.4, "locked: grey")
	check(not avail.Friends and not avail.Tag and lead:GetAlpha() == 0.8,
		"no friends, \"closes\" or \"lead-in\" on the cards (in the tooltip; a lead-in's line is dashed, its card a bit dimmer)")
	check(item(107) and graphOutline():find("107@0", 1, true), "every level of the chain (a low level step too)")
	check(stub and item(201).stub and stub.Title:GetText() == "Westfall" and plain(stub.Info:GetText()) == "[10] The People's Militia"
		and stub.Icon.path == "Interface\\Icons\\INV_Misc_Map_01", "a step in another zone: a stub with the zone's name")
	-- The next step pulses once.
	check(active.Pulse.Anim.plays == 1 and st.pulse == nil, "the next step pulses once when the chain opens")
	view.g.frame._scripts.OnMouseWheel(view.g.frame, -1)
	view.g.frame._scripts.OnMouseWheel(view.g.frame, 1)
	check(active.Pulse.Anim.plays == 1, "and only once")
	-- Tooltips.
	active._scripts.OnEnter(active)
	check(TOOLTIP.shown and TOOLTIP.title == "Investigate Echo Ridge" and TOOLTIP.lines[1] == "In your quest log"
		and TOOLTIP.lines[#TOOLTIP.lines] == "Click: details", "hovering: a tooltip")
	local tip = table.concat(TOOLTIP.lines, "|")
	check(tip:find("Step 4 of 9 · Elwynn's Kobolds", 1, true) and tip:find("Then: Skirmish at Echo Ridge", 1, true), "with its step and what's next")
	active._scripts.OnLeave(active)
	check(not TOOLTIP.shown, "gone when the mouse leaves")
	lead._scripts.OnEnter(lead)
	check(table.concat(TOOLTIP.lines, "|"):find("A lead-in: not needed", 1, true), "a lead-in's tooltip says so")
	avail._scripts.OnEnter(avail)
	check(table.concat(TOOLTIP.lines, "|"):find("Taking it closes: Report to Goldshire", 1, true), "what taking it closes")
	stub._scripts.OnEnter(stub)
	check(TOOLTIP.title == "Westfall" and plain(TOOLTIP.lines[1]) == "In another zone: [10] The People's Militia"
		and TOOLTIP.lines[#TOOLTIP.lines] == "Click: go there", "a stub's tooltip")
	stub._scripts.OnLeave(stub)
	-- Without Q.ChainStep and Q.LevelColor: the chain's first title, the level against mine (19).
	Q.ChainStep, Q.LevelColor = nil, nil
	wipe(st.layouts)
	view.g.bucket = nil
	Q.ToggleBrowser(); Q.ToggleBrowser()
	check(st.chain == CHAIN1 and view.head.Title:GetText() == "A Threat Within" and card(101).Title:GetText():find("|cff808080[1]|r", 1, true),
		"without them: the first quest's title, level 1 grey (trivial at 19); opened again: still the chain")
	Q.ChainStep, Q.LevelColor = stand.ChainStep, stand.LevelColor
	Q.ToggleBrowser(); Q.ToggleBrowser()
end

section("Questtree: the big window, why it's locked")
do
	card(108):Click()
	local path = st.path
	check(st.picked == 108 and path and path.order[103] == 1 and path.order[105] == 2 and path.elsewhere == 0,
		"a locked quest picked: the way back to it (Q.Missing)")
	check(card(103).Order:IsShown() and card(103).Order:GetText() == "1" and card(105).Order:GetText() == "2" and not card(104).Order:IsShown()
		and card(103).Edges[1].color[1] == 1 and card(103).Edges[1].color[2] == 0.5, "its steps numbered (1: do it first), lit")
	check(card(101):GetAlpha() == 0.4 and card(103):GetAlpha() == 1 and card(108):GetAlpha() == 1 and card(108).Glow:IsShown(), "the rest dim")
	local litLines, dimLines = 0, 0
	for i = 1, view.g.linesShown do
		local line = view.g.lines[i]
		if line.color[1] == 1 and line.color[2] == 0.5 then litLines = litLines + 1 elseif line.color[4] < 0.5 then dimLines = dimLines + 1 end
	end
	check(litLines > 0 and dimLines > 0, "its lines lit, the others dim")
	check(plain(view.head.Sub:GetText()) == "To take it, do 2 quests first", "the head says how many, got " .. plain(view.head.Sub:GetText()))
	card(104):Click()
	check(st.path == nil and card(101):GetAlpha() == 1 and not card(103).Order:IsShown()
		and plain(view.head.Sub:GetText()) == "In your log: Investigate Echo Ridge", "another quest: back as it was")
	-- Across zones: a stub clicked goes there, the way back lights the stub.
	card(201):Click()
	check(st.where == "z:1436" and st.chain == "z:1436:101" and st.picked == 201 and zoneRow("z:1436").Picked:IsShown(),
		"a stub clicked: that zone, the chain there, that quest picked")
	check(graphOutline() == "105@0* 201@1", "in Westfall the chain's own step, the one before it a stub, got " .. graphOutline())
	check(st.path and st.path.elsewhere == 2 and card(105).Order:GetText() == "2" and card(105):GetAlpha() == 1
		and plain(view.head.Sub:GetText()) == "To take it, do 2 quests first, 2 of them in other zones",
		"locked: the way back across zones (the stub lights up), got " .. plain(view.head.Sub:GetText()))
	view.head.Back:Click()
	check(st.chain == nil and view.zp:IsShown() and st.path == nil and view.zp.map.map == WESTFALL and st.picked == 201,
		"back: the zone's page, the quest still picked")
	zoneRow("z:1429"):Click()
end

section("Questtree: the big window, the filters")
do
	openChain(CHAIN1)
	check(view.filters.allLevels._kind == "Button" and not view.filters.allLevels.Tick.shown and plain(view.filters.allLevels.Text:GetText()) == "All levels"
		and view.filters.showOther._kind == "Button" and not view.filters.showOther.Tick.shown, "two filters: buttons of ours, off")
	check(filters.hideDone == nil and filters.onlyAvailable == nil and not view.filters.hideDone and not view.filters.onlyAvailable,
		"\"Hide done\" and \"Only available now\" are gone (their saved keys ignored)")
	local before = graphOutline()
	view.filters.allLevels:Click()
	check(filters.allLevels and graphOutline() == before, "an opened chain shows every level anyway")
	view.filters.allLevels:Click()
	view.head.Back:Click()
	view.filters.showOther:Click()
	openChain(SINGLES)
	check(graphOutline() == "110 112 111" and card(112):GetAlpha() == 0.55, "not for me: shown, dimmed, got " .. graphOutline())
	view.filters.showOther:Click()
	check(graphOutline() == "110 111", "off: not shown, the quests without a chain every level too, got " .. graphOutline())
	view.head.Back:Click()
	-- A step not for me between two shown: the line passes through, fainter; a skipped one stays.
	STATUS_OF[102], WHY[102] = "other", "class"
	Q.ToggleBrowser(); Q.ToggleBrowser()
	openChain(CHAIN1)
	local faint = 0
	for _, s in ipairs(lay().segs) do faint = faint + ((s.faint and not s.dashed) and 1 or 0) end
	check(not item(102) and graphOutline():find("101@0", 1, true) and graphOutline():find("103@1", 1, true) and faint > 0,
		"a step not for me: hidden, its line passes through, fainter, got " .. graphOutline())
	WHY[102] = { "closed", 107 }
	Q.ToggleBrowser(); Q.ToggleBrowser()
	check(item(102) and card(102):GetAlpha() <= 0.55, "one I skipped (closed by another I took): it stays, dimmed")
	card(102)._scripts.OnEnter(card(102))
	check(TOOLTIP.lines[1] == "Skipped" and TOOLTIP.lines[2] == "You took Speak with Willem instead", "its tooltip says why, got " .. tostring(TOOLTIP.lines[2]))
	card(102)._scripts.OnLeave(card(102))
	STATUS_OF[102], WHY[102] = "done", nil
	Q.ToggleBrowser(); Q.ToggleBrowser()
	check(not filters.allLevels and not filters.showOther, "all off again")
	view.head.Back:Click()
	-- The zone page: a chain with nothing within my levels left out (a line says so), the done ones folded.
	FAR[201], STATUS_OF[301], STATUS_OF[202] = true, "done", "done"
	zoneRow("z:1436"):Click()
	Q.ToggleBrowser(); Q.ToggleBrowser()
	check(cardsOutline() == "z:1436:done z:1436:more", "Westfall: its chain out of my levels left out, its done chain folded, got " .. cardsOutline())
	local fold, more = chainCard("z:1436:done"), chainCard("z:1436:more")
	check(plain(fold.Line:GetText()) == "Completed (1)" and fold.Toggle:IsShown() and fold.Toggle.path:find("Plus", 1, true) and not fold.Title:IsShown(),
		"the fold: Completed (1)")
	check(plain(more.Line:GetText()) == "1 more outside your levels · Show all levels" and not more.Bg:IsShown(), "a quiet line: how many more")
	fold:Click()
	check(cardsOutline() == "z:1436:done z:1436:301 z:1436:more" and chainCard("z:1436:301").Check:IsShown(), "the fold opened: the done chain")
	chainCard("z:1436:more"):Click()
	check(filters.allLevels and view.filters.allLevels.Tick.shown and cardsOutline() == "z:1436:101 z:1436:done z:1436:301",
		"a click on the line: all levels, got " .. cardsOutline())
	view.filters.allLevels:Click()
	FAR[201], STATUS_OF[301], STATUS_OF[202] = nil, "level", "locked"
	st.folded["z:1436:done"] = nil
	Q.ToggleBrowser(); Q.ToggleBrowser()
	-- Everything hidden: says so.
	zoneRow("z:1411"):Click()
	check(view.b.Empty:IsShown() and plain(view.b.Empty:GetText()) == "Nothing to show with these filters.", "Durotar: nothing for me shows")
	zoneRow("z:1429"):Click()
end

section("Questtree: the big window, the details")
do
	local d = view.d
	st.picked = nil
	openChain(CHAIN1)
	Q.ToggleBrowser(); Q.ToggleBrowser()
	card(105):Click()
	check(st.picked == 105 and card(105).Glow:IsShown() and card(105).Edges[1].color[2] == 0.82 and not card(104).Glow:IsShown(),
		"a click: its card marked")
	check(d.Panel:IsShown() and not view.b.Scroll:IsShown() and plain(d.Back.Text:GetText()) == "Elwynn's Kobolds", "its details, the way back to the chain's briefing")
	local sub = plain(d.Sub:GetText())
	check(plain(d.Title:GetText()) == "[5] Skirmish at Echo Ridge" and d.Title:GetText():find("|cff336699", 1, true) and d.Title._points[1][2] == 40
		and sub == "Needs Investigate Echo Ridge" and d.Icon.atlas == "QuestNormal" and d.Icon.desaturated == true,
		"its icon, the title in its level's colour beside it, one status line with the reason, got " .. sub)
	check(detailHeads() == "Step 6 of 9 · Elwynn's Kobolds | Quest giver and turn-in | Needs first: | Leads to:",
		"its sections (only what it has), got " .. detailHeads())
	local steps = {}
	for _, b in ipairs(d.steps) do if b:IsShown() then steps[#steps + 1] = b.quest end end
	check(table.concat(steps, " ") == "104 105 106 108" and plain(d.StepsBefore:GetText()) == "... 4 before" and plain(d.StepsMore:GetText()) == "... and 1 more"
		and plain(d.steps[2].Text:GetText()) == "6. [5] Skirmish at Echo Ridge" and d.steps[2].Picked:IsShown() and not d.steps[1].Picked:IsShown()
		and d.steps[2].Icon.path == "Interface\\ChatFrame\\ChatFrameExpandArrow" and d.steps[2]._kind == "Button",
		"the steps around it: one before, this one marked, two after, how many more, got " .. table.concat(steps, " "))
	check(d.StepBack:IsShown() and math.abs(d.StepBar.width - (400 - 24 - 4) * 2 / 9) < 0.01 and d.ChainBtn:IsShown() and d.ChainBtn._kind == "Button",
		"how far along the chain (a bar), and a button that opens it")
	check(d.NeedsHead:IsShown() and d.links[1]:IsShown() and d.links[1].quest == 103
		and plain(d.links[1].Text:GetText()) == "[3] Investigate Echo Ridge" and not d.NeedsMore:IsShown(), "Needs first: a button to the quest")
	check(d.LeadsHead:IsShown() and d.links[2].quest == 201 and plain(d.links[2].Text:GetText()) == "[10] The People's Militia · Westfall",
		"Leads to: the next one, its zone named")
	check(plain(d.places[1].Text:GetText()) == "Deputy Willem · Elwynn Forest" and d.places[1].Icon.atlas == "QuestNormal" and not d.places[2]:IsShown()
		and d.map.frame:IsShown(), "its giver: one line (no turn-in known: none); the small map (the zone's map isn't in sight)")
	check(not d.ObjHead:IsShown() and not d.RewardHead:IsShown(), "no objectives or rewards known: no such sections")
	check(#shownInSmall == 0, "the small window closed: it isn't asked")
	card(108):Click()
	check(d.links[1].quest == 103 and d.links[2].quest ~= 105 and d.NeedsMore:IsShown()
		and plain(d.NeedsMore:GetText()) == "... and 1 more", "Needs first: only the first step, and how many more")
	local opens = QUESTS_DATA[101].opens
	QUESTS_DATA[101].opens = { 102, 103, 104, 105, 106 }
	card(101):Click()
	check(d.links[3].quest == 104 and not (d.links[4] and d.links[4]:IsShown()) and plain(d.LeadsMore:GetText()) == "... and 2 more",
		"Leads to: at most three")
	QUESTS_DATA[101].opens = opens
	card(105):Click()
	d.links[1]:Click()
	check(st.picked == 103 and st.where == "z:1429" and st.chain == CHAIN1 and plain(d.Title:GetText()) == "[3] Investigate Echo Ridge" and card(103).Glow:IsShown(),
		"a link to a quest of the chain shown: picked there")
	check(not d.places[1]:IsShown() and plain(d.places[2].Text:GetText()) == "Deputy Willem · Elwynn Forest" and d.places[2].Icon.atlas == "QuestTurnin"
		and d.places[2].Icon.desaturated == true, "in my log: where it's turned in (a grey ?: not done yet)")
	-- Its objectives (Q.Objectives): what to do, where it drops; on the small map its areas, lit from its line.
	local o1, o2 = d.objectives[1], d.objectives[2]
	check(o1:IsShown() and o2:IsShown() and not (d.objectives[3] and d.objectives[3]:IsShown()) and plain(o1.Text:GetText()) == "Kill 10 x Kobold Vermin"
		and plain(o2.Text:GetText()) == "Collect 8 x Gold Dust\nfrom Kobold Miner, 32%" and o1.Icon.path == "Interface\\QuestFrame\\UI-Quest-BulletPoint"
		and o2:GetHeight() > o1:GetHeight() and o1._kind == "Button", "its objectives: each a line, where the item drops under it")
	local m = d.map
	local color = m.pick and m.pick.color
	check(m.frame:IsShown() and m.pick and m.pick.quest == 103 and m.areasShown == 3 and o1.Dot:IsShown() and o1.Dot.vertex[1] == color[1]
		and m.areas[1].Fill.vertex[1] == color[1], "the small map: its objectives' areas in its chain's colour, a dot on each line that has one")
	o2._scripts.OnEnter(o2)
	local tip = plain(table.concat(TOOLTIP.lines, "|"))
	check(tip == "Drops from Kobold Miner (32%) · Elwynn Forest|Drops from Old Chest (5%) · Westfall|Click: put a map pin there"
		and m.areas[3].Fill.vertex[4] == 0.42 and m.areas[1].Fill.vertex[4] == 0.07, "hovering a line: where it drops (every source) and its area lit, the others dim, got " .. tip)
	o2._scripts.OnLeave(o2)
	check(m.areas[1].Fill.vertex[4] == 0.22 and m.areas[3].Fill.vertex[4] == 0.22, "left: all as before")
	-- My progress from the quest log, ticked when done; drawn again when it changes (a moment later).
	QUESTS = { { id = 103, title = "Investigate Echo Ridge", objectives = { { text = "Kobold Vermin slain: 3/10", finished = false, type = "monster" },
		{ text = "Gold Dust: 8/8", finished = true, type = "item" } } } }
	Fire("QUEST_LOG_UPDATE")
	check(plain(o1.Text:GetText()) == "Kill 10 x Kobold Vermin", "not in the event")
	Wait(1.1)
	check(plain(o1.Text:GetText()) == "Kobold Vermin slain: 3/10" and plain(o2.Text:GetText()) == "Gold Dust: 8/8\nfrom Kobold Miner, 32%"
		and o2.Icon.atlas == "common-icon-checkmark" and o2.Text:GetText():find("|cff888888Gold Dust", 1, true) and o1.Icon.path ~= nil,
		"in my log: the quest log's lines with my progress, the done one ticked and grey")
	check(m.areas[3].spec.done and m.areas[3].Fill.vertex[4] == 0.07 and not m.areas[3].Button.Dot.shown and m.areas[3].Button.Check.shown,
		"its area faint, ticked")
	check(d.Pin:IsShown() and d.Pin.point and d.Pin.point.x == 0.4 and d.Pin.point.y == 0.5 and plain(d.Pin:GetText()) == "Map pin",
		"Map pin: to the first objective not done yet")
	local draws = st.draws
	Fire("QUEST_LOG_UPDATE")
	Wait(1.1)
	check(st.draws == draws, "nothing changed: nothing drawn again")
	QUESTS = {}

	-- The client's title, requirements, giver and turn-in and their places, the map, rewards, friends.
	QUESTS = { { id = 104, title = "Bruderschaft der Diebe", objectives = {} } }
	smallOpen = true
	card(104):Click()
	check(shownInSmall[1] == 104, "the small window open: it shows the quest too")
	check(plain(d.Title:GetText()) == "[4] Bruderschaft der Diebe" and plain(card(104).Title:GetText()) == "[4] Bruderschaft der Diebe",
		"the client's title when it knows the quest")
	check(plain(d.Req:GetText()) == "Taking it closes: Report to Goldshire" and d.ReqHead:IsShown(),
		"requirements met aren't listed; what taking it closes is, got " .. plain(d.Req:GetText()))
	check(plain(d.Sub:GetText()) == "Available · New in WoW: Forever, Repeatable", "its status, new and repeatable on that line")
	check(detailHeads() == "Step 5 of 9 · Elwynn's Kobolds | Objectives | Quest giver and turn-in | Rewards | Requirements | Friends",
		"its sections, in that order, got " .. detailHeads())
	check(plain(d.places[1].Text:GetText()) == "Marshal Dughan · Elwynn Forest" and d.places[1].Icon.atlas == "QuestNormal"
		and plain(d.places[2].Text:GetText()) == "Deputy Willem · Elwynn Forest" and d.places[2].Icon.atlas == "QuestTurnin",
		"who gives it and takes it back, where: a line each")
	d.places[1]._scripts.OnEnter(d.places[1])
	local tip1 = plain(table.concat(TOOLTIP.lines, "|"))
	check(tip1 == "Elwynn Forest  42.0, 66.0|Starts at|Wanted Poster (an object) · Elwynn Forest|Click: put a map pin there",
		"the other givers: in its tooltip, got " .. tip1)
	d.places[1]._scripts.OnLeave(d.places[1])
	check(plain(d.objectives[1].Text:GetText()) == "Use Wanted Poster" and not (d.objectives[2]:IsShown()), "an object to use")
	check(m.frame:IsShown() and m.map == ELWYNN and m.shown == 3 and m.markers[1].look == "start" and m.markers[3].look == "end" and m.areasShown == 1,
		"the small map: the zone, givers, the ender, its objective's area")
	-- Rewards (Q.Rewards): the items to choose from, the ones it gives, money, experience; the game's tooltips.
	local items = {}
	for _, b in ipairs(d.items) do if b:IsShown() then items[#items + 1] = b.item .. "x" .. (b.Count:GetText() ~= "" and b.Count:GetText() or "1") end end
	check(table.concat(items, " ") == "2075x1 1155x1 2589x5" and plain(d.ChoiceLabel:GetText()) == "Choose one of:" and plain(d.GetLabel:GetText()) == "You also get:"
		and d.items[1].Icon.path == 1000 + 2075 and d.items[1].Border:IsShown() and d.items[2].Border:IsShown() and not d.items[3].Border:IsShown()
		and d.items[1]._kind == "Button", "its rewards: the game's icons, counts, a border by quality (not for a common one), got " .. table.concat(items, " "))
	check(d.items[2]._points[1][2] == 42 and d.items[3]._points[1][3] < d.items[1]._points[1][3] and plain(d.Money:GetText()) == "1g 20s 50c · 1250 XP",
		"side by side, the second group under the first; money and experience, got " .. plain(d.Money:GetText()))
	GameTooltip.SetItemByID = function(_, id) TOOLTIP.item = id end
	d.items[2]._scripts.OnEnter(d.items[2])
	check(TOOLTIP.item == 1155 and TOOLTIP.shown and TOOLTIP.owner == d.items[2], "an item hovered: the game's item tooltip (GameTooltip:SetItemByID)")
	d.items[2]._scripts.OnLeave(d.items[2])
	GameTooltip.SetItemByID = nil
	STATE.ctrl = true
	local dressups = DRESSUPS
	d.items[1]:Click()
	STATE.ctrl = false
	check(DRESSUPS == dressups + 1, "a modified click: the game's (Ctrl: try it on)")
	-- An item the client doesn't know yet: asked for, drawn again when it came.
	local askedItems = {}
	C_Item.RequestLoadItemDataByID = function(id) askedItems[#askedItems + 1] = id end
	REWARDS[104].items[2] = { id = 9999, count = 1 }
	card(104):Click()
	check(askedItems[1] == 9999 and not d.items[4].Border:IsShown(), "an item the client doesn't know: asked for")
	ITEMS[9999] = { name = "Shiny Thing", quality = 4 }
	Fire("ITEM_DATA_LOAD_RESULT", 2589, true)
	Wait(0.5)
	check(not d.items[4].Border:IsShown(), "another item's answer: nothing")
	Fire("ITEM_DATA_LOAD_RESULT", 9999, true)
	Wait(0.5)
	check(d.items[4].Border:IsShown() and d.items[4].item == 9999, "it came: drawn again (its quality's border)")
	REWARDS[104].items[2], ITEMS[9999] = nil, nil
	C_Item.RequestLoadItemDataByID = function() end
	check(plain(d.Friends:GetText()) == "Anna Brook (Completed), Bob (In your quest log)" and d.FriendsHead:IsShown(),
		"friends, got " .. plain(d.Friends:GetText()))
	check(d.Small:IsShown() and d.Small:GetText() == "Companion" and d.Pin:IsShown() and d.Pin:IsEnabled() and d.Pin.point.x == 0.42,
		"at the bottom: Map pin (its giver: not taken yet) and Companion")
	smallOpen = false
	d.Small:Click()
	check(shownInSmall[2] == 104, "... which shows it in the small window")
	local friends = FRIENDS[104]
	FRIENDS[104] = { { name = "A", status = "done" }, { name = "B", status = "done" }, { name = "C", status = "active" }, { name = "D", status = "done" },
		{ name = "E", status = "done" } }
	card(104):Click()
	check(plain(d.Friends:GetText()) == "A (Completed), B (Completed), C (In your quest log)  +2", "at most three friends, got " .. plain(d.Friends:GetText()))
	FRIENDS[104] = friends
	-- What isn't met, with the reason: a reputation, a profession's rank, a race, a class.
	local function again() Q.ToggleBrowser(); Q.ToggleBrowser() end
	STATUS_OF[104], NEEDS[104] = "locked", { kind = "rep", faction = 72, min = 3000, have = 0 }
	again()
	check(plain(d.Sub:GetText()):find("^Needs Friendly with #72") and plain(d.Req:GetText()) == "Reputation: #72, Friendly\nTaking it closes: Report to Goldshire",
		"a reputation too low: says which, got " .. plain(d.Sub:GetText()) .. " / " .. plain(d.Req:GetText()))
	NEEDS[104] = { kind = "skill", id = 165, value = 50, have = 10 }
	again()
	check(plain(d.Sub:GetText()):find("^Needs Leatherworking 50") and plain(d.Req:GetText()):find("^Skill: Leatherworking 50"),
		"a profession's rank too low, got " .. plain(d.Sub:GetText()))
	STATUS_OF[104], NEEDS[104], WHY[104] = "other", nil, "race"
	again()
	check(plain(d.Sub:GetText()):find("^Not for your race") and plain(d.Req:GetText()) == "Races: every Alliance race",
		"not for my race: only that (a side's every race: the new ones too), got " .. plain(d.Req:GetText()))
	WHY[104] = "class"
	again()
	check(plain(d.Sub:GetText()):find("^Not for your class") and plain(d.Req:GetText()) == "Classes: Warrior", "not for my class")
	WHY[104] = "skill"
	again()
	check(plain(d.Sub:GetText()):find("^Needs Leatherworking") and plain(d.Req:GetText()) == "Skill: Leatherworking 50", "a profession I don't have")
	STATUS_OF[104], WHY[104] = "available", nil
	again()
	QUESTS = {}
	-- Lines put a map pin there (the game's own waypoint, nothing of the world map).
	local pins = pinStubs()
	card(104):Click()
	d.places[1]:Click()
	d.places[2]:Click()
	d.Pin:Click()
	d.objectives[1]:Click()
	check(#pins == 4 and pins[1].uiMapID == ELWYNN and pins[1].x == 0.42 and pins[2].x == 0.48 and pins[3].x == 0.42 and pins[4].x == 0.47
		and pins.tracked == true, "its giver's, its turn-in's and its objective's line, Map pin: a pin there, tracked")
	-- An item: its best drop, the rest in the tooltip.
	view.head.Back:Click()
	unpick()
	openChain(SINGLES)
	card(110):Click()
	check(plain(d.places[1].Text:GetText()) == "Wolf Fang (an item)\nDrops from Young Wolf (12%) · Elwynn Forest" and d.places[1].Icon.path == "Interface\\Icons\\INV_Misc_Bag_10",
		"an item: the item, what drops it most often under it, got " .. plain(d.places[1].Text:GetText()))
	d.places[1]._scripts.OnEnter(d.places[1])
	check(plain(table.concat(TOOLTIP.lines, "|")):find("Drops from Timber Wolf (0.5%) · Elwynn Forest", 1, true), "the other drops: in its tooltip")
	d.places[1]._scripts.OnLeave(d.places[1])
	check(m.frame:IsShown() and m.map == ELWYNN and m.shown == 2 and m.markers[1].look == "drop", "the small map: where it drops")
	check(plain(card(110).Info:GetText()) == "Wolf Fang" and card(110).Icon.path == "Interface\\Icons\\INV_Misc_Bag_10", "its card: the item")
	d.places[1]:Click()
	check(pins[5] and pins[5].x == 0.3, "a drop's line: a pin there")
	pins.off()
	view.head.Back:Click()
	-- From the details: the chain opened in the middle.
	Q.OpenBrowser(101)
	check(st.chain == nil and st.picked == 101 and view.zp:IsShown() and marker("Marshal Dughan").Ring:IsShown(),
		"Q.OpenBrowser(id): its zone's map, the quest picked on it")
	check(not d.Req:IsShown() and not d.ReqHead:IsShown() and d.places[1]:IsShown() and not d.Friends:IsShown()
		and not d.NeedsHead:IsShown() and d.LeadsHead:IsShown() and not d.ObjHead:IsShown() and not d.RewardHead:IsShown(), "a plain quest: only what it has")
	d.ChainBtn:Click()
	check(st.chain == CHAIN1 and view.g.frame:IsShown() and st.picked == 101 and card(101).Glow:IsShown(), "its chain's button: the chain opened, the quest in it")
	-- Without this round's Q.Objectives and Q.Rewards (Data.lua before them): the rest as it is.
	Q.Objectives, Q.Rewards = nil, nil
	card(104):Click()
	check(st.picked == 104 and not d.ObjHead:IsShown() and not d.RewardHead:IsShown() and d.places[1]:IsShown() and d.Pin.point.x == 0.42,
		"without Q.Objectives and Q.Rewards: no objectives or rewards, the rest there")
	Q.Objectives, Q.Rewards = stand.Objectives, stand.Rewards
	view.head.Back:Click()
end

section("Questtree: the big window, across zones")
do
	zoneRow("z:1436"):Click()
	check(st.where == "z:1436" and cardsOutline() == "z:1436:101 z:1436:301",
		"another zone: the chain from Elwynn too, and a quest given here that's listed with a dungeon (Q.ZoneGiven), got " .. cardsOutline())
	local c = chainCard("z:1436:101")
	c._scripts.OnEnter(c)
	check(table.concat(TOOLTIP.lines, "|"):find("8 steps elsewhere", 1, true) and c.Title:GetText() == "Elwynn's Kobolds",
		"its card's tooltip counts the steps elsewhere")
	c._scripts.OnLeave(c)
	check(plain(view.b.Count:GetText()) == "0 of 2 done", "its count: its own quests")
	openChain("z:1436:301")
	check(graphOutline() == "301@0 202@1" and plain(card(301).Info:GetText()) == "The Deadmines" and plain(card(301).Title:GetText()) == "[17] Red Silk Bandanas",
		"the dungeon's chain given here, it says where")
	card(202):Click()
	view.d.links[1]:Click()
	check(st.where == "z:1436" and st.picked == 301, "Needs first in a dungeon, given here: it stays")
	zoneRow("d:The Deadmines"):Click()
	check(st.where == "d:The Deadmines" and st.chain == nil and st.picked == nil and cardsOutline() == "d:The Deadmines:301",
		"the dungeon: its page, its briefing (a place clicked: nothing picked)")
	zoneRow("c:1414"):Click()
	check(not zoneRow("z:1411"), "Kalimdor folded")
	view.filters.showOther:Click()
	Q.OpenBrowser(401)
	check(win:IsShown() and st.where == "z:1411" and st.picked == 401 and zoneRow("z:1411") and zoneRow("z:1411").Picked:IsShown()
		and st.chain == nil and view.zp:IsShown() and view.zp.map.map == DUROTAR, "Q.OpenBrowser(id): its zone's map, its continent opened")
	check(plain(view.d.Sub:GetText()):find("Not for your race", 1, true) and plain(view.d.Sub:GetText()):find("Learned while playing", 1, true)
		and not plain(view.d.Req:GetText()):find("Faction", 1, true), "not for me: why and where it came from (its faction isn't what keeps me)")
	check(plain(view.d.Req:GetText()) == "Races: Human, High Order Skyborne", "races named by Q.Races (Forever's new ones), got "
		.. plain(view.d.Req:GetText()))
	view.filters.showOther:Click()
	Q.OpenBrowser(103)
	local m = view.zp.map
	check(st.where == "z:1429" and st.picked == 103 and view.zp:IsShown() and m.pick and m.pick.quest == 103 and m.areasShown == 3
		and marker("Deputy Willem").Ring:IsShown(), "back in Elwynn: on its map its turn-in ringed, its objectives' areas (those of this zone)")
	check(not (m.ends[1] and m.ends[1]:IsShown()) and not m.ends[2]:IsShown() and m.routeShown > 0,
		"no giver known, its turn-in has its pin: the way from its objectives to it")
	local o1 = view.d.objectives[1]
	check(o1.Dot:IsShown() and o1.Dot.vertex[1] == m.pick.color[1], "the details' objectives: a dot in the map's colour")
	o1._scripts.OnEnter(o1)
	check(m.areas[1].Fill.vertex[4] == 0.42 and m.areas[2].Fill.vertex[4] == 0.42 and m.areas[3].Fill.vertex[4] == 0.07,
		"an objective's line hovered: its areas lit on the zone's map, the others dim")
	o1._scripts.OnLeave(o1)
	check(m.areas[3].Fill.vertex[4] == 0.22, "left: as before")
end

section("Questtree: the big window, the overview")
do
	view.tabs.overview:Click()
	check(st.tab == "overview" and view.list.scroll:IsShown() and not view.g.frame:IsShown() and not view.zp:IsShown() and M.db.browser.tab == "overview",
		"the quest list's tab (kept)")
	check(listOutline() == "#In progress 103 #Available now 104 110 #Blocked 105 106 108 #Completed +2",
		"in groups within my levels, the done ones folded, how many more, got " .. listOutline())
	check(plain(listRow("more").Name:GetText()) == "2 more outside your levels · Show all levels" and not listRow("more").Icon:IsShown(),
		"a quiet line at the end: how many the level filter left out")
	check(view.d.map.frame:IsShown(), "the details' small map: shown (the zone's map isn't in sight)")
	listRow("more"):Click()
	check(filters.allLevels and listOutline() == "#In progress 103 #Available now 104 107 110 #Coming up 111 #Blocked 105 106 108 #Completed",
		"a click: all levels, got " .. listOutline())
	check(plain(listRow(105).Right:GetText()) == "Needs Investigate Echo Ridge" and plain(listRow(111).Right:GetText()) == "Needs level 7"
		and plain(listRow(104).Right:GetText()) == "Marshal Dughan" and plain(listRow("z:1429:b:available").Right:GetText()) == "3",
		"what blocks it, the level it needs, the giver; how many")
	check(plain(listRow(104).Name:GetText()) == "[4] Brotherhood of Thieves" and listRow(103).Picked:IsShown(), "level and title; the quest picked marked")
	check(view.head.Title:GetText() == "Elwynn Forest" and not view.Zoom:IsShown(), "the zone's head, no zoom")
	listRow("z:1429:b:done"):Click()
	check(listOutline():find("#Completed 101 102", 1, true), "the done ones open")
	-- One I skipped goes with the done ones; not for me only with its filter, saying why.
	STATUS_OF[106], WHY[106] = "other", { "closed", 104 }
	Q.ToggleBrowser(); Q.ToggleBrowser()
	check(listOutline():find("#Completed 101 102 106", 1, true) and plain(listRow(106).Right:GetText()) == "Skipped", "skipped: with the completed ones")
	listRow(106)._scripts.OnEnter(listRow(106))
	check(TOOLTIP.lines[1] == "Skipped" and TOOLTIP.lines[2] == "You took Brotherhood of Thieves instead", "its tooltip: what I took instead")
	listRow(106)._scripts.OnLeave(listRow(106))
	view.filters.showOther:Click()
	check(listOutline():find("#Not for you 112$") and plain(listRow(112).Right:GetText()) == "Not for your faction",
		"not for you: only with the filter, saying why, got " .. listOutline())
	view.filters.showOther:Click()
	STATUS_OF[106], WHY[106] = "locked", nil
	Q.ToggleBrowser(); Q.ToggleBrowser()
	listRow(111):Click()
	check(st.picked == 111 and plain(view.d.Title:GetText()) == "[9] Princess Must Die", "a click: the details")
	view.d.links[1]:Click()
	check(st.tab == "overview", "a link from the overview: it stays the overview")
	view.filters.allLevels:Click()
	view.tabs.zone:Click()
	check(st.tab == "zone" and view.zp:IsShown() and st.chain == nil, "the zone's tab: its page")
end

section("Questtree: the big window, the search")
do
	view.Box:SetText("echo")
	check(view.Clear:IsShown() and st.query == "", "typing: not searched yet")
	Wait(0.5)
	check(st.query == "echo" and listOutline() == "#Search results 103 105" and view.head.Title:GetText() == "Search results"
		and listRow("search").Right:GetText() == "2" and not view.zp:IsShown() and not view.tabs.zone.Line:IsShown(),
		"searched after a moment: the results replace the page, got " .. listOutline())
	check(plain(listRow(105).Right:GetText()) == "Elwynn Forest", "a result says its zone")
	listRow(105):Click()
	check(st.drilled and st.picked == 105 and st.chain == nil and view.Box:GetText() == "echo" and view.zp:IsShown() and view.Back:IsShown()
		and marker("Deputy Willem").Ring:IsShown(), "a result clicked: its zone's map, picked on it, a way back, the search stays")
	check(plain(view.Back.Text:GetText()) == "Back to the search results", "the way back says so")
	view.Back:Click()
	check(not st.drilled and listOutline() == "#Search results 103 105" and not view.Back:IsShown(), "back: the results")
	zoneRow("z:1436"):Click()
	check(st.drilled and st.where == "z:1436" and view.zp:IsShown() and view.Back:IsShown(), "a zone clicked during a search: there, inside the search")
	view.Box:SetText("e")
	Wait(0.5)
	check(view.Message:IsShown() and view.Message:GetText() == "Type at least two letters." and #view.list.entries == 0, "one letter: not searched")
	view.Box:SetText("401")
	Wait(0.5)
	check(listOutline() == "#Search results 401", "a quest's ID finds it")
	view.Box:SetText("zzz")
	Wait(0.5)
	check(view.Message:IsShown() and view.Message:GetText() == "Nothing found", "nothing found: says so")
	view.Clear:Click()
	check(st.query == "" and not view.Clear:IsShown() and not view.Back:IsShown() and st.where == "z:1436" and view.zp:IsShown(),
		"cleared: the zone's page, where I was")
	view.Box:SetText("militia")
	Q.ToggleBrowser()
	Wait(0.5)
	check(st.query == "" and win:GetScript("OnUpdate") == nil, "closed right after typing: nothing runs")
	Q.ToggleBrowser()
	Wait(0.1)
	check(st.query == "militia" and listOutline() == "#Search results 201", "opened again: searched then")
	view.Clear:Click()
end

section("Questtree: the big window, views other files register")
do
	local log = {}
	local built
	local function Build(parent)
		log[#log + 1] = "build"
		local f = CreateFrame("Frame", nil, parent)
		local b = CreateFrame("Button", nil, f)
		b:SetScript("OnClick", function() Q.OpenBrowser(104) end)
		built = { frame = f, button = b, parent = parent,
			Refresh = function(self) log[#log + 1] = "refresh" end,
			OnShow = function(self) log[#log + 1] = "show" end,
			OnHide = function(self) log[#log + 1] = "hide" end }
		return built
	end
	check(Q.RegisterBrowserView("zone", "Mine", Build) == false and Q.RegisterBrowserView("overview", "Mine", Build) == false
		and Q.RegisterBrowserView("x", "X", nil) == false and Q.RegisterBrowserView(nil, "X", Build) == false, "the window's own keys and broken ones refused")
	check(Q.RegisterBrowserView("test", "Storylines", Build) == true and view.tabs.test and view.tabs.test:IsShown()
		and plain(view.tabs.test.Text:GetText()) == "Storylines" and #log == 0, "registered: a tab of its own, nothing built yet")
	local order = {}
	for _, t in ipairs(registry.order) do order[#order + 1] = t.key end
	check(view.tabs.test._points[1][2] > view.tabs.overview._points[1][2] and order[#order] == "test", "after the zone page and the overview")
	view.tabs.test:Click()
	check(table.concat(log, ",") == "build,show,refresh" and st.tab == "test" and M.db.browser.tab == "test", "its tab: built (once), shown, refreshed")
	local holder = built.parent
	check(holder:IsShown() and built.frame._points[1] and holder:GetWidth() == 1012 and holder:GetHeight() == 742 and view.viewW == 1012,
		"in the middle under the tab bar (1012 x 742 here), its frame filling it, got " .. holder:GetWidth() .. " x " .. holder:GetHeight())
	check(view.b.Scroll:IsShown() ~= view.d.Panel:IsShown(), "the right pane: the briefing or the quest picked (never empty)")
	check(not view.zp:IsShown() and not view.g.frame:IsShown() and not view.list.scroll:IsShown() and not view.head:IsShown()
		and not view.Legend:IsShown() and view.tabs.test.Line:IsShown() and not view.tabs.zone.Line:IsShown(), "our pages hidden, its tab marked")
	-- Quests changing while it's shown: refreshed on the next frame.
	Fire("QUEST_ACCEPTED", 104)
	Wait(0.6)
	check(log[#log] == "refresh" and #log == 4, "a quest accepted: refreshed")
	view.tabs.zone:Click()
	check(log[#log] == "hide" and not holder:IsShown() and view.zp:IsShown(), "another tab: hidden")
	check(Q.ShowBrowserView("test") == true and log[#log - 1] == "show" and log[#log] == "refresh" and holder:IsShown(), "Q.ShowBrowserView: shown again (not built again)")
	local builds = 0
	for _, w in ipairs(log) do builds = builds + (w == "build" and 1 or 0) end
	check(builds == 1, "built once")
	Q.ToggleBrowser()
	check(log[#log] == "hide", "the window closed: hidden")
	Q.ToggleBrowser()
	check(log[#log] == "refresh" and log[#log - 1] == "show" and st.tab == "test", "opened again: on it")
	-- Going from it to a quest or a zone.
	built.button:Click()
	check(st.tab == "zone" and st.chain == nil and view.zp:IsShown() and st.picked == 104 and log[#log] == "hide",
		"Q.OpenBrowser(id) from it: the quest's zone map, the quest picked")
	Q.ShowBrowserView("test")
	check(Q.SelectZone(WESTFALL) == true and st.tab == "zone" and st.where == "z:1436" and st.chain == nil and view.zp:IsShown()
		and zoneRow("z:1436").Picked:IsShown(), "Q.SelectZone(map) from it: the zone's page")
	check(Q.SelectZone(999999) == false and Q.SelectZone("The Deadmines") == true and st.where == "d:The Deadmines", "a dungeon by its name; an unknown map: false")
	check(Q.ShowBrowserView("nothing") == false and Q.ShowBrowserView("overview") == true and st.tab == "overview", "the overview too; an unknown view: false")
	Q.ShowBrowserView("zone")
	-- A view that fails: says so, the window goes on.
	local errors = #ERRORS
	Q.RegisterBrowserView("broken", "Broken", function() error("view broke") end)
	view.tabs.broken:Click()
	check(#ERRORS == errors + 1 and ERRORS[#ERRORS]:find("view broke", 1, true) and st.tab == "broken", "a view that fails to build: its error reported")
	for i = #ERRORS, errors + 1, -1 do table.remove(ERRORS, i) end -- (the test's own)
	view.tabs.zone:Click()
	check(view.list.scroll:IsShown() and st.tab == "zone" and registry.current == nil, "the window goes on (the dungeon's Zone tab: its quest list)")
	-- Closed: Q.SelectZone opens it.
	Q.ToggleBrowser()
	check(Q.SelectZone(ELWYNN) == true and win:IsShown() and st.where == "z:1429", "Q.SelectZone opens the window")
	-- (the test's views go again)
	for _, key in ipairs({ "test", "broken" }) do
		registry.byKey[key] = nil
		view.tabs[key]:Hide()
		view.tabs[key] = nil
	end
	for i = #registry.order, 1, -1 do
		if registry.order[i].key == "test" or registry.order[i].key == "broken" then table.remove(registry.order, i) end
	end
	registry.current = nil
end

section("Questtree: the big window, quests changing")
do
	Q.OpenBrowser(103)
	view.d.ChainBtn:Click()
	check(st.where == "z:1429" and st.picked == 103 and card(103):IsShown(), "on its chain")
	local draws, built = st.draws, st.layouts_built
	STATUS_OF[103] = "done"
	STATUS_OF[105] = "available"
	Fire("QUEST_TURNED_IN", 103, 100, 0)
	Fire("QUEST_ACCEPTED", 105)
	check(st.draws == draws and not card(103).Check:IsShown(), "not in the event: nothing drawn yet")
	Wait(0.5)
	check(st.draws == draws + 1 and st.layouts_built == built + 1, "the next frame: drawn once for both, got " .. (st.draws - draws))
	check(card(103).Check:IsShown() and card(105).Strip.color[1] == 0.85 and plain(zoneRow("z:1429").Count:GetText()) == "3 of 10"
		and plain(view.head.Count:GetText()) == "3 of 9 steps done" and segsOf(103, 105)[1].tone == 1,
		"the cards, the zone's count, the head and the lines follow")
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
	view.head.Back:Click()
	unpick()
	check(plain(chainCard(CHAIN1).Count:GetText()) == "3/9" and plain(chainCard(CHAIN1).Next:GetText()) == "Next: Speak with Willem · Guard Roberts",
		"the zone page's card too: nothing in my log, the first I can take, got " .. plain(chainCard(CHAIN1).Next:GetText()))

	-- Closed: nothing heard, nothing runs; opened: as it is now.
	Q.ToggleBrowser()
	draws = st.draws
	STATUS_OF[104] = "done"
	Fire("QUEST_TURNED_IN", 104, 100, 0)
	Fire("QUEST_LOG_UPDATE")
	Wait(1)
	check(st.draws == draws and win:GetScript("OnUpdate") == nil and not st.listening, "closed: events aren't listened to")
	Q.ToggleBrowser()
	check(plain(zoneRow("z:1429").Count:GetText()) == "4 of 10" and chainCard(CHAIN1).Count:GetText() == "4/9", "opened again: the counts and statuses of now")

	-- The client's title coming in later: the cards in sight follow.
	local asked = {}
	C_QuestLog.RequestLoadQuestByID = function(id) asked[#asked + 1] = id end
	st.asked[111] = nil
	openChain(SINGLES)
	Q.ToggleBrowser(); Q.ToggleBrowser()
	Q.ToggleBrowser(); Q.ToggleBrowser()
	local times = 0
	for _, id in ipairs(asked) do times = times + (id == 111 and 1 or 0) end
	check(times == 1, "a title the client doesn't know: asked for, once, got " .. times)
	QUESTS = { { id = 111, title = "Prinzessin muss sterben", objectives = {} } }
	Fire("QUEST_DATA_LOAD_RESULT", 111, true)
	Wait(0.5)
	check(plain(card(111).Title:GetText()) == "[9] Prinzessin muss sterben", "it came: the card shows it")
	QUESTS = {}
	C_QuestLog.RequestLoadQuestByID = nil
	view.head.Back:Click()
end

section("Questtree: the big window, the data changing")
do
	local _, _, _, changed = Q.BrowserView()
	QUESTS_DATA[113] = { id = 113, title = "Lost Necklace", level = 6, minLevel = 5, zone = ELWYNN }
	ZONE_QUESTS[ELWYNN][#ZONE_QUESTS[ELWYNN] + 1] = 113
	openChain(SINGLES)
	local built = st.trees_built
	changed()
	check(st.trees_built == built and not item(113), "in the callback: nothing drawn")
	Wait(0.5)
	check(st.trees_built == built + 1 and item(113) and graphOutline() == "110 113 111", "the next frame: worked out again, got " .. graphOutline())
	Q.ToggleBrowser()
	ZONE_QUESTS[ELWYNN][#ZONE_QUESTS[ELWYNN]] = nil
	QUESTS_DATA[113] = nil
	changed()
	Wait(0.5)
	check(win:GetScript("OnUpdate") == nil, "closed: nothing runs for it")
	Q.ToggleBrowser()
	check(not item(113), "it comes when the window opens")
	local before = st.trees_built
	zoneRow("z:1436"):Click()
	zoneRow("z:1429"):Click()
	check(st.trees_built == before + 1, "a zone's chains are worked out once, then kept")
end

section("Questtree: the big window, a big zone and the canvas")
do
	local list = {}
	for i = 1, 400 do
		local id = 5000 + i
		QUESTS_DATA[id] = { id = id, title = "Bloodsail Business " .. i, level = 30 + i % 10, zone = STV }
		list[i] = id
	end
	ZONE_QUESTS[STV] = list
	table.insert(ZONES, 4, { map = STV, name = "Stranglethorn Vale", continent = EK, minLevel = 30, maxLevel = 45 })
	local _, _, _, changed = Q.BrowserView()
	changed()
	Wait(0.5)
	check(zoneRow("z:1434").Name:GetText() == "|cff888888Stranglethorn Vale|r" and plain(zoneRow("z:1434").Count:GetText()) == "0 of 400",
		"a zone far above my level (19, its levels 30-45): dimmed on the left, its count kept")
	zoneRow("z:1434"):Click()
	check(cardsOutline() == "z:1434:more" and plain(chainCard("z:1434:more").Line:GetText()):find("^1 more outside your levels"),
		"the zone page: nothing within my levels, a line says so, got " .. cardsOutline())
	view.filters.allLevels:Click()
	check(cardsOutline() == "z:1434:single" and #view.b.cards <= 3, "all levels: one card (pooled)")
	openChain("z:1434:single")
	view.filters.allLevels:Click()
	check(st.chain == "z:1434:single", "its page stays when the filter goes off (a chain's page shows every level)")
	local g = view.g
	local near = 0
	for _ in pairs(g.cards) do near = near + 1 end
	check(#lay().cards == 400 and near < 60 and g.made < 80, "400 quests: only the cards near sight exist, got " .. near .. " (made " .. g.made .. ")")
	check(g.VThumb:IsShown() and not g.HThumb:IsShown(), "a bar says where it's scrolled")
	local statuses = calls.Status
	local lays = g.lays
	local id = lay().cards[4 * 3 + 1].quest
	local kept = g.cards[id]
	g.frame._scripts.OnMouseWheel(g.frame, -1)
	check(g.sy == 82 and g.lays == lays + 1, "the wheel scrolls a stage down, got " .. g.sy)
	g.frame._scripts.OnMouseWheel(g.frame, -1)
	g.frame._scripts.OnMouseWheel(g.frame, 1)
	check(kept and g.cards[id] == kept and kept.item.quest == id, "each card stays on its quest (a controller's cursor stays on it)")
	check(calls.Status - statuses < 400, "scrolled: only the cards near sight read their status")
	-- Dragging moves it.
	CURSOR.x, CURSOR.y = 500, 500
	g.frame._scripts.OnDragStart(g.frame)
	CURSOR.y = 600
	g.frame._scripts.OnUpdate(g.frame, 0.01)
	g.frame._scripts.OnDragStop(g.frame)
	check(g.sy == 182 and g.frame:GetScript("OnUpdate") == nil, "dragged 100 down: 100 further, got " .. g.sy)
	-- The controller's cursor on a card below sight: it comes into view.
	local before = g.sy
	local below
	for _, c in pairs(g.cards) do
		if c.item.y > g.sy + g.h then below = c end
	end
	GAMEPAD_STATE.ui = true
	below._scripts.OnEnter(below)
	GAMEPAD_STATE.ui = false
	check(below and g.sy > before and below.item.y + 48 <= g.sy + g.h, "a card the controller moves to out of sight: brought into view")
	below._scripts.OnLeave(below)
	-- Zoom: Ctrl and the wheel, the buttons, Fit.
	STATE.ctrl = true
	g.frame._scripts.OnMouseWheel(g.frame, -1)
	STATE.ctrl = false
	check(g.zoom == 0.9 and g.canvas:GetScale() == 0.9 and plain(view.ZoomText:GetText()) == "90%", "Ctrl and the wheel: zoomed out")
	for _ = 1, 5 do view.ZoomButtons.minus:Click() end
	check(g.zoom == 0.5, "down to half")
	view.ZoomButtons.fit:Click()
	check(g.zoom == 1, "Fit: as much as fits (the width here)")
	table.remove(ZONES, 4)
	ZONE_QUESTS[STV] = nil
	for i = 1, 400 do QUESTS_DATA[5000 + i] = nil end
	changed()
	Wait(0.5)
	check(st.where == "z:1429" and st.chain == nil, "the zone gone: back to mine, its page")
end

section("Questtree: the big window, a small screen and the controller")
do
	local width, height = GetScreenWidth, GetScreenHeight
	GetScreenWidth, GetScreenHeight = function() return 1024 end, function() return 768 end
	Q.ToggleBrowser()
	Q.ToggleBrowser()
	check(math.abs(win:GetScale() - math.min((1024 - 40) / 1700, (768 - 80) / 868)) < 1e-6, "a small screen: scaled to fit, got " .. win:GetScale())
	-- The size it's built at, by the screen: at least 1400 x 760, wider (and the map with it) where there's room.
	local sizes = {}
	for _, s in ipairs({ { 1365, 768 }, { 1600, 900 }, { 1920, 1080 }, { 2560, 1440 } }) do
		GetScreenWidth, GetScreenHeight = function() return s[1] end, function() return s[2] end
		local w, h, right = view.Size()
		sizes[#sizes + 1] = w .. "x" .. h .. "/" .. right
	end
	check(table.concat(sizes, " ") == "1400x760/360 1520x775/360 1700x868/400 1700x868/400",
		"the default UI's screen: 1400 x 760 (scaled to fit); more room: wider, up to 1700, as high as the map needs, got " .. table.concat(sizes, " "))
	GetScreenWidth, GetScreenHeight = width, height
	Q.ToggleBrowser()
	Q.ToggleBrowser()
	check(win:GetScale() == 1, "a big one: full size")
	unpick()
	openChain(CHAIN1)
	card(103):Click()
	local m = view.zp.map
	local buttons = true
	for _, list in ipairs({ view.zones.rows, view.list.rows, view.b.cards, view.b.rows, view.d.links, view.d.places, view.d.steps, view.d.objectives,
		view.d.items, view.g.cards, view.tabs, view.filters, view.ZoomButtons, m.markers, m.buttons, m.ends, view.d.map.markers, view.d.map.ends,
		m.chooser and m.chooser.rows or {} }) do
		for _, b in pairs(list) do buttons = buttons and b._kind == "Button" end
	end
	for _, a in ipairs(m.areas) do buttons = buttons and a.Button._kind == "Button" end
	check(buttons and view.d.Small._kind == "Button" and view.d.Pin._kind == "Button" and view.d.Back._kind == "Button" and view.d.ChainBtn._kind == "Button"
		and view.Clear._kind == "Button" and view.Back._kind == "Button" and view.head.Back._kind == "Button" and view.zp.Suggest._kind == "Button"
		and #view.d.objectives > 0 and #view.d.items > 0 and #m.areas > 0,
		"every card, pin, area, row, tab, filter, link, reward, the map's zoom and the pane's buttons: buttons the controller reaches")
	check(view.g.frame:GetScript("OnMouseDown") == nil and view.g.frame:GetScript("OnMouseUp") == nil
		and m.frame:GetScript("OnMouseDown") == nil and m.frame:GetScript("OnMouseUp") == nil,
		"the canvas and the map themselves aren't (no mouse down or up script)")
	local blizzard = false
	for _, f in ipairs({ win, view.root, view.zones.scroll, view.list.scroll, view.b.Scroll, view.d.Scroll, view.g.frame, view.g.canvas, view.zp, m.frame }) do
		blizzard = blizzard or f.useCustomNavigation ~= nil or f.smartNavigationIgnored ~= nil
	end
	check(not blizzard, "nothing of Blizzard's on our frames")
	-- The controller's cursor on a pin out of sight: the map moves there.
	view.head.Back:Click()
	m.buttons.plus:Click()
	m.buttons.plus:Click()
	m.buttons.plus:Click()
	local function Out(mk) return mk.px + m.ox < 0 or mk.px + m.ox > m.width or mk.py + m.oy < 0 or mk.py + m.oy > m.height end
	local far
	for i = 1, m.shown do
		far = far or (Out(m.markers[i]) and m.markers[i]) or nil
	end
	local outside = far ~= nil
	far = far or m.markers[1]
	GAMEPAD_STATE.ui = true
	far._scripts.OnEnter(far)
	check(outside and far.px + m.ox >= 0 and far.px + m.ox <= m.width and far.py + m.oy >= 0 and far.py + m.oy <= m.height,
		"a pin the controller moves to out of sight: the map moves to it")
	far._scripts.OnLeave(far)
	GAMEPAD_STATE.ui = false
	m.buttons.fit:Click()
	-- The controller's cursor on a chain's card lights its pins, as the mouse does.
	unpick()
	GAMEPAD_STATE.ui = true
	local c = chainCard(CHAIN1)
	c._scripts.OnEnter(c)
	check(view.zp.map.lit == CHAIN1 and marker("drops here (12%)"):GetAlpha() == 0.3, "a chain's card the controller is on: its pins lit")
	c._scripts.OnLeave(c)
	Q.ToggleBrowser()
	Q.ToggleBrowser()
	check(win:IsShown() and view.root:IsShown(), "it opens in gamepad mode")
	GAMEPAD_STATE.ui = false
	EnterCombat()
	Q.ToggleBrowser()
	Q.ToggleBrowser()
	openChain(CHAIN1)
	card(101):Click()
	check(win:IsShown() and st.picked == 101 and #BLOCKED == blockedBefore, "and in a fight")
	LeaveCombat()
end

-- Back as it was: the window closed, the real functions.
Q.HideBrowser()
for key, fn in pairs(saved) do
	Q[key] = fn or nil
end
if M and M.db then M.db.browser = browserSaved end
MAP_NAMES[DUROTAR], MAP_NAMES[STV], MAP_NAMES[REDRIDGE] = nil, nil, nil
QUESTS = questLogBefore
Wait(math.ceil(waited) - waited + 1)
