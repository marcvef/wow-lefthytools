local _, ns = ...
local L = ns.L
local C = ns.Chronicle

-- Chronicle's drawing kit for the Graphs, Compare and Friends pages: a canvas on the window's scroll
-- content, drawn with plain textures (bars, with a gradient), line objects and font strings. Every
-- object comes from a pool and is reused on the next draw, so redrawing creates nothing new once a
-- page has been drawn; the window draws a page only when it's opened and at most every few seconds
-- after. Then the building blocks the pages share (a card, bars, a curve, a split bar, tables) and how
-- their numbers are labelled. Graphs.lua and Compare.lua draw the pages with it.

local CARD_GAP, PAD = 12, 10
local HEADER = 24                -- card title row
local GRID = { 0.08, 0.08, 0.08 } -- faint guide lines
local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"

local G = {}
C.Graphs = G
G.CARD_GAP, G.PAD, G.HEADER, G.GRID, G.GOLD_ICON = CARD_GAP, PAD, HEADER, GRID, GOLD_ICON

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

G.Card, G.Empty, G.Bars, G.HBars, G.Split, G.Curve, G.Heat = Card, Empty, Bars, HBars, Split, Curve, Heat

---------------------------------------------------------------------------
-- Values and labels
---------------------------------------------------------------------------

-- A number as the pages show it: a time, a distance, gold with its icon, else a number.
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
-- A lifetime number's label (the friend's page, the hall of fame).
function G.LifetimeLabel(key)
	return LIFETIME_LABEL[key] and LIFETIME_LABEL[key]() or key
end

---------------------------------------------------------------------------
-- Tables (the Friends page: who's online, who isn't)
---------------------------------------------------------------------------

local TABLE_ROW = 22

-- One table in a card. t = { title, note, columns = { { title, w (part of the width), right } },
-- rows = { { cells = { text | { icon, text } }, tip = { lines } (hover), click = fn } }, empty (text
-- while there are no rows) }. Returns its height.
local function Table(canvas, y, w, t)
	local rows = t.rows
	local h = HEADER + 4 + (#rows > 0 and (20 + #rows * TABLE_ROW) or 24) + PAD
	local ix, iy, iw, ih = Card(canvas, 0, y, w, h, t.title, t.note)
	if #rows == 0 then
		Empty(canvas, ix, iy, iw, ih, t.empty or "")
		return h
	end
	local x, cx = {}, ix
	for i, column in ipairs(t.columns) do
		x[i] = cx
		canvas:Text("|cffffd200" .. column.title .. "|r", cx, iy, "GameFontNormalSmall", column.right and "RIGHT" or "LEFT", iw * column.w - 8)
		cx = cx + iw * column.w
	end
	for r, row in ipairs(rows) do
		local ry = iy + 20 + (r - 1) * TABLE_ROW
		canvas:Rect(ix - 4, ry - 4, iw + 8, TABLE_ROW, 1, 1, 1, r % 2 == 0 and 0.035 or 0, "BORDER")
		for i, cell in ipairs(row.cells) do
			local column = t.columns[i]
			local cw = iw * column.w - 8
			if type(cell) == "table" then -- an icon, then text
				canvas:Icon(cell.icon, x[i], ry - 1, 14)
				canvas:Text(cell.text, x[i] + 18, ry, "GameFontHighlightSmall", "LEFT", cw - 18)
			else
				canvas:Text(cell, x[i], ry, "GameFontHighlightSmall", column.right and "RIGHT" or "LEFT", cw)
			end
		end
		canvas:Hover(ix - 4, ry - 4, iw + 8, TABLE_ROW, row.tip, row.click) -- (all of it: a long cell is cut)
	end
	return h
end

-- Tables one under the other (the window builds them). Returns the page height.
function G.DrawTables(canvas, width, tables)
	canvas:Reset()
	local y = 0
	for i, t in ipairs(tables) do
		y = y + Table(canvas, y, width, t) + (i < #tables and CARD_GAP or 0)
	end
	return y + 4
end
