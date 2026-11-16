-- WhyPoor?'s crafting margins (Margins.lua, the Crafting tab: Crafting.lua): my recipes from Chronicle's real
-- recipe scan and data, vendor prices (the data's, a merchant's), checking one recipe at the auction house (what's
-- asked, the pacing, the throttle, no answer, a fight), the numbers, a full scan (ReplicateItems read over frames,
-- every item kept, by items when it was too soon, going on after a stop), the Crafting tab (the list, its order,
-- the profession, stale prices, the details, the overview's scan button), the button on the profession window,
-- none of Margins' own on the auction house any more, the auction house closing mid-scan, nothing running idle,
-- WhyPoor? off, the button's setting, secret values.
-- Needs: no other file (it plays its own character's professions).
local suite = ...
local check, section, ns, LT = suite.check, suite.section, suite.ns, suite.LT
local C = ns.Chronicle
local W = ns.WhyPoor
local Mg = W.Margins
local M = LT:GetModule("whypoor")
local Cf = W.Crafting
local P = ns.WhyPoor.Prices -- (the price engine Margins reads: WhyPoor?'s Prices.lua)
local spent = 0 -- seconds this file lets pass (a whole number at its end)
local function Wait(seconds)
	Advance(seconds)
	spent = spent + seconds
end
-- The engine's prices of this realm and faction, made older by that many seconds.
local function Age(seconds)
	local items = ns.WhyPoor.DB().prices.houses["Realmy-Alliance"].items
	for item, text in pairs(items) do
		local e = P.Decode(text)
		e.seen = e.seen - seconds
		items[item] = P.Encode(e)
	end -- (no revision: as if time had passed)
end
local function plain(text)
	return ((text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local BOLT, LINEN, THREAD, VEST, BANDAGE = 2963, 2589, 2320, 2385, 3275 -- spells; LINEN, THREAD also items
local whypoorDB = LT:GetModule("whypoor").db
local autoScanWas = whypoorDB.autoScan
whypoorDB.autoScan = false -- (this file scans when Margins asks; WhyPoor?'s scan on opening: whypoor_prices.lua)
local BOLT_ITEM, VEST_ITEM = 2996, 2568
local REALM = "Realmy-Alliance"
ITEMS[BOLT_ITEM] = { name = "Bolt of Linen Cloth", quality = 1, price = 40 }
ITEMS[VEST_ITEM] = { name = "Brown Linen Vest", quality = 1, price = 50, classID = 4 }
ITEMS[THREAD] = { name = "Coarse Thread", quality = 1, price = 2 }
local linenPrice = ITEMS[LINEN].price
ITEMS[LINEN].price = 10
SPELL_CAST_MS[BOLT] = 1000

section("Margins: my recipes")
check(Mg and Mg.Enabled(), "on by default")
PROFESSIONS = { { name = "Tailoring", level = 60, line = 197 } }
KNOWN_SPELLS[BOLT], KNOWN_SPELLS[VEST] = true, true
Fire("SKILL_LINES_CHANGED")
Wait(25) -- (the recipe scan: a tick after the professions are read, 50 recipes a tick)
local list, bySpell = Mg.MyRecipes()
check(#list == 2 and bySpell[BOLT] and bySpell[VEST], "my two recipes that make items, got " .. #list)
check(bySpell[BOLT] and bySpell[BOLT].current and bySpell[BOLT].who.skill == 60, "made by the character I play, its skill")
local keep, want = Mg.Items()
check(keep[LINEN] and keep[THREAD] and keep[BOLT_ITEM] and keep[VEST_ITEM], "what matters: every reagent and product")
check(#want == 3 and want[1] == VEST_ITEM and want[2] == LINEN and want[3] == BOLT_ITEM, "asked of the AH: products and reagents no vendor sells")

local r = Mg.Recipe(VEST)
check(r and not r.complete and r.reagents[2].source == "vendor" and r.reagents[2].unit == 10, "before any scan: thread at the data's vendor price, the bolt without one")
check(r and r.profit == nil and r.vendorEach == 50, "no profit without every price; the vest's sell price")

section("Margins: a merchant's prices")
MERCHANT = { { THREAD, 40, 5 }, { 6948, 100, 1 }, { 2321, 500, 1, extended = true } }
Fire("MERCHANT_SHOW")
Wait(1) -- (the data's reagents first, a line a frame)
local p, seen = Mg.VendorPrice(THREAD)
check(p == 8 and seen, "coarse thread at what this merchant asks for one, got " .. tostring(p))
check(select(2, Mg.VendorPrice(6948)) == true, "not a reagent: kept too (the engine keeps every merchant's prices)")
check(select(2, Mg.VendorPrice(2321)) == false, "bought with something else than gold: not taken")
check(not Mg.Busy(), "nothing left to do: the driver hides")
MERCHANT = {}

section("Margins: one recipe at the auction house")
check(not Mg.ScanRecipe(BOLT) and not Mg.Status().open, "the auction house closed: nothing asked")
Fire("AUCTION_HOUSE_SHOW")
AH_COMMODITY[LINEN] = true
AH_LISTINGS[LINEN] = { { 11, 3, own = true }, { 12, 20 } }
AH_LISTINGS[BOLT_ITEM] = { { 100, 2 }, { 150, 1 } }
local before = #AH_SEARCHES
check(Mg.ScanRecipe(BOLT), "checked with the auction house open")
Wait(2)
check(#AH_SEARCHES == before + 2 and AH_SEARCHES[before + 1].item == BOLT_ITEM and AH_SEARCHES[before + 2].item == LINEN,
	"its product, then its reagent, got " .. (#AH_SEARCHES - before))
check(AH_SEARCHES[before + 2] and AH_SEARCHES[before + 2].at - AH_SEARCHES[before + 1].at >= 0.65, "searches 0.65 s apart (100 a minute)")
local linen = Mg.AHPrice(LINEN)
check(linen and linen.p == 12 and linen.q == 23 and time() - linen.t <= 2, "a commodity: the cheapest not of mine, how many listed, when")
local bolt = Mg.AHPrice(BOLT_ITEM)
check(bolt and bolt.p == 100, "items: an auction's buyout for one, got " .. tostring(bolt and bolt.p))
check(ns.WhyPoor.DB().prices.houses[REALM].items[LINEN] ~= nil, "kept for this realm and faction (the engine's)")
r = Mg.Recipe(BOLT)
check(r.complete and r.cost == 24 and r.reagents[1].source == "ah", "cost: two linen at the AH's price")
check(r.vendorRevenue == 40 and r.vendorProfit == 16, "sold to a vendor: 40c, 16c profit")
check(math.abs(r.ahRevenue - 95) < 0.001 and math.abs(r.ahProfit - 71) < 0.001, "on the AH: 100c less the 5% cut")
check(r.best == "ah" and math.abs(r.profit - 71) < 0.001, "profit: the better of the two")
check(r.seconds == 1.5 and r.castKnown and math.abs(r.perHour - 71 * 2400) < 0.01, "1 s cast and half a second more; gold per hour")
check(r.oldest == math.min(linen.t, bolt.t) and not r.few, "the prices' age; enough on the AH")

before = #AH_SEARCHES
Mg.ScanRecipe(VEST)
Wait(2)
check(#AH_SEARCHES == before + 2 and AH_SEARCHES[before + 1].item == VEST_ITEM and AH_SEARCHES[before + 2].item == BOLT_ITEM,
	"a vendor's thread isn't asked for")
check(AH_SEARCHES[before + 1] and AH_SEARCHES[before + 1].level == 8, "gear is searched by its item level")
local vest = Mg.AHPrice(VEST_ITEM)
check(vest and vest.p == nil and vest.q == 0, "none listed: said so, with when")
r = Mg.Recipe(VEST)
check(r.complete and r.cost == 32 and r.reagents[2].source == "vendor" and r.reagents[2].unit == 8, "the thread from the merchant")
check(r.reagents[1].source == "craft" and r.reagents[1].unit == 24 and r.reagents[1].cost.recipe.spell == BOLT and r.crafted,
	"the bolt crafted from two linen (24c), cheaper than the AH's 100c")
check(r.best == "vendor" and r.profit == 18 and r.ahRevenue == nil, "a profit at a vendor (nothing on the AH)")
check(not r.castKnown and r.cast == 3 and r.subSeconds == 1.5 and r.seconds == 5, "a cast time the game doesn't say: 3 s; the bolt's cast counts too")

section("Margins: no answer, the throttle, a fight")
local linenAt = Mg.AHPrice(LINEN).t
AH_SILENT[LINEN] = true
Wait(1)
Mg.ScanRecipe(BOLT)
Wait(5)
check(Mg.AHPrice(LINEN).t == linenAt and Mg.AHPrice(LINEN).p == 12, "no answer: the price it had stays")
check(not Mg.Status().running, "and the scan goes on to the end")
AH_SILENT[LINEN] = nil
AH_THROTTLED = true
before = #AH_SEARCHES
Mg.ScanRecipe(BOLT)
Wait(1)
check(#AH_SEARCHES == before, "the throttle isn't ready: nothing sent")
AH_THROTTLED = false
Wait(2)
check(#AH_SEARCHES == before + 2, "ready again: sent")
EnterCombat()
before = #AH_SEARCHES
Mg.ScanRecipe(BOLT)
Wait(2)
check(#AH_SEARCHES == before, "nothing asked in a fight")
LeaveCombat()
Wait(2)
check(#AH_SEARCHES == before + 2, "after the fight it goes on")

section("Margins: everything at once")
AH_REPLICATE_FILLER = 300
local fakeMs = 0
debugprofilestop = function() fakeMs = fakeMs + 1; return fakeMs end -- (each look at the clock: a millisecond)
before = #AH_SEARCHES
check(Mg.ScanAll(), "a full scan")
check(AH_REPLICATES == 1 and Mg.Status().kind == "replicate", "one request for the whole auction house")
local frames, readingFrames = 0, 0
while Mg.Status().running and frames < 300 do
	Advance(1 / 60)
	frames = frames + 1
	local status = Mg.Status()
	if status.running and status.total > 0 then
		readingFrames = readingFrames + 1
	end
end
spent = spent + frames / 60
debugprofilestop = nil
check(not Mg.Status().running, "done")
check(readingFrames >= 3, "its answer read over several frames (304 rows, 2 ms a frame), got " .. readingFrames)
check(#AH_SEARCHES == before, "no searches meanwhile")
check(P.AHPrice(999999) ~= nil, "every item is kept (the engine's prices are WhyPoor?'s too)")
local vestAH, linenAH = Mg.AHPrice(VEST_ITEM), Mg.AHPrice(LINEN)
check(vestAH and vestAH.p == nil and vestAH.q == 0, "not in the auction house: none listed")
check(linenAH.p == 11 and linenAH.q == 23 and Mg.AHPrice(THREAD) == nil, "the cheapest for one, every listing counted; never listed: no price")
check(time() - ns.WhyPoor.DB().prices.replicated <= 3, "when, for the game's limit")

check(Mg.ScanAll() and AH_REPLICATES == 1, "again too soon: no second full request")
Wait(1)
check(not Mg.Status().running and #AH_SEARCHES == before, "every price is fresh: nothing to ask")
Age(3600)
Mg.ScanAll()
check(Mg.Status().kind == "search" and Mg.Status().total == 3, "an hour later, by items: the products and the linen")
Wait(1)
Mg.Cancel()
local status = Mg.Status()
check(not status.running and status.left == 2 and status.items == 3, "stopped: two left, got " .. tostring(status.left))

section("Margins: the Crafting tab")
local Wn = W.Window
local function details()
	local _, _, _, D = Wn.View()
	local out = {}
	for _, fs in ipairs(D.texts) do
		if fs:IsShown() then out[#out + 1] = plain(fs:GetText()) end
	end
	return table.concat(out, "\n"), D
end
check(Cf.OpenOn(BOLT), "opens on a recipe")
local frame, state, view = Wn.View()
check(frame:IsShown() and state.tab == "crafting", "the window, on the Crafting tab")
local _, D0 = details()
check(D0.buttons[1] and plain(D0.buttons[1]:GetText()) == "Checking...", "the auction house open: the recipe's prices checked there at once (its button says so)")
Wait(3)
local entries = view.list.entries or {}
check(#entries == 2 and entries[1].spell == BOLT and entries[2].spell == VEST, "my recipes, by gold per hour")
local text, D = details()
check(text:find("Bolt of Linen Cloth", 1, true), "the recipe it opened on")
check(text:find("Cost per craft: 24c", 1, true), "its cost in the details (the linen just checked: 12c, my own 11c left out), got " .. text)
check(text:find("Gold per hour", 1, true) and D.buttons[1]:IsShown() and plain(D.buttons[1]:GetText()) == "Check AH", "gold per hour; Check AH")
check(Cf.picker:IsShown() and Cf.sort:IsShown() and plain(view.Head:GetText()) == "2 recipes", "its controls on the line above the list")
state.sel.crafting = nil
Wn.Draw()
text = details()
check(text:find("Crafting margins", 1, true) and plain(D.buttons[1]:GetText()) == "Scan all my recipes" and D.buttons[1]:IsEnabled(),
	"nothing picked: the overview with the scan button (the rest checked by now: a new scan, not going on)")
Cf.sort:Click()
Wait(0.1)
check(view.list.entries[1].spell == BOLT and plain(Cf.sort:GetText()) == "By profit", "by profit per craft")
local row = view.list.rows[1]
check(row and not row.Money:GetText():find("|cff888888", 1, true), "fresh prices: not greyed")
Age(4 * 3600)
Fire("BAG_UPDATE_DELAYED")
Wait(3)
row = view.list.rows[1]
check(row and row.Money:GetText():find("|cff888888", 1, true), "prices older than 3 hours: greyed")
view.list.rows[2]:Click()
text = details()
check(text:find("Brown Linen Vest", 1, true) and text:find("craft it: 1 Bolt of Linen Cloth from 2 Linen Cloth", 1, true),
	"a click shows another recipe, its crafted bolt's line")
Fire("AUCTION_HOUSE_CLOSED")
Wait(1)
text = details()
check(not D.buttons[1]:IsEnabled() and text:find("Open the auction house to update the prices.", 1, true), "the auction house closed: no check, the details say to open it")
state.sel.crafting = nil
Wn.Draw()
text = details()
check(not D.buttons[1]:IsEnabled() and text:find("Open the auction house to scan.", 1, true), "and the overview")
Cf.filter = 171 -- (Alchemy: none of mine)
Wn.Draw()
check(#view.list.entries == 0, "a profession picked: only its recipes")
Cf.filter = nil
frame:Hide()

section("Margins: on the profession window")
local shownRecipe = BOLT
local professions = CreateFrame("Frame", "ProfessionsFrame", UIParent)
professions.CraftingPage = CreateFrame("Frame", nil, professions)
local form = CreateFrame("Frame", nil, professions.CraftingPage)
professions.CraftingPage.SchematicForm = form
function form:GetRecipeInfo() return { recipeID = shownRecipe, name = "Spell " .. shownRecipe } end
function form:Init() end
Fire("ADDON_LOADED", "Blizzard_Professions")
Wait(1)
local button = select(1, form:GetChildren())
check(button and button:GetText() == "Margins" and button:IsShown(), "a Margins button on the recipe")
Fire("AUCTION_HOUSE_SHOW")
before = #AH_SEARCHES
button:Click()
text = details()
check(frame:IsShown() and state.tab == "crafting" and text:find("Bolt of Linen Cloth", 1, true), "it opens the Crafting tab on that recipe")
Wait(2)
check(#AH_SEARCHES == before + 2, "and checks it at the open auction house")
shownRecipe = 7418 -- (an enchant: it makes no item)
form:Init()
Wait(1)
check(not button:IsShown(), "a recipe that makes no item: no button")
shownRecipe = BOLT
form:Init()
Wait(1)
check(button:IsShown(), "back")
frame:Hide()
local ah = CreateFrame("Frame", "AuctionHouseFrame", UIParent)
Fire("ADDON_LOADED", "Blizzard_AuctionHouseUI")
Wait(1)
local margins = false
for _, child in ipairs({ ah:GetChildren() }) do
	if child.GetText and child:GetText() == "Margins" then margins = true end
end
check(not margins, "no Margins button of its own on the auction house any more (WhyPoor?'s opens the window)")

section("Margins: the auction house closing, idle")
Age(3600)
Mg.ScanAll()
check(Mg.Status().running, "a scan")
Wait(1)
Fire("AUCTION_HOUSE_CLOSED")
Wait(1)
check(not Mg.Status().running and not Mg.Busy(), "the auction house closed: it stops, nothing runs")

section("Margins: WhyPoor? off, the button's setting, secrets")
LT:SetModuleSetting(M, "craftButton", false)
Wait(1)
check(not button:IsShown(), "the setting off: no button")
LT:SetModuleSetting(M, "craftButton", true)
Wait(1)
check(button:IsShown(), "on: back")
LT:SetModuleEnabled("whypoor", false)
Wait(1)
check(not Mg.Enabled() and not button:IsShown(), "WhyPoor? off: no margins, no button")
LT:SetModuleEnabled("whypoor", true)
Wait(1)
check(Mg.Enabled() and button:IsShown(), "on again")
Fire("AUCTION_HOUSE_SHOW")
AH_LISTINGS[LINEN] = { { SECRET, 5 } }
Mg.ScanRecipe(BOLT)
Wait(2)
check(Mg.AHPrice(LINEN) and Mg.AHPrice(LINEN).p == nil, "a secret price isn't taken")
Fire("AUCTION_HOUSE_CLOSED")
Wait(1)

-- (put back what this file changed)
whypoorDB.autoScan = autoScanWas
ProfessionsFrame, AuctionHouseFrame = nil, nil
professions:Hide()
ah:Hide()
PROFESSIONS, KNOWN_SPELLS[BOLT], KNOWN_SPELLS[VEST] = {}, nil, nil
ITEMS[BOLT_ITEM], ITEMS[VEST_ITEM], ITEMS[THREAD], ITEMS[LINEN].price = nil, nil, nil, linenPrice
SPELL_CAST_MS[BOLT] = nil
AH_LISTINGS, AH_COMMODITY, AH_REPLICATE_FILLER = {}, {}, 0
Advance(math.ceil(spent - 1e-6) - spent) -- (a whole number of seconds in all)
