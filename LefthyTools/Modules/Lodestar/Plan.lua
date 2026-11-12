local _, ns = ...
local LT = ns.LT
local L = ns.L
local Q = ns.Lodestar or {}; ns.Lodestar = Q

-- The plan: the quests a player wants to do, in the order they choose (docs/lodestar.md, Plan). The
-- "+" on a quest's row adds it at the end (the quest list, My quests, a quest's details, Alt-click on
-- the map); the Plan tab (Views.lua) orders it, the companion (Small.lua) says where to go next, the
-- big window draws it on the zone map (Browser.lua). Kept per character:
-- LefthyToolsDB.lodestar.plans[GUID] = { list = { questID, ... }, route = { keys, spots, before, after } }
-- (route: a suggested route in use, Route.lua's Q.SuggestRoute; any change of the list drops it).
--   Q.PlanList(), Q.PlanHas(id), Q.PlanAdd(id), Q.PlanRemove(id), Q.PlanToggle(id), Q.PlanMove(id, index),
--   Q.PlanClear(), Q.PlanRev(), Q.PlanStops(), Q.PlanNext(), Q.PlanSuggest(), Q.PlanUseOrder(),
--   Q.PlanRouteInfo(), Q.PlanSkip(stop), Q.PlanStopText(stop, withQuest), Q.PlanBriefing(),
--   Q.OnPlanChanged(fn), Q.NewPlanButton(parent[, size]).
-- A stop: { quest, kind = "start" | "objective" | "end", index (objectives: which, the data's), label,
-- spots = { { map, x, y }, ... } (every giver, area or turn-in spot known: the data's own point tables,
-- shared), spot (the chosen one: the route's, else the nearest to the stop before it, else the first),
-- done, key ("quest:kind:index") }. A quest not taken: its giver, its objectives, its turn-in; taken,
-- the giver is done; its objectives done as my quest log says (ready: all); a stop without any spot is
-- left out. A quest turned in leaves the plan by itself (QUEST_TURNED_IN; one done before: when the
-- stops are made).
-- What it costs: the stops are made when asked and kept until the plan, the data, my progress or my
-- quest log changes (the events only note it, and are listened to only while the plan has quests and
-- Lodestar is on). Nothing per frame; the callbacks run on the next frame after an edit.

local EVENTS = { "QUEST_TURNED_IN", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED" }
local KIND_ORDER = { start = 1, objective = 2, ["end"] = 3 }
local GOOD_ENOUGH = 0.05 -- a route that saves less than this share (or 50 yards) isn't worth it
local EMPTY = {}

local P = { edits = 0, rev = 0, logSeen = 0, skipped = {}, callbacks = {} }

---------------------------------------------------------------------------
-- Where it's kept
---------------------------------------------------------------------------

-- This character's plan ({ list, route }); create: made when missing. Without saved variables or a
-- GUID (the game won't say): one for this session.
function P.Saved(create)
	local guid = UnitGUID and LT.Value(UnitGUID, "player")
	local db = LT.db
	if type(guid) ~= "string" or LT.IsSecret(guid) or type(db) ~= "table" then
		P.session = P.session or { list = {} }
		return P.session
	end
	if type(db.lodestar) ~= "table" then
		if not create then return nil end
		db.lodestar = {}
	end
	local root = db.lodestar
	if type(root.plans) ~= "table" then
		if not create then return nil end
		root.plans = {}
	end
	local plan = root.plans[guid]
	if type(plan) ~= "table" or type(plan.list) ~= "table" then
		if not create then return nil end
		plan = { list = {} }
		root.plans[guid] = plan
	end
	if not P.checked or P.checked ~= plan then -- (once: only quest IDs, each once)
		P.checked = plan
		local seen, list = {}, {}
		for _, id in ipairs(plan.list) do
			if type(id) == "number" and id > 0 and id == math.floor(id) and not seen[id] then
				seen[id] = true
				list[#list + 1] = id
			end
		end
		plan.list = list
		if plan.route ~= nil and (type(plan.route) ~= "table" or type(plan.route.keys) ~= "table") then
			plan.route = nil
		end
		P.Listen()
	end
	return plan
end

-- Where each quest is in the list: { [id] = i } (made again after an edit).
function P.Index()
	local plan = P.Saved(false)
	if P.indexFor ~= plan or P.indexAt ~= P.edits then
		P.index, P.indexFor, P.indexAt = {}, plan, P.edits
		for i, id in ipairs(plan and plan.list or EMPTY) do
			P.index[id] = i
		end
	end
	return P.index
end

---------------------------------------------------------------------------
-- Changes: the callbacks, the events
---------------------------------------------------------------------------

-- fn() on the next frame after the plan changed (several changes: once).
function Q.OnPlanChanged(fn)
	if type(fn) == "function" then
		P.callbacks[#P.callbacks + 1] = fn
	end
end

function P.Notify()
	if P.notifying then
		return
	end
	P.notifying = true
	C_Timer.After(0, function()
		P.notifying = false
		for _, fn in ipairs(P.callbacks) do
			LT.Guard("Lodestar.plan", fn)
		end
	end)
end

local events = CreateFrame("Frame")

-- The quest log's events, only while the plan has quests and Lodestar is on.
function P.Listen()
	local plan = P.Saved(false)
	local want = Q.module ~= nil and Q.module.enabled == true and plan ~= nil and plan.list[1] ~= nil
	if want == (P.listening == true) then
		return
	end
	P.listening = want
	for _, event in ipairs(EVENTS) do
		if want then
			events:RegisterEvent(event)
		else
			events:UnregisterEvent(event)
		end
	end
end

-- An edit: the stops are made again when asked, the callbacks run; dropRoute: a route in use goes
-- (the plan changed: back to the quest order, and the Plan tab says so).
function P.Edited(plan, dropRoute)
	if dropRoute and plan and plan.route then
		plan.route = nil
		P.dropped = true
	end
	P.edits = P.edits + 1
	P.rev = P.rev + 1
	P.Listen()
	P.Notify()
end

-- A quest turned in leaves the plan (its stops are done; a route in use stays).
function P.TurnedIn(id)
	local plan = P.Saved(false)
	local at = plan and P.Index()[id]
	if at then
		table.remove(plan.list, at)
		P.Edited(plan, false)
	end
end

events:SetScript("OnEvent", function(_, event, id)
	if event == "QUEST_TURNED_IN" and type(id) == "number" and not LT.IsSecret(id) then
		P.TurnedIn(id)
	end
	P.logSeen = P.logSeen + 1 -- (the stops are looked at again when asked)
end)

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	P.Listen()
end)
if Q.When then
	Q.When("enable", P.Listen)
	Q.When("disable", P.Listen)
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------

-- The plan's quests in order (a copy).
function Q.PlanList()
	local plan = P.Saved(false)
	local out = {}
	for i, id in ipairs(plan and plan.list or EMPTY) do
		out[i] = id
	end
	return out
end

function Q.PlanHas(id)
	return type(id) == "number" and P.Index()[id] ~= nil
end

-- Adds a quest at the end; true when it was added.
function Q.PlanAdd(id)
	id = tonumber(id)
	if not id or id <= 0 or id ~= math.floor(id) or Q.PlanHas(id) then
		return false
	end
	local plan = P.Saved(true)
	plan.list[#plan.list + 1] = id
	P.Edited(plan, true)
	return true
end

function Q.PlanRemove(id)
	local plan = P.Saved(false)
	local at = plan and type(id) == "number" and P.Index()[id]
	if not at then
		return false
	end
	table.remove(plan.list, at)
	P.Edited(plan, true)
	return true
end

-- In the plan or out of it; returns whether it's in now.
function Q.PlanToggle(id)
	if Q.PlanHas(id) then
		Q.PlanRemove(id)
		return false
	end
	return Q.PlanAdd(id)
end

-- Moves a quest to a place in the list (1 = first; beyond the ends: the end).
function Q.PlanMove(id, index)
	local plan = P.Saved(false)
	local at = plan and type(id) == "number" and P.Index()[id]
	index = tonumber(index)
	if not (at and index) then
		return false
	end
	index = math.max(1, math.min(#plan.list, math.floor(index)))
	if index == at then
		return false
	end
	table.remove(plan.list, at)
	table.insert(plan.list, index, id)
	P.Edited(plan, true)
	return true
end

function Q.PlanClear()
	local plan = P.Saved(false)
	if not plan then
		return
	end
	plan.list, plan.route = {}, nil
	P.dropped, P.skipped = nil, {}
	P.Edited(plan, false)
end

---------------------------------------------------------------------------
-- The stops
---------------------------------------------------------------------------

function P.Key(stop)
	return stop.quest .. ":" .. stop.kind .. ":" .. (stop.index or 0)
end

-- A spot as words, for the saved route ("1429:0.4200:0.6600").
function P.SpotId(spot)
	return ("%d:%.4f:%.4f"):format(tonumber(spot.map) or 0, tonumber(spot.x) or 0, tonumber(spot.y) or 0)
end

-- Every spot of some people (givers or enders: their points; an item that starts it: where it drops),
-- into spots, and each spot's name into names.
function P.PeopleSpots(people, spots, names)
	for _, who in ipairs(people or EMPTY) do
		if who.kind == "item" then
			for _, drop in ipairs(type(who.drops) == "table" and who.drops or EMPTY) do
				for _, p in ipairs(drop.points or EMPTY) do
					if p.map and p.x and p.y then
						spots[#spots + 1] = p
						names[p] = L["%s (drops from %s)"]:format(who.name or L["unknown"], drop.name or L["unknown"])
					end
				end
			end
		else
			for _, p in ipairs(who.points or EMPTY) do
				if p.map and p.x and p.y then
					spots[#spots + 1] = p
					names[p] = who.name or L["unknown"]
				end
			end
		end
	end
	return spots
end

-- An objective in words: "Kill 10 x Kobold Vermin", "Collect 8 x Gold Dust", "Use Wanted Poster" (the
-- quest log's name when it's in my log: the client's language).
function P.ObjectiveText(d, logged)
	local count = tonumber(logged and logged.need) or tonumber(d.count) or 0
	local name = logged and logged.name
	if not name and d.kind == "item" and d.id and C_Item and C_Item.GetItemNameByID then
		name = LT.Value(C_Item.GetItemNameByID, d.id)
		name = type(name) == "string" and name ~= "" and not LT.IsSecret(name) and name or nil
	end
	name = name or d.name or "?"
	if d.kind == "kill" then
		return count > 1 and L["Kill %d x %s"]:format(count, name) or L["Kill %s"]:format(name)
	elseif d.kind == "item" then
		return count > 1 and L["Collect %d x %s"]:format(count, name) or L["Collect %s"]:format(name)
	end
	return count > 1 and L["Use %d x %s"]:format(count, name) or L["Use %s"]:format(name)
end

-- One quest's stops, into out.
function P.QuestStops(out, id, q, status)
	local inLog = status == "active"
	local ready = inLog and C_QuestLog and LT.Value(C_QuestLog.IsComplete, id) == true
	local names = {}
	local spots = P.PeopleSpots(q.starts, {}, names)
	if spots[1] then
		out[#out + 1] = { quest = id, kind = "start", spots = spots, names = names, label = names[spots[1]], done = inLog }
	end
	local logged = {}
	if inLog then
		for _, o in ipairs(Q.LogObjectives(id)) do
			if o.data then
				logged[o.data] = o
			end
		end
	end
	local data = Q.Objectives and Q.Objectives(id)
	for i, d in ipairs(type(data) == "table" and data or EMPTY) do
		local areas = {}
		for _, source in ipairs(not d.provided and d.sources or EMPTY) do
			for _, p in ipairs(source.points or EMPTY) do
				if p.map and p.x and p.y then
					areas[#areas + 1] = p
				end
			end
		end
		if areas[1] then
			local o = logged[d]
			out[#out + 1] = { quest = id, kind = "objective", index = i, spots = areas, label = P.ObjectiveText(d, o),
				done = ready or (o ~= nil and o.done == true), have = o and o.have, need = o and o.need }
		end
	end
	names = {}
	spots = P.PeopleSpots(q.ends, {}, names)
	if spots[1] then
		out[#out + 1] = { quest = id, kind = "end", spots = spots, names = names, label = names[spots[1]], done = false }
	end
end

-- Where I am ({ map, x, y } on my zone; nil: the game won't say).
function P.Here()
	if not Q.HereZone then
		return nil
	end
	local zone, x, y = Q.HereZone()
	if zone and x and y then
		return { map = zone, x = x, y = y }
	end
end

-- How far apart two spots are, to choose: the route's yards when it's there, else on one map its
-- width counted 1.5 times (a zone's map is 3:2); nil: not comparable.
function P.Apart(a, b)
	if Q.RouteYards then
		local ok, yards = pcall(Q.RouteYards, a, b)
		if ok and type(yards) == "number" then
			return yards
		end
	end
	if a.map == b.map then
		return math.sqrt(((a.x - b.x) * 1.5) ^ 2 + (a.y - b.y) ^ 2) * 1000
	end
end

function P.Nearest(spots, from)
	if not from then
		return nil
	end
	local best, bestD
	for _, spot in ipairs(spots) do
		local d = P.Apart(from, spot)
		if d and (not bestD or d < bestD) then
			best, bestD = spot, d
		end
	end
	return best
end

-- The order: the quest order, or the route's (the stops it doesn't name: done ones first, the rest
-- after it, in the quest order).
function P.Order(plan, stops)
	local route = plan.route
	if not route then
		return stops
	end
	local byKey, used, out = {}, {}, {}
	for _, s in ipairs(stops) do
		byKey[s.key] = s
	end
	for _, key in ipairs(route.keys) do
		local s = byKey[key]
		if s and not used[s] then
			used[s] = true
			out[#out + 1] = s
		end
	end
	local head, tail = {}, {}
	for _, s in ipairs(stops) do
		if not used[s] then
			if s.done then head[#head + 1] = s else tail[#tail + 1] = s end
		end
	end
	for i = #head, 1, -1 do
		table.insert(out, 1, head[i])
	end
	for _, s in ipairs(tail) do
		out[#out + 1] = s
	end
	return out
end

-- Each stop's spot: the route's choice, else the nearest to the stop before it (the first: to me),
-- else the first; its label then that spot's person.
function P.Choose(plan, stops)
	local chosen = plan.route and type(plan.route.spots) == "table" and plan.route.spots or EMPTY
	local from = P.Here()
	for _, s in ipairs(stops) do
		local spot
		local want = chosen[s.key]
		if want then
			for _, candidate in ipairs(s.spots) do
				if not spot and P.SpotId(candidate) == want then
					spot = candidate
				end
			end
		end
		spot = spot or P.Nearest(s.spots, from) or s.spots[1]
		s.spot = spot
		if s.names and s.names[spot] then
			s.label = s.names[spot]
		end
		if not s.done then
			from = spot
		end
	end
end

-- The stops of the plan's quests, in order; a quest done (not a repeatable one) leaves the plan.
function P.Build(plan)
	local stops, gone = {}, nil
	for _, id in ipairs(plan.list) do
		local q = Q.Quest(id)
		local status = q and Q.StatusOf(id)
		if q and status == "done" and not q.repeatable then
			gone = gone or {}
			gone[#gone + 1] = id
		elseif q then
			local first = #stops + 1
			P.QuestStops(stops, id, q, status)
			for i = first, #stops do
				local s = stops[i]
				s.key = P.Key(s)
				if P.skipped[s.key] and not s.done then
					s.done, s.skipped = true, true
				end
			end
		end
	end
	for _, id in ipairs(gone or EMPTY) do
		local at = P.Index()[id]
		if at then
			table.remove(plan.list, at)
			P.edits = P.edits + 1
		end
	end
	if gone then
		P.Listen()
		P.Notify()
	end
	stops = P.Order(plan, stops)
	P.Choose(plan, stops)
	return stops
end

-- What makes the stops: the plan, the edits, my quest log, the data and my progress.
function P.CacheKey(plan, loaded)
	return tostring(plan) .. ":" .. P.edits .. ":" .. P.logSeen .. ":" .. tostring(loaded and Q.dataGen) .. ":" .. tostring(Q.progressGen)
end

-- The stops, made again when what they come from changed; the rev goes up when they look different.
function P.Fresh()
	local plan = P.Saved(false)
	local loaded = Q.IsLoaded ~= nil and Q.IsLoaded() == true and Q.Quest ~= nil
	if loaded and Q.Status then
		Q.Status(0) -- (the engine reads my progress first: a change moves Q.progressGen)
	end
	if P.stops and P.key == P.CacheKey(plan, loaded) then
		return P.stops
	end
	local stops = (loaded and plan and plan.list[1]) and P.Build(plan) or {}
	P.key = P.CacheKey(plan, loaded)
	P.stops = stops
	local sig = { tostring(plan), plan and plan.route and "r" or "-" }
	for _, s in ipairs(stops) do
		sig[#sig + 1] = s.key .. (s.done and "+" or "-") .. P.SpotId(s.spot)
	end
	sig = table.concat(sig, ",")
	if sig ~= P.sig then
		P.sig = sig
		P.rev = P.rev + 1
	end
	return stops
end

-- The ordered stops (the route's order when one is in use, else each quest's in the plan's order).
-- Shared: callers don't write into them.
function Q.PlanStops()
	return P.Fresh()
end

-- A number that changes whenever the plan or its stops change (compare it; don't poll it per frame).
function Q.PlanRev()
	P.Fresh()
	return P.rev
end

-- The first stop not done, and its place in Q.PlanStops(); nil: none.
function Q.PlanNext()
	for i, s in ipairs(P.Fresh()) do
		if not s.done then
			return s, i
		end
	end
end

-- Marks a stop done for now (until the next /reload or logout): the next one comes up.
function Q.PlanSkip(stop)
	local key = type(stop) == "table" and (stop.key or P.Key(stop)) or stop
	if type(key) ~= "string" or P.skipped[key] then
		return false
	end
	P.skipped[key] = true
	P.edits = P.edits + 1
	P.Notify()
	return true
end

---------------------------------------------------------------------------
-- A suggested route
---------------------------------------------------------------------------

-- Asks Route.lua for a route through the plan's stops from where I am (Q.SuggestRoute); in use from
-- then on (kept). Returns its answer, nil when it can't.
function Q.PlanSuggest()
	local plan = P.Saved(false)
	if not (plan and plan.list[1] and Q.SuggestRoute) then
		return nil
	end
	local before = plan.route
	plan.route = nil
	P.edits = P.edits + 1
	local stops = P.Fresh()
	local ok, result = pcall(Q.SuggestRoute, stops, P.Here())
	if not ok then
		geterrorhandler()(result)
	end
	if not (ok and type(result) == "table" and type(result.order) == "table" and result.order[1]) then
		plan.route = before
		P.edits = P.edits + 1
		return nil
	end
	local keys, spots = {}, {}
	for i, s in ipairs(result.order) do
		keys[i] = s.key or P.Key(s)
		if type(s.spot) == "table" then
			spots[keys[i]] = P.SpotId(s.spot)
		end
	end
	plan.route = { keys = keys, spots = spots, before = tonumber(result.before), after = tonumber(result.after) }
	P.dropped = nil
	P.Edited(plan, false)
	return result
end

-- Back to the quest order.
function Q.PlanUseOrder()
	local plan = P.Saved(false)
	P.dropped = nil
	if plan and plan.route then
		plan.route = nil
		P.Edited(plan, false)
	end
end

-- { active (a route in use), before, after (yards: the quest order's, the route's), saves (yards; 0
-- when it's no better), good (the quest order was good already), dropped (the plan changed since a
-- route was suggested: it went) }.
function Q.PlanRouteInfo()
	local plan = P.Saved(false)
	local route = plan and plan.route
	local info = { active = route ~= nil, dropped = P.dropped == true }
	if route then
		info.before, info.after = route.before, route.after
		local saves = (route.before or 0) - (route.after or 0)
		info.saves = math.max(0, saves)
		info.good = saves < 50 or saves < (route.before or 0) * GOOD_ENOUGH
	end
	return info
end

---------------------------------------------------------------------------
-- Words the windows share
---------------------------------------------------------------------------

-- A stop in words: "Pick up Wanted: Hogger at Marshal Dughan", "Kill 10 x Kobold Vermin", "Turn in at
-- Gryan Stoutmantle" (withQuest: "Turn in Wanted: Hogger at ...", an objective with " · <title>").
function Q.PlanStopText(stop, withQuest)
	local title = Q.Title(stop.quest)
	local label = stop.label or L["unknown"]
	if stop.kind == "start" then
		return L["Pick up %s at %s"]:format(title, label)
	elseif stop.kind == "end" then
		return withQuest and L["Turn in %s at %s"]:format(title, label) or L["Turn in at %s"]:format(label)
	end
	return withQuest and (label .. " · " .. title) or label
end

-- The plan in a few lines, for a briefing: { title, lines = { ... } } ("Next (2/14): ...", the zones it
-- covers, "5 quests · 14 stops"); nil without a plan.
function Q.PlanBriefing()
	local list = Q.PlanList()
	if not list[1] then
		return nil
	end
	local stops = Q.PlanStops()
	local lines = {}
	local stop, at = Q.PlanNext()
	if stop then
		local zone = Q.MapName(stop.spot.map)
		lines[#lines + 1] = L["Next (%d/%d): %s"]:format(at, #stops, Q.PlanStopText(stop, true)) .. (zone and (" · " .. zone) or "")
	elseif stops[1] then
		lines[#lines + 1] = L["Every stop of your plan is done."]
	end
	local zones, seen = {}, {}
	for _, s in ipairs(stops) do
		local name = not s.done and Q.MapName(s.spot.map)
		if name and not seen[name] then
			seen[name] = true
			zones[#zones + 1] = name
		end
	end
	if zones[1] then
		lines[#lines + 1] = L["Zones: %s"]:format(table.concat(zones, ", "))
	end
	lines[#lines + 1] = L["%d quests · %d stops"]:format(#list, #stops)
	return { title = L["Your plan"], lines = lines }
end

---------------------------------------------------------------------------
-- The "+" on a quest's row
---------------------------------------------------------------------------

local function PlanButtonEnter(self)
	if not self.quest then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if Q.PlanHas(self.quest) then
		GameTooltip:SetText(L["In your plan"], 0.37, 0.73, 0.28)
		GameTooltip:AddLine(L["Click: remove it from your plan"], 0.5, 0.75, 1)
	else
		GameTooltip:SetText(L["Add to plan"], 1, 0.82, 0)
		GameTooltip:AddLine(L["Click: add it to the end of your plan (the Plan tab)"], 0.5, 0.75, 1, true)
	end
	GameTooltip:Show()
end

local function PlanButtonLeave(self)
	if GameTooltip:IsOwned(self) then
		GameTooltip:Hide()
	end
end

local CHECK_ATLAS = "common-icon-checkmark"
local function SetPlanButton(self, id)
	self.quest = id
	if not id then
		self:Hide()
		return
	end
	local has = Q.PlanHas(id)
	if has and C_Texture and LT.Value(C_Texture.GetAtlasInfo, CHECK_ATLAS) then
		self.Icon:SetAtlas(CHECK_ATLAS)
	else
		self.Icon:SetTexture(has and "Interface\\RaidFrame\\ReadyCheck-Ready" or "Interface\\Buttons\\UI-PlusButton-Up")
	end
	self.Icon:SetAlpha(has and 1 or 0.85)
	self.has = has
	self:Show()
end

-- A small Button: "+" (Add to plan) or a check (In your plan; a click removes it). b:SetQuest(id)
-- (nil: hidden).
function Q.NewPlanButton(parent, size)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size or 16, size or 16)
	b.Icon = b:CreateTexture(nil, "ARTWORK")
	b.Icon:SetAllPoints()
	b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	b.SetQuest = SetPlanButton
	b:SetScript("OnEnter", PlanButtonEnter)
	b:SetScript("OnLeave", PlanButtonLeave)
	b:SetScript("OnClick", function(self)
		if self.quest then
			Q.PlanToggle(self.quest)
			self:SetQuest(self.quest)
			if GameTooltip:IsOwned(self) then
				PlanButtonEnter(self)
			end
		end
	end)
	b:Hide()
	return b
end

-- For the tests: what's kept here.
function Q.PlanState()
	return P
end
