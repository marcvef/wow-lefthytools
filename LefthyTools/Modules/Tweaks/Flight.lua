local _, ns = ...
local LT = ns.LT
local L = ns.L
local M = LT:GetModule("tweaks")
local data = ns.MirageData -- the window lists, to notice a window being opened

-- Cinematic flights (a Misc Tweak; works without Mirage): on a flight path the interface fades
-- out, black bars slide in like a film, the camera pulls back and slowly circles, and a title card
-- names your destination and every zone you fly into (its level range, and Beacon friends who are
-- there). Whispers and party chat show as subtitles in the lower bar. Landing brings everything
-- back; so do a click, opening a window (map, bags, ...), typing in chat, combat or a popup that
-- needs you, for the rest of that flight.
--
-- The interface is hidden with ns.HideInterface (Tweaks.lua: UIParent's alpha, shared with the AFK
-- screen). The destination comes from a post-hook on TakeTaxiNode (both the flight map and the old
-- taxi window call it) and TaxiNodeName.
--
-- Cost: nothing on the ground. PLAYER_CONTROL_LOST (a flight starting) or PLAYER_ENTERING_WORLD
-- shows the driver, which looks for UnitOnTaxi for a few seconds and hides itself; during a
-- flight it checks 4x a second whether to leave. The bars and title cards fade by animation.

local FADE = 1.5            -- seconds for the interface and the bars
local POLL = 0.25
local START_WAIT = 3        -- seconds after losing control to look for the taxi
local PULL_BACK = 12        -- yards the camera moves out
local ORBIT_SPEED = 0.015   -- MoveViewLeftStart speed: slower than the AFK screen's
local CARD_IN, CARD_HOLD, CARD_OUT = 1.2, 3.5, 1.5
local SUBTITLE_TIME, MAX_SUBTITLES = 8, 2
local BAR = 0.11            -- letterbox bar height, part of the screen height
local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local CHAT_COLOURS = {
	CHAT_MSG_WHISPER = "|cffff80ff", CHAT_MSG_BN_WHISPER = "|cff00faf6",
	CHAT_MSG_PARTY = "|cffaaaaff", CHAT_MSG_PARTY_LEADER = "|cff76c8ff",
}
local LEAVE_EVENTS = {      -- things that need the interface right away
	"PLAYER_REGEN_DISABLED", "READY_CHECK", "PARTY_INVITE_REQUEST", "LFG_PROPOSAL_SHOW", "DUEL_REQUESTED",
	"CONFIRM_SUMMON", "CINEMATIC_START", "PLAY_MOVIE",
}

local Flight = {}
ns.CinematicFlight = Flight

local screen, card -- built on first use
local driver = CreateFrame("Frame")
driver:Hide()
Flight.driver = driver
local events = CreateFrame("Frame")
local flying, dismissed, leaveNow, zoneChanged, chatChanged = false, false, false, false, false
local lookUntil      -- after losing control: look for the taxi until then
local destination    -- "Sentinel Hill, Westfall", from TakeTaxiNode
local lastZone, windowsAtStart
local sincePoll = 0
local subtitles = {} -- { text, at }
local savedZoom, orbiting

local function Readable(value)
	return value ~= nil and not (issecretvalue and issecretvalue(value))
end

local function OnTaxi()
	local onTaxi = UnitOnTaxi("player")
	return Readable(onTaxi) and onTaxi == true
end

local function InCombat()
	return InCombatLockdown() or UnitAffectingCombat("player")
end

local function ChatActive()
	return ACTIVE_CHAT_EDIT_BOX ~= nil or (GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() ~= nil)
end

-- How many windows are open (the taxi map closing as you take off is fine; one opening isn't).
local function Windows()
	local count = 0
	if GetUIPanel then
		for _, area in ipairs(data.PANEL_AREAS) do
			if GetUIPanel(area) then
				count = count + 1
			end
		end
	end
	if IsAnyBagOpen and IsAnyBagOpen() then
		count = count + 1
	end
	for _, name in ipairs(data.WINDOWS) do
		local f = _G[name]
		if type(f) == "table" and f.IsShown and f:IsShown() then
			count = count + 1
		end
	end
	return count
end

---------------------------------------------------------------------------
-- The screen: letterbox bars, subtitles, title cards
---------------------------------------------------------------------------

local function Fade(region, from, to, duration)
	local group = region:CreateAnimationGroup()
	local alpha = group:CreateAnimation("Alpha")
	alpha:SetFromAlpha(from)
	alpha:SetToAlpha(to)
	alpha:SetDuration(duration)
	group:SetToFinalAlpha(true)
	return group
end

local function Build()
	screen = CreateFrame("Frame", "LefthyToolsFlightFrame") -- no parent: stays while UIParent is invisible
	screen:SetFrameStrata("FULLSCREEN")
	screen:SetAllPoints(UIParent)
	screen:SetScript("OnMouseDown", function()
		leaveNow = true -- the interface comes back on the next frame, not inside the click
	end)
	screen:Hide()
	screen.Top = screen:CreateTexture(nil, "BACKGROUND")
	screen.Top:SetPoint("TOPLEFT")
	screen.Top:SetPoint("TOPRIGHT")
	screen.Top:SetColorTexture(0, 0, 0, 1)
	screen.Bottom = screen:CreateTexture(nil, "BACKGROUND")
	screen.Bottom:SetPoint("BOTTOMLEFT")
	screen.Bottom:SetPoint("BOTTOMRIGHT")
	screen.Bottom:SetColorTexture(0, 0, 0, 1)
	screen.FadeIn = Fade(screen, 0, 1, FADE)
	screen.FadeOut = Fade(screen, 1, 0, FADE)
	screen.FadeOut:SetScript("OnFinished", function()
		if not flying then
			screen:Hide()
		end
	end)
	screen.Subtitles = screen:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	screen.Subtitles:SetPoint("CENTER", screen.Bottom, "CENTER")
	screen.Subtitles:SetWidth(900)
	screen.Subtitles:SetSpacing(4)

	-- The title card, in the upper middle: a small header, the name in the quest font, a thin
	-- gold line and a subtitle. It fades in, holds, fades out, drifting slightly closer.
	card = CreateFrame("Frame", nil, screen)
	screen.Card = card
	card:SetSize(900, 170)
	card:SetPoint("CENTER", 0, 150)
	card:SetAlpha(0)
	card.Header = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	card.Header:SetPoint("TOP")
	card.Header:SetTextColor(0.85, 0.75, 0.55)
	card.Title = card:CreateFontString(nil, "OVERLAY")
	card.Title:SetFont(TITLE_FONT, 46, "")
	card.Title:SetShadowOffset(2, -2)
	card.Title:SetShadowColor(0, 0, 0, 1)
	card.Title:SetTextColor(1, 0.92, 0.75)
	card.Title:SetPoint("TOP", card.Header, "BOTTOM", 0, -6)
	card.Line = card:CreateTexture(nil, "ARTWORK")
	card.Line:SetColorTexture(1, 0.82, 0.4, 0.8)
	card.Line:SetSize(280, 1)
	card.Line:SetPoint("TOP", card.Title, "BOTTOM", 0, -8)
	card.Sub = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	card.Sub:SetPoint("TOP", card.Line, "BOTTOM", 0, -8)
	card.Anim = card:CreateAnimationGroup()
	local fadeIn = card.Anim:CreateAnimation("Alpha")
	fadeIn:SetFromAlpha(0)
	fadeIn:SetToAlpha(1)
	fadeIn:SetDuration(CARD_IN)
	local fadeOut = card.Anim:CreateAnimation("Alpha")
	fadeOut:SetFromAlpha(1)
	fadeOut:SetToAlpha(0)
	fadeOut:SetStartDelay(CARD_IN + CARD_HOLD)
	fadeOut:SetDuration(CARD_OUT)
	local drift = card.Anim:CreateAnimation("Scale")
	drift:SetScaleFrom(0.96, 0.96)
	drift:SetScaleTo(1.04, 1.04)
	drift:SetDuration(CARD_IN + CARD_HOLD + CARD_OUT)
	card.Anim:SetToFinalAlpha(true)
end

local function ShowCard(header, title, sub)
	card.Header:SetText(header or "")
	card.Title:SetText(title or "")
	card.Sub:SetText(sub or "")
	card.Anim:Stop()
	card.Anim:Play()
end

-- The continent above a zone ("Eastern Kingdoms"), for the card's header.
local function Continent(mapID)
	local continentType = Enum.UIMapType and Enum.UIMapType.Continent or 2
	for _ = 1, 5 do
		local info = mapID and C_Map.GetMapInfo(mapID)
		if not info then
			return nil
		end
		if info.mapType == continentType then
			return info.name
		end
		mapID = info.parentMapID
	end
end

-- "Anna is here" / "Anna, Bob are here": Beacon friends in that zone.
local function FriendsHere(zone)
	local beacon = LT:GetModule("beacon")
	local B = ns.Beacon
	if not (beacon and beacon.enabled and B and B.FriendList) then
		return nil
	end
	local names = {}
	for _, item in ipairs(B.FriendList()) do
		local info = C_BattleNet.GetGameAccountInfoByID(item.id)
		local area = info and info.areaName or item.peer.area
		if Readable(area) and area == zone then
			names[#names + 1] = LT.Window.ClassColorCode(item.peer.classFile) .. item.peer.name .. "|r"
		end
	end
	if #names == 1 then
		return L["%s is here"]:format(names[1])
	elseif #names > 1 then
		return L["%s are here"]:format(table.concat(names, ", "))
	end
end

local function ZoneCard()
	local zone = GetZoneText()
	if not Readable(zone) or zone == "" or zone == lastZone then
		return
	end
	lastZone = zone
	local mapID = C_Map.GetBestMapForUnit("player")
	local parts = {}
	local ok, minLevel, maxLevel = pcall(C_Map.GetMapLevels, mapID)
	if ok and mapID and (minLevel or 0) > 0 and (maxLevel or 0) > 0 then
		parts[#parts + 1] = minLevel == maxLevel and L["Level %d"]:format(minLevel) or L["Levels %d-%d"]:format(minLevel, maxLevel)
	end
	parts[#parts + 1] = FriendsHere(zone)
	ShowCard(Continent(mapID), zone, table.concat(parts, "   |cff888888·|r   "))
end

local function UpdateSubtitles()
	local now = GetTime()
	while subtitles[1] and now - subtitles[1].at > SUBTITLE_TIME do
		table.remove(subtitles, 1)
	end
	local lines = {}
	for i = math.max(1, #subtitles - MAX_SUBTITLES + 1), #subtitles do
		lines[#lines + 1] = subtitles[i].text
	end
	screen.Subtitles:SetText(table.concat(lines, "\n"))
end

---------------------------------------------------------------------------
-- The camera: pulled back and circling, put back on landing (also after a /reload mid-flight)
---------------------------------------------------------------------------

local function CameraStart()
	if not M.db.flightCamera then
		return
	end
	local zoom = GetCameraZoom and GetCameraZoom()
	if not savedZoom and Readable(zoom) and CameraZoomOut then -- (after a /reload mid-flight it's out already)
		savedZoom = zoom
		M.db.flightZoom = zoom
		CameraZoomOut(PULL_BACK)
	end
	if MoveViewLeftStart then
		MoveViewLeftStart(ORBIT_SPEED)
		orbiting = true
		M.db.flightOrbit = true
	end
end

local function CameraStop()
	if orbiting and MoveViewLeftStop then
		MoveViewLeftStop()
	end
	orbiting, M.db.flightOrbit = false, nil
	local zoom = GetCameraZoom and GetCameraZoom()
	if savedZoom and Readable(zoom) and CameraZoomIn and zoom > savedZoom then
		CameraZoomIn(zoom - savedZoom)
	end
	savedZoom, M.db.flightZoom = nil, nil
end

---------------------------------------------------------------------------
-- Starting and leaving
---------------------------------------------------------------------------

local function Start()
	if not screen then
		Build()
	end
	flying, leaveNow, zoneChanged, chatChanged = true, false, false, false
	sincePoll, lastZone = 0, nil
	wipe(subtitles)
	windowsAtStart = Windows()
	screen:SetScale(UIParent:GetScale())
	local barHeight = math.floor(UIParent:GetHeight() * BAR + 0.5)
	screen.Top:SetHeight(barHeight)
	screen.Bottom:SetHeight(barHeight)
	screen:EnableMouse(true) -- nothing invisible underneath gets clicked by accident
	screen.FadeOut:Stop()
	screen:SetAlpha(0)
	screen:Show()
	screen.FadeIn:Play()
	UpdateSubtitles()
	ns.HideInterface("flight", true, FADE)
	CameraStart()
	if destination then
		local place, area = destination:match("^(.-),%s*(.+)$")
		ShowCard(L["Next stop"], place or destination, area)
		destination = nil
		lastZone = GetZoneText() -- the zone you take off in gets no card of its own
	else
		ZoneCard() -- after a /reload or a loading screen mid-flight
	end
end

-- landed: the flight is over; anything else (a click, a window, ...) keeps the interface for the
-- rest of this flight.
local function Leave(landed)
	flying, dismissed = false, not landed
	screen:EnableMouse(false)
	screen.FadeIn:Stop()
	if landed then
		screen.FadeOut:Play() -- hides the screen when done
	else
		screen:Hide()
	end
	card.Anim:Stop()
	card:SetAlpha(0)
	ns.HideInterface("flight", false, landed and FADE or 0)
	CameraStop()
end

local function ShouldStart()
	return M.enabled and M.db.cinematicFlights and not dismissed and OnTaxi() and not InCombat() and not ChatActive()
end

driver:SetScript("OnUpdate", function(self, elapsed)
	sincePoll = sincePoll + elapsed
	if sincePoll < POLL and not leaveNow then
		return
	end
	sincePoll = 0
	if flying then
		if not OnTaxi() then
			Leave(true)
			self:Hide()
			return
		end
		windowsAtStart = math.min(windowsAtStart, Windows())
		if leaveNow or not (M.enabled and M.db.cinematicFlights) or InCombat() or ChatActive()
				or Windows() > windowsAtStart then
			Leave(false)
			self:Hide()
			return
		end
		if zoneChanged then
			zoneChanged = false
			ZoneCard()
		end
		if chatChanged or subtitles[1] then
			chatChanged = false
			UpdateSubtitles()
		end
		return
	end
	if ShouldStart() then
		Start()
	elseif not lookUntil or GetTime() > lookUntil then
		lookUntil = nil
		self:Hide() -- on the ground: nothing to do until the next flight
	end
end)

local function Look()
	lookUntil = GetTime() + START_WAIT
	driver:Show()
end

events:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_CONTROL_LOST" then
		dismissed = false -- a new flight
		Look()
	elseif event == "PLAYER_CONTROL_GAINED" then
		dismissed = false
		if flying then
			driver:Show() -- landed: the driver notices on its next check
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		Look() -- a /reload, or a loading screen mid-flight
	elseif event == "ZONE_CHANGED_NEW_AREA" then
		zoneChanged = flying
	elseif CHAT_COLOURS[event] then
		local text, sender = ...
		if flying and Readable(text) and Readable(sender) then
			if event ~= "CHAT_MSG_BN_WHISPER" then
				sender = sender:gsub("%-.*$", "") -- without the realm
			end
			subtitles[#subtitles + 1] = { text = CHAT_COLOURS[event] .. "[" .. sender .. "]|r " .. text, at = GetTime() }
			while #subtitles > MAX_SUBTITLES do
				table.remove(subtitles, 1)
			end
			chatChanged = true
		end
	elseif flying then
		leaveNow = true -- combat or a popup: back on the next check
	end
end)

if type(TakeTaxiNode) == "function" then
	hooksecurefunc("TakeTaxiNode", function(slot)
		local name = TaxiNodeName and TaxiNodeName(slot)
		destination = Readable(name) and type(name) == "string" and name or nil
	end)
end

---------------------------------------------------------------------------
-- Switched by Tweaks.lua (on the next frame after the setting or the module changes)
---------------------------------------------------------------------------

function Flight.Enable()
	for _, event in ipairs({ "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_ENTERING_WORLD",
			"ZONE_CHANGED_NEW_AREA", "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_PARTY",
			"CHAT_MSG_PARTY_LEADER" }) do
		events:RegisterEvent(event)
	end
	for _, event in ipairs(LEAVE_EVENTS) do
		pcall(events.RegisterEvent, events, event)
	end
	-- The UI was reloaded mid-flight: the camera is still circling and pulled back.
	if M.db.flightOrbit and MoveViewLeftStop then
		MoveViewLeftStop()
	end
	M.db.flightOrbit = nil
	if M.db.flightZoom then
		savedZoom = M.db.flightZoom -- the zoom from before that flight: put back when it ends
		if not OnTaxi() then
			CameraStop()
		end
	end
	dismissed = false
	Look() -- maybe on a flight already (switched on, or a reload)
end

function Flight.Disable()
	events:UnregisterAllEvents()
	if flying then
		Leave(false)
	end
	dismissed, lookUntil = false, nil
	driver:Hide()
end

function Flight.IsFlying()
	return flying
end

function ns.ApplyCinematicFlights(on)
	if on then
		Flight.Enable()
	else
		Flight.Disable()
	end
end
