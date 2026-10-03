local _, ns = ...
local LT = ns.LT
local L = ns.L
local M = LT:GetModule("beacon")
local B = ns.Beacon

-- Hand-over reminder: an item I offered (Need / Pass, Items.lua) and someone won gets a line on its
-- tooltip, "Won by Anna: still to hand over", until I trade or mail it to them; opening a trade
-- with the winner also says so in chat. Kept in LefthyToolsDB.handover (the winner may be offline
-- for a while), at most MAX entries, each for KEEP_DAYS at most.
--
-- Handing over:
--   * trade: TRADE_SHOW gives the partner, TRADE_PLAYER_ITEM_CHANGED / TRADE_ACCEPT_UPDATE the items
--     I put in (slots 1-6; the 7th is "will not be traded"), UI_INFO_MESSAGE with ERR_TRADE_COMPLETE
--     means done (it may come after TRADE_CLOSED, so the snapshot lives until the next trade);
--   * mail: a post-hook on SendMail gives the recipient and the attachments, MAIL_SEND_SUCCESS means
--     done, MAIL_FAILED drops it.
-- An item given to someone else keeps its line. The partner is matched by GUID when both are known,
-- else by name; if the game won't tell who it is (a secret value), the item counts as handed over.
-- The tooltip line is a TooltipDataProcessor post-call (it runs before the tooltip is sized); it
-- returns right away while nothing is owed.

local MAX, KEEP_DAYS = 20, 7
local TRADE_SLOTS = 6
local LINE_R, LINE_G, LINE_B = 1, 0.55, 0.2

local list -- LefthyToolsDB.handover: { { itemID, link, winner, guid, at }, ... }, oldest first
local trade = { items = {} } -- the open (or last) trade: name, guid, items = { itemID, ... }
local mail -- a mail on its way: { name, items }

local function Readable(value)
	return value ~= nil and not (issecretvalue and issecretvalue(value))
end

-- "Anna" from "Anna" or "Anna-Realm".
local function BaseName(name)
	return Readable(name) and type(name) == "string" and name:match("^[^%-]+") or nil
end

local function Later(fn)
	C_Timer.After(0, fn) -- chat output outside the event handler
end

-- From Items.lua: my offer has a winner.
function B.AddHandover(itemString, link, winner, guid)
	local itemID = tonumber(itemString and itemString:match("^(%d+)"))
	if not (list and itemID and winner) then
		return
	end
	list[#list + 1] = { itemID = itemID, link = link, winner = winner, guid = guid, at = time() }
	while #list > MAX do
		table.remove(list, 1)
	end
end

-- The reminder for itemID given to name / guid (nil: unknown, any winner), or nil.
local function HandedOver(itemID, name, guid)
	for i, entry in ipairs(list or {}) do
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
				table.remove(list, i)
				return entry
			end
		end
	end
end

local function Delivered(items, name, guid)
	for _, itemID in ipairs(items) do
		local entry = HandedOver(itemID, name, guid)
		if entry then
			Later(function()
				M:Print(("%s handed over to %s."):format(entry.link or ("item " .. itemID), entry.winner))
			end)
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
-- Trades and mail
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
	if not (list and list[1]) then
		return
	end
	local owed = {}
	for _, entry in ipairs(list) do
		if (trade.guid and entry.guid and trade.guid == entry.guid) or (trade.name and BaseName(entry.winner) == trade.name) then
			owed[#owed + 1] = entry.link or ("item " .. entry.itemID)
		end
	end
	if owed[1] then
		Later(function()
			M:Print(("%s won %s: put it in the trade."):format(trade.name or "they", table.concat(owed, ", ")))
		end)
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

function B.HandoverCommand(arg)
	if arg == "clear" then
		wipe(list)
		M:Print("hand-over reminders cleared.")
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
