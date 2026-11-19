-- Misc Tweaks: flight points on zone maps, whether you have them.
-- Needs: no other file.
local suite = ...
local check, section, ns, LT, lefthy, near = suite.check, suite.section, suite.ns, suite.LT, suite.lefthy, suite.near
local FP = ns.FlightPoints

section("Misc Tweaks: flight points on zone maps")
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
	TDB.flightPointsKnown, TDB.flightPointsCheck = {}, {}
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
	local function Tip(f)
		f._scripts.OnEnter(f)
		local tip = { title = TOOLTIP.title, lines = TOOLTIP.lines }
		f._scripts.OnLeave(f)
		return tip
	end
	local function Plain(f) return f and near(f:GetAlpha(), 1) and not f.Glow:IsShown() end
	local function Glowing(f) return f and near(f:GetAlpha(), 1) and f.Glow:IsShown() end
	local function Faded(f) return f and near(f:GetAlpha(), 0.55) and not f.Glow:IsShown() end

	-- A character who never talked to a flight master with LefthyTools: every one of theirs, faded.
	OpenWorldMap(1429)
	local pins = Shown()
	check(Count(pins) == 3 and Faded(pins[2]) and Faded(pins[4]) and Faded(pins[79]) and not pins[10] and not pins[5] and not pins[26],
		"Elwynn: theirs and both factions' (not the Horde's or another map's), faded: not known yet, got " .. Count(pins))
	check(near(pins[4].mapX, 0.25) and near(pins[4].mapY, 0.75) and pins[4]:GetParent() == WorldMapFrame:GetCanvas(),
		"at the flight master's spot, on the map's canvas")
	check(#MAP_WRITES == 0 and #MAP_PARENTED == 0 and pins[4]._motion == true and not pins[4]:IsMouseClickEnabled()
		and not pins[4]._scripts.OnMouseDown and not pins[4]._scripts.OnClick, "nothing written into the map; hover only, clicks go to the map")
	local tip = Tip(pins[4])
	check(tip.title == "Sentinel Hill, Westfall" and tip.lines[1] == "Not known yet whether you have it: talk to any flight master once."
		and #tip.lines == 1, "hover: its name, not known yet")
	local info = Info()
	check(info:find("flight points on Elwynn Forest (1429): 3 of yours (A): 0 you have, 0 not discovered, 3 not known yet", 1, true)
		and info:find("flight master maps seen on continent(s): none yet.", 1, true), "/lefthy tweaks flightinfo, got " .. info)

	-- The flight master's map: what it shows is known (where you are, where you can fly), the rest of the
	-- continent isn't. An unreachable one (Blizzard's flight map hides those) isn't learned.
	TAXI_MAP_NODES = {
		{ nodeID = 2, name = "Stormwind, Elwynn", state = 0, slotIndex = 1, position = CreateVector2D(0.5, 0.5) },
		{ nodeID = 4, name = "Sentinel Hill, Westfall", state = 2, slotIndex = 2, position = CreateVector2D(0.4, 0.6) },
	}
	Fire("TAXIMAP_OPENED", 1)
	Advance(0.05)
	pins = Shown()
	check(Count(pins) == 3 and Plain(pins[2]) and Glowing(pins[4]) and Glowing(pins[79]),
		"after the flight master: the one you have plain, the others (the unreachable one too) on a glow")
	local mine = TDB.flightPointsKnown["Lefthy-Realmy"]
	check(mine and mine.nodes[2] and not mine.nodes[4] and mine.checked[0] and not mine.checked[1], "kept for this character, per continent")
	check(Tip(pins[2]).lines[1] == "You have this flight point.", "hover one you have: says so")
	tip = Tip(pins[4])
	check(tip.lines[1] == "A flight point you haven't discovered yet" and tip.lines[2] == "Talk to its flight master to discover it.",
		"hover one you don't: says so")
	check(TDB.flightPointsCheck.trusted == false and TDB.flightPointsCheck.agree == 0, "no game data to compare: not used")
	info = Info()
	check(info:find("3 of yours (A): 1 you have, 2 not discovered, 0 not known yet", 1, true)
		and info:find("not discovered: Sentinel Hill, Westfall; Marshal's Refuge, Un'Goro Crater", 1, true), "flightinfo, got " .. info)

	-- Continent and world maps: none.
	OpenWorldMap(1415)
	check(Count(Shown()) == 0 and Info():find("(markers show on zone maps only)", 1, true), "a continent map: none, only zones")
	OpenWorldMap(947)
	check(Count(Shown()) == 0, "the world map: none")

	-- Kalimdor, never seen at a flight master: faded.
	OpenWorldMap(9001)
	pins = Shown()
	check(Count(pins) == 2 and Faded(pins[26]) and Faded(pins[27]), "another continent: faded")

	-- The game's map data, compared at a flight master: wrong there (it calls Marshal's Refuge known, which the
	-- flight master doesn't show): not used.
	local says = {}
	C_TaxiMap.GetTaxiNodesForMap = function(mapID) return says[mapID] or {} end
	local function Node(id, undiscovered, name) return { nodeID = id, isUndiscovered = undiscovered, name = name, position = CreateVector2D(0.5, 0.5) } end
	says[1415] = { Node(2, false), Node(4, false), Node(5, false), Node(79, false) }
	says[9001] = { Node(26, true, "Auberdine, Dunkelküste"), Node(27, false) }
	OpenWorldMap(1429)
	Fire("TAXIMAP_OPENED", 1)
	Advance(0.05)
	local last = TDB.flightPointsCheck
	check(last.continent == 0 and last.disagree == 2 and not last.trusted and not mine.checked[1] and not mine.nodes[27],
		"the game's data wrong at the flight master: not used, Kalimdor still not known")
	-- Right there (what it shows known, Lakeshire and Marshal's Refuge undiscovered; the unreachable one isn't
	-- compared): used for both continents, so Kalimdor is known from this one visit.
	says[1415] = { Node(2, false), Node(4, true), Node(5, true), Node(79, true) }
	Fire("TAXIMAP_OPENED", 1)
	Advance(0.05)
	last = TDB.flightPointsCheck
	check(last.agree == 3 and last.disagree == 0 and last.trusted and mine.checked[1] and mine.nodes[27] and not mine.nodes[26]
		and not mine.nodes[4], "the game's data right at the flight master: Kalimdor from it too")
	OpenWorldMap(9001)
	pins = Shown()
	check(Plain(pins[27]) and Glowing(pins[26]) and near(pins[27].mapX, 0.25), "Kalimdor's zone: the one you have plain, the other on a glow")
	check(Tip(pins[26]).title == "Auberdine, Dunkelküste", "the game's name when it tells (the client's language)")
	check(Info():find("the game's data at the last flight master (continent 0): 3 right, 0 wrong: used for both continents.", 1, true),
		"flightinfo: the comparison")
	C_TaxiMap.GetTaxiNodesForMap = nil

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
	check(Glowing(pins[4]) and Glowing(pins[79]) and Plain(pins[2]), "on again: drawn on the open map")
	WorldMapFrame:Hide()

	ns.FLIGHT_POINTS, C_TaxiMap, TAXI_MAP_NODES = realPoints, realTaxi, realNodes
	MAPS[9001], MAP_NAMES[9001], MAP_TYPES[9001], MAP_PARENTS[9001] = nil, nil, nil, nil
	FP.Forget()
	TDB.flightPointsKnown, TDB.flightPointsCheck = {}, {}
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
