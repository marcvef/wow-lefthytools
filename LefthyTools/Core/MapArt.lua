local _, ns = ...
local LT = ns.LT

-- LT.MapArt: a zone's map as your world map draws it, laid into a frame of ours (the Bestiary
-- ledger's kill map). The world map's art of the zone: its first layer (C_Map.GetMapArtLayers /
-- GetMapArtLayerTextures), tiles in rows like Blizzard_MapCanvasDetailLayer, the last column and
-- row cut to the map's edge with SetTexCoord, so nothing hangs over. That art leaves what you
-- haven't explored blank; what you have is overlays on it (C_MapExplorationInfo.
-- GetExploredMapTextures, laid like Blizzard's MapExplorationPin), so the map shows what your
-- world map shows. Both checked against the forever branch of Blizzard's UI source.
--   * New(frame, drawLayer, subLevel, mask): a map on that frame, its textures pooled.
--   * Lay(map, mapID, width, height, fit): the zone's art at that size, its top left at the frame's.
--   * SetShown(map, shown), Stale(map).
-- Laid only when the zone, the size or what you've explored changes; never per frame.

local MapArt = {}
LT.MapArt = MapArt

local IsSecret, Value = LT.IsSecret, LT.Value
local explored = 0 -- MAP_EXPLORATION_UPDATED seen so far: a map laid before the last one is laid again
local watcher

-- A number the game gave (nil: none, or a secret).
local function Number(v)
	if not IsSecret(v) and type(v) == "number" then
		return v
	end
end

-- A zone's first art layer: its size and its tiles' size, in the art's pixels (nil: no art, or the
-- game says nothing usable).
local function Layer(mapID)
	local layers = C_Map and Value(C_Map.GetMapArtLayers, mapID)
	local info = type(layers) == "table" and layers[1]
	if IsSecret(info) or type(info) ~= "table" then
		return nil
	end
	local width, height = Number(info.layerWidth), Number(info.layerHeight)
	local tileWidth, tileHeight = Number(info.tileWidth), Number(info.tileHeight)
	if width and height and tileWidth and tileHeight and width > 0 and height > 0 and tileWidth > 0 and tileHeight > 0 then
		return { width = width, height = height, tileWidth = tileWidth, tileHeight = tileHeight }
	end
end

-- The pool's texture n, made the first time it's needed (cut round, or however the map's mask cuts).
local function Texture(map, pool, n, subLevel)
	local texture = pool[n]
	if not texture then
		texture = map.frame:CreateTexture(nil, map.drawLayer, nil, subLevel)
		if map.mask then
			texture:AddMaskTexture(map.mask)
		end
		pool[n] = texture
	end
	return texture
end

-- An explored area's tile along one side: a whole tile, but the last is what's left over, in a file
-- of the next power of two from 16 (as Blizzard's MapExplorationPin reads them): its pixels, the file's.
local function OverlayPart(size, tile, last)
	if not last then
		return tile, tile
	end
	local pixels = size % tile
	pixels = pixels > 0 and pixels or tile
	local file = 16
	while file < pixels do
		file = file * 2
	end
	return pixels, file
end

-- An area you've explored, on the art: its tiles in rows from its offset (the layer's pixels, scaled
-- like the base tiles), cut at the map's edge; one shown only on mouseover isn't explored. Over the
-- art, some over the other areas (as Blizzard draws them). Returns how many of the pool are in use.
local function LayOverlay(map, info, layer, sx, sy, n)
	local width, height = Number(info.textureWidth), Number(info.textureHeight)
	local files, mouseOver = info.fileDataIDs, info.isShownByMouseOver
	if not (width and height and width > 0 and height > 0) or IsSecret(files) or type(files) ~= "table"
		or IsSecret(mouseOver) or mouseOver == true then
		return n
	end
	local onTop = not IsSecret(info.isDrawOnTopLayer) and info.isDrawOnTopLayer == true
	local x0, y0 = Number(info.offsetX) or 0, Number(info.offsetY) or 0
	local wide, tall = math.ceil(width / layer.tileWidth), math.ceil(height / layer.tileHeight)
	for row = 1, tall do
		local y = y0 + (row - 1) * layer.tileHeight
		local h, fileH = OverlayPart(height, layer.tileHeight, row == tall)
		h = math.min(h, layer.height - y)
		for col = 1, wide do
			local x = x0 + (col - 1) * layer.tileWidth
			local w, fileW = OverlayPart(width, layer.tileWidth, col == wide)
			w = math.min(w, layer.width - x)
			local file = files[(row - 1) * wide + col]
			if file and not IsSecret(file) and w > 0 and h > 0 then
				n = n + 1
				local tile = Texture(map, map.overlays, n, map.subLevel + 1)
				tile:SetDrawLayer(map.drawLayer, map.subLevel + (onTop and 2 or 1))
				tile:SetTexture(file)
				tile:SetTexCoord(0, w / fileW, 0, h / fileH)
				tile:SetSize(w * sx, h * sy)
				tile:ClearAllPoints()
				tile:SetPoint("TOPLEFT", map.frame, "TOPLEFT", x * sx, -y * sy)
				tile:SetShown(map.shown)
			end
		end
	end
	return n
end

local function HideFrom(pool, n)
	for i = n + 1, #pool do
		pool[i]:Hide()
	end
end

-- A map on a frame: the art's tiles at drawLayer's subLevel (default ARTWORK 0), what you've
-- explored over them (subLevel + 1 and + 2: keep those free), each texture cut by mask if given.
-- Shown when laid (SetShown hides it, also what's laid later). Once one exists, a frame of ours
-- notes MAP_EXPLORATION_UPDATED (only a count: maps are laid again when next asked for).
function MapArt.New(frame, drawLayer, subLevel, mask)
	if not watcher then
		watcher = CreateFrame("Frame")
		watcher:RegisterEvent("MAP_EXPLORATION_UPDATED")
		watcher:SetScript("OnEvent", function()
			explored = explored + 1
		end)
	end
	return { frame = frame, drawLayer = drawLayer or "ARTWORK", subLevel = subLevel or 0, mask = mask,
		tiles = {}, overlays = {}, tileCount = 0, overlayCount = 0, shown = true }
end

-- Lays the world map's art of mapID and what you've explored of it, from the frame's top left: the
-- whole layer width x height (the art's pixels scaled to it; fit: as large as fits in it, the art's
-- own shape), the textures from the pool, the rest of it hidden. Returns the width and height it
-- takes, or nil: no art (nothing shown); the game saying nothing about what you've explored: the art
-- alone. The same map, size and exploring as last time: nothing to do.
function MapArt.Lay(map, mapID, width, height, fit)
	if map.mapID == mapID and map.askWidth == width and map.askHeight == height and map.fit == fit
		and map.explored == explored then
		return map.width, map.height
	end
	map.mapID, map.askWidth, map.askHeight, map.fit, map.explored = mapID, width, height, fit, explored
	map.width, map.height = nil, nil
	local layer = mapID and width and height and width > 0 and height > 0 and Layer(mapID)
	local textures = layer and Value(C_Map.GetMapArtLayerTextures, mapID, 1)
	local n, o = 0, 0
	if type(textures) == "table" then
		local sx, sy = width / layer.width, height / layer.height
		if fit then
			sx = math.min(sx, sy)
			sy = sx
		end
		local cols = math.ceil(layer.width / layer.tileWidth)
		for row = 1, math.ceil(layer.height / layer.tileHeight) do
			for col = 1, cols do
				local file = textures[(row - 1) * cols + col]
				if file and not IsSecret(file) then
					n = n + 1
					local tile = Texture(map, map.tiles, n, map.subLevel)
					local w = math.min(layer.tileWidth, layer.width - (col - 1) * layer.tileWidth)
					local h = math.min(layer.tileHeight, layer.height - (row - 1) * layer.tileHeight)
					tile:SetTexture(file)
					tile:SetTexCoord(0, w / layer.tileWidth, 0, h / layer.tileHeight)
					tile:SetSize(w * sx, h * sy)
					tile:ClearAllPoints()
					tile:SetPoint("TOPLEFT", map.frame, "TOPLEFT", (col - 1) * layer.tileWidth * sx, -(row - 1) * layer.tileHeight * sy)
					tile:SetShown(map.shown)
				end
			end
		end
		local areas = C_MapExplorationInfo and Value(C_MapExplorationInfo.GetExploredMapTextures, mapID)
		for _, info in ipairs(type(areas) == "table" and areas or {}) do
			if not IsSecret(info) and type(info) == "table" then
				o = LayOverlay(map, info, layer, sx, sy, o)
			end
		end
		map.width, map.height = layer.width * sx, layer.height * sy
	end
	HideFrom(map.tiles, n)
	HideFrom(map.overlays, o)
	map.tileCount, map.overlayCount = n, o
	return map.width, map.height
end

-- Shows or hides what's laid (and what's laid from now on).
function MapArt.SetShown(map, shown)
	map.shown = shown
	for i = 1, map.tileCount do
		map.tiles[i]:SetShown(shown)
	end
	for i = 1, map.overlayCount do
		map.overlays[i]:SetShown(shown)
	end
end

-- true when you've explored more since the art shown was laid (Lay lays it again).
function MapArt.Stale(map)
	return map.width ~= nil and map.explored ~= explored
end
