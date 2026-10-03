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
end

local function StyleDot(frame, peer)
	local dead = peer.dead or peer.ghost
	frame.Skull:SetShown(dead)
	frame.Skull:SetAlpha(peer.ghost and 0.6 or 1)
	frame.Ring:SetShown(not dead)
	frame.Dot:SetShown(not dead)
	frame.Dot:SetColorTexture(B.ClassColor(peer.classFile))
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

function B.ShowTooltip(owner, peer)
	-- AFK/DND, level and zone straight from Battle.net, so they're current.
	local account = peer.guid and C_BattleNet.GetAccountInfoByGUID and C_BattleNet.GetAccountInfoByGUID(peer.guid)
	local game = account and account.gameAccountInfo
	local title = peer.name or "?"
	if game and game.isGameAFK then
		title = title .. " <AFK>"
	elseif game and game.isGameBusy then
		title = title .. " <DND>"
	end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(title, B.ClassColor(peer.classFile))
	local battleTag = account and account.battleTag and account.battleTag:match("^[^#]+")
	if battleTag then
		GameTooltip:AddLine(battleTag, BNET_BLUE_R, BNET_BLUE_G, BNET_BLUE_B)
	end
	if peer.groupUnit then
		GameTooltip:AddLine(L["In your group"], GROUP_R, GROUP_G, GROUP_B)
	end
	local level = game and game.characterLevel or peer.level
	if level then
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
		GameTooltip:AddLine(peer.target ~= "" and L["Fighting %s"]:format(peer.target) or L["In combat"],
			STATUS_R, STATUS_G, STATUS_B)
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
	GameTooltip:Show()
end

-- Restyles a dot only when its friend's data changed (or the frame now shows someone else).
local function Restyle(frame, peer)
	if frame.styledPeer == peer and frame.styledRev == peer.rev then
		return
	end
	frame.styledPeer, frame.styledRev = peer, peer.rev
	StyleDot(frame, peer)
	if GameTooltip:IsOwned(frame) then
		B.ShowTooltip(frame, peer)
	end
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
		B.ShowTooltip(self, peer)
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
	local show = M.enabled and M.db.showFriends and mapID
	for gameAccountID, pin in pairs(mapPins) do
		local peer = show and B.peers[gameAccountID]
		local x, y
		if peer and B.IsShown(peer) then
			x, y = MapPosition(peer, mapID)
		end
		if x then
			pin:SetPosition(x, y)
			Restyle(pin, peer)
		else
			map:RemovePin(pin)
			mapPins[gameAccountID] = nil
		end
	end
	if not show then
		return
	end
	for gameAccountID, peer in pairs(B.peers) do
		if not mapPins[gameAccountID] and B.IsShown(peer) then
			local x, y = MapPosition(peer, mapID)
			if x then
				local pin = map:AcquirePin(PIN_TEMPLATE, gameAccountID)
				mapPins[gameAccountID] = pin
				pin:SetPosition(x, y)
				Restyle(pin, peer)
			end
		end
	end
end

function provider:OnMapChanged()
	self:RefreshAllData()
end

---------------------------------------------------------------------------
-- Minimap
---------------------------------------------------------------------------

local minimapPins = {} -- gameAccountID -> frame
local sparePins = {}
local gliding = false
local drawn = {} -- what the minimap dots were last placed for

local function MinimapPinOnEnter(self)
	local peer = B.peers[self.gameAccountID]
	if peer then
		B.ShowTooltip(self, peer)
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

local function PlaceMinimapPins(now, continent, north, west, half, radius, facing)
	view.north, view.west, view.scale = north, west, half / radius
	view.sin, view.cos = math.sin(facing), math.cos(facing)
	view.square = GetMinimapShape and GetMinimapShape() == "SQUARE"
	view.limit = half - EDGE_INSET
	gliding = false
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
			local pin = minimapPins[gameAccountID] or AcquireMinimapPin(gameAccountID)
			if pin.x ~= x or pin.y ~= y then
				pin.x, pin.y = x, y
				pin:ClearAllPoints()
				pin:SetPoint("CENTER", Minimap, "CENTER", x, y)
			end
			if pin.edge ~= edge then
				pin.edge = edge
				pin:SetAlpha(edge and EDGE_ALPHA or 1)
			end
			Restyle(pin, peer)
		elseif minimapPins[gameAccountID] then
			ReleaseMinimapPin(gameAccountID)
		end
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
				pin:SetPosition(x, y)
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
