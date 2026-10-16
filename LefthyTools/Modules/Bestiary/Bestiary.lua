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
-- /bestiary log shows the last loot windows and kills and what was made of them.
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
local CAST_GAP = 1.5            -- skinning (a pickpocket, gathering) this shortly before the loot window: not a kill's loot
local SEEN_KEEP = 200           -- mobs remembered (name, level) from target, mouseover and nameplates
local LOG_KEEP = 12             -- loot windows remembered with what was made of them (/bestiary log)
-- Spells whose loot isn't a kill's (each rank's ID, and by name for ranks not listed): Skinning,
-- Pick Pocket, Mining, Herb Gathering. Any other spell just before looting (a killing blow, then a
-- quick loot) doesn't matter.
local NOT_A_KILL = { 8613, 8617, 8618, 10768, 921, 2575, 2576, 3564, 10248, 2366, 2368, 3570, 11993 }
local issecret = issecretvalue or function() return false end

local data                       -- LefthyToolsBestiaryDB
local pending = {}               -- GUID -> { at, creature }: killed, its loot not seen yet
local done = {}                  -- GUID -> time: counted (or its loot seen); kept a while
local seen, seenOrder = {}, {}   -- GUID -> { name, level, class }
local castAt = -math.huge        -- when one of the NOT_A_KILL spells went off
local notKillIDs, notKillNames   -- NOT_A_KILL as a set, and their names (read once)
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

-- Is this spell one whose loot isn't a kill's (skinning, a pickpocket, gathering)?
local function NotAKill(spellID)
	if not notKillIDs then
		notKillIDs, notKillNames = {}, {}
		for _, id in ipairs(NOT_A_KILL) do
			notKillIDs[id] = true
			local name = C_Spell and C_Spell.GetSpellName and Value(C_Spell.GetSpellName, id)
			if name then
				notKillNames[name] = true
			end
		end
	end
	if notKillIDs[spellID] then
		return true
	end
	local name = C_Spell and C_Spell.GetSpellName and Value(C_Spell.GetSpellName, spellID)
	return name ~= nil and notKillNames[name] == true
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
	if not Solo() then
		return Log(creature, "group", 0)
	elseif IsFishingLoot and IsFishingLoot() then
		return
	elseif GetTime() - castAt < CAST_GAP then
		return Log(creature, "skinning or pickpocket", 0)
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
			local _, _, quantity, _, quality = GetLootSlotInfo(slot)
			local link = Value(GetLootSlotLink, slot)
			local id = type(link) == "string" and tonumber(link:match("|Hitem:(%d+)"))
			if id and not issecret(quantity) and not issecret(quality) then
				local item = mob.items[id] or { 0, 0, quality }
				mob.items[id] = item
				item[1], item[2], item[3] = item[1] + 1, item[2] + math.max(1, tonumber(quantity) or 1), tonumber(quality) or item[3]
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
		if not issecret(c) and NotAKill(c) then
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
	elseif cmd == "log" then
		Bt.PrintLog()
	else
		self:Print("/bestiary - open or close the window (your target's drops)")
		self:Print("/bestiary log - the last loot windows and kills, and what was made of them")
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
