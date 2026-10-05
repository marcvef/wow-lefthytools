local _, ns = ...
local LT = ns.LT
local L = ns.L
local M = LT:GetModule("tweaks")
local data = ns.MirageData -- the window lists Mirage uses to tell whether the UI is in use

-- AFK screen (a Misc Tweak; works without Mirage): while you're away (/afk or the game's
-- auto-AFK) the interface disappears, the camera slowly circles your character, and a panel shows your character, how long you've been away,
-- the time, your level progress, whispers and friends' news since then, and which Beacon
-- friends are online and where. Moving, combat, a popup that needs you (ready check, invite,
-- trade, ...), opening a window or a click brings everything back.
--
-- The interface is hidden with UIParent:SetAlpha(0) (ns.HideInterface), not Hide(): SetAlpha isn't protected, so
-- the screen can be left at any moment, also when combat starts (Hide/Show on UIParent is blocked
-- in combat). The panel is a frame without a parent, so it stays visible, and it takes mouse
-- clicks, so nothing invisible underneath can be clicked by accident.
--
-- Cost: nothing while you're not AFK. PLAYER_FLAGS_CHANGED shows the driver for one check on the
-- next frame; only while the screen is up does it run, checking 4x a second whether to leave and
-- updating the texts once a second.

local SPIN_SPEED = 0.03  -- MoveViewLeftStart speed: a slow circle
local POLL = 0.25        -- while shown: how often to check whether to leave
local REFRESH = 1        -- while shown: how often the texts update
local MAX_FRIENDS = 5       -- up to three lines each
local MAX_NEWS = 6
local LEAVE_EVENTS = {   -- things that need the interface right away
	"PLAYER_REGEN_DISABLED", "READY_CHECK", "PARTY_INVITE_REQUEST", "LFG_PROPOSAL_SHOW", "TRADE_SHOW",
	"DUEL_REQUESTED", "CONFIRM_SUMMON", "RESURRECT_REQUEST", "PLAYER_DEAD", "CINEMATIC_START", "PLAY_MOVIE",
}
local issecret = issecretvalue or function() return false end

local AFK = {}
ns.AFKScreen = AFK
-- Other modules add lines to the panel: function() return { "line", ... } end (Chronicle).
AFK.sections = {}

local screen -- built on first use
local driver = CreateFrame("Frame")
driver:Hide()
AFK.driver = driver
local events = CreateFrame("Frame")
local shown, dismissed, checkPending, leaveNow = false, false, false, false
local since, spinning
local sincePoll, sinceRefresh = 0, 0
local whispers, lastWhisper = 0, nil
local news = {} -- friends' news while away (OnFriendEvent): { kind, name, classFile, data }
local listening = false

local function IsAFK()
	local afk = UnitIsAFK("player")
	return not issecret(afk) and afk == true
end

local function ChatActive()
	if ACTIVE_CHAT_EDIT_BOX then
		return true
	end
	local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
	return focus ~= nil
end

local function WindowOpen()
	if GetUIPanel then
		for _, area in ipairs(data.PANEL_AREAS) do
			if GetUIPanel(area) then
				return true
			end
		end
	end
	if IsAnyBagOpen and IsAnyBagOpen() then
		return true
	end
	for _, name in ipairs(data.WINDOWS) do
		local f = _G[name]
		if type(f) == "table" and f.IsShown and f:IsShown() then
			return true
		end
	end
	return false
end

local function InCombat()
	return InCombatLockdown() or UnitAffectingCombat("player")
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------

local function Text(parent, font, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY", font)
	fs:SetJustifyH(justify or "LEFT")
	fs:SetJustifyV("BOTTOM")
	return fs
end

local function Build()
	screen = CreateFrame("Frame", "LefthyToolsAFKFrame") -- no parent: stays while UIParent is invisible
	screen:SetFrameStrata("FULLSCREEN_DIALOG")
	screen:SetAllPoints(UIParent)
	screen:EnableMouse(true)
	screen:SetScript("OnMouseDown", function()
		leaveNow = true -- left on the next frame, not inside the click
	end)
	screen:Hide()

	local band = screen:CreateTexture(nil, "BACKGROUND")
	band:SetPoint("BOTTOMLEFT")
	band:SetPoint("BOTTOMRIGHT")
	band:SetHeight(260)
	band:SetColorTexture(0, 0, 0, 0.6)

	screen.Model = CreateFrame("PlayerModel", nil, screen)
	screen.Model:SetSize(260, 340)
	screen.Model:SetPoint("BOTTOMLEFT", 30, 0)

	screen.Title = Text(screen, "GameFontNormalHuge")
	screen.Title:SetPoint("BOTTOMLEFT", 300, 150)
	screen.Name = Text(screen, "GameFontHighlightLarge")
	screen.Name:SetPoint("BOTTOMLEFT", 300, 118)
	screen.Info = Text(screen, "GameFontHighlight")
	screen.Info:SetPoint("BOTTOMLEFT", 300, 20)
	screen.Info:SetWidth(420)
	screen.Info:SetSpacing(3)
	screen.Friends = Text(screen, "GameFontHighlight")
	screen.Friends:SetPoint("BOTTOMRIGHT", -40, 20)
	screen.Friends:SetWidth(440)
	screen.Friends:SetSpacing(2)
	screen.Hint = Text(screen, "GameFontDisableSmall", "CENTER")
	screen.Hint:SetPoint("BOTTOM", 0, 4)
	screen.Hint:SetText(L["Move, or click anywhere, to come back."])
end

local function Clock(seconds)
	seconds = math.floor(seconds + 0.5) -- refreshed right on the second: 64.9999 is 65
	local h, m, s = math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60
	if h > 0 then
		return ("%d:%02d:%02d"):format(h, m, s)
	end
	return ("%d:%02d"):format(m, s)
end

local function ColouredName(name, classFile)
	return LT.Window.ClassColorCode(classFile) .. (name or "?") .. "|r"
end

-- A friend's text, cut so a line doesn't grow the panel much (links and colours go first, so
-- nothing is cut in half).
local function Short(text)
	if #text > 90 then
		text = text:gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", "")
	end
	if #text > 90 then
		text = text:sub(1, 87):gsub("[\192-\255][\128-\191]*$", "") .. "..."
	end
	return text
end

local function NewsLine(item)
	local who = ColouredName(item.name, item.classFile)
	if item.kind == "level" then
		return L["%s reached level %d"]:format(who, item.data.level or 0)
	elseif item.kind == "death" then
		return item.data.foe and L["%s died, fighting %s"]:format(who, item.data.foe) or L["%s died"]:format(who)
	elseif item.kind == "item" and item.data.link then -- Beacon: shown or offered (a click brings back its buttons)
		return (item.data.offer and L["%s offers %s"] or L["%s shares %s"]):format(who, item.data.link)
	elseif item.kind == "chat" and item.data.text then -- Lefthy chat
		return "|cffffb84d[Lefthy]|r " .. who .. ": " .. Short(item.data.text)
	elseif item.kind == "announce" and item.data.text then
		return who .. ": |cffffd200" .. Short(item.data.text) .. "|r"
	end
	return item.data.text and (who .. ": " .. item.data.text) or nil
end

-- Each Beacon friend (Beacon's B.FriendLines: who, where, what they're doing), up to MAX_FRIENDS.
local function FriendLines(lines)
	local beacon = LT:GetModule("beacon")
	local B = ns.Beacon
	local list = beacon and beacon.enabled and B and B.FriendList() or {}
	lines[#lines + 1] = "|cffffd200" .. L["Friends online"] .. "|r"
	if #list == 0 then
		lines[#lines + 1] = "|cff999999" .. L["No friends with LefthyTools online"] .. "|r"
	end
	for i = 1, math.min(#list, MAX_FRIENDS) do
		if i > 1 then
			lines[#lines + 1] = " "
		end
		B.FriendLines(lines, list[i].peer, list[i].id)
	end
	if #list > MAX_FRIENDS then
		lines[#lines + 1] = " "
		lines[#lines + 1] = "|cff999999" .. L["and %d more"]:format(#list - MAX_FRIENDS) .. "|r"
	end
end

local function Refresh()
	screen.Title:SetText(L["AFK"] .. "   " .. Clock(GetTime() - since))
	local className, classFile = UnitClass("player")
	local race = UnitRace("player")
	local level = UnitLevel("player") or 0
	screen.Name:SetText(ColouredName(UnitName("player"), classFile) .. "  |cffcccccc"
		.. L["Level %d %s %s"]:format(level, race or "", className or "") .. "|r")

	local info = {}
	local zone, subzone = GetZoneText(), GetSubZoneText()
	info[#info + 1] = (subzone ~= "" and subzone ~= zone) and (zone .. " - " .. subzone) or zone
	info[#info + 1] = L["Time: %s"]:format(date("%H:%M"))
	local xp, xpMax = UnitXP("player"), UnitXPMax("player")
	if not issecret(xp) and not issecret(xpMax) and (xpMax or 0) > 0 then
		local progress = L["Level progress: %d%%"]:format(math.floor(xp / xpMax * 100))
		local rested = GetXPExhaustion and GetXPExhaustion()
		if rested and not issecret(rested) and rested > 0 then
			progress = progress .. ", " .. L["rested: %d%%"]:format(math.floor(rested / xpMax * 100))
		end
		info[#info + 1] = progress
	end
	if whispers > 0 then
		info[#info + 1] = L["Whispers: %d (last from %s)"]:format(whispers, lastWhisper or "?")
	end
	for _, section in ipairs(AFK.sections) do
		local ok, lines = pcall(section)
		if ok and type(lines) == "table" then
			for _, line in ipairs(lines) do
				info[#info + 1] = line
			end
		end
	end
	if #news > 0 then
		info[#info + 1] = "|cffffd200" .. L["While you were away"] .. "|r"
		for i = math.max(1, #news - MAX_NEWS + 1), #news do
			local line = NewsLine(news[i])
			if line then
				info[#info + 1] = line
			end
		end
	end
	screen.Info:SetText(table.concat(info, "\n"))

	local friends = {}
	FriendLines(friends)
	screen.Friends:SetText(table.concat(friends, "\n"))
end

---------------------------------------------------------------------------
-- Showing and leaving
---------------------------------------------------------------------------

local function StopSpin()
	if spinning and MoveViewLeftStop then
		MoveViewLeftStop()
	end
	spinning = false
	M.db.afkSpinning = nil
end

local function Show()
	if not screen then
		Build()
	end
	shown, since, leaveNow = true, GetTime(), false
	whispers, lastWhisper = 0, nil
	wipe(news)
	ns.HideInterface("afk", true) -- Tweaks.lua (shared with cinematic flights)
	screen:SetScale(UIParent:GetScale())
	-- The two columns share what's right of the model (x 300 to the right edge, 40 margin, 20 gap):
	-- on a narrower screen (a big UI scale) they get narrower instead of running into each other.
	local room = math.max(400, (UIParent:GetWidth() or 0) - 300 - 40 - 20)
	local infoWidth = math.min(420, math.floor(room * 0.49))
	screen.Info:SetWidth(infoWidth)
	screen.Friends:SetWidth(math.min(440, room - infoWidth))
	screen.Model:SetUnit("player") -- current gear
	screen.Model:SetFacing(0.6)
	screen:Show()
	if M.db.afkSpin and MoveViewLeftStart then
		MoveViewLeftStart(SPIN_SPEED)
		spinning = true
		M.db.afkSpinning = true -- a /reload mid-spin stops it on the next start (AFK.Enable)
	end
	sincePoll, sinceRefresh = 0, 0
	Refresh()
end

-- back = the AFK flag is gone; anything else (moved, combat, click, ...) while still flagged AFK
-- keeps the screen away until the next time you go AFK.
local function Leave(back)
	shown = false
	ns.HideInterface("afk", false)
	StopSpin()
	screen:Hide()
	dismissed = not back
end

local function ShouldShow()
	return M.enabled and M.db.afkScreen and not dismissed and IsAFK() and not InCombat()
		and not UnitIsDeadOrGhost("player") and not IsPlayerMoving() and not ChatActive() and not WindowOpen()
end

-- Why to leave right now, or nil to stay.
local function LeaveReason()
	if not IsAFK() then
		return "back"
	elseif leaveNow or not (M.enabled and M.db.afkScreen) or InCombat() or IsPlayerMoving() or ChatActive()
			or WindowOpen() or UnitIsDeadOrGhost("player") then
		return "other"
	end
end

driver:SetScript("OnUpdate", function(self, elapsed)
	if checkPending then
		checkPending = false
		if not shown and ShouldShow() then
			Show()
		end
	end
	if not shown then
		self:Hide() -- nothing to do until the next PLAYER_FLAGS_CHANGED
		return
	end
	sincePoll = sincePoll + elapsed
	if sincePoll >= POLL or leaveNow then
		sincePoll = 0
		local reason = LeaveReason()
		if reason then
			Leave(reason == "back")
			self:Hide()
			return
		end
	end
	sinceRefresh = sinceRefresh + elapsed
	if sinceRefresh >= REFRESH then
		sinceRefresh = math.min(sinceRefresh - REFRESH, REFRESH) -- keeps the clock in step, no catching up
		Refresh()
	end
end)

events:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_FLAGS_CHANGED" then
		if ... ~= "player" then
			return
		end
		if not IsAFK() then
			dismissed = false -- back: the next AFK shows the screen again
		end
		checkPending = true
		driver:Show()
	elseif event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER" then
		if shown then
			whispers = whispers + 1
			local sender = select(2, ...)
			if type(sender) == "string" and not issecret(sender) then
				lastWhisper = sender:gsub("%-.*$", "") -- without the realm
			end
		end
	elseif shown then
		leaveNow = true -- combat or a popup: back on the next frame
	end
end)

-- Friends' news while away, from Beacon (its listeners run on Beacon's tick): level-ups, deaths,
-- items shown or offered, Lefthy chat lines and announcements (the notices are hidden too).
local NEWS_KINDS = { level = true, death = true, item = true, chat = true, announce = true }
local function OnFriendEvent(kind, peer, eventData)
	if shown and NEWS_KINDS[kind] then
		news[#news + 1] = { kind = kind, name = peer.name, classFile = peer.classFile, data = eventData or {} }
		while #news > MAX_NEWS do
			table.remove(news, 1)
		end
	end
end

---------------------------------------------------------------------------
-- Switched by Tweaks.lua (on the next frame after the setting or the module changes)
---------------------------------------------------------------------------

function AFK.Enable()
	events:RegisterEvent("PLAYER_FLAGS_CHANGED")
	events:RegisterEvent("CHAT_MSG_WHISPER")
	events:RegisterEvent("CHAT_MSG_BN_WHISPER")
	for _, event in ipairs(LEAVE_EVENTS) do
		pcall(events.RegisterEvent, events, event)
	end
	if not listening and ns.Beacon then
		listening = true
		table.insert(ns.Beacon.listeners, OnFriendEvent)
	end
	if M.db.afkSpinning and MoveViewLeftStop then
		MoveViewLeftStop() -- the UI was reloaded while the camera was circling
		M.db.afkSpinning = nil
	end
	dismissed = false
	checkPending = true -- maybe AFK already (switched on, or a reload)
	driver:Show()
end

function AFK.Disable()
	events:UnregisterAllEvents()
	if shown then
		Leave(false)
	end
	-- Switched off: the next time it's on, the next AFK shows it again (the event that would have
	-- cleared this, coming back from AFK, isn't listened to while off).
	dismissed, checkPending = false, false
	driver:Hide()
end

function AFK.IsShown()
	return shown
end

function ns.ApplyAFKScreen(on)
	if on then
		AFK.Enable()
	else
		AFK.Disable()
	end
end
