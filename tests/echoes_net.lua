-- Echoes' delivery (Delivery.lua) and Beacon's B family: the messages, what friends hold and what's
-- safe, who gets B at all, serving within the budget, pulling, checks and resuming, relaying, dropping
-- copies once safe, switching off, the probe, and three clients (author, relay, collector) passing
-- pages between them.
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
local function Stop(c, reload)
	c.env.Fire("PLAYER_LOGOUT")
	local saved = {}
	for _, name in ipairs(SAVED) do
		saved[name] = Copy(c.env[name])
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
			world.log[#world.log + 1] = { from = c.who.id, to = m.id, data = m.data, at = world.time }
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
-- 1001 on, since E.data.n is set to 1000 here; the test's are 100 to 999.)
local function MyPage(c, n, len, m)
	local z = Data(len, n * 7919 + #c.who.name)
	local page = { t = c.env.GetServerTime() - 3600 + (n % 100) * 30, h = Hash32(z), m = m or "z", z = z }
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

	-- Full at 8 MB (until exported): nothing asked.
	mark = Mark(me)
	E.data.inbox[BOB.key] = { [1] = { t = 1, h = "00000000", m = "z", z = ("A"):rep(8 * 1024 * 1024), s = E.data.session } }
	Touched(me)
	Say(me, ANNA, "B2;es;" .. ANNA.key .. ":10")
	Pass(me, 5)
	check(E.Store.InboxFull() and #Sent(me, ANNA, mark, "B2;eq;") == 0, "the inbox at 8 MB: nothing more asked")
	E.data.inbox[BOB.key] = nil
	Touched(me)
	Pass(me, 2)
	check(#Sent(me, ANNA, mark, "B2;eq;") == 1, "below it again: asked")
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
	-- Anna has 1-200; Bob and Cedric hold 1-60 already: past the first 50 pages, 61 is the one.
	local mark = Mark(c)
	Say(c, BOB, "B2;es;" .. ANNA.key .. ":1-60")
	Say(c, CEDRIC, "B2;es;" .. ANNA.key .. ":1-60")
	Say(c, ANNA, "B2;es;" .. ANNA.key .. ":1-200")
	Pass(c, 1.5)
	local asked = Sent(c, ANNA, mark, "B2;eq;")
	check(#asked == 1 and asked[1]:find(";61;0$"), "pages 1-60 held by two others: 61 asked for, got " .. tostring(asked[1]))
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
