-- Misc Tweaks: flight points not discovered yet, on the world map.
-- Needs: no other file.
local suite = ...
local check, section, ns, LT, lefthy, near = suite.check, suite.section, suite.ns, suite.LT, suite.lefthy, suite.near
local FP = ns.FlightPoints

section("Misc Tweaks: undiscovered flight points on the map")
do
	local TDB = LefthyToolsDB.settings.tweaks
	check(TDB.flightPointMap == true and REGISTERED_SETTINGS.LefthyTools_tweaks_flightPointMap, "on by default, with a checkbox")
	local realPoints, realTaxi = ns.FLIGHT_POINTS, C_TaxiMap
	local realNodes = TAXI_MAP_NODES
	WorldMapFrame:Hide()
	MAP_VIEW.scale, MAP_VIEW.zoom, MAP_VIEW.pinScale = 1, 0, 1
	-- Elwynn Forest (1429) is north 0-1000, west 0-1000 on continent 0; the Eastern Kingdoms (1415) are
	-- 2000 to -2000; Kalimdor (1414) the same on continent 1.
	ns.FLIGHT_POINTS = {
		[2] = { 0, 500, 500, "A", "Stormwind, Elwynn" },
		[4] = { 0, 250, 750, "A", "Sentinel Hill, Westfall" },
		[5] = { 0, -1000, -1000, "A", "Lakeshire, Redridge" }, -- (off Elwynn, on the continent)
		[10] = { 0, 300, 300, "H", "The Sepulcher, Silverpine Forest" },
		[79] = { 0, 800, 200, "", "Marshal's Refuge, Un'Goro Crater" },
		[26] = { 1, 0, 0, "A", "Auberdine, Darkshore" },
	}
	FP.Forget()
	TDB.flightPointsKnown = {}
	C_TaxiMap = { GetAllTaxiNodes = realTaxi.GetAllTaxiNodes }

	local function Shown()
		local byID = {}
		for _, f in ipairs(FP.Pins()) do
			if f:IsShown() then
				byID[f.point.spot.id] = f
			end
		end
		return byID
	end
	local function Count(t)
		local n = 0
		for _ in pairs(t) do n = n + 1 end
		return n
	end

	-- A character who never talked to a flight master with LefthyTools: every one of theirs, faded.
	OpenWorldMap(1429)
	local pins = Shown()
	check(Count(pins) == 3 and pins[2] and pins[4] and pins[79] and not pins[10] and not pins[5] and not pins[26],
		"Elwynn: the Alliance's and both factions' points on it, not the Horde's or another map's, got " .. Count(pins))
	check(pins[4] and near(pins[4].mapX, 0.25) and near(pins[4].mapY, 0.75) and pins[4]:GetParent() == WorldMapFrame:GetCanvas(),
		"at the flight master's spot, on the map's canvas")
	check(pins[4] and near(pins[4]:GetAlpha(), 0.55) and pins[2] and near(pins[2]:GetAlpha(), 0.55), "not sure yet: faded")
	check(#MAP_WRITES == 0 and #MAP_PARENTED == 0 and pins[4]._motion == true and not pins[4]:IsMouseClickEnabled()
		and not pins[4]._scripts.OnMouseDown and not pins[4]._scripts.OnClick, "nothing written into the map; hover only, clicks go to the map")
	pins[4]._scripts.OnEnter(pins[4])
	check(TOOLTIP.shown and TOOLTIP.title == "Sentinel Hill, Westfall" and TOOLTIP.lines[1] == "A flight point you haven't discovered yet"
		and TOOLTIP.lines[3] and TOOLTIP.lines[3]:find("You may know it already", 1, true), "hover: its name, what it is, why it's faded")
	pins[4]._scripts.OnLeave(pins[4])

	-- The flight master's map: what's on it is known, and the continent is sure from now on.
	TAXI_MAP_NODES = {
		{ nodeID = 2, name = "Stormwind, Elwynn", state = 0, slotIndex = 1, position = CreateVector2D(0.5, 0.5) },
	}
	Fire("TAXIMAP_OPENED", 1)
	Advance(0.05)
	pins = Shown()
	check(Count(pins) == 2 and not pins[2] and pins[4] and pins[79] and near(pins[4]:GetAlpha(), 1),
		"after the flight master: the known one is gone, the others sure (not faded), got " .. Count(pins))
	local mine = TDB.flightPointsKnown["Lefthy-Realmy"]
	check(mine and mine.nodes[2] and mine.checked[0] and not mine.checked[1], "kept for this character, per continent")
	pins[4]._scripts.OnEnter(pins[4])
	check(TOOLTIP.title == "Sentinel Hill, Westfall" and #TOOLTIP.lines == 2, "sure: no 'may know it' line")
	pins[4]._scripts.OnLeave(pins[4])
	OpenWorldMap(1415)
	pins = Shown()
	check(pins[5] and pins[4] and pins[79] and not pins[2] and near(pins[5].mapX, 0.75) and near(pins[5].mapY, 0.75),
		"the continent map: its points too")

	-- Kalimdor, never seen at a flight master: the game's own map data decides where it tells.
	OpenWorldMap(1414)
	pins = Shown()
	check(pins[26] and near(pins[26]:GetAlpha(), 0.55), "another continent, nothing known: faded")
	local said = {}
	C_TaxiMap.GetTaxiNodesForMap = function(mapID) return mapID == 1414 and said or {} end
	said[1] = { nodeID = 26, name = "Auberdine, Dunkelküste", isUndiscovered = false, faction = 2, position = CreateVector2D(0.5, 0.5) }
	OpenWorldMap(1414)
	check(not Shown()[26], "the game says it's known: not shown")
	said[1].isUndiscovered = true
	said[2] = { nodeID = 999, name = "New Camp", isUndiscovered = true, faction = 2, position = CreateVector2D(0.1, 0.2) }
	said[3] = { nodeID = 998, name = "Horde Camp", isUndiscovered = true, faction = 1, position = CreateVector2D(0.3, 0.3) }
	OpenWorldMap(1414)
	pins = Shown()
	check(pins[26] and near(pins[26]:GetAlpha(), 1) and pins[999] and near(pins[999].mapX, 0.1) and not pins[998],
		"the game says undiscovered: sure; one the data doesn't have shows at the game's spot (not the Horde's)")
	pins[26]._scripts.OnEnter(pins[26])
	check(TOOLTIP.title == "Auberdine, Dunkelküste", "the game's name (the client's language) when it tells")
	pins[26]._scripts.OnLeave(pins[26])
	C_TaxiMap.ShouldMapShowTaxiNodes = function() return true end
	OpenWorldMap(1414)
	check(Count(Shown()) == 0, "where Blizzard's map draws flight points itself, the undiscovered ones it knows are left to it")
	C_TaxiMap.ShouldMapShowTaxiNodes = nil

	-- The world map: none.
	OpenWorldMap(947)
	check(Count(Shown()) == 0, "the world map: none (too crowded)")

	-- Closed: nothing listens but the flight master's map; switched off: nothing at all.
	WorldMapFrame:Hide()
	check(Count(Shown()) == 0, "the map closed: hidden")
	lefthy("tweaks flightpoints off")
	Advance(0.05)
	OpenWorldMap(1429)
	check(Count(Shown()) == 0, "switched off: none")
	TAXI_MAP_NODES = { { nodeID = 4, name = "Sentinel Hill, Westfall", state = 0, slotIndex = 1, position = CreateVector2D(0.5, 0.5) } }
	Fire("TAXIMAP_OPENED", 1)
	Advance(0.05)
	check(not mine.nodes[4], "switched off: nothing learned either")
	lefthy("tweaks flightpoints on")
	Advance(0.05)
	pins = Shown()
	check(pins[4] and pins[79], "on again: drawn on the open map")
	WorldMapFrame:Hide()

	ns.FLIGHT_POINTS, C_TaxiMap, TAXI_MAP_NODES = realPoints, realTaxi, realNodes
	FP.Forget()
	TDB.flightPointsKnown = {}
end

-- The data: every point a character can discover, on a continent, with a side and a name.
do
	local n, bad = 0, {}
	for id, p in pairs(ns.FLIGHT_POINTS) do
		n = n + 1
		if not (type(id) == "number" and (p[1] == 0 or p[1] == 1) and type(p[2]) == "number" and type(p[3]) == "number"
			and (p[4] == "A" or p[4] == "H" or p[4] == "") and type(p[5]) == "string" and not p[5]:find("^zzOLD")) then
			bad[#bad + 1] = tostring(id)
		end
	end
	check(n >= 60 and #bad == 0, "Data/FlightPoints.lua: " .. n .. " flight points, all well formed: " .. table.concat(bad, ", "))
end
