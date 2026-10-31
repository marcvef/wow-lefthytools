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

-- What every client shares: Lua's libraries and whatever run.js gave the state (functions from JS).
local STD = { string = true, table = true, math = true, os = true, io = true, debug = true, coroutine = true, utf8 = true,
	package = true }
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
for _, p in ipairs({ ANNA, BOB, CEDRIC, DORA, EVE, FINN }) do
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
local function MyPage(c, n, len, m)
	local z = Data(len, n * 7919 + #c.who.name)
	local page = { t = c.env.GetServerTime() - 3600 + n * 60, h = Hash32(z), m = m or "z", z = z }
	c.E.data.mine[n] = page
	c.E.data.n = math.max(c.E.data.n, n)
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

local function Keys(t)
	local list = {}
	for k in pairs(t or {}) do
		list[#list + 1] = k
	end
	table.sort(list)
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
