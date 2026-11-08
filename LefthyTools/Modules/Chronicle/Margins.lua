local _, ns = ...
local LT = ns.LT
local C = ns.Chronicle
local M = C.module

-- Crafting margins (setting margins): what one of my recipes costs to make, what it brings, and gold per
-- hour, from auction house and vendor prices. The window and the buttons on Blizzard's profession window
-- and auction house are MarginsWindow.lua's; this file keeps the prices, scans the auction house and works
-- the numbers out (C.Margins, Mg).
--
-- Prices, saved account-wide in LefthyToolsDB.margins:
--   ah[<realm>-<faction>][item] = { p, q, t }   the lowest buyout for one (copper; nil: none listed), how many
--                                              were listed, when (time()). Each realm and faction has its own
--                                              auction house. Only items of my recipes; older than KEEP: gone.
--   vendor[item] = { p, t }                    what a merchant asked for one (seen when its window showed)
--   replicated[<realm>-<faction>] = t          the last full scan (the game allows one every REPLICATE_GAP)
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
-- Scanning, only with the auction house open, never in a fight: one recipe (its product and the reagents no
-- vendor sells) with C_AuctionHouse.SendSearchQuery, one item at a time, QUERY_GAP apart (the game takes 100
-- a minute) and only when its throttle says it's ready; everything with ReplicateItems (the whole auction
-- house in one answer, read within READ_MS a frame), or, when the game doesn't allow that again yet or
-- doesn't answer, item by item like a recipe, skipping prices fresher than FRESH (so a scan that was
-- stopped goes on where it was). None of these are restricted (Blizzard_APIDocumentationGenerated).
-- Events only note things; a driver frame does the rest and is hidden while there's nothing to do.

local AH_CUT = 0.05
local OVERHEAD = 0.5          -- seconds a craft takes beyond its cast (the button, the next cast)
local DEFAULT_CAST = 3        -- seconds, when the spell's cast time can't be read
local STALE = 3 * 3600        -- prices older than this are shown greyed
local FRESH = 30 * 60         -- a full scan by items skips prices younger than this
local KEEP = 14 * 86400       -- prices older than this go
local FEW = 5                 -- fewer listed than for this many crafts: "few on the AH"
local QUERY_GAP = 0.65        -- seconds between two searches (100 a minute)
local QUERY_WAIT = 3          -- no answer this long: the next one
local SETTLE = 0.2            -- after an answer came, before it's read (its rows come in a burst)
local REPLICATE_GAP = 15 * 60 -- the game answers a full scan this often
local REPLICATE_WAIT = 30     -- no full scan's answer this long: item by item instead
local READ_MS = 2             -- a full scan's answer read this long a frame at most
local REPLICATE_STEP = 50     -- rows read between two looks at the clock
local SEARCH_ROWS = 50        -- an item's search rows looked at for the lowest price for one

local Mg = {}
C.Margins = Mg

local issecret = LT.IsSecret
local saved           -- LefthyToolsDB.margins
local realmKey        -- "<realm>-<faction>"
local rev = 0         -- goes up when a price changed
local ahOpen = false
local scan            -- what's being scanned (below)
local lastSend = -math.huge
local merchantDue = false
local reagentSet, reagentNext -- every reagent of the data ([item] = true), built a line a frame; the line next
local mine, mineRev   -- Mg.MyRecipes, of that R.Revision
local casts = {}      -- spell -> seconds
local asked = {}      -- items whose data was asked for

local function Number(v)
	return type(v) == "number" and not issecret(v) and v or nil
end

local function Clock()
	local ok, ms = pcall(debugprofilestop)
	return ok and type(ms) == "number" and ms or nil
end

local function Changed()
	rev = rev + 1
end

function Mg.Enabled()
	return M.enabled and M.db.margins and saved ~= nil
end

function Mg.IsAHOpen()
	return ahOpen
end

-- This realm's and faction's prices.
local function Prices()
	local list = saved.ah[realmKey]
	if not list then
		list = {}
		saved.ah[realmKey] = list
	end
	return list
end

---------------------------------------------------------------------------
-- Prices
---------------------------------------------------------------------------

-- What a vendor asks for one: seen at a merchant, else the data's list; the second result says it was seen.
function Mg.VendorPrice(item)
	local seen = saved and saved.vendor[item]
	if type(seen) == "table" and type(seen.p) == "number" then
		return seen.p, true
	end
	local list = ns.RecipeData and ns.RecipeData.vendor
	local p = list and list[item]
	if type(p) == "number" then
		return p, false
	end
end

-- The AH's: { p (nil: none listed), q, t } or nil (never scanned).
function Mg.AHPrice(item)
	if not saved then
		return nil
	end
	local e = Prices()[item]
	return type(e) == "table" and e or nil
end

local function Ask(item)
	if not asked[item] then
		asked[item] = true
		pcall(C_Item.RequestLoadItemDataByID, item)
	end
end

-- An item's sell price (copper; 0: vendors don't buy it), nil while the client doesn't have the item yet.
function Mg.SellPrice(item)
	local ok, name, _, _, _, _, _, _, _, _, _, price = pcall(C_Item.GetItemInfo, ("item:%d"):format(item))
	if ok and type(name) == "string" and not issecret(name) and Number(price) then
		return price
	end
	Ask(item)
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
	if not (recipe and saved) then
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
	local R = C.Recipes
	return rev * 100000 + (R and R.Revision() or 0)
end

function Mg.Age(t)
	return t and time() - t or nil
end

Mg.STALE = STALE

---------------------------------------------------------------------------
-- The auction house
---------------------------------------------------------------------------

local driver = CreateFrame("Frame")
driver:Hide()

local function Wake()
	driver:Show()
end

local SORTS = { { sortOrder = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0, reverseSort = false } }

-- The item's key for a search: gear by its item level, the rest without (as the auction house lists them).
local function ItemKey(item)
	local A = C_AuctionHouse
	local ok, _, _, _, _, _, class = pcall(C_Item.GetItemInfoInstant, item)
	local level = 0
	if ok and (class == 2 or class == 4) then -- (weapons, armour)
		local okLevel, ilvl = pcall(C_Item.GetDetailedItemLevelInfo, item)
		level = okLevel and Number(ilvl) or 0
		if level == 0 then
			local recipe = C.Recipes and select(1, Mg.MakerOf(item))
			level = recipe and recipe.ilvl or 0
		end
	end
	local made, key = pcall(A.MakeItemKey, item, level)
	return made and type(key) == "table" and key or nil
end

-- (a recipe making it, for its item level)
function Mg.MakerOf(item)
	local _, bySpell = Mg.MyRecipes()
	for _, entry in pairs(bySpell) do
		if entry.recipe.item == item then
			return entry.recipe
		end
	end
end

-- An item's search answer: the lowest buyout for one (my own auctions left out) and how many are listed.
local function ReadResults(item, key)
	local A = C_AuctionHouse
	local best
	local n = LT.Value(A.GetNumCommoditySearchResults, item)
	n = Number(n) or 0
	if n > 0 then
		for i = 1, math.min(n, SEARCH_ROWS) do
			local row = LT.Value(A.GetCommoditySearchResultInfo, item, i)
			local unit, count = type(row) == "table" and Number(row.unitPrice), type(row) == "table" and Number(row.quantity)
			if unit and unit > 0 and count and (Number(row.numOwnerItems) or 0) < count then
				best = math.min(best or math.huge, unit)
			end
		end
		return best, Number(LT.Value(A.GetCommoditySearchResultsQuantity, item)) or 0
	end
	n = key and Number(LT.Value(A.GetNumItemSearchResults, key)) or 0
	for i = 1, math.min(n, SEARCH_ROWS) do
		local row = LT.Value(A.GetItemSearchResultInfo, key, i)
		local buyout, count = type(row) == "table" and Number(row.buyoutAmount), type(row) == "table" and Number(row.quantity)
		if buyout and buyout > 0 and count and count > 0 and row.containsOwnerItem ~= true then
			best = math.min(best or math.huge, buyout / count)
		end
	end
	return best, n > 0 and (Number(LT.Value(A.GetItemSearchResultsQuantity, key)) or 0) or 0
end

local function Store(item, p, q, t)
	Prices()[item] = { p = p, q = q, t = t or time() }
	Changed()
end

local function StartSearch(items, spell)
	scan = { kind = "search", items = items, i = 1, total = #items, done = 0, spell = spell }
	Wake()
end

local function Finish()
	if scan and scan.full then
		-- Only what my recipes use stays (a recipe unlearned, another character's realm).
		local keep = scan.keep or Mg.Items()
		local list = Prices()
		for item in pairs(list) do
			if not keep[item] then
				list[item] = nil
			end
		end
	end
	scan = nil
	Changed()
end

local function SearchStep(now)
	local A = C_AuctionHouse
	local f = scan.inflight
	if f then
		if (f.came and now - f.came >= SETTLE) or now - f.sent >= QUERY_WAIT then
			if f.came then
				Store(f.item, ReadResults(f.item, f.key)) -- (no rows: none listed)
			end -- (no answer: the old price stays; rows still there would be an earlier search's)
			scan.inflight, scan.done = nil, scan.done + 1
		end
		return
	end
	local item = scan.items[scan.i]
	if not item then
		Finish()
		return
	end
	local ready = LT.Value(A.IsThrottledMessageSystemReady)
	if now - lastSend < QUERY_GAP or ready == false then
		return
	end
	scan.i = scan.i + 1
	local key = ItemKey(item)
	if not (key and pcall(A.SendSearchQuery, key, SORTS, true)) then
		scan.done = scan.done + 1
		return
	end
	lastSend = now
	scan.inflight = { item = item, key = key, sent = now }
end

local function ByItems()
	local keep, want = Mg.Items()
	StartSearch(Stale(want))
	scan.full, scan.keep = true, keep
end

local function ReplicateStep(now)
	local A = C_AuctionHouse
	if scan.waiting then
		if scan.came and now - scan.came >= SETTLE then
			scan.waiting, scan.index, scan.found = false, 0, {}
			scan.n = Number(LT.Value(A.GetNumReplicateItems)) or 0
			scan.total = scan.n
			if scan.n == 0 then
				ByItems()
			end
		elseif now - scan.sent >= REPLICATE_WAIT then
			ByItems() -- (no answer: item by item)
		end
		return
	end
	local started, keep, found, get = Clock(), scan.keep, scan.found, A.GetReplicateItemInfo
	if not get then
		ByItems()
		return
	end
	while scan.index < scan.n do
		local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, item = get(scan.index)
		scan.index = scan.index + 1
		item, count, buyout = Number(item), Number(count), Number(buyout)
		if item and keep[item] and count and count > 0 and buyout and buyout > 0 then
			local f = found[item]
			if not f then
				f = { p = math.huge, q = 0 }
				found[item] = f
			end
			f.p, f.q = math.min(f.p, buyout / count), f.q + count
		end
		if scan.index % REPLICATE_STEP == 0 and started and Clock() - started >= READ_MS then
			scan.done = scan.index
			return
		end
	end
	local t = time()
	for item in pairs(keep) do
		local f = found[item]
		Store(item, f and f.p, f and f.q or 0, t) -- (the whole auction house: not in it means none listed)
	end
	Finish()
end

local function Tick()
	if merchantDue then
		Mg.ReadMerchant()
	end
	if reagentNext then
		Mg.ReagentStep()
	end
	if scan then
		if not ahOpen then
			scan = nil -- (closed: the next scan goes on from the prices that came)
			Changed()
		elseif not LT.InFight() then
			local now = GetTime()
			if scan.kind == "search" then
				SearchStep(now)
			else
				ReplicateStep(now)
			end
		end
	end
	if not (scan or merchantDue or reagentNext) then
		driver:Hide()
	end
end

driver:SetScript("OnUpdate", function()
	LT.Guard("C.MarginsTick", Tick)
end)

-- Checks one recipe: its product and the reagents no vendor sells. Goes before what a full scan has left.
function Mg.ScanRecipe(spell)
	local R = C.Recipes
	local recipe = R and R.RecipeOf(spell)
	if not (Mg.Enabled() and ahOpen and recipe and recipe.item) then
		return false
	end
	local items, seen = { recipe.item }, { [recipe.item] = true }
	for _, need in ipairs(recipe.reagents or {}) do
		if not seen[need.item] and not Mg.VendorPrice(need.item) then
			seen[need.item] = true
			items[#items + 1] = need.item
		end
	end
	if scan and scan.kind == "search" then
		for k = #items, 1, -1 do
			table.insert(scan.items, scan.i, items[k])
		end
		scan.total, scan.spell = scan.total + #items, spell
	elseif not scan then
		StartSearch(items, spell)
	end
	return true
end

-- Every recipe of mine: the whole auction house at once if the game allows it again, else item by item.
function Mg.ScanAll()
	if not (Mg.Enabled() and ahOpen) or scan then
		return false
	end
	local A = C_AuctionHouse
	local last = saved.replicated[realmKey] or 0
	if A.ReplicateItems and time() - last >= REPLICATE_GAP and pcall(A.ReplicateItems) then
		saved.replicated[realmKey] = time()
		scan = { kind = "replicate", waiting = true, sent = GetTime(), keep = (Mg.Items()), total = 0, done = 0, full = true }
		Wake()
	else
		ByItems()
	end
	return true
end

-- Whether the driver has work (it's hidden while it has none).
function Mg.Busy()
	return driver:IsShown()
end

function Mg.Cancel()
	if scan then
		scan = nil
		Changed()
	end
end

-- { open, running, kind, done, total, spell, left (items a full scan would still ask for), items }.
local left
function Mg.Status()
	local status = { open = ahOpen }
	if scan then
		status.running, status.kind, status.done, status.total, status.spell = true, scan.kind, scan.done, scan.total, scan.spell
	end
	if saved then
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
-- Merchants
---------------------------------------------------------------------------

-- Every reagent the data knows, a line a frame (the data's text is long).
function Mg.ReagentStep()
	local data = ns.RecipeData
	local line = data and data.order and data.order[reagentNext]
	local text = line and data.recipes and data.recipes[line]
	if type(text) == "string" then
		for id in text:gmatch("(%d+)%*%d+") do
			reagentSet[tonumber(id)] = true
		end
	end
	reagentNext = line and reagentNext + 1 or nil
end

-- What the merchant on screen sells that's a reagent, for one (no other currencies).
function Mg.ReadMerchant()
	if not reagentSet then
		reagentSet, reagentNext = {}, 1
		return
	elseif reagentNext then
		return -- (still building)
	end
	merchantDue = false
	local n = Number(LT.Value(GetMerchantNumItems)) or 0
	local learned = false
	for i = 1, n do
		local item = Number(LT.Value(GetMerchantItemID, i))
		if item and reagentSet[item] then
			local price, stack, extended
			if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
				local info = LT.Value(C_MerchantFrame.GetItemInfo, i)
				if type(info) == "table" then
					price, stack, extended = Number(info.price), Number(info.stackCount), info.hasExtendedCost
				end
			elseif GetMerchantItemInfo then
				local ok, _, _, p, q, _, _, _, ext = pcall(GetMerchantItemInfo, i)
				if ok then
					price, stack, extended = Number(p), Number(q), ext
				end
			end
			if price and price > 0 and extended ~= true then
				local unit = price / math.max(1, stack or 1)
				local old = saved.vendor[item]
				if not (type(old) == "table" and old.p == unit) then
					learned = true
				end
				saved.vendor[item] = { p = unit, t = time() }
			end
		end
	end
	if learned then
		Changed()
	end
end

---------------------------------------------------------------------------
-- Events, switching
---------------------------------------------------------------------------

local function SameItem(key, item)
	if type(key) == "table" then
		return Number(key.itemID) == item
	end
	return Number(key) == item
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, arg)
	if event == "AUCTION_HOUSE_SHOW" then
		ahOpen = true
		Changed()
	elseif event == "AUCTION_HOUSE_CLOSED" then
		ahOpen = false
		Changed()
		if scan then
			Wake() -- (the driver ends it)
		end
	elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
		merchantDue = true
		Wake()
	elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
		if scan and scan.kind == "replicate" and scan.waiting and not scan.came then
			scan.came = GetTime()
		end
	elseif scan and scan.inflight and not scan.inflight.came and SameItem(arg, scan.inflight.item) then
		scan.inflight.came = GetTime() -- (COMMODITY_SEARCH_RESULTS_UPDATED, ITEM_SEARCH_RESULTS_UPDATED)
	end
end)
local EVENTS = { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
	"REPLICATE_ITEM_LIST_UPDATE", "MERCHANT_SHOW", "MERCHANT_UPDATE" }

-- Prices older than KEEP go, on every realm; what was saved broken goes too.
local function Prune()
	local limit = time() - KEEP
	for key, list in pairs(saved.ah) do
		if type(list) ~= "table" then
			saved.ah[key] = nil
		else
			for item, e in pairs(list) do
				if type(e) ~= "table" or type(e.t) ~= "number" or e.t < limit then
					list[item] = nil
				end
			end
			if not next(list) then
				saved.ah[key] = nil
			end
		end
	end
	for item, e in pairs(saved.vendor) do
		if type(e) ~= "table" or type(e.p) ~= "number" then
			saved.vendor[item] = nil
		end
	end
end

local function Start()
	local db = LT.db
	db.margins = type(db.margins) == "table" and db.margins or {}
	saved = db.margins
	for _, key in ipairs({ "ah", "vendor", "replicated" }) do
		saved[key] = type(saved[key]) == "table" and saved[key] or {}
	end
	local faction = UnitFactionGroup("player")
	realmKey = tostring(GetRealmName()) .. "-" .. (type(faction) == "string" and not issecret(faction) and faction or "")
	Prune()
	local frame = _G.AuctionHouseFrame
	ahOpen = type(frame) == "table" and frame.IsShown and frame:IsShown() == true or false
	for _, event in ipairs(EVENTS) do
		pcall(events.RegisterEvent, events, event)
	end
	Changed()
end

local function Stop()
	events:UnregisterAllEvents()
	scan, merchantDue, ahOpen = nil, false, false
	driver:Hide()
	saved = nil
	Changed()
end

-- Chronicle's OnEnable, OnDisable and OnSettingChanged.
function C.MarginsEnable()
	if M.db.margins then
		Start()
	end
	if C.MarginsUIChanged then
		C.MarginsUIChanged()
	end
end

function C.MarginsDisable()
	Stop()
	if C.MarginsUIChanged then
		C.MarginsUIChanged()
	end
end

function C.MarginsSettingChanged()
	if M.enabled and M.db.margins and not saved then
		Start()
	elseif not (M.enabled and M.db.margins) and saved then
		Stop()
	end
	if C.MarginsUIChanged then
		C.MarginsUIChanged()
	end
end
