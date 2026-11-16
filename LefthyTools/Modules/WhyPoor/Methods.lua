local _, ns = ...
local LT = ns.LT
local L = ns.L
local W = ns.WhyPoor or {}
ns.WhyPoor = W

-- The ideas: every way of making money worked out for this character, ranked (W.Ideas).
-- docs/whypoor.md has the contract and "The ideas" every rule and number below, with why.
--
-- Nothing runs before I.Request(): it notes the wish and shows the driver frame, which on the next
-- frames works the ideas out a few ms a frame (one "unit" at a time: a mob, a zone, a quest, an
-- item), publishes them and hides. Events only count what changed (their counter is part of the key
-- the last run was for). I.Watch's callbacks run on the frame after the list changed.

local Value = LT.Value
local NONE = {}

local I = {}
W.Ideas = I
local X = {}  -- everything else, in one table (Lua 5.1's limits on locals and upvalues)
I.parts = X   -- (the tests)

---------------------------------------------------------------------------
-- The rules (docs/whypoor.md, The ideas: each one's reason)
---------------------------------------------------------------------------

X.BUDGET_MS = 3          -- a frame's work at most (debugprofilestop)
X.UNITS = 30             -- units a frame where there's no clock (tests), and between two looks at it
X.JOB_GAP = 5            -- seconds between the starts of two runs that only prices or bags moved
X.STALE = 3 * 3600       -- (P.STALE when Prices has it)
X.AH_CUT = 0.05          -- (P.AH_CUT when Prices has it)

-- Grinding
X.ABOVE = 1              -- mobs at most this many levels above you
X.MIN_SPAWNS = 8         -- spawns on the map at least
X.ZONE_MARGIN = 8        -- zones whose quest levels are this far from your window: not looked at
X.DOWNTIME = 20          -- seconds between two kills (loot, the next mob, resting): an estimate
X.SKIN_SECONDS = 2       -- seconds a skinning adds
X.EST_FIGHT = 35         -- seconds a fight takes when nothing of yours tells (an estimate, on the slow side)
X.PACE_MIN = 5           -- timed kills of a kind before its pace counts
X.PACE_BELOW = 3         -- a pace from this many levels below yours still counts (you only got stronger)
X.HPS_MIN = 10           -- timed kills (any kinds at your level) before your damage per second counts
X.OWN_KILLS = 30         -- kills of a kind before your own worth per kill counts
X.OWN_SKINS = 10         -- skinnings of a kind before your own skinning loot counts
X.MISSING_SHARE = 0.25   -- drops without any price making up this much of the chances: not ranked
X.SHARE_MIN = 0.05       -- a part below this share of an idea's worth doesn't lower its confidence
-- Gathering and fishing (estimates: nothing measures them)
X.NODES_PER_HOUR = 15
X.GATHER_MIN_NODES = 20
X.CATCHES_PER_HOUR = 120
-- The market
X.FLIP_SELLS = 0.5       -- a flip only for items that sell at least this likely
X.FLIP_MARGIN = 0.15     -- and bring this much more than they cost
X.FLIP_MIN = 100         -- and at least this much copper each
X.VENDOR_MIN = 20        -- a vendor flip: at least this much copper each
X.LIMITED_MARGIN = 0.15
X.LIMITED_MIN = 100
X.DE_MARGIN = 0.15
X.DE_MAX = 5             -- greens bought to disenchant, counted at most this many of one
-- How many of each kind are kept
X.KEEP = { grind = 6, gather = 3, fish = 2, pickpocket = 3, quest = 8, craft = 5, flip = 6, vendorflip = 5,
	limited = 5, disenchant = 4, sell = 1, learn = 4 }

X.BASIS_RANK = { yours = 1, forever = 2, prices = 3, classic = 4, estimate = 5 }
X.CONF_RANK = { high = 1, medium = 2, low = 3 }
X.CONF_OF = { "high", "medium", "low" }
X.CONF_FACTOR = { high = 1, medium = 0.75, low = 0.5 }
X.SKIN_LINE = { leather = 393, herb = 182, ore = 186 }
X.GATHER_LINE = { herb = 182, ore = 186 }
X.FIGHT_TYPES = { Critter = false, Totem = false, ["Non-combat Pet"] = false, ["Gas Cloud"] = false }

-- The zone maps looked at (uiMapIDs, outdoors, no capitals), with their quest levels from Lodestar's data
-- (LefthyTools_QuestData's zones, Forever's four new ones included; 0: not known): only a first sieve,
-- the mobs' own levels decide.
X.ZONES = {
	{ 1411, 2, 12 }, { 1412, 4, 30 }, { 1413, 12, 26 }, { 1438, 4, 12 }, { 1439, 12, 21 }, { 1440, 20, 32 },
	{ 1441, 28, 41 }, { 1442, 18, 28 }, { 1443, 33, 42 }, { 1444, 43, 50 }, { 1445, 35, 60 }, { 1446, 45, 60 },
	{ 1447, 48, 58 }, { 1448, 54, 56 }, { 1449, 52, 55 }, { 1450, 55, 60 }, { 1451, 59, 60 }, { 1452, 54, 60 },
	{ 2482, 0, 0 }, { 2652, 40, 43 }, { 1416, 33, 60 }, { 1417, 34, 42 }, { 1418, 37, 50 }, { 1419, 50, 60 },
	{ 1420, 4, 13 }, { 1421, 11, 21 }, { 1422, 53, 60 }, { 1423, 56, 60 }, { 1424, 24, 40 }, { 1425, 43, 51 },
	{ 1426, 2, 15 }, { 1427, 48, 60 }, { 1428, 52, 60 }, { 1429, 2, 10 }, { 1431, 23, 35 }, { 1432, 10, 30 },
	{ 1433, 15, 26 }, { 1434, 34, 50 }, { 1435, 35, 55 }, { 1436, 10, 22 }, { 1437, 21, 31 }, { 2548, 38, 44 },
	{ 2521, 4, 12 },
}

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

X.list = {}          -- the ideas published last
X.rev = 0            -- I.Revision
X.watchers = {}
X.inputs = 0         -- goes up with every event that changes who I am (level, skill, zone, group)
X.minor = 0          -- goes up when bags change or an item's name comes
X.bestiary = 0       -- goes up when the Bestiary's records change
X.lastKey = nil      -- the key the published list is for
X.job = nil          -- the run in progress
X.pending = false    -- I.Request asked for a run
X.notify = false     -- the watchers are told on the next frame
X.lastStart = nil    -- when the last run started (GetTime)
X.awaited = {}       -- item ID -> true: its name was asked for
X.cand = nil         -- the grinding candidates of the last zone scan, and the key they're for

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

function X.Clock()
	local ok, ms = pcall(debugprofilestop)
	return ok and type(ms) == "number" and ms or nil
end

function X.Now()
	return time()
end

function X.Stale()
	local P = W.Prices
	return P and type(P.STALE) == "number" and P.STALE or X.STALE
end

-- A call into another part: its first answer, nil if the part or function isn't there.
function X.Call(part, name, ...)
	local fn = part and part[name]
	if type(fn) ~= "function" then
		return nil
	end
	return fn(...)
end

-- Classic's grey level: mobs at it or below give no experience (Lodestar's rule, the game's).
function X.GreyLevel(level)
	if level <= 5 then return 0 end
	if level <= 39 then return level - 5 - math.floor(level / 10) end
	if level <= 59 then return level - 1 - math.floor(level / 5) end
	return level - 9
end

-- The levels of mobs worth grinding: from one above the grey level to X.ABOVE above yours.
function X.Window(level)
	return math.max(1, X.GreyLevel(level) + 1), level + X.ABOVE
end

-- The highest level a corpse can be skinned (herbed, mined) at with a skill: classic's rule, skill below
-- 100 needs (level - 10) * 10, from 100 on level * 5.
function X.SkinMax(skill)
	if skill < 100 then
		return math.floor(skill / 10) + 10
	end
	return math.floor(skill / 5)
end

-- The skill a corpse of a level needs (the same rule the other way round).
function X.SkinNeed(level)
	if level <= 10 then return 1 end
	if level < 20 then return (level - 10) * 10 end
	return level * 5
end

-- Two significant digits: what an estimate is worth saying.
function X.Round(c)
	if c < 100 then
		return math.floor(c + 0.5)
	end
	local scale = 10 ^ (math.floor(math.log10 and math.log10(c) or math.log(c) / math.log(10)) - 1)
	return math.floor(c / scale + 0.5) * scale
end

-- Copper as the game writes it (its coin icons), "~" and two digits when it's not sure.
function X.Money(c, approx)
	c = math.max(0, c or 0)
	if approx then
		c = X.Round(c)
	end
	c = math.floor(c + 0.5)
	local text
	if GetCoinTextureString then
		text = GetCoinTextureString(c)
	else
		local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
		text = (g > 0 and g .. "g " or "") .. ((g > 0 or s > 0) and s .. "s " or "") .. k .. "c"
	end
	return approx and "~" .. text or text
end

function X.Count(n, approx)
	if approx then
		return "~" .. X.Round(n)
	end
	return tostring(math.floor(n * 10 + 0.5) / 10)
end

-- An approximate basis: classic data and estimates are said with "~".
function X.Approx(basis)
	return basis == "classic" or basis == "estimate"
end

function X.Weaker(a, b)
	return (X.BASIS_RANK[a] or 5) >= (X.BASIS_RANK[b] or 5) and a or b
end

function X.New(kind, key)
	return { key = key, kind = kind, confidence = "high", basis = "yours", why = {}, how = {}, numbers = {}, items = {},
		warnings = {}, needs = nil }
end

function X.Basis(idea, basis)
	idea.basis = X.Weaker(idea.basis, basis)
end

function X.Conf(idea, conf)
	if (X.CONF_RANK[conf] or 3) > (X.CONF_RANK[idea.confidence] or 3) then
		idea.confidence = conf
	end
end

-- One step less sure.
function X.LessSure(idea)
	idea.confidence = X.CONF_OF[math.min(3, (X.CONF_RANK[idea.confidence] or 3) + 1)]
end

function X.Warn(idea, text)
	for _, w in ipairs(idea.warnings) do
		if w == text then return end
	end
	idea.warnings[#idea.warnings + 1] = text
end

-- A line of the working: label, the value as text, its basis (and the copper when it's money).
function X.Num(idea, label, value, basis, money)
	local text = value
	if type(value) == "number" then
		text = money and X.Money(value, X.Approx(basis)) or X.Count(value, X.Approx(basis))
	end
	idea.numbers[#idea.numbers + 1] = { label = label, value = text, basis = basis, copper = money and value or nil }
end

function X.Older(a, b)
	if not a then return b end
	if not b then return a end
	return math.min(a, b)
end

-- An item's name (the client's; asked for when it doesn't know it yet: the list is worked out again when
-- it comes), else "item 1234".
function X.ItemName(id)
	local name = C_Item and C_Item.GetItemInfo and Value(C_Item.GetItemInfo, ("item:%d"):format(id))
	if type(name) == "string" then
		return name
	end
	if not X.awaited[id] and C_Item and C_Item.RequestLoadItemDataByID then
		X.awaited[id] = true
		pcall(C_Item.RequestLoadItemDataByID, id)
		if X.events then
			X.events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
		end
	end
	return L["item %d"]:format(id)
end

function X.MapName(map)
	local info = map and C_Map and C_Map.GetMapInfo and Value(C_Map.GetMapInfo, map)
	return type(info) == "table" and info.name or tostring(map)
end

-- A mob's name: as the Bestiary saw it (the client's language), else the data's (English).
function X.MobName(creature, mob)
	local Bt = ns.Bestiary
	return Bt and Bt.NameOf and Bt.NameOf(creature) or mob and mob.name or ("#" .. creature)
end

function X.LineName(line)
	local names = ns.RecipeData and ns.RecipeData.names and ns.RecipeData.names[line]
	return names and names[ns.LOCALE == "deDE" and 2 or 1] or tostring(line)
end

---------------------------------------------------------------------------
-- What an item is worth (the better of a vendor and the auction house)
---------------------------------------------------------------------------

-- { each (copper, 0 when nothing's known), source ("ah"|"vendor"), vendor, ah, info (P.Get's), missing
-- (no price at all), noAH (never seen on the auction house) }, once per run. The auction house only
-- with a robust price that isn't unstable or of low confidence (P.AHSale: after the cut and deposits).
function X.Value(job, item)
	local v = job.values[item]
	if v then
		return v
	end
	local P = W.Prices
	local vendor = X.Call(P, "Vendor", item)
	local info = X.Call(P, "Get", item)
	local ah
	if type(info) == "table" and info.value and not info.unstable and info.confidence ~= "low" then
		ah = X.Call(P, "AHSale", item, 1)
	end
	v = { item = item, vendor = vendor, ah = ah, info = type(info) == "table" and info or nil, noAH = info == nil }
	if ah and ah > (vendor or 0) then
		v.each, v.source = ah, "ah"
	elseif vendor then
		v.each, v.source = vendor, "vendor"
	else
		v.each, v.missing = 0, true
	end
	job.values[item] = v
	return v
end

-- What a value adds to an idea: auction house prices weaken its basis to "prices", their confidence and
-- age lower it, a friend's are said; a vendor's price is the client's fact (it doesn't weaken it).
function X.UseValue(idea, v)
	if v.source ~= "ah" then
		return
	end
	local info = v.info
	X.Basis(idea, "prices")
	X.Conf(idea, info.confidence or "low")
	if info.seen then
		idea.oldest = X.Older(idea.oldest, info.seen)
		if X.Now() - info.seen > X.Stale() then
			if not idea.staleSaid then
				idea.staleSaid = true
				X.LessSure(idea)
			end
		end
	end
	if info.friend then
		X.Warn(idea, L["Prices from %s"]:format(info.friend))
	end
end

-- Parts of an idea's worth ({ v, per, worth }): the ones that matter (X.SHARE_MIN of the total) weigh on
-- its basis and confidence; how many have no price at all, and their share of the chances.
function X.Settle(idea, parts, total)
	local missing, missingChance, chance = 0, 0, 0
	for _, part in ipairs(parts) do
		chance = chance + part.per
		if part.v.missing then
			missing, missingChance = missing + 1, missingChance + part.per
		elseif total > 0 and part.worth / total >= X.SHARE_MIN then
			X.UseValue(idea, part.v)
		end
	end
	if missing > 0 then
		idea.missing = idea.missing or {}
		for _, part in ipairs(parts) do
			if part.v.missing then
				idea.missing[#idea.missing + 1] = part.v.item
			end
		end
		X.Warn(idea, L["%d items have no price yet: counted as nothing"]:format(missing))
		X.LessSure(idea)
	end
	return chance > 0 and missingChance / chance or 0
end

-- The items line of an idea, the most worth first, five at most.
function X.Items(idea, parts, source, scale)
	table.sort(parts, function(a, b)
		if a.worth ~= b.worth then return a.worth > b.worth end
		return a.v.item < b.v.item
	end)
	for i = 1, math.min(5, #parts) do
		local part = parts[i]
		local info = part.v.info
		idea.items[#idea.items + 1] = { item = part.v.item, n = part.per * (scale or 1), each = part.v.each,
			source = part.v.source or source, age = part.v.source == "ah" and info and info.seen or nil }
	end
end

---------------------------------------------------------------------------
-- Keys, the driver, the API
---------------------------------------------------------------------------

-- What everything the ideas rest on is at now, without asking the game (cheap): the events' count,
-- the Bestiary's, prices, recipes, Lodestar's data and progress, the money data.
function X.Key()
	local C, Q = ns.Chronicle, ns.Lodestar
	local R = C and C.Recipes
	return table.concat({ X.inputs, X.minor, X.bestiary, tostring(X.Call(W.Prices, "Revision") or 0),
		tostring(R and R.Revision and R.Revision() or 0), tostring(Q and Q.dataGen or 0), tostring(Q and Q.progressGen or 0),
		tostring(X.Call(W.Data, "Revision") or 0) }, ":")
end

function I.Get()
	return X.list, not X.job and not X.pending and X.lastKey ~= nil and X.lastKey == X.Key()
end

function I.Revision()
	return X.rev
end

function I.Watch(fn)
	X.watchers[#X.watchers + 1] = fn
end

function I.Request()
	X.Listen()
	X.pending = true
	X.Show()
end

function X.Show()
	if not X.frame then
		X.frame = CreateFrame("Frame")
		X.frame:Hide()
		X.frame:SetScript("OnUpdate", function() X.Tick() end)
	end
	X.frame:Show()
end

-- The events, registered with the first request: each only counts.
function X.Listen()
	if X.events then
		return
	end
	X.events = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD",
		"GROUP_ROSTER_UPDATE", "BAG_UPDATE_DELAYED", "LEARNED_SPELL_IN_SKILL_LINE" }) do
		pcall(X.events.RegisterEvent, X.events, event)
	end
	X.events:SetScript("OnEvent", function(_, event, id)
		if event == "GET_ITEM_INFO_RECEIVED" then
			if LT.IsSecret(id) or not X.awaited[id] then
				return
			end
			X.awaited[id] = nil
			if not next(X.awaited) then
				X.events:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
			end
			X.minor = X.minor + 1
		elseif event == "BAG_UPDATE_DELAYED" then
			X.minor = X.minor + 1
		else
			X.inputs = X.inputs + 1
		end
	end)
	local Bt = ns.Bestiary
	if Bt and Bt.OnChanged then
		Bt.OnChanged(function() X.bestiary = X.bestiary + 1 end)
	end
end

-- The driver: the watchers told (a frame after the list changed), a run started when asked and
-- something changed, the run's units within the frame's budget; hidden when there's nothing to do.
function X.Tick()
	if X.notify then
		X.notify = false
		for i, fn in ipairs(X.watchers) do
			LT.Guard("WhyPoor ideas watch " .. i, fn)
		end
	end
	if X.pending and not X.job then
		X.pending = false
		local key = X.Key()
		if key ~= X.lastKey then
			local wait = X.lastStart and X.lastStart + X.JOB_GAP - GetTime()
			if wait and wait > 0 and X.lastLevelKey == X.LevelKey() then
				X.pending = true
				X.frame:Hide()
				if not X.waiting then -- (one timer however often it's asked meanwhile)
					X.waiting = true
					C_Timer.After(wait, function()
						X.waiting = false
						X.Show()
					end)
				end
				return
			end
			X.Start(key)
		end
	end
	if X.job then
		if not LT.Guard("WhyPoor ideas", X.Work) then
			X.job = nil -- (it failed, or rests after failing: the next request starts again)
		end
	end
	if not (X.job or X.pending or X.notify) then
		X.frame:Hide()
	end
end

-- What makes waiting X.JOB_GAP wrong: a level, a place or a group of another kind.
function X.LevelKey()
	return tostring(Value(UnitLevel, "player")) .. ":" .. tostring(X.inputs)
end

X.PHASES = { "PhaseStart", "PhasePace", "PhaseZones", "PhaseGrind", "PhaseGather", "PhaseQuests", "PhaseMarket",
	"PhaseLimited", "PhaseCraft", "PhaseBags", "PhaseFinish" }

function X.Start(key)
	X.lastStart, X.lastLevelKey = GetTime(), X.LevelKey()
	X.job = { key = key, at = 1, c = {}, values = {}, ideas = {}, frames = 0, units = 0 }
end

-- One frame's part of the run: units until the budget is spent. True (for LT.Guard) when it went well.
function X.Work()
	local job = X.job
	job.frames = job.frames + 1
	local start, n = X.Clock(), 0
	while X.job == job do
		local phase = X.PHASES[job.at]
		if not phase then
			X.job = nil
			return true
		end
		if X[phase](job) then
			job.at, job.c = job.at + 1, {}
		end
		n, job.units = n + 1, job.units + 1
		if start then
			if (X.Clock() or start) - start >= X.BUDGET_MS then break end
		elseif n >= X.UNITS then
			break
		end
	end
	return true
end

---------------------------------------------------------------------------
-- The phases: each call does one unit and returns true when the phase is done
---------------------------------------------------------------------------

function X.PhaseStart(job)
	local ctx = W.Context()
	job.ctx = ctx
	job.data = X.Call(W.Data, "Load") == true
	job.level = ctx.level or 1
	job.lo, job.hi = X.Window(job.level)
	job.now = X.Now()
	local Bt = ns.Bestiary
	local db = Bt and Bt.Data and Bt.Data()
	job.own = {}
	for creature in pairs(db and type(db.mobs) == "table" and db.mobs or NONE) do
		job.own[#job.own + 1] = creature
	end
	job.hpsHealth, job.hpsSeconds, job.hpsKills = 0, 0, 0
	return true
end

-- A kind's health at a level from the classic database (between its lowest and highest in a line).
function X.HealthAt(known, level)
	local h = known and known.health
	if not h then return nil end
	if h[2] <= h[1] or level <= h[1] then return h[3] end
	if level >= h[2] then return h[4] end
	return h[3] + (h[4] - h[3]) * (level - h[1]) / (h[2] - h[1])
end

-- A kind's levels: the classic database's, else what the Bestiary saw.
function X.Levels(known, own)
	local h = known and known.health
	if h then
		return h[1], h[2]
	end
	local levels = own and type(own.levels) == "table" and own.levels
	if levels and levels[1] and levels[2] then
		return levels[1], levels[2]
	end
	if own and type(own.level) == "number" and own.level > 0 then
		return own.level, own.level
	end
end

-- A kind's own pace if it counts: seconds per fight and the level it's from.
function X.OwnPace(job, own)
	local Bt = ns.Bestiary
	local pace = own and type(own.pace) == "table" and own.pace
	if not (pace and Bt and Bt.Pace) or (pace[4] or 0) < X.PACE_MIN then
		return nil
	end
	local _, seconds, _, level = Bt.Pace(own)
	if not (seconds and seconds > 0 and level) or level > job.level or level < job.level - X.PACE_BELOW then
		return nil
	end
	return seconds, level
end

-- Your damage per second from your own paces at your level (the kinds whose health the database knows):
-- the health of what you killed over the time it took.
function X.PhasePace(job)
	local c = job.c
	c.i = (c.i or 0) + 1
	local creature = job.own[c.i]
	if not creature then
		if job.hpsKills >= X.HPS_MIN and job.hpsSeconds > 0 then
			job.hps = job.hpsHealth / job.hpsSeconds
		end
		return true
	end
	local Bt = ns.Bestiary
	local own = Bt.Mob(creature)
	local seconds = X.OwnPace(job, own)
	local known = seconds and Bt.Known and Bt.Known(creature)
	local lo, hi = X.Levels(known, own)
	local health = known and lo and X.HealthAt(known, (lo + hi) / 2)
	if health then
		local timed = own.pace[4]
		job.hpsHealth = job.hpsHealth + health * timed
		job.hpsSeconds = job.hpsSeconds + seconds * timed
		job.hpsKills = job.hpsKills + timed
	end
	return false
end

-- Whether a kind could be ground: not in an instance, hostile to you (or a neutral beast), a fighting
-- type, normal (an elite only in a group), its levels within your window. The kind's levels.
function X.Fit(job, creature)
	local Dt, Bt = W.Data, ns.Bestiary
	local mob = X.Call(Dt, "Mob", creature)
	if type(mob) ~= "table" or mob.instance then return nil end
	local ctx = job.ctx
	local react = ctx.faction == "Horde" and mob.reactH or mob.reactA
	if not (react == "hostile" or (react == "neutral" and mob.type == "Beast")) or not ctx.faction then return nil end
	if X.FIGHT_TYPES[mob.type] == false then return nil end
	if not (mob.rank == "normal" or (mob.rank == "elite" and ctx.grouped)) then return nil end
	local known = Bt and Bt.Known and Bt.Known(creature)
	local own = Bt and Bt.Mob and Bt.Mob(creature)
	local lo, hi = X.Levels(known, own)
	if not lo or lo < job.lo or hi > job.hi then return nil end
	return mob, known, lo, hi
end

-- The zones, their mobs: the kinds that fit, each on the map where most of it spawns (enough spawns).
-- Kept for the next run while your level, side, group and the data stay.
function X.PhaseZones(job)
	local c = job.c
	if not c.key then
		c.key = table.concat({ job.level, tostring(job.ctx.faction), tostring(job.ctx.grouped), tostring(job.data),
			#job.own, tostring(X.Call(W.Data, "Revision") or 0) }, ":")
		if X.cand and X.cand.key == c.key then
			job.cand = X.cand.list
			return true
		end
		c.z, c.list, c.found = 0, nil, {}
	end
	if not c.list or c.m > #c.list then
		repeat
			c.z = c.z + 1
			local zone = X.ZONES[c.z]
			if not zone then
				X.cand = { key = c.key, list = c.found }
				job.cand = c.found
				return true
			end
			local fits = zone[2] == 0 or (zone[3] >= job.lo - X.ZONE_MARGIN and zone[2] <= job.hi + X.ZONE_MARGIN)
			c.list = fits and X.Call(W.Data, "MobsOn", zone[1]) or NONE
			c.map, c.m = zone[1], 1
		until #c.list > 0
		return false
	end
	local creature = c.list[c.m]
	c.m = c.m + 1
	if not X.Fit(job, creature) then return false end
	local n, points = 0, {}
	for _, spot in ipairs(X.Call(W.Data, "Spots", creature) or NONE) do
		if spot.map == c.map then
			n = n + (spot.n or 0)
			points[#points + 1] = spot
		end
	end
	local had = c.found[creature]
	if n >= X.MIN_SPAWNS and (not had or n > had.n) then
		table.sort(points, function(a, b) return (a.n or 0) > (b.n or 0) end)
		c.found[creature] = { map = c.map, n = n, spots = points }
	end
	return false
end

-- What a kind brings a kill: coin, its drops, skinning (when you can, at your skill). From your own kills
-- once there are X.OWN_KILLS, else the classic database's. Returns the parts and totals.
function X.PerKill(job, idea, creature, mob, known, own, hi)
	local ctx = job.ctx
	local useOwn = own and (own.kills or 0) >= X.OWN_KILLS
	local said = known and known.items or NONE
	local coin, coinBasis, parts, rates = 0, "classic", {}, "classic"
	if useOwn then
		coin, coinBasis, rates = (own.money or 0) / own.kills, "yours", "yours"
		for id, item in pairs(own.items or NONE) do
			local listed = said[id]
			local quality = item[3] or 1
			-- (a quest's item left out; a green or better the database doesn't list for it: a world drop)
			if not (listed and listed[3]) and (quality < 2 or listed) then
				local per = (item[2] or 0) / own.kills
				local v = X.Value(job, id)
				parts[#parts + 1] = { v = v, per = per, worth = per * v.each }
			end
		end
	elseif known then
		if known.coin then
			coin = (known.coin[1] + known.coin[2]) / 2
		end
		for id, entry in pairs(said) do
			if not entry[3] then
				local v = X.Value(job, id)
				parts[#parts + 1] = { v = v, per = entry[1], worth = entry[1] * v.each }
			end
		end
	else
		return nil
	end
	local drops = 0
	for _, part in ipairs(parts) do drops = drops + part.worth end
	-- Skinning (herbs, ore from a corpse): the line it needs, your skill against the kind's highest level.
	local line = mob.skin and X.SKIN_LINE[mob.skin]
	local skill = line and ctx.professions[line]
	local skinParts, skin = {}, 0
	if skill and X.SkinMax(skill) >= hi then
		local ownSkins = own and (own.skinned or 0) >= X.OWN_SKINS
		local source = ownSkins and own.skins or known and known.skins or NONE
		for id, entry in pairs(source) do
			local per = ownSkins and (entry[2] or 0) / own.skinned or entry[1]
			local v = X.Value(job, id)
			skinParts[#skinParts + 1] = { v = v, per = per, worth = per * v.each }
			skin = skin + per * v.each
		end
		if #skinParts > 0 then
			idea.skinBasis = ownSkins and "yours" or "classic"
		end
	elseif line and not skill then
		idea.couldSkin = { line = line, need = X.SkinNeed(hi) }
	end
	return { coin = coin, coinBasis = coinBasis, rates = rates, parts = parts, drops = drops, skinParts = skinParts,
		skin = skin, own = useOwn }
end

-- How long a kill takes: your pace on this kind, else its health over your damage per second (your paces
-- on other kinds), else X.EST_FIGHT; plus X.DOWNTIME (and a skinning). Kills per hour, capped by the spawns.
function X.KillsPerHour(job, idea, creature, mob, known, own, lo, hi, cand, skinning)
	local fight, level = X.OwnPace(job, own)
	local basis = "yours"
	if fight then
		X.Num(idea, L["Fight"], L["%d s"]:format(math.floor(fight + 0.5)), "yours")
		if level ~= job.level then
			X.Warn(idea, L["Your pace is from level %d"]:format(level))
		end
	elseif mob.rank == "elite" then
		return nil -- (an elite only with your own pace on it: a group's speed isn't guessed)
	else
		basis = "estimate"
		local health = X.HealthAt(known, (lo + hi) / 2)
		if job.hps and health then
			fight = health / job.hps
			X.Num(idea, L["Fight"], L["%d s"]:format(math.floor(fight + 0.5)), "estimate")
			X.Warn(idea, L["Fight time worked out from its health and your pace on other mobs"])
		else
			fight = X.EST_FIGHT
			X.Num(idea, L["Fight"], L["%d s"]:format(fight), "estimate")
			X.Warn(idea, L["You haven't fought it: kills per hour are a careful guess"])
		end
	end
	local between = X.DOWNTIME + (skinning and X.SKIN_SECONDS or 0)
	X.Num(idea, L["Between kills"], L["%d s"]:format(between), "estimate")
	local kph = 3600 / (fight + between)
	local respawn = tonumber(mob.respawn)
	if respawn and respawn > 0 then
		local cap = cand.n * 3600 / respawn
		if kph > cap then
			kph = cap
			X.Warn(idea, L["Only %d spawns: about %d kills an hour at most"]:format(cand.n, math.floor(cap)))
		end
	end
	return kph, basis
end

function X.Place(map, spots, max)
	local points = {}
	for i = 1, math.min(max or 3, #spots) do
		local s = spots[i]
		points[i] = { x = s.x, y = s.y, r = s.r }
	end
	return { map = map, name = X.MapName(map), points = points }
end

-- A grinding idea for a kind (and, from it, picking its pockets and learning to skin it).
function X.PhaseGrind(job)
	local c = job.c
	if not c.list then
		c.list, c.i = {}, 0
		for creature in pairs(job.cand or NONE) do c.list[#c.list + 1] = creature end
		table.sort(c.list)
	end
	c.i = c.i + 1
	local creature = c.list[c.i]
	if not creature then return true end
	local cand = job.cand[creature]
	local mob, known, lo, hi = X.Fit(job, creature)
	if not mob then return false end
	local Bt = ns.Bestiary
	local own = Bt and Bt.Mob and Bt.Mob(creature)
	local ctx = job.ctx
	local idea = X.New("grind", "grind:" .. creature)
	local name = X.MobName(creature, mob)
	local k = X.PerKill(job, idea, creature, mob, known, own, hi)
	if not k then return false end
	local skinning = #k.skinParts > 0
	local kph, rateBasis = X.KillsPerHour(job, idea, creature, mob, known, own, lo, hi, cand, skinning)
	if not kph then return false end
	local perKill = k.coin + k.drops + k.skin
	idea.title = L["Kill %s"]:format(name)
	idea.sub = L["%s · level %s"]:format(X.MapName(cand.map), lo == hi and tostring(lo) or lo .. "-" .. hi)
	idea.place = X.Place(cand.map, cand.spots)
	idea.creature = creature
	X.Num(idea, L["Coin per kill"], k.coin, k.coinBasis, true)
	X.Num(idea, L["Drops per kill"], k.drops, k.rates, true)
	if skinning then
		X.Num(idea, L["Skinning per kill"], k.skin, idea.skinBasis, true)
	end
	X.Num(idea, L["Worth per kill"], perKill, X.Weaker(k.rates, idea.skinBasis or k.rates), true)
	X.Num(idea, L["Kills per hour"], kph, rateBasis)
	X.Num(idea, L["Spawns"], cand.n, "classic")
	idea.perHour = perKill * kph
	idea.perKill, idea.killsPerHour = perKill, kph
	X.Basis(idea, k.coinBasis)
	X.Basis(idea, k.rates)
	X.Basis(idea, rateBasis)
	if idea.skinBasis then X.Basis(idea, idea.skinBasis) end
	-- (the rest between kills is always an estimate: never quite sure)
	X.Conf(idea, "medium")
	if rateBasis == "estimate" or k.rates == "classic" then X.Conf(idea, rateBasis == "estimate" and "low" or "medium") end
	local all = {}
	for _, part in ipairs(k.parts) do all[#all + 1] = part end
	for _, part in ipairs(k.skinParts) do all[#all + 1] = part end
	local flagged = X.Settle(idea, all, k.drops + k.skin) >= X.MISSING_SHARE
	if flagged then
		idea.perHour = nil
	end
	X.Items(idea, all, "drop", kph)
	if k.rates == "classic" then
		X.Warn(idea, L["Classic data: Forever may differ"])
		X.Warn(idea, L["Drops counted one each: the data has no stack sizes"])
	end
	X.Warn(idea, L["World drops (random greens and better) are not counted"])
	if ctx.grouped then
		X.Warn(idea, L["In a group: loot is shared, kills go faster. These numbers are for playing alone."])
	end
	idea.why[#idea.why + 1] = L["Level %s, %d spawns on this map"]:format(lo == hi and tostring(lo) or lo .. "-" .. hi, cand.n)
	idea.how[#idea.how + 1] = L["Kill them where they spawn (Show on map) and loot every corpse."]
	if skinning then idea.how[#idea.how + 1] = L["Skin every corpse."] end
	if perKill >= 1 or flagged then -- (one worth nothing: not an idea, but its pockets and skins may be)
		job.ideas[#job.ideas + 1] = idea
	end
	X.Pickpocket(job, creature, mob, idea, kph)
	if idea.couldSkin and ctx.freePrimary then
		X.LearnSkin(job, creature, idea, known, own, kph)
	end
	return false
end

-- Picking a kind's pockets while grinding it (rogues): the classic database's pickpocket loot, as many
-- times an hour as you kill it. Coin from pockets isn't counted (the data has no rule for it).
function X.Pickpocket(job, creature, mob, grind, kph)
	if not job.ctx.canPick then return end
	local loot = X.Call(W.Data, "Pickpocket", creature)
	if type(loot) ~= "table" or not loot[1] then return end
	local idea = X.New("pickpocket", "pickpocket:" .. creature)
	local parts, worth = {}, 0
	for _, entry in ipairs(loot) do
		local per = (entry.chance or 0) * ((entry.min or 1) + (entry.max or entry.min or 1)) / 2
		local v = X.Value(job, entry.item)
		parts[#parts + 1] = { v = v, per = per, worth = per * v.each }
		worth = worth + per * v.each
	end
	if worth < 1 then return end
	idea.title = L["Pick the pockets of %s"]:format(X.MobName(creature, mob))
	idea.sub = L["On top of grinding them"]
	idea.place, idea.creature = grind.place, creature
	X.Num(idea, L["Per pocket"], worth, "classic", true)
	X.Num(idea, L["Pockets per hour"], kph, grind.basis == "estimate" and "estimate" or "yours")
	idea.perHour = worth * kph
	X.Basis(idea, "classic")
	X.Basis(idea, grind.basis)
	X.Conf(idea, grind.confidence)
	X.Conf(idea, "medium")
	if X.Settle(idea, parts, worth) >= X.MISSING_SHARE then idea.perHour = nil end
	X.Items(idea, parts, "pickpocket", kph)
	X.Warn(idea, L["Classic data: Forever may differ"])
	X.Warn(idea, L["Coin from pockets is not counted"])
	idea.how[#idea.how + 1] = L["Sneak up, pick its pocket, then kill it."]
	job.ideas[#job.ideas + 1] = idea
end

-- Learning to skin (herb, mine) a kind you grind: what it would add an hour once your skill is high
-- enough (needs says how high). Only with a free slot for a primary profession.
function X.LearnSkin(job, creature, grind, known, own, kph)
	local could = grind.couldSkin
	local ownSkins = own and (own.skinned or 0) >= X.OWN_SKINS
	local source = ownSkins and own.skins or known and known.skins or NONE
	local parts, worth = {}, 0
	for id, entry in pairs(source) do
		local per = ownSkins and (entry[2] or 0) / own.skinned or entry[1]
		local v = X.Value(job, id)
		parts[#parts + 1] = { v = v, per = per, worth = per * v.each }
		worth = worth + per * v.each
	end
	if worth < 1 then return end
	local key = "learn:" .. could.line
	local had = job.learn and job.learn[key]
	kph = 3600 / (3600 / kph + X.SKIN_SECONDS) -- (a skinning a kill)
	local perHour = worth * kph
	if had and (had.perHour or 0) >= perHour then return end
	local idea = X.New("learn", key)
	local name = X.LineName(could.line)
	idea.title = L["Learn %s"]:format(name)
	idea.sub = L["On top of grinding %s"]:format(X.MobName(creature))
	idea.needs = L["%s %d"]:format(name, could.need)
	idea.place = grind.place
	X.Num(idea, L["Per corpse"], worth, ownSkins and "yours" or "classic", true)
	X.Num(idea, L["Kills per hour"], kph, grind.basis == "estimate" and "estimate" or "yours")
	idea.perHour = perHour
	X.Basis(idea, ownSkins and "yours" or "classic")
	X.Basis(idea, grind.basis)
	X.Conf(idea, grind.confidence)
	if X.Settle(idea, parts, worth) >= X.MISSING_SHARE then idea.perHour = nil end
	X.Items(idea, parts, "drop", kph)
	if not ownSkins then X.Warn(idea, L["Classic data: Forever may differ"]) end
	idea.why[#idea.why + 1] = L["You have a free slot for a profession"]
	idea.how[#idea.how + 1] = L["Learn it from a trainer and raise it on easier mobs first."]
	job.learn = job.learn or {}
	if had then
		for i, other in ipairs(job.ideas) do
			if other == had then table.remove(job.ideas, i) break end
		end
	end
	job.learn[key] = idea
	job.ideas[#job.ideas + 1] = idea
end

-- Gathering and fishing, per zone: what a node (a catch) is worth at your skill, how many nodes the zone has
-- for it; per hour only with the estimates X.NODES_PER_HOUR and X.CATCHES_PER_HOUR. Zones whose quests start
-- above your level aren't safe to gather in: left out. Learning herbalism or mining: the best zone's nodes.
function X.PhaseGather(job)
	local c = job.c
	c.z = (c.z or 0) + 1
	local zone = X.ZONES[c.z]
	if not zone then return true end
	if zone[2] > job.level + 2 or not job.data then return false end
	local ctx = job.ctx
	local nodes = X.Call(W.Data, "Nodes", zone[1])
	if type(nodes) == "table" then
		for kind, line in pairs(X.GATHER_LINE) do
			local skill = ctx.professions[line]
			if skill then
				X.GatherIdea(job, zone[1], nodes, kind, line, skill, false)
			elseif ctx.freePrimary then
				X.GatherIdea(job, zone[1], nodes, kind, line, 300, true)
			end
		end
	end
	local fishing = ctx.professions[356] and X.Call(W.Data, "Fishing", zone[1])
	if type(fishing) == "table" and (fishing.skill or 0) <= ctx.professions[356] then
		X.FishIdea(job, zone[1], fishing)
	end
	return false
end

function X.GatherIdea(job, map, nodes, kind, line, skill, learn)
	local parts, byItem, count, worth, need = {}, {}, 0, 0, 0
	local spots = {}
	for _, node in ipairs(nodes) do
		if node.kind == kind and (node.skill or 0) <= skill and (node.n or 0) > 0 then
			local nodeWorth = 0
			for _, entry in ipairs(node.loot or NONE) do
				local per = (entry.chance or 0) * ((entry.min or 1) + (entry.max or entry.min or 1)) / 2
				local v = X.Value(job, entry.item)
				local part = byItem[entry.item]
				if not part then
					part = { v = v, per = 0, worth = 0 }
					byItem[entry.item] = part
					parts[#parts + 1] = part
				end
				part.per, part.worth = part.per + per * node.n, part.worth + per * v.each * node.n
				nodeWorth = nodeWorth + per * v.each
			end
			count, worth = count + node.n, worth + nodeWorth * node.n
			need = math.max(need, node.skill or 0)
			for _, s in ipairs(node.spots or NONE) do spots[#spots + 1] = s end
		end
	end
	if count < X.GATHER_MIN_NODES or worth <= 0 then return end
	for _, part in ipairs(parts) do part.per, part.worth = part.per / count, part.worth / count end
	local each = worth / count
	local key = learn and "learn:" .. line or "gather:" .. kind .. ":" .. map
	local idea = X.New(learn and "learn" or "gather", key)
	local perHour = each * X.NODES_PER_HOUR
	if learn then
		local had = job.learn and job.learn[key]
		if had and (had.perHour or 0) >= perHour then return end
		idea.title = L["Learn %s"]:format(X.LineName(line))
		idea.sub = L["Then gather in %s"]:format(X.MapName(map))
		idea.needs = L["%s %d"]:format(X.LineName(line), need)
		idea.why[#idea.why + 1] = L["You have a free slot for a profession"]
		idea.how[#idea.how + 1] = L["Learn it from a trainer and raise it on easier nodes first."]
		if had then
			for i, other in ipairs(job.ideas) do
				if other == had then table.remove(job.ideas, i) break end
			end
		end
		job.learn = job.learn or {}
		job.learn[key] = idea
	else
		idea.title = kind == "herb" and L["Gather herbs in %s"]:format(X.MapName(map)) or L["Mine in %s"]:format(X.MapName(map))
		idea.sub = L["%d nodes for your skill"]:format(count)
		idea.how[#idea.how + 1] = L["Ride a loop through the zone and gather every node you pass."]
	end
	table.sort(spots, function(a, b) return (a.n or 0) > (b.n or 0) end)
	idea.place = X.Place(map, spots, 5)
	X.Num(idea, L["Per node"], each, "classic", true)
	X.Num(idea, L["Nodes in the zone"], count, "classic")
	X.Num(idea, L["Nodes per hour"], X.NODES_PER_HOUR, "estimate")
	idea.perHour, idea.perNode, idea.nodes = perHour, each, count
	X.Basis(idea, "estimate")
	X.Conf(idea, "low")
	if X.Settle(idea, parts, each) >= X.MISSING_SHARE then idea.perHour = nil end
	X.Items(idea, parts, kind, X.NODES_PER_HOUR)
	X.Warn(idea, L["Nodes per hour is a guess: it depends on your route and on others gathering"])
	X.Warn(idea, L["Classic data: Forever may differ"])
	job.ideas[#job.ideas + 1] = idea
end

function X.FishIdea(job, map, fishing)
	local parts, worth = {}, 0
	for _, entry in ipairs(fishing.loot or NONE) do
		local v = X.Value(job, entry.item)
		local per = entry.chance or 0
		parts[#parts + 1] = { v = v, per = per, worth = per * v.each }
		worth = worth + per * v.each
	end
	if worth <= 0 then return end
	local idea = X.New("fish", "fish:" .. map)
	idea.title = L["Fish in %s"]:format(X.MapName(map))
	idea.sub = L["No fish get away at your skill"]
	idea.place = { map = map, name = X.MapName(map), points = {} }
	X.Num(idea, L["Per catch"], worth, "classic", true)
	X.Num(idea, L["Catches per hour"], X.CATCHES_PER_HOUR, "estimate")
	idea.perHour = worth * X.CATCHES_PER_HOUR
	X.Basis(idea, "estimate")
	X.Conf(idea, "low")
	if X.Settle(idea, parts, worth) >= X.MISSING_SHARE then idea.perHour = nil end
	X.Items(idea, parts, "fish", X.CATCHES_PER_HOUR)
	X.Warn(idea, L["Catches per hour is a guess"])
	X.Warn(idea, L["Classic data: Forever may differ"])
	idea.how[#idea.how + 1] = L["Fish in open water with a fishing pole."]
	job.ideas[#job.ideas + 1] = idea
end

-- Quests open to you now (Lodestar: available or in your log, within your levels) that pay: their money
-- and the reward worth the most (of a choice, the best one; items you get all of, all). Once each. Which
-- quests are open is kept while Lodestar's data, your progress and level stay (prices only redo the worth).
-- Nothing while Lodestar is switched off (its data isn't loaded for us then).
function X.PhaseQuests(job)
	local Q = ns.Lodestar
	local c = job.c
	if not c.stage then
		local m = LT.GetModule and LT:GetModule("lodestar")
		if not (Q and Q.Load and Q.Status and Q.Rewards and Q.Zones and Q.ZoneQuests) or (m and not m.enabled) then return true end
		local ok, loaded = pcall(Q.Load)
		if not (ok and loaded) then return true end
		c.key = table.concat({ tostring(Q.dataGen), tostring(Q.progressGen), job.level }, ":")
		if X.quests and X.quests.key == c.key then
			c.stage, c.open, c.i = "worth", X.quests.open, 0
			return false
		end
		c.ids, c.seen, c.open = {}, {}, {}
		for _, zone in ipairs(Q.Zones()) do
			for _, id in ipairs(Q.ZoneQuests(zone.map)) do
				if not c.seen[id] then
					c.seen[id] = true
					c.ids[#c.ids + 1] = id
				end
			end
		end
		c.stage, c.i = "open", 0
		return false
	end
	c.i = c.i + 1
	if c.stage == "open" then
		local id = c.ids[c.i]
		if not id then
			X.quests = { key = c.key, open = c.open }
			c.stage, c.i = "worth", 0
			return false
		end
		local status = Q.Status(id)
		if (status == "available" or status == "active") and (not Q.InRange or Q.InRange(id)) and Q.Rewards(id) then
			c.open[#c.open + 1] = id
		end
		return false
	end
	local id = c.open[c.i]
	if not id then return true end
	X.QuestIdea(job, Q, id, Q.Status(id))
	return false
end

function X.QuestIdea(job, Q, id, status)
	local r = Q.Rewards(id)
	if not r then return end
	local q = Q.Quest(id)
	local idea = X.New("quest", "quest:" .. id)
	local parts, best, items = {}, nil, 0
	for _, choice in ipairs(r.choice or NONE) do
		local v = X.Value(job, choice.id)
		local part = { v = v, per = choice.count or 1, worth = (choice.count or 1) * v.each }
		if not best or part.worth > best.worth then best = part end
	end
	if best then parts[#parts + 1] = best end
	for _, item in ipairs(r.items or NONE) do
		local v = X.Value(job, item.id)
		local part = { v = v, per = item.count or 1, worth = (item.count or 1) * v.each }
		parts[#parts + 1] = part
		items = items + part.worth
	end
	local money = r.money or 0
	local total = money + (best and best.worth or 0) + items
	if total < 1 and not (best and best.v.missing) then return end
	local basis = q and q.source == "forever" and "forever" or "classic"
	local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and Value(C_QuestLog.GetTitleForQuestID, id)
	idea.title = L["Quest: %s"]:format(type(title) == "string" and title or q and q.title or ("#" .. id))
	idea.sub = q and q.zoneName or ""
	idea.quest = id
	if money > 0 then X.Num(idea, L["Money"], money, basis, true) end
	if best then X.Num(idea, L["Best reward"], best.worth, basis, true) end
	if items > 0 then X.Num(idea, L["Reward items"], items, basis, true) end
	idea.once = total
	X.Basis(idea, basis)
	X.Conf(idea, basis == "forever" and "high" or "medium")
	if X.Settle(idea, parts, total) >= X.MISSING_SHARE and money == 0 then idea.once = nil end
	X.Items(idea, parts, "quest", 1)
	if basis == "classic" then X.Warn(idea, L["Classic data: Forever may differ"]) end
	if Q.Group and Q.Group(id) then X.Warn(idea, L["A group quest"]) end
	if job.level >= 60 then X.Warn(idea, L["At the highest level quests may pay more instead of experience: not counted"]) end
	local who = q and (status == "active" and q.ends or q.starts)
	who = who and who[1]
	if status == "active" then
		idea.how[#idea.how + 1] = L["It's in your quest log: finish it and turn it in."]
	else
		idea.how[#idea.how + 1] = who and who.name and L["Pick it up from %s."]:format(who.name) or L["Pick it up."]
	end
	if who and who.points and who.points[1] then
		local p = who.points[1]
		idea.place = { map = p.map, name = X.MapName(p.map), points = { { x = p.x, y = p.y, r = p.r } } }
	end
	if best and #(r.choice or NONE) > 1 then
		idea.why[#idea.why + 1] = L["Of the rewards to choose from, the one worth the most is counted"]
	end
	job.ideas[#job.ideas + 1] = idea
end

-- The auction house: items listed cheaper than they sell for (flip), cheaper than a vendor pays
-- (vendorflip), greens cheaper than what disenchanting them gives (disenchant). Only fresh listings.
function X.PhaseMarket(job)
	local c = job.c
	if not c.items then
		local items = X.Call(W.Prices, "Items")
		if type(items) ~= "table" then return true end
		c.items, c.i = items, 0
		return false
	end
	c.i = c.i + 1
	local item = c.items[c.i]
	if not item then return true end
	local P = W.Prices
	local info = P.Get(item)
	if type(info) ~= "table" or not info.low or not info.seen or job.now - info.seen > X.Stale() then return false end
	X.Flip(job, item, info)
	X.VendorFlip(job, item, info)
	X.DisenchantBuy(job, item, info)
	return false
end

-- A flip: bought at the cheapest listing, listed again at its usual price (the robust value: what its lowest
-- listing usually is), after the cut; the deposit lost on what doesn't sell only when how likely it sells is
-- known (my own auctions), else said. Only items whose listings go often (perDay: bought or taken back early,
-- from scans) and, when it's known, that sell likely. One each: only the cheapest listing's price is known,
-- not how many are listed at it.
function X.Flip(job, item, info)
	if not info.value or info.unstable or info.confidence == "low" or (info.perDay or 0) < 1
		or (info.sells and info.sells < X.FLIP_SELLS) then
		return
	end
	local P = W.Prices
	local sale = info.value * (1 - (P.AH_CUT or 0.05))
	local deposit = X.Call(P, "Deposit", item, 1)
	local depositCounted = info.sells ~= nil and deposit ~= nil
	if depositCounted then
		sale = info.sells * sale - (1 - info.sells) * deposit
	end
	local profit = sale - info.low
	if profit < X.FLIP_MIN or profit < info.low * X.FLIP_MARGIN then return end
	local n = 1
	local idea = X.New("flip", "flip:" .. item)
	idea.title = L["Buy and resell %s"]:format(X.ItemName(item))
	idea.sub = L["%s each now, sells for about %s"]:format(X.Money(info.low), X.Money(info.value))
	X.Num(idea, L["Buy at"], info.low, "prices", true)
	X.Num(idea, L["Sells for (after the cut)"], sale, "prices", true)
	X.Num(idea, L["Profit each"], profit, "prices", true)
	X.Num(idea, L["Listings gone early a day"], info.perDay, "prices")
	idea.once = profit * n
	idea.items[1] = { item = item, n = n, each = info.low, source = "ah", age = info.seen }
	idea.why[#idea.why + 1] = L["Counted for one: only the cheapest listing's price is known, not how many are at it"]
	if not depositCounted then
		X.Warn(idea, L["The deposit lost if it doesn't sell isn't counted"])
	end
	X.Basis(idea, "prices")
	X.Conf(idea, info.confidence)
	X.LessSure(idea) -- (the listing may be gone, and selling takes time)
	idea.oldest = info.seen
	if info.friend then X.Warn(idea, L["Prices from %s"]:format(info.friend)) end
	X.Warn(idea, L["The cheap listing may be gone since the scan"])
	idea.how[#idea.how + 1] = L["Buy the cheap ones, list them near the usual price."]
	job.ideas[#job.ideas + 1] = idea
end

function X.VendorFlip(job, item, info)
	local vendor = X.Call(W.Prices, "Vendor", item)
	if not vendor or vendor - info.low < X.VENDOR_MIN then return end
	local n = 1 -- (only the cheapest listing's price is known, not how many are at it)
	local idea = X.New("vendorflip", "vendorflip:" .. item)
	idea.title = L["Buy %s and sell it to a vendor"]:format(X.ItemName(item))
	idea.sub = L["%s each now, a vendor pays %s"]:format(X.Money(info.low), X.Money(vendor))
	X.Num(idea, L["Buy at"], info.low, "prices", true)
	X.Num(idea, L["A vendor pays"], vendor, "forever", true)
	idea.once = (vendor - info.low) * n
	idea.why[#idea.why + 1] = L["Counted for one: only the cheapest listing's price is known, not how many are at it"]
	idea.items[1] = { item = item, n = n, each = info.low, source = "ah", age = info.seen }
	X.Basis(idea, "prices")
	idea.oldest = info.seen
	if job.now - info.seen > 600 then X.LessSure(idea) end
	X.Warn(idea, L["The cheap listing may be gone since the scan"])
	idea.how[#idea.how + 1] = L["Buy them, sell them to any vendor."]
	job.ideas[#job.ideas + 1] = idea
end

-- What disenchanting one gives at your skill (each result at its value), nil without the skill or a price.
function X.DisenchantWorth(job, item)
	local ctx = job.ctx
	local skill = ctx.professions[333]
	if not skill then return nil end
	local de = X.Call(W.Data, "Disenchant", item)
	if type(de) ~= "table" or (de.skill or 0) > skill then return nil end
	local parts, worth = {}, 0
	for _, r in ipairs(de.results or NONE) do
		local per = (r.chance or 0) * ((r.min or 1) + (r.max or r.min or 1)) / 2
		local v = X.Value(job, r.item)
		if v.source ~= "ah" then return nil end -- (dust and essences sell on the auction house: without its price, no number)
		parts[#parts + 1] = { v = v, per = per, worth = per * v.each }
		worth = worth + per * v.each
	end
	return worth > 0 and worth or nil, parts
end

function X.DisenchantBuy(job, item, info)
	local worth, parts = X.DisenchantWorth(job, item)
	if not worth then return end
	local profit = worth - info.low
	if profit < X.FLIP_MIN or profit < info.low * X.DE_MARGIN then return end
	local n = 1 -- (only the cheapest listing's price is known, not how many are at it)
	local idea = X.New("disenchant", "disenchant:" .. item)
	idea.title = L["Buy %s to disenchant"]:format(X.ItemName(item))
	idea.sub = L["%s each now, disenchanted about %s"]:format(X.Money(info.low), X.Money(worth))
	X.Num(idea, L["Buy at"], info.low, "prices", true)
	X.Num(idea, L["Disenchanted"], worth, "classic", true)
	X.Num(idea, L["Profit each"], profit, "classic", true)
	idea.once = profit * n
	idea.why[#idea.why + 1] = L["Counted for one: only the cheapest listing's price is known, not how many are at it"]
	X.Basis(idea, "classic")
	X.Conf(idea, "medium")
	X.Settle(idea, parts, worth)
	idea.oldest = X.Older(idea.oldest, info.seen)
	X.Items(idea, parts, "disenchant", n)
	X.Warn(idea, L["Classic data: Forever may differ"])
	X.Warn(idea, L["The cheap listing may be gone since the scan"])
	idea.how[#idea.how + 1] = L["Buy them, disenchant them, sell what you get on the auction house."]
	job.ideas[#job.ideas + 1] = idea
end

-- Limited stock at vendors that sells for more on the auction house (a vendor of your side or neutral).
function X.PhaseLimited(job)
	local c = job.c
	if not c.items then
		local items = job.data and X.Call(W.Data, "LimitedItems")
		if type(items) ~= "table" then return true end
		c.items, c.i = items, 0
		return false
	end
	c.i = c.i + 1
	local item = c.items[c.i]
	if not item then return true end
	local info = X.Call(W.Prices, "Get", item)
	if type(info) ~= "table" or not info.value or info.unstable or info.confidence == "low" then return false end
	local sale, unit = X.Call(W.Prices, "AHSale", item, 1)
	if not sale then return false end
	local best, bestProfit
	for _, vendor in ipairs(X.Call(W.Data, "Limited", item) or NONE) do
		local npc = X.Call(W.Data, "Mob", vendor.npc)
		local react = type(npc) == "table" and (job.ctx.faction == "Horde" and npc.reactH or npc.reactA)
		if react ~= "hostile" and vendor.price then
			local profit = sale - vendor.price
			if not best or profit > bestProfit then best, bestProfit = vendor, profit end
		end
	end
	if not best or bestProfit < X.LIMITED_MIN or bestProfit < best.price * X.LIMITED_MARGIN then return false end
	local price, priceBasis = best.price, "classic"
	local seenPrice, seen = X.Call(W.Prices, "VendorBuy", item)
	if seen and seenPrice then -- (what a merchant asked when you saw it: Forever's own)
		price, priceBasis = seenPrice, "forever"
		bestProfit = sale - price
		if bestProfit < X.LIMITED_MIN or bestProfit < price * X.LIMITED_MARGIN then return false end
	end
	local n = best.stock or 1
	if info.perDay then n = math.max(1, math.min(n, math.floor(info.perDay))) end
	local idea = X.New("limited", "limited:" .. item)
	idea.title = L["Buy %s from %s"]:format(X.ItemName(item), best.name or "?")
	idea.sub = L["%s each there, sells for about %s"]:format(X.Money(price), X.Money(unit or info.value))
	X.Num(idea, L["Buy at"], price, priceBasis, true)
	X.Num(idea, L["Sells for (after the cut)"], sale, "prices", true)
	X.Num(idea, L["How many"], n, "classic")
	idea.once = bestProfit * n
	idea.items[1] = { item = item, n = n, each = price, source = "vendor" }
	if best.map then
		idea.place = { map = best.map, name = X.MapName(best.map), points = { { x = best.x, y = best.y } } }
	end
	X.Basis(idea, "classic")
	X.Conf(idea, info.confidence)
	X.Conf(idea, "medium")
	idea.oldest = info.seen
	if info.seen and job.now - info.seen > X.Stale() then X.LessSure(idea) end
	X.Warn(idea, L["Classic data: Forever may differ"])
	if best.restock then
		idea.why[#idea.why + 1] = L["Restocks about every %s"]:format(SecondsToTime and SecondsToTime(best.restock) or (best.restock .. " s"))
	end
	idea.how[#idea.how + 1] = L["Buy what the vendor has, list it on the auction house."]
	job.ideas[#job.ideas + 1] = idea
	return false
end

-- Your recipes that pay (Cr.Mine: verdict "craft"): the profit of a craft times how many sell a day.
function X.PhaseCraft(job)
	local Cr = W.Crafts
	local ok, list = pcall(X.Call, Cr, "Mine")
	if not ok then geterrorhandler()(list) end
	for i, e in ipairs(ok and type(list) == "table" and list or NONE) do
		if i > 20 then break end
		if type(e) == "table" and e.verdict == "craft" and (e.profit or 0) > 0 and e.spell then
			local product = e.item or (e.recipe and e.recipe.item)
			local info = product and X.Call(W.Prices, "Get", product)
			local perDay = type(info) == "table" and info.perDay or nil
			local n = perDay and math.max(1, math.floor(perDay)) or 1
			local idea = X.New("craft", "craft:" .. e.spell)
			local name = product and X.ItemName(product) or (e.name or ("#" .. e.spell))
			idea.title = L["Craft %s"]:format(name)
			idea.sub = perDay and L["About %s sell a day"]:format(X.Count(perDay, true)) or L["How many sell is not known"]
			X.Num(idea, L["Profit each"], e.profit, e.basis or "prices", true)
			X.Num(idea, L["How many"], n, perDay and "prices" or "estimate")
			idea.once = e.profit * n
			idea.spell, idea.oldest = e.spell, e.oldest
			X.Basis(idea, e.basis or "prices")
			if type(info) == "table" and info.confidence then X.Conf(idea, info.confidence) end
			if e.oldest and job.now - e.oldest > X.Stale() then X.LessSure(idea) end
			if not perDay then
				X.Conf(idea, "low")
				X.Warn(idea, L["How many sell is not known: one counted"])
			end
			if e.complete == false then
				idea.once, idea.missing = nil, { product }
				X.Warn(idea, L["Not every reagent has a price"])
			end
			idea.how[#idea.how + 1] = L["Craft it and list it on the auction house."]
			job.ideas[#job.ideas + 1] = idea
		end
	end
	return true
end

-- Your bags: what they'd fetch (W.Bags), and greens worth more disenchanted than sold (enchanters).
function X.PhaseBags(job)
	local Bags = W.Bags
	local ok, list, total = pcall(X.Call, Bags, "List")
	if not ok then
		geterrorhandler()(list)
		return true
	end
	if type(list) ~= "table" then return true end
	if type(total) == "number" and total > 0 then
		local idea = X.New("sell", "sell:bags")
		idea.basis = "forever" -- (what vendors pay: the client's prices)
		idea.title = L["Sell what's in your bags"]
		idea.sub = L["%d things you don't need"]:format(#list)
		idea.once = total
		local sorted = {}
		for _, entry in ipairs(list) do
			if not entry.keep and (entry.value or 0) > 0 then sorted[#sorted + 1] = entry end
			if entry.best == "ah" then X.Basis(idea, "prices") end
		end
		table.sort(sorted, function(a, b) return a.value > b.value end)
		for i = 1, math.min(5, #sorted) do
			local e = sorted[i]
			idea.items[i] = { item = e.item, n = e.count, each = (e.count or 0) > 0 and e.value / e.count or e.value, source = e.best }
		end
		X.Num(idea, L["All together"], total, idea.basis, true)
		idea.how[#idea.how + 1] = L["Vendor what a vendor pays more for, list the rest on the auction house."]
		job.ideas[#job.ideas + 1] = idea
	end
	if job.ctx.canDisenchant then
		local gain, worthAll, parts, count = 0, 0, {}, 0
		local idea = X.New("disenchant", "disenchant:bags")
		for _, entry in ipairs(list) do
			local worth, deParts = X.DisenchantWorth(job, entry.item)
			local n = entry.count or 1
			local sale = n > 0 and (entry.value or 0) / n or 0
			if worth and not entry.keep and worth > sale then
				gain, worthAll, count = gain + (worth - sale) * n, worthAll + worth * n, count + n
				for _, p in ipairs(deParts) do
					parts[#parts + 1] = { v = p.v, per = p.per * n, worth = p.worth * n }
				end
			end
		end
		if count > 0 and gain >= 1 then
			idea.title = L["Disenchant what's in your bags"]
			idea.sub = L["%d items are worth more disenchanted"]:format(count)
			X.Num(idea, L["Disenchanted"], worthAll, "classic", true)
			X.Num(idea, L["More than selling them"], gain, "classic", true)
			idea.once = worthAll
			X.Basis(idea, "classic")
			X.Conf(idea, "medium")
			X.Settle(idea, parts, worthAll)
			X.Items(idea, parts, "disenchant", 1)
			X.Warn(idea, L["Classic data: Forever may differ"])
			idea.how[#idea.how + 1] = L["Disenchant them, sell what you get on the auction house."]
			job.ideas[#job.ideas + 1] = idea
		end
	end
	return true
end

-- Ranking: per hour first (perHour lowered by confidence), then the once-ideas (the same way), then those
-- that need a price (no number). The best X.KEEP of each kind.
function X.Score(idea)
	return (idea.perHour or idea.once or 0) * (X.CONF_FACTOR[idea.confidence] or 0.5)
end

function X.Group(idea)
	if idea.perHour then return 1 end
	if idea.once then return 2 end
	return 3
end

function X.Rank(ideas)
	for _, idea in ipairs(ideas) do
		idea.score, idea.group = X.Score(idea), X.Group(idea)
	end
	table.sort(ideas, function(a, b)
		if a.group ~= b.group then return a.group < b.group end
		if a.score ~= b.score then return a.score > b.score end
		return a.key < b.key
	end)
	local out, kept = {}, {}
	for _, idea in ipairs(ideas) do
		local n = (kept[idea.kind] or 0) + 1
		if n <= (X.KEEP[idea.kind] or 3) then
			kept[idea.kind] = n
			out[#out + 1] = idea
			idea.rank = #out
		end
	end
	return out
end

-- What a list says: a change in it is a change the window shows.
function X.Signature(list)
	local parts = {}
	for i, idea in ipairs(list) do
		parts[i] = table.concat({ idea.key, tostring(math.floor(idea.perHour or -1)), tostring(math.floor(idea.once or -1)),
			idea.confidence, idea.basis, idea.title or "", idea.sub or "", table.concat(idea.warnings, "|"),
			tostring(idea.needs), tostring(idea.oldest) }, ";")
	end
	return table.concat(parts, "\n")
end

function X.PhaseFinish(job)
	for _, idea in ipairs(job.ideas) do
		if idea.oldest and job.now - idea.oldest > X.Stale() then
			X.Warn(idea, L["Oldest price: %s"]:format(LT.Ago(idea.oldest)))
		end
		local map = idea.place and idea.place.map
		if map and map == job.ctx.map then
			table.insert(idea.why, 1, L["In your zone"])
		end
	end
	local list = X.Rank(job.ideas)
	local signature = X.Signature(list)
	X.lastKey = job.key
	if signature ~= X.signature then
		X.list, X.signature = list, signature
		X.rev = X.rev + 1
		X.notify = true
	end
	return true
end
