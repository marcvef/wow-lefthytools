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
-- The click is read from GLOBAL_MOUSE_DOWN, not from the map (Core/MapOverlay.lua): Blizzard's own
-- click handling stays untouched. Mouse down, not up: on mouse up the map may zoom into the zone
-- under the cursor, and the spot is read before that.

local PING_TIME = 60     -- seconds a marker stays
local RIPPLE_TIME = 10   -- the ripple runs this long, then the marker just sits there
local FADE_TIME = 10     -- and fades out over its last seconds
local SEND_GAP = 2.5     -- my own pings at most this often (friends take one per 2 s: Beacon's PING_GAP)
local EDGE_ALPHA = 0.6
local MARKER_ATLAS = "Ping_Marker_Icon_NonThreat" -- the game's "look here" ping
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local MINIMAP_SIZE = 16
local MAP_SIZE = 20 -- the world map marker's

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
		M:Print("not so fast: ping again in a moment.") -- (friends would drop it)
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
	AddPing("me", B.MyName(), classFile, continent, north, west, mapID)
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
	local continent, north, west = LT.Position()
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
	M:Print(("%s pinged a spot%s: see your map.%s"):format(B.ColouredName(peer.name, peer.classFile),
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

-- tip: GameTooltip (the mouse), or the world map's own for the controller's map cursor.
local function ShowPingTooltip(owner, ping, tip)
	tip = tip or GameTooltip
	tip:SetOwner(owner, "ANCHOR_RIGHT")
	tip:SetText(ping.name or "?", B.ClassColor(ping.classFile))
	tip:AddLine(L["Map ping, %d s ago"]:format(math.floor(GetTime() - ping.at)), 1, 1, 1)
	if ZoneName(ping.mapID) then
		tip:AddLine(ZoneName(ping.mapID), 1, 1, 1)
	end
	local distance = B.DistanceText(ping.continent, ping.north, ping.west)
	if distance then
		tip:AddLine(distance, 0.75, 0.75, 0.75)
	end
	if owner.key == "me" then
		tip:AddLine(L["Alt+click it on the world map to take it back."], 0.5, 0.8, 1)
	end
	tip:Show()
end

---------------------------------------------------------------------------
-- World map: markers of our own on the map's canvas (Core/MapOverlay.lua), hover only, like
-- Dots.lua's dots.
---------------------------------------------------------------------------

local Overlay = LT.MapOverlay
local MARKER_LEVEL = "PIN_FRAME_LEVEL_VEHICLE_ABOVE_GROUP_MEMBER"
local SCALE_FROM, SCALE_TO = 1.0, 1.2 -- as a map pin with SetScalingLimits(1, 1.0, 1.2)
local mapPins, spareMapPins = {}, {} -- key -> marker on the open map; markers not in use
local vector = CreateVector2D(0, 0)

local function MapMarkerOnEnter(self)
	local ping = pings[self.key]
	if ping then
		ShowPingTooltip(self, ping)
	end
end

local function MapMarkerOnLeave()
	GameTooltip:Hide()
end

local function MapMarkerHover(self, tip)
	local ping = pings[self.key]
	if ping then
		ShowPingTooltip(self, ping, tip)
	end
end

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

local function ReleaseMapMarker(key)
	local frame = mapPins[key]
	mapPins[key] = nil
	if Overlay.TooltipOf(frame) then
		Overlay.TooltipOf(frame):Hide()
	end
	frame.RippleAnim:Stop()
	frame:Hide()
	spareMapPins[#spareMapPins + 1] = frame
end

local function ReleaseAllMapMarkers()
	for key in pairs(mapPins) do
		ReleaseMapMarker(key)
	end
end

local function AcquireMapMarker(key)
	local frame = table.remove(spareMapPins)
	if not frame then
		frame = Overlay.Frame("beaconPing")
		if not frame then
			return nil
		end
		frame:SetSize(MAP_SIZE, MAP_SIZE)
		BuildMarker(frame)
		frame:SetMouseMotionEnabled(true) -- hover only: clicks go through to the map
		frame:SetMouseClickEnabled(false)
		frame:SetScript("OnEnter", MapMarkerOnEnter)
		frame:SetScript("OnLeave", MapMarkerOnLeave)
		Overlay.SetHover(frame, MapMarkerHover)
	end
	frame:SetFrameLevel(Overlay.Level(MARKER_LEVEL))
	frame.key = key
	mapPins[key] = frame
	return frame
end

local function DrawWorldMap()
	local view = Overlay.view
	local mapID = view.shown and M.enabled and view.mapID
	local now = GetTime()
	for key, frame in pairs(mapPins) do
		local ping = mapID and pings[key]
		local x, y
		if ping then
			x, y = MapPosition(ping, mapID)
		end
		if x then
			Overlay.Place(frame, x, y, SCALE_FROM, SCALE_TO)
			StyleMarker(frame, ping, now, 1)
		else
			ReleaseMapMarker(key)
		end
	end
	if not mapID then
		return
	end
	for key, ping in pairs(pings) do
		if not mapPins[key] then
			local x, y = MapPosition(ping, mapID)
			local frame = x and AcquireMapMarker(key)
			if frame then
				Overlay.Place(frame, x, y, SCALE_FROM, SCALE_TO)
				StyleMarker(frame, ping, now, 1)
			end
		end
	end
end

Overlay.Watch("B.WorldMapPings", function(what)
	if what == "hide" then
		ReleaseAllMapMarkers()
	elseif what == "scale" then
		for _, frame in pairs(mapPins) do -- (the same spots, another zoom)
			if frame.mapX then
				Overlay.Place(frame, frame.mapX, frame.mapY, SCALE_FROM, SCALE_TO)
			end
		end
	else
		DrawWorldMap()
	end
end)

-- Alt+click on the world map pings that spot; on my own marker it takes my ping back. Read from
-- GLOBAL_MOUSE_DOWN (Core/MapOverlay.lua: only while the map is open, only on the map), mouse down
-- because on mouse up the map may zoom into the zone and move what's under the cursor. No hook on
-- the map: a script hooked there runs inside Blizzard's click handling.
Overlay.OnMouse("B.MapPingClick", function(event, button)
	if event == "down" and button == "LeftButton" and IsAltKeyDown() and M.enabled and M.db.pings and Overlay.MouseOnMap() then
		local mine = mapPins.me
		if mine and mine:IsShown() and mine:IsMouseOver() then
			B.ClearMyPing() -- on my own marker: take it back
		else
			B.PingMapPosition(Overlay.view.mapID, Overlay.CursorPosition())
		end
	end
end)

-- Beacon on (Dots.lua's B.Attach): an open map shows the markers at once.
function B.AttachPings()
	if Overlay.view.shown then
		DrawWorldMap()
	end
end

function B.DetachPings()
	ReleaseAllMapMarkers()
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
	if Overlay.view.shown then
		if B.pingsDirty then
			DrawWorldMap()
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
