local _, ns = ...
local LT = ns.LT
local L = ns.L
local Bt = ns.Bestiary
local M = Bt.module

-- The Bestiary's ledger: every kind of mob you've killed, with its statistics and drops, and one
-- search over mobs and items. On the left the mobs (name, level, kind, your kills, their best drops
-- as tiny icons), sorted by kills, name, level, coin, worth (coin and the drops' vendor value), XP
-- per kill or per hour of fighting (a row then says it) or when you last killed one: where farming
-- pays. On the right the one picked: its whole model turning slowly, kills, coin, first and last
-- kill, skinnings, under the model what a kill pays (its worth, XP and time per kill, XP per hour of
-- fighting); beside that where you killed it, seen without scrolling: the world map's art of the
-- zone with the most kills (what you've explored of it, as your world map shows it), a dot each, a
-- picker for its other zones; under all that its drops (as in the window: quality edge, how many,
-- chance; skinning marked), scrolling.
-- At the top what the Bestiary knows in all, and your rarest find. With the classic drop database
-- (Bestiary.lua): a row says how many of its drops you've found, and the picked mob's drops have a
-- section of what you haven't had yet, faded, between its own drops and its world drops.
--
-- The search is fuzzy: a query's letters in order, not necessarily together ("dfbnd" finds Defias
-- Bandit), case and spaces ignored. Letters together, at a word's start and early count more. It
-- looks at mob names and at the names of everything they dropped: a mob found by one of its items
-- shows that item and its chance in its row, and the picked mob's matching drops stand out.
-- Escape closes it (it's for looking things up, unlike the window, which stays).
--
-- The wish list (Bestiary.lua) is a strip of icons at the top right: hovering one says where it
-- drops (your kills, else the classic database's mobs you've seen; how many more it lists) and how
-- many kills since you pinned it; a click searches for it, Alt-click takes it off the list. Alt-click
-- on any drop here pins it, as in the window.

-- The picked mob's pane: its details (model, numbers, what a kill pays) and beside them the map of
-- where you killed it, both seen without scrolling (the user: "the map should be also on the right
-- of the mob details so that you dont have to scroll down"); its drops under them, the pane wide.
-- 986 x 580 fits a 1366 x 768 screen at the default UI scale (768 units tall) with room around it.
local PAD = 12
local LIST_W, ROW_H = 282, 36
local TOP = 104             -- where the list and the picked mob start
local MODEL_W, MODEL_H = 112, 150
local DETAILS_W = 320       -- the model and its numbers, what a kill pays under them
local MAP_GAP = 16          -- between them and the map
local MAP_W, MAP_H = 330, 220 -- the map's box (a zone's art is 3:2)
local MAP_HEAD = 24         -- the row over it: a heading, the zone's name or a picker of its zones
local ZONE_PICK_W = 180     -- (its list too: "Stranglethorn Vale (50)" fits)
local UPPER = MAP_HEAD + 4 + MAP_H + 4 + 13 -- the details and the map (a line under it): the drops start under them
local PANE_W = DETAILS_W + MAP_GAP + MAP_W
local WIDTH, HEIGHT = PAD + LIST_W + 14 + PANE_W + PAD, 580
local CELL, CELL_GAP, CELL_ROW = 28, 6, 46  -- a drop's icon, the gap, a row with its chance under it
local DROPS_W = PANE_W - 24 -- (the picked mob's pane, less its scroll bar)
local PER_ROW = math.floor((DROPS_W + CELL_GAP) / (CELL + CELL_GAP))
local ROW_ICONS = 6
local WISH_ICON, WISH_GAP, WISH_TOP = 20, 4, 40 -- the wish list's strip, at the top right
local WISHES = 8          -- icons in it, at most (the rest: "+N")
local WISH_SOURCES = 8    -- mobs named in an icon's tooltip, at most
local MAP_DOT = 6           -- a kill on the map of where you killed them
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local GOLD = { 1, 0.82, 0.3 }
local SORTS = { "kills", "name", "level", "coin", "worth", "xp", "xph", "last" }
local issecret = issecretvalue or function() return false end

local function Value(f, ...)
	if not f then
		return nil
	end
	local ok, v = pcall(f, ...)
	if ok and not issecret(v) then
		return v
	end
end

local ledger
local entries = {}       -- the list as shown: { creature, mob, score, positions, items (found by the search) }
local selected           -- the picked creature
local query = ""         -- the search, lower case, without spaces
local sortBy = "kills"

---------------------------------------------------------------------------
-- The search
---------------------------------------------------------------------------

-- How well the query matches a text: nil when its letters aren't all in it in order; else a score
-- (letters together, at a word's start, early, in a short text: more) and where they are.
local function Fuzzy(q, text)
	if q == "" or type(text) ~= "string" then
		return nil
	end
	local lower = text:lower()
	local score, from, run, positions = 0, 1, 0, {}
	for i = 1, #q do
		local at = lower:find(q:sub(i, i), from, true)
		if not at then
			return nil
		end
		run = (i > 1 and at == from) and run + 1 or 0
		local wordStart = at == 1 or lower:sub(at - 1, at - 1):find("[%s%-%(%.']") ~= nil
		score = score + 1 + run * 3 + (wordStart and 4 or 0)
		positions[#positions + 1] = at
		from = at + 1
	end
	return score - (positions[1] - 1) * 0.2 - #lower * 0.02, positions
end
Bt.Fuzzy = Fuzzy

-- The name with the found letters in gold (only plain-letter names: a letter of several bytes
-- can't be coloured on its own).
local function Marked(name, positions)
	if not positions or name:find("[\128-\255]") then
		return name
	end
	local marked, last = {}, 0
	for _, at in ipairs(positions) do
		marked[#marked + 1] = name:sub(last + 1, at - 1)
		marked[#marked + 1] = "|cffffd100" .. name:sub(at, at) .. "|r"
		last = at
	end
	marked[#marked + 1] = name:sub(last + 1)
	return table.concat(marked)
end

-- An item's name: as it was looted, else the client's, kept in its record for the search (asked for
-- when it doesn't know it yet, once: it redraws when it comes).
local function NameOf(id, item)
	if not item then
		return nil
	elseif item[4] then
		return item[4]
	end
	local ok, name = false, nil
	if C_Item and C_Item.GetItemInfo then
		ok, name = pcall(C_Item.GetItemInfo, ("item:%d"):format(id))
	end
	if ok and type(name) == "string" and not issecret(name) then
		item[4] = name
		return name
	end
	Bt.AskItem(id)
end

local function XPPerHour(mob)
	local _, _, perHour = Bt.Pace(mob)
	return perHour
end

local SORT_KEYS = {
	kills = function(mob) return -mob.kills end,
	name = function(mob) return (mob.name or "~"):lower() end,
	level = function(mob) return -(mob.level or 0) end,
	coin = function(mob) return mob.kills > 0 and -(mob.money / mob.kills) or 0 end,
	worth = function(mob) return -((Bt.Worth(mob)) or 0) end,
	xp = function(mob) return -((Bt.Pace(mob)) or 0) end,
	xph = function(mob) return -(XPPerHour(mob) or 0) end,
	last = function(mob) return -(mob.last or 0) end,
}

-- What a row says on the right, sorted by something it doesn't show otherwise: coin, worth, XP per
-- kill or per hour of fighting (nil: the found count, as always).
local SORT_SHOWS = {
	coin = function(mob) return mob.kills > 0 and mob.money > 0 and Bt.Coins(mob.money / mob.kills) or "" end,
	worth = function(mob)
		local worth = Bt.Worth(mob)
		return worth and worth > 0 and "~" .. Bt.Coins(Bt.Rounded(worth)) or ""
	end,
	xp = function(mob)
		local xp = Bt.Pace(mob)
		return xp and L["%d XP"]:format(math.floor(xp + 0.5)) or ""
	end,
	xph = function(mob)
		local perHour = XPPerHour(mob)
		return perHour and L["%s XP/h"]:format(Bt.Thousands(perHour)) or ""
	end,
}

-- The list: everything (sorted) or what the search finds (the best match first).
local function Collect()
	wipe(entries)
	local key = SORT_KEYS[sortBy] or SORT_KEYS.kills
	for creature, mob in pairs(LefthyToolsBestiaryDB and LefthyToolsBestiaryDB.mobs or {}) do
		if mob.kills > 0 or (mob.skinned or 0) > 0 then
			local entry = { creature = creature, mob = mob, sort = key(mob) }
			if query ~= "" then
				local score, positions = Fuzzy(query, mob.name)
				entry.positions = positions
				local found = {}
				for _, skin in ipairs({ false, true }) do
					for id, item in pairs(Bt.Part(mob, skin)) do
						local itemScore = Fuzzy(query, NameOf(id, item))
						if itemScore then
							found[#found + 1] = { id = id, score = itemScore, skin = skin, chance = Bt.Chance(mob, item, skin), quality = item[3] }
						end
					end
				end
				table.sort(found, function(a, b) return a.score > b.score end)
				entry.items = #found > 0 and found or nil
				local best = math.max(score or -math.huge, found[1] and found[1].score * 0.95 or -math.huge)
				if best > -math.huge then
					entry.score = best
					entries[#entries + 1] = entry
				end
			else
				entries[#entries + 1] = entry
			end
		end
	end
	table.sort(entries, function(a, b)
		if a.score and b.score and a.score ~= b.score then
			return a.score > b.score
		elseif a.sort ~= b.sort then
			return a.sort < b.sort
		end
		return a.creature < b.creature
	end)
end

---------------------------------------------------------------------------
-- What the Bestiary knows in all, and your rarest find
---------------------------------------------------------------------------

local function Totals()
	local mobs, kills, coin, items = 0, 0, 0, {}
	local rarest
	for creature, mob in pairs(LefthyToolsBestiaryDB and LefthyToolsBestiaryDB.mobs or {}) do
		mobs, kills, coin = mobs + 1, kills + mob.kills, coin + mob.money
		for id, item in pairs(mob.items) do
			items[id] = true
			local chance = Bt.Chance(mob, item)
			-- (the rarest: the lowest chance, from enough kills to mean something)
			if mob.kills >= 5 and (not rarest or chance < rarest.chance) then
				rarest = { id = id, item = item, chance = chance, mob = mob, creature = creature }
			end
		end
		for id in pairs(mob.skins or {}) do
			items[id] = true
		end
	end
	local count = 0
	for _ in pairs(items) do
		count = count + 1
	end
	return mobs, kills, count, coin, rarest
end

---------------------------------------------------------------------------
-- A mob's row
---------------------------------------------------------------------------

-- A click picks that row and keeps it while the list redraws (names coming in, a kill), also among
-- a search's results (in game a click went back to the first); typing again picks the best match.
local function Select(creature)
	selected = creature
	ledger.keepPick = true
	Bt.DrawLedger()
end

local function NewRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(LIST_W - 26, ROW_H)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row.Picked = row:CreateTexture(nil, "BACKGROUND")
	row.Picked:SetAllPoints()
	row.Picked:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.14)
	row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.Name:SetPoint("TOPLEFT", 6, -4)
	row.Name:SetPoint("RIGHT", -46, 0)
	row.Name:SetJustifyH("LEFT")
	row.Name:SetWordWrap(false)
	row.Kills = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.Kills:SetPoint("TOPRIGHT", -6, -4)
	row.KillsLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.KillsLabel:SetPoint("TOPRIGHT", row.Kills, "BOTTOMRIGHT", 0, -1)
	row.KillsLabel:SetTextScale(0.85)
	row.icons = {}
	for i = 1, ROW_ICONS do
		local icon = row:CreateTexture(nil, "ARTWORK")
		icon:SetSize(14, 14)
		icon:SetPoint("TOPLEFT", 6 + (i - 1) * 17, -19)
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		row.icons[i] = icon
	end
	row.Found = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Found:SetPoint("LEFT", row.icons[1], "RIGHT", 4, 0)
	row.Found:SetPoint("RIGHT", -46, 0)
	row.Found:SetJustifyH("LEFT")
	row.Found:SetWordWrap(false)
	-- How many of the classic database's drops you've found: "6/11 found".
	row.Known = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.Known:SetPoint("RIGHT", -46, 0)
	row.Known:SetPoint("TOP", row.icons[1], "TOP", 0, 0)
	row.Known:SetTextScale(0.9)
	row:SetScript("OnClick", function(self) Select(self.creature) end)
	return row
end

-- Its best drops as tiny icons (the best quality first, then the likeliest), or what the search
-- found among its drops: the best one's icon, name and chance.
local function FillRow(row, entry)
	local mob = entry.mob
	row.creature = entry.creature
	local tag = mob.class == "elite" and (" |cffffd100" .. L["Elite"] .. "|r") or mob.class == "rare" and (" |cffc0c0ff" .. L["Rare"] .. "|r")
		or mob.class == "rareelite" and (" |cffc0c0ff" .. L["Rare elite"] .. "|r") or ""
	local name = Marked(mob.name or ("#" .. entry.creature), entry.positions)
	row.Name:SetText(name .. (mob.level and mob.level > 0 and (" |cff888888" .. mob.level .. "|r") or "") .. tag)
	row.Kills:SetText(tostring(mob.kills))
	row.KillsLabel:SetText(mob.kills == 1 and L["kill"] or L["kills"])
	row.Picked:SetShown(entry.creature == selected)
	for _, icon in ipairs(row.icons) do
		icon:Hide()
	end
	local shows = SORT_SHOWS[sortBy]
	if shows then -- (sorted by it: what it's sorted by)
		row.Known:SetText(shows(mob))
		row.Known:SetShown(not entry.items)
	else
		local _, found, total = Bt.Compare(entry.creature, mob, M.db.showPoor, true)
		row.Known:SetText(total and total > 0 and L["%d/%d found"]:format(found, total) or "")
		row.Known:SetShown(not entry.items and total ~= nil)
	end
	if entry.items then
		local found = entry.items[1]
		local r, g, b = Bt.QualityColor(found.quality)
		row.icons[1]:SetTexture(Bt.ItemIcon(found.id))
		row.icons[1]:Show()
		row.Found:SetText(("|cff%02x%02x%02x%s|r  %s%s"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5),
			NameOf(found.id, Bt.Part(mob, found.skin)[found.id]) or "?",
			Bt.Percent(found.chance), found.skin and (" |T%s:12:12|t"):format(Bt.SKIN_ICON) or "")
			.. (#entry.items > 1 and ("  |cff888888+" .. (#entry.items - 1) .. "|r") or ""))
		row.Found:Show()
	else
		row.Found:Hide()
		local best = {}
		for _, drop in ipairs(Bt.Drops(mob, M.db.showPoor)) do
			if not drop.group then -- (its own drops: not the world drops)
				best[#best + 1] = drop
			end
		end
		table.sort(best, function(a, b)
			if a.quality ~= b.quality then
				return a.quality > b.quality
			end
			return a.chance > b.chance
		end)
		for i = 1, math.min(ROW_ICONS, #best) do
			row.icons[i]:SetTexture(Bt.ItemIcon(best[i].id))
			row.icons[i]:Show()
		end
	end
	row:Show()
end

---------------------------------------------------------------------------
-- The picked mob
---------------------------------------------------------------------------

local function Ago(t)
	local seconds = math.max(0, time() - (t or 0))
	if seconds < 120 then
		return L["just now"]
	elseif seconds < 3600 then
		return L["%d min ago"]:format(math.floor(seconds / 60))
	elseif seconds < 86400 then
		return L["%d h ago"]:format(math.floor(seconds / 3600))
	elseif seconds < 2 * 86400 then
		return L["yesterday"]
	end
	return L["%d days ago"]:format(math.floor(seconds / 86400))
end

-- A section of the picked mob's drops at y in its scrolling area (heading, a rule, every drop: no
-- "+N", it scrolls); returns where the next one starts. show false: hidden.
local function Section(section, title, list, kills, y, show)
	section.Heading:SetShown(show)
	section.Rule:SetShown(show)
	section.Grid:SetShown(show)
	if not show then
		return y
	end
	y = y > 0 and y + 10 or y
	section.Heading:ClearAllPoints()
	section.Heading:SetPoint("TOPLEFT", ledger.Pane.Drops, "TOPLEFT", 0, -y)
	section.Heading:SetText(title)
	y = y + 20
	section.Grid:ClearAllPoints()
	section.Grid:SetPoint("TOPLEFT", ledger.Pane.Drops, "TOPLEFT", 0, -y)
	local rows = Bt.Lay(section.Grid, section.cells, list, kills, CELL, CELL_GAP, PER_ROW, #list, true)
	return y + rows * CELL_ROW
end

local function MapName(mapID)
	local info = C_Map and Value(C_Map.GetMapInfo, mapID)
	local name = type(info) == "table" and info.name
	return not issecret(name) and type(name) == "string" and name or ("#" .. mapID)
end

-- A number the game gave (nil: none, or a secret).
local function Number(v)
	if not issecret(v) and type(v) == "number" then
		return v
	end
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
-- like the base tiles), cut at the map's edge; one shown only on mouseover isn't explored. Returns
-- how many of the pool are in use.
local function LayOverlay(where, info, layer, scale, n)
	local width, height = Number(info.textureWidth), Number(info.textureHeight)
	local files, mouseOver = info.fileDataIDs, info.isShownByMouseOver
	if not (width and height and width > 0 and height > 0) or issecret(files) or type(files) ~= "table"
		or issecret(mouseOver) or mouseOver == true then
		return n
	end
	local onTop = not issecret(info.isDrawOnTopLayer) and info.isDrawOnTopLayer == true
	local x0, y0 = Number(info.offsetX) or 0, Number(info.offsetY) or 0
	local wide, tall = math.ceil(width / layer.tileWidth), math.ceil(height / layer.tileHeight)
	for row = 1, tall do
		local y = y0 + (row - 1) * layer.tileHeight
		local h, fileH = OverlayPart(height, layer.tileHeight, row == tall)
		h = math.min(h, layer.layerHeight - y)
		for col = 1, wide do
			local x = x0 + (col - 1) * layer.tileWidth
			local w, fileW = OverlayPart(width, layer.tileWidth, col == wide)
			w = math.min(w, layer.layerWidth - x)
			local file = files[(row - 1) * wide + col]
			if file and w > 0 and h > 0 then
				n = n + 1
				local tile = where.overlays[n] or where.Map:CreateTexture(nil, "ARTWORK", nil, 1)
				where.overlays[n] = tile
				tile:SetDrawLayer("ARTWORK", onTop and 2 or 1) -- (over the base art; some over the others, as Blizzard draws them)
				tile:SetTexture(file)
				tile:SetTexCoord(0, w / fileW, 0, h / fileH)
				tile:SetSize(w * scale, h * scale)
				tile:ClearAllPoints()
				tile:SetPoint("TOPLEFT", where.Map, "TOPLEFT", x * scale, -y * scale)
				tile:Show()
			end
		end
	end
	return n
end

-- The world map's art of a zone, as large as fits the map's box (MAP_W x MAP_H): its first layer's
-- tiles, laid like Blizzard_MapCanvasDetailLayer (and the fight stream's map), the last column and
-- row cut to the map's edge. That art leaves what you haven't explored blank; what you have is
-- overlays on it (C_MapExplorationInfo.GetExploredMapTextures, laid like Blizzard's
-- MapExplorationPin), so the map shows what your world map shows (the user: "ideally the same
-- visibility the player has"). The game saying nothing: the art alone. No art: the box's dark back
-- alone. Returns its width and height; laid again only for another map, or once you've explored
-- more (MAP_EXPLORATION_UPDATED: where.mapID = nil).
local function LayMap(where, mapID)
	if where.mapID == mapID then
		return where.width, where.height
	end
	where.mapID = mapID
	local layers = C_Map and Value(C_Map.GetMapArtLayers, mapID)
	local layer = type(layers) == "table" and layers[1]
	local textures = type(layer) == "table" and Value(C_Map.GetMapArtLayerTextures, mapID, 1)
	local width, height, n, o = MAP_W, MAP_H, 0, 0
	if type(textures) == "table" and (layer.layerWidth or 0) > 0 and (layer.layerHeight or 0) > 0
		and (layer.tileWidth or 0) > 0 and (layer.tileHeight or 0) > 0 then
		local scale = math.min(MAP_W / layer.layerWidth, MAP_H / layer.layerHeight)
		local cols = math.ceil(layer.layerWidth / layer.tileWidth)
		width, height = layer.layerWidth * scale, layer.layerHeight * scale
		for row = 1, math.ceil(layer.layerHeight / layer.tileHeight) do
			for col = 1, cols do
				local file = textures[(row - 1) * cols + col]
				if file then
					n = n + 1
					local tile = where.tiles[n] or where.Map:CreateTexture(nil, "ARTWORK")
					where.tiles[n] = tile
					local w = math.min(layer.tileWidth, layer.layerWidth - (col - 1) * layer.tileWidth)
					local h = math.min(layer.tileHeight, layer.layerHeight - (row - 1) * layer.tileHeight)
					tile:SetTexture(file)
					tile:SetTexCoord(0, w / layer.tileWidth, 0, h / layer.tileHeight)
					tile:SetSize(w * scale, h * scale)
					tile:ClearAllPoints()
					tile:SetPoint("TOPLEFT", where.Map, "TOPLEFT", (col - 1) * layer.tileWidth * scale, -(row - 1) * layer.tileHeight * scale)
					tile:Show()
				end
			end
		end
		local explored = C_MapExplorationInfo and Value(C_MapExplorationInfo.GetExploredMapTextures, mapID)
		for _, info in ipairs(type(explored) == "table" and explored or {}) do
			if not issecret(info) and type(info) == "table" then
				o = LayOverlay(where, info, layer, scale, o)
			end
		end
	end
	for i = n + 1, #where.tiles do
		where.tiles[i]:Hide()
	end
	for i = o + 1, #where.overlays do
		where.overlays[i]:Hide()
	end
	where.width, where.height = width, height
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
	where.maps, where.shown = maps, shown
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

local function DrawPicked()
	local pane, mob = ledger.Pane, Bt.Mob(selected)
	pane:SetShown(mob ~= nil)
	ledger.Empty:SetShown(mob == nil)
	if not mob then
		return
	end
	if pane.creature ~= selected then
		pane.creature, pane.facing = selected, 0.4
		pane.Model:ClearModel()
		pane.Model:SetCreature(selected)
		pane.Scroll:SetVerticalScroll(0)
		pane.where.zone = nil -- (its map: the zone with the most kills again)
	end
	pane.Name:SetText(mob.name or ("#" .. selected))
	pane.Kind:SetText(Bt.Kind({ level = mob.level, class = mob.class }))
	local lines = { (mob.kills == 1 and L["1 kill"] or L["%d kills"]:format(mob.kills)) }
	if mob.kills > 0 then
		lines[#lines + 1] = mob.money > 0 and L["%s each, %s in all"]:format(Bt.Coins(mob.money / mob.kills), Bt.Coins(mob.money))
			or L["no coin"]
	end
	if mob.first then
		lines[#lines + 1] = L["First: %s"]:format(Ago(mob.first))
	end
	if mob.last then
		lines[#lines + 1] = L["Last: %s"]:format(Ago(mob.last))
	end
	if (mob.skinned or 0) > 0 then
		lines[#lines + 1] = ("|T%s:12:12|t "):format(Bt.SKIN_ICON) .. L["Skinned %d times"]:format(mob.skinned)
	end
	-- The classic database beside it: its coin, and how many of its drops you've found.
	local unseen, had, total = Bt.Compare(selected, mob, M.db.showPoor)
	local known = Bt.Known(selected)
	if known and known.coin then
		lines[#lines + 1] = "|cff999999" .. L["Classic database: %s to %s each"]:format(Bt.Coins(known.coin[1]), Bt.Coins(known.coin[2])) .. "|r"
	end
	if total and total > 0 then
		lines[#lines + 1] = "|cff999999" .. L["%d of its %d drops found"]:format(had, total) .. "|r"
	end
	pane.Stats:SetText(table.concat(lines, "\n"))
	-- What a kill pays, a line each, under the model; beside it all the map of where you killed it.
	local _, pace = Bt.PaceText(mob)
	pane.Pace:SetText(table.concat(pace, "\n"))
	pane.Pace:SetShown(#pace > 0)
	Where(pane.where, mob)
	local own, world = {}, {}
	for _, drop in ipairs(Bt.Drops(mob, M.db.showPoor, selected)) do
		if drop.group then
			world = drop.group
		else
			own[#own + 1] = drop
		end
	end
	unseen = unseen or {}
	local y = Section(pane.sections.own, L["Drops (%d)"]:format(#own), own, mob.kills, 0, true)
	y = Section(pane.sections.unseen, L["Not seen yet (%d), classic database"]:format(#unseen), unseen, mob.kills, y, #unseen > 0)
	y = Section(pane.sections.world, L["World drops (%d)"]:format(#world), world, mob.kills, y, #world > 0)
	pane.Drops:SetHeight(math.max(y, 10))
	-- What the search found stands out; the rest steps back.
	local found = {}
	for _, entry in ipairs(entries) do
		if entry.creature == selected and entry.items then
			for _, item in ipairs(entry.items) do
				found[item.id] = true
			end
		end
	end
	for _, section in pairs(pane.sections) do
		for _, cell in ipairs(section.cells) do
			cell:SetAlpha((not next(found) or (cell.drop and found[cell.drop.id])) and 1 or 0.35)
		end
	end
end

---------------------------------------------------------------------------
-- The wish list's strip
---------------------------------------------------------------------------

-- Hover: the item, how many kills since you pinned it, where it drops (your chance and kills, else
-- the classic database's chance; mobs it lists that you haven't met have no name: counted).
local function WishOnEnter(self)
	local wish = Bt.Wish(self.id)
	if not wish then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
	local r, g, b = Bt.QualityColor(wish[5])
	GameTooltip:SetText(("|T%s:16:16|t %s"):format(Bt.ItemIcon(self.id), wish[4] or Bt.ItemName(self.id)), r, g, b)
	Bt.AddWish(GameTooltip, wish)
	local sources, unnamed = Bt.WishSources(self.id)
	for i = 1, math.min(#sources, WISH_SOURCES) do
		local source = sources[i]
		GameTooltip:AddDoubleLine(source.name, source.out and ("%s |cff888888(%d)|r"):format(Bt.Percent(source.chance), source.out)
			or ("%s |cff888888%s|r"):format(Bt.Percent(source.chance), L["classic database"]), 1, 1, 1, 1, 1, 1)
	end
	local more = unnamed + math.max(0, #sources - WISH_SOURCES)
	if #sources == 0 and unnamed == 0 then
		GameTooltip:AddLine(L["No mob known to drop it yet."], 0.6, 0.6, 0.6)
	elseif more > 0 then
		GameTooltip:AddLine((more == unnamed and L["and %d more in the classic database"] or L["and %d more"]):format(more), 0.6, 0.6, 0.6)
	end
	GameTooltip:AddLine(L["Click: search for it"], 0.6, 0.6, 0.6)
	GameTooltip:AddLine(L["Shift-click: link it in chat"], 0.6, 0.6, 0.6)
	GameTooltip:AddLine(L["Alt-click: off your wish list"], 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

-- Click: search for it; Alt-click: off the list; Shift-click: link it.
local function WishOnClick(self)
	if IsAltKeyDown() then
		GameTooltip:Hide()
		Bt.ToggleWish(self.id)
	elseif IsShiftKeyDown() or IsControlKeyDown() then
		local link = C_Item and select(2, C_Item.GetItemInfo(("item:%d"):format(self.id)))
		if link then
			HandleModifiedItemClick(link)
		end
	else
		local wish = Bt.Wish(self.id)
		ledger.Search:SetText(wish and wish[4] or Bt.ItemName(self.id)) -- (searches: OnTextChanged)
		ledger.Search:ClearFocus()
	end
end

local function NewWish()
	local button = CreateFrame("Button", nil, ledger)
	button:SetSize(WISH_ICON, WISH_ICON)
	button.Edge = button:CreateTexture(nil, "BACKGROUND")
	button.Edge:SetAllPoints()
	button.Icon = button:CreateTexture(nil, "ARTWORK")
	button.Icon:SetPoint("TOPLEFT", 1, -1)
	button.Icon:SetPoint("BOTTOMRIGHT", -1, 1)
	button.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button:SetScript("OnEnter", WishOnEnter)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetScript("OnClick", WishOnClick)
	return button
end

-- The strip: the wishes, the first pinned leftmost, right-aligned; empty: how to pin one.
local function DrawWishes()
	local wishes, ids = Bt.Wishes(), {}
	for id in pairs(wishes) do
		ids[#ids + 1] = id
	end
	table.sort(ids, function(a, b)
		if wishes[a][1] ~= wishes[b][1] then
			return wishes[a][1] < wishes[b][1]
		end
		return a < b
	end)
	local shown = math.min(#ids, WISHES)
	for i = 1, math.max(#ledger.wishes, shown) do
		local button = ledger.wishes[i]
		if i <= shown then
			button = button or NewWish()
			ledger.wishes[i] = button
			button.id = ids[i]
			button:ClearAllPoints()
			button:SetPoint("TOPRIGHT", ledger, "TOPRIGHT", -PAD - (shown - i) * (WISH_ICON + WISH_GAP), -WISH_TOP)
			button.Icon:SetTexture(Bt.ItemIcon(ids[i]))
			local r, g, b = Bt.QualityColor(wishes[ids[i]][5])
			button.Edge:SetColorTexture(r, g, b, 0.9)
			button:Show()
		elseif button then
			button:Hide()
		end
	end
	ledger.WishLabel:ClearAllPoints()
	if shown > 0 then
		ledger.WishLabel:SetPoint("RIGHT", ledger.wishes[1], "LEFT", -6, 0)
		ledger.WishLabel:SetText(("|T%s:12:12|t "):format(Bt.STAR) .. L["Wish list"] .. (#ids > shown and ("  +" .. (#ids - shown)) or ""))
	else
		ledger.WishLabel:SetPoint("TOPRIGHT", ledger, "TOPRIGHT", -PAD, -WISH_TOP - 4)
		ledger.WishLabel:SetText(L["Wish list: Alt-click a drop to pin it"])
	end
end

---------------------------------------------------------------------------
-- Drawing it all
---------------------------------------------------------------------------

function Bt.DrawLedger()
	if not (ledger and ledger:IsShown()) then
		return
	end
	local mobs, kills, items, coin, rarest = Totals()
	ledger.Summary:SetText(L["%d mobs  ·  %d kills  ·  %d items  ·  %s coin, %s per kill"]:format(mobs, kills, items, Bt.Coins(coin),
		Bt.Coins(kills > 0 and coin / kills or 0)))
	if rarest then
		ledger.Rarest:SetText(L["Rarest find: %s, %s from %s"]:format(("|T%s:14:14|t %s"):format(Bt.ItemIcon(rarest.id),
			NameOf(rarest.id, rarest.item) or "?"), Bt.Percent(rarest.chance), rarest.mob.name or ("#" .. rarest.creature)))
	else
		ledger.Rarest:SetText("")
	end
	DrawWishes()
	Collect()
	if not selected or not Bt.Mob(selected) or (query ~= "" and entries[1] and not ledger.keepPick) then
		selected = entries[1] and entries[1].creature or selected
	end
	local rows = ledger.rows
	for i, entry in ipairs(entries) do
		rows[i] = rows[i] or NewRow(ledger.ListContent)
		rows[i]:ClearAllPoints()
		rows[i]:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
		FillRow(rows[i], entry)
	end
	for i = #entries + 1, #rows do
		rows[i]:Hide()
	end
	ledger.ListContent:SetHeight(math.max(1, #entries * ROW_H))
	ledger.NoMatch:SetShown(#entries == 0)
	ledger.NoMatch:SetText(query ~= "" and L["Nothing found."] or L["No mobs yet: kill something on your own and loot it."])
	DrawPicked()
end

local function Search(text)
	query = (text or ""):lower():gsub("%s", "")
	ledger.keepPick = false
	ledger.Placeholder:SetShown(text == nil or text == "")
	ledger.Clear:SetShown(text ~= nil and text ~= "")
	ledger.List:SetVerticalScroll(0)
	Bt.DrawLedger()
end

---------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------

local SORT_LABELS = { kills = L["Most kills"], name = L["Name"], level = L["Level"], coin = L["Coin per kill"], worth = L["Worth per kill"],
	xp = L["XP per kill"], xph = L["XP per hour"], last = L["Last killed"] }

local function Build()
	ledger = CreateFrame("Frame", "LefthyToolsBestiaryLedger", UIParent)
	ledger:SetSize(WIDTH, HEIGHT)
	ledger:SetPoint("CENTER")
	ledger:SetFrameStrata("HIGH")
	ledger:SetToplevel(true)
	ledger:SetClampedToScreen(true)
	ledger:EnableMouse(true)
	ledger:SetMovable(true)
	ledger:RegisterForDrag("LeftButton")
	ledger:SetScript("OnDragStart", ledger.StartMoving)
	ledger:SetScript("OnDragStop", ledger.StopMovingOrSizing)
	ledger:Hide()
	Bt.Dress(ledger)
	table.insert(UISpecialFrames, "LefthyToolsBestiaryLedger") -- (Escape closes it)
	LT.Window.Register("LefthyToolsBestiaryLedger")
	ledger.rows = {}

	ledger.Close = CreateFrame("Button", nil, ledger, "UIPanelCloseButtonNoScripts")
	ledger.Close:SetPoint("TOPRIGHT", -2, -2)
	ledger.Close:SetScript("OnClick", function() ledger:Hide() end)
	local title = ledger:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", PAD + 2, -12)
	title:SetText("Bestiary")
	local subtitle = ledger:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	subtitle:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 1)
	subtitle:SetText(L["the ledger"])
	ledger.Summary = ledger:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	ledger.Summary:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	ledger.Rarest = ledger:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	ledger.Rarest:SetPoint("TOPLEFT", ledger.Summary, "BOTTOMLEFT", 0, -4)
	-- The wish list: a strip of icons at the top right (DrawWishes).
	ledger.WishLabel = ledger:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	ledger.wishes = {}

	-- The search: a box with a magnifier, a grey hint while empty, an x to clear it.
	local box = CreateFrame("EditBox", "LefthyToolsBestiarySearch", ledger)
	ledger.Search = box
	box:SetSize(LIST_W - 26, 22)
	box:SetPoint("TOPLEFT", PAD, -74)
	box:SetAutoFocus(false)
	box:SetFontObject("ChatFontNormal")
	box:SetMaxLetters(40)
	if box.SetTextInsets then
		box:SetTextInsets(22, 20, 0, 0)
	end
	local back = box:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.55)
	local edge = box:CreateTexture(nil, "BORDER")
	edge:SetPoint("BOTTOMLEFT")
	edge:SetPoint("BOTTOMRIGHT")
	edge:SetHeight(1)
	edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.5)
	local glass = box:CreateTexture(nil, "OVERLAY")
	glass:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
	glass:SetSize(14, 14)
	glass:SetPoint("LEFT", 5, -1)
	ledger.Placeholder = box:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	ledger.Placeholder:SetPoint("LEFT", 24, 0)
	ledger.Placeholder:SetText(L["Search mobs and items"])
	ledger.Clear = CreateFrame("Button", nil, box, "UIPanelCloseButtonNoScripts")
	ledger.Clear:SetSize(20, 20)
	ledger.Clear:SetPoint("RIGHT", 0, 0)
	ledger.Clear:SetScript("OnClick", function() box:SetText("") Search("") end)
	ledger.Clear:Hide()
	box:SetScript("OnTextChanged", function(self) Search(self:GetText()) end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

	-- The order: a picker of our own (Core/Window.lua).
	local sortLabel = ledger:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sortLabel:SetPoint("LEFT", box, "RIGHT", 18, 0)
	sortLabel:SetText(L["Sort:"])
	ledger.Sort = LT.Window.AddPicker(ledger, 130, function()
		local list = {}
		for _, key in ipairs(SORTS) do
			list[#list + 1] = { text = SORT_LABELS[key], value = key, selected = key == sortBy }
		end
		return list
	end, function(key)
		sortBy = key
		ledger.Sort:SetLabel(SORT_LABELS[key])
		Bt.DrawLedger()
	end)
	ledger.Sort:SetPoint("LEFT", sortLabel, "RIGHT", 6, 0)
	ledger.Sort:SetLabel(SORT_LABELS[sortBy])

	-- The list, scrolling.
	ledger.List = CreateFrame("ScrollFrame", nil, ledger, "UIPanelScrollFrameTemplate")
	ledger.List:SetPoint("TOPLEFT", PAD, -TOP)
	ledger.List:SetPoint("BOTTOMLEFT", PAD, PAD)
	ledger.List:SetWidth(LIST_W - 24)
	ledger.ListContent = CreateFrame("Frame", nil, ledger.List)
	ledger.ListContent:SetSize(LIST_W - 26, 1)
	ledger.List:SetScrollChild(ledger.ListContent)
	ledger.NoMatch = ledger:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	ledger.NoMatch:SetPoint("TOPLEFT", PAD + 4, -TOP - 8)
	ledger.NoMatch:SetWidth(LIST_W - 30)
	ledger.NoMatch:SetJustifyH("LEFT")
	local split = ledger:CreateTexture(nil, "ARTWORK")
	split:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.2)
	split:SetWidth(1)
	split:SetPoint("TOPLEFT", PAD + LIST_W, -TOP + 4)
	split:SetPoint("BOTTOMLEFT", PAD + LIST_W, PAD)

	-- The picked mob: its model turning slowly, its numbers, beside them the map of where you killed
	-- it, all its drops under them.
	local x = PAD + LIST_W + 14
	local pane = CreateFrame("Frame", nil, ledger)
	ledger.Pane = pane
	pane:SetPoint("TOPLEFT", x, -TOP)
	pane:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	local details = CreateFrame("Frame", nil, pane) -- (the column its texts end at)
	details:SetPoint("TOPLEFT")
	details:SetSize(DETAILS_W, UPPER)
	local modelBack = pane:CreateTexture(nil, "BACKGROUND")
	modelBack:SetPoint("TOPLEFT")
	modelBack:SetSize(MODEL_W, MODEL_H)
	modelBack:SetColorTexture(0, 0, 0, 0.45)
	pane.Model = CreateFrame("PlayerModel", nil, pane)
	pane.Model:SetAllPoints(modelBack)
	pane.Model:SetPortraitZoom(0)
	pane.Model:SetScript("OnModelLoaded", function(self) self:RefreshCamera() end)
	pane.Name = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	pane.Name:SetPoint("TOPLEFT", modelBack, "TOPRIGHT", 12, -2)
	pane.Name:SetPoint("RIGHT", details, "RIGHT", 0, 0)
	pane.Name:SetJustifyH("LEFT")
	pane.Name:SetWordWrap(false)
	pane.Kind = pane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	pane.Kind:SetPoint("TOPLEFT", pane.Name, "BOTTOMLEFT", 0, -3)
	pane.Stats = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pane.Stats:SetPoint("TOPLEFT", pane.Kind, "BOTTOMLEFT", 0, -8)
	pane.Stats:SetPoint("RIGHT", details, "RIGHT", 0, 0)
	pane.Stats:SetJustifyH("LEFT")
	pane.Stats:SetSpacing(3)
	-- What a kill of it pays (its worth, XP and time per kill, XP per hour of fighting), under the
	-- model, as wide as the details.
	pane.ModelBack = modelBack
	pane.Pace = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pane.Pace:SetPoint("TOPLEFT", modelBack, "BOTTOMLEFT", 0, -8)
	pane.Pace:SetPoint("RIGHT", details, "RIGHT", 0, 0)
	pane.Pace:SetJustifyH("LEFT")
	pane.Pace:SetSpacing(3)
	-- Beside the details, where you killed it (Where): a heading with the zone's name or a picker of
	-- its zones (ours, like the sort's), the map's box (a dark back under the art and what you've
	-- explored of it, the dots on top; none known: a quiet line), a line under it.
	local where = { tiles = {}, overlays = {}, dots = {} }
	where.Box = CreateFrame("Frame", nil, pane)
	where.Box:SetPoint("TOPLEFT", DETAILS_W + MAP_GAP, -(MAP_HEAD + 4))
	where.Box:SetSize(MAP_W, MAP_H)
	local mapBack = where.Box:CreateTexture(nil, "BACKGROUND")
	mapBack:SetAllPoints()
	mapBack:SetColorTexture(0, 0, 0, 0.45)
	where.Map = CreateFrame("Frame", nil, where.Box)
	where.Map:SetPoint("CENTER")
	where.Map:SetSize(MAP_W, MAP_H)
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
		Where(where, Bt.Mob(selected))
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
	pane.where = where
	-- Its drops under all that, the pane wide, scrolling: its own, what the classic database says it
	-- drops that you haven't had yet (faded), then its world drops (random gear from anywhere), each a
	-- section of its own and each drop with its item tooltip.
	pane.Scroll = CreateFrame("ScrollFrame", nil, pane, "UIPanelScrollFrameTemplate")
	pane.Scroll:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -(UPPER + 10))
	pane.Scroll:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -24, 0)
	pane.Drops = CreateFrame("Frame", nil, pane.Scroll)
	pane.Drops:SetSize(DROPS_W, 10)
	pane.Scroll:SetScrollChild(pane.Drops)
	pane.sections = {}
	for _, key in ipairs({ "own", "unseen", "world" }) do
		local section = { cells = {} }
		section.Heading = pane.Drops:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		section.Rule = pane.Drops:CreateTexture(nil, "ARTWORK")
		section.Rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
		section.Rule:SetHeight(1)
		section.Rule:SetPoint("LEFT", section.Heading, "RIGHT", 8, 0)
		section.Rule:SetPoint("RIGHT", pane.Drops, "RIGHT", 0, 0)
		section.Grid = CreateFrame("Frame", nil, pane.Drops)
		section.Grid:SetSize(DROPS_W, 10)
		pane.sections[key] = section
	end
	ledger.Empty = ledger:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	ledger.Empty:SetPoint("CENTER", pane, "CENTER", 0, 0)
	ledger.Empty:SetText(L["Pick a mob on the left."])

	-- The model turns slowly while the ledger is open (an OnUpdate only then).
	ledger:SetScript("OnUpdate", function(_, elapsed)
		if pane:IsShown() and pane.facing then
			pane.facing = pane.facing + elapsed * 0.35
			pane.Model:SetFacing(pane.facing)
		end
	end)
	ledger:SetScript("OnEvent", function()
		where.mapID = nil -- (MAP_EXPLORATION_UPDATED: you've explored more, the map is laid again when next drawn)
	end)
	ledger:RegisterEvent("MAP_EXPLORATION_UPDATED") -- (rare, and only a flag: also while closed)
	ledger:SetScript("OnHide", function(self)
		self.Search:ClearFocus()
	end)
end

-- Opens the ledger (on a creature, with a search), or closes it when it's open and nothing's asked.
function Bt.ToggleLedger(creature, search)
	if not M.enabled then
		return
	end
	if not ledger then
		Build()
	end
	if ledger:IsShown() and not creature and not search then
		ledger:Hide()
		return
	end
	if creature and Bt.Mob(creature) then
		selected = creature
	end
	ledger:Show()
	ledger.Search:SetText(search or "")
	query = (search or ""):lower():gsub("%s", "")
	ledger.keepPick = creature ~= nil and not search
	ledger.Placeholder:SetShown(query == "")
	ledger.Clear:SetShown(query ~= "")
	Bt.DrawLedger()
end

Bt.OnChanged(function()
	Bt.DrawLedger()
end)

-- For tests.
function Bt.Ledger()
	return ledger, entries, selected
end
