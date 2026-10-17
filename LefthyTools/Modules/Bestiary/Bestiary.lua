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
--   * your (or your pet's) killing blow (PARTY_KILL), or any corpse you loot: it was yours; not a
--     mob someone else tagged first (its corpse isn't yours);
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
--   name } }, skinned (how many), skins = { [itemID] = { times, count, quality, name } },
--   pace = { your level, kills with their XP known, XP, kills timed, seconds },
--   spots = { where you were at each kill outside instances, the last SPOTS_KEEP: map ID * 1e6 +
--   x * 1e3 + y, x and y in thousandths of the map } } },
--   wishes = { [itemID] = { pinned (time()), kills since, expected drops in them, name, quality } } }
--
-- The pace: what a counted kill of yours gave in XP (PLAYER_XP_UPDATE in the moment around its
-- PARTY_KILL) and how long it took (since the fight began, or since your last kill in it: several
-- mobs in one fight share its length). XP per kill depends on your level, so it's kept for one level
-- (the level you were at the kill): a kill at another level starts it again. A kill's worth (its
-- coin and what its drops sell for at a vendor, Bt.Worth) is worked out when shown, not kept.
--
-- The Bestiary's other files, in the order they load: Classic.lua (what a classic drop database says
-- beside your numbers, and mobs' health for the fight stream), Quests.lua (quest drops), Wishes.lua
-- (the wish list), Window.lua (the window, the card beside the mouse, item tooltips, the minimap
-- button) and Ledger.lua (every mob, the search). Each registers the events it handles (Bt.On) and
-- what it does when the Bestiary is switched on or off or a setting changes (Bt.When).

local M = LT:NewModule("bestiary", {
	title = "Bestiary",
	description = L["What the mobs you kill drop: a window for your target with each drop, how many you got and the drop chance, from your own kills. Kept for all your characters, only on your computer."],
	defaults = {
		minimapButton = true,
		minimapAngle = 150,  -- degrees, 0 = right, counter-clockwise: the upper left
		showPoor = true,     -- grey items in the lists
		hoverCard = false,   -- the drops next to the mouse over an enemy
		cardHideInCombat = true, -- but not while you're in combat
		itemTooltip = true,  -- an item's tooltip: the mobs it comes from likeliest, with the chance
		dropData = true,     -- compare with the classic drop database (LefthyTools_DropData)
		windowUnseen = false, -- the window: what the database says it drops that you haven't had yet
		cardUnseen = false,  -- the card beside the mouse over a mob you haven't killed: what it can drop
		window = {},         -- shown, left, top (Window.lua: whether it's open, where)
	},
})

local Bt = { module = M }
ns.Bestiary = Bt

-- Shared by the Bestiary's files: whether a value is a secret (Forever hides many API returns), a
-- game call's value (nil when it fails or is a secret), an empty table to read from, the gold of
-- edges and headings.
local issecret = issecretvalue or function() return false end

local function Value(f, ...)
	if not f then
		return nil
	end
	local ok, v = pcall(f, ...)
	if ok and not issecret(v) then
		return v
	end
end

local NONE = {}
Bt.issecret, Bt.Value, Bt.NONE, Bt.GOLD = issecret, Value, NONE, { 1, 0.82, 0.3 }

-- The events each file of the Bestiary handles (Bt.On: handlers run in the order the files load),
-- registered while it's switched on; and what each file does when it's switched on or off or a
-- setting changes (Bt.When "enable", "disable", "settings"; after its events are registered, after
-- they're unregistered).
local events = CreateFrame("Frame")
local handlers, units = {}, {} -- event -> { handler, ... }; event -> the unit it's registered for
local hooks = { enable = {}, disable = {}, settings = {} }

function Bt.On(event, handler, unit)
	handlers[event] = handlers[event] or {}
	table.insert(handlers[event], handler)
	units[event] = unit or units[event]
end

function Bt.When(what, fn)
	table.insert(hooks[what], fn)
end

local function Run(what)
	for _, fn in ipairs(hooks[what]) do
		fn()
	end
end

events:SetScript("OnEvent", function(_, event, ...)
	for _, handler in ipairs(handlers[event] or NONE) do
		handler(...)
	end
end)

local EMPTY_CHECKS = { 2, 6 }  -- seconds after a kill: is its corpse empty? (both times: then it counts)
local PENDING_FOR = 300         -- a corpse not looted in this long: not counted
local CAST_GAP = 1.5            -- skinning (a pickpocket, gathering) this shortly before the loot window: not a kill's loot
local SEEN_KEEP = 200           -- mobs remembered (name, level) from target, mouseover and nameplates
local LOG_KEEP = 12             -- loot windows remembered with what was made of them (/bestiary log)
local XP_FROM_KILL = 1.5        -- seconds: XP this close to a kill of yours came from it
local FIGHT_AFTER = 2           -- seconds a kill may come after the fight ended and still be timed
local RECENT_KEEP = 8           -- your last kills, for the XP that comes a moment after them
local SPOTS_KEEP = 50           -- where you killed each kind: the last this many kills
Bt.SPOTS_KEEP = SPOTS_KEEP
local TAP_UNITS = { "target", "mouseover" } -- whose tap a killing blow can be checked on
-- Spells whose loot isn't a kill's (each rank's ID, and by name for ranks not listed): Skinning,
-- Pick Pocket, Mining, Herb Gathering. Any other spell just before looting (a killing blow, then a
-- quick loot) doesn't matter.
local NOT_A_KILL = { 8613, 8617, 8618, 10768, 921, 2575, 2576, 3564, 10248, 2366, 2368, 3570, 11993 }
local SKINNING = { [8613] = true, [8617] = true, [8618] = true, [10768] = true }
Bt.SKINNING = SKINNING -- (Classic.lua: can you skin?)
Bt.SKIN_ICON = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01" -- (Skinning's own icon)
Bt.STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" -- (on your wish list: the raid marker's star)

local data                       -- LefthyToolsBestiaryDB
local pending = {}               -- GUID -> { at, creature }: killed, its loot not seen yet
local done = {}                  -- GUID -> time: counted (or its loot seen); kept a while
local seen, seenOrder = {}, {}   -- GUID -> { name, level, class }
local seenNames = {}             -- creature ID -> its name, as last seen (this session)
local castAt = -math.huge        -- when one of the NOT_A_KILL spells went off
local castSkin = false           -- and it was Skinning
local notKillIDs, notKillNames   -- NOT_A_KILL as a set, and their names (read once); Skinning's name
local skinName
local skinnedCorpse = {}         -- GUID -> time: skinned (once each)
local lootMoney, lootSource      -- while the loot window is open: money before, the corpse
local lootSeen = false           -- this loot window was looked at (LOOT_READY or LOOT_OPENED)
local recent = {}                -- your last kills (their pending entries), the oldest first
local xpWas = {}                 -- your XP as last read (xp, max): what each update added
local looseXP                    -- XP that came just before its kill: { amount, at }
local fightFrom, fightEnd        -- when the fight began (PLAYER_REGEN_DISABLED) and ended (nil: still on)
local lastKillAt = -math.huge    -- your last kill in this fight: the next one's time starts there
local listeners = {}

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

-- LefthyToolsBestiaryDB (nil before the saved variables are loaded).
function Bt.Data()
	return data
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

-- A kind's pace (nil: nothing known): XP per kill, seconds per kill, XP per hour of fighting (the
-- time between fights not counted), each nil when not known, and the level they're for.
function Bt.Pace(mob)
	local pace = mob and type(mob.pace) == "table" and mob.pace
	if not pace then
		return nil
	end
	local xp = (pace[2] or 0) > 0 and pace[3] / pace[2] or nil
	local seconds = (pace[4] or 0) > 0 and pace[5] / pace[4] or nil
	return xp, seconds, xp and seconds and seconds > 0 and xp / seconds * 3600 or nil, pace[1]
end

-- Items the client doesn't know yet (for a price, a quest item's name, the ledger's search): each is
-- asked for once a session (RequestLoadItemDataByID), and GET_ITEM_INFO_RECEIVED is listened to only
-- while one is awaited. They come in bunches: half a second after the first, everything shown
-- redraws once (Bt.Redraw: the window, the card, the ledger); one coming later redraws again.
local ITEM_GAP = 0.5
local asked = {}        -- item ID -> true: asked for this session
local awaited = {}      -- item ID -> true: asked for, not here yet
local itemsSoon = false -- a redraw is on its way
local itemEvents = CreateFrame("Frame")

function Bt.AskItem(id)
	if asked[id] or type(id) ~= "number" or not (C_Item and C_Item.RequestLoadItemDataByID) then
		return
	end
	asked[id], awaited[id] = true, true
	pcall(C_Item.RequestLoadItemDataByID, id)
	itemEvents:RegisterEvent("GET_ITEM_INFO_RECEIVED")
end

itemEvents:SetScript("OnEvent", function(_, _, id)
	if issecret(id) or not awaited[id] then
		return
	end
	awaited[id] = nil
	if not next(awaited) then -- (all came: not listened to any more)
		itemEvents:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
	end
	if not itemsSoon then
		itemsSoon = true
		C_Timer.After(ITEM_GAP, function()
			itemsSoon = false
			if Bt.Redraw then
				Bt.Redraw()
			end
		end)
	end
end)

-- Switched off: nothing awaited (what didn't come is asked for again when needed).
Bt.When("disable", function()
	for id in pairs(awaited) do
		asked[id] = nil
	end
	wipe(awaited)
	itemEvents:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
end)

-- An item's name: as you looted it (item: its entry in a record), else the client's (asked for when
-- it doesn't know it yet: it redraws when it comes). For quest objectives and the wish list.
local itemNames = {}    -- item ID -> its name (the client's)

function Bt.ItemNameOf(id, item)
	local name = item and item[4] or itemNames[id]
	if name then
		return name
	end
	name = C_Item and Value(C_Item.GetItemInfo, ("item:%d"):format(id))
	if type(name) == "string" then
		itemNames[id] = name
		return name
	end
	Bt.AskItem(id)
end

-- Vendor prices (C_Item.GetItemInfo's sellPrice), read once each; one the client doesn't know yet
-- counts as nothing until it comes (asked for: Bt.AskItem).
local prices = {}       -- item ID -> what it sells for, in copper

local function Price(id)
	if prices[id] then
		return prices[id]
	end
	local ok, name, _, _, _, _, _, _, _, _, _, sell = pcall(C_Item and C_Item.GetItemInfo, ("item:%d"):format(id))
	if ok and not issecret(name) and type(name) == "string" then
		prices[id] = not issecret(sell) and type(sell) == "number" and sell or 0
		return prices[id]
	end
	Bt.AskItem(id)
end

-- What a kill of a kind brings on average, in copper: its coin and what its drops sell for at a
-- vendor (how many per kill times the sell price; grey ones and world drops too, it's all money;
-- not skinning, not everyone skins). Returns the worth, the coin's part and the drops' part per
-- kill; nil without kills. A price the client doesn't know yet counts as nothing until it comes.
function Bt.Worth(mob)
	if not mob or (mob.kills or 0) <= 0 then
		return nil
	end
	local vendor = 0
	for id, item in pairs(mob.items or NONE) do
		vendor = vendor + (item[2] or 0) * (Price(id) or 0)
	end
	local money = mob.money or 0
	return (money + vendor) / mob.kills, money / mob.kills, vendor / mob.kills
end

-- Where you killed a kind (its last SPOTS_KEEP kills), per map, the most kills first: { { map = map
-- ID, xy = { x, y, x, y, ... } (0-1, the oldest first) }, ... }; nil: nowhere known.
function Bt.Spots(mob)
	local spots = mob and type(mob.spots) == "table" and mob.spots
	if not spots or #spots == 0 then
		return nil
	end
	local byMap, list = {}, {}
	for _, spot in ipairs(spots) do
		if type(spot) == "number" then
			local map = math.floor(spot / 1e6)
			local rest = spot - map * 1e6
			local entry = byMap[map]
			if not entry then
				entry = { map = map, xy = {} }
				byMap[map], list[#list + 1] = entry, entry
			end
			entry.xy[#entry.xy + 1] = (math.floor(rest / 1e3) + 0.5) / 1e3
			entry.xy[#entry.xy + 1] = (rest % 1e3 + 0.5) / 1e3
		end
	end
	table.sort(list, function(a, b)
		if #a.xy ~= #b.xy then
			return #a.xy > #b.xy
		end
		return a.map < b.map
	end)
	return list[1] and list or nil
end

-- The order drops are listed in: the likeliest first, the better quality first when even.
local function Likelier(a, b)
	if a.chance ~= b.chance then
		return a.chance > b.chance
	elseif a.quality ~= b.quality then
		return a.quality > b.quality
	end
	return a.id < b.id
end
Bt.Likelier = Likelier

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
-- Mobs seen: name, level, kind (for records and the window)
---------------------------------------------------------------------------

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
	seenNames[creature] = info.name or seenNames[creature]
	local mob = data and data.mobs[creature]
	if mob then -- (its name and level as last seen)
		mob.name, mob.level, mob.class = info.name or mob.name, info.level or mob.level, info.class or mob.class
	end
	return guid, creature
end

function Bt.Seen(guid)
	return seen[guid]
end

-- A kind of mob's name: from its record, else as seen this session (the classic database has none).
function Bt.NameOf(creature)
	local mob = data and data.mobs[creature]
	return mob and mob.name or seenNames[creature]
end

Bt.On("PLAYER_TARGET_CHANGED", function() Bt.Look("target") end)
Bt.On("UPDATE_MOUSEOVER_UNIT", function() Bt.Look("mouseover") end)
Bt.On("NAME_PLATE_UNIT_ADDED", function(unit) Bt.Look(unit) end)

---------------------------------------------------------------------------
-- Kills and loot
---------------------------------------------------------------------------

local function Solo()
	return not (IsInGroup and IsInGroup())
end

-- What was made of a loot window or a kill, the last LOG_KEEP (/bestiary log; kept for a look
-- after a /reload): { time, mob (creature ID), what, items (how many), check (CanLootUnit's
-- answers), the corpse's GUID (when it was counted: Counted) }.
local function Log(creature, what, items, check, guid)
	if not data then
		return
	end
	data.log = type(data.log) == "table" and data.log or {}
	table.insert(data.log, 1, { time(), creature, what, items, check, guid })
	for i = #data.log, LOG_KEEP + 1, -1 do
		data.log[i] = nil
	end
end

-- A corpse counted already (done: { at, how }), also before a /reload: that forgets the session's
-- corpses, but the log is saved, and a corpse looted, a /reload and looted again would count twice
-- (said empty, then looted after the /reload: a second kill instead of its items joining the first).
local COUNTED = { empty = "empty", looted = "looted", ["looted (said empty before)"] = "looted", ["looted before"] = "looted" }

local function Counted(guid)
	if done[guid] or not (data and type(data.log) == "table") then
		return done[guid]
	end
	local now = time()
	for _, entry in ipairs(data.log) do -- (the newest first)
		if entry[6] == guid and COUNTED[entry[3]] and now - (tonumber(entry[1]) or 0) <= PENDING_FOR then
			done[guid] = { at = entry[1], how = COUNTED[entry[3]] }
			return done[guid]
		end
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

-- What your XP grew by since it was last read (a level-up in between: the rest of the old level
-- and what's in the new one); nil when it can't be told. A level-up shows as the XP going down, not
-- as UnitLevel changing: the client may tell the new XP an update before the new level, and taking
-- the level then would count a whole level as one kill's XP.
local function ReadXP()
	local xp, max = Value(UnitXP, "player"), Value(UnitXPMax, "player")
	if type(xp) ~= "number" or type(max) ~= "number" then
		return nil
	end
	local gained = xpWas.xp and (xp >= xpWas.xp and xp - xpWas.xp or (xpWas.max - xpWas.xp) + xp)
	xpWas.xp, xpWas.max = xp, max
	return gained
end

-- Kills give you XP (the XP bar's own rule: not at the level cap, not switched off): a kill without
-- any then gave 0 (a grey mob), else it says nothing about XP.
local function XPGrows()
	return not (Value(IsPlayerAtEffectiveMaxLevel) or Value(IsXPUserDisabled))
end

-- A counted kill's XP and how long it took, for the level you were at when it died (another level
-- starts the pace again: XP per kill depends on it). XP still to come joins it then (kill.pace).
local function AddPace(mob, kill)
	if not (kill and kill.level) then
		return -- (a corpse looted without your killing blow seen: nothing known)
	end
	local pace = mob.pace
	if type(pace) ~= "table" or pace[1] ~= kill.level then
		pace = { kill.level, 0, 0, 0, 0 }
		mob.pace = pace
	end
	if kill.xp or XPGrows() then
		pace[2], pace[3] = pace[2] + 1, pace[3] + (kill.xp or 0)
		kill.pace = not kill.xp and pace or nil
	end
	if kill.seconds then
		pace[4], pace[5] = pace[4] + 1, pace[5] + math.floor(kill.seconds * 10 + 0.5) / 10
	end
end

-- Your XP grew: a kill's from the moment before (the oldest still without, when several died at
-- once), else it waits a moment for its kill (the XP can come first).
local function OnXP()
	local gained = ReadXP()
	if not gained or gained <= 0 then
		return
	end
	local now = GetTime()
	for _, kill in ipairs(recent) do
		if not kill.xp and now - kill.at <= XP_FROM_KILL then
			kill.xp = gained
			if kill.pace then -- (counted already, as 0: it's added now)
				kill.pace[3], kill.pace = kill.pace[3] + gained, nil
				Changed(kill.creature)
			end
			return
		end
	end
	looseXP = { amount = gained, at = now }
end

-- Where you are, packed in one number (map ID * 1e6 + x * 1e3 + y, x and y in thousandths of the
-- map: a yard or two); nil in an instance or when the game doesn't say.
local function Spot()
	if Value(IsInInstance) or not C_Map then
		return nil
	end
	local map = Value(C_Map.GetBestMapForUnit, "player")
	local pos = type(map) == "number" and Value(C_Map.GetPlayerMapPosition, map, "player")
	if type(pos) ~= "table" or type(pos.GetXY) ~= "function" then
		return nil
	end
	local ok, x, y = pcall(pos.GetXY, pos)
	if not ok or issecret(x) or issecret(y) or type(x) ~= "number" or type(y) ~= "number"
		or x < 0 or x > 1 or y < 0 or y > 1 or (x == 0 and y == 0) then
		return nil
	end
	return map * 1e6 + math.min(999, math.floor(x * 1e3)) * 1e3 + math.min(999, math.floor(y * 1e3))
end

-- A kill's spot joins its kind's, the last SPOTS_KEEP.
local function AddSpot(mob, spot)
	if not spot then
		return
	end
	mob.spots = type(mob.spots) == "table" and mob.spots or {}
	mob.spots[#mob.spots + 1] = spot
	while #mob.spots > SPOTS_KEEP do
		table.remove(mob.spots, 1)
	end
end

-- A kill counted (once per corpse). how: "looted" or "empty" (the game said there's nothing on it:
-- if it's looted after all, its items still join this kill).
local function Count(guid, creature, how)
	local kill = pending[guid]
	done[guid] = { at = time(), how = how }
	pending[guid] = nil
	local mob = MobFor(creature)
	mob.kills, mob.last = mob.kills + 1, time()
	mob.first = mob.first or mob.last
	local info = seen[guid]
	if info then
		mob.name, mob.level, mob.class = info.name or mob.name, info.level or mob.level, info.class or mob.class
	end
	AddPace(mob, kill)
	-- Where: you at its killing blow; a corpse looted without one seen, you at it now.
	if kill then
		AddSpot(mob, kill.spot)
	else
		AddSpot(mob, Spot())
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
		Bt.WishKill(kill.creature, Count(guid, kill.creature, "empty"))
		Log(kill.creature, "empty", 0, kill.check, guid)
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
	-- Someone else's mob (they hit it first, you finished it): its corpse isn't yours, and the game
	-- would say it's empty, a kill without drops. Told by your target or the mouseover.
	for _, unit in ipairs(TAP_UNITS) do
		if Value(UnitGUID, unit) == target and Value(UnitIsTapDenied, unit) == true then
			return Log(creature, "tapped by someone else", 0)
		end
	end
	if Value(UnitGUID, "target") == target then
		Bt.Look("target")
	end
	local now = GetTime()
	local kill = { at = now, creature = creature, level = Value(UnitLevel, "player"), spot = Spot() }
	-- How long it took: since the fight began, or since your last kill in it; not when the fight's
	-- start wasn't seen (switched on in it, a /reload).
	if fightFrom and (not fightEnd or now - fightEnd <= FIGHT_AFTER) then
		kill.seconds = now - math.max(fightFrom, lastKillAt)
	end
	lastKillAt = now
	if looseXP and now - looseXP.at <= XP_FROM_KILL then -- (its XP came first)
		kill.xp, looseXP = looseXP.amount, nil
	end
	pending[target] = kill
	recent[#recent + 1] = kill
	if #recent > RECENT_KEEP then
		table.remove(recent, 1)
	end
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
	local was, check = Counted(guid), pending[guid] and pending[guid].check
	if was and was.how ~= "empty" then
		return Log(creature, "looted before", 0, nil, guid)
	end
	local mob
	if was then -- (the game said it was empty: its items join that kill)
		mob = MobFor(creature)
		was.how = "looted"
	else
		mob = Count(guid, creature, "looted")
	end
	local coin, items, got = false, 0, {}
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
				items, got[id] = items + 1, link
			end
		end
	end
	if coin then
		lootMoney, lootSource = GetMoney(), creature
	end
	local fulfilled = Bt.WishKill(creature, mob, got, was ~= nil)
	Log(creature, was and "looted (said empty before)" or "looted", items, check, guid)
	Changed(creature)
	if fulfilled and Bt.Redraw then
		Bt.Redraw() -- (its star goes everywhere)
	end
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

Bt.On("PARTY_KILL", function(attacker, target)
	OnKill(attacker, target)
	Prune()
end)
Bt.On("LOOT_READY", OnLoot)
Bt.On("LOOT_OPENED", OnLoot)
Bt.On("LOOT_CLOSED", OnLootClosed)
Bt.On("UNIT_SPELLCAST_SUCCEEDED", function(_, _, spellID)
	local notKill, skin = false, false
	if not issecret(spellID) then
		notKill, skin = NotAKill(spellID)
	end
	if notKill then
		castAt, castSkin = GetTime(), skin
	end
end, "player")
Bt.On("PLAYER_XP_UPDATE", OnXP)
Bt.On("PLAYER_REGEN_DISABLED", function() -- (a fight began: the next kill's time starts here)
	fightFrom, fightEnd, lastKillAt = GetTime(), nil, -math.huge
end)
Bt.On("PLAYER_REGEN_ENABLED", function()
	fightEnd = GetTime()
end)

Bt.When("enable", function()
	xpWas.xp = nil
	ReadXP() -- (where counting XP starts)
end)

Bt.When("disable", function()
	wipe(pending)
	wipe(recent)
	-- (switched off with the loot window open: its LOOT_CLOSED won't come, and the next window would
	-- look already seen)
	lootMoney, lootSource, lootSeen, looseXP, fightFrom = nil, nil, false, nil, nil
end)

---------------------------------------------------------------------------
-- The module
---------------------------------------------------------------------------

LT.onLoad[#LT.onLoad + 1] = function()
	LefthyToolsBestiaryDB = type(LefthyToolsBestiaryDB) == "table" and LefthyToolsBestiaryDB or {}
	data = LefthyToolsBestiaryDB
	data.mobs = type(data.mobs) == "table" and data.mobs or {}
	data.wishes = type(data.wishes) == "table" and next(data.wishes) and data.wishes or nil -- (only once there's one)
end

function M:OnEnable()
	for event in pairs(handlers) do
		if units[event] then
			events:RegisterUnitEvent(event, units[event])
		else
			events:RegisterEvent(event)
		end
	end
	Run("enable")
end

function M:OnDisable()
	events:UnregisterAllEvents()
	Run("disable")
end

function M:OnSettingChanged()
	Run("settings")
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
	o:Checkbox("cardHideInCombat", L["Hidden in combat"],
		L["The drops next to the mouse don't show while you're in combat, and go when a fight starts."])
	o:Checkbox("itemTooltip", L["Drop chances in item tooltips"],
		L["An item's tooltip (in your bags, in chat, anywhere) lists the three mobs it comes from likeliest, with the chance; a pelt marks skinning."])
	o:Checkbox("showPoor", L["Grey items"], L["Show grey (junk) items among the drops."])
	o:Checkbox("dropData", L["Compare with a drop database"],
		L["Beside your own numbers, what a classic world database (CMaNGOS) says each mob can drop: its chance on each of your drops, and what you haven't had yet, faded. Beacon's fight stream takes mobs' health from it too. WoW: Forever may differ. It's an add-on of its own, LefthyTools Drop Data, installed with LefthyTools; /bestiary data says whether it's there."])
	o:Checkbox("windowUnseen", L["Not seen yet in the window"],
		L["Under your target's drops in the window, what the drop database says it drops that you haven't had yet, faded (a mob you haven't killed: what it can drop). The ledger always shows it."])
	o:Checkbox("cardUnseen", L["Mobs not killed yet beside the mouse"],
		L["Over an enemy you haven't killed yet, the drops next to the mouse show what the drop database says it can drop, faded. Off: only enemies you've killed get them."])
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
	elseif cmd == "wishes" then
		Bt.PrintWishes()
	elseif cmd == "wish" or cmd:match("^wish ") then
		local what = strtrim(msg or ""):match("^%S+%s+(.+)$") or ""
		local id = tonumber(what:match("item:(%d+)") or what:match("^(%d+)$"))
		if id and C_Item and C_Item.GetItemInfoInstant and not Value(C_Item.GetItemInfoInstant, id) then
			self:Print(("there's no item %d."):format(id))
		elseif id then
			Bt.ToggleWish(id)
		else
			self:Print("/bestiary wish <item link or ID> - pin an item to your wish list, or take it off")
		end
	else
		self:Print("/bestiary - open or close the window (your target's drops)")
		self:Print("/bestiary ledger [search] - every mob you've killed, its drops; search mobs and items")
		self:Print("/bestiary wish <item link or ID> - pin an item to your wish list (Alt-click a drop does it too), or take it off")
		self:Print("/bestiary wishes - your wish list")
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

-- For tests: the kills waiting to be counted, and what a /reload forgets.
function Bt.Pending()
	return pending
end

function Bt.Forget()
	wipe(pending)
	wipe(done)
	wipe(skinnedCorpse)
	wipe(recent)
end
