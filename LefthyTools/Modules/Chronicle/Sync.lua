local _, ns = ...
local LT = ns.LT
local L = ns.L
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
--   J2;e;<acct>;<u>        that's all: you're complete up to u
-- A request goes to one friend at a time per account (PENDING_TIMEOUT without progress: another
-- may answer). An answer holds at most SERVE_MAX records, oldest first; its end says how far that
-- got, so the rest follows on the next round. Old D2/K2/E2 messages still go to everyone (older
-- builds, chat lines); their data stays in store.friendStats / store.friends and is shown where a
-- friend has no synced journal.
--
-- Also here: "while you were away" after logging in, the weekly recap, the leaderboards and the
-- people for the Compare page, and sharing a ranking in Lefthy chat.
--
-- Cost: a check every CHECK_GAP (today's and yesterday's numbers as text, compared), summaries
-- when something changed, everything else only when a friend asks or sends.

local VERSION = "2"
local DAYS_KEPT = 30
local NEWS_KEPT = 150
local SUMMARY_GAP = 60
local CHECK_GAP = 60
local PROFILE_GAP = 300
local PENDING_TIMEOUT = 90
local SERVE_MAX = 400
local FRIENDS_CACHE = 30
local CATCHUP_AFTER, CATCHUP_WAIT = 75, 240 -- s after logging in; waiting for syncs at most this long
local RECAP_AFTER = 120
local NAME_BYTES, TEXT_BYTES = 48, 60
local SHAREABLE = { level = true, death = true, zone = true, dungeon = true, boss = true, rare = true, loot = true, mount = true,
	achievement = true, quests = true, gold = true, profession = true }
local DAY_FIELDS = { "played", "xp", "quests", "kills", "deaths", "levels", "afk", "level", "gold", "dist", "bosses", "rares",
	"runs", "jumps" }
local MINUTES = { played = true, afk = true } -- sent in minutes, kept in seconds
local PROFILE_FIELDS = { "played", "sessions", "quests", "kills", "deaths", "zones", "dungeons", "runs", "bosses", "rares",
	"dist", "jumps", "mounts", "achievements", "gold", "fastest", "longest", "afk", "loot4", "levels", "xp" }
local issecret = issecretvalue or function() return false end

local store
local myAcct
local friendsCache, friendsAt = {}, -math.huge
local pending = {}     -- acct -> { from, at }
local summaries = {}   -- gameAccountID -> { at, sent = { [acct] = u } }
local lastCheck, lastProfile = -math.huge, -math.huge
local catchUp          -- { since, at, deadline }
local recapAt
local feedVersion = 0  -- bumped when friends' news change (the merged feed is rebuilt then)

---------------------------------------------------------------------------
-- Accounts: BattleTag hashes
---------------------------------------------------------------------------

-- Two 32-bit rolling hashes over the lowercased BattleTag, folded into 8 hex digits (built from
-- two 16-bit halves: %x of a number above 2^31 isn't safe in every Lua).
local function Hash(text)
	local h1, h2 = 5381, 0
	text = text:lower()
	for i = 1, #text do
		local b = text:byte(i)
		h1 = (h1 * 33 + b) % 4294967296
		h2 = (h2 * 131 + b) % 4294967296
	end
	local h = (h1 + h2 * 7) % 4294967296
	return ("%04x%04x"):format(math.floor(h / 65536), h % 65536)
end
C.Hash = Hash

function C.MyAccount()
	if not myAcct and BNGetInfo then
		local _, battleTag = BNGetInfo()
		if type(battleTag) == "string" and battleTag ~= "" and not issecret(battleTag) then
			myAcct = Hash(battleTag)
		end
	end
	return myAcct
end

-- My Battle.net friends' hashes -> the BattleTag's name (shown for the account), kept 30 s.
local function Friends()
	local now = GetTime()
	if now - friendsAt < FRIENDS_CACHE then
		return friendsCache
	end
	friendsAt = now
	wipe(friendsCache)
	local getInfo = C_BattleNet and C_BattleNet.GetFriendAccountInfo
	for i = 1, (getInfo and BNGetNumFriends and BNGetNumFriends() or 0) do
		local info = getInfo(i)
		local tag = info and info.battleTag
		if type(tag) == "string" and tag ~= "" and not issecret(tag) then
			friendsCache[Hash(tag)] = tag:match("^[^#]+") or tag
		end
	end
	return friendsCache
end
C.FriendAccounts = Friends

function C.AccountLabel(acct)
	return Friends()[acct]
end

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

local function Changed()
	feedVersion = feedVersion + 1
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

local function Count(t)
	local n = 0
	for _ in pairs(t or {}) do
		n = n + 1
	end
	return n
end

local function Top(t)
	local best, most
	for key, value in pairs(t or {}) do
		if not most or value > most or (value == most and key < best) then
			best, most = key, value
		end
	end
	return best
end

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
		local text = numbers .. ";" .. foe .. ";" .. zone .. ";" .. (c.level or 0)
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
			e.n, e.u = s.seq, e.t
			store.myU = math.max(store.myU or 0, e.t)
		end
	end
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

-- How far I hold an account (0: not at all).
local function Held(acct)
	if acct == C.MyAccount() then
		return M.db.share and (store.myU or 0) or 0
	end
	local a = store.book[acct]
	return a and M.db.relay and a.u or 0
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

-- What I hold, to one friend: only what grew since they last heard it (everything the first time),
-- at most every SUMMARY_GAP.
local function SendSummary(id, peer, now)
	local s = summaries[id]
	if not s then
		s = { at = -math.huge, sent = {} }
		summaries[id] = s
	end
	if now - s.at < SUMMARY_GAP then
		return
	end
	local items = {}
	local function Offer(acct)
		local u = Held(acct)
		if u > 0 and acct ~= peer.journal and u > (s.sent[acct] or 0) then
			items[#items + 1] = acct .. "," .. u
			s.sent[acct] = u
		end
	end
	if C.MyAccount() then
		Offer(myAcct)
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
	pending[acct] = { from = id, at = now }
	ns.Beacon.Queue(id, J("q", acct, store.book[acct] and store.book[acct].u or 0))
end

local function Serve(id, acct, since)
	if Held(acct) == 0 then
		ns.Beacon.Queue(id, J("e", acct, since)) -- (nothing for them: they ask someone else)
		return
	end
	local list = Records(acct, since)
	local B = ns.Beacon
	local count = math.min(#list, SERVE_MAX)
	for i = 1, count do
		B.QueueLow(id, list[i][2])
	end
	local upTo = #list > SERVE_MAX and list[SERVE_MAX][1] or Held(acct)
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
		c.name, c.realm = key:match("^([^%-]+)%-?(.*)$")
		a.chars[key] = c
	end
	a.seen = time()
	return c
end

local function Progress(acct, now)
	if pending[acct] then
		pending[acct].at = now
	end
end

local function Prune(c)
	local oldestDay, oldestT = Oldest(), C.DayAgo(DAYS_KEPT)
	for day in pairs(c.days) do
		if day < oldestDay then
			c.days[day] = nil
		end
	end
	local list = {}
	for n, e in pairs(c.news) do
		if e.t < oldestT then
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

local function Numbers(text, count)
	local list = {}
	for n in text:gmatch("[^,]+") do
		list[#list + 1] = tonumber(n)
	end
	return #list == count and list or nil
end

-- One record from a friend (validated; only for my own Battle.net friends' accounts).
local function Store(word, more, now)
	local f = {}
	for field in (more .. ";"):gmatch("([^;]*);") do
		f[#f + 1] = field
	end
	local acct, key, u = f[1], f[2], tonumber(f[3])
	if not (acct and acct:match("^%x%x%x%x%x%x%x%x$") and key and key ~= "" and #key <= NAME_BYTES and u)
		or acct == C.MyAccount() or not Friends()[acct] then
		return
	end
	Progress(acct, now)
	if word == "p" and #f == 9 then
		local numbers = Numbers(f[7], #PROFILE_FIELDS)
		local c = numbers and Book(acct, key)
		if c and u > (c.u or 0) then
			c.u, c.classFile, c.level, c.last = u, f[4]:match("^%u+$"), tonumber(f[5]), tonumber(f[6])
			c.profile = {}
			for i, field in ipairs(PROFILE_FIELDS) do
				c.profile[field] = MINUTES[field] and numbers[i] * 60 or numbers[i]
			end
			c.foe, c.zone = ns.Beacon.Clean(f[8], 40), ns.Beacon.Clean(f[9], 40)
			Changed()
		end
	elseif word == "d" and #f == 5 then
		local y, mo, d = f[4]:match("^(%d%d%d%d)(%d%d)(%d%d)$")
		local numbers = y and Numbers(f[5], #DAY_FIELDS)
		local day = y and (y .. "-" .. mo .. "-" .. d)
		if numbers and day >= Oldest() and day <= date("%Y-%m-%d", C.DayAgo(-1)) then
			local c = Book(acct, key)
			local old = c.days[day]
			if not old or u > (old.u or 0) then
				local b = { u = u }
				for i, field in ipairs(DAY_FIELDS) do
					b[field] = MINUTES[field] and numbers[i] * 60 or numbers[i]
				end
				c.days[day] = b
				c.level = math.max(c.level or 0, b.level or 0)
				Changed()
			end
		end
	elseif word == "n" and #f == 8 then
		local n, t, k = tonumber(f[4]), tonumber(f[5]), f[6]
		if n and t and SHAREABLE[k] and t >= C.DayAgo(DAYS_KEPT) and t <= time() + 86400 then
			local c = Book(acct, key)
			local old = c.news[n]
			if not old or u > (old.u or 0) then
				c.news[n] = { u = u, t = t, k = k, a = ns.Beacon.Clean(f[7], TEXT_BYTES), b = ns.Beacon.Clean(f[8], TEXT_BYTES),
					g = old and old.g or time() }
				Prune(c)
				Changed()
			end
		end
	end
	C.feedDirty, C.dirty = true, true
end

-- Beacon.lua hands every J message here (after its own spam guard).
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
	elseif word == "s" then
		peer.journal = peer.journal or ""
		for acct, u in more:gmatch("(%x%x%x%x%x%x%x%x),(%d+)") do
			u = tonumber(u)
			if acct ~= C.MyAccount() and Friends()[acct] and u > ((store.book[acct] or {}).u or 0) then
				Request(id, acct, now)
			end
		end
	elseif word == "q" then
		local acct, since = more:match("^(%x%x%x%x%x%x%x%x);(%d+)$")
		if acct then
			Serve(id, acct, tonumber(since))
		end
	elseif word == "e" then
		local acct, u = more:match("^(%x%x%x%x%x%x%x%x);(%d+)$")
		local p = acct and pending[acct]
		if p and p.from == id then
			pending[acct] = nil
			local a = store.book[acct] or { u = 0, chars = {} } -- (nothing newer came: still, they're complete)
			store.book[acct] = a
			a.u = math.max(a.u or 0, tonumber(u))
		end
	else
		Store(word, more, now)
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
end

---------------------------------------------------------------------------
-- People, news and leaderboards (for the window, the recap and sharing)
---------------------------------------------------------------------------

local function Online(name)
	local B = ns.Beacon
	for _, peer in pairs(B and B.peers or {}) do
		if peer.name == name then
			return true
		end
	end
	return false
end

-- Everyone with a journal: me (the character I play) first, then friends' characters (synced
-- journals; friends on older builds from the days they sent), by name. Each: { key, name, classFile,
-- level, me, online, last, days, profile, foe, zone, acct, account (their BattleTag's name) }.
function C.People()
	local people, names = {}, {}
	local me = C.Char()
	if me then
		local profile = ProfileNumbers(me)
		people[1] = { key = "me", name = me.name, classFile = me.classFile, level = me.level, me = true, online = true,
			last = time(), days = me.daily, profile = profile, foe = Top(me.killers), zone = Top(me.zoneTime) }
	end
	local friends = {}
	for acct, a in pairs(store.book) do
		if acct ~= C.MyAccount() then
			for key, c in pairs(a.chars) do
				local last = c.last or 0
				for day, b in pairs(c.days) do
					if (b.played or 0) > 0 then
						local y, mo, d = day:match("^(%d+)-(%d+)-(%d+)$")
						last = math.max(last, time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 12 }))
					end
				end
				friends[#friends + 1] = { key = "book:" .. acct .. ":" .. key, name = c.name, realm = c.realm, classFile = c.classFile,
					level = c.level, online = Online(c.name), last = last, days = c.days, profile = c.profile, foe = c.foe,
					zone = c.zone, acct = acct, account = C.AccountLabel(acct), news = c.news }
				names[c.name] = true
			end
		end
	end
	for name, f in pairs(store.friendStats or {}) do
		if not names[name] then
			friends[#friends + 1] = { key = "friend:" .. name, name = name, classFile = f.classFile, level = f.level,
				online = Online(name), last = f.updated or 0, days = f.days or {}, legacy = true }
		end
	end
	table.sort(friends, function(a, b) return (a.name or "") < (b.name or "") end)
	for _, f in ipairs(friends) do
		people[#people + 1] = f
	end
	return people
end

-- "just now", "5 min ago", "3 h ago", "yesterday", "4 days ago" (localized).
function C.Ago(t)
	local seconds = math.max(0, time() - (t or 0))
	if seconds < 120 then
		return L["just now"]
	elseif seconds < 3600 then
		return L["%d min ago"]:format(math.floor(seconds / 60))
	elseif seconds < 86400 then
		return L["%d h ago"]:format(math.floor(seconds / 3600))
	elseif seconds < 2 * 86400 then
		return L["yesterday"]
	end
	return L["%d days ago"]:format(math.floor(seconds / 86400))
end

function C.Person(key)
	for _, person in ipairs(C.People()) do
		if person.key == key then
			return person
		end
	end
end

-- A metric's value on one day of a person (nil: no record that day).
function C.DayValue(person, day, metric)
	local b = person.days[day]
	return b and b[metric]
end

-- Sums over the last `count` days (ending today, or `ending` days ago).
function C.Sum(person, metric, count, ending)
	local sum = 0
	for i = ending or 0, (ending or 0) + count - 1 do
		sum = sum + (C.DayValue(person, date("%Y-%m-%d", C.DayAgo(i)), metric) or 0)
	end
	return sum
end

C.BOARD = { "played", "xp", "quests", "kills", "levels", "deaths", "dist", "jumps", "afk" }

-- Rankings over `count` days ending `ending` days ago: { [metric] = { { person, value }, ... } },
-- highest first, only people with some time played then.
function C.Leaderboard(count, ending, people)
	local board = {}
	people = people or C.People()
	for _, metric in ipairs(C.BOARD) do
		local list = {}
		for _, person in ipairs(people) do
			if C.Sum(person, "played", count, ending) > 0 then
				local value = C.Sum(person, metric, count, ending)
				if value > 0 then
					list[#list + 1] = { person = person, value = value }
				end
			end
		end
		table.sort(list, function(a, b) return a.value > b.value or (a.value == b.value and a.person.name < b.person.name) end)
		board[metric] = list
	end
	return board
end

-- The merged feed, oldest first: friends' synced highlights and what came live (Beacon's events,
-- E2 highlights, online and offline), each once (a live one that a synced one repeats goes).
local merged, mergedFor
function C.FriendNews()
	local version = feedVersion .. ":" .. #store.friends .. ":" .. tostring(store.friends[#store.friends])
	if mergedFor == version then
		return merged
	end
	local list, synced = {}, {}
	for acct, a in pairs(store.book) do
		if acct ~= C.MyAccount() then
			for _, c in pairs(a.chars) do
				for _, e in pairs(c.news) do
					local entry = { t = e.t, g = e.g, name = c.name, classFile = c.classFile, k = e.k, a = e.a, b = e.b, synced = true }
					if e.k == "level" then
						entry.level = tonumber(e.a)
					elseif e.k == "death" then
						entry.foe, entry.where = e.a ~= "" and e.a or nil, e.b
					end
					list[#list + 1] = entry
					local id = c.name .. "|" .. e.k .. "|" .. (e.a or "")
					synced[id] = synced[id] or {}
					table.insert(synced[id], e.t)
				end
			end
		end
	end
	for _, f in ipairs(store.friends) do
		local a = f.k == "level" and tostring(f.level or "") or f.k == "death" and (f.foe or "") or f.a or ""
		local times = synced[(f.name or "") .. "|" .. (f.k or "") .. "|" .. a]
		local repeated = false
		for _, t in ipairs(times or {}) do
			repeated = repeated or math.abs(t - f.t) < 900
		end
		if not repeated then
			list[#list + 1] = f
		end
	end
	table.sort(list, function(x, y) return x.t < y.t end)
	merged, mergedFor = list, version
	return list
end

-- News from friends the journal hasn't shown yet (the Friends page marks them seen).
function C.UnseenCount()
	if not store then
		return 0
	end
	local seen, count = store.feedSeenAt or 0, 0
	for _, f in ipairs(C.FriendNews()) do
		if (f.g or f.t) > seen and f.k ~= "online" and f.k ~= "offline" and f.k ~= "quest" then
			count = count + 1
		end
	end
	return count
end

function C.MarkFeedSeen()
	if store then
		store.feedSeenAt = time()
		if C.UpdateNewDot then
			C.UpdateNewDot()
		end
	end
end

---------------------------------------------------------------------------
-- Chat: while you were away, the weekly recap, sharing (English, like all chat output)
---------------------------------------------------------------------------

local NEWS_CHAT = {
	level = function(f) return ("reached level %s"):format(f.level or f.a or "?") end,
	death = function(f) return f.foe and ("died to %s"):format(f.foe) or "died" end,
	zone = function(f) return ("discovered %s"):format(f.a) end,
	dungeon = function(f) return ("entered %s"):format(f.a) end,
	boss = function(f) return ("defeated %s"):format(f.a) end,
	rare = function(f) return ("killed the rare %s"):format(f.a) end,
	loot = function(f) return ("looted %s"):format(C.QualityText(f.a or "?", tonumber(f.b))) end,
	mount = function(f) return ("got the mount %s"):format(f.a) end,
	achievement = function(f) return ("earned %s"):format(f.a) end,
	quests = function(f) return ("completed %s quests"):format(f.a) end,
	gold = function(f) return ("has %s gold"):format(f.a) end,
	profession = function(f) return ("reached %s %s"):format(f.a, f.b) end,
}
local CHAT_ORDER = { level = 1, boss = 2, rare = 3, dungeon = 4, achievement = 5, mount = 6, loot = 7, profession = 8,
	quests = 9, gold = 10, death = 11, zone = 12 }

local function Coloured(name, classFile)
	return LT.Window.ClassColorCode(classFile) .. (name or "?") .. "|r"
end

-- One line per friend, the most notable first: "Anna: reached level 24, defeated Hogger, died 2x (+5 more)".
function C.CatchUpLines(since)
	local byName, order = {}, {}
	for _, f in ipairs(C.FriendNews()) do
		if f.t > since and NEWS_CHAT[f.k] then
			local entry = byName[f.name]
			if not entry then
				entry = { classFile = f.classFile, items = {}, deaths = 0, zones = 0 }
				byName[f.name] = entry
				order[#order + 1] = f.name
			end
			if f.k == "death" then
				entry.deaths = entry.deaths + 1
			elseif f.k == "zone" then
				entry.zones = entry.zones + 1
			else
				entry.items[#entry.items + 1] = f
			end
		end
	end
	local lines = {}
	for _, name in ipairs(order) do
		local entry = byName[name]
		table.sort(entry.items, function(a, b) return (CHAT_ORDER[a.k] or 99) < (CHAT_ORDER[b.k] or 99) end)
		local parts = {}
		for i, f in ipairs(entry.items) do
			if i > 3 then
				break
			end
			parts[#parts + 1] = NEWS_CHAT[f.k](f)
		end
		if entry.zones > 0 then
			parts[#parts + 1] = entry.zones == 1 and "discovered a zone" or ("discovered %d zones"):format(entry.zones)
		end
		if entry.deaths > 0 then
			parts[#parts + 1] = entry.deaths == 1 and "died once" or ("died %d times"):format(entry.deaths)
		end
		local more = #entry.items - 3
		lines[#lines + 1] = Coloured(name, entry.classFile) .. ": " .. table.concat(parts, ", ") .. (more > 0 and (" (+%d more)"):format(more) or "")
	end
	return lines
end

local LABEL_CHAT = { played = "time played", xp = "XP", quests = "quests", kills = "killing blows", levels = "levels",
	deaths = "deaths", dist = "distance", jumps = "jumps", afk = "time AFK" }

-- A value as chat text (English).
function C.ChatValue(metric, value)
	if metric == "played" or metric == "afk" then
		return C.Duration(value)
	elseif metric == "dist" then
		return C.Distance(value, true)
	end
	return C.Number(value)
end

-- "Quests: Anna 142, Bob 98, Lefthy 61" for a ranking (people's names plain: chat links can't colour).
function C.RankingText(metric, list, count)
	local parts = {}
	for i = 1, math.min(count or 3, #list) do
		parts[#parts + 1] = ("%s %s"):format(list[i].person.name, C.ChatValue(metric, list[i].value))
	end
	return #parts > 0 and (LABEL_CHAT[metric]:gsub("^%l", string.upper) .. ": " .. table.concat(parts, ", ")) or nil
end

-- The week's leaderboard in a few lines: the leader of each, plus the Martin award.
function C.RecapLines(count, ending)
	local board, lines = C.Leaderboard(count, ending), {}
	for _, metric in ipairs(C.BOARD) do
		local list = board[metric]
		if list[1] and #list >= 1 then
			local first = list[1]
			local title = metric == "deaths" and "most deaths" or metric == "afk" and "Martin award (most time AFK)"
				or ("most " .. LABEL_CHAT[metric])
			lines[#lines + 1] = ("%s: %s (%s)"):format(title, Coloured(first.person.name, first.person.classFile),
				C.ChatValue(metric, first.value))
		end
	end
	return lines, board
end

-- Shares a line in Lefthy chat (Beacon's /l), or prints it if that isn't on.
function C.ShareLine(text)
	local B = Beacon()
	local beacon = LT:GetModule("beacon")
	if B and B.SendChat and beacon.db.lefthyChat then
		B.SendChat(text)
	else
		M:Print(text .. " (Lefthy chat is off: only you see this.)")
	end
end

-- Monday of the week `back` weeks ago, as YYYY-MM-DD.
local function Monday(back)
	local t = date("*t")
	local sinceMonday = (t.wday + 5) % 7 -- wday: 1 = Sunday
	return date("%Y-%m-%d", time({ year = t.year, month = t.month, day = t.day - sinceMonday - 7 * (back or 0), hour = 12 }))
end
C.Monday = Monday

local function Recap()
	recapAt = nil
	local week = Monday(0)
	if store.recapWeek == week then
		return
	end
	store.recapWeek = week
	-- Last week: Monday to Sunday, ending (days since this Monday + 1) days ago.
	local t = date("*t")
	local ending = (t.wday + 5) % 7 + 1
	local lines, board = C.RecapLines(7, ending)
	if #(board.played or {}) < 2 then
		return -- (alone, or nobody played: nothing to compare)
	end
	M:Print("last week's leaderboard (Chronicle):")
	for _, line in ipairs(lines) do
		print("   |cffffd200•|r " .. line)
	end
end

local function CatchUp(now)
	if next(pending) and now < catchUp.deadline then
		return -- (journals still coming in)
	end
	local since = catchUp.since
	catchUp = nil
	local lines = C.CatchUpLines(since)
	if #lines == 0 then
		return
	end
	M:Print(("while you were away (since %s):"):format(date("%H:%M %b %d", since)))
	for i, line in ipairs(lines) do
		if i > 6 then
			print(("   |cffffd200•|r and %d more friends: /chronicle"):format(#lines - 6))
			break
		end
		print("   |cffffd200•|r " .. line)
	end
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
		for id, peer in pairs(B.peers) do
			if peer.journal then
				SendSummary(id, peer, now)
			end
		end
	end
	if catchUp and now >= catchUp.at then
		if M.db.catchUp then
			CatchUp(now)
		else
			catchUp = nil
		end
	end
	if recapAt and now >= recapAt then
		if M.db.weeklyRecap then
			Recap()
		else
			recapAt = nil
		end
	end
end

function C.SyncEnable()
	store = C.Store()
	store.book = type(store.book) == "table" and store.book or {}
	for _, c in pairs(store.chars) do
		C.Fill(c)
		Upgrade(c)
	end
	for _, c in pairs(store.chars) do
		StampChar(c, false, true)
	end
	for _, a in pairs(store.book) do
		a.chars = type(a.chars) == "table" and a.chars or {}
		for _, c in pairs(a.chars) do
			c.days, c.news = c.days or {}, c.news or {}
			Prune(c)
		end
	end
	local now = GetTime()
	lastCheck, lastProfile = now, now
	wipe(pending)
	wipe(summaries)
	if store.lastSeenAt and time() - store.lastSeenAt > 300 then
		catchUp = { since = store.lastSeenAt, at = now + CATCHUP_AFTER, deadline = now + CATCHUP_WAIT }
	end
	recapAt = now + RECAP_AFTER
	if store.sharedAlts == nil then
		store.sharedAlts = M.db.shareAlts
	end
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
	catchUp, recapAt = nil, nil
end

-- A setting changed: friends hear again what grew (all my characters, when that was switched on).
function C.SyncSettingChanged()
	if not store then
		return
	end
	if M.db.shareAlts ~= store.sharedAlts then
		store.sharedAlts = M.db.shareAlts
		for _, c in pairs(store.chars) do
			local s = SyncState(c)
			wipe(s.daySig)
			s.profileSig = nil
			for _, e in ipairs(c.events) do
				if e.n then
					e.u = NextU()
				end
			end
		end
		for _, c in pairs(store.chars) do
			StampChar(c, false, true)
		end
	end
	wipe(summaries) -- (everything offered again)
end

-- For tests.
function C.SyncPending()
	return pending
end
