local _, ns = ...
local LT = ns.LT
local L = ns.L
local Q = ns.Questtree or {}; ns.Questtree = Q

-- The small zone map: a zone's map as your world map draws it (LT.MapArt, Core/MapArt.lua: the
-- world map's art and what you've explored of it, as the fight stream's map and the Bestiary
-- ledger's), in a frame of ours, with a marker at each quest giver and turn-in. Never the world map
-- itself: nothing of WorldMapFrame is touched (no pins, no data providers).
--   local m = Q.NewMiniMap(parent[, width, height])  -- default 240 x 160 (a zone's art is 3:2)
--   m.frame                                         -- to anchor it
--   m:Show(map, points[, name])                     -- points = { { x, y, kind = "start" | "end", label } }
--   m:SetSize(width, height), m:Hide()
-- x and y are 0..1 on that map. Markers closer than a few pixels become one (a giver who's also the
-- turn-in), its tooltip with each label. The art is laid only when the map or the size changes (or
-- you've explored more); nothing runs per frame. The markers are buttons, so a controller's cursor
-- reaches them (its focus shows the tooltip).

local WIDTH, HEIGHT = 240, 160
local MARKER = 18
local NEAR = 6           -- px: markers this close are one
local MAX_MARKERS = 40   -- (an item from mobs can start a quest in many places)
local ICONS = {
	start = "Interface\\GossipFrame\\AvailableQuestIcon",
	["end"] = "Interface\\GossipFrame\\ActiveQuestIcon",
}
local KINDS = { start = L["Quest giver"], ["end"] = L["Turn-in"] }

local Widget = {}
Widget.__index = Widget

local function MarkerEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	for i, line in ipairs(self.lines) do
		if i == 1 then
			GameTooltip:SetText(line[1], 1, 1, 1)
		else
			GameTooltip:AddLine(line[1], 1, 1, 1)
		end
		GameTooltip:AddLine(KINDS[line[2]] or "", 0.7, 0.7, 0.7)
	end
	GameTooltip:Show()
end

local function MarkerLeave(self)
	if GameTooltip:IsOwned(self) then
		GameTooltip:Hide()
	end
end

local function Marker(m, i)
	local marker = m.markers[i]
	if not marker then
		marker = CreateFrame("Button", nil, m.Map)
		marker:SetSize(MARKER, MARKER)
		marker:SetFrameLevel(m.Map:GetFrameLevel() + 2)
		marker.Icon = marker:CreateTexture(nil, "ARTWORK")
		marker.Icon:SetAllPoints()
		marker:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
		marker:SetScript("OnEnter", MarkerEnter)
		marker:SetScript("OnLeave", MarkerLeave)
		marker.lines = {}
		m.markers[i] = marker
	end
	return marker
end

function Q.NewMiniMap(parent, width, height)
	local m = setmetatable({ markers = {}, used = 0, width = width or WIDTH, height = height or HEIGHT }, Widget)
	local box = CreateFrame("Frame", nil, parent)
	box:SetSize(m.width, m.height)
	local back = box:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.5)
	m.frame = box
	m.Map = CreateFrame("Frame", nil, box)
	m.Map:SetPoint("CENTER")
	m.Map:SetSize(m.width, m.height)
	m.art = LT.MapArt.New(m.Map)
	-- The zone's name over its top left corner, on a dark strip.
	m.Strip = box:CreateTexture(nil, "OVERLAY")
	m.Strip:SetPoint("TOPLEFT")
	m.Strip:SetPoint("TOPRIGHT")
	m.Strip:SetHeight(16)
	m.Strip:SetColorTexture(0, 0, 0, 0.55)
	m.Zone = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	m.Zone:SetPoint("TOPLEFT", 4, -2)
	m.Zone:SetPoint("TOPRIGHT", -4, -2)
	m.Zone:SetJustifyH("LEFT")
	m.Zone:SetWordWrap(false)
	m.Empty = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	m.Empty:SetPoint("CENTER", 0, -6)
	m.Empty:SetText(L["No map of this zone"])
	m.Empty:Hide()
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

-- The map's art (as large as fits the box, its own shape) and the markers on it. map nil: the box
-- says there's no map; a map without art: the markers on the dark box, the zone's name over it.
function Widget:Show(map, points, name)
	self.map, self.points, self.name = map, points, name
	self.frame:Show()
	local width, height
	if map then
		width, height = LT.MapArt.Lay(self.art, map, self.width, self.height, true)
	else
		LT.MapArt.Forget(self.art)
	end
	self.Empty:SetShown(width == nil)
	width, height = width or self.width, height or self.height
	self.Map:SetSize(width, height)
	self.Zone:SetText(name or (map and Q.MapName(map)) or "")
	self.Strip:SetShown(map ~= nil)
	local n = 0
	for _, point in ipairs(map and points or {}) do
		local x, y = tonumber(point.x), tonumber(point.y)
		if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
			local px, py = x * width, y * height
			local near
			for i = 1, n do
				local marker = self.markers[i]
				if math.abs(marker.px - px) <= NEAR and math.abs(marker.py - py) <= NEAR then
					near = marker
					break
				end
			end
			if near then
				near.lines[#near.lines + 1] = { point.label or "", point.kind }
			elseif n < MAX_MARKERS then
				n = n + 1
				local marker = Marker(self, n)
				marker.px, marker.py, marker.kind = px, py, point.kind
				marker.lines = { { point.label or "", point.kind } }
				marker.Icon:SetTexture(ICONS[point.kind] or ICONS.start)
				marker:ClearAllPoints()
				marker:SetPoint("CENTER", self.Map, "TOPLEFT", px, -py)
				marker:Show()
			end
		end
	end
	for i = n + 1, self.used do
		MarkerLeave(self.markers[i])
		self.markers[i]:Hide()
	end
	self.used = math.max(n, self.used)
	self.shown = n
end

-- For tests: the markers shown.
function Widget:Markers()
	local list = {}
	for i = 1, self.shown or 0 do
		list[i] = self.markers[i]
	end
	return list
end
