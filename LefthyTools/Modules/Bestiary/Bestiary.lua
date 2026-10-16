local _, ns = ...
local LT = ns.LT
local L = ns.L

-- Bestiary: what the mobs you kill drop. A database of your own (LefthyToolsBestiaryDB: all your
-- characters add to it, nothing goes to friends) per kind of mob (creature ID, from its GUID): how
-- many you killed, which items dropped how often and how many, and the coin. Window.lua shows your
-- target's (a window that stays open, a minimap button) and, if you like, a hovered enemy's next to
-- the mouse.
--
-- Counting so the chances hold:
--   * a kill counts once its corpse is looted, or once the game says it's empty (CanLootUnit, a
--     moment after it died): a corpse left lying would count as a kill that dropped nothing. The
--     game can be wrong (in game: "empty" for a corpse with two items): looted after all, its items
--     join that kill;
--   * your (or your pet's) killing blow (PARTY_KILL), or any corpse you loot: it was yours;
--   * on your own only: in a group the loot goes round, so you'd see only part of it;
--   * a corpse's loot once (the first time it opens); not right after skinning, a pickpocket or
--     gathering (NOT_A_KILL), nor what isn't a creature's (herbs, ore, chests, fishing, a bag's
--     contents: their source isn't a creature);
--   * coin: what your money grew by while the loot window was open.
-- Skinning is kept apart: what you skin from a kind of mob, each corpse once, per skinning (also in
-- a group: what you skin is yours). /bestiary log shows the last loot windows and kills and what was
-- made of them.
--
-- LefthyToolsBestiaryDB = { mobs = { [creatureID] = { name, level, class, kills, money (copper),
--   first, last (time()), items = { [itemID] = { drops (corpses it came from), count, quality,
--   name } }, skinned (how many), skins = { [itemID] = { times, count, quality, name } } } } }
--
-- Beside your own numbers (setting dropData): what a classic world database says each kind of mob
-- can drop (LefthyTools_DropData, a separate add-on: GPL v3 like its source, CMaNGOS Classic DB),
-- loaded when first needed. Forever is classic content (the same mob and item IDs) but may differ, so
-- it's never mixed into your numbers: your drops show its chance beside yours, and what you haven't
-- seen yet shows faded.

local M = LT:NewModule("bestiary", {
	title = "Bestiary",
	description = L["What the mobs you kill drop: a window for your target with each drop, how many you got and the drop chance, from your own kills. Kept for all your characters, only on your computer."],
	defaults = {
		minimapButton = true,
		minimapAngle = 150,  -- degrees, 0 = right, counter-clockwise: the upper left
		showPoor = true,     -- grey items in the lists
		hoverCard = false,   -- the drops next to the mouse over an enemy
		itemTooltip = true,  -- an item's tooltip: the mobs it comes from likeliest, with the chance
		dropData = true,     -- compare with the classic drop database (LefthyTools_DropData)
		window = {},         -- shown, point, x, y
	},
})

local Bt = { module = M }
ns.Bestiary = Bt

local EMPTY_CHECKS = { 2, 6 }  -- seconds after a kill: is its corpse empty? (both times: then it counts)
local PENDING_FOR = 300         -- a corpse not looted in this long: not counted
local CAST_GAP = 1.5            -- skinning (a pickpocket, gathering) this shortly before the loot window: not a kill's loot
local SEEN_KEEP = 200           -- mobs remembered (name, level) from target, mouseover and nameplates
local LOG_KEEP = 12             -- loot windows remembered with what was made of them (/bestiary log)
-- Spells whose loot isn't a kill's (each rank's ID, and by name for ranks not listed): Skinning,
-- Pick Pocket, Mining, Herb Gathering. Any other spell just before looting (a killing blow, then a
-- quick loot) doesn't matter.
local NOT_A_KILL = { 8613, 8617, 8618, 10768, 921, 2575, 2576, 3564, 10248, 2366, 2368, 3570, 11993 }
local SKINNING = { [8613] = true, [8617] = true, [8618] = true, [10768] = true }
Bt.SKIN_ICON = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01" -- (Skinning's own icon)
local issecret = issecretvalue or function() return false end

local data                       -- LefthyToolsBestiaryDB
local pending = {}               -- GUID -> { at, creature }: killed, its loot not seen yet
local done = {}                  -- GUID -> time: counted (or its loot seen); kept a while
local seen, seenOrder = {}, {}   -- GUID -> { name, level, class }
local castAt = -math.huge        -- when one of the NOT_A_KILL spells went off
local castSkin = false           -- and it was Skinning
local notKillIDs, notKillNames   -- NOT_A_KILL as a set, and their names (read once); Skinning's name
local skinName
local skinnedCorpse = {}         -- GUID -> time: skinned (once each)
local lootMoney, lootSource      -- while the loot window is open: money before, the corpse
local lootSeen = false           -- this loot window was looked at (LOOT_READY or LOOT_OPENED)
local listeners = {}
local events = CreateFrame("Frame")

---------------------------------------------------------------------------
-- The database
---------------------------------------------------------------------------

-- A creature's ID from its GUID ("Creature-0-<server>-<instance>-<zone>-<ID>-<spawn>"); nil for
-- players, pets of players, objects and hidden ones.
function Bt.CreatureOf(guid)
	if type(guid) ~= "string" or issecret(guid) then
		return nil
	end
	return tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-") or guid:match("^Vehicle%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
end

-- A kind of mob's record (nil: never killed or seen).
function Bt.Mob(creature)
	return data and creature and data.mobs[creature]
end

local function MobFor(creature)
	local mob = data.mobs[creature]
	if not mob then
		mob = { kills = 0, money = 0, items = {} }
		data.mobs[creature] = mob
	end
	return mob
end

-- Something changed for a kind of mob (the window and the card redraw).
function Bt.OnChanged(fn)
	listeners[#listeners + 1] = fn
end

local sources -- item ID -> where it comes from (Bt.Sources), built when asked after a change

local function Changed(creature)
	sources = nil
	for _, fn in ipairs(listeners) do
		local ok, err = pcall(fn, creature)
		if not ok then
			geterrorhandler()(err)
		end
	end
end

local NONE = {}

-- A kind's drops (skin: what skinning it gave), never nil. (Not `skin and mob.skins or mob.items`:
-- without skinnings that falls back to the drops.)
function Bt.Part(mob, skin)
	if skin then
		return mob.skins or NONE
	end
	return mob.items
end

-- A drop's chance, 0-1, and how many came per drop (out of kills, or skinnings for skin = true).
function Bt.Chance(mob, item, skin)
	local out = skin and (mob.skinned or 0) or mob.kills
	return out > 0 and math.min(1, item[1] / out) or 0, item[1] > 0 and item[2] / item[1] or 0
end

local function Likelier(a, b)
	if a.chance ~= b.chance then
		return a.chance > b.chance
	elseif a.quality ~= b.quality then
		return a.quality > b.quality
	end
	return a.id < b.id
end

-- World drops: random green and better gear drops from any mob of about its level, so with one mob
-- it says nothing about that mob (the user: a random BoE "forever stuck to that mob"). An item is
-- one when it's gear (a weapon or armour that can be worn: GetItemInfoInstant) of green or better
-- that doesn't bind on pickup (unknown yet: taken as one), or when it came from WORLD_KINDS or more
-- kinds of mobs. They gather in one place at the end of a mob's drops.
local WORLD_KINDS = 3

function Bt.IsWorldDrop(id, quality)
	local list = Bt.Sources(id)
	if list and #list >= WORLD_KINDS then
		return true
	end
	if (quality or 0) < 2 or not (C_Item and C_Item.GetItemInfoInstant) then
		return false
	end
	local ok, _, _, _, equipLoc, _, classID = pcall(C_Item.GetItemInfoInstant, id)
	if not ok or (classID ~= 2 and classID ~= 4) or type(equipLoc) ~= "string" or equipLoc == ""
		or equipLoc == "INVTYPE_NON_EQUIP_IGNORE" then
		return false
	end
	local bind = C_Item.GetItemInfo and select(14, C_Item.GetItemInfo(("item:%d"):format(id)))
	return bind ~= 1 -- (1: binds on pickup, a mob's own)
end

-- A kind's drops, the likeliest first (ties: better quality first), then what skinning it gives
-- (skin = true, the chance per skinning), then its world drops gathered in one entry ({ group =
-- the world drops, quality = the best of them }): { { id, drops, count, quality, chance, each,
-- skin, name, out (kills or skinnings), classic, quest }, ... }. Grey ones only with showPoor.
-- With its creature ID, the classic database beside it: classic = its chance there (false: the
-- database knows the mob but not this drop), quest = only while on a quest.
function Bt.Drops(mob, showPoor, creature)
	local list, world = {}, {}
	local known = Bt.Known(creature)
	for _, skin in ipairs({ false, true }) do
		local part = {}
		local classic = known and (skin and known.skins or known.items)
		for id, item in pairs(mob and Bt.Part(mob, skin) or {}) do
			local quality = item[3] or 1
			if showPoor or quality ~= 0 then
				local chance, each = Bt.Chance(mob, item, skin)
				local said = classic and classic[id]
				local entry = { id = id, drops = item[1], count = item[2], quality = quality, chance = chance, each = each,
					skin = skin, name = item[4], out = skin and mob.skinned or mob.kills, quest = said and said[3] or nil }
				if said then
					entry.classic = said[1]
				elseif classic then
					entry.classic = false -- (not `classic and false or nil`: that's always nil)
				end
				if not skin and Bt.IsWorldDrop(id, quality) then
					world[#world + 1] = entry
				else
					part[#part + 1] = entry
				end
			end
		end
		table.sort(part, Likelier)
		for _, entry in ipairs(part) do
			list[#list + 1] = entry
		end
	end
	if #world > 0 then
		table.sort(world, Likelier)
		local best = 0
		for _, entry in ipairs(world) do
			best = math.max(best, entry.quality)
		end
		list[#list + 1] = { id = 0, group = world, quality = best, chance = 0, drops = 0, count = #world }
	end
	return list
end

-- Where an item comes from: { { creature, mob, chance, out (kills or skinnings), skin }, ... }, the
-- likeliest first (then the more kills behind it); nil: nowhere yet. Built over the whole
-- database when first asked after a change (item tooltips, the ledger's search).
local function Likeliest(a, b)
	if a.chance ~= b.chance then
		return a.chance > b.chance
	end
	return a.out > b.out
end

function Bt.Sources(itemID)
	if not sources then
		sources = {}
		for creature, mob in pairs(data and data.mobs or {}) do
			for _, skin in ipairs({ false, true }) do
				for id, item in pairs(Bt.Part(mob, skin)) do
					local chance = Bt.Chance(mob, item, skin)
					if chance > 0 then
						local list = sources[id] or {}
						sources[id] = list
						list[#list + 1] = { creature = creature, mob = mob, chance = chance, skin = skin,
							out = skin and mob.skinned or mob.kills, quality = item[3] }
					end
				end
			end
		end
		for _, list in pairs(sources) do
			table.sort(list, Likeliest)
		end
	end
	return sources[itemID]
end

---------------------------------------------------------------------------
-- The classic drop database (LefthyTools_DropData)
---------------------------------------------------------------------------

local DATA_ADDON = "LefthyTools_DropData"
local known = {}           -- creature ID -> what the database says (false: not in it), read when first asked
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

-- "<item>:<quality>:<chance in hundredths of a percent>[q],...[;s=<skinning, the same>][;g=<min>-<max>]"
-- (tools/update-drop-data.js).
local function ParseKnown(text)
	local entry = { items = {}, skins = {} }
	for part in text:gmatch("[^;]+") do
		local kind, rest = part:match("^(%a)=(.*)$")
		if kind == "g" then
			local low, high = rest:match("^(%d+)%-(%d+)$")
			entry.coin = low and { tonumber(low), tonumber(high) } or nil
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
-- (copper, or nil) }; nil: it doesn't know the mob, or there's no database. Each mob read once.
function Bt.Known(creature)
	local db = creature and DropData()
	if not db then
		return nil
	end
	if known[creature] == nil then
		local text = db.mobs[creature]
		known[creature] = type(text) == "string" and ParseKnown(text) or false
	end
	return known[creature] or nil
end

-- You can skin (Skinning, any rank): only then does what skinning gives count among what you could
-- have had (else every beast's leather would wait there forever).
local function CanSkin()
	for id in pairs(SKINNING) do
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
		table.sort(part, Likelier)
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
	local count = 0
	for _ in pairs(db.mobs) do
		count = count + 1
	end
	M:Print(("the classic drop database: %d kinds of mobs, from %s."):format(count, tostring(db.source)))
end

---------------------------------------------------------------------------
-- Mobs seen: name, level, kind (for records and the window)
---------------------------------------------------------------------------

local function Value(f, ...)
	if not f then
		return nil
	end
	local ok, v = pcall(f, ...)
	if ok and not issecret(v) then
		return v
	end
end

-- Remembers a unit that's a creature; returns its GUID and creature ID.
function Bt.Look(unit)
	local guid = Value(UnitGUID, unit)
	local creature = Bt.CreatureOf(guid)
	if not creature or Value(UnitIsPlayer, unit) then
		return nil
	end
	local info = seen[guid]
	if not info then
		info = {}
		seen[guid] = info
		seenOrder[#seenOrder + 1] = guid
		if #seenOrder > SEEN_KEEP then
			seen[table.remove(seenOrder, 1)] = nil
		end
	end
	info.name = Value(UnitName, unit) or info.name
	info.level = Value(UnitLevel, unit) or info.level
	info.class = Value(UnitClassification, unit) or info.class
	local mob = data and data.mobs[creature]
	if mob then -- (its name and level as last seen)
		mob.name, mob.level, mob.class = info.name or mob.name, info.level or mob.level, info.class or mob.class
	end
	return guid, creature
end

function Bt.Seen(guid)
	return seen[guid]
end

---------------------------------------------------------------------------
-- Kills and loot
---------------------------------------------------------------------------

local function Solo()
	return not (IsInGroup and IsInGroup())
end

-- What was made of a loot window or a kill, the last LOG_KEEP (/bestiary log; kept for a look
-- after a /reload): { time, mob (creature ID), what, items (how many), check (CanLootUnit's
-- answers) }.
local function Log(creature, what, items, check)
	if not data then
		return
	end
	data.log = type(data.log) == "table" and data.log or {}
	table.insert(data.log, 1, { time(), creature, what, items, check })
	for i = #data.log, LOG_KEEP + 1, -1 do
		data.log[i] = nil
	end
end

-- /bestiary log: the newest first, in chat (English, like the other chat lines).
function Bt.PrintLog()
	local log = data and type(data.log) == "table" and data.log or {}
	if #log == 0 then
		M:Print("nothing yet: no loot window or kill since the log began.")
		return
	end
	M:Print("the last loot windows and kills, newest first:")
	for _, entry in ipairs(log) do
		local mob = entry[2] and data.mobs[entry[2]]
		local who = mob and mob.name or entry[2] and ("creature " .. entry[2]) or "?"
		print(("  %s  %s: %s%s%s"):format(date("%H:%M:%S", entry[1]), who, entry[3],
			(entry[4] or 0) > 0 and (", " .. entry[4] .. " item(s)") or "", entry[5] and (" (loot check " .. entry[5] .. ")") or ""))
	end
end

-- A kill counted (once per corpse). how: "looted" or "empty" (the game said there's nothing on it:
-- if it's looted after all, its items still join this kill).
local function Count(guid, creature, how)
	done[guid] = { at = time(), how = how }
	pending[guid] = nil
	local mob = MobFor(creature)
	mob.kills, mob.last = mob.kills + 1, time()
	mob.first = mob.first or mob.last
	local info = seen[guid]
	if info then
		mob.name, mob.level, mob.class = info.name or mob.name, info.level or mob.level, info.class or mob.class
	end
	return mob
end

-- A corpse not looted yet: empty? (CanLootUnit: hasLoot.) Twice, a few seconds apart: its loot can
-- take a moment to show.
local function CheckEmpty(guid, round)
	local kill = pending[guid]
	if not kill then
		return
	end
	local ok, hasLoot, canLoot = pcall(CanLootUnit, guid)
	kill.check = ("%s/%s"):format(tostring(ok and not issecret(hasLoot) and hasLoot), tostring(ok and not issecret(canLoot) and canLoot))
	if not ok or issecret(hasLoot) or hasLoot then
		return -- (has loot, or can't tell: counted when it's looted)
	end
	if round < #EMPTY_CHECKS then
		C_Timer.After(EMPTY_CHECKS[round + 1] - EMPTY_CHECKS[round], function() CheckEmpty(guid, round + 1) end)
	else
		Count(guid, kill.creature, "empty")
		Log(kill.creature, "empty", 0, kill.check)
		Changed(kill.creature)
	end
end

local function OnKill(attacker, target)
	if issecret(attacker) or issecret(target) or not Solo() or done[target] or pending[target] then
		return
	end
	if attacker ~= Value(UnitGUID, "player") and attacker ~= Value(UnitGUID, "pet") then
		return
	end
	local creature = Bt.CreatureOf(target)
	if not creature then
		return
	end
	if Value(UnitGUID, "target") == target then
		Bt.Look("target")
	end
	pending[target] = { at = GetTime(), creature = creature }
	if CanLootUnit then
		C_Timer.After(EMPTY_CHECKS[1], function() CheckEmpty(target, 1) end)
	end
end

-- The corpse a loot window is for: its GUID (GetLootSourceInfo; when that says nothing, your dead
-- target, else the one kill waiting from the last minute).
local function LootSource()
	local source
	for slot = 1, GetNumLootItems() do
		local guid = GetLootSourceInfo and Value(GetLootSourceInfo, slot)
		if guid then
			if source and source ~= guid then
				return nil -- (several corpses at once: not told apart)
			end
			source = guid
		end
	end
	if not source and Value(UnitIsDead, "target") then
		source = Bt.CreatureOf(Value(UnitGUID, "target")) and Value(UnitGUID, "target")
	end
	if not source then
		local now, only = GetTime(), nil
		for guid, kill in pairs(pending) do
			if now - kill.at < 60 then
				if only then
					return nil
				end
				only = guid
			end
		end
		source = only
	end
	return source
end

-- Is this spell one whose loot isn't a kill's (skinning, a pickpocket, gathering)? And is it Skinning?
local function NotAKill(spellID)
	local GetName = C_Spell and C_Spell.GetSpellName
	if not notKillIDs then
		notKillIDs, notKillNames = {}, {}
		for _, id in ipairs(NOT_A_KILL) do
			notKillIDs[id] = true
			local name = Value(GetName, id)
			if name then
				notKillNames[name] = true
			end
		end
		skinName = Value(GetName, 8613)
	end
	local name = not notKillIDs[spellID] and Value(GetName, spellID)
	if notKillIDs[spellID] or (name and notKillNames[name]) then
		return true, SKINNING[spellID] or (name ~= nil and name == skinName)
	end
	return false
end

-- Skinned: what came, per skinning of its kind (each corpse once; also in a group).
local function OnSkinned(guid, creature)
	if skinnedCorpse[guid] then
		return Log(creature, "skinned before", 0)
	end
	skinnedCorpse[guid] = time()
	local mob = MobFor(creature)
	mob.skinned = (mob.skinned or 0) + 1
	mob.skins = mob.skins or {}
	local items = 0
	for slot = 1, GetNumLootItems() do
		if Value(GetLootSlotType, slot) == 1 then
			local _, name, quantity, _, quality = GetLootSlotInfo(slot)
			local link = Value(GetLootSlotLink, slot)
			local id = type(link) == "string" and tonumber(link:match("|Hitem:(%d+)"))
			if id and not issecret(quantity) and not issecret(quality) then
				local skin = mob.skins[id] or { 0, 0, quality }
				mob.skins[id] = skin
				skin[1], skin[2], skin[3] = skin[1] + 1, skin[2] + math.max(1, tonumber(quantity) or 1), tonumber(quality) or skin[3]
				skin[4] = not issecret(name) and type(name) == "string" and name or skin[4]
				items = items + 1
			end
		end
	end
	Log(creature, "skinned", items)
	Changed(creature)
end

-- The loot window opened (LOOT_READY, before anything is taken; LOOT_OPENED if its slots weren't
-- there yet): a corpse's loot, the first time.
local function OnLoot()
	if lootSeen or not data then
		return
	end
	lootMoney, lootSource = nil, nil
	if GetNumLootItems() == 0 then
		return -- (not filled yet: LOOT_OPENED looks again)
	end
	lootSeen = true
	local guid = LootSource()
	local creature = Bt.CreatureOf(guid)
	local gathered = GetTime() - castAt < CAST_GAP
	if gathered and castSkin and creature then
		return OnSkinned(guid, creature)
	elseif IsFishingLoot and IsFishingLoot() then
		return
	elseif gathered then
		return Log(creature, "pickpocket or gathering", 0)
	elseif not Solo() then
		return Log(creature, "group", 0)
	elseif not creature then
		return Log(nil, guid and "not a mob" or "no corpse", 0)
	end
	local was, check = done[guid], pending[guid] and pending[guid].check
	if was and was.how ~= "empty" then
		return Log(creature, "looted before", 0)
	end
	local mob
	if was then -- (the game said it was empty: its items join that kill)
		mob = MobFor(creature)
		done[guid].how = "looted"
	else
		mob = Count(guid, creature, "looted")
	end
	local coin, items = false, 0
	for slot = 1, GetNumLootItems() do
		local kind = Value(GetLootSlotType, slot)
		if kind == 2 then -- (Enum.LootSlotType.Money)
			coin = true
		elseif kind == 1 then -- (Item)
			local _, name, quantity, _, quality = GetLootSlotInfo(slot)
			local link = Value(GetLootSlotLink, slot)
			local id = type(link) == "string" and tonumber(link:match("|Hitem:(%d+)"))
			if id and not issecret(quantity) and not issecret(quality) then
				local item = mob.items[id] or { 0, 0, quality }
				mob.items[id] = item
				item[1], item[2], item[3] = item[1] + 1, item[2] + math.max(1, tonumber(quantity) or 1), tonumber(quality) or item[3]
				item[4] = not issecret(name) and type(name) == "string" and name or item[4] -- (for the search)
				items = items + 1
			end
		end
	end
	if coin then
		lootMoney, lootSource = GetMoney(), creature
	end
	Log(creature, was and "looted (said empty before)" or "looted", items, check)
	Changed(creature)
end

-- The loot window closed: its coin is what the money grew by.
local function OnLootClosed()
	if lootMoney and lootSource then
		local gained = GetMoney() - lootMoney
		local mob = data.mobs[lootSource]
		if mob and gained > 0 then
			mob.money = mob.money + gained
			Changed(lootSource)
		end
	end
	lootMoney, lootSource, lootSeen = nil, nil, false
end

-- Old waiting kills and counted corpses go.
local function Prune()
	local now, wall = GetTime(), time()
	for guid, kill in pairs(pending) do
		if now - kill.at > PENDING_FOR then
			pending[guid] = nil
		end
	end
	for guid, counted in pairs(done) do
		if wall - counted.at > PENDING_FOR then
			done[guid] = nil
		end
	end
	for guid, at in pairs(skinnedCorpse) do
		if wall - at > PENDING_FOR then
			skinnedCorpse[guid] = nil
		end
	end
end

events:SetScript("OnEvent", function(_, event, a, b, c)
	if event == "PARTY_KILL" then
		OnKill(a, b)
		Prune()
	elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
		OnLoot()
	elseif event == "LOOT_CLOSED" then
		OnLootClosed()
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then -- unit, castGUID, spellID
		local notKill, skin = false, false
		if not issecret(c) then
			notKill, skin = NotAKill(c)
		end
		if notKill then
			castAt, castSkin = GetTime(), skin
		end
	elseif event == "PLAYER_TARGET_CHANGED" then
		Bt.Look("target")
		if Bt.TargetChanged then
			Bt.TargetChanged()
		end
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		Bt.Look("mouseover")
		if Bt.MouseoverChanged then
			Bt.MouseoverChanged()
		end
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		Bt.Look(a)
	end
end)

---------------------------------------------------------------------------
-- The module
---------------------------------------------------------------------------

LT.onLoad[#LT.onLoad + 1] = function()
	LefthyToolsBestiaryDB = type(LefthyToolsBestiaryDB) == "table" and LefthyToolsBestiaryDB or {}
	data = LefthyToolsBestiaryDB
	data.mobs = type(data.mobs) == "table" and data.mobs or {}
end

function M:OnEnable()
	for _, event in ipairs({ "PARTY_KILL", "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED", "PLAYER_TARGET_CHANGED",
			"UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED" }) do
		events:RegisterEvent(event)
	end
	events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	if Bt.Start then
		Bt.Start() -- (Window.lua: the button, the window as it was)
	end
end

function M:OnDisable()
	events:UnregisterAllEvents()
	wipe(pending)
	lootMoney, lootSource = nil, nil
	if Bt.Stop then
		Bt.Stop()
	end
end

function M:OnSettingChanged()
	dataTried = false -- (switched on again, or installed since: loading the database is tried again)
	if Bt.Settings then
		Bt.Settings()
	end
end

function M:BuildOptions(o)
	o:Header(L["Window"])
	o:Button(L["Open the Bestiary"], L["Open"], function() Bt.Toggle() end,
		L["Your target's drops: each item, how many you got and its drop chance. It stays open (Escape doesn't close it) and follows your target. Also /bestiary."])
	o:Checkbox("minimapButton", L["Minimap button"],
		L["A button on the edge of the minimap: click opens or closes the Bestiary, right-click these settings. Drag it to move it."])
	o:Button(L["Open the ledger"], L["Open"], function() Bt.ToggleLedger() end,
		L["Every mob you've killed, with its statistics and drops; search mobs and items. Also Ctrl-click on the minimap button, or /bestiary ledger."])
	o:Header(L["Drops"])
	o:Checkbox("hoverCard", L["Drops next to the mouse"],
		L["Hovering an enemy you've killed before shows its likeliest drops beside the mouse. Shift-click on the minimap button switches it on or off."])
	o:Checkbox("itemTooltip", L["Drop chances in item tooltips"],
		L["An item's tooltip (in your bags, in chat, anywhere) lists the three mobs it comes from likeliest, with the chance; a pelt marks skinning."])
	o:Checkbox("showPoor", L["Grey items"], L["Show grey (junk) items among the drops."])
	o:Checkbox("dropData", L["Compare with a drop database"],
		L["Beside your own numbers, what a classic world database (CMaNGOS) says each mob can drop: its chance on each of your drops, and what you haven't had yet, faded. WoW: Forever may differ. It's an add-on of its own, LefthyTools Drop Data, installed with LefthyTools; /bestiary data says whether it's there."])
end

function M:OnSlashCommand(msg)
	local cmd = strtrim(msg or ""):lower()
	if cmd == "" or cmd == "open" then
		Bt.Toggle()
	elseif cmd == "settings" or cmd == "options" then
		LT:OpenSettings(self)
	elseif cmd == "minimap" then
		LT:SetModuleSetting(self, "minimapButton", not self.db.minimapButton)
		self:Print("minimap button " .. (self.db.minimapButton and "on." or "off."))
	elseif cmd == "log" then
		Bt.PrintLog()
	elseif cmd == "data" then
		Bt.PrintData()
	elseif cmd == "ledger" or cmd:match("^ledger ") or cmd:match("^search ") then
		Bt.ToggleLedger(nil, strtrim(msg or ""):match("^%S+%s+(.+)$"))
	else
		self:Print("/bestiary - open or close the window (your target's drops)")
		self:Print("/bestiary ledger [search] - every mob you've killed, its drops; search mobs and items")
		self:Print("/bestiary log - the last loot windows and kills, and what was made of them")
		self:Print("/bestiary data - whether the classic drop database is there")
		self:Print("/bestiary minimap - show or hide the minimap button")
		self:Print("/bestiary settings - the Bestiary's settings")
	end
end

SLASH_LEFTHYTOOLS_BESTIARY1 = "/bestiary"
SlashCmdList.LEFTHYTOOLS_BESTIARY = function(msg)
	if M.enabled then
		M:OnSlashCommand(msg)
	else
		LT.Print(L["The Bestiary is switched off (LefthyTools settings)."])
	end
end

-- For tests.
function Bt.Pending()
	return pending
end
