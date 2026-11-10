local _, ns = ...
local LT = ns.LT
local L = ns.L
local Q = ns.Questtree or {}
ns.Questtree = Q

-- Two more views of the quest browser (docs/questtree.md, Views), tabs of its window through its
-- registry (Q.RegisterBrowserView(key, label, build): build(parent) gives { frame, Refresh, OnShow,
-- OnHide }), registered when the registry is there: at load (Browser.lua comes before this file) or
-- when the module is switched on; without it nothing happens.
--   * Storylines: every chain for me, in all zones, as a grid of cards of three lines (its title and
--     steps done, its zone and levels, its next step), filtered (for my level by default, in
--     progress, ready to turn in, done, all) and sorted by what it's worth (the quests left in it, by
--     their levels) or by level; the rest in a card's tooltip; a click opens the chain in the window
--     (Q.OpenBrowser).
--   * Level path ("Where to go next"): the zones with something for my levels (Q.InRange) or friends
--     there (all zones with a toggle) as rows: the name, a bar across the levels 1-60 from its lowest
--     to its highest quest level, shaded per level (done, available, later), a line at my level, and
--     how many quests there are for my level; the rest in the row's tooltip. A click opens the zone
--     (Q.SelectZone).
-- What it costs: the counts (every zone's quests by status and level, every chain's) are made once
-- per data and progress change (Q.dataGen, Q.progressGen, my level), a few hundred quests a frame
-- (no hitch), only while a view is shown; what's ready to turn in is read from the quest log when a
-- view draws. Events only while a view is shown, noted and drawn half a second later. Nothing runs
-- per frame while idle; the lists are pools of the rows in sight. Our own frames only (Buttons the
-- controller's navigation reaches), nothing protected, no Blizzard menu.

local K = {
	W = 1060, H = 640,          -- a view's size when its parent has none yet
	TOP = 34, FOOT = 20, PAD = 8, GAP = 10, BAR = 24,
	SLICE = 200,                -- quests counted per frame
	BEYOND = 120,               -- px of rows laid beyond sight (the controller's next one)
	CARD_W = 280, CARD_H = 58,  -- storylines' cards (the width is the least)
	ROW_H = 26, NAME_W = 200, RIGHT_W = 150, MAX_LEVEL = 60, -- level path
	REDRAW = 0.5,
}

local T = {
	flat = "Interface\\ChatFrame\\ChatFrameBackground",
	highlight = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
	available = "Interface\\GossipFrame\\AvailableQuestIcon",
	turnin = "Interface\\GossipFrame\\ActiveQuestIcon",
	progress = "Interface\\GossipFrame\\IncompleteQuestIcon",
	lock = "Interface\\LFGFrame\\UI-LFG-ICON-LOCK",
	check = "Interface\\RaidFrame\\ReadyCheck-Ready",
}

-- The window's status colours (Browser.lua's tones), and gold for "ready to turn in".
local TONE = {
	done = { 0.37, 0.73, 0.28 }, active = { 0.35, 0.65, 1 }, available = { 0.85, 0.61, 0 }, ready = { 1, 0.82, 0 },
	locked = { 0.55, 0.55, 0.55 }, level = { 0.9, 0.45, 0.25 }, other = { 0.4, 0.4, 0.4 },
}
local GOLD, GREY = "|cffffd200", "|cff888888"

local V = {}      -- what the views share
local Census = {} -- the counts
local C, D = {}, {} -- the views: storylines, level path

---------------------------------------------------------------------------
-- Shared bits
---------------------------------------------------------------------------

function V.Hex(c)
	return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

function V.MyLevel()
	local level = UnitLevel and LT.Value(UnitLevel, "player")
	return type(level) == "number" and level or 1
end

-- An atlas when the client has it, else the file.
local atlasKnown = {}
function V.Art(texture, atlas, file)
	if atlas and atlasKnown[atlas] == nil then
		atlasKnown[atlas] = (C_Texture and LT.Value(C_Texture.GetAtlasInfo, atlas)) and true or false
	end
	texture:SetDesaturated(false)
	texture:SetVertexColor(1, 1, 1)
	if atlas and atlasKnown[atlas] then
		texture:SetAtlas(atlas)
	else
		texture:SetTexture(file)
		texture:SetTexCoord(0, 1, 0, 1)
	end
end

function V.Untip(self)
	if GameTooltip:IsOwned(self) then
		GameTooltip:Hide()
	end
end

-- Four 1 px edges (the cards' flat border, as the big window's).
function V.Edges(f)
	f.Edges = {}
	for i, spec in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
		local t = f:CreateTexture(nil, "BORDER")
		t:SetPoint(spec[1])
		t:SetPoint(spec[2])
		if spec[3] then
			t:SetHeight(1)
		else
			t:SetWidth(1)
		end
		f.Edges[i] = t
	end
end

function V.EdgeColor(f, r, g, b, a)
	for _, t in ipairs(f.Edges) do
		t:SetColorTexture(r, g, b, a or 1)
	end
end

-- A thin progress bar: a track and its fill (fraction 0..1).
function V.NewBar(parent, height)
	local bar = { height = height }
	bar.Back = parent:CreateTexture(nil, "ARTWORK")
	bar.Back:SetHeight(height)
	bar.Back:SetColorTexture(1, 1, 1, 0.08)
	bar.Fill = parent:CreateTexture(nil, "ARTWORK", nil, 1)
	bar.Fill:SetHeight(height)
	bar.Fill:SetPoint("TOPLEFT", bar.Back, "TOPLEFT")
	return bar
end

function V.SetBar(bar, width, fraction, c)
	bar.Back:SetWidth(width)
	fraction = math.max(0, math.min(1, fraction or 0))
	bar.Fill:SetShown(fraction > 0)
	bar.Fill:SetWidth(math.max(1, width * fraction))
	bar.Fill:SetColorTexture(c[1], c[2], c[3], 1)
	bar.fraction = fraction
end

-- Within my levels (Engine.lua's Q.InRange: in my log, or neither grey nor too far above me); true
-- without it.
function V.InRange(id)
	if not Q.InRange then
		return true
	end
	return Q.InRange(id) == true
end

-- "[12]" or "[12-18]" in their difficulty colours.
function V.Levels(lo, hi)
	if not lo or lo <= 0 then
		return ""
	end
	if not hi or hi == lo then
		return Q.LevelCode(nil, nil, lo) .. "[" .. lo .. "]|r"
	end
	return Q.LevelCode(nil, nil, lo) .. "[" .. lo .. "|r" .. GREY .. "-|r" .. Q.LevelCode(nil, nil, hi) .. hi .. "]|r"
end

-- Going there in the window: a zone (Q.SelectZone; without it the zone's first quest), a quest.
function V.OpenZone(map)
	if not map then
		return
	end
	if Q.SelectZone then
		Q.SelectZone(map)
	elseif Q.OpenBrowser then
		local first = Q.ZoneQuests and Q.ZoneQuests(map)[1]
		if first then
			Q.OpenBrowser(first)
		end
	end
end

function V.OpenQuest(id)
	if id and Q.OpenBrowser then
		Q.OpenBrowser(id)
	end
end

-- The module's setting friends (on without the module).
function V.FriendsOn()
	local m = Q.module
	return not (m and m.db) or m.db.friends ~= false
end

-- What the views keep (the module's settings: views = { show, sort, allZones }): the storylines'
-- filter (for my level at first) and sort, the level path's toggle. (An older build's "filter" is
-- left alone: the new default wins once.)
function V.Saved()
	local m = Q.module
	local saved
	if not (m and m.db) then
		V.fallback = V.fallback or {}
		saved = V.fallback
	else
		if type(m.db.views) ~= "table" then
			m.db.views = {}
		end
		saved = m.db.views
	end
	saved.show = saved.show or "level"
	saved.sort = saved.sort or "worth"
	return saved
end

-- My quests that are ready to turn in (complete, in the log): a set. Read when a view draws.
function V.ReadySet()
	local set, log = {}, C_QuestLog
	if not (log and log.GetNumQuestLogEntries and log.GetInfo and log.IsComplete) then
		return set
	end
	local n = LT.Value(log.GetNumQuestLogEntries)
	for i = 1, type(n) == "number" and n or 0 do
		local info = LT.Value(log.GetInfo, i)
		local id = type(info) == "table" and not info.isHeader and info.questID
		if type(id) == "number" and not LT.IsSecret(id) and LT.Value(log.IsComplete, id) == true then
			set[id] = true
		end
	end
	return set
end

-- A chip of ours (a Button: the controller reaches it): a label, gold and underlined when on.
function V.NewChip(parent, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(80, 22)
	b.Back = b:CreateTexture(nil, "BACKGROUND")
	b.Back:SetAllPoints()
	b.Back:SetColorTexture(0, 0, 0, 0.35)
	b.Line = b:CreateTexture(nil, "ARTWORK")
	b.Line:SetPoint("BOTTOMLEFT")
	b.Line:SetPoint("BOTTOMRIGHT")
	b.Line:SetHeight(2)
	b.Line:SetColorTexture(1, 0.82, 0, 1)
	b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.Text:SetPoint("CENTER", 0, 1)
	b:SetHighlightTexture(T.highlight, "ADD")
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", function(self)
		if self.tip then
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:SetText(self.label or "", 1, 0.82, 0)
			GameTooltip:AddLine(self.tip, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", V.Untip)
	return b
end

function V.SetChip(b, label, on)
	b.label = label
	b.on = on and true or false
	b.Text:SetText((on and GOLD or "|cffdddddd") .. label .. "|r")
	b:SetWidth(math.floor(b.Text:GetStringWidth() + 18))
	b.Line:SetShown(b.on)
	b.Back:SetColorTexture(on and 0.25 or 0, on and 0.2 or 0, 0, on and 0.5 or 0.35)
end

---------------------------------------------------------------------------
-- Lists: rows of any height in a scroll frame, only those in sight (and a bit beyond) made, each
-- kept on its entry (its key) while it stays near, so a controller's cursor stays on it
---------------------------------------------------------------------------

-- kinds = { [kind] = { new = function(child, width) -> row, fill = function(row, entry) } };
-- entries = { { kind, key, h, ... } }.
function V.NewList(parent, kinds)
	local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(1, 1)
	scroll:SetScrollChild(child)
	local list = { scroll = scroll, child = child, kinds = kinds, entries = {}, used = {}, free = {}, w = 1, h = 1, total = 0,
		made = 0, fills = 0 }

	function list:SetSize(w, h)
		self.w, self.h = w, h
		scroll:SetSize(w, h)
		child:SetWidth(w)
	end

	-- The rows near sight: new entries from the pools, those still near kept (refilled when force).
	function list:Lay(force, offset)
		offset = offset or scroll:GetVerticalScroll() or 0
		local lo, hi = offset - K.BEYOND, offset + self.h + K.BEYOND
		local near = {}
		for _, e in ipairs(self.entries) do
			if e.y + e.h > lo and e.y < hi then
				near[e.key] = e
			end
		end
		for key, row in pairs(self.used) do
			local e = near[key]
			if not e or e.kind ~= row.kind then
				self.used[key] = nil
				row:Hide()
				row.entry = nil
				self.free[row.kind] = self.free[row.kind] or {}
				table.insert(self.free[row.kind], row)
			end
		end
		for _, e in ipairs(self.entries) do
			if near[e.key] == e then
				local row = self.used[e.key]
				local fresh = not row
				if fresh then
					local pool = self.free[e.kind]
					row = pool and table.remove(pool)
					if not row then
						row = self.kinds[e.kind].new(child, self.w)
						row.kind = e.kind
						self.made = self.made + 1
					end
					self.used[e.key] = row
				end
				if fresh or force or row.entry ~= e then
					row:ClearAllPoints()
					row:SetPoint("TOPLEFT", 0, -e.y)
					row.entry = e
					self.kinds[e.kind].fill(row, e)
					self.fills = self.fills + 1
				end
				row:Show()
			end
		end
	end

	-- New entries; keep: scrolled where it is (as far as it still goes), else to the top.
	function list:SetEntries(entries, keep)
		local y = 0
		for _, e in ipairs(entries) do
			e.y = y
			y = y + e.h
		end
		self.entries, self.total = entries, y
		child:SetHeight(math.max(1, y))
		local now = scroll:GetVerticalScroll() or 0
		local want = keep and now or 0
		want = math.max(0, math.min(want, y - self.h))
		if want ~= now then
			scroll:SetVerticalScroll(want)
		end
		self:Lay(true, want)
	end

	-- The row showing an entry with this key, if it's near sight (tests, the controller).
	function list:Row(key)
		return self.used[key]
	end

	scroll:HookScript("OnVerticalScroll", function(_, offset)
		list:Lay(false, offset)
	end)
	return list
end

---------------------------------------------------------------------------
-- The counts: every zone's quests by status and level, every chain's, made a slice a frame
---------------------------------------------------------------------------

Census.users = {}   -- the views shown now
Census.starts, Census.slices = 0, 0 -- (for the tests)

-- What the counts depend on: the data, my progress (Status is asked once first, so a quest taken
-- while no view was shown is read), my level.
function Census.Key()
	if Q.Status then
		Q.Status(0)
	end
	return tostring(Q.dataGen) .. ":" .. tostring(Q.progressGen) .. ":" .. tostring(V.MyLevel())
end

local pulse = CreateFrame("Frame")
pulse:Hide()
local events = CreateFrame("Frame")
local EVENTS = { QUEST_TURNED_IN = true, QUEST_ACCEPTED = true, QUEST_REMOVED = true, PLAYER_LEVEL_UP = true, QUEST_LOG_UPDATE = false,
	ZONE_CHANGED_NEW_AREA = false }
Census.pulse, Census.events = pulse, events

function Census.Wake()
	pulse:Show()
end

-- A redraw in delay seconds (several at once: one).
function Census.Due(delay)
	local at = GetTime() + (delay or 0)
	if not Census.due or at < Census.due then
		Census.due = at
	end
	Census.Wake()
end

function Census.AnyShown()
	for inst in pairs(Census.users) do
		if inst.frame:IsVisible() then
			return true
		end
	end
	return false
end

function Census.Listen(on)
	if on == Census.listening then
		return
	end
	Census.listening = on
	for event in pairs(EVENTS) do
		if on then
			events:RegisterEvent(event)
		else
			events:UnregisterEvent(event)
		end
	end
end

-- No view shown: no events, no OnUpdate (the counting goes on when one shows again).
function Census.Sleep()
	pulse:Hide()
	Census.Listen(false)
end

events:SetScript("OnEvent", function(_, event)
	if EVENTS[event] then
		Census.dirty = true -- (statuses change: counted again)
	end
	Census.Due(K.REDRAW)
end)

function Census.Start()
	local w = { zones = {}, byMap = {}, byName = {}, chains = {}, list = {}, seen = {}, jobs = {}, job = 1, at = 1, ci = 1, phase = 1,
		me = V.MyLevel() }
	for _, z in ipairs(Q.Zones and Q.Zones() or {}) do
		local ids = Q.ZoneQuests(z.map)
		local e = { map = z.map, name = Q.MapName(z.map) or z.name or ("#" .. tostring(z.map)), dataName = z.name, continent = z.continent,
			minLevel = tonumber(z.minLevel) or 0, maxLevel = tonumber(z.maxLevel) or 0, count = #ids, total = 0, done = 0, active = 0,
			available = 0, level = 0, locked = 0, near = 0, levels = {} }
		w.zones[#w.zones + 1] = e
		w.byMap[z.map] = e
		for _, name in ipairs({ e.name, z.name }) do
			if type(name) == "string" then
				w.byName[name:lower()] = e
			end
		end
		w.jobs[#w.jobs + 1] = { zone = e, ids = ids }
	end
	for _, d in ipairs(Q.Dungeons and Q.Dungeons() or {}) do
		w.jobs[#w.jobs + 1] = { ids = Q.DungeonQuests(d.name) }
	end
	Census.work = w
	Census.starts = Census.starts + 1
	Census.Wake()
end

-- One quest of a zone: its status into the zone's counts and its level's; its chain noted.
function Census.Quest(w, z, id)
	local q = Q.Quest(id)
	if not q then
		return
	end
	if z then
		local s = Q.Status(id)
		if s and s ~= "other" then
			z.total = z.total + 1
			z[s] = (z[s] or 0) + 1
			local lv = tonumber(q.level) or tonumber(q.minLevel) or 0
			if lv > 0 then
				z.qmin = math.min(z.qmin or lv, lv)
				z.qmax = math.max(z.qmax or lv, lv)
				local b = z.levels[lv]
				if not b then
					b = { total = 0, done = 0, open = 0 }
					z.levels[lv] = b
				end
				b.total = b.total + 1
				if s == "done" then
					b.done = b.done + 1
				elseif s == "available" or s == "active" then
					b.open = b.open + 1
				end
			end
			if s ~= "done" and V.InRange(id) then
				z.near = z.near + 1 -- (for my levels: to do, in my log or neither grey nor far above me)
			end
		end
	end
	local chain = Q.Chain and Q.Chain(id)
	if type(chain) == "table" and #chain >= 2 and not w.seen[chain[1]] then
		w.seen[chain[1]] = true
		w.chains[#w.chains + 1] = chain
	end
end

local NEXT_RANK = { active = 1, available = 2, level = 3, locked = 4 }

-- What a quest left in a chain is worth to me: its level (grey ones a tenth, ones far above me half).
function Census.Worth(id, q, s, me)
	local lv = tonumber(q.level) or tonumber(q.minLevel) or me
	if Q.IsTrivial and Q.IsTrivial(id) then
		return lv * 0.1
	elseif s == "level" or lv > me + 4 then
		return lv * 0.5
	end
	return lv
end

-- One chain: its quests for me by status, levels, zones, what's next, what it's worth.
function Census.Chain(w, chain)
	local c = { first = chain[1], ids = chain, total = 0, done = 0, active = 0, available = 0, level = 0, locked = 0,
		left = 0, worth = 0, zones = {}, zoneList = {} }
	local nextRank
	for _, m in ipairs(chain) do
		local q = Q.Quest(m)
		local s = q and Q.Status(m)
		if s and s ~= "other" then
			c.total = c.total + 1
			c[s] = (c[s] or 0) + 1
			local lv = tonumber(q.level) or tonumber(q.minLevel)
			if lv and lv > 0 then
				c.minLevel = math.min(c.minLevel or lv, lv)
				c.maxLevel = math.max(c.maxLevel or lv, lv)
			end
			local where = q.zone or q.dungeon
			if where then
				if not c.zones[where] then
					c.zones[where] = 0
					c.zoneList[#c.zoneList + 1] = where
				end
				c.zones[where] = c.zones[where] + 1
			end
			if s ~= "done" then
				c.left = c.left + 1
				c.worth = c.worth + Census.Worth(m, q, s, w.me)
				local rank = NEXT_RANK[s]
				if rank and (not nextRank or rank < nextRank) then
					c.next, c.nextStatus, nextRank = m, s, rank
				end
			end
		end
	end
	if c.total < 2 then
		return
	end
	-- Its zone: where most of its quests are (a tie: the first).
	local best
	for _, where in ipairs(c.zoneList) do
		if not best or c.zones[where] > c.zones[best] then
			best = where
		end
	end
	c.zone = best
	local z = type(best) == "number" and w.byMap[best]
	c.zoneName = z and z.name or (type(best) == "number" and Q.MapName(best)) or (type(best) == "string" and best) or nil
	c.title = Q.Title(c.first)
	c.inRange = c.next ~= nil and V.InRange(c.next) -- (its next step is for my levels)
	w.list[#w.list + 1] = c
end

-- Some quests (budget) counted; true when all are.
function Census.Step(budget)
	local w = Census.work
	if not w then
		return true
	end
	Census.slices = Census.slices + 1
	while budget > 0 do
		if w.phase == 1 then
			local job = w.jobs[w.job]
			if not job then
				w.phase = 2
			else
				local id = job.ids[w.at]
				if id == nil then
					w.job, w.at = w.job + 1, 1
				else
					w.at = w.at + 1
					budget = budget - 1
					Census.Quest(w, job.zone, id)
				end
			end
		else
			local chain = w.chains[w.ci]
			if not chain then
				Census.Finish(w)
				return true
			end
			w.ci = w.ci + 1
			budget = budget - #chain
			Census.Chain(w, chain)
		end
	end
	return false
end

-- How far the counting is (0..1).
function Census.Progress()
	local w = Census.work
	if not w then
		return 1
	end
	if w.phase == 1 then
		return 0.7 * (w.job - 1) / math.max(1, #w.jobs)
	end
	return 0.7 + 0.3 * (w.ci - 1) / math.max(1, #w.chains)
end

function Census.Finish(w)
	for _, z in ipairs(w.zones) do
		if z.minLevel <= 0 then
			z.minLevel = z.qmin or 1
		end
		if z.maxLevel < z.minLevel then
			z.maxLevel = math.max(z.minLevel, z.qmax or z.minLevel)
		end
		z.levels.n = nil
	end
	w.jobs, w.seen, w.chains = nil, nil, nil
	w.key = Census.Key()
	Census.data, Census.work = w, nil
	for inst in pairs(Census.users) do
		inst:Draw()
	end
end

-- Drawn again: counted again first when what they depend on changed (meanwhile the last counts).
-- Every view shown (its OnShow came, maybe before its frame showed) is drawn.
function Census.Redraw()
	local key = Census.Key()
	if Census.dirty or not Census.data or Census.data.key ~= key then
		if Census.dirty or not Census.work then
			Census.Start()
		end
		Census.dirty = false
	end
	for inst in pairs(Census.users) do
		inst:Draw()
	end
end

function Census.Tick()
	if not Census.AnyShown() then
		Census.Sleep()
		return
	end
	if Census.work then
		if not Census.Step(K.SLICE) then
			for inst in pairs(Census.users) do
				if inst.frame:IsVisible() then
					V.Status(inst)
				end
			end
		end
	end
	if Census.due and GetTime() >= Census.due then
		Census.due = nil
		Census.Redraw()
	end
	if not (Census.work or Census.due) then
		pulse:Hide()
	end
end

pulse:SetScript("OnUpdate", function()
	LT.Guard("Questtree.views", Census.Tick)
end)

-- The data changed (learned quests, the data loaded): counted again; friends' answers: drawn again.
if Q.OnDataChanged then
	Q.OnDataChanged(function()
		Census.dirty = true
		if Census.AnyShown() then
			Census.Due(0)
		end
	end)
end
if Q.OnFriendProgress then
	Q.OnFriendProgress(function()
		if Census.AnyShown() then
			Census.Due(0.2)
		end
	end)
end

---------------------------------------------------------------------------
-- A view's frame: the top bar, the list on a darker panel, the footer (legend, "Updating")
---------------------------------------------------------------------------

function V.NewView(parent, key)
	local inst = { key = key, draws = 0 }
	local f = CreateFrame("Frame", nil, parent)
	f:SetAllPoints(parent)
	inst.frame = f
	inst.Panel = f:CreateTexture(nil, "BACKGROUND")
	inst.Panel:SetColorTexture(0, 0, 0, 0.25)
	inst.Legend = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	inst.Legend:SetPoint("BOTTOMLEFT", K.PAD, 4)
	inst.Legend:SetJustifyH("LEFT")
	inst.Legend:SetWordWrap(false)
	inst.Note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	inst.Note:SetPoint("BOTTOMRIGHT", -K.PAD, 4)
	inst.Note:SetJustifyH("RIGHT")
	inst.Message = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	inst.Message:SetPoint("TOP", f, "TOP", 0, -K.TOP - 40)
	inst.Message:SetJustifyH("CENTER")
	inst.Message:Hide()
	inst.Guide = LT.Window.AddButton(f, "", function()
		if inst.onGuide then
			inst.onGuide()
		end
	end, { "TOP", inst.Message, "BOTTOM", 0, -12 })
	inst.Guide:SetSize(220, 22)
	inst.Guide:Hide()
	inst.OnShow = function() V.Show(inst) end
	inst.OnHide = function() V.Hide(inst) end
	inst.Refresh = function() Census.Due(0) end
	function inst:Visible()
		return self.frame:IsVisible()
	end
	f:HookScript("OnShow", function() V.Show(inst) end)
	f:HookScript("OnHide", function() V.Hide(inst) end)
	f:SetScript("OnSizeChanged", function() -- (the window laid out or scaled: laid again)
		if inst.active then
			Census.Due(0)
		end
	end)
	return inst
end

-- The parent's size (a view's when it has none yet); laid out again when it changed.
function V.Fit(inst)
	local parent = inst.frame:GetParent()
	local w, h = 0, 0
	if parent and parent.GetSize then
		w, h = parent:GetSize()
	end
	if not (w and w >= 200 and h and h >= 150) then
		w, h = K.W, K.H
	end
	w, h = math.floor(w), math.floor(h)
	if w == inst.w and h == inst.h then
		return false
	end
	inst.w, inst.h = w, h
	local listY = K.TOP + (inst.axis or 0)
	local listH = h - listY - K.FOOT - K.PAD
	inst.Panel:ClearAllPoints()
	inst.Panel:SetPoint("TOPLEFT", 0, -listY)
	inst.Panel:SetSize(w, listH + 4)
	inst.listW = w - K.BAR - 2 * K.PAD
	inst.list:SetSize(inst.listW, listH)
	inst.list.scroll:ClearAllPoints()
	inst.list.scroll:SetPoint("TOPLEFT", K.PAD, -listY - 2)
	inst.Message:SetWidth(w - 80)
	if inst.Layout then
		inst:Layout(w, h)
	end
	return true
end

function V.Show(inst)
	if inst.active then
		return
	end
	inst.active = true
	V.Fit(inst)
	Census.users[inst] = true
	Census.Listen(true)
	if not Q.Ready() then
		V.Say(inst, L["The quest data isn't there: LefthyTools_QuestData is missing or switched off in the AddOns list."])
		inst.noData = true
		return
	end
	inst.noData = false
	Census.Redraw()
end

function V.Hide(inst)
	if not inst.active then
		return
	end
	inst.active = false
	Census.users[inst] = nil
	if GameTooltip:GetOwner() and GameTooltip:GetOwner() ~= UIParent then
		local owner = GameTooltip:GetOwner()
		local p = owner
		for _ = 1, 8 do
			if p == inst.frame then
				GameTooltip:Hide()
				break
			end
			p = p and p.GetParent and p:GetParent()
		end
	end
	if not Census.AnyShown() then
		Census.Sleep()
	end
end

-- A message instead of the list (and maybe a button that helps: guide = { label, fn }).
function V.Say(inst, text, guide)
	inst.list.scroll:SetShown(text == nil)
	inst.Message:SetShown(text ~= nil)
	inst.Message:SetText(text or "")
	inst.Guide:SetShown(text ~= nil and guide ~= nil)
	if guide then
		inst.Guide:SetText(guide[1])
		inst.onGuide = guide[2]
	end
end

-- The footer's note: counting (how far), else nothing.
function V.Status(inst)
	if Census.work then
		local pct = math.floor(Census.Progress() * 100 + 0.5)
		inst.Note:SetText(L["Counting quests... %d%%"]:format(pct))
		if not Census.data then
			V.Say(inst, L["Counting the quests of every zone... %d%%"]:format(pct))
		end
	else
		inst.Note:SetText("")
	end
end

-- Drawn from the counts (none yet: "Counting").
function V.Draw(inst, fill)
	if inst.noData then
		return
	end
	inst.draws = inst.draws + 1
	V.Status(inst)
	if Census.data then
		fill(inst, Census.data)
	end
end

---------------------------------------------------------------------------
-- Storylines: every chain for me, a grid of cards
---------------------------------------------------------------------------

local FILTERS = { "level", "progress", "ready", "done", "all" }
local FILTER_LABEL = { all = L["All"], progress = L["In progress"], ready = L["Ready to turn in"], level = L["For your level"], done = L["Done"] }
local FILTER_TIP = {
	all = L["Every storyline with quests for you, in every zone."],
	progress = L["Started and not finished: you've done a step, or have one in your log."],
	ready = L["A step is ready to turn in."],
	level = L["Its next step is for your level: in your log, or not grey and at most %d levels above you."]:format(Q.RANGE_ABOVE or 2),
	done = L["Every step done."],
}

-- A chain's state now: done, ready (a step ready to turn in), active, available, level, locked.
function C.State(c, ready)
	if c.done >= c.total then
		return "done"
	elseif ready[c.first] then
		return "ready"
	elseif c.active > 0 then
		return "active"
	end
	return c.nextStatus or "locked"
end

function C.Passes(c, filter, ready)
	if filter == "progress" then
		return (c.done > 0 or c.active > 0) and c.done < c.total
	elseif filter == "ready" then
		return ready[c.first] ~= nil
	elseif filter == "level" then
		return c.inRange and c.done < c.total
	elseif filter == "done" then
		return c.done >= c.total
	end
	return true
end

-- The next step's level (else the chain's lowest).
local function NextLevel(c)
	local q = c.next and Q.Quest(c.next)
	return q and (tonumber(q.level) or tonumber(q.minLevel)) or c.minLevel or 0
end

function C.Sort(list, by)
	table.sort(list, function(a, b)
		if (a.left == 0) ~= (b.left == 0) then
			return b.left == 0 -- (done ones last)
		end
		if by == "level" then
			local la, lb = NextLevel(a), NextLevel(b)
			if la ~= lb then
				return la < lb
			end
			if a.worth ~= b.worth then
				return a.worth > b.worth
			end
		else
			if a.worth ~= b.worth then
				return a.worth > b.worth
			end
			if (a.minLevel or 0) ~= (b.minLevel or 0) then
				return (a.minLevel or 0) < (b.minLevel or 0)
			end
		end
		if a.title ~= b.title then
			return tostring(a.title) < tostring(b.title)
		end
		return a.first < b.first
	end)
end

-- What the card says is next: the step to turn in, the one in my log, the next one, what's coming.
function C.NextLine(c, state, ready)
	if state == "done" then
		return TONE.done, L["All done"]
	end
	local id = state == "ready" and ready[c.first] or c.next
	local text = id and Q.LevelTitle(id) or ""
	if state == "ready" then
		return TONE.ready, L["Turn in: %s"]:format(text)
	elseif state == "active" then
		return TONE.active, L["In your log: %s"]:format(text)
	elseif state == "available" then
		return TONE.available, L["Next: %s"]:format(text)
	end
	return TONE.locked, L["Coming up: %s"]:format(text)
end

function C.CardEnter(self)
	local c = self.chain
	if not c then
		return
	end
	local state = C.State(c, self.ready or {})
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(c.title or "?", 1, 0.82, 0)
	local zones = {}
	for _, where in ipairs(c.zoneList) do
		zones[#zones + 1] = type(where) == "number" and (Q.MapName(where) or tostring(where)) or tostring(where)
	end
	if zones[1] then
		GameTooltip:AddLine(table.concat(zones, ", "), 0.8, 0.8, 0.8, true)
	end
	GameTooltip:AddLine(L["%d of %d steps done"]:format(c.done, c.total), 1, 1, 1)
	local color, line = C.NextLine(c, state, self.ready or {})
	GameTooltip:AddLine(line, color[1], color[2], color[3], true)
	local q = c.next and Q.Quest(c.next)
	local giver = q and q.starts and q.starts[1]
	if state ~= "done" and state ~= "ready" and giver and giver.name then
		GameTooltip:AddLine(L["From %s"]:format(giver.name), 0.7, 0.7, 0.7)
	end
	if c.left > 0 then
		GameTooltip:AddLine(L["Worth: %d quests left for you, %s"]:format(c.left, V.Levels(c.minLevel, c.maxLevel)), 0.85, 0.85, 0.85, true)
	end
	if V.FriendsOn() and Q.Friends and c.next then
		local friends = Q.Friends(c.next) or {}
		if friends[1] then
			local done = 0
			for _, fr in ipairs(friends) do
				done = done + (fr.status == "done" and 1 or 0)
			end
			GameTooltip:AddLine(L["Friends: %d of %d have done the next step"]:format(done, #friends), 0.5, 0.75, 1)
		end
	end
	GameTooltip:AddLine(L["Click: open this storyline"], 0.5, 0.75, 1)
	GameTooltip:Show()
end

-- A card of three lines: the title and "3/7", the zone and levels, the next step; the status strip
-- and icon at the left, a thin bar of the steps done along its bottom.
function C.NewCard(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(K.CARD_W, K.CARD_H)
	b.Bg = b:CreateTexture(nil, "BACKGROUND")
	b.Bg:SetAllPoints()
	b.Bg:SetColorTexture(0.1, 0.1, 0.1, 0.6)
	V.Edges(b)
	V.EdgeColor(b, 0.3, 0.3, 0.3, 1)
	b.Strip = b:CreateTexture(nil, "ARTWORK")
	b.Strip:SetPoint("TOPLEFT", 1, -1)
	b.Strip:SetPoint("BOTTOMLEFT", 1, 1)
	b.Strip:SetWidth(3)
	b.Icon = b:CreateTexture(nil, "ARTWORK")
	b.Icon:SetSize(24, 24)
	b.Icon:SetPoint("LEFT", 9, 0)
	b.Steps = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.Steps:SetPoint("TOPRIGHT", -8, -7)
	b.Steps:SetJustifyH("RIGHT")
	b.Title = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	b.Title:SetPoint("TOPLEFT", 40, -6)
	b.Title:SetPoint("RIGHT", b.Steps, "LEFT", -6, 0)
	b.Title:SetJustifyH("LEFT")
	b.Title:SetWordWrap(false)
	b.Meta = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	b.Meta:SetPoint("TOPLEFT", 40, -23)
	b.Meta:SetPoint("RIGHT", -8, 0)
	b.Meta:SetJustifyH("LEFT")
	b.Meta:SetWordWrap(false)
	b.Next = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.Next:SetPoint("TOPLEFT", 40, -38)
	b.Next:SetPoint("RIGHT", -8, 0)
	b.Next:SetJustifyH("LEFT")
	b.Next:SetWordWrap(false)
	b.Next:SetTextColor(0.8, 0.8, 0.8)
	b.Bar = V.NewBar(b, 2)
	b.Bar.Back:SetPoint("BOTTOMLEFT", 4, 1)
	b:SetHighlightTexture(T.highlight, "ADD")
	b:SetScript("OnEnter", C.CardEnter)
	b:SetScript("OnLeave", V.Untip)
	b:SetScript("OnClick", function(self)
		local c = self.chain
		if c then
			V.Untip(self)
			V.OpenQuest(C.State(c, self.ready or {}) == "ready" and self.ready[c.first] or c.next or c.first)
		end
	end)
	return b
end

local CHAIN_ICON = {
	ready = { "QuestTurnin", T.turnin }, active = { "SideInProgressquesticon", T.progress }, available = { "QuestNormal", T.available },
	level = { "QuestNormal", T.available }, locked = { nil, T.lock }, done = { "common-icon-checkmark", T.check },
}

function C.FillCard(b, c, width, ready)
	b.chain, b.ready = c, ready
	b:SetWidth(width)
	local state = C.State(c, ready)
	local tone = TONE[state] or TONE.locked
	b.Strip:SetColorTexture(tone[1], tone[2], tone[3], 1)
	local icon = CHAIN_ICON[state] or CHAIN_ICON.locked
	V.Art(b.Icon, icon[1], icon[2])
	if state == "level" then
		b.Icon:SetDesaturated(true)
		b.Icon:SetVertexColor(1, 0.6, 0.3)
	end
	b.Title:SetText(c.title or "?")
	if state == "done" then
		b.Title:SetTextColor(0.7, 0.7, 0.7)
	else
		b.Title:SetTextColor(1, 0.82, 0)
	end
	b.Steps:SetText((c.left > 0 and GREY or V.Hex(TONE.done)) .. c.done .. "/" .. c.total .. "|r")
	local parts = {}
	if c.zoneName then
		parts[#parts + 1] = c.zoneName
	end
	local levels = V.Levels(c.minLevel, c.maxLevel)
	if levels ~= "" then
		parts[#parts + 1] = levels
	end
	b.Meta:SetText(table.concat(parts, GREY .. " · |r"))
	V.SetBar(b.Bar, width - 8, c.done / math.max(1, c.total), TONE.done)
	local _, line = C.NextLine(c, state, ready)
	b.Next:SetText(line)
	b.state = state
	b:Show()
end

function C.NewRow(parent, width)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(width, K.CARD_H + K.GAP)
	row.cards = {}
	return row
end

function C.FillRow(row, e)
	local inst = e.inst
	for i, c in ipairs(e.chains) do
		local b = row.cards[i]
		if not b then
			b = C.NewCard(row)
			row.cards[i] = b
			inst.cardsMade = (inst.cardsMade or 0) + 1
		end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", (i - 1) * (inst.cardW + K.GAP), 0)
		C.FillCard(b, c, inst.cardW, e.ready)
	end
	for i = #e.chains + 1, #row.cards do
		row.cards[i]:Hide()
		row.cards[i].chain = nil
	end
end

function C.SetFilter(inst, filter)
	V.Saved().show = filter
	inst:Draw(true)
end

function C.SetSort(inst, by)
	V.Saved().sort = by
	inst:Draw(true)
end

function C.Layout(inst, w)
	local inner = inst.listW
	inst.cols = math.max(1, math.floor((inner + K.GAP) / (K.CARD_W + K.GAP)))
	inst.cardW = math.floor((inner - (inst.cols - 1) * K.GAP) / inst.cols)
	inst.rowsFor = nil
end

-- The chips, the counts in them; the cards in rows.
function C.Fill(inst, data, top)
	local saved = V.Saved()
	local filter = FILTER_LABEL[saved.show] and saved.show or "level"
	local sort = saved.sort == "level" and "level" or "worth"
	local readyQuests = V.ReadySet()
	local ready = {}
	for id in pairs(readyQuests) do
		local chain = Q.Chain and Q.Chain(id)
		if type(chain) == "table" and #chain >= 2 then
			ready[chain[1]] = ready[chain[1]] or id
		end
	end
	local counts, shown = {}, {}
	for _, key in ipairs(FILTERS) do
		counts[key] = 0
	end
	for _, c in ipairs(data.list) do
		for _, key in ipairs(FILTERS) do
			if C.Passes(c, key, ready) then
				counts[key] = counts[key] + 1
			end
		end
		if C.Passes(c, filter, ready) then
			shown[#shown + 1] = c
		end
	end
	local x = 0
	for _, key in ipairs(FILTERS) do
		local chip = inst.chips[key]
		V.SetChip(chip, ("%s (%d)"):format(FILTER_LABEL[key], counts[key]), key == filter)
		chip:ClearAllPoints()
		chip:SetPoint("TOPLEFT", inst.frame, "TOPLEFT", K.PAD + x, -6)
		x = x + chip:GetWidth() + 6
	end
	V.SetChip(inst.sorts.worth, L["Worth"], sort == "worth")
	V.SetChip(inst.sorts.level, L["Level"], sort == "level")
	C.Sort(shown, sort)
	inst.shown, inst.counts = shown, counts
	local entries = {}
	for i = 1, #shown, inst.cols do
		local e = { kind = "cards", key = "r" .. #entries + 1, h = K.CARD_H + K.GAP, chains = {}, inst = inst, ready = ready }
		for j = i, math.min(#shown, i + inst.cols - 1) do
			e.chains[#e.chains + 1] = shown[j]
		end
		entries[#entries + 1] = e
	end
	if #data.list == 0 then
		V.Say(inst, L["No storylines for this character here yet."])
	elseif #shown == 0 then
		V.Say(inst, L["No storyline matches this filter."], { L["Show all storylines"], function() C.SetFilter(inst, "all") end })
	else
		V.Say(inst, nil)
	end
	inst.list:SetEntries(entries, not top)
end

function C.Build(parent)
	local inst = V.NewView(parent, "storylines")
	inst.chips, inst.sorts = {}, {}
	for _, key in ipairs(FILTERS) do
		local chip = V.NewChip(inst.frame, function() C.SetFilter(inst, key) end)
		chip.tip = FILTER_TIP[key]
		inst.chips[key] = chip
	end
	inst.sorts.level = V.NewChip(inst.frame, function() C.SetSort(inst, "level") end)
	inst.sorts.level.tip = L["The next step's level first, the lowest first."]
	inst.sorts.level:SetPoint("TOPRIGHT", inst.frame, "TOPRIGHT", -K.PAD, -6)
	inst.sorts.worth = V.NewChip(inst.frame, function() C.SetSort(inst, "worth") end)
	inst.sorts.worth.tip = L["The quests left in it for you, by their levels: grey ones count little, ones far above you half."]
	inst.SortLabel = inst.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	inst.SortLabel:SetText(L["Sort:"])
	inst.list = V.NewList(inst.frame, { cards = { new = C.NewRow, fill = C.FillRow } })
	inst.Layout = function(self, w)
		C.Layout(self, w)
		V.SetChip(self.sorts.level, L["Level"], false)
		V.SetChip(self.sorts.worth, L["Worth"], false)
		self.sorts.worth:ClearAllPoints()
		self.sorts.worth:SetPoint("RIGHT", self.sorts.level, "LEFT", -6, 0)
		self.SortLabel:ClearAllPoints()
		self.SortLabel:SetPoint("RIGHT", self.sorts.worth, "LEFT", -8, 0)
	end
	inst.Draw = function(self, top)
		V.Fit(self)
		V.Draw(self, function(i, data) C.Fill(i, data, top) end)
	end
	return inst
end

---------------------------------------------------------------------------
-- Level path: where to go next, zones as bars across the levels
---------------------------------------------------------------------------

local SHADE = { done = TONE.done, open = TONE.available, later = { 0.42, 0.42, 0.42 } }

-- A zone of my side: enough of its quests are for me.
function D.Mine(z)
	return z.total > 0 and (z.total >= 5 or z.total * 4 >= z.count)
end

-- How a level of a zone looks: done (all its quests), open (some I can take or have), later.
function D.Shade(b)
	if not b or b.total == 0 then
		return nil
	elseif b.done >= b.total then
		return "done"
	elseif b.open > 0 then
		return "open"
	end
	return "later"
end

-- The zone's levels as runs of one shade: { { from, to, shade } } (levels without quests join the
-- run before them; quests outside the zone's range count at its ends).
function D.Runs(z)
	local lo, hi = z.minLevel, math.max(z.minLevel, z.maxLevel)
	local merged = {}
	for lv, b in pairs(z.levels) do
		local at = math.max(lo, math.min(hi, lv))
		local m = merged[at]
		if not m then
			m = { total = 0, done = 0, open = 0 }
			merged[at] = m
		end
		m.total, m.done, m.open = m.total + b.total, m.done + b.done, m.open + b.open
	end
	local runs, cur = {}, nil
	for lv = lo, hi do
		local shade = D.Shade(merged[lv]) or (cur and cur[3]) or nil
		if shade and cur and cur[3] == shade then
			cur[2] = lv
		elseif shade then
			cur = { lv, lv, shade }
			runs[#runs + 1] = cur
		end
	end
	if runs[1] and runs[1][1] > lo then
		runs[1][1] = lo
	end
	return runs
end

function D.Sort(list, me)
	local function away(z)
		if me < z.minLevel then
			return z.minLevel - me
		elseif me > z.maxLevel then
			return me - z.maxLevel
		end
		return 0
	end
	table.sort(list, function(a, b)
		if a.near ~= b.near then
			return a.near > b.near
		end
		local da, db = away(a), away(b)
		if da ~= db then
			return da < db
		end
		if a.minLevel ~= b.minLevel then
			return a.minLevel < b.minLevel
		end
		return a.map < b.map
	end)
end

-- Beacon friends where they are now (Battle.net's zone name) by zone: { [map] = { peer, ... } }.
function D.FriendsHere(data)
	local out = {}
	if not V.FriendsOn() then
		return out
	end
	local beacon = LT.GetModule and LT:GetModule("beacon")
	local peers = beacon and beacon.enabled and beacon.GetPeers and beacon:GetPeers()
	for _, p in pairs(type(peers) == "table" and peers or {}) do
		local area = type(p) == "table" and p.name and p.area
		local z = type(area) == "string" and not LT.IsSecret(area) and data.byName[area:lower()]
		if z then
			out[z.map] = out[z.map] or {}
			table.insert(out[z.map], p)
		end
	end
	for _, list in pairs(out) do
		table.sort(list, function(a, b) return tostring(a.name) < tostring(b.name) end)
	end
	return out
end

function D.X(inst, level)
	return inst.x0 + (math.max(1, math.min(inst.maxL, level)) - 1) * inst.per
end

function D.RowEnter(self)
	local e = self.entry
	local z = e and e.zone
	if not z then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(z.name, 1, 0.82, 0)
	GameTooltip:AddLine(L["Levels %s"]:format(V.Levels(z.minLevel, z.maxLevel)), 1, 1, 1)
	GameTooltip:AddLine(L["%d of %d done"]:format(z.done, z.total), 1, 1, 1)
	if z.near > 0 then
		GameTooltip:AddLine(L["%d for your level"]:format(z.near), TONE.available[1], TONE.available[2], TONE.available[3])
	end
	if z.available > 0 then
		GameTooltip:AddLine(L["%d you can take now"]:format(z.available), 0.85, 0.85, 0.85)
	end
	if (z.active or 0) > 0 then
		GameTooltip:AddLine(L["%d in your quest log"]:format(z.active), TONE.active[1], TONE.active[2], TONE.active[3])
	end
	local later = (z.level or 0) + (z.locked or 0)
	if later > 0 then
		GameTooltip:AddLine(L["%d later (level too low, or another quest first)"]:format(later), 0.6, 0.6, 0.6, true)
	end
	for _, run in ipairs(e.runs) do
		local c = SHADE[run[3]]
		local word = run[3] == "done" and L["done"] or run[3] == "open" and L["quests to take"] or L["later"]
		local span = run[1] == run[2] and tostring(run[1]) or (run[1] .. "-" .. run[2])
		GameTooltip:AddLine(L["Level %s: %s"]:format(span, word), c[1], c[2], c[3])
	end
	for _, p in ipairs(e.friends or {}) do
		GameTooltip:AddLine(LT.Window.ClassColorCode(p.classFile) .. tostring(p.name) .. "|r " .. GREY .. (p.level and L["level %d"]:format(p.level) or "")
			.. "|r", 1, 1, 1)
	end
	if e.here then
		GameTooltip:AddLine(L["You're here."], 0.4, 0.8, 1)
	end
	GameTooltip:AddLine(L["Click: open this zone"], 0.5, 0.75, 1)
	GameTooltip:Show()
end

-- A row: the zone's name, its bar across the levels with my level's line, how many quests there are
-- for my level (all done: says so). The zone I'm in has a faint blue band; the rest is its tooltip's.
function D.NewRow(parent, width)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, K.ROW_H)
	b:SetHighlightTexture(T.highlight, "ADD")
	b.Here = b:CreateTexture(nil, "BACKGROUND")
	b.Here:SetAllPoints()
	b.Here:SetColorTexture(0.35, 0.65, 1, 0.1)
	b.Line = b:CreateTexture(nil, "BACKGROUND", nil, 1)
	b.Line:SetPoint("BOTTOMLEFT")
	b.Line:SetPoint("BOTTOMRIGHT")
	b.Line:SetHeight(1)
	b.Line:SetColorTexture(1, 1, 1, 0.05)
	b.Name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	b.Name:SetPoint("LEFT", 8, 0)
	b.Name:SetWidth(K.NAME_W - 16)
	b.Name:SetJustifyH("LEFT")
	b.Name:SetWordWrap(false)
	b.Right = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.Right:SetPoint("RIGHT", -8, 0)
	b.Right:SetWidth(K.RIGHT_W - 12)
	b.Right:SetJustifyH("RIGHT")
	b.Right:SetWordWrap(false)
	b.Track = b:CreateTexture(nil, "BORDER", nil, 1)
	b.Track:SetColorTexture(1, 1, 1, 0.06)
	b.Runs = {}
	b.Me = b:CreateTexture(nil, "OVERLAY")
	b.Me:SetColorTexture(1, 0.82, 0, 0.85)
	b.Me:SetWidth(2)
	b:SetScript("OnEnter", D.RowEnter)
	b:SetScript("OnLeave", V.Untip)
	b:SetScript("OnClick", function(self)
		if self.entry then
			V.Untip(self)
			V.OpenZone(self.entry.zone.map)
		end
	end)
	return b
end

function D.FillRow(b, e)
	local inst, z = e.inst, e.zone
	b:SetWidth(inst.listW)
	b.Here:SetShown(e.here)
	b.Name:SetText(z.name)
	if z.near > 0 then
		b.Right:SetText(V.Hex(TONE.available) .. L["%d for your level"]:format(z.near) .. "|r")
	elseif z.done >= z.total then
		b.Right:SetText(V.Hex(TONE.done) .. L["All done"] .. "|r")
	else
		b.Right:SetText("")
	end
	local mid, barH = -K.ROW_H / 2, 10
	local function place(t, from, to, h)
		t:ClearAllPoints()
		t:SetPoint("LEFT", b, "TOPLEFT", D.X(inst, from), mid)
		t:SetSize(math.max(1, D.X(inst, to) + inst.per - D.X(inst, from)), h)
	end
	place(b.Track, z.minLevel, math.max(z.minLevel, z.maxLevel), barH + 4)
	for i, run in ipairs(e.runs) do
		local t = b.Runs[i]
		if not t then
			t = b:CreateTexture(nil, "ARTWORK")
			b.Runs[i] = t
		end
		local c = SHADE[run[3]]
		t:SetColorTexture(c[1], c[2], c[3], run[3] == "later" and 0.7 or 0.9)
		place(t, run[1], run[2], barH)
		t:Show()
	end
	for i = #e.runs + 1, #b.Runs do
		b.Runs[i]:Hide()
	end
	b.Me:ClearAllPoints()
	b.Me:SetPoint("TOP", b, "TOPLEFT", D.X(inst, inst.me) + inst.per / 2, 0)
	b.Me:SetHeight(K.ROW_H)
end

-- The axis over the rows: levels every ten, "You" at mine.
function D.Axis(inst)
	local a = inst.Axis
	for i, fs in ipairs(a.ticks) do
		local lv = i == 1 and 1 or (i - 1) * 10
		if lv <= inst.maxL then
			fs:ClearAllPoints()
			fs:SetPoint("BOTTOM", a, "BOTTOMLEFT", K.PAD + D.X(inst, lv) + inst.per / 2, 2)
			fs:SetText(tostring(lv))
			fs:Show()
		else
			fs:Hide()
		end
	end
	a.You:ClearAllPoints()
	a.You:SetPoint("BOTTOM", a, "BOTTOMLEFT", K.PAD + D.X(inst, inst.me) + inst.per / 2, 14)
	a.You:SetText(GOLD .. L["You (%d)"]:format(inst.me) .. "|r")
end

function D.Layout(inst, w)
	inst.x0 = K.NAME_W
	inst.per = math.max(2, (inst.listW - K.NAME_W - K.RIGHT_W) / inst.maxL)
	inst.Axis:SetSize(w, 28)
end

-- The toggle "All zones" (kept: views.allZones).
function D.SetAll(inst, on)
	V.Saved().allZones = on and true or nil
	inst:Draw()
end

-- The zones of my side with something for my levels or friends there (all of them with the toggle),
-- the most for my levels first; on top the best next one.
function D.Fill(inst, data)
	local me = V.MyLevel()
	local maxL = K.MAX_LEVEL
	for _, z in ipairs(data.zones) do
		maxL = math.max(maxL, z.maxLevel)
	end
	if maxL ~= inst.maxL or me ~= inst.me then
		inst.maxL, inst.me = maxL, me
		D.Layout(inst, inst.w)
	end
	D.Axis(inst)
	local all = V.Saved().allZones == true
	V.SetChip(inst.All, L["All zones"], all)
	local here = Q.HereZone and Q.HereZone()
	local friends = D.FriendsHere(data)
	local mine, list = {}, {}
	for _, z in ipairs(data.zones) do
		if D.Mine(z) then
			mine[#mine + 1] = z
			if all or z.near > 0 or friends[z.map] then
				list[#list + 1] = z
			end
		end
	end
	D.Sort(list, me)
	local entries = {}
	for _, z in ipairs(list) do
		entries[#entries + 1] = { kind = "zone", key = "z" .. z.map, h = K.ROW_H, zone = z, inst = inst, here = z.map == here,
			friends = friends[z.map], runs = D.Runs(z) }
	end
	inst.zones = list
	local best = list[1]
	if best and best.near > 0 then
		inst.Head:SetText(L["Best next: %s, %d quests for your level"]:format(GOLD .. best.name .. "|r", best.near))
	else
		local soon
		for _, z in ipairs(mine) do
			if z.done < z.total and z.minLevel > me and (not soon or z.minLevel < soon.minLevel) then
				soon = z
			end
		end
		inst.Head:SetText(soon and L["Nothing for your level. Next up: %s, from level %d."]:format(GOLD .. soon.name .. "|r", soon.minLevel)
			or (mine[1] and L["Nothing for your level."]) or "")
	end
	if not mine[1] then
		V.Say(inst, L["No zone has quests for this character."])
	elseif not best then
		V.Say(inst, L["No zone has quests for your level."], { L["Show all zones"], function() D.SetAll(inst, true) end })
	else
		V.Say(inst, nil)
	end
	inst.list:SetEntries(entries, true)
end

function D.Build(parent)
	local inst = V.NewView(parent, "levelpath")
	inst.axis = 28
	inst.maxL, inst.me = K.MAX_LEVEL, V.MyLevel()
	inst.All = V.NewChip(inst.frame, function() D.SetAll(inst, not V.Saved().allZones) end)
	inst.All.tip = L["Also the zones without quests for your level."]
	inst.All:SetPoint("TOPRIGHT", inst.frame, "TOPRIGHT", -K.PAD, -6)
	inst.Head = inst.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	inst.Head:SetPoint("TOPLEFT", K.PAD, -10)
	inst.Head:SetPoint("RIGHT", inst.All, "LEFT", -K.PAD, 0)
	inst.Head:SetJustifyH("LEFT")
	inst.Head:SetWordWrap(false)
	inst.Axis = CreateFrame("Frame", nil, inst.frame)
	inst.Axis:SetPoint("TOPLEFT", 0, -K.TOP)
	inst.Axis.ticks = {}
	for i = 1, 7 do
		inst.Axis.ticks[i] = inst.Axis:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	end
	inst.Axis.You = inst.Axis:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	inst.list = V.NewList(inst.frame, { zone = { new = D.NewRow, fill = D.FillRow } })
	inst.Layout = function(self, w)
		D.Layout(self, w)
	end
	inst.Legend:SetText(V.Hex(TONE.done) .. "|T" .. T.flat .. ":10:10|t " .. L["Done"] .. "|r   " .. V.Hex(TONE.available) .. "|T" .. T.flat .. ":10:10|t "
		.. L["Quests to take"] .. "|r   |cff6b6b6b|T" .. T.flat .. ":10:10|t " .. L["Later"] .. "|r   " .. GOLD .. "| " .. L["Your level"] .. "|r")
	inst.Draw = function(self)
		V.Fit(self)
		V.Draw(self, D.Fill)
	end
	return inst
end

---------------------------------------------------------------------------
-- Registering the views with the window
---------------------------------------------------------------------------

local DEFS = {
	{ key = "storylines", label = L["Storylines"], build = C.Build },
	{ key = "levelpath", label = L["Level path"], build = D.Build },
}
local built = {}      -- key -> the view made (the last one)
local registered = false

-- A view made for a parent frame: { frame, Refresh, OnShow, OnHide, ... } (also for the tests).
function Q.BuildView(key, parent)
	for _, def in ipairs(DEFS) do
		if def.key == key then
			local inst = def.build(parent)
			built[key] = inst
			return inst
		end
	end
end

-- Registered with the window's registry once it's there (true when it is).
local function Register()
	if registered or type(Q.RegisterBrowserView) ~= "function" then
		return registered
	end
	registered = true
	for _, def in ipairs(DEFS) do
		local key = def.key
		local ok, err = pcall(Q.RegisterBrowserView, key, def.label, function(parent)
			return Q.BuildView(key, parent)
		end)
		if not ok then
			geterrorhandler()(err)
		end
	end
	return true
end

Register()
if Q.When then
	Q.When("enable", Register)
	Q.When("disable", function()
		Census.work, Census.due = nil, nil
		Census.Sleep()
	end)
end

-- For the tests: the views made, the counts, the shared bits; reset forgets the registration.
function Q.ViewsState(reset)
	if reset then
		registered = false
	end
	return { built = built, census = Census, defs = DEFS, registered = registered, register = Register, V = V, K = K }
end
