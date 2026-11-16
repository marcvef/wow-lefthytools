local _, ns = ...
local LT = ns.LT
local W = ns.WhyPoor or {}
ns.WhyPoor = W
local C = ns.Chronicle -- (its record of my characters' recipes, C.Recipes)

-- Crafting margins (W.Margins, Mg; the Crafting tab of the window is Crafting.lua's): which of my characters'
-- recipes to show and work out, and what to scan for them. Part of WhyPoor? (it was Chronicle's until build
-- 0.7.0-193; its setting went with it: it's on while WhyPoor? is).
--
-- Prices come from the price engine (Prices.lua, W.Prices; docs/whypoor.md): Mg.AHPrice, Mg.VendorPrice and
-- Mg.SellPrice read it, Mg.ScanRecipe and Mg.ScanAll ask it to scan. A recipe's numbers are the crafting part's
-- (Crafts.lua, Cr.Recipe): each reagent the cheapest way (the auction house, a vendor, crafting it yourself,
-- the bags), revenue at a vendor and on the auction house after its cut, profit, time with the sub-crafts,
-- gold per hour.
--
-- Scanning, only with the auction house open, never in a fight (the engine's rules): one recipe (its product and
-- the reagents no vendor sells) item by item; everything with a full scan (ReplicateItems: the whole auction
-- house) when the game allows one again, else item by item like a recipe, skipping prices fresher than FRESH
-- (so a scan that was stopped goes on where it was).

local STALE = 3 * 3600        -- prices older than this are shown greyed
local FRESH = 30 * 60         -- a full scan by items skips prices younger than this

local Mg = {}
W.Margins = Mg

local mine, mineRev   -- Mg.MyRecipes, of that R.Revision

-- The price engine (Prices.lua, loaded before this file).
local function Prices()
	return W.Prices
end

function Mg.Enabled()
	local P = Prices()
	return W.module ~= nil and W.module.enabled and P ~= nil and P.running == true
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

-- A recipe's numbers, worked out by WhyPoor?'s crafting part (Modules/WhyPoor/Crafts.lua, Cr.Recipe): each reagent
-- the cheapest way, also crafted by who makes it (that character's recipes; nil: the character I play) where that's
-- cheaper, the sub-crafts' casts counted in its time. { spell, line, recipe, who, reagents = { { item, n, unit,
-- source ("ah", "vendor", "craft" or nil: no price), cost (Cr.Cost's answer), have, q, t, scanned, few }, ... }, cost,
-- complete, covers, yield, mayVary, vendorEach, vendorRevenue, vendorProfit, ahEach, ahQty, ahScanned, ahRevenue,
-- ahProfit, best ("vendor", "ah"), profit, cast, castKnown, subSeconds, subCastKnown, seconds, perHour, oldest (the
-- oldest AH price it uses), few, crafted, waiting (an item's data hasn't come), verdict, reason, why }.
local function Compute(recipe, line, who)
	return W.Crafts.Recipe(recipe.spell, { recipe = recipe, line = line, crafter = who })
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
	local recipe, line
	if R then
		recipe, line = R.RecipeOf(spell) -- (both: "R and R.RecipeOf()" would keep only the first)
	end
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

-- Gear the game gives no item level for is searched by its recipe's (the engine asks).
if Prices() then
	Prices().levelHint = Mg.LevelHint
end
