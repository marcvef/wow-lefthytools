local _, ns = ...
local LT = ns.LT
local L = ns.L
local C = ns.Chronicle
local M = C.module

-- Professions and known recipes: mine, every friend's, also when they aren't online. Four things:
-- reading Data/Recipes.lua (R.Parse, R.RecipeOf); my scan (which recipes the character I play knows);
-- the sync (friends pass each other's lists on, like journals: per Battle.net account, kept in
-- store.book, only asked for and kept by people who have that account as a friend); and the lists the
-- Professions tab asks for (R.People, R.Search, R.Crafters).
--
-- Saved on the character's record, mine (store.chars) and friends' (store.book[acct].chars) alike:
--   c.trade[line] = { skill, max }      every profession it has (the base line: 165, not 2945)
--   c.tradeU                            its stamp
--   c.recipes[line] = { u, v, of, n, parts = { [k] = text } }
--                                       the list: of parts (k = 1..of), n spells so far, v its version
--                                       (part k's stamp is v + k - 1), u its last stamp (v + of - 1)
--   c.tradeScan, c.tradeDirty           mine: when it was last scanned; a skill changed, not stamped yet
-- store.recipeU is my last stamp, a.recipeU (a = store.book[acct]) how far I hold an account.
--
-- Its own stream, not records in Sync.lua's journals: a holder on an older build would answer "complete
-- up to u" without having any recipes, and a new client would believe it has them all. So it has its
-- own stamps, and goes by Beacon's B family (Protocol.lua), only to builds from RECIPES_SINCE on (their
-- V2; before that build is known, nothing):
--   B2;co;<acct>,<u>/...                what I hold: per account, complete up to u (to a friend when
--                                       it grew, at most every OFFER_GAP; everything after their hello
--                                       and every FULL_OFFER)
--   B2;cq;<acct>;<since>                send me that account's records newer than since
--   B2;ct;<acct>;<char>;<u>;<class>;<level>;<line:skill:max,...>      a character's professions
--   B2;cr;<acct>;<char>;<line>;<v>;<k>;<of>;<text>                    part k of a list
--   B2;ce;<acct>;<u>;<count>            that's all: you're complete up to u, if count records came
-- A request goes to one friend at a time per account. An answer holds at most SERVE_MAX records, oldest
-- first; its end says how far that got, so the rest follows at once. Parts are relayed unchanged.
--
-- <text>: the list's sorted spell IDs, as differences in base 36, comma-separated, the part's first one
-- whole (each part can be read on its own). A new list replaces the old one at its first part; a skill
-- that changes only sends its own small record, at most every SKILL_GAP.
--
-- Nothing heavy in an event: events only note what's wanted, everything happens on Chronicle's tick
-- (once a second, not in a fight, within TICK_MS).

local RECIPES_SINCE = "0.7.0-14-g0000000" -- the first build that reads these (LT.CompareVersions)

local SCAN_STEP = 50     -- recipes looked at a tick at most (and within the tick's budget)
local SCAN_FIRST = 10    -- after entering the world: the game has what it knows by then
local SCAN_SOON = 2      -- after learning something: several at a trainer are one scan
local SCAN_GAP = 60      -- what only might have changed (a skill went up, the window's list) waits this long
local DROP_AFTER = 60    -- no profession at all this soon after a loading screen: not believed yet
local SKILL_GAP = 300    -- a skill that went up is stamped this often at most
local RESTAMP_AFTER = 30 * 86400 -- a played character's stamps older than this are renewed: friends' books drop a character
                         -- after 60 days without news (Sync.lua's BOOK_DAYS), and a list that never changes wouldn't come back
local OFFER_GAP = 60
local FULL_OFFER = 600   -- everything offered again this often (an offer lost on the way)
local PENDING_TIMEOUT = 90
local ASK_AGAIN = 120    -- an account they offered that I'm still short of: asked again this long after
local SERVE_MAX = 300    -- records an answer holds at most
local SERVE_STEP = 50    -- an answer's messages built a tick at most
local SERVES_MAX = 100
local INCOMING_MAX, INCOMING_PER_TICK, TICK_MS = 1000, 100, 1.5
local WEEK = 7 * 86400   -- a stamp can be this far ahead (Sync.lua's Plausible)

-- Sizes. A part's text is at most PART_BYTES: a message is 250 bytes at most with the longest character
-- key (48 bytes). The biggest real list (1278 bytes, all of Leatherworking's 592 recipes) is 9 parts.
local PART_BYTES = 160
local PART_MAX = 200     -- what a friend's part may be
local PARTS_MAX = 30     -- parts a list may have
local RECIPES_MAX = 1500 -- spells a list may have
local SPELL_MAX = 5000000
local LINES_MAX = 12     -- professions a character's record may have

local SEARCH_MAX, SEARCH_MS, ITEM_ASKS = 100, 5, 20 -- results; names fetched a search at most (ms, items asked for)

local R = {}
C.Recipes = R

local issecret = LT.IsSecret

local store
local rev = 0            -- R.Revision

-- The tick's budget.
local function Clock()
	local ok, ms = pcall(debugprofilestop)
	return ok and type(ms) == "number" and ms or nil
end
local tickStart
local function InBudget()
	local at = tickStart and Clock()
	return not (at and at - tickStart >= TICK_MS)
end

local function Changed()
	rev = rev + 1
end
C.RecipesPruned = Changed -- (Sync.lua: characters left the book)

---------------------------------------------------------------------------
-- Data/Recipes.lua
---------------------------------------------------------------------------

local data                                -- ns.RecipeData, once seen
local crafting, lines = {}, {}            -- line -> true: has recipes; every line it knows
local parsed, bySpell, lineOf = {}, {}, {} -- line -> its recipes; spell -> recipe, line (of the lines parsed)
local makers, makersNext, makersWanted    -- R.Makers: item -> what makes it; the next line to scan (nil: done); asked for

local function Data()
	local d = type(ns.RecipeData) == "table" and ns.RecipeData or nil
	if d ~= data then
		data = d
		crafting, lines, parsed, bySpell, lineOf = {}, {}, {}, {}, {}
		makers, makersNext = nil, nil -- (R.Makers: scanned anew)
		for _, line in ipairs(d and d.order or {}) do
			crafting[line], lines[line] = true, true
		end
		for _, line in ipairs(d and d.gathering or {}) do
			lines[line] = true
		end
		Changed()
	end
	return d
end

-- spell:item:count:slot:ilvl:quality:low:high:cat:reagents, reagents being item*n+item*n.
local RECIPE = "^(%d+):(%d*):(%d*):(%d*):(%d*):(%d*):(%d*):(%d*):(%d*):(.*)$"

-- One recipe of the data's text (nil: not one).
local function ReadRecipe(entry)
	local spell, item, count, slot, ilvl, quality, low, high, cat, reagents = entry:match(RECIPE)
	spell = tonumber(spell)
	if not spell then
		return nil
	end
	local recipe = { spell = spell, item = tonumber(item), count = tonumber(count), slot = tonumber(slot), ilvl = tonumber(ilvl),
		quality = tonumber(quality), low = tonumber(low), high = tonumber(high), cat = tonumber(cat), reagents = {} }
	for id, n in reagents:gmatch("(%d+)%*(%d+)") do
		recipe.reagents[#recipe.reagents + 1] = { item = tonumber(id), n = tonumber(n) }
	end
	return recipe
end

function R.Parse(line)
	local d = Data()
	local list = parsed[line]
	if list then
		return list
	end
	list = {}
	parsed[line] = list
	local text = d and d.recipes and d.recipes[line]
	for entry in (type(text) == "string" and text or ""):gmatch("[^;]+") do
		local recipe = ReadRecipe(entry)
		if recipe then
			list[#list + 1] = recipe
			if not bySpell[recipe.spell] then
				bySpell[recipe.spell], lineOf[recipe.spell] = recipe, line
			end
		end
	end
	return list
end

-- A recipe and its line; its line is parsed if that hasn't happened yet (nil: no line has it).
function R.RecipeOf(spell)
	local d = Data()
	if not bySpell[spell] then
		for _, line in ipairs(d and d.order or {}) do
			if not parsed[line] then
				R.Parse(line)
				if bySpell[spell] then
					break
				end
			end
		end
	end
	return bySpell[spell], lineOf[spell]
end

-- What makes an item, for item tooltips: R.Makers(item) = { { spell, line, at }, ... } in the data's
-- order (at: where the recipe begins in its line's text), false when nothing does, nil until it's built.
-- A tooltip can't wait for R.Parse (every line takes several ms), so this only scans the text for
-- ";spell:item:" (reagents hold no ";"), on Chronicle's tick after a tooltip first asked: a line at
-- least, more within the tick's budget, never in a fight. Once per data: the data doesn't change.
local function ScanMakers(line, text)
	for at, spell, item in (";" .. text):gmatch(";()(%d+):(%d+):") do
		item = tonumber(item)
		local list = makers[item]
		if not list then
			list = {}
			makers[item] = list
		end
		list[#list + 1] = { spell = tonumber(spell), line = line, at = at - 1 } -- (at in the text without the ";")
	end
end

local function MakersTick()
	local d = Data()
	if not (makersWanted and d) or (makers and not makersNext) then
		return
	end
	if not makers then
		makers, makersNext = {}, 1
	end
	local order = d.order or {}
	repeat
		local line = order[makersNext]
		local text = line and d.recipes and d.recipes[line]
		if type(text) == "string" then
			ScanMakers(line, text)
		end
		makersNext = makersNext + 1
		if not order[makersNext] then
			makersNext = nil -- (all done)
			return
		end
	until not InBudget()
end

function R.Makers(item)
	Data()
	if not makers or makersNext then
		makersWanted = true
		return nil
	end
	return makers[item] or false
end

-- A maker's recipe as R.Parse has it, read from its own place in the text: its line isn't parsed for it.
function R.MakerRecipe(maker)
	if maker.recipe == nil then
		local text = data and data.recipes and data.recipes[maker.line]
		maker.recipe = bySpell[maker.spell] or (type(text) == "string" and ReadRecipe(text:match("^[^;]+", maker.at) or "")) or false
	end
	return maker.recipe or nil
end

---------------------------------------------------------------------------
-- Lists: sorted spell IDs, as differences in base 36
---------------------------------------------------------------------------

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

local function Base36(n)
	local text = ""
	repeat
		local digit = n % 36
		text = DIGITS:sub(digit + 1, digit + 1) .. text
		n = math.floor(n / 36)
	until n == 0
	return text
end

-- A sorted list of spell IDs as parts of at most PART_BYTES, each starting with a whole ID.
local function Encode(spells)
	local parts, part, bytes, last = {}, {}, 0, 0
	for _, spell in ipairs(spells) do
		local text = Base36(spell - last)
		if bytes + #text + 1 > PART_BYTES + 1 then
			parts[#parts + 1] = table.concat(part, ",")
			part, bytes = {}, 0
			text = Base36(spell)
		end
		part[#part + 1] = text
		bytes, last = bytes + #text + 1, spell
	end
	if part[1] then
		parts[#parts + 1] = table.concat(part, ",")
	end
	return parts
end
R.Encode = Encode

-- How many spells a part has, or nil if it isn't one (only these characters, each number short, always
-- rising, never past SPELL_MAX). into: gets them, [spell] = true.
local function Decode(text, into)
	if type(text) ~= "string" or text == "" or #text > PART_MAX or text:find("[^0-9a-z,]") then
		return nil
	end
	local spell, count = 0, 0
	for piece in (text .. ","):gmatch("([^,]*),") do
		local step = #piece <= 5 and tonumber(piece, 36)
		if not step or step < 1 then
			return nil
		end
		spell, count = spell + step, count + 1
		if spell > SPELL_MAX then
			return nil
		end
		if into then
			into[spell] = true
		end
	end
	return count
end
R.Decode = Decode

---------------------------------------------------------------------------
-- My scan
---------------------------------------------------------------------------

local scan            -- the one under way: { c, lines, i (the line at), pos (in its text), known }
local scanWanted      -- when the next one starts (GetTime); nil: none wanted
local lastScan = -math.huge
local skillsDirty = false -- look at my skills
local lastSkillStamp = -math.huge
local enteredAt = 0   -- the last loading screen's end

-- A new stamp of mine, count of them in a row: now, and always later than the last one.
local function NextU(count)
	local u = math.max(time(), (store.recipeU or 0) + 1)
	store.recipeU = u + (count or 1) - 1
	return u
end

-- Every record of a character stamped anew, so friends who are further ask for them again.
local function Restamp(c)
	if c.trade then
		c.tradeU = NextU()
	end
	for _, r in pairs(c.recipes or {}) do
		r.v = NextU(r.of)
		r.u = r.v + r.of - 1
	end
end

-- A character played again after a long time: friends who dropped it get it again.
local function RenewOld(c)
	local oldest = c.tradeU or math.huge
	for _, r in pairs(c.recipes or {}) do
		oldest = math.min(oldest, r.u)
	end
	if oldest ~= math.huge and time() - oldest > RESTAMP_AFTER then
		Restamp(c)
		Changed()
	end
end

local function Want(at)
	if not scanWanted or at < scanWanted then
		scanWanted = at
	end
end

-- Chronicle.lua's CheckProfessions, on its tick: SKILL_LINES_CHANGED came (or Chronicle started).
function C.RecipesDirty()
	skillsDirty = true
end

local function Whole(v)
	return type(v) == "number" and not issecret(v) and v >= 0 and math.floor(v) or 0
end

-- The base line GetProfessionInfo's line (its 7th return) stands for, a child line (2945) too; if that
-- says nothing, its name (English or German: what names has). nil: not one of the data's.
local function Resolve(line, name)
	if type(line) == "number" and not issecret(line) then
		line = data.parents and data.parents[line] or line
		if lines[line] then
			return line
		end
	end
	if type(name) == "string" and not issecret(name) then
		for known, names in pairs(data.names or {}) do
			if names[1] == name or names[2] == name then
				return known
			end
		end
	end
end

-- The professions the game says I have; the second result is false when one couldn't be told.
local function ReadProfessions()
	local found, whole = {}, true
	for _, index in pairs({ GetProfessions() }) do
		local name, _, skill, max, _, _, line = GetProfessionInfo(index)
		local base = Resolve(line, name)
		if base then
			found[base] = { skill = Whole(skill), max = Whole(max) }
		else
			whole = false
		end
	end
	return found, whole
end

local function StampTrade(c, now)
	c.tradeU, c.tradeDirty = NextU(), nil
	lastSkillStamp = now
end

-- My professions now; their stamp if I got or lost one. Returns whether I did.
local function ReadSkills(c, now)
	if not (GetProfessions and GetProfessionInfo and data) then
		return false
	end
	local found, whole = ReadProfessions()
	c.trade = type(c.trade) == "table" and c.trade or {}
	local set, skills = false, false
	for line, t in pairs(found) do
		local old = c.trade[line]
		if not old then
			set = true
		elseif old.skill ~= t.skill or old.max ~= t.max then
			skills = true
		end
		c.trade[line] = t
	end
	-- Unlearned: it goes, with its list. Not on a read that may be wrong: one the game can't tell yet, or
	-- none at all right after a loading screen (asked again once that's believed).
	if whole and (next(found) or now - enteredAt >= DROP_AFTER) then
		for line in pairs(c.trade) do
			if not found[line] then
				c.trade[line] = nil
				if c.recipes then
					c.recipes[line] = nil
				end
				set = true
			end
		end
	elseif whole and next(c.trade) then
		Want(enteredAt + DROP_AFTER + 1)
	end
	if set then
		StampTrade(c, now)
	elseif skills then
		c.tradeDirty = true -- (stamped on the tick, at most every SKILL_GAP; saved: it may be the last thing this session)
	end
	if set or skills then
		Changed()
	end
	return set
end

-- A line's scan is over: its list, stamped anew if it differs from what's saved. Nothing known: the list
-- stays (the game may not be ready; an unlearned profession goes in ReadSkills).
local function FinishLine(c, line, known)
	if not known[1] then
		return
	end
	table.sort(known)
	local parts = Encode(known)
	local old = c.recipes and c.recipes[line]
	local same = old and old.of == #parts
	for k = 1, #parts do
		same = same and old.parts[k] == parts[k]
	end
	if same then
		return
	end
	local v = NextU(#parts)
	c.recipes = c.recipes or {}
	c.recipes[line] = { u = v + #parts - 1, v = v, of = #parts, n = #known, parts = parts }
	Changed()
end

local function StartScan(c, now)
	scanWanted = nil
	local isKnown = C_SpellBook and C_SpellBook.IsSpellKnown
	if not (isKnown and data and data.recipes) then
		return
	end
	ReadSkills(c, now)
	local list = {}
	for _, line in ipairs(data.order or {}) do
		if c.trade and c.trade[line] and type(data.recipes[line]) == "string" then
			list[#list + 1] = line
		end
	end
	scan = { c = c, lines = list, i = 1, pos = 1, known = {} }
end

-- The scan's next recipes: SCAN_STEP at most, within the tick's budget. It walks the data's text itself:
-- nothing is parsed for this, and the rest of a recipe isn't looked at.
local function Scan(now)
	local s, steps = scan, 0
	local isKnown = C_SpellBook.IsSpellKnown
	while steps < SCAN_STEP do
		local line = s.lines[s.i]
		if not line then
			scan, lastScan = nil, now
			s.c.tradeScan = time()
			RenewOld(s.c)
			return
		end
		local text = data.recipes[line]
		local spell = text:match("^(%d+)", s.pos)
		if spell then
			local known = isKnown(tonumber(spell))
			if issecret(known) then
				scan = nil -- (can't be read now: later)
				Want(now + SCAN_GAP)
				return
			end
			if known == true then
				s.known[#s.known + 1] = tonumber(spell)
			end
			local semicolon = text:find(";", s.pos, true)
			s.pos = semicolon and semicolon + 1 or #text + 1
			steps = steps + 1
			if steps % 10 == 0 and not InBudget() then
				return
			end
		else
			FinishLine(s.c, line, s.known)
			s.i, s.pos, s.known = s.i + 1, 1, {}
		end
	end
end

-- What's wanted on this tick: my skills looked at, stamped if due, the scan begun or gone on with.
local function ScanTick(now)
	local c = C.Char()
	if not (c and Data()) then
		return
	end
	if skillsDirty then
		skillsDirty = false
		-- (a new profession at once, if the game is ready; a skill that went up may mean nothing)
		local at = math.max(now, enteredAt + SCAN_FIRST)
		Want(ReadSkills(c, now) and at or math.max(at, lastScan + SCAN_GAP))
	end
	if c.tradeDirty and now - lastSkillStamp >= SKILL_GAP then
		StampTrade(c, now)
	end
	if not scan and scanWanted and now >= scanWanted then
		StartScan(c, now)
	end
	if scan then
		Scan(now)
	end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
	local now = GetTime()
	if event == "PLAYER_ENTERING_WORLD" then
		enteredAt = now
		Want(math.max(now + SCAN_FIRST, lastScan + SCAN_GAP))
	elseif event == "TRADE_SKILL_LIST_UPDATE" then
		Want(math.max(now + SCAN_SOON, lastScan + SCAN_GAP))
	else
		Want(now + SCAN_SOON) -- (learned something)
	end
end)
local EVENTS = { "PLAYER_ENTERING_WORLD", "NEW_RECIPE_LEARNED", "LEARNED_SPELL_IN_SKILL_LINE", "TRADE_SKILL_LIST_UPDATE" }

---------------------------------------------------------------------------
-- Talking to friends
---------------------------------------------------------------------------

local pending = {}     -- acct -> { from, at, got (records come so far), lost }: asked, one friend at a time
local wanted = {}      -- acct -> { id, u, at }: who offered it, how far, when to ask next
local offers = {}      -- gameAccountID -> { at, full, sent = { [acct] = u } }
local serves = {}      -- answers to build on the tick: { id, acct, since }
local answer           -- the one being built: { id, acct, since, held, mine, chars, ci, items, i, count, sent }
local incoming, inHead, inTail = {}, 1, 0 -- friends' messages for the tick: { id, word, more }
local WORDS = { co = true, ct = true, cr = true, ce = true } -- (and cq; words of later builds are left alone)

local function Msg(word, ...)
	return ("B%s;%s;%s"):format(ns.Beacon.VERSION, word, table.concat({ ... }, ";"))
end

local function Beacon()
	local beacon = LT:GetModule("beacon")
	return beacon and beacon.enabled and ns.Beacon or nil
end

-- Does their build read these? Older builds are never sent any (and a build that doesn't say, or the
-- tagged 0.7.0 without a commit count, counts as older).
local function ReadsRecipes(peer)
	if not (peer and peer.version) then
		return false
	end
	if peer.recipesBuild ~= peer.version then
		peer.recipesBuild = peer.version
		peer.readsRecipes = (LT.CompareVersions(peer.version, RECIPES_SINCE) or -1) >= 0
	end
	return peer.readsRecipes
end

-- A setting that says mine go out: its own, and Chronicle's overall one.
local function Sharing()
	return M.db.share and M.db.shareRecipes
end

-- How far I hold an account (0: not at all; friends' only while they're still my friends).
local function Held(acct)
	if acct == C.MyAccount() then
		return Sharing() and store.recipeU or 0
	end
	local a = store.book[acct]
	return a and M.db.relay and C.IsFriend(acct) and a.recipeU or 0
end

-- A friend said hello (Beacon.lua's Answer): they (re)started, so everything is offered again.
function ns.Beacon.RecipesAnswer(id)
	offers[id] = nil
end

-- What I hold, to one friend whose build reads it: only what grew since they last heard it (everything
-- the first time, and every FULL_OFFER), at most every OFFER_GAP. Their own account left out.
local function SendOffer(id, peer, now)
	local s = offers[id]
	if not s then
		s = { at = -math.huge, full = now, sent = {} }
		offers[id] = s
	end
	if now - s.at < OFFER_GAP then
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
		if acct ~= mine then
			Offer(acct)
		end
	end
	if not items[1] then
		return
	end
	s.at = now
	for first = 1, #items, 10 do
		ns.Beacon.QueueLow(id, Msg("co", table.concat(items, "/", first, math.min(first + 9, #items))))
	end
end

-- Accounts friends offered that I'm short of: one request each, to one friend at a time.
local function Ask(now)
	local B = ns.Beacon
	for acct, w in pairs(wanted) do
		local a = store.book[acct]
		local peer = B.peers[w.id]
		if not peer or w.u <= (a and a.recipeU or 0) or not C.FriendAccounts()[acct] then
			wanted[acct] = nil
		elseif not pending[acct] and now >= w.at and ReadsRecipes(peer) then
			w.at = now + ASK_AGAIN
			pending[acct] = { from = w.id, at = now, got = 0 }
			B.QueueLow(w.id, Msg("cq", acct, a and a.recipeU or 0))
		end
	end
end

local function TradeText(c)
	local list = {}
	for line in pairs(c.trade or {}) do
		list[#list + 1] = line
	end
	table.sort(list)
	for i, line in ipairs(list) do
		local t = c.trade[line]
		list[i] = line .. ":" .. (t.skill or 0) .. ":" .. (t.max or 0)
	end
	return table.concat(list, ",")
end

-- An answer's records are listed first, without their messages ({ u, character's key, record, line, k }):
-- a character's newer than since (mine: only up to held, my last stamp when the answer began).
local function ListChar(a, key, c)
	local function Add(u, line, k)
		if u > a.since and (not a.mine or u <= a.held) then
			a.items[#a.items + 1] = { u, key, c, line, k }
		end
	end
	if c.tradeU then
		Add(c.tradeU)
	end
	for line, r in pairs(c.recipes or {}) do
		for k in pairs(r.parts) do
			Add(r.v + k - 1, line, k)
		end
	end
end

local function StartAnswer(id, acct, since)
	local B = ns.Beacon
	B.DropLowFor(id, function(message) -- (asked again: it goes once)
		return message:match("^B%d+;c[rte];(%x+);") == acct
	end)
	local held = Held(acct)
	if held == 0 then
		B.QueueLow(id, Msg("ce", acct, since, 0)) -- (nothing for them: they ask someone else)
		return
	end
	answer = { id = id, acct = acct, since = since, held = held, mine = acct == C.MyAccount(), chars = {}, ci = 1, items = {}, i = 1, sent = 0 }
	if answer.mine then
		for _, c in ipairs(C.MyChars()) do
			answer.chars[#answer.chars + 1] = { C.CharKey(c), c }
		end
	else
		for key, c in pairs(store.book[acct] and store.book[acct].chars or {}) do
			answer.chars[#answer.chars + 1] = { key, c }
		end
	end
end

-- One step of the answer being built; false once the tick's budget is spent.
local function AnswerStep()
	local B, a = ns.Beacon, answer
	local char = a.chars[a.ci]
	if char then
		a.ci = a.ci + 1
		ListChar(a, char[1], char[2])
		return InBudget()
	end
	local items = a.items
	if not a.count then
		table.sort(items, function(x, y) return x[1] < y[1] end)
		local count = math.min(#items, SERVE_MAX)
		while items[count + 1] and items[count + 1][1] == items[count][1] do
			count = count + 1
		end
		a.count = count
		return InBudget()
	end
	local built = 0
	while a.i <= a.count do
		local item = items[a.i]
		local u, key, c, line, k = item[1], item[2], item[3], item[4], item[5]
		if line then
			local r = c.recipes and c.recipes[line]
			if r and r.parts[k] then -- (a list replaced meanwhile: what's there now; its stamps come next round)
				B.QueueLow(a.id, Msg("cr", a.acct, key, line, r.v, k, r.of, r.parts[k]))
				a.sent = a.sent + 1
			end
		else
			B.QueueLow(a.id, Msg("ct", a.acct, key, u, c.classFile or "", c.level or 0, TradeText(c)))
			a.sent = a.sent + 1
		end
		a.i, built = a.i + 1, built + 1
		if built >= SERVE_STEP or not InBudget() then
			return false
		end
	end
	B.QueueLow(a.id, Msg("ce", a.acct, #items > a.count and items[a.count][1] or a.held, a.sent))
	answer = nil
	return InBudget()
end

-- Friends' requests, answered within the tick's budget, in the order asked.
local function Answers()
	local B = ns.Beacon
	if answer and not B.peers[answer.id] then
		answer = nil -- (they went)
	end
	local first = true -- (one step at least: merging may have spent the budget)
	while first or InBudget() do
		first = false
		if not answer then
			local serve = table.remove(serves, 1)
			if not serve then
				return
			end
			if ReadsRecipes(B.peers[serve.id]) then
				StartAnswer(serve.id, serve.acct, serve.since)
			end
		elseif not AnswerStep() then
			return
		end
	end
end

-- A small number in a message: digits only.
local function Small(text)
	return text and text:match("^%d%d?%d?%d?$") and tonumber(text) or nil
end

-- A stamp in a message, if it can be real.
local function Stamp(text)
	local u = text and #text <= 10 and text:match("^%d+$") and tonumber(text)
	return u and C.Plausible(u) and u or nil
end

-- line:skill:max,... as { [line] = { skill, max } }, or nil if it isn't that. Lines I don't know are left
-- out, for a build with newer data.
local function ParseTrade(text)
	local trade, count = {}, 0
	if text == "" then
		return trade
	end
	for piece in (text .. ","):gmatch("([^,]*),") do
		local line, skill, max = piece:match("^(%d%d?%d?%d?):(%d%d?%d?%d?):(%d%d?%d?%d?)$")
		count = count + 1
		if not line or count > LINES_MAX then
			return nil
		end
		if lines[tonumber(line)] then
			trade[tonumber(line)] = { skill = tonumber(skill), max = tonumber(max) }
		end
	end
	return trade
end

-- A character's professions from a friend. A list whose profession has gone (by a newer stamp) goes.
local function StoreTrade(acct, f)
	if #f ~= 6 then
		return
	end
	local key, u, class, level, trade = f[2], Stamp(f[3]), f[4], f[5], ParseTrade(f[6])
	if not u or not trade or not C.ValidKey(key) or #class > 20 or not class:match("^%u*$") or not level:match("^%d%d?%d?$") then
		return
	end
	local a = store.book[acct]
	local c = a and a.chars[key]
	if c and u <= (c.tradeU or 0) then
		return
	end
	if not c and not next(trade) then
		return -- (nothing to keep a new character for)
	end
	local new = not c
	c = c or C.Book(acct, key)
	c.trade, c.tradeU = trade, u
	c.classFile = c.classFile or (class ~= "" and class or nil)
	c.level = tonumber(level) > 0 and math.max(c.level or 0, tonumber(level)) or c.level -- (0: a holder didn't know it)
	for line, r in pairs(c.recipes or {}) do
		if not trade[line] and r.u < u then
			c.recipes[line] = nil
		end
	end
	if new then
		C.CapBook(store.book[acct])
	end
	Changed()
end

-- A part of a list from a friend. A newer version replaces the list, an older one is ignored, and a
-- part I have of this version is the same one.
local function StorePart(acct, f)
	if #f ~= 7 then
		return
	end
	local key, line, v, k, of, text = f[2], Small(f[3]), Stamp(f[4]), Small(f[5]), Small(f[6]), f[7]
	if not (line and crafting[line] and v and k and of) or not C.ValidKey(key) then
		return
	end
	if k < 1 or k > of or of > PARTS_MAX or not C.Plausible(v + of - 1) then
		return
	end
	local count = Decode(text)
	if not count then
		return
	end
	local a = store.book[acct]
	local c = a and a.chars[key]
	local r = c and c.recipes and c.recipes[line]
	if (r and (v < r.v or (v == r.v and (of ~= r.of or r.parts[k])))) then
		return
	end
	-- (an older list of a profession they've dropped since, on its way through a holder)
	if c and c.tradeU and c.trade and not c.trade[line] and v < c.tradeU then
		return
	end
	if (r and v == r.v and r.n or 0) + count > RECIPES_MAX then
		return
	end
	local new = not c
	c = c or C.Book(acct, key)
	c.recipes = type(c.recipes) == "table" and c.recipes or {}
	if not r or v > r.v then
		r = { u = v + of - 1, v = v, of = of, n = 0, parts = {} }
		c.recipes[line] = r
	end
	r.parts[k], r.n = text, r.n + count
	if new then
		C.CapBook(store.book[acct])
	end
	Changed()
end

-- A friend's message, on the tick.
local function Handle(id, word, more, now)
	local mine = C.MyAccount()
	if word == "co" then
		for piece in more:gmatch("[^/]+") do
			local acct, text = piece:match("^(%x%x%x%x%x%x%x%x),(%d+)$")
			local u = Stamp(text)
			if u and acct ~= mine and C.FriendAccounts()[acct] then
				local a, w = store.book[acct], wanted[acct]
				if u > (a and a.recipeU or 0) and (not w or u >= w.u) then
					wanted[acct] = { id = id, u = u, at = w and w.at or now } -- (the latest who has that much)
				end
			end
		end
	elseif word == "ce" then
		local acct, text, count = more:match("^(%x%x%x%x%x%x%x%x);(%d+);(%d+)$")
		local p = acct and pending[acct]
		if p and p.from == id then
			pending[acct] = nil
			-- Fewer records came than were sent (lost on the way, or not kept: too many waited): not
			-- complete, asked again later.
			if p.lost or p.got < tonumber(count) then
				return
			end
			local a, u, w = store.book[acct], Stamp(text), wanted[acct]
			local before = a and a.recipeU or 0
			if u and u > before and acct ~= mine and C.FriendAccounts()[acct] then
				if not a then
					a = { u = 0, chars = {} }
					store.book[acct] = a
				end
				a.recipeU = u
				if w then
					w.at = now -- (an answer cut short: the rest at once)
				end
			else
				wanted[acct] = nil -- (they have no more than I do, whatever they offered)
			end
		end
	else
		local f = {}
		for field in (more .. ";"):gmatch("([^;]*);") do
			f[#f + 1] = field
		end
		local acct = f[1]
		if not (acct and acct:match("^%x%x%x%x%x%x%x%x$")) then
			return
		end
		local p = pending[acct]
		if p and p.from == id then
			p.at, p.got = now, p.got + 1
		end
		if acct ~= mine and C.FriendAccounts()[acct] then
			if word == "ct" then
				StoreTrade(acct, f)
			else
				StorePart(acct, f)
			end
		end
	end
end

-- The friends' messages waiting, merged by the tick: at most INCOMING_PER_TICK, within the budget (one at least).
local function Incoming(now)
	local handled = 0
	while inHead <= inTail and handled < INCOMING_PER_TICK do
		local item = incoming[inHead]
		incoming[inHead] = nil
		inHead, handled = inHead + 1, handled + 1
		local ok, err = pcall(Handle, item[1], item[2], item[3], now)
		if not ok then
			geterrorhandler()(err) -- (reported; the next one is merged as ever)
		end
		if not InBudget() then
			break
		end
	end
	if inHead > inTail then
		inHead, inTail = 1, 0
	end
end

-- Beacon.lua hands every B2;c... here (after its own guard), inside the event: only noted here.
function ns.Beacon.ReceiveRecipes(id, word, more)
	if not (M.enabled and store and ns.Beacon.peers[id]) then
		return
	end
	if word == "cq" then
		local acct, since = more:match("^(%x%x%x%x%x%x%x%x);(%d%d?%d?%d?%d?%d?%d?%d?%d?%d?)$")
		if acct then
			for i = #serves, 1, -1 do -- (asked again before it was answered: once)
				if serves[i].id == id and serves[i].acct == acct then
					table.remove(serves, i)
				end
			end
			if answer and answer.id == id and answer.acct == acct then
				answer = nil -- (the one being built too: it starts anew, from what they asked now)
			end
			if #serves < SERVES_MAX then
				serves[#serves + 1] = { id = id, acct = acct, since = tonumber(since) }
			end
		end
		return
	elseif not WORDS[word] then
		return
	end
	local acct = word ~= "co" and more:match("^(%x%x%x%x%x%x%x%x);")
	local p = acct and pending[acct]
	if p and p.from ~= id then
		p = nil
	end
	if inTail - inHead + 1 >= INCOMING_MAX then
		if p then
			p.lost = true -- (its end doesn't complete the account: asked again)
		end
		return
	end
	if p then
		p.at = GetTime()
	end
	inTail = inTail + 1
	incoming[inTail] = { id, word, more }
end

---------------------------------------------------------------------------
-- The tick (Chronicle.lua's, once a second) and switching on and off
---------------------------------------------------------------------------

local function Forget()
	wipe(pending)
	wipe(wanted)
	wipe(offers)
	wipe(serves)
	answer = nil
	wipe(incoming)
	inHead, inTail = 1, 0
end

function C.RecipesTick(now)
	if not store or LT.InFight() then
		return -- (what's due is done on the first tick after a fight; low-priority messages wait there too)
	end
	tickStart = Clock()
	ScanTick(now)
	Incoming(now)
	MakersTick()
	local B = Beacon()
	if not B then
		if next(offers) or next(pending) or next(wanted) or serves[1] or answer then
			Forget() -- (Beacon switched off)
		end
		return
	end
	if inHead > inTail then -- (only once everything that came is merged: each record is progress)
		for acct, p in pairs(pending) do
			if now - p.at >= PENDING_TIMEOUT or not B.peers[p.from] then
				pending[acct] = nil
			end
		end
	end
	Answers()
	Ask(now)
	for id in pairs(offers) do
		if not B.peers[id] then
			offers[id] = nil -- (gone)
		end
	end
	for id, peer in pairs(B.peers) do
		if ReadsRecipes(peer) then
			SendOffer(id, peer, now)
		end
	end
end

-- A record saved earlier that can't be read, or with a stamp that can't be real, goes: asked again.
local function Tidy(c, limit)
	if type(c.trade) ~= "table" or type(c.tradeU) ~= "number" or c.tradeU > limit then
		c.trade, c.tradeU = nil, nil
	end
	if type(c.recipes) ~= "table" then
		c.recipes = nil
		return
	end
	for line, r in pairs(c.recipes) do
		if type(r) ~= "table" or type(r.parts) ~= "table" or type(r.v) ~= "number" or type(r.of) ~= "number" or type(r.u) ~= "number"
			or type(r.n) ~= "number" or r.v > limit then
			c.recipes[line] = nil
		end
	end
end

function C.RecipesEnable()
	store = C.Store()
	local limit = time() + WEEK
	for _, a in pairs(store.book) do
		for _, c in pairs(a.chars) do
			Tidy(c, limit)
		end
		if type(a.recipeU) ~= "number" or a.recipeU > limit then
			a.recipeU = nil -- (an impossible stamp would block the account for good)
		end
	end
	-- My last stamp from a clock that was more than a week ahead once: everything of mine anew.
	local fromTheFuture = type(store.recipeU) == "number" and store.recipeU > limit
	if type(store.recipeU) ~= "number" or fromTheFuture then
		store.recipeU = nil
	end
	for _, c in pairs(store.chars) do
		if fromTheFuture then
			c.tradeU = c.trade and 0
		end
		Tidy(c, math.huge)
		if fromTheFuture then
			Restamp(c)
		end
	end
	if store.recipeAlts == nil then
		store.recipeAlts = M.db.shareAlts
	end
	-- Only the character I play is shared, and it's another one than last time: its records are stamped
	-- anew, or friends (further than its old stamps) would never ask for them.
	local current = C.CurrentKey()
	if not M.db.shareAlts and store.recipeChar and store.recipeChar ~= current and C.Char() then
		Restamp(C.Char())
	end
	store.recipeChar = current
	Forget()
	local now = GetTime()
	scan, skillsDirty = nil, true
	scanWanted, enteredAt, lastScan, lastSkillStamp = now + SCAN_FIRST, now, -math.huge, -math.huge
	for _, event in ipairs(EVENTS) do
		pcall(events.RegisterEvent, events, event)
	end
	Changed()
end

function C.RecipesDisable()
	events:UnregisterAllEvents()
	scan, scanWanted = nil, nil
	Forget()
end

-- A setting changed: friends hear again what I hold (all my characters, when that was switched on).
-- Switched off: what of mine still waits to go doesn't.
function C.RecipesSettingChanged()
	if not store then
		return
	end
	if M.db.shareAlts ~= store.recipeAlts then
		store.recipeAlts = M.db.shareAlts
		for _, c in pairs(store.chars) do
			Restamp(c)
		end
	end
	if answer and answer.mine then
		answer = nil -- (what it shares may have changed; they ask again)
	end
	local B, mine = Beacon(), C.MyAccount()
	if B and mine and not Sharing() then
		for id in pairs(B.peers) do
			B.DropLowFor(id, function(message)
				return message:match("^B%d+;c[rte];(%x+);") == mine
			end)
		end
	end
	wipe(offers)
end

---------------------------------------------------------------------------
-- For the Professions tab. Built when asked, and kept until R.Revision moves.
---------------------------------------------------------------------------

local cacheRev
local peopleOf = {}     -- line -> R.People's list
local professions       -- R.Professions' list
local heldList          -- every recipe someone knows: { recipe, line, people }
local spellNames, itemNames, itemsAsked = {}, {}, {} -- lowercased, once the client has them

local function Fresh()
	Data()
	if cacheRev ~= rev then
		cacheRev = rev
		wipe(peopleOf)
		professions, heldList = nil, nil
	end
end

-- The number that goes up whenever a list changed (mine or a friend's), so the tab redraws only then.
function R.Revision()
	Data()
	return rev
end

-- Every character I know of: mine, and my friends' (those still my friends).
local function EachChar(visit)
	if not store then
		return
	end
	for key, c in pairs(store.chars) do
		visit("me:" .. key, c, L["you"], true)
	end
	local mine = C.MyAccount()
	for acct, a in pairs(store.book) do
		if acct ~= mine and C.IsFriend(acct) then
			local label = C.AccountLabel(acct) or ""
			for key, c in pairs(a.chars) do
				if c.name then
					visit("book:" .. acct .. ":" .. key, c, label, false)
				end
			end
		end
	end
end

function R.Professions()
	Fresh()
	if professions then
		return professions
	end
	local counts = {}
	EachChar(function(_, c)
		for line in pairs(c.trade or {}) do
			counts[line] = (counts[line] or 0) + 1
		end
	end)
	professions = {}
	local function Add(list, gathering)
		for _, line in ipairs(list or {}) do
			local names = data.names and data.names[line]
			professions[#professions + 1] = { line = line, name = names and names[ns.LOCALE == "deDE" and 2 or 1] or tostring(line),
				icon = data.icons and data.icons[line], count = counts[line] or 0, gathering = gathering }
		end
	end
	if data then
		Add(data.order, false)
		Add(data.gathering, true)
	end
	return professions
end

-- A list's spells, [spell] = true, and whether a part is missing: read once, until more of it comes.
local decoded = setmetatable({}, { __mode = "k" }) -- list -> { v, n, known, missing }
local function KnownOf(r)
	local d = decoded[r]
	if not d or d.v ~= r.v or d.n ~= r.n then
		d = { v = r.v, n = r.n, known = {}, missing = false }
		for k = 1, r.of do
			if r.parts[k] then
				Decode(r.parts[k], d.known)
			else
				d.missing = true
			end
		end
		decoded[r] = d
	end
	return d.known, d.missing
end

-- Best skill first; ties by their BattleTag's name, then by level.
local function Better(x, y)
	if x.skill ~= y.skill then
		return x.skill > y.skill
	end
	local a, b = x.account:lower(), y.account:lower()
	if a ~= b then
		return a < b
	end
	if (x.level or 0) ~= (y.level or 0) then
		return (x.level or 0) > (y.level or 0)
	end
	return x.id < y.id
end

function R.People(line)
	Fresh()
	local list = peopleOf[line]
	if list then
		for _, person in ipairs(list) do -- (a surname learned since: no list changed)
			person.name, person.partial = C.NameOf(person.record), C.Partial(person.record)
		end
		return list
	end
	list = {}
	peopleOf[line] = list
	EachChar(function(id, c, account, mine)
		local t, r = c.trade and c.trade[line], c.recipes and c.recipes[line]
		if t or r then
			local known, missing = {}, false
			if r and crafting[line] then
				known, missing = KnownOf(r)
			end
			local updated = mine and c.tradeScan or math.max(r and r.u or 0, c.tradeU or 0)
			list[#list + 1] = { id = id, name = C.NameOf(c), classFile = c.classFile, level = c.level, account = account, mine = mine,
				skill = t and t.skill or 0, max = t and t.max or 0, known = known, updated = math.min(updated, time()),
				partial = C.Partial(c), incomplete = missing, record = c }
		end
	end)
	table.sort(list, Better)
	return list
end

function R.Crafters(spell)
	local list = {}
	local _, line = R.RecipeOf(spell)
	for _, person in ipairs(line and R.People(line) or {}) do
		if person.known[spell] then
			list[#list + 1] = person
		end
	end
	return list
end

-- Every recipe someone knows, with who (in R.People's order), built once per revision.
local function HeldList()
	if heldList then
		return heldList
	end
	heldList = {}
	for _, line in ipairs(data and data.order or {}) do
		local people = R.People(line)
		if people[1] then
			for _, recipe in ipairs(R.Parse(line)) do
				local who
				for _, person in ipairs(people) do
					if person.known[recipe.spell] then
						who = who or {}
						who[#who + 1] = person
					end
				end
				if who then
					heldList[#heldList + 1] = { recipe = recipe, line = line, people = who }
				end
			end
		end
	end
	return heldList
end

-- For comparing: lowercase, and the capital umlauts string.lower leaves alone.
local function Fold(text)
	return (text:gsub("Ä", "ä"):gsub("Ö", "ö"):gsub("Ü", "ü"):lower())
end

local function SpellName(spell)
	local get = C_Spell and C_Spell.GetSpellName
	local name
	if get then
		name = get(spell)
	else
		local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spell)
		name = info and info.name
	end
	return type(name) == "string" and not issecret(name) and Fold(name) or nil
end

-- An item's name if the client has it; if not, asked for, once each, a few a search at most (it's there
-- for a later search). asks: how many this search may still ask for; returns the name and that number.
local function ItemName(item, asks)
	local isCached = C_Item and C_Item.IsItemDataCachedByID
	if isCached and not isCached(item) then
		if asks > 0 and not itemsAsked[item] and C_Item.RequestLoadItemDataByID then
			itemsAsked[item] = true
			C_Item.RequestLoadItemDataByID(item)
			asks = asks - 1
		end
		return nil, asks
	end
	local name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(("item:%d"):format(item))
	return type(name) == "string" and not issecret(name) and Fold(name) or nil, asks
end

-- Recipes someone knows by what the client has loaded of their names, the spell's or the item's. Names
-- are kept once fetched; a search fetches them for SEARCH_MS at most, the next one goes on from there.
-- People whose character or BattleTag name holds text, by BattleTag, then level: { { who, professions =
-- { { line, name, icon, skill, max, count, gathering }, ... } }, ... }, in the professions' order. At
-- most SEARCH_MAX. It only asks what the lists hold already: nothing to wait for.
function R.SearchPeople(text)
	local needle = type(text) == "string" and Fold(strtrim(text)) or ""
	if needle == "" then
		return {}
	end
	local found, byId = {}, {}
	for _, prof in ipairs(R.Professions()) do
		for _, who in ipairs(R.People(prof.line)) do
			local entry = byId[who.id]
			if not entry and (Fold(who.name or ""):find(needle, 1, true) or Fold(who.account or ""):find(needle, 1, true)) then
				entry = { who = who, professions = {} }
				byId[who.id] = entry
				found[#found + 1] = entry
			end
			if entry then
				local count = 0
				for _ in pairs(who.known or {}) do
					count = count + 1
				end
				entry.professions[#entry.professions + 1] = { line = prof.line, name = prof.name, icon = prof.icon,
					skill = who.skill, max = who.max, count = count, gathering = prof.gathering }
			end
		end
	end
	table.sort(found, function(x, y)
		local a, b = x.who.account or "", y.who.account or ""
		if a ~= b then
			return a < b
		elseif (x.who.level or 0) ~= (y.who.level or 0) then
			return (x.who.level or 0) > (y.who.level or 0)
		end
		return x.who.id < y.who.id
	end)
	for i = #found, SEARCH_MAX + 1, -1 do
		found[i] = nil
	end
	return found
end

function R.Search(text)
	Fresh()
	local needle = type(text) == "string" and Fold(strtrim(text)) or ""
	if needle == "" then
		return {}
	end
	local found, asks = {}, ITEM_ASKS
	local started = Clock()
	for _, entry in ipairs(HeldList()) do
		local recipe = entry.recipe
		local spell, item = recipe.spell, recipe.item
		local fetching = not started or Clock() - started < SEARCH_MS
		if fetching and not spellNames[spell] then
			spellNames[spell] = SpellName(spell)
		end
		if fetching and item and not itemNames[item] then
			itemNames[item], asks = ItemName(item, asks)
		end
		local spellName, itemName = spellNames[spell], item and itemNames[item]
		if (spellName and spellName:find(needle, 1, true)) or (itemName and itemName:find(needle, 1, true)) then
			found[#found + 1] = { recipe = recipe, line = entry.line, people = entry.people, sortName = spellName or itemName }
		end
	end
	table.sort(found, function(x, y)
		if x.sortName ~= y.sortName then
			return x.sortName < y.sortName
		end
		return x.recipe.spell < y.recipe.spell
	end)
	for i = #found, SEARCH_MAX + 1, -1 do
		found[i] = nil
	end
	return found
end
