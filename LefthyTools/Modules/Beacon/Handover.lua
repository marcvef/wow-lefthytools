local _, ns = ...
local LT = ns.LT
local L = ns.L
local M = LT:GetModule("beacon")
local B = ns.Beacon

-- Hand-over reminder: an item I offered (Need / Pass, Items.lua) and someone won is reserved for
-- them until I trade or mail it to them. Kept in LefthyToolsDB.handover (the winner may be offline
-- for a while), at most MAX entries, each for KEEP_DAYS at most. While reserved:
--   * its tooltip says "Won by Anna: still to hand over" (a TooltipDataProcessor post-call; it runs
--     before the tooltip is sized and returns right away while nothing is reserved);
--   * its bag slot has an orange border (a post-hook on each bag frame's UpdateItems);
--   * at a vendor, right-clicking it asks first (an invisible button over the slot catches the
--     right-click; left-clicks and hovering pass through to the slot), and if it leaves the bags
--     another way (dragged onto the vendor, a bag addon) a warning says how to buy it back;
--   * opening a trade with the winner says so in chat, and attaching it to a mail fills in the
--     winner as recipient when the field is empty (a warning if another name is in it).
--
-- Handing over:
--   * trade: TRADE_SHOW gives the partner, TRADE_PLAYER_ITEM_CHANGED / TRADE_ACCEPT_UPDATE the items
--     I put in (slots 1-6; the 7th is "will not be traded"), UI_INFO_MESSAGE with ERR_TRADE_COMPLETE
--     means done (it may come after TRADE_CLOSED, so the snapshot lives until the next trade);
--   * mail: a post-hook on SendMail gives the recipient and the attachments, MAIL_SEND_SUCCESS means
--     done, MAIL_FAILED drops it.
-- An item given to someone else stays reserved. The partner is matched by GUID when both are
-- known, else by name; if the game won't tell who it is (a secret value), the item counts as
-- handed over. Event handlers only note things down; anything shown waits for the next frame.

local MAX, KEEP_DAYS = 20, 7
local TRADE_SLOTS = 6
local LINE_R, LINE_G, LINE_B = 1, 0.55, 0.2
local BORDER = "Interface\\Buttons\\UI-ActionButton-Border"

local list -- LefthyToolsDB.handover: { { itemID, link, winner, mailName, guid, at }, ... }, oldest first
local trade = { items = {} } -- the open (or last) trade: name, guid, items = { itemID, ... }
local mail -- a mail on its way: { name, items }
local merchantOpen = false
local counts = {} -- at a vendor: itemID -> how many are in my bags (to notice one going)
local mailWarned -- the recipient + attachments last warned about

local function Readable(value)
	return value ~= nil and not (issecretvalue and issecretvalue(value))
end

-- "Anna" from "Anna" or "Anna-Realm".
local function BaseName(name)
	return Readable(name) and type(name) == "string" and name:match("^[^%-]+") or nil
end

local function EntryFor(itemID)
	for _, entry in ipairs(list or {}) do
		if entry.itemID == itemID then
			return entry
		end
	end
end

local function Remove(entry)
	for i, e in ipairs(list or {}) do
		if e == entry then
			table.remove(list, i)
			return
		end
	end
end

-- Work for the next frame, collected: Soon("bags") etc.
local pending, scheduled, Run = {}, false, nil
local function Soon(what, value)
	pending[what] = value or true
	if not scheduled then
		scheduled = true
		C_Timer.After(0, Run)
	end
end

-- From Items.lua: my offer has a winner. gameAccountID: theirs, for their realm (mail needs it
-- when it isn't mine).
function B.AddHandover(itemString, link, winner, guid, gameAccountID)
	local itemID = tonumber(itemString and itemString:match("^(%d+)"))
	if not (list and itemID and winner) then
		return
	end
	local mailName = winner
	local info = gameAccountID and C_BattleNet.GetGameAccountInfoByID(gameAccountID)
	local realm = info and Readable(info.realmName) and info.realmName
	if realm and realm ~= "" and realm ~= GetRealmName() then
		mailName = winner .. "-" .. realm:gsub("[%s%-]", "")
	end
	-- Rolled again: only the newest winner keeps it reserved.
	for i = #list, 1, -1 do
		if list[i].itemID == itemID then
			local old = table.remove(list, i)
			if old.winner ~= winner then
				M:Print(("%s is no longer reserved for %s."):format(link or ("item " .. itemID), old.winner))
			end
		end
	end
	list[#list + 1] = { itemID = itemID, link = link, winner = winner, mailName = mailName, guid = guid, at = time() }
	while #list > MAX do
		table.remove(list, 1)
	end
	Soon("bags")
end

-- The reminder for itemID given to name / guid (nil: unknown, any winner), or nil.
local function HandedOver(itemID, name, guid)
	for _, entry in ipairs(list or {}) do
		if entry.itemID == itemID then
			local match
			if guid and entry.guid then
				match = guid == entry.guid
			elseif name then
				match = BaseName(entry.winner) == name
			else
				match = true
			end
			if match then
				Remove(entry)
				return entry
			end
		end
	end
end

local function Delivered(items, name, guid)
	for _, itemID in ipairs(items) do
		local entry = HandedOver(itemID, name, guid)
		if entry then
			C_Timer.After(0, function()
				M:Print(("%s handed over to %s."):format(entry.link or ("item " .. itemID), entry.winner))
			end)
			Soon("bags")
		end
	end
end

---------------------------------------------------------------------------
-- The tooltip line
---------------------------------------------------------------------------

local function OnItemTooltip(tooltip, data)
	if not (list and list[1] and M.enabled and data) or not Readable(data.id) then
		return
	end
	for _, entry in ipairs(list) do
		if entry.itemID == data.id then
			tooltip:AddLine(L["Won by %s: still to hand over"]:format(entry.winner), LINE_R, LINE_G, LINE_B)
		end
	end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
end

---------------------------------------------------------------------------
-- At a vendor: "Sell it anyway?"
---------------------------------------------------------------------------

local dialog

local function SellAnyway()
	dialog:Hide()
	local bag, slot, itemID, entry = dialog.bag, dialog.slot, dialog.itemID, dialog.entry
	if not (merchantOpen and C_Container.GetContainerItemID(bag, slot) == itemID) then
		return -- the vendor closed or the item moved meanwhile
	end
	Remove(entry) -- not reserved any more: no warning when it leaves the bags
	counts[itemID] = nil
	C_Container.UseContainerItem(bag, slot)
	M:Print(("sold %s, which %s had won; it's no longer reserved."):format(entry.link or ("item " .. itemID), entry.winner))
	Soon("bags")
end

local function Dialog()
	if dialog then
		return dialog
	end
	dialog = CreateFrame("Frame", "LefthyToolsSellReservedDialog", UIParent)
	dialog:SetSize(420, 124)
	dialog:SetPoint("TOP", UIParent, "TOP", 0, -135)
	dialog:SetFrameStrata("DIALOG")
	dialog:SetToplevel(true)
	dialog:EnableMouse(true)
	dialog:Hide()
	dialog.Border = CreateFrame("Frame", nil, dialog, "DialogBorderTemplate") -- the game's popup look
	dialog.Border:SetAllPoints()
	dialog.Icon = dialog:CreateTexture(nil, "ARTWORK")
	dialog.Icon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
	dialog.Icon:SetSize(40, 40)
	dialog.Icon:SetPoint("TOPLEFT", 22, -20)
	dialog.Text = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	dialog.Text:SetPoint("TOPLEFT", 74, -22)
	dialog.Text:SetWidth(320)
	dialog.Text:SetJustifyH("LEFT")
	dialog.Sell = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	dialog.Sell:SetSize(140, 24)
	dialog.Sell:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -6, 18)
	dialog.Sell:SetText(L["Sell anyway"])
	dialog.Sell:SetScript("OnClick", SellAnyway)
	dialog.Keep = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	dialog.Keep:SetSize(140, 24)
	dialog.Keep:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", 6, 18)
	dialog.Keep:SetText(L["Keep it"])
	dialog.Keep:SetScript("OnClick", function() dialog:Hide() end)
	table.insert(UISpecialFrames, "LefthyToolsSellReservedDialog") -- Escape closes it
	return dialog
end

local function Confirm(bag, slot, itemID, entry)
	local d = Dialog()
	d.bag, d.slot, d.itemID, d.entry = bag, slot, itemID, entry
	d.Text:SetText(L["%s is reserved for %s: they won it. Sell it anyway?"]:format(entry.link or "?", entry.winner))
	d:Show()
	PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
end

---------------------------------------------------------------------------
-- Bags: the border, and the guard over the slot at a vendor
---------------------------------------------------------------------------

local hookedBags, marked = {}, {} -- bag frames hooked; item buttons showing the border

-- The guard's clicks: right-click asks first. Without pass-through (see Guard) it also does what
-- the slot would: left-click and drag pick the item up, hovering shows its tooltip.
local function GuardOnClick(guard, mouseButton)
	local button = guard:GetParent()
	local bag, slot = button:GetBagID(), button:GetID()
	if mouseButton == "LeftButton" then
		C_Container.PickupContainerItem(bag, slot)
		return
	end
	if IsModifiedClick() then -- Ctrl+right-click shows it to friends, as anywhere else
		local link = C_Container.GetContainerItemLink(bag, slot)
		if link then
			HandleModifiedItemClick(link, ItemLocation and ItemLocation:CreateFromBagAndSlot(bag, slot))
		end
		return
	end
	local itemID = C_Container.GetContainerItemID(bag, slot)
	local entry = itemID and EntryFor(itemID)
	if entry then
		Confirm(bag, slot, itemID, entry)
	elseif merchantOpen and itemID then
		C_Container.UseContainerItem(bag, slot) -- no longer reserved: sell, as the click meant
	end
end

local function GuardOnDragStart(guard)
	local button = guard:GetParent()
	C_Container.PickupContainerItem(button:GetBagID(), button:GetID())
end

local function GuardOnEnter(guard)
	local button = guard:GetParent()
	GameTooltip:SetOwner(guard, "ANCHOR_RIGHT")
	GameTooltip:SetBagItem(button:GetBagID(), button:GetID())
	GameTooltip:Show()
end

local function GuardOnLeave(guard)
	if GameTooltip:IsOwned(guard) then
		GameTooltip:Hide()
	end
end

-- Made out of combat only: pass-through and motion propagation can't be set in combat.
local function Guard(button)
	local guard = button.LefthyToolsSellGuard
	if guard or InCombatLockdown() then
		return guard
	end
	guard = CreateFrame("Button", nil, button)
	guard:SetAllPoints()
	guard:SetFrameLevel(button:GetFrameLevel() + 10)
	guard:RegisterForClicks("RightButtonUp")
	-- Left clicks (pick up, drag) and hovering reach the slot underneath.
	local passLeft = pcall(guard.SetPassThroughButtons, guard, "LeftButton")
	local passMotion = pcall(guard.SetPropagateMouseMotion, guard, true)
	if not passLeft then
		guard:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		guard:RegisterForDrag("LeftButton")
		guard:SetScript("OnDragStart", GuardOnDragStart)
	end
	if not passMotion then
		guard:SetScript("OnEnter", GuardOnEnter)
		guard:SetScript("OnLeave", GuardOnLeave)
	end
	guard:SetScript("OnClick", GuardOnClick)
	button.LefthyToolsSellGuard = guard
	return guard
end

local function Border(button)
	local border = button.LefthyToolsReserved
	if not border then
		border = button:CreateTexture(nil, "OVERLAY", nil, 6)
		border:SetTexture(BORDER)
		border:SetBlendMode("ADD")
		border:SetVertexColor(LINE_R, LINE_G, LINE_B, 1)
		border:SetPoint("CENTER")
		local size = (button:GetWidth() > 0 and button:GetWidth() or 37) * 1.8
		border:SetSize(size, size)
		button.LefthyToolsReserved = border
	end
	return border
end

local function Unmark(button)
	marked[button] = nil
	button.LefthyToolsReserved:Hide()
	if button.LefthyToolsSellGuard then
		button.LefthyToolsSellGuard:Hide()
	end
end

-- Post-hook on a bag frame's UpdateItems, and after changes to the list or the vendor.
local function MarkBag(frame)
	local any = list and list[1] and M.enabled
	if not (any or next(marked)) or not frame.EnumerateValidItems then
		return
	end
	for _, button in frame:EnumerateValidItems() do
		local itemID = any and C_Container.GetContainerItemID(button:GetBagID(), button:GetID())
		if itemID and EntryFor(itemID) then
			Border(button):Show()
			marked[button] = true
			local guard = merchantOpen and Guard(button) or button.LefthyToolsSellGuard
			if guard then
				guard:SetShown(merchantOpen)
			end
		elseif marked[button] then
			Unmark(button)
		end
	end
end

local function BagFrames()
	local frames = {}
	if ContainerFrameCombinedBags then
		frames[1] = ContainerFrameCombinedBags
	end
	for _, frame in ipairs(ContainerFrameContainer and ContainerFrameContainer.ContainerFrames or {}) do
		frames[#frames + 1] = frame
	end
	return frames
end

local function RefreshBags()
	for frame in pairs(hookedBags) do
		if frame:IsShown() then
			MarkBag(frame)
		end
	end
	for button in pairs(marked) do -- a closed bag's buttons: unmarked when it opens again anyway
		if not button:IsVisible() then
			Unmark(button)
		end
	end
end

local function HookBags()
	for _, frame in ipairs(BagFrames()) do
		if not hookedBags[frame] and type(frame.UpdateItems) == "function" then
			hookedBags[frame] = true
			hooksecurefunc(frame, "UpdateItems", MarkBag)
		end
	end
end

-- At a vendor, a reserved item that left the bags without the question (dragged onto the vendor,
-- sold from a bag addon): say so while it can still be bought back.
local function CountReserved(warn)
	local GetCount = C_Item and C_Item.GetItemCount
	if not GetCount then
		return
	end
	for _, entry in ipairs(list or {}) do
		local now = GetCount(entry.itemID) or 0
		local before = counts[entry.itemID]
		if warn and before and now < before then
			M:Print(("|cffff4040%s, which %s won, is gone: if you sold it, buy it back on the vendor's Buyback tab.|r")
				:format(entry.link or ("item " .. entry.itemID), entry.winner))
			PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
		end
		counts[entry.itemID] = now
	end
end

---------------------------------------------------------------------------
-- Mail: fill in the winner
---------------------------------------------------------------------------

local function CheckMail()
	if not (list and list[1] and SendMailNameEditBox and SendMailFrame and SendMailFrame:IsShown() and HasSendMailItem) then
		return
	end
	local winners, first, count, ids = {}, nil, 0, {}
	for slot = 1, ATTACHMENTS_MAX_SEND or 12 do
		if HasSendMailItem(slot) then
			local _, itemID = GetSendMailItem(slot)
			local entry = Readable(itemID) and EntryFor(itemID)
			if entry then
				ids[#ids + 1] = itemID
				if not winners[entry.winner] then
					winners[entry.winner], count = entry, count + 1
					first = first or entry
				end
			end
		end
	end
	if not first then
		return
	end
	local typed = SendMailNameEditBox:GetText() or ""
	if typed == "" then
		if count == 1 then
			SendMailNameEditBox:SetText(first.mailName or first.winner)
			M:Print(("mail to %s: they won %s."):format(first.winner, first.link or "it"))
		end
		return
	end
	local name = BaseName(typed)
	if not winners[name or ""] then
		local key = typed .. ":" .. table.concat(ids, ",")
		if mailWarned ~= key then
			mailWarned = key
			M:Print(("|cffff4040heads up: %s is reserved for %s, not %s.|r"):format(first.link or "it", first.winner, typed))
		end
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function ReadTradeItems()
	wipe(trade.items)
	for slot = 1, TRADE_SLOTS do
		local link = GetTradePlayerItemLink and GetTradePlayerItemLink(slot)
		local itemID = Readable(link) and tonumber(link:match("|Hitem:(%d+)"))
		if itemID then
			trade.items[#trade.items + 1] = itemID
		end
	end
end

local events = CreateFrame("Frame")
local handlers = {}

function handlers.TRADE_SHOW()
	local guid = UnitGUID("NPC")
	trade.name, trade.guid = BaseName(GetUnitName("NPC", false)), Readable(guid) and guid or nil
	wipe(trade.items)
	if list and list[1] then
		Soon("tradeNudge")
	end
end

handlers.TRADE_PLAYER_ITEM_CHANGED = ReadTradeItems
handlers.TRADE_ACCEPT_UPDATE = ReadTradeItems

function handlers.UI_INFO_MESSAGE(_, message)
	if message == ERR_TRADE_COMPLETE and trade.items[1] then
		local items = { unpack(trade.items) }
		wipe(trade.items)
		Delivered(items, trade.name, trade.guid)
	end
end

function handlers.MAIL_SEND_SUCCESS()
	if mail then
		local sent = mail
		mail = nil
		Delivered(sent.items, sent.name, nil)
	end
end

function handlers.MAIL_FAILED()
	mail = nil
end

function handlers.MAIL_SEND_INFO_UPDATE()
	if list and list[1] then
		Soon("mail")
	end
end

function handlers.MERCHANT_SHOW()
	merchantOpen = true
	wipe(counts)
	if list and list[1] then
		Soon("bags")
		Soon("count")
	end
end

function handlers.MERCHANT_CLOSED()
	merchantOpen = false
	wipe(counts)
	if dialog and dialog:IsShown() then
		Soon("closeDialog")
	end
	if next(marked) then
		Soon("bags")
	end
end

function handlers.BAG_UPDATE_DELAYED()
	if merchantOpen and next(counts) then
		Soon("sold")
	end
end

Run = function()
	scheduled = false
	local work = pending
	pending = {}
	if work.closeDialog and dialog then
		dialog:Hide()
	end
	if work.bags then
		RefreshBags()
	end
	if work.count then
		CountReserved(false)
	end
	if work.sold then
		CountReserved(true)
	end
	if work.mail then
		CheckMail()
	end
	if work.tradeNudge then
		local owed = {}
		for _, entry in ipairs(list or {}) do
			if (trade.guid and entry.guid and trade.guid == entry.guid) or (trade.name and BaseName(entry.winner) == trade.name) then
				owed[#owed + 1] = entry.link or ("item " .. entry.itemID)
			end
		end
		if owed[1] then
			M:Print(("%s won %s: put it in the trade."):format(trade.name or "they", table.concat(owed, ", ")))
		end
	end
end

local function OnSendMail(recipient)
	mail = nil
	if not (list and list[1]) then
		return
	end
	local items = {}
	for slot = 1, ATTACHMENTS_MAX_SEND or 12 do
		if HasSendMailItem and HasSendMailItem(slot) then
			local _, itemID = GetSendMailItem(slot)
			if Readable(itemID) then
				items[#items + 1] = itemID
			end
		end
	end
	if items[1] then
		mail = { name = BaseName(recipient), items = items }
	end
end

if type(SendMail) == "function" then
	hooksecurefunc("SendMail", OnSendMail)
end

events:SetScript("OnEvent", function(_, event, ...)
	handlers[event](...)
end)
for event in pairs(handlers) do
	pcall(events.RegisterEvent, events, event)
end

---------------------------------------------------------------------------
-- Saved list and /lefthy beacon handover
---------------------------------------------------------------------------

table.insert(LT.onLoad, function(db)
	db.handover = type(db.handover) == "table" and db.handover or {}
	list = db.handover
	local oldest = time() - KEEP_DAYS * 86400
	for i = #list, 1, -1 do
		if type(list[i]) ~= "table" or (list[i].at or 0) < oldest then
			table.remove(list, i)
		end
	end
end)

table.insert(LT.onLogin, HookBags)

function B.HandoverCommand(arg)
	if arg == "clear" then
		wipe(list)
		M:Print("hand-over reminders cleared.")
		Soon("bags")
		return
	end
	if not (list and list[1]) then
		M:Print("nothing to hand over.")
		return
	end
	for _, entry in ipairs(list) do
		M:Print(("  %s to %s (won %s)"):format(entry.link or ("item " .. entry.itemID), entry.winner,
			date("%Y-%m-%d %H:%M", entry.at)))
	end
	M:Print("they go away by themselves once traded or mailed to the winner; /lefthy beacon handover clear forgets them.")
end
