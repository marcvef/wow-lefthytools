local _, ns = ...
local L = ns.L
local M = ns.LT:GetModule("tweaks")
local Overlay = ns.LT.MapOverlay
local view = Overlay.view

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
-- Drawn on frames of our own over the map (Core/MapOverlay.lua), not as the map's pins: the map is
-- only read, so the controller UI never runs anything of ours.
--
-- Cost: nothing while the map is closed. While it's open, quest events only queue a redraw, at
-- most one every half second.

local REFRESH_GAP = 0.5
local ICON_SCALE = 0.8   -- of Blizzard's quest icons on zone maps: continents get crowded
local QUANTIZE_CELLS = 75 -- Blizzard's grid for spreading icons that would cover each other
local MAP_TYPE = Enum.UIMapType or { Cosmic = 0, World = 1, Continent = 2, Zone = 3 }
local WHOLE_MAP = { 0, 1, 0, 1 }
local EVENTS = { "QUEST_LOG_UPDATE", "QUEST_POI_UPDATE", "QUEST_WATCH_LIST_CHANGED", "SUPER_TRACKING_CHANGED",
	"CVAR_UPDATE" }

local active = false

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
local function Spread(quests)
	if not (WorldMapPOIQuantizerMixin and SparseGridMixin) or not (view.width and view.height and view.height > 0) then
		return
	end
	local high = QUANTIZE_CELLS
	local wide = math.ceil(high * view.width / view.height)
	if not quantizer then
		quantizer = CreateFromMixins(WorldMapPOIQuantizerMixin)
		quantizer:OnLoad(wide, high)
	elseif quantizer.numCellsWide ~= wide then
		quantizer:Resize(wide, high)
	end
	quantizer:ClearAndQuantize(quests)
end

---------------------------------------------------------------------------
-- Frames: our own on the map's canvas (Core/MapOverlay.lua), never the map's pins
---------------------------------------------------------------------------

local icons, areas = { n = 0 }, { n = 0 } -- the i-th icon / area of a draw is always the i-th frame
local hoverArea                           -- the area shown while an icon is hovered (icons only)
local mouseIcon, pressedIcon, pressedButton
local passPending = false                 -- icons made in a fight pass right-clicks through after it

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

-- Right-clicks go through to the map (it zooms out), as on Blizzard's pins. SetPassThroughButtons is
-- protected in combat, so it's set once per icon, outside it: icons made in a fight get it after.
local function PassRightClicks(f)
	if f.passesRightClicks then
		return
	end
	if InCombatLockdown() then
		passPending = true
		return
	end
	f:SetPassThroughButtons("RightButton")
	f.passesRightClicks = true
end

local combat = CreateFrame("Frame")
combat:RegisterEvent("PLAYER_REGEN_ENABLED")
combat:SetScript("OnEvent", function()
	if passPending then
		C_Timer.After(0, function() -- (no frame work inside the event)
			if InCombatLockdown() then
				return -- (the next fight began: its end comes again)
			end
			passPending = false
			for i = 1, #icons do
				PassRightClicks(icons[i])
			end
		end)
	end
end)

-- One zone's quest areas: the engine draws them into a QuestPOIFrame for one map, filling the frame
-- (set up like Blizzard's QuestBlobPinMixin, without the mouse), laid over the zone on the shown map.
local function NewArea()
	local f = Overlay.Frame("questArea", "QuestPOIFrame")
	if not f then
		return nil
	end
	f:SetFillTexture("Interface\\WorldMap\\UI-QuestBlob-Inside")
	f:SetBorderTexture("Interface\\WorldMap\\UI-QuestBlob-Outside")
	f:SetFillAlpha(128)
	f:SetBorderAlpha(192)
	f:SetBorderScalar(1.0)
	f:EnableMouse(false)
	return f
end

local function DrawArea(f, mapID, zone, questIDs)
	local rect = zone == mapID and WHOLE_MAP or Rect(zone, mapID)
	f:SetFrameLevel(Overlay.Level("PIN_FRAME_LEVEL_QUEST_BLOB"))
	Overlay.PlaceRect(f, rect[1], rect[2], rect[3], rect[4])
	f:SetMapID(zone)
	f:DrawNone()
	for _, questID in ipairs(questIDs) do
		f:DrawBlob(questID, true)
	end
end

local function HideHoverArea()
	if hoverArea then
		hoverArea:Hide()
	end
end

-- With icons only, the hovered quest's area shows (on zone maps Blizzard does that too).
local function ShowHoverArea(f)
	local quest = f.quest
	local mapID = view.mapID
	if not mapID then
		return
	end
	local _, wantAreas = Wanted(mapID)
	if wantAreas or quest.questID == C_SuperTrack.GetSuperTrackedQuestID() then -- (the selected one's is there)
		return
	end
	hoverArea = hoverArea or NewArea()
	if hoverArea then
		DrawArea(hoverArea, mapID, quest.zone, { quest.questID })
	end
end

local function ShowQuestTooltip(f, tip)
	local questID = f.quest.questID
	local title = C_QuestLog.GetTitleForQuestID(questID) or ""
	if SetQuestTitleLevelAndDifficultyColor then -- [level] and difficulty colour, as the map's own options say
		local ok, styled = pcall(SetQuestTitleLevelAndDifficultyColor, questID, title)
		title = ok and styled or title
	end
	tip:SetOwner(f, "ANCHOR_RIGHT")
	tip:SetText(title)
	local zone = f.quest.zone ~= view.mapID and C_Map.GetMapInfo(f.quest.zone)
	if zone then
		tip:AddLine(zone.name, 0.75, 0.75, 0.75)
	end
	if C_QuestLog.IsComplete(questID) then
		tip:AddLine(L["Ready to turn in"], 0.3, 1, 0.3)
	else
		for _, objective in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
			if objective.text and not objective.finished then
				tip:AddLine((QUEST_DASH or "- ") .. objective.text, 1, 1, 1, true)
			end
		end
	end
	tip:Show()
end

local function IconOnEnter(self)
	mouseIcon = self
	if self.quest then
		ShowQuestTooltip(self, GameTooltip)
		ShowHoverArea(self)
	end
end

local function IconOnLeave(self)
	if mouseIcon == self then
		mouseIcon = nil
	end
	GameTooltip:Hide()
	HideHoverArea()
end

-- The controller's map cursor near an icon (Core/MapOverlay.lua): its tooltip on the map's own, and
-- its area. No click: the controller's button is the map's (it zooms in).
local function IconHover(self, tip)
	if self.quest then
		ShowQuestTooltip(self, tip)
		ShowHoverArea(self)
	end
end

local function NewIcon()
	local f = Overlay.Frame("questIcon")
	if not f then
		return nil
	end
	f:SetSize(16, 16)
	f.Back = f:CreateTexture(nil, "BACKGROUND")
	f.Back:SetPoint("CENTER")
	f.Icon = f:CreateTexture(nil, "ARTWORK")
	f.Icon:SetPoint("CENTER")
	-- The mouse, without a click script (a frame with one is a button to the controller's
	-- navigation, which reads it back from Blizzard's code): clicks come from GLOBAL_MOUSE_UP.
	f:EnableMouse(true)
	f:SetScript("OnEnter", IconOnEnter)
	f:SetScript("OnLeave", IconOnLeave)
	Overlay.SetHover(f, IconHover, HideHoverArea)
	PassRightClicks(f)
	return f
end

local function DrawIcon(i, quest)
	local f = icons[i] or NewIcon()
	if not f then
		return false
	end
	icons[i] = f
	f.quest = quest
	local selected = quest.questID == C_SuperTrack.GetSuperTrackedQuestID()
	f:SetFrameLevel(Overlay.Level(selected and "PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST" or "PIN_FRAME_LEVEL_ACTIVE_QUEST", i))
	SetArt(f.Back, selected and "UI-QuestPoi-QuestNumber-SuperTracked" or "UI-QuestPoi-QuestNumber", nil)
	if C_QuestLog.IsComplete(quest.questID) then
		SetArt(f.Icon, "UI-QuestIcon-TurnIn-Normal", "Interface\\GossipFrame\\ActiveQuestIcon")
	else
		SetArt(f.Icon, "Quest-In-Progress-Icon-yellow", "Interface\\GossipFrame\\AvailableQuestIcon")
	end
	-- Clicks select the quest (setting questMapClick), else they reach the map, which zooms in.
	-- Not with a controller: its button is the map's (it zooms in, or changes the zone).
	f.clickable = M.db.questMapClick and not (InputUtil and InputUtil.IsGamepadUIEnabled()) or false
	f:SetMouseClickEnabled(f.clickable)
	Overlay.Place(f, quest.quantizedX or quest.x, quest.quantizedY or quest.y, 1.0, 1.2)
	return true
end

-- Hides list[first], list[first + 1], ...; list.n: how many are drawn.
local function HideFrom(list, first)
	for i = first, #list do
		list[i]:Hide()
	end
	list.n = first - 1
end

local function Clear()
	HideFrom(icons, 1)
	HideFrom(areas, 1)
	HideHoverArea()
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function Draw()
	local mapID = view.shown and view.mapID
	if not (active and mapID) then
		Clear()
		return
	end
	local wantIcons, wantAreas, isZone = Wanted(mapID)
	if not (wantIcons or wantAreas) then
		Clear()
		return
	end
	HideHoverArea()
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
			draw = wantAreas or quest.questID == selected
		end
		if draw then
			if not byZone[quest.zone] then
				byZone[quest.zone] = {}
				zones[#zones + 1] = quest.zone
			end
			table.insert(byZone[quest.zone], quest.questID)
		end
	end
	local n = 0
	for _, zone in ipairs(zones) do
		local f = areas[n + 1] or NewArea()
		if f then
			n = n + 1
			areas[n] = f
			DrawArea(f, mapID, zone, byZone[zone])
		end
	end
	HideFrom(areas, n + 1)
	n = 0
	if wantIcons then
		local shown = {}
		for _, quest in ipairs(quests) do
			if not (continent and quest.questID == selected) then
				shown[#shown + 1] = quest
			end
		end
		Spread(shown)
		for index, quest in ipairs(shown) do
			if not DrawIcon(index, quest) then
				break
			end
			n = index
		end
	end
	HideFrom(icons, n + 1)
end

-- Redraws an open map on the next frame (after a click: not while the clicked icon is busy).
local function RefreshSoon()
	C_Timer.After(0, function()
		if view.shown then
			Draw()
		end
	end)
end

-- A click on an icon does what it does on zone maps (POIButtonMixin:OnClick): it selects the
-- quest (waypoint arrow, its area on the map; tracked if it wasn't), or unselects the selected
-- one. Shift-click on a tracked quest stops tracking it; with the chat box open, its link goes in.
local function SelectQuest(f, button)
	local questID = button == "LeftButton" and f.quest and f.quest.questID
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

-- A click is a GLOBAL_MOUSE_DOWN and a GLOBAL_MOUSE_UP of one button on the hovered icon (the right
-- button passes through to the map).
Overlay.OnMouse("QuestMap.Click", function(event, button)
	if event == "down" then
		if button ~= "RightButton" then
			pressedIcon, pressedButton = mouseIcon, button
		end
		return
	end
	local f = pressedIcon
	pressedIcon = nil
	if f and f == mouseIcon and button == pressedButton and f.clickable and f:IsVisible() and active then
		SelectQuest(f, button)
	end
end)

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
		if view.shown then
			Draw()
		end
	end)
end

events:SetScript("OnEvent", function(_, event, name)
	if event ~= "CVAR_UPDATE" or name == "questPOI" then
		QueueRefresh()
	end
end)

local function Listen()
	for _, event in ipairs(EVENTS) do
		pcall(events.RegisterEvent, events, event)
	end
end

-- The map: nothing while it's closed; drawn when it opens or shows another map, the icons placed
-- again on zoom (the areas are in canvas units: they zoom with the map).
Overlay.Watch("QuestMap", function(what)
	if what == "hide" then
		events:UnregisterAllEvents()
		mouseIcon, pressedIcon = nil, nil
		Clear()
		return
	end
	if what == "show" and active then
		Listen()
	end
	if what == "scale" then
		for i = 1, icons.n do
			local f = icons[i]
			if f.mapX then -- (one off the map stays hidden)
				Overlay.Place(f, f.mapX, f.mapY, 1.0, 1.2)
			end
		end
	else
		Draw()
	end
end)

---------------------------------------------------------------------------
-- Switching on and off (Tweaks.lua)
---------------------------------------------------------------------------

function ns.ApplyQuestMap(on)
	active = on
	if not on then
		events:UnregisterAllEvents()
		Clear()
	elseif view.shown then
		Listen()
		Draw()
	end
end

-- A setting changed: an open map follows.
function ns.RefreshQuestMap()
	if view.shown then
		QueueRefresh()
	end
end
