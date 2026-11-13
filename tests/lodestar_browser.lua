-- Lodestar: the big window (Browser.lua), against a small made-up world. The data and engine (Q.Load,
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
-- with the done ones, reasons; a dungeon's Zone tab), the switch Map | Chain over the middle (greyed
-- when no chain applies, saying why; one click each way; its label following the quest picked; cut
-- short beside the way back to the results), the chain badges on the rows ("2/4": the chain opened,
-- the quest picked, its card in sight; the rows' tooltips; Q.OpenChain), the search, the views other files register
-- (lazily built, shown, hidden, refreshed, Q.ShowBrowserView, Q.SelectZone, Q.OpenBrowser from one,
-- one that fails), events and data changes redrawn on the next frame only while it's open (my
-- progress in the quest log, items the client learns), a small screen, the controller's buttons.
-- Round 6: this round's shared contract (Q.Tier, Q.TierColor, Q.TierCode, Q.TIER_WORD, Q.Group,
-- Q.MobLevels, Q.ForMyLevel, Q.IsHard, Q.StatusRank, Q.Compare: Data.lua and Engine.lua make them in
-- parallel) as stand-ins with its meaning; "Current zone" and the left's alphabetical order (German
-- names too), how hard (counts apart, hard ones after the fitting ones and marked, the pins' orange
-- ring, red only with all levels, without the contract), the order everywhere (chain cards, what's
-- next, the quest list, the briefing, the search; without Q.Compare the same), the clicks on quest rows
-- (the map; right-click: the chain).
-- Needs: no other file.
local suite = ...
local check, section, ns, LT = suite.check, suite.section, suite.ns, suite.LT
local Q = ns.Lodestar

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

-- This round's shared contract (Data.lua and Engine.lua make it in parallel: stand-ins with its meaning
-- here): a quest's tier for me (TIER: "difficult" for HARD ones, "trivial" for TRIVIAL, "impossible"
-- for FAR, else "fair"), its colour, its mobs' levels (MOBS), a group quest (GROUP), for my level (in
-- my log, or to take now and easy or fair), hard (to take now, within my levels, difficult), the one
-- order of quests (Q.Compare: ready, in my log, for my level, hard, other ones to take, coming up,
-- blocked, done, not for me; then the effective level, no level last; the client's title; the ID).
local HARD, MOBS, GROUP = {}, {}, {}
local TIER_RGB = { trivial = { 0.5, 0.5, 0.5 }, easy = { 0.25, 0.75, 0.25 }, fair = { 1, 0.82, 0 }, difficult = { 1, 0.5, 0.25 },
	impossible = { 1, 0.1, 0.1 } }
local function TierOf(id)
	return HARD[id] and "difficult" or TRIVIAL[id] and "trivial" or FAR[id] and "impossible" or "fair"
end
local function StatusOfStub(id) return STATUS_OF[id] or "available" end
local function InRangeOf(id) -- (this round's: in my log, or from my level on, not grey, at most 4 above me)
	local q = QUESTS_DATA[id]
	local my = UnitLevel("player")
	return STATUS_OF[id] == "active" or not (TRIVIAL[id] or FAR[id] or (q and q.minLevel and q.minLevel > my) or (q and q.level and q.level > my + 4))
end
local function ForMyLevelOf(id)
	local s, t = StatusOfStub(id), TierOf(id)
	return s == "active" or (s == "available" and InRangeOf(id) and (t == "easy" or t == "fair"))
end
local function IsHardOf(id) return StatusOfStub(id) == "available" and InRangeOf(id) and TierOf(id) == "difficult" end
local RANK_OF = { level = 6, locked = 7, done = 8, other = 9 }
local function RankOf(id)
	local s = StatusOfStub(id)
	if s == "active" then return C_QuestLog.IsComplete(id) and 1 or 2 end
	if s == "available" then return ForMyLevelOf(id) and 3 or IsHardOf(id) and 4 or 5 end
	return RANK_OF[s] or 9
end
local function EffectiveLevel(id)
	local q = QUESTS_DATA[id]
	local level = q and q.level
	if not level or level <= 0 then return math.huge end
	return math.max(level, MOBS[id] and MOBS[id][2] or 0)
end
local compares = 0
local function CompareOf(a, b)
	compares = compares + 1
	local ra, rb = RankOf(a), RankOf(b)
	if ra ~= rb then return ra < rb end
	local la, lb = EffectiveLevel(a), EffectiveLevel(b)
	if la ~= lb then return la < lb end
	local ta = (C_QuestLog.GetTitleForQuestID(a) or (QUESTS_DATA[a] and QUESTS_DATA[a].title) or ""):lower()
	local tb = (C_QuestLog.GetTitleForQuestID(b) or (QUESTS_DATA[b] and QUESTS_DATA[b].title) or ""):lower()
	if ta ~= tb then return ta < tb end
	return a < b
end
local function CodeOf(tier)
	local c = TIER_RGB[tier]
	return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
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
	InRange = InRangeOf,
	Tier = TierOf,
	TierColor = function(tier) local c = TIER_RGB[tier]; return c and { r = c[1], g = c[2], b = c[3] } or nil end,
	TierCode = function(id) return QUESTS_DATA[id] and CodeOf(TierOf(id)) or nil end,
	TIER_WORD = { trivial = "Trivial", easy = "Easy", fair = "Fair", difficult = "Hard", impossible = "Too hard" },
	Group = function(id) return GROUP[id] == true end,
	MobLevels = function(id) local m = MOBS[id]; if m then return m[1], m[2] end end,
	ForMyLevel = ForMyLevelOf,
	IsHard = IsHardOf,
	StatusRank = RankOf,
	Compare = CompareOf,
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
-- Round 7's plan (Plan.lua makes it in parallel): missing until its sections (no "+" buttons, nothing of
-- it on the map), then stand-ins of the shared contract there; Plan.lua's own put back at the end.
local PLAN_KEYS = { "PlanList", "PlanHas", "PlanAdd", "PlanRemove", "PlanToggle", "PlanMove", "PlanClear", "PlanRev", "PlanStops", "PlanNext",
	"OnPlanChanged" }
local planSaved = {}
for _, key in ipairs(PLAN_KEYS) do
	planSaved[key] = Q[key] or false
	Q[key] = nil
end
local M = LT:GetModule("lodestar")
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

section("Lodestar: the big window without the data")
do
	Q.OpenBrowser()
	refs()
	check(win == LefthyToolsLodestarBrowser and win:IsShown() and win.TitleContainer.TitleText:GetText() == "Lodestar",
		"it opens, called Lodestar (never translated)")
	check(view.Empty:IsShown() and not view.root:IsShown() and not view.Box:IsShown() and not view.filters.allLevels:IsShown()
		and plain(view.Empty:GetText()):find("LefthyTools_QuestData", 1, true),
		"no data addon: a line saying so, no panes, no search, no filters")
	check(#dataCallbacks == 1 or st.listening, "it listens for data changes")
	local found
	for _, name in ipairs(UISpecialFrames) do found = found or name == "LefthyToolsLodestarBrowser" end
	check(found, "Escape closes it (UISpecialFrames)")
	Q.ToggleBrowser()
	check(not win:IsShown(), "toggled: closed")
end

section("Lodestar: the big window, zones on the left")
do
	loaded = true
	Q.ToggleBrowser()
	check(win:IsShown() and view.root:IsShown() and not view.Empty:IsShown() and view.Box:IsShown(), "with the data: the panes")
	check(win:GetWidth() == 1700 and win:GetHeight() == 868 and view.W == 1700 and win:GetScale() == 1,
		"a big screen (1920 x 1080): wider (1700), as high as the map needs (868), not scaled, got " .. win:GetWidth() .. " x " .. win:GetHeight())
	check(zonesOutline() == "#Eastern Kingdoms, Elwynn Forest, Redridge Mountains, Westfall, #Kalimdor, Durotar, #Dungeons, The Deadmines",
		"by continent, each one's zones alphabetical, then the dungeons, got: " .. zonesOutline())
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

section("Lodestar: the big window, the tab bar")
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

section("Lodestar: the big window, the zone page's map")
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
	check(wolf and wolf.drop and wolf.look ~= "drop" and wolf.Icon.path ~= "Interface\\CharacterFrame\\TempPortraitAlphaMask" and not wolf.Badge:IsShown()
		and wolf.dropRing and wolf.dropRing[1]:IsShown() and wolf.dropRing[33]:IsShown() and wolf.dropRing[33].thickness == 1.5,
		"where an item that starts a quest drops: its quest's own pin, its area a thin light ring on a dark edge")
	-- Its quest done: the dim dot, the ring only while hovered (it drops once).
	local fangWas = STATUS_OF[110]
	STATUS_OF[110] = "done"
	Q.ToggleBrowser(); Q.ToggleBrowser()
	wolf = marker("drops here (12%)")
	check(wolf and wolf.look == "done" and not wolf.dropRing[1]:IsShown(), "its quest done: a dim dot, no ring")
	wolf._scripts.OnEnter(wolf)
	check(wolf.dropRing[1]:IsShown(), "hovered: its ring")
	wolf._scripts.OnLeave(wolf)
	check(not wolf.dropRing[1]:IsShown(), "left: gone")
	STATUS_OF[110] = fangWas
	Q.ToggleBrowser(); Q.ToggleBrowser()
	wolf = marker("drops here (12%)")
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
	dughan._mouse = true
	Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
	dughan._mouse = nil
	check(list:IsShown(), "a click on its pin: it stays (the pin's own click closes it)")
	Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
	check(not list:IsShown(), "a click anywhere else (the map too): closed")
	dughan:Click()
	list.rows[2]:Click()
	check(st.picked == 104 and not list:IsShown() and dughan.Ring:IsShown() and plain(view.d.Title:GetText()) == "[4] Brotherhood of Thieves"
		and view.d.Panel:IsShown() and not view.b.Scroll:IsShown(), "a quest of the list clicked: picked, its pin ringed, its details on the right")
	-- The quest picked on the map: its objectives' areas (blue, as the game's), its turn-in, the way between.
	local color = m.lines[1].color
	check(m.lines[1]:IsShown() and m.lines[2]:IsShown(), "its chain picked: its thread shows")
	local done = m.lines[1].done and m.lines[1] or m.lines[2]
	local open = m.lines[1].done and m.lines[2] or m.lines[1]
	check(math.abs(done.color[4] - 0.25 * 0.6) < 1e-9 and math.abs(open.color[4] - 0.7 * 0.6) < 1e-9 and open.thickness == 2,
		"a done step's thread fainter; both fainter while the quest's own way shows, got " .. done.color[4] .. ", " .. open.color[4])
	local a = m.areas[1]
	check(m.areasShown == 1 and a.spec.objective == 1 and a.spec.label == "Use Wanted Poster" and a.Fill:IsShown() and a.Glow.blend == "ADD"
		and a.Fill.vertex[1] == 0.35 and a.Fill.vertex[3] == 1 and a.Fill.vertex[4] == 0.22 and a.Button._kind == "Button",
		"its objective's area: a soft blue circle (as the game's quest areas), a button at its middle")
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
	-- Zoomed in on a corner, a quest picked with nothing of it in sight: the map goes to it.
	CURSOR.x, CURSOR.y = 4, -4
	for _ = 1, 4 do m.frame._scripts.OnMouseWheel(m.frame, 1) end
	local function seen(x, y)
		local sx, sy = m.ox + x * m.artW, m.oy + y * m.artH
		return sx >= 0 and sx <= m.width and sy >= 0 and sy <= m.height
	end
	check(m.zoom > 3 and not seen(0.48, 0.42) and not seen(0.4, 0.5), "zoomed in on the map's corner")
	Q.OpenBrowser(103)
	check(st.picked == 103 and m.zoom > 3 and seen(0.48, 0.42) and seen(0.56, 0.46), "a quest picked out of sight: the map goes to it (its turn-in, its areas)")
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
	check(plain(view.zp.Counts:GetText()) == "1 ready to turn in · 3 for your level" and view.zp.Hint:IsShown()
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

section("Lodestar: the big window, the zone's briefing")
do
	local b = view.b
	check(b.Scroll:IsShown() and not view.d.Panel:IsShown() and plain(b.Title:GetText()) == "Elwynn Forest"
		and plain(b.Sub:GetText()) == "Level 1-10 · Eastern Kingdoms" and plain(b.Count:GetText()) == "2 of 10 done" and b.BarBack:IsShown()
		and math.abs(b.Bar.width - b.BarBack.width * 2 / 10) < 0.01,
		"nothing picked: the zone's briefing on the right: its name, levels, continent, how far along with a bar")
	check(plain(b.Line:GetText()) == "3 for your level · 2 to pick up now",
		"what's for my level here (in my log, or to take now: not what needs another first), what I can take now, got " .. plain(b.Line:GetText()))
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
	check(plain(view.zp.Counts:GetText()) == "3 for your level" and not view.zp.Guide:IsShown(),
		"under the map one line: for my level (in my log or to take now; nothing ready, nothing hard), got " .. plain(view.zp.Counts:GetText()))
	-- Hovering a card: its pins and thread lit, the rest dim.
	local m = view.zp.map
	c._scripts.OnEnter(c)
	local lit, dim = marker("Marshal Dughan"), marker("drops here (12%)")
	local thread
	for i = 1, m.linesShown do if m.lines[i].key == CHAIN1 then thread = m.lines[i] end end
	check(lit:GetAlpha() == 1 and dim:GetAlpha() == 0.3 and thread.thickness == 3.5 and thread.color[4] == 1,
		"hovering a chain's card: its pins and thread light up, the others dim")
	check(TOOLTIP.title == "Elwynn's Kobolds" and TOOLTIP.lines[#TOOLTIP.lines - 1] == "Click: open the chain"
		and TOOLTIP.lines[#TOOLTIP.lines] == "Click the next step's line: show it on the map", "its tooltip: a click opens the chain (it's a chain, not a quest)")
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
	local kept = st.suggest
	view.zones:Lay()
	view.zp.Suggest:Click()
	check(st.where == "z:1433" and plain(b.Title:GetText()) == "Redridge Mountains" and zoneRow("z:1433").Picked:IsShown(),
		"a click: that zone")
	zoneRow("z:1436"):Click()
	check(st.suggest == kept, "the zone to go to is kept (worked out again after a status change)")
	-- A dungeon: no map; its Zone tab is its quest list, its briefing on the right.
	zoneRow("d:The Deadmines"):Click()
	check(not view.zp:IsShown() and view.list.scroll:IsShown() and view.head:IsShown() and view.head.Title:GetText() == "The Deadmines"
		and view.Legend:IsShown() and plain(view.Legend:GetText()):find("Dungeon quests", 1, true) and listOutline() == "#Coming up 301"
		and cardsOutline() == "d:The Deadmines:301" and plain(b.Sub:GetText()) == "Level 17-24 · Dungeon",
		"a dungeon: its quest list (no map), says why, its chain in its briefing, got " .. listOutline())
	zoneRow("z:1429"):Click()
	check(view.zp.map.frame:IsShown() and view.zp:IsShown() and not view.head:IsShown(), "back in Elwynn")
end

section("Lodestar: the big window, a chain opened")
do
	openChain(CHAIN1)
	check(st.chain == CHAIN1 and view.g.frame:IsShown() and not view.zp:IsShown() and view.tabs.zone.Line:IsShown(), "a click on its card: the chain's page")
	local h = view.head
	check(not h.Back and h.Title:GetText() == "Elwynn's Kobolds" and h.Dot:IsShown() and h.Dot.points[1][2] == 0
		and plain(h.Count:GetText()) == "2 of 9 steps done" and plain(h.Sub:GetText()) == "In your log: Investigate Echo Ridge",
		"its head: its colour, name, how far along, what's next (the way back is the switch's Map above it)")
	local sw = view.switch
	check(sw:IsShown() and sw.chain.on and not sw.map.on and sw.chain.Line:IsShown() and not sw.map.Line:IsShown()
		and plain(sw.chain.Text:GetText()) == "Chain: Elwynn's Kobolds" and sw.chain.Count:GetText() == "2/9",
		"the switch: Chain lit, its name and how far along")
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
	check(briefRows() == "101 102 107 103 104 105 106 108 201" and plain(br.rows[1].Text:GetText()) == "[1] A Threat Within"
		and plain(br.rows[1].Right:GetText()) == "Completed" and br.rows[1].Icon.atlas == "common-icon-checkmark"
		and plain(br.rows[5].Right:GetText()) == "Marshal Dughan" and plain(br.rows[6].Right:GetText()) == "Needs Investigate Echo Ridge",
		"its steps, each a row: done ones ticked, the giver for one I can take, else the reason, got " .. briefRows())
	check(br.rows[1].Badge:IsShown() and plain(br.rows[1].Badge.Text:GetText()) == "1/9" and plain(br.rows[6].Badge.Text:GetText()) == "6/9"
		and br.rows[6].Badge._kind == "Button" and br.rows[6].Badge._points[1][1] == "RIGHT"
		and br.rows[6].Badge._points[1][2] == -(br.rows[6].Right:GetStringWidth() + 12),
		"each step's badge says which (\"6/9\"), left of its reason, got " .. tostring(br.rows[1].Badge:IsShown()) .. " "
		.. plain(br.rows[1].Badge.Text:GetText()) .. " " .. plain(br.rows[6].Badge.Text:GetText()) .. " " .. tostring(br.rows[6].Badge._points[1][2]))
	check(plain(br.Friends:GetText()) == "Anna Brook  1 of 9\nBob  0 of 9", "friends on it, got " .. plain(br.Friends:GetText()))
	br.rows[6]:Click("RightButton")
	check(st.picked == 105 and st.chain == CHAIN1 and view.g.frame:IsShown() and plain(view.d.Back.Text:GetText()) == "Elwynn's Kobolds",
		"a step right-clicked (its chain): picked on the chain's page, the way back says the chain")
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
	check(done.Title:GetText():find("|cffffd100[1]|r", 1, true), "the level in its tier's colour (Q.TierCode)")
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
		and TOOLTIP.lines[#TOOLTIP.lines - 1] == "Click: details" and TOOLTIP.lines[#TOOLTIP.lines] == "Ctrl-click: show it on the map",
		"hovering: a tooltip (a click: its details; Ctrl-click: the map)")
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
	-- A step's row clicked: picked there (its details, the small map in them), the chain's page stays;
	-- Ctrl-click: the zone's map with it picked, never the chain's page; the switch goes back.
	br.rows[6]:Click()
	check(st.picked == 105 and st.chain == CHAIN1 and view.g.frame:IsShown() and not view.zp:IsShown() and view.d.Panel:IsShown()
		and view.d.map.frame:IsShown() and card(105).Glow:IsShown(), "a step clicked: its details with the small map, the chain's page stays, its card picked")
	unpick()
	STATE.ctrl = true
	view.b.rows[6]:Click()
	STATE.ctrl = false
	check(st.picked == 105 and st.chain == nil and view.zp:IsShown() and not view.g.frame:IsShown() and st.lastChain == CHAIN1
		and st.tab == "zone", "Ctrl-click: the zone's map with it picked (not the chain), the chain kept for the switch")
	view.switch.chain:Click()
	unpick()
	check(st.chain == CHAIN1 and view.g.frame:IsShown(), "the switch's Chain: back to it")
	-- Without Q.TierCode: Q.LevelColor's colour; without Q.ChainStep and it too: the chain's first title,
	-- the level against mine (19).
	Q.TierCode = nil
	Q.ToggleBrowser(); Q.ToggleBrowser()
	check(card(101).Title:GetText():find("|cff336699[1]|r", 1, true), "without Q.TierCode: Q.LevelColor's")
	Q.ChainStep, Q.LevelColor = nil, nil
	wipe(st.layouts)
	view.g.bucket = nil
	Q.ToggleBrowser(); Q.ToggleBrowser()
	check(st.chain == CHAIN1 and view.head.Title:GetText() == "A Threat Within" and card(101).Title:GetText():find("|cff808080[1]|r", 1, true),
		"without them: the first quest's title, level 1 grey (trivial at 19); opened again: still the chain")
	Q.ChainStep, Q.LevelColor, Q.TierCode = stand.ChainStep, stand.LevelColor, stand.TierCode
	Q.ToggleBrowser(); Q.ToggleBrowser()
end

section("Lodestar: the big window, why it's locked")
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
	view.switch.map:Click()
	check(st.chain == nil and view.zp:IsShown() and st.path == nil and view.zp.map.map == WESTFALL and st.picked == 201,
		"back: the zone's page, the quest still picked")
	zoneRow("z:1429"):Click()
end

section("Lodestar: the big window, the filters")
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
	view.switch.map:Click()
	view.filters.showOther:Click()
	openChain(SINGLES)
	check(graphOutline() == "110 111 112" and card(112):GetAlpha() == 0.55, "not for me: shown, dimmed (in Q.Compare's order: no chain to keep), got " .. graphOutline())
	view.filters.showOther:Click()
	check(graphOutline() == "110 111", "off: not shown, the quests without a chain every level too, got " .. graphOutline())
	view.switch.map:Click()
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
	view.switch.map:Click()
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

section("Lodestar: the big window, the details")
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
	check(plain(d.Title:GetText()) == "[5] Skirmish at Echo Ridge" and d.Title:GetText():find("|cffffd100", 1, true) and d.Title._points[1][2] == 40
		and sub == "Needs Investigate Echo Ridge" and d.Icon.atlas == "QuestNormal" and d.Icon.desaturated == true,
		"its icon, the title in its tier's colour beside it, one status line with the reason, got " .. sub)
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
	check(d.links[1].quest == 103 and d.links[2].quest == 104 and d.links[3].quest == 105 and not (d.links[4] and d.links[4]:IsShown())
		and plain(d.LeadsMore:GetText()) == "... and 2 more", "Leads to: at most three, in Q.Compare's order (in my log, to take, blocked; the done one last)")
	QUESTS_DATA[101].opens = opens
	card(105):Click()
	d.links[1]:Click("RightButton")
	check(st.picked == 103 and st.where == "z:1429" and st.chain == CHAIN1 and plain(d.Title:GetText()) == "[3] Investigate Echo Ridge" and card(103).Glow:IsShown(),
		"a link right-clicked (its chain), on the chain shown: picked there")
	check(not d.places[1]:IsShown() and plain(d.places[2].Text:GetText()) == "Deputy Willem · Elwynn Forest" and d.places[2].Icon.atlas == "QuestTurnin"
		and d.places[2].Icon.desaturated == true, "in my log: where it's turned in (a grey ?: not done yet)")
	-- Its objectives (Q.Objectives): what to do, where it drops; on the small map its areas, lit from its line.
	local o1, o2 = d.objectives[1], d.objectives[2]
	check(o1:IsShown() and o2:IsShown() and not (d.objectives[3] and d.objectives[3]:IsShown()) and plain(o1.Text:GetText()) == "Kill 10 x Kobold Vermin"
		and plain(o2.Text:GetText()) == "Collect 8 x Gold Dust\nfrom Kobold Miner, 32%" and o1.Icon.path == "Interface\\QuestFrame\\UI-Quest-BulletPoint"
		and o2:GetHeight() > o1:GetHeight() and o1._kind == "Button", "its objectives: each a line, where the item drops under it")
	local m = d.map
	local color = m.pick and m.pick.color
	check(m.frame:IsShown() and m.pick and m.pick.quest == 103 and m.areasShown == 3 and o1.Dot:IsShown() and o1.Dot.vertex[3] == 1
		and m.areas[1].Fill.vertex[3] == 1 and color, "the small map: its objectives' areas in blue, a dot on each line that has one")
	o2._scripts.OnEnter(o2)
	local tip = plain(table.concat(TOOLTIP.lines, "|"))
	check(tip == "Drops from Kobold Miner (32%) · Elwynn Forest|Drops from Old Chest (5%) · Westfall|Click: map pin there, and find it on the map"
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
	check(tip1 == "Elwynn Forest  42.0, 66.0|Starts at|Wanted Poster (an object) · Elwynn Forest|Click: map pin there, and find it on the map",
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
	view.switch.map:Click()
	unpick()
	openChain(SINGLES)
	card(110):Click()
	check(plain(d.places[1].Text:GetText()) == "Wolf Fang (an item)\nDrops from Young Wolf (12%) · Elwynn Forest" and d.places[1].Icon.path == "Interface\\Icons\\INV_Misc_Bag_10",
		"an item: the item, what drops it most often under it, got " .. plain(d.places[1].Text:GetText()))
	d.places[1]._scripts.OnEnter(d.places[1])
	check(plain(table.concat(TOOLTIP.lines, "|")):find("Drops from Timber Wolf (0.5%) · Elwynn Forest", 1, true), "the other drops: in its tooltip")
	d.places[1]._scripts.OnLeave(d.places[1])
	check(m.frame:IsShown() and m.map == ELWYNN and m.shown == 2 and m.markers[1].drop and m.markers[1].look == "start", "the small map: where it drops (the giver's pin)")
	check(plain(card(110).Info:GetText()) == "Wolf Fang" and card(110).Icon.path == "Interface\\Icons\\INV_Misc_Bag_10", "its card: the item")
	d.places[1]:Click()
	check(pins[5] and pins[5].x == 0.3, "a drop's line: a pin there")
	pins.off()
	view.switch.map:Click()
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
	view.switch.map:Click()
end

section("Lodestar: the big window, across zones")
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
	check(st.where == "z:1436" and st.picked == 301 and st.chain == "z:1436:301" and view.g.frame:IsShown(),
		"Needs first clicked on a chain's page: its details, the chain stays")
	card(202):Click()
	STATE.ctrl = true
	view.d.links[1]:Click()
	STATE.ctrl = false
	check(st.where == "z:1436" and st.picked == 301 and st.chain == nil and view.zp:IsShown(),
		"Needs first in a dungeon, given here, Ctrl-clicked: it stays, on this zone's map")
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
	check(o1.Dot:IsShown() and o1.Dot.vertex[1] == 0.35 and o1.Dot.vertex[3] == 1, "the details' objectives: a dot in the areas' blue")
	-- In my log, the game knowing its areas on this map: the game's own shape (a QuestPOIFrame over the
	-- map's art) instead of the circles, drawn again when zoomed; the buttons at their middles stay.
	local statusWas, questsWas, onMapWas = STATUS_OF[103], QUESTS, QUESTS_ON_MAP[1429]
	QUESTS_ON_MAP[1429] = { { 103, 0.5, 0.5 } }
	STATUS_OF[103] = "active"
	QUESTS = { { id = 103, title = "Investigate Echo Ridge", objectives = {} } }
	Fire("QUEST_LOG_UPDATE")
	Wait(1.1)
	Q.ShowOnMap(103)
	check(m.Blob and m.Blob:IsShown() and m.Blob.mapID == 1429 and m.Blob.blobs[1] == 103 and m.blob and not m.areas[1].Fill:IsShown()
		and not m.areas[1].Glow:IsShown() and m.areas[1].Button:IsShown(), "in my log: the game's own shape of its areas, no circles (their buttons stay)")
	m.Blob.blobs = {}
	m.buttons.plus:Click()
	check(m.Blob.blobs[1] == 103, "zoomed: drawn again (it fills the map's art)")
	QUESTS_ON_MAP[1429], STATUS_OF[103], QUESTS = onMapWas, statusWas, questsWas
	Fire("QUEST_LOG_UPDATE")
	Wait(1.1)
	Q.ShowOnMap(103)
	check(not m.Blob:IsShown() and m.areas[1].Fill:IsShown(), "not in my log: the circles again")
	o1._scripts.OnEnter(o1)
	check(m.areas[1].Fill.vertex[4] == 0.42 and m.areas[2].Fill.vertex[4] == 0.42 and m.areas[3].Fill.vertex[4] == 0.07,
		"an objective's line hovered: its areas lit on the zone's map, the others dim")
	o1._scripts.OnLeave(o1)
	check(m.areas[3].Fill.vertex[4] == 0.22, "left: as before")
end

section("Lodestar: the big window, the overview")
do
	view.tabs.overview:Click()
	check(st.tab == "overview" and view.list.scroll:IsShown() and not view.g.frame:IsShown() and not view.zp:IsShown() and M.db.browser.tab == "overview",
		"the quest list's tab (kept)")
	check(listOutline() == "#In progress 103 #Available now 110 104 #Blocked 105 106 108 #Completed +2",
		"in groups within my levels, the done ones folded, how many more, got " .. listOutline())
	check(plain(listRow("more").Name:GetText()) == "2 more outside your levels · Show all levels" and not listRow("more").Icon:IsShown(),
		"a quiet line at the end: how many the level filter left out")
	check(view.d.map.frame:IsShown(), "the details' small map: shown (the zone's map isn't in sight)")
	listRow("more"):Click()
	check(filters.allLevels and listOutline() == "#In progress 103 #Available now 110 104 107 #Coming up 111 #Blocked 105 106 108 #Completed",
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
	check(st.tab == "overview" and view.list.scroll:IsShown() and not view.zp:IsShown() and st.picked == 111
		and plain(view.d.Title:GetText()) == "[9] Princess Must Die" and view.d.map.frame:IsShown() and view.d.map.map == ELWYNN
		and listRow(111).Picked:IsShown(), "a row clicked: its details first (the small map in them), the quest list stays")
	listRow(111)._scripts.OnEnter(listRow(111))
	check(TOOLTIP.lines[#TOOLTIP.lines] == "Click: details · Ctrl-click: show it on the map", "its tooltip says so, got " .. tostring(TOOLTIP.lines[#TOOLTIP.lines]))
	listRow(111)._scripts.OnLeave(listRow(111))
	view.d.Show:Click()
	check(st.tab == "zone" and view.zp:IsShown() and st.picked == 111 and marker("Remy").Ring:IsShown(),
		"the details' Show on map (the controller's way): the Zone tab's map with it picked")
	view.tabs.overview:Click()
	STATE.ctrl = true
	listRow(111):Click()
	STATE.ctrl = false
	check(st.tab == "zone" and view.zp:IsShown() and st.picked == 111 and plain(view.d.Title:GetText()) == "[9] Princess Must Die"
		and marker("Remy").Ring:IsShown() and M.db.browser.tab == "zone", "a row Ctrl-clicked: the Zone tab's map with it picked (its pin ringed), its details")
	view.tabs.overview:Click()
	listRow(104):Click("RightButton")
	check(st.tab == "zone" and st.chain == CHAIN1 and st.picked == 104 and card(104).Glow:IsShown(), "a row right-clicked: its chain, the quest picked in it")
	view.tabs.overview:Click()
	listRow(110):Click("RightButton")
	check(st.tab == "zone" and st.chain == nil and view.zp:IsShown() and st.picked == 110, "one in no chain right-clicked: on the map")
	view.filters.allLevels:Click()
	view.tabs.zone:Click()
	check(st.tab == "zone" and view.zp:IsShown() and st.chain == nil, "the zone's tab: its page")
end

section("Lodestar: the big window, the switch Map | Chain")
do
	local sw = view.switch
	zoneRow("z:1429"):Click()
	local right = 0
	for _, tab in pairs(view.tabs) do
		if tab:IsShown() then right = math.max(right, tab._points[1][2] + tab:GetWidth()) end
	end
	local at = sw._points[1][2]
	check(sw:IsShown() and sw:GetParent() == view.tabBar and at == right + 4 + 12 and sw.map._kind == "Button" and sw.chain._kind == "Button",
		"on the Zone tab a switch of our own two buttons, right after the tabs, got x " .. tostring(at))
	check(plain(sw.map.Text:GetText()) == "Map" and sw.map.on and sw.map.Line:IsShown() and plain(sw.chain.Text:GetText()) == "Chain"
		and sw.chain.off and not sw.chain.on and sw.chain.Text.color[1] == 0.45 and sw.chain.Count:GetText() == "",
		"nothing picked: Map lit, Chain greyed")
	sw.chain._scripts.OnEnter(sw.chain)
	check(TOOLTIP.title == "Chain" and plain(TOOLTIP.lines[1]) == "Pick a quest of a chain (on the map or on the right): its chain opens here."
		and not sw.chain.Hover:IsShown(), "its tooltip says why (no hover light on a greyed half)")
	sw.chain._scripts.OnLeave(sw.chain)
	sw.chain:Click()
	check(st.chain == nil and view.zp:IsShown(), "a click on it: nothing")
	marker("drops here (12%)"):Click()
	check(st.picked == 110 and sw.chain.off and plain(sw.chain.Text:GetText()) == "Chain", "a quest in no chain picked: still greyed")
	sw.chain._scripts.OnEnter(sw.chain)
	check(plain(TOOLTIP.lines[1]) == "Wolves Across the Border is in no quest chain.", "it says so, got " .. plain(TOOLTIP.lines[1]))
	sw.chain._scripts.OnLeave(sw.chain)
	-- A quest of a chain picked: its chain offered, how far along.
	local trees, layouts = st.trees_built, st.layouts_built
	marker("Wanted Poster")._scripts.OnEnter(marker("Wanted Poster"))
	check(TOOLTIP.lines[#TOOLTIP.lines - 1] == "Then Chain above the map: its quest chain", "a pin of a chain's quest: its tooltip says where its chain is")
	marker("Wanted Poster")._scripts.OnLeave(marker("Wanted Poster"))
	marker("Wanted Poster"):Click()
	check(st.picked == 104 and not sw.chain.off and not sw.chain.on and sw.map.on and plain(sw.chain.Text:GetText()) == "Chain: Elwynn's Kobolds"
		and sw.chain.Count:GetText() == "2/9" and sw.chain.Text.color[1] == 0.8, "picked: Chain offers its chain and how far along")
	check(st.trees_built == trees and st.layouts_built == layouts, "nothing worked out again for it (kept)")
	sw.chain._scripts.OnEnter(sw.chain)
	check(TOOLTIP.title == "Elwynn's Kobolds" and TOOLTIP.lines[1] == "2 of 9 steps done" and TOOLTIP.lines[2] == "Click: open the chain"
		and sw.chain.Hover:IsShown(), "its tooltip, a hover light")
	sw.chain._scripts.OnLeave(sw.chain)
	sw.chain:Click()
	check(st.chain == CHAIN1 and view.g.frame:IsShown() and not view.zp:IsShown() and st.picked == 104 and card(104) and card(104).Glow:IsShown()
		and sw.chain.on and not sw.map.on and sw._points[1][2] == at, "one click: the chain, the quest picked in it; the switch where it was, Chain lit")
	local it = item(104)
	check(it.x * view.g.zoom >= view.g.sx * view.g.zoom - 1 and it.y >= view.g.sy and it.y + 48 <= view.g.sy + view.g.h / view.g.zoom,
		"its card in sight")
	sw.map._scripts.OnEnter(sw.map)
	check(TOOLTIP.title == "Elwynn Forest" and TOOLTIP.lines[1] == "Click: back to the map", "Map's tooltip")
	sw.map._scripts.OnLeave(sw.map)
	sw.map:Click()
	check(st.chain == nil and view.zp:IsShown() and st.picked == 104 and marker("Wanted Poster").Ring:IsShown() and sw.map.on and not sw.chain.on
		and plain(sw.chain.Text:GetText()) == "Chain: Elwynn's Kobolds", "and one click back: the map, the quest still picked")
	-- Another quest picked: the label follows.
	Q.OpenBrowser(301)
	check(st.where == "z:1436" and st.picked == 301 and plain(sw.chain.Text:GetText()) == "Chain: Red Silk Bandanas" and sw.chain.Count:GetText() == "0/2",
		"another quest picked: its chain's name, got " .. plain(sw.chain.Text:GetText()))
	Q.OpenBrowser(201)
	check(st.picked == 201 and plain(sw.chain.Text:GetText()) == "Chain: Elwynn's Kobolds", "and again")
	-- A chain opened from its card (nothing picked): Map and back to it, one click each.
	zoneRow("z:1429"):Click()
	openChain(CHAIN1)
	check(st.picked == nil and sw.chain.on and plain(sw.chain.Text:GetText()) == "Chain: Elwynn's Kobolds", "a chain's card: Chain lit")
	sw.map:Click()
	check(st.chain == nil and not sw.chain.off and plain(sw.chain.Text:GetText()) == "Chain: Elwynn's Kobolds", "Map: the chain left is still offered")
	sw.chain:Click()
	check(st.chain == CHAIN1 and view.g.frame:IsShown(), "and back to it")
	sw.map:Click()
	zoneRow("z:1436"):Click()
	check(sw.chain.off, "another zone: nothing offered (nothing picked there)")
	-- The quests without a chain opened: named as they are.
	zoneRow("z:1429"):Click()
	openChain(SINGLES)
	check(plain(sw.chain.Text:GetText()) == "Quests without a chain" and sw.chain.on, "the quests without a chain: their name")
	sw.map:Click()
	-- Only on the Zone tab; a dungeon's left half is its quest list.
	view.tabs.overview:Click()
	check(not sw:IsShown(), "not on the quest list")
	view.tabs.zone:Click()
	zoneRow("d:The Deadmines"):Click()
	check(sw:IsShown() and plain(sw.map.Text:GetText()) == "Quests" and sw.chain.off, "a dungeon: Quests | Chain")
	sw.map._scripts.OnEnter(sw.map)
	check(TOOLTIP.title == "The Deadmines" and TOOLTIP.lines[1] == "Shown now", "its tooltip")
	sw.map._scripts.OnLeave(sw.map)
	zoneRow("z:1429"):Click()
	-- A long name: the chain's half as wide as there's room for (beside the way back to the results too).
	local step = Q.ChainStep
	Q.ChainStep = function(id) local a, b = step(id); return a, b, a and string.rep("A very long chain name ", 12) end
	view.Box:SetText("echo")
	Wait(0.5)
	STATE.ctrl = true
	listRow(103):Click()
	STATE.ctrl = false
	check(view.Back:IsShown() and sw:IsShown() and sw._points[1][2] + sw:GetWidth() <= view.tabBar:GetWidth() - view.Back:GetWidth() - 8
		and sw.chain.Text.width < #sw.chain.Text:GetText() * 6, "a long name is cut short: the switch keeps beside the way back to the results")
	view.Clear:Click()
	Q.ChainStep = step
	unpick()
end

section("Lodestar: the big window, chain badges")
do
	view.tabs.overview:Click()
	local row, plainRow = listRow(104), listRow(110)
	check(row.Badge:IsShown() and plain(row.Badge.Text:GetText()) == "5/9" and row.Badge._kind == "Button" and not plainRow.Badge:IsShown()
		and row.Badge._points[1][2] == -168, "the quest list: a quest of a chain has its badge (its step, as the details count it), left of the giver; one in none hasn't")
	check(row.Name._points[2][2] == -170 - row.Badge:GetWidth() - 6 and plainRow.Name._points[2][2] == -170, "the title leaves it room")
	row._scripts.OnEnter(row)
	check(TOOLTIP.lines[#TOOLTIP.lines - 1] == "Click: details · Ctrl-click: show it on the map · Right-click: its chain"
		and TOOLTIP.lines[#TOOLTIP.lines] == "Click 5/9: open the chain",
		"the row's tooltip says what each click does, got " .. tostring(TOOLTIP.lines[#TOOLTIP.lines - 1]))
	plainRow._scripts.OnEnter(plainRow)
	check(TOOLTIP.lines[#TOOLTIP.lines] == "Click: details · Ctrl-click: show it on the map", "one in no chain: no chain")
	plainRow._scripts.OnLeave(plainRow)
	row._scripts.OnLeave(row)
	row.Badge._scripts.OnEnter(row.Badge)
	check(TOOLTIP.title == "Elwynn's Kobolds" and TOOLTIP.lines[1] == "Step 5 of 9" and TOOLTIP.lines[2] == "Click: open the chain",
		"the badge's own tooltip")
	row.Badge._scripts.OnLeave(row.Badge)
	plainRow:Click()
	check(st.tab == "overview" and st.picked == 110 and view.d.Panel:IsShown(), "a click on a row elsewhere: its details")
	STATE.ctrl = true
	plainRow:Click()
	STATE.ctrl = false
	check(st.tab == "zone" and st.picked == 110 and view.zp:IsShown(), "Ctrl-click on a row elsewhere: the map with it picked")
	view.tabs.overview:Click()
	row = listRow(104)
	row.Badge:Click()
	check(st.tab == "zone" and st.chain == CHAIN1 and view.g.frame:IsShown() and st.picked == 104 and card(104).Glow:IsShown()
		and view.switch.chain.on and M.db.browser.tab == "zone", "the badge clicked: the chain in the middle on the Zone tab, the quest picked")
	-- The right pane's rows: in progress here (and the chain's steps).
	view.switch.map:Click()
	unpick()
	local b = view.b.rows[1]
	check(b.quest == 103 and b.Sub:IsShown() and b.Badge:IsShown() and plain(b.Badge.Text:GetText()) == "4/9" and b.Badge._points[1][1] == "TOPRIGHT",
		"in progress here: its badge at the right of its title line")
	b._scripts.OnEnter(b)
	check(TOOLTIP.lines[#TOOLTIP.lines] == "Click 4/9: open the chain", "its tooltip")
	b._scripts.OnLeave(b)
	b.Badge:Click()
	check(st.chain == CHAIN1 and st.picked == 103 and card(103).Glow:IsShown(), "clicked: its chain, the quest picked")
	unpick()
	local step = view.b.rows[8]
	check(step.quest == 108 and plain(step.Badge.Text:GetText()) == "8/9", "the chain's steps")
	step.Badge:Click()
	check(st.chain == CHAIN1 and st.picked == 108 and card(108).Glow:IsShown(), "a step's badge: picked on the chain shown")
	unpick()
	view.b.rows[9].Badge:Click()
	check(st.where == "z:1436" and st.chain == "z:1436:101" and st.picked == 201, "a step elsewhere: its place, the chain there")
	-- Q.OpenChain (other files: My quests' badges).
	Q.ToggleBrowser()
	check(Q.OpenChain(105) == true and win:IsShown() and st.where == "z:1429" and st.tab == "zone" and st.chain == CHAIN1 and st.picked == 105
		and card(105) and card(105).Glow:IsShown(), "Q.OpenChain(id): the window opens on its zone, its chain shown, the quest picked")
	Q.ShowBrowserView("overview")
	check(Q.OpenChain(110) == false and st.picked == 110 and st.chain == nil, "a quest in no chain: opened as Q.OpenBrowser does, false")
	check(Q.OpenChain(424242) == false and Q.OpenChain(nil) == false, "an unknown quest: false")
	view.tabs.zone:Click()
	unpick()
end

section("Lodestar: the big window, the search")
do
	view.Box:SetText("echo")
	check(view.Clear:IsShown() and st.query == "", "typing: not searched yet")
	Wait(0.5)
	check(st.query == "echo" and listOutline() == "#Search results 103 105" and view.head.Title:GetText() == "Search results"
		and listRow("search").Right:GetText() == "2" and not view.zp:IsShown() and not view.tabs.zone.Line:IsShown(),
		"searched after a moment: the results replace the page, got " .. listOutline())
	check(plain(listRow(105).Right:GetText()) == "Elwynn Forest", "a result says its zone")
	listRow(105):Click()
	check(not st.drilled and st.picked == 105 and listOutline() == "#Search results 103 105" and view.d.Panel:IsShown() and view.d.map.frame:IsShown()
		and listRow(105).Picked:IsShown(), "a result clicked: its details (the small map), the results stay")
	STATE.ctrl = true
	listRow(105):Click()
	STATE.ctrl = false
	check(st.drilled and st.picked == 105 and st.chain == nil and view.Box:GetText() == "echo" and view.zp:IsShown() and view.Back:IsShown()
		and marker("Deputy Willem").Ring:IsShown(), "a result Ctrl-clicked: its zone's map, picked on it, a way back, the search stays")
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

section("Lodestar: the big window, views other files register")
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

section("Lodestar: the big window, quests changing")
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
	view.switch.map:Click()
	unpick()
	check(plain(chainCard(CHAIN1).Count:GetText()) == "3/9" and plain(chainCard(CHAIN1).Next:GetText()) == "Next: Brotherhood of Thieves · Marshal Dughan",
		"the zone page's card too: nothing in my log, the one to take first (for my level, the lowest level; not the grey lead-in), got "
		.. plain(chainCard(CHAIN1).Next:GetText()))

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
	view.switch.map:Click()
end

section("Lodestar: the big window, the data changing")
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

section("Lodestar: the big window, a big zone and the canvas")
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

section("Lodestar: the big window, a small screen and the controller")
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
	local badges = 0
	for _, list in ipairs({ view.list.rows, view.b.rows }) do
		for _, row in pairs(list) do
			buttons = buttons and row.Badge._kind == "Button" and row.Badge:GetParent() == row
			badges = badges + 1
		end
	end
	check(buttons and view.d.Small._kind == "Button" and view.d.Pin._kind == "Button" and view.d.Back._kind == "Button" and view.d.ChainBtn._kind == "Button"
		and view.Clear._kind == "Button" and view.Back._kind == "Button" and view.switch.map._kind == "Button" and view.switch.chain._kind == "Button"
		and view.zp.Suggest._kind == "Button" and badges > 0 and #view.d.objectives > 0 and #view.d.items > 0 and #m.areas > 0,
		"every card, pin, area, row, its chain badge, tab, the switch's halves, filter, link, reward, the map's zoom and the pane's buttons: buttons the controller reaches")
	check(view.g.frame:GetScript("OnMouseDown") == nil and view.g.frame:GetScript("OnMouseUp") == nil
		and m.frame:GetScript("OnMouseDown") == nil and m.frame:GetScript("OnMouseUp") == nil,
		"the canvas and the map themselves aren't (no mouse down or up script)")
	local blizzard = false
	for _, f in ipairs({ win, view.root, view.zones.scroll, view.list.scroll, view.b.Scroll, view.d.Scroll, view.g.frame, view.g.canvas, view.zp, m.frame }) do
		blizzard = blizzard or f.useCustomNavigation ~= nil or f.smartNavigationIgnored ~= nil
	end
	check(not blizzard, "nothing of Blizzard's on our frames")
	-- The controller's cursor on a pin out of sight: the map moves there.
	view.switch.map:Click()
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

section("Lodestar: the big window, Current zone and the left's order")
do
	local here = view.Here
	STATUS_OF[103], STATUS_OF[104], STATUS_OF[105] = "active", "available", "locked" -- (as the world began)
	Q.ToggleBrowser(); Q.ToggleBrowser()
	unpick()
	if st.chain then view.switch.map:Click() end
	check(here and here._kind == "Button" and here:IsShown() and plain(here.Text:GetText()) == "Current zone" and here._points[1][2] == view.Box,
		"\"Current zone\" beside the search: a button of ours")
	zoneRow("z:1436"):Click()
	here:Click()
	check(st.where == "z:1429" and st.picked == nil and view.zp:IsShown() and zoneRow("z:1429").Picked:IsShown(), "a click: the zone I'm in, its page")
	-- A city's floor (Stormwind City in Elwynn): walked up to the zone the left lists.
	PLAYER_MAP = 1453
	zoneRow("z:1436"):Click()
	zoneRow("c:1415"):Click()
	check(not zoneRow("z:1429"), "(its continent folded)")
	here._scripts.OnEnter(here)
	check(TOOLTIP.title == "Current zone" and TOOLTIP.lines[1] == "Elwynn Forest" and TOOLTIP.lines[2] == "Click: show Elwynn Forest",
		"its tooltip names it")
	here._scripts.OnLeave(here)
	here:Click()
	check(st.where == "z:1429" and zoneRow("z:1429") and zoneRow("z:1429").Picked:IsShown(), "from a city's floor: its zone, its continent opened")
	-- The quest list stays the quest list.
	view.tabs.overview:Click()
	zoneRow("z:1436"):Click()
	here:Click()
	check(st.tab == "overview" and st.where == "z:1429" and view.list.scroll:IsShown() and listOutline():find("^#In progress 103"),
		"on the quest list: the zone I'm in, its quest list")
	view.tabs.zone:Click()
	-- In a dungeon: the dungeon.
	INSTANCE = { name = "The Deadmines", type = "party" }
	here:Click()
	check(st.where == "d:The Deadmines", "in a dungeon: the dungeon")
	INSTANCE = nil
	-- Nowhere the left lists: greyed, its tooltip says so, a click does nothing.
	PLAYER_MAP = 1415
	Fire("ZONE_CHANGED_NEW_AREA")
	Wait(1.1)
	check(here.Text.color[1] == 0.5 and here.Icon.desaturated, "in none of the left's places: greyed (looked at after a zone change)")
	here._scripts.OnEnter(here)
	check(TOOLTIP.lines[1] == "You're in no zone with quests known.", "its tooltip says so")
	here._scripts.OnLeave(here)
	here:Click()
	check(st.where == "d:The Deadmines", "a click: nothing")
	PLAYER_MAP = 1429
	Fire("ZONE_CHANGED_NEW_AREA")
	Wait(1.1)
	check(here.Text.color[1] == 1, "back in Elwynn: there again")
	-- During a search: the zone, inside the search.
	view.Box:SetText("echo")
	Wait(0.5)
	here:Click()
	check(st.drilled and st.where == "z:1429" and view.zp:IsShown() and view.Back:IsShown(), "during a search: the zone, the search stays")
	view.Clear:Click()
	-- Not on another file's view; not without the data.
	Q.RegisterBrowserView("herev", "Here test", function(parent) return { frame = CreateFrame("Frame", nil, parent) } end)
	view.tabs.herev:Click()
	check(not here:IsShown(), "not on another file's view")
	view.tabs.zone:Click()
	check(here:IsShown(), "the zone's page: there")
	registry.byKey.herev = nil
	view.tabs.herev:Hide()
	view.tabs.herev = nil
	table.remove(registry.order)
	registry.current = nil
	loaded = false
	Q.ToggleBrowser(); Q.ToggleBrowser()
	check(not here:IsShown(), "without the data: not there")
	loaded = true
	Q.ToggleBrowser(); Q.ToggleBrowser()
	-- The left: each continent's zones alphabetical by the client's names, case-insensitive, an
	-- umlaut as its vowel (a German client: "Ödland" with the O's).
	local _, _, _, changed = Q.BrowserView()
	MAP_NAMES[ELWYNN], MAP_NAMES[WESTFALL], MAP_NAMES[REDRIDGE] = "Wald von Elwynn", "rotkammgebirge", "Ödland"
	changed()
	Wait(0.5)
	check(zonesOutline() == "#Eastern Kingdoms, Ödland, rotkammgebirge, Wald von Elwynn, #Kalimdor, Durotar, #Dungeons, The Deadmines",
		"the client's names, alphabetical (case and umlauts as they're read), got " .. zonesOutline())
	MAP_NAMES[ELWYNN], MAP_NAMES[WESTFALL], MAP_NAMES[REDRIDGE] = "Elwynn Forest", "Westfall", "Redridge Mountains"
	changed()
	Wait(0.5)
	check(zonesOutline():find("^#Eastern Kingdoms, Elwynn Forest, Redridge Mountains, Westfall"), "and back")
end

section("Lodestar: the big window, how hard (tiers)")
do
	local function again() Q.ToggleBrowser(); Q.ToggleBrowser() end
	HARD[110] = true
	again()
	unpick()
	local orange = CodeOf("difficult")
	check(plain(view.zp.Counts:GetText()) == "2 for your level · 1 hard" and view.zp.Counts:GetText():find(orange .. "1 hard|r", 1, true),
		"under the map: for my level (in my log or to take now, easy or fair) and apart the hard ones, in orange, got " .. plain(view.zp.Counts:GetText()))
	check(plain(view.b.Line:GetText()) == "2 for your level · 1 to pick up now · 1 hard", "the briefing too, got " .. plain(view.b.Line:GetText()))
	check(plain(chainCard(SINGLES).Next:GetText()) == "2 quests", "the quests without a chain: none for my level to pick up (the hard one isn't)")
	view.tabs.overview:Click()
	check(listOutline():find("#Available now 104 110 ", 1, true), "the quest list: the hard one after the one that fits (though lower), got " .. listOutline())
	local row = listRow(110)
	check(plain(row.Right:GetText()) == "Hard · Wolf Fang" and row.Right:GetText():find(orange .. "Hard|r", 1, true)
		and row.Name:GetText():find(orange .. "[2]|r", 1, true), "marked: \"Hard\" in orange at its right; its level in its tier's colour")
	check(plain(listRow(104).Right:GetText()) == "Marshal Dughan", "one that fits: not marked")
	-- What makes it hard: its mobs, a group quest; in its tooltip, its details, on its pin.
	HARD[110], HARD[104], MOBS[104], GROUP[104] = nil, true, { 6, 8 }, true
	again()
	row = listRow(104)
	row._scripts.OnEnter(row)
	local tip = table.concat(TOOLTIP.lines, "|")
	check(plain(tip):find("Level 4|Hard · Group quest · Mobs up to level 8|", 1, true), "its tooltip: hard, a group quest, its mobs higher, got " .. plain(tip))
	row._scripts.OnLeave(row)
	view.tabs.zone:Click()
	local poster, dughan, willem = marker("Wanted Poster"), marker("Marshal Dughan"), marker("Deputy Willem")
	check(poster.Edge:IsShown() and poster.Icon.atlas == "QuestDaily" and poster.Edge.vertex[1] == 1 and poster.Edge.vertex[2] == 0.5
		and dughan.Edge:IsShown() and not willem.Edge:IsShown(), "its pins: the game's icon (a repeatable one's), an orange ring around it")
	poster._scripts.OnEnter(poster)
	check(plain(TOOLTIP.lines[1]) == "  [4] Brotherhood of Thieves · repeatable · Hard · Group quest · Mobs up to level 8",
		"a pin's tooltip says it, got " .. plain(TOOLTIP.lines[1]))
	poster._scripts.OnLeave(poster)
	poster:Click()
	check(plain(view.d.Sub:GetText()) == "Available · Hard · Group quest · Mobs up to level 8 · New in WoW: Forever, Repeatable",
		"its details: on its status line, got " .. plain(view.d.Sub:GetText()))
	unpick()
	-- Red (too hard) only with all levels, in red.
	check(not marker("Remy"), "too hard (red): not by default")
	view.filters.allLevels:Click()
	-- On the map a "!" to pick up has its difficulty's colour (one I could take now far above me: red).
	local statusRemy = STATUS_OF[111]
	STATUS_OF[111] = "available"
	again()
	local remy = marker("Remy")
	check(remy and remy.look == "available" and remy.tier == "impossible" and remy.Icon.desaturated and remy.Icon.vertex[1] == 1
		and remy.Icon.vertex[2] < 0.2 and not remy.Edge:IsShown(), "on the map: its \"!\" in red, its difficulty's colour (no ring)")
	STATUS_OF[111] = statusRemy
	again()
	view.tabs.overview:Click()
	check(listRow(111) and listRow(111).Name:GetText():find(CodeOf("impossible") .. "[9]|r", 1, true), "with all levels: there, in red")
	view.filters.allLevels:Click()
	view.tabs.zone:Click()
	HARD[104], MOBS[104], GROUP[104] = nil, nil, nil
	-- Without this round's Q.Tier, Q.ForMyLevel, Q.IsHard, Q.TIER_WORD: the engine's difficulty (Q.Difficulty)
	-- and range; a hard one still apart.
	local saved2 = { Tier = Q.Tier, ForMyLevel = Q.ForMyLevel, IsHard = Q.IsHard, TIER_WORD = Q.TIER_WORD, Difficulty = Q.Difficulty }
	Q.Tier, Q.ForMyLevel, Q.IsHard, Q.TIER_WORD = nil, nil, nil, nil
	Q.Difficulty = function(id) return id == 110 and "difficult" or "fair" end
	again()
	check(plain(view.zp.Counts:GetText()) == "2 for your level · 1 hard" and plain(view.b.Line:GetText()) == "2 for your level · 1 to pick up now · 1 hard",
		"without them: Q.Difficulty's tier, the same counts, got " .. plain(view.zp.Counts:GetText()))
	for key, fn in pairs(saved2) do Q[key] = fn end
	again()
	check(plain(view.zp.Counts:GetText()) == "3 for your level", "back as it was")
end

section("Lodestar: the big window, the order everywhere")
do
	-- A zone of its own: chains in my log, for my level, hard, coming up.
	local function npc(id, name) return { kind = "npc", id = id, name = name, points = { at(STV, 0.1 + (id % 10) / 20, 0.5) } } end
	local made = {
		{ 601, "Fitting Start", 18, "available" }, { 602, "Fitting End", 19, "locked", { 601 } },
		{ 611, "Hard Start", 16, "available" }, { 612, "Hard End", 17, "locked", { 611 } },
		{ 621, "Logged Start", 20, "active" }, { 622, "Logged Middle", 21, "available" }, { 623, "Another Log", 16, "active" },
		{ 631, "Coming Start", 18, "locked" }, { 632, "Coming End", 20, "locked", { 631 } },
		{ 641, "Grey Lead", 10, "available" }, { 642, "Second Way", 17, "available" }, { 643, "First Way", 17, "available" },
	}
	local list = {}
	for _, m in ipairs(made) do
		QUESTS_DATA[m[1]] = { id = m[1], title = m[2], level = m[3], minLevel = m[3] - 3, zone = STV, pre = m[5], starts = { npc(m[1], "Giver " .. m[1]) } }
		STATUS_OF[m[1]] = m[4]
		list[#list + 1] = m[1]
	end
	HARD[611], TRIVIAL[641] = true, true
	ZONE_QUESTS[STV] = list
	local added = { { 601, 602 }, { 611, 612 }, { 621, 623, 622 }, { 631, 632 }, { 641, 642, 643 } }
	for _, c in ipairs(added) do CHAINS[#CHAINS + 1] = c end
	table.insert(ZONES, 4, { map = STV, name = "Stranglethorn Vale", continent = EK, minLevel = 15, maxLevel = 25 })
	local _, _, _, changed = Q.BrowserView()
	changed()
	Wait(0.5)
	zoneRow("z:1434"):Click()
	-- The chains' cards: in my log first, then a next step for my level, then a hard one, then the rest; by level.
	check(cardsOutline() == "z:1434:621 z:1434:641 z:1434:601 z:1434:611 z:1434:631",
		"chains in my log, for my level (the lowest next step first), hard, the rest, got " .. cardsOutline())
	check(plain(chainCard("z:1434:621").Next:GetText()) == "In your log: Another Log", "in my log: the first of them in the order (the lower one)")
	check(plain(chainCard("z:1434:641").Next:GetText()) == "Next: First Way · Giver 643",
		"to take: the one for my level first (not the grey lead-in), same level: by title, got " .. plain(chainCard("z:1434:641").Next:GetText()))
	local hardNext = chainCard("z:1434:611").Next:GetText()
	check(plain(hardNext) == "Next: Hard Start · Giver 611 · Hard" and hardNext:find(CodeOf("difficult") .. "Hard|r", 1, true), "a hard next step: marked")
	check(plain(chainCard("z:1434:631").Next:GetText()) == "Coming up: Coming Start", "the rest: what comes up")
	-- The briefing's lists, the quest list's sections, the search: Q.Compare's order.
	check(briefRows() == "623 621", "in progress here: the lowest level first, got " .. briefRows())
	local function outlines()
		view.tabs.overview:Click()
		local o = listOutline()
		view.tabs.zone:Click()
		return o
	end
	local expected = "#In progress 623 621 #Available now 643 642 601 622 611 #Blocked 612 631 602 632 +1"
	check(outlines() == expected, "the quest list: each section in the order (for my level, then the hard one; by level, then title), got " .. outlines())
	view.Box:SetText("start")
	Wait(0.5)
	check(listOutline() == "#Search results 621 601 611 631", "the search's results: in the order, got " .. listOutline())
	view.Clear:Click()
	-- Without Q.Compare and Q.StatusRank: the same order, worked out here.
	Q.Compare, Q.StatusRank = nil, nil
	compares = 0
	Q.ToggleBrowser(); Q.ToggleBrowser()
	check(outlines() == expected and cardsOutline() == "z:1434:621 z:1434:641 z:1434:601 z:1434:611 z:1434:631" and briefRows() == "623 621",
		"without Q.Compare: the same, got " .. outlines())
	Q.Compare, Q.StatusRank = stand.Compare, stand.StatusRank
	Q.ToggleBrowser(); Q.ToggleBrowser()
	check(compares > 0, "with it: Q.Compare's order")
	-- A chain's steps keep the chain's order.
	openChain("z:1434:621")
	check(briefRows() == "621 623 622", "a chain's steps: in the chain's order, got " .. briefRows())
	view.switch.map:Click()
	-- Clicks: the next step's line (a quest: the map; right-click: its chain), the card (the chain).
	local c = chainCard("z:1434:641")
	local nb = c.NextBtn
	check(nb._kind == "Button" and nb:IsShown() and nb.quest == 643 and nb:GetParent() == c, "the next step's line: a button of its own on the card")
	nb._scripts.OnEnter(nb)
	check(TOOLTIP.title == "First Way" and TOOLTIP.lines[#TOOLTIP.lines] == "Click: show it on the map · Right-click: its chain"
		and view.zp.map.lit == "z:1434:641", "its tooltip: the quest's, what each click does; its chain lit on the map")
	nb._scripts.OnLeave(nb)
	check(view.zp.map.lit == nil, "left: as before")
	nb:Click()
	check(st.picked == 643 and st.chain == nil and view.zp:IsShown() and view.d.Panel:IsShown(), "a click: the quest on the map, picked")
	unpick()
	chainCard("z:1434:641").NextBtn:Click("RightButton")
	check(st.chain == "z:1434:641" and st.picked == 643 and card(643) and card(643).Glow:IsShown(), "a right-click: its chain, the quest picked in it")
	view.switch.map:Click()
	unpick()
	chainCard("z:1434:641"):Click()
	check(st.chain == "z:1434:641" and st.picked == nil, "the card elsewhere: the chain (it's a chain, not a quest)")
	view.switch.map:Click()
	view.b.rows[1]:Click("RightButton")
	check(st.chain == "z:1434:621" and st.picked == 623, "a row of the briefing right-clicked: its chain, the quest picked")
	view.switch.map:Click()
	view.b.rows[1]:Click()
	check(st.chain == nil and st.picked == 623 and view.zp:IsShown(), "clicked: on the map")
	unpick()
	-- (the zone goes again)
	for _, m in ipairs(made) do QUESTS_DATA[m[1]], STATUS_OF[m[1]] = nil, nil end
	HARD[611], TRIVIAL[641] = nil, nil
	ZONE_QUESTS[STV] = nil
	for _ = 1, #added do table.remove(CHAINS) end
	table.remove(ZONES, 4)
	changed()
	Wait(0.5)
	check(st.where == "z:1429", "the zone gone: back to mine")
end

-- Round 7: a quest found on the map (moved, zoomed out as far as needed, pulsing), a spot asked for
-- (zoomed in to it), the details first where the map isn't in sight, the plan's "+" buttons and the
-- plan on the map (Plan.lua's Q.PlanHas, Q.PlanToggle, Q.PlanStops, Q.PlanRev, Q.PlanNext: stand-ins).
local statusBefore = {}
for id, s in pairs(STATUS_OF) do statusBefore[id] = s end
local function inSight(m, x, y)
	local sx, sy = m.ox + x * m.artW, m.oy + y * m.artH
	return sx >= 0 and sx <= m.width and sy >= 0 and sy <= m.height
end
local function centred(m, x, y)
	return math.abs(m.ox + x * m.artW - m.width / 2) < 1 and math.abs(m.oy + y * m.artH - m.height / 2) < 1
end
local function ringLines(f)
	local n = 0
	for _, l in ipairs(f.lines) do n = n + (l:IsShown() and 1 or 0) end
	return n
end

section("Lodestar: the big window, finding a quest on the map (round 7)")
do
	STATUS_OF[101], STATUS_OF[102], STATUS_OF[103], STATUS_OF[104], STATUS_OF[105], STATUS_OF[110] = "done", "done", "active", "available", "locked", "available"
	Q.HideBrowser()
	Q.SelectZone(ELWYNN)
	view.tabs.zone:Click()
	unpick()
	local m = view.zp.map
	m.buttons.fit:Click()
	-- The whole zone in sight: nothing moves; its pins and areas pulse.
	local ox, oy, flashes = m.ox, m.oy, m.flashes or 0
	check(Q.ShowOnMap(103) == true and st.picked == 103 and st.tab == "zone" and view.zp:IsShown(), "Q.ShowOnMap(id): the Zone tab's map, the quest picked")
	local f = m.Flash
	check(m.zoom == 1 and m.ox == ox and m.oy == oy, "all of it in sight already: the map stays")
	check(f and f:IsShown() and f.Anim:IsPlaying() and m.flashes == flashes + 1 and f.rings == 4 and ringLines(f) == 4 * 18
		and f:GetParent() == m.Map and f:GetFrameLevel() < marker("Deputy Willem"):GetFrameLevel(),
		"its turn-in's pin and its three areas pulse: a glow and a ring of ours each, under the pins, got " .. tostring(f and f.rings))
	local ring2 = f.lines[19] -- (the first area's ring: its radius, 3 px outside the area)
	check(math.abs(ring2.from[1] - (0.4 * m.artW + 0.03 * m.artW + 3)) < 0.01 and math.abs(ring2.from[2] + 0.5 * m.artH) < 0.01
		and f.glows[2].blend == "ADD", "an area's ring: its outline, brighter")
	local alphas = {}
	for _, a in ipairs(f.Anim.anims) do alphas[#alphas + 1] = a.from .. ">" .. a.to end
	check(table.concat(alphas, " ") == "0>1 1>0.35 0.35>1 1>0.35 0.35>1 1>0" and f.Anim.final, "an AnimationGroup on the frame: in and out three times, then gone")
	f.Anim:Finish()
	check(not f:IsShown() and marker("Deputy Willem").Ring:IsShown(), "done: hidden, the quest picked keeps its gold ring")
	-- Zoomed in on a corner: moved there, zoomed out only as far as it needs.
	CURSOR.x, CURSOR.y = 4, -4
	for _ = 1, 5 do m.frame._scripts.OnMouseWheel(m.frame, 1) end
	local zoom = m.zoom
	check(zoom > 4 and not inSight(m, 0.48, 0.42), "zoomed in on the corner")
	Q.ShowOnMap(103)
	check(m.zoom < zoom and m.zoom > 3 and inSight(m, 0.48, 0.42) and inSight(m, 0.37, 0.455) and inSight(m, 0.64, 0.61) and f:IsShown(),
		"out of sight: its pin and its areas brought into sight, zoomed out only as far as they need, got " .. m.zoom)
	m.buttons.fit:Click()
	Q.ShowOnMap(110)
	check(st.picked == 110 and m.zoom == 1 and f.rings == 2, "its pins (where its item drops, two) in sight: never zoomed in to them, got " .. tostring(st.picked) .. " " .. m.zoom .. " " .. tostring(f.rings))
	-- A spot: zoomed in to it, in the middle.
	check(Q.ShowOnMap(104, { map = ELWYNN, x = 0.45, y = 0.6 }) == true and st.picked == 104 and m.zoom == 3 and centred(m, 0.45, 0.6)
		and f:IsShown() and f.rings == 1 and st.spot and st.spot.quest == 104, "a spot: zoomed in to it (300%), in the middle, pulsing")
	Q.ShowOnMap(103, { map = ELWYNN, x = 0.6, y = 0.55, r = 0.2 })
	check(math.abs(m.zoom - (674 - 48) / (2 * 0.2 * m.artW / m.zoom)) < 0.01 and centred(m, 0.6, 0.55), "a large area: only as far in as it fits, got " .. m.zoom)
	Q.ShowOnMap(101, { map = 1453, x = 0.5, y = 0.5 })
	check(st.where == "z:1429" and st.picked == 101 and m.zoom == 3 and centred(m, 0.2, 0.2), "a spot on a city's floor: on its zone's map")
	Q.ShowOnMap(103, { map = WESTFALL, x = 0.5, y = 0.5 })
	check(st.where == "z:1436" and st.picked == 103 and view.zp:IsShown() and m.map == WESTFALL and m.zoom == 3 and centred(m, 0.5, 0.5)
		and zoneRow("z:1436").Picked:IsShown(), "a spot in another zone: that zone's page, the quest picked, zoomed in to it")
	check(Q.ShowOnMap(104, { map = 999999, x = 0.5, y = 0.5 }) == true and st.where == "z:1429" and st.picked == 104,
		"a spot on no zone's map: the quest on its map")
	check(Q.ShowOnMap(424242) == false, "an unknown quest: false")
	-- The details' lines on the zone's map page: the map pin (as before), and the map goes there.
	local d = view.d
	local pins = pinStubs()
	m.buttons.fit:Click()
	d.places[1]:Click()
	check(#pins == 1 and pins[1].x == 0.42 and st.picked == 104 and m.zoom == 3 and centred(m, 0.42, 0.66) and f:IsShown() and f.rings == 1,
		"its giver's line clicked: the game's map pin, and the map zoomed in to it, pulsing")
	d.objectives[1]:Click()
	check(#pins == 2 and pins[2].x == 0.47 and centred(m, 0.47, 0.58) and st.spot.r == 0.01, "an objective's line: its area")
	pins.off()
	-- Not in sight (the quest list): the small map in the details pulses it, "Show on map" goes there.
	view.tabs.overview:Click()
	unpick()
	local ends = QUESTS_DATA[104].ends
	QUESTS_DATA[104].ends = { { kind = "npc", id = 260, name = "Gryan Stoutmantle", points = { at(WESTFALL, 0.56, 0.47) } } }
	listRow(104):Click()
	check(st.tab == "overview" and st.picked == 104 and d.map.frame:IsShown() and d.map.map == ELWYNN and not view.zp:IsShown(),
		"the quest list: its details, the small map of its giver's zone")
	local small = d.map
	local before = small.flashes or 0
	pins = pinStubs()
	d.places[1]:Click()
	check(st.tab == "overview" and small.map == ELWYNN and small.Flash:IsShown() and small.flashes == before + 1 and #pins == 1
		and small.flash[1].x == 0.42, "its giver clicked: the map pin, and the small map pulses it (the quest list stays)")
	d.places[2]:Click()
	check(st.tab == "overview" and small.map == WESTFALL and small.frame:IsShown() and small.Flash:IsShown() and small.flashes == before + 2
		and small.flash[1].x == 0.56, "its turn-in in another zone: the small map shows that zone, pulsing there")
	d.Show._scripts.OnEnter(d.Show)
	check(d.Show._kind == "Button" and TOOLTIP.lines[1] == "The Zone tab's map, zoomed in to the place you picked in the details.", "Show on map says where it goes")
	d.Show._scripts.OnLeave(d.Show)
	d.Show:Click()
	check(st.tab == "zone" and st.where == "z:1436" and st.picked == 104 and m.zoom == 3 and centred(m, 0.56, 0.47), "Show on map: there, on the Zone tab's map")
	pins.off()
	QUESTS_DATA[104].ends = ends
	-- A pin of the small map: it pulses when hovered (and clicked).
	Q.SelectZone(ELWYNN)
	view.tabs.overview:Click()
	listRow(104):Click()
	local pin = small.markers[1]
	before = small.flashes
	pin._scripts.OnEnter(pin)
	check(small.flashes == before + 1 and small.Flash:IsShown() and small.flash[1].x == pin.x, "a pin of the small map hovered: it pulses")
	pin._scripts.OnLeave(pin)
	Q.HideBrowser()
	check(not small.Flash:IsShown() and not m.Flash:IsShown(), "the window closed: nothing pulses")
	Q.SelectZone(ELWYNN)
end

section("Lodestar: the big window, details first (round 7)")
do
	local m, d = view.zp.map, view.d
	view.tabs.overview:Click()
	unpick()
	check(Q.ShowDetails(103) == true and st.tab == "overview" and st.picked == 103 and d.Panel:IsShown() and d.map.frame:IsShown()
		and view.list.scroll:IsShown(), "Q.ShowDetails(id): its details on the tab shown (the quest list stays), the small map in them")
	view.tabs.zone:Click()
	m.buttons.fit:Click()
	m.buttons.plus:Click()
	local ox, oy, zoom, flashes = m.ox, m.oy, m.zoom, m.flashes
	check(Q.ShowDetails(104) == true and st.picked == 104 and m.zoom == zoom and m.ox == ox and m.oy == oy and m.flashes == flashes
		and marker("Marshal Dughan").Ring:IsShown(), "on the zone's map: picked there, the map not moved, nothing pulsing")
	Q.RegisterBrowserView("r7", "Round 7", function(parent) return { frame = CreateFrame("Frame", nil, parent) } end)
	Q.ShowBrowserView("r7")
	check(Q.ShowDetails(110) == true and st.tab == "r7" and st.picked == 110 and d.Panel:IsShown() and d.map.frame:IsShown(),
		"from another file's view: its details beside it, the view stays")
	check(Q.ShowDetails(424242) == false and Q.ShowDetails(nil) == false and st.picked == 110, "an unknown quest: false")
	Q.HideBrowser()
	check(Q.ShowDetails(103) == true and win:IsShown() and st.tab == "r7" and st.picked == 103, "closed: it opens on the tab it showed")
	check(Q.OpenBrowser(104) == true and st.tab == "zone" and view.zp:IsShown() and st.picked == 104, "Q.OpenBrowser(id) is Q.ShowOnMap(id): the Zone tab's map")
	registry.byKey.r7 = nil
	view.tabs.r7:Hide()
	view.tabs.r7 = nil
	table.remove(registry.order)
	registry.current = nil
	-- A chain's card: a click picks it there (its details, the small map), Ctrl-click the map.
	unpick()
	openChain(CHAIN1)
	card(104):Click()
	check(st.chain == CHAIN1 and st.picked == 104 and view.g.frame:IsShown() and d.map.frame:IsShown(), "a chain's card clicked: picked there, the small map in its details")
	STATE.ctrl = true
	card(103):Click()
	STATE.ctrl = false
	check(st.chain == nil and st.picked == 103 and view.zp:IsShown() and st.lastChain == CHAIN1, "Ctrl-clicked: the zone's map with it")
	-- The zone's map page: the briefing's rows show it on the map, their tooltips say so.
	unpick()
	local row
	for _, r in ipairs(view.b.rows) do if r:IsShown() and r.quest == 103 then row = r end end
	row._scripts.OnEnter(row)
	check(TOOLTIP.lines[#TOOLTIP.lines - 1] == "Click: show it on the map · Right-click: its chain", "on the map page: a click shows it on the map")
	row._scripts.OnLeave(row)
	row:Click()
	check(st.picked == 103 and view.zp:IsShown() and m.Flash:IsShown(), "clicked: picked on the map, pulsing")
	unpick()
end

section("Lodestar: the big window, the plan's + (round 7)")
do
	view.tabs.overview:Click()
	unpick()
	local row = listRow(104)
	check(not row.Plus:IsShown() and row.Name._points[1][2] == 24 and row.Icon.points[1][2] == 4, "without the plan (Plan.lua): no +")
	-- The shared contract's plan (Plan.lua makes it): a list of quests, its rev.
	local plan, rev, stops = {}, 0, {}
	local function Has(id) for _, p in ipairs(plan) do if p == id then return true end end return false end
	local toggles = 0
	Q.PlanHas = Has
	Q.PlanList = function() return plan end
	Q.PlanToggle = function(id)
		toggles = toggles + 1
		if Has(id) then
			for i, p in ipairs(plan) do if p == id then table.remove(plan, i) break end end
		else
			plan[#plan + 1] = id
		end
		rev = rev + 1
	end
	Q.PlanRev = function() return rev end
	Q.PlanStops = function() return stops end
	Q.PlanNext = function() for i, s in ipairs(stops) do if not s.done then return s, i end end end
	Q.ToggleBrowser(); Q.ToggleBrowser()
	row = listRow(104)
	local p = row.Plus
	check(p:IsShown() and p._kind == "Button" and p.Plus.shown and not p.Check.shown and row.Icon.points[1][2] == 22 and row.Name._points[1][2] == 42
		and not listRow("z:1429:b:available").Plus:IsShown(), "the quest list: a + at the left of each quest's row (a Button), the icon and title after it; none on a heading")
	p._scripts.OnEnter(p)
	check(TOOLTIP.title == "Add to plan" and plain(TOOLTIP.lines[1]) == "[4] Brotherhood of Thieves", "its tooltip says it")
	local fills = view.list.fills
	p:Click()
	check(plan[1] == 104 and toggles == 1 and listRow(104).Plus.Check.shown and not listRow(104).Plus.Plus.shown and view.list.fills > fills
		and TOOLTIP.title == "In your plan" and TOOLTIP.lines[2] == "Click: remove from plan", "clicked: in the plan, the check instead of the +, drawn again (Q.PlanRev)")
	p._scripts.OnLeave(p)
	listRow(104)._scripts.OnEnter(listRow(104))
	check(table.concat(TOOLTIP.lines, "|"):find("In your plan", 1, true) and TOOLTIP.lines[#TOOLTIP.lines] == "Alt-click: remove from plan",
		"the row's tooltip says so too, and that Alt-click takes it out")
	listRow(104)._scripts.OnLeave(listRow(104))
	-- Alt-click on a row: as on the map's pins.
	local picked = st.picked
	STATE.alt = true
	listRow(104):Click()
	STATE.alt = false
	check(not Has(104) and st.picked == picked and listRow(104).Plus.Plus.shown, "Alt-click a row: out of the plan, nothing shown")
	STATE.alt = true
	listRow(104):Click()
	STATE.alt = false
	check(Has(104) and listRow(104).Plus.Check.shown, "again: in it")
	-- The details' title line, the briefing's rows.
	listRow(103):Click()
	local d = view.d
	-- Wowhead: its link to copy (a small window of ours, the link selected).
	check(d.Web:IsShown() and d.Web:IsEnabled(), "the details: a Wowhead button")
	d.Web:Click()
	local link = LefthyToolsLinkFrame
	check(link and link:IsShown() and link.Box:GetText() == "https://www.wowhead.com/classic/quest=103" and link.Box._highlighted and link.Box._focus,
		"clicked: the link to copy, selected, got " .. tostring(link and link.Box:GetText()))
	link.Box:GetScript("OnEscapePressed")(link.Box)
	check(not link:IsShown(), "Escape: closed")
	check(Q.WowheadURL(103, { new = true }) == nil, "none for a quest new in WoW: Forever")
	check(d.Plan:IsShown() and d.Plan.Plus.shown and d.Title.width == d.bodyW - 44 - 18, "the details: a + on the title line")
	d.Plan:Click()
	check(plan[2] == 103 and d.Plan.Check.shown, "clicked: in the plan, a check")
	d.Plan:Click()
	check(not Has(103) and d.Plan.Plus.shown, "again: out of it")
	unpick()
	local briefRow
	for _, r in ipairs(view.b.rows) do if r:IsShown() and r.quest == 103 then briefRow = r end end
	check(briefRow and briefRow.Plus:IsShown() and briefRow.Text._points[1][2] == 26 + 18, "the briefing's rows: a + too")
	-- Redrawn only when Q.PlanRev changes: a change elsewhere is drawn with the next quest log update.
	fills = view.list.fills
	Fire("QUEST_LOG_UPDATE")
	Wait(1.1)
	check(view.list.fills == fills, "nothing changed: the rows aren't drawn again")
	plan[#plan + 1] = 110
	rev = rev + 1
	Fire("QUEST_LOG_UPDATE")
	Wait(1.1)
	check(listRow(110).Plus.Check.shown and view.list.fills > fills, "the plan changed elsewhere (Q.PlanRev): drawn again")
	-- A + showing what's no longer so (changed elsewhere meanwhile): only drawn again.
	table.remove(plan)
	local stale = listRow(110).Plus
	stale:Click()
	check(not Has(110) and toggles == 5 and stale.Plus.shown, "a stale check clicked: nothing toggled, drawn as it is")
	-- On the map: Alt-click a pin of one quest; a pin of several: its list's rows have the +.
	view.tabs.zone:Click()
	local wolf = marker("drops here (12%)")
	wolf._scripts.OnEnter(wolf)
	check(TOOLTIP.lines[#TOOLTIP.lines] == "Alt-click: add to plan", "a pin's tooltip: Alt-click adds it")
	wolf._scripts.OnLeave(wolf)
	STATE.alt = true
	wolf:Click()
	STATE.alt = false
	check(Has(110) and st.picked == nil, "Alt-clicked: in the plan (nothing picked)")
	wolf._scripts.OnEnter(wolf)
	check(TOOLTIP.lines[#TOOLTIP.lines] == "Alt-click: remove from plan", "its tooltip now says so")
	wolf._scripts.OnLeave(wolf)
	local dughan = marker("Marshal Dughan")
	dughan:Click()
	local list = view.zp.map.chooser
	check(list:IsShown() and list.rows[2].Plus and list.rows[2].Plus:IsShown() and list.rows[2].Plus.quest == 104 and list.rows[2].Plus.Check.shown
		and list.rows[3].Plus.Plus.shown and not (list.rows[1].Plus and list.rows[1].Plus:IsShown()), "a pin of several quests: its list's rows have the + (a check: in the plan)")
	list.rows[3].Plus:Click()
	check(Has(101) and list:IsShown() and list.rows[3].Plus.Check.shown and st.picked == nil, "a + in the list: in the plan, the list stays")
	list:Hide()
	-- Without Q.PlanToggle: no buttons again.
	Q.PlanToggle = nil
	view.tabs.overview:Click()
	check(not listRow(104).Plus:IsShown() and listRow(104).Name._points[1][2] == 24, "without Q.PlanToggle: none")
	Q.PlanToggle = function(id) if Has(id) then for i, x in ipairs(plan) do if x == id then table.remove(plan, i) break end end else plan[#plan + 1] = id end rev = rev + 1 end
	view.tabs.zone:Click()
	-- The plan on the map: the stops at their spots, numbered, the next one gold, joined in order; a stop
	-- in another zone: the line to the map's edge toward it.
	local m = view.zp.map
	local ELW = ELWYNN
	stops[1] = { quest = 104, kind = "start", label = "Marshal Dughan", spot = at(ELW, 0.42, 0.66), done = true }
	stops[2] = { quest = 104, kind = "objective", index = 1, label = "Use Wanted Poster", spot = at(ELW, 0.47, 0.58) }
	stops[3] = { quest = 104, kind = "end", label = "Deputy Willem", spot = at(ELW, 0.48, 0.42) }
	stops[4] = { quest = 201, kind = "start", label = "Gryan Stoutmantle", spot = at(WESTFALL, 0.5, 0.5) }
	stops[5] = { quest = 103, kind = "objective", index = 1, label = "Kill 10 x Kobold Vermin", spot = at(ELW, 0.4, 0.5) }
	rev = rev + 1
	local plans = st.plans
	Q.ToggleBrowser(); Q.ToggleBrowser()
	check(view.filters.planMap:IsShown() and filters.planMap and st.plans == plans + 1, "the plan: worked out once when drawn; its toggle among the filters, on")
	local function shownMarkers()
		local out = {}
		for _, b in ipairs(m.planMarkers or {}) do if b:IsShown() then out[#out + 1] = b.Num:GetText() end end
		return table.concat(out, " ")
	end
	check(shownMarkers() == "2 3 5", "a marker per stop not done on this map, numbered in the plan's order, got " .. shownMarkers())
	local first = m.planMarkers[1]
	check(first._kind == "Button" and first.entry.next and first.Back.vertex[1] == 1 and first:GetWidth() == 22
		and not m.planMarkers[2].entry.next and m.planMarkers[2]:GetWidth() == 18, "the next one: gold, larger")
	check(math.abs(first._points[1][4] - (0.47 * m.artW - 12)) < 0.01 and math.abs(first._points[1][5] + (0.58 * m.artH - 12)) < 0.01,
		"beside the spot (up and left of the quest's own pin there)")
	local lines = {}
	for _, l in ipairs(m.planLines) do if l:IsShown() then lines[#lines + 1] = l end end
	check(#lines == 3 and math.abs(lines[1].from[1] - 0.47 * m.artW) < 0.01 and math.abs(lines[1].to[1] - 0.48 * m.artW) < 0.01,
		"joined by a line in the plan's order: 2 to 3, then toward Westfall and back, got " .. #lines)
	check(math.abs(lines[2].to[2] + 0.99 * m.artH) < 0.01 and lines[2].to[1] < 0.48 * m.artW and lines[2].thickness == 2,
		"toward Westfall (south and west of Elwynn): to the map's bottom edge")
	local labels = {}
	for _, l in ipairs(m.planLabels) do if l:IsShown() then labels[#labels + 1] = l:GetText() end end
	check(table.concat(labels, "|") == "to Westfall (4)|from Westfall (4)", "labelled at the edge, got " .. table.concat(labels, "|"))
	first._scripts.OnEnter(first)
	check(TOOLTIP.title == "2. Use Wanted Poster · Brotherhood of Thieves" and TOOLTIP.lines[1] == "Next stop", "its tooltip: the stop, the next one")
	first._scripts.OnLeave(first)
	m.planMarkers[2]._scripts.OnEnter(m.planMarkers[2])
	check(TOOLTIP.title == "3. Turn in Brotherhood of Thieves · Deputy Willem", "a turn-in's")
	m.planMarkers[2]._scripts.OnLeave(m.planMarkers[2])
	-- Zoomed: laid again, not worked out again.
	m.buttons.plus:Click()
	check(st.plans == plans + 1 and math.abs(first._points[1][4] - (0.47 * m.artW - 12)) < 0.01, "zoomed: laid again where they are, not worked out again")
	-- A click: its quest picked, the stop pulsing; a right-click: the game's map pin.
	first:Click()
	check(st.picked == 104 and m.Flash:IsShown() and m.flash[1].x == 0.47, "a marker clicked: its quest, the stop pulsing")
	local pins = pinStubs()
	first:Click("RightButton")
	check(#pins == 1 and pins[1].x == 0.47, "right-clicked: the map pin there")
	pins.off()
	unpick()
	-- The plan changed: worked out again (Q.PlanRev); a stop done: left out, the next one lit.
	stops[2].done = true
	rev = rev + 1
	Fire("QUEST_LOG_UPDATE")
	Wait(1.1)
	check(st.plans == plans + 2 and shownMarkers() == "3 5" and m.planMarkers[1].entry.next, "a stop done: gone, the next one gold")
	-- Another zone's page: its stop there, the lines toward Elwynn.
	zoneRow("z:1436"):Click()
	check(shownMarkers() == "4" and st.plans == plans + 3, "Westfall: its stop")
	labels = {}
	for _, l in ipairs(m.planLabels) do if l:IsShown() then labels[#labels + 1] = l:GetText() end end
	check(table.concat(labels, "|") == "from Elwynn Forest (3)|to Elwynn Forest (5)", "and where the plan comes from and goes, got " .. table.concat(labels, "|"))
	zoneRow("z:1429"):Click()
	-- "Plan on map" off: nothing of it; on again: back, not worked out again.
	view.filters.planMap:Click()
	check(not filters.planMap and shownMarkers() == "" and M.db.browser.planMap == false, "Plan on map off: gone (kept in the settings)")
	plans = st.plans
	view.filters.planMap:Click()
	check(filters.planMap and shownMarkers() == "3 5" and st.plans == plans, "on again: there")
	-- What the numbers are: each marker says its kind ("?" a turn-in, a dot an objective), the line under
	-- the map says what they are.
	check(m.planMarkers[1].Kind.path == "Interface\\GossipFrame\\ActiveQuestIcon" and m.planMarkers[2].Kind.path == "Interface\\CharacterFrame\\TempPortraitAlphaMask"
		and plain(view.zp.Hint:GetText()):find("^Teal numbers: your plan"), "a marker's kind on it, the line under the map says what they are")
	-- The plan on the right: the switch over the pane, every stop numbered as on the map (done ones ticked).
	for i = #plan, 1, -1 do plan[i] = nil end
	plan[1], plan[2], plan[3] = 104, 201, 103
	rev = rev + 1
	Q.PlanMove = function(id, to)
		for i, x in ipairs(plan) do if x == id then table.remove(plan, i) break end end
		table.insert(plan, math.min(to, #plan + 1), id)
		rev = rev + 1
		return true
	end
	Fire("QUEST_LOG_UPDATE")
	Wait(1.1)
	local sw, p = view.sideSwitch, view.p
	check(sw:IsShown() and sw.info.on and not sw.plan.on and plain(sw.plan.Count:GetText()) == "3 to go" and not p.Scroll:IsShown(),
		"the switch over the right pane: Plan, its stops to go")
	sw.plan:Click()
	check(st.side == "plan" and sw.plan.on and p.Scroll:IsShown() and not view.b.Scroll:IsShown() and not view.d.Panel:IsShown(), "clicked: the plan on the right")
	local function nums()
		local out = {}
		for _, r in ipairs(p.stops) do if r:IsShown() then out[#out + 1] = plain(r.Num:GetText()) end end
		return table.concat(out, " ")
	end
	check(nums() == "1. 2. 3. 4. 5." and plain(p.quests[1].Text:GetText()):find("^1%. %[%d+%] Brotherhood of Thieves") and p.quests[3]:IsShown()
		and plain(p.Sub:GetText()) == "3 quests · 5 stops · 3 to go", "every stop numbered as on the map, under its quest, got " .. nums())
	local done, nextRow = p.stops[1], p.stops[3]
	check(done.Kind.path == "Interface\\RaidFrame\\ReadyCheck-Ready" and plain(done.Text:GetText()):find("Marshal Dughan") and not done.Band:IsShown()
		and nextRow.Band:IsShown() and nextRow.Kind.path == "Interface\\GossipFrame\\ActiveQuestIcon" and p.stops[4].Kind.path == "Interface\\GossipFrame\\AvailableQuestIcon",
		"done ones ticked, the next one on a band, each with its kind")
	-- Hovering a stop lights its number on the map; a click goes there, the pane stays.
	nextRow._scripts.OnEnter(nextRow)
	check(m.planMarkers[1]._lit and not m.planMarkers[2]._lit and TOOLTIP.title == "3. Turn in Brotherhood of Thieves · Deputy Willem"
		and table.concat(TOOLTIP.lines, "|"):find("Click: there on the map", 1, true), "hovered: its number on the map lit, its tooltip")
	nextRow._scripts.OnLeave(nextRow)
	check(not m.planMarkers[1]._lit, "left: not lit")
	done._scripts.OnEnter(done)
	check(table.concat(TOOLTIP.lines, "|"):find("Done: not on the map anymore", 1, true), "a done one says why it isn't on the map")
	done._scripts.OnLeave(done)
	nextRow:Click()
	check(st.picked == 104 and st.side == "plan" and p.Scroll:IsShown() and st.planLit == stops[3] and nextRow.Band:IsShown() and m.Flash:IsShown(),
		"clicked: there on the map, its quest picked, the pane stays, the stop lit")
	m.planMarkers[2]:Click()
	check(st.picked == 103 and st.side == "plan" and st.planLit == stops[5], "a number on the map clicked: the pane stays, that stop lit")
	STATE.ctrl = true
	p.stops[4]:Click()
	STATE.ctrl = false
	check(st.picked == 201 and st.side == nil and view.d.Panel:IsShown() and not p.Scroll:IsShown() and sw.info.on and plain(sw.info.Text:GetText()) == "Quest",
		"Ctrl-click: its quest's details, the switch on Quest")
	sw.plan:Click()
	-- A quest's row dragged: moved in my order.
	p.Scroll.GetTop = function() return 500 end
	local row3 = p.quests[3]
	row3._scripts.OnDragStart(row3)
	CURSOR.y = 500 - (p.quests[1].entry.y + 2)
	p.Dragger._scripts.OnUpdate(p.Dragger, 0)
	check(p.DropLine:IsShown() and row3._alpha == 0.4, "dragged: dim, the line where it lands")
	row3._scripts.OnDragStop(row3)
	check(table.concat(plan, ",") == "103,104,201" and not p.DropLine:IsShown() and plain(p.quests[1].Text:GetText()):find("^1%. %[%d+%] ") and p.quests[1].entry.id == 103,
		"let go at the top: first in my order, drawn again: " .. table.concat(plan, ","))
	-- A quest picked elsewhere (a pin on the map): its details again.
	local pin = marker("Marshal Dughan")
	pin:Click()
	if view.zp.map.chooser then view.zp.map.chooser:Hide() end
	marker("drops here (12%)"):Click()
	check(st.side == nil and view.d.Panel:IsShown() and not p.Scroll:IsShown(), "a quest picked on the map: its details again")
	unpick()
	Q.PlanMove = nil
	-- Without the plan: nothing, no toggle.
	Q.PlanStops = nil
	Q.ToggleBrowser(); Q.ToggleBrowser()
	check(shownMarkers() == "" and not view.filters.planMap:IsShown(), "without Q.PlanStops: nothing of it, no toggle")
	for _, key in ipairs(PLAN_KEYS) do Q[key] = nil end
	Q.ToggleBrowser(); Q.ToggleBrowser()
	for id in pairs(STATUS_OF) do STATUS_OF[id] = statusBefore[id] end
end

-- Back as it was: the window closed, the real functions.
Q.HideBrowser()
for key, fn in pairs(saved) do
	Q[key] = fn or nil
end
for key, fn in pairs(planSaved) do
	Q[key] = fn or nil
end
if M and M.db then M.db.browser = browserSaved end
MAP_NAMES[DUROTAR], MAP_NAMES[STV], MAP_NAMES[REDRIDGE] = nil, nil, nil
QUESTS = questLogBefore
Wait(math.ceil(waited) - waited + 1)
