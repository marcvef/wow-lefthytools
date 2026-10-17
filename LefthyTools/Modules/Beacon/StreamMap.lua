local _, ns = ...
local LT = ns.LT
local B = ns.Beacon
local S = B.Stream

-- The fight stream's map under a window's radar (StreamView.lua builds the window: win.Map, cut
-- round, and win.Plain, the rings' discs for when there's no map): the minimap's own terrain tiles
-- (Data/MinimapTiles.lua: 256 px for 533.33 yd of the world's grid, the 3 x 3 around the place),
-- else the world map's art of the zone with what you've explored of it (LT.MapArt, Core/MapArt.lua,
-- like the Bestiary ledger's map; yours, also on a friend's stream: what your world map shows),
-- else none (the plain discs). To the windows' one scale (S.PX_PER_YARD: a yard on the map is a
-- yard on the rings), north up, the place in the middle. S.MoveMap every frame: textures change only
-- when the place reaches another tile or zone (or you've explored more), the anchor only when the
-- map moved.

local Value, issecret = S.Value, S.issecret
local PX_PER_YARD, GLIDE = S.PX_PER_YARD, S.GLIDE
local TILE_YARDS = 1600 / 3

local function MapCorner(mapID, x, y)
	local ok, _, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
	if ok and pos and not issecret(pos) then
		return pos:GetXY()
	end
end

-- The world map's art of a zone with what you've explored of it, to scale (the zone's corners in
-- the world: its yards), cut round; laid anew (a zone, a window opened, explored more), hidden:
-- MoveMap shows it when it's the one in use.
local function SetupMap(view, mapID)
	local map, win = view.map, view.win
	map.id, map.ok, map.x = mapID, false, nil
	map.art = map.art or LT.MapArt.New(win.Map, "BACKGROUND", 0, win.Map.Round)
	LT.MapArt.Forget(map.art)
	LT.MapArt.SetShown(map.art, false)
	local north0, west0 = MapCorner(mapID, 0, 0)
	local north1, west1 = MapCorner(mapID, 1, 1)
	if north0 and north1 and west0 > west1 and north0 > north1 then
		map.ok = LT.MapArt.Lay(map.art, mapID, (west0 - west1) * PX_PER_YARD, (north0 - north1) * PX_PER_YARD) ~= nil
		map.north0, map.west0 = north0, west0
	end
	if map.source == "art" then
		map.source = nil
	end
end

-- The minimap's own terrain tiles, the 3 x 3 of the world's grid around (x0, y0 the top left one).
local function LayMinimap(view, tiles, continent, x0, y0)
	local map, win = view.map, view.win
	map.continent, map.x0, map.y0, map.x = continent, x0, y0, nil
	local size = TILE_YARDS * PX_PER_YARD
	map.mini = map.mini or {}
	for i = 0, 2 do
		for j = 0, 2 do
			local n = i * 3 + j + 1
			local tile = map.mini[n]
			if not tile then
				tile = win.Map:CreateTexture(nil, "BACKGROUND", nil, 1)
				tile:AddMaskTexture(win.Map.Round)
				tile:SetSize(size, size)
				map.mini[n] = tile
			end
			local file = tiles[(x0 + i) * 100 + (y0 + j)]
			if file then
				tile:SetTexture(file)
				tile:ClearAllPoints()
				tile:SetPoint("TOPLEFT", win.Map, "TOPLEFT", i * size, -j * size)
			end
			tile.has = file ~= nil
		end
	end
end

-- Which tiles show: the minimap's ("mini"), the world map's art ("art") or none.
local function UseTiles(view, source)
	local map = view.map
	if source ~= map.source then
		map.source, map.x = source, nil
	end
	for _, tile in ipairs(map.mini or {}) do
		tile:SetShown(source == "mini" and tile.has)
	end
	if map.art then
		LT.MapArt.SetShown(map.art, source == "art")
	end
end

-- The map under a place (north, west on continent; mapID for the world map's art); glide: move
-- there smoothly (a friend's place comes twice a second) instead of at once.
function S.MoveMap(view, north, west, continent, mapID, elapsed)
	local map, win = view.map, view.win
	if mapID ~= map.id or (map.art and LT.MapArt.Stale(map.art)) then
		SetupMap(view, mapID)
	end
	local tiles = north and continent and ns.MINIMAP_TILES and ns.MINIMAP_TILES[continent]
	local x, y
	if tiles then
		local tx, ty = 32 - west / TILE_YARDS, 32 - north / TILE_YARDS
		local x0, y0 = math.floor(tx) - 1, math.floor(ty) - 1
		if not map.mini or x0 ~= map.x0 or y0 ~= map.y0 or continent ~= map.continent or map.source ~= "mini" then
			LayMinimap(view, tiles, continent, x0, y0)
			UseTiles(view, "mini")
		end
		x, y = -(tx - x0) * TILE_YARDS * PX_PER_YARD, (ty - y0) * TILE_YARDS * PX_PER_YARD
	elseif north and map.ok then
		if map.source ~= "art" then
			UseTiles(view, "art")
		end
		x, y = -(map.west0 - west) * PX_PER_YARD, (map.north0 - north) * PX_PER_YARD
	end
	win.Map:SetShown(x ~= nil)
	win.Plain:SetShown(x == nil)
	if not x then
		return
	end
	if elapsed and map.x and math.abs(x - map.x) + math.abs(y - map.y) < 100 then
		local k = math.min(1, elapsed * GLIDE)
		x, y = map.x + (x - map.x) * k, map.y + (y - map.y) * k
	end
	if not map.x or math.abs(x - map.x) + math.abs(y - map.y) > 0.2 then
		map.x, map.y = x, y
		win.Map:ClearAllPoints()
		win.Map:SetPoint("TOPLEFT", win.Radar, "CENTER", x, y)
	end
end
