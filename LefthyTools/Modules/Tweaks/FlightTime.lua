local _, ns = ...
local LT = ns.LT
local L = ns.L

-- Cinematic flights' time left to landing (Flight.lua shows it in the bottom bar). The game doesn't
-- tell. Best first:
--   * a route flown before: its time (LefthyToolsDB.flightTimes, "From > To"), counted down exactly;
--   * its length along the real flight path: the flight's legs (GetNumRoutes / TaxiGetNodeSlot)
--     looked up in Data/FlightPaths.lua (from the client's TaxiPath / TaxiPathNode tables), at
--     ~29.9 yd/s, learned from your flights (LefthyToolsDB.flightPathPace), plus waits on the way;
--   * only if a leg isn't known: the straight distance between the two flight points (C_TaxiMap
--     node positions, C_Map.GetMapWorldSize) at a learned pace (flightPace), shown as "about".
--
-- The route is read when it's picked on the flight map (Flight.lua's post-hook on TakeTaxiNode:
-- FlightTime.Pick), a trip starts at the takeoff (FlightTime.Trip) and is kept when it lands
-- (FlightTime.Record).

local PATH_PACE = 1 / 29.9  -- seconds per yard along a flight path (classic routes fly ~29.9 yd/s)
local DEFAULT_PACE = 1.15 / 30 -- seconds per yard of straight distance (the fallback) before any flight is timed
local MIN_FLIGHT, MAX_FLIGHT = 10, 1800 -- timed flights outside this are left out

local FlightTime = {}
ns.FlightTime = FlightTime

local saved -- LefthyToolsDB: flightTimes, flightPathPace, flightPace

local function Readable(value)
	return value ~= nil and not (issecretvalue and issecretvalue(value))
end

local Clock = ns.TweakUtil.Clock -- Tweaks.lua

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

-- The route of a slot on the taxi map, just picked: { name = "Sentinel Hill, Westfall", route =
-- "From > To", pathYards, pathWait, distance, at = when it was picked }, or nil.
function FlightTime.Pick(slot)
	local name = TaxiNodeName and TaxiNodeName(slot)
	if not (Readable(name) and type(name) == "string") then
		return nil
	end
	local route = { name = name, at = GetTime() }
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

---------------------------------------------------------------------------
-- A flight on a picked route: how long it takes, and what it teaches
---------------------------------------------------------------------------

-- A flight on the picked route (FlightTime.Pick), timed from the takeoff (takeoffAt; nil: the film
-- didn't see it, then it's timed from now and not kept).
function FlightTime.Trip(picked, takeoffAt)
	local trip = { route = picked.route, distance = picked.distance, pathYards = picked.pathYards,
		pathWait = picked.pathWait, started = takeoffAt or GetTime(), fromTakeoff = takeoffAt ~= nil }
	-- Best first: this route's own time; its length along the flight path; the straight line.
	trip.known = saved and saved.flightTimes[picked.route]
	if picked.pathYards then
		trip.estimate = picked.pathYards * (saved and saved.flightPathPace or PATH_PACE) + (picked.pathWait or 0)
	elseif picked.distance then
		trip.estimate = picked.distance * (saved and saved.flightPace or DEFAULT_PACE)
	end
	return trip
end

-- The flight is over: its time for this route, and the paces for estimating new ones. The path
-- pace only learns from flights near it (within 25%): a route flown at another speed (some of
-- Forever's own) has its own time kept and shouldn't skew the rest.
function FlightTime.Record(trip)
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

-- Seconds left to landing, or nil if that isn't known (no trip: a /reload mid-flight).
function FlightTime.Left(trip)
	local total = trip and (trip.known or trip.estimate)
	if not (total and trip.started) then
		return nil
	end
	return total - (GetTime() - trip.started)
end

-- What the bottom bar says: "Landing in 1:42" (timed before, or from the flight path's length),
-- "Landing in about 2:10" (only the straight distance known), past it "Landing any moment".
function FlightTime.Text(trip, left)
	if math.floor(left + 0.5) <= 0 then
		return L["Landing any moment"]
	elseif trip.known or trip.pathYards then
		return L["Landing in %s"]:format(Clock(left))
	end
	return L["Landing in about %s"]:format(Clock(left))
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
