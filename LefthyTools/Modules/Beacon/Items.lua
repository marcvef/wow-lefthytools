local _, ns = ...
local LT = ns.LT
local L = ns.L
local M = LT:GetModule("beacon")
local B = ns.Beacon

-- Item sharing: Ctrl+right-click an item (bags, character, bank, loot, merchant, quest rewards,
-- chat links: everything that goes through Blizzard's HandleModifiedItemClick) and every friend
-- with Beacon gets "Anna shares [item]" at the top of the screen and the whisper sound. Ctrl+Shift+right-click
-- offers it: the notice gets Need and Pass buttons, and after CALL_TIME seconds, or once
-- everyone answered, the sharer's client decides:
-- nobody, one Need (they get it), or several: everyone sees a drumroll (the bonus roll spinner
-- sound, numbers whirling) and then the rolls, with the winner in big gold letters and a fanfare.
--
-- Messages: I2;<item string>;<call id> (the share; without the id from older builds: no
-- buttons), N2;<call id>;<1 = need | 0 = pass> (to the sharer), R2;<call id>;<name>:<roll>,...
-- (the result to everyone, highest first; roll 0 = the only one, no roll needed). The sharer's
-- client is the referee: it rolls 1-100 per Need and rolls ties again.
--
-- The click is a post-hook on HandleModifiedItemClick: Blizzard's own handling runs first and
-- stays untainted (for gear, Ctrl+click also opens the game's preview, as always).

local SEND_GAP = 3        -- my shares at most this often
local CALL_TIME = 20      -- seconds to answer Need or Pass
local ROLL_TIME = 2.5     -- the drumroll
local SHOW_RESULT = 7     -- how long the result stays before the notice fades
local FADE = 1
local MAX_FRAMES = 3      -- calls shown at once (stacked)
local NEED_ICON = "Interface\\Buttons\\UI-GroupLoot-Dice-Up"
local PASS_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
local SOUND = {
	call = SOUNDKIT and SOUNDKIT.TELL_MESSAGE or 3081,              -- the whisper sound
	rollStart = SOUNDKIT and SOUNDKIT.UI_BONUS_LOOT_ROLL_START or 31579,
	rollLoop = SOUNDKIT and SOUNDKIT.UI_BONUS_LOOT_ROLL_LOOP or 31580,
	rollEnd = SOUNDKIT and SOUNDKIT.UI_BONUS_LOOT_ROLL_END or 31581,
	win = SOUNDKIT and SOUNDKIT.UI_EPICLOOT_TOAST or 31578,
	need = SOUNDKIT and SOUNDKIT.UI_NEED_ROLL_POSITIVE or 229319,
}

local lastSent = -math.huge
-- calls[key] = { id, mine, from (gameAccountID), fromName, link, itemString, ends, recipients,
--   answers = { [gameAccountID] = { name, need } }, myAnswer, state = "open" | "rolling" | "done",
--   result = { { name, roll }, ... }, frame }
-- key: "me:<id>" for mine, "<gameAccountID>:<id>" for a friend's.
local calls = {}
B.calls = calls

-- "12345:0:0:..." from an item link, or nil.
local function ItemString(link)
	local itemString = type(link) == "string" and link:match("|Hitem:([%-%d:]+)|h")
	if itemString and #itemString <= 200 then
		return itemString
	end
end

local function Coloured(name, classFile)
	return LT.Window.ClassColorCode(classFile) .. (name or "?") .. "|r"
end

local function MyName()
	return UnitName("player")
end

---------------------------------------------------------------------------
-- The notice: one frame per call, stacked at the top of the screen
---------------------------------------------------------------------------

local framePool, shown = {}, {}

-- No box: one line of shadowed text with the icon in it, like the game's own messages at the top
-- of the screen. Offers get the answers, Need / Pass and a timer underneath.
local TOP_Y, GAP = -220, 10 -- under the level-up toast
local LINE_HEIGHT, OFFER_HEIGHT = 22, 76
local TEXT_SCALE = 1.15
local BUTTON_WIDTH, BUTTON_GAP = 96, 8
local TIMER_WIDTH = 2 * BUTTON_WIDTH + BUTTON_GAP

local function Layout()
	local y = TOP_Y
	for _, frame in ipairs(shown) do
		frame:ClearAllPoints()
		frame:SetPoint("TOP", UIParent, "TOP", 0, y)
		y = y - frame:GetHeight() - GAP
	end
end

local function Release(frame)
	if GameTooltip:IsOwned(frame.Hover) then
		GameTooltip:Hide()
	end
	frame:Hide()
	if frame.call then
		frame.call.frame = nil -- the call gets a frame again if it needs one (FrameFor)
	end
	frame.call = nil
	for i, f in ipairs(shown) do
		if f == frame then
			table.remove(shown, i)
			break
		end
	end
	framePool[#framePool + 1] = frame
	Layout()
end

local Answer -- below

-- Hovering the line shows the item's tooltip, as on an item in the bags.
local function HoverOnEnter(hover)
	local call = hover:GetParent().call
	if call then
		GameTooltip:SetOwner(hover, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink("item:" .. call.itemString)
		GameTooltip:Show()
	end
end

local function HoverOnLeave(hover)
	if GameTooltip:IsOwned(hover) then
		GameTooltip:Hide()
	end
end

-- Shift-click links it in chat, Ctrl-click previews it: the game's own item click handling.
local function HoverOnClick(hover)
	local call = hover:GetParent().call
	if call and IsModifiedClick() then
		HandleModifiedItemClick(call.link)
	end
end

local function NewFrame()
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetSize(600, LINE_HEIGHT)
	f:SetFrameStrata("HIGH")
	-- "[icon] Anna shares [item]": one line, as wide as it needs.
	f.Line = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.Line:SetPoint("TOP")
	f.Line:SetWordWrap(false)
	f.Line:SetTextScale(TEXT_SCALE)
	-- An invisible button over the line (it's as wide as its text): the item's tooltip on hover.
	-- Frame hyperlinks would be the other way, but SetHyperlinksEnabled is protected in Forever.
	f.Hover = CreateFrame("Button", nil, f)
	f.Hover:SetAllPoints(f.Line)
	f.Hover:SetScript("OnEnter", HoverOnEnter)
	f.Hover:SetScript("OnLeave", HoverOnLeave)
	f.Hover:SetScript("OnClick", HoverOnClick)
	f.Status =f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.Status:SetPoint("TOP", 0, -26)
	f.Status:SetWidth(580)
	f.Status:SetWordWrap(false)
	f.Need = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.Need:SetSize(BUTTON_WIDTH, 24)
	f.Need:SetPoint("TOPRIGHT", f, "TOP", -BUTTON_GAP / 2, -46)
	f.Need:SetText(("|T%s:16:16|t %s"):format(NEED_ICON, L["Need"]))
	f.Need:SetScript("OnClick", function() Answer(f.call, true) end)
	f.Pass = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.Pass:SetSize(BUTTON_WIDTH, 24)
	f.Pass:SetPoint("TOPLEFT", f, "TOP", BUTTON_GAP / 2, -46)
	f.Pass:SetText(("|T%s:16:16|t %s"):format(PASS_ICON, L["Pass"]))
	f.Pass:SetScript("OnClick", function() Answer(f.call, false) end)
	f.Timer = f:CreateTexture(nil, "ARTWORK")
	f.Timer:SetPoint("TOPLEFT", f.Need, "BOTTOMLEFT", 0, -3)
	f.Timer:SetHeight(2)
	f.Timer:SetColorTexture(1, 0.82, 0, 0.9)
	-- The winner, where the buttons were, popping in (scaled around its own centre).
	f.Result = CreateFrame("Frame", nil, f)
	f.Result:SetSize(500, 28)
	f.Result:SetPoint("TOP", 0, -44)
	f.Winner = f.Result:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	f.Winner:SetAllPoints()
	f.Pop = f.Result:CreateAnimationGroup()
	local grow = f.Pop:CreateAnimation("Scale")
	grow:SetScaleFrom(1.5, 1.5)
	grow:SetScaleTo(1, 1)
	grow:SetDuration(0.3)
	local appear = f.Pop:CreateAnimation("Alpha")
	appear:SetFromAlpha(0)
	appear:SetToAlpha(1)
	appear:SetDuration(0.2)
	return f
end

-- "[icon] You offer [item]", "[icon] Anna offers [item]" or "[icon] Anna shares [item]".
local function Headline(call)
	local itemID = tonumber(call.itemString:match("^(%d+)"))
	local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID) or 134400
	local text
	if call.mine then
		text = L["You offer %s"]:format(call.link)
	else
		local who = Coloured(call.fromName, call.fromClass)
		text = (call.id and L["%s offers %s"] or L["%s shares %s"]):format(who, call.link)
	end
	return ("|T%s:0|t %s"):format(icon, text)
end

local function FrameFor(call)
	if call.frame then
		return call.frame
	end
	if #shown >= MAX_FRAMES then
		-- The oldest finished one makes room, or else the oldest.
		local victim = shown[1]
		for _, f in ipairs(shown) do
			if f.call and f.call.state == "done" then
				victim = f
				break
			end
		end
		Release(victim)
	end
	local frame = table.remove(framePool) or NewFrame()
	frame.call, call.frame = call, frame
	frame:SetAlpha(1)
	frame.Winner:SetText("")
	frame.Status:SetText("")
	frame.Line:SetText(Headline(call))
	frame:SetHeight(call.id and OFFER_HEIGHT or LINE_HEIGHT)
	shown[#shown + 1] = frame
	Layout()
	frame:Show()
	return frame
end

-- Stores a call; one already under that key gives up its notice.
local function Put(key, call)
	local old = calls[key]
	if old then
		if old.sound and StopSound then
			StopSound(old.sound)
		end
		if old.frame then
			Release(old.frame)
		end
	end
	calls[key] = call
end

local function Answers(call)
	local parts = {}
	for _, a in pairs(call.answers) do
		parts[#parts + 1] = a.name .. ": " .. (a.need and ("|cff40ff40" .. L["Need"] .. "|r") or ("|cffaaaaaa" .. L["Pass"] .. "|r"))
	end
	table.sort(parts)
	return table.concat(parts, "   ")
end

-- Fills the notice for the call's current state.
local function Draw(call)
	local f = FrameFor(call)
	local open = call.state == "open"
	f.Need:SetShown(open and not call.mine and call.id ~= nil and call.myAnswer == nil)
	f.Pass:SetShown(open and not call.mine and call.id ~= nil and call.myAnswer == nil)
	f.Timer:SetShown(open and call.id ~= nil)
	if open then
		if call.mine then
			f.Status:SetText(next(call.answers) and Answers(call) or ("|cffaaaaaa" .. L["Waiting for your friends..."] .. "|r"))
		elseif call.myAnswer ~= nil then
			f.Status:SetText(call.myAnswer and ("|cff40ff40" .. L["You need it. Fingers crossed!"] .. "|r")
				or ("|cffaaaaaa" .. L["You passed."] .. "|r"))
		end
	end
end

---------------------------------------------------------------------------
-- Results: nobody, one Need, or a roll with a drumroll
---------------------------------------------------------------------------

local function WinnerText(name)
	if name == MyName() then
		return L["You win!"]
	end
	return L["%s wins!"]:format(name)
end

local function RollLines(call, rolls)
	local lines = {}
	for i, entry in ipairs(call.result) do
		local roll = rolls and rolls[i] or entry.roll
		local colour = (not rolls and i == 1) and "|cffffd200" or "|cffffffff"
		lines[#lines + 1] = ("%s%s  %d|r"):format(colour, entry.name, roll)
	end
	return table.concat(lines, "    ")
end

local function Finish(call)
	call.state, call.doneAt = "done", GetTime()
	local f = FrameFor(call)
	local result = call.result
	f.Need:Hide()
	f.Pass:Hide()
	f.Timer:Hide()
	if #result == 0 then
		f.Status:SetText("|cffaaaaaa" .. L["Nobody needs it."] .. "|r")
		M:Print(("nobody needs %s."):format(call.link))
		return
	end
	local winner = result[1].name
	f.Status:SetText(#result > 1 and RollLines(call) or "")
	f.Winner:SetText("|cffffd200" .. WinnerText(winner) .. "|r")
	f.Pop:Play()
	PlaySound(SOUND.win)
	if #result > 1 then
		local others = {}
		for i = 2, #result do
			others[#others + 1] = ("%s %d"):format(result[i].name, result[i].roll)
		end
		M:Print(("%s wins %s with %d (%s)."):format(winner, call.link, result[1].roll, table.concat(others, ", ")))
	else
		M:Print(("%s gets %s."):format(winner, call.link))
	end
	if call.mine and B.AddHandover then
		-- My item: its tooltip reminds me until it's traded or mailed to them (Handover.lua).
		local guid, account
		for gameAccountID, a in pairs(call.answers) do
			if a.name == winner then
				guid, account = a.guid, gameAccountID
			end
		end
		B.AddHandover(call.itemString, call.link, winner, guid, account)
		M:Print(("its tooltip reminds you until you trade or mail it to %s."):format(winner))
	end
end

local function StartResult(call, result)
	call.result = result
	if #result > 1 then
		call.state, call.rollEnds = "rolling", GetTime() + ROLL_TIME
		local f = FrameFor(call)
		f.Need:Hide()
		f.Pass:Hide()
		f.Timer:Hide()
		f.Winner:SetText("|cffffd200" .. L["Rolling..."] .. "|r")
		PlaySound(SOUND.rollStart)
		local _, handle = PlaySound(SOUND.rollLoop)
		call.sound = handle
	else
		Finish(call)
	end
end

-- "Anna:87,Bob:12" -> { { name, roll }, ... }
local function ParseResult(text)
	local result = {}
	for name, roll in text:gmatch("([^,:]+):(%d+)") do
		result[#result + 1] = { name = name, roll = tonumber(roll) }
	end
	return result
end

-- My call is over: roll for everyone who needs it and tell everyone.
local function Decide(call)
	local needers = {}
	for _, a in pairs(call.answers) do
		if a.need then
			needers[#needers + 1] = a.name
		end
	end
	table.sort(needers)
	local result = {}
	if #needers == 1 then
		result[1] = { name = needers[1], roll = 0 }
	elseif #needers > 1 then
		local taken = {}
		for _, name in ipairs(needers) do
			local roll
			repeat
				roll = math.random(1, 100)
			until not taken[roll] -- no ties
			taken[roll] = true
			result[#result + 1] = { name = name, roll = roll }
		end
		table.sort(result, function(a, b) return a.roll > b.roll end)
	end
	local entries = {}
	for _, entry in ipairs(result) do
		entries[#entries + 1] = entry.name .. ":" .. entry.roll
	end
	B.QueueToPeers(("R%s;%d;%s"):format(B.VERSION, call.id, table.concat(entries, ",")))
	StartResult(call, result)
end

---------------------------------------------------------------------------
-- Sharing and answering
---------------------------------------------------------------------------

-- offer: friends can say Need or Pass, and it's rolled out (Ctrl+Shift+right-click); otherwise
-- they just see it (Ctrl+right-click).
function B.ShareItem(link, offer)
	local itemString = ItemString(link)
	if not (M.enabled and M.db.shareItems and itemString) then
		return
	end
	local now = GetTime()
	if now - lastSent < SEND_GAP then
		return
	end
	local recipients, count = {}, 0
	for gameAccountID in pairs(B.peers) do
		recipients[gameAccountID], count = true, count + 1
	end
	if count == 0 then
		M:Print("no friends with LefthyTools online to show it to.")
		return
	end
	lastSent = now
	if not offer then
		B.QueueToPeers(("I%s;%s"):format(B.VERSION, itemString))
		M:Print(("shared %s with %d friend(s)."):format(link, count))
		return
	end
	local id
	repeat
		id = math.random(1, 99999)
	until not calls["me:" .. id]
	local call = { id = id, mine = true, link = link, itemString = itemString, recipients = recipients,
		answers = {}, state = "open", ends = now + CALL_TIME }
	calls["me:" .. id] = call
	B.QueueToPeers(("I%s;%s;%d"):format(B.VERSION, itemString, id))
	M:Print(("offered %s to %d friend(s): they can say Need or Pass."):format(link, count))
	Draw(call)
end

function Answer(call, need)
	if not call or call.mine or call.state ~= "open" or call.myAnswer ~= nil then
		return
	end
	call.myAnswer = need
	B.Queue(call.from, ("N%s;%d;%d"):format(B.VERSION, call.id, need and 1 or 0))
	if need then
		PlaySound(SOUND.need)
	end
	Draw(call)
end

-- Only items that can change hands are shared: not soulbound (unless the loot trade timer still
-- runs: "You may trade this item with players that were also eligible..."), not bound to the
-- account, not quest items. A bag item is asked directly (the clicked slot is the mouse focus);
-- a worn item is bound; anything else (chat links, the loot window) goes by its bind type.
local NO_TRADE_BIND = { [1] = true, [4] = true, [7] = true, [8] = true, [9] = true } -- Enum.ItemBind
local ALWAYS_BOUND = { [4] = true, [7] = true, [8] = true, [9] = true } -- quest, account

local tradeTimerPattern
local function HasTradeTimer(bag, slot)
	if not (C_TooltipInfo and C_TooltipInfo.GetBagItem and BIND_TRADE_TIME_REMAINING) then
		return false
	end
	if not tradeTimerPattern then
		local escaped = BIND_TRADE_TIME_REMAINING:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
		tradeTimerPattern = "^" .. escaped:gsub("%%%%s", ".+") -- "%s" (escaped "%%s"): the time
	end
	local data = C_TooltipInfo.GetBagItem(bag, slot)
	for _, line in ipairs(data and data.lines or {}) do
		local text = line.leftText
		if type(text) == "string" and not (issecretvalue and issecretvalue(text)) and text:find(tradeTimerPattern) then
			return true
		end
	end
	return false
end

local function Shareable(link)
	local bindType = select(14, C_Item.GetItemInfo(link))
	local focus = GetMouseFoci and GetMouseFoci()[1] or (GetMouseFocus and GetMouseFocus())
	if focus and focus.IsForbidden and focus:IsForbidden() then
		focus = nil
	end
	if focus and focus.isSellGuard then
		focus = focus:GetParent() -- Handover.lua's guard over a reserved bag slot
	end
	local bag = focus and focus.GetBagID and focus:GetBagID()
	if bag and C_Container.GetContainerItemLink(bag, focus:GetID()) == link then
		local slot = focus:GetID()
		local info = C_Container.GetContainerItemInfo(bag, slot)
		if (info and info.isBound) or ALWAYS_BOUND[bindType] then
			return HasTradeTimer(bag, slot)
		end
		return true
	end
	if focus and not bag and focus.GetID and GetInventoryItemLink("player", focus:GetID()) == link then
		return false -- worn: equipping binds it
	end
	return not NO_TRADE_BIND[bindType]
end

local function OnModifiedItemClick(link, itemLocation)
	if type(link) ~= "string" then
		return -- an empty slot: Blizzard calls this with no link
	end
	if GetMouseButtonClicked() == "RightButton" and IsControlKeyDown() and not IsAltKeyDown() then
		if not (M.enabled and M.db.shareItems) then
			return
		end
		if not Shareable(link) then
			M:Print(("%s is soulbound or can't be traded: nothing to share."):format(link))
			return
		end
		B.ShareItem(link, IsShiftKeyDown()) -- with Shift: let them roll for it
	end
end

if type(HandleModifiedItemClick) == "function" then
	hooksecurefunc("HandleModifiedItemClick", OnModifiedItemClick)
end

---------------------------------------------------------------------------
-- From friends (on Beacon's tick)
---------------------------------------------------------------------------

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

-- A friend's share (callID nil from builds without Need / Pass).
function B.ReceiveItem(peer, gameAccountID, itemString, callID)
	if not M.db.shareItems then
		return
	end
	WithLink(itemString, function(link)
		-- (Loading can take a moment: Beacon or the setting may be off by then.)
		if not (link and M.enabled and M.db.shareItems) then
			return
		end
		M:Print(("%s shares %s."):format(Coloured(peer.name, peer.classFile), link))
		local now = GetTime()
		local call = { id = callID, from = gameAccountID, fromName = peer.name, fromClass = peer.classFile, link = link,
			itemString = itemString, answers = {}, state = "open", ends = now + CALL_TIME + 5 }
		if not callID then
			call.state, call.doneAt = "done", now -- just showing it: no buttons, fades after a while
		end
		Put(gameAccountID .. ":" .. (callID or ("x" .. now)), call)
		Draw(call)
		PlaySound(SOUND.call)
	end)
	B.Notify("item", peer, { itemString = itemString })
end

-- A friend answers my call.
function B.ReceiveAnswer(peer, gameAccountID, callID, need)
	local call = calls["me:" .. callID]
	if not call or call.state ~= "open" or not call.recipients[gameAccountID] or call.answers[gameAccountID] then
		return
	end
	call.answers[gameAccountID] = { name = B.Clean(peer.name, 48), need = need, guid = peer.guid }
	Draw(call)
end

-- The sharer's verdict on a call I got.
function B.ReceiveResult(peer, gameAccountID, callID, text)
	local call = calls[gameAccountID .. ":" .. callID]
	if not call or call.state ~= "open" then
		return
	end
	StartResult(call, ParseResult(text))
end

-- Beacon's tick: timers, the drumroll, fading out.
function B.UpdateCalls(now)
	if not next(calls) then
		return
	end
	for key, call in pairs(calls) do
		local f = call.frame
		if call.state == "open" then
			if not f and #shown < MAX_FRAMES then
				Draw(call) -- it made room for a newer one earlier: back, buttons and all
				f = call.frame
			end
			if f and call.id then
				local total = call.mine and CALL_TIME or CALL_TIME + 5
				f.Timer:SetWidth(math.max(1, TIMER_WIDTH * math.max(0, call.ends - now) / total))
			end
			local everyone = call.mine
			if everyone then
				for id in pairs(call.recipients) do
					if not call.answers[id] then
						everyone = false
						break
					end
				end
			end
			if call.mine and (now >= call.ends or everyone) then
				Decide(call)
			elseif not call.mine and now >= call.ends then
				-- no verdict came (they went offline): let it go
				call.state, call.doneAt = "done", now - SHOW_RESULT + 2
				if f then
					f.Need:Hide()
					f.Pass:Hide()
					f.Timer:Hide()
				end
			end
		elseif call.state == "rolling" then
			if now >= call.rollEnds then
				if call.sound and StopSound then
					StopSound(call.sound)
				end
				PlaySound(SOUND.rollEnd)
				Finish(call)
			elseif f then
				local rolls = {}
				for i = 1, #call.result do
					rolls[i] = math.random(1, 100) -- whirling numbers
				end
				f.Status:SetText(RollLines(call, rolls))
			end
		elseif call.state == "done" then
			local age = now - call.doneAt
			if f then
				if age >= SHOW_RESULT + FADE then
					Release(f)
					call.frame = nil
				elseif age > SHOW_RESULT then
					f:SetAlpha(1 - (age - SHOW_RESULT) / FADE)
				end
			end
			if age >= SHOW_RESULT + FADE then
				calls[key] = nil
			end
		end
	end
end

function B.ReleaseCalls()
	for key, call in pairs(calls) do
		if call.sound and StopSound then
			StopSound(call.sound)
		end
		if call.frame then
			Release(call.frame)
		end
		calls[key] = nil
	end
end
