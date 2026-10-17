local _, ns = ...
local L = ns.L
local C = ns.Chronicle

-- Who is who: Battle.net accounts and characters, whatever named them. An account (a Battle.net
-- account, its BattleTag) goes by an 8-hex hash of its BattleTag, my friends' only (C.FriendAccounts).
-- A character goes by its journal's key (the first name and realm, "Anna-Realm", as every build sends
-- it), while Battle.net, Beacon's live news and older builds' days name it by the name the game shows
-- ("Anna Brook": first name and surname). Here they're matched (FindBook, Learn; Battle.net's friend
-- list teaches the full names, Meet), and the lists every page and the chat use are built: every
-- character once (C.Characters), every account once with its characters added up (C.Accounts), and
-- friends' news, synced and live, each once (C.FriendNews). Never two characters taken for one, an
-- account never named after one of its characters, and a character never also shown as part of
-- another row.
--
-- Sync.lua passes the journals between friends (store.book), Recap.lua turns these lists into chat.

local DAYS = 30 -- an account's days added up: what friends' journals keep (Sync.lua's DAYS_KEPT)
local FRIENDS_CACHE = 30
local issecret = ns.LT.IsSecret

local myAcct
local friendsCache, friendsAt = {}, -math.huge
local newsVersion = 0 -- bumped when friends' news or names change (the merged feed is rebuilt then)

-- Friends' news changed (a record came, a name was learned, the book was pruned): C.FriendNews is
-- built anew when next asked.
local function NewsChanged()
	newsVersion = newsVersion + 1
end
C.NewsChanged = NewsChanged

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

-- Is an account one of my friends' (while the friend list isn't known yet: assumed so)?
local function IsFriend(acct)
	local friends = Friends()
	return next(friends) == nil or friends[acct] ~= nil
end
C.IsFriend = IsFriend

function C.AccountLabel(acct)
	return Friends()[acct]
end

-- A Beacon friend's account (their BattleTag's hash), or nil while Battle.net doesn't say.
function C.PeerAccount(peer)
	local guid = peer and peer.guid
	local info = type(guid) == "string" and not issecret(guid) and C_BattleNet and C_BattleNet.GetAccountInfoByGUID
		and C_BattleNet.GetAccountInfoByGUID(guid)
	local tag = info and info.battleTag
	if type(tag) == "string" and tag ~= "" and not issecret(tag) then
		return Hash(tag)
	end
end

-- My BattleTag's name ("Me" of "Me#1111"), or nil.
local function MyTag()
	local _, tag = BNGetInfo and BNGetInfo()
	return type(tag) == "string" and not issecret(tag) and tag:match("^[^#]+") or nil
end

---------------------------------------------------------------------------
-- Names: a character is one, whatever named it
---------------------------------------------------------------------------

-- A character in WoW: Forever has a first name and a surname: UnitName gives them apart (the
-- surname as its second return), the game shows them together ("Anna Brook"), and so does
-- Battle.net (characterName: Beacon's peer.name). Journals go by the first name and realm
-- ("Anna-Realm", the key every build sends), Beacon's live news and older builds' days
-- (store.friends, store.friendStats) by the full name. So they're matched here, and every page
-- shows each character once, by its full name: by GUID; else by the full name (from its author:
-- the "a" record, or learned from Battle.net); else by the first name while its journal doesn't
-- know the full one, within their account, if exactly one character fits (and has the same class).
-- A match that isn't unique isn't made: two characters are never taken for one.
--
-- A character whose full name isn't known yet (its journal came from an older build, which only
-- ever sent the first name, and Battle.net hasn't shown it online since; or an alt of mine not
-- played since this build) is shown by its first name with a muted mark, never as if that were all
-- of it (the user: "In forever you have to have two"), and a hover or a line under the list says
-- when the rest comes.

-- "Anna" of "Anna Brook" or "Anna-Realm"; whether a name is "Anna Brook", not "Anna" (Core's LT.Names).
local FirstName, HasSurname = ns.LT.Names.First, ns.LT.Names.HasSurname
C.FirstName, C.HasSurname = FirstName, HasSurname

-- The name a character is shown by: the full name the game shows, once known.
function C.NameOf(c)
	return c.full or c.name
end

-- A record (mine, or a friend's journal's) without the name the game shows: only its first name. (A
-- character keyed by its full name, Chronicle.lua: another of that account's has its first name,
-- carries its surname in the key, also when its "a" record was lost on the way through an older build.)
function C.Partial(c)
	return not c.full and not HasSurname(c.name)
end

-- The mark after a partial name ("" for a whole one); plain: for LTC, where colours don't go.
local MARK = " |cff888888?|r"
function C.Mark(partial, plain)
	return partial and (plain and " (?)" or MARK) or ""
end

-- When a partial name gets its surname, for a hover or the line under a list: mine when I log in on
-- it; a friend's when Battle.net shows it online while I am, or their journal sends it (an up-to-date
-- LefthyTools). account: their BattleTag's name, if known. note: as a line under a list (the mark first).
function C.PartialHint(me, account, note)
	local text
	if me then
		text = L["Surname not known yet: it shows once you log in on the character."]
	elseif account then
		text = L["Surname not known yet: it shows once %s plays the character while you're online, or with an up-to-date LefthyTools."]:format(account)
	else
		text = L["Surname not known yet: it shows once the character is played while you're online, or with an up-to-date LefthyTools."]
	end
	return (note and (MARK:sub(2) .. "  ") or "") .. "|cff888888" .. text .. "|r"
end

-- A friend's account hash as saved (nil: not one, or no longer my friend's).
local function ValidAcct(acct)
	return type(acct) == "string" and acct:match("^%x%x%x%x%x%x%x%x$") and IsFriend(acct) and acct or nil
end

local function ValidGuid(guid)
	return type(guid) == "string" and not issecret(guid) and guid:match("^Player%-%d+%-%x+$") and guid or nil
end
C.ValidGuid = ValidGuid

-- The character in my friends' journals that a full name from Battle.net belongs to: acct (their
-- account; nil: any of my friends', and then only by GUID or full name, unless loose), name, and
-- classFile and guid when known. kept: any journal kept counts (also before the friend list is known,
-- at login). Returns acct, key, the record and how it matched (1 GUID, 2 the full name, 3 the first
-- name), or nil when no single character fits.
local function FindBook(acct, name, classFile, guid, kept, loose)
	if type(name) ~= "string" or name == "" or issecret(name) then
		return nil
	end
	local first, mine, store = FirstName(name), C.MyAccount(), C.Store()
	local best, count, foundAcct, foundKey, found = 4, 0, nil, nil, nil
	for a, account in pairs(store.book) do
		if (not acct or a == acct) and a ~= mine and (kept or IsFriend(a)) then
			for key, c in pairs(account.chars) do
				local tier
				if guid and c.guid then
					tier = c.guid == guid and 1 or nil -- (another GUID: another character, whatever its name)
				elseif classFile and c.classFile and classFile ~= c.classFile then
					tier = nil
				elseif C.NameOf(c) == name then
					tier = 2
				elseif not HasSurname(c.full) and c.name == first and (acct or loose) then
					tier = 3
				end
				if tier and tier < best then
					best, count, foundAcct, foundKey, found = tier, 1, a, key, c
				elseif tier and tier == best then
					count = count + 1
				end
			end
		end
	end
	if count == 1 then
		return foundAcct, foundKey, found, best
	end
end

-- What Battle.net says of a friend's character joins its journal: its GUID, and the name the game
-- shows (also without a surname: then that's all of it). One it knows, its author's or learned, stays,
-- unless this one adds the surname, or the GUID says it's this character, renamed (to a name with a
-- surname: one without never replaces one with). Returns true if it learned something.
local function Learn(c, name, guid, tier)
	local changed = false
	if guid and not c.guid then
		c.guid, changed = guid, true
	end
	if c.full ~= name and FirstName(name) == FirstName(c.name)
		and (not c.full or (HasSurname(name) and (tier == 1 or not HasSurname(c.full)))) then
		c.full, changed = name, true
	end
	if changed then
		NewsChanged() -- (names in the news)
	end
	return changed
end

-- One character a friend is online on (Battle.net's game account info), within their account: its
-- journal's character learns its name and GUID. Called through pcall: a value Battle.net keeps
-- secret can't be compared, and then this one is skipped.
local function MeetGame(acct, game)
	if not (game and game.isOnline and game.clientProgram == (BNET_CLIENT_WOW or "WoW") and game.isInCurrentRegion ~= false
		and game.wowProjectID == WOW_PROJECT_ID) then
		return false
	end
	local name, classFile, guid = game.characterName, game.classFilename, ValidGuid(game.playerGuid)
	if type(name) ~= "string" or name == "" or issecret(name) then
		return false
	end
	classFile = type(classFile) == "string" and not issecret(classFile) and classFile or nil
	local _, _, c, tier = FindBook(acct, name, classFile, guid)
	return c ~= nil and Learn(c, name, guid, tier)
end

-- Battle.net shows the name the game shows (with the surname) of every character a friend is online
-- on, on each of their game accounts, whatever they run (an older LefthyTools, none, Beacon off):
-- the journals I hold of their account learn it. (Beacon's friends teach it too, C.PeerChar, but
-- only those with LefthyTools, and only when a page asks.) Every 30 s on Sync.lua's tick (MEET_GAP):
-- a walk over the friend list, a few calls per friend online.
local function Meet()
	local getAccount, numGames, getGame = C_BattleNet and C_BattleNet.GetFriendAccountInfo,
		C_BattleNet and C_BattleNet.GetFriendNumGameAccounts, C_BattleNet and C_BattleNet.GetFriendGameAccountInfo
	if not (getAccount and numGames and getGame and BNGetNumFriends) then
		return
	end
	local learned, store = false, C.Store()
	for i = 1, BNGetNumFriends() or 0 do
		local ok, info = pcall(getAccount, i)
		local tag = ok and info and info.battleTag
		local acct = type(tag) == "string" and tag ~= "" and not issecret(tag) and Hash(tag)
		if acct and store.book[acct] then
			local okCount, count = pcall(numGames, i)
			count = okCount and type(count) == "number" and not issecret(count) and count or 0
			for j = 1, count do
				local okGame, game = pcall(getGame, i, j)
				local okMeet, met = pcall(MeetGame, acct, okGame and game)
				learned = learned or (okMeet and met)
			end
		end
	end
	if learned then
		C.feedDirty = true -- (the open page: its names)
	end
end
C.Meet = Meet

-- A friend's character for a full name from Battle.net (Beacon's live news, an older build's days):
-- its key among C.Characters() and its journal's record, or "friend:<name>" while no journal has it.
local function LiveChar(name, classFile, acct, guid)
	if type(name) ~= "string" or issecret(name) then
		return "friend:?"
	end
	acct, guid = ValidAcct(acct), ValidGuid(guid)
	local a, key, c, tier = FindBook(acct, name, classFile, guid)
	if c then
		Learn(c, name, guid, tier)
		return "book:" .. a .. ":" .. key, c
	end
	return "friend:" .. name
end

-- A Beacon friend's character (its key among C.Characters()) and their account (nil while
-- Battle.net doesn't say).
function C.PeerChar(peer)
	local acct = C.PeerAccount(peer)
	return LiveChar(peer.name, peer.classFile, acct, peer.guid), acct
end

-- Do an older build's days (sent live) look like the journal's character's? Both come from its
-- author's own numbers: the live one is the day as far as it had gone when sent (they may have
-- played on after), so never more than the journal's day, and on some day both have about the same.
local function SameDays(live, journal)
	local shared, agree = false, false
	for day, x in pairs(type(live) == "table" and live or {}) do
		local y = journal[day]
		if type(x) == "table" and y then
			local more = (x.played or 0) - (y.played or 0)
			if more > 900 then
				return false
			end
			shared, agree = true, agree or more >= -900
		end
	end
	return agree or not shared
end

-- Once (store.identity), for what was saved before characters were matched: older builds' days and
-- the live feed were kept by the full name Battle.net gives ("Anna Brook"), journals by the first
-- name ("Anna-Realm"), so a character showed up twice and its days counted twice. Each finds its
-- journal's character now: its account is noted, and the journal learns the full name. Days saved
-- before their account was noted with them are matched over all the journals kept, only where
-- exactly one character fits (first name, class, and the days both have agree). Nothing is deleted
-- or moved: the pages match the same way from then on.
function C.JoinCharacters()
	local store = C.Store()
	local function Acct(acct) -- (the friend list may not be known yet at login: any account kept)
		return type(acct) == "string" and acct:match("^%x%x%x%x%x%x%x%x$") and store.book[acct] and acct or nil
	end
	for name, f in pairs(store.friendStats) do
		local acct, guid = Acct(f.acct), ValidGuid(f.guid)
		local a, _, c, tier = FindBook(acct, name, f.classFile, guid, true, true)
		if c and (acct or tier < 3 or SameDays(f.days, c.days)) then
			Learn(c, name, guid, tier)
			f.acct = a
		end
	end
	-- (the feed's entries without their account: by the full names the days above taught the journals)
	for _, f in ipairs(store.friends) do
		local a, _, c, tier = FindBook(Acct(f.acct), f.name, f.classFile, nil, true)
		if c then
			Learn(c, f.name, nil, tier)
			f.acct = a
		end
	end
end

---------------------------------------------------------------------------
-- Characters, accounts and news (for the window, the recap and sharing)
---------------------------------------------------------------------------

local function Oldest()
	return date("%Y-%m-%d", C.DayAgo(DAYS))
end

-- When a friend's character last played: its profile says (stamped while they play); without one,
-- the last day it played (its morning: "noon" would read as later than it was).
local function LastPlayed(last, days)
	last = last or 0
	if last == 0 then
		for day, b in pairs(days) do
			if (b.played or 0) > 0 then
				local y, mo, d = day:match("^(%d+)-(%d+)-(%d+)$")
				last = math.max(last, time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 0 }))
			end
		end
	end
	return math.min(last, time())
end

-- Every character, once: mine (store.chars), my friends' from their journals (the book; with the days
-- their older builds sent live, store.friendStats, where the journal has none), and characters only
-- known from such days. Each: { key, name (the full name the game shows), partial (only the first
-- name is known: shown marked), realm, classFile, level, me, current (the one I play), online,
-- accountOnline (one of its account's characters is), last, days, profile, foe, zone, acct, account
-- (its BattleTag's name), news, legacy }. Mine first (the one I play first), then my friends', by
-- name. Graphs, leaderboards and lists go by these: a character is never also shown as part of
-- another row.
function C.Characters()
	local list, current, store = {}, C.Char(), C.Store()
	local myAcct, myTag = C.MyAccount(), MyTag()
	for key, c in pairs(store.chars) do
		C.Fill(c)
		list[#list + 1] = { key = "me:" .. key, name = C.NameOf(c), partial = C.Partial(c), realm = c.realm, classFile = c.classFile,
			level = c.level, me = true, current = c == current, online = c == current, accountOnline = true,
			last = c == current and time() or (c.session and c.session.last) or 0, days = c.daily, profile = C.ProfileNumbers(c),
			foe = C.Top(c.killers), zone = C.Top(c.zoneTime), acct = myAcct, account = myTag }
	end
	-- Who's online: Beacon's friends, by their character's key (and their account).
	local online, onlineAccounts = {}, {}
	for _, peer in pairs(ns.Beacon and ns.Beacon.peers or {}) do
		if peer.name then
			local key, acct = C.PeerChar(peer)
			online[key] = true
			if acct then
				onlineAccounts[acct] = true
			end
		end
	end
	-- Older builds' days: their character's journal (its own days come first), else a character of their own.
	local liveDays, loose = {}, {}
	for name, f in pairs(store.friendStats) do
		local key = LiveChar(name, f.classFile, f.acct, f.guid)
		if key:find("^book:") then
			liveDays[key] = liveDays[key] or {}
			table.insert(liveDays[key], f)
		else
			loose[#loose + 1] = { key = key, name = name, f = f }
		end
	end
	for acct, account in pairs(store.book) do
		if acct ~= myAcct and IsFriend(acct) then
			for bookKey, c in pairs(account.chars) do
				local key = "book:" .. acct .. ":" .. bookKey
				local extra = liveDays[key]
				if c.name and (c.profile or next(c.days) or next(c.news) or extra) then
					local days, last, level = c.days, c.last, c.level
					if extra then
						days = {}
						for _, f in ipairs(extra) do
							for day, b in pairs(type(f.days) == "table" and f.days or {}) do
								days[day] = b
							end
							last, level = math.max(last or 0, f.updated or 0), math.max(level or 0, f.level or 0)
						end
						for day, b in pairs(c.days) do
							days[day] = b
						end
					end
					list[#list + 1] = { key = key, name = C.NameOf(c), partial = C.Partial(c), realm = c.realm, classFile = c.classFile,
						level = level, online = online[key] or false, accountOnline = onlineAccounts[acct] or false, last = LastPlayed(last, days),
						days = days, profile = c.profile, foe = c.foe, zone = c.zone, acct = acct, account = C.AccountLabel(acct),
						news = c.news }
				end
			end
		end
	end
	for _, item in ipairs(loose) do
		local f, acct = item.f, ValidAcct(item.f.acct)
		list[#list + 1] = { key = item.key, name = item.name, partial = false, classFile = f.classFile, level = f.level,
			online = online[item.key] or false, accountOnline = (acct and onlineAccounts[acct]) or online[item.key] or false,
			last = f.updated or 0, days = type(f.days) == "table" and f.days or {}, legacy = true, acct = acct,
			account = acct and C.AccountLabel(acct) }
	end
	table.sort(list, function(a, b)
		if (a.me or false) ~= (b.me or false) then
			return a.me == true
		elseif (a.current or false) ~= (b.current or false) then
			return a.current == true
		elseif a.name ~= b.name then
			return (a.name or "") < (b.name or "")
		end
		return a.key < b.key
	end)
	return list
end

-- The same characters per Battle.net account: me (all my characters), then each friend's account
-- (all its characters, also those only known from the days they sent, when Battle.net told their
-- BattleTag), then characters whose account isn't known (one each). For the window's dropdown (one
-- entry per account) and a friend's graphs. An account goes by its own name: "You", a friend's
-- BattleTag's name (only a lone character whose account isn't known goes by its name), never by
-- one of its characters'. Activity adds up over its characters (time, XP, quests, kills, deaths,
-- distance, AFK, jumps); level is that of the character played most that day, gold the sum of every
-- character's last known gold. chars: the one played most in the last 30 days first (mine: the one
-- I play), whose class colour, foe and zone the account takes.
local ADDITIVE = { "played", "xp", "quests", "kills", "deaths", "levels", "afk", "dist", "bosses", "rares", "runs", "jumps" }
local SUMMED = { played = true, sessions = true, quests = true, kills = true, deaths = true, runs = true, bosses = true,
	rares = true, dist = true, jumps = true, afk = true, loot4 = true, levels = true, xp = true }
local LOWEST = { fastest = true }

local function Combine(account)
	local chars = account.chars
	local oldest = Oldest()
	-- The main character: the one I play, else the most played in the last 30 days (then the highest level).
	local main, mainPlayed
	for _, c in ipairs(chars) do
		local played = c.current and math.huge or 0
		for day, b in pairs(c.days) do
			if day >= oldest then
				played = played + (b.played or 0)
			end
		end
		c.recent = played
		if not main or played > mainPlayed or (played == mainPlayed and (c.level or 0) > (main.level or 0)) then
			main, mainPlayed = c, played
		end
	end
	table.sort(chars, function(a, b)
		if a.recent ~= b.recent then
			return a.recent > b.recent
		elseif (a.level or 0) ~= (b.level or 0) then
			return (a.level or 0) > (b.level or 0)
		end
		return a.key < b.key
	end)
	account.name = account.me and L["You"] or account.account or (main and main.name)
	account.classFile, account.level = main and main.classFile, main and main.level
	account.foe, account.zone = main and main.foe, main and main.zone
	-- Days: added up; level from the day's most played character; gold summed over each one's last.
	local days, dayList = {}, {}
	for _, c in ipairs(chars) do
		for day in pairs(c.days) do
			if day >= oldest and not days[day] then
				days[day] = {}
				dayList[#dayList + 1] = day
			end
		end
	end
	table.sort(dayList)
	local lastGold = {}
	for _, day in ipairs(dayList) do
		local b, most = days[day], -1
		for i, c in ipairs(chars) do
			local cb = c.days[day]
			if cb then
				for _, key in ipairs(ADDITIVE) do
					b[key] = (b[key] or 0) + (cb[key] or 0)
				end
				if cb.level and (cb.played or 0) > most then
					b.level, most = cb.level, cb.played or 0
				end
				if cb.gold then
					lastGold[i] = cb.gold
				end
			end
		end
		local gold, any = 0, false
		for i = 1, #chars do
			if lastGold[i] then
				gold, any = gold + lastGold[i], true
			end
		end
		b.gold = any and gold or nil
	end
	account.days = days
	-- Lifetime: summed where it adds up, the best otherwise (zones, dungeons, most gold, longest session, ...).
	local profile
	for _, c in ipairs(chars) do
		if c.profile then
			profile = profile or {}
			for key, value in pairs(c.profile) do
				local old = profile[key]
				if SUMMED[key] then
					profile[key] = (old or 0) + value
				elseif LOWEST[key] then
					profile[key] = (value > 0 and (not old or old == 0 or value < old)) and value or old
				else
					profile[key] = math.max(old or 0, value)
				end
			end
		end
		account.online = account.online or c.online
		account.last = math.max(account.last or 0, c.last or 0)
	end
	account.profile = profile
	return account
end

function C.Accounts()
	local accounts, mine, byAccount, friends = {}, nil, {}, {}
	for _, c in ipairs(C.Characters()) do
		local key = c.me and "me" or (c.acct and ("acct:" .. c.acct)) or c.key
		local account = byAccount[key]
		if not account then
			account = { key = key, me = c.me, chars = {}, acct = c.acct, account = c.account }
			byAccount[key] = account
			if c.me then
				mine = account
			else
				friends[#friends + 1] = account
			end
		end
		account.chars[#account.chars + 1] = c
	end
	if mine then
		accounts[1] = Combine(mine)
	end
	for _, account in ipairs(friends) do
		Combine(account)
	end
	table.sort(friends, function(a, b) return (a.name or "") < (b.name or "") or (a.name == b.name and a.key < b.key) end)
	for _, account in ipairs(friends) do
		accounts[#accounts + 1] = account
	end
	return accounts
end

-- A death the game reported twice (PLAYER_DEAD again within seconds), from builds that recorded
-- each: the highlights (n -> entry) of a character's that came this soon after the death before.
local function RepeatedDeaths(news)
	local deaths, repeated = {}, {}
	for n, e in pairs(news) do
		if e.k == "death" and type(e.t) == "number" then
			deaths[#deaths + 1] = { n = n, t = e.t }
		end
	end
	table.sort(deaths, function(a, b) return a.t < b.t or (a.t == b.t and a.n < b.n) end)
	local last
	for _, d in ipairs(deaths) do
		if last and d.t - last < C.DEATH_REPEAT then
			repeated[d.n] = true
		else
			last = d.t
		end
	end
	return repeated
end

-- The merged feed, oldest first: friends' synced highlights and what came live (Beacon's events,
-- E2 highlights, online and offline), each once (a live one that a synced one of the same character
-- repeats goes). Each entry: its character's key (among C.Characters()), name (the full one) and
-- partial (only its first name is known).
local merged, mergedFor
function C.FriendNews()
	local store = C.Store()
	local version = newsVersion .. ":" .. #store.friends .. ":" .. tostring(store.friends[#store.friends])
	if mergedFor == version then
		return merged
	end
	local list, synced, live, found = {}, {}, {}, {}
	for i, f in ipairs(store.friends) do -- (first: what they teach the journals shows in the synced ones' names)
		if type(f.name) == "string" and type(f.t) == "number" then
			local id = f.name .. "|" .. tostring(f.acct) .. "|" .. tostring(f.classFile) -- (each character once, not per entry)
			found[id] = found[id] or { LiveChar(f.name, f.classFile, f.acct) }
			live[i] = found[id]
		end
	end
	for acct, a in pairs(store.book) do
		if acct ~= C.MyAccount() and IsFriend(acct) then
			for bookKey, c in pairs(a.chars) do
				local key, name, partial = "book:" .. acct .. ":" .. bookKey, C.NameOf(c), C.Partial(c)
				local repeated = RepeatedDeaths(c.news)
				for n, e in pairs(c.name and c.news or {}) do
					if not repeated[n] then
						local entry = { t = e.t, g = e.g, key = key, name = name, partial = partial, classFile = c.classFile, k = e.k,
							a = e.a, b = e.b, synced = true }
						if e.k == "level" then
							entry.level = tonumber(e.a)
						elseif e.k == "death" then
							entry.foe, entry.where = e.a ~= "" and e.a or nil, e.b
						end
						list[#list + 1] = entry
					end
					local id = key .. "|" .. e.k .. "|" .. (e.a or "")
					synced[id] = synced[id] or {}
					table.insert(synced[id], e.t)
				end
			end
		end
	end
	for i, f in ipairs(store.friends) do
		if live[i] then
			local key, c = live[i][1], live[i][2]
			local a = f.k == "level" and tostring(f.level or "") or f.k == "death" and (f.foe or "") or f.a or ""
			local times = synced[key .. "|" .. (f.k or "") .. "|" .. a]
			local repeated = false
			for _, t in ipairs(times or {}) do
				repeated = repeated or math.abs(t - f.t) < 900
			end
			if not repeated then
				local entry = { key = key, name = c and C.NameOf(c) or f.name, partial = c ~= nil and C.Partial(c),
					classFile = c and c.classFile or f.classFile }
				for field, value in pairs(f) do
					entry[field] = entry[field] or value
				end
				list[#list + 1] = entry
			end
		end
	end
	table.sort(list, function(x, y) return x.t < y.t end)
	merged, mergedFor = list, version
	return list
end

-- News from friends the journal hasn't shown yet (the News page marks them seen).
function C.UnseenCount()
	local store = C.Store()
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
	local store = C.Store()
	if store then
		store.feedSeenAt = time()
		if C.UpdateNewDot then
			C.UpdateNewDot()
		end
	end
end
