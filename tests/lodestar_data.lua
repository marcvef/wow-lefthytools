-- Lodestar's data and engine (Modules/Lodestar/Data.lua, Engine.lua; docs/lodestar.md): the quest
-- data add-on loaded only when asked, once; the real generated data (LefthyTools_QuestData/QuestData.lua)
-- through the accessors: quests, givers and their places, zones, dungeons, search; real chains (Elwynn
-- Forest's Northshire, Westfall's Defias Brotherhood, a Forever chain); where a quest stands with a
-- made-up progress (done, in the log, locked, too low, not for me), what's missing across zones,
-- exclusive groups, what's next; Forever's races (the Skyborne) and the race rule, item starters'
-- drops, who gives what, zone counts over every level, chain steps, what's available nearby, quest
-- difficulty colours; objectives (kill, collect, use) with their places, rewards, the turn-in, Forever's
-- levels and ones that scale; my levels (Q.InRange: nothing red or coming up, no event's), for my level
-- (Q.ForMyLevel) and event quests (Q.IsEvent); with the real data, every zone's count for a level-22 Horde
-- Skyborne and a level-22 Human (nothing of the other side, nothing locked or an event's; the Alliance's
-- zones empty for the Horde but for quests both sides take); learned data filling gaps only; the test
-- hook Q.SetTestData.
-- Needs: no other file.

local suite = ...
local check, section, ns = suite.check, suite.section, suite.ns
local Q = ns.Lodestar

local function has(list, v)
	for _, x in ipairs(list or {}) do if x == v then return true end end
	return false
end
local function at(list, v)
	for i, x in ipairs(list or {}) do if x == v then return i end end
end

-- My progress, the game's way: completed quests and the quest log (the mock's QUESTS).
local completed = {}
C_QuestLog.GetAllCompletedQuestIDs = function()
	local list = {}
	for id in pairs(completed) do list[#list + 1] = id end
	return list
end
local savedQuests, savedLevel, savedMap = QUESTS, PLAYER_LEVEL, PLAYER_MAP
QUESTS, PLAYER_LEVEL, PLAYER_MAP = {}, 1, 1429
local function login(list) -- the server's completed quests, read again after a loading screen
	completed = {}
	for _, id in ipairs(list or {}) do completed[id] = true end
	Fire("PLAYER_ENTERING_WORLD", false, false)
end
local function inLog(list)
	QUESTS = {}
	for _, id in ipairs(list) do QUESTS[#QUESTS + 1] = { id = id, title = "Quest " .. id, objectives = {} } end
	Fire("QUEST_ACCEPTED", list[#list])
end

section("Lodestar data: loaded only when asked")
do
	check(type(Q) == "table" and Q.Load and Q.Quest and Q.Status and Q.SetTestData, "the data and engine are there")
	check(LefthyToolsQuestData == nil, "nothing loaded at login")
	check(Q.Quest(176) == nil and #Q.Zones() == 0 and #Q.Search("hogger") == 0 and Q.Status(176) == nil and #Q.Next() == 0,
		"without data: no quests, zones, search hits, status or next steps")
	check(Q.HasData() == false and Q.DataProblem() == nil, "not there yet (the mock has no add-on list), nothing tried")

	-- Learned before the data is there: it waits.
	Q.AddLearned(176, { title = "Learned Hogger", starts = { { kind = "npc", id = 999990, name = "Not The Poster" } } })
	Q.AddLearned(999001, { title = "A Learned Quest", level = 7, zone = 1429, pre = { 783 },
		starts = { { kind = "npc", id = 999991, name = "Learned Giver", points = { { map = 1429, x = 0.5, y = 0.5 } } } } })

	-- The add-on missing: asked once, the reason kept.
	local loads, loader = {}, C_AddOns.LoadAddOn
	C_AddOns.LoadAddOn = function(name) loads[#loads + 1] = name; return false, "MISSING" end
	check(Q.Load() == false and Q.DataProblem() == "MISSING" and loads[1] == "LefthyTools_QuestData", "missing: Load says no, and why")
	check(Q.Load() == false and #loads == 1 and Q.HasData() == false, "asked only once")

	-- There: the real data.
	C_AddOns.LoadAddOn = function(name)
		loads[#loads + 1] = name
		assert(loadfile("LefthyTools_QuestData/QuestData.lua"))()
		return true
	end
	check(Q.Load() == false and #loads == 1, "still not asked again")
	assert(loadfile("LefthyTools_QuestData/QuestData.lua"))() -- (the add-on loaded by someone else meanwhile)
	check(Q.HasData() == true and Q.Load() == true and Q.DataProblem() == nil, "loaded since: taken")
	check(Q.Load() == true and #loads == 1, "loaded once")
	C_AddOns.LoadAddOn = loader
	local info = Q.DataInfo()
	check(info and info.quests > 5000 and info.build:match("^1%.60%.") and info.source:find("CMaNGOS", 1, true)
		and info.source:find("EG Link", 1, true), "the data says what it is: " .. tostring(info and info.quests) .. " quests, " .. tostring(info and info.build))
end

section("Lodestar data: quests, givers, places")
do
	local hogger = Q.Quest(176)
	check(hogger and hogger.title == 'Wanted:  "Hogger"' and hogger.level == 11 and hogger.minLevel == 5 and hogger.zone == 1429
		and hogger.zoneName == "Elwynn Forest" and hogger.faction == "Alliance" and hogger.source == "classic" and not hogger.new,
		"Wanted: Hogger: its title, levels, zone, faction (learned title not taken)")
	check(hogger.races == 77 + 2 ^ 32 and hogger.classes == nil and hogger.repeatable == false,
		"races as a mask (the Alliance's: classic's four and the High Order Skyborne), no class")
	local poster = hogger.starts[1]
	check(#hogger.starts == 2 and poster.kind == "object" and poster.name and #hogger.ends == 1, "given by the wanted posters (objects), the learned giver not added")
	local dughan = hogger.ends[1]
	local p = dughan.points[1]
	check(dughan.kind == "npc" and dughan.id == 240 and dughan.name == "Marshal Dughan" and p and p.map == 1429
		and suite.near(p.x, 0.421, 0.002) and suite.near(p.y, 0.659, 0.002), "taken by Marshal Dughan in Goldshire, 42.1, 65.9")
	check(Q.Quest(54).ends[1] == dughan, "a giver's table is shared by its quests")
	check(Q.Quest(166).dungeon == "Deadmines" and Q.Quest(166).zone == nil and Q.Quest(166).zoneName == "Deadmines", "a dungeon quest: its dungeon, no zone")
	local warrior = Q.Quest(1638)
	check(warrior.classes == 1 and warrior.sort == "Warrior" and has(warrior.excl, 1679) and has(warrior.excl, 1684), "a class quest: the class, its sort, the exclusive ones")
	check(Q.Quest(1097).breadcrumbFor == 353 and has(Q.Quest(1097).opens, 353), "a breadcrumb leads to its quest")
	check(Q.Quest(784).faction == "Horde", "a Horde quest")
	local new = Q.Quest(91743)
	check(new and new.new and new.source == "forever" and new.title == "Rascally Rodents" and new.zone == 1429,
		"a quest new in WoW: Forever, from its own data")
	check(Q.Quest(999999999) == nil and Q.Quest("x") == nil, "unknown: nil")

	-- Where zones' rectangles overlap the game's map decides: Farmer Saldean stands where Westfall's
	-- and Elwynn Forest's rectangles overlap.
	local mapAt = C_Map.GetMapInfoAtPosition
	local asked
	C_Map.GetMapInfoAtPosition = function(map, x, y) asked = { map, x, y }; return C_Map.GetMapInfo(1429) end
	local saldean = Q.Quest(9).starts[1]
	C_Map.GetMapInfoAtPosition = mapAt
	check(saldean.id == 233 and saldean.points[1].map == 1429 and suite.near(saldean.points[1].x, 0.138, 0.002) and asked and asked[1] == 1415,
		"an overlap: the zone the game's continent map has there")
	check(Q.Quest(64).starts[1].points[1].map == 1436, "without the game's word: the tool's guess (Westfall)")
end

section("Lodestar data: zones, dungeons, search")
do
	local zones = Q.Zones()
	local elwynn
	for i, z in ipairs(zones) do
		if z.map == 1429 then elwynn = z end
		local nextZone = zones[i + 1]
		if nextZone and (nextZone.continent < z.continent or (nextZone.continent == z.continent and nextZone.minLevel < z.minLevel)) then
			elwynn = false
			break
		end
	end
	check(#zones > 40 and elwynn and elwynn.name == "Elwynn Forest" and elwynn.continent == 1415 and elwynn.count > 100
		and elwynn.minLevel >= 1 and elwynn.maxLevel <= 15, "zones by continent, then level; Elwynn Forest with its quests")
	local list = Q.ZoneQuests(1429)
	check(#list == elwynn.count and has(list, 176) and has(list, 999001), "a zone's quests (with a learned one)")
	local sorted = true
	for i = 2, #list do
		local a, b = Q.Quest(list[i - 1]), Q.Quest(list[i])
		if (a.level or a.minLevel or 0) > (b.level or b.minLevel or 0) then sorted = false end
	end
	check(sorted, "the lowest level first")
	local deadmines
	for _, d in ipairs(Q.Dungeons()) do if d.name == "Deadmines" then deadmines = d end end
	check(deadmines and deadmines.count >= 5 and has(Q.DungeonQuests("Deadmines"), 166) and deadmines.minLevel >= 15,
		"dungeons: the Deadmines with its quests")
	local hits = Q.Search("hogger")
	check(hits[1] == 176 or (has(hits, 176) and at(hits, 176) <= 3), "search: by title")
	check(has(Q.Search("Marshal Dughan"), 54) and has(Q.Search("  DUGHAN "), 176), "search: by giver or ender, any case")
	check(#Q.Search("") == 0 and #Q.Search("zzqqxx") == 0, "nothing for nothing")
end

section("Lodestar data: races, item drops, who gives what")
do
	local races, byId = Q.Races(), {}
	for _, r in ipairs(races) do byId[r.id] = r end
	check(#races == 10 and byId[1].bit == 0 and byId[1].classic and byId[8].faction == "Horde"
		and byId[95].bit == 32 and byId[95].faction == "Alliance" and not byId[95].classic and byId[95].name == "High Order Skyborne"
		and byId[96].bit == 33 and byId[96].faction == "Horde" and byId[96].name == "Windshaper Skyborne" and Q.RaceInfo(96) == byId[96],
		"Forever's ten playable races: classic's eight and both Skyborne (their mask bits, sides)")
	check(Q.Quest(784).races == 178 + 2 ^ 33 and Q.Quest(363).races == 16 and Q.Quest(98340).races == 32 + 2 ^ 33
		and Q.Quest(92598).races == 2 ^ 33, "masks: all of the Horde's classic races widened, one race's kept, Forever's own as recorded")
	check(Q.RaceAllowed(176, 95) and not Q.RaceAllowed(176, 96) and Q.RaceAllowed(784, 96) and not Q.RaceAllowed(363, 96)
		and Q.RaceAllowed(363, 5) and not Q.RaceAllowed(92598, 2) and Q.RaceAllowed(92598, 96) and Q.RaceAllowed(176, 12345)
		and Q.RaceAllowed(7, 1), "Q.RaceAllowed by the data's masks (a race the data doesn't know: yes)")

	-- An item that starts a quest: where it drops.
	local schedule = Q.Quest(123).starts[1]
	local first = schedule.drops and schedule.drops[1]
	check(schedule.kind == "item" and schedule.id == 1307 and #schedule.points == 0 and first and first.kind == "npc" and first.id == 100
		and first.name == "Gruff Swiftbite" and suite.near(first.chance, 80, 0.01) and #schedule.drops <= 3,
		"The Collector's Gold Pickup Schedule drops from Gruff Swiftbite (80%), the likeliest first")
	local spot = first.points[1]
	check(spot and spot.map == 1429 and spot.x > 0.2 and spot.x < 0.35 and spot.y > 0.8 and spot.r > 0 and spot.r <= 0.15,
		"its spawns as a cluster: centre and radius on Elwynn Forest's map")
	local riverpaw
	for _, d in ipairs(schedule.drops) do if d.id == 478 then riverpaw = d end end
	check(riverpaw and riverpaw.chance < first.chance and #riverpaw.points >= 1, "the other sources, less likely")
	local writ
	for _, a in ipairs(Q.Quest(96294).starts) do if a.id == 273658 then writ = a end end
	check(writ and writ.drops[1] and writ.drops[1].id == 264082 and writ.drops[1].name == "Broodmother Valraxx" and writ.drops[1].points[1],
		"a Forever item: where players looted it (EG Link)")
	check(#Q.Quest(176).starts[1].points > 0 and Q.Quest(176).starts[1].drops == nil, "givers that aren't items have no drops")

	-- Who starts and ends what (tooltips).
	local starts, ends = Q.GiverQuests(240)
	check(has(ends, 176) and has(ends, 54) and #starts > 0 and Q.GiverQuests(240) == starts, "Marshal Dughan: what he gives and takes")
	local poster = Q.Quest(176).starts[1]
	check(has((Q.GiverQuests(poster.id, "object")), 176) and #Q.GiverQuests(999999999) == 0, "a wanted poster (an object); nobody: nothing")
	Q.AddLearned(999003, { title = "Learned At Dughan", zone = 1429, level = 8, starts = { { kind = "npc", id = 240, name = "Marshal Dughan" } } })
	check(has((Q.GiverQuests(240)), 999003), "a learned quest at him: there too")
	check(has(Q.ZoneGiven(1436), 166) and not has(Q.ZoneQuests(1436), 166) and #Q.ZoneGiven(999) == 0,
		"Westfall: the Deadmines' quests given there, listed under the dungeon")
end

section("Lodestar data: objectives, rewards, turn-in")
do
	check(type(LefthyToolsQuestData.quests[7]) == "string", "the data stays strings: nothing parsed at load")
	-- Kill: the creature with its spawns' clusters.
	local cleanup = Q.Objectives(7)
	local kill = cleanup[1]
	local vermin = kill and kill.sources[1]
	check(#cleanup == 1 and kill.kind == "kill" and kill.id == 6 and kill.name == "Kobold Vermin" and kill.count == 10
		and vermin.kind == "npc" and vermin.id == 6 and vermin.name == "Kobold Vermin" and vermin.chance == nil,
		"Kobold Camp Cleanup: kill 10 Kobold Vermin")
	local area = vermin.points[1]
	check(area and area.map == 1429 and area.x > 0.4 and area.x < 0.6 and area.y > 0.2 and area.y < 0.5 and area.r >= 0.015 and area.r <= 0.15,
		"where they are: a cluster in Northshire (" .. tostring(area and area.x) .. ", " .. tostring(area and area.y) .. ")")
	check(Q.Objectives(7) == cleanup, "kept: the same list asked again")
	-- Item: where it drops, with the chance.
	local claw = Q.Objectives(176)[1]
	local hogger = claw and claw.sources[1]
	check(claw.kind == "item" and claw.id == 1931 and claw.name == "Huge Gnoll Claw" and claw.count == 1 and hogger.kind == "npc"
		and hogger.id == 448 and hogger.name == "Hogger" and suite.near(hogger.chance, 100, 0.01) and hogger.points[1].map == 1429,
		"Wanted: Hogger: his claw, from Hogger (100%) in Elwynn Forest")
	check(claw.sources == Q.Quest(176).starts[1].drops or claw.sources == (Q.Objectives(176)[1].sources), "an item's sources are shared")
	-- Several kinds, the order the quest log has them; an object to use.
	local hillsbrad = Q.Objectives(532)
	local kinds = {}
	for i, o in ipairs(hillsbrad) do kinds[i] = o.kind .. o.id .. "x" .. o.count end
	check(table.concat(kinds, ",") == "kill2335x1,kill2387x5,object1761x1,item3657x1", "Battle of Hillsbrad: " .. table.concat(kinds, ","))
	local proclamation = hillsbrad[3]
	check(proclamation.name == "Hillsbrad Proclamation" and proclamation.sources[1].kind == "object" and proclamation.sources[1].points[1].map == 1424,
		"an object to destroy: where it stands")
	local registry = hillsbrad[4].sources[1]
	check(registry and registry.kind == "object" and registry.id == 1759 and registry.points[1], "an item from an object (the Town Registry's)")
	-- What Forever changed: its server's counts (EG Link), not classic's.
	local thistlefur = Q.Objectives(216)
	check(thistlefur[1] and thistlefur[1].count == 12, "Between a Rock and a Thistlefur: 12 on Forever (classic: 8)")
	-- An item the giver hands over; Forever's own quest.
	local documents = Q.Objectives(54)[1]
	check(documents and documents.kind == "item" and documents.id == 745 and documents.provided == true and #documents.sources == 0,
		"Report to Goldshire: the documents you were given")
	local books = Q.Objectives(91743)[1]
	check(books and books.kind == "item" and books.id == 247839 and books.count == 8 and books.name == "Stolen Book", "Forever's own quest: its objectives (EG Link)")
	check(#Q.Objectives(999999999) == 0 and #Q.Objectives(nil) == 0 and #Q.Objectives(999001) == 0, "unknown, nothing, a learned quest: none")

	-- Rewards: IDs and counts, money, experience.
	local r = Q.Rewards(176)
	local choice = {}
	for i, c in ipairs(r.choice) do choice[i] = c.id .. "x" .. c.count end
	check(table.concat(choice, ",") == "6085x1,6084x1,6215x1,270000x1" and #r.items == 0 and r.money == nil and r.xp == 875,
		"Hogger: one of four (Forever added one), 875 XP: " .. table.concat(choice, ",") .. ", " .. tostring(r.xp))
	r = Q.Rewards(7)
	check(r and #r.choice == 0 and r.money == 25 and r.xp == 170 and Q.Rewards(7) == r, "Kobold Camp Cleanup: 25 copper, 170 XP; kept")
	r = Q.Rewards(91743)
	check(r and #r.choice == 3 and r.money == 17 and r.xp == 170, "Forever's quest: its rewards")
	r = Q.Rewards(448)
	check(r and r.choice[1] and r.choice[1].id == 3240 and r.choice[1].count == 5 and r.choice[2].count == 5 and r.items[1].id == 2313
		and r.items[1].count == 1, "Report to Hadrec: one of 5 x two items, and one for sure")
	check(Q.Rewards(999999999) == nil and Q.Rewards(999001) == nil, "nothing known: nil")

	-- Levels as Forever has them; a level that scales.
	check(Q.Quest(952).level == 17 and Q.Quest(952).minLevel == 6, "Grove of the Ancients: level 17 on Forever (classic: 11)")
	local angler = Q.Quest(8194)
	check(angler.scales == true and angler.level == nil and Q.Quest(176).scales == false, "Apprentice Angler scales to you")

	-- Where it's turned in.
	local ends = Q.Ends(176)
	check(ends == Q.Quest(176).ends and ends[1].id == 240 and ends[1].points[1].map == 1429 and #Q.Ends(999999999) == 0,
		"turned in at Marshal Dughan")
end

section("Lodestar engine: Northshire with a made-up progress")
do
	login({})
	PLAYER_LEVEL = 1
	Fire("PLAYER_LEVEL_UP", 1)
	check(Q.Status(783) == "available" and Q.Status(7) == "locked" and Q.Status(54) == "locked", "a new character: the first quest available, the next ones locked")
	local missing = Q.Missing(54)
	local ids = {}
	for i, m in ipairs(missing) do ids[i] = m.id end
	check(table.concat(ids, ",") == "783,7,15,21" and missing[1].status == "available" and missing[1].reason == "done"
		and missing[4].status == "locked", "missing before Report to Goldshire: the whole chain, the first to do first")
	local chain = Q.Chain(54)
	check(at(chain, 783) < at(chain, 7) and at(chain, 7) < at(chain, 15) and at(chain, 15) < at(chain, 21) and at(chain, 21) < at(chain, 54),
		"its chain in order")
	check(Q.Chain(15) == chain, "the same chain for each of its quests")

	inLog({ 783 })
	check(Q.Status(783) == "active", "taken: in the log")
	Fire("QUEST_TURNED_IN", 783, 40, 0)
	QUESTS = {}
	Fire("QUEST_REMOVED", 783)
	check(Q.Status(783) == "done" and Q.Status(7) == "available" and Q.Status(5261) == "available", "turned in: done (before the server's list has it), the next ones open")
	check(Q.Status(18) == "level", "too low for one of them")
	local nxt = Q.Next()
	check(has(nxt, 7) and has(nxt, 5261) and not has(nxt, 18) and not has(nxt, 783), "next up: what it leads to, not what's too low or done")
	check(Q.Opens(783) == Q.Quest(783).opens and has(Q.Opens(783), 7), "what it opens")

	PLAYER_LEVEL = 4
	Fire("PLAYER_LEVEL_UP", 4)
	check(Q.Status(18) == "available" and has(Q.Next(), 18), "a level up: it's there")
	local reads, get = 0, C_QuestLog.GetAllCompletedQuestIDs
	C_QuestLog.GetAllCompletedQuestIDs = function() reads = reads + 1; return get() end
	login({ 783, 7 })
	check(Q.Status(7) == "done" and Q.Status(15) == "available" and #Q.Missing(15) == 0, "after a loading screen: the server's list")
	for _ = 1, 50 do Q.Status(15); Q.Status(21); Q.Next() end
	Fire("QUEST_TURNED_IN", 15, 0, 0)
	check(Q.Status(15) == "done" and Q.Status(21) == "available" and reads == 1, "the list read once, a quest turned in added to it")
	C_QuestLog.GetAllCompletedQuestIDs = get
	-- In my zone first.
	PLAYER_MAP = 1436
	local westfallFirst = Q.Next()
	PLAYER_MAP = 1429
	check(Q.Quest(Q.Next()[1]).zone == 1429 and #westfallFirst == #Q.Next(), "next: my zone's first")
end

section("Lodestar engine: not for me, exclusive, across zones, a Forever chain")
do
	PLAYER_LEVEL = 19
	Fire("PLAYER_LEVEL_UP", 19)
	login({})
	check(Q.Status(784) == "other", "a Horde quest: not for me")
	check(Q.Status(1638) == "other", "a warrior's quest for a rogue: not for me")
	check(Q.Quest(2205).classes == 8 and Q.Status(2205) ~= "other", "a rogue's quest: for me")
	local friend = { name = "Anna", classFile = "WARRIOR", race = 1, faction = "Alliance", level = 10, done = {}, active = {} }
	check(Q.Status(1638, friend) == "available", "for a warrior friend: available")
	friend.done[1679] = true
	check(Q.Status(1638, friend) == "other", "an exclusive one done: closed")
	friend.done, friend.active = {}, { [1684] = true }
	check(Q.Status(1638, friend) == "other", "an exclusive one taken: closed too")
	friend.active = {}
	check(Q.Status(1638, { classFile = "WARRIOR", faction = "Horde", level = 10 }) == "other", "a Horde friend: not theirs")

	-- Across zones: Dead-tooth Jack (Elwynn Forest) needs Marshal Haggard (Stormwind City) first.
	local missing = Q.Missing(1667)
	local last = missing[#missing]
	check(last and last.id == 1666 and Q.Quest(1666).zone == 1453 and Q.Quest(1667).zone == 1429, "missing: the one before it in another zone")

	-- An "all of" group: A Warden of the Alliance needs both Children's Week quests.
	local warden = Q.Quest(171)
	check(#warden.pre == 2 and has(warden.pre, 558) and has(warden.pre, 4822), "an all-of group: both needed")
	friend.done = { [558] = true }
	local ids = {}
	for i, m in ipairs(Q.Missing(171, friend)) do ids[i] = m.id end
	check(table.concat(ids, ",") == "4822", "one done: the other missing")

	-- One of several: the Burning Blade Medallion needs one of two.
	local medallion = Q.Quest(794)
	check(#medallion.preAny == 2 and has(medallion.preAny, 1499) and #medallion.pre == 0, "one of two needed")
	local orc = { name = "Grunt", classFile = "WARRIOR", race = 2, faction = "Horde", level = 5, done = {}, active = {} }
	local need = Q.Missing(794, orc)
	check(Q.Status(794, orc) == "locked" and #need >= 1 and need[#need].reason == "any" and has(medallion.preAny, need[#need].id),
		"none done: locked, the best of them missing")
	orc.done[1499] = true
	check(Q.Status(794, orc) == "available" and #Q.Missing(794, orc) == 0, "one done: available")

	-- Forever's own chain in Elwynn Forest (a book that drops starts it).
	local chain = Q.Chain(91777)
	check(at(chain, 91743) and at(chain, 91743) < at(chain, 91745) and at(chain, 91752) < at(chain, 91758) and at(chain, 91775) < at(chain, 91777),
		"Forever's kobold chain, in order")
	local walk = Q.Missing(91777)
	check(#walk == 7 and walk[1].id == 91741 and walk[2].id == 91743 and walk[7].id == 91775,
		"missing before its last quest: seven, from the book that starts it")

	-- Friends' progress (Learn.lua's Q.friends).
	Q.friends = { a = friend, b = { name = "Bob", classFile = "MAGE", race = 7, faction = "Alliance", done = { [176] = true } } }
	local friends = Q.Friends(176)
	check(#friends == 2 and friends[1].name == "Anna" and friends[2].status == "done", "friends' status of a quest")
	Q.friends = nil
	check(#Q.Friends(176) == 0, "no friends known: none")
end

section("Lodestar engine: a Skyborne, zone counts, chain steps, nearby, colours")
do
	-- I'm a Windshaper Skyborne (Horde): every quest for all of the Horde is mine.
	local race, side = UnitRace, UnitFactionGroup
	UnitRace = function(unit) if unit == "player" then return "Windshaper Skyborne", "Skyborne", 96 end end
	UnitFactionGroup = function(unit) if unit == "player" then return "Horde", "Horde" end end
	login({})
	check(Q.Status(784) ~= "other" and Q.Status(92598) ~= "other" and Q.Status(98340) ~= "other", "Skyborne: the Horde's quests, Skyborne ones, a Tauren-and-Skyborne one")
	check(Q.Status(363) == "other" and Q.Status(176) == "other" and Q.RaceAllowed(784) and not Q.RaceAllowed(363), "not an Undead's or the Alliance's")
	UnitRace = function(unit) if unit == "player" then return "Skyborne", "Skyborne" end end
	login({})
	check(Q.Status(784) ~= "other" and Q.Status(363) == "other", "the race's file and my side are enough")
	UnitRace, UnitFactionGroup = race, side
	login({})
	check(Q.Status(784) == "other" and Q.Status(176) ~= "other", "a human again")
	local friend = { name = "Sky", classFile = "SHAMAN", race = "Windshaper Skyborne", faction = "Horde", level = 20, done = {}, active = {} }
	local other = { name = "Lin", classFile = "MAGE", raceFile = "Skyborne", faction = "Alliance", level = 20, done = {}, active = {} }
	check(Q.Status(784, friend) ~= "other" and Q.Status(363, friend) == "other" and Q.Status(176, other) ~= "other" and Q.Status(784, other) == "other",
		"friends: a race by its name (Battle.net's), the Skyborne by file and side")
	-- The engine widens a classic mask itself (data made before the rule, learned quests).
	local hordeOnly, orcsOnly = { races = 178 }, { races = 2 }
	check(Q.RaceAllowed(hordeOnly, 96) and not Q.RaceAllowed(hordeOnly, 95) and not Q.RaceAllowed(orcsOnly, 96) and Q.RaceAllowed(orcsOnly, 2)
		and Q.RaceAllowed({}, 96), "the rule in the engine too")

	-- X of N: every level, only "not for me" left out.
	PLAYER_LEVEL = 19
	Fire("PLAYER_LEVEL_UP", 19)
	login({})
	local function count(map)
		local n = 0
		for _, id in ipairs(Q.ZoneQuests(map)) do
			local s = Q.Status(id)
			if s and s ~= "other" then n = n + 1 end
		end
		return n
	end
	local done, total = Q.ZoneCount(1429)
	check(done == 0 and total == count(1429) and total < #Q.ZoneQuests(1429) and total > 80, "Elwynn Forest: " .. tostring(total) .. " for me")
	local status, asked = Q.Status, 0
	Q.Status = function(...) asked = asked + 1; return status(...) end
	for _ = 1, 20 do Q.ZoneCount(1429); Q.Available(1429); Q.Available(1429, 0.5, 0.5) end
	local asks = asked
	for _ = 1, 20 do Q.ZoneCount(1429); Q.Available(1429, 0.5, 0.5) end
	Q.Status = status
	check(asked == asks, "kept: asked again, nothing worked out again")
	login({ 783, 7, 176 })
	done, total = Q.ZoneCount(1429)
	check(done == 3 and total == count(1429), "low ones done count too")
	local dd, dt = Q.ZoneCount("Deadmines")
	check(dd == 0 and dt >= 5 and Q.ZoneCount(nil) == 0, "a dungeon by its name")
	login({})

	-- Which step.
	local s783, total783, title = Q.ChainStep(783)
	local s54, total54 = Q.ChainStep(54)
	check(s783 == 1 and title == Q.Quest(Q.Chain(54)[1]).title and s54 >= 5 and select(1, Q.ChainStep(21)) == s54 - 1
		and total54 == total783 and total54 >= s54, "Report to Goldshire: step " .. tostring(s54) .. " of " .. tostring(total54) .. " (" .. tostring(title) .. ")")
	check(select(2, Q.ChainStep(3100)) >= 1 and Q.ChainStep(999999999) == nil, "steps of a branch; unknown: nil")

	-- Nearby: what I can take now, the nearest giver first.
	PLAYER_LEVEL = 10
	Fire("PLAYER_LEVEL_UP", 10)
	local here = Q.Available(1429)
	check(has(here, 783) and not has(here, 7) and not has(here, 123) and Q.Status(123) == "available", "Elwynn: available ones; not locked ones, not an item's")
	local all = true
	for _, id in ipairs(here) do if Q.Status(id) ~= "available" then all = false end end
	check(all and Q.Available(1429) == here, "only available ones; kept")
	local willem = Q.Quest(783).starts[1].points[1]
	local near = Q.Available(1429, willem.x, willem.y)
	check(Q.IsTrivial(783) and at(near, 783) > #near - 12 and not Q.IsTrivial(near[1]), "grey ones last, even right by their giver")
	PLAYER_LEVEL = 1
	Fire("PLAYER_LEVEL_UP", 1)
	near = Q.Available(1429, willem.x, willem.y)
	local here1 = Q.Available(1429)
	check(near[1] == 783 and #near == #here1, "by Deputy Willem: his quest first")
	local far = Q.Available(1429, 0.1, 0.9)
	check(far[1] ~= near[1] and #far == #here1, "elsewhere: another first")
	check(has(Q.Available(1436), 166) == (Q.Status(166) == "available"), "Westfall: the Deadmines' quests given there too")
	check(#Q.Available(nil) == 0, "no map: none")

	-- Colours as the game's quest difficulty.
	PLAYER_LEVEL = 20
	Fire("PLAYER_LEVEL_UP", 20)
	check(Q.LevelColor(25).key == "impossible" and Q.LevelColor(23).key == "difficult" and Q.LevelColor(22).key == "fair"
		and Q.LevelColor(18).key == "fair" and Q.LevelColor(17).key == "easy" and Q.LevelColor(14).key == "easy"
		and Q.LevelColor(13).key == "trivial" and Q.LevelColor(nil).key == "fair", "by level: red, orange, yellow, green, grey (13 is grey at 20)")
	check(Q.LevelColor(25).hex == "ffff1a1a" and Q.LevelColor(23).hex == "ffff8040" and Q.LevelColor(13).r == 0.5, "the game's colours")
	check(Q.IsTrivial(783) and not Q.IsTrivial(166) and Q.Difficulty(166) == "fair" and Q.Difficulty(999999999) == nil,
		"a level-1 quest is grey at 20, the Defias Brotherhood (22) yellow")
	local enum = Enum.RelativeContentDifficulty
	Enum.RelativeContentDifficulty = { Trivial = 0, Easy = 1, Fair = 2, Difficult = 3, Impossible = 4 }
	C_PlayerInfo.GetContentDifficultyQuestForPlayer = function(id) return id == 783 and 4 or nil end
	check(Q.LevelColor(1, 783).key == "impossible" and Q.LevelColor(1, 7).key == "trivial" and Q.Difficulty(783) == "impossible",
		"the client's own difficulty first, when it answers")
	C_PlayerInfo.GetContentDifficultyQuestForPlayer, Enum.RelativeContentDifficulty = nil, enum
	PLAYER_LEVEL = 19
	Fire("PLAYER_LEVEL_UP", 19)
end

section("Lodestar engine: for my level with the real data (a level-22 Horde Skyborne, a level-22 Human)")
do
	-- Forever's own quests the data had no side for: an NPC their text names, else a side's own zone.
	check(Q.Quest(98386).faction == "Alliance" and Q.Quest(98013).faction == "Alliance" and Q.Quest(87760).faction == "Alliance"
		and Q.Quest(97234).faction == "Alliance", "Alther's Mill (for Foreman Oslow), Swelling Forces, Holy Diver, Reading Room: the Alliance's")
	check(Q.Quest(95883).faction == "Horde" and Q.Quest(78149).faction == "Horde", "Silverpine's Tortured Soul, Owen Thadd's book: the Horde's")
	check(Q.Quest(79975).faction == nil and Q.Quest(103).faction == nil,
		"Eagle's Fist (Horde players turned it in) and Captain Grayson's Keeper of the Flame stay both sides'")
	-- Holidays' quests: only while their event is on.
	check(Q.IsEvent(9388) and Q.IsEvent(8768) and Q.IsEvent(7882) and Q.IsEvent(172) and Q.IsEvent(558) and Q.IsEvent(8193)
		and not Q.IsEvent(176) and not Q.IsEvent(999999999),
		"events: Flickering Flames, A Gaily Wrapped Present, Carnival Jerkins, Children's Week (its orphan's too), the fishing contest; not Hogger")

	local race, side, level = UnitRace, UnitFactionGroup, PLAYER_LEVEL
	local function As(raceName, raceID, faction)
		UnitRace = function(unit) if unit == "player" then return raceName, raceName, raceID end end
		UnitFactionGroup = function(unit) if unit == "player" then return faction, faction end end
		PLAYER_LEVEL = 22
		Fire("PLAYER_LEVEL_UP", 22)
		login({})
	end
	-- Every zone's quests for my level as the windows count them (Q.ForMyLevel), and what's wrong with any.
	local function Census(faction)
		local per, wrong = {}, {}
		for _, z in ipairs(Q.Zones()) do
			local list = {}
			for _, id in ipairs(Q.ZoneQuests(z.map)) do
				if Q.ForMyLevel(id) then
					list[#list + 1] = id
					local q, s = Q.Quest(id), Q.Status(id)
					if (q.faction and q.faction ~= faction) or not Q.RaceAllowed(q) or s == "locked" or s == "level" or q.event then
						wrong[#wrong + 1] = id .. " " .. tostring(q.title)
					end
				end
			end
			per[z.map] = list
		end
		return per, wrong
	end
	local function Titles(list)
		local out = {}
		for _, id in ipairs(list or {}) do out[#out + 1] = id .. " " .. tostring(Q.Quest(id).title) .. (Q.Quest(id).faction and "" or " (both)") end
		return table.concat(out, "; ")
	end

	As("Windshaper Skyborne", 96, "Horde")
	local horde, wrong = Census("Horde")
	check(#wrong == 0, "Horde: no zone counts a quest of the Alliance, one that needs another first, one too high or an event's: " .. table.concat(wrong, "; "))
	local function Only(list, allowed)
		for _, id in ipairs(list or {}) do
			if not allowed[id] then return false end
		end
		return true
	end
	-- Left in the Alliance's zones for a Horde character: quests both sides can take (neutral givers).
	check(#horde[1429] == 0 and #horde[1433] == 0 and #horde[1439] == 0, "Horde: Elwynn Forest, Redridge Mountains, Darkshore: nothing for my level: "
		.. Titles(horde[1429]) .. " | " .. Titles(horde[1433]) .. " | " .. Titles(horde[1439]))
	check(Only(horde[1436], { [103] = true, [104] = true, [152] = true, [136] = true }),
		"Horde: Westfall only Captain Grayson's and Captain Sander's treasure (a ghost and a map both sides can use): " .. Titles(horde[1436]))
	check(#horde[1413] > 10 and #horde[1421] > 0, "Horde: The Barrens and Silverpine Forest have quests for my level: " .. #horde[1413] .. ", " .. #horde[1421])
	local hordeSuggest = {}
	for _, z in ipairs(Q.Zones()) do hordeSuggest[z.map] = #horde[z.map] end

	As("Human", 1, "Alliance")
	local alliance
	alliance, wrong = Census("Alliance")
	check(#wrong == 0, "Alliance: no zone counts a quest of the Horde, one that needs another first, one too high or an event's: " .. table.concat(wrong, "; "))
	check(#alliance[1413] < hordeSuggest[1413] and #alliance[1421] == 0 and #alliance[1411] == 0 and #alliance[1412] == 0,
		"Alliance: Silverpine, Durotar, Mulgore nothing; The Barrens fewer than for the Horde: " .. Titles(alliance[1421]) .. " | " .. #alliance[1413])
	check(#alliance[1433] > 0 and #alliance[1431] > 0, "Alliance: Redridge Mountains and Duskwood have quests for my level: " .. #alliance[1433] .. ", " .. #alliance[1431])

	UnitRace, UnitFactionGroup, PLAYER_LEVEL = race, side, level
	Fire("PLAYER_LEVEL_UP", level)
	login({})
end

section("Lodestar engine: tiers with the real data (a level-22 Horde character), mobs' levels, group quests")
do
	local race, side, level = UnitRace, UnitFactionGroup, PLAYER_LEVEL
	UnitRace = function(unit) if unit == "player" then return "Orc", "Orc", 2 end end
	UnitFactionGroup = function(unit) if unit == "player" then return "Horde", "Horde" end end
	PLAYER_LEVEL = 22
	Fire("PLAYER_LEVEL_UP", 22)
	login({})
	-- The data: a quest's mobs' levels (field mobs) and the group flag (g).
	local hogger = Q.Quest(176)
	check(hogger.group == true and Q.Group(176) and select(1, Q.MobLevels(176)) == 11 and select(2, Q.MobLevels(176)) == 11,
		"Hogger: a group quest (classic-db's elite), its mob level 11")
	check(not Q.Group(155) and Q.Group(1487) and Q.Group(6284) and Q.MobLevels(783) == nil and not Q.Group(999999999) and Q.MobLevels(999999999) == nil,
		"The Defias Brotherhood (155): Forever made it a normal quest (EG Link); Deviate Eradication (a dungeon's) and Arachnophobia (elite) are for a group; no mobs, unknown: nil")
	local lo, hi = Q.MobLevels(821)
	check(lo == 18 and hi == 19, "Chen's Empty Keg (15): its thunder lizards' blood, from mobs 18-19")

	-- Tiers by zone for a level-22 Horde character: what the windows count.
	local function Tiers(list)
		local by, wrong = { trivial = 0, easy = 0, fair = 0, difficult = 0, impossible = 0 }, {}
		for _, id in ipairs(list) do
			local s = Q.Status(id)
			if s == "available" or s == "active" then
				local t = Q.Tier(id)
				by[t] = by[t] + 1
				local fits = Q.ForMyLevel(id)
				if fits ~= (s == "active" or ((t == "easy" or t == "fair") and Q.InRange(id))) or Q.IsHard(id) ~= (s == "available" and t == "difficult" and Q.InRange(id))
					or (fits and Q.IsHard(id)) or (s == "available" and (t == "trivial" or t == "impossible") and Q.InRange(id)) then
					wrong[#wrong + 1] = id
				end
			end
		end
		return by, wrong
	end
	local function Say(by)
		return ("grey %d, green %d, yellow %d, orange %d, red %d"):format(by.trivial, by.easy, by.fair, by.difficult, by.impossible)
	end
	local barrens, wrong = Tiers(Q.ZoneQuests(1413))
	check(#wrong == 0 and barrens.easy + barrens.fair >= 15 and barrens.difficult >= 3 and barrens.impossible >= 3 and barrens.trivial >= 5,
		"The Barrens at 22: " .. Say(barrens) .. "; for my level only green and yellow, hard only orange: " .. table.concat(wrong, ","))
	for _, z in ipairs({ { 1442, "Stonetalon Mountains" }, { 1440, "Ashenvale" }, { 1421, "Silverpine Forest" }, { 1424, "Hillsbrad Foothills" } }) do
		local by, bad = Tiers(Q.ZoneQuests(z[1]))
		check(#bad == 0 and by.easy + by.fair + by.difficult > 0, z[2] .. " at 22: " .. Say(by) .. " " .. table.concat(bad, ","))
	end
	-- A group quest a tier up: Arachnophobia (21, elite) and Wailing Caverns' Deviate Eradication (21) orange, not yellow.
	check(Q.Difficulty(6284) == "fair" and Q.Tier(6284) == "difficult" and Q.Difficulty(1487) == "fair" and Q.Tier(1487) == "difficult"
		and Q.Tier(1486) == "fair" and Q.Difficulty(1486) == "easy", "group quests a tier up: Arachnophobia, Deviate Eradication orange; Deviate Hides (17) yellow, not green")
	check(Q.Status(6284) ~= "available" or (Q.IsHard(6284) and not Q.ForMyLevel(6284) and Q.StatusRank(6284) == 4), "Arachnophobia: hard, not for my level")
	-- Mobs higher than the quest: Battle of Hillsbrad (26) has Magistrate Burnside (30) to kill: red, not orange.
	check(Q.Difficulty(532) == "difficult" and Q.Tier(532) == "impossible" and Q.MobLevels(532) == 30 and Q.EffectiveLevel(532) == 30,
		"Battle of Hillsbrad: its level orange, its mobs (30) red")
	PLAYER_LEVEL = 15
	Fire("PLAYER_LEVEL_UP", 15)
	check(Q.Difficulty(821) == "fair" and Q.Tier(821) == "difficult" and Q.EffectiveLevel(821) == 18,
		"at 15, Chen's Empty Keg (15) is orange: its lizards are 18-19")
	PLAYER_LEVEL = 22
	Fire("PLAYER_LEVEL_UP", 22)
	check(Q.Tier(821) == "easy", "at 22 it's green again")

	-- The one order: the Barrens' quests sorted by Q.Compare, rank by rank, each by its effective level.
	local list = {}
	for i, id in ipairs(Q.ZoneQuests(1413)) do list[i] = id end
	table.sort(list, Q.Compare)
	local ok, last = true, nil
	for _, id in ipairs(list) do
		local key = { Q.StatusRank(id), Q.EffectiveLevel(id) or math.huge }
		if last and (key[1] < last[1] or (key[1] == last[1] and key[2] < last[2])) then ok = false end
		last = key
	end
	check(ok and Q.StatusRank(list[1]) <= 3 and Q.StatusRank(list[#list]) == 9, "the Barrens in order: for my level first, rank by rank, by level (" .. #list .. " quests)")
	UnitRace, UnitFactionGroup, PLAYER_LEVEL = race, side, level
	Fire("PLAYER_LEVEL_UP", level)
	login({})
end

section("Lodestar data: learned data fills gaps")
do
	local learned = Q.Quest(999001)
	check(learned and learned.source == "learned" and learned.title == "A Learned Quest" and has(learned.pre, 783)
		and has(Q.Quest(783).opens, 999001) and learned.starts[1].points[1].map == 1429, "learned before the load: applied, what it needs leads to it")
	check(Q.Quest(176).title == 'Wanted:  "Hogger"', "classic's title stays")

	local changed = 0
	Q.OnDataChanged(function() changed = changed + 1 end)
	-- A classic quest's giver without a place gets one; its own lists stay.
	local orphanQuest = Q.Quest(558)
	local orphan = orphanQuest.starts[1]
	check(orphan and #orphan.points == 0, "the Human Orphan: no place in the data (an event's)")
	Q.AddLearned(558, { level = 1, pre = { 1 }, starts = { { kind = "npc", id = orphan.id, points = { { map = 1453, x = 0.6, y = 0.7 } } },
		{ kind = "npc", id = 999992, name = "Someone Else" } } })
	check(orphan.points[1] and orphan.points[1].map == 1453 and #orphanQuest.starts == 1 and orphanQuest.level == 60
		and #orphanQuest.pre == 0, "classic: the place filled; no new giver, level and needs kept")
	-- Forever's quest: new givers and needs add up.
	local rodents = Q.Quest(91745)
	local starts = #rodents.starts
	Q.AddLearned(91745, { pre = { 91741 }, starts = { { kind = "npc", id = 999993, name = "Learned Kobold Expert" } }, title = "Other Title" })
	check(#rodents.starts == starts + 1 and has(rodents.pre, 91741) and has(rodents.pre, 91743) and rodents.title == "Mining Consultant",
		"Forever's: a giver and a need added, the title kept")
	check(has(Q.Search("kobold expert"), 91745), "search finds what's learned")
	check(changed == 0, "the windows hear of it on the next frame")
	Advance(1)
	check(changed == 1, "once for both")
	local before, rewards = Q.Objectives(7), Q.Rewards(7)
	Q.AddLearned(999002, { title = "Somewhere New", zone = 1436, level = 12 })
	check(has(Q.ZoneQuests(1436), 999002) and Q.Quest(999002).zoneName == "Westfall", "a learned quest in a zone: listed there")
	local after = Q.Objectives(7)
	check(after ~= before and after[1].id == before[1].id and after[1].sources[1] == before[1].sources[1] and Q.Rewards(7) ~= rewards,
		"objectives and rewards read again after a change of the data (the places stay shared)")
	Advance(1)
end

section("Lodestar data: the test hook")
do
	local heard = 0
	Q.OnDataChanged(function() heard = heard + 1 end)
	Q.SetTestData({
		{ id = 1, title = "First", level = 2, minLevel = 1, zone = 1429, starts = { { kind = "npc", id = 1, name = "Giver", points = { { map = 1429, x = 0.5, y = 0.5 } } } } },
		{ id = 2, title = "Second", level = 4, minLevel = 2, zone = 1429, pre = { 1 } },
		{ id = 3, title = "Elsewhere", level = 9, minLevel = 8, zone = 1436, preAny = { 1, 2 } },
		{ id = 4, title = "Deep", level = 20, dungeon = "Deadmines", pre = { 3 },
			objectives = { { kind = "kill", id = 7, name = "Boss", count = 1, sources = { { kind = "npc", id = 7, name = "Boss", points = {} } } } },
			rewards = { choice = {}, items = { { id = 5, count = 1 } }, xp = 100 } },
	}, { { map = 1429, name = "Elwynn Forest", continent = 1415 }, { map = 1436, name = "Westfall", continent = 1415, minLevel = 10, maxLevel = 20 } })
	check(heard >= 1, "the windows hear of it at once")
	check(Q.Quest(176) == nil and Q.Quest(999001) == nil and Q.Quest(1).title == "First" and has(Q.Quest(1).opens, 2) and has(Q.Quest(1).opens, 3),
		"the real data and learned ones gone; what's needed leads to it")
	local zones = Q.Zones()
	check(#zones == 2 and zones[1].map == 1429 and zones[1].minLevel == 2 and zones[1].maxLevel == 4 and zones[1].count == 2
		and zones[2].minLevel == 10 and zones[2].count == 1, "zones: levels from the quests unless given")
	check(#Q.Dungeons() == 1 and Q.DungeonQuests("Deadmines")[1] == 4 and Q.Quest(3).zoneName == "Westfall", "dungeons from the quests")
	login({})
	PLAYER_LEVEL = 5
	Fire("PLAYER_LEVEL_UP", 5)
	check(Q.Status(1) == "available" and Q.Status(2) == "locked" and Q.Status(3) == "locked", "status in the test data")
	login({ 1 })
	check(Q.Status(2) == "available" and Q.Status(3) == "level" and Q.Status(4) == "locked", "one of two is enough; too low")
	check(#Q.Search("deep") == 1 and table.concat(Q.Chain(4), ",") == "1,2,3,4", "search and chain in it")
	check(Q.Objectives(4)[1].name == "Boss" and Q.Rewards(4).xp == 100 and #Q.Objectives(1) == 0 and Q.Rewards(1) == nil,
		"a test quest's own objectives and rewards; none without")
end

section("Lodestar engine: why not for me, what blocks it, my levels")
do
	local factions = C_Reputation
	local standing = { [72] = 2000 }
	C_Reputation = { GetFactionDataByID = function(id) return standing[id] and { currentStanding = standing[id] } end }
	PROFESSIONS = { { name = "Alchemy", level = 60, line = 171 } }
	Q.SetTestData({
		{ id = 1, title = "Trivial", level = 2, minLevel = 1, zone = 1429 },
		{ id = 2, title = "Mine", level = 20, minLevel = 18, zone = 1429 },
		{ id = 3, title = "Soon", level = 23, minLevel = 22, zone = 1429 },
		{ id = 4, title = "Later", level = 30, minLevel = 25, zone = 1429 },
		{ id = 5, title = "Brew", level = 20, minLevel = 18, zone = 1429, skill = { id = 171, value = 100 } },
		{ id = 6, title = "Forge", level = 20, minLevel = 18, zone = 1429, skill = { id = 164, value = 50 } },
		{ id = 7, title = "Friends", level = 20, minLevel = 18, zone = 1429, rep = { faction = 72, min = 3000 } },
		{ id = 8, title = "Mage", level = 20, minLevel = 18, zone = 1429, classes = 128 },
		{ id = 9, title = "One way", level = 20, minLevel = 18, zone = 1429, excl = { 10 } },
		{ id = 10, title = "Other way", level = 20, minLevel = 18, zone = 1429, excl = { 9 } },
		{ id = 11, title = "Report in", level = 20, minLevel = 18, zone = 1429, breadcrumbFor = 2 },
		{ id = 12, title = "Red", level = 25, minLevel = 18, zone = 1429 },
		{ id = 13, title = "Orange", level = 24, minLevel = 18, zone = 1429 },
		{ id = 14, title = "Scales", level = -1, minLevel = 10, zone = 1429 },
		{ id = 15, title = "Zero", level = 0, minLevel = 5, zone = 1429 },
		{ id = 16, title = "Flagged", minLevel = 5, scales = true, zone = 1429 },
		{ id = 17, title = "Grey", level = 10, minLevel = 5, zone = 1429 },
		{ id = 18, title = "No level", zone = 1429 },
		{ id = 19, title = "Feast", level = 20, minLevel = 18, zone = 1429, event = true },
		{ id = 20, title = "After the feast", level = 20, minLevel = 18, zone = 1429, pre = { 19 } },
	}, { { map = 1429, name = "Elwynn Forest", continent = 1415 } })
	PLAYER_LEVEL = 20
	Fire("PLAYER_LEVEL_UP", 20)
	login({})
	QUESTS = { { id = 10 }, { id = 2 } }
	Fire("QUEST_LOG_UPDATE")
	check(Q.Status(5) == "locked" and Q.Needs(5) and Q.Needs(5).kind == "skill" and Q.Needs(5).value == 100 and Q.Needs(5).have == 60,
		"a profession I have, its rank too low: blocked, and by what")
	check(Q.Status(6) == "other" and Q.WhyOther(6) == "skill", "a profession I don't have: not for me")
	check(Q.Status(7) == "locked" and Q.Needs(7).kind == "rep" and Q.Needs(7).min == 3000 and Q.Needs(7).faction == 72,
		"a reputation too low: blocked, not 'not for you'")
	check(Q.WhyOther(8) == "class" and Q.Needs(8) == nil, "another class's: not for me")
	local why, by = Q.WhyOther(9)
	check(why == "closed" and by == 10, "the other way taken: closed by it")
	why, by = Q.WhyOther(11)
	check(why == "closed" and by == 2 and Q.WhyOther(2) == nil and Q.WhyOther(1) == nil, "a breadcrumb to a quest I have: closed; others aren't 'other'")
	check(not Q.InRange(1) and Q.InRange(2) and not Q.InRange(3) and not Q.InRange(4) and Q.RANGE_RED == 4 and Q.RANGE_ABOVE == nil,
		"my levels: not grey, nothing I can't take yet (coming up is out)")
	check(not Q.InRange(12) and Q.InRange(13) and Q.Status(12) == "available" and Q.Difficulty(12) == "impossible",
		"a red quest I could take: still available, not in my levels; orange is")
	check(Q.InRange(14) and Q.InRange(15) and Q.InRange(16) and not Q.InRange(18) and not Q.InRange(17),
		"levels -1, 0 and the data's flag count as mine; no level at all (Forever's untitled hidden quests): out; grey: out")
	check(Q.IsEvent(19) and not Q.IsEvent(2) and Q.Status(19) == "available" and not Q.InRange(19),
		"an event's quest (only while its holiday is on): available, but never in my levels")
	check(Q.ForMyLevel(2) and not Q.ForMyLevel(13) and Q.IsHard(13) and not Q.IsHard(2) and not Q.ForMyLevel(19) and not Q.ForMyLevel(20) and Q.Status(20) == "locked" and Q.InRange(20)
		and not Q.IsHard(20) and not Q.ForMyLevel(1) and not Q.ForMyLevel(3) and not Q.ForMyLevel(12) and not Q.IsHard(12) and not Q.ForMyLevel(5),
		"for my level: in my log or to take now within my levels, green or yellow (orange is hard, apart); not what needs another first (in my levels or not), an event's, grey, too high, red or blocked")
	check(Q.Difficulty(14) == "fair" and Q.Difficulty(15) == "fair" and Q.Difficulty(16) == "fair" and not Q.IsTrivial(16)
		and Q.LevelColor(-1).key == "fair" and Q.LevelColor(0).key == "fair" and Q.Difficulty(17) == "trivial",
		"a level that scales: yellow (fair), never grey")
	PLAYER_LEVEL = 4
	Fire("PLAYER_LEVEL_UP", 4)
	check(not Q.InRange(14) and not Q.InRange(15) and Q.Status(14) == "level", "below its minimum level: out, even when it scales")
	PLAYER_LEVEL = 20
	Fire("PLAYER_LEVEL_UP", 20)
	PLAYER_LEVEL = 30
	Fire("PLAYER_LEVEL_UP", 30)
	QUESTS = { { id = 10 }, { id = 2 }, { id = 3 }, { id = 4 }, { id = 19 } }
	Fire("QUEST_LOG_UPDATE")
	check(Q.InRange(2) and Q.InRange(3) and Q.InRange(4) and Q.InRange(19) and Q.ForMyLevel(19), "in my log: always in my levels (grey or not, an event's too)")
	QUESTS = {}
	Fire("QUEST_LOG_UPDATE")
	C_Reputation, PROFESSIONS = factions, {}
end

section("Lodestar engine: tiers (level, mobs, group, the client's), my levels, the one order")
do
	Q.SetTestData({
		{ id = 1, title = "Grey", level = 10, zone = 1429 },
		{ id = 2, title = "Green", level = 16, zone = 1429 },
		{ id = 3, title = "Yellow", level = 20, zone = 1429 },
		{ id = 4, title = "Orange", level = 23, zone = 1429 },
		{ id = 5, title = "Red", level = 25, zone = 1429 },
		{ id = 6, title = "Mobs above", level = 20, zone = 1429, mobMin = 23, mobMax = 24 },
		{ id = 7, title = "Group", level = 20, zone = 1429, group = true },
		{ id = 8, title = "Group orange", level = 23, zone = 1429, group = true },
		{ id = 9, title = "Group grey", level = 10, zone = 1429, group = true },
		{ id = 10, title = "Group green", level = 16, zone = 1429, group = true },
		{ id = 11, title = "Scales", level = -1, zone = 1429, mobMin = 30 },
		{ id = 12, title = "Mobs below", level = 21, zone = 1429, mobMin = 15 },
		{ id = 13, title = "The client's", level = 20, zone = 1429, mobMin = 25 },
		{ id = 14, title = "The client's too", level = 24, zone = 1429 },
		{ id = 15, title = "Mobs red", level = 20, zone = 1429, mobMin = 26 },
	}, { { map = 1429, name = "Elwynn Forest", continent = 1415 } })
	PLAYER_LEVEL = 20
	Fire("PLAYER_LEVEL_UP", 20)
	login({})
	local function tiers(from, to)
		local out = {}
		for id = from, to do out[#out + 1] = tostring(Q.Tier(id)) end
		return table.concat(out, ",")
	end
	check(tiers(1, 5) == "trivial,easy,fair,difficult,impossible", "by level, at 20: grey, green, yellow, orange, red: " .. tiers(1, 5))
	check(Q.Tier(6) == "difficult" and Q.Difficulty(6) == "fair" and Q.EffectiveLevel(6) == 23 and select(1, Q.MobLevels(6)) == 23
		and select(2, Q.MobLevels(6)) == 24 and Q.Tier(15) == "impossible", "mobs above the quest make it harder: 23-24 orange, 26 red")
	check(tiers(7, 10) == "difficult,impossible,trivial,fair" and Q.Group(7) and not Q.Group(3),
		"a group quest a tier up (yellow to orange, orange to red, green to yellow); grey stays grey: " .. tiers(7, 10))
	check(Q.Tier(11) == "fair" and Q.Tier(12) == "fair" and Q.EffectiveLevel(12) == 21 and Q.Tier(999) == nil and Q.MobLevels(3) == nil,
		"one that scales: yellow, its mobs scale too; mobs below never make it easier; unknown: nil")
	check(Q.TierColor("difficult").hex == "ffff8040" and Q.TierColor("fair").r == 1 and Q.TierColor("nope") == nil
		and Q.TierCode(5) == "|cffff1a1a" and Q.TierCode(2) == "|cff40bf40" and Q.TierCode(999) == "|cffffd100", "colours: the tier's, yellow for an unknown quest")
	check(Q.TIER_WORD.trivial == "Trivial" and Q.TIER_WORD.easy == "Easy" and Q.TIER_WORD.fair == "Fair" and Q.TIER_WORD.difficult == "Hard"
		and Q.TIER_WORD.impossible == "Too hard", "the tiers' words")
	-- My levels: green and yellow for my level, orange hard (in range, apart), red and grey out.
	check(Q.ForMyLevel(2) and Q.ForMyLevel(3) and not Q.ForMyLevel(4) and Q.IsHard(4) and Q.InRange(4) and not Q.InRange(5) and not Q.InRange(1)
		and Q.IsHard(6) and Q.IsHard(7) and not Q.InRange(8) and not Q.InRange(15) and Q.ForMyLevel(10) and not Q.IsHard(3),
		"for my level green and yellow; hard: orange by level, mobs or group; red (a group's orange too) and grey out")

	-- The client's own difficulty wins, unless the mobs make it harder.
	local enum = Enum.RelativeContentDifficulty
	Enum.RelativeContentDifficulty = { Trivial = 0, Easy = 1, Fair = 2, Difficult = 3, Impossible = 4 }
	C_PlayerInfo.GetContentDifficultyQuestForPlayer = function(id) return (id == 13 or id == 14) and 1 or nil end
	login({})
	check(Q.Tier(14) == "easy" and Q.Tier(13) == "impossible", "the client's green wins; mobs (25) still make one red")
	C_PlayerInfo.GetContentDifficultyQuestForPlayer, Enum.RelativeContentDifficulty = nil, enum
	-- Kept: worked out once per progress change; my level moves it.
	local difficulty, asked = Q.Difficulty, 0
	Q.Difficulty = function(...) asked = asked + 1; return difficulty(...) end
	login({})
	for _ = 1, 5 do for id = 1, 15 do Q.Tier(id); Q.ForMyLevel(id); Q.IsHard(id) end end
	local once = asked
	for _ = 1, 5 do for id = 1, 15 do Q.Tier(id) end end
	check(asked == once and once <= 15, "tiers kept: " .. once .. " worked out for 15 quests")
	PLAYER_LEVEL = 23
	Fire("PLAYER_LEVEL_UP", 23)
	check(Q.Tier(4) == "fair" and Q.Tier(5) == "fair" and asked > once, "at 23: what was orange and red is yellow")
	Q.Difficulty = difficulty
	PLAYER_LEVEL = 20
	Fire("PLAYER_LEVEL_UP", 20)

	-- The one order, everywhere: ready to turn in, in my log, for my level, hard, other available ones,
	-- coming up, needing another first, done, not for me; then by level, title (any case), ID.
	Q.SetTestData({
		{ id = 101, title = "Zeta", level = 20, zone = 1429 },
		{ id = 102, title = "alpha", level = 20, zone = 1429 },
		{ id = 103, title = "Beta", level = 18, zone = 1429 },
		{ id = 104, title = "Hard one", level = 23, zone = 1429 },
		{ id = 105, title = "Red one", level = 26, zone = 1429 },
		{ id = 106, title = "Grey one", level = 5, zone = 1429 },
		{ id = 107, title = "Later", level = 25, minLevel = 22, zone = 1429 },
		{ id = 108, title = "Locked", level = 20, zone = 1429, pre = { 107 } },
		{ id = 109, title = "Done", level = 10, zone = 1429 },
		{ id = 110, title = "Mage only", level = 20, zone = 1429, classes = 128 },
		{ id = 111, title = "In my log", level = 21, zone = 1429 },
		{ id = 112, title = "Ready", level = 24, zone = 1429 },
		{ id = 113, title = "No level", zone = 1429 },
		{ id = 114, title = "Alpha", level = 20, zone = 1429 },
		{ id = 115, title = "Mobs make it later", level = 18, zone = 1429, mobMin = 21 },
	}, { { map = 1429, name = "Elwynn Forest", continent = 1415 } })
	QUESTS = { { id = 111, title = "In my log", objectives = { { text = "Boars slain: 1/5", finished = false } } },
		{ id = 112, title = "Ready", objectives = { { text = "Boars slain: 5/5", finished = true } } } }
	Fire("QUEST_ACCEPTED", 112)
	login({ 109 })
	local list = { 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115 }
	table.sort(list, Q.Compare)
	local ranks = {}
	for i, id in ipairs(list) do ranks[i] = Q.StatusRank(id) end
	check(table.concat(list, ",") == "112,111,103,102,114,101,115,104,106,105,113,107,108,109,110",
		"ready, in my log, for my level (by level, then title in any case, then ID), hard, the others available, coming up, locked, done, not for me: "
		.. table.concat(list, ","))
	check(table.concat(ranks, ",") == "1,2,3,3,3,3,3,4,5,5,5,6,7,8,9" and Q.StatusRank(999) == 9 and not Q.Compare(101, 101)
		and Q.Compare(101, nil) and not Q.Compare(nil, 101), "the ranks; a quest isn't before itself; unknown last")
	-- The client's title (German): the order follows it.
	local titleOf = C_QuestLog.GetTitleForQuestID
	C_QuestLog.GetTitleForQuestID = function(id) if id == 101 then return "Aal" end return titleOf(id) end
	login({ 109 })
	table.sort(list, Q.Compare)
	check(list[3] == 103 and list[4] == 101 and list[5] == 102, "the client's title: Aal before alpha")
	C_QuestLog.GetTitleForQuestID = titleOf
	-- Turned in: done, near the end.
	QUESTS = { { id = 111, title = "In my log", objectives = { { text = "Boars slain: 1/5", finished = false } } } }
	Fire("QUEST_TURNED_IN", 112)
	check(Q.StatusRank(112) == 8 and Q.StatusRank(111) == 2, "turned in: done")
	QUESTS = {}
	Fire("QUEST_LOG_UPDATE")
end

QUESTS, PLAYER_LEVEL, PLAYER_MAP = savedQuests, savedLevel, savedMap
