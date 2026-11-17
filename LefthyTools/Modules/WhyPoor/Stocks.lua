local _, ns = ...
local LT = ns.LT
local L = ns.L
local W = ns.WhyPoor or {}
ns.WhyPoor = W

-- The window's Stocks tab (W.Stocks, St): a watch list of items and their price on your auction house over time.
-- The list: the watched items (LefthyToolsWhyPoorDB.watch, account-wide: item IDs in the order added), each with
-- its latest daily low (P.History) and the change since a week ago (else since the oldest day known). A search box
-- on the line above the list, a stock app's ticker search: as you type, up to MAX suggestions in a dropdown under
-- it (icon, the name in its quality colour with the typed part marked, the lowest price, "watched"); Up/Down,
-- Enter or Tab, Escape, a click. A pick selects that item (its details on the right). Typing and waiting (or Enter
-- with nothing marked): the list is every item whose name has it (any case; an item link or "#1234" is that item).
-- A click: the item's price graph (D.Graph) and "Add to watch list" / "Remove from watch list". Informational only.
-- What it costs: nothing until the tab is first shown, nothing while it isn't.
--   * The name index (St.index): built over frames on a frame of its own (St.indexer, BUDGET_MS and
--     INDEX_PER_FRAME a frame, hidden when done) from P.Items(), the bags and the watch list: each name's start
--     and each later word's start as sorted keys, so a keystroke is two binary searches and at most SCAN keys
--     each, plus at most FRESH_MAX names not sorted in yet. Names the client doesn't have are asked for ASK_BATCH
--     every ASK_GAP s and come in with GET_ITEM_INFO_RECEIVED (listened to only while some are awaited and the tab
--     shows). Again when the prices changed (P.Revision), at most every REFRESH s.
--   * The full search: SEARCH_GAP after the last key, over the index's names a slice a frame (BUDGET_MS, at most
--     PER_FRAME items) on a frame of its own (St.driver), hidden once it's done.

local St = { query = "", lower = {}, results = nil, total = 0, sugg = {}, lows = {} }
W.Stocks = St

local Wn = W.Window
local D = Wn.D
local GREY, GREEN, RED, MARK = "|cff888888", "|cff40c040", "|cffff4040", "|cffffd200"
local SEP = " · "
local PRE, WORD, CUT = "\2", "\3", "\1" -- (the index's keys: a name's start, a later word's start; before the item)
local WORD_SEP = "[%s%-%(%)/:,%.\"]" -- (what ends a word: "Bolt of Linen Cloth", "Elixir (Lesser)")
St.SEARCH_GAP, St.BUDGET_MS, St.PER_FRAME, St.CHECK = 0.2, 2, 2000, 50
St.SHOWN, St.WEEK, St.ASK = 50, 7, 50 -- results shown at most; a week in days; items' data asked for per search
-- Suggestions shown at most; keys looked at per kind of match and keystroke; names looked at one by one before
-- they're sorted in; the index's work a frame (an item 4, a key placed 1); a sorted run; names asked for at once and
-- how often; the index again at most this often; the dropdown closing after the focus left; its size.
St.MAX, St.SCAN, St.FRESH_MAX, St.INDEX_PER_FRAME, St.RUN = 8, 40, 200, 4000, 64
St.ASK_BATCH, St.ASK_GAP, St.REFRESH, St.CLOSE_DELAY = 50, 1, 10, 0.2
St.DROP_W, St.DROP_ROW = 300, 20

local function Clock()
	local ok, ms = pcall(debugprofilestop)
	return ok and type(ms) == "number" and ms or nil
end

local function P()
	return W.Prices
end

---------------------------------------------------------------------------
-- The watch list
---------------------------------------------------------------------------

-- The saved list (item IDs, the order added); an empty one before the saved variables are there.
function St.List()
	local db = W.DB and W.DB()
	if not db then
		return {}
	end
	db.watch = type(db.watch) == "table" and db.watch or {}
	return db.watch
end

function St.Watched(item)
	for i, id in ipairs(St.List()) do
		if id == item then
			return i
		end
	end
end

function St.Watch(item)
	if type(item) == "number" and not St.Watched(item) and W.DB and W.DB() then
		local list = St.List()
		list[#list + 1] = item
		if St.index then
			St.Look(item)
		end
	end
	Wn.state.due = true
end

function St.Unwatch(item)
	local i = St.Watched(item)
	if i then
		table.remove(St.List(), i)
	end
	Wn.state.due = true
end

---------------------------------------------------------------------------
-- An item's numbers
---------------------------------------------------------------------------

-- An entry: the item, its daily lows (P.History, the oldest first), the latest low, the change.
function St.Entry(item)
	local p = P()
	local list = p and p.History and p.History(item) or {}
	local e = { item = item, days = list }
	local last = list[#list]
	if last then
		e.low, e.day = last.low, last.day
	end
	if #list >= 2 then
		-- The change since a week ago: the latest day at least a week before the last, else the oldest.
		local ref = list[1]
		for _, d in ipairs(list) do
			if d.day <= last.day - St.WEEK then
				ref = d
			end
		end
		if ref.low > 0 then
			e.change, e.since = (last.low - ref.low) / ref.low, last.day - ref.day
		end
	end
	return e
end

-- "+12% vs. 7 days ago", green up, red down.
function St.ChangeText(e)
	if not e.change then
		return nil
	end
	local pct = math.floor(e.change * 100 + 0.5)
	local text = (pct > 0 and (GREEN .. "+" .. pct) or pct < 0 and (RED .. pct) or "0") .. "%" .. (pct ~= 0 and "|r" or "")
	return L["%s vs. %d days ago"]:format(text, e.since)
end

-- An item's plain name (nil: not known to the client yet).
function St.Name(item)
	local ok, name = pcall(C_Item.GetItemInfo, ("item:%d"):format(item))
	return ok and type(name) == "string" and not LT.IsSecret(name) and name or nil
end

-- Lowercased, the accented capitals too (Lua's lower knows only A-Z): Ä ä, Ö ö, Ü ü, É é. As many bytes.
function St.Lower(text)
	return (text:lower():gsub("\195([\128-\150\152-\158])", St.Small))
end

function St.Small(c)
	return "\195" .. string.char(c:byte() + 32)
end

-- Where text is in a name: 1 at its start, 2 at a later word's start, 3 anywhere else; and where. nil: not in it.
function St.MatchAt(name, text)
	local at = name:find(text, 1, true)
	if not at then
		return nil
	end
	if at == 1 then
		return 1, 1
	end
	local first = at
	while at do
		if name:sub(at - 1, at - 1):find(WORD_SEP) then
			return 2, at
		end
		at = name:find(text, at + 1, true)
	end
	return 3, first
end

-- The lowest price on your auction house now (P.Get's low), worked out again only when the prices changed.
function St.Low(item)
	local p = P()
	local rev = p and p.Revision and p.Revision()
	local c = St.lows[item]
	if not (c and c[1] == rev) then
		local now = p and p.Get and p.Get(item)
		c = { rev, type(now) == "table" and now.low or nil }
		St.lows[item] = c
	end
	return c[2]
end

---------------------------------------------------------------------------
-- The name index
---------------------------------------------------------------------------

-- St.index (X): the items known by name. X.items: those with a name, in the order they came (X.has: in it or
-- awaited); X.all: their keys as they came, PRE .. name .. CUT .. item and, for each later word, WORD .. the name
-- from that word on .. CUT .. item; X.keys: X.all's first X.sortedKeys sorted, covering X.items' first
-- X.sortedItems (those after: "fresh", looked at one by one). X.lists: what's still to be looked at (P.Items(),
-- the bags, the watch list; X.li, X.qi where); X.sort: a sort under way; X.wait: items whose name the client didn't
-- have (X.waiting: still awaited, X.waitCount of them; X.ask: the next to ask for); X.priced: on your auction
-- house's prices.
function St.NewIndex()
	St.index = { items = {}, has = {}, all = {}, keys = {}, sortedKeys = 0, sortedItems = 0, priced = {}, wait = {},
		waiting = {}, waitCount = 0, ask = 1, nextAsk = 0, nextRefresh = 0, started = false }
	return St.index
end

-- An item with its name: in the index, its keys sorted in by the next sort.
function St.AddName(item, name)
	local X = St.index
	X.has[item] = true
	X.items[#X.items + 1] = item
	local all, tail = X.all, CUT .. item
	all[#all + 1] = PRE .. name .. tail
	for at in name:gmatch(WORD_SEP .. "+()") do
		if at <= #name then
			all[#all + 1] = WORD .. name:sub(at) .. tail
		end
	end
end

-- An item looked at: its name in the index, else awaited (asked for later). One awaited is looked at again.
function St.Look(item)
	local X = St.index
	if type(item) ~= "number" or (X.has[item] and not X.waiting[item]) then
		return
	end
	local name = St.lower[item]
	if not name then
		-- (Not in the client's cache: not asked for its name here, GetItemInfo would request it at once.)
		local cached = C_Item.IsItemDataCachedByID
		local plain = (not cached or LT.Value(cached, item) ~= false) and St.Name(item) or nil
		name = plain and St.Lower(plain) or nil
		St.lower[item] = name
	end
	if name then
		if X.waiting[item] then
			X.waiting[item], X.waitCount = nil, X.waitCount - 1
		end
		St.AddName(item, name)
	elseif not X.has[item] then
		X.has[item], X.waiting[item], X.waitCount = true, true, X.waitCount + 1
		X.wait[#X.wait + 1] = item
	end
end

-- The items in your bags.
function St.BagItems()
	local out = {}
	local last = W.Bags and W.Bags.LastBag and W.Bags.LastBag() or 4
	local C = C_Container or {}
	for bag = 0, last do
		local slots = tonumber(LT.Value(C.GetContainerNumSlots, bag)) or 0
		for slot = 1, slots do
			local id = LT.Value(C.GetContainerItemID, bag, slot)
			if type(id) == "number" then
				out[#out + 1] = id
			end
		end
	end
	return out
end

-- The tab shows: the index made, or looked at again when the prices changed (at most every REFRESH s); its
-- work goes on.
function St.Wake()
	if not St.Showing() then
		return
	end
	local X = St.index or St.NewIndex()
	local p = P()
	local rev = p and p.Revision and p.Revision()
	if not X.started or (X.rev ~= rev and not X.lists and GetTime() >= X.nextRefresh) then
		X.started, X.rev, X.nextRefresh = true, rev, GetTime() + St.REFRESH
		X.lists, X.li, X.qi = { St.Items(), St.BagItems(), St.List() }, 1, 1
	end
	if X.paused then
		X.paused = false
		if X.waitCount > 0 then -- (names that came while the tab was away: looked at again)
			if not X.lists then
				X.lists, X.li, X.qi = {}, 1, 1
			end
			X.lists[#X.lists + 1] = X.wait
		end
	end
	if St.Busy() then
		St.indexer:Show()
	end
	St.Listen()
end

-- Sorting due: names not sorted in yet, FRESH_MAX of them or the first ones, once the lists are looked at.
function St.SortDue()
	local X = St.index
	local fresh = #X.items - X.sortedItems
	return not X.lists and not X.sort and fresh > 0 and (fresh >= St.FRESH_MAX or X.sortedItems == 0)
end

function St.Busy()
	local X = St.index
	return X and (X.lists or X.sort or St.SortDue() or X.ask <= #X.wait or St.dirty) and true or false
end

-- Names still coming: not looked at, sorted or asked for yet (the dropdown says so).
function St.Reading()
	local X = St.index
	return not (X and X.started) or X.lists ~= nil or X.sort ~= nil or #X.items - X.sortedItems > St.FRESH_MAX
		or X.ask <= #X.wait
end

-- A sort a slice at a time (keys are strings: Lua's own <): runs of RUN sorted by table.sort, then merged two by
-- two, the runs twice as long each pass. s = { from = the keys, n = how many, src = {}, dst = {}, tmp = {}, w = 0,
-- lo = 1 }; count: keys placed at most. True when done: s.src sorted.
function St.SortStep(s, count)
	local n = s.n
	if s.w == 0 then
		local from, src, tmp = s.from, s.src, s.tmp
		while count > 0 and s.lo <= n do
			local lo = s.lo
			local hi = math.min(lo + St.RUN - 1, n)
			local len = hi - lo + 1
			for x = 1, len do
				tmp[x] = from[lo + x - 1]
			end
			for x = #tmp, len + 1, -1 do
				tmp[x] = nil
			end
			table.sort(tmp)
			for x = 1, len do
				src[lo + x - 1] = tmp[x]
			end
			s.lo, count = hi + 1, count - len * 2
		end
		if s.lo <= n then
			return false
		end
		s.w, s.lo, s.tmp = St.RUN, 1, nil
	end
	while s.w < n and count > 0 do
		local src, dst = s.src, s.dst
		if not s.k then
			if s.lo > n then -- (a pass done)
				s.src, s.dst, s.w, s.lo = dst, src, s.w * 2, 1
			else
				s.i, s.ie = s.lo, math.min(s.lo + s.w - 1, n)
				s.j, s.je, s.k = s.ie + 1, math.min(s.lo + 2 * s.w - 1, n), s.lo
			end
		else
			local i, ie, j, je, k = s.i, s.ie, s.j, s.je, s.k
			local stop = math.min(je, k + count - 1)
			count = count - (stop - k + 1)
			while k <= stop do
				if j > je or (i <= ie and src[i] <= src[j]) then
					dst[k], i = src[i], i + 1
				else
					dst[k], j = src[j], j + 1
				end
				k = k + 1
			end
			if k > je then
				s.k, s.lo = nil, je + 1
			else
				s.i, s.j, s.k = i, j, k
			end
		end
	end
	return s.w >= n
end

-- A frame's work: the lists, else the sort; names asked for (ASK_BATCH every ASK_GAP s); the dropdown again if
-- names came. At most BUDGET_MS (the clock looked at every slice) and INDEX_PER_FRAME units.
function St.IndexStep()
	local X = St.index
	local started, units, limit = Clock(), 0, St.INDEX_PER_FRAME
	while units < limit and not (started and Clock() - started >= St.BUDGET_MS) do
		if X.lists then
			local list = X.lists[X.li]
			if not list then
				X.lists = nil
			else
				local stop = math.min(#list, X.qi + math.min(St.CHECK, math.ceil((limit - units) / 4)) - 1)
				for i = X.qi, stop do
					local item = list[i]
					if X.li == 1 and type(item) == "number" then
						X.priced[item] = true
					end
					St.Look(item)
				end
				units = units + math.max(1, (stop - X.qi + 1) * 4)
				X.qi = stop + 1
				if X.qi > #list then
					X.li, X.qi = X.li + 1, 1
				end
			end
		elseif X.sort then
			local count = math.min(St.CHECK * 4, limit - units)
			if St.SortStep(X.sort, count) then
				X.keys, X.sortedKeys, X.sortedItems, X.sort = X.sort.src, X.sort.n, X.sort.items, nil
				St.dirty = true
			end
			units = units + count
		elseif St.SortDue() then
			X.sort = { from = X.all, n = #X.all, items = #X.items, src = {}, dst = {}, tmp = {}, w = 0, lo = 1 }
		else
			break
		end
	end
	St.units = units
	if X.ask <= #X.wait and GetTime() >= X.nextAsk and C_Item.RequestLoadItemDataByID then
		local asked = 0
		while X.ask <= #X.wait and asked < St.ASK_BATCH do
			local item = X.wait[X.ask]
			X.ask = X.ask + 1
			if X.waiting[item] then
				pcall(C_Item.RequestLoadItemDataByID, item)
				asked = asked + 1
			end
		end
		X.nextAsk = GetTime() + St.ASK_GAP
	elseif not C_Item.RequestLoadItemDataByID then
		X.ask = #X.wait + 1
	end
	if St.dirty then
		St.dirty = false
		if St.wanted then
			St.Refresh()
		end
	end
	if not St.Busy() then
		St.indexer:Hide()
	end
	St.Listen()
end

-- GET_ITEM_INFO_RECEIVED: only while names are awaited and the tab shows.
function St.Listen()
	local X = St.index
	local want = X and X.waitCount > 0 and St.Showing() and true or false
	if want ~= (St.listening or false) then
		St.listening = want
		if want then
			St.indexer:RegisterEvent("GET_ITEM_INFO_RECEIVED")
		else
			St.indexer:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
		end
	end
end

-- An awaited name came (or the item doesn't exist: success false).
function St.Arrived(item, success)
	local X = St.index
	if not (X and type(item) == "number" and X.waiting[item]) then
		return
	end
	if success == false then
		X.waiting[item], X.waitCount = nil, X.waitCount - 1
	else
		St.Look(item)
	end
	if not X.waiting[item] then
		St.dirty = true
		if St.Showing() then
			St.indexer:Show()
		end
	end
	St.Listen()
end

-- Away from the tab: the index waits (looked at again when it shows).
function St.Pause()
	St.indexer:Hide()
	if St.index then
		St.index.paused = true
	end
	St.Listen()
end

---------------------------------------------------------------------------
-- Suggestions
---------------------------------------------------------------------------

-- The first of keys[1..n] not below text.
function St.LowerBound(keys, n, text)
	local lo, hi, steps = 1, n + 1, 0
	while lo < hi do
		local mid = math.floor((lo + hi) / 2)
		if keys[mid] < text then
			lo = mid + 1
		else
			hi = mid
		end
		steps = steps + 1
	end
	return lo, steps
end

-- One suggestion before another: the kind of match (the name's start, a word's start, anywhere), watched, with a
-- price on your auction house, the shorter name, by name.
function St.Better(a, b)
	if a.tier ~= b.tier then
		return a.tier < b.tier
	end
	if a.watched ~= b.watched then
		return a.watched
	end
	if a.priced ~= b.priced then
		return a.priced
	end
	if #a.name ~= #b.name then
		return #a.name < #b.name
	end
	if a.name ~= b.name then
		return a.name < b.name
	end
	return a.item < b.item
end

-- c into the best MAX, in order.
function St.Offer(list, c)
	if #list >= St.MAX and not St.Better(c, list[#list]) then
		return
	end
	local i = #list + 1
	while i > 1 and St.Better(c, list[i - 1]) do
		list[i] = list[i - 1]
		i = i - 1
	end
	list[i] = c
	list[St.MAX + 1] = nil
end

-- The suggestions for what's typed (q lowercased), at most MAX: the sorted names starting with it and with a word
-- starting with it (SCAN keys each), the same in the fresh names (FRESH_MAX at most), and from the last full search
-- for the same text the names that have it anywhere. St.work: the keys and names looked at (bounded, whatever the index).
function St.Suggest(q)
	local X = St.index or St.NewIndex()
	local list, seen, watched, work = {}, {}, {}, 0
	for _, id in ipairs(St.List()) do
		watched[id] = true
	end
	local function Offer(item, tier, at)
		seen[item] = true
		St.Offer(list, { item = item, tier = tier, at = at, len = #q, name = St.lower[item] or "",
			watched = watched[item] == true, priced = X.priced[item] == true })
	end
	local keys, n = X.keys, X.sortedKeys
	for tier, tag in ipairs({ PRE, WORD }) do
		local key = tag .. q
		local i, steps = St.LowerBound(keys, n, key)
		local looked = 0
		while i <= n and looked < St.SCAN do
			local k = keys[i]
			if k:sub(1, #key) ~= key then
				break
			end
			local cut = k:find(CUT, #key + 1, true)
			local item = tonumber(k:sub(cut + 1))
			if item and not seen[item] and St.lower[item] then
				Offer(item, tier, tier == 1 and 1 or #St.lower[item] - (cut - 2) + 1)
			end
			i, looked = i + 1, looked + 1
		end
		work = work + steps + looked
	end
	local items = X.items
	for x = X.sortedItems + 1, math.min(#items, X.sortedItems + St.FRESH_MAX) do
		local item = items[x]
		local name = St.lower[item]
		if name and not seen[item] then
			local tier, at = St.MatchAt(name, q)
			if tier and tier <= 2 then
				Offer(item, tier, at)
			end
		end
		work = work + 1
	end
	local found = St.found
	if found and found.q == q then
		for _, item in ipairs(found.rest) do
			local name = St.lower[item]
			if name and not seen[item] then
				local tier, at = St.MatchAt(name, q)
				if tier then
					Offer(item, tier, at)
				end
			end
			work = work + 1
		end
	end
	St.work = work
	return list
end

-- What's typed, for the dropdown: an item link or "#1234" is that item; else the names. The mark: none. Wanted
-- (St.wanted: shown again as names come) until closed on purpose.
function St.Type(text)
	text = strtrim(text or "")
	local q = St.Lower(text)
	St.typed, St.hl = q, nil
	if q == "" then
		St.sugg = {}
		St.CloseDrop()
		return
	end
	St.wanted = true
	local id = tonumber(text:match("|Hitem:(%d+)") or text:match("^#(%d+)$") or "")
	if id then
		St.sugg = { { item = id, tier = 1, name = St.lower[id] or "", watched = St.Watched(id) ~= nil } }
		St.work = 0
	else
		St.sugg = St.Suggest(q)
	end
	St.LayDrop()
end

-- The same text's suggestions again (names came, the full search found more); the marked item stays marked.
function St.Refresh()
	local marked = St.hl and St.sugg[St.hl] and St.sugg[St.hl].item
	local hl
	St.Type(St.box and St.box:GetText() or "")
	for i, c in ipairs(St.sugg) do
		if c.item == marked then
			hl = i
		end
	end
	St.hl = hl
	St.LayDrop()
end

-- An item's name in its quality colour, the typed part (at, len bytes: lowercasing keeps them) marked.
function St.Marked(item, at, len)
	local ok, plain, _, quality = pcall(C_Item.GetItemInfo, ("item:%d"):format(item))
	if not (ok and type(plain) == "string" and not LT.IsSecret(plain)) then
		return "#" .. item
	end
	local hex = C_Item.GetItemQualityColor and select(4, C_Item.GetItemQualityColor(type(quality) == "number" and quality or 1))
	local c = type(hex) == "string" and ("|c" .. hex) or "|cffffffff"
	if not (at and len and len > 0) then
		return c .. plain .. "|r"
	end
	return c .. plain:sub(1, at - 1) .. "|r" .. MARK .. plain:sub(at, at + len - 1) .. "|r" .. c .. plain:sub(at + len) .. "|r"
end

---------------------------------------------------------------------------
-- The dropdown
---------------------------------------------------------------------------

-- Under the box, on the window (its left at the box's, St.DROP_W wide, MAX rows: within the window), above the
-- rest (the strata of our popup lists). A click elsewhere closes it (GLOBAL_MOUSE_DOWN, only while it's open), so
-- does the window hiding.
function St.NewDrop(box)
	local f = box:GetParent()
	local d = CreateFrame("Frame", nil, f)
	d:SetFrameStrata("FULLSCREEN_DIALOG")
	d:SetFrameLevel((f:GetFrameLevel() or 1) + 50)
	d:SetClampedToScreen(true)
	d:EnableMouse(true)
	d:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -6, -2)
	d:SetSize(St.DROP_W, 40)
	LT.Window.Dress(d)
	d.rows = {}
	for i = 1, St.MAX do
		local r = CreateFrame("Button", nil, d)
		r:SetHeight(St.DROP_ROW)
		r:SetPoint("TOPLEFT", 3, -3 - (i - 1) * St.DROP_ROW)
		r:SetPoint("TOPRIGHT", -3, -3 - (i - 1) * St.DROP_ROW)
		r.index = i
		r.Sel = r:CreateTexture(nil, "BACKGROUND")
		r.Sel:SetAllPoints()
		r.Sel:SetColorTexture(1, 0.82, 0, 0.18)
		r.Sel:Hide()
		r.Icon = r:CreateTexture(nil, "ARTWORK")
		r.Icon:SetSize(16, 16)
		r.Icon:SetPoint("LEFT", 2, 0)
		r.Right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		r.Right:SetPoint("RIGHT", -4, 0)
		r.Right:SetJustifyH("RIGHT")
		r.Name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		r.Name:SetPoint("LEFT", r.Icon, "RIGHT", 5, 0)
		r.Name:SetPoint("RIGHT", r.Right, "LEFT", -6, 0)
		r.Name:SetJustifyH("LEFT")
		r.Name:SetWordWrap(false)
		r:SetScript("OnClick", function(self)
			St.Choose(self.index)
		end)
		r:SetScript("OnEnter", function(self)
			St.hl = self.index
			St.LayDrop()
		end)
		d.rows[i] = r
	end
	d.Status = d:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	d.Status:SetPoint("BOTTOMLEFT", 8, 4)
	d:SetScript("OnShow", function(self)
		self:RegisterEvent("GLOBAL_MOUSE_DOWN")
	end)
	d:SetScript("OnHide", function(self)
		self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
	end)
	d:SetScript("OnEvent", function(self)
		if not (self:IsMouseOver() or box:IsMouseOver()) then
			St.CloseDrop() -- (a click somewhere else)
		end
	end)
	d:Hide()
	f:HookScript("OnHide", function()
		St.CloseDrop()
		St.Pause()
	end)
	St.drop = d
	return d
end

function St.DropShown()
	return St.drop ~= nil and St.drop:IsShown()
end

-- The suggestions drawn (nothing to show and no names coming: closed).
function St.LayDrop()
	local d = St.drop
	if not (d and St.box and St.box:IsShown()) then
		return
	end
	local list, reading = St.sugg, St.Reading()
	if #list == 0 and not reading then
		St.hl = nil
		d:Hide() -- (still wanted: names may come)
		return
	end
	for i, r in ipairs(d.rows) do
		local c = list[i]
		if c then
			r.Icon:SetTexture(Wn.ItemIcon(c.item))
			r.Name:SetText(St.Marked(c.item, c.at, c.len))
			local low = St.Low(c.item)
			r.Right:SetText((c.watched and (GREY .. L["watched"] .. "|r  ") or "")
				.. (low and W.Money(low) or (GREY .. "-|r")))
			r.Sel:SetShown(St.hl == i)
			r:Show()
		else
			r:Hide()
		end
	end
	d.Status:SetText(reading and L["still reading names..."] or "")
	d.Status:SetShown(reading)
	d:SetHeight(6 + #list * St.DROP_ROW + (reading and 14 or 0))
	d:Show()
end

function St.CloseDrop()
	St.hl, St.wanted = nil, false
	if St.drop then
		St.drop:Hide()
	end
end

-- Up/Down: the mark down (from none: the first; past the last: the first again) or up (from the first: none).
function St.Arrow(key)
	if not St.DropShown() then
		if key == "DOWN" and St.box and (St.box:GetText() or "") ~= "" then
			St.Type(St.box:GetText()) -- (opened again)
		end
		return
	end
	local n = #St.sugg
	if n == 0 then
		return
	end
	if key == "DOWN" then
		St.hl = (St.hl or 0) % n + 1
	elseif key == "UP" then
		St.hl = not St.hl and n or St.hl > 1 and St.hl - 1 or nil
	end
	St.LayDrop()
end

function St.Choose(i)
	local c = St.sugg[i]
	if c then
		St.Pick(c.item)
	end
end

-- A pick: the box shows its name (the list: the search for it, at once), the item selected, its details.
function St.Pick(item)
	St.CloseDrop()
	local box = St.box
	if box then
		St.picking = true
		box:SetText(St.Name(item) or ("#" .. item))
		St.picking = false
		box:ClearFocus()
	end
	St.RunNow()
	if Wn.Shown() and Wn.state.tab == "stocks" and Wn.view then
		Wn.Pick({ item = item })
	end
	Wn.state.due = true
end

-- The full search now (Enter), not SEARCH_GAP after the last key.
function St.RunNow()
	if St.search then
		St.search.at = GetTime()
		St.driver:Show()
	end
end

-- The focus left: closed a moment later (a click on a suggestion lands first), unless it's back or the mouse is on
-- the dropdown.
function St.LaterClose()
	C_Timer.After(St.CLOSE_DELAY, function()
		local box = St.box
		if not St.wanted or (box and box:HasFocus()) then
			return
		end
		if St.DropShown() and St.drop:IsMouseOver() then
			St.LaterClose()
		else
			St.CloseDrop()
		end
	end)
end

---------------------------------------------------------------------------
-- The search
---------------------------------------------------------------------------

-- The items of the auction house's prices, fetched again only when the prices changed.
function St.Items()
	local p = P()
	local rev = p and p.Revision and p.Revision()
	if not St.items or St.itemsRev ~= rev then
		St.items, St.itemsRev = p and p.Items and p.Items() or {}, rev
	end
	return St.items
end

-- What the search goes over: the index's names once its lists are looked at, else the prices' items.
function St.SearchList()
	local X = St.index
	if X and X.started and not X.lists then
		return X.items
	end
	return St.Items()
end

-- What's typed: "" clears the search; an item link or "#1234" is that item at once; else a search after SEARCH_GAP.
function St.SetQuery(text)
	text = strtrim(text or "")
	local q = St.Lower(text)
	if q == St.query then
		return
	end
	St.query = q
	local id = tonumber(text:match("|Hitem:(%d+)") or text:match("^#(%d+)$") or "")
	if q == "" then
		St.search, St.results, St.total = nil, nil, 0
	elseif id then
		St.search, St.results, St.total = nil, { id }, 1
	else
		St.search = { q = q, at = GetTime() + St.SEARCH_GAP, i = 1, tiers = { {}, {}, {} }, total = 0, asked = 0 }
		St.driver:Show()
	end
	Wn.state.due = true
end

-- A slice of the search: the matches (a name not known yet is asked for, ASK a search); at the end the names
-- starting with what's typed first, then those with a word starting with it, then the others, each by name, SHOWN
-- at most.
function St.SearchStep()
	local s = St.search
	local items = s.items
	if not items then
		items = St.SearchList()
		s.items = items
	end
	local started, n = Clock(), 0
	while items[s.i] do
		local item = items[s.i]
		local name = St.lower[item]
		if name == nil then
			local plain = St.Name(item)
			if plain then
				name = St.Lower(plain)
				St.lower[item] = name
			elseif s.asked < St.ASK and C_Item.RequestLoadItemDataByID then
				s.asked = s.asked + 1
				pcall(C_Item.RequestLoadItemDataByID, item)
			end
		end
		if name then
			local tier = St.MatchAt(name, s.q)
			if tier then
				s.total = s.total + 1
				local into = s.tiers[tier]
				if #into < St.SHOWN then
					into[#into + 1] = item
				end
			end
		end
		s.i, n = s.i + 1, n + 1
		if n >= St.PER_FRAME or (n % St.CHECK == 0 and started and Clock() - started >= St.BUDGET_MS) then
			return false
		end
	end
	local function ByName(a, b)
		local x, y = St.lower[a], St.lower[b]
		if x ~= y then
			return x < y
		end
		return a < b
	end
	local out = {}
	for _, list in ipairs(s.tiers) do
		table.sort(list, ByName)
		for _, item in ipairs(list) do
			if #out < St.SHOWN then
				out[#out + 1] = item
			end
		end
	end
	St.results, St.total, St.search = out, s.total, nil
	St.found = { q = s.q, rest = s.tiers[3] }
	if St.wanted and St.typed == s.q then
		St.Refresh() -- (the names that have it anywhere)
	end
	Wn.state.due = true
	return true
end

function St.Showing()
	return Wn.Shown() and Wn.state.tab == "stocks"
end

-- The search's frame: only while one is waiting or under way and the tab shows.
St.driver = CreateFrame("Frame")
St.driver:Hide()
St.driver:SetScript("OnUpdate", function(self)
	if not (St.search and St.Showing()) then
		self:Hide()
		return
	end
	if GetTime() >= St.search.at then
		LT.Guard("WhyPoor stocks", St.SearchStep)
	end
end)

-- The index's frame: only while it has work and the tab shows.
St.indexer = CreateFrame("Frame")
St.indexer:Hide()
St.indexer:SetScript("OnUpdate", function()
	if not St.Showing() then
		St.Pause()
		return
	end
	LT.Guard("WhyPoor stocks index", St.IndexStep)
end)
St.indexer:SetScript("OnEvent", function(_, _, item, success)
	LT.Guard("WhyPoor stocks names", St.Arrived, item, success)
end)

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------

local T = { headWidth = 96 }
St.tab = T

function T.Entries()
	St.Wake()
	local ids
	if St.query == "" then
		ids = St.List()
	else
		if St.search and not St.driver:IsShown() then
			St.driver:Show() -- (a search left when the window closed goes on)
		end
		ids = St.results or {}
	end
	local list = {}
	for _, item in ipairs(ids) do
		if type(item) == "number" then
			list[#list + 1] = { item = item } -- (its numbers when its row is in sight: T.Fill)
		end
	end
	if St.query == "" then
		return list, L["%d watched"]:format(#list), L["Search for an item above and add it to watch its price."]
	elseif St.search then
		return {}, L["Searching..."], L["Searching..."]
	end
	local head = St.total > #list and L["%d of %d found"]:format(#list, St.total) or L["%d found"]:format(#list)
	return list, head, L["No item by that name in your auction house's prices."]
end

function T.Fill(row, e)
	e = St.Entry(e.item)
	row.Icon:SetTexture(Wn.ItemIcon(e.item))
	row.Title:SetText(Wn.ItemName(e.item))
	local p = P()
	local old = e.day and p and p.Today and e.day < p.Today() - 1 -- (not seen today or yesterday)
	row.Money:SetText(e.low and ((old and GREY or "") .. W.Money(e.low) .. (old and "|r" or "")) or (GREY .. "-|r"))
	local sub = St.ChangeText(e) or (#e.days == 1 and L["One day of prices so far"]) or L["No prices yet"]
	if St.query ~= "" and St.Watched(e.item) then
		sub = sub .. SEP .. L["watched"]
	end
	row.Sub:SetText(sub)
	for _, dot in ipairs(row.Dots) do
		dot:Hide()
	end
end

function T.Key(e)
	return e.item
end

-- Picked but not in the list (the search changed, or it left the watch list): its details all the same.
function T.Find(item)
	return type(item) == "number" and { item = item } or nil
end

function T.Enter(row, e)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if not pcall(GameTooltip.SetHyperlink, GameTooltip, ("item:%d"):format(e.item)) then
		GameTooltip:SetText(Wn.ItemName(e.item), 1, 1, 1)
	end
	GameTooltip:AddLine(L["Click: its details"], 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

function T.Details(e)
	local item = e.item
	D.Text(Wn.ItemName(item), "title")
	local p = P()
	local now = p and p.Get and p.Get(item)
	if type(now) == "table" and now.seen then
		D.Text(L["AH"] .. ": " .. (now.low and L["%s (%d listed, %s)"]:format(W.Money(now.low), now.qty or 0, LT.Ago(now.seen))
			or L["none listed (%s)"]:format(LT.Ago(now.seen))), "small")
	end
	D.Graph(item)
	D.y = D.y + 6
	if St.Watched(item) then
		D.Button(L["Remove from watch list"], function() St.Unwatch(item) end, true, 170)
	else
		D.Button(L["Add to watch list"], function() St.Watch(item) end, true, 170)
	end
	local Ch = W.Chart
	if Ch and Ch.Open then
		D.Button(L["Big chart"], function() Ch.Open(item) end, true, 110, true)
	end
	local Ds = Ch and Ch.dash
	if Ds and Ds.Items and Ds.AddItem then
		local on = false
		for _, id in ipairs(Ds.Items()) do
			on = on or id == item
		end
		D.Button(on and L["On the dashboard"] or L["Add to dashboard"], function()
			if Ds.AddItem(item) then
				Wn.state.due = true
			end
		end, not on, 170)
		D.Button(L["Dashboard"], function() Ch.OpenDashboard() end, true, 110, true)
	end
	if W.Alerts and W.Alerts.Details then W.Alerts.Details(item) end -- (price alerts: Alerts.lua)
end

-- Nothing picked: what the tab is.
function T.Overview()
	D.Text(L["Stocks"], "title")
	D.Text(L["Your watch list: each item's lowest price on your auction house, day by day, and how it changed in a week. Search an item above the list and add it."], "text", 0, 2)
	local Ch = W.Chart
	if Ch and Ch.OpenDashboard then
		D.Text(L["The dashboard: charts of the items you pick, side by side (Edit to set it up)."], "text", 0, 6)
		D.Button(L["Dashboard"], function() Ch.OpenDashboard() end, true, 140)
	end
end

-- The search box on the line above the list: as you type, the dropdown; Up/Down mark a suggestion, Enter or Tab
-- picks it (Tab with none marked: the first; Enter with none: the full results now); Escape closes the dropdown,
-- a second empties the box.
function T.Controls(view, shown)
	if not shown and not St.box then
		return
	end
	if not St.box then
		local box = CreateFrame("EditBox", nil, view.Head:GetParent(), "InputBoxTemplate")
		box:SetSize(180, 18)
		box:SetPoint("LEFT", view.Head, "RIGHT", 8, 0)
		box:SetAutoFocus(false)
		box:SetMaxLetters(60)
		box.Hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		box.Hint:SetPoint("LEFT", 2, 0)
		box.Hint:SetText(L["Search an item: name, link or #id"])
		box:SetScript("OnEscapePressed", function(self)
			if St.DropShown() then
				St.CloseDrop()
			else
				self:SetText("")
				self:ClearFocus()
			end
		end)
		box:SetScript("OnEnterPressed", function(self)
			if St.DropShown() and St.hl and St.sugg[St.hl] then
				St.Choose(St.hl)
				return
			end
			St.CloseDrop()
			St.RunNow()
			self:ClearFocus()
		end)
		box:SetScript("OnTabPressed", function()
			if St.DropShown() and #St.sugg > 0 then
				St.Choose(St.hl or 1)
			end
		end)
		box:SetScript("OnArrowPressed", function(_, key)
			St.Arrow(key)
		end)
		-- (Hooked: the template's own highlighting of the text stays.)
		box:HookScript("OnEditFocusLost", St.LaterClose)
		box:HookScript("OnEditFocusGained", function(self)
			if (self:GetText() or "") ~= "" and not St.DropShown() then
				St.Type(self:GetText())
			end
		end)
		box:SetScript("OnTextChanged", function(self, typed)
			local text = self:GetText() or ""
			self.Hint:SetShown(text == "")
			St.Wake()
			St.SetQuery(text)
			if typed and not St.picking then
				St.Type(text)
			else
				St.CloseDrop()
			end
		end)
		St.box = box
		St.NewDrop(box)
	end
	St.box:SetShown(shown)
	if not shown then
		St.CloseDrop()
		St.box:ClearFocus()
		St.Pause()
	end
end

Wn.AddTab("stocks", L["Stocks"], T)
