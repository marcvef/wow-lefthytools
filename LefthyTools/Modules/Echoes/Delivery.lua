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
-- Messages: Beacon's B family (Protocol.lua), module letter e. Only to friends who sent eh (an
-- eh itself only to a build that reads it, see Hello):
--   B2;eh;<acct>;<store>;<proto>;<maxBytes>;<flags>
--                       hello: flags c collect, r relay, s share, a an answer (no answer to it);
--                       none of c, r, s: switched off. In answer to a hello, when settings change
--   B2;es;<acct>.<store>:<ranges>/...    pages I can serve ("1-56,58")
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
local BACKOFF_FIRST, BACKOFF_MAX, BACKOFF_CALM = 30, 300, 600 -- after a throttle: silent this long,
                             -- twice that after the next one (up to BACKOFF_MAX), back to the first after calm
local HELLO_WAIT = 60        -- a friend's build not known to read B this long after their hello: an older one
local COPIES = 2             -- a relay leaves pages alone that this many online friends besides the author hold
local NO_ROOM_WAIT = 300     -- a page too big for the relay's cache isn't asked for again this long
local PARTIALS_MAX, PARTIAL_AGE = 256 * 1024, 600 -- unfinished pages: bytes kept, seconds without progress
local INCOMING_MAX, INCOMING_PER_TICK = 600, 60 -- messages waiting for the tick, handled per tick
local FRIENDS_GAP = 30       -- the friend list's accounts are read again after this long
local HOUSE_GAP = 1          -- requests, timeouts, checks, summaries: once a second
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

-- Every Battle.net friend, online or not: their account, and which game accounts are theirs.
local function ReadFriends(now)
	friendsAt = now
	wipe(friendAccts)
	wipe(idAccts)
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
	if now - friendsAt >= FRIENDS_GAP then
		ReadFriends(now)
	end
	return friendAccts
end

-- Pages I take: my Battle.net friends' accounts' and my own (my other computers).
local function Accepted(acct, now)
	return acct ~= nil and (acct == MyAccount() or Friends(now)[acct] == true)
end

-- A Beacon friend's account (their BattleTag's hash), nil while Battle.net doesn't say.
local function PeerAccount(id, now)
	Friends(now)
	local acct = idAccts[id]
	if not acct and now - friendsAt >= 5 then
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

local function Changed()
	wipe(cache)
end
-- Pages changed outside Delivery (closed, dropped by the cap, the 30 days or a receipt): looked at
-- anew. (Delivery also looks again every 30 s, and when E.data.n moves.)
D.PagesChanged = Changed

-- My pages' key, nil while my BattleTag isn't known.
local function MyKey()
	return S.Own()
end

local function Split(key)
	return key:sub(1, 8), key:sub(10)
end

-- What I hold of where ("mine", "carry", "inbox"): { [key] = list }.
local function HeldIn(where)
	local id = "held>" .. where
	if not cache[id] then
		local out = {}
		for key, ranges in pairs(S.Held(where)) do
			local list = Ranges.Parse(ranges)
			if list and #list > 0 then
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

-- A page I can serve (of key, number n), or nil.
local function Get(key, n)
	local acct, store = Split(key)
	local page = S.Page(acct, store, n)
	return S.Shareable(page) and page or nil
end

-- A collector's: what the exporter has of key.
local function Exported(key)
	local id = "exported>" .. key
	if not cache[id] then
		cache[id] = Ranges.Parse(E.data.exported[key] or "") or {}
	end
	return cache[id]
end

-- What some collector holds safely of key (what collectors said, and mine if I collect).
local function SafeOf(key)
	local id = "safe>" .. key
	if not cache[id] then
		local list = {}
		for _, ranges in pairs(E.data.safe[key] or {}) do
			list = Ranges.Union(list, Ranges.Parse(ranges) or {})
		end
		cache[id] = list
	end
	return cache[id]
end

-- A collector holds list of key safely: E.Store merges it into safe (only grows) and drops those
-- pages from mine and carry. Only when it grows; at most SAFE_KEYS stores and SAFE_COLLECTORS
-- collectors each (a broken or hostile client can't fill the saved table).
local SAFE_KEYS, SAFE_COLLECTORS = 200, 8
local function Safe(key, collector, list)
	local safe = E.data.safe
	local byCollector = safe[key]
	if not byCollector and Count(safe) >= SAFE_KEYS then
		return
	elseif byCollector and not byCollector[collector] and Count(byCollector) >= SAFE_COLLECTORS then
		return
	end
	local old = byCollector and byCollector[collector]
	local merged = Ranges.Format(Ranges.Union(Ranges.Parse(old or "") or {}, list))
	if merged == "" or merged == old then
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
		local list = Ranges.Parse(S.SafeHere(acct, store)) or {}
		if #list > 0 then
			Safe(key, mine, list)
		end
	end
	cache.safeHere = true
end

-- A page that came, kept by E.Store where ("carry" or "inbox"): true (true, "have": had it), or
-- false and why (E.Store.Put's reasons).
local function Put(key, n, page, where)
	local acct, store = Split(key)
	local ok, why = S.Put(acct, store, n, page, where)
	Changed()
	return ok, why
end

-- A page I relay already, collected now: it moves to the inbox.
local function Move(key, n, page)
	local acct, store = Split(key)
	if S.Put(acct, store, n, page, "inbox") then
		S.Drop(acct, store, tostring(n), "carry")
	end
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
local function Pack(head, items)
	local list, current, size = {}, {}, #head
	for _, item in ipairs(items) do
		if #current > 0 and size + 1 + #item > MAX_BYTES then
			list[#list + 1] = head .. table.concat(current, "/")
			current, size = {}, #head
		end
		current[#current + 1] = item
		size = size + (#current > 1 and 1 or 0) + #item
	end
	if #current > 0 then
		list[#list + 1] = head .. table.concat(current, "/")
	end
	return list
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
				relay = flags:find("r", 1, true) ~= nil, share = flags:find("s", 1, true) ~= nil, answer = flags:find("a", 1, true) ~= nil }
		end
	elseif word == "es" then
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
-- verified (true: their account is the one Battle.net says; false: it isn't; nil: not known yet),
-- holdings = { [key] = list } }
local peers = {}
local owedHello = {}   -- gameAccountID -> { at, answer }: my eh, once they're known to read it
local incoming = {}    -- [inHead..inTail] = { id, word, more }: messages for the tick
local inHead, inTail = 1, 0
local inflight = {}    -- pageId ("<acct>.<store>.<n>") -> { from, key, n, at, sent }: my requests
local partials = {}    -- pageId -> { key, n, len, hash, t0, m, chunks, have, at, from = { [id] = true } }
local bad = {}         -- pageId -> { [id] = true }: holders whose copy didn't match its hash (this session)
local noRoom = {}      -- pageId -> when it was too big for my relay cache (not asked again for NO_ROOM_WAIT)
local xmap = {}        -- sender -> { [x] = pageId }: their transfers
local serves = {}      -- requests waiting: { id, key, acct, store, n, offset }
local active = {}      -- serving: { id, key, acct, store, n, x, offset, len, page, begun, pending }
local out = {}         -- my other messages, waiting their turn: { id, message, kind, pageId }
local queued = {}      -- record -> true: my messages in Beacon's queue, not sent yet
local outstanding = 0
local sentHold, sentSafe = {}, {} -- gameAccountID -> { at, full, sent = { [item key] = ranges text } }
-- The rate, in any second: when my last RATE messages went, and the last PEER_RATE to each friend
-- (oldest first), and how many wait in Beacon's queue for each.
local sentTimes, peerTimes, waitingFor = {}, {}, {}
local nextX, seq = 0, 0
local lastHouse
local pausedUntil, backoff, seenThrottle = 0, nil, nil
local inCombat = false
local lastFlags
local seenN, seenAt = nil, -math.huge -- the pages' cache: the last page closed when last looked, and when
local probe
local stats = { sent = 0, received = 0, pages = 0, served = 0, badHash = 0, rejected = 0 }

D.peers, D.inflight, D.partials, D.serves, D.active, D.out, D.stats = peers, inflight, partials, serves, active, out, stats

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

local function MyFlags(answer)
	return (M.db.collect and "c" or "") .. (M.db.relay and "r" or "") .. "s" .. (answer and "a" or "")
end

local function HelloMessage(flags)
	local acct = E.data.acct or MyAccount()
	return Msg("eh", acct, E.data.store, PROTO, MAX_BYTES, flags)
end

-- A message for one friend, after the ones already waiting (sent on the tick, see Send).
local function Control(id, message, kind, pageId)
	out[#out + 1] = { id = id, message = message, kind = kind, pageId = pageId }
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
	for _, t in ipairs(times or {}) do
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
		pageId = item.pageId, seq = seq }
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
	for i = #list, 1, -1 do
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
			table.insert(out, 1, { id = record.id, message = record.message, kind = record.kind, pageId = record.pageId })
		end
	end
end
D.Withdraw = Withdraw

-- The next message to send: mine waiting first (hellos, requests, summaries), then the pages I
-- serve, by turns; only to a friend who may get one now (MayGo). nil: none.
local turn = 0
local function NextMessage(now)
	local B = ns.Beacon
	for i, item in ipairs(out) do
		if not B.peers[item.id] then
			table.remove(out, i)
			return NextMessage(now) -- (gone: theirs go)
		elseif MayGo(item.id, now) then
			table.remove(out, i)
			return item
		end
	end
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

-- Requests waiting become serves while fewer than SERVING run.
local function StartServes()
	while #active < SERVING and serves[1] do
		local s = NextServe()
		local page = ns.Beacon.peers[s.id] and Get(s.key, s.n)
		if page and s.offset < #page.z then
			nextX = nextX % 99 + 1
			active[#active + 1] = { id = s.id, key = s.key, acct = s.acct, store = s.store, n = s.n, x = nextX,
				offset = s.offset, len = #page.z, page = page, begun = false, pending = 0 }
		elseif ns.Beacon.peers[s.id] and not page then
			Control(s.id, Msg("en", s.acct, s.store, s.n), "en")
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
	StartServes()
	local B = ns.Beacon
	-- Only when nothing but mine waits in Beacon's queues: everything else goes first.
	while outstanding < OUTSTANDING and B.Waiting() <= outstanding do
		local item = NextMessage(now)
		if not item then
			break
		end
		Enqueue(item)
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
	sentHold[id], sentSafe[id] = nil, nil
end

-- Requests to one holder are given up (another may answer, or the same again later), also the ones
-- still waiting to go.
local function Release(id)
	for pageId, r in pairs(inflight) do
		if r.from == id then
			inflight[pageId] = nil
		end
	end
	for i = #out, 1, -1 do
		if out[i].id == id and out[i].kind == "eq" then
			table.remove(out, i)
		end
	end
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

local function Verify(id, peer, now)
	local acct = PeerAccount(id, now)
	if acct then
		peer.verified = acct == peer.acct
		if not peer.verified then
			stats.rejected = stats.rejected + 1
		end
	end
end

local function OnHello(id, msg, now)
	local peer = peers[id]
	local key = msg.acct .. "." .. msg.store
	if not peer or peer.key ~= key then
		peer = { holdings = {} }
		peers[id] = peer
	end
	peer.acct, peer.store, peer.key = msg.acct, msg.store, key
	peer.proto, peer.maxBytes = msg.proto, msg.maxBytes
	peer.collect, peer.relay, peer.share = msg.collect, msg.relay, msg.share
	if not msg.answer then
		-- They (re)started: they need mine, and everything I hold again; theirs comes again. What
		-- they asked of me before is gone with their session (they ask again what they still need).
		peer.holdings = {}
		ResetPeer(id)
		Release(id)
		StopServing(id)
		owedHello[id] = owedHello[id] or { at = now, answer = true }
	end
	if not (peer.collect or peer.relay or peer.share) then
		peer.holdings = {} -- (switched off)
		Release(id)
		StopServing(id)
	end
	if peer.verified == nil then
		Verify(id, peer, now)
	end
end

-- What I hold, to one friend who collects or relays: only what grew since they last heard it
-- (everything the first time, and again every FULL_OFFER), at most every SUMMARY_GAP.
local function Summary(id, peer, now)
	local s = sentHold[id]
	if not s then
		s = { at = -math.huge, full = now, sent = {} }
		sentHold[id] = s
	end
	if now - s.at < SUMMARY_GAP then
		return
	end
	if now - s.full >= FULL_OFFER then
		s.full = now
		wipe(s.sent)
	end
	local items, head = {}, "B2;es;"
	for key, list in pairs(Holdings()) do
		local text = Ranges.Format(list)
		if key ~= peer.key and text ~= s.sent[key] then
			s.sent[key] = text
			WriteItems(key, list, MAX_BYTES - #head, items)
		end
	end
	if #items > 0 then
		s.at = now
		table.sort(items)
		for _, message in ipairs(Pack(head, items)) do
			Control(id, message, "es")
		end
	end
end

-- What collectors hold safely (theirs passed on, mine if I collect), to one friend, the same way.
local function SafeSummary(id, now)
	local s = sentSafe[id]
	if not s then
		s = { at = -math.huge, full = now, sent = {} }
		sentSafe[id] = s
	end
	if now - s.at < SUMMARY_GAP then
		return
	end
	if now - s.full >= FULL_OFFER then
		s.full = now
		wipe(s.sent)
	end
	local byCollector = {}
	for key, collectors in pairs(E.data.safe) do
		for collector, text in pairs(collectors) do
			local mark = collector .. ">" .. key
			if text ~= s.sent[mark] then
				s.sent[mark] = text
				byCollector[collector] = byCollector[collector] or {}
				local list = byCollector[collector]
				list[#list + 1] = { key, Ranges.Parse(text) or {} }
			end
		end
	end
	local any = false
	for collector, list in pairs(byCollector) do
		local cAcct, cStore = collector:match("^(%x+)%.(%x+)$")
		if cAcct then
			local head = "B2;ed;" .. cAcct .. ";" .. cStore .. ";"
			local items = {}
			for _, entry in ipairs(list) do
				WriteItems(entry[1], entry[2], MAX_BYTES - #head, items)
			end
			table.sort(items)
			for _, message in ipairs(Pack(head, items)) do
				Control(id, message, "ed")
				any = true
			end
		end
	end
	if any then
		s.at = now
	end
end

---------------------------------------------------------------------------
-- Pulling: asking holders for the pages I want
---------------------------------------------------------------------------

local function InFlight()
	return Count(inflight)
end

-- An online friend who collects holds n of key (it's as good as safe: no relay needed).
local function HeldByCollector(key, n)
	for _, peer in pairs(peers) do
		if peer.verified and peer.collect and peer.holdings[key] and Ranges.Has(peer.holdings[key], n) then
			return true
		end
	end
	return false
end

-- Online friends besides the author who hold n of key.
local function Copies(key, n)
	local copies = 0
	for _, peer in pairs(peers) do
		if peer.verified and peer.key ~= key and peer.holdings[key] and Ranges.Has(peer.holdings[key], n) then
			copies = copies + 1
		end
	end
	return copies
end

-- The first page of offered (key's) I want from holder id, and where it goes; nil: none.
local function Wanted(id, key, offered, now, collecting, relaying)
	local acct = key:sub(1, 8)
	if key == MyKey() or not Accepted(acct, now) then
		return nil
	end
	local where, want
	if collecting then
		where = "inbox"
		want = Ranges.Minus(Ranges.Minus(offered, Have("inbox", key)), Exported(key))
	elseif relaying and acct ~= MyAccount() and Fits(key, 1) then -- (the size comes with the page: checked then)
		where = "carry"
		want = Ranges.Minus(Ranges.Minus(offered, Have("carry", key)), SafeOf(key))
	else
		return nil
	end
	local looked = 0
	for _, r in ipairs(want) do
		for n = r[1], r[2] do
			looked = looked + 1
			if looked > 50 then
				return nil -- (enough for this round)
			end
			local pageId = PageId(key, n)
			if not inflight[pageId] and not (bad[pageId] and bad[pageId][id]) and not (noRoom[pageId] and now - noRoom[pageId] < NO_ROOM_WAIT) then
				if where == "inbox" then
					local carried = (E.data.carry[key] or {})[n]
					if S.Shareable(carried) then
						Move(key, n, carried) -- (I relay it already: it just moves)
					else
						return n, where
					end
				elseif not HeldByCollector(key, n) and Copies(key, n) < COPIES then
					return n, where
				end
			end
		end
	end
	return nil
end

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
	if not (collecting or relaying) or InFlight() >= IN_FLIGHT then
		return
	end
	local busy = {}
	for _, r in pairs(inflight) do
		busy[r.from] = true
	end
	for _, id in ipairs(SortedKeys(peers)) do
		local peer = peers[id]
		if peer.verified and not busy[id] and ns.Beacon.peers[id] and (peer.share or peer.relay or peer.collect) then
			for _, key in ipairs(SortedKeys(peer.holdings)) do
				local n, where = Wanted(id, key, peer.holdings[key], now, collecting, relaying)
				if n then
					local pageId = PageId(key, n)
					local part = partials[pageId]
					inflight[pageId] = { from = id, key = key, n = n, where = where, at = now, sent = false }
					Control(id, Msg("eq", key:sub(1, 8), key:sub(10), n, part and part.have or 0), "eq", pageId)
					if InFlight() >= IN_FLIGHT then
						return
					end
					break
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
local function Complete(pageId, part)
	partials[pageId], inflight[pageId] = nil, nil
	local where
	if M.db.collect then
		where = "inbox"
	elseif M.db.relay and part.key:sub(1, 8) ~= MyAccount() then
		where = "carry"
	else
		return
	end
	local ok, why = Put(part.key, part.n, { t = part.t0, h = part.hash, m = part.m, z = table.concat(part.chunks) }, where)
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
local function OnBegin(id, msg, now)
	local key = msg.acct .. "." .. msg.store
	local pageId = PageId(key, msg.n)
	local r, part = inflight[pageId], partials[pageId]
	xmap[id] = xmap[id] or {}
	xmap[id][msg.x] = nil
	local stop = Msg("eq", msg.acct, msg.store, msg.n, msg.len)
	if not (r or part) or Get(key, msg.n) then
		Control(id, stop, "eq") -- (not asked for, or got already)
		return
	end
	if not Accepted(msg.acct, now) or key == MyKey() then
		bad[pageId] = bad[pageId] or {}
		bad[pageId][id] = true
		stats.rejected = stats.rejected + 1
		if r and r.from == id then
			inflight[pageId] = nil
		end
		Control(id, stop, "eq")
		return
	end
	if part and (part.len ~= msg.len or part.hash ~= msg.hash or part.t0 ~= msg.t0 or part.m ~= msg.m) then
		part = nil -- (another page than the bytes so far: from the start)
	end
	if not part then
		part = { key = key, n = msg.n, len = msg.len, hash = msg.hash, t0 = msg.t0, m = msg.m, chunks = {}, have = 0, from = {} }
		partials[pageId] = part
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
		Control(id, stop, "eq")
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
	local page = Get(key, msg.n)
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
		Control(id, Msg("en", msg.acct, msg.store, msg.n), "en")
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
	if peer and peer.holdings[key] then
		peer.holdings[key] = Ranges.Minus(peer.holdings[key], { { msg.n, msg.n } })
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
			local merged = peer.holdings[key] and Ranges.Union(peer.holdings[key], list) or list
			if #merged <= RANGES_MAX then
				peer.holdings[key] = merged
			end
			if key == MyKey() and peer.relay then
				Carried(key, list) -- (a relay holds these of mine: over the cap they go first)
			end
		end
	end
end

local function OnSafe(_, msg, now)
	-- Only collectors I'd take pages from myself (a friend's account or mine), about pages I take.
	if not Accepted(msg.acct, now) then
		return
	end
	local collector = msg.acct .. "." .. msg.store
	for _, item in ipairs(msg.items) do
		if Accepted(item[2], now) then
			Safe(item[1], collector, item[3])
		end
	end
end

-- The probe's answer to them: how much of it arrived.
local function OnProbe(id, size, got)
	Control(id, Msg("ey", size, got), "ey")
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
	for i = #out, 1, -1 do
		if out[i].id == id then
			table.remove(out, i)
		end
	end
	Release(id)
	StopServing(id)
	peers[id], owedHello[id], xmap[id], peerTimes[id], waitingFor[id] = nil, nil, nil, nil, nil
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
	for _, t in ipairs({ peers, owedHello, incoming, inflight, partials, bad, noRoom, xmap, serves, active, out, queued,
			sentHold, sentSafe, sentTimes, peerTimes, waitingFor }) do
		wipe(t)
	end
	inHead, inTail, outstanding = 1, 0, 0
	seenN, seenAt = nil, -math.huge
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
	-- Pages close, and retention or receipts drop some, outside Delivery: looked at anew then.
	if E.data.n ~= seenN or now - seenAt >= 30 then
		seenN, seenAt = E.data.n, now
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
	for pageId, r in pairs(inflight) do
		if r.sent and now - r.at >= SILENCE or not peers[r.from] then
			inflight[pageId] = nil
		end
	end
	TrimPartials(now)
	-- What I hold safely as a collector, in safe like friends' summaries (passed on with them).
	if M.db.collect then
		SafeHere()
	end
	for id, peer in pairs(peers) do
		if peer.verified and beacon.peers[id] then
			if peer.collect or peer.relay then
				Summary(id, peer, now)
			end
			if peer.share or peer.relay or peer.collect then
				SafeSummary(id, now)
			end
		end
	end
	Pull(now)
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
			probe.results[size] = { result = ok and result or "error" }
			probe.i, probe.nextAt = probe.i + 1, now + PROBE_GAP
			probe.lastAt = now
			if ok and (result == 3 or result == 11) then
				probe.i = #PROBE_SIZES + 1 -- (the server says slow down: that's the answer for now)
				Backoff(now)
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

-- Recording started (login, or switched on): friends already known hear my hello.
E.When("start", function()
	Reset()
	local now = GetTime()
	for id in pairs(ns.Beacon.peers) do
		owedHello[id] = { at = now, answer = false }
	end
end)

-- Recording stops (switched off): friends hear that I'm out (no c, r or s; no answer wanted), and
-- nothing else of mine goes.
E.When("stop", function()
	Withdraw()
	local beacon = Beacon()
	if beacon and E.data and (E.data.acct or MyAccount()) then
		for id, peer in pairs(peers) do
			if peer.verified ~= false and beacon.peers[id] then
				beacon.QueueLow(id, HelloMessage("a"))
			end
		end
	end
	Reset()
end)

---------------------------------------------------------------------------
-- Status and the probe (for /lefthy echoes status | probe <friend>)
---------------------------------------------------------------------------

-- Delivery's lines for a status (chat, English).
function D.Status()
	local now = GetTime()
	local beacon = ns.Beacon
	local friends = {}
	for id, peer in pairs(peers) do
		if peer.verified and beacon.peers[id] then
			local roles = (peer.collect and "collects, " or "") .. (peer.relay and "relays, " or "")
			local pages = 0
			for _, list in pairs(peer.holdings) do
				for _, r in ipairs(list) do
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
