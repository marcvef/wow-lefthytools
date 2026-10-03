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
local GLIDE_SNAP = 300       -- a jump this far (yards) is a teleport: no gliding
local TICK = 0.1
local REFRESH_THROTTLE = 0.5

local M = LT:NewModule("beacon", {
	title = "Beacon",
	description = L["Shares your position with Battle.net friends who also use LefthyTools and shows theirs on the world map and minimap, in their class colour."],
	defaults = {
		share = true,
		interval = 3,
		showFriends = true,
		showMinimap = true,
		minimapEdge = true,
		dingAnnounce = true,
		dingText = "",
		dingShow = true,
		dingSound = true,
		dingSoundKit = 50111, -- boss defeated fanfare (Ding.lua lists the choices)
	},
})

-- Shared with Dots.lua and Ding.lua.
local B = { module = M, VERSION = VERSION, handlers = {} }
ns.Beacon = B

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
local inbox = {}        -- gameAccountID -> { count, windowStart }: flood guard
local dings = {}        -- { gameAccountID, level, text } received, shown on the next tick
local stats = { sent = 0, received = 0, throttled = 0, since = 0 }

local sweepRequested, validateRequested, statusDirty = false, false, false
local lastSweep, lastValidate, lastCheck, lastSent, lastExpire, lastRefresh
local lastState
local tokens, pausedUntil = SEND_BURST, 0
-- Friends' data changed: the world map redraws on the next tick (at most twice a second, and
-- only while open), the minimap on the next frame so gliding dots start right away.
B.dirty, B.minimapDirty = false, true

local function Changed()
	B.dirty, B.minimapDirty = true, true
end

local function ResetTimers()
	lastSweep, lastValidate, lastCheck, lastSent = -math.huge, -math.huge, -math.huge, -math.huge
	lastExpire, lastRefresh = 0, -math.huge
	lastState = nil
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

-- Friends in my group are left to Blizzard, which already shows them on both maps.
function B.IsShown(peer)
	return peer.name and peer.hasPos and not (peer.guid and IsGUIDInGroup and IsGUIDInGroup(peer.guid))
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

---------------------------------------------------------------------------
-- Sending: everything goes through the rate limiter in Drain()
---------------------------------------------------------------------------

local THROTTLED = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.AddonMessageThrottle or 3

-- false: the server asked us to slow down, try again later. Other failures (lockdown, friend
-- went offline) just drop the message; the next state or heartbeat covers it.
local function SendNow(gameAccountID, message)
	local ok, result = pcall(C_BattleNet.SendGameData, gameAccountID, PREFIX, message)
	if ok and result == THROTTLED then
		return false
	end
	stats.sent = stats.sent + 1
	return true
end

function B.Queue(gameAccountID, message)
	outbox[#outbox + 1] = { gameAccountID, message }
end

function B.QueueToPeers(message)
	for gameAccountID in pairs(peers) do
		B.Queue(gameAccountID, message)
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
	if tokens < 1 or not next(owed) then
		return
	end
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
	peer.name, peer.classFile, peer.guid = info.characterName, info.classFilename, info.playerGuid
	peer.level, peer.area = info.characterLevel, info.areaName
end

local function Forget(gameAccountID)
	if peers[gameAccountID] then
		peers[gameAccountID] = nil
		Changed()
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
	end
	return nil
end

local function ApplyState(peer, now, flags, continent, north, west, subzone, target)
	peer.dead, peer.ghost = flags:find("D", 1, true) ~= nil, flags:find("G", 1, true) ~= nil
	peer.combat = flags:find("C", 1, true) ~= nil
	peer.subzone, peer.target = B.Clean(subzone, 48), B.Clean(target, 48)
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
end

local function OnMessage(text, senderID)
	if type(senderID) ~= "number" then
		return
	end
	local now = GetTime()
	local rate = inbox[senderID]
	if not rate or now - rate[2] >= 1 then
		rate = { 0, now }
		inbox[senderID] = rate
	end
	rate[1] = rate[1] + 1
	if rate[1] > INBOX_LIMIT then
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
	if not peer then
		peer = { seen = now, rev = 0, hasPos = false, glide = 0 }
		peers[senderID] = peer
		otherVersion[senderID] = nil
		owed[senderID] = true      -- they just found us: they need my state too
		validateRequested = true   -- fetch name and class on the next tick
	end
	peer.seen = now
	if kind == "H" then
		owed[senderID] = true      -- they (re)started the addon: answer with my state
	elseif kind == "S" then
		ApplyState(peer, now, a, b, c, d, e, f)
	elseif kind == "L" then
		if not peer.dingAt or now - peer.dingAt >= DING_GAP then
			peer.dingAt = now
			dings[#dings + 1] = { senderID, a, b }
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
	if pendingLevel then
		local level = pendingLevel
		pendingLevel = nil
		if B.AnnounceLevel then
			B.AnnounceLevel(level)
		end
	end
	SendStateIfChanged(now)
	Drain(now, elapsed)

	while dings[1] do
		local ding = table.remove(dings, 1)
		local peer = peers[ding[1]]
		if peer and peer.name and B.ShowDing then
			B.ShowDing(peer, ding[2], ding[3])
		end
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
handlers.GROUP_ROSTER_UPDATE = function() Changed() end
handlers.PLAYER_LEVEL_UP = function(level) pendingLevel = level end

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

function M:OnEnable()
	if not prefixRegistered then
		prefixRegistered = true
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
	end
	for event in pairs(handlers) do
		pcall(events.RegisterEvent, events, event)
	end
	ResetTimers()
	tokens, pausedUntil, sinceTick = SEND_BURST, 0, 0
	stats.sent, stats.received, stats.throttled, stats.since = 0, 0, 0, GetTime()
	driver:SetScript("OnUpdate", OnUpdate)
	if B.Attach then
		C_Timer.After(0, B.Attach)
	end
end

function M:OnDisable()
	for gameAccountID in pairs(peers) do
		SendNow(gameAccountID, "Q" .. VERSION) -- friends drop my dot and stop sending to me
	end
	events:UnregisterAllEvents()
	driver:SetScript("OnUpdate", nil)
	for _, t in ipairs({ peers, helloAt, otherVersion, owed, outbox, inbox, dings }) do
		wipe(t)
	end
	sweepRequested, validateRequested, statusDirty, pendingLevel = false, false, false, nil
	B.dirty = false
	if B.Detach then
		C_Timer.After(0, B.Detach) -- removes the dots too
	end
end

function M:OnSettingChanged()
	statusDirty, lastCheck = true, -math.huge -- e.g. sharing switched: tell friends right away
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

	if B.BuildDingOptions then
		B.BuildDingOptions(o)
	end
end

function M:GetPeers()
	return peers
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
			self:Print(string.format("  %s - %s%s", peer.name or ("#" .. gameAccountID),
				peer.hasPos and string.format("position %.0f s ago", now - peer.posTime)
					or "no position (dungeon, raid or not sharing)", StatusWords(peer)))
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
			self.db.interval = math.max(1, math.min(10, math.floor(n + 0.5)))
		end
		self:Print("update interval: " .. LT.Options.Seconds(self.db.interval) .. ".")
	elseif cmd == "sound" and B.SoundCommand then
		B.SoundCommand(arg)
	elseif cmd == "ding" and B.DingCommand then
		B.DingCommand(arg)
	else
		self:Print("/lefthy beacon - open settings")
		self:Print("/lefthy beacon status - friends with LefthyTools, their last update and the message traffic")
		self:Print("/lefthy beacon interval <1-10> - seconds between position updates while moving")
		self:Print("/lefthy beacon ding <text> | reset | test - your level-up message; {name} and {level} are filled in")
		self:Print("/lefthy beacon sound [<number>] - list the level-up sounds, or pick one and hear it")
	end
end
