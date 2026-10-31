-- Echoes: pages and storage (Pages.lua, Store.lua; docs/echoes.md, Pages and storage): the header and
-- the character line; the lines joined every 60 s and at logout; /reload going on without losing or
-- doubling a line; closing by time, size and lines, on the tick only, one page packed a tick; a stale
-- open page at login; packing through the mock's C_EncodingUtil (Node's real zlib, tests/native.js),
-- the hash and the fallbacks; my BattleTag not known yet; range strings; what's kept (mine, carry,
-- inbox) and the API for the delivery; the exporter's receipt; the launch day; the beta untouched;
-- /lefthy echoes; nothing heavy per tick; the exporter's own readers on the saved file, when the
-- environment variable ECHOES_EXPORTER names the exporter's folder (skipped otherwise). The capture
-- is kept quiet until the last section, where it runs: its lines after the header, a page going on
-- at its last point, its last lines joined at logout and when switched off.
-- Needs: no other file (it starts Echoes itself, on saved tables of its own, and puts back the beta).
local suite = ...
local check, section, ns, LT, lefthy, printedSince = suite.check, suite.section, suite.ns, suite.LT, suite.lefthy, suite.printedSince
local E = ns.Echoes
local M = LT:GetModule("echoes")
local Store, Ranges = E.Store, E.Ranges
local ZLIB = Enum.CompressionMethod.Zlib
local STORE = "9f3a61c2" -- this WTF folder's store, in these tests

---------------------------------------------------------------------------
-- The tests' tools
---------------------------------------------------------------------------

-- The realm's clock: the mock's, plus skew (time passing while logged out, or a jump ahead).
local skew = 0
local serverTime = GetServerTime
GetServerTime = function() return time() + skew end

-- The heavy work counted: packing (CompressString), hashing (LT.Hash32) and closing (E.Store.Close),
-- and whether any of it ran inside an event handler (depth: inside Fire, or a start at login, which
-- in the game runs inside PLAYER_LOGIN).
local depth, heavyInEvent = 0, 0
local compressCalls, hashCalls, closes = 0, 0, 0
local lastClosed -- the text of the page closed last
local realFire, realHash, realClose = Fire, LT.Hash32, Store.Close
local encoding = C_EncodingUtil
local realCompress, realEncode = encoding.CompressString, encoding.EncodeBase64
local function inEvent(fn, ...)
	depth = depth + 1
	local ok, err = pcall(fn, ...)
	depth = depth - 1
	if not ok then error(err, 0) end
end
Fire = function(...) inEvent(realFire, ...) end
LT.Hash32 = function(text)
	if #text > 64 then -- (a page's; my BattleTag's hash is no work)
		hashCalls = hashCalls + 1
		heavyInEvent = heavyInEvent + (depth > 0 and 1 or 0)
	end
	return realHash(text)
end
local function countedCompress(...)
	compressCalls = compressCalls + 1
	heavyInEvent = heavyInEvent + (depth > 0 and 1 or 0)
	return realCompress(...)
end
encoding.CompressString = countedCompress
Store.Close = function(n, t0, text, ...)
	closes, lastClosed = closes + 1, text
	return realClose(n, t0, text, ...)
end

-- The most packed and closed in one tick since resetTicks() (a subscriber after the pages' own).
local most, seenCompress, seenCloses = { compress = 0, close = 0 }, 0, 0
local function resetTicks()
	most.compress, most.close, seenCompress, seenCloses = 0, 0, compressCalls, closes
end
E.OnTick(function()
	most.compress = math.max(most.compress, compressCalls - seenCompress)
	most.close = math.max(most.close, closes - seenCloses)
	seenCompress, seenCloses = compressCalls, closes
end)
local function tick() Advance(0.25, 0.25) end -- one tick of the driver
-- One tick at the realm's time t (whole seconds): the clock set ahead to it (the mock's time() is
-- whole seconds of GetTime(); the tick comes 0.25 s on).
local function tickAt(t)
	skew = skew + t - (time() + skew + math.floor(GetTime() + 0.25) - math.floor(GetTime()))
	tick()
end

-- The saved table as the game writes it (sorted here, so two writes compare): strings with \\, \",
-- \n, \r and other control bytes as \ddd, everything else as it is.
local ESC = { ["\\"] = "\\\\", ['"'] = '\\"', ["\n"] = "\\n", ["\r"] = "\\r" }
local function Quote(s)
	return '"' .. s:gsub('[%c"\\]', function(c) return ESC[c] or ("\\%03d"):format(c:byte()) end) .. '"'
end
local function Write(v, indent, out)
	local kind = type(v)
	if kind == "string" then
		out[#out + 1] = Quote(v)
	elseif kind == "number" then
		out[#out + 1] = v == math.floor(v) and ("%d"):format(v) or ("%.17g"):format(v)
	elseif kind == "boolean" then
		out[#out + 1] = tostring(v)
	elseif kind == "table" then
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = k end
		table.sort(keys, function(a, b)
			if type(a) == type(b) then return a < b end
			return type(a) == "number"
		end)
		out[#out + 1] = "{\n"
		for _, k in ipairs(keys) do
			out[#out + 1] = indent .. "\t[" .. (type(k) == "number" and ("%d"):format(k) or Quote(k)) .. "] = "
			Write(v[k], indent .. "\t", out)
			out[#out + 1] = ",\n"
		end
		out[#out + 1] = indent .. "}"
	else
		out[#out + 1] = "nil"
	end
end
local function Saved()
	local out = { "LefthyToolsEchoesDB = " }
	Write(LefthyToolsEchoesDB, "", out)
	out[#out + 1] = "\n"
	return table.concat(out)
end

-- The capture (Path.lua, Events.lua, Changes.lua) kept quiet until the last section, so only the
-- pages' own lines and the tests' are written: nowhere to be (no position), and after each start a
-- loading screen that doesn't end (it writes nothing until its session's anchor, and nothing at
-- logout or when switched off while that anchor is still to come).
local realPosition = LT.Position
LT.Position = function() return nil end
-- (A page doesn't close while the capture waits for its anchor, E.PageMayClose: for the quiet capture
-- it may, until the last sections.)
local realMayClose = E.PageMayClose
E.PageMayClose = function() return true end
local function start()
	inEvent(LT.SetModuleEnabled, LT, "echoes", true)
	Fire("PLAYER_LEAVING_WORLD")
end

-- Echoes on a saved table of its own: as a first install would make it (session: each fresh table
-- another number, as the module's once-a-session things go by it), recording.
local sessions = 1000
local function fresh(acct)
	LT:SetModuleEnabled("echoes", false)
	LT.world = nil -- (a client that isn't the beta: it records)
	E.buffer, E.state, E.bytes, E.count = {}, { anchored = false, names = {} }, 0, 0
	sessions = sessions + 100
	LefthyToolsEchoesDB = { v = 1, store = STORE, acct = acct, session = sessions, n = 0, mine = {}, carry = {}, safe = {}, inbox = {},
		exported = {}, capture = {}, friends = {} }
	E.data = LefthyToolsEchoesDB
	start()
end

-- A /reload (or a login offline seconds later): the logout's handlers run while recording (unless
-- loggedOut: the test fired it), the saved table is written and read back as the game does (through
-- its text), the old interface goes (Lines.lua's buffer and state are new), Echoes' load counts a
-- new session, and it records again. The saved file's text. lastSave: a crash instead: nothing is
-- written, the next load reads the file the game saved last (that text).
local function reload(offline, loggedOut, lastSave)
	if not loggedOut and not lastSave then
		Fire("PLAYER_LOGOUT")
	end
	local text = lastSave or Saved()
	LT:SetModuleEnabled("echoes", false) -- (the old interface: what it does now isn't saved)
	E.buffer, E.state, E.bytes, E.count = {}, { anchored = false, names = {} }, 0, 0
	skew = skew + (offline or 0)
	assert(load(text))()
	LefthyToolsEchoesDB.session = LefthyToolsEchoesDB.session + 1
	E.data = LefthyToolsEchoesDB
	start()
	return text
end

-- A page's text: unpacked as the exporter does (the game never does).
local function textOf(page)
	if page.m == "z" then
		return encoding.DecompressString(encoding.DecodeBase64(page.z), ZLIB)
	elseif page.m == "r" then
		return encoding.DecodeBase64(page.z)
	end
	return page.z
end
local function linesOf(text)
	local list = {}
	for line in text:gmatch("([^\n]*)\n") do list[#list + 1] = line end
	return list
end
-- Every line with its time: t0 from the header, then each line's dt (a clock line sets it).
local function timesOf(text)
	local out, t = {}, nil
	for _, line in ipairs(linesOf(text)) do
		local c = line:sub(1, 1)
		if line:find("^E1;") then
			t = tonumber((select(5, strsplit(";", line))))
		elseif c:find("%d") then
			t = t + tonumber(line:match("^(%d+),"))
		elseif c == "!" then
			t = tonumber(line:match("^!%d+;(%d+)$"))
		else
			t = t + tonumber(line:match("^.(%d+)"))
		end
		out[#out + 1] = { line = line, t = t }
	end
	return out
end
local function count(text, plain)
	local n, at = 0, 1
	while true do
		local i = text:find(plain, at, true)
		if not i then return n end
		n, at = n + 1, i + #plain
	end
end
local function size(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

-- Kills 1..n as lines ("k<dt>;<id>"); written[id] = when.
local function kills(from, to, written)
	for id = from, to do
		E.Line("k", id)
		if written then written[id] = E.Now() end
	end
end
E.On("ECHOES_PAGES_TEST", function(lines, width) -- (an event whose handler writes lines)
	for _ = 1, lines do E.Line("H", ("x"):rep(width)) end
end)

local acct = realHash(("Me#1111"):lower())
local own = acct .. "." .. STORE
local function header(n, t0, a)
	return ("E1;%s;%s;%d;%d;enUS;%s;%s"):format(a or acct, STORE, n, t0, select(2, GetBuildInfo()), LT.version)
end
local function charLine(key, full, guid)
	return ("C0;%s;%s;%s;%s;Human;3;%d;Alliance"):format(key or "Lefthy-Realmy", full or "Lefthy", guid or UnitGUID("player"),
		select(2, UnitClass("player")), UnitLevel("player"))
end

---------------------------------------------------------------------------

section("Echoes pages: the first page")
do
	fresh()
	local t0, open = E.Now(), E.data.open
	check(open and open.n == 1 and open.t0 == t0 and open.char == "Lefthy-Realmy" and open.guid == UnitGUID("player")
		and open.acct == acct and open.text == "" and E.data.acct == acct and E.data.n == 0,
		"recording starts: page 1 is open, mine (my BattleTag known: its hash is kept)")
	check(acct == ns.Chronicle.MyAccount() and Store.Own() == own, "the account is Chronicle's hash of my BattleTag; my pages' key is account.store")
	check(E.buffer[1] == header(1, t0) and E.buffer[2] == charLine() and #E.buffer == 2,
		"its header (format 1, account, store, number, start, locale, build, addon version) and the character line, got\n"
		.. tostring(E.buffer[1]) .. "\n" .. tostring(E.buffer[2]))
	check(E.bytes == #E.buffer[1] + #E.buffer[2] + 2 and E.count == 2, "counted: its bytes (with each \"\\n\") and lines")
	check(open.buffer == E.buffer and open.state == E.state, "the open page keeps the encoder's buffer and state (saved with it)")
	check(E.state.t == t0 and not E.state.anchored, "the next line's time counts from the page's start; points wait for the capture's anchor")

	-- The full name: the surname from the game, or Chronicle's record of it.
	local baseName, chars = UnitName, LefthyToolsChronicleDB.chars
	UnitName = function(unit) if unit == "player" then return "Anna", nil end return baseName(unit) end
	chars["Anna-Realmy"] = { full = "Anna Brook" }
	local c = E.Character()
	check(c.key == "Anna-Realmy" and c.full == "Anna Brook", "no surname from the game: Chronicle's record has it")
	chars["Anna-Realmy"] = nil
	check(E.Character().full == "Anna", "nobody knows it: the first name")
	UnitName = function(unit) if unit == "player" then return "Anna", "Brook" end return baseName(unit) end
	check(E.Character().full == "Anna Brook", "the game says it: first name and surname")
	UnitName = baseName
end

section("Echoes pages: the lines joined every 60 s and at logout")
local written, before = {}, nil
do
	local open = E.data.open
	E.Anchor(0, -9046, -160, "f", "s")
	E.Zone(1429, "Goldshire")
	kills(1, 5, written)
	check(open.text == "" and #E.buffer == 9, "lines go into the buffer, not the page's text (no concatenation per line)")
	Advance(59, 0.25)
	check(open.text == "", "not joined before 60 s")
	E.Point(-9050, -170)
	Advance(2, 0.25)
	local lines = linesOf(open.text)
	check(#E.buffer == 0 and #lines == 10 and lines[1] == header(1, open.t0) and lines[3] == "@0;0;-9046;-160;f;s"
		and lines[10]:find("^%d+,%-4,%-10$"), "joined after 60 s, in order, the buffer empty, got\n" .. open.text)
	kills(6, 7, written)
	Fire("PLAYER_LOGOUT")
	check(#E.buffer == 0 and count(open.text, ";7\n") == 1, "joined at logout")
	E.Line("o", 0) -- (a line from a logout handler after Echoes': in E.buffer, which is saved with the page)
	check(open.buffer == E.buffer and open.buffer[1] == "o0;0", "a line written after it still goes with the page: E.buffer is saved")
	before = open.text .. "o0;0\n"
end

section("Echoes pages: /reload goes on with the page")
do
	local saved = reload(30, true)
	local open = E.data.open
	check(saved:find("o0;0", 1, true) and open.n == 1 and open.text == before and #E.buffer == 0 and open.buffer == E.buffer
		and open.state == E.state and E.data.n == 0, "the same page goes on: its text with the line from after the logout, joined once")
	check(E.bytes == #before and E.count == #linesOf(before), "its size goes on: bytes and lines")
	check(E.state.anchored and E.state.north == -9050 and E.state.mode == "f" and E.state.names and E.state.t == written[7],
		"the encoder's state goes on: the last position, the mode, the last line's time")
	kills(8, 10, written)
	check(E.buffer[1] == "k30;8", "the next line's dt counts from the last line before the /reload, got " .. tostring(E.buffer[1]))
	E.Point(-9060, -180)
	check(E.buffer[4] == "0,-10,-10", "points go on from the last position, got " .. tostring(E.buffer[4]))

	-- 30 minutes after it started, it closes on the tick.
	skew = skew + 1800
	resetTicks()
	local n0 = closes
	tick()
	local page = E.data.mine[1]
	check(closes == n0 + 1 and page and page.q and page.m == "t" and page.t == open.t0 and page.z == lastClosed and E.data.n == 1,
		"after 30 minutes the page closes on the tick: kept as text, waiting to be packed; it's the last closed page now")
	local text = page.z
	local times = timesOf(text)
	local order, right = {}, true
	for _, x in ipairs(times) do
		local id = x.line:match("^k%d+;(%d+)$")
		if id then
			order[#order + 1] = id
			right = right and x.t == written[tonumber(id)]
		end
	end
	check(text:sub(1, #before) == before and table.concat(order, ",") == "1,2,3,4,5,6,7,8,9,10" and right,
		"every line once, in order, each at the time it was written (across the /reload), got " .. table.concat(order, ","))
	check(times[#times].line == (".%d;t"):format(E.Now() - written[10]) and times[#times].t == E.Now() and count(text, "\nE1;") == 0,
		"it ends in \".<dt>;t\" (time) at the time it closed; one header, got " .. times[#times].line)

	-- The next page: header, character, and it goes on from the last position (E.Continue).
	local open2 = E.data.open
	check(open2.n == 2 and E.buffer[1] == header(2, E.Now()) and E.buffer[2] == charLine() and E.buffer[3] == "@0;0;-9060;-180;f;c"
		and E.buffer[4] == "z0;1429;Goldshire" and #E.buffer == 4, "page 2: header, character, an anchor at the last position (why c) and the zone")

	-- The tick after: packed (Base64 of zlib) and hashed.
	tick()
	check(page.m == "z" and not page.q and page.h == realHash(page.z) and not page.z:find("[^A-Za-z0-9+/=]"),
		"the next tick packs it: Base64 of zlib, LT.Hash32 of the Base64")
	check(textOf(page) == text, "unpacked (Node's real zlib, like the exporter), the text again")
	check(most.compress == 1 and most.close == 1, "one page closed on one tick, packed on the next")
end

section("Echoes pages: closing by size and by lines, on the tick")
do
	local n, c0 = E.data.open.n, closes
	resetTicks()
	Fire("ECHOES_PAGES_TEST", 158, 200) -- (158 lines of 204 bytes: just under 32 KB)
	tick()
	check(E.data.open.n == n and closes == c0 and E.bytes < 32768, "(just under 32 KB: open)")
	Fire("ECHOES_PAGES_TEST", 3, 200)
	check(E.data.open.n == n and closes == c0 and E.bytes > 32768, "past 32 KB inside an event: nothing closes there")
	tick()
	local page, text = E.data.mine[n], lastClosed
	check(closes == c0 + 1 and page and E.data.open.n == n + 1 and text:find("\n%.[01];s\n$") and #text >= 32768 and #text < 32768 + 3 * 204 + 10,
		"the next tick closes it: \".<dt>;s\" (size), right after it passed 32 KB")
	tick()
	check(page.m == "z" and textOf(page) == text and #page.z < #text / 4, "and the tick after packs it: zlib makes it much smaller")
	Fire("ECHOES_PAGES_TEST", 2000, 1) -- (2,000 lines of 5 bytes, after the page's first 4)
	tick()
	local lines = linesOf(lastClosed)
	check(E.data.open.n == n + 2 and lastClosed:find("\n%.[01];s\n$") and #lines == 2005 and #lastClosed < 32768,
		"2,000 lines close a page too (\".<dt>;s\"), got " .. #lines .. " lines")
	tick()
	check(most.compress == 1 and most.close == 1 and heavyInEvent == 0, "one a tick; nothing heavy inside an event")
end

section("Echoes pages: a page with nothing on it doesn't close by time")
do
	-- The page after one closed mid-session: its header, the character and the going on (an anchor
	-- at the last position and the zone), then nothing while you're away (an AFK night).
	local open, c0 = E.data.open, closes
	check(open.own == 4 and E.count == 4 and not open.busy, "(the next page: its own 4 lines, nothing else yet)")
	for _ = 1, 6 do
		skew = skew + 1800
		tick()
	end
	check(closes == c0 and E.data.open == open and not open.busy, "3 hours with nothing new on it: it stays open (no page every 30 minutes)")
	local mark = #PRINTED + 1
	lefthy("echoes")
	check(printedSince(mark):find("4 lines, started 180 min ago; nothing recorded on it yet, so it stays open.", 1, true),
		"the status says so, got\n" .. printedSince(mark))

	-- Something happens: its 30 minutes run from then. One page for the whole time away.
	local when = {}
	kills(1, 1, when)
	tick()
	local busy = open.busy
	check(busy == E.Now() and busy - when[1] <= 1, "the next tick notes when something came on it")
	tickAt(busy + 1799)
	check(closes == c0, "(29 minutes 59 seconds later: open)")
	tickAt(busy + 1800)
	local lines = linesOf(lastClosed)
	check(closes == c0 + 1 and #lines == 6 and lines[5] == ("k%d;1"):format(when[1] - open.t0) and when[1] - open.t0 >= 10800
		and lines[6] == (".%d;t"):format(busy + 1800 - when[1]), "30 minutes after that it closes (\".<dt>;t\"), with the hours before it, got\n" .. lastClosed)
	check(E.data.open.own == 4 and not E.data.open.busy, "(the next page waits the same way)")

	-- A /reload: when its 30 minutes started goes on with the page.
	kills(2, 2)
	tick()
	busy = E.data.open.busy
	reload(30)
	check(busy and E.data.open.busy == busy and E.data.open.own == 4, "a /reload keeps when its 30 minutes started")
	c0 = closes
	tickAt(busy + 1800)
	check(closes == c0 + 1, "and it closes 30 minutes after it")

	-- A page from a build before this rule (no own): 30 minutes from its start, as before.
	local t0 = E.data.open.t0
	E.data.open.own, E.data.open.busy = nil, nil
	tickAt(t0 + 1799)
	check(closes == c0 + 1, "(an open page from before: open 29 minutes 59 seconds after it started)")
	tickAt(t0 + 1800)
	check(closes == c0 + 2 and lastClosed:find("\n%.1800;t\n$"), "and closed 30 minutes after it started, nothing on it or not")
	tick()
end

section("Echoes pages: a stale page at login, another character, packing one a tick")
do
	-- A page closes, and before the tick that packs it the game ends (a logout: the capture's o0, written
	-- here, as the quiet capture doesn't); back 11 minutes later.
	local stale = E.data.open.n
	Fire("ECHOES_PAGES_TEST", 170, 200)
	tick()
	local waiting = E.data.mine[stale]
	check(waiting and waiting.q, "(a closed page waiting to be packed)")
	kills(11, 12)
	E.Line("o", 0)
	local c0, before0 = compressCalls, E.data.open.text .. table.concat(E.buffer, "\n") .. "\n"
	reload(11 * 60)
	local open, old = E.data.open, E.data.mine[stale + 1]
	check(old and old.q and old.z == before0 .. ".0;l\n" and old.t == tonumber(old.z:match("^E1;%x*;%x+;%d+;(%d+);")) and E.data.n == stale + 1,
		"its last line more than 10 minutes ago: the open page closes as it was, \".0;l\" (stale at login)")
	check(open.n == stale + 2 and E.buffer[1] == header(stale + 2, E.Now()) and compressCalls == c0,
		"a new page starts; nothing packed at login (inside PLAYER_LOGIN)")
	resetTicks()
	tick()
	check(E.data.mine[stale].m == "z" and E.data.mine[stale + 1].q and compressCalls == c0 + 1, "one tick: the oldest waiting page packed, only it")
	tick()
	check(E.data.mine[stale + 1].m == "z" and textOf(E.data.mine[stale + 1]) == before0 .. ".0;l\n" and most.compress == 1,
		"the next tick: the stale one")
	check(Store.Page(acct, STORE, stale + 1) == E.data.mine[stale + 1] and Store.Page(acct, STORE, stale) == E.data.mine[stale],
		"both offered at once: the one closed before the game ended is on disk, the stale one is the saved text (any later load closes it the same way)")

	-- Soon after, on the same character: the page goes on.
	kills(13, 13)
	reload(5 * 60)
	check(E.data.open.n == stale + 2 and count(E.data.open.text, "E1;") == 1 and #E.buffer == 0, "5 minutes later: the same page goes on")

	-- Another character a minute later: the page closes (".0;l"), a new one has the other character.
	local baseName = UnitName
	UnitName = function(unit) if unit == "player" then return "Anna", "Brook" end return baseName(unit) end
	MY_GUID = "Player-1-0ANNA"
	reload(60)
	check(E.data.mine[stale + 2] and E.data.mine[stale + 2].z:sub(-5) == ".0;l\n" and E.data.open.n == stale + 3
		and E.buffer[2] == charLine("Anna-Realmy", "Anna Brook", "Player-1-0ANNA"), "another character: the page closes, the new one is Anna's")
	-- Back to the first a minute later: Anna's page closes the same way.
	UnitName, MY_GUID = baseName, nil
	reload(60)
	check(E.data.mine[stale + 3] and E.data.mine[stale + 3].z:find("\nC0;Anna%-Realmy;") and E.data.open.char == "Lefthy-Realmy",
		"and back: Anna's page closes, mine starts")
	Advance(1, 0.25)
	check(E.data.mine[stale + 3].m == "z" and Store.Page(acct, STORE, stale + 3) == nil and Store.Page(acct, STORE, stale + 2),
		"closed for another character a minute after its last line: offered from the next session on (after a crash, back on the "
		.. "first character within 10 minutes, the page would go on instead); the one from the session before is offered")
	check(heavyInEvent == 0, "nothing heavy inside an event or at login")
end

section("Echoes pages: a disconnect, switched off for a while")
do
	-- The game saves without PLAYER_LOGOUT (a disconnect): the lines not joined yet are in the page's
	-- buffer, saved with it, and go on with the page once.
	local n = E.data.open.n
	kills(21, 23)
	local before0 = E.data.open.text .. table.concat(E.buffer, "\n") .. "\n"
	check(#E.buffer >= 3, "(lines not joined yet)")
	reload(5, true)
	check(E.data.open.n == n and E.data.open.text == before0 and #E.buffer == 0 and count(E.data.open.text, ";23\n") == 1,
		"no PLAYER_LOGOUT: the lines not joined yet came with the page, once")

	-- Switched off for 11 minutes, then on: the page closes as it was (".0;l"), its lines in it once.
	kills(24, 24)
	LT:SetModuleEnabled("echoes", false)
	skew = skew + 11 * 60
	local c0 = closes
	start()
	local page = E.data.mine[n]
	check(closes == c0 + 1 and page and page.q and count(page.z, ";24\n") == 1 and page.z:sub(-5) == ".0;l\n" and E.data.open.n == n + 1
		and E.buffer[1] == header(n + 1, E.Now()), "switched off for 11 minutes: the page closes as it was (\".0;l\"), a new one starts")

	-- Off for a minute: the same page goes on.
	kills(25, 25)
	LT:SetModuleEnabled("echoes", false)
	skew = skew + 60
	start()
	check(E.data.open.n == n + 1 and count(E.data.open.text, ";25\n") == 1 and #E.buffer == 0 and E.bytes == #E.data.open.text
		and E.count == #linesOf(E.data.open.text), "switched off for a minute: the same page goes on, its size counted")
	tick()
	tick()
	check(page.m == "z" and Store.Page(acct, STORE, n) == nil, "the page closed after switching on again has this session's lines: offered from the next session on")
end

section("Echoes pages: a crash or a disconnect writes no logout: the page gets it")
do
	-- The game ends without PLAYER_LOGOUT (a crash, a disconnect: saved as it was), the page's last
	-- session line a login (o1): stale at the next login, it closes with "o0;0" before its end (at the
	-- time of its last line).
	fresh(acct)
	E.Anchor(0, -9046, -160, "f", "s")
	E.Zone(1429, "Goldshire")
	E.Line("o", 1)
	local when = {}
	kills(1, 2, when)
	local n = E.data.open.n
	reload(11 * 60, true)
	local text = E.data.mine[n] and E.data.mine[n].z or ""
	local times = timesOf(text)
	check(text:sub(-10) == "o0;0\n.0;l\n" and times[#times - 1].t == when[2] and count(text, "\no") == 2,
		"stale after a disconnect, the session not ended: \"o0;0\" before the end, at its last line's time, got\n" .. text)

	-- Logged out properly (its o0): nothing added.
	E.Anchor(0, -9046, -160, "f", "s")
	E.Line("o", 1)
	kills(3, 3)
	E.Line("o", 0)
	n = E.data.open.n
	reload(11 * 60, true)
	text = E.data.mine[n] and E.data.mine[n].z or ""
	check(text:find("\no%d+;0\n%.0;l\n$") and count(text, "\no") == 2, "logged out (o0 last): nothing added, got\n" .. text)

	-- A page that went on from the one before (an anchor, why c; no session line on it): the session
	-- was going on.
	E.Anchor(0, -9046, -160, "f", "s")
	E.Line("o", 1)
	kills(4, 4)
	tick()
	skew = skew + 1800
	tick()
	n = E.data.open.n
	check(E.buffer[3] == "@0;0;-9046;-160;f;c", "(a page going on from the last one)")
	kills(5, 5)
	reload(11 * 60, true)
	text = E.data.mine[n] and E.data.mine[n].z or ""
	check(text:sub(-10) == "o0;0\n.0;l\n" and count(text, "\no") == 1, "a page going on from the last one, not ended: \"o0;0\" too, got\n" .. text)

	-- Back on the same character within 10 minutes: the page goes on, with the logout first (dt 0).
	E.Anchor(0, -9046, -160, "f", "s")
	E.Line("o", 1)
	kills(6, 6, when)
	n = E.data.open.n
	reload(3 * 60, true)
	kills(7, 7)
	check(E.data.open.n == n and E.buffer[1] == "o0;0" and E.buffer[2] == ("k%d;7"):format(E.Now() - when[6]),
		"the page goes on after a disconnect: the logout first, at its last line's time, got " .. table.concat(E.buffer, " | "))
	-- A /reload (o0 written at its logout): nothing added.
	E.Line("o", 1)
	E.Line("o", 0)
	E.Flush()
	reload(30, true)
	check(E.data.open.n == n and #E.buffer == 0 and E.data.open.text:find("\no%d+;0\n$"), "a /reload (o0 last): nothing added")
	-- The same save read twice (a crash after the login that closed it): the same page.
	local save = Saved()
	E.Line("o", 1)
	E.Flush()
	save = Saved()
	reload(11 * 60, nil, save)
	local once = E.data.mine[n] and E.data.mine[n].z
	reload(0, nil, save)
	check(once and once:sub(-10) == "o0;0\n.0;l\n" and E.data.mine[n] and E.data.mine[n].z == once,
		"the same save read again: closed the same way, byte for byte")

	local result = MOCK_EXPORTER(Saved())
	if type(result) == "table" then
		local clean = true
		for _, p in pairs(result.parsed) do
			clean = clean and p.ok and p.bad == 0 and p.unknown == ""
		end
		check(clean and result.bad == 0 and #result.warnings == 0, "the exporter reads them: " .. table.concat(result.warnings, "; "))
	elseif type(result) == "string" then
		check(false, "the exporter: " .. result)
	end
end

section("Echoes pages: my pages offered once on disk (a crash)")
do
	-- The game writes the saved file only at a logout or /reload; after a crash the next login goes
	-- on from the last save and numbers its pages from there again. So my pages are offered from the
	-- session after the one they closed in: none of a lost session's pages is out there.
	fresh(acct)
	kills(1, 1)
	tick()
	skew = skew + 1800
	tick()
	tick()
	local offered = {} -- n -> what was offered as page n (E.Store.Mine)
	local function look() for n, page in Store.Mine() do offered[n] = page.z end end
	look()
	check(E.data.mine[1].m == "z" and Store.Page(acct, STORE, 1) == nil and Store.Held("mine")[own] == nil and next(offered) == nil,
		"a page closed and packed this session: not offered (E.Store.Mine, Held, Page)")
	local mark = #PRINTED + 1
	lefthy("echoes")
	check(printedSince(mark):find("1 offered from the next session on (a /reload is one)", 1, true), "the status says so, got\n" .. printedSince(mark))
	local save = reload(5)
	look()
	check(Store.Page(acct, STORE, 1) == E.data.mine[1] and Store.Held("mine")[own] == "1" and offered[1] == E.data.mine[1].z,
		"a /reload saved it: offered from then on")

	-- The next session closes page 2 (by size) and starts page 3; then the game crashes, and the next
	-- login, a minute later, reads the save from before: page 2 is open again and goes on.
	Fire("ECHOES_PAGES_TEST", 170, 200)
	tick()
	tick()
	look()
	local lost = E.data.mine[2]
	check(lost and lost.m == "z" and E.data.open.n == 3 and offered[2] == nil, "(page 2 closed and packed this session: not offered)")
	reload(60, nil, save) -- (the crash: nothing saved)
	check(E.data.n == 1 and E.data.open.n == 2 and not E.data.mine[2], "after the crash: the save from before, page 2 open again")
	kills(7, 8)
	Fire("ECHOES_PAGES_TEST", 170, 200)
	tick()
	tick()
	local again = E.data.mine[2]
	check(again and again.m == "z" and again.z ~= lost.z and Store.Page(acct, STORE, 2) == nil, "page 2 again, with other lines: not offered this session either")
	local same = true
	for n, z in pairs(offered) do same = same and E.data.mine[n] ~= nil and E.data.mine[n].z == z end
	check(same and size(offered) == 1, "every page offered before the crash is the same page now: no number went out with other lines")
	check(Store.Safe(acct, STORE, Ranges.Of(offered), "c011ec70.12345678") == 1 and E.data.mine[2] == again,
		"what a collector can hold (only what was offered) drops only that: the new page 2 stays")
	reload(1)
	check(Store.Page(acct, STORE, 2) == E.data.mine[2] and E.data.mine[2].z == again.z, "after a /reload the new page 2 goes out")
end

section("Echoes pages: packing when the game's compression fails")
do
	local function closeNow()
		kills(1, 1) -- (something on it: a page with nothing on it doesn't close by time)
		tick()
		skew = skew + 1800
		tick()
		local n = E.data.n
		tick()
		return E.data.mine[n], lastClosed
	end
	closeNow() -- (nothing waiting)
	encoding.CompressString = function(...) countedCompress(...) return nil end
	local page, text = closeNow()
	check(page.m == "r" and encoding.DecodeBase64(page.z) == text and page.h == realHash(page.z), "compressing answers nothing: Base64 of the text (r)")
	encoding.CompressString = function() error("broken") end
	page, text = closeNow()
	check(page.m == "r" and encoding.DecodeBase64(page.z) == text, "compressing fails: r too")
	encoding.EncodeBase64 = function() return nil end
	page, text = closeNow()
	check(page.m == "t" and page.z == text and page.h == realHash(text) and not page.q, "Base64 answers nothing too: the text as it is (t)")
	encoding.EncodeBase64 = function() return "not Base64!" end
	page, text = closeNow()
	check(page.m == "t" and page.z == text, "Base64 answers something that isn't: t")
	encoding.CompressString, encoding.EncodeBase64 = countedCompress, realEncode
	C_EncodingUtil = nil
	page, text = closeNow()
	check(page.m == "t" and page.z == text, "no C_EncodingUtil at all: t")
	C_EncodingUtil = encoding
	local plain = E.data.n
	page = closeNow()
	check(page.m == "z", "(compressing again)")
	check(Store.Page(acct, STORE, plain + 1) == nil and not Ranges.Contains(Store.Held("mine")[own] or "", plain + 1),
		"(closed this session: not offered yet)")
	reload(1) -- (on disk now)
	local shared = {}
	for n, p in Store.Mine() do shared[#shared + 1] = n check(p == E.data.mine[n], "(Mine: the page itself)") end
	check(not Ranges.Contains(table.concat(shared, ","), plain) and Ranges.Contains(table.concat(shared, ","), plain + 1)
		and Store.Page(acct, STORE, plain) == nil and Store.Page(acct, STORE, plain + 1) == E.data.mine[plain + 1],
		"a plain-text page is kept (the exporter reads it) but never shared: not in E.Store.Mine, E.Store.Page")
	check(shared[1] < shared[#shared] and not Ranges.Contains(Store.Held("mine")[own], plain), "E.Store.Mine goes oldest first; Held leaves t out")
end

section("Echoes pages: my BattleTag not known yet")
do
	MY_BATTLETAG = nil
	fresh()
	local open = E.data.open
	check(E.buffer[1] == header(1, open.t0, "") and open.acct == nil and E.data.acct == nil and Store.Own() == nil,
		"not known: the header's account is empty, got " .. E.buffer[1])
	kills(1, 3)
	Advance(6, 0.25)
	local size0 = E.bytes
	MY_BATTLETAG = "Me#1111"
	Advance(5.25, 0.25)
	check(open.text:sub(1, #header(1, open.t0)) == header(1, open.t0) and open.acct == acct and E.data.acct == acct and E.bytes == size0 + 8
		and count(open.text, "\nk0;") == 3, "known within 5 s: the open page's header gets it (once), its size counted")
	MY_BATTLETAG = nil
	fresh()
	kills(1, 1)
	tick()
	skew = skew + 1800
	tick()
	tick()
	check(E.data.mine[1] and textOf(E.data.mine[1]):find("^E1;;" .. STORE .. ";1;"), "a page closed before it was known keeps the empty one")
	fresh(acct)
	check(E.buffer[1] == header(1, E.data.open.t0) and Store.Own() == own, "known from before, Battle.net silent now: the last known")
	MY_BATTLETAG = "Me#1111"
end

section("Echoes pages: range strings")
do
	check(Ranges.Format(Ranges.Parse("1-56,58")) == "1-56,58" and Ranges.Format("58,1-56") == "1-56,58", "parsed and written, sorted")
	check(Ranges.Format("3-1,0,a,5,-2,7-7, 9 - 10 ,,2-3x") == "5,7,9-10", "parts that aren't one are skipped; spaces are fine")
	check(Ranges.Format("1-2,2-5,7,6") == "1-7" and Ranges.Format("") == "" and Ranges.Format(nil) == "" and Ranges.Format(SECRET) == "",
		"overlapping and touching ranges merge; nothing is empty")
	check(Ranges.Union("1-3,7", "4-5,9") == "1-5,7,9" and Ranges.Union("", nil) == "" and Ranges.Union(nil, "2") == "2", "union")
	check(Ranges.Contains("1-56,58", 1) and Ranges.Contains("1-56,58", 56) and not Ranges.Contains("1-56,58", 57) and Ranges.Contains("1-56,58", 58)
		and not Ranges.Contains("1-56,58", 0) and not Ranges.Contains("1-56,58", nil) and not Ranges.Contains(nil, 1), "contains")
	check(Ranges.Of({ [1] = 1, [2] = 1, [3] = 1, [5] = 1, [2.5] = 1, x = 1 }) == "1-3,5"
		and Ranges.Of({ [1] = 1, [2] = 2, [3] = 1 }, function(_, v) return v == 1 end) == "1,3", "a table's page numbers (keep: some)")
	check(Ranges.Format("1-99999999999") == "" and Ranges.Contains("1-999999999", 500000000), "numbers up to 999,999,999; ranges never spelled out")
end

section("Echoes pages: friends' pages (carry, inbox) and what's safe")
local A, B = "5e6f7a8b", "0c77e1f2" -- a friend's account and store
local friend = A .. "." .. B
local function friendPage(n, t)
	local m, z = Store.Pack(("E1;%s;%s;%d;%d;enUS;70532;0.6.0\nk0;%d\n.0;t\n"):format(A, B, n, t, n))
	return { t = t, h = realHash(z), m = m, z = z }
end
local big = ("A"):rep(60 * 1024) -- (a page's worth of Base64)
local bigHash = realHash(big)
local function bigPage(t) return { t = t or E.Now(), h = bigHash, m = "z", z = big } end
-- Whether the sizes E.Store keeps (as pages came and went) are the pages' as they are: counted anew.
local function sizesAgree()
	local kept = { Store.Bytes("mine"), Store.Bytes("carry"), Store.Bytes("inbox") }
	local authors = {}
	for key in pairs(E.data.carry) do authors[key] = Store.Bytes("carry", key:sub(1, 8), key:sub(10)) end
	Store.Recount()
	local same = kept[1] == Store.Bytes("mine") and kept[2] == Store.Bytes("carry") and kept[3] == Store.Bytes("inbox")
	for key, n in pairs(authors) do same = same and n == Store.Bytes("carry", key:sub(1, 8), key:sub(10)) end
	return same
end
do
	fresh(acct)
	local now = E.Now()
	check(Store.Key(A, B) == friend and Store.Key("x", B) == nil and Store.Key(A, "0c77e1f") == nil and Store.Own() == own, "keys: account.store")
	check(not pcall(Store.Put, A, B, 1, friendPage(1, now), "mine"), "Put: carry or inbox, nothing else")
	local function refused(why, ...) local ok, reason = Store.Put(...) return ok == false and reason == why end
	local good = friendPage(1, now)
	check(refused("id", "x", B, 1, good, "carry") and refused("id", A, B, 0, good, "carry") and refused("id", A, B, 1.5, good, "carry"),
		"refused: an id that isn't one")
	check(refused("mine", acct, STORE, 1, good, "inbox"), "refused: my own store's pages")
	check(refused("page", A, B, 1, { t = now, h = good.h, m = "t", z = good.z }, "carry")
		and refused("page", A, B, 1, { t = now, h = realHash("ab;c"), m = "r", z = "ab;c" }, "carry")
		and refused("page", A, B, 1, { t = now, h = "", m = "z", z = "" }, "carry"), "refused: plain text, not Base64, empty")
	check(refused("size", A, B, 1, { t = now, h = "x", m = "z", z = ("A"):rep(64 * 1024 + 4) }, "carry"), "refused: over 64 KB")
	check(refused("time", A, B, 1, friendPage(1, now + 86400 + 60), "carry") and refused("time", A, B, 1, { t = nil, h = good.h, m = "z", z = good.z }, "carry"),
		"refused: starting more than a day ahead, or no start")
	check(refused("hash", A, B, 1, { t = now, h = "00000000", m = good.m, z = good.z }, "carry"), "refused: a hash that doesn't match")
	check(Store.Put(A, B, 1, good, "carry") == true and select(2, Store.Put(A, B, 1, good, "carry")) == "have", "kept; again: had it")
	local kept = E.data.carry[friend][1]
	check(kept ~= good and kept.z == good.z and kept.h == good.h and kept.m == "z" and kept.t == now and kept.s == E.data.session and kept.a == E.Now(),
		"a copy, with the session (s) and when it came (a)")
	check(Store.Page(A, B, 1) == kept and select(2, Store.Page(A, B, 1)) == "carry" and Store.Page(A, B, 2) == nil and Store.Held("carry")[friend] == "1",
		"served from carry; held: 1")
	check(Store.Bytes("carry") == #good.z and Store.Bytes("carry", A, B) == #good.z, "its size counted")

	-- Safe at a collector: dropped from carry (and from mine, for my own), never kept again.
	Store.Put(A, B, 2, friendPage(2, now), "carry")
	Store.Put(A, B, 3, friendPage(3, now), "carry")
	local collector = "c011ec70.12345678"
	check(Store.Safe(A, B, "1-2", collector) == 2 and E.data.carry[friend][3] and not E.data.carry[friend][1]
		and E.data.safe[friend][collector] == "1-2", "a collector holds 1-2 safely: they go from carry, its summary kept")
	check(Store.Safe(A, B, "3,5", collector) == 1 and E.data.safe[friend][collector] == "1-3,5" and E.data.carry[friend] == nil
		and Store.Bytes("carry") == 0, "summaries merge (only grow); an author with nothing left goes")
	check(refused("safe", A, B, 2, friendPage(2, now), "carry"), "a page a collector holds isn't relayed again")

	-- The cache: 128 KB per author, 512 KB in all.
	check(Store.Fits(A, B, 60 * 1024) and Store.Put(A, B, 10, bigPage(), "carry") and Store.Put(A, B, 11, bigPage(), "carry")
		and not Store.Fits(A, B, 9 * 1024) and refused("full", A, B, 12, bigPage(), "carry"), "128 KB per author's store")
	for i = 1, 3 do
		local store = ("0000000%d"):format(i)
		Store.Put(A, store, 1, bigPage(), "carry")
		Store.Put(A, store, 2, bigPage(), "carry")
	end
	check(Store.Bytes("carry") == 8 * #big and not Store.Fits(A, "00000009", 60 * 1024) and refused("full", A, "00000009", 1, bigPage(), "carry"),
		"512 KB in all")
	check(Store.Drop(A, "00000001") == 2 and Store.Drop(A, "00000002", "2") == 1 and Store.Bytes("carry") == 5 * #big
		and E.data.carry[A .. ".00000002"][1], "dropped: all of a store, or some")

	-- The inbox (collecting): pages from earlier sessions are on disk: safe here, with what's exported.
	check(Store.Put(A, B, 1, friendPage(1, now), "inbox") and Store.Put(A, B, 2, friendPage(2, now), "inbox")
		and Store.Page(A, B, 1) == E.data.inbox[friend][1] and select(2, Store.Page(A, B, 1)) == "inbox", "kept in the inbox, served from it")
	check(Store.SafeHere(A, B) == "", "received this session: not safe here yet (the game hasn't saved it)")
	E.data.exported[friend] = "7-9"
	check(refused("exported", A, B, 8, friendPage(8, now), "inbox"), "a page the exporter has isn't taken again")
	reload(1)
	check(Store.SafeHere(A, B) == "1-2,7-9" and Store.Held("inbox")[friend] == "1-2", "after a /reload: on disk, safe here, with what's exported")
	Store.Put(A, B, 3, friendPage(3, E.Now()), "inbox")
	check(Store.SafeHere(A, B) == "1-2,7-9", "(the new one not yet)")

	-- Relayed pages go after 30 days.
	E.data.carry[A .. ".00000003"][1].a = E.Now() - 31 * 86400
	E.data.carry[A .. ".00000003"][2].a = E.Now() - 29 * 86400
	reload(1)
	Advance(2, 0.25)
	check(E.data.carry[A .. ".00000003"] and not E.data.carry[A .. ".00000003"][1] and E.data.carry[A .. ".00000003"][2],
		"relayed pages go 30 days after they came, at the next login")
	check(sizesAgree(), "the sizes kept as pages came and went are the pages' (carry per author too)")
end

section("Echoes pages: my pages over 2 MB")
do
	local hundred = ("B"):rep(100 * 1024)
	local function page() return { t = E.Now(), h = realHash("x"), m = "z", z = hundred } end
	fresh(acct)
	LT:SetModuleEnabled("echoes", false)
	for n = 1, 21 do E.data.mine[n] = page() end
	E.data.n, E.data.open = 21, nil
	start() -- (page 22 opens)
	check(Store.Bytes("mine") == 2100 * 1024 and E.data.open.n == 22, "(21 pages of 100 KB)")
	Store.Carried(acct, STORE, "5-6")
	Store.Carried(A, B, "1-3") -- (someone else's: nothing to do with mine)
	check(Store.Trim() == 1 and not E.data.mine[5] and E.data.mine[1] and E.data.mine[6] and Store.Bytes("mine") == 2000 * 1024,
		"over 2 MB: a page a relay carries goes first, the oldest of them")
	for n = 101, 103 do E.data.mine[n] = page() end
	Store.Recount()
	check(Store.Trim() == 3 and not E.data.mine[6] and not E.data.mine[1] and not E.data.mine[2] and E.data.mine[3]
		and Store.Bytes("mine") == 2000 * 1024, "then the others carried, then the oldest")
	-- It runs after each packed page by itself.
	E.data.mine[104] = page()
	Store.Recount()
	kills(1, 1)
	tick()
	skew = skew + 1800
	tick()
	tick()
	check(not E.data.mine[3] and E.data.mine[4] and E.data.mine[22] and E.data.mine[22].m == "z" and Store.Bytes("mine") <= 2048 * 1024,
		"after packing a page: back under 2 MB, the oldest gone")
	check(Store.Safe(acct, STORE, "4-10", "c011ec70.12345678") == 5 and not E.data.mine[4] and E.data.mine[11],
		"my pages a collector holds safely go")
	check(sizesAgree(), "(the sizes agree: closed, packed, trimmed, safe)")
end

section("Echoes pages: collecting: 4 MB, 8 MB, the exporter's receipt")
local loads = 0
C_AddOns.LoadAddOn = function(name)
	loads = loads + 1
	if name == "LefthyTools_EchoesReceipt" and MOCK_RECEIPT then
		LefthyToolsEchoesReceipt = MOCK_RECEIPT
		return true
	end
	return false, "MISSING"
end
do
	fresh(acct)
	local key = A .. ".00000010"
	E.data.inbox[key] = {}
	for n = 1, 68 do
		E.data.inbox[key][n] = { t = E.Now(), h = bigHash, m = "z", z = big, s = E.data.session }
	end
	Store.Recount()
	local mark = #PRINTED + 1
	check(Store.Put(A, "00000010", 69, bigPage(), "inbox") and Store.Bytes("inbox") >= 4096 * 1024 and not Store.InboxFull(), "(over 4 MB)")
	check(not printedSince(mark):find("run the exporter", 1, true), "not said inside the call (the tick says it)")
	Advance(1.5, 0.25)
	check(select(2, printedSince(mark):gsub("run the exporter", "")) == 1, "a chat line asks to run the exporter, got: " .. printedSince(mark))
	Store.Put(A, "00000010", 70, bigPage(), "inbox")
	Advance(1, 0.25)
	check(select(2, printedSince(mark):gsub("run the exporter", "")) == 1, "once a session")
	reload(1)
	Advance(2, 0.25)
	check(select(2, printedSince(mark):gsub("run the exporter", "")) == 2, "and again the next session (at login)")
	for n = 71, 137 do
		E.data.inbox[key][n] = { t = E.Now(), h = bigHash, m = "z", z = big, s = E.data.session }
	end
	Store.Recount()
	check(Store.InboxFull() and Store.Put(A, "00000010", 138, bigPage(), "inbox"),
		"8 MB: the inbox is full (the delivery stops pulling); a page that still comes is kept")
	check(loads == 0, "collecting off: the receipt isn't loaded")

	-- The receipt: with collecting on, loaded at login; what it lists goes from inbox, carry and mine.
	fresh(acct)
	LT:SetModuleSetting(M, "collect", true)
	for n = 1, 5 do Store.Put(A, B, n, friendPage(n, E.Now()), "inbox") end
	for n = 1, 3 do Store.Put(A, "0c77e1f3", n, friendPage(n, E.Now()), "carry") end
	for n = 1, 3 do Store.Close(n, E.Now(), header(n, E.Now()) .. "\n.0;t\n") end
	Advance(3, 0.25) -- (packed, the chores after the start, then the receipt)
	MOCK_RECEIPT = { v = 1, at = E.Now(), done = { [friend] = "1-3", [A .. ".0c77e1f3"] = "2", [own] = "1-2", ["bad key"] = "1",
		[A .. ".0c77e1f4"] = "nonsense" } }
	check(loads == 1 and LefthyToolsEchoesReceipt == nil, "(switched on mid-session: tried once, no folder yet)")
	reload(1)
	Advance(2, 0.25)
	check(loads == 2 and Ranges.Of(E.data.inbox[friend]) == "4-5" and Ranges.Of(E.data.carry[A .. ".0c77e1f3"]) == "1,3"
		and Ranges.Of(E.data.mine) == "3", "at login: the receipt's pages go from the inbox, carry and mine")
	check(E.data.exported[friend] == "1-3" and E.data.exported[A .. ".0c77e1f3"] == "2" and E.data.exported[own] == "1-2"
		and E.data.exported["bad key"] == nil and E.data.exported[A .. ".0c77e1f4"] == nil, "and are kept as exported (bad entries skipped)")
	check(Store.SafeHere(A, B) == "1-5", "safe here: exported, and the rest on disk")
	MOCK_RECEIPT.done[friend] = "1-4"
	reload(1)
	Advance(2, 0.25)
	check(loads == 3 and Ranges.Of(E.data.inbox[friend]) == "5" and E.data.exported[friend] == "1-4" and Ranges.Of(E.data.mine) == "3",
		"each login reads it again; the full ranges again are harmless")
	MOCK_RECEIPT = nil
	LefthyToolsEchoesReceipt = nil
	reload(1)
	Advance(2, 0.25)
	check(loads == 4 and Ranges.Of(E.data.inbox[friend]) == "5" and E.data.exported[friend] == "1-4", "no receipt folder: nothing changes")

	-- A receipt that isn't one, or no way to load it: nothing changes, nothing breaks.
	local reported, stop = suite.catchErrors()
	local inbox0, exported0, stores0 = Ranges.Of(E.data.inbox[friend]), E.data.exported[friend], size(E.data.exported)
	for _, bad in ipairs({ "x", { v = 1 }, { v = 1, done = "1-5" }, { v = 2, done = { [friend] = 5, [7] = "1-5", [friend .. "x"] = "1-5",
		[A .. ".0c77e1f5"] = "x-y" } } }) do
		MOCK_RECEIPT = bad
		reload(1)
		Advance(2, 0.25)
	end
	local loader = C_AddOns.LoadAddOn
	C_AddOns.LoadAddOn, LefthyToolsEchoesReceipt = nil, nil
	reload(1)
	Advance(2, 0.25)
	C_AddOns.LoadAddOn = function() error("broken") end
	reload(1)
	Advance(2, 0.25)
	stop()
	C_AddOns.LoadAddOn, MOCK_RECEIPT, LefthyToolsEchoesReceipt = loader, nil, nil
	check(#reported == 0 and Ranges.Of(E.data.inbox[friend]) == inbox0 and E.data.exported[friend] == exported0 and size(E.data.exported) == stores0,
		"receipts that aren't one (not a table, no done, bad keys and ranges), no LoadAddOn, a broken one: nothing changes, got "
		.. table.concat(reported, "; "))
	check(sizesAgree(), "(the sizes agree after the receipts)")
	LT:SetModuleSetting(M, "collect", false)
end

section("Echoes pages: the launch day")
do
	fresh(acct)
	LT.world = "release"
	local today = date("!*t", E.Now())
	LT.LAUNCH_DAY = ("%04d-%02d-%02d"):format(today.year, today.month, today.day)
	local launch = E.Now() - E.Now() % 86400 -- (that day's first second, UTC)
	E.data.mine[1] = { t = launch - 60, h = "x", m = "z", z = "QUJD" }
	E.data.mine[2] = { t = launch + 60, h = "x", m = "z", z = "QUJD" }
	E.data.carry[friend] = { [1] = { t = launch - 60, h = "x", m = "z", z = "QUJD", a = E.Now() }, [2] = { t = launch, h = "x", m = "z", z = "QUJD", a = E.Now() } }
	E.data.inbox[friend] = { [1] = { t = launch - 1, h = "x", m = "z", z = "QUJD", s = 1 }, [2] = { t = launch + 1, h = "x", m = "z", z = "QUJD", s = 1 } }
	E.data.n = 2
	E.data.open.t0 = launch - 120 -- (an open page from before the launch)
	E.data.open.state.t = E.Now()
	local n0 = closes
	reload(1)
	check(closes == n0 and E.data.n == 2 and E.data.open.n == 3 and E.data.open.t0 >= launch, "an open page from before the launch goes, unclosed")
	Advance(2, 0.25)
	check(not E.data.mine[1] and E.data.mine[2] and not E.data.carry[friend][1] and E.data.carry[friend][2] and not E.data.inbox[friend][1]
		and E.data.inbox[friend][2], "pages from before it go from mine, carry and inbox; from the day on they stay")
	check(select(2, Store.Put(A, B, 5, friendPage(5, launch - 10), "inbox")) == "time", "a page from before it isn't taken")
	LT.LAUNCH_DAY = nil
	LT.world = nil
	check(Store.Put(A, B, 5, friendPage(5, launch - 10), "inbox"), "(the beta, or no launch day: any)")
end

section("Echoes pages: nothing heavy on a tick")
do
	fresh(acct)
	local c0, h0, joins, length = compressCalls, hashCalls, 0, #E.data.open.text
	local function watch()
		if #E.data.open.text ~= length then joins, length = joins + 1, #E.data.open.text end
	end
	E.OnTick(function() if E.data.open then watch() end end)
	for _ = 1, 4 do
		kills(1, 20)
		Advance(29.5, 0.25)
	end
	check(compressCalls == c0 and hashCalls == h0 and joins == 1 and #E.buffer == 20,
		"2 minutes of ticks: no packing, no hashing, the lines joined once a minute")
end

section("Echoes pages: the delivery hears when they change")
do
	-- Delivery caches what I hold (D.Holdings): E.Store tells it of every change, so a page packed
	-- is offered at once, not at Delivery's next look (every 30 s, or when E.data.n moves).
	local D = E.Delivery
	local real, heard = D.PagesChanged, 0
	D.PagesChanged = function() heard = heard + 1 return real() end
	local function held(n) return D.Ranges.Has(D.Holdings()[own] or {}, n) end
	fresh(acct)
	kills(1, 1)
	tick()
	heard = 0
	skew = skew + 1800
	tick()
	local n = E.data.n
	check(heard > 0 and E.data.mine[n].q and not held(n), "a page closed: heard (not offered: it waits to be packed)")
	heard = 0
	tick()
	check(heard > 0 and E.data.mine[n].m == "z" and not held(n), "packed on the next tick: heard (closed this session: offered from the next)")
	-- A page closed as stale at login is on disk: offered as soon as it's packed.
	kills(2, 2)
	reload(11 * 60)
	n = E.data.n
	check(E.data.mine[n].q and E.data.mine[n].z:sub(-5) == ".0;l\n" and held(n - 1) and not held(n), "(a login 11 minutes later: the open page closed as stale, waiting)")
	heard = 0
	tick()
	check(heard > 0 and E.data.mine[n].m == "z" and held(n), "packed on the next tick: heard, and offered at once")
	local function hears(what, fn)
		heard = 0
		local out = fn()
		check(heard > 0, what .. ": heard")
		return out
	end
	local function quiet(what, fn)
		heard = 0
		fn()
		check(heard == 0, what .. ": nothing to hear")
	end
	hears("a friend's page kept", function() return Store.Put(A, B, 1, friendPage(1, E.Now()), "carry") end)
	quiet("one I have", function() Store.Put(A, B, 1, friendPage(1, E.Now()), "carry") end)
	quiet("one refused", function() Store.Put(A, B, 2, { t = E.Now(), h = "00000000", m = "z", z = "QUJD" }, "carry") end)
	hears("a collector's summary", function() Store.Safe(A, B, "5", "c011ec70.12345678") end)
	quiet("the same summary again", function() Store.Safe(A, B, "5", "c011ec70.12345678") end)
	hears("pages dropped", function() Store.Drop(A, B, "1") end)
	quiet("nothing to drop", function() Store.Drop(A, B, "1") end)
	for m = 1, 21 do E.data.mine[100 + m] = { t = E.Now(), h = "x", m = "z", z = ("B"):rep(100 * 1024) } end
	Store.Recount()
	hears("my pages over 2 MB, the oldest dropped", Store.Trim)
	for m = 1, 21 do E.data.mine[100 + m] = nil end
	Store.Recount()
	E.data.carry[A .. ".0c77e1f9"] = { [1] = { t = E.Now(), h = "x", m = "z", z = "QUJD", a = E.Now() - 31 * 86400 } }
	reload(1)
	heard = 0
	Advance(2, 0.25)
	check(heard > 0 and not E.data.carry[A .. ".0c77e1f9"], "relayed pages expired at login: heard")

	-- Delivery's file left out (an older build, or a test): nothing to tell, nothing breaks.
	E.Delivery = nil
	kills(2, 2)
	tick()
	skew = skew + 1800
	tick()
	tick()
	E.Delivery = D
	check(E.data.mine[E.data.n].m == "z", "no delivery: pages still close and pack")
	D.PagesChanged = real
end

section("Echoes pages: the beta")
do
	fresh(acct)
	kills(1, 3)
	E.data.open.state.t = E.Now() - 3600 -- (a stale page: it would close at a login)
	LT:SetModuleEnabled("echoes", false)
	LT.world = "beta"
	inEvent(LT.SetModuleEnabled, LT, "echoes", true)
	local saved, c0, h0, n0 = Saved(), compressCalls, hashCalls, closes
	skew = skew + 3600
	Advance(3, 0.25)
	Fire("PLAYER_LOGOUT")
	check(not E.recording and Saved() == saved and compressCalls == c0 and hashCalls == h0 and closes == n0 and E.Line("k", 1) == nil,
		"on the beta nothing runs: no page closes, opens or joins; the saved table stays as it is")
	LT:SetModuleEnabled("echoes", false)
	LT.world = nil
	start()
	check(E.data.mine[1] and E.data.mine[1].z:sub(-5) == ".0;l\n" and E.data.open.n == 2, "(off the beta again: it closes now)")
end

section("Echoes pages: /lefthy echoes")
local statusExtra, statusRuns, commandRest = false, 0, nil
local EXTRA = "pagestest: a line another file adds" -- (Delivery adds lines of its own)
E.OnStatus(function(add) statusRuns = statusRuns + 1 if statusExtra then add(EXTRA) end end)
E.Command("pagestest", function(rest) commandRest = rest end, "/lefthy echoes pagestest - a test's word")
do
	fresh(acct)
	kills(1, 3)
	tick()
	skew = skew + 1800
	tick()
	tick()
	kills(4, 5)
	Store.Put(A, B, 1, friendPage(1, E.Now()), "carry")
	local mark = #PRINTED + 1
	statusExtra = true
	lefthy("echoes")
	local out = printedSince(mark)
	check(out:find("recording.", 1, true) and out:find(("account %s, store %s."):format(acct, STORE), 1, true)
		and out:find("open page 2: %d+%.%d KB, 4 lines, started 0 min ago")
		and out:find("my pages: 1 %(1%), %d+%.%d KB of 2%.0 MB, 1 offered from the next session on %(a /reload is one%)%.")
		and out:find("relaying: 1 pages of 1 friends' stores, %d+%.%d KB of 512%.0 KB") and not out:find("collected:", 1, true)
		and (out:find(EXTRA, 1, true) or 0) > out:find("relaying:", 1, true), "the status: recording, the account, the open page, my pages, relaying, "
		.. "what other files add; collecting off and nothing collected: no inbox line, got\n" .. out)
	statusExtra = false
	LT:SetModuleSetting(M, "collect", true)
	Store.Put(A, B, 1, friendPage(1, E.Now()), "inbox")
	mark = #PRINTED + 1
	local runs = statusRuns
	lefthy("echoes status")
	out = printedSince(mark)
	check(out:find("collected: 1 pages of 1 stores, %d+%.%d KB; the exporter has 0 stores' pages%."), "collecting: the inbox's size, got\n" .. out)
	check(statusRuns == runs + 1 and not out:find(EXTRA, 1, true), "a file that adds nothing this time: asked again, no line of it, got\n" .. out)
	LT:SetModuleSetting(M, "collect", false)
	MY_BATTLETAG = nil
	fresh()
	mark = #PRINTED + 1
	lefthy("echoes")
	check(printedSince(mark):find(("store %s; your BattleTag isn't known yet."):format(STORE), 1, true)
		and printedSince(mark):find("my pages: 0 (none), 0.0 KB of 2.0 MB.", 1, true), "not known yet; no pages")
	MY_BATTLETAG = "Me#1111"
	LT:SetModuleEnabled("echoes", false)
	mark = #PRINTED + 1
	lefthy("echoes")
	check(printedSince(mark):find("switched off: nothing is recorded.", 1, true), "switched off")
	start()
	lefthy("echoes pagestest a b")
	check(commandRest == "a b", "a word another file added runs with the rest")
	mark = #PRINTED + 1
	lefthy("echoes nope")
	check(printedSince(mark):find("/lefthy echoes [status]", 1, true) and printedSince(mark):find("pagestest - a test's word", 1, true),
		"anything else: the words")
end

section("Echoes pages: the exporter reads them")
do
	-- A session with every kind of page: packed, Base64 of the text, plain, one waiting to be packed;
	-- a friend's in the inbox; the open page.
	fresh(acct)
	E.Anchor(0, -9046, -160, "f", "s")
	E.Zone(1429, "Goldshire")
	E.Point(-9050, -170)
	E.Name("c", 327, "Kobold Vermin")
	E.Line("k", 327, 5, "n", "m")
	E.Name("q", 7, "Kobold Camp; Cleanup, 100%|cff00ff00|r")
	E.Line("Q", 7, 250, 40)
	E.Name("i", 2589, "Linen Cloth \195\164\195\182\195\188")
	E.Line("l", 2589, 2, 1, "l", 327)
	tick()
	skew = skew + 1800
	tick()
	tick()
	E.Line("x", 12, 1500, 3000, 400, 1)
	tick()
	encoding.CompressString = function() return nil end
	skew = skew + 1800
	tick()
	tick()
	encoding.EncodeBase64 = function() return nil end
	E.Line("o", 1)
	tick()
	skew = skew + 1800
	tick()
	tick()
	encoding.CompressString, encoding.EncodeBase64 = countedCompress, realEncode
	E.Line("L", 13, 3600)
	Fire("ECHOES_PAGES_TEST", 170, 200)
	tick() -- (closed, not packed yet)
	Store.Put(A, B, 1, friendPage(1, E.Now()), "inbox")
	kills(1, 2)
	E.Flush()
	local kinds = {}
	for n = 1, E.data.n do kinds[n] = E.data.mine[n].q and "q" or E.data.mine[n].m end
	check(table.concat(kinds, ",") == "z,r,t,q" and E.data.open.n == 5, "(pages of every kind, got " .. table.concat(kinds, ",") .. ")")

	local result = MOCK_EXPORTER(Saved())
	if result == nil then
		io.write("  (skipped: ECHOES_EXPORTER isn't set to the exporter's folder)\n")
	elseif type(result) == "string" then
		check(false, "the exporter: " .. result)
	else
		io.write(("  (the exporter archived %s pages and %s provisionally: %s unreadable, %s wrong hashes, %d warnings)\n")
			:format(tostring(result.new), tostring(result.provisional), tostring(result.bad), tostring(result.hashBad), #result.warnings))
		check(result.bad == 0 and result.hashBad == 0 and #result.warnings == 0, "the exporter reads every page, every hash matches, no warnings: "
			.. table.concat(result.warnings, "; "))
		check(result.new == 5 and result.provisional == 1, "4 of mine and the friend's archived, the open page provisionally, got "
			.. tostring(result.new) .. " and " .. tostring(result.provisional))
		local same = true
		for n = 1, 4 do
			same = same and result.pages[own .. "." .. n] == textOf(E.data.mine[n])
		end
		check(same and result.pages[friend .. ".1"] == textOf(E.data.inbox[friend][1]) and result.open[own .. ".5"] == E.data.open.text,
			"the archived texts are the recorded ones, byte for byte (UTF-8, escapes)")
		local ends, ok = {}, true
		for n = 1, 4 do
			local p = result.parsed[own .. "." .. n]
			ok = ok and p.ok and p.acct == acct and p.store == STORE and p.n == n and p.t0 == E.data.mine[n].t and p.chars == 1 and p.bad == 0
				and p.unknown == ""
			ends[n] = p["end"]
		end
		check(ok and table.concat(ends, ",") == "t,t,t,s", "its parser reads them: header, character, end reasons, got " .. table.concat(ends, ","))
		local first = result.parsed[own .. ".1"]
		check(first.segs == 1 and first.events >= 3, "page 1: one segment, its events")
	end
end

section("Echoes pages: with the capture")
do
	LT.Position, E.PageMayClose = realPosition, realMayClose
	local map, pos = PLAYER_MAP, PLAYER_POS
	local function at(north, west) PLAYER_MAP, PLAYER_POS = 1429, { (1000 - west) / 1000, (1000 - north) / 1000 } end
	at(500, 500)
	fresh(acct)
	local t0 = E.data.open.t0
	Fire("PLAYER_ENTERING_WORLD", true, false) -- (a login: the capture's session starts on the next tick)
	Advance(1, 0.25)
	check(E.buffer[1] == header(1, t0) and E.buffer[2] == charLine() and E.buffer[3]:find("^@%d+;0;500;500;%a;s$"),
		"the header and the character first, then the capture's session anchor (why s), got " .. tostring(E.buffer[3]))
	at(500, 550)
	Advance(2, 0.25)
	skew = skew + 1800
	tick()
	local first = lastClosed
	check(first:find("\n%d+,0,50\n") and E.buffer[1] == header(2, E.Now()) and E.buffer[2] == charLine()
		and E.buffer[3] == "@0;0;500;550;f;c" and E.buffer[4]:find("^z0;1429;"), "a page closes mid-session: the next goes on at the "
		.. "capture's last point (why c) and zone, got " .. table.concat(E.buffer, " | "))
	at(500, 600)
	Advance(2, 0.25)
	check(E.buffer[#E.buffer]:find("^%d+,0,50$"), "the capture's points go on from there, got " .. tostring(E.buffer[#E.buffer]))

	-- Switched off and at logout the capture writes its last lines first; the pages join them after.
	LT:SetModuleEnabled("echoes", false)
	check(#E.buffer == 0 and E.data.open.text:find("\no%d+;0\n$") and E.data.open.n == 2, "switched off: joined with the capture's o0, last")
	inEvent(LT.SetModuleEnabled, LT, "echoes", true)
	Advance(1, 0.25)
	check(E.data.open.n == 2 and E.buffer[1]:find("^@%d+;0;500;600;%a;s$"), "on again soon: the same page, the capture's new session")
	Fire("PLAYER_LOGOUT")
	check(#E.buffer == 0 and E.data.open.text:find("\no%d+;0\n$"), "at logout: joined with the capture's o0, last")

	-- The exporter reads the capture's pages too.
	skew = skew + 1800
	tick()
	tick()
	local result = MOCK_EXPORTER(Saved())
	if type(result) == "table" then
		local clean = true
		for _, p in pairs(result.parsed) do
			clean = clean and p.ok and p.bad == 0 and p.unknown == ""
		end
		check(result.bad == 0 and result.hashBad == 0 and #result.warnings == 0 and result.new == 2 and clean
			and result.pages[own .. ".1"] == first and result.parsed[own .. ".1"].segs >= 1,
			"the exporter reads the pages with the capture's lines: every kind known, nothing unreadable")
	elseif type(result) == "string" then
		check(false, "the exporter: " .. result)
	end
	PLAYER_MAP, PLAYER_POS = map, pos
end

section("Echoes pages: no page closes while the capture waits after a loading screen")
do
	local map, pos = PLAYER_MAP, PLAYER_POS
	local function at(north, west) PLAYER_MAP, PLAYER_POS = 1429, { (1000 - west) / 1000, (1000 - north) / 1000 } end
	at(500, 500)
	fresh(acct)
	Fire("PLAYER_ENTERING_WORLD", true, false)
	Advance(1, 0.25)
	at(500, 520)
	Advance(2, 0.25)
	-- A loading screen; after it the game doesn't say where I am for 2 s, and the page's 30 minutes
	-- are up meanwhile.
	local n, c0 = E.data.open.n, closes
	check(E.data.open.busy, "(a page with the capture's lines on it: its 30 minutes run)")
	Fire("PLAYER_LEAVING_WORLD")
	skew = skew + 1800
	STATE.inInstance = true
	at(800, 800)
	Fire("PLAYER_ENTERING_WORLD", false, false)
	Advance(2, 0.25)
	check(closes == c0 and E.data.open.n == n, "the capture waits for the position after a loading screen: the page stays open")
	STATE.inInstance = false
	tick()
	check(closes == c0 + 1 and E.data.open.n == n + 1 and lastClosed:find("\n@%d+;0;800;800;f;l\n") and E.buffer[3] == "@0;0;800;800;f;c",
		"the position comes: the capture's anchor, then the page closes on that tick; the next goes on from there (not from before "
		.. "the loading screen), got " .. table.concat(E.buffer, " | "))
	PLAYER_MAP, PLAYER_POS = map, pos
end

-- Back as it was: the mock's clock and calls, the beta, Echoes recording nothing.
LT.Position = realPosition
GetServerTime, Fire, LT.Hash32, Store.Close = serverTime, realFire, realHash, realClose
encoding.CompressString, encoding.EncodeBase64 = realCompress, realEncode
C_AddOns.LoadAddOn, LefthyToolsEchoesReceipt, MOCK_RECEIPT = nil, nil, nil
LT:SetModuleSetting(M, "collect", false)
LT:SetModuleEnabled("echoes", false)
LT.world = "beta"
LT:SetModuleEnabled("echoes", true)
check(not E.recording, "(the beta again)")
