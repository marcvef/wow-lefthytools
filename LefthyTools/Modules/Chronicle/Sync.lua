local _, ns = ...
local LT = ns.LT
local C = ns.Chronicle
local M = C.module

-- Friends' journals, also when they aren't online. Battle.net messages only reach friends who are
-- online right now, so every client keeps what it learned about friends (store.book) and passes it
-- on: whoever is online brings the news of whoever isn't. Only to people who have that player as
-- a Battle.net friend too: journals are kept per Battle.net account, named by a hash of its
-- BattleTag (8 hex, never the BattleTag itself), and a client only asks for and keeps the accounts
-- whose hash matches one of its own friends' BattleTags.
--
-- What a player publishes about themselves (setting share; shareAlts: all their characters):
--   days      a record per day (30 days): played, XP, quests, kills, deaths, levels, AFK, level and
--             gold at the day's end, distance, bosses, rares, dungeon runs, jumps
--   news      their timeline's highlights (level-ups, deaths, zones, dungeons, bosses, rares, epic
--             loot, mounts, achievements, milestones), numbered, 30 days, at most 150 a character
--   profile   lifetime numbers (time, quests, kills, deaths, zones, ...), their deadliest foe and
--             favourite zone, and when they last played
-- Every record carries u, its author's stamp (time(), strictly increasing per author), and an
-- account's holder knows it completely up to some u. Messages (Beacon kind J, low priority except
-- requests; older builds ignore J):
--   J2;h;<acct>            I sync (with every answer to a hello), my account's hash
--   J2;s;<acct>,<u>/...    what I hold: per account, complete up to u (to a friend when it grew,
--                          at most every SUMMARY_GAP; the whole list the first time)
--   J2;q;<acct>;<since>    send me that account's records newer than since
--   J2;p;<acct>;<char>;<u>;<class>;<level>;<last>;<numbers>;<foe>;<zone>      a profile
--   J2;d;<acct>;<char>;<u>;<YYYYMMDD>;<numbers>                              a day
--   J2;n;<acct>;<char>;<u>;<n>;<t>;<kind>;<a>;<b>                             a highlight
--   J2;a;<acct>;<char>;<u>;<full name>;<guid>    the character's full name and GUID, with the
--                          profile's stamp (<char> stays its record's key: the first name's)
--   J2;l;<acct>;<char>;<full name>;<guid>        a full name I learned, not from its author (no
--                          stamp; with every answer, and to the account's owner on their hello;
--                          only to builds that read it)
--   J2;c;<acct>;<count>    the answer had count records (just before its end)
--   J2;e;<acct>;<u>        that's all: you're complete up to u
-- A request goes to one friend at a time per account (PENDING_TIMEOUT without progress: another
-- may answer). An answer holds at most SERVE_MAX records, oldest first; its end says how far that
-- got, so the rest follows on the next round. Old D2/K2 days still go to builds before these
-- journals, E2 highlights to everyone (chat lines; Live.lua); their data stays in
-- store.friendStats / store.friends, and Characters.lua joins it to the journals' characters.
--
-- Characters.lua: who is who (accounts, names, matching) and the lists the pages use; Recap.lua:
-- "while you were away", the weekly recap, the leaderboards and sharing in LTC.
--
-- Cost: a check every CHECK_GAP (today's and yesterday's numbers as text, compared), summaries
-- when something changed, everything else only when a friend asks or sends.

local VERSION = "2"
local DAYS_KEPT = 30
local NEWS_KEPT = 150
local SUMMARY_GAP = 60
local FULL_OFFER = 300  -- everything offered again this often (an offer missed, a journal only partly got)
local SERVES_PER_TICK = 2 -- answers built per tick (each up to SERVE_MAX messages)
local BOOK_DAYS = 60     -- a friend's character with nothing newer than this goes
-- Characters kept per friend's account, the most recently played: a real account has a handful in
-- BOOK_DAYS (the most in a real book: 6), so 30 keeps every one even an altoholic plays, while a
-- broken or hostile client can't fill my saved data with characters.
local CHARS_KEPT = 30
local CHECK_GAP = 60
local PROFILE_GAP = 300
local PENDING_TIMEOUT = 90
local SERVE_MAX = 400
local MEET_GAP, MEET_FIRST = 30, 10 -- friends' characters online on Battle.net, matched to their journals (s)
local NAME_BYTES, TEXT_BYTES = 48, 60
local SHAREABLE = { level = true, death = true, zone = true, dungeon = true, boss = true, rare = true, loot = true, mount = true,
	achievement = true, quests = true, gold = true, profession = true }
local DAY_FIELDS = { "played", "xp", "quests", "kills", "deaths", "levels", "afk", "level", "gold", "dist", "bosses", "rares",
	"runs", "jumps" }
local MINUTES = { played = true, afk = true } -- sent in minutes, kept in seconds
local PROFILE_FIELDS = { "played", "sessions", "quests", "kills", "deaths", "zones", "dungeons", "runs", "bosses", "rares",
	"dist", "jumps", "mounts", "achievements", "gold", "fastest", "longest", "afk", "loot4", "levels", "xp" }

local store
local pending = {}     -- acct -> { from, at, got (records come so far), expect (how many the answer has) }
local serves = {}      -- answers to build on the tick: { id, acct, since }
local summaries = {}   -- gameAccountID -> { at, sent = { [acct] = u } }
local lastCheck, lastProfile = -math.huge, -math.huge
local pruneAt          -- when the book is pruned (PruneBook)
local meetAt           -- the next walk over Battle.net's friends online (Meet)
-- (Characters.lua: accounts, names, matching)
local Friends, IsFriend, FirstName, HasSurname, ValidGuid = C.FriendAccounts, C.IsFriend, C.FirstName, C.HasSurname, C.ValidGuid
local Changed = C.NewsChanged -- (friends' news or names changed)
-- Dated before Forever's launch, on the release (Core.lua): the beta's, passed on by a friend on an
-- older LefthyTools that didn't start fresh. Left out where records come in and pruned from the book;
-- older builds send as before, only what I take changes.
local BeforeLaunch = LT.BeforeLaunch

---------------------------------------------------------------------------
-- Publishing my journal: stamps
---------------------------------------------------------------------------

local function SyncState(c)
	local s = c.sync
	if type(s) ~= "table" then
		s = {}
		c.sync = s
	end
	s.seq = s.seq or 0
	s.daySig = type(s.daySig) == "table" and s.daySig or {}
	s.dayU = type(s.dayU) == "table" and s.dayU or {}
	return s
end

-- A new stamp of mine: now, and always later than the last one.
local function NextU()
	local u = math.max(time(), (store.myU or 0) + 1)
	store.myU = u
	return u
end

function C.Shareable(e)
	return SHAREABLE[e.k] and (e.k ~= "loot" or (e.quality or 0) >= 4)
end

-- Chronicle.lua's Record: a highlight friends may see gets its number and stamp.
function C.Stamp(c, e)
	if store and C.Shareable(e) then
		local s = SyncState(c)
		s.seq = s.seq + 1
		e.n, e.u = s.seq, NextU()
	end
end

local function Oldest()
	return date("%Y-%m-%d", C.DayAgo(DAYS_KEPT))
end

local function Int(v)
	return math.max(0, math.floor((tonumber(v) or 0) + 0.5))
end

-- A day's numbers as the message's field list ("12,3400,5,...").
local function DayText(b)
	local parts = {}
	for i, key in ipairs(DAY_FIELDS) do
		local v = b[key] or 0
		parts[i] = tostring(Int(MINUTES[key] and math.min(1440, v / 60) or v))
	end
	return table.concat(parts, ",")
end

local Count, Top = C.Count, C.Top

-- My character's lifetime numbers, in PROFILE_FIELDS' order.
local function ProfileNumbers(c)
	C.Fill(c)
	local s = c.stats
	return {
		played = s.played, sessions = s.sessions, quests = s.quests, kills = s.kills, deaths = s.deaths,
		zones = Count(c.seen.zones), dungeons = Count(c.seen.dungeons), runs = s.dungeonRuns, bosses = s.bosses,
		rares = s.rares, dist = s.walked + s.ridden + s.swum + s.flown, jumps = s.jumps, mounts = s.mounts,
		achievements = s.achievements, gold = s.maxMoney / 10000, fastest = c.fastestLevel or 0, longest = s.longestSession,
		afk = s.afk, loot4 = s.loot4, levels = s.levels, xp = s.xp,
	}
end
C.ProfileNumbers = ProfileNumbers

local function ProfileText(c)
	local numbers, parts = ProfileNumbers(c), {}
	for i, key in ipairs(PROFILE_FIELDS) do
		parts[i] = tostring(Int(MINUTES[key] and numbers[key] / 60 or numbers[key]))
	end
	return table.concat(parts, ","), ns.Beacon.Clean(Top(c.killers) or "", 40), ns.Beacon.Clean(Top(c.zoneTime) or "", 40)
end

-- Stamps whatever of a character changed since it was last stamped: its days (all kept ones, or
-- only today's and yesterday's) and its profile.
local function StampChar(c, recentOnly, withProfile)
	local s = SyncState(c)
	local oldest = Oldest()
	local days = {}
	if recentOnly then
		days[1], days[2] = date("%Y-%m-%d", C.DayAgo(1)), date("%Y-%m-%d", C.DayAgo(0))
	else
		for day in pairs(c.daily) do
			days[#days + 1] = day
		end
		table.sort(days)
	end
	for _, day in ipairs(days) do
		local b = c.daily[day]
		if b and day >= oldest then
			local text = DayText(b)
			if text ~= s.daySig[day] then
				s.daySig[day], s.dayU[day] = text, NextU()
			end
		end
	end
	for day in pairs(s.daySig) do
		if day < oldest then
			s.daySig[day], s.dayU[day] = nil, nil
		end
	end
	if withProfile then
		local numbers, foe, zone = ProfileText(c)
		-- (its full name and GUID go with the profile's stamp: friends ask again when they're new)
		local text = numbers .. ";" .. foe .. ";" .. zone .. ";" .. (c.level or 0) .. ";" .. (c.full or "") .. ";" .. (c.guid or "")
		if text ~= s.profileSig then
			s.profileSig, s.profileU = text, NextU()
		end
	end
end

-- After an update: highlights recorded before stamps existed get theirs (their own time; nobody
-- has synced them yet), oldest first.
local function Upgrade(c)
	local s = SyncState(c)
	local oldest = C.DayAgo(DAYS_KEPT)
	for _, e in ipairs(c.events) do
		if not e.n and e.t and e.t >= oldest and C.Shareable(e) then
			s.seq = s.seq + 1
			-- (its own time, but always above the last stamp: two in one second must differ, or an
			-- answer cut between them would lose the second)
			local u = math.max(e.t, (store.myU or 0) + 1)
			e.n, e.u = s.seq, u
			store.myU = u
		end
	end
end

-- Every record of a character stamped anew, so friends who are further ask for them again (all
-- characters shared from now on; another character played while only the current one is shared).
local function Restamp(c)
	local s = SyncState(c)
	wipe(s.daySig)
	s.profileSig = nil
	for _, e in ipairs(c.events) do
		if e.n then
			e.u = NextU()
		end
	end
	StampChar(c, false, true)
end

---------------------------------------------------------------------------
-- Records: mine (from store.chars) and friends' (store.book)
---------------------------------------------------------------------------

local function CharKey(c)
	return ns.Beacon.Clean((c.name or "?") .. "-" .. (c.realm or ""), NAME_BYTES)
end

local function MyChars()
	local list, current = {}, C.Char()
	for _, c in pairs(store.chars) do
		if c == current or M.db.shareAlts then
			list[#list + 1] = c
		end
	end
	return list
end

-- How far I hold an account (0: not at all; friends' journals only while they're still my friends).
local function Held(acct)
	if acct == C.MyAccount() then
		return M.db.share and (store.myU or 0) or 0
	end
	local a = store.book[acct]
	return a and M.db.relay and IsFriend(acct) and a.u or 0
end

local function J(word, ...)
	return ("J%s;%s;%s"):format(VERSION, word, table.concat({ ... }, ";"))
end

-- A profile message; its foe and zone are left out if it would be too long for one message.
local function ProfileMessage(acct, key, u, classFile, level, last, numbers, foe, zone)
	local message = J("p", acct, key, u, classFile or "", level or 0, last or 0, numbers, foe or "", zone or "")
	if #message > 250 then
		message = J("p", acct, key, u, classFile or "", level or 0, last or 0, numbers, "", "")
	end
	return message
end

-- A character's full name and GUID (the "a" word: newer builds; older ones ignore words they don't
-- know). Its key stays the first name's, the one every build knows it by.
local function AliasMessage(acct, key, u, full, guid)
	return J("a", acct, key, u, ns.Beacon.Clean(full or "", NAME_BYTES), guid or "")
end

-- An account's records newer than since: { { u, message }, ... }, oldest first.
local function Records(acct, since)
	local list = {}
	local function Add(u, message)
		if u and u > since then
			list[#list + 1] = { u, message }
		end
	end
	if acct == C.MyAccount() then
		local oldest = C.DayAgo(DAYS_KEPT)
		for _, c in ipairs(MyChars()) do
			local key, s = CharKey(c), SyncState(c)
			if s.profileU then
				local numbers, foe, zone = ProfileText(c)
				local last = c == C.Char() and time() or (c.session and c.session.last) or 0
				Add(s.profileU, ProfileMessage(acct, key, s.profileU, c.classFile, c.level, last, numbers, foe, zone))
				if c.full or c.guid then
					Add(s.profileU, AliasMessage(acct, key, s.profileU, c.full or c.name, c.guid))
				end
			end
			for day, u in pairs(s.dayU) do
				local b = c.daily[day]
				if b then
					Add(u, J("d", acct, key, u, (day:gsub("-", "")), DayText(b)))
				end
			end
			local news = 0
			for i = #c.events, 1, -1 do
				local e = c.events[i]
				if e.t and e.t < oldest then
					break
				end
				if e.n and news < NEWS_KEPT then
					news = news + 1
					local a, b = C.NewsFields(e)
					Add(e.u, J("n", acct, key, e.u, e.n, e.t, e.k, a, b))
				end
			end
		end
	else
		local a = store.book[acct]
		for key, c in pairs(a and a.chars or {}) do
			if c.aliasU and c.full then
				Add(c.aliasU, AliasMessage(acct, key, c.aliasU, c.full, c.guid))
			end
			if c.profile then
				local p, numbers = c.profile, {}
				for i, field in ipairs(PROFILE_FIELDS) do
					numbers[i] = tostring(Int(MINUTES[field] and (p[field] or 0) / 60 or p[field]))
				end
				Add(c.u, ProfileMessage(acct, key, c.u, c.classFile, c.level, c.last, table.concat(numbers, ","), c.foe, c.zone))
			end
			for day, b in pairs(c.days) do
				Add(b.u, J("d", acct, key, b.u, (day:gsub("-", "")), DayText(b)))
			end
			for n, e in pairs(c.news) do
				Add(e.u, J("n", acct, key, e.u, n, e.t, e.k, e.a or "", e.b or ""))
			end
		end
	end
	table.sort(list, function(x, y) return x[1] < y[1] end)
	return list
end

-- A highlight's two text fields, the way friends get them (the same as Beacon's E2 highlights).
function C.NewsFields(e)
	local clean = ns.Beacon.Clean
	local k = e.k
	local a, b
	if k == "level" then
		a, b = e.level, e.zone
	elseif k == "death" then
		a, b = e.foe, e.sub and (e.zone .. " - " .. e.sub) or e.zone
	elseif k == "zone" then
		a = e.zone
	elseif k == "boss" then
		a, b = e.name, e.instance
	elseif k == "rare" then
		a, b = e.name, e.zone
	elseif k == "loot" then
		a, b = e.name, e.quality
	elseif k == "quests" then
		a = e.count
	elseif k == "gold" then
		a = e.gold
	elseif k == "profession" then
		a, b = e.name, e.level
	else
		a = e.name
	end
	return clean(tostring(a or ""), TEXT_BYTES), clean(tostring(b or ""), TEXT_BYTES)
end

---------------------------------------------------------------------------
-- Talking to friends
---------------------------------------------------------------------------

local function Beacon()
	local beacon = LT:GetModule("beacon")
	return beacon and beacon.enabled and ns.Beacon or nil
end

-- With every answer to a friend's hello (Beacon.lua); nil while Chronicle is off.
function ns.Beacon.JournalHello()
	if M.enabled and store then
		return J("h", C.MyAccount() or "")
	end
end

-- What I hold, to one friend: only what grew since they last heard it (everything the first time,
-- and again every FULL_OFFER: an offer missed, or a journal they got only part of, is asked for
-- then), at most every SUMMARY_GAP.
local function SendSummary(id, peer, now)
	local s = summaries[id]
	if not s then
		s = { at = -math.huge, full = now, sent = {} }
		summaries[id] = s
	end
	if now - s.at < SUMMARY_GAP then
		return
	end
	if now - s.full >= FULL_OFFER then
		s.full = now
		wipe(s.sent)
	end
	local items = {}
	local function Offer(acct)
		local u = Held(acct)
		if u > 0 and acct ~= peer.journal and u > (s.sent[acct] or 0) then
			items[#items + 1] = acct .. "," .. u
			s.sent[acct] = u
		end
	end
	local mine = C.MyAccount()
	if mine then
		Offer(mine)
	end
	for acct in pairs(store.book) do
		Offer(acct)
	end
	if #items == 0 then
		return
	end
	s.at = now
	local B = ns.Beacon
	for first = 1, #items, 10 do
		B.QueueLow(id, J("s", table.concat(items, "/", first, math.min(first + 9, #items))))
	end
end

local function Request(id, acct, now)
	local p = pending[acct]
	if p and now - p.at < PENDING_TIMEOUT then
		return
	end
	pending[acct] = { from = id, at = now, got = 0 }
	ns.Beacon.Queue(id, J("q", acct, store.book[acct] and store.book[acct].u or 0))
end

-- Full names of a friend's characters that I learned (Battle.net showed them online, or an older
-- build's days by the full name joined their journal), not from their author: "l" messages,
-- J2;l;<acct>;<Name-Realm>;<full name>;<guid>, without a stamp (no author made them; older builds
-- ignore the word). They go with every answer about that account, whatever it asked since (whoever
-- holds the journal from older builds only has its first names), and to the account's owner when
-- they say hello: their journal takes the name of an alt it doesn't know (not played since their
-- update) and sends it on as its own ("a").
local function Learned(acct)
	local list = {}
	local a = acct ~= C.MyAccount() and store.book[acct]
	for key, c in pairs(a and a.chars or {}) do
		if not c.aliasU and HasSurname(c.full) then
			list[#list + 1] = J("l", acct, key, ns.Beacon.Clean(c.full, NAME_BYTES), c.guid or "")
		end
	end
	return list
end

-- Builds from 0.5.0-176 on (ba4dbad) read "l"; older ones ignore it, so they aren't sent it. A friend
-- whose build isn't known yet, or doesn't say its commit count, gets it, as before.
local NAMES_SINCE = "0.5.0-176-gba4dbad"
local function ReadsNames(peer)
	return LT.CompareVersions(peer and peer.version, NAMES_SINCE) ~= -1
end

-- An answer: the account's records newer than since, at most SERVE_MAX (never cutting between two
-- of the same stamp), the names learned of it, how many (c: a receiver that got fewer doesn't take
-- the end's stamp; older builds ignore it) and the end. An answer to the same friend for the same
-- account still waiting goes first: asked again, they get it once.
local function Serve(id, acct, since)
	local B = ns.Beacon
	B.DropLowFor(id, function(message)
		return message:sub(1, 3) == "J" .. VERSION .. ";" and message:find(";" .. acct .. ";", 1, true) ~= nil
	end)
	if Held(acct) == 0 then
		B.Queue(id, J("e", acct, since)) -- (nothing for them: they ask someone else)
		return
	end
	local list = Records(acct, since)
	local count = math.min(#list, SERVE_MAX)
	while list[count + 1] and list[count + 1][1] == list[count][1] do
		count = count + 1
	end
	for i = 1, count do
		B.QueueLow(id, list[i][2])
	end
	-- (counted too: every build that counts counts every message about the account it asked for;
	-- builds that don't read them get none, and a count without them)
	local learned = ReadsNames(B.peers[id]) and Learned(acct) or {}
	for _, message in ipairs(learned) do
		B.QueueLow(id, message)
	end
	local upTo = #list > count and list[count][1] or Held(acct)
	B.QueueLow(id, J("c", acct, count + #learned))
	B.QueueLow(id, J("e", acct, upTo))
end

local function Book(acct, key)
	local a = store.book[acct]
	if not a then
		a = { u = 0, chars = {} }
		store.book[acct] = a
	end
	local c = a.chars[key]
	if not c then
		c = { days = {}, news = {} }
		c.name, c.realm = key:match("^([^%-]+)%-(.+)$")
		a.chars[key] = c
	end
	a.seen = time()
	return c
end

local function Prune(c)
	local oldestDay, oldestT = Oldest(), C.DayAgo(DAYS_KEPT)
	for day in pairs(c.days) do
		if day < oldestDay or BeforeLaunch(day) then
			c.days[day] = nil
		end
	end
	if c.profile and BeforeLaunch(c.last or 0) then
		c.profile = nil -- (not played since the launch: the beta's numbers)
	end
	local list = {}
	for n, e in pairs(c.news) do
		if e.t < oldestT or BeforeLaunch(e.t) then
			c.news[n] = nil
		else
			list[#list + 1] = n
		end
	end
	if #list > NEWS_KEPT then
		table.sort(list)
		for i = 1, #list - NEWS_KEPT do
			c.news[list[i]] = nil
		end
	end
end

-- When a friend's character last played, as far as its journal says: its profile's last played,
-- its latest day, its latest highlight (never ahead of now: a wrong clock).
local function LastSeen(c)
	local t, latest = tonumber(c.last) or 0, nil
	for day in pairs(c.days) do
		latest = (not latest or day > latest) and day or latest
	end
	local y, mo, d = (latest or ""):match("^(%d+)-(%d+)-(%d+)$")
	if y then
		t = math.max(t, time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 0 }))
	end
	for _, e in pairs(c.news) do
		t = math.max(t, tonumber(e.t) or 0)
	end
	return math.min(t, time())
end

-- An account keeps its CHARS_KEPT most recently played characters; the others go (one played again
-- comes back with its next records).
local function Cap(a)
	if Count(a.chars) <= CHARS_KEPT then
		return
	end
	local list = {}
	for key, c in pairs(a.chars) do
		list[#list + 1] = { key = key, t = LastSeen(c) }
	end
	table.sort(list, function(x, y) return x.t > y.t or (x.t == y.t and x.key < y.key) end)
	for i = CHARS_KEPT + 1, #list do
		a.chars[list[i].key] = nil
	end
end

-- A record's numbers ("12,3400,5,..."), exactly count of them, or nil. Each at most 10 digits: more is
-- nobody's real number (a broken or hostile client), and too large to show or add up.
local function Numbers(text, count)
	local list = {}
	for n in text:gmatch("[^,]+") do
		if not n:match("^%d+$") or #n > 10 then
			return nil
		end
		list[#list + 1] = tonumber(n)
	end
	return #list == count and list or nil
end

-- A day's numbers (DAY_FIELDS): a day has 1440 minutes to play, or be AFK, at most (like a D2's).
local function DayNumbers(text)
	local numbers = Numbers(text, #DAY_FIELDS)
	for i, field in ipairs(numbers and DAY_FIELDS or {}) do
		if MINUTES[field] and numbers[i] > 1440 then
			return nil
		end
	end
	return numbers
end

-- A character's key in a record ("Anna-Realm": its first name, or its full name, and its realm), as
-- every build sends it. No escape codes or control characters: the pages show it as a name.
local function ValidKey(key)
	return type(key) == "string" and #key <= NAME_BYTES and key:match("^[^%-]+%-.+$") ~= nil and not key:find("[|%c]")
end

-- A stamp that can be real: an author's clock, give or take a week.
local function Plausible(u)
	return u and u > 0 and u <= time() + 7 * 86400
end

-- A full name a friend learned ("l", see Learned): for a character of one of my friends' journals,
-- or an alt of mine, that doesn't know its surname yet; never instead of one it knows, nor for the
-- character I play (UnitName says). Mine then goes on as my own (its profile's stamp changes with
-- it, so friends ask for its "a" record).
local function StoreName(acct, f)
	local key, full, guid = f[2], ns.Beacon.Clean(f[3] or "", NAME_BYTES), ValidGuid(f[4])
	if #f ~= 4 or not ValidKey(key) or not HasSurname(full) or FirstName(full) ~= FirstName(key) then
		return
	end
	local c
	if acct == C.MyAccount() then
		for _, mine in pairs(store.chars) do
			if CharKey(mine) == key and mine ~= C.Char() then
				c = mine
			end
		end
	elseif Friends()[acct] and store.book[acct] then
		c = store.book[acct].chars[key]
	end
	if not c or HasSurname(C.NameOf(c)) then
		return -- (a surname known, or in its key)
	end
	c.full, c.guid = full, c.guid or guid
	if acct == C.MyAccount() then
		StampChar(c, true, true)
	end
	Changed() -- (names in the news)
	C.feedDirty = true
end

-- One record from a friend (validated; only for my own Battle.net friends' accounts). Counted
-- for the request it answers.
local function Store(id, word, more, now)
	local f = {}
	for field in (more .. ";"):gmatch("([^;]*);") do
		f[#f + 1] = field
	end
	local acct, key, u = f[1], f[2], f[3] and f[3]:match("^%d+$") and tonumber(f[3])
	if not (acct and acct:match("^%x%x%x%x%x%x%x%x$")) then
		return
	end
	local p = pending[acct]
	if p and p.from == id then
		p.at, p.got = now, (p.got or 0) + 1
	end
	if word == "l" then
		StoreName(acct, f) -- (no stamp)
		return
	end
	if not (ValidKey(key) and Plausible(u)) or acct == C.MyAccount() or not Friends()[acct] then
		return
	end
	local known = store.book[acct] and store.book[acct].chars[key] ~= nil
	local changed, newNews = false, false
	if word == "p" and #f == 9 then
		local numbers = Numbers(f[7], #PROFILE_FIELDS)
		-- (last played before the launch: a character of the beta's)
		local c = numbers and not BeforeLaunch(tonumber(f[6]:match("^%d+$") or "") or 0) and Book(acct, key)
		if c and u > (c.u or 0) then
			-- (a level has three digits at most, last played is a time())
			c.u, c.classFile, c.level, c.last = u, f[4]:match("^%u+$"), tonumber(f[5]:match("^%d%d?%d?$") or ""),
				tonumber(f[6]:match("^%d+$") and #f[6] <= 10 and f[6] or "")
			c.profile = {}
			for i, field in ipairs(PROFILE_FIELDS) do
				c.profile[field] = MINUTES[field] and numbers[i] * 60 or numbers[i]
			end
			c.foe, c.zone = ns.Beacon.Clean(f[8], 40), ns.Beacon.Clean(f[9], 40)
			changed = true
		end
	elseif word == "d" and #f == 5 then
		local y, mo, d = f[4]:match("^(%d%d%d%d)(%d%d)(%d%d)$")
		local numbers = y and DayNumbers(f[5])
		local day = y and (y .. "-" .. mo .. "-" .. d)
		if numbers and day >= Oldest() and day <= date("%Y-%m-%d", C.DayAgo(-1)) and not BeforeLaunch(day) then
			local c = Book(acct, key)
			local old = c.days[day]
			if not old or u > (old.u or 0) then
				local b = { u = u }
				for i, field in ipairs(DAY_FIELDS) do
					b[field] = MINUTES[field] and numbers[i] * 60 or numbers[i]
				end
				c.days[day] = b
				c.level = math.max(c.level or 0, b.level or 0)
				changed = true
			end
		end
	elseif word == "n" and #f == 8 then
		local n, t, k = f[4]:match("^%d+$") and tonumber(f[4]), f[5]:match("^%d+$") and tonumber(f[5]), f[6]
		if n and t and SHAREABLE[k] and t >= C.DayAgo(DAYS_KEPT) and t <= time() + 86400 and not BeforeLaunch(t) then
			local c = Book(acct, key)
			local old = c.news[n]
			if not old or u > (old.u or 0) then
				c.news[n] = { u = u, t = t, k = k, a = ns.Beacon.Clean(f[7], TEXT_BYTES), b = ns.Beacon.Clean(f[8], TEXT_BYTES),
					g = old and old.g or time() }
				Prune(c)
				changed, newNews = true, true
			end
		end
	elseif word == "a" and #f == 5 then
		-- A character's full name and GUID, from its author (the name its journal is shown by, and
		-- how Battle.net's news finds it). It must name the character of its key.
		local full, guid = ns.Beacon.Clean(f[4], NAME_BYTES), ValidGuid(f[5])
		if full ~= "" and FirstName(full) == FirstName(key) then
			local c = Book(acct, key)
			if u > (c.aliasU or 0) then
				c.full, c.guid, c.aliasU = full, guid or c.guid, u
				changed, newNews = true, true -- (the news shows the name)
			end
		end
	end
	if not known and store.book[acct] and store.book[acct].chars[key] then
		Cap(store.book[acct]) -- (a character new to the account: the most recently played stay)
	end
	if newNews then
		Changed() -- (the merged feed is rebuilt)
	end
	if changed then
		C.feedDirty = true -- (the open page: Friends, Compare, a friend's graphs)
	end
end

-- Beacon.lua hands every J message here (after its own spam guard). Answering a request is heavy
-- (hundreds of messages built): that waits for the tick (serves).
function ns.Beacon.ReceiveJournal(id, word, more)
	if not (M.enabled and store) then
		return
	end
	local peer = ns.Beacon.peers[id]
	if not peer then
		return
	end
	local now = GetTime()
	if word == "h" then
		peer.journal = more:match("^%x%x%x%x%x%x%x%x$") or "" -- (they sync; their account, if known)
		summaries[id] = nil -- (they (re)started: everything is offered again)
		for _, message in ipairs(peer.journal ~= "" and ReadsNames(peer) and Learned(peer.journal) or {}) do
			ns.Beacon.QueueLow(id, message) -- (their own characters' names I learned, if their build reads them)
		end
	elseif word == "s" then
		peer.journal = peer.journal or ""
		for acct, u in more:gmatch("(%x%x%x%x%x%x%x%x),(%d+)") do
			u = tonumber(u)
			if acct ~= C.MyAccount() and Friends()[acct] and Plausible(u) and u > ((store.book[acct] or {}).u or 0) then
				Request(id, acct, now)
			end
		end
	elseif word == "q" then
		local acct, since = more:match("^(%x%x%x%x%x%x%x%x);(%d+)$")
		if acct then
			for i = #serves, 1, -1 do -- (asked again before it was answered: once)
				if serves[i].id == id and serves[i].acct == acct then
					table.remove(serves, i)
				end
			end
			if #serves < 50 then
				serves[#serves + 1] = { id = id, acct = acct, since = tonumber(since) }
			end
		end
	elseif word == "c" then
		local acct, count = more:match("^(%x%x%x%x%x%x%x%x);(%d+)$")
		local p = acct and pending[acct]
		if p and p.from == id then
			p.expect = tonumber(count)
		end
	elseif word == "e" then
		local acct, u = more:match("^(%x%x%x%x%x%x%x%x);(%d+)$")
		local p = acct and pending[acct]
		if p and p.from == id then
			pending[acct] = nil
			u = tonumber(u)
			-- Fewer records came than were sent (lost on the way): not complete; asked again later.
			if Plausible(u) and not (p.expect and (p.got or 0) < p.expect) then
				local a = store.book[acct] or { u = 0, chars = {} } -- (nothing newer came: still, they're complete)
				store.book[acct] = a
				a.u = math.max(a.u or 0, u)
			end
		end
	else
		Store(id, word, more, now)
	end
end

-- A friend went away: what was asked of them can be asked of someone else.
function ns.Beacon.JournalForget(id)
	summaries[id] = nil
	for acct, p in pairs(pending) do
		if p.from == id then
			pending[acct] = nil
		end
	end
	for i = #serves, 1, -1 do
		if serves[i].id == id then
			table.remove(serves, i)
		end
	end
end

-- Beacon switched off: nothing asked, offered or owed any more.
function ns.Beacon.JournalStop()
	wipe(summaries)
	wipe(pending)
	wipe(serves)
end

-- Friends' journals that aren't worth keeping: accounts no longer among my friends (once the friend
-- list is known), characters with nothing in the last BOOK_DAYS days.
local function PruneBook()
	local friends = Friends()
	local oldest = C.DayAgo(BOOK_DAYS)
	for acct, a in pairs(store.book) do
		if next(friends) and not friends[acct] then
			store.book[acct] = nil
		else
			for key, c in pairs(a.chars) do
				Prune(c)
				if not next(c.days) and not next(c.news) and ((c.last or 0) < oldest or BeforeLaunch(c.last or 0)) then
					a.chars[key] = nil
				end
			end
			if not next(a.chars) then
				store.book[acct] = nil
			end
		end
	end
	Changed()
end

---------------------------------------------------------------------------
-- The tick (Chronicle.lua's, once a second) and switching on and off
---------------------------------------------------------------------------

function C.SyncTick(now)
	if not store then
		return
	end
	local char = C.Char()
	if now - lastCheck >= CHECK_GAP then
		lastCheck = now
		local withProfile = now - lastProfile >= PROFILE_GAP
		if withProfile then
			lastProfile = now
		end
		StampChar(char, true, withProfile)
	end
	for acct, p in pairs(pending) do
		if now - p.at >= PENDING_TIMEOUT then
			pending[acct] = nil
		end
	end
	local B = Beacon()
	if B then
		for _ = 1, SERVES_PER_TICK do -- (answers to friends' requests, built here, not in the event)
			local serve = table.remove(serves, 1)
			if not serve then
				break
			end
			if B.peers[serve.id] then
				Serve(serve.id, serve.acct, serve.since)
			end
		end
		for id, peer in pairs(B.peers) do
			if peer.journal then
				SendSummary(id, peer, now)
			end
		end
	end
	if pruneAt and now >= pruneAt then
		pruneAt = nil
		PruneBook()
	end
	if meetAt and now >= meetAt then
		meetAt = now + MEET_GAP
		C.Meet() -- (Characters.lua: Battle.net tells friends' full names)
	end
	C.RecapTick(now) -- (Recap.lua: while you were away, the weekly recap)
end

function C.SyncEnable()
	store = C.Store()
	store.book = type(store.book) == "table" and store.book or {}
	-- My last stamp from a clock that was more than a week ahead once: friends drop every record of
	-- mine stamped after it (Plausible), and every new stamp would go on from it, for good. Everything
	-- of mine is stamped anew from now.
	local fromTheFuture = type(store.myU) == "number" and store.myU > time() + 7 * 86400
	if fromTheFuture then
		store.myU = nil
	end
	for _, c in pairs(store.chars) do
		C.Fill(c)
		Upgrade(c)
		if fromTheFuture then
			Restamp(c)
		end
	end
	for _, c in pairs(store.chars) do
		StampChar(c, false, true)
	end
	for acct, a in pairs(store.book) do
		a.chars = type(a.chars) == "table" and a.chars or {}
		for key, c in pairs(a.chars) do
			if not ValidKey(key) then
				a.chars[key] = nil -- (from before records were checked this closely)
			else
				c.days, c.news = c.days or {}, c.news or {}
				c.name, c.realm = key:match("^([^%-]+)%-(.+)$")
				Prune(c)
			end
		end
		Cap(a) -- (saved before there was a cap: the most recently played stay)
		if type(a.u) ~= "number" or a.u > time() + 7 * 86400 then
			a.u = 0 -- (an impossible stamp would block the account for good: everything is asked again)
		end
	end
	if (store.identity or 0) < 1 then
		C.JoinCharacters()
		store.identity = 1
	end
	if store.sharedAlts == nil then
		store.sharedAlts = M.db.shareAlts
	end
	-- Only the character I play is shared, and it's another one than last time: its records are
	-- stamped anew, or friends (further than its old stamps) would never ask for them.
	local current = C.CurrentKey()
	if not M.db.shareAlts and store.sharedChar and store.sharedChar ~= current and C.Char() then
		Restamp(C.Char())
	end
	store.sharedChar = current
	local now = GetTime()
	lastCheck, lastProfile = now, now
	wipe(pending)
	wipe(summaries)
	wipe(serves)
	C.RecapStart(now)
	pruneAt = now + 60 -- (the friend list is known by then)
	meetAt = now + MEET_FIRST
	-- Switched on mid-session: friends already here hear it now (at login nobody is known yet;
	-- they learn it from my answers).
	local B = Beacon()
	if B then
		for id in pairs(B.peers) do
			B.QueueLow(id, J("h", C.MyAccount() or ""))
		end
	end
	Changed()
end

function C.SyncDisable()
	wipe(pending)
	wipe(summaries)
	wipe(serves)
	pruneAt, meetAt = nil, nil
	C.RecapStop()
end

-- A setting changed: friends hear again what grew (all my characters, when that was switched on).
function C.SyncSettingChanged()
	if not store then
		return
	end
	if M.db.shareAlts ~= store.sharedAlts then
		store.sharedAlts = M.db.shareAlts
		for _, c in pairs(store.chars) do
			Restamp(c)
		end
	end
	wipe(summaries) -- (everything offered again)
end

-- Requests waiting for an answer (Recap.lua waits while journals still come in; tests).
function C.SyncPending()
	return pending
end
