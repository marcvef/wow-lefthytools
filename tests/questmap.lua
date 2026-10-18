-- Misc Tweaks: quests on continent and world maps.
local suite = ...
local check, near, section, lefthy = suite.check, suite.near, suite.section, suite.lefthy

section("Misc Tweaks: quests on continent and world maps")
do
	local TDB = LefthyToolsDB.settings.tweaks
	local function T(id) return REGISTERED_SETTINGS["LefthyTools_tweaks_" .. id] end
	check(TDB.questMap == true and TDB.questMapContinent == "both" and TDB.questMapWorld == "both"
		and TDB.questMapZone == "blizzard" and T("questMap") and T("questMapContinent") and T("questMapWorld") and T("questMapZone"),
		"on by default: icons and areas on continent maps and the world map, zone maps as Blizzard has them")
	local savedQuests = QUESTS
	QUESTS = {
		{ id = 101, title = "Kobold Camp Cleanup",
			objectives = { { text = "Kobold Vermin slain: 4/10", finished = false }, { text = "Map found", finished = true } } },
		{ id = 102, title = "The Defias Brotherhood", objectives = {}, complete = true },
		{ id = 103, title = "A city errand", objectives = { { text = "Package delivered: 0/1", finished = false } } },
	}
	-- What the zone maps show: Elwynn Forest its quest and the city's (reported on the zone too),
	-- the city its own, Westfall one.
	QUESTS_ON_MAP = { [1429] = { { 101, 0.5, 0.5 }, { 103, 0.2, 0.2, 1453 } }, [1453] = { { 103, 0.5, 0.5 } },
		[1436] = { { 102, 0.5, 0.25 } } }
	SUPER_TRACKED = 0
	local asked = 0
	local getQuestsOnMap = C_QuestLog.GetQuestsOnMap
	C_QuestLog.GetQuestsOnMap = function(mapID) asked = asked + 1; return getQuestsOnMap(mapID) end
	local ICONS, AREAS = "LefthyToolsQuestMapPinTemplate", "LefthyToolsQuestAreaPinTemplate"
	local function iconOf(id) for _, pin in ipairs(PinsOf(ICONS)) do if pin.quest.questID == id then return pin end end end
	local function areaOf(zone) for _, pin in ipairs(PinsOf(AREAS)) do if pin.mapID == zone then return pin end end end

	OpenWorldMap(1429)
	check(#PinsOf(ICONS) == 0 and #PinsOf(AREAS) == 0, "a zone map: Blizzard's own icons and area, nothing added")
	OpenWorldMap(1415)
	local kobolds, defias, errand = iconOf(101), iconOf(102), iconOf(103)
	check(#PinsOf(ICONS) == 3 and kobolds and defias and errand, "continent map: an icon per quest in its zones, the city's quest once")
	check(near(kobolds.x, 0.375) and near(kobolds.y, 0.375) and near(defias.x, 0.25) and near(defias.y, 0.5625),
		"... at the zone map's spot, carried over to the continent")
	check(near(errand.x, 0.3) and near(errand.y, 0.3), "... a quest in the city at its spot in the city")
	check(kobolds.Icon.atlas == "Quest-In-Progress-Icon-yellow" and defias.Icon.atlas == "UI-QuestIcon-TurnIn-Normal"
		and kobolds.Back.atlas == "UI-QuestPoi-QuestNumber", "Blizzard's quest icons: in progress, ready to turn in")
	local elwynn = areaOf(1429)
	check(#PinsOf(AREAS) == 3 and elwynn and #elwynn.blobs == 1 and elwynn.blobs[1] == 101 and areaOf(1453).blobs[1] == 103
		and areaOf(1436).blobs[1] == 102, "... and the quest areas, each drawn for its own zone")
	check(elwynn:GetWidth() == 250 and elwynn:GetHeight() == 250 and near(elwynn.x, 0.375) and near(elwynn.y, 0.375),
		"... laid over that zone on the continent")
	kobolds:OnMouseEnter()
	local tip = table.concat(TOOLTIP.lines, "|")
	check(TOOLTIP.title == "Kobold Camp Cleanup" and tip:find("Elwynn Forest", 1, true) and tip:find("Kobold Vermin slain: 4/10", 1, true)
		and not tip:find("Map found", 1, true), "hovering an icon: the quest, its zone and what's left, got " .. tip)
	check(#PinsOf(AREAS) == 3, "... areas already shown: none added")
	kobolds:OnMouseLeave()
	check(not TOOLTIP.shown, "the tooltip goes on leave")
	defias:OnMouseEnter()
	check(table.concat(TOOLTIP.lines, "|"):find("Ready to turn in", 1, true), "a finished quest: ready to turn in")
	defias:OnMouseLeave()

	OpenWorldMap(947)
	check(#PinsOf(ICONS) == 3 and near(iconOf(101).x, 0.65) and near(iconOf(101).y, 0.325) and near(iconOf(103).x, 0.62),
		"world map: the same quests, placed through their continent")
	check(areaOf(1429) and near(areaOf(1429).x, 0.65) and near(areaOf(1429):GetWidth(), 100), "... with their areas")

	SUPER_TRACKED = 101
	OpenWorldMap(1415)
	check(not iconOf(101) and #PinsOf(ICONS) == 2 and areaOf(1429).blobs[1] == 101,
		"the selected quest: Blizzard shows its icon on continent maps, so only its area is added")
	OpenWorldMap(947)
	check(iconOf(101) and iconOf(101).Back.atlas == "UI-QuestPoi-QuestNumber-SuperTracked"
		and iconOf(101).frameLevelType == "PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST", "... the world map shows it, marked as selected")
	SUPER_TRACKED = 0

	-- Clicking an icon selects its quest, as on zone maps.
	local savedWatched = WATCHED
	WATCHED = {}
	OpenWorldMap(1415)
	check(TDB.questMapClick == true and T("questMapClick") and iconOf(102)._click == true
		and iconOf(102)._passThrough and iconOf(102)._passThrough[1] == "RightButton",
		"icons take left clicks (a setting, on); right-clicks go through to the map, which zooms out")
	local soundMark = #SOUNDS
	iconOf(102):OnClick("LeftButton")
	check(SUPER_TRACKED == 102 and WATCHED[1] == 102 and #SOUNDS == soundMark + 1, "a click selects the quest and tracks it, with a click sound")
	Advance(0.05)
	check(not iconOf(102) and #PinsOf(ICONS) == 2, "... the map is redrawn right away: on continent maps Blizzard shows the selected quest's icon")
	OpenWorldMap(947)
	iconOf(102):OnClick("LeftButton")
	check(SUPER_TRACKED == 0 and WATCHED[1] == 102, "clicking the selected quest unselects it (it stays tracked)")
	STATE.shift = true
	iconOf(102):OnClick("LeftButton")
	STATE.shift = false
	check(SUPER_TRACKED == 0 and #WATCHED == 0, "Shift-click on a tracked quest stops tracking it")
	iconOf(101):OnClick("RightButton")
	check(SUPER_TRACKED == 0, "a right-click doesn't select")
	T("questMapContinent"):SetValue(2) -- icons only
	SUPER_TRACKED = 101
	OpenWorldMap(1415)
	check(#PinsOf(AREAS) == 1 and areaOf(1429).blobs[1] == 101 and #areaOf(1429).blobs == 1,
		"icons only: the selected quest's area still shows, as on zone maps")
	SUPER_TRACKED = 0
	T("questMapContinent"):SetValue(4)
	T("questMapClick"):SetValue(false)
	OpenWorldMap(1415)
	iconOf(102):OnClick("LeftButton")
	check(iconOf(102)._click == false and SUPER_TRACKED == 0, "setting off: icons take no clicks, a click zooms the map in")
	T("questMapClick"):SetValue(true)
	GAMEPAD_STATE.ui = true
	OpenWorldMap(1415)
	check(iconOf(102)._click == false and not iconOf(102).OnMouseClickAction,
		"gamepad mode: no click action (the controller's button would run it inside Blizzard's map code)")
	GAMEPAD_STATE.ui = false
	WATCHED = savedWatched
	Advance(0.6)

	T("questMapContinent"):SetValue(2) -- the slider: icons only
	check(TDB.questMapContinent == "icons", "continent maps: icons only")
	OpenWorldMap(1415)
	check(#PinsOf(ICONS) == 3 and #PinsOf(AREAS) == 0, "... no areas")
	kobolds = iconOf(101)
	kobolds:OnMouseEnter()
	check(#PinsOf(AREAS) == 1 and areaOf(1429).blobs[1] == 101 and #areaOf(1429).blobs == 1, "... hovering an icon shows its area")
	kobolds:OnMouseLeave()
	check(#PinsOf(AREAS) == 0, "... until the mouse leaves")
	T("questMapContinent"):SetValue(3) -- areas only
	Advance(0.6) -- the open map follows the setting
	check(#PinsOf(ICONS) == 0 and #PinsOf(AREAS) == 3, "areas only")
	T("questMapContinent"):SetValue(1)
	Advance(0.6)
	check(#PinsOf(ICONS) == 0 and #PinsOf(AREAS) == 0, "nothing")
	T("questMapContinent"):SetValue(4)
	Advance(0.6)

	T("questMapZone"):SetValue(2) -- every quest's area on zone maps
	SUPER_TRACKED = 103
	OpenWorldMap(1429)
	check(#PinsOf(ICONS) == 0 and #PinsOf(AREAS) == 1 and areaOf(1429).blobs[1] == 101 and #areaOf(1429).blobs == 1
		and areaOf(1429):GetWidth() == 1000, "zone maps, all quests: their areas over the whole map, not the selected one's (Blizzard draws it)")
	T("questMapZone"):SetValue(1)
	SUPER_TRACKED = 0

	FOCUSED_QUEST = 102
	QuestMapFrame_GetFocusedQuestID = function() return FOCUSED_QUEST end
	OpenWorldMap(1415)
	check(#PinsOf(ICONS) == 1 and iconOf(102) and #PinsOf(AREAS) == 1, "a quest's details open: only that quest, as on zone maps")
	QuestMapFrame_GetFocusedQuestID = nil

	-- Quest changes while the map is open: one redraw for a burst of events.
	OpenWorldMap(1415)
	QUESTS[#QUESTS + 1] = { id = 104, title = "Another one", objectives = {} }
	table.insert(QUESTS_ON_MAP[1436], { 104, 0.7, 0.7 })
	asked = 0
	for _ = 1, 5 do Fire("QUEST_LOG_UPDATE") end
	check(asked == 0, "quest events only queue a redraw")
	Advance(0.6)
	check(asked == 3 and iconOf(104), "... half a second later the map is redrawn once (3 zones asked), with the new quest")
	CVARS.questPOI = "0"
	Fire("CVAR_UPDATE", "questPOI")
	Advance(0.6)
	check(#PinsOf(ICONS) == 0 and #PinsOf(AREAS) == 0, "the map's quest objectives filter off: nothing")
	CVARS.questPOI = "1"
	local blockedMark = #BLOCKED
	STATE.combat = true
	OpenWorldMap(1414); OpenWorldMap(1415)
	check(#PinsOf(ICONS) == 4 and #BLOCKED == blockedMark, "drawn in combat without blocked actions, got " .. table.concat(BLOCKED, ", "))
	STATE.combat = false

	WorldMapFrame:Hide()
	asked = 0
	Fire("QUEST_LOG_UPDATE"); Fire("QUEST_POI_UPDATE")
	Advance(1)
	check(asked == 0, "map closed: quest events cost nothing")
	lefthy("tweaks questmap off")
	Advance(0.1)
	OpenWorldMap(1415)
	check(TDB.questMap == false and #PinsOf(ICONS) == 0 and #PinsOf(AREAS) == 0 and asked == 0, "/lefthy tweaks questmap off")
	lefthy("tweaks questmap on")
	Advance(0.1)
	OpenWorldMap(1415)
	check(#PinsOf(ICONS) == 4, "on again")
	WorldMapFrame:Hide()
	C_QuestLog.GetQuestsOnMap = getQuestsOnMap
	QUESTS, QUESTS_ON_MAP = savedQuests, {}
end
