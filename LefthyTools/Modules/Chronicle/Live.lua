local _, ns = ...
local LT = ns.LT
local C = ns.Chronicle
local M = C.module

-- Chronicle and friends live, through Beacon: the messages builds before the synced journals
-- (Sync.lua) rely on, still sent and read for them. Out: my highlights (E2, on the tick, at most a
-- few a minute) and my days for their graphs (D2, and K2 for the day's AFK time: builds before it
-- reject a D2 with another field). In: their highlights, level-ups, deaths, coming online and going
-- offline into the feed (store.friends, with a chat line for highlights), and their days
-- (store.friendStats, by the full name Battle.net gives; Characters.lua joins them to their
-- journals' characters). Never change these messages' formats: older builds read them.

local SHARE_DAYS = 7         -- days a friend gets from me when they show up
local SHARE_AGAIN = 600      -- back sooner (a /reload, a shaky connection): only today, they keep the rest
local SHARE_GAP = 300        -- today's numbers go to friends at most this often (if they changed)
local FRIEND_DAYS = 30       -- days of friends' numbers kept
-- The feed keeps each kind of news to a share of its own (300 in all), the oldest of that kind going
-- first: one list of 300 let a busy quest day push out a boss kill (a real feed held 126 quests of
-- its 300). Every quest turned in, friends coming online and going offline, first visits to zones,
-- level-ups, deaths, and the highlights (bosses, rares, dungeons, loot, mounts, achievements,
-- milestones, professions).
local FEED_KEEP = { quest = 80, comings = 50, zone = 40, level = 30, death = 30, highlight = 70 }
local FEED_GROUP = { quest = "quest", online = "comings", offline = "comings", zone = "zone", level = "level", death = "death" }
local issecret = LT.IsSecret

local shareQueue = {} -- { kind, a, b }: highlights recorded since the last tick
local listening = false

---------------------------------------------------------------------------
-- My highlights for friends (on the tick)
---------------------------------------------------------------------------

-- A highlight recorded (Chronicle.lua): it goes on the next tick.
function C.Share(kind, a, b)
	shareQueue[#shareQueue + 1] = { kind, a, b }
end

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

-- On the tick: the highlights recorded since the last one, to every friend with Beacon.
function C.ShareHighlights(now)
	while shareQueue[1] do
		local item = table.remove(shareQueue, 1)
		local beacon = LT:GetModule("beacon")
		if M.db.share and beacon and beacon.enabled and ns.Beacon and ns.Beacon.ShareHighlight and FeedBudget(item[1], now) then
			ns.Beacon.ShareHighlight(item[1], item[2], item[3])
		end
	end
end

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

-- Keeps each kind's newest entries, as many as its share (FEED_KEEP); the rest goes.
local function TrimFeed(feed)
	local counts = {}
	for i = #feed, 1, -1 do
		local group = type(feed[i]) == "table" and FEED_GROUP[feed[i].k] or "highlight"
		counts[group] = (counts[group] or 0) + 1
		if counts[group] > FEED_KEEP[group] then
			table.remove(feed, i)
		end
	end
end

local function AddToFeed(entry)
	local feed = C.Store().friends
	feed[#feed + 1] = entry
	TrimFeed(feed) -- (the oldest of its kind, if that kind's share is full)
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
	local b = C.Char().daily[day]
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
	local b = C.Char().daily[day]
	local minutes = b and math.min(1440, math.floor((b.afk or 0) / 60)) or 0
	if minutes > 0 then
		return ("K%s;%s;%d"):format(ns.Beacon.VERSION, (day:gsub("-", "")), minutes)
	end
end

-- On the tick, at most every SHARE_GAP: today's and yesterday's numbers to everyone, if changed.
function C.ShareDays(now)
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
local daysSentAt = {} -- gameAccountID -> GetTime() of the last full week
local function SendDaysTo(gameAccountID)
	if not SharingOn() then
		return
	end
	local now = GetTime()
	local again = daysSentAt[gameAccountID] and now - daysSentAt[gameAccountID] < SHARE_AGAIN
	if not again then
		daysSentAt[gameAccountID] = now
	end
	for i = again and 0 or SHARE_DAYS - 1, 0, -1 do
		local day = date("%Y-%m-%d", C.DayAgo(i))
		for _, message in ipairs({ DailyMessage(day) or false, AfkMessage(day) or false }) do
			if message then
				ns.Beacon.QueueLow(gameAccountID, message)
			end
		end
	end
end

-- A day of a friend's numbers (D2), or just its AFK time (K2: day.afk only):
-- store.friendStats[name] = { classFile, level, updated, days, acct, guid }, by the full name
-- Battle.net gives. Either keeps what the other set. acct (their BattleTag's hash) and guid find the
-- character in their journal (Characters.lua), whose name is its first name: these days are that
-- character's (where the journal has none), never a second one (older builds keep the fields and
-- ignore them).
local function StoreFriendDay(peer, day)
	if day.day > date("%Y-%m-%d", C.DayAgo(-1)) then
		return -- a day after tomorrow (a wrong clock): it would never be pruned
	end
	local friends = C.Store().friendStats
	local f = friends[peer.name] or { days = {} }
	friends[peer.name] = f
	f.classFile, f.level, f.updated = peer.classFile, peer.level, time()
	f.acct = C.PeerAccount and C.PeerAccount(peer) or f.acct
	f.guid = type(peer.guid) == "string" and not issecret(peer.guid) and peer.guid or f.guid
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
	if not (M.enabled and C.Store() and peer.name) then
		return
	end
	if kind == "known" then
		SendDaysTo(data.id)
		return
	elseif kind == "daily" then
		StoreFriendDay(peer, data)
		return
	end
	-- (their account too: Characters.lua finds the character in their journal by it and the full name)
	local entry = { t = time(), name = peer.name, classFile = peer.classFile, acct = C.PeerAccount and C.PeerAccount(peer) }
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
-- Switching on and off (Chronicle.lua)
---------------------------------------------------------------------------

function C.LiveEnable()
	local store = C.Store()
	-- Friends whose days have all run out (30 days) leave the dropdown.
	local oldest = date("%Y-%m-%d", C.DayAgo(FRIEND_DAYS))
	for friendName, f in pairs(store.friendStats) do
		local any = false
		for day in pairs(type(f.days) == "table" and f.days or {}) do
			any = any or day >= oldest
		end
		if not any then
			store.friendStats[friendName] = nil
		end
	end
	-- A feed saved before the shares (one list of 300): each kind down to its share, oldest first.
	TrimFeed(store.friends)
	if not listening and ns.Beacon then
		listening = true
		table.insert(ns.Beacon.listeners, OnFriendEvent)
	end
end

function C.LiveDisable()
	wipe(shareQueue)
end
