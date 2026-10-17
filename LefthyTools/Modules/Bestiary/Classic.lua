local _, ns = ...
local Bt = ns.Bestiary
local M = Bt.module
local NONE, issecret = Bt.NONE, Bt.issecret

-- The classic drop database beside your own numbers (setting dropData): what a classic world
-- database says each kind of mob can drop (LefthyTools_DropData, an add-on of its own: GPL v3 like
-- its source, CMaNGOS Classic DB), loaded when first needed. Forever is classic content (the same
-- mob and item IDs) but may differ, so it's never mixed into your numbers: your drops show its
-- chance beside yours, and what you haven't seen yet shows faded. It also has each kind's health,
-- for Beacon's fight stream (Bt.Health).

local DATA_ADDON = "LefthyTools_DropData"
local known = {}           -- creature ID -> what the database says (false: not in it), read when first asked
local knownOf              -- the database those were read from (another one: read again)
local dataTried = false    -- loading it was tried (again after a setting changes)
local dataWhy              -- why it isn't there (LoadAddOn's reason: "MISSING", "DISABLED", ...)

-- The database, loaded the first time it's needed (nil: switched off, not installed or disabled).
local function DropData()
	if not (M.db and M.db.dropData) then
		return nil
	end
	if type(LefthyToolsDropData) ~= "table" and not dataTried then
		dataTried = true
		local load = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
		if load then
			local ok, loaded, why = pcall(load, DATA_ADDON)
			dataWhy = not (ok and loaded) and tostring(ok and why or "error") or nil
		else
			dataWhy = "no LoadAddOn"
		end
	end
	local db = LefthyToolsDropData
	return type(db) == "table" and type(db.mobs) == "table" and db or nil
end

-- "<item>:<quality>:<chance in hundredths of a percent>[q],...[;s=<skinning, the same>][;g=<min>-<max>]
-- [;h=<min level>[-<max level>]:<health at the min level>[-<at the max level>]]"
-- (tools/update-drop-data.js). A part of a kind it doesn't know is skipped (builds before the health
-- skip "h" that way).
local function ParseKnown(text)
	local entry = { items = {}, skins = {} }
	for part in text:gmatch("[^;]+") do
		local kind, rest = part:match("^(%a)=(.*)$")
		if kind == "g" then
			local low, high = rest:match("^(%d+)%-(%d+)$")
			entry.coin = low and { tonumber(low), tonumber(high) } or nil
		elseif kind == "h" then
			local low, high, lowHealth, highHealth = rest:match("^(%d+)%-?(%d*):(%d+)%-?(%d*)$")
			if low then
				low, lowHealth = tonumber(low), tonumber(lowHealth)
				entry.health = { low, tonumber(high) or low, lowHealth, tonumber(highHealth) or lowHealth }
			end
		elseif not kind or kind == "s" then
			local into = kind and entry.skins or entry.items
			for id, quality, chance, quest in (rest or part):gmatch("(%d+):(%d+):(%d+)(q?)") do
				into[tonumber(id)] = { tonumber(chance) / 10000, tonumber(quality), quest == "q" }
			end
		end
	end
	return entry
end

-- What the classic database says a kind of mob drops: { items = { [item ID] = { chance (0-1),
-- quality, quest (only while on its quest) } }, skins = (the same, per skinning), coin = { min, max }
-- (copper, or nil), health = { min level, max level, health at the min level, at the max } (or nil) };
-- nil: it doesn't know the mob, or there's no database. Each mob read once.
function Bt.Known(creature)
	local db = creature and DropData()
	if not db then
		return nil
	end
	if db ~= knownOf then
		known, knownOf = {}, db
	end
	if known[creature] == nil then
		local text = db.mobs[creature]
		known[creature] = type(text) == "string" and ParseKnown(text) or false
	end
	return known[creature] or nil
end

-- What the classic database says a kind of mob has at full health at a level (the fight stream's
-- estimate of mobs' health, StreamSense.lua): between its lowest and highest level in a straight
-- line (most kinds span a level or two); and the level that is for. A level outside its range: the
-- nearest end's (that level second, so the caller can scale it); not known (nil, or -1 for a boss's
-- "??"): its highest. nil: the database doesn't know it, or the Bestiary or the database is switched
-- off (then nothing is loaded).
function Bt.Health(creature, level)
	if not M.enabled then
		return nil
	end
	local entry = Bt.Known(creature)
	local health = entry and entry.health
	if not health then
		return nil
	end
	local low, high = health[1], health[2]
	if type(level) ~= "number" or issecret(level) or level < 1 or level >= high then
		return health[4], high
	elseif level <= low then
		return health[3], low
	end
	return math.floor(health[3] + (health[4] - health[3]) * (level - low) / (high - low)), level
end

-- The mobs the classic database says drop an item (not skinning): { { creature, chance }, ... }, the
-- likeliest first; found when first asked (the wish list). A plain find for "<item>:" over every
-- mob's text is quick; only the mobs it finds are looked at closer, and not kept read (a common item
-- comes from hundreds).
local knownSources, sourcesOf = {}, nil -- item ID -> that list; the database it was found in

function Bt.KnownSources(id)
	local db = DropData()
	if not (db and type(id) == "number") then
		return NONE
	end
	if db ~= sourcesOf then -- (another database: found anew)
		knownSources, sourcesOf = {}, db
	end
	local list = knownSources[id]
	if not list then
		list = {}
		local key, entry = id .. ":", "," .. id .. ":%d+:(%d+)"
		for creature, text in pairs(db.mobs) do
			if type(text) == "string" and text:find(key, 1, true) then
				local chance = ("," .. text:match("^[^;]*")):match(entry) -- (its drops: before ";s=" and ";g=")
				if chance then
					list[#list + 1] = { creature = creature, chance = tonumber(chance) / 10000 }
				end
			end
		end
		table.sort(list, function(a, b)
			if a.chance ~= b.chance then
				return a.chance > b.chance
			end
			return a.creature < b.creature
		end)
		knownSources[id] = list
	end
	return list
end

Bt.When("settings", function()
	dataTried = false -- (switched on again, or installed since: loading the database is tried again)
	wipe(knownSources)
end)

-- You can skin (Skinning, any rank): only then does what skinning gives count among what you could
-- have had (else every beast's leather would wait there forever).
local function CanSkin()
	for id in pairs(Bt.SKINNING) do
		if C_SpellBook and C_SpellBook.IsSpellKnown then
			local ok, known = pcall(C_SpellBook.IsSpellKnown, id)
			if ok and known == true then
				return true
			end
		end
		if IsPlayerSpell and IsPlayerSpell(id) == true then
			return true
		end
	end
	return false
end

-- The database beside your own: what it says this kind drops that you haven't had yet (entries like
-- Bt.Drops', unseen = true, chance = the database's, out = your kills or skinnings: the likeliest
-- first, then skinning), how many of its drops you've had, and of how many. Grey ones only with
-- showPoor; skinning only when you can skin or have skinned this kind. nil: the database doesn't
-- know it. countOnly: the counts, no list.
function Bt.Compare(creature, mob, showPoor, countOnly)
	local data = Bt.Known(creature)
	if not data then
		return nil
	end
	local unseen, found, total = {}, 0, 0
	local skins = next(data.skins) ~= nil and ((mob and (mob.skinned or 0) > 0) or CanSkin())
	for _, skin in ipairs(skins and { false, true } or { false }) do
		local part, mine = {}, mob and Bt.Part(mob, skin) or NONE
		for id, said in pairs(skin and data.skins or data.items) do
			if showPoor or said[2] ~= 0 then
				total = total + 1
				if mine[id] then
					found = found + 1
				elseif not countOnly then
					part[#part + 1] = { id = id, chance = said[1], quality = said[2], quest = said[3] or nil, skin = skin, unseen = true,
						drops = 0, count = 0, classic = said[1], out = mob and (skin and (mob.skinned or 0) or mob.kills) or 0 }
				end
			end
		end
		table.sort(part, Bt.Likelier)
		for _, entry in ipairs(part) do
			unseen[#unseen + 1] = entry
		end
	end
	return unseen, found, total
end

-- /bestiary data: whether the database is there and what it holds (English, like the other chat lines).
function Bt.PrintData()
	if not M.db.dropData then
		M:Print("the classic drop database is switched off (settings).")
		return
	end
	local db = DropData()
	if not db then
		M:Print(("the classic drop database isn't there (%s): the add-on %s is missing or switched off in the add-on list.")
			:format(dataWhy or "?", DATA_ADDON))
		return
	end
	local count, health = 0, 0
	for _, text in pairs(db.mobs) do
		count = count + 1
		if type(text) == "string" and text:find(";h=", 1, true) then
			health = health + 1
		end
	end
	M:Print(("the classic drop database: %d kinds of mobs, %d of them with their health, from %s.")
		:format(count, health, tostring(db.source)))
end
