local _, ns = ...
local LT = ns.LT
local E = ns.Echoes
local M = E.module

-- Storage: the closed pages in LefthyToolsEchoesDB (E.data) and what is kept of them (docs/echoes.md,
-- Pages and storage). Pages.lua closes a page with E.Store.Close (plain text, queued); the tick packs
-- one queued page at a time (zlib, Base64, LT.Hash32), never inside an event handler.
--
--   mine     my own closed pages, kept until a collector holds them: 2 MB at most, then the oldest
--            go, the ones a relay is known to carry first; offered to everyone only once on disk
--            (closed in an earlier session: after a crash, page numbers from the last save are used
--            again), and before that only to collectors who take them early (Held("early"),
--            Page(..., early)), as provisional pages. A page that never went out (o = 0) whose number
--            friends hold anyway is another page with that number (a WTF folder restored, or copied
--            and played on two computers, or a crash's lost pages a collector holds provisionally): it
--            moves to a new number above all of them (E.data.top), and my next pages close above it too
--   carry    friends' pages I relay: 512 KB, 128 KB per author, 30 days
--   inbox    a collector's received pages (a: when each came), dropped only by the exporter's receipt
--            (only the ones it read: upto); a chat line at 4 MB asks to run the exporter, at 8 MB
--            pulling pauses (E.Store.InboxFull). A page that came early (p) is provisional until a
--            copy from its author's disk shows the same hash (Confirm): never safe, never served,
--            told only to its author; one the receipt takes goes to provisional (n -> its hash), not
--            exported, so a page with that number from the author's disk is still fetched
--   safe     what collectors hold safely, per author; exported: what the receipts listed in done (a
--            version from a disk; never their early, the numbers the exporter has only early copies
--            of). A store's entry goes 60 days after anything was last heard of it first-hand
--            (heard: a friend offered pages of it, its collector told it, or pages of it are here):
--            summaries passed on from friend to friend would keep every entry forever, and a broken
--            or hostile friend could fill all 200 places for good
--
-- For /lefthy echoes, noted as pages come and go (one comparison each): safeTo, the newest page of
-- mine that went because a collector holds it (my pages keep when they ended, e); latest, the newest
-- page a collector received of each store (the exporter's receipt takes the pages themselves);
-- names, friends' first names by store (Delivery says them).
--
-- Pages from before the launch day go. E.Ranges: page numbers as range strings ("1-56,58").
-- E.Store: the pages' API for the delivery; every change to mine, carry and inbox goes through it
-- (it keeps their sizes), and each one tells the delivery (D.PagesChanged: it caches what I hold).
-- The game never decompresses a page: only the exporter does.

local KB = 1024
local MINE_CAP = 2048 * KB                    -- my pages
local CARRY_CAP, CARRY_AUTHOR = 512 * KB, 128 * KB -- relayed pages, in all and per author
local CARRY_SECONDS = 30 * 86400              -- a relayed page is dropped after 30 days
local INBOX_NOTE, INBOX_FULL = 4096 * KB, 8192 * KB -- the collector: ask for the exporter; pause
local PAGE_MAX = 64 * KB                      -- a stored page (its z) is at most this
local AHEAD = 86400                           -- a page may start at most a day ahead
local MAX_N = 999999999                       -- page numbers are 1 to this
local SEEN_AHEAD = 10000                      -- my numbers friends tell beyond this above my last page: not believed
local SAFE_AGE = 60 * 86400                   -- what collectors hold of a store goes after 60 days unmentioned
local RECEIPT = "LefthyTools_EchoesReceipt"   -- the exporter's load-on-demand addon, on the collector's PC
local NAMES_MAX = 200                         -- friends' names kept (E.data.names)
local SHOWN, SHOWN_AGE = 10, 30 * 86400       -- the status: friends' stores shown at most, and none whose newest page is older

local issecret = LT.IsSecret

---------------------------------------------------------------------------
-- Ranges: page numbers as "1-56,58" (ascending, merged, from 1). A parsed list is { { 1, 56 },
-- { 58, 58 } }; every function takes a string or a parsed list.
---------------------------------------------------------------------------

local Ranges = {}
E.Ranges = Ranges

local function ByStart(a, b)
	return a[1] < b[1]
end

-- Sorted, overlapping and touching ranges merged (a new list).
local function Merge(list)
	table.sort(list, ByStart)
	local out = {}
	for i = 1, #list do
		local r, last = list[i], out[#out]
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

-- "1-56,58" as a parsed list; parts that aren't a number or "a-b" (a <= b, from 1) are skipped.
-- A list is taken as it is.
function Ranges.Parse(ranges)
	if issecret(ranges) then
		return {}
	elseif type(ranges) == "table" then
		return ranges
	end
	local list = {}
	if type(ranges) ~= "string" then
		return list
	end
	for part in ranges:gmatch("[^,]+") do
		local a, b = part:match("^%s*(%d+)%s*%-%s*(%d+)%s*$")
		if not a then
			a = part:match("^%s*(%d+)%s*$")
			b = a
		end
		a, b = tonumber(a), tonumber(b)
		if a and b and a >= 1 and a <= b and b <= MAX_N then
			list[#list + 1] = { a, b }
		end
	end
	return Merge(list)
end

-- A parsed list as "1-56,58" ("" when empty).
function Ranges.Format(ranges)
	local parts = {}
	for i, r in ipairs(Ranges.Parse(ranges)) do
		parts[i] = r[1] == r[2] and ("%d"):format(r[1]) or ("%d-%d"):format(r[1], r[2])
	end
	return table.concat(parts, ",")
end

-- Both together, as a string.
function Ranges.Union(a, b)
	local list = {}
	for _, r in ipairs(Ranges.Parse(a)) do
		list[#list + 1] = r
	end
	for _, r in ipairs(Ranges.Parse(b)) do
		list[#list + 1] = r
	end
	return Ranges.Format(Merge(list))
end

-- a without b, as a string.
function Ranges.Minus(a, b)
	local out, y, j = {}, Ranges.Parse(b), 1
	for _, r in ipairs(Ranges.Parse(a)) do
		local from, to = r[1], r[2]
		while y[j] and y[j][2] < from do
			j = j + 1
		end
		local k = j
		while from <= to do
			local s = y[k]
			if not s or s[1] > to then
				out[#out + 1] = { from, to }
				break
			end
			if s[1] > from then
				out[#out + 1] = { from, s[1] - 1 }
			end
			from = math.max(from, s[2] + 1)
			k = k + 1
		end
	end
	return Ranges.Format(out)
end

-- Whether n is in them.
function Ranges.Contains(ranges, n)
	if type(n) ~= "number" then
		return false
	end
	for _, r in ipairs(Ranges.Parse(ranges)) do
		if n < r[1] then
			return false
		elseif n <= r[2] then
			return true
		end
	end
	return false
end

-- A table's page numbers (its keys) as a string; keep(n, value): only those it says true for.
function Ranges.Of(t, keep)
	local list = {}
	for n, v in pairs(type(t) == "table" and t or {}) do
		if type(n) == "number" and n >= 1 and n <= MAX_N and n == math.floor(n) and (not keep or keep(n, v)) then
			list[#list + 1] = { n, n }
		end
	end
	return Ranges.Format(Merge(list))
end

---------------------------------------------------------------------------
-- Sizes: the bytes of the stored strings (z), kept as pages come and go; counted anew when recording
-- starts, for a saved table not counted yet, and by the status command.
---------------------------------------------------------------------------

local Store = {}
E.Store = Store

local WHERE = { "mine", "carry", "inbox" }
local bytes = { mine = 0, carry = 0, inbox = 0 }
local carryBy = {}   -- "acct.store" -> bytes relayed for that author's store
local carried = {}   -- n -> true: my pages a relay is known to carry (this session)
local countedFor     -- the saved table the sizes are of
local queue = {}     -- my closed pages waiting to be packed, oldest first
local chores = {}    -- what's left to do after the start, one a tick
local notedSession, receiptSession -- the session the 4 MB line was said in, the receipt read in
local noteDue = false
local moved = 0      -- my pages moved to a new number this session (their number was in use)
local arrived = 0    -- one more than the latest arrival (a) in the inbox when the sizes were counted

local function Size(page)
	return type(page) == "table" and type(page.z) == "string" and #page.z or 0
end

local function Count(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end

-- The pages changed (closed, packed, kept, dropped, safe, exported): the delivery looks at them anew
-- (Delivery.lua's D.PagesChanged, if it's there: it loads after this file).
local function Changed()
	local D = E.Delivery
	if type(D) == "table" and D.PagesChanged then
		LT.Guard("E.Store changed", D.PagesChanged)
	end
end

-- The sizes counted anew (a page that isn't one is dropped on the way), and the latest arrival in the
-- inbox noted (this runs when recording starts: a page that comes in this session arrives after
-- every page of an earlier one, whatever the clock says; the receipt's upto relies on it).
function Store.Recount()
	local data = E.data
	countedFor = data
	bytes.mine, bytes.carry, bytes.inbox = 0, 0, 0
	wipe(carryBy)
	arrived = 0
	for n, page in pairs(data.mine) do
		if Size(page) == 0 then
			data.mine[n] = nil
		else
			bytes.mine = bytes.mine + Size(page)
		end
	end
	for _, where in ipairs({ "carry", "inbox" }) do
		for key, pages in pairs(data[where]) do
			local sum = 0
			if type(pages) == "table" then
				for n, page in pairs(pages) do
					if Size(page) == 0 then
						pages[n] = nil
					else
						sum = sum + Size(page)
						if where == "inbox" and type(page.a) == "number" and page.a >= arrived and page.a < 1e10 then
							arrived = page.a + 1
						end
					end
				end
			end
			if sum == 0 then
				data[where][key] = nil
			else
				bytes[where] = bytes[where] + sum
				if where == "carry" then
					carryBy[key] = sum
				end
			end
		end
	end
	Changed()
end

local function Counted()
	if countedFor ~= E.data then
		Store.Recount()
	end
end

---------------------------------------------------------------------------
-- Pages by id
---------------------------------------------------------------------------

local function Hex8(s)
	return type(s) == "string" and not issecret(s) and #s == 8 and s:find("^%x+$") ~= nil
end

-- "acct.store" (the key pages are kept by), or nil if either isn't 8 hex digits.
function Store.Key(acct, store)
	if Hex8(acct) and Hex8(store) then
		return acct .. "." .. store
	end
end

-- My own pages' key, nil while my BattleTag isn't known.
function Store.Own()
	local data = E.data
	return data and Store.Key(data.acct, data.store)
end

-- The pages kept for key in where (mine: only my own key); make: a new table if there's none.
local function Pages(where, key, make)
	local data = E.data
	if where == "mine" then
		return key ~= nil and key == Store.Own() and data.mine or nil
	end
	local list = key and data[where][key]
	if not list and key and make then
		list = {}
		data[where][key] = list
	end
	return list
end

-- My page n goes (whatever my key).
local function DropMine(n)
	local page = E.data.mine[n]
	if not page then
		return false
	end
	E.data.mine[n] = nil
	bytes.mine = bytes.mine - Size(page)
	carried[n] = nil
	return true
end

local function Remove(where, key, n)
	if where == "mine" then
		return Pages(where, key) ~= nil and DropMine(n)
	end
	local list = Pages(where, key)
	local page = list and list[n]
	if not page then
		return false
	end
	list[n] = nil
	local size = Size(page)
	bytes[where] = bytes[where] - size
	if where == "carry" then
		carryBy[key] = (carryBy[key] or 0) - size
	end
	if next(list) == nil then
		E.data[where][key] = nil
		if where == "carry" then
			carryBy[key] = nil
		end
	end
	return true
end

-- Whether a page may go to others: packed (z) or Base64 of the text (r), not waiting to be packed.
-- Plain text (t) is kept and exported, never shared.
function Store.Shareable(page)
	return type(page) == "table" and not page.q and (page.m == "z" or page.m == "r") and type(page.z) == "string"
end
local Shareable = Store.Shareable

-- Whether my page is on disk: closed in an earlier session than this one (a /reload starts a new
-- one), closed as stale at login from the saved text (s: the session before), or from a build
-- before this rule (no s). Only those are offered to everyone: after a crash the next session
-- numbers its pages from the last save, so a lost session's page out there would share its number
-- with another page. The others go early only to collectors who keep them provisional (Delivery):
-- they never count as safe until a copy from my disk shows the same hash.
local function OnDisk(page)
	return type(page.s) ~= "number" or page.s < E.data.session
end

-- My page may go to others: shareable and on disk.
local function Offered(page)
	return Shareable(page) and OnDisk(page)
end

-- My page may go early (to a collector who takes pages early): shareable, not on disk yet.
local function Early(page)
	return Shareable(page) and not OnDisk(page)
end

-- E.data.provisional["acct.store"]: { [n] = hash }, a collector's provisional pages the exporter's
-- receipt took out of the inbox (the exporter has them) that aren't confirmed yet: not in exported,
-- so a page with that number from the author's disk is still fetched. nil if there's none (make: a
-- new one; the table made here if it isn't one).
local function ProvisionalOf(key, make)
	local all = E.data.provisional
	if type(all) ~= "table" then
		if not make then
			return nil
		end
		all = {}
		E.data.provisional = all
	end
	local list = key and all[key]
	if type(list) ~= "table" and make and key then
		list = {}
		all[key] = list
	end
	return type(list) == "table" and list or nil
end

-- A provisional inbox page: it came early, not confirmed yet.
local function Pending(page)
	return type(page) == "table" and page.p ~= nil
end

-- for n, page in E.Store.Mine(): my pages I offer (shareable, on disk), oldest (lowest n) first.
function Store.Mine()
	local list = {}
	for n, page in pairs(E.data.mine) do
		if type(n) == "number" and Offered(page) then
			list[#list + 1] = n
		end
	end
	table.sort(list)
	local i = 0
	return function()
		while i < #list do
			i = i + 1
			local page = E.data.mine[list[i]]
			if page then
				return list[i], page
			end
		end
	end
end

-- A page to serve: page, where ("mine", "inbox" or "carry"); nil if I don't have it (or it isn't
-- shareable; mine: or not on disk yet, unless early: for a collector who takes pages early; inbox:
-- or it's provisional).
function Store.Page(acct, store, n, early)
	local key = Store.Key(acct, store)
	if not key or type(n) ~= "number" then
		return nil
	end
	if key == Store.Own() then
		local page = E.data.mine[n]
		if Offered(page) or (early and Shareable(page)) then
			return page, "mine"
		end
		return nil
	end
	for _, where in ipairs({ "inbox", "carry" }) do
		local list = E.data[where][key]
		local page = list and list[n]
		if page and not Pending(page) then
			return page, where
		end
	end
end

-- What I hold of where as { ["acct.store"] = "ranges" }: "mine" (the pages I offer, shareable and on
-- disk, under my key; nothing while my BattleTag isn't known), "early" (mine shareable and not on
-- disk yet: for collectors who take them early), "carry", "inbox" (provisional pages left out) or
-- "provisional" (a collector's provisional pages: in the inbox, and the ones the receipt took).
function Store.Held(where)
	local out = {}
	if where == "mine" or where == "early" then
		local own = Store.Own()
		local ranges = own and Ranges.Of(E.data.mine, function(_, page) return (where == "mine" and Offered or Early)(page) end)
		if ranges and ranges ~= "" then
			out[own] = ranges
		end
	elseif where == "provisional" then
		for key, pages in pairs(E.data.inbox) do
			local ranges = Ranges.Of(pages, function(_, page) return Pending(page) end)
			if ranges ~= "" then
				out[key] = ranges
			end
		end
		for key, list in pairs(type(E.data.provisional) == "table" and E.data.provisional or {}) do
			local ranges = Ranges.Of(list, function(_, h) return type(h) == "string" end)
			if ranges ~= "" then
				out[key] = Ranges.Union(out[key], ranges)
			end
		end
	else
		for key, pages in pairs(E.data[where]) do
			out[key] = Ranges.Of(pages, where == "inbox" and function(_, page) return not Pending(page) end or nil)
		end
	end
	return out
end

-- Bytes kept: where ("mine", "carry", "inbox"); for carry with acct and store, that author's.
function Store.Bytes(where, acct, store)
	Counted()
	if where == "carry" and acct then
		return carryBy[Store.Key(acct, store) or ""] or 0
	end
	return bytes[where] or 0
end

-- Whether a relayed page of size bytes fits the cache (512 KB, 128 KB for the author's store).
function Store.Fits(acct, store, size)
	Counted()
	local key = Store.Key(acct, store)
	size = type(size) == "number" and size or 0
	return key ~= nil and bytes.carry + size <= CARRY_CAP and (carryBy[key] or 0) + size <= CARRY_AUTHOR
end

-- The collector's inbox reached 8 MB: stop pulling until the exporter's receipt makes room.
function Store.InboxFull()
	Counted()
	return bytes.inbox >= INBOX_FULL
end

---------------------------------------------------------------------------
-- My page numbers used twice: a WTF folder restored from a backup (its n from before pages that
-- went out since), or copied to a second computer and played on both (one store, both numbering
-- from the same n). A page of mine that never went out (o = 0: no part of it was ever sent; one
-- closed by a build before this rule counts as out) whose number friends hold anyway (a holder's
-- holdings, a collector's safe summary) is another page with that number: it moves to a new
-- number above every one of mine friends told of, so it travels as a page of its own, and my next
-- pages close above them too (E.data.top).
---------------------------------------------------------------------------

-- The highest number of mine friends told of, or given to a moved page (E.data.top); 0: none.
local function Told()
	local top = E.data.top
	return type(top) == "number" and top or 0
end

-- The text with its header's number old made new ("E1;acct;store;n;..."). Only for a page still in
-- plain text: a packed one keeps the number it was recorded under in its header (the game never
-- unpacks a page; the exporter files it under the number it's kept under).
local function Renumbered(text, old, new)
	local head, n, rest = text:match("^(E1;[^;\n]*;[^;\n]*;)(%d+)()")
	if head and tonumber(n) == old then
		return head .. new .. text:sub(rest)
	end
	return text
end

-- My page n moves to a new number: above every one in use or told of, and the open page's (that
-- one closes above it then). Offered from the next session on, like a new page: its new number is
-- on disk then. The new number.
local function Move(n)
	local data = E.data
	local page = data.mine[n]
	local open = type(data.open) == "table" and type(data.open.n) == "number" and data.open.n or 0
	local new = math.max(data.n, Told(), open) + 1
	while data.mine[new] do
		new = new + 1
	end
	data.mine[n], data.mine[new] = nil, page
	data.top = new
	page.s = data.session
	if page.q then
		local text = Renumbered(page.z, n, new)
		bytes.mine = bytes.mine - #page.z + #text
		page.z = text
		for i, waiting in ipairs(queue) do
			if waiting == n then
				queue[i] = new
			end
		end
	end
	carried[new], carried[n] = carried[n], nil
	moved = moved + 1
	return new
end

-- Friends hold these pages of mine (a holder's holdings, a collector's summary): my next pages close
-- above the highest (at most SEEN_AHEAD above my last page: a broken client), and a page of mine
-- among them that never went out moves to a new number (not one the exporter has from here: it read
-- it from this very table). The number moved.
local function Seen(ranges)
	local data = E.data
	local list = Ranges.Parse(ranges)
	local cap = data.n + SEEN_AHEAD
	for i = #list, 1, -1 do
		if list[i][1] <= cap then
			local high = math.min(list[i][2], cap)
			if high > Told() then
				data.top = high
			end
			break
		end
	end
	local clash, exported = {}, data.exported[Store.Own() or ""]
	for n, page in pairs(data.mine) do
		if type(page) == "table" and page.o == 0 and Ranges.Contains(list, n) and not Ranges.Contains(exported, n) then
			clash[#clash + 1] = n
		end
	end
	table.sort(clash)
	for _, n in ipairs(clash) do
		Move(n)
	end
	if clash[1] then
		Changed()
	end
	return #clash
end

-- Friends hold these pages of acct.store (a holder's holdings). For my own key: see above. The
-- number of my pages moved to a new number.
function Store.Elsewhere(acct, store, ranges)
	local key = Store.Key(acct, store)
	if not key or key ~= Store.Own() then
		return 0
	end
	return Seen(ranges)
end

-- A part of my page n went to a friend (Delivery, when it went; page: the page it served, if that's
-- still page n): it's out, so it keeps its number from now on.
function Store.WentOut(n, page)
	local mine = E.data.mine[n]
	if mine and mine == page and mine.o == 0 then
		mine.o = 1
	end
end

-- Whether a collector holds page n of key safely (a summary told so).
local function SafeSomewhere(key, n)
	for _, ranges in pairs(E.data.safe[key] or {}) do
		if Ranges.Contains(ranges, n) then
			return true
		end
	end
	return false
end

-- E.data[field] (heard, names, latest), made here if it isn't a table.
local function Kept(field)
	local t = E.data[field]
	if type(t) ~= "table" then
		t = {}
		E.data[field] = t
	end
	return t
end

-- My page n goes because a collector holds it safely (its summary, or my own exporter has it):
-- E.data.safeTo keeps the newest such page, { n, e (when it ended; a page from before e: its start) },
-- for the status. Newest by its end, not its number: a page moved to a new number is an old one.
local function Reached(n, page)
	local e = type(page) == "table" and (type(page.e) == "number" and page.e or page.t)
	if type(e) ~= "number" then
		return
	end
	local to = E.data.safeTo
	if type(to) ~= "table" or type(to.n) ~= "number" or type(to.e) ~= "number" then
		E.data.safeTo = { n = n, e = e }
	elseif e > to.e or (e == to.e and n > to.n) then
		to.n, to.e = n, e
	end
end

-- A collector received page n of key, started at t: E.data.latest[key] keeps the newest, { n, t },
-- for the status ("up to"; the exporter's receipt takes the pages themselves). Newest by its start,
-- like safeTo.
local function Newest(key, n, t)
	local latest = Kept("latest")
	local was = latest[key]
	if type(was) ~= "table" or type(was.n) ~= "number" or type(was.t) ~= "number" then
		latest[key] = { n = n, t = t }
	elseif t > was.t or (t == was.t and n > was.n) then
		was.n, was.t = n, t
	end
end

-- A friend's page received: where "carry" (relaying) or "inbox" (collecting). page = { t (its
-- start), h (LT.Hash32 of z), m ("z" or "r"), z }; it's kept as a copy with s (this session) and a
-- (when it came: relayed, for the 30 days; collected, for the receipt's upto, after every page of an
-- earlier session). provisional (inbox only): it came early, kept with p = 1 (Confirm). true, or
-- true and "have" (kept already); false and why not: "id" (a key or number that isn't one), "mine"
-- (my own store's), "page" (not a page: m, z, Base64), "size" (z over 64 KB), "time" (before the
-- launch or more than a day ahead), "hash" (h doesn't match), "exported" (the exporter has it),
-- "safe" (relaying: a collector holds it), "full" (relaying: no room, E.Store.Fits).
function Store.Put(acct, store, n, page, where, provisional)
	if where ~= "carry" and where ~= "inbox" then
		error("E.Store.Put: where is \"carry\" or \"inbox\", got " .. tostring(where), 2)
	end
	Counted()
	local key, data = Store.Key(acct, store), E.data
	if not key or type(n) ~= "number" or n < 1 or n > MAX_N or n ~= math.floor(n) then
		return false, "id"
	elseif key == Store.Own() then
		return false, "mine"
	elseif type(page) ~= "table" or (page.m ~= "z" and page.m ~= "r") or type(page.z) ~= "string" or issecret(page.z)
		or page.z == "" or page.z:find("[^A-Za-z0-9%+/=]") then
		return false, "page"
	elseif #page.z > PAGE_MAX then
		return false, "size"
	elseif type(page.t) ~= "number" or LT.BeforeLaunch(page.t) or page.t > E.Now() + AHEAD then
		return false, "time"
	end
	local list = Pages(where, key)
	if list and list[n] then
		return true, "have"
	elseif type(page.h) ~= "string" or LT.Hash32(page.z) ~= page.h then
		return false, "hash"
	elseif Ranges.Contains(data.exported[key], n) then
		return false, "exported"
	elseif where == "carry" and SafeSomewhere(key, n) then
		return false, "safe"
	elseif where == "carry" and not Store.Fits(acct, store, #page.z) then
		return false, "full"
	end
	list = Pages(where, key, true)
	local inbox = where == "inbox"
	list[n] = { t = page.t, h = page.h, m = page.m, z = page.z, s = data.session, a = inbox and math.max(E.Now(), arrived) or E.Now(),
		p = (inbox and provisional) and 1 or nil }
	bytes[where] = bytes[where] + #page.z
	if where == "carry" then
		carryBy[key] = (carryBy[key] or 0) + #page.z
	else
		Newest(key, n, page.t)
		if bytes.inbox >= INBOX_NOTE then
			noteDue = true -- (said on the tick)
		end
	end
	Changed()
	return true
end

-- Drops pages of acct.store: those in ranges (nil: all), from where (nil: mine, carry and inbox;
-- mine only for my own key); safe: a collector holds them (mine: noted in safeTo). The number dropped.
local function Drop(acct, store, ranges, where, safe)
	Counted()
	local key = Store.Key(acct, store)
	if not key then
		return 0
	end
	local list = ranges ~= nil and Ranges.Parse(ranges)
	local count = 0
	for _, w in ipairs(where and { where } or WHERE) do
		local pages = Pages(w, key)
		for n, page in pairs(pages or {}) do
			if (not list or Ranges.Contains(list, n)) and Remove(w, key, n) then
				count = count + 1
				if safe and w == "mine" then
					Reached(n, page)
				end
			end
		end
	end
	if count > 0 then
		Changed()
	end
	return count
end

function Store.Drop(acct, store, ranges, where)
	return Drop(acct, store, ranges, where)
end

-- E.data.heard: "acct.store" -> when (E.Now()) something was last heard of that store first-hand,
-- for the stores in safe only.
local function Heard()
	return Kept("heard")
end

-- A friend told of acct.store first-hand: it offers pages of it, or it's the collector whose summary
-- it is (one passed on doesn't count: every friend passes on every summary). What collectors hold of
-- it is kept 60 days from now.
function Store.Mentioned(acct, store)
	local key = Store.Key(acct, store)
	if key and type(E.data.safe[key]) == "table" then
		Heard()[key] = E.Now()
	end
end

-- acct.store is a friend's, whose character's first name is name (Delivery, when a verified friend
-- says hello): E.data.names keeps it for the status. At most 200; the chores drop the names of
-- stores nothing is kept of any more (Forget).
function Store.Named(acct, store, name)
	local key = Store.Key(acct, store)
	if not key or type(name) ~= "string" or issecret(name) or name == "" then
		return
	end
	local names = Kept("names")
	if names[key] == nil and Count(names) >= NAMES_MAX then
		return
	end
	names[key] = name
end

-- A collector (its "acct.store") holds these pages of acct.store safely (its summary, merged into
-- E.data.safe): they go from mine and carry. Of mine, a page that never went out isn't the one the
-- collector holds: it moves to a new number instead (Seen). The number dropped.
function Store.Safe(acct, store, ranges, collector)
	local key = Store.Key(acct, store)
	if not key or type(collector) ~= "string" or issecret(collector) or collector == "" then
		return 0
	end
	local safe = E.data.safe
	if type(safe[key]) ~= "table" then
		safe[key] = {}
		Heard()[key] = E.Now() -- (new: 60 days from now, unless heard of again)
	end
	local merged = Ranges.Union(safe[key][collector], ranges)
	if merged ~= safe[key][collector] then
		safe[key][collector] = merged
		Changed()
	end
	if key == Store.Own() then
		Seen(ranges)
	end
	return Drop(acct, store, ranges, "mine", true) + Drop(acct, store, ranges, "carry")
end

-- What this collector holds safely of acct.store, as ranges: received in an earlier session (on
-- disk) or exported. Never a provisional page: it came early, its author may have lost it in a crash
-- and closed another page with that number since; until a copy from the author's disk shows the
-- same hash, nobody may drop a page for it.
function Store.SafeHere(acct, store)
	local key = Store.Key(acct, store)
	if not key then
		return ""
	end
	local session = E.data.session
	local onDisk = Ranges.Of(E.data.inbox[key], function(_, page)
		return type(page) == "table" and type(page.s) == "number" and page.s < session and not Pending(page)
	end)
	return Ranges.Union(E.data.exported[key], onDisk)
end

-- Whether this collector holds page n of acct.store provisionally (it came early, not confirmed
-- yet): its hash and where, "inbox" (the page is here) or "provisional" (the receipt took it); nil
-- if not (also when the inbox has a page n from a disk: that one counts).
function Store.Provisional(acct, store, n)
	local key = Store.Key(acct, store)
	if not key or type(n) ~= "number" then
		return nil
	end
	local list = E.data.inbox[key]
	local page = type(list) == "table" and list[n]
	if type(page) == "table" then
		if Pending(page) then
			return type(page.h) == "string" and page.h or "", "inbox"
		end
		return nil
	end
	list = ProvisionalOf(key)
	local h = list and list[n]
	if type(h) == "string" then
		return h, "provisional"
	end
end

-- A copy of page n of acct.store from its author's disk has this hash: if it's the one I hold
-- provisionally, it's confirmed (the inbox page loses p and is safe like any; one the receipt took
-- is exported now). Whether it was.
function Store.Confirm(acct, store, n, hash)
	local h, where = Store.Provisional(acct, store, n)
	if not h or h ~= hash then
		return false
	end
	local key = Store.Key(acct, store)
	if where == "inbox" then
		E.data.inbox[key][n].p = nil
	else
		local list = ProvisionalOf(key)
		list[n] = nil
		if next(list) == nil then
			E.data.provisional[key] = nil
		end
		E.data.exported[key] = Ranges.Union(E.data.exported[key], tostring(n))
	end
	Changed()
	return true
end

-- A relay is known to carry these pages of acct.store (its holdings): if they're mine, they go first
-- when mine is over its cap. For this session.
function Store.Carried(acct, store, ranges)
	local key = Store.Key(acct, store)
	if not key or key ~= Store.Own() then
		return
	end
	local list = Ranges.Parse(ranges)
	for n in pairs(E.data.mine) do
		if Ranges.Contains(list, n) then
			carried[n] = true
		end
	end
end

-- Mine back under its cap: the oldest pages go, the ones a relay is known to carry first. The
-- number dropped. (On its own after every packed page and at the start.)
function Store.Trim()
	Counted()
	if bytes.mine <= MINE_CAP then
		return 0
	end
	local list, count = {}, 0
	for n in pairs(E.data.mine) do
		list[#list + 1] = n
	end
	table.sort(list)
	for pass = 1, 2 do -- first the ones a relay carries, then any
		for _, n in ipairs(list) do
			if bytes.mine > MINE_CAP and (pass == 2 or carried[n]) and DropMine(n) then
				count = count + 1
			end
		end
	end
	if count > 0 then
		Changed()
	end
	return count
end

---------------------------------------------------------------------------
-- Closing and packing my pages
---------------------------------------------------------------------------

-- Pages.lua closes page n (started at t0, ended at e: its last line's time; nil: now): its text
-- (ending in its "." line) is kept as plain text, waiting to be packed (q), not out yet (o = 0), and
-- n is the last closed page's number now. s: the session it closed in, offered from the next one
-- on; onDisk (closed as stale at login from the saved text, which any later load closes the same
-- way): the session before, offered at once. A number friends hold already (E.data.top: my numbering
-- went back) or kept here: it closes above them, its header renumbered (plain text still). The
-- number it's kept under.
function Store.Close(n, t0, text, onDisk, e)
	Counted()
	local data = E.data
	local top = math.max(data.n, Told())
	if n <= top or data.mine[n] then
		local new = top + 1
		while data.mine[new] do
			new = new + 1
		end
		text, n = Renumbered(text, n, new), new
		moved = moved + 1
	end
	bytes.mine = bytes.mine + #text
	data.mine[n] = { t = t0, e = type(e) == "number" and e or E.Now(), m = "t", z = text, q = 1, s = onDisk and data.session - 1 or data.session,
		o = 0 }
	if n > data.n then
		data.n = n
	end
	queue[#queue + 1] = n
	Changed()
	return n
end

-- Base64 of s, or nil if it didn't work.
local function Base64(util, s, variant)
	local ok, z = pcall(util.EncodeBase64, s, variant)
	if ok and type(z) == "string" and not issecret(z) and z ~= "" and not z:find("[^A-Za-z0-9%+/=]") then
		return z
	end
end

-- A page's text packed: "z", Base64 of its zlib; "r", Base64 of the text (compressing failed);
-- "t", the text (Base64 failed too). Looked up when it runs (tests replace them).
function Store.Pack(text)
	local util = C_EncodingUtil
	if type(util) == "table" and util.EncodeBase64 then
		local methods, variants = Enum and Enum.CompressionMethod, Enum and Enum.Base64Variant
		local variant = variants and variants.Standard or 0
		if util.CompressString then
			local ok, packed = pcall(util.CompressString, text, methods and methods.Zlib or 1)
			if ok and type(packed) == "string" and not issecret(packed) and packed ~= "" then
				local z = Base64(util, packed, variant)
				if z then
					return "z", z
				end
			end
		end
		local z = Base64(util, text, variant)
		if z then
			return "r", z
		end
	end
	return "t", text
end

-- The oldest page waiting: packed, hashed (LT.Hash32 of what's stored), then mine back under its cap.
local function PackNext()
	local n = table.remove(queue, 1)
	local page = E.data.mine[n]
	if type(page) ~= "table" or not page.q then
		return
	end
	local text = page.z
	local m, z = Store.Pack(text)
	page.m, page.z, page.h, page.q = m, z, LT.Hash32(z), nil
	bytes.mine = bytes.mine - #text + #z
	Changed() -- (it can be shared now)
	Store.Trim()
end

---------------------------------------------------------------------------
-- After the start: the launch day, old relayed pages, the receipt, the cap; one a tick
---------------------------------------------------------------------------

-- Pages from before the launch day go (only on the release, once LT.LAUNCH_DAY is set).
local function LaunchDay()
	if not LT.BeforeLaunch(0) then
		return
	end
	local data, dropped = E.data, false
	for n, page in pairs(data.mine) do
		if type(page.t) ~= "number" or LT.BeforeLaunch(page.t) then
			dropped = DropMine(n) or dropped
		end
	end
	for _, where in ipairs({ "carry", "inbox" }) do
		for key, pages in pairs(data[where]) do
			for n, page in pairs(pages) do
				if type(page.t) ~= "number" or LT.BeforeLaunch(page.t) then
					dropped = Remove(where, key, n) or dropped
				end
			end
		end
	end
	if dropped then
		Changed()
	end
end

-- Relayed pages go after 30 days.
local function Expire()
	local now, dropped = E.Now(), false
	for key, pages in pairs(E.data.carry) do
		for n, page in pairs(pages) do
			local at = type(page.a) == "number" and page.a or page.t
			if type(at) ~= "number" or now - at > CARRY_SECONDS then
				dropped = Remove("carry", key, n) or dropped
			end
		end
	end
	if dropped then
		Changed()
	end
end

-- What collectors hold of a store goes 60 days after it was last heard of first-hand (Store.Mentioned),
-- unless pages of it are here: my own while I hold any, the ones I relay or collected (they're
-- heard of now). An entry from before the rule gets its 60 days from now. The status's names and
-- newest pages go with the stores nothing is kept of any more (names: in inbox, exported,
-- provisional, safe or carry; newest pages: a collector's, in the first three), and broken ones.
local function Forget()
	local data, now, heard = E.data, E.Now(), Heard()
	local own, dropped = Store.Own(), false
	for key in pairs(data.safe) do
		if (key == own and next(data.mine) ~= nil) or data.carry[key] ~= nil or data.inbox[key] ~= nil
			or type(heard[key]) ~= "number" then
			heard[key] = now
		elseif now - heard[key] > SAFE_AGE then
			data.safe[key], heard[key] = nil, nil
			dropped = true
		end
	end
	for key in pairs(heard) do
		if data.safe[key] == nil then
			heard[key] = nil
		end
	end
	local provisional = type(data.provisional) == "table" and data.provisional or {}
	local names, latest = Kept("names"), Kept("latest")
	for key, newest in pairs(latest) do
		if type(newest) ~= "table" or type(newest.n) ~= "number" or type(newest.t) ~= "number"
			or not (data.inbox[key] or data.exported[key] or provisional[key]) then
			latest[key] = nil
		end
	end
	for key, name in pairs(names) do
		if type(name) ~= "string" or not (data.inbox[key] or data.exported[key] or provisional[key] or data.safe[key] or data.carry[key]) then
			names[key] = nil
		end
	end
	if dropped then
		Changed()
	end
end

-- The exporter has these pages of acct.store (a receipt's done: a version of each from a disk; early:
-- only copies that came early, provisional ones); upto: the latest arrival (a) of my inbox it read,
-- nil if it doesn't say (an older exporter). Inbox pages in done go if it read them (arrived by upto):
-- a provisional one into provisional (its hash), any other into exported (and out of provisional: the
-- page with that number from a disk is archived now). Without upto every one goes, except a page from
-- a disk whose number is provisional: it came after a provisional page of that number that the
-- receipt took, so the receipt may be older than it. A number of done with no inbox page goes into
-- exported unless it's provisional; one kept in the inbox doesn't. Carry and mine: done goes.
--
-- early: only my provisional inbox pages in it go (by the same rule), into provisional; nothing else.
-- Its numbers never go into exported, and nothing is dropped for them: the author may have lost
-- that page in a crash and used its number again for another (the exporter doesn't have that one),
-- and a page from a disk here with such a number is one the exporter hasn't read.
local function Take(acct, store, key, done, early, upto)
	local data = E.data
	local list, aside = Ranges.Parse(done or ""), Ranges.Parse(early or "")
	local inbox, provisional = data.inbox[key], ProvisionalOf(key)
	local taken, kept = {}, {}
	for n, page in pairs(type(inbox) == "table" and inbox or {}) do
		local listed = Ranges.Contains(list, n)
		if listed or (Pending(page) and Ranges.Contains(aside, n)) then
			local take
			if upto then
				take = (type(page.a) == "number" and page.a or 0) <= upto
			else
				take = Pending(page) or not (provisional and provisional[n])
			end
			if take then
				taken[#taken + 1] = n
			elseif listed then
				kept[#kept + 1] = { n, n }
			end
		end
	end
	for _, n in ipairs(taken) do
		local page = inbox[n]
		if Pending(page) then
			ProvisionalOf(key, true)[n] = type(page.h) == "string" and page.h or ""
		elseif provisional then
			provisional[n] = nil
		end
		Remove("inbox", key, n)
	end
	provisional = ProvisionalOf(key)
	if provisional and next(provisional) == nil then
		data.provisional[key] = nil
	end
	local add = Ranges.Minus(list, Ranges.Union(Merge(kept), provisional and Ranges.Of(provisional) or ""))
	local exported = add ~= "" and Ranges.Union(data.exported[key], add) or data.exported[key]
	if taken[1] or exported ~= data.exported[key] then
		data.exported[key] = exported
		Changed()
	end
	if list[1] then
		Drop(acct, store, list, "carry")
		Drop(acct, store, list, "mine", true) -- (my own exporter has them)
	end
end

-- A receipt's ranges for a key: the string, nil if it isn't one or lists nothing.
local function Listed(ranges)
	if type(ranges) == "string" and Ranges.Format(ranges) ~= "" then
		return ranges
	end
end

-- The exporter's receipt (collecting only): its addon loaded (load on demand; nothing if the folder
-- isn't there), the pages it lists dropped from inbox (the ones it read), carry and mine, and kept in
-- exported (Take). upto["<store>"]: the latest arrival of that store's inbox the exporter read (a
-- store it didn't read: none of its inbox goes). early (a newer exporter's): numbers it has only from
-- copies that came early; only my provisional pages of them go aside (no early: an older exporter,
-- whose done lists those too).
local function Receipt()
	local data = E.data
	receiptSession = data.session
	local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
	if load then
		pcall(load, RECEIPT)
	end
	local receipt = _G.LefthyToolsEchoesReceipt
	if type(receipt) ~= "table" or type(receipt.done) ~= "table" then
		return
	end
	Counted()
	local upto
	if type(receipt.upto) == "table" then
		upto = receipt.upto[data.store]
		upto = type(upto) == "number" and upto or -1
	end
	local early = type(receipt.early) == "table" and receipt.early or {}
	local keys = {}
	for _, list in ipairs({ receipt.done, early }) do
		for key in pairs(list) do
			keys[key] = true
		end
	end
	for key in pairs(keys) do
		local acct, store
		if type(key) == "string" then
			acct, store = key:match("^(%x+)%.(%x+)$")
		end
		local done, aside = Listed(receipt.done[key]), Listed(early[key])
		if acct and Store.Key(acct, store) == key and (done or aside) then
			Take(acct, store, key, done, aside, upto)
		end
	end
end

-- The collector's inbox at 4 MB: one chat line a session asks to run the exporter.
local function Note()
	if bytes.inbox >= INBOX_NOTE and notedSession ~= E.data.session then
		notedSession = E.data.session
		M:Print(("the recordings you collected take %.1f MB: run the exporter on this computer (it frees the space). At 8 MB collecting pauses.")
			:format(bytes.inbox / KB / KB))
	end
end

E.When("start", function()
	Store.Recount()
	wipe(queue)
	wipe(carried)
	for n, page in pairs(E.data.mine) do
		if page.q then
			queue[#queue + 1] = n
		end
	end
	table.sort(queue)
	chores = { LaunchDay, Expire, Forget, Store.Trim, Note }
	noteDue, moved = false, 0
end)

-- One thing a tick: a page packed, or else a chore; the receipt once a session while collecting.
E.OnTick(function()
	if queue[1] then
		PackNext()
		return
	end
	local chore = table.remove(chores, 1)
	if chore then
		chore()
	elseif M.db.collect and receiptSession ~= E.data.session then
		Receipt()
	elseif noteDue then
		noteDue = false
		Note()
	end
end)

---------------------------------------------------------------------------
-- /lefthy echoes: the status, and words other files add (E.Command, E.OnStatus)
---------------------------------------------------------------------------

local commands, helps = {}, {}
local statusHooks, statusNames = {}, {}

-- "/lefthy echoes <word> ..." runs fn(rest); help is its line in the list.
function E.Command(word, fn, help)
	commands[word:lower()] = fn
	if help then
		helps[#helps + 1] = help
	end
end

-- fn(add) while the status is printed: add(text) prints one more line (through LT.Guard).
function E.OnStatus(fn)
	statusHooks[#statusHooks + 1] = fn
	statusNames[#statusHooks] = "E.OnStatus " .. #statusHooks
end

local function Amount(n)
	if n >= KB * KB then
		return ("%.1f MB"):format(n / KB / KB)
	end
	return ("%.1f KB"):format(n / KB)
end

local function Line(text)
	M:Print("  " .. text)
end

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

-- A time of the realm's clock (E.Now()) as this computer shows it: "21:30" today, "Nov 1 21:30"
-- another day; more than a day ago, it says so (", 3 days ago").
local function When(t)
	local ok, at = pcall(date, "*t", t)
	if not ok or type(at) ~= "table" then
		return "?" -- (a broken saved time)
	end
	local now = E.Now()
	local today = date("*t", now)
	local text = ("%02d:%02d"):format(at.hour, at.min)
	if at.year ~= today.year or at.yday ~= today.yday then
		text = ("%s %d %s"):format(MONTHS[at.month] or "?", at.day, text)
	end
	local days = math.floor((now - t) / 86400)
	if days >= 1 then
		text = text .. (", %d day%s ago"):format(days, days == 1 and "" or "s")
	end
	return text
end

local function PageCount(n)
	return n == 1 and "1 page" or n .. " pages"
end

local function PageNumber(n)
	return type(n) == "number" and n >= 1 and n <= MAX_N and n == math.floor(n)
end

-- How many page numbers a parsed list has (never spelled out).
local function Numbers(list)
	local n = 0
	for _, r in ipairs(list) do
		n = n + r[2] - r[1] + 1
	end
	return n
end

-- A parsed list for a status line: "212-214", "1-50,52-57"; in more than 3 pieces, the first and
-- the last number and how many gaps ("1-900 with 11 gaps").
local function Span(list)
	if #list <= 3 then
		return Ranges.Format(list)
	end
	return ("%d-%d with %d gaps"):format(list[1][1], list[#list][2], #list - 1)
end

-- My own pages: how far my recording is safe at a collector (safeTo), what still waits to reach
-- one (and what of it went early), and what's kept of it.
local function MineStatus(data)
	local to = data.safeTo
	if type(to) == "table" and type(to.n) == "number" and type(to.e) == "number" then
		Line(("your recording is safe at a collector up to %s (page %d)."):format(When(to.e), to.n))
	else
		Line("no page of yours has reached a collector yet.")
	end
	local count, oldest, packing, later, early = 0, nil, 0, 0, 0
	for n, page in pairs(data.mine) do
		if PageNumber(n) then
			count = count + 1
			if type(page.t) == "number" and (not oldest or page.t < oldest) then
				oldest = page.t
			end
			packing = packing + (page.q and 1 or 0)
			later = later + (OnDisk(page) and 0 or 1)
			early = early + ((not OnDisk(page) and page.o == 1) and 1 or 0)
		end
	end
	if count == 0 then
		Line("none of your pages waits to reach a collector.")
	else
		Line(("%s waiting to reach a collector (%s)%s%s."):format(PageCount(count), Span(Ranges.Parse(Ranges.Of(data.mine))),
			oldest and ", recorded since " .. When(oldest) or "",
			early > 0 and ("; %d of them sent early to a collector, safe once confirmed"):format(early) or ""))
	end
	if count > 0 or moved > 0 then
		Line(("my pages: %s of %s%s%s%s."):format(Amount(bytes.mine), Amount(MINE_CAP),
			packing > 0 and (", %d waiting to be packed"):format(packing) or "",
			later > 0 and (", %d offered from the next session on (a /reload is one)"):format(later) or "",
			moved > 0 and (", %d moved to a new number this session (friends hold another page with theirs: a WTF folder restored, or copied?)"):format(moved) or ""))
	end
end

-- A collector's lines, one per friend's store with anything collected, exported or provisional (my
-- own account's other computers too; not this one's: the lines above): how many pages, up to when
-- (the newest one's start: latest, or the inbox), and how far they're confirmed. The 10 whose newest
-- page is newest, sorted by name; stores whose newest page is over 30 days old left out.
local function FriendsStatus(data)
	local own, now = Store.Own(), E.Now()
	local names = type(data.names) == "table" and data.names or {}
	local latest = type(data.latest) == "table" and data.latest or {}
	local provisional = type(data.provisional) == "table" and data.provisional or {}
	local keys = {}
	for _, where in ipairs({ data.inbox, data.exported, provisional }) do
		for key in pairs(where) do
			keys[key] = true
		end
	end
	local rows, old = {}, 0
	for key in pairs(keys) do
		local acct, store
		if type(key) == "string" then
			acct, store = key:match("^(%x+)%.(%x+)$")
		end
		if acct and key ~= own and Store.Key(acct, store) == key then
			local exported = Ranges.Parse(type(data.exported[key]) == "string" and data.exported[key] or "")
			local all = {}
			for i, r in ipairs(exported) do
				all[i] = { r[1], r[2] }
			end
			local newest = type(latest[key]) == "table" and type(latest[key].t) == "number" and latest[key].t or nil
			local inbox = type(data.inbox[key]) == "table" and data.inbox[key] or {}
			local row = { key = key, acct = acct, store = store, exported = Numbers(exported), disk = 0, fresh = 0, early = 0 }
			for n, page in pairs(inbox) do
				if PageNumber(n) and type(page) == "table" then
					all[#all + 1] = { n, n }
					if Pending(page) then
						row.early = row.early + 1
					elseif type(page.s) == "number" and page.s < data.session then
						row.disk = row.disk + 1
					else
						row.fresh = row.fresh + 1
					end
					if type(page.t) == "number" and (not newest or page.t > newest) then
						newest = page.t -- (one that came before latest was kept)
					end
				end
			end
			local taken = provisional[key]
			for n, h in pairs(type(taken) == "table" and taken or {}) do
				if PageNumber(n) and type(h) == "string" and not inbox[n] then -- (an inbox page n from a disk counts)
					all[#all + 1] = { n, n }
					row.early = row.early + 1
				end
			end
			row.all, row.newest = Merge(all), newest
			if not row.all[1] then
				row = nil
			elseif newest and now - newest > SHOWN_AGE then
				old, row = old + 1, nil
			end
			if row then
				row.name = acct == data.acct and "you (" .. store .. ")" or type(names[key]) == "string" and names[key] or acct
				rows[#rows + 1] = row
			end
		end
	end
	table.sort(rows, function(a, b)
		local x, y = a.newest or -math.huge, b.newest or -math.huge
		if x ~= y then
			return x > y
		end
		return a.key < b.key
	end)
	local shown, seen = {}, {}
	for i = 1, math.min(#rows, SHOWN) do
		shown[i] = rows[i]
		seen[rows[i].name] = (seen[rows[i].name] or 0) + 1
	end
	table.sort(shown, function(a, b)
		local x, y = a.name:lower(), b.name:lower()
		if x ~= y then
			return x < y
		end
		return a.key < b.key
	end)
	for _, row in ipairs(shown) do
		local parts = {}
		if row.exported > 0 then
			parts[#parts + 1] = row.exported .. " exported"
		end
		if row.disk > 0 then
			parts[#parts + 1] = row.disk .. " on disk"
		end
		if row.fresh > 0 then
			parts[#parts + 1] = row.fresh .. " not on disk yet (safe after your logout or /reload)"
		end
		if row.early > 0 then
			parts[#parts + 1] = ("%d sent early (confirmed once %s game saved it)"):format(row.early,
				row.acct == data.acct and "that computer's" or row.name .. "'s")
		end
		Line(("  %s: %s (%s)%s; %s."):format(seen[row.name] > 1 and ("%s (%s)"):format(row.name, row.store) or row.name,
			PageCount(Numbers(row.all)), Span(row.all), row.newest and " up to " .. When(row.newest) or "", table.concat(parts, ", ")))
	end
	if #rows > SHOWN then
		Line(("  ... and %d more."):format(#rows - SHOWN))
	end
	if old > 0 then
		Line(("  (%d older not shown: nothing from them in 30 days.)"):format(old))
	end
end

local function Status()
	Store.Recount()
	local data = E.data
	if E.recording then
		M:Print("recording.")
	elseif LT.world == "beta" and M.enabled then
		M:Print("idle on the beta: nothing recorded there counts.")
	else
		M:Print("switched off: nothing is recorded.")
	end
	Line(data.acct and ("account %s, store %s."):format(data.acct, data.store)
		or ("store %s; your BattleTag isn't known yet."):format(data.store))
	local open = data.open
	if type(open) == "table" and type(open.text) == "string" then
		local size, lines = #open.text, select(2, open.text:gsub("\n", "\n"))
		if E.recording and open.buffer == E.buffer then
			size, lines = E.bytes, E.count
		end
		local idle = type(open.own) == "number" and lines <= open.own -- (Pages.lua: it doesn't close by time)
		Line(("open page %d: %s, %d lines, started %d min ago%s."):format(open.n or 0, Amount(size), lines,
			math.max(0, math.floor((E.Now() - (open.t0 or E.Now())) / 60)), idle and "; nothing recorded on it yet, so it stays open" or ""))
	else
		Line("no open page.")
	end
	MineStatus(data)
	local relayed = 0
	for _, pages in pairs(data.carry) do
		relayed = relayed + Count(pages)
	end
	if M.db.relay or relayed > 0 then
		Line(("relaying: %d pages of %d friends' stores, %s of %s."):format(relayed, Count(data.carry), Amount(bytes.carry), Amount(CARRY_CAP)))
	end
	if M.db.collect or next(data.inbox) or next(data.exported) or (type(data.provisional) == "table" and next(data.provisional)) then
		local received = 0
		for _, pages in pairs(data.inbox) do
			received = received + Count(pages)
		end
		Line(("collected: %d pages of %d stores, %s%s; the exporter has %d stores' pages."):format(received, Count(data.inbox),
			Amount(bytes.inbox), bytes.inbox >= INBOX_FULL and " (8 MB: collecting pauses until the exporter ran)"
			or bytes.inbox >= INBOX_NOTE and " (over 4 MB: run the exporter)" or "", Count(data.exported)))
		FriendsStatus(data)
	end
	for i = 1, #statusHooks do
		LT.Guard(statusNames[i], statusHooks[i], Line)
	end
end

function M:OnSlashCommand(msg)
	local word, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
	word = word:lower()
	if word == "" or word == "status" then
		Status()
	elseif commands[word] then
		commands[word](rest)
	else
		M:Print("/lefthy echoes [status] - what's recorded and kept, in numbers")
		for _, help in ipairs(helps) do
			M:Print(help)
		end
	end
end
