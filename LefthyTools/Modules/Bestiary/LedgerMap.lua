local _, ns = ...
local LT = ns.LT
local L = ns.L
local Bt = ns.Bestiary
local GOLD, Value, issecret = Bt.GOLD, Bt.Value, Bt.issecret

-- The ledger's map of where you killed a kind of mob (Bt.Spots: its last kills outside instances),
-- beside its details: the world map's art of a zone with what you've explored of it, a dot per kill,
-- the zone's name over it or a picker of its zones. Bt.NewKillMap builds it on the ledger's pane,
-- Bt.DrawKillMap shows a mob's kills on it.

local MAP_W, MAP_H = 330, 220 -- the map's box (a zone's art is 3:2)
local MAP_HEAD = 24         -- the row over it: a heading, the zone's name or a picker of its zones
local ZONE_PICK_W = 180     -- (its list too: "Stranglethorn Vale (50)" fits)
local MAP_DOT = 6           -- a kill on the map
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
Bt.KILL_MAP_W, Bt.KILL_MAP_H, Bt.KILL_MAP_HEAD = MAP_W, MAP_H, MAP_HEAD -- (the ledger lays out around it)

local function MapName(mapID)
	local info = C_Map and Value(C_Map.GetMapInfo, mapID)
	local name = type(info) == "table" and info.name
	return not issecret(name) and type(name) == "string" and name or ("#" .. mapID)
end

-- The world map's art of a zone with what you've explored of it (LT.MapArt, Core/MapArt.lua: laid
-- like Blizzard_MapCanvasDetailLayer and MapExplorationPin, as the fight stream's map), as large as
-- fits the map's box (MAP_W x MAP_H), so the map shows what your world map shows (the user: "ideally
-- the same visibility the player has"). No art: the box's dark back alone. Returns its width and
-- height; laid again only for another map, or once you've explored more.
local function LayMap(where, mapID)
	local width, height = LT.MapArt.Lay(where.art, mapID, MAP_W, MAP_H, true)
	width, height = width or MAP_W, height or MAP_H
	where.Map:SetSize(width, height)
	return width, height
end

-- A zone in the picker (and on it): its name and your kills there.
local function ZoneLabel(spots)
	return ("%s (%d)"):format(MapName(spots.map), #spots.xy / 2)
end

-- Where you killed it (Bt.Spots: the last SPOTS_KEEP kills, outside instances), beside its details:
-- the zone picked (where.zone; at first the one with the most kills), a dot each (the older, the
-- fainter). Over it the zone's name, or a picker of them when there are more (the most kills first,
-- each with its kills); under it that only the last kills are kept. None known: the box says so.
local function Where(where, mob)
	local maps = Bt.Spots(mob)
	local shown = maps and maps[1]
	for _, spots in ipairs(maps or {}) do
		if spots.map == where.zone then
			shown = spots
		end
	end
	where.mob, where.maps, where.shown = mob, maps, shown
	local several = maps ~= nil and maps[2] ~= nil
	where.Pick:SetShown(several)
	where.Zone:SetShown(shown ~= nil and not several)
	where.Map:SetShown(shown ~= nil)
	where.Empty:SetShown(shown == nil)
	where.Note:SetShown(shown ~= nil and #mob.spots >= Bt.SPOTS_KEEP)
	-- (the heading's rule runs up to the zone's name or the picker)
	local right = several and where.Pick or shown and where.Zone
	where.Rule:ClearAllPoints()
	where.Rule:SetPoint("LEFT", where.Heading, "RIGHT", 8, 0)
	if right then
		where.Rule:SetPoint("RIGHT", right, "LEFT", -8, 0)
	else
		where.Rule:SetPoint("RIGHT", where.Box, "TOPRIGHT", 0, MAP_HEAD / 2 + 4)
	end
	if not shown then
		return
	end
	if several then
		where.Pick:SetLabel(ZoneLabel(shown))
	else
		where.Zone:SetText(MapName(shown.map))
	end
	local width, height = LayMap(where, shown.map)
	local count = #shown.xy / 2
	for i = 1, math.max(count, #where.dots) do
		local dot = where.dots[i]
		if i <= count then
			if not dot then -- (a red dot in a dark ring: seen on any map's colours)
				dot = where.Map:CreateTexture(nil, "OVERLAY", nil, 2)
				dot:SetTexture(CIRCLE)
				dot:SetSize(MAP_DOT, MAP_DOT)
				dot:SetVertexColor(1, 0.25, 0.15)
				dot.Ring = where.Map:CreateTexture(nil, "OVERLAY", nil, 1)
				dot.Ring:SetTexture(CIRCLE)
				dot.Ring:SetSize(MAP_DOT + 3, MAP_DOT + 3)
				dot.Ring:SetVertexColor(0, 0, 0, 0.8)
				dot.Ring:SetPoint("CENTER", dot, "CENTER")
				where.dots[i] = dot
			end
			dot:ClearAllPoints()
			dot:SetPoint("CENTER", where.Map, "TOPLEFT", shown.xy[2 * i - 1] * width, -shown.xy[2 * i] * height)
			dot:SetAlpha(0.45 + 0.55 * i / count) -- (the newest the brightest)
			dot.Ring:SetAlpha(0.45 + 0.55 * i / count)
			dot:Show()
			dot.Ring:Show()
		elseif dot then
			dot:Hide()
			dot.Ring:Hide()
		end
	end
end

-- Builds the map on the ledger's picked mob's pane, x from the pane's left (MAP_HEAD under its top):
-- a heading with the zone's name or a picker of its zones (ours, like the sort's), the map's box (a
-- dark back under the art and what you've explored of it, the dots on top; none known: a quiet line),
-- a line under it. Returns it (Bt.DrawKillMap draws on it).
function Bt.NewKillMap(pane, x)
	local where = { dots = {} }
	where.Box = CreateFrame("Frame", nil, pane)
	where.Box:SetPoint("TOPLEFT", x, -(MAP_HEAD + 4))
	where.Box:SetSize(MAP_W, MAP_H)
	local mapBack = where.Box:CreateTexture(nil, "BACKGROUND")
	mapBack:SetAllPoints()
	mapBack:SetColorTexture(0, 0, 0, 0.45)
	where.Map = CreateFrame("Frame", nil, where.Box)
	where.Map:SetPoint("CENTER")
	where.Map:SetSize(MAP_W, MAP_H)
	where.art = LT.MapArt.New(where.Map) -- (the art and what you've explored, under the dots)
	where.Heading = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	where.Heading:SetPoint("LEFT", where.Box, "TOPLEFT", 0, MAP_HEAD / 2 + 4)
	where.Heading:SetText(L["Where you killed them"])
	where.Rule = pane:CreateTexture(nil, "ARTWORK")
	where.Rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
	where.Rule:SetHeight(1)
	where.Zone = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	where.Zone:SetPoint("RIGHT", where.Box, "TOPRIGHT", 0, MAP_HEAD / 2 + 4)
	where.Zone:SetWordWrap(false)
	where.Pick = LT.Window.AddPicker(pane, ZONE_PICK_W, function()
		local list = {}
		for _, spots in ipairs(where.maps or {}) do
			list[#list + 1] = { text = ZoneLabel(spots), value = spots.map, selected = spots == where.shown }
		end
		return list
	end, function(map)
		where.zone = map
		Where(where, where.mob)
	end)
	where.Pick:SetPoint("RIGHT", where.Box, "TOPRIGHT", 0, MAP_HEAD / 2 + 4)
	where.Empty = where.Box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	where.Empty:SetPoint("CENTER")
	where.Empty:SetText(L["No kills on a map yet"])
	where.Note = pane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	where.Note:SetPoint("TOPLEFT", where.Box, "BOTTOMLEFT", 0, -4)
	where.Note:SetWidth(MAP_W)
	where.Note:SetJustifyH("LEFT")
	where.Note:SetWordWrap(false)
	where.Note:SetText(L["Your last %d kills."]:format(Bt.SPOTS_KEEP))
	return where
end

Bt.DrawKillMap = Where
