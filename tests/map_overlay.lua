-- The world map, only read (Core/MapOverlay.lua): nothing written into it and no frame made on it, our
-- frames placed and scaled like the map's pins, nothing done while it's closed or still, clicks from
-- GLOBAL_MOUSE_DOWN only on the open map, the controller's map cursor showing our tooltips on a
-- tooltip of our own, quest icons made in a fight passing right-clicks through after it.
-- Needs: no other file: Anna (the mock's Battle.net friend) tells her position here.
local suite = ...
local check, section, LT, lefthy = suite.check, suite.section, suite.LT, suite.lefthy
local mapPins, pinOf, anna, near = suite.mapPins, suite.pinOf, suite.anna, suite.near

section("The world map, only read")
do
	local Overlay = LT.MapOverlay
	local canvas = WorldMapFrame:GetCanvas()
	WorldMapFrame:Hide()
	MAP_VIEW.scale, MAP_VIEW.zoom, MAP_VIEW.pinScale = 1, 0, 1
	PLAYER_POS = { 0.5, 0.5 }
	anna("S2;;0;250.0;750.0;Goldshire;")
	Advance(1.5)

	-- Closed: nothing runs, not even the compare.
	local reads = 0
	local getMapID = WorldMapFrame.GetMapID
	WorldMapFrame.GetMapID = function(self) reads = reads + 1; return getMapID(self) end
	Advance(1)
	check(reads == 0, "the map closed: nothing of ours looks at it, got " .. reads .. " reads")

	OpenWorldMap(1429)
	local dot = pinOf(11)
	check(dot and dot:IsShown() and dot:GetParent() == canvas and near(dot.mapX, 0.25) and near(dot.mapY, 0.75),
		"opened: Anna's dot on the map's canvas, at her spot")
	check(#MAP_WRITES == 0 and #MAP_PARENTED == 0, "no data provider, no pin, no map method that writes; no frame made on the map")
	local buttons = 0
	for _, f in ipairs(canvas._children or {}) do
		if f._kind == "Button" or f._scripts.OnMouseDown or f._scripts.OnMouseUp or f._scripts.OnClick then buttons = buttons + 1 end
	end
	check(buttons == 0, "nothing of ours on the canvas is a button to the controller's navigation (no Button, no click script)")

	-- Open and still: one compare a frame, nothing drawn.
	local placed = 0
	local setPoint = dot.SetPoint
	dot.SetPoint = function(...) placed = placed + 1; return setPoint(...) end
	reads = 0
	Advance(1)
	check(reads > 0 and placed == 0, "open and still: the map is only compared, nothing is drawn again, got " .. placed)

	-- Zoomed: placed and scaled like a map pin with SetScalingLimits(1, 1.0, 1.2).
	MAP_VIEW.scale, MAP_VIEW.zoom, MAP_VIEW.pinScale = 2, 0.5, 1.5
	MapTick()
	local s = (1 + 0.2 * 0.5) / 2 * 1.5
	local point, rel, relPoint, x, y = dot:GetPoint(1)
	check(placed > 0 and near(dot:GetScale(), s) and point == "CENTER" and rel == canvas and relPoint == "TOPLEFT"
		and near(x, 250 / s) and near(y, -750 / s), "zoomed in: scaled as Blizzard scales its pins, on the same spot, got "
		.. tostring(dot:GetScale()) .. " " .. tostring(x) .. " " .. tostring(y))
	MAP_VIEW.scale, MAP_VIEW.zoom, MAP_VIEW.pinScale = 1, 0, 1
	MapTick()
	check(near(dot:GetScale(), 1), "zoomed out again")
	dot.SetPoint = nil
	WorldMapFrame.GetMapID = getMapID

	-- A spot off the map: hidden.
	local probe = Overlay.Frame("test")
	check(probe and probe:GetParent() == canvas and not probe:IsShown() and #MAP_PARENTED == 0, "a frame of ours: made on its own, then put on the canvas")
	check(not Overlay.Place(probe, 1.2, 0.5) and not probe:IsShown() and Overlay.Place(probe, 0.5, 0.5) and probe:IsShown(),
		"a spot off the map hides the frame, one on it shows it")
	probe:Hide()

	-- Clicks: only while the map is open, only on the map.
	local mark, pmark = #GAMEDATA + 1, #PRINTED + 1
	STATE.alt = true
	MOCK_FOCUS = UIParent -- (somewhere else on the screen)
	ClickWorldMap()
	check(#suite.sentTo(11, mark, "P2;") == 0, "Alt+click off the map: no ping")
	MOCK_FOCUS = nil
	WorldMapFrame:Hide()
	Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
	Fire("GLOBAL_MOUSE_UP", "LeftButton")
	check(#suite.sentTo(11, mark, "P2;") == 0, "the map closed: clicks aren't even listened to")
	OpenWorldMap(1429)
	MOCK_CURSOR = { 0.5, 0.5 }
	ClickWorldMap()
	STATE.alt = false
	Advance(0.5)
	check(suite.sentTo(11, mark, "P2;")[1] == "P2;0;500.0;500.0;1429" and mapPins("beaconPing")[1], "Alt+click on the open map: pinged, my marker drawn")
	lefthy("beacon ping clear")
	Advance(0.5)

	-- The controller's map cursor near Anna's dot (canvas at 100, 1100: her dot at 350, 350).
	SoftCursor._centerX, SoftCursor._centerY = 355, 352
	SoftCursor:Show()
	TOOLTIP.shown = false
	Advance(0.1)
	local tip = LefthyToolsMapTooltip
	check(tip and tip:IsShown() and tip:IsOwned(dot) and tip._text == "Anna Brook" and not TOOLTIP.shown,
		"the controller's cursor near a dot: its tooltip, on a tooltip of our own (not GameTooltip)")
	anna("S2;C;0;250.0;750.0;Goldshire;Hogger")
	Advance(0.6)
	local fighting = false
	for _, line in ipairs(tip._lines or {}) do if line == "Fighting Hogger" then fighting = true end end
	check(fighting, "... it follows what changes")
	SoftCursor._centerX = 380 -- 30 away
	Advance(0.1)
	check(not tip:IsShown(), "the cursor moves away: the tooltip goes")
	CVARS.GamepadDisableTooltips = "1"
	SoftCursor._centerX = 350
	Advance(0.1)
	check(not tip:IsShown(), "tooltips switched off with the right stick: none")
	CVARS.GamepadDisableTooltips = nil
	Advance(0.1)
	check(tip:IsShown(), "on again")
	SoftCursor:Hide()
	Advance(0.1)
	check(not tip:IsShown(), "the cursor gone: the tooltip too")

	-- A quest icon (Misc Tweaks' quests on maps) under the cursor; in a fight a new icon waits to pass
	-- right-clicks through.
	local savedQuests = QUESTS
	QUESTS = { { id = 101, title = "Kobold Camp Cleanup", objectives = { { text = "Kobold Vermin slain: 4/10", finished = false } } } }
	QUESTS_ON_MAP = { [1429] = { { 101, 0.5, 0.5 } } }
	SUPER_TRACKED = 0
	OpenWorldMap(1415)
	local icon = mapPins("questIcon")[1]
	check(icon and near(icon.mapX, 0.375), "a quest icon on the continent map")
	SoftCursor._centerX, SoftCursor._centerY = 100 + 375, 1100 - 375
	SoftCursor:Show()
	Advance(0.1)
	check(tip:IsShown() and tip:IsOwned(icon) and tip._text == "Kobold Camp Cleanup" and not TOOLTIP.shown,
		"the controller's cursor near a quest icon: its tooltip, on ours")
	SoftCursor:Hide()
	Advance(0.1)
	local blocked = #BLOCKED
	local made = #mapPins("questIcon", true)
	for i = 1, made + 1 do QUESTS[i + 1] = { id = 200 + i, title = "Quest " .. i, objectives = {} } end
	QUESTS_ON_MAP[1436] = {}
	for i = 1, made + 1 do table.insert(QUESTS_ON_MAP[1436], { 200 + i, i / (made + 3), 0.5 }) end
	EnterCombat()
	OpenWorldMap(1415)
	local newest = mapPins("questIcon", true)[made + 1]
	check(newest and newest:IsShown() and not newest._passThrough and #BLOCKED == blocked,
		"a quest icon made in a fight: no protected call (it can't pass right-clicks through yet)")
	LeaveCombat()
	Advance(0.1)
	check(newest._passThrough and newest._passThrough[1] == "RightButton" and #BLOCKED == blocked, "... after the fight it does")
	WorldMapFrame:Hide()
	QUESTS, QUESTS_ON_MAP = savedQuests, {}
	anna("S2;;0;250.0;750.0;Goldshire;")
	Advance(1.1) -- (6 s in all)
	check(#MAP_WRITES == 0 and #MAP_PARENTED == 0, "still nothing written into the map")
end
