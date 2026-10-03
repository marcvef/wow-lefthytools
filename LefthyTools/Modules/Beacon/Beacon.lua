local _, ns = ...
local LT = ns.LT
local L = ns.L

-- Beacon: Battle.net friends who also run LefthyTools see each other on the world map and
-- minimap, with their status (dead, in combat), and get told when one of them levels up.
--
-- Addons can't reach the internet, so this runs entirely on the game's Battle.net addon
-- messages (C_BattleNet.SendGameData / BN_CHAT_MSG_ADDON): no group, guild or realm needed.
-- Each client can only read its *own* position (C_Map.GetPlayerMapPosition works for the
-- player and party only), so every client sends its own. Messages, ";"-separated:
--
--   H2                  hello: "I run Beacon". Sent to online WoW friends we don't know yet;
--                       anyone running it answers with their state. Friends without the addon
--                       get this one message (at most every HELLO_RETRY seconds) and nothing else.
--   S2;<flags>;<continent>;<north>;<west>;<subzone>;<target>
--                       my state. flags: D dead, G ghost, C in combat. The position is a world
--                       position (C_Map.GetWorldPosFromMapPos), empty in dungeons/raids or with
--                       sharing off; <target> is who I'm fighting, only while in combat.
--   L2;<level>;<text>   I levelled up; <text> is my own level-up message (empty = their default)
--   V2;<version>        my LefthyTools build (LT.version), sent with every answer; a friend on an
--                       older build gets told once per login. Builds before 0.4.0 ignore it.
--   P2;<continent>;<north>;<west>;<uiMapID>
--                       a map ping (Pings.lua): "look here", shown on friends' maps for a minute
--   T2;<questID>;<done>;<title>;<objective>
--                       the quest I'm tracking (super-tracked, else the first watched one), for
--                       the tooltip: done 1 = ready to turn in, objective = the first unfinished
--                       one. questID 0 = none or not shared. Sent when it changes (at most every
--                       QUEST_GAP seconds) and with every answer.
--   E2;<kind>;<a>;<b>   a Chronicle highlight (boss, rare, dungeon, loot, mount, achievement, quests,
--                       gold, profession) with up to two text fields; see Chronicle.lua
--   C2;<count>          in combat: how many enemies have me on their threat list (counted on the
--                       nameplates the game shows). Sent when it changes, at most once a second;
--                       a state without C clears it.
--   I2;<item string>[;<call id>]
--                       an item I show my friends (Ctrl+right-click, Items.lua); with a call id
--                       (Ctrl+Shift+right-click) they can say Need or Pass:
--   N2;<call id>;<1|0>  my Need (1) or Pass (0) for a friend's item, to them
--   R2;<call id>;<name>:<roll>,...
--                       the verdict on my item, to everyone: highest roll first (0 = no roll)
--   D2;<YYYYMMDD>;<minutes played>;<xp>;<quests>;<kills>;<deaths>;<levels>
--                       a day of my Chronicle statistics, for friends' graphs: my last 7 days
--                       when a friend shows up, then today's at most every 5 minutes if changed
--   X2;<percent>        progress on my current level (0-99), empty at max level or with sharing
--                       off. Sent when the whole percent changes (at most every XP_GAP seconds)
--                       and with every answer.
--
-- Builds that don't know a message kind ignore it (Parse returns nil), so new kinds can be
-- added without breaking older friends.
--   Q2                  module switched off: forget me
--
-- Keeping it light: the state is only sent when it changed (checked every <interval> seconds,
-- status changes at most once a second) plus a heartbeat every HEARTBEAT seconds. Every send
-- goes through one rate limiter, and a throttle answer from the server pauses sending.
-- Event handlers only record what happened; the 10 Hz driver tick does the work, and drawing
-- (Dots.lua) is batched: the world map at most twice a second while open, the minimap only
-- when something on it moved.

local PREFIX = "LTBeacon"
local VERSION = "2"
local SWEEP_INTERVAL = 60    -- look for friends who started the addon
local SWEEP_COALESCE = 10    -- a friend came online: look again, but not more often than this
local HELLO_RETRY = 120      -- greet the same friend at most this often
local HEARTBEAT = 20         -- resend an unchanged state this often, so friends know I'm still here
local PEER_TIMEOUT = 65      -- forget a friend after this much silence (three missed heartbeats)
local VALIDATE_INTERVAL = 15 -- re-check that known friends are still online in WoW
local STATUS_GAP = 1         -- status changes (combat, death, target) go out at most this often
local SEND_RATE, SEND_BURST = 10, 10 -- messages per second, across all friends
local THROTTLE_PAUSE = 2     -- the server said slow down: pause sending this long
local INBOX_LIMIT = 20       -- messages per second accepted from one friend
local DING_GAP = 10          -- level-up messages accepted from one friend at most this often
local DEATH_GAP = 10         -- death alerts for one friend at most this often
local PING_GAP = 2           -- map pings accepted from one friend at most this often
local QUEST_GAP = 2          -- my tracked quest is checked (and sent if changed) at most this often
local HIGHLIGHT_LIMIT, HIGHLIGHT_WINDOW = 10, 60 -- Chronicle highlights accepted from one friend
local ONLINE_QUIET = 60      -- friends found in the first minute were online already: not news
local COUNT_GAP = 1          -- in combat: enemies counted (and sent if changed) at most this often
local XP_GAP = 2             -- my level progress is checked (and sent if changed) at most this often
local ITEM_GAP = 2           -- shared items accepted from one friend at most this often (they send
                             -- at most every 3 s; the margin is for their queue and the network)
local CALL_LIMIT, CALL_WINDOW = 10, 10 -- Need / Pass answers and verdicts accepted from one friend
local DAILY_LIMIT = 20       -- Chronicle days accepted from one friend per minute (7 arrive at once)
local HIGHLIGHTS = { boss = true, rare = true, dungeon = true, loot = true, mount = true, achievement = true,
	quests = true, gold = true, profession = true, quest = true, zone = true }
local ANSWER_GAP = 5         -- answer one friend's hellos at most this often
local FAREWELL_TIMEOUT = 10  -- switched off: stop trying to say goodbye after this long
local GLIDE_SNAP = 300       -- a jump this far (yards) is a teleport: no gliding
local TICK = 0.1
local REFRESH_THROTTLE = 0.5

local M = LT:NewModule("beacon", {
	title = "Beacon",
	description = L["Shares your position with Battle.net friends who also use LefthyTools and shows theirs on the world map and minimap, in their class colour."],
	defaults = {
		share = true,
		shareQuest = true,
		interval = 3,
		showFriends = true,
		showMinimap = true,
		minimapEdge = true,
		showGroup = true,
		deathAlert = true,
		pings = true,
		shareItems = true,
		dingAnnounce = true,
		dingText = "",
		dingShow = true,
		dingSound = true,
		dingSoundKit = 50111, -- boss defeated fanfare (Ding.lua lists the choices)
	},
})

-- Shared with Dots.lua, Ding.lua and Alerts.lua.
local B = { module = M, VERSION = VERSION, handlers = {}, listeners = {}, pings = {} }
ns.Beacon = B

-- Things that happened to a friend ("level", "death", ...), for other modules (Chronicle):
-- table.insert(ns.Beacon.listeners, function(kind, peer, data) ... end). Called on the driver tick.
function B.Notify(kind, peer, data)
	for _, listener in ipairs(B.listeners) do
		local ok, err = pcall(listener, kind, peer, data)
		if not ok then
			geterrorhandler()(err)
		end
	end
end

-- peers[gameAccountID] = {
--   seen                             time of their last message
--   name, classFile, guid, level, area   from Battle.net (CopyInfo)
--   hasPos, continent, north, west   their last world position, posTime when it arrived
--   fromNorth, fromWest, glide       where the minimap dot glides from, over how many seconds
--   dead, ghost, combat, subzone, target
--   rev                              bumped on every change, so dots restyle only when needed
-- }
local peers = {}
B.peers = peers

local helloAt = {}      -- gameAccountID -> when we last greeted them
local otherVersion = {} -- gameAccountID -> protocol version of a friend on another LefthyTools version
local owed = {}         -- gameAccountID -> true: send them my current state
local outbox = {}       -- { gameAccountID, message }: one-off messages, sent before states
local lowOutbox = {}    -- the same, sent only when nothing else waits (bulk data)
local inbox = {}        -- gameAccountID -> { count, window, dingAt, answeredAt }: spam guards
local dings = {}        -- { gameAccountID, level, text } received, shown on the next tick
local deaths = {}       -- { gameAccountID, foe }: friends who just died, told on the next tick
local pingsIn = {}      -- { gameAccountID, continent, north, west, mapID } received, shown on the next tick
local highlightsIn = {} -- { gameAccountID, kind, a, b } received, passed on on the next tick
local itemsIn = {}      -- { "item" | "answer" | "result", gameAccountID, ... } for Items.lua, next tick
local dailyIn = {}      -- { gameAccountID, { day, played, xp, ... } }: friends' days, for Chronicle
local comings = {}      -- { "online" | "offline", peer }: told to listeners on the next tick
local enabledAt = 0
local newerFrom         -- gameAccountID of a friend with a newer LefthyTools, told on the next tick
local newerNoticeShown = false -- that notice comes once per login
local stats = { sent = 0, received = 0, throttled = 0, since = 0 }

local sweepRequested, validateRequested, statusDirty = false, false, false
local groupChanged = true -- re-check which friends are in my group on the next tick
local questDirty = true   -- my tracked quest may have changed
local xpDirty = true      -- my experience may have changed
local lastSweep, lastValidate, lastCheck, lastSent, lastExpire, lastRefresh, lastQuestCheck, lastXPCheck
local lastState, lastQuest, lastXP
local tokens, pausedUntil = SEND_BURST, 0
-- Friends' data changed: the world map redraws on the next tick (at most twice a second, and
-- only while open), the minimap on the next frame so gliding dots start right away.
B.dirty, B.minimapDirty = false, true

local function Changed()
	B.dirty, B.minimapDirty = true, true
end

local function ResetTimers()
	lastSweep, lastValidate, lastCheck, lastSent = -math.huge, -math.huge, -math.huge, -math.huge
	lastExpire, lastRefresh, lastQuestCheck, lastXPCheck = 0, -math.huge, -math.huge, -math.huge
	lastState, lastQuest, questDirty, lastXP, xpDirty = nil, nil, true, nil, true
end
ResetTimers()

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- Free text for a message: no colour codes or other escape sequences, separators or control
-- characters, and cut at maxBytes without splitting a UTF-8 character.
function B.Clean(text, maxBytes)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then
		return ""
	end
	text = strtrim((text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[|;%c]", "")))
	if #text > maxBytes then
		text = text:sub(1, maxBytes):gsub("[\192-\255][\128-\191]*$", "")
	end
	return text
end

function B.ClassColor(classFile)
	local color = classFile and C_ClassColor and C_ClassColor.GetClassColor(classFile)
	if color then
		return color:GetRGB()
	end
	local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if c then
		return c.r, c.g, c.b
	end
	return 1, 1, 1
end

-- C_PartyInfo.IsGUIDInGroup; the global IsGUIDInGroup only exists while the client's
-- "loadDeprecationFallbacks" setting is on (Blizzard_DeprecatedPartyInfo).
function B.IsInMyGroup(guid)
	local check = C_PartyInfo and C_PartyInfo.IsGUIDInGroup or IsGUIDInGroup
	return check ~= nil and check(guid) == true
end

-- The friend's unit token while they're in my group (party1-4 / raid1-40), else nil.
local function FindGroupUnit(guid)
	if not (guid and B.IsInMyGroup(guid)) then
		return nil
	end
	local raid = IsInRaid()
	for i = 1, raid and 40 or 4 do
		local unit = (raid and "raid" or "party") .. i
		local unitGuid = UnitGUID(unit)
		if unitGuid == guid and not (issecretvalue and issecretvalue(unitGuid)) then
			return unit
		end
	end
	return nil
end

-- Re-checks who of my friends is in my group (on roster changes, on the next tick).
local function UpdateGroupUnits()
	for _, peer in pairs(peers) do
		local unit = FindGroupUnit(peer.guid)
		if unit ~= peer.groupUnit then
			peer.groupUnit = unit
			peer.rev = peer.rev + 1
		end
	end
end

-- Friends in my group are drawn too (marked as group members), unless "show group" is off;
-- Blizzard draws its own dot for them, ours goes on top and adds the tooltip.
function B.IsShown(peer)
	return peer.name and peer.hasPos and (M.db.showGroup or not peer.groupUnit)
end

-- Where a friend's minimap dot is right now: gliding from the previous report to the latest
-- one, so the dot moves smoothly instead of jumping every few seconds. Second value: still gliding.
function B.DrawnPosition(peer, now)
	local t = peer.glide > 0 and (now - peer.posTime) / peer.glide or 1
	if t >= 1 then
		return peer.north, peer.west, false
	end
	return peer.fromNorth + (peer.north - peer.fromNorth) * t, peer.fromWest + (peer.west - peer.fromWest) * t, true
end

---------------------------------------------------------------------------
-- My own position
---------------------------------------------------------------------------

-- The map route (verified in game) is what we send. The minimap needs my position every frame
-- while moving; UnitPosition gives it without creating tables, so it's used once it has been
-- seen to agree with the map route (HereBeDragons relies on the two matching).
local unitPositionAgrees = false

local function MapRoutePosition()
	local mapID = C_Map.GetBestMapForUnit("player")
	local mapPos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not mapPos then
		return nil -- dungeons, raids and other places without a map position
	end
	local continent, worldPos = C_Map.GetWorldPosFromMapPos(mapID, mapPos)
	if not continent or not worldPos then
		return nil
	end
	local north, west = worldPos:GetXY()
	if UnitPosition and not unitPositionAgrees then
		local uNorth, uWest, _, uContinent = UnitPosition("player")
		unitPositionAgrees = uNorth ~= nil and uContinent == continent
			and math.abs(uNorth - north) < 2 and math.abs(uWest - west) < 2
	end
	return continent, north, west
end

-- continent, north, west in world yards, or nil where the game hides positions.
function B.MyWorldPosition()
	if unitPositionAgrees then
		local north, west, _, continent = UnitPosition("player")
		if north then
			return continent, north, west
		end
	end
	return MapRoutePosition()
end

local function CurrentState()
	if not M.db.share then
		return "S" .. VERSION .. ";;;;;;"
	end
	local flags, target = "", ""
	if UnitIsDeadOrGhost("player") then
		flags = UnitIsGhost("player") and "G" or "D"
	end
	if UnitAffectingCombat("player") then
		flags = flags .. "C"
		if UnitExists("target") and UnitCanAttack("player", "target") then
			target = B.Clean(UnitName("target"), 48)
		end
	end
	local position = ";;"
	local continent, north, west = MapRoutePosition()
	if continent then
		position = ("%d;%.1f;%.1f"):format(continent, north, west)
	end
	return ("S%s;%s;%s;%s;%s"):format(VERSION, flags, position, B.Clean(GetSubZoneText(), 48), target)
end

-- Enemies fighting me: nameplate units (tracked from NAME_PLATE_UNIT_ADDED/REMOVED) that can be
-- attacked and have me on their threat list. Needs enemy nameplates on; mobs without a nameplate
-- (out of range, nameplates off) aren't counted. nil when the game keeps threat secret.
local plates = {}
local lastCount, lastCountCheck = 0, -math.huge

local function EnemyCount()
	local count = 0
	for unit in pairs(plates) do
		if UnitCanAttack("player", unit) then
			local threat = UnitThreatSituation("player", unit)
			if issecretvalue and issecretvalue(threat) then
				return nil
			end
			if threat then
				count = count + 1
			end
		end
	end
	return count
end

-- On the tick, only in combat (and only with sharing on): tell friends when the number changes.
local function SendCountIfChanged(now)
	if not (M.db.share and UnitAffectingCombat("player")) then
		lastCount = 0 -- friends drop the count when the fight ends; the next one starts at 0
		return
	end
	if now - lastCountCheck < COUNT_GAP then
		return
	end
	lastCountCheck = now
	local count = EnemyCount()
	if count and count ~= lastCount then
		lastCount = count
		B.QueueToPeers(("C%s;%d"):format(VERSION, math.min(count, 99)), true)
	end
end

local NO_XP = "X" .. VERSION .. ";"

-- Progress on my current level in whole percent; none at max level or with sharing off.
local function CurrentXP()
	if not M.db.share or (IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel()) then
		return NO_XP
	end
	local xp, xpMax = UnitXP("player"), UnitXPMax("player")
	if issecretvalue and (issecretvalue(xp) or issecretvalue(xpMax)) or not xpMax or xpMax <= 0 then
		return NO_XP
	end
	return ("X%s;%d"):format(VERSION, math.min(99, math.floor(xp / xpMax * 100)))
end

local function SendXPIfChanged(now)
	if not xpDirty or now - lastXPCheck < XP_GAP then
		return
	end
	xpDirty, lastXPCheck = false, now
	local message = CurrentXP()
	if message ~= lastXP then
		lastXP = message
		B.QueueToPeers(message, true)
	end
end

local NO_QUEST = "T" .. VERSION .. ";0;;;"

-- The quest I'm tracking: the super-tracked one (the arrow), else the first on the tracker.
local function CurrentQuest()
	if not M.db.shareQuest then
		return NO_QUEST
	end
	local questID = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
	if not questID or questID == 0 then
		questID = C_QuestLog.GetQuestIDForQuestWatchIndex and C_QuestLog.GetQuestIDForQuestWatchIndex(1)
	end
	local title = type(questID) == "number" and questID > 0 and C_QuestLog.GetTitleForQuestID(questID)
	if not title then
		return NO_QUEST
	end
	local done, objective = C_QuestLog.IsComplete(questID), ""
	if not done then
		for _, o in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
			if not o.finished and type(o.text) == "string" and o.text ~= "" then
				objective = o.text
				break
			end
		end
	end
	return ("T%s;%d;%s;%s;%s"):format(VERSION, questID, done and "1" or "0", B.Clean(title, 64), B.Clean(objective, 64))
end

-- On the tick: tell friends when my tracked quest or its progress changed.
local function SendQuestIfChanged(now)
	if not questDirty or now - lastQuestCheck < QUEST_GAP then
		return
	end
	questDirty, lastQuestCheck = false, now
	local quest = CurrentQuest()
	if quest ~= lastQuest then
		lastQuest = quest
		B.QueueToPeers(quest, true)
	end
end

---------------------------------------------------------------------------
-- Sending: everything goes through the rate limiter in Drain()
---------------------------------------------------------------------------

local RESULT = Enum and Enum.SendAddonMessageResult or {}
-- Temporary refusals: keep the message and try again after a pause.
local RETRY_LATER = {
	[RESULT.AddonMessageThrottle or 3] = true,  -- the server asked us to slow down
	[RESULT.AddOnMessageLockdown or 11] = true, -- addon messages are locked for now (e.g. encounters)
}

-- false: try again later. Other failures (friend went offline, ...) drop the message; the next
-- state or heartbeat covers states, and a friend who is gone doesn't need the rest.
local function SendNow(gameAccountID, message)
	local ok, result = pcall(C_BattleNet.SendGameData, gameAccountID, PREFIX, message)
	if ok and RETRY_LATER[result] then
		return false
	end
	stats.sent = stats.sent + 1
	return true
end

function B.Queue(gameAccountID, message)
	outbox[#outbox + 1] = { gameAccountID, message }
end

-- latest: a value that only matters in its newest form (tracked quest, enemy count, level
-- progress). If one of the same kind is still waiting for that friend, it's replaced instead of
-- queued behind it, so a busy fight can't pile them up in front of position updates.
function B.QueueToPeers(message, latest)
	local kind = latest and message:sub(1, 1)
	for gameAccountID in pairs(peers) do
		local replaced = false
		if latest then
			for _, item in ipairs(outbox) do
				if item[1] == gameAccountID and item[2]:sub(1, 1) == kind then
					item[2], replaced = message, true
					break
				end
			end
		end
		if not replaced then
			B.Queue(gameAccountID, message)
		end
	end
end

local function Drain(now, elapsed)
	tokens = math.min(SEND_BURST, tokens + elapsed * SEND_RATE)
	if now < pausedUntil then
		return
	end
	while tokens >= 1 and outbox[1] do
		local item = outbox[1]
		if not SendNow(item[1], item[2]) then
			pausedUntil, stats.throttled = now + THROTTLE_PAUSE, stats.throttled + 1
			return
		end
		table.remove(outbox, 1)
		tokens = tokens - 1
	end
	if tokens >= 1 and next(owed) then
		local state = CurrentState()
		for gameAccountID in pairs(owed) do
			if tokens < 1 then
				return
			end
			if peers[gameAccountID] then
				if not SendNow(gameAccountID, state) then
					pausedUntil, stats.throttled = now + THROTTLE_PAUSE, stats.throttled + 1
					return
				end
				tokens = tokens - 1
			end
			owed[gameAccountID] = nil
		end
	end
	-- Bulk data (Chronicle's days for friends' graphs) only goes when nothing else waits, so it
	-- never delays positions, states or anything someone clicked.
	while tokens >= 1 and lowOutbox[1] and not outbox[1] and not next(owed) do
		local item = lowOutbox[1]
		if peers[item[1]] then
			if not SendNow(item[1], item[2]) then
				pausedUntil, stats.throttled = now + THROTTLE_PAUSE, stats.throttled + 1
				return
			end
			tokens = tokens - 1
		end
		table.remove(lowOutbox, 1)
	end
end

-- Low priority (see Drain): sent when nothing else is waiting.
function B.QueueLow(gameAccountID, message)
	lowOutbox[#lowOutbox + 1] = { gameAccountID, message }
end

function B.QueueLowToPeers(message)
	for gameAccountID in pairs(peers) do
		B.QueueLow(gameAccountID, message)
	end
end

-- Every <interval> seconds (sooner after a status change): send my state if it changed, or
-- as a heartbeat. Standing still out of combat sends one small message every HEARTBEAT seconds.
local function SendStateIfChanged(now)
	if not next(peers) or now - lastSent < STATUS_GAP or not (statusDirty or now - lastCheck >= M.db.interval) then
		return
	end
	statusDirty, lastCheck = false, now
	local state = CurrentState()
	if state ~= lastState or now - lastSent >= HEARTBEAT then
		lastState, lastSent = state, now
		for gameAccountID in pairs(peers) do
			owed[gameAccountID] = true
		end
	end
end

---------------------------------------------------------------------------
-- Finding friends with the addon
---------------------------------------------------------------------------

local function IsUsableAccount(info)
	return info and info.isOnline and info.gameAccountID
		and info.clientProgram == (BNET_CLIENT_WOW or "WoW")
		and info.isInCurrentRegion ~= false
		and info.wowProjectID == WOW_PROJECT_ID
end

local function CopyInfo(peer, info)
	if peer.name ~= info.characterName or peer.level ~= info.characterLevel or peer.classFile ~= info.classFilename then
		peer.rev = peer.rev + 1
		Changed()
	end
	if not peer.name and info.characterName then
		-- "known": a friend with LefthyTools is here now (Chronicle sends them its last days).
		comings[#comings + 1] = { "known", peer, { id = info.gameAccountID } }
		if GetTime() - enabledAt > ONLINE_QUIET then
			comings[#comings + 1] = { "online", peer } -- someone just came online with LefthyTools
		end
	end
	peer.name, peer.classFile, peer.guid = info.characterName, info.classFilename, info.playerGuid
	peer.level, peer.area = info.characterLevel, info.areaName
end

local function Forget(gameAccountID)
	local peer = peers[gameAccountID]
	if peer then
		peers[gameAccountID] = nil
		Changed()
		if peer.name then
			comings[#comings + 1] = { "offline", peer }
		end
	end
	owed[gameAccountID] = nil
end

-- Walks the friend list: greets online WoW friends we don't know yet. Runs once a minute and
-- shortly after a friend comes online; never from inside an event handler.
local function Sweep(now)
	lastSweep, sweepRequested = now, false
	for i = 1, (BNGetNumFriends() or 0) do
		for j = 1, (C_BattleNet.GetFriendNumGameAccounts(i) or 0) do
			local info = C_BattleNet.GetFriendGameAccountInfo(i, j)
			if IsUsableAccount(info) then
				local id = info.gameAccountID
				if peers[id] then
					CopyInfo(peers[id], info)
				elseif not otherVersion[id] and (not helloAt[id] or now - helloAt[id] >= HELLO_RETRY) then
					helloAt[id] = now
					B.Queue(id, "H" .. VERSION)
				end
			end
		end
	end
end

-- Known friends only: still online in WoW? Refreshes name, level and zone on the way.
local function Validate(now)
	lastValidate, validateRequested = now, false
	for gameAccountID, peer in pairs(peers) do
		local info = C_BattleNet.GetGameAccountInfoByID(gameAccountID)
		if IsUsableAccount(info) then
			CopyInfo(peer, info)
		else
			Forget(gameAccountID)
		end
	end
	groupChanged = true -- names/GUIDs may be new: check them against my group too
end

local function Expire(now)
	lastExpire = now
	for gameAccountID, peer in pairs(peers) do
		if now - peer.seen > PEER_TIMEOUT then
			Forget(gameAccountID)
		end
	end
end

---------------------------------------------------------------------------
-- Receiving (state only; the driver tick does the sending and drawing)
---------------------------------------------------------------------------

-- Returns the message kind and its fields, "version" plus their version for another
-- LefthyTools version, or nil for anything that isn't exactly our protocol.
local function Parse(text)
	if type(text) ~= "string" or #text > 255 then
		return nil
	end
	local kind, version, rest = text:match("^(%u)(%d+)(.*)$")
	if not kind then
		return nil
	elseif version ~= VERSION then
		return "version", version
	elseif (kind == "H" or kind == "Q") and rest == "" then
		return kind
	elseif kind == "S" then
		local flags, continent, north, west, subzone, target =
			rest:match("^;(%u*);(%-?%d*);(%-?[%d%.]*);(%-?[%d%.]*);([^;]*);([^;]*)$")
		if not flags then
			return nil
		end
		local c, n, w = tonumber(continent), tonumber(north), tonumber(west)
		local hasPos = c ~= nil and n ~= nil and w ~= nil
		if not hasPos and (continent ~= "" or north ~= "" or west ~= "") then
			return nil
		end
		return "S", flags, hasPos and c, n, w, subzone, target
	elseif kind == "L" then
		local level, message = rest:match("^;(%d+);([^;]*)$")
		if level then
			return "L", tonumber(level), message
		end
	elseif kind == "V" then
		local version = rest:match("^;([%w%.%-]+)$")
		if version and #version <= 40 then
			return "V", version
		end
	elseif kind == "P" then
		local continent, north, west, mapID = rest:match("^;(%d+);(%-?%d+%.?%d*);(%-?%d+%.?%d*);(%d+)$")
		if continent then
			return "P", tonumber(continent), tonumber(north), tonumber(west), tonumber(mapID)
		end
	elseif kind == "T" then
		local questID, done, title, objective = rest:match("^;(%d+);([01]?);([^;]*);([^;]*)$")
		if questID then
			return "T", tonumber(questID), done == "1", title, objective
		end
	elseif kind == "E" then
		local highlight, a, b = rest:match("^;(%l+);([^;]*);([^;]*)$")
		if highlight and HIGHLIGHTS[highlight] then
			return "E", highlight, a, b
		end
	elseif kind == "C" then
		local count = rest:match("^;(%d%d?)$")
		if count then
			return "C", tonumber(count)
		end
	elseif kind == "X" then
		local percent = rest:match("^;(%d?%d?)$")
		if percent then
			return "X", tonumber(percent) -- nil: not shared
		end
	elseif kind == "I" then
		local itemString, callID = rest:match("^;(%d+[%-%d:]*);(%d+)$")
		itemString = itemString or rest:match("^;(%d+[%-%d:]*)$")
		if itemString then
			return "I", itemString, tonumber(callID) -- no call id: just showing it
		end
	elseif kind == "N" then
		local callID, need = rest:match("^;(%d+);([01])$")
		if callID then
			return "N", tonumber(callID), need == "1"
		end
	elseif kind == "R" then
		local callID, result = rest:match("^;(%d+);([^;]*)$")
		if callID and #result <= 200 then
			return "R", tonumber(callID), result
		end
	elseif kind == "D" then
		local y, mo, d, played, xp, quests, kills, deaths, levels =
			rest:match("^;(%d%d%d%d)(%d%d)(%d%d);(%d+);(%d+);(%d+);(%d+);(%d+);(%d+)$")
		if y and tonumber(played) <= 1440 and #xp <= 9 and #quests <= 5 and #kills <= 6 and #deaths <= 4 and #levels <= 3 then
			return "D", { day = y .. "-" .. mo .. "-" .. d, played = tonumber(played) * 60, xp = tonumber(xp),
				quests = tonumber(quests), kills = tonumber(kills), deaths = tonumber(deaths), levels = tonumber(levels) }
		end
	end
	return nil
end

-- Returns true and who they were fighting (or nil) when this state says they just died.
local function ApplyState(peer, now, flags, continent, north, west, subzone, target)
	local wasAlive = peer.stateSeen and not (peer.dead or peer.ghost)
	-- Their killer: whom they were fighting in their last state before this one. A long fight
	-- sends no new state, so the time since then doesn't matter.
	local foe = peer.combat and peer.target ~= "" and peer.target or nil
	peer.dead, peer.ghost = flags:find("D", 1, true) ~= nil, flags:find("G", 1, true) ~= nil
	peer.combat = flags:find("C", 1, true) ~= nil
	if not peer.combat then
		peer.mobs = nil -- the fight is over
	end
	peer.subzone, peer.target = B.Clean(subzone, 48), B.Clean(target, 48)
	peer.stateSeen = true
	if continent then
		local fromNorth, fromWest, glide = north, west, 0
		if peer.hasPos and peer.continent == continent then
			local drawnNorth, drawnWest = B.DrawnPosition(peer, now)
			local dn, dw = north - drawnNorth, west - drawnWest
			if dn * dn + dw * dw < GLIDE_SNAP * GLIDE_SNAP then
				fromNorth, fromWest = drawnNorth, drawnWest
				glide = math.min(math.max(now - peer.posTime, 0.2), 10)
			end
		end
		peer.hasPos, peer.continent, peer.north, peer.west = true, continent, north, west
		peer.fromNorth, peer.fromWest, peer.glide, peer.posTime = fromNorth, fromWest, glide, now
	else
		peer.hasPos = false
	end
	peer.rev = peer.rev + 1
	Changed()
	if wasAlive and (peer.dead or peer.ghost) then
		return true, foe
	end
end

local function OnMessage(text, senderID)
	if type(senderID) ~= "number" then
		return
	end
	local now = GetTime()
	-- Per sender, kept even when the peer is forgotten (so "Q2" can't reset the guards).
	local guard = inbox[senderID]
	if not guard then
		guard = { count = 0, window = now }
		inbox[senderID] = guard
	end
	if now - guard.window >= 1 then
		guard.count, guard.window = 0, now
	end
	guard.count = guard.count + 1
	if guard.count > INBOX_LIMIT then
		return -- a friend's client gone haywire can't flood us
	end

	local kind, a, b, c, d, e, f = Parse(text)
	if not kind then
		return -- malformed: don't even count the sender as a friend with the addon
	end
	stats.received = stats.received + 1
	if kind == "version" then
		otherVersion[senderID] = a
		return
	elseif kind == "Q" then
		Forget(senderID)
		return
	end

	local peer = peers[senderID]
	local answer = false
	if not peer then
		peer = { seen = now, rev = 0, hasPos = false, glide = 0 }
		peers[senderID] = peer
		otherVersion[senderID] = nil
		answer = true              -- they just found us: they need my state too
		validateRequested = true   -- fetch name and class on the next tick
	end
	peer.seen = now
	if kind == "H" then
		answer = true              -- they (re)started the addon: answer with my state
	elseif kind == "S" then
		local died, foe = ApplyState(peer, now, a, b, c, d, e, f)
		if died and (not guard.deathAt or now - guard.deathAt >= DEATH_GAP) then
			guard.deathAt = now
			deaths[#deaths + 1] = { senderID, foe }
		end
	elseif kind == "L" then
		if not guard.dingAt or now - guard.dingAt >= DING_GAP then
			guard.dingAt = now
			dings[#dings + 1] = { senderID, a, b }
		end
	elseif kind == "T" then
		local title = B.Clean(c, 64)
		peer.quest = a > 0 and title ~= "" and { id = a, done = b, title = title, objective = B.Clean(d, 64) } or nil
		peer.rev = peer.rev + 1
		Changed() -- an open tooltip shows it
	elseif kind == "C" then
		peer.mobs = a
		peer.rev = peer.rev + 1
		Changed()
	elseif kind == "X" then
		peer.xpPercent = a
		peer.rev = peer.rev + 1
		Changed()
	elseif kind == "I" then
		if not guard.itemAt or now - guard.itemAt >= ITEM_GAP then
			guard.itemAt = now
			itemsIn[#itemsIn + 1] = { "item", senderID, a, b }
		end
	elseif kind == "N" or kind == "R" then
		-- One per call each way; a count per window, so two in the same moment both count.
		if not guard.callWindow or now - guard.callWindow >= CALL_WINDOW then
			guard.callWindow, guard.calls = now, 0
		end
		if guard.calls < CALL_LIMIT then
			guard.calls = guard.calls + 1
			itemsIn[#itemsIn + 1] = { kind == "N" and "answer" or "result", senderID, a, b }
		end
	elseif kind == "D" then
		if not guard.dailyWindow or now - guard.dailyWindow >= 60 then
			guard.dailyWindow, guard.daily = now, 0
		end
		if guard.daily < DAILY_LIMIT then
			guard.daily = guard.daily + 1
			dailyIn[#dailyIn + 1] = { senderID, a }
		end
	elseif kind == "E" then
		if not guard.highlightWindow or now - guard.highlightWindow >= HIGHLIGHT_WINDOW then
			guard.highlightWindow, guard.highlights = now, 0
		end
		if guard.highlights < HIGHLIGHT_LIMIT then
			guard.highlights = guard.highlights + 1
			highlightsIn[#highlightsIn + 1] = { senderID, a, B.Clean(b, 64), B.Clean(c, 64) }
		end
	elseif kind == "P" then
		if M.db.pings and (not guard.pingAt or now - guard.pingAt >= PING_GAP) then
			guard.pingAt = now
			pingsIn[#pingsIn + 1] = { senderID, a, b, c, d }
		end
	elseif kind == "V" then
		peer.version = a
		LT:NoteFriendVersion(a) -- the settings overview shows it
		if not newerNoticeShown and LT.CompareVersions(a, LT.version) == 1 then
			newerFrom = senderID -- told on the next tick, once their name is known
		end
	end
	-- At most one answer per ANSWER_GAP, so repeated hellos can't eat the send budget.
	if answer and (not guard.answeredAt or now - guard.answeredAt >= ANSWER_GAP) then
		guard.answeredAt = now
		owed[senderID] = true
		B.Queue(senderID, "V" .. VERSION .. ";" .. B.Clean(LT.version, 40)) -- my LefthyTools build
		if lastQuest and lastQuest ~= NO_QUEST then
			B.Queue(senderID, lastQuest)
		end
		if lastXP and lastXP ~= NO_XP then
			B.Queue(senderID, lastXP)
		end
	end
end

---------------------------------------------------------------------------
-- Driver, lifecycle and events
---------------------------------------------------------------------------

local driver = CreateFrame("Frame")
local events = CreateFrame("Frame")
local sinceTick = 0
local pendingLevel

local function Tick(now, elapsed)
	if validateRequested and now - lastValidate >= 1 or now - lastValidate >= VALIDATE_INTERVAL then
		Validate(now)
	end
	if now - lastSweep >= SWEEP_INTERVAL or (sweepRequested and now - lastSweep >= SWEEP_COALESCE) then
		Sweep(now)
	end
	if groupChanged then
		groupChanged = false
		UpdateGroupUnits()
		Changed()
	end
	if pendingLevel then
		local level = pendingLevel
		pendingLevel = nil
		if B.AnnounceLevel then
			B.AnnounceLevel(level)
		end
	end
	SendStateIfChanged(now)
	SendQuestIfChanged(now)
	SendCountIfChanged(now)
	SendXPIfChanged(now)
	Drain(now, elapsed)

	while dings[1] do
		local ding = table.remove(dings, 1)
		local peer = peers[ding[1]]
		if peer and peer.name and B.ShowDing then
			B.ShowDing(peer, ding[2], ding[3])
		end
	end
	while deaths[1] do
		local death = table.remove(deaths, 1)
		local peer = peers[death[1]]
		if peer and peer.name and B.ShowDeath then
			B.ShowDeath(peer, death[1], death[2])
		end
	end
	while pingsIn[1] do
		local ping = table.remove(pingsIn, 1)
		local peer = peers[ping[1]]
		if peer and peer.name and B.ReceivePing then
			B.ReceivePing(peer, ping[1], ping[2], ping[3], ping[4], ping[5])
		end
	end
	while comings[1] do
		local item = table.remove(comings, 1)
		B.Notify(item[1], item[2], item[3] or {})
	end
	while dailyIn[1] do
		local item = table.remove(dailyIn, 1)
		local peer = peers[item[1]]
		if peer and peer.name then
			B.Notify("daily", peer, item[2])
		end
	end
	while itemsIn[1] do -- Items.lua: shared items, Need / Pass answers, roll results
		local item = table.remove(itemsIn, 1)
		local peer = peers[item[2]]
		if peer and peer.name and B.ReceiveItem then
			if item[1] == "item" then
				B.ReceiveItem(peer, item[2], item[3], item[4])
			elseif item[1] == "answer" then
				B.ReceiveAnswer(peer, item[2], item[3], item[4])
			else
				B.ReceiveResult(peer, item[2], item[3], item[4])
			end
		end
	end
	if B.UpdateCalls then
		B.UpdateCalls(now)
	end
	while highlightsIn[1] do
		local item = table.remove(highlightsIn, 1)
		local peer = peers[item[1]]
		if peer and peer.name then
			B.Notify("highlight", peer, { kind = item[2], a = item[3], b = item[4] })
		end
	end
	if B.UpdatePings then
		B.UpdatePings(now)
	end
	-- A friend runs a newer LefthyTools: say so once per login (a /reload counts as one).
	local newer = newerFrom and peers[newerFrom]
	if newer and newer.name and not newerNoticeShown then
		newerNoticeShown, newerFrom = true, nil
		M:Print(string.format("%s has a newer LefthyTools (%s, you have %s). To update, run "
			.. "Update-LefthyTools.cmd again, then /reload.", newer.name, newer.version, LT.version))
	elseif newerFrom and not peers[newerFrom] then
		newerFrom = nil
	end
	if now - lastExpire >= 1 then
		Expire(now)
	end
	if B.dirty and now - lastRefresh >= REFRESH_THROTTLE then
		lastRefresh = now
		B.dirty = false
		if B.RefreshMaps then
			B.RefreshMaps()
		end
	end
end

local function OnUpdate(_, elapsed)
	local now = GetTime()
	sinceTick = sinceTick + elapsed
	if sinceTick >= TICK then
		Tick(now, sinceTick)
		sinceTick = 0
	end
	if B.UpdateMinimap then
		B.UpdateMinimap(now) -- every frame, but returns at once unless a dot has to move
	end
	if B.UpdateWorldMapGroupPins then
		B.UpdateWorldMapGroupPins() -- only does something with the map open and group friends on it
	end
end

local handlers = B.handlers

function handlers.BN_CHAT_MSG_ADDON(prefix, text, _, senderID)
	if prefix == PREFIX then
		OnMessage(text, senderID)
	end
end

handlers.BN_FRIEND_ACCOUNT_ONLINE = function() sweepRequested = true end
-- Fires whenever any friend changes zone, in any game: only re-check the friends we know.
handlers.BN_FRIEND_INFO_CHANGED = function() validateRequested = true end
handlers.BN_FRIEND_ACCOUNT_OFFLINE = handlers.BN_FRIEND_INFO_CHANGED
handlers.PLAYER_ENTERING_WORLD = function()
	sweepRequested, statusDirty, lastSweep, lastState = true, true, -math.huge, nil
end
handlers.GROUP_ROSTER_UPDATE = function() groupChanged = true end
handlers.NAME_PLATE_UNIT_ADDED = function(unit) plates[unit] = true end
handlers.NAME_PLATE_UNIT_REMOVED = function(unit) plates[unit] = nil end
local function MarkQuestDirty() questDirty = true end
handlers.QUEST_LOG_UPDATE = MarkQuestDirty
handlers.QUEST_WATCH_LIST_CHANGED = MarkQuestDirty
handlers.SUPER_TRACKING_CHANGED = MarkQuestDirty
handlers.PLAYER_LEVEL_UP = function(level) pendingLevel, xpDirty = level, true end
handlers.PLAYER_XP_UPDATE = function() xpDirty = true end

local function MarkStatusDirty() statusDirty = true end
for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD", "PLAYER_ALIVE",
		"PLAYER_UNGHOST", "PLAYER_TARGET_CHANGED", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
	handlers[event] = MarkStatusDirty
end

events:SetScript("OnEvent", function(_, event, ...)
	local handler = handlers[event]
	if handler then
		handler(...)
	end
end)

local prefixRegistered = false

-- Switched off: only the goodbyes are left. They go through the rate limiter like everything
-- else (the server throttles bursts), from the next frame on, until sent or FAREWELL_TIMEOUT.
local farewellUntil
local function FarewellUpdate(_, elapsed)
	local now = GetTime()
	Drain(now, elapsed)
	if not outbox[1] or now > farewellUntil then
		wipe(outbox)
		farewellUntil = nil
		driver:SetScript("OnUpdate", nil)
	end
end

function M:OnEnable()
	if not prefixRegistered then
		prefixRegistered = true
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
	end
	for event in pairs(handlers) do
		pcall(events.RegisterEvent, events, event)
	end
	ResetTimers()
	wipe(outbox) -- goodbyes still pending from switching off just before: no longer true
	wipe(lowOutbox)
	farewellUntil = nil
	tokens, pausedUntil, sinceTick = SEND_BURST, 0, 0
	stats.sent, stats.received, stats.throttled, stats.since = 0, 0, 0, GetTime()
	enabledAt = GetTime()
	driver:SetScript("OnUpdate", OnUpdate)
	if B.Attach then
		C_Timer.After(0, B.Attach)
	end
end

function M:OnDisable()
	events:UnregisterAllEvents()
	wipe(outbox)
	wipe(owed)
	wipe(lowOutbox)
	for gameAccountID in pairs(peers) do
		B.Queue(gameAccountID, "Q" .. VERSION) -- friends drop my dot and stop sending to me
	end
	for _, t in ipairs({ peers, helloAt, otherVersion, inbox, dings, deaths, pingsIn, highlightsIn, itemsIn, dailyIn,
			comings, B.pings, plates }) do
		wipe(t)
	end
	sweepRequested, validateRequested, statusDirty, pendingLevel = false, false, false, nil
	B.dirty = false
	farewellUntil = GetTime() + FAREWELL_TIMEOUT
	driver:SetScript("OnUpdate", outbox[1] and FarewellUpdate or nil)
	if B.Detach then
		C_Timer.After(0, B.Detach) -- removes the dots too
	end
	if B.ReleaseCalls then
		C_Timer.After(0, B.ReleaseCalls) -- open Need / Pass notices
	end
end

function M:OnSettingChanged()
	statusDirty, lastCheck = true, -math.huge -- e.g. sharing switched: tell friends right away
	questDirty, lastQuestCheck = true, -math.huge
	xpDirty, lastXPCheck = true, -math.huge
	Changed()
	if B.OnSettingChanged then
		B.OnSettingChanged() -- Ding.lua: a newly picked level-up sound is played
	end
end

---------------------------------------------------------------------------
-- Settings page and /lefthy beacon
---------------------------------------------------------------------------

function M:BuildOptions(o)
	o:Header(L["Sharing"])
	o:Checkbox("share", L["Share my position"],
		L["Battle.net friends who also use LefthyTools see you on their maps, and whether you're dead or in combat. Not available in dungeons and raids."])
	o:Checkbox("shareQuest", L["Share the quest I'm tracking"],
		L["Friends see the quest you're tracking, and your progress, when they hover your dot."])
	o:Slider("interval", L["Update interval"],
		L["How often your position is sent while you move. Standing still sends almost nothing."],
		1, 10, 1, LT.Options.Seconds)

	o:Header(L["Map"])
	o:Checkbox("showFriends", L["Show friends on the world map"],
		L["Dots in their class colour, a skull when they're dead and a red ring in combat. Hover for details. Friends in your group are already shown by the game."])
	o:Checkbox("showMinimap", L["Show friends on the minimap"],
		L["The same dots on the minimap. Friends in your group are already shown by the game."])
	o:Checkbox("minimapEdge", L["Keep far-away friends at the minimap edge"],
		L["Friends beyond the minimap's range stay faded at its edge, so you can see which way they are."])
	o:Checkbox("showGroup", L["Show friends in my group too"],
		L["Friends in your group keep their Beacon dot, with a blue ring, on top of the game's own group dot, and the tooltip says they're in your group. Off: only the game's dot."])

	o:Header(L["Alerts"])
	o:Checkbox("deathAlert", L["Tell me when a friend dies"],
		L["A chat line when a friend dies: where, and what they were fighting."])
	o:Checkbox("shareItems", L["Show items to friends"],
		L["Ctrl+right-click an item that can be traded (bags, bank, loot, chat links) to show it to your friends: they see it at the top of the screen, with the whisper sound. Ctrl+Shift+right-click offers it: they can say Need or Pass, and if several need it, it is rolled out. The item stays reserved for the winner until you hand it over."])
	o:Button(L["Hand-over reminders"], L["Clear"], function() B.HandoverCommand("clear") end,
		L["Items you offered and someone won stay reserved until you trade or mail them to the winner: a tooltip line, a bag border, a question at vendors. This forgets all of them, in case one is stuck. /lefthy beacon handover lists them."])
	o:Checkbox("pings", L["Map pings"],
		L["Alt+click on the world map shows your friends a spot: a marker on their maps for a minute, with a sound. Their pings show up on your maps. /lefthy beacon ping pings where you stand."])

	if B.BuildDingOptions then
		B.BuildDingOptions(o)
	end
end

function M:GetPeers()
	return peers
end

-- A Chronicle highlight for every friend with Beacon (Chronicle.lua calls this on its tick).
function B.ShareHighlight(kind, a, b)
	if M.enabled and HIGHLIGHTS[kind] then
		B.QueueToPeers(("E%s;%s;%s;%s"):format(VERSION, kind, B.Clean(tostring(a or ""), 64), B.Clean(tostring(b or ""), 64)))
	end
end

local function StatusWords(peer)
	local words = {}
	if peer.ghost then
		words[#words + 1] = "ghost"
	elseif peer.dead then
		words[#words + 1] = "dead"
	end
	if peer.combat then
		words[#words + 1] = peer.target ~= "" and ("fighting " .. peer.target) or "in combat"
	end
	return #words > 0 and (", " .. table.concat(words, ", ")) or ""
end

function M:OnSlashCommand(msg)
	local cmd, arg = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()
	if cmd == "" then
		LT:OpenSettings(self)
	elseif cmd == "status" or cmd == "friends" then
		local count, now = 0, GetTime()
		for gameAccountID, peer in pairs(peers) do
			count = count + 1
			self:Print(string.format("  %s - %s%s, LefthyTools %s", peer.name or ("#" .. gameAccountID),
				peer.hasPos and string.format("position %.0f s ago", now - peer.posTime)
					or "no position (dungeon, raid or not sharing)", StatusWords(peer),
				peer.version or "0.3.0 or older"))
		end
		for gameAccountID, version in pairs(otherVersion) do
			local info = C_BattleNet.GetGameAccountInfoByID(gameAccountID)
			self:Print(string.format("  %s runs another LefthyTools version (Beacon %s, you have %s): update both to the same version.",
				info and info.characterName or ("#" .. gameAccountID), version, VERSION))
		end
		self:Print(count == 0 and "no friends with LefthyTools online." or (count .. " friend(s) with LefthyTools online."))
		local minutes = math.max((now - stats.since) / 60, 1 / 60)
		self:Print(string.format("traffic: %d sent, %d received in %.0f min (%.1f / %.1f per minute), throttled %d time(s).",
			stats.sent, stats.received, minutes, stats.sent / minutes, stats.received / minutes, stats.throttled))
	elseif cmd == "interval" then
		local n = tonumber(arg)
		if n then
			LT:SetModuleSetting(self, "interval", math.max(1, math.min(10, math.floor(n + 0.5))))
		end
		self:Print("update interval: " .. LT.Options.Seconds(self.db.interval) .. ".")
	elseif cmd == "ping" and B.PingMe then
		B.PingMe()
	elseif cmd == "sound" and B.SoundCommand then
		B.SoundCommand(arg)
	elseif cmd == "ding" and B.DingCommand then
		B.DingCommand(arg)
	elseif cmd == "handover" and B.HandoverCommand then
		B.HandoverCommand(arg)
	else
		self:Print("/lefthy beacon - open settings")
		self:Print("/lefthy beacon status - friends with LefthyTools, their last update and the message traffic")
		self:Print("/lefthy beacon interval <1-10> - seconds between position updates while moving")
		self:Print("/lefthy beacon ping - show your friends where you stand (or Alt+click the world map)")
		self:Print("/lefthy beacon ding <text> | reset | test - your level-up message; {name} and {level} are filled in")
		self:Print("/lefthy beacon sound [<number>] - list the level-up sounds, or pick one and hear it")
		self:Print("/lefthy beacon handover [clear] - items you offered that winners still have to get")
	end
end
