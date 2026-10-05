local _, ns = ...
local LT = ns.LT
local L = ns.L
local M = LT:GetModule("tweaks")
local data = ns.MirageData -- the window lists, to notice a window being opened

-- Cinematic flights (a Misc Tweak; works without Mirage): on a flight path the interface fades
-- out, thin black bars fade in like a film, and a title card names your destination and every
-- zone you fly into (its level range, and Beacon friends who are there). The top bar shows what
-- Beacon friends are doing (a line each: name, level, where, fighting or their quest; setting
-- flightFriends), the bottom bar the time left to landing; whispers and party chat show as
-- subtitles just above it. Landing brings everything back.
--
-- The screen doesn't take clicks, so the camera can be dragged as always. Opening a window (map,
-- bags, ...), typing in chat or a friend's item offer waiting for your Need or Pass (Beacon) pauses
-- the film (the interface is back at once) and it resumes by itself once that's done. Combat or a
-- popup that needs you ends it for the rest of that flight. Friends' item shares and the outcome
-- of offers come in as subtitles too (Flight.Subtitle, from Beacon's Items.lua).
--
-- Flight time: the game doesn't tell. Best first:
--   * a route flown before: its time (LefthyToolsDB.flightTimes, "From > To"), counted down exactly;
--   * its length along the real flight path: the flight's legs (GetNumRoutes / TaxiGetNodeSlot)
--     looked up in Data/FlightPaths.lua (from the client's TaxiPath / TaxiPathNode tables), at
--     ~29.9 yd/s, learned from your flights (LefthyToolsDB.flightPathPace), plus waits on the way;
--   * only if a leg isn't known: the straight distance between the two flight points (C_TaxiMap
--     node positions, C_Map.GetMapWorldSize) at a learned pace (flightPace), shown as "about".
--
-- The interface is hidden with ns.HideInterface (Tweaks.lua: UIParent's alpha, shared with the AFK
-- screen), or, with the setting flightHide on "chosen", only the chosen elements (flightGroups:
-- Mirage's groups) through Mirage's engine (Mirage:HideGroups, also with Mirage off). The
-- destination comes from a post-hook on TakeTaxiNode (both the flight map and the old taxi window
-- call it) and TaxiNodeName.
--
-- Cost: nothing on the ground. PLAYER_CONTROL_LOST (a flight starting) or PLAYER_ENTERING_WORLD
-- shows the driver, which looks for UnitOnTaxi for a few seconds and hides itself; during a
-- flight it checks 4x a second. The bars and title cards fade by animation.

local FADE = 1.5            -- seconds for the interface and the bars
local POLL = 0.25
local START_WAIT = 3        -- seconds after losing control to look for the taxi
local RESUME_DELAY = 2      -- seconds after a window closes or typing ends
local CARD_IN, CARD_HOLD, CARD_OUT = 1.2, 3.5, 1.5
local SUBTITLE_TIME, MAX_SUBTITLES = 8, 2
local BAR = 0.07            -- letterbox bar height, part of the screen height
local FRIENDS_EVERY = 2     -- seconds between updates of the friends in the top bar
local FRIENDS_PER_PAGE, FRIENDS_PAGE_TIME = 2, 8 -- more friends: pages, one after another
local PATH_PACE = 1 / 29.9  -- seconds per yard along a flight path (classic routes fly ~29.9 yd/s)
local DEFAULT_PACE = 1.15 / 30 -- seconds per yard of straight distance (the fallback) before any flight is timed
local MIN_FLIGHT, MAX_FLIGHT = 10, 1800 -- timed flights outside this are left out
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
-- flying: on a flight with the film engaged (shown, or paused for a window); dismissed: the film
-- ended for the rest of this flight (combat, a popup), only the flight's time is still taken.
local flying, shown, dismissed, leaveNow, zoneChanged, chatChanged = false, false, false, false, false, false
local lookUntil      -- after losing control: look for the taxi until then
local picked         -- from TakeTaxiNode: { name = "Sentinel Hill, Westfall", route, distance }
local trip           -- this flight: { route, distance, started, known, estimate }
local lastZone, baseline -- baseline: the fewest windows open this flight (the taxi map closes at takeoff)
local resumeAt
local takeoffAt      -- when control was lost for this flight; nil if the film didn't see the takeoff
local sincePoll, shownSecond = 0, nil
local subtitles = {} -- { text, at }
local saved -- LefthyToolsDB: flightTimes, flightPathPace, flightPace

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

-- A friend's item offer waiting for my Need or Pass: its buttons are on the interface.
local function OfferWaiting()
	local beacon = ns.Beacon
	return beacon and beacon.AwaitingAnswer and beacon.AwaitingAnswer() or false
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

local function Clock(seconds)
	seconds = math.max(0, math.floor(seconds + 0.5))
	local h, m, s = math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60
	if h > 0 then
		return ("%d:%02d:%02d"):format(h, m, s)
	end
	return ("%d:%02d"):format(m, s)
end

---------------------------------------------------------------------------
-- The route picked on the taxi map: its name, its length along the real flight path, and the
-- straight distance to it
---------------------------------------------------------------------------

-- The flight's length along its real path: its legs (GetNumRoutes / TaxiGetNodeSlot, as the old
-- taxi window draws them), each looked up in Data/FlightPaths.lua (generated from the client's
-- own flight path tables). nil if any leg isn't known.
local function PathLength(slot, nodeBySlot)
	local paths = ns.FLIGHT_PATHS
	local legs = paths and GetNumRoutes and TaxiGetNodeSlot and GetNumRoutes(slot)
	if not (type(legs) == "number" and legs > 0) then
		return nil
	end
	local yards, waits = 0, 0
	for leg = 1, legs do
		local from = nodeBySlot[TaxiGetNodeSlot(slot, leg, true)]
		local to = nodeBySlot[TaxiGetNodeSlot(slot, leg, false)]
		local path = from and to and paths[from .. ">" .. to]
		if not path then
			return nil
		end
		yards, waits = yards + path[1], waits + path[2]
	end
	return yards, waits
end

local function PickRoute(slot)
	local name = TaxiNodeName and TaxiNodeName(slot)
	if not (Readable(name) and type(name) == "string") then
		return nil
	end
	local route = { name = name }
	local ok = pcall(function()
		local mapID = GetTaxiMapID and GetTaxiMapID()
		local nodes = mapID and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes(mapID)
		local here, there
		local nodeBySlot = {}
		local current = Enum.FlightPathState and Enum.FlightPathState.Current or 0
		for _, node in ipairs(nodes or {}) do
			nodeBySlot[node.slotIndex] = node.nodeID
			if node.state == current then
				here = node
			elseif node.slotIndex == slot then
				there = node
			end
		end
		if here and Readable(here.name) then
			route.route = here.name .. " > " .. name
		end
		route.pathYards, route.pathWait = PathLength(slot, nodeBySlot)
		local width, height = C_Map.GetMapWorldSize(mapID)
		if here and there and (width or 0) > 0 and (height or 0) > 0 then
			local dx = (there.position.x - here.position.x) * width
			local dy = (there.position.y - here.position.y) * height
			route.distance = math.sqrt(dx * dx + dy * dy)
		end
	end)
	if not (ok and route.route) then
		-- Without the taxi map's nodes: from where you stand.
		route.route = (GetRealZoneText() or "?") .. "/" .. (GetSubZoneText() or "") .. " > " .. name
	end
	return route
end

-- The flight is over: its time for this route, and the paces for estimating new ones. The path
-- pace only learns from flights near it (within 25%): a route flown at another speed (some of
-- Forever's own) has its own time kept and shouldn't skew the rest.
local function RecordTrip()
	local seconds = trip and trip.route and trip.fromTakeoff and trip.started and GetTime() - trip.started
	if not (saved and seconds and seconds >= MIN_FLIGHT and seconds <= MAX_FLIGHT) then
		return
	end
	saved.flightTimes[trip.route] = math.floor(seconds + 0.5)
	if trip.pathYards and trip.pathYards > 0 then
		local pace = math.max(seconds - (trip.pathWait or 0), 1) / trip.pathYards
		local current = saved.flightPathPace or PATH_PACE
		if pace > current * 0.8 and pace < current * 1.25 then
			saved.flightPathPace = current * 0.7 + pace * 0.3
		end
	end
	if trip.distance and trip.distance > 0 then
		local pace = seconds / trip.distance
		saved.flightPace = saved.flightPace and (saved.flightPace * 0.7 + pace * 0.3) or pace
	end
end

---------------------------------------------------------------------------
-- The screen: letterbox bars, the time left, subtitles, title cards
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
	screen:EnableMouse(false) -- clicks and camera drags go through
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
	-- The time left, in the bottom bar; subtitles just above it, over the picture.
	screen.Timer = screen:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	screen.Timer:SetPoint("CENTER", screen.Bottom, "CENTER")
	screen.Timer:SetTextColor(0.85, 0.82, 0.75)
	screen.Subtitles = screen:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	screen.Subtitles:SetPoint("BOTTOM", screen.Bottom, "TOP", 0, 10)
	screen.Subtitles:SetWidth(900)
	screen.Subtitles:SetSpacing(4)
	-- What Beacon friends are doing, in the top bar: one line each.
	screen.Friends = screen:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	screen.Friends:SetPoint("CENTER", screen.Top, "CENTER")
	screen.Friends:SetJustifyH("CENTER")
	screen.Friends:SetSpacing(4)
	screen.Friends:SetWordWrap(false)
	screen.Friends:SetTextColor(0.85, 0.82, 0.75)

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

-- The top bar: Beacon friends, one line each (Beacon's own summary of them: name, level, where,
-- what they're doing), a page of FRIENDS_PER_PAGE at a time.
local friendsAt = -math.huge
local function UpdateFriends(now)
	friendsAt = now
	local beacon = LT:GetModule("beacon")
	local B = ns.Beacon
	local list = M.db.flightFriends and beacon and beacon.enabled and B and B.FriendList and B.FriendList() or {}
	if #list == 0 then
		screen.Friends:SetText("")
		return
	end
	local pages = math.ceil(#list / FRIENDS_PER_PAGE)
	local page = math.floor(now / FRIENDS_PAGE_TIME) % pages
	local lines = {}
	for i = page * FRIENDS_PER_PAGE + 1, math.min(#list, (page + 1) * FRIENDS_PER_PAGE) do
		local parts = {}
		B.FriendLines(parts, list[i].peer, list[i].id)
		lines[#lines + 1] = table.concat(parts, "   |cff888888·|r   ")
	end
	screen.Friends:SetText(table.concat(lines, "\n"))
end
Flight.UpdateFriends = UpdateFriends -- (tests)

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

-- "Landing in 1:42" (timed before, or from the flight path's length), "Landing in about 2:10"
-- (only the straight distance known), nothing if unknown (a /reload mid-flight). Set only when
-- the second changes.
local function UpdateTimer()
	local total = trip and (trip.known or trip.estimate)
	if not (total and trip.started) then
		screen.Timer:SetText("")
		return
	end
	local left = total - (GetTime() - trip.started)
	local second = math.floor(left + 0.5)
	if second == shownSecond then
		return
	end
	shownSecond = second
	if second <= 0 then
		screen.Timer:SetText(L["Landing any moment"])
	elseif trip.known or trip.pathYards then
		screen.Timer:SetText(L["Landing in %s"]:format(Clock(left)))
	else
		screen.Timer:SetText(L["Landing in about %s"]:format(Clock(left)))
	end
end

---------------------------------------------------------------------------
-- Starting, pausing and leaving
---------------------------------------------------------------------------

-- Everything (UIParent's alpha), or only the chosen elements (Mirage's groups); fade: seconds.
-- Giving back undoes whichever was used, so a setting changed meanwhile can't leave anything hidden.
local groupsHidden = false
local function HideUI(hide, fade)
	local chosen = hide and M.db.flightHide == "chosen"
	ns.HideInterface("flight", hide and not chosen, fade)
	local mirage = LT:GetModule("mirage")
	if mirage and mirage.HideGroups and (chosen or groupsHidden) then
		mirage:HideGroups("flight", chosen and M.db.flightGroups or nil, fade)
		groupsHidden = chosen
	end
end

-- The film on screen: the interface fades out, the bars in.
local function Show()
	shown, resumeAt, shownSecond = true, nil, nil
	screen:SetScale(UIParent:GetScale())
	local barHeight = math.floor(UIParent:GetHeight() * BAR + 0.5)
	screen.Top:SetHeight(barHeight)
	screen.Bottom:SetHeight(barHeight)
	screen.Friends:SetWidth(math.max(200, UIParent:GetWidth() - 80))
	screen.FadeOut:Stop()
	screen:SetAlpha(0)
	screen:Show()
	screen.FadeIn:Play()
	UpdateSubtitles()
	UpdateTimer()
	UpdateFriends(GetTime())
	HideUI(true, FADE)
end

-- The interface back at once (a window, typing): paused until that's done.
local function Pause()
	shown, resumeAt = false, nil
	screen.FadeIn:Stop()
	screen:Hide()
	card.Anim:Stop()
	card:SetAlpha(0)
	HideUI(false, 0)
end

local function Start()
	if not screen then
		Build()
	end
	flying, leaveNow, zoneChanged, chatChanged = true, false, false, false
	sincePoll, lastZone = 0, nil
	wipe(subtitles)
	baseline = Windows()
	trip = nil
	if picked then
		-- Timed from the takeoff (also when the film starts late); not kept if it didn't see it.
		trip = { route = picked.route, distance = picked.distance, pathYards = picked.pathYards,
			pathWait = picked.pathWait, started = takeoffAt or GetTime(), fromTakeoff = takeoffAt ~= nil }
		takeoffAt = nil -- (used up: a later start can't take an old takeoff)
		-- Best first: this route's own time; its length along the flight path; the straight line.
		trip.known = saved and saved.flightTimes[picked.route]
		if picked.pathYards then
			trip.estimate = picked.pathYards * (saved and saved.flightPathPace or PATH_PACE) + (picked.pathWait or 0)
		elseif picked.distance then
			trip.estimate = picked.distance * (saved and saved.flightPace or DEFAULT_PACE)
		end
	end
	Show()
	if picked then
		local place, area = picked.name:match("^(.-),%s*(.+)$")
		ShowCard(L["Next stop"], place or picked.name, area)
		picked = nil
		lastZone = GetZoneText() -- the zone you take off in gets no card of its own
	else
		ZoneCard() -- after a /reload or a loading screen mid-flight
	end
end

-- The film ends: landing fades everything back; anything else (combat, a popup, switched off)
-- brings the interface back at once, for the rest of this flight.
local function EndFilm(landed)
	local wasShown = shown
	flying, shown, leaveNow = false, false, false -- (leaveNow would keep the driver checking every frame)
	screen.FadeIn:Stop()
	if wasShown and landed then
		screen.FadeOut:Play() -- hides the screen when done
	else
		screen:Hide()
	end
	card.Anim:Stop()
	card:SetAlpha(0)
	HideUI(false, (wasShown and landed) and FADE or 0)
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
	if dismissed and trip then
		-- The film was ended: only the flight's time is still taken.
		if not OnTaxi() then
			RecordTrip()
			trip = nil
			self:Hide()
		end
		return
	end
	if flying then
		if not OnTaxi() then
			RecordTrip()
			trip = nil
			EndFilm(true)
			self:Hide()
			return
		end
		if leaveNow or not (M.enabled and M.db.cinematicFlights) or InCombat() then
			EndFilm(false)
			dismissed = true
			if not trip then
				self:Hide()
			end
			return
		end
		local now = GetTime()
		local windows = Windows()
		baseline = math.min(baseline, windows)
		local busy = ChatActive() or windows > baseline or OfferWaiting()
		if shown and busy then
			Pause()
		elseif not shown then
			if busy then
				resumeAt = nil
			elseif not resumeAt then
				resumeAt = now + RESUME_DELAY
			elseif now >= resumeAt then
				Show()
			end
		end
		if not shown then
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
		UpdateTimer()
		if now - friendsAt >= FRIENDS_EVERY then
			UpdateFriends(now)
		end
		return
	end
	if ShouldStart() then
		Start()
	elseif M.enabled and M.db.cinematicFlights and not dismissed and not InCombat() and OnTaxi() then
		-- In the air, but typing in chat: keep looking (4x a second) and start once that's done.
	elseif not lookUntil or GetTime() > lookUntil then
		lookUntil = nil
		self:Hide() -- on the ground: nothing to do until the next flight
	end
end)

local function Look()
	lookUntil = GetTime() + START_WAIT
	driver:Show()
end

-- The newest few lines, each for SUBTITLE_TIME seconds; drawn on the next check.
local function AddSubtitle(text)
	subtitles[#subtitles + 1] = { text = text, at = GetTime() }
	while #subtitles > MAX_SUBTITLES do
		table.remove(subtitles, 1)
	end
	chatChanged = true
end

-- Other parts' news while the interface is hidden (Beacon: a friend's item share, an offer's
-- outcome). True if it's shown, i.e. on a flight with the film.
function Flight.Subtitle(text)
	if not flying or not Readable(text) then
		return false
	end
	AddSubtitle(text)
	return true
end

events:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_CONTROL_LOST" then
		dismissed, trip = false, nil -- a new flight
		takeoffAt = GetTime() -- (the film may start later: typing in chat at takeoff)
		Look()
	elseif event == "PLAYER_CONTROL_GAINED" then
		if flying or trip then
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
			AddSubtitle(CHAT_COLOURS[event] .. "[" .. sender .. "]|r " .. text)
		end
	elseif flying then
		leaveNow = true -- combat or a popup: back on the next check
	end
end)

if type(TakeTaxiNode) == "function" then
	hooksecurefunc("TakeTaxiNode", function(slot)
		picked = PickRoute(slot)
	end)
end

table.insert(LT.onLoad, function(db)
	db.flightTimes = type(db.flightTimes) == "table" and db.flightTimes or {}
	for _, key in ipairs({ "flightPace", "flightPathPace" }) do
		if type(db[key]) ~= "number" then
			db[key] = nil
		end
	end
	saved = db
end)

---------------------------------------------------------------------------
-- Switched by Tweaks.lua (on the next frame after the setting or the module changes)
---------------------------------------------------------------------------

-- The first version moved the camera; one left circling or zoomed out (a /reload mid-flight) is
-- put back once, and its settings go.
local function CleanUpCamera()
	local db = M.db
	if db.flightOrbit and MoveViewLeftStop then
		MoveViewLeftStop()
	end
	local zoom = GetCameraZoom and GetCameraZoom()
	if db.flightZoom and Readable(zoom) and CameraZoomIn and zoom > db.flightZoom then
		CameraZoomIn(zoom - db.flightZoom)
	end
	if db.flightMaxZoom and SetCVar then
		SetCVar("cameraDistanceMaxZoomFactor", db.flightMaxZoom)
	end
	db.flightOrbit, db.flightZoom, db.flightMaxZoom, db.flightCamera = nil, nil, nil, nil
end

function Flight.Enable()
	for _, event in ipairs({ "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_ENTERING_WORLD",
			"ZONE_CHANGED_NEW_AREA", "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_PARTY",
			"CHAT_MSG_PARTY_LEADER" }) do
		events:RegisterEvent(event)
	end
	for _, event in ipairs(LEAVE_EVENTS) do
		pcall(events.RegisterEvent, events, event)
	end
	CleanUpCamera()
	dismissed = false
	Look() -- maybe on a flight already (switched on, or a reload)
end

function Flight.Disable()
	events:UnregisterAllEvents()
	if flying then
		EndFilm(false)
	end
	dismissed, lookUntil, trip, takeoffAt = false, nil, nil, nil
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
