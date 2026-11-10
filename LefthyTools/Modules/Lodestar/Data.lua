local _, ns = ...
local Q = ns.Lodestar or {}; ns.Lodestar = Q

-- Lodestar's quest data (docs/lodestar.md, Data): LefthyTools_QuestData, an add-on of its own (GPL v3
-- like its source, CMaNGOS Classic DB, with EG Link's Forever data, CC BY 4.0), made by
-- tools/update-quest-data.js and loaded the first time a Lodestar window asks (Q.Load), never at
-- login. Its quests are strings, read one at a time when asked for (Q.Quest) and kept; what the game
-- teaches while playing (Learn.lua) fills the gaps (Q.AddLearned). Also Forever's playable races
-- (Q.Races), where items that start quests drop (an item's drops), who gives and takes what
-- (Q.GiverQuests), the quests given in a zone but listed elsewhere (Q.ZoneGiven), a quest's objectives
-- with where to do them (Q.Objectives), its rewards (Q.Rewards) and turn-in (Q.Ends), which quests an
-- item is for (Q.ItemQuests: an index made over a few frames the first time it's asked). Without the add-on
-- everything here answers nil or empty lists, and Q.DataProblem() says why.

local DATA_ADDON = "LefthyTools_QuestData"
local KIND = { n = "npc", o = "object", i = "item" }

local db               -- the loaded data (LefthyToolsQuestData, or the test data)
local tried, why       -- loading was tried; why the data isn't there ("MISSING", "DISABLED", ...)
local quests = {}      -- id -> quest table (false: not in the data), read when first asked for
local actors = { n = {}, o = {}, i = {} } -- a giver's or ender's table, shared by its quests
local sources = { n = {}, o = {} } -- a drop source's or objective's { kind, id, name, points } (dropNpcs, dropObjects), shared
local roles = { n = {}, o = {} }   -- Q.GiverQuests: id -> { starts, ends } (the data's, read when asked)
local learnedRoles = { n = {}, o = {} } -- givers and enders learned (Q.AddLearned) or of the test data: id -> { starts, ends }
local raceList, raceById -- Q.Races()
local objectivesOf, rewardsOf, extrasGen = {}, {}, nil -- Q.Objectives, Q.Rewards: per quest, kept per data generation

-- Forever's playable races when the data doesn't say (race ID, race-mask bit, side, classic's).
local RACES = {
	{ 1, 0, "Alliance", "Human" }, { 2, 1, "Horde", "Orc" }, { 3, 2, "Alliance", "Dwarf" }, { 4, 3, "Alliance", "Night Elf" },
	{ 5, 4, "Horde", "Undead" }, { 6, 5, "Horde", "Tauren" }, { 7, 6, "Alliance", "Gnome" }, { 8, 7, "Horde", "Troll" },
	{ 95, 32, "Alliance", "High Order Skyborne" }, { 96, 33, "Horde", "Windshaper Skyborne" },
}
local zoneList, zoneById, dungeonList, dungeonByName -- Q.Zones(), Q.Dungeons() and their quests
local searchIndex      -- { { id, text } } for Q.Search, made by the first search after a change
local pending = {}     -- Q.AddLearned before the data was loaded: { id, fields }
local listeners = {}   -- Q.OnDataChanged
local announcing = false

Q.dataGen = 0 -- goes up with every change of the data (the Engine's caches read it)

local function Num(s)
	return s and s ~= "" and tonumber(s) or nil
end

-- "a|b||c" -> { "a", "b", "", "c" }
local function Fields(text, sep)
	local f, n, at = {}, 0, 1
	while true do
		local stop = text:find(sep, at, true)
		n = n + 1
		if not stop then
			f[n] = text:sub(at)
			return f
		end
		f[n] = text:sub(at, stop - 1)
		at = stop + 1
	end
end

-- "1,2,3" -> { 1, 2, 3 } (a new table, empty for "")
local function Ids(s)
	local list = {}
	if s and s ~= "" then
		for id in s:gmatch("%d+") do list[#list + 1] = tonumber(id) end
	end
	return list
end

local function Changed()
	Q.dataGen = Q.dataGen + 1
	searchIndex = nil
end

-- The callbacks of Q.OnDataChanged, once on the next frame for any number of changes.
local function Announce()
	if announcing then return end
	announcing = true
	local function run()
		announcing = false
		for _, fn in ipairs(listeners) do
			local ok, err = pcall(fn)
			if not ok then
				local handler = geterrorhandler and geterrorhandler()
				if handler then handler(err) end
			end
		end
	end
	if C_Timer and C_Timer.After then C_Timer.After(0, run) else run() end
end

function Q.OnDataChanged(fn)
	if type(fn) == "function" then listeners[#listeners + 1] = fn end
end

-- ---------------------------------------------------------------- places

-- The map a uiMap is on (its continent), by the client's map tree.
local function ContinentOf(map)
	if not (C_Map and C_Map.GetMapInfo) then return nil end
	local at = map
	for _ = 1, 8 do
		local ok, info = pcall(C_Map.GetMapInfo, at)
		if not (ok and type(info) == "table") then return nil end
		if info.mapType == 2 then return info.mapID end
		at = info.parentMapID
		if not at or at == 0 then return nil end
	end
end

-- A place where zones' rectangles overlap ("map,x,y/map,x,y"): the zone the client's own map has
-- there, if it's one of them, else the first (the tool's best guess).
local function Place(text)
	local alts = Fields(text, "/")
	local list = {}
	for i, alt in ipairs(alts) do
		local m, x, y = alt:match("^(%d+),(%d+),(%d+)$")
		if m then list[#list + 1] = { map = tonumber(m), x = tonumber(x) / 1000, y = tonumber(y) / 1000 } end
	end
	local best = list[1]
	if #list > 1 and C_Map and C_Map.GetMapInfoAtPosition and C_Map.GetMapRectOnMap then
		local ok, found = pcall(function()
			local continent = ContinentOf(best.map)
			if not continent then return nil end
			local minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(best.map, continent)
			if type(minX) ~= "number" or type(maxY) ~= "number" then return nil end
			local info = C_Map.GetMapInfoAtPosition(continent, minX + best.x * (maxX - minX), minY + best.y * (maxY - minY))
			return type(info) == "table" and info.mapID or nil
		end)
		if ok and found then
			for _, p in ipairs(list) do
				if p.map == found then return p end
			end
		end
	end
	return best
end

-- A drop source's table (shared by the items it drops and the objectives to kill or use it): { kind =
-- "npc"|"object", id, name, points = { { map, x, y, r } } }, r the radius of the spawns' cluster (a
-- share of the map's width).
local function Source(letter, id)
	local known = sources[letter][id]
	if known then return known end
	local list = db and db[letter == "n" and "dropNpcs" or "dropObjects"]
	local text = list and list[id]
	local source = { kind = KIND[letter], id = id, points = {} }
	if type(text) == "string" then
		local name, places = text:match("^([^|]*)|?(.*)$")
		source.name = name ~= "" and name or nil
		for m, x, y, r in (places or ""):gmatch("(%d+),(%d+),(%d+),(%d+)") do
			source.points[#source.points + 1] = { map = tonumber(m), x = tonumber(x) / 1000, y = tonumber(y) / 1000, r = tonumber(r) / 1000 }
		end
	end
	sources[letter][id] = source
	return source
end

-- An item's drops ("n123:4500,o45:100", hundredths of a percent): { { kind, id, name, chance (0..100),
-- points } }, the likeliest first.
local function Drops(text)
	local list = {}
	for letter, id, chance in (text or ""):gmatch("(%a)(%d+):(%d+)") do
		if letter == "n" or letter == "o" then
			id = tonumber(id)
			local source = Source(letter, id)
			list[#list + 1] = { kind = KIND[letter], id = id, name = source.name, chance = tonumber(chance) / 100, points = source.points }
		end
	end
	return list
end

-- A giver's or ender's table: { kind = "npc"|"object"|"item", id, name, points = { { map, x, y } } }; an
-- item's has drops (where it drops: Drops) and no points.
local function Actor(key)
	local letter, id = key:match("^(%a)(%d+)$")
	if not KIND[letter] then return nil end
	id = tonumber(id)
	local known = actors[letter][id]
	if known then return known end
	local text = db and db[KIND[letter] == "npc" and "npcs" or KIND[letter] == "object" and "objects" or "items"]
	text = text and text[id]
	local actor = { kind = KIND[letter], id = id, points = {} }
	if letter == "i" then actor.drops = {} end
	if type(text) == "string" then
		local name, rest = text:match("^([^|]*)|?(.*)$")
		actor.name = name ~= "" and name or nil
		if letter == "i" then
			actor.drops = Drops(rest)
		elseif rest and rest ~= "" then
			for place in rest:gmatch("[^;]+") do actor.points[#actor.points + 1] = Place(place) end
		end
	end
	actors[letter][id] = actor
	return actor
end

local function Actors(s)
	local list = {}
	if s and s ~= "" then
		for key in s:gmatch("[^,]+") do list[#list + 1] = Actor(key) end
	end
	return list
end

-- ---------------------------------------------------------------- quests

local function Name(i)
	i = Num(i)
	return i and db.names and db.names[i] or nil
end

-- A quest of the data's strings (tools/update-quest-data.js has the format).
local function Parse(id, text)
	local f = Fields(text, "|")
	local flags = f[16] or ""
	local q = {
		id = id, title = f[1] ~= "" and f[1] or nil,
		level = Num(f[2]), minLevel = Num(f[3]), races = Num(f[4]), classes = Num(f[5]),
		zone = Num(f[6]), sort = Name(f[8]), dungeon = Name(f[9]),
		pre = Ids(f[10]), preAny = Ids(f[11]), preActive = Num(f[12]), excl = Ids(f[13]), opens = Ids(f[14]),
		breadcrumbFor = Num(f[15]),
		faction = flags:find("A", 1, true) and "Alliance" or flags:find("H", 1, true) and "Horde" or nil,
		repeatable = flags:find("r", 1, true) ~= nil, new = flags:find("n", 1, true) ~= nil, scales = flags:find("s", 1, true) ~= nil,
		source = flags:find("f", 1, true) and "forever" or "classic",
		starts = Actors(f[19]), ends = Actors(f[20]),
	}
	local skill, value = (f[17] or ""):match("^(%d+):(%d+)$")
	if skill then q.skill = { id = tonumber(skill), value = tonumber(value) } end
	local faction, min = (f[18] or ""):match("^(%d+):(%-?%d+)$")
	if faction then q.rep = { faction = tonumber(faction), min = tonumber(min) } end
	local zone = q.zone and zoneById and zoneById[q.zone]
	q.zoneName = Name(f[7]) or zone and zone.name or q.dungeon or q.sort
	return q
end

-- A quest given as a table (Q.SetTestData, Q.AddLearned): a copy with every list there.
local LISTS = { "pre", "preAny", "excl", "opens", "starts", "ends" }
local function Normalize(id, t)
	local q = {}
	for k, v in pairs(t) do q[k] = v end
	q.id = id
	for _, k in ipairs(LISTS) do
		local list = {}
		for i, v in ipairs(type(q[k]) == "table" and q[k] or {}) do list[i] = v end
		q[k] = list
	end
	q.source = q.source or "learned"
	q.repeatable = q.repeatable == true
	q.new = q.new == true
	if not q.zoneName then
		local zone = q.zone and zoneById and zoneById[q.zone]
		q.zoneName = zone and zone.name or q.dungeon or q.sort
	end
	return q
end

-- The quest table (see the contract in docs/lodestar.md), or nil. Shared: never written by callers.
function Q.Quest(id)
	id = tonumber(id)
	if not id or not db then return nil end
	local q = quests[id]
	if q == nil then
		local raw = db.quests[id]
		if type(raw) == "string" then
			local ok, parsed = pcall(Parse, id, raw)
			q = ok and parsed or false
		elseif type(raw) == "table" then
			q = Normalize(id, raw)
		else
			q = false
		end
		quests[id] = q
	end
	return q or nil
end

-- ---------------------------------------------------------------- objectives, rewards, turn-in

local OBJECTIVE = { k = "kill", o = "object", i = "item" }
local NONE = {} -- (Q.Objectives' answer without any: shared, never written)

-- A quest's extra fields (objectives, choice, items, money, xp: after its ends), read only when asked.
local function Extras(id)
	local raw = db and db.quests[id]
	if type(raw) ~= "string" then return nil end
	local f = Fields(raw, "|")
	return f[21] or "", f[22] or "", f[23] or "", f[24] or "", f[25] or ""
end

local function Fresh()
	if extrasGen ~= Q.dataGen then objectivesOf, rewardsOf, extrasGen = {}, {}, Q.dataGen end
end

-- "k6:10,i745p" -> { { kind, id, name, count, sources, provided } }
local function ParseObjectives(text)
	local list = {}
	for letter, id, count, provided in text:gmatch("(%a)(%d+):?(%d*)(p?)") do
		local kind = OBJECTIVE[letter]
		if kind then
			id = tonumber(id)
			local o = { kind = kind, id = id, count = tonumber(count) or 1 }
			if kind == "item" then
				local item = Actor("i" .. id)
				o.name, o.sources = item and item.name, item and item.drops or {}
				if provided == "p" then o.provided = true end
			else
				local source = Source(letter == "k" and "n" or "o", id)
				o.name, o.sources = source.name, { source }
			end
			list[#list + 1] = o
		end
	end
	return list
end

-- What a quest asks for: { { kind = "kill"|"item"|"object", id, name, count, sources = { { kind =
-- "npc"|"object", id, name, chance (0..100, items only), points = { { map, x, y, r } } } }, provided (an
-- item the giver hands over) } }, empty when none. kill: the creature with its spawns' clusters; item:
-- where it drops (at most 3, with places first, in the quest's zone, the likeliest), object: its spawns.
-- Shared (never written by callers), kept per data generation. A test or learned quest's own objectives.
function Q.Objectives(id)
	id = tonumber(id)
	if not id or not db then return NONE end
	Fresh()
	local list = objectivesOf[id]
	if list then return list end
	local raw = db.quests[id]
	if type(raw) == "string" then
		local ok, parsed = pcall(ParseObjectives, (Extras(id)))
		list = ok and parsed or {}
	else
		local q = Q.Quest(id)
		list = q and type(q.objectives) == "table" and q.objectives or {}
	end
	objectivesOf[id] = list
	return list
end

-- "6085,9030:5" -> { { id, count } }
local function Counted(text)
	local list = {}
	for item, count in text:gmatch("(%d+):?(%d*)") do list[#list + 1] = { id = tonumber(item), count = tonumber(count) or 1 } end
	return list
end

-- What a quest gives: { choice = { { id, count } } (one of them), items = { { id, count } } (all of them),
-- money (copper) or nil, xp (at the quest's level) or nil }, nil when nothing's known. Item IDs only
-- (names and icons: the client's). Shared, kept per data generation. A test or learned quest's own.
function Q.Rewards(id)
	id = tonumber(id)
	if not id or not db then return nil end
	Fresh()
	local r = rewardsOf[id]
	if r ~= nil then return r or nil end
	local raw = db.quests[id]
	if type(raw) == "string" then
		local _, choice, items, money, xp = Extras(id)
		r = { choice = Counted(choice), items = Counted(items), money = Num(money), xp = Num(xp) }
		if #r.choice == 0 and #r.items == 0 and not r.money and not r.xp then r = false end
	else
		local q = Q.Quest(id)
		r = q and type(q.rewards) == "table" and q.rewards or false
	end
	rewardsOf[id] = r
	return r or nil
end

-- Where a quest is turned in: its enders ({ kind, id, name, points }, the quest's own list: shared).
function Q.Ends(id)
	local q = Q.Quest(id)
	return q and q.ends or NONE
end

-- ---------------------------------------------------------------- zones and dungeons

local function SortZones()
	table.sort(zoneList, function(a, b)
		if a.continent ~= b.continent then return (a.continent or 0) < (b.continent or 0) end
		if a.minLevel ~= b.minLevel then return a.minLevel < b.minLevel end
		return a.map < b.map
	end)
	table.sort(dungeonList, function(a, b)
		if a.minLevel ~= b.minLevel then return a.minLevel < b.minLevel end
		return a.name < b.name
	end)
end

-- The quest IDs of each zone and dungeon, and their entries.
local function BuildIndex()
	zoneList, zoneById, dungeonList, dungeonByName = {}, {}, {}, {}
	for map, text in pairs(db.zones or {}) do
		local entry
		if type(text) == "string" then
			local f = Fields(text, "|")
			entry = { map = map, continent = Num(f[1]), minLevel = Num(f[2]) or 0, maxLevel = Num(f[3]) or 0, name = f[4], quests = Ids(f[5]),
				given = Ids(f[6]) }
		elseif type(text) == "table" then
			entry = { map = map, continent = text.continent, minLevel = text.minLevel or 0, maxLevel = text.maxLevel or 0, name = text.name,
				quests = {}, given = {} }
			for i, id in ipairs(text.quests or {}) do entry.quests[i] = id end
		end
		if entry then
			entry.count = #entry.quests
			zoneById[map] = entry
			zoneList[#zoneList + 1] = entry
		end
	end
	for key, text in pairs(db.dungeons or {}) do
		if type(text) == "string" then
			local f = Fields(text, "|")
			local entry = { name = Name(key) or tostring(key), minLevel = Num(f[1]) or 0, maxLevel = Num(f[2]) or 0, quests = Ids(f[3]) }
			entry.count = #entry.quests
			dungeonByName[entry.name] = entry
			dungeonList[#dungeonList + 1] = entry
		end
	end
	SortZones()
end

-- The test data's zones and dungeons, from its quests (a zone's name, continent: as given).
local function BuildTestIndex(list, zones)
	db.zones, db.dungeons = {}, {}
	for _, z in ipairs(zones or {}) do
		if z.map then db.zones[z.map] = { name = z.name, continent = z.continent, minLevel = z.minLevel, maxLevel = z.maxLevel, quests = {} } end
	end
	BuildIndex()
	local given = {} -- entries whose levels the test gave
	for _, z in ipairs(zones or {}) do
		if z.map and z.minLevel and zoneById[z.map] then given[zoneById[z.map]] = true end
	end
	local function add(entry, q)
		entry.quests[#entry.quests + 1] = q.id
		entry.count = #entry.quests
		local level = q.level or q.minLevel
		if level and level > 0 and not given[entry] then
			entry.minLevel = entry.minLevel > 0 and math.min(entry.minLevel, level) or level
			entry.maxLevel = math.max(entry.maxLevel, level)
		end
	end
	for _, q in ipairs(list) do
		if q.zone then
			local entry = zoneById[q.zone]
			if not entry then
				entry = { map = q.zone, name = q.zoneName or tostring(q.zone), minLevel = 0, maxLevel = 0, quests = {}, given = {}, count = 0 }
				zoneById[q.zone] = entry
				zoneList[#zoneList + 1] = entry
			end
			add(entry, q)
		end
		if q.dungeon then
			local entry = dungeonByName[q.dungeon]
			if not entry then
				entry = { name = q.dungeon, minLevel = 0, maxLevel = 0, quests = {}, count = 0 }
				dungeonByName[q.dungeon] = entry
				dungeonList[#dungeonList + 1] = entry
			end
			add(entry, q)
		end
	end
	SortZones()
end

-- Zones with quests: { map, name, continent, minLevel, maxLevel, count }, by continent then level.
function Q.Zones()
	return zoneList or {}
end

function Q.Dungeons()
	return dungeonList or {}
end

-- A zone's (a dungeon's) quest IDs, the lowest level first; shared, never written by callers.
function Q.ZoneQuests(map)
	local entry = zoneById and zoneById[tonumber(map) or map]
	return entry and entry.quests or {}
end

function Q.DungeonQuests(name)
	local entry = dungeonByName and dungeonByName[name]
	return entry and entry.quests or {}
end

-- Quests given in a zone (a giver stands there) that are listed elsewhere: a dungeon's quests at its
-- town, another zone's. Shared, never written by callers.
function Q.ZoneGiven(map)
	local entry = zoneById and zoneById[tonumber(map) or map]
	return entry and entry.given or {}
end

-- ---------------------------------------------------------------- races

-- Forever's playable races: { { id, bit, faction, name, classic } } (bit: the race mask's, 0 = the
-- lowest), the data's or, without it, the ones known when this was written.
function Q.Races()
	if raceList then return raceList end
	local list = {}
	if db and type(db.races) == "table" then
		for id, text in pairs(db.races) do
			local f = type(text) == "string" and Fields(text, "|")
			if f and Num(f[1]) then
				list[#list + 1] = { id = id, bit = Num(f[1]), faction = f[2] == "A" and "Alliance" or f[2] == "H" and "Horde" or nil,
					name = f[3] ~= "" and f[3] or nil, classic = f[4] == "c" }
			end
		end
	end
	if #list == 0 then
		for i, r in ipairs(RACES) do list[i] = { id = r[1], bit = r[2], faction = r[3], name = r[4], classic = r[1] <= 8 } end
	end
	table.sort(list, function(a, b) return a.id < b.id end)
	raceList, raceById = list, {}
	for _, r in ipairs(list) do raceById[r.id] = r end
	return list
end

-- A race's entry of Q.Races() by its ID, nil if it isn't a playable race.
function Q.RaceInfo(id)
	if not raceList then Q.Races() end
	return raceById[tonumber(id) or id]
end

-- ---------------------------------------------------------------- who gives and takes what

local function AddRole(letter, id, quest, which)
	local list = learnedRoles[letter]
	list[id] = list[id] or { starts = {}, ends = {} }
	local into = list[id][which]
	for _, v in ipairs(into) do if v == quest then return end end
	into[#into + 1] = quest
end

-- The quests an NPC (kind "npc", the default) or object ("object") starts and ends: two lists of quest
-- IDs (shared, never written by callers; empty without data). For tooltips: cheap, no quest is read.
function Q.GiverQuests(id, kind)
	id = tonumber(id)
	local letter = kind == "object" and "o" or "n"
	if not id or not db then return {}, {} end
	local known = roles[letter][id]
	if known and known.gen == Q.dataGen then return known.starts, known.ends end
	local entry = { gen = Q.dataGen, starts = {}, ends = {} }
	local list = db[letter == "n" and "npcQuests" or "objectQuests"]
	local text = type(list) == "table" and list[id]
	if type(text) == "string" then
		local s, e = text:match("^([^|]*)|?(.*)$")
		entry.starts, entry.ends = Ids(s), Ids(e)
	end
	local learned = learnedRoles[letter][id]
	if learned then
		for _, which in ipairs({ "starts", "ends" }) do
			local into, seen = entry[which], {}
			for _, v in ipairs(into) do seen[v] = true end
			for _, v in ipairs(learned[which]) do
				if not seen[v] then seen[v] = true; into[#into + 1] = v end
			end
		end
	end
	roles[letter][id] = entry
	return entry.starts, entry.ends
end

-- ---------------------------------------------------------------- quest items

-- Q.ItemQuests: which quests an item is for. Made from the quests' raw strings (only their starts and
-- objectives fields, and only of quests whose string has an item in it: no quest is parsed), a few
-- hundred quests a frame, the first time it's asked after the data is loaded; quests changed by
-- learning (Apply) go over it, per data generation.
local ITEM_STEP = 300 -- quests a frame at most
local ITEM_MS = 3     -- and no longer than this a frame (where the game says: debugprofilestop)
local itemRaw, itemRawOf  -- item -> { { id, role } } of the data, and the data table it's of
local itemScan            -- the build going on: { db, key (the last quest read), index }
local itemTop, itemTopGen = {}, nil -- learned quests' items over itemRaw (lists copied), and the data generation
local itemSorted = setmetatable({}, { __mode = "k" }) -- lists put in order (Q.ItemQuests)
local touched = {}        -- quests Apply changed: their items go over the data's
Q.itemGen = 0             -- goes up when the index is made (the tooltips' caches read it)

local ROLE_ORDER = { objective = 1, provided = 2, starts = 3 }

local function AddItem(index, item, quest, role)
	if not item then return end
	local list = index[item]
	if not list then
		list = {}
		index[item] = list
	end
	for _, e in ipairs(list) do
		if e.id == quest and e.role == role then return end
	end
	list[#list + 1] = { id = quest, role = role }
end

-- A quest's items into the index: its raw string's starts (field 19: "n12,i345") and objectives
-- (field 21: "k6:10,i745p"), or a quest table's (test or learned data) starts and objectives.
local function ScanQuest(index, id, raw)
	if type(raw) == "string" then
		if not raw:find("i%d") then return end -- (no item anywhere in it: most quests)
		local f = Fields(raw, "|")
		for item in (f[19] or ""):gmatch("i(%d+)") do AddItem(index, tonumber(item), id, "starts") end
		for letter, item, provided in (f[21] or ""):gmatch("(%a)(%d+):?%d*(p?)") do
			if letter == "i" then AddItem(index, tonumber(item), id, provided == "p" and "provided" or "objective") end
		end
	elseif type(raw) == "table" then
		for _, a in ipairs(type(raw.starts) == "table" and raw.starts or {}) do
			if type(a) == "table" and a.kind == "item" then AddItem(index, tonumber(a.id), id, "starts") end
		end
		for _, o in ipairs(type(raw.objectives) == "table" and raw.objectives or {}) do
			if type(o) == "table" and o.kind == "item" then AddItem(index, tonumber(o.id), id, o.provided and "provided" or "objective") end
		end
	end
end

-- Milliseconds (debugprofilestop), nil where there's none (tests).
local function Clock()
	local ok, ms = pcall(debugprofilestop)
	return ok and type(ms) == "number" and ms or nil
end

-- One frame's part of the build; the next on the next frame. The data replaced meanwhile: it stops
-- (the next question starts again).
local function ScanStep(scan)
	if itemScan ~= scan or scan.db ~= db then return end
	local list, key, n, start = db.quests, scan.key, 0, Clock()
	while true do
		local id, raw = next(list, key)
		if id == nil then
			itemRaw, itemRawOf, itemScan, itemTopGen = scan.index, db, nil, nil
			Q.itemGen = Q.itemGen + 1
			return
		end
		key = id
		ScanQuest(scan.index, id, raw)
		n = n + 1
		if n >= ITEM_STEP or (start and n % 25 == 0 and (Clock() or start) - start >= ITEM_MS) then break end
	end
	scan.key = key
	C_Timer.After(0, function() ScanStep(scan) end)
end

-- The learned quests' items over the data's (the lists they change are copies).
local function ItemTop()
	if itemTopGen == Q.dataGen then return end
	itemTop, itemTopGen = {}, Q.dataGen
	for id in pairs(touched) do
		local q = Q.Quest(id)
		if q then
			local extra = {}
			ScanQuest(extra, id, { starts = q.starts, objectives = Q.Objectives(id) })
			for item, list in pairs(extra) do
				local merged = itemTop[item]
				if not merged then
					merged = {}
					for i, e in ipairs(itemRaw[item] or NONE) do merged[i] = e end
					itemTop[item] = merged
				end
				for _, e in ipairs(list) do AddItem(itemTop, item, e.id, e.role) end
			end
		end
	end
end

-- The quests an item is for: { { id = questID, role = "objective" (collected for it) | "provided" (the
-- giver hands it over) | "starts" (it starts the quest) } }, objectives first, then by quest ID; an
-- empty list for an item of no quest. Shared, never written by callers. nil while the index isn't
-- made yet (without data, or for the few frames after the first question: it's made then, never in
-- one go).
function Q.ItemQuests(item)
	if not db then return nil end
	if itemRawOf ~= db then
		if not (itemScan and itemScan.db == db) then
			local scan = { db = db, index = {} }
			itemScan, itemRaw, itemRawOf = scan, nil, nil
			C_Timer.After(0, function() ScanStep(scan) end)
		end
		return nil
	end
	ItemTop()
	item = tonumber(item)
	local list = item and (itemTop[item] or itemRaw[item])
	if not list then return NONE end
	if not itemSorted[list] then
		table.sort(list, function(a, b)
			if a.role ~= b.role then return ROLE_ORDER[a.role] < ROLE_ORDER[b.role] end
			return a.id < b.id
		end)
		itemSorted[list] = true
	end
	return list
end

-- A zone a learned quest is in, for Q.Zones (the client's name and continent).
local function ZoneEntry(map)
	local entry = zoneById[map]
	if entry then return entry end
	local info = C_Map and C_Map.GetMapInfo and select(2, pcall(C_Map.GetMapInfo, map))
	entry = { map = map, name = type(info) == "table" and info.name or tostring(map), continent = ContinentOf(map),
		minLevel = 0, maxLevel = 0, quests = {}, given = {}, count = 0 }
	zoneById[map] = entry
	zoneList[#zoneList + 1] = entry
	return entry
end

-- ---------------------------------------------------------------- search

local function Lower(s)
	return type(s) == "string" and s:lower() or ""
end

-- Every quest's searchable text: titles (the data's, the client's) and its givers' and enders' names.
local function BuildSearch()
	searchIndex = {}
	local clientTitle = C_QuestLog and C_QuestLog.GetTitleForQuestID
	local function names(list)
		local out = {}
		for _, a in ipairs(list) do if a.name then out[#out + 1] = a.name end end
		return table.concat(out, "\n")
	end
	local function add(id, title, people)
		local text = Lower(title) .. "\n" .. Lower(people)
		if clientTitle then
			local ok, t = pcall(clientTitle, id)
			if ok and type(t) == "string" and not (issecretvalue and issecretvalue(t)) then text = text .. "\n" .. t:lower() end
		end
		searchIndex[#searchIndex + 1] = { id = id, text = text, title = Lower(title) }
	end
	local seen = {}
	for id, raw in pairs(db.quests) do
		seen[id] = true
		local q = quests[id]
		if q then
			add(id, q.title, names(q.starts) .. "\n" .. names(q.ends))
		elseif type(raw) == "string" then
			local f = Fields(raw, "|")
			local people = {}
			for _, field in ipairs({ f[19] or "", f[20] or "" }) do
				for key in field:gmatch("[^,]+") do
					local a = Actor(key)
					if a and a.name then people[#people + 1] = a.name end
				end
			end
			add(id, f[1], table.concat(people, "\n"))
		elseif type(raw) == "table" then
			q = Q.Quest(id)
			if q then add(id, q.title, names(q.starts) .. "\n" .. names(q.ends)) end
		end
	end
	for id, q in pairs(quests) do
		if q and not seen[id] then add(id, q.title, names(q.starts) .. "\n" .. names(q.ends)) end
	end
	table.sort(searchIndex, function(a, b) return a.id < b.id end)
end

-- Quest IDs whose title (English or the client's) or giver's or ender's name has text in it (any
-- case): title matches first, then by level.
function Q.Search(text)
	if not db or type(text) ~= "string" then return {} end
	local needle = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
	if needle == "" then return {} end
	if not searchIndex then BuildSearch() end
	local hits = {}
	for _, e in ipairs(searchIndex) do
		if e.text:find(needle, 1, true) then
			hits[#hits + 1] = { id = e.id, title = e.title:find(needle, 1, true) ~= nil }
		end
	end
	local level = {}
	for _, h in ipairs(hits) do
		local q = Q.Quest(h.id)
		level[h.id] = q and (q.level or q.minLevel) or 0
	end
	table.sort(hits, function(a, b)
		if a.title ~= b.title then return a.title end
		if level[a.id] ~= level[b.id] then return level[a.id] < level[b.id] end
		return a.id < b.id
	end)
	local out = {}
	for i, h in ipairs(hits) do out[i] = h.id end
	return out
end

-- ---------------------------------------------------------------- learning

local SCALARS = { "title", "level", "minLevel", "races", "classes", "faction", "zone", "zoneName", "sort", "dungeon",
	"preActive", "breadcrumbFor", "skill", "rep" }

local function HasId(list, id)
	for _, v in ipairs(list) do if v == id then return true end end
	return false
end

-- A learned giver or ender into a quest's list: points for a known one that has none; a new one
-- only where the data has none of its own (classic's) or doesn't come from classic.
local function MergeActors(q, key, list)
	local mine = q[key]
	for _, a in ipairs(list) do
		if type(a) == "table" and a.id then
			local kind = a.kind or "npc"
			local found
			for _, b in ipairs(mine) do
				if b.kind == kind and b.id == a.id then found = b end
			end
			if found then
				if not found.name and a.name then found.name = a.name end
				if (not found.points or #found.points == 0) and type(a.points) == "table" and #a.points > 0 then
					found.points = {}
					for i, p in ipairs(a.points) do found.points[i] = { map = p.map, x = p.x, y = p.y } end
				end
			elseif q.source ~= "classic" or #mine == 0 then
				local copy = { kind = kind, id = a.id, name = a.name, points = {} }
				for i, p in ipairs(type(a.points) == "table" and a.points or {}) do copy.points[i] = { map = p.map, x = p.x, y = p.y } end
				mine[#mine + 1] = copy
			end
		end
	end
end

local function Apply(id, fields)
	touched[id] = true -- (its items, for Q.ItemQuests)
	local q = Q.Quest(id)
	local zoneBefore = q and q.zone
	if not q then
		q = Normalize(id, { source = "learned" })
		quests[id] = q
	end
	local fromClassic = q.source == "classic"
	for _, k in ipairs(SCALARS) do
		if q[k] == nil and fields[k] ~= nil then q[k] = fields[k] end
	end
	if q.zone and not q.zoneName then
		q.zoneName = zoneById[q.zone] and zoneById[q.zone].name
	end
	-- Lists of quests: classic's stay as they are (an empty one says "nothing"); the others gain what's learned.
	for _, k in ipairs({ "pre", "preAny", "excl", "opens" }) do
		local list = fields[k]
		if type(list) == "table" and not fromClassic then
			for _, other in ipairs(list) do
				other = tonumber(other)
				if other and other ~= id and not HasId(q[k], other) then
					q[k][#q[k] + 1] = other
					-- What it needs leads to it.
					if k ~= "excl" and k ~= "opens" then
						local before = Q.Quest(other)
						if before and not HasId(before.opens, id) then before.opens[#before.opens + 1] = id end
					end
				end
			end
		end
	end
	if fields.preActive and q.preActive == fields.preActive and not fromClassic then
		local before = Q.Quest(fields.preActive)
		if before and not HasId(before.opens, id) then before.opens[#before.opens + 1] = id end
	end
	for _, k in ipairs({ "starts", "ends" }) do
		if type(fields[k]) == "table" then
			MergeActors(q, k, fields[k])
			-- (who gives or takes it, for Q.GiverQuests: the ones the quest has now)
			for _, a in ipairs(q[k]) do
				if (a.kind == "npc" or a.kind == "object") and a.id then AddRole(a.kind == "npc" and "n" or "o", a.id, id, k) end
			end
		end
	end
	-- A zone it wasn't in before: its list (and the zone itself, when the data has none).
	if q.zone and q.zone ~= zoneBefore then
		local entry = ZoneEntry(q.zone)
		if not HasId(entry.quests, id) then
			-- (in level order, after the ones of its level)
			local level, at = q.level or q.minLevel or 0, #entry.quests + 1
			for i, other in ipairs(entry.quests) do
				local o = Q.Quest(other)
				if o and (o.level or o.minLevel or 0) > level then at = i; break end
			end
			table.insert(entry.quests, at, id)
			entry.count = #entry.quests
			SortZones()
		end
	end
end

-- Learned fields (as in the quest table) into a quest: they fill gaps, never replace the data's.
-- Values only where the quest has none; lists of quests (pre, preAny, excl, opens) only for quests
-- not from classic-db (whose lists, empty ones too, are what the core checks), and what a quest
-- needs then leads to it; givers and enders: places for a known one without any, new ones where
-- classic-db has none or the quest isn't classic's. An unknown quest is made, with source
-- "learned". Before the data is loaded they wait for it (Learn feeds them at login).
function Q.AddLearned(id, fields)
	id = tonumber(id)
	if not id or type(fields) ~= "table" then return end
	if not db then
		pending[#pending + 1] = { id, fields }
		return
	end
	Apply(id, fields)
	Changed()
	Announce()
end

-- ---------------------------------------------------------------- loading

local function Reset()
	quests, actors = {}, { n = {}, o = {}, i = {} }
	sources, roles, learnedRoles = { n = {}, o = {} }, { n = {}, o = {} }, { n = {}, o = {} }
	raceList, raceById = nil, nil
	searchIndex = nil
	objectivesOf, rewardsOf, extrasGen = {}, {}, nil
	touched, itemTop, itemTopGen = {}, {}, nil -- (Q.ItemQuests: the index is made again for other data)
end

local function Use(data)
	db = data
	Reset()
	BuildIndex()
	if #pending > 0 then
		local list = pending
		pending = {}
		for _, p in ipairs(list) do Apply(p[1], p[2]) end
	end
	Changed()
end

-- Loads the data the first time (LefthyTools_QuestData through C_AddOns.LoadAddOn); true when it's
-- there. Only a Lodestar window asks: never at login.
function Q.Load()
	if db then return true end
	local data = rawget(_G, "LefthyToolsQuestData")
	if tried and type(data) ~= "table" then return false end -- (asked once; loaded since by someone else: taken)
	tried = true
	if type(data) ~= "table" then
		local load = C_AddOns and C_AddOns.LoadAddOn or rawget(_G, "LoadAddOn")
		if load then
			local ok, loaded, reason = pcall(load, DATA_ADDON)
			if not (ok and loaded) then why = tostring(ok and reason or "error") end
		else
			why = "no LoadAddOn"
		end
		data = rawget(_G, "LefthyToolsQuestData")
	end
	if type(data) ~= "table" or type(data.quests) ~= "table" then
		why = why or "BROKEN"
		return false
	end
	why = nil
	Use(data)
	return true
end

-- Whether the data is loaded now (Learn.lua asks before it looks a quest up: asking mustn't load it).
function Q.IsLoaded()
	return db ~= nil
end

-- Whether the data is loaded or can be (installed and enabled), without loading it.
function Q.HasData()
	if db or type(rawget(_G, "LefthyToolsQuestData")) == "table" then return true end
	if tried then return false end
	local info = C_AddOns and C_AddOns.GetAddOnInfo
	if not info then return false end
	local ok, name, _, _, loadable, reason = pcall(info, DATA_ADDON)
	return ok and name ~= nil and (loadable == true or reason == "DEMAND_LOADED") or false
end

-- Why there's no data: nil when it's loaded (or not tried yet), else the game's reason
-- ("MISSING", "DISABLED", ...).
function Q.DataProblem()
	return not db and why or nil
end

-- What the data says about itself: { source, build, quests (count) }, nil without data.
function Q.DataInfo()
	if not db then return nil end
	local n = 0
	for _ in pairs(db.quests) do n = n + 1 end
	return { source = db.source, build = db.build, quests = n }
end

-- Test hook: uses a data table in the add-on's own format (LefthyToolsQuestData: strings) as if it
-- had just been loaded (Q.Load).
function Q.SetTestRawData(data)
	tried, why, pending = true, nil, {}
	Use(data)
end

-- Test hook: replaces the data with quests (a list of quest tables, or { [id] = table }) and zones
-- ({ { map, name, continent [, minLevel, maxLevel] } }; levels and counts from the quests when not
-- given). What a quest needs leads to it (opens) without saying so. Learned data and caches go;
-- Q.OnDataChanged's callbacks run at once.
function Q.SetTestData(list, zones)
	local byId, ordered = {}, {}
	for k, t in pairs(list or {}) do
		if type(t) == "table" then
			local id = tonumber(t.id) or tonumber(k)
			if id then
				byId[id] = t
				ordered[#ordered + 1] = id
			end
		end
	end
	table.sort(ordered)
	db = { source = "test", build = "test", quests = {}, names = {} }
	tried, why, pending = true, nil, {}
	Reset()
	zoneById = nil
	local normalized = {}
	for _, id in ipairs(ordered) do
		local q = Normalize(id, byId[id])
		if not byId[id].source then q.source = "classic" end
		db.quests[id] = q
		quests[id] = q
		normalized[#normalized + 1] = q
	end
	for _, q in ipairs(normalized) do
		for _, k in ipairs({ "pre", "preAny" }) do
			for _, other in ipairs(q[k]) do
				local before = quests[other]
				if before and not HasId(before.opens, q.id) then before.opens[#before.opens + 1] = q.id end
			end
		end
		local active = q.preActive and quests[q.preActive]
		if active and not HasId(active.opens, q.id) then active.opens[#active.opens + 1] = q.id end
		local target = q.breadcrumbFor and quests[q.breadcrumbFor]
		if target and not HasId(q.opens, target.id) then q.opens[#q.opens + 1] = target.id end
		for _, k in ipairs({ "starts", "ends" }) do
			for _, a in ipairs(q[k]) do
				if type(a) == "table" and (a.kind == "npc" or a.kind == "object") and a.id then AddRole(a.kind == "npc" and "n" or "o", a.id, q.id, k) end
			end
		end
	end
	BuildTestIndex(normalized, zones)
	for _, q in ipairs(normalized) do
		local zone = q.zone and zoneById[q.zone]
		if zone and not byId[q.id].zoneName then q.zoneName = zone.name end
	end
	Changed()
	for _, fn in ipairs(listeners) do pcall(fn) end
end
