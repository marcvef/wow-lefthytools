-- WhyPoor?: friends' scans of watched items (Share.lua's ww / wf, Prices.lua's P.RecordFriend, Chart.lua's point
-- tooltip, dots and info line): my watch list to friends (first seen, again when it changes, at most every minute,
-- their ask answered); my points after a full scan and after searches, only of the items they watch, a 20-item
-- list in two messages within 250 bytes; theirs recorded marked as theirs; the merging rules with mine (scan
-- points: never over mine, filling the gaps, their own told twice; days: high, low, the newest scan's close and
-- count; sold: the longer watch, never added up); old saved texts still load and pruning keeps the marks; the
-- version gate; broken, oversized and unwatched entries; the rate limit; nothing in a fight.
-- Needs: no other file.
local suite = ...
local check, section, ns, LT = suite.check, suite.section, suite.ns, suite.LT
local sentTo, anna = suite.sentTo, suite.anna
local W = ns.WhyPoor
local P, S = W.Prices, W.Share
local DAY = 86400
local spent = 0
local function Wait(seconds) -- (Anna and Bob say they're there now and then: Beacon forgets a friend after 65 s of silence)
	while seconds > 0 do
		local step = math.min(seconds, 20)
		if step >= 1 then
			Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;250.0;750.0;Goldshire;", "WHISPER", 11)
			Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;250.0;750.0;Goldshire;", "WHISPER", 12)
		end
		Advance(step)
		spent, seconds = spent + step, seconds - step
	end
end
local function bob(text) Fire("BN_CHAT_MSG_ADDON", "LTBeacon", text, "WHISPER", 12) end
local function Lines() return table.concat(TOOLTIP.lines or {}, "\n") end
local function Plain(text) return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local key = P.HomeKey()
local house = LT.Hash32(key)
local function H() return P.House(key) end
local B36 = P.B36
local watchWas = W.DB().watch
local X, Y, Z, U, M, N, C, K = 9801, 9802, 9803, 9804, 9805, 9806, 9807, 9808
for _, item in ipairs({ X, Y, Z, U, M, N, C, K }) do ITEMS[item] = { name = "Point Item " .. item, quality = 1 } end
local WPdb = LT:GetModule("whypoor").db
WPdb.sharePrices = true
W.DB().watch = { X, Y }

section("WhyPoor? friends' scans: my watch list to friends")
check(P.running, "the engine runs")
S.friends[11], S.friends[12] = nil, nil -- (as if first seen)
local mark = #GAMEDATA + 1
local start = mark
anna("H2")
anna("V2;0.7.0-500-gabcdef0")
bob("H2")
bob("V2;0.7.0-200-gabcdef0") -- (a build that reads prices, not the points)
Wait(11)
local ww = sentTo(11, mark, "B2;ww;")
check(#ww == 1 and ww[1] == "B2;ww;" .. house .. ";1;" .. B36(X) .. "," .. B36(Y),
	"a friend first seen: my watched items, asking for theirs, got " .. tostring(ww[1]))
check(#sentTo(12, mark, "B2;ww;") == 0 and S.Reads(ns.Beacon.peers[12]) and not S.ReadsPoints(ns.Beacon.peers[12]),
	"a build from before the points: none")
W.DB().watch = { X, Y, U }
mark = #GAMEDATA + 1
Wait(11)
check(#sentTo(11, mark, "B2;ww;") == 0, "changed within a minute: not yet")
Wait(60)
ww = sentTo(11, mark, "B2;ww;")
check(#ww == 1 and ww[1] == "B2;ww;" .. house .. ";1;" .. B36(X) .. "," .. B36(Y) .. "," .. B36(U), "a minute on: the new list")
Wait(11)
check(#sentTo(11, mark, "B2;ww;") == 1, "unchanged: not again")

section("WhyPoor? friends' scans: a friend's list, my points after my scans")
Wait(30) -- (well after mine went: their ask is answered)
mark = #GAMEDATA + 1
anna("B2;ww;" .. house .. ";1;" .. B36(X) .. "," .. B36(Z))
Wait(1)
local f = S.friends[11]
check(f.watch and f.watch[X] and f.watch[Z] and not f.watch[Y] and f.heard, "their list kept")
anna("B2;ww;" .. house .. ";;" .. B36(Y))
anna("B2;ww;0badf00d;;" .. B36(U))
Wait(1)
check(f.watch[X] and not f.watch[Y] and not f.watch[U], "another list within 20 seconds, another auction house's: not taken")
check(#sentTo(11, mark, "B2;wf;") == 0, "nothing of theirs known yet: no points")
Wait(70)
ww = sentTo(11, mark, "B2;ww;")
check(#ww == 1 and ww[1] == "B2;ww;" .. house .. ";;" .. B36(X) .. "," .. B36(Y) .. "," .. B36(U),
	"they asked: mine again, no longer asking, got " .. tostring(ww[1]))
W.DB().prices.replicated = time() -- (no whole scan on opening)
Fire("AUCTION_HOUSE_SHOW")
AH_LISTINGS[X], AH_LISTINGS[Y], AH_LISTINGS[Z], AH_LISTINGS[U] = { { 100, 5 } }, { { 300, 2 } }, { { 200, 3 } }, { { 50, 1 } }
W.DB().prices.replicated = time() - 1000
mark = #GAMEDATA + 1
check(P.ScanFull(), "my full scan")
for _ = 1, 600 do
	Wait(1 / 60)
	if not P.Status().running then break end
end
Wait(2)
local wf = sentTo(11, mark, "B2;wf;")
local age, entries = (wf[1] or ""):match("^B2;wf;" .. house .. ";(%d+);(.*)$")
local want = { [B36(X) .. ":" .. B36(100) .. ":" .. B36(5) .. ":::"] = true, [B36(Z) .. ":" .. B36(200) .. ":" .. B36(3) .. ":::"] = true }
local good, bad = 0, 0
for e in (entries or ""):gmatch("[^,]+") do
	if want[e] then good = good + 1 else bad = bad + 1 end
end
check(#wf == 1 and good == 2 and bad == 0 and tonumber(age) <= 3,
	"after my full scan: the items they watch, the price for one and how many (no flow yet), as old as the scan: " .. tostring(wf[1]))
AH_COMMODITY[X], AH_LISTINGS[X] = true, { { 95, 4 } }
Wait(61)
mark = #GAMEDATA + 1
P.ScanItems({ X, Y })
Wait(6)
wf = sentTo(11, mark, "B2;wf;")
check(#wf == 1 and wf[1]:match("^B2;wf;%x+;%d+;([^,]*)$") == B36(X) .. ":" .. B36(95) .. ":" .. B36(4) .. ":::",
	"searched: only the item they watch, once the searching is done: " .. tostring(wf[1]))
Fire("AUCTION_HOUSE_CLOSED")
Wait(0.1)

section("WhyPoor? friends' scans: theirs, marked as theirs")
local before = #P.DecodeScans(H().scans[X])
anna("B2;wf;" .. house .. ";3600;" .. B36(Y) .. ":" .. B36(310) .. ":" .. B36(4) .. ":" .. B36(7) .. ":" .. B36(7200) .. ":,"
	.. B36(Z) .. ":" .. B36(1) .. ":1:::")
anna("B2;wf;" .. house .. ";0;" .. B36(X) .. ":" .. B36(90) .. ":" .. B36(6) .. ":::")
Wait(1)
local now = time()
local scans = P.DecodeScans(H().scans[Y])
local theirs = scans[#scans]
check(#scans == 2 and theirs[4] and P.WhoName(H(), theirs[4]) == "Anna Brook" and math.abs(theirs[1] - (now - 3601)) <= 2
	and theirs[2] == 310 and theirs[3] == 4 and scans[1][4] == nil, "an hour-old scan of theirs: a point of its own, marked as Anna's")
check(#P.DecodeScans(H().scans[X]) == before, "theirs within 15 minutes of mine: left out")
check(H().scans[Z] == nil and H().daily[Z] == nil, "an item I don't watch: not taken")
local pts, res = P.Series(Y, theirs[1], now)
check(res == "scan" and #pts == 2 and pts[1].from == "Anna Brook" and pts[2].from == nil, "P.Series: their point says whose")
local sold = P.SoldSeries(Y, now - 2 * DAY, now)
local soldDay = sold[#sold]
check(soldDay and soldDay.friend and soldDay.gone == 7 and soldDay.span == 7200 and math.abs(soldDay.perDay - 84) < 0.01,
	"their flow that day: the sold estimate where I watched none")

section("WhyPoor? friends' scans: never over mine, filling the gaps")
W.DB().watch = { X, Y, U, M, N, C, K }
local h = H()
local ann, bo = P.Who(h, "Anna Brook"), P.Who(h, "Bob Stone")
check(ann and bo and ann ~= bo and P.Who(h, "Anna Brook") == ann and P.WhoName(h, bo) == "Bob Stone", "friends' names: each once")
local d0 = P.Today() - 3
local t0 = d0 * DAY + 8 * 3600
P.Record(h, M, t0, 100, 5)
check(not P.RecordFriend(h, M, t0, 90, 4, ann), "a friend's scan at the same time as mine: never over it")
check(not P.RecordFriend(h, M, t0 + 600, 90, 4, ann), "within 15 minutes of mine: left out")
check(P.RecordFriend(h, M, t0 + 1800, 90, 4, ann), "half an hour later: theirs fills the gap")
check(P.RecordFriend(h, M, t0 + 1810, 91, 4, ann), "their own again (the same scan told twice): replaces theirs")
check(not P.RecordFriend(h, M, t0 + 1900, 92, 4, bo), "another friend's near it: left out")
scans = P.DecodeScans(h.scans[M])
check(#scans == 2 and scans[1][1] == t0 + 1810 and scans[1][2] == 91 and scans[1][4] == ann and scans[2][4] == nil,
	"two points: theirs marked, mine not")
check(h.scans[M]:match("^%w+,%w+,%w+,%w+;%w+,%w+,%w+$") ~= nil, "compact: a friend's point has one field more, mine none")
check(P.Record(h, M, t0 + 1820, 95, 3), "mine within 5 minutes after theirs")
scans = P.DecodeScans(h.scans[M])
check(#scans == 2 and scans[1][1] == t0 + 1820 and scans[1][4] == nil, "replaces theirs: mine win")
P.Record(h, M, t0 + 7200, 120, 2)
check(P.RecordFriend(h, M, t0 + 4500, 80, 7, ann), "theirs older than my newest, far from both: taken")
scans = P.DecodeScans(h.scans[M])
check(#scans == 4 and scans[1][1] == t0 + 7200 and scans[2][1] == t0 + 4500 and scans[2][4] == ann and scans[3][1] == t0 + 1820,
	"in its place by time")
check(not P.Record(h, M, t0 + 4000, 70, 1) and #P.DecodeScans(h.scans[M]) == 4, "mine older than my newest: left out, as before")
local day = P.DecodeDaily(h.daily[M])[1]
check(day[1] == d0 and day[2] == 100 and day[3] == 120 and day[4] == 80 and day[5] == 120 and day[6] == 2 and day[7] == 8 * 3600 + 7200
	and day[8] == nil, "the day: mine and theirs merged (high, low over both; the close and count the newest scan's, mine)")
local t1 = d0 * DAY + 10 * 3600
P.Record(h, N, t1, 100, 5)
P.RecordFriend(h, N, t1 + 7200, 80, 9, ann)
day = P.DecodeDaily(h.daily[N])[1]
check(day[3] == 100 and day[4] == 80 and day[5] == 80 and day[6] == 9 and day[7] == 12 * 3600 and day[8] == ann,
	"their newer scan: the day's close and count, marked as theirs")
P.RecordFriend(h, N, t1 - 7200, 150, 2, ann)
day = P.DecodeDaily(h.daily[N])[1]
check(day[2] == 100 and day[3] == 150 and day[5] == 80 and day[6] == 9, "their older one: the high, not the close; the open stays")
P.Record(h, N, t1 + 3 * 3600, 110, 4)
day = P.DecodeDaily(h.daily[N])[1]
check(day[5] == 110 and day[6] == 4 and day[8] == nil, "mine newer again: the close mine")
P.RecordFriend(h, N, (d0 - 1) * DAY + 20 * 3600, 60, 1, ann)
local days = P.DecodeDaily(h.daily[N])
check(#days == 2 and days[1][1] == d0 and days[2][1] == d0 - 1 and days[2][8] == ann, "a day before mine: in its place")
pts, res = P.Series(N, (d0 - 2) * DAY, (d0 + 1) * DAY)
check(res == "day" and #pts == 2 and pts[1].from == "Anna Brook" and pts[2].from == nil, "P.Series by day: a day whose last scan was theirs says so")
pts, res = P.Series(N, (d0 - 1) * DAY + 20 * 3600, (d0 + 1) * DAY)
check(res == "scan" and pts[1].from == "Anna Brook" and pts[#pts].from == nil, "and by scan")
h.sold[N] = P.AddSold(nil, d0, 5, 3600)
P.RecordFriend(h, N, t1, nil, 0, ann, 20, 7200)
sold = P.SoldSeries(N, d0 * DAY, d0 * DAY + DAY - 1)
check(#sold == 1 and sold[1].gone == 20 and sold[1].span == 7200 and sold[1].friend, "a day they watched longer than I did: their numbers, not added to mine")
P.RecordFriend(h, N, t1, nil, 0, bo, 30, 5000)
sold = P.SoldSeries(N, d0 * DAY, d0 * DAY + DAY - 1)
check(sold[1].gone == 20 and sold[1].span == 7200, "a friend who watched less: not taken (never added up)")
P.RecordFriend(h, N, t1, nil, 0, ann, 25, 9000)
sold = P.SoldSeries(N, d0 * DAY, d0 * DAY + DAY - 1)
check(sold[1].gone == 25 and sold[1].span == 9000, "their day told again later, watched longer: replaces it")
h.sold[N] = P.AddSold(h.sold[N], d0, 50, 20000)
sold = P.SoldSeries(N, d0 * DAY, d0 * DAY + DAY - 1)
check(sold[1].gone == 55 and sold[1].span == 23600 and not sold[1].friend, "mine watched longer: mine")

section("WhyPoor? friends' scans: older saved texts")
local tOld = (d0 - 5) * DAY + 3600
local oldScans = B36(tOld + 7200) .. "," .. B36(70) .. ",3;" .. B36(tOld) .. "," .. B36(75) .. ",2"
h.scans[C] = oldScans
h.daily[C] = B36(d0 - 5) .. ",," .. B36(75) .. "," .. B36(70) .. ",," .. B36(3) .. "," .. B36(3600 + 7200)
local list = P.DecodeScans(h.scans[C])
check(#list == 2 and list[1][2] == 70 and list[1][4] == nil and list[2][4] == nil, "an old scans text: loads, all mine")
local dd = P.DecodeDaily(h.daily[C])
check(#dd == 1 and dd[1][3] == 75 and dd[1][4] == 70 and dd[1][7] == 10800 and dd[1][8] == nil, "an old daily text: loads, mine")
check(P.RecordFriend(h, C, tOld + 4 * 3600, 60, 1, ann), "a friend's point onto it")
check(h.scans[C]:sub(-#oldScans) == oldScans and #P.DecodeScans(h.scans[C]) == 3, "the old points untouched")
dd = P.DecodeDaily(h.daily[C])
check(dd[1][4] == 60 and dd[1][5] == 60 and dd[1][8] == ann and h.daily[C]:match("," .. B36(ann) .. "$"), "the day: theirs now its close, marked")
h.scans[M] = h.scans[M] .. ";" .. P.ScanText(time() - 40 * DAY, 1, 1) -- (pruned: the texts written anew)
h.friendSold[N] = h.friendSold[N] .. ";" .. B36(P.Today() - 2000) .. ",1,1"
LT:SetModuleEnabled("whypoor", false)
Wait(1)
LT:SetModuleEnabled("whypoor", true)
Wait(2)
h = H()
scans = P.DecodeScans(h.scans[M])
check(#scans == 4 and scans[2][4] == ann and scans[1][4] == nil, "pruning keeps whose points they are")
check(not h.friendSold[N]:find(";", 1, true), "friends' flow older than 3 years: gone")
W.DB().watch = { X, Y, U, C, K }
LT:SetModuleEnabled("whypoor", false)
Wait(1)
LT:SetModuleEnabled("whypoor", true)
Wait(2)
check(H().unwatched[N] ~= nil and H().friendSold[N] ~= nil, "an item off the list: friends' flow kept with the rest for 14 days")
W.DB().watch = { X, Y, U, M, N, C, K }

section("WhyPoor? friends' scans: broken, too many, too often")
Wait(25)
anna("B2;ww;" .. house .. ";;" .. B36(X) .. "," .. B36(Z)) -- (WhyPoor? was off a moment: their list again, as their client does when asked)
Wait(1)
S.friends[11].takes, S.friends[11].takesAt = nil, nil
local yBefore = H().scans[Y]
local ok = B36(Y) .. ":" .. B36(333) .. ":1:::"
anna("B2;wf;0badf00d;7200;" .. ok)
anna("B2;wf;" .. house .. ";7200;" .. ok .. ",zzzzzzzzzz:1:1:::")
anna("B2;wf;" .. house .. ";7200;" .. ok .. "," .. B36(X) .. ":1:1:5::")
anna("B2;wf;" .. house .. ";99999;" .. ok)
anna("B2;wf;" .. house .. ";7200;" .. ok .. "," .. B36(X) .. ":1:1:::" .. B36(30000))
local many = {}
for i = 1, 21 do many[i] = B36(Y) .. ":1:1:::" end
check(#("B2;wf;" .. house .. ";7200;" .. table.concat(many, ",")) <= 255, "(21 entries within Beacon's 255 bytes)")
anna("B2;wf;" .. house .. ";7200;" .. table.concat(many, ","))
anna("B2;wf;" .. house .. ";7200;" .. ok .. string.rep("," .. ok, 30))
Wait(1)
check(H().scans[Y] == yBefore,
	"another auction house, a broken entry, half a flow, too old, an entry too old, more than 20 entries, over 255 bytes: all dropped whole")
for i = 1, 16 do
	anna("B2;wf;" .. house .. ";7200;" .. B36(Z) .. ":1:1:::")
	if i % 8 == 0 then Wait(1) end -- (Beacon's own flood guard: 20 a second from one friend)
end
anna("B2;wf;" .. house .. ";7200;" .. ok)
Wait(3)
check(H().scans[Y] == yBefore and S.friends[11].takes == S.POINTS_LIMIT, "more than 20 in 10 minutes from one friend: dropped")
Wait(600)
anna("B2;wf;" .. house .. ";7200;" .. ok)
Wait(1)
scans = P.DecodeScans(H().scans[Y])
local found = false
for _, s in ipairs(scans) do found = found or (s[2] == 333 and s[4] == ann) end
check(found, "10 minutes on: taken again")

section("WhyPoor? friends' scans: nothing in a fight")
EnterCombat()
mark = #GAMEDATA + 1
S.friends[11].pointsAt = nil
S.Scanned(key)
yBefore = H().scans[Y]
anna("B2;wf;" .. house .. ";14400;" .. B36(Y) .. ":" .. B36(444) .. ":2:::")
Wait(5)
check(#sentTo(11, mark, "B2;wf;") == 0 and H().scans[Y] == yBefore, "in a fight: nothing sent, nothing taken")
LeaveCombat()
Wait(3)
check(#sentTo(11, mark, "B2;wf;") >= 1, "after it: my points go")
check(H().scans[Y] ~= yBefore, "and theirs are taken: " .. tostring(H().scans[Y]))

section("WhyPoor? friends' scans: a 20-item list in two messages")
local list20 = {}
local today = P.Today()
for i = 1, 20 do
	local item = 21000 + i * 37
	list20[i] = B36(item)
	P.Store(key, item, 120000 + i * 1111, 150 + i)
	H().flow[item] = P.AddDays(nil, today, 40 + i, 50000 + i)
end
Wait(25)
mark = #GAMEDATA + 1
S.friends[11].pointsAt = nil
anna("B2;ww;" .. house .. ";;" .. table.concat(list20, ","))
Wait(3)
wf = sentTo(11, mark, "B2;wf;")
local n, longest, sample = 0, 0, nil
for _, m in ipairs(wf) do
	longest = math.max(longest, #m)
	for e in m:match("^B2;wf;%x+;%d+;(.*)$"):gmatch("[^,]+") do
		n = n + 1
		sample = sample or e
	end
end
check(#wf == 2 and n == 20 and longest <= 250, ("20 items with flow: %d messages, %d entries, the longest %d bytes (%d and %d)"):format(#wf, n,
	longest, wf[1] and #wf[1] or 0, wf[2] and #wf[2] or 0))
check(sample and sample:match("^%w+:%w+:%w+:%w+:%w+:$"), "an entry with flow: " .. tostring(sample))

check(#sentTo(12, start, "B2;ww;") == 0 and #sentTo(12, start, "B2;wf;") == 0, "the older build: nothing of it all along")

section("WhyPoor? friends' scans: the setting")
WPdb.sharePrices = false
Wait(2)
mark = #GAMEDATA + 1
yBefore = H().scans[Y]
S.Scanned(key)
anna("B2;wf;" .. house .. ";18000;" .. B36(Y) .. ":" .. B36(555) .. ":2:::")
W.DB().watch = { X, Y, U, M, N, C, K, Z }
Wait(70)
check(#sentTo(11, mark, "B2;ww;") == 0 and #sentTo(11, mark, "B2;wf;") == 0 and H().scans[Y] == yBefore and S.friends[11].watch == nil,
	"off: nothing sent, nothing taken, their list forgotten")
WPdb.sharePrices = true
Wait(12)
ww = sentTo(11, mark, "B2;ww;")
check(#ww == 1 and ww[1]:match("^B2;ww;%x+;1;") ~= nil, "on again: my list, asking for theirs")

section("WhyPoor? friends' scans: the chart")
local Ch = W.Chart
now = time()
h = H()
P.Record(h, K, now - 30 * 3600, 120, 3)
P.Record(h, K, now - 3 * 3600, 100, 5)
P.RecordFriend(h, K, now - 2 * 3600, 90, 7, ann)
h.daily[K] = h.daily[K] .. ";" .. P.DayText({ P.Today(now) - 40, 130, 130, 130, 130, 2 }) -- (days known from before its scans)
check(Ch.Open(K) == true, "the big chart")
local frame, state, w = Ch.View()
state.range, state.zoom = "1D", nil
Ch.Draw()
local fi
for i, p in ipairs(w.points) do
	if p.from then fi = i end
end
check(w.res == "scan" and #w.points == 2 and fi, "1D: my scan and theirs")
w:HoverAt(w:X(w.points[fi].t))
check(TOOLTIP.shown and Lines():find("from Anna Brook", 1, true), "their point's tooltip: from whom")
local friendDot, dots = false, 0
for k = 1, w.pools.dot and w.pools.dot.n or 0 do
	local d = w.pools.dot.list[k]
	dots = dots + 1
	friendDot = friendDot or (d.color and d.color[1] == Ch.FRIEND[1] and d.color[3] == Ch.FRIEND[3])
end
check(dots == 2 and friendDot, "their dot: its own colour")
w:Unhover()
check(Plain(frame.Info:GetText()):find("friends' scans: 1", 1, true), "the info line counts them: " .. Plain(frame.Info:GetText()))
state.range = "Max"
Ch.Draw()
fi = nil
for i, p in ipairs(w.points) do
	if p.from then fi = i end
end
check(w.res == "day" and fi, "by day: the day their scan was the last")
w:HoverAt(w:X(w.points[fi].t))
check(Lines():find("last scan that day from Anna Brook", 1, true), "its tooltip says so")
w:Unhover()
frame:Hide()

-- (put back what this file changed)
W.DB().watch = watchWas
for _, item in ipairs({ X, Y, Z, U, M, N, C, K }) do ITEMS[item] = nil end
AH_LISTINGS, AH_COMMODITY = {}, {}
Advance(math.ceil(spent - 1e-6) - spent) -- (a whole number of seconds in all)
