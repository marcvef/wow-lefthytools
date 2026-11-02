local _, ns = ...
local LT = ns.LT
local E = ns.Echoes

-- Pages: the recording cut into pages (docs/echoes.md, Pages and storage). A page starts with its
-- header and the character; the capture writes its first anchor when recording starts, and a page
-- that follows one closed mid-session goes on from the last position (E.Continue). The open page is
-- E.data.open: its text so far, the lines not joined yet (E.buffer itself, so whatever is written
-- up to the saving at logout is saved) and the encoder's state (E.state), so a /reload goes on with
-- it. Its lines are joined into the text every 60 s and at logout: never one concatenation per line.
--
-- A page closes on the tick (never inside an event handler) at 32 KB of text or 2,000 lines (".<dt>;s",
-- size), or 30 minutes after its first line other than its own (".<dt>;t", time; 10 minutes while a
-- friend who takes pages early is online: a page leaves me sooner, so a crash loses less; never in
-- combat: after the fight): a page with nothing but its header, the character and the going on from
-- the last page (an AFK night) stays open. E.Store.Close keeps it, and a later tick packs it (Store.lua). When recording starts,
-- an open page of another character, or whose last line is more than 10 minutes old, closes as it
-- was (".0;l"); a fresh one goes on. My pages go out to everyone only once on disk (E.Store): from
-- the next session on, or at once for one closed here from the saved text alone that's stale by its
-- time; before that early to a collector online, who keeps them provisional (Delivery.lua).
--
-- The page id is <acct>.<store>.<n>: acct my BattleTag's hash (E.MyAccount), store this WTF folder's
-- (E.data.store), n one more than the last closed page's (E.data.n).
--
-- Loads after the capture's files: at logout and when switched off their handlers write the last
-- lines before this file joins them. The header still comes first: the capture writes nothing when
-- recording starts (its first line comes on the first tick).

local PAGE_SECONDS = 1800 -- a page closes 30 minutes after its first line other than its own
local PAGE_SECONDS_EARLY = 600 -- (10 while a friend who takes pages early is online),
local PAGE_BYTES = 32768  -- 32 KB of text
local PAGE_LINES = 2000   -- or 2,000 lines
local STALE = 600         -- at the start an open page whose last line is older than this closes
local FLUSH = 60          -- seconds between joining the lines into the open page's text
local ACCOUNT_RETRY = 5   -- seconds between asking for my BattleTag while it isn't known
local EARLY_EVERY = 5     -- seconds an answer whether a friend who takes pages early is online is kept

local issecret = LT.IsSecret

local active          -- the open page this session writes (E.data.open), nil until recording starts
local flushedAt = 0   -- GetTime() of the last join
local accountAt = 0   -- GetTime() of the next ask for my BattleTag
local early, earlyAt = false, -math.huge -- whether a friend who takes pages early is online; GetTime() of that answer

---------------------------------------------------------------------------
-- Who: my account and my character
---------------------------------------------------------------------------

-- My account: LT.Hash32 of my lowercased BattleTag (Chronicle's account hash, Chronicle switched on
-- or not); nil while Battle.net doesn't say.
function E.MyAccount()
	if not BNGetInfo then
		return nil
	end
	local ok, _, tag = pcall(BNGetInfo)
	if ok and type(tag) == "string" and not issecret(tag) and tag ~= "" then
		return LT.Hash32(tag:lower())
	end
end

-- My account as known: now, or the last time it was (E.data.acct, kept).
local function Account()
	local acct = E.MyAccount()
	if acct then
		E.data.acct = acct
	end
	return E.data.acct
end

-- f(...)'s second answer, if the call works and it isn't a secret.
local function Second(f, ...)
	if not f then
		return nil
	end
	local ok, _, v = pcall(f, ...)
	if ok and not issecret(v) then
		return v
	end
end

-- My character: { key ("Anna-Realm", first name and realm), full ("Anna Brook": the surname from
-- UnitName, or Chronicle's record of it), guid, class (its file name), race (its file name), sex,
-- level, faction (English) }. A part the game doesn't say is nil.
function E.Character()
	local ok, full, first, surname = pcall(LT.Names.Mine)
	if not ok or type(first) ~= "string" or issecret(first) then
		full, first, surname = nil, nil, nil
	end
	local realm = LT.Value(GetRealmName)
	local key = first and type(realm) == "string" and (first .. "-" .. realm) or nil
	if key and not surname then
		local chars = type(LefthyToolsChronicleDB) == "table" and type(LefthyToolsChronicleDB.chars) == "table" and LefthyToolsChronicleDB.chars
		local known = chars and type(chars[key]) == "table" and chars[key].full
		if LT.Names.HasSurname(known) and LT.Names.Same(known, first) then
			full = known
		end
	end
	return {
		key = key,
		full = full,
		guid = LT.Value(UnitGUID, "player"),
		class = Second(UnitClass, "player"),
		race = Second(UnitRace, "player"),
		sex = LT.Value(UnitSex, "player"),
		level = LT.Value(UnitLevel, "player"),
		faction = LT.Value(UnitFactionGroup, "player"),
	}
end

---------------------------------------------------------------------------
-- The open page
---------------------------------------------------------------------------

-- "E1;acct;store;n;t0;locale;build;addon": the header (acct empty while not known).
local function Header(n, t0, acct)
	local F = E.Field
	return "E1;" .. F(acct) .. ";" .. F(E.data.store) .. ";" .. F(n) .. ";" .. F(t0) .. ";" .. F(LT.Value(GetLocale)) .. ";"
		.. F(Second(GetBuildInfo)) .. ";" .. F(LT.version)
end

-- A new page, n one more than the last closed one's, from now: its header and the character; goOn:
-- it goes on from the last page (E.Continue: an anchor at the last position, the mode, the zone).
-- These are the page's own lines (open.own: how many): a page with nothing else on it doesn't close
-- by time. (Take the last page's lines first.)
local function StartPage(char, goOn)
	local data = E.data
	local t0, n = E.Now(), data.n + 1
	E.PageStart(t0)
	local acct = Account()
	E.Raw(Header(n, t0, acct))
	E.Line("C", char.key, char.full, char.guid, char.class, char.race, char.sex, char.level, char.faction)
	if goOn then
		E.Continue()
	end
	data.open = { n = n, t0 = t0, char = char.key, guid = char.guid, acct = acct, own = E.count, text = "", buffer = E.buffer,
		state = E.state }
	active = data.open
	flushedAt = GetTime()
end

-- When the open page's 30 minutes run from (E.Now() time), nil while nothing but its own lines is on
-- it: open.busy, noted on the first tick that sees another line. (A page from a build before this
-- rule, without open.own: from its start.)
local function Busy(open)
	if not open.busy then
		if type(open.own) ~= "number" then
			open.busy = open.t0
		elseif E.count > open.own then
			open.busy = E.Now()
		end
	end
	return open.busy
end

-- The lines written so far joined into the open page's text.
local function Flush()
	local open = active
	if not open or E.data.open ~= open then
		return
	end
	if E.buffer[1] then
		open.text = open.text .. E.Take()
	end
	open.buffer, open.state = E.buffer, E.state
	flushedAt = GetTime()
end
E.Flush = Flush -- (for tests)

-- The lines in a text.
local function Lines(text)
	local _, count = text:gsub("\n", "\n")
	return count
end

-- The logout a crash or a disconnect didn't write (the game ended without PLAYER_LOGOUT), at the
-- time of the page's last line (dt 0).
local UNENDED = "o0;0"

-- Whether the session was still going on where a page's text ends: its last session line is a login
-- ("o<dt>;1") with no logout after it, or it has none and goes on from the page before (an anchor
-- with why c). Only from the text, so every load of the same save says the same.
local function Unended(text)
	local last
	for on in text:gmatch("\no%d+;([01])") do
		last = on
	end
	if last then
		return last == "1"
	end
	return text:find("\n@%d+;[^\n]*;c\n") ~= nil
end

-- An open page from before (a /reload, a login soon after) goes on: its text with the lines that
-- weren't joined yet, the encoder's state, its size; the logout first if its session never ended
-- (a crash, a disconnect: saved without one). fromDisk: not the page this session wrote (switched
-- off and on: its lines since are in E.buffer, and its session ended when it was switched off).
local function Resume(open, fromDisk)
	if open.state ~= E.state then
		local state = open.state
		state.names = type(state.names) == "table" and state.names or {}
		state.anchored = state.anchored == true
		E.state = state
	end
	local buffer = open.buffer
	if type(buffer) == "table" and buffer ~= E.buffer and buffer[1] then
		open.text = open.text .. table.concat(buffer, "\n") .. "\n"
	end
	open.buffer = E.buffer
	local waiting = 0
	for i = 1, #E.buffer do
		waiting = waiting + #E.buffer[i] + 1
	end
	E.bytes, E.count = #open.text + waiting, Lines(open.text) + #E.buffer
	active = open
	flushedAt = GetTime()
	if fromDisk and Unended(open.text) then
		E.Raw(UNENDED)
	end
end

-- An open page from before that doesn't go on closes as it was: ".0;l" (stale at login), at the time
-- of its last line (it ends then: state.t; none readable: its start). One with nothing in it, or that
-- can't be a page, goes. onDisk: the page is the saved text and nothing else (E.Store offers it at
-- once, see the start).
local function Retire(open, onDisk)
	local data = E.data
	data.open = nil
	if type(open.n) ~= "number" or open.n <= data.n or type(open.t0) ~= "number" or type(open.text) ~= "string" then
		return
	end
	local text, buffer = open.text, open.buffer
	if buffer == E.buffer then
		text = text .. E.Take()
	elseif type(buffer) == "table" and buffer[1] then
		text = text .. table.concat(buffer, "\n") .. "\n"
	end
	if text ~= "" then
		local state = open.state
		local ended = type(state) == "table" and type(state.t) == "number" and state.t or open.t0
		-- (Its session never ended, a crash or a disconnect: the logout first.)
		E.Store.Close(open.n, open.t0, text .. (Unended(text) and UNENDED .. "\n" or "") .. ".0;l\n", onDisk, ended)
	end
end

-- Whether an open page from before goes on: this character's, its last line at most 10 minutes ago.
local function Fresh(open, char)
	local state = open.state
	if type(open.text) ~= "string" or type(open.n) ~= "number" or open.n <= E.data.n or type(open.t0) ~= "number"
		or type(state) ~= "table" or type(state.t) ~= "number" then
		return false
	elseif open.char ~= char.key or (open.guid and char.guid and open.guid ~= char.guid) then
		return false
	end
	return E.Now() - state.t <= STALE
end

-- Whether an open page from before is stale by its time: its last line more than 10 minutes ago (or
-- none readable). Every later load of the same save finds it so too.
local function Old(open)
	local state = open.state
	return type(state) ~= "table" or type(state.t) ~= "number" or E.Now() - state.t > STALE
end

-- The open page closes (reason "t" or "s"; it ends now), the next one starts and goes on from the
-- last position.
local function Rollover(reason)
	local open = active
	E.Line(".", reason)
	E.Store.Close(open.n, open.t0, open.text .. E.Take(), nil, E.Now())
	E.data.open = nil
	StartPage(E.Character(), true)
end

-- My BattleTag became known: the open page's header gets it (pages closed before keep an empty one).
local function PatchAccount(open)
	local acct = Account()
	if not acct then
		return
	end
	Flush()
	local text, count = open.text:gsub("^E1;;", "E1;" .. acct .. ";", 1)
	if count == 1 then
		open.text = text
		E.bytes = E.bytes + #acct
	end
	open.acct = acct
end

-- Recording starts (login, /reload, switched on): the open page goes on, or closes and a new one starts.
-- A page that closes here counts as on disk (E.Store offers it at once) when it's the saved text
-- alone (not written this session: switched off and on) and stale by its time: any later load of
-- this save, after a crash too, closes it the same way. One closed for another character waits for
-- the next session (back on the first character within 10 minutes, a later load would go on with it).
E.When("start", function()
	local data, char = E.data, E.Character()
	local open, written = data.open, active -- (written: the page this session wrote, if any)
	active = nil
	if type(open) ~= "table" or (type(open.t0) == "number" and LT.BeforeLaunch(open.t0)) then
		data.open = nil -- (from before the launch: never counts)
	elseif Fresh(open, char) then
		Account()
		Resume(open, open ~= written)
	else
		Retire(open, open ~= written and Old(open))
	end
	if not data.open then
		E.Take() -- (nothing may come before the header)
		StartPage(char)
	end
	accountAt = 0
end)

E.When("stop", Flush)
E.On("PLAYER_LOGOUT", Flush) -- (lines written after it are in E.buffer, which is saved with the page)

-- Whether the open page may close now: not while the capture waits for its anchor (a loading screen,
-- and the position after it: up to 3 s), else the next page would go on (E.Continue) from where you
-- were before it, at a time after it. It closes on the first tick the capture is ready again.
function E.PageMayClose()
	return E.capture.Ready()
end

-- Whether a friend who takes my pages early is online (Delivery.lua, loaded after this file; not
-- there: none). Asked at most every EARLY_EVERY seconds (the tick asks 4 times a second).
local function EarlyTaker()
	local now = GetTime()
	if now - earlyAt >= EARLY_EVERY then
		local D = E.Delivery
		early, earlyAt = type(D) == "table" and type(D.EarlyTaker) == "function" and D.EarlyTaker() == true, now
	end
	return early
end

-- Whether a page busy since then is due by time: 30 minutes, or 10 while a friend who takes pages
-- early is online (asked only from 10 minutes on).
local function Due(busy)
	local age = busy and E.Now() - busy
	return age ~= nil and age >= PAGE_SECONDS_EARLY and (age >= PAGE_SECONDS or EarlyTaker())
end

-- The tick: a page that's full, or busy long enough (Due; not in combat: the fight's end), closes
-- (and nothing else this tick); my BattleTag while it isn't known; the lines joined every 60 s.
E.OnTick(function(now)
	local open = active
	if not open or E.data.open ~= open then
		return
	end
	local busy = Busy(open)
	local full = E.bytes >= PAGE_BYTES or E.count >= PAGE_LINES
	if (full or (Due(busy) and not E.InFight())) and E.PageMayClose() then
		Rollover(full and "s" or "t")
		return
	end
	if not open.acct and now >= accountAt then
		accountAt = now + ACCOUNT_RETRY
		PatchAccount(open)
	end
	if now - flushedAt >= FLUSH then
		Flush()
	end
end)
