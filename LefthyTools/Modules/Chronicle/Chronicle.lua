local _, ns = ...
local LT = ns.LT
local L = ns.L

-- Chronicle: a journal per character, recorded automatically: level-ups (with how long each
-- took), deaths (where, and what killed you), zones discovered, first dungeon visits, bosses and
-- rare elites killed, notable loot, new mounts, pets, toys and achievements, and milestones
-- (quests, gold, professions). Plus statistics (time, distance on foot/riding/swimming/flying,
-- kills, gold, loot, ...) for the character and for the current session, and a feed of what
-- Battle.net friends with LefthyTools did. Highlights go to those friends through Beacon.
--
-- Data: LefthyToolsChronicleDB (account-wide, so every character's chronicle can be browsed)
--   chars[<name-realm>] = { name, realm, classFile, race, level, first, events, stats, zoneTime,
--     killers, levelTimes, seen = { zones, dungeons, bosses, rares }, professions, session, ... }
--   friends = { { t, name, classFile, k, ... }, ... } the friends' feed, newest last
--
-- Cost: event handlers only count or note things. A 1-second tick does the rest: time played,
-- time per zone, distance (one UnitPosition call), the rare-kill check on your target, sharing,
-- and redrawing the Chronicle window if it's open and something changed. Nothing else runs.

local TICK = 1
local EVENTS_MAX = 1000      -- per character; the oldest go first
local FEED_MAX = 300
local FOE_MEMORY = 15        -- seconds: whom you last fought counts as your killer this long
local TELEPORT = 150         -- yards within one tick: a portal, hearthstone or teleport, not travel
local BOSS_DEDUPE = 30       -- ENCOUNTER_END and BOSS_KILL report the same kill
local QUEST_MILESTONES = { 10, 25, 50, 100, 250, 500, 750, 1000, 1500, 2000, 2500, 3000, 4000, 5000 }
local GOLD_MILESTONES = { 1, 10, 50, 100, 250, 500, 1000, 2500, 5000, 10000 }
local PROFESSION_MILESTONES = { 75, 150, 225, 300 }
local COPPER_PER_GOLD = 10000
local DAILY_DAYS = 60        -- days of per-day counters kept (the graphs show 14)
local SHARE_DAYS = 7         -- days a friend gets from me when they show up
local SHARE_GAP = 300        -- today's numbers go to friends at most this often (if they changed)
local FRIEND_DAYS = 30       -- days of friends' numbers kept
local SAMPLE_STEP, SAMPLE_MAX = 60, 240 -- the session curve: a point a minute, at most 240
local SESSION_GAP = 300 -- switched on after this long without a tick: a new session
local issecret = issecretvalue or function() return false end

local STAT_KEYS = {
	"played", "sessions", "levels", "quests", "foreverQuests", "questXP", "xp", "kills", "rares", "bosses",
	"dungeonRuns", "deaths", "moneyIn", "moneyOut", "maxMoney", "loot2", "loot3", "loot4", "jumps",
	"walked", "ridden", "swum", "flown", "flights", "mounts", "pets", "toys", "achievements", "longestSession",
	"afk", "afkTimes", "longestAfk", -- the Martin tracker
}

local M = LT:NewModule("chronicle", {
	title = "Chronicle",
	description = L["A journal for each character, kept automatically: level-ups, deaths, dungeons, bosses, rares, loot, mounts and milestones, statistics, and what your friends did."],
	defaults = {
		share = true,
		friendsChat = true,
		minimapButton = true,
		minimapAngle = 210, -- degrees, 0 = right, counter-clockwise: the lower left
	},
})

local C = { module = M }
ns.Chronicle = C

local store, char, charKey
local lastTick, sinceTick = 0, 0
local afkStreak -- seconds AFK in a row, nil while not AFK
local lastFoe, lastFoeAt
local lastXP, lastXPMax, lastLevel
local lastMoney
local lastPos = {}
local onTaxi = false
local zone
local zoneDirty, professionsDirty = true, true
local lastBossName, lastBossAt
local shareQueue = {}
C.ticks = 0 -- for tests: the driver ticks once a second

---------------------------------------------------------------------------
-- Records
---------------------------------------------------------------------------

local function NewChar()
	local c = { events = {}, stats = {}, zoneTime = {}, killers = {}, levelTimes = {}, levelCounts = {}, professions = {},
		seen = { zones = {}, dungeons = {}, bosses = {}, rares = {} }, days = {}, daily = {}, first = time() }
	return c
end

local function Fill(c)
	for _, key in ipairs({ "events", "stats", "zoneTime", "killers", "levelTimes", "levelCounts", "professions", "seen",
		"days", "daily" }) do
		c[key] = type(c[key]) == "table" and c[key] or {}
	end
	for _, key in ipairs({ "zones", "dungeons", "bosses", "rares" }) do
		c.seen[key] = type(c.seen[key]) == "table" and c.seen[key] or {}
	end
	for _, key in ipairs(STAT_KEYS) do
		c.stats[key] = type(c.stats[key]) == "number" and c.stats[key] or 0
	end
	c.first = c.first or time()
end

-- An entry in this character's timeline; shareKind sends it to friends as a highlight too.
local function Record(kind, fields)
	fields.t, fields.k = time(), kind
	local events = char.events
	events[#events + 1] = fields
	if #events > EVENTS_MAX then
		table.remove(events, 1)
	end
	C.dirty, C.eventsDirty = true, true
	return fields
end

local function Share(kind, a, b)
	shareQueue[#shareQueue + 1] = { kind, a, b }
end

-- Noon of the day `back` days before today (negative: ahead), by the calendar: stepping back
-- 86400 s at a time skips or repeats a day around a daylight saving change.
function C.DayAgo(back)
	local t = date("*t")
	return time({ year = t.year, month = t.month, day = t.day - back, hour = 12 })
end

-- Per day (for the graphs): daily["YYYY-MM-DD"] = { played, xp, quests, kills, deaths, levels, afk }.
local DAILY = { played = true, xp = true, quests = true, kills = true, deaths = true, levels = true, afk = true }

local function Today()
	local day = date("%Y-%m-%d")
	local bucket = char.daily[day]
	if not bucket then
		bucket = { played = 0, xp = 0, quests = 0, kills = 0, deaths = 0, levels = 0, afk = 0 }
		char.daily[day] = bucket
	end
	return bucket
end

local function Add(stat, amount)
	amount = amount or 1
	char.stats[stat] = char.stats[stat] + amount
	if DAILY[stat] then
		local bucket = Today()
		bucket[stat] = (bucket[stat] or 0) + amount -- older buckets lack newer fields
	end
	C.dirty = true
end

-- Keeps the last DAILY_DAYS days.
local function PruneDaily()
	local oldest = date("%Y-%m-%d", C.DayAgo(DAILY_DAYS))
	for day in pairs(char.daily) do
		if day < oldest then -- ISO dates sort as text
			char.daily[day] = nil
		end
	end
end

-- This session as a curve for the graphs: { played, xp, money } every `step` seconds of play
-- (60 s; when it gets long, every other point goes and the step doubles, so it stays small).
local function SampleSession()
	local s = char.session
	if not s then
		return
	end
	s.series = s.series or {}
	s.step = s.step or SAMPLE_STEP
	local played = char.stats.played - s.stats.played
	local lastPoint = s.series[#s.series]
	if lastPoint and played - lastPoint.played < s.step then
		return
	end
	s.series[#s.series + 1] = { played = played, xp = char.stats.xp - s.stats.xp, money = GetMoney() - (s.money or 0) }
	if #s.series > SAMPLE_MAX then
		local kept = {}
		for i = 1, #s.series, 2 do
			kept[#kept + 1] = s.series[i]
		end
		s.series, s.step = kept, s.step * 2
	end
end

local function ZoneAndSubzone()
	local area, sub = GetRealZoneText() or "", GetSubZoneText() or ""
	return area, (sub ~= "" and sub ~= area) and sub or nil
end

local function Milestone(list, before, after)
	local hit
	for _, value in ipairs(list) do
		if before < value and after >= value then
			hit = value
		end
	end
	return hit
end

---------------------------------------------------------------------------
-- Session: since the last real login (a /reload continues it)
---------------------------------------------------------------------------

local function StartSession()
	local snapshot = {}
	for _, key in ipairs(STAT_KEYS) do
		snapshot[key] = char.stats[key]
	end
	char.session = { start = time(), stats = snapshot, money = GetMoney() }
	Add("sessions")
	char.days[date("%Y-%m-%d")] = true
end

-- { played, xp, levels, quests, kills, deaths, money, distance } gained this session.
function C.Session(c)
	c = c or char
	local s, now = c and c.session, c and c.stats
	if not s then
		return nil
	end
	local function diff(key) return (now[key] or 0) - (s.stats[key] or 0) end
	return {
		played = diff("played"), xp = diff("xp"), levels = diff("levels"), quests = diff("quests"),
		kills = diff("kills"), deaths = diff("deaths"), money = (c == char and GetMoney() or s.money) - (s.money or 0),
		distance = diff("walked") + diff("ridden") + diff("swum") + diff("flown"), afk = diff("afk"),
	}
end

-- The level before `level`, for the level-up window: { took (seconds played), kills, quests,
-- fastest (the quickest level so far, of at least three timed ones) }, or nil if not recorded.
function C.LevelReport(level)
	if not (M.enabled and char) then
		return nil
	end
	local took = char.levelTimes[level - 1]
	if not took then
		return nil
	end
	local counts = char.levelCounts[level - 1] or {}
	local timed = 0
	for _ in pairs(char.levelTimes) do
		timed = timed + 1
	end
	return { took = took, kills = counts.kills, quests = counts.quests,
		fastest = timed >= 3 and took <= (char.fastestLevel or took) }
end

---------------------------------------------------------------------------
-- Events (record only; the tick does anything that shows or sends)
---------------------------------------------------------------------------

local handlers = {}

local sessionJustStarted = false -- OnEnable started one; the login's PLAYER_ENTERING_WORLD follows

function handlers.PLAYER_ENTERING_WORLD(isInitialLogin)
	if (isInitialLogin and not sessionJustStarted) or not char.session then
		StartSession()
	end
	sessionJustStarted = false
	zoneDirty = true
end

handlers.ZONE_CHANGED_NEW_AREA = function() zoneDirty = true end
handlers.SKILL_LINES_CHANGED = function() professionsDirty = true end

function handlers.PLAYER_LEVEL_UP(level)
	local took = char.levelStart and (char.stats.played - char.levelStart) or nil
	if took then
		char.levelTimes[level - 1] = took
		if not char.fastestLevel or took < char.fastestLevel then
			char.fastestLevel = took
		end
	end
	-- Kills and quests during the level that just ended (the level-up window shows them).
	local s, from = char.stats, char.levelFrom
	if from then
		char.levelCounts[level - 1] = { kills = s.kills - (from.kills or 0), quests = s.quests - (from.quests or 0) }
	end
	char.levelFrom = { kills = s.kills, quests = s.quests }
	char.levelStart = char.stats.played
	char.level = level
	Add("levels")
	Record("level", { level = level, zone = ZoneAndSubzone(), took = took })
end

function handlers.PLAYER_DEAD()
	local foe = lastFoeAt and GetTime() - lastFoeAt <= FOE_MEMORY and lastFoe or nil
	Add("deaths")
	if foe then
		char.killers[foe] = (char.killers[foe] or 0) + 1
	end
	local area, sub = ZoneAndSubzone()
	Record("death", { zone = area, sub = sub, foe = foe, level = UnitLevel("player") })
	lastFoe, lastFoeAt = nil, nil
end

function handlers.QUEST_TURNED_IN(questID, xpReward)
	local before = char.stats.quests
	Add("quests")
	if ns.IsForeverQuest and ns.IsForeverQuest(questID) then
		Add("foreverQuests")
	end
	if type(xpReward) == "number" and not issecret(xpReward) then
		Add("questXP", xpReward)
	end
	local hit = Milestone(QUEST_MILESTONES, before, char.stats.quests)
	if hit then
		Record("quests", { count = hit })
		Share("quests", hit)
	end
	-- Every quest goes to friends' feeds (not their chat): what you're up to.
	local title = C_QuestLog.GetTitleForQuestID(questID)
	if type(title) == "string" and not issecret(title) then
		Share("quest", title)
	end
end

function handlers.PLAYER_XP_UPDATE()
	local xp, xpMax, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
	if issecret(xp) or issecret(xpMax) then
		return
	end
	if lastXP then
		local gained = level == lastLevel and xp - lastXP or (lastXPMax - lastXP) + xp
		if gained > 0 then
			Add("xp", gained)
		end
	end
	lastXP, lastXPMax, lastLevel = xp, xpMax, level
end

local function RecordRare(guid, name)
	if char.seen.rares[guid] then
		return
	end
	char.seen.rares[guid] = true -- this spawn, not the name: rares respawn
	Add("rares")
	local area = ZoneAndSubzone()
	Record("rare", { name = name, zone = area })
	Share("rare", name, area)
end

-- Rares, and world bosses outdoors: inside dungeons and raids "worldboss" is how Classic marks
-- their bosses (counted as bosses instead).
local function IsRareTarget()
	local class = UnitClassification("target")
	if issecret(class) or UnitIsPlayer("target") then
		return false
	end
	if class == "worldboss" then
		local inInstance, instanceType = IsInInstance()
		return not (inInstance and (instanceType == "party" or instanceType == "raid"))
	end
	return class == "rare" or class == "rareelite"
end

function handlers.PARTY_KILL(attackerGUID, targetGUID)
	if issecret(attackerGUID) or issecret(targetGUID) or attackerGUID ~= UnitGUID("player") then
		return
	end
	Add("kills")
	local targetNow = UnitGUID("target")
	if targetGUID == targetNow and not issecret(targetNow) and IsRareTarget() then
		local name = UnitName("target")
		if not issecret(name) then
			RecordRare(targetGUID, name)
		end
	end
end

local function RecordBoss(name)
	if type(name) ~= "string" or issecret(name) then
		return
	end
	local now = GetTime()
	if lastBossName == name and now - lastBossAt < BOSS_DEDUPE then
		return
	end
	lastBossName, lastBossAt = name, now
	Add("bosses")
	if not char.seen.bosses[name] then
		char.seen.bosses[name] = true
		local instance = IsInInstance() and GetInstanceInfo() or nil
		Record("boss", { name = name, instance = instance })
		Share("boss", name, instance)
	end
end

function handlers.ENCOUNTER_END(_, name, _, _, success)
	if success == 1 or success == true then
		RecordBoss(name)
	end
end

function handlers.BOSS_KILL(_, name)
	RecordBoss(name)
end

local function GoldMilestones(before, after)
	local hit = Milestone(GOLD_MILESTONES, before / COPPER_PER_GOLD, after / COPPER_PER_GOLD)
	if hit then
		Record("gold", { gold = hit })
		Share("gold", hit)
	end
end

function handlers.PLAYER_MONEY()
	local money = GetMoney()
	if lastMoney then
		local delta = money - lastMoney
		if delta > 0 then
			Add("moneyIn", delta)
		elseif delta < 0 then
			Add("moneyOut", -delta)
		end
	end
	if money > char.stats.maxMoney then
		local before = char.stats.maxMoney
		char.stats.maxMoney = money
		GoldMilestones(before, money)
	end
	lastMoney = money
end

-- "You receive loot: %s." and friends, as patterns: only my own loot counts.
local LOOT_PATTERNS
local function LootPatterns()
	if LOOT_PATTERNS then
		return LOOT_PATTERNS
	end
	LOOT_PATTERNS = {}
	for _, fmt in ipairs({ LOOT_ITEM_SELF_MULTIPLE or "You receive loot: %sx%d.", LOOT_ITEM_SELF or "You receive loot: %s.",
			LOOT_ITEM_PUSHED_SELF_MULTIPLE or "You receive item: %sx%d.", LOOT_ITEM_PUSHED_SELF or "You receive item: %s." }) do
		local pattern = fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
		pattern = pattern:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
		LOOT_PATTERNS[#LOOT_PATTERNS + 1] = "^" .. pattern .. "$"
	end
	return LOOT_PATTERNS
end

local function ItemQuality(link, itemID)
	local quality = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID)
	if type(quality) ~= "number" then
		quality = tonumber(link:match("|cnIQ(%d):")) -- retail links carry their quality
	end
	return quality
end

function handlers.CHAT_MSG_LOOT(text)
	if type(text) ~= "string" or issecret(text) then
		return
	end
	for _, pattern in ipairs(LootPatterns()) do
		local link, count = text:match(pattern)
		if link then
			local itemID = tonumber(link:match("|Hitem:(%d+)"))
			local quality = itemID and ItemQuality(link, itemID)
			if quality and quality >= 2 then
				Add("loot" .. math.min(quality, 4), tonumber(count) or 1)
			end
			if quality and quality >= 3 then
				local name = link:match("|h%[(.-)%]|h") or link
				local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
				Record("loot", { link = link, name = name, quality = quality, icon = icon })
				if quality >= 4 then
					Share("loot", name, quality)
				end
			end
			return
		end
	end
end

function handlers.NEW_MOUNT_ADDED(mountID)
	local name = C_MountJournal and C_MountJournal.GetMountInfoByID and C_MountJournal.GetMountInfoByID(mountID)
	Add("mounts")
	if name then
		Record("mount", { name = name })
		Share("mount", name)
	end
end

function handlers.NEW_PET_ADDED(petGUID)
	local name
	if C_PetJournal and C_PetJournal.GetPetInfoByPetID then
		name = select(8, C_PetJournal.GetPetInfoByPetID(petGUID))
	end
	Add("pets")
	if name then
		Record("pet", { name = name })
	end
end

function handlers.NEW_TOY_ADDED(itemID)
	local name = C_ToyBox and C_ToyBox.GetToyInfo and select(2, C_ToyBox.GetToyInfo(itemID))
	Add("toys")
	if name then
		Record("toy", { name = name })
	end
end

function handlers.ACHIEVEMENT_EARNED(achievementID, alreadyEarned)
	if alreadyEarned then
		return
	end
	local _, name, _, _, _, _, _, _, _, icon = GetAchievementInfo(achievementID)
	Add("achievements")
	if name then
		Record("achievement", { name = name, icon = icon })
		Share("achievement", name)
	end
end

function handlers.TIME_PLAYED_MSG(total)
	if type(total) == "number" and not issecret(total) then
		char.playedTotal, char.playedTotalAt = total, time() -- what /played said
	end
end

-- Jumps: a post-hook on the jump binding's function (it runs after the jump, untouched).
local jumpHooked = false
local function OnJump()
	if M.enabled and char and not (IsSwimming and IsSwimming()) and not (IsFlying and IsFlying()) then
		char.stats.jumps = char.stats.jumps + 1
	end
end

---------------------------------------------------------------------------
-- The 1-second tick
---------------------------------------------------------------------------

local function CheckZone()
	zoneDirty = false
	zone = GetRealZoneText()
	if zone and zone ~= "" and not char.seen.zones[zone] then
		char.seen.zones[zone] = true
		Record("zone", { zone = zone })
		Share("zone", zone) -- friends' feeds only
	end
	local inInstance, instanceType = IsInInstance()
	if inInstance and (instanceType == "party" or instanceType == "raid") then
		local name = GetInstanceInfo()
		-- (kept in the record: a /reload or a disconnect inside isn't another run)
		if name and name ~= char.instance then
			char.instance = name
			Add("dungeonRuns")
			if not char.seen.dungeons[name] then
				char.seen.dungeons[name] = true
				Record("dungeon", { name = name })
				Share("dungeon", name)
			end
		end
	elseif not inInstance then
		char.instance = nil
	end
end

local function CheckProfessions()
	professionsDirty = false
	if not GetProfessions then
		return
	end
	local firstScan = not char.professionsScanned
	char.professionsScanned = true
	for _, index in pairs({ GetProfessions() }) do
		local name, icon, level = GetProfessionInfo(index)
		if name and type(level) == "number" then
			local before = char.professions[name]
			char.professions[name] = level
			if not firstScan then
				if not before then
					Record("profession", { name = name, icon = icon })
				else
					local hit = Milestone(PROFESSION_MILESTONES, before, level)
					if hit then
						Record("profession", { name = name, icon = icon, level = hit })
						Share("profession", name, hit)
					end
				end
			end
		end
	end
end

local function TrackTravel()
	local north, west, _, continent = UnitPosition("player")
	if not north or issecret(north) then
		lastPos.continent = nil
		return
	end
	local taxi = UnitOnTaxi("player")
	if taxi and not onTaxi then
		Add("flights")
	end
	onTaxi = taxi
	if lastPos.continent == continent then
		local dn, dw = north - lastPos.north, west - lastPos.west
		local d = math.sqrt(dn * dn + dw * dw)
		if d > 0.5 and d < TELEPORT then
			local kind = taxi and "flown" or (IsSwimming() and "swum") or (IsMounted() and "ridden") or "walked"
			char.stats[kind] = char.stats[kind] + d
		end
	end
	lastPos.continent, lastPos.north, lastPos.west = continent, north, west
end

local function TrackTarget(now)
	if not UnitExists("target") then
		return
	end
	if UnitAffectingCombat("player") and UnitCanAttack("player", "target") then
		local name = UnitName("target")
		if type(name) == "string" and not issecret(name) then
			lastFoe, lastFoeAt = name, now
		end
	end
	-- A rare you were fighting dies while you have it targeted (and it isn't someone else's tap).
	if IsRareTarget() and UnitIsDead("target") and not UnitIsTapDenied("target") then
		local guid, name = UnitGUID("target"), UnitName("target")
		if guid and not issecret(guid) and not issecret(name) then
			RecordRare(guid, name)
		end
	end
end

local ShareDays -- below, with the friends' part

-- Friends take at most 10 highlights a minute from one friend (Beacon). Feed-only ones (every quest
-- turned in, every new zone) take at most FEED_SHARES of them, so a quest hub can't crowd out a boss
-- or epic loot in the same minute.
local FEED_SHARE_KINDS, FEED_SHARES, FEED_WINDOW = { quest = true, zone = true }, 5, 60
local feedShares = {} -- times of the last feed-only shares
local function FeedBudget(kind, now)
	if not FEED_SHARE_KINDS[kind] then
		return true
	end
	while feedShares[1] and now - feedShares[1] >= FEED_WINDOW do
		table.remove(feedShares, 1)
	end
	if #feedShares >= FEED_SHARES then
		return false
	end
	feedShares[#feedShares + 1] = now
	return true
end

local function Tick(now, elapsed)
	C.ticks = C.ticks + 1
	local stats = char.stats
	stats.played = stats.played + elapsed
	local today = Today()
	today.played = today.played + elapsed
	SampleSession()
	if zone then
		char.zoneTime[zone] = (char.zoneTime[zone] or 0) + elapsed
	end
	if char.session then
		char.session.last = time()
		stats.longestSession = math.max(stats.longestSession, char.session.last - char.session.start)
	end
	-- The Martin tracker: time spent AFK, how often, the longest stretch.
	local afk = UnitIsAFK("player")
	if not issecret(afk) and afk == true then
		if not afkStreak then
			afkStreak = 0
			stats.afkTimes = stats.afkTimes + 1
		end
		afkStreak = afkStreak + elapsed
		Add("afk", elapsed) -- (per day too, for the graphs)
		stats.longestAfk = math.max(stats.longestAfk, afkStreak)
	else
		afkStreak = nil
	end
	if zoneDirty then
		CheckZone()
	end
	if professionsDirty then
		CheckProfessions()
	end
	TrackTravel()
	TrackTarget(now)
	ShareDays(now)
	while shareQueue[1] do
		local item = table.remove(shareQueue, 1)
		local beacon = LT:GetModule("beacon")
		if M.db.share and beacon and beacon.enabled and ns.Beacon and ns.Beacon.ShareHighlight and FeedBudget(item[1], now) then
			ns.Beacon.ShareHighlight(item[1], item[2], item[3])
		end
	end
	if C.OnTick then
		-- Window.lua: redraws only while open, and only the page whose data changed.
		C.OnTick(now, C.dirty, C.eventsDirty, C.feedDirty)
	end
	C.dirty, C.eventsDirty, C.feedDirty = false, false, false
end

local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(_, elapsed)
	sinceTick = sinceTick + elapsed
	if sinceTick >= TICK then
		local now = GetTime()
		local since = now - lastTick
		lastTick, sinceTick = now, 0 -- first: an error in the tick must not make it run every frame
		Tick(now, since)
	end
end)

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
	if char and handlers[event] then
		handlers[event](...)
	end
end)

---------------------------------------------------------------------------
-- Friends: their level-ups, deaths and highlights, from Beacon (on Beacon's tick)
---------------------------------------------------------------------------

-- English chat lines for friends' highlights (chat output stays English).
local CHAT = {
	boss = function(a, b) return ("defeated %s%s."):format(a, b ~= "" and (" (" .. b .. ")") or "") end,
	rare = function(a, b) return ("killed the rare %s%s."):format(a, b ~= "" and (" in " .. b) or "") end,
	dungeon = function(a) return ("entered %s for the first time."):format(a) end,
	loot = function(a, b) return ("looted %s."):format(C.QualityText(a, tonumber(b))) end,
	mount = function(a) return ("got a new mount: %s."):format(a) end,
	achievement = function(a) return ("earned %s."):format(a) end,
	quests = function(a) return ("has completed %s quests."):format(a) end,
	gold = function(a) return ("has %s gold."):format(a) end,
	profession = function(a, b) return ("reached %s %s."):format(a, b) end,
}

-- An item name in its quality colour.
function C.QualityText(name, quality)
	local hex
	if quality and C_Item and C_Item.GetItemQualityColor then
		hex = select(4, C_Item.GetItemQualityColor(quality))
	end
	return hex and ("|c" .. hex .. name .. "|r") or name
end

local function AddToFeed(entry)
	local feed = store.friends
	feed[#feed + 1] = entry
	if #feed > FEED_MAX then
		table.remove(feed, 1)
	end
	C.feedDirty = true
end

---------------------------------------------------------------------------
-- My days for friends' graphs (through Beacon), and theirs
---------------------------------------------------------------------------

local sentDaily = {} -- day -> the message last sent to everyone
local lastDailyShare = -math.huge

local function SharingOn()
	local beacon = LT:GetModule("beacon")
	return M.db.share and beacon and beacon.enabled and ns.Beacon ~= nil
end

-- D2;<YYYYMMDD>;<minutes>;<xp>;<quests>;<kills>;<deaths>;<levels> for one of my days, or nil.
local function DailyMessage(day)
	local b = char.daily[day]
	if not b then
		return nil
	end
	return ("D%s;%s;%d;%d;%d;%d;%d;%d"):format(ns.Beacon.VERSION, (day:gsub("-", "")),
		math.min(1440, math.floor((b.played or 0) / 60)), math.floor(b.xp or 0), b.quests or 0, b.kills or 0,
		b.deaths or 0, b.levels or 0)
end

-- K2;<YYYYMMDD>;<minutes AFK> for one of my days, or nil (none). Its own message, sent after the
-- day's D2: builds before it reject a D2 with another field, and ignore a kind they don't know.
local function AfkMessage(day)
	local b = char.daily[day]
	local minutes = b and math.min(1440, math.floor((b.afk or 0) / 60)) or 0
	if minutes > 0 then
		return ("K%s;%s;%d"):format(ns.Beacon.VERSION, (day:gsub("-", "")), minutes)
	end
end

-- On the tick, at most every SHARE_GAP: today's and yesterday's numbers to everyone, if changed.
function ShareDays(now)
	if now - lastDailyShare < SHARE_GAP or not SharingOn() then
		return
	end
	lastDailyShare = now
	for _, t in ipairs({ C.DayAgo(1), C.DayAgo(0) }) do
		local day = date("%Y-%m-%d", t)
		for _, message in ipairs({ DailyMessage(day) or false, AfkMessage(day) or false }) do
			local key = message and (day .. message:sub(1, 1))
			if message and message ~= sentDaily[key] then
				sentDaily[key] = message
				ns.Beacon.QueueLowToPeers(message) -- never ahead of live data
			end
		end
	end
end

-- A friend just showed up: my last SHARE_DAYS days, for their graphs.
local function SendDaysTo(gameAccountID)
	if not SharingOn() then
		return
	end
	for i = SHARE_DAYS - 1, 0, -1 do
		local day = date("%Y-%m-%d", C.DayAgo(i))
		for _, message in ipairs({ DailyMessage(day) or false, AfkMessage(day) or false }) do
			if message then
				ns.Beacon.QueueLow(gameAccountID, message)
			end
		end
	end
end

-- A day of a friend's numbers (D2), or just its AFK time (K2: day.afk only):
-- store.friendStats[name] = { classFile, level, updated, days }. Either keeps what the other set.
local function StoreFriendDay(peer, day)
	local friends = store.friendStats
	local f = friends[peer.name] or { days = {} }
	friends[peer.name] = f
	f.classFile, f.level, f.updated = peer.classFile, peer.level, time()
	local old = f.days[day.day] or {}
	if day.played == nil then
		old.afk = day.afk
		f.days[day.day] = old
	else
		f.days[day.day] = { played = day.played, xp = day.xp, quests = day.quests, kills = day.kills,
			deaths = day.deaths, levels = day.levels, afk = old.afk }
	end
	local oldest = date("%Y-%m-%d", C.DayAgo(FRIEND_DAYS))
	for d in pairs(f.days) do
		if d < oldest then
			f.days[d] = nil
		end
	end
	C.dirty = true -- the graphs
end

-- Highlights that only go into the feed: they'd be too chatty as chat lines.
local FEED_ONLY = { quest = true, zone = true }

local function OnFriendEvent(kind, peer, data)
	if not (M.enabled and store and peer.name) then
		return
	end
	if kind == "known" then
		SendDaysTo(data.id)
		return
	elseif kind == "daily" then
		StoreFriendDay(peer, data)
		return
	end
	local entry = { t = time(), name = peer.name, classFile = peer.classFile }
	if kind == "level" then
		entry.k, entry.level = "level", data.level
	elseif kind == "death" then
		entry.k, entry.where, entry.foe = "death", data.where, data.foe
	elseif kind == "online" or kind == "offline" then
		entry.k = kind
	elseif kind == "highlight" and (CHAT[data.kind] or FEED_ONLY[data.kind]) then
		entry.k, entry.a, entry.b = data.kind, data.a, data.b
		if M.db.friendsChat and CHAT[data.kind] then
			M:Print(("%s%s|r %s"):format(LT.Window.ClassColorCode(peer.classFile), peer.name, CHAT[data.kind](data.a, data.b)))
		end
	else
		return
	end
	AddToFeed(entry)
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

local EVENTS = {
	"PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "SKILL_LINES_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_DEAD",
	"QUEST_TURNED_IN", "PLAYER_XP_UPDATE", "PARTY_KILL", "ENCOUNTER_END", "BOSS_KILL", "PLAYER_MONEY",
	"CHAT_MSG_LOOT", "NEW_MOUNT_ADDED", "NEW_PET_ADDED", "NEW_TOY_ADDED", "ACHIEVEMENT_EARNED", "TIME_PLAYED_MSG",
}

local listening = false

-- MinimapButton.lua's, looked up when it runs: after an update that added that file, a /reload
-- doesn't load it (only a restart does), and C_Timer.After must never get nil.
local function UpdateMinimapButton()
	if C.UpdateMinimapButton then
		C.UpdateMinimapButton()
	end
end

function M:OnEnable()
	LefthyToolsChronicleDB = type(LefthyToolsChronicleDB) == "table" and LefthyToolsChronicleDB or {}
	store = LefthyToolsChronicleDB
	store.chars = type(store.chars) == "table" and store.chars or {}
	store.friends = type(store.friends) == "table" and store.friends or {}
	store.friendStats = type(store.friendStats) == "table" and store.friendStats or {}
	local name, realm = UnitName("player"), GetRealmName()
	charKey = name .. "-" .. (realm or "")
	char = store.chars[charKey] or NewChar()
	store.chars[charKey] = char
	Fill(char)
	local _, classFile = UnitClass("player")
	char.name, char.realm, char.classFile, char.race = name, realm, classFile, UnitRace("player")
	local level = UnitLevel("player")
	if char.level and char.level ~= level then
		-- Levelled where Chronicle didn't see it (off, another PC): this level's start is unknown.
		char.levelStart, char.levelFrom = nil, nil
	end
	char.level = level
	lastMoney = GetMoney()
	char.stats.maxMoney = math.max(char.stats.maxMoney, lastMoney)
	lastXP, lastXPMax, lastLevel = nil, nil, nil
	handlers.PLAYER_XP_UPDATE() -- the starting point for counting experience
	zoneDirty, professionsDirty, lastPos.continent = true, true, nil
	sessionJustStarted = false
	-- A new character, or Chronicle switched on mid-game after being off: the session it knows
	-- ended long ago (a /reload or switching it off and on keeps it; those take seconds).
	local session = char.session
	-- (Sessions from before the stamp existed go by their start.)
	if not session or time() - (session.last or session.start or 0) > SESSION_GAP then
		StartSession()
		sessionJustStarted = true
	end
	PruneDaily()

	for _, event in ipairs(EVENTS) do
		pcall(events.RegisterEvent, events, event)
	end
	if not listening and ns.Beacon then
		listening = true
		table.insert(ns.Beacon.listeners, OnFriendEvent)
	end
	if not jumpHooked and type(JumpOrAscendStart) == "function" then
		jumpHooked = true
		hooksecurefunc("JumpOrAscendStart", OnJump)
	end
	lastTick, sinceTick = GetTime(), 0
	driver:Show()
	C_Timer.After(0, UpdateMinimapButton) -- MinimapButton.lua
end

function M:OnDisable()
	events:UnregisterAllEvents()
	driver:Hide()
	wipe(shareQueue)
	if C.window then
		C.window:Hide()
	end
	C_Timer.After(0, UpdateMinimapButton)
end

function M:OnSettingChanged()
	C_Timer.After(0, UpdateMinimapButton) -- the minimap button's checkbox
end

---------------------------------------------------------------------------
-- For the window, the AFK screen and the commands
---------------------------------------------------------------------------

function C.Store()
	return store
end

-- Makes a record complete (records from older versions lack newer statistics).
C.Fill = Fill

function C.CurrentKey()
	return charKey
end

function C.Char()
	return char
end

-- "1h 12m", "3d 4h", "45s"
function C.Duration(seconds)
	seconds = math.floor((seconds or 0) + 0.5)
	if seconds < 60 then
		return seconds .. "s"
	elseif seconds < 3600 then
		return math.floor(seconds / 60) .. "m"
	elseif seconds < 86400 then
		return ("%dh %dm"):format(math.floor(seconds / 3600), math.floor(seconds / 60) % 60)
	end
	return ("%dd %dh"):format(math.floor(seconds / 86400), math.floor(seconds / 3600) % 24)
end

function C.Number(n)
	n = math.floor((n or 0) + 0.5)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

function C.Money(copper)
	copper = math.floor(copper or 0)
	local sign = copper < 0 and "-" or ""
	copper = math.abs(copper)
	if GetMoneyString then
		return sign .. GetMoneyString(copper, true)
	end
	return ("%s%dg %ds %dc"):format(sign, math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

function C.Distance(yards)
	return L["%.1f km"]:format((yards or 0) * 0.9144 / 1000)
end

-- This session in one line, for the AFK screen (localized) or chat (English).
function C.SessionLine(english)
	local s = C.Session()
	if not s then
		return nil
	end
	if english then
		return ("this session: %s played, %s XP, %d level(s), %d quest(s), %d killing blow(s), %d death(s), %s, %s gold.")
			:format(C.Duration(s.played), C.Number(s.xp), s.levels, s.quests, s.kills, s.deaths, C.Distance(s.distance),
				C.Money(s.money))
	end
	return L["This session: %s played, %s XP, %d quests, %d kills"]:format(C.Duration(s.played), C.Number(s.xp), s.quests, s.kills)
end

if ns.AFKScreen then
	table.insert(ns.AFKScreen.sections, function()
		return M.enabled and { C.SessionLine() } or nil
	end)
end

function M:Toggle()
	if C.Toggle then
		C.Toggle()
	end
end

function M:BuildOptions(o)
	o:Header(L["Sharing"])
	o:Checkbox("share", L["Share highlights with friends"],
		L["Bosses, rares, first dungeon visits, epic loot, new mounts, achievements and milestones go to Battle.net friends with LefthyTools (needs Beacon)."])
	o:Checkbox("friendsChat", L["Show friends' highlights in chat"],
		L["A chat line when a friend shares a highlight. They're always in Chronicle's Friends tab."])
	o:Header(L["Journal"])
	o:Button(L["Open the journal"], L["Open"], function() M:Toggle() end,
		L["Your timeline, your statistics and your friends' news. Also /chronicle or a key binding."])
	o:Checkbox("minimapButton", L["Minimap button"],
		L["A button on the edge of the minimap: click opens the journal, right-click these settings. Drag it to move it."])
end

function M:OnSlashCommand(msg)
	local cmd = strtrim(msg or ""):lower()
	if cmd == "" or cmd == "open" then
		self:Toggle()
	elseif cmd == "session" then
		self:Print(C.SessionLine(true) or "no session yet.")
	elseif cmd == "settings" or cmd == "options" then
		LT:OpenSettings(self)
	elseif cmd == "minimap" then
		LT:SetModuleSetting(self, "minimapButton", not self.db.minimapButton)
		self:Print("minimap button " .. (self.db.minimapButton and "on." or "off."))
	else
		self:Print("/chronicle - open or close the journal")
		self:Print("/chronicle session - this session in one line")
		self:Print("/chronicle minimap - show or hide the minimap button")
		self:Print("/chronicle settings - Chronicle's settings")
	end
end

BINDING_NAME_LEFTHYTOOLS_CHRONICLE_TOGGLE = L["Chronicle: open or close the journal"]

SLASH_LEFTHYTOOLS_CHRONICLE1 = "/chronicle"
SlashCmdList.LEFTHYTOOLS_CHRONICLE = function(msg)
	if M.enabled then
		M:OnSlashCommand(msg)
	else
		M:Print("Chronicle is off: switch it on with /lefthy enable chronicle.")
	end
end
