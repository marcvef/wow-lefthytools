local _, ns = ...
local LT = ns.LT
local B = ns.Beacon
local W = ns.WhyPoor or {}
ns.WhyPoor = W

-- Friends' auction house prices over Beacon, and ours to them (W.Share). docs/whypoor.md ("Friends' prices")
-- and docs/beacon.md (the words). Beacon's B family, WhyPoor?'s letter w, only to friends whose build is from
-- PRICES_SINCE on (their V2; before it's known, nothing; older builds ignore an unknown B word anyway), and only
-- while WhyPoor? is on with its sharePrices setting and Beacon is on (both sides). Only friends on the same
-- realm and faction get prices: an offer names the auction house by a hash, and only a friend whose house it is
-- asks for them.
--
--   B2;wo;<house>;<age>        my last full scan of this auction house was age seconds ago (house: LT.Hash32 of
--                              "<realm>-<faction>"; ages, not times, since two computers' clocks differ)
--   B2;wq;<house>              send me yours (my newest data is older than yours)
--   B2;wp;<house>;<age>;<entries>  prices, as old as age at most: <item>:<value>:<low>:<qty>:<days>:<unstable>,...
--                              (base 36; value or low empty: none; unstable 1 or empty)
--   B2;we;<house>;<count>      that's all (count entries)
--
-- Friends' scan points of watched items (only to builds from POINTS_SINCE on; the same setting, the same house):
--
--   B2;ww;<house>;<ask>;<item>,...   the items I watch (base 36; the first WATCH_MAX of my list that fit; none:
--                              empty). ask 1: I have none of yours yet, send me yours. To a friend first seen and
--                              again when my list changes, at most every WATCH_GAP per friend.
--   B2;wf;<house>;<age>;<item>:<low>:<qty>:<gone>:<span>:<older>,...   my own data of items they watch, from my
--                              scans (base 36): the lowest for one (empty: none listed) and how many were listed
--                              at my scan as old as age (+ older seconds; empty: 0), and my flow of that day so far
--                              (gone, span; both empty: none). After each full scan of mine and after my searches of
--                              them (once the searching is done, FRESH_WAIT at most), my latest when their list
--                              comes; at most every POINTS_GAP per friend, data POINT_AGE old at most.
--
-- Theirs are recorded into my watched items' long history marked as theirs (Prices.lua's P.RecordFriend: never
-- over a point of mine, days merged, their flow a day only where they watched longer). Every wf is checked whole
-- (a broken one is dropped), only items I watch are taken, at most POINTS_ITEMS a message and POINTS_LIMIT
-- messages in POINTS_WINDOW from one friend. Only my own data goes out, never a friend's passed on.
--
-- Offers go at low priority after my full scan and to a friend first seen, at most every OFFER_GAP per friend.
-- One friend is asked at a time, a friend at most every ASK_GAP, and only when their scan is NEWER than my
-- newest data. A request is answered at most every ANSWER_GAP per friend, one friend at a time, a few messages
-- a second while Beacon's queues are nearly empty, SERVE_MAX items at most. Only my own prices go out (never a
-- friend's passed on). Theirs are kept marked with their name and when they came, and only where they're newer
-- than mine. Nothing of it in a fight: it waits. Events only note; Beacon's tick (B.TickPrices) does the rest.

local S = {}
W.Share = S

local PRICES_SINCE = "0.7.0-190-g0000000" -- the first build that reads these (LT.CompareVersions)
local POINTS_SINCE = "0.7.0-217-g0000000" -- the first build that reads ww / wf

local VERSION = B.VERSION
local OFFER_GAP = 600       -- an offer to one friend at most this often
local ASK_GAP = 1800        -- one friend asked at most this often
local NEWER = 600           -- a friend's scan this much newer than my newest data: asked
local ANSWER_GAP = 1800     -- one friend's request answered at most this often
local PENDING_TIMEOUT = 120 -- a request given up after this long without a message
local SERVE_MAX = 2000      -- items an answer holds at most (the newest first)
local SEND_STEP = 4         -- messages queued a second at most
local SEND_WAITING = 8      -- ... and only while fewer than this wait in Beacon's queues
local INCOMING_MAX = 300    -- friends' messages waiting for the tick
local HANDLE_STEP = 25      -- friends' messages handled a tick at most
local SLOW_TICK = 1         -- seconds between the slow steps (offers, asking, serving)
local MESSAGE_BYTES = 250
local MONEY_MAX = 1e11      -- copper; more is a broken message
local QTY_MAX = 1e7
local HANDLE_MS = 2         -- friends' messages handled this long a tick at most
local WATCH_MAX = 40        -- items my watch list (ww) holds at most
local WATCH_GAP = 60        -- my watch list to one friend at most this often
local WATCH_TAKE_GAP = 20   -- a friend's watch list taken at most this often
local CROSSED = 30          -- their ask came this soon after mine went: crossed, not answered
local POINTS_GAP = 60       -- my fresh points to one friend at most this often
local POINT_AGE = 6 * 3600  -- points older than this aren't sent or taken
local FRESH_WAIT = 20       -- while searches run, fresh points wait at most this long
local POINTS_ITEMS = 20     -- entries a wf holds at most (more: broken)
local POINTS_LIMIT, POINTS_WINDOW = 20, 600 -- wf taken from one friend at most (more: dropped)
local SPAN_MAX = 3 * 86400  -- a day's flow span; more is a broken message

S.PRICES_SINCE, S.SERVE_MAX, S.OFFER_GAP, S.ASK_GAP, S.ANSWER_GAP = PRICES_SINCE, SERVE_MAX, OFFER_GAP, ASK_GAP, ANSWER_GAP
S.POINTS_SINCE, S.WATCH_GAP, S.POINTS_GAP, S.POINT_AGE, S.POINTS_LIMIT, S.POINTS_WINDOW, S.POINTS_ITEMS =
	POINTS_SINCE, WATCH_GAP, POINTS_GAP, POINT_AGE, POINTS_LIMIT, POINTS_WINDOW, POINTS_ITEMS

S.friends = {}      -- gameAccountID -> { due, offeredAt, askedAt, answeredAt, theirs (the seen of their offer);
                    -- points: watch (their items, a set), watchList, sentWatch (my list's text they got), watchAt,
                    -- watchTakenAt, heard (their list came), fresh (items with new data for them), freshAll (a full
                    -- scan), freshSince, pointsAt, takes and takesAt (their wf counted) }
S.incoming, S.inHead, S.inTail = {}, 1, 0
S.serves = {}       -- { gameAccountID, ... }: requests to answer, in order
S.lastSlow = -math.huge

local WORDS = { wo = true, wq = true, wp = true, we = true, ww = true, wf = true }

local function P()
	return W.Prices
end

local function Clock()
	local ok, ms = pcall(debugprofilestop)
	return ok and type(ms) == "number" and ms or nil
end

---------------------------------------------------------------------------
-- Who takes part
---------------------------------------------------------------------------

function S.Sharing()
	local m, prices = W.module, P()
	return m ~= nil and m.enabled and type(m.db) == "table" and m.db.sharePrices == true and B.module.enabled
		and prices ~= nil and prices.running == true
end

-- Does their build read these? A build that doesn't say, or one without its commit count, counts as older.
function S.Reads(peer)
	if not (peer and peer.version) then
		return false
	end
	if peer.pricesBuild ~= peer.version then
		peer.pricesBuild = peer.version
		peer.readsPrices = (LT.CompareVersions(peer.version, PRICES_SINCE) or -1) >= 0
	end
	return peer.readsPrices
end

-- Does their build read the watched items' points (ww, wf)?
function S.ReadsPoints(peer)
	if not (peer and peer.version) then
		return false
	end
	if peer.pointsBuild ~= peer.version then
		peer.pointsBuild = peer.version
		peer.readsPoints = (LT.CompareVersions(peer.version, POINTS_SINCE) or -1) >= 0
	end
	return peer.readsPoints
end

-- My auction house's name on the wire (this realm and faction), and its saved table.
function S.MyHouse()
	local key = P().HomeKey()
	if key then
		return LT.Hash32(key), P().House(key)
	end
end

function S.Msg(word, ...)
	return ("B%s;%s;%s"):format(VERSION, word, table.concat({ ... }, ";"))
end

function S.Friend(id)
	local f = S.friends[id]
	if not f then
		f = { due = true, fresh = {} }
		S.friends[id] = f
	end
	return f
end

-- The newest data I have of my house: my last full scan, or the newest a friend gave me.
function S.Newest(h)
	return math.max(h.scan or 0, h.friendScan or 0)
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

-- My full scan was kept (Prices.lua): offered to every friend again.
function S.Scanned(key)
	if key ~= P().HomeKey() then
		return -- (a neutral auction house's isn't shared)
	end
	for _, f in pairs(S.friends) do
		f.due = true
		if f.watch then
			f.freshAll, f.freshSince = true, f.freshSince or GetTime()
			S.anyPoints = true
		end
	end
	S.anyDue = true
end

-- A watched item searched on my auction house (Prices.lua's P.Store): fresh for the friends who watch it too.
function S.Searched(key, item)
	if key ~= P().HomeKey() then
		return
	end
	for _, f in pairs(S.friends) do
		if f.watch and f.watch[item] then
			f.fresh[item], f.freshSince = true, f.freshSince or GetTime()
			S.anyPoints = true
		end
	end
end

-- My watch list on the wire: base-36 IDs, the first of the list that fit in a message, WATCH_MAX at most.
function S.WatchText(house)
	local db = W.DB and W.DB()
	local out, seen, bytes = {}, {}, #S.Msg("ww", house, "1", "")
	for _, item in ipairs(db and type(db.watch) == "table" and db.watch or {}) do
		if type(item) == "number" and item >= 1 and item <= 1e7 and item % 1 == 0 and not seen[item] then
			local id = P().B36(item)
			if #out >= WATCH_MAX or bytes + #id + 1 > MESSAGE_BYTES then
				break
			end
			seen[item], out[#out + 1], bytes = true, id, bytes + #id + 1
		end
	end
	return table.concat(out, ",")
end

-- My watch list to each friend whose build reads it, when it isn't what they have (first: always).
function S.SendWatch(now)
	local house = S.MyHouse()
	if not house then
		return
	end
	local text
	for id, peer in pairs(B.peers) do
		if S.ReadsPoints(peer) then
			text = text or S.WatchText(house)
			local f = S.Friend(id)
			if f.sentWatch ~= text and now - (f.watchAt or -math.huge) >= WATCH_GAP then
				f.sentWatch, f.watchAt = text, now
				B.QueueLow(id, S.Msg("ww", house, f.heard and "" or "1", text))
			end
		end
	end
end

-- Fresh points to each friend who has some due: at most every POINTS_GAP, and not while my searches still run
-- (FRESH_WAIT at most), so a search scan's items go together.
function S.SendPoints(now)
	local left = false
	local scan = P().scan
	local searching = scan ~= nil and scan.kind == "search"
	for id, f in pairs(S.friends) do
		if f.freshAll or next(f.fresh) then
			local peer = B.peers[id]
			if not (f.watch and peer and S.ReadsPoints(peer)) then
				f.freshAll, f.freshSince = nil, nil
				wipe(f.fresh)
			elseif now - (f.pointsAt or -math.huge) < POINTS_GAP or (searching and now - (f.freshSince or now) < FRESH_WAIT) then
				left = true
			else
				if S.QueuePoints(id, f) > 0 then
					f.pointsAt = now -- (nothing to tell: the next scan's go at once)
				end
				f.freshAll, f.freshSince = nil, nil
				wipe(f.fresh)
			end
		end
	end
	S.anyPoints = left
end

-- My data of the items a friend watches (those fresh, or all after a full scan): from my last scan of each when
-- it's at most POINT_AGE old, the newest first, as many wf as they take (MESSAGE_BYTES, POINTS_ITEMS). Gives how
-- many messages were queued.
function S.QueuePoints(id, f)
	local key = P().HomeKey()
	local house, h = S.MyHouse()
	if not (key and house and h) then
		return 0
	end
	local prices = P()
	local now = time()
	local today = prices.Today(now)
	local list = {}
	for _, item in ipairs(f.watchList or {}) do
		local e = (f.freshAll or f.fresh[item]) and prices.Entry(key, item)
		if e and e.seen and e.seen <= now and now - e.seen <= POINT_AGE then
			local gone, span
			local day = prices.Today(e.seen)
			for _, d in ipairs(prices.DecodeDays(h.flow[item], today)) do
				if d[1] == day and d[3] > 0 then
					gone, span = d[2], d[3]
				end
			end
			if e.low or span then
				list[#list + 1] = { item = item, seen = e.seen, low = e.low, qty = e.qty or 0, gone = gone, span = span }
			end
		end
	end
	table.sort(list, function(a, b) return a.seen > b.seen end)
	local B36 = prices.B36
	local i, sent = 1, 0
	while list[i] do
		local base = list[i].seen
		local age = math.max(0, now - base)
		local entries, bytes = {}, #S.Msg("wf", house, age, "")
		while list[i] and #entries < POINTS_ITEMS do
			local x = list[i]
			local older = base - x.seen
			local entry = table.concat({ B36(x.item), x.low and B36(x.low) or "", B36(x.qty), x.span and B36(x.gone) or "",
				x.span and B36(x.span) or "", older > 0 and B36(older) or "" }, ":")
			if entries[1] and bytes + #entry + 1 > MESSAGE_BYTES then
				break
			end
			entries[#entries + 1], bytes = entry, bytes + #entry + 1
			i = i + 1
		end
		B.QueueLow(id, S.Msg("wf", house, age, table.concat(entries, ",")))
		sent = sent + 1
	end
	return sent
end

function S.Offer(now)
	local house, h = S.MyHouse()
	if not (house and h.scan) then
		return
	end
	local left = false
	for id, peer in pairs(B.peers) do
		if S.Reads(peer) then
			local f = S.Friend(id)
			if f.due then
				if now - (f.offeredAt or -math.huge) >= OFFER_GAP then
					f.due, f.offeredAt = false, now
					B.QueueLow(id, S.Msg("wo", house, math.max(0, time() - h.scan)))
				else
					left = true
				end
			end
		end
	end
	S.anyDue = left
end

-- One answer: the items of my house (their keys only: encoded a message at a time), those listed at my last
-- scan first, then the rest; SERVE_MAX at most.
function S.NextEntry(s, key, today)
	while true do
		local item = s.keys[s.i]
		if not item then
			if s.pass == 1 then
				s.pass, s.i = 2, 1
				item = s.keys[1]
			end
			if not item then
				return nil
			end
		end
		s.i = s.i + 1
		local e = P().Entry(key, item)
		if e and (e.low ~= nil) == (s.pass == 1) then
			local entry, seen = S.EncodeEntry(key, item, today)
			if entry then
				return entry, seen
			end
		end
	end
end

-- An item's entry on the wire, and when its data is from; nil: nothing to tell.
function S.EncodeEntry(key, item, today)
	local prices = P()
	local e = prices.Entry(key, item)
	if not e then
		return nil
	end
	local value, days = prices.Value(e.days, today)
	if not (value or e.low) then
		return nil
	end
	local B36 = prices.B36
	return table.concat({ B36(item), value and B36(value) or "", e.low and B36(e.low) or "", B36(e.qty or 0), B36(days),
		prices.Unstable(e.days, today) and "1" or "" }, ":"), e.seen
end

function S.Serve()
	if not S.serving then
		local id = table.remove(S.serves, 1)
		if not id then
			return
		end
		local house, h = S.MyHouse()
		if not (house and B.peers[id]) then
			return
		end
		S.serving = { id = id, house = house, keys = P().Keys(h.items), i = 1, pass = 1, sent = 0 }
	end
	local s = S.serving
	local key = P().HomeKey()
	local today = P().Today()
	local now = time()
	for _ = 1, SEND_STEP do
		if B.Waiting() >= SEND_WAITING then
			return
		end
		if not B.peers[s.id] then
			S.serving = nil
			return
		end
		local entries, bytes, oldest = {}, 0, now
		local room = MESSAGE_BYTES - #S.Msg("wp", s.house, "0000000", "")
		local entry, seen = s.held, s.heldSeen
		s.held = nil
		if not entry then
			entry, seen = S.NextEntry(s, key, today)
		end
		while entry and s.sent + #entries < SERVE_MAX do
			if bytes + #entry + 1 > room then
				s.held, s.heldSeen = entry, seen -- (the next message's first)
				break
			end
			entries[#entries + 1] = entry
			bytes = bytes + #entry + 1
			oldest = math.min(oldest, seen)
			entry, seen = S.NextEntry(s, key, today)
		end
		if entries[1] then
			B.QueueLow(s.id, S.Msg("wp", s.house, math.max(0, now - oldest), table.concat(entries, ",")))
			s.sent = s.sent + #entries
		end
		if not s.held then
			B.QueueLow(s.id, S.Msg("we", s.house, s.sent))
			S.serving = nil
			return
		end
	end
end

-- The friend whose scan is newest and newer than my data, asked if no one is.
function S.Ask(now)
	if S.pending then
		if now - S.pending.at >= PENDING_TIMEOUT then
			S.pending = nil
		else
			return
		end
	end
	local house, h = S.MyHouse()
	if not house then
		return
	end
	local bestId, best
	for id, f in pairs(S.friends) do
		if f.theirs and B.peers[id] and f.theirs > S.Newest(h) + NEWER and now - (f.askedAt or -math.huge) >= ASK_GAP
			and (not best or f.theirs > best.theirs) then
			bestId, best = id, f
		end
	end
	if best then
		best.askedAt = now
		S.pending = { id = bestId, at = now, seen = best.theirs, n = 0 }
		B.Queue(bestId, S.Msg("wq", house))
	end
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

-- Beacon.lua hands every B2;w... here (after its own guard), inside the event: only noted.
function B.ReceivePrices(id, word, more)
	if not (WORDS[word] and B.peers[id]) or S.inTail - S.inHead + 1 >= INCOMING_MAX then
		return
	end
	S.inTail = S.inTail + 1
	S.incoming[S.inTail] = { id, word, more }
end

local function Num(s, max)
	local n = s and s ~= "" and #s <= 9 and tonumber(s, 36)
	return n and n >= 0 and n <= max and n or nil
end

-- One entry of a wp: item, value, low, qty, days, unstable; nil: broken.
function S.DecodeEntry(text)
	local a, b, c, d, e, f = text:match("^(%w+):(%w*):(%w*):(%w+):(%w+):(1?)$")
	local item = Num(a, 1e7)
	if not item or item < 1 then
		return nil
	end
	local value, low = Num(b, MONEY_MAX), Num(c, MONEY_MAX)
	if (b ~= "" and not value) or (c ~= "" and not low) or not (value or low) then
		return nil
	end
	local qty, days = Num(d, QTY_MAX), Num(e, P().DAYS)
	if not (qty and days) then
		return nil
	end
	return item, value, low, qty, days, f == "1"
end

-- One entry of a wf: item, low (nil: none listed), qty, gone and span (nil: none), older; nil: broken.
function S.DecodePoint(text)
	local a, b, c, d, e, g = text:match("^(%w+):(%w*):(%w+):(%w*):(%w*):(%w*)$")
	local item = Num(a, 1e7)
	if not item or item < 1 then
		return nil
	end
	local low, qty, gone, span = Num(b, MONEY_MAX), Num(c, QTY_MAX), Num(d, QTY_MAX), Num(e, SPAN_MAX)
	local older = g == "" and 0 or Num(g, POINT_AGE)
	if (b ~= "" and not low) or not qty or (d ~= "" and not gone) or (e ~= "" and not span) or (d == "") ~= (e == "")
		or not older or not (low or span) then
		return nil
	end
	return item, low, qty, gone, span, older
end

-- A friend's watch list (ww): kept for my scans; a broken one is dropped. Their ask: mine goes to them again
-- (unless mine went just now: the two crossed).
function S.TakeWatch(f, more, myHouse)
	local house, ask, list = more:match("^(%x+);(1?);([%w,]*)$")
	local now = GetTime()
	if not (house and house == myHouse) or now - (f.watchTakenAt or -math.huge) < WATCH_TAKE_GAP then
		return
	end
	local set, order = {}, {}
	for text in list:gmatch("[^,]+") do
		local item = Num(text, 1e7)
		if not item or item < 1 or #order >= WATCH_MAX then
			return
		end
		if not set[item] then
			set[item], order[#order + 1] = true, item
		end
	end
	f.watchTakenAt, f.heard = now, true
	if ask == "1" and now - (f.watchAt or -math.huge) > CROSSED then
		f.sentWatch = nil
	end
	f.watch, f.watchList = order[1] and set or nil, order
	wipe(f.fresh)
	f.freshAll, f.freshSince = order[1] and true or nil, order[1] and now or nil -- (my latest of them, at once)
	S.anyPoints = S.anyPoints or order[1] ~= nil
end

-- A friend's fresh points (wf): checked whole first (a broken one is dropped), at most POINTS_LIMIT in
-- POINTS_WINDOW from one friend; only items I watch are recorded, marked as theirs (P.RecordFriend).
function S.TakePoints(id, f, more, now)
	local house, age, list = more:match("^(%x+);(%d+);([%w:,]+)$")
	local myHouse, h = S.MyHouse()
	if not (house and h and house == myHouse and #age <= 9 and tonumber(age) <= POINT_AGE) then
		return
	end
	local at = GetTime()
	if not (f.takesAt and f.takes) or at - f.takesAt >= POINTS_WINDOW then
		f.takesAt, f.takes = at, 0
	end
	if f.takes >= POINTS_LIMIT then
		return
	end
	f.takes = f.takes + 1
	local prices = P()
	local watch = prices.WatchSet()
	local points = {}
	local n = 0
	for entry in list:gmatch("[^,]+") do
		n = n + 1
		if n > POINTS_ITEMS then
			return
		end
		local item, low, qty, gone, span, older = S.DecodePoint(entry)
		local t = item and now - tonumber(age) - older
		if not t or now - t > POINT_AGE then
			return
		end
		if watch[item] then
			points[#points + 1] = { item, t, low, qty, gone, span }
		end
	end
	local peer = B.peers[id]
	local name = peer and peer.name and B.Clean(peer.name, 48) or ""
	local who = points[1] and name ~= "" and prices.Who(h, name)
	if not who then
		return
	end
	for _, p in ipairs(points) do
		prices.RecordFriend(h, p[1], p[2], p[3], p[4], who, p[5], p[6])
	end
	prices.Changed()
end

-- A friend's prices: kept only where they're newer than my own and than what a friend gave before.
function S.Take(id, more, now)
	local house, age, list = more:match("^(%x+);(%d+);(.+)$")
	local myHouse, h = S.MyHouse()
	local p = S.pending
	if not (house and house == myHouse and p and p.id == id and tonumber(age) <= P().KEEP) then
		return
	end
	p.at = GetTime()
	local seen = now - tonumber(age)
	local peer = B.peers[id]
	local name = peer and peer.name and B.Clean(peer.name, 48) or "?"
	local key = P().HomeKey()
	local B36 = P().B36
	local took = false
	for entry in list:gmatch("[^,]+") do
		local item, value, low, qty, days, unstable = S.DecodeEntry(entry)
		if item then
			p.n = p.n + 1
			local mine = P().Entry(key, item)
			local had = P().FriendEntry(h, item)
			if not (mine and mine.seen >= seen) and not (had and had.seen >= seen) then
				h.friends[item] = table.concat({ B36(seen), value and B36(value) or "", low and B36(low) or "", B36(qty), B36(days),
					unstable and "1" or "", B36(now) }, ",") .. ";" .. name
				took = true
			end
		end
	end
	if took then
		P().Changed()
	end
end

function S.Handle(id, word, more, now)
	if not S.Sharing() then
		return -- (the setting off: nothing taken, nothing answered)
	end
	local f = S.Friend(id)
	local myHouse, h = S.MyHouse()
	if word == "wo" then
		local house, age = more:match("^(%x+);(%d+)$")
		if house and house == myHouse and #age <= 10 then
			f.theirs = now - tonumber(age)
		end
	elseif word == "wq" then
		if more == myHouse and h.scan and GetTime() - (f.answeredAt or -math.huge) >= ANSWER_GAP then
			f.answeredAt = GetTime()
			for i = #S.serves, 1, -1 do
				if S.serves[i] == id then
					table.remove(S.serves, i)
				end
			end
			S.serves[#S.serves + 1] = id
		end
	elseif word == "wp" then
		S.Take(id, more, now)
	elseif word == "ww" then
		S.TakeWatch(f, more, myHouse)
	elseif word == "wf" then
		S.TakePoints(id, f, more, now)
	elseif word == "we" then
		local house = more:match("^(%x+);%d+$")
		local p = S.pending
		if house and house == myHouse and p and p.id == id then
			h.friendScan = math.max(h.friendScan or 0, p.seen)
			S.pending = nil
			P().Changed()
		end
	end
end

function S.Incoming()
	local handled, now, start = 0, time(), Clock()
	while S.inHead <= S.inTail and handled < HANDLE_STEP do
		local item = S.incoming[S.inHead]
		S.incoming[S.inHead] = nil
		S.inHead, handled = S.inHead + 1, handled + 1
		local ok, err = pcall(S.Handle, item[1], item[2], item[3], now)
		if not ok then
			geterrorhandler()(err)
		end
		if start and (Clock() or start) - start >= HANDLE_MS then
			break -- (the rest next tick)
		end
	end
	if S.inHead > S.inTail then
		S.inHead, S.inTail = 1, 0
	end
end

---------------------------------------------------------------------------
-- Beacon's tick (10 a second): nothing in a fight, nothing while there's nothing to do
---------------------------------------------------------------------------

function S.Idle(now)
	return S.inHead > S.inTail and not S.serving and not S.serves[1] and not S.pending and not S.anyDue
		and not S.anyPoints and now - S.lastSlow < SLOW_TICK * 10
end

function B.TickPrices(now)
	if S.Idle(now) or LT.InFight() then
		return
	end
	S.Incoming()
	if now - S.lastSlow < SLOW_TICK then
		return
	end
	S.lastSlow = now
	if not S.Sharing() then
		S.serving, S.pending, S.anyPoints = nil, nil, false
		wipe(S.serves)
		for _, f in pairs(S.friends) do -- (on again: lists sent and asked for anew)
			f.watch, f.watchList, f.sentWatch, f.heard, f.freshAll, f.freshSince = nil, nil, nil, nil, nil, nil
			wipe(f.fresh)
		end
		return
	end
	for id, peer in pairs(B.peers) do
		if S.Reads(peer) and not S.friends[id] then
			S.Friend(id) -- (a friend first seen: offered once)
			S.anyDue = true
		end
	end
	if S.anyDue then
		S.Offer(now)
	end
	S.SendWatch(now)
	if S.anyPoints then
		S.SendPoints(now)
	end
	S.Ask(GetTime())
	S.Serve()
end

-- A friend gone (Beacon.lua's Forget).
function B.PricesForget(id)
	S.friends[id] = nil
	for i = #S.serves, 1, -1 do
		if S.serves[i] == id then
			table.remove(S.serves, i)
		end
	end
	if S.serving and S.serving.id == id then
		S.serving = nil
	end
	if S.pending and S.pending.id == id then
		S.pending = nil
	end
end

-- Beacon switched off.
function B.PricesStop()
	wipe(S.friends)
	wipe(S.serves)
	wipe(S.incoming)
	S.inHead, S.inTail = 1, 0
	S.serving, S.pending, S.anyDue, S.anyPoints = nil, nil, false, false
end
