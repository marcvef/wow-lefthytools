local _, ns = ...
local LT = ns.LT
local E = ns.Echoes
local M = E.module

-- Storage: the closed pages in LefthyToolsEchoesDB (E.data) and what is kept of them (docs/echoes.md,
-- Pages and storage). Pages.lua closes a page with E.Store.Close (plain text, queued); the tick packs
-- one queued page at a time (zlib, Base64, LT.Hash32), never inside an event handler.
--
--   mine     my own closed pages, kept until a collector holds them: 2 MB at most, then the oldest
--            go, the ones a relay is known to carry first
--   carry    friends' pages I relay: 512 KB, 128 KB per author, 30 days
--   inbox    a collector's received pages, dropped only by the exporter's receipt; a chat line at
--            4 MB asks to run the exporter, at 8 MB pulling pauses (E.Store.InboxFull)
--   safe     what collectors hold safely, per author; exported: what the receipts listed
--
-- Pages from before the launch day go. E.Ranges: page numbers as range strings ("1-56,58").
-- E.Store: the pages' API for the delivery; every change to mine, carry and inbox goes through it
-- (it keeps their sizes). The game never decompresses a page: only the exporter does.

local KB = 1024
local MINE_CAP = 2048 * KB                    -- my pages
local CARRY_CAP, CARRY_AUTHOR = 512 * KB, 128 * KB -- relayed pages, in all and per author
local CARRY_SECONDS = 30 * 86400              -- a relayed page is dropped after 30 days
local INBOX_NOTE, INBOX_FULL = 4096 * KB, 8192 * KB -- the collector: ask for the exporter; pause
local PAGE_MAX = 64 * KB                      -- a stored page (its z) is at most this
local AHEAD = 86400                           -- a page may start at most a day ahead
local MAX_N = 999999999                       -- page numbers are 1 to this
local RECEIPT = "LefthyTools_EchoesReceipt"   -- the exporter's load-on-demand addon, on the collector's PC

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
-- Sizes: the bytes of the stored strings (z), kept as pages come and go; counted anew for a new
-- saved table (a load) and by the status command.
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

local function Size(page)
	return type(page) == "table" and type(page.z) == "string" and #page.z or 0
end

-- The sizes counted anew (a page that isn't one is dropped on the way).
function Store.Recount()
	local data = E.data
	countedFor = data
	bytes.mine, bytes.carry, bytes.inbox = 0, 0, 0
	wipe(carryBy)
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

-- for n, page in E.Store.Mine(): my shareable pages, oldest (lowest n) first.
function Store.Mine()
	local list = {}
	for n, page in pairs(E.data.mine) do
		if type(n) == "number" and Shareable(page) then
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
-- shareable).
function Store.Page(acct, store, n)
	local key = Store.Key(acct, store)
	if not key or type(n) ~= "number" then
		return nil
	end
	if key == Store.Own() then
		local page = E.data.mine[n]
		if Shareable(page) then
			return page, "mine"
		end
		return nil
	end
	for _, where in ipairs({ "inbox", "carry" }) do
		local list = E.data[where][key]
		if list and list[n] then
			return list[n], where
		end
	end
end

-- What I hold of where ("mine", "carry", "inbox") as { ["acct.store"] = "ranges" } (mine: its
-- shareable pages, under my key; nothing while my BattleTag isn't known).
function Store.Held(where)
	local out = {}
	if where == "mine" then
		local own = Store.Own()
		local ranges = own and Ranges.Of(E.data.mine, function(_, page) return Shareable(page) end)
		if ranges and ranges ~= "" then
			out[own] = ranges
		end
	else
		for key, pages in pairs(E.data[where]) do
			out[key] = Ranges.Of(pages)
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

-- Whether a collector holds page n of key safely (a summary told so).
local function SafeSomewhere(key, n)
	for _, ranges in pairs(E.data.safe[key] or {}) do
		if Ranges.Contains(ranges, n) then
			return true
		end
	end
	return false
end

-- A friend's page received: where "carry" (relaying) or "inbox" (collecting). page = { t (its
-- start), h (LT.Hash32 of z), m ("z" or "r"), z }; it's kept as a copy with s (this session) and,
-- relayed, a (when it came). true, or true and "have" (kept already); false and why not: "id" (a
-- key or number that isn't one), "mine" (my own store's), "page" (not a page: m, z, Base64), "size"
-- (z over 64 KB), "time" (before the launch or more than a day ahead), "hash" (h doesn't match),
-- "exported" (the exporter has it), "safe" (relaying: a collector holds it), "full" (relaying: no
-- room, E.Store.Fits).
function Store.Put(acct, store, n, page, where)
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
	list[n] = { t = page.t, h = page.h, m = page.m, z = page.z, s = data.session, a = where == "carry" and E.Now() or nil }
	bytes[where] = bytes[where] + #page.z
	if where == "carry" then
		carryBy[key] = (carryBy[key] or 0) + #page.z
	elseif bytes.inbox >= INBOX_NOTE then
		noteDue = true -- (said on the tick)
	end
	return true
end

-- Drops pages of acct.store: those in ranges (nil: all), from where (nil: mine, carry and inbox;
-- mine only for my own key). The number dropped.
function Store.Drop(acct, store, ranges, where)
	Counted()
	local key = Store.Key(acct, store)
	if not key then
		return 0
	end
	local list = ranges ~= nil and Ranges.Parse(ranges)
	local count = 0
	for _, w in ipairs(where and { where } or WHERE) do
		local pages = Pages(w, key)
		for n in pairs(pages or {}) do
			if (not list or Ranges.Contains(list, n)) and Remove(w, key, n) then
				count = count + 1
			end
		end
	end
	return count
end

-- A collector (its "acct.store") holds these pages of acct.store safely (its summary, merged into
-- E.data.safe): they go from mine and carry. The number dropped.
function Store.Safe(acct, store, ranges, collector)
	local key = Store.Key(acct, store)
	if not key or type(collector) ~= "string" or issecret(collector) or collector == "" then
		return 0
	end
	local safe = E.data.safe
	safe[key] = type(safe[key]) == "table" and safe[key] or {}
	safe[key][collector] = Ranges.Union(safe[key][collector], ranges)
	return Store.Drop(acct, store, ranges, "mine") + Store.Drop(acct, store, ranges, "carry")
end

-- What this collector holds safely of acct.store, as ranges: received in an earlier session (on
-- disk) or exported.
function Store.SafeHere(acct, store)
	local key = Store.Key(acct, store)
	if not key then
		return ""
	end
	local session = E.data.session
	local onDisk = Ranges.Of(E.data.inbox[key], function(_, page)
		return type(page.s) == "number" and page.s < session
	end)
	return Ranges.Union(E.data.exported[key], onDisk)
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
	return count
end

---------------------------------------------------------------------------
-- Closing and packing my pages
---------------------------------------------------------------------------

-- Pages.lua closes page n (started at t0): its text (ending in its "." line) is kept as plain text,
-- waiting to be packed (q), and n is the last closed page's number now.
function Store.Close(n, t0, text)
	Counted()
	local data = E.data
	bytes.mine = bytes.mine - Size(data.mine[n]) + #text
	data.mine[n] = { t = t0, m = "t", z = text, q = 1 }
	if n > data.n then
		data.n = n
	end
	queue[#queue + 1] = n
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
	local data = E.data
	for n, page in pairs(data.mine) do
		if type(page.t) ~= "number" or LT.BeforeLaunch(page.t) then
			DropMine(n)
		end
	end
	for _, where in ipairs({ "carry", "inbox" }) do
		for key, pages in pairs(data[where]) do
			for n, page in pairs(pages) do
				if type(page.t) ~= "number" or LT.BeforeLaunch(page.t) then
					Remove(where, key, n)
				end
			end
		end
	end
end

-- Relayed pages go after 30 days.
local function Expire()
	local now = E.Now()
	for key, pages in pairs(E.data.carry) do
		for n, page in pairs(pages) do
			local at = type(page.a) == "number" and page.a or page.t
			if type(at) ~= "number" or now - at > CARRY_SECONDS then
				Remove("carry", key, n)
			end
		end
	end
end

-- The exporter's receipt (collecting only): its addon loaded (load on demand; nothing if the folder
-- isn't there), the pages it lists dropped from inbox, carry and mine, and kept in exported.
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
	for key, ranges in pairs(receipt.done) do
		local acct, store
		if type(key) == "string" then
			acct, store = key:match("^(%x+)%.(%x+)$")
		end
		if acct and Store.Key(acct, store) == key and type(ranges) == "string" and Ranges.Format(ranges) ~= "" then
			data.exported[key] = Ranges.Union(data.exported[key], ranges)
			Store.Drop(acct, store, ranges)
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
	chores = { LaunchDay, Expire, Store.Trim, Note }
	noteDue = false
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

local function Count(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end

local function Line(text)
	M:Print("  " .. text)
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
	local count, waiting = 0, 0
	for _, page in pairs(data.mine) do
		count = count + 1
		waiting = waiting + (page.q and 1 or 0)
	end
	Line(("my pages: %d (%s), %s of %s%s."):format(count, count > 0 and Ranges.Of(data.mine) or "none", Amount(bytes.mine),
		Amount(MINE_CAP), waiting > 0 and (", %d waiting to be packed"):format(waiting) or ""))
	local relayed = 0
	for _, pages in pairs(data.carry) do
		relayed = relayed + Count(pages)
	end
	if M.db.relay or relayed > 0 then
		Line(("relaying: %d pages of %d friends' stores, %s of %s."):format(relayed, Count(data.carry), Amount(bytes.carry), Amount(CARRY_CAP)))
	end
	if M.db.collect or next(data.inbox) or next(data.exported) then
		local received = 0
		for _, pages in pairs(data.inbox) do
			received = received + Count(pages)
		end
		Line(("collected: %d pages of %d stores, %s%s; the exporter has %d stores' pages."):format(received, Count(data.inbox),
			Amount(bytes.inbox), bytes.inbox >= INBOX_FULL and " (8 MB: collecting pauses until the exporter ran)"
			or bytes.inbox >= INBOX_NOTE and " (over 4 MB: run the exporter)" or "", Count(data.exported)))
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
