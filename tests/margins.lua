-- Chronicle's crafting margins (Margins.lua, MarginsWindow.lua): my recipes from C.Recipes' real scan and
-- data, vendor prices (the data's, a merchant's), checking one recipe at the auction house (what's asked, the
-- pacing, the throttle, no answer, a fight), the numbers, a full scan (ReplicateItems read over frames, only
-- what my recipes use kept, by items when it was too soon, going on after a stop), the window (the list, its
-- order, stale prices, the details, the scan button), the buttons on the profession window and the auction
-- house, the auction house closing mid-scan, nothing running idle, the setting, pruning, secret values.
-- Needs: no other file (it plays its own character's professions).
local suite = ...
local check, section, ns, LT = suite.check, suite.section, suite.ns, suite.LT
local C = ns.Chronicle
local Mg = C.Margins
local M = LT:GetModule("chronicle")
local spent = 0 -- seconds this file lets pass (a whole number at its end)
local function Wait(seconds)
	Advance(seconds)
	spent = spent + seconds
end
local function plain(text)
	return ((text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local BOLT, LINEN, THREAD, VEST, BANDAGE = 2963, 2589, 2320, 2385, 3275 -- spells; LINEN, THREAD also items
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
check(LefthyToolsDB.margins.vendor[6948] == nil, "not a reagent: not kept")
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
check(LefthyToolsDB.margins.ah[REALM][LINEN] ~= nil, "kept for this realm and faction")
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
check(r.complete and r.cost == 108 and r.reagents[2].source == "vendor" and r.reagents[2].unit == 8, "the bolt from the AH, the thread from the merchant")
check(r.best == "vendor" and r.profit == -58 and r.ahRevenue == nil, "a loss, at a vendor (nothing on the AH)")
check(not r.castKnown and r.seconds == 3.5, "a cast time the game doesn't say: 3 s")

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
local saved = LefthyToolsDB.margins.ah[REALM]
check(saved[999999] == nil, "only what my recipes use is kept")
check(saved[VEST_ITEM] and saved[VEST_ITEM].p == nil and saved[VEST_ITEM].q == 0, "not in the auction house: none listed")
check(saved[LINEN].p == 11 and saved[LINEN].q == 23 and saved[THREAD].q == 0, "the cheapest for one, every listing counted")
check(time() - LefthyToolsDB.margins.replicated[REALM] <= 3, "when, for the game's limit")

check(Mg.ScanAll() and AH_REPLICATES == 1, "again too soon: no second full request")
Wait(1)
check(not Mg.Status().running and #AH_SEARCHES == before, "every price is fresh: nothing to ask")
for _, e in pairs(saved) do e.t = e.t - 3600 end
Mg.ScanAll()
check(Mg.Status().kind == "search" and Mg.Status().total == 3, "an hour later, by items: the products and the linen")
Wait(1)
Mg.Cancel()
local status = Mg.Status()
check(not status.running and status.left == 2 and status.items == 3, "stopped: two left, got " .. tostring(status.left))

section("Margins: the window")
C.OpenMargins(BOLT)
local frame = C.marginsFrame
local view = frame and frame.view
check(frame and frame:IsShown(), "opens")
Wait(1)
local entries = view and view.list.entries or {}
check(#entries == 2 and entries[1].spell == BOLT and entries[2].spell == VEST, "my recipes, by gold per hour")
check(plain(view.Scan:GetText()) == "Go on (2 left)" and view.Scan:IsEnabled(), "the scan button goes on where it stopped")
check(view.detail:IsShown() and plain(view.detail.Name:GetText()):find("Bolt of Linen Cloth", 1, true), "the recipe it opened on")
check(plain(view.detail.Values:GetText()):find("22c", 1, true), "its cost in the details, got " .. plain(view.detail.Values:GetText()))
check(plain(view.detail.Labels:GetText()):find("Gold per hour", 1, true), "and gold per hour")
view.Sort:Click()
check(view.list.entries[1].spell == BOLT and plain(view.Sort:GetText()) == "Sort: profit per craft", "by profit per craft")
local row = view.list.rows[1]
check(row and row:GetAlpha() == 1, "fresh prices: not greyed")
for _, e in pairs(saved) do e.t = e.t - 4 * 3600 end
Fire("BAG_UPDATE_DELAYED")
Wait(1)
check(view.list.rows[1]:GetAlpha() == 1, "the bags changed: worked out again, but not at once again")
Wait(2)
row = view.list.rows[1]
check(row and row:GetAlpha() < 1, "prices older than 3 hours: greyed")
view.list.rows[2]:Click()
check(plain(view.detail.Name:GetText()):find("Brown Linen Vest", 1, true), "a click shows another recipe")
Fire("AUCTION_HOUSE_CLOSED")
Wait(1)
check(not view.Scan:IsEnabled() and view.Status:GetText() == "Open the auction house to scan.", "the auction house closed: no scan")
check(not view.detail.Check:IsEnabled() and plain(view.detail.Notes:GetText()):find("Open the auction house", 1, true),
	"the details say to open it")
frame:Hide()

section("Margins: on the profession window and the auction house")
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
check(frame:IsShown() and plain(view.detail.Name:GetText()):find("Bolt of Linen Cloth", 1, true), "it opens the window on that recipe")
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
local ahButton = select(1, ah:GetChildren())
check(ahButton and ahButton:IsShown() and ahButton:GetText() == "Margins", "and one on the auction house")
ahButton:Click()
check(frame:IsShown(), "it opens the window")
frame:Hide()

section("Margins: the auction house closing, idle")
for _, e in pairs(saved) do e.t = e.t - 3600 end
Mg.ScanAll()
check(Mg.Status().running, "a scan")
Wait(1)
Fire("AUCTION_HOUSE_CLOSED")
Wait(1)
check(not Mg.Status().running and not Mg.Busy(), "the auction house closed: it stops, nothing runs")

section("Margins: the setting, pruning, secrets")
LT:SetModuleSetting(M, "margins", false)
Wait(1)
check(not Mg.Enabled() and not button:IsShown() and not ahButton:IsShown(), "off: no buttons")
MERCHANT = { { THREAD, 60, 5 } }
Fire("MERCHANT_SHOW")
Wait(1)
check(LefthyToolsDB.margins.vendor[THREAD].p == 8, "off: no merchant's prices taken")
MERCHANT = {}
LefthyToolsDB.margins.ah[REALM][LINEN].t = time() - 15 * 86400
LefthyToolsDB.margins.ah[REALM][12345] = "broken"
LefthyToolsDB.margins.ah["Other-Horde"] = { [LINEN] = { p = 5, q = 1, t = time() - 20 * 86400 } }
LT:SetModuleSetting(M, "margins", true)
Wait(1)
check(Mg.Enabled() and button:IsShown(), "on again")
check(LefthyToolsDB.margins.ah[REALM][LINEN] == nil and LefthyToolsDB.margins.ah[REALM][12345] == nil, "older than 14 days, or broken: gone")
check(LefthyToolsDB.margins.ah["Other-Horde"] == nil, "a realm with nothing left: gone")
Fire("AUCTION_HOUSE_SHOW")
AH_LISTINGS[LINEN] = { { SECRET, 5 } }
Mg.ScanRecipe(BOLT)
Wait(2)
check(Mg.AHPrice(LINEN) and Mg.AHPrice(LINEN).p == nil, "a secret price isn't taken")
Fire("AUCTION_HOUSE_CLOSED")
Wait(1)

-- (put back what this file changed)
ProfessionsFrame, AuctionHouseFrame = nil, nil
professions:Hide()
ah:Hide()
PROFESSIONS, KNOWN_SPELLS[BOLT], KNOWN_SPELLS[VEST] = {}, nil, nil
ITEMS[BOLT_ITEM], ITEMS[VEST_ITEM], ITEMS[THREAD], ITEMS[LINEN].price = nil, nil, nil, linenPrice
SPELL_CAST_MS[BOLT] = nil
AH_LISTINGS, AH_COMMODITY, AH_REPLICATE_FILLER = {}, {}, 0
Advance(math.ceil(spent - 1e-6) - spent) -- (a whole number of seconds in all)
