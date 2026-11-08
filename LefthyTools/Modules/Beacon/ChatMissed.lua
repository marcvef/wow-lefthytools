local _, ns = ...
local LT = ns.LT
local M = LT:GetModule("beacon")
local B = ns.Beacon

-- LTC's missed lines: a friend who wasn't online when lines were written gets them when they come
-- online, marked as missed, with the time they were written (Chat.lua shows them). Setting
-- lefthyChatMissed; only between builds from Chat.lua's LTC_SINCE on (B.ReadsLTC).
--
-- Who keeps them: whoever wrote the line, and every friend who got it live (so a line reaches a
-- friend who comes online after its writer went offline), each for their own friends with LefthyTools
-- who aren't online right now. Those are the friends seen on such a build in the last FRIEND_DAYS
-- (LefthyToolsDB.ltcFriends, by account: their BattleTag's hash, LT.Hash32 of it in lower case, as
-- Chronicle's) who are still my Battle.net friends. The last KEEP seconds (24 hours), at most
-- PER_FRIEND lines per friend (the oldest go first), MAX_LINES in all: LefthyToolsDB.ltcHeld,
-- account-wide, so another of my characters passes on what this one kept.
--
-- Passing them on, when such a friend is online (on the tick, every LOOK_EVERY seconds):
--   B2;bo;<account>/<account>/...   whose lines I keep for you (their writers, up to MAX_AUTHORS)
--   B2;bq;<account>/...             the ones I take: only my Battle.net friends' (nobody gets lines from
--                                   someone who isn't their friend), never my own; with LTC or missed
--                                   lines off nothing is answered, and the lines stay for later
--   B2;bm;<account>;<time>;<class>;<name>;<text>
--                                   one line: its writer's account, when it was written (server
--                                   time), their class and name, the text as LTC sends it (cut to fit
--                                   255 bytes), oldest first, one every PACE seconds
-- A line is forgotten for that friend once it went. A friend on an older build gets none of these.
--
-- The same line kept by two friends (its writer and a relay, two relays): shown once. A line is known
-- by its writer's account and the first 100 bytes of its text, and by its time: copies less than SAME
-- seconds apart are the same line (the holders' times differ by the way there). LefthyToolsDB.ltcSeen
-- keeps what was shown (lines that came live too) for SEEN_KEEP seconds. So the same words from the same
-- friend twice within SAME seconds show once if both were missed.

local KEEP = 24 * 3600      -- lines older than this aren't passed on
local SEEN_KEEP = 25 * 3600 -- what was shown, kept for spotting a copy
local FRIEND_DAYS = 30 * 86400 -- a friend not seen this long gets nothing kept
local PER_FRIEND, MAX_LINES = 50, 300
local MAX_AUTHORS = 20      -- writers in one offer (9 bytes each)
local PACE = 0.5            -- one line every this many seconds to a friend (they take 80 a minute)
local SAME = 30             -- two copies of a line this close in time are one
local LOOK_EVERY = 2        -- friends online looked at (whom to offer lines)
local PRUNE_EVERY = 60
local FRIENDS_CACHE = 30    -- my Battle.net friends' accounts, read again after this long
local MAX_SEEN = 2000

---------------------------------------------------------------------------
-- Accounts: mine, my Battle.net friends', a Beacon friend's
---------------------------------------------------------------------------

local function Usable(v)
	return LT.Readable(v) and type(v) == "string" and v ~= ""
end

local function Hash(tag)
	return LT.Hash32(tag:lower())
end

local myAcct
local function MyAccount()
	if not myAcct and BNGetInfo then
		local ok, _, tag = pcall(BNGetInfo)
		if ok and Usable(tag) then
			myAcct = Hash(tag)
		end
	end
	return myAcct
end

local friendAccts, friendsAt = {}, -math.huge
-- My Battle.net friends' accounts, online or not.
local function Friends()
	local now = GetTime()
	if now - friendsAt >= FRIENDS_CACHE then
		friendsAt = now
		wipe(friendAccts)
		local bn = C_BattleNet
		for i = 1, (bn and bn.GetFriendAccountInfo and BNGetNumFriends and BNGetNumFriends() or 0) do
			local info = bn.GetFriendAccountInfo(i)
			local tag = type(info) == "table" and info.battleTag
			if Usable(tag) then
				friendAccts[Hash(tag)] = true
			end
		end
	end
	return friendAccts
end

-- One of my Battle.net friends' (while the list can't be read: assumed so).
local function IsFriend(acct)
	local friends = Friends()
	return next(friends) == nil or friends[acct] == true
end

-- A Beacon friend's account, nil while Battle.net doesn't say (kept on the peer for its GUID).
local function PeerAccount(peer)
	local guid = peer and peer.guid
	if not Usable(guid) then
		return nil
	end
	if peer.ltcGuid ~= guid then
		local info = C_BattleNet and C_BattleNet.GetAccountInfoByGUID and LT.Value(C_BattleNet.GetAccountInfoByGUID, guid)
		local tag = type(info) == "table" and info.battleTag
		if not Usable(tag) then
			return nil
		end
		peer.ltcGuid, peer.ltcAcct = guid, Hash(tag)
	end
	return peer.ltcAcct
end

---------------------------------------------------------------------------
-- What's kept (LefthyToolsDB: ltcHeld, ltcFriends, ltcSeen)
---------------------------------------------------------------------------

local function Saved(key)
	local db = LT.db
	if not db then
		return {}
	end
	if type(db[key]) ~= "table" then
		db[key] = {}
	end
	return db[key]
end

local function Now()
	return GetServerTime and GetServerTime() or time()
end

local function On()
	return M.enabled and M.db.lefthyChat and M.db.lefthyChatMissed
end

-- A line as ltcHeld keeps it: { a = writer's account, n = name, c = class, t = written, x = text,
-- f = { [account] = true: still to pass on to them } }. Anything else (a hand-edited file) goes.
local function Valid(line)
	return type(line) == "table" and type(line.a) == "string" and line.a:find("^%x%x%x%x%x%x%x%x$") ~= nil
		and type(line.t) == "number" and type(line.x) == "string" and type(line.f) == "table"
end

local function Key(acct, text)
	return acct .. LT.Hash32(text:sub(1, 100))
end

local function Seen(key, t)
	local list = Saved("ltcSeen")[key]
	for _, at in ipairs(type(list) == "table" and list or {}) do
		if type(at) == "number" and math.abs(at - t) < SAME then
			return true
		end
	end
	return false
end

local function Saw(key, t)
	local seen = Saved("ltcSeen")
	local list = type(seen[key]) == "table" and seen[key] or {}
	seen[key] = list
	list[#list + 1] = t
	if #list > 4 then
		table.remove(list, 1)
	end
end

-- Each friend in accts keeps at most PER_FRIEND lines (the newest), MAX_LINES in all.
local function Trim(held, accts)
	local counts = {}
	for i = #held, 1, -1 do
		local f = held[i].f
		for acct in pairs(accts) do
			if f[acct] then
				counts[acct] = (counts[acct] or 0) + 1
				if counts[acct] > PER_FRIEND then
					f[acct] = nil
				end
			end
		end
		if not next(f) then
			table.remove(held, i)
		end
	end
	while #held > MAX_LINES do
		table.remove(held, 1)
	end
end

-- A line to keep for my friends with LefthyTools who aren't online now (not for its writer or me).
local function Hold(acct, name, classFile, t, text)
	if not (On() and acct and text ~= "") then
		return
	end
	local present = {}
	for _, peer in pairs(B.peers) do
		local a = PeerAccount(peer)
		if a then
			present[a] = true
		end
	end
	local mine, now, accts = MyAccount(), Now(), nil
	for friend, seenAt in pairs(Saved("ltcFriends")) do
		if type(seenAt) == "number" and now - seenAt <= FRIEND_DAYS and friend ~= acct and friend ~= mine
			and not present[friend] and IsFriend(friend) then
			accts = accts or {}
			accts[friend] = true
		end
	end
	if not accts then
		return
	end
	local held = Saved("ltcHeld")
	held[#held + 1] = { a = acct, n = B.Clean(name or "", 48), c = type(classFile) == "string" and classFile:match("^%u+$") or nil,
		t = t, x = text, f = accts }
	Trim(held, accts)
end

-- My own line, as it went to friends on my build (Chat.lua; a call's text too).
function B.LTCHold(text)
	local _, classFile = UnitClass("player")
	Hold(MyAccount(), B.MyName(), classFile, Now(), text)
end

-- A friend's line that came live (cleaned): seen (a copy that comes later as missed isn't shown),
-- and kept for my friends who aren't online now.
function B.LTCHeard(peer, text)
	local acct = PeerAccount(peer)
	if not acct or text == "" then
		return
	end
	local t = Now()
	Saw(Key(acct, text), t)
	Hold(acct, peer.name, peer.classFile, t, text)
end

-- Lines too old, friends not seen for long, what was shown long ago: gone. Broken entries too.
local function Prune()
	if not LT.db then
		return
	end
	local now = Now()
	local held = Saved("ltcHeld")
	for i = #held, 1, -1 do
		local line = held[i]
		if not Valid(line) or now - line.t > KEEP or not next(line.f) then
			table.remove(held, i)
		end
	end
	local known = Saved("ltcFriends")
	for acct, seenAt in pairs(known) do
		if type(seenAt) ~= "number" or now - seenAt > FRIEND_DAYS then
			known[acct] = nil
		end
	end
	local seen, count = Saved("ltcSeen"), 0
	for key, list in pairs(seen) do
		local newest = type(list) == "table" and list[#list]
		if type(newest) ~= "number" or now - newest > SEEN_KEEP then
			seen[key] = nil
		else
			count = count + 1
		end
	end
	if count > MAX_SEEN then
		for key, list in pairs(seen) do
			if now - list[#list] > 3600 then
				seen[key] = nil -- (a flood of lines: the older ones go first)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Passing them on
---------------------------------------------------------------------------

local sending = {} -- gameAccountID -> { peer, acct, take = { [writer] = true }, nextAt }: lines going to them

local function Message(line)
	local head = ("B%s;bm;%s;%d;%s;%s;"):format(B.VERSION, line.a, math.floor(line.t), line.c or "", line.n or "")
	local text = line.x
	if #head + #text > 255 then
		text = (LT.CutUTF8(text, 255 - #head):gsub("{%a+:[^}]*$", "")) -- (a link cut in half goes)
	end
	return head .. text
end

-- Whose lines I keep for a friend (writers, oldest line first): the offer. Returns who's in it.
local function Offer(id, acct)
	local writers, list = {}, {}
	local now = Now()
	for _, line in ipairs(Saved("ltcHeld")) do
		if Valid(line) and line.f[acct] and now - line.t <= KEEP and not writers[line.a] and #list < MAX_AUTHORS then
			writers[line.a] = true
			list[#list + 1] = line.a
		end
	end
	if list[1] then
		B.Queue(id, "B" .. B.VERSION .. ";bo;" .. table.concat(list, "/"))
	end
	return writers
end

-- Friends online on a build that reads these: known from now on, and offered what I keep for them
-- (once per time they come online: a new peer).
local function Look()
	if not On() then
		return
	end
	local mine, now = MyAccount(), Now()
	for id, peer in pairs(B.peers) do
		if peer.name and B.ReadsLTC(peer) then
			local acct = PeerAccount(peer)
			if acct and acct ~= mine then
				Saved("ltcFriends")[acct] = now
				if not peer.ltcOffered then
					peer.ltcOffered = Offer(id, acct) -- (whose: an answer is only taken for them)
				end
			end
		end
	end
end

-- The next line for a friend: the oldest still to go to them, of a writer they take.
local function NextFor(s)
	local now = Now()
	for _, line in ipairs(Saved("ltcHeld")) do
		if Valid(line) and line.f[s.acct] and s.take[line.a] and now - line.t <= KEEP then
			return line
		end
	end
end

local function Deliver(now)
	for id, s in pairs(sending) do
		if B.peers[id] ~= s.peer or not On() then
			sending[id] = nil -- (gone, or switched off: what's left stays for next time)
		elseif now >= s.nextAt then
			local line = NextFor(s)
			if line then
				line.f[s.acct] = nil
				B.Queue(id, Message(line))
				s.nextAt = now + PACE
			else
				sending[id] = nil
			end
		end
	end
end

local lastLook, lastPrune = -math.huge, -math.huge
function B.TickMissed(now)
	if now - lastPrune >= PRUNE_EVERY then
		lastPrune = now
		Prune()
	end
	if now - lastLook >= LOOK_EVERY then
		lastLook = now
		Look()
	end
	if next(sending) then
		Deliver(now)
	end
end

-- "a/b/c" -> { a, b, c }, writers' accounts; nil if it isn't that.
local function Accounts(text)
	if not text:find("^[%x/]*$") then
		return nil
	end
	local list = {}
	for acct in text:gmatch("[^/]+") do
		if not acct:find("^%x%x%x%x%x%x%x%x$") then
			return nil
		end
		list[#list + 1] = acct
	end
	return list
end

local function ReceiveLine(rest)
	local acct, t, classFile, name, text = rest:match("^(%x%x%x%x%x%x%x%x);(%d+);(%u*);([^;]*);([^;]+)$")
	t = tonumber(t)
	local now = Now()
	if not t or t < now - KEEP - 600 or t > now + 600 or acct == MyAccount() or not IsFriend(acct) then
		return
	end
	text = B.Clean(text, B.LTC_TEXT_BYTES)
	local key = Key(acct, text)
	if text == "" or Seen(key, t) then
		return -- (another friend brought it already, or it came live)
	end
	Saw(key, t)
	name = B.Clean(name, 48)
	B.LTCShowFriend(name ~= "" and name or "?", classFile ~= "" and classFile or nil, text, { missed = t })
end

-- From Chat.lua (B.ReceiveLTC): an offer, its answer, a line.
function B.ReceiveMissed(peer, id, word, rest)
	if not On() then
		return -- (nothing answered: what friends keep for me stays for later)
	end
	if word == "bo" then
		local writers = Accounts(rest)
		if not writers then
			return
		end
		local take, mine = {}, MyAccount()
		for _, acct in ipairs(writers) do
			if acct ~= mine and IsFriend(acct) then
				take[#take + 1] = acct
			end
		end
		B.Queue(id, "B" .. B.VERSION .. ";bq;" .. table.concat(take, "/"))
	elseif word == "bq" then
		local writers, acct, offered = Accounts(rest), PeerAccount(peer), peer.ltcOffered
		if not (writers and acct and offered) then
			return
		end
		local take = {}
		for _, writer in ipairs(writers) do
			take[writer] = offered[writer]
		end
		-- Writers offered that they don't take (not their friends) never will be: forgotten for them.
		for _, line in ipairs(Saved("ltcHeld")) do
			if Valid(line) and line.f[acct] and offered[line.a] and not take[line.a] then
				line.f[acct] = nil
			end
		end
		sending[id] = { peer = peer, acct = acct, take = take, nextAt = GetTime() }
	elseif word == "bm" then
		ReceiveLine(rest)
	end
end
