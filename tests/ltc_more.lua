-- LTC (Chat.lua, ChatMissed.lua, ChatCalls.lua): a line that mentions me (highlight, flashing, the
-- sound, the setting); lines a friend missed while offline (kept by the writer and by friends who got
-- them, passed on when they come online, shown once, marked with their time, only from their friends,
-- 24 hours, 50 per friend, paced); /ltc who <text> (the links, answers, the tally, Invite all, the end);
-- and friends on an older build, who get nothing but what their build reads.
--
-- Every client here is a game of its own, like in recipes.lua: mock.lua and the addon in an environment
-- of their own, with their own clock, Battle.net friends and saved variables.
-- Needs: no other file (its clients are its own; the suite's state is left alone).
local suite = ...
local check, section = suite.check, suite.section
local Hash32 = suite.LT.Hash32

---------------------------------------------------------------------------
-- The harness (as in recipes.lua)
---------------------------------------------------------------------------

local STD = { string = true, table = true, math = true, os = true, io = true, debug = true, coroutine = true, utf8 = true,
	package = true, C_EncodingUtil = true }
local BASE = { _VERSION = _VERSION }
for k, v in pairs(_G) do
	if STD[k] or (type(v) == "function" and debug.getinfo(v, "S").what ~= "Lua") then
		BASE[k] = v
	end
end
local BASE_META = { __index = BASE }

local NEW, OLD = "0.7.0-39-gabc1234", "0.7.0-24-gabc1234" -- a build that reads LTC's words, an older one
-- What an older build doesn't have (its client here runs without them).
local OLD_FILES = { ["Modules/Beacon/ChatMissed.lua"] = true, ["Modules/Beacon/ChatCalls.lua"] = true }
local SAVED = { "LefthyToolsDB", "LefthyToolsChronicleDB", "LefthyToolsBestiaryDB", "LefthyToolsEchoesDB" }

local function Person(id, name, class, tag)
	local first, surname = name:match("^(%S+) (%S+)$")
	return { id = id, name = name, first = first, surname = surname, class = class, tag = tag, guid = "Player-1-" .. id, acct = Hash32(tag:lower()) }
end
local ANNA = Person(11, "Anna Brook", "MAGE", "Annie#1234")
local BOB = Person(12, "Bob Stone", "WARRIOR", "Bobby#2345")
local CEDRIC = Person(13, "Cedric Vale", "ROGUE", "Cedric#3456")
local DORA = Person(14, "Dora Reed", "PRIEST", "Dora#4567") -- on an older build
local EVE = Person(15, "Eve Marsh", "DRUID", "Eve#5678") -- a friend of Bob's, not of Anna's

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

local world = { time = 0, list = {}, byId = {}, log = {} }

local function Account(p, online)
	return { gameAccountID = p.id, isOnline = online, clientProgram = "WoW", wowProjectID = 1, isInCurrentRegion = true,
		characterName = p.name, classFilename = p.class, characterLevel = 20, areaName = "Elwynn Forest", playerGuid = p.guid,
		isGameAFK = false, isGameBusy = false, realmName = "Realmy", factionName = "Alliance" }
end

-- A client starts. opts: friends, version (OLD: also without OLD_FILES), saved, fake (friends are played by the test).
local function Start(p, opts)
	opts = opts or {}
	local env = setmetatable({}, BASE_META)
	env._G = env
	assert(loadfile("tests/mock.lua", "t", env))()
	local printed = env.PRINTED
	env.print = function(...)
		printed[#printed + 1] = tostring((...))
	end
	env.geterrorhandler = function()
		return function(err)
			env.ERRORS[#env.ERRORS + 1] = tostring(err)
			io.write("    [" .. p.name .. "'s error handler] " .. tostring(err) .. "\n")
		end
	end
	if world.time > 0 then
		env.Advance(world.time, world.time)
	end
	env.MOCK_CLIENT, env.MOCK_BUILD = { beta = false, test = false, ptr = false }, "70532"
	env.MOCK_VERSION = opts.version or NEW
	env.MY_BATTLETAG, env.MY_GUID, env.PLAYER_CLASS = p.tag, p.guid, p.class
	local baseUnitName = env.UnitName
	env.UnitName = function(unit)
		if unit == "player" then
			return p.first, p.surname
		end
		return baseUnitName(unit)
	end
	env.FLASHES = 0
	env.FlashClientIcon = function() env.FLASHES = env.FLASHES + 1 end
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
	local old = opts.version == OLD
	for _, file in ipairs(SOURCES) do
		if not (old and OLD_FILES[file.name]) then
			assert(load(file.src, "@Interface/AddOns/LefthyTools/" .. file.name, "t", env))("LefthyTools", ns)
		end
	end
	ns.LT.LAUNCH_DAY = nil
	env.Fire("ADDON_LOADED", "LefthyTools")
	env.Fire("PLAYER_LOGIN")
	env.Fire("PLAYER_ENTERING_WORLD", true, false)
	local c = { who = p, env = env, ns = ns, B = ns.Beacon, LT = env.LefthyTools, opts = opts, read = 0, before = before, alive = {} }
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

-- The game closes: saved variables written (returned), friends see them go offline.
local function Stop(c)
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
	if world.byId[c.who.id] == c then
		world.byId[c.who.id] = nil
	end
	for _, other in ipairs(world.list) do
		for _, entry in ipairs(other.env.BN_FRIENDS) do
			if entry.battleTag == c.who.tag and entry[1].isOnline then
				entry[1].isOnline = false
				other.env.Fire("BN_FRIEND_ACCOUNT_OFFLINE")
			end
		end
	end
	return saved
end

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

-- Time passes for every client running, in steps, messages carried after each. until_(): stop early.
local function Run(seconds, until_)
	local t, step = 0, 0.2
	while t < seconds - 1e-9 do
		for _, c in ipairs(world.list) do
			c.env.Advance(step, step)
		end
		world.time, t = world.time + step, t + step
		Deliver()
		if until_ and until_() then
			return true
		end
	end
	return until_ == nil
end

-- One client alone, with friends the test plays.
local function Say(c, f, text)
	c.env.Fire("BN_CHAT_MSG_ADDON", "LTBeacon", text, "WHISPER", f.id)
end
local function Pass(c, seconds)
	local t, step = 0, 0.25
	while t < seconds - 1e-9 do
		c.env.Advance(step, step)
		t = t + step
	end
end

local function Set(c, key, value)
	c.env.LefthyTools.Options.registered["LefthyTools_beacon_" .. key]:SetValue(value)
end

-- What a client printed since mark (#PRINTED + 1 then) that has every one of the words in it.
local function PrintedSince(c, mark, ...)
	local list = {}
	for i = mark, #c.env.PRINTED do
		local line, all = c.env.PRINTED[i], true
		for k = 1, select("#", ...) do
			all = all and line:find((select(k, ...)), 1, true) ~= nil
		end
		if all then
			list[#list + 1] = line
		end
	end
	return list
end
local function Mark(c)
	return #c.env.PRINTED + 1
end

-- Messages in the world's log since from (#world.log + 1 then): to, from (nil: anyone), starting with prefix.
local function Logged(from, to, sender, prefix)
	local list = {}
	for i = from, #world.log do
		local m = world.log[i]
		if m.to == to.id and (not sender or m.from == sender.id) and m.data:sub(1, #prefix) == prefix then
			list[#list + 1] = m
		end
	end
	return list
end

-- The lines a client keeps for a friend.
local function HeldFor(c, p)
	local list = {}
	for _, line in ipairs(c.env.LefthyToolsDB.ltcHeld or {}) do
		if line.f[p.acct] then
			list[#list + 1] = line
		end
	end
	return list
end

local function Line(c, text)
	c.env.SlashCmdList.LEFTHYTOOLS_CHAT(text)
end

---------------------------------------------------------------------------
section("LTC: a line that mentions me")
---------------------------------------------------------------------------
do
	local me = Start(ANNA, { friends = { BOB }, fake = true })
	local env = me.env
	Say(me, BOB, "H2")
	Say(me, BOB, "V2;" .. NEW)
	Pass(me, 1.5)
	check(env.LefthyToolsDB.settings.beacon.lefthyChatMentions == true and env.LefthyTools.Options.registered["LefthyTools_beacon_lefthyChatMentions"],
		"on by default, with a checkbox")
	local mark, sounds = Mark(me), #env.SOUNDS
	Say(me, BOB, "M2;hey anna, ready?")
	Pass(me, 0.5)
	local got = PrintedSince(me, mark, "]: hey ")
	check(got[1] and got[1]:find("hey |cffffffffanna|r|cffffb84d, ready?", 1, true), "my name stands out, whatever its case, got " .. tostring(got[1]))
	check(env.FLASHES == 1 and #env.SOUNDS == sounds + 1 and env.SOUNDS[#env.SOUNDS] == 826, "the taskbar icon flashes and LTC's sound plays")
	-- Right after it, another one: the sound waits 1.5 s, the flash doesn't.
	Say(me, BOB, "M2;Annie, you there?")
	Pass(me, 0.5)
	got = PrintedSince(me, mark, "you there?")
	check(got[1] and got[1]:find("|cffffffffAnnie|r", 1, true) and env.FLASHES == 2 and #env.SOUNDS == sounds + 1,
		"my BattleTag's name too; a second one within 1.5 s flashes but plays no second sound")
	Pass(me, 1.5)
	-- A plain line just ticked: a mention still plays.
	Say(me, BOB, "M2;ok")
	Pass(me, 0.3)
	sounds = #env.SOUNDS
	Say(me, BOB, "M2;anna!")
	Pass(me, 0.3)
	check(#env.SOUNDS == sounds + 1 and env.FLASHES == 3, "a mention plays even right after a plain line's tick")
	mark = Mark(me)
	local flashes = env.FLASHES
	Pass(me, 2)
	Say(me, BOB, "M2;Annabelle and Joanna came, and Anna's {quest:176:10[Anna's Errand]ffff00} too")
	Pass(me, 0.5)
	got = PrintedSince(me, mark, "Annabelle")
	check(got[1] and not got[1]:find("|cffffffffAnnabelle", 1, true) and not got[1]:find("Jo|cffffffff", 1, true)
		and got[1]:find("|cffffffffAnna|r|cffffb84d's", 1, true) and got[1]:find("|h[Anna's Errand]|h", 1, true),
		"only a word of its own counts, and a link's text is left alone, got " .. tostring(got[1]))
	check(env.FLASHES == flashes + 1, "and it flashes once")
	-- A tab of its own for LTC, out of sight: it flashes (as for any line).
	local added, alerted = {}, {}
	env.ChatFrame2.AddMessage = function(_, line) added[#added + 1] = line end
	env.ChatFrame2.GetID = function() return 2 end
	env.ChatFrame2:Hide()
	env.FCF_StartAlertFlash = function(frame) alerted[#alerted + 1] = frame end
	env.LefthyToolsDB.ltcTabs = { [ANNA.guid] = { [2] = true } }
	Pass(me, 2)
	Say(me, BOB, "M2;anna, look at tab 2")
	Pass(me, 0.5)
	check(added[1] and added[1]:find("|cffffffffanna|r", 1, true) and alerted[1] == env.ChatFrame2, "LTC's tab out of sight flashes")
	env.LefthyToolsDB.ltcTabs = nil
	-- My own line with my name: nothing.
	flashes = env.FLASHES
	Line(me, "Anna here")
	Pass(me, 0.5)
	check(env.FLASHES == flashes, "my own line is no mention")
	-- Switched off: plain lines.
	Set(me, "lefthyChatMentions", false)
	mark, flashes = Mark(me), env.FLASHES
	Pass(me, 2)
	Say(me, BOB, "M2;anna?")
	Pass(me, 0.5)
	got = PrintedSince(me, mark, "]: anna?")
	check(got[1] and not got[1]:find("|cffffffff", 1, true) and env.FLASHES == flashes, "switched off: no highlight, no flash")
	Set(me, "lefthyChatMentions", true)
	env.FCF_StartAlertFlash = nil
	Leftovers(me)
end

---------------------------------------------------------------------------
section("LTC: lines a friend missed while offline")
---------------------------------------------------------------------------
do
	world.time = 1000
	-- Anna: a friend of Bob's, Cedric's and Dora's (older build). Bob: also of Eve's, who isn't Anna's friend.
	local a = Start(ANNA, { friends = { BOB, CEDRIC, DORA } })
	local b = Start(BOB, { friends = { ANNA, CEDRIC, EVE } })
	local c = Start(CEDRIC, { friends = { ANNA, BOB } })
	local e = Start(EVE, { friends = { BOB } })
	Run(15)
	local known = a.env.LefthyToolsDB.ltcFriends or {}
	check(known[BOB.acct] and known[CEDRIC.acct] and not known[EVE.acct], "friends on a build that reads them are known, got "
		.. tostring(known[BOB.acct]) .. "/" .. tostring(known[CEDRIC.acct]))
	check(#(a.env.LefthyToolsDB.ltcHeld or {}) == 0, "everyone online: nothing kept")

	-- Cedric and Eve go offline; Dora comes, on an older build.
	local savedC, savedE = Stop(c), Stop(e)
	local d = Start(DORA, { friends = { ANNA }, version = OLD })
	Run(10)
	local from = #world.log + 1
	local wroteAt = a.env.GetServerTime()
	Line(a, "first line")
	Line(a, "second, with {item:1155}")
	Line(a, "third")
	Run(1)
	Line(b, "Bob was here")
	Run(3)
	local forC = HeldFor(a, CEDRIC)
	check(#forC == 4 and forC[1].x == "first line" and forC[1].t == wroteAt and forC[1].n == "Anna Brook" and forC[1].c == "MAGE",
		"the writer keeps her lines for a friend who's offline, got " .. #forC)
	check(forC[4] and forC[4].a == BOB.acct and forC[4].n == "Bob Stone" and forC[4].c == "WARRIOR", "and Bob's, which she got")
	check(#HeldFor(a, DORA) == 0 and #HeldFor(a, EVE) == 0, "not for a friend never seen on a build that reads them, nor for someone not her friend")
	check(#HeldFor(b, CEDRIC) == 4 and #HeldFor(b, EVE) == 4 and HeldFor(b, CEDRIC)[1].a == ANNA.acct,
		"a friend who got them keeps them too (his own as well), for each of his friends offline")
	local toDora = Logged(from, DORA, nil, "M2;")
	check(#toDora == 3 and toDora[1].data == "M2;first line", "Dora, on an older build, gets the lines live as ever")
	local bad = {}
	for _, m in ipairs(world.log) do
		if m.to == DORA.id and m.data:find("^B2;b") and not m.data:find("^B2;bl;") then
			bad[#bad + 1] = m.data
		end
	end
	check(#bad == 0, "and never one of LTC's new words, got " .. table.concat(bad, " | "))

	-- Anna goes offline; Cedric comes back: Bob passes on her lines and his.
	local savedA = Stop(a)
	Run(3)
	c = Start(CEDRIC, { friends = { ANNA, BOB }, saved = savedC })
	from = #world.log + 1
	local mark = Mark(c)
	Run(30)
	local missed = PrintedSince(c, mark, "(missed, ")
	check(#missed == 4, "all four arrive, from Bob while Anna's away, got " .. #missed)
	local clock = c.env.date("%H:%M", wroteAt)
	check(missed[1] and missed[1]:find("(missed, " .. clock .. ")", 1, true) and missed[1]:find("Anna Brook", 1, true)
		and missed[1]:find("first line", 1, true), "marked as missed, with the time it was written, under its writer's name, got " .. tostring(missed[1]))
	check(missed[2] and missed[2]:find("second, with |cnIQ3:|Hitem:1155:", 1, true) and missed[2]:find("[Rod of the Sleepwalker]|h", 1, true), "links come back as links, got " .. tostring(missed[2]))
	check(missed[4] and missed[4]:find("Bob was here", 1, true), "in the order they were written")
	local lines = Logged(from, CEDRIC, BOB, "B2;bm;")
	local paced = true
	for i = 2, #lines do
		paced = paced and lines[i].at - lines[i - 1].at >= 0.4
	end
	check(#lines == 4 and paced, "one every half second, got " .. #lines)
	check(#Logged(from, BOB, CEDRIC, "B2;bq;") == 1 and #Logged(from, CEDRIC, BOB, "B2;bo;") == 1, "after an offer and its answer")
	check(#HeldFor(b, CEDRIC) == 0, "then Bob forgets them for him")

	-- Anna comes back: she still has them for him. They go, and aren't shown again.
	local a2 = Start(ANNA, { friends = { BOB, CEDRIC, DORA }, saved = savedA })
	from, mark = #world.log + 1, Mark(c)
	Run(20)
	check(#Logged(from, CEDRIC, ANNA, "B2;bm;") == 4 and #PrintedSince(c, mark, "(missed, ") == 0,
		"the same lines from their writer (and Bob's from her): shown once, got " .. #Logged(from, CEDRIC, ANNA, "B2;bm;"))
	check(#HeldFor(a2, CEDRIC) == 0, "and she forgets them for him")

	-- Eve comes: Bob's line she gets, Anna's not (Anna isn't her friend).
	e = Start(EVE, { friends = { BOB }, saved = savedE })
	mark = Mark(e)
	Run(20)
	missed = PrintedSince(e, mark, "(missed, ")
	check(#missed == 1 and missed[1]:find("Bob was here", 1, true), "only her friends' lines reach her, got " .. #missed)
	check(#HeldFor(b, EVE) == 0, "Bob forgets the rest for her: she won't take them")

	-- A lot while she's away: the newest 50, paced.
	Stop(e)
	Run(3)
	for i = 1, 55 do
		b.B.LTCHold("line " .. i)
	end
	check(#HeldFor(b, EVE) == 50 and HeldFor(b, EVE)[1].x == "line 6", "at most 50 lines per friend: the oldest go, got " .. #HeldFor(b, EVE))
	e = Start(EVE, { friends = { BOB }, saved = savedE })
	from, mark = #world.log + 1, Mark(e)
	Run(40)
	lines = Logged(from, EVE, BOB, "B2;bm;")
	local most = 0
	for i = 1, #lines do
		local n = 0
		for k = i, #lines do
			if lines[k].at - lines[i].at < 60 then
				n = n + 1
			end
		end
		most = math.max(most, n)
	end
	check(#PrintedSince(e, mark, "(missed, ") == 50 and most <= 80, "all 50 come, within what she takes in a minute, got "
		.. #PrintedSince(e, mark, "(missed, "))
	local all = PrintedSince(e, mark, "(missed, ")
	check(all[1] and all[1]:find("]: line 6|r", 1, true) and all[50] and all[50]:find("]: line 55|r", 1, true), "oldest first")

	-- Cedric logs in on an older build: nothing new goes to him, and Anna keeps them for later.
	Stop(c)
	Run(3)
	Line(a2, "for later")
	Run(2)
	from = #world.log + 1
	local oldC = Start(CEDRIC, { friends = { ANNA, BOB }, saved = savedC, version = OLD })
	Run(15)
	check(#Logged(from, CEDRIC, nil, "B2;b") - #Logged(from, CEDRIC, nil, "B2;bl;") == 0, "an older build: no offer, no line")
	check(#HeldFor(a2, CEDRIC) == 1, "kept for when he updates")
	Stop(oldC)
	Run(3)

	-- A line older than 24 hours isn't passed on; yesterday's says so.
	Line(a2, "too old")
	Line(a2, "from yesterday")
	Run(2)
	for _, holder in ipairs({ a2, b }) do -- (Bob keeps them too)
		for _, kept in ipairs(HeldFor(holder, CEDRIC)) do
			kept.t = kept.t - (kept.x == "too old" and 25 * 3600 or kept.x == "from yesterday" and 20 * 3600 or 0)
		end
	end
	c = Start(CEDRIC, { friends = { ANNA, BOB }, saved = savedC })
	mark = Mark(c)
	Run(20)
	missed = PrintedSince(c, mark, "(missed, ")
	check(#missed == 2 and missed[1]:find("for later", 1, true) and missed[2]:find("(missed, yesterday ", 1, true)
		and missed[2]:find("from yesterday", 1, true), "updated, he gets them; one from the day before says so; too old: not at all, got " .. #missed)

	-- Switched off (him): nothing answered, so Anna keeps them.
	Set(c, "lefthyChatMissed", false)
	Stop(c)
	Run(3)
	savedC = nil
	Line(a2, "while he's off")
	Run(2)
	c = Start(CEDRIC, { friends = { ANNA, BOB } })
	Set(c, "lefthyChatMissed", false)
	mark = Mark(c)
	Run(15)
	check(#PrintedSince(c, mark, "(missed, ") == 0 and #HeldFor(a2, CEDRIC) == 1, "his setting off: nothing shown, and she keeps the line")
	for _, client in ipairs({ a2, b, c, d, e }) do
		Stop(client)
	end
end

---------------------------------------------------------------------------
section("LTC: who's in")
---------------------------------------------------------------------------
do
	world.time = world.time + 100
	local a = Start(ANNA, { friends = { BOB, CEDRIC, DORA } })
	local b = Start(BOB, { friends = { ANNA, CEDRIC } })
	local c = Start(CEDRIC, { friends = { ANNA, BOB } })
	local d = Start(DORA, { friends = { ANNA }, version = OLD })
	-- Anna's main window can redraw a line, like the game's.
	local window = {}
	a.env.ChatFrame1.GetID = function() return 1 end
	a.env.ChatFrame1.AddMessage = function(_, line) window[#window + 1] = line end
	local function transform(_, matches, change)
		for i, line in ipairs(window) do
			if matches(line, 1, 1, 1) then
				window[i] = change(line, 1, 1, 1)
			end
		end
	end
	a.env.ChatFrame1.TransformMessages = transform
	a.env.LefthyToolsDB.ltcTabs = { [ANNA.guid] = { [1] = true } }
	Run(15)
	local from, markB, markD = #world.log + 1, Mark(b), Mark(d)
	a.env.SlashCmdList.LEFTHYTOOLS_LTC("who Deadmines at 8?")
	Run(2)
	check(Logged(from, BOB, ANNA, "B2;bw;")[1] and Logged(from, BOB, ANNA, "B2;bw;")[1].data == "B2;bw;1;Deadmines at 8?", "the call goes to friends on a new build")
	local toD = Logged(from, DORA, ANNA, "")
	check(#toD == 1 and toD[1].data == "M2;Who's in? Deadmines at 8?", "an older build gets a plain LTC line, got " .. tostring(toD[1] and toD[1].data))
	check(PrintedSince(d, markD, "Anna Brook", "]: Who's in? Deadmines at 8?")[1] ~= nil, "and shows it as one")
	local line = PrintedSince(b, markB, "Who's in? Deadmines at 8?")[1]
	local yes = line and line:match("|H(addon:lefthytools:who:in:[%d:]+)|h%[I'm in%]|h")
	local no = line and line:match("|H(addon:lefthytools:who:out:[%d:]+)|h%[Not now%]|h")
	check(yes and no, "Bob's line has I'm in and Not now, got " .. tostring(line))
	check(window[1] and window[1]:find("]: Who's in? Deadmines at 8?", 1, true) and window[2] and window[2]:find("no answers yet", 1, true)
		and window[2]:find("[Invite all]", 1, true), "Anna: her line and the tally under it")

	-- Bob's in.
	markB = Mark(b)
	b.env.EventRegistry:TriggerEvent("SetItemRef", yes, "[I'm in]", "LeftButton")
	Run(2)
	check(PrintedSince(b, markB, "You told Anna Brook you're in.")[1] ~= nil, "Bob is told what he said")
	check(#window == 2 and window[2]:find("1 in (Bob Stone)", 1, true), "the tally changes in place, got " .. tostring(window[2]))
	-- Cedric isn't; then Bob changes his mind; then again.
	local cLine = PrintedSince(c, 1, "Who's in? Deadmines")[1]
	c.env.EventRegistry:TriggerEvent("SetItemRef", cLine:match("|H(addon:lefthytools:who:out:[%d:]+)|h"), "[Not now]", "LeftButton")
	Run(2)
	check(window[2]:find("1 in (Bob Stone), 1 not now (Cedric Vale)", 1, true), "both, got " .. window[2])
	b.env.EventRegistry:TriggerEvent("SetItemRef", no, "[Not now]", "LeftButton")
	Run(2)
	check(window[2]:find("2 not now (Bob Stone, Cedric Vale)", 1, true), "the last answer counts, got " .. window[2])
	b.env.EventRegistry:TriggerEvent("SetItemRef", yes, "[I'm in]", "LeftButton")
	Run(2)
	-- Someone who wasn't asked, an answer to another call: nothing.
	a.env.Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "B2;ba;1;1", "WHISPER", DORA.id)
	a.env.Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "B2;ba;7;1", "WHISPER", CEDRIC.id)
	Run(2)
	check(window[2]:find("1 in (Bob Stone), 1 not now (Cedric Vale)", 1, true), "answers from someone not asked, or to no call: left out, got " .. window[2])

	-- Invite all: those who are in, from the click.
	check(#a.env.INVITES == 0, "nobody invited before the click")
	a.env.EventRegistry:TriggerEvent("SetItemRef", window[2]:match("|H(addon:lefthytools:who:all:[%d:]+)|h"), "[Invite all]", "LeftButton")
	Run(1)
	check(#a.env.INVITES == 1 and a.env.INVITES[1] == BOB.id and window[3] and window[3]:find("Invited Bob Stone.", 1, true),
		"Invite all invites who's in, and says so")
	a.B.peers[BOB.id].groupUnit = "party1"
	a.env.EventRegistry:TriggerEvent("SetItemRef", window[2]:match("|H(addon:lefthytools:who:all:[%d:]+)|h"), "[Invite all]", "LeftButton")
	Run(1)
	check(#a.env.INVITES == 1 and window[4] and window[4]:find("Nobody to invite", 1, true), "not someone already in my group")
	a.B.peers[BOB.id].groupUnit = nil

	-- Mentions in a call work too; a missed call comes as a plain line.
	Stop(d)
	local savedC = Stop(c)
	Run(3)
	a.env.SlashCmdList.LEFTHYTOOLS_LTC("who RFC, Bob?")
	Run(2)
	check(b.env.FLASHES >= 1, "a call with my name in it: a mention")
	-- The tally scrolled away (a window that can't redraw it): a new line.
	a.env.ChatFrame1.TransformMessages = nil
	local count = #window
	b.env.EventRegistry:TriggerEvent("SetItemRef", PrintedSince(b, 1, "RFC, ")[1]:match("|H(addon:lefthytools:who:in:[%d:]+)|h"), "[I'm in]", "LeftButton")
	Run(2)
	check(#window == count + 1 and window[#window]:find("Who's in? RFC, Bob?: 1 in (Bob Stone)", 1, true), "a window that can't redraw: a new tally line")
	c = Start(CEDRIC, { friends = { ANNA, BOB }, saved = savedC })
	local markC = Mark(c)
	Run(20)
	local missed = PrintedSince(c, markC, "(missed, ")
	check(#missed == 1 and missed[1]:find("Who's in? RFC, Bob?", 1, true) and not missed[1]:find("|Haddon", 1, true),
		"a friend offline gets the call as a line he missed, without the links, got " .. #missed)

	-- After 15 minutes it's over.
	a.env.ChatFrame1.TransformMessages = transform
	Run(900)
	local tally
	for _, l in ipairs(window) do
		if l:find("Who's in? RFC, Bob?", 1, true) and not l:find("]: ", 1, true) then
			tally = l
		end
	end
	check(tally and tally:find("The call has ended.", 1, true) and not tally:find("|Haddon", 1, true), "after 15 minutes the call ends, got " .. tostring(tally))
	markB = Mark(b)
	b.env.EventRegistry:TriggerEvent("SetItemRef", yes, "[I'm in]", "LeftButton")
	Run(1)
	check(PrintedSince(b, markB, "The call has ended.")[1] ~= nil, "a link of a call that ended says so")
	for _, client in ipairs({ a, b, c }) do
		Stop(client)
	end
end
