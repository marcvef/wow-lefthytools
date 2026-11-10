local _, ns = ...
local LT = ns.LT
local B = ns.Beacon
local Q = ns.Questtree or {}
ns.Questtree = Q

-- Questtree between friends (docs/questtree.md, "Learning and friends"; the words: docs/beacon.md):
-- friends' progress on the quests I look at, and what everyone's client learned (Questtree/Learn.lua)
-- passed on, so everyone's data fills in. Beacon's B family, Questtree's letter q, only to builds from
-- QUESTTREE_SINCE on (their V2; before it's known, nothing), only while the Questtree module and its
-- `friends` setting are on (both sides). Friends' answers fill Q.friends (Engine.lua's shape, below).
--
--   B2;qp;<req>;<questID>,...          what of these have you done? (the quest I opened and its chain, up to
--                                      IDS_MAX; req 1-999 per session)
--   B2;qs;<req>;<letters>              the answer, a letter per quest in the order asked: d done, r ready to
--                                      turn in, a in the quest log, n none; no letters: not shared
--   B2;qo;<acct>;<epoch>;<seq>         the learned records I hold, up to my store's stamp seq (epoch: my
--                                      store's, made with it; acct: my BattleTag's hash, as Chronicle's)
--   B2;qq;<epoch>;<since>;<acct>       send me yours changed after since (acct: mine; what came from me
--                                      isn't sent back)
--   B2;qr;<questID>;<level>;<giver>;<ender>;<pre>;<not>;<title>
--                                      one record: giver/ender <k><id>:<uiMapID>:<x>:<y>:<name> (k n npc,
--                                      o object, i item; x, y in thousandths; parts empty when unknown),
--                                      pre <questID>[*],... (* weak), not <questID>,... (proven not before it)
--   B2;qe;<epoch>;<upto>;<count>       that's all: you have mine up to upto, if count records came
--
-- Requests go when a window asks (Q.RequestFriendProgress), at most every REQUEST_GAP; a friend's are
-- answered at most every ANSWER_GAP (the latest one). Records go at low priority, a few a second and only
-- while Beacon's queues are nearly empty, an answer at most SERVE_MAX of them; one friend asked at a time.
-- Nothing of it in a fight (LT.InFight): it waits for the end. Event work only notes; Beacon's tick
-- (B.TickQuests) does the rest.

local QUESTTREE_SINCE = "0.7.0-69-g0000000" -- the first build that reads these (LT.CompareVersions)

local VERSION = B.VERSION
local IDS_MAX = 40          -- quests a request asks about at most
local REQUEST_GAP = 2       -- my requests at most this often
local ASK_SAME = 20         -- the same quest asked about again after this long at most
local ANSWER_GAP = 1        -- a friend's requests answered at most this often
local REQUEST_FOR = 60      -- answers to a request taken this long
local PROGRESS_MAX = 400    -- quests kept per friend (more: the oldest answers go)
local OFFER_GROWN = 60      -- what I hold offered again when it grew, at most this often
local OFFER_AGAIN = 600     -- and anyway this often (an offer lost on the way)
local ASK_AGAIN = 30        -- a holder asked again at most this often
local PENDING_TIMEOUT = 120 -- a request for records given up after this long without one
local SERVE_MAX = 100       -- records an answer holds at most
local SEND_STEP = 4         -- records queued a second at most
local SEND_WAITING = 8      -- ... and only while fewer messages than this wait in Beacon's queues
local INCOMING_MAX = 300    -- friends' messages waiting for the tick
local HANDLE_STEP = 25      -- friends' messages handled a tick at most
local SLOW_TICK = 1         -- seconds between the bulk steps (offers, asking, serving)
local GOT_MAX = 50          -- holders whose stamps are kept
local NAME_BYTES, TITLE_BYTES = 32, 48
local MESSAGE_BYTES = 250

local issecret, Value = LT.IsSecret, LT.Value

local requests = {}   -- req -> { ids, at, to = { [gameAccountID] = true } }
local nextReq = 0
local want            -- the ids to ask about next (Q.RequestFriendProgress)
local lastRequestAt = -math.huge
local askedAbout = {} -- questID -> when its friends were asked
local asked = {}      -- gameAccountID -> { req, ids }: a friend's request still to answer (the latest)
local answeredAt = {}
local offers = {}     -- gameAccountID -> { at, seq }: what I told them I hold
local holders = {}    -- gameAccountID -> { acct, epoch, seq, askAt }: what they told me they hold
local pending         -- { id, acct, epoch, at, n }: records asked of one friend
local serves = {}     -- { { id, since } }: friends' requests for my records, in order
local serving         -- { id, list, i, upto, sent }: the answer going out
local incoming, inHead, inTail = {}, 1, 0
local listeners = {}  -- Q.OnFriendProgress
local progressChanged = false
local answeredFor = {} -- the quests (first of each request answered: the one a window shows) since the last redraw
local lastSlow = -math.huge
local myAcct

---------------------------------------------------------------------------
-- Who takes part
---------------------------------------------------------------------------

-- The Questtree module on, with its friends setting (Questtree.lua; nothing while it isn't there).
local function Sharing()
	local m = LT:GetModule("questtree")
	return m ~= nil and m.enabled and type(m.db) == "table" and m.db.friends == true and B.module.enabled
end

-- Does their build read these? Older builds are never sent any (and a build that doesn't say, or one
-- without its commit count, counts as older).
local function Reads(peer)
	if not (peer and peer.version) then
		return false
	end
	if peer.questBuild ~= peer.version then
		peer.questBuild = peer.version
		peer.readsQuests = (LT.CompareVersions(peer.version, QUESTTREE_SINCE) or -1) >= 0
	end
	return peer.readsQuests
end
B.ReadsQuesttree = Reads

local function MyAccount()
	if not myAcct and BNGetInfo then
		local _, battleTag = BNGetInfo()
		if type(battleTag) == "string" and battleTag ~= "" and not issecret(battleTag) then
			myAcct = LT.Hash32(battleTag:lower())
		end
	end
	return myAcct
end

local function Msg(word, ...)
	return ("B%s;%s;%s"):format(VERSION, word, table.concat({ ... }, ";"))
end

---------------------------------------------------------------------------
-- Records on the wire
---------------------------------------------------------------------------

local function Thousandths(v)
	return v and math.floor(v * 1000 + 0.5) or ""
end

local function EncodePlace(w)
	if not w then
		return ""
	end
	local name = Q.LearnText and Q.LearnText(w.n, NAME_BYTES) or ""
	local x, y = "", ""
	if w.m and w.x and w.y then
		x, y = Thousandths(w.x), Thousandths(w.y)
	end
	return w.k .. w.i .. ":" .. (w.m or "") .. ":" .. x .. ":" .. y .. ":" .. (name or "")
end

local function Sorted(set, weak)
	local list = {}
	for id in pairs(set or {}) do
		list[#list + 1] = id
	end
	table.sort(list)
	if weak then
		for i, id in ipairs(list) do
			list[i] = set[id] == 1 and (id .. "*") or tostring(id)
		end
	end
	return table.concat(list, ",")
end

-- A record as B2;qr (at most MESSAGE_BYTES: the title is cut to fit).
local function Encode(id, rec)
	local head = Msg("qr", id, rec.l or "", EncodePlace(rec.s), EncodePlace(rec.e), Sorted(rec.p, true), Sorted(rec.x), "")
	local title = Q.LearnText and Q.LearnText(rec.t, TITLE_BYTES) or ""
	local room = MESSAGE_BYTES - #head
	if not title or room < 1 then
		return head
	end
	return head .. (#title > room and LT.CutUTF8(title, room) or title)
end
Q.EncodeLearned = Encode

local function Count(text, max)
	local n = text and tonumber(text)
	return n and #text <= max and n > 0 and n or nil
end

-- A place, or nil; second: whether the text was one (empty is).
local function DecodePlace(text)
	if text == "" then
		return nil, true
	end
	local k, i, mt, x, y, n = text:match("^([noi])(%d+):(%d*):(%d*):(%d*):([^:,]*)$")
	i = Count(i, 9)
	local m = mt and mt ~= "" and Count(mt, 6) or nil
	if not (k and i) or (mt ~= "" and not m) then
		return nil, false
	end
	local px, py = tonumber(x), tonumber(y)
	if (px == nil) ~= (py == nil) or (px and (not m or #x > 4 or #y > 4 or px > 1000 or py > 1000)) or #n > 40 then
		return nil, false
	end
	-- (the name cleaned as mine are: no escape sequences, separators or control characters)
	return { k = k, i = i, m = m, x = px and px / 1000, y = py and py / 1000, n = Q.LearnText and Q.LearnText(n, NAME_BYTES) }, true
end

local function DecodeSet(text, max, weak)
	if text == "" then
		return nil, true
	end
	local set, n = {}, 0
	for piece in (text .. ","):gmatch("([^,]*),") do
		local id, mark = piece:match("^(%d+)(%*?)$")
		id = Count(id, 9)
		n = n + 1
		if not id or n > max or (mark ~= "" and not weak) then
			return nil, false
		end
		set[id] = weak and (mark == "*" and 1 or 2) or true
	end
	return set, true
end

-- The fields after "qr;", as Learn.lua's record, or nil.
local function Decode(more)
	local id, level, s, e, p, x, title = more:match("^(%d+);(%d*);([^;]*);([^;]*);([^;]*);([^;]*);([^;]*)$")
	id = Count(id, 9)
	if not id or #level > 3 or #title > TITLE_BYTES + 20 then
		return nil
	end
	local giver, ok1 = DecodePlace(s)
	local ender, ok2 = DecodePlace(e)
	local pre, ok3 = DecodeSet(p, 4, true)
	local no, ok4 = DecodeSet(x, 8, false)
	if not (ok1 and ok2 and ok3 and ok4) then
		return nil
	end
	return id, { s = giver, e = ender, p = pre, x = no, l = level ~= "" and Count(level, 3) or nil,
		t = Q.LearnText and Q.LearnText(title, TITLE_BYTES) }
end
Q.DecodeLearned = Decode

---------------------------------------------------------------------------
-- Friends' progress
---------------------------------------------------------------------------


local function Letter(id)
	if C_QuestLog and Value(C_QuestLog.IsQuestFlaggedCompleted, id) == true then
		return "d"
	end
	local index = C_QuestLog and Value(C_QuestLog.GetLogIndexForQuestID, id)
	if type(index) == "number" and index > 0 then
		return Value(C_QuestLog.IsComplete, id) == true and "r" or "a"
	end
	return "n"
end

-- Ask my friends what they have done of a quest and its chain (the windows call it when a quest is
-- shown). False when there's no one to ask.
function Q.RequestFriendProgress(id)
	if type(id) ~= "number" or not Sharing() then
		return false
	end
	local anyone = false
	for _, peer in pairs(B.peers) do
		if Reads(peer) then
			anyone = true
			break
		end
	end
	if not anyone then
		return false
	end
	local now = GetTime()
	if askedAbout[id] and now - askedAbout[id] < ASK_SAME then
		return true -- (asked a moment ago: the answers are there or on their way)
	end
	local ids, seen = { id }, { [id] = true }
	if Q.Chain then
		local ok, chain = LT.Guard("Q.Chain", Q.Chain, id)
		for _, other in ipairs(ok and type(chain) == "table" and chain or {}) do
			if #ids >= IDS_MAX then
				break
			end
			if type(other) == "number" and not seen[other] then
				ids[#ids + 1], seen[other] = other, true
			end
		end
	end
	askedAbout[id], want = now, ids
	return true
end

-- Friends' progress lives in Q.friends[gameAccountID], the shape Engine.lua reads (its Q.Friends,
-- Q.Status(id, progress), Q.Missing(id, progress)): { done = { [questID] = true }, active = { [questID] =
-- true }, name, classFile, class, level, faction, race, gameAccountID }, plus QuestShare's own ready (in the
-- log and ready to turn in; also in active), known (asked and answered: absent from done and active = none),
-- n, at, shares (false: their friends setting is off). Only friends who answered; dropped when Beacon forgets
-- them. Got anew each call (Engine.lua may make the table itself: it loads later).
local function Friends()
	Q.friends = type(Q.friends) == "table" and Q.friends or {}
	return Q.friends
end

-- One friend's progress table (above), or nil; without an account: Q.friends (every friend who answered).
function Q.FriendProgress(gameAccountID)
	if gameAccountID == nil then
		return Friends()
	end
	return Friends()[gameAccountID]
end

-- One friend's status of a quest: "done", "ready" (in the log, to turn in), "active", "none", or nil (not known).
function Q.FriendStatus(gameAccountID, id)
	local p = Friends()[gameAccountID]
	if not p then
		return nil
	elseif p.done[id] then
		return "done"
	elseif p.ready[id] then
		return "ready"
	elseif p.active[id] then
		return "active"
	end
	return p.known[id] and "none" or nil
end

-- fn() after friends' answers came (on Beacon's tick): the windows redraw.
function Q.OnFriendProgress(fn)
	listeners[#listeners + 1] = fn
end

local function SendRequest(now)
	local ids = want
	want, lastRequestAt = nil, now
	nextReq = nextReq % 999 + 1
	local list, room = {}, MESSAGE_BYTES - #Msg("qp", nextReq, "")
	for _, id in ipairs(ids) do
		local text = tostring(id)
		room = room - #text - 1
		if room < 0 then
			break
		end
		list[#list + 1] = text
	end
	local request = { ids = {}, at = now, to = {} }
	for i, text in ipairs(list) do
		request.ids[i] = tonumber(text)
	end
	local message = Msg("qp", nextReq, table.concat(list, ","))
	for id, peer in pairs(B.peers) do
		if Reads(peer) then
			request.to[id] = true
			B.Queue(id, message)
		end
	end
	if next(request.to) then
		requests[nextReq] = request
	end
	for req, r in pairs(requests) do
		if now - r.at > REQUEST_FOR then
			requests[req] = nil
		end
	end
end

local function Answer(id, a, now)
	asked[id], answeredAt[id] = nil, now
	if not Sharing() then
		B.Queue(id, Msg("qs", a.req, "")) -- (not shared: they stop waiting)
		return
	end
	local letters = {}
	for i, quest in ipairs(a.ids) do
		letters[i] = Letter(quest)
	end
	B.Queue(id, Msg("qs", a.req, table.concat(letters)))
end

local function TakeAnswer(id, req, letters, now)
	local r = requests[req]
	if not (r and r.to[id] and now - r.at <= REQUEST_FOR) then
		return
	end
	r.to[id] = nil
	local friends, peer = Friends(), B.peers[id]
	local p = friends[id]
	if not p then
		p = { done = {}, active = {}, ready = {}, known = {}, n = 0 }
		friends[id] = p
	end
	-- Who they are (Engine checks race, class and faction): Beacon's peer, Battle.net for the rest.
	local info = C_BattleNet and Value(C_BattleNet.GetGameAccountInfoByID, id)
	info = type(info) == "table" and info or {}
	p.gameAccountID, p.name, p.classFile, p.class = id, peer.name, peer.classFile, peer.classFile
	p.level = peer.level
	p.faction = type(info.factionName) == "string" and not issecret(info.factionName) and info.factionName or p.faction
	p.race = type(info.raceName) == "string" and not issecret(info.raceName) and info.raceName or p.race
	p.at, p.shares = now, letters ~= ""
	if letters == "" or #letters ~= #r.ids then
		return
	end
	if p.n + #letters > PROGRESS_MAX then
		for _, set in ipairs({ p.done, p.active, p.ready, p.known }) do
			wipe(set) -- (the oldest answers go; what's shown now is asked again)
		end
		p.n = 0
	end
	for i = 1, #letters do
		local quest, letter = r.ids[i], letters:sub(i, i)
		if not p.known[quest] then
			p.n = p.n + 1
		end
		p.known[quest] = true
		p.done[quest] = letter == "d" or nil
		p.active[quest] = (letter == "a" or letter == "r") or nil
		p.ready[quest] = letter == "r" or nil
	end
	answeredFor[r.ids[1]] = true
	progressChanged = true
end

---------------------------------------------------------------------------
-- Learned records
---------------------------------------------------------------------------

local function Meta()
	return Q.LearnedMeta and Q.LearnedMeta() or nil
end

local function Offer(now)
	local meta, acct = Meta(), MyAccount()
	if not (meta and acct and meta.seq > 0) then
		return
	end
	for id, peer in pairs(B.peers) do
		if Reads(peer) then
			local o = offers[id]
			if not o or (meta.seq > o.seq and now - o.at >= OFFER_GROWN) or now - o.at >= OFFER_AGAIN then
				offers[id] = { at = now, seq = meta.seq }
				B.QueueLow(id, Msg("qo", acct, meta.epoch, meta.seq))
			end
		end
	end
end

-- One friend at a time: the holder who has the most I haven't got.
local function Ask(now)
	local meta = Meta()
	if pending then
		if now - pending.at > PENDING_TIMEOUT or not B.peers[pending.id] then
			pending = nil -- (given up: asked again later)
		else
			return
		end
	end
	if not meta then
		return
	end
	for id, h in pairs(holders) do
		local got = meta.got[h.acct]
		local since = got and got.epoch == h.epoch and got.seq or 0
		if not (B.peers[id] and Reads(B.peers[id])) or h.seq <= since or h.acct == MyAccount() then
			holders[id] = nil
		elseif now >= h.askAt then
			h.askAt = now + ASK_AGAIN
			pending = { id = id, acct = h.acct, epoch = h.epoch, at = now, n = 0 }
			B.QueueLow(id, Msg("qq", h.epoch, since, MyAccount() or ""))
			return
		end
	end
end

local function Keep(meta, acct, epoch, upto)
	meta.got[acct] = { epoch = epoch, seq = upto, at = time() }
	local n, oldest, at = 0, nil, nil
	for a, g in pairs(meta.got) do
		n = n + 1
		if not at or (g.at or 0) < at then
			oldest, at = a, g.at or 0
		end
	end
	if n > GOT_MAX then
		meta.got[oldest] = nil
	end
end

local function StartServing(id, since, acct)
	local store, meta = Q.LearnedStore and Q.LearnedStore(), Meta()
	if not (store and meta) then
		return
	end
	local list = {}
	for quest, rec in pairs(store) do
		if rec.u > since then
			list[#list + 1] = { quest, rec.u }
		end
	end
	table.sort(list, function(a, b) return a[2] < b[2] end)
	local upto = meta.seq
	if #list > SERVE_MAX then
		upto = list[SERVE_MAX][2]
		for i = #list, SERVE_MAX + 1, -1 do
			list[i] = nil
		end
	end
	serving = { id = id, list = list, i = 1, upto = upto, sent = 0, epoch = meta.epoch, acct = acct }
end

-- A few of the answer's records a second, while Beacon's queues are nearly empty.
local function Serve()
	if serving and not B.peers[serving.id] then
		serving = nil
	end
	if not serving then
		local s = table.remove(serves, 1)
		if not s then
			return
		end
		StartServing(s.id, s.since, s.acct)
		if not serving then
			return
		end
	end
	local store, a = Q.LearnedStore(), serving
	local queued = 0
	while a.i <= #a.list and queued < SEND_STEP and B.Waiting() < SEND_WAITING do
		local quest = a.list[a.i][1]
		local rec = store[quest]
		a.i = a.i + 1
		if rec and not (a.acct and rec.f == a.acct) then -- (theirs, as they sent it: not sent back)
			B.QueueLow(a.id, Encode(quest, rec))
			a.sent, queued = a.sent + 1, queued + 1
		end
	end
	if a.i > #a.list and B.Waiting() < SEND_WAITING then
		B.QueueLow(a.id, Msg("qe", a.epoch, a.upto, a.sent))
		serving = nil
	end
end

---------------------------------------------------------------------------
-- Friends' messages: noted in the event, handled on the tick
---------------------------------------------------------------------------

local WORDS = { qp = true, qs = true, qo = true, qq = true, qr = true, qe = true } -- (later builds' words: left alone)

local function Handle(id, word, more, now)
	local peer = B.peers[id]
	if not Reads(peer) then
		return
	end
	if word == "qp" then
		local req, list = more:match("^(%d%d?%d?);([%d,]+)$")
		local ids, set = {}, req and DecodeSet(list, IDS_MAX, false)
		if set then
			for quest in list:gmatch("%d+") do
				ids[#ids + 1] = tonumber(quest)
			end
			asked[id] = { req = req, ids = ids }
		end
	elseif word == "qs" then
		local req, letters = more:match("^(%d%d?%d?);([dran]*)$")
		if req then
			TakeAnswer(id, tonumber(req), letters, now)
		end
	elseif not Sharing() then
		return
	elseif word == "qo" then
		local acct, epoch, seq = more:match("^(%x%x%x%x%x%x%x%x);(%x%x%x%x%x%x%x%x);(%d+)$")
		seq = Count(seq, 12)
		if seq then
			local h = holders[id]
			holders[id] = { acct = acct, epoch = epoch, seq = seq, askAt = h and h.askAt or now }
		end
	elseif word == "qq" then
		local epoch, since, acct = more:match("^(%x%x%x%x%x%x%x%x);(%d+);(%x*)$")
		local meta = Meta()
		if epoch and meta and epoch == meta.epoch and #since <= 12 then
			for i = #serves, 1, -1 do
				if serves[i].id == id then
					table.remove(serves, i) -- (asked again: once, from what they asked now)
				end
			end
			if serving and serving.id == id then
				serving = nil
			end
			serves[#serves + 1] = { id = id, since = tonumber(since), acct = #acct == 8 and acct or nil }
		end
	elseif word == "qr" then
		if pending and pending.id == id then
			pending.at, pending.n = now, pending.n + 1
			local quest, rec = Decode(more)
			if quest and Q.MergeLearned then
				Q.MergeLearned(quest, rec, pending.acct)
			end
		end
	elseif word == "qe" then
		local epoch, upto, n = more:match("^(%x%x%x%x%x%x%x%x);(%d+);(%d+)$")
		local meta = Meta()
		if pending and pending.id == id and epoch == pending.epoch and meta and #upto <= 12 then
			local p = pending
			pending = nil
			if not p.lost and p.n >= tonumber(n) then
				Keep(meta, p.acct, epoch, tonumber(upto))
				local h = holders[id]
				if h then
					h.askAt = now -- (an answer cut short: the rest right away)
				end
			end
		end
	end
end

-- Beacon.lua hands every B2;q... here (after its own guard), inside the event: only noted.
function B.ReceiveQuesttree(id, word, more)
	if not (WORDS[word] and B.peers[id]) then
		return
	end
	if inTail - inHead + 1 >= INCOMING_MAX then
		if pending and pending.id == id then
			pending.lost = true -- (its end doesn't count: asked again)
		end
		return
	end
	inTail = inTail + 1
	incoming[inTail] = { id, word, more }
end

local function Incoming(now)
	local handled = 0
	while inHead <= inTail and handled < HANDLE_STEP do
		local item = incoming[inHead]
		incoming[inHead] = nil
		inHead, handled = inHead + 1, handled + 1
		local ok, err = pcall(Handle, item[1], item[2], item[3], now)
		if not ok then
			geterrorhandler()(err)
		end
	end
	if inHead > inTail then
		inHead, inTail = 1, 0
	end
end

---------------------------------------------------------------------------
-- Beacon's tick (10 a second): nothing in a fight
---------------------------------------------------------------------------

function B.TickQuests(now)
	if inHead > inTail and not want and not next(asked) and not serving and not serves[1] and not pending
		and now - lastSlow < SLOW_TICK then
		return
	end
	if LT.InFight() then
		return -- (all of it waits for the fight's end: friends' requests one each, messages up to INCOMING_MAX)
	end
	Incoming(now)
	if want and now - lastRequestAt >= REQUEST_GAP then
		SendRequest(now)
	end
	for id, a in pairs(asked) do
		if not B.peers[id] then
			asked[id] = nil
		elseif now - (answeredAt[id] or -math.huge) >= ANSWER_GAP then
			Answer(id, a, now)
		end
	end
	if progressChanged then
		progressChanged = false
		if Q.RedrawSmall and next(answeredFor) then
			LT.Guard("Q.RedrawSmall", Q.RedrawSmall, now) -- (the small window: a friend's progress on the quest it shows)
		end
		wipe(answeredFor)
		for _, fn in ipairs(listeners) do
			local ok, err = pcall(fn)
			if not ok then
				geterrorhandler()(err)
			end
		end
	end
	if now - lastSlow >= SLOW_TICK then
		lastSlow = now
		if Sharing() then
			Offer(now)
			Ask(now)
			Serve()
		end
	end
end

-- A friend gone (Beacon.lua's Forget).
function B.QuestForget(id)
	Friends()[id] = nil
	asked[id], answeredAt[id], offers[id], holders[id] = nil, nil, nil, nil
	if pending and pending.id == id then
		pending = nil
	end
	for i = #serves, 1, -1 do
		if serves[i].id == id then
			table.remove(serves, i)
		end
	end
	if serving and serving.id == id then
		serving = nil
	end
	progressChanged = true
end

-- Beacon switched off.
function B.QuestStop()
	for _, t in ipairs({ Friends(), requests, askedAbout, asked, answeredAt, offers, holders, serves, incoming, answeredFor }) do
		wipe(t)
	end
	want, pending, serving = nil, nil, nil
	inHead, inTail = 1, 0
	progressChanged = true
end
