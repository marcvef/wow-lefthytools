local _, ns = ...
local W = ns.WhyPoor or {}
ns.WhyPoor = W

-- The money data add-on (LefthyTools_MoneyData, GPL v3 like its source; made by tools/update-money-data.js):
-- the creatures worth farming and where they spawn, gathering nodes per zone map, fishing per zone,
-- pickpocketing, disenchanting and limited vendor stock (W.Data). Loaded the first time something asks
-- (C_AddOns.LoadAddOn, like the Bestiary's drop data): never at login. Its tables stay strings; each entry is
-- read when first asked and kept. docs/whypoor.md has the contract, the add-on's README every field's source.
-- Everything here is the classic world database's (basis "classic"), but the reactions players saw on Forever
-- (seenA, seenH), the gathering skills (Forever's client), prices from Forever's client (basis "forever") and
-- the disenchanting skill (Forever's client).

local Dt = W.Data or {}
W.Data = Dt

Dt.ADDON = "LefthyTools_MoneyData"
Dt.TYPES = { "Beast", "Dragonkin", "Demon", "Elemental", "Giant", "Undead", "Humanoid", "Critter", "Mechanical", "Not specified", "Totem" }
Dt.RANKS = { n = "normal", e = "elite", r = "rare", R = "rareelite", b = "boss" }
Dt.REACT = { h = "hostile", n = "neutral", f = "friendly" }
Dt.SKINS = { l = "leather", h = "herb", o = "ore" }

-- db: the loaded data table; tried: loading was asked once; why: the game's reason it isn't there; cache: what
-- was read, per table and key (false: not there).
Dt.db, Dt.tried, Dt.why = nil, false, nil
Dt.cache = {}

local function Fields(text)
	local out = {}
	for f in (text .. "|"):gmatch("([^|]*)|") do out[#out + 1] = f end
	return out
end

-- Loads the data the first time (true when it's there). Asked once: a missing or disabled add-on isn't asked
-- again (one loaded by someone else meanwhile is taken).
function Dt.Load()
	if Dt.db then return true end
	local data = rawget(_G, "LefthyToolsMoneyData")
	if type(data) ~= "table" and not Dt.tried then
		Dt.tried = true
		local load = C_AddOns and C_AddOns.LoadAddOn or rawget(_G, "LoadAddOn")
		if load then
			local ok, loaded, reason = pcall(load, Dt.ADDON)
			if not (ok and loaded) then Dt.why = tostring(ok and reason or "error") end
		else
			Dt.why = "no LoadAddOn"
		end
		data = rawget(_G, "LefthyToolsMoneyData")
	end
	if type(data) ~= "table" or type(data.mobs) ~= "table" then
		if Dt.tried then Dt.why = Dt.why or "BROKEN" end
		return false
	end
	Dt.Use(data)
	return true
end

-- Uses a data table in the add-on's format (also the tests' hook).
function Dt.Use(data)
	Dt.db, Dt.why = data, nil
	Dt.cache = {}
end

-- Whether it's loaded now (asking doesn't load it).
function Dt.IsLoaded()
	return Dt.db ~= nil
end

-- Why there's no data: nil when it's loaded or not asked for yet, else the game's reason ("MISSING", ...).
function Dt.Problem()
	return not Dt.db and Dt.why or nil
end

-- What the data says about itself: { source, build }, nil without data.
function Dt.Info()
	if not Dt.db then return nil end
	return { source = Dt.db.source, build = Dt.db.build }
end

-- An entry of one of the data's tables, read by fn(text) once and kept (nil: not there or no data).
function Dt.Read(tableName, key, fn)
	if key == nil or not Dt.Load() then return nil end
	local byKey = Dt.cache[tableName]
	if not byKey then
		byKey = {}
		Dt.cache[tableName] = byKey
	end
	local v = byKey[key]
	if v == nil then
		local list = Dt.db[tableName]
		local text = type(list) == "table" and list[key] or nil
		v = text ~= nil and fn(text) or false
		byKey[key] = v
	end
	return v or nil
end

-- "item:chance[:count[:flag]],..." -> { { item, chance (0..1), min, max, event (only during a game event),
-- side ("Alliance"/"Horde": only for it) }, ... }, the likeliest first.
function Dt.ParseLoot(text)
	local out = {}
	for part in (text or ""):gmatch("[^,]+") do
		local item, chance, count, flag = part:match("^(%d+):(%d+):?([%d%-]*):?(%a*)$")
		if item then
			local low, high = count:match("^(%d+)%-(%d+)$")
			low = tonumber(low or count) or 1
			out[#out + 1] = {
				item = tonumber(item), chance = tonumber(chance) / 10000, min = low, max = tonumber(high) or low,
				event = flag == "e" or nil, side = flag == "A" and "Alliance" or flag == "H" and "Horde" or nil,
			}
		end
	end
	return out
end

-- "x,y,r,n[,up]" (with map first when withMap) -> { map, x, y, r, n, up } (0..1; up: about how many are up at once).
function Dt.ParseCluster(text, withMap)
	local nums = {}
	for v in text:gmatch("[^,]+") do nums[#nums + 1] = tonumber(v) end
	local at = withMap and 1 or 0
	if #nums < 4 + at then return nil end
	local n = nums[4 + at]
	return {
		map = withMap and nums[1] or nil, x = nums[1 + at] / 1000, y = nums[2 + at] / 1000, r = nums[3 + at] / 1000,
		n = n, up = nums[5 + at] or n,
	}
end

function Dt.ParseMob(text)
	local f = Fields(text)
	local flags = f[8] or ""
	local spots = {}
	for c in (f[10] or ""):gmatch("[^;]+") do spots[#spots + 1] = Dt.ParseCluster(c, true) end
	return {
		name = f[1], rank = Dt.RANKS[f[2]] or "normal", type = Dt.TYPES[tonumber(f[3]) or 0],
		skin = Dt.SKINS[f[4]], reactA = Dt.REACT[f[5]], reactH = Dt.REACT[f[6]], respawn = tonumber(f[7]),
		instance = flags:find("i", 1, true) ~= nil, civilian = flags:find("c", 1, true) ~= nil or nil,
		seenA = flags:find("A", 1, true) ~= nil or nil, seenH = flags:find("H", 1, true) ~= nil or nil,
		rep = tonumber(f[9]), spots = #spots > 0 and spots or nil, basis = "classic",
	}
end

-- A creature worth farming: { name, rank ("normal", "elite", "rare", "rareelite", "boss"), type ("Humanoid",
-- "Beast", ...), skin ("leather" or nil), reactA, reactH ("hostile", "neutral", "friendly": to a new character
-- of that side; nil unknown), respawn (seconds), instance (only in dungeons and raids), civilian, rep (its
-- faction's ID when its reaction is by reputation: killing it costs standing), seenA / seenH (that reaction
-- is what players saw on Forever), basis = "classic" } or nil (not in the data: not farmable, or no data).
function Dt.Mob(creature)
	return Dt.Read("mobs", creature, Dt.ParseMob)
end

-- Where it spawns on zone maps: { { map, x, y, r, n, up }, ... } the most spawns first; nil: nowhere outdoors.
function Dt.Spots(creature)
	local mob = Dt.Mob(creature)
	return mob and mob.spots or nil
end

function Dt.ParseIds(text)
	local out = {}
	for id in text:gmatch("%d+") do out[#out + 1] = tonumber(id) end
	return out
end

-- The creatures (in the data) that spawn on a zone map: a list of IDs (empty: none or no data).
function Dt.MobsOn(map)
	return Dt.Read("zones", map, Dt.ParseIds) or {}
end

function Dt.ParseObject(text)
	local f = Fields(text)
	local low, high = (f[5] or ""):match("^(%d+)%-?(%d*)$")
	low = tonumber(low) or 1
	return {
		name = f[1], kind = f[2], skill = tonumber(f[3]) or 0, respawn = tonumber(f[4]),
		uses = { low, tonumber(high) or low }, loot = Dt.ParseLoot(f[6]),
	}
end

-- A gathering object: { name, kind ("herb", "ore", "chest", "fish"), skill, respawn, uses = { min, max }, loot }.
function Dt.Object(id)
	return Dt.Read("objects", id, Dt.ParseObject)
end

function Dt.ParseNodes(text)
	local out = {}
	for part in text:gmatch("[^|]+") do
		local id, n, up, clusters = part:match("^(%d+):(%d+):([%d%.]+)=(.*)$")
		local obj = id and Dt.Object(tonumber(id))
		if obj then
			local spots = {}
			for c in clusters:gmatch("[^;]+") do spots[#spots + 1] = Dt.ParseCluster(c, false) end
			out[#out + 1] = {
				object = tonumber(id), name = obj.name, kind = obj.kind, skill = obj.skill, respawn = obj.respawn, uses = obj.uses,
				loot = obj.loot, spots = spots, n = tonumber(n), up = tonumber(up), basis = "classic",
			}
		end
	end
	return out
end

-- Gathering nodes on a zone map: { { object, name, kind ("herb", "ore", "chest", "fish": a school), skill (the
-- Herbalism or Mining needed, Forever's client; a chest's Lockpicking, 0 for anyone; a school: the zone's
-- fishing), respawn, uses = { min, max } (times one can be looted), loot, spots = { { x, y, r, n, up } }, n (spawn
-- points on the map), up (about how many are up at once) }, ... } (empty: none or no data).
function Dt.Nodes(map)
	return Dt.Read("nodes", map, Dt.ParseNodes) or {}
end

-- A fishing area from "base|loot": base (classic's skill_fishing_base_level), low (the least skill that
-- catches anything), skill (sure catches, no getaways: base + 95), loot.
function Dt.ParseFishing(base, loot)
	base = tonumber(base) or 0
	return { base = base, low = math.max(1, base), skill = math.max(1, base + 95), loot = Dt.ParseLoot(loot) }
end

function Dt.ParseZoneFishing(text)
	local f = Fields(text)
	return Dt.ParseFishing(f[1], f[2])
end

-- Fishing on a zone map: { skill (to fish without getaways), low (the least that catches anything), base, loot,
-- areas = { { area, name, skill, low, base, loot }, ... } (its subzones that differ), basis = "classic" } or nil.
function Dt.Fishing(map)
	local zone = Dt.Read("fishing", map, Dt.ParseZoneFishing)
	if zone and not zone.areas then
		zone.areas, zone.basis = {}, "classic"
		local list = {}
		for area in pairs(Dt.db.fishingAreas or {}) do list[#list + 1] = area end
		table.sort(list)
		for _, area in ipairs(list) do
			local f = Fields(Dt.db.fishingAreas[area])
			if tonumber(f[1]) == map then
				local a = Dt.ParseFishing(f[3], f[4])
				a.area, a.name = area, f[2]
				zone.areas[#zone.areas + 1] = a
			end
		end
	end
	return zone
end

-- What picking a creature's pockets can give: { { item, chance, min, max }, ... } or nil.
function Dt.Pickpocket(creature)
	return Dt.Read("pickpocket", creature, Dt.ParseLoot)
end

function Dt.ParseDisenchant(value)
	local group, skill = tostring(value):match("^(%d+):?(%d*)$")
	local loot = group and Dt.db.disenchantLoot and Dt.db.disenchantLoot[tonumber(group)]
	if not loot then return false end
	return { skill = tonumber(skill) or 1, results = Dt.ParseLoot(loot), basis = "classic" }
end

-- Disenchanting an item: { skill (Enchanting needed: Forever's client asks none beyond knowing it, 1), results =
-- { { item, chance, min, max }, ... } (classic's), basis = "classic" } or nil (can't be, or not known).
function Dt.Disenchant(item)
	return Dt.Read("disenchant", item, Dt.ParseDisenchant)
end

function Dt.ParseVendor(text)
	local f = Fields(text)
	local map, x, y = (f[4] or ""):match("^(%d+),(%d+),(%d+)$")
	return { name = f[1], reactA = Dt.REACT[f[2]], reactH = Dt.REACT[f[3]], map = tonumber(map), x = x and tonumber(x) / 1000, y = y and tonumber(y) / 1000 }
end

function Dt.ParseLimited(text)
	local f = Fields(text)
	local price, count, basis = tonumber(f[1]), tonumber(f[2]) or 1, f[3] == "f" and "forever" or "classic"
	local out = {}
	for npc, stock, restock in (f[4] or ""):gmatch("(%d+):(%d+):(%d+)") do
		npc = tonumber(npc)
		local v = Dt.Read("vendors", npc, Dt.ParseVendor) or {}
		out[#out + 1] = {
			npc = npc, name = v.name, map = v.map, x = v.x, y = v.y, reactA = v.reactA, reactH = v.reactH,
			stock = tonumber(stock), restock = tonumber(restock), price = price, count = count, basis = basis,
		}
	end
	return #out > 0 and out or false
end

-- Vendors selling an item in limited stock: { { npc, name, map, x, y (nil: no zone map), reactA, reactH (who can
-- buy), stock, restock (seconds until one more), price (copper for count items, before reputation discounts),
-- count, basis ("forever": the price is Forever's client's; "classic") }, ... } or nil.
function Dt.Limited(item)
	return Dt.Read("limited", item, Dt.ParseLimited)
end

-- Every item some vendor sells in limited stock (a sorted list; empty without data).
function Dt.LimitedItems()
	if not Dt.Load() then return {} end
	if not Dt.cache.limitedItems then
		local list = {}
		for item in pairs(Dt.db.limited or {}) do list[#list + 1] = item end
		table.sort(list)
		Dt.cache.limitedItems = list
	end
	return Dt.cache.limitedItems
end
