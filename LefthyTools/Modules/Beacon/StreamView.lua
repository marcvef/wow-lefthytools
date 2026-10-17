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
-- top, and a bottom line ("2 on you · 5 near · X casts Y"). Under the spells the battle row
-- (StreamBattle.lua): their model and the mobs they fight, the fight played on them; what happens
-- to them floats up from their model there (hits, heals, a dodge, loot; XP from the mob that died);
-- their kills since the window opened at the top right; after a fight, a line on how it went in
-- the bottom line's place for a few seconds.
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
local SEEN_FOR = 6         -- seconds a moment's number counts as shown (they come round: 1-99)

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
		GameTooltip:SetText(S.MobTitle(mob), r, g, b)
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
	GameTooltip:SetText(S.MobTitle(mob), 1, 1, 1)
	local class = S.ClassLabel(mob.class)
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
		local level = S.LevelText(mob.level)
		dot.Name:SetText(named and (level and ("%s %s"):format(mob.name, level) or mob.name) or "")
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
-- After a fight: one line, fading
---------------------------------------------------------------------------

-- The user: "if it remains only in the stream". A fight seen from its start (out of combat, then
-- in) is followed per window: how long it lasted, their kills (killing blows), the XP, their lowest
-- health (estimated). When it's over, a line takes the bottom line's place for SUMMARY_TIME, fading
-- in and out: "38 s · 3 kills · 420 XP · lowest ~10%", only what's known (no XP: none said). Their
-- death ends it too: "Died after 38 s · ...". A fight joined halfway isn't summed up (its numbers
-- would be short). Nothing in chat. Cost: a look per new picture, a fade while the line shows.
local SUMMARY_TIME = 6     -- seconds the line stays, fading in and out
local SUMMARY_WAIT = 1     -- seconds after the fight before it shows (the last kill's XP can come a moment later)
local SHORT_FIGHT = 4      -- shorter, with no kill, XP or death: no line (combat that only flickered)

-- "38 s", "1:12 min".
local function Duration(seconds)
	seconds = math.floor(seconds + 0.5)
	if seconds < 60 then
		return L["%d s"]:format(seconds)
	end
	return L["%d:%02d min"]:format(math.floor(seconds / 60), seconds % 60)
end

-- A moment while a fight is followed (also in the moment after it ends): kills and XP add up.
local function Tally(view, m)
	local fight = view.fight
	if not fight then
		return
	elseif m.kind == "kill" then
		fight.kills = fight.kills + 1
	elseif m.kind == "xp" and m.amount then
		fight.xp = fight.xp + m.amount
	end
end

-- What's known of it, in a line.
local function FightLine(fight)
	local length = Duration(fight.endAt - fight.startAt)
	local parts = { fight.died and L["Died after %s"]:format(length) or length }
	if fight.kills > 0 then
		parts[#parts + 1] = fight.kills == 1 and L["1 kill"] or L["%d kills"]:format(fight.kills)
	end
	if fight.xp > 0 then
		parts[#parts + 1] = L["%s XP"]:format(BreakUpLargeNumbers and BreakUpLargeNumbers(fight.xp) or tostring(fight.xp))
	end
	if fight.lowest and not fight.died then
		parts[#parts + 1] = L["lowest ~%d%%"]:format(math.floor(fight.lowest * 20 + 0.5) * 5) -- (in steps of 5, like the bar's)
	end
	return table.concat(parts, "  ·  ")
end

local function ShowSummary(view, fight)
	local win = view.win
	if not fight.died and fight.kills == 0 and fight.xp == 0 and fight.endAt - fight.startAt < SHORT_FIGHT then
		return
	end
	win.Summary:SetText(FightLine(fight))
	if fight.died then
		win.Summary:SetTextColor(1, 0.45, 0.4)
	else
		win.Summary:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	end
	win.Summary:SetAlpha(0)
	win.Summary:Show()
	view.summaryAt = view.clock
end

-- After each new picture: a fight begins (in combat after a picture out of it), goes on, ends (out
-- of combat, or dead); its line shows SUMMARY_WAIT later. In combat again before that: the same
-- fight, pulled on.
local function FightLook(view)
	local picture, fight = view.picture, view.fight
	if (view.kind == "friend" and view.stale) or (view.kind == "me" and (picture.looked or 0) < view.since) then
		return -- (nothing new from them yet: a picture from before the window opened says nothing)
	end
	local combat = picture.combat and not picture.dead and true or false
	if fight then
		if picture.dead and not fight.died then
			fight.died, fight.endAt = true, fight.endAt or view.clock
		elseif fight.endAt and combat and not fight.died then
			fight.endAt = nil
		elseif not fight.endAt and not combat then
			fight.endAt = view.clock
		end
		if not fight.endAt and picture.health then
			fight.lowest = math.min(fight.lowest or 1, picture.health)
		elseif fight.endAt and view.clock - fight.endAt >= SUMMARY_WAIT then
			view.fight = nil
			ShowSummary(view, fight)
		end
	elseif combat and view.wasCombat == false then
		view.fight = { startAt = view.clock, kills = 0, xp = 0, lowest = picture.health }
	end
	view.wasCombat = combat
end

-- Every frame while the line shows: it fades in, stays, fades out; the bottom line (and the hint
-- above it) gives way meanwhile.
local function FadeSummary(view)
	local win, age = view.win, view.clock - view.summaryAt
	local alpha = math.max(0, math.min(1, age / 0.3, (SUMMARY_TIME - age) / 1.5))
	if age >= SUMMARY_TIME then
		view.summaryAt = nil
		win.Summary:Hide()
	end
	win.Summary:SetAlpha(alpha)
	win.Status:SetAlpha(1 - alpha)
	win.Hint:SetAlpha(1 - alpha)
end

---------------------------------------------------------------------------
-- What happens to them: numbers floating up over the radar
---------------------------------------------------------------------------


-- The game's own word for a miss, dodge, ... (in its language).
local function Word(token)
	local word = _G[token]
	return type(word) == "string" and word or token:sub(1, 1) .. token:sub(2):lower()
end
S.Word = Word

-- One floating text: from x, y (off its anchor's middle: a model in the battle row, else the radar's)
-- by dx, dy over its life, fading in and out.
local function Float(view, text, x, y, dx, dy, color, scale, life, anchor)
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
	float.x, float.y, float.dx, float.dy, float.anchor = x, y, dx, dy, anchor or view.win.Radar
	float:SetText(text)
	float:SetTextColor(color[1], color[2], color[3])
	float:SetTextScale(scale or 1)
	float:SetAlpha(0)
	float:ClearAllPoints()
	float:SetPoint("CENTER", float.anchor, "CENTER", x, y)
	float:Show()
end
S.Float = Float

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
				f:SetPoint("CENTER", f.anchor or view.win.Radar, "CENTER", f.x + f.dx * p, f.y + f.dy * p)
				f:SetAlpha(p < 0.1 and p * 10 or p > 0.65 and (1 - p) / 0.35 or 1)
			end
		end
	end
end

local function ShowKills(view)
	local kills = view.kills
	view.win.Kills:SetText(kills == 1 and L["1 kill"] or kills > 1 and L["%d kills"]:format(kills) or "")
end

-- Loot: its icon and name in its quality's colour (an item the client doesn't know yet: asked for);
-- a rare find (chance: RareChance) has its drop chance after it, in gold.
local function LootText(m, chance)
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
	local text = (icon and ("|T%s:16:16|t "):format(icon) or "") .. (name or L["an item"])
	if chance then
		local Bt = ns.Bestiary
		text = text .. ", |cffffd14c" .. (Bt and Bt.Percent and Bt.Percent(chance) or ("%.1f%%"):format(chance * 100)) .. "|r"
	end
	return text, color
end
S.LootText = LootText

-- Rare finds (the user picked it: "When a friend loots something rare, the database chance pops up
-- with it"). A loot moment carries only the item and its quality, so the chance is worked out here,
-- from what this client has (nothing more over the network): the mobs killed lately (their kill and
-- XP moments, the last LATELY seconds; a friend's by the creature their stream named) and the dead
-- ones in the picture now are where it may have come from; the one likeliest to drop it is taken,
-- by the Bestiary's classic database (Bt.Known), else your own record of that kind once it has
-- RARE_KILLS kills (Bt.Mob). Below RARE it's a rare find: its float says the chance, in gold, a
-- little bigger and longer. Looked up when loot comes, never per frame; the classic database loads
-- the first time it's asked, as for the Bestiary's window. Without the Bestiary (switched off):
-- plain loot, as before.
local RARE = 0.02
local RARE_KILLS = 10
local LATELY = 45          -- seconds a kill counts as where loot may come from
local LATELY_MAX = 8

-- A mob's creature ID by its key: from the picture; gone from it already, from your own mob's GUID
-- or from the names a friend's stream sent.
local function CreatureFor(view, key)
	for _, mob in ipairs(view.picture.mobs) do
		if mob.key == key then
			return mob.creature
		end
	end
	if view.kind == "friend" then
		return S.FriendCreature(view.id, key)
	end
	return S.CreatureOf(key)
end

-- A kill or its XP: that kind was killed just now (each mob once).
local function Lately(view, key)
	local list = view.lately
	for _, kill in ipairs(list) do
		if kill.key == key then
			kill.at = view.clock
			return
		end
	end
	local creature = CreatureFor(view, key)
	if creature then
		table.insert(list, 1, { key = key, creature = creature, at = view.clock })
		list[LATELY_MAX + 1] = nil
	end
end

-- What a kind of mob drops an item with (0-1; nil: not known).
local function DropChance(Bt, creature, item)
	local known = Bt.Known(creature)
	local said = known and known.items[item]
	if said then
		return said[1]
	end
	local mob = Bt.Mob(creature)
	local own = mob and mob.kills >= RARE_KILLS and mob.items[item]
	return own and (Bt.Chance(mob, own)) or nil
end

-- A loot's chance where it most likely came from, if that's rare (nil: not rare, or not known).
local function RareChance(view, m)
	if m.chance then
		return m.chance < RARE and m.chance or nil -- (the preview's, made up)
	end
	local Bt = ns.Bestiary
	if not (Bt and Bt.module and Bt.module.enabled and m.item) then
		return nil
	end
	local best
	for _, kill in ipairs(view.lately) do
		local chance = view.clock - kill.at <= LATELY and DropChance(Bt, kill.creature, m.item)
		if chance and chance > 0 and chance > (best or 0) then
			best = chance
		end
	end
	for _, mob in ipairs(view.picture.mobs) do
		local chance = mob.dead and mob.creature and DropChance(Bt, mob.creature, m.item)
		if chance and chance > 0 and chance > (best or 0) then
			best = chance
		end
	end
	return best and best < RARE and best or nil
end

-- A moment: played in the battle row (StreamBattle.lua: a hit lands on their model, a heal or loot
-- floats up from it, XP from the mob that died); a kill counts (and adds to a fight's line).
local function Spawn(view, m)
	Tally(view, m)
	if (m.kind == "kill" or m.kind == "xp") and m.key then
		Lately(view, m.key) -- (loot may come from it)
	end
	if m.kind == "kill" then
		view.kills = view.kills + 1
		ShowKills(view)
		S.BattleKill(view, m.key) -- (its box falls now)
	else
		S.BattleMoment(view, m, m.kind == "loot" and RareChance(view, m) or nil)
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

local function ClearFloats(view)
	for _, f in ipairs(view.win.Floats.list) do
		f.on = false
		f:Hide()
	end
	wipe(view.seen)
	wipe(view.lately)
	view.kills = 0
	ShowKills(view)
end

---------------------------------------------------------------------------
-- The preview: a made-up friend in a made-up fight, on a loop
---------------------------------------------------------------------------

local PREVIEW_LOOP = 24
local PREVIEW_CALM = 21.5 -- her fight is over (the rest run off), so its line shows; a new one each loop
local previewMobs = {}
-- What happens to her (seconds into the loop): hits while the bandits are on her, heals, a dodge,
-- the bandit's death (her killing blow, its XP), loot.
local PREVIEW_MOMENTS = {
	{ 3, "hurt", 24 }, { 4.6, "hurt", 31 }, { 5.5, "avoid", "DODGE" }, { 6.3, "hurt", 27 }, { 7.5, "heal", 120 },
	{ 9, "hurt", 26 }, { 10.4, "hurt", 158, true }, { 11.6, "heal", 310, true }, { 12.8, "hurt", 25 },
	{ 14, "kill" }, { 14.1, "xp", 87 }, { 16.5, "loot", 774 }, { 19, "hurt", 30 }, { 21, "avoid", "PARRY" },
}

-- Her spells: a cast every 4 s, { start, spell ID, cast time, its name if the game has none },
-- each joining her last spells when it goes off; a Fire Blast (an instant) now and then.
local PREVIEW_CASTS = { { 0, 133, 2.5, L["Fireball"] }, { 4, 133, 2.5, L["Fireball"] }, { 8, 116, 2.5, L["Frostbolt"] },
	{ 12, 118, 1.5, L["Polymorph"] }, { 16, 133, 2.5, L["Fireball"] } } -- (the last before the fight is over)
local PREVIEW_BLASTS = { 7, 15 }
-- Once a loop she sheeps the mage: her target from a moment before her Polymorph until after it went
-- off (then the leader again). It's a sheep until the fight is over: it leaves the row then.
local PREVIEW_POLYMORPH, PREVIEW_ON_MAGE, PREVIEW_SHEEP = 118, { 11.5, 14.5 }, 13.5

-- Whether a moment of the loop passed since the last step (also over the loop's end).
local function Passed(at, was, t)
	return (was < at and at <= t) or (t < was and (at > was or at <= t))
end

-- The moments passed since the last step, newest first, kept 2.5 s.
local function PreviewMoments(view, was, t)
	local moments = view.picture.moments
	for _, e in ipairs(PREVIEW_MOMENTS) do
		local at, kind = e[1], e[2]
		if Passed(at, was, t) then
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
				m.item, m.quality, m.chance = e[3], 2, 0.0128 -- (Malachite: a rare find, the classic database's chance from a Defias Bandit)
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
	mob.aggro, mob.aggroName, mob.aggroSelf = nil, nil, false
	return mob
end

local function FeedPreview(view)
	local picture, t = view.picture, view.clock % PREVIEW_LOOP
	local fighting = t > 2 and t < PREVIEW_CALM
	local mobs = picture.mobs
	wipe(mobs)
	picture.name, picture.classFile, picture.where, picture.facing = PREVIEW_FRIEND, PREVIEW_CLASS, L["Westfall"], 0
	picture.combat = fighting
	picture.power = picture.power or { token = "MANA" }
	picture.power.frac = 0.4 + 0.3 * math.cos(t / 4)
	picture.health = 0.65 + 0.3 * math.cos(t / 3)
	local was = view.previewAt or t
	view.previewAt = t
	PreviewMoments(view, was, t)
	-- (Their models: Hogger, a Defias Bandit, a Defias Rogue Wizard, a Riverpaw Gnoll, Thuros
	-- Lightfingers. Health: the leader's goes down, the bandit's faster, the mage's isn't known.
	-- Who has aggro: her Fireball pulls the leader, Bob, the tank, takes it from her at 8 s; the
	-- bandit stays on her; the mage is on Cedric, passing by, outside her group, until she sheeps it.)
	local onMage = t >= PREVIEW_ON_MAGE[1] and t < PREVIEW_ON_MAGE[2] -- (her target for her Polymorph)
	local leader = PreviewMob(1, "leader", L["Bandit leader"], 16, "elite", 448)
	leader.combat, leader.attacking, leader.target, leader.engaged = fighting, fighting and t < 8, not onMage, fighting
	leader.yards, leader.bearing = math.max(6, 30 - t * 2), -0.6 + 0.15 * math.sin(t)
	leader.casting = fighting and (t % 8 >= 3 and t % 8 < 5) and L["Fireball"] or nil
	local landed = 0 -- (her spells land; the Polymorph hurts nobody)
	for _, c in ipairs(PREVIEW_CASTS) do
		if c[2] ~= PREVIEW_POLYMORPH and t >= c[1] + c[3] then
			landed = landed + 1
		end
	end
	leader.health = math.max(0.1, 1 - 0.13 * landed)
	if leader.attacking then
		leader.aggro, leader.aggroSelf = "DAMAGER", true
	elseif leader.combat then
		leader.aggro, leader.aggroName = "TANK", "Bob"
	end
	mobs[#mobs + 1] = leader
	if t < 18 then
		local bandit = PreviewMob(2, "bandit", L["Bandit"], 15, "normal", 116)
		bandit.dead = t >= 14
		bandit.combat, bandit.attacking, bandit.engaged = not bandit.dead, not bandit.dead, not bandit.dead
		bandit.yards, bandit.bearing = 5 + math.sin(t * 1.3), 0.35 + 0.15 * math.sin(t * 0.8)
		bandit.health = bandit.dead and 0 or math.max(0.05, 1 - 0.12 * math.floor(math.max(0, t - 2) / 1.5)) -- (Bob's hits)
		bandit.aggro, bandit.aggroSelf = not bandit.dead and "DAMAGER" or nil, not bandit.dead
		mobs[#mobs + 1] = bandit
	end
	local mage = PreviewMob(3, "mage", L["Bandit mage"], 15, "normal", 474)
	mage.combat, mage.engaged, mage.target = fighting, fighting, onMage -- (she's on its threat list)
	mage.yards, mage.bearing = 24, 1.1 + 0.03 * t -- (casting at her, until it's a sheep)
	mage.casting = fighting and (t % 6 < 2 and t < PREVIEW_SHEEP) and L["Frostbolt"] or nil
	if fighting and t < PREVIEW_SHEEP then
		mage.aggro, mage.aggroName = "OUTSIDER", "Cedric"
	end
	mobs[#mobs + 1] = mage
	local gnoll = PreviewMob(4, "gnoll", L["Gnoll"], 14, "normal", 117)
	gnoll.yards, gnoll.bearing, gnoll.sure = 32 + 3 * math.sin(t * 0.4), 2.9, 0.25 -- behind, not sure yet: faint
	mobs[#mobs + 1] = gnoll
	local rare = PreviewMob(5, "rare", L["Greyfang"], 17, "rare", 61)
	rare.yards, rare.bearing = 37, 2.4 + 0.1 * math.sin(t * 0.5)
	mobs[#mobs + 1] = rare
	-- Her group: a warrior in front of her, at the leader (placed exactly); and someone passing by.
	local tank = PreviewMob(6, "tank", "Bob", 16)
	tank.player, tank.classFile, tank.friendly, tank.group, tank.combat = true, "WARRIOR", true, true, fighting
	tank.yards, tank.bearing = math.max(4, leader.yards - 2), leader.bearing + 0.25
	tank.exact = math.floor(tank.yards + 0.5)
	mobs[#mobs + 1] = tank
	local passer = PreviewMob(7, "passer", "Cedric", 22)
	passer.player, passer.classFile, passer.friendly, passer.sure = true, "PRIEST", true, 0.5
	passer.yards, passer.bearing = 28, -2.2 + 0.05 * t
	mobs[#mobs + 1] = passer
	-- What she's doing: her cast now, and the spells before it.
	local now = GetTime()
	picture.cast = nil
	for _, c in ipairs(PREVIEW_CASTS) do
		if t >= c[1] and t < c[1] + c[3] then
			local info = Value("C_Spell.GetSpellInfo", c[2])
			local cast = picture.castPreview or {}
			picture.castPreview = cast
			cast.name, cast.icon, cast.spellID = info and info.name or c[4], info and info.iconID, c[2]
			cast.start, cast.finish, cast.channel = now - (t - c[1]), now - (t - c[1]) + c[3], false
			picture.cast = cast
		end
	end
	if not picture.recent[1] then
		for i, id in ipairs({ 2136, 116, 122, 133 }) do -- Fire Blast, Frostbolt, Frost Nova, Fireball (oldest last)
			S.AddRecent(picture.recent, id, now - 8 + i)
		end
	end
	-- A cast that went off joins her last spells; so does a Fire Blast.
	for _, c in ipairs(PREVIEW_CASTS) do
		if Passed(c[1] + c[3], was, t) then
			S.AddRecent(picture.recent, c[2], now)
		end
	end
	for _, at in ipairs(PREVIEW_BLASTS) do
		if Passed(at, was, t) then
			S.AddRecent(picture.recent, 2136, now)
		end
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
		S.BattleShow(view) -- (StreamBattle.lua: the row, and what happened since)
		FightLook(view) -- (before the moments: the first hit is the fight's, the last kill's XP too)
		Happenings(view) -- (after the row: XP floats from its mob)
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
	S.BattleUpdate(view, elapsed)
	MoveFloats(view, elapsed)
	if view.summaryAt then
		FadeSummary(view)
	end
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

	-- The battle row under the spells (StreamBattle.lua): their model, the mobs they fight.
	S.BattleBuild(win, act)
	win.Floats:SetFrameLevel(win.Foes:GetFrameLevel() + 30) -- (the numbers float over the models too)

	win.Status = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	win.Status:SetPoint("BOTTOM", 0, 12)
	win.Status:SetWidth(WIDTH - 36)
	-- Said in your own window: directions are learned.
	win.Hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	win.Hint:SetPoint("BOTTOM", win.Status, "TOP", 0, 4)
	win.Hint:SetWidth(WIDTH - 20)
	win.Hint:SetText(L["Move and turn: faint dots find their place."])
	win.Hint:Hide()
	-- After a fight, its line in the bottom line's place for a few seconds (FightLook). Clear of the
	-- radar's middle and the battle row's models.
	win.Summary = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	win.Summary:SetPoint("BOTTOM", 0, 12)
	win.Summary:SetWidth(WIDTH - 20)
	win.Summary:Hide()

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
		picture = { mobs = {}, recent = {}, moments = {} }, seen = {}, kills = 0, lately = {} }
end

-- Shows a view (fresh: its dots, map, floating numbers and picture start over).
local function Start(view)
	ReleaseAll(view)
	ClearFloats(view)
	S.BattleReset(view) -- (the models load anew when shown)
	if view.picture ~= S.Sensed() then -- (the sensor's own picture: friends watching may be getting it)
		wipe(view.picture.mobs)
		wipe(view.picture.recent)
		wipe(view.picture.moments)
		view.picture.cast, view.picture.health = nil, nil
	end
	view.previewAt = nil
	view.map.id, view.map.x, view.map.source = false, nil, nil
	view.clock, view.nextFeed, view.open, view.looked = 0, 0, true, nil
	view.fight, view.wasCombat, view.summaryAt, view.since = nil, nil, nil, GetTime() -- (a fight going on now isn't seen from its start)
	view.win.Summary:Hide()
	view.win.Status:SetAlpha(1)
	view.win.Hint:SetAlpha(1)
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
