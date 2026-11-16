-- WhyPoor?: the price engine (Prices.lua) and friends' prices (Share.lua): when it runs, Margins' old prices
-- taken over, the codec, the daily lows and their time-weighted median, unstable prices, confidence; searches
-- item by item, the full scan (read over frames, every item, the 15-minute rule, no answer); listings gone before
-- they could expire (relisted ones not), my own auctions sold and expired (by ID, by name, once each), the
-- deposit (the game's, what it said before, its rounding), AHSale and Best, merchants, a neutral auction house,
-- pruning; sharing over Beacon (the offer, answering, asking, taking only newer data, other realms, the limits,
-- older builds, the setting); nothing running idle.
-- Needs: margins.lua (it leaves the engine with this realm's prices, and runs Margins on the same engine)
local suite = ...
local check, section, ns, LT = suite.check, suite.section, suite.ns, suite.LT
local sentTo, anna, peers = suite.sentTo, suite.anna, suite.peers
local W = ns.WhyPoor
local P, S = W.Prices, W.Share
local WP = LT:GetModule("whypoor")
local CH = LT:GetModule("chronicle")
local REALM = "Realmy-Alliance"
local spent = 0
local function Wait(seconds)
	Advance(seconds)
	spent = spent + seconds
end
local function DB() return W.DB().prices end
local function Items() return DB().houses[REALM].items end
local DAY = 86400
local function Put(item, seen, low, qty, days) -- days: { { age in days, low, qty }, ... }
	local e = { seen = seen, low = low, qty = qty or 0, days = {} }
	local today = P.Today()
	for _, d in ipairs(days or {}) do e.days[#e.days + 1] = { today - d[1], d[2], d[3] or 1 } end
	table.sort(e.days, function(a, b) return a[1] > b[1] end)
	Items()[item] = P.Encode(e)
end

local CLOTH, ORE, GEM, FRIENDS_ITEM = 4306, 2771, 1210, 6000
ITEMS[CLOTH] = { name = "Silk Cloth", quality = 1, price = 50 }
ITEMS[ORE] = { name = "Tin Ore", quality = 1, price = 0 }
ITEMS[GEM] = { name = "Shadowgem", quality = 2, price = 100 }

section("WhyPoor? prices: the engine runs while it's wanted")
check(P.running and WP.enabled, "WhyPoor? on: running")
LT:SetModuleSetting(CH, "margins", false)
LT:SetModuleEnabled("whypoor", false)
Wait(1)
check(not P.running and not P.driver:IsShown(), "WhyPoor? off and Chronicle's margins off: stopped")
Fire("MERCHANT_SHOW")
Wait(1)
check(not P.Busy(), "stopped: events aren't heard")
LT:SetModuleSetting(CH, "margins", true)
Wait(1)
check(P.running, "Chronicle's margins on: running")
LT:SetModuleEnabled("whypoor", true)
Wait(1)
check(P.running and WP.enabled, "both on")

section("WhyPoor? prices: Margins' old prices taken over once")
DB().imported = nil
local old = time() - 3600
LefthyToolsDB.margins = { ah = { [REALM] = { [5000] = { p = 50, q = 4, t = old }, [5002] = { q = 0, t = old } },
	["Other-Horde"] = { [5000] = { p = 70, q = 1, t = old } } }, vendor = { [5001] = { p = 7, t = old } },
	replicated = { [REALM] = DB().replicated or 0 } }
P.Import()
local imported = P.AHPrice(5000)
check(imported and imported.p == 50 and imported.q == 4 and imported.t == old, "a price, its count and its time")
check(P.AHPrice(5002) and P.AHPrice(5002).p == nil, "none listed stays none listed")
check(P.Get(5000).value == 50 and P.Get(5000).days == 1, "a day of history from it")
check(DB().houses["Other-Horde"].items[5000] ~= nil, "every realm and faction")
check(select(1, P.VendorBuy(5001)) == 7 and select(2, P.VendorBuy(5001)) == true, "a merchant's price")
check(LefthyToolsDB.margins == nil and DB().imported, "Margins keeps nothing of its own any more")
LefthyToolsDB.margins = { ah = { [REALM] = { [5003] = { p = 1, q = 1, t = old } } } }
P.Import()
check(P.AHPrice(5003) == nil, "only once")
LefthyToolsDB.margins = nil
DB().houses["Other-Horde"] = nil

section("WhyPoor? prices: the codec")
check(P.B36(0) == "0" and P.B36(35) == "z" and P.B36(36) == "10" and P.N36("10") == 36, "base 36")
check(P.B36(123456789) == "21i3v9" and P.N36(P.B36(1.8e9)) == 1.8e9, "big numbers both ways")
local e = P.Decode(P.Encode({ seen = 1700000000, low = nil, qty = 0, days = { { 19700, 120, 3 }, { 19699, 0, 1 } } }))
check(e.seen == 1700000000 and e.low == nil and e.qty == 0, "the last scan: none listed")
check(#e.days == 2 and e.days[1][2] == 120 and e.days[2][2] == 0 and e.days[2][3] == 1, "the days (a price of 0 is a price)")
check(P.Decode("broken") == nil and P.Decode(nil) == nil, "broken text: nothing")

section("WhyPoor? prices: daily lows, value, unstable, confidence")
local now = time()
Put(7001, now, 100, 10, { { 0, 100 }, { 1, 100 }, { 2, 100 }, { 3, 100 }, { 4, 100 } })
local g = P.Get(7001)
check(g.value == 100 and g.days == 5 and not g.unstable and g.confidence == "high", "five steady days, fresh: high")
Put(7002, now, 10, 10, { { 0, 10 }, { 1, 10 }, { 11, 100 }, { 12, 100 }, { 13, 100 } })
check(P.Get(7002).value == 10, "time-weighted: two recent days outweigh three old ones (the plain median would be 100)")
Put(7003, now, 200, 10, { { 0, 200 }, { 1, 100 }, { 2, 100 } })
check(P.Get(7003).value == 100, "today's spike doesn't move the value")
check(P.Get(7003).low == 200, "the last scan's lowest is still said")
Put(7004, now, 100, 10, { { 0, 100 }, { 1, 300 }, { 2, 30 }, { 3, 250 }, { 4, 60 } })
check(P.Get(7004).unstable and P.Get(7004).confidence == "low", "prices that jump: unstable, low confidence")
Put(7005, now, 100, 10, { { 0, 100 }, { 1, 400 } })
Put(7006, now, 100, 10, { { 0, 100 }, { 1, 250 } })
check(P.Get(7005).unstable and not P.Get(7006).unstable, "two days: more than three times apart is unstable")
Put(7007, now - 4 * 3600, 100, 10, { { 0, 100 }, { 1, 100 }, { 2, 100 }, { 3, 100 } })
check(P.Get(7007).confidence == "medium", "four steady days but 4 hours old: medium")
Put(7008, now, 100, 10, { { 0, 100 } })
check(P.Get(7008).confidence == "low" and P.Get(7008).value == 100, "one day: low")
Put(7009, now, 100, 1, { { 0, 100 }, { 1, 100 }, { 2, 100 }, { 3, 100 } })
check(P.Get(7009).confidence == "medium", "one listed: not high")
Put(7010, now, nil, 0, { { 20, 100 } })
check(P.Get(7010).value == nil and P.Get(7010).days == 0, "a day older than 14 days doesn't count")
check(P.Get(7011) == nil, "never seen: nil")
check(P.Get(7001).sells == nil and P.Get(7001).perDay == nil, "how well it sells: not known yet")

section("WhyPoor? prices: searching item by item")
Fire("AUCTION_HOUSE_SHOW")
AH_COMMODITY[CLOTH] = true
AH_LISTINGS[CLOTH] = { { 30, 2, own = true }, { 40, 10 }, { 45, 5 } }
check(P.ScanItems({ CLOTH }), "asked")
Wait(2)
g = P.Get(CLOTH)
check(g and g.low == 40 and g.qty == 17 and g.days == 1 and g.value == 40, "the lowest not of mine, all listed")
AH_LISTINGS[CLOTH] = { { 60, 10 } }
P.ScanItems({ CLOTH })
Wait(2)
g = P.Get(CLOTH)
check(g.low == 60 and g.qty == 10 and g.days == 1 and g.value == 40, "again the same day: the last scan says 60, the day's lowest stays 40")
AH_LISTINGS[CLOTH] = { { 40, 10 }, { 45, 5 } }

section("WhyPoor? prices: the whole auction house")
DB().replicated = time() - 1000
Put(7020, now - 60, 500, 3, { { 0, 500 } })
AH_LISTINGS[ORE] = { { 7, 20 }, { 9, 40 } }
AH_REPLICATE_FILLER = 300
local fakeMs = 0
debugprofilestop = function() fakeMs = fakeMs + 1; return fakeMs end
local before = AH_REPLICATES
check(P.ScanFull(), "a full scan")
check(AH_REPLICATES == before + 1 and P.Status().kind == "replicate", "one request")
local frames, reading = 0, 0
while P.Status().running and frames < 400 do
	Advance(1 / 60)
	frames = frames + 1
	local st = P.Status()
	if st.running and st.total > 0 then reading = reading + 1 end
end
spent = spent + frames / 60
debugprofilestop = nil
check(not P.Status().running and reading >= 3, "read over several frames, got " .. reading)
check(P.Get(ORE).low == 7 and P.Get(ORE).qty == 60, "an item no one asked for: kept")
check(P.Get(999999).low == 101 and P.Get(999999).qty == 300, "every item, the cheapest for one")
local items, inItems = P.Items(), {}
for i, item in ipairs(items) do inItems[item] = true; assert(i == 1 or items[i - 1] < item) end
check(inItems[ORE] and inItems[999999] and inItems[7020] and not inItems[7011], "P.Items: every item this auction house has data of, sorted")
check(P.Get(7020).low == nil and P.Get(7020).qty == 0 and P.Get(7020).value == 500, "known but not in it: none listed, its history stays")
check(time() - P.LastScan() <= 3, "the last full scan")
local can, at = P.CanReplicate()
check(not can and at == DB().replicated + 900, "the next only 15 minutes later")
before = AH_REPLICATES
check(not P.ScanFull() and AH_REPLICATES == before, "too soon: not asked")
DB().replicated = time() - 1000
AH_REPLICATE_NONE = true
local fellBack = false
check(P.ScanFull(function() fellBack = true; return { CLOTH } end), "asked again")
Wait(31)
check(fellBack, "no answer in 30 s: the fallback's items")
Wait(2)
check(not P.Status().running, "and those searched")
AH_REPLICATE_NONE = false

section("WhyPoor? prices: listings gone before they could expire")
local A = C_AuctionHouse
local saved = { ReplicateItems = A.ReplicateItems, GetNumReplicateItems = A.GetNumReplicateItems,
	GetReplicateItemInfo = A.GetReplicateItemInfo, GetReplicateItemTimeLeft = A.GetReplicateItemTimeLeft,
	GetTimeLeftBandInfo = A.GetTimeLeftBandInfo }
local rows = {}
A.ReplicateItems = function()
	AH_REPLICATES = AH_REPLICATES + 1
	C_Timer.After(1, function() Fire("REPLICATE_ITEM_LIST_UPDATE") end)
end
A.GetNumReplicateItems = function() return #rows end
A.GetReplicateItemInfo = function(i) -- { item, count, buyout for the stack, owner, band }
	local r = rows[i + 1]
	if r then return "Item", 1, r[2], 1, true, 1, "", 0, 0, r[3], 0, nil, nil, r[4], r[4], 0, r[1], true end
end
A.GetReplicateItemTimeLeft = function(i) return rows[i + 1][5] end
local BANDS = { [0] = 0, 1800, 7200, 43200 }
A.GetTimeLeftBandInfo = function(band) return BANDS[band], BANDS[band + 1] or 172800 end
local function FullScan(list)
	rows = list
	DB().replicated = time() - 1000
	P.ScanFull()
	Wait(2)
end
FullScan({ { GEM, 5, 500, "Ann", 3 }, { GEM, 10, 1200, "Bob", 3 }, { GEM, 2, 300, "", 0 }, { GEM, 3, 390, "Cid", 3 } })
check(P.Get(GEM).low == 100 and P.Get(GEM).qty == 20, "the first scan")
P.last.t = P.last.t - 3600 -- (as if an hour had passed)
FullScan({ { GEM, 10, 1200, "Bob", 3 }, { GEM, 3, 375, "Cid", 3 } })
local flow = P.DecodeDays(DB().houses[REALM].flow[GEM], P.Today())
check(flow[1] and flow[1][2] == 5 and flow[1][3] >= 3600 and flow[1][3] <= 3605,
	"gone: Ann's 5 (bought or taken back); the short one could have expired; Cid relisted, got " .. tostring(flow[1] and flow[1][2]))
check(P.Get(GEM).perDay == nil, "an hour watched: too little for a number")
P.last.t = P.last.t - 3600
FullScan({ { GEM, 10, 1200, "Bob", 3 }, { GEM, 3, 375, "Cid", 3 } })
check(math.abs((P.Get(GEM).perDay or 0) - 60) < 0.2, "two hours watched, 5 gone: about 60 a day, got " .. tostring(P.Get(GEM).perDay))
P.last.t = P.last.t - 3 * DAY
FullScan({ { GEM, 10, 1200, "Bob", 3 } })
check(P.DecodeDays(DB().houses[REALM].flow[GEM], P.Today())[1][3] < 7300, "scans more than two days apart aren't compared")
for k, f in pairs(saved) do A[k] = f end

section("WhyPoor? prices: my own auctions")
local owned = {}
local queried = 0
A.QueryOwnedAuctions = function() queried = queried + 1; C_Timer.After(0.3, function() Fire("OWNED_AUCTIONS_UPDATED") end) end
A.GetNumOwnedAuctions = function() return #owned end
A.GetOwnedAuctionInfo = function(i) return owned[i] end
owned = { { auctionID = 77, itemKey = { itemID = GEM }, status = 0, quantity = 2 },
	{ auctionID = 78, itemKey = { itemID = GEM }, status = 0, quantity = 1 },
	{ auctionID = 79, itemKey = { itemID = GEM }, status = 0, quantity = 1 },
	{ auctionID = 80, itemKey = { itemID = GEM }, status = 0, quantity = 1 } }
Fire("AUCTION_HOUSE_AUCTION_CREATED", 80)
Wait(2)
check(queried == 1 and P.Posted(77) and P.Posted(77).item == GEM and P.Posted(77).q == 2, "after posting: my auctions asked for and remembered")
Fire("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 4, "Shadowgem", 77)
Fire("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 4, "Shadowgem", 77)
Wait(1)
local own = P.DecodeDays(DB().houses[REALM].own[GEM], P.Today())
check(own[1] and own[1][2] == 1 and own[1][3] == 0, "sold, by its ID, counted once")
Fire("AUCTION_CANCELED", 79)
Fire("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 5, "Shadowgem")
Wait(1)
own = P.DecodeDays(DB().houses[REALM].own[GEM], P.Today())
check(own[1][3] == 1 and P.Posted(78).done and not P.Posted(80).done, "expired, by its name: my oldest such auction (a cancelled one isn't)")
check(P.Get(GEM).sells == nil, "two outcomes: too few to say")
owned[4].status = 1
Fire("OWNED_AUCTIONS_UPDATED")
Wait(1)
Fire("OWNED_AUCTIONS_UPDATED")
Wait(1)
check(math.abs(P.Get(GEM).sells - 2 / 3) < 1e-9, "sold as the game lists it, counted once: 2 of 3")
Fire("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 5, "Silk Cloth")
Wait(1)
check(P.DecodeDays(DB().houses[REALM].own[CLOTH], P.Today())[1][3] == 1, "an auction I didn't see posted: by the item's name")
Fire("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 1, "Shadowgem")
Fire("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 4, "No Such Thing")
Wait(1)
check(math.abs(P.Get(GEM).sells - 2 / 3) < 1e-9, "other notifications, unknown names: nothing")
A.QueryOwnedAuctions, A.GetNumOwnedAuctions, A.GetOwnedAuctionInfo = nil, nil, nil

section("WhyPoor? prices: the deposit, AHSale, Best")
check(P.Deposit(GEM, 4) == nil, "the game never said: unknown")
A.CalculateCommodityDeposit = function(item, duration, n) return item == GEM and 15 * n * duration or nil end
A.SupportsCopperValues = function() return true end
CVARS.auctionHouseDurationDropdown = "1"
local d, how = P.Deposit(GEM, 4)
check(d == 60 and how == "game", "open: the game's, for the duration last picked")
Fire("AUCTION_HOUSE_CLOSED")
Wait(1)
d, how = P.Deposit(GEM, 4)
check(d == 60 and how == "seen", "closed: what it said for as many")
check(P.Deposit(GEM, 10) == 150 and P.Deposit(GEM, 1) == 15, "scaled: it was seen to be n times the one for one")
A.SupportsCopperValues = function() return false end
check(P.Deposit(GEM, 4) == 100, "rounded up to silver where the game doesn't take copper")
A.SupportsCopperValues = function() return true end
CVARS.auctionHouseDurationDropdown = "2"
check(P.Deposit(GEM, 4) == nil, "another duration: unknown again")
CVARS.auctionHouseDurationDropdown = "1"
Put(GEM, time(), 90, 20, { { 0, 90 }, { 1, 100 }, { 2, 100 } })
local copper, unit, chance, deposit = P.AHSale(GEM, 4)
check(unit == 90 and math.abs(chance - 2 / 3) < 1e-9 and deposit == 60, "the lower of the lowest and the value; the chance; the deposit")
check(math.abs(copper - (2 / 3 * 4 * 90 * 0.95 - 1 / 3 * 60)) < 1e-6, "sells x n x unit x 0.95 - (1 - sells) x deposit, got " .. tostring(copper))
copper, unit, chance = P.AHSale(7001, 3)
check(math.abs(copper - 285) < 1e-6 and unit == 100 and chance == nil, "no sell chance: what it brings if it sells, after the cut")
Put(7030, time(), nil, 0, { { 1, 80 } })
check(select(2, P.AHSale(7030, 1)) == 80, "none listed now: the value")
check(P.AHSale(7011, 1) == nil, "no price: nil")
local way, money, why = P.Best(GEM, 4)
check(way == "vendor" and money == 400 and why == "vendor-more", "a vendor pays more: vendor")
ITEMS[GEM].price = 10
way, money, why = P.Best(GEM, 4)
check(way == "ah" and math.abs(money - copper) > 0 and why == "ah-more", "the auction house brings more")
Put(GEM, time(), 90, 20, { { 0, 100 }, { 1, 400 } })
local _
way, _, why = P.Best(GEM, 4)
check(way == "vendor" and why == "ah-unstable", "unstable prices: the vendor's certain money")
way, money, why = P.Best(ORE, 2)
check(way == "ah" and money == 2 * 7 * 0.95 and why == "ah-only", "vendors don't buy it: the auction house")
way, money, why = P.Best(7011, 1)
check(way == nil and money == nil and why == "no-price", "nothing known")
A.CalculateCommodityDeposit, A.SupportsCopperValues, CVARS.auctionHouseDurationDropdown = nil, nil, nil
ITEMS[GEM].price = 100

section("WhyPoor? prices: merchants")
MERCHANT = { { CLOTH, 40, 5 }, { 7999, 500, 1, extended = true } }
Fire("MERCHANT_SHOW")
Wait(1)
local p, seen = P.VendorBuy(CLOTH)
check(p == 8 and seen, "what a merchant asks for one")
check(P.VendorBuy(7999) == nil, "bought with something else than gold: not taken")
check(P.Vendor(CLOTH) == 50 and P.Vendor(ORE) == 0, "what vendors pay (0: they don't buy it)")
MERCHANT = {}

section("WhyPoor? prices: a neutral auction house")
local bestMap = C_Map.GetBestMapForUnit
C_Map.GetBestMapForUnit = function() return 1446 end
Put(CLOTH, time(), 40, 15, { { 0, 40 } })
Fire("AUCTION_HOUSE_SHOW")
AH_LISTINGS[CLOTH] = { { 1, 1 } }
P.ScanItems({ CLOTH })
Wait(2)
check(DB().houses["Realmy-Neutral"] and P.Decode(DB().houses["Realmy-Neutral"].items[CLOTH]).low == 1, "kept as the neutral house's")
check(P.Get(CLOTH).low == 40, "not mixed into my faction's")
Fire("AUCTION_HOUSE_CLOSED")
Wait(1)
C_Map.GetBestMapForUnit = bestMap
AH_LISTINGS[CLOTH] = { { 40, 10 }, { 45, 5 } }

section("WhyPoor? prices: friends")
local house = LT.Hash32(REALM)
local h = DB().houses[REALM]
anna("H2")
anna("V2;" .. "0.7.0-500-gabcdef0")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "H2", "WHISPER", 16) -- (Finn: an older build)
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "V2;0.7.0-100-gabcdef0", "WHISPER", 16)
Wait(2)
check(peers()[11] and S.Reads(peers()[11]) and peers()[16] and not S.Reads(peers()[16]), "Anna reads prices, Finn's build doesn't")
local mark = #GAMEDATA + 1
S.Scanned(REALM)
Wait(2)
local offers = sentTo(11, mark, "B2;wo;")
check(#offers == 1 and offers[1]:match("^B2;wo;(%x+);%d+$") == house, "after my scan: an offer naming my auction house, got " .. #offers)
check(#sentTo(16, mark, "B2;w") == 0, "an older build gets nothing")
S.Scanned(REALM)
Wait(2)
check(#sentTo(11, mark, "B2;wo;") == 1, "again within 10 minutes: no second offer")

mark = #GAMEDATA + 1
anna("B2;wq;" .. house)
Wait(20)
local parts, ends = sentTo(11, mark, "B2;wp;"), sentTo(11, mark, "B2;we;")
local count, long, gemEntry, unlistedSeen, order = 0, 0, nil, false, true
for _, m in ipairs(parts) do
	long = math.max(long, #m)
	for entry in m:match("^B2;wp;%x+;%d+;(.*)$"):gmatch("[^,]+") do
		count = count + 1
		if entry:match("^(%w+):") == P.B36(CLOTH) then gemEntry = entry end
		local listed = entry:match("^%w+:%w*:(%w*):") ~= ""
		if listed and unlistedSeen then order = false end
		unlistedSeen = unlistedSeen or not listed
	end
end
check(order and unlistedSeen, "the items listed at my scan first, then the rest")
check(#parts >= 2 and #ends == 1 and ends[1] == "B2;we;" .. house .. ";" .. count, "asked: my prices, then that's all (" .. count .. " in " .. #parts .. ")")
check(long <= 255, "each message within 255 bytes, got " .. long)
check(gemEntry == P.B36(CLOTH) .. ":" .. P.B36(40) .. ":" .. P.B36(40) .. ":" .. P.B36(15) .. ":1:", "an item: value, lowest, listed, days, got " .. tostring(gemEntry))
mark = #GAMEDATA + 1
anna("B2;wq;" .. house)
Wait(3)
check(#sentTo(11, mark, "B2;wp;") == 0, "asked again at once: not answered (30 minutes)")
anna("B2;wq;0badf00d")
Wait(2)
check(#sentTo(11, mark, "B2;w") == 0, "another realm or faction: nothing")

mark = #GAMEDATA + 1
anna("B2;wo;" .. house .. ";0")
Wait(2)
check(#sentTo(11, mark, "B2;wq;") == 0, "their scan isn't newer than mine: not asked")
S.friends[11].theirs = nil
h.scan = h.scan - 7200
anna("B2;wo;0badf00d;0")
Wait(2)
check(#sentTo(11, mark, "B2;wq;") == 0, "another auction house's offer: not asked")
anna("B2;wo;" .. house .. ";60")
Wait(2)
check(#sentTo(11, mark, "B2;wq;") == 1, "theirs is newer: asked")
local B36 = P.B36
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "B2;wp;" .. house .. ";60;" .. B36(FRIENDS_ITEM) .. ":" .. B36(77) .. "::0:3:", "WHISPER", 12)
anna("B2;wp;" .. house .. ";60;" .. B36(FRIENDS_ITEM) .. ":" .. B36(70) .. ":" .. B36(65) .. ":" .. B36(9) .. ":5:," .. B36(CLOTH) .. ":1:1:1:1:,"
	.. "zzzzzzzzzz:1:1:1:1:," .. B36(7040) .. "::::1:")
Wait(1)
g = P.Get(FRIENDS_ITEM)
check(g and g.friend == "Anna Brook" and g.value == 70 and g.low == 65 and g.qty == 9 and g.days == 5, "a friend's price, marked as theirs")
check(g.confidence == "medium" and math.abs(g.seen - (time() - 61)) <= 2, "never high; as old as they said")
check(P.Get(CLOTH).friend == nil and P.Get(CLOTH).low == 40, "my own fresher price isn't replaced")
check(h.friends[7040] == nil, "broken entries: not taken")
anna("B2;we;" .. house .. ";4")
Wait(1)
check(S.pending == nil and h.friendScan and h.friendScan >= time() - 70, "that's all: their scan counts as my newest data")
mark = #GAMEDATA + 1
anna("B2;wo;" .. house .. ";0")
Wait(2)
check(#sentTo(11, mark, "B2;wq;") == 0, "a friend asked at most every 30 minutes")
Put(FRIENDS_ITEM, time(), 50, 2, { { 0, 50 } })
check(P.Get(FRIENDS_ITEM).friend == nil and P.Get(FRIENDS_ITEM).low == 50, "my own newer scan wins over the friend's")

WP.db.sharePrices = false
mark = #GAMEDATA + 1
S.friends[11].answeredAt = nil
anna("B2;wq;" .. house)
anna("B2;wo;" .. house .. ";0")
Wait(3)
check(#sentTo(11, mark, "B2;w") == 0, "sharing off: nothing answered, offered or asked")
WP.db.sharePrices = true
check(#sentTo(16, 1, "B2;w") == 0, "the older build got nothing all along")
Wait(1)

section("WhyPoor? prices: pruning, idle")
Put(7050, time() - 15 * DAY, 10, 1, {})
Items()[7051] = "broken"
DB().houses["Other-Horde"] = { items = { [5000] = P.Encode({ seen = time() - 20 * DAY, qty = 0, days = {} }) } }
LT:SetModuleSetting(CH, "margins", false)
LT:SetModuleEnabled("whypoor", false)
Wait(1)
LT:SetModuleEnabled("whypoor", true)
Wait(1)
LT:SetModuleSetting(CH, "margins", true)
Wait(1)
check(Items()[7050] == nil and Items()[7051] == nil, "older than 14 days, or broken: gone when it starts")
check(DB().houses["Other-Horde"] == nil, "an auction house with nothing left: gone")
check(Items()[7001] ~= nil, "the rest stays")
Wait(1)
check(not P.Busy() and not P.driver:IsShown(), "nothing to do: the driver hides")
check(not S.serving and not S.pending and not S.serves[1], "nothing to send or wait for")

-- (put back what this file changed)
ITEMS[CLOTH], ITEMS[ORE], ITEMS[GEM] = nil, nil, nil
AH_LISTINGS, AH_COMMODITY, AH_REPLICATE_FILLER = {}, {}, 0
Advance(math.ceil(spent - 1e-6) - spent) -- (a whole number of seconds in all)
