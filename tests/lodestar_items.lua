-- Lodestar's quest items (Items.lua, Data.lua's Q.ItemQuests): the index of which quests an item is
-- for (objectives, items the giver hands over, items that start a quest), made after the first
-- question over the next frames (the real data: a few hundred quests a frame), learned quests on top;
-- item tooltips: each quest with where it stands for me (in my log with my progress "3/8", ready to
-- turn in, not taken yet: can take it / too low / needs one first, done, skipped), a starter's ("you
-- can start it", "already done: you can discard it", "from level 30"), those that need it first, in
-- the one order (Q.Compare; round 6's contract gets stand-ins while it's missing), at most four and
-- "and N more",
-- "No quest needs it any more: you can discard it" / "Still needed for ..."; quests of my log the
-- data doesn't have with the item, by the item's name (any language: a German one); GameTooltip and
-- ItemRefTooltip only, kept per data, progress and quest log change (a hover is a lookup), nothing
-- before the data is loaded (a hover never loads it), secret IDs, the setting; Q.ItemDone; the sorted
-- bags' mark on a quest item no quest needs any more.
-- Data.lua and Engine.lua are in the build: the quests go in through Q.SetTestData. Whatever this
-- file replaces is put back at its end.
-- Needs: no other file.

local suite = ...
local check, section, ns, LT = suite.check, suite.section, suite.ns, suite.LT
local Q = ns.Lodestar
local M = LT:GetModule("lodestar")

-- What this file replaces on Q, put back at the end.
local replaced = {}
local function Replace(name, fn)
	if replaced[name] == nil then
		replaced[name] = Q[name] or false
	end
	Q[name] = fn
end
local function PutBack(name)
	if replaced[name] ~= nil then
		Q[name] = replaced[name] or nil
		replaced[name] = nil
	end
end

-- The round's shared contract (docs/lodestar.md, Engine: difficulty tiers, "for your level", "hard"
-- and the one order of quests), the data part's, built in parallel: while it's missing (no Q.Tier),
-- stand-ins with its meaning (Q.InRange and Q.ForMyLevel then too: theirs before were the old
-- meaning). Their own test fields: a quest's q.mobs = { lo, hi } (its objectives' mobs) and q.group.
if not (Q.Tier and Q.Compare) then
	local HARDER, KEYS = { trivial = 1, easy = 2, fair = 3, difficult = 4, impossible = 5 }, { "trivial", "easy", "fair", "difficult", "impossible" }
	local RGB = { trivial = { 0.5, 0.5, 0.5 }, easy = { 0.25, 0.75, 0.25 }, fair = { 1, 0.82, 0 }, difficult = { 1, 0.5, 0.25 }, impossible = { 1, 0.1, 0.1 } }
	Replace("TIER_WORD", { trivial = "Trivial", easy = "Easy", fair = "Fair", difficult = "Hard", impossible = "Too hard" })
	Replace("Group", function(id) local q = Q.Quest(id) return q ~= nil and q.group == true end)
	Replace("MobLevels", function(id) local q = Q.Quest(id) if q and q.mobs then return q.mobs[1], q.mobs[2] end end)
	Replace("Tier", function(id)
		local q = Q.Quest(id)
		if not q then return nil end
		local tier = Q.Difficulty(id) or "fair"
		local _, hi = Q.MobLevels(id)
		local mobs = hi and hi > (tonumber(q.level) or 0) and Q.LevelColor(hi).key
		if mobs and HARDER[mobs] > HARDER[tier] then tier = mobs end
		if Q.Group(id) then tier = KEYS[math.min(5, HARDER[tier] + 1)] end
		return tier
	end)
	Replace("TierColor", function(tier) local c = RGB[tier] or RGB.fair return { r = c[1], g = c[2], b = c[3] } end)
	Replace("TierCode", function(id)
		local c = Q.TierColor(Q.Tier(id) or "fair")
		return ("|cff%02x%02x%02x"):format(math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
	end)
	local function Level(q) -- (the effective level: its own, a scaling one mine, its mobs' if higher; nil: none)
		local level = tonumber(q.level) or tonumber(q.minLevel)
		if q.scales or (level and level <= 0) then level = UnitLevel("player") end
		local _, hi = Q.MobLevels(q.id)
		if hi and (not level or hi > level) then level = hi end
		return level
	end
	Replace("InRange", function(id)
		local q = Q.Quest(id)
		if not q then return false end
		if Q.Status(id) == "active" then return true end
		if q.event or (tonumber(q.minLevel) or 0) > UnitLevel("player") or not Level(q) then return false end
		local tier = Q.Tier(id)
		return tier == "easy" or tier == "fair" or tier == "difficult"
	end)
	Replace("ForMyLevel", function(id)
		local s = Q.Status(id)
		return s == "active" or (s == "available" and Q.InRange(id) and (Q.Tier(id) == "easy" or Q.Tier(id) == "fair"))
	end)
	Replace("IsHard", function(id) return Q.Status(id) == "available" and Q.InRange(id) and Q.Tier(id) == "difficult" end)
	local RANK = { active = 2, available = 5, level = 6, locked = 7, done = 8, other = 9 }
	Replace("StatusRank", function(id)
		local s = Q.Status(id) or "other"
		if s == "active" and C_QuestLog.IsComplete(id) then return 1 end
		if Q.ForMyLevel(id) then return s == "active" and 2 or 3 end
		if Q.IsHard(id) then return 4 end
		return RANK[s] or 9
	end)
	Replace("Compare", function(a, b)
		local ra, rb = Q.StatusRank(a), Q.StatusRank(b)
		if ra ~= rb then return ra < rb end
		local qa, qb = Q.Quest(a), Q.Quest(b)
		local la, lb = qa and Level(qa) or 1000, qb and Level(qb) or 1000
		if la ~= lb then return la < lb end
		local ta, tb = Q.Title(a):lower(), Q.Title(b):lower()
		if ta ~= tb then return ta < tb end
		return a < b
	end)
end

-- The clock moves in frames and quarters of a second here (whole seconds in all at the end).
local spent = 0
local function Step(seconds)
	spent = spent + (seconds or 0.25)
	Advance(seconds or 0.25)
end

local function Item(id) return { kind = "item", id = id } end
local function Collect(id, count, provided) return { kind = "item", id = id, count = count or 1, provided = provided } end
local function Npc(id) return { kind = "npc", id = id, name = "Giver " .. id, points = { { map = 1429, x = 0.5, y = 0.5 } } } end
local function Quest(id, title, level, extra)
	local q = { id = id, title = title, level = level, zone = 1429, starts = { Npc(950) }, ends = { Npc(950) } }
	for k, v in pairs(extra or {}) do q[k] = v end
	return q
end
local QUESTS_DATA = {
	Quest(9501, "Gather Candles", 8, { objectives = { Collect(9901, 8) } }),
	Quest(9502, "Old Errand", 5, { objectives = { Collect(9902) } }),
	Quest(9503, "Letter Two", 6, { excl = { 9504 }, objectives = { Collect(9902) } }),
	Quest(9504, "The Other Way", 6, { excl = { 9503 } }),
	Quest(9505, "The Torn Map", 9, { starts = { Item(9903) } }),
	Quest(9506, "A Faded Note", 5, { starts = { Item(9904) } }),
	Quest(9507, "Sealed Orders", 32, { minLevel = 30, starts = { Item(9905) } }),
	Quest(9508, "Wolf Pelts", 9, { objectives = { { kind = "kill", id = 299, count = 5 }, Collect(9906, 6) } }),
	Quest(9509, "Old Pelts", 6, { objectives = { Collect(9906, 4) } }),
	Quest(9510, "More Pelts", 10, { pre = { 9508 }, objectives = { Collect(9906, 8) } }),
	Quest(9511, "Fine Pelts", 42, { minLevel = 40, objectives = { Collect(9906, 10) } }),
	Quest(9512, "Pelts for the Tanner", 9, { objectives = { Collect(9906, 3) } }),
	Quest(9513, "Supply Run", 9, { objectives = { Collect(9907, 1, true) } }),
}
local ZONES = { { map = 1429, name = "Elwynn Forest", continent = 1415, minLevel = 1, maxLevel = 10 } }
local NEW_ITEMS = {
	[9901] = { name = "Kobold Candle", quality = 1, classID = 12 },
	[9902] = { name = "Old Letter", quality = 1, classID = 12 },
	[9903] = { name = "Torn Map", quality = 1, classID = 12 },
	[9904] = { name = "Faded Note", quality = 1, classID = 12 },
	[9905] = { name = "Sealed Orders", quality = 1, classID = 12 },
	[9906] = { name = "Wolf Pelt", quality = 1, classID = 12 },
	[9907] = { name = "Supply Crate", quality = 1, classID = 12 },
	[9908] = { name = "Glowing Shard", quality = 1, classID = 12 },
	[9909] = { name = "Leinenstoffbündel", quality = 1, classID = 12 }, -- (a German client's name)
	[9911] = { name = "Odd Trinket", quality = 1, classID = 12 },
}
for id, item in pairs(NEW_ITEMS) do ITEMS[id] = item end

-- My progress: done Old Errand, The Other Way (Letter Two skipped), A Faded Note, Old Pelts; level 10;
-- in my log Gather Candles (3/8), Supply Run (ready), two quests the data doesn't know.
local completed = { [9502] = true, [9504] = true, [9506] = true, [9509] = true }
local savedCompleted = C_QuestLog.GetAllCompletedQuestIDs
C_QuestLog.GetAllCompletedQuestIDs = function()
	local list = {}
	for id in pairs(completed) do list[#list + 1] = id end
	return list
end
local savedQuests, savedLevel = QUESTS, PLAYER_LEVEL
PLAYER_LEVEL = 10
local candles = { text = "Kobold Candle: 3/8", finished = false, type = "item", numFulfilled = 3, numRequired = 8 }
QUESTS = {
	{ id = 9501, title = "Gather Candles", objectives = { candles } },
	{ id = 9513, title = "Supply Run", complete = true, objectives = { { text = "Supply Crate: 1/1", finished = true } } },
	{ id = 9600, title = "Shards of the Rift", objectives = { { text = "Glowing Shard: 2/5", finished = false } } },
	{ id = 9601, title = "Leinen für Goldhain", objectives = { { text = "Leinenstoffbündel: 1/4", finished = false } } },
}
local function Progress()
	Fire("PLAYER_ENTERING_WORLD", false, false)
	Fire("QUEST_LOG_UPDATE")
end

local function Plain(text) return ((text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function Ours(text)
	return text:find("^Lodestar: ") or text:find("^No quest needs it") or text:find("^Still needed for") or text:find("^Only low%-level")
end
-- An item hovered (GameTooltip, as in the bags): Lodestar's lines.
local function Hover(item)
	GameTooltip:SetOwner(UIParent)
	GameTooltip:SetHyperlink("item:" .. item)
	local out = {}
	for _, line in ipairs(TOOLTIP.lines) do
		local text = Plain(line)
		if Ours(text) then out[#out + 1] = text end
	end
	return out
end
local function Joined(item) return table.concat(Hover(item), " | ") end
-- The item post-calls run on another tooltip (as the data processor would): its Lodestar lines.
local function HoverOn(tooltip, info)
	if tooltip.SetOwner then tooltip:SetOwner(UIParent) end
	for _, c in ipairs(TOOLTIP_POSTCALLS) do
		if c[1] == Enum.TooltipDataType.Item then c[2](tooltip, info) end
	end
	local out = {}
	for _, line in ipairs(tooltip._lines or {}) do
		if Ours(Plain(line)) then out[#out + 1] = Plain(line) end
	end
	return out
end

Q.SetTestData(QUESTS_DATA, ZONES)
Progress()

---------------------------------------------------------------------------
section("Lodestar: which quests an item is for (Q.ItemQuests)")
do
	check(Q.ItemQuests(9901) == nil, "the first question: not made yet (it starts)")
	check(#Hover(9901) == 0, "a hover meanwhile: nothing yet")
	Step(1 / 60)
	local list = Q.ItemQuests(9901)
	check(list and #list == 1 and list[1].id == 9501 and list[1].role == "objective", "a frame later: an objective's item")
	list = Q.ItemQuests(9906)
	local ids = {}
	for i, e in ipairs(list or {}) do ids[i] = e.id .. e.role:sub(1, 1) end
	check(table.concat(ids, ",") == "9508o,9509o,9510o,9511o,9512o", "every quest it's for, by ID (the kill beside it left out), got " .. table.concat(ids, ","))
	check(Q.ItemQuests(9907)[1].role == "provided" and Q.ItemQuests(9903)[1].role == "starts" and Q.ItemQuests(9903)[1].id == 9505,
		"what the giver hands over; what starts a quest")
	check(#Q.ItemQuests(2589) == 0 and #Q.ItemQuests(9908) == 0, "an item of no quest: an empty list")
	check(Q.ItemQuests(9906) == Q.ItemQuests(9906), "shared: the same list each time")
end

---------------------------------------------------------------------------
section("Lodestar: quest items in tooltips")
do
	check(M.db.itemTooltips == true and REGISTERED_SETTINGS["LefthyTools_lodestar_itemTooltips"]
		and REGISTERED_SETTINGS["LefthyTools_lodestar_itemTooltips"].name == "Quest items in tooltips", "on by default, a checkbox under Tooltips")
	check(Joined(9901) == "Lodestar: for Gather Candles · in your log (3/8)", "in my log: with my progress, got " .. Joined(9901))
	check(Joined(9907) == "Lodestar: for Supply Run · ready to turn in", "ready to turn in (what the giver handed over), got " .. Joined(9907))
	check(Joined(9902) == "Lodestar: for Old Errand · done | Lodestar: for Letter Two · skipped | No quest needs it any more: you can discard it",
		"every quest done or skipped: you can discard it, got " .. Joined(9902))
	check(Joined(9903) == "Lodestar: starts the quest [9] The Torn Map · you can start it", "a starter: you can start it, its level, got " .. Joined(9903))
	check(Joined(9904) == "Lodestar: starts the quest A Faded Note · already done: you can discard it",
		"a starter done: discard it (one line), got " .. Joined(9904))
	check(Joined(9905) == "Lodestar: starts the quest [32] Sealed Orders · from level 30", "a starter for later: from which level, got " .. Joined(9905))
	check(Joined(9906) == "Lodestar: for [9] Pelts for the Tanner · not taken yet: you can take it | Lodestar: for [9] Wolf Pelts · not taken yet: you can take it"
		.. " | Lodestar: for [42] Fine Pelts · not taken yet: from level 40 | Lodestar: for [10] More Pelts · not taken yet: needs another quest first"
		.. " | Lodestar: and 1 more | Still needed for Pelts for the Tanner and 3 more",
		"many quests: the ones that need it first, in the one order (to take: by level, then title; coming up; blocked), at most four, "
		.. "how many more, which still need it, got " .. Joined(9906))
	check(#Hover(2589) == 0, "an item of no quest: nothing")

	-- Quests not taken yet that are grey for me: left out unless the setting says otherwise.
	local grey = { [9508] = true, [9510] = true, [9512] = true }
	local tier = Q.Tier
	Replace("Tier", function(id) return grey[id] and "trivial" or tier(id) end)
	Progress()
	check(M.db.itemTooltipsLow == false and REGISTERED_SETTINGS["LefthyTools_lodestar_itemTooltipsLow"], "low-level quests: off by default, a checkbox")
	check(Joined(9906) == "Lodestar: for [42] Fine Pelts · not taken yet: from level 40 | Lodestar: for Old Pelts · done | Still needed for Fine Pelts",
		"grey ones not taken yet: left out, got " .. Joined(9906))
	grey[9511] = true
	Progress()
	check(Joined(9906) == "Lodestar: for Old Pelts · done | Only low-level quests need it: you can discard it",
		"only grey ones still need it: you can discard it, got " .. Joined(9906))
	LT:SetModuleSetting(M, "itemTooltipsLow", true)
	check(select(2, Joined(9906):gsub("not taken yet", "")) == 4, "the setting on: all of them again, got " .. Joined(9906))
	LT:SetModuleSetting(M, "itemTooltipsLow", false)
	PutBack("Tier")
	Progress()
	Hover(9906); Hover(9902); Hover(9901) -- (made again for what comes next)

	-- Quests the data doesn't have with the item: my log's, by the item's name (the client's language).
	check(Joined(9908) == "Lodestar: for Shards of the Rift · in your log (2/5)", "a quest of my log the data doesn't know, got " .. Joined(9908))
	check(Joined(9909) == "Lodestar: for Leinen für Goldhain · in your log (1/4)", "a German client's name, got " .. Joined(9909))

	-- Kept: a hover is a lookup, until the data, my progress or the quest log changes.
	local asked = 0
	local statusOf = Q.StatusOf
	Replace("StatusOf", function(...) asked = asked + 1; return statusOf(...) end)
	Hover(9906); Hover(9902); Hover(9901)
	check(asked == 0, "hovered again: the lines kept (no status asked)")
	candles.text, candles.numFulfilled = "Kobold Candle: 4/8", 4
	Fire("QUEST_LOG_UPDATE")
	check(Joined(9901) == "Lodestar: for Gather Candles · in your log (4/8)" and asked > 0, "the quest log changed: made again, got " .. Joined(9901))
	asked = 0
	Hover(9901)
	check(asked == 0, "... and kept again")
	completed[9505] = true
	Progress()
	check(Joined(9903) == "Lodestar: starts the quest The Torn Map · already done: you can discard it", "my progress changed: made again")
	completed[9505] = nil
	Progress()
	PutBack("StatusOf")

	-- Only GameTooltip and ItemRefTooltip (chat links); secret IDs; the setting.
	check(HoverOn(ItemRefTooltip, { type = 0, id = 9901 })[1] == "Lodestar: for Gather Candles · in your log (4/8)", "a chat link's tooltip (ItemRefTooltip)")
	local other = CreateFrame("GameTooltip", nil, UIParent)
	check(#HoverOn(other, { type = 0, id = 9901 }) == 0, "another tooltip (a comparison): nothing")
	local reported, stop = suite.catchErrors()
	GameTooltip:SetOwner(UIParent)
	HoverOn(GameTooltip, { type = 0, id = SECRET })
	stop()
	check(#reported == 0 and #TOOLTIP.lines == 0, "a secret item ID: nothing, no error")
	LT:SetModuleSetting(M, "itemTooltips", false)
	check(#Hover(9901) == 0 and Q.ItemMarked(9902) == false, "the setting off: nothing (and no mark)")
	LT:SetModuleSetting(M, "itemTooltips", true)
	check(#Hover(9901) == 1, "on again")

	-- Nothing before the data is loaded, and a hover never loads it.
	local loads = 0
	local isLoaded = Q.IsLoaded
	Replace("IsLoaded", function() return false end)
	Replace("Load", function() loads = loads + 1; return false end)
	check(#Hover(9901) == 0 and Q.ItemDone(9902) == nil and loads == 0, "the data not loaded: nothing, and a hover never loads it")
	PutBack("Load")
	PutBack("IsLoaded")
	check(Q.IsLoaded == isLoaded and #Hover(9901) == 1, "loaded: the lines again")
end

---------------------------------------------------------------------------
section("Lodestar: no quest needs it any more (Q.ItemDone)")
do
	check(Q.ItemDone(9902) == true and Q.ItemDone(9904) == true, "every quest done or skipped; a starter of a quest done")
	check(Q.ItemDone(9901) == false and Q.ItemDone(9906) == false and Q.ItemDone(9903) == false and Q.ItemDone(9905) == false,
		"one still needs it (in my log, can take it, for later)")
	check(Q.ItemDone(2589) == nil and Q.ItemDone(9908) == nil, "an item of no quest the data knows: nil")
	completed[9501] = true
	QUESTS[1].objectives = {}
	table.remove(QUESTS, 1)
	Progress()
	check(Q.ItemDone(9901) == true and Joined(9901) == "Lodestar: for Gather Candles · done | No quest needs it any more: you can discard it",
		"its quest turned in: discard it, got " .. Joined(9901))

	-- Learned quests: their items on top of the data's.
	check(#Q.ItemQuests(9911) == 0, "an item of no quest")
	Q.AddLearned(9520, { title = "Learned Errand", level = 9, zone = 1429, starts = { { kind = "item", id = 9911 } } })
	local list = Q.ItemQuests(9911)
	check(list and #list == 1 and list[1].id == 9520 and list[1].role == "starts" and #Q.ItemQuests(9906) == 5,
		"a learned quest an item starts: there at once, the rest as it was")
	check(Joined(9911) == "Lodestar: starts the quest [9] Learned Errand · you can start it", "and in its tooltip, got " .. Joined(9911))
end

---------------------------------------------------------------------------
section("Lodestar: the sorted bags mark what no quest needs any more")
do
	local bagsBefore = BAGS
	local tweaks = LT:GetModule("tweaks")
	check(tweaks.db.mouseBags == true, "(the sorted bags with mouse and keyboard)")
	BAGS = { [0] = { [1] = 9901, [2] = 9906, [3] = 9902, [4] = 2589 } }
	local function Button(slot)
		for _, b in ipairs(ContainerFrameCombinedBags.buttons) do
			if b:GetBagID() == 0 and b:GetID() == slot then return b end
		end
	end
	OpenBags()
	Step()
	local st = ns.GamepadBagsState()
	check(st.applied and st.marked[Button(1)] and st.marked[Button(3)] and not st.marked[Button(2)] and not st.marked[Button(4)],
		"quest items no quest needs any more: marked; one still needed and other items: not")
	local mark = st.marked[Button(3)]
	local point, rel, relPoint = mark:GetPoint(1)
	check(mark.path == "Interface\\RaidFrame\\ReadyCheck-NotReady" and point == "TOPLEFT" and rel == Button(3) and relPoint == "TOPLEFT",
		"a small red x in its top left corner")
	-- An item moved: the mark goes with it.
	BAGS[0][3], BAGS[0][5] = nil, 9902
	ContainerFrameCombinedBags:UpdateItems()
	Step()
	st = ns.GamepadBagsState()
	check(st.marked[Button(5)] and not st.marked[Button(3)], "moved: the mark follows it")
	LT:SetModuleSetting(M, "itemTooltips", false)
	CloseBags()
	OpenBags()
	Step()
	st = ns.GamepadBagsState()
	check(not next(st.marked), "the setting off: no marks")
	LT:SetModuleSetting(M, "itemTooltips", true)
	CloseBags()
	BAGS = bagsBefore
end

---------------------------------------------------------------------------
section("Lodestar: the item index of the real data, over frames")
do
	if type(LefthyToolsQuestData) ~= "table" then
		assert(loadfile("LefthyTools_QuestData/QuestData.lua"))()
	end
	Q.SetTestRawData(LefthyToolsQuestData)
	check(Q.ItemQuests(1931) == nil, "the real data: the first question starts it")
	local frames = 0
	while Q.ItemQuests(1931) == nil and frames < 200 do
		Step(1 / 60)
		frames = frames + 1
	end
	local n = 0
	for _ in pairs(LefthyToolsQuestData.quests) do n = n + 1 end
	check(frames >= math.ceil(n / 300) - 1 and frames < 200, ("made over %d frames (%d quests, at most 300 a frame)"):format(frames, n))
	local claw, deed, given = Q.ItemQuests(1931), Q.ItemQuests(1972), Q.ItemQuests(1971)
	check(claw[1] and claw[1].id == 176 and claw[1].role == "objective", "Hogger's Huge Gnoll Claw: collected for Wanted: Hogger")
	check(deed[1] and deed[1].id == 184 and deed[1].role == "starts" and given[1] and given[1].id == 184 and given[1].role == "provided",
		"Furlbrow's Deed: the item that starts it, and the one its giver hands over")
	check(type(LefthyToolsQuestData.quests[176]) == "string", "the data stays strings")
	Q.SetTestData(QUESTS_DATA, ZONES) -- (the test data again, for what comes after)
end

-- Put back what this file replaced, the mock's world; the clock on a whole second.
for name in pairs(replaced) do PutBack(name) end
for id in pairs(NEW_ITEMS) do ITEMS[id] = nil end
QUESTS, PLAYER_LEVEL = savedQuests, savedLevel
C_QuestLog.GetAllCompletedQuestIDs = savedCompleted
Progress()
if spent ~= math.ceil(spent) then
	Advance(math.ceil(spent) - spent)
end
