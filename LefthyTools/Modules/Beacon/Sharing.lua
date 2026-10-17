local _, ns = ...
local LT = ns.LT
local M = LT:GetModule("beacon")
local B = ns.Beacon

-- What I tell my friends about myself: my state (S2: dead or a ghost, in combat and whom I fight,
-- where I am), the quest I'm tracking (T2), my progress on my level (X2), in combat how many enemies
-- are on me (C2), my level-ups (L2: Ding.lua words them), Chronicle's highlights (E2), and my build
-- every 10 minutes (F2 / V2; every answer carries it too). Event handlers only mark what may have
-- changed; Beacon.lua's tick calls B.SharingTick, which looks at most every so often and sends only
-- what changed. The state: checked every <interval> seconds (a status change at most once a second),
-- sent when it changed or as a heartbeat every HEARTBEAT seconds. The rest replace one of their
-- kind still waiting for a friend (B.QueueToPeers(message, true)), so they never pile up.

local VERSION = B.VERSION
local HEARTBEAT = 20         -- resend an unchanged state this often, so friends know I'm still here
local STATUS_GAP = 1         -- status changes (combat, death, target) go out at most this often
local QUEST_GAP = 2          -- my tracked quest is checked (and sent if changed) at most this often
local COUNT_GAP = 1          -- in combat: enemies counted (and sent if changed) at most this often
local XP_GAP = 2             -- my level progress is checked (and sent if changed) at most this often
local VERSION_EVERY = 600    -- my version goes to every friend this often too (besides answers)

local statusDirty = false -- combat, death, target or zone changed: look at my state soon
local questDirty = true   -- my tracked quest may have changed
local xpDirty = true      -- my experience may have changed
local pendingLevel        -- I levelled up: friends are told on the next tick
local lastCheck, lastSent, lastQuestCheck, lastXPCheck
local lastState, lastQuest, lastXP
local lastVersionSent = 0 -- my version to every friend every VERSION_EVERY seconds too

---------------------------------------------------------------------------
-- My own position, my state, what's on me, my level, my quest
---------------------------------------------------------------------------

-- The map route (verified in game) is what we send. The minimap needs my position every frame
-- while moving; UnitPosition gives it without creating tables, so it's used once it has been
-- seen to agree with the map route (HereBeDragons relies on the two matching), checked again
-- after every loading screen (another continent or instance).
local unitPositionAgrees = false
local issecret = issecretvalue or function() return false end

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
		unitPositionAgrees = uNorth ~= nil and not (issecret(uNorth) or issecret(uWest) or issecret(uContinent))
			and uContinent == continent and math.abs(uNorth - north) < 2 and math.abs(uWest - west) < 2
	end
	return continent, north, west
end

-- continent, north, west in world yards, or nil where the game hides positions.
function B.MyWorldPosition()
	if unitPositionAgrees then
		local north, west, _, continent = UnitPosition("player")
		if north and not (issecret(north) or issecret(west) or issecret(continent)) then
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

-- Every <interval> seconds (sooner after a status change): send my state if it changed, or
-- as a heartbeat. Standing still out of combat sends one small message every HEARTBEAT seconds.
local function SendStateIfChanged(now)
	if not next(B.peers) or now - lastSent < STATUS_GAP or not (statusDirty or now - lastCheck >= M.db.interval) then
		return
	end
	statusDirty, lastCheck = false, now
	local state = CurrentState()
	if state ~= lastState or now - lastSent >= HEARTBEAT then
		lastState, lastSent = state, now
		B.OweStateToAll() -- (Beacon.lua builds it when it goes: CurrentState)
	end
	-- Versions go with answers; this makes sure no friend's view of mine stays unknown or old
	-- whatever got lost (low priority: after everything else).
	if now - lastVersionSent >= VERSION_EVERY then
		lastVersionSent = now
		B.QueueLowToPeers("F" .. VERSION .. ";" .. LT.FILES)
		B.QueueLowToPeers("V" .. VERSION .. ";" .. B.Clean(LT.version, 40))
	end
end

-- A Chronicle highlight for every friend with Beacon (Chronicle.lua calls this on its tick).
function B.ShareHighlight(kind, a, b)
	if M.enabled and B.HIGHLIGHTS[kind] then
		B.QueueToPeers(("E%s;%s;%s;%s"):format(VERSION, kind, B.Clean(tostring(a or ""), 64), B.Clean(tostring(b or ""), 64)))
	end
end

---------------------------------------------------------------------------
-- Hooks for Beacon.lua
---------------------------------------------------------------------------

-- What my state message says right now (Drain builds it when it goes to a friend owed it).
B.CurrentState = CurrentState

-- On the driver tick, before the queues are sent: my level-up first, then whatever changed.
function B.SharingTick(now)
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
end

-- With every answer to a friend (after my state, build and the rest): my tracked quest and level
-- progress, which otherwise only go when they change.
function B.SharingAnswer(gameAccountID)
	if lastQuest and lastQuest ~= NO_QUEST then
		B.Queue(gameAccountID, lastQuest)
	end
	if lastXP and lastXP ~= NO_XP then
		B.Queue(gameAccountID, lastXP)
	end
end

local function Reset()
	lastCheck, lastSent, lastQuestCheck, lastXPCheck = -math.huge, -math.huge, -math.huge, -math.huge
	lastState, lastQuest, questDirty, lastXP, xpDirty = nil, nil, true, nil, true
end
Reset()

-- Beacon switched on: everything is looked at again, nameplates already up count like ones that
-- come later, and my version repeats 10 minutes from now (the answers at the start carry it).
function B.SharingStart()
	Reset()
	wipe(plates)
	for _, plate in ipairs(C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if type(unit) == "string" then
			plates[unit] = true
		end
	end
	lastVersionSent = GetTime()
end

function B.SharingStop()
	wipe(plates)
	statusDirty, pendingLevel = false, nil
end

-- A setting changed (sharing switched, say): friends are told right away.
function B.SharingSettingChanged()
	statusDirty, lastCheck = true, -math.huge
	questDirty, lastQuestCheck = true, -math.huge
	xpDirty, lastXPCheck = true, -math.huge
end

-- After a loading screen: my state goes out at once, and UnitPosition has to agree with the map
-- route again (another continent or an instance).
function B.SharingEnteredWorld()
	statusDirty, lastState = true, nil
	unitPositionAgrees = false
end

---------------------------------------------------------------------------
-- Events: they only mark what may have changed (Beacon.lua registers them)
---------------------------------------------------------------------------

local handlers = B.handlers
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
