local _, ns = ...
local LT = ns.LT
local L = ns.L
local M = LT:GetModule("beacon")
local B = ns.Beacon

-- Map pings ("meet here"): Alt+click on the world map sends that spot to every friend with
-- Beacon (P2;<continent>;<north>;<west>;<uiMapID>, a world position like the state message, and
-- the zone for its name). Everyone's world map and minimap show a marker there for a minute:
-- the game's ping icon with a ripple in the sender's class colour. Receivers also get a chat line
-- (with the game's map pin link for the spot: a click puts your waypoint arrow there) and the map
-- ping sound. `/lefthy beacon ping` pings where you stand. Alt+click on your own marker (or
-- `/lefthy beacon ping clear`) takes it back before its minute is up, for everyone (G2).
--
-- The click is caught with a post-hook (HookScript) on the map's scroll container: Blizzard's
-- own click handling runs first and untouched. Mouse down, not up: on mouse up the map may zoom
-- into the zone under the cursor, and the spot is read before that.

local PING_TIME = 60     -- seconds a marker stays
local RIPPLE_TIME = 10   -- the ripple runs this long, then the marker just sits there
local FADE_TIME = 10     -- and fades out over its last seconds
local SEND_GAP = 1.5     -- my own pings at most this often
local EDGE_ALPHA = 0.6
local PIN_TEMPLATE = "LefthyToolsBeaconPingPinTemplate"
local MARKER_ATLAS = "Ping_Marker_Icon_NonThreat" -- the game's "look here" ping
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local MINIMAP_SIZE = 16

-- B.pings[gameAccountID or "me"] = { name, classFile, continent, north, west, mapID, at }
local pings = B.pings
local lastSent = -math.huge

local function ZoneName(mapID)
	local info = mapID and mapID > 0 and C_Map.GetMapInfo(mapID)
	return info and info.name or nil
end

local function PingSound()
	PlaySound(SOUNDKIT and SOUNDKIT.MAP_PING or 3175)
end

local function AddPing(key, name, classFile, continent, north, west, mapID)
	pings[key] = { name = name, classFile = classFile, continent = continent, north = north, west = west,
		mapID = mapID, at = GetTime() }
	B.pingsDirty, B.minimapDirty = true, true
end

-- A ping taken back (mine, or a friend's G2): gone from both maps on the next tick.
function B.RemovePing(key)
	if pings[key] then
		pings[key] = nil
		B.pingsDirty, B.minimapDirty = true, true
	end
end

-- Alt+click on my own marker, or /lefthy beacon ping clear: my ping goes, for everyone.
function B.ClearMyPing()
	if not pings.me then
		M:Print("you have no ping out.")
		return
	end
	B.RemovePing("me")
	B.QueueToPeers("G" .. B.VERSION)
	M:Print("ping taken back.")
end

---------------------------------------------------------------------------
-- Sending and receiving
---------------------------------------------------------------------------

function B.SendPing(continent, north, west, mapID)
	local now = GetTime()
	if now - lastSent < SEND_GAP then
		return
	end
	local count = 0
	for _ in pairs(B.peers) do
		count = count + 1
	end
	if count == 0 then
		M:Print("no friends with LefthyTools online to ping.")
		return
	end
	lastSent = now
	B.QueueToPeers(("P%s;%d;%.1f;%.1f;%d"):format(B.VERSION, continent, north, west, mapID or 0))
	local _, classFile = UnitClass("player")
	AddPing("me", UnitName("player"), classFile, continent, north, west, mapID)
	M:Print(("pinged %s for %d friend(s)."):format(ZoneName(mapID) or "a spot", count))
	PingSound()
end

-- A spot on a map (normalized x, y on uiMapID mapID).
function B.PingMapPosition(mapID, x, y)
	if not (mapID and x and y) then
		return
	end
	local continent, world = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
	if not continent or not world then
		M:Print("can't ping on this map.")
		return
	end
	-- The zone under the cursor (on a continent map), for the name friends see.
	local zone = C_Map.GetMapInfoAtPosition and C_Map.GetMapInfoAtPosition(mapID, x, y)
	local north, west = world:GetXY()
	B.SendPing(continent, north, west, zone and zone.mapID or mapID)
end

-- /lefthy beacon ping: where I stand.
function B.PingMe()
	if not M.db.pings then
		M:Print("map pings are off (Beacon settings).")
		return
	end
	local continent, north, west = B.MyWorldPosition()
	if not continent then
		M:Print("can't ping here (no map position in dungeons and raids).")
		return
	end
	B.SendPing(continent, north, west, C_Map.GetBestMapForUnit("player"))
end

-- The game's map pin link for that spot on the zone map (a click sets your waypoint arrow there
-- and opens the map), or nil where the game has no pins.
local function PinLink(continent, north, west, mapID)
	if not (mapID and mapID > 0) or (C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(mapID)) then
		return nil
	end
	local uiMapID, pos = C_Map.GetMapPosFromWorldPos(continent, CreateVector2D(north, west), mapID)
	local x, y
	if uiMapID == mapID and pos then
		x, y = pos:GetXY()
	end
	if not x or x < 0 or x > 1 or y < 0 or y > 1 then
		return nil
	end
	return ("|cffffff00|Hworldmap:%d:%d:%d|h[%s]|h|r"):format(mapID, math.floor(x * 10000 + 0.5), math.floor(y * 10000 + 0.5),
		MAP_PIN_HYPERLINK or L["Map pin"])
end

-- A friend's P message, on the driver tick.
function B.ReceivePing(peer, gameAccountID, continent, north, west, mapID)
	AddPing(gameAccountID, peer.name, peer.classFile, continent, north, west, mapID)
	local pin = PinLink(continent, north, west, mapID)
	M:Print(("%s%s|r pinged a spot%s: see your map.%s"):format(LT.Window.ClassColorCode(peer.classFile), peer.name,
		ZoneName(mapID) and (" in " .. ZoneName(mapID)) or "", pin and (" " .. pin) or ""))
	PingSound()
end

---------------------------------------------------------------------------
-- Look (world map and minimap)
---------------------------------------------------------------------------

local function BuildMarker(frame)
	frame.Ripple = frame:CreateTexture(nil, "ARTWORK")
	frame.Ripple:SetAllPoints()
	local mask = frame:CreateMaskTexture()
	mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(frame.Ripple)
	frame.Ripple:AddMaskTexture(mask)
	frame.RippleAnim = frame.Ripple:CreateAnimationGroup()
	local grow = frame.RippleAnim:CreateAnimation("Scale")
	grow:SetScaleFrom(0.4, 0.4)
	grow:SetScaleTo(2.4, 2.4)
	grow:SetDuration(1.2)
	local fade = frame.RippleAnim:CreateAnimation("Alpha")
	fade:SetFromAlpha(0.9)
	fade:SetToAlpha(0)
	fade:SetDuration(1.2)
	frame.RippleAnim:SetLooping("REPEAT")

	frame.Icon = frame:CreateTexture(nil, "OVERLAY")
	frame.Icon:SetAllPoints()
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(MARKER_ATLAS) then
		frame.Icon:SetAtlas(MARKER_ATLAS)
	else
		frame.Icon:SetTexture(ROUND_MASK) -- a plain round marker in the sender's colour
		frame.iconTinted = true
	end
end

-- Colour, ripple and fade for the ping's age; fadeBase is the frame's alpha before fading.
local function StyleMarker(frame, ping, now, fadeBase)
	local r, g, b = B.ClassColor(ping.classFile)
	frame.Ripple:SetColorTexture(r, g, b, 1)
	if frame.iconTinted then
		frame.Icon:SetVertexColor(r, g, b)
	end
	local age = now - ping.at
	if age < RIPPLE_TIME then
		if not frame.RippleAnim:IsPlaying() then
			frame.RippleAnim:Play()
		end
	elseif frame.RippleAnim:IsPlaying() then
		frame.RippleAnim:Stop()
		frame.Ripple:Hide()
	end
	frame.Ripple:SetShown(age < RIPPLE_TIME)
	frame:SetAlpha(fadeBase * math.min(1, (PING_TIME - age) / FADE_TIME))
end

local function ShowPingTooltip(owner, ping)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(ping.name or "?", B.ClassColor(ping.classFile))
	GameTooltip:AddLine(L["Map ping, %d s ago"]:format(math.floor(GetTime() - ping.at)), 1, 1, 1)
	if ZoneName(ping.mapID) then
		GameTooltip:AddLine(ZoneName(ping.mapID), 1, 1, 1)
	end
	local distance = B.DistanceText(ping.continent, ping.north, ping.west)
	if distance then
		GameTooltip:AddLine(distance, 0.75, 0.75, 0.75)
	end
	if owner.key == "me" then
		GameTooltip:AddLine(L["Alt+click it on the world map to take it back."], 0.5, 0.8, 1)
	end
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- World map
---------------------------------------------------------------------------

LefthyToolsBeaconPingPinMixin = CreateFromMixins(MapCanvasPinMixin)

function LefthyToolsBeaconPingPinMixin:OnLoad()
	self:UseFrameLevelType("PIN_FRAME_LEVEL_VEHICLE_ABOVE_GROUP_MEMBER")
	self:SetScalingLimits(1, 1.0, 1.2)
	BuildMarker(self)
end

function LefthyToolsBeaconPingPinMixin:OnAcquired(key)
	self.key = key
end

function LefthyToolsBeaconPingPinMixin:OnMouseEnter()
	local ping = pings[self.key]
	if ping then
		ShowPingTooltip(self, ping)
	end
end

function LefthyToolsBeaconPingPinMixin:OnMouseLeave()
	GameTooltip:Hide()
end

-- See LefthyToolsBeaconPinMixin: the base version calls a protected function.
function LefthyToolsBeaconPingPinMixin:CheckMouseButtonPassthrough()
end

local provider = CreateFromMixins(MapCanvasDataProviderMixin)
local mapPins = {} -- key -> pin
local providerAdded, hooked = false, false
local vector = CreateVector2D(0, 0)

local function MapPosition(ping, mapID)
	vector:SetXY(ping.north, ping.west)
	local uiMapID, mapPos = C_Map.GetMapPosFromWorldPos(ping.continent, vector, mapID)
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
	local now = GetTime()
	for key, pin in pairs(mapPins) do
		local ping = M.enabled and pings[key]
		local x, y
		if ping and mapID then
			x, y = MapPosition(ping, mapID)
		end
		if x then
			pin:SetPosition(x, y)
			StyleMarker(pin, ping, now, 1)
		else
			map:RemovePin(pin)
			mapPins[key] = nil
		end
	end
	if not (M.enabled and mapID) then
		return
	end
	for key, ping in pairs(pings) do
		if not mapPins[key] then
			local x, y = MapPosition(ping, mapID)
			if x then
				local pin = map:AcquirePin(PIN_TEMPLATE, key)
				mapPins[key] = pin
				pin:SetPosition(x, y)
				StyleMarker(pin, ping, now, 1)
			end
		end
	end
end

function provider:OnMapChanged()
	self:RefreshAllData()
end

local function OnMapMouseDown(_, button)
	if button == "LeftButton" and IsAltKeyDown() and M.enabled and M.db.pings then
		local mine = mapPins.me
		if mine and mine:IsShown() and mine:IsMouseOver() then
			B.ClearMyPing() -- on my own marker: take it back
		else
			B.PingMapPosition(WorldMapFrame:GetMapID(), WorldMapFrame:GetNormalizedCursorPosition())
		end
	end
end

function B.AttachPings()
	if providerAdded then
		return
	end
	WorldMapFrame:AddDataProvider(provider)
	providerAdded = true
	if not hooked and WorldMapFrame.ScrollContainer then
		hooked = true -- a hook stays for good; it checks whether Beacon and pings are on
		WorldMapFrame.ScrollContainer:HookScript("OnMouseDown", OnMapMouseDown)
	end
end

function B.DetachPings()
	if providerAdded then
		WorldMapFrame:RemoveDataProvider(provider)
		providerAdded = false
	end
end

---------------------------------------------------------------------------
-- Minimap (placed by Dots.lua's minimap update, with the same view)
---------------------------------------------------------------------------

local minimapFrames, spareFrames = {}, {}

local function MinimapOnEnter(self)
	local ping = pings[self.key]
	if ping then
		ShowPingTooltip(self, ping)
	end
end

local function ReleaseMinimapPing(key)
	local frame = minimapFrames[key]
	minimapFrames[key] = nil
	if GameTooltip:IsOwned(frame) then
		GameTooltip:Hide()
	end
	frame.RippleAnim:Stop()
	frame:Hide()
	spareFrames[#spareFrames + 1] = frame
end

function B.ReleaseMinimapPings()
	for key in pairs(minimapFrames) do
		ReleaseMinimapPing(key)
	end
end

function B.PlaceMinimapPings(continent)
	local now = GetTime()
	for key, ping in pairs(pings) do
		local x, y, edge
		if ping.continent == continent then
			x, y, edge = B.MinimapOffset(ping.north, ping.west)
		end
		if x then
			local frame = minimapFrames[key]
			if not frame then
				frame = table.remove(spareFrames)
				if not frame then
					frame = CreateFrame("Frame", nil, Minimap)
					frame:SetSize(MINIMAP_SIZE, MINIMAP_SIZE)
					BuildMarker(frame)
					frame:SetMouseMotionEnabled(true)
					frame:SetMouseClickEnabled(false)
					frame:SetScript("OnEnter", MinimapOnEnter)
					frame:SetScript("OnLeave", GameTooltip_Hide or function() GameTooltip:Hide() end)
				end
				frame:SetFrameLevel(Minimap:GetFrameLevel() + 6)
				frame.key = key
				frame:Show()
				minimapFrames[key] = frame
			end
			frame:ClearAllPoints()
			frame:SetPoint("CENTER", Minimap, "CENTER", x, y)
			frame.edgeAlpha = edge and EDGE_ALPHA or 1
			StyleMarker(frame, ping, now, frame.edgeAlpha)
		elseif minimapFrames[key] then
			ReleaseMinimapPing(key)
		end
	end
	for key in pairs(minimapFrames) do
		if not pings[key] then
			ReleaseMinimapPing(key)
		end
	end
end

---------------------------------------------------------------------------
-- Driver tick (Beacon.lua): expire old pings, fade the markers, redraw the open map on changes.
---------------------------------------------------------------------------

function B.UpdatePings(now)
	if not next(pings) and not B.pingsDirty then
		return
	end
	for key, ping in pairs(pings) do
		if now - ping.at >= PING_TIME then
			pings[key] = nil
			B.pingsDirty, B.minimapDirty = true, true
		end
	end
	for key, frame in pairs(minimapFrames) do
		local ping = pings[key]
		if ping then
			StyleMarker(frame, ping, now, frame.edgeAlpha or 1)
		end
	end
	if providerAdded and WorldMapFrame:IsShown() then
		if B.pingsDirty then
			provider:RefreshAllData()
		else
			for key, pin in pairs(mapPins) do
				if pings[key] then
					StyleMarker(pin, pings[key], now, 1)
				end
			end
		end
	end
	B.pingsDirty = false
end

-- For tests.
function B.GetMinimapPings()
	return minimapFrames
end
