local _, ns = ...
local Q = ns.Lodestar or {}; ns.Lodestar = Q

-- Lodestar's engine (docs/lodestar.md, Engine): where a quest stands for me or a friend, what's
-- missing before it, what it leads to, its whole chain and its step in it, what's next for me, what I
-- can take nearby, a zone's count, the race rule (Q.RaceAllowed) and quest difficulty colours
-- (Q.LevelColor). It reads the data
-- (Data.lua) and my progress: completed quests (C_QuestLog.GetAllCompletedQuestIDs, read once and
-- kept, a turned-in quest added when it happens) and the quest log. Answers are kept until the data
-- or my progress changes. Nothing runs before the first question: the events are registered then,
-- and their handlers only note what changed.

local CLASS_IDS = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }
local RACE_IDS = { Human = 1, Orc = 2, Dwarf = 3, NightElf = 4, Scourge = 5, Undead = 5, Tauren = 6, Gnome = 7, Troll = 8 }
local CHAIN_LIMIT = 400 -- quests in one chain at most (a safety net: the biggest classic one has ~120)

local done = {}           -- my completed quests (set), valid while doneRead
local doneRead = false
local turnedIn = {}       -- turned in since the last loading screen (the server's list may not have them yet)
local active = {}         -- my quest log (set), valid while activeRead
local activeRead = false
local progress = 0        -- goes up when my progress changes
local listening = false
local statusOf, statusData, statusProgress = {}, nil, nil -- Q.Status cache (mine), and the data and progress it's for
local chainOf, chainKey = {}, nil   -- Q.Chain cache, per data
local nextList, nextKey             -- Q.Next cache

Q.progressGen = 0

local function Bump()
	progress = progress + 1
	Q.progressGen = progress
end

local function Readable(v)
	return v ~= nil and not (issecretvalue and issecretvalue(v))
end

-- ---------------------------------------------------------------- my progress

local function OnEvent(_, event, id)
	if event == "QUEST_TURNED_IN" then
		if type(id) == "number" and Readable(id) then done[id], turnedIn[id] = true, true end
		activeRead = false
		Bump()
	elseif event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" or event == "QUEST_LOG_UPDATE" then
		activeRead = false -- (read again on the next question; a change there bumps progress)
	elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
		doneRead, activeRead, turnedIn = false, false, {}
		Bump()
	else -- a level, a skill, a reputation
		Bump()
	end
end

-- The events, registered with the first question (nothing before a Lodestar window opens).
local function Listen()
	if listening or not CreateFrame then return end
	listening = true
	local f = CreateFrame("Frame")
	for _, event in ipairs({ "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_LOG_UPDATE", "PLAYER_LOGIN",
		"PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "UPDATE_FACTION" }) do
		pcall(f.RegisterEvent, f, event)
	end
	f:SetScript("OnEvent", OnEvent)
end

local function ReadDone()
	if doneRead then return end
	doneRead = true
	local log = C_QuestLog
	if log and log.GetAllCompletedQuestIDs then
		local ok, list = pcall(log.GetAllCompletedQuestIDs)
		if ok and type(list) == "table" then
			local set = {}
			for _, id in ipairs(list) do
				if type(id) == "number" and Readable(id) then set[id] = true end
			end
			for id in pairs(turnedIn) do set[id] = true end
			done = set
		end
	end
end

local function ReadActive()
	if activeRead then return end
	activeRead = true
	local set, log = {}, C_QuestLog
	if log and log.GetNumQuestLogEntries and log.GetInfo then
		local ok, n = pcall(log.GetNumQuestLogEntries)
		for i = 1, ok and type(n) == "number" and n or 0 do
			local okInfo, info = pcall(log.GetInfo, i)
			if okInfo and type(info) == "table" and not info.isHeader and type(info.questID) == "number" and Readable(info.questID) then
				set[info.questID] = true
			end
		end
	end
	local changed = false
	for id in pairs(set) do if not active[id] then changed = true end end
	for id in pairs(active) do if not set[id] then changed = true end end
	active = set
	if changed then Bump() end
end

-- Done: completed; also a quest the client says is flagged completed (a quest the list missed).
local function IsDone(id, who)
	if who then return type(who.done) == "table" and who.done[id] == true end
	ReadDone()
	return done[id] == true
end

local function IsActive(id, who)
	if who then return type(who.active) == "table" and who.active[id] == true end
	ReadActive()
	return active[id] == true
end

-- Bit n (1 = the lowest) of a mask, without bit operators (Lua 5.1).
local function HasBit(mask, n)
	return math.floor(mask / 2 ^ (n - 1)) % 2 == 1
end

local function MyFaction()
	local ok, faction = pcall(UnitFactionGroup, "player")
	return ok and type(faction) == "string" and faction or nil
end

-- A race's ID from its file name ("Skyborne" is two races: the side tells which).
local function RaceOfFile(file, faction)
	if file == "Skyborne" then return faction == "Alliance" and 95 or faction == "Horde" and 96 or nil end
	return RACE_IDS[file]
end

local function MyRace()
	local ok, _, file, id = pcall(UnitRace, "player")
	if ok and type(id) == "number" and Readable(id) then return id end
	return ok and Readable(file) and RaceOfFile(file, MyFaction()) or nil
end

-- A race's ID from its name, English (the data's) or the client's (a friend's Battle.net race).
local raceByName
local function RaceOfName(name)
	if type(name) ~= "string" or not Readable(name) then return nil end
	if not raceByName then
		raceByName = {}
		for _, r in ipairs(Q.Races and Q.Races() or {}) do
			if r.name then raceByName[r.name:lower()] = r.id end
			local info = C_CreatureInfo and C_CreatureInfo.GetRaceInfo
			local ok, got = pcall(info or error, r.id)
			if ok and type(got) == "table" and type(got.raceName) == "string" and Readable(got.raceName) then raceByName[got.raceName:lower()] = r.id end
		end
	end
	return raceByName[name:lower()]
end

-- Whether a quest is open to a race (an ID; nil: mine). Its mask's bit; a race new in WoW: Forever (the
-- Skyborne) also where the mask has every classic race of its side. Not known (no mask, a race that
-- isn't playable or not known): yes.
function Q.RaceAllowed(quest, race)
	local q = type(quest) == "table" and quest or Q.Quest and Q.Quest(quest)
	local mask = q and tonumber(q.races)
	if not mask or mask <= 0 then return true end
	if race == nil then race = MyRace() end
	local info = race and Q.RaceInfo and Q.RaceInfo(race)
	if not info then return true end
	if HasBit(mask, info.bit + 1) then return true end
	if info.classic then return false end
	local any = false
	for _, r in ipairs(Q.Races()) do
		if r.classic and r.faction == info.faction then
			if not HasBit(mask, r.bit + 1) then return false end
			any = true
		end
	end
	return any
end

local function MyClass()
	local ok, _, file, id = pcall(UnitClass, "player")
	if ok and type(id) == "number" and Readable(id) then return id end
	return ok and CLASS_IDS[file] or nil
end

local function MyLevel()
	local ok, level = pcall(UnitLevel, "player")
	return ok and type(level) == "number" and Readable(level) and level or nil
end

-- Whether a quest's level scales to the player's (a level of -1 or 0, or the data's flag).
local function Scales(q)
	return q.scales == true or (tonumber(q.level) or 1) <= 0
end

-- A quest's level to compare with mine (mine: my level, nil if not known): its level; one that scales
-- to me counts as mine; without a level its minimum level.
local function LevelOf(q, mine)
	if Scales(q) then return mine end
	local level = tonumber(q.level)
	if level and level > 0 then return level end
	level = tonumber(q.minLevel)
	return level and level > 0 and level or nil
end

-- A profession's rank (skill line), nil if not known.
local function SkillRank(line)
	if not (GetProfessions and GetProfessionInfo) then return nil end
	local list = { pcall(GetProfessions) }
	if not table.remove(list, 1) then return nil end
	for i = 1, 5 do
		local index = list[i]
		if index then
			local ok, _, _, rank, _, _, _, skillLine = pcall(GetProfessionInfo, index)
			if ok and skillLine == line and type(rank) == "number" then return rank end
		end
	end
	return 0 -- (a profession I don't have)
end

-- My standing with a faction (reputation points, as the data's minimum), nil if not known.
local function Standing(faction)
	if C_Reputation and C_Reputation.GetFactionDataByID then
		local ok, data = pcall(C_Reputation.GetFactionDataByID, faction)
		if ok and type(data) == "table" and type(data.currentStanding) == "number" then return data.currentStanding end
	end
	if GetFactionInfoByID then
		local ok, name, _, _, _, _, value = pcall(GetFactionInfoByID, faction)
		if ok and name and type(value) == "number" then return value end
	end
	return nil
end

-- For this character (me: who nil, or a friend's progress table)? Race, class, faction and a
-- profession (mine: one I don't have isn't for me; a rank too low or a reputation too low only
-- blocks it, Gate); what isn't known counts as yes. Not for me: false and why ("race", "class",
-- "faction", "skill").
local function ForMe(q, who)
	local race, class, faction
	if who then
		faction = who.faction
		race = tonumber(who.race) or RaceOfFile(who.raceFile, faction) or RaceOfName(who.race)
		class = tonumber(who.class) or CLASS_IDS[who.classFile]
	else
		race, class, faction = MyRace(), MyClass(), MyFaction()
	end
	if q.races and race and not Q.RaceAllowed(q, race) then return false, "race" end
	if q.classes and class and not HasBit(q.classes, class) then return false, "class" end
	if q.faction and faction and (faction == "Alliance" or faction == "Horde") and q.faction ~= faction then return false, "faction" end
	if not who and q.skill and SkillRank(q.skill.id) == 0 and (q.skill.value or 0) > 0 then return false, "skill" end
	return true
end

-- What besides quests keeps me from a quest for me: a profession's rank or a reputation too low
-- (nil: nothing, or a friend's: not known).
local function Gate(q, who)
	if who then return nil end
	if q.skill then
		local rank = SkillRank(q.skill.id)
		if rank and rank > 0 and rank < (q.skill.value or 0) then return { kind = "skill", id = q.skill.id, value = q.skill.value, have = rank } end
	end
	if q.rep then
		local standing = Standing(q.rep.faction)
		if standing and standing < (q.rep.min or 0) then return { kind = "rep", faction = q.rep.faction, min = q.rep.min, have = standing } end
	end
	return nil
end

-- Closed by another: an exclusive one done or taken, or the quest a breadcrumb leads to (true and
-- that quest).
local function Closed(q, who)
	for _, other in ipairs(q.excl or {}) do
		if IsDone(other, who) or IsActive(other, who) then return true, other end
	end
	local target = q.breadcrumbFor
	if target and (IsDone(target, who) or IsActive(target, who)) then return true, target end
	return false
end

local function NeedsMet(q, who)
	for _, p in ipairs(q.pre or {}) do
		if not IsDone(p, who) then return false end
	end
	if q.preAny and #q.preAny > 0 then
		local any = false
		for _, p in ipairs(q.preAny) do
			if IsDone(p, who) then any = true; break end
		end
		if not any then return false end
	end
	if q.preActive and not IsActive(q.preActive, who) then return false end
	return true
end

local function Compute(id, who)
	local q = Q.Quest(id)
	if not q then return nil end
	if IsDone(id, who) then return "done" end
	if IsActive(id, who) then return "active" end
	if not ForMe(q, who) or Closed(q, who) then return "other" end
	if not NeedsMet(q, who) or Gate(q, who) then return "locked" end
	local level = who and tonumber(who.level) or not who and MyLevel()
	if level and q.minLevel and level < q.minLevel then return "level" end
	return "available"
end

-- "done" | "active" | "available" | "locked" | "level" | "other" for me (who nil) or a friend's
-- progress (who: { done = { [id] = true }, active = { [id] = true }, level, faction, race (raceID) or
-- raceFile, class (classID) or classFile }); nil for a quest the data doesn't know. "other" is also a
-- quest closed by another (an exclusive one done or taken, a breadcrumb's quest).
function Q.Status(id, who)
	id = tonumber(id)
	if not id then return nil end
	Listen()
	if who then return Compute(id, who) end
	ReadActive() -- (a change bumps progress before the cache is checked)
	ReadDone()
	if statusData ~= Q.dataGen or statusProgress ~= progress then statusOf, statusData, statusProgress = {}, Q.dataGen, progress end
	local s = statusOf[id]
	if s == nil then
		s = Compute(id) or false
		statusOf[id] = s
	end
	return s or nil
end

-- Why a quest is "other" for me: "closed" and the quest that closed it (an exclusive one taken, the
-- quest a breadcrumb leads to), or "race", "class", "faction", "skill" (a profession I don't have);
-- nil when it isn't "other".
function Q.WhyOther(id)
	id = tonumber(id)
	local q = id and Q.Quest(id)
	if not q or Q.Status(id) ~= "other" then return nil end
	local ok, why = ForMe(q)
	if not ok then return why end
	local _, by = Closed(q)
	return "closed", by
end

-- What besides quests blocks a quest of mine: { kind = "skill", id, value, have } (a profession's
-- rank) or { kind = "rep", faction, min, have } (a reputation), nil if nothing.
function Q.Needs(id)
	id = tonumber(id)
	local q = id and Q.Quest(id)
	return q and Gate(q) or nil
end

-- An event quest: only takeable while its holiday or event is on (Seasonal, Lunar Festival, the
-- Darkmoon Faire, ...: the data's flag e).
function Q.IsEvent(id)
	local q = tonumber(id) and Q.Quest(id)
	return q and q.event == true or false
end

-- Within my levels, what the windows show unless asked for all levels: a quest in my log, or one I can
-- take now by its levels and that's worth it: its minimum level reached, not grey for me (Q.IsTrivial)
-- and not red, at most RANGE_RED levels above mine (a level that scales to me counts as mine; no level
-- known at all: no, those are Forever's untitled hidden quests); never an event quest that isn't in my
-- log (its holiday may not be on). What else stands in its way is Q.Status's.
local RANGE_RED = 4
Q.RANGE_RED = RANGE_RED
function Q.InRange(id)
	id = tonumber(id)
	local q = id and Q.Quest(id)
	if not q then return false end
	if Q.Status(id) == "active" then return true end
	if q.event then return false end
	local my = MyLevel()
	if not my then return true end
	local need = tonumber(q.minLevel)
	if need and need > my then return false end
	if Q.IsTrivial(id) then return false end
	local level = LevelOf(q, my)
	return level ~= nil and level <= my + RANGE_RED
end

-- For my level, what the windows count as that: in my log, or one I can take now ("available") within my
-- levels (Q.InRange). Not a quest that needs another first, one too high or an event's.
function Q.ForMyLevel(id)
	local s = Q.Status(id)
	return s == "active" or (s == "available" and Q.InRange(id))
end

-- The best of several quests one of which is needed: one in my log, then one I can take, then
-- one for me, the lowest level.
local RANK = { active = 1, available = 2, locked = 3, level = 4, done = 5, other = 6 }
local function Best(list, who)
	local best, bestRank, bestLevel
	for _, id in ipairs(list) do
		local q = Q.Quest(id)
		local rank = RANK[Q.Status(id, who) or "other"] or 7
		local mine
		if who then mine = tonumber(who.level) else mine = MyLevel() end
		local level = q and LevelOf(q, mine) or 99
		if not best or rank < bestRank or (rank == bestRank and (level < bestLevel or (level == bestLevel and id < best))) then
			best, bestRank, bestLevel = id, rank, level
		end
	end
	return best
end

-- What's missing before a quest, walked back through its chain (across zones): { { id, status,
-- reason } }, the first one to do first. reason: "done" (must be completed), "any" (one of several:
-- this one, the best of them), "log" (must be in the quest log).
function Q.Missing(id, who)
	local out, seen = {}, {}
	local function add(other, reason)
		out[#out + 1] = { id = other, status = Q.Status(other, who), reason = reason }
	end
	local function walk(qid)
		if seen[qid] then return end
		seen[qid] = true
		local q = Q.Quest(qid)
		if not q then return end
		for _, p in ipairs(q.pre or {}) do
			if not IsDone(p, who) and not seen[p] then
				walk(p)
				add(p, "done")
			end
		end
		if q.preAny and #q.preAny > 0 then
			local any = false
			for _, p in ipairs(q.preAny) do
				if IsDone(p, who) then any = true end
			end
			local pick = not any and Best(q.preAny, who)
			if pick and not seen[pick] then
				walk(pick)
				add(pick, "any")
			end
		end
		local log = q.preActive
		if log and not IsActive(log, who) and not seen[log] then
			if not IsDone(log, who) then walk(log) end
			add(log, "log")
		end
	end
	id = tonumber(id)
	if id then walk(id) end
	return out
end

-- The quests this one leads to (shared, never written by callers).
function Q.Opens(id)
	local q = Q.Quest(id)
	return q and q.opens or {}
end

-- The neighbours of a quest in its chain: what it needs, leads to, closes.
local function Neighbours(q)
	local list = {}
	for _, k in ipairs({ "pre", "preAny", "opens", "excl" }) do
		for _, other in ipairs(q[k] or {}) do list[#list + 1] = other end
	end
	if q.preActive then list[#list + 1] = q.preActive end
	if q.breadcrumbFor then list[#list + 1] = q.breadcrumbFor end
	return list
end

-- The whole chain a quest is in, every quest after what it needs (the lowest level first where
-- there's a choice): a list of IDs; just { id } for a quest on its own.
function Q.Chain(id)
	id = tonumber(id)
	local q = id and Q.Quest(id)
	if not q then return {} end
	if chainKey ~= Q.dataGen then chainOf, chainKey = {}, Q.dataGen end
	if chainOf[id] then return chainOf[id] end
	-- The quests connected to it.
	local members, queue, head = { [id] = true }, { id }, 1
	while queue[head] and #queue < CHAIN_LIMIT do
		local cur = Q.Quest(queue[head])
		head = head + 1
		for _, other in ipairs(cur and Neighbours(cur) or {}) do
			if not members[other] and Q.Quest(other) then
				members[other] = true
				queue[#queue + 1] = other
			end
		end
	end
	-- In order: a quest once everything before it is placed (Kahn's), the lowest level first.
	local before, count = {}, {}
	for m in pairs(members) do before[m], count[m] = {}, 0 end
	local function edge(a, b) -- a before b
		if a ~= b and members[a] and members[b] and not before[a][b] then
			before[a][b] = true
			count[b] = count[b] + 1
		end
	end
	for m in pairs(members) do
		local mq = Q.Quest(m)
		for _, p in ipairs(mq.pre) do edge(p, m) end
		for _, p in ipairs(mq.preAny) do edge(p, m) end
		if mq.preActive then edge(mq.preActive, m) end
		for _, o in ipairs(mq.opens) do edge(m, o) end
	end
	local function level(m)
		local mq = Q.Quest(m)
		return mq.level or mq.minLevel or 0
	end
	local function earlier(a, b)
		if level(a) ~= level(b) then return level(a) < level(b) end
		return a < b
	end
	local order, placed = {}, {}
	while #order < #queue do
		local ready = {}
		for m in pairs(members) do
			if not placed[m] and count[m] <= 0 then ready[#ready + 1] = m end
		end
		if #ready == 0 then -- (a loop in the data: the lowest of the rest goes next)
			for m in pairs(members) do
				if not placed[m] then ready[#ready + 1] = m end
			end
		end
		table.sort(ready, earlier)
		local m = ready[1]
		placed[m] = true
		order[#order + 1] = m
		for b in pairs(before[m]) do count[b] = count[b] - 1 end
	end
	for _, m in ipairs(order) do chainOf[m] = order end
	return order
end

-- Which step of its chain a quest is: step, total, the chain's title (its first quest's, the data's
-- English one), the first quest's ID. A step is a column: one more than the longest way to it inside
-- the chain (quests side by side share a step); total: the last step. A quest on its own: 1, 1.
local stepOf, stepKey = {}, nil
function Q.ChainStep(id)
	id = tonumber(id)
	local chain = id and Q.Chain(id)
	if not chain or #chain == 0 then return nil end
	if stepKey ~= Q.dataGen then stepOf, stepKey = {}, Q.dataGen end
	local steps = stepOf[chain]
	if not steps then
		steps = { depth = {}, total = 1 }
		local members, before = {}, {}
		for _, m in ipairs(chain) do members[m], before[m] = true, {} end
		local function edge(a, b) -- a before b
			if members[a] and members[b] and a ~= b then before[b][#before[b] + 1] = a end
		end
		for _, m in ipairs(chain) do
			local mq = Q.Quest(m)
			for _, p in ipairs(mq.pre) do edge(p, m) end
			for _, p in ipairs(mq.preAny) do edge(p, m) end
			if mq.preActive then edge(mq.preActive, m) end
			for _, o in ipairs(mq.opens) do edge(m, o) end
		end
		-- (in the chain's order everything before a quest is placed first; a loop's back edge is left out)
		for _, m in ipairs(chain) do
			local d = 1
			for _, p in ipairs(before[m]) do
				local pd = steps.depth[p]
				if pd and pd + 1 > d then d = pd + 1 end
			end
			steps.depth[m] = d
			if d > steps.total then steps.total = d end
		end
		stepOf[chain] = steps
	end
	local first = Q.Quest(chain[1])
	return steps.depth[id] or 1, steps.total, first and first.title, chain[1]
end

-- How many of a zone's quests (a uiMap; a dungeon by its name) I've done: done, total. Every level;
-- only quests that aren't for me ("other") are left out. Kept per data and progress change.
local countOf, countKey = {}, nil
function Q.ZoneCount(map)
	if map == nil then return 0, 0 end
	local list = type(map) == "string" and Q.DungeonQuests(map) or Q.ZoneQuests(map)
	Listen()
	ReadActive()
	ReadDone()
	local key = Q.dataGen .. ":" .. progress
	if countKey ~= key then countOf, countKey = {}, key end
	local c = countOf[map]
	if not c then
		local doneCount, total = 0, 0
		for _, id in ipairs(list) do
			local s = Q.Status(id)
			if s and s ~= "other" then
				total = total + 1
				if s == "done" then doneCount = doneCount + 1 end
			end
		end
		c = { doneCount, total }
		countOf[map] = c
	end
	return c[1], c[2]
end

-- ---------------------------------------------------------------- difficulty

-- The game's quest difficulty colours (impossible, difficult, fair, easy, trivial). Shared tables.
local DIFFICULTY = {
	impossible = { r = 1, g = 0.1, b = 0.1, hex = "ffff1a1a", key = "impossible" },
	difficult = { r = 1, g = 0.5, b = 0.25, hex = "ffff8040", key = "difficult" },
	fair = { r = 1, g = 0.82, b = 0, hex = "ffffd100", key = "fair" },
	easy = { r = 0.25, g = 0.75, b = 0.25, hex = "ff40bf40", key = "easy" },
	trivial = { r = 0.5, g = 0.5, b = 0.5, hex = "ff808080", key = "trivial" },
}
Q.DIFFICULTY = DIFFICULTY

-- The highest quest level that's grey (trivial) at a level (classic's rule).
local function GreyLevel(level)
	if level <= 5 then return 0 end
	if level <= 39 then return level - 5 - math.floor(level / 10) end
	if level <= 59 then return level - 1 - math.floor(level / 5) end
	return level - 9
end

-- A quest level against mine: a key of DIFFICULTY (no level, or -1 / 0, a level that scales to me: fair).
local function LevelKey(level)
	local mine = MyLevel()
	if not mine or type(level) ~= "number" or level <= 0 then return "fair" end
	local diff = level - mine
	if diff >= 5 then return "impossible" end
	if diff >= 3 then return "difficult" end
	if diff >= -2 then return "fair" end
	if level > GreyLevel(mine) then return "easy" end
	return "trivial"
end

-- The client's own difficulty of a quest for me (Enum.RelativeContentDifficulty), a key or nil.
local nativeKeys
local function NativeKey(id)
	local get = C_PlayerInfo and C_PlayerInfo.GetContentDifficultyQuestForPlayer
	if not (get and id) then return nil end
	if not nativeKeys then
		nativeKeys = {}
		local enum = Enum and Enum.RelativeContentDifficulty
		for name, value in pairs(type(enum) == "table" and enum or {}) do
			if DIFFICULTY[tostring(name):lower()] then nativeKeys[value] = tostring(name):lower() end
		end
	end
	local ok, value = pcall(get, id)
	if ok and type(value) == "number" and Readable(value) then return nativeKeys[value] end
	return nil
end

-- The colour of a quest level as the game shows quest difficulty, against my level: { r, g, b, hex
-- ("ffrrggbb"), key = "impossible" | "difficult" | "fair" | "easy" | "trivial" } (shared). With a quest
-- ID the client's own difficulty of that quest comes first (C_PlayerInfo.GetContentDifficultyQuestForPlayer);
-- else the level: 5 or more above mine red, 3-4 orange, 2 below to 2 above yellow, green above the grey
-- level, grey (classic's grey levels). No level: yellow.
function Q.LevelColor(level, questID)
	return DIFFICULTY[NativeKey(tonumber(questID)) or LevelKey(tonumber(level))]
end

-- A quest's difficulty key for me (the client's, else its level's: one that scales to me is fair), nil
-- for one the data doesn't know.
function Q.Difficulty(id)
	id = tonumber(id)
	local q = id and Q.Quest(id)
	if not q then return nil end
	return NativeKey(id) or (Scales(q) and "fair") or LevelKey(LevelOf(q))
end

-- Grey for me: too low to be worth much (the game's grey "!").
function Q.IsTrivial(id)
	return Q.Difficulty(id) == "trivial"
end

-- The zone I'm in (a zone map, not a city's floor or a cave), nil if not known.
local function MyZone()
	if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
	local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
	if not (ok and type(map) == "number" and Readable(map)) then return nil end
	for _ = 1, 6 do
		local okInfo, info = pcall(C_Map.GetMapInfo, map)
		if not (okInfo and type(info) == "table") then return map end
		if info.mapType == 3 then return map end
		if not info.parentMapID or info.parentMapID == 0 or info.mapType and info.mapType < 3 then return map end
		map = info.parentMapID
	end
	return map
end

-- The zone with quests a map is in (itself, or a parent: a cave, a city's floor), and x, y on it.
local function QuestZone(map, x, y)
	for _ = 1, 5 do
		if #Q.ZoneQuests(map) > 0 or #Q.ZoneGiven(map) > 0 then return map, x, y end
		local ok, info = pcall(C_Map and C_Map.GetMapInfo or error, map)
		local parent = ok and type(info) == "table" and info.parentMapID
		if not parent or parent == 0 or (info.mapType and info.mapType <= 2) then return map, x, y end
		if x and y then
			local okRect, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap or error, map, parent)
			if okRect and type(minX) == "number" and type(maxY) == "number" and Readable(minX) then
				x, y = minX + x * (maxX - minX), minY + y * (maxY - minY)
			else
				x, y = nil, nil
			end
		end
		map = parent
	end
	return map, x, y
end

-- The spots a quest is started at on a map: its givers' (NPCs, objects) places there.
local function StartSpots(q, map)
	local spots, onlyItems = {}, #q.starts > 0
	for _, a in ipairs(q.starts) do
		if a.kind ~= "item" then onlyItems = false end
		for _, p in ipairs(a.kind ~= "item" and a.points or {}) do
			if p.map == map then spots[#spots + 1] = p end
		end
	end
	return spots, onlyItems
end

-- Quests I can take now in a zone (a uiMap; a cave or a city's floor counts as its zone): its quests and
-- the ones given there that are listed elsewhere (a dungeon's), "available" for me, not started by an
-- item only (no one offers those). With my position on that map (x, y: 0..1) the nearest giver first;
-- without, the nearest my level first. Grey (trivial) ones after the others; ones without a giver on
-- the map after those with. Kept per data, progress and map; the order for the last position asked (to 1%).
local availBase, availKey, availSorted = {}, nil, {}
function Q.Available(map, x, y)
	map = tonumber(map)
	if not map then return {} end
	Listen()
	ReadActive()
	ReadDone()
	local zone
	zone, x, y = QuestZone(map, tonumber(x), tonumber(y))
	local level = MyLevel()
	local key = Q.dataGen .. ":" .. progress .. ":" .. tostring(level)
	if key ~= availKey then availBase, availKey, availSorted = {}, key, {} end
	local base = availBase[zone]
	if not base then
		base = {}
		local seen = {}
		for _, list in ipairs({ Q.ZoneQuests(zone), Q.ZoneGiven(zone) }) do
			for _, id in ipairs(list) do
				local q = not seen[id] and Q.Quest(id)
				seen[id] = true
				if q and Q.Status(id) == "available" then
					local spots, onlyItems = StartSpots(q, zone)
					if not onlyItems then
						base[#base + 1] = { id = id, spots = spots, grey = Q.IsTrivial(id) and 1 or 0, level = LevelOf(q, level) or level or 0 }
					end
				end
			end
		end
		availBase[zone] = base
	end
	local sortKey = zone .. ":" .. (x and y and (math.floor(x * 100) .. "," .. math.floor(y * 100)) or "-")
	if availSorted.key == sortKey then return availSorted.list end
	local far = {}
	for _, e in ipairs(base) do
		local best
		if x and y then
			for _, p in ipairs(e.spots) do
				local d = ((p.x - x) * 1.5) ^ 2 + (p.y - y) ^ 2 -- (a zone map is half again as wide as high)
				if not best or d < best then best = d end
			end
		end
		far[e] = best or (#e.spots > 0 and not x and 0) or false
	end
	local sorted = {}
	for i, e in ipairs(base) do sorted[i] = e end
	table.sort(sorted, function(a, b)
		if a.grey ~= b.grey then return a.grey < b.grey end
		local fa, fb = far[a], far[b]
		if (fa ~= false) ~= (fb ~= false) then return fa ~= false end
		if fa and fb and fa ~= fb then return fa < fb end
		local la, lb = math.abs(a.level - (level or a.level)), math.abs(b.level - (level or b.level))
		if la ~= lb then return la < lb end
		if a.level ~= b.level then return a.level < b.level end
		return a.id < b.id
	end)
	local out = {}
	for i, e in ipairs(sorted) do out[i] = e.id end
	availSorted = { key = sortKey, list = out } -- (the last one: a position keeps moving)
	return out
end

-- What's next for me: what the quests I finished or have in my log lead to, that I can take or that
-- still need something; in my zone first, then the lowest level, then the ones I can take.
function Q.Next()
	Listen()
	ReadActive()
	ReadDone()
	local zone, level = MyZone(), MyLevel()
	local key = Q.dataGen .. ":" .. progress .. ":" .. tostring(zone) .. ":" .. tostring(level)
	if key == nextKey and nextList then return nextList end
	local seen, list = {}, {}
	local function from(set)
		for id in pairs(set) do
			local q = Q.Quest(id)
			for _, other in ipairs(q and q.opens or {}) do
				if not seen[other] then
					seen[other] = true
					local s = Q.Status(other)
					if s == "available" or s == "locked" then list[#list + 1] = other end
				end
			end
		end
	end
	from(done)
	from(active)
	local function rank(id)
		local q = Q.Quest(id)
		return (zone and q.zone == zone) and 0 or 1, LevelOf(q, level) or 0, Q.Status(id) == "available" and 0 or 1
	end
	table.sort(list, function(a, b)
		local za, la, sa = rank(a)
		local zb, lb, sb = rank(b)
		if za ~= zb then return za < zb end
		if la ~= lb then return la < lb end
		if sa ~= sb then return sa < sb end
		return a < b
	end)
	nextList, nextKey = list, key
	return list
end

-- Friends whose progress is known (Learn.lua keeps it in Q.friends: { [key] = { name, classFile,
-- done, active, level, faction, race } }): { { name, classFile, status } }, by name; {} without any.
-- Learn.lua may define its own Q.Friends.
function Q.Friends(id)
	local out = {}
	if type(Q.friends) ~= "table" then return out end
	for _, p in pairs(Q.friends) do
		if type(p) == "table" and p.name then
			out[#out + 1] = { name = p.name, classFile = p.classFile, status = Q.Status(id, p) }
		end
	end
	table.sort(out, function(a, b) return tostring(a.name) < tostring(b.name) end)
	return out
end
