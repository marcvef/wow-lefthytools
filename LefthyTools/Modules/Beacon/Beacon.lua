local _, ns = ...
local LT = ns.LT
local L = ns.L

-- Beacon: Battle.net friends who also run LefthyTools see each other on the world map and
-- minimap, with their status (dead, in combat), and get told when one of them levels up.
--
-- Addons can't reach the internet, so this runs entirely on the game's Battle.net addon
-- messages (C_BattleNet.SendGameData / BN_CHAT_MSG_ADDON): no group, guild or realm needed.
-- Each client can only read its *own* position (C_Map.GetPlayerMapPosition works for the
-- player and party only), so every client sends its own.
--
-- This file: the module, what the other files share (B), sending (one rate limiter, the queues),
-- finding friends, receiving, and the driver tick. The messages are listed in Protocol.lua, what
-- I send about myself is Sharing.lua's, a friend's newer build Updates.lua's, the settings page
-- Options.lua's; dots, level-ups, pings, items, chat, reports and the fight stream have files of
-- their own, which hook in through B (docs/beacon.md lists the hooks).
--
-- Keeping it light: my state is only sent when it changed, plus a heartbeat (Sharing.lua). Every
-- send goes through one rate limiter, and a throttle answer from the server pauses sending.
-- Event handlers only record what happened; the 10 Hz driver tick does the work, and drawing
-- (Dots.lua) is batched: the world map at most twice a second while open, the minimap only
-- when something on it moved.

local PREFIX = "LTBeacon"
local VERSION = "2"
local SWEEP_INTERVAL = 60    -- look for friends who started the addon
local SWEEP_COALESCE = 10    -- a friend came online: look again, but not more often than this
local HELLO_RETRY = 120      -- greet the same friend at most this often
local PEER_TIMEOUT = 65      -- forget a friend after this much silence (three missed heartbeats)
local VALIDATE_INTERVAL = 15 -- re-check that known friends are still online in WoW
local SEND_RATE, SEND_BURST = 10, 10 -- messages per second, across all friends
local THROTTLE_PAUSE = 2     -- the server said slow down: pause sending this long
local INBOX_LIMIT = 20       -- messages per second accepted from one friend
local DING_GAP = 10          -- level-up messages accepted from one friend at most this often
local DEATH_GAP = 10         -- death alerts for one friend at most this often
local PING_GAP = 2           -- map pings accepted from one friend at most this often
local HIGHLIGHT_LIMIT, HIGHLIGHT_WINDOW = 10, 60 -- Chronicle highlights accepted from one friend
local ONLINE_QUIET = 60      -- friends found in the first minute were online already: not news
local ITEM_GAP = 2           -- shared items accepted from one friend at most this often (they send
                             -- at most every 3 s; the margin is for their queue and the network)
local CALL_LIMIT, CALL_WINDOW = 10, 10 -- Need / Pass answers and verdicts accepted from one friend
local DAILY_LIMIT = 30       -- Chronicle days accepted from one friend per minute (7 + their AFK times arrive at once)
local REPORT_PARTS = 60      -- error report parts accepted from one friend per minute (a report has up to 16)
local JOURNAL_LIMIT, JOURNAL_WINDOW = 700, 60 -- Chronicle journal messages accepted from one friend (a
                             -- full sync of an account is a few hundred, low priority)
local STREAM_LIMIT, STREAM_WINDOW = 80, 10 -- fight stream messages accepted from one friend (2 frames a
                             -- second, mob names, keepalives)
local ANSWER_GAP = 5         -- answer one friend's hellos at most this often
local CHAT_LIMIT, CHAT_WINDOW = 5, 5 -- LTC lines accepted from one friend (a burst of 5 per 5 s)
local ANNOUNCE_GAP = 3       -- announcements from one friend at most this often
local NEWS_GAP = 60          -- tell one friend what's new in mine at most this often (Updates.lua)
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
		lefthyChat = true,    -- Chat.lua: LTC (/ltc, /l) lines in the chat window
		lefthyChatSound = true, -- a soft tick when a friend writes there
		announcements = true, -- /lefthy announce: lines in the middle of the screen
		dingAnnounce = true,
		dingText = "",
		dingShow = true,
		dingSound = true,
		dingSoundKit = 50111, -- boss defeated fanfare (Ding.lua lists the choices)
		sendReports = true,   -- Reports.lua: my LefthyTools errors to friends who collect them
		collectReports = false, -- and theirs to me
		streamShare = true,   -- Stream*.lua: friends can watch my fights
		streamWatchedDot = true, -- a small red dot by the minimap while someone watches
		streamFlights = true, -- a cinematic flight opens a friend's stream
		streamMapClick = true, -- clicking a friend's world map dot opens their stream
		streamButton = true,  -- StreamButton.lua: a minimap button listing friends to watch
		streamButtonAngle = 235, -- degrees, 0 = right, counter-clockwise: below Chronicle's book
	},
})

-- Shared by Beacon's files, and used by Chronicle and Misc Tweaks (docs/beacon.md lists what).
local B ={ module = M, VERSION = VERSION, handlers = {}, listeners = {}, pings = {} }
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
--   name, classFile, guid, level, area   from Battle.net (CopyInfo); name nil until the first check
--   hasPos, continent, north, west   their last world position, posTime when it arrived
--   fromNorth, fromWest, glide       where the minimap dot glides from, over how many seconds
--   dead, ghost, combat, subzone, target   their last state (S2); stateSeen, blank (sharing off)
--   quest, mobs, xpPercent           tracked quest (T2), enemies on them (C2), level progress (X2)
--   version, files, collects         their build (V2, F2), they collect error reports (Y2)
--   groupUnit                        their unit token while in my group
--   health, streamable, journal      set by StreamNet.lua (O2) and Chronicle's Sync.lua (J2)
--   rev                              bumped on every change, so dots and tooltips redraw only then
-- }
local peers = {}
B.peers = peers

local helloAt = {}      -- gameAccountID -> when we last greeted them
local otherVersion = {} -- gameAccountID -> protocol version of a friend on another LefthyTools version
local owed = {}         -- gameAccountID -> true: send them my current state
local outbox = {}       -- { gameAccountID, message }: one-off messages, sent before states
local lowOutbox = {}    -- the same, sent only when nothing else waits (bulk data); [3]: onSent()
local helloOutbox = {}  -- gameAccountIDs to greet (Sweep): after states and messages, before bulk data
local helloWaiting = {} -- gameAccountID -> true while their hello is in helloOutbox
local inbox = {}        -- gameAccountID -> what they may still send (Spaced / Counted, in OnMessage)
local dings = {}        -- { gameAccountID, level, text } received, shown on the next tick
local deaths = {}       -- { gameAccountID, foe }: friends who just died, told on the next tick
local pingsIn = {}      -- { gameAccountID, continent, north, west, mapID } received, shown on the next tick
local highlightsIn = {} -- { gameAccountID, kind, a, b } received, passed on on the next tick
local itemsIn = {}      -- { "item" | "answer" | "result" | "chat" | "announce", gameAccountID, ... }: for
                        -- Items.lua and Chat.lua, on the next tick
local dailyIn = {}      -- { gameAccountID, { day, played, xp, ... } }: friends' days, for Chronicle
local comings = {}      -- { "known" | "online" | "offline", peer[, data] }: told to listeners on the next tick
local enabledAt = 0
local stats = { sent = 0, received = 0, throttled = 0, since = 0 }

local sweepRequested, validateRequested = false, false
local groupChanged = true -- re-check which friends are in my group on the next tick
local lastSweep, lastValidate, lastExpire, lastRefresh
local tokens, pausedUntil = SEND_BURST, 0
-- Friends' data changed: the world map redraws on the next tick (at most twice a second, and
-- only while open), the minimap on the next frame so gliding dots start right away.
B.dirty, B.minimapDirty = false, true

local function Changed()
	B.dirty, B.minimapDirty = true, true
end

-- A friend's data changed outside this file (their health, StreamNet.lua): tooltips follow.
function B.PeerChanged(peer)
	peer.rev = peer.rev + 1
	Changed()
end

local function ResetTimers()
	lastSweep, lastValidate, lastExpire, lastRefresh = -math.huge, -math.huge, 0, -math.huge
end
ResetTimers()

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- The first maxBytes bytes of text, cut before a UTF-8 character that wouldn't fit whole (a
-- letter that ends right at the limit stays). At least one byte, so a loop cutting a long text
-- into parts always gets on.
function B.CutUTF8(text, maxBytes)
	local cut = math.min(#text, maxBytes)
	while cut < #text and cut > 1 and text:byte(cut + 1) >= 128 and text:byte(cut + 1) < 192 do
		cut = cut - 1 -- (the byte after the cut continues a character: it goes too)
	end
	return text:sub(1, cut)
end

-- Free text for a message: no colour codes or other escape sequences, separators or control
-- characters, and cut at maxBytes without splitting a UTF-8 character.
function B.Clean(text, maxBytes)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then
		return ""
	end
	text = strtrim((text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[|;%c]", "")))
	if #text > maxBytes then
		text = B.CutUTF8(text, maxBytes)
	end
	return text
end

-- My character's name as friends see it: Battle.net (a friend's peer.name) shows the name the game
-- shows, with the surname WoW: Forever gives every character (UnitName's second return).
function B.MyName()
	local first, surname = UnitName("player")
	if type(surname) == "string" and surname ~= "" and not (issecretvalue and issecretvalue(surname)) then
		return first .. " " .. surname
	end
	return first
end

-- Whether a name a friend's client sent (a verdict, ...) is mine: with the surname, or without.
function B.IsMe(name)
	return name ~= nil and (name == UnitName("player") or name == B.MyName())
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

-- A name in its class colour, for chat lines and notices ("?" while it isn't known).
function B.ColouredName(name, classFile)
	return LT.Window.ClassColorCode(classFile) .. (name or "?") .. "|r"
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

-- One friend, a message that only matters in its newest form (a fight stream frame): one still
-- waiting that starts the same (prefix) is replaced where it is; behind: dropped, and this one
-- goes to the end (after messages it needs, queued just before it).
function B.QueueLatest(gameAccountID, message, prefix, behind)
	for i, item in ipairs(outbox) do
		if item[1] == gameAccountID and item[2]:sub(1, #prefix) == prefix then
			if not behind then
				item[2] = message
				return
			end
			table.remove(outbox, i)
			break
		end
	end
	B.Queue(gameAccountID, message)
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
		local state = B.CurrentState() -- (Sharing.lua)
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
	-- Hellos to friends not known yet (Sweep): after everything live, so a friend list full of
	-- WoW players without LefthyTools never delays a state or a chat line.
	while tokens >= 1 and helloOutbox[1] and not outbox[1] do
		local id = table.remove(helloOutbox, 1)
		helloWaiting[id] = nil
		if not peers[id] then
			if not SendNow(id, "H" .. VERSION) then
				table.insert(helloOutbox, 1, id)
				helloWaiting[id] = true
				pausedUntil, stats.throttled = now + THROTTLE_PAUSE, stats.throttled + 1
				return
			end
			tokens = tokens - 1
		end
	end
	-- Bulk data (Chronicle's days for friends' graphs) only goes when nothing else waits, so it
	-- never delays positions, states or anything someone clicked.
	while tokens >= 1 and lowOutbox[1] and not outbox[1] and not next(owed) and not helloOutbox[1] do
		local item = table.remove(lowOutbox, 1)
		if peers[item[1]] then
			if not SendNow(item[1], item[2]) then
				table.insert(lowOutbox, 1, item)
				pausedUntil, stats.throttled = now + THROTTLE_PAUSE, stats.throttled + 1
				return
			end
			tokens = tokens - 1
			if item[3] then
				item[3]() -- (it went: an error report is no longer kept)
			end
		end
	end
end

-- Low priority (see Drain): sent when nothing else is waiting. onSent(): called once it went.
function B.QueueLow(gameAccountID, message, onSent)
	lowOutbox[#lowOutbox + 1] = { gameAccountID, message, onSent }
end

-- Drops low-priority messages still waiting that start with prefix (they'd arrive after a newer one
-- sent through the normal queue, and contradict it).
function B.DropLow(prefix)
	for i = #lowOutbox, 1, -1 do
		if lowOutbox[i][2]:sub(1, #prefix) == prefix then
			table.remove(lowOutbox, i)
		end
	end
end

-- Drops low-priority messages still waiting for one friend that match(message) says (an answer
-- asked for again: it goes once).
function B.DropLowFor(gameAccountID, match)
	for i = #lowOutbox, 1, -1 do
		if lowOutbox[i][1] == gameAccountID and match(lowOutbox[i][2]) then
			table.remove(lowOutbox, i)
		end
	end
end

-- Whether a low-priority message starting with prefix is still waiting (Reports.lua: a report
-- still on its way isn't queued again).
function B.LowWaiting(prefix)
	for _, item in ipairs(lowOutbox) do
		if item[2]:sub(1, #prefix) == prefix then
			return true
		end
	end
	return false
end

function B.QueueLowToPeers(message)
	for gameAccountID in pairs(peers) do
		B.QueueLow(gameAccountID, message)
	end
end

-- My state goes to every friend on the next Drain (built when it goes: B.CurrentState, Sharing.lua).
function B.OweStateToAll()
	for gameAccountID in pairs(peers) do
		owed[gameAccountID] = true
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
	if B.StreamForget then
		B.StreamForget(gameAccountID, peer) -- (watching them, or they me)
	end
	if B.JournalForget then
		B.JournalForget(gameAccountID) -- (Chronicle: what was asked of them goes to someone else)
	end
	if B.RemovePing then
		B.RemovePing(gameAccountID) -- (their marker goes with them)
	end
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
				elseif helloWaiting[id] then
					-- Still waiting to go (sending is held up): as good as a new one, and never two.
					helloAt[id] = now
				elseif not otherVersion[id] and (not helloAt[id] or now - helloAt[id] >= HELLO_RETRY) then
					helloAt[id], helloWaiting[id] = now, true
					helloOutbox[#helloOutbox + 1] = id
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

-- Returns true and who they were fighting (or nil) when this state says they just died.
local function ApplyState(peer, now, flags, continent, north, west, subzone, target)
	-- (after a blank state, what a friend with sharing off sends, being dead is no news: they may
	-- have died before switching it on)
	local wasAlive = peer.stateSeen and not peer.blank and not (peer.dead or peer.ghost)
	peer.blank = flags == "" and not continent and subzone == "" and target == ""
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

-- What one friend may send, kept in their inbox guard (per sender, also when the peer is
-- forgotten, so "Q2" can't reset it). Spaced: one per gap seconds.
local function Spaced(guard, key, gap, now)
	local last = guard[key]
	if last and now - last < gap then
		return false
	end
	guard[key] = now
	return true
end

-- Counted: at most limit in a window of that many seconds, starting with the first one after the
-- last window ran out (a burst of them in the same moment all count).
local function Counted(guard, key, limit, window, now)
	local counter = guard[key]
	if not counter then
		counter = {}
		guard[key] = counter
	end
	if not counter.at or now - counter.at >= window then
		counter.at, counter.n = now, 0
	end
	if counter.n >= limit then
		return false
	end
	counter.n = counter.n + 1
	return true
end

local function OnMessage(text, senderID)
	if type(senderID) ~= "number" then
		return
	end
	local now = GetTime()
	local guard = inbox[senderID]
	if not guard then
		guard = {}
		inbox[senderID] = guard
	end
	if not Counted(guard, "flood", INBOX_LIMIT, 1, now) then
		return -- a friend's client gone haywire can't flood us
	end

	local kind, a, b, c, d, e, f = B.Parse(text)
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
		-- Back after I'd forgotten them (65 s of silence, a loading screen): their version, quest
		-- and progress only come in answers, and they don't see me as new. A hello asks for them
		-- (low priority: after the answers that are owed).
		if kind ~= "H" and (not helloAt[senderID] or now - helloAt[senderID] >= ANSWER_GAP) then
			helloAt[senderID] = now
			B.QueueLow(senderID, "H" .. VERSION)
		end
	end
	peer.seen = now
	if kind == "H" then
		answer = true              -- they (re)started the addon: answer with my state
	elseif kind == "S" then
		local died, foe = ApplyState(peer, now, a, b, c, d, e, f)
		if died and Spaced(guard, "deathAt", DEATH_GAP, now) then
			deaths[#deaths + 1] = { senderID, foe }
		end
	elseif kind == "L" then
		if Spaced(guard, "dingAt", DING_GAP, now) then
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
		if Spaced(guard, "itemAt", ITEM_GAP, now) then
			itemsIn[#itemsIn + 1] = { "item", senderID, a, b }
		end
	elseif kind == "M" then
		if Counted(guard, "chat", CHAT_LIMIT, CHAT_WINDOW, now) then
			itemsIn[#itemsIn + 1] = { "chat", senderID, a }
		end
	elseif kind == "A" then
		if Spaced(guard, "announceAt", ANNOUNCE_GAP, now) then
			itemsIn[#itemsIn + 1] = { "announce", senderID, a }
		end
	elseif kind == "N" or kind == "R" then
		-- One per call each way; a count per window, so two in the same moment both count.
		if Counted(guard, "calls", CALL_LIMIT, CALL_WINDOW, now) then
			itemsIn[#itemsIn + 1] = { kind == "N" and "answer" or "result", senderID, a, b }
		end
	elseif kind == "D" or kind == "K" then -- (K: a day's AFK time, merged into that day)
		if Counted(guard, "daily", DAILY_LIMIT, 60, now) then
			dailyIn[#dailyIn + 1] = { senderID, a }
		end
	elseif kind == "E" then
		if Counted(guard, "highlights", HIGHLIGHT_LIMIT, HIGHLIGHT_WINDOW, now) then
			highlightsIn[#highlightsIn + 1] = { senderID, a, B.Clean(b, 64), B.Clean(c, 64) }
		end
	elseif kind == "P" then
		if M.db.pings and Spaced(guard, "pingAt", PING_GAP, now) then
			pingsIn[#pingsIn + 1] = { senderID, a, b, c, d }
		end
	elseif kind == "G" then
		for i = #pingsIn, 1, -1 do -- (one still waiting for the tick goes too)
			if pingsIn[i][1] == senderID then
				table.remove(pingsIn, i)
			end
		end
		if B.RemovePing then
			B.RemovePing(senderID)
		end
	elseif kind == "Y" then
		peer.collects = a -- Reports.lua sends my error reports to them
	elseif kind == "Z" then
		if M.db.collectReports and B.ReceiveReportPart and Counted(guard, "reportParts", REPORT_PARTS, 60, now) then
			B.ReceiveReportPart(senderID, a, b, c, d)
		end
	elseif kind == "O" then
		if Counted(guard, "stream", STREAM_LIMIT, STREAM_WINDOW, now) and B.ReceiveStream then
			B.ReceiveStream(senderID, a, b)
		end
	elseif kind == "J" then
		if Counted(guard, "journal", JOURNAL_LIMIT, JOURNAL_WINDOW, now) and B.ReceiveJournal then
			B.ReceiveJournal(senderID, a, b)
		end
	elseif kind == "F" then
		peer.files = a -- (comes just before their version)
	elseif kind == "V" then
		peer.version = a
		B.FriendBuild(senderID, peer, now) -- Updates.lua
	elseif kind == "U" then
		if Spaced(guard, "newsAt", NEWS_GAP, now) then
			B.NewsAsked(senderID, a, b)
		end
	elseif kind == "W" then
		B.ReceiveNews(senderID, a, b, c)
	end
	-- At most one answer per ANSWER_GAP, so repeated hellos can't eat the send budget.
	if answer and Spaced(guard, "answeredAt", ANSWER_GAP, now) then
		owed[senderID] = true
		B.Queue(senderID, "F" .. VERSION .. ";" .. LT.FILES) -- my LefthyTools build and its files
		B.Queue(senderID, "V" .. VERSION .. ";" .. B.Clean(LT.version, 40))
		local collector = B.CollectorMessage and B.CollectorMessage()
		if collector then
			B.Queue(senderID, collector) -- I collect error reports
		end
		if B.StreamHello then
			B.QueueLow(senderID, B.StreamHello()) -- whether they can watch my fights (after the rest)
		end
		local health = B.StreamHealthHello and B.StreamHealthHello()
		if health then
			B.QueueLow(senderID, health) -- my health (estimated)
		end
		local journal = B.JournalHello and B.JournalHello()
		if journal then
			B.QueueLow(senderID, journal) -- Chronicle: I sync journals
		end
		B.SharingAnswer(senderID) -- my tracked quest and level progress
	end
end

---------------------------------------------------------------------------
-- Driver, lifecycle and events
---------------------------------------------------------------------------

local driver = CreateFrame("Frame")
local events = CreateFrame("Frame")
local sinceTick = 0
local NAMELESS_WAIT = 10

-- Hands a queue's items to handle(peer, item), in order. A friend just found has no name until
-- the next Validate (a second, or a little more while Battle.net fills it in): their items wait
-- for it, up to NAMELESS_WAIT; a friend who's gone, their items go.
local function Each(queue, idAt, now, handle)
	local waiting
	while queue[1] do
		local item = table.remove(queue, 1)
		local peer = peers[item[idAt]]
		item.at = item.at or now
		if peer and peer.name then
			handle(peer, item)
		elseif peer and now - item.at < NAMELESS_WAIT then
			waiting = waiting or {}
			waiting[#waiting + 1] = item
		end
	end
	for i, item in ipairs(waiting or {}) do
		queue[i] = item
	end
end

local function HandleDing(peer, ding)
	if B.ShowDing then
		B.ShowDing(peer, ding[2], ding[3])
	end
end

local function HandleDeath(peer, death)
	if B.ShowDeath then
		B.ShowDeath(peer, death[1], death[2])
	end
end

local function HandlePing(peer, ping)
	if B.ReceivePing then
		B.ReceivePing(peer, ping[1], ping[2], ping[3], ping[4], ping[5])
	end
end

local function HandleDaily(peer, item)
	B.Notify("daily", peer, item[2])
end

local function HandleItem(peer, item)
	if not B.ReceiveItem then
		return
	end
	if item[1] == "item" then
		B.ReceiveItem(peer, item[2], item[3], item[4])
	elseif item[1] == "chat" then
		B.ReceiveChat(peer, item[3]) -- Chat.lua
	elseif item[1] == "announce" then
		B.ReceiveAnnouncement(peer, item[3])
	elseif item[1] == "answer" then
		B.ReceiveAnswer(peer, item[2], item[3], item[4])
	else
		B.ReceiveResult(peer, item[2], item[3], item[4])
	end
end

local function HandleHighlight(peer, item)
	B.Notify("highlight", peer, { kind = item[2], a = item[3], b = item[4] })
end

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
	B.SharingTick(now) -- Sharing.lua: my level-up, state, quest, enemies, level progress
	if B.StreamHealthTick then
		B.StreamHealthTick(now) -- my health (estimated), to everyone
	end
	Drain(now, elapsed)

	Each(dings, 1, now, HandleDing)
	Each(deaths, 1, now, HandleDeath)
	Each(pingsIn, 1, now, HandlePing)
	while comings[1] do
		local item = table.remove(comings, 1)
		B.Notify(item[1], item[2], item[3] or {})
	end
	Each(dailyIn, 1, now, HandleDaily)
	Each(itemsIn, 2, now, HandleItem) -- Items.lua: shared items, Need / Pass answers, roll results
	if B.UpdateCalls then
		B.UpdateCalls(now)
	end
	Each(highlightsIn, 1, now, HandleHighlight)
	if B.UpdatePings then
		B.UpdatePings(now)
	end
	if B.TickReports then
		B.TickReports(now)
	end
	B.TickUpdates(now) -- Updates.lua: a friend's newer build, what's new in mine
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
		local since = sinceTick
		sinceTick = 0 -- (first: an error in Tick must not make it run every frame)
		Tick(now, since)
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
	sweepRequested, lastSweep = true, -math.huge
	B.SharingEnteredWorld()
end
handlers.GROUP_ROSTER_UPDATE = function() groupChanged = true end
-- (Sharing.lua adds its own: nameplates, quests, experience, combat, death, target, zone; Dots.lua
-- ADDON_LOADED. All are registered while Beacon is on.)

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
	B.SharingStart()
	wipe(outbox) -- goodbyes still pending from switching off just before: no longer true
	wipe(lowOutbox)
	wipe(helloOutbox)
	wipe(helloWaiting)
	farewellUntil = nil
	tokens, pausedUntil, sinceTick = SEND_BURST, 0, 0
	stats.sent, stats.received, stats.throttled, stats.since = 0, 0, 0, GetTime()
	enabledAt = GetTime()
	driver:SetScript("OnUpdate", OnUpdate)
	if B.Attach then
		C_Timer.After(0, B.Attach)
	end
	if B.HandoverRefresh then
		C_Timer.After(0, B.HandoverRefresh) -- reserved items' borders
	end
	if B.StreamStart then
		B.StreamStart()
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
	for _, t in ipairs({ peers, helloAt, helloOutbox, helloWaiting, otherVersion, inbox, dings, deaths, pingsIn, highlightsIn, itemsIn,
			dailyIn, comings, B.pings }) do
		wipe(t)
	end
	sweepRequested, validateRequested = false, false
	B.SharingStop()
	B.dirty = false
	farewellUntil = GetTime() + FAREWELL_TIMEOUT
	driver:SetScript("OnUpdate", outbox[1] and FarewellUpdate or nil)
	if B.Detach then
		C_Timer.After(0, B.Detach) -- removes the dots too
	end
	if B.ReleaseCalls then
		C_Timer.After(0, B.ReleaseCalls) -- open Need / Pass notices
	end
	if B.HandoverRefresh then
		C_Timer.After(0, B.HandoverRefresh) -- reserved items: borders, vendor guards and question go
	end
	if B.StreamStop then
		B.StreamStop() -- streams close, nobody watches me
	end
	if B.JournalStop then
		B.JournalStop() -- Chronicle: nothing asked, offered or owed any more
	end
end

function M:OnSettingChanged()
	B.SharingSettingChanged() -- e.g. sharing switched: friends are told right away
	Changed()
	if not M.db.pings and B.RemovePing then
		for key in pairs(B.pings) do
			B.RemovePing(key) -- "Map pings" off: the markers up now go too
		end
	end
	if B.OnSettingChanged then
		B.OnSettingChanged() -- Ding.lua: a newly picked level-up sound is played
	end
	if B.StreamSettingChanged then
		B.StreamSettingChanged() -- StreamNet.lua: friends hear whether they can watch me
	end
end

function M:GetPeers()
	return peers
end

-- /lefthy beacon status: every friend with LefthyTools (realm, faction, last position, status,
-- build), friends on another Beacon version, and the message traffic since switching on.
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

function B.PrintStatus()
	local count, now = 0, GetTime()
	for gameAccountID, peer in pairs(peers) do
		count = count + 1
		local info = C_BattleNet.GetGameAccountInfoByID(gameAccountID)
		M:Print(string.format("  %s (%s, %s) - %s%s, LefthyTools %s", peer.name or ("#" .. gameAccountID),
			info and info.realmName or "?", info and info.factionName or "?",
			peer.hasPos and string.format("position %.0f s ago", now - peer.posTime)
				or "no position (dungeon, raid or not sharing)", StatusWords(peer),
			peer.version or "0.3.0 or older"))
	end
	M:Print(string.format("  you (%s, %s), LefthyTools %s", GetRealmName() or "?", UnitFactionGroup("player") or "?", LT.version))
	for gameAccountID, version in pairs(otherVersion) do
		local info = C_BattleNet.GetGameAccountInfoByID(gameAccountID)
		M:Print(string.format("  %s runs another LefthyTools version (Beacon %s, you have %s): update both to the same version.",
			info and info.characterName or ("#" .. gameAccountID), version, VERSION))
	end
	M:Print(count == 0 and "no friends with LefthyTools online." or (count .. " friend(s) with LefthyTools online."))
	local minutes = math.max((now - stats.since) / 60, 1 / 60)
	M:Print(string.format("traffic: %d sent, %d received in %.0f min (%.1f / %.1f per minute), throttled %d time(s).",
		stats.sent, stats.received, minutes, stats.sent / minutes, stats.received / minutes, stats.throttled))
end
