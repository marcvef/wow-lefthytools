-- Lodestar's suggested route for the plan (Route.lua): Q.RouteYards (straight-line yards in world
-- coordinates, another continent a fixed cost) and Q.SuggestRoute (stops in an order that keeps a
-- quest's start before its objectives before its end and a needed quest's end before the start of the
-- one needing it; a zig-zag order fixed; each stop's spot picked near the route; another continent
-- visited once; deterministic; done stops dropped; nil for nothing to do; 80 stops in time). Pure
-- logic: the mock's maps (1429 and 1415 on continent 0, 1414 on continent 1; 1429 is 1000 x 1000
-- yards), the quests' needs through Q.SetTestData and the engine's Q.Missing.
-- Needs: no other file.

local suite = ...
local check, section, ns = suite.check, suite.section, suite.ns
local Q = ns.Lodestar

local function near(a, b, eps) return math.abs(a - b) <= (eps or 0.5) end
local function Spot(x, y, map) return { map = map or 1429, x = x, y = y } end
local function Stop(quest, kind, spots, extra)
	local stop = { quest = quest, kind = kind, label = quest .. " " .. kind, spots = spots }
	for k, v in pairs(extra or {}) do stop[k] = v end
	return stop
end
-- The order as text: "quest kind[index]" joined.
local function Names(route)
	local out = {}
	for i, stop in ipairs(route and route.order or {}) do
		out[i] = stop.quest .. (stop.kind == "start" and "s" or stop.kind == "end" and "e" or ("o" .. (stop.index or "")))
	end
	return table.concat(out, ",")
end
-- Every constraint kept: start < objectives < end per quest, needs[b] = { a, ... }: a's end < b's start.
local function Kept(route, needs)
	local at = {}
	for i, stop in ipairs(route.order) do
		local q = at[stop.quest] or { objectives = {} }
		at[stop.quest] = q
		if stop.kind == "start" then q.start = i elseif stop.kind == "end" then q.finish = i else q.objectives[#q.objectives + 1] = i end
	end
	for id, q in pairs(at) do
		for _, o in ipairs(q.objectives) do
			if (q.start and q.start > o) or (q.finish and q.finish < o) then return false, id .. ": an objective out of place" end
		end
		if q.start and q.finish and q.start > q.finish then return false, id .. ": its end before its start" end
		for _, need in ipairs(needs and needs[id] or {}) do
			local other = at[need]
			if other and other.finish and q.start and other.finish > q.start then return false, id .. " starts before " .. need .. " ends" end
		end
	end
	return true
end

-- Quests for the needs (Q.Missing reads them): 97002 needs 97001; 97004 needs 97003 in the log.
Q.SetTestData({
	{ id = 97001, title = "First Errand", level = 5, zone = 1429 },
	{ id = 97002, title = "Second Errand", level = 6, zone = 1429, pre = { 97001 } },
	{ id = 97003, title = "Long Watch", level = 6, zone = 1429 },
	{ id = 97004, title = "While on Watch", level = 6, zone = 1429, preActive = 97003 },
}, { { map = 1429, name = "Elwynn Forest", continent = 1415, minLevel = 1, maxLevel = 10 } })

---------------------------------------------------------------------------
section("Lodestar route: yards between spots (Q.RouteYards)")
do
	check(type(Q.RouteYards) == "function" and type(Q.SuggestRoute) == "function", "Route.lua gives Q.RouteYards and Q.SuggestRoute")
	check(near(Q.RouteYards(Spot(0, 0), Spot(0.3, 0.4)), 500), "straight line in world yards: 300 by 400 is 500")
	check(near(Q.RouteYards(Spot(0.5, 0.5, 1429), Spot(0.375, 0.375, 1415)), 0, 1),
		"the same place on the zone and on its continent's map: 0 yards")
	local yards, far = Q.RouteYards(Spot(0.5, 0.5), Spot(0.5, 0.5, 1414))
	check(yards == 10000 and far == true, "another continent: the fixed cost, and says so")
	check(Q.RouteYards(Spot(0.5, 0.5), nil) == nil and Q.RouteYards({ map = 1429 }, Spot(0, 0)) == nil, "without two spots: nil")
	check(near(Q.RouteYards(Spot(0, 0, 5555), Spot(0.1, 0, 5555)), 300), "a map without world positions: its own size (3000 yards wide by default)")
	check(Q.RouteYards(Spot(0, 0, 5555), Spot(0, 0, 5556)) == 5000, "two such maps: a fixed cost")
end

---------------------------------------------------------------------------
section("Lodestar route: nothing to do")
do
	check(Q.SuggestRoute(nil) == nil and Q.SuggestRoute({}) == nil, "no stops: nil")
	check(Q.SuggestRoute({ Stop(1, "end", { Spot(0.1, 0.1) }, { done = true }) }) == nil, "only done stops: nil")
	check(Q.SuggestRoute({ Stop(1, "end", {}) }) == nil, "a stop without a spot is left out: nil")
	local one = Stop(1, "end", { Spot(0.2, 0.1) })
	local route = Q.SuggestRoute({ one }, Spot(0.1, 0.1))
	check(route and #route.order == 1 and route.order[1] == one and one.spot == one.spots[1] and near(route.before, 100) and near(route.after, 100),
		"one stop: itself, the same table, its spot set, 100 yards from here")
end

---------------------------------------------------------------------------
section("Lodestar route: a zig-zag order fixed")
do
	local stops = {}
	for i, x in ipairs({ 0.1, 0.9, 0.2, 0.8, 0.3, 0.7 }) do
		stops[i] = Stop(100 + i, "end", { Spot(x, 0.5) })
	end
	local route = Q.SuggestRoute(stops, Spot(0, 0.5))
	check(route and Names(route) == "101e,103e,105e,106e,104e,102e", "west to east, got " .. Names(route))
	check(route and near(route.before, 3100) and near(route.after, 900), ("3100 yards in the given order, 900 the route's (%s, %s)"):format(route and route.before, route and route.after))
	-- Already a good order: kept as it is.
	local good = {}
	for i, x in ipairs({ 0.1, 0.2, 0.3 }) do good[i] = Stop(200 + i, "end", { Spot(x, 0.5) }) end
	route = Q.SuggestRoute(good, Spot(0, 0.5))
	check(route and Names(route) == "201e,202e,203e" and route.before == route.after, "a good order stays, nothing saved")
	-- Without here: the route starts where it likes.
	local free = {}
	for i, x in ipairs({ 0.5, 0.1, 0.9 }) do free[i] = Stop(300 + i, "end", { Spot(x, 0.5) }) end
	route = Q.SuggestRoute(free)
	check(route and near(route.after, 800) and near(route.before, 1200), ("no position known: 800 yards end to end (%s)"):format(route and route.after))
end

---------------------------------------------------------------------------
section("Lodestar route: the constraints")
do
	-- A quest whose giver stands far east, its objectives west, its end in the middle: from the west,
	-- the giver still comes first. 97002 needs 97001: its giver right here, yet after 97001's end.
	local stops = {
		Stop(97001, "start", { Spot(0.9, 0.5) }),
		Stop(97001, "objective", { Spot(0.1, 0.5) }, { index = 1 }),
		Stop(97001, "objective", { Spot(0.15, 0.5) }, { index = 2 }),
		Stop(97001, "end", { Spot(0.5, 0.5) }),
		Stop(97002, "start", { Spot(0.05, 0.5) }),
		Stop(97002, "end", { Spot(0.06, 0.5) }),
	}
	local route = Q.SuggestRoute(stops, Spot(0, 0.5))
	local ok, why = Kept(route, { [97002] = { 97001 } })
	check(route and #route.order == 6 and ok, "start < objectives < end, and the needed quest's end before the start: " .. (why or Names(route)))
	check(route and route.order[1].quest == 97001 and route.order[1].kind == "start", "the giver first, though far: " .. Names(route))
	-- In the log (no start): its objectives, then its end; 97004 is taken while 97003 is in the log.
	stops = {
		Stop(97003, "start", { Spot(0.8, 0.2) }),
		Stop(97003, "end", { Spot(0.1, 0.2) }),
		Stop(97004, "start", { Spot(0.05, 0.2) }),
		Stop(97004, "end", { Spot(0.06, 0.2) }),
		Stop(55, "objective", { Spot(0.5, 0.9) }, { index = 1 }),
		Stop(55, "end", { Spot(0.02, 0.2) }),
	}
	route = Q.SuggestRoute(stops, Spot(0, 0.2))
	local pos = {}
	for i, stop in ipairs(route and route.order or {}) do pos[stop.quest .. stop.kind] = i end
	check(route and pos["97003start"] < pos["97004start"] and pos["97004start"] < pos["97003end"],
		"needed in the log: taken after its start, before its end: " .. Names(route))
	check(route and pos["55objective"] < pos["55end"], "a quest in my log: its objective before its end")
	-- A loop in the needs (bad data): still a route, each quest's own order kept.
	Q.SetTestData({
		{ id = 97011, title = "Loop A", level = 5, zone = 1429, pre = { 97012 } },
		{ id = 97012, title = "Loop B", level = 5, zone = 1429, pre = { 97011 } },
	}, { { map = 1429, name = "Elwynn Forest", continent = 1415 } })
	route = Q.SuggestRoute({
		Stop(97011, "start", { Spot(0.1, 0.1) }), Stop(97011, "end", { Spot(0.2, 0.1) }),
		Stop(97012, "start", { Spot(0.3, 0.1) }), Stop(97012, "end", { Spot(0.4, 0.1) }),
	}, Spot(0, 0.1))
	check(route and #route.order == 4 and Kept(route), "a loop in the needs: a route anyway, " .. Names(route))
end

---------------------------------------------------------------------------
section("Lodestar route: each stop's spot")
do
	-- The end has three spots: one far off, one by the others, one between: the one by the route.
	local stops = {
		Stop(400, "end", { Spot(0.9, 0.9), Spot(0.6, 0.6), Spot(0.21, 0.1) }),
		Stop(401, "end", { Spot(0.2, 0.1) }),
		Stop(402, "end", { Spot(0.3, 0.1) }),
	}
	local route = Q.SuggestRoute(stops, Spot(0.1, 0.1))
	check(route and stops[1].spot == stops[1].spots[3], "the spot by the route chosen")
	check(route and near(route.after, 200), ("200 yards in all (%s)"):format(route and route.after))
	-- Two objectives with clusters each side: both on the side the route is on.
	stops = {
		Stop(410, "objective", { Spot(0.9, 0.5), Spot(0.1, 0.4) }, { index = 1 }),
		Stop(410, "objective", { Spot(0.9, 0.6), Spot(0.1, 0.6) }, { index = 2 }),
		Stop(410, "end", { Spot(0.1, 0.5) }),
	}
	route = Q.SuggestRoute(stops, Spot(0.1, 0.5))
	check(route and stops[1].spot == stops[1].spots[2] and stops[2].spot == stops[2].spots[2] and stops[3] == route.order[3],
		"both clusters on the route's side, then the end: " .. Names(route))
	-- The given order's yards use each stop's own spot.
	stops = { Stop(420, "end", { Spot(0.2, 0.1), Spot(0.9, 0.1) }) }
	stops[1].spot = stops[1].spots[2]
	route = Q.SuggestRoute(stops, Spot(0.1, 0.1))
	check(route and near(route.before, 800) and near(route.after, 100) and stops[1].spot == stops[1].spots[1], "before: the stop's own spot; after: the near one")
end

---------------------------------------------------------------------------
section("Lodestar route: another continent")
do
	local stops = {
		Stop(501, "end", { Spot(0.2, 0.5) }),
		Stop(502, "end", { Spot(0.2, 0.5, 1414) }),
		Stop(503, "end", { Spot(0.3, 0.5) }),
		Stop(504, "end", { Spot(0.3, 0.5, 1414) }),
	}
	local route = Q.SuggestRoute(stops, Spot(0.1, 0.5))
	check(route and Names(route) == "501e,503e,502e,504e", "this continent first, then the other once: " .. Names(route))
	check(route and route.before - route.after >= 19000, ("two crossings saved (%s -> %s)"):format(route and route.before, route and route.after))
end

---------------------------------------------------------------------------
section("Lodestar route: done stops, the same answer every time")
do
	local function Make()
		return {
			Stop(601, "start", { Spot(0.5, 0.5) }, { done = true }),
			Stop(601, "objective", { Spot(0.7, 0.2), Spot(0.3, 0.8) }, { index = 1 }),
			Stop(601, "end", { Spot(0.5, 0.5) }),
			Stop(602, "start", { Spot(0.3, 0.3) }),
			Stop(602, "end", { Spot(0.7, 0.7), Spot(0.25, 0.3) }),
			Stop(603, "end", { Spot(0.6, 0.6) }, { done = true }),
		}
	end
	local a, b = Make(), Make()
	local ra, rb = Q.SuggestRoute(a, Spot(0.4, 0.4)), Q.SuggestRoute(b, Spot(0.4, 0.4))
	local same = ra and rb and Names(ra) == Names(rb) and ra.after == rb.after
	for i = 1, ra and #ra.order or 0 do
		local sa, sb = ra.order[i].spot, rb.order[i].spot
		if not (sb and sa.x == sb.x and sa.y == sb.y) then same = false end
	end
	check(same, "the same stops twice: the same route and spots, " .. Names(ra))
	local dropped = true
	for _, stop in ipairs(ra and ra.order or {}) do
		if stop.done then dropped = false end
	end
	check(ra and #ra.order == 4 and dropped, "the done stops left out")
end

---------------------------------------------------------------------------
section("Lodestar route: 80 stops in time")
do
	local seed = 12345
	local function Random() -- deterministic (an LCG)
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	local quests, needs, stops = {}, {}, {}
	for k = 1, 20 do
		local id = 98000 + k
		local q = { id = id, title = "Errand " .. k, level = 5, zone = 1429 }
		if k > 1 and k % 3 == 0 then
			q.pre = { id - 1 }
			needs[id] = { id - 1 }
		end
		quests[k] = q
	end
	Q.SetTestData(quests, { { map = 1429, name = "Elwynn Forest", continent = 1415 } })
	for k = 1, 20 do
		local id = 98000 + k
		stops[#stops + 1] = Stop(id, "start", { Spot(Random(), Random()) })
		for o = 1, 2 do
			local spots = {}
			for _ = 1, 1 + (k + o) % 3 do spots[#spots + 1] = Spot(Random(), Random()) end
			stops[#stops + 1] = Stop(id, "objective", spots, { index = o })
		end
		stops[#stops + 1] = Stop(id, "end", { Spot(Random(), Random()), Spot(Random(), Random()) })
	end
	local clock = os.clock()
	local route = Q.SuggestRoute(stops, Spot(0.5, 0.5))
	local took = os.clock() - clock
	local ok, why = route and Kept(route, needs)
	check(route and #route.order == 80 and ok, "80 stops, every constraint kept " .. (why or ""))
	check(route and route.after < route.before * 0.6, ("much shorter than the quests one after the other (%d -> %d yards)"):format(route and route.before or 0, route and route.after or 0))
	check(took < 3, ("in time: %.3f s here (the test VM is far slower than the game's Lua)"):format(took))
end

-- The test data goes (the next file sets its own).
Q.SetTestData({}, {})
