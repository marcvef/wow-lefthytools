-- Questtree: the big window (Browser.lua), against a small made-up world. The data and engine (Q.Load,
-- Q.Quest, Q.Zones, Q.Status, Q.Chain, ...), the iteration's new ones (Q.ZoneCount, Q.ChainStep,
-- Q.LevelColor, Q.Races, Q.ZoneGiven), the small window (Q.ShowQuest, Q.IsSmallShown) are stand-ins
-- installed here, so every card is certain; the real ones are put back at the end. Without the new
-- ones the window works too (counted here, the step from Q.Chain, the level against mine). The empty
-- window without the data, the zones by continent with their counts, the chains as cards (stages,
-- centred, lines that never run through a card, their colours, OR, banners, folding), the filters,
-- the canvas (pools, scrolling, zoom, a card the controller reaches out of sight), the overview, the
-- zone map (markers, a giver with several quests, drop areas, clicks, zoom), the details (level
-- colour, chain step, drops, map pins, races), the search, events and data changes redrawn on the next
-- frame only while it's open, a small screen, the controller's buttons.
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
MAP_NAMES[DUROTAR], MAP_NAMES[STV] = "Durotar", "Stranglethorn Vale"
local function at(map, x, y) return { map = map, x = x, y = y } end
local DUGHAN = { kind = "npc", id = 240, name = "Marshal Dughan", points = { at(ELWYNN, 0.42, 0.66) } }
local WILLEM = { kind = "npc", id = 241, name = "Deputy Willem", points = { at(ELWYNN, 0.48, 0.42) } }
local FANG = { kind = "item", id = 7001, name = "Wolf Fang", points = {}, drops = {
	{ kind = "npc", id = 300, name = "Young Wolf", chance = 12, points = { at(ELWYNN, 0.3, 0.7) } },
	{ kind = "npc", id = 301, name = "Timber Wolf", chance = 0.5, points = { at(ELWYNN, 0.6, 0.8) } } } }
local QUESTS_DATA = {
	[101] = { id = 101, title = "A Threat Within", level = 1, minLevel = 1, zone = ELWYNN, opens = { 102 }, starts = { DUGHAN } },
	[102] = { id = 102, title = "Kobold Camp Cleanup", level = 2, minLevel = 1, zone = ELWYNN, pre = { 101 }, opens = { 103, 104 } },
	[103] = { id = 103, title = "Investigate Echo Ridge", level = 3, minLevel = 2, zone = ELWYNN, pre = { 102 }, opens = { 105 }, ends = { WILLEM } },
	[104] = { id = 104, title = "Brotherhood of Thieves", level = 4, minLevel = 2, zone = ELWYNN, pre = { 102 },
		races = 77, classes = 1, skill = { id = 165, value = 50 }, rep = { faction = 72, min = 3000 }, repeatable = true, new = true,
		starts = { DUGHAN, { kind = "object", id = 9, name = "Wanted Poster", points = { at(ELWYNN, 0.45, 0.6) } } },
		ends = { WILLEM } },
	[105] = { id = 105, title = "Skirmish at Echo Ridge", level = 5, minLevel = 3, zone = ELWYNN, pre = { 103 }, opens = { 201 } },
	[106] = { id = 106, title = "Report to Goldshire", level = 6, minLevel = 4, zone = ELWYNN, preAny = { 103, 104 } },
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
}
local ZONES = {
	{ map = ELWYNN, name = "Elwynn Forest", continent = EK, minLevel = 1, maxLevel = 10 },
	{ map = WESTFALL, name = "Westfall", continent = EK, minLevel = 9, maxLevel = 18 },
	{ map = DUROTAR, name = "Durotar", continent = KALIMDOR, minLevel = 1, maxLevel = 10 },
}
local ZONE_QUESTS = { [ELWYNN] = { 101, 102, 103, 104, 105, 106, 108, 110, 111, 112 }, [WESTFALL] = { 201, 202 }, [DUROTAR] = { 401 } }
local DUNGEON_QUESTS = { ["The Deadmines"] = { 301 } }
local CHAINS = { { 101, 102, 103, 104, 105, 106, 108, 201 }, { 301, 202 } }
local STATUS_OF = { [101] = "done", [102] = "done", [103] = "active", [104] = "available", [105] = "locked", [106] = "locked",
	[108] = "locked", [110] = "available", [111] = "level", [112] = "other", [201] = "locked", [202] = "locked", [301] = "level", [401] = "other" }
local MISSING = { [105] = { { id = 103, status = "active" } }, [201] = { { id = 103, status = "active" }, { id = 105, status = "locked" } },
	[202] = { { id = 301, status = "level" } }, [106] = { { id = 103, status = "active" } }, [108] = { { id = 103, status = "active" } } }
local FRIENDS = { [104] = { { name = "Anna Brook", classFile = "MAGE", status = "done" }, { name = "Bob", classFile = "WARRIOR", status = "active" } } }
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

local loaded, dataCallbacks, shownInSmall, smallOpen, calls = false, {}, {}, false, { Status = 0, Chain = 0, ZoneCount = 0 }
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
	st.where, st.picked, st.query, st.results, st.drilled, st.places, st.opened, st.tab = nil, nil, "", nil, false, nil, nil, "chains"
	wipe(st.folded); wipe(st.trees); wipe(st.counts); wipe(st.layouts)
end

local view, st, win, filters
local function refs()
	local v, s, w, _, f = Q.BrowserView()
	view, st, win, filters = v, s, w, f
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
		if e and (e.quest == match or e.key == match or (match == "search" and e.search)) then return row end
	end
end
local function zonesOutline()
	local out = {}
	for _, e in ipairs(view.zones.entries) do out[#out + 1] = e.header and ("#" .. e.label) or e.name end
	return table.concat(out, ", ")
end
local function listOutline()
	local out = {}
	for _, e in ipairs(view.list.entries) do out[#out + 1] = e.header and ("#" .. e.label) or tostring(e.quest) end
	return table.concat(out, " ")
end
local function lay() return view.g.layout end
local function item(id) return lay().byQuest[id] end
local function card(id) return view.g.cards[id] end
-- The chains as words: each banner "#", each card "id@stage" in the layout's order.
local function graphOutline()
	local out = {}
	local byBanner = {}
	for _, it in ipairs(lay().cards) do
		local key = it.group.key
		byBanner[key] = byBanner[key] or {}
		table.insert(byBanner[key], it.stage and (it.quest .. "@" .. it.stage) or tostring(it.quest))
	end
	for _, b in ipairs(lay().banners) do
		out[#out + 1] = "#"
		for _, w in ipairs(byBanner[b.key] or {}) do out[#out + 1] = w end
	end
	return table.concat(out, " ")
end
local function segsOf(fromId, toId) -- segments between two cards' columns (tests: the colours)
	local a, b = item(fromId), item(toId)
	local list = {}
	for _, s in ipairs(lay().segs) do
		if s.minY >= a.bottom - 1 and s.maxY <= b.y + 1 and ((s.x1 == a.cx and s.x2 == a.cx) or (s.x1 == b.cx and s.x2 == b.cx)) then
			list[#list + 1] = s
		end
	end
	return list
end
local function bannerFrame(key) return view.g.banners[key] end

section("Questtree: the big window without the data")
do
	Q.OpenBrowser()
	refs()
	check(win == LefthyToolsQuesttreeBrowser and win:IsShown() and win.TitleContainer.TitleText:GetText() == "Questtree",
		"it opens, called Questtree (never translated)")
	check(view.Empty:IsShown() and not view.root:IsShown() and not view.Box:IsShown() and not view.filters.hideDone:IsShown()
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
	check(win:GetWidth() == 1320 and win:GetHeight() == 800 and win:GetScale() == 1, "1320 x 800, not scaled on a big screen")
	check(zonesOutline() == "#Eastern Kingdoms, Elwynn Forest, Westfall, #Kalimdor, Durotar, #Dungeons, The Deadmines",
		"by continent, then the dungeons, got: " .. zonesOutline())
	check(st.where == "z:1429" and zoneRow("z:1429").Picked:IsShown() and not zoneRow("z:1436").Picked:IsShown(),
		"the zone I'm in is chosen at first")
	local elwynn = zoneRow("z:1429")
	check(elwynn.Name:GetText() == "Elwynn Forest" and elwynn.Range:GetText() == "1-10" and plain(elwynn.Count:GetText()) == "2 of 9"
		and calls.ZoneCount > 0, "name, level range, done of every quest for me at any level (Q.ZoneCount), got " .. tostring(plain(elwynn.Count:GetText())))
	check(elwynn.Bar:IsShown() and math.abs(elwynn.Bar.width - (elwynn:GetWidth() - 24) * 2 / 9) < 0.01, "a thin bar: how far along")
	check(plain(zoneRow("z:1411").Count:GetText()) == "-" and zoneRow("d:The Deadmines").Range:GetText() == "17-24"
		and plain(zoneRow("d:The Deadmines").Count:GetText()) == "0 of 1", "Durotar: nothing for me; the dungeon by its name")
	check(plain(view.Head:GetText()) == "Elwynn Forest  Level 1-10   2 of 9 done", "the middle's title, got " .. plain(view.Head:GetText()))
	-- Without Q.ZoneCount (Data.lua before this iteration): counted here, the same.
	Q.ZoneCount = nil
	wipe(st.counts)
	view.zones:Lay()
	check(plain(zoneRow("z:1429").Count:GetText()) == "2 of 9", "without Q.ZoneCount: counted here, got " .. plain(zoneRow("z:1429").Count:GetText()))
	Q.ZoneCount = stand.ZoneCount
	zoneRow("c:1415"):Click()
	check(zonesOutline() == "#Eastern Kingdoms, #Kalimdor, Durotar, #Dungeons, The Deadmines" and zoneRow("c:1415").Toggle.path:find("Plus", 1, true),
		"a continent folds")
	zoneRow("c:1415"):Click()
	check(zonesOutline():find("Elwynn Forest", 1, true), "and opens again")
	local legend = plain(view.Legend:GetText())
	check(legend:find("Completed", 1, true) and legend:find("In your quest log", 1, true) and legend:find("Available", 1, true)
		and legend:find("Locked", 1, true) and legend:find("Level too low", 1, true) and legend:find("Not for you", 1, true),
		"the legend names every status, got " .. legend)
end

section("Questtree: the big window, chains as cards")
do
	check(st.tab == "chains" and view.g.frame:IsShown() and not view.mapPane:IsShown() and not view.list.scroll:IsShown()
		and view.tabs.chains.Line:IsShown() and not view.tabs.map.Line:IsShown(), "the chains' tab first")
	check(graphOutline() == "# 101@0 102@1 103@2 104@2 105@3 106@3 201@4 108@4 # 110 111",
		"a row per stage, the next ones side by side, ordered by where what leads to them is; then the quests without a chain "
		.. "(the Horde one not shown), got: " .. graphOutline())
	local a, b, c, d = item(101), item(102), item(103), item(104)
	check(a.x == 6 + (660 - 170) / 2 and a.cx == b.cx and c.y == b.y + 78 and c.y == d.y and d.x == c.x + 170 + 14,
		"centred, 78 apart in stages, 14 between cards")
	check(item(108).y == item(201).y and lay().hidden == 1, "two quests in the last stage; one quest hidden (not for me)")
	-- No line runs through a card (a line past a stage has a slot of its own).
	local through = 0
	for _, s in ipairs(lay().segs) do
		for _, it in ipairs(lay().cards) do
			if s.maxX > it.x + 1 and s.minX < it.x + 170 - 1 and s.maxY > it.y + 1 and s.minY < it.y + 48 - 1 then
				through = through + 1
			end
		end
	end
	check(#lay().segs > 10 and through == 0, "no line runs through a card, got " .. through .. " of " .. #lay().segs)
	local green, amber, grey = segsOf(101, 102)[1], segsOf(102, 103)[1], segsOf(105, 201)[1]
	check(green and green.tone == 2 and amber and amber.tone == 1 and grey and grey.tone == 0,
		"lines: green between done ones, amber from a done one, grey otherwise")
	check(#lay().pills == 1 and math.abs(lay().pills[1].x - (c.x + 170 + d.x) / 2) < 0.01, "OR between the two of which one is enough")
	check(view.g.linesShown > 0 and view.g.pills[1]:IsShown() and plain(view.g.pills[1].Text:GetText()) == "OR", "drawn: the lines and the OR")
	-- The cards.
	local done, active, avail, item110, level = card(101), card(103), card(104), card(110), card(111)
	check(done.Title:GetText() == "A Threat Within" and plain(done.Info:GetText()) == "[1] Marshal Dughan" and done.Check:IsShown()
		and done.Strip.color[2] == 0.73 and done.Bg.vertex[4] == 0.3, "a done card: title, [level] and giver, a check, the green strip and tone")
	check(done.Info:GetText():find("|cff336699[1]|r", 1, true), "the level in its difficulty colour (Q.LevelColor)")
	check(done.Icon.atlas == "QuestNormal" and done.Icon.desaturated == true and avail.Icon.atlas == "QuestDaily" and avail.Icon.desaturated == false,
		"the start: the giver's ! (a repeatable one's blue), bright only when I can take it")
	check(active.Icon.atlas == "SideInProgressquesticon" and item110.Icon.path == "Interface\\Icons\\INV_Misc_Bag_10"
		and plain(item110.Info:GetText()) == "[2] Wolf Fang", "in my log: in progress; an item: its icon, its name")
	check(not card(105).Check:IsShown() and card(105).Bg.vertex[1] == 0.1 and card(105).Edges[1].color[1] == 0.4, "locked: grey")
	check(avail.Friends:IsShown() and plain(avail.Friends:GetText()) == "1/2" and not done.Friends:IsShown(), "friends who've done it")
	check(plain(card(201).Info:GetText()) == "[10] Westfall", "a step in another zone says which")
	-- Banners.
	local key = lay().banners[1].key
	local banner = bannerFrame(key)
	check(banner and banner.Name:GetText() == "Elwynn's Kobolds" and plain(banner.Count:GetText()) == "2 of 8 steps done"
		and plain(banner.Next:GetText()) == "In your log: Investigate Echo Ridge" and banner.Art.atlas == "StoryHeader-BG",
		"a chain's banner: its name (Q.ChainStep), how far along, what's next")
	check(math.abs(banner.Bar.width - 130 * 2 / 8) < 0.01, "... and a bar")
	check(plain(bannerFrame(lay().banners[2].key).Name:GetText()) == "Quests without a chain", "the rest under a banner of their own")
	banner:Click()
	check(graphOutline() == "# # 110 111" and bannerFrame(key).Toggle.path:find("Plus", 1, true), "a chain folds")
	bannerFrame(key):Click()
	check(graphOutline():find("# 101@0", 1, true) == 1, "and opens")
	-- Without Q.ChainStep and Q.LevelColor: the chain's first title, the level against mine (19).
	Q.ChainStep, Q.LevelColor = nil, nil
	wipe(st.layouts)
	view.g.bucket = nil
	Q.ToggleBrowser(); Q.ToggleBrowser()
	check(bannerFrame(key).Name:GetText() == "A Threat Within" and card(101).Info:GetText():find("|cff808080[1]|r", 1, true),
		"without them: the first quest's title, level 1 grey (trivial at 19)")
	Q.ChainStep, Q.LevelColor = stand.ChainStep, stand.LevelColor
	card(103)._scripts.OnEnter(card(103))
	check(TOOLTIP.shown and TOOLTIP.title == "Investigate Echo Ridge" and TOOLTIP.lines[1] == "In your quest log"
		and TOOLTIP.lines[#TOOLTIP.lines] == "Click: details", "hovering: a tooltip")
	local tip = table.concat(TOOLTIP.lines, "|")
	check(tip:find("Step 3 of 8 - Elwynn's Kobolds", 1, true) and tip:find("Then: Skirmish at Echo Ridge", 1, true), "with its step and what's next")
	card(103)._scripts.OnLeave(card(103))
	check(not TOOLTIP.shown, "gone when the mouse leaves")
end

section("Questtree: the big window, the filters")
do
	check(view.filters.hideDone._kind == "Button" and not view.filters.hideDone.Tick.shown and plain(view.filters.hideDone.Text:GetText()) == "Hide done",
		"filters: buttons of ours, off")
	view.filters.hideDone:Click()
	check(filters.hideDone and view.filters.hideDone.Tick.shown and M.db.browser.hideDone == true, "hide done: on, kept in the settings")
	check(graphOutline() == "# 103@0 104@0 105@1 106@1 108@2 201@2 # 110 111", "done ones gone, the rest moves up, got " .. graphOutline())
	view.filters.hideDone:Click()
	view.filters.onlyAvailable:Click()
	check(graphOutline() == "# 104@0 # 110", "only available now, got " .. graphOutline())
	view.filters.onlyAvailable:Click()
	view.filters.showOther:Click()
	check(graphOutline() == "# 101@0 102@1 103@2 104@2 105@3 106@3 201@4 108@4 # 110 112 111" and card(112):GetAlpha() == 0.55,
		"not for me: shown, dimmed, got " .. graphOutline())
	view.filters.showOther:Click()
	-- A hidden step between two shown: the line passes through, fainter.
	STATUS_OF[101] = "active"
	view.filters.hideDone:Click()
	local faint = 0
	for _, s in ipairs(lay().segs) do faint = faint + (s.faint and 1 or 0) end
	check(graphOutline():find("101@0 103@1", 1, true) and faint > 0, "a hidden step: its line passes through, fainter, got " .. graphOutline())
	view.filters.hideDone:Click()
	STATUS_OF[101] = "done"
	wipe(st.layouts)
	Q.ToggleBrowser(); Q.ToggleBrowser()
	check(not filters.hideDone and not filters.onlyAvailable and not filters.showOther, "all off again")
end

section("Questtree: the big window, the details")
do
	check(view.d.Hint:IsShown() and not view.d.Body:IsShown() and not view.d.Small:IsShown(), "nothing chosen: a hint")
	card(105):Click()
	check(st.picked == 105 and card(105).Glow:IsShown() and card(105).Edges[1].color[2] == 0.82 and not card(104).Glow:IsShown(),
		"a click: its card marked")
	local sub = plain(view.d.Sub:GetText())
	check(plain(view.d.Title:GetText()) == "[5] Skirmish at Echo Ridge" and view.d.Title:GetText():find("|cff336699", 1, true)
		and sub:find("Locked: an earlier quest comes first", 1, true) and sub:find("Level 5, from level 3", 1, true)
		and sub:find("Step 5 of 8 - Elwynn's Kobolds", 1, true), "title in its level's colour, status, level, the step, got " .. sub)
	check(view.d.NeedsHead:IsShown() and view.d.links[1]:IsShown() and view.d.links[1].quest == 103
		and plain(view.d.links[1].Text:GetText()) == "[3] Investigate Echo Ridge", "Needs first: a button to the quest")
	check(view.d.LeadsHead:IsShown() and view.d.links[2].quest == 201 and plain(view.d.links[2].Text:GetText()) == "[10] The People's Militia - Westfall",
		"Leads to: the next one, its zone named")
	check(#shownInSmall == 0, "the small window closed: it isn't asked")
	view.d.links[1]:Click()
	check(st.picked == 103 and st.where == "z:1429" and plain(view.d.Title:GetText()) == "[3] Investigate Echo Ridge" and card(103).Glow:IsShown(),
		"a link opens that quest")

	-- The client's title, requirements, givers and their places, the map, friends.
	QUESTS = { { id = 104, title = "Bruderschaft der Diebe", objectives = {} } }
	smallOpen = true
	card(104):Click()
	check(shownInSmall[1] == 104, "the small window open: it shows the quest too")
	check(plain(view.d.Title:GetText()) == "[4] Bruderschaft der Diebe" and card(104).Title:GetText() == "Bruderschaft der Diebe",
		"the client's title when it knows the quest")
	local req = plain(view.d.Req:GetText())
	check(view.d.ReqHead:IsShown() and req:find("Races: every Alliance race", 1, true) and req:find("Classes: Warrior", 1, true)
		and req:find("Skill: Leatherworking 50", 1, true) and req:find("Reputation: #72, Friendly", 1, true),
		"requirements: a side's every race (the new ones too), classes, skill, reputation, got " .. req)
	check(plain(view.d.Sub:GetText()):find("New in WoW: Forever, Repeatable", 1, true), "new and repeatable")
	local places = {}
	for _, b in ipairs(view.d.places) do if b:IsShown() then places[#places + 1] = plain(b.Text:GetText()) end end
	check(view.d.StartsHead:IsShown() and view.d.EndsHead:IsShown() and table.concat(places, "|")
		== "Marshal Dughan - Elwynn Forest|Wanted Poster (an object) - Elwynn Forest|Deputy Willem - Elwynn Forest",
		"who gives it and where to turn it in, got " .. table.concat(places, "|"))
	local m = view.d.map
	check(m.frame:IsShown() and m.map == ELWYNN and m.shown == 3 and m.markers[1].look == "start" and m.markers[3].look == "end",
		"the small map: the zone, givers and the ender")
	check(plain(view.d.Friends:GetText()) == "Anna Brook (Completed), Bob (In your quest log)" and view.d.FriendsHead:IsShown(),
		"friends, got " .. plain(view.d.Friends:GetText()))
	check(view.d.Small:IsShown() and view.d.Small:GetText() == "Show in the small window", "a button for the small window")
	smallOpen = false
	view.d.Small:Click()
	check(shownInSmall[2] == 104, "... which shows it there")
	QUESTS = {}
	-- A place's line puts a map pin there (the game's own waypoint, nothing of the world map).
	local pins = {}
	C_Map.SetUserWaypoint = function(point) pins[#pins + 1] = point end
	C_Map.CanSetUserWaypointOnMap = function(map) return map == ELWYNN end
	UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { uiMapID = map, x = x, y = y } end }
	C_SuperTrack.SetSuperTrackedUserWaypoint = function(on) pins.tracked = on end
	view.d.places[1]._scripts.OnEnter(view.d.places[1])
	check(TOOLTIP.lines[#TOOLTIP.lines] == "Click: put a map pin there", "a place's tooltip says so")
	view.d.places[1]:Click()
	check(pins[1] and pins[1].uiMapID == ELWYNN and pins[1].x == 0.42 and pins.tracked == true, "clicked: a pin there, tracked")
	-- An item: what drops it, how often, where.
	card(110):Click()
	places = {}
	for _, b in ipairs(view.d.places) do if b:IsShown() then places[#places + 1] = plain(b.Text:GetText()) end end
	check(table.concat(places, "|") == "Wolf Fang (an item)|   Drops from Young Wolf (12%) - Elwynn Forest|   Drops from Timber Wolf (0.5%) - Elwynn Forest",
		"an item: what drops it, how often, got " .. table.concat(places, "|"))
	check(m.frame:IsShown() and m.map == ELWYNN and m.shown == 2 and m.markers[1].look == "drop", "the small map: where it drops")
	view.d.places[2]:Click()
	check(pins[2] and pins[2].x == 0.3, "a drop's line: a pin there")
	C_Map.SetUserWaypoint, C_Map.CanSetUserWaypointOnMap, UiMapPoint, C_SuperTrack.SetSuperTrackedUserWaypoint = nil, nil, nil, nil
	card(101):Click()
	check(not view.d.Req:IsShown() and not view.d.ReqHead:IsShown() and not view.d.EndsHead:IsShown() and not view.d.Friends:IsShown()
		and not view.d.NeedsHead:IsShown() and view.d.LeadsHead:IsShown(), "a plain quest: only what it has")
end

section("Questtree: the big window, across zones")
do
	zoneRow("z:1436"):Click()
	check(st.where == "z:1436" and graphOutline() == "# 101@0 102@1 103@2 104@2 105@3 106@3 201@4 108@4 # 301@0 202@1",
		"another zone: the whole chain, and a quest given here that's listed with a dungeon (Q.ZoneGiven), got " .. graphOutline())
	check(plain(card(201).Info:GetText()) == "[10] Westfall" and plain(card(101).Info:GetText()) == "[1] Elwynn Forest"
		and plain(card(301).Info:GetText()) == "[17] The Deadmines", "the steps elsewhere say where")
	check(plain(view.Head:GetText()) == "Westfall  Level 9-18   0 of 2 done", "its count: its own quests")
	card(202):Click()
	view.d.links[1]:Click()
	check(st.where == "z:1436" and st.picked == 301, "Needs first in a dungeon, given here: it stays")
	zoneRow("d:The Deadmines"):Click()
	check(st.where == "d:The Deadmines" and graphOutline() == "# 301@0 202@1", "the dungeon: its chain")
	zoneRow("c:1414"):Click()
	check(not zoneRow("z:1411"), "Kalimdor folded")
	view.filters.showOther:Click()
	Q.OpenBrowser(401)
	check(win:IsShown() and st.where == "z:1411" and st.picked == 401 and zoneRow("z:1411") and zoneRow("z:1411").Picked:IsShown(),
		"Q.OpenBrowser(id): its zone, its continent opened")
	check(plain(view.d.Sub:GetText()):find("Not for you", 1, true) and plain(view.d.Sub:GetText()):find("Learned while playing", 1, true)
		and plain(view.d.Req:GetText()):find("Faction: Horde", 1, true), "not for me: faction and where it came from")
	check(plain(view.d.Req:GetText()):find("Races: Human, High Order Skyborne", 1, true), "races named by Q.Races (Forever's new ones), got "
		.. plain(view.d.Req:GetText()))
	view.filters.showOther:Click()
	Q.OpenBrowser(103)
	check(st.where == "z:1429" and st.picked == 103 and card(103):IsShown(), "back in Elwynn")
end

section("Questtree: the big window, the overview")
do
	view.tabs.overview:Click()
	check(st.tab == "overview" and view.list.scroll:IsShown() and not view.g.frame:IsShown() and M.db.browser.tab == "overview",
		"the overview's tab (kept)")
	check(listOutline() == "#In progress 103 #Available now 104 110 #Coming up 111 #Blocked 105 106 108 #Completed",
		"in groups, the done ones folded, got " .. listOutline())
	check(plain(listRow(105).Right:GetText()) == "needs Investigate Echo Ridge" and plain(listRow(111).Right:GetText()) == "from level 7"
		and plain(listRow(104).Right:GetText()) == "Marshal Dughan" and plain(listRow("z:1429:b:available").Right:GetText()) == "2",
		"what blocks it, the level it needs, the giver; how many")
	check(plain(listRow(104).Name:GetText()) == "[4] Brotherhood of Thieves" and listRow(103).Picked:IsShown(), "level and title; the quest picked marked")
	listRow("z:1429:b:done"):Click()
	check(listOutline():find("#Completed 101 102", 1, true), "the done ones open")
	listRow(111):Click()
	check(st.picked == 111 and plain(view.d.Title:GetText()) == "[9] Princess Must Die", "a click: the details")
end

section("Questtree: the big window, the zone map")
do
	view.tabs.map:Click()
	local m = view.mapPane.map
	check(st.tab == "map" and view.mapPane:IsShown() and m.frame:IsShown() and m.map == ELWYNN and m.shown == 6,
		"the map's tab: the zone's givers, turn-ins and drop areas, got " .. m.shown)
	local function marker(label)
		for i = 1, m.shown do
			if m.markers[i].spots[1].label:find(label, 1, true) then return m.markers[i] end
		end
	end
	local dughan, willem, remy, wolf = marker("Marshal Dughan"), marker("Deputy Willem"), marker("Remy"), marker("drops here (12%)")
	check(dughan and dughan.look == "available" and dughan.Icon.atlas == "QuestNormal" and not dughan.Icon.desaturated and dughan.Back:IsShown()
		and dughan.Icon.width == 24, "a giver with a quest for me now: a bright ! on a dark disc, full size")
	check(#dughan.quests == 2 and dughan.quests[1] == 104 and dughan.quests[2] == 101, "... and the done one there, the one to do first first")
	check(willem and willem.look == "active" and willem.Icon.atlas == "QuestTurnin", "the turn-in of a quest in my log: a ?")
	check(remy and remy.look == "level" and remy.Icon.desaturated and remy.Icon.width == 18, "later ones: a smaller grey !")
	check(wolf and wolf.look == "drop" and wolf.Icon.path == "Interface\\CharacterFrame\\TempPortraitAlphaMask", "where an item drops: a soft circle")
	check(m.You:IsShown(), "me on the map")
	dughan._scripts.OnEnter(dughan)
	check(TOOLTIP.title == "Marshal Dughan" and plain(TOOLTIP.lines[1]) == "  [4] Brotherhood of Thieves" and plain(TOOLTIP.lines[2]) == "  [1] A Threat Within"
		and TOOLTIP.lines[3] == "Click: show Brotherhood of Thieves", "its tooltip: the giver and each quest")
	dughan:Click()
	check(st.picked == 104 and dughan.Ring:IsShown() and plain(view.d.Title:GetText()) == "[4] Brotherhood of Thieves", "a click: that quest, its marker ringed")
	dughan:Click()
	check(st.picked == 101, "again: the next one there")
	local px = dughan.px
	m.frame._scripts.OnMouseWheel(m.frame, 1)
	check(m.zoom == 1.35 and math.abs(marker("Marshal Dughan").px - px * 1.35) < 0.01 and plain(view.ZoomText:GetText()) == "135%",
		"the wheel zooms in")
	view.ZoomButtons.fit:Click()
	check(m.zoom == 1, "Fit: the whole zone")
	view.filters.onlyAvailable:Click()
	check(m.shown == 4, "the filters too (only the ones I can take: two givers, two drop areas), got " .. m.shown)
	view.filters.onlyAvailable:Click()
	zoneRow("d:The Deadmines"):Click()
	check(not m.frame:IsShown() and plain(view.mapPane.Note:GetText()):find("Dungeon quests", 1, true), "a dungeon: no map, says why")
	zoneRow("z:1429"):Click()
	view.tabs.chains:Click()
	check(st.tab == "chains" and view.g.frame:IsShown(), "back to the chains")
end

section("Questtree: the big window, the search")
do
	view.Box:SetText("echo")
	check(view.Clear:IsShown() and st.query == "", "typing: not searched yet")
	Wait(0.5)
	check(st.query == "echo" and listOutline() == "#Search results 103 105" and plain(view.Head:GetText()) == "Search results"
		and listRow("search").Right:GetText() == "2" and not view.g.frame:IsShown(), "searched after a moment: the results replace the chains, got " .. listOutline())
	check(plain(listRow(105).Right:GetText()) == "Elwynn Forest", "a result says its zone")
	listRow(105):Click()
	check(st.drilled and st.picked == 105 and view.Box:GetText() == "echo" and view.g.frame:IsShown() and view.Back:IsShown(),
		"a result clicked: its zone's chains, a way back, the search stays")
	check(plain(view.Back.Text:GetText()) == "Back to the search results", "the way back says so")
	view.Back:Click()
	check(not st.drilled and listOutline() == "#Search results 103 105" and not view.Back:IsShown(), "back: the results")
	zoneRow("z:1436"):Click()
	check(st.drilled and st.where == "z:1436" and view.Back:IsShown(), "a zone clicked during a search: there, inside the search")
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
	check(st.query == "" and not view.Clear:IsShown() and not view.Back:IsShown() and st.where == "z:1436" and view.g.frame:IsShown(),
		"cleared: the chains, where I was")
	view.Box:SetText("militia")
	Q.ToggleBrowser()
	Wait(0.5)
	check(st.query == "" and win:GetScript("OnUpdate") == nil, "closed right after typing: nothing runs")
	Q.ToggleBrowser()
	Wait(0.1)
	check(st.query == "militia" and listOutline() == "#Search results 201", "opened again: searched then")
	view.Clear:Click()
end

section("Questtree: the big window, quests changing")
do
	Q.OpenBrowser(103)
	check(st.where == "z:1436" and st.picked == 103 and card(103):IsShown(), "a quest in the chains shown (Westfall's): it stays there")
	zoneRow("z:1429"):Click()
	local draws, built = st.draws, st.layouts_built
	STATUS_OF[103] = "done"
	STATUS_OF[105] = "available"
	Fire("QUEST_TURNED_IN", 103, 100, 0)
	Fire("QUEST_ACCEPTED", 105)
	check(st.draws == draws and not card(103).Check:IsShown(), "not in the event: nothing drawn yet")
	Wait(0.5)
	check(st.draws == draws + 1 and st.layouts_built == built + 1, "the next frame: drawn once for both, got " .. (st.draws - draws))
	check(card(103).Check:IsShown() and card(105).Strip.color[1] == 0.85 and plain(zoneRow("z:1429").Count:GetText()) == "3 of 9"
		and plain(bannerFrame(lay().banners[1].key).Count:GetText()) == "3 of 8 steps done" and segsOf(103, 105)[1].tone == 1,
		"the cards, the zone's count, the banner and the lines follow")
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
	check(plain(zoneRow("z:1429").Count:GetText()) == "4 of 9" and card(104).Check:IsShown(), "opened again: the counts and statuses of now")

	-- The client's title coming in later: the cards in sight follow.
	local asked = {}
	C_QuestLog.RequestLoadQuestByID = function(id) asked[#asked + 1] = id end
	st.asked[111] = nil
	Q.ToggleBrowser(); Q.ToggleBrowser()
	Q.ToggleBrowser(); Q.ToggleBrowser()
	local times = 0
	for _, id in ipairs(asked) do times = times + (id == 111 and 1 or 0) end
	check(times == 1, "a title the client doesn't know: asked for, once, got " .. times)
	QUESTS = { { id = 111, title = "Prinzessin muss sterben", objectives = {} } }
	Fire("QUEST_DATA_LOAD_RESULT", 111, true)
	Wait(0.5)
	check(card(111).Title:GetText() == "Prinzessin muss sterben", "it came: the card shows it")
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
	check(st.trees_built == built and not item(113), "in the callback: nothing drawn")
	Wait(0.5)
	check(st.trees_built == built + 1 and item(113) and graphOutline():find("# 110 113 111", 1, true), "the next frame: worked out again, got " .. graphOutline())
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
	table.insert(ZONES, 3, { map = STV, name = "Stranglethorn Vale", continent = EK, minLevel = 30, maxLevel = 45 })
	local _, _, _, changed = Q.BrowserView()
	changed()
	Wait(0.5)
	zoneRow("z:1434"):Click()
	local g = view.g
	local near = 0
	for _ in pairs(g.cards) do near = near + 1 end
	check(#lay().cards == 400 and near < 60 and g.made < 80, "400 quests: only the cards near sight exist, got " .. near .. " (made " .. g.made .. ")")
	check(g.VThumb:IsShown() and not g.HThumb:IsShown(), "a bar says where it's scrolled")
	local statuses = calls.Status
	local lays = g.lays
	local id = list[3 * 3 + 1]
	local kept = g.cards[id]
	g.frame._scripts.OnMouseWheel(g.frame, -1)
	check(g.sy == 78 and g.lays == lays + 1, "the wheel scrolls a stage down")
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
	check(g.sy == 178 and g.frame:GetScript("OnUpdate") == nil, "dragged 100 down: 100 further, got " .. g.sy)
	-- The controller's cursor on a card below sight: it comes into view.
	local before = g.sy
	local below
	for qid, c in pairs(g.cards) do
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
	view.ZoomButtons.minus:Click()
	view.ZoomButtons.minus:Click()
	view.ZoomButtons.minus:Click()
	view.ZoomButtons.minus:Click()
	view.ZoomButtons.minus:Click()
	check(g.zoom == 0.5, "down to half")
	view.ZoomButtons.fit:Click()
	check(g.zoom == 1, "Fit: as much as fits (the width here)")
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
	check(math.abs(win:GetScale() - (1024 - 40) / 1320) < 1e-6, "a small screen: scaled to fit, got " .. win:GetScale())
	GetScreenWidth, GetScreenHeight = width, height
	Q.ToggleBrowser()
	Q.ToggleBrowser()
	check(win:GetScale() == 1, "a big one: full size")
	local buttons = true
	for _, list in ipairs({ view.zones.rows, view.list.rows, view.d.links, view.d.places, view.g.cards, view.g.banners, view.tabs, view.filters,
		view.ZoomButtons, view.mapPane.map.markers, view.d.map.markers }) do
		for _, b in pairs(list) do buttons = buttons and b._kind == "Button" end
	end
	check(buttons and view.d.Small._kind == "Button" and view.Clear._kind == "Button" and view.Back._kind == "Button",
		"every card, marker, row, tab, filter and link is a button the controller reaches")
	check(view.g.frame:GetScript("OnMouseDown") == nil and view.g.frame:GetScript("OnMouseUp") == nil,
		"the canvas itself isn't one (no mouse down or up script)")
	local blizzard = false
	for _, f in ipairs({ win, view.root, view.zones.scroll, view.list.scroll, view.d.Scroll, view.g.frame, view.g.canvas }) do
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
MAP_NAMES[DUROTAR], MAP_NAMES[STV] = nil, nil
QUESTS = questLogBefore
Wait(math.ceil(waited) - waited + 1)
