-- Chronicle's recipes (Recipes.lua): the data, the list encoding, my scan in steps, what goes out and
-- when, who gets it (older builds nothing), friends' lists passed on while their owner is offline, only
-- among friends, broken messages, the setting, pruning, and the lists the Professions tab asks for.
--
-- Every client here is a game of its own, like in echoes_net.lua: mock.lua and the addon in an environment
-- of their own, with their own clock, Battle.net friends and saved variables, and a small
-- ns.RecipeData of the test's (whatever Data/Recipes.lua holds).
-- Needs: no other file (its clients are its own; the suite's state is left alone).
local suite = ...
local check, section = suite.check, suite.section
local Hash32 = suite.LT.Hash32

---------------------------------------------------------------------------
-- The test's recipes: Alchemy (a few), Leatherworking (enough for several parts), Cooking
---------------------------------------------------------------------------

local LEATHER = {} -- 120 recipes, spells far enough apart to take room
do
	local list = {}
	for i = 1, 120 do
		local spell = 2000 + 40 * i
		LEATHER[i] = spell
		list[i] = ("%d:%d:1:5:20:2:50:80:7:2318*%d+2320*1"):format(spell, 5000 + i, i % 5 + 1)
	end
	LEATHER.text = table.concat(list, ";")
end
local DATA = {
	build = "test",
	order = { 171, 165, 185 },
	gathering = { 186 },
	parents = { [2937] = 171, [2945] = 165, [2939] = 185, [2946] = 186 },
	names = { [171] = { "Alchemy", "Alchimie" }, [165] = { "Leatherworking", "Lederverarbeitung" }, [185] = { "Cooking", "Kochkunst" },
		[186] = { "Mining", "Bergbau" } },
	icons = { [171] = 136240, [165] = 133611, [185] = 133971, [186] = 136248 },
	categories = {},
	recipes = {
		[171] = "2329:118:1:0:5:1:1:45:5:2447*1+765*1;2330:2454:2:::1:15:55::;2331:::::::::2453*3",
		[165] = LEATHER.text,
		[185] = "818:2679:1:::1:10:20::6889*1;3371:2680:1:::1:15:30::6889*2",
	},
}

---------------------------------------------------------------------------
-- The harness (as in echoes_net.lua)
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

local NEW, OLD = "0.7.0-20-gabc1234", "0.7.0-13-gabc1234" -- a build that reads recipes, the one before them
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

-- A client starts. opts: friends, version, saved, fake (friends are played by the test), char ({ first,
-- surname }: another character), professions, known ({ spell, ... }), level, locale.
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
	env.MOCK_LOCALE = opts.locale
	env.MY_BATTLETAG, env.MY_GUID, env.PLAYER_CLASS = p.tag, p.guid, p.class
	local first, surname = p.first, p.surname
	if opts.char then
		first, surname = opts.char[1], opts.char[2]
	end
	local baseUnitName = env.UnitName
	env.UnitName = function(unit)
		if unit == "player" then
			return first, surname
		end
		return baseUnitName(unit)
	end
	env.PLAYER_LEVEL = opts.level or env.PLAYER_LEVEL
	env.PROFESSIONS = opts.professions or {}
	for _, spell in ipairs(opts.known or {}) do
		env.KNOWN_SPELLS[spell] = true
	end
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
		assert(load(file.src, "@Interface/AddOns/LefthyTools/" .. file.name, "t", env))("LefthyTools", ns)
	end
	ns.LT.LAUNCH_DAY = nil
	ns.RecipeData = DATA
	env.Fire("ADDON_LOADED", "LefthyTools")
	env.Fire("PLAYER_LOGIN")
	env.Fire("PLAYER_ENTERING_WORLD", true, false)
	local c = { who = p, env = env, ns = ns, C = ns.Chronicle, R = ns.Chronicle.Recipes, B = ns.Beacon, LT = env.LefthyTools, opts = opts,
		read = 0, before = before, alive = {} }
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
	if world.byId[c.who.id] == c then
		world.byId[c.who.id] = nil
	end
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

-- /reload or logging in on another character: the same player, the next session.
local function Reload(c, change)
	local opts = c.opts
	opts.saved = Stop(c, true)
	for k, v in pairs(change or {}) do
		opts[k] = v
	end
	return Start(c.who, opts)
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
local function Pass(c, seconds, each)
	local t, step = 0, 0.25
	while t < seconds - 1e-9 do
		c.env.Advance(step, step)
		t = t + step
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
local function Mark(c)
	return #c.env.GAMEDATA + 1
end
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
local function Meet(c, f, version)
	Say(c, f, "H2")
	if version then
		Say(c, f, "V2;" .. version)
	end
	c.alive[#c.alive + 1] = f
	Pass(c, 1.5)
end

local function Set(c, key, value)
	c.env.LefthyTools.Options.registered["LefthyTools_chronicle_" .. key]:SetValue(value)
end

-- The spells of a list's parts (the ones it has).
local function Spells(R, r)
	local known, count = {}, 0
	for k = 1, r.of do
		R.Decode(r.parts[k] or "0", known)
	end
	for _ in pairs(known) do
		count = count + 1
	end
	return known, count
end

local function PersonOf(list, id)
	for _, person in ipairs(list) do
		if person.id == id then
			return person
		end
	end
end

local ALCHEMY = { name = "Alchemy", level = 120, max = 150, line = 2937 } -- (a child line)
local LEATHERWORKING = { name = "Leatherworking", level = 150, max = 225, line = 2945 }
local COOKING = { name = "Cooking", level = 40, max = 75, line = 185 } -- (a base line)
local MINING = { name = "Mining", level = 60, max = 75, line = 2946 }

local function SomeRecipes()
	local known = { 2329, 2331, 818 }
	for _, spell in ipairs(LEATHER) do
		known[#known + 1] = spell
	end
	return known
end

---------------------------------------------------------------------------
section("Recipes: reading the data, the lists' encoding")
---------------------------------------------------------------------------
do
	local me = Start(ANNA, { friends = { BOB }, fake = true })
	local R = me.R

	local list = R.Parse(171)
	local first = list[1]
	check(#list == 3 and first.spell == 2329 and first.item == 118 and first.count == 1 and first.slot == 0 and first.ilvl == 5
		and first.quality == 1 and first.low == 1 and first.high == 45 and first.cat == 5, "a recipe's fields")
	check(#first.reagents == 2 and first.reagents[1].item == 2447 and first.reagents[1].n == 1 and first.reagents[2].item == 765,
		"its reagents")
	check(list[2].slot == nil and list[2].cat == nil and #list[2].reagents == 0, "empty fields are nil")
	check(list[3].item == nil and list[3].count == nil and list[3].reagents[1].item == 2453 and list[3].reagents[1].n == 3,
		"a recipe that makes no item")
	check(R.Parse(171) == list, "parsed once: the same table")
	check(#R.Parse(999) == 0 and #R.Parse(186) == 0, "a line without recipes: none")
	local recipe, line = R.RecipeOf(LEATHER[3])
	check(recipe and recipe.spell == LEATHER[3] and line == 165, "a spell's recipe and line, parsed when needed")
	check(R.RecipeOf(1) == nil, "a spell no line has: nil")

	-- The encoding, both ways.
	local spells = { 1, 2, 3, 36, 37, 1296, 2149, 2150, 2190, 1317279, 1317964 }
	local parts = R.Encode(spells)
	local back, count = {}, 0
	for _, part in ipairs(parts) do
		count = count + (R.Decode(part, back) or 0)
	end
	local all = count == #spells
	for _, spell in ipairs(spells) do
		all = all and back[spell]
	end
	check(all and #parts == 1, "a short list goes there and back, in one part")
	check(parts[1]:sub(1, 8) == "1,1,1,x,", "differences in base 36, got " .. parts[1])

	-- A long list: parts small enough, each readable on its own.
	local long, seen = {}, {}
	for i = 1, 600 do
		long[i] = 2000 + 2100 * i
	end
	parts = R.Encode(long)
	local fits, stepsOk, sum = true, true, 0
	for _, part in ipairs(parts) do
		fits = fits and #part <= 160
		local one = {}
		local n = R.Decode(part, one)
		stepsOk = stepsOk and n ~= nil
		sum = sum + (n or 0)
		for spell in pairs(one) do
			seen[spell] = true
		end
	end
	all = sum == #long
	for _, spell in ipairs(long) do
		all = all and seen[spell]
	end
	check(#parts > 5 and fits and stepsOk and all, "a long list: parts of at most 160 bytes, each read on its own, all there, " .. #parts .. " parts")
	check(#("B2;cr;12345678;" .. ("x"):rep(48) .. ";2945;1234567890;30;30;") + 160 < 250, "a part with the longest key stays under 250 bytes")
	check(#R.Encode({}) == 0, "no spells: no parts")

	for _, bad in ipairs({ "", ",", "1,", ",1", "1,,2", "A", "1;2", "-1", "1.5", "0", "1,0", "zzzzzz", "zzzzz,zzzzz", ("1,"):rep(120) .. "1", 12 }) do
		check(R.Decode(bad) == nil, "not a part: " .. tostring(bad))
	end
	Stop(me)
end

---------------------------------------------------------------------------
section("Recipes: my scan")
---------------------------------------------------------------------------
local anna, annaCalls
do
	anna = Start(ANNA, { friends = { BOB, CEDRIC, DORA }, fake = true, professions = { ALCHEMY, LEATHERWORKING, COOKING, MINING },
		known = SomeRecipes() })
	local env, c = anna.env, anna.C.Char()
	annaCalls = { n = 0, inEvent = false }
	local isKnown = env.C_SpellBook.IsSpellKnown
	env.C_SpellBook.IsSpellKnown = function(id)
		annaCalls.n = annaCalls.n + 1
		return isKnown(id)
	end

	local mostInATick, last = 0, 0
	local function Watch()
		mostInATick = math.max(mostInATick, annaCalls.n - last)
		last = annaCalls.n
	end
	Pass(anna, 9, Watch)
	check(annaCalls.n == 0, "nothing scanned in the first seconds after entering the world")
	check(c.trade and c.trade[171] and c.trade[171].skill == 120 and c.trade[171].max == 150, "a child line counts as its base line")
	check(c.trade[185].skill == 40 and c.trade[186].skill == 60, "a base line too, and gathering")
	check(c.tradeU and not c.recipes, "my skills are saved first (they're cheap)")
	local total = 3 + 120 + 2
	Pass(anna, 2, Watch)
	check(annaCalls.n > 0 and annaCalls.n < total, "the scan goes in steps: " .. annaCalls.n .. " of " .. total .. " after its first tick")
	Pass(anna, 5, Watch)
	check(annaCalls.n == total, "every recipe of my professions is looked at once, got " .. annaCalls.n)
	check(mostInATick <= 50, "at most 50 a tick, got " .. mostInATick)
	check(c.recipes and c.recipes[171] and c.recipes[165] and c.recipes[185] and c.recipes[186] == nil, "a list per crafting line")
	local known, count = Spells(anna.R, c.recipes[171])
	check(count == 2 and known[2329] and known[2331] and not known[2330], "only the recipes I know")
	known, count = Spells(anna.R, c.recipes[165])
	check(count == 120 and c.recipes[165].of > 1, "a long list goes in parts, got " .. c.recipes[165].of)
	check(c.recipes[165].u == c.recipes[165].v + c.recipes[165].of - 1 and c.tradeScan, "its stamps: one per part")
	local stamps = c.recipes[171].u
	check(c.recipes[185].v > stamps or c.recipes[165].v > stamps, "stamps always rise")
	check(anna.LT and #env.ERRORS == 0, "no errors")

	-- A scan that finds what's saved changes nothing.
	local rev, u, v = anna.R.Revision(), env.LefthyToolsChronicleDB.recipeU, c.recipes[165].v
	annaCalls.n = 0
	env.Fire("TRADE_SKILL_LIST_UPDATE")
	env.Fire("TRADE_SKILL_LIST_UPDATE")
	check(annaCalls.n == 0, "the window's list: nothing in the event")
	Pass(anna, 60)
	check(annaCalls.n == total, "many list updates are one scan, within a minute, got " .. annaCalls.n)
	check(anna.R.Revision() == rev and env.LefthyToolsChronicleDB.recipeU == u and c.recipes[165].v == v, "the same list: no new stamp")

	-- Learning a recipe.
	annaCalls.n = 0
	env.KNOWN_SPELLS[2330] = true
	env.Fire("NEW_RECIPE_LEARNED", 2330)
	check(annaCalls.n == 0, "learning a recipe: nothing in the event")
	Pass(anna, 8)
	known = Spells(anna.R, c.recipes[171])
	check(known[2330] and c.recipes[171].v > v and c.recipes[165].v == v, "its list gets a new version, the others stay")
	check(anna.R.Revision() > rev, "the revision moved")

	-- A character played again after a long time: its stamps are renewed, for friends who dropped it.
	local oldList = c.recipes[185]
	oldList.u, oldList.v = env.time() - 31 * 86400, env.time() - 31 * 86400 - oldList.of + 1
	local keptV = c.recipes[171].v
	env.Fire("NEW_RECIPE_LEARNED", 0)
	Pass(anna, 8)
	check(c.recipes[185].v > env.time() - 86400 and c.recipes[171].v > keptV and c.tradeU > env.time() - 86400, "stamps older than 30 days: all of the character's renewed")
	u = env.LefthyToolsChronicleDB.recipeU
	env.Fire("NEW_RECIPE_LEARNED", 0)
	Pass(anna, 8)
	check(env.LefthyToolsChronicleDB.recipeU == u, "and not again")

	-- A loading screen that still knows nothing, or a game that doesn't say yet.
	local wasKnown, wasProfessions = env.KNOWN_SPELLS, env.PROFESSIONS
	env.KNOWN_SPELLS, env.PROFESSIONS = {}, {}
	env.Fire("PLAYER_ENTERING_WORLD", false, false)
	Pass(anna, 15)
	check(c.trade[171] and c.recipes[171], "no professions right after a loading screen: not believed")
	env.PROFESSIONS = wasProfessions
	Pass(anna, 70)
	check(c.recipes[171] and c.recipes[165], "nothing known for a moment: the lists stay")
	env.KNOWN_SPELLS = wasKnown
	Pass(anna, 62)

	-- A profession the game names some other way, or not at all.
	env.PROFESSIONS = { ALCHEMY, LEATHERWORKING, COOKING, { name = "Mining", level = 60, max = 75 } }
	env.Fire("SKILL_LINES_CHANGED")
	Pass(anna, 2)
	check(c.trade[186] and c.trade[186].skill == 60, "no line from the game: by its name")
	env.PROFESSIONS = { ALCHEMY, LEATHERWORKING, COOKING, { name = "Bergbau", level = 61, max = 75, line = 99999 } }
	env.Fire("SKILL_LINES_CHANGED")
	Pass(anna, 2)
	check(c.trade[186].skill == 61, "a line it doesn't know: by its name, German too")
	env.PROFESSIONS = { ALCHEMY, LEATHERWORKING, COOKING, { name = "Secret Art", level = 1, max = 1, line = 99999 } }
	env.Fire("SKILL_LINES_CHANGED")
	Pass(anna, 2)
	check(c.trade[186] and #env.ERRORS == 0, "one it can't tell: skipped, and nothing dropped because of it")
	env.PROFESSIONS = { ALCHEMY, LEATHERWORKING, COOKING, MINING }
	env.Fire("SKILL_LINES_CHANGED")
	Pass(anna, 2)
end

---------------------------------------------------------------------------
section("Recipes: what goes to friends, and when")
---------------------------------------------------------------------------
do
	local me, c = anna, anna.C.Char()
	local env = me.env
	local db = env.LefthyToolsChronicleDB
	Pass(me, 310) -- (the skills above stamped, nothing due)

	-- An older build, and one that doesn't say, never get a B message.
	local mark = Mark(me)
	Meet(me, DORA, OLD)
	Pass(me, 70)
	check(#Sent(me, DORA, mark, "B2;c") == 0, "a friend on an older build: no B message of these")
	me.B.peers[DORA.id].version = "0.7.0"
	Pass(me, 3)
	check(#Sent(me, DORA, mark, "B2;c") == 0, "nor on the tagged 0.7.0 (no commit count: not newer)")
	me.B.peers[DORA.id].version = nil
	Pass(me, 3)
	check(#Sent(me, DORA, mark, "B2;c") == 0, "nor while their build isn't known")
	Say(me, DORA, "B2;cq;" .. ANNA.acct .. ";0")
	Pass(me, 3)
	check(#Sent(me, DORA, mark, "B2;c") == 0, "not even if they ask")
	me.B.peers[DORA.id].version = "0.7.0-14-gabc1234"
	Pass(me, 3)
	check(Sent(me, DORA, mark, "B2;co;")[1] == "B2;co;" .. ANNA.acct .. "," .. db.recipeU, "the first build that reads them is offered them")
	me.B.peers[DORA.id].version = OLD
	Pass(me, 3)

	-- A friend hears what I hold; they ask.
	mark = Mark(me)
	Meet(me, BOB, NEW)
	Pass(me, 2)
	local offers = Sent(me, BOB, mark, "B2;co;")
	check(#offers == 1 and offers[1] == "B2;co;" .. ANNA.acct .. "," .. db.recipeU, "a friend is offered what I hold, got " .. tostring(offers[1]))
	check(#Sent(me, BOB, mark, "B2;cr;") == 0 and #Sent(me, BOB, mark, "B2;ct;") == 0, "no list before they ask")
	Pass(me, 70)
	check(#Sent(me, BOB, mark, "B2;co;") == 1, "nothing changed: nothing more")

	mark = Mark(me)
	Say(me, BOB, "B2;cq;" .. ANNA.acct .. ";0")
	Pass(me, 5)
	local trades, parts, ends = Sent(me, BOB, mark, "B2;ct;"), Sent(me, BOB, mark, "B2;cr;"), Sent(me, BOB, mark, "B2;ce;")
	local want = c.recipes[171].of + c.recipes[165].of + c.recipes[185].of
	check(#trades == 1 and trades[1] == ("B2;ct;%s;Anna-Realmy;%d;MAGE;%d;165:150:225,171:120:150,185:40:75,186:60:75"):format(ANNA.acct, c.tradeU, c.level),
		"my professions, got " .. tostring(trades[1]))
	check(#parts == want, "every part of every list, got " .. #parts .. " of " .. want)
	check(ends[1] == ("B2;ce;%s;%d;%d"):format(ANNA.acct, db.recipeU, want + 1), "and the end: how far, how many, got " .. tostring(ends[1]))
	local longest = 0
	for _, m in ipairs(parts) do
		longest = math.max(longest, #m)
		check(me.B.Parse(m) == "B", "Beacon reads it")
	end
	check(longest < 250, "under 250 bytes, the longest " .. longest)

	-- A skill that goes up: friends hear of it every 5 minutes at most, and it brings no list.
	mark = Mark(me)
	local partsBefore = c.recipes[165].v
	env.PROFESSIONS[2].level = 151
	env.Fire("SKILL_LINES_CHANGED")
	Pass(me, 70)
	check(c.trade[165].skill == 151 and #Sent(me, BOB, mark, "B2;co;") == 1, "my skill is saved at once, and offered (the last stamp is long ago)")
	mark = Mark(me)
	env.PROFESSIONS[2].level = 152
	env.Fire("SKILL_LINES_CHANGED")
	Pass(me, 70)
	check(c.trade[165].skill == 152 and c.tradeDirty and #Sent(me, BOB, mark, "B2;c") == 0, "another within 5 minutes: saved, friends aren't told yet")
	Pass(me, 240)
	local since = tonumber((Sent(me, BOB, mark, "B2;co;")[1] or ""):match(",(%d+)$"))
	check(since and #Sent(me, BOB, mark, "B2;co;") == 1 and c.recipes[165].v == partsBefore and not c.tradeDirty,
		"it's offered once the 5 minutes are up, once, got " .. #Sent(me, BOB, mark, "B2;co;"))
	mark = Mark(me)
	Say(me, BOB, "B2;cq;" .. ANNA.acct .. ";" .. (since - 1))
	Pass(me, 3)
	check(#Sent(me, BOB, mark, "B2;cr;") == 0, "a skill change alone sends no list")
	check(#Sent(me, BOB, mark, "B2;ct;") == 1 and Sent(me, BOB, mark, "B2;ct;")[1]:find("165:152:225", 1, true), "only the small record")
	check(Sent(me, BOB, mark, "B2;ce;")[1] == ("B2;ce;%s;%d;1"):format(ANNA.acct, db.recipeU), "and its end")

	-- A new recipe: only that list.
	since = db.recipeU
	mark = Mark(me)
	env.KNOWN_SPELLS[3371] = true
	env.Fire("NEW_RECIPE_LEARNED", 3371)
	Pass(me, 70)
	check(#Sent(me, BOB, mark, "B2;co;") == 1, "a new recipe is offered")
	Say(me, BOB, "B2;cq;" .. ANNA.acct .. ";" .. since)
	Pass(me, 3)
	parts = Sent(me, BOB, mark, "B2;cr;")
	check(#parts == c.recipes[185].of and parts[1]:find(";Anna-Realmy;185;", 1, true), "only its list")
	check(#Sent(me, BOB, mark, "B2;ct;") == 0, "without the skills")

	-- Every part has its own stamp: asked from inside a list, the rest of it comes.
	mark = Mark(me)
	Say(me, BOB, "B2;cq;" .. ANNA.acct .. ";" .. c.recipes[165].v)
	Pass(me, 3)
	parts = Sent(me, BOB, mark, "B2;cr;")
	local notFirst = true
	for _, m in ipairs(parts) do
		notFirst = notFirst and not m:find((";Anna-Realmy;165;%d;1;"):format(c.recipes[165].v))
	end
	check(notFirst and #parts >= c.recipes[165].of - 1, "asked from inside a list: its parts after that stamp")

	-- Their hello: everything offered again.
	mark = Mark(me)
	Pass(me, 6)
	Say(me, BOB, "H2")
	Pass(me, 2)
	check(#Sent(me, BOB, mark, "B2;co;") == 1, "a friend's hello (a /reload): offered again")

	-- My alts' lists go only with "all my characters" on.
	local alt = { name = "Zed", realm = "Realmy", classFile = "MAGE", level = 12, tradeU = db.recipeU + 1,
		trade = { [185] = { skill = 5, max = 75 } } }
	db.recipeU = db.recipeU + 1
	db.chars["Zed-Realmy"] = alt
	me.C.Fill(alt)
	mark = Mark(me)
	Say(me, BOB, "B2;cq;" .. ANNA.acct .. ";0")
	Pass(me, 5)
	local forAlt = false
	for _, m in ipairs(Sent(me, BOB, mark, "B2;ct;")) do
		forAlt = forAlt or m:find(";Zed-Realmy;", 1, true) ~= nil
	end
	check(forAlt, "an alt's list goes with all my characters")
	local stamp = alt.tradeU
	Set(me, "shareAlts", false)
	check(alt.tradeU > stamp, "switching that restamps them, so friends ask again")
	mark = Mark(me)
	Say(me, BOB, "B2;cq;" .. ANNA.acct .. ";0")
	Pass(me, 5)
	forAlt = false
	for _, m in ipairs(Sent(me, BOB, mark, "B2;c")) do
		forAlt = forAlt or m:find(";Zed-Realmy;", 1, true) ~= nil
	end
	check(not forAlt and #Sent(me, BOB, mark, "B2;ct;") == 1, "only the one I play with it off")
	Set(me, "shareAlts", true)
	db.chars["Zed-Realmy"] = nil
	Pass(me, 65)

	-- More than an answer holds: it's cut at SERVE_MAX, nothing lost, and the rest comes on the next round.
	local holder = db.book[BOB.acct] or { u = 0, chars = {} }
	db.book[BOB.acct] = holder
	local stampAt = env.time() - 5000
	for i = 1, 30 do
		local parts = {}
		for k = 1, 10 do
			parts[k] = "1z"
		end
		holder.chars["Many" .. i .. "-Realmy"] = { name = "Many" .. i, realm = "Realmy", days = {}, news = {}, classFile = "MAGE", level = 20,
			tradeU = stampAt + (i - 1) * 11, trade = { [185] = { skill = 1, max = 75 } },
			recipes = { [185] = { v = stampAt + (i - 1) * 11 + 1, u = stampAt + (i - 1) * 11 + 10, of = 10, n = 10, parts = parts } } }
	end
	holder.recipeU = stampAt + 30 * 11
	mark = Mark(me)
	Say(me, BOB, "B2;cq;" .. BOB.acct .. ";0") -- (his own: a holder doesn't know whose it asks for)
	Pass(me, 60)
	local firstEnd = Sent(me, BOB, mark, "B2;ce;" .. BOB.acct)[1]
	local count = #Sent(me, BOB, mark, "B2;cr;" .. BOB.acct) + #Sent(me, BOB, mark, "B2;ct;" .. BOB.acct)
	local upTo, said = (firstEnd or ""):match(";(%d+);(%d+)$")
	check(count == 300 and tonumber(said) == 300 and tonumber(upTo) == stampAt + 299, "an answer holds at most 300 records, oldest first, its end says how far, got " .. tostring(firstEnd))
	mark = Mark(me)
	Say(me, BOB, "B2;cq;" .. BOB.acct .. ";" .. upTo)
	Pass(me, 10)
	count = #Sent(me, BOB, mark, "B2;cr;" .. BOB.acct) + #Sent(me, BOB, mark, "B2;ct;" .. BOB.acct)
	check(count == 30 and Sent(me, BOB, mark, "B2;ce;" .. BOB.acct)[1] == ("B2;ce;%s;%d;30"):format(BOB.acct, holder.recipeU), "the rest comes on the next round, got " .. count)
	db.book[BOB.acct] = nil
	Pass(me, 65)

	-- The setting off: none of mine go out, a request gets nothing, what waits doesn't go.
	check(env.LefthyTools.Options.registered.LefthyTools_chronicle_shareRecipes ~= nil and me.C.module.db.shareRecipes == true, "a setting, on by default")
	mark = Mark(me)
	Say(me, BOB, "B2;cq;" .. ANNA.acct .. ";0")
	Set(me, "shareRecipes", false)
	Pass(me, 5)
	check(#Sent(me, BOB, mark, "B2;cr;") == 0 and #Sent(me, BOB, mark, "B2;ct;") == 0, "switched off: what was asked doesn't go")
	mark = Mark(me)
	Pass(me, 65)
	check(#Sent(me, BOB, mark, "B2;co;") == 0, "off: mine aren't offered")
	env.KNOWN_SPELLS[2330] = nil
	env.Fire("NEW_RECIPE_LEARNED", 2330)
	Pass(me, 65)
	check(#Sent(me, BOB, mark, "B2;c") == 0, "nor what changes meanwhile")
	Say(me, BOB, "B2;cq;" .. ANNA.acct .. ";0")
	Pass(me, 3)
	check(Sent(me, BOB, mark, "B2;ce;")[1] == ("B2;ce;%s;0;0"):format(ANNA.acct) and #Sent(me, BOB, mark, "B2;cr;") == 0,
		"asked anyway: an empty end")
	check(c.recipes[171] and not Spells(me.R, c.recipes[171])[2330], "my own list goes on being kept, for my own tab")
	Set(me, "shareRecipes", true)
	mark = Mark(me)
	Pass(me, 3)
	check(Sent(me, BOB, mark, "B2;co;")[1] == "B2;co;" .. ANNA.acct .. "," .. db.recipeU, "on again: what changed meanwhile is offered")

	mark = Mark(me)
	Set(me, "share", false)
	Say(me, BOB, "B2;cq;" .. ANNA.acct .. ";0")
	Pass(me, 65)
	check(#Sent(me, BOB, mark, "B2;co;") == 0 and #Sent(me, BOB, mark, "B2;cr;") == 0, "Chronicle's overall share off: the same")
	Set(me, "share", true)
	Pass(me, 3)
end

---------------------------------------------------------------------------
section("Recipes: friends' lists, broken messages")
---------------------------------------------------------------------------
do
	local me = anna
	local env, db, R = me.env, me.env.LefthyToolsChronicleDB, me.R
	local book = db.book
	Meet(me, CEDRIC, NEW)
	local t = env.time()
	local bob = BOB.acct

	-- A friend offers Bob's account: I ask one friend at a time, and only for my friends.
	local stranger = Hash32("stranger#9999")
	local mark = Mark(me)
	Say(me, CEDRIC, ("B2;co;%s,%d/%s,%d"):format(bob, t, stranger, t))
	Pass(me, 2)
	check(Sent(me, CEDRIC, mark, "B2;cq;" .. bob .. ";0")[1], "an account of a friend of mine is asked for")
	check(not Sent(me, CEDRIC, mark, "B2;cq;" .. stranger)[1], "a stranger's isn't")
	mark = Mark(me)
	Say(me, BOB, ("B2;co;%s,%d"):format(bob, t))
	Pass(me, 2)
	check(#Sent(me, BOB, mark, "B2;cq;") == 0, "asked of Cedric already: not of Bob too")

	-- His records come. Without his list being complete, it says so.
	local text = R.Encode({ LEATHER[1], LEATHER[2], LEATHER[3] })[1]
	Say(me, CEDRIC, ("B2;ct;%s;Bob-Realmy;%d;WARRIOR;40;165:300:300,185:10:75"):format(bob, t - 100))
	Say(me, CEDRIC, ("B2;cr;%s;Bob-Realmy;165;%d;1;2;%s"):format(bob, t - 90, text))
	Pass(me, 2)
	local c = book[bob] and book[bob].chars["Bob-Realmy"]
	check(c and c.trade[165].skill == 300 and c.trade[185].max == 75 and c.classFile == "WARRIOR" and c.level == 40, "a character's professions are kept")
	check(c.recipes[165].v == t - 90 and c.recipes[165].u == t - 89 and c.recipes[165].of == 2 and c.recipes[165].parts[1] == text, "a part of a list")
	check(not book[bob].recipeU, "no end yet: not complete")
	local rev = R.Revision()
	local bobPerson = PersonOf(R.People(165), "book:" .. bob .. ":Bob-Realmy")
	check(bobPerson and bobPerson.skill == 300 and bobPerson.known[LEATHER[2]] and bobPerson.incomplete == true, "the tab has what came, and that some is missing")
	local again = ("B2;ce;%s;%d;%d"):format(bob, t, 5)
	Say(me, CEDRIC, again)
	Pass(me, 2)
	check(not book[bob].recipeU, "an end with more records than came doesn't complete it")
	check(R.Revision() == rev, "nothing changed: the revision stays")

	-- Asked again later; the rest comes, and it's complete.
	mark = Mark(me)
	Pass(me, 125)
	check(Sent(me, BOB, mark, "B2;cq;" .. bob .. ";0")[1], "still short of it: asked again, of whoever offered it last")
	Say(me, BOB, ("B2;cr;%s;Bob-Realmy;165;%d;1;2;%s"):format(bob, t - 90, text))
	Say(me, BOB, ("B2;cr;%s;Bob-Realmy;165;%d;2;2;%s"):format(bob, t - 90, R.Encode({ LEATHER[4] })[1]))
	Say(me, BOB, ("B2;ct;%s;Bob-Realmy;%d;WARRIOR;40;165:300:300,185:10:75"):format(bob, t - 100))
	Say(me, BOB, ("B2;ce;%s;%d;3"):format(bob, t))
	Pass(me, 2)
	check(book[bob].recipeU == t, "the end of an answer complete: how far I hold it")
	bobPerson = PersonOf(R.People(165), "book:" .. bob .. ":Bob-Realmy")
	check(bobPerson.known[LEATHER[4]] and bobPerson.incomplete == false and bobPerson.updated == t - 89, "the whole list, and when it changed")
	check(R.Revision() > rev, "the revision moved")

	-- An answer cut short (its end says how far): the rest is asked for at once, from there.
	local fred = Hash32("fred#1111")
	me.env.BN_FRIENDS[#me.env.BN_FRIENDS + 1] = { Account(Person(16, "Fred Lane", "MAGE", "Fred#1111"), false), battleTag = "Fred#1111" }
	Pass(me, 31) -- (the friend list is kept 30 s)
	Say(me, CEDRIC, ("B2;co;%s,%d"):format(fred, t))
	Pass(me, 2)
	check(Sent(me, CEDRIC, mark, "B2;cq;" .. fred .. ";0")[1], "a friend's account is asked for")
	mark = Mark(me)
	Say(me, CEDRIC, ("B2;ct;%s;Fred-Realmy;%d;MAGE;20;185:1:75"):format(fred, t - 300))
	Say(me, CEDRIC, ("B2;ce;%s;%d;1"):format(fred, t - 300))
	Pass(me, 2)
	check(book[fred].recipeU == t - 300, "the end: how far it got")
	check(Sent(me, CEDRIC, mark, "B2;cq;" .. fred .. ";" .. (t - 300))[1], "the rest is asked for at once")
	-- And its end brings nothing more than I have: no asking for ever.
	mark = Mark(me)
	Say(me, CEDRIC, ("B2;ce;%s;%d;0"):format(fred, t - 300))
	Pass(me, 130)
	check(#Sent(me, CEDRIC, mark, "B2;cq;" .. fred) == 0 and book[fred].recipeU == t - 300, "someone who offered more than they have isn't asked again and again")

	-- Newer and older versions.
	mark = Mark(me)
	mark = Mark(me)
	Say(me, CEDRIC, ("B2;cr;%s;Bob-Realmy;165;%d;1;1;%s"):format(bob, t - 200, R.Encode({ LEATHER[9] })[1]))
	Pass(me, 2)
	check(c.recipes[165].v == t - 90, "an older version is ignored")
	Say(me, CEDRIC, ("B2;cr;%s;Bob-Realmy;165;%d;1;1;%s"):format(bob, t - 50, R.Encode({ LEATHER[9] })[1]))
	Pass(me, 2)
	check(c.recipes[165].v == t - 50 and c.recipes[165].of == 1 and not c.recipes[165].parts[2], "a newer one replaces the list")
	check(PersonOf(R.People(165), "book:" .. bob .. ":Bob-Realmy").known[LEATHER[1]] == nil, "the old recipes are gone from the tab")
	-- A profession dropped: a newer record without it.
	Say(me, CEDRIC, ("B2;ct;%s;Bob-Realmy;%d;WARRIOR;40;185:10:75"):format(bob, t - 40))
	Pass(me, 2)
	check(c.trade[165] == nil and c.recipes[165] == nil, "a profession dropped takes its list along")
	Say(me, CEDRIC, ("B2;cr;%s;Bob-Realmy;165;%d;1;1;%s"):format(bob, t - 45, R.Encode({ LEATHER[9] })[1]))
	Pass(me, 2)
	check(c.recipes[165] == nil, "an older list of it, still on its way, stays out")

	-- Broken and hostile messages: nothing kept, nothing reported.
	local before = { rev = R.Revision(), chars = 0 }
	for _ in pairs(book[bob].chars) do
		before.chars = before.chars + 1
	end
	local valid = ("B2;cr;%s;Bad-Realmy;171;%d;1;1;%s"):format(bob, t, R.Encode({ 2329 })[1])
	local BROKEN = {
		("B2;cr;%s;Bad-Realmy;171;%d;1;1;%s"):format(stranger, t, "1z"), -- a stranger's account
		("B2;cr;%s;Bad-Realmy;171;%d;1;1;%s"):format(ANNA.acct, t, "1z"), -- mine
		("B2;cr;nothex12;Bad-Realmy;171;%d;1;1;%s"):format(t, "1z"),
		("B2;cr;%s;Bad-Realmy;171;%d;1;1"):format(bob, t), -- a field missing
		valid .. ";1", -- one more
		("B2;cr;%s;Bad;171;%d;1;1;1z"):format(bob, t), -- a key without a realm
		("B2;cr;%s;Bad|cff-Realmy;171;%d;1;1;1z"):format(bob, t), -- escape codes
		("B2;cr;%s;%s-Realmy;171;%d;1;1;1z"):format(bob, ("x"):rep(60), t), -- too long a key
		("B2;cr;%s;Bad-Realmy;186;%d;1;1;1z"):format(bob, t), -- gathering has no list
		("B2;cr;%s;Bad-Realmy;999;%d;1;1;1z"):format(bob, t), -- an unknown line
		("B2;cr;%s;Bad-Realmy;171;abc;1;1;1z"):format(bob),
		("B2;cr;%s;Bad-Realmy;171;%d;1;1;1z"):format(bob, t + 8 * 86400), -- a stamp from the future
		("B2;cr;%s;Bad-Realmy;171;0;1;1;1z"):format(bob),
		("B2;cr;%s;Bad-Realmy;171;12345678901;1;1;1z"):format(bob),
		("B2;cr;%s;Bad-Realmy;171;%d;0;1;1z"):format(bob, t), -- part 0
		("B2;cr;%s;Bad-Realmy;171;%d;2;1;1z"):format(bob, t), -- part 2 of 1
		("B2;cr;%s;Bad-Realmy;171;%d;1;31;1z"):format(bob, t), -- too many parts
		("B2;cr;%s;Bad-Realmy;171;%d;1e0;1;1z"):format(bob, t),
		("B2;cr;%s;Bad-Realmy;171;%d;1;1;"):format(bob, t), -- no text
		("B2;cr;%s;Bad-Realmy;171;%d;1;1;1Z"):format(bob, t), -- not base 36's lowercase
		("B2;cr;%s;Bad-Realmy;171;%d;1;1;1,0"):format(bob, t), -- a difference of 0
		("B2;cr;%s;Bad-Realmy;171;%d;1;1;zzzzz,zzzzz"):format(bob, t), -- past any spell
		("B2;cr;%s;Bad-Realmy;171;%d;1;1;zzzzzz"):format(bob, t), -- too many digits
		("B2;cr;%s;Bad-Realmy;171;%d;1;1;%s"):format(bob, t, ("1,"):rep(110) .. "1"), -- too long a part
		("B2;ct;%s;Bad-Realmy;%d;MAGE;20"):format(bob, t),
		("B2;ct;%s;Bad-Realmy;abc;MAGE;20;165:1:1"):format(bob),
		("B2;ct;%s;Bad-Realmy;%d;MAGE;20;165:1"):format(bob, t),
		("B2;ct;%s;Bad-Realmy;%d;MAGE;20;165:1:x"):format(bob, t),
		("B2;ct;%s;Bad-Realmy;%d;MAGE;20;165:12345:1"):format(bob, t),
		("B2;ct;%s;Bad-Realmy;%d;MAGE;20;165:1:1,"):format(bob, t),
		("B2;ct;%s;Bad-Realmy;%d;MAGE;20;%s"):format(bob, t, ("165:1:1,"):rep(12) .. "165:1:1"), -- too many
		("B2;ct;%s;Bad-Realmy;%d;mage;20;165:1:1"):format(bob, t),
		("B2;ct;%s;Bad-Realmy;%d;MAGE;1000;165:1:1"):format(bob, t),
		("B2;ct;%s;Bad-Realmy;%d;MAGE;20;"):format(bob, t), -- nothing to keep a character for
		("B2;co;%s"):format(bob),
		("B2;ce;%s;abc;1"):format(bob),
		("B2;cz;%s;1;1"):format(bob), -- a word of a later build
		"B2;cr;" .. ("x"):rep(300), -- too long for any message
		"B2;cr;",
		"B2;c;1",
	}
	for _, m in ipairs(BROKEN) do
		Say(me, CEDRIC, m)
	end
	Pass(me, 3)
	check(book[bob].chars["Bad-Realmy"] == nil and not book[stranger] and #env.ERRORS == 0, "broken messages: nothing kept, nothing reported")
	check(book[ANNA.acct] == nil, "nothing about my own account")
	check(R.Revision() == before.rev, "and nothing changed")
	Say(me, CEDRIC, valid)
	Pass(me, 2)
	check(book[bob].chars["Bad-Realmy"] and book[bob].chars["Bad-Realmy"].recipes[171], "the same message done right is kept")

	-- A request with a stamp no real one has, or that isn't one, is simply not answered.
	mark = Mark(me)
	Say(me, CEDRIC, "B2;cq;" .. bob .. ";abc")
	Say(me, CEDRIC, "B2;cq;" .. bob .. ";123456789012")
	Say(me, CEDRIC, "B2;cq;zz;0")
	Pass(me, 2)
	check(#Sent(me, CEDRIC, mark, "B2;ce;") == 0, "a broken request gets no answer")

	-- Too many characters on one account: the most recently played stay.
	for i = 1, 40 do
		Say(me, CEDRIC, ("B2;ct;%s;Char%d-Realmy;%d;MAGE;20;165:%d:300"):format(bob, i, t - 1000 + i, i))
		if i % 10 == 0 then
			Pass(me, 1.5)
		end
	end
	Pass(me, 2)
	local kept = 0
	for _ in pairs(book[bob].chars) do
		kept = kept + 1
	end
	check(kept == 30, "at most 30 characters an account, got " .. kept)
	check(book[bob].chars["Char40-Realmy"] and not book[bob].chars["Char1-Realmy"], "the latest stay")
	for key in pairs(book[bob].chars) do
		if key:find("^Char") or key == "Bad-Realmy" then
			book[bob].chars[key] = nil
		end
	end

	-- A list can't grow past its caps, however it's sent.
	local many = {}
	for i = 1, 100 do
		many[i] = "1"
	end
	local big = table.concat(many, ",")
	for k = 1, 30 do
		Say(me, CEDRIC, ("B2;cr;%s;Huge-Realmy;171;%d;%d;30;%s"):format(bob, t, k, big))
		if k % 10 == 0 then
			Pass(me, 1.5)
		end
	end
	Pass(me, 2)
	local huge = book[bob].chars["Huge-Realmy"].recipes[171]
	check(huge.n == 1500 and huge.parts[15] and not huge.parts[16], "at most 1500 recipes a list, got " .. huge.n)
	book[bob].chars["Huge-Realmy"] = nil
end

---------------------------------------------------------------------------
section("Recipes: who's in the tab")
---------------------------------------------------------------------------
do
	local me = anna
	local env, db, R = me.env, me.env.LefthyToolsChronicleDB, me.R
	local bob, cedric = BOB.acct, CEDRIC.acct
	local t = env.time()
	env.SPELL_NAMES[LEATHER[1]], env.SPELL_NAMES[LEATHER[2]] = "Heavy Armor Kit", "Öl für Leder"
	env.SPELL_NAMES[2329] = "Elixir of Lion's Strength"

	local function Trade(f, key, u, level, trade)
		Say(me, f, ("B2;ct;%s;%s;%d;MAGE;%d;%s"):format(f.acct, key, u, level, trade))
	end
	-- (Bob's and Cedric's: the friend says it of themselves)
	Trade(BOB, "Bob-Realmy", t + 1, 40, "165:300:300")
	Trade(BOB, "Bobby-Realmy", t + 2, 30, "165:152:300")
	Trade(BOB, "Bo-Realmy", t + 3, 20, "165:152:300")
	Trade(CEDRIC, "Cedric-Realmy", t + 4, 60, "165:152:300,171:10:75,186:75:75")
	local parts = R.Encode({ LEATHER[1], LEATHER[2], LEATHER[3] })
	Say(me, BOB, ("B2;cr;%s;Bob-Realmy;165;%d;1;%d;%s"):format(bob, t + 5, #parts, parts[1]))
	parts = R.Encode({ LEATHER[2] })
	Say(me, CEDRIC, ("B2;cr;%s;Cedric-Realmy;165;%d;1;%d;%s"):format(cedric, t + 6, #parts, parts[1]))
	Pass(me, 2)
	local people = R.People(165)
	local order = {}
	for i, person in ipairs(people) do
		order[i] = person.id:match("([^:]+)$")
	end
	check(table.concat(order, " ") == "Bob-Realmy Bobby-Realmy Bo-Realmy Cedric-Realmy Anna-Realmy",
		"best skill first, ties by BattleTag, then level, got " .. table.concat(order, " "))
	local first, last = people[1], people[#people]
	check(first.id == "book:" .. bob .. ":Bob-Realmy" and first.name == "Bob Stone" and first.classFile == "WARRIOR" and first.level == 40 and first.account == "Bobby"
		and first.mine == false and first.skill == 300 and first.max == 300 and first.partial == false and first.known[LEATHER[3]],
		"a friend's person (Battle.net told his full name)")
	check(last.id == "me:Anna-Realmy" and last.name == "Anna Brook" and last.mine == true and last.account == "you" and last.skill == 152 and last.max == 225
		and last.partial == false and last.known[LEATHER[120]] and last.updated == me.C.Char().tradeScan, "mine")
	check(R.People(165) == people, "kept until the revision moves")
	check(#R.People(186) == 2 and next(PersonOf(R.People(186), "book:" .. cedric .. ":Cedric-Realmy").known) == nil, "gathering: who, no recipes")
	check(#R.People(197) == 0, "a profession nobody has: nobody")

	local bobby = R.People(165)[2]
	check(bobby.name == "Bobby" and bobby.partial == true and bobby.level == 30, "only its first name known yet: partial")
	db.book[bob].chars["Bobby-Realmy"].full = "Bobby Stone"
	check(bobby.partial == true and R.People(165)[2].name == "Bobby Stone" and R.People(165)[2].partial == false and R.People(165) == people,
		"a surname learned shows without a rebuild")

	local professions = R.Professions()
	check(#professions == 4 and professions[1].line == 171 and professions[2].line == 165 and professions[3].line == 185 and professions[4].line == 186,
		"professions in the data's order, crafting first")
	check(professions[1].name == "Alchemy" and professions[1].icon == 136240 and professions[1].count == 2 and not professions[1].gathering, "Alchemy: me and Cedric")
	check(professions[2].count == 5 and professions[4].gathering == true and professions[4].count == 2, "the counts, gathering marked")

	-- Crafters.
	local crafters = R.Crafters(LEATHER[2])
	check(#crafters == 3 and crafters[1].id == first.id and crafters[2].id == "book:" .. cedric .. ":Cedric-Realmy" and crafters[3].id == "me:Anna-Realmy",
		"who knows a recipe, best skill first")
	check(#R.Crafters(LEATHER[3]) == 2 and #R.Crafters(2330) == 0, "only those who know it (Anna unlearned it)")
	check(#R.Crafters(1) == 0, "a spell no line has: nobody")

	-- People: by a character's name or BattleTag name, each once, with all their professions.
	local someone = first
	local byName = R.SearchPeople(someone.name:sub(1, 3):upper())
	local hit
	for _, match in ipairs(byName) do
		if match.who.id == someone.id then hit = match end
	end
	check(hit and hit.professions[1] and hit.professions[1].line and hit.professions[1].name and hit.professions[1].skill,
		"a character's name, any case: them, with their professions")
	local inline = 0
	for _, prof in ipairs(hit and hit.professions or {}) do
		if prof.line == 165 then inline = inline + 1; check(prof.count == (function() local n = 0; for _ in pairs(someone.known) do n = n + 1 end return n end)(), "their recipes counted") end
	end
	check(inline == 1, "each profession once")
	check(#R.SearchPeople("") == 0 and #R.SearchPeople("zzzz-nobody") == 0, "nothing typed, or nobody: none")
	if someone.account and someone.account ~= "" then
		local byTag = R.SearchPeople(someone.account)
		local tagged = false
		for _, match in ipairs(byTag) do
			tagged = tagged or match.who.id == someone.id
		end
		check(tagged, "a BattleTag name finds them too")
	end

	-- Search.
	local results = R.Search("HEAVY armor")
	check(#results == 1 and results[1].recipe.spell == LEATHER[1] and results[1].line == 165 and #results[1].people == 2,
		"by the spell's name, any case: the recipe, its line and who knows it")
	check(results[1].people[1].id == first.id and results[1].people[2].mine == true, "in the tab's order")
	check(#R.Search("öl für") == 1 and #R.Search("Öl FÜR") == 1, "an umlaut in any case")
	check(#R.Search("") == 0 and #R.Search("   ") == 0 and #R.Search(nil) == 0, "no text: nothing")
	check(#R.Search("nothing like this") == 0, "no match: nothing")
	check(#R.Search("spell") == 100, "at most 100 results")

	-- An item's name, only once the client has it; asked for sparingly.
	local asked = {}
	env.C_Item.RequestLoadItemDataByID = function(id)
		asked[#asked + 1] = id
	end
	local item = 5000 + 7 -- (LEATHER[7]: only I know it)
	local cached = {}
	env.C_Item.IsItemDataCachedByID = function(id)
		return cached[id] == true
	end
	env.ITEMS[item] = { name = "Rugged Sack", quality = 1 }
	check(#R.Search("rugged") == 0, "an item that isn't loaded: not found yet")
	check(#asked > 0 and #asked <= 20, "a few are asked for at a time, got " .. #asked)
	local firstAsked = #asked
	R.Search("rugged")
	local twice = {}
	for _, id in ipairs(asked) do
		check(not twice[id], "each only once")
		twice[id] = true
	end
	check(#asked <= firstAsked + 20, "and a few more with the next search")
	cached[item] = true
	results = R.Search("rugged")
	check(#results == 1 and results[1].recipe.spell == LEATHER[7] and results[1].recipe.item == item, "loaded: found by the item's name")
	env.C_Item.IsItemDataCachedByID = nil

	-- The same revision, nothing rebuilt; another revision, rebuilt.
	local rev = R.Revision()
	Trade(CEDRIC, "Cedric-Realmy", t + 9, 60, "165:153:300,171:10:75,186:75:75")
	Pass(me, 2)
	check(R.Revision() > rev and R.People(165) ~= people, "a change moves the revision, and the lists are built anew")
	check(PersonOf(R.People(165), "book:" .. cedric .. ":Cedric-Realmy").skill == 153, "with the new skill")
	check(PersonOf(R.People(165), "book:" .. cedric .. ":Cedric-Realmy").known[LEATHER[2]], "a new skill leaves the list alone")

	-- German.
	local de = Start(EVE, { friends = {}, fake = true, locale = "deDE", professions = { { name = "Alchimie", level = 5, max = 75 } } })
	Pass(de, 2)
	check(de.R.Professions()[1].name == "Alchimie" and de.R.Professions()[1].count == 1, "on a German client: German names, by a German profession's name")
	check(de.R.People(171)[1].account == "du", "and mine says so in German")
	Stop(de)
end

---------------------------------------------------------------------------
section("Recipes: a character with only recipes, and pruning")
---------------------------------------------------------------------------
do
	local me = anna
	local env, db, R = me.env, me.env.LefthyToolsChronicleDB, me.R
	local t = env.time()
	local bob = BOB.acct

	Say(me, CEDRIC, ("B2;ct;%s;Lone-Realmy;%d;MAGE;33;185:40:75"):format(bob, t))
	Say(me, CEDRIC, ("B2;cr;%s;Lone-Realmy;185;%d;1;1;%s"):format(bob, t + 1, R.Encode({ 818 })[1]))
	Say(me, CEDRIC, ("B2;ct;%s;Stale-Realmy;%d;MAGE;33;185:40:75"):format(bob, t - 80 * 86400))
	Pass(me, 2)
	local lone = db.book[bob].chars["Lone-Realmy"]
	check(lone and lone.classFile == "MAGE" and lone.level == 33 and next(lone.days) == nil, "a character I only know by its recipes")
	check(PersonOf(R.People(185), "book:" .. bob .. ":Lone-Realmy") ~= nil, "is in the tab")
	-- Chronicle's other pages and lists leave it out, without tripping over it.
	local ok, err = pcall(function()
		local listed = false
		for _, character in ipairs(me.C.Characters()) do
			listed = listed or character.key == "book:" .. bob .. ":Lone-Realmy"
		end
		check(not listed, "not on the pages of journals")
		me.C.Accounts()
		me.C.FriendNews()
		me.C.UnseenCount()
		me.C.AnyUnseen()
		me.C.Meet()
		me.C.Partial(lone)
	end)
	check(ok, "the pages don't trip over it: " .. tostring(err))

	-- The journal's answer about that account leaves it out cleanly too.
	local mark = Mark(me)
	Say(me, DORA, "J2;h;" .. DORA.acct)
	Say(me, DORA, "J2;q;" .. bob .. ";0")
	Pass(me, 5)
	check(#env.ERRORS == 0, "a journal's answer doesn't trip over it")
	check(Sent(me, DORA, mark, "J2;e;" .. bob)[1] ~= nil, "and ends as ever")

	-- /reload: the book is pruned a minute later.
	local rev = R.Revision()
	local cOffer = db.book[bob].recipeU
	me = Reload(me)
	anna = me
	env, R = me.env, me.R
	db = env.LefthyToolsChronicleDB
	me.alive = { BOB, CEDRIC }
	Pass(me, 65)
	check(db.book[bob].chars["Lone-Realmy"] ~= nil, "a character with only recently stamped recipes stays")
	check(db.book[bob].chars["Stale-Realmy"] == nil, "one with nothing newer than 60 days goes, its recipes too")
	check(db.book[bob].recipeU == cOffer, "the account's stamp stays: it isn't asked for again")
	check(PersonOf(R.People(185), "book:" .. bob .. ":Stale-Realmy") == nil and rev ~= nil, "and it's gone from the tab")
	check(me.C.Char().recipes and me.C.Char().recipes[171], "mine came through the saved data")

	-- Saved data that can't be right.
	local saved = Stop(me, true)
	local book = saved.LefthyToolsChronicleDB.book
	book[bob].recipeU = env.time() + 30 * 86400
	book[bob].chars["Lone-Realmy"].recipes = "broken"
	book[bob].chars["Bob-Realmy"].trade = 5
	book[bob].chars["Bob-Realmy"].recipes = { [185] = { parts = "x" }, [171] = { v = env.time() + 30 * 86400, of = 1, parts = {} } }
	saved.LefthyToolsChronicleDB.recipeU = env.time() + 30 * 86400
	local opts = me.opts
	opts.saved = saved
	me = Start(ANNA, opts)
	anna = me
	local fromFuture = me.env.LefthyToolsChronicleDB
	check(fromFuture.book[bob].recipeU == nil, "an impossible stamp on an account: asked again")
	check(fromFuture.book[bob].chars["Lone-Realmy"].recipes == nil and fromFuture.book[bob].chars["Bob-Realmy"].trade == nil
		and next(fromFuture.book[bob].chars["Bob-Realmy"].recipes) == nil, "records that can't be read go")
	local mine = fromFuture.chars["Anna-Realmy"]
	check(fromFuture.recipeU <= me.env.time() + 1000 and mine.recipes[171].v <= me.env.time() + 1000, "my own stamp from the future: everything stamped anew from now")
	Pass(me, 3)
	check(#me.env.ERRORS == 0, "no errors")

	-- Switching Chronicle off and on.
	Set(me, "shareAlts", false)
	Set(me, "shareAlts", true)
	me.LT:SetModuleEnabled("chronicle", false)
	Say(me, CEDRIC, ("B2;ct;%s;Late-Realmy;%d;MAGE;33;185:40:75"):format(bob, me.env.time()))
	Pass(me, 2)
	check(fromFuture.book[bob].chars["Late-Realmy"] == nil, "Chronicle off: nothing is taken")
	me.LT:SetModuleEnabled("chronicle", true)
	Pass(me, 2)
	check(#me.env.ERRORS == 0, "back on, no errors")
	Stop(me)
end

---------------------------------------------------------------------------
section("Recipes: friends, and friends of friends while they're offline")
---------------------------------------------------------------------------
do
	world.time = 1000
	-- Anna: a friend of Bob's and Cedric's and of Dora's (older build). Bob: also of Eve's, who isn't Anna's friend.
	local a = Start(ANNA, { friends = { BOB, CEDRIC, DORA }, professions = { ALCHEMY, COOKING }, known = { 2329, 2331, 818 } })
	local b = Start(BOB, { friends = { ANNA, CEDRIC, EVE }, professions = { LEATHERWORKING }, known = { LEATHER[1], LEATHER[2] } })

	local function BobHasAnna()
		local c = b.env.LefthyToolsChronicleDB.book[ANNA.acct]
		c = c and c.chars["Anna-Realmy"]
		return c and c.recipes and c.recipes[171] and c.recipes[185] and c.trade and b.env.LefthyToolsChronicleDB.book[ANNA.acct].recipeU
	end
	check(Run(90, BobHasAnna), "a friend online gets my lists")
	local inBob = b.env.LefthyToolsChronicleDB.book[ANNA.acct].chars["Anna-Realmy"]
	local mine = a.C.Char()
	check(inBob.recipes[171].v == mine.recipes[171].v and inBob.recipes[171].parts[1] == mine.recipes[171].parts[1],
		"unchanged: the same stamps, the same text")
	check(inBob.trade[171].skill == 120 and inBob.classFile == "MAGE", "and my skills")
	local annaInBob = PersonOf(b.R.People(171), "book:" .. ANNA.acct .. ":Anna-Realmy")
	check(annaInBob and annaInBob.known[2331] and annaInBob.account == "Annie", "in the friend's tab")
	Run(10)
	check(a.env.LefthyToolsChronicleDB.book[BOB.acct] and a.env.LefthyToolsChronicleDB.book[BOB.acct].chars["Bob-Realmy"].recipes[165], "and I get theirs")

	-- Nothing changes: quiet.
	local from = #world.log + 1
	Run(50)
	local quiet = 0
	for i = from, #world.log do
		if world.log[i].data:sub(1, 4) == "B2;c" then
			quiet = quiet + 1
		end
	end
	check(quiet == 0, "nothing changed: no recipe message for a while, got " .. quiet)

	-- Older and newer builds at once.
	local d = Start(DORA, { friends = { ANNA }, version = OLD, professions = { COOKING }, known = { 818 } })
	Run(70)
	local toDora = 0
	for _, m in ipairs(world.log) do
		if m.data:sub(1, 4) == "B2;c" and m.to == DORA.id then
			toDora = toDora + 1
		end
	end
	check(toDora == 0, "a friend on an older build never gets a recipe message, got " .. toDora)
	check(a.B.peers[DORA.id] and a.B.peers[DORA.id].version == OLD, "though she's known")
	Stop(d)

	-- Anna goes offline. Cedric comes: friends with both, he gets her list from Bob.
	local annaStamp = a.env.LefthyToolsChronicleDB.recipeU
	local partsThere = mine.recipes[171].parts[1]
	local v = mine.recipes[171].v
	local savedAnna = Stop(a)
	local c = Start(CEDRIC, { friends = { ANNA, BOB }, professions = {} })
	local e = Start(EVE, { friends = { BOB }, professions = {} })
	local function CedricHasAnna()
		local book = c.env.LefthyToolsChronicleDB.book[ANNA.acct]
		return book and book.recipeU == annaStamp
	end
	check(Run(120, CedricHasAnna), "a third friend gets her list relayed while she's offline")
	local inCedric = c.env.LefthyToolsChronicleDB.book[ANNA.acct].chars["Anna-Realmy"]
	check(inCedric.recipes[171].parts[1] == partsThere and inCedric.recipes[171].v == v and inCedric.recipes[185] and inCedric.trade[185],
		"relayed unchanged: her stamps, her text")
	check(PersonOf(c.R.People(171), "book:" .. ANNA.acct .. ":Anna-Realmy") ~= nil, "she's in his tab")

	-- Eve hears of Anna's account from Bob, and neither asks nor keeps it: not her friend.
	Run(30)
	check(e.env.LefthyToolsChronicleDB.book[ANNA.acct] == nil, "someone who isn't her friend doesn't get it")
	local asked = false
	for _, m in ipairs(world.log) do
		if m.from == EVE.id and m.data:find("B2;cq;" .. ANNA.acct, 1, true) then
			asked = true
		end
	end
	check(not asked, "and doesn't ask for it")
	check(e.env.LefthyToolsChronicleDB.book[BOB.acct] and e.env.LefthyToolsChronicleDB.book[BOB.acct].chars["Bob-Realmy"].recipes[165], "Bob's own she gets")
	Stop(e)

	-- Relay off: Bob keeps what he holds, and passes on nothing.
	Set(b, "relay", false)
	Stop(c)
	local late = Start(CEDRIC, { friends = { ANNA, BOB }, professions = {} })
	Run(40)
	check(late.env.LefthyToolsChronicleDB.book[ANNA.acct] == nil, "with relay off, friends' lists aren't passed on")
	check(late.env.LefthyToolsChronicleDB.book[BOB.acct] and late.env.LefthyToolsChronicleDB.book[BOB.acct].chars["Bob-Realmy"], "his own still go")
	Set(b, "relay", true)
	Stop(late)

	-- Anna comes back on another character: her list is saved when that one is played, and joins the first.
	local a2 = Start(ANNA, { friends = { BOB, CEDRIC, DORA }, saved = savedAnna, char = { "Ann", "Brook" }, professions = { LEATHERWORKING }, known = { LEATHER[5] } })
	local function BobHasBoth()
		local chars = b.env.LefthyToolsChronicleDB.book[ANNA.acct].chars
		return chars["Ann-Realmy"] and chars["Ann-Realmy"].recipes and chars["Ann-Realmy"].recipes[165] and chars["Anna-Realmy"].recipes[171]
	end
	check(Run(90, BobHasBoth), "an alt's list reaches friends, and her first character's stays")
	check(#a2.R.People(171) >= 1 and PersonOf(a2.R.People(171), "me:Anna-Realmy") and PersonOf(a2.R.People(165), "me:Ann-Realmy"), "both in her own tab")
	check(PersonOf(a2.R.People(165), "me:Anna-Realmy") == nil, "each with its own professions")

	-- She'd rather not: off. What Bob holds stays until it's replaced.
	Set(a2, "shareRecipes", false)
	a2.env.KNOWN_SPELLS[LEATHER[6]] = true
	a2.env.Fire("NEW_RECIPE_LEARNED", LEATHER[6])
	local before = b.env.LefthyToolsChronicleDB.book[ANNA.acct].chars["Ann-Realmy"].recipes[165].v
	Run(70)
	check(a2.C.Char().recipes[165].v > before, "her own list goes on")
	check(b.env.LefthyToolsChronicleDB.book[ANNA.acct].chars["Ann-Realmy"].recipes[165].v == before, "off: friends get nothing new, and keep what they have")
	Stop(a2)
	Stop(b)
end

---------------------------------------------------------------------------
section("Recipes: who can craft it, in item tooltips")
---------------------------------------------------------------------------
do
	world.time = 0
	local me = Start(ANNA, { friends = { BOB, CEDRIC }, fake = true, professions = { { name = "Leatherworking", level = 150, max = 225, line = 2945 } },
		known = { LEATHER[1], LEATHER[2], LEATHER[4] } })
	local env, R = me.env, me.R
	Meet(me, BOB, NEW)
	Meet(me, CEDRIC, NEW)
	Pass(me, 16) -- (my scan)
	local t = env.time()
	local function Trade(f, key, u, level, trade)
		Say(me, f, ("B2;ct;%s;%s;%d;%s;%d;%s"):format(f.acct, key, u, f.class, level, trade))
	end
	local function List(f, key, line, u, spells)
		local parts = R.Encode(spells)
		for k, text in ipairs(parts) do
			Say(me, f, ("B2;cr;%s;%s;%d;%d;%d;%d;%s"):format(f.acct, key, line, u, k, #parts, text))
		end
	end
	Trade(BOB, "Bob-Realmy", t + 1, 40, "165:300:300")
	Trade(BOB, "Bobby-Realmy", t + 2, 30, "165:200:300")
	Trade(BOB, "Bo-Realmy", t + 3, 20, "165:120:300")
	Trade(CEDRIC, "Cedric-Realmy", t + 4, 60, "165:180:300")
	List(BOB, "Bob-Realmy", 165, t + 5, { LEATHER[1], LEATHER[2], LEATHER[3] })
	List(BOB, "Bobby-Realmy", 165, t + 6, { LEATHER[1] })
	List(BOB, "Bo-Realmy", 165, t + 7, { LEATHER[1] })
	List(CEDRIC, "Cedric-Realmy", 165, t + 8, { LEATHER[1], LEATHER[2] })
	Pass(me, 30) -- (and Battle.net shows Bob and Cedric online: their full names)

	local function plain(text)
		return ((text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
	end
	local function Hover(item, tooltip)
		env.GameTooltip:SetOwner(env.UIParent)
		env.GameTooltip:SetHyperlink("item:" .. item)
		local found = {}
		for _, line in ipairs(env.TOOLTIP.lines) do
			local text = plain(line)
			if text:find("^Craftable by: ") then
				found.by = text
			elseif text:find("^Reagents: ") then
				found.reagents = text
			end
		end
		return found
	end

	-- The first hover asks for what makes items; Chronicle's next tick reads it from the data.
	check(Hover(5001).by == nil, "the very first hover: nothing yet")
	Pass(me, 1)
	check(Hover(5001).by == "Craftable by: Bob Stone (Leatherworking 300), Bobby ? (Leatherworking 200), Cedric Vale (Leatherworking 180) +2 more",
		"best skill first, the tab's names, at most three, got " .. tostring(Hover(5001).by))
	check(Hover(5002).by == "Craftable by: Bob Stone (Leatherworking 300), Cedric Vale (Leatherworking 180), Anna Brook (Leatherworking 150)",
		"three: no more, mine too, got " .. tostring(Hover(5002).by))
	check(Hover(5004).by == "Craftable by: Anna Brook (Leatherworking 150)", "only my own character")
	check(Hover(5005).by == nil and Hover(118).by == nil and Hover(6948).by == nil, "nobody knows it, or nothing makes it: no line")
	check(Hover(5001).reagents == nil, "no Shift: no reagents")

	-- Shift: the recipe's reagents, by name once the game has them.
	local asked = {}
	local request = env.C_Item.RequestLoadItemDataByID
	env.C_Item.RequestLoadItemDataByID = function(id)
		asked[#asked + 1] = id
	end
	env.STATE.shift = true
	check(Hover(5001).reagents == "Reagents: ... x2, ... x1", "names not loaded yet, got " .. tostring(Hover(5001).reagents))
	check(#asked == 2, "and asked for, once each, got " .. #asked)
	env.ITEMS[2318], env.ITEMS[2320] = { name = "Light Leather", quality = 1 }, { name = "Coarse Thread", quality = 1 }
	check(Hover(5001).reagents == "Reagents: Light Leather x2, Coarse Thread x1", "then by name, got " .. tostring(Hover(5001).reagents))
	check(Hover(5003).reagents == "Reagents: Light Leather x4, Coarse Thread x1", "each recipe its own")
	local recipe = R.MakerRecipe(R.Makers(5007)[1])
	local parsed = R.RecipeOf(LEATHER[7])
	check(recipe.spell == parsed.spell and recipe.item == 5007 and recipe.low == parsed.low and recipe.cat == parsed.cat
		and recipe.reagents[1].item == 2318 and recipe.reagents[1].n == parsed.reagents[1].n, "a maker's recipe is the data's")
	env.STATE.shift = false
	env.C_Item.RequestLoadItemDataByID = request

	-- A hover is a lookup: nothing is built again until a list or a skill changes.
	local people = R.People
	local calls = 0
	R.People = function(line)
		calls = calls + 1
		return people(line)
	end
	for _ = 1, 20 do
		Hover(5001)
		Hover(5005)
	end
	check(calls == 0, "the same hovers again: kept, got " .. calls .. " lookups of people")
	Trade(CEDRIC, "Cedric-Realmy", t + 20, 60, "165:310:310")
	Pass(me, 2)
	check(Hover(5001).by:find("^Craftable by: Cedric Vale %(Leatherworking 310%), Bob Stone") ~= nil, "a skill went up: the line follows")
	check(calls > 0, "built anew once")
	R.People = people

	-- Two recipes make an item (another profession): each character once, by its best.
	local data = {}
	for k, v in pairs(DATA) do
		data[k] = v
	end
	data.recipes = { [171] = DATA.recipes[171], [165] = DATA.recipes[165], [185] = DATA.recipes[185] .. ";3372:5001:1:::1:15:30::6889*2" }
	me.ns.RecipeData = data
	Trade(BOB, "Bo-Realmy", t + 21, 20, "165:120:300,185:250:300")
	List(BOB, "Bo-Realmy", 185, t + 22, { 3372 })
	Trade(CEDRIC, "Cedric-Realmy", t + 23, 60, "165:310:310,185:50:75")
	List(CEDRIC, "Cedric-Realmy", 185, t + 24, { 3372 })
	Pass(me, 2)
	Hover(5001)
	Pass(me, 1)
	check(Hover(5001).by == "Craftable by: Cedric Vale (Leatherworking 310), Bob Stone (Leatherworking 300), Bo ? (Cooking 250) +2 more",
		"new data: read anew; Bo by her better profession, Cedric once, got " .. tostring(Hover(5001).by))
	me.ns.RecipeData = DATA
	Hover(5002)
	Pass(me, 1)

	-- The setting; tooltips that aren't the game's own.
	Set(me, "craftTooltip", false)
	check(Hover(5002).by == nil, "switched off: no line")
	Set(me, "craftTooltip", true)
	check(Hover(5002).by ~= nil, "on again")
	local added = 0
	local other = { AddLine = function() added = added + 1 end }
	for _, call in ipairs(env.TOOLTIP_POSTCALLS) do
		call[2](other, { type = 0, id = 5002 })
	end
	check(added == 0, "a tooltip of someone else's (a comparison, the Professions tab's own): nothing added")
	Stop(me)
end
