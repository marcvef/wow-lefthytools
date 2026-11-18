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
	-- 2000 to -2000; Kalimdor (1414) the same on continent 1, and a zone there (9001) too.
	MAPS[9001], MAP_NAMES[9001], MAP_TYPES[9001], MAP_PARENTS[9001] =
		{ continent = 1, top = 2000, left = 2000, width = 4000, height = 4000 }, "Darkshore", 3, 1414
	ns.FLIGHT_POINTS = {
		[2] = { 0, 500, 500, "A", "Stormwind, Elwynn" },
		[4] = { 0, 250, 750, "A", "Sentinel Hill, Westfall" },
		[5] = { 0, -1000, -1000, "A", "Lakeshire, Redridge" }, -- (off Elwynn, on the continent)
		[10] = { 0, 300, 300, "H", "The Sepulcher, Silverpine Forest" },
		[79] = { 0, 800, 200, "", "Marshal's Refuge, Un'Goro Crater" },
		[26] = { 1, 0, 0, "A", "Auberdine, Darkshore" },
		[27] = { 1, 1000, 1000, "A", "Rut'theran Village, Teldrassil" },
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
	local function Info()
		local printed = #PRINTED
		lefthy("tweaks flightinfo")
		return table.concat(PRINTED, "\n", printed + 1)
	end

	-- A character who never talked to a flight master with LefthyTools: nobody knows which ones they have.
	OpenWorldMap(1429)
	check(Count(Shown()) == 0, "before any flight master: none (they may be discovered already)")
	local info = Info()
	check(info:find("flight points on Elwynn Forest (1429): 3 of yours (A), 0 not discovered, 3 hidden until you talk to a flight master on this continent.", 1, true)
		and info:find("flight master maps seen on continent(s): none yet.", 1, true), "/lefthy tweaks flightinfo says why, got " .. info)

	-- The flight master's map: what it shows is known (where you are, where you can fly), and the
	-- continent is sure from now on. An unreachable one (Blizzard's flight map hides those) isn't learned.
	TAXI_MAP_NODES = {
		{ nodeID = 2, name = "Stormwind, Elwynn", state = 0, slotIndex = 1, position = CreateVector2D(0.5, 0.5) },
		{ nodeID = 4, name = "Sentinel Hill, Westfall", state = 2, slotIndex = 2, position = CreateVector2D(0.4, 0.6) },
	}
	Fire("TAXIMAP_OPENED", 1)
	Advance(0.05)
	local pins = Shown()
	check(Count(pins) == 2 and not pins[2] and pins[4] and pins[79] and not pins[10] and not pins[5] and not pins[26],
		"after the flight master: the ones not discovered (the unreachable one too), not the known one, the Horde's or another map's, got " .. Count(pins))
	check(pins[4] and near(pins[4].mapX, 0.25) and near(pins[4].mapY, 0.75) and pins[4]:GetParent() == WorldMapFrame:GetCanvas()
		and near(pins[4]:GetAlpha(), 1), "at the flight master's spot, on the map's canvas")
	check(#MAP_WRITES == 0 and #MAP_PARENTED == 0 and pins[4]._motion == true and not pins[4]:IsMouseClickEnabled()
		and not pins[4]._scripts.OnMouseDown and not pins[4]._scripts.OnClick, "nothing written into the map; hover only, clicks go to the map")
	local mine = TDB.flightPointsKnown["Lefthy-Realmy"]
	check(mine and mine.nodes[2] and not mine.nodes[4] and mine.checked[0] and not mine.checked[1], "kept for this character, per continent")
	pins[4]._scripts.OnEnter(pins[4])
	check(TOOLTIP.shown and TOOLTIP.title == "Sentinel Hill, Westfall" and TOOLTIP.lines[1] == "A flight point you haven't discovered yet"
		and TOOLTIP.lines[2] == "Talk to its flight master to discover it." and #TOOLTIP.lines == 2, "hover: its name, what it is")
	pins[4]._scripts.OnLeave(pins[4])
	info = Info()
	check(info:find("3 of yours (A), 2 not discovered, 0 hidden", 1, true) and info:find("not discovered: Sentinel Hill, Westfall; Marshal's Refuge, Un'Goro Crater", 1, true),
		"flightinfo: the ones not discovered by name, got " .. info)

	-- Continent and world maps: none.
	OpenWorldMap(1415)
	check(Count(Shown()) == 0 and Info():find("(markers show on zone maps only)", 1, true), "a continent map: none, only zones")
	OpenWorldMap(947)
	check(Count(Shown()) == 0, "the world map: none")

	-- Kalimdor, never seen at a flight master: none, whatever the game's map data says (in game it called
	-- points never visited known); once seen, its names are used (the client's language).
	local said = {}
	C_TaxiMap.GetTaxiNodesForMap = function(mapID) return mapID == 9001 and said or {} end
	C_TaxiMap.ShouldMapShowTaxiNodes = function() return true end
	said[1] = { nodeID = 26, name = "Auberdine, Dunkelküste", isUndiscovered = true, faction = 2, position = CreateVector2D(0.5, 0.5) }
	OpenWorldMap(9001)
	check(Count(Shown()) == 0, "a continent not seen at a flight master: none, even where the game says undiscovered")
	info = Info()
	check(info:find("1 listed (1 undiscovered, 0 known); Blizzard's map shows flight points here: true.", 1, true),
		"flightinfo: what the game says, got " .. info)
	TAXI_MAP_NODES = { { nodeID = 27, name = "Rut'theran Village, Teldrassil", state = 0, slotIndex = 1, position = CreateVector2D(0.5, 0.5) } }
	Fire("TAXIMAP_OPENED", 1)
	Advance(0.05)
	pins = Shown()
	check(pins[26] and near(pins[26].mapX, 0.5) and mine.checked[1], "after a flight master there: its points not discovered, drawn on the open map")
	pins[26]._scripts.OnEnter(pins[26])
	check(TOOLTIP.title == "Auberdine, Dunkelküste", "the game's name when it tells")
	pins[26]._scripts.OnLeave(pins[26])
	C_TaxiMap.ShouldMapShowTaxiNodes, C_TaxiMap.GetTaxiNodesForMap = nil, nil

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
	MAPS[9001], MAP_NAMES[9001], MAP_TYPES[9001], MAP_PARENTS[9001] = nil, nil, nil, nil
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
