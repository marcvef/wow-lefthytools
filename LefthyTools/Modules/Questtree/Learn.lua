local _, ns = ...
local LT = ns.LT
local Q = ns.Questtree or {}
ns.Questtree = Q

-- Questtree's learning while playing (docs/questtree.md, "Learning and friends"): who gives a quest and
-- who takes it back (an NPC, an object or an item, with where I stood), its title and level, and what
-- had to be done before it (inferred). Only while the module's `learn` setting is on, and only for quests
-- the data doesn't know fully (or doesn't know at all: without the data add-on everything is kept).
--
-- Kept account-wide in LefthyToolsDB.questtree.learned[questID] (at most RECORDS_MAX, the oldest changes
-- go first), fed into Q.AddLearned (Data.lua) at login and with every change, and passed on to friends by
-- Beacon's QuestShare.lua (the records' stamps are its sync's):
--   { u = stamp (this store's change counter: LefthyToolsDB.questtree.share.seq),
--     t = title, l = level,
--     s = giver, e = ender: { k = "n" npc | "o" object | "i" item, i = id, n = name, m = uiMapID, x, y (0..1) },
--     p = { [questID] = 2 strong | 1 weak }: done before it (inferred), x = { [questID] = true }: proven not,
--     f = the friend's account (QuestShare.lua) whose record changed it last, nil: mine (not sent back to them) }
--
-- Prerequisites: a quest that an NPC offers now, but didn't the last time I looked at its offers (gossip
-- or greeting, same level), after exactly one turn-in since (or one at that NPC) has that turn-in before
-- it (strong). A quest the game offers right after a turn-in at the same NPC, within FOLLOW_UP seconds,
-- is its follow-up (strong); later, within RECENT, only a hint (weak: shared, never fed as a prerequisite).
-- A quest offered while one of its prerequisites isn't completed (C_QuestLog.IsQuestFlaggedCompleted) proves
-- that one wrong (another character of the account, or a friend's client).
--
-- Never lags, never taints: read-only APIs, no Blizzard frames. The handlers read the dialog (it's gone
-- later) and note it; a frame shown for a frame does the rest.

local RECORDS_MAX = 1500  -- records kept; over it, the oldest changes go (down to PRUNE_TO)
local PRUNE_TO = 1350
local PRE_MAX, NOT_MAX = 4, 8 -- prerequisites and disproved ones a record keeps
local TURNINS_KEEP = 5    -- the last turn-ins remembered (this session)
local NPCS_KEEP = 40      -- NPCs whose last offers are remembered (this session)
local FOLLOW_UP = 3       -- seconds: offered this soon after a turn-in at the same NPC: its follow-up
local RECENT = 60         -- seconds: taken this long after a turn-in at the same NPC: a hint
local DIALOG_FOR = 120    -- seconds a quest dialog's giver or ender counts for its accept or turn-in
local OFFERS_MAX = 25     -- quests read from one gossip or greeting at most
local FEED_STEP = 50      -- records fed to Q.AddLearned a frame at most (at login)
local NAME_BYTES, TITLE_BYTES = 32, 48

local issecret, Value = LT.IsSecret, LT.Value

local saved   -- LefthyToolsDB.questtree
local store   -- saved.learned
local meta    -- saved.share = { seq, epoch, got } (got: QuestShare.lua's)
local count = 0

local notes = {}        -- what the handlers read, for the driver: { kind, ... }
local offered = {}      -- NPC key -> { ids = { [id] = true }, seq, level, full, at }: its offers last seen
local offeredOrder = {} -- the NPC keys, oldest first
local turnins = {}      -- { id, key (ender's NPC key or nil), at, seq }: the last TURNINS_KEEP
local turnSeq = 0       -- turn-ins this session
local dialog = {}       -- "detail" / "complete" -> { id, who, at }: the last quest dialog's
local feedList, feedAt  -- ids still to feed at login, and how far
local fed = false

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

-- The Questtree module's switch and its learn setting (Questtree.lua; nil while that isn't there).
local function Learning()
	local m = LT:GetModule("questtree")
	return store ~= nil and m ~= nil and m.enabled and type(m.db) == "table" and m.db.learn == true
end
Q.Learning = Learning

local function Number(v)
	return type(v) == "number" and not issecret(v) and v > 0 and v == math.floor(v) and v or nil
end

local function Text(v, bytes)
	if type(v) ~= "string" or issecret(v) then
		return nil
	end
	v = strtrim((v:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[|;:,%c]", "")))
	if v == "" then
		return nil
	end
	return #v > bytes and LT.CutUTF8(v, bytes) or v
end
Q.LearnText = Text

local function Round(v)
	return math.floor(v * 1000 + 0.5) / 1000
end

local function PlayerLevel()
	return Value(UnitLevel, "player")
end

-- Whether I completed the quest: true, false, or nil when the game won't say.
local function Completed(id)
	local done = C_QuestLog and Value(C_QuestLog.IsQuestFlaggedCompleted, id)
	if type(done) == "boolean" then
		return done
	end
	return nil
end

-- The data's quest, only once the data is loaded (asking must never load it: that's for the windows).
local function DataQuest(id)
	if not (Q.Quest and Q.IsLoaded and Q.IsLoaded()) then
		return nil
	end
	local ok, q = pcall(Q.Quest, id)
	return ok and type(q) == "table" and q or nil
end

local function HasPoint(list)
	for _, place in ipairs(type(list) == "table" and list or {}) do
		if type(place.points) == "table" and place.points[1] then
			return true
		end
	end
	return false
end

-- Does the data lack this part of a quest (s giver, e ender, p prerequisites, t title, l level)? A quest
-- I have a record of is kept whole (my records are merged into the data's tables, so they can't tell).
local function Needs(id, part)
	if store[id] then
		return true
	end
	local q = DataQuest(id)
	if not q or q.source == "learned" then
		return true
	elseif part == "s" then
		return not HasPoint(q.starts)
	elseif part == "e" then
		return not HasPoint(q.ends)
	elseif part == "p" then
		return q.new == true and not (q.pre or q.preAny) -- (new in WoW: Forever: the data may not know what comes first)
	end
	return false
end

-- Who I'm talking to: { k, i, n, m, x, y }, or nil (a player sharing a quest, a secret, nothing).
local function Where(who)
	local map = C_Map and Number(Value(C_Map.GetBestMapForUnit, "player"))
	if not map then
		return who
	end
	who.m = map
	local pos = Value(C_Map.GetPlayerMapPosition, map, "player")
	if type(pos) == "table" and pos.GetXY then
		local ok, x, y = pcall(pos.GetXY, pos)
		if ok and not issecret(x) and not issecret(y) and type(x) == "number" and type(y) == "number"
			and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
			who.x, who.y = Round(x), Round(y)
		end
	end
	return who
end

local function Npc()
	local guid = Value(UnitGUID, "npc")
	if type(guid) ~= "string" then
		return nil
	end
	local kind, id = "n", LT.CreatureOf(guid)
	if not id then
		kind, id = "o", tonumber(guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-") or "")
	end
	if not Number(id) then
		return nil
	end
	return Where({ k = kind, i = id, n = Text(Value(UnitName, "npc"), NAME_BYTES) })
end

local function Key(who)
	return who and (who.k .. who.i) or nil
end

local function LogLevel(id)
	local index = C_QuestLog and Number(Value(C_QuestLog.GetLogIndexForQuestID, id))
	local info = index and Value(C_QuestLog.GetInfo, index)
	if type(info) == "table" and info.questID == id then
		return Number(info.level)
	end
	return nil
end

local function Title(id)
	return C_QuestLog and Text(Value(C_QuestLog.GetTitleForQuestID, id), TITLE_BYTES)
end

---------------------------------------------------------------------------
-- The store
---------------------------------------------------------------------------

local function Touch(rec)
	meta.seq = meta.seq + 1
	rec.u = meta.seq
end

-- Over RECORDS_MAX: the oldest changes go, down to PRUNE_TO (so it isn't done for every new one).
local function Prune()
	if count <= RECORDS_MAX then
		return
	end
	local list = {}
	for id, rec in pairs(store) do
		list[#list + 1] = { id, rec.u }
	end
	table.sort(list, function(a, b) return a[2] < b[2] end)
	for i = 1, #list - PRUNE_TO do
		store[list[i][1]] = nil
	end
	count = math.min(count, PRUNE_TO)
end

local function Record(id, create)
	local rec = store[id]
	if not rec and create then
		rec = { u = 0 }
		store[id] = rec
		count = count + 1
	end
	return rec
end

local KINDS = { n = "npc", o = "object", i = "item" }

local function Place(w)
	return { kind = KINDS[w.k], id = w.i, name = w.n, points = w.x and { { map = w.m, x = w.x, y = w.y } } or {} }
end

-- The prerequisites fed as such: the strong ones.
local function Strong(rec)
	local list
	for x, strength in pairs(rec.p or {}) do
		if strength >= 2 then
			list = list or {}
			list[#list + 1] = x
		end
	end
	if list then
		table.sort(list)
	end
	return list
end

-- What Q.AddLearned gets for a record (the contract's quest fields).
local function Fields(rec)
	return { title = rec.t, level = rec.l, zone = rec.s and rec.s.k ~= "i" and rec.s.m or nil,
		starts = rec.s and { Place(rec.s) } or nil, ends = rec.e and { Place(rec.e) } or nil, pre = Strong(rec) }
end

local function Feed(id, rec)
	if not Q.AddLearned then
		return
	end
	LT.Guard("Q.AddLearned", Q.AddLearned, id, Fields(rec))
	for x in pairs(rec.p or {}) do
		LT.Guard("Q.AddLearned", Q.AddLearned, x, { opens = { id } }) -- (a weak one too: it leads there)
	end
end

-- (QuestShare.lua offers friends what changed: the store's seq grew.) from: the friend's account it came from.
local function Changed(id, rec, from)
	Touch(rec)
	rec.f = from
	Feed(id, rec)
end

-- A better place: one with a point beats one without; else the first seen stays.
local function Better(old, new)
	if not old then
		return true
	end
	return not old.x and new.x ~= nil
end

-- Learns a giver (s) or ender (e), with the title and level when they're known.
local function Learn(id, part, who, title, level)
	if not who or not Needs(id, part) then
		return
	end
	local rec = Record(id, true)
	local changed = false
	if Better(rec[part], who) then
		rec[part], changed = { k = who.k, i = who.i, n = who.n, m = who.m, x = who.x, y = who.y }, true
	elseif not rec[part].n and who.n and rec[part].k == who.k and rec[part].i == who.i then
		rec[part].n, changed = who.n, true
	end
	if title and not rec.t then
		rec.t, changed = title, true
	end
	if level and not rec.l then
		rec.l, changed = level, true
	end
	if changed then
		Changed(id, rec)
		Prune()
	end
end

-- Keeps the strongest few.
local function Trim(set, max)
	local n = 0
	for _ in pairs(set) do
		n = n + 1
	end
	while n > max do
		local weakest, at
		for k, v in pairs(set) do
			local strength = v == true and 1 or v
			if not weakest or strength < at or (strength == at and k > weakest) then
				weakest, at = k, strength
			end
		end
		set[weakest], n = nil, n - 1
	end
end

-- x was done before id (strength 2 strong, 1 weak).
local function AddPre(id, x, strength)
	if x == id or not Needs(id, "p") then
		return
	end
	local rec = Record(id, true)
	if rec.x and rec.x[x] then
		return
	end
	rec.p = rec.p or {}
	if (rec.p[x] or 0) >= strength then
		return
	end
	rec.p[x] = strength
	Trim(rec.p, PRE_MAX)
	Changed(id, rec)
	Prune()
end

-- id is offered to me: a prerequisite I haven't completed wasn't one.
local function Disprove(id)
	local rec = store[id]
	if not (rec and rec.p) then
		return
	end
	local changed = false
	for x in pairs(rec.p) do
		if Completed(x) == false then
			rec.p[x] = nil
			rec.x = rec.x or {}
			rec.x[x], changed = true, true
		end
	end
	if changed then
		Trim(rec.x, NOT_MAX)
		if not next(rec.p) then
			rec.p = nil
		end
		Changed(id, rec)
	end
end

---------------------------------------------------------------------------
-- Friends' records (QuestShare.lua): merged, only filling gaps
---------------------------------------------------------------------------

local function ValidPlace(w)
	return type(w) == "table" and KINDS[w.k] and Number(w.i) and (w.n == nil or type(w.n) == "string")
		and (w.m == nil or Number(w.m)) and (w.x == nil or (type(w.x) == "number" and type(w.y) == "number"))
end

-- A record from a friend (decoded by QuestShare.lua; from: the account of the friend who sent it). True if
-- it taught me something.
function Q.MergeLearned(id, rec, from)
	if not (store and Number(id) and type(rec) == "table") then
		return false
	end
	local mine = store[id]
	if not mine then
		-- (nothing I'd keep: everything in it the data knows already)
		local useful = (rec.s and Needs(id, "s")) or (rec.e and Needs(id, "e")) or (rec.p and Needs(id, "p"))
		if not useful then
			return false
		end
	end
	mine = Record(id, true)
	local changed = false
	for _, part in ipairs({ "s", "e" }) do
		local w = rec[part]
		if ValidPlace(w) and Better(mine[part], w) then
			mine[part], changed = { k = w.k, i = w.i, n = w.n, m = w.m, x = w.x, y = w.y }, true
		end
	end
	if type(rec.t) == "string" and not mine.t then
		mine.t, changed = rec.t, true
	end
	if Number(rec.l) and not mine.l then
		mine.l, changed = rec.l, true
	end
	for x in pairs(type(rec.x) == "table" and rec.x or {}) do
		if Number(x) and not (mine.x and mine.x[x]) then
			mine.x = mine.x or {}
			mine.x[x], changed = true, true
			if mine.p and mine.p[x] then
				mine.p[x] = nil
			end
		end
	end
	for x, strength in pairs(type(rec.p) == "table" and rec.p or {}) do
		if Number(x) and x ~= id and (strength == 1 or strength == 2) and not (mine.x and mine.x[x])
			and (not mine.p or (mine.p[x] or 0) < strength) then
			mine.p = mine.p or {}
			mine.p[x], changed = strength, true
		end
	end
	if mine.p and not next(mine.p) then
		mine.p = nil
	end
	if mine.p then
		Trim(mine.p, PRE_MAX)
	end
	if mine.x then
		Trim(mine.x, NOT_MAX)
	end
	if mine.u == 0 and not changed then
		store[id], count = nil, count - 1 -- (made for nothing)
		return false
	end
	if changed then
		Changed(id, mine, type(from) == "string" and from or nil)
		Prune()
	end
	return changed
end

-- For QuestShare.lua and the windows.
function Q.LearnedStore()
	return store
end
function Q.LearnedMeta()
	return meta
end
function Q.Learned(id)
	return store and store[id]
end

---------------------------------------------------------------------------
-- What I see: offers, dialogs, accepting and turning in
---------------------------------------------------------------------------

-- The turn-in since seq that explains a new offer at key: the only one at that NPC, else the only one.
local function SinceTurnIn(seq, key)
	local here, any, hereCount, anyCount = nil, nil, 0, 0
	for _, t in ipairs(turnins) do
		if t.seq > seq then
			anyCount, any = anyCount + 1, t.id
			if t.key == key then
				hereCount, here = hereCount + 1, t.id
			end
		end
	end
	if hereCount == 1 then
		return here
	elseif anyCount == 1 then
		return any
	end
	return nil
end

local function Remember(key, entry)
	if not offered[key] then
		offeredOrder[#offeredOrder + 1] = key
		if #offeredOrder > NPCS_KEEP then
			offered[table.remove(offeredOrder, 1)] = nil
		end
	end
	offered[key] = entry
end

-- Quests an NPC offers ({ { id, title, level } }) and has for me to turn in (active). partial: a quest
-- dialog (one quest, not the whole list).
local function Offers(who, available, active, now)
	local key = Key(who)
	if not key then
		return
	end
	local seen = offered[key]
	local level = PlayerLevel()
	local partial = active == nil
	local ids = {}
	for _, q in ipairs(available) do
		local id = q[1]
		ids[id] = true
		Learn(id, "s", who, q[2], q[3])
		Disprove(id)
		if seen and seen.full then
			if not seen.ids[id] and seen.level == level then
				local x = SinceTurnIn(seen.seq, key)
				if x then
					AddPre(id, x, 2)
				end
			end
		elseif partial then
			local last = turnins[#turnins]
			if last and last.key == key and now - last.at <= RECENT then
				AddPre(id, last.id, now - last.at <= FOLLOW_UP and 2 or 1)
			end
		end
	end
	for _, q in ipairs(active or {}) do
		Learn(q[1], "e", who, q[2], q[3])
	end
	if not partial then
		Remember(key, { ids = ids, seq = turnSeq, level = level, full = true, at = now })
	elseif seen then
		for id in pairs(ids) do
			seen.ids[id] = true -- (it's offered now: not news the next time)
		end
	end
end

local function Dialog(which, id, now)
	local d = dialog[which]
	if d and d.id == id and now - d.at <= DIALOG_FOR then
		return d.who
	end
	return nil
end

local function Accept(id, who, now)
	who = Dialog("detail", id, now) or who
	Learn(id, "s", who, Title(id), LogLevel(id))
end

local function TurnIn(id, who, now)
	who = Dialog("complete", id, now) or who
	Learn(id, "e", who, Title(id))
	turnSeq = turnSeq + 1
	turnins[#turnins + 1] = { id = id, key = Key(who), at = now, seq = turnSeq }
	if #turnins > TURNINS_KEEP then
		table.remove(turnins, 1)
	end
end

local function Handle(note, now)
	local kind = note[1]
	if kind == "offers" then
		Offers(note[2], note[3], note[4], now)
	elseif kind == "detail" then
		dialog.detail = { id = note[2], who = note[3], at = now }
		if note[3] then
			Offers(note[3], { { note[2], note[4] } }, nil, now)
		end
	elseif kind == "complete" then
		dialog.complete = { id = note[2], who = note[3], at = now }
	elseif kind == "accept" then
		Accept(note[2], note[3], now)
	elseif kind == "turnin" then
		TurnIn(note[2], note[3], now)
	end
end

---------------------------------------------------------------------------
-- The driver: shown while there's something to do, hidden (costing nothing) otherwise
---------------------------------------------------------------------------

local driver = CreateFrame("Frame")
driver:Hide()

local function FeedStep()
	local m = LT:GetModule("questtree")
	if not (m and m.enabled) or not Q.AddLearned then
		feedList = nil -- (the module off: Q.FeedLearned when it's switched on)
		return
	end
	if LT.InFight() then
		return -- (after the fight)
	end
	local last = math.min(#feedList, feedAt + FEED_STEP - 1)
	for i = feedAt, last do
		local rec = store[feedList[i]]
		if rec then
			Feed(feedList[i], rec)
		end
	end
	feedAt = last + 1
	if feedAt > #feedList then
		feedList, fed = nil, true
	end
end

driver:SetScript("OnUpdate", function(self)
	local now = GetTime()
	local list = notes
	notes = {}
	for _, note in ipairs(list) do
		LT.Guard("Questtree learn", Handle, note, now)
	end
	if feedList then
		LT.Guard("Questtree feed", FeedStep)
	end
	if not notes[1] and not feedList then
		self:Hide()
	end
end)

local function Note(kind, a, b, c, d)
	if #notes < 50 then
		notes[#notes + 1] = { kind, a, b, c, d }
	end
	driver:Show()
end

-- Every record into Q.AddLearned, a few a frame (at login; Questtree.lua may call it when switched on).
function Q.FeedLearned()
	if not store or feedList then
		return
	end
	feedList, feedAt = {}, 1
	for id in pairs(store) do
		feedList[#feedList + 1] = id
	end
	table.sort(feedList)
	driver:Show()
end

---------------------------------------------------------------------------
-- Events: read the dialog now (it's gone later), note it for the driver
---------------------------------------------------------------------------

local function QuestID(v)
	return Number(v)
end

-- { { id, title, level } } from the gossip API's list (C_GossipInfo.GetAvailableQuests / GetActiveQuests).
local function GossipList(f)
	local list = {}
	local infos = Value(f)
	for i, info in ipairs(type(infos) == "table" and infos or {}) do
		if i > OFFERS_MAX then
			break
		end
		local id = type(info) == "table" and QuestID(info.questID)
		if id then
			list[#list + 1] = { id, Text(info.title, TITLE_BYTES), Number(info.questLevel) }
		end
	end
	return list
end

local handlers = {}

function handlers.GOSSIP_SHOW()
	local who = Npc()
	if who and C_GossipInfo then
		Note("offers", who, GossipList(C_GossipInfo.GetAvailableQuests), GossipList(C_GossipInfo.GetActiveQuests))
	end
end

-- The greeting (an NPC with several quests and no gossip): the classic functions.
function handlers.QUEST_GREETING()
	local who = Npc()
	if not who then
		return
	end
	local available, active = {}, {}
	for i = 1, math.min(Number(Value(GetNumAvailableQuests)) or 0, OFFERS_MAX) do
		local ok, _, _, _, _, id = pcall(GetAvailableQuestInfo, i)
		id = ok and QuestID(id)
		if id then
			available[#available + 1] = { id, Text(Value(GetAvailableTitle, i), TITLE_BYTES), Number(Value(GetAvailableLevel, i)) }
		end
	end
	for i = 1, math.min(Number(Value(GetNumActiveQuests)) or 0, OFFERS_MAX) do
		local id = QuestID(Value(GetActiveQuestID, i))
		if id then
			active[#active + 1] = { id, Text(Value(GetActiveTitle, i), TITLE_BYTES), Number(Value(GetActiveLevel, i)) }
		end
	end
	Note("offers", who, available, active)
end

-- The quest's text, before accepting: from an NPC or object, or an item (questStartItemID).
function handlers.QUEST_DETAIL(itemID)
	local id = QuestID(Value(GetQuestID))
	if not id then
		return
	end
	local who
	itemID = Number(itemID)
	if itemID then
		who = Where({ k = "i", i = itemID })
	else
		who = Npc()
	end
	Note("detail", id, who, Text(Value(GetTitleText), TITLE_BYTES) or Title(id))
end

function handlers.QUEST_ACCEPTED(questID)
	local id = QuestID(questID)
	if id then
		Note("accept", id, Npc())
	end
end

function handlers.QUEST_COMPLETE()
	local id = QuestID(Value(GetQuestID))
	if id then
		Note("complete", id, Npc())
	end
end

function handlers.QUEST_TURNED_IN(questID)
	local id = QuestID(questID)
	if id then
		Note("turnin", id, Npc())
	end
end

local events = CreateFrame("Frame")
for event in pairs(handlers) do
	pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, ...)
	if Learning() then
		if not fed and not feedList then
			Q.FeedLearned() -- (switched on since login: what's kept goes in first)
		end
		local ok, err = pcall(handlers[event], ...)
		if not ok then
			geterrorhandler()(err)
		end
	end
end)

---------------------------------------------------------------------------
-- Loading: what's kept, checked; fed in after login
---------------------------------------------------------------------------

local function ValidRecord(id, rec)
	if not (Number(id) and type(rec) == "table" and type(rec.u) == "number") then
		return false
	end
	for _, part in ipairs({ "s", "e" }) do
		if rec[part] ~= nil and not ValidPlace(rec[part]) then
			rec[part] = nil
		end
	end
	if rec.t ~= nil and type(rec.t) ~= "string" then
		rec.t = nil
	end
	if rec.f ~= nil and type(rec.f) ~= "string" then
		rec.f = nil
	end
	if rec.l ~= nil and not Number(rec.l) then
		rec.l = nil
	end
	for _, set in ipairs({ "p", "x" }) do
		if rec[set] ~= nil and type(rec[set]) ~= "table" then
			rec[set] = nil
		end
	end
	return rec.s ~= nil or rec.e ~= nil or rec.p ~= nil
end

table.insert(LT.onLoad, function(db)
	saved = type(db.questtree) == "table" and db.questtree or {}
	db.questtree = saved
	store = type(saved.learned) == "table" and saved.learned or {}
	saved.learned = store
	meta = type(saved.share) == "table" and saved.share or {}
	saved.share = meta
	meta.got = type(meta.got) == "table" and meta.got or {}
	if type(meta.epoch) ~= "string" or not meta.epoch:match("^%x%x%x%x%x%x%x%x$") then
		meta.epoch = ("%08x"):format(math.random(0, 0x7fffffff))
		meta.seq = 0
	end
	meta.seq = type(meta.seq) == "number" and meta.seq >= 0 and math.floor(meta.seq) or 0
	count = 0
	local last, restamp = meta.seq, {}
	for id, rec in pairs(store) do
		if ValidRecord(id, rec) then
			count = count + 1
			if rec.u > last or rec.u < 1 or rec.u ~= math.floor(rec.u) then
				restamp[#restamp + 1] = id -- (a stamp it can't have: it would never be sent, or twice)
			end
		else
			store[id] = nil
		end
	end
	table.sort(restamp)
	for _, id in ipairs(restamp) do
		Touch(store[id])
	end
	Prune()
end)

table.insert(LT.onLogin, function()
	Q.FeedLearned() -- (the first frame after login: the module is switched on by then, or this waits)
end)
