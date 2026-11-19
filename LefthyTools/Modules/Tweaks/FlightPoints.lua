local _, ns = ...
local LT = ns.LT
local L = ns.L
local M = LT:GetModule("tweaks")
local Overlay = LT.MapOverlay
local view = Overlay.view

-- Flight points on zone maps (the flightPointMap tweak): a flight master icon where each of your
-- faction's (and the ones both fly from) stands, saying whether you have it: plain if you do, on a
-- gold glow if you don't, faded while that isn't known yet (no flight master seen). Not on continent
-- or world maps: only while looking at the zone.
--
-- Where they stand: Data/FlightPoints.lua (the client's TaxiNodes table: the nodes a character can
-- discover, their world position; tools/update-flight-paths.ps1), carried onto the shown map with
-- C_Map.GetMapPosFromWorldPos (a map's spots are kept: maps don't move).
--
-- Which ones you know: the flight master's map shows them (C_TaxiMap.GetAllTaxiNodes at
-- TAXIMAP_OPENED, which a new flight point opens too): the node you're at (Current) and the ones
-- you can fly to (Reachable). Unreachable ones are left out: Blizzard's flight map hides them, so
-- they may be ones you don't know. Kept per character in M.db.flightPointsKnown["Name-Realm"] =
-- { nodes = { [nodeID] = true }, checked = { [continent] = true } }. On a continent not checked yet a
-- point not known to be yours is "unsure" (faded): nobody knows whether you have it.
--
-- The other continent from the same visit: the game's own map data (C_TaxiMap.GetTaxiNodesForMap's
-- isUndiscovered, on each continent's map and its zones) is checked against the flight master's map
-- right then (Calibrate): the ones it shows must be "known", the ones it doesn't list "undiscovered".
-- Only if it all matches (3 points at least, none wrong) is the game's data used, for both continents.
-- It isn't trusted otherwise: in game, before any flight master, it hid points never visited (seen on
-- Kalimdor). The last check is kept in M.db.flightPointsCheck. Its names (the client's language) are
-- used on the markers. /lefthy tweaks flightinfo says what the record and the game tell.
--
-- Drawn on frames of our own over the map (Core/MapOverlay.lua), hover only: clicks go to the map.
-- Cost: nothing while the map is closed; a draw when it opens or shows another map.

local MAP_TYPE = Enum.UIMapType or { Cosmic = 0, World = 1, Continent = 2, Zone = 3 }
local SIDE = { Alliance = "A", Horde = "H" }
local ICON_ATLAS, ICON_FILE = "FlightMaster", "Interface\\Minimap\\Tracking\\FlightMaster"
local ICON_SIZE = 18
local UNSURE_ALPHA = 0.55 -- not known yet whether you have it

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

-- The flight master's map is open: the nodes it shows are known (where you are, where you can fly),
-- and their continent is sure from now on; the game's map data, if it matches, does the other one.
local STATE = Enum.FlightPathState or { Current = 0, Reachable = 1, Unreachable = 2 }
local Calibrate -- (below)
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
	local listed, continent = {}, nil -- nodeID -> its state on the flight master's map; this continent
	for _, node in ipairs(nodes) do
		local id = type(node) == "table" and node.nodeID
		local shown = type(node) == "table" and (node.state == STATE.Current or node.state == STATE.Reachable)
		if type(id) == "number" and LT.Readable(id) and LT.Readable(node.state) then
			listed[id] = node.state
		end
		if shown and type(id) == "number" and LT.Readable(id) then
			continent = continent or (data[id] and data[id][1])
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
	if continent then
		learned = learned + Calibrate(continent, listed, mine)
	end
	if learned > 0 and view.shown then
		Draw()
	end
	return learned
end

---------------------------------------------------------------------------
-- What the shown map gets
---------------------------------------------------------------------------

-- Zone maps only: not continents or the world, dungeons have none.
local function ShowsOn(mapID)
	local info = C_Map.GetMapInfo(mapID)
	return info and info.mapType == MAP_TYPE.Zone or false
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
		return nil
	end
	local ok, shows = pcall(C_TaxiMap.ShouldMapShowTaxiNodes, mapID)
	return ok and shows
end

-- The continents' maps (the Eastern Kingdoms, Kalimdor), where the game's map data is asked.
local CONTINENT_MAP = { [0] = 1415, [1] = 1414 }

-- What the game's map data says of a continent's flight points: nodeID -> isUndiscovered (true or
-- false), from the continent's map and its zones' (only at a flight master: about 20 small calls).
local function GameSays(continent)
	local says = {}
	local top = CONTINENT_MAP[continent]
	if not (top and C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then
		return says
	end
	local maps = { top }
	if C_Map.GetMapChildrenInfo then
		local ok, children = pcall(C_Map.GetMapChildrenInfo, top, MAP_TYPE.Zone, true)
		if ok and type(children) == "table" then
			for _, child in ipairs(children) do
				if type(child) == "table" and type(child.mapID) == "number" then
					maps[#maps + 1] = child.mapID
				end
			end
		end
	end
	for _, mapID in ipairs(maps) do
		for id, node in pairs(FromGame(mapID)) do
			if says[id] == nil and type(node.isUndiscovered) == "boolean" and LT.Readable(node.isUndiscovered) then
				says[id] = node.isUndiscovered
			end
		end
	end
	return says
end

-- At a flight master: does the game's map data agree with its map (what it shows is known, what it
-- doesn't list isn't)? Then it says which ones you know on both continents. Returns how much it taught.
Calibrate = function(continent, listed, mine)
	local data, side = ns.FLIGHT_POINTS or {}, SIDE[UnitFactionGroup("player") or ""]
	local says = GameSays(continent)
	local agree, disagree = 0, 0
	for id, p in pairs(data) do
		if p[1] == continent and (p[4] == "" or p[4] == side) and says[id] ~= nil then
			local state = listed[id]
			if state == STATE.Current or state == STATE.Reachable then
				if says[id] == false then agree = agree + 1 else disagree = disagree + 1 end
			elseif state == nil then
				if says[id] == true then agree = agree + 1 else disagree = disagree + 1 end
			end
		end
	end
	local check = { at = time(), continent = continent, agree = agree, disagree = disagree, trusted = disagree == 0 and agree >= 3 }
	M.db.flightPointsCheck = check
	if not check.trusted then
		return 0
	end
	local learned = 0
	for c in pairs(CONTINENT_MAP) do
		local said = c == continent and says or GameSays(c)
		local known, told = 0, 0
		for id, undiscovered in pairs(said) do
			if data[id] and data[id][1] == c then
				told = told + 1
				if undiscovered == false then
					known = known + 1
					if not mine.nodes[id] then
						mine.nodes[id] = true
						learned = learned + 1
					end
				end
			end
		end
		check["continent" .. c] = told .. " told, " .. known .. " known"
		if told > 0 and not mine.checked[c] then
			mine.checked[c] = true
			learned = learned + 1
		end
	end
	return learned
end

-- A point: "known", "missing" (not discovered) or "unsure" (not known: its continent not checked yet).
local function Status(spot, mine)
	if mine.nodes[spot.id] then
		return "known"
	end
	return mine.checked[spot.continent] and "missing" or "unsure"
end

-- The points to draw on a map: { spot, status, gameName }.
function FlightPoints.OnMap(mapID)
	local list = {}
	if not ShowsOn(mapID) then
		return list
	end
	local side = SIDE[UnitFactionGroup("player") or ""]
	local mine, game = Mine(), FromGame(mapID)
	for _, spot in ipairs(Spots(mapID)) do
		if spot.side == "" or spot.side == side then
			local said = game[spot.id]
			list[#list + 1] = { spot = spot, status = Status(spot, mine),
				gameName = said and LT.Readable(said.name) and said.name or nil }
		end
	end
	return list
end

-- /lefthy tweaks flightinfo: what the record and the game say for a map (the shown one, else where you are).
function FlightPoints.Info(mapID)
	mapID = mapID or (view.shown and view.mapID) or C_Map.GetBestMapForUnit("player")
	local info = mapID and C_Map.GetMapInfo(mapID)
	if not info then
		return { "flight points: no map here." }
	end
	local out = {}
	local side = SIDE[UnitFactionGroup("player") or ""] or "?"
	local mine = Mine()
	local yours, have, missing, unsure = 0, 0, 0, 0
	local game = FromGame(mapID)
	local listed, saysNew, saysKnown = 0, 0, 0
	for _, said in pairs(game) do
		listed = listed + 1
		if said.isUndiscovered == true then
			saysNew = saysNew + 1
		elseif said.isUndiscovered == false then
			saysKnown = saysKnown + 1
		end
	end
	local missingNames = {}
	for _, spot in ipairs(Spots(mapID)) do
		if spot.side == "" or spot.side == side then
			yours = yours + 1
			local status = Status(spot, mine)
			if status == "missing" then
				missing = missing + 1
				missingNames[#missingNames + 1] = spot.name
			elseif status == "unsure" then
				unsure = unsure + 1
			else
				have = have + 1
			end
		end
	end
	local known, continents = 0, {}
	for _ in pairs(mine.nodes) do
		known = known + 1
	end
	for continent in pairs(mine.checked) do
		continents[#continents + 1] = tostring(continent)
	end
	table.sort(continents)
	out[#out + 1] = ("flight points on %s (%d): %d of yours (%s): %d you have, %d not discovered, %d not known yet (talk to a flight master)."):format(
		info.name or "?", mapID, yours, side, have, missing, unsure)
	if not ShowsOn(mapID) then
		out[#out + 1] = "  (markers show on zone maps only)"
	end
	out[#out + 1] = ("  this character knows %d; flight master maps seen on continent(s): %s."):format(known,
		#continents > 0 and table.concat(continents, ", ") or "none yet")
	local last = M.db.flightPointsCheck
	if type(last) == "table" and last.agree then
		out[#out + 1] = ("  the game's data at the last flight master (continent %s): %d right, %d wrong: %s."):format(
			tostring(last.continent), last.agree, last.disagree or 0, last.trusted and "used for both continents" or "not used")
	end
	local shows = BlizzardShows(mapID)
	out[#out + 1] = ("  the game's map data: %d listed (%d undiscovered, %d known); Blizzard's map shows flight points here: %s."):format(
		listed, saysNew, saysKnown, tostring(shows))
	if #missingNames > 0 then
		out[#out + 1] = "  not discovered: " .. table.concat(missingNames, "; ")
	end
	return out
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
	if point.status == "known" then
		tip:AddLine(L["You have this flight point."], 0.3, 1, 0.3)
	elseif point.status == "missing" then
		tip:AddLine(L["A flight point you haven't discovered yet"], 1, 0.82, 0)
		tip:AddLine(L["Talk to its flight master to discover it."], 1, 1, 1, true)
	else
		tip:AddLine(L["Not known yet whether you have it: talk to any flight master once."], 0.75, 0.75, 0.75, true)
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
		f.Glow:SetShown(point.status == "missing")
		f:SetAlpha(point.status == "unsure" and UNSURE_ALPHA or 1)
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
