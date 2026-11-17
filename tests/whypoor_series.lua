-- WhyPoor?: watched items' long price history (Prices.lua's scans, daily and unwatched; P.Series, P.SeriesSpan):
-- an unwatched item's daily lows as day points; watching seeds the daily history from them; a point recorded on a
-- single search and on a full scan's commit (watched items only), one within 5 minutes replacing the newest, the
-- day's open, high, low, close; both resolutions and the bounds; a 20000-item commit's extra work (one look at the
-- watch list, a record per watched item); pruning (31 days of scan points, 3000 at most, 3 years of days, a watched
-- item not on the auction house for 14 days keeps its history, an unwatched one goes 14 days after it left the
-- list, back on it in time: kept); SeriesSpan.
-- Needs: no other file.
local suite = ...
local check, section, ns, LT = suite.check, suite.section, suite.ns, suite.LT
local W = ns.WhyPoor
local P = W.Prices
local DAY = 86400
local spent = 0
local function Wait(seconds)
	Advance(seconds)
	spent = spent + seconds
end
local key = P.HomeKey()
local function H() return W.DB().prices.houses[key] end
local function Noon(day) return day * DAY + DAY / 2 end
local watchWas = W.DB().watch
W.DB().watch = {}
local function Watch(item) table.insert(W.DB().watch, item) end -- (as Stocks.lua's St.Watch: it tells no one)
local function Unwatch(item)
	for i, id in ipairs(W.DB().watch) do
		if id == item then table.remove(W.DB().watch, i) return end
	end
end
local A, B, C, E, F, G = 9701, 9702, 9703, 9704, 9705, 9706
local MINE = { A, B, C, E, F, G }
for i, item in ipairs(MINE) do ITEMS[item] = { name = "Series Item " .. i, quality = 1 } end

section("WhyPoor? prices: an item's series, unwatched")
check(P.running, "the engine runs")
local now = time()
for age = 5, 1, -1 do
	P.Store(key, A, 100 + age, 3, now - age * DAY)
	P.Store(key, C, 200 + age, 2, now - age * DAY)
end
check(H().daily[A] == nil and H().scans[A] == nil and H().daily[C] == nil, "not watched: no long history kept")
local pts, res = P.Series(C, now - 10 * DAY, now)
check(res == "day" and #pts == 5, "its daily lows as day points, got " .. tostring(res) .. " " .. #pts)
check(pts[1].t == Noon(P.Today(now - 5 * DAY)) and pts[1].price == 205 and pts[1].open == 205 and pts[1].high == 205
	and pts[1].low == 205 and pts[1].close == 205 and pts[1].qty == 2, "the oldest: its noon, open = high = low = close")
check(pts[5].t == now - DAY and pts[5].price == 201, "the day of its last scan: that scan's time")
for i = 2, #pts do assert(pts[i - 1].t < pts[i].t) end
check(#P.Series(C, now - 3 * DAY - DAY / 2, now - 2 * DAY + DAY / 2) == 2, "between from and to only")
local first, last, long = P.SeriesSpan(C)
check(first == pts[1].t and last == pts[5].t and long == false, "its span: the first and last point, not kept long")
check(select(1, P.SeriesSpan(9799)) == nil and #P.Series(9799, 0, now) == 0, "never seen: nothing")

section("WhyPoor? prices: watching seeds the long history")
Watch(A)
first, last, long = P.SeriesSpan(A)
local days = P.DecodeDaily(H().daily[A])
check(long == true and #days == 5 and days[1][4] == 101 and days[5][4] == 105, "watched: its 5 daily lows seeded, got " .. #days)
check(H().daily[A]:match("^%w+,,,%w+,,%w+,%w*;") ~= nil, "compact: open, high and close the same as low are left empty")
check(first == Noon(P.Today(now - 5 * DAY)) and last == now - DAY, "the span stays the same")
check(H().scans[A] == nil and select(2, P.Series(A, now - DAY, now)) == "day", "no scan points yet: day points")

section("WhyPoor? prices: recording a watched item's prices")
Watch(E)
local d0 = P.Today() - 20
local t1 = d0 * DAY + 10 * 3600
P.Store(key, E, 100, 5, t1)
check(#P.DecodeScans(H().scans[E]) == 1 and #P.DecodeDaily(H().daily[E]) == 1, "a price: a scan point and its day")
P.Store(key, E, 120, 6, t1 + 120)
local scans = P.DecodeScans(H().scans[E])
local day = P.DecodeDaily(H().daily[E])[1]
check(#scans == 1 and scans[1][1] == t1 + 120 and scans[1][2] == 120, "2 minutes later: replaces the newest point")
check(day[1] == d0 and day[2] == 100 and day[3] == 120 and day[4] == 100 and day[5] == 120 and day[6] == 6 and day[7] == 36120,
	"the day: open, high, low, close, the last count and when")
P.Store(key, E, 90, 4, t1 + 600)
P.Store(key, E, 50, 9, t1 - 1000)
P.Store(key, E, nil, 0, t1 + 700)
scans, day = P.DecodeScans(H().scans[E]), P.DecodeDaily(H().daily[E])[1]
check(#scans == 2 and scans[1][2] == 90 and day[4] == 90 and day[5] == 90 and day[3] == 120 and day[2] == 100,
	"10 minutes later: a point of its own; an older one and none listed: nothing")
local t5 = t1 + DAY
P.Store(key, E, 110, 3, t5)
scans, days = P.DecodeScans(H().scans[E]), P.DecodeDaily(H().daily[E])
check(#scans == 3 and #days == 2 and days[1][1] == d0 + 1 and days[1][4] == 110 and days[2][1] == d0, "the next day: a day of its own")

section("WhyPoor? prices: P.Series, scan by scan and day by day")
pts, res = P.Series(E, t1 + 120, t5)
check(res == "scan" and #pts == 3 and pts[1].t == t1 + 120 and pts[1].price == 120 and pts[2].price == 90 and pts[3].price == 110
	and pts[3].qty == 3 and pts[1].open == nil, "within the scan points: every scan, oldest first")
pts, res = P.Series(E, t1 + 121, t1 + 600)
check(res == "scan" and #pts == 1 and pts[1].t == t1 + 600, "from and to bound them")
pts, res = P.Series(E, t1, t5)
check(res == "day" and #pts == 2, "from before the oldest scan point: day points, got " .. tostring(res) .. " " .. #pts)
check(pts[1].t == d0 * DAY + 36600 and pts[1].price == 90 and pts[1].open == 100 and pts[1].high == 120 and pts[1].low == 90
	and pts[1].close == 90 and pts[1].qty == 4, "a day: its last scan's time, open, high, low, close (the long history over the daily lows)")
check(#P.Series(E, nil, nil) == 2 and select(2, P.Series(E)) == "day", "no bounds: all of it, by day")
pts = P.Series(A, now - 10 * DAY, now)
check(#pts == 5 and pts[5].t == now - DAY, "a watched item's seeded days")
first, last, long = P.SeriesSpan(E)
check(first == t1 + 120 and last == t5 and long, "its span: from its oldest scan point to its newest")

section("WhyPoor? prices: a search and a full scan record watched items")
W.DB().prices.replicated = time() -- (no whole scan on opening)
Fire("AUCTION_HOUSE_SHOW")
AH_COMMODITY[A], AH_COMMODITY[C] = true, true
AH_LISTINGS[A], AH_LISTINGS[C] = { { 90, 7 } }, { { 300, 1 } }
P.ScanItems({ A, C })
Wait(3)
scans = P.DecodeScans(H().scans[A])
check(#scans == 1 and scans[1][2] == 90 and scans[1][3] == 7 and math.abs(scans[1][1] - time()) <= 3, "a search: the watched item's point")
check(H().scans[C] == nil and H().daily[C] == nil, "an unwatched item searched: nothing long")
day = P.DecodeDaily(H().daily[A])[1]
check(day[1] == P.Today() and day[4] == 90 and #P.DecodeDaily(H().daily[A]) == 6, "and today's day after the seeded ones")
Watch(B)
AH_LISTINGS[A], AH_LISTINGS[B] = { { 85, 2 }, { 99, 1 } }, { { 40, 10 } }
W.DB().prices.replicated = time() - 1000
check(P.ScanFull(), "a full scan")
for _ = 1, 600 do
	Wait(1 / 60)
	if not P.Status().running then break end
end
check(not P.Status().running, "read and kept")
scans = P.DecodeScans(H().scans[A])
check(#scans == 1 and scans[1][2] == 85 and scans[1][3] == 3, "within 5 minutes of the search: its point replaced")
check(#P.DecodeScans(H().scans[B]) == 1 and P.DecodeDaily(H().daily[B])[1][4] == 40, "an item watched before it was ever seen: its first point")
check(H().scans[C] == nil, "unwatched ones: nothing long")
pts, res = P.Series(A, scans[1][1], time())
check(res == "scan" and #pts == 1 and pts[1].price == 85, "P.Series: the scan")
check(select(2, P.Series(A, time() - DAY, time())) == "day", "a day back is before its first scan point: by day")
Fire("AUCTION_HOUSE_CLOSED")
Wait(0.1)

section("WhyPoor? prices: a big full scan's extra work")
local found = {}
for i = 1, 20000 do found[100000 + i] = { p = 50 + i % 7, q = 1 } end
found[A], found[B] = { p = 70, q = 2 }, { p = 30, q = 4 }
for i = 1, 50 do Watch(200000 + i) end -- (a long watch list of items not in it)
local records, looks = 0, 0
local record, watchSet = P.Record, P.WatchSet
P.Record = function(...) records = records + 1; return record(...) end
P.WatchSet = function(...) looks = looks + 1; return watchSet(...) end
local co = coroutine.create(P.Commit)
local resumes = 1
local running = P.Resume(co, { key = "Testy-Alliance", t = time() }, found)
while running and resumes < 100000 do
	running, resumes = P.Resume(co), resumes + 1
end
P.Record, P.WatchSet = record, watchSet
local test = W.DB().prices.houses["Testy-Alliance"]
check(not running and test and test.items[100001] and test.items[A], "20000 items kept")
check(looks == 1 and records == 2, "the watch list looked at once, a record per watched item in it: " .. looks .. ", " .. records)
check(test.scans[A] and test.scans[B] and test.scans[100001] == nil and next(test.daily, nil) ~= nil, "only watched items' long history")
W.DB().prices.houses["Testy-Alliance"] = nil
for i = 1, 50 do Unwatch(200000 + i) end

section("WhyPoor? prices: pruning keeps watched items' history")
now = time()
local today = P.Today(now)
Watch(F)
Watch(G)
P.Store(key, F, 500, 1, now - 2 * DAY)
P.WatchSet()
Unwatch(F) -- (left while the engine was off: P.WatchSet hears of it only when pruning starts)
P.watchSet[F] = nil
check(H().daily[F] ~= nil and H().unwatched[F] == nil, "an item that left the list unheard: its history, no mark yet")
-- A's history reaches far back; it hasn't been on the auction house for 20 days.
H().scans[A] = H().scans[A] .. ";" .. P.ScanText(now - 20 * DAY, 75, 1) .. ";" .. P.ScanText(now - 40 * DAY, 70, 1)
H().daily[A] = H().daily[A] .. ";" .. P.DayText({ today - 1000, 80, 90, 60, 70, 2 }) .. ";" .. P.DayText({ today - 1200, 70, 70, 70, 70, 1 })
H().items[A] = P.Encode({ seen = now - 20 * DAY, qty = 0, days = {} })
-- G: more scan points than are kept.
local parts = {}
for i = 1, P.SCAN_MAX + 5 do parts[i] = P.ScanText(now - i * 600, 1000 + i, 1) end
H().scans[G] = table.concat(parts, ";")
Unwatch(E)
Unwatch(B)
first, last, long = P.SeriesSpan(E)
check(H().unwatched[E] and math.abs(H().unwatched[E] - now) <= 1 and long == false, "off the list: marked")
H().unwatched[E] = now - 15 * DAY
H().unwatched[B] = now - 13 * DAY
LT:SetModuleEnabled("whypoor", false)
Wait(1)
LT:SetModuleEnabled("whypoor", true)
Wait(3)
check(H().items[A] == nil, "not seen for 14 days: its daily lows go, as any item's")
scans, days = P.DecodeScans(H().scans[A]), P.DecodeDaily(H().daily[A])
check(#scans == 2 and scans[2][1] == now - 20 * DAY, "scan points older than 31 days go, got " .. #scans)
check(days[#days][1] == today - 1000 and days[#days][3] == 90 and #days == 7, "days older than 3 years go, got " .. #days)
pts, res = P.Series(A, now - 30 * DAY, now)
check(res == "day" and #pts == 6, "watched but off the auction house: still its long history, got " .. #pts)
pts, res = P.Series(A, now - 20 * DAY)
check(res == "scan" and #pts == 2, "and its scans")
first, last, long = P.SeriesSpan(A)
check(first == Noon(today - 1000) and long, "its span reaches back 1000 days")
check(#P.DecodeScans(H().scans[G]) == P.SCAN_MAX and P.DecodeScans(H().scans[G])[1][2] == 1001, "3000 scan points at most, the newest")
check(H().daily[E] == nil and H().scans[E] == nil and H().unwatched[E] == nil, "off the list for 15 days: its long history gone")
check(H().daily[B] ~= nil and H().unwatched[B] == now - 13 * DAY, "13 days: still kept")
check(H().daily[F] ~= nil and math.abs((H().unwatched[F] or 0) - now) <= 5, "left unheard: marked when pruning starts")
Watch(B)
first, last, long = P.SeriesSpan(B)
check(long and H().unwatched[B] == nil and H().daily[B] ~= nil and H().scans[B] ~= nil, "back on the list in time: its history kept, the mark gone")

section("WhyPoor? prices: sold a day (estimated), kept long for watched items")
do
	local today = P.Today(time())
	local s = P.AddSold(nil, today - 1, 4, 3600)
	s = P.AddSold(s, today - 1, 2, 1800)
	check(s == P.B36(today - 1) .. "," .. P.B36(6) .. "," .. P.B36(5400), "a day's gone and watched time add up: " .. s)
	s = P.AddSold(s, today, 10, 7200)
	check(s:match("^(%w+),") == P.B36(today) and select(2, s:gsub(";", "")) == 1, "a new day goes first")
	check(P.AddSold(s, today - 3, 1, 100) == s, "an older day than the newest: left out")
	-- Two whole scans an hour apart: listings gone before they could expire (the flow), for every item; a watched
	-- one's kept long too.
	local band = 99
	P.bands = P.bands or {}
	local bandWas = P.bands[band]
	P.bands[band] = 48 * 3600
	Unwatch(G)
	Watch(G)
	P.WatchSet()
	H().flow[G], H().sold[G], H().flow[E], H().sold[E] = nil, nil, nil, nil
	local t = time()
	local last = { t = t - 3600, cnt = { [G] = { ["5/100/"] = 3 }, [E] = { ["5/100/"] = 3 } }, bnd = { [G] = { ["5/100/"] = band }, [E] = { ["5/100/"] = band } } }
	local sigs = { cnt = { [G] = { ["5/100/"] = 1 }, [E] = { ["5/100/"] = 1 } } }
	P.CompareScans(H(), last, sigs, t)
	check(H().flow[G] ~= nil and H().sold[G] == H().flow[G] and H().flow[E] ~= nil and H().sold[E] == nil,
		"10 gone in an hour: the flow for both, kept long only for the watched one")
	local list, perDay, gone, span = P.SoldSeries(G, t - DAY, t)
	check(#list == 1 and list[1].gone == 10 and list[1].span == 3600 and list[1].perDay == 240 and perDay == nil and gone == 10,
		"its day: 10 in an hour watched, ~240 a day; over the range too little watched for an estimate (under 2 hours)")
	-- An older day only in sold (flow forgets after 14 days): still there; a day watched under an hour: left out.
	H().sold[G] = H().sold[G] .. ";" .. P.B36(today - 40) .. "," .. P.B36(30) .. "," .. P.B36(3 * 3600) .. ";"
		.. P.B36(today - 41) .. "," .. P.B36(5) .. "," .. P.B36(600)
	list, perDay = P.SoldSeries(G, (today - 45) * DAY, t)
	check(#list == 2 and list[1].day == today - 40 and list[1].perDay == 240 and perDay and math.abs(perDay - 40 * DAY / (4 * 3600)) < 1e-6,
		"40 days back from the long store; under an hour watched left out; over the range: 40 in 4 hours, ~240 a day")
	check(#P.SoldSeries(G, (today - 2) * DAY, t) == 1, "between from and to only")
	-- Watching an item seeds its sold from its flow.
	H().flow[F], H().sold[F] = P.AddSold(nil, today - 2, 7, 7200), nil
	Watch(F)
	P.WatchSet()
	check(H().sold[F] == H().flow[F], "watched: its sold seeded from its flow")
	-- Pruning: days older than 3 years go; an unwatched item's sold goes with the rest of its history.
	H().sold[G] = H().sold[G] .. ";" .. P.B36(today - P.LONG_DAYS - 5) .. ",1,e10"
	Unwatch(F)
	P.WatchSet()
	H().unwatched[F] = time() - 15 * DAY
	P.PruneLong(H(), G, P.WatchSet(), time())
	P.PruneLong(H(), F, P.WatchSet(), time())
	check(select(2, H().sold[G]:gsub(";", "")) == 2 and H().sold[F] == nil, "pruned: older than 3 years, and an item off the list 15 days")
	P.bands[band] = bandWas
end

-- (put back what this file changed)
W.DB().watch = watchWas
P.WatchSet()
for _, item in ipairs(MINE) do
	ITEMS[item] = nil
	for _, list in ipairs({ "items", "scans", "daily", "sold", "flow", "unwatched" }) do H()[list][item] = nil end
end
AH_LISTINGS, AH_COMMODITY = {}, {}
Advance(math.ceil(spent - 1e-6) - spent) -- (a whole number of seconds in all)
