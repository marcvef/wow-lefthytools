local _, ns = ...
local LT = ns.LT
local Q = ns.Lodestar or {}
ns.Lodestar = Q

-- Lodestar's suggested route for the plan (docs/lodestar.md, "Route"): pure logic, no UI, no events.
--   Q.SuggestRoute(stops, here) -> { order = { stop, ... }, before = yards, after = yards } or nil
--   Q.RouteYards(a, b)          -> yards between two spots ({ map, x, y }), true for another continent
-- A stop is Plan.lua's ({ quest, kind = "start"|"objective"|"end", spots = { spot, ... }, spot, done }).
-- Kept: a quest's start before its objectives before its end; a quest that needs another in the plan
-- (Q.Missing) starts after that one's end ("log": while that one is in the log: after its start, before
-- its end). Travel: straight-line yards in world coordinates (C_Map.GetWorldPosFromMapPos, as
-- Q.Toward); another continent a fixed cost. Flight paths aren't counted: Data/FlightPaths.lua has
-- the paths' lengths but not where the flight masters stand, and which ones I know is only seen at
-- a flight master. Precedence-feasible nearest neighbour from here (or the given order when it's as
-- short), then 2-opt and or-opt moves that keep every constraint (or-opt tries the places next to a
-- segment's 8 nearest stops), each stop's spot picked best for the order (a Viterbi pass) between
-- rounds; deterministic. Runs once per click (80 stops: about 10 ms), never per frame.

local CONTINENT_YARDS = 10000 -- another continent: a boat, a zeppelin or a portal and the wait
local OTHER_MAP_YARDS = 5000 -- two maps the game gives no world position for (an instance's)
local ZONE_WIDTH, ZONE_HEIGHT = 3000, 2000 -- a map without a world position: its size in yards
local ROUNDS = 8 -- improvement rounds (moves, then spots) at most
local MOVES = 4000 -- improving moves per round at most
local IMPROVE_MAX = 200 -- more stops than this: nearest neighbour and the spots only
local GAIN = 0.5 -- a move must save at least this many yards (no loops on rounding)

local sqrt = math.sqrt

-- Where a spot is: { real = true, c = continent, n = north, w = west } in world yards, else { map, x,
-- y in yards on its map }; nil for no spot.
local function Place(spot)
	if type(spot) ~= "table" or type(spot.x) ~= "number" or type(spot.y) ~= "number" then
		return nil
	end
	local place = { map = spot.map }
	if spot.map and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
		local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, spot.map, CreateVector2D(spot.x, spot.y))
		if ok and continent ~= nil and type(pos) == "table" and not LT.IsSecret(continent) and not LT.IsSecret(pos) then
			local okXY, north, west = pcall(pos.GetXY, pos)
			if okXY and type(north) == "number" and type(west) == "number" then
				place.real, place.c, place.n, place.w = true, continent, north, west
			end
		end
	end
	local width, height = ZONE_WIDTH, ZONE_HEIGHT
	if not place.real and spot.map and C_Map and C_Map.GetMapWorldSize then
		local ok, w, h = pcall(C_Map.GetMapWorldSize, spot.map)
		if ok and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
			width, height = w, h
		end
	end
	place.x, place.y = spot.x * width, spot.y * height
	return place
end

-- Yards from place a to place b; true as well when it's another continent (the fixed cost).
local function Yards(a, b)
	if a.real and b.real then
		if a.c ~= b.c then
			return CONTINENT_YARDS, true
		end
		local dn, dw = a.n - b.n, a.w - b.w
		return sqrt(dn * dn + dw * dw)
	elseif a.map ~= nil and a.map == b.map then
		local dx, dy = a.x - b.x, a.y - b.y
		return sqrt(dx * dx + dy * dy)
	end
	return OTHER_MAP_YARDS
end

-- Yards between two spots ({ map, x, y }, 0..1 on that map), for others to show distances: straight
-- line in world coordinates; another continent: a fixed cost (and true). nil without both spots.
function Q.RouteYards(a, b)
	local pa, pb = Place(a), Place(b)
	if not (pa and pb) then
		return nil
	end
	return Yards(pa, pb)
end

-- The quests a quest needs that may be in the plan: { { id, reason } } (reason as Q.Missing's: "done",
-- "any", "log"). Q.Missing when the engine is there, else the quest's own lists.
local function Needs(id)
	local out = {}
	if Q.Missing then
		local ok, list = pcall(Q.Missing, id)
		if ok and type(list) == "table" then
			for _, m in ipairs(list) do
				if type(m) == "table" and m.id then
					out[#out + 1] = { m.id, m.reason }
				end
			end
			return out
		end
	end
	local q = Q.Quest and Q.Quest(id)
	if type(q) == "table" then
		for _, p in ipairs(q.pre or {}) do out[#out + 1] = { p, "done" } end
		for _, p in ipairs(q.preAny or {}) do out[#out + 1] = { p, "any" } end
		if q.preActive then out[#out + 1] = { q.preActive, "log" } end
	end
	return out
end

-- The constraints between the nodes (1..n, the stops kept): preds[i], succs[i] lists of nodes.
-- withNeeds false: only each quest's own order (when the quests' needs make a loop).
local function Constraints(list, withNeeds)
	local n = #list
	local preds, succs, seen = {}, {}, {}
	for i = 1, n do
		preds[i], succs[i], seen[i] = {}, {}, {}
	end
	local function edge(a, b)
		if a and b and a ~= b and not seen[a][b] then
			seen[a][b] = true
			succs[a][#succs[a] + 1] = b
			preds[b][#preds[b] + 1] = a
		end
	end
	local quests, order = {}, {}
	for i, stop in ipairs(list) do
		local id = stop.quest
		local q = quests[id]
		if not q then
			q = { objectives = {} }
			quests[id] = q
			order[#order + 1] = id
		end
		if stop.kind == "start" then
			q.start = q.start or i
		elseif stop.kind == "end" then
			q.finish = q.finish or i
		else
			q.objectives[#q.objectives + 1] = i
		end
	end
	for _, id in ipairs(order) do
		local q = quests[id]
		for _, o in ipairs(q.objectives) do
			edge(q.start, o)
			edge(o, q.finish)
		end
		edge(q.start, q.finish)
	end
	if withNeeds then
		for _, id in ipairs(order) do
			local q = quests[id]
			if q.start and id ~= nil then
				for _, need in ipairs(Needs(id)) do
					local other = quests[need[1]]
					if other and other ~= q then
						if need[2] == "log" then
							edge(other.start, q.start)
							edge(q.start, other.finish)
						else
							edge(other.finish or other.start, q.start)
						end
					end
				end
			end
		end
	end
	return preds, succs
end

-- True when the constraints have no loop (Kahn).
local function Acyclic(preds, succs, n)
	local count, ready, head = {}, {}, 1
	for i = 1, n do
		count[i] = #preds[i]
		if count[i] == 0 then ready[#ready + 1] = i end
	end
	while ready[head] do
		local i = ready[head]
		head = head + 1
		for _, s in ipairs(succs[i]) do
			count[s] = count[s] - 1
			if count[s] == 0 then ready[#ready + 1] = s end
		end
	end
	return #ready == n
end

-- The route: the nodes in an order and a place for each.
local function Solve(list, cand, places, here, preds, succs, given)
	local n, M = #list, #places + 1
	local memo = {} -- the yards between two places, asked once
	local function D(a, b) -- place indexes; nil (no start known) costs nothing
		if not a or not b then return 0 end
		local key = a * M + b
		local d = memo[key]
		if not d then
			d = (Yards(places[a], places[b]))
			memo[key], memo[b * M + a] = d, d
		end
		return d
	end

	local function Total(seq, sp)
		local total, prev = 0, here
		for i = 1, n do
			total = total + D(prev, sp[seq[i]])
			prev = sp[seq[i]]
		end
		return total
	end

	-- The best place for each node in this order (exact for the order: a Viterbi pass).
	local function BestSpots(seq, sp)
		local back, prevCost, prevCands = {}, nil, nil
		for idx = 1, n do
			local cs = cand[seq[idx]]
			local cost, from = {}, {}
			for a = 1, #cs do
				if idx == 1 then
					cost[a] = D(here, cs[a])
				else
					local best, arg
					for b = 1, #prevCands do
						local c = prevCost[b] + D(prevCands[b], cs[a])
						if not best or c < best then best, arg = c, b end
					end
					cost[a], from[a] = best, arg
				end
			end
			back[idx], prevCost, prevCands = from, cost, cs
		end
		local best, arg
		for a = 1, #prevCands do
			if not best or prevCost[a] < best then best, arg = prevCost[a], a end
		end
		for idx = n, 1, -1 do
			sp[seq[idx]] = cand[seq[idx]][arg]
			arg = back[idx][arg]
		end
		return best
	end

	-- The yards between the nodes in their places: dm[x * N + y + 1], node 0 here (nothing when not
	-- known), n + 1 the end (nothing to it); rows made again only for nodes whose place changed (at).
	-- True when any did.
	local N = n + 2
	local function Matrix(dm, at, sp)
		local changed = {}
		for x = 1, n do
			if at[x] ~= sp[x] then
				changed[x], at[x] = true, sp[x]
			end
		end
		if not next(changed) then
			return false
		end
		dm[1], dm[n + 2] = 0, 0
		for x = 1, n do
			if changed[x] then
				local px = sp[x]
				for y = 1, n do
					if not (changed[y] and y < x) then -- (done from y's side)
						local d = x ~= y and D(px, sp[y]) or 0
						dm[x * N + y + 1], dm[y * N + x + 1] = d, d
					end
				end
				dm[x * N + 1], dm[x * N + n + 2], dm[x + 1] = 0, 0, D(here, px)
			end
		end
		return true
	end

	-- Each node's NEAR nearest other nodes (for or-opt's places to try).
	local NEAR = 8
	local function Neighbours(dm)
		local near = {}
		for x = 1, n do
			local list, dist, row = {}, {}, x * N + 1
			for y = 1, n do
				if y ~= x then
					local d = dm[row + y]
					local k = #list
					if k < NEAR or d < dist[k] then
						if k == NEAR then k = k - 1 end
						while k > 0 and dist[k] > d do
							list[k + 1], dist[k + 1] = list[k], dist[k]
							k = k - 1
						end
						list[k + 1], dist[k + 1] = y, d
					end
				end
			end
			near[x] = list
		end
		return near
	end

	-- Moves that keep every constraint, each saving yards, until none does; the places stay (BestSpots
	-- picks them again after). On a copy with the ends: s[0] = here (node 0), s[n + 1] = the end.
	local function Improve(seq, dm, near)
		local s, pos = { [0] = 0 }, {}
		for i = 1, n do s[i] = seq[i] end
		s[n + 1] = n + 1
		local function renumber()
			for i = 1, n do pos[s[i]] = i end
		end
		renumber()
		local moves, improved = 0, true
		while improved and moves < MOVES do
			improved = false
			-- 2-opt: reverse s[i..j] (no constraint inside it).
			for i = 1, n - 1 do
				local aN = s[i - 1] * N + 1
				for j = i + 1, n do
					local pl, blocked = preds[s[j]], false
					for k = 1, #pl do
						if pos[pl[k]] >= i then blocked = true break end
					end
					if blocked then break end
					local first, last, b = s[i], s[j], s[j + 1]
					if dm[aN + last] + dm[first * N + b + 1] - dm[aN + first] - dm[last * N + b + 1] < -GAIN then
						local lo, hi = i, j
						while lo < hi do
							s[lo], s[hi] = s[hi], s[lo]
							lo, hi = lo + 1, hi - 1
						end
						renumber()
						improved, moves = true, moves + 1
					end
				end
			end
			-- or-opt: move s[i..i+len-1] between rest[t] and rest[t + 1] (rest: s without it), t right
			-- after a node near its head, right before one near its tail, or the start.
			for len = 1, 3 do
				local i = 1
				while i <= n - len + 1 and moves < MOVES do
					local last = i + len - 1
					local lo, hi = 0, n - len -- the window the constraints leave
					for k = i, last do
						local pl, sl = preds[s[k]], succs[s[k]]
						for m = 1, #pl do
							local r = pos[pl[m]]
							if r < i then
								if r > lo then lo = r end
							elseif r > last and r - len > lo then
								lo = r - len
							end
						end
						for m = 1, #sl do
							local r = pos[sl[m]]
							if r < i then
								if r - 1 < hi then hi = r - 1 end
							elseif r > last and r - len - 1 < hi then
								hi = r - len - 1
							end
						end
					end
					local head, tail = s[i], s[last]
					local tN = tail * N + 1
					local before, after = s[i - 1], s[last + 1]
					local gain = dm[before * N + head + 1] + dm[tN + after] - dm[before * N + after + 1]
					local bestT, bestDelta
					local function try(t)
						if t >= lo and t <= hi and t ~= i - 1 then
							local p = t < i and s[t] or s[t + len]
							local q = t + 1 < i and s[t + 1] or s[t + 1 + len]
							local delta = dm[p * N + head + 1] + dm[tN + q] - dm[p * N + q + 1] - gain
							if delta < -GAIN and (not bestDelta or delta < bestDelta or (delta == bestDelta and t < bestT)) then
								bestT, bestDelta = t, delta
							end
						end
					end
					try(0)
					local nh, nt = near[head], near[tail]
					for m = 1, #nh do
						local r = pos[nh[m]]
						if r < i then try(r) elseif r > last then try(r - len) end
					end
					for m = 1, #nt do
						local r = pos[nt[m]]
						if r < i then try(r - 1) elseif r > last then try(r - len - 1) end
					end
					if bestT then
						local out, k = {}, 0
						for t = 0, n - len do
							if t > 0 then
								k = k + 1
								out[k] = t < i and s[t] or s[t + len]
							end
							if t == bestT then
								for m = i, last do
									k = k + 1
									out[k] = s[m]
								end
							end
						end
						for m = 1, n do s[m] = out[m] end
						renumber()
						improved, moves = true, moves + 1
					else
						i = i + 1
					end
				end
			end
		end
		for i = 1, n do seq[i] = s[i] end
	end

	local function Optimise(seq, sp)
		local total = BestSpots(seq, sp)
		local dm, at = {}, {}
		for _ = 1, n <= IMPROVE_MAX and ROUNDS or 0 do
			if not Matrix(dm, at, sp) then
				break -- (the same places as the last round's moves had)
			end
			Improve(seq, dm, Neighbours(dm))
			local now = BestSpots(seq, sp)
			if now > total - GAIN then
				break
			end
			total = now
		end
		return Total(seq, sp)
	end

	-- Nearest neighbour from here, only stops whose constraints are met.
	local seq, sp = {}, {}
	local count, placed = {}, {}
	for i = 1, n do count[i] = #preds[i] end
	local cur = here
	for step = 1, n do
		local bestNode, bestSpot, bestD
		for i = 1, n do
			if not placed[i] and count[i] == 0 then
				local cs = cand[i]
				for k = 1, #cs do
					local d = D(cur, cs[k])
					if not bestD or d < bestD then bestNode, bestSpot, bestD = i, cs[k], d end
				end
			end
		end
		if not bestNode then return nil end -- (a loop: Acyclic said no)
		placed[bestNode], seq[step], sp[bestNode], cur = true, bestNode, bestSpot, bestSpot
		for _, s in ipairs(succs[bestNode]) do count[s] = count[s] - 1 end
	end

	-- The given order instead when it keeps the constraints and is as short (a good order stays).
	if given then
		local gseq, gsp = {}, {}
		for i = 1, n do gseq[i] = i end
		if BestSpots(gseq, gsp) <= BestSpots(seq, sp) + GAIN then
			seq, sp = gseq, gsp
		end
	end
	return seq, sp, Optimise(seq, sp)
end

-- A route for the plan's stops: { order = { stop, ... } (the same tables, each with .spot set to the
-- spot chosen), before = yards in the given order, after = yards in the route's } (from here when
-- given: { map, x, y }), or nil when there's nothing to do (no stop not done with a spot).
function Q.SuggestRoute(stops, here)
	if type(stops) ~= "table" then
		return nil
	end
	local list, cand, places, spotOf, known = {}, {}, {}, {}, {}
	local function index(spot)
		local k = known[spot]
		if k == nil then
			local place = Place(spot)
			if place then
				places[#places + 1] = place
				spotOf[#places] = spot
				k = #places
			else
				k = false
			end
			known[spot] = k
		end
		return k or nil
	end
	for _, stop in ipairs(stops) do
		if type(stop) == "table" and not stop.done and type(stop.spots) == "table" then
			local cs = {}
			for _, spot in ipairs(stop.spots) do
				cs[#cs + 1] = index(spot)
			end
			if #cs > 0 then
				list[#list + 1] = stop
				cand[#list] = cs
			end
		end
	end
	local n = #list
	if n == 0 then
		return nil
	end
	local hereAt = here and index(here)

	-- The given order's yards: each stop's own spot, else its nearest to the one before.
	local before, prev = 0, hereAt
	for i, stop in ipairs(list) do
		local k = stop.spot and index(stop.spot)
		if not k then
			local best
			for _, c in ipairs(cand[i]) do
				local d = prev and Yards(places[prev], places[c]) or 0
				if not best or d < best then best, k = d, c end
			end
		end
		before = before + (prev and Yards(places[prev], places[k]) or 0)
		prev = k
	end

	local preds, succs = Constraints(list, true)
	if not Acyclic(preds, succs, n) then
		preds, succs = Constraints(list, false)
	end
	local given = true
	for i = 1, n do
		for _, s in ipairs(succs[i]) do
			if s < i then given = false end
		end
	end
	local seq, sp, after = Solve(list, cand, places, hereAt, preds, succs, given)
	if not seq then
		return nil
	end
	local order = {}
	for i = 1, n do
		local stop = list[seq[i]]
		stop.spot = spotOf[sp[seq[i]]]
		order[i] = stop
	end
	return { order = order, before = math.floor(before + 0.5), after = math.floor(after + 0.5) }
end
