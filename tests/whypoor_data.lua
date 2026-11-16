-- WhyPoor?: the money data add-on and its reader (Data.lua; docs/whypoor.md, The money data): nothing loaded at
-- login, the add-on asked for once (missing: the reason), loaded since by someone else: taken; a small fixture
-- in the add-on's format through every accessor (mobs, spots, zones, nodes, fishing and its subzones,
-- pickpocketing, disenchanting, limited stock and vendors; entries read once and kept, the data staying
-- strings); then the real generated file (LefthyTools_MoneyData/MoneyData.lua): its format (every entry of
-- every table reads), and facts from the game and its client (gathering skills, city guards' reactions,
-- fishing skills, a pickpocket, disenchanting, limited stock). Leaves Data.lua as it found it (nothing loaded).
-- Needs: no other file.
local suite = ...
local check, section, ns, LT = suite.check, suite.section, suite.ns, suite.LT

section("whypoor_data")
check(ns.WhyPoor ~= nil and LT:GetModule("whypoor") ~= nil, "the module is there")
local Dt = ns.WhyPoor and ns.WhyPoor.Data

local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-9 end
local function find(list, key, value)
	for _, v in ipairs(list or {}) do if v[key] == value then return v end end
end

section("WhyPoor? data: loaded only when asked")
do
	check(type(Dt) == "table" and Dt.Load and Dt.Mob and Dt.Spots and Dt.MobsOn and Dt.Nodes and Dt.Fishing and Dt.Pickpocket
		and Dt.Disenchant and Dt.Limited and Dt.LimitedItems, "the contract's functions are there")
	check(LefthyToolsMoneyData == nil and not Dt.IsLoaded() and Dt.Problem() == nil, "nothing loaded at login, nothing asked")

	local loads, loader = {}, C_AddOns.LoadAddOn
	C_AddOns.LoadAddOn = function(name) loads[#loads + 1] = name; return false, "MISSING" end
	check(Dt.Mob(68) == nil and Dt.Problem() == "MISSING" and loads[1] == "LefthyTools_MoneyData", "missing: nothing, and why")
	check(Dt.Load() == false and #Dt.MobsOn(1429) == 0 and #Dt.Nodes(1429) == 0 and Dt.Fishing(1429) == nil and #Dt.LimitedItems() == 0
		and #loads == 1, "asked only once; empty answers")
	LefthyToolsMoneyData = { source = "test", build = "1.60.1.1", mobs = { [1] = "Test Mob|n|7||h|h|300" } }
	check(Dt.Load() == true and Dt.Problem() == nil and Dt.Mob(1).name == "Test Mob" and #loads == 1, "loaded since by someone else: taken")
	check(Dt.Info().source == "test" and Dt.Info().build == "1.60.1.1", "what it says about itself")
	C_AddOns.LoadAddOn = loader
end

section("WhyPoor? data: a fixture through every accessor")
do
	local raw = {
		source = "fixture", build = "1.60.1.2",
		mobs = {
			[113] = "Stonetusk Boar|n|1|l|n|n|180|||1429,363,861,76,36;1429,409,726,48,14,7.5",
			[68] = "Stormwind City Guard|n|7||f|h|300||72|1453,667,779,61,11",
			[2578] = "Young Mesa Buzzard|R|1||n|h|400|H",
			[1731] = "Goblin Craftsman|e|7||h|h|7200|ic",
		},
		zones = { [1429] = "113,116", [1453] = "68" },
		objects = {
			[1618] = "Peacebloom|herb|1|300|1|2447:10000:1-3",
			[1731] = "Copper Vein|ore|1|300|2-4|2770:10000,2835:4400:1-2,774:100",
			[180582] = "Oily Blackmouth School|fish|0|135|2-6|6358:8500,3820:500:1-3",
		},
		nodes = { [1429] = "1618:47:8=410,587,68,6,1.6;650,624,66,6|1731:20:3.5=100,200,30,4|999:1:1=1,1,15,1" },
		fishing = { [1429] = "-70|6291:5880,6289:4000", [1434] = "130|8365:5840,13889:500::e" },
		fishingAreas = { [87] = "1429|Goldshire|-20|6291:9000", [5000] = "1434|Somewhere|205|8365:100", [6000] = "1437|Elsewhere|1|6291:1" },
		pickpocket = { [116] = "6150:786,2589:30:2,5000:10:1:A" },
		disenchant = { [864] = 26, [2303] = "1:25", [5] = 99 },
		disenchantLoot = { [1] = "10940:8000:1-2,10938:2000:1-2", [26] = "11134:7500:1-2,11083:2000:2-5" },
		limited = { [6270] = "200|1|f|66:1:9000;3364:1:7200", [4565] = "12|5|c|999:2:3600" },
		vendors = { [66] = "Tharynn Bouden|f|h|1429,418,672", [3364] = "Borya|h|f|1454,630,513" },
	}
	Dt.Use(raw)
	local boar = Dt.Mob(113)
	check(boar and boar.name == "Stonetusk Boar" and boar.rank == "normal" and boar.type == "Beast" and boar.skin == "leather"
		and boar.reactA == "neutral" and boar.reactH == "neutral" and boar.respawn == 180 and boar.instance == false and boar.rep == nil
		and boar.basis == "classic", "a mob: every field")
	local spots = Dt.Spots(113)
	check(#spots == 2 and spots[1].map == 1429 and near(spots[1].x, 0.363) and near(spots[1].y, 0.861) and near(spots[1].r, 0.076)
		and spots[1].n == 36 and spots[1].up == 36 and spots[2].n == 14 and spots[2].up == 7.5, "its spots: clusters, up only when given")
	local guard = Dt.Mob(68)
	check(guard.reactA == "friendly" and guard.reactH == "hostile" and guard.rep == 72 and guard.spots[1].map == 1453, "a guard: friendly to its side, a reputation")
	local buzzard = Dt.Mob(2578)
	check(buzzard.rank == "rareelite" and buzzard.seenH == true and buzzard.seenA == nil and Dt.Spots(2578) == nil, "seen by players; no spots: nil")
	local inside = Dt.Mob(1731)
	check(inside.rank == "elite" and inside.instance == true and inside.civilian == true and inside.spots == nil, "only in dungeons; a civilian")
	check(Dt.Mob(999) == nil and Dt.Mob(nil) == nil and Dt.Mob(113) == boar, "unknown: nil; read once and kept")
	local on = Dt.MobsOn(1429)
	check(#on == 2 and on[1] == 113 and on[2] == 116 and #Dt.MobsOn(1) == 0, "the mobs on a map")

	local nodes = Dt.Nodes(1429)
	local herb, ore = find(nodes, "object", 1618), find(nodes, "object", 1731)
	check(#nodes == 2 and herb and herb.name == "Peacebloom" and herb.kind == "herb" and herb.skill == 1 and herb.n == 47 and herb.up == 8
		and herb.uses[1] == 1 and herb.uses[2] == 1 and herb.respawn == 300 and herb.basis == "classic", "a herb node; an unknown object left out")
	check(herb.loot[1].item == 2447 and herb.loot[1].chance == 1 and herb.loot[1].min == 1 and herb.loot[1].max == 3, "its loot: item, chance, count")
	check(#herb.spots == 2 and near(herb.spots[1].x, 0.41) and herb.spots[1].up == 1.6 and herb.spots[2].up == 6 and herb.spots[1].map == nil,
		"its spots on the map")
	check(ore.kind == "ore" and ore.uses[1] == 2 and ore.uses[2] == 4 and near(ore.loot[2].chance, 0.44) and ore.loot[2].max == 2
		and ore.loot[3].min == 1 and ore.loot[3].max == 1 and ore.up == 3.5, "a vein: mined 2-4 times, stones 44%")
	check(Dt.Object(180582).kind == "fish" and Dt.Object(180582).uses[2] == 6 and #Dt.Nodes(1) == 0, "a school; no nodes elsewhere")

	local elwynn = Dt.Fishing(1429)
	check(elwynn and elwynn.base == -70 and elwynn.low == 1 and elwynn.skill == 25 and elwynn.basis == "classic"
		and elwynn.loot[1].item == 6291 and near(elwynn.loot[1].chance, 0.588), "Elwynn: catches from 1, sure from 25")
	check(#elwynn.areas == 1 and elwynn.areas[1].area == 87 and elwynn.areas[1].name == "Goldshire" and elwynn.areas[1].skill == 75
		and elwynn.areas[1].low == 1 and elwynn.areas[1].loot[1].chance == 0.9, "a subzone that differs")
	local stv = Dt.Fishing(1434)
	check(stv.low == 130 and stv.skill == 225 and stv.loot[2].event == true and stv.loot[2].min == 1 and stv.areas[1].skill == 300
		and Dt.Fishing(1) == nil and Dt.Fishing(1429) == elwynn, "Stranglethorn: 130 to catch, 225 sure; an event's fish; kept")

	local pockets = Dt.Pickpocket(116)
	check(#pockets == 3 and pockets[1].item == 6150 and near(pockets[1].chance, 0.0786) and pockets[2].min == 2 and pockets[2].max == 2
		and pockets[3].side == "Alliance" and Dt.Pickpocket(1) == nil, "pickpocketing")
	local sword, pants = Dt.Disenchant(864), Dt.Disenchant(2303)
	check(sword and sword.skill == 1 and sword.results[1].item == 11134 and near(sword.results[1].chance, 0.75) and sword.results[2].max == 5
		and pants.skill == 25 and pants.results[1].item == 10940 and Dt.Disenchant(5) == nil and Dt.Disenchant(6) == nil,
		"disenchanting: results, the skill, a group without results")
	local vest = Dt.Limited(6270)
	check(#vest == 2 and vest[1].npc == 66 and vest[1].name == "Tharynn Bouden" and vest[1].map == 1429 and near(vest[1].x, 0.418)
		and vest[1].reactA == "friendly" and vest[1].reactH == "hostile" and vest[1].stock == 1 and vest[1].restock == 9000
		and vest[1].price == 200 and vest[1].count == 1 and vest[1].basis == "forever" and vest[2].reactH == "friendly", "limited stock")
	local unknownVendor = Dt.Limited(4565)[1]
	check(unknownVendor.npc == 999 and unknownVendor.name == nil and unknownVendor.map == nil and unknownVendor.count == 5
		and unknownVendor.basis == "classic" and Dt.Limited(1) == nil, "a vendor the data doesn't place; classic's price")
	local items = Dt.LimitedItems()
	check(#items == 2 and items[1] == 4565 and items[2] == 6270, "every limited item, sorted")
	check(type(raw.mobs[113]) == "string" and type(raw.nodes[1429]) == "string", "the data stays strings")
end

section("WhyPoor? data: the real generated file")
do
	local loader = C_AddOns.LoadAddOn
	Dt.db, Dt.tried, Dt.why, Dt.cache = nil, false, nil, {}
	LefthyToolsMoneyData = nil
	C_AddOns.LoadAddOn = function(name)
		assert(name == "LefthyTools_MoneyData")
		assert(loadfile("LefthyTools_MoneyData/MoneyData.lua"))()
		return true
	end
	check(Dt.Load() == true and Dt.Info().source:find("CMaNGOS", 1, true) and Dt.Info().build:match("^1%.60%."), "it loads; its source and build")
	C_AddOns.LoadAddOn = loader
	local db = LefthyToolsMoneyData

	-- Its format: every entry of every table reads into the contract's shapes.
	local bad, count = {}, {}
	local REACT = { hostile = true, neutral = true, friendly = true }
	local function okLoot(list)
		for _, l in ipairs(list or {}) do
			if not (l.item > 0 and l.chance > 0 and l.chance <= 1 and l.min >= 1 and l.max >= l.min) then return false end
		end
		return list ~= nil and #list > 0
	end
	local function okSpot(s, withMap)
		return s and (not withMap or s.map > 0) and s.x >= 0 and s.x <= 1 and s.y >= 0 and s.y <= 1 and s.r > 0 and s.r <= 0.15 and s.n >= 1 and s.up > 0 and s.up <= s.n + 1e-9
	end
	for id in pairs(db.mobs) do
		count.mobs = (count.mobs or 0) + 1
		local m = Dt.Mob(id)
		local ok = m and m.name ~= "" and m.rank and (m.reactA == nil or REACT[m.reactA]) and (m.reactH == nil or REACT[m.reactH])
			and m.respawn and m.respawn >= 0 -- (no spots: in dungeons, or outdoors where no zone map is: a shark at sea)
		for _, s in ipairs(m and m.spots or {}) do ok = ok and okSpot(s, true) end
		-- (never a mob both sides see as friends, nor one of a reputation neither starts hostile with)
		ok = ok and not (m.reactA == "friendly" and m.reactH == "friendly") and not (m.rep and m.reactA ~= "hostile" and m.reactH ~= "hostile")
		if not ok and #bad < 5 then bad[#bad + 1] = "mob " .. id end
	end
	for map in pairs(db.zones) do
		for _, id in ipairs(Dt.MobsOn(map)) do
			if not (Dt.Mob(id) and Dt.Mob(id).spots) and #bad < 5 then bad[#bad + 1] = "zone " .. map .. " mob " .. id end
		end
	end
	local KINDS = { herb = true, ore = true, chest = true, fish = true }
	for map, text in pairs(db.nodes) do
		local list = Dt.Nodes(map)
		local _, parts = text:gsub("|", "")
		local ok = #list == parts + 1
		for _, nd in ipairs(list) do
			count.nodes = (count.nodes or 0) + 1
			ok = ok and KINDS[nd.kind] and nd.skill >= 0 and nd.n >= 1 and nd.up > 0 and nd.uses[1] >= 1 and nd.uses[2] >= nd.uses[1] and okLoot(nd.loot) and #nd.spots >= 1
			for _, s in ipairs(nd.spots) do ok = ok and okSpot(s, false) end
		end
		if not ok and #bad < 5 then bad[#bad + 1] = "nodes " .. map end
	end
	for map in pairs(db.fishing) do
		local f = Dt.Fishing(map)
		local ok = f and f.skill == math.max(1, f.base + 95) and okLoot(f.loot)
		for _, a in ipairs(f and f.areas or {}) do ok = ok and a.name ~= "" and okLoot(a.loot) end
		if not ok and #bad < 5 then bad[#bad + 1] = "fishing " .. map end
	end
	for id in pairs(db.pickpocket) do
		if not (Dt.Mob(id) and okLoot(Dt.Pickpocket(id))) and #bad < 5 then bad[#bad + 1] = "pickpocket " .. id end
	end
	for item in pairs(db.disenchant) do
		count.disenchant = (count.disenchant or 0) + 1
		local d = Dt.Disenchant(item)
		if not (d and d.skill >= 1 and okLoot(d.results)) and #bad < 5 then bad[#bad + 1] = "disenchant " .. item end
	end
	for _, item in ipairs(Dt.LimitedItems()) do
		local list = Dt.Limited(item)
		local ok = list and #list >= 1
		for _, v in ipairs(list or {}) do ok = ok and v.name and v.stock >= 1 and v.restock >= 0 and v.price >= 0 and v.count >= 1 and (v.map == nil or v.x) end
		if not ok and #bad < 5 then bad[#bad + 1] = "limited " .. item end
	end
	check(#bad == 0, "every entry reads into the contract's shapes, bad: " .. table.concat(bad, ", "))
	check((count.mobs or 0) > 3000 and (count.nodes or 0) > 300 and (count.disenchant or 0) > 5000 and #Dt.LimitedItems() > 200,
		"it holds a world's worth: " .. tostring(count.mobs) .. " mobs, " .. tostring(count.nodes) .. " nodes, " .. tostring(count.disenchant) .. " disenchantable items")

	-- Facts: gathering skills (Forever's client's Lock table) on Elwynn Forest, Westfall, Arathi Highlands' maps.
	local function node(map, name)
		for _, nd in ipairs(Dt.Nodes(map)) do if nd.name == name then return nd end end
	end
	local function gives(nd, item)
		return nd and nd.loot[1] and nd.loot[1].item == item and nd.loot[1].chance == 1
	end
	local peace, silver, copper = node(1429, "Peacebloom"), node(1429, "Silverleaf"), node(1429, "Copper Vein")
	check(peace and peace.kind == "herb" and peace.skill == 1 and gives(peace, 2447) and silver and silver.skill == 1 and gives(silver, 765),
		"Peacebloom and Silverleaf: Herbalism 1, in Elwynn Forest")
	check(copper and copper.kind == "ore" and copper.skill == 1 and gives(copper, 2770) and copper.uses[2] > 1, "Copper Vein: Mining 1, mined more than once")
	local skills = {}
	for _, map in ipairs({ 1429, 1436, 1431, 1433, 1417, 1426, 1432, 1437, 1438, 1411, 1413, 1418 }) do
		for _, nd in ipairs(Dt.Nodes(map)) do skills[nd.name] = nd.skill end
	end
	check(skills["Mageroyal"] == 50 and skills["Briarthorn"] == 70 and skills["Tin Vein"] == 65 and skills["Silver Vein"] == 75
		and skills["Iron Deposit"] == 125, "Mageroyal 50, Briarthorn 70, Tin 65, Silver 75, Iron 125")
	-- City guards: friendly to their own side, hostile to the other.
	local swGuard, grunt = Dt.Mob(68), Dt.Mob(3296)
	check(swGuard and swGuard.name == "Stormwind City Guard" and swGuard.reactA == "friendly" and swGuard.reactH == "hostile",
		"a Stormwind City Guard: friendly to the Alliance, hostile to the Horde")
	check(grunt and grunt.name == "Orgrimmar Grunt" and grunt.reactH == "friendly" and grunt.reactA == "hostile", "an Orgrimmar Grunt: the other way round")
	check(Dt.Mob(4624) == nil, "Booty Bay's bruisers (neutral to both by reputation) aren't mobs to farm")
	local boar = Dt.Mob(113)
	check(boar and boar.skin == "leather" and boar.type == "Beast" and boar.spots[1].map == 1429, "Stonetusk Boar: skinnable, in Elwynn Forest")
	-- Fishing: Elwynn sure from 25, Stranglethorn from 225 (130 to catch anything).
	local elwynn, stv = Dt.Fishing(1429), Dt.Fishing(1434)
	check(elwynn and elwynn.skill == 25 and elwynn.low == 1 and find(elwynn.loot, "item", 6291) and find(elwynn.loot, "item", 6289),
		"Elwynn Forest's fishing: sure from 25, Brilliant Smallfish and Longjaw Mud Snapper")
	check(stv and stv.low == 130 and stv.skill == 225, "Stranglethorn Vale's fishing: 130 to catch, 225 sure")
	-- Pickpocketing, disenchanting, limited stock.
	check(Dt.Pickpocket(116) and #Dt.Pickpocket(116) > 0 and Dt.Mob(116).name == "Defias Bandit", "a Defias Bandit's pockets")
	local ring = Dt.Disenchant(1077)
	check(ring and ring.skill == 1 and ring.results[1].item == 11083 and ring.results[1].chance >= 0.6, "a green ring of level 26: Soul Dust mostly")
	local pants = Dt.Disenchant(2303)
	check(pants and pants.results[1].item == 10940, "Handstitched Leather Pants (green on Forever): Strange Dust")
	local vest = Dt.Limited(6270)
	local tharynn = find(vest, "npc", 66)
	check(tharynn and tharynn.name == "Tharynn Bouden" and tharynn.map == 1429 and tharynn.stock == 1 and tharynn.restock == 9000
		and tharynn.reactA == "friendly" and tharynn.basis == "forever" and tharynn.price > 0, "Pattern: Blue Linen Vest, one at a time at Tharynn Bouden")
	check(type(db.mobs[68]) == "string", "the data stays strings")

	-- (as found: nothing loaded, nothing asked)
	Dt.db, Dt.tried, Dt.why, Dt.cache = nil, false, nil, {}
	LefthyToolsMoneyData = nil
end
