local _, ns = ...
local LT = ns.LT
local L = ns.L

-- Bestiary: what the mobs you kill drop. A database of your own (LefthyToolsBestiaryDB: all your
-- characters add to it, nothing goes to friends) per kind of mob (creature ID, from its GUID): how
-- many you killed, which items dropped how often and how many, and the coin. A window shows your
-- target's (it stays open; a minimap button) and, if you like, a hovered enemy's on a card next to
-- the mouse; a ledger lists every mob.
--
-- LefthyToolsBestiaryDB = { mobs = { [creatureID] = { name, level, class, kills, money (copper),
--   first, last (time()), items = { [itemID] = { drops (corpses it came from), count, quality,
--   name } }, skinned (how many), skins = { [itemID] = { times, count, quality, name } },
--   pace = { your level, kills with their XP known, XP, kills timed, seconds },
--   spots = { where you were at each kill outside instances, the last SPOTS_KEEP: map ID * 1e6 +
--   x * 1e3 + y, x and y in thousandths of the map } } },
--   wishes = { [itemID] = { pinned (time()), kills since, expected drops in them, name, quality } },
--   log = { { time, creature, what, items, check, the corpse's GUID }, ... } (/bestiary log) }
--
-- This file: the module, what its files share, reading the records (chances, drops, worth, where),
-- items the client doesn't know yet, the mobs seen. The others, in the order they load: Classic.lua
-- (what a classic drop database says beside your numbers, and mobs' health for the fight stream),
-- Quests.lua (quest drops), Wishes.lua (the wish list), Recording.lua (your kills and their loot:
-- how they're counted), Format.lua (how numbers and lines are written), Cells.lua (drops as cells,
-- item tooltips), Window.lua (the window, the minimap button), Card.lua (the card beside the mouse),
-- LedgerMap.lua (the ledger's map of where you killed them) and Ledger.lua (every mob, the search).
-- Each registers the events it handles (Bt.On) and what it does when the Bestiary is switched on or
-- off or a setting changes (Bt.When).

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
-- game call's value (nil when it fails or is a secret; both Core's), an empty table to read from,
-- the gold of edges and headings.
local issecret, Value = LT.IsSecret, LT.Value
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

local SEEN_KEEP = 200           -- mobs remembered (name, level) from target, mouseover and nameplates
Bt.SKIN_ICON = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01" -- (Skinning's own icon)
Bt.STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" -- (on your wish list: the raid marker's star)

local data                       -- LefthyToolsBestiaryDB
local seen, seenOrder = {}, {}   -- GUID -> { name, level, class }
local seenNames = {}             -- creature ID -> its name, as last seen (this session)
local listeners = {}             -- Bt.OnChanged

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

-- Something changed for a kind of mob (the window and the card redraw).
function Bt.OnChanged(fn)
	listeners[#listeners + 1] = fn
end

local sources -- item ID -> where it comes from (Bt.Sources), built when asked after a change

-- A kind of mob's record changed (Recording.lua): the item sources again, the listeners told.
function Bt.Changed(creature)
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
-- that doesn't bind on pickup (unknown yet: taken as one), or when it dropped as loot from WORLD_KINDS
-- or more kinds of mobs. Skinning doesn't count: every beast gives leather (the user, on an item
-- skinned from three kinds counting as a world drop: "no that doesnt make sense does it"). They
-- gather in one place at the end of a mob's drops.
local WORLD_KINDS = 3

function Bt.IsWorldDrop(id, quality)
	local looted = 0
	for _, source in ipairs(Bt.Sources(id) or Bt.NONE) do
		if not source.skin then
			looted = looted + 1
		end
	end
	if looted >= WORLD_KINDS then
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
