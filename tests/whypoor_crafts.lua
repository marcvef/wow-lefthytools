-- WhyPoor?: the cheapest way to get an item and what a recipe brings, crafting the reagents yourself (Crafts.lua), and Margins using it.
-- Chains (cloth, bolt, shirt; bar, bolts, bomb; ore and bar: Mining's smelting), cheaper to buy than to craft,
-- several recipes for one item, the transmute circle, the depth, yields (a share of a craft, "may vary"), the bags
-- (sale value, partly, each used once, crafting cheaper than what's in them), vendor reagents, unknown prices (no
-- number), the verdict, the prices' age and basis, this character's recipes (Cr.Mine over
-- calls, cached), the Crafting tab's crafted reagents.
-- Needs: margins.lua
local suite = ...
local check, section, ns, LT = suite.check, suite.section, suite.ns, suite.LT

section("whypoor_crafts")
check(ns.WhyPoor ~= nil and LT:GetModule("whypoor") ~= nil, "the module is there")

local W = ns.WhyPoor
local Cr = W.Crafts
local C = ns.Chronicle
local spent = 0
local function Wait(seconds)
	Advance(seconds)
	spent = spent + seconds
end
local function near(a, b) return a ~= nil and b ~= nil and math.abs(a - b) < 0.001 end
local function plain(text) return ((text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

-- Items and spells (Data/Recipes.lua's, WoW: Forever 1.60.1).
local LINEN, BOLT_ITEM, THREAD, BLEACH, SHIRT, VEST = 2589, 2996, 2320, 2324, 2576, 2568
local BOLT, SHIRT_SPELL, VEST_SPELL = 2963, 2393, 2385
local BAR, BOLTS, STONE, POWDER, BOMB, ORE = 2840, 4359, 2835, 4357, 4360, 2770
local BOLTS_SPELL, POWDER_SPELL, BOMB_SPELL, SMELT = 3922, 3918, 3923, 2657
local EARTH, FIRE, WATER, AIR, LIFE = 7076, 7078, 7080, 7082, 12803
local FIRE_EARTH, AIR_FIRE, WATER_AIR, EARTH_WATER, LIFE_EARTH = 17560, 17559, 17562, 17561, 17565

-- Prices of our own (W.Prices' contract), put back at the end.
local realPrices = W.Prices
local AH, VBUY, VSELL = {}, {}, {} -- AH[item] = { low, qty, seen }
local fakeRev = 0
local fake = {}
function fake.Get(item)
	local e = AH[item]
	return e and { low = e[1], qty = e[2], seen = e[3] or time(), friend = e.friend } or nil
end
function fake.VendorBuy(item) return VBUY[item], false end
function fake.Vendor(item) return VSELL[item] end
function fake.AHSale(item, n)
	local e = AH[item]
	if e and e[1] then return e[1] * n * 0.95, e[1] end
end
function fake.Best(item, n)
	local ah, v = fake.AHSale(item, n), VSELL[item] and VSELL[item] * n
	if ah and not (v and v >= ah) then return "ah", ah end
	if v then return "vendor", v end
end
function fake.Revision() return fakeRev end
setmetatable(fake, { __index = realPrices }) -- (the rest, and whether the engine runs: the real one's)
W.Prices = fake

local casts = { [BOLT] = 1000, [SHIRT_SPELL] = 2000, [BOLTS_SPELL] = 2000 }
for spell, ms in pairs(casts) do SPELL_CAST_MS[spell] = ms end
local bags = {}
local itemCount = C_Item.GetItemCount
C_Item.GetItemCount = function(item) return bags[item] or 0 end

local tailor = { [BOLT] = true, [SHIRT_SPELL] = true, [VEST_SPELL] = true }
local tailorNoBolt = { [SHIRT_SPELL] = true }

section("Crafts: cloth, bolt, shirt")
AH[LINEN] = { 10, 100, time() - 600 }
AH[BOLT_ITEM] = { 100, 20 }
VBUY[THREAD], VBUY[BLEACH] = 10, 25
local c = Cr.Cost(SHIRT, 1, { who = tailor })
check(c and c.how == "craft" and c.recipe.spell == SHIRT_SPELL and c.complete, "never on the AH: crafted")
check(c and c.parts[1].how == "craft" and c.parts[1].recipe.spell == BOLT and c.parts[1].total == 20,
	"its bolt crafted from two linen (20c), not bought for 100c")
check(c and c.parts[1].parts[1].how == "ah" and c.parts[1].parts[1].n == 2 and c.parts[1].parts[1].total == 20, "the linen from the AH")
check(c and c.parts[2].how == "vendor" and c.parts[3].how == "vendor" and c.parts[3].total == 25, "thread and bleach from a vendor")
check(c and c.total == 55 and c.unit == 55, "55c in all, got " .. tostring(c and c.total))
check(c and c.seconds == 4 and c.castKnown, "both casts and their half seconds: 4 s, got " .. tostring(c and c.seconds))
check(c and c.basis == "prices" and c.oldest == AH[LINEN][3], "rests on AH prices; the linen's age")

AH[BOLT_ITEM] = { 15, 20 }
c = Cr.Cost(SHIRT, 1, { who = tailor })
check(c and c.parts[1].how == "ah" and c.total == 50 and c.seconds == 2.5, "the bolt cheaper on the AH: bought, no bolt cast")
AH[BOLT_ITEM] = { 100, 20 }
c = Cr.Cost(SHIRT, 1, { who = tailorNoBolt })
check(c and c.parts[1].how == "ah" and c.total == 135, "a crafter who can't make bolts buys them")
check(Cr.Cost(SHIRT, 1, { who = {} }) == nil, "no recipe, no price: no way known")
c = Cr.Cost(BOLT_ITEM, 3, { who = tailor })
check(c and c.how == "craft" and c.crafts == 3 and c.parts[1].n == 6 and c.total == 60, "three bolts: three crafts, six linen")

section("Crafts: vendor reagents, unknown prices")
AH[THREAD] = { 10, 50 }
c = Cr.Cost(THREAD, 2)
check(c and c.how == "vendor" and c.total == 20 and c.basis == "forever", "a tie: the vendor (it's certain); the data's price")
AH[THREAD] = { 7, 50 }
c = Cr.Cost(THREAD, 2)
check(c and c.how == "ah" and c.total == 14 and c.few == false, "cheaper on the AH")
AH[THREAD] = { 7, 4 }
check(Cr.Cost(THREAD, 1).few == true, "fewer listed than for five crafts: few")
AH[THREAD] = nil
AH[LINEN], AH[BOLT_ITEM] = nil, nil
c = Cr.Cost(SHIRT, 1, { who = tailor })
check(c and c.how == "craft" and not c.complete and c.parts[1].parts[1].how == nil and c.parts[1].parts[1].complete == false,
	"no linen price: the shirt has no cost (complete false)")
AH[LINEN] = { 10, 100, time() - 600 }
AH[BOLT_ITEM] = { nil, 0 }
c = Cr.Cost(BOLT_ITEM, 1, { who = {} })
check(c == nil, "none listed and no recipe: no way")

section("Crafts: bar, bolts, bomb; ore and bar")
AH[BAR], AH[ORE], AH[STONE] = { 50, 100 }, { 5, 100 }, { 3, 100 }
local engineer = { [BOLTS_SPELL] = true, [POWDER_SPELL] = true, [BOMB_SPELL] = true }
c = Cr.Cost(BOLTS, 1, { who = engineer })
check(c and c.how == "craft" and c.parts[1].how == "ah" and c.parts[1].item == BAR and c.total == 50,
	"bolts from a bar bought: no smelting known, so the ore isn't counted")
c = Cr.Cost(BOLTS, 1, { who = { [BOLTS_SPELL] = true, [SMELT] = true } })
check(c and c.parts[1].how == "craft" and c.parts[1].recipe.spell == SMELT and c.parts[1].parts[1].item == ORE and c.total == 5,
	"an engineer who mines: the bar smelted from its ore (5c, not 50c)")
c = Cr.Cost(BOMB, 2, { who = engineer })
check(c and c.how == "craft" and c.crafts == 1 and c.total == 116 and c.unit == 58, "two bombs: one craft (it makes two), 116c")
check(c and c.mayVary == true, "a craft making several: it may vary (the data has the middle)")
check(c and c.parts[3].how == "craft" and c.parts[3].crafts == 2 and c.parts[3].total == 6, "two blasting powders crafted from stone")
c = Cr.Cost(BOMB, 1, { who = engineer })
check(c and c.crafts == 0.5 and c.total == 58 and c.parts[1].n == 0.5, "one bomb: half a craft (the other goes into the next)")
local r = Cr.Recipe(BOMB_SPELL, { who = engineer })
check(r and r.yield == 2 and r.complete and r.cost == 116 and r.crafted, "the bomb's recipe: its reagents crafted where cheaper")
check(r and r.cast == 3 and not r.castKnown and r.subSeconds == 9.5 and r.seconds == 13 and not r.subCastKnown,
	"time: its cast (unknown: 3 s), the bolts' 2.5 s, two powders' 3.5 s each; got " .. tostring(r and r.seconds))

section("Crafts: several recipes, the circle, the depth")
AH[FIRE], AH[LIFE], AH[EARTH] = { 300, 10 }, { 200, 10 }, { 1000, 10 }
c = Cr.Cost(EARTH, 1, { who = { [FIRE_EARTH] = true, [LIFE_EARTH] = true } })
check(c and c.how == "craft" and c.recipe.spell == LIFE_EARTH and c.total == 200, "made by two recipes: the cheaper one")
local circle = { [FIRE_EARTH] = true, [AIR_FIRE] = true, [WATER_AIR] = true, [EARTH_WATER] = true }
AH[FIRE], AH[AIR], AH[WATER] = { 2000, 10 }, { 3000, 10 }, { 500, 10 }
c = Cr.Cost(EARTH, 1, { who = circle })
local water = c and c.parts[1].parts[1].parts[1]
check(c and c.total == 500 and c.parts[1].item == FIRE and c.parts[1].parts[1].item == AIR, "earth from fire from air from water")
check(water and water.item == WATER and water.how == "ah", "and the water bought: earth is being worked out above it, no circle")
check(c and near(c.seconds, 3 * 3.5) and c.mayVary == false, "three transmutes' time")
c = Cr.Cost(WATER, 1, { who = circle })
check(c and c.how == "ah" and c.total == 500, "water: bought (crafting it round the circle would end at water again)")
c = Cr.Cost(EARTH, 1, { who = circle, depth = 2 })
check(c and c.how == "ah" and c.total == 1000, "two deep: fire from air at best, dearer than earth on the AH")
c = Cr.Cost(EARTH, 1, { who = circle, depth = 3 })
check(c and c.how == "craft" and c.total == 500, "three deep: down to the water")
c = Cr.Cost(EARTH, 1, { who = circle, depth = 0 })
check(c and c.how == "ah", "no depth: nothing crafted")

section("Crafts: the bags")
bags[LINEN] = 3
c = Cr.Cost(BOLT_ITEM, 1, { who = tailor, bags = true })
check(c and c.how == "craft" and c.parts[1].how == "bags" and near(c.total, 19), "linen from the bags at what it sells for (2 x 10c less 5%)")
check(Cr.Cost(BOLT_ITEM, 1, { who = tailor }).total == 20, "without the bags: bought")
c = Cr.Cost(BOLT_ITEM, 2, { who = tailor, bags = true })
local linen = c and c.parts[1]
check(linen and linen.how == "mixed" and linen.bags.n == 3 and linen.rest.how == "ah" and linen.rest.n == 1 and near(c.total, 38.5),
	"two bolts: three linen from the bags, one bought")
bags[LINEN] = nil
bags[BAR] = 1
c = Cr.Cost(BOMB, 2, { who = engineer, bags = true })
check(c and near(c.total, 113.5), "one bar in the bags goes into one place only (the bomb or its bolts), got " .. tostring(c and c.total))
bags[BAR] = nil
bags[BOLT_ITEM] = 1
AH[BOLT_ITEM] = { 100, 20 }
c = Cr.Cost(BOLT_ITEM, 1, { who = tailor, bags = true })
check(c and c.how == "craft" and c.total == 20, "a bolt crafted for 20c beats using one that sells for 95c")
bags[BOLT_ITEM] = nil
bags[POWDER] = 5 -- (never on the AH, vendors don't buy it: its value isn't known)
c = Cr.Cost(POWDER, 1, { who = engineer, bags = true })
check(c and c.how == "craft", "what's in the bags without a known sale value isn't counted")
bags[POWDER] = nil

section("Crafts: a recipe's verdict")
AH[SHIRT] = { 200, 10 }
r = Cr.Recipe(SHIRT_SPELL, { who = tailor })
check(r and r.complete and r.cost == 55 and near(r.ahRevenue, 190) and near(r.profit, 135) and r.best == "ah", "the shirt: 55c, 190c on the AH")
check(r and r.verdict == "craft" and r.reason == "profit" and r.why ~= nil, "craft it")
check(r and near(r.perHour, 135 * 3600 / 4), "gold per hour over both casts")
do
	local ok, parts = r.breakEven ~= nil and near(r.breakEven, 190), {}
	for _, g in ipairs(r.reagents) do
		local others = r.cost - g.unit * g.n
		ok = ok and g.maxUnit == math.floor((190 - others) / g.n + 1e-9) and g.maxUnit >= g.unit
		parts[#parts + 1] = ("%s: %s each (now %s)"):format(g.item, tostring(g.maxUnit), tostring(g.unit))
	end
	check(ok, "break even: all reagents up to 190c a craft; each one's most, the others at their prices: " .. table.concat(parts, ", "))
end
AH[VEST], VSELL[VEST], VSELL[THREAD], VSELL[BOLT_ITEM] = { 60, 10 }, 50, 2, 40
r = Cr.Recipe(VEST_SPELL, { who = tailor })
check(r and r.reagents[1].source == "craft" and r.cost == 30 and near(r.profit, 27), "the vest: a profit (57c on the AH for 30c)")
check(r and near(r.reagentsSale, 97) and r.verdict == "sell reagents" and r.reason == "reagents",
	"but its bolt (95c on the AH) and thread (2c) sell for more: sell the reagents")
check(r and r.reagentsSaleComplete == false, "(at least: the thread was never seen on the AH, it might fetch more there)")
AH[SHIRT], VSELL[SHIRT] = { 30, 10 }, 10
r = Cr.Recipe(SHIRT_SPELL, { who = tailor })
check(r and r.verdict == "sell reagents", "the shirt for 28.5c: its bolt alone sells for 95c")
AH[BOLT_ITEM], VSELL[BOLT_ITEM] = { 15, 20 }, 10
r = Cr.Recipe(SHIRT_SPELL, { who = tailor })
check(r and r.cost == 50 and near(r.profit, -21.5) and r.verdict == "no" and r.reason == "loss", "bolts at 15c: a loss, don't")
check(r and r.reagents[1].maxUnit < r.reagents[1].unit and W.Crafting.BuyUpTo(r.reagents[1]):find("|cffff4040", 1, true),
	"a loss: the bolt's price is over its most, said in red")
AH[SHIRT] = nil
r = Cr.Recipe(SHIRT_SPELL, { who = tailor })
check(r and r.profit == -40 and r.verdict == nil and r.reason == "price", "never on the AH: a vendor loss, but no verdict (the AH may pay more)")
AH[LINEN], AH[BOLT_ITEM] = nil, nil
r = Cr.Recipe(SHIRT_SPELL, { who = tailor })
check(r and not r.complete and r.profit == nil and r.perHour == nil and r.verdict == nil, "a missing price: no profit, no number")
AH[LINEN], AH[BOLT_ITEM] = { 10, 100, time() - 600 }, { 100, 20 }
AH[SHIRT] = { 200, 10, time() - 7200, friend = "Anna" }
r = Cr.Recipe(SHIRT_SPELL, { who = tailor })
check(r and r.oldest == time() - 7200 and r.friend == "Anna" and r.basis == "prices", "the oldest price, a friend's, the basis")
AH[SHIRT] = nil
VSELL[SHIRT] = nil
r = Cr.Recipe(SHIRT_SPELL, { who = tailor })
check(r and r.waiting and r.vendorRevenue == nil, "the client doesn't have the item yet: waiting")

section("Crafts: this character's recipes")
ITEMS[BOLT_ITEM] = { name = "Bolt of Linen Cloth", quality = 1, price = 40 }
ITEMS[VEST] = { name = "Brown Linen Vest", quality = 1, price = 50, classID = 4 }
ITEMS[SHIRT] = { name = "White Linen Shirt", quality = 1, price = 10, classID = 4 }
VSELL[SHIRT] = 10
PROFESSIONS = { { name = "Tailoring", level = 60, line = 197 } }
KNOWN_SPELLS[BOLT], KNOWN_SPELLS[VEST_SPELL], KNOWN_SPELLS[SHIRT_SPELL] = true, true, true
Fire("SKILL_LINES_CHANGED")
Wait(25)
local mine = Cr.KnownOf(Cr.MyId())
check(mine[BOLT] and mine[VEST_SPELL] and mine[SHIRT_SPELL], "what the character I play knows (Chronicle's record)")
c = Cr.Cost(SHIRT, 1)
check(c and c.parts[1].how == "craft", "by default its recipes craft the bolt")
-- Mining's smelting: not in Chronicle's record, asked of the game for the character I play.
AH[ORE], AH[BAR] = { 8, 50 }, { 30, 50 }
c = Cr.Cost(BAR, 1)
check(c and c.how == "ah" and not mine[SMELT], "no smelting known: the bar is bought (30c)")
KNOWN_SPELLS[SMELT] = true
local withSmelt = Cr.KnownOf(Cr.MyId())
check(withSmelt[SMELT] and withSmelt[BOLT] and Cr.KnownOf(Cr.MyId()) == withSmelt, "Smelt Copper known: with the crafting recipes, one set while nothing changes")
c = Cr.Cost(BAR, 1)
check(c and c.how == "craft" and c.recipe.spell == SMELT and c.total == 8 and c.parts[1].how == "ah",
	"a miner smelts the bar from its ore (8c) instead of buying it (30c), got " .. tostring(c and c.how))
local smeltRecipe = C.Recipes.RecipeOf(SMELT)
check(smeltRecipe and smeltRecipe.item == BAR and smeltRecipe.reagents[1].item == ORE and select(2, C.Recipes.RecipeOf(SMELT)) == 186,
	"Chronicle's recipes know the smelting recipe (Mining's line)")
KNOWN_SPELLS[SMELT] = nil
AH[ORE], AH[BAR] = nil, nil
check(Cr.KnownOf(Cr.MyId())[SMELT] == nil, "forgotten again: not counted")
fakeRev = fakeRev + 1
local fakeMs = 0
local clock = debugprofilestop
debugprofilestop = function() fakeMs = fakeMs + 1; return fakeMs end -- (each look at the clock: a millisecond)
local list, done = Cr.Mine(1)
check(not done and #list == 0, "worked out over calls: not done after the first, nothing yet")
local calls = 1
while not done and calls < 10 do
	list, done = Cr.Mine(1)
	calls = calls + 1
end
debugprofilestop = clock
check(done and #list == 3 and calls >= 2, "done after a few calls: three recipes, got " .. #list)
check(list[1] and list[1].spell == BOLT and (list[1].perHour or 0) >= (list[2].perHour or -math.huge), "best gold per hour first")
check(list[3] and list[3].perHour == nil or list[3].perHour <= list[2].perHour, "those without a number last")
local again, done2 = Cr.Mine()
check(again == list and done2, "nothing changed: the same list")
fakeRev = fakeRev + 1
again = Cr.Mine(1000)
check(again ~= list, "the prices changed: worked out again")

section("Crafts: the Crafting tab's details")
Wait(1)
W.Crafting.OpenOn(VEST_SPELL)
local frame, _, _, D = W.Window.View()
Wait(1)
local lines, items = {}, {}
for _, fs in ipairs(D.texts) do
	if fs:IsShown() then lines[#lines + 1] = plain(fs:GetText()) end
end
for _, b in ipairs(D.items) do
	if b:IsShown() then items[#items + 1] = b end
end
local all = table.concat(lines, "\n")
check(all:find("craft it: 1 Bolt of Linen Cloth from 2 Linen Cloth, 1.5 s", 1, true), "the bolt's line: crafted, from what, how long; got " .. all)
local _, crafted = all:gsub("craft it:", "")
check(crafted == 1, "the thread is bought: no line of its own")
check(items[1] and plain(items[1].Right:GetText()):find("Craft", 1, true), "its source: Craft")
check(all:find("(1.5 s crafting reagents)", 1, true), "the time says what the sub-craft takes")
check(all:find("Break even: reagents up to", 1, true) and all:find("buy up to ", 1, true) and all:find("Buy up to: the most a reagent may cost", 1, true),
	"break even in the numbers, buy up to under the reagents, a note: " .. all)
check(all:find("Reagents you can make count as crafted", 1, true), "and a note says so")
items[1]:GetScript("OnEnter")(items[1])
local shown = table.concat(TOOLTIP.lines, "\n")
check(shown:find("The cheapest way:", 1, true) and shown:find("Linen Cloth x2", 1, true), "the hover has the way down to the linen")
items[1]:GetScript("OnLeave")(items[1])
frame:Hide()

-- (put back what this file changed)
W.Prices = realPrices
C_Item.GetItemCount = itemCount
for spell in pairs(casts) do SPELL_CAST_MS[spell] = nil end
PROFESSIONS, KNOWN_SPELLS[BOLT], KNOWN_SPELLS[VEST_SPELL], KNOWN_SPELLS[SHIRT_SPELL] = {}, nil, nil, nil
ITEMS[BOLT_ITEM], ITEMS[VEST], ITEMS[SHIRT] = nil, nil, nil
Advance(math.ceil(spent - 1e-6) - spent)
