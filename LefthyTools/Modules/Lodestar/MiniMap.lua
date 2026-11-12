local _, ns = ...
local LT = ns.LT
local L = ns.L
local Q = ns.Lodestar or {}; ns.Lodestar = Q

-- The small zone map: a zone's map as your world map draws it (LT.MapArt, Core/MapArt.lua: the
-- world map's art tiles and every area's overlay on them, all uncovered: MapArt's reveal), in a frame of ours that clips it, with the game's own quest icons for givers
-- and turn-ins, soft spots where a quest's item drops, and your own arrow when you're on that map.
-- Never the world map itself: nothing of WorldMapFrame is touched (no pins, no data providers, no
-- opening it).
--   local m = Q.NewMiniMap(parent[, width, height])  -- default 240 x 160 (a zone's art is 3:2)
--   m.frame                                         -- to anchor it
--   m:Show(map, points[, name])                     -- points = { { x, y, kind, label [, note, look, grey, chance, radius, group, hard] } }
--   m:SetSize(width, height), m:Hide(), m:ShowPlayer(on), m:Zoom(factor[, x, y]), m:Markers(), m:Light(group)
-- x and y are 0..1 on that map. kind: "start" (a quest giver), "end" (a turn-in), "drop" (where a
-- quest's item drops: a soft orange spot, as big as its radius (0..1 of the map's width) or
-- more; the likeliest one says "drops here (12%)"), "area" (where a quest's objective is done: a
-- soft gold circle as big as its radius; group: which objective, m:Light(group) lights its areas
-- and dims the others', m:Light() puts them back). look, the
-- icon (the ones players know from the game's maps): "available" (yellow !), "repeatable" (blue !),
-- "trivial" (the game's grey ! of a low quest), "locked" (grey !: not open yet), "turnin" (yellow ?),
-- "repeatturnin", "progress" (in your log, not done yet). Without look: a start is "available", an
-- end "turnin"; grey = true makes them "locked" / "progress". hard = true: its dark outline is an
-- orange ring (a hard quest's giver, its icon the game's). note: a line for the tooltip (the
-- quest). Markers within a few pixels are one, its tooltip listing each (several givers at a
-- spot, a giver who's also the turn-in).
-- A click on a marker sets the game's own map pin there and tracks it (Q.Waypoint: the arrow on
-- screen and the minimap); Shift-click also puts the pin in the chat box. The mouse wheel zooms
-- (around the cursor, up to 8 times), dragging moves the zoomed map, a right-click shows the whole
-- zone again. The art is laid only when the map, the size or the zoom changes (or you've explored
-- more). While the map is shown, your arrow is moved ten times a second (an OnUpdate on a frame of
-- the map: hidden, it doesn't run); a drag runs one only while the button is held. The markers are
-- buttons, so a controller's cursor reaches them (its focus shows the tooltip, its button sets
-- the pin).

local WIDTH, HEIGHT = 240, 160
local MARKER = 22        -- px: a giver's or turn-in's icon (the gossip icons were 18 and see-through)
local OUTLINE = 4        -- px: the dark copy behind it, bigger by this
local DROP = 34          -- px: a drop area's soft spot (at least; its radius makes it bigger)
local DROP_MAX = 140
local NEAR = 8           -- px: markers this close are one
local MAX_MARKERS = 40   -- (an item from mobs can start a quest in many places)
local PLAYER_EVERY = 0.1 -- s between moves of your arrow
local ZOOM_STEP, ZOOM_MAX = 1.35, 8
-- { atlas, file, alpha, grey, the file's alpha (when the atlas is missing) }
local LOOKS = { -- the game's map icons (atlas; a dark rim of their own), else the gossip window's
	available = { "QuestNormal", "Interface\\GossipFrame\\AvailableQuestIcon" },
	repeatable = { "QuestDaily", "Interface\\GossipFrame\\DailyQuestIcon" },
	trivial = { "TrivialQuests", "Interface\\GossipFrame\\AvailableQuestIcon", nil, nil, 0.55 },
	locked = { "QuestNormal", "Interface\\GossipFrame\\AvailableQuestIcon", 1, true },
	turnin = { "QuestTurnin", "Interface\\GossipFrame\\ActiveQuestIcon" },
	repeatturnin = { "QuestRepeatableTurnin", "Interface\\GossipFrame\\DailyActiveQuestIcon" },
	progress = { "SideInProgressquesticon", "Interface\\GossipFrame\\IncompleteQuestIcon" },
}
local GLOW = "Spells\\GenericGlow64" -- (soft and round, black around it: drawn added)
local DOT = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local ARROW = "Interface\\Minimap\\MinimapArrow"
local DROP_R, DROP_G, DROP_B = 1, 0.55, 0.12
local AREA_R, AREA_G, AREA_B = 1, 0.82, 0.25 -- an objective's area (the quest log's gold)
local AREA_ALPHA, AREA_DIM, AREA_LIT = 0.7, 0.2, 1
-- An area's fill under its glow (as the big window's): a glow alone, drawn added, all but vanishes on
-- light ground (Elwynn's fields, a desert); the fill reads on any.
local FILL_ALPHA, FILL_DIM, FILL_LIT = 0.3, 0.08, 0.45
local HARD_R, HARD_G, HARD_B = 1, 0.5, 0.25 -- a hard quest's ring (the game's orange difficulty)
local KINDS = { start = L["Quest giver"], ["end"] = L["Turn-in"], drop = L["Drops here"], area = L["Objective area"] }

-- A soft spot under the icons: a drop's or an objective's area.
local function Soft(kind)
	return kind == "drop" or kind == "area"
end

local Widget = {}
Widget.__index = Widget

-- "12%", "0.5%" (chance 0..100).
function Q.Percent(chance)
	chance = tonumber(chance) or 0
	if chance > 0 and chance < 1 then
		return ("%.1f%%"):format(chance)
	end
	return ("%d%%"):format(math.floor(chance + 0.5))
end

-- The look of a point: its icon's name in LOOKS.
local function LookOf(point)
	if point.look and LOOKS[point.look] then
		return point.look
	end
	if point.kind == "end" then
		return point.grey and "progress" or "turnin"
	end
	return point.grey and "locked" or "available"
end

-- The icon on a texture; its alpha (the file's own when the atlas is missing).
local function SetArt(texture, look)
	local art = LOOKS[look] or LOOKS.available
	if C_Texture and C_Texture.GetAtlasInfo and LT.Value(C_Texture.GetAtlasInfo, art[1]) then
		texture:SetAtlas(art[1])
		return art[3] or 1
	end
	texture:SetTexture(art[2])
	return art[5] or art[3] or 1
end

local function MarkerEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	for i, line in ipairs(self.lines) do
		if i == 1 then
			GameTooltip:SetText(line[1], 1, 1, 1)
		else
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(line[1], 1, 1, 1)
		end
		GameTooltip:AddLine(KINDS[line[2]] or "", 0.7, 0.7, 0.7)
		if line[3] then
			GameTooltip:AddLine(line[3], 1, 0.82, 0, true)
		end
	end
	if self.kind ~= "drop" and Q.Waypoint then -- (an area's spot is where to go: a pin too)
		GameTooltip:AddLine(L["Click: map pin. Shift-click: also in chat."], 0.5, 0.8, 1, true)
	end
	GameTooltip:Show()
end

local function MarkerLeave(self)
	if GameTooltip:IsOwned(self) then
		GameTooltip:Hide()
	end
end

local function MarkerClick(self)
	local m = self.widget
	if Q.Waypoint and m.map and self.x then
		Q.Waypoint(m.map, self.x, self.y, IsShiftKeyDown and IsShiftKeyDown())
	end
end

local function Marker(m, i)
	local marker = m.markers[i]
	if not marker then
		marker = CreateFrame("Button", nil, m.Map)
		marker.widget = m
		marker.Shadow = marker:CreateTexture(nil, "ARTWORK", nil, 0)
		marker.Shadow:SetPoint("CENTER")
		marker.Shadow:SetSize(MARKER + OUTLINE, MARKER + OUTLINE)
		marker.Icon = marker:CreateTexture(nil, "ARTWORK", nil, 1)
		marker.Icon:SetPoint("CENTER")
		marker.Icon:SetSize(MARKER, MARKER)
		marker.Glow = marker:CreateTexture(nil, "BACKGROUND")
		marker.Glow:SetAllPoints()
		marker.Glow:SetTexture(GLOW)
		marker.Glow:SetBlendMode("ADD")
		marker.Glow:SetVertexColor(DROP_R, DROP_G, DROP_B, 0.9)
		marker.Fill = marker:CreateTexture(nil, "BORDER")
		marker.Fill:SetPoint("CENTER")
		marker.Fill:SetTexture(DOT)
		marker.Fill:Hide()
		marker.Dot = marker:CreateTexture(nil, "ARTWORK", nil, 2)
		marker.Dot:SetPoint("CENTER")
		marker.Dot:SetSize(7, 7)
		marker.Dot:SetTexture(DOT)
		marker.Dot:SetVertexColor(DROP_R, DROP_G, DROP_B, 1)
		marker:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
		marker:SetScript("OnEnter", MarkerEnter)
		marker:SetScript("OnLeave", MarkerLeave)
		marker:SetScript("OnClick", MarkerClick)
		marker.lines = {}
		m.markers[i] = marker
	end
	return marker
end

-- A marker's look for its kind: a drop's soft spot under the others; a giver's or turn-in's icon,
-- solid, on a dark copy of itself (the outline that keeps it readable on any ground).
local function Dress(m, marker, point)
	local drop = Soft(point.kind)
	local size = drop and math.max(DROP, math.min(DROP_MAX, (tonumber(point.radius) or 0) * 2 * m.artW)) or MARKER
	marker.kind, marker.size, marker.group = point.kind, size, point.group
	marker:SetSize(size, size)
	marker:SetFrameLevel(m.Map:GetFrameLevel() + (drop and 1 or 3))
	marker.Glow:SetShown(drop)
	marker.Dot:SetShown(point.kind == "drop")
	marker.Icon:SetShown(not drop)
	marker.Shadow:SetShown(not drop)
	marker.look = not drop and LookOf(point) or nil
	marker.Fill:SetShown(point.kind == "area")
	if point.kind == "area" then
		marker.Glow:SetVertexColor(AREA_R, AREA_G, AREA_B, AREA_ALPHA)
		marker.Fill:SetSize(size * 0.7, size * 0.7) -- (the glow's bright middle)
		marker.Fill:SetVertexColor(AREA_R, AREA_G, AREA_B, FILL_ALPHA)
	elseif drop then
		marker.Glow:SetVertexColor(DROP_R, DROP_G, DROP_B, 0.9)
	end
	if not drop then
		local art = LOOKS[marker.look]
		local alpha = SetArt(marker.Icon, marker.look)
		SetArt(marker.Shadow, marker.look)
		marker.hard = point.hard == true
		if marker.hard then -- (a hard quest's giver: the game's icon on an orange ring)
			marker.Shadow:SetVertexColor(HARD_R, HARD_G, HARD_B, 0.95)
		else
			marker.Shadow:SetVertexColor(0, 0, 0, 0.7)
		end
		marker.Icon:SetDesaturated(art[4] == true)
		local v = art[4] and 0.85 or 1
		marker.Icon:SetVertexColor(v, v, v, alpha)
	end
end

-- Your arrow, where you are on the map shown (hidden when you're not on it, or the game won't say).
local function PlacePlayer(m)
	local x, y
	if m.player and m.map and Q.PlayerAt then
		x, y = Q.PlayerAt(m.map)
	end
	if not (x and y) then
		m.Me:Hide()
		m.meX, m.meY = nil, nil
		return
	end
	m.meX, m.meY = x, y
	m.Me:ClearAllPoints()
	m.Me:SetPoint("CENTER", m.Map, "TOPLEFT", x * m.artW, -y * m.artH)
	local facing = LT.Value(GetPlayerFacing)
	if type(facing) == "number" then
		m.Me:SetRotation(facing)
	end
	m.Me:Show()
end

-- Where the map sits in the box: the point (cx, cy) of the map in the box's middle, kept so the
-- art always covers the box when it's zoomed in.
local function PlaceMap(m)
	local w, h = m.artW, m.artH
	local half = w > m.width and (m.width / 2) / w or 0.5
	local halfY = h > m.height and (m.height / 2) / h or 0.5
	m.cx = math.max(half, math.min(1 - half, m.cx or 0.5))
	m.cy = math.max(halfY, math.min(1 - halfY, m.cy or 0.5))
	m.Map:ClearAllPoints()
	m.Map:SetPoint("TOPLEFT", m.frame, "TOPLEFT", m.width / 2 - m.cx * w, -(m.height / 2 - m.cy * h))
end

-- The cursor's spot on the box (0..width, 0..height from its top left), or nil.
local function CursorOnBox(m)
	local left, top = m.frame:GetLeft(), m.frame:GetTop()
	local x, y = GetCursorPosition()
	local scale = m.frame:GetEffectiveScale()
	if not (left and top and x and y and scale and scale > 0) then
		return nil
	end
	return x / scale - left, top - y / scale
end

local function Hint(m)
	m.Hint:SetText(m.zoom > 1 and L["right-click: whole zone"] or L["wheel: zoom"])
end

local function OnWheel(box, delta)
	local m = box.widget
	if not m.map then
		return
	end
	local bx, by = CursorOnBox(m)
	m:Zoom(m.zoom * (delta > 0 and ZOOM_STEP or 1 / ZOOM_STEP), bx, by)
end

-- Dragging moves the zoomed map: an OnUpdate only while the button is held.
local function DragUpdate(box)
	local m = box.widget
	local bx, by = CursorOnBox(m)
	if bx and m.dragFrom then
		m.cx = m.dragFrom[3] - (bx - m.dragFrom[1]) / m.artW
		m.cy = m.dragFrom[4] - (by - m.dragFrom[2]) / m.artH
		PlaceMap(m)
	end
end

local function OnMouseDown(box, button)
	local m = box.widget
	if button == "RightButton" then
		if m.zoom > 1 then
			m:Zoom(1)
		end
		return
	end
	local bx, by = CursorOnBox(m)
	if m.zoom > 1 and bx then
		m.dragFrom = { bx, by, m.cx, m.cy }
		box:SetScript("OnUpdate", DragUpdate)
	end
end

local function OnMouseUp(box)
	box.widget.dragFrom = nil
	box:SetScript("OnUpdate", nil)
end

function Q.NewMiniMap(parent, width, height)
	local m = setmetatable({ markers = {}, used = 0, width = width or WIDTH, height = height or HEIGHT, player = true,
		zoom = 1, cx = 0.5, cy = 0.5 }, Widget)
	m.artW, m.artH = m.width, m.height
	local box = CreateFrame("Frame", nil, parent)
	box.widget = m
	box:SetSize(m.width, m.height)
	box:SetClipsChildren(true)
	box:EnableMouse(true)
	box:EnableMouseWheel(true)
	box:SetScript("OnMouseWheel", OnWheel)
	box:SetScript("OnMouseDown", OnMouseDown)
	box:SetScript("OnMouseUp", OnMouseUp)
	box:HookScript("OnHide", OnMouseUp)
	local back = box:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.5)
	m.frame = box
	m.Map = CreateFrame("Frame", nil, box)
	m.Map:SetPoint("TOPLEFT")
	m.Map:SetSize(m.width, m.height)
	m.art = LT.MapArt.New(m.Map, nil, nil, nil, true) -- (every area uncovered)
	-- Over the markers: the drop label and your arrow, moved while shown.
	m.Top = CreateFrame("Frame", nil, m.Map)
	m.Top:SetAllPoints()
	m.Top:SetFrameLevel(m.Map:GetFrameLevel() + 6)
	m.Label = m.Top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	m.Label:SetShadowOffset(1, -1)
	m.Label:Hide()
	m.Me = m.Top:CreateTexture(nil, "OVERLAY")
	m.Me:SetTexture(ARROW)
	m.Me:SetSize(18, 18)
	m.Me:Hide()
	local wait = 0
	m.Top:SetScript("OnUpdate", function(_, elapsed)
		wait = wait - elapsed
		if wait <= 0 then
			wait = PLAYER_EVERY
			PlacePlayer(m)
		end
	end)
	-- The zone's name over its top, on a dark strip, with how to zoom at its right end.
	local strip = CreateFrame("Frame", nil, box)
	strip:SetPoint("TOPLEFT")
	strip:SetPoint("TOPRIGHT")
	strip:SetHeight(16)
	strip:SetFrameLevel(m.Map:GetFrameLevel() + 8)
	m.Strip = strip:CreateTexture(nil, "OVERLAY")
	m.Strip:SetAllPoints()
	m.Strip:SetColorTexture(0, 0, 0, 0.6)
	m.Zone = strip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	m.Zone:SetPoint("TOPLEFT", 4, -2)
	m.Zone:SetPoint("TOPRIGHT", -80, -2)
	m.Zone:SetJustifyH("LEFT")
	m.Zone:SetWordWrap(false)
	m.Hint = strip:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	m.Hint:SetPoint("TOPRIGHT", -4, -2)
	m.Hint:SetJustifyH("RIGHT")
	m.StripFrame = strip
	m.Empty = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	m.Empty:SetPoint("CENTER", 0, -6)
	m.Empty:SetText(L["No map of this zone"])
	m.Empty:Hide()
	Hint(m)
	box:Hide()
	return m
end

function Widget:SetSize(width, height)
	if width == self.width and height == self.height then
		return
	end
	self.width, self.height = width, height
	self.frame:SetSize(width, height)
	if self.frame:IsShown() then
		self:Show(self.map, self.points, self.name)
	end
end

function Widget:Hide()
	self.frame:Hide()
	for i = 1, self.used do
		MarkerLeave(self.markers[i])
	end
end

-- Your arrow on the map (on by default).
function Widget:ShowPlayer(on)
	self.player = on ~= false
	PlacePlayer(self)
end

-- Zooms to factor (1: the whole zone, up to 8), keeping the map's spot under (bx, by) (the box's
-- pixels from its top left; nil: its middle) where it is.
function Widget:Zoom(factor, bx, by)
	factor = math.max(1, math.min(ZOOM_MAX, tonumber(factor) or 1))
	if factor == self.zoom or not self.map then
		return
	end
	bx, by = bx or self.width / 2, by or self.height / 2
	local mx = self.cx + (bx - self.width / 2) / self.artW
	local my = self.cy + (by - self.height / 2) / self.artH
	local ratio = factor / self.zoom
	self.zoom = factor
	self.cx = mx - (bx - self.width / 2) / (self.artW * ratio)
	self.cy = my - (by - self.height / 2) / (self.artH * ratio)
	self:Show(self.map, self.points, self.name, true)
	Hint(self)
end

-- The drop label next to the likeliest drop marker: right of it, or left near the right edge.
local function PlaceLabel(m, best)
	if not best then
		m.Label:Hide()
		return
	end
	m.Label:SetText(L["drops here (%s)"]:format(Q.Percent(best.chance)))
	m.Label:ClearAllPoints()
	local half = math.min(best.size, DROP) / 2
	if best.px > m.artW - 90 then
		m.Label:SetPoint("RIGHT", m.Map, "TOPLEFT", best.px - half + 4, -best.py)
	else
		m.Label:SetPoint("LEFT", m.Map, "TOPLEFT", best.px + half - 4, -best.py)
	end
	m.Label:Show()
end

-- One marker for a point (or a line more on a marker near it).
local function Put(m, n, point, width, height)
	local x, y = tonumber(point.x), tonumber(point.y)
	if not (x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1) then
		return n, nil
	end
	local px, py = x * width, y * height
	local drop = point.kind == "drop"
	local line = { point.label or "", point.kind, point.note }
	for i = 1, n do
		local marker = m.markers[i] -- (one marker: givers and turn-ins, drops, an objective's areas)
		local same = Soft(marker.kind) == Soft(point.kind) and (marker.kind ~= "area" or (point.kind == "area" and marker.group == point.group))
		if same and math.abs(marker.px - px) <= NEAR and math.abs(marker.py - py) <= NEAR then
			marker.lines[#marker.lines + 1] = line
			return n, nil
		end
	end
	if n >= MAX_MARKERS then
		return n, nil
	end
	n = n + 1
	local marker = Marker(m, n)
	marker.px, marker.py, marker.x, marker.y, marker.chance = px, py, x, y, tonumber(point.chance)
	marker.lines = { line }
	Dress(m, marker, point)
	marker:ClearAllPoints()
	marker:SetPoint("CENTER", m.Map, "TOPLEFT", px, -py)
	marker:Show()
	return n, drop and marker.chance and marker or nil
end

-- The map's art (as large as fits the box, its own shape, times the zoom) and the markers on it.
-- map nil: the box says there's no map; a map without art: the markers on the dark box, the
-- zone's name over it. Another map than before shows the whole zone.
function Widget:Show(map, points, name, keepZoom)
	if map ~= self.map and not keepZoom then
		self.zoom, self.cx, self.cy, self.lit = 1, 0.5, 0.5, nil
		Hint(self)
	end
	self.map, self.points, self.name = map, points, name
	self.frame:Show()
	local width, height
	if map then
		width, height = LT.MapArt.Lay(self.art, map, self.width * self.zoom, self.height * self.zoom, true)
	else
		LT.MapArt.Forget(self.art)
	end
	self.Empty:SetShown(width == nil)
	width, height = width or self.width * self.zoom, height or self.height * self.zoom
	self.artW, self.artH = width, height
	self.Map:SetSize(width, height)
	PlaceMap(self)
	self.Zone:SetText(name or (map and Q.MapName(map)) or "")
	self.StripFrame:SetShown(map ~= nil)
	local n, best = 0, nil
	for _, point in ipairs(map and points or {}) do
		local drop
		n, drop = Put(self, n, point, width, height)
		if drop and (not best or drop.chance > best.chance) then
			best = drop
		end
	end
	for i = n + 1, self.used do
		MarkerLeave(self.markers[i])
		self.markers[i]:Hide()
	end
	self.used = math.max(n, self.used)
	self.shown = n
	PlaceLabel(self, best)
	PlacePlayer(self)
	if self.lit ~= nil then
		self:Light(self.lit)
	end
end

-- Lights an objective's areas (group) and dims the other objectives' (only alphas change); nil:
-- all as they were.
function Widget:Light(group)
	self.lit = group
	for i = 1, self.shown or 0 do
		local marker = self.markers[i]
		if marker.kind == "area" then
			local alpha = group == nil and AREA_ALPHA or (marker.group == group and AREA_LIT or AREA_DIM)
			marker.Glow:SetVertexColor(AREA_R, AREA_G, AREA_B, alpha)
			marker.Fill:SetVertexColor(AREA_R, AREA_G, AREA_B, group == nil and FILL_ALPHA or (marker.group == group and FILL_LIT or FILL_DIM))
			marker.alpha = alpha
		end
	end
end

-- For tests: the markers shown.
function Widget:Markers()
	local list = {}
	for i = 1, self.shown or 0 do
		list[i] = self.markers[i]
	end
	return list
end
