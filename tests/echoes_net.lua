-- Echoes' delivery (Delivery.lua) and Beacon's B family: the messages, what friends hold and what's
-- safe, who gets B at all, serving within the budget, pulling, checks and resuming, relaying, dropping
-- copies once safe, switching off, the probe, and three clients (author, relay, collector) passing
-- pages between them; early pages (a collector online keeps them provisional until a copy from the
-- author's disk confirms them) through crashes on either side, and what both sides' /lefthy echoes
-- says of them.
--
-- Every client here is a game of its own: mock.lua and the addon loaded into an environment of their
-- own (a table as their _ENV, in this Lua state) with their own clock, Battle.net friends and saved
-- variables. The harness below starts, stops and reloads them (saved variables copied over, like
-- the game writes and reads them) and carries Battle.net messages between the ones running. In the
-- first parts one client talks to friends the test plays itself (it says what they'd send, and
-- reads what the client sent them); the last part runs three clients and an older build together.
-- Needs: no other file (its clients are its own; the suite's state is left alone).
local suite = ...
local check, section = suite.check, suite.section
local Hash32 = suite.LT.Hash32

---------------------------------------------------------------------------
-- The harness
---------------------------------------------------------------------------

-- What every client shares: Lua's libraries and whatever run.js gave the state (functions from JS,
-- and tests/native.js's C_EncodingUtil: Node's real zlib).
local STD = { string = true, table = true, math = true, os = true, io = true, debug = true, coroutine = true, utf8 = true,
	package = true, C_EncodingUtil = true }
local BASE = { _VERSION = _VERSION }
for k, v in pairs(_G) do
	if STD[k] or (type(v) == "function" and debug.getinfo(v, "S").what ~= "Lua") then
		BASE[k] = v
	end
end
local BASE_META = { __index = BASE }

local NEW, OLD = "0.6.0-30-gabc1234", "0.6.0-10-gabc1234" -- a build with Echoes' delivery, one before it
local SAVED = { "LefthyToolsDB", "LefthyToolsChronicleDB", "LefthyToolsBestiaryDB", "LefthyToolsEchoesDB" }

local function Person(id, name, class, tag, store)
	return { id = id, name = name, class = class, tag = tag, guid = "Player-1-" .. id, acct = Hash32(tag:lower()), store = store }
end
-- (stores: what the friends the test plays say; a client makes its own)
local ANNA = Person(11, "Anna Brook", "MAGE", "Annie#1234", "a1a1a1a1")
local BOB = Person(12, "Bob Stone", "WARRIOR", "Bobby#2345", "b2b2b2b2")
local CEDRIC = Person(13, "Cedric Vale", "ROGUE", "Cedric#3456", "c3c3c3c3")
local DORA = Person(14, "Dora Reed", "PRIEST", "Dora#4567", "d4d4d4d4")
local EVE = Person(15, "Eve Marsh", "DRUID", "Eve#5678", "e5e5e5e5") -- nobody's friend here but Anna's
local FINN = Person(16, "Finn Hale", "HUNTER", "Finn#6789", "f6f6f6f6") -- runs an older LefthyTools
local GWEN = Person(17, "Gwen Ash", "PALADIN", "Gwen#7890", "a7a7a7a7") -- updates from just before Delivery to it
for _, p in ipairs({ ANNA, BOB, CEDRIC, DORA, EVE, FINN, GWEN }) do
	p.key = p.acct .. "." .. p.store
end

-- Saved variables as the game keeps them: plain data, copied (nothing shared between two sessions).
local function Copy(v)
	if type(v) ~= "table" then
		return type(v) ~= "function" and v or nil
	end
	local t = {}
	for k, x in pairs(v) do
		if type(k) == "string" or type(k) == "number" then
			t[k] = Copy(x)
		end
	end
	return t
end

local world = { time = 0, list = {}, byId = {}, log = {}, errors = {}, leaked = {} }

local function Account(p, online)
	return { gameAccountID = p.id, isOnline = online, clientProgram = "WoW", wowProjectID = 1, isInCurrentRegion = true,
		characterName = p.name, classFilename = p.class, characterLevel = 20, areaName = "Elwynn Forest", playerGuid = p.guid,
		isGameAFK = false, isGameBusy = false, realmName = "Realmy", factionName = "Alliance" }
end

-- A client starts (the game with LefthyTools on the release): p is who plays. opts: friends (people
-- on their Battle.net friend list; online if running, or if fake), version (their LefthyTools), saved
-- (saved variables), without (a file left out: an older build), collect / relay (Echoes' settings).
local function Start(p, opts)
	opts = opts or {}
	local env = setmetatable({}, BASE_META)
	env._G = env
	assert(loadfile("tests/mock.lua", "t", env))()
	local printed = env.PRINTED
	env.print = function(...) -- (quiet: kept for checks, not written out)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring(select(i, ...))
		end
		printed[#printed + 1] = table.concat(parts, " ")
	end
	env.geterrorhandler = function()
		return function(err)
			env.ERRORS[#env.ERRORS + 1] = tostring(err)
			io.write("    [" .. p.name .. "'s error handler] " .. tostring(err) .. "\n")
		end
	end
	if world.time > 0 then
		env.Advance(world.time, world.time) -- (the clock as late as everyone's)
	end
	env.MOCK_CLIENT, env.MOCK_BUILD = { beta = false, test = false, ptr = false }, "70532"
	env.MOCK_VERSION = opts.version or NEW
	env.MY_BATTLETAG, env.MY_GUID = p.tag, p.guid
	env.BN_FRIENDS = {}
	for _, f in ipairs(opts.friends or {}) do
		env.BN_FRIENDS[#env.BN_FRIENDS + 1] = { Account(f, world.byId[f.id] ~= nil or opts.fake == true), battleTag = f.tag }
	end
	for _, name in ipairs(SAVED) do
		env[name] = Copy(opts.saved and opts.saved[name])
	end
	local before = {}
	for k in pairs(env) do
		before[k] = true
	end
	local ns = {}
	for _, file in ipairs(SOURCES) do
		if not (opts.without and file.name == opts.without) then
			assert(load(file.src, "@Interface/AddOns/LefthyTools/" .. file.name, "t", env))("LefthyTools", ns)
		end
	end
	env.Fire("ADDON_LOADED", "LefthyTools")
	env.Fire("PLAYER_LOGIN")
	env.Fire("PLAYER_ENTERING_WORLD", true, false)
	local c = { who = p, env = env, ns = ns, E = ns.Echoes, D = ns.Echoes.Delivery, B = ns.Beacon, LT = env.LefthyTools,
		opts = opts, read = 0, before = before, alive = {} }
	if c.E.module.db then
		if opts.collect ~= nil then
			c.E.module.db.collect = opts.collect
		end
		if opts.relay ~= nil then
			c.E.module.db.relay = opts.relay
		end
	end
	if not opts.fake then
		world.list[#world.list + 1] = c
		world.byId[p.id] = c
		for _, other in ipairs(world.list) do
			for _, entry in ipairs(other.env.BN_FRIENDS) do
				if entry.battleTag == p.tag and not entry[1].isOnline then
					entry[1].isOnline = true
					other.env.Fire("BN_FRIEND_ACCOUNT_ONLINE")
				end
			end
		end
	end
	return c
end

-- What a client leaves behind: no errors, no globals leaked (ours start with LefthyTools; all caps
-- are the game's and the mock's knobs).
local function Leftovers(c)
	local leaked = {}
	for k in pairs(c.env) do
		if not c.before[k] and type(k) == "string" and not k:match("^[A-Z][A-Z0-9_]*$") and not k:match("^LefthyTools") then
			leaked[#leaked + 1] = k
		end
	end
	table.sort(leaked)
	check(#c.env.ERRORS == 0, c.who.name .. "'s client: no errors, got " .. table.concat(c.env.ERRORS, " | "))
	check(#leaked == 0, c.who.name .. "'s client: no accidental globals, found: " .. table.concat(leaked, ", "))
end

-- The game closes: saved variables written (returned), friends see them go offline (not on a reload).
-- crash: nothing fired, nothing saved (nil returned).
local function Stop(c, reload, crash)
	local saved
	if not crash then
		c.env.Fire("PLAYER_LOGOUT")
		saved = {}
		for _, name in ipairs(SAVED) do
			saved[name] = Copy(c.env[name])
		end
	end
	Leftovers(c)
	for i = #world.list, 1, -1 do
		if world.list[i] == c then
			table.remove(world.list, i)
		end
	end
	world.byId[c.who.id] = nil
	if not reload then
		for _, other in ipairs(world.list) do
			for _, entry in ipairs(other.env.BN_FRIENDS) do
				if entry.battleTag == c.who.tag and entry[1].isOnline then
					entry[1].isOnline = false
					other.env.Fire("BN_FRIEND_ACCOUNT_OFFLINE")
				end
			end
		end
	end
	return saved
end

-- /reload: the same player, the next session.
local function Reload(c)
	local opts = c.opts
	opts.saved = Stop(c, true)
	opts.collect, opts.relay = nil, nil -- (the settings are saved)
	return Start(c.who, opts)
end

-- Battle.net messages sent since the last look go to their receivers (the ones running).
local function Deliver()
	for _, c in ipairs(world.list) do
		local sent = c.env.GAMEDATA
		for i = c.read + 1, #sent do
			local m = sent[i]
			world.log[#world.log + 1] = { from = c.who.id, to = m.id, data = m.data, at = world.time, client = c }
			local target = world.byId[m.id]
			if target then
				target.env.Fire("BN_CHAT_MSG_ADDON", m.prefix, m.data, "WHISPER", c.who.id)
			end
		end
		c.read = #sent
	end
end

-- Time passes for every client running, in steps, messages carried after each. until(): stop early.
local function Run(seconds, until_, step)
	step = step or 0.1
	local t = 0
	while t < seconds - 1e-9 do
		local dt = math.min(step, seconds - t)
		for _, c in ipairs(world.list) do
			c.env.Advance(dt, dt)
		end
		world.time, t = world.time + dt, t + dt
		Deliver()
		if until_ and until_() then
			return true
		end
	end
	return until_ == nil
end

-- One client alone, with friends the test plays (fakes): f says text to c.
local function Say(c, f, text)
	c.env.Fire("BN_CHAT_MSG_ADDON", "LTBeacon", text, "WHISPER", f.id)
end

-- Time passes for one client; the friends it knows (c.alive) say something now and then (Beacon
-- forgets a friend after 65 s of silence). each(): after every step.
local function Pass(c, seconds, step, each)
	step = step or 0.1
	local t = 0
	while t < seconds - 1e-9 do
		local dt = math.min(step, seconds - t)
		c.env.Advance(dt, dt)
		t = t + dt
		local now = c.env.GetTime()
		if now - (c.keptAt or 0) >= 15 then
			c.keptAt = now
			for _, f in ipairs(c.alive) do
				Say(c, f, "S2;;;;;;")
			end
		end
		if each then
			each()
		end
	end
end

-- What c sent to f since mark (an index into its GAMEDATA) that starts with prefix.
local function Sent(c, f, mark, prefix)
	local list = {}
	for i = mark, #c.env.GAMEDATA do
		local m = c.env.GAMEDATA[i]
		if m.id == f.id and m.data:sub(1, #prefix) == prefix then
			list[#list + 1] = m.data
		end
	end
	return list
end
local function Mark(c)
	return #c.env.GAMEDATA + 1
end

-- f starts LefthyTools (build version) and c meets them: hello, their build, then Battle.net's name.
local function Meet(c, f, version)
	Say(c, f, "H2")
	Say(c, f, "V2;" .. version)
	c.alive[#c.alive + 1] = f
	Pass(c, 1.3)
end

-- f goes offline (Battle.net says so; they say nothing more), or comes back.
local function Online(c, f, online)
	for _, entry in ipairs(c.env.BN_FRIENDS) do
		if entry.battleTag == f.tag then
			entry[1].isOnline = online
		end
	end
	for i = #c.alive, 1, -1 do
		if c.alive[i] == f then
			table.remove(c.alive, i)
		end
	end
	c.env.Fire(online and "BN_FRIEND_ACCOUNT_ONLINE" or "BN_FRIEND_ACCOUNT_OFFLINE")
end

-- f's Echoes says hello to c. flags: c collect, r relay, s share, a answer.
local function Hello(c, f, flags, acct)
	Say(c, f, ("B2;eh;%s;%s;1;255;%s"):format(acct or f.acct, f.store, flags))
	Pass(c, 2)
end

-- A page's Base64 text: len bytes from the alphabet, the same for the same seed.
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function Data(len, seed)
	local t, x = {}, seed
	for i = 1, len do
		x = (x * 1103515245 + 12345) % 2147483648
		local k = math.floor(x / 65536) % 64 + 1
		t[i] = B64:sub(k, k)
	end
	return table.concat(t)
end

-- A closed page of c's own (put straight into the saved table, as Pages.lua would): n, its length.
-- The saved table changed by the test, not through E.Store: its sizes counted anew, Delivery looks again.
local function Touched(c)
	c.E.Store.Recount()
	c.D.PagesChanged()
end

-- (Pages.lua numbers its pages from E.data.n on: the client's own are 1, opened at login, and from
-- 1001 on, since E.data.n is set to 1000 here; the test's are 100 to 999.) Closed in an earlier
-- session (s): on disk, so offered (E.Store offers my pages only from the session after they closed).
local function MyPage(c, n, len, m)
	local z = Data(len, n * 7919 + #c.who.name)
	local page = { t = c.env.GetServerTime() - 3600 + (n % 100) * 30, h = Hash32(z), m = m or "z", z = z, s = c.E.data.session - 1 }
	c.E.data.mine[n] = page
	c.E.data.n = math.max(c.E.data.n, 1000)
	Touched(c)
	return page
end

-- A friend's page: what they'd send for it.
local function TheirPage(c, n, len, seed)
	local z = Data(len, seed or n)
	return { n = n, z = z, h = Hash32(z), t = c.env.GetServerTime() - 7200 + n * 60, len = len }
end

-- f sends c page pg as transfer x, from offset (to upTo, default the end).
local function SendPage(c, f, owner, pg, x, offset, upTo, hash)
	Say(c, f, ("B2;eb;%d;%s;%s;%d;%d;%s;%d;z"):format(x, owner.acct, owner.store, pg.n, pg.len, hash or pg.h, pg.t))
	offset = offset or 0
	while offset < (upTo or pg.len) do
		Say(c, f, ("B2;ep;%d;%d;%s"):format(x, offset, pg.z:sub(offset + 1, offset + 240)))
		offset = offset + 240
	end
end

-- The page put together from c's eb/ep messages to f since mark (parts by offset).
local function Received(c, f, mark)
	local parts, x, len = {}, nil, nil
	for _, m in ipairs(Sent(c, f, mark, "B2;e")) do
		local bx, blen = m:match("^B2;eb;(%d+);%x+;%x+;%d+;(%d+);")
		if bx then
			x, len = bx, tonumber(blen)
		end
		local px, offset, data = m:match("^B2;ep;(%d+);(%d+);(.*)$")
		if px and px == x then
			parts[tonumber(offset)] = data
		end
	end
	local out, offset = {}, 0
	while parts[offset] do
		out[#out + 1] = parts[offset]
		offset = offset + #parts[offset]
	end
	return table.concat(out), len
end

-- A table's keys, sorted; numbers only 100 to 999 (the test's pages, not the client's own).
local function Keys(t)
	local list = {}
	for k in pairs(t or {}) do
		if type(k) ~= "number" or (k >= 100 and k < 1000) then
			list[#list + 1] = k
		end
	end
	table.sort(list, function(a, b)
		if type(a) == "number" and type(b) == "number" then
			return a < b
		end
		return tostring(a) < tostring(b)
	end)
	return table.concat(list, ",")
end

---------------------------------------------------------------------------
-- Beacon's B family, with a module's hooks played by the test
---------------------------------------------------------------------------

section("Beacon: the B family (other modules' messages)")
do
	local c = Start(CEDRIC, { friends = { ANNA, BOB, FINN }, fake = true })
	local B = c.B
	local kind, word, more = B.Parse("B2;eq;1a2b3c4d;9f3a61c2;214;0")
	check(kind == "B" and word == "eq" and more == "1a2b3c4d;9f3a61c2;214;0", "B2: a module's letter and word, then its fields")
	local refused = true
	for _, bad in ipairs({ "B2;e;x", "B2;EH;x", "B2;eh", "B2;ehx;1", "B2eh;1", "B2;;x", "B2;e1;x", "B2;eq;" .. ("1"):rep(250) }) do
		refused = refused and B.Parse(bad) == nil
	end
	check(refused and select(1, B.Parse("B3;eh;x")) == "version", "malformed ones and ones over 255 bytes refused; another version is one")

	-- A module's hooks (Echoes' Delivery.lua sets them), played by the test.
	local kept = { B.ReceiveEchoes, B.EchoesAnswer, B.EchoesForget, B.EchoesStop, B.ReceiveProbe }
	local heard, answered, forgot, probes, stopped = {}, {}, {}, {}, 0
	B.ReceiveEchoes = function(id, w, m) heard[#heard + 1] = id .. " " .. w .. " " .. m end
	B.EchoesAnswer = function(id) answered[#answered + 1] = id end
	B.EchoesForget = function(id) forgot[#forgot + 1] = id end
	B.EchoesStop = function() stopped = stopped + 1 end
	B.ReceiveProbe = function(id, text) probes[#probes + 1] = id .. " " .. #text end
	Meet(c, ANNA, NEW)
	check(answered[1] == ANNA.id, "Beacon answers a friend's hello: the module hears it (to send its own hello)")
	Say(c, ANNA, "B2;eh;1a2b3c4d;9f3a61c2;1;255;s")
	Say(c, ANNA, "B2;xy;another module's word")
	Pass(c, 0.2)
	check(#heard == 1 and heard[1] == "11 eh 1a2b3c4d;9f3a61c2;1;255;s", "e words go to Echoes' hook; other letters to nobody yet")
	check(c.B.peers[ANNA.id] and not c.B.peers[ANNA.id].blank, "(Anna is still a friend with the addon)")

	-- At most 400 a minute from one friend (and 20 a second, Beacon's flood guard for everything).
	Pass(c, 61)
	wipe(heard)
	for _ = 1, 22 do -- (418 in 23 s)
		for _ = 1, 19 do
			Say(c, ANNA, "B2;ep;1;0;QUJD")
		end
		Pass(c, 1.05)
	end
	check(#heard == 400, "at most 400 a minute from one friend, got " .. #heard)
	Pass(c, 40)
	Say(c, ANNA, "B2;ep;1;0;QUJD")
	Pass(c, 0.2)
	check(#heard == 401, "the next minute: again")

	-- Echoes' probe, bigger than any other message: from a friend Beacon knows, at most 10 a minute.
	for i = 1, 11 do
		Say(c, ANNA, "B2;ex;2000;" .. ("x"):rep(2000 - 11))
	end
	Say(c, ANNA, ("x"):rep(2000))
	Say(c, DORA, "B2;ex;2000;" .. ("x"):rep(2000 - 11))
	Say(c, ANNA, "B2;ex;5000;" .. ("x"):rep(5000 - 11))
	Pass(c, 0.2)
	check(#probes == 10 and probes[1] == "11 2000" and not c.B.peers[DORA.id], "probes: 10 a minute, only from a friend known, up to 4100 bytes")

	-- What Echoes reads off Beacon: the queues, the last throttle.
	local waiting = B.Waiting()
	B.QueueLow(BOB.id, "K2;20300515;1")
	B.QueueLow(BOB.id, "K2;20300515;2")
	B.Queue(ANNA.id, "M2;hi")
	check(B.Waiting() == waiting + 3 and B.PREFIX == "LTBeacon", "B.Waiting: every message still waiting, in every queue")
	c.env.MOCK_SEND_RESULT = 11
	Pass(c, 0.15, 0.05)
	c.env.MOCK_SEND_RESULT = nil
	check(B.throttledAt and math.abs(B.throttledAt - c.env.GetTime()) < 0.2 and B.throttleResult == 11, "a lockdown: its time and result")
	Pass(c, 3)
	check(B.Waiting() == 0, "(sent after Beacon's pause)")

	-- A friend gone; Beacon switched off.
	Online(c, ANNA, false)
	Pass(c, 1.5)
	check(forgot[1] == ANNA.id, "a friend gone: the module hears it")
	c.LT:SetModuleEnabled("beacon", false)
	check(stopped == 1, "Beacon off: the module hears it")
	B.ReceiveEchoes, B.EchoesAnswer, B.EchoesForget, B.EchoesStop, B.ReceiveProbe = kept[1], kept[2], kept[3], kept[4], kept[5]
	Stop(c)
end

---------------------------------------------------------------------------
-- One client, friends played by the test
---------------------------------------------------------------------------

section("Echoes' delivery: the B messages")
local me = Start(CEDRIC, { friends = { ANNA, BOB, DORA, FINN }, fake = true })
local B, D, LT, E = me.B, me.D, me.LT, me.E
CEDRIC.store = E.data.store
CEDRIC.key = CEDRIC.acct .. "." .. CEDRIC.store
E.data.n = 1000 -- (the client's own pages: 1 and from 1001 on; see MyPage)
do
	check(LT.world == "release" and E.recording and D and B.ReceiveEchoes and B.EchoesAnswer and B.EchoesForget and B.EchoesStop
		and B.ReceiveProbe, "the release: Echoes records, Delivery's hooks are in Beacon")
	check(E.Store.Own() == CEDRIC.key, "E.Store knows my key (my BattleTag's hash and this store)")

	local R = D.Read
	local eh = R("eh", "1a2b3c4d;9f3a61c2;1;255;crsa")
	check(eh and eh.acct == "1a2b3c4d" and eh.store == "9f3a61c2" and eh.proto == 1 and eh.maxBytes == 255 and eh.collect and eh.relay
		and eh.share and eh.answer, "eh: account, store, proto, size, flags")
	local off = R("eh", "1a2b3c4d;9f3a61c2;1;255;")
	check(off and not (off.collect or off.relay or off.share or off.answer) and R("eh", "1a2b3c4d;9f3a61c2;2;500;s;later") ~= nil,
		"eh without flags (switched off); later builds' extra fields are fine")
	local es = R("es", "1a2b3c4d.9f3a61c2:1-56,58/5e6f7a8b.0c77e1f2:200-213")
	check(es and #es.items == 2 and es.items[1][1] == "1a2b3c4d.9f3a61c2" and es.items[1][2] == "1a2b3c4d"
		and D.Ranges.Format(es.items[1][3]) == "1-56,58" and D.Ranges.Format(es.items[2][3]) == "200-213", "es: holdings per store")
	local ed = R("ed", "5e6f7a8b;0c77e1f2;1a2b3c4d.9f3a61c2:1-50")
	check(ed and ed.acct == "5e6f7a8b" and ed.store == "0c77e1f2" and D.Ranges.Format(ed.items[1][3]) == "1-50", "ed: safe at a collector")
	local eq = R("eq", "1a2b3c4d;9f3a61c2;214;480")
	check(eq and eq.n == 214 and eq.offset == 480 and R("eq", "1a2b3c4d;9f3a61c2;214;65536").offset == 65536, "eq: page and offset")
	local eb = R("eb", "7;1a2b3c4d;9f3a61c2;214;3000;0badc0de;1793452800;z")
	check(eb and eb.x == 7 and eb.n == 214 and eb.len == 3000 and eb.hash == "0badc0de" and eb.t0 == 1793452800 and eb.m == "z"
		and R("eb", "7;1a2b3c4d;9f3a61c2;214;3000;0badc0de;1793452800;r").m == "r", "eb: transfer, page, length, hash, start, mode")
	local ep = R("ep", "7;480;QUJD+/9=")
	check(ep and ep.x == 7 and ep.offset == 480 and ep.data == "QUJD+/9=", "ep: transfer, offset, Base64")
	local en = R("en", "1a2b3c4d;9f3a61c2;214")
	check(en and en.n == 214, "en: the page")
	local bad = {
		{ "eh", "1A2B3C4D;9f3a61c2;1;255;s" }, { "eh", "1a2b3c4;9f3a61c2;1;255;s" }, { "eh", "1a2b3c4d;9f3a61c2;1;255;CR" },
		{ "eh", "1a2b3c4d;9f3a61c2;x;255;s" }, { "eh", "1a2b3c4d;9f3a61c2;1;255" },
		{ "es", "1a2b3c4d:1-5" }, { "es", "1a2b3c4d.9f3a61c2:3-1" }, { "es", "1a2b3c4d.9f3a61c2:0" }, { "es", "1a2b3c4d.9f3a61c2:1,,2" },
		{ "es", "1a2b3c4d.9f3a61c2:1;x" }, { "es", "" },
		{ "ed", "5e6f7a8b;0c77e1f2" }, { "ed", "5e6f7a8;0c77e1f2;1a2b3c4d.9f3a61c2:1" },
		{ "eq", "1a2b3c4d;9f3a61c2;0;0" }, { "eq", "1a2b3c4d;9f3a61c2;1;65537" }, { "eq", "1a2b3c4d;9f3a61c2;1" },
		{ "eq", "1a2b3c4d;9f3a61c2;1;0;5" },
		{ "eb", "0;1a2b3c4d;9f3a61c2;1;30;0badc0de;1793452800;z" }, { "eb", "100;1a2b3c4d;9f3a61c2;1;30;0badc0de;1793452800;z" },
		{ "eb", "7;1a2b3c4d;9f3a61c2;1;0;0badc0de;1793452800;z" }, { "eb", "7;1a2b3c4d;9f3a61c2;1;65537;0badc0de;1793452800;z" },
		{ "eb", "7;1a2b3c4d;9f3a61c2;1;30;0badc0de;1793452800;t" }, { "eb", "7;1a2b3c4d;9f3a61c2;1;30;0BADC0DE;1793452800;z" },
		{ "eb", "7;1a2b3c4d;9f3a61c2;1;30;0badc0de;17934528000;z" }, { "eb", "7;1a2b3c4d;9f3a61c2;1;30;0badc0de;1793452800" },
		{ "ep", "7;480;QUJD!" }, { "ep", "7;65536;QUJD" }, { "ep", "a;0;QUJD" }, { "ep", "7;0;" },
		{ "en", "1a2b3c4d;9f3a61c2;0" }, { "en", "1a2b3c4d;9f3a61c2" },
		{ "ez", "1" },
	}
	local all = true
	for _, b in ipairs(bad) do
		if R(b[1], b[2]) ~= nil then
			all = false
			io.write("    (read: " .. b[1] .. ";" .. b[2] .. ")\n")
		end
	end
	check(all, "malformed fields of every word are refused (" .. #bad .. " cases)")
end

section("Echoes' delivery: ranges, summaries in messages")
do
	local R = D.Ranges
	check(R.Format(R.Parse("58,1-56")) == "1-56,58" and R.Format(R.Parse("1-3,4-6,10,11")) == "1-6,10-11"
		and R.Format(R.Parse("5-9,1-6")) == "1-9", "parsed: sorted, overlapping and adjacent ones joined")
	check(#R.Parse("") == 0 and R.Parse("3-1") == nil and R.Parse("0") == nil and R.Parse("1,,2") == nil and R.Parse("a") == nil
		and R.Parse("1-") == nil and R.Parse(nil) == nil and R.Parse("99999999999") == nil, "empty is none; anything else odd is refused")
	local many = {}
	for i = 1, 301 do
		many[i] = tostring(i * 2)
	end
	check(R.Parse(table.concat(many, ",", 1, 300)) ~= nil and R.Parse(table.concat(many, ",")) == nil, "at most 300 intervals")
	check(R.Format(R.Union(R.Parse("1-5,9"), R.Parse("6-7,20"))) == "1-7,9,20", "union")
	check(R.Format(R.Minus(R.Parse("1-10,15-20"), R.Parse("3-4,10-16,19"))) == "1-2,5-9,17-18,20"
		and R.Format(R.Minus(R.Parse("1-5"), R.Parse(""))) == "1-5" and #R.Minus(R.Parse("2-3"), R.Parse("1-9")) == 0
		and R.Format(R.Minus(R.Parse("1-3,7-9"), R.Parse("2,8"))) == "1,3,7,9", "minus")
	local list = R.Parse("1-5,9")
	check(R.Has(list, 1) and R.Has(list, 9) and not R.Has(list, 6) and not R.Has(list, 10) and not R.Has(list, 0), "has")
	check(R.Parse("999999999") ~= nil and R.Parse("1000000000") == nil, "page numbers up to E.Store's 999,999,999")
	local stored = E.Ranges.Union("1-3,9", "5,4")
	check(stored == "1-5,9" and R.Format(R.Parse(stored)) == stored, "the same strings as E.Ranges writes (E.Store's)")

	-- A long, gappy list in pieces that fit; packed into messages of at most 255 bytes.
	local gappy = {}
	for i = 1, 150 do
		gappy[i] = { i * 3, i * 3 + 1 }
	end
	local items = {}
	D.WriteItems(ANNA.key, gappy, 249, items)
	local fit, back = true, {}
	for _, item in ipairs(items) do
		fit = fit and #item <= 249 and item:sub(1, #ANNA.key + 1) == ANNA.key .. ":"
		back = R.Union(back, R.Parse(item:sub(#ANNA.key + 2)))
	end
	check(#items > 1 and fit and R.Format(back) == R.Format(gappy), "a long list goes in pieces, all of it")
	local messages = D.Pack("B2;es;", items)
	local short, joined = true, {}
	for _, m in ipairs(messages) do
		short = short and #m <= 255 and B.Parse(m) == "B"
		joined[#joined + 1] = m:sub(7)
	end
	check(#messages > 1 and short and table.concat(joined, "/") == table.concat(items, "/"),
		"packed into messages of at most 255 bytes that Beacon reads, got " .. #messages)
end

section("Echoes' delivery: who gets B (hellos, builds, accounts)")
do
	local mark = Mark(me)
	Say(me, ANNA, "H2")
	me.alive[#me.alive + 1] = ANNA
	Pass(me, 1.5)
	check(#Sent(me, ANNA, mark, "S2;") >= 1 and #Sent(me, ANNA, mark, "B2;") == 0, "Anna says hello: Beacon answers; no B while her build isn't known")
	Say(me, ANNA, "V2;" .. NEW)
	Pass(me, 1.5)
	local eh = Sent(me, ANNA, mark, "B2;eh;")
	check(#eh == 1 and eh[1] == ("B2;eh;%s;%s;1;255;rs"):format(CEDRIC.acct, CEDRIC.store),
		"her build reads B: my hello (relay on, collect off, sharing; it asks for hers), got " .. tostring(eh[1]))
	check(#Sent(me, ANNA, mark, "B2;") == 1, "... and nothing else before hers")

	mark = Mark(me)
	Hello(me, ANNA, "csa")
	local peer = D.peers[ANNA.id]
	check(peer and peer.verified == true and peer.collect and peer.share and not peer.relay and #Sent(me, ANNA, mark, "B2;eh;") == 0,
		"her answer: her account is the one Battle.net says, she collects; an answer gets none back")
	Pass(me, 1)
	check(#Sent(me, ANNA, mark, "B2;es;") == 0, "no pages of mine yet: nothing offered")
	Hello(me, ANNA, "cs")
	local back = Sent(me, ANNA, mark, "B2;eh;")
	check(#back == 1 and back[1]:sub(-4) == ";rsa", "her hello (she restarted): answered once, as an answer, got " .. tostring(back[1]))

	-- Finn runs an older LefthyTools: he never gets B, also when he says hello again and again.
	mark = Mark(me)
	Meet(me, FINN, OLD)
	Say(me, FINN, "H2")
	Pass(me, 70)
	Say(me, FINN, "H2")
	Pass(me, 10)
	check(#Sent(me, FINN, mark, "V2;") >= 1 and #Sent(me, FINN, mark, "B2;") == 0, "Finn (an older build): Beacon as ever, never a B message")
	Say(me, FINN, "V2;0.6.0")
	Say(me, FINN, "H2")
	Pass(me, 70)
	check(#Sent(me, FINN, mark, "B2;") == 0, "nor on the tagged release before it (no commit count: not newer)")

	-- Bob says he's Anna: not believed; nothing exchanged. Then rightly: he is.
	mark = Mark(me)
	Meet(me, BOB, NEW)
	Hello(me, BOB, "rs", ANNA.acct)
	check(D.peers[BOB.id] and D.peers[BOB.id].verified == false and D.stats.rejected >= 1, "an eh with another account than Battle.net's: refused")
	Say(me, BOB, ("B2;eq;%s;%s;1;0"):format(CEDRIC.acct, CEDRIC.store))
	Pass(me, 2)
	check(#Sent(me, BOB, mark, "B2;en;") == 0, "... his requests get nothing (not even \"don't have\")")
	Hello(me, BOB, "rs")
	check(D.peers[BOB.id].verified == true, "he says hello as himself: taken")
end

section("Echoes' delivery: serving, within the budget")
do
	-- My pages: 501-503 (2400 bytes: 10 parts each), 504 plain text (never shared).
	local pages = {}
	for n = 501, 503 do
		pages[n] = MyPage(me, n, 2400)
	end
	MyPage(me, 504, 500, "t")
	local mark = Mark(me)
	Pass(me, 62) -- (the next summary)
	local es = Sent(me, ANNA, mark, "B2;es;")
	check(#es == 1 and es[1] == "B2;es;" .. CEDRIC.key .. ":501-503", "my pages offered to the collector, not the plain-text one, got " .. tostring(es[1]))
	check(#Sent(me, BOB, mark, "B2;es;") == 1, "... and to the relay")

	-- Anna asks for page 501, Bob for 502: both served, by turns, within the budget.
	mark = Mark(me)
	local most = 0
	Say(me, ANNA, ("B2;eq;%s;%s;501;0"):format(CEDRIC.acct, CEDRIC.store))
	Say(me, BOB, ("B2;eq;%s;%s;502;0"):format(CEDRIC.acct, CEDRIC.store))
	Pass(me, 12, 0.05, function()
		most = math.max(most, D.Outstanding())
	end)
	local a, b = Sent(me, ANNA, mark, "B2;e"), Sent(me, BOB, mark, "B2;e")
	check(#a == 11 and #b == 11 and a[1]:find("^B2;eb;%d+;" .. CEDRIC.acct .. ";" .. CEDRIC.store .. ";501;2400;" .. pages[501].h .. ";"
		.. pages[501].t .. ";z$") and a[2]:find("^B2;ep;%d+;0;") and a[3]:find("^B2;ep;%d+;240;"),
		"each gets the page's start, then its 10 parts in order")
	check(Received(me, ANNA, mark) == pages[501].z and Received(me, BOB, mark) == pages[502].z, "the parts are the stored text, as it is")
	check(most <= 3, "at most 3 of my messages wait in Beacon's queue, got " .. most)
	local fit = true
	for _, m in ipairs(a) do
		fit = fit and #m <= 255
	end
	check(fit and #a[2] == 6 + #a[2]:match("^B2;ep;(%d+;%d+;)") + 240, "a part: 240 bytes of the page, 255 in all at most")

	-- The rate: 3 a second in total, 2 to one friend.
	pages[505] = MyPage(me, 505, 9600) -- (40 parts)
	pages[506] = MyPage(me, 506, 9600)
	mark = Mark(me)
	local sentAt, last = {}, #me.env.GAMEDATA
	local function Note()
		for i = last + 1, #me.env.GAMEDATA do
			local m = me.env.GAMEDATA[i]
			if m.data:sub(1, 4) == "B2;e" then
				sentAt[#sentAt + 1] = { me.env.GetTime(), m.id }
			end
		end
		last = #me.env.GAMEDATA
	end
	Say(me, ANNA, ("B2;eq;%s;%s;505;0"):format(CEDRIC.acct, CEDRIC.store))
	Pass(me, 10, 0.05, Note)
	local function MostInASecond(id)
		local top = 0
		for i, s in ipairs(sentAt) do
			local n = 0
			for j = i, #sentAt do
				if sentAt[j][1] - s[1] < 1 - 1e-9 and (not id or sentAt[j][2] == id) then
					n = n + 1
				end
			end
			top = math.max(top, (not id or s[2] == id) and n or 0)
		end
		return top
	end
	check(#sentAt >= 14 and #sentAt <= 20 and MostInASecond(ANNA.id) <= 2,
		"one friend: never more than 2 in a second (about 16 in 10 s: the ticks), got " .. #sentAt .. ", at most "
		.. MostInASecond(ANNA.id) .. " in a second")
	sentAt = {}
	Say(me, BOB, ("B2;eq;%s;%s;506;0"):format(CEDRIC.acct, CEDRIC.store))
	Pass(me, 10, 0.05, Note)
	check(#sentAt >= 20 and #sentAt <= 30 and MostInASecond() <= 3 and MostInASecond(BOB.id) <= 2,
		"two friends: never more than 3 in a second in all, got " .. #sentAt .. " in 10 s, at most " .. MostInASecond() .. " in a second")

	-- Everything else of Beacon's goes first.
	local first = #me.env.GAMEDATA
	for i = 1, 25 do
		B.QueueLow(ANNA.id, "K2;20300515;" .. i)
	end
	B.Queue(BOB.id, "M2;hello there")
	Pass(me, 4, 0.05)
	local lastOther = 0
	for i = first + 1, #me.env.GAMEDATA do
		local m = me.env.GAMEDATA[i].data
		if m:sub(1, 3) == "K2;" or m:sub(1, 3) == "M2;" then
			lastOther = i
		end
	end
	-- (up to 3 of mine were already waiting in the queue before the others came)
	local early = 0
	for i = first + 1, lastOther do
		early = early + (me.env.GAMEDATA[i].data:sub(1, 4) == "B2;e" and 1 or 0)
	end
	check(lastOther > first and early <= 3, "26 other messages queued: they all go before any more of mine (" .. early .. " were waiting already)")

	-- In combat: nothing; after it, the pages go on from where they were.
	local before = Mark(me)
	me.env.EnterCombat()
	Pass(me, 8, 0.05)
	check(#Sent(me, ANNA, before, "B2;") == 0 and #Sent(me, BOB, before, "B2;") == 0 and D.Outstanding() == 0 and not B.LowWaiting("B2;e"),
		"in combat: nothing sent, nothing of mine left waiting in Beacon's queue")
	me.env.LeaveCombat()
	Pass(me, 30, 0.1)
	check(Received(me, ANNA, mark) == pages[505].z and Received(me, BOB, mark) == pages[506].z,
		"after the fight they go on: both pages whole, no part lost or out of place")

	-- What I don't have, and a page asked to stop.
	mark = Mark(me)
	Say(me, ANNA, ("B2;eq;%s;%s;599;0"):format(CEDRIC.acct, CEDRIC.store))
	Say(me, ANNA, ("B2;eq;%s;%s;504;0"):format(CEDRIC.acct, CEDRIC.store))
	Say(me, ANNA, ("B2;eq;%s;%s;7;0"):format(BOB.acct, BOB.store))
	Pass(me, 3)
	local en = Sent(me, ANNA, mark, "B2;en;")
	check(#en == 3 and en[1] == ("B2;en;%s;%s;599"):format(CEDRIC.acct, CEDRIC.store) and en[2]:find(";504$") and en[3]:find(";7$"),
		"\"don't have\": a page I never had, a plain-text one, another store's")
	mark = Mark(me)
	Say(me, ANNA, ("B2;eq;%s;%s;505;0"):format(CEDRIC.acct, CEDRIC.store))
	Pass(me, 2)
	Say(me, ANNA, ("B2;eq;%s;%s;505;9600"):format(CEDRIC.acct, CEDRIC.store))
	local count = #Sent(me, ANNA, mark, "B2;ep;")
	Pass(me, 5)
	check(count > 0 and #Sent(me, ANNA, mark, "B2;ep;") <= count + 3 and #D.active == 0,
		"asked from its end: the page stops (what was waiting aside), got " .. count .. " then " .. #Sent(me, ANNA, mark, "B2;ep;"))

	-- 25 requests from one friend (in a fight: nothing goes meanwhile; in two seconds: Beacon takes
	-- 20 a second from a friend): she asks one holder for one page at a time, so each replaces the one
	-- before; she can't take every place in the line.
	for n = 510, 534 do
		MyPage(me, n, 20)
	end
	mark = Mark(me)
	me.env.EnterCombat()
	for n = 510, 534 do
		Say(me, ANNA, ("B2;eq;%s;%s;%d;0"):format(CEDRIC.acct, CEDRIC.store, n))
		if n == 521 then
			Pass(me, 1.05)
		end
	end
	Pass(me, 0.3)
	local kept = D.active[1] or D.serves[1]
	check(#D.active + #D.serves == 1 and kept.n == 534, "one friend's requests: each replaces the one before, got "
		.. #D.active .. " served and " .. #D.serves .. " waiting")
	me.env.LeaveCombat()
	Pass(me, 40)
	local begun = Sent(me, ANNA, mark, "B2;eb;")
	check(#begun == 1 and begun[1]:find(";534;20;") and #D.serves == 0 and #D.active == 0, "only her last one served, got " .. #begun)
	for n = 510, 534 do
		E.data.mine[n] = nil
	end
	Touched(me)
end

section("Echoes' delivery: Beacon told to slow down")
do
	-- A throttle: Echoes is silent for 30 s while Beacon (after its own 2 s) sends as before.
	MyPage(me, 540, 24000)
	Pass(me, 1)
	local mark = Mark(me)
	Say(me, ANNA, ("B2;eq;%s;%s;540;0"):format(CEDRIC.acct, CEDRIC.store))
	Pass(me, 3)
	local before = #Sent(me, ANNA, mark, "B2;ep;")
	me.env.MOCK_SEND_RESULT = 3
	B.Queue(ANNA.id, "M2;slow down")
	Pass(me, 0.3, 0.05)
	me.env.MOCK_SEND_RESULT = nil
	local pausedUntil, backoff = D.Paused()
	check(backoff == 30 and math.abs(pausedUntil - (B.throttledAt + 30)) < 1e-6 and B.throttleResult == 3, "a throttle: 30 s of silence")
	local quiet = Mark(me)
	Pass(me, 27)
	check(#Sent(me, ANNA, quiet, "B2;") == 0 and #Sent(me, ANNA, quiet, "M2;slow down") == 1 and D.Outstanding() == 0,
		"nothing of mine for 30 s (nothing left in Beacon's queue either); Beacon's own message went after its pause")
	Pass(me, 6)
	check(#Sent(me, ANNA, quiet, "B2;ep;") > 0, "then the page goes on")
	-- Again right after: twice as long, up to 5 minutes; a lockdown counts the same.
	local seen = {}
	for i = 1, 6 do
		pausedUntil = D.Paused()
		Pass(me, math.max(0, pausedUntil - me.env.GetTime()) + 1, 0.5)
		me.env.MOCK_SEND_RESULT = i == 3 and 11 or 3
		B.Queue(ANNA.id, "M2;again")
		Pass(me, 0.3, 0.05)
		me.env.MOCK_SEND_RESULT = nil
		seen[i] = select(2, D.Paused())
	end
	check(table.concat(seen, ",") == "60,120,240,300,300,300", "each next one doubles it, up to 5 minutes, got " .. table.concat(seen, ","))
	pausedUntil = D.Paused()
	Pass(me, pausedUntil - me.env.GetTime() + 610, 0.5)
	me.env.MOCK_SEND_RESULT = 3
	B.Queue(ANNA.id, "M2;after a calm")
	Pass(me, 0.3, 0.05)
	me.env.MOCK_SEND_RESULT = nil
	check(select(2, D.Paused()) == 30, "after 10 calm minutes: 30 s again")
	Pass(me, 32)
	-- (Anna stops it: the rest of the page isn't needed here)
	Say(me, ANNA, ("B2;eq;%s;%s;540;24000"):format(CEDRIC.acct, CEDRIC.store))
	Pass(me, 3)
	E.data.mine[540] = nil
	Touched(me)
	check(before > 0 and #D.active == 0, "(the page stopped)")
end

section("Echoes' delivery: collecting (pulling, checks, resuming)")
do
	E.module.db.collect = true
	Pass(me, 1.1)
	-- Anna offers her pages 1-3; Bob (a relay) has 2-3 of them, and Eve's (not my friend).
	local mark = Mark(me)
	local p1, p2, p3 = TheirPage(me, 1, 1000), TheirPage(me, 2, 1200), TheirPage(me, 3, 1500)
	Hello(me, ANNA, "s")
	Say(me, ANNA, "B2;es;" .. ANNA.key .. ":1-3")
	Say(me, BOB, "B2;es;" .. ANNA.key .. ":2-3/" .. EVE.key .. ":1-9")
	Pass(me, 1.2)
	local toAnna, toBob = Sent(me, ANNA, mark, "B2;eq;"), Sent(me, BOB, mark, "B2;eq;")
	check(#toAnna == 1 and toAnna[1] == ("B2;eq;%s;%s;1;0"):format(ANNA.acct, ANNA.store) and #toBob == 1
		and toBob[1] == ("B2;eq;%s;%s;2;0"):format(ANNA.acct, ANNA.store),
		"one request per holder, 2 pages at once: page 1 from Anna, 2 from Bob; got " .. table.concat(toAnna, " ") .. " / " .. table.concat(toBob, " "))
	Pass(me, 5)
	check(#Sent(me, ANNA, mark, "B2;eq;") == 1 and #Sent(me, BOB, mark, "B2;eq;") == 1, "nothing more asked while those come, and nothing of Eve's (not my friend)")

	-- Page 1 comes whole: kept in the inbox with this session.
	SendPage(me, ANNA, ANNA, p1, 4)
	Pass(me, 2)
	local got = E.data.inbox[ANNA.key] and E.data.inbox[ANNA.key][1]
	check(got and got.z == p1.z and got.h == p1.h and got.t == p1.t and got.m == "z" and got.s == E.data.session,
		"page 1 is in the inbox as it was sent, with this session")
	check(#Sent(me, ANNA, mark, "B2;eq;") == 2 and Sent(me, ANNA, mark, "B2;eq;")[2]:find(";3;0$"), "then page 3 from Anna")

	-- Page 2 from Bob with a wrong hash: thrown away, and Bob isn't asked for it again.
	SendPage(me, BOB, ANNA, p2, 9, 0, nil, "00000000")
	Pass(me, 1.2)
	check(not E.data.inbox[ANNA.key][2] and D.stats.badHash == 1 and not D.inflight[ANNA.key .. ".2"], "a wrong hash: not kept")
	-- Page 3 from Anna: half of it, then she goes offline. Bob has it too: it goes on from there.
	SendPage(me, ANNA, ANNA, p3, 5, 0, 720)
	Pass(me, 0.5)
	local part = D.partials[ANNA.key .. ".3"]
	check(part and part.have == 720, "half of page 3 (in memory)")
	Online(me, ANNA, false)
	Pass(me, 2.5)
	check(not me.B.peers[ANNA.id] and not D.peers[ANNA.id], "Anna went offline: forgotten")
	local again = Sent(me, BOB, mark, "B2;eq;")
	check(again[#again] == ("B2;eq;%s;%s;3;720"):format(ANNA.acct, ANNA.store), "page 3 asked of Bob from byte 720, got " .. tostring(again[#again]))
	SendPage(me, BOB, ANNA, p3, 11, 720)
	Pass(me, 1.2)
	check(E.data.inbox[ANNA.key][3] and E.data.inbox[ANNA.key][3].z == p3.z, "page 3 whole: bytes from two holders fit together")
	-- Page 2: only Bob has it, and his copy is broken: not asked of him again.
	Pass(me, 5)
	check(#Sent(me, BOB, mark, "B2;eq;") == 2, "page 2: Bob isn't asked again (his copy is broken)")
	Online(me, ANNA, true)
	Meet(me, ANNA, NEW)
	Hello(me, ANNA, "s")
	Say(me, ANNA, "B2;es;" .. ANNA.key .. ":2")
	Pass(me, 2)
	mark = Mark(me)
	local asked = Sent(me, ANNA, 1, "B2;eq;")
	check(asked[#asked]:find(";2;0$"), "Anna back: page 2 asked of her")

	-- She goes silent for 30 s after a part: asked again from where it got to.
	local p2part = TheirPage(me, 2, 1200)
	SendPage(me, ANNA, ANNA, p2part, 6, 0, 480)
	Pass(me, 20)
	check(#Sent(me, ANNA, mark, "B2;eq;") == 0, "20 s of silence: still waiting")
	Pass(me, 12)
	local resend = Sent(me, ANNA, mark, "B2;eq;")
	check(#resend == 1 and resend[1]:find(";2;480$"), "30 s: asked again from byte 480, got " .. tostring(resend[1]))
	-- A part out of place is ignored; then the rest.
	Say(me, ANNA, ("B2;ep;6;960;%s"):format(p2part.z:sub(961, 1200)))
	Pass(me, 0.5)
	check(D.partials[ANNA.key .. ".2"].have == 480, "a part after a gap: ignored")
	SendPage(me, ANNA, ANNA, p2part, 6, 480)
	Pass(me, 1.2)
	check(E.data.inbox[ANNA.key][2] and E.data.inbox[ANNA.key][2].z == p2part.z, "the rest: page 2 whole")

	-- Checks on a page: too big (its start says so), before the launch or more than a day ahead
	-- (E.Store.Put refuses it, once whole), not a friend's account.
	mark = Mark(me)
	local p7, p8, p9 = TheirPage(me, 7, 300), TheirPage(me, 8, 300), TheirPage(me, 9, 300)
	Say(me, ANNA, "B2;es;" .. ANNA.key .. ":7")
	Pass(me, 2)
	Say(me, ANNA, ("B2;eb;3;%s;%s;7;65537;%s;%d;z"):format(ANNA.acct, ANNA.store, p7.h, p7.t))
	Pass(me, 0.5)
	check(not D.partials[ANNA.key .. ".7"], "a page over 64 KB: refused at its start")
	LT.LAUNCH_DAY = me.env.date("%Y-%m-%d", me.env.time() + 2 * 86400) -- (the day after tomorrow: the launch)
	SendPage(me, ANNA, ANNA, p7, 3)
	Pass(me, 0.5)
	check(LT.BeforeLaunch(p7.t) and not (E.data.inbox[ANNA.key] or {})[7] and D.inflight[ANNA.key .. ".7"] == nil
		and not D.partials[ANNA.key .. ".7"], "a page from before the launch: not kept")
	LT.LAUNCH_DAY = nil
	Pass(me, 6)
	check(#Sent(me, ANNA, mark, "B2;eq;") == 1, "... and not asked of her again")
	Say(me, ANNA, "B2;es;" .. ANNA.key .. ":8")
	Pass(me, 2)
	p8.t = me.env.GetServerTime() + 2 * 86400
	SendPage(me, ANNA, ANNA, p8, 3)
	Pass(me, 0.5)
	check(not (E.data.inbox[ANNA.key] or {})[8] and not D.partials[ANNA.key .. ".8"] and not D.inflight[ANNA.key .. ".8"]
		and D.stats.rejected >= 3, "a page starting more than a day ahead: not kept")
	SendPage(me, ANNA, EVE, p9, 2)
	Pass(me, 1)
	check(not E.data.inbox[EVE.key] and not D.partials[EVE.key .. ".9"], "a page of an account that isn't my friend's: not taken")

	-- Full at 8 MB (until exported): nothing asked, and no pages taken early: friends hear it once (a
	-- hello without e), and nothing more while it stays full.
	mark = Mark(me)
	local function Flags(f)
		local list = {}
		for i, m in ipairs(Sent(me, f, mark, "B2;eh;")) do
			list[i] = m:match(";(%l*)$")
		end
		return table.concat(list, " ")
	end
	check(Flags(ANNA) == "" and D.peers[ANNA.id], "(no hello to Anna yet)")
	E.data.inbox[BOB.key] = { [1] = { t = 1, h = "00000000", m = "z", z = ("A"):rep(8 * 1024 * 1024), s = E.data.session } }
	Touched(me)
	Say(me, ANNA, "B2;es;" .. ANNA.key .. ":10")
	Pass(me, 5)
	check(E.Store.InboxFull() and #Sent(me, ANNA, mark, "B2;eq;") == 0, "the inbox at 8 MB: nothing more asked")
	check(Flags(ANNA) == "crsa" and Flags(BOB) == "crsa", "friends hear it once: collecting, no e (an answer: none back), got " .. Flags(ANNA))
	Pass(me, 70)
	check(Flags(ANNA) == "crsa" and #Sent(me, ANNA, mark, "B2;eq;") == 0, "still full a minute later: no more hellos, nothing asked")
	E.data.inbox[BOB.key] = nil
	Touched(me)
	Pass(me, 5)
	check(#Sent(me, ANNA, mark, "B2;eq;") == 1, "below it again: asked")
	check(Flags(ANNA) == "crsa cersa" and Flags(BOB) == "crsa cersa", "and friends hear e again, once, got " .. Flags(ANNA))
	Say(me, ANNA, ("B2;en;%s;%s;10"):format(ANNA.acct, ANNA.store))
	Hello(me, ANNA, "s") -- (she restarts: what she offered is gone)
	Say(me, BOB, ("B2;en;%s;%s;2"):format(ANNA.acct, ANNA.store))
	Say(me, BOB, ("B2;en;%s;%s;3"):format(ANNA.acct, ANNA.store))
	for _, k in ipairs({ ANNA.key, EVE.key }) do
		E.data.inbox[k] = nil
	end
	Touched(me)
	E.module.db.collect = false
	Pass(me, 1.1)
end

section("Echoes' delivery: relaying")
do
	-- Me: a relay. Anna (the author) offers 1-6; Dora relays too, and she and Bob hold some of them.
	-- (A relay starts at a random page among those it wants: here the first, so the steps show.)
	local random = D.Random
	D.Random = function(low) return low end
	check(next(D.inflight) == nil, "(nothing asked for from before)")
	local mark = Mark(me)
	Hello(me, ANNA, "s") -- (she restarted: what she offered before is gone)
	Meet(me, DORA, NEW)
	Hello(me, DORA, "rs")
	Hello(me, BOB, "rs")
	Say(me, BOB, ("B2;ed;%s;%s;%s:1"):format(DORA.acct, DORA.store, ANNA.key)) -- (Dora collected page 1 once)
	Say(me, ANNA, "B2;es;" .. ANNA.key .. ":1-6")
	Say(me, BOB, "B2;es;" .. ANNA.key .. ":3")
	Say(me, DORA, "B2;es;" .. ANNA.key .. ":2-3")
	Pass(me, 2.2)
	-- Page 1 is safe at a collector; 3 is held by two besides Anna; 2 by one: asked for.
	local asked = Sent(me, ANNA, mark, "B2;eq;")
	check(#asked == 1 and asked[1]:find(";2;0$") and #Sent(me, BOB, mark, "B2;eq;") == 0 and #Sent(me, DORA, mark, "B2;eq;") == 0,
		"a relay asks for pages no collector holds safely, that fewer than 2 others hold: 2, got " .. tostring(asked[1]))
	SendPage(me, ANNA, ANNA, TheirPage(me, 2, 600), 1)
	Pass(me, 1.2)
	local carried = E.data.carry[ANNA.key]
	check(carried and carried[2] and carried[2].s == E.data.session and not E.data.inbox[ANNA.key], "page 2 in the relay's cache")
	asked = Sent(me, ANNA, mark, "B2;eq;")
	check(asked[2] and asked[2]:find(";4;0$"), "then 4 (3 is held by two others), got " .. tostring(asked[2]))
	-- Dora collects now and holds 4: as good as safe, it's left alone.
	Hello(me, DORA, "crsa")
	Say(me, DORA, "B2;es;" .. ANNA.key .. ":4")
	Say(me, ANNA, ("B2;en;%s;%s;4"):format(ANNA.acct, ANNA.store)) -- (Anna: "don't have" 4 after all)
	Pass(me, 2.5)
	asked = Sent(me, ANNA, mark, "B2;eq;")
	check(asked[3] and asked[3]:find(";5;0$"), "4 is held by an online collector: 5 next, got " .. tostring(asked[3]))
	-- No room: a page bigger than what's left of Anna's 128 KB in my cache (per author's store, E.Store's)
	-- is stopped at its start.
	local filler = { t = me.env.GetServerTime() - 60, h = "00000000", m = "z", z = ("A"):rep(125000), s = E.data.session }
	E.data.carry[ANNA.key][900] = filler
	Touched(me)
	Say(me, ANNA, ("B2;eb;2;%s;%s;5;9000;0badc0de;%d;z"):format(ANNA.acct, ANNA.store, me.env.GetServerTime() - 60))
	Pass(me, 2.2)
	local stop = Sent(me, ANNA, mark, "B2;eq;")
	check(stop[4] == ("B2;eq;%s;%s;5;9000"):format(ANNA.acct, ANNA.store), "too big for my cache: asked from its end (stops it), got " .. tostring(stop[4]))
	check(stop[5] and stop[5]:find(";6;0$"), "then 6 (it may be smaller), got " .. tostring(stop[5]))
	Say(me, ANNA, ("B2;en;%s;%s;6"):format(ANNA.acct, ANNA.store))
	-- Anna's 128 KB in my cache full: none of hers asked for.
	filler.z = ("A"):rep(131072)
	Touched(me)
	Say(me, ANNA, "B2;es;" .. ANNA.key .. ":11-13")
	Pass(me, 3)
	check(not E.Store.Fits(ANNA.acct, ANNA.store, 1) and #Sent(me, ANNA, mark, "B2;eq;") == 5,
		"Anna's share of the cache full: nothing more of hers asked")
	E.data.carry[ANNA.key][900] = nil
	Touched(me)
	Pass(me, 2.2)
	asked = Sent(me, ANNA, mark, "B2;eq;")
	check(asked[6] and asked[6]:find(";11;0$"), "room again: 11 (not 5: no room for it a moment ago; not 6: she hasn't it), got "
		.. tostring(asked[6]))
	for n = 11, 13 do
		Say(me, ANNA, ("B2;en;%s;%s;%d"):format(ANNA.acct, ANNA.store, n))
	end
	-- Relaying off: my cache isn't offered, nothing asked.
	E.module.db.relay = false
	mark = Mark(me)
	Say(me, ANNA, "B2;es;" .. ANNA.key .. ":14")
	Pass(me, 3)
	check(#Sent(me, ANNA, mark, "B2;eq;") == 0 and not D.Holdings()[ANNA.key], "relay off: nothing asked, my cache not offered")
	E.module.db.relay = true
	Pass(me, 1.1)
	D.Random = random
end

section("Echoes' delivery: safe at a collector")
do
	-- My pages 501-506 (from above: 501-506 still kept). Bob passes on what Dora (a collector, my
	-- friend) holds; E.Store.Safe keeps it and drops my copies.
	for n = 501, 506 do
		if not E.data.mine[n] then
			MyPage(me, n, 300)
		end
	end
	Say(me, BOB, ("B2;ed;%s;%s;%s:501-503"):format(DORA.acct, DORA.store, CEDRIC.key))
	Pass(me, 1.2)
	check(Keys(E.data.mine) == "504,505,506" and E.data.safe[CEDRIC.key][DORA.key] == "501-503",
		"safe at Dora (passed on by Bob): my copies of 501-503 go, got " .. Keys(E.data.mine))
	Say(me, BOB, ("B2;ed;%s;%s;%s:504-506"):format(EVE.acct, EVE.store, CEDRIC.key))
	Pass(me, 1.2)
	check(Keys(E.data.mine) == "504,505,506" and not (E.data.safe[CEDRIC.key][EVE.key]), "a collector who isn't my friend: not believed")
	Say(me, BOB, ("B2;ed;%s;%s;%s:505"):format(DORA.acct, DORA.store, CEDRIC.key))
	Say(me, BOB, ("B2;ed;%s;%s;%s:502"):format(DORA.acct, DORA.store, CEDRIC.key))
	Pass(me, 1.2)
	check(Keys(E.data.mine) == "504,506" and E.data.safe[CEDRIC.key][DORA.key] == "501-503,505", "summaries only grow (merged): 505 goes")
	Say(me, BOB, ("B2;ed;%s;%s;%s:1-9"):format(DORA.acct, DORA.store, EVE.key))
	Pass(me, 1.2)
	check(not E.data.safe[EVE.key], "about pages of an account that isn't my friend's: not kept")
	-- Passed on: Anna (sharing) hears what Dora holds of mine.
	local mark = Mark(me)
	Hello(me, ANNA, "s")
	Pass(me, 1.2)
	local ed = Sent(me, ANNA, mark, "B2;ed;")
	local passed = ed[1] and ed[1]:sub(1, 24) == ("B2;ed;%s;%s;"):format(DORA.acct, DORA.store)
		and ("/" .. ed[1]:sub(25) .. "/"):find("/" .. CEDRIC.key .. ":501-503,505/", 1, true)
	check(#ed == 1 and passed, "passed on to friends (with what Dora holds of Anna's), got " .. tostring(ed[1]))

	-- As a collector: pages that came in an earlier session and what the exporter has are safe.
	E.module.db.collect = true
	E.data.inbox[ANNA.key] = { [1] = { t = 1, h = "00000000", m = "z", z = "QQ==", s = E.data.session - 1 },
		[2] = { t = 1, h = "00000000", m = "z", z = "QQ==", s = E.data.session } }
	E.data.exported[ANNA.key] = "5-6"
	Touched(me)
	mark = Mark(me)
	Pass(me, 62)
	check(E.data.safe[ANNA.key][CEDRIC.key] == "1,5-6", "my own summary: 1 (on my disk), 5-6 (exported); 2 came this session")
	local mine = Sent(me, ANNA, mark, "B2;ed;" .. CEDRIC.acct)
	check(#mine == 1 and mine[1] == ("B2;ed;%s;%s;%s:1,5-6"):format(CEDRIC.acct, CEDRIC.store, ANNA.key), "told to friends, got " .. tostring(mine[1]))
	E.data.inbox[ANNA.key], E.data.exported[ANNA.key] = nil, nil
	Touched(me)
	E.module.db.collect = false
	Pass(me, 1.1)
end

section("Echoes' delivery: the probe")
do
	local ok, why = D.Probe("nobody")
	check(not ok and why:find("no friend with Echoes", 1, true), "a friend without Echoes can't be probed")
	local status = #me.env.PRINTED
	me.env.SlashCmdList.LEFTHYTOOLS("echoes")
	local said = table.concat(me.env.PRINTED, "\n", status + 1)
	check(said:find("passing pages on: 3 friend(s) with Echoes online", 1, true) and said:find("Anna Brook: ", 1, true)
		and said:find("traffic: ", 1, true), "/lefthy echoes: the delivery's lines in the status, got\n" .. said)
	local mark = Mark(me)
	local printedAt = #me.env.PRINTED
	me.env.SlashCmdList.LEFTHYTOOLS("echoes probe anna")
	check(me.env.PRINTED[printedAt + 1] and me.env.PRINTED[printedAt + 1]:find("probing", 1, true), "/lefthy echoes probe anna")
	Pass(me, 4)
	Say(me, ANNA, "B2;ey;255;255")
	Say(me, ANNA, "B2;ey;500;500")
	Pass(me, 8)
	Say(me, ANNA, "B2;ey;2000;255")
	local printed = #me.env.PRINTED
	Pass(me, 15)
	local sizes = {}
	for _, m in ipairs(Sent(me, ANNA, mark, "B2;ex;")) do
		sizes[#sizes + 1] = #m
	end
	check(table.concat(sizes, ",") == "255,500,1000,2000,4000", "five messages, 255 to 4000 bytes, got " .. table.concat(sizes, ","))
	local line = table.concat(me.env.PRINTED, "\n", printed + 1)
	check(line:find("probe to Anna Brook: 255 bytes: arrived whole; 500 bytes: arrived whole; 1000 bytes: no answer; 2000 bytes: arrived as 255 bytes; 4000 bytes: no answer.", 1, true),
		"the result in one line, got " .. line)
	-- Theirs: answered with what arrived; Beacon lets a big one through only for this.
	mark = Mark(me)
	Say(me, ANNA, "B2;ex;2000;" .. ("x"):rep(2000 - 11))
	Say(me, ANNA, "B2;ex;255;" .. ("x"):rep(255 - 10))
	Say(me, FINN, "B2;ex;500;" .. ("x"):rep(500 - 10))
	Pass(me, 2)
	local answers = Sent(me, ANNA, mark, "B2;ey;")
	check(#answers == 2 and answers[1] == "B2;ey;2000;2000" and answers[2] == "B2;ey;255;255" and #Sent(me, FINN, mark, "B2;") == 0,
		"a friend's probe is answered (not Finn's: no Echoes), got " .. table.concat(answers, " "))
end

section("Echoes' delivery: switching off")
do
	local mark = Mark(me)
	LT:SetModuleEnabled("echoes", false)
	Pass(me, 2)
	local off = Sent(me, ANNA, mark, "B2;")
	check(#off == 1 and off[1] == ("B2;eh;%s;%s;1;255;a"):format(CEDRIC.acct, CEDRIC.store) and #Sent(me, BOB, mark, "B2;eh;") == 1
		and #Sent(me, FINN, mark, "B2;") == 0, "Echoes off: friends hear I'm out (no flags); nothing else, got " .. tostring(off[1]))
	Say(me, ANNA, ("B2;eq;%s;%s;506;0"):format(CEDRIC.acct, CEDRIC.store))
	Pass(me, 3)
	check(#Sent(me, ANNA, mark, "B2;") == 1 and not next(D.peers), "while off: nothing heard, nothing sent")
	LT:SetModuleEnabled("echoes", true)
	Pass(me, 2)
	check(#Sent(me, ANNA, mark, "B2;eh;") == 2 and Sent(me, ANNA, mark, "B2;eh;")[2]:sub(-3) == ";rs", "on again: my hello to friends known")
	Hello(me, ANNA, "sa")
	check(D.peers[ANNA.id] and D.peers[ANNA.id].verified, "... and theirs")
	-- Switched off in a fight: nothing of Echoes' goes in one, my "I'm out" too waits for its end.
	local out = ("B2;eh;%s;%s;1;255;a"):format(CEDRIC.acct, CEDRIC.store)
	mark = Mark(me)
	me.env.EnterCombat()
	LT:SetModuleEnabled("echoes", false)
	Pass(me, 3)
	check(#Sent(me, ANNA, mark, "B2;") == 0, "switched off in a fight: my hello that I'm out waits")
	me.env.LeaveCombat()
	Pass(me, 2)
	local said = Sent(me, ANNA, mark, "B2;")
	check(#said == 1 and said[1] == out, "the fight over: Anna hears I'm out, got " .. tostring(said[1]))
	-- Off and on again in a fight: she never hears I was out, only that I'm back.
	LT:SetModuleEnabled("echoes", true)
	Pass(me, 2)
	Hello(me, ANNA, "sa")
	mark = Mark(me)
	me.env.EnterCombat()
	LT:SetModuleEnabled("echoes", false)
	Pass(me, 1)
	LT:SetModuleEnabled("echoes", true)
	Pass(me, 1)
	me.env.LeaveCombat()
	Pass(me, 3)
	said = Sent(me, ANNA, mark, "B2;eh;")
	check(#said == 1 and said[1]:sub(-3) == ";rs", "off and on again in a fight: only my hello that I'm back, got " .. table.concat(said, " "))
	Hello(me, ANNA, "sa")
	LT:SetModuleEnabled("beacon", false)
	check(not next(D.peers) and #D.active == 0, "Beacon off: Echoes forgets everyone too")
	LT:SetModuleEnabled("beacon", true)
	Pass(me, 1)
	Stop(me)
end

-- (The sections below start a client of their own, so the ones above keep their timing.)

section("Echoes' delivery: the first build with Delivery")
do
	-- 0.6.0-24 (0702157) reads B2 but has no Delivery; 0.6.0-25 (41f011b) is the first with it (a
	-- "-dirty" install of it too).
	local c = Start(DORA, { friends = { GWEN }, fake = true })
	local mark = Mark(c)
	Meet(c, GWEN, "0.6.0-24-g0702157")
	Pass(c, 65)
	Say(c, GWEN, "H2")
	Pass(c, 65)
	check(#Sent(c, GWEN, mark, "V2;") >= 1 and #Sent(c, GWEN, mark, "B2;") == 0, "0.6.0-24 (B2, no Delivery yet): never a B message")
	Say(c, GWEN, "V2;0.6.0-25-g41f011b-dirty")
	Say(c, GWEN, "H2")
	Pass(c, 6)
	local sent = Sent(c, GWEN, mark, "B2;")
	check(#sent == 1 and sent[1]:find("^B2;eh;"), "0.6.0-25 (the first build with Delivery): my hello, got " .. tostring(sent[1]))
	Stop(c)
end

-- n friends with Echoes, played by the test (ids from first + 1 on).
local function Crowd(n, first)
	local list = {}
	for i = 1, n do
		local id = (first or 100) + i
		local p = Person(id, ("Pal%02d Stone"):format(i), "MAGE", ("Pal%02d#%d"):format(i, 1000 + id), ("%08x"):format(0x10000000 + id))
		p.key = p.acct .. "." .. p.store
		list[i] = p
	end
	return list
end

-- c meets friends with Echoes: flags for each (relay and sharing unless said).
local function MeetAll(c, friends, flags)
	for _, f in ipairs(friends) do
		Meet(c, f, NEW)
		Hello(c, f, flags or "rs")
	end
end

-- f asks c for c's own page n from offset.
local function Ask(c, f, n, offset)
	Say(c, f, ("B2;eq;%s;%s;%d;%d"):format(c.who.acct, c.E.data.store, n, offset or 0))
end

-- The friends c began a page for since mark (eb), in order.
local function Begun(c, mark)
	local list = {}
	for i = mark, #c.env.GAMEDATA do
		local m = c.env.GAMEDATA[i]
		if m.data:sub(1, 6) == "B2;eb;" then
			list[#list + 1] = m.id
		end
	end
	return list
end

section("Echoes' delivery: a holder's line (one place per friend, kept when asked again)")
do
	local crowd = Crowd(24)
	local c = Start(EVE, { friends = crowd, fake = true })
	local D = c.D
	for i = 1, 30 do
		MyPage(c, 600 + i, 480) -- (2 parts each)
	end
	MeetAll(c, crowd)
	-- In a fight (nothing goes), each asks for a page: 2 served at once, 20 waiting, the rest dropped
	-- (they ask again).
	local mark = Mark(c)
	c.env.EnterCombat()
	for i, f in ipairs(crowd) do
		Ask(c, f, 600 + i)
	end
	Pass(c, 0.3)
	check(#D.active == 2 and #D.serves == 20, "2 served at once and 20 waiting, got " .. #D.active .. " and " .. #D.serves)
	-- Pal03 (first in line) asks again for the same page, as after 30 s without progress: it keeps
	-- its place. Pal04 asks for another page: it takes the place of the one before, not a second one.
	Ask(c, crowd[3], 603)
	Ask(c, crowd[4], 630)
	Pass(c, 0.3)
	check(D.serves[1].id == crowd[3].id and D.serves[2].id == crowd[4].id and D.serves[2].n == 630 and #D.serves == 20,
		"asked again: in its place; another page: instead of the one before, got " .. tostring(D.serves[1].id) .. ", "
		.. tostring(D.serves[2].id) .. " (page " .. tostring(D.serves[2].n) .. "), " .. #D.serves .. " waiting")
	c.env.LeaveCombat()
	Pass(c, 90)
	local order, at = Begun(c, mark), {}
	for i, id in ipairs(order) do
		at[id] = at[id] or i
	end
	local inOrder = true
	for i = 3, 22 do -- (two go at once: a neighbour may begin a moment before)
		inOrder = inOrder and at[crowd[i].id] ~= nil and math.abs(at[crowd[i].id] - i) <= 1
	end
	check(#order == 22 and inOrder, "served in the order they first asked, got " .. #order .. " pages begun, Pal03 as "
		.. tostring(at[crowd[3].id]))
	local fourth = Sent(c, crowd[4], mark, "B2;eb;")
	check(#fourth == 1 and fourth[1]:find(";630;480;"), "Pal04: only the page asked last, got " .. table.concat(fourth, " "))

	-- A friend restarts (an eh without a) while I serve them a page: what they asked before is gone
	-- with their session, so it stops (they ask again for what they still need).
	MyPage(c, 640, 9600) -- (40 parts)
	Pass(c, 65) -- (the summaries of it go first)
	Ask(c, crowd[1], 640)
	Pass(c, 4)
	mark = Mark(c)
	local before = #Sent(c, crowd[1], 1, "B2;ep;")
	Hello(c, crowd[1], "rs")
	Pass(c, 20)
	local after = #Sent(c, crowd[1], 1, "B2;ep;")
	check(before > 0 and before < 40 and after - before <= 3 and #D.active == 0,
		"a friend who restarted isn't served what they asked before (" .. before .. " parts, then " .. after - before .. ")")

	-- Collectors first: pages go to the collector, a relay only carries them for a while. The line
	-- full of relays' requests, Pal24 (collecting now) asks: the last relay's place is hers, and she
	-- is served next.
	Hello(c, crowd[24], "crsa")
	Pass(c, 5)
	mark = Mark(c)
	c.env.EnterCombat()
	for i = 1, 23 do
		Ask(c, crowd[i], 600 + i)
	end
	Pass(c, 0.3)
	Ask(c, crowd[24], 624)
	Pass(c, 0.3)
	local waiting = {}
	for _, s in ipairs(D.serves) do
		waiting[s.id] = true
	end
	check(#D.serves == 20 and waiting[crowd[24].id] and not waiting[crowd[22].id], "the line full: a collector's request takes a relay's place")
	c.env.LeaveCombat()
	Pass(c, 20)
	order = Begun(c, mark)
	check(order[3] == crowd[24].id or order[4] == crowd[24].id, "... and is served next (the two served then go on together), got "
		.. table.concat(order, ","))
	Stop(c)
end

section("Echoes' delivery: a page's start I don't take")
do
	local c = Start(DORA, { friends = { ANNA, BOB }, fake = true, collect = true })
	local D = c.D
	Meet(c, ANNA, NEW)
	Hello(c, ANNA, "s")
	local mark = Mark(c)
	Say(c, ANNA, "B2;es;" .. ANNA.key .. ":1")
	Pass(c, 1.5)
	check(#Sent(c, ANNA, mark, "B2;eq;") == 1, "(page 1 asked of Anna)")
	-- She begins page 1 as transfer 5, then (a request of mine from before, say) page 9 with the same
	-- transfer id: page 9's parts don't go into page 1, and she's asked to stop page 9.
	local p1, p9 = TheirPage(c, 1, 1000), TheirPage(c, 9, 1000, 99)
	Say(c, ANNA, ("B2;eb;5;%s;%s;1;%d;%s;%d;z"):format(ANNA.acct, ANNA.store, p1.len, p1.h, p1.t))
	Pass(c, 0.5)
	Say(c, ANNA, ("B2;eb;5;%s;%s;9;%d;%s;%d;z"):format(ANNA.acct, ANNA.store, p9.len, p9.h, p9.t))
	Say(c, ANNA, ("B2;ep;5;0;%s"):format(p9.z:sub(1, 240)))
	Pass(c, 1)
	local part = D.partials[ANNA.key .. ".1"]
	check(part and part.have == 0, "a transfer id is the page its last start said: page 9's part isn't page 1's, got "
		.. tostring(part and part.have))
	local stops = Sent(c, ANNA, mark, ("B2;eq;%s;%s;9;"):format(ANNA.acct, ANNA.store))
	check(#stops == 1 and stops[1]:find(";9;1000$"), "a page I didn't ask for: she's asked to stop it (from its end), got " .. tostring(stops[1]))
	-- One I have already: stopped too.
	SendPage(c, ANNA, ANNA, p1, 6)
	Pass(c, 1)
	check(c.E.data.inbox[ANNA.key] and c.E.data.inbox[ANNA.key][1], "(page 1 whole, from transfer 5 again)")
	mark = Mark(c)
	Say(c, ANNA, ("B2;eb;7;%s;%s;1;%d;%s;%d;z"):format(ANNA.acct, ANNA.store, p1.len, p1.h, p1.t))
	Pass(c, 1)
	check(#Sent(c, ANNA, mark, ("B2;eq;%s;%s;1;1000"):format(ANNA.acct, ANNA.store)) == 1, "a page I have: stopped too")
	Stop(c)
end

section("Echoes' delivery: what a relay asks for, however much others hold")
do
	local crowd = Crowd(20, 200)
	local friends = { ANNA, BOB, CEDRIC }
	for _, f in ipairs(crowd) do
		friends[#friends + 1] = f
	end
	local c = Start(DORA, { friends = friends, fake = true })
	Meet(c, ANNA, NEW)
	Hello(c, ANNA, "s")
	MeetAll(c, { BOB, CEDRIC })
	-- Anna has 1-200; Bob and Cedric hold 1-60 already: past the first 50 pages, one of 61-200 is
	-- the one (a relay starts at a random one of the pages it wants).
	local mark = Mark(c)
	Say(c, BOB, "B2;es;" .. ANNA.key .. ":1-60")
	Say(c, CEDRIC, "B2;es;" .. ANNA.key .. ":1-60")
	Say(c, ANNA, "B2;es;" .. ANNA.key .. ":1-200")
	Pass(c, 1.5)
	local asked = Sent(c, ANNA, mark, "B2;eq;")
	local first = asked[1] and tonumber(asked[1]:match(";(%d+);0$"))
	check(#asked == 1 and first and first >= 61 and first <= 200, "pages 1-60 held by two others: one of 61-200 asked for, got " .. tostring(asked[1]))
	-- 20 more relays hold 1-299 of hers, and of each other's own pages; one copy of 300 is around:
	-- 300 is the page, and finding it is quick (ranges, not page by page). (Anna restarts first: what
	-- she offered and what I asked of her go.)
	MeetAll(c, crowd)
	Hello(c, ANNA, "s")
	mark = Mark(c)
	for i, f in ipairs(crowd) do
		local items = { ANNA.key .. ":1-" .. (i == 1 and 300 or 299) }
		for _, g in ipairs(crowd) do
			if g ~= f then
				items[#items + 1] = g.key .. ":1-500"
			end
		end
		for first = 1, #items, 9 do
			Say(c, f, "B2;es;" .. table.concat(items, "/", first, math.min(first + 8, #items)))
		end
	end
	Say(c, ANNA, "B2;es;" .. ANNA.key .. ":1-300")
	local clock = os.clock()
	Pass(c, 1.5)
	local took = os.clock() - clock
	asked = {}
	for i = mark, #c.env.GAMEDATA do
		local m = c.env.GAMEDATA[i]
		if m.data:sub(1, 6) == "B2;eq;" then
			asked[#asked + 1] = m.data
		end
	end
	check(#asked == 1 and asked[1]:find(";300;0$"), "everything else held by two others: 300 asked for (of Anna or Pal01), got "
		.. table.concat(asked, " "))
	-- (In the test's Lua, page by page took 2.7 s for these 15 ticks, ranges 0.08 s.)
	check(took < 0.5, ("... quickly: 15 ticks with 23 friends offering 21 stores each, %.2f s in the test's Lua"):format(took))
	Stop(c)
end

section("Echoes' delivery: a collector's relay cache moves to the inbox")
do
	-- Dora relayed pages of Anna's, then switched collecting on: they move over, one a second, also
	-- when nobody offers them; one the exporter has already just goes.
	local c = Start(DORA, { friends = { ANNA }, fake = true })
	local carry, texts = {}, {}
	for n = 1, 4 do
		local p = TheirPage(c, n, 800)
		carry[n], texts[n] = { t = p.t, h = p.h, m = "z", z = p.z, s = c.E.data.session, a = c.env.GetServerTime() - 60 }, p.z
	end
	c.E.data.carry[ANNA.key] = carry
	c.E.data.exported[ANNA.key] = "4"
	Touched(c)
	c.E.module.db.collect = true
	Pass(c, 1.1)
	local moved = 0
	for _ in pairs(c.E.data.inbox[ANNA.key] or {}) do
		moved = moved + 1
	end
	check(moved <= 1, "one a second (each is hashed again), got " .. moved)
	Pass(c, 5)
	local inbox = c.E.data.inbox[ANNA.key] or {}
	check(Keys(inbox) == "" and inbox[1] and inbox[2] and inbox[3] and not inbox[4] and next(c.E.data.carry) == nil
		and inbox[1].z == texts[1] and inbox[1].s == c.E.data.session, "pages 1-3 in the inbox (this session's), 4 (exported) gone, the cache empty")
	Stop(c)
end

section("Echoes' delivery: holders that go silent are asked last")
do
	-- Anna and Bob offer pages but don't answer (a long fight, silent after a throttle); Dora does.
	-- Both of my requests went to them; after 30 s the next ones go to Dora first.
	local c = Start(EVE, { friends = { ANNA, BOB, DORA }, fake = true, collect = true })
	MeetAll(c, { ANNA, BOB, DORA })
	local mark = Mark(c)
	for _, f in ipairs({ ANNA, BOB, DORA }) do
		Say(c, f, "B2;es;" .. ANNA.key .. ":1-10")
	end
	Pass(c, 2) -- (one a tick)
	check(#Sent(c, ANNA, mark, "B2;eq;") == 1 and #Sent(c, BOB, mark, "B2;eq;") == 1 and #Sent(c, DORA, mark, "B2;eq;") == 0,
		"(two requests: to Anna and Bob)")
	Pass(c, 33.5) -- (30 s from when they went)
	local toDora = Sent(c, DORA, mark, "B2;eq;")
	check(#toDora == 1 and toDora[1]:find(";1;0$"), "silent for 30 s: Dora is asked first now, got " .. tostring(toDora[1]))
	local p1 = TheirPage(c, 1, 600)
	SendPage(c, DORA, ANNA, p1, 3)
	Pass(c, 2)
	check(c.E.data.inbox[ANNA.key] and c.E.data.inbox[ANNA.key][1] and #Sent(c, DORA, mark, "B2;eq;") == 2,
		"page 1 from Dora, and the next asked of her too")
	Stop(c)
end

section("Echoes' delivery: a friend asking again and again")
do
	-- Anna (broken, or hostile) asks for 120 pages I don't have, 20 a second, in a fight (nothing goes):
	-- my answers to her wait, but at most 8 of them (she asks again).
	local c = Start(EVE, { friends = { ANNA }, fake = true })
	MeetAll(c, { ANNA })
	Pass(c, 3)
	c.env.EnterCombat()
	for second = 1, 6 do
		for i = 1, 20 do
			Ask(c, ANNA, second * 100 + i)
		end
		Pass(c, 1.05)
	end
	local waiting = 0
	for _, item in ipairs(c.D.out) do
		waiting = waiting + (item.id == ANNA.id and 1 or 0)
	end
	check(waiting <= 8, "answers waiting for one friend: at most 8, got " .. waiting)
	local mark = Mark(c)
	c.env.LeaveCombat()
	Pass(c, 10)
	local en = #Sent(c, ANNA, mark, "B2;en;")
	check(en >= 1 and en <= 8 and #c.D.out == 0, "after the fight: those go, nothing else piled up, got " .. en)
	Stop(c)
end

-- When each message c sends goes out (GetTime() on its GAMEDATA entry, as .at).
local function Stamped(c)
	local bn = c.env.C_BattleNet
	local send = bn.SendGameData
	bn.SendGameData = function(...)
		local n = #c.env.GAMEDATA
		local result = send(...)
		if #c.env.GAMEDATA > n then
			c.env.GAMEDATA[#c.env.GAMEDATA].at = c.env.GetTime()
		end
		return result
	end
end

-- The most of c's messages since mark starting with prefix that went within window seconds of each
-- other (to one friend: same), and how many went in all (Stamped).
local function Burst(c, mark, prefix, window, same)
	local list = {}
	for i = mark, #c.env.GAMEDATA do
		local m = c.env.GAMEDATA[i]
		if m.at and m.data:sub(1, #prefix) == prefix then
			list[#list + 1] = m
		end
	end
	local most = 0
	for i, m in ipairs(list) do
		local n = 0
		for j = i, #list do
			if list[j].at - m.at > window - 1e-6 then
				break
			end
			n = n + ((not same or list[j].id == m.id) and 1 or 0)
		end
		most = math.max(most, n)
	end
	return most, #list
end

section("Echoes' delivery: spread out, little work a tick")
do
	-- Six friends ask for a page each: Echoes hands Beacon one message a tick at most, so they don't
	-- go out in the same moment (three in one of Beacon's ticks, before).
	local crowd = Crowd(6, 300)
	local c = Start(EVE, { friends = crowd, fake = true })
	Stamped(c)
	for i = 1, 6 do
		MyPage(c, 600 + i, 4800)
	end
	MeetAll(c, crowd, "crs")
	local mark = Mark(c)
	for i = 1, 6 do
		Ask(c, crowd[i], 600 + i)
	end
	Pass(c, 30)
	local together, total = Burst(c, mark, "B2;e", 0.1)
	local inASecond = Burst(c, mark, "B2;e", 1)
	check(together == 1 and inASecond <= 3 and total >= 60, ("one at a time: at most 1 within 0.1 s (and 3 in a second), got %d (%d) of %d")
		:format(together, inASecond, total))
	Stop(c)

	-- 30 friends with Echoes, 8 answers waiting for each (asked in a fight): while the rate is used up,
	-- a tick looks at nobody; else each friend once, not every message waiting.
	crowd = Crowd(30, 330)
	c = Start(EVE, { friends = crowd, fake = true })
	MeetAll(c, crowd)
	Pass(c, 5)
	c.env.EnterCombat()
	for _, f in ipairs(crowd) do
		for n = 1, 8 do
			Ask(c, f, 900 + n)
		end
		Pass(c, 0.5)
	end
	local waiting = #c.D.out
	local peers, looked = c.B.peers, 0
	c.B.peers = setmetatable({}, {
		__index = function(_, id)
			looked = looked + 1
			return peers[id]
		end,
		__pairs = function()
			return next, peers, nil
		end,
	})
	c.env.LeaveCombat()
	Pass(c, 10)
	c.B.peers = peers
	check(waiting >= 200 and looked < 1200, ("%d answers waiting: friends looked up %d times in 10 s (once a message, every tick: 9000)"):format(waiting, looked))
	Stop(c)
end

section("Echoes' delivery: summaries worked out once a change, not every second")
do
	-- 30 friends who relay; what's safe of 10 stores at one of them. Nothing changes for a minute: no
	-- summary is worked out (each friend's, every second, before). A page of mine closes: each friend
	-- hears of it once, the ranges written once for all of them.
	local crowd = Crowd(30, 400)
	local c = Start(EVE, { friends = crowd, fake = true })
	MyPage(c, 701, 300)
	for i = 1, 10 do
		c.E.data.safe[crowd[i].key] = { [crowd[30].key] = "1-" .. (10 + i) }
	end
	Touched(c)
	MeetAll(c, crowd)
	Pass(c, 70)
	local format, formatted = c.D.Ranges.Format, 0
	c.D.Ranges.Format = function(list)
		formatted = formatted + 1
		return format(list)
	end
	local mark = Mark(c)
	Pass(c, 60)
	local quiet = formatted
	check(quiet == 0 and #Sent(c, crowd[1], mark, "B2;e") == 0, "a minute without a change: nothing worked out, nothing sent, got "
		.. quiet .. " lists written")
	MyPage(c, 702, 300)
	formatted = 0
	Pass(c, 60)
	local heard = 0
	for _, f in ipairs(crowd) do
		local es = Sent(c, f, mark, "B2;es;")
		heard = heard + ((#es == 1 and es[1] == "B2;es;" .. c.E.Store.Own() .. ":701-702") and 1 or 0)
	end
	c.D.Ranges.Format = format
	check(heard == 30 and formatted <= 15, ("a page closed: all 30 friends hear of it once (%d), the lists written once for all (%d times)")
		:format(heard, formatted))
	Stop(c)
end

-- What's safe of 2 stores of each friend's, at collectors (the first few friends), each with
-- intervals ranges: a big safe table, as after many sessions.
local function SafeOfAll(c, crowd, collectors, intervals)
	for i, f in ipairs(crowd) do
		for s = 1, 2 do
			local entry = {}
			for k = 1, collectors do
				local parts = {}
				for r = 1, intervals do
					parts[r] = (r * 10) .. "-" .. (r * 10 + 5)
				end
				entry[crowd[k].key] = table.concat(parts, ",")
			end
			c.E.data.safe[f.acct .. "." .. ("%08x"):format(0x20000000 + i * 16 + s)] = entry
		end
	end
	Touched(c)
end

section("Echoes' delivery: summaries don't pile up, pages aren't held up by them")
do
	-- 30 friends, a big safe table (what a collector holds of 60 stores, a dozen messages to each
	-- friend): out stays bounded (before, summaries were queued again every 5 minutes while the last
	-- ones still waited: it grew without end), and a page asked for goes while they wait (it waited
	-- behind all of them, before). What's safe goes in full every 30 minutes (it only grows, and
	-- friends keep it), not every 5.
	local crowd = Crowd(30, 500)
	local c = Start(EVE, { friends = crowd, fake = true })
	MyPage(c, 701, 9600) -- (40 parts)
	SafeOfAll(c, crowd, 1, 10)
	local mark, most = Mark(c), 0
	MeetAll(c, crowd)
	Pass(c, 120, 0.25, function()
		most = math.max(most, #c.D.out)
	end)
	Ask(c, crowd[5], 701)
	local asked = c.env.GetTime()
	local done
	Pass(c, 480, 0.25, function()
		most = math.max(most, #c.D.out)
		if not done and #Sent(c, crowd[5], mark, "B2;ep;") >= 40 then
			done = c.env.GetTime() - asked
		end
	end)
	local told, twice = {}, 0
	for _, m in ipairs(Sent(c, crowd[3], mark, "B2;ed;")) do
		twice = twice + (told[m] and 1 or 0)
		told[m] = true
	end
	check(most <= 300 and done and done < 90, ("out at most %d (200, and a friend's summaries past it); the page went in %s s")
		:format(most, tostring(done and math.floor(done))))
	check(next(told) and twice == 0, ("what's safe: told in full once in 11 minutes, got %d messages again"):format(twice))

	-- My settings change in a fight (summaries for everyone wait), friends ask for pages I don't have:
	-- a summary waiting makes room for each answer (it comes again), and past 200 an answer doesn't wait.
	c.env.EnterCombat()
	c.E.module.db.relay = false
	Pass(c, 15)
	local before = 0
	for _, item in ipairs(c.D.out) do
		before = before + ((item.kind == "es" or item.kind == "ed") and 1 or 0)
	end
	for _, f in ipairs(crowd) do
		for n = 1, 8 do
			Ask(c, f, 900 + n)
		end
		Pass(c, 0.3)
	end
	local summaries, answers = 0, 0
	for _, item in ipairs(c.D.out) do
		summaries = summaries + ((item.kind == "es" or item.kind == "ed") and 1 or 0)
		answers = answers + (item.kind == "en" and 1 or 0)
	end
	check(before > 0 and summaries == 0 and answers == before and #c.D.out <= 230, ("out full: the %d summaries made room for "
		.. "as many answers (%d), no more waited (%d in all, with my 30 hellos), got %d summaries left"):format(before, answers, #c.D.out, summaries))
	c.env.LeaveCombat()
	Pass(c, 5)
	Stop(c)
end

section("Echoes' delivery: everyone's summaries spread over the seconds")
do
	-- My settings change with 30 friends: everyone hears my hello at once, but their summaries are
	-- made 3 friends a second (all 30 in one tick, before); the 5-minute full offers come at times of
	-- each friend's own (all in the same second, before).
	local crowd = Crowd(30, 550)
	local c = Start(EVE, { friends = crowd, fake = true })
	local k = 0
	c.D.Random = function(low, high) -- (spread, the same each run)
		k = k + 7
		return low + k % (high - low + 1)
	end
	Stamped(c)
	MyPage(c, 701, 300)
	SafeOfAll(c, crowd, 1, 1)
	MeetAll(c, crowd)
	Pass(c, 400)
	local mark = Mark(c)
	Pass(c, 300)
	local first, last = math.huge, 0
	for _, f in ipairs(crowd) do
		for i = mark, #c.env.GAMEDATA do
			local m = c.env.GAMEDATA[i]
			if m.id == f.id and m.data:sub(1, 6) == "B2;es;" then
				first, last = math.min(first, m.at), math.max(last, m.at)
			end
		end
	end
	check(last - first >= 40, ("the full offers of 5 minutes later: over %.0f s"):format(last - first))
	-- (the friends with summaries waiting in out, and how many)
	local function Waiting()
		local ids, n = {}, 0
		for _, item in ipairs(c.D.out) do
			if (item.kind == "es" or item.kind == "ed") and not ids[item.id] then
				ids[item.id], n = true, n + 1
			end
		end
		return ids, n
	end
	local most, heard, before = 0, {}, Waiting()
	c.E.module.db.relay = false
	Pass(c, 30, 0.25, function()
		local now, new = Waiting(), 0
		for id in pairs(now) do
			new = new + (before[id] and 0 or 1)
			heard[id] = true
		end
		most, before = math.max(most, new), now
	end)
	local all = 0
	for _ in pairs(heard) do
		all = all + 1
	end
	check(most <= 3 and all == 30, ("settings changed: 3 friends' summaries a second at most, got %d friends' in one tick (%d in all)")
		:format(most, all))
	Stop(c)
end

section("Echoes' delivery: long range lists of my own")
do
	-- What I keep (exported, safe, my inbox) may have more than the 300 intervals a message may: read
	-- in full, not as "none". A collector: the exporter has Anna's odd pages 1-701 (351 intervals),
	-- her even pages 702-1300 are in the inbox (300 more).
	local odd, even = {}, {}
	for n = 1, 701, 2 do
		odd[#odd + 1] = tostring(n)
	end
	local c = Start(EVE, { friends = { ANNA, BOB }, fake = true, collect = true })
	local inbox = {}
	for n = 702, 1300, 2 do
		local p = TheirPage(c, n % 600 + 1, 40)
		inbox[n] = { t = p.t, h = p.h, m = "z", z = p.z, s = c.E.data.session - 1 }
		even[#even + 1] = tostring(n)
	end
	c.E.data.exported[ANNA.key] = table.concat(odd, ",")
	c.E.data.inbox[ANNA.key] = inbox
	Touched(c)
	MeetAll(c, { ANNA })
	local D = c.D
	Say(c, ANNA, "B2;es;" .. ANNA.key .. ":1-3")
	Pass(c, 1.5)
	check(D.inflight[ANNA.key .. ".2"] and not D.inflight[ANNA.key .. ".1"], "351 intervals exported: page 1 isn't asked for, 2 is")
	Say(c, ANNA, ("B2;en;%s;%s;2"):format(ANNA.acct, ANNA.store))
	Say(c, ANNA, "B2;es;" .. ANNA.key .. ":702")
	Pass(c, 1.5)
	check(next(D.inflight) == nil, "a page in an inbox of 300 intervals: not asked for again")
	check(c.E.data.safe[ANNA.key] and c.E.data.safe[ANNA.key][c.E.Store.Own()]
		and c.E.Ranges.Contains(c.E.data.safe[ANNA.key][c.E.Store.Own()], 701)
		and c.E.Ranges.Contains(c.E.data.safe[ANNA.key][c.E.Store.Own()], 1300), "my own summary has all of it (on disk, exported)")
	Stop(c)
end

section("Echoes' delivery: pages changed behind its back")
do
	-- E.Store tells Delivery when pages change (D.PagesChanged); a page put in without it is offered
	-- anyway within the safety net's 5 minutes (and not worked out anew every 30 s any more).
	local c = Start(EVE, { friends = { BOB }, fake = true })
	MeetAll(c, { BOB })
	MyPage(c, 701, 300)
	Pass(c, 70)
	local mark = Mark(c)
	local z = Data(300, 1)
	c.E.data.mine[702] = { t = c.env.GetServerTime() - 60, h = Hash32(z), m = "z", z = z }
	Pass(c, 120)
	local quiet = #Sent(c, BOB, mark, "B2;es;")
	Pass(c, 250)
	local offers = Sent(c, BOB, mark, "B2;es;")
	check(quiet == 0 and #offers >= 1 and offers[#offers]:find(":701%-702$"), "offered within 5 minutes, got "
		.. quiet .. " then " .. tostring(offers[#offers]))
	Stop(c)
end

section("Echoes' delivery: safe summaries from friends are bounded")
do
	-- Bob (broken, or hostile) says Dora holds every other page of Anna's, 40 at a time, 800 in all:
	-- at most 300 intervals are kept (a longer list isn't parsed on every message, nor saved).
	local c = Start(EVE, { friends = { ANNA, BOB, DORA }, fake = true })
	MeetAll(c, { BOB })
	local n = 1001
	for message = 1, 20 do
		local list = {}
		for i = 1, 40 do
			list[i] = tostring(n)
			n = n + 2
		end
		Say(c, BOB, ("B2;ed;%s;%s;%s:%s"):format(DORA.acct, DORA.store, ANNA.key, table.concat(list, ",")))
		if message % 10 == 0 then
			Pass(c, 1.05)
		end
	end
	Pass(c, 3)
	local kept = c.E.data.safe[ANNA.key] and c.E.data.safe[ANNA.key][DORA.key]
	local count = kept and #c.E.Ranges.Parse(kept) or 0
	check(count >= 280 and count <= 300, "at most 300 intervals kept for one collector, got " .. count)
	Stop(c)
end

section("Echoes' delivery: a store's safe entry is kept by what's heard of it first-hand")
do
	-- Summaries are passed on by every friend, so they'd keep every entry forever: only what's heard
	-- first-hand keeps one (E.Store drops it 60 days after): the collector's own summary, or a friend
	-- offering pages of that store.
	local c = Start(EVE, { friends = { ANNA, BOB, DORA }, fake = true })
	MeetAll(c, { BOB, DORA })
	local function Heard()
		return c.E.data.heard and c.E.data.heard[ANNA.key]
	end
	local t0 = c.env.GetServerTime()
	Say(c, BOB, ("B2;ed;%s;%s;%s:1-3"):format(DORA.acct, DORA.store, ANNA.key))
	Pass(c, 1.2)
	check(c.E.data.safe[ANNA.key] and Heard() and Heard() >= t0, "a new entry (passed on by Bob): heard of now")
	c.E.data.heard[ANNA.key] = 1000
	Say(c, BOB, ("B2;ed;%s;%s;%s:1-5"):format(DORA.acct, DORA.store, ANNA.key))
	Pass(c, 1.2)
	check(Heard() == 1000 and c.E.data.safe[ANNA.key][DORA.key] == "1-5", "passed on by Bob again: merged, not heard of first-hand")
	Say(c, DORA, ("B2;ed;%s;%s;%s:1-5"):format(DORA.acct, DORA.store, ANNA.key))
	Pass(c, 1.2)
	check(Heard() >= t0, "Dora's own summary: heard of")
	c.E.data.heard[ANNA.key] = 1000
	Say(c, BOB, "B2;es;" .. ANNA.key .. ":7")
	Pass(c, 1.2)
	check(Heard() >= t0, "Bob offers a page of it: heard of")
	Stop(c)
end

section("Echoes' delivery: a friend Battle.net lists late")
do
	-- Bob relays Anna's pages; she isn't on my friend list yet (just added, or Battle.net slow to list
	-- her). Her pages are taken as soon as the list has her: read again when an account isn't in it
	-- (at most every 5 s), and after Battle.net's events; not only every 30 s.
	local c = Start(DORA, { friends = { BOB }, fake = true })
	MeetAll(c, { BOB })
	local function Offered()
		local peer = c.D.peers[BOB.id]
		return peer and peer.holdings[ANNA.key] and c.D.Ranges.Format(peer.holdings[ANNA.key]) or ""
	end
	Pass(c, 6)
	Say(c, BOB, "B2;es;" .. ANNA.key .. ":1-3")
	Pass(c, 1.2)
	check(Offered() == "", "Anna isn't my friend: what Bob holds of hers isn't taken")
	-- Battle.net lists her now, and says so: Bob's next summary (5 s later) is taken.
	c.env.BN_FRIENDS[#c.env.BN_FRIENDS + 1] = { Account(ANNA, true), battleTag = ANNA.tag }
	c.env.Fire("BN_FRIEND_LIST_SIZE_CHANGED")
	Pass(c, 5)
	Say(c, BOB, "B2;es;" .. ANNA.key .. ":1-4")
	Pass(c, 1.2)
	check(Offered() == "1-4", "Battle.net lists her (and says so): taken within seconds, got " .. Offered())
	-- Without an event: an account not looked for since the list was read is looked for again.
	Pass(c, 6)
	local dot = Person(99, "Dot Fern", "MAGE", "Dot#9999", "d0d0d0d0") -- (offline)
	c.env.BN_FRIENDS[#c.env.BN_FRIENDS + 1] = { Account(dot, false), battleTag = dot.tag }
	local dorothy = dot.acct .. "." .. dot.store
	Say(c, BOB, "B2;es;" .. dorothy .. ":1")
	Pass(c, 1.2)
	local peer = c.D.peers[BOB.id]
	check(peer and peer.holdings[dorothy], "a friend's account the list didn't have when last read: read again, taken")
	Stop(c)
end

section("Echoes' delivery: the probe when sending says nothing")
do
	-- If SendGameData returns nothing on Forever (Beacon takes that as sent), the probe doesn't call
	-- every size refused: what the friend answers says what arrived.
	local c = Start(EVE, { friends = { ANNA }, fake = true })
	MeetAll(c, { ANNA })
	local send = c.env.C_BattleNet.SendGameData
	c.env.C_BattleNet.SendGameData = function(...)
		send(...)
		return nil
	end
	Pass(c, 5)
	local ok = c.D.Probe("anna")
	Pass(c, 4)
	Say(c, ANNA, "B2;ey;255;255")
	Say(c, ANNA, "B2;ey;500;500")
	local printed = #c.env.PRINTED
	Pass(c, 25)
	local line = table.concat(c.env.PRINTED, "\n", printed + 1)
	check(ok and line:find("255 bytes: arrived whole; 500 bytes: arrived whole; 1000 bytes: no answer", 1, true),
		"no result from sending: what arrived counts, got " .. line)
	c.env.C_BattleNet.SendGameData = send
	Stop(c)
end

section("Beacon: a hello right after my answer (a friend's quick /reload)")
do
	-- Beacon answers one friend's hellos at most every 5 s. Anna /reloads 2 s after my answer: her
	-- new session's hello is answered once the 5 s are up (her build, and Echoes' hello with it),
	-- not dropped. More hellos meanwhile still get one answer.
	local c = Start(EVE, { friends = { ANNA }, fake = true })
	local mark = Mark(c)
	Meet(c, ANNA, NEW)
	Hello(c, ANNA, "s")
	local first = #Sent(c, ANNA, mark, "V2;")
	mark = Mark(c)
	Say(c, ANNA, "H2")
	Pass(c, 2)
	Say(c, ANNA, "H2") -- (she /reloaded)
	Say(c, ANNA, "H2")
	Pass(c, 1)
	check(#Sent(c, ANNA, mark, "V2;") == 1, "(one answer, then nothing for 5 s)")
	Pass(c, 5)
	check(first == 1 and #Sent(c, ANNA, mark, "V2;") == 2, "the hello right after it: answered once the 5 s are up, once")
	Pass(c, 10)
	check(#Sent(c, ANNA, mark, "V2;") == 2 and #Sent(c, ANNA, mark, "B2;eh;") >= 2, "... with Echoes' hello, and no more")
	Stop(c)
end

section("Echoes' delivery: a saved file edited by hand")
do
	-- Keys that aren't 8 lowercase hex digits twice, and a safe entry that isn't a table: they stay
	-- out of my messages (friends would refuse the whole message, or it would pass 255 bytes), and
	-- nothing fails.
	local c = Start(EVE, { friends = { ANNA, DORA }, fake = true })
	local p = TheirPage(c, 5, 300)
	local page = { t = p.t, h = p.h, m = "z", z = p.z, s = c.E.data.session - 1, a = c.env.GetServerTime() - 60 }
	c.E.data.carry["ABCDEF01.0c77e1f2"] = { [5] = page }
	c.E.data.carry[("0123456789abcdef"):rep(10) .. ".0c77e1f2"] = { [5] = page }
	c.E.data.carry[ANNA.key] = { [5] = page }
	c.E.data.safe["0badc0de.0badc0de"] = "1-5"
	c.E.data.safe[ANNA.key] = { ["AAAAAAAA.BBBBBBBB"] = "1-3", [DORA.key] = "1-4" }
	Touched(c)
	local mark = Mark(c)
	MeetAll(c, { DORA }, "crs")
	Pass(c, 65)
	local read, items = true, 0
	for _, m in ipairs(Sent(c, DORA, mark, "B2;e")) do
		local word, more = m:match("^B2;(e%l);(.*)$")
		local msg = #m <= 255 and c.D.Read(word, more)
		read = read and msg ~= nil
		items = items + (msg and msg.items and #msg.items or 0)
	end
	check(read and items >= 2, "every message of mine reads (with Anna's page held and Dora's summary), got " .. items .. " items")
	Stop(c)
end

---------------------------------------------------------------------------
-- Three clients: Anna records, Bob relays, Cedric collects; Finn runs an older build
---------------------------------------------------------------------------

section("Echoes' delivery: three clients (author, relay, collector)")
do
	local everyone = { ANNA, BOB, CEDRIC, FINN }
	local function Others(p)
		local list = {}
		for _, f in ipairs(everyone) do
			if f ~= p then
				list[#list + 1] = f
			end
		end
		return list
	end
	world.time = 0
	local finn = Start(FINN, { friends = Others(FINN), version = OLD, without = "Modules/Echoes/Delivery.lua" })
	local anna = Start(ANNA, { friends = Others(ANNA) })
	local bob = Start(BOB, { friends = Others(BOB) })
	-- Anna's recording: pages 101-106 (1-3 KB), and 107 in plain text (compression failed: never shared).
	local pages = {}
	for n = 101, 106 do
		pages[n] = MyPage(anna, n, 1000 + (n - 100) * 300)
	end
	MyPage(anna, 107, 400, "t")
	local akey = ANNA.acct .. "." .. anna.E.data.store
	local function Carried(c)
		local n = 0
		for i = 101, 106 do
			local page = (c.E.data.carry[akey] or {})[i]
			n = n + ((page and page.z == pages[i].z and page.h == pages[i].h and page.t == pages[i].t) and 1 or 0)
		end
		return n
	end
	local function Collected(c)
		local n = 0
		for i = 101, 106 do
			local page = (c.E.data.inbox[akey] or {})[i]
			n = n + ((page and page.z == pages[i].z and page.h == pages[i].h and page.m == "z") and 1 or 0)
		end
		return n
	end

	-- Bob relays while Cedric is offline.
	check(Run(300, function() return Carried(bob) == 6 end), "Bob (relay) carries all 6 of Anna's pages, got " .. Carried(bob))
	check(not (bob.E.data.carry[akey] or {})[107] and next(bob.E.data.inbox) == nil, "not the plain-text one; nothing in Bob's inbox")
	local annaPeer = bob.D.peers[ANNA.id]
	check(annaPeer and annaPeer.verified and annaPeer.share and not annaPeer.collect and bob.D.peers[FINN.id] == nil,
		"Bob knows Anna's Echoes (her account checked); Finn has none")

	-- Anna goes; Cedric (collector) comes and gets them from Bob. Bob goes mid-page; Anna is back:
	-- the page goes on from her, from where it got to.
	local annaSaved = Stop(anna)
	local cedric = Start(CEDRIC, { friends = Others(CEDRIC), collect = true })
	local resumed = Run(300, function()
		for _, part in pairs(cedric.D.partials) do
			if part.have > 0 and Collected(cedric) >= 2 then
				return true
			end
		end
	end, 0.05)
	check(resumed, "Cedric got " .. Collected(cedric) .. " page(s) from Bob, and part of the next")
	local partial
	for pageId, part in pairs(cedric.D.partials) do
		partial = { id = pageId, have = part.have }
	end
	local bobSaved = Stop(bob)
	local mark = #world.log + 1
	anna = Start(ANNA, { friends = Others(ANNA), saved = annaSaved })
	check(Run(300, function() return Collected(cedric) == 6 end), "Cedric collects all 6, got " .. Collected(cedric))
	local resumedFrom
	for i = mark, #world.log do
		local m = world.log[i]
		local n, offset = m.data:match("^B2;eq;" .. ANNA.acct .. ";%x+;(%d+);(%d+)$")
		if m.from == CEDRIC.id and m.to == ANNA.id and n and akey .. "." .. n == partial.id then
			resumedFrom = resumedFrom or tonumber(offset)
		end
	end
	check(resumedFrom and resumedFrom == partial.have and resumedFrom > 0,
		"the page Bob didn't finish: asked of Anna from byte " .. tostring(resumedFrom) .. " (had " .. partial.have .. ")")
	local session = cedric.E.data.session
	local sessions = true
	for _, page in pairs(cedric.E.data.inbox[akey]) do
		sessions = sessions and page.s == session
	end
	check(sessions and Keys(anna.E.data.mine) == "101,102,103,104,105,106,107", "Cedric's pages came this session: Anna keeps her copies")
	Run(65)
	check(Keys(anna.E.data.mine) == "101,102,103,104,105,106,107", "a minute later still (not on Cedric's disk yet)")

	-- Bob is back; Anna goes. Cedric's next session: on his disk now. Bob hears it and drops his copies.
	annaSaved = Stop(anna)
	bob = Start(BOB, { friends = Others(BOB), saved = bobSaved })
	Run(5)
	check(Carried(bob) == 6, "Bob back, still carrying them")
	cedric = Reload(cedric)
	check(cedric.E.data.session == session + 1 and Collected(cedric) == 6, "Cedric's /reload: the next session, his pages kept")
	check(Run(120, function() return Carried(bob) == 0 end), "Bob drops his copies: safe at Cedric")
	check(bob.E.data.safe[akey] and bob.E.data.safe[akey][CEDRIC.acct .. "." .. cedric.E.data.store] == "101-106", "Bob keeps what Cedric holds safely")

	-- Cedric goes; Anna comes back: Bob passes on what Cedric holds, and she drops her copies.
	local cedricStore = cedric.E.data.store
	Stop(cedric)
	anna = Start(ANNA, { friends = Others(ANNA), saved = annaSaved })
	check(Run(120, function() return Keys(anna.E.data.mine) == "107" end), "Anna drops pages 101-106 (Bob told her Cedric has them), got " .. Keys(anna.E.data.mine))
	check(anna.E.data.safe[akey] and anna.E.data.safe[akey][CEDRIC.acct .. "." .. cedricStore] == "101-106", "... and keeps page 107, never shared")

	-- Finn never got a B message; Beacon talked to him as ever. Every B message fits 255 bytes.
	local toFinn, beaconToFinn, longest = 0, 0, 0
	for _, m in ipairs(world.log) do
		if m.to == FINN.id then
			toFinn = toFinn + (m.data:sub(1, 2) == "B2" and 1 or 0)
			beaconToFinn = beaconToFinn + (m.data:sub(1, 3) == "S2;" and 1 or 0)
		end
		if m.data:sub(1, 3) == "B2;" then
			longest = math.max(longest, #m.data)
		end
	end
	check(toFinn == 0 and beaconToFinn > 0, "Finn (an older build) never got a B message, Beacon's as ever (" .. beaconToFinn .. " states)")
	check(longest <= 255 and longest >= 250, "every B message fits 255 bytes (the longest: " .. longest .. ")")
	Stop(anna)
	Stop(bob)
	Stop(finn)
end

section("Echoes' delivery: an author's crash, the collector online at her next session")
do
	-- Anna records with Cedric (collecting, this build) online. Her page 1 closes and goes to him early
	-- (provisional); then her game crashes. Back a minute later, her last save has page 1 open again
	-- (it goes on); Cedric tells her (her only) he holds a page 1 of hers, so it closes above it, as 2.
	-- His page 1, the lost one, is never confirmed, nothing of Anna's is dropped for it, and her page 2
	-- goes once a copy from her disk confirmed it and it's safe at him.
	local function Write(c, seed) -- (a page's worth of lines: it closes by size on the next tick)
		for _ = 1, 170 do
			c.E.Line("H", seed:rep(200))
		end
	end
	local function Header(page) -- (the number in a packed page's header)
		local text = C_EncodingUtil.DecompressString(C_EncodingUtil.DecodeBase64(page.z), 1)
		return tonumber(text:match("^E1;%x*;%x+;(%d+);"))
	end
	local cedric = Start(CEDRIC, { friends = { ANNA }, collect = true })
	local anna = Start(ANNA, { friends = { CEDRIC } })
	Run(5)
	anna = Reload(anna) -- (her last save: page 1 open, nothing closed)
	local save = anna.opts.saved
	local store = anna.E.data.store
	local key = ANNA.acct .. "." .. store
	local ckey = CEDRIC.acct .. "." .. cedric.E.data.store
	local function Got(n)
		return (cedric.E.data.inbox[key] or {})[n]
	end
	Write(anna, "a")
	Run(1)
	local lost = anna.E.data.mine[1]
	check(lost and lost.m == "z" and anna.E.Store.Page(ANNA.acct, store, 1) == nil, "Anna's page 1 closes and is packed: not on her disk yet")
	check(Run(120, function() return Got(1) ~= nil end) and Got(1).p == 1 and Got(1).z == lost.z, "Cedric, online, gets it early: provisional")
	Stop(anna, false, true) -- (the game crashes: nothing saved)
	Run(60)
	anna = Start(ANNA, { friends = { CEDRIC }, saved = save })
	check(anna.E.data.n == 0 and anna.E.data.open.n == 1, "her next login a minute later reads the last save: page 1 open again (it goes on)")
	check(Run(30, function() return anna.E.data.top == 1 end), "Cedric tells her he holds a page 1 of hers: her next pages close above it")
	Write(anna, "b")
	Run(1)
	local page = anna.E.data.mine[2]
	check(not anna.E.data.mine[1] and page and page.m == "z" and Header(page) == 2, "her open page 1 closes as 2 (its header too)")
	check(Run(120, function() return Got(2) ~= nil end) and Got(2).p == 1 and Got(2).z == page.z, "page 2 goes to Cedric early")
	anna = Reload(anna)
	check(Run(120, function() return Got(2).p == nil end), "after her /reload a copy from her disk confirms page 2")
	check(anna.E.data.mine[2] and Got(1).p == 1 and Got(1).z == lost.z, "Anna keeps page 2 (not on Cedric's disk yet); his page 1, the lost one, stays provisional")
	cedric = Reload(cedric) -- (within 5 s of Anna's last answer to him: she answers when they're up)
	check(Run(120, function() return anna.E.data.mine[2] == nil end), "his next session: page 2 safe at Cedric, Anna drops it")
	local told = (anna.E.data.safe[key] or {})[ckey]
	check(Got(1).p == 1 and not cedric.E.Ranges.Contains(cedric.E.Store.SafeHere(ANNA.acct, store), 1) and anna.E.Ranges.Contains(told, 2)
		and not anna.E.Ranges.Contains(told, 1), "page 1 is never safe at Cedric (never confirmed), got " .. tostring(told))
	Stop(anna)
	Stop(cedric)
end

---------------------------------------------------------------------------
-- More clients: two relays, reloads in the middle of a page on each side, a collector who records
-- too, a full inbox, many pages
---------------------------------------------------------------------------

-- Pages first to last of c's own (MyPage), len bytes each: { [n] = page }.
local function MyPages(c, first, last, len)
	local pages = {}
	for n = first, last do
		pages[n] = MyPage(c, n, len)
	end
	return pages
end

-- How many of pages c keeps in where ("carry", "inbox", "mine") under key, as they were.
local function Holds(c, where, key, pages)
	local list = where == "mine" and c.E.data.mine or c.E.data[where][key] or {}
	local n = 0
	for i, p in pairs(pages) do
		local got = list[i]
		n = n + ((got and got.z == p.z and got.h == p.h) and 1 or 0)
	end
	return n
end

-- The friends of p among people.
local function FriendsOf(p, people)
	local list = {}
	for _, f in ipairs(people) do
		if f ~= p then
			list[#list + 1] = f
		end
	end
	return list
end

-- A page c has part of, and from whom: pageId, have, holder (nil: none).
local function Partial(c)
	for pageId, part in pairs(c.D.partials) do
		local r = c.D.inflight[pageId]
		if part.have > 0 and part.have < part.len and r then
			return pageId, part.have, r.from
		end
	end
end

section("Echoes' delivery: two relays, then the collector reloading, and a relay reloading, mid-page")
do
	local people = { ANNA, BOB, CEDRIC, DORA }
	local anna = Start(ANNA, { friends = FriendsOf(ANNA, people) })
	local bob = Start(BOB, { friends = FriendsOf(BOB, people) })
	local dora = Start(DORA, { friends = FriendsOf(DORA, people) })
	local pages = MyPages(anna, 101, 112, 2400) -- (10 parts each)
	local akey = ANNA.acct .. "." .. anna.E.data.store
	-- Two relays: each sees one other copy besides Anna's (fewer than 2), so both carry them all.
	check(Run(900, function() return Holds(bob, "carry", akey, pages) == 12 and Holds(dora, "carry", akey, pages) == 12 end),
		"two relays carry all 12 of Anna's pages, got " .. Holds(bob, "carry", akey, pages) .. " and " .. Holds(dora, "carry", akey, pages))
	local annaSaved = Stop(anna)

	-- Cedric collects from both. Bob /reloads in the middle of a page Cedric has part of: Cedric goes
	-- on with it from where it got to (of Bob again, or Dora).
	local cedric = Start(CEDRIC, { friends = FriendsOf(CEDRIC, people), collect = true })
	local pageId, have
	check(Run(300, function()
		local id, got, from = Partial(cedric)
		if id and from == BOB.id and got >= 480 then
			pageId, have = id, got
			return true
		end
	end, 0.05), "Cedric has part of a page from Bob")
	local mark = #world.log + 1
	bob = Reload(bob)
	check(Run(120, function() return not cedric.D.partials[pageId] end), "... and gets the rest of it after Bob's /reload")
	local resumed
	for i = mark, #world.log do
		local m = world.log[i]
		local n, offset = m.data:match("^B2;eq;" .. ANNA.acct .. ";%x+;(%d+);(%d+)$")
		if m.from == CEDRIC.id and n and akey .. "." .. n == pageId then
			resumed = resumed or tonumber(offset)
		end
	end
	check(resumed and resumed >= have, "asked for again from byte " .. tostring(resumed) .. " (had " .. tostring(have) .. ")")
	local fromBoth = { [BOB.id] = 0, [DORA.id] = 0 }
	for _, m in ipairs(world.log) do
		if m.to == CEDRIC.id and m.data:sub(1, 6) == "B2;ep;" and fromBoth[m.from] then
			fromBoth[m.from] = fromBoth[m.from] + 1
		end
	end
	check(fromBoth[BOB.id] > 0 and fromBoth[DORA.id] > 0, "parts came from both relays (" .. fromBoth[BOB.id] .. " and " .. fromBoth[DORA.id] .. ")")

	-- Cedric /reloads in the middle of a page: its parts went with his session; he gets it whole after.
	check(Run(300, function() return Partial(cedric) ~= nil end, 0.05) or Holds(cedric, "inbox", akey, pages) == 12,
		"(Cedric has part of another page)")
	local before = Holds(cedric, "inbox", akey, pages)
	cedric = Reload(cedric)
	check(before < 12 and Run(600, function() return Holds(cedric, "inbox", akey, pages) == 12 end),
		"Cedric /reloaded mid-page (" .. before .. " whole): he collects all 12, got " .. Holds(cedric, "inbox", akey, pages))
	-- His next session: on his disk. Both relays drop theirs; Anna, back, drops hers.
	cedric = Reload(cedric)
	check(Run(300, function() return Holds(bob, "carry", akey, pages) == 0 and Holds(dora, "carry", akey, pages) == 0 end),
		"safe at Cedric: both relays drop their copies")
	Stop(cedric)
	anna = Start(ANNA, { friends = FriendsOf(ANNA, people), saved = annaSaved })
	check(Run(300, function() return Holds(anna, "mine", nil, pages) == 0 end), "Anna, back, drops hers (the relays told her)")
	Stop(anna)
	Stop(bob)
	Stop(dora)
end

section("Echoes' delivery: a collector who records too, a full inbox, many pages")
do
	local people = { ANNA, BOB, CEDRIC }
	local cedric = Start(CEDRIC, { friends = FriendsOf(CEDRIC, people), collect = true })
	local anna = Start(ANNA, { friends = FriendsOf(ANNA, people) })
	local bob = Start(BOB, { friends = FriendsOf(BOB, people) })
	local mine = MyPages(cedric, 201, 205, 1200) -- (Cedric's own recording)
	local pages = MyPages(anna, 101, 220, 1000) -- (120 pages, 5 parts each)
	local akey, ckey = ANNA.acct .. "." .. anna.E.data.store, CEDRIC.acct .. "." .. cedric.E.data.store
	-- Cedric's inbox is full (8 MB, waiting for the exporter): he asks for nothing. Bob relays meanwhile
	-- (a collector online doesn't hold them); Anna keeps all of hers.
	local filler = BOB.acct .. ".0badf00d"
	cedric.E.data.inbox[filler] = { [1] = { t = 1, h = "00000000", m = "z", z = ("A"):rep(8 * 1024 * 1024), s = cedric.E.data.session } }
	Touched(cedric)
	local mark = #world.log + 1
	Run(90)
	local asked = 0
	for i = mark, #world.log do
		asked = asked + ((world.log[i].from == CEDRIC.id and world.log[i].data:sub(1, 6) == "B2;eq;") and 1 or 0)
	end
	check(cedric.E.Store.InboxFull() and asked == 0 and Holds(cedric, "inbox", akey, pages) == 0
		and Holds(anna, "mine", nil, pages) == 120, "the inbox full: Cedric asks for nothing, Anna keeps hers")
	-- The exporter ran (its receipt dropped the filler): he collects all 120, from Anna and Bob.
	cedric.E.Store.Drop(BOB.acct, "0badf00d")
	cedric.D.PagesChanged()
	check(Run(1500, function() return Holds(cedric, "inbox", akey, pages) == 120 end),
		"room again: Cedric collects all 120 of Anna's, got " .. Holds(cedric, "inbox", akey, pages))
	-- His own pages: in his own (mine), never in an inbox or a relay's cache (he holds them: nobody
	-- relays them), and not dropped at his next session (only the exporter's receipt does that).
	check(Holds(cedric, "mine", nil, mine) == 5 and not cedric.E.data.inbox[ckey] and not bob.E.data.carry[ckey]
		and not anna.E.data.carry[ckey], "Cedric's own pages: his, nobody carries them")
	cedric = Reload(cedric)
	check(Run(300, function() return Holds(anna, "mine", nil, pages) == 0 and Holds(bob, "carry", akey, pages) == 0 end),
		"safe at Cedric: Anna drops hers, Bob his copies")
	check(Holds(cedric, "mine", nil, mine) == 5, "Cedric's own stay (until the exporter has them), got " .. Holds(cedric, "mine", nil, mine))
	-- The budget, all along: never more than 3 Echoes messages in a second from one client, nor 2 to
	-- one friend; none over 255 bytes. (By client: a friend's last messages before a section stops
	-- them and the next one's first, from a client of their own, aren't one client's.)
	local sent = {}
	for _, m in ipairs(world.log) do
		if m.data:sub(1, 4) == "B2;e" then
			sent[m.client] = sent[m.client] or {}
			table.insert(sent[m.client], m)
		end
	end
	local most, mostTo, longest = 0, 0, 0
	for _, list in pairs(sent) do
		for i, m in ipairs(list) do
			local all, to = 0, 0
			for j = i, #list do
				if list[j].at - m.at > 1 - 1e-6 then
					break
				end
				all = all + 1
				to = to + (list[j].to == m.to and 1 or 0)
			end
			most, mostTo, longest = math.max(most, all), math.max(mostTo, to), math.max(longest, #m.data)
		end
	end
	check(most <= 3 and mostTo <= 2 and longest <= 255, ("within the budget: at most %d in a second from one client, %d to one friend,"
		.. " the longest %d bytes"):format(most, mostTo, longest))
	Stop(cedric)
	Stop(anna)
	Stop(bob)
end

---------------------------------------------------------------------------
-- Page numbers used twice: a WTF folder restored from a backup, or copied to a second computer and
-- played on both (one store, both numbering from the same saved n)
---------------------------------------------------------------------------

-- A page's worth of lines: it closes by size on the next tick.
local function Fill(c, seed)
	for _ = 1, 170 do
		c.E.Line("H", seed:rep(200))
	end
end

-- A page's text without its header's number (a page that moves to a new number keeps the rest).
local function Body(text)
	return (text:gsub("^(E1;[^;\n]*;[^;\n]*;)%d+;", "%1#;", 1))
end

-- A stored page's text, unpacked as the exporter does (the game never does).
local function TextOf(page)
	if page.m == "z" then
		return C_EncodingUtil.DecompressString(C_EncodingUtil.DecodeBase64(page.z), 1)
	end
	return page.m == "r" and C_EncodingUtil.DecodeBase64(page.z) or page.z
end

-- Every page c closes (those closed at its login, still waiting to be packed, too): its Body into
-- closed (true).
local function Watch(c, closed)
	for _, page in pairs(c.E.data.mine) do
		if page.q then
			closed[Body(page.z)] = true
		end
	end
	local close = c.E.Store.Close
	c.E.Store.Close = function(...)
		local n = close(...)
		closed[Body(c.E.data.mine[n].z)] = true
		return n
	end
end

-- How many of closed (Bodies) c collected under key, and whether each came under one number only.
local function Gathered(c, key, closed)
	local got, numbers, once = {}, {}, true
	for n, page in pairs(c.E.data.inbox[key] or {}) do
		local body = Body(TextOf(page))
		once = once and not got[body]
		got[body], numbers[#numbers + 1] = true, n
	end
	local n, all = 0, 0
	for body in pairs(closed) do
		all = all + 1
		n = n + (got[body] and 1 or 0)
	end
	table.sort(numbers)
	return n, all, once, table.concat(numbers, ",")
end

-- The page numbers of a table, sorted.
local function Numbers(t)
	local list = {}
	for n in pairs(t or {}) do
		list[#list + 1] = n
	end
	table.sort(list)
	return table.concat(list, ",")
end

section("Echoes' delivery: many relays at once spread over an author's pages")
do
	-- Four relays and Anna come online together, nobody holding anything yet: each asks her for a
	-- page, and not all for the same first one (they'd all fetch it while what they hold spreads).
	local people = { ANNA, BOB, DORA, EVE, GWEN }
	local relays = {}
	for _, p in ipairs({ BOB, DORA, EVE, GWEN }) do
		relays[#relays + 1] = Start(p, { friends = FriendsOf(p, people) })
	end
	local anna = Start(ANNA, { friends = FriendsOf(ANNA, people) })
	MyPages(anna, 101, 140, 480)
	local mark = #world.log + 1
	local firsts = {}
	local function Asked()
		for i = mark, #world.log do
			local m = world.log[i]
			local n = m.to == ANNA.id and m.data:match("^B2;eq;" .. ANNA.acct .. ";%x+;(%d+);0$")
			if n and not firsts[m.from] then
				firsts[m.from] = tonumber(n)
			end
		end
		local count = 0
		for _ in pairs(firsts) do
			count = count + 1
		end
		return count == 4
	end
	check(Run(120, Asked), "each relay asked Anna for a page")
	local list, same = {}, true
	for _, n in pairs(firsts) do
		list[#list + 1] = n
		same = same and n == list[1]
	end
	table.sort(list)
	check(not same, "their first pages: " .. table.concat(list, ", ") .. " (not all the same)")
	local akey = ANNA.acct .. "." .. anna.E.data.store
	check(Run(900, function()
		for n = 101, 140 do
			local copies = 0
			for _, c in ipairs(relays) do
				copies = copies + ((c.E.data.carry[akey] or {})[n] and 1 or 0)
			end
			if copies < 2 then
				return false
			end
		end
		return true
	end), "every one of her 40 pages carried by at least two of them")
	Stop(anna)
	for _, c in ipairs(relays) do
		Stop(c)
	end
end

section("Echoes' delivery: a page of mine that moves to a new number while I serve it")
do
	local c = Start(EVE, { friends = { ANNA, BOB }, fake = true })
	local key = EVE.acct .. "." .. c.E.data.store
	local p, q = MyPage(c, 701, 2400), MyPage(c, 702, 2400) -- (10 parts each)
	p.o, q.o = 0, 0 -- (closed by this build: not out yet)
	MeetAll(c, { ANNA, BOB })
	local mark = Mark(c)
	Ask(c, ANNA, 701)
	Pass(c, 3)
	check(#Sent(c, ANNA, mark, "B2;ep;") >= 1 and p.o == 1 and q.o == 0, "a part of 701 went to Anna: it's out")
	-- Bob asks for 702 in a fight (nothing goes yet). Anna offers a 701 and a 702 of mine: 701 is the
	-- one I sent; 702 never went out, so hers is another page 702 (my WTF folder copied?): mine moves,
	-- and nothing of it goes as 702 any more.
	c.env.EnterCombat()
	mark = Mark(c)
	Ask(c, BOB, 702)
	Pass(c, 0.5)
	Say(c, ANNA, ("B2;es;%s:701-702"):format(key))
	Pass(c, 1.2)
	local new = c.E.data.top
	check(c.E.data.mine[701] == p and not c.E.data.mine[702] and new and new > 1000 and c.E.data.mine[new] == q,
		"701 keeps its number; 702 moves (to " .. tostring(new) .. ")")
	c.env.LeaveCombat()
	Pass(c, 10)
	check(#Sent(c, BOB, mark, "B2;eb;") == 0 and #Sent(c, BOB, mark, "B2;ep;") == 0 and #c.D.active == 0,
		"after the fight nothing of it goes to Bob as 702")
	Ask(c, BOB, 702)
	Pass(c, 1.5)
	check(#Sent(c, BOB, mark, "B2;en;") == 1, "asked again: I don't have a 702")
	Stop(c)
end

section("Echoes' delivery: a WTF folder restored from a backup (page numbers used again)")
do
	local cedric = Start(CEDRIC, { friends = { ANNA }, collect = true })
	local anna = Start(ANNA, { friends = { CEDRIC } })
	Run(5)
	anna = Reload(anna)
	local backup = Copy(anna.opts.saved) -- (her saved table now: copied aside)
	local key = ANNA.acct .. "." .. anna.E.data.store
	local closed = {}
	Watch(anna, closed)
	for _, seed in ipairs({ "a", "b", "c" }) do
		Fill(anna, seed)
		Run(1)
	end
	check(Numbers(anna.E.data.mine) == "1,2,3", "Anna's pages 1-3 closed")
	local function Provisional(n)
		return (cedric.E.data.inbox[key] or {})[n] and cedric.E.data.inbox[key][n].p
	end
	check(Run(120, function() return Provisional(1) and Provisional(2) and Provisional(3) end), "Cedric, online, takes them early (provisional)")
	anna = Reload(anna)
	Watch(anna, closed)
	check(Run(300, function() return Numbers(cedric.E.data.inbox[key]) == "1,2,3" and not (Provisional(1) or Provisional(2) or Provisional(3)) end),
		"after her /reload copies from her disk confirm them: Cedric collected 1-3")
	check(anna.E.data.mine[1].o == 1 and anna.E.data.mine[3].o == 1, "they went out (o = 1)")
	-- As ever: pages that went out go once they're safe at the collector.
	cedric = Reload(cedric)
	check(Run(120, function() return next(anna.E.data.mine) == nil end), "safe at Cedric (his next session): Anna drops them, as before")
	local collected = {}
	for n, page in pairs(cedric.E.data.inbox[key]) do
		collected[n] = page.z
	end

	-- The backup comes back, more than 10 minutes later, while Cedric is away: her saved table from
	-- before pages 1-3. Its open page closes as 1 (stale at login); she records 2 and 3 again, with
	-- other lines, and they're on disk after a /reload: offered, nobody there to say the numbers are
	-- taken.
	Stop(anna)
	local cedricSaved = Stop(cedric)
	Run(700)
	anna = Start(ANNA, { friends = { CEDRIC }, saved = backup })
	Watch(anna, closed)
	check(anna.E.data.n == 1 and anna.E.data.mine[1] and anna.E.data.open.n == 2, "(the backup: its open page closes as 1, stale at login)")
	for _, seed in ipairs({ "d", "e" }) do
		Fill(anna, seed)
		Run(1)
	end
	anna = Reload(anna)
	Watch(anna, closed)
	check(Numbers(anna.E.data.mine) == "1,2,3" and anna.E.Store.Page(ANNA.acct, anna.E.data.store, 3), "her new 1-3, offered")
	-- Cedric is back: what he holds and his summary say 1-3 are taken. Hers never went out: they're
	-- other pages; they move to new numbers, nothing is dropped, and he collects them after her next
	-- /reload (a moved page is offered from the next session on).
	cedric = Start(CEDRIC, { friends = { ANNA }, saved = cedricSaved })
	check(Run(60, function() return anna.E.data.mine[1] == nil end), "Anna hears 1-3 are taken")
	local moved = Numbers(anna.E.data.mine)
	check(moved == "5,6,7" and anna.E.data.top == 7, "hers moved to 5-7 (above the open page 4), got " .. moved)
	Fill(anna, "f")
	Run(1)
	check(anna.E.data.mine[8] and TextOf(anna.E.data.mine[8]):find("^E1;%x+;%x+;8;") and anna.E.data.open.n == 9,
		"the open page 4 closes above them: 8 (its header too)")
	anna = Reload(anna)
	check(Run(300, function() return select(1, Gathered(cedric, key, closed)) == select(2, Gathered(cedric, key, closed)) end),
		"Cedric collects every page Anna closed, the backup's too")
	local n, all, once, numbers = Gathered(cedric, key, closed)
	check(n == 7 and all == 7 and once and numbers == "1,2,3,5,6,7,8", ("all %d of %d (1-3, the backup's 1, its 2-3 again, 8), each under one number (%s)"):format(n, all, numbers))
	local same = true
	for i, z in pairs(collected) do
		same = same and cedric.E.data.inbox[key][i].z == z
	end
	check(same, "the 1-3 he had are as they were (pages never change)")
	cedric = Reload(cedric)
	check(Run(120, function() return next(anna.E.data.mine) == nil end), "his next session: safe, Anna drops them")
	Stop(anna)
	Stop(cedric)
end

section("Echoes' delivery: one WTF folder on two computers, played by turns")
do
	-- Anna copies her WTF folder to a second computer and plays on both by turns (never at once: one
	-- BattleTag): one store, both number their pages from the same n. Bob relays; Cedric collects,
	-- online only later. Every page either computer closes reaches Cedric, each under its own number.
	local people = { ANNA, BOB, CEDRIC }
	local bob = Start(BOB, { friends = FriendsOf(BOB, people) })
	local anna = Start(ANNA, { friends = FriendsOf(ANNA, people) })
	Run(5)
	anna = Reload(anna)
	local savedA, savedB = anna.opts.saved, Copy(anna.opts.saved) -- (the folder copied to the second computer)
	local key = ANNA.acct .. "." .. anna.E.data.store
	Stop(anna)
	local closed = {}
	-- One turn at a computer: pages written, then a /reload (offered), time for friends to carry them.
	local function Turn(saved, seeds)
		local c = Start(ANNA, { friends = FriendsOf(ANNA, people), saved = saved })
		Watch(c, closed)
		Run(10)
		for _, seed in ipairs(seeds) do
			Fill(c, seed)
			Run(1)
		end
		c = Reload(c)
		Watch(c, closed)
		Run(240)
		return c, Stop(c)
	end
	local function Carried(c)
		return Numbers(c.E.data.carry[key])
	end
	local first
	first, savedA = Turn(savedA, { "a", "b" })
	check(Numbers(first.E.data.mine) == "1,2" and Carried(bob) == "1,2", "the first computer: pages 1-2, Bob carries them, got " .. Carried(bob))
	Run(700)
	local second
	second, savedB = Turn(savedB, { "c", "d" })
	local onSecond = Numbers(second.E.data.mine)
	check(onSecond == "3,4,5", "the second: its open page from the copy (closed as 1 at login) moves to 3 (Bob holds 1-2), then 4-5, got " .. onSecond)
	check(Carried(bob) == "1,2,3,4,5", "Bob carries all, got " .. Carried(bob))
	first, savedA = Turn(savedA, { "e" })
	check(Numbers(first.E.data.mine) == "1,2,6,7", "the first again: its open page (closed as 3 at login) moves to 6, then 7, got " .. Numbers(first.E.data.mine))
	-- Cedric comes and collects from Bob; his next session: safe, Bob drops his copies.
	local cedric = Start(CEDRIC, { friends = FriendsOf(CEDRIC, people), collect = true })
	check(Run(600, function() return Numbers(cedric.E.data.inbox[key]) == "1,2,3,4,5,6,7" end),
		"Cedric collects 1-7 from Bob, got " .. Numbers(cedric.E.data.inbox[key]))
	local n, all, once = Gathered(cedric, key, closed)
	check(n == all and all == 7 and once, ("every page either computer closed: %d of %d, each under one number"):format(n, all))
	cedric = Reload(cedric)
	check(Run(120, function() return Carried(bob) == "" end), "safe at Cedric: Bob drops his copies")
	-- Each computer, back, drops its own (they went out). The second's open page from its last turn,
	-- busy for more than 10 minutes with Cedric online (he takes pages early), closes meanwhile: it
	-- goes to Cedric early, and she keeps it until it's safe at him (his next session).
	second, savedB = Turn(savedB, {})
	local left, kept = Numbers(second.E.data.mine), true
	for n, page in pairs(second.E.data.mine) do
		local got = (cedric.E.data.inbox[key] or {})[n]
		kept = kept and n > 7 and got ~= nil and got.h == page.h and not cedric.E.Ranges.Contains(cedric.E.Store.SafeHere(ANNA.acct, key:sub(10)), n)
	end
	check(kept, "the second computer drops its pages 3-5; a page it closed this turn stays (Cedric has it, not safe yet), got " .. left)
	Stop(cedric)
	Stop(bob)
end

---------------------------------------------------------------------------
-- Early pages: a collector online gets an author's pages closed this session (not on her disk yet)
-- at once, and keeps them provisional until a copy from her disk shows the same hash
---------------------------------------------------------------------------

-- A page's worth of lines, the first 20 varied (it packs to a few KB: a page of many parts).
local function Varied(c, seed)
	for i = 1, 170 do
		c.E.Line("H", i <= 20 and Data(200, seed * 1000 + i) or ("v"):rep(200))
	end
end

-- What went from one person's client to another's since mark (world.log), starting with prefix.
local function Logged(mark, from, to, prefix)
	local list = {}
	for i = mark, #world.log do
		local m = world.log[i]
		if m.from == from.id and m.to == to.id and m.data:sub(1, #prefix) == prefix then
			list[#list + 1] = m.data
		end
	end
	return list
end

-- A set of page numbers ({ [n] = true }) as ranges ("1-3,5").
local function RangesOf(set)
	local list, parts, i = {}, {}, 1
	for n in pairs(set) do
		list[#list + 1] = n
	end
	table.sort(list)
	while list[i] do
		local j = i
		while list[j + 1] == list[j] + 1 do
			j = j + 1
		end
		parts[#parts + 1] = i == j and tostring(list[i]) or (list[i] .. "-" .. list[j])
		i = j + 1
	end
	return table.concat(parts, ",")
end

-- The exporter on a collector's PC, as far as the game sees it. Read(saved): every version of each
-- page in a collector's saved inbox (archive[key][n][hash]: true once a copy of it came from a disk,
-- false while only copies that came early, p); its receipt: in done the numbers it has a version of
-- from a disk, in early the ones it has only from copies that came early, and per collector's store
-- the latest arrival it read (upto, never lower).
local function Exporter()
	local x = { archive = {}, upto = {} }
	function x.Receipt()
		local done, early, upto = {}, {}, {}
		for key, numbers in pairs(x.archive) do
			local disk, only = {}, {}
			for n, versions in pairs(numbers) do
				local fromDisk = false
				for _, d in pairs(versions) do
					fromDisk = fromDisk or d
				end
				if fromDisk then
					disk[n] = true
				else
					only[n] = true
				end
			end
			done[key], early[key] = RangesOf(disk), RangesOf(only)
		end
		for store, a in pairs(x.upto) do
			upto[store] = a
		end
		return { v = 1, at = world.time, done = done, early = early, upto = upto }
	end
	function x.Read(saved)
		local db = saved.LefthyToolsEchoesDB
		local upto = x.upto[db.store] or 0
		for key, pages in pairs(db.inbox or {}) do
			x.archive[key] = x.archive[key] or {}
			for n, page in pairs(pages) do
				local versions = x.archive[key][n] or {}
				x.archive[key][n] = versions
				versions[page.h] = versions[page.h] == true or page.p == nil
				upto = math.max(upto, page.a or 0)
			end
		end
		x.upto[db.store] = upto
		return x.Receipt()
	end
	return x
end

-- Page n of acct from one person's client to another's since mark: its starts (eb), and the parts
-- (ep) that went under their transfer ids.
local function Transfer(mark, from, to, acct, n)
	local begun, parts, live = 0, 0, {}
	for i = mark, #world.log do
		local m = world.log[i]
		if m.from == from.id and m.to == to.id then
			local x, a, pn = m.data:match("^B2;eb;(%d+);(%x+);%x+;(%d+);")
			if x then
				live[x] = (a == acct and tonumber(pn) == n) or nil
				begun = begun + (live[x] and 1 or 0)
			end
			local px = m.data:match("^B2;ep;(%d+);")
			if px and live[px] then
				parts = parts + 1
			end
		end
	end
	return begun, parts
end

section("Echoes' delivery: early pages, to a collector online")
do
	-- Anna records with Cedric (collecting, this build) and Bob (relaying) online. A page she closes
	-- goes to Cedric within minutes (ea), not to Bob: Cedric keeps it provisional (never safe, never
	-- served, told only to Anna) until her /reload puts it on her disk and a check shows the same hash.
	local people = { ANNA, BOB, CEDRIC }
	local cedric = Start(CEDRIC, { friends = FriendsOf(CEDRIC, people), collect = true })
	local bob = Start(BOB, { friends = FriendsOf(BOB, people) })
	local anna = Start(ANNA, { friends = FriendsOf(ANNA, people) })
	local function Known(id)
		local peer = anna.D.peers[id]
		return peer ~= nil and peer.verified
	end
	Run(30, function() return Known(CEDRIC.id) and Known(BOB.id) end)
	local store = anna.E.data.store
	local key = ANNA.acct .. "." .. store
	local ckey = CEDRIC.acct .. "." .. cedric.E.data.store
	local R = anna.D.Ranges
	local function Got(n)
		return (cedric.E.data.inbox[key] or {})[n]
	end
	check(Known(CEDRIC.id) and anna.D.peers[CEDRIC.id].early and not anna.D.peers[BOB.id].early and anna.D.EarlyTaker(),
		"Cedric collects on this build: he takes pages early (e in his hello); Bob doesn't")
	-- (/lefthy echoes on a client: what it prints)
	local function Status(c)
		local from = #c.env.PRINTED
		c.env.SlashCmdList.LEFTHYTOOLS("echoes")
		return table.concat(c.env.PRINTED, "\n", from + 1)
	end
	local said = Status(anna)
	check(said:find("Cedric Vale: collects, takes early pages, ", 1, true) and said:find("Bob Stone: relays, ", 1, true)
		and said:find("your pages go to Cedric Vale early (10-minute pages while a collector is online).", 1, true),
		"Anna's status: Cedric takes early pages, her pages go to him early; Bob doesn't, got\n" .. said)
	check(cedric.E.data.names[key] == "Anna" and anna.E.data.names[ckey] == "Cedric" and anna.E.data.names[BOB.acct .. "." .. bob.E.data.store] == "Bob",
		"friends' first names kept by store, once their account is checked")
	Varied(anna, 1)
	Run(1)
	local n = anna.E.data.n
	local page = anna.E.data.mine[n]
	check(page and page.m == "z" and #page.z > 2400 and anna.E.Store.Page(ANNA.acct, store, n) == nil, "(her page closes and is packed: not on her disk yet)")
	check(Run(120, function() return Got(n) ~= nil end), "Cedric gets it within minutes")
	check(Got(n).p == 1 and Got(n).z == page.z and page.o == 2, "provisional at Cedric (p), as Anna has it; at Anna it went only early (o = 2)")
	said = Status(cedric)
	check(said:find(("Anna: 1 page (%d) up to "):format(n), 1, true) and said:find("; 1 sent early (confirmed once Anna's game saved it).", 1, true),
		"Cedric's status: Anna's page, early, got\n" .. said)
	said = Status(anna)
	check(said:find("no page of yours has reached a collector yet.", 1, true) and said:find(("1 page waiting to reach a collector (%d), recorded"
		.. " since "):format(n), 1, true) and said:find("; 1 of them sent early to a collector, safe once confirmed.", 1, true),
		"Anna's status: nothing safe yet, her page went early, got\n" .. said)
	Run(65)
	local safe = (anna.E.data.safe[key] or {})[ckey]
	check(not R.Has(bob.D.peers[CEDRIC.id].holdings[key] or {}, n) and R.Has(anna.D.peers[CEDRIC.id].holdings[key] or {}, n)
		and not (bob.E.data.carry[key] or {})[n], "Cedric tells Anna he holds it (hers), not Bob; Bob doesn't get it")
	check(not anna.E.Ranges.Contains(safe, n) and not anna.E.Ranges.Contains(cedric.E.Store.SafeHere(ANNA.acct, store), n) and anna.E.data.mine[n] == page,
		"not in Cedric's safe summary: Anna keeps it")
	-- A provisional page isn't served: asked for it (as Bob), Cedric says en.
	local mark = #world.log + 1
	cedric.env.Fire("BN_CHAT_MSG_ADDON", "LTBeacon", ("B2;eq;%s;%s;%d;0"):format(ANNA.acct, store, n), "WHISPER", BOB.id)
	Run(3)
	check(#Logged(mark, CEDRIC, BOB, ("B2;en;%s;%s;%d"):format(ANNA.acct, store, n)) == 1 and #Logged(mark, CEDRIC, BOB, "B2;eb;") == 0,
		"asked for it, Cedric doesn't serve it: en")

	-- Her /reload: on her disk, offered to everyone; Cedric checks it: its start (maybe a part), then
	-- stopped; the same hash: confirmed.
	mark = #world.log + 1
	anna = Reload(anna)
	check(Run(120, function() return Got(n).p == nil end), "after her /reload a copy from her disk confirms it")
	Run(5) -- (his stop goes; what of the page already waited in her queue too)
	-- (the copy from her disk: hers, or Bob's, who may have fetched it from her meanwhile)
	local begun, parts = Transfer(mark, ANNA, CEDRIC, ANNA.acct, n)
	local begun2, parts2 = Transfer(mark, BOB, CEDRIC, ANNA.acct, n)
	local stop = ("B2;eq;%s;%s;%d;%d"):format(ANNA.acct, store, n, #page.z)
	local stops = #Logged(mark, CEDRIC, ANNA, stop) + #Logged(mark, CEDRIC, BOB, stop)
	check(begun + begun2 == 1 and parts + parts2 <= 3 and stops == 1 and Got(n).z == page.z, ("the check: the page's start, %d of its %d"
		.. " parts, then stopped"):format(parts + parts2, math.ceil(#page.z / 240)))
	check(anna.E.data.mine[n] ~= nil and anna.E.data.mine[n].o == 1, ("Anna keeps it: it came in Cedric's session, not on his disk yet; it's out"
		.. " (o = 1; the check: its start and %d part(s) from %s)"):format(parts + parts2, begun > 0 and "her" or "Bob"))
	said = Status(cedric)
	check(said:find(("Anna: 1 page (%d) up to "):format(n), 1, true) and said:find("; 1 not on disk yet (safe after your logout or /reload).", 1, true),
		"Cedric's status: confirmed, not on his disk yet, got\n" .. said)
	cedric = Reload(cedric)
	local function Kept(h)
		for _, p in pairs(anna.E.data.mine) do
			if p.h == h then
				return true
			end
		end
		return false
	end
	check(Run(120, function() return anna.E.data.mine[n] == nil end) and not Kept(page.h), "his next session: safe at Cedric (his summary), Anna"
		.. " drops it (not moved to a new number)")
	said = Status(anna)
	check(said:find(("your recording is safe at a collector up to [^\n]-%s[^\n]- %%(page %d%%)%%."):format(date("%H:%M", page.e), n))
		and said:find("none of your pages waits to reach a collector.", 1, true), "Anna's status: safe at a collector up to her page's end, got\n" .. said)
	said = Status(cedric)
	check(said:find(("Anna: 1 page %%(%d%%) up to [^\n]-; 1 on disk%%."):format(n)), "Cedric's status: on his disk, got\n" .. said)

	-- While Cedric is online her pages close 10 minutes after their first line (30 without him).
	Varied(anna, 2)
	Run(1)
	anna.E.Line("H", "x")
	Run(1)
	local open = anna.E.data.open
	local busy = open.busy
	check(busy and Run(700, function() return anna.E.data.open ~= open end), "her page closes by time with Cedric online")
	local after = anna.E.Now() - busy
	local closed = anna.E.data.mine[anna.E.data.n]
	check(after >= 600 and after <= 602 and closed and TextOf(closed):find("\n%.%d+;t\n$"), "10 minutes after its first line (" .. after
		.. " s), by time")
	Stop(cedric)
	Run(3)
	said = Status(anna)
	check(not anna.D.EarlyTaker() and not said:find("early (10-minute pages", 1, true) and not said:find("takes early pages", 1, true),
		"Cedric gone: nobody who takes pages early, got\n" .. said)
	Stop(anna)
	Stop(bob)
end

section("Echoes' delivery: an author's crash, the collector offline at her next session")
do
	-- Anna's page 1 goes early to Cedric (provisional); Cedric logs out; Anna's game crashes. Her next
	-- session numbers from her last save: another page 1, which goes to Bob (relay) after her /reload.
	-- Cedric back: the check shows another hash; he waits (his inbox holds his page 1), and nobody
	-- drops theirs (it isn't safe at Cedric). The exporter runs: its receipt takes his provisional page
	-- 1 aside (provisional, not exported), and he fetches the other page 1; safe at his next session,
	-- Anna and Bob drop theirs. Both pages 1 reached the exporter.
	local people = { ANNA, BOB, CEDRIC }
	local cedric = Start(CEDRIC, { friends = FriendsOf(CEDRIC, people), collect = true })
	local anna = Start(ANNA, { friends = FriendsOf(ANNA, people) })
	local bob = Start(BOB, { friends = FriendsOf(BOB, people) })
	Run(5)
	anna = Reload(anna) -- (her last save: page 1 open, nothing closed)
	local save = anna.opts.saved
	local store = anna.E.data.store
	local key = ANNA.acct .. "." .. store
	local cstore = cedric.E.data.store
	local function Got(n)
		return (cedric.E.data.inbox[key] or {})[n]
	end
	local function Carried(n)
		return (bob.E.data.carry[key] or {})[n]
	end
	-- The exporter reads Cedric's saved file (its receipt: done, early, upto).
	local exporter = Exporter()
	local Export = exporter.Read
	Varied(anna, 3)
	Run(1)
	local first = anna.E.data.mine[1]
	check(first and Run(120, function() return Got(1) ~= nil end) and Got(1).p == 1 and Got(1).z == first.z and not Carried(1),
		"Anna's page 1 goes early to Cedric (provisional), not to Bob")
	local cedricSaved = Stop(cedric) -- (he logs out: page 1 saved, provisional)
	Stop(anna, false, true) -- (her game crashes: nothing saved)
	Run(60)
	anna = Start(ANNA, { friends = FriendsOf(ANNA, people), saved = save })
	Varied(anna, 4)
	Run(1)
	local second = anna.E.data.mine[1]
	check(second and second.z ~= first.z and second.h ~= first.h, "her next session closes another page 1 (her last save's numbers)")
	anna = Reload(anna)
	check(Run(300, function() return Carried(1) ~= nil end) and Carried(1).z == second.z and anna.E.data.mine[1].o == 1,
		"after her /reload it goes to Bob (out: o = 1)")

	-- Cedric back: a check of page 1 shows another hash. He keeps his, fetches nothing; they keep theirs.
	local mark = #world.log + 1
	cedric = Start(CEDRIC, { friends = FriendsOf(CEDRIC, people), saved = cedricSaved })
	check(Run(60, function() return (cedric.D.checked[key] or {})[1] end), "Cedric back: a check of page 1 shows another hash")
	Run(65)
	local begun, parts = Transfer(mark, BOB, CEDRIC, ANNA.acct, 1)
	local begun2, parts2 = Transfer(mark, ANNA, CEDRIC, ANNA.acct, 1)
	check(begun + begun2 == 1 and parts + parts2 <= 3, ("the check: one start, %d part(s); nothing more asked"):format(parts + parts2))
	check(Got(1).z == first.z and Got(1).p == 1 and anna.E.data.mine[1] and Carried(1), "he keeps his (provisional); Anna and Bob keep theirs")
	cedric = Reload(cedric)
	Run(65)
	check(Got(1).z == first.z and anna.E.data.mine[1] and Carried(1), "his next session too: nothing safe, nothing dropped")

	-- The exporter runs (his saved file: page 1, provisional). Its receipt (1 in early: only that copy)
	-- takes it aside: provisional, not exported. Then the other page 1 is fetched like any.
	local saved = Stop(cedric)
	local receipt = Export(saved)
	check(receipt.done[key] == "" and receipt.early[key] == "1" and receipt.upto[cstore] == saved.LefthyToolsEchoesDB.inbox[key][1].a,
		"(the receipt: 1 in early, the latest arrival read)")
	cedric = Start(CEDRIC, { friends = FriendsOf(CEDRIC, people), saved = saved })
	cedric.env.LefthyToolsEchoesReceipt = receipt
	check(Run(120, function() return Got(1) ~= nil and Got(1).z == second.z end), "the receipt took his page 1 aside: he fetches the other page 1")
	local provisional = cedric.E.data.provisional and cedric.E.data.provisional[key]
	check(Got(1).p == nil and provisional and provisional[1] == first.h and not cedric.E.Ranges.Contains(cedric.E.data.exported[key], 1),
		"the other page 1 in his inbox (from a disk); his early one provisional (its hash), 1 not exported")
	check(anna.E.data.mine[1] and Carried(1), "(it came this session: not safe yet, they keep theirs)")
	-- His next session: safe. The same receipt again (the exporter hasn't run): the page 1 that came
	-- after it stays.
	cedric = Reload(cedric)
	cedric.env.LefthyToolsEchoesReceipt = receipt
	check(Run(120, function() return anna.E.data.mine[1] == nil and not Carried(1) end), "his next session: safe at Cedric, Anna and Bob drop theirs")
	check(Got(1).z == second.z and not cedric.E.Ranges.Contains(cedric.E.data.exported[key], 1) and cedric.E.data.provisional[key][1] == first.h,
		"the same receipt again: the page 1 that came after it stays, not exported")
	-- The exporter runs again: both pages 1 reached it. Its receipt: exported, the provisional entry gone.
	saved = Stop(cedric)
	receipt = Export(saved)
	local versions = exporter.archive[key][1]
	check(versions[first.h] == false and versions[second.h] == true and receipt.done[key] == "1" and receipt.early[key] == "",
		"both pages 1 reached the exporter (the first only early, the second from a disk: 1 in done now)")
	cedric = Start(CEDRIC, { friends = FriendsOf(CEDRIC, people), saved = saved })
	cedric.env.LefthyToolsEchoesReceipt = receipt
	Run(5)
	check(not Got(1) and cedric.E.Ranges.Contains(cedric.E.data.exported[key], 1) and not (cedric.E.data.provisional or {})[key],
		"its receipt: page 1 exported, nothing provisional left")
	Stop(cedric)
	Stop(anna)
	Stop(bob)
end

section("Echoes' delivery: two collectors on one PC share the exporter's receipt")
do
	-- Anna's page 1 (A) goes early to Cedric; her game crashes, and her next page 1 (B) goes to Bob
	-- (relay) after her /reload. The exporter reads Cedric's saved file: it has only A, a copy that
	-- came early, so its receipt lists 1 in early, not in done. Dora collects on another WoW account on
	-- that PC (the same receipt) and has no page 1 of Anna's: she doesn't take 1 as exported (that would
	-- make it safe, and Anna and Bob would drop B, which the exporter doesn't have), and fetches B.
	-- Cedric back with the receipt: A goes aside (provisional), and he fetches B too.
	local people = { ANNA, BOB, CEDRIC, DORA }
	local cedric = Start(CEDRIC, { friends = FriendsOf(CEDRIC, people), collect = true })
	local anna = Start(ANNA, { friends = FriendsOf(ANNA, people) })
	local bob = Start(BOB, { friends = FriendsOf(BOB, people) })
	Run(5)
	anna = Reload(anna) -- (her last save: page 1 open, nothing closed)
	local save = anna.opts.saved
	local key = ANNA.acct .. "." .. anna.E.data.store
	local function Got(c, n)
		return (c.E.data.inbox[key] or {})[n]
	end
	Varied(anna, 3)
	Run(1)
	local first = anna.E.data.mine[1]
	check(first and Run(120, function() return Got(cedric, 1) ~= nil end) and Got(cedric, 1).p == 1, "page 1 (A) goes early to Cedric")
	local cedricSaved = Stop(cedric)
	Stop(anna, false, true) -- (her game crashes: nothing saved)
	Run(60)
	anna = Start(ANNA, { friends = FriendsOf(ANNA, people), saved = save })
	Varied(anna, 4)
	Run(1)
	local second = anna.E.data.mine[1]
	check(second and second.h ~= first.h, "her next session closes another page 1 (B)")
	anna = Reload(anna)
	check(Run(300, function() return (bob.E.data.carry[key] or {})[1] ~= nil end), "after her /reload B goes to Bob")
	local exporter = Exporter()
	local receipt = exporter.Read(cedricSaved)
	check(receipt.done[key] == "" and receipt.early[key] == "1", "the exporter has only A, a copy that came early: 1 in early, not in done")
	local dora = Start(DORA, { friends = FriendsOf(DORA, people), collect = true })
	dora.env.LefthyToolsEchoesReceipt = receipt
	check(Run(180, function() return Got(dora, 1) ~= nil end) and Got(dora, 1).h == second.h and Got(dora, 1).p == nil,
		"Dora (another account on that PC, the same receipt) fetches B")
	check(not dora.E.Ranges.Contains(dora.E.data.exported[key], 1) and anna.E.data.mine[1] and anna.E.data.mine[1].h == second.h
		and (bob.E.data.carry[key] or {})[1], "she doesn't take 1 as exported: Anna and Bob keep B (not safe yet)")
	local doraSaved = Stop(dora)
	cedric = Start(CEDRIC, { friends = FriendsOf(CEDRIC, people), saved = cedricSaved })
	cedric.env.LefthyToolsEchoesReceipt = receipt
	check(Run(180, function() return Got(cedric, 1) ~= nil and Got(cedric, 1).h == second.h end)
		and ((cedric.E.data.provisional or {})[key] or {})[1] == first.h and not cedric.E.Ranges.Contains(cedric.E.data.exported[key], 1),
		"Cedric back with the receipt: A aside (provisional), he fetches B too")
	-- The exporter reads both saved files: B from a disk; 1 is in done now.
	exporter.Read(doraSaved)
	receipt = exporter.Read(Stop(cedric))
	check(receipt.done[key] == "1" and receipt.early[key] == "" and exporter.archive[key][1][first.h] == false and exporter.archive[key][1][second.h],
		"the exporter has both pages 1 (A only early, B from a disk)")
	Stop(anna)
	Stop(bob)
end

-- Anna's page 1 (A) is safe at Dora. Then her WTF folder comes back from a backup (page 1 open again)
-- while Dora is away, and she closes another page 1 (B). early: Cedric (collecting, this build) is
-- online and takes B early (it went only early: o = 2), then his game crashes before it saved B. Dora
-- back: what she holds and her summary say 1 is taken: B is another page. It moves to a new number,
-- isn't dropped, and reaches Dora under it after Anna's /reload: both pages are kept.
local function Restored(early)
	local people = { ANNA, CEDRIC, DORA }
	local dora = Start(DORA, { friends = FriendsOf(DORA, people), collect = true })
	local anna = Start(ANNA, { friends = FriendsOf(ANNA, people) })
	Run(5)
	anna = Reload(anna)
	local backup = anna.opts.saved
	local key = ANNA.acct .. "." .. anna.E.data.store
	local function Got(c, n)
		return (c.E.data.inbox[key] or {})[n]
	end
	local function Under(h)
		for n, page in pairs(anna.E.data.mine) do
			if page.h == h then
				return n
			end
		end
	end
	Varied(anna, 7)
	Run(1)
	local A = anna.E.data.mine[1]
	check(A and Run(120, function() return Got(dora, 1) ~= nil end), "page 1 (A) goes early to Dora")
	anna = Reload(anna)
	check(Run(120, function() return Got(dora, 1).p == nil end), "after Anna's /reload it's confirmed")
	dora = Reload(dora)
	check(Run(120, function() return anna.E.data.mine[1] == nil end), "safe at Dora's next session: Anna drops A")
	local doraSaved = Stop(dora)
	Stop(anna)
	Run(70)
	local cedric = early and Start(CEDRIC, { friends = FriendsOf(CEDRIC, people), collect = true }) or nil
	anna = Start(ANNA, { friends = FriendsOf(ANNA, people), saved = backup })
	Run(10)
	check(anna.E.data.open and anna.E.data.open.n == 1, "the backup: her page 1 goes on")
	Varied(anna, 8)
	Run(1)
	local B = anna.E.data.mine[1]
	check(B and B.h ~= A.h, "another page 1 (B) closes")
	if cedric then
		check(Run(120, function() return Got(cedric, 1) ~= nil end) and Got(cedric, 1).p == 1 and B.o == 2,
			"B goes early to Cedric (provisional there; at Anna it went only early: o = 2)")
		Run(65)
		check(anna.E.data.mine[1] == B and anna.D.Ranges.Has(anna.D.peers[CEDRIC.id].holdings[key] or {}, 1),
			"Cedric tells Anna he holds 1 (his provisional B): it stays")
	else
		Run(120)
	end
	dora = Start(DORA, { friends = FriendsOf(DORA, people), saved = doraSaved })
	check(Run(120, function() return anna.E.data.mine[1] == nil end), "Dora back: Anna hears 1 is taken")
	local moved = Under(B.h)
	check(moved and moved > 1 and anna.E.data.mine[moved].o == 0, "B moved to a new number (" .. tostring(moved) .. ", nothing of it out"
		.. " under it), not dropped")
	if cedric then
		Stop(cedric, false, true) -- (his game crashes: his early copy of B is lost)
		Run(5)
	end
	anna = Reload(anna)
	check(Run(300, function()
		local page = Got(dora, moved)
		return page ~= nil and page.h == B.h and page.p == nil
	end), "after her /reload B reaches Dora under its new number (from her disk, or early and then confirmed)")
	dora = Reload(dora)
	check(Run(120, function() return Under(B.h) == nil end) and Got(dora, 1).h == A.h and Got(dora, moved).h == B.h,
		"safe at Dora's next session: Anna drops it; Dora has both pages, A as 1 and B as " .. moved)
	Stop(anna)
	Stop(dora)
end

section("Echoes' delivery: a WTF folder restored, the collector of the old page away")
Restored(false)

section("Echoes' delivery: a WTF folder restored, the new page went early to a collector who then crashes")
Restored(true)

section("Echoes' delivery: a page that went only early, checked after the author's /reload")
do
	-- Eve's pages 702-705 close this session (not on her disk yet) and go early to Anna (collecting,
	-- this build): they went only early (o = 2). After Eve's /reload Anna checks them: the start of
	-- each from Eve's disk is all she needs to confirm her copy, and her check usually stops before
	-- any part goes. A start that went to a collector who takes pages early, or who said she holds
	-- that number (her es; an author who doesn't relay hears none), makes the page out (o = 1), and
	-- so does a part: her summary drops them later, none is moved. A start alone to a relay (it
	-- holds nothing then): still only early.
	local c = Start(EVE, { friends = { ANNA, BOB }, fake = true })
	local key = EVE.acct .. "." .. c.E.data.store
	c.E.data.n = 1000 -- (the client's own pages: 1 and from 1001 on)
	for n = 702, 706 do
		local z = Data(720, n)
		c.E.data.mine[n] = { t = c.env.GetServerTime() - 60, h = Hash32(z), m = "z", z = z, s = c.E.data.session, o = 0 }
	end
	Touched(c)
	MeetAll(c, { ANNA }, "cers")
	MeetAll(c, { BOB }, "rs")
	local mark = Mark(c)
	for n = 702, 706 do
		Ask(c, ANNA, n)
		Pass(c, 4)
	end
	local only = true
	for n = 702, 706 do
		only = only and c.E.data.mine[n].o == 2
	end
	check(only and #Sent(c, ANNA, mark, "B2;ep;") == 15, "702-706 went early to Anna: only early (o = 2)")
	Say(c, ANNA, "B2;es;" .. key .. ":702-706")
	Pass(c, 1.5)
	check(c.E.data.mine[702] and c.E.data.mine[703] and c.E.data.mine[704] and c.E.data.mine[705] and c.E.data.mine[706],
		"Anna holds them (provisionally, she says): nothing moves")
	-- Bob (a relay: only pages from a disk) holds a page 706 of mine: another page (my WTF folder
	-- copied?). Mine moves before it goes out under that number.
	local p706 = c.E.data.mine[706]
	Say(c, BOB, "B2;es;" .. key .. ":706")
	Pass(c, 1.5)
	check(not c.E.data.mine[706] and c.E.data.mine[c.E.data.top] == p706 and p706.o == 0, "Bob's holdings have 706: mine moves (to "
		.. tostring(c.E.data.top) .. ")")
	c = Reload(c)
	MeetAll(c, { ANNA }, "cers")
	MeetAll(c, { BOB }, "rs")
	Say(c, ANNA, "B2;es;" .. key .. ":702") -- (her provisional copies: only 702 told yet)
	Pass(c, 1.5)
	-- f's request for n, stopped once its start went (part: once a part went too). A page I don't have
	-- asked first: its en, then the start, and nothing more may go to them for a second.
	local function Check(f, n, part)
		local page = c.E.data.mine[n]
		local from = Mark(c)
		Ask(c, f, 999)
		Ask(c, f, n)
		for _ = 1, 100 do
			Pass(c, 0.05)
			if #Sent(c, f, from, part and "B2;ep;" or "B2;eb;") > 0 then
				break
			end
		end
		Say(c, f, ("B2;eq;%s;%s;%d;%d"):format(EVE.acct, c.E.data.store, n, #page.z))
		Pass(c, 3)
		return #Sent(c, f, from, "B2;eb;"), #Sent(c, f, from, "B2;ep;"), page
	end
	local eb, ep, p702 = Check(ANNA, 702)
	check(eb == 1 and ep == 0 and p702.o == 1, ("702: its start alone (%d start, %d parts) to Anna, who said she holds it: out (o = 1)"):format(eb, ep))
	local p703
	eb, ep, p703 = Check(ANNA, 703)
	check(eb == 1 and ep == 0 and p703.o == 1, "703: its start alone to Anna, who takes pages early (she hadn't said she holds it): out")
	local p704
	eb, ep, p704 = Check(ANNA, 704, true)
	check(eb == 1 and ep >= 1 and p704.o == 1, ("704: a part went too (%d): out"):format(ep))
	local p705
	eb, ep, p705 = Check(BOB, 705)
	check(eb == 1 and ep == 0 and p705.o == 2, "705: its start alone to Bob (a relay): still only early (o = 2)")
	eb, ep = Check(BOB, 705, true)
	check(ep >= 1 and p705.o == 1, "Bob asks again, a part goes: out (from 2)")
	-- Her summary (confirmed, on her disk at her next session): they go, none moved.
	local function Under(h)
		for n, page in pairs(c.E.data.mine) do
			if page.h == h then
				return n
			end
		end
	end
	Say(c, ANNA, ("B2;ed;%s;%s;%s:702-705"):format(ANNA.acct, ANNA.store, key))
	Pass(c, 1.5)
	check(not (Under(p702.h) or Under(p703.h) or Under(p704.h) or Under(p705.h)), "safe at Anna: 702-705 go (none moved)")
	Stop(c)
end

section("Echoes' delivery: a collector's crash right after receiving")
do
	-- Cedric gets a page of Anna's from her disk and one early; his game crashes before it saved
	-- them. Neither was safe at him (they came this session), so Anna still has both: they reach him
	-- again in his next session.
	local cedric = Start(CEDRIC, { friends = { ANNA }, collect = true })
	local anna = Start(ANNA, { friends = { CEDRIC } })
	Run(5)
	cedric = Reload(cedric) -- (his last save)
	local save = cedric.opts.saved
	local key = ANNA.acct .. "." .. anna.E.data.store
	local function Got(n)
		return (cedric.E.data.inbox[key] or {})[n]
	end
	local disk = MyPage(anna, 101, 2400)
	Varied(anna, 5)
	Run(1)
	local n = anna.E.data.n
	local early = anna.E.data.mine[n]
	check(n > 1000 and early and Run(300, function() return Got(101) and Got(n) end) and Got(101).p == nil and Got(n).p == 1,
		"Cedric gets both: 101 from her disk, " .. n .. " early (provisional)")
	Stop(cedric, false, true) -- (his game crashes: nothing saved)
	Run(30)
	check(anna.E.data.mine[101] == disk and anna.E.data.mine[n] == early, "Anna still has both (neither was safe at him)")
	cedric = Start(CEDRIC, { friends = { ANNA }, saved = save })
	check(not Got(101) and not Got(n), "his next session, from his last save: neither is there")
	check(Run(300, function() return Got(101) and Got(n) end) and Got(101).z == disk.z and Got(n).z == early.z, "both reach him again")
	Stop(cedric)
	Stop(anna)
end

section("Echoes' delivery: early pages and older builds (the author's side)")
do
	-- Eve has page 701 on her disk, 702 not yet (closed this session). Dora collects on an older build
	-- (no e in her hello): no ea; 702 is en to her; 701 goes as ever. Anna collects on this build (e):
	-- ea, and 702 goes to her. Bob relays: no ea, en.
	local c = Start(EVE, { friends = { ANNA, BOB, DORA }, fake = true })
	local key = EVE.acct .. "." .. c.E.data.store
	MyPage(c, 701, 480)
	local z = Data(720, 702)
	c.E.data.mine[702] = { t = c.env.GetServerTime() - 60, h = Hash32(z), m = "z", z = z, s = c.E.data.session, o = 0 }
	Touched(c)
	local mark = Mark(c)
	MeetAll(c, { DORA }, "crs")
	MeetAll(c, { ANNA }, "cers")
	MeetAll(c, { BOB }, "rs")
	Pass(c, 65)
	local ea = Sent(c, ANNA, mark, "B2;ea;")
	check(#ea == 1 and ea[1] == "B2;ea;" .. key .. ":702" and #Sent(c, DORA, mark, "B2;ea;") == 0 and #Sent(c, BOB, mark, "B2;ea;") == 0,
		"ea only to Anna (collects, this build): 702; none to Dora (an older collector) or Bob (a relay), got " .. tostring(ea[1]))
	local es = Sent(c, DORA, mark, "B2;es;")
	check(es[1] == "B2;es;" .. key .. ":701" and Sent(c, ANNA, mark, "B2;es;")[1] == es[1], "es as ever, to both: 701 (on disk), got " .. tostring(es[1]))
	check(c.D.peers[ANNA.id].early and not c.D.peers[DORA.id].early and c.D.EarlyTaker(), "Anna takes pages early (Dora doesn't): one is online")
	mark = Mark(c)
	Ask(c, DORA, 702)
	Ask(c, BOB, 702)
	Pass(c, 2)
	check(#Sent(c, DORA, mark, "B2;en;") == 1 and #Sent(c, BOB, mark, "B2;en;") == 1 and #Sent(c, DORA, mark, "B2;eb;") == 0,
		"702 asked for by Dora and Bob: en, as for a page I don't have")
	mark = Mark(c)
	Ask(c, DORA, 701)
	Ask(c, ANNA, 702)
	Pass(c, 6)
	check(Received(c, DORA, mark) == c.E.data.mine[701].z and Received(c, ANNA, mark) == z and c.E.data.mine[702].o == 2,
		"701 goes to Dora as ever; 702 to Anna (it went only early: o = 2)")
	-- Anna stops collecting (her hello without c and e): nothing early to her any more.
	Hello(c, ANNA, "rsa")
	mark = Mark(c)
	Ask(c, ANNA, 702)
	Pass(c, 2)
	check(#Sent(c, ANNA, mark, "B2;en;") == 1 and not c.D.EarlyTaker(), "Anna no longer collects: 702 is en to her; nobody takes pages early")
	Stop(c)
end

section("Echoes' delivery: a collector's provisional pages (ea, checks)")
do
	-- Dora collects. Anna (an author, relaying) offers her own page 5 early (ea): kept provisional. It
	-- isn't served, Bob doesn't hear of it, Anna does. Bob's copy of page 5 from a disk shows another
	-- hash: stopped, not asked again this session. Page 6: Anna's from her disk shows the same hash:
	-- confirmed by its start alone.
	local c = Start(DORA, { friends = { ANNA, BOB }, fake = true, collect = true })
	local D = c.D
	MeetAll(c, { ANNA, BOB }, "rs")
	local mark = Mark(c)
	Say(c, ANNA, ("B2;ea;%s:5/%s:1-3"):format(ANNA.key, BOB.key))
	Pass(c, 1.5)
	local asked = Sent(c, ANNA, mark, "B2;eq;")
	check(#asked == 1 and asked[1] == ("B2;eq;%s;%s;5;0"):format(ANNA.acct, ANNA.store) and not D.peers[ANNA.id].earlyHoldings[BOB.key]
		and D.inflight[ANNA.key .. ".5"].early, "Anna's own page 5 asked for (early); the item of Bob's key ignored, got " .. tostring(asked[1]))
	local p5 = TheirPage(c, 5, 600)
	mark = Mark(c)
	SendPage(c, ANNA, ANNA, p5, 3)
	Pass(c, 1.5)
	local got = c.E.data.inbox[ANNA.key] and c.E.data.inbox[ANNA.key][5]
	check(got and got.p == 1 and got.z == p5.z, "kept provisional (p): it came early")
	Say(c, BOB, ("B2;eq;%s;%s;5;0"):format(ANNA.acct, ANNA.store))
	Pass(c, 65)
	local toBob, toAnna = table.concat(Sent(c, BOB, mark, "B2;es;"), " "), table.concat(Sent(c, ANNA, mark, "B2;es;"), " ")
	check(#Sent(c, BOB, mark, "B2;en;") == 1 and not toBob:find(ANNA.key, 1, true) and toAnna:find(ANNA.key .. ":5", 1, true),
		"not served (en to Bob); told to Anna (her own), not to Bob, got \"" .. toAnna .. "\" and \"" .. toBob .. "\"")
	-- Bob's page 5 from a disk: a check; another hash: stopped.
	local other = TheirPage(c, 5, 600, 55)
	mark = Mark(c)
	Say(c, BOB, "B2;es;" .. ANNA.key .. ":5")
	Pass(c, 1.5)
	local r = D.inflight[ANNA.key .. ".5"]
	check(Sent(c, BOB, mark, "B2;eq;")[1] == ("B2;eq;%s;%s;5;0"):format(ANNA.acct, ANNA.store) and r and r.check, "a check: page 5 asked of Bob")
	Say(c, BOB, ("B2;eb;4;%s;%s;5;%d;%s;%d;z"):format(ANNA.acct, ANNA.store, other.len, other.h, other.t))
	Say(c, BOB, ("B2;ep;4;0;%s"):format(other.z:sub(1, 240)))
	Pass(c, 1.5)
	check(#Sent(c, BOB, mark, ("B2;eq;%s;%s;5;600"):format(ANNA.acct, ANNA.store)) == 1 and D.checked[ANNA.key][5] and got.p == 1 and got.z == p5.z
		and not D.inflight[ANNA.key .. ".5"] and not D.partials[ANNA.key .. ".5"], "another hash: stopped (from its end); page 5 stays provisional, as it was")
	Pass(c, 10)
	check(#Sent(c, BOB, mark, "B2;eq;") == 2, "not asked again this session")
	-- Page 6: early, then (her /reload) Anna's from her disk with the same hash.
	Say(c, ANNA, "B2;ea;" .. ANNA.key .. ":6")
	Pass(c, 1.5)
	local p6 = TheirPage(c, 6, 960)
	SendPage(c, ANNA, ANNA, p6, 5)
	Pass(c, 1.5)
	check(c.E.data.inbox[ANNA.key][6] and c.E.data.inbox[ANNA.key][6].p == 1, "(page 6 came early: provisional)")
	Hello(c, ANNA, "rs")
	mark = Mark(c)
	Say(c, ANNA, "B2;es;" .. ANNA.key .. ":6")
	Pass(c, 1.5)
	check(Sent(c, ANNA, mark, "B2;eq;")[1] == ("B2;eq;%s;%s;6;0"):format(ANNA.acct, ANNA.store), "a check of page 6")
	Say(c, ANNA, ("B2;eb;6;%s;%s;6;%d;%s;%d;z"):format(ANNA.acct, ANNA.store, p6.len, p6.h, p6.t))
	Pass(c, 1.5)
	check(c.E.data.inbox[ANNA.key][6].p == nil and #Sent(c, ANNA, mark, ("B2;eq;%s;%s;6;960"):format(ANNA.acct, ANNA.store)) == 1,
		"the same hash: confirmed by its start alone (stopped from its end)")
	-- Not collecting: what I tell Anna I hold no longer has her provisional page 5 (what a friend who
	-- doesn't collect holds is only ever from a disk), and an ea is ignored.
	mark = Mark(c)
	c.E.module.db.collect = false
	Pass(c, 3)
	local told = table.concat(Sent(c, ANNA, mark, "B2;es;"), " ")
	check(told:find(ANNA.key .. ":6", 1, true) and not told:find(ANNA.key .. ":5", 1, true), "not collecting: my es to Anna has 6, not her"
		.. " provisional 5, got " .. told)
	mark = Mark(c)
	Say(c, ANNA, "B2;ea;" .. ANNA.key .. ":7")
	Pass(c, 2)
	check(not D.Ranges.Has(D.peers[ANNA.id].earlyHoldings[ANNA.key] or {}, 7) and #Sent(c, ANNA, mark, ("B2;eq;%s;%s;7;"):format(ANNA.acct, ANNA.store)) == 0,
		"not collecting: an ea is ignored")
	Stop(c)
end
