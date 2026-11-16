local _, ns = ...
local LT = ns.LT
local L = ns.L
local W = ns.WhyPoor or {}
ns.WhyPoor = W

-- Your bags: each item's best way to sell, for the window's Bags tab and the ideas (W.Bags). Nothing in item
-- tooltips and nothing on the bags themselves (no extra data there: everything is in the window).
-- docs/whypoor.md has the contract.
--
--   * W.Bags.List(): every item in the bags (0 to the reagent bag; not the bank), stacks of one item added
--     up (bound and unbound copies apart), with what a vendor pays for them all (P.Vendor), what the
--     auction house would bring after its cut and the deposits lost (P.AHSale; nothing for bound items),
--     the better of the two (P.Best; bound: the vendor) and a reason to keep it: a quest item (for a quest
--     in your log; one Lodestar says no quest needs any more has none), or soulbound gear you might wear
--     (you can use it and its item level isn't below what you wear there). The total: what the items
--     without a reason would fetch, each its better way. Worked out when asked, kept until the bags,
--     your gear, your quests or the prices (P.Revision) change.

local B = {}
W.Bags = B

-- Where gear goes: the inventory slots of an equip location (the weaker one counts where there are two).
local SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 }, INVTYPE_CHEST = { 5 },
	INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
	INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16, 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
	INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 }, INVTYPE_TABARD = { 19 },
}

B.rev = 0               -- goes up when the bags, gear or quests change
B.cache = nil           -- { key, list, total }

local function Num(v)
	return type(v) == "number" and not LT.IsSecret(v) and v or nil
end

local function P()
	return W.Prices
end

-- The last bag that's yours to carry (the reagent bag), as the client counts them.
function B.LastBag()
	return Num(NUM_TOTAL_EQUIPPED_BAG_SLOTS) or Num(NUM_BAG_SLOTS) or 4
end

---------------------------------------------------------------------------
-- Reasons to keep
---------------------------------------------------------------------------

local function ItemLevel(link)
	return link and C_Item.GetDetailedItemLevelInfo and Num(LT.Value(C_Item.GetDetailedItemLevelInfo, link)) or nil
end

-- Soulbound gear you might wear: you can use it, and its item level isn't below the weaker of what you
-- wear where it goes (unknown levels: kept, to be safe).
function B.MightWear(item, link, equipLoc)
	local slots = SLOTS[equipLoc]
	if not slots then
		return false
	end
	if C_PlayerInfo and C_PlayerInfo.CanUseItem and LT.Value(C_PlayerInfo.CanUseItem, item) == false then
		return false
	end
	local mine = ItemLevel(link)
	local worst
	for _, slot in ipairs(slots) do
		local worn = GetInventoryItemLink and LT.Value(GetInventoryItemLink, "player", slot)
		if type(worn) ~= "string" then
			return true -- (that slot is empty)
		end
		local level = ItemLevel(worn)
		if not level then
			return true
		end
		worst = worst and math.min(worst, level) or level
	end
	return not (mine and worst) or mine >= worst
end

-- A reason not to sell (localized) or nil.
function B.Keep(item, bag, slot, bound, link)
	local quest = C_Container.GetContainerItemQuestInfo and LT.Value(C_Container.GetContainerItemQuestInfo, bag, slot)
	local _, _, _, equipLoc, _, class = C_Item.GetItemInfoInstant(item)
	class, equipLoc = Num(class), type(equipLoc) == "string" and not LT.IsSecret(equipLoc) and equipLoc or nil
	local questID = type(quest) == "table" and Num(quest.questID)
	if questID and C_QuestLog and C_QuestLog.GetLogIndexForQuestID and Num(LT.Value(C_QuestLog.GetLogIndexForQuestID, questID)) then
		return L["for a quest in your log"]
	end
	if class == 12 or (type(quest) == "table" and quest.isQuestItem == true) then
		local Q = ns.Lodestar
		if Q and Q.ItemMarked then
			local ok, done = pcall(Q.ItemMarked, item)
			if ok and done == true then
				return nil -- (no quest needs it any more)
			end
		end
		return L["a quest item"]
	end
	if bound and (class == 2 or class == 4) and equipLoc and B.MightWear(item, link, equipLoc) then
		return L["soulbound: you might wear it"]
	end
	return nil
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------

local function ByValue(a, b)
	if (a.value or -1) ~= (b.value or -1) then
		return (a.value or -1) > (b.value or -1)
	end
	return a.item < b.item
end

-- One entry's numbers (P's), for count of them.
function B.Price(e)
	local prices = P()
	if not prices then
		return
	end
	local each = prices.Vendor and prices.Vendor(e.item)
	e.vendor = Num(each) and each * e.count or nil
	if not e.bound then
		e.ah, e.unit = nil, nil
		if prices.AHSale then
			e.ah, e.unit = prices.AHSale(e.item, e.count)
			e.ah, e.unit = Num(e.ah), Num(e.unit)
		end
		e.price = prices.Get and prices.Get(e.item) or nil
		if prices.Best then
			e.best, e.value, e.reason = prices.Best(e.item, e.count)
			e.value = Num(e.value)
		end
	end
	if e.bound or (e.best ~= "ah" and e.best ~= "vendor") then
		e.best, e.value = nil, nil
		if e.vendor and e.vendor > 0 then
			e.best, e.value = "vendor", e.vendor
		end
	end
end

function B.Scan()
	local byKey, list = {}, {}
	for bag = 0, B.LastBag() do
		local slots = Num(LT.Value(C_Container.GetContainerNumSlots, bag)) or 0
		for slot = 1, slots do
			local info = LT.Value(C_Container.GetContainerItemInfo, bag, slot)
			local item = type(info) == "table" and Num(info.itemID)
			if item then
				local bound = info.isBound == true
				local key = bound and (item .. ":b") or item
				local e = byKey[key]
				if not e then
					local link = LT.Readable(info.hyperlink) and info.hyperlink or nil
					e = { item = item, count = 0, bound = bound, link = link, bag = bag, slot = slot,
						quality = Num(info.quality) or Num(LT.Value(C_Item.GetItemQualityByID, item)) }
					e.keep = B.Keep(item, bag, slot, bound, link)
					byKey[key] = e
					list[#list + 1] = e
				end
				e.count = e.count + (Num(info.stackCount) or 1)
			end
		end
	end
	local total = 0
	for _, e in ipairs(list) do
		B.Price(e)
		if e.value and not e.keep then
			total = total + e.value
		end
	end
	table.sort(list, ByValue)
	return list, total
end

local function Key()
	local prices = P()
	return B.rev .. ":" .. tostring(prices and prices.Revision and prices.Revision() or 0)
end

function B.Cached()
	local key = Key()
	if not (B.cache and B.cache.key == key) then
		local list, total = B.Scan()
		B.cache = { key = key, list = list, total = total }
	end
	return B.cache
end

-- The contract: { { item, count, best, value, vendor, ah, keep, ... } }, total. (Also bound, unit: the AH
-- price for one it assumes, price: P.Get's, quality, link.)
function B.List()
	local c = B.Cached()
	return c.list, c.total
end

function B.Total()
	return B.Cached().total
end

---------------------------------------------------------------------------
-- What changes it (events only note)
---------------------------------------------------------------------------

B.events = CreateFrame("Frame")
for _, event in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED",
		"QUEST_TURNED_IN", "GET_ITEM_INFO_RECEIVED" }) do
	B.events:RegisterEvent(event)
end
B.events:SetScript("OnEvent", function()
	B.rev = B.rev + 1
	if W.Goal and W.Goal.Forget then
		W.Goal.Forget()
	end
end)
