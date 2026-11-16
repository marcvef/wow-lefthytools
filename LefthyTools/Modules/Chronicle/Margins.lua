local _, ns = ...
local LT = ns.LT
local C = ns.Chronicle
local M = C.module

-- Crafting margins (setting margins): what one of my recipes costs to make, what it brings, and gold per
-- hour, from auction house and vendor prices. The window and the buttons on Blizzard's profession window
-- and auction house are MarginsWindow.lua's; this file picks what to scan and works the numbers out
-- (C.Margins, Mg).
--
-- Prices come from WhyPoor?'s price engine (Modules/WhyPoor/Prices.lua, W.Prices; docs/whypoor.md): it keeps
-- every auction house price per realm and faction, merchants' prices and the scans; it runs while this
-- setting or the WhyPoor? module is on. Mg.AHPrice, Mg.VendorPrice and Mg.SellPrice read it, Mg.ScanRecipe and
-- Mg.ScanAll ask it to scan. (Margins' own saved prices, LefthyToolsDB.margins, went over to it once.)
-- A vendor-sold reagent no merchant has shown yet costs what Data/Recipes.lua's vendor list says.
--
-- The numbers of a recipe (Mg.Recipe):
--   a reagent's price is the cheaper of the AH (lowest buyout for one) and a vendor; reagents in my bags
--   count at that price too (what they'd sell for), and how many crafts they cover is said apart;
--   cost = the reagents' prices times how many it needs;
--   revenue: at a vendor its sell price times how many a craft makes (a range: the data's middle); on the AH
--   the lowest buyout for one times as many, less the AH's 5% cut (the deposit isn't counted);
--   profit = the better revenue minus the cost (vendor and AH each also have their own);
--   time per craft = the spell's cast time plus OVERHEAD; gold per hour = profit / time.
--
-- Scanning, only with the auction house open, never in a fight (the engine's rules): one recipe (its product and
-- the reagents no vendor sells) item by item; everything with a full scan (ReplicateItems: the whole auction
-- house) when the game allows one again, else item by item like a recipe, skipping prices fresher than FRESH
-- (so a scan that was stopped goes on where it was).

local AH_CUT = 0.05
local OVERHEAD = 0.5          -- seconds a craft takes beyond its cast (the button, the next cast)
local DEFAULT_CAST = 3        -- seconds, when the spell's cast time can't be read
local STALE = 3 * 3600        -- prices older than this are shown greyed
local FRESH = 30 * 60         -- a full scan by items skips prices younger than this
local FEW = 5                 -- fewer listed than for this many crafts: "few on the AH"

local Mg = {}
C.Margins = Mg

local issecret = LT.IsSecret
local mine, mineRev   -- Mg.MyRecipes, of that R.Revision
local casts = {}      -- spell -> seconds

local function Number(v)
	return type(v) == "number" and not issecret(v) and v or nil
end

-- The price engine (WhyPoor?'s Prices.lua loads after this file).
local function Prices()
	return ns.WhyPoor and ns.WhyPoor.Prices
end

function Mg.Enabled()
	local P = Prices()
	return M.enabled and M.db.margins and P ~= nil and P.running == true
end

function Mg.IsAHOpen()
	local P = Prices()
	return P ~= nil and P.IsOpen()
end

---------------------------------------------------------------------------
-- Prices
---------------------------------------------------------------------------

-- What a vendor asks for one: seen at a merchant, else the data's list; the second result says it was seen.
function Mg.VendorPrice(item)
	local P = Prices()
	if P then
		return P.VendorBuy(item)
	end
end

-- The AH's: { p (nil: none listed), q, t } or nil (never scanned).
function Mg.AHPrice(item)
	local P = Prices()
	return P and P.AHPrice(item) or nil
end

-- An item's sell price (copper; 0: vendors don't buy it), nil while the client doesn't have the item yet.
function Mg.SellPrice(item)
	local P = Prices()
	return P and P.Vendor(item) or nil
end

-- Seconds a cast takes (and whether the game said so).
function Mg.CastTime(spell)
	local known = casts[spell]
	if not known then
		local info = LT.Value(C_Spell.GetSpellInfo, spell)
		local ms = type(info) == "table" and Number(info.castTime)
		if ms and ms >= 0 then
			known = ms / 1000
			casts[spell] = known
		end
	end
	return known or DEFAULT_CAST, known ~= nil
end

local function InBags(item)
	local ok, n = pcall(C_Item.GetItemCount, item)
	return ok and Number(n) or 0
end

local function Older(a, b)
	if not a then
		return b
	end
	return b and math.min(a, b) or a
end

-- A recipe's numbers (the file's head says what they are): { spell, line, recipe, who, reagents = { { item, n,
-- unit, source ("ah", "vendor" or nil: no price), have, q, t, few }, ... }, cost, complete, covers, yield,
-- vendorEach, vendorRevenue, vendorProfit, ahEach, ahQty, ahScanned, ahRevenue, ahProfit, best ("vendor",
-- "ah"), profit, seconds, castKnown, perHour, oldest (the oldest AH price it uses), few, waiting (an item's
-- data hasn't come) }.
local function Compute(recipe, line, who)
	local r = { spell = recipe.spell, line = line, recipe = recipe, who = who, reagents = {}, cost = 0, complete = true }
	local covers = math.huge
	for i, need in ipairs(recipe.reagents or {}) do
		local vendor = Mg.VendorPrice(need.item)
		local e = Mg.AHPrice(need.item)
		local ah = e and e.p
		local row = { item = need.item, n = need.n, have = InBags(need.item), q = e and e.q, t = e and e.t, scanned = e ~= nil }
		if vendor and not (ah and ah < vendor) then
			row.unit, row.source = vendor, "vendor"
		elseif ah then
			row.unit, row.source = ah, "ah"
			r.oldest = Older(r.oldest, e.t)
			if (e.q or 0) < need.n * FEW then
				row.few, r.few = true, true
			end
		end
		if row.unit then
			r.cost = r.cost + row.unit * need.n
		else
			r.complete = false
		end
		covers = math.min(covers, math.floor(row.have / math.max(1, need.n)))
		r.reagents[i] = row
	end
	r.covers = covers == math.huge and 0 or covers
	r.yield = (recipe.count or 0) > 0 and recipe.count or 1
	local sell = recipe.item and Mg.SellPrice(recipe.item)
	r.waiting = recipe.item ~= nil and sell == nil
	r.vendorEach = sell
	r.vendorRevenue = sell and sell > 0 and sell * r.yield or nil
	local e = recipe.item and Mg.AHPrice(recipe.item)
	r.ahEach, r.ahQty, r.ahScanned, r.ahT = e and e.p, e and e.q, e ~= nil, e and e.t
	r.ahRevenue = r.ahEach and r.ahEach * r.yield * (1 - AH_CUT) or nil
	if r.complete then
		r.vendorProfit = r.vendorRevenue and r.vendorRevenue - r.cost
		r.ahProfit = r.ahRevenue and r.ahRevenue - r.cost
	end
	if r.ahProfit and not (r.vendorProfit and r.vendorProfit >= r.ahProfit) then
		r.best, r.profit = "ah", r.ahProfit
		r.oldest = Older(r.oldest, r.ahT)
	elseif r.vendorProfit then
		r.best, r.profit = "vendor", r.vendorProfit
	end
	local cast, known = Mg.CastTime(recipe.spell)
	r.seconds, r.castKnown = cast + OVERHEAD, known
	r.perHour = r.profit and r.profit * 3600 / r.seconds
	return r
end

---------------------------------------------------------------------------
-- My recipes
---------------------------------------------------------------------------

-- What my characters on this realm know that makes an item: { { spell, line, recipe, who, current }, ... }
-- (who: R.People's entry; a recipe two of them know: the one I play, else the best skill) and the same by
-- spell. Built again when R.Revision moves.
function Mg.MyRecipes()
	local R = C.Recipes
	if not (R and ns.RecipeData) then
		return {}, {}
	end
	local revision = R.Revision()
	if mine and mineRev == revision then
		return mine.list, mine.bySpell
	end
	local list, bySpell = {}, {}
	local realm, current = GetRealmName(), "me:" .. tostring(C.CurrentKey())
	for _, line in ipairs(ns.RecipeData.order or {}) do
		for _, who in ipairs(R.People(line)) do
			if who.mine and who.record and who.record.realm == realm then
				for spell in pairs(who.known or {}) do
					local recipe = R.RecipeOf(spell)
					if recipe and recipe.item and recipe.reagents[1] then
						local had = bySpell[spell]
						local isCurrent = who.id == current
						if not had then
							had = { spell = spell, line = line, recipe = recipe }
							bySpell[spell] = had
							list[#list + 1] = had
						end
						if not had.who or (isCurrent and not had.current) or (not had.current and (who.skill or 0) > (had.who.skill or 0)) then
							had.who, had.current = who, isCurrent
						end
					end
				end
			end
		end
	end
	table.sort(list, function(a, b) return a.spell < b.spell end)
	mine, mineRev = { list = list, bySpell = bySpell }, revision
	return list, bySpell
end

-- One recipe's numbers (any recipe of the data; who made it from my list when it's there).
function Mg.Recipe(spell)
	local R = C.Recipes
	local recipe, line = R and R.RecipeOf(spell)
	if not (recipe and Prices() and Prices().running) then
		return nil
	end
	local _, bySpell = Mg.MyRecipes()
	local entry = bySpell[spell]
	return Compute(recipe, line, entry and entry.who)
end

-- An entry of Mg.MyRecipes worked out (the window does its list a few a frame).
function Mg.Compute(entry)
	return Compute(entry.recipe, entry.line, entry.who)
end

-- The items that matter (keep: every reagent and product of my recipes) and those to ask the AH for (want:
-- the products and the reagents no vendor sells), sorted.
local items, itemsRev -- Mg.Items, of that Mg.Revision
function Mg.Items()
	local revision = Mg.Revision()
	if items and itemsRev == revision then
		return items.keep, items.want
	end
	local keep, want, seen = {}, {}, {}
	for _, entry in ipairs((Mg.MyRecipes())) do
		local recipe = entry.recipe
		keep[recipe.item] = true
		if not seen[recipe.item] then
			seen[recipe.item] = true
			want[#want + 1] = recipe.item
		end
		for _, need in ipairs(recipe.reagents) do
			keep[need.item] = true
			if not seen[need.item] and not Mg.VendorPrice(need.item) then
				seen[need.item] = true
				want[#want + 1] = need.item
			end
		end
	end
	table.sort(want)
	items, itemsRev = { keep = keep, want = want }, revision
	return keep, want
end

-- Of those, the ones without a price fresher than FRESH.
local function Stale(want)
	local list, now = {}, time()
	for _, item in ipairs(want) do
		local e = Mg.AHPrice(item)
		if not (e and e.t and now - e.t < FRESH) then
			list[#list + 1] = item
		end
	end
	return list
end

function Mg.Revision()
	local R, P = C.Recipes, Prices()
	return (P and P.Revision() or 0) * 100000 + (R and R.Revision() or 0)
end

function Mg.Age(t)
	return t and time() - t or nil
end

Mg.STALE = STALE

---------------------------------------------------------------------------
-- The auction house (the engine's scans)
---------------------------------------------------------------------------

-- (a recipe making it, for its item level)
function Mg.MakerOf(item)
	local _, bySpell = Mg.MyRecipes()
	for _, entry in pairs(bySpell) do
		if entry.recipe.item == item then
			return entry.recipe
		end
	end
end

-- Gear the game gives no item level for is searched by its recipe's (the engine asks).
function Mg.LevelHint(item)
	local recipe = C.Recipes and Mg.MakerOf(item)
	return recipe and recipe.ilvl or nil
end

-- Checks one recipe: its product and the reagents no vendor sells. Goes before what a scan by items has left.
function Mg.ScanRecipe(spell)
	local R, P = C.Recipes, Prices()
	local recipe = R and R.RecipeOf(spell)
	if not (Mg.Enabled() and P.IsOpen() and recipe and recipe.item) then
		return false
	end
	local items, seen = { recipe.item }, { [recipe.item] = true }
	for _, need in ipairs(recipe.reagents or {}) do
		if not seen[need.item] and not Mg.VendorPrice(need.item) then
			seen[need.item] = true
			items[#items + 1] = need.item
		end
	end
	P.ScanItems(items, { front = true, spell = spell }) -- (during a full scan: nothing, the full scan has it)
	return true
end

-- Every recipe of mine: the whole auction house at once if the game allows it again, else item by item.
function Mg.ScanAll()
	local P = Prices()
	if not (Mg.Enabled() and P.IsOpen()) or P.Status().running then
		return false
	end
	local function ByItems()
		local _, want = Mg.Items()
		return Stale(want)
	end
	if not P.ScanFull(ByItems) then
		P.ScanItems(ByItems())
	end
	return true
end

-- Whether the engine has work (its driver is hidden while it has none).
function Mg.Busy()
	local P = Prices()
	return P ~= nil and P.Busy()
end

function Mg.Cancel()
	local P = Prices()
	if P then
		P.Cancel()
	end
end

-- { open, running, kind, done, total, spell, left (items a full scan would still ask for), items }.
local left
function Mg.Status()
	local P = Prices()
	local status = P and P.Status() or { open = false }
	if Mg.Enabled() then
		local _, want = Mg.Items()
		local now = GetTime()
		if not (left and left.rev == Mg.Revision() and now - left.at < 30) then
			left = { rev = Mg.Revision(), at = now, n = #Stale(want) } -- (prices age: looked at again now and then)
		end
		status.left, status.items = left.n, #want
	end
	return status
end

---------------------------------------------------------------------------
-- Switching
---------------------------------------------------------------------------

local function Engine()
	local P = Prices()
	if P then
		P.levelHint = Mg.LevelHint
		P.Refresh() -- (it runs while this setting or WhyPoor? is on)
	end
end

-- Chronicle's OnEnable, OnDisable and OnSettingChanged.
function C.MarginsEnable()
	Engine()
	if C.MarginsUIChanged then
		C.MarginsUIChanged()
	end
end

function C.MarginsDisable()
	Engine()
	if C.MarginsUIChanged then
		C.MarginsUIChanged()
	end
end

function C.MarginsSettingChanged()
	Engine()
	if C.MarginsUIChanged then
		C.MarginsUIChanged()
	end
end
