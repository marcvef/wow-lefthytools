-- WhyPoor?: who I am (Context.lua) and the ideas, worked out and ranked (Methods.lua): the context from
-- the game (C_SkillInfo and the fallback, a rogue's Pick Pocket, the group); with stand-ins for Prices,
-- Data, Crafts, Bags, the Bestiary's records and Lodestar (realistic fixtures, put back at the end):
-- each kind's numbers (grind from the database and from your own kills, pace and damage, skinning and its
-- skill, pickpocket, gather, fish, quest, craft, flip, vendor flip, limited, disenchant, sell, learn), the
-- filters (side, level window, elite, rare, critters, instances, spawns, skill), bases, confidence and
-- warnings, ranking, missing prices, characters of level 5, 25, 45 and 60; the driver (nothing before a
-- request, a few units a frame, the budget, the watchers a frame later, nothing idle, the cache, an error).
-- Needs: no other file.
local suite = ...
local check, near, section, ns, LT = suite.check, suite.near, suite.section, suite.ns, suite.LT
local catchErrors = suite.catchErrors
local L = ns.L

local W = ns.WhyPoor
local I = W.Ideas
local X = I.parts
local Bt = ns.Bestiary
local Q = ns.Lodestar

section("whypoor_methods")
check(ns.WhyPoor ~= nil and LT:GetModule("whypoor") ~= nil, "the module is there")

-- Nothing runs before the first request: no driver, no events, no run.
check(X.frame == nil and X.events == nil and X.job == nil, "nothing made before the first request")
local list0, fresh0 = I.Get()
check(type(list0) == "table" and #list0 == 0 and fresh0 == false, "I.Get before a run: an empty list, not up to date")

---------------------------------------------------------------------------
-- The rules
---------------------------------------------------------------------------

section("whypoor_methods: rules")
check(X.GreyLevel(5) == 0 and X.GreyLevel(25) == 18 and X.GreyLevel(45) == 35 and X.GreyLevel(60) == 51, "grey levels: classic's")
local lo, hi = X.Window(5)
check(lo == 1 and hi == 6, "level 5: mobs 1-6")
lo, hi = X.Window(25)
check(lo == 19 and hi == 26, "level 25: mobs 19-26")
lo, hi = X.Window(60)
check(lo == 52 and hi == 61, "level 60: mobs 52-61")
check(X.SkinMax(1) == 10 and X.SkinMax(99) == 19 and X.SkinMax(100) == 20 and X.SkinMax(150) == 30 and X.SkinMax(300) == 60,
	"skinning: the highest level a skill skins")
check(X.SkinNeed(8) == 1 and X.SkinNeed(15) == 50 and X.SkinNeed(25) == 125 and X.SkinNeed(60) == 300, "skinning: the skill a level needs")
for level = 1, 60 do
	if X.SkinMax(X.SkinNeed(level)) < level then check(false, "the skill a level needs skins it: " .. level) end
end
check(X.Round(12345) == 12000 and X.Round(987) == 990 and X.Round(42.4) == 42, "estimates: two digits")
check(X.Money(12345) == "1g 23s 45c" and X.Money(12345, true) == "~1g 20s 0c" and X.Money(7) == "7c", "money as text, ~ when not sure")
check(X.Weaker("yours", "classic") == "classic" and X.Weaker("estimate", "prices") == "estimate" and X.Weaker("forever", "yours") == "forever",
	"the weaker basis")

---------------------------------------------------------------------------
-- The context
---------------------------------------------------------------------------

section("whypoor_methods: context")
PROFESSIONS = { { name = "Skinning", level = 150, line = 2947 }, { name = "Mining", level = 140, line = 186 }, nil, { name = "Fishing", level = 75, line = 356 } }
PLAYER_CLASS, PLAYER_LEVEL = "ROGUE", 25
KNOWN_SPELLS[921] = true
local ctx = W.Context()
check(ctx.level == 25 and ctx.class == "ROGUE" and ctx.race == "Human" and ctx.faction == "Alliance" and ctx.gold == MONEY,
	"level, class, race, side, gold")
check(ctx.map == 1429, "the zone I'm in")
check(ctx.professions[393] == 150 and ctx.professions[186] == 140 and ctx.professions[356] == 75, "professions from the game (a child line counts as its base)")
check(ctx.canSkin and ctx.canMine and ctx.canFish and not ctx.canHerb and not ctx.canDisenchant, "what it can gather")
check(ctx.primaries == 2 and ctx.freePrimary == false, "two primary professions: no free slot (fishing isn't one)")
check(ctx.canPick == true, "a rogue with Pick Pocket can pick pockets")
KNOWN_SPELLS[921] = nil
check(W.Context().canPick == false, "a rogue without Pick Pocket (the game says so) can't")
PLAYER_CLASS = "WARRIOR"
check(W.Context().canPick == false, "a warrior can't")
check(ctx.group == 1 and ctx.grouped == false, "alone")
GROUP = "party"
check(W.Context().grouped == true and W.Context().group >= 2, "in a group")
GROUP = "none"
-- C_SkillInfo first: every line, Lockpicking too.
C_SkillInfo = { GetSkillLineInfoByID = function(id)
	local ranks = { [633] = 80, [182] = 1 }
	if ranks[id] then return { skillID = id, rank = ranks[id], maxRank = 300 } end
end }
ctx = W.Context()
check(ctx.professions[633] == 80 and ctx.professions[182] == 1 and ctx.professions[393] == nil, "C_SkillInfo's lines, Lockpicking too")
check(ctx.canHerb and not ctx.canSkin and ctx.freePrimary, "one primary: a free slot")
C_SkillInfo = { GetSkillLineInfoByID = function(id) if id == 182 then return { skillID = id, rank = SECRET } end end }
ctx = W.Context()
check(ctx.professions[182] == nil and ctx.professions[393] == 150, "a secret rank isn't one: the game's list instead")
C_SkillInfo = nil
PROFESSIONS = {}
check(next(W.Context().professions) == nil and W.Context().freePrimary, "no professions")

---------------------------------------------------------------------------
-- Fixtures: prices, the money data, the Bestiary, Lodestar, crafts, bags
---------------------------------------------------------------------------

local NOW = time()
local saved = { Prices = W.Prices, Data = W.Data, Crafts = W.Crafts, Bags = W.Bags, Known = Bt.Known, Mob = Bt.Mob, BtData = Bt.Data,
	NameOf = Bt.NameOf, faction = UnitFactionGroup, items = {}, maps = {} }
for _, k in ipairs({ "Load", "Zones", "ZoneQuests", "Status", "InRange", "Rewards", "Quest", "Group" }) do saved["Q" .. k] = Q[k] end

-- Items: names, vendor prices, the auction house (value, low, qty, seen, sells, perDay, confidence, unstable).
local GREEN, GREEN2, UNSTABLE, LOWCONF, STALEITEM, LIMITED, NOPRICE = 90001, 90002, 90003, 90004, 90005, 90006, 90007
local FIX = {
	[2589] = { "Linen Cloth", 13, { value = 60, low = 55, qty = 40, perDay = 50, sells = 0.8, confidence = "high" } },
	[2318] = { "Light Leather", 15, { value = 50, low = 45, qty = 20, perDay = 30, sells = 0.8, confidence = "high" } },
	[2319] = { "Medium Leather", 25, { value = 80, low = 70, qty = 20, perDay = 20, sells = 0.7, confidence = "medium" } },
	[2934] = { "Ruined Leather Scraps", 5 },
	[7073] = { "Broken Fang", 6 },
	[750] = { "Tough Wolf Meat", 0 },
	[2592] = { "Wool Cloth", 33, { value = 120, low = 10, qty = 4, perDay = 30, sells = 0.8, confidence = "high" } },
	[4306] = { "Silk Cloth", 150, { value = 400, low = 250, qty = 6, perDay = 20, sells = 0.8, confidence = "high" } },
	[4338] = { "Mageweave Cloth", 250, { value = 700, low = 650, qty = 30, perDay = 25, sells = 0.8, confidence = "high" } },
	[4304] = { "Thick Leather", 50, { value = 300, low = 280, qty = 10, perDay = 10, sells = 0.6, confidence = "medium" } },
	[8170] = { "Rugged Leather", 75, { value = 400, low = 380, qty = 10, perDay = 10, sells = 0.6, confidence = "high" } },
	[14047] = { "Runecloth", 400, { value = 1500, low = 1400, qty = 50, perDay = 40, sells = 0.8, confidence = "high" } },
	[2771] = { "Tin Ore", 25, { value = 120, low = 110, qty = 20, perDay = 15, sells = 0.7, confidence = "high" } },
	[2775] = { "Silver Ore", 75 },
	[3356] = { "Kingsblood", 30, { value = 200, low = 180, qty = 10, perDay = 10, sells = 0.7, confidence = "high" } },
	[13466] = { "Plaguebloom", 100, { value = 900, low = 850, qty = 10, perDay = 10, sells = 0.7, confidence = "high" } },
	[8836] = { "Arthas' Tears", 30, { value = 600, low = 550, qty = 10, perDay = 10, sells = 0.7, confidence = "medium" } },
	[13759] = { "Raw Nightfin Snapper", 6, { value = 100, low = 90, qty = 40, perDay = 30, sells = 0.6, confidence = "high" } },
	[13757] = { "Lightning Eel", 6, { value = 300, low = 280, qty = 10, perDay = 10, sells = 0.6, confidence = "medium" } },
	[10940] = { "Strange Dust", 2, { value = 150, low = 140, qty = 50, perDay = 40, sells = 0.9, confidence = "high" } },
	[10938] = { "Lesser Magic Essence", 2, { value = 400, low = 380, qty = 10, perDay = 10, sells = 0.8, confidence = "high" } },
	[5367] = { "Primitive Rock", 4 },
	[1251] = { "Linen Bandage", 20, { value = 120, low = 110, qty = 10, perDay = 12, sells = 0.8, confidence = "high" } },
	[GREEN] = { "Green Belt", 100, nil, 2 },
	[GREEN2] = { "Green Boots", 80, { value = 300, low = 100, qty = 1, perDay = 2, sells = 0.4, confidence = "medium" }, 2 },
	[UNSTABLE] = { "Shaky Thing", 10, { value = 2000, low = 100, qty = 3, perDay = 5, sells = 0.9, confidence = "medium", unstable = true } },
	[LOWCONF] = { "Rare Thing", 10, { value = 2000, low = 100, qty = 3, perDay = 5, sells = 0.9, confidence = "low" } },
	[STALEITEM] = { "Old Thing", 10, { value = 2000, low = 100, qty = 3, perDay = 5, sells = 0.9, confidence = "high", age = 4 * 3600 } },
	[LIMITED] = { "Limited Recipe", 250, { value = 3000, low = 2900, qty = 1, perDay = 5, sells = 0.8, confidence = "high" } },
	[NOPRICE] = { "Unknown Thing" },
}
local priceRev = 1
local P = { STALE = 3 * 3600, AH_CUT = 0.05 }
function P.Vendor(item) return FIX[item] and FIX[item][2] end
function P.Get(item)
	local f = FIX[item] and FIX[item][3]
	if not f then return nil end
	return { low = f.low, qty = f.qty, seen = NOW - (f.age or 600), value = f.value, days = f.days or 7, sells = f.sells, perDay = f.perDay,
		confidence = f.confidence, unstable = f.unstable, friend = f.friend }
end
function P.AHSale(item, n)
	local f = FIX[item] and FIX[item][3]
	if not (f and f.value) then return nil end
	return math.floor(f.value * 0.95) * n, f.value
end
function P.Items()
	return { 2589, 2592, 4306, GREEN2, UNSTABLE, LOWCONF, STALEITEM }
end
function P.Revision() return priceRev end
for id, f in pairs(FIX) do
	saved.items[id] = ITEMS[id] or false
	ITEMS[id] = { name = f[1], quality = f[4] or 1, price = f[2] }
end

-- The world: zones, mobs (Data's), their classic drops (Bt.Known), spawns, nodes, fishing, pockets.
for map, name in pairs({ [1431] = "Duskwood", [1446] = "Tanaris", [1423] = "Eastern Plaguelands", [1444] = "Feralas" }) do
	saved.maps[map] = MAP_NAMES[map] or false
	MAP_NAMES[map] = name
end
local function M(name, rank, kind, a, h, extra)
	local m = { name = name, rank = rank, type = kind, reactA = a, reactH = h, respawn = 300 }
	for k, v in pairs(extra or {}) do m[k] = v end
	return m
end
local MOBS_ = {
	-- Elwynn Forest
	[299] = M("Young Wolf", "normal", "Beast", "hostile", "hostile", { skin = "leather" }),
	[6] = M("Kobold Vermin", "normal", "Humanoid", "hostile", "hostile"),
	[1] = M("Kobold Brute", "elite", "Humanoid", "hostile", "hostile"),
	[100] = M("Stormwind Guard", "normal", "Humanoid", "friendly", "hostile"),
	[101] = M("Grey Deer", "normal", "Beast", "neutral", "neutral"),
	[108] = M("Horde Peon", "normal", "Humanoid", "hostile", "friendly", { civilian = true }),
	[109] = M("Timbermaw Bear", "normal", "Beast", "neutral", "neutral", { rep = 576 }),
	[102] = M("Farmer", "normal", "Humanoid", "neutral", "neutral"),
	[103] = M("Mother Fang", "rare", "Beast", "hostile", "hostile"),
	[104] = M("Rabbit", "normal", "Critter", "hostile", "hostile"),
	[105] = M("Defias Miner", "normal", "Humanoid", "hostile", "hostile", { instance = true }),
	[106] = M("Lone Kobold", "normal", "Humanoid", "hostile", "hostile"),
	[107] = M("Riverpaw Gnoll", "normal", "Humanoid", "hostile", "hostile"),
	-- Duskwood
	[565] = M("Rabid Dire Wolf", "normal", "Beast", "hostile", "hostile", { skin = "leather" }),
	[910] = M("Defias Enchanter", "normal", "Humanoid", "hostile", "hostile"),
	[920] = M("Nightbane Dark Runner", "normal", "Humanoid", "hostile", "hostile"),
	[930] = M("Skeletal Fiend", "normal", "Undead", "hostile", "hostile"),
	-- Tanaris
	[5419] = M("Glasshide Basilisk", "normal", "Beast", "hostile", "hostile", { skin = "leather" }),
	[5615] = M("Wastewander Rogue", "normal", "Humanoid", "hostile", "hostile"),
	[5600] = M("Southsea Ally", "normal", "Humanoid", "hostile", "friendly"),
	[900] = M("Vendor Bob", "normal", "Humanoid", "friendly", "friendly"),
	-- Eastern Plaguelands
	[8521] = M("Blighted Horror", "normal", "Undead", "hostile", "hostile"),
	[8522] = M("Plague Monstrosity", "normal", "Undead", "hostile", "hostile"),
	[8596] = M("Plaguehound Runt", "normal", "Beast", "hostile", "hostile", { skin = "leather" }),
	[8597] = M("Pricey Ghoul", "normal", "Undead", "hostile", "hostile"),
}
local KNOWN = {
	[299] = { items = { [750] = { 0.8, 1, true }, [7073] = { 0.4, 0, false } }, skins = { [2934] = { 0.6, 0 }, [2318] = { 0.4, 1 } }, health = { 1, 2, 42, 55 } },
	[6] = { items = { [2589] = { 0.2, 1, false } }, skins = {}, coin = { 1, 4 }, health = { 1, 2, 42, 55 } },
	[1] = { items = { [2589] = { 0.5, 1, false } }, skins = {}, coin = { 10, 20 }, health = { 3, 3, 200, 200 } },
	[100] = { items = {}, skins = {}, coin = { 1, 4 }, health = { 2, 2, 50, 50 } },
	[101] = { items = { [7073] = { 0.5, 0, false } }, skins = {}, health = { 2, 2, 50, 50 } },
	[108] = { items = {}, skins = {}, coin = { 5, 9 }, health = { 2, 2, 50, 50 } },
	[109] = { items = { [7073] = { 0.5, 0, false } }, skins = {}, health = { 2, 2, 50, 50 } },
	[102] = { items = {}, skins = {}, coin = { 5, 9 }, health = { 2, 2, 50, 50 } },
	[103] = { items = {}, skins = {}, coin = { 50, 90 }, health = { 4, 4, 90, 90 } },
	[104] = { items = {}, skins = {}, health = { 1, 1, 8, 8 } },
	[105] = { items = {}, skins = {}, coin = { 5, 9 }, health = { 3, 3, 70, 70 } },
	[106] = { items = {}, skins = {}, coin = { 5, 9 }, health = { 3, 3, 70, 70 } },
	[107] = { items = {}, skins = {}, coin = { 5, 9 }, health = { 7, 8, 140, 160 } },
	[565] = { items = {}, skins = { [2319] = { 0.7, 1 }, [4304] = { 0.3, 1 } }, health = { 24, 25, 664, 713 } },
	[910] = { items = { [2592] = { 0.3, 1, false }, [GREEN] = { 0.01, 2, false } }, skins = {}, coin = { 30, 50 }, health = { 24, 25, 600, 650 } },
	[920] = { items = {}, skins = {}, coin = { 30, 50 }, health = { 26, 27, 700, 750 } },
	[930] = { items = {}, skins = {}, coin = { 20, 30 }, health = { 18, 18, 450, 450 } },
	[5419] = { items = {}, skins = { [8170] = { 1, 1 } }, health = { 43, 44, 1800, 1900 } },
	[5615] = { items = { [4338] = { 0.25, 1, false } }, skins = {}, coin = { 80, 150 }, health = { 43, 44, 1800, 1900 } },
	[5600] = { items = {}, skins = {}, coin = { 80, 150 }, health = { 43, 44, 1800, 1900 } },
	[8521] = { items = { [14047] = { 0.3, 1, false } }, skins = {}, coin = { 200, 400 }, health = { 56, 57, 3200, 3300 } },
	[8522] = { items = {}, skins = {}, coin = { 200, 400 }, health = { 55, 56, 3000, 3100 } },
	[8596] = { items = {}, skins = { [8170] = { 1, 1 } }, health = { 54, 55, 2800, 2900 } },
	[8597] = { items = { [NOPRICE] = { 0.9, 1, false } }, skins = {}, health = { 54, 55, 2800, 2900 } },
}
local function S(map, x, y, n) return { map = map, x = x, y = y, r = 0.05, n = n } end
local SPOTS = {
	[299] = { S(1429, 0.4, 0.6, 8), S(1429, 0.6, 0.7, 4) }, [6] = { S(1429, 0.4, 0.8, 20) }, [1] = { S(1429, 0.5, 0.5, 10) },
	[100] = { S(1429, 0.3, 0.3, 10) }, [101] = { S(1429, 0.5, 0.2, 10) }, [108] = { S(1429, 0.45, 0.25, 10) }, [109] = { S(1429, 0.55, 0.25, 10) }, [102] = { S(1429, 0.4, 0.4, 10) }, [103] = { S(1429, 0.1, 0.1, 10) },
	[104] = { S(1429, 0.2, 0.2, 30) }, [105] = { S(1429, 0.2, 0.9, 10) }, [106] = { S(1429, 0.8, 0.8, 3) }, [107] = { S(1429, 0.9, 0.5, 10) },
	[565] = { S(1431, 0.3, 0.5, 15), S(1429, 0.9, 0.9, 2) }, [910] = { S(1431, 0.2, 0.7, 12) }, [920] = { S(1431, 0.7, 0.3, 20) },
	[930] = { S(1431, 0.8, 0.3, 20) }, [5419] = { S(1446, 0.5, 0.5, 30) }, [5615] = { S(1446, 0.6, 0.4, 25) },
	[5600] = { S(1446, 0.7, 0.7, 25) }, [8521] = { S(1423, 0.5, 0.5, 20) }, [8522] = { S(1423, 0.6, 0.5, 12) },
	[8596] = { S(1423, 0.4, 0.4, 25) }, [8597] = { S(1423, 0.3, 0.3, 25) },
}
local ON = { [1429] = { 299, 6, 1, 100, 101, 108, 109, 102, 103, 104, 105, 106, 107, 565 }, [1431] = { 565, 910, 920, 930 },
	[1446] = { 5419, 5615, 5600, 900 }, [1423] = { 8521, 8522, 8596, 8597 } }
local NODES = {
	[1431] = { { object = 1733, kind = "ore", skill = 65, n = 25, loot = { { item = 2771, chance = 1, min = 1, max = 2 } }, spots = { S(1431, 0.5, 0.5, 25) } },
		{ object = 1734, kind = "ore", skill = 175, n = 10, loot = { { item = 2775, chance = 1, min = 1, max = 1 } }, spots = { S(1431, 0.6, 0.5, 10) } },
		{ object = 1620, kind = "herb", skill = 125, n = 30, loot = { { item = 3356, chance = 1, min = 1, max = 3 } }, spots = { S(1431, 0.4, 0.4, 30) } } },
	[1423] = { { object = 176587, kind = "herb", skill = 285, n = 25, loot = { { item = 13466, chance = 1, min = 1, max = 3 } }, spots = { S(1423, 0.5, 0.5, 25) } },
		{ object = 142141, kind = "herb", skill = 220, n = 15, loot = { { item = 8836, chance = 1, min = 1, max = 3 } }, spots = { S(1423, 0.7, 0.2, 15) } } },
	[1429] = { { object = 1617, kind = "herb", skill = 1, n = 10, loot = { { item = 2589, chance = 1, min = 1, max = 1 } } } },
}
local FISHING = { [1444] = { skill = 205, loot = { { item = 13759, chance = 0.6 }, { item = 13757, chance = 0.3 } } },
	[1423] = { skill = 330, loot = { { item = 13759, chance = 1 } } } }
local POCKETS = { [910] = { { item = 5367, chance = 0.5, min = 1, max = 1 }, { item = 2592, chance = 0.2, min = 1, max = 1 } },
	[6] = { { item = 5367, chance = 0.5, min = 1, max = 1 } } }
local DE = { [GREEN] = { skill = 1, results = { { item = 10940, chance = 0.75, min = 1, max = 2 }, { item = 10938, chance = 0.25, min = 1, max = 1 } } },
	[GREEN2] = { skill = 1, results = { { item = 10940, chance = 0.75, min = 1, max = 2 }, { item = 10938, chance = 0.25, min = 1, max = 1 } } } }
local calls = { MobsOn = 0 }
local dataLoaded = true
local Dt = {
	Load = function() return dataLoaded end,
	Mob = function(c) return MOBS_[c] end,
	Spots = function(c) return SPOTS[c] end,
	MobsOn = function(map) calls.MobsOn = calls.MobsOn + 1; return ON[map] or {} end,
	Nodes = function(map) return NODES[map] end,
	Fishing = function(map) return FISHING[map] end,
	Pickpocket = function(c) return POCKETS[c] end,
	Disenchant = function(item) return DE[item] end,
	LimitedItems = function() return { LIMITED } end,
	Limited = function(item)
		if item == LIMITED then return { { npc = 900, name = "Vendor Bob", map = 1446, x = 0.5, y = 0.3, stock = 3, restock = 3600, price = 1000 } } end
	end,
}

-- The Bestiary's own records (LefthyToolsBestiaryDB's shape) and its classic database.
local OWN = {}
local function Own(t) return t end
Bt.Known = function(c) return KNOWN[c] end
Bt.Mob = function(c) return OWN[c] end
Bt.Data = function() return { mobs = OWN } end
Bt.NameOf = function(c) return OWN[c] and OWN[c].name end

-- Lodestar: its zones and quests, a status each, rewards.
local QUESTS_ = {
	[7] = { status = "available", range = true, q = { title = "Kobold Camp Cleanup", zoneName = "Elwynn Forest", source = "classic",
		starts = { { name = "Marshal McBride", points = { { map = 1429, x = 0.48, y = 0.42 } } } }, ends = {} }, r = { choice = {}, items = {}, money = 35 } },
	[54] = { status = "available", range = true, q = { title = "Report to Goldshire", source = "classic", starts = {}, ends = {} }, r = nil },
	[33] = { status = "active", range = true, q = { title = "Wolves Across the Border", zoneName = "Elwynn Forest", source = "classic",
		starts = {}, ends = { { name = "Eagan Peltskinner", points = { { map = 1429, x = 0.48, y = 0.40 } } } } },
		r = { choice = { { id = 2318, count = 1 }, { id = 4306, count = 1 } }, items = {}, money = 100 } },
	[60] = { status = "done", range = true, q = { title = "Kobold Candles", source = "classic", starts = {}, ends = {} }, r = { money = 5000 } },
	[61] = { status = "available", range = false, q = { title = "Too Hard", source = "classic", starts = {}, ends = {} }, r = { money = 5000 } },
	[62] = { status = "available", range = true, group = true, q = { title = "The Defias Brotherhood", source = "classic", starts = {}, ends = {} },
		r = { choice = {}, items = { { id = 2589, count = 2 } }, money = 500 } },
	[63] = { status = "available", range = true, q = { title = "A Forever Quest", source = "forever", starts = {}, ends = {} }, r = { money = 777 } },
}
Q.Load = function() return true end
Q.Zones = function() return { { map = 1429 }, { map = 1431 } } end
Q.ZoneQuests = function(map) return map == 1429 and { 7, 54, 33, 60, 61 } or { 62, 63, 7 } end
Q.Status = function(id) calls.Status = (calls.Status or 0) + 1; return QUESTS_[id] and QUESTS_[id].status end
Q.InRange = function(id) return QUESTS_[id] and QUESTS_[id].range end
Q.Rewards = function(id) return QUESTS_[id] and QUESTS_[id].r end
Q.Quest = function(id) return QUESTS_[id] and QUESTS_[id].q end
Q.Group = function(id) return QUESTS_[id] and QUESTS_[id].group or false end

-- Crafts and bags.
local CRAFTS = {
	{ spell = 3275, item = 1251, profit = 50, verdict = "craft", complete = true, basis = "prices", oldest = NOW - 300 },
	{ spell = 2, item = 2589, profit = -5, verdict = "sell reagents", complete = true },
	{ spell = 3, item = 4306, profit = 500, verdict = "craft", complete = false },
	{ spell = 4, item = 90100, profit = 80, verdict = "craft", complete = true, basis = "prices" },
}
local mineCalls = 0
local Cr = { Mine = function() mineCalls = mineCalls + 1; if mineCalls == 1 then return {}, false end return CRAFTS, true end } -- (the first call: not done yet)
local BAGS = { { item = 2589, count = 10, best = "ah", value = 570 }, { item = GREEN, count = 1, best = "vendor", value = 100 },
	{ item = 750, count = 3, best = nil, value = 0, keep = "quest" } }
local Bags = { List = function() return BAGS, 670 end }

W.Prices, W.Data, W.Crafts, W.Bags = P, Dt, Cr, Bags

-- One run, to the end (a request and the frames it takes), from scratch (no wait between runs).
local function run(budget)
	X.lastStart = nil
	X.inputs = X.inputs + 1 -- (as the game's events would: the tests change the mock's knobs without them)
	I.Request()
	local frames = 0
	repeat
		Advance(1 / 60)
		frames = frames + 1
	until (not X.job and not X.pending) or frames > (budget or 3000)
	Advance(1 / 60) -- (the watchers, then hidden)
	return I.All() -- (every idea worked out; the list shown is those worth your time: its own section)
end
local function find(list, key)
	for _, idea in ipairs(list) do if idea.key == key then return idea end end
end
local function num(idea, label)
	for _, n in ipairs(idea.numbers) do if n.label == label then return n end end
end
local function warned(idea, text)
	for _, w in ipairs(idea.warnings) do if w == text then return true end end
	return false
end
local function kinds(list)
	local set = {}
	for _, idea in ipairs(list) do set[idea.kind] = (set[idea.kind] or 0) + 1 end
	return set
end
-- The contract's fields on every idea.
local function wellFormed(list)
	for _, idea in ipairs(list) do
		if type(idea.key) ~= "string" or type(idea.kind) ~= "string" or type(idea.title) ~= "string"
			or (idea.perHour ~= nil and idea.once ~= nil) or not X.CONF_RANK[idea.confidence] or not X.BASIS_RANK[idea.basis]
			or type(idea.why) ~= "table" or type(idea.how) ~= "table" or type(idea.numbers) ~= "table" or type(idea.items) ~= "table"
			or type(idea.warnings) ~= "table" then
			return false, idea.key
		end
		for _, n in ipairs(idea.numbers) do
			if type(n.label) ~= "string" or type(n.value) ~= "string" or not X.BASIS_RANK[n.basis] then return false, idea.key .. " numbers" end
		end
		if idea.place and (type(idea.place.map) ~= "number" or type(idea.place.points) ~= "table") then return false, idea.key .. " place" end
	end
	return true
end

---------------------------------------------------------------------------
-- Level 5, a warrior without professions in Elwynn Forest
---------------------------------------------------------------------------

section("whypoor_methods: level 5 warrior")
PLAYER_LEVEL, PLAYER_CLASS, PROFESSIONS, PLAYER_MAP = 5, "WARRIOR", {}, 1429
local list = run()
local ok, bad = wellFormed(list)
check(ok, "every idea has the contract's fields: " .. tostring(bad))
check(X.frame and not X.frame:IsShown() and not X.job, "the driver is hidden when the run is done")
local vermin = find(list, "grind:6")
check(vermin ~= nil, "Kobold Vermin: a grinding idea")
-- 2.5 coin (1-4) + 0.2 Linen Cloth at the auction house's 57 (60 less the cut) = 13.9 a kill; 35 s a fight + 20 s
-- between: 65.45 kills an hour.
check(near(vermin.perKill, 13.9, 0.001) and near(vermin.killsPerHour, 3600 / 55, 0.001) and near(vermin.perHour, 13.9 * 3600 / 55, 0.01),
	"Kobold Vermin's numbers: " .. tostring(vermin.perKill) .. ", " .. tostring(vermin.perHour))
check(vermin.basis == "estimate" and vermin.confidence == "low", "never fought: an estimate, low confidence")
check(warned(vermin, L["Classic data: Forever may differ"]) and warned(vermin, L["You haven't fought it: kills per hour are a careful guess"])
	and warned(vermin, L["World drops (random greens and better) are not counted"]), "its warnings")
check(num(vermin, L["Coin per kill"]).value == "~3c" and num(vermin, L["Coin per kill"]).basis == "classic", "a classic number with ~")
check(num(vermin, L["Kills per hour"]).basis == "estimate", "kills per hour: an estimate")
check(vermin.place.map == 1429 and vermin.place.points[1].x == 0.4 and vermin.place.name == "Elwynn Forest", "its place: its spawns")
check(vermin.items[1].item == 2589 and near(vermin.items[1].n, 0.2 * 3600 / 55, 0.001) and vermin.items[1].source == "ah", "its items: linen an hour")
check(vermin.title == "Kill Kobold Vermin" and vermin.sub == "Elwynn Forest · level 1-2", "title and sub")
check(vermin.why[1] == L["In your zone"], "in my zone: said first")
local wolf = find(list, "grind:299")
-- The quest's meat (0.8) left out, 0.4 Broken Fang at a vendor's 6: 2.4 a kill.
check(wolf and near(wolf.perKill, 2.4, 0.001), "Young Wolf: the quest's drop left out")
check(wolf and not num(wolf, L["Skinning per kill"]), "no skinning without Skinning")
check(find(list, "grind:1") == nil, "an elite alone: no")
check(find(list, "grind:100") == nil, "a friendly guard: no")
check(find(list, "grind:101") ~= nil, "a neutral beast: yes")
check(find(list, "grind:108") == nil, "an enemy town's civilian: no (a dishonorable kill)")
check(find(list, "grind:109") == nil, "a neutral beast of a reputation's faction: no (it costs standing)")
check(find(list, "grind:102") == nil, "a neutral humanoid (a town's): no")
check(find(list, "grind:103") == nil and find(list, "grind:104") == nil and find(list, "grind:105") == nil,
	"a rare, a critter, one in an instance: no")
check(find(list, "grind:106") == nil, "three spawns: too few")
check(find(list, "grind:107") == nil, "level 7-8 at level 5: too high")
check(find(list, "grind:565") == nil, "Duskwood's wolves (level 24): far too high")
-- Learning Skinning: a free slot; the wolf's skins (0.6 scraps at 5 + 0.4 Light Leather at 47) = 21.8 a corpse, at
-- 3600 / 57 corpses an hour (a skinning adds 2 s).
local learnSkin = find(list, "learn:393")
check(learnSkin and near(learnSkin.perHour, 21.8 * 3600 / 57, 0.01) and learnSkin.needs == "Skinning 1",
	"learn Skinning: what it adds to grinding wolves: " .. tostring(learnSkin and learnSkin.perHour))
-- Learning Herbalism: Elwynn's node (10) is too few (20 at least): no idea.
check(find(list, "learn:182") == nil, "too few nodes: no idea to learn Herbalism")
check(find(list, "pickpocket:6") == nil, "a warrior picks no pockets")
-- Quests: available ones that pay, the one in the log with its best choice; not done, out of range, none paying.
local q7, q33 = find(list, "quest:7"), find(list, "quest:33")
check(q7 and q7.once == 35 and q7.place and q7.place.x == nil and q7.place.points[1].x == 0.48, "a quest's money, its giver's place")
check(q33 and q33.once == 100 + 380 and num(q33, L["Best reward"]).copper == 380, "the reward worth the most (Silk Cloth at 380) counted: " .. tostring(q33 and q33.once))
check(q33 and q33.how[1] == L["It's in your quest log: finish it and turn it in."] and q33.place.points[1].y == 0.40, "a quest in my log: turn it in, at its ender")
check(find(list, "quest:54") == nil and find(list, "quest:60") == nil and find(list, "quest:61") == nil, "no reward, done, out of range: none")
local q62, q63 = find(list, "quest:62"), find(list, "quest:63")
check(q62 and q62.once == 500 + 2 * 57 and warned(q62, L["A group quest"]), "a group quest says so, its items all counted")
check(q63 and q63.basis == "forever" and q63.confidence == "high" and q7.basis == "classic" and q7.confidence == "medium", "a Forever quest's basis")
local quests = 0
for _, idea in ipairs(list) do if idea.kind == "quest" then quests = quests + 1 end end
check(quests == 4, "four quests (one listed in two zones once)")
-- Ranking: per hour first, by score; then once.
local lastGroup, lastScore = 0, math.huge
local ordered = true
for _, idea in ipairs(list) do
	if idea.group < lastGroup or (idea.group == lastGroup and idea.score > lastScore + 1e-9) then ordered = false end
	if idea.group ~= lastGroup then lastScore = math.huge end
	lastGroup, lastScore = idea.group, idea.score
end
check(ordered, "ranked: per hour first, by perHour times confidence; then once-ideas")
check(list[1].perHour ~= nil and list[#list].perHour == nil, "a per hour idea first, a once-idea last")

---------------------------------------------------------------------------
-- The market, crafts and bags (the same character)
---------------------------------------------------------------------------

section("whypoor_methods: market")
local silk = find(list, "flip:4306")
-- Silk Cloth: 250 now, usually 400: 380 after the cut, 130 each; counted for one (only the cheapest listing's price
-- is known), the deposit not known: said.
check(silk and silk.once == 130 and silk.basis == "prices" and silk.confidence == "medium", "a flip: the profit of one, got " .. tostring(silk and silk.once))
check(silk and warned(silk, L["The deposit lost if it doesn't sell isn't counted"]), "a flip without the deposit: says so")
check(silk and warned(silk, L["The cheap listing may be gone since the scan"]) and silk.oldest == NOW - 600, "a flip's warning and age")
check(find(list, "flip:2589") == nil, "Linen at 55 against 57: no flip")
check(find(list, "flip:" .. UNSTABLE) == nil and find(list, "flip:" .. LOWCONF) == nil and find(list, "flip:" .. STALEITEM) == nil,
	"never on unstable, low-confidence or old prices")
local wool = find(list, "vendorflip:2592")
check(wool and wool.once == 33 - 10, "a vendor flip: the cheapest listing below what a vendor pays, counted for one")
check(find(list, "disenchant:" .. GREEN2) == nil, "not an enchanter: no greens to disenchant")
local limited = find(list, "limited:" .. LIMITED)
-- 3000 less the cut is 2850 against 1000 at the vendor: 1850 each, 3 in stock.
check(limited and limited.once == 1850 * 3 and limited.place.map == 1446 and limited.basis == "classic", "limited stock: profit times the stock")
local craft = find(list, "craft:3275")
check(craft and craft.once == 50 and craft.basis == "prices", "a recipe that pays: the profit of one craft (how many sell isn't multiplied in)")
check(find(list, "craft:2") == nil, "a recipe whose verdict isn't craft: no")
local incomplete = find(list, "craft:3")
check(incomplete and incomplete.once == nil and incomplete.perHour == nil and incomplete.missing and incomplete.group == 3,
	"a recipe without every price: flagged, not ranked")
local unknown = find(list, "craft:4")
local saidOne = false
for _, line in ipairs(unknown and unknown.why or {}) do
	if line == L["Counted for one craft: how many the auction house takes isn't known"] then saidOne = true end
end
check(unknown and unknown.once == 80 and unknown.confidence == "low" and saidOne, "nothing known of its market: one craft, low, and said")
local sell = find(list, "sell:bags")
check(sell and sell.once == 670 and sell.basis == "prices" and #sell.items == 2 and sell.items[1].item == 2589, "what the bags would fetch")
check(find(list, "disenchant:bags") == nil, "not an enchanter: nothing to disenchant")

---------------------------------------------------------------------------
-- Level 25, a rogue with Skinning and Mining in Duskwood
---------------------------------------------------------------------------

section("whypoor_methods: level 25 rogue")
PLAYER_LEVEL, PLAYER_CLASS = 25, "ROGUE" -- (in Elwynn still: the mock knows its map only)
PROFESSIONS = { { name = "Skinning", level = 150, line = 393 }, { name = "Mining", level = 140, line = 186 } }
KNOWN_SPELLS[921] = true
list = run()
check(wellFormed(list), "every idea has the contract's fields")
local direWolf = find(list, "grind:565")
-- Skins: 0.7 Medium Leather at 76 + 0.3 Thick Leather at 285 = 138.7 a corpse; skill 150 skins up to 30.
check(direWolf and near(direWolf.perKill, 0.7 * 76 + 0.3 * 285, 0.001), "Rabid Dire Wolf: what skinning gives")
check(direWolf and near(direWolf.killsPerHour, 3600 / (35 + 22), 0.001), "skinning adds 2 s a kill")
check(direWolf and direWolf.place.map == 1431 and direWolf.place.points[1].n == nil, "the map with the most spawns (Duskwood, not Elwynn's two)")
local enchanter = find(list, "grind:910")
-- 40 coin + 0.3 Wool Cloth at 114 (+ a green the database lists for it: 0.01 at a vendor's 100) = 75.2.
check(enchanter and near(enchanter.perKill, 40 + 0.3 * 114 + 0.01 * 100, 0.001), "Defias Enchanter: coin, cloth, its own green")
check(find(list, "grind:920") == nil and find(list, "grind:930") == nil, "too high (26-27) and grey (18): no")
local pocket = find(list, "pickpocket:910")
-- 0.5 Primitive Rock at 4 + 0.2 Wool at 114 = 24.8 a pocket, as often as a kill.
check(pocket and near(pocket.perHour, (0.5 * 4 + 0.2 * 114) * enchanter.killsPerHour, 0.01) and warned(pocket, L["Coin from pockets is not counted"]),
	"pick pockets: its loot, as often as kills")
local tin = find(list, "gather:ore:1431")
-- Tin: 1.5 ore at 114 = 171 a node, 25 nodes (silver needs 175: not counted); 15 nodes an hour (estimate).
check(tin and near(tin.perNode, 1.5 * 114, 0.001) and tin.nodes == 25 and near(tin.perHour, 171 * 15, 0.01), "mining: a node's worth, the zone's nodes at my skill")
check(tin and tin.basis == "estimate" and tin.confidence == "low" and num(tin, L["Nodes per hour"]).basis == "estimate", "nodes per hour: an estimate")
check(find(list, "gather:herb:1431") == nil and find(list, "learn:182") == nil, "no Herbalism, no free slot: neither herbs nor learning")
check(find(list, "fish:1444") == nil, "no Fishing: no fishing")
check(find(list, "grind:6") == nil, "Elwynn's kobolds (level 1-2) are grey at 25: no")
KNOWN_SPELLS[921] = nil

---------------------------------------------------------------------------
-- Level 45, a Horde mage with Tailoring and Enchanting in Tanaris
---------------------------------------------------------------------------

section("whypoor_methods: level 45 mage")
PLAYER_LEVEL, PLAYER_CLASS = 45, "MAGE"
UnitFactionGroup = function(unit) if unit == "player" then return "Horde", "Horde" end end
PROFESSIONS = { { name = "Tailoring", level = 225, line = 197 }, { name = "Enchanting", level = 200, line = 333 } }
list = run()
check(wellFormed(list), "every idea has the contract's fields")
local rogue = find(list, "grind:5615")
check(rogue and near(rogue.perKill, 115 + 0.25 * 665, 0.001), "Wastewander Rogue: 115 coin + Mageweave")
local basilisk = find(list, "grind:5419")
check(basilisk == nil, "a basilisk gives only skins: nothing without Skinning")
check(find(list, "learn:393") == nil, "no free slot: no idea to learn Skinning")
check(find(list, "grind:5600") == nil, "friendly to the Horde: no")
local de = find(list, "disenchant:bags")
-- The green: 0.75 x 1.5 Strange Dust at 142 + 0.25 Lesser Magic Essence at 380 = 254.75, sold 100.
check(de and near(de.once, 0.75 * 1.5 * 142 + 0.25 * 380, 0.001) and near(num(de, L["More than selling them"]).copper, 254.75 - 100, 0.001),
	"disenchant the bags' green: worth more than its sale")
local deBuy = find(list, "disenchant:" .. GREEN2)
check(deBuy and near(deBuy.once, 254.75 - 100, 0.001) and deBuy.basis == "classic", "a green listed below its dust: buy and disenchant")
UnitFactionGroup = saved.faction

---------------------------------------------------------------------------
-- Level 60, a hunter with Herbalism, Skinning and Fishing, with records of her own
---------------------------------------------------------------------------

section("whypoor_methods: level 60 hunter")
PLAYER_LEVEL, PLAYER_CLASS = 60, "HUNTER"
PROFESSIONS = { { name = "Herbalism", level = 300, line = 182 }, { name = "Skinning", level = 300, line = 393 }, nil, { name = "Fishing", level = 300, line = 356 } }
-- Her own: 50 Blighted Horrors (300 coin each, Runecloth 18 times, one random green), 40 of them timed in 720 s
-- at level 60; 12 Plague Monstrosities timed in 240 s.
OWN[8521] = Own({ name = "Blighted Horror", kills = 50, money = 15000, items = { [14047] = { 15, 18, 1, "Runecloth" }, [GREEN] = { 1, 1, 2, "Green Belt" } },
	pace = { 60, 50, 0, 40, 720 }, levels = { 56, 57 } })
OWN[8522] = Own({ name = "Plague Monstrosity", kills = 12, money = 3600, items = {}, pace = { 60, 12, 0, 12, 240 }, levels = { 55, 56 } })
list = run()
check(wellFormed(list), "every idea has the contract's fields")
local horror = find(list, "grind:8521")
-- Her own: 300 coin + 18/50 Runecloth at 1425 (the green left out: a world drop) = 813; 18 s a fight + 20 s.
check(horror and near(horror.perKill, 300 + 0.36 * 1425, 0.001), "her own worth per kill (a world drop left out): " .. tostring(horror and horror.perKill))
check(horror and near(horror.killsPerHour, 3600 / 38, 0.001), "her own pace")
check(horror and horror.basis == "prices" and num(horror, L["Coin per kill"]).basis == "yours" and num(horror, L["Fight"]).basis == "yours",
	"her own numbers, Runecloth at the auction house's price")
check(horror and horror.confidence == "medium" and not warned(horror, L["Classic data: Forever may differ"]), "her own: medium (the rest between kills), no classic warning")
check(horror and horror.title == "Kill Blighted Horror", "her own record's name")
local monstrosity = find(list, "grind:8522")
-- Only coin from her 12 kills: fewer than 30, so the database's 300 coin; her pace: 20 s.
check(monstrosity and near(monstrosity.perKill, 300, 0.001) and near(monstrosity.killsPerHour, 3600 / 40, 0.001)
	and num(monstrosity, L["Coin per kill"]).basis == "classic" and num(monstrosity, L["Fight"]).basis == "yours",
	"few kills: the database's worth, her pace")
check(monstrosity and monstrosity.basis == "classic" and monstrosity.confidence == "medium", "the database's worth: classic")
local runt = find(list, "grind:8596")
-- Her damage: (3250 x 40 + 3050 x 12) / 960 s = 173.5 a second; the runt's 2850 health: 16.4 s.
local hps = (3250 * 40 + 3050 * 12) / 960
check(runt and near(runt.killsPerHour, 3600 / (2850 / hps + 22), 0.001),
	"a mob she never fought: its health over her damage: " .. tostring(runt and runt.killsPerHour))
check(runt and runt.basis == "estimate" and warned(runt, L["Fight time worked out from its health and your pace on other mobs"]), "said how")
check(runt and near(runt.perKill, 380, 0.001), "skinning at 300 skins level 55: Rugged Leather")
local ghoul = find(list, "grind:8597")
check(ghoul and ghoul.perHour == nil and ghoul.missing and ghoul.missing[1] == NOPRICE and ghoul.group == 3,
	"a mob whose drops have no price: listed, not ranked")
local plague = find(list, "gather:herb:1423")
-- (25 x 2 x 855 + 15 x 2 x 570) / 40 = 1496.25 a node.
check(plague and near(plague.perNode, (25 * 2 * 855 + 15 * 2 * 570) / 40, 0.001) and plague.nodes == 40, "herbs: the zone's nodes, weighted by how many")
check(plague and plague.confidence == "low" and plague.basis == "estimate", "herbs per hour: an estimate")
check(find(list, "gather:herb:1431") ~= nil, "Duskwood's herbs too")
local fish = find(list, "fish:1444")
check(fish and near(fish.perHour, (0.6 * 95 + 0.3 * 285) * 120, 0.01), "fishing where no fish get away")
check(find(list, "fish:1423") == nil, "skill 330 needed: no")
check(find(list, "learn:186") == nil, "no free slot: no idea to learn Mining")
check(warned(find(list, "quest:7"), L["At the highest level quests may pay more instead of experience: not counted"])
	and not warned(find(list, "quest:7"), L["A group quest"]), "at level 60: a quest's money for its experience isn't counted, said")
-- Ranking: confidence lowers.
local a = { key = "a", kind = "grind", perHour = 1000, confidence = "low", warnings = {} }
local b = { key = "b", kind = "grind", perHour = 800, confidence = "high", warnings = {} }
local c = { key = "c", kind = "quest", once = 100000, confidence = "high", warnings = {} }
local d = { key = "d", kind = "grind", confidence = "high", missing = { 1 }, warnings = {} }
local ranked = X.Rank({ d, c, a, b })
check(ranked[1] == b and ranked[2] == a and ranked[3] == c and ranked[4] == d, "high 800 before low 1000; once after; needs a price last")
local many = {}
for i = 1, 10 do many[i] = { key = "g" .. i, kind = "grind", perHour = i, confidence = "high", warnings = {} } end
check(#X.Rank(many) == X.KEEP.grind, "six grinding ideas at most")

---------------------------------------------------------------------------
-- Elites in a group, prices old and from a friend, the data missing
---------------------------------------------------------------------------

section("whypoor_methods: groups, old prices")
PLAYER_LEVEL, PLAYER_CLASS, PLAYER_MAP, PROFESSIONS = 5, "WARRIOR", 1429, {}
GROUP = "party"
list = run()
check(find(list, "grind:1") == nil, "an elite in a group, never fought: no (its speed isn't guessed)")
check(warned(find(list, "grind:6"), L["In a group: loot is shared, kills go faster. These numbers are for playing alone."]), "in a group: said")
OWN[1] = Own({ name = "Kobold Brute", kills = 4, money = 60, items = {}, pace = { 5, 6, 0, 6, 120 }, levels = { 3, 3 } })
list = run()
check(find(list, "grind:1") ~= nil, "an elite in a group with my own pace: yes")
GROUP = "none"
OWN[1] = nil
FIX[2589][3].age, FIX[2589][3].friend = 5 * 3600, "Anna"
priceRev = priceRev + 1
list = run()
vermin = find(list, "grind:6")
check(vermin and warned(vermin, L["Prices from %s"]:format("Anna")) and warned(vermin, L["Oldest price: %s"]:format(LT.Ago(NOW - 5 * 3600))),
	"a friend's old price: both said")
check(vermin and vermin.oldest == NOW - 5 * 3600, "the oldest price used")
FIX[2589][3].age, FIX[2589][3].friend = nil, nil
priceRev = priceRev + 1
dataLoaded = false
list = run()
check(find(list, "gather:herb:1429") == nil and find(list, "limited:" .. LIMITED) == nil, "without the money data: no nodes, no limited stock")
dataLoaded = true

---------------------------------------------------------------------------
-- The driver
---------------------------------------------------------------------------

section("whypoor_methods: driver")
list = run()
local rev = I.Revision()
local _, upToDate = I.Get()
check(upToDate == true, "up to date after a run")
-- Asked again with nothing changed: nothing runs, the watchers aren't told.
local told = 0
I.Watch(function() told = told + 1 end)
local started = X.lastStart
I.Request()
check(X.job == nil, "a request does nothing at once")
Advance(0.1)
check(X.lastStart == started and told == 0 and I.Revision() == rev and not X.frame:IsShown(), "nothing changed: no run, no call, hidden again")
-- A price changes: a run (5 s after the last start at the earliest); the list changes, the watchers hear on the
-- frame after.
FIX[4306][3].low = 200
priceRev = priceRev + 1
check(select(2, I.Get()) == true and #I.All() > 0, "a price changed: the last list still there and ready until a run works (the window shows it)")
local mobsOn, statuses = calls.MobsOn, calls.Status
X.UNITS = 5
I.Request()
Advance(1 / 60)
local waited = X.job == nil and X.pending and not X.frame:IsShown()
local mine, realAfter = 0, C_Timer.After
C_Timer.After = function(d, fn)
	local info = debug.getinfo(2, "S")
	if info and tostring(info.source):find("WhyPoor/Methods.lua", 1, true) then mine = mine + 1 end
	return realAfter(d, fn)
end
I.Request()
Advance(1 / 60)
I.Request()
Advance(1 / 60)
C_Timer.After = realAfter
check(mine == 0 and X.waiting and X.pending, "asked again while waiting: no second timer")
for _ = 1, 400 do
	Advance(1 / 60)
	if X.job then break end
end
check(waited and X.job ~= nil and X.lastStart ~= started, "the next run waits the gap (hidden meanwhile), then starts")
local p0 = I.Progress()
check(type(p0) == "table" and p0.step >= 1 and p0.steps == #X.PHASES and p0.step <= p0.steps, "while it runs: its step of the steps")
local frames, maxUnits, lastUnits = 0, 0, X.job and X.job.units or 0
while X.job do
	Advance(1 / 60)
	frames = frames + 1
	if X.job then
		maxUnits = math.max(maxUnits, X.job.units - lastUnits)
		lastUnits = X.job.units
	end
end
check(frames > 3 and maxUnits <= 5, "a run over frames, 5 units a frame at most without a clock: " .. frames .. " frames, " .. maxUnits)
check(calls.MobsOn == mobsOn, "the zones' mobs not looked at again for a price (the candidates kept)")
check(calls.Status - statuses <= 4, "which quests are open: kept (only the open ones' status asked again)")
check(I.Revision() == rev + 1 and told == 0, "the list changed: a new revision, the watchers not yet")
Advance(1 / 60)
check(told == 1 and find(I.All(), "flip:4306").once == 380 - 200, "the watchers on the frame after, the new numbers")
Advance(0.1)
check(not X.frame:IsShown(), "nothing runs idle")
-- A price changes while a run works: when it's done, the next run comes by itself (after the gap), no request
-- needed; meanwhile the list is there and ready.
priceRev = priceRev + 1
Advance(6)
I.Request()
Advance(1 / 60)
check(X.job ~= nil and select(2, I.Get()) == false, "a run works: not ready meanwhile")
priceRev = priceRev + 1
local frames2 = 0
while X.job and frames2 < 2000 do Advance(1 / 60); frames2 = frames2 + 1 end
check(X.job == nil and X.pending and select(2, I.Get()) == true and X.lastKey ~= X.Key(), "done, but a price changed meanwhile: ready, and another run due")
frames2 = 0
while (X.pending or X.job) and frames2 < 2000 do Advance(1 / 60); frames2 = frames2 + 1 end
check(X.lastKey == X.Key() and not X.frame:IsShown(), "that run came by itself (no request), up to date, then idle")
X.UNITS = 30
-- The budget: with a clock, a frame's units stop at 3 ms.
local clock = 0
debugprofilestop = function() clock = clock + 0.5; return clock end
Fire("SKILL_LINES_CHANGED")
X.lastStart = nil
I.Request()
Advance(1 / 60)
local perFrame = X.job and X.job.units or 0
check(perFrame >= 1 and perFrame <= 7, "a frame's work stops at the budget: " .. perFrame .. " units")
while X.job or X.pending do Advance(1 / 60) end
debugprofilestop = nil
-- A level up starts at once (no gap) and scans the zones again.
mobsOn = calls.MobsOn
PLAYER_LEVEL = 6
Fire("PLAYER_LEVEL_UP", 6)
I.Request()
Advance(1 / 60)
check(X.job ~= nil, "a level up: a run at once")
while X.job or X.pending do Advance(1 / 60) end
check(calls.MobsOn > mobsOn, "another level: the zones looked at again")
PLAYER_LEVEL = 5
Fire("PLAYER_LEVEL_UP", 5)
-- Lodestar switched off: no quests (its data isn't loaded for us).
local lodestar = LT:GetModule("lodestar")
lodestar.enabled = false
list = run()
check(find(list, "quest:7") == nil and find(list, "grind:6") ~= nil, "Lodestar off: no quests, the rest still")
lodestar.enabled = true
-- An error in a part: reported once, the run dropped, nothing runs every frame.
local errors, stop = catchErrors()
Dt.Spots = function() error("broken spots") end
Fire("ZONE_CHANGED_NEW_AREA")
X.cand = nil
X.lastStart = nil
I.Request()
Advance(0.5)
check(#errors == 1 and errors[1]:find("broken spots", 1, true) and X.job == nil and not X.frame:IsShown(), "an error: reported once, the run dropped, hidden")
check(I.Progress() == nil and select(2, I.Progress()) == true, "its progress: no run, the last one failed (the window says so)")
stop()
Dt.Spots = function(cr) return SPOTS[cr] end
Advance(2) -- (the failed hook rests a second)
list = run()
check(find(list, "grind:6") ~= nil, "it works again once the part does")
check(select(2, I.Progress()) == false, "and the failure is forgotten")

---------------------------------------------------------------------------
-- Worth your time: what the shown list keeps
---------------------------------------------------------------------------

section("whypoor_methods: worth your time")
do
	local YOUNG = 90008
	FIX[YOUNG] = { "New Thing", 10, { value = 2000, low = 1900, qty = 5, perDay = 5, sells = 0.9, confidence = "high", days = 1 } }
	local realGoal, rate, own = W.Goal, nil, nil
	W.Goal = { Rate = function() return rate end, OwnBar = function() return own end }
	local bar = X.Bar({ level = 30 })
	check(bar.hour == 30000 and bar.once == 15000 and bar.how == "level", "no pace of your own: the bar by level (30: 3g an hour, 1g 50s once)")
	rate = 40000
	bar = X.Bar({ level = 30 })
	check(bar.hour == 60000 and bar.once == 30000 and bar.how == "rate", "your own 4g an hour played: the bar half again that (6g; 3g once)")
	rate = 5000
	bar = X.Bar({ level = 30 })
	check(bar.hour == 7500 and bar.how == "rate" and bar.rate == 5000, "50s an hour played: the bar 75s, below the level's 3g (your own pace wins)")
	rate = 1000
	bar = X.Bar({ level = 30 })
	check(bar.hour == 6000 and bar.how == "least", "10s an hour played: the bar at least 2s a level (60s)")
	rate = -2000
	bar = X.Bar({ level = 30 })
	check(bar.hour == 30000 and bar.how == "spent", "your gold went down: by level, said so")
	own = 20000
	bar = X.Bar({ level = 30 })
	check(bar.hour == 20000 and bar.once == 10000 and bar.how == "own", "your own bar wins: 2g an hour, 1g once")
	rate, own = nil, nil
	local function Idea(key, kind, perHour, once, items)
		return { key = key, kind = kind, perHour = perHour, once = once, items = items or {}, why = {}, how = {}, warnings = {},
			numbers = {}, confidence = "medium", basis = "prices" }
	end
	local ideas = {
		Idea("grind:a", "grind", 50000, nil, { { item = 2589, n = 600, each = 57, source = "ah" } }),
		Idea("grind:b", "grind", 20000, nil, { { item = 2589, n = 100, each = 57, source = "ah" } }),
		Idea("grind:c", "grind", 60000, nil, { { item = YOUNG, n = 25, each = 1900, source = "ah" } }),
		Idea("grind:d", "grind", 40000, nil, { { item = 750, n = 10, each = 0, source = "vendor" } }),
		Idea("quest:e", "quest", nil, 100000),
		Idea("flip:f", "flip", nil, 20000, { { item = 4306, n = 1, each = 250, source = "ah" } }),
		Idea("craft:g", "craft", nil, 5000, { { item = 1251, n = 1, each = 110, source = "ah" } }),
	}
	local kept, hidden = X.Worth({ level = 30, ideas = ideas })
	local keys = {}
	for _, idea in ipairs(kept) do keys[#keys + 1] = idea.key end
	check(table.concat(keys, ",") == "grind:a,grind:d,flip:f", "kept: what beats the bar on solid prices, got " .. table.concat(keys, ","))
	check(ideas[1].star == 2589 and ideas[1].why[1]:find("3g", 1, true) and ideas[1].why[2]:find("Linen Cloth", 1, true),
		"its main item (for the price graph) and why it's worth it: " .. tostring(ideas[1].why[1]))
	check(ideas[4].star == nil, "money from coin and vendors: solid, no item to graph")
	check(hidden.n == 4 and hidden.young == 1 and hidden.bar.hour == 30000, "left out: below the bar, a price only a day old (said), a quest, a small craft")
	-- After a run: the shown list is the part of every idea worked out that's worth it.
	local all, shown = run(), I.Get()
	local inAll = {}
	for _, idea in ipairs(all) do inAll[idea.key] = true end
	local subset = true
	for _, idea in ipairs(shown) do subset = subset and inAll[idea.key] == true end
	check(subset and #shown <= #all and type(I.Hidden()) == "table" and I.Hidden().n == #all - #shown,
		"the window's list: those worth it, the rest counted (" .. #shown .. " of " .. #all .. ")")
	W.Goal = realGoal
	FIX[YOUNG] = nil
end

---------------------------------------------------------------------------
-- Put back
---------------------------------------------------------------------------

W.Prices, W.Data, W.Crafts, W.Bags = saved.Prices, saved.Data, saved.Crafts, saved.Bags
Bt.Known, Bt.Mob, Bt.Data, Bt.NameOf = saved.Known, saved.Mob, saved.BtData, saved.NameOf
for _, k in ipairs({ "Load", "Zones", "ZoneQuests", "Status", "InRange", "Rewards", "Quest", "Group" }) do Q[k] = saved["Q" .. k] end
for id, item in pairs(saved.items) do ITEMS[id] = item or nil end
for map, name in pairs(saved.maps) do MAP_NAMES[map] = name or nil end
PLAYER_LEVEL, PLAYER_CLASS, PLAYER_MAP, PROFESSIONS = 19, "ROGUE", 1429, {}
X.watchers = {}
X.list, X.signature, X.lastKey, X.cand = {}, nil, nil, nil
