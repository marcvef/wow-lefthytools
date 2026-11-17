local _, ns = ...
local LT = ns.LT
local L = ns.L
local W = ns.WhyPoor or {}
ns.WhyPoor = W

-- The cheapest way to get an item (auction house, vendor, crafting it yourself, your bags) and what a recipe brings (W.Crafts).
-- docs/whypoor.md has the contract and the rules ("Crafting"); Chronicle's margins (Margins.lua's Compute) work their
-- numbers out here.
--
-- A way to get n of an item (Cr.Cost):
--   ah      the lowest buyout for one at the last scan that covered it, times n (an item never seen there, or none listed
--           then: no AH price);
--   vendor  what a vendor asks for one (seen at a merchant, else Data/Recipes.lua's list), times n; a vendor wins a tie;
--   craft   a recipe the crafter knows that makes it: n / what a craft makes crafts (a fraction: what's left over goes into
--           the next craft, as when crafting over and over), its reagents each worked out the same way, at most DEPTH deep
--           and never through an item already being worked out above (the transmute circles); its time is the casts
--           (the spell's cast time plus OVERHEAD, each craft) of it and of every craft below it;
--   bags    (only when asked for) what the bags hold, at what it would sell for (P.Best: what you give up by using it);
--           the rest another way ("mixed"). Each item in the bags is used once in one answer.
-- The cheapest way wins among the ones with every price known; one missing a price only when there's no other (then
-- complete is false and total isn't a cost). No price at all and no recipe: nil.
--
-- Prices come from W.Prices (P.Get, P.VendorBuy, P.Vendor, P.AHSale, P.Best) and, while it isn't there, from Margins'
-- own (Mg.AHPrice, Mg.VendorPrice, Mg.SellPrice). Nothing here keeps state but caches: what a character knows and which
-- of its recipes makes what (by R.Revision), and Cr.Mine's list (by the prices' and the recipes' revisions), worked
-- out MINE_MS a call so a driver can spread it over frames.

local AH_CUT = 0.05
local OVERHEAD = 0.5          -- seconds a craft takes beyond its cast (the button, the next cast), as Margins counts it
local DEFAULT_CAST = 3        -- seconds, when the spell's cast time can't be read
local DEPTH = 4               -- crafted reagents at most this deep
local FEW = 5                 -- fewer listed on the AH than for this many crafts: "few"
local MINE_MS = 2             -- Cr.Mine works this long a call at most
local WAITING_AGAIN = 5       -- seconds: Cr.Mine's list with items' data still coming is worked out again after this
local EPSILON = 1e-6
local RANK = { yours = 5, forever = 4, prices = 3, classic = 2, estimate = 1 } -- (a lower rank: a weaker basis)
local EMPTY = {}

local Cr = {}
W.Crafts = Cr
Cr.OVERHEAD, Cr.DEFAULT_CAST, Cr.DEPTH, Cr.FEW, Cr.AH_CUT = OVERHEAD, DEFAULT_CAST, DEPTH, FEW, AH_CUT

local issecret = LT.IsSecret
local casts = {}   -- spell -> seconds
local known        -- { rev, byId = { [id] = { [spell] = true } }, mine = { key, set } }
local makers = setmetatable({}, { __mode = "k" }) -- a known set -> { rev, byItem = { [item] = { { recipe, line }, ... } } }
local mine         -- Cr.Mine's last list: { key, list, at, waiting }
local work         -- Cr.Mine's list being worked out: { key, todo, i, out, waiting }
local entries      -- Cr.MyEntries: { rev, id, list }

local function Number(v)
	return type(v) == "number" and not issecret(v) and v or nil
end

local function Clock()
	local ok, ms = pcall(debugprofilestop)
	return ok and type(ms) == "number" and ms or nil
end

local function Older(a, b)
	if not a then
		return b
	end
	return b and math.min(a, b) or a
end

-- The weaker of two bases (nil: none yet).
function Cr.Weaker(a, b)
	if not a then
		return b
	elseif not b then
		return a
	end
	return (RANK[b] or 0) < (RANK[a] or 0) and b or a
end

local function Recipes()
	return ns.Chronicle and ns.Chronicle.Recipes
end

---------------------------------------------------------------------------
-- Prices (W.Prices, Prices.lua: loaded before this file; Margins reads the same)
---------------------------------------------------------------------------

-- The auction house's lowest buyout for one at the last scan that covered it (nil: none listed then, or never seen),
-- how many were listed, when, whether it was ever seen there, and the friend whose data it is.
function Cr.AHBuy(item)
	local e = W.Prices.Get(item)
	if type(e) == "table" then
		return Number(e.low), Number(e.qty), Number(e.seen), true, type(e.friend) == "string" and e.friend or nil
	end
	return nil, nil, nil, false
end

-- What a vendor asks for one (nil: not sold by vendors we know) and whether a merchant was seen asking it.
function Cr.VendorBuy(item)
	local p, seen = W.Prices.VendorBuy(item)
	return Number(p), seen == true
end

-- What a vendor pays for one (0: vendors don't buy it), nil while the client doesn't know the item yet.
function Cr.VendorSell(item)
	return Number(W.Prices.Vendor(item))
end

-- What selling n on the auction house brings (P.AHSale: after the cut and the deposit lost on what doesn't sell),
-- nil: no price; and the price for one it assumes.
function Cr.AHSale(item, n)
	local copper, unit = W.Prices.AHSale(item, n)
	return Number(copper), Number(unit)
end

-- What n would sell for, the better way (P.Best): copper, "ah" or "vendor", when the AH price is from, its basis,
-- the friend whose price it is, and atLeast (true: the AH's price isn't known, so it may fetch more there). nil:
-- not known.
function Cr.SaleValue(item, n)
	local sale = Cr.AHSale(item, n)
	local _, _, seen, _, friend = Cr.AHBuy(item)
	local way, copper = W.Prices.Best(item, n)
	copper = Number(copper)
	if way == "ah" and copper then
		return copper, "ah", seen, "prices", friend
	elseif way == "vendor" and copper and (copper > 0 or sale) then
		return copper, "vendor", nil, "forever", nil, sale == nil
	end
	return nil
end

-- How many the bags hold.
function Cr.Have(item)
	local ok, n = pcall(C_Item.GetItemCount, item)
	return ok and Number(n) or 0
end

-- Seconds a cast takes (and whether the game said so).
function Cr.CastTime(spell)
	local seconds = casts[spell]
	if not seconds then
		local info = LT.Value(C_Spell.GetSpellInfo, spell)
		local ms = type(info) == "table" and Number(info.castTime)
		if ms and ms >= 0 then
			seconds = ms / 1000
			casts[spell] = seconds
		end
	end
	return seconds or DEFAULT_CAST, seconds ~= nil
end

-- The prices' and the recipes' revision together (for caches).
function Cr.Revision()
	local R = Recipes()
	return (Number(W.Prices.Revision()) or 0) .. ":" .. (R and R.Revision() or 0)
end

---------------------------------------------------------------------------
-- Who knows what
---------------------------------------------------------------------------

-- The character I play, as R.People has it.
function Cr.MyId()
	local C = ns.Chronicle
	return "me:" .. tostring(C and C.CurrentKey and C.CurrentKey())
end

-- The smelting spells I know (Mining's: Chronicle records only the crafting lines, so they're asked of
-- the game, for the character I play only): a sorted list.
function Cr.MySmelting()
	local R = Recipes()
	local out = {}
	for _, recipe in ipairs(R and R.Smelting and R.Smelting() or EMPTY) do
		local id, has = recipe.spell, false
		if C_SpellBook and C_SpellBook.IsSpellKnown then
			local ok, yes = pcall(C_SpellBook.IsSpellKnown, id)
			has = ok and yes == true
		end
		if not has and IsPlayerSpell then
			local ok, yes = pcall(IsPlayerSpell, id)
			has = ok and yes == true
		end
		if has then
			out[#out + 1] = id
		end
	end
	return out
end

-- Every recipe a character (R.People's id) knows, of all its professions: { [spell] = true }. The character I
-- play: with the smelting spells I know (one set per what's known, so a newly learnt one counts).
function Cr.KnownOf(id)
	local set = Cr.KnownOfLines(id)
	if id ~= Cr.MyId() then
		return set
	end
	local smelt = Cr.MySmelting()
	if not (smelt[1] and known) then
		return set
	end
	local key = table.concat(smelt, ",")
	local had = known.mine
	if had and had.key == key and had.base == set then
		return had.set
	end
	local with = {}
	for spell in pairs(set) do
		with[spell] = true
	end
	for _, spell in ipairs(smelt) do
		with[spell] = true
	end
	known.mine = { key = key, base = set, set = with }
	return with
end

-- Of the crafting lines (Chronicle's record of a character's recipes).
function Cr.KnownOfLines(id)
	local R = Recipes()
	local data = ns.RecipeData
	if not (R and data) then
		return EMPTY
	end
	local rev = R.Revision()
	if not known or known.rev ~= rev then
		known = { rev = rev, byId = {} }
	end
	local set = known.byId[id]
	if not set then
		set = {}
		for _, line in ipairs(data.order or EMPTY) do
			for _, who in ipairs(R.People(line)) do
				if who.id == id then
					for spell in pairs(who.known or EMPTY) do
						set[spell] = true
					end
				end
			end
		end
		known.byId[id] = set
	end
	return set
end

-- Of a known set, which recipes make what: { [item] = { { recipe, line }, ... } } (by spell).
function Cr.MakersIn(set)
	local R = Recipes()
	if not R then
		return EMPTY
	end
	local rev = R.Revision()
	local x = makers[set]
	if x and x.rev == rev then
		return x.byItem
	end
	local byItem = {}
	for spell in pairs(set) do
		local recipe, line = R.RecipeOf(spell)
		if recipe and recipe.item and recipe.reagents and recipe.reagents[1] then
			local list = byItem[recipe.item]
			if not list then
				list = {}
				byItem[recipe.item] = list
			end
			list[#list + 1] = { recipe = recipe, line = line }
		end
	end
	for _, list in pairs(byItem) do
		table.sort(list, function(a, b) return a.recipe.spell < b.recipe.spell end)
	end
	makers[set] = { rev = rev, byItem = byItem }
	return byItem
end

---------------------------------------------------------------------------
-- The cheapest way
---------------------------------------------------------------------------

-- What one answer works with: the crafter's recipes by item, the bags (used: how many of each this answer took
-- already), the items being worked out above (no circles).
function Cr.NewContext(opts)
	local set = opts.who
	if type(set) ~= "table" then
		local crafter = opts.crafter
		if type(crafter) == "table" then
			set = crafter.id and Cr.KnownOf(crafter.id) or crafter.known
		end
		set = set or Cr.KnownOf(Cr.MyId())
	end
	return { makers = Cr.MakersIn(set or EMPTY), bags = opts.bags == true, used = {}, visiting = {} }
end

local function Copy(t)
	local c = {}
	for k, v in pairs(t) do
		c[k] = v
	end
	return c
end

-- The better of two answers: every price known beats a price missing, then the lower total; a tie: the first.
function Cr.Better(a, b)
	if not a then
		return b
	elseif not b then
		return a
	elseif a.complete ~= b.complete then
		return a.complete and a or b
	end
	return b.total < a.total - EPSILON and b or a
end

-- Bought: the cheaper of the AH and a vendor (a vendor on a tie), or nil (no price).
function Cr.Buy(item, n)
	local vendor, seen = Cr.VendorBuy(item)
	local ah, q, t, _, friend = Cr.AHBuy(item)
	if vendor and not (ah and ah < vendor) then
		return { item = item, n = n, total = vendor * n, unit = vendor, how = "vendor", complete = true,
			basis = seen and "yours" or "forever", seconds = 0, castKnown = true }
	elseif ah then
		return { item = item, n = n, total = ah * n, unit = ah, how = "ah", complete = true, basis = "prices", oldest = t,
			friend = friend, q = q, few = (q or 0) < n * FEW, seconds = 0, castKnown = true }
	end
end

-- Crafted with one recipe: its reagents worked out below it.
function Cr.Crafted(ctx, item, n, entry, depth)
	local recipe = entry.recipe
	local yield = (recipe.count or 0) > 0 and recipe.count or 1
	local crafts = n / yield
	local cast, castKnown = Cr.CastTime(recipe.spell)
	local r = { item = item, n = n, how = "craft", recipe = { spell = recipe.spell, line = entry.line, yield = yield, data = recipe },
		crafts = crafts, parts = {}, total = 0, complete = true, seconds = crafts * (cast + OVERHEAD), castKnown = castKnown,
		mayVary = yield > 1 }
	ctx.visiting[item] = true
	for i, need in ipairs(recipe.reagents) do
		local part = Cr.Get(ctx, need.item, need.n * crafts, depth - 1)
		if part then
			r.total = r.total + (part.total or 0)
			r.complete = r.complete and part.complete
			r.oldest = Older(r.oldest, part.oldest)
			r.basis = Cr.Weaker(r.basis, part.basis)
			r.seconds = r.seconds + (part.seconds or 0)
			r.castKnown = r.castKnown and part.castKnown ~= false
			r.friend = r.friend or part.friend
			r.few = r.few or part.few
			r.mayVary = r.mayVary or part.mayVary == true
		else
			part = { item = need.item, n = need.n * crafts, complete = false, seconds = 0 }
			r.complete = false
		end
		r.parts[i] = part
	end
	ctx.visiting[item] = nil
	r.unit = r.total / n
	return r
end

-- The cheapest way without what the bags hold of this item (its reagents may still come from the bags).
function Cr.Way(ctx, item, n, depth)
	local best = Cr.Buy(item, n)
	if depth >= 1 and not ctx.visiting[item] then
		local start, bestUsed = ctx.used, ctx.used
		for _, entry in ipairs(ctx.makers[item] or EMPTY) do
			ctx.used = Copy(start)
			local c = Cr.Crafted(ctx, item, n, entry, depth)
			if Cr.Better(best, c) == c then
				best, bestUsed = c, ctx.used
			end
		end
		ctx.used = bestUsed
	end
	return best
end

-- The cheapest way, the bags too when the answer counts them.
function Cr.Get(ctx, item, n, depth)
	local have = ctx.bags and math.max(0, math.floor(Cr.Have(item) - (ctx.used[item] or 0))) or 0
	local k = math.min(have, n)
	local value, way, seen, basis, friend, atLeast
	if k > 0 then
		value, way, seen, basis, friend, atLeast = Cr.SaleValue(item, k)
	end
	if not value or atLeast then
		return Cr.Way(ctx, item, n, depth)
	end
	local start = ctx.used
	ctx.used = Copy(start)
	local without = Cr.Way(ctx, item, n, depth)
	local usedWithout = ctx.used
	ctx.used = Copy(start)
	ctx.used[item] = (ctx.used[item] or 0) + k
	local rest = k < n and Cr.Way(ctx, item, n - k, depth) or nil
	local with = { item = item, n = n, how = rest and "mixed" or "bags", total = value + (rest and rest.total or 0),
		bags = { n = k, total = value, way = way }, rest = rest, complete = not rest or rest.complete,
		basis = Cr.Weaker(basis, rest and rest.basis), oldest = Older(seen, rest and rest.oldest), friend = friend or rest and rest.friend,
		seconds = rest and rest.seconds or 0, castKnown = not rest or rest.castKnown ~= false, few = rest and rest.few,
		mayVary = rest ~= nil and rest.mayVary == true }
	with.unit = with.total / n
	if Cr.Better(with, without) == with then
		return with
	end
	ctx.used = usedWithout
	return without
end

-- The cheapest way to get n of an item (docs/whypoor.md, Crafts): a table, or nil when no way is known.
function Cr.Cost(item, n, opts)
	opts = opts or EMPTY
	n = n or 1
	if not item or n <= 0 then
		return nil
	end
	return Cr.Get(Cr.NewContext(opts), item, n, opts.depth or DEPTH)
end

-- fn(step, level) for a cost and every step below it (a craft's parts, a mixed one's rest), level 0 at the top.
function Cr.Walk(c, fn, level)
	if not c then
		return
	end
	level = level or 0
	fn(c, level)
	if c.rest then
		Cr.Walk(c.rest, fn, level)
	end
	for _, part in ipairs(c.parts or EMPTY) do
		Cr.Walk(part, fn, level + 1)
	end
end

---------------------------------------------------------------------------
-- A recipe
---------------------------------------------------------------------------

-- What its reagents would sell for instead (the better way each), and whether every one of them is known (else
-- it's at least that much).
function Cr.ReagentsSale(recipe)
	local total, complete = 0, true
	for _, need in ipairs(recipe.reagents or EMPTY) do
		local value, _, _, _, _, atLeast = Cr.SaleValue(need.item, need.n)
		total = total + (value or 0)
		complete = complete and value ~= nil and not atLeast
	end
	return total, complete
end

-- The verdict: "craft", "sell reagents", "no", or nil (not known: a price it needs is missing), and its reason's key.
-- "sell reagents" and "no" need the product's AH price (without it, it might sell for more there); "sell reagents"
-- holds even with a reagent's price missing (that would only add to what they sell for).
function Cr.Verdict(r)
	local revenue
	if r.ahRevenue or r.vendorRevenue then
		revenue = math.max(r.ahRevenue or 0, r.vendorRevenue or 0)
	end
	r.revenue = revenue
	local full = r.ahRevenue ~= nil
	if full and r.reagentsSale > revenue + EPSILON then
		return "sell reagents", "reagents"
	elseif not r.profit then
		return nil, "price"
	elseif r.profit > EPSILON then
		return "craft", "profit"
	elseif full then
		return "no", "loss"
	end
	return nil, "price"
end

local WHY = {
	reagents = L["Its reagents sell for more than what it makes."],
	price = L["A price it needs is missing."],
	profit = L["It brings more than its reagents cost."],
	loss = L["It brings less than its reagents cost."],
}

-- A recipe's numbers: Margins' fields (Margins.lua's Compute) and the verdict. opts: recipe, line (else the data's
-- for spell), crafter (R.People's entry: its character's recipes; r.who), who, bags, depth (as Cr.Cost's).
function Cr.Recipe(spell, opts)
	opts = opts or EMPTY
	local recipe, line = opts.recipe, opts.line
	if not recipe then
		local R = Recipes()
		if R then
			recipe, line = R.RecipeOf(spell)
		end
	end
	if not (recipe and recipe.item) then
		return nil
	end
	local ctx = Cr.NewContext(opts)
	local depth = opts.depth or DEPTH
	local r = { spell = recipe.spell, line = line, recipe = recipe, who = opts.crafter, reagents = {}, cost = 0, complete = true,
		subSeconds = 0, subCastKnown = true, crafted = false }
	ctx.visiting[recipe.item] = true
	local covers = math.huge
	for i, need in ipairs(recipe.reagents or EMPTY) do
		local c = Cr.Get(ctx, need.item, need.n, depth)
		local _, q, t, scanned = Cr.AHBuy(need.item)
		local row = { item = need.item, n = need.n, have = Cr.Have(need.item), cost = c, q = q, t = t, scanned = scanned }
		if c then
			row.source, row.few = c.how, c.few
			if c.complete then
				row.unit = c.total / need.n
			end
			r.cost = r.cost + (c.total or 0)
			r.oldest = Older(r.oldest, c.oldest)
			r.basis = Cr.Weaker(r.basis, c.basis)
			r.subSeconds = r.subSeconds + (c.seconds or 0)
			r.subCastKnown = r.subCastKnown and c.castKnown ~= false
			r.friend = r.friend or c.friend
			r.few = r.few or c.few or nil
			r.mayVary = r.mayVary or c.mayVary == true
			Cr.Walk(c, function(step)
				if step.how == "craft" then
					r.crafted = true
				end
			end)
		end
		if not (c and c.complete) then
			r.complete = false
		end
		covers = math.min(covers, math.floor(row.have / math.max(1, need.n)))
		r.reagents[i] = row
	end
	r.covers = covers == math.huge and 0 or covers
	r.yield = (recipe.count or 0) > 0 and recipe.count or 1
	r.mayVary = r.mayVary or r.yield > 1
	local sell = Cr.VendorSell(recipe.item)
	r.waiting = sell == nil
	r.vendorEach = sell
	r.vendorRevenue = sell and sell > 0 and sell * r.yield or nil
	local low, qty, seen, scanned, friend = Cr.AHBuy(recipe.item)
	local sale, unit = Cr.AHSale(recipe.item, r.yield)
	r.ahEach, r.ahQty, r.ahScanned, r.ahT = unit or low, qty, scanned, seen
	r.ahRevenue = sale
	if r.complete then
		r.vendorProfit = r.vendorRevenue and r.vendorRevenue - r.cost
		r.ahProfit = r.ahRevenue and r.ahRevenue - r.cost
	end
	if r.ahProfit and not (r.vendorProfit and r.vendorProfit >= r.ahProfit) then
		r.best, r.profit = "ah", r.ahProfit
		r.oldest = Older(r.oldest, r.ahT)
		r.basis = Cr.Weaker(r.basis, "prices")
		r.friend = r.friend or friend
	elseif r.vendorProfit then
		r.best, r.profit = "vendor", r.vendorProfit
		r.basis = Cr.Weaker(r.basis, "forever")
	end
	-- Break even: what the craft brings at best (the auction house's after its cut, or a vendor's) is what all its
	-- reagents may cost together (breakEven); each reagent's maxUnit is the most one may cost, the others at their
	-- prices now (whole copper, rounded down: at that price it doesn't lose money).
	local revenue = (r.ahRevenue or r.vendorRevenue) and math.max(r.ahRevenue or 0, r.vendorRevenue or 0)
	if r.complete and revenue then
		r.breakEven = revenue
		for _, row in ipairs(r.reagents) do
			if row.unit and row.n > 0 then
				row.maxUnit = math.floor((revenue - (r.cost - row.unit * row.n)) / row.n + 1e-9)
			end
		end
	end
	local cast, castKnown = Cr.CastTime(recipe.spell)
	r.cast, r.castKnown = cast, castKnown
	r.seconds = cast + OVERHEAD + r.subSeconds
	r.perHour = r.profit and r.profit * 3600 / r.seconds
	r.reagentsSale, r.reagentsSaleComplete = Cr.ReagentsSale(recipe)
	r.verdict, r.reason = Cr.Verdict(r)
	r.why = WHY[r.reason]
	return r
end

---------------------------------------------------------------------------
-- This character's recipes
---------------------------------------------------------------------------

-- The recipes the character I play knows that make an item: { { spell, line, recipe, who }, ... } by spell.
function Cr.MyEntries()
	local R = Recipes()
	local data = ns.RecipeData
	if not (R and data) then
		return EMPTY
	end
	local rev, id = R.Revision(), Cr.MyId()
	if entries and entries.rev == rev and entries.id == id then
		return entries.list
	end
	local list = {}
	for _, line in ipairs(data.order or EMPTY) do
		for _, who in ipairs(R.People(line)) do
			if who.id == id then
				for spell in pairs(who.known or EMPTY) do
					local recipe = R.RecipeOf(spell)
					if recipe and recipe.item and recipe.reagents and recipe.reagents[1] then
						list[#list + 1] = { spell = spell, line = line, recipe = recipe, who = who }
					end
				end
			end
		end
	end
	table.sort(list, function(a, b) return a.spell < b.spell end)
	entries = { rev = rev, id = id, list = list }
	return list
end

local function ByHour(a, b)
	if (a.perHour ~= nil) ~= (b.perHour ~= nil) then
		return a.perHour ~= nil
	elseif a.perHour and a.perHour ~= b.perHour then
		return a.perHour > b.perHour
	end
	return a.spell < b.spell
end

-- This character's recipes worked out (Cr.Recipe each), best gold per hour first, those without a number last; and
-- whether that list is up to date. Works ms (MINE_MS) a call at most and goes on from there at the next call; until
-- it's done it answers the last list (empty the first time) and false. Kept until the prices or the recipes change
-- (a list with an item's data still coming: worked out again WAITING_AGAIN later).
function Cr.Mine(ms)
	local key = Cr.Revision() .. ":" .. Cr.MyId()
	if mine and mine.key == key and not (mine.waiting and GetTime() - mine.at >= WAITING_AGAIN) then
		return mine.list, true
	end
	if not work or work.key ~= key then
		work = { key = key, todo = Cr.MyEntries(), i = 1, out = {}, waiting = false }
	end
	local started, budget = Clock(), ms or MINE_MS
	while work.todo[work.i] do
		local e = work.todo[work.i]
		work.i = work.i + 1
		local r = Cr.Recipe(e.spell, { recipe = e.recipe, line = e.line, crafter = e.who })
		if r then
			work.out[#work.out + 1] = r
			work.waiting = work.waiting or r.waiting
		end
		if work.todo[work.i] and started and Clock() - started >= budget then
			return mine and mine.list or EMPTY, false
		end
	end
	table.sort(work.out, ByHour)
	mine = { key = key, list = work.out, at = GetTime(), waiting = work.waiting }
	work = nil
	return mine.list, true
end
