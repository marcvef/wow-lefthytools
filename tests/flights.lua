-- Misc Tweaks: cinematic flights.
-- Needs: no other file (it greets Anna and Bob itself).
local suite = ...
local check, a, section, ns, LT, lefthy = suite.check, suite.a, suite.section, suite.ns, suite.LT, suite.lefthy
local anna = suite.anna
local Mirage = LT:GetModule("mirage")
local BB = ns.Beacon

section("Misc Tweaks: cinematic flights")
do
	local TDB = LefthyToolsDB.settings.tweaks
	check(TDB.cinematicFlights == true and REGISTERED_SETTINGS.LefthyTools_tweaks_cinematicFlights
		and not REGISTERED_SETTINGS.LefthyTools_tweaks_flightCamera, "on by default, with a checkbox (no camera option)")
	local uiW, uiH = UIParent:GetWidth(), UIParent:GetHeight()
	UIParent:SetSize(1920, 1080)
	anna("H2") -- friends online, in Elwynn Forest (whatever earlier tests took long enough to forget)
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "H2", "WHISPER", 12)
	anna("O2;h;1") -- (Anna can be watched, Bob not)
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "O2;h;0", "WHISPER", 12)
	Advance(0.2)
	-- The flight map: where you are (state 0) and the destination, 1118 yd apart in a straight line.
	TAXI_MAP_NODES = {
		{ name = "Stormwind, Elwynn", state = 0, slotIndex = 1, position = CreateVector2D(0.5, 0.5) },
		{ name = "Sentinel Hill, Westfall", state = 1, slotIndex = 3, position = CreateVector2D(0.45, 0.6) },
	}
	TAXI_NODES[3] = "Sentinel Hill, Westfall"
	local route = "Stormwind, Elwynn > Sentinel Hill, Westfall"
	LefthyToolsDB.flightTimes[route], LefthyToolsDB.flightPace = nil, nil
	TakeTaxiNode(3) -- picked on the flight map
	ZONE, CAMERA.zoom, CAMERA.spinning = "Stormwind City", 10, false
	Fire("PLAYER_CONTROL_LOST") -- a stun, say: no taxi
	Advance(0.5)
	check(UIParent:GetAlpha() == 1 and not (LefthyToolsFlightFrame and LefthyToolsFlightFrame:IsShown()), "losing control without a flight: nothing")
	Advance(3)
	TRAVEL.taxi = true
	Fire("PLAYER_CONTROL_LOST")
	Advance(0.3)
	local film = LefthyToolsFlightFrame
	check(film and film:IsShown() and not film._mouseEnabled and film.Top.height == 76 and film.Bottom.height == 76,
		"on the flight: black bars top and bottom (7% of the screen, room for friends' lines); clicks and camera drags go through")
	check(film.Timer:GetText() == "Landing in about 0:43",
		"a first flight on this route: the time left, estimated from the distance, got " .. tostring(film.Timer:GetText()))
	check(BB.StreamIsWatching(11) and not BB.StreamIsWatching(12) and film.FriendColumns[1].Watch.Text:GetText() == "Live",
		"takeoff: the stream of a friend who can be watched opens (Live in the top bar)")
	local alphaMidway = UIParent:GetAlpha()
	check(alphaMidway > 0 and alphaMidway < 1, "the interface fades out, got " .. alphaMidway)
	Advance(1.5)
	check(UIParent:GetAlpha() == 0, "... and is gone")
	local card = film.Card
	check(card and card.Title:GetText() == "Sentinel Hill" and card.Sub:GetText() == "Westfall" and card.Header:GetText() == "Next stop"
		and card.Title.fontFile == "Fonts\\MORPHEUS.TTF" and card.Anim.plays == 1, "a title card: the destination")
	check(CAMERA.zoom == 10 and not CAMERA.spinning, "the camera is left alone")
	-- A zone on the way, with its level range and a friend who is there.
	ZONE = "Elwynn Forest"
	Fire("ZONE_CHANGED_NEW_AREA")
	Advance(0.3)
	check(card.Title:GetText() == "Elwynn Forest" and card.Header:GetText() == "Eastern Kingdoms"
		and card.Sub:GetText():find("Levels 1-10", 1, true) and card.Sub:GetText():find("Anna|r, |cffc79c6eBob|r are here", 1, true)
		and card.Anim.plays == 2,
		"each new zone gets a card: continent, levels, friends there, got " .. tostring(card.Sub:GetText()))
	Fire("ZONE_CHANGED_NEW_AREA") -- same zone again
	Advance(0.3)
	check(card.Anim.plays == 2, "the same zone again: no new card")
	-- Whispers and party chat as subtitles.
	Fire("CHAT_MSG_WHISPER", "where are you?", "Bob-Realmy")
	Fire("CHAT_MSG_PARTY", "pull in 5", "Anna")
	Advance(0.3)
	check(film.Subtitles:GetText() == "|cffff80ff[Bob]|r where are you?\n|cffaaaaff[Anna]|r pull in 5", "subtitles, got " .. tostring(film.Subtitles:GetText()))
	check(film.Timer:GetText() == "Landing in about 0:40", "the time left counts down, got " .. tostring(film.Timer:GetText()))
	Advance(8)
	check(film.Subtitles:GetText() == "", "subtitles fade after a few seconds")
	Advance(35)
	check(film.Timer:GetText() == "Landing any moment", "past the estimate: any moment")
	-- Landing: everything back, and this route's time is kept.
	TRAVEL.taxi = false
	Fire("PLAYER_CONTROL_GAINED")
	Advance(0.3)
	local took = LefthyToolsDB.flightTimes[route]
	check(took and took >= 44 and took <= 48 and LefthyToolsDB.flightPace
		and math.abs(LefthyToolsDB.flightPace - took / 1118.03) < 0.001,
		"landed: the flight's time is kept for the route, the pace learned, got " .. tostring(took) .. ", pace " .. tostring(LefthyToolsDB.flightPace))
	check(not BB.StreamIsWatching(11), "landed: the flight's stream closes")
	Advance(1.5)
	check(UIParent:GetAlpha() == 1, "and the interface fades back in")
	film.FadeOut:Finish()
	check(not film:IsShown(), "the bars fade away")
	check(not ns.CinematicFlight.driver:IsShown(), "on the ground nothing runs")
	-- The same route again: counted down exactly. Opening the map pauses the film; closing it brings it back.
	TakeTaxiNode(3)
	TRAVEL.taxi = true
	Fire("PLAYER_CONTROL_LOST")
	Advance(2)
	check(film:IsShown() and UIParent:GetAlpha() == 0, "the next flight")
	do -- The top bar: friends side by side, three lines each that keep their place.
		local anna, bob = film.FriendColumns[1], film.FriendColumns[2]
		local function y(line) return line._points and line._points[1] and line._points[1][5] end
		local function x(line) return line._points and line._points[1] and line._points[1][4] end
		check(anna.Who:GetText():find("Anna", 1, true) and anna.Who:GetText():find("Level 20", 1, true)
			and bob.Who:GetText():find("Bob", 1, true) and x(anna.Who) < 0 and x(bob.Who) > 0,
			"the top bar: my Beacon friends side by side, name, level and where first, got " .. anna.Who:GetText())
		check(y(anna.Who) > 0 and y(anna.Quest) == 0 and y(anna.Fight) < 0, "three lines: who and where, quest, fighting")
		local fadeIns = anna.FightIn.plays
		Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "T2;176;0;Wanted: Hogger;Hogger slain: 0/1", "WHISPER", 11)
		Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;C;0;260.0;750.0;Goldshire;Hogger", "WHISPER", 11)
		ns.CinematicFlight.UpdateFriends(GetTime())
		check(anna.Quest:GetText():find("Quest: Wanted: Hogger", 1, true) and anna.Fight:GetText():find("Fighting Hogger", 1, true)
			and anna.FightIn.plays == fadeIns + 1 and anna.Fight:GetAlpha() == 1 and y(anna.Who) > 0 and y(anna.Quest) == 0,
			"her quest on its own line; a fight fades in on the third, nothing else moves, got " .. tostring(anna.Fight:GetText()))
		ns.CinematicFlight.UpdateFriends(GetTime())
		check(anna.FightIn.plays == fadeIns + 1, "still fighting: no new fade")
		Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;260.0;750.0;Goldshire;", "WHISPER", 11)
		ns.CinematicFlight.UpdateFriends(GetTime())
		check(anna.FightOut.plays == 1 and anna.Fight:GetAlpha() == 0 and anna.Fight:GetText():find("Fighting Hogger", 1, true),
			"the fight over: the line fades out (its words stay while it does)")
		-- Right of a friend's name: their fight stream, Watch / Live (none for Bob: he can't be watched).
		BB.Stream.StopWatching("")
		ns.CinematicFlight.UpdateFriends(GetTime())
		check(anna.Watch:IsShown() and anna.Watch.Text:GetText() == "Watch" and not bob.Watch:IsShown()
			and anna.Watch._points[1][4] > x(anna.Who), "Watch right of her name; Bob can't be watched: no button")
		anna.Watch:Click()
		check(BB.StreamIsWatching(11) and anna.Watch.Text:GetText() == "Live", "clicked: her stream opens, the button says Live")
		anna.Watch:Click()
		check(not BB.StreamIsWatching(11) and anna.Watch.Text:GetText() == "Watch", "clicked again: closed")
		-- Five friends: three in the top bar, two in the bottom one, the time left then at its right end.
		local realList, realRows = BB.FriendList, BB.FriendRows
		BB.FriendList = function()
			local list = {}
			for i = 1, 5 do list[i] = { id = 900 + i, peer = { name = "F" .. i, classFile = "MAGE" } } end
			return list
		end
		BB.FriendRows = function(peer) return peer.name, "", nil end
		ns.CinematicFlight.UpdateFriends(GetTime())
		local columns = film.FriendColumns
		local function bar(i) return columns[i].Who._points[1][2] end
		check(#columns == 6 and bar(1) == film.Top and bar(3) == film.Top and bar(4) == film.Bottom and bar(5) == film.Bottom
			and columns[5].Who:GetText() == "F5" and columns[6].Who:GetText() == "" and film.Timer._points[1][1] == "RIGHT",
			"five friends: three on top, two in the bottom bar, the time left at its right end")
		BB.FriendList, BB.FriendRows = realList, realRows
		ns.CinematicFlight.UpdateFriends(GetTime())
		check(film.Timer._points[1][1] == "CENTER", "two again: all on top, the time left back in the middle")
		LefthyToolsDB.settings.beacon.streamFlights = false
		ns.CinematicFlight.UpdateFriends(GetTime())
		check(not anna.Watch:IsShown(), "streams on flights off: no buttons")
		LefthyToolsDB.settings.beacon.streamFlights = true
		LefthyToolsDB.settings.tweaks.flightFriends = false
		ns.CinematicFlight.UpdateFriends(GetTime())
		check(anna.Who:GetText() == "" and anna.Quest:GetText() == "" and bob.Who:GetText() == "" and not anna.Watch:IsShown(),
			"setting off: the top bar stays black")
		LefthyToolsDB.settings.tweaks.flightFriends = true
	end
	check(film.Timer:GetText() == ("Landing in 0:%02d"):format(took - 2), "the same route: an exact countdown, got " .. tostring(film.Timer:GetText()))
	OpenWorldMap(1429)
	Advance(0.3)
	check(not film:IsShown() and UIParent:GetAlpha() == 1, "opening the map: the interface is back at once")
	Advance(3)
	check(not film:IsShown(), "while it's open the film waits")
	WorldMapFrame:Hide()
	Advance(1)
	check(not film:IsShown(), "just closed: not yet")
	Advance(1.5)
	check(film:IsShown(), "a moment later the film is back")
	Advance(1.5)
	check(UIParent:GetAlpha() == 0, "... the interface faded out again")
	-- The settings panel and LefthyTools' own windows (Chronicle, what's new, ...) count too.
	SettingsPanel:Show()
	Advance(0.3)
	check(not film:IsShown() and UIParent:GetAlpha() == 1, "the settings panel: the interface is back")
	Advance(3)
	check(not film:IsShown(), "and the film waits while it's open")
	SettingsPanel:Hide()
	Advance(2.5)
	check(film:IsShown(), "settings closed: the film again")
	SlashCmdList.LEFTHYTOOLS_CHRONICLE("")
	Advance(0.3)
	check(LefthyToolsChronicleFrame:IsShown() and not film:IsShown() and UIParent:GetAlpha() == 1, "the Chronicle window: the interface is back")
	Advance(3)
	check(not film:IsShown(), "and the film waits while it's open")
	LefthyToolsChronicleFrame:Hide()
	Advance(2.5)
	check(film:IsShown(), "Chronicle closed: the film again")
	-- Typing in chat pauses it the same way.
	ACTIVE_CHAT_EDIT_BOX = {}
	Advance(0.3)
	check(not film:IsShown() and UIParent:GetAlpha() == 1, "typing: the interface is back")
	ACTIVE_CHAT_EDIT_BOX = nil
	Advance(2.5)
	check(film:IsShown(), "done typing: the film again")
	-- A popup that needs you ends it for this flight; the flight is still timed.
	Fire("READY_CHECK")
	Advance(0.05)
	check(not film:IsShown() and UIParent:GetAlpha() == 1, "a ready check: everything back at once")
	Advance(4)
	check(not film:IsShown(), "and it stays back for this flight")
	local taxiChecks, onTaxi = 0, UnitOnTaxi
	UnitOnTaxi = function(...) taxiChecks = taxiChecks + 1; return onTaxi(...) end
	Advance(1)
	UnitOnTaxi = onTaxi
	check(taxiChecks <= 8, "ended for this flight: the driver checks a few times a second, not every frame, got " .. taxiChecks)
	Advance(8.4) -- (36 s in the air, with the windows above)
	TRAVEL.taxi = false
	Fire("PLAYER_CONTROL_GAINED")
	Advance(0.5)
	check(math.abs(LefthyToolsDB.flightTimes[route] - 36) <= 2 and not ns.CinematicFlight.driver:IsShown(),
		"landed: that flight's time is kept too, got " .. tostring(LefthyToolsDB.flightTimes[route]))
	-- With the flight path data (Data/FlightPaths.lua, the client's own paths): a route's real
	-- length, all its legs, at ~29.9 yd/s. Real node IDs: Undercity 11, Tarren Mill 13, Hammerfall 17.
	TAXI_MAP_NODES = {
		{ name = "Undercity, Tirisfal", state = 0, slotIndex = 1, nodeID = 11, position = CreateVector2D(0.5, 0.5) },
		{ name = "Tarren Mill, Hillsbrad", state = 1, slotIndex = 3, nodeID = 13, position = CreateVector2D(0.55, 0.6) },
		{ name = "Hammerfall, Arathi", state = 1, slotIndex = 4, nodeID = 17, position = CreateVector2D(0.6, 0.7) },
	}
	TAXI_NODES[3], TAXI_NODES[4] = "Tarren Mill, Hillsbrad", "Hammerfall, Arathi"
	TAXI_ROUTES = { [3] = { { 1, 3 } }, [4] = { { 1, 3 }, { 3, 4 } } }
	LefthyToolsDB.flightPathPace = nil
	TakeTaxiNode(4) -- two legs: Undercity > Tarren Mill > Hammerfall, 4222 + 3532 yd
	TRAVEL.taxi = true
	Fire("PLAYER_CONTROL_LOST")
	Advance(0.3)
	check(film.Timer:GetText() == "Landing in 4:19", "a route never flown: its real length, all legs, no \"about\", got " .. tostring(film.Timer:GetText()))
	Advance(270)
	TRAVEL.taxi = false
	Fire("PLAYER_CONTROL_GAINED")
	Advance(0.5)
	check(LefthyToolsDB.flightPathPace and math.abs(LefthyToolsDB.flightPathPace - (0.7 / 29.9 + 0.3 * 271 / 7754)) < 0.0005,
		"landed a bit later: the pace learns from it, got " .. tostring(LefthyToolsDB.flightPathPace))
	-- A route flown at another speed (some of Forever's own) keeps its own time and doesn't skew the pace.
	local pace = LefthyToolsDB.flightPathPace
	TakeTaxiNode(3)
	TRAVEL.taxi = true
	Fire("PLAYER_CONTROL_LOST")
	-- On the way: a friend's item share is a subtitle; an offer pauses the film so its buttons show.
	anna("H2")
	Advance(2)
	anna("I2;1179::::::::20:::::")
	Advance(0.3)
	check(film:IsShown() and film.Subtitles:GetText():find("Anna|r shares", 1, true),
		"a friend shows an item: a subtitle, got " .. tostring(film.Subtitles:GetText()))
	do -- The item in it: hover for its tooltip (ours, above the film), click to open it.
		local lines = film.SubtitleFrame
		check(lines._mouseEnabled and lines._hyperlinks, "a line with a link: the subtitles take the mouse (only then)")
		local link = film.Subtitles:GetText():match("|H(item:[^|]+)|h")
		lines._scripts.OnHyperlinkEnter(lines, link, "[Item]")
		check(link and film.Tooltip:IsShown() and film.Tooltip._hyperlink == link and film.Tooltip._strata == "TOOLTIP",
			"hovering the item: its tooltip, above the film")
		lines._scripts.OnHyperlinkLeave(lines)
		check(not film.Tooltip:IsShown(), "and away")
		lines._scripts.OnHyperlinkClick(lines, link, "[Item]", "LeftButton")
		Advance(0.3)
		check(not film:IsShown() and UIParent:GetAlpha() == 1 and ItemRefTooltip:IsShown() and LINKS_CLICKED[#LINKS_CLICKED] == link,
			"a click: the interface back, the item opens")
		Advance(3)
		check(not film:IsShown(), "the film waits while it's open")
		ItemRefTooltip:Hide()
		Advance(2.6)
		check(film:IsShown(), "closed: the film comes back")
		-- Gamepad mode: not through SetItemRef (its ShowUIPanel from addon code taints the focus manager).
		local clicked = #LINKS_CLICKED
		GAMEPAD_STATE.ui = true
		lines._scripts.OnHyperlinkClick(lines, link, "[Item]", "LeftButton")
		GAMEPAD_STATE.ui = false
		Advance(0.3)
		check(#LINKS_CLICKED == clicked and ItemRefTooltip:IsShown() and ItemRefTooltip._hyperlink == link and not film:IsShown(),
			"gamepad mode: the item's tooltip shown directly, the film waits")
		ItemRefTooltip:Hide()
		Advance(2.6)
		check(film:IsShown(), "closed: back again")
	end
	Advance(2.1)
	anna("I2;6948::::::::20:::::;6161")
	Advance(0.6) -- (Beacon's tick, then the film's check, a few times a second)
	check(not film:IsShown() and UIParent:GetAlpha() == 1 and BB.calls["11:6161"].frame.Need:IsShown(),
		"a friend's offer: the film pauses for its Need and Pass buttons")
	BB.calls["11:6161"].frame.Pass:Click()
	Advance(2.5)
	check(film:IsShown(), "answered: the film comes back")
	anna("R2;6161;Bob:0")
	Advance(0.3)
	check(film.Subtitles:GetText():find("Bob wins!", 1, true), "and the outcome comes as a subtitle, got " .. tostring(film.Subtitles:GetText()))
	Advance(53.4) -- 4222 yd in 70 s: much faster than the rest (8.8 s went to the item link above)
	TRAVEL.taxi = false
	Fire("PLAYER_CONTROL_GAINED")
	Advance(0.5)
	check(LefthyToolsDB.flightPathPace == pace and math.abs(LefthyToolsDB.flightTimes["Undercity, Tirisfal > Tarren Mill, Hillsbrad"] - 70) <= 1,
		"an odd one: its time is kept, the pace isn't moved")
	-- A leg the data doesn't know: the straight line again, "about".
	TAXI_ROUTES[4] = { { 1, 3 }, { 3, 99 } }
	LefthyToolsDB.flightTimes["Undercity, Tirisfal > Hammerfall, Arathi"] = nil
	TakeTaxiNode(4)
	TRAVEL.taxi = true
	Fire("PLAYER_CONTROL_LOST")
	Advance(0.3)
	check(film.Timer:GetText():find("^Landing in about "), "a leg not in the data: the straight-line estimate, got " .. tostring(film.Timer:GetText()))
	TRAVEL.taxi = false
	Fire("PLAYER_CONTROL_GAINED")
	Advance(0.5)
	TAXI_ROUTES = {}
	-- The first version moved the camera: one left zoomed out or circling (a /reload mid-flight) is put back once.
	TDB.flightZoom, TDB.flightOrbit, TDB.flightMaxZoom, TDB.flightCamera, CAMERA.zoom, CAMERA.spinning = 10, true, 1.9, true, 22, true
	CVARS.cameraDistanceMaxZoomFactor = "2.6"
	lefthy("tweaks flights off")
	Advance(0.1)
	lefthy("tweaks flights on")
	Advance(0.1)
	check(CAMERA.zoom == 10 and not CAMERA.spinning and CVARS.cameraDistanceMaxZoomFactor == "1.9"
		and TDB.flightZoom == nil and TDB.flightCamera == nil, "the old camera settings: put back and gone")
	-- With the AFK screen at the same time, the interface stays hidden until both are done.
	ns.HideInterface("afk", true)
	TRAVEL.taxi = true
	Fire("PLAYER_CONTROL_LOST")
	Advance(2)
	check(film.Timer:GetText() == "", "a flight not picked on the map (a reload mid-flight): no time shown")
	TRAVEL.taxi = false
	Fire("PLAYER_CONTROL_GAINED")
	Advance(2)
	check(UIParent:GetAlpha() == 0, "landing while the AFK screen still hides it: still hidden")
	ns.HideInterface("afk", false)
	check(UIParent:GetAlpha() == 1, "both done: back")
	lefthy("tweaks flights off")
	Advance(0.1)
	check(TDB.cinematicFlights == false, "/lefthy tweaks flights off")
	TRAVEL.taxi = true
	Fire("PLAYER_CONTROL_LOST")
	Advance(2)
	check(UIParent:GetAlpha() == 1, "off: flights stay normal")
	TRAVEL.taxi = false
	Fire("PLAYER_CONTROL_GAINED")
	lefthy("tweaks flights on")
	Advance(0.5)
	UIParent:SetSize(uiW, uiH)
	ZONE = "Elwynn Forest"
end

section("Misc Tweaks: a flight that starts while typing")
do
	TAXI_NODES[3] = "Sentinel Hill, Westfall"
	TAXI_MAP_NODES = {
		{ name = "Stormwind, Elwynn", state = 0, slotIndex = 1, position = CreateVector2D(0.5, 0.5) },
		{ name = "Sentinel Hill, Westfall", state = 1, slotIndex = 3, position = CreateVector2D(0.45, 0.6) },
	}
	local route = "Stormwind, Elwynn > Sentinel Hill, Westfall"
	LefthyToolsDB.flightTimes[route] = nil
	local film = LefthyToolsFlightFrame
	if film:IsShown() then film.FadeOut:Finish() end
	ACTIVE_CHAT_EDIT_BOX = {} -- still typing as the flight starts
	TakeTaxiNode(3)
	TRAVEL.taxi = true
	Fire("PLAYER_CONTROL_LOST")
	Advance(6)
	check(not film:IsShown(), "typing at takeoff: no film yet")
	ACTIVE_CHAT_EDIT_BOX = nil
	Advance(0.5)
	check(film:IsShown(), "done typing (6 s in): the film starts after all")
	Advance(20)
	TRAVEL.taxi = false
	Fire("PLAYER_CONTROL_GAINED")
	Advance(0.5)
	local took = LefthyToolsDB.flightTimes[route]
	check(took and took >= 26 and took <= 27, "and the flight is timed from the takeoff, got " .. tostring(took))
	Advance(2)
	film.FadeOut:Finish()
	-- Switched on in the air: the film comes, but a flight it didn't see from the takeoff isn't kept.
	LefthyToolsDB.flightTimes[route] = nil
	lefthy("tweaks flights off")
	Advance(0.2)
	TakeTaxiNode(3)
	TRAVEL.taxi = true
	Fire("PLAYER_CONTROL_LOST")
	Advance(5)
	lefthy("tweaks flights on")
	Advance(0.5)
	Fire("PLAYER_ENTERING_WORLD", false, false) -- (as if the film looked again)
	Advance(0.5)
	Advance(20)
	TRAVEL.taxi = false
	Fire("PLAYER_CONTROL_GAINED")
	Advance(0.5)
	check(LefthyToolsDB.flightTimes[route] == nil, "a flight the film joined late isn't kept as the route's time")
	Advance(2)
	if film:IsShown() then film.FadeOut:Finish() end
	-- A pick that never took off (not enough money): a later flight not taken from the flight map
	-- (a quest's) isn't that route.
	TakeTaxiNode(3)
	Advance(11)
	TRAVEL.taxi = true
	Fire("PLAYER_CONTROL_LOST")
	Advance(0.5)
	check(film:IsShown() and film.Card.Header:GetText() ~= "Next stop" and film.Timer:GetText() == "",
		"a quest's flight long after an old pick: not named after it, no time, got " .. tostring(film.Card.Header:GetText()))
	Advance(11)
	TRAVEL.taxi = false
	Fire("PLAYER_CONTROL_GAINED")
	Advance(0.5)
	check(LefthyToolsDB.flightTimes[route] == nil, "... and its time isn't kept for the old pick's route")
	Advance(2)
	if film:IsShown() then film.FadeOut:Finish() end
end

section("Misc Tweaks: what a flight hides")
do
	local TDB = LefthyToolsDB.settings.tweaks
	local function T(id) return REGISTERED_SETTINGS["LefthyTools_tweaks_" .. id] end
	check(TDB.flightHide == "all" and TDB.flightGroups.chat == true and TDB.flightGroups.actionbars == true
		and T("flightHide") and T("flightGroup_chat") and T("flightGroup_minimap"), "default: everything; every element ticked")
	local mirageWasOn = Mirage.enabled
	if mirageWasOn then
		lefthy("disable mirage")
		Advance(3)
	end
	local barsBefore, playerBefore = a("MainActionBar"), a("PlayerFrame")
	T("flightHide"):SetValue(2) -- chosen elements
	T("flightGroup_chat"):SetValue(false)
	TRAVEL.taxi = true
	Fire("PLAYER_CONTROL_LOST")
	Advance(2.5)
	check(LefthyToolsFlightFrame:IsShown() and UIParent:GetAlpha() == 1 and a("MainActionBar") == 0 and a("PlayerFrame") == 0
		and a("ChatFrame1") == 1, "chosen elements, Mirage off: those go (action bars, unit frames), chat stays")
	check(not Minimap:IsShown(), "... a hidden minimap is taken away altogether (its quest areas ignore opacity)")
	ACTIVE_CHAT_EDIT_BOX = {}
	Advance(0.3)
	check(a("MainActionBar") == barsBefore and Minimap:IsShown(), "typing: back at once")
	ACTIVE_CHAT_EDIT_BOX = nil
	Advance(4.5)
	check(a("MainActionBar") == 0, "done typing: hidden again")
	TRAVEL.taxi = false
	Fire("PLAYER_CONTROL_GAINED")
	Advance(2.5)
	check(a("MainActionBar") == barsBefore and a("PlayerFrame") == playerBefore and Minimap:IsShown(),
		"landed: everything back at its own opacity (Edit Mode's, too)")
	T("flightHide"):SetValue(1)
	T("flightGroup_chat"):SetValue(true)
	if mirageWasOn then
		lefthy("enable mirage")
		Advance(0.5)
	end
end
