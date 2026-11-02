local _, ns = ...
local LT = ns.LT
local E = ns.Echoes
local M = E.module

-- Delivery: pages go from their author to whoever collects them, through Beacon. Battle.net
-- messages only reach friends online right now, so every client offers the pages it holds (its
-- own, the ones it relays, a collector's) and friends pass them on: a page gets from its author to
-- the collector also when the two are never online together. A collector asks for every page it
-- lacks; a relay for pages no collector holds safely yet, while few others hold them. A page goes
-- whole or not at all: in parts of its stored Base64 text (each a substring of it), checked
-- against its hash, never decompressed in game. Collectors say what they hold safely (on their
-- disk, or exported); that is passed on, so authors and relays drop their copies.
--
-- Early pages: an author's pages closed this session aren't on its disk yet (after a crash the next
-- session numbers its pages from the last save again), so they go to everyone only from its next
-- session on. A collector online now gets them at once (ea), but keeps them provisional (E.Store):
-- never safe, never served, told only to their author, until a copy from the author's disk (anyone's
-- normal offer of that number) shows the same hash: a check asks for it and stops at its start (eb).
-- Another hash: another page with that number; it's fetched once the receipt took the provisional
-- one (both reach the exporter). So nobody drops a page for one that came early, and nothing is lost.
--
-- Messages: Beacon's B family (Protocol.lua), module letter e. Only to friends who sent eh (an
-- eh itself only to a build that reads it, see Hello):
--   B2;eh;<acct>;<store>;<proto>;<maxBytes>;<flags>
--                       hello: flags c collect, r relay, s share, e takes early pages (with c,
--                       while the inbox isn't full), a an answer (no answer to it); none of c, r,
--                       s: switched off. In answer to a hello, when the flags change
--   B2;es;<acct>.<store>:<ranges>/...    pages I can serve ("1-56,58")
--   B2;ea;<acct>.<store>:<ranges>/...    my own pages not on my disk yet, to a collector who takes
--                       them early (older builds read no ea, and send no e)
--   B2;ed;<collector acct>;<collector store>;<acct>.<store>:<ranges>/...
--                       pages safe at that collector; passed on by everyone; only grows
--   B2;eq;<acct>;<store>;<n>;<offset>    send me page n from byte offset (offset = its length: stop)
--   B2;eb;<x>;<acct>;<store>;<n>;<len>;<hash>;<t0>;<m>
--                       page n begins: transfer x (1-99, mine), its length, LT.Hash32, start, mode
--   B2;ep;<x>;<offset>;<data>             a part: up to 240 bytes of the page's Base64 text
--   B2;en;<acct>;<store>;<n>             I don't have it: ask someone else
--   B2;ex;<size>;<padding> / B2;ey;<size>;<got>
--                       the probe (bigger than 255 bytes, Beacon lets it through) and its answer
--
-- Never lags the client and never gets in the way: Beacon hands messages over and they wait for
-- the tick, which handles a bounded number; everything goes through Beacon's low-priority queue,
-- only when nothing else waits there (chat, positions, the fight stream, journals first), at most 3
-- waiting, 3 a second, 2 a second to one friend; nothing in combat; after a throttle Echoes is
-- silent for a while. Unfinished pages stay in memory.
--
-- The pages are Store.lua's (E.Store): every change to them goes through it, and it checks what
-- comes (hash, size, start, room).

local PROTO = 1              -- these rules' version (eh)
local MAX_BYTES = 255        -- my messages' size at most (Beacon's; eh tells it, for later builds)
local PART = 240             -- Base64 bytes per part: "B2;ep;<x>;<offset>;" takes at most 15
local PAGE_MAX = 65536       -- a page is at most 64 KB (E.Store keeps no bigger one)
local OUTSTANDING = 3        -- my messages waiting in Beacon's queue at most
local RATE, PEER_RATE = 3, 2 -- my messages a second, in total and to one friend
local IN_FLIGHT = 2          -- pages asked for at once (one per holder)
local SILENCE = 30           -- a request without progress this long: asked again, from where it got to
local SERVE_QUEUE, SERVING = 20, 2 -- requests a holder keeps, and serves at once
local SUMMARY_GAP, FULL_OFFER = 60, 300 -- what I hold: when it grew (at most this often), all of it this often
local FULL_SAFE = 1800       -- what's safe (ed) all of it this often: it only grows, and friends keep it
local OUT_MAX = 200          -- my messages waiting their turn at most (past it summaries wait: they come again)
local SUMMARY_FRIENDS = 3    -- friends whose summaries are made in one second at most
local BACKOFF_FIRST, BACKOFF_MAX, BACKOFF_CALM = 30, 300, 600 -- after a throttle: silent this long,
                             -- twice that after the next one (up to BACKOFF_MAX), back to the first after calm
local HELLO_WAIT = 60        -- a friend's build not known to read B this long after their hello: an older one
local COPIES = 2             -- a relay leaves pages alone that this many online friends besides the author hold
local NO_ROOM_WAIT = 300     -- a page too big for the relay's cache isn't asked for again this long
local PARTIALS_MAX, PARTIAL_AGE = 256 * 1024, 600 -- unfinished pages: bytes kept, seconds without progress
local INCOMING_MAX, INCOMING_PER_TICK = 600, 60 -- messages waiting for the tick, handled per tick
local FRIENDS_GAP = 30       -- the friend list's accounts are read again after this long,
local FRIENDS_SOON = 5       -- or after this long when it may have changed (an account not in it, Battle.net's events)
local RECHECK = 300          -- what I hold is worked out anew at least this often (E.Store says when it changes)
local HOUSE_GAP = 1          -- requests, timeouts, checks, summaries: once a second
local ANSWERS_MAX = 8        -- my answers (en, ey, a stop) waiting for one friend at most: more go (they ask again)
local PROBE_SIZES = { 255, 500, 1000, 2000, 4000 }
local PROBE_GAP, PROBE_WAIT = 2, 10 -- between probe messages; answers awaited after the last
-- The first LefthyTools build with Delivery (41f011b; LT.CompareVersions goes by the commit count):
-- a friend on an older one is never sent a B message (0.6.0-24 reads B2 but has no Delivery). A
-- friend whose build doesn't say (no commit count) gets an eh only in answer to theirs.
local ECHOES_SINCE = "0.6.0-25-g41f011b"

local D = {}
E.Delivery = D -- (status, probe, tests)

local issecret = LT.IsSecret
local function Readable(s)
	return type(s) == "string" and not issecret(s) and s ~= ""
end

local function Count(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end

-- Beacon's shared table while Beacon is on, else nil.
local function Beacon()
	local beacon = LT:GetModule("beacon")
	return beacon and beacon.enabled and ns.Beacon or nil
end

---------------------------------------------------------------------------
-- Ranges: page numbers as a sorted list of intervals { { 1, 56 }, { 58, 58 } } ("1-56,58")
---------------------------------------------------------------------------

local Ranges = {}
D.Ranges = Ranges
local RANGES_MAX = 300   -- intervals in one list at most (a broken or hostile client)
local N_MAX = 999999999   -- page numbers are 1 to this (E.Store's)

-- Sorted, overlapping and adjacent intervals joined (in place, returns the list).
function Ranges.Normal(list)
	table.sort(list, function(x, y) return x[1] < y[1] end)
	local out = {}
	for _, r in ipairs(list) do
		local last = out[#out]
		if last and r[1] <= last[2] + 1 then
			if r[2] > last[2] then
				last[2] = r[2]
			end
		else
			out[#out + 1] = { r[1], r[2] }
		end
	end
	return out
end

-- "1-56,58" as a list; "" is empty; nil if it isn't one.
function Ranges.Parse(text)
	if type(text) ~= "string" then
		return nil
	end
	local list = {}
	if text == "" then
		return list
	end
	for part in (text .. ","):gmatch("([^,]*),") do
		local a, b = part:match("^(%d+)%-(%d+)$")
		if not a then
			a = part:match("^(%d+)$")
			b = a
		end
		if not a or #a > 10 or #b > 10 then
			return nil
		end
		a, b = tonumber(a), tonumber(b)
		if a < 1 or b < a or b > N_MAX or #list >= RANGES_MAX then
			return nil
		end
		list[#list + 1] = { a, b }
	end
	return Ranges.Normal(list)
end

function Ranges.Format(list)
	local parts = {}
	for i, r in ipairs(list) do
		parts[i] = r[1] == r[2] and tostring(r[1]) or (r[1] .. "-" .. r[2])
	end
	return table.concat(parts, ",")
end

function Ranges.Union(x, y)
	local all = {}
	for _, r in ipairs(x) do
		all[#all + 1] = { r[1], r[2] }
	end
	for _, r in ipairs(y) do
		all[#all + 1] = { r[1], r[2] }
	end
	return Ranges.Normal(all)
end

-- x without y (both sorted).
function Ranges.Minus(x, y)
	local out, j = {}, 1
	for _, r in ipairs(x) do
		local a, b = r[1], r[2]
		while y[j] and y[j][2] < a do
			j = j + 1
		end
		local k = j
		while a <= b do
			local s = y[k]
			if not s or s[1] > b then
				out[#out + 1] = { a, b }
				break
			end
			if s[1] > a then
				out[#out + 1] = { a, s[1] - 1 }
			end
			a = math.max(a, s[2] + 1)
			k = k + 1
		end
	end
	return out
end

function Ranges.Has(list, n)
	for _, r in ipairs(list) do
		if n < r[1] then
			return false
		elseif n <= r[2] then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------
-- Accounts: mine, my Battle.net friends', a Beacon friend's (Chronicle's hashes, which work
-- whether Chronicle is on or not)
---------------------------------------------------------------------------

local function Hash(tag)
	return LT.Hash32(tag:lower())
end

local myAcct
local function MyAccount()
	if not myAcct and BNGetInfo then
		local _, tag = BNGetInfo()
		if Readable(tag) then
			myAcct = Hash(tag)
		end
	end
	return myAcct
end

local friendAccts, idAccts, friendsAt = {}, {}, -math.huge -- acct -> true; gameAccountID -> acct
local missed, missedCount = {}, 0 -- acct -> true: looked for since the list was read, not in it
local friendsStale = false   -- Battle.net said a friend came online or changed: read it again soon

-- Every Battle.net friend, online or not: their account, and which game accounts are theirs.
local function ReadFriends(now)
	friendsAt, friendsStale = now, false
	wipe(friendAccts)
	wipe(idAccts)
	wipe(missed)
	missedCount = 0
	local bn = C_BattleNet
	local count = bn and bn.GetFriendAccountInfo and BNGetNumFriends and BNGetNumFriends() or 0
	for i = 1, count do
		local info = bn.GetFriendAccountInfo(i)
		local tag = info and info.battleTag
		if Readable(tag) then
			local acct = Hash(tag)
			friendAccts[acct] = true
			local game = info.gameAccountInfo
			if type(game) == "table" and type(game.gameAccountID) == "number" then
				idAccts[game.gameAccountID] = acct
			end
			for j = 1, (bn.GetFriendNumGameAccounts and bn.GetFriendNumGameAccounts(i) or 0) do
				game = bn.GetFriendGameAccountInfo and bn.GetFriendGameAccountInfo(i, j)
				if type(game) == "table" and type(game.gameAccountID) == "number" then
					idAccts[game.gameAccountID] = acct
				end
			end
		end
	end
end

local function Friends(now)
	if now - friendsAt >= FRIENDS_GAP or (friendsStale and now - friendsAt >= FRIENDS_SOON) then
		ReadFriends(now)
	end
	return friendAccts
end

-- Battle.net says a friend came online, changed (logged into a game) or the list changed: the list is
-- read again when next needed, at most every FRIENDS_SOON (the handlers only note it).
local function FriendsChanged()
	friendsStale = true
end
E.On("BN_FRIEND_ACCOUNT_ONLINE", FriendsChanged)
E.On("BN_FRIEND_INFO_CHANGED", FriendsChanged)
E.On("BN_FRIEND_LIST_SIZE_CHANGED", FriendsChanged)

-- Pages I take: my Battle.net friends' accounts' and my own (my other computers). An account the
-- list as last read doesn't have (a friend just added, or one Battle.net listed late): the list is
-- read again, at most every FRIENDS_SOON and once per account until it's read anew, so a friend's
-- holdings that came before Battle.net listed them aren't dropped until the next summary.
local function Accepted(acct, now)
	if acct == nil then
		return false
	elseif acct == MyAccount() or Friends(now)[acct] then
		return true
	end
	if not missed[acct] and now - friendsAt >= FRIENDS_SOON then
		ReadFriends(now)
	end
	if not missed[acct] and missedCount < 256 then
		missed[acct], missedCount = true, missedCount + 1
	end
	return friendAccts[acct] == true
end

-- A Beacon friend's account (their BattleTag's hash), nil while Battle.net doesn't say.
local function PeerAccount(id, now)
	Friends(now)
	local acct = idAccts[id]
	if not acct and now - friendsAt >= FRIENDS_SOON then
		ReadFriends(now) -- (a friend just came online)
		acct = idAccts[id]
	end
	if not acct then
		local peer = ns.Beacon.peers[id]
		local guid = peer and peer.guid
		local info = Readable(guid) and C_BattleNet and LT.Value(C_BattleNet.GetAccountInfoByGUID, guid)
		local tag = type(info) == "table" and info.battleTag
		if Readable(tag) then
			acct = Hash(tag)
		end
	end
	return acct
end
D.PeerAccount, D.MyAccount = PeerAccount, MyAccount

---------------------------------------------------------------------------
-- The pages: Store.lua's E.Store. Every change to them goes through it, and it checks what comes
-- (the hash, the size, the start, exported, safe, room). What Delivery works out of them (what I
-- hold, what's exported or safe) is cached until they change.
---------------------------------------------------------------------------

local S = E.Store
local cache = {}

-- Ranges kept here (what I hold, what's exported or safe) as a list: read leniently (E.Ranges, no
-- limit on their number). D.Ranges.Parse is for the wire: strict, at most RANGES_MAX intervals.
local function Stored(ranges)
	return type(ranges) == "string" and E.Ranges.Parse(ranges) or {}
end

local summaryGen = 0 -- (counts the changes: a summary is worked out again only after one)
local function Changed()
	wipe(cache)
	summaryGen = summaryGen + 1
end
-- Pages changed outside Delivery (closed, packed, dropped by the cap, the 30 days or a receipt):
-- looked at anew. Store.lua calls it on every change; Delivery also looks again every RECHECK
-- seconds, a safety net.
D.PagesChanged = Changed

-- My pages' key, nil while my BattleTag isn't known.
local function MyKey()
	return S.Own()
end

local function Split(key)
	return key:sub(1, 8), key:sub(10)
end

-- A store's key as it goes on the wire ("acct.store", 8 lowercase hex digits each). One that isn't
-- (a saved file edited by hand) stays here: it would make friends refuse the whole message it's in,
-- or make one longer than 255 bytes.
local function WireKey(key)
	return type(key) == "string" and #key == 17 and key:sub(9, 9) == "." and key:match("^[0-9a-f]+%.[0-9a-f]+$") ~= nil
end

-- What I hold of where ("mine", "carry", "inbox", or "early": mine not on disk yet, "provisional": a
-- collector's pages that came early, E.Store.Held): { [key] = list }.
local function HeldIn(where)
	local id = "held>" .. where
	if not cache[id] then
		local out = {}
		for key, ranges in pairs(S.Held(where)) do
			local list = Stored(ranges)
			if #list > 0 and WireKey(key) then
				out[key] = list
			end
		end
		cache[id] = out
	end
	return cache[id]
end

local function Have(where, key)
	return HeldIn(where)[key] or {}
end

-- What I can serve: { [key] = list } (my own pages, the ones I relay while relaying, a collector's).
local function Holdings()
	if not cache.holdings then
		local held = {}
		for _, where in ipairs({ "mine", "carry", "inbox" }) do
			if where ~= "carry" or M.db.relay then
				for key, list in pairs(HeldIn(where)) do
					held[key] = held[key] and Ranges.Union(held[key], list) or list
				end
			end
		end
		cache.holdings = held
	end
	return cache.holdings
end
D.Holdings = Holdings

-- A page I can serve (of key, number n), or nil. early: my own not on disk yet too (to a collector
-- who takes pages early).
local function Get(key, n, early)
	local acct, store = Split(key)
	local page = S.Page(acct, store, n, early)
	return S.Shareable(page) and page or nil
end

-- Whether I hold page n of key provisionally (it came early): its hash and where (E.Store); only
-- while I collect (then the checks run; what a collector kept from before means nothing to a relay).
local function Provisional(key, n)
	if M.db.collect then
		local acct, store = Split(key)
		return S.Provisional(acct, store, n)
	end
end

-- A collector's: what the exporter has of key.
local function Exported(key)
	local id = "exported>" .. key
	if not cache[id] then
		cache[id] = Stored(E.data.exported[key])
	end
	return cache[id]
end

-- What some collector holds safely of key (what collectors said, and mine if I collect).
local function SafeOf(key)
	local id = "safe>" .. key
	if not cache[id] then
		local list = {}
		local collectors = E.data.safe[key]
		for _, ranges in pairs(type(collectors) == "table" and collectors or {}) do
			list = Ranges.Union(list, Stored(ranges))
		end
		cache[id] = list
	end
	return cache[id]
end

-- A collector holds list of key safely: E.Store merges it into safe (only grows) and drops those
-- pages from mine and carry. Only when it grows; at most SAFE_KEYS stores and SAFE_COLLECTORS
-- collectors each, and from friends (told) at most RANGES_MAX intervals each: a broken or hostile
-- client can't fill the saved table, nor make every message parse a longer list. (Past that, the
-- rest isn't taken as safe: its pages are kept, nothing is lost.)
local SAFE_KEYS, SAFE_COLLECTORS = 200, 8
local function Safe(key, collector, list, told)
	local safe = E.data.safe
	local byCollector = type(safe[key]) == "table" and safe[key] or nil
	if not byCollector and Count(safe) >= SAFE_KEYS then
		return
	elseif byCollector and not byCollector[collector] and Count(byCollector) >= SAFE_COLLECTORS then
		return
	end
	local old = byCollector and byCollector[collector]
	local union = Ranges.Union(Stored(old), list)
	local merged = Ranges.Format(union)
	if merged == "" or merged == old or (told and #union > RANGES_MAX) then
		return
	end
	local acct, store = Split(key)
	S.Safe(acct, store, merged, collector)
	Changed()
end

-- A collector's own summary, like the ones friends send: what's on its disk or exported (E.Store's
-- SafeHere), for every store it has pages of. (Again only once the pages changed.)
local function SafeHere()
	local mine = MyKey()
	if not mine or cache.safeHere then
		return
	end
	local keys = {}
	for key in pairs(E.data.inbox) do
		keys[key] = true
	end
	for key in pairs(E.data.exported) do
		keys[key] = true
	end
	for key in pairs(keys) do
		local acct, store = Split(key)
		local list = Stored(S.SafeHere(acct, store))
		if #list > 0 then
			Safe(key, mine, list)
			S.Mentioned(acct, store) -- (my own summary: first-hand)
		end
	end
	cache.safeHere = true
end

-- A page that came, kept by E.Store where ("carry" or "inbox"; provisional: it came early): true
-- (true, "have": had it), or false and why (E.Store.Put's reasons).
local function Put(key, n, page, where, provisional)
	local acct, store = Split(key)
	local ok, why = S.Put(acct, store, n, page, where, provisional)
	Changed()
	return ok, why
end

-- A page I relay already, collected now: it moves to the inbox (one E.Store won't keep there,
-- exported, from before the launch or broken, just goes).
local function Move(key, n, page)
	local acct, store = Split(key)
	S.Put(acct, store, n, page, "inbox")
	S.Drop(acct, store, tostring(n), "carry")
	Changed()
end

-- Whether a page of size bytes of key fits my relay cache (512 KB, 128 KB per author's store).
local function Fits(key, size)
	local acct, store = Split(key)
	return S.Fits(acct, store, size)
end

-- A relay holds these of my pages (they go first when mine is over its cap).
local function Carried(key, list)
	local acct, store = Split(key)
	S.Carried(acct, store, Ranges.Format(list))
end

---------------------------------------------------------------------------
-- Messages: writing and reading them
---------------------------------------------------------------------------

local function Msg(word, ...)
	return "B" .. ns.Beacon.VERSION .. ";" .. word .. ";" .. table.concat({ ... }, ";")
end

local function Hex8(s)
	return type(s) == "string" and #s == 8 and s:match("^[0-9a-f]+$") ~= nil
end

-- A number of at most digits digits in min..max, or nil.
local function Number(s, min, max)
	local n = type(s) == "string" and #s <= 10 and s:match("^%d+$") and tonumber(s)
	return n and n >= min and n <= max and n or nil
end

-- Items ("<acct>.<store>:<ranges>/..."): { { key, acct, list }, ... }, nil if malformed.
local function ReadItems(text)
	local items = {}
	for item in (text .. "/"):gmatch("([^/]*)/") do
		local acct, store, ranges = item:match("^(%w+)%.(%w+):(.+)$")
		local list = acct and Hex8(acct) and Hex8(store) and Ranges.Parse(ranges)
		if not list or #items >= 40 then
			return nil
		end
		items[#items + 1] = { acct .. "." .. store, acct, list }
	end
	return items
end

-- Items for a key's list, each fitting room bytes (a long list goes in pieces), added to into.
local function WriteItems(key, list, room, into)
	local width, current, size = room - #key - 1, {}, 0
	for _, r in ipairs(list) do
		local s = r[1] == r[2] and tostring(r[1]) or (r[1] .. "-" .. r[2])
		if #current > 0 and size + 1 + #s > width then
			into[#into + 1] = key .. ":" .. table.concat(current, ",")
			current, size = {}, 0
		end
		current[#current + 1] = s
		size = size + (#current > 1 and 1 or 0) + #s
	end
	if #current > 0 then
		into[#into + 1] = key .. ":" .. table.concat(current, ",")
	end
end

-- head .. items joined by "/", as few messages of at most MAX_BYTES as they fit in.
-- prefix: also what each message tells of, a list per message of prefix .. each item's key (its
-- first 17 characters: a summary's marks, see Tell).
local function Pack(head, items, prefix)
	local list, current, size = {}, {}, #head
	local marks, these = prefix and {}, prefix and {}
	for _, item in ipairs(items) do
		if #current > 0 and size + 1 + #item > MAX_BYTES then
			list[#list + 1] = head .. table.concat(current, "/")
			current, size = {}, #head
			if prefix then
				marks[#marks + 1], these = these, {}
			end
		end
		current[#current + 1] = item
		size = size + (#current > 1 and 1 or 0) + #item
		if prefix then
			local mark = prefix .. item:sub(1, 17)
			if these[#these] ~= mark then
				these[#these + 1] = mark
			end
		end
	end
	if #current > 0 then
		list[#list + 1] = head .. table.concat(current, "/")
		if prefix then
			marks[#marks + 1] = these
		end
	end
	return list, marks
end
D.Pack, D.WriteItems = Pack, WriteItems

-- A message's fields (what B.Parse gave: its word and the rest), checked; nil if it isn't one.
function D.Read(word, more)
	if type(more) ~= "string" then
		return nil
	end
	local f = {}
	for field in (more .. ";"):gmatch("([^;]*);") do
		f[#f + 1] = field
	end
	if word == "eh" then
		-- (later builds may add fields: they're ignored)
		local proto, maxBytes = Number(f[3], 1, 999), Number(f[4], 1, 999999)
		if #f >= 5 and Hex8(f[1]) and Hex8(f[2]) and proto and maxBytes and f[5]:match("^%l*$") and #f[5] <= 16 then
			local flags = f[5]
			return { acct = f[1], store = f[2], proto = proto, maxBytes = maxBytes, collect = flags:find("c", 1, true) ~= nil,
				relay = flags:find("r", 1, true) ~= nil, share = flags:find("s", 1, true) ~= nil, answer = flags:find("a", 1, true) ~= nil,
				early = flags:find("e", 1, true) ~= nil }
		end
	elseif word == "es" or word == "ea" then
		local items = #f == 1 and ReadItems(f[1])
		if items then
			return { items = items }
		end
	elseif word == "ed" then
		local items = #f == 3 and Hex8(f[1]) and Hex8(f[2]) and ReadItems(f[3])
		if items then
			return { acct = f[1], store = f[2], items = items }
		end
	elseif word == "eq" then
		local n, offset = Number(f[3], 1, N_MAX), Number(f[4], 0, PAGE_MAX)
		if #f == 4 and Hex8(f[1]) and Hex8(f[2]) and n and offset then
			return { acct = f[1], store = f[2], n = n, offset = offset }
		end
	elseif word == "eb" then
		local x, n, len, t0 = Number(f[1], 1, 99), Number(f[4], 1, N_MAX), Number(f[5], 1, PAGE_MAX), Number(f[7], 1, 9999999999)
		if #f == 8 and x and Hex8(f[2]) and Hex8(f[3]) and n and len and Hex8(f[6]) and t0 and (f[8] == "z" or f[8] == "r") then
			return { x = x, acct = f[2], store = f[3], n = n, len = len, hash = f[6], t0 = t0, m = f[8] }
		end
	elseif word == "ep" then
		local x, offset = Number(f[1], 1, 99), Number(f[2], 0, PAGE_MAX - 1)
		if #f == 3 and x and offset and f[3]:match("^[%w%+/=]+$") then
			return { x = x, offset = offset, data = f[3] }
		end
	elseif word == "en" then
		local n = Number(f[3], 1, N_MAX)
		if #f == 3 and Hex8(f[1]) and Hex8(f[2]) and n then
			return { acct = f[1], store = f[2], n = n }
		end
	elseif word == "ex" then
		local size = Number(f[1], 1, 99999)
		if #f == 2 and size then
			return { size = size }
		end
	elseif word == "ey" then
		local size, got = Number(f[1], 1, 99999), Number(f[2], 0, 99999)
		if #f == 2 and size and got then
			return { size = size, got = got }
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- State (memory only; a /reload starts afresh)
---------------------------------------------------------------------------

-- Friends who sent eh: gameAccountID -> { acct, store, key, proto, maxBytes, collect, relay, share,
-- early (takes pages early), verified (true: their account is the one Battle.net says; false: it
-- isn't; nil: not known yet), holdings = { [key] = list } (es: pages on a disk somewhere),
-- earlyHoldings = { [their key] = list } (ea: their own not on their disk yet) }
local peers = {}
local owedHello = {}   -- gameAccountID -> { at, answer }: my eh, once they're known to read it
local incoming = {}    -- [inHead..inTail] = { id, word, more }: messages for the tick
local inHead, inTail = 1, 0
-- pageId ("<acct>.<store>.<n>") -> { from, key, n, where, at, sent, early (from an ea), check (a
-- number I hold provisionally: its start is compared, see OnBegin) }: my requests
local inflight = {}
-- pageId -> { key, n, len, hash, t0, m, chunks, have, at, from = { [id] = true }, early (no holder
-- that sent it offered it as on a disk: it's kept provisional) }
local partials = {}
local bad = {}         -- pageId -> { [id] = true }: holders whose copy didn't match its hash (this session)
local checked = {}     -- key -> { [n] = true }: provisional pages a copy from a disk didn't match (this session)
local noRoom = {}      -- pageId -> when it was too big for my relay cache (not asked again for NO_ROOM_WAIT)
local silentAt = {}    -- gameAccountID -> when a request to them went without progress (asked last for a while)
local xmap = {}        -- sender -> { [x] = pageId }: their transfers
local serves = {}      -- requests waiting: { id, key, acct, store, n, offset }
local active = {}      -- serving: { id, key, acct, store, n, x, offset, len, page, begun, pending }
local out = {}         -- my other messages, waiting their turn: { id, message, kind, pageId }
local queued = {}      -- record -> true: my messages in Beacon's queue, not sent yet
local answersOut = {}  -- gameAccountID -> my answers to them waiting in out (Control)
local outstanding = 0
-- My summaries, per kind (es: what I hold, ea: my early pages, ed: what's safe): what I told each
-- friend, gameAccountID -> { at, full, gen, stamp, sent = { [mark] = ranges text } } (Due), and how
-- many of each kind wait in out for them (Control).
local sentEarly = {}
local tracks = { es = {}, ea = sentEarly, ed = {} }
local summariesOut = { es = {}, ea = {}, ed = {} }
-- The rate, in any second: when my last RATE messages went, and the last PEER_RATE to each friend
-- (oldest first), and how many wait in Beacon's queue for each.
local sentTimes, peerTimes, waitingFor = {}, {}, {}
local nextX, seq = 0, 0
local lastHouse
local pausedUntil, backoff, seenThrottle = 0, nil, nil
local inCombat = false
local lastFlags
local seenAt = -math.huge -- when the pages' cache was last wiped by the safety net (RECHECK)
local probe
local stats = { sent = 0, received = 0, pages = 0, served = 0, badHash = 0, rejected = 0 }

D.peers, D.inflight, D.partials, D.serves, D.active, D.out, D.stats = peers, inflight, partials, serves, active, out, stats
D.checked = checked

local function PageId(key, n)
	return key .. "." .. n
end

local function IsEchoes(message)
	return message:sub(1, 4) == "B2;e"
end

-- A friend's build reads B messages (their LefthyTools version, Beacon's V2).
local function Capable(bpeer)
	local compare = bpeer and LT.CompareVersions(bpeer.version, ECHOES_SINCE)
	return compare == 1 or compare == 0
end

-- (e: a collector of this build takes pages early, as provisional ones; not while its inbox is full:
-- it asks for nothing then, and authors keep their pages to 30 minutes. A change is a hello to
-- everyone (Hellos): the inbox fills only as pages come, and empties only by the exporter's receipt.
-- Older builds look for each letter on its own: an unknown one changes nothing for them.)
local function MyFlags(answer)
	return (M.db.collect and (S.InboxFull() and "c" or "ce") or "") .. (M.db.relay and "r" or "") .. "s" .. (answer and "a" or "")
end

-- Whether a friend takes my pages early: their account checked, they collect, their build keeps
-- such pages provisional (e).
local function TakesEarly(id)
	local peer = peers[id]
	return peer ~= nil and peer.verified == true and peer.collect == true and peer.early == true
end

-- Whether a friend's holdings (es) list my page n (a collector's: the ones of mine it holds
-- provisionally too, told only to me).
local function HoldsMine(id, n)
	local peer, key = peers[id], MyKey()
	local held = peer and key and peer.holdings[key]
	return held ~= nil and Ranges.Has(held, n)
end

local function HelloMessage(flags)
	local acct = E.data.acct or MyAccount()
	return Msg("eh", acct, E.data.store, PROTO, MAX_BYTES, flags)
end

-- An item into out, or left out (sent, or dropped): counted (step 1), or no longer (-1).
local function Tally(item, step)
	if item.answer then
		local n = (answersOut[item.id] or 0) + step
		answersOut[item.id] = n > 0 and n or nil
	end
	local waiting = summariesOut[item.kind]
	if waiting then
		local n = (waiting[item.id] or 0) + step
		waiting[item.id] = n > 0 and n or nil
	end
end

-- A message for one friend, after the ones already waiting (sent on the tick, see Send). answer:
-- one of my answers to what they sent (en, ey, a stop): at most ANSWERS_MAX of those wait for one
-- friend, so a friend asking for pages I don't have, again and again, can't pile them up (they come
-- in faster than they go). At most OUT_MAX wait in all: past that the last summary waiting makes
-- room, and what it told that friend is forgotten (it comes again, once there's room); with none, an
-- answer doesn't wait (they ask again); hellos and requests always do (a few a friend at most:
-- dropping one would leave a friend unknown, or a page asked for forever). marks: what a summary
-- tells of (Tell).
local function Control(id, message, kind, pageId, answer, marks)
	if answer and (answersOut[id] or 0) >= ANSWERS_MAX then
		return
	end
	if #out >= OUT_MAX and not summariesOut[kind] then
		local room = false
		for i = #out, 1, -1 do
			local item = out[i]
			if summariesOut[item.kind] then
				table.remove(out, i)
				Tally(item, -1)
				local s = tracks[item.kind][item.id]
				for _, mark in ipairs(s and item.marks or {}) do
					s.sent[mark], s.gen, s.told = nil, nil, nil
				end
				room = true
				break
			end
		end
		if not room and answer then
			return
		end
	end
	local item = { id = id, message = message, kind = kind, pageId = pageId, answer = answer, marks = marks }
	Tally(item, 1)
	out[#out + 1] = item
end

-- out's item i goes (sent, or dropped).
local function TakeOut(i)
	local item = table.remove(out, i)
	Tally(item, -1)
	return item
end

-- out's items for one friend go (of one kind, if given), in one pass; the others keep their order.
-- known: the friends whose items stay instead (the ones of everyone else go).
local function DropOut(id, kind, known)
	local j = 0
	for i = 1, #out do
		local item = out[i]
		out[i] = nil
		local drop
		if known then
			drop = not known[item.id]
		else
			drop = item.id == id and (not kind or item.kind == kind)
		end
		if drop then
			Tally(item, -1)
		else
			j = j + 1
			out[j] = item
		end
	end
end

---------------------------------------------------------------------------
-- Sending: my messages go through Beacon's low-priority queue, a few at a time
---------------------------------------------------------------------------

local function Done(serve)
	return serve.offset >= serve.len and serve.pending == 0
end

-- times: the last limit send times, oldest first; now one more.
local function Note(times, limit, now)
	times[#times + 1] = now
	if #times > limit then
		table.remove(times, 1)
	end
end

-- How many of times are within the last second.
local function Recent(times, now)
	local n = 0
	if not times then
		return 0
	end
	for _, t in ipairs(times) do
		if now - t < 1 then
			n = n + 1
		end
	end
	return n
end

-- One more message may go: counting the ones sent in the last second and the ones still waiting
-- (they go later, in order), never more than RATE in any second, nor PEER_RATE to one friend.
local function MayGo(id, now)
	return outstanding + Recent(sentTimes, now) < RATE and (waitingFor[id] or 0) + Recent(peerTimes[id], now) < PEER_RATE
end

local function Unwait(id)
	local n = (waitingFor[id] or 0) - 1
	waitingFor[id] = n > 0 and n or nil
end

local function RemoveServe(serve)
	for i = #active, 1, -1 do
		if active[i] == serve then
			table.remove(active, i)
		end
	end
end

local function Sent(record)
	if not queued[record] then
		return -- (withdrawn before: it went anyway, as far as Beacon is concerned)
	end
	queued[record] = nil
	outstanding = outstanding - 1
	Unwait(record.id)
	local now = GetTime()
	Note(sentTimes, RATE, now)
	peerTimes[record.id] = peerTimes[record.id] or {}
	Note(peerTimes[record.id], PEER_RATE, now)
	stats.sent = stats.sent + 1
	local serve = record.serve
	if serve then
		serve.pending = serve.pending - 1
		if record.kind == "ep" then
			stats.served = stats.served + #record.message
			if serve.mine then
				S.WentOut(serve.n, serve.page, serve.early) -- (out now, or only early: see E.Store)
			end
		elseif record.kind == "eb" and serve.mine and not serve.early and (TakesEarly(serve.id) or HoldsMine(serve.id, serve.n)) then
			-- (the start of my page from my disk, to a collector who takes pages early or holds that
			-- number of mine provisionally: its check, and the start's hash is all it needs to confirm
			-- its copy, before any part goes. Its holdings alone wouldn't do: a collector tells them
			-- only to friends who collect or relay.)
			S.WentOut(serve.n, serve.page, false, true)
		end
		if Done(serve) then
			RemoveServe(serve)
		end
	elseif record.kind == "eq" then
		local r = inflight[record.pageId]
		if r and r.from == record.id then
			r.sent, r.at = true, GetTime() -- (silence counts from now)
		end
	end
end

local function Enqueue(item)
	seq = seq + 1
	local record = { id = item.id, message = item.message, kind = item.kind, serve = item.serve, offset = item.offset,
		pageId = item.pageId, marks = item.marks, seq = seq }
	queued[record] = true
	outstanding = outstanding + 1
	waitingFor[item.id] = (waitingFor[item.id] or 0) + 1
	if record.serve then
		record.serve.pending = record.serve.pending + 1
	end
	ns.Beacon.QueueLow(item.id, item.message, function() Sent(record) end)
end

-- My messages still in Beacon's queue come back out (combat, a throttle, a friend gone): parts are
-- sent again from where they were, the others go back to the front of mine. only: one friend's.
local function Withdraw(only)
	local B = ns.Beacon
	local list, ids = {}, {}
	for record in pairs(queued) do
		if not only or record.id == only then
			list[#list + 1] = record
			ids[record.id] = true
		end
	end
	for id in pairs(ids) do
		B.DropLowFor(id, IsEchoes)
	end
	table.sort(list, function(x, y) return x.seq < y.seq end)
	local back = {} -- (to the front of out, in the order they were queued: put there at once)
	for i = 1, #list do
		local record = list[i]
		queued[record] = nil
		outstanding = outstanding - 1
		Unwait(record.id)
		local serve = record.serve
		if serve then
			serve.pending = serve.pending - 1
			if serve.stopped then
				if Done(serve) then
					RemoveServe(serve) -- (asked to stop, or replaced: nothing of it goes again)
				end
			elseif record.kind == "eb" then
				serve.begun = false
			elseif record.offset < serve.offset then
				serve.offset = record.offset
			end
		elseif record.id ~= only then
			local item = { id = record.id, message = record.message, kind = record.kind, pageId = record.pageId, marks = record.marks }
			Tally(item, 1)
			back[#back + 1] = item
		end
	end
	local k = #back
	if k > 0 then
		for i = #out, 1, -1 do
			out[i + k] = out[i]
		end
		for i = 1, k do
			out[i] = back[i]
		end
	end
end
D.Withdraw = Withdraw

-- The next message to send: mine waiting first (hellos, requests, answers), then my summaries and
-- the parts of the pages I serve by turns (summaries for many friends don't hold up a page), those
-- pages by turns too; only to a friend who may get one now (MayGo). nil: none.
-- (Asked every tick: when the rate is used up nothing is looked at, and each friend's rate once.
-- In a block of its own: Lua allows a file 200 locals.)
local NextMessage
do
local turn = 0
local may = {} -- gameAccountID -> whether they may get one now (this look)
local summaryTurn = true

local function NextPart(now)
	for _ = 1, #active do
		turn = turn % #active + 1
		local serve = active[turn]
		if MayGo(serve.id, now) and serve.offset < serve.len then
			if not serve.begun then
				serve.begun = true
				local page = serve.page
				return { id = serve.id, kind = "eb", serve = serve, offset = serve.offset,
					message = Msg("eb", serve.x, serve.acct, serve.store, serve.n, serve.len, page.h, page.t, page.m) }
			end
			local offset = serve.offset
			serve.offset = math.min(offset + PART, serve.len)
			return { id = serve.id, kind = "ep", serve = serve, offset = offset,
				message = "B2;ep;" .. serve.x .. ";" .. offset .. ";" .. serve.page.z:sub(offset + 1, offset + PART) }
		end
	end
	return nil
end

function NextMessage(now)
	if outstanding + Recent(sentTimes, now) >= RATE then
		return nil -- (nobody may get one now)
	end
	local B = ns.Beacon
	wipe(may)
	local gone, summary = false, nil
	for i = 1, #out do
		local item = out[i]
		local ok = may[item.id]
		if ok == nil then
			ok = B.peers[item.id] ~= nil and MayGo(item.id, now)
			may[item.id] = ok
			gone = gone or B.peers[item.id] == nil
		end
		if ok and summariesOut[item.kind] then
			summary = summary or i
		elseif ok then
			if gone then
				break -- (theirs go first: then this one)
			end
			return TakeOut(i)
		end
	end
	if gone then
		DropOut(nil, nil, B.peers) -- (gone: theirs go, all at once)
		return NextMessage(now)
	end
	if summary and summaryTurn then
		summaryTurn = false
		return TakeOut(summary)
	end
	local part = NextPart(now)
	if part then
		summaryTurn = true
		return part
	end
	return summary and TakeOut(summary) or nil
end
end

-- Whether a friend collects (their requests go first: pages go to the collector, a relay only
-- carries them for a while).
local function Collects(id)
	return peers[id] ~= nil and peers[id].collect == true
end

-- The next request to serve: the first one of a friend who collects, else the first.
local function NextServe()
	for i, s in ipairs(serves) do
		if Collects(s.id) then
			return table.remove(serves, i)
		end
	end
	return table.remove(serves, 1)
end

-- Requests waiting become serves while fewer than SERVING run. My own page not on my disk yet only
-- to a friend who takes it early (early: it's such a serve); anyone else gets en, as for a page I
-- don't have.
local function StartServes()
	while #active < SERVING and serves[1] do
		local s = NextServe()
		local online = ns.Beacon.peers[s.id] ~= nil
		local page = online and Get(s.key, s.n)
		local early = false
		if online and not page and s.key == MyKey() and TakesEarly(s.id) then
			page = Get(s.key, s.n, true)
			early = page ~= nil
		end
		if page and s.offset < #page.z then
			nextX = nextX % 99 + 1
			active[#active + 1] = { id = s.id, key = s.key, acct = s.acct, store = s.store, n = s.n, x = nextX,
				offset = s.offset, len = #page.z, page = page, begun = false, pending = 0, mine = s.key == MyKey(), early = early }
		elseif online and not page then
			Control(s.id, Msg("en", s.acct, s.store, s.n), "en", nil, true)
		end
	end
end

-- A page of mine I serve that moved to a new number (E.Store: friends hold another page with its
-- number) or went, or one not on my disk to a friend who no longer takes pages early: nothing more
-- of it goes (what of it waits in Beacon's queue still does).
local function DropMoved()
	for i = #active, 1, -1 do
		local s = active[i]
		if s.mine and not s.stopped and (E.data.mine[s.n] ~= s.page or (s.early and not TakesEarly(s.id))) then
			s.offset, s.stopped = s.len, true
			if Done(s) then
				table.remove(active, i)
			end
		end
	end
end

local function Send(now)
	if LT.InCombat() then
		if not inCombat then
			inCombat = true
			Withdraw() -- (nothing in combat: what still waits in Beacon's queue too)
		end
		return
	end
	inCombat = false
	if now < pausedUntil then
		return
	end
	DropMoved()
	StartServes()
	local B = ns.Beacon
	-- Only when nothing but mine waits in Beacon's queues: everything else goes first. One a tick at
	-- most: Beacon sends what it holds on its next tick, so more at once would go in the same moment.
	if outstanding < OUTSTANDING and B.Waiting() <= outstanding then
		local item = NextMessage(now)
		if item then
			Enqueue(item)
		end
	end
end

-- A fight starts: what of mine still waits in Beacon's queue comes back out at once (the tick
-- would be a moment late). Only tables: no frames touched.
E.On("PLAYER_REGEN_DISABLED", function()
	if next(queued) then
		Withdraw()
	end
	inCombat = true
end)

-- Silent until (GetTime()), and for how long the last silence was (nil: none yet). (Tests, status.)
function D.Paused()
	return pausedUntil, backoff
end

-- My messages waiting in Beacon's queue. (Tests.)
function D.Outstanding()
	return outstanding
end

-- The server said slow down (a throttle or lockdown) at: silent for a while, twice as long after the
-- next one, back to the first after a calm BACKOFF_CALM. (One during the silence doesn't add to it.)
local function Backoff(at)
	if at >= pausedUntil then
		local calm = pausedUntil == 0 or at - pausedUntil >= BACKOFF_CALM
		backoff = (backoff and not calm) and math.min(backoff * 2, BACKOFF_MAX) or BACKOFF_FIRST
		pausedUntil = at + backoff
	end
	Withdraw()
end

-- Beacon was told to slow down (it says when).
local function CheckThrottle()
	local at = ns.Beacon.throttledAt
	if at and at ~= seenThrottle then
		seenThrottle = at
		Backoff(at)
	end
end

---------------------------------------------------------------------------
-- Friends: hellos, what they hold, what's safe
---------------------------------------------------------------------------

local function ResetPeer(id)
	tracks.es[id], tracks.ea[id], tracks.ed[id] = nil, nil, nil
end

-- Requests to one holder are given up (another may answer, or the same again later), also the ones
-- still waiting to go.
local function Release(id)
	for pageId, r in pairs(inflight) do
		if r.from == id then
			inflight[pageId] = nil
		end
	end
	DropOut(id, "eq")
end

-- Their requests: no more serving them.
local function StopServing(id)
	for i = #serves, 1, -1 do
		if serves[i].id == id then
			table.remove(serves, i)
		end
	end
	for i = #active, 1, -1 do
		if active[i].id == id then
			table.remove(active, i)
		end
	end
end

-- A verified friend's store gets their character's first name, as Battle.net says it (E.Store keeps
-- it for the status: a collector's lines per friend).
local function Named(id, peer)
	local bpeer = ns.Beacon.peers[id]
	E.Store.Named(peer.acct, peer.store, bpeer and LT.Names.First(bpeer.name))
end

local function Verify(id, peer, now)
	local acct = PeerAccount(id, now)
	if acct then
		peer.verified = acct == peer.acct
		if peer.verified then
			Named(id, peer)
		else
			stats.rejected = stats.rejected + 1
		end
	end
end

local function OnHello(id, msg, now)
	local peer = peers[id]
	local key = msg.acct .. "." .. msg.store
	if not peer or peer.key ~= key then
		peer = { holdings = {}, earlyHoldings = {} }
		peers[id] = peer
	end
	if msg.early and not peer.early then
		sentEarly[id] = nil -- (they take pages early now: all of mine not on disk go to them at once)
	end
	peer.acct, peer.store, peer.key = msg.acct, msg.store, key
	peer.proto, peer.maxBytes = msg.proto, msg.maxBytes
	peer.collect, peer.relay, peer.share, peer.early = msg.collect, msg.relay, msg.share, msg.early
	if not msg.answer then
		-- They (re)started: they need mine, and everything I hold again; theirs comes again (the
		-- pages they offered early too: a crash may have lost them). What they asked of me before is
		-- gone with their session (they ask again what they still need).
		peer.holdings, peer.earlyHoldings = {}, {}
		ResetPeer(id)
		Release(id)
		StopServing(id)
		owedHello[id] = owedHello[id] or { at = now, answer = true }
	end
	if not (peer.collect or peer.relay or peer.share) then
		peer.holdings, peer.earlyHoldings = {}, {} -- (switched off)
		Release(id)
		StopServing(id)
	end
	if peer.verified == nil then
		Verify(id, peer, now)
	elseif peer.verified then
		Named(id, peer) -- (Battle.net may not have said their name when they were verified)
	end
end

-- My summaries: what I hold (Summary), my early pages (EarlySummary), what's safe (SafeSummary).
-- (In a block of their own: Lua allows a file 200 locals.)
local Summary, EarlySummary, SafeSummary
do

-- What I told one friend of kind (es, ea or ed), if it's time to tell them again (at most every
-- SUMMARY_GAP; what they heard is forgotten every FULL_OFFER, what's safe every FULL_SAFE: then all
-- of it again); nil if not. Looked at again only once something changed since (Changed:
-- summaryGen), or what stamp says about them (their key) did: else nothing would be told anyway.
-- While some of that kind still wait for them in out, what changed goes after those (out doesn't
-- grow with summaries that can't go yet); all of it goes instead of them.
local function Due(kind, id, now, stamp)
	local track = tracks[kind]
	local s = track[id]
	if not s then
		s = { at = -math.huge, full = -math.huge, sent = {} } -- (all of it, now)
		track[id] = s
	end
	if now - s.at < SUMMARY_GAP then
		return nil
	end
	local every = kind == "ed" and FULL_SAFE or FULL_OFFER
	if now - s.full >= every then
		-- (the next one up to a quarter sooner, by chance: friends met together don't stay in step)
		s.full = now - D.Random(0, every / 4)
		wipe(s.sent)
		s.told = nil
		if summariesOut[kind][id] then
			DropOut(id, kind)
		end
	elseif (s.gen == summaryGen and s.stamp == stamp) or summariesOut[kind][id] then
		return nil
	end
	s.gen, s.stamp = summaryGen, stamp
	return s
end

-- What my summaries say, worked out once a change for every friend (Told): per message head, its
-- items ("<key>:<ranges>", a long list in pieces) sorted, with each item's mark (what a friend
-- hears of: a key, for ed the collector and the key), each mark's text (ranges), list and items. A
-- change that leaves a kind's summary as it was keeps it (last): friends told it already are passed
-- over; what of it didn't change is taken over, not worked out again.
local told, toldGen, last = {}, nil, {}

-- offer under head into t (marks: prefix .. key): { [key] = list }, or the ranges text as kept (read
-- only when it changed since before, the summary built last).
local function AddOffer(t, head, offer, prefix, before)
	local h = { head = head, prefix = prefix or "", keys = {} }
	for key, value in pairs(offer) do
		local mark = h.prefix .. key
		local text, list, items
		if type(value) == "string" then
			t.raws[mark] = value
			if before and before.raws[mark] == value then
				text, list, items = before.texts[mark], before.lists[mark], before.items[mark]
			else
				list = Stored(value)
			end
		else
			list = value
			text = Ranges.Format(list)
			items = before and before.texts[mark] == text and before.items[mark] or nil
		end
		if not items then
			text, items = text or Ranges.Format(list), {}
			WriteItems(key, list, MAX_BYTES - #head, items)
		end
		t.texts[mark], t.lists[mark], t.items[mark] = text, list, items
		h.keys[#h.keys + 1] = mark
	end
	t.heads[#t.heads + 1] = h
end

-- kind's summary as it is now ("es": what I hold, "ea": my early pages, "ed": what's safe), the same
-- for every friend (to the author, what I hold of theirs provisionally is added: Summary).
local function Told(kind)
	if toldGen ~= summaryGen then
		wipe(told)
		toldGen = summaryGen
	end
	local t = told[kind]
	if t then
		return t
	end
	local before = last[kind]
	t = { texts = {}, lists = {}, items = {}, raws = {}, heads = {}, extras = {} }
	if kind == "es" then
		AddOffer(t, "B2;es;", Holdings(), nil, before)
	elseif kind == "ea" then
		local key = MyKey()
		AddOffer(t, "B2;ea;", key and { [key] = Have("early", key) } or {}, nil, before)
	else
		-- (What I keep of what's safe, checked once here: a key that isn't one, or an entry of the
		-- wrong type, stays out.)
		local byCollector, collectors = {}, {}
		for key, entry in pairs(E.data.safe) do
			for collector, text in pairs(WireKey(key) and type(entry) == "table" and entry or {}) do
				if WireKey(collector) and type(text) == "string" then
					if not byCollector[collector] then
						byCollector[collector] = {}
						collectors[#collectors + 1] = collector
					end
					byCollector[collector][key] = text
				end
			end
		end
		table.sort(collectors)
		for _, collector in ipairs(collectors) do
			local cAcct, cStore = Split(collector)
			AddOffer(t, "B2;ed;" .. cAcct .. ";" .. cStore .. ";", byCollector[collector], collector .. ">", before)
		end
	end
	local same = before ~= nil
	for mark, text in pairs(same and t.texts or {}) do
		same = same and before.texts[mark] == text
	end
	for mark in pairs(same and before.texts or {}) do
		same = same and t.texts[mark] ~= nil
	end
	if same then
		wipe(before.extras) -- (what I hold provisionally may have changed: worked out again)
		t = before
	else
		-- (each head's items sorted, with their marks)
		for _, h in ipairs(t.heads) do
			local markOf = {}
			h.items, h.marks = {}, {}
			for _, mark in ipairs(h.keys) do
				for _, item in ipairs(t.items[mark]) do
					h.items[#h.items + 1] = item
					markOf[item] = mark
				end
			end
			table.sort(h.items)
			for i, item in ipairs(h.items) do
				h.marks[i] = markOf[item]
			end
		end
	end
	told[kind], last[kind] = t, t
	return t
end

-- t (Told) to one friend as kind's messages: what changed since they last heard it (s, from Due).
-- extra: { mark, text, items } told instead of t's for that mark (only "es", one head). True if
-- something went.
local function Tell(id, s, kind, t, now, extra)
	if s.told == t and not extra then
		return false -- (all of it as they heard it last)
	end
	s.told = not extra and t or nil
	local changed
	for mark, text in pairs(t.texts) do
		if extra and mark == extra.mark then
			text = extra.text
		end
		if s.sent[mark] ~= text then
			s.sent[mark] = text
			changed = changed or {}
			changed[mark] = true
		end
	end
	if extra and not t.texts[extra.mark] and s.sent[extra.mark] ~= extra.text then
		s.sent[extra.mark] = extra.text
		changed = changed or {}
		changed[extra.mark] = true
	end
	if not changed then
		return false
	end
	local any = false
	for _, h in ipairs(t.heads) do
		local every = not extra
		for i = 1, every and #h.marks or 0 do
			every = every and changed[h.marks[i]] == true
		end
		local messages, marks
		if every then
			-- (all of it: the same messages for everyone, made once)
			if not h.full then
				h.full, h.fullMarks = Pack(h.head, h.items, h.prefix)
			end
			messages, marks = h.full, h.fullMarks
		else
			local items = {}
			for i, item in ipairs(h.items) do
				local mark = h.marks[i]
				if changed[mark] and not (extra and mark == extra.mark) then
					items[#items + 1] = item
				end
			end
			if extra and changed[extra.mark] then
				for _, item in ipairs(extra.items) do
					items[#items + 1] = item
				end
				table.sort(items)
			end
			messages, marks = Pack(h.head, items, h.prefix)
		end
		for i, message in ipairs(messages) do
			Control(id, message, kind, nil, nil, marks[i])
			any = true
		end
	end
	if any then
		s.at = now
	end
	return any
end

-- What I hold, to one friend who collects or relays: only what grew since they last heard it
-- (everything the first time, and again every FULL_OFFER), at most every SUMMARY_GAP.
function Summary(id, peer, now)
	local s = Due("es", id, now, peer.key)
	if not s then
		return false
	end
	-- (Their own pages too: the author learns who holds which of its pages, and a page of theirs
	-- that never went out but that I hold under its number is another page with that number. To
	-- their author only, while I collect, the ones I hold provisionally too (they came early): a
	-- page that a crash lost has its number, so the author's next pages close above it. Nobody else
	-- hears of those: no relay leaves a page alone for them, no collector fetches one; and what a
	-- friend who doesn't collect holds is only ever from a disk, see OnHoldings.)
	-- (Worked out once a change for each such author, and only while I collect.)
	local t = Told("es")
	local theirs = M.db.collect and HeldIn("provisional")[peer.key]
	local extra = theirs and t.extras[peer.key]
	if theirs and not extra then
		local list = t.lists[peer.key] and Ranges.Union(t.lists[peer.key], theirs) or theirs
		extra = { mark = peer.key, text = Ranges.Format(list), items = {} }
		WriteItems(peer.key, list, MAX_BYTES - #t.heads[1].head, extra.items)
		t.extras[peer.key] = extra
	end
	return Tell(id, s, "es", t, now, extra)
end

-- My own pages not on my disk yet, to one friend who takes them early (TakesEarly), the same way.
function EarlySummary(id, now)
	local s = MyKey() and Due("ea", id, now)
	if not s then
		return false
	end
	return Tell(id, s, "ea", Told("ea"), now)
end

-- What collectors hold safely (theirs passed on, mine if I collect), to one friend, the same way.
function SafeSummary(id, now)
	local s = Due("ed", id, now)
	if not s then
		return false
	end
	return Tell(id, s, "ed", Told("ed"), now)
end
end

---------------------------------------------------------------------------
-- Pulling: asking holders for the pages I want
---------------------------------------------------------------------------

local function InFlight()
	return Count(inflight)
end

-- The pages that lists cover at least times over (each list sorted, without overlaps): a sweep
-- over their ends.
local function CoveredBy(lists, times)
	local points = {}
	for _, list in ipairs(lists) do
		for _, r in ipairs(list) do
			points[#points + 1] = { r[1], 1 }
			points[#points + 1] = { r[2] + 1, -1 }
		end
	end
	table.sort(points, function(x, y) return x[1] < y[1] end)
	local out, count, i = {}, 0, 1
	while points[i] do
		local at = points[i][1]
		while points[i] and points[i][1] == at do
			count = count + points[i][2]
			i = i + 1
		end
		if count >= times and points[i] then
			out[#out + 1] = { at, points[i][1] - 1 }
		end
	end
	return Ranges.Normal(out)
end

-- The provisional pages of key a copy from a disk didn't match this session, still in the inbox (the
-- receipt may take one meanwhile: then it's checked again).
local function Checked(key)
	local list = {}
	for n in pairs(checked[key] or {}) do
		local _, where = Provisional(key, n)
		if where == "inbox" then
			list[#list + 1] = { n, n }
		end
	end
	return Ranges.Normal(list)
end

-- What of key I don't want, worked out once per Pull (memo). Collecting: what's in my inbox,
-- exported, or in my relay cache (it moves over, MoveOne); offered early (early): also what I hold
-- provisionally (a page's number taken: nothing early comes into it); offered as on a disk: not what
-- I hold provisionally (a check: does the copy match?) unless it was checked this session and didn't.
-- Relaying: what's in my cache, safe at a collector, held by an online friend who collects (as good as
-- safe: it will be at their next session), or by COPIES online friends besides the author.
local function Unwanted(key, collecting, memo, early)
	local id = (early and "early>" or "") .. key
	if memo[id] then
		return memo[id]
	end
	local list
	if collecting then
		list = Ranges.Union(Ranges.Union(Have("inbox", key), Exported(key)), Have("carry", key))
		list = Ranges.Union(list, early and Have("provisional", key) or Checked(key))
	else
		local covered, copies = {}, {}
		for _, peer in pairs(peers) do
			local held = peer.verified and peer.holdings[key]
			if held and peer.collect then
				covered = Ranges.Union(covered, held)
			elseif held and peer.key ~= key then
				copies[#copies + 1] = held
			end
		end
		list = Ranges.Union(Ranges.Union(Have("carry", key), SafeOf(key)), Ranges.Union(covered, CoveredBy(copies, COPIES)))
	end
	memo[id] = list
	return list
end

-- A page of key I want from holder id, and where it goes; nil: none. What I don't want is taken
-- out as ranges, so the pages looked at one by one are only the ones asked for already, or that
-- this holder's copy or my room failed (a few). A collector takes the oldest first; a relay starts
-- at a random one of them and goes on from there (around to the first): many relays asking an
-- author at once, before what they hold has spread, each fetch another page, not all the first.
-- early: offered early (ea; only a collector asks for those).
local function Wanted(id, key, offered, now, collecting, relaying, memo, early)
	local acct = key:sub(1, 8)
	if key == MyKey() or not Accepted(acct, now) then
		return nil
	end
	local where
	if collecting then
		where = "inbox"
	elseif relaying and acct ~= MyAccount() and Fits(key, 1) then -- (the size comes with the page: checked then)
		where = "carry"
	else
		return nil
	end
	local free, count = Ranges.Minus(offered, Unwanted(key, collecting, memo, early)), 0
	for _, r in ipairs(free) do
		count = count + r[2] - r[1] + 1
	end
	local start = (where == "carry" and count > 1) and D.Random(0, count - 1) or 0
	local looked = 0
	for pass = 1, 2 do -- (from the start to the end, then from the first up to the start)
		local before = 0 -- (pages of free before r)
		for _, r in ipairs(free) do
			local size = r[2] - r[1] + 1
			local from, to = r[1], r[2]
			if pass == 1 then
				from = r[1] + math.max(0, start - before)
			else
				to = math.min(r[2], r[1] + start - before - 1)
			end
			for n = from, to do
				local pageId = PageId(key, n)
				if not inflight[pageId] and not (bad[pageId] and bad[pageId][id]) and not (noRoom[pageId] and now - noRoom[pageId] < NO_ROOM_WAIT) then
					return n, where
				end
				looked = looked + 1
				if looked >= 50 then
					return nil -- (enough for this round: a holder whose copies failed again and again)
				end
			end
			before = before + size
		end
	end
	return nil
end

-- Collecting: a page of my relay cache moves to the inbox, one a second (E.Store checks its hash
-- again). Exported, from before the launch or broken: it just goes.
local function MoveOne(now)
	for key, pages in pairs(E.data.carry) do
		if Accepted(key:sub(1, 8), now) then
			for n, page in pairs(pages) do
				if S.Shareable(page) then
					Move(key, n, page)
					return
				end
			end
		end
	end
end

D.Random = math.random -- (a relay's start among the pages it wants; tests make it the first)

local function SortedKeys(t)
	local list = {}
	for k in pairs(t) do
		list[#list + 1] = k
	end
	table.sort(list)
	return list
end

-- At most one open request per holder, IN_FLIGHT pages at once; a page I got part of goes on from there.
local function Pull(now)
	local collecting = M.db.collect and not S.InboxFull()
	local relaying = M.db.relay and not M.db.collect -- (a collector is where pages go: it doesn't relay them)
	if collecting then
		MoveOne(now)
	end
	if not (collecting or relaying) or InFlight() >= IN_FLIGHT then
		return
	end
	local busy, memo = {}, {}
	for _, r in pairs(inflight) do
		busy[r.from] = true
	end
	-- Holders whose request went silent lately come last.
	local order, later = {}, {}
	for _, id in ipairs(SortedKeys(peers)) do
		local list = silentAt[id] and now - silentAt[id] < 2 * SILENCE and later or order
		list[#list + 1] = id
	end
	for _, id in ipairs(later) do
		order[#order + 1] = id
	end
	for _, id in ipairs(order) do
		local peer = peers[id]
		if peer.verified and not busy[id] and ns.Beacon.peers[id] and (peer.share or peer.relay or peer.collect) then
			local key, n, where, early
			for _, k in ipairs(SortedKeys(peer.holdings)) do
				n, where = Wanted(id, k, peer.holdings[k], now, collecting, relaying, memo)
				if n then
					key = k
					break
				end
			end
			-- Then their own pages not on their disk yet (a collector keeps them provisional).
			local offered = collecting and not n and peer.earlyHoldings[peer.key]
			if offered then
				n, where = Wanted(id, peer.key, offered, now, collecting, false, memo, true)
				key, early = peer.key, true
			end
			if n then
				local pageId = PageId(key, n)
				local part = partials[pageId]
				-- (A number I hold provisionally, offered as on a disk: a check, OnBegin.)
				inflight[pageId] = { from = id, key = key, n = n, where = where, at = now, sent = false, early = early,
					check = not early and Provisional(key, n) ~= nil }
				Control(id, Msg("eq", key:sub(1, 8), key:sub(10), n, part and part.have or 0), "eq", pageId)
				if InFlight() >= IN_FLIGHT then
					return
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Receiving: the tick handles what Beacon handed over
---------------------------------------------------------------------------

-- Keeps unfinished pages within PARTIALS_MAX: the ones without progress for longest go.
local function TrimPartials(now)
	local total, oldest, oldestId = 0, nil, nil
	for pageId, part in pairs(partials) do
		if now - part.at > PARTIAL_AGE then
			partials[pageId] = nil
		else
			total = total + part.have
			if not oldest or part.at < oldest then
				oldest, oldestId = part.at, pageId
			end
		end
	end
	if total > PARTIALS_MAX and oldestId then
		partials[oldestId] = nil
	end
end

-- A page whole: E.Store keeps it (into the inbox collecting, else relaying the cache) and checks it
-- (its hash, size and start). Not the page it said: whoever sent parts of it isn't asked for it again.
-- One that came early (no holder offered it as on a disk, or I asked for it from an ea) goes into the
-- inbox as provisional, never into a relay's cache (relays only ever have pages from a disk):
-- collecting switched off meanwhile, it goes (its author still has it).
local function Complete(pageId, part)
	local r = inflight[pageId]
	local early = part.early or (r ~= nil and r.early == true)
	partials[pageId], inflight[pageId] = nil, nil
	local where
	if M.db.collect then
		where = "inbox"
	elseif M.db.relay and not early and part.key:sub(1, 8) ~= MyAccount() then
		where = "carry"
	else
		return
	end
	local ok, why = Put(part.key, part.n, { t = part.t0, h = part.hash, m = part.m, z = table.concat(part.chunks) }, where, early)
	if ok then
		stats.pages = stats.pages + (why == "have" and 0 or 1)
	elseif why == "full" then
		noRoom[pageId] = GetTime()
	elseif why ~= "exported" and why ~= "safe" then
		bad[pageId] = bad[pageId] or {}
		for id in pairs(part.from) do
			bad[pageId][id] = true
		end
		if why == "hash" then
			stats.badHash = stats.badHash + 1
		else
			stats.rejected = stats.rejected + 1
		end
	end
end

-- A page's start. Its transfer id is that page's now (parts with it never go into another page),
-- and one I don't take is stopped: asked from its end, the sender sends no more of it.
--
-- A copy is from a disk when its holder offered that number in its holdings (es: my own on my disk,
-- relayed, a collector's not provisional); one that isn't came early (its author's, ea): the page is
-- kept provisional (part.early).
--
-- A number I hold provisionally (it came early): my request was a check, and its start says the
-- hash of the copy from a disk. The same: confirmed (E.Store.Confirm), nothing more of it comes.
-- Another, while the provisional page is in my inbox: another page with that number; it's stopped
-- and not asked for again this session: the inbox has no room for it until the receipt took the
-- provisional one (nobody drops it meanwhile: it isn't safe here). Another, the receipt took the
-- provisional one: fetched like any page, into the inbox. A start for such a number that isn't the
-- answer to my check is stopped.
local function OnBegin(id, msg, now)
	local key = msg.acct .. "." .. msg.store
	local pageId = PageId(key, msg.n)
	local r, part = inflight[pageId], partials[pageId]
	xmap[id] = xmap[id] or {}
	xmap[id][msg.x] = nil
	local stop = Msg("eq", msg.acct, msg.store, msg.n, msg.len)
	local offered = peers[id].holdings[key]
	local fromDisk = offered ~= nil and Ranges.Has(offered, msg.n)
	local hash, pending = Provisional(key, msg.n)
	if pending then
		local check = r ~= nil and r.from == id and fromDisk
		if check and hash == msg.hash then
			local acct, store = Split(key)
			S.Confirm(acct, store, msg.n, msg.hash)
			Changed()
		elseif check and pending == "inbox" then
			checked[key] = checked[key] or {}
			checked[key][msg.n] = true
		end
		if not check or hash == msg.hash or pending == "inbox" then
			if r and r.from == id then
				inflight[pageId], partials[pageId] = nil, nil
			end
			Control(id, stop, "eq", nil, true)
			return
		end
		r.check = false -- (the receipt took the provisional one: this one is fetched)
	end
	if not (r or part) or Get(key, msg.n) then
		Control(id, stop, "eq", nil, true) -- (not asked for, or got already)
		return
	end
	if not Accepted(msg.acct, now) or key == MyKey() then
		bad[pageId] = bad[pageId] or {}
		bad[pageId][id] = true
		stats.rejected = stats.rejected + 1
		if r and r.from == id then
			inflight[pageId] = nil
		end
		Control(id, stop, "eq", nil, true)
		return
	end
	if part and (part.len ~= msg.len or part.hash ~= msg.hash or part.t0 ~= msg.t0 or part.m ~= msg.m) then
		part = nil -- (another page than the bytes so far: from the start)
	end
	if not part then
		part = { key = key, n = msg.n, len = msg.len, hash = msg.hash, t0 = msg.t0, m = msg.m, chunks = {}, have = 0, from = {},
			early = not fromDisk }
		partials[pageId] = part
	elseif fromDisk then
		part.early = false -- (this very page, a holder has it from a disk)
	end
	if part.early and not M.db.collect then
		partials[pageId] = nil -- (an early page goes only into a collector's inbox)
		if r and r.from == id then
			inflight[pageId] = nil
		end
		Control(id, stop, "eq", nil, true)
		return
	end
	part.at = now
	xmap[id][msg.x] = pageId
	if r and r.from == id then
		r.at = now
	end
	-- A relay with no room for it: the holder is asked for nothing more of it (from its end).
	local where = r and r.where or (M.db.collect and "inbox" or "carry")
	if where == "carry" and not M.db.collect and not Fits(key, msg.len) then
		noRoom[pageId] = now
		partials[pageId], inflight[pageId] = nil, nil
		Control(id, stop, "eq", nil, true)
	end
end

local function OnPart(id, msg, now)
	local pageId = xmap[id] and xmap[id][msg.x]
	local part = pageId and partials[pageId]
	if not part or msg.offset ~= part.have then
		return -- (unknown, or not the next bytes: what's missing is asked for again after SILENCE)
	end
	if part.have + #msg.data > part.len then
		partials[pageId] = nil -- (longer than it said: broken)
		return
	end
	part.chunks[#part.chunks + 1] = msg.data
	part.have = part.have + #msg.data
	part.at = now
	part.from[id] = true
	silentAt[id] = nil -- (they answer again)
	local r = inflight[pageId]
	if r then
		r.at = now
	end
	if part.have == part.len then
		Complete(pageId, part)
	end
end

-- A serve ends: nothing more of it goes (its parts already in Beacon's queue still do).
local function Finish(s, i)
	s.offset, s.stopped = s.len, true
	if Done(s) then
		table.remove(active, i)
	end
end

-- Their request. A friend asks one holder for one page at a time, so a new request from them
-- replaces theirs, being served or waiting: in its place in the line (asked again after SILENCE,
-- a page keeps its turn, and nobody holds more than one place); a page they're being served
-- already goes on from the offset asked. Offset = its length: that page stops (only that one).
local function OnRequest(id, msg)
	local key = msg.acct .. "." .. msg.store
	local page = Get(key, msg.n, TakesEarly(id)) -- (mine not on my disk yet: only to a collector who takes it early)
	local stop = page ~= nil and msg.offset >= #page.z
	local turn -- (where theirs was waiting)
	for i = #active, 1, -1 do
		local s = active[i]
		if s.id == id and not s.stopped then
			local same = s.key == key and s.n == msg.n
			if same and page and not stop then
				s.offset, s.begun = msg.offset, false
				return
			elseif same or not stop then
				Finish(s, i)
				turn = 1 -- (they were being served: the new one is next)
			end
		end
	end
	for i = #serves, 1, -1 do
		local s = serves[i]
		if s.id == id and (not stop or (s.key == key and s.n == msg.n)) then
			table.remove(serves, i)
			turn = math.min(turn or i, i)
		end
	end
	if not page then
		Control(id, Msg("en", msg.acct, msg.store, msg.n), "en", nil, true)
		return
	end
	if not stop and not turn and #serves >= SERVE_QUEUE and Collects(id) then
		-- The line is full: a collector's request takes the place of the last relay's (they ask again).
		for i = #serves, 1, -1 do
			if not Collects(serves[i].id) then
				table.remove(serves, i)
				break
			end
		end
	end
	if not stop and (turn or #serves < SERVE_QUEUE) then
		table.insert(serves, math.min(turn or #serves + 1, #serves + 1),
			{ id = id, key = key, acct = msg.acct, store = msg.store, n = msg.n, offset = msg.offset })
		StartServes() -- (SERVING of them at once, collectors first; SERVE_QUEUE more waiting)
	end
end

local function OnNone(id, msg)
	local key = msg.acct .. "." .. msg.store
	local peer = peers[id]
	for _, held in ipairs(peer and { peer.holdings, peer.earlyHoldings } or {}) do
		if held[key] then
			held[key] = Ranges.Minus(held[key], { { msg.n, msg.n } })
		end
	end
	local pageId = PageId(key, msg.n)
	local r = inflight[pageId]
	if r and r.from == id then
		inflight[pageId] = nil
	end
end

local function OnHoldings(id, msg, now)
	local peer = peers[id]
	for _, item in ipairs(msg.items) do
		local key, acct, list = item[1], item[2], item[3]
		if Accepted(acct, now) and (peer.holdings[key] or Count(peer.holdings) < 200) then
			S.Mentioned(acct, key:sub(10)) -- (pages of it are around: what collectors hold of it still counts)
			local merged = peer.holdings[key] and Ranges.Union(peer.holdings[key], list) or list
			if #merged <= RANGES_MAX then
				peer.holdings[key] = merged
			end
			if key == MyKey() then
				if peer.relay and not peer.collect then
					-- (a relay holds these of mine: over the cap they go first. Not a collector's: it
					-- doesn't relay, and pages of mine it holds provisionally are among them)
					Carried(key, list)
				end
				-- (a page of mine they hold that never went out is another page with that number;
				-- a collector's provisional ones too: a crash may have lost the page it holds. One
				-- that went only early too, if they don't collect: they hold only pages from a disk)
				S.Elsewhere(acct, key:sub(10), list, not peer.collect)
			end
		end
	end
end

-- Their own pages not on their disk yet (ea): taken only while I collect (as provisional pages),
-- only of their own key; kept like holdings, until they restart or say en.
local function OnEarly(id, msg, now)
	local peer = peers[id]
	if not M.db.collect then
		return
	end
	for _, item in ipairs(msg.items) do
		local key, acct, list = item[1], item[2], item[3]
		if key == peer.key and Accepted(acct, now) then
			S.Mentioned(acct, key:sub(10))
			local merged = peer.earlyHoldings[key] and Ranges.Union(peer.earlyHoldings[key], list) or list
			if #merged <= RANGES_MAX then
				peer.earlyHoldings[key] = merged
			end
		end
	end
end

local function OnSafe(id, msg, now)
	-- Only collectors I'd take pages from myself (a friend's account or mine), about pages I take.
	if not Accepted(msg.acct, now) then
		return
	end
	local collector = msg.acct .. "." .. msg.store
	for _, item in ipairs(msg.items) do
		if Accepted(item[2], now) then
			Safe(item[1], collector, item[3], true)
			if collector == peers[id].key then
				S.Mentioned(item[2], item[1]:sub(10)) -- (the collector's own summary; passed on ones don't count)
			end
		end
	end
end

-- The probe's answer to them: how much of it arrived.
local function OnProbe(id, size, got)
	Control(id, Msg("ey", size, got), "ey", nil, true)
end

local function OnProbeAnswer(id, msg)
	if probe and probe.id == id and probe.results[msg.size] then
		probe.results[msg.size].got = msg.got
	end
end

local function Handle(id, word, more, now)
	if not ns.Beacon.peers[id] then
		return -- (gone in the meantime)
	end
	local msg = D.Read(word, more)
	if not msg then
		return
	end
	stats.received = stats.received + 1
	if word == "eh" then
		OnHello(id, msg, now)
		return
	end
	local peer = peers[id]
	if not (peer and peer.verified) then
		return -- (only friends who said hello, with the account they are)
	end
	if word == "es" then
		OnHoldings(id, msg, now)
	elseif word == "ea" then
		OnEarly(id, msg, now)
	elseif word == "ed" then
		OnSafe(id, msg, now)
	elseif word == "eq" then
		OnRequest(id, msg)
	elseif word == "eb" then
		OnBegin(id, msg, now)
	elseif word == "ep" then
		OnPart(id, msg, now)
	elseif word == "en" then
		OnNone(id, msg)
	elseif word == "ex" then
		OnProbe(id, msg.size, #more + 6)
	elseif word == "ey" then
		OnProbeAnswer(id, msg)
	end
end

local function HandleIncoming(now)
	local handled = 0
	while inHead <= inTail and handled < INCOMING_PER_TICK do
		local item = incoming[inHead]
		incoming[inHead] = nil
		inHead = inHead + 1
		handled = handled + 1
		Handle(item[1], item[2], item[3], now)
	end
	if inHead > inTail then
		inHead, inTail = 1, 0
	end
end

---------------------------------------------------------------------------
-- Beacon's hooks
---------------------------------------------------------------------------

local B = ns.Beacon

-- Every B2;e... message (after Beacon's guard): for the tick.
function B.ReceiveEchoes(id, word, more)
	if E.recording and inTail - inHead + 1 < INCOMING_MAX then
		inTail = inTail + 1
		incoming[inTail] = { id, word, more }
	end
end

-- A probe bigger than any other message (Beacon lets it through): answered on the tick.
function B.ReceiveProbe(id, text)
	local size = E.recording and text:match("^B2;ex;(%d+);")
	if size and peers[id] and peers[id].verified then
		OnProbe(id, tonumber(size), #text)
	end
end

-- Beacon answers a friend's hello (they started, or are new to me): my eh, once their build is
-- known to read it; everything I hold goes to them again.
function B.EchoesAnswer(id)
	if E.recording then
		owedHello[id] = { at = GetTime(), answer = false }
		ResetPeer(id)
	end
end

-- A friend went away: what was asked of them can be asked of someone else.
function B.EchoesForget(id)
	Withdraw(id)
	DropOut(id)
	Release(id)
	StopServing(id)
	peers[id], owedHello[id], xmap[id], peerTimes[id], waitingFor[id], silentAt[id] = nil, nil, nil, nil, nil, nil
	ResetPeer(id)
	if probe and probe.id == id then
		probe.gone = true
	end
end

local function Reset()
	for record in pairs(queued) do
		if record.serve then
			record.serve.pending = 0
		end
	end
	for _, t in ipairs({ peers, owedHello, incoming, inflight, partials, bad, checked, noRoom, silentAt, xmap, serves, active, out, queued,
			answersOut, tracks.es, tracks.ea, tracks.ed, summariesOut.es, summariesOut.ea, summariesOut.ed, sentTimes, peerTimes, waitingFor }) do
		wipe(t)
	end
	inHead, inTail, outstanding = 1, 0, 0
	seenAt = -math.huge
	lastHouse, lastFlags, probe = nil, nil, nil
	inCombat = false
	Changed()
end

-- Beacon switched off: its queues are empty, nobody is known any more.
function B.EchoesStop()
	Reset()
end

---------------------------------------------------------------------------
-- The tick (Echoes' driver, 4 a second while recording)
---------------------------------------------------------------------------

local function Hellos(now)
	local beacon = ns.Beacon
	for id, owed in pairs(owedHello) do
		local bpeer = beacon.peers[id]
		if not bpeer then
			owedHello[id] = nil
		elseif peers[id] or Capable(bpeer) then
			owedHello[id] = nil
			Control(id, HelloMessage(MyFlags(owed.answer)), "eh")
		elseif now - owed.at > HELLO_WAIT then
			owedHello[id] = nil -- (an older build: nothing for them)
		end
	end
	-- My settings changed: friends hear it (an answer: no hello back).
	local flags = MyFlags(false)
	if lastFlags and flags ~= lastFlags then
		for id, peer in pairs(peers) do
			if peer.verified ~= false and beacon.peers[id] then
				Control(id, HelloMessage(MyFlags(true)), "eh")
				ResetPeer(id) -- (what I hold may have changed with it)
			end
		end
		Changed()
	end
	lastFlags = flags
end

local function Housekeeping(now)
	lastHouse = now
	-- Pages change outside Delivery: E.Store says so (D.PagesChanged); this is only a safety net.
	if now - seenAt >= RECHECK then
		seenAt = now
		Changed()
	end
	Hellos(now)
	local beacon = ns.Beacon
	for id, peer in pairs(peers) do
		if not beacon.peers[id] then
			B.EchoesForget(id)
		elseif peer.verified == nil then
			Verify(id, peer, now)
		end
	end
	-- Requests without progress for SILENCE: asked again (Pull: from where they got to).
	-- Whoever let it go silent is asked last for a while (a holder in a long fight, or silent after
	-- a throttle, can't hold up both of my requests while others could answer).
	for pageId, r in pairs(inflight) do
		if r.sent and now - r.at >= SILENCE or not peers[r.from] then
			inflight[pageId] = nil
			if peers[r.from] then
				silentAt[r.from] = now
			end
		end
	end
	TrimPartials(now)
	-- What I hold safely as a collector, in safe like friends' summaries (passed on with them).
	if M.db.collect then
		SafeHere()
	end
	-- What I hold, my early pages, what's safe: to each friend it changed for, while out has room, and
	-- to SUMMARY_FRIENDS of them a second at most (everyone's at once after a hello or a change of my
	-- settings: spread over the next seconds; who got theirs waits SUMMARY_GAP, so all get a turn).
	local told = 0
	for id, peer in pairs(peers) do
		if #out >= OUT_MAX or told >= SUMMARY_FRIENDS then
			break
		end
		if peer.verified and beacon.peers[id] then
			local went = false
			if peer.collect or peer.relay then
				went = Summary(id, peer, now)
			end
			if TakesEarly(id) then
				went = EarlySummary(id, now) or went
			end
			if peer.share or peer.relay or peer.collect then
				went = SafeSummary(id, now) or went
			end
			told = told + (went and 1 or 0)
		end
	end
	Pull(now)
end

-- Whether a friend who takes my pages early is online (Pages.lua: pages close sooner then, so they
-- leave me sooner). (Asked up to 4 times a second: nothing made for it.)
function D.EarlyTaker()
	local beacon = Beacon()
	if not beacon or not next(peers) then
		return false
	end
	for id in pairs(peers) do
		if TakesEarly(id) and beacon.peers[id] then
			return true
		end
	end
	return false
end

local function ProbeTick(now)
	if probe.gone then
		probe.finish = true
	elseif probe.i <= #PROBE_SIZES then
		if now >= probe.nextAt and not LT.InCombat() and now >= pausedUntil and ns.Beacon.Waiting() == 0 then
			local size = PROBE_SIZES[probe.i]
			local head = "B2;ex;" .. size .. ";"
			local message = head .. ("x"):rep(size - #head)
			local ok, result = pcall(C_BattleNet.SendGameData, probe.id, ns.Beacon.PREFIX, message)
			-- (A call that returns nothing went, as far as anyone can tell, like Beacon takes it: the
			-- friend's answer says whether it arrived.)
			probe.results[size] = { result = ok and (result or 0) or "error" }
			probe.i, probe.nextAt = probe.i + 1, now + PROBE_GAP
			probe.lastAt = now
			if ok and (result == 3 or result == 11) then
				probe.i = #PROBE_SIZES + 1 -- (the server says slow down: that's the answer for now)
				ns.Beacon.Throttled(result) -- (Beacon pauses too, as after its own)
				CheckThrottle() -- (and Echoes, at once)
			end
		end
	elseif now - probe.lastAt >= PROBE_WAIT then
		probe.finish = true
	else
		local all = true
		for _, size in ipairs(PROBE_SIZES) do
			local r = probe.results[size]
			all = all and (not r or r.got ~= nil or r.result ~= 0)
		end
		probe.finish = all
	end
	if probe.finish then
		local parts = {}
		for _, size in ipairs(PROBE_SIZES) do
			local r = probe.results[size]
			if r then
				local arrived = r.got == nil and "no answer" or (r.got == size and "arrived whole" or ("arrived as " .. r.got .. " bytes"))
				parts[#parts + 1] = ("%d bytes: %s"):format(size, r.result == 0 and arrived or ("refused (result " .. tostring(r.result) .. ")"))
			end
		end
		M:Print(("probe to %s: %s."):format(probe.name, #parts > 0 and table.concat(parts, "; ") or "nothing sent (gone)"))
		probe = nil
	end
end

local function Tick(now)
	local beacon = LT:GetModule("beacon")
	if not (beacon and beacon.enabled and E.data and MyAccount() and MyKey()) then
		return -- (my pages' key comes with my BattleTag: Pages.lua fills in E.data.acct)
	end
	HandleIncoming(now)
	CheckThrottle()
	if not lastHouse or now - lastHouse >= HOUSE_GAP then
		Housekeeping(now)
	end
	if probe then
		ProbeTick(now)
	end
	Send(now)
end
E.OnTick(Tick)

-- Switched off: my "I'm out" hello to these friends (gameAccountID -> true). Echoes' tick and budget
-- stop with it, so a frame of its own paces them (its OnUpdate set only while some are left): one at
-- a time, handed to Beacon only when nothing else waits there, OUT_GAP after the one before went.
-- Nothing of Echoes' goes in a fight: in one, the one waiting in Beacon's queue comes back out, and
-- the rest wait for its end (PLAYER_REGEN_ENABLED, registered only then); switched on again before
-- they all went, the rest don't go.
do
local OUT_GAP = 0.5
local outTo = {}
local outFrame = CreateFrame("Frame")
local outWait, pending = 0, nil -- (pending: the one in Beacon's queue, not sent yet)

local function SayOutUpdate(_, elapsed)
	local beacon = Beacon()
	if not (beacon and E.data and (E.data.acct or MyAccount())) then
		wipe(outTo)
		pending = nil
	elseif LT.InCombat() then
		if pending then
			beacon.DropLowFor(pending, IsEchoes)
			outTo[pending], pending = true, nil
		end
		outFrame:SetScript("OnUpdate", nil)
		outFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	elseif pending and not beacon.peers[pending] then
		pending = nil -- (gone: Beacon drops what waits for them)
	elseif not pending then
		outWait = outWait - elapsed
		if outWait <= 0 and beacon.Waiting() == 0 then
			local id = next(outTo)
			while id and not beacon.peers[id] do -- (gone meanwhile: the next one instead)
				outTo[id] = nil
				id = next(outTo)
			end
			if id then
				outTo[id], pending = nil, id
				beacon.QueueLow(id, HelloMessage("a"), function()
					if pending == id then
						pending, outWait = nil, OUT_GAP
					end
				end)
			end
		end
	end
	if not pending and not next(outTo) then
		outFrame:SetScript("OnUpdate", nil)
	end
end

local function SayOut()
	outFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
	outWait, pending = 0, nil
	outFrame:SetScript("OnUpdate", next(outTo) and SayOutUpdate or nil)
end
outFrame:SetScript("OnEvent", SayOut)

-- Recording started (login, or switched on): friends already known hear my hello.
E.When("start", function()
	wipe(outTo) -- (switched off and on in a fight, or before all heard it: the rest never hear I was out)
	pending = nil
	outFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
	outFrame:SetScript("OnUpdate", nil)
	Reset()
	local now = GetTime()
	for id in pairs(ns.Beacon.peers) do
		owedHello[id] = { at = now, answer = false }
	end
end)

-- Recording stops (switched off): friends hear that I'm out (no c, r or s; no answer wanted), after
-- the fight if I'm in one, and nothing else of mine goes.
E.When("stop", function()
	Withdraw()
	local beacon = Beacon()
	for id, peer in pairs(beacon and peers or {}) do
		if peer.verified ~= false and beacon.peers[id] then
			outTo[id] = true
		end
	end
	if next(outTo) then
		if LT.InCombat() then
			outFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
		else
			SayOut()
		end
	end
	Reset()
end)
end

---------------------------------------------------------------------------
-- Status and the probe (for /lefthy echoes status | probe <friend>)
---------------------------------------------------------------------------

-- Delivery's lines for a status (chat, English).
function D.Status()
	local now = GetTime()
	local beacon = ns.Beacon
	local friends, early = {}, {}
	for id, peer in pairs(peers) do
		if peer.verified and beacon.peers[id] then
			local takes = TakesEarly(id)
			local roles = (peer.collect and "collects, " or "") .. (takes and "takes early pages, " or "") .. (peer.relay and "relays, " or "")
			if takes then
				early[#early + 1] = beacon.peers[id].name or ("#" .. id)
			end
			local pages = 0
			for key, list in pairs(peer.holdings) do
				for _, r in ipairs(key ~= MyKey() and list or {}) do -- (not my own pages they hold)
					pages = pages + r[2] - r[1] + 1
				end
			end
			friends[#friends + 1] = ("  %s: %s%d page(s) offered."):format(beacon.peers[id].name or ("#" .. id), roles, pages)
		end
	end
	table.sort(friends)
	local lines = { ("passing pages on: %d friend(s) with Echoes online, %d page(s) coming, %d being served, %d waiting to be."):format(
		#friends, InFlight(), #active, #serves) }
	for _, line in ipairs(friends) do
		lines[#lines + 1] = line
	end
	if D.EarlyTaker() then
		table.sort(early)
		lines[#lines + 1] = ("your pages go to %s early (10-minute pages while a collector is online)."):format(table.concat(early, ", "))
	end
	lines[#lines + 1] = ("traffic: %d message(s) sent, %d received, %d page(s) got, %.1f KB served, %d page(s) failed their hash."):format(
		stats.sent, stats.received, stats.pages, stats.served / 1024, stats.badHash)
	if now < pausedUntil then
		lines[#lines + 1] = ("paused for %d s more (the server asked Beacon to slow down)."):format(math.ceil(pausedUntil - now))
	end
	return lines
end

-- /lefthy echoes probe <friend>: messages of 255 to 4000 bytes to a friend with Echoes, to see
-- what the server lets through (docs/echoes.md: Message size). Returns false and why if it can't.
function D.Probe(name)
	local beacon = Beacon()
	if not (beacon and E.recording) then
		return false, "needs Echoes recording and Beacon on."
	end
	name = strtrim(tostring(name or "")):lower()
	if name == "" then
		return false, "usage: /lefthy echoes probe <friend>"
	end
	if probe then
		return false, "a probe is still running."
	end
	for id, peer in pairs(peers) do
		local friend = beacon.peers[id] and beacon.peers[id].name
		if peer.verified and friend and (friend:lower() == name or (LT.Names.First(friend) or ""):lower() == name) then
			probe = { id = id, name = friend, i = 1, nextAt = 0, lastAt = GetTime(), results = {} }
			return true
		end
	end
	return false, "no friend with Echoes called " .. name .. " online."
end

-- "/lefthy echoes probe <friend>".
function D.ProbeCommand(rest)
	local ok, why = D.Probe(rest)
	M:Print(ok and "probing... the result follows in about 20 s." or why)
end

E.Command("probe", D.ProbeCommand, "/lefthy echoes probe <friend> - which message sizes the server lets through to a friend with Echoes")
E.OnStatus(function(add)
	for _, line in ipairs(D.Status()) do
		add(line)
	end
end)
