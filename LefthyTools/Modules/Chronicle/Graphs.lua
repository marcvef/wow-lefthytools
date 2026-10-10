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
local METRICS = { "played", "xp", "quests", "kills" } -- (time AFK and jumps go per account: the Compare page)

local G = {}
C.Graphs = G

-- Each kind of journal entry's icon (the window's timelines, the Compare page's symbols).
local ICONS = {
	level = "Interface\\Icons\\Achievement_Level_10",
	death = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
	zone = "Interface\\Icons\\INV_Misc_Map_01",
	dungeon = "Interface\\Icons\\INV_Misc_Key_14",
	boss = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
	rare = "Interface\\Icons\\Ability_Hunter_SniperShot",
	loot = "Interface\\Icons\\INV_Misc_Bag_10",
	mount = "Interface\\Icons\\Ability_Mount_RidingHorse",
	pet = "Interface\\Icons\\INV_Box_PetCarrier_01",
	toy = "Interface\\Icons\\INV_Misc_Toy_10",
	achievement = "Interface\\Icons\\Achievement_General",
	quests = "Interface\\Icons\\INV_Misc_Note_01",
	gold = "Interface\\Icons\\INV_Misc_Coin_01",
	profession = "Interface\\Icons\\INV_Misc_Gear_01",
	quest = "Interface\\Icons\\INV_Misc_Note_02",
	online = "Interface\\FriendsFrame\\StatusIcon-Online",
	offline = "Interface\\FriendsFrame\\StatusIcon-Offline",
}
G.EVENT_ICONS = ICONS

-- The highlights the Compare page marks on the lines, the most notable first (a day shows its first).
G.MARK_KINDS = { "death", "boss", "level", "dungeon", "rare", "loot", "achievement", "mount", "gold" }

-- An icon in text, its border trimmed.
function G.IconText(icon, size)
	return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(tostring(icon), size or 14, size or 14)
end

---------------------------------------------------------------------------
-- Canvas: pooled drawing objects on one parent frame
---------------------------------------------------------------------------

local Canvas = {}
Canvas.__index = Canvas

function G.NewCanvas(parent)
	return setmetatable({ parent = parent, pools = { tex = {}, line = {}, text = {}, hover = {}, icon = {} },
		used = { tex = 0, line = 0, text = 0, hover = 0, icon = 0 } }, Canvas)
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
	if t.hasGradient then -- it was a bar last time: the gradient outlives SetColorTexture
		t:SetVertexColor(1, 1, 1, 1)
		t.hasGradient = nil
	end
	return t
end

-- A vertical gradient on a texture from Rect (marked, so Rect resets it when the texture is reused).
function Canvas:Gradient(t, bottom, top)
	t:SetGradient("VERTICAL", bottom, top)
	t.hasGradient = true
	return t
end

-- A bar that is brighter at the top.
function Canvas:Bar(x, y, w, h, color, alpha)
	local t = self:Rect(x, y, w, h, 1, 1, 1, 1)
	local r, g, b = color[1], color[2], color[3]
	return self:Gradient(t, CreateColor(r * 0.45, g * 0.45, b * 0.45, alpha or 0.9), CreateColor(r, g, b, alpha or 1))
end

-- An icon (a path or file id), its border trimmed, above lines and bars; dim: greyed out.
function Canvas:Icon(icon, x, y, size, dim)
	local t = Take(self, "icon", function()
		local tex = self.parent:CreateTexture()
		tex:SetDrawLayer("OVERLAY", 7)
		tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		return tex
	end)
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", self.parent, "TOPLEFT", x, -y)
	t:SetSize(size, size)
	t:SetTexture(icon)
	t:SetDesaturated(dim and true or false)
	t:SetAlpha(dim and 0.45 or 1)
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

-- An invisible area that shows a tooltip: lines = { title, line, ... } (nil: none); onClick(button)
-- makes it clickable.
local function HoverEnter(self)
	if not self.lines then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText(self.lines[1], 1, 0.82, 0)
	for i = 2, #self.lines do
		GameTooltip:AddLine(self.lines[i], 1, 1, 1)
	end
	GameTooltip:Show()
end

-- raised: above the other hover areas (a symbol on a chart, inside its day's area).
function Canvas:Hover(x, y, w, h, lines, onClick, raised)
	local f = Take(self, "hover", function()
		local frame = CreateFrame("Frame", nil, self.parent)
		frame:EnableMouse(true)
		frame:SetScript("OnEnter", HoverEnter)
		frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
		frame:SetScript("OnMouseUp", function(it, button)
			if it.onClick then
				it.onClick(button)
			end
		end)
		return frame
	end)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", self.parent, "TOPLEFT", x, -y)
	f:SetSize(math.max(w, 1), math.max(h, 1))
	f:SetFrameLevel(self.parent:GetFrameLevel() + (raised and 4 or 1)) -- (a reused one may have been raised)
	f.lines, f.onClick, f.raised = lines, onClick, raised
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
		canvas:Gradient(t, CreateColor(color[1], color[2], color[3], 0), CreateColor(color[1], color[2], color[3], 0.3))
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
	afk = function() return L["Time AFK"] end, -- the Martin tracker
}

local function MetricText(metric, value)
	return (metric == "played" or metric == "afk") and C.Duration(value) or C.Number(value)
end

local function Days(canvas, x, y, w, c, metric)
	local h = 170
	local items, total, played = {}, 0, 0
	for i = DAYS - 1, 0, -1 do
		local t = C.DayAgo(i)
		local day = date("%Y-%m-%d", t)
		local value = (c.daily[day] or {})[metric] or 0
		total, played = total + value, played + ((c.daily[day] or {}).played or 0)
		items[#items + 1] = { value = value, label = date("%d", t), color = i == 0 and BAR_TODAY or nil,
			tooltip = { date(L["%Y-%m-%d"], t), METRIC_LABEL[metric]() .. ": " .. MetricText(metric, value) } }
	end
	local note = METRIC_LABEL[metric]() .. ": " .. MetricText(metric, total)
	local ix, iy, iw, ih = Card(canvas, x, y, w, h, L["Last 14 days"], note)
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

-- The 14-day chart's metric buttons sit in its header row.
local function PlaceButtons(canvas, ix, iy, state)
	for i, metric in ipairs(METRICS) do
		local button = state.buttons[metric]
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", canvas.parent, "TOPLEFT", ix + (i - 1) * 84, -(iy - 2))
		button:SetEnabled(metric ~= state.metric)
		button:Show()
	end
end

-- Draws the whole page for record c; state.metric is the 14-day chart's metric, state.buttons
-- the four metric buttons (created by the window). Returns the page height.
function G.Draw(canvas, width, c, state)
	canvas:Reset()
	local y = 0
	local h, ix, iy = Days(canvas, 0, y, width, c, state.metric)
	PlaceButtons(canvas, ix, iy, state)
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

---------------------------------------------------------------------------
-- A friend's page: from the days they send (Chronicle's D2 messages through Beacon), so it also
-- covers the time you weren't online
---------------------------------------------------------------------------

local MY_COLOR = { 1, 0.78, 0.2 }
local THEIR_COLOR = BAR_BLUE
local WEEK = { "played", "xp", "levels", "quests", "kills", "deaths" }

local function Sum(days, count)
	local sum = { played = 0, xp = 0, levels = 0, quests = 0, kills = 0, deaths = 0, afk = 0 }
	for i = 0, count - 1 do
		local b = days[date("%Y-%m-%d", C.DayAgo(i))]
		if b then
			for key in pairs(sum) do
				sum[key] = sum[key] + (b[key] or 0)
			end
		end
	end
	return sum
end

local function Label(key)
	if METRIC_LABEL[key] then
		return METRIC_LABEL[key]()
	end
	return key == "levels" and L["Levels"] or L["Deaths"]
end

-- Seven numbers for the last 7 days, as tiles.
local function Week(canvas, x, y, w, days)
	local h = 84
	local ix, iy, iw = Card(canvas, x, y, w, h, L["Last 7 days"])
	local sum = Sum(days, 7)
	local tileW = iw / #WEEK
	for i, key in ipairs(WEEK) do
		local tx = ix + (i - 1) * tileW
		canvas:Rect(tx + 2, iy, tileW - 4, 46, 1, 1, 1, 0.04, "BORDER")
		canvas:Text(MetricText(key, sum[key]), tx, iy + 6, "GameFontHighlightLarge", "CENTER", tileW)
		canvas:Text(Label(key), tx, iy + 30, "GameFontNormalSmall", "CENTER", tileW)
	end
	return h
end

-- You and them over the last 7 days, two bars per number.
local function Versus(canvas, x, y, w, mine, theirs, name)
	local rows = { "played", "xp", "quests", "kills" }
	local rowH = 32
	local h = HEADER + 4 + #rows * rowH + PAD
	local function Hex(c)
		return ("%02x%02x%02x"):format(math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
	end
	local note = ("|cff%s%s|r   |cff%s%s|r"):format(Hex(MY_COLOR), L["You"], Hex(THEIR_COLOR), name)
	local ix, iy, iw = Card(canvas, x, y, w, h, L["You and %s, last 7 days"]:format(name), note)
	local labelW, valueW = iw * 0.22, 80
	local barW = iw - labelW - valueW
	for i, key in ipairs(rows) do
		local ry = iy + (i - 1) * rowH
		canvas:Text(Label(key), ix, ry + 9, "GameFontHighlightSmall", "LEFT", labelW - 4)
		local max = math.max(mine[key], theirs[key])
		for j, side in ipairs({ { mine[key], MY_COLOR }, { theirs[key], THEIR_COLOR } }) do
			local by = ry + (j - 1) * 13
			canvas:Rect(ix + labelW, by, barW, 11, 1, 1, 1, 0.05, "BORDER")
			if max > 0 and side[1] > 0 then
				canvas:Bar(ix + labelW, by, barW * side[1] / max, 11, side[2])
			end
			canvas:Text(MetricText(key, side[1]), ix + labelW + barW + 6, by, "GameFontHighlightSmall", "LEFT", valueW - 6)
		end
	end
	return h
end

-- Their latest entries from the friends' feed.
local function News(canvas, x, y, w, lines)
	local lineH = 15
	local h = HEADER + 4 + math.max(#lines, 1) * lineH + PAD
	local ix, iy, iw, ih = Card(canvas, x, y, w, h, L["Latest news"])
	if #lines == 0 then
		Empty(canvas, ix, iy, iw, ih, L["Nothing recorded yet."])
	end
	for i, line in ipairs(lines) do
		canvas:Text(line, ix, iy + (i - 1) * lineH, "GameFontHighlightSmall", "LEFT", iw)
	end
	return h
end

-- You and them, lifetime: from their journal's profile (synced friends only).
local LIFETIME = { "played", "quests", "kills", "deaths", "zones", "dungeons", "bosses", "rares", "dist", "jumps",
	"achievements" }

local function Lifetime(canvas, x, y, w, mine, theirs, name, person)
	local rowH = 17
	local h = HEADER + 4 + #LIFETIME * rowH + 22 + PAD
	local ix, iy, iw = Card(canvas, x, y, w, h, L["You and %s, all time"]:format(name),
		person.last and person.last > 0 and L["Last played %s"]:format(C.Ago(person.last)) or nil)
	local labelW, colW = iw * 0.4, iw * 0.3
	canvas:Text(L["You"], ix + labelW, iy, "GameFontNormalSmall", "RIGHT", colW - 10)
	canvas:Text(name, ix + labelW + colW, iy, "GameFontNormalSmall", "RIGHT", colW - 10)
	for i, key in ipairs(LIFETIME) do
		local ry = iy + 16 + (i - 1) * rowH
		local a, b = mine[key] or 0, theirs[key] or 0
		canvas:Rect(ix, ry - 2, iw, rowH, 1, 1, 1, i % 2 == 0 and 0.03 or 0, "BORDER")
		canvas:Text(G.LifetimeLabel(key), ix + 4, ry, "GameFontHighlightSmall", "LEFT", labelW)
		canvas:Text((a > b and "|cffffd200" or "|cffffffff") .. G.LifetimeText(key, a) .. "|r", ix + labelW, ry,
			"GameFontHighlightSmall", "RIGHT", colW - 10)
		canvas:Text((b > a and "|cffffd200" or "|cffffffff") .. G.LifetimeText(key, b) .. "|r", ix + labelW + colW, ry,
			"GameFontHighlightSmall", "RIGHT", colW - 10)
	end
	local facts = {}
	if person.foe and person.foe ~= "" then
		facts[#facts + 1] = L["Deadliest foe: %s"]:format(person.foe)
	end
	if person.zone and person.zone ~= "" then
		facts[#facts + 1] = L["Favourite zone: %s"]:format(person.zone)
	end
	canvas:Text("|cff999999" .. table.concat(facts, "   ") .. "|r", ix + 4, iy + 18 + #LIFETIME * rowH, "GameFontHighlightSmall",
		"LEFT", iw - 8)
	return h
end

-- Draws a friend's page: friend = a person from C.People() (days; a synced one also a profile),
-- me = my record (for the comparison); state as for G.Draw, plus state.newsLines(name) from the window.
function G.DrawFriend(canvas, width, friend, name, me, state)
	canvas:Reset()
	local y = 0
	local h, ix, iy = Days(canvas, 0, y, width, { daily = friend.days }, state.metric)
	PlaceButtons(canvas, ix, iy, state)
	y = y + h + CARD_GAP
	y = y + Week(canvas, 0, y, width, friend.days) + CARD_GAP
	y = y + Versus(canvas, 0, y, width, Sum(me.daily, 7), Sum(friend.days, 7), name) + CARD_GAP
	if friend.profile then
		y = y + Lifetime(canvas, 0, y, width, C.ProfileNumbers(me), friend.profile, name, friend) + CARD_GAP
	end
	y = y + News(canvas, 0, y, width, state.newsLines and state.newsLines(name) or {})
	return y + 4
end

---------------------------------------------------------------------------
-- Compare: you and every friend in every graph, on one page
---------------------------------------------------------------------------

local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"

-- What a chart shows: key (a day's field, or value(b) for a sum of fields), mode "day" (that
-- day's number), "sum" (adding up over the range) or "last" (where the day ended: level, gold).
local CHARTS = {
	{ key = "played", mode = "day" },
	{ key = "xp", mode = "day" },
	{ key = "quests", mode = "day" },
	{ key = "kills", mode = "day" },
	{ key = "deaths", mode = "sum" },
	{ key = "gold", mode = "last" },
	{ key = "dist", mode = "day" },
	{ key = "bossesRares", mode = "sum", value = function(b) return (b.bosses or 0) + (b.rares or 0) end },
	{ key = "afk", mode = "day" },
	{ key = "jumps", mode = "sum" },
}
local LEVEL_CHART = { key = "level", mode = "last" }
local BY_KEY = { level = LEVEL_CHART }
for _, chart in ipairs(CHARTS) do
	BY_KEY[chart.key] = chart
end

-- The big chart at the top shows any of these (icons above it pick); per day or adding up.
local BIG = { "level", "played", "xp", "quests", "kills", "deaths", "gold", "dist", "bossesRares", "afk", "jumps" }
local CHART_ICON = {
	level = ICONS.level,
	played = "Interface\\Icons\\INV_Misc_PocketWatch_01",
	xp = "Interface\\Icons\\Spell_Holy_HolyBolt",
	quests = ICONS.quests,
	kills = "Interface\\Icons\\Ability_DualWield",
	deaths = ICONS.death,
	gold = ICONS.gold,
	dist = "Interface\\Icons\\Ability_Rogue_Sprint",
	bossesRares = ICONS.boss,
	afk = "Interface\\Icons\\Spell_Nature_Sleep",
	jumps = "Interface\\Icons\\Spell_Magic_FeatherFall",
}
local CHART_NAME = {
	level = function() return L["Level"] end,
	played = function() return L["Time played"] end,
	xp = function() return L["Experience"] end,
	quests = function() return L["Quests"] end,
	kills = function() return L["Killing blows"] end,
	deaths = function() return L["Deaths"] end,
	gold = function() return L["Gold"] end,
	dist = function() return L["Distance"] end,
	bossesRares = function() return L["Bosses and rares"] end,
	afk = function() return L["Time AFK"] end,
	jumps = function() return L["Jumps"] end,
}
-- The symbols' legend.
local MARK_LABEL = {
	death = function() return L["Deaths"] end,
	boss = function() return L["Bosses defeated"] end,
	level = function() return L["Level 10, 20, 30, ..."] end,
	dungeon = function() return L["Dungeons seen"] end,
	rare = function() return L["Rare elites killed"] end,
	loot = function() return L["Epic items"] end,
	achievement = function() return L["Achievements"] end,
	mount = function() return L["Mounts"] end,
	gold = function() return L["Gold milestones"] end,
}

-- What the big chart shows (state.big, state.perDay); level and gold are where the day ended.
local function BigChart(state)
	local key = BY_KEY[state.big or ""] and state.big or "level"
	local base = BY_KEY[key]
	return { key = key, value = base.value, mode = base.mode == "last" and "last" or (state.perDay and "day" or "sum") }
end

local function BigTitle(chart)
	local name = CHART_NAME[chart.key]()
	if chart.mode == "day" then
		return L["%s per day"]:format(name)
	elseif chart.mode == "sum" then
		return L["%s, adding up"]:format(name)
	end
	return name
end

local CHART_LABEL = {
	level = function() return L["Level"] end,
	played = function() return L["Time played per day"] end,
	xp = function() return L["Experience per day"] end,
	quests = function() return L["Quests per day"] end,
	kills = function() return L["Killing blows per day"] end,
	deaths = function() return L["Deaths, adding up"] end,
	gold = function() return L["Gold"] end,
	dist = function() return L["Distance per day"] end,
	bossesRares = function() return L["Bosses and rares, adding up"] end,
	afk = function() return L["Time AFK per day"] end,
	jumps = function() return L["Jumps, adding up"] end,
}

function G.ValueText(key, value)
	if key == "played" or key == "afk" then
		return C.Duration(value)
	elseif key == "dist" then
		return C.Distance(value)
	elseif key == "gold" then
		return C.Number(value) .. GOLD_ICON
	end
	return C.Number(value)
end

local LIFETIME_LABEL = {
	level = function() return L["Level"] end,
	played = function() return L["Time played"] end,
	quests = function() return L["Quests"] end,
	kills = function() return L["Killing blows"] end,
	deaths = function() return L["Deaths"] end,
	zones = function() return L["Zones discovered"] end,
	dungeons = function() return L["Dungeons seen"] end,
	bosses = function() return L["Bosses defeated"] end,
	rares = function() return L["Rare elites killed"] end,
	dist = function() return L["Distance"] end,
	jumps = function() return L["Jumps"] end,
	achievements = function() return L["Achievements"] end,
	gold = function() return L["Most gold at once"] end,
}
function G.LifetimeLabel(key)
	return LIFETIME_LABEL[key] and LIFETIME_LABEL[key]() or key
end
function G.LifetimeText(key, value)
	return G.ValueText(key, value)
end

-- Each person's colour: their class's; a second (third) of the same class lighter (darker).
local VARIANTS = { function(c) return c end, function(c) return c + (1 - c) * 0.55 end, function(c) return c * 0.55 end,
	function(c) return c + (1 - c) * 0.25 end }
local function Colours(people)
	local seen = {}
	for _, p in ipairs(people) do
		local r, g, b = 1, 1, 1
		if ns.Beacon and ns.Beacon.ClassColor then
			r, g, b = ns.Beacon.ClassColor(p.classFile)
		end
		local n = (seen[p.classFile or "?"] or 0) + 1
		seen[p.classFile or "?"] = n
		local f = VARIANTS[(n - 1) % #VARIANTS + 1]
		p.colour = { f(r), f(g), f(b) }
		p.hex = ("%02x%02x%02x"):format(math.floor(p.colour[1] * 255), math.floor(p.colour[2] * 255), math.floor(p.colour[3] * 255))
	end
end

local function Named(p)
	return "|cff" .. p.hex .. (p.name or "?") .. "|r"
end

-- A person's values over the range (days: YYYY-MM-DD, oldest first): nil where unknown.
local function Series(p, chart, days)
	local values, last = {}, nil
	local function Value(b)
		if chart.value then
			return chart.value(b)
		end
		return b[chart.key]
	end
	if chart.mode == "last" then
		local first = days[1]
		local before -- the latest value before the range starts
		for day, b in pairs(p.days) do
			if day < first and Value(b) ~= nil and (not before or day > before) then
				before = day
			end
		end
		last = before and Value(p.days[before]) or nil
	end
	local sum, any = 0, false
	for i, day in ipairs(days) do
		local b = p.days[day]
		local v = b and Value(b)
		if chart.mode == "last" then
			if v ~= nil and (chart.key ~= "level" or v > 0) then
				last = v
			end
			values[i] = last
			any = any or last ~= nil
		elseif chart.mode == "sum" then
			sum = sum + (v or 0)
			values[i] = sum
			any = any or (v or 0) > 0
		else
			values[i] = v or 0
			any = any or (v or 0) > 0
		end
	end
	return any and values or nil
end

-- Share a ranking in Lefthy chat: "Chronicle, last 14 days, quests: Anna 142, Bob 98".
local function ShareRanking(title, ranking, key, days)
	local parts = {}
	for i = 1, math.min(5, #ranking) do
		parts[#parts + 1] = ranking[i].person.name .. " " .. (key == "gold" and (C.Number(ranking[i].value) .. "g")
			or C.ChatValue(key == "bossesRares" and "kills" or key, ranking[i].value))
	end
	if #parts > 0 then
		C.ShareLine(("Chronicle, %s (%d days): %s"):format(title, days, table.concat(parts, ", ")))
	end
end

local CHART_CHAT = { level = "level", played = "time played", xp = "XP", quests = "quests", kills = "killing blows",
	deaths = "deaths", gold = "gold", dist = "distance", bossesRares = "bosses and rares", afk = "time AFK", jumps = "jumps" }

-- A line chart card: a line per person, the day's values in a tooltip, the leader in the corner.
-- opts (all optional): title; header(ix, iy, iw) draws a row above the plot and returns its height;
-- marks ([person key][day] = { { icon, text, rank, t } }: a symbol on their line that day, all of
-- them in the day's tooltip); pick() (a click on the plot: show this chart big at the top).
local function LineChart(canvas, x, y, w, h, chart, people, days, state, opts)
	opts = opts or {}
	local series, ranking = {}, {}
	local lo, hi = math.huge, -math.huge
	for _, p in ipairs(people) do
		if not state.hidden[p.key] then
			local values = Series(p, chart, days)
			if values then
				series[#series + 1] = { p = p, values = values }
				local final
				for _, v in pairs(values) do
					lo, hi = math.min(lo, v), math.max(hi, v)
				end
				for i = #days, 1, -1 do
					final = final or values[i]
				end
				-- The ranking: the range's total (per day), or where it ended (sum, last).
				local total = 0
				if chart.mode == "day" then
					for i = 1, #days do
						total = total + (values[i] or 0)
					end
				else
					total = final or 0
				end
				ranking[#ranking + 1] = { person = p, value = total }
			end
		end
	end
	table.sort(ranking, function(a, b) return a.value > b.value end)
	local note = ranking[1] and ranking[1].value > 0 and (Named(ranking[1].person) .. " " .. G.ValueText(chart.key, ranking[1].value)) or nil
	local ix, iy, iw, ih = Card(canvas, x, y, w, h, opts.title or CHART_LABEL[chart.key](), note)
	if opts.header then
		local used = opts.header(ix, iy, iw)
		iy, ih = iy + used, ih - used
	end
	-- Share, at the bottom right (under the day labels).
	canvas:Text("|cff80c0ff" .. L["Share"] .. "|r", ix + iw - 60, iy + ih - 11, "GameFontHighlightSmall", "RIGHT", 60)
	canvas:Hover(ix + iw - 60, iy + ih - 14, 60, 16, { L["Share"], L["Post this ranking in Lefthy chat."] },
		function() ShareRanking(CHART_CHAT[chart.key], ranking, chart.key, #days) end)
	ih = ih - 14
	if #series == 0 then
		Empty(canvas, ix, iy, iw, ih, L["Nothing recorded yet."])
		return
	end
	if chart.mode ~= "last" or chart.key == "gold" then
		lo = 0
	else
		lo = math.max(0, math.floor(lo) - 1)
	end
	hi = math.max(hi, lo + 1)
	local plotH = ih - 14
	for i = 1, 3 do
		canvas:Rect(ix, iy + plotH * (1 - i / 3), iw, 1, 1, 1, 1, GRID[i], "BORDER")
	end
	canvas:Text(G.ValueText(chart.key, hi), ix, iy - 2, "GameFontHighlightSmall", "LEFT", iw / 2)
	if lo > 0 then
		canvas:Text(G.ValueText(chart.key, lo), ix, iy + plotH - 12, "GameFontHighlightSmall", "LEFT", iw / 2)
	end
	local n = #days
	local function X(i)
		return ix + (n > 1 and (i - 1) / (n - 1) or 0.5) * iw
	end
	local function Y(v)
		return iy + plotH - plotH * (v - lo) / (hi - lo)
	end
	for _, s in ipairs(series) do
		local thick = s.p.me and 3 or 2
		local prev
		for i = 1, n do
			local v = s.values[i]
			if v ~= nil then
				if prev then
					canvas:Line(X(prev), Y(s.values[prev]), X(i), Y(v), s.p.colour, thick)
				end
				prev = i
			end
		end
		if n <= 14 then
			for i = 1, n do
				local v = s.values[i]
				if v ~= nil then
					canvas:Rect(X(i) - 2, Y(v) - 2, 4, 4, s.p.colour[1], s.p.colour[2], s.p.colour[3], 1, "OVERLAY")
				end
			end
		end
	end
	-- Symbols: each person's most notable highlight of the day, on their line (no line: at the bottom).
	local marks, marked, lined = opts.marks or {}, {}, {}
	for _, s in ipairs(series) do
		marked[#marked + 1], lined[s.p] = s, true
	end
	for _, p in ipairs(people) do
		if marks[p.key] and not state.hidden[p.key] and not lined[p] then
			marked[#marked + 1] = { p = p, values = {} }
		end
	end
	-- A symbol's own tooltip: only that person's moments of the day (two of a kind at most, so five
	-- deaths don't hide the boss; five in all). Symbols on the same spot share one.
	local function DayTitle(day)
		return date(L["%Y-%m-%d"], time({ year = tonumber(day:sub(1, 4)), month = tonumber(day:sub(6, 7)),
			day = tonumber(day:sub(9, 10)), hour = 12 }))
	end
	local function Moments(lines, p, list)
		lines[#lines + 1] = Named(p)
		local shown, ofKind = 0, {}
		for _, m in ipairs(list) do
			ofKind[m.rank] = (ofKind[m.rank] or 0) + 1
			if ofKind[m.rank] <= 2 and shown < 5 then
				lines[#lines + 1] = G.IconText(m.icon) .. " " .. m.text
				shown = shown + 1
			end
		end
		if #list > shown then
			lines[#lines + 1] = "|cff888888" .. L["... and %d more"]:format(#list - shown) .. "|r"
		end
	end
	local spots = {}
	for _, s in ipairs(marked) do
		local byDay = marks[s.p.key]
		for i, day in ipairs(byDay and days or {}) do
			local list = byDay[day]
			if list then
				table.sort(list, function(a, b) return a.rank < b.rank or (a.rank == b.rank and a.t > b.t) end)
				local mx, my = X(i), Y(s.values[i] or lo)
				canvas:Icon(list[1].icon, mx - 7, my - 7, 14)
				local spot
				for _, other in ipairs(spots) do
					if math.abs(other.x - mx) < 8 and math.abs(other.y - my) < 8 then
						spot = other
						break
					end
				end
				if not spot then
					spot = { x = mx, y = my, lines = { DayTitle(day) } }
					spots[#spots + 1] = spot
					canvas:Hover(mx - 8, my - 8, 16, 16, spot.lines, nil, true)
				end
				Moments(spot.lines, s.p, list) -- (the hover shows its lines table as it is when hovered)
			end
		end
	end
	-- Day labels under the plot, and a hover per day: everyone's value, small icons for what
	-- happened (a symbol's own hover tells what).
	local step = n <= 7 and 1 or n <= 14 and 2 or 5
	local slot = iw / math.max(n - 1, 1)
	for i, day in ipairs(days) do
		if (n - i) % step == 0 then
			canvas:Text(day:sub(9, 10), X(i) - 12, iy + plotH + 2, "GameFontHighlightSmall", "CENTER", 24)
		end
		local lines = { DayTitle(day) }
		local rows, anyMoments = {}, false
		for _, s in ipairs(marked) do
			local v, list = s.values[i], marks[s.p.key] and marks[s.p.key][day]
			if v ~= nil or list then
				rows[#rows + 1] = { p = s.p, v = v, list = list }
			end
		end
		table.sort(rows, function(a, b) return (a.v or -math.huge) > (b.v or -math.huge) end)
		for _, row in ipairs(rows) do
			local icons, kinds, count = "", {}, 0
			for _, m in ipairs(row.list or {}) do
				if not kinds[m.rank] and count < 3 then -- (each kind once, three at most)
					kinds[m.rank], count = true, count + 1
					icons = icons .. (count == 1 and "  " or " ") .. G.IconText(m.icon, 12)
				end
			end
			anyMoments = anyMoments or row.list ~= nil
			lines[#lines + 1] = Named(row.p) .. (row.v and ("  " .. G.ValueText(chart.key, row.v)) or "") .. icons
		end
		if anyMoments then
			lines[#lines + 1] = "|cff888888" .. L["Hover a symbol for what happened."] .. "|r"
		end
		if opts.pick then
			lines[#lines + 1] = "|cff80c0ff" .. L["Click: show it big at the top"] .. "|r"
		end
		canvas:Hover(X(i) - slot / 2, iy, slot, plotH, lines, opts.pick)
	end
end

-- The big chart's row above the plot: an icon per thing it can show, per day or adding up, and the
-- symbols switch (its tooltip: what they mean). Returns the row's height.
local function BigPicker(canvas, ix, iy, iw, chart, state, redraw)
	local size, gap = 20, 6
	local cx = ix
	for _, key in ipairs(BIG) do
		local on = key == chart.key
		if on then
			canvas:Rect(cx - 2, iy - 2, size + 4, size + 4, 1, 0.82, 0, 0.85, "BORDER")
		end
		canvas:Icon(CHART_ICON[key], cx, iy, size, not on)
		canvas:Hover(cx - 2, iy - 2, size + 4, size + 4, { CHART_NAME[key](), on and L["Shown now"] or L["Click: show this"] },
			function()
				state.big = key
				redraw()
			end)
		cx = cx + size + gap
	end
	-- From the right: the symbols switch, then per day | adding up.
	local marksOn = not state.noMarks
	local legend = { L["Symbols on the lines"], L["Everyone's most notable moment of the day. Hover a symbol for all of that day's."] }
	for _, kind in ipairs(G.MARK_KINDS) do
		legend[#legend + 1] = G.IconText(ICONS[kind]) .. " " .. MARK_LABEL[kind]()
	end
	legend[#legend + 1] = "|cff80c0ff" .. (marksOn and L["Click: hide the symbols"] or L["Click: show the symbols"]) .. "|r"
	local rx = ix + iw - 84
	canvas:Rect(rx, iy, 84, 20, 1, 1, 1, marksOn and 0.12 or 0.03, "BORDER")
	canvas:Icon(ICONS.death, rx + 4, iy + 3, 14, not marksOn)
	canvas:Text((marksOn and "|cffffffff" or "|cff888888") .. L["Symbols"] .. "|r", rx + 22, iy + 4, "GameFontHighlightSmall", "LEFT", 58)
	canvas:Hover(rx, iy, 84, 20, legend, function()
		state.noMarks = marksOn or nil
		redraw()
	end)
	if chart.mode ~= "last" then
		for _, perDay in ipairs({ true, false }) do
			local chipW = 92
			rx = rx - chipW - 4
			local on = (chart.mode == "day") == perDay
			canvas:Rect(rx, iy, chipW, 20, 1, 0.82, 0, on and 0.35 or 0.08, "BORDER")
			canvas:Text((on and "|cffffffff" or "|cffaaaaaa") .. (perDay and L["Per day"] or L["Adding up"]) .. "|r", rx, iy + 4,
				"GameFontHighlightSmall", "CENTER", chipW)
			canvas:Hover(rx, iy, chipW, 20, { perDay and L["Per day"] or L["Adding up"],
				perDay and L["Each day on its own."] or L["Each day adds to the days before it."] }, function()
				state.perDay = perDay or nil
				redraw()
			end)
		end
	end
	return size + 10
end

-- The legend: a chip per person (click: hide or show them everywhere), the range, sharing the week.
local RANGES = { 7, 14, 30 }

local function Toolbar(canvas, x, y, w, people, state, redraw)
	local h = 26
	local cx = x
	for _, days in ipairs(RANGES) do
		local text = L["%d days"]:format(days)
		local chipW = 58
		local on = state.range == days
		canvas:Rect(cx, y, chipW - 4, 20, 1, 0.82, 0, on and 0.35 or 0.08, "BORDER")
		canvas:Text((on and "|cffffffff" or "|cffaaaaaa") .. text .. "|r", cx, y + 4, "GameFontHighlightSmall", "CENTER", chipW - 4)
		canvas:Hover(cx, y, chipW - 4, 20, nil, function()
			state.range = days
			redraw()
		end)
		cx = cx + chipW
	end
	cx = cx + 10
	local rowY = y
	for _, p in ipairs(people) do
		local label = (p.name or "?") .. (p.me and (" " .. L["(you)"]) or "")
		local chipW = 26 + math.min(110, #label * 6.5)
		if cx + chipW > x + w then
			cx, rowY = x, rowY + 24
			h = h + 24
		end
		local hidden = state.hidden[p.key]
		canvas:Rect(cx, rowY, chipW - 4, 20, 1, 1, 1, hidden and 0.02 or 0.07, "BORDER")
		canvas:Rect(cx + 6, rowY + 6, 8, 8, p.colour[1], p.colour[2], p.colour[3], hidden and 0.25 or 1)
		canvas:Text((hidden and "|cff666666" or ("|cff" .. p.hex)) .. label .. "|r", cx + 18, rowY + 4, "GameFontHighlightSmall",
			"LEFT", chipW - 22)
		local tip = { p.name or "?" }
		tip[#tip + 1] = p.level and L["Level %d"]:format(p.level) or nil
		if p.account then
			tip[#tip + 1] = p.account
		end
		if p.chars and #p.chars > 1 then -- (an account: its numbers add up all its characters)
			local names = {}
			for _, c in ipairs(p.chars) do
				names[#names + 1] = LT.Window.ClassColorCode(c.classFile) .. (c.name or "?") .. "|r " .. (c.level or "")
			end
			tip[#tip + 1] = L["All characters: %s"]:format(table.concat(names, ", "))
		end
		if p.online then
			tip[#tip + 1] = L["Online now"]
		elseif p.last and p.last > 0 then
			tip[#tip + 1] = L["Last played %s"]:format(C.Ago(p.last))
		end
		tip[#tip + 1] = hidden and L["Click: show in the graphs"] or L["Click: hide from the graphs"]
		canvas:Hover(cx, rowY, chipW - 4, 20, tip, function()
			state.hidden[p.key] = not state.hidden[p.key] or nil
			redraw()
		end)
		cx = cx + chipW
	end
	return h + 6
end

-- This week (the last 7 days): who leads in what, the top three of each.
local BOARD_LABEL = {
	played = function() return L["Time played"] end, xp = function() return L["Experience"] end,
	quests = function() return L["Quests"] end, kills = function() return L["Killing blows"] end,
	levels = function() return L["Levels gained"] end, deaths = function() return L["Most deaths"] end,
	dist = function() return L["Distance"] end, jumps = function() return L["Jumps"] end,
	afk = function() return L["Martin award"] end,
}

local function Leaders(canvas, x, y, w, people, state)
	local board = C.Leaderboard(7, 0, people)
	local columns, cellH = 3, 64
	local rows = math.ceil(#C.BOARD / columns)
	local h = HEADER + 4 + rows * cellH + PAD
	local ix, iy, iw = Card(canvas, x, y, w, h, L["Leaderboard, last 7 days"])
	canvas:Text("|cff80c0ff" .. L["Share"] .. "|r", x + w - PAD - 60, y + 9, "GameFontHighlightSmall", "RIGHT", 60)
	canvas:Hover(x + w - PAD - 60, y + 4, 60, 18, { L["Share"], L["Post the week's leaders in Lefthy chat."] }, function()
		local parts = {}
		for _, metric in ipairs({ "quests", "xp", "kills", "deaths", "afk" }) do
			local first = board[metric][1]
			if first then
				local title = metric == "afk" and "Martin award" or ("most " .. CHART_CHAT[metric])
				parts[#parts + 1] = ("%s %s (%s)"):format(title, first.person.name, C.ChatValue(metric, first.value))
			end
		end
		if #parts > 0 then
			C.ShareLine("Chronicle week: " .. table.concat(parts, ", "))
		end
	end)
	local cellW = iw / columns
	local medals = { "|cffffd700", "|cffc0c0c0", "|cffcd7f32" }
	for i, metric in ipairs(C.BOARD) do
		local cx = ix + ((i - 1) % columns) * cellW
		local cy = iy + math.floor((i - 1) / columns) * cellH
		canvas:Rect(cx + 2, cy, cellW - 4, cellH - 6, 1, 1, 1, 0.03, "BORDER")
		canvas:Text(BOARD_LABEL[metric](), cx + 8, cy + 4, "GameFontNormalSmall", "LEFT", cellW - 16)
		local list = {}
		for _, entry in ipairs(board[metric] or {}) do
			if not state.hidden[entry.person.key] then
				list[#list + 1] = entry
			end
		end
		if #list == 0 then
			canvas:Text("|cff666666-|r", cx + 8, cy + 20, "GameFontHighlightSmall", "LEFT", cellW - 16)
		end
		for rank = 1, math.min(3, #list) do
			local entry = list[rank]
			canvas:Text(("%s%d.|r %s"):format(medals[rank], rank, Named(entry.person)), cx + 8, cy + 6 + rank * 13,
				"GameFontHighlightSmall", "LEFT", cellW * 0.6)
			canvas:Text(G.ValueText(metric, entry.value), cx + cellW * 0.5, cy + 6 + rank * 13, "GameFontHighlightSmall", "RIGHT",
				cellW * 0.5 - 10)
		end
	end
	return h
end

-- Everyone's lifetime numbers in a table; a column's header sorts by it; the best in gold.
local HALL = { "level", "played", "quests", "kills", "deaths", "zones", "dungeons", "bosses", "rares", "dist", "jumps" }
local HALL_SHORT = {
	level = function() return L["Level"] end, played = function() return L["Time"] end, quests = function() return L["Quests"] end,
	kills = function() return L["Kills"] end, deaths = function() return L["Deaths"] end, zones = function() return L["Zones"] end,
	dungeons = function() return L["Dungeons"] end, bosses = function() return L["Bosses"] end, rares = function() return L["Rares"] end,
	dist = function() return L["Distance"] end, jumps = function() return L["Jumps"] end,
}

local function Hall(canvas, x, y, w, people, state, redraw)
	local list = {}
	for _, p in ipairs(people) do
		if p.profile and not state.hidden[p.key] then
			list[#list + 1] = p
		end
	end
	local rowH = 18
	local h = HEADER + 4 + 20 + math.max(#list, 1) * rowH + PAD
	local ix, iy, iw, ih = Card(canvas, x, y, w, h, L["Hall of fame, all time"])
	if #list == 0 then
		Empty(canvas, ix, iy, iw, ih, L["Friends' lifetime numbers come with their synced journals."])
		return h
	end
	local sortBy = state.sortBy or "level"
	local function Value(p, key)
		if key == "level" then
			return p.level or 0
		end
		return p.profile[key] or 0
	end
	table.sort(list, function(a, b)
		local va, vb = Value(a, sortBy), Value(b, sortBy)
		return va > vb or (va == vb and (a.name or "") < (b.name or ""))
	end)
	local best = {}
	for _, key in ipairs(HALL) do
		for _, p in ipairs(list) do
			best[key] = math.max(best[key] or 0, Value(p, key))
		end
	end
	local nameW = iw * 0.16
	local colW = (iw - nameW) / #HALL
	for i, key in ipairs(HALL) do
		local hx = ix + nameW + (i - 1) * colW
		canvas:Text((key == sortBy and "|cffffffff" or "|cffffd200") .. HALL_SHORT[key]() .. "|r", hx, iy, "GameFontNormalSmall",
			"RIGHT", colW - 4)
		canvas:Hover(hx, iy - 2, colW, 16, { G.LifetimeLabel(key), L["Click: sort by this"] }, function()
			state.sortBy = key
			redraw()
		end)
	end
	for r, p in ipairs(list) do
		local ry = iy + 20 + (r - 1) * rowH
		canvas:Rect(ix, ry - 3, iw, rowH, 1, 1, 1, r % 2 == 0 and 0.03 or 0, "BORDER")
		canvas:Text(Named(p), ix + 2, ry, "GameFontHighlightSmall", "LEFT", nameW - 4)
		for i, key in ipairs(HALL) do
			local v = Value(p, key)
			local text = key == "level" and tostring(v) or key == "played" and C.Duration(v) or key == "dist" and C.Distance(v)
				or C.Number(v)
			canvas:Text(((v > 0 and v == best[key]) and "|cffffd200" or "|cffffffff") .. text .. "|r", ix + nameW + (i - 1) * colW, ry,
				"GameFontHighlightSmall", "RIGHT", colW - 4)
		end
	end
	return h
end

-- Records among everyone: fastest level, longest session, most gold, most deaths, deadliest foes.
local function Records(canvas, x, y, w, people, state)
	local lines = {}
	local function Best(key, lowest)
		local winner, value
		for _, p in ipairs(people) do
			local v = p.profile and p.profile[key]
			if v and v > 0 and not state.hidden[p.key] and (not value or (lowest and v < value) or (not lowest and v > value)) then
				winner, value = p, v
			end
		end
		return winner, value
	end
	local p, v = Best("fastest", true)
	if p then
		lines[#lines + 1] = L["Fastest level: %s (%s)"]:format(Named(p), C.Duration(v))
	end
	p, v = Best("longest")
	if p then
		lines[#lines + 1] = L["Longest session: %s (%s)"]:format(Named(p), C.Duration(v))
	end
	p, v = Best("gold")
	if p then
		lines[#lines + 1] = L["Most gold at once: %s (%s)"]:format(Named(p), C.Number(v) .. GOLD_ICON)
	end
	p, v = Best("deaths")
	if p then
		lines[#lines + 1] = L["Died the most: %s (%s)"]:format(Named(p), C.Number(v))
	end
	p, v = Best("afk")
	if p then
		lines[#lines + 1] = L["Martin of all time: %s (%s AFK)"]:format(Named(p), C.Duration(v))
	end
	for _, person in ipairs(people) do
		if person.foe and person.foe ~= "" and not state.hidden[person.key] then
			lines[#lines + 1] = L["%s's nemesis: %s"]:format(Named(person), person.foe)
		end
	end
	local lineH = 15
	local h = HEADER + 4 + math.max(#lines, 1) * lineH + PAD
	local ix, iy, iw, ih = Card(canvas, x, y, w, h, L["Records"])
	if #lines == 0 then
		Empty(canvas, ix, iy, iw, ih, L["Nothing recorded yet."])
	end
	for i, line in ipairs(lines) do
		canvas:Text(line, ix, iy + (i - 1) * lineH, "GameFontHighlightSmall", "LEFT", iw)
	end
	return h
end

-- The page: state = { range (days), hidden = { [person key] = true }, sortBy, big (what the big chart
-- shows), perDay, noMarks, marks(people, days) (the symbols, from the window) }; redraw(top) draws it
-- again (a click on a chip, a range or a column; top: scrolled to the top). Returns the page height.
local BIG_H = 260

function G.DrawCompare(canvas, width, people, state, redraw)
	canvas:Reset()
	Colours(people)
	local days = {}
	for i = state.range - 1, 0, -1 do
		days[#days + 1] = date("%Y-%m-%d", C.DayAgo(i))
	end
	local y = 0
	y = y + Toolbar(canvas, 0, y, width, people, state, redraw)
	if #people < 2 then
		local h = 46
		local ix, iy, iw, ih = Card(canvas, 0, y, width, h, L["Just you so far"])
		Empty(canvas, ix, iy, iw, ih, L["Friends show up here once they run this LefthyTools: their journals come in whenever any friend who has them is online."])
		y = y + h + CARD_GAP
	end
	local big = BigChart(state)
	LineChart(canvas, 0, y, width, BIG_H, big, people, days, state, {
		title = BigTitle(big),
		header = function(ix, iy, iw) return BigPicker(canvas, ix, iy, iw, big, state, redraw) end,
		marks = not state.noMarks and state.marks and state.marks(people, days) or nil,
	})
	y = y + BIG_H + CARD_GAP
	y = y + Leaders(canvas, 0, y, width, people, state) + CARD_GAP
	local half = (width - CARD_GAP) / 2
	for i, chart in ipairs(CHARTS) do
		local column = (i - 1) % 2
		LineChart(canvas, column * (half + CARD_GAP), y, half, 160, chart, people, days, state, { pick = function()
			state.big, state.perDay = chart.key, chart.mode == "day" or nil
			redraw(true)
		end })
		if column == 1 or i == #CHARTS then
			y = y + 160 + CARD_GAP
		end
	end
	y = y + Hall(canvas, 0, y, width, people, state, redraw) + CARD_GAP
	y = y + Records(canvas, 0, y, width, people, state)
	return y + 4
end

---------------------------------------------------------------------------
-- Offline: every friend's character that isn't online, a row each
---------------------------------------------------------------------------

-- The columns, as parts of the width.
local AWAY_COLUMNS = {
	{ key = "name", w = 0.18, title = function() return L["Name"] end },
	{ key = "level", w = 0.07, title = function() return L["Level"] end, right = true },
	{ key = "account", w = 0.15, title = function() return L["BattleTag"] end },
	{ key = "last", w = 0.15, title = function() return L["Last played"] end },
	{ key = "week", w = 0.12, title = function() return L["This week"] end },
	{ key = "latest", w = 0.33, title = function() return L["Latest news"] end },
}

-- rows = { { person (C.People), week (seconds played in 7 days), latest = { icon, text, t } or nil } },
-- most recently played first; open(key): a click on a row (their graphs). Returns the page height.
function G.DrawAway(canvas, width, rows, open)
	canvas:Reset()
	local rowH = 22
	local h = HEADER + 4 + 20 + math.max(#rows, 1) * rowH + PAD
	local ix, iy, iw, ih = Card(canvas, 0, 0, width, h, L["Not online"],
		#rows > 0 and ("|cff999999" .. L["%d characters"]:format(#rows) .. "|r") or nil)
	if #rows == 0 then
		Empty(canvas, ix, iy, iw, ih, L["Everyone with a journal is online, or no friend's journal has come yet."])
		return h + 4
	end
	local x = {}
	local cx = ix
	for i, column in ipairs(AWAY_COLUMNS) do
		x[i] = cx
		canvas:Text("|cffffd200" .. column.title() .. "|r", cx, iy, "GameFontNormalSmall", column.right and "RIGHT" or "LEFT",
			iw * column.w - 8)
		cx = cx + iw * column.w
	end
	for r, row in ipairs(rows) do
		local p = row.person
		local ry = iy + 20 + (r - 1) * rowH
		canvas:Rect(ix - 4, ry - 4, iw + 8, rowH, 1, 1, 1, r % 2 == 0 and 0.035 or 0, "BORDER")
		local function Cell(i, text)
			local column = AWAY_COLUMNS[i]
			canvas:Text(text, x[i], ry, "GameFontHighlightSmall", column.right and "RIGHT" or "LEFT", iw * column.w - 8)
		end
		Cell(1, LT.Window.ClassColorCode(p.classFile) .. (p.name or "?") .. "|r")
		Cell(2, p.level and tostring(p.level) or "|cff666666-|r")
		Cell(3, p.account and ("|cff80c0ff" .. p.account .. "|r") or "|cff666666-|r")
		Cell(4, (p.last and p.last > 0) and C.Ago(p.last) or "|cff666666-|r")
		Cell(5, row.week > 0 and C.Duration(row.week) or "|cff666666-|r")
		local latest = row.latest
		if latest then
			canvas:Icon(latest.icon, x[6], ry - 1, 14)
			canvas:Text("|cffcccccc" .. latest.text .. "|r  |cff888888" .. C.Ago(latest.t) .. "|r", x[6] + 18, ry,
				"GameFontHighlightSmall", "LEFT", iw * AWAY_COLUMNS[6].w - 24)
		else
			Cell(6, "|cff666666-|r")
		end
		-- Hover: all of it (a long highlight is cut in its cell); click: their graphs.
		local tip = { LT.Window.ClassColorCode(p.classFile) .. (p.name or "?") .. "|r" }
		if p.level then
			tip[#tip + 1] = L["Level %d"]:format(p.level) .. (p.realm and (" - " .. p.realm) or "")
		end
		if p.account then
			tip[#tip + 1] = "|cff80c0ff" .. p.account .. "|r"
		end
		if p.last and p.last > 0 then
			tip[#tip + 1] = L["Last played %s"]:format(C.Ago(p.last))
		end
		if row.week > 0 then
			tip[#tip + 1] = L["%s this week"]:format(C.Duration(row.week))
		end
		if latest then
			tip[#tip + 1] = G.IconText(latest.icon) .. " " .. latest.text .. "  |cff888888" .. date(L["%Y-%m-%d"], latest.t) .. "|r"
		end
		tip[#tip + 1] = "|cff80c0ff" .. L["Click: their graphs"] .. "|r"
		canvas:Hover(ix - 4, ry - 4, iw + 8, rowH, tip, function() open(p.key) end)
	end
	return h + 4
end

G.METRICS = METRICS
G.METRIC_LABEL = METRIC_LABEL
