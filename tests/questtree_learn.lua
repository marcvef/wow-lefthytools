-- Questtree's learning (Questtree/Learn.lua) and sharing (Beacon/QuestShare.lua): givers and enders (NPCs,
-- objects, items) with where I stood, titles and levels, prerequisites inferred from offers and turn-ins
-- (strong, weak, proven wrong), what the data knows already, secrets, the learn switch, pruning and feeding
-- at login; friends' progress on request, learned records passed on between two current builds (paced,
-- only once each way), and an older build that gets nothing; Beacon's limits and fights.
--
-- Every client here is a game of its own, like in recipes.lua: mock.lua and the addon in an environment of
-- their own, with their own clock, Battle.net friends and saved variables.
--
-- Stand-ins (until the lead merges the other parts): the Questtree module (Questtree.lua) with
-- `learn = true`, `friends = true`, and Data.lua's Q.SetTestData / Q.Quest / Q.IsLoaded / Q.AddLearned and
-- Engine's Q.Chain, each only where the addon doesn't have it; Q.AddLearned is wrapped to see what it gets.
-- The game's quest dialogs, gossip and completed quests are the test's too (UnitGUID/UnitName "npc",
-- C_GossipInfo, the greeting functions, C_QuestLog.IsQuestFlaggedCompleted).
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

local NEW, OLD = "0.7.0-69-gabc1234", "0.7.0-68-gabc1234" -- the first build that reads Questtree's words, the one before
-- What an older build doesn't have (its client here runs without them).
local OLD_FILES = { ["Modules/Beacon/QuestShare.lua"] = true, ["Modules/Questtree/Learn.lua"] = true }
local SAVED = { "LefthyToolsDB", "LefthyToolsChronicleDB", "LefthyToolsBestiaryDB", "LefthyToolsEchoesDB" }

local function Person(id, name, class, tag)
	local first, surname = name:match("^(%S+) (%S+)$")
	return { id = id, name = name, first = first, surname = surname, class = class, tag = tag, guid = "Player-1-" .. id, acct = Hash32(tag:lower()) }
end
local ANNA = Person(11, "Anna Brook", "MAGE", "Annie#1234")
local BOB = Person(12, "Bob Stone", "WARRIOR", "Bobby#2345")
local CEDRIC = Person(13, "Cedric Vale", "ROGUE", "Cedric#3456")
local DORA = Person(14, "Dora Reed", "PRIEST", "Dora#4567") -- on an older build
local EVE = Person(15, "Eve Marsh", "DRUID", "Eve#5678")

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

-- The game's side of quests the mock doesn't have: who I talk to (NPC = { guid, name }), the gossip and
-- greeting lists, the quest dialog's title, quests completed (COMPLETED[id]), quest log levels.
local function Game(env)
	env.NPC, env.COMPLETED, env.DIALOG_TITLE = nil, {}, nil
	env.GOSSIP = { available = {}, active = {} }
	env.GREETING = { available = {}, active = {} }
	local baseGUID, baseName = env.UnitGUID, env.UnitName
	env.UnitGUID = function(unit)
		if unit == "npc" then
			return env.NPC and env.NPC.guid
		end
		return baseGUID(unit)
	end
	env.UnitName = function(unit)
		if unit == "npc" then
			return env.NPC and env.NPC.name
		end
		return baseName(unit)
	end
	local Q = env.C_QuestLog
	Q.IsQuestFlaggedCompleted = function(id) return env.COMPLETED[id] == true end
	Q.GetLogIndexForQuestID = function(id)
		for i, q in ipairs(env.QUESTS) do
			if q.id == id then
				return i
			end
		end
	end
	local baseInfo = Q.GetInfo
	Q.GetInfo = function(i)
		local info, q = baseInfo(i), env.QUESTS[i]
		if info and q then
			info.level = q.level
		end
		return info
	end
	env.C_GossipInfo = {
		GetAvailableQuests = function() return env.GOSSIP.available end,
		GetActiveQuests = function() return env.GOSSIP.active end,
	}
	local G = env.GREETING
	env.GetNumAvailableQuests = function() return #G.available end
	env.GetAvailableQuestInfo = function(i) return false, 0, false, false, G.available[i] and G.available[i].questID end
	env.GetAvailableTitle = function(i) return G.available[i] and G.available[i].title end
	env.GetAvailableLevel = function(i) return G.available[i] and G.available[i].questLevel end
	env.GetNumActiveQuests = function() return #G.active end
	env.GetActiveQuestID = function(i) return G.active[i] and G.active[i].questID end
	env.GetActiveTitle = function(i) return G.active[i] and G.active[i].title, false end
	env.GetActiveLevel = function(i) return G.active[i] and G.active[i].questLevel end
	env.GetTitleText = function() return env.DIALOG_TITLE end
end

local CHAINS = { [101] = { 101, 102, 103 }, [102] = { 101, 102, 103 }, [103] = { 101, 102, 103 } }

-- Stand-ins for the parts of Questtree not in this tree (each only where the addon doesn't have it).
local function Questtree(ns)
	local LT, Q = ns.LT, ns.Questtree
	if not LT:GetModule("questtree") then
		LT:NewModule("questtree", { title = "Questtree", defaults = { learn = true, friends = true } })
	end
	if not Q.SetTestData then
		local data, loaded = {}, false
		Q.SetTestData = function(quests)
			data, loaded = {}, true
			for _, q in ipairs(quests) do
				data[q.id] = q
			end
		end
		Q.Quest = function(id) return data[id] end
		Q.IsLoaded = function() return loaded end
	end
	if not Q.Chain then
		Q.Chain = function(id) return CHAINS[id] or { id } end
	end
	local real = Q.AddLearned
	Q.added = {}
	Q.AddLearned = function(id, fields)
		Q.added[#Q.added + 1] = { id = id, fields = fields }
		if real then
			return real(id, fields)
		end
	end
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
	Game(env)
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
	ns.Questtree = ns.Questtree or {}
	Questtree(ns)
	env.Fire("ADDON_LOADED", "LefthyTools")
	env.Fire("PLAYER_LOGIN")
	env.Fire("PLAYER_ENTERING_WORLD", true, false)
	local c = { who = p, env = env, ns = ns, Q = ns.Questtree, B = ns.Beacon, LT = env.LefthyTools, opts = opts, read = 0,
		before = before, alive = {} }
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

-- Where a client kept a secret in its saved variables (a few paths, or nil).
local function SecretsKept(c)
	local found, seen = {}, {}
	local secret = c.env.issecretvalue
	local function walk(t, path)
		if seen[t] or #found >= 5 then
			return
		end
		seen[t] = true
		for k, v in next, t do
			local at = path .. (secret(k) and "[secret]" or "." .. tostring(k))
			if secret(k) or secret(v) then
				found[#found + 1] = at
			end
			if type(v) == "table" and not secret(v) then
				walk(v, at)
			end
		end
	end
	if type(c.env.LefthyToolsDB) == "table" then
		walk(c.env.LefthyToolsDB, "LefthyToolsDB")
	end
	return found[1] and table.concat(found, ", ")
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
	local kept = SecretsKept(c)
	check(not kept, c.who.name .. "'s client: no secret in the saved variables, found: " .. tostring(kept))
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
local function Pass(c, seconds)
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

-- What went through the world from one to another since mark (world.log), starting with prefix.
local function Logged(from, to, prefix, mark)
	local list = {}
	for i = mark or 1, #world.log do
		local m = world.log[i]
		if m.from == from.id and m.to == to.id and m.data:sub(1, #prefix) == prefix then
			list[#list + 1] = m
		end
	end
	return list
end

---------------------------------------------------------------------------
-- Playing: NPCs, dialogs, accepting and turning in
---------------------------------------------------------------------------

local MARSHAL = { guid = "Creature-0-1-0-0-240-0000ABCD01", name = "Marshal Dughan" }
local THOMAS = { guid = "Creature-0-1-0-0-261-0000ABCD02", name = "Guard Thomas" }
local SMITH = { guid = "Creature-0-1-0-0-262-0000ABCD07", name = "Smith Argus" }
local SHRINE = { guid = "GameObject-0-1-0-0-3000-0000ABCD03", name = "Shrine" }
local SHARER = { guid = "Player-1-77", name = "Someone" }

local function At(c, npc, x, y)
	c.env.NPC = npc
	if x then
		c.env.PLAYER_POS = { x, y }
	end
end
local function Q(id, title, level)
	return { questID = id, title = title, questLevel = level }
end
local function Gossip(c, available, active)
	c.env.GOSSIP.available, c.env.GOSSIP.active = available or {}, active or {}
	c.env.Fire("GOSSIP_SHOW")
end
local function Detail(c, id, title, itemID)
	c.env.DIALOG_QUEST, c.env.DIALOG_TITLE = id, title
	c.env.Fire("QUEST_DETAIL", itemID)
end
local function Accept(c, id, title, level)
	table.insert(c.env.QUESTS, { id = id, title = title, level = level, objectives = {} })
	c.env.Fire("QUEST_ACCEPTED", id)
end
local function TurnIn(c, id)
	c.env.DIALOG_QUEST = id
	c.env.Fire("QUEST_COMPLETE")
	for i = #c.env.QUESTS, 1, -1 do
		if c.env.QUESTS[i].id == id then
			table.remove(c.env.QUESTS, i)
		end
	end
	c.env.COMPLETED[id] = true
	c.env.Fire("QUEST_TURNED_IN", id, 100, 50)
end
local function Frame(c)
	c.env.Advance(1 / 60)
end
local function Store(c)
	return c.Q.LearnedStore()
end
local function Added(c, id, from)
	local list = {}
	for i = from or 1, #c.Q.added do
		if c.Q.added[i].id == id then
			list[#list + 1] = c.Q.added[i].fields
		end
	end
	return list
end
local function Count(t)
	local n = 0
	for _ in pairs(t or {}) do
		n = n + 1
	end
	return n
end

---------------------------------------------------------------------------
section("Questtree learning: givers, enders, levels")
---------------------------------------------------------------------------

local anna = Start(ANNA, { friends = { BOB, DORA } })
check(type(anna.Q.LearnedStore()) == "table" and next(anna.Q.LearnedStore()) == nil, "a new store, empty")

At(anna, MARSHAL, 0.4214, 0.6527)
Gossip(anna, { Q(101, "Wolves", 5) })
check(not Store(anna)[101] and #anna.Q.added == 0, "in the event: only noted (nothing stored or fed yet)")
Frame(anna)
local r = Store(anna)[101]
check(r and r.s and r.s.k == "n" and r.s.i == 240 and r.s.n == "Marshal Dughan" and r.s.m == 1429 and r.s.x == 0.421
	and r.s.y == 0.653, "a quest offered in a gossip: its giver, the NPC with its name and where I stood")
check(r and r.t == "Wolves" and r.l == 5 and type(r.u) == "number" and r.u > 0, "with its title, level and a stamp")
local fed = Added(anna, 101)
check(fed[1] and fed[1].starts and fed[1].starts[1].kind == "npc" and fed[1].starts[1].id == 240
	and fed[1].starts[1].points[1].map == 1429 and fed[1].starts[1].points[1].x == 0.421 and fed[1].zone == 1429
	and fed[1].title == "Wolves" and fed[1].level == 5, "fed into Q.AddLearned in the contract's quest fields")
local stamp = r.u
Gossip(anna, { Q(101, "Wolves", 5) })
Frame(anna)
check(Store(anna)[101].u == stamp, "the same offer again changes nothing")

Detail(anna, 101, "Wolves")
Accept(anna, 101, "Wolves", 5)
Frame(anna)
check(Store(anna)[101].u == stamp, "accepting it: nothing new")

-- The quest log's level when the gossip didn't say: a quest from a greeting.
At(anna, THOMAS, 0.30, 0.20)
anna.env.GREETING.available = { Q(140, "Patrol", nil) }
anna.env.GREETING.active = {}
anna.env.Fire("QUEST_GREETING")
Frame(anna)
r = Store(anna)[140]
check(r and r.s and r.s.i == 261 and r.t == "Patrol" and not r.l, "a greeting's quests: giver and title")
Detail(anna, 140, "Patrol")
Accept(anna, 140, "Patrol", 7)
Frame(anna)
check(Store(anna)[140].l == 7, "the level from the quest log once accepted")

-- The ender: in a gossip's active quests, then the turn-in's dialog.
At(anna, MARSHAL, 0.5, 0.5)
Gossip(anna, {}, { Q(101, "Wolves", 5) })
Frame(anna)
r = Store(anna)[101]
check(r.e and r.e.i == 240 and r.e.x == 0.5, "a quest I can turn in at an NPC: its ender")
TurnIn(anna, 101)
Frame(anna)

---------------------------------------------------------------------------
section("Questtree learning: prerequisites")
---------------------------------------------------------------------------

local mark = #anna.Q.added + 1
Gossip(anna, { Q(102, "Wolves II", 6) })
Frame(anna)
r = Store(anna)[102]
check(r and r.p and r.p[101] == 2, "offered after a turn-in, not before: that turn-in comes first (strong)")
fed = Added(anna, 102, mark)
check(fed[#fed] and fed[#fed].pre and fed[#fed].pre[1] == 101, "fed as a prerequisite")
local opens = Added(anna, 101, mark)
check(opens[1] and opens[1].opens and opens[1].opens[1] == 102, "and the one before leads to it")
Detail(anna, 102, "Wolves II")
Accept(anna, 102, "Wolves II", 6)
Frame(anna)

-- A level-up between two looks tells nothing (the level may have opened it).
At(anna, MARSHAL)
Gossip(anna, {}, { Q(102, "Wolves II", 6) })
Frame(anna)
TurnIn(anna, 102)
anna.env.PLAYER_LEVEL = 20
Gossip(anna, { Q(130, "Bandits", 6) })
Frame(anna)
check(Store(anna)[130] and not Store(anna)[130].p, "a level-up between the looks: no prerequisite")
anna.env.PLAYER_LEVEL = 19

-- The game's follow-up right after a turn-in at an NPC never looked at: strong; later: a hint (weak).
At(anna, SMITH)
Accept(anna, 104, "Sweep", 8)
Frame(anna)
TurnIn(anna, 104)
Frame(anna)
Detail(anna, 105, "Sweep II")
Frame(anna)
check(Store(anna)[105] and Store(anna)[105].p and Store(anna)[105].p[104] == 2, "offered within seconds of a turn-in there: its follow-up")
Accept(anna, 105, "Sweep II", 8)
Frame(anna)
TurnIn(anna, 105)
Frame(anna)
anna.env.Advance(20)
mark = #anna.Q.added + 1
Detail(anna, 106, "Sweep III")
Frame(anna)
r = Store(anna)[106]
check(r and r.p and r.p[105] == 1, "taken a while after a turn-in there: a hint (weak)")
fed = Added(anna, 106, mark)
check(fed[1] and fed[1].pre == nil, "a weak one isn't fed as a prerequisite")
opens = Added(anna, 105, mark)
check(opens[1] and opens[1].opens and opens[1].opens[1] == 106, "only as what the earlier one leads to")

---------------------------------------------------------------------------
section("Questtree learning: objects, items, players, secrets, the switch, the data")
---------------------------------------------------------------------------

At(anna, SHRINE, 0.6, 0.6)
Detail(anna, 107, "The Shrine")
Accept(anna, 107, "The Shrine", 9)
Frame(anna)
r = Store(anna)[107]
check(r and r.s and r.s.k == "o" and r.s.i == 3000 and r.s.n == "Shrine", "an object's quest: the object")
At(anna, nil)
Detail(anna, 108, "A Letter", 5000)
Accept(anna, 108, "A Letter", 9)
Frame(anna)
r = Store(anna)[108]
check(r and r.s and r.s.k == "i" and r.s.i == 5000 and r.s.m == 1429 and r.l == 9, "a quest from an item: the item")
fed = Added(anna, 108)
check(fed[1] and fed[1].starts[1].kind == "item" and fed[1].zone == nil, "fed as an item (no zone from it)")
At(anna, SHARER)
Detail(anna, 109, "Shared")
Accept(anna, 109, "Shared", 9)
Frame(anna)
check(not Store(anna)[109], "a quest a player shared: no giver learned")

local SECRET = anna.env.SECRET
At(anna, { guid = SECRET, name = "Hidden" })
Gossip(anna, { Q(110, "Hidden", 9) })
Frame(anna)
check(not Store(anna)[110], "an NPC whose GUID is secret: nothing")
At(anna, { guid = "Creature-0-1-0-0-300-0000ABCD04", name = SECRET })
Gossip(anna, { Q(111, SECRET, SECRET), { questID = SECRET, title = "x" } })
Frame(anna)
r = Store(anna)[111]
check(r and r.s.i == 300 and r.s.n == nil and r.t == nil and r.l == nil, "a secret name, title, level: left out")
anna.env.Fire("QUEST_ACCEPTED", SECRET)
anna.env.Fire("QUEST_TURNED_IN", SECRET, SECRET, SECRET)
anna.env.PLAYER_POS = { SECRET, SECRET }
At(anna, { guid = "Creature-0-1-0-0-301-0000ABCD05", name = "Pos" })
Gossip(anna, { Q(112, "Secret place", 9) })
Frame(anna)
r = Store(anna)[112]
check(r and r.s.m == 1429 and r.s.x == nil and r.s.y == nil, "a secret position: the map only")
check(#anna.env.ERRORS == 0, "secrets: no errors")
anna.env.PLAYER_POS = { 0.5, 0.5 }

local module = anna.LT:GetModule("questtree")
module.db.learn = false
At(anna, MARSHAL)
Gossip(anna, { Q(113, "Off", 9) })
Frame(anna)
check(not Store(anna)[113], "the module's learn setting off: nothing learned")
module.db.learn = true
module.enabled = false
Gossip(anna, { Q(113, "Off", 9) })
Frame(anna)
check(not Store(anna)[113], "the module off: nothing learned")
module.enabled = true

-- What the data knows: not learned (only once it's loaded: asking must never load it).
anna.Q.SetTestData({
	{ id = 114, title = "Known", source = "classic",
		starts = { { kind = "npc", id = 240, points = { { map = 1429, x = 0.4, y = 0.6 } } } },
		ends = { { kind = "npc", id = 240, points = { { map = 1429, x = 0.4, y = 0.6 } } } } },
	{ id = 115, title = "Half", source = "classic", starts = { { kind = "npc", id = 240, points = { { map = 1429, x = 0.4, y = 0.6 } } } }, ends = {} },
})
Gossip(anna, { Q(114, "Known", 9), Q(115, "Half", 9) })
Frame(anna)
check(not Store(anna)[114] and not Store(anna)[115], "quests whose giver the data knows: not learned")
Gossip(anna, {}, { Q(114, "Known", 9), Q(115, "Half", 9) })
Frame(anna)
check(not Store(anna)[114] and Store(anna)[115] and Store(anna)[115].e and not Store(anna)[115].s,
	"an ender the data lacks: learned, and only that")

---------------------------------------------------------------------------
section("Questtree learning: kept, checked and fed at login, pruned")
---------------------------------------------------------------------------

local before = Count(Store(anna))
anna = Reload(anna)
check(Count(Store(anna)) == before and Store(anna)[102].p[101] == 2, "kept over a /reload, account-wide")
check(#anna.Q.added == 0, "fed after login, not in it")
Frame(anna)
local fedAt = {}
for _, a in ipairs(anna.Q.added) do
	fedAt[a.id] = true
end
check(Count(fedAt) == before, "every record fed into Q.AddLearned (" .. Count(fedAt) .. " of " .. before .. ")")
Leftovers(anna)

local cedricSaved = { LefthyToolsDB = { world = "release", questtree = { learned = {}, share = { seq = 1700, epoch = "0badf00d" } } } }
do
	local learned = cedricSaved.LefthyToolsDB.questtree.learned
	for i = 1, 1600 do
		learned[1000 + i] = { u = i, s = { k = "n", i = 50 + i % 7, n = "Npc", m = 1429, x = 0.5, y = 0.5 }, t = "Q" .. i }
	end
	learned[5001] = { u = "x", s = {} } -- (broken)
	learned[5002] = { u = 5, s = { k = "z", i = 1 } }
	learned[5003] = { u = 99999, e = { k = "n", i = 9 } } -- (a stamp from the future)
	learned["x"] = { u = 1 }
end
local cedric = Start(CEDRIC, { friends = { EVE, DORA }, fake = true, saved = cedricSaved })
local cs = Store(cedric)
check(Count(cs) == 1350, "over 1500 records: the oldest changes go, down to 1350, got " .. Count(cs))
check(not cs[1001] and cs[1600] and not cs[5001] and not cs[5002] and not cs["x"], "the oldest gone; broken ones too")
check(cs[5003] and cs[5003].u > 1700, "a stamp from the future: stamped anew (so it's sent)")
cedric.env.Advance(1 / 60)
check(#cedric.Q.added <= 60, "fed a few a frame, got " .. #cedric.Q.added)
cedric.env.Advance(2)
check(#cedric.Q.added >= 1350, "then all of them")

---------------------------------------------------------------------------
section("Questtree sharing: two current builds, an older one")
---------------------------------------------------------------------------

local logFrom = #world.log + 1
local bob = Start(BOB, { friends = { ANNA, DORA } })
local dora = Start(DORA, { friends = { ANNA, BOB }, version = OLD })
check(not dora.ns.Questtree.LearnedStore, "the older build has none of it")
local annaCount = Count(Store(anna))
Run(60, function() return Count(Store(bob)) >= annaCount end)
check(Count(Store(bob)) == annaCount, "Bob got every record Anna learned (" .. Count(Store(bob)) .. " of " .. annaCount .. ")")
r = Store(bob)[102]
check(r and r.s and r.s.i == 240 and r.s.x == 0.5 and r.p and r.p[101] == 2 and r.t == "Wolves II" and r.l == 6,
	"a record whole: giver, place, prerequisite, title, level")
check(Store(bob)[106].p[105] == 1, "a weak one stays weak")
check(Store(bob)[111] and Store(bob)[111].s.n == nil, "and what's unknown stays unknown")
check(r and r.f == ANNA.acct, "kept as Anna's (not sent back to her)")
fed = Added(bob, 102)
check(fed[1] and fed[1].pre and fed[1].pre[1] == 101, "merged into Bob's data (Q.AddLearned)")
local records = Logged(ANNA, BOB, "B2;qr;", logFrom)
local busiest = 0
for i, m in ipairs(records) do
	local n = 0
	for j = i, #records do
		if records[j].at - m.at < 3 - 1e-6 then
			n = n + 1
		end
	end
	busiest = math.max(busiest, n)
end
check(#records >= 10 and busiest <= 16, "paced: about 4 records a second (at most 16 in any 3 s), got " .. busiest)
check(#Logged(ANNA, DORA, "B2;q", logFrom) == 0 and #Logged(BOB, DORA, "B2;q", logFrom) == 0,
	"the older build gets none of Questtree's words")

-- Once each way: Bob holds Anna's records now, and offers what he has; nothing comes back to her.
local annaSeq = anna.Q.LearnedMeta().seq
logFrom = #world.log + 1
Run(70)
check(#Logged(BOB, ANNA, "B2;qr;", logFrom) == 0, "Anna's own records aren't sent back to her")
check(anna.Q.LearnedMeta().seq == annaSeq, "and nothing changes in her store")

-- Something new on Bob's side reaches Anna, alone.
At(bob, { guid = "Creature-0-1-0-0-777-0000ABCD06", name = "Farmer" }, 0.2, 0.8)
Gossip(bob, { Q(120, "Crops", 10) })
Run(1)
logFrom = #world.log + 1
Run(80, function() return Store(anna)[120] ~= nil end)
check(Store(anna)[120] and Store(anna)[120].s.i == 777 and Store(anna)[120].f == BOB.acct, "a new record of Bob's reaches Anna")
Run(2)
check(#Logged(BOB, ANNA, "B2;qr;", logFrom) == 1, "only that one")

---------------------------------------------------------------------------
section("Questtree sharing: friends' progress")
---------------------------------------------------------------------------

-- Anna: 101 done, 102 in her log, 103 not; 140 ready to turn in (complete).
anna.env.COMPLETED[101] = true
anna.env.QUESTS = { { id = 102, title = "Wolves II", level = 6, objectives = { { text = "Wolves slain", finished = false } } },
	{ id = 140, title = "Patrol", level = 7, objectives = {}, complete = true } }
logFrom = #world.log + 1
check(bob.Q.RequestFriendProgress(102), "a window asks about a quest")
Run(1)
for i = 1, 10 do
	bob.Q.RequestFriendProgress(150 + i) -- (a window redrawn many times, another quest each time)
end
Run(1)
check(#Logged(BOB, ANNA, "B2;qp;", logFrom) == 1, "at most one request every 2 s")
check(bob.Q.FriendStatus(ANNA.id, 101) == "done" and bob.Q.FriendStatus(ANNA.id, 102) == "active"
	and bob.Q.FriendStatus(ANNA.id, 103) == "none", "Anna's progress on the quest and its chain")
Run(2)
local asks = Logged(BOB, ANNA, "B2;qp;", logFrom)
check(#asks == 2 and asks[2].data:match(";160$"), "then the latest one")
check(#Logged(BOB, DORA, "B2;qp;", logFrom) == 0, "the older build isn't asked")
local friends = bob.Q.Friends(102)
check(#friends == 1 and friends[1].name == ANNA.name and friends[1].status == "active" and friends[1].classFile == "MAGE",
	"Q.Friends: who has it, and how far")
local p = bob.Q.FriendProgress(ANNA.id)
check(p and p.quests[101] == "done" and p.name == ANNA.name and bob.Q.FriendProgress()[ANNA.id] == p, "Q.FriendProgress, one or all")
check(bob.Q.RequestFriendProgress(140), "asked about another")
local told = 0
bob.Q.OnFriendProgress(function() told = told + 1 end)
Run(3)
check(bob.Q.FriendStatus(ANNA.id, 140) == "ready" and told >= 1, "ready to turn in; the windows are told")
logFrom = #world.log + 1
bob.Q.RequestFriendProgress(140)
Run(3)
check(#Logged(BOB, ANNA, "B2;qp;", logFrom) == 0, "the same quest again a moment later: not asked again")

-- Anna's friends setting off: she answers "not shared" and offers nothing.
anna.LT:GetModule("questtree").db.friends = false
bob.Q.RequestFriendProgress(101)
Run(3)
check(not bob.Q.FriendProgress(ANNA.id).shares and bob.Q.FriendStatus(ANNA.id, 101) == "done", "not shared: said so (what was known stays)")
check(not anna.Q.RequestFriendProgress(102), "and she doesn't ask")
anna.LT:GetModule("questtree").db.friends = true

---------------------------------------------------------------------------
section("Questtree learning: a prerequisite proven wrong, passed on")
---------------------------------------------------------------------------

-- Anna's alt hasn't done 101, yet Marshal offers it 102: 101 wasn't needed after all.
anna = Reload(anna) -- (a new session's COMPLETED is empty: another character of hers)
Run(20)
At(anna, MARSHAL)
Gossip(anna, { Q(102, "Wolves II", 6) })
Run(1)
r = Store(anna)[102]
check(r and not r.p and r.x and r.x[101], "offered without it: not a prerequisite")
Run(80, function() return Store(bob)[102].x ~= nil end)
check(Store(bob)[102].x and Store(bob)[102].x[101] and not Store(bob)[102].p, "passed on to Bob")
Stop(dora)

---------------------------------------------------------------------------
section("Questtree sharing: limits, fights, older builds (friends the test plays)")
---------------------------------------------------------------------------

local m0 = Mark(cedric)
Meet(cedric, EVE, NEW)
Meet(cedric, DORA, OLD)
Say(cedric, EVE, "B2;qp;1;1001,1600")
Pass(cedric, 0.25)
for i = 2, 5 do
	Say(cedric, EVE, "B2;qp;" .. i .. ";1001,1600")
end
Pass(cedric, 0.25)
check(#Sent(cedric, EVE, m0, "B2;qs;") == 1, "a friend's requests: one answer at once")
Pass(cedric, 1.5)
local answers = Sent(cedric, EVE, m0, "B2;qs;")
check(#answers == 2 and answers[2] == "B2;qs;5;nn", "then the latest, a second later, got " .. table.concat(answers, " | "))
check(#Sent(cedric, EVE, m0, "B2;qo;") == 1, "Eve is offered Cedric's records")
check(#Sent(cedric, DORA, m0, "B2;q") == 0, "Dora (older) gets nothing")
Say(cedric, DORA, "B2;qp;1;1001")
Pass(cedric, 2)
check(#Sent(cedric, DORA, m0, "B2;q") == 0, "and isn't answered")

-- In a fight: nothing goes (it waits for the end).
cedric.env.EnterCombat()
m0 = Mark(cedric)
Say(cedric, EVE, "B2;qp;9;1001")
Say(cedric, EVE, "B2;qq;0badf00d;0;" .. EVE.acct)
Pass(cedric, 5)
check(#Sent(cedric, EVE, m0, "B2;q") == 0, "in a fight: no answer, no records")
cedric.env.LeaveCombat()
Pass(cedric, 3)
check(#Sent(cedric, EVE, m0, "B2;qs;9;") == 1 and #Sent(cedric, EVE, m0, "B2;qr;") >= 1, "after it: both")
local served = #Sent(cedric, EVE, m0, "B2;qr;")
check(served <= 3 * 4 + 4, "a few records a second, got " .. served)
Pass(cedric, 40)
local all = Sent(cedric, EVE, m0, "B2;qr;")
local ends = Sent(cedric, EVE, m0, "B2;qe;")
check(#all == 100 and ends[1] and ends[1]:match("^B2;qe;0badf00d;%d+;100$"), "an answer holds 100 records, then its end, got "
	.. #all .. " and " .. tostring(ends[1]))
local biggest = 0
for _, msg in ipairs(all) do
	biggest = math.max(biggest, #msg)
end
check(biggest <= 255, "every record within 255 bytes")
local id1, rec1 = cedric.Q.DecodeLearned(all[1]:sub(#"B2;qr;" + 1))
check(id1 and rec1 and rec1.s and rec1.s.n == "Npc" and rec1.t, "a record reads back")

-- Broken messages: ignored, no error.
for _, bad in ipairs({ "B2;qr;abc;;;;;;", "B2;qr;1;;z1:::;;;;", "B2;qs;1;xyz", "B2;qp;1;", "B2;qe;zz;1;1", "B2;qz;1",
	"B2;qr;1;;n1:1429:2000:5:Name;;;;", "B2;qr;1;;n1::500:500:;;;;" }) do
	Say(cedric, EVE, bad)
end
Pass(cedric, 2)
check(#cedric.env.ERRORS == 0, "broken messages: ignored")
check(not cedric.Q.DecodeLearned("1;;n1:1429:2000:5:Name;;;;") and not cedric.Q.DecodeLearned("1;;n1::500:500:;;;;"),
	"a place off the map, or a point without a map: not a record")
local _, odd = cedric.Q.DecodeLearned("7;;n5:1429:500:500:|cffff0000Red|r;;;;Title|r")
check(odd and odd.s.n == "Red" and odd.t == "Title", "a friend's name and title: escape sequences removed")

Pass(cedric, 60) -- (a quiet minute: Beacon's count starts anew)

-- Beacon's limit: at most 300 of Questtree's messages a minute from one friend.
local got = 0
local receive = cedric.B.ReceiveQuesttree
cedric.B.ReceiveQuesttree = function(...)
	got = got + 1
	return receive(...)
end
for _ = 1, 25 do
	for _ = 1, 16 do
		Say(cedric, EVE, "B2;qo;" .. EVE.acct .. ";0000beef;5")
	end
	Pass(cedric, 1)
end
check(got == 300, "Beacon takes 300 a minute from one friend, got " .. got)
cedric.B.ReceiveQuesttree = receive

Leftovers(cedric)
Stop(bob)
Stop(anna)
