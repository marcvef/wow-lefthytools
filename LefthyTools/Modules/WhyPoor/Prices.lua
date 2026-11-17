local _, ns = ...
local LT = ns.LT
local W = ns.WhyPoor or {}
ns.WhyPoor = W

-- Auction house and vendor prices for every item, their history and how sure they are (W.Prices, P): the
-- suite's one auction house engine. Chronicle's Margins reads its prices from here and asks it to scan.
-- docs/whypoor.md ("Prices") has the contract and the rules each number follows.
--
-- Saved in LefthyToolsWhyPoorDB.prices (W.DB().prices), account-wide:
--   houses[<realm>-<faction>] = {          each auction house its own (a neutral one: <realm>-Neutral)
--     scan = t,                            the last full scan read here
--     items[item] = "<seen>,<low>,<qty>;<day>,<low>,<qty>;..."   the last scan that covered it (low empty: none
--                                          listed), then each day's lowest for one and how many (newest first,
--                                          DAYS at most); numbers in base 36, days = time() / 86400
--     flow[item] = "<day>,<gone>,<span>;..."   listings gone before they could expire, seen between two full
--                                          scans of one session (gone: how many; span: the seconds watched)
--     own[item] = "<day>,<sold>,<expired>;..."  my own auctions of it that sold or expired
--     friends[item] = "<seen>,<value>,<low>,<qty>,<days>,<unstable>,<at>;<name>"  a friend's (Share.lua)
--     scans[item] = "<t>,<low>,<qty>;..."   a watched item's every scan (newest first, SCAN_KEEP, SCAN_MAX; one
--                                          within SCAN_MERGE of the newest replaces it; none listed: no point)
--     daily[item] = "<day>,<open>,<high>,<low>,<close>,<qty>,<at>;..."   a watched item's days (newest first,
--                                          LONG_DAYS): the first, highest, lowest and last scan's price for one
--                                          (open, high, close empty: the same as low), the last scan's count and
--                                          its seconds into the day (empty: not known); seeded from items' days
--     sold[item] = "<day>,<gone>,<span>;..."   a watched item's flow days kept LONG_DAYS (as flow, newest first;
--                                          seeded from flow when it's watched): its estimated sales over time
--     unwatched[item] = t                  when it left the watch list: scans, daily and sold go UNWATCH_KEEP later
--   }
--   replicated = t                         the last ReplicateItems asked (the game answers one every 15 min)
--   vendor[item] = copper                  what a merchant asked for one (any realm; seen in its window)
--   posted[auctionID] = "<item>,<qty>,<t>,<house>[,d]"  my auctions, to tell what sold (d: counted or gone)
--   deposit[item] = "<dur>,<d1>,<n>,<dn>"  the game's deposit for one and for n (duration index dur)
--   imported = true                        Margins' old prices (LefthyToolsDB.margins) taken over once
--
-- Watched items: LefthyToolsWhyPoorDB.watch (Stocks.lua's list), looked at once per full scan's commit and per
-- search (P.WatchSet), a set lookup per item. P.Series and P.SeriesSpan read the long history for a chart.
--
-- Events only note; a driver frame does the work a few ms a frame and is hidden while there's none. The
-- engine runs while WhyPoor? or Chronicle's margins setting is on (P.Refresh), nothing at all otherwise.

local P = {}
W.Prices = P

local AH_CUT = 0.05
local STALE = 3 * 3600         -- prices older than this are old (greyed, lower confidence)
local DAY = 86400
local DAYS = 14                -- days of daily lows kept
local KEEP = DAYS * DAY        -- an item's data not seen for this long goes
local HALF_LIFE = 7            -- days: a daily low counts half as much as today's after this long
local QUERY_GAP = 0.65         -- seconds between two searches (the game takes 100 a minute)
local QUERY_WAIT = 3           -- no answer this long: the next one
local SETTLE = 0.2             -- after an answer came, before it's read
local REPLICATE_GAP = 15 * 60  -- the game answers a full scan this often
local REPLICATE_WAIT = 30      -- no full scan's answer this long: the fallback
local READ_MS = 2              -- work this long a frame at most
local STEP = 50                -- rows or items between two looks at the clock
local SEARCH_ROWS = 50         -- an item's search rows looked at for the lowest price for one
local FLOW_GAP_MAX = 48 * 3600 -- two full scans further apart than this aren't compared
local FLOW_SPAN_MIN = 2 * 3600 -- perDay only once listings were watched this long in all
local SOLD_DAY_MIN = 3600      -- a day's own sales estimate only once its listings were watched this long
local SIGS_MAX = 100000        -- listings remembered for the next full scan's compare at most
local POSTED_KEEP = 3 * DAY    -- my auctions watched this long (48 h at most, then the mail)
local OWN_MIN = 3              -- sells from my own auctions once this many sold or expired
local NEUTRAL = { [1434] = true, [1446] = true, [1452] = true } -- Stranglethorn, Tanaris, Winterspring (classic
                               -- uiMapIDs): the neutral auction houses of Booty Bay, Gadgetzan and Everlook
local SCAN_KEEP = 31 * DAY     -- watched items: every scan's point kept this long
local SCAN_MAX = 3000          -- and this many at most (the newest)
local SCAN_MERGE = 5 * 60      -- a point this soon after the newest replaces it (the same look, twice)
local LONG_DAYS = 3 * 366      -- watched items: a point a day kept this many days
local UNWATCH_KEEP = 14 * DAY  -- an item off the watch list keeps its long history this long (added back: still there)
local NOON = DAY / 2           -- a day's point when only the day is known

P.AH_CUT, P.STALE, P.KEEP, P.DAYS = AH_CUT, STALE, KEEP, DAYS
P.SCAN_KEEP, P.SCAN_MAX, P.SCAN_MERGE, P.LONG_DAYS, P.UNWATCH_KEEP = SCAN_KEEP, SCAN_MAX, SCAN_MERGE, LONG_DAYS, UNWATCH_KEEP
P.REPLICATE_GAP, P.READ_MS = REPLICATE_GAP, READ_MS

local issecret = LT.IsSecret
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

-- State (in P's table, so the functions stay under Lua 5.1's upvalue limit).
P.rev = 0
P.running = false
P.ahOpen = false
P.lastSend = -math.huge
P.decoded = {}      -- [house key] = { [item] = { text, entry } }
P.long = {}         -- [house key] = { [item] = { scans text, daily text, scans, days } } (P.LongEntry)
P.asked = {}        -- items whose data was asked for
P.notes = {}        -- auction notifications waiting for the driver
P.wants = {}        -- who wants the engine besides the two modules (P.Want)

local function Number(v)
	return type(v) == "number" and not issecret(v) and v or nil
end

local function Text(v)
	return type(v) == "string" and not issecret(v) and v or nil
end

local function Clock()
	local ok, ms = pcall(debugprofilestop)
	return ok and type(ms) == "number" and ms or nil
end

function P.Changed()
	P.rev = P.rev + 1
end

function P.Revision()
	return P.rev
end

function P.Today(t)
	return math.floor((t or time()) / DAY)
end

---------------------------------------------------------------------------
-- The codec: whole non-negative numbers in base 36
---------------------------------------------------------------------------

function P.B36(n)
	n = math.floor(n + 0.5)
	if n <= 0 then
		return "0"
	end
	local s = ""
	while n > 0 do
		local d = n % 36
		s = DIGITS:sub(d + 1, d + 1) .. s
		n = (n - d) / 36
	end
	return s
end

local function N36(s)
	return s and s ~= "" and tonumber(s, 36) or nil
end
P.N36 = N36

-- An item's saved text as { seen, low (nil: none listed), qty, days = { { day, low, qty }, ... } } (newest first).
function P.Decode(text)
	if type(text) ~= "string" then
		return nil
	end
	local e, first = { days = {} }, true
	for part in text:gmatch("[^;]+") do
		local a, b, c = part:match("^(%w*),(%w*),(%w*)$")
		if first then
			e.seen, e.low, e.qty = N36(a), N36(b), N36(c) or 0
			first = false
		elseif N36(a) and N36(b) then
			e.days[#e.days + 1] = { N36(a), N36(b), N36(c) or 0 }
		end
	end
	return e.seen and e or nil
end

function P.Encode(e)
	local parts = { P.B36(e.seen) .. "," .. (e.low and P.B36(e.low) or "") .. "," .. P.B36(e.qty or 0) }
	for _, d in ipairs(e.days) do
		parts[#parts + 1] = P.B36(d[1]) .. "," .. P.B36(d[2]) .. "," .. P.B36(d[3] or 0)
	end
	return table.concat(parts, ";")
end

-- "<day>,<a>,<b>;..." lists (flow, own): { { day, a, b }, ... }, only days of the last DAYS.
function P.DecodeDays(text, today)
	local list = {}
	if type(text) == "string" then
		for a, b, c in text:gmatch("(%w+),(%w*),(%w*)") do
			local day = N36(a)
			if day and day > today - DAYS then
				list[#list + 1] = { day, N36(b) or 0, N36(c) or 0 }
			end
		end
	end
	return list
end

-- Adds a and b to the day's numbers of such a list and gives its text (or nil: empty).
function P.AddDays(text, today, a, b)
	local list = P.DecodeDays(text, today)
	local hit
	for _, d in ipairs(list) do
		if d[1] == today then
			hit = d
		end
	end
	if not hit then
		hit = { today, 0, 0 }
		table.insert(list, 1, hit)
	end
	hit[2], hit[3] = hit[2] + a, hit[3] + b
	local parts = {}
	for _, d in ipairs(list) do
		parts[#parts + 1] = P.B36(d[1]) .. "," .. P.B36(d[2]) .. "," .. P.B36(d[3])
	end
	return parts[1] and table.concat(parts, ";") or nil
end

---------------------------------------------------------------------------
-- Houses
---------------------------------------------------------------------------

function P.Saved()
	local db = W.DB and W.DB()
	return db and type(db.prices) == "table" and db.prices or nil
end

-- This realm's and faction's auction house: "<realm>-<faction>" (nil: unknown yet).
function P.HomeKey()
	local realm = Text(LT.Value(GetRealmName))
	local faction = Text(LT.Value(UnitFactionGroup, "player"))
	if realm and faction and faction ~= "" then
		return realm .. "-" .. faction
	end
end

-- A house's saved table, made when missing.
function P.House(key)
	local saved = P.Saved()
	if not (saved and key) then
		return nil
	end
	local h = saved.houses[key]
	if type(h) ~= "table" then
		h = {}
		saved.houses[key] = h
	end
	for _, k in ipairs({ "items", "flow", "own", "friends", "scans", "daily", "sold", "unwatched" }) do
		h[k] = type(h[k]) == "table" and h[k] or {}
	end
	return h
end

-- The auction house open now: a neutral one in the three goblin towns' zones, else my faction's.
function P.FindHouse()
	P.houseDue = false
	local key = P.HomeKey()
	local map = Number(LT.Value(C_Map.GetBestMapForUnit, "player"))
	for _ = 1, 8 do
		if not map then
			break
		end
		if NEUTRAL[map] then
			local realm = Text(LT.Value(GetRealmName))
			key = realm and realm .. "-Neutral" or nil
			break
		end
		local info = LT.Value(C_Map.GetMapInfo, map)
		map = type(info) == "table" and Number(info.parentMapID) or nil
	end
	P.openKey = key
end

-- An item's decoded entry in a house (kept while its text stays the same).
function P.Entry(key, item)
	local h = P.Saved() and P.Saved().houses[key]
	local text = type(h) == "table" and type(h.items) == "table" and h.items[item]
	if not text then
		return nil
	end
	local cache = P.decoded[key]
	if not cache then
		cache = {}
		P.decoded[key] = cache
	end
	local c = cache[item]
	if not (c and c[1] == text) then
		c = { text, P.Decode(text) }
		cache[item] = c
	end
	return c[2]
end

-- A new scan's answer for an item: the last scan, and the day's lowest. Gives the new text.
function P.Merge(e, t, low, qty)
	e = e or { days = {} }
	e.seen, e.low, e.qty = t, low, qty or 0
	local today, kept = P.Today(t), {}
	local hit
	for _, d in ipairs(e.days) do
		if d[1] > today - DAYS then
			if d[1] == today then
				hit = d
			end
			kept[#kept + 1] = d
		end
	end
	if low then
		if hit then
			hit[2], hit[3] = math.min(hit[2], low), qty or 0
		else
			table.insert(kept, 1, { today, low, qty or 0 })
		end
	end
	table.sort(kept, function(a, b) return a[1] > b[1] end)
	while #kept > DAYS do
		kept[#kept] = nil
	end
	e.days = kept
	return P.Encode(e)
end

-- A search's or scan's price for one, rounded to whole copper (a lowest under half a copper each is 0).
local function Whole(p)
	return p and math.floor(p + 0.5) or nil
end

function P.Store(key, item, low, qty, t)
	local h = P.House(key)
	if not h then
		return
	end
	t, low = t or time(), Whole(low)
	if P.WatchSet()[item] then
		P.Record(h, item, t, low, qty)
	end
	h.items[item] = P.Merge(P.Decode(h.items[item]), t, low, qty)
	P.Changed()
end

---------------------------------------------------------------------------
-- What an item is worth
---------------------------------------------------------------------------

-- The time-weighted median of the daily lows: each day weighs 0.5^(age / HALF_LIFE).
function P.Value(days, today)
	local list, total = {}, 0
	for _, d in ipairs(days) do
		local age = today - d[1]
		if age >= 0 and age < DAYS then
			local w = 0.5 ^ (age / HALF_LIFE)
			list[#list + 1] = { d[2], w }
			total = total + w
		end
	end
	if not list[1] then
		return nil, 0
	end
	table.sort(list, function(a, b) return a[1] < b[1] end)
	local sum = 0
	for _, v in ipairs(list) do
		sum = sum + v[2]
		if sum >= total / 2 - 1e-9 then
			return v[1], #list
		end
	end
	return list[#list][1], #list
end

local function Median(values)
	table.sort(values)
	local n = #values
	if n % 2 == 1 then
		return values[(n + 1) / 2]
	end
	return (values[n / 2] + values[n / 2 + 1]) / 2
end

-- Prices jump too much to rank on: three or more days whose lows lie further from their median than half of
-- it (the median of the distances), or two days with one more than three times the other.
function P.Unstable(days, today)
	local lows = {}
	for _, d in ipairs(days) do
		if today - d[1] < DAYS then
			lows[#lows + 1] = d[2]
		end
	end
	if #lows == 2 then
		local a, b = math.min(lows[1], lows[2]), math.max(lows[1], lows[2])
		return b > 3 * math.max(a, 1)
	elseif #lows >= 3 then
		local m = Median(lows)
		local dist = {}
		for i, v in ipairs(lows) do
			dist[i] = math.abs(v - m)
		end
		return Median(dist) > 0.5 * math.max(m, 1)
	end
	return false
end

-- How sure: high (4+ days, steady, fresh, 3+ listed), medium (2+ days, steady, a day old at most), else low.
function P.Confidence(days, unstable, age, qty)
	if not unstable and days >= 4 and age <= STALE and (qty or 0) >= 3 then
		return "high"
	elseif not unstable and days >= 2 and age <= DAY then
		return "medium"
	end
	return "low"
end

-- About how many leave a day, and how likely a listing sells (see the file's head and docs/whypoor.md).
function P.Flow(h, item, today)
	local perDay, sells
	local gone, span = 0, 0
	for _, d in ipairs(P.DecodeDays(h.flow[item], today)) do
		gone, span = gone + d[2], span + d[3]
	end
	if span >= FLOW_SPAN_MIN then
		perDay = gone * DAY / span
	end
	local sold, expired = 0, 0
	for _, d in ipairs(P.DecodeDays(h.own[item], today)) do
		sold, expired = sold + d[2], expired + d[3]
	end
	if sold + expired >= OWN_MIN then
		sells = sold / (sold + expired)
	end
	return perDay, sells, sold, expired
end

-- A friend's entry: { seen, value, low, qty, days, unstable, at, name }.
function P.FriendEntry(h, item)
	local text = h and h.friends[item]
	if type(text) ~= "string" then
		return nil
	end
	local nums, name = text:match("^([^;]*);(.*)$")
	local a, b, c, d, e, f, g = (nums or ""):match("^(%w*),(%w*),(%w*),(%w*),(%w*),(%w*),(%w*)$")
	if not (N36(a) and name) then
		return nil
	end
	return { seen = N36(a), value = N36(b), low = N36(c), qty = N36(d) or 0, days = N36(e) or 0, unstable = f == "1",
		at = N36(g), name = name }
end

-- The contract's P.Get: this realm's and faction's auction house.
function P.Get(item)
	local key = P.HomeKey()
	local h = key and P.Saved() and P.Saved().houses[key]
	if type(h) ~= "table" or type(item) ~= "number" then
		return nil
	end
	P.House(key)
	local now = time()
	local today = P.Today(now)
	local e = P.Entry(key, item)
	local fr = P.FriendEntry(h, item)
	if not (e or fr) then
		return nil
	end
	local r = {}
	r.perDay, r.sells = P.Flow(h, item, today)
	if e and not (fr and fr.seen > e.seen) then
		r.low, r.qty, r.seen = e.low, e.qty, e.seen
		r.value, r.days = P.Value(e.days, today)
		r.unstable = P.Unstable(e.days, today)
		r.confidence = P.Confidence(r.days, r.unstable, now - e.seen, e.qty)
	else
		r.low, r.qty, r.seen, r.value, r.days, r.unstable = fr.low, fr.qty, fr.seen, fr.value, fr.days, fr.unstable
		r.friend = fr.name
		local c = P.Confidence(r.days, r.unstable, now - fr.seen, fr.qty)
		r.confidence = c == "high" and "medium" or c -- (a friend's: never high)
	end
	return r
end

-- Margins' old shape: { p (the last scan's lowest for one; nil: none listed), q, t } or nil (never seen).
function P.AHPrice(item)
	local key = P.HomeKey()
	local e = key and P.Entry(key, item)
	return e and { p = e.low, q = e.qty, t = e.seen } or nil
end

function P.LastScan()
	local key = P.HomeKey()
	local h = key and P.Saved() and P.Saved().houses[key]
	return type(h) == "table" and h.scan or nil
end

function P.IsOpen()
	return P.ahOpen
end

---------------------------------------------------------------------------
-- Vendors, selling, the deposit
---------------------------------------------------------------------------

function P.Ask(item)
	if not P.asked[item] then
		P.asked[item] = true
		pcall(C_Item.RequestLoadItemDataByID, item)
	end
end

-- What a vendor pays for one (0: vendors don't buy it), nil while the client doesn't know the item yet.
function P.Vendor(item)
	local ok, name, _, _, _, _, _, _, _, _, _, price = pcall(C_Item.GetItemInfo, ("item:%d"):format(item))
	if ok and Text(name) and Number(price) then
		return price
	end
	P.Ask(item)
end

-- What a vendor asks for one: seen at a merchant (2nd: true), else Data/Recipes.lua's list (false).
function P.VendorBuy(item)
	local saved = P.Saved()
	local seen = saved and saved.vendor[item]
	if Number(seen) then
		return seen, true
	end
	local list = ns.RecipeData and ns.RecipeData.vendor
	local p = list and list[item]
	if type(p) == "number" then
		return p, false
	end
end

-- The duration the player last picked in the auction house (its own CVar), else the first.
function P.Duration()
	local d = tonumber(Text(LT.Value(GetCVar, "auctionHouseDurationDropdown")) or "")
	return d and d >= 1 and d <= 3 and math.floor(d) or 1
end

-- Rounded like the auction house shows it: to silver when the game doesn't take copper.
local function RoundDeposit(d)
	if LT.Value(C_AuctionHouse.SupportsCopperValues) == false then
		return math.ceil(d / 100) * 100
	end
	return d
end

-- Where an item is in my bags (an ItemLocation), or nil.
function P.InBags(item)
	if not (C_Container and ItemLocation) then
		return nil
	end
	for bag = 0, 4 do
		local slots = Number(LT.Value(C_Container.GetContainerNumSlots, bag)) or 0
		for slot = 1, slots do
			if Number(LT.Value(C_Container.GetContainerItemID, bag, slot)) == item then
				return ItemLocation:CreateFromBagAndSlot(bag, slot)
			end
		end
	end
end

-- The game's deposit for n with the auction house open (an item in my bags, else as a commodity by its ID).
function P.AskDeposit(item, n, dur)
	local A = C_AuctionHouse
	local loc = P.InBags(item)
	if loc and A.GetItemCommodityStatus and A.CalculateItemDeposit then
		local status = LT.Value(A.GetItemCommodityStatus, loc)
		local commodity = Enum and Enum.ItemCommodityStatus and Enum.ItemCommodityStatus.Commodity or 2
		if status ~= commodity then
			return Number(LT.Value(A.CalculateItemDeposit, loc, dur, n))
		end
	end
	return A.CalculateCommodityDeposit and Number(LT.Value(A.CalculateCommodityDeposit, item, dur, n)) or nil
end

-- The deposit for n: the game's with the auction house open (2nd: "game"); closed, what the game said for this
-- item at this duration before, for the same n or, once the game's deposit for more than one was seen to be n
-- times the one for one, scaled (2nd: "seen"); else nil. Rounded as the auction house shows it.
function P.Deposit(item, n)
	n = math.max(1, math.floor(n or 1))
	local saved = P.Saved()
	local dur = P.Duration()
	if P.ahOpen and saved then
		local dn = P.AskDeposit(item, n, dur)
		if dn then
			local d1 = n == 1 and dn or P.AskDeposit(item, 1, dur)
			if d1 then
				saved.deposit[item] = table.concat({ dur, P.B36(d1), P.B36(n), P.B36(dn) }, ",")
			end
			return RoundDeposit(dn), "game"
		end
	end
	local text = saved and saved.deposit[item]
	local d, a, b, c = (text or ""):match("^(%d),(%w+),(%w+),(%w+)$")
	if tonumber(d) ~= dur then
		return nil
	end
	local d1, seenN, dn = N36(a), N36(b), N36(c)
	if n == seenN then
		return RoundDeposit(dn), "seen"
	elseif n == 1 then
		return RoundDeposit(d1), "seen"
	elseif seenN > 1 and dn == seenN * d1 then
		return RoundDeposit(d1 * n), "seen"
	end
end

-- What selling n on the auction house brings: the unit price is the lower of the last scan's lowest and the
-- value (the value alone when none is listed), less the 5% cut; when how likely it sells is known (my own
-- auctions) and the deposit too, the deposit lost on what doesn't sell comes off:
--   sells * n * unit * (1 - cut) - (1 - sells) * deposit
-- Returns the copper (nil: no price), the unit price, the sell chance used (nil: assumed to sell) and the
-- deposit counted (nil: none).
function P.AHSale(item, n)
	n = n or 1
	local g = P.Get(item)
	if not g then
		return nil
	end
	local unit = g.value
	if g.low and (not unit or g.low < unit) then
		unit = g.low
	end
	if not unit then
		return nil
	end
	local gross = n * unit * (1 - AH_CUT)
	local deposit = g.sells and P.Deposit(item, n)
	if g.sells and deposit then
		return g.sells * gross - (1 - g.sells) * deposit, unit, g.sells, deposit
	end
	return gross, unit, nil, nil
end

-- The better way to sell n: "vendor" | "ah" | nil, the copper, and why:
--   "no-price" (neither known), "vendor-only" (no auction house price), "ah-only" (vendors don't buy it or its
--   sell price isn't known yet), "ah-unstable" (vendor, since the auction house's prices jump), "vendor-more",
--   "ah-more" (a tie goes to the vendor: it's certain).
function P.Best(item, n)
	n = n or 1
	local each = P.Vendor(item)
	local vendor = each and each > 0 and each * n or nil
	local ah = P.AHSale(item, n)
	if not (vendor or ah) then
		return nil, nil, "no-price"
	elseif not ah then
		return "vendor", vendor, "vendor-only"
	elseif not vendor then
		return "ah", ah, "ah-only"
	end
	local g = P.Get(item)
	if g and g.unstable then
		return "vendor", vendor, "ah-unstable"
	elseif ah > vendor then
		return "ah", ah, "ah-more"
	end
	return "vendor", vendor, "vendor-more"
end

---------------------------------------------------------------------------
-- The driver
---------------------------------------------------------------------------

P.driver = CreateFrame("Frame")
P.driver:Hide()

function P.Wake()
	if P.running then
		P.driver:Show()
	end
end

-- In a coroutine: gives the frame back once READ_MS are used.
function P.Yield()
	local now = Clock()
	if P.sliceStart and now and now - P.sliceStart >= READ_MS then
		coroutine.yield()
	end
end

-- Runs a coroutine for this frame's slice; true while it has more to do.
function P.Resume(co, ...)
	P.sliceStart = Clock()
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		geterrorhandler()(err)
		return false
	end
	return coroutine.status(co) ~= "dead"
end

function P.Tick()
	if P.merchantDue then
		P.ReadMerchant()
	end
	if P.houseDue then
		P.FindHouse()
	end
	if P.ownedDue then
		P.ReadOwned()
	end
	if P.notes[1] then
		P.HandleNotes()
	end
	local fight = LT.InFight()
	local now = GetTime()
	local scan = P.scan
	if scan and not fight then
		if scan.kind == "search" then
			if not P.ahOpen then
				P.Finish(scan)
			else
				P.SearchStep(scan, now)
			end
		else
			P.ReplicateStep(scan, now)
		end
	elseif scan and not P.ahOpen and not scan.committing then
		P.Finish(scan)
	end
	-- The auction house opened: a whole scan when the game allows one again (WhyPoor? on, its setting autoScan;
	-- Margins alone scans when asked, as it always did).
	if P.autoScan and not fight and not P.scan then
		P.autoScan = false
		local m = W.module
		if P.ahOpen and m and m.enabled and type(m.db) == "table" and m.db.autoScan ~= false then
			P.ScanFull()
		end
	end
	if P.ownedAsk and P.ahOpen and not fight and not (P.scan and P.scan.inflight) then
		P.AskOwned(now)
	end
	if P.job and not fight and not P.scan then -- (one at a time: the scan writes what it goes over)
		if not P.Resume(P.job) then
			P.job = nil
		end
	end
	if not P.Busy() then
		P.driver:Hide()
	end
end

P.driver:SetScript("OnUpdate", function()
	LT.Guard("W.PricesTick", P.Tick)
end)

-- Whether the driver has work.
function P.Busy()
	return (P.scan or P.merchantDue or P.houseDue or P.ownedDue or P.notes[1] or P.job or P.autoScan
		or (P.ownedAsk and P.ahOpen)) and true or false
end

---------------------------------------------------------------------------
-- Searching item by item
---------------------------------------------------------------------------

local SORTS = { { sortOrder = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0, reverseSort = false } }

-- The item's key for a search: gear by its item level (the game's, else P.levelHint's: Margins' recipe), the
-- rest without (as the auction house lists them).
function P.ItemKey(item)
	local A = C_AuctionHouse
	local ok, _, _, _, _, _, class = pcall(C_Item.GetItemInfoInstant, item)
	local level = 0
	if ok and (class == 2 or class == 4) then -- (weapons, armour)
		local okLevel, ilvl = pcall(C_Item.GetDetailedItemLevelInfo, item)
		level = okLevel and Number(ilvl) or 0
		if level == 0 and P.levelHint then
			local okHint, hint = pcall(P.levelHint, item)
			level = okHint and Number(hint) or 0
		end
	end
	local made, key = pcall(A.MakeItemKey, item, level)
	return made and type(key) == "table" and key or nil
end

-- An item's search answer: the lowest buyout for one (my own auctions left out) and how many are listed.
function P.ReadResults(item, key)
	local A = C_AuctionHouse
	local best
	local n = Number(LT.Value(A.GetNumCommoditySearchResults, item)) or 0
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

-- Searches these items, one at a time. opts: { front = true (before what a search scan has left), spell (for
-- Margins' status) }. False when the auction house is closed, the engine off or a full scan runs.
function P.ScanItems(items, opts)
	opts = opts or {}
	if not (P.running and P.ahOpen and type(items) == "table") then
		return false
	end
	if P.houseDue then
		P.FindHouse() -- (opened this frame)
	end
	local scan = P.scan
	if scan and scan.kind == "search" then
		if opts.front then
			for k = #items, 1, -1 do
				table.insert(scan.items, scan.i, items[k])
			end
		else
			for _, item in ipairs(items) do
				scan.items[#scan.items + 1] = item
			end
		end
		scan.total = scan.total + #items
		scan.spell = opts.spell or scan.spell
		return true
	elseif scan then
		return false
	end
	local copy = {}
	for k, item in ipairs(items) do
		copy[k] = item
	end
	P.scan = { kind = "search", items = copy, i = 1, total = #items, done = 0, spell = opts.spell,
		key = P.openKey or P.HomeKey() }
	P.Wake()
	return true
end

function P.SearchStep(scan, now)
	local A = C_AuctionHouse
	local f = scan.inflight
	if f then
		if (f.came and now - f.came >= SETTLE) or now - f.sent >= QUERY_WAIT then
			if f.came then
				P.Store(scan.key, f.item, P.ReadResults(f.item, f.key)) -- (no rows: none listed)
			end -- (no answer: the old price stays; rows still there would be an earlier search's)
			scan.inflight, scan.done = nil, scan.done + 1
		end
		return
	end
	local item = scan.items[scan.i]
	if not item then
		P.Finish(scan)
		return
	end
	local ready = LT.Value(A.IsThrottledMessageSystemReady)
	if now - P.lastSend < QUERY_GAP or ready == false then
		return
	end
	scan.i = scan.i + 1
	local key = P.ItemKey(item)
	if not (key and pcall(A.SendSearchQuery, key, SORTS, true)) then
		scan.done = scan.done + 1
		return
	end
	P.lastSend = now
	scan.inflight = { item = item, key = key, sent = now }
end

function P.Finish(scan)
	if P.scan == scan then
		P.scan = nil
	end
	P.Changed()
end

function P.Cancel()
	if P.scan and not P.scan.committing then
		P.scan = nil
		P.Changed()
	end
end

---------------------------------------------------------------------------
-- The whole auction house at once
---------------------------------------------------------------------------

-- Whether the game allows a full scan now, and when it will (time()).
function P.CanReplicate()
	local saved = P.Saved()
	local last = saved and Number(saved.replicated) or 0
	local at = last + REPLICATE_GAP
	return C_AuctionHouse.ReplicateItems ~= nil and time() >= at, at
end

-- A full scan (ReplicateItems) if the game allows it again. fallback: a function giving items to search
-- instead when it doesn't answer (or the answer is empty). True when it started.
function P.ScanFull(fallback)
	if not (P.running and P.ahOpen) or P.scan or not P.CanReplicate() then
		return false
	end
	if P.houseDue then
		P.FindHouse() -- (opened this frame)
	end
	if not pcall(C_AuctionHouse.ReplicateItems) then
		return false
	end
	P.Saved().replicated = time()
	P.scan = { kind = "replicate", waiting = true, sent = GetTime(), total = 0, done = 0, fallback = fallback,
		key = P.openKey or P.HomeKey() }
	P.Wake()
	P.Changed()
	return true
end

function P.Fallback(scan)
	P.scan = nil
	local items = scan.fallback and scan.fallback()
	if type(items) == "table" then
		P.ScanItems(items)
	end
	P.Changed()
end

function P.ReplicateStep(scan, now)
	if scan.waiting then
		if not P.ahOpen then
			P.Finish(scan)
		elseif scan.came and now - scan.came >= SETTLE then
			scan.waiting = false
			scan.n = Number(LT.Value(C_AuctionHouse.GetNumReplicateItems)) or 0
			scan.total, scan.t = scan.n, time()
			if scan.n == 0 or not C_AuctionHouse.GetReplicateItemInfo then
				P.Fallback(scan)
			else
				scan.co = coroutine.create(P.ReadAll)
			end
		elseif now - scan.sent >= REPLICATE_WAIT then
			P.Fallback(scan) -- (no answer)
		end
		return
	end
	if not scan.committing and not P.ahOpen then
		P.Finish(scan) -- (closed while reading: nothing kept of it)
		return
	end
	if not P.Resume(scan.co, scan) then
		P.Finish(scan)
	end
end

-- A time-left band's shortest time (seconds; the game's GetTimeLeftBandInfo), nil: unknown.
function P.BandSeconds(band)
	P.bands = P.bands or {}
	if P.bands[band] == nil then
		local f = C_AuctionHouse.GetTimeLeftBandInfo
		P.bands[band] = f and Number(LT.Value(f, band)) or false
	end
	return P.bands[band] or nil
end

-- The coroutine reading a full scan, then keeping it. Rows: a stack's buyout for its count; one with no buyout
-- (bids only) isn't counted. My own listings count in how many are listed, not in the lowest.
function P.ReadAll(scan)
	local get, left = C_AuctionHouse.GetReplicateItemInfo, C_AuctionHouse.GetReplicateItemTimeLeft
	local found, cnt, bnd = {}, {}, {}
	local tracked = 0
	local track = left ~= nil and P.BandSeconds(0) ~= nil
	local i = 0
	while i < scan.n do
		local _, _, count, _, _, _, _, _, _, buyout, _, _, _, owner, _, _, item = get(i)
		i = i + 1
		item, count, buyout = Number(item), Number(count), Number(buyout)
		if item and count and count > 0 and buyout and buyout > 0 then
			owner = Text(owner) or ""
			local f = found[item]
			if not f then
				f = { q = 0 }
				found[item] = f
			end
			f.q = f.q + count
			if not LT.Names.IsMine(owner ~= "" and owner or nil) then
				f.p = math.min(f.p or math.huge, buyout / count)
			end
			if track and tracked < SIGS_MAX then
				local band = Number(LT.Value(left, i - 1))
				if band then
					local sig = count .. "/" .. buyout .. "/" .. owner
					local c, b = cnt[item], bnd[item]
					if not c then
						c, b = {}, {}
						cnt[item], bnd[item] = c, b
					end
					c[sig] = (c[sig] or 0) + 1
					b[sig] = math.min(b[sig] or band, band)
					tracked = tracked + 1
				end
			end
		end
		if i % STEP == 0 then
			scan.done = i
			P.Yield()
			if not P.ahOpen then
				return
			end
		end
	end
	scan.done, scan.committing = scan.n, true
	P.Commit(scan, found, track and { cnt = cnt, bnd = bnd } or nil)
end

-- Keeps a full scan: every item in it, and every item known here that wasn't (none listed); data not seen
-- for KEEP goes. Then compares it with the session's last full scan of this house (listings gone early).
function P.Commit(scan, found, sigs)
	local key, t = scan.key, scan.t
	local h = P.House(key)
	if not h then
		return
	end
	local items, k = h.items, 0
	local watch = P.WatchSet() -- (once: a set lookup per item)
	for item, f in pairs(found) do
		local low = Whole(f.p)
		if watch[item] then
			P.Record(h, item, t, low, f.q)
		end
		items[item] = P.Merge(P.Decode(items[item]), t, low, f.q)
		k = k + 1
		if k % STEP == 0 then
			P.Yield()
		end
	end
	for item, text in pairs(items) do
		if not found[item] then
			local e = P.Decode(text)
			if not e or t - e.seen > KEEP then
				items[item] = nil
			else
				items[item] = P.Merge(e, t, nil, 0) -- (the whole auction house: not in it means none listed)
			end
			k = k + 1
			if k % STEP == 0 then
				P.Yield()
			end
		end
	end
	local last = P.last
	if sigs and last and last.key == key and t - last.t >= REPLICATE_GAP and t - last.t <= FLOW_GAP_MAX then
		P.CompareScans(h, last, sigs, t)
	end
	P.last = sigs and { key = key, t = t, cnt = sigs.cnt, bnd = sigs.bnd } or nil
	h.scan = t
	P.decoded[key] = nil
	P.Changed()
	if W.Share and W.Share.Scanned then
		LT.Guard("W.Share.Scanned", W.Share.Scanned, key)
	end
end

-- Listings of the earlier scan whose time left was longer than the time between the scans couldn't have
-- expired: those gone in the later one were bought or taken back (the game doesn't say which). Gone listings of
-- a seller who listed as many again count as relisted, not gone (sellers the game names).
function P.CompareScans(h, last, sigs, t)
	local gap = t - last.t
	local today, k = P.Today(t), 0
	for item, before in pairs(last.cnt) do
		local now = sigs.cnt[item] or {}
		local bands = last.bnd[item]
		local goneBy, newBy, watched = {}, {}, 0
		for sig, n in pairs(before) do
			local min = P.BandSeconds(bands[sig])
			if min and min >= gap then
				local count, owner = sig:match("^(%d+)/[^/]*/(.*)$")
				count = tonumber(count) or 0
				watched = watched + n * count
				local gone = n - (now[sig] or 0)
				if gone > 0 then
					goneBy[owner] = (goneBy[owner] or 0) + gone * count
				end
			end
		end
		if watched > 0 then
			for sig, n in pairs(now) do
				local count, owner = sig:match("^(%d+)/[^/]*/(.*)$")
				local more = n - (before[sig] or 0)
				if owner ~= "" and more > 0 then
					newBy[owner] = (newBy[owner] or 0) + more * (tonumber(count) or 0)
				end
			end
			local gone = 0
			for owner, q in pairs(goneBy) do
				gone = gone + (owner == "" and q or math.max(0, q - (newBy[owner] or 0)))
			end
			h.flow[item] = P.AddDays(h.flow[item], today, gone, gap)
			if P.watchSet and P.watchSet[item] then
				h.sold[item] = P.AddSold(h.sold[item], today, gone, gap)
			end
		end
		k = k + 1
		if k % STEP == 0 then
			P.Yield()
		end
	end
end

-- { open, running, kind ("search" | "replicate"), done, total, spell, nextFull (time() a full scan is allowed) }.
function P.Status()
	local s = { open = P.ahOpen }
	local scan = P.scan
	if scan then
		s.running, s.kind, s.done, s.total, s.spell = true, scan.kind, scan.done, scan.total, scan.spell
		s.waiting, s.committing = scan.waiting == true, scan.committing == true
	end
	s.nextFull = select(2, P.CanReplicate())
	return s
end

---------------------------------------------------------------------------
-- Merchants
---------------------------------------------------------------------------

-- What the merchant on screen sells for gold, for one.
function P.ReadMerchant()
	P.merchantDue = false
	local saved = P.Saved()
	if not saved then
		return
	end
	local n = Number(LT.Value(GetMerchantNumItems)) or 0
	local learned = false
	for i = 1, n do
		local item = Number(LT.Value(GetMerchantItemID, i))
		if item then
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
				if saved.vendor[item] ~= unit then
					saved.vendor[item] = unit
					learned = true
				end
			end
		end
	end
	if learned then
		P.Changed()
	end
end

---------------------------------------------------------------------------
-- My own auctions: what sold, what expired
---------------------------------------------------------------------------

-- Asks the game for my auctions (after I posted one), once the throttle is ready.
function P.AskOwned(now)
	local A = C_AuctionHouse
	if not A.QueryOwnedAuctions then
		P.ownedAsk = false
		return
	end
	if now - P.lastSend < QUERY_GAP or LT.Value(A.IsThrottledMessageSystemReady) == false then
		return
	end
	P.ownedAsk = false
	if pcall(A.QueryOwnedAuctions, SORTS) then
		P.lastSend = now
	end
end

function P.Posted(id)
	local saved = P.Saved()
	local text = saved and saved.posted[id]
	local item, q, t, house, done = (text or ""):match("^(%d+),(%d+),(%d+),([^,]*),?(d?)$")
	if item then
		return { item = tonumber(item), q = tonumber(q), t = tonumber(t), house = house, done = done == "d" }
	end
end

function P.SetPosted(id, p)
	P.Saved().posted[id] = ("%d,%d,%d,%s%s"):format(p.item, p.q, p.t, p.house or "", p.done and ",d" or "")
end

-- An outcome of mine: sold (true) or expired (false), counted once.
function P.Outcome(house, item, sold)
	local h = P.House(house)
	if h and item then
		h.own[item] = P.AddDays(h.own[item], P.Today(), sold and 1 or 0, sold and 0 or 1)
		P.Changed()
	end
end

-- My auctions as the game lists them: new ones remembered (what, how many, where), sold ones counted.
function P.ReadOwned()
	P.ownedDue = false
	local saved = P.Saved()
	local A = C_AuctionHouse
	if not (saved and A.GetNumOwnedAuctions and A.GetOwnedAuctionInfo) then
		return
	end
	local sold = Enum and Enum.AuctionStatus and Enum.AuctionStatus.Sold or 1
	local n = Number(LT.Value(A.GetNumOwnedAuctions)) or 0
	for i = 1, n do
		local a = LT.Value(A.GetOwnedAuctionInfo, i)
		local id = type(a) == "table" and Number(a.auctionID)
		local item = id and type(a.itemKey) == "table" and Number(a.itemKey.itemID)
		if item then
			local p = P.Posted(id) or { item = item, q = Number(a.quantity) or 1, t = time(), house = P.openKey or P.HomeKey() }
			if Number(a.status) == sold and not p.done then
				p.done = true
				P.Outcome(p.house, p.item, true)
			end
			P.SetPosted(id, p)
		end
	end
end

-- The game's notifications (AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION, anywhere): sold or expired, by the
-- auction's ID when it comes, else by the item's name among my auctions, else by the name alone.
function P.HandleNotes()
	local saved = P.Saved()
	local list = P.notes
	P.notes = {}
	if not saved then
		return
	end
	for _, note in ipairs(list) do
		local p = note.id and P.Posted(note.id)
		if note.cancel then
			if p then
				p.done = true
				P.SetPosted(note.id, p)
			end
		elseif p then
			if not p.done then
				p.done = true
				P.SetPosted(note.id, p)
				P.Outcome(p.house, p.item, note.sold)
			end
		elseif note.name then
			P.ByName(note.name, note.sold)
		end
	end
end

function P.NameOf(item)
	local ok, name = pcall(C_Item.GetItemInfo, ("item:%d"):format(item))
	return ok and Text(name) or nil
end

function P.ByName(name, sold)
	local saved = P.Saved()
	local link = tonumber(name:match("|Hitem:(%d+)") or "")
	local plain = name:match("|h%[(.-)%]|h") or name
	local bestId, best
	for id in pairs(saved.posted) do
		local p = P.Posted(id)
		if p and not p.done and (p.item == link or (not link and P.NameOf(p.item) == plain)) and (not best or p.t < best.t) then
			bestId, best = id, p
		end
	end
	if best then
		best.done = true
		P.SetPosted(bestId, best)
		P.Outcome(best.house, best.item, sold)
		return
	end
	local item = link
	if not item then
		local ok, _, itemLink = pcall(C_Item.GetItemInfo, plain)
		item = ok and Text(itemLink) and tonumber(itemLink:match("item:(%d+)") or "")
	end
	if item then
		P.Outcome(P.HomeKey(), item, sold)
	end
end

---------------------------------------------------------------------------
-- Pruning (a job over frames when the engine starts)
---------------------------------------------------------------------------

-- A table's keys (one pass, no work per key): what's gone over across frames, as others may add keys meanwhile.
-- An item's history on this realm's and faction's auction house, for a graph: { { day, low, qty }, ... } the
-- oldest first (each day's lowest buyout for one and how many were listed then; days without a scan are
-- missing), up to DAYS days; then the robust value and whether it jumps around. Empty: never scanned.
function P.History(item)
	local key = P.HomeKey()
	local e = key and P.Entry(key, item)
	if not e then
		return {}
	end
	local today = P.Today()
	local list = {}
	for _, d in ipairs(e.days or {}) do
		if d[1] > today - DAYS and d[2] and d[2] > 0 then
			list[#list + 1] = { day = d[1], low = d[2], qty = d[3] or 0 }
		end
	end
	table.sort(list, function(a, b) return a.day < b.day end)
	local value = P.Value(e.days, today)
	return list, value, P.Unstable(e.days, today)
end

---------------------------------------------------------------------------
-- Long history of watched items (the series)
---------------------------------------------------------------------------

function P.ScanText(t, low, qty)
	return P.B36(t) .. "," .. P.B36(low) .. "," .. P.B36(qty or 0)
end

-- A day's entry: { day, open, high, low, close, qty, at (seconds into the day; nil: not known) }.
function P.DayEntry(part)
	local a, b, c, d, e, f, g = (part or ""):match("^(%w+),(%w*),(%w*),(%w+),(%w*),(%w*),(%w*)$")
	local day, low = N36(a), N36(d)
	if not (day and low) then
		return nil
	end
	return { day, N36(b) or low, N36(c) or low, low, N36(e) or low, N36(f) or 0, N36(g) }
end

function P.DayText(d)
	local low = d[4]
	local function Or(v)
		return v and v ~= low and P.B36(v) or ""
	end
	return table.concat({ P.B36(d[1]), Or(d[2]), Or(d[3]), P.B36(low), Or(d[5]), P.B36(d[6] or 0),
		d[7] and P.B36(d[7]) or "" }, ",")
end

-- scans[item]'s points: { { t, low, qty }, ... } newest first (broken ones left out).
function P.DecodeScans(text)
	local list = {}
	if type(text) == "string" then
		for part in text:gmatch("[^;]+") do
			local a, b, c = part:match("^(%w+),(%w+),(%w*)$")
			if N36(a) and N36(b) then
				list[#list + 1] = { N36(a), N36(b), N36(c) or 0 }
			end
		end
	end
	return list
end

-- daily[item]'s days: P.DayEntry's, newest first (broken ones left out).
function P.DecodeDaily(text)
	local list = {}
	if type(text) == "string" then
		for part in text:gmatch("[^;]+") do
			list[#list + 1] = P.DayEntry(part)
		end
	end
	return list
end

-- An items entry's daily lows as day entries (open = high = low = close), newest first; the day of its last scan
-- knows when that was.
function P.ItemDays(e)
	local list = {}
	local seenDay = e.seen and P.Today(e.seen)
	for _, d in ipairs(e.days or {}) do
		list[#list + 1] = { d[1], d[2], d[2], d[2], d[2], d[3] or 0, d[1] == seenDay and e.seen - d[1] * DAY or nil }
	end
	table.sort(list, function(a, b) return a[1] > b[1] end)
	return list
end

-- An item just watched: its daily history starts from the daily lows its items entry has.
function P.Seed(h, item)
	local e = P.Decode(h.items[item])
	if not e then
		return
	end
	local parts = {}
	for i, d in ipairs(P.ItemDays(e)) do
		parts[i] = P.DayText(d)
	end
	h.daily[item] = parts[1] and table.concat(parts, ";") or nil
	if not h.sold[item] and h.flow[item] then
		h.sold[item] = h.flow[item] -- (its estimated sales so far: the same format)
	end
end

-- A day's gone and span added to a newest-first "<day>,<gone>,<span>;..." text (sold): only its first entry is
-- read and rewritten, the same work however long the history. A day older than its newest: left out.
function P.AddSold(text, today, gone, span)
	gone, span = math.max(0, math.floor((gone or 0) + 0.5)), math.max(0, math.floor((span or 0) + 0.5))
	local first, rest = (text or ""):match("^([^;]*)(.*)$")
	local d, a, b = first:match("^(%w+),(%w+),(%w+)$")
	d, a, b = N36(d), N36(a), N36(b)
	if d and a and b and d == today then
		return P.B36(today) .. "," .. P.B36(a + gone) .. "," .. P.B36(b + span) .. rest
	elseif d and d > today then
		return text
	end
	local entry = P.B36(today) .. "," .. P.B36(gone) .. "," .. P.B36(span)
	return (text and text ~= "") and (entry .. ";" .. text) or entry
end

-- An item's estimated sales a day here: listings gone before they could expire over the time they were watched
-- (flow's 14 days; a watched item's sold for longer). Oldest first: { { t (the day's noon), day, gone, span,
-- perDay } } for the days touching from..to whose listings were watched SOLD_DAY_MIN or more; then over those
-- days: perDay (nil: watched less than FLOW_SPAN_MIN in all), gone, span.
function P.SoldSeries(item, from, to)
	from, to = tonumber(from) or -math.huge, tonumber(to) or math.huge
	local out, gone, span = {}, 0, 0
	local key = P.HomeKey()
	local h = key and type(item) == "number" and P.House(key)
	if not h then
		return out, nil, 0, 0
	end
	local byDay = {}
	for _, text in ipairs({ h.sold[item] or "", h.flow[item] or "" }) do -- (no sold text: still the flow's)
		for entry in (text or ""):gmatch("[^;]+") do
			local d, a, b = entry:match("^(%w+),(%w+),(%w+)$")
			d, a, b = N36(d), N36(a), N36(b)
			if d and a and b and not byDay[d] then
				byDay[d] = { a, b }
			end
		end
	end
	for day, e in pairs(byDay) do
		if (day + 1) * DAY > from and day * DAY <= to and e[2] >= SOLD_DAY_MIN then
			out[#out + 1] = { t = day * DAY + NOON, day = day, gone = e[1], span = e[2], perDay = e[1] * DAY / e[2] }
			gone, span = gone + e[1], span + e[2]
		end
	end
	table.sort(out, function(a, b) return a.t < b.t end)
	return out, span >= FLOW_SPAN_MIN and gone * DAY / span or nil, gone, span
end

-- The watched items (LefthyToolsWhyPoorDB.watch, Stocks.lua's list) as a set, built anew each call (the list is
-- short; Stocks.lua changes it without telling). Compared with the last call's: an item that came onto it loses
-- its unwatched mark and gets its daily history seeded in each house that has none yet; one that left is marked
-- (P.PruneLong drops its long history UNWATCH_KEEP later).
function P.WatchSet()
	local db = W.DB and W.DB()
	local set = {}
	for _, item in ipairs(db and type(db.watch) == "table" and db.watch or {}) do
		if type(item) == "number" then
			set[item] = true
		end
	end
	local before = P.watchSet
	P.watchSet = set
	local saved = P.Saved()
	if not (saved and type(saved.houses) == "table") then
		return set
	end
	for item in pairs(set) do
		if not (before and before[item]) then
			for _, key in ipairs(P.Keys(saved.houses)) do
				local h = P.House(key)
				h.unwatched[item] = nil
				if not h.daily[item] and h.items[item] then
					P.Seed(h, item)
				elseif not h.sold[item] and h.flow[item] then
					h.sold[item] = h.flow[item]
				end
			end
		end
	end
	for item in pairs(before or {}) do
		if not set[item] then
			for _, key in ipairs(P.Keys(saved.houses)) do
				local h = P.House(key)
				if (h.daily[item] or h.scans[item] or h.sold[item]) and not h.unwatched[item] then
					h.unwatched[item] = time()
				end
			end
		end
	end
	return set
end

-- A watched item's price at t in a house (low nil: none listed, nothing kept): a scan point (replacing the newest
-- within SCAN_MERGE) and today's day (open, high, low, close, qty, when). Only each text's first entry is read and
-- rewritten: the same work however long the history. Older than the newest: left out (they come in time order).
function P.Record(h, item, t, low, qty)
	if not low then
		return
	end
	qty = qty or 0
	if not h.daily[item] then
		P.Seed(h, item)
	end
	local text = h.scans[item]
	local point = P.ScanText(t, low, qty)
	local first, rest = (text or ""):match("^([^;]*)(.*)$")
	local t0 = N36(first:match("^(%w+),"))
	if not t0 then
		h.scans[item] = point
	elseif t - t0 < SCAN_MERGE and t >= t0 then
		h.scans[item] = point .. rest
	elseif t > t0 then
		h.scans[item] = point .. ";" .. text
	end
	local today = P.Today(t)
	text = h.daily[item]
	first, rest = (text or ""):match("^([^;]*)(.*)$")
	local d = P.DayEntry(first)
	if not d then
		h.daily[item] = P.DayText({ today, low, low, low, low, qty, t - today * DAY })
	elseif d[1] == today and (not d[7] or t - today * DAY >= d[7]) then
		d[3], d[4], d[5], d[6], d[7] = math.max(d[3], low), math.min(d[4], low), low, qty, t - today * DAY
		h.daily[item] = P.DayText(d) .. rest
	elseif d[1] < today then
		h.daily[item] = P.DayText({ today, low, low, low, low, qty, t - today * DAY }) .. ";" .. text
	end
end

-- An item's long history in a house, decoded (kept while its texts stay the same): scans, days (newest first).
function P.LongEntry(key, item)
	local saved = P.Saved()
	local h = saved and type(saved.houses) == "table" and saved.houses[key]
	local s = type(h) == "table" and type(h.scans) == "table" and h.scans[item] or nil
	local d = type(h) == "table" and type(h.daily) == "table" and h.daily[item] or nil
	if not (s or d) then
		return nil, nil
	end
	local cache = P.long[key]
	if not cache then
		cache = {}
		P.long[key] = cache
	end
	local c = cache[item]
	if not (c and c[1] == s and c[2] == d) then
		c = { s, d, P.DecodeScans(s), P.DecodeDaily(d) }
		cache[item] = c
	end
	return c[3], c[4]
end

-- The contract's P.Series: an item's prices between from and to (time(); nil: no bound) on this realm's and
-- faction's auction house, oldest first: { { t, price, qty, open, high, low, close }, ... }, and "scan" (every
-- scan's point: the whole span lies within the watched item's kept scan points, from its oldest on) or "day"
-- (a point a day: the long daily history, the items entry's daily lows for days it hasn't; price = the day's
-- low; t = the day's last scan, else its noon). A new list each call.
function P.Series(item, from, to)
	from, to = tonumber(from) or -math.huge, tonumber(to) or math.huge
	local points = {}
	local key = P.HomeKey()
	if type(item) ~= "number" or not key then
		return points, "day"
	end
	P.WatchSet() -- (seeds an item just watched)
	local scans, days = P.LongEntry(key, item)
	local oldest = scans and scans[#scans]
	if oldest and from >= oldest[1] then
		for i = #scans, 1, -1 do
			local s = scans[i]
			if s[1] >= from and s[1] <= to then
				points[#points + 1] = { t = s[1], price = s[2], qty = s[3] }
			end
		end
		return points, "scan"
	end
	local byDay = {}
	for _, d in ipairs(days or {}) do
		byDay[d[1]] = byDay[d[1]] or d
	end
	local e = P.Entry(key, item)
	for _, d in ipairs(e and P.ItemDays(e) or {}) do
		byDay[d[1]] = byDay[d[1]] or d
	end
	for day, d in pairs(byDay) do
		local t = day * DAY + (d[7] or NOON)
		if t >= from and t <= to then
			points[#points + 1] = { t = t, price = d[4], qty = d[6], open = d[2], high = d[3], low = d[4], close = d[5] }
		end
	end
	table.sort(points, function(a, b) return a.t < b.t end)
	return points, "day"
end

-- The contract's P.SeriesSpan: the first and last point's time known of an item here (nil, nil: none) and whether
-- its history is kept long (it's watched).
function P.SeriesSpan(item)
	local long = P.WatchSet()[item] == true
	local days = P.Series(item)
	local first, last = days[1] and days[1].t, days[#days] and days[#days].t
	local key = P.HomeKey()
	local scans = key and type(item) == "number" and P.LongEntry(key, item)
	if scans and scans[1] then
		first, last = math.min(first or math.huge, scans[#scans][1]), math.max(last or -math.huge, scans[1][1])
	end
	return first, last, long
end

-- Every item with data on this realm's and faction's auction house (mine or a friend's), for the ideas'
-- market pass: a new list each call; nil before the saved table is there.
function P.Items()
	local key = P.HomeKey()
	local h = key and P.House(key)
	if not h then
		return nil
	end
	local out, seen = {}, {}
	for _, list in ipairs({ h.items, h.friends }) do
		for item in pairs(list) do
			if type(item) == "number" and not seen[item] then
				seen[item] = true
				out[#out + 1] = item
			end
		end
	end
	table.sort(out)
	return out
end

function P.Keys(list)
	local keys = {}
	for k in pairs(list) do
		keys[#keys + 1] = k
	end
	return keys
end

function P.PruneJob()
	local saved = P.Saved()
	local now = time()
	local today = P.Today(now)
	local k = 0
	local function Tick()
		k = k + 1
		if k % STEP == 0 then
			P.Yield()
		end
	end
	local function Seen(text)
		return type(text) == "string" and N36(text:match("^(%w+),")) or nil
	end
	local watch = P.WatchSet()
	for _, key in ipairs(P.Keys(saved.houses)) do
		local h = saved.houses[key]
		if type(h) ~= "table" then
			saved.houses[key] = nil
		else
			P.House(key)
			for _, item in ipairs(P.Keys(h.unwatched)) do
				if not (h.daily[item] or h.scans[item] or h.sold[item]) or not Number(h.unwatched[item]) then
					h.unwatched[item] = nil -- (nothing left, or broken: looked at again below)
				end
			end
			local long = P.Keys(h.daily)
			for item in pairs(h.scans) do
				if not h.daily[item] then
					long[#long + 1] = item
				end
			end
			for item in pairs(h.sold) do
				if not (h.daily[item] or h.scans[item]) then
					long[#long + 1] = item
				end
			end
			for _, item in ipairs(long) do
				P.PruneLong(h, item, watch, now)
				Tick()
			end
			for _, list in ipairs({ h.items, h.friends }) do
				for _, item in ipairs(P.Keys(list)) do
					local seen = Seen(list[item])
					if not seen or now - seen > KEEP then
						list[item] = nil
					end
					Tick()
				end
			end
			for _, list in ipairs({ h.flow, h.own }) do
				for _, item in ipairs(P.Keys(list)) do
					if not P.DecodeDays(list[item], today)[1] then
						list[item] = nil
					end
					Tick()
				end
			end
			if not (next(h.items) or next(h.friends) or next(h.own) or next(h.flow) or next(h.daily) or next(h.scans) or h.scan) then
				saved.houses[key] = nil
			end
		end
	end
	for _, id in ipairs(P.Keys(saved.posted)) do
		local p = P.Posted(id)
		if not p or now - p.t > POSTED_KEEP then
			saved.posted[id] = nil
		end
		Tick()
	end
	for _, item in ipairs(P.Keys(saved.vendor)) do
		if not Number(saved.vendor[item]) then
			saved.vendor[item] = nil
		end
	end
	P.decoded, P.long = {}, {}
	P.Changed()
end

-- A watched item's long history in a house at the start: kept while watched; off the watch list, marked and dropped
-- UNWATCH_KEEP later; scan points older than SCAN_KEEP (or beyond SCAN_MAX) and days older than LONG_DAYS go.
function P.PruneLong(h, item, watch, now)
	if watch[item] then
		h.unwatched[item] = nil
	elseif not h.unwatched[item] then
		h.unwatched[item] = now -- (it left the list while the engine was off)
	elseif now - h.unwatched[item] > UNWATCH_KEEP then
		h.scans[item], h.daily[item], h.sold[item], h.unwatched[item] = nil, nil, nil, nil
		return
	end
	local scans, cut = P.DecodeScans(h.scans[item]), now - SCAN_KEEP
	local n = #scans
	while n > 0 and (scans[n][1] < cut or n > SCAN_MAX) do
		scans[n], n = nil, n - 1
	end
	if n == 0 then
		h.scans[item] = nil
	elseif n < select(2, (h.scans[item] or ""):gsub(";", "")) + 1 then
		local parts = {}
		for i, s in ipairs(scans) do
			parts[i] = P.ScanText(s[1], s[2], s[3])
		end
		h.scans[item] = table.concat(parts, ";")
	end
	P.Yield()
	local days, first = P.DecodeDaily(h.daily[item]), P.Today(now) - LONG_DAYS
	n = #days
	while n > 0 and days[n][1] <= first do
		days[n], n = nil, n - 1
	end
	if n == 0 then
		h.daily[item] = nil
	elseif n < select(2, (h.daily[item] or ""):gsub(";", "")) + 1 then
		local parts = {}
		for i, d in ipairs(days) do
			parts[i] = P.DayText(d)
		end
		h.daily[item] = table.concat(parts, ";")
	end
	local sold, kept = h.sold[item], {}
	for entry in (sold or ""):gmatch("[^;]+") do
		local d = N36(entry:match("^(%w+),%w+,%w+$"))
		if d and d > first then
			kept[#kept + 1] = entry
		end
	end
	h.sold[item] = kept[1] and table.concat(kept, ";") or nil
	if not (h.scans[item] or h.daily[item] or h.sold[item]) then
		h.unwatched[item] = nil
	end
	P.Yield()
end

---------------------------------------------------------------------------
-- Margins' old prices, once
---------------------------------------------------------------------------

function P.Import()
	local saved = P.Saved()
	if not saved or saved.imported then
		return
	end
	saved.imported = true
	local old = type(LT.db) == "table" and type(LT.db.margins) == "table" and LT.db.margins
	if not old then
		return
	end
	for key, list in pairs(type(old.ah) == "table" and old.ah or {}) do
		if type(key) == "string" and type(list) == "table" then
			local h = P.House(key)
			for item, e in pairs(list) do
				if type(item) == "number" and type(e) == "table" and Number(e.t) then
					local low = Number(e.p)
					h.items[item] = P.Merge(P.Decode(h.items[item]), e.t, Whole(low), Number(e.q) or 0)
				end
			end
		end
	end
	for item, e in pairs(type(old.vendor) == "table" and old.vendor or {}) do
		if type(item) == "number" and type(e) == "table" and Number(e.p) and not saved.vendor[item] then
			saved.vendor[item] = e.p
		end
	end
	local last = 0
	for _, t in pairs(type(old.replicated) == "table" and old.replicated or {}) do
		last = math.max(last, Number(t) or 0)
	end
	saved.replicated = math.max(Number(saved.replicated) or 0, last)
	LT.db.margins = nil -- (taken over: Margins keeps nothing of its own any more)
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

P.events = CreateFrame("Frame")
P.events:SetScript("OnEvent", function(_, event, a, b, c)
	local scan = P.scan
	if event == "AUCTION_HOUSE_SHOW" then
		P.ahOpen, P.houseDue, P.autoScan = true, true, true
		P.Changed()
		P.Wake()
	elseif event == "AUCTION_HOUSE_CLOSED" then
		P.ahOpen, P.ownedAsk = false, false
		P.Changed()
		if scan then
			P.Wake() -- (the driver ends it)
		end
	elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
		P.merchantDue = true
		P.Wake()
	elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
		if scan and scan.kind == "replicate" and scan.waiting and not scan.came then
			scan.came = GetTime()
		end
	elseif event == "OWNED_AUCTIONS_UPDATED" then
		P.ownedDue = true
		P.Wake()
	elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
		P.ownedAsk = true
		P.Wake()
	elseif event == "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION" then
		local kind = Number(a)
		local sold = Enum and Enum.AuctionHouseNotification and Enum.AuctionHouseNotification.AuctionSold or 4
		local expired = Enum and Enum.AuctionHouseNotification and Enum.AuctionHouseNotification.AuctionExpired or 5
		if (kind == sold or kind == expired) and #P.notes < 50 then
			P.notes[#P.notes + 1] = { sold = kind == sold, name = Text(b), id = Number(c) }
			P.Wake()
		end
	elseif event == "AUCTION_CANCELED" then
		if Number(a) and #P.notes < 50 then
			P.notes[#P.notes + 1] = { cancel = true, id = Number(a) }
			P.Wake()
		end
	elseif scan and scan.inflight and not scan.inflight.came and SameItem(a, scan.inflight.item) then
		scan.inflight.came = GetTime() -- (COMMODITY_SEARCH_RESULTS_UPDATED, ITEM_SEARCH_RESULTS_UPDATED)
	end
end)
P.EVENTS = { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
	"REPLICATE_ITEM_LIST_UPDATE", "MERCHANT_SHOW", "MERCHANT_UPDATE", "OWNED_AUCTIONS_UPDATED", "AUCTION_HOUSE_AUCTION_CREATED",
	"AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", "AUCTION_CANCELED" }

-- Whether something wants the engine: WhyPoor? on (its Crafting tab is the crafting margins), or P.Want's.
function P.Wanted()
	local wp = W.module
	if wp and wp.enabled then
		return true
	end
	return next(P.wants) ~= nil
end

function P.Want(who, on)
	P.wants[who] = on and true or nil
	P.Refresh()
end

function P.Start()
	local saved = P.Saved()
	if not saved then
		return
	end
	P.running = true
	for _, key in ipairs({ "houses", "vendor", "posted", "deposit" }) do
		saved[key] = type(saved[key]) == "table" and saved[key] or {}
	end
	P.Import()
	local frame = _G.AuctionHouseFrame
	P.ahOpen = type(frame) == "table" and frame.IsShown and frame:IsShown() == true or false
	P.houseDue = P.ahOpen
	for _, event in ipairs(P.EVENTS) do
		pcall(P.events.RegisterEvent, P.events, event)
	end
	P.job = coroutine.create(P.PruneJob)
	P.decoded = {}
	P.Changed()
	P.Wake()
end

function P.Stop()
	P.events:UnregisterAllEvents()
	P.running = false
	P.scan, P.job, P.merchantDue, P.houseDue, P.ownedDue, P.ownedAsk, P.ahOpen = nil, nil, false, false, false, false, false
	P.notes, P.last, P.decoded, P.long = {}, nil, {}, {}
	P.driver:Hide()
	P.Changed()
end

-- Starts or stops the engine as the modules want (safe to call any time).
function P.Refresh()
	local want = P.Wanted() and P.Saved() ~= nil
	if want and not P.running then
		P.Start()
	elseif not want and P.running then
		P.Stop()
	end
end

-- Modules switching on or off (WhyPoor?, Chronicle) and the login: looked at again.
hooksecurefunc(LT, "ApplyModuleState", function()
	P.Refresh()
end)
LT.onLogin[#LT.onLogin + 1] = function()
	C_Timer.After(0, P.Refresh) -- (the modules start right after onLogin)
end
