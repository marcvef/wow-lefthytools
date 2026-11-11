local _, ns = ...
local LT = ns.LT
local L = ns.L
local Q = ns.Lodestar or {}
ns.Lodestar = Q

-- Two more views of the quest browser (docs/lodestar.md, Views), tabs of its window through its
-- registry (Q.RegisterBrowserView(key, label, build): build(parent) gives { frame, Refresh, OnShow,
-- OnHide }), registered when the registry is there: at load (Browser.lua comes before this file) or
-- when the module is switched on; without it nothing happens.
--   * My quests: my quest log, organised as quest log add-ons and guides do it: what's ready to turn
--     in (every zone) first, then by zone (mine first), by level or by storyline, each group in the
--     one order of quests (Q.Compare: by level; a storyline in its steps' order); a line per quest:
--     "[12] Title" in its difficulty tier's colour (Q.Tier), its chain's "2/4", its first objective
--     not done with its progress ("3/10 Defias Bandit", how far) or "Ready to turn in", and where
--     it's turned in. A click shows it on the window's map (Q.OpenBrowser), a right-click opens its
--     chain (Q.OpenChain; a controller: the "2/4" badge, a button of its own), Shift-click sets the
--     map pin where to go (the turn-in, else the nearest objective area). Under it "Continue your
--     storylines": the chains I've started whose next step I can take now (Q.InRange), in the one
--     order of those steps (for my level first, hard ones after, marked), at most 8.
--   * Level path ("Where to go next"): the zones with something for my levels (Q.InRange) or friends
--     there (all zones with a toggle) as rows: the name, a bar across the levels 1-60 from its lowest
--     to its highest quest level, each level in the difficulty tier its quests have for me (green,
--     yellow, orange, red; grey below; a thin line where all are done), a line at my level, and "7
--     for your level · 2 hard"; the rest (counts by tier) in the row's tooltip. A click opens the
--     zone (Q.SelectZone).
-- What it costs: the counts (every zone's quests by status and level, every chain's) are made once
-- per data and progress change (Q.dataGen, Q.progressGen, my level), a few hundred quests a frame
-- (no hitch), only while a view is shown; the quest log is read when a view draws. Events only while
-- a view is shown, noted and drawn half a second later; My quests looks every 2 s whether I moved
-- (the distances). Nothing runs while hidden; the lists are pools of the rows in sight. Our own
-- frames only (Buttons the controller's navigation reaches), nothing protected, no Blizzard menu.

local K = {
	W = 1060, H = 640,          -- a view's size when its parent has none yet
	TOP = 34, FOOT = 20, PAD = 8, GAP = 10, BAR = 24,
	SLICE = 200,                -- quests counted per frame
	BEYOND = 120,               -- px of rows laid beyond sight (the controller's next one)
	ROW_H = 26, NAME_W = 200, RIGHT_W = 190, MAX_LEVEL = 60, -- level path
	REDRAW = 0.5,
}

local T = {
	flat = "Interface\\ChatFrame\\ChatFrameBackground",
	highlight = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
	available = "Interface\\GossipFrame\\AvailableQuestIcon",
	turnin = "Interface\\GossipFrame\\ActiveQuestIcon",
	progress = "Interface\\GossipFrame\\IncompleteQuestIcon",
}

-- The window's status colours (Browser.lua's tones), and gold for "ready to turn in".
local TONE = {
	done = { 0.37, 0.73, 0.28 }, active = { 0.35, 0.65, 1 }, available = { 0.85, 0.61, 0 },
}
local GOLD, GREY = "|cffffd200", "|cff888888"

local V = {}      -- what the views share
local Census = {} -- the counts
local C, D = {}, {} -- the views: my quests, level path

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

-- Within my levels (Engine.lua's Q.InRange: in my log, or my level reached, neither grey nor red); true
-- without it.
function V.InRange(id)
	if not Q.InRange then
		return true
	end
	return Q.InRange(id) == true
end

-- Difficulty for me (the engine's tiers: "trivial" grey, "easy" green, "fair" yellow, "difficult"
-- orange, "impossible" red): Q.Tier (the quest's effective level, its mobs', a group quest one
-- harder); without it Q.Difficulty, else fair.
local TIERS = { "trivial", "easy", "fair", "difficult", "impossible" }
local TIER_RGB = { trivial = { 0.5, 0.5, 0.5 }, easy = { 0.25, 0.75, 0.25 }, fair = { 1, 0.82, 0 }, difficult = { 1, 0.5, 0.25 },
	impossible = { 1, 0.1, 0.1 } }
local TIER_EN = { trivial = "Trivial", easy = "Easy", fair = "Fair", difficult = "Hard", impossible = "Too hard" }
V.TIERS = TIERS

function V.Tier(id)
	local tier = Q.Tier and Q.Tier(id) or Q.Difficulty and Q.Difficulty(id)
	return TIER_RGB[tier] and tier or "fair"
end

-- A tier's colour: r, g, b (Q.TierColor's table, { r, g, b } or { 1, 2, 3 }).
function V.TierRGB(tier)
	local c = Q.TierColor and Q.TierColor(tier)
	if type(c) == "table" and tonumber(c.r or c[1]) then
		return tonumber(c.r or c[1]), tonumber(c.g or c[2]) or 1, tonumber(c.b or c[3]) or 1
	end
	c = TIER_RGB[tier] or TIER_RGB.fair
	return c[1], c[2], c[3]
end

function V.TierHex(tier)
	return V.Hex({ V.TierRGB(tier) })
end

-- A tier's word (Lodestar.lua's Q.TIER_WORD: "Easy", "Hard", "Too hard", ...).
function V.TierWord(tier)
	local word = Q.TIER_WORD and Q.TIER_WORD[tier]
	return type(word) == "string" and word or TIER_EN[tier] or tostring(tier)
end

-- "|cff......" of a quest's tier (Q.TierCode; else its level's colour).
function V.TierCode(id, quest)
	local code = Q.TierCode and id and Q.TierCode(id)
	return type(code) == "string" and code ~= "" and code or Q.LevelCode(id, quest)
end

-- "[12] Title" in its tier's colour.
function V.Title(id, quest)
	quest = quest or Q.Quest(id)
	local level = quest and tonumber(quest.level)
	return V.TierCode(id, quest) .. ((level and level > 0) and ("[" .. level .. "] ") or "") .. Q.Title(id, quest) .. "|r"
end

-- For my level (Q.ForMyLevel: in my log, or one I can take now that's easy or fair) and hard (Q.IsHard:
-- I can take it, within my levels, orange); without them: in my log or available within my levels,
-- and none.
function V.ForMyLevel(id)
	if Q.ForMyLevel then
		return Q.ForMyLevel(id) == true
	end
	local s = Q.Status(id)
	return s == "active" or (s == "available" and V.InRange(id))
end

function V.IsHard(id)
	return Q.IsHard ~= nil and Q.IsHard(id) == true
end

-- The one order of quests (Engine.lua's Q.Compare: ready, in my log, for my level, hard, ..., then by
-- level and title); without it by ID.
function V.Before(a, b)
	if Q.Compare then
		return Q.Compare(a, b) == true
	end
	return a < b
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

-- A quest's chain in the window: its zone, the quest picked, the chain in the middle with its card in
-- sight (Q.OpenChain; without it the quest).
function V.OpenChain(id)
	if id and Q.OpenChain then
		Q.OpenChain(id)
	else
		V.OpenQuest(id)
	end
end

-- A chain's badge on a row ("2/4"): a Button of its own over the row (the controller reaches it), a
-- faint gold pill; hovering lights it and says what it is (b.title, b.line), a click opens the chain
-- (b.quest: V.OpenChain). The row's own click stays the row's.
function V.NewBadge(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(40, 16)
	b.Back = b:CreateTexture(nil, "BACKGROUND")
	b.Back:SetAllPoints()
	b.Back:SetColorTexture(1, 0.82, 0, 0.1)
	b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.Text:SetPoint("CENTER", 0, 0)
	b:SetHighlightTexture(T.highlight, "ADD")
	b:SetScript("OnEnter", V.BadgeEnter)
	b:SetScript("OnLeave", V.Untip)
	b:SetScript("OnClick", function(self)
		V.Untip(self)
		V.OpenChain(self.quest)
	end)
	b:Hide()
	return b
end

-- A badge for a quest: "2/4" (nil text: hidden), its tooltip's title and line.
function V.SetBadge(b, id, text, title, line)
	b.quest, b.title, b.line = text and id or nil, title, line
	b.Text:SetText(text and (Q.COLOR.progress .. text .. "|r") or "")
	b:SetShown(text ~= nil)
end

function V.BadgeEnter(self)
	if not self.quest then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(self.title or "?", 1, 0.82, 0)
	if self.line then
		GameTooltip:AddLine(self.line, 1, 1, 1)
	end
	GameTooltip:AddLine(L["Click: open the chain"], 0.5, 0.75, 1)
	GameTooltip:Show()
end

-- The module's setting friends (on without the module).
function V.FriendsOn()
	local m = Q.module
	return not (m and m.db) or m.db.friends ~= false
end

-- What the views keep (the module's settings: views = { mySort, allZones }): My quests' sort (by
-- zone at first), the level path's toggle. (The storylines' show and sort of the builds before are
-- left alone.)
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
	if saved.mySort ~= "level" and saved.mySort ~= "chain" then
		saved.mySort = "zone"
	end
	return saved
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
			available = 0, level = 0, locked = 0, near = 0, hard = 0, tiers = {}, levels = {} }
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

-- One quest of a zone: its status into the zone's counts, its tier (not done ones) into the zone's
-- and its level's; its chain noted. An event quest not in my log (only takeable while its holiday is
-- on) isn't one I can take now: counted apart.
function Census.Quest(w, z, id)
	local q = Q.Quest(id)
	if not q then
		return
	end
	if z then
		local s = Q.Status(id)
		if s and s ~= "other" then
			if s == "available" and q.event then
				s = "event"
			end
			z.total = z.total + 1
			z[s] = (z[s] or 0) + 1
			local tier = s ~= "done" and V.Tier(id) or nil
			if tier then
				z.tiers[tier] = (z.tiers[tier] or 0) + 1
			end
			local lv = tonumber(q.level) or tonumber(q.minLevel) or 0
			if lv > 0 then
				z.qmin = math.min(z.qmin or lv, lv)
				z.qmax = math.max(z.qmax or lv, lv)
				local b = z.levels[lv]
				if not b then
					b = { total = 0, done = 0, tiers = {} }
					z.levels[lv] = b
				end
				b.total = b.total + 1
				if tier then
					b.tiers[tier] = (b.tiers[tier] or 0) + 1
				else
					b.done = b.done + 1
				end
			end
			if V.ForMyLevel(id) then
				z.near = z.near + 1 -- (for my level: in my log, or one I can take now that's easy or fair)
			elseif V.IsHard(id) then
				z.hard = z.hard + 1 -- (one I can take now that's orange)
			end
		end
	end
	local chain = Q.Chain and Q.Chain(id)
	if type(chain) == "table" and #chain >= 2 and not w.seen[chain[1]] then
		w.seen[chain[1]] = true
		w.chains[#w.chains + 1] = chain
	end
end

-- One chain: its quests for me by status, its levels, and its next step I can take now within my
-- levels (the first in its order that's "available" and Q.InRange).
function Census.Chain(w, chain)
	local c = { first = chain[1], ids = chain, total = 0, done = 0, active = 0, available = 0, level = 0, locked = 0 }
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
			if s == "available" and not c.take and V.InRange(m) then
				c.take = m
			end
		end
	end
	if c.total < 2 then
		return
	end
	c.title = Q.Title(c.first)
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
	LT.Guard("Lodestar.views", Census.Tick)
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
		if not Census.data and not inst.ownList then
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
-- My quests: the quest log, organised (ready to turn in first, then by zone, level or storyline),
-- and the storylines I've started whose next step I can take now
---------------------------------------------------------------------------

local SORTS = { "zone", "level", "chain" }
local SORT_LABEL = { zone = L["Zone"], level = L["Level"], chain = L["Storyline"] }
local SORT_TIP = {
	zone = L["Your zone first (the nearest first), then the other zones."],
	level = L["The lowest level first."],
	chain = L["By storyline, its steps in order."],
}
local CONTINUE_MAX = 8
local QUEST_H, HEAD_H, NOTE_H = 24, 28, 22
local MOVE_EVERY, MOVE_FAR = 2, 0.02 -- s between looks whether I moved; how far (of the map) is a move

-- My quest log in its order: { { id, header, ready, logLevel } } (header: the game's zone heading
-- above it). Hidden and secret entries left out.
function C.Log()
	local out, log = {}, C_QuestLog
	if not (log and log.GetNumQuestLogEntries and log.GetInfo) then
		return out
	end
	local n = LT.Value(log.GetNumQuestLogEntries)
	local header
	for i = 1, type(n) == "number" and n or 0 do
		local info = LT.Value(log.GetInfo, i)
		if type(info) == "table" then
			local id = info.questID
			if info.isHeader then
				header = type(info.title) == "string" and not LT.IsSecret(info.title) and info.title or nil
			elseif not info.isHidden and type(id) == "number" and not LT.IsSecret(id) and id > 0 then
				out[#out + 1] = { id = id, header = header, ready = log.IsComplete and LT.Value(log.IsComplete, id) == true,
					logLevel = tonumber(info.level) }
			end
		end
	end
	return out
end

-- A quest of my log made ready to draw: its level, title, the zone it's listed under, its first
-- objective not done (Q.LogObjectives), its chain, where to go (ready: the turn-in nearest me, else
-- the nearest area of an objective not done) and how far that is when it's in my zone.
function C.Fill(e, ctx)
	local q = Q.Quest(e.id)
	e.quest = q
	local level = q and tonumber(q.level) or e.logLevel
	e.level = level and level > 0 and level or ctx.me
	e.title = Q.Title(e.id, q)
	if q and type(q.zone) == "number" then
		e.zone, e.zoneName = q.zone, Q.MapName(q.zone) or q.zoneName
	elseif q and q.dungeon then
		e.zone, e.zoneName = q.dungeon, q.dungeon
	elseif e.header then
		e.zone, e.zoneName = e.header, e.header
	else
		e.zone, e.zoneName = "?", L["Other quests"]
	end
	e.zoneName = e.zoneName or tostring(e.zone)
	e.here = ctx.zone ~= nil and (e.zone == ctx.zone or e.zoneName == ctx.zoneName)
	e.objectives = Q.LogObjectives(e.id)
	e.todo = nil
	for _, o in ipairs(e.objectives) do
		if not o.done then
			e.todo = o
			break
		end
	end
	local ends = q and q.ends or {}
	e.ender = ends[1]
	local spot, objective
	if e.ready then
		spot = Q.NearestPoint(ends, ctx.zone, ctx.x, ctx.y)
	else
		spot, objective = Q.ObjectiveSpot(e.id, ctx.zone, ctx.x, ctx.y)
	end
	if not spot then
		spot = Q.NearestPoint(ends, ctx.zone, ctx.x, ctx.y)
		for _, who in ipairs(ends) do
			spot = spot or (who.points and who.points[1])
		end
		objective = nil
	end
	e.spot, e.spotObjective = spot, objective
	e.far = nil
	if spot and spot.map == ctx.zone and ctx.x then
		e.far = Q.TowardText(ctx.zone, ctx.x, ctx.y, spot.x, spot.y)
	end
	e.chain, e.at = Q.ChainFor(e.id)
	return e
end

-- The one order (Q.Compare: ready, in my log, ..., then by level and title).
local function ByCompare(a, b)
	if a.id == b.id then
		return false
	end
	return V.Before(a.id, b.id)
end

-- How many steps of a chain I've done ("2/4": done of all for me).
local function ChainDone(chain)
	local done = 0
	for _, id in ipairs(chain) do
		if Q.StatusOf(id) == "done" then
			done = done + 1
		end
	end
	return done
end

-- The groups: { { key, title, note, here, list } }. Ready to turn in (every zone) always first; then
-- by zone (mine first, the others by their lowest level), by level, or by storyline (its steps in
-- order; the quests in none last). Within a group the one order (Q.Compare: by level), a storyline's
-- in its steps' order.
function C.Groups(list, sort)
	local ready, rest = {}, {}
	for _, e in ipairs(list) do
		if e.ready then
			ready[#ready + 1] = e
		else
			rest[#rest + 1] = e
		end
	end
	table.sort(ready, ByCompare)
	local groups = {}
	if ready[1] then
		groups[1] = { key = "ready", title = L["Ready to turn in"], list = ready }
	end
	if not rest[1] then
		return groups
	end
	if sort == "level" then
		table.sort(rest, ByCompare)
		groups[#groups + 1] = { key = "level", title = L["In progress"], list = rest }
		return groups
	end
	local byKey, keyed = {}, {}
	for _, e in ipairs(rest) do
		local key, title
		if sort == "chain" then
			key = e.chain and ("c" .. e.chain[1]) or "none"
			title = e.chain and Q.Title(e.chain[1]) or L["Not in a storyline"]
		else
			key, title = "z" .. tostring(e.zone), e.zoneName
		end
		local g = byKey[key]
		if not g then
			g = { key = key, title = title, list = {}, low = e.level, here = sort ~= "chain" and e.here, chain = sort == "chain" and e.chain }
			byKey[key] = g
			keyed[#keyed + 1] = g
		end
		g.list[#g.list + 1] = e
		g.low = math.min(g.low, e.level)
	end
	for _, g in ipairs(keyed) do
		if sort == "chain" then
			table.sort(g.list, function(a, b)
				if (a.at or 0) ~= (b.at or 0) then
					return (a.at or 0) < (b.at or 0)
				end
				return ByCompare(a, b)
			end)
			if g.chain then
				g.note = ChainDone(g.chain) .. "/" .. #g.chain
			end
		else
			table.sort(g.list, ByCompare)
		end
	end
	table.sort(keyed, function(a, b)
		if (a.key == "none") ~= (b.key == "none") then
			return b.key == "none"
		end
		if (a.here == true) ~= (b.here == true) then
			return a.here == true
		end
		if a.low ~= b.low then
			return a.low < b.low
		end
		return tostring(a.title) < tostring(b.title)
	end)
	for _, g in ipairs(keyed) do
		groups[#groups + 1] = g
	end
	return groups
end

-- The storylines I've started (a step done or in my log) whose next step I can take now (Q.InRange)
-- and isn't in my log, in the one order of their next steps (Q.Compare: for my level, then hard, by
-- level); at most CONTINUE_MAX.
function C.Continue(data, ctx)
	local out = {}
	for _, c in ipairs(data and data.list or {}) do
		if c.take and (c.done > 0 or c.active > 0) and c.done < c.total and Q.Status(c.take) == "available" then
			local q = Q.Quest(c.take)
			local giver = q and q.starts and q.starts[1]
			local point = q and Q.NearestPoint(q.starts, ctx.zone, ctx.x, ctx.y)
			for _, who in ipairs(q and q.starts or {}) do
				point = point or (who.points and who.points[1])
			end
			local level = q and tonumber(q.level)
			out[#out + 1] = { chain = c, id = c.take, giver = giver, point = point, here = point ~= nil and point.map == ctx.zone,
				level = level and level > 0 and level or ctx.me, title = c.title or "?", hard = V.IsHard(c.take) }
		end
	end
	table.sort(out, ByCompare)
	for i = #out, CONTINUE_MAX + 1, -1 do
		out[i] = nil
	end
	return out
end

-- The game's map pin at a row's spot (share: its link in chat too).
local function PinAt(point, share)
	if point and Q.Waypoint then
		Q.Waypoint(point.map, point.x, point.y, share == true)
	end
end

-- A quest row's clicks (as the big window's): a click shows it on the map (Q.OpenBrowser: its zone,
-- picked, its objectives), a right-click opens its chain (Q.OpenChain; in no chain: as a click),
-- Shift-click sets the game's map pin at its spot (Shift-right-click: its link in chat too).
local function QuestClick(id, chained, point, button)
	if IsShiftKeyDown and IsShiftKeyDown() then
		PinAt(point, button == "RightButton")
	elseif button == "RightButton" and chained then
		V.OpenChain(id)
	else
		V.OpenQuest(id)
	end
end

-- A turn-in: "Gryan Stoutmantle" (in another zone: ", Westfall"; an object or item says so).
local function EnderText(e)
	local who = e.ender
	if not who then
		return ""
	end
	local name = who.name or L["unknown"]
	local point = who.points and who.points[1]
	local zone = point and point.map
	if e.spot and e.ready then
		zone = e.spot.map
	end
	-- (its zone when it isn't the quest's own, or in the ready ones of every zone when it isn't mine)
	if zone and (zone ~= e.zone or (e.ready and zone ~= e.ctxZone)) and not (e.ready and zone == e.ctxZone) then
		name = name .. ", " .. (Q.MapName(zone) or tostring(zone))
	end
	return name
end

-- The objective column: "3/10 Defias Bandit" (the first not done), "Ready to turn in", how far.
local function TodoText(e)
	if e.ready then
		return V.Hex(TONE.done) .. L["Ready to turn in"] .. "|r"
	end
	local o = e.todo
	if not o then
		return ""
	end
	local text = (o.need and o.need > 0) and (tostring(o.have or 0) .. "/" .. o.need .. " " .. (o.name or o.text)) or o.text
	if e.far and e.spotObjective then
		text = text .. GREY .. " · " .. e.far .. "|r"
	end
	return text
end

function C.QuestEnter(self)
	local e = self.entry and self.entry.e
	if not e then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(V.Title(e.id, e.quest), 1, 1, 1)
	if e.ready then
		GameTooltip:AddLine(L["Ready to turn in"], TONE.done[1], TONE.done[2], TONE.done[3])
	else
		GameTooltip:AddLine(L["In your quest log"], TONE.active[1], TONE.active[2], TONE.active[3])
	end
	GameTooltip:AddLine(e.zoneName, 0.8, 0.8, 0.8)
	if e.chain then
		GameTooltip:AddLine(L["Step %d of %d · %s"]:format(e.at, #e.chain, Q.Title(e.chain[1])), 1, 0.82, 0, true)
	end
	for _, o in ipairs(e.objectives) do
		local line = (o.done and (Q.Icon("done", 12) .. " ") or "- ") .. o.text
		local data = o.data
		if not o.done and data and data.kind == "item" and data.sources and data.sources[1] then
			local s = data.sources[1]
			line = line .. GREY .. " " .. L["(from %s)"]:format((s.name or L["unknown"]) .. (tonumber(s.chance) and (", " .. Q.Percent(s.chance)) or "")) .. "|r"
		end
		if o.done then
			GameTooltip:AddLine(line, 0.55, 0.55, 0.55, true)
		else
			GameTooltip:AddLine(line, 1, 1, 1, true)
		end
	end
	if e.ender then
		GameTooltip:AddLine(L["Turn in: %s"]:format(EnderText(e)) .. (e.ready and e.far and (" · " .. e.far) or ""), 0.8, 0.8, 0.8, true)
	end
	GameTooltip:AddLine(L["Click: show it on the map"], 0.5, 0.75, 1)
	if e.chain then
		GameTooltip:AddLine(L["Right-click (or %s): open the chain"]:format(e.at .. "/" .. #e.chain), 0.5, 0.75, 1)
	end
	if e.spot then
		local where = e.spotObjective and (e.spotObjective.name or e.spotObjective.text) or (e.ender and e.ender.name) or ""
		GameTooltip:AddLine(L["Shift-click: map pin at %s"]:format(where), 0.5, 0.75, 1, true)
	end
	GameTooltip:Show()
end

-- A quest of my log, one line in columns: its verb icon, "[12] Title", its chain's "2/4" (a badge: a
-- click opens the chain), its first objective not done ("3/10 Defias Bandit", how far) or "Ready to
-- turn in", and at the right where it's turned in. A click shows it on the window's map, a right-click
-- opens its chain, Shift-click sets the map pin where to go.
function C.NewQuest(parent, width)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, QUEST_H)
	b:SetHighlightTexture(T.highlight, "ADD")
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b.Line = b:CreateTexture(nil, "BACKGROUND")
	b.Line:SetPoint("BOTTOMLEFT")
	b.Line:SetPoint("BOTTOMRIGHT")
	b.Line:SetHeight(1)
	b.Line:SetColorTexture(1, 1, 1, 0.04)
	b.Icon = b:CreateTexture(nil, "ARTWORK")
	b.Icon:SetSize(16, 16)
	b.Icon:SetPoint("LEFT", 6, 0)
	local function Column(font, justify)
		local fs = b:CreateFontString(nil, "OVERLAY", font)
		fs:SetJustifyH(justify or "LEFT")
		fs:SetWordWrap(false)
		return fs
	end
	b.Title = Column("GameFontHighlight")
	b.Title:SetPoint("LEFT", 28, 0)
	b.Badge = V.NewBadge(b)
	b.Badge:SetPoint("LEFT", b.Title, "RIGHT", 4, 0)
	b.Todo = Column("GameFontHighlightSmall")
	b.Todo:SetPoint("LEFT", b.Badge, "RIGHT", 12, 0)
	b.Todo:SetTextColor(0.85, 0.85, 0.85)
	b.Right = Column("GameFontDisableSmall", "RIGHT")
	b.Right:SetPoint("RIGHT", -8, 0)
	b:SetScript("OnEnter", C.QuestEnter)
	b:SetScript("OnLeave", V.Untip)
	b:SetScript("OnClick", function(self, button)
		local e = self.entry and self.entry.e
		if not e then
			return
		end
		V.Untip(self)
		QuestClick(e.id, e.chain ~= nil, e.spot, button)
	end)
	return b
end

function C.FillQuest(b, entry)
	local e, w = entry.e, entry.inst.listW
	b:SetWidth(w)
	V.Art(b.Icon, e.ready and "QuestTurnin" or "SideInProgressquesticon", e.ready and T.turnin or T.progress)
	local titleW = math.floor(w * 0.38)
	local todoW = math.floor(w * 0.3)
	b.Title:SetWidth(titleW - 28)
	b.Title:SetText(V.Title(e.id, e.quest))
	if e.chain then
		V.SetBadge(b.Badge, e.id, e.at .. "/" .. #e.chain, Q.Title(e.chain[1]), L["Step %d of %d"]:format(e.at, #e.chain))
	else
		V.SetBadge(b.Badge, nil, nil)
	end
	b.Todo:SetWidth(todoW)
	b.Todo:SetText(TodoText(e))
	b.Right:SetWidth(math.max(40, w - titleW - 40 - 16 - todoW - 16))
	local ender = EnderText(e)
	b.Right:SetText(ender ~= "" and (Q.Icon(e.ready and "turnin" or "progress", 12) .. " " .. ender .. (e.ready and e.far and (" · " .. e.far) or "")) or "")
end

-- A group's heading: its name in gold, a grey note (how many, "you're here", a chain's "2/4"), a rule.
function C.NewHead(parent, width)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(width, HEAD_H)
	f.Text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.Text:SetPoint("BOTTOMLEFT", 4, 6)
	f.Text:SetJustifyH("LEFT")
	f.Text:SetWordWrap(false)
	f.Rule = f:CreateTexture(nil, "ARTWORK")
	f.Rule:SetPoint("BOTTOMLEFT", 0, 2)
	f.Rule:SetPoint("BOTTOMRIGHT", 0, 2)
	f.Rule:SetHeight(1)
	f.Rule:SetColorTexture(1, 0.82, 0, 0.25)
	return f
end

function C.FillHead(f, entry)
	f:SetWidth(entry.inst.listW)
	f.Text:SetWidth(entry.inst.listW - 8)
	f.Text:SetText(GOLD .. tostring(entry.text) .. "|r" .. (entry.note and ("  " .. GREY .. entry.note .. "|r") or ""))
end

function C.NewNote(parent, width)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(width, NOTE_H)
	f.Text = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.Text:SetPoint("LEFT", 8, 0)
	f.Text:SetJustifyH("LEFT")
	f.Text:SetWordWrap(false)
	return f
end

function C.FillNote(f, entry)
	f:SetWidth(entry.inst.listW)
	f.Text:SetWidth(entry.inst.listW - 16)
	f.Text:SetText(entry.text)
end

function C.NextEnter(self)
	local n = self.entry and self.entry.n
	if not n then
		return
	end
	local c = n.chain
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(c.title or "?", 1, 0.82, 0)
	GameTooltip:AddLine(L["%d of %d steps done"]:format(c.done, c.total), 1, 1, 1)
	GameTooltip:AddLine(L["Next: %s"]:format(V.Title(n.id)), 1, 1, 1, true)
	if n.hard then
		GameTooltip:AddLine(V.TierWord("difficult"), V.TierRGB("difficult"))
	end
	if n.giver then
		local zone = n.point and Q.MapName(n.point.map)
		GameTooltip:AddLine(L["From %s"]:format((n.giver.name or L["unknown"]) .. (zone and (", " .. zone) or "")), 0.8, 0.8, 0.8, true)
	end
	GameTooltip:AddLine(L["Click: show it on the map"], 0.5, 0.75, 1)
	GameTooltip:AddLine(L["Right-click (or %s): open the chain"]:format(c.done .. "/" .. c.total), 0.5, 0.75, 1)
	if n.point then
		GameTooltip:AddLine(L["Shift-click: map pin at %s"]:format(n.giver and n.giver.name or ""), 0.5, 0.75, 1, true)
	end
	GameTooltip:Show()
end

-- A storyline to go on with: "<chain> - next: [12] <title>, <giver> (<zone>)", its "3/7" at the right
-- (a badge: a click opens the chain, its next step picked).
function C.NewNext(parent, width)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, QUEST_H)
	b:SetHighlightTexture(T.highlight, "ADD")
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b.Icon = b:CreateTexture(nil, "ARTWORK")
	b.Icon:SetSize(16, 16)
	b.Icon:SetPoint("LEFT", 6, 0)
	b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.Text:SetPoint("LEFT", 28, 0)
	b.Text:SetJustifyH("LEFT")
	b.Text:SetWordWrap(false)
	b.Badge = V.NewBadge(b)
	b.Badge:SetPoint("RIGHT", -8, 0)
	b:SetScript("OnEnter", C.NextEnter)
	b:SetScript("OnLeave", V.Untip)
	b:SetScript("OnClick", function(self, button)
		local n = self.entry and self.entry.n
		if not n then
			return
		end
		V.Untip(self)
		QuestClick(n.id, true, n.point, button)
	end)
	return b
end

function C.FillNext(b, entry)
	local n, w = entry.n, entry.inst.listW
	b:SetWidth(w)
	V.Art(b.Icon, "QuestNormal", T.available)
	local title = V.Title(n.id)
	if n.hard then -- (orange: after the ones for my level, marked)
		title = title .. " " .. V.TierHex("difficult") .. "(" .. V.TierWord("difficult") .. ")|r"
	end
	local text
	if n.giver then
		local zone = n.point and Q.MapName(n.point.map) or "?"
		text = L["%s - next: %s, %s (%s)"]:format(GOLD .. n.title .. "|r", title, n.giver.name or L["unknown"], zone)
	else
		text = L["%s - next: %s"]:format(GOLD .. n.title .. "|r", title)
	end
	V.SetBadge(b.Badge, n.id, n.chain.done .. "/" .. n.chain.total, n.title, L["%d of %d steps done"]:format(n.chain.done, n.chain.total))
	b.Text:SetWidth(w - 28 - 60)
	b.Text:SetText(text)
end

function C.SetSort(inst, by)
	V.Saved().mySort = by
	inst:Draw(true)
end

-- The list: the groups of my log, then "Continue your storylines".
function C.Draw(inst, top)
	if inst.noData then
		return
	end
	inst.draws = inst.draws + 1
	V.Status(inst)
	local saved = V.Saved()
	local sort = SORT_LABEL[saved.mySort] and saved.mySort or "zone"
	for _, key in ipairs(SORTS) do
		V.SetChip(inst.sorts[key], SORT_LABEL[key], key == sort)
	end
	local zone, x, y = nil, nil, nil
	if Q.HereZone then
		zone, x, y = Q.HereZone()
	end
	local ctx = { zone = zone, x = x, y = y, zoneName = zone and Q.MapName(zone), me = V.MyLevel() }
	inst.drawnAt = { zone, x, y }
	local list, ready = {}, 0
	for _, e in ipairs(C.Log()) do
		e.ctxZone = zone
		list[#list + 1] = C.Fill(e, ctx)
		ready = ready + (e.ready and 1 or 0)
	end
	inst.quests = list
	inst.Head:SetText(L["%d quests in your log"]:format(#list) .. (ready > 0 and (GREY .. " · |r" .. V.Hex(TONE.done) .. L["%d ready to turn in"]:format(ready) .. "|r") or ""))
	local entries = {}
	local function Add(kind, key, h, fields)
		fields.kind, fields.key, fields.h, fields.inst = kind, key, h, inst
		entries[#entries + 1] = fields
	end
	inst.groups = C.Groups(list, sort)
	for _, g in ipairs(inst.groups) do
		local note = g.note or ("(" .. #g.list .. ")")
		if g.here then
			note = note .. "  " .. "|cff66ccff" .. L["you're here"] .. "|r"
		end
		Add("head", "h" .. g.key, HEAD_H, { text = g.title, note = note })
		for _, e in ipairs(g.list) do
			Add("quest", "q" .. e.id, QUEST_H, { e = e })
		end
	end
	if not list[1] then
		Add("note", "empty", NOTE_H, { text = L["Your quest log is empty. The Zone tab has what you can pick up here."] })
	end
	-- Continue your storylines.
	Add("head", "hcontinue", HEAD_H + 8, { text = L["Continue your storylines"], note = L["started, the next step for your level"] })
	if not Census.data then
		Add("note", "counting", NOTE_H, { text = L["Looking through your storylines..."] })
		inst.continued = {}
	else
		inst.continued = C.Continue(Census.data, ctx)
		for _, n in ipairs(inst.continued) do
			Add("next", "n" .. n.id, QUEST_H, { n = n })
		end
		if not inst.continued[1] then
			Add("note", "none", NOTE_H, { text = L["No storyline you've started has a next step for your level now."] })
		end
	end
	V.Say(inst, nil)
	inst.list:SetEntries(entries, not top)
end

-- Moved far enough (or into another zone) while shown: drawn again (the distances, the order).
function C.Moved(inst)
	local at = inst.drawnAt
	if not (at and Q.HereZone and inst.active) or inst.noData then
		return
	end
	local zone, x, y = Q.HereZone()
	if zone ~= at[1] or (x and not at[2]) or (x and at[2] and math.abs(x - at[2]) + math.abs(y - at[3]) > MOVE_FAR) then
		Census.Due(0)
	end
end

function C.Build(parent)
	local inst = V.NewView(parent, "myquests")
	inst.ownList = true -- (the log shows at once; only "Continue" waits for the counts)
	inst.sorts = {}
	for i = #SORTS, 1, -1 do
		local key = SORTS[i]
		local chip = V.NewChip(inst.frame, function() C.SetSort(inst, key) end)
		chip.tip = SORT_TIP[key]
		inst.sorts[key] = chip
	end
	inst.SortLabel = inst.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	inst.SortLabel:SetText(L["Sort:"])
	inst.Head = inst.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	inst.Head:SetPoint("TOPLEFT", K.PAD, -10)
	inst.Head:SetJustifyH("LEFT")
	inst.Head:SetWordWrap(false)
	inst.list = V.NewList(inst.frame, {
		quest = { new = C.NewQuest, fill = C.FillQuest },
		head = { new = C.NewHead, fill = C.FillHead },
		note = { new = C.NewNote, fill = C.FillNote },
		["next"] = { new = C.NewNext, fill = C.FillNext },
	})
	inst.Layout = function(self)
		local right = nil
		for i = #SORTS, 1, -1 do
			local chip = self.sorts[SORTS[i]]
			V.SetChip(chip, SORT_LABEL[SORTS[i]], chip.on)
			chip:ClearAllPoints()
			if right then
				chip:SetPoint("RIGHT", right, "LEFT", -6, 0)
			else
				chip:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -K.PAD, -6)
			end
			right = chip
		end
		self.SortLabel:ClearAllPoints()
		self.SortLabel:SetPoint("RIGHT", right, "LEFT", -8, 0)
		self.Head:SetPoint("RIGHT", self.SortLabel, "LEFT", -K.PAD, 0)
	end
	inst.Draw = function(self, top)
		V.Fit(self)
		C.Draw(self, top)
	end
	-- Whether I moved, every few seconds, only while it's shown (a child of it: hidden, it doesn't run).
	local mover = CreateFrame("Frame", nil, inst.frame)
	local wait = MOVE_EVERY
	mover:SetScript("OnUpdate", function(_, elapsed)
		wait = wait - elapsed
		if wait <= 0 then
			wait = MOVE_EVERY
			C.Moved(inst)
		end
	end)
	inst.Mover = mover
	return inst
end

---------------------------------------------------------------------------
-- Level path: where to go next, zones as bars across the levels
---------------------------------------------------------------------------

local DONE_RGB = { 0.8, 0.8, 0.8 } -- a level all done: a thin light line (the tiers are full bands)
local HARDER = { trivial = 1, easy = 2, fair = 3, difficult = 4, impossible = 5 }

-- A zone of my side: enough of its quests are for me.
function D.Mine(z)
	return z.total > 0 and (z.total >= 5 or z.total * 4 >= z.count)
end

-- How a level of a zone looks: "done" (all its quests), else the tier most of its quests not done
-- have for me (as many: the harder).
function D.Shade(b)
	if not b or b.total == 0 then
		return nil
	elseif b.done >= b.total then
		return "done"
	end
	local best, most = nil, 0
	for tier, n in pairs(b.tiers) do
		if n > most or (best and n == most and (HARDER[tier] or 0) > (HARDER[best] or 0)) then
			best, most = tier, n
		end
	end
	return best or "done"
end

-- A shade's colour: r, g, b.
function D.RGB(shade)
	if shade == "done" then
		return DONE_RGB[1], DONE_RGB[2], DONE_RGB[3]
	end
	return V.TierRGB(shade)
end

-- A shade's word ("done", or the tier's).
function D.Word(shade)
	return shade == "done" and L["done"] or V.TierWord(shade)
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
			m = { total = 0, done = 0, tiers = {} }
			merged[at] = m
		end
		m.total, m.done = m.total + b.total, m.done + b.done
		for tier, n in pairs(b.tiers) do
			m.tiers[tier] = (m.tiers[tier] or 0) + n
		end
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

-- The most for my level first, then the most hard ones, then the zones my level is in (the nearest),
-- the lowest.
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
		if a.hard ~= b.hard then
			return a.hard > b.hard
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

-- "7 for your level · 2 hard" (what's there), coloured; "" for nothing.
function D.Counts(z)
	local parts = {}
	if z.near > 0 then
		parts[1] = V.Hex(TONE.available) .. L["%d for your level"]:format(z.near) .. "|r"
	end
	if z.hard > 0 then
		parts[#parts + 1] = V.TierHex("difficult") .. L["%d hard"]:format(z.hard) .. "|r"
	end
	return table.concat(parts, GREY .. " · |r")
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
	if z.hard > 0 then
		GameTooltip:AddLine(L["%d hard"]:format(z.hard), V.TierRGB("difficult"))
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
	-- What's left by difficulty for me (every quest not done: to take, in my log, later), the
	-- easiest first, grey last.
	local any = false
	for i = 2, #TIERS + 1 do
		local tier = TIERS[i] or TIERS[1]
		local n = z.tiers[tier] or 0
		if n > 0 then
			if not any then
				any = true
				GameTooltip:AddLine(L["Left to do, by difficulty:"], 0.8, 0.8, 0.8)
			end
			GameTooltip:AddLine("  " .. L["%s: %d"]:format(V.TierWord(tier), n), V.TierRGB(tier))
		end
	end
	for _, run in ipairs(e.runs) do
		local span = run[1] == run[2] and tostring(run[1]) or (run[1] .. "-" .. run[2])
		GameTooltip:AddLine(L["Level %s: %s"]:format(span, D.Word(run[3])), D.RGB(run[3]))
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
	if z.near > 0 or z.hard > 0 then
		b.Right:SetText(D.Counts(z))
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
		local r, g, bl = D.RGB(run[3])
		t:SetColorTexture(r, g, bl, 0.9)
		place(t, run[1], run[2], run[3] == "done" and 2 or barH)
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
			if all or z.near > 0 or z.hard > 0 or friends[z.map] then
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
	elseif best and best.hard > 0 then
		inst.Head:SetText(L["Only hard ones for your level: %s has %d."]:format(GOLD .. best.name .. "|r", best.hard))
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
	-- The legend: each tier's colour and word, done (a thin line), my level's line.
	local legend = {}
	for i = 2, #TIERS do
		legend[#legend + 1] = V.TierHex(TIERS[i]) .. "|T" .. T.flat .. ":10:10|t " .. V.TierWord(TIERS[i]) .. "|r"
	end
	legend[#legend + 1] = V.TierHex("trivial") .. "|T" .. T.flat .. ":10:10|t " .. V.TierWord("trivial") .. "|r"
	legend[#legend + 1] = V.Hex(DONE_RGB) .. "|T" .. T.flat .. ":10:2|t " .. L["Done"] .. "|r"
	legend[#legend + 1] = GOLD .. "| " .. L["Your level"] .. "|r"
	inst.Legend:SetText(table.concat(legend, "   "))
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
	{ key = "myquests", label = L["My quests"], build = C.Build },
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
