local _, ns = ...
local LT = ns.LT
local L = ns.L
local C = ns.Chronicle

-- Chronicle's Graphs page: cards drawn with plain textures (bars, with a gradient), line objects
-- (the session curve) and font strings, on the window's scroll content. Every object comes from
-- a pool and is reused on the next draw, so redrawing creates nothing new once the page has been
-- drawn; the window draws the page only when it's opened and at most every few seconds after.
--
--   Last 14 days      bars per day: time played, XP, quests or kills (buttons switch)
--   This session      XP over the session, a line with a soft fill under it
--   Time per level    a bar per level, green (fast) to red (slow)
--   Favourite zones | Deadliest foes        horizontal bars
--   On the road     | Loot by quality       one split bar each, with a legend

local CARD_GAP, PAD = 12, 10
local HEADER = 24                -- card title row
local GRID = { 0.08, 0.08, 0.08 } -- faint guide lines
local BAR_BLUE = { 0.25, 0.6, 1 }
local BAR_TODAY = { 1, 0.78, 0.2 }
local LINE_COLOR = { 0.35, 0.85, 0.45 }
local DAYS = 14
local LEVELS = 20
local METRICS = { "played", "xp", "quests", "kills" }

local G = {}
C.Graphs = G

---------------------------------------------------------------------------
-- Canvas: pooled drawing objects on one parent frame
---------------------------------------------------------------------------

local Canvas = {}
Canvas.__index = Canvas

function G.NewCanvas(parent)
	return setmetatable({ parent = parent, pools = { tex = {}, line = {}, text = {}, hover = {} },
		used = { tex = 0, line = 0, text = 0, hover = 0 } }, Canvas)
end

local function Take(canvas, kind, create)
	local used = canvas.used[kind] + 1
	canvas.used[kind] = used
	local pool = canvas.pools[kind]
	local object = pool[used]
	if not object then
		object = create()
		pool[used] = object
	end
	object:Show()
	return object
end

-- Hides everything; the next draw takes objects from the start again.
function Canvas:Reset()
	for kind, pool in pairs(self.pools) do
		for _, object in ipairs(pool) do
			object:Hide()
		end
		self.used[kind] = 0
	end
end

-- A rectangle at x, y (from the top left of the canvas), w x h.
function Canvas:Rect(x, y, w, h, r, g, b, a, layer)
	local t = Take(self, "tex", function() return self.parent:CreateTexture() end)
	t:SetDrawLayer(layer or "ARTWORK")
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", self.parent, "TOPLEFT", x, -y)
	t:SetSize(math.max(w, 0.1), math.max(h, 0.1))
	t:SetColorTexture(r, g, b, a or 1)
	return t
end

-- A bar that is brighter at the top.
function Canvas:Bar(x, y, w, h, color, alpha)
	local t = self:Rect(x, y, w, h, 1, 1, 1, 1)
	local r, g, b = color[1], color[2], color[3]
	t:SetGradient("VERTICAL", CreateColor(r * 0.45, g * 0.45, b * 0.45, alpha or 0.9), CreateColor(r, g, b, alpha or 1))
	return t
end

function Canvas:Line(x1, y1, x2, y2, color, thickness)
	local line = Take(self, "line", function() return self.parent:CreateLine(nil, "OVERLAY") end)
	line:SetStartPoint("TOPLEFT", self.parent, x1, -y1)
	line:SetEndPoint("TOPLEFT", self.parent, x2, -y2)
	line:SetThickness(thickness or 2)
	line:SetColorTexture(color[1], color[2], color[3], 1)
	return line
end

function Canvas:Text(text, x, y, font, justify, width)
	local fs = Take(self, "text", function()
		local f = self.parent:CreateFontString(nil, "OVERLAY")
		f:SetWordWrap(false)
		return f
	end)
	fs:SetFontObject(font or "GameFontHighlightSmall")
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWidth(width or 0)
	fs:ClearAllPoints()
	local anchor = justify == "RIGHT" and "TOPRIGHT" or (justify == "CENTER" and "TOP" or "TOPLEFT")
	local ax = justify == "RIGHT" and x + (width or 0) or (justify == "CENTER" and x + (width or 0) / 2 or x)
	fs:SetPoint(anchor, self.parent, "TOPLEFT", ax, -y)
	fs:SetText(text)
	return fs
end

-- An invisible area that shows a tooltip: lines = { title, line, ... }.
local function HoverEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText(self.lines[1], 1, 0.82, 0)
	for i = 2, #self.lines do
		GameTooltip:AddLine(self.lines[i], 1, 1, 1)
	end
	GameTooltip:Show()
end

function Canvas:Hover(x, y, w, h, lines)
	local f = Take(self, "hover", function()
		local frame = CreateFrame("Frame", nil, self.parent)
		frame:EnableMouse(true)
		frame:SetScript("OnEnter", HoverEnter)
		frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return frame
	end)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", self.parent, "TOPLEFT", x, -y)
	f:SetSize(math.max(w, 1), math.max(h, 1))
	f.lines = lines
	return f
end

---------------------------------------------------------------------------
-- Building blocks
---------------------------------------------------------------------------

-- A card with a title (and an optional note on the right); returns the inner area.
local function Card(canvas, x, y, w, h, title, note)
	canvas:Rect(x, y, w, h, 0, 0, 0, 0.35, "BACKGROUND")
	canvas:Rect(x, y, w, 1, 1, 0.82, 0, 0.35, "BORDER")
	canvas:Text(title, x + PAD, y + 7, "GameFontNormal", "LEFT", w / 2)
	if note then
		canvas:Text(note, x + w / 2, y + 9, "GameFontHighlightSmall", "RIGHT", w / 2 - PAD)
	end
	return x + PAD, y + HEADER + 4, w - 2 * PAD, h - HEADER - 4 - PAD
end

local function Empty(canvas, x, y, w, h, text)
	canvas:Text("|cff888888" .. text .. "|r", x, y + h / 2 - 6, "GameFontHighlightSmall", "CENTER", w)
end

-- Vertical bars: items = { { value, label, tooltip = { ... }, color } }, with faint guide lines
-- and labels under the bars.
local function Bars(canvas, x, y, w, h, items, color)
	local max = 0
	for _, item in ipairs(items) do
		max = math.max(max, item.value)
	end
	local plotH = h - 14
	for i = 1, 3 do
		canvas:Rect(x, y + plotH * (1 - i / 3), w, 1, 1, 1, 1, GRID[i], "BORDER")
	end
	local slot = w / math.max(#items, 1)
	local barW = math.max(slot * 0.68, 2)
	for i, item in ipairs(items) do
		local bx = x + (i - 1) * slot + (slot - barW) / 2
		local bh = max > 0 and plotH * item.value / max or 0
		if bh > 0 then
			canvas:Bar(bx, y + plotH - bh, barW, bh, item.color or color)
		end
		canvas:Text(item.label, x + (i - 1) * slot, y + plotH + 2, "GameFontHighlightSmall", "CENTER", slot)
		canvas:Hover(x + (i - 1) * slot, y, slot, h, item.tooltip)
	end
end

-- Horizontal bars with a name on the left and a value on the right.
local function HBars(canvas, x, y, w, h, items, color)
	local max, rowH = 0, math.min(18, h / math.max(#items, 1))
	for _, item in ipairs(items) do
		max = math.max(max, item.value)
	end
	local nameW = w * 0.42
	for i, item in ipairs(items) do
		local ry = y + (i - 1) * rowH
		canvas:Text(item.label, x, ry + 2, "GameFontHighlightSmall", "LEFT", nameW - 4)
		local barW = max > 0 and (w - nameW) * item.value / max or 0
		canvas:Rect(x + nameW, ry + 2, w - nameW, rowH - 5, 1, 1, 1, 0.05, "BORDER")
		if barW > 0 then
			canvas:Bar(x + nameW, ry + 2, barW, rowH - 5, color)
		end
		canvas:Text(item.text, x + nameW, ry + 2, "GameFontHighlightSmall", "RIGHT", w - nameW - 4)
	end
end

-- One bar split into parts { value, label, text, color } plus a legend below it.
local function Split(canvas, x, y, w, h, parts)
	local total = 0
	for _, part in ipairs(parts) do
		total = total + part.value
	end
	local bx = x
	for _, part in ipairs(parts) do
		local pw = total > 0 and w * part.value / total or 0
		if pw > 0 then
			canvas:Bar(bx, y, pw, 14, part.color)
			canvas:Hover(bx, y, pw, 14, { part.label, part.text })
			bx = bx + pw
		end
	end
	local columns = 2
	local colW = w / columns
	for i, part in ipairs(parts) do
		local lx = x + ((i - 1) % columns) * colW
		local ly = y + 22 + math.floor((i - 1) / columns) * 16
		canvas:Rect(lx, ly + 3, 8, 8, part.color[1], part.color[2], part.color[3], 1)
		canvas:Text(("%s  |cffffffff%s|r"):format(part.label, part.text), lx + 12, ly + 1, "GameFontHighlightSmall", "LEFT", colW - 14)
	end
end

-- A line with a soft fill under it: points = { { x = 0..1, y = value } }.
local function Curve(canvas, x, y, w, h, points, color)
	local max = 0
	for _, p in ipairs(points) do
		max = math.max(max, p.y)
	end
	for i = 1, 3 do
		canvas:Rect(x, y + h * (1 - i / 3), w, 1, 1, 1, 1, GRID[i], "BORDER")
	end
	local function At(p)
		return x + p.x * w, y + h - (max > 0 and h * p.y / max or 0)
	end
	local columns = math.min(#points, 60) -- the fill: thin columns, fading downwards
	for i = 1, columns do
		local p = points[math.max(1, math.floor(i / columns * #points + 0.5))]
		local px, py = At(p)
		local colW = w / columns
		local t = canvas:Rect(x + (i - 1) * colW, py, colW + 0.5, y + h - py, 1, 1, 1, 1)
		t:SetGradient("VERTICAL", CreateColor(color[1], color[2], color[3], 0), CreateColor(color[1], color[2], color[3], 0.3))
	end
	for i = 2, #points do
		local x1, y1 = At(points[i - 1])
		local x2, y2 = At(points[i])
		canvas:Line(x1, y1, x2, y2, color, 2)
	end
	canvas:Text(C.Number(max), x - 2, y - 2, "GameFontHighlightSmall", "LEFT", w)
end

-- Green for the fastest, red for the slowest.
local function Heat(fraction)
	return { 0.3 + 0.7 * fraction, 0.9 - 0.6 * fraction, 0.3 }
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

local METRIC_LABEL = {
	played = function() return L["Time"] end,
	xp = function() return L["Experience"] end,
	quests = function() return L["Quests"] end,
	kills = function() return L["Killing blows"] end,
}

local function MetricText(metric, value)
	return metric == "played" and C.Duration(value) or C.Number(value)
end

local function Days(canvas, x, y, w, c, metric)
	local h = 170
	local items, total = {}, 0
	local now = time()
	for i = DAYS - 1, 0, -1 do
		local t = now - i * 86400
		local day = date("%Y-%m-%d", t)
		local value = (c.daily[day] or {})[metric] or 0
		total = total + value
		items[#items + 1] = { value = value, label = date("%d", t), color = i == 0 and BAR_TODAY or nil,
			tooltip = { date(L["%Y-%m-%d"], t), METRIC_LABEL[metric]() .. ": " .. MetricText(metric, value) } }
	end
	local ix, iy, iw, ih = Card(canvas, x, y, w, h, L["Last 14 days"],
		METRIC_LABEL[metric]() .. ": " .. MetricText(metric, total))
	Bars(canvas, ix, iy + 22, iw, ih - 22, items, BAR_BLUE)
	return h, ix, iy
end

local function Session(canvas, x, y, w, c)
	local h = 140
	local s = c.session
	local series = s and s.series or {}
	local last = series[#series]
	local note
	if last and last.played > 0 then
		note = L["+%s XP, %s per hour"]:format(C.Number(last.xp), C.Number(last.xp / last.played * 3600))
	end
	local ix, iy, iw, ih = Card(canvas, x, y, w, h, L["This session"], note)
	if #series < 2 or last.played <= 0 then
		Empty(canvas, ix, iy, iw, ih, L["Not enough data yet: check back in a few minutes."])
		return h
	end
	local points = {}
	for _, p in ipairs(series) do
		points[#points + 1] = { x = p.played / last.played, y = p.xp }
	end
	Curve(canvas, ix, iy + 10, iw, ih - 10, points, LINE_COLOR)
	canvas:Text(C.Duration(last.played), ix, iy + ih + 1, "GameFontHighlightSmall", "RIGHT", iw)
	return h
end

local function Levels(canvas, x, y, w, c)
	local h = 150
	local levels = {}
	for level in pairs(c.levelTimes) do
		levels[#levels + 1] = level
	end
	table.sort(levels)
	while #levels > LEVELS do
		table.remove(levels, 1)
	end
	local fastest, slowest
	for _, level in ipairs(levels) do
		local t = c.levelTimes[level]
		if not fastest or t < c.levelTimes[fastest] then fastest = level end
		if not slowest or t > c.levelTimes[slowest] then slowest = level end
	end
	local note = fastest and L["Fastest: %d (%s), slowest: %d (%s)"]:format(fastest, C.Duration(c.levelTimes[fastest]),
		slowest, C.Duration(c.levelTimes[slowest])) or nil
	local ix, iy, iw, ih = Card(canvas, x, y, w, h, L["Time per level"], note)
	if #levels == 0 then
		Empty(canvas, ix, iy, iw, ih, L["Level up once with Chronicle on to see this."])
		return h
	end
	local low, high = c.levelTimes[fastest], c.levelTimes[slowest]
	local items = {}
	for _, level in ipairs(levels) do
		local t = c.levelTimes[level]
		items[#items + 1] = { value = t, label = tostring(level), color = Heat(high > low and (t - low) / (high - low) or 0),
			tooltip = { L["Level %d"]:format(level), C.Duration(t) } }
	end
	Bars(canvas, ix, iy, iw, ih, items, BAR_BLUE)
	return h
end

local function Top(t, count)
	local list = {}
	for key, value in pairs(t) do
		list[#list + 1] = { key = key, value = value }
	end
	table.sort(list, function(a, b) return a.value > b.value or (a.value == b.value and a.key < b.key) end)
	while #list > count do
		table.remove(list)
	end
	return list
end

local function Zones(canvas, x, y, w, h, c)
	local ix, iy, iw, ih = Card(canvas, x, y, w, h, L["Favourite zones"])
	local items = {}
	for _, entry in ipairs(Top(c.zoneTime, 5)) do
		items[#items + 1] = { label = entry.key, value = entry.value, text = C.Duration(entry.value) }
	end
	if #items == 0 then
		Empty(canvas, ix, iy, iw, ih, L["Nothing recorded yet."])
	else
		HBars(canvas, ix, iy, iw, ih, items, { 0.4, 0.75, 0.4 })
	end
end

local function Foes(canvas, x, y, w, h, c)
	local ix, iy, iw, ih = Card(canvas, x, y, w, h, L["Deadliest foes"])
	local items = {}
	for _, entry in ipairs(Top(c.killers, 5)) do
		items[#items + 1] = { label = entry.key, value = entry.value, text = tostring(entry.value) }
	end
	if #items == 0 then
		Empty(canvas, ix, iy, iw, ih, L["No deaths yet."])
	else
		HBars(canvas, ix, iy, iw, ih, items, { 0.9, 0.3, 0.25 })
	end
end

local function Travel(canvas, x, y, w, h, c)
	local ix, iy, iw, ih = Card(canvas, x, y, w, h, L["On the road"])
	local s = c.stats
	local parts = {
		{ value = s.walked, label = L["On foot"], text = C.Distance(s.walked), color = { 0.85, 0.7, 0.4 } },
		{ value = s.ridden, label = L["Riding"], text = C.Distance(s.ridden), color = { 0.6, 0.45, 0.25 } },
		{ value = s.swum, label = L["Swimming"], text = C.Distance(s.swum), color = { 0.3, 0.6, 0.95 } },
		{ value = s.flown, label = L["Flight paths"], text = C.Distance(s.flown), color = { 0.75, 0.75, 0.9 } },
	}
	if s.walked + s.ridden + s.swum + s.flown <= 0 then
		Empty(canvas, ix, iy, iw, ih, L["Nothing recorded yet."])
	else
		Split(canvas, ix, iy, iw, ih, parts)
	end
end

local QUALITY = { [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 } }

local function Loot(canvas, x, y, w, h, c)
	local ix, iy, iw, ih = Card(canvas, x, y, w, h, L["Loot by quality"])
	local s = c.stats
	local parts = {
		{ value = s.loot2, label = L["Uncommon items"], text = C.Number(s.loot2), color = QUALITY[2] },
		{ value = s.loot3, label = L["Rare items"], text = C.Number(s.loot3), color = QUALITY[3] },
		{ value = s.loot4, label = L["Epic items"], text = C.Number(s.loot4), color = QUALITY[4] },
	}
	if s.loot2 + s.loot3 + s.loot4 <= 0 then
		Empty(canvas, ix, iy, iw, ih, L["Nothing recorded yet."])
	else
		Split(canvas, ix, iy, iw, ih, parts)
	end
end

-- Draws the whole page for record c; state.metric is the 14-day chart's metric, state.buttons
-- the four metric buttons (created by the window). Returns the page height.
function G.Draw(canvas, width, c, state)
	canvas:Reset()
	local y = 0
	local h, ix, iy = Days(canvas, 0, y, width, c, state.metric)
	-- The metric buttons sit in the card's header row.
	for i, metric in ipairs(METRICS) do
		local button = state.buttons[metric]
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", canvas.parent, "TOPLEFT", ix + (i - 1) * 84, -(iy - 2))
		button:SetEnabled(metric ~= state.metric)
		button:Show()
	end
	y = y + h + CARD_GAP
	if c == C.Char() then -- a session only exists for the character you're playing
		y = y + Session(canvas, 0, y, width, c) + CARD_GAP
	end
	y = y + Levels(canvas, 0, y, width, c) + CARD_GAP
	local half = (width - CARD_GAP) / 2
	Zones(canvas, 0, y, half, 120, c)
	Foes(canvas, half + CARD_GAP, y, half, 120, c)
	y = y + 120 + CARD_GAP
	Travel(canvas, 0, y, half, 90, c)
	Loot(canvas, half + CARD_GAP, y, half, 90, c)
	return y + 90 + 4
end

G.METRICS = METRICS
G.METRIC_LABEL = METRIC_LABEL
