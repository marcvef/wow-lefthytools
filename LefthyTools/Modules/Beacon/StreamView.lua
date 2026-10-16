local _, ns = ...
local LT = ns.LT
local L = ns.L
local M = LT:GetModule("beacon")
local B = ns.Beacon
local S = B.Stream

-- The fight stream's windows: yours ("me": the sensor's picture, StreamSense.lua), the preview (a
-- made-up fight) and one per friend you watch (their pictures, StreamNet.lua). Each draws the same
-- way: the map of the place under a radar, north up, to scale (one scale for rings, dots and map),
-- the one it shows in the middle (an arrow turning with their facing; a skull when dead), a dot per
-- mob (red: attacking them, orange: in combat, grey: not; gold ring: elite, silver: rare; a white
-- ring and its name: their target; a purple glow while casting; a skull that fades when it dies;
-- faint while its direction is still a guess), and under it what they're doing (the spell being
-- cast with its bar, the last spells), their health (estimated: "~80%"), power and form at the
-- top, and a bottom line ("2 on you · 5 near · X casts Y"). What happens to them floats up over
-- the radar: hits (red, left of them), heals (green, right), a dodge or miss, XP from the mob that
-- died, loot (green and better); their kills since the window opened at the top right.
--
-- The map: the minimap's own terrain tiles (Data/MinimapTiles.lua: 256 px for 533.33 yd of the
-- world's grid, the 3 x 3 around), else the world map's art of the zone (C_Map.GetMapArtLayers /
-- GetMapArtLayerTextures, laid like Blizzard_MapCanvasDetailLayer), else plain rings; cut round,
-- a little darker. Frames can't turn, so north is up and the arrow turns.
--
-- Windows are small and can be dragged and resized (the grip at the bottom right; sizes kept per
-- kind in LefthyToolsDB.streamWindows). Yours sits in the interface (and pauses a cinematic flight,
-- like any window); friends' windows float above everything (also above a flight's film, which
-- they don't pause), stacked from the top left. Cost: an OnUpdate per open window (dots and map
-- glide), nothing when none is open.

local WIDTH, HEIGHT, RADAR = 250, 432, 220
local OUTER_YARDS = S.OUTER_YARDS
local RINGS = { 40, 30, 20, 10 }
local MAX_DOTS = S.MAX_MOBS
local NAMES = 4            -- the nearest mobs show their name
local GLIDE = 6            -- how fast dots (and a friend's map) glide to their new spot
local DEAD_FADE = 3
local RECENT_TIME = 12     -- seconds a recent spell stays, fading
local STALE = 6            -- seconds without a picture from a friend: "waiting"
local CAST_BAR = 100
local SCALES = { me = 0.8, friend = 0.55 } -- default sizes; the grip changes them
local MIN_SCALE, MAX_SCALE = 0.35, 1.3
local PX_PER_YARD = (RADAR / 2 - 8) / OUTER_YARDS
local TILE_YARDS = 1600 / 3
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local ARROW = "Interface\\Minimap\\MinimapArrow"
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local GRIP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
local GOLD = { 1, 0.82, 0.3 }
local POWER_COLORS = { MANA = { 0.2, 0.45, 1 }, RAGE = { 0.9, 0.15, 0.15 }, ENERGY = { 1, 0.9, 0.2 }, FOCUS = { 1, 0.5, 0.25 } }
local HEALTH_COLOR = { 0.25, 0.8, 0.3 }
local BAR = 120            -- the health and power bars' width
local FLOATS = 10          -- floating numbers at once, per window
local FLOAT_TIME = 1.6     -- seconds one floats
local LOOT_TIME = 3.5
local SEEN_FOR = 6         -- seconds a moment's number counts as shown (they come round: 1-99)
local HURT_COLOR, HEAL_COLOR, AVOID_COLOR, XP_COLOR = { 1, 0.3, 0.25 }, { 0.35, 1, 0.4 }, { 0.9, 0.9, 0.9 }, { 0.75, 0.6, 1 }
local FOES = 5             -- the mobs fought, in the row under the spells
local FOE_W, FOE_H = 40, 50 -- a foe's model (the whole mob), px
local FOE_GAP = ((WIDTH - 24) - FOES * (FOE_W + 2)) / (FOES - 1)
local FOE_FACING = 0.45    -- turned a little (radians): not straight at you
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local PREVIEW_FRIEND, PREVIEW_CLASS = "Anna", "MAGE"
local Value, issecret = S.Value, S.issecret

local views = {}   -- key ("me", or a friend's gameAccountID) -> view
local spare = {}   -- friends' windows not in use (frames can't be destroyed)
local friendCount = 0

---------------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------------

local function Circle(parent, layer, sublevel, size)
	local texture = parent:CreateTexture(nil, layer, nil, sublevel)
	texture:SetSize(size, size)
	texture:SetPoint("CENTER")
	local mask = parent:CreateMaskTexture()
	mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetSize(size, size)
	mask:SetPoint("CENTER")
	texture:AddMaskTexture(mask)
	return texture
end

-- Why a view's health isn't known (nil: it is): "old" (a friend's build from before health went
-- along), "max" (the maximum is hidden there), "wait" (no checkpoint yet; or a friend's build that
-- said nothing yet).
local HEALTH_SINCE = "0.5.0-114-g060a4af"
local function HealthWhy(view)
	local picture = view.picture
	if picture.health then
		return nil
	elseif picture.healthWhy then
		return picture.healthWhy
	elseif view.kind == "friend" and not picture.vitals and LT.CompareVersions(picture.version, HEALTH_SINCE) == -1 then
		return "old"
	end
	return "wait"
end

local function ClassLabel(class)
	if class == "elite" or class == "worldboss" then
		return L["Elite"]
	elseif class == "rare" then
		return L["Rare"]
	elseif class == "rareelite" then
		return L["Rare elite"]
	end
end

-- Whose window: nil for yours, else the friend's (or the preview's) name.
local function Whose(view)
	if view.kind == "me" then
		return nil
	end
	return view.picture.name or "?"
end

local function DotOnEnter(dot)
	local mob, view = dot.mob, dot.view
	if not mob then
		return
	end
	local who = Whose(view)
	GameTooltip:SetOwner(dot, "ANCHOR_RIGHT")
	if mob.player then
		local r, g, b = B.ClassColor(mob.classFile)
		GameTooltip:SetText(mob.level and ("%s (%s)"):format(mob.name, mob.level) or mob.name, r, g, b)
		if mob.group then
			GameTooltip:AddLine(who and L["In %s's group"]:format(who) or L["In your group"], 0.3, 0.65, 1)
		else
			GameTooltip:AddLine(mob.friendly and L["Friendly player"] or L["Enemy player"], mob.friendly and 0.9 or 1,
				mob.friendly and 0.9 or 0.3, mob.friendly and 0.9 or 0.25)
		end
		if mob.dead then
			GameTooltip:AddLine(L["dead"], 0.7, 0.7, 0.7)
		elseif mob.combat then
			GameTooltip:AddLine(L["in combat"], 1, 0.6, 0.2)
		end
		if mob.casting and not mob.dead then
			GameTooltip:AddLine(L["casting %s"]:format(mob.casting), 0.8, 0.6, 1)
		end
		if mob.exact then
			GameTooltip:AddLine(L["%d yd away"]:format(mob.exact), 0.8, 0.8, 0.8)
		else
			GameTooltip:AddLine(mob.beyond and L["more than %d yd away"]:format(mob.beyond)
				or mob.yards and L["about %d yd"]:format(math.floor(mob.yards + 0.5)) or L["distance unknown"], 0.8, 0.8, 0.8)
		end
		if (mob.sure or 1) < 0.6 then
			GameTooltip:AddLine(view.kind == "me" and L["direction still unsure: move and turn"] or L["direction still unsure"],
				0.6, 0.6, 0.6, true)
		end
		GameTooltip:Show()
		return
	end
	GameTooltip:SetText(mob.level and ("%s (%s)"):format(mob.name, mob.level) or mob.name, 1, 1, 1)
	local class = ClassLabel(mob.class)
	if class then
		GameTooltip:AddLine(class, GOLD[1], GOLD[2], GOLD[3])
	end
	if mob.dead then
		GameTooltip:AddLine(L["dead"], 0.7, 0.7, 0.7)
	else
		if mob.attacking then
			GameTooltip:AddLine(who and L["attacking %s"]:format(who) or L["attacking you"], 1, 0.3, 0.25)
		elseif mob.combat then
			GameTooltip:AddLine(L["in combat"], 1, 0.6, 0.2)
		end
		if mob.casting then
			GameTooltip:AddLine(L["casting %s"]:format(mob.casting), 0.8, 0.6, 1)
		end
	end
	GameTooltip:AddLine(mob.beyond and L["more than %d yd away"]:format(mob.beyond)
		or mob.yards and L["about %d yd"]:format(math.floor(mob.yards + 0.5)) or L["distance unknown"], 0.8, 0.8, 0.8)
	if mob.target then
		GameTooltip:AddLine(who and L["%s's target"]:format(who) or L["your target"], 0.8, 0.8, 0.8)
	end
	if mob.remembered and mob.age then
		GameTooltip:AddLine(who and L["%s: off screen for %d s"]:format(who, math.floor(mob.age + 0.5))
			or L["off your screen for %d s"]:format(math.floor(mob.age + 0.5)), 0.6, 0.6, 0.6)
	end
	if (mob.sure or 1) < 0.6 then
		GameTooltip:AddLine(view.kind == "me" and L["direction still unsure: move and turn"] or L["direction still unsure"],
			0.6, 0.6, 0.6, true)
	end
	GameTooltip:Show()
end

local function NewDot(view)
	local dot = CreateFrame("Frame", nil, view.win.Radar)
	dot.view = view
	dot:SetSize(16, 16)
	dot.Glow = Circle(dot, "BACKGROUND", 0, 26)
	dot.Glow:SetColorTexture(0.75, 0.45, 1, 1)
	dot.Glow:SetBlendMode("ADD")
	dot.Target = Circle(dot, "BORDER", -1, 20)
	dot.Target:SetColorTexture(1, 1, 1, 0.85)
	dot.Ring = Circle(dot, "BORDER", 0, 16)
	dot.Body = Circle(dot, "ARTWORK", 0, 11)
	dot.Skull = dot:CreateTexture(nil, "OVERLAY")
	dot.Skull:SetTexture(SKULL)
	dot.Skull:SetSize(14, 14)
	dot.Skull:SetPoint("CENTER")
	dot.Name = dot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	dot.Name:SetPoint("LEFT", dot, "RIGHT", 1, 0)
	dot.Name:SetTextScale(0.85)
	dot:EnableMouse(true)
	dot:SetScript("OnEnter", DotOnEnter)
	dot:SetScript("OnLeave", function() GameTooltip:Hide() end)
	dot:Hide()
	return dot
end

local function FreeDot(view)
	for i = 1, MAX_DOTS do
		view.dots[i] = view.dots[i] or NewDot(view)
		if not view.dots[i].key then
			return view.dots[i]
		end
	end
end

local function Release(view, dot)
	if dot.key then
		view.dotFor[dot.key] = nil
	end
	dot.key, dot.mob, dot.deadAt = nil, nil, nil
	dot:Hide()
end

local function ReleaseAll(view)
	for _, dot in ipairs(view.dots) do
		Release(view, dot)
	end
end

-- Where a mob goes on the radar, north up: its bearing (radians clockwise from north) and distance
-- (beyond every check: on the rim).
local function Spot(mob)
	local yards = mob.beyond and OUTER_YARDS or mob.yards and math.min(mob.yards, OUTER_YARDS) or OUTER_YARDS * 0.85
	local r = yards * PX_PER_YARD
	local angle = mob.bearing or 0
	return math.sin(angle) * r, math.cos(angle) * r
end

---------------------------------------------------------------------------
-- The map under the radar
---------------------------------------------------------------------------

local function MapCorner(mapID, x, y)
	local ok, _, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
	if ok and pos and not issecret(pos) then
		return pos:GetXY()
	end
end

-- The world map's art of a zone (laid out, hidden: MoveMap shows it when it's the one in use).
local function SetupMap(view, mapID)
	local map, win = view.map, view.win
	map.id, map.ok, map.x = mapID, false, nil
	local layers = mapID and Value("C_Map.GetMapArtLayers", mapID)
	local layer = type(layers) == "table" and layers[1]
	local textures = layer and Value("C_Map.GetMapArtLayerTextures", mapID, 1)
	local north0, west0 = MapCorner(mapID, 0, 0)
	local north1, west1 = MapCorner(mapID, 1, 1)
	if type(textures) == "table" and north0 and north1 and west0 > west1 and north0 > north1 then
		map.ok, map.north0, map.west0 = true, north0, west0
		local sx = (west0 - west1) * PX_PER_YARD / layer.layerWidth
		local sy = (north0 - north1) * PX_PER_YARD / layer.layerHeight
		local cols = math.ceil(layer.layerWidth / layer.tileWidth)
		local rows = math.ceil(layer.layerHeight / layer.tileHeight)
		local n = 0
		for row = 1, rows do
			for col = 1, cols do
				n = n + 1
				local tile = map.tiles[n]
				if not tile then
					tile = win.Map:CreateTexture(nil, "BACKGROUND")
					tile:AddMaskTexture(win.Map.Round)
					map.tiles[n] = tile
				end
				tile:SetTexture(textures[(row - 1) * cols + col])
				tile:SetSize(layer.tileWidth * sx, layer.tileHeight * sy)
				tile:ClearAllPoints()
				tile:SetPoint("TOPLEFT", win.Map, "TOPLEFT", (col - 1) * layer.tileWidth * sx, -(row - 1) * layer.tileHeight * sy)
			end
		end
		map.count = n
	end
	for _, tile in ipairs(map.tiles) do
		tile:Hide()
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
	for i, tile in ipairs(map.tiles) do
		tile:SetShown(source == "art" and i <= (map.count or 0))
	end
end

-- The map under a place (north, west on continent; mapID for the world map's art); glide: move
-- there smoothly (a friend's place comes twice a second) instead of at once.
local function MoveMap(view, north, west, continent, mapID, elapsed)
	local map, win = view.map, view.win
	if mapID ~= map.id then
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

---------------------------------------------------------------------------
-- Drawing a picture
---------------------------------------------------------------------------

local GROUP_RING, ENEMY_RING, FRIEND_RING = { 0.3, 0.65, 1 }, { 1, 0.2, 0.2 }, { 0.9, 0.9, 0.9 }

local function Style(view, dot, mob, named, clock)
	dot.mob = mob
	local r, g, b = 0.65, 0.65, 0.65 -- nearby, not fighting
	if mob.player then
		r, g, b = B.ClassColor(mob.classFile) -- a player: their class colour, the ring says who
	elseif mob.attacking then
		r, g, b = 1, 0.25, 0.2
	elseif mob.combat then
		r, g, b = 1, 0.6, 0.15
	end
	dot.Body:SetColorTexture(r, g, b, 1)
	dot.Body:SetAlpha((0.3 + 0.7 * (mob.sure or 1)) * (mob.fade or 1)) -- solid when sure; remembered ones fade
	dot.Name:SetAlpha(mob.fade or 1)
	dot.Body:SetShown(not mob.dead)
	dot.Skull:SetShown(mob.dead)
	dot.Target:SetShown(mob.target and not mob.dead or false)
	local class = mob.class
	if mob.player then
		local ring = mob.group and GROUP_RING or mob.friendly and FRIEND_RING or ENEMY_RING
		dot.Ring:SetColorTexture(ring[1], ring[2], ring[3], 1)
		dot.Ring:Show()
	elseif class == "elite" or class == "worldboss" or class == "rareelite" then
		dot.Ring:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
		dot.Ring:Show()
	elseif class == "rare" then
		dot.Ring:SetColorTexture(0.8, 0.85, 0.95, 1)
		dot.Ring:Show()
	else
		dot.Ring:Hide()
	end
	dot.casting = mob.casting and not mob.dead
	dot.Glow:SetShown(dot.casting and true or false)
	named = named or (mob.target and not mob.dead) or mob.group -- (group members always: they're few)
	if mob.player then
		dot.Name:SetText(named and mob.name or "")
		dot.Name:SetTextColor(r, g, b)
	else
		dot.Name:SetText(named and (mob.level and ("%s %s"):format(mob.name, mob.level) or mob.name) or "")
		if mob.target then
			dot.Name:SetTextColor(1, 0.9, 0.4) -- (their target: named in yellow)
		else
			dot.Name:SetTextColor(1, 1, 1)
		end
	end
	if mob.dead and not dot.deadAt then
		dot.deadAt = clock
	elseif not mob.dead then
		dot.deadAt = nil
		dot:SetAlpha(1)
	end
	dot.tx, dot.ty = Spot(mob)
	if dot.fresh then
		dot.x, dot.y, dot.fresh = dot.tx, dot.ty, nil
		dot:ClearAllPoints()
		dot:SetPoint("CENTER", view.win.Radar, "CENTER", dot.x, dot.y)
	end
	dot:Show()
end

local function Nearer(a, b)
	return (a.yards or 999) < (b.yards or 999)
end

-- The mobs onto the dots: a dot follows its mob from look to look, so it glides.
local function Apply(view)
	local mobs = view.picture.mobs
	table.sort(mobs, Nearer)
	for _, dot in ipairs(view.dots) do
		dot.seen = false
	end
	local named = 0 -- (the nearest NAMES mobs get their name; players count apart)
	for _, mob in ipairs(mobs) do
		local dot = view.dotFor[mob.key]
		if not dot then
			dot = FreeDot(view)
			if not dot then
				break
			end
			dot.key, dot.fresh = mob.key, true
			view.dotFor[mob.key] = dot
		end
		dot.seen = true
		local name = false
		if not mob.player and not mob.dead and named < NAMES then
			named, name = named + 1, true
		end
		Style(view, dot, mob, name, view.clock)
	end
	for _, dot in ipairs(view.dots) do
		if dot.key and not dot.seen then
			Release(view, dot)
		end
	end
end

-- The bottom line: how many are on them, how many near, who's casting what.
local function Status(view)
	local on, near, cast = 0, 0, nil
	for _, mob in ipairs(view.picture.mobs) do
		if not mob.dead and not mob.friendly then -- (enemies only: mobs and enemy players)
			near = near + 1
			on = on + (mob.attacking and 1 or 0)
			if mob.casting and not cast then
				cast = L["%s casts %s"]:format(mob.name, mob.casting)
			end
		end
	end
	local who = Whose(view)
	if near == 0 then
		return view.kind == "me" and L["No mobs with a nameplate near you."] or ""
	end
	local parts = { who and L["%d on %s"]:format(on, who) or L["%d on you"]:format(on), L["%d near"]:format(near) }
	parts[#parts + 1] = cast
	return table.concat(parts, "  ·  ")
end

-- The top: name, where, power bar, form; dead: a skull in the middle, the name greyed.
local function ShowSelf(view)
	local win, picture = view.win, view.picture
	local name = picture.name or "?"
	if picture.dead then
		win.Title:SetText("|cff888888" .. name .. "|r  |cffff5050" .. L["dead"] .. "|r")
	else
		win.Title:SetText(LT.Window.ClassColorCode(picture.classFile) .. name .. "|r")
	end
	win.Where:SetText(picture.where or "")
	win.Me:SetShown(not picture.dead)
	win.MeDot:SetShown(not picture.dead)
	win.MeSkull:SetShown(picture.dead and true or false)
	-- Health: estimated (StreamSense.lua), so "~" and in steps of 5%; not known: "~?" (the hover
	-- says why).
	local health = not picture.dead and picture.health
	local unknown = not picture.dead and not health
	if health then
		win.Health:SetWidth(math.max(1, BAR * health))
		win.HealthText:SetText(("~%d%%"):format(math.floor(health * 20 + 0.5) * 5))
		win.HealthText:SetTextColor(0.6, 0.95, 0.6)
	elseif unknown then
		win.HealthText:SetText("~?")
		win.HealthText:SetTextColor(0.6, 0.6, 0.6)
	end
	local row = (health or unknown) and true or false
	win.Health:SetShown(health and true or false)
	win.HealthBack:SetShown(row)
	win.HealthText:SetShown(row)
	win.HealthHover:SetShown(row)
	local power = picture.power
	if power and power.frac then
		local color = POWER_COLORS[power.token] or GOLD
		win.Power:SetColorTexture(color[1], color[2], color[3], 0.9)
		win.Power:SetWidth(math.max(1, BAR * power.frac))
		win.Power:Show()
		win.PowerBack:Show()
	else
		win.Power:Hide()
		win.PowerBack:Hide()
	end
	local form = picture.form
	if form and form.icon then
		if win.Form.icon ~= form.icon then
			win.Form.icon = form.icon
			win.Form:SetTexture(form.icon)
		end
		win.Form:Show()
	else
		win.Form:Hide()
	end
end

-- The row under the radar: the spell being cast (icon, name, a bar that fills while casting and
-- empties while channelling), and the last spells on the right, fading.
local function ShowDoing(view, now)
	local act, picture = view.win.Act, view.picture
	local cast = picture.cast
	if cast and now > cast.finish + 0.3 then
		cast, picture.cast = nil, nil -- (over; a new one shows on its start or the next look)
	end
	if cast then
		local p = math.max(0, math.min(1, (now - cast.start) / math.max(0.1, cast.finish - cast.start)))
		if cast.channel then
			p = 1 - p
		end
		if act.icon ~= cast.icon then
			act.icon = cast.icon
			act.Icon:SetTexture(cast.icon)
		end
		act.Icon:Show()
		act.Name:SetText(cast.name)
		act.Bar:SetWidth(math.max(1, CAST_BAR * p))
		act.Bar:Show()
		act.BarBack:Show()
	else
		act.Icon:Hide()
		act.Name:SetText("")
		act.Bar:Hide()
		act.BarBack:Hide()
	end
	for i, icon in ipairs(act.Recent) do
		local entry = picture.recent and picture.recent[i]
		local age = entry and now - entry.at
		if age and age < RECENT_TIME then
			if icon.icon ~= entry.icon then
				icon.icon = entry.icon
				icon:SetTexture(entry.icon)
			end
			icon:SetAlpha(1 - 0.8 * age / RECENT_TIME)
			icon:Show()
		else
			icon:Hide()
		end
	end
end

---------------------------------------------------------------------------
-- What happens to them: numbers floating up over the radar
---------------------------------------------------------------------------

local function Number(n)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

-- The game's own word for a miss, dodge, ... (in its language).
local function Word(token)
	local word = _G[token]
	return type(word) == "string" and word or token:sub(1, 1) .. token:sub(2):lower()
end

-- One floating text: from x, y (off the radar's middle) by dx, dy over its life, fading in and out.
local function Float(view, text, x, y, dx, dy, color, scale, life)
	local list = view.win.Floats.list
	local float
	for _, f in ipairs(list) do
		if not f.on then
			float = f
			break
		end
	end
	if not float and #list < FLOATS then
		float = view.win.Floats:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		list[#list + 1] = float
	elseif not float then
		float = list[1] -- (all in use: the oldest goes)
		for _, f in ipairs(list) do
			if f.age > float.age then
				float = f
			end
		end
	end
	float.on, float.age, float.life = true, 0, life or FLOAT_TIME
	float.x, float.y, float.dx, float.dy = x, y, dx, dy
	float:SetText(text)
	float:SetTextColor(color[1], color[2], color[3])
	float:SetTextScale(scale or 1)
	float:SetAlpha(0)
	float:ClearAllPoints()
	float:SetPoint("CENTER", view.win.Radar, "CENTER", x, y)
	float:Show()
end

local function MoveFloats(view, elapsed)
	for _, f in ipairs(view.win.Floats.list) do
		if f.on then
			f.age = f.age + elapsed
			local p = f.age / f.life
			if p >= 1 then
				f.on = false
				f:Hide()
			else
				f:ClearAllPoints()
				f:SetPoint("CENTER", view.win.Radar, "CENTER", f.x + f.dx * p, f.y + f.dy * p)
				f:SetAlpha(p < 0.1 and p * 10 or p > 0.65 and (1 - p) / 0.35 or 1)
			end
		end
	end
end

local function ShowKills(view)
	local kills = view.kills
	view.win.Kills:SetText(kills == 1 and L["1 kill"] or kills > 1 and L["%d kills"]:format(kills) or "")
end

-- Loot: its icon and name in its quality's colour (an item the client doesn't know yet: asked for).
local function LootText(m)
	local name = Value("C_Item.GetItemInfo", ("item:%d"):format(m.item))
	if not name then
		local load = S.Api("C_Item.RequestLoadItemDataByID")
		if load then
			pcall(load, m.item)
		end
	end
	local icon = Value("C_Item.GetItemIconByID", m.item)
	local color, colorOf = { 1, 1, 1 }, S.Api("C_Item.GetItemQualityColor")
	if colorOf then
		local ok, r, g, b = pcall(colorOf, m.quality)
		if ok and type(r) == "number" then
			color = { r, g, b }
		end
	end
	return (icon and ("|T%s:16:16|t "):format(icon) or "") .. (name or L["an item"]), color
end

-- A moment floats up: hits up and to the left of them, heals to the right, a dodge above; XP from
-- the mob that died (else from them); loot rising through them, a little longer. A kill counts.
local function Spawn(view, m)
	local kind = m.kind
	local lift = 0 -- (another of its kind just now: below it, so they don't cover each other)
	if view.lastFloat[kind] and view.clock - view.lastFloat[kind] < 0.45 then
		lift = -12
	end
	view.lastFloat[kind] = view.clock
	if kind == "hurt" then
		Float(view, "-" .. Number(m.amount), -14, 8 + lift, -8, 34, HURT_COLOR, m.big and 1.35 or 1)
	elseif kind == "heal" then
		Float(view, "+" .. Number(m.amount), 14, 8 + lift, 8, 34, HEAL_COLOR, m.big and 1.35 or 1)
	elseif kind == "avoid" then
		Float(view, Word(m.avoid), 0, 18 + lift, 0, 26, AVOID_COLOR, 0.85)
	elseif kind == "xp" then
		local dot = m.key and view.dotFor[m.key]
		local x, y = 0, 16
		if dot and dot.x then
			x, y = dot.x, dot.y + 10
		end
		Float(view, L["+%d XP"]:format(m.amount), x, y + lift, 0, 26, XP_COLOR, 0.9)
	elseif kind == "kill" then
		view.kills = view.kills + 1
		ShowKills(view)
	elseif kind == "loot" then
		local text, color = LootText(m)
		Float(view, text, 0, -16 + lift, 0, 44, color, 0.9, LOOT_TIME)
	end
end

-- The picture's new moments (each number once), oldest first.
local function Happenings(view)
	local moments = view.picture.moments
	for i = #(moments or {}), 1, -1 do
		local m = moments[i]
		local seen = view.seen[m.seq]
		if not seen or view.clock - seen > SEEN_FOR then
			view.seen[m.seq] = view.clock
			Spawn(view, m)
		end
	end
end

---------------------------------------------------------------------------
-- The foes: the mobs fought, a still model and a health bar each
---------------------------------------------------------------------------

-- Your own window: the real health of a mob with a unit (hidden values go straight into the bar:
-- StatusBar takes them, AllowedWhenTainted). A friend's (or no unit): the estimate, 0-1.
local function RealHealth(bar, unit)
	bar:SetMinMaxValues(0, UnitHealthMax(unit))
	bar:SetValue(UnitHealth(unit))
end

local function FoeOnEnter(slot)
	local mob = slot.mob
	if not mob then
		return
	end
	GameTooltip:SetOwner(slot, "ANCHOR_BOTTOM")
	GameTooltip:SetText(mob.level and ("%s (%s)"):format(mob.name, mob.level) or mob.name, 1, 1, 1)
	local class = mob.class == "elite" and L["Elite"] or mob.class == "rare" and L["Rare"] or mob.class == "rareelite" and L["Rare elite"]
	if class then
		GameTooltip:AddLine(class, GOLD[1], GOLD[2], GOLD[3])
	end
	if not slot.real then
		if mob.health then
			GameTooltip:AddLine(L["~%d%% health"]:format(math.floor(mob.health * 100 + 0.5)), 1, 0.4, 0.3)
			GameTooltip:AddLine(L["Estimated: the hits it took, against what one of its kind had in all."], 0.7, 0.7, 0.7, true)
		else
			GameTooltip:AddLine(L["Health not known yet: it's learned when one of its kind is seen from full health to dead."],
				0.7, 0.7, 0.7, true)
		end
	end
	GameTooltip:Show()
end

-- Loaded: the camera fits the model to the frame as big as it is now, turned a little, still.
local function FoeLoaded(model)
	model:RefreshCamera()
	model:SetFacing(FOE_FACING)
	model:SetPaused(true)
end

local function NewFoe(row)
	local slot = CreateFrame("Frame", nil, row)
	slot:SetSize(FOE_W + 2, FOE_H + 8)
	slot.Ring = slot:CreateTexture(nil, "BACKGROUND", nil, -1) -- (gold: their target)
	slot.Ring:SetPoint("TOPLEFT")
	slot.Ring:SetSize(FOE_W + 2, FOE_H + 2)
	slot.Ring:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.8)
	slot.Back = slot:CreateTexture(nil, "BACKGROUND")
	slot.Back:SetPoint("TOPLEFT", 1, -1)
	slot.Back:SetSize(FOE_W, FOE_H)
	slot.Back:SetColorTexture(0, 0, 0, 0.55)
	slot.Model = CreateFrame("PlayerModel", nil, slot)
	slot.Model:SetPoint("TOPLEFT", 1, -1)
	slot.Model:SetSize(FOE_W, FOE_H)
	slot.Model:SetPortraitZoom(0) -- (the whole mob, not its portrait)
	slot.Model:SetScript("OnModelLoaded", FoeLoaded)
	slot.BarBack = slot:CreateTexture(nil, "BORDER")
	slot.BarBack:SetPoint("TOPLEFT", slot.Back, "BOTTOMLEFT", 0, -2)
	slot.BarBack:SetSize(FOE_W, 4)
	slot.BarBack:SetColorTexture(1, 1, 1, 0.15)
	slot.Bar = CreateFrame("StatusBar", nil, slot)
	slot.Bar:SetAllPoints(slot.BarBack)
	slot.Bar:SetStatusBarTexture(BAR_TEXTURE)
	slot.Bar:SetStatusBarColor(0.85, 0.2, 0.15)
	slot.Unknown = slot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	slot.Unknown:SetPoint("CENTER", slot.BarBack, "CENTER", 0, 0)
	slot.Unknown:SetTextScale(0.7)
	slot.Unknown:SetText("?")
	slot:SetMouseMotionEnabled(true)
	slot:SetMouseClickEnabled(false)
	slot:SetScript("OnEnter", FoeOnEnter)
	slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
	slot:Hide()
	return slot
end

-- The row: the mobs fought (S.Foes: fighting them or their target; the target first, then the
-- ones attacking, the nearest), left to right. A model loads when its creature changes, and again
-- when the window's size does (a model's camera is set for the size it loaded at: smaller, it
-- showed nothing).
local foeList = {}
local function ShowFoes(view)
	local row, picture = view.win.Foes, view.picture
	local foes = S.Foes(picture.mobs, foeList, FOES)
	local shown = 0
	for _, mob in ipairs(foes) do
		if mob.creature and shown < FOES then
			shown = shown + 1
			local slot = row.slots[shown] or NewFoe(row)
			row.slots[shown] = slot
			slot:ClearAllPoints()
			slot:SetPoint("TOPLEFT", row, "TOPLEFT", (shown - 1) * (FOE_W + 2 + FOE_GAP), 0)
			slot.mob = mob
			local scale = slot:GetEffectiveScale()
			if slot.creature ~= mob.creature or not slot.scale or math.abs(slot.scale - scale) > 0.001 then
				slot.creature, slot.scale = mob.creature, scale
				slot.Model:ClearModel()
				slot.Model:SetCreature(mob.creature)
				slot.Model:SetFacing(FOE_FACING)
			end
			slot.Ring:SetShown(mob.target and true or false)
			local unit = view.kind == "me" and mob.unit
			slot.real = unit and Value("UnitGUID", unit) == mob.key and pcall(RealHealth, slot.Bar, unit) or false
			if not slot.real and mob.health then
				slot.Bar:SetMinMaxValues(0, 1)
				slot.Bar:SetValue(mob.health)
			elseif not slot.real then
				slot.Bar:SetMinMaxValues(0, 1)
				slot.Bar:SetValue(0)
			end
			slot.Unknown:SetShown(not slot.real and not mob.health)
			slot:Show()
		end
	end
	for i = shown + 1, #row.slots do
		row.slots[i].mob = nil
		row.slots[i]:Hide()
	end
end

local function ClearFloats(view)
	for _, f in ipairs(view.win.Floats.list) do
		f.on = false
		f:Hide()
	end
	wipe(view.seen)
	wipe(view.lastFloat)
	view.kills = 0
	ShowKills(view)
end

---------------------------------------------------------------------------
-- The preview: a made-up friend in a made-up fight, on a loop
---------------------------------------------------------------------------

local PREVIEW_LOOP = 24
local previewMobs = {}
-- What happens to her (seconds into the loop): hits while the bandits are on her, heals, a dodge,
-- the bandit's death (her killing blow, its XP), loot.
local PREVIEW_MOMENTS = {
	{ 3, "hurt", 24 }, { 4.6, "hurt", 31 }, { 5.5, "avoid", "DODGE" }, { 6.3, "hurt", 27 }, { 7.5, "heal", 120 },
	{ 9, "hurt", 26 }, { 10.4, "hurt", 158, true }, { 11.6, "heal", 310, true }, { 12.8, "hurt", 25 },
	{ 14, "kill" }, { 14.1, "xp", 87 }, { 16.5, "loot", 774 }, { 19, "hurt", 30 }, { 21, "avoid", "PARRY" },
}

-- The moments passed since the last step (also over the loop's end), newest first, kept 2.5 s.
local function PreviewMoments(view, t)
	local was = view.previewAt or t
	view.previewAt = t
	local moments = view.picture.moments
	for _, e in ipairs(PREVIEW_MOMENTS) do
		local at, kind = e[1], e[2]
		if (was < at and at <= t) or (t < was and (at > was or at <= t)) then
			view.previewSeq = (view.previewSeq or 0) % 99 + 1
			local m = { seq = view.previewSeq, kind = kind, at = view.clock }
			if kind == "hurt" or kind == "heal" then
				m.amount, m.big = e[3], e[4] or false
			elseif kind == "avoid" then
				m.avoid = e[3]
			elseif kind == "xp" then
				m.amount, m.key = e[3], "bandit"
			elseif kind == "kill" then
				m.key = "bandit"
			else
				m.item, m.quality = e[3], 2 -- (Malachite)
			end
			table.insert(moments, 1, m)
		end
	end
	while moments[1] and view.clock - moments[#moments].at > 2.5 do
		moments[#moments] = nil
	end
end

local function PreviewMob(n, key, name, level, class, creature)
	local mob = previewMobs[n] or {}
	previewMobs[n] = mob
	mob.key, mob.name, mob.level, mob.class, mob.creature, mob.health, mob.engaged = key, name, level, class, creature, nil, false
	mob.dead, mob.combat, mob.attacking, mob.casting, mob.target, mob.sure = false, false, false, nil, false, 1
	mob.player, mob.classFile, mob.friendly, mob.group, mob.exact = false, nil, false, false, nil
	return mob
end

local function FeedPreview(view)
	local picture, t = view.picture, view.clock % PREVIEW_LOOP
	local mobs = picture.mobs
	wipe(mobs)
	picture.name, picture.classFile, picture.where, picture.facing = PREVIEW_FRIEND, PREVIEW_CLASS, L["Westfall"], 0
	picture.power = picture.power or { token = "MANA" }
	picture.power.frac = 0.4 + 0.3 * math.cos(t / 4)
	picture.health = 0.65 + 0.3 * math.cos(t / 3)
	PreviewMoments(view, t)
	-- (Their models: Hogger, a Defias Bandit, a Defias Rogue Wizard, a Riverpaw Gnoll, Thuros
	-- Lightfingers. Health: the leader's goes down, the bandit's faster, the mage's isn't known.)
	local leader = PreviewMob(1, "leader", L["Bandit leader"], 16, "elite", 448)
	leader.combat, leader.attacking, leader.target, leader.engaged = t > 2, t > 2, true, t > 2
	leader.yards, leader.bearing = math.max(6, 30 - t * 2), -0.6 + 0.15 * math.sin(t)
	leader.casting = (t % 8 >= 3 and t % 8 < 5) and L["Fireball"] or nil
	leader.health = math.max(0.1, 1 - math.max(0, t - 2) / 24)
	mobs[#mobs + 1] = leader
	if t < 18 then
		local bandit = PreviewMob(2, "bandit", L["Bandit"], 15, "normal", 116)
		bandit.dead = t >= 14
		bandit.combat, bandit.attacking, bandit.engaged = not bandit.dead, not bandit.dead, not bandit.dead
		bandit.yards, bandit.bearing = 5 + math.sin(t * 1.3), 0.35 + 0.15 * math.sin(t * 0.8)
		bandit.health = bandit.dead and 0 or math.max(0.05, 1 - math.max(0, t - 2) / 12)
		mobs[#mobs + 1] = bandit
	end
	local mage = PreviewMob(3, "mage", L["Bandit mage"], 15, "normal", 474)
	mage.combat, mage.engaged, mage.yards, mage.bearing = true, true, 24, 1.1 + 0.03 * t -- (casting at her)
	mage.casting = (t % 6 < 2) and L["Frostbolt"] or nil
	mobs[#mobs + 1] = mage
	local gnoll = PreviewMob(4, "gnoll", L["Gnoll"], 14, "normal", 117)
	gnoll.yards, gnoll.bearing, gnoll.sure = 32 + 3 * math.sin(t * 0.4), 2.9, 0.25 -- behind, not sure yet: faint
	mobs[#mobs + 1] = gnoll
	local rare = PreviewMob(5, "rare", L["Greyfang"], 17, "rare", 61)
	rare.yards, rare.bearing = 37, 2.4 + 0.1 * math.sin(t * 0.5)
	mobs[#mobs + 1] = rare
	-- Her group: a warrior in front of her, at the leader (placed exactly); and someone passing by.
	local tank = PreviewMob(6, "tank", "Bob", 16)
	tank.player, tank.classFile, tank.friendly, tank.group, tank.combat = true, "WARRIOR", true, true, t > 2
	tank.yards, tank.bearing = math.max(4, leader.yards - 2), leader.bearing + 0.25
	tank.exact = math.floor(tank.yards + 0.5)
	mobs[#mobs + 1] = tank
	local passer = PreviewMob(7, "passer", "Cedric", 22)
	passer.player, passer.classFile, passer.friendly, passer.sure = true, "PRIEST", true, 0.5
	passer.yards, passer.bearing = 28, -2.2 + 0.05 * t
	mobs[#mobs + 1] = passer
	-- What she's doing: a Fireball every 4 s (2.5 s to cast), and the spells before it.
	local now, cycle = GetTime(), t % 4
	if cycle < 2.5 then
		local info = Value("C_Spell.GetSpellInfo", 133)
		local cast = picture.castPreview or {}
		picture.castPreview = cast
		cast.name, cast.icon = info and info.name or L["Fireball"], info and info.iconID
		cast.start, cast.finish, cast.channel = now - cycle, now - cycle + 2.5, false
		picture.cast = cast
	else
		picture.cast = nil
	end
	if not picture.recent[1] then
		for i, id in ipairs({ 2136, 116, 122, 133 }) do -- Fire Blast, Frostbolt, Frost Nova, Fireball (oldest last)
			S.AddRecent(picture.recent, id, now - 8 + i)
		end
	end
	for i, entry in ipairs(picture.recent) do
		entry.at = now - (i - 1) * 2 -- (kept from fading away in the preview)
	end
end

---------------------------------------------------------------------------
-- A window
---------------------------------------------------------------------------

local function UserScale(kind)
	local sizes = S.Saved("streamWindows")
	local key = kind == "friend" and "friend" or "me"
	local scale = tonumber(sizes[key]) or SCALES[key]
	return math.max(MIN_SCALE, math.min(MAX_SCALE, scale))
end

-- The window's size: yours lives in the interface (UIParent's scale); a friend's floats on its own
-- (no parent: above a flight's film), so it takes UIParent's scale itself.
local function ApplyScale(view, scale)
	view.scale = scale
	if view.kind == "friend" then
		view.win:SetScale(scale * UIParent:GetEffectiveScale())
	else
		view.win:SetScale(scale)
	end
end

-- Kept where its top left corner is (in UIParent's units), whatever the size.
local function PlaceAt(view, left, top)
	view.left, view.top = left, top
	view.win:ClearAllPoints()
	view.win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / view.scale, top / view.scale)
end

local function WhereNow(view)
	local win = view.win
	local left, top = win:GetLeft(), win:GetTop()
	if left and top then
		local ratio = win:GetEffectiveScale() / UIParent:GetEffectiveScale()
		return left * ratio, top * ratio
	end
	return view.left, view.top
end

local function OnUpdate(win, elapsed)
	local view = win.view
	view.clock = view.clock + elapsed
	local now = GetTime()
	-- Redrawn when there's something new: the sensor looked (yours), a friend's frame came (and
	-- every LOOK_GAP, to notice it's stale), the preview's next step.
	local due = view.clock >= view.nextFeed
	if due then
		view.nextFeed = view.clock + S.LOOK_GAP
	end
	local changed = false
	if view.kind == "preview" then
		if due then
			FeedPreview(view)
			changed = true
		end
	elseif view.kind == "friend" then
		local fresh, age = S.ReadFriend(view.id, view.picture)
		changed = fresh or due
		if changed then
			view.stale = not age or age > STALE
		end
	elseif view.picture.looked ~= view.looked then
		view.looked, changed = view.picture.looked, true
	end
	if changed then
		Apply(view)
		ShowSelf(view)
		Happenings(view) -- (after Apply: XP floats from its mob's dot)
		ShowFoes(view)
		if view.kind == "friend" and view.stale then
			win.Status:SetText(L["Waiting for %s's stream..."]:format(view.picture.name or "?"))
			win.Live.Text:SetTextColor(0.6, 0.6, 0.6)
		else
			win.Status:SetText(Status(view))
			win.Live.Text:SetTextColor(1, 0.3, 0.25)
		end
	end
	local picture = view.picture
	local facing = picture.facing or 0
	if view.kind == "friend" then
		MoveMap(view, picture.north, picture.west, picture.continent, picture.mapID, elapsed)
	else
		local ok, north, west, _, continent = pcall(UnitPosition, "player")
		if not ok or issecret(north) or issecret(west) or issecret(continent) then
			north, continent = nil, nil
		end
		MoveMap(view, north, west, continent, Value("C_Map.GetBestMapForUnit", "player"))
		facing = view.kind == "me" and Value("GetPlayerFacing") or 0 -- (yours: every frame, smooth)
	end
	if facing ~= win.Me.facing then
		win.Me.facing = facing
		win.Me:SetRotation(facing)
	end
	ShowDoing(view, now)
	MoveFloats(view, elapsed)
	local k = math.min(1, elapsed * GLIDE)
	local pulse = 0.5 + 0.5 * math.sin(view.clock * 5)
	for _, dot in ipairs(view.dots) do
		if dot.key then
			local dx, dy = dot.tx - dot.x, dot.ty - dot.y
			if dx * dx + dy * dy > 0.01 then
				dot.x, dot.y = dot.x + dx * k, dot.y + dy * k
				dot:ClearAllPoints()
				dot:SetPoint("CENTER", win.Radar, "CENTER", dot.x, dot.y)
			end
			if dot.casting then
				dot.Glow:SetAlpha(0.2 + 0.5 * pulse)
			end
			if dot.deadAt then
				dot:SetAlpha(math.max(0, 1 - (view.clock - dot.deadAt) / DEAD_FADE))
			end
		end
	end
	win.Live.Dot:SetAlpha(0.35 + 0.65 * pulse)
end

-- The grip at the bottom right: drag to make the window bigger or smaller (kept per kind).
local function GripUpdate(grip)
	local view = grip:GetParent().view
	local x = GetCursorPosition() / UIParent:GetEffectiveScale()
	local scale = math.max(MIN_SCALE, math.min(MAX_SCALE, grip.startScale + (x - grip.startX) / WIDTH))
	if math.abs(scale - view.scale) > 0.005 then
		ApplyScale(view, scale)
		PlaceAt(view, grip.left, grip.top)
	end
end

local function Build(view, name, parent)
	local win = CreateFrame("Frame", name, parent)
	view.win, win.view = win, view
	win:SetSize(WIDTH, HEIGHT)
	win:SetFrameStrata(parent and "HIGH" or "FULLSCREEN_DIALOG")
	win:SetClampedToScreen(true)
	win:EnableMouse(true)
	win:SetMovable(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		self:SetUserPlaced(false)
		PlaceAt(self.view, WhereNow(self.view))
	end)
	win:SetScript("OnUpdate", OnUpdate) -- (only runs while it's shown)
	win:SetScript("OnHide", function(self)
		-- A resize or move in progress ends (the mouse-up may never come; the frame is reused).
		if self.Grip and self.Grip:GetScript("OnUpdate") then
			self.Grip:SetScript("OnUpdate", nil)
			S.Saved("streamWindows")[self.view.kind == "friend" and "friend" or "me"] = self.view.scale
		end
		self:StopMovingOrSizing()
		-- Escape, or hidden some other way: closed. (Not when only the interface is hidden, Alt+Z:
		-- then it's still shown itself, and comes back with it.)
		if self.view.open and not self:IsShown() then
			S.CloseView(self.view.key)
		end
	end)
	win:Hide()
	if UISpecialFrames then
		table.insert(UISpecialFrames, name) -- Escape closes it
	end

	-- Dark blue-grey, thin gold edges.
	local bg = win:CreateTexture(nil, "BACKGROUND", nil, -8)
	bg:SetAllPoints()
	bg:SetColorTexture(1, 1, 1, 1)
	bg:SetGradient("VERTICAL", CreateColor(0.03, 0.04, 0.06, 0.94), CreateColor(0.07, 0.09, 0.12, 0.94))
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local edge = win:CreateTexture(nil, "BORDER")
		edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], (side == "TOP" or side == "BOTTOM") and 0.4 or 0.2)
		if side == "TOP" or side == "BOTTOM" then
			edge:SetHeight(1)
			edge:SetPoint(side .. "LEFT")
			edge:SetPoint(side .. "RIGHT")
		else
			edge:SetWidth(1)
			edge:SetPoint("TOP" .. side)
			edge:SetPoint("BOTTOM" .. side)
		end
	end

	win.Close = CreateFrame("Button", nil, win, "UIPanelCloseButtonNoScripts")
	win.Close:SetPoint("TOPRIGHT", -2, -2)
	win.Close:SetScript("OnClick", function() S.CloseView(view.key) end)
	win.Title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	win.Title:SetPoint("TOPLEFT", 12, -10)
	win.Form = win:CreateTexture(nil, "OVERLAY")
	win.Form:SetSize(16, 16)
	win.Form:SetPoint("LEFT", win.Title, "RIGHT", 4, 0)
	win.Form:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	win.Form:Hide()
	win.Where = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	win.Where:SetPoint("TOPLEFT", win.Title, "BOTTOMLEFT", 0, -2)
	-- Their health (estimated, "~80%" beside it; the tooltip says so) and power (mana, rage,
	-- energy): thin bars under where they are.
	win.HealthBack = win:CreateTexture(nil, "BORDER")
	win.HealthBack:SetColorTexture(1, 1, 1, 0.12)
	win.HealthBack:SetSize(BAR, 4)
	win.HealthBack:SetPoint("TOPLEFT", win.Where, "BOTTOMLEFT", 0, -3)
	win.Health = win:CreateTexture(nil, "ARTWORK")
	win.Health:SetColorTexture(HEALTH_COLOR[1], HEALTH_COLOR[2], HEALTH_COLOR[3], 0.9)
	win.Health:SetSize(1, 4)
	win.Health:SetPoint("LEFT", win.HealthBack, "LEFT")
	win.HealthText = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	win.HealthText:SetPoint("LEFT", win.HealthBack, "RIGHT", 5, 0)
	win.HealthText:SetTextScale(0.85)
	win.HealthText:SetTextColor(0.6, 0.95, 0.6)
	win.HealthHover = CreateFrame("Frame", nil, win) -- (hover only: a drag still moves the window)
	win.HealthHover:SetPoint("TOPLEFT", win.HealthBack, "TOPLEFT", 0, 4)
	win.HealthHover:SetPoint("BOTTOMRIGHT", win.HealthBack, "BOTTOMRIGHT", 40, -4)
	win.HealthHover:SetMouseMotionEnabled(true)
	win.HealthHover:SetMouseClickEnabled(false)
	win.HealthHover:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(L["Health (estimated)"], HEALTH_COLOR[1], HEALTH_COLOR[2], HEALTH_COLOR[3])
		local why = HealthWhy(win.view)
		if why == "old" then
			GameTooltip:AddLine(L["%s's LefthyTools is older and doesn't send health: they need to update."]:format(win.view.picture.name or "?"),
				1, 0.6, 0.3, true)
		elseif why == "max" then
			GameTooltip:AddLine(L["Not known here: the game hides the maximum health in this place, and none is known from before."],
				1, 0.6, 0.3, true)
		elseif why == "wait" then
			GameTooltip:AddLine(L["Not known yet: it is after a few seconds out of combat at full health (a /reload starts over)."],
				1, 0.6, 0.3, true)
		end
		GameTooltip:AddLine(L["The game hides health from addons, so this one is added up from hits and heals. It can be a little off until the next time it's full."],
			0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	win.HealthHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
	for _, part in ipairs({ win.HealthBack, win.Health, win.HealthText, win.HealthHover }) do
		part:Hide()
	end
	win.PowerBack = win:CreateTexture(nil, "BORDER")
	win.PowerBack:SetColorTexture(1, 1, 1, 0.12)
	win.PowerBack:SetSize(BAR, 3)
	win.PowerBack:SetPoint("TOPLEFT", win.HealthBack, "BOTTOMLEFT", 0, -2)
	win.Power = win:CreateTexture(nil, "ARTWORK")
	win.Power:SetSize(1, 3)
	win.Power:SetPoint("LEFT", win.PowerBack, "LEFT")
	win.Power:Hide()
	win.PowerBack:Hide()
	-- "● LIVE" (or DEMO), the dot breathing.
	win.Live = CreateFrame("Frame", nil, win)
	win.Live:SetSize(60, 14)
	win.Live:SetPoint("RIGHT", win.Close, "LEFT", 0, 0)
	win.Live.Text = win.Live:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	win.Live.Text:SetPoint("RIGHT")
	win.Live.Text:SetTextColor(1, 0.3, 0.25)
	local dotFrame = CreateFrame("Frame", nil, win.Live) -- (its own frame: the round mask sits in its middle)
	dotFrame:SetSize(8, 8)
	dotFrame:SetPoint("RIGHT", win.Live.Text, "LEFT", -4, 0)
	win.Live.Dot = Circle(dotFrame, "OVERLAY", 0, 8)
	win.Live.Dot:SetColorTexture(1, 0.2, 0.15, 1)
	-- Their kills since the window opened, under it.
	win.Kills = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	win.Kills:SetPoint("TOPRIGHT", win.Live, "BOTTOMRIGHT", 0, -3)

	-- The map (MoveMap): its own frame under the radar, its tiles cut round.
	local ring = (OUTER_YARDS * PX_PER_YARD + 8) * 2 -- (the round cut: the outer ring and a little more)
	win.Map = CreateFrame("Frame", nil, win)
	win.Map:SetSize(1, 1)
	win.Map.Round = win.Map:CreateMaskTexture()
	win.Map.Round:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	win.Map.Round:SetSize(ring, ring)
	win.Map:Hide()

	-- The radar, over the map: north up; rings every 10 yd (thin lines over the map; without one,
	-- faint discs, darker inside), labels, the one shown in the middle.
	local radar = CreateFrame("Frame", nil, win)
	win.Radar = radar
	radar:SetSize(RADAR, RADAR)
	radar:SetPoint("TOP", 0, -64)
	radar:SetFrameLevel(win.Map:GetFrameLevel() + 1)
	win.Map.Round:SetPoint("CENTER", radar, "CENTER")
	local dim = Circle(radar, "BACKGROUND", -8, ring) -- (the map a little darker: the dots stand out)
	dim:SetColorTexture(0, 0, 0, 0.35)
	win.Plain = CreateFrame("Frame", nil, radar) -- (no map: the discs)
	win.Plain:SetAllPoints()
	for i, yards in ipairs(RINGS) do
		local radius = yards * PX_PER_YARD
		local band = Circle(win.Plain, "BACKGROUND", i - 8, radius * 2)
		band:SetColorTexture(0.35, 0.45, 0.55, 0.07 + i * 0.015)
		local segments = 48
		for s = 1, segments do
			local a, b = 2 * math.pi * (s - 1) / segments, 2 * math.pi * s / segments
			local line = radar:CreateLine(nil, "ARTWORK")
			line:SetThickness(1)
			line:SetColorTexture(1, 1, 1, i == 1 and 0.35 or 0.22)
			line:SetStartPoint("CENTER", radar, math.sin(a) * radius, math.cos(a) * radius)
			line:SetEndPoint("CENTER", radar, math.sin(b) * radius, math.cos(b) * radius)
		end
		local label = radar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("CENTER", radar, "CENTER", 0, radius - 6)
		label:SetTextScale(0.75)
		label:SetAlpha(0.8)
		label:SetText(i == 1 and L["%d yd"]:format(yards) or tostring(yards))
	end
	local north = radar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	north:SetPoint("BOTTOM", radar, "TOP", 0, 1)
	north:SetText("N")
	win.MeDot = Circle(radar, "OVERLAY", 1, 7) -- (also there if this client lacks the arrow)
	win.MeDot:SetColorTexture(1, 1, 1, 0.9)
	win.Me = radar:CreateTexture(nil, "OVERLAY", nil, 2)
	win.Me:SetTexture(ARROW)
	win.Me:SetSize(24, 24)
	win.Me:SetPoint("CENTER")
	win.MeSkull = radar:CreateTexture(nil, "OVERLAY", nil, 3)
	win.MeSkull:SetTexture(SKULL)
	win.MeSkull:SetSize(22, 22)
	win.MeSkull:SetPoint("CENTER")
	win.MeSkull:Hide()
	-- The floating numbers: their own frame, above the dots.
	win.Floats = CreateFrame("Frame", nil, radar)
	win.Floats:SetAllPoints()
	win.Floats:SetFrameLevel(radar:GetFrameLevel() + 30)
	win.Floats.list = {}

	-- What they're doing (ShowDoing): the cast on the left, the last spells on the right.
	local act = CreateFrame("Frame", nil, win)
	win.Act = act
	act:SetSize(WIDTH - 24, 22)
	act:SetPoint("TOP", radar, "BOTTOM", 0, -8)
	act.Icon = act:CreateTexture(nil, "ARTWORK")
	act.Icon:SetSize(20, 20)
	act.Icon:SetPoint("LEFT")
	act.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	act.Name = act:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	act.Name:SetPoint("TOPLEFT", act.Icon, "TOPRIGHT", 5, 0)
	act.Name:SetWidth(CAST_BAR)
	act.Name:SetJustifyH("LEFT")
	act.Name:SetWordWrap(false)
	act.Name:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	act.BarBack = act:CreateTexture(nil, "BORDER")
	act.BarBack:SetColorTexture(1, 1, 1, 0.12)
	act.BarBack:SetSize(CAST_BAR, 3)
	act.BarBack:SetPoint("BOTTOMLEFT", act.Icon, "BOTTOMRIGHT", 5, 1)
	act.Bar = act:CreateTexture(nil, "ARTWORK")
	act.Bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
	act.Bar:SetSize(1, 3)
	act.Bar:SetPoint("LEFT", act.BarBack, "LEFT")
	act.Recent = {}
	for i = 1, 5 do
		local icon = act:CreateTexture(nil, "ARTWORK")
		icon:SetSize(16, 16)
		icon:SetPoint("RIGHT", act, "RIGHT", -(i - 1) * 18, 0)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		icon:Hide()
		act.Recent[i] = icon
	end

	-- The foes (ShowFoes): a still model and a health bar each, under the spells.
	win.Foes = CreateFrame("Frame", nil, win)
	win.Foes:SetSize(WIDTH - 24, FOE_H + 8)
	win.Foes:SetPoint("TOP", act, "BOTTOM", 0, -6)
	win.Foes.slots = {}

	win.Status = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	win.Status:SetPoint("BOTTOM", 0, 12)
	win.Status:SetWidth(WIDTH - 36)
	-- Said in your own window: directions are learned.
	win.Hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	win.Hint:SetPoint("BOTTOM", win.Status, "TOP", 0, 4)
	win.Hint:SetWidth(WIDTH - 20)
	win.Hint:SetText(L["Move and turn: faint dots find their place."])
	win.Hint:Hide()

	-- The grip: drag to resize.
	local grip = CreateFrame("Button", nil, win)
	win.Grip = grip
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
	grip:SetNormalTexture(GRIP)
	grip:SetScript("OnMouseDown", function(self)
		local v = win.view
		self.startScale, self.startX = v.scale, GetCursorPosition() / UIParent:GetEffectiveScale()
		self.left, self.top = WhereNow(v)
		self:SetScript("OnUpdate", GripUpdate)
	end)
	grip:SetScript("OnMouseUp", function(self)
		self:SetScript("OnUpdate", nil)
		local v = win.view
		S.Saved("streamWindows")[v.kind == "friend" and "friend" or "me"] = v.scale
	end)
	return win
end

local function NewView(key, kind)
	return { key = key, kind = kind, dots = {}, dotFor = {}, map = { tiles = {} }, clock = 0, nextFeed = 0,
		picture = { mobs = {}, recent = {}, moments = {} }, seen = {}, lastFloat = {}, kills = 0 }
end

-- Shows a view (fresh: its dots, map, floating numbers and picture start over).
local function Start(view)
	ReleaseAll(view)
	ClearFloats(view)
	for _, slot in ipairs(view.win.Foes.slots) do
		slot.mob, slot.creature = nil, nil -- (loaded anew when shown)
		slot:Hide()
	end
	if view.picture ~= S.Sensed() then -- (the sensor's own picture: friends watching may be getting it)
		wipe(view.picture.mobs)
		wipe(view.picture.recent)
		wipe(view.picture.moments)
		view.picture.cast, view.picture.health = nil, nil
	end
	view.previewAt = nil
	view.map.id, view.map.x, view.map.source = false, nil, nil
	view.clock, view.nextFeed, view.open, view.looked = 0, 0, true, nil
	view.win.Status:SetText("")
	view.win:Show()
end

---------------------------------------------------------------------------
-- Opening and closing
---------------------------------------------------------------------------

-- Your window: "me" (live, the sensor runs) or "preview" (a made-up fight). One window for both.
function S.OpenView(kind)
	local view = views.me
	if not view then
		view = NewView("me", kind)
		Build(view, "LefthyToolsStreamFrame", UIParent)
		LT.Window.Register("LefthyToolsStreamFrame") -- (a cinematic flight pauses for it)
		ApplyScale(view, UserScale("me"))
		PlaceAt(view, UIParent:GetWidth() - 60 - WIDTH * view.scale, UIParent:GetHeight() / 2 + 40 + HEIGHT * view.scale / 2)
		views.me = view
	end
	view.kind = kind
	if kind == "me" then
		view.picture = S.Sensed()
		S.SenseNeed("me", true)
		view.win.Live.Text:SetText(L["LIVE"])
	else
		view.picture = { mobs = {}, recent = {}, moments = {} }
		S.SenseNeed("me", false)
		view.win.Live.Text:SetText(L["DEMO"])
	end
	view.win.Hint:SetShown(kind == "me")
	Start(view)
	return view
end

-- A friend's window (origin: "flight", "map" or "command": a flight's ones close when it lands).
function S.OpenFriend(id, origin)
	local view = views[id]
	if view and view.open then
		return view
	end
	view = table.remove(spare)
	if not view then
		friendCount = friendCount + 1
		view = NewView(nil, "friend")
		Build(view, "LefthyToolsStreamFriend" .. friendCount, nil)
	end
	view.key, view.id, view.kind, view.origin = id, id, "friend", origin
	view.picture = { mobs = {}, recent = {}, moments = {}, name = S.FriendName(id) }
	-- Side by side from the top left: the first place no other friend's window has.
	local taken = {}
	for _, other in pairs(views) do
		if other.kind == "friend" and other.open then
			taken[other.slot] = true
		end
	end
	view.slot = 0
	while taken[view.slot] do
		view.slot = view.slot + 1
	end
	views[id] = view
	ApplyScale(view, UserScale("friend"))
	PlaceAt(view, 12 + view.slot * (WIDTH * view.scale + 6), UIParent:GetHeight() - 8)
	view.win.Live.Text:SetText(L["LIVE"])
	view.win.Hint:Hide()
	Start(view)
	S.Watch(id, true)
	S.UpdateButton() -- (StreamButton.lua: its red dot)
	return view
end

function S.CloseView(key)
	local view = views[key]
	if not view or not view.open then
		return
	end
	view.open = false
	view.win:Hide()
	ReleaseAll(view)
	GameTooltip:Hide()
	if view.kind == "friend" then
		S.Watch(view.id, false)
		views[key] = nil
		spare[#spare + 1] = view
		S.UpdateButton()
	elseif view.kind == "me" then
		S.SenseNeed("me", false)
	end
end

function S.IsWatching(id)
	local view = views[id]
	return view ~= nil and view.open == true
end

-- Opens or closes a friend's stream; true if it's open now.
function S.ToggleFriend(id, origin)
	if S.IsWatching(id) then
		S.CloseView(id)
		return false
	end
	S.OpenFriend(id, origin)
	return true
end

-- A flight landed: its streams close (ones opened on the map or by command stay).
function S.CloseFlightViews()
	for key, view in pairs(views) do
		if view.kind == "friend" and view.origin == "flight" then
			S.CloseView(key)
		end
	end
end

-- Everything closes (Beacon switched off).
function S.CloseAllViews()
	for key in pairs(views) do
		S.CloseView(key)
	end
end

-- For tests: the view of a key, and the dots of one (yours by default).
function S.View(key)
	return views[key]
end

function B.StreamDots(key)
	local view = views[key or "me"]
	return view and view.dots or {}
end
