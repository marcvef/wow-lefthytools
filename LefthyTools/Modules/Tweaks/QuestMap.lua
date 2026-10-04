local _, ns = ...
local L = ns.L
local M = ns.LT:GetModule("tweaks")

-- Quests on continent and world maps (the questMap tweak).
--
-- Blizzard's world map shows the quests in your log on zone maps only
-- (MapUtil.ShouldMapTypeShowQuests): an icon per quest, and the area ("blob") of the selected
-- one. A continent map shows just the selected quest's icon, the world map nothing. This adds
-- them there, per zoom level as set: icons, areas or both. On zone maps it can add every quest's
-- area.
--
-- Where: each zone on the shown map is asked for its quests (C_QuestLog.GetQuestsOnMap, what the
-- zone map shows), and their spots are carried over with the zone's rectangle on the shown map
-- (C_Map.GetMapRectOnMap). Areas are drawn by the engine (a QuestPOIFrame, like Blizzard's
-- QuestBlobPinTemplate) for one map at a time, so each zone with quests gets its own, set to that
-- zone and laid over its rectangle.
--
-- Cost: nothing while the map is closed. While it's open, quest events only queue a redraw, at
-- most one every half second.

local ICON_TEMPLATE = "LefthyToolsQuestMapPinTemplate"
local AREA_TEMPLATE = "LefthyToolsQuestAreaPinTemplate"
local REFRESH_GAP = 0.5
local ICON_SCALE = 0.8   -- of Blizzard's quest icons on zone maps: continents get crowded
local QUANTIZE_CELLS = 75 -- Blizzard's grid for spreading icons that would cover each other
local MAP_TYPE = Enum.UIMapType or { Cosmic = 0, World = 1, Continent = 2, Zone = 3 }
local WHOLE_MAP = { 0, 1, 0, 1 }
local EVENTS = { "QUEST_LOG_UPDATE", "QUEST_POI_UPDATE", "QUEST_WATCH_LIST_CHANGED", "SUPER_TRACKING_CHANGED",
	"CVAR_UPDATE" }

local active, attached = false, false
local provider = CreateFromMixins(MapCanvasDataProviderMixin)
local hoverArea -- the area shown while an icon is hovered

local function HideHoverArea()
	local pin = hoverArea
	hoverArea = nil
	if pin and attached then
		WorldMapFrame:RemovePin(pin)
	end
end

---------------------------------------------------------------------------
-- Maps
---------------------------------------------------------------------------

-- What to show on a map: icons, areas, and whether it's a zone map (Blizzard draws the icons there).
local function Wanted(mapID)
	local info = C_Map.GetMapInfo(mapID)
	if not (info and info.mapType) or not GetCVarBool("questPOI") then -- the map's quest objectives filter
		return false, false, false
	end
	local mode
	if info.mapType == MAP_TYPE.World or info.mapType == MAP_TYPE.Cosmic then
		mode = M.db.questMapWorld
	elseif info.mapType == MAP_TYPE.Continent then
		mode = M.db.questMapContinent
	else
		return false, M.db.questMapZone == "areas", true
	end
	return mode == "icons" or mode == "both", mode == "areas" or mode == "both", false
end

-- A map's rectangle on a map above it, { left, right, top, bottom } (0-1), or false. Maps don't
-- move, so it's kept.
local rects = {}
local function Rect(mapID, topID)
	rects[topID] = rects[topID] or {}
	local rect = rects[topID][mapID]
	if rect == nil then
		local left, right, top, bottom = C_Map.GetMapRectOnMap(mapID, topID)
		if not left then
			-- Not placed on that map directly (a zone on the world map): through its parent.
			local info = C_Map.GetMapInfo(mapID)
			local parent = info and info.parentMapID
			local outer = parent and parent ~= 0 and parent ~= mapID and parent ~= topID and Rect(parent, topID)
			local l, r, t, b
			if outer then
				l, r, t, b = C_Map.GetMapRectOnMap(mapID, parent)
			end
			if l then
				local width, height = outer[2] - outer[1], outer[4] - outer[3]
				left, right = outer[1] + l * width, outer[1] + r * width
				top, bottom = outer[3] + t * height, outer[3] + b * height
			end
		end
		rect = left and right > left and bottom > top and { left, right, top, bottom } or false
		rects[topID][mapID] = rect
	end
	return rect
end

-- The zones on a continent or world map: { ids = { mapID, ... }, has = { [mapID] = true } }.
local zoneLists = {}
local function ZonesOn(mapID)
	local zones = zoneLists[mapID]
	if not zones then
		zones = { ids = {}, has = {} }
		for _, child in ipairs(C_Map.GetMapChildrenInfo(mapID, MAP_TYPE.Zone, true) or {}) do
			if not zones.has[child.mapID] and Rect(child.mapID, mapID) then
				zones.ids[#zones.ids + 1] = child.mapID
				zones.has[child.mapID] = true
			end
		end
		zoneLists[mapID] = zones
	end
	return zones
end

---------------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------------

-- Blizzard's rules for quest icons (QuestDataProviderMixin:ShouldShowQuest), without the map type.
local function Showable(info, focused)
	local questID = info.questID
	if not questID or info.isMapIndicatorQuest or (focused and focused ~= questID) then
		return false
	end
	if (QuestUtils_IsQuestWorldQuest and QuestUtils_IsQuestWorldQuest(questID))
		or (QuestUtils_IsQuestBonusObjective and QuestUtils_IsQuestBonusObjective(questID)) then
		return false
	end
	return not HaveQuestData or HaveQuestData(questID)
end

-- The quests to show on a map: { { questID, zone, x, y }, ... }, x and y on that map.
local function Collect(mapID, isZone)
	local quests = {}
	-- With a quest's details open, the map shows only that quest.
	local focused = QuestMapFrame_GetFocusedQuestID and QuestMapFrame_GetFocusedQuestID()
	if isZone then
		for _, info in ipairs(C_QuestLog.GetQuestsOnMap(mapID) or {}) do
			if Showable(info, focused) then
				quests[#quests + 1] = { questID = info.questID, zone = mapID, x = info.x, y = info.y }
			end
		end
		return quests
	end
	local zones = ZonesOn(mapID)
	for _, zone in ipairs(zones.ids) do
		local rect = Rect(zone, mapID)
		for _, info in ipairs(C_QuestLog.GetQuestsOnMap(zone) or {}) do
			-- A quest in a zone inside this one (a city) comes up for both: count it from its own.
			local fromInside = info.mapID and info.mapID ~= zone and zones.has[info.mapID]
			if not fromInside and Showable(info, focused) then
				quests[#quests + 1] = { questID = info.questID, zone = zone,
					x = rect[1] + info.x * (rect[2] - rect[1]), y = rect[3] + info.y * (rect[4] - rect[3]) }
			end
		end
	end
	return quests
end

-- Icons that would cover each other move to free neighbouring cells, like on zone maps.
local quantizer
local function Spread(map, quests)
	if not (WorldMapPOIQuantizerMixin and SparseGridMixin) then
		return
	end
	local high = QUANTIZE_CELLS
	local wide = math.ceil(high * map:DenormalizeHorizontalSize(1) / map:DenormalizeVerticalSize(1))
	if not quantizer then
		quantizer = CreateFromMixins(WorldMapPOIQuantizerMixin)
		quantizer:OnLoad(wide, high)
	elseif quantizer.numCellsWide ~= wide then
		quantizer:Resize(wide, high)
	end
	quantizer:ClearAndQuantize(quests)
end

---------------------------------------------------------------------------
-- Pins
---------------------------------------------------------------------------

-- Atlases from Blizzard's quest icons (POIButton.lua), at their own size; fallback: a texture or nothing.
local function SetArt(texture, atlas, fallback)
	if C_Texture.GetAtlasInfo(atlas) then
		texture:SetAtlas(atlas, true)
		texture:SetScale(ICON_SCALE)
	else
		texture:SetTexture(fallback)
		texture:SetSize(16, 16)
		texture:SetScale(1)
	end
end

-- One zone's quest areas, laid over the zone on the shown map.
local function AcquireArea(map, mapID, zone, questIDs)
	local rect = zone == mapID and WHOLE_MAP or Rect(zone, mapID)
	local pin = map:AcquirePin(AREA_TEMPLATE)
	pin:SetSize(map:DenormalizeHorizontalSize(rect[2] - rect[1]), map:DenormalizeVerticalSize(rect[4] - rect[3]))
	pin:SetPosition((rect[1] + rect[2]) / 2, (rect[3] + rect[4]) / 2)
	pin:SetMapID(zone)
	pin:DrawNone()
	for _, questID in ipairs(questIDs) do
		pin:DrawBlob(questID, true)
	end
	return pin
end

-- Redraws an open map on the next frame (after a click: not while the clicked pin is busy).
local function RefreshSoon()
	C_Timer.After(0, function()
		if attached and WorldMapFrame:IsShown() then
			provider:RefreshAllData()
		end
	end)
end

-- A click on an icon does what it does on zone maps (POIButtonMixin:OnClick): it selects the
-- quest (waypoint arrow, its area on the map; tracked if it wasn't), or unselects the selected
-- one. Shift-click on a tracked quest stops tracking it; with the chat box open, its link goes in.
local function SelectQuest(self, button)
	local questID = button == "LeftButton" and self.quest and self.quest.questID
	if not questID then
		return
	end
	if questID == C_SuperTrack.GetSuperTrackedQuestID() then
		PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF or 857)
		C_SuperTrack.ClearAllSuperTracked()
		RefreshSoon()
		return
	end
	PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
	if ChatFrameUtil and ChatFrameUtil.TryInsertQuestLinkForQuestID and ChatFrameUtil.TryInsertQuestLinkForQuestID(questID) then
		return
	end
	if C_QuestLog.GetQuestWatchType(questID) ~= nil then
		if IsShiftKeyDown() then
			if not (QuestUtil and QuestUtil.CanRemoveQuestWatch) or QuestUtil.CanRemoveQuestWatch() then
				C_QuestLog.RemoveQuestWatch(questID)
			end
			return
		end
	else
		C_QuestLog.AddQuestWatch(questID)
	end
	C_SuperTrack.SetSuperTrackedQuestID(questID)
	RefreshSoon()
end

LefthyToolsQuestMapPinMixin = CreateFromMixins(MapCanvasPinMixin)

function LefthyToolsQuestMapPinMixin:OnLoad()
	self:SetScalingLimits(1, 1.0, 1.2)
	self.Back = self:CreateTexture(nil, "BACKGROUND")
	self.Back:SetPoint("CENTER")
	self.Icon = self:CreateTexture(nil, "ARTWORK")
	self.Icon:SetPoint("CENTER")
end

function LefthyToolsQuestMapPinMixin:OnAcquired(quest, index)
	self.quest = quest
	local selected = quest.questID == C_SuperTrack.GetSuperTrackedQuestID()
	self:UseFrameLevelType(selected and "PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST" or "PIN_FRAME_LEVEL_ACTIVE_QUEST", index)
	SetArt(self.Back, selected and "UI-QuestPoi-QuestNumber-SuperTracked" or "UI-QuestPoi-QuestNumber", nil)
	if C_QuestLog.IsComplete(quest.questID) then
		SetArt(self.Icon, "UI-QuestIcon-TurnIn-Normal", "Interface\\GossipFrame\\ActiveQuestIcon")
	else
		SetArt(self.Icon, "Quest-In-Progress-Icon-yellow", "Interface\\GossipFrame\\AvailableQuestIcon")
	end
	-- Clicks select the quest (setting questMapClick), else they reach the map, which zooms in.
	-- Not with a controller: its button "clicks" pins from inside Blizzard's own code
	-- (WorldMapMixin:GamepadMapClick), which would then go on, tainted, to change the map.
	local clickable = M.db.questMapClick and not (InputUtil and InputUtil.IsGamepadUIEnabled())
	self.OnMouseClickAction = clickable and SelectQuest or nil -- (the map canvas calls it from OnClick)
	self:SetMouseClickEnabled(clickable and true or false)
end

function LefthyToolsQuestMapPinMixin:OnMouseEnter()
	local quest = self.quest
	if not quest then
		return
	end
	local questID = quest.questID
	local title = C_QuestLog.GetTitleForQuestID(questID) or ""
	if SetQuestTitleLevelAndDifficultyColor then -- [level] and difficulty colour, as the map's own options say
		local ok, styled = pcall(SetQuestTitleLevelAndDifficultyColor, questID, title)
		title = ok and styled or title
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(title)
	local map = self:GetMap()
	local zone = quest.zone ~= map:GetMapID() and C_Map.GetMapInfo(quest.zone)
	if zone then
		GameTooltip:AddLine(zone.name, 0.75, 0.75, 0.75)
	end
	if C_QuestLog.IsComplete(questID) then
		GameTooltip:AddLine(L["Ready to turn in"], 0.3, 1, 0.3)
	else
		for _, objective in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
			if objective.text and not objective.finished then
				GameTooltip:AddLine((QUEST_DASH or "- ") .. objective.text, 1, 1, 1, true)
			end
		end
	end
	GameTooltip:Show()
	-- With icons only, the hovered quest's area shows (on zone maps Blizzard does that too).
	local _, areas = Wanted(map:GetMapID())
	if not areas and not hoverArea and questID ~= C_SuperTrack.GetSuperTrackedQuestID() then -- (the selected one's is there)
		hoverArea = AcquireArea(map, map:GetMapID(), quest.zone, { questID })
	end
end

function LefthyToolsQuestMapPinMixin:OnMouseLeave()
	GameTooltip:Hide()
	HideHoverArea() -- (also runs while a redraw releases this pin: no self:GetMap() then)
end

-- AcquirePin calls this on every acquire: right-clicks go through to the map (zoom out), as on
-- Blizzard's pins. SetPassThroughButtons is protected in combat, so it's set once, outside it.
function LefthyToolsQuestMapPinMixin:CheckMouseButtonPassthrough()
	if not self.passesRightClicks and not InCombatLockdown() then
		self:SetPassThroughButtons("RightButton")
		self.passesRightClicks = true
	end
end

-- Like Blizzard's QuestBlobPinMixin, without the mouse.
LefthyToolsQuestAreaPinMixin = CreateFromMixins(MapCanvasPinMixin)

function LefthyToolsQuestAreaPinMixin:OnLoad()
	self:SetFillTexture("Interface\\WorldMap\\UI-QuestBlob-Inside")
	self:SetBorderTexture("Interface\\WorldMap\\UI-QuestBlob-Outside")
	self:SetFillAlpha(128)
	self:SetBorderAlpha(192)
	self:SetBorderScalar(1.0)
	self:SetIgnoreGlobalPinScale(true)
	self:UseFrameLevelType("PIN_FRAME_LEVEL_QUEST_BLOB")
end

function LefthyToolsQuestAreaPinMixin:CheckMouseButtonPassthrough()
end

---------------------------------------------------------------------------
-- Map provider
---------------------------------------------------------------------------

function provider:RemoveAllData()
	local map = self:GetMap()
	hoverArea = nil -- removed with the other areas
	map:RemoveAllPinsByTemplate(ICON_TEMPLATE)
	map:RemoveAllPinsByTemplate(AREA_TEMPLATE)
end

function provider:RefreshAllData()
	self:RemoveAllData()
	local map = self:GetMap()
	local mapID = map:GetMapID()
	if not (active and mapID) then
		return
	end
	local icons, areas, isZone = Wanted(mapID)
	if not (icons or areas) then
		return
	end
	local quests = Collect(mapID, isZone)
	-- Blizzard already shows the selected quest: its icon on continent maps, its area on zone maps.
	local selected = C_SuperTrack.GetSuperTrackedQuestID()
	local continent = C_Map.GetMapInfo(mapID).mapType == MAP_TYPE.Continent
	-- Areas: every quest's; with icons only, the selected quest's, as zone maps show it.
	local byZone, zones = {}, {}
	for _, quest in ipairs(quests) do
		local draw
		if isZone then
			draw = quest.questID ~= selected
		else
			draw = areas or quest.questID == selected
		end
		if draw then
			if not byZone[quest.zone] then
				byZone[quest.zone] = {}
				zones[#zones + 1] = quest.zone
			end
			table.insert(byZone[quest.zone], quest.questID)
		end
	end
	for _, zone in ipairs(zones) do
		AcquireArea(map, mapID, zone, byZone[zone])
	end
	if icons then
		local shown = {}
		for _, quest in ipairs(quests) do
			if not (continent and quest.questID == selected) then
				shown[#shown + 1] = quest
			end
		end
		Spread(map, shown)
		for index, quest in ipairs(shown) do
			local pin = map:AcquirePin(ICON_TEMPLATE, quest, index)
			pin:SetPosition(quest.quantizedX or quest.x, quest.quantizedY or quest.y)
		end
	end
end

function provider:OnCanvasSizeChanged()
	if WorldMapFrame:IsShown() then
		self:RefreshAllData()
	end
end

-- Quest changes while the map is open: redrawn half a second later, once for a burst of events.
local events = CreateFrame("Frame")
local refreshQueued = false

local function QueueRefresh()
	if refreshQueued then
		return
	end
	refreshQueued = true
	C_Timer.After(REFRESH_GAP, function()
		refreshQueued = false
		if attached and WorldMapFrame:IsShown() then
			provider:RefreshAllData()
		end
	end)
end

events:SetScript("OnEvent", function(_, event, name)
	if event ~= "CVAR_UPDATE" or name == "questPOI" then
		QueueRefresh()
	end
end)

function provider:OnShow()
	for _, event in ipairs(EVENTS) do
		pcall(events.RegisterEvent, events, event)
	end
end

function provider:OnHide()
	events:UnregisterAllEvents()
end

---------------------------------------------------------------------------
-- Switching on and off (Tweaks.lua)
---------------------------------------------------------------------------

local function Attach()
	if attached or not (active and WorldMapFrame and WorldMapFrame.AddDataProvider) then
		return
	end
	WorldMapFrame:AddDataProvider(provider)
	attached = true
	if WorldMapFrame:IsShown() then
		provider:OnShow()
		provider:RefreshAllData()
	end
end

-- The world map may load later than us.
local loader = CreateFrame("Frame")
loader:SetScript("OnEvent", function(self, _, name)
	if name == "Blizzard_WorldMap" then
		self:UnregisterEvent("ADDON_LOADED")
		C_Timer.After(0, Attach)
	end
end)

function ns.ApplyQuestMap(on)
	active = on
	if on then
		if WorldMapFrame then
			Attach()
		else
			loader:RegisterEvent("ADDON_LOADED")
		end
	elseif attached then
		WorldMapFrame:RemoveDataProvider(provider) -- takes its pins along
		events:UnregisterAllEvents()
		attached = false
	end
end

-- A setting changed: an open map follows.
function ns.RefreshQuestMap()
	if attached and WorldMapFrame:IsShown() then
		QueueRefresh()
	end
end
