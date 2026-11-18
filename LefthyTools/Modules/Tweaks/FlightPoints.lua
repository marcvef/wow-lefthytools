local _, ns = ...
local LT = ns.LT
local L = ns.L
local M = LT:GetModule("tweaks")
local Overlay = LT.MapOverlay
local view = Overlay.view

-- Flight points you haven't discovered yet, on the world map (the flightPointMap tweak): a flight
-- master icon on zone and continent maps where one stands, so you can find it. Only your faction's
-- (and the ones both fly from).
--
-- Where they stand: Data/FlightPoints.lua (the client's TaxiNodes table: the nodes a character can
-- discover, their world position; tools/update-flight-paths.ps1), carried onto the shown map with
-- C_Map.GetMapPosFromWorldPos (a map's spots are kept: maps don't move).
--
-- Which ones you know: the flight master's map lists them (C_TaxiMap.GetAllTaxiNodes at
-- TAXIMAP_OPENED, which a new flight point opens too). They're kept per character in
-- M.db.flightPointsKnown["Name-Realm"] = { nodes = { [nodeID] = true }, checked = { [continent] =
-- true } }: a continent whose flight map was seen is sure. On one not seen yet, the game's own map
-- data decides where it tells (C_TaxiMap.GetTaxiNodesForMap's isUndiscovered); where it doesn't,
-- the point shows faded and its tooltip says why. A node the game calls undiscovered that the data
-- doesn't have (a newer patch) shows at the game's spot. Where Blizzard's map draws flight points
-- itself (C_TaxiMap.ShouldMapShowTaxiNodes), the undiscovered ones it knows are left to it.
--
-- Drawn on frames of our own over the map (Core/MapOverlay.lua), hover only: clicks go to the map.
-- Cost: nothing while the map is closed; a draw when it opens or shows another map.

local MAP_TYPE = Enum.UIMapType or { Cosmic = 0, World = 1, Continent = 2, Zone = 3 }
local SIDE = { Alliance = "A", Horde = "H" }
local GAME_SIDE = { [1] = "H", [2] = "A" } -- Enum.FlightPathFaction: 0 neutral, 1 Horde, 2 Alliance
local ICON_ATLAS, ICON_FILE = "FlightMaster", "Interface\\Minimap\\Tracking\\FlightMaster"
local ICON_SIZE = 18
local FADED = 0.55 -- a point that may already be known

local active = false
local pins = { n = 0 } -- the i-th point of a draw is always the i-th frame
local spots = {}       -- mapID -> { { id, x, y, side, name, continent }, ... } (maps don't move)
local vector = CreateVector2D(0, 0)
local events = CreateFrame("Frame")

local FlightPoints = {}
ns.FlightPoints = FlightPoints

---------------------------------------------------------------------------
-- What this character knows
---------------------------------------------------------------------------

local function CharKey()
	return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function Mine()
	local all = M.db.flightPointsKnown
	local key = CharKey()
	local mine = all[key]
	if type(mine) ~= "table" or type(mine.nodes) ~= "table" or type(mine.checked) ~= "table" then
		mine = { nodes = {}, checked = {} }
		all[key] = mine
	end
	return mine
end

local Draw -- (below)

-- The flight master's map is open: every node on it is known, and its continent is sure from now on.
function FlightPoints.Learn()
	local mapID = GetTaxiMapID and GetTaxiMapID()
	if not (mapID and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes) then
		return 0
	end
	local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, mapID)
	if not ok or type(nodes) ~= "table" then
		return 0
	end
	local mine, data, learned = Mine(), ns.FLIGHT_POINTS or {}, 0
	for _, node in ipairs(nodes) do
		local id = type(node) == "table" and node.nodeID
		if type(id) == "number" and LT.Readable(id) then
			if not mine.nodes[id] then
				mine.nodes[id] = true
				learned = learned + 1
			end
			local point = data[id]
			if point and not mine.checked[point[1]] then
				mine.checked[point[1]] = true
				learned = learned + 1
			end
		end
	end
	if learned > 0 and view.shown then
		Draw()
	end
	return learned
end

---------------------------------------------------------------------------
-- What the shown map gets
---------------------------------------------------------------------------

-- Zone and continent maps: the world map would be crowded, dungeons have none.
local function ShowsOn(mapID)
	local info = C_Map.GetMapInfo(mapID)
	return info and (info.mapType == MAP_TYPE.Zone or info.mapType == MAP_TYPE.Continent) or false
end

-- Every flight point on a map, with its spot (0-1), kept.
local function Spots(mapID)
	local list = spots[mapID]
	if list then
		return list
	end
	list = {}
	for id, p in pairs(ns.FLIGHT_POINTS or {}) do
		vector:SetXY(p[2], p[3])
		local ok, onMap, pos = pcall(C_Map.GetMapPosFromWorldPos, p[1], vector, mapID)
		if ok and onMap == mapID and pos then
			local x, y = pos:GetXY()
			if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
				list[#list + 1] = { id = id, x = x, y = y, side = p[4], name = p[5], continent = p[1] }
			end
		end
	end
	table.sort(list, function(a, b) return a.id < b.id end)
	spots[mapID] = list
	return list
end

-- What the game's own map data says of the map's flight points: nodeID -> its MapTaxiNodeInfo.
local function FromGame(mapID)
	local info = {}
	if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then
		return info
	end
	local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, mapID)
	if ok and type(nodes) == "table" then
		for _, node in ipairs(nodes) do
			if type(node) == "table" and type(node.nodeID) == "number" and LT.Readable(node.nodeID) then
				info[node.nodeID] = node
			end
		end
	end
	return info
end

local function BlizzardShows(mapID)
	if not (C_TaxiMap and C_TaxiMap.ShouldMapShowTaxiNodes) then
		return false
	end
	local ok, shows = pcall(C_TaxiMap.ShouldMapShowTaxiNodes, mapID)
	return ok and shows == true
end

-- A point: "missing" (not discovered), "maybe" (no one can tell yet) or nil (known, or Blizzard's map
-- draws it).
local function Status(spot, mine, game, blizzard)
	local said = game[spot.id]
	local undiscovered = said and said.isUndiscovered
	if mine.checked[spot.continent] then
		if mine.nodes[spot.id] or (blizzard and undiscovered == true) then
			return nil
		end
		return "missing"
	end
	if mine.nodes[spot.id] or undiscovered == false then
		return nil
	elseif undiscovered == true then
		return not blizzard and "missing" or nil
	end
	return "maybe"
end

-- The points to draw on a map: { spot, status, gameName }.
function FlightPoints.OnMap(mapID)
	local list = {}
	if not ShowsOn(mapID) then
		return list
	end
	local side = SIDE[UnitFactionGroup("player") or ""]
	local mine, game, blizzard = Mine(), FromGame(mapID), BlizzardShows(mapID)
	local data = ns.FLIGHT_POINTS or {}
	for _, spot in ipairs(Spots(mapID)) do
		if spot.side == "" or spot.side == side then
			local status = Status(spot, mine, game, blizzard)
			if status then
				local said = game[spot.id]
				list[#list + 1] = { spot = spot, status = status, gameName = said and LT.Readable(said.name) and said.name or nil }
			end
		end
	end
	-- One the game calls undiscovered that the data doesn't have (a newer patch): at the game's spot.
	if not blizzard then
		for id, said in pairs(game) do
			local pos = said.position
			local theirs = GAME_SIDE[said.faction]
			if not data[id] and said.isUndiscovered == true and not mine.nodes[id] and (not theirs or theirs == side)
				and type(pos) == "table" and pos.GetXY and LT.Readable(said.name) then
				local x, y = pos:GetXY()
				list[#list + 1] = { spot = { id = id, x = x, y = y, name = said.name }, status = "missing", gameName = said.name }
			end
		end
	end
	return list
end

---------------------------------------------------------------------------
-- Frames: our own on the map's canvas (Core/MapOverlay.lua), never the map's pins
---------------------------------------------------------------------------

local function ShowTooltip(f, tip)
	local point = f.point
	if not point then
		return
	end
	tip:SetOwner(f, "ANCHOR_RIGHT")
	tip:SetText(point.gameName or point.spot.name)
	tip:AddLine(L["A flight point you haven't discovered yet"], 1, 0.82, 0)
	tip:AddLine(L["Talk to its flight master to discover it."], 1, 1, 1, true)
	if point.status == "maybe" then
		tip:AddLine(L["You may know it already: after you talk to any flight master on this continent, only the ones you haven't discovered show."], 0.75, 0.75, 0.75, true)
	end
	tip:Show()
end

local function PinOnEnter(self)
	ShowTooltip(self, GameTooltip)
end

local function PinOnLeave()
	GameTooltip:Hide()
end

local function NewPin()
	local f = Overlay.Frame("flightPoint")
	if not f then
		return nil
	end
	f:SetSize(ICON_SIZE, ICON_SIZE)
	f.Glow = f:CreateTexture(nil, "BACKGROUND")
	f.Glow:SetPoint("CENTER")
	f.Glow:SetSize(ICON_SIZE * 2, ICON_SIZE * 2)
	f.Glow:SetTexture("Interface\\Cooldown\\star4")
	f.Glow:SetBlendMode("ADD")
	f.Glow:SetVertexColor(1, 0.82, 0.2, 0.7)
	f.Icon = f:CreateTexture(nil, "ARTWORK")
	f.Icon:SetPoint("CENTER")
	f.Icon:SetSize(ICON_SIZE, ICON_SIZE)
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(ICON_ATLAS) then
		f.Icon:SetAtlas(ICON_ATLAS)
	else
		f.Icon:SetTexture(ICON_FILE)
	end
	-- Hover only, no click script (a frame with one is a button to the controller's navigation):
	-- clicks go through to the map.
	f:SetMouseMotionEnabled(true)
	f:SetMouseClickEnabled(false)
	f:SetScript("OnEnter", PinOnEnter)
	f:SetScript("OnLeave", PinOnLeave)
	Overlay.SetHover(f, ShowTooltip)
	return f
end

local function Clear()
	for i = 1, pins.n do
		local f = pins[i]
		if Overlay.TooltipOf(f) then
			Overlay.TooltipOf(f):Hide()
		end
		f.point = nil
		f:Hide()
	end
	pins.n = 0
end

Draw = function()
	local mapID = view.shown and view.mapID
	local points = (active and mapID) and FlightPoints.OnMap(mapID) or {}
	local n = 0
	for _, point in ipairs(points) do
		local f = pins[n + 1] or NewPin()
		if not f then
			break
		end
		n = n + 1
		pins[n] = f
		f.point = point
		f:SetAlpha(point.status == "maybe" and FADED or 1)
		f:SetFrameLevel(Overlay.Level("PIN_FRAME_LEVEL_FLIGHT_POINT", n))
		Overlay.Place(f, point.spot.x, point.spot.y, 1.0, 1.2)
	end
	for i = n + 1, pins.n do
		pins[i].point = nil
		pins[i]:Hide()
	end
	pins.n = n
end

-- The map: nothing while it's closed; drawn when it opens or shows another map, placed again on zoom.
Overlay.Watch("FlightPoints", function(what)
	if what == "hide" then
		events:UnregisterEvent("TAXI_NODE_STATUS_CHANGED")
		Clear()
		return
	end
	if what == "show" and active then
		pcall(events.RegisterEvent, events, "TAXI_NODE_STATUS_CHANGED")
	end
	if what == "scale" then
		for i = 1, pins.n do
			local f = pins[i]
			if f.mapX then
				Overlay.Place(f, f.mapX, f.mapY, 1.0, 1.2)
			end
		end
	else
		Draw()
	end
end)

events:SetScript("OnEvent", function(_, event)
	C_Timer.After(0, function() -- (not inside the event)
		if not active then
			return
		end
		if event == "TAXIMAP_OPENED" then
			FlightPoints.Learn()
		elseif view.shown then
			Draw()
		end
	end)
end)

---------------------------------------------------------------------------
-- Switching on and off (Tweaks.lua)
---------------------------------------------------------------------------

function ns.ApplyFlightPointMap(on)
	active = on
	if on then
		pcall(events.RegisterEvent, events, "TAXIMAP_OPENED")
		if view.shown then
			pcall(events.RegisterEvent, events, "TAXI_NODE_STATUS_CHANGED")
		end
	else
		events:UnregisterAllEvents()
	end
	if view.shown then
		Draw()
	end
end

-- (tests) other data: the maps' spots worked out again
function FlightPoints.Forget()
	wipe(spots)
end

-- (tests) the frames shown now
function FlightPoints.Pins()
	local list = {}
	for i = 1, pins.n do
		list[i] = pins[i]
	end
	return list
end
