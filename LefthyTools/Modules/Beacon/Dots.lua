local _, ns = ...
local LT = ns.LT
local L = ns.L
local M = LT:GetModule("beacon")
local B = ns.Beacon

-- Friends' dots: one look for the world map and the minimap, and the tooltip on hover.
--
-- World map: pins of a map data provider (the official MapCanvas extension point; the map runs
-- every provider call through secureexecuterange, so it can't taint Blizzard's map code).
-- Pins are updated in place, so a hovered dot keeps its tooltip while it moves.
--
-- Minimap: plain frames on Minimap, placed relative to my own world position (same maths as
-- HereBeDragons-Pins: yards to pixels via C_Minimap.GetViewRadius, rotated by the facing when
-- "Rotate Minimap" is on). They are only repositioned when something moved: me, a gliding dot,
-- the zoom or the rotation. Standing still with friends standing still costs a few cheap calls
-- per frame and no drawing.

local PIN_TEMPLATE = "LefthyToolsBeaconPinTemplate"
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local PIN_SIZE = 14 -- the world map pin's size (LefthyToolsBeaconPinTemplate in Beacon.xml)
local MINIMAP_DOT_SIZE = 10
local EDGE_INSET = 5   -- pixels between an edge dot's centre and the minimap border
local EDGE_ALPHA = 0.6
local BNET_BLUE_R, BNET_BLUE_G, BNET_BLUE_B = 0.51, 0.773, 1
local STATUS_R, STATUS_G, STATUS_B = 1, 0.3, 0.3
local GROUP_R, GROUP_G, GROUP_B = 0.3, 0.65, 1 -- ring and tooltip line for friends in my group
local atan2 = math.atan2 or math.atan

---------------------------------------------------------------------------
-- Look
---------------------------------------------------------------------------

local function BuildDot(frame)
	-- A dark ring with the class-coloured dot inside, both made round by the portrait mask.
	frame.Ring = frame:CreateTexture(nil, "ARTWORK")
	frame.Ring:SetAllPoints()
	frame.Dot = frame:CreateTexture(nil, "OVERLAY")
	frame.Dot:SetPoint("TOPLEFT", 2, -2)
	frame.Dot:SetPoint("BOTTOMRIGHT", -2, 2)
	for _, texture in ipairs({ frame.Ring, frame.Dot }) do
		local mask = frame:CreateMaskTexture()
		mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(texture)
		texture:AddMaskTexture(mask)
	end
	-- Dead or a ghost: a skull instead of the dot.
	frame.Skull = frame:CreateTexture(nil, "OVERLAY", nil, 1)
	frame.Skull:SetPoint("TOPLEFT", -2, 2)
	frame.Skull:SetPoint("BOTTOMRIGHT", 2, -2)
	frame.Skull:SetTexture(SKULL)
	frame.Skull:Hide()
	-- In combat: the ring turns red and pulses.
	frame.Pulse = frame.Ring:CreateAnimationGroup()
	local fade = frame.Pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.25)
	fade:SetDuration(0.5)
	frame.Pulse:SetLooping("BOUNCE")
	-- In combat: how many enemies are on them.
	frame.Count = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	frame.Count:SetPoint("CENTER", frame, "BOTTOMRIGHT", 1, 1)
	frame.Count:Hide()
end

local function StyleDot(frame, peer)
	local dead = peer.dead or peer.ghost
	frame.Skull:SetShown(dead)
	frame.Skull:SetAlpha(peer.ghost and 0.6 or 1)
	frame.Ring:SetShown(not dead)
	frame.Dot:SetShown(not dead)
	frame.Dot:SetColorTexture(B.ClassColor(peer.classFile))
	local mobs = peer.combat and not dead and peer.mobs or 0
	frame.Count:SetText(mobs > 0 and tostring(mobs) or "")
	frame.Count:SetShown(mobs > 0)
	if peer.combat and not dead then
		frame.Ring:SetColorTexture(1, 0.15, 0.1, 1)
		if not frame.Pulse:IsPlaying() then
			frame.Pulse:Play()
		end
	else
		frame.Pulse:Stop()
		if peer.groupUnit then
			frame.Ring:SetColorTexture(GROUP_R, GROUP_G, GROUP_B, 1) -- in my group: blue ring
		else
			frame.Ring:SetColorTexture(0, 0, 0, 0.85)
		end
	end
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------

local DIRECTIONS = { L["north"], L["north-east"], L["east"], L["south-east"], L["south"], L["south-west"], L["west"], L["north-west"] }

-- "240 yd north-east" from me to a world position, or nil when it's on another continent.
function B.DistanceText(theirContinent, theirNorth, theirWest)
	local continent, north, west = B.MyWorldPosition()
	if not continent or theirContinent ~= continent then
		return nil
	end
	local dNorth, dEast = theirNorth - north, west - theirWest
	local yards = math.sqrt(dNorth * dNorth + dEast * dEast)
	if yards < 5 then
		return L["Right next to you"]
	end
	local sector = math.floor(atan2(dEast, dNorth) / (math.pi / 4) + 0.5) % 8 + 1
	return L["%d yd %s"]:format(math.floor(yards / 5 + 0.5) * 5, DIRECTIONS[sector])
end

local function DistanceText(peer)
	return peer.hasPos and B.DistanceText(peer.continent, peer.north, peer.west) or nil
end

---------------------------------------------------------------------------
-- Dots on top of each other
--
-- Friends standing together would hide each other's dot, and only the top one could be hovered.
-- Dots whose centres are closer than OVERLAP x their size (measured in screen pixels, so it works
-- at any zoom) form a group: they're spread around the group's middle so every colour shows, and
-- hovering any of them shows all of them in one tooltip.
---------------------------------------------------------------------------

local OVERLAP = 0.8

-- Whether any two of items = { { x, y }, ... } (pixels) overlap; no tables made, for the per-frame
-- minimap update.
local function AnyOverlap(items, count, size)
	local limit = (size * OVERLAP) ^ 2
	for i = 1, count - 1 do
		for j = i + 1, count do
			local dx, dy = items[i].x - items[j].x, items[i].y - items[j].y
			if dx * dx + dy * dy < limit then
				return true
			end
		end
	end
	return false
end

-- items = { { key, x, y }, ... } in pixels. Sets item.dx, item.dy (pixels to move it) and
-- item.group (the keys of its group, nil when alone). Groups keep a fixed order (by key), so the
-- dots don't swap places from one update to the next.
function B.Spread(items, size)
	table.sort(items, function(a, b) return a.key < b.key end)
	local groups, limit = {}, (size * OVERLAP) ^ 2
	for _, item in ipairs(items) do
		item.dx, item.dy, item.group = 0, 0, nil
		local home
		for _, g in ipairs(groups) do
			local dx, dy = item.x - g[1].x, item.y - g[1].y
			if dx * dx + dy * dy < limit then
				home = g
				break
			end
		end
		if home then
			home[#home + 1] = item
		else
			groups[#groups + 1] = { item }
		end
	end
	for _, g in ipairs(groups) do
		local n = #g
		if n > 1 then
			local mx, my, keys = 0, 0, {}
			for i, item in ipairs(g) do
				mx, my, keys[i] = mx + item.x / n, my + item.y / n, item.key
			end
			local radius = size * (n == 2 and 0.4 or 0.55) -- two side by side, more in a small ring
			for i, item in ipairs(g) do
				local angle = math.pi + (i - 1) * 2 * math.pi / n -- the first one on the left
				item.dx = mx + math.cos(angle) * radius - item.x
				item.dy = my + math.sin(angle) * radius - item.y
				item.group = keys
			end
		end
	end
end

-- One friend's lines; the first friend's name is the tooltip title, the others' follow below.
local function AddPeer(peer, first)
	-- AFK/DND, level and zone straight from Battle.net, so they're current.
	local account = peer.guid and C_BattleNet.GetAccountInfoByGUID and C_BattleNet.GetAccountInfoByGUID(peer.guid)
	local game = account and account.gameAccountInfo
	local title = peer.name or "?"
	if game and game.isGameAFK then
		title = title .. " <AFK>"
	elseif game and game.isGameBusy then
		title = title .. " <DND>"
	end
	if first then
		GameTooltip:SetText(title, B.ClassColor(peer.classFile))
	else
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(title, B.ClassColor(peer.classFile))
	end
	local battleTag = account and account.battleTag and account.battleTag:match("^[^#]+")
	if battleTag then
		GameTooltip:AddLine(battleTag, BNET_BLUE_R, BNET_BLUE_G, BNET_BLUE_B)
	end
	if peer.groupUnit then
		GameTooltip:AddLine(L["In your group"], GROUP_R, GROUP_G, GROUP_B)
	end
	local level = game and game.characterLevel or peer.level
	if level and peer.xpPercent then
		GameTooltip:AddLine(L["Level %d (%d%%)"]:format(level, peer.xpPercent), 1, 1, 1) -- with their progress on it
	elseif level then
		GameTooltip:AddLine(L["Level %d"]:format(level), 1, 1, 1)
	end
	local area = game and game.areaName or peer.area
	local subzone = peer.subzone ~= "" and peer.subzone ~= area and peer.subzone or nil
	if area and subzone then
		GameTooltip:AddLine(area .. " - " .. subzone, 1, 1, 1)
	elseif area or subzone then
		GameTooltip:AddLine(area or subzone, 1, 1, 1)
	end
	if peer.ghost then
		GameTooltip:AddLine(L["Ghost"], STATUS_R, STATUS_G, STATUS_B)
	elseif peer.dead then
		GameTooltip:AddLine(L["Dead"], STATUS_R, STATUS_G, STATUS_B)
	end
	if peer.combat then
		local mobs, text = peer.mobs or 0, nil
		if peer.target ~= "" then
			text = mobs > 1 and L["Fighting %s and %d more"]:format(peer.target, mobs - 1) or L["Fighting %s"]:format(peer.target)
		elseif mobs > 1 then
			text = L["In combat with %d enemies"]:format(mobs)
		elseif mobs == 1 then
			text = L["In combat with 1 enemy"]
		else
			text = L["In combat"]
		end
		GameTooltip:AddLine(text, STATUS_R, STATUS_G, STATUS_B)
	end
	local quest = peer.quest
	if quest then
		GameTooltip:AddLine(L["Quest: %s"]:format(quest.title), 1, 0.82, 0)
		if quest.done then
			GameTooltip:AddLine("  " .. L["Ready to turn in"], 0.3, 1, 0.3)
		elseif quest.objective ~= "" then
			GameTooltip:AddLine("  " .. quest.objective, 0.85, 0.85, 0.85)
		end
		if C_QuestLog.GetLogIndexForQuestID(quest.id) then
			GameTooltip:AddLine("  " .. L["You have this quest too"], GROUP_R, GROUP_G, GROUP_B)
		end
	end
	local distance = DistanceText(peer)
	if distance then
		GameTooltip:AddLine(distance, 0.75, 0.75, 0.75)
	end
end

-- What the tooltip shows, as a string: changes when anyone in it changed.
local function Signature(peer, group)
	local sig = tostring(peer.rev)
	for _, key in ipairs(group or {}) do
		local other = B.peers[key]
		sig = sig .. "," .. key .. ":" .. (other and other.rev or "-")
	end
	return sig
end

-- The hovered friend first, then everyone whose dot is on top of theirs (group).
function B.ShowTooltip(owner, peer, group)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	AddPeer(peer, true)
	for _, key in ipairs(group or {}) do
		local other = B.peers[key]
		if other and other ~= peer and other.name then
			AddPeer(other, false)
		end
	end
	GameTooltip:Show()
	owner.tooltipSig = Signature(peer, group)
end

-- An open tooltip on this dot follows changes of anyone in it (cheap when nothing changed).
local function RefreshTooltip(frame, peer)
	if GameTooltip:IsOwned(frame) and Signature(peer, frame.group) ~= frame.tooltipSig then
		B.ShowTooltip(frame, peer, frame.group)
	end
end

-- Restyles a dot only when its friend's data changed (or the frame now shows someone else).
local function Restyle(frame, peer)
	if frame.styledPeer == peer and frame.styledRev == peer.rev then
		return
	end
	frame.styledPeer, frame.styledRev = peer, peer.rev
	StyleDot(frame, peer)
end

---------------------------------------------------------------------------
-- World map
---------------------------------------------------------------------------

LefthyToolsBeaconPinMixin = CreateFromMixins(MapCanvasPinMixin)

function LefthyToolsBeaconPinMixin:OnLoad()
	-- Just above Blizzard's group member dots, so a friend in my group shows our marked dot.
	self:UseFrameLevelType("PIN_FRAME_LEVEL_VEHICLE_ABOVE_GROUP_MEMBER")
	self:SetScalingLimits(1, 1.0, 1.2)
	BuildDot(self)
end

function LefthyToolsBeaconPinMixin:OnAcquired(gameAccountID)
	self.gameAccountID, self.styledPeer = gameAccountID, nil
end

function LefthyToolsBeaconPinMixin:OnMouseEnter()
	local peer = B.peers[self.gameAccountID]
	if peer then
		B.ShowTooltip(self, peer, self.group)
	end
end

function LefthyToolsBeaconPinMixin:OnMouseLeave()
	GameTooltip:Hide()
end

-- AcquirePin calls this on every acquire, and the base version uses SetPassThroughButtons,
-- which is protected: from addon code in combat it raises ADDON_ACTION_BLOCKED. Our pins don't
-- take clicks at all (enableMouseMotion only), so every click reaches the map anyway.
function LefthyToolsBeaconPinMixin:CheckMouseButtonPassthrough()
end

local provider = CreateFromMixins(MapCanvasDataProviderMixin)
local mapPins = {} -- gameAccountID -> pin on the open map
local providerAdded = false
local vector = CreateVector2D(0, 0) -- reused for every conversion

local function MapPosition(peer, mapID)
	-- In my group: the live position, the same one Blizzard's group dot uses, so ours sits exactly
	-- on top of it instead of trailing a few seconds behind.
	if peer.groupUnit then
		local pos = C_Map.GetPlayerMapPosition(mapID, peer.groupUnit)
		if pos then
			local x, y = pos:GetXY()
			if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
				return x, y
			end
		end
	end
	vector:SetXY(peer.north, peer.west)
	local uiMapID, mapPos = C_Map.GetMapPosFromWorldPos(peer.continent, vector, mapID)
	if uiMapID ~= mapID or not mapPos then
		return nil
	end
	local x, y = mapPos:GetXY()
	if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
		return x, y
	end
end

function provider:RemoveAllData()
	self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
	wipe(mapPins)
end

function provider:RefreshAllData()
	local map = self:GetMap()
	local mapID = map:GetMapID()
	local placed, wanted = {}, {}
	if M.enabled and M.db.showFriends and mapID then
		for gameAccountID, peer in pairs(B.peers) do
			if B.IsShown(peer) then
				local x, y = MapPosition(peer, mapID)
				if x then
					placed[#placed + 1] = { key = gameAccountID, peer = peer, nx = x, ny = y }
					wanted[gameAccountID] = true
				end
			end
		end
	end
	for gameAccountID, pin in pairs(mapPins) do
		if not wanted[gameAccountID] then
			map:RemovePin(pin)
			mapPins[gameAccountID] = nil
		end
	end
	if not placed[1] then
		return
	end
	-- Map units to screen pixels at the current zoom, to find dots that really overlap.
	local canvas = map:GetCanvas()
	local scale = canvas:GetEffectiveScale()
	local pxW, pxH = canvas:GetWidth() * scale, canvas:GetHeight() * scale
	for _, item in ipairs(placed) do
		item.pin = mapPins[item.key] or map:AcquirePin(PIN_TEMPLATE, item.key)
		mapPins[item.key] = item.pin
		item.x, item.y = item.nx * pxW, item.ny * pxH
	end
	B.Spread(placed, PIN_SIZE * placed[1].pin:GetEffectiveScale())
	for _, item in ipairs(placed) do
		local pin = item.pin
		pin.fanX, pin.fanY = pxW > 0 and item.dx / pxW or 0, pxH > 0 and item.dy / pxH or 0
		pin.group = item.group
		pin:SetPosition(item.nx + pin.fanX, item.ny + pin.fanY)
		Restyle(pin, item.peer)
		RefreshTooltip(pin, item.peer)
	end
end

function provider:OnMapChanged()
	self:RefreshAllData()
end

-- Zooming changes which dots overlap on screen.
function provider:OnCanvasScaleChanged()
	self:RefreshAllData()
end

---------------------------------------------------------------------------
-- Minimap
---------------------------------------------------------------------------

local minimapPins = {} -- gameAccountID -> frame
local sparePins = {}
local gliding = false
local drawn = {} -- what the minimap dots were last placed for
local placed = {} -- this update's dots: { key, peer, x, y, edge, dx, dy, group }, reused

local function MinimapPinOnEnter(self)
	local peer = B.peers[self.gameAccountID]
	if peer then
		B.ShowTooltip(self, peer, self.group)
	end
end

local function MinimapPinOnLeave()
	GameTooltip:Hide()
end

local function AcquireMinimapPin(gameAccountID)
	local pin = table.remove(sparePins)
	if not pin then
		pin = CreateFrame("Frame", nil, Minimap)
		pin:SetSize(MINIMAP_DOT_SIZE, MINIMAP_DOT_SIZE)
		BuildDot(pin)
		-- Hover shows the tooltip; clicks go through to the minimap (pings).
		pin:SetMouseMotionEnabled(true)
		pin:SetMouseClickEnabled(false)
		pin:SetScript("OnEnter", MinimapPinOnEnter)
		pin:SetScript("OnLeave", MinimapPinOnLeave)
	end
	pin:SetFrameLevel(Minimap:GetFrameLevel() + 5)
	pin.gameAccountID, pin.styledPeer, pin.x, pin.y, pin.edge = gameAccountID, nil, nil, nil, nil
	pin:Show()
	minimapPins[gameAccountID] = pin
	return pin
end

local function ReleaseMinimapPin(gameAccountID)
	local pin = minimapPins[gameAccountID]
	minimapPins[gameAccountID] = nil
	if GameTooltip:IsOwned(pin) then
		GameTooltip:Hide()
	end
	pin.Pulse:Stop()
	pin:Hide()
	sparePins[#sparePins + 1] = pin
end

local function ReleaseAllMinimapPins()
	for gameAccountID in pairs(minimapPins) do
		ReleaseMinimapPin(gameAccountID)
	end
end

-- Where a world position goes on the minimap: pixels from its centre, and whether it's clamped to
-- the edge; nil if it's out of range and far-away friends aren't kept at the edge.
local view = {}
function B.MinimapOffset(theirNorth, theirWest)
	local east, up = (view.west - theirWest) * view.scale, (theirNorth - view.north) * view.scale
	local x, y = east * view.cos + up * view.sin, up * view.cos - east * view.sin -- my facing points up
	local reach = view.square and math.max(math.abs(x), math.abs(y)) or math.sqrt(x * x + y * y)
	local edge = reach > view.limit
	if edge and M.db.minimapEdge then
		return x * view.limit / reach, y * view.limit / reach, true
	elseif edge then
		return nil
	end
	return x, y, false
end

-- The minimap's last spread. It only depends on where the dots are relative to each other, so
-- while that stays within a pixel (I walk, or friends walk together) it's reused instead of being
-- worked out, with its tables, every frame. key -> { rx, ry (relative to the lowest key), dx, dy,
-- group, stamp }.
local spreadCache, spreadCount, spreadStamp = {}, 0, 0

local function SpreadMinimap(items, count)
	local ref = items[1]
	for i = 2, count do
		if items[i].key < ref.key then
			ref = items[i]
		end
	end
	local hit = count == spreadCount
	for i = 1, count do
		local item = items[i]
		local c = spreadCache[item.key]
		if not (hit and c and math.abs(item.x - ref.x - c.rx) < 1 and math.abs(item.y - ref.y - c.ry) < 1) then
			hit = false
			break
		end
	end
	if hit then
		for i = 1, count do
			local item = items[i]
			local c = spreadCache[item.key]
			item.dx, item.dy, item.group = c.dx, c.dy, c.group
		end
		return
	end
	B.Spread(items, MINIMAP_DOT_SIZE)
	spreadStamp, spreadCount = spreadStamp + 1, count
	for i = 1, count do
		local item = items[i]
		local c = spreadCache[item.key] or {}
		spreadCache[item.key] = c
		c.rx, c.ry, c.dx, c.dy, c.group, c.stamp = item.x - ref.x, item.y - ref.y, item.dx, item.dy, item.group, spreadStamp
	end
	for key, c in pairs(spreadCache) do
		if c.stamp ~= spreadStamp then
			spreadCache[key] = nil
		end
	end
end

local function PlaceMinimapPins(now, continent, north, west, half, radius, facing)
	view.north, view.west, view.scale = north, west, half / radius
	view.sin, view.cos = math.sin(facing), math.cos(facing)
	view.square = GetMinimapShape and GetMinimapShape() == "SQUARE"
	view.limit = half - EDGE_INSET
	gliding = false
	local count = 0
	for gameAccountID, peer in pairs(B.peers) do
		local x, y, edge
		if B.IsShown(peer) and peer.continent == continent then
			local peerNorth, peerWest, moving = B.DrawnPosition(peer, now)
			if peer.groupUnit then
				-- In my group: live position, right on top of Blizzard's own blip; redraw every frame.
				local liveNorth, liveWest, _, liveContinent = UnitPosition(peer.groupUnit)
				if liveNorth and liveContinent == continent then
					peerNorth, peerWest, moving = liveNorth, liveWest, true
				end
			end
			gliding = gliding or moving
			x, y, edge = B.MinimapOffset(peerNorth, peerWest)
		end
		if x then
			count = count + 1
			local item = placed[count] or {} -- reused: this runs every frame while something moves
			placed[count] = item
			item.key, item.peer, item.x, item.y, item.edge = gameAccountID, peer, x, y, edge
			item.dx, item.dy, item.group = 0, 0, nil
		elseif minimapPins[gameAccountID] then
			ReleaseMinimapPin(gameAccountID)
		end
	end
	for i = count + 1, #placed do
		placed[i] = nil
	end
	if AnyOverlap(placed, count, MINIMAP_DOT_SIZE) then
		SpreadMinimap(placed, count) -- only when dots really overlap
	end
	for i = 1, count do
		local item = placed[i]
		local pin = minimapPins[item.key] or AcquireMinimapPin(item.key)
		local x, y = item.x + item.dx, item.y + item.dy
		if pin.x ~= x or pin.y ~= y then
			pin.x, pin.y = x, y
			pin:ClearAllPoints()
			pin:SetPoint("CENTER", Minimap, "CENTER", x, y)
		end
		if pin.edge ~= item.edge then
			pin.edge = item.edge
			pin:SetAlpha(item.edge and EDGE_ALPHA or 1)
		end
		pin.group = item.group
		Restyle(pin, item.peer)
		RefreshTooltip(pin, item.peer)
	end
	for gameAccountID in pairs(minimapPins) do
		if not B.peers[gameAccountID] then
			ReleaseMinimapPin(gameAccountID)
		end
	end
	if B.PlaceMinimapPings then
		B.PlaceMinimapPings(continent) -- Pings.lua, with the same view
	end
end

-- Called every frame by the driver; returns right away unless a dot has to move.
function B.UpdateMinimap(now)
	if not (M.db.showMinimap and Minimap and (next(B.peers) or next(B.pings))) then
		if next(minimapPins) then
			ReleaseAllMinimapPins()
		end
		if B.ReleaseMinimapPings then
			B.ReleaseMinimapPings()
		end
		return
	end
	if not Minimap:IsVisible() then
		B.minimapDirty = true -- redraw once it's back (Mirage may hide it)
		return
	end
	local continent, north, west = B.MyWorldPosition()
	local radius = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
	if not continent or not radius or radius <= 0 then
		if next(minimapPins) then
			ReleaseAllMinimapPins()
		end
		if B.ReleaseMinimapPings then
			B.ReleaseMinimapPings()
		end
		return
	end
	local half = Minimap:GetWidth() / 2
	local facing = GetCVarBool("rotateMinimap") and GetPlayerFacing() or 0
	if not (B.minimapDirty or gliding) and north == drawn.north and west == drawn.west and facing == drawn.facing
			and radius == drawn.radius and half == drawn.half then
		return
	end
	B.minimapDirty = false
	drawn.north, drawn.west, drawn.facing, drawn.radius, drawn.half = north, west, facing, radius, half
	PlaceMinimapPins(now, continent, north, west, half, radius, facing)
end

---------------------------------------------------------------------------
-- Hooks for Beacon.lua
---------------------------------------------------------------------------

-- Called every frame by the driver while friends are known: dots of friends in my group follow
-- their live position on the open world map, like Blizzard's group dot underneath.
function B.UpdateWorldMapGroupPins()
	if not (providerAdded and WorldMapFrame:IsShown() and next(mapPins)) then
		return
	end
	local mapID = WorldMapFrame:GetMapID()
	for gameAccountID, pin in pairs(mapPins) do
		local peer = B.peers[gameAccountID]
		local pos = peer and peer.groupUnit and mapID and C_Map.GetPlayerMapPosition(mapID, peer.groupUnit)
		if pos then
			local x, y = pos:GetXY()
			if x >= 0 and x <= 1 and y >= 0 and y <= 1 and (x ~= pin.liveX or y ~= pin.liveY) then
				pin.liveX, pin.liveY = x, y
				pin:SetPosition(x + (pin.fanX or 0), y + (pin.fanY or 0)) -- spread from a dot on top of it
			end
		end
	end
end

function B.RefreshMaps()
	if providerAdded and WorldMapFrame:IsShown() then
		provider:RefreshAllData()
	end
	B.minimapDirty = true
end

function B.Attach()
	if providerAdded or not M.enabled or not (WorldMapFrame and WorldMapFrame.AddDataProvider) then
		return
	end
	WorldMapFrame:AddDataProvider(provider)
	providerAdded = true
	if B.AttachPings then
		B.AttachPings()
	end
end

function B.Detach()
	if providerAdded and not M.enabled then
		WorldMapFrame:RemoveDataProvider(provider) -- removes the pins too
		providerAdded = false
		if B.DetachPings then
			B.DetachPings()
		end
	end
	ReleaseAllMinimapPins()
	if B.ReleaseMinimapPings then
		B.ReleaseMinimapPings()
	end
end

function B.handlers.ADDON_LOADED(name)
	if name == "Blizzard_WorldMap" then
		C_Timer.After(0, B.Attach)
	end
end

-- For tests and /lefthy beacon status.
function B.GetMinimapPins()
	return minimapPins
end
