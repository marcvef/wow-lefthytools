local _, ns = ...
local Q = ns.Questtree or {}; ns.Questtree = Q

-- Questtree's quest data (docs/questtree.md, Data): LefthyTools_QuestData, an add-on of its own (GPL v3
-- like its source, CMaNGOS Classic DB, with EG Link's Forever data, CC BY 4.0), made by
-- tools/update-quest-data.js and loaded the first time a Questtree window asks (Q.Load), never at
-- login. Its quests are strings, read one at a time when asked for (Q.Quest) and kept; what the game
-- teaches while playing (Learn.lua) fills the gaps (Q.AddLearned). Without the add-on everything
-- here answers nil or empty lists, and Q.DataProblem() says why.

local DATA_ADDON = "LefthyTools_QuestData"
local KIND = { n = "npc", o = "object", i = "item" }

local db               -- the loaded data (LefthyToolsQuestData, or the test data)
local tried, why       -- loading was tried; why the data isn't there ("MISSING", "DISABLED", ...)
local quests = {}      -- id -> quest table (false: not in the data), read when first asked for
local actors = { n = {}, o = {}, i = {} } -- a giver's or ender's table, shared by its quests
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

-- A giver's or ender's table: { kind = "npc"|"object"|"item", id, name, points = { { map, x, y } } }.
local function Actor(key)
	local letter, id = key:match("^(%a)(%d+)$")
	if not KIND[letter] then return nil end
	id = tonumber(id)
	local known = actors[letter][id]
	if known then return known end
	local text = db and db[KIND[letter] == "npc" and "npcs" or KIND[letter] == "object" and "objects" or "items"]
	text = text and text[id]
	local actor = { kind = KIND[letter], id = id, points = {} }
	if type(text) == "string" then
		local name, places = text:match("^([^|]*)|?(.*)$")
		actor.name = name ~= "" and name or nil
		if places and places ~= "" then
			for place in places:gmatch("[^;]+") do actor.points[#actor.points + 1] = Place(place) end
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
		repeatable = flags:find("r", 1, true) ~= nil, new = flags:find("n", 1, true) ~= nil,
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

-- The quest table (see the contract in docs/questtree.md), or nil. Shared: never written by callers.
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
			entry = { map = map, continent = Num(f[1]), minLevel = Num(f[2]) or 0, maxLevel = Num(f[3]) or 0, name = f[4], quests = Ids(f[5]) }
		elseif type(text) == "table" then
			entry = { map = map, continent = text.continent, minLevel = text.minLevel or 0, maxLevel = text.maxLevel or 0, name = text.name,
				quests = {} }
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
				entry = { map = q.zone, name = q.zoneName or tostring(q.zone), minLevel = 0, maxLevel = 0, quests = {}, count = 0 }
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

-- A zone a learned quest is in, for Q.Zones (the client's name and continent).
local function ZoneEntry(map)
	local entry = zoneById[map]
	if entry then return entry end
	local info = C_Map and C_Map.GetMapInfo and select(2, pcall(C_Map.GetMapInfo, map))
	entry = { map = map, name = type(info) == "table" and info.name or tostring(map), continent = ContinentOf(map),
		minLevel = 0, maxLevel = 0, quests = {}, count = 0 }
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
		if type(fields[k]) == "table" then MergeActors(q, k, fields[k]) end
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
	searchIndex = nil
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
-- there. Only a Questtree window asks: never at login.
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
	end
	BuildTestIndex(normalized, zones)
	for _, q in ipairs(normalized) do
		local zone = q.zone and zoneById[q.zone]
		if zone and not byId[q.id].zoneName then q.zoneName = zone.name end
	end
	Changed()
	for _, fn in ipairs(listeners) do pcall(fn) end
end
