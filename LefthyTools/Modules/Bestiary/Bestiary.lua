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
--     moment after it died): a corpse left lying would count as a kill that dropped nothing;
--   * your (or your pet's) killing blow (PARTY_KILL), or any corpse you loot: it was yours;
--   * on your own only: in a group the loot goes round, so you'd see only part of it;
--   * a corpse's loot once (the first time it opens); not when a spell of yours went off just before
--     (skinning, a pickpocket, opening), nor what isn't a creature's (herbs, ore, chests, fishing,
--     a bag's contents: their source isn't a creature);
--   * coin: what your money grew by while the loot window was open.
--
-- LefthyToolsBestiaryDB = { mobs = { [creatureID] = { name, level, class, kills, money (copper),
--   last (time()), items = { [itemID] = { drops (corpses it came from), count, quality } } } } }

local M = LT:NewModule("bestiary", {
	title = "Bestiary",
	description = L["What the mobs you kill drop: a window for your target with each drop, how many you got and the drop chance, from your own kills. Kept for all your characters, only on your computer."],
	defaults = {
		minimapButton = true,
		minimapAngle = 150,  -- degrees, 0 = right, counter-clockwise: the upper left
		showPoor = true,     -- grey items in the lists
		hoverCard = false,   -- the drops next to the mouse over an enemy
		window = {},         -- shown, point, x, y
	},
})

local Bt = { module = M }
ns.Bestiary = Bt

local EMPTY_CHECKS = { 2, 6 }  -- seconds after a kill: is its corpse empty? (both times: then it counts)
local PENDING_FOR = 300         -- a corpse not looted in this long: not counted
local CAST_GAP = 1              -- a spell of yours this shortly before the loot window: not a mob's loot
local SEEN_KEEP = 200           -- mobs remembered (name, level) from target, mouseover and nameplates
local NOT_A_CAST = { [75] = true, [5019] = true } -- Auto Shot, Shoot (a wand): they repeat while fighting
local issecret = issecretvalue or function() return false end

local data                       -- LefthyToolsBestiaryDB
local pending = {}               -- GUID -> { at, creature }: killed, its loot not seen yet
local done = {}                  -- GUID -> time: counted (or its loot seen); kept a while
local seen, seenOrder = {}, {}   -- GUID -> { name, level, class }
local castAt = -math.huge
local lootMoney, lootSource      -- while the loot window is open: money before, the corpse
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

local function Changed(creature)
	for _, fn in ipairs(listeners) do
		local ok, err = pcall(fn, creature)
		if not ok then
			geterrorhandler()(err)
		end
	end
end

-- A drop's chance, 0-1, and how many came per drop.
function Bt.Chance(mob, item)
	return mob.kills > 0 and math.min(1, item[1] / mob.kills) or 0, item[1] > 0 and item[2] / item[1] or 0
end

-- A kind's drops, the likeliest first (ties: better quality first): { { id, drops, count, quality,
-- chance, each }, ... }. Grey ones only with showPoor.
function Bt.Drops(mob, showPoor)
	local list = {}
	for id, item in pairs(mob and mob.items or {}) do
		local quality = item[3] or 1
		if showPoor or quality ~= 0 then
			local chance, each = Bt.Chance(mob, item)
			list[#list + 1] = { id = id, drops = item[1], count = item[2], quality = quality, chance = chance, each = each }
		end
	end
	table.sort(list, function(a, b)
		if a.chance ~= b.chance then
			return a.chance > b.chance
		elseif a.quality ~= b.quality then
			return a.quality > b.quality
		end
		return a.id < b.id
	end)
	return list
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

-- A kill counted (once per corpse).
local function Count(guid, creature)
	done[guid] = time()
	pending[guid] = nil
	local mob = MobFor(creature)
	mob.kills, mob.last = mob.kills + 1, time()
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
	local ok, hasLoot = pcall(CanLootUnit, guid)
	if not ok or issecret(hasLoot) or hasLoot then
		return -- (has loot, or can't tell: counted when it's looted)
	end
	if round < #EMPTY_CHECKS then
		C_Timer.After(EMPTY_CHECKS[round + 1] - EMPTY_CHECKS[round], function() CheckEmpty(guid, round + 1) end)
	else
		Count(guid, kill.creature)
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

-- The corpse a loot window is for: its GUID (GetLootSourceInfo; without it, the one kill waiting).
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
	if not source and not GetLootSourceInfo then
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

-- The loot window opened (LOOT_READY, before anything is taken): a corpse's loot, the first time.
local function OnLoot()
	lootMoney, lootSource = nil, nil
	if not data or not Solo() or (IsFishingLoot and IsFishingLoot()) or GetTime() - castAt < CAST_GAP then
		return
	end
	local guid = LootSource()
	local creature = Bt.CreatureOf(guid)
	if not creature or done[guid] then
		return
	end
	local mob = Count(guid, creature)
	local coin = false
	for slot = 1, GetNumLootItems() do
		local kind = Value(GetLootSlotType, slot)
		if kind == 2 then -- (Enum.LootSlotType.Money)
			coin = true
		elseif kind == 1 then -- (Item)
			local _, _, quantity, _, quality = GetLootSlotInfo(slot)
			local link = Value(GetLootSlotLink, slot)
			local id = type(link) == "string" and tonumber(link:match("|Hitem:(%d+)"))
			if id and not issecret(quantity) and not issecret(quality) then
				local item = mob.items[id] or { 0, 0, quality }
				mob.items[id] = item
				item[1], item[2], item[3] = item[1] + 1, item[2] + math.max(1, tonumber(quantity) or 1), tonumber(quality) or item[3]
			end
		end
	end
	if coin then
		lootMoney, lootSource = GetMoney(), creature
	end
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
	lootMoney, lootSource = nil, nil
end

-- Old waiting kills and counted corpses go.
local function Prune()
	local now, wall = GetTime(), time()
	for guid, kill in pairs(pending) do
		if now - kill.at > PENDING_FOR then
			pending[guid] = nil
		end
	end
	for guid, at in pairs(done) do
		if wall - at > PENDING_FOR then
			done[guid] = nil
		end
	end
end

events:SetScript("OnEvent", function(_, event, a, b, c)
	if event == "PARTY_KILL" then
		OnKill(a, b)
		Prune()
	elseif event == "LOOT_READY" then
		OnLoot()
	elseif event == "LOOT_CLOSED" then
		OnLootClosed()
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then -- unit, castGUID, spellID
		if issecret(c) or not NOT_A_CAST[c] then
			castAt = GetTime()
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
	for _, event in ipairs({ "PARTY_KILL", "LOOT_READY", "LOOT_CLOSED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
			"NAME_PLATE_UNIT_ADDED" }) do
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
	o:Header(L["Drops"])
	o:Checkbox("hoverCard", L["Drops next to the mouse"],
		L["Hovering an enemy you've killed before shows its likeliest drops beside the mouse."])
	o:Checkbox("showPoor", L["Grey items"], L["Show grey (junk) items among the drops."])
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
	else
		self:Print("/bestiary - open or close the window (your target's drops)")
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
