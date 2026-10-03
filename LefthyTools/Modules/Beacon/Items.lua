local _, ns = ...
local LT = ns.LT
local L = ns.L
local M = LT:GetModule("beacon")
local B = ns.Beacon

-- Item sharing: Ctrl+right-click an item (bags, character, bank, loot, merchant, quest rewards,
-- chat links: everything that goes through Blizzard's HandleModifiedItemClick) and every friend
-- with Beacon gets "Anna shares [item]" in chat, as a clickable link, and as a notice on screen
-- with the whisper sound. Handy for "does anyone need this?".
--
-- The click is a post-hook on HandleModifiedItemClick, so Blizzard's own handling runs first and
-- stays untainted (for gear, Ctrl+click also opens the game's preview, as always).
-- Message: I2;<item string> (the part after "item:" of the link: id, enchant, suffix, ...), so
-- receivers build a real link in their own language; their client loads the item if needed.

local SEND_GAP = 3       -- my shares at most this often
local NOTICE_TIME, NOTICE_FADE = 4, 1

local lastSent = -math.huge

-- "12345:0:0:..." from an item link, or nil.
local function ItemString(link)
	local itemString = type(link) == "string" and link:match("|Hitem:([%-%d:]+)|h")
	if itemString and #itemString <= 200 then
		return itemString
	end
end

local function Peers()
	local count = 0
	for _ in pairs(B.peers) do
		count = count + 1
	end
	return count
end

function B.ShareItem(link)
	local itemString = ItemString(link)
	if not (M.enabled and M.db.shareItems and itemString) then
		return
	end
	local now = GetTime()
	if now - lastSent < SEND_GAP then
		return
	end
	local count = Peers()
	if count == 0 then
		M:Print("no friends with LefthyTools online to show it to.")
		return
	end
	lastSent = now
	B.QueueToPeers(("I%s;%s"):format(B.VERSION, itemString))
	M:Print(("shared %s with %d friend(s)."):format(link, count))
end

local function OnModifiedItemClick(link)
	if GetMouseButtonClicked() == "RightButton" and IsControlKeyDown() and not IsShiftKeyDown() and not IsAltKeyDown() then
		B.ShareItem(link)
	end
end

if type(HandleModifiedItemClick) == "function" then
	hooksecurefunc("HandleModifiedItemClick", OnModifiedItemClick)
end

---------------------------------------------------------------------------
-- Receiving: a chat line with the link, a notice on screen and the whisper sound (easy to miss otherwise)
---------------------------------------------------------------------------

local notice

local function NoticeOnUpdate(self)
	local age = GetTime() - self.shownAt
	if age >= NOTICE_TIME + NOTICE_FADE then
		self:Hide()
	elseif age > NOTICE_TIME then
		self:SetAlpha(1 - (age - NOTICE_TIME) / NOTICE_FADE)
	end
end

local function ShowNotice(text)
	if not notice then
		notice = CreateFrame("Frame", nil, UIParent)
		notice:SetSize(800, 30)
		notice:SetPoint("TOP", UIParent, "TOP", 0, -205) -- under the level-up toast
		notice:SetFrameStrata("HIGH")
		notice.Text = notice:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		notice.Text:SetAllPoints()
		notice:SetScript("OnUpdate", NoticeOnUpdate)
	end
	notice.Text:SetText(text)
	notice.shownAt = GetTime()
	notice:SetAlpha(1)
	notice:Show()
end

-- A real link in this client's language, once the item is loaded (it may have to be asked for).
local function WithLink(itemString, callback)
	local itemLink = "item:" .. itemString
	local item = Item and Item.CreateFromItemLink and Item:CreateFromItemLink(itemLink)
	if item and not item:IsItemEmpty() then
		item:ContinueOnItemLoad(function()
			local _, link = C_Item.GetItemInfo(itemLink)
			callback(link)
		end)
	else
		local _, link = C_Item.GetItemInfo(itemLink)
		callback(link)
	end
end

-- A friend's I message, on the driver tick.
function B.ReceiveItem(peer, itemString)
	if not M.db.shareItems then
		return
	end
	local name = LT.Window.ClassColorCode(peer.classFile) .. peer.name .. "|r"
	WithLink(itemString, function(link)
		if not link then
			return
		end
		M:Print(("%s shares %s."):format(name, link))
		ShowNotice(L["%s shares %s"]:format(name, link))
		PlaySound(SOUNDKIT and SOUNDKIT.TELL_MESSAGE or 3081) -- the whisper sound
	end)
	B.Notify("item", peer, { itemString = itemString })
end
