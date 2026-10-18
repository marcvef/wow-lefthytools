-- Misc Tweaks: the AFK screen, status values, bags, quest progress, combo points, retail unit frames,
-- new quests, quests on continent and world maps, who has aggro on enemy nameplates. (Cinematic
-- flights and the level-up window: flights.lua and levelup.lua.)
-- Needs: no other file.
local suite = ...
local check, near, section, ns, LT, lefthy = suite.check, suite.near, suite.section, suite.ns, suite.LT, suite.lefthy
local printedSince, afk = suite.printedSince, suite.afk
local Mirage = LT:GetModule("mirage")
local MDB = LefthyToolsDB.settings.mirage
local function S(id) return REGISTERED_SETTINGS["LefthyTools_mirage_" .. id] end

section("AFK screen")
local AFK = ns.AFKScreen
local function AFKS(id) return REGISTERED_SETTINGS["LefthyTools_tweaks_" .. id] end
check(LefthyToolsDB.settings.tweaks.afkScreen and LefthyToolsDB.settings.tweaks.afkSpin and AFKS("afkScreen") and AFKS("afkSpin")
	and MDB.afkScreen == nil and not S("afkScreen"), "a Misc Tweak (not part of Mirage), on by default")
Advance(0.1)
check(not AFK.driver:IsShown(), "not AFK: nothing runs at all")
afk(true)
check(UIParent:GetAlpha() == 1 and not LefthyToolsAFKFrame, "nothing happens inside the event handler")
Advance(0.05)
local afkScreen = LefthyToolsAFKFrame
check(afkScreen and afkScreen:IsShown() and UIParent:GetAlpha() == 0, "AFK: the interface disappears, the AFK screen shows")
check(afkScreen:GetParent() == nil and afkScreen._mouseEnabled and afkScreen._strata == "FULLSCREEN_DIALOG",
	"the screen isn't part of the interface, sits on top and catches clicks")
check(CAMERA.spinning and CAMERA.speed < 0.1, "the camera slowly circles")
check(afkScreen.Model._unit == "player", "your character")
check(afkScreen.Name:GetText():find("Lefthy|r", 1, true) and afkScreen.Name:GetText():find("Level 19 Human Rogue", 1, true),
	"name, level, race and class, got " .. afkScreen.Name:GetText())
local afkInfo = afkScreen.Info:GetText()
check(afkInfo:find("Elwynn Forest - Goldshire", 1, true) and afkInfo:find("Time: 12:", 1, true)
	and afkInfo:find("Level progress: 25%, rested: 20%", 1, true), "zone, time, level progress, got " .. afkInfo)
check(afkScreen.Friends:GetText():find("No friends with LefthyTools online", 1, true), "friends: none online yet")
Advance(65.5)
check(afkScreen.Title:GetText():find("1:05", 1, true), "the timer counts (once a second), got " .. afkScreen.Title:GetText())
Fire("CHAT_MSG_WHISPER", "you there?", "Anna-Realm")
Advance(1.1)
check(afkScreen.Info:GetText():find("Whispers: 1 (last from Anna)", 1, true), "whispers while away")
STATE.moving = true
Advance(0.3)
check(not afkScreen:IsShown() and UIParent:GetAlpha() == 1 and not CAMERA.spinning, "moving brings everything back, the camera stops")
STATE.moving = false
Advance(1)
check(not afkScreen:IsShown() and not AFK.driver:IsShown(), "still flagged AFK, but you were back: it stays away, nothing runs")
afk(false)
Advance(0.1)
afk(true)
Advance(0.05)
check(afkScreen:IsShown(), "the next AFK shows it again")
EnterCombat()
Advance(0.02)
check(not afkScreen:IsShown() and UIParent:GetAlpha() == 1, "combat: back on the next frame (SetAlpha works in combat)")
afk(false)
afk(true)
Advance(0.1)
check(not afkScreen:IsShown(), "not while in combat")
STATE.combat = false
afk(false)
afk(true)
Advance(0.05)
afkScreen._scripts.OnMouseDown(afkScreen, "LeftButton")
Advance(0.02)
check(not afkScreen:IsShown() and UIParent:GetAlpha() == 1, "a click brings everything back")
afk(false)
afk(true)
Advance(0.05)
Fire("READY_CHECK", "Anna", 30)
Advance(0.02)
check(not afkScreen:IsShown(), "a ready check needs you: back")
afk(false)
afk(true)
Advance(0.05)
afk(false)
Advance(0.3)
check(not afkScreen:IsShown() and UIParent:GetAlpha() == 1 and not AFK.driver:IsShown(), "no longer AFK: back, nothing runs")
AFKS("afkSpin"):SetValue(false)
afk(true)
Advance(0.05)
check(afkScreen:IsShown() and not CAMERA.spinning, "camera circling off")
AFKS("afkSpin"):SetValue(true)
afk(false)
lefthy("disable mirage")
afk(true)
Advance(0.05)
check(afkScreen:IsShown() and UIParent:GetAlpha() == 0, "it doesn't need Mirage")
lefthy("disable tweaks")
Advance(0.05)
check(not afkScreen:IsShown() and UIParent:GetAlpha() == 1, "Misc Tweaks off while AFK: back")
afk(false)
lefthy("enable tweaks")
lefthy("enable mirage")
Advance(0.05)
afk(true)
Advance(0.05)
check(afkScreen:IsShown(), "on again: the next AFK shows it (leaving by switching off isn't 'you were back')")
afk(false)
Advance(0.05)
AFKS("afkScreen"):SetValue(false)
Advance(0.05)
afk(true)
Advance(0.3)
check(not afkScreen:IsShown(), "AFK screen off: nothing")
afk(false)
AFKS("afkScreen"):SetValue(true)
Advance(0.05)
LefthyToolsDB.settings.tweaks.afkSpinning, CAMERA.spinning = true, true -- a /reload while the camera was circling
local stops = CAMERA.stops
AFK.Enable() -- what the login after a /reload does
Advance(0.05)
check(CAMERA.stops == stops + 1 and not CAMERA.spinning and not LefthyToolsDB.settings.tweaks.afkSpinning,
	"after a reload mid-circle the camera is stopped")
do -- A narrower screen (a big UI scale): the two columns get narrower instead of overlapping.
	local width = UIParent:GetWidth()
	UIParent:SetWidth(1100)
	afk(true)
	Advance(0.1)
	local info, friends = LefthyToolsAFKFrame.Info.width, LefthyToolsAFKFrame.Friends.width
	check(LefthyToolsAFKFrame:IsShown() and 300 + info + 20 <= 1100 - 40 - friends,
		"1100 wide: info ends before the friends begin, got " .. info .. " and " .. friends)
	afk(false)
	Advance(0.1)
	UIParent:SetWidth(width)
end
Advance(8) -- let the HUD settle again

section("Misc Tweaks: framework")
local Tweaks = LT:GetModule("tweaks")
local TDB = LefthyToolsDB.settings.tweaks
local function T(id) return REGISTERED_SETTINGS["LefthyTools_tweaks_" .. id] end
check(Tweaks and Tweaks.enabled, "tweaks module registered and enabled at login")
check(REGISTERED_SETTINGS.LefthyTools_module_tweaks, "overview page has a switch for Misc Tweaks")
check(Tweaks.category and Tweaks.category.parent == LT.category and Tweaks.category.name == "Misc Tweaks",
	"Misc Tweaks has its own sub-page under LefthyTools")
check(T("statusText") and T("movableBags") and T("questAnnounce") and not T("gamepadSortButton"),
	"one checkbox per tweak (sort button removed)")

section("Misc Tweaks: always show health / power values")
check(CVARS.statusText == "1" and CVARS.statusTextDisplay == "NUMERIC", "values shown permanently as current / max")
T("statusText"):SetValue(false)
check(CVARS.statusText == "1", "not applied inside the settings callback itself")
Advance(0.05)
check(CVARS.statusText == "0" and CVARS.statusTextDisplay == "PERCENT", "switching off restores the previous Status Text setting")
T("statusText"):SetValue(true); Advance(0.05)
check(CVARS.statusText == "1" and CVARS.statusTextDisplay == "NUMERIC", "on again")

section("Misc Tweaks: movable bags")
OpenBags()
check(ContainerFrameCombinedBags:GetPoint(1) == "BOTTOMRIGHT", "no saved position: Blizzard's default spot")
check(ContainerFrameCombinedBags._dragButtons and BAG_TITLE_ROUTER._dragButtons, "bag and its title bar accept drags")
BAG_TITLE_ROUTER._scripts.OnDragStart(BAG_TITLE_ROUTER)
check(ContainerFrameCombinedBags._moving and MENUS_CLOSED > 0, "dragging the title bar moves the bag and closes the bag menu")
ContainerFrameCombinedBags._dropAt = { left = 300, top = 700 }
BAG_TITLE_ROUTER._scripts.OnDragStop(BAG_TITLE_ROUTER)
local saved = TDB.bagPositions.combined
check(saved and saved.left == 300 and saved.top == 700 and ContainerFrameCombinedBags._userPlaced == false, "position saved")
do -- In gamepad mode the menu stays: closing a Blizzard menu from addon code taints the controller's focus manager.
	local closed = MENUS_CLOSED
	GAMEPAD_STATE.ui = true
	BAG_TITLE_ROUTER._scripts.OnDragStart(BAG_TITLE_ROUTER)
	BAG_TITLE_ROUTER._scripts.OnDragStop(BAG_TITLE_ROUTER)
	GAMEPAD_STATE.ui = false
	check(MENUS_CLOSED == closed, "gamepad mode: dragging doesn't close Blizzard's menu from our code")
	ContainerFrame1:Show()
	UpdateContainerFrameAnchors()
	check(ContainerFrame1._clamped == true, "a bag not moved while another one is: kept on the screen")
	ContainerFrame1:Hide()
end
CloseBags(); OpenBags()
local point, _, _, x, y = ContainerFrameCombinedBags:GetPoint(1)
check(point == "TOPLEFT" and x == 300 and y == 700, "reopens where it was left instead of Blizzard's spot")
MOCK_CONTAINER_SCALE = 0.5
CloseBags(); OpenBags()
point, _, _, x, y = ContainerFrameCombinedBags:GetPoint(1)
check(x == 600 and y == 1400, "same screen spot when Blizzard shrinks the bags (offsets scale with the bag)")
MOCK_CONTAINER_SCALE = nil
CloseBags(); OpenBags()
ContainerFrameCombinedBags._scripts.OnDragStart(ContainerFrameCombinedBags)
ContainerFrameCombinedBags._dropAt = { left = 100, top = 500 }
ContainerFrameCombinedBags._scripts.OnDragStop(ContainerFrameCombinedBags)
check(TDB.bagPositions.combined.left == 100, "dragging an empty spot of the bag works too")
ContainerFrameCombinedBags.IsProtected = function() return true end
STATE.combat = true
ContainerFrameCombinedBags._scripts.OnDragStart(ContainerFrameCombinedBags)
check(not ContainerFrameCombinedBags._moving, "a protected bag isn't moved in combat")
STATE.combat = false
ContainerFrameCombinedBags.IsProtected = nil
T("movableBags"):SetValue(false); Advance(0.05)
check(ContainerFrameCombinedBags:GetPoint(1) == "BOTTOMRIGHT", "switching off puts the bag back at Blizzard's spot")
ContainerFrameCombinedBags._scripts.OnDragStart(ContainerFrameCombinedBags)
check(not ContainerFrameCombinedBags._moving, "and dragging does nothing while off")
T("movableBags"):SetValue(true); Advance(0.05)
point, _, _, x, y = ContainerFrameCombinedBags:GetPoint(1)
check(point == "TOPLEFT" and x == 100 and y == 500, "switching on again restores the saved spot")
lefthy("tweaks resetbags")
check(ContainerFrameCombinedBags:GetPoint(1) == "BOTTOMRIGHT" and next(TDB.bagPositions) == nil, "/lefthy tweaks resetbags")
CloseBags()

section("Misc Tweaks: the bags' clean-up button")
do
	check(TDB.gamepadBagSort == true and T("gamepadBagSort"), "on by default, with a checkbox")
	ContainerFrameCombinedBags:Show()
	ContainerFrameCombinedBags:UpdateSearchBox()
	local p1, rel, p2, x, y = BagItemAutoSortButton:GetPoint(1)
	local s1, srel, s2, sx, sy = BagItemSearchBox:GetPoint(1)
	check(BagItemAutoSortButton:IsShown() and BagItemAutoSortButton:GetParent() == ContainerFrameCombinedBags and p1 == "TOPLEFT"
		and rel == ContainerFrameCombinedBags and x == 38 and y == -34 and sx == 74 and sy == -37 and BagItemSearchBox:GetWidth() == 98,
		"mouse and keyboard (Blizzard hides it since the patch): back, at the left of the search row (the search box moved over)")
	ContainerFrameCombinedBags:UpdateSearchBox()
	ContainerFrameCombinedBags:UpdateSearchBox()
	check(BagItemSearchBox:GetWidth() == 98 and select(4, BagItemSearchBox:GetPoint(1)) == 74, "Blizzard's updates again: still the same, not narrower each time")
	GAMEPAD_STATE.ui = true
	ContainerFrameCombinedBags:UpdateSearchBox()
	check(BagItemAutoSortButton:IsShown() and BagItemAutoSortButton:GetParent() == ContainerFrameCombinedBags, "gamepad mode: there too")
	GAMEPAD_STATE.ui = false
	ContainerFrameCombinedBags:Hide()
	BagItemAutoSortButton:Hide()
	ContainerFrameCombinedBags:Show() -- (opening the bags: also when UpdateSearchBox isn't called)
	check(BagItemAutoSortButton:IsShown(), "opening the bags: there")
	check(select(4, BagItemSearchBox:GetPoint(1)) == 74 and BagItemSearchBox:GetWidth() == 98,
		"opened again without Blizzard placing the search box (Alt+Z, ...): not moved over twice, got "
		.. tostring(select(4, BagItemSearchBox:GetPoint(1))))
	ContainerFrameCombinedBags:Hide()
	lefthy("tweaks bagsort off"); Advance(0.05)
	check(select(4, BagItemSearchBox:GetPoint(1)) == 42 and BagItemSearchBox:GetWidth() == 130,
		"switched off with the bags closed: the search box back too")
	lefthy("tweaks bagsort on"); Advance(0.05)
	ContainerFrameCombinedBags:Show()
	lefthy("tweaks bagsort off"); Advance(0.05)
	check(TDB.gamepadBagSort == false and not BagItemAutoSortButton:IsShown() and BagItemSearchBox:GetWidth() == 130
		and select(4, BagItemSearchBox:GetPoint(1)) == 42, "/lefthy tweaks bagsort off: hidden again, the search box as Blizzard has it")
	ContainerFrameCombinedBags:UpdateSearchBox()
	check(not BagItemAutoSortButton:IsShown(), "... and stays so")
	lefthy("tweaks bagsort on"); Advance(0.05)
	check(BagItemAutoSortButton:IsShown(), "on again: back at once")
	-- A client without Blizzard's button: ours, which cleans up the same way.
	local blizzard = BagItemAutoSortButton
	blizzard:Hide()
	BagItemAutoSortButton = nil
	ContainerFrameCombinedBags:UpdateSearchBox()
	local own = LefthyToolsBagSortButton
	check(own and own:IsShown() and own:GetParent() == ContainerFrameCombinedBags, "no Blizzard button: ours, in the same place")
	local sorted = SORTED_BAGS
	own:Click()
	check(SORTED_BAGS == sorted + 1, "... it cleans up the bags")
	lefthy("tweaks bagsort off"); Advance(0.05)
	check(not own:IsShown(), "off: ours goes too")
	lefthy("tweaks bagsort on"); Advance(0.05)
	BagItemAutoSortButton = blizzard
	ContainerFrameCombinedBags:Hide()
end

section("Misc Tweaks: quest progress in party chat")
check(T("questAnnounce"), "checkbox for quest announcements")
local function QuestUpdate() Fire("QUEST_LOG_UPDATE"); Advance(0.5) end
local function Q(id, title, ...)
	local objectives = {}
	for i, text in ipairs({ ... }) do objectives[i] = { text = text, finished = false } end
	return { id = id, title = title, objectives = objectives }
end
local function Finish(quest, i, text) quest.objectives[i] = { text = text, finished = true } end
GROUP = "party"
QUESTS = {
	Q(101, "Kobold Camp Cleanup", "0/10 Kobold Vermin slain", "0/5 Kobold Workers slain"),
	{ id = 102, title = "Already Done", objectives = { { text = "1/1 Letter delivered", finished = true } } },
}
QuestUpdate()
check(#SENT == 0, "quests seen for the first time stay silent (just accepted, or already done)")
QUESTS[1].objectives[1] = { text = "5/10 Kobold Vermin slain", finished = false }
QuestUpdate()
check(#SENT == 0, "no message for every single kill")
Finish(QUESTS[1], 1, "10/10 Kobold Vermin slain")
QuestUpdate()
check(#SENT == 1 and SENT[1].channel == "PARTY" and SENT[1].msg == "{rt1} [Kobold Camp Cleanup]: 10/10 Kobold Vermin slain",
	"finished objective posted in party chat, got: " .. tostring(SENT[1] and SENT[1].msg))
Finish(QUESTS[1], 2, "5/5 Kobold Workers slain")
QuestUpdate()
check(#SENT == 2 and SENT[2].msg == "{rt1} [Kobold Camp Cleanup]: quest complete!",
	"last objective: one 'quest complete' line instead of the objective")
QuestUpdate()
check(#SENT == 2, "nothing repeated on later updates")

QUESTS[3] = Q(103, "Collapsed Header Quest", "0/1 Thing found")
QuestUpdate()
QUESTS[3].collapsed = true
Finish(QUESTS[3], 1, "1/1 Thing found")
QuestUpdate()
check(#SENT == 3 and SENT[3].msg:find("Collapsed Header Quest", 1, true), "quests under a collapsed header still announce")

GROUP = "none"
QUESTS[4] = Q(104, "Solo Quest", "0/1 X")
QuestUpdate(); Finish(QUESTS[4], 1, "1/1 X"); QuestUpdate()
check(#SENT == 3, "nothing is posted when solo")
GROUP = "raid"
QUESTS[5] = Q(105, "Raid Quest", "0/1 Y")
QuestUpdate(); Finish(QUESTS[5], 1, "1/1 Y"); QuestUpdate()
check(#SENT == 3, "nothing is posted in a raid")
GROUP = "instance"
QUESTS[6] = Q(106, "Dungeon Quest", "0/1 Z")
QuestUpdate(); Finish(QUESTS[6], 1, "1/1 Z"); QuestUpdate()
check(#SENT == 4 and SENT[4].channel == "INSTANCE_CHAT", "instance group uses instance chat")

GROUP = "party"
STATE.chatLockdown = true
QUESTS[7] = Q(107, "Locked Quest", "0/1 W")
QuestUpdate(); Finish(QUESTS[7], 1, "1/1 W"); QuestUpdate()
check(#SENT == 4, "held while the client locks down addon chat")
STATE.chatLockdown = false
Advance(1.2)
check(#SENT == 5 and SENT[5].msg:find("Locked Quest", 1, true), "sent once the lockdown lifts")
STATE.chatLockdown = true -- a lockdown that lasts (a whole dungeon run)
QUESTS[8] = Q(108, "Long Locked Quest", "0/1 V")
QuestUpdate(); Finish(QUESTS[8], 1, "1/1 V"); QuestUpdate()
Advance(15)
STATE.chatLockdown = false
Advance(1.2)
check(#SENT == 5, "a line that waited longer than 10 s is old news: dropped, not sent late")
table.remove(QUESTS, 8)
QuestUpdate()

table.remove(QUESTS, 1) -- turned in
Fire("QUEST_TURNED_IN", 101)
QuestUpdate()
check(#SENT == 5, "turning a quest in doesn't post anything")

lefthy("tweaks quests off"); Advance(0.05)
QUESTS[#QUESTS + 1] = Q(108, "Muted Quest", "0/1 V")
QuestUpdate(); Finish(QUESTS[#QUESTS], 1, "1/1 V"); QuestUpdate()
check(#SENT == 5, "switched off: silent")
lefthy("tweaks quests on"); Advance(0.05)
QuestUpdate()
check(#SENT == 5, "switching on again doesn't re-announce what's already done")
GROUP = "none"

section("Misc Tweaks: combo points")
do
	local PRD = PersonalResourceDisplayFrame
	check(TDB.comboColors == true and TDB.comboNameplate == true and REGISTERED_SETTINGS.LefthyTools_tweaks_comboColors
		and REGISTERED_SETTINGS.LefthyTools_tweaks_comboNameplate and not REGISTERED_SETTINGS.LefthyTools_tweaks_comboPoints,
		"colouring and the nameplate dot on by default, each with a checkbox; our own row is gone (Blizzard has its own)")
	-- Blizzard's bar (the display builds it itself): coloured by count after each of its updates.
	PRD:SetupClassBar()
	local points = PRD.classFrame.classResourceButtonTable
	local function near(texture, r, g, b)
		local v = texture and texture.vertex
		return v and math.abs(v[1] - r) < 0.01 and math.abs(v[2] - g) < 0.01 and math.abs(v[3] - b) < 0.01
	end
	STATE.target, COMBO.points = true, 2
	PRD.classFrame:UpdatePower()
	check(points[1].IconUncharged.desaturated and near(points[1].LefthyToolsBoost, 0.575, 0.95, 0.075)
		and near(points[2].SlashFBUncharged, 0.575, 0.95, 0.075) and near(points[1].IconUncharged, 0.68125, 0.9625, 0.30625)
		and near(points[2].BGActive, 0.68125, 0.9625, 0.30625),
		"2 of 5: Blizzard's gems and their effects tinted yellow-green right after its update (gem and socket a quarter lighter)")
	check(not points[1].BGInactive.desaturated and points[1].BGShadow.vertex == nil, "empty sockets and the shadow keep their look")
	check(points[1].LefthyToolsBoost.blend == "ADD" and points[1].BGGlow.blend == "ADD" and points[1].BGActive.blend == nil,
		"an additive copy of each gem and additive glows keep the colours bright; the socket blends as Blizzard's")
	Advance(0.05)
	check(points[1].LefthyToolsBoost.alpha == 1 and points[3].LefthyToolsBoost.alpha == 0, "the copies follow Blizzard's gems")
	COMBO.points = 5
	PRD.classFrame:UpdatePower()
	check(near(points[1].LefthyToolsBoost, 1, 0.1, 0.05) and near(points[5].LefthyToolsBoost, 1, 0.1, 0.05), "all 5: red")
	COMBO.points = 0
	PRD.classFrame:UpdatePower()
	check(near(points[1].LefthyToolsBoost, 1, 0.1, 0.05), "spent: the gems keep their colour while they burst out")
	lefthy("tweaks combocolors off"); Advance(0.05)
	check(TDB.comboColors == false and not points[1].IconUncharged.desaturated and near(points[1].IconUncharged, 1, 1, 1)
		and not points[1].LefthyToolsBoost.shown and points[1].BGGlow.blend == "BLEND", "/lefthy tweaks combocolors off: Blizzard's red")
	COMBO.points = 1
	PRD.classFrame:UpdatePower()
	check(not points[1].IconUncharged.desaturated, "... and stays so")
	lefthy("tweaks combocolors on"); Advance(0.05)
	check(points[1].IconUncharged.desaturated and near(points[1].LefthyToolsBoost, 0.15, 1, 0.15), "on again: 1 point, green")

	-- Dots in the middle of my target's health bar: one per point the bar can hold, the lit ones
	-- coloured by count, the rest dark sockets; each on a dark ring.
	MOBS.target = { name = "Hogger", level = 11, x = 0.5, y = 0.5 }
	COMBO.points = 3
	Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
	local row = ns.GetComboDots()
	check(not (row and row:IsShown()), "nothing done inside the event")
	Advance(0.05)
	row = ns.GetComboDots()
	local plate = MOBS.target.unitFrame
	local function lit()
		local n = 0
		for i = 1, row.count do if row.dots[i].lit then n = n + 1 end end
		return n
	end
	local function colour(texture, r, g, b, a)
		local c = texture and texture.color
		return c and math.abs(c[1] - r) < 0.01 and math.abs(c[2] - g) < 0.01 and math.abs(c[3] - b) < 0.01
			and (a == nil or math.abs((c[4] or 1) - a) < 0.01)
	end
	local point = row and row._points[#row._points]
	check(row and row:IsShown() and row:GetParent() == plate and point[1] == "CENTER" and point[2] == plate.HealthBarsContainer
		and point[3] == "CENTER" and point[4] == 0 and point[5] == 0 and row.count == 5 and lit() == 3,
		"3 points: five dots in the middle of my target's health bar, three lit")
	plate.HealthBarsContainer.healthBar = CreateFrame("StatusBar", nil, plate.HealthBarsContainer)
	T("comboDotSize"):SetValue(10)
	Advance(0.05)
	point = row._points[#row._points]
	check(point[1] == "CENTER" and point[2] == plate.HealthBarsContainer.healthBar and point[5] == 0 and row:GetHeight() == 10,
		"bigger dots: still centred, on the health bar itself (its container can be taller)")
	T("comboDotSize"):SetValue(6)
	Advance(0.05)
	check(colour(row.dots[1].Fill, 1, 0.9, 0) and colour(row.dots[3].Fill, 1, 0.9, 0) and colour(row.dots[4].Fill, 0.22, 0.22, 0.22, 0.75)
		and colour(row.dots[1].Ring, 0, 0, 0, 0.85), "lit ones yellow (3 of 5), the others dark sockets, each on a dark ring")
	local _, _, _, ringX = row.dots[2].Ring:GetPoint(1)
	check(row:GetWidth() == 5 * 6 + 4 * 3 and row:GetHeight() == 6 and row.dots[1].Ring.width == 6 and row.dots[1].Fill.width == 4
		and ringX == 9, "6 px each, 3 px apart, the ring a pixel wider than the dot all round")
	-- Their size: a slider, and a preview on the target while it moves.
	T("comboDotSize"):SetValue(9)
	Advance(0.05)
	check(TDB.comboDotSize == 9 and row.size == 9 and row:GetWidth() == 5 * 9 + 4 * 5, "the slider: 9 px dots")
	COMBO.points = 0
	Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
	T("comboDotSize"):SetValue(8)
	Advance(0.05)
	check(row:IsShown() and lit() == 5, "moving the slider without points: the dots show a moment (full points), to see them")
	Advance(5.2)
	check(not row:IsShown(), "then they go")
	-- Nameplates coming and going in a crowd: nothing to do while no points wait for the target's.
	local plateLookups, getPlate = 0, C_NamePlate.GetNamePlateForUnit
	C_NamePlate.GetNamePlateForUnit = function(...) plateLookups = plateLookups + 1; return getPlate(...) end
	for i = 1, 20 do
		Fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. i)
		Fire("NAME_PLATE_UNIT_REMOVED", "nameplate" .. i)
	end
	Advance(0.05)
	C_NamePlate.GetNamePlateForUnit = getPlate
	check(plateLookups == 0, "nameplates coming and going without points: nothing looked up, got " .. plateLookups)
	-- The preview: the dots on a stand-in nameplate, without a mob and without the settings.
	local savedTarget = MOBS.target
	MOBS.target = nil
	T("comboDotSize"):SetValue(6)
	lefthy("tweaks combopos")
	local trial = ns.GetComboTrial()
	local dots = trial and trial.Dots
	check(trial and trial:IsShown() and dots.count == 5 and dots.points == 1 and trial.Values:GetText() == "Size 6 px"
		and trial._strata == "FULLSCREEN_DIALOG",
		"/lefthy tweaks combopos: a nameplate with the dots, one lit, no mob needed, got " .. tostring(trial and trial.Values:GetText()))
	Advance(0.85)
	check(dots.points == 2, "they count up")
	Advance(0.8 * 4)
	check(dots.points == 1, "... to full, then from one again")
	trial.Bigger:Click()
	check(TDB.comboDotSize == 7 and dots.size == 7 and trial.Values:GetText() == "Size 7 px", "+: bigger, saved")
	trial.Smaller:Click()
	trial.Smaller:Click()
	check(TDB.comboDotSize == 5, "-: smaller")
	MOBS.target = savedTarget
	Fire("PLAYER_TARGET_CHANGED")
	Advance(6)
	check(row:IsShown() and row.size == 5 and lit() == 5, "a target meanwhile: its nameplate shows the dots too, without points, while it's open")
	trial.Reset:Click()
	check(TDB.comboDotSize == 6, "Reset: back to 6 px")
	trial.Done:Click()
	Advance(0.1)
	check(not trial:IsShown() and not row:IsShown(), "Done: closed; without points no dots")
	COMBO.points = 3
	Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
	Advance(5.3)
	Fire("UNIT_POWER_FREQUENT", "player", "ENERGY")
	COMBO.points = 5
	Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
	Advance(0.05)
	check(lit() == 5 and colour(row.dots[5].Fill, 1, 0.1, 0.05), "5 points: all lit, red")
	lefthy("tweaks combocolors off"); Advance(0.05)
	COMBO.points = 2
	Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
	Advance(0.05)
	check(row:IsShown() and lit() == 2 and colour(row.dots[1].Fill, 1, 0.1, 0.05), "colouring off: Blizzard's red")
	lefthy("tweaks combocolors on"); Advance(0.05)
	check(colour(row.dots[1].Fill, 0.575, 0.95, 0.075), "on again: 2 of 5, yellow-green")
	MOBS.target.x = nil -- (its nameplate gone: off screen)
	Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
	Advance(0.05)
	check(not row:IsShown(), "my target without a nameplate: no dots")
	MOBS.target.x = 0.5
	Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
	Advance(0.05)
	check(row:IsShown(), "its nameplate back: the dots too")
	COMBO.points = 0
	Fire("PLAYER_TARGET_CHANGED")
	Advance(0.05)
	check(not row:IsShown(), "no points: no dots")
	COMBO.points = SECRET
	Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
	Advance(0.05)
	check(not row:IsShown(), "secret points: no dots, no error")
	COMBO.points = 2
	lefthy("tweaks combo off"); Advance(0.05)
	Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
	Advance(0.05)
	check(TDB.comboNameplate == false and not row:IsShown(), "/lefthy tweaks combo off: no dots")
	lefthy("tweaks combo on"); Advance(0.05)
	check(row:IsShown(), "/lefthy tweaks combo on")
	MOBS, COMBO.points, STATE.target = {}, 0, false
	Fire("PLAYER_TARGET_CHANGED")
	Advance(0.05)
end

section("Misc Tweaks: retail unit frames")
;(function() -- (a function of its own: the main chunk's 200 locals)
	check(TDB.retailFrames == false and T("retailFrames"), "off by default (friends keep Forever's look), with a checkbox")
	local ART, BARS = ns.RETAIL_FRAME_ART, ns.RETAIL_FRAME_BARS
	local function Tex(parent, atlas, mask)
		local t = mask and parent:CreateMaskTexture() or parent:CreateTexture()
		t:SetAtlas(atlas, true) -- (XML: useAtlasSize)
		return t
	end
	local function Bar(parent, atlas)
		local b = CreateFrame("StatusBar", nil, parent)
		b:SetStatusBarTexture(atlas)
		return b
	end
	local function last(region)
		local p = region._points or region.points or {}
		return p[#p] or {}
	end
	local function retail(texture, atlas)
		local art = ART[atlas:lower()]
		return art and texture.path == art[1] and texture.coords and texture.coords[1] == art[2] and texture.coords[4] == art[5]
			and texture.width == art[6] and texture.height == art[7]
	end
	-- The player and target frames as Forever builds them: its classic art set and its own layout.
	PlayerFrame.unit = "player"
	local box = CreateFrame("Frame", nil, PlayerFrame)
	PlayerFrame.PlayerFrameContainer = box
	local playerArt = Tex(box, "UI-HUD-UnitFrame-Player-PortraitOn")
	box.FrameFlash = Tex(box, "UI-HUD-UnitFrame-Player-PortraitOn-InCombat")
	PlayerFrame.PlayerFrameContent = CreateFrame("Frame", nil, PlayerFrame)
	local main = CreateFrame("Frame", nil, PlayerFrame.PlayerFrameContent)
	PlayerFrame.PlayerFrameContent.PlayerFrameContentMain = main
	main.StatusTexture = Tex(main, "UI-HUD-UnitFrame-Player-PortraitOn-Status")
	main.LevelBackgroundCircle = Tex(main, "UI-HUD-UnitFrame-SmallCircle")
	local health = CreateFrame("Frame", nil, main)
	main.HealthBarsContainer = health
	health.HealthBar = Bar(health, "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health")
	health.HealthBarMask = Tex(health, "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health-Mask", true)
	main.ManaBar = Bar(main, "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana")
	main.ManaBar.ManaBarMask = Tex(main.ManaBar, "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana-Mask", true)
	PlayerLevelText, PlayerName = main:CreateFontString(), main:CreateFontString()
	function PlayerFrame_UpdateHealthBarVisuals()
		health:SetHeight(15)
		health:SetPoint("TOPLEFT", 87, -46)
		health.HealthBar:ClearAllPoints()
		health.HealthBar:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 3)
	end
	function PlayerFrame_UpdateLevel() PlayerLevelText:SetVertexColor(1, 1, 1, 1) end
	PlayerFrame_UpdateHealthBarVisuals()
	TargetFrame.unit = "target"
	TargetFrame.TargetFrameContainer = CreateFrame("Frame", nil, TargetFrame)
	local targetArt = Tex(TargetFrame.TargetFrameContainer, "UI-HUD-UnitFrame-Target-PortraitOn")
	TargetFrame.TargetFrameContainer.Flash = Tex(TargetFrame.TargetFrameContainer, "UI-HUD-UnitFrame-Target-PortraitOn-InCombat")
	TargetFrame.TargetFrameContent = CreateFrame("Frame", nil, TargetFrame)
	local tMain = CreateFrame("Frame", nil, TargetFrame.TargetFrameContent)
	TargetFrame.TargetFrameContent.TargetFrameContentMain = tMain
	local contextual = CreateFrame("Frame", nil, TargetFrame.TargetFrameContent)
	TargetFrame.TargetFrameContent.TargetFrameContentContextual = contextual
	contextual.HighLevelTexture = Tex(contextual, "UI-HUD-UnitFrame-Target-HighLevelTarget_Icon")
	tMain.ReputationColor = Tex(tMain, "UI-HUD-UnitFrame-Target-PortraitOn-Type")
	tMain.Name, tMain.LevelText = tMain:CreateFontString(), tMain:CreateFontString()
	tMain.LevelBackgroundCircle = Tex(tMain, "UI-HUD-UnitFrame-SmallCircle")
	local tHealth = CreateFrame("Frame", nil, tMain)
	tMain.HealthBarsContainer = tHealth
	tHealth.HealthBar = Bar(tHealth, "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health")
	tHealth.HealthBar.HealthBarTexture = tHealth.HealthBar:GetStatusBarTexture()
	tHealth.HealthBarMask = Tex(tHealth, "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health-Mask", true)
	tMain.ManaBar = Bar(tMain, "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Mana")
	tMain.ManaBar.RightText = tMain:CreateFontString()
	function TargetFrame:UpdateHealthBarVisuals() -- (Forever's, on every new target)
		tHealth:SetHeight(15)
		tHealth:SetPoint("BOTTOMRIGHT", self.TargetFrameContainer, "LEFT", 147, -9)
		tHealth.HealthBar.HealthBarTexture:SetAtlas("UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health", true)
	end

	-- Like the game: a bar's fill keeps its size secret (its width is the health), and so do textures
	-- anchored to one.
	health.HealthBar:GetStatusBarTexture().width = SECRET
	contextual.HighLevelTexture.width = SECRET
	local errorsBefore = LT.Errors.Count()
	lefthy("tweaks retailframes on"); Advance(0.05)
	local highLevel = ART["ui-hud-unitframe-target-highleveltarget_icon"]
	check(LT.Errors.Count() == errorsBefore and Tweaks:IsTweakActive("retailFrames") and contextual.HighLevelTexture.path == highLevel[1]
		and contextual.HighLevelTexture.width == SECRET, "secret sizes: no error, the art still retail's (not resized: it isn't the atlas's size)")
	check(TDB.retailFrames == true and retail(playerArt, "UI-HUD-UnitFrame-Player-PortraitOn")
		and retail(targetArt, "UI-HUD-UnitFrame-Target-PortraitOn") and retail(box.FrameFlash, "UI-HUD-UnitFrame-Player-PortraitOn-InCombat"),
		"on: the frames' art is retail's again (its file, texture coordinates and size)")
	check(health.HealthBar:GetStatusBarTexture().atlas == BARS["ui-hud-unitframe-player-portraiton-bar-health"]
		and main.ManaBar:GetStatusBarTexture().atlas == BARS["ui-hud-unitframe-player-portraiton-bar-mana"]
		and not health.HealthBar:GetStatusBarTexture().coords,
		"status bar fills: an atlas with retail's bar art (the bar crops it itself)")
	local mask = health.HealthBarMask
	check(mask.path == ART["ui-hud-unitframe-player-portraiton-bar-health-mask"][1] and mask.wrap == "CLAMPTOBLACKADDITIVE",
		"masks: retail's mask file")
	check(not main.LevelBackgroundCircle.shown and main.LevelBackgroundCircle.atlas == "UI-HUD-UnitFrame-SmallCircle"
		and last(PlayerLevelText)[1] == "TOPRIGHT" and last(PlayerLevelText)[4] == -24.5 and PlayerLevelText.justifyH == "RIGHT"
		and last(PlayerName)[4] == 88 and PlayerName.width == 96,
		"player: Forever's level circle hidden (no retail art for it), level and name where retail has them")
	check(last(health)[2] == 85 and last(health)[3] == -41 and health:GetHeight() == 19 and last(health.HealthBar)[4] == 0
		and last(health.HealthBar)[5] == 0, "player: the health bar where retail's art has its slot")
	PlayerFrame_UpdateLevel()
	check(PlayerLevelText.vertex[2] == 0.82, "the level in retail's gold (Forever's is white)")
	check(last(tMain.Name)[2] == tMain.ReputationColor and last(tMain.Name)[4] == -106 and last(tMain.LevelText)[4] == -133
		and not tMain.LevelBackgroundCircle.shown and last(tHealth)[4] == 149 and tHealth:GetHeight() == 20,
		"target: name, level and health bar where retail has them")
	-- Forever's code places things again (a new target, a vehicle): retail's again after it.
	PlayerFrame_UpdateHealthBarVisuals()
	TargetFrame:UpdateHealthBarVisuals("normal")
	check(last(health)[2] == 85 and health:GetHeight() == 19 and last(tHealth)[4] == 149 and tHealth:GetHeight() == 20
		and tHealth.HealthBar:GetStatusBarTexture().atlas == BARS["ui-hud-unitframe-target-portraiton-bar-health"],
		"Forever's layout runs again: retail's right after it")
	main.StatusTexture:SetAtlas("UI-HUD-UnitFrame-Player-PortraitOn-Status", true)
	main.ManaBar:SetStatusBarTexture("UI-HUD-UnitFrame-Player-PortraitOn-Bar-Rage")
	check(retail(main.StatusTexture, "UI-HUD-UnitFrame-Player-PortraitOn-Status")
		and main.ManaBar:GetStatusBarTexture().atlas == BARS["ui-hud-unitframe-player-portraiton-bar-rage"],
		"art set later (a status flash, another power type): retail's too")
	-- In combat bars can't be moved (protected): they follow when it ends.
	STATE.combat = true
	TargetFrame:UpdateHealthBarVisuals("normal")
	check(last(tHealth)[4] == 147 and ns.RetailFramesPending() and tHealth.HealthBarMask.path,
		"a new target in combat: Forever's bar position for now (the art still retail's)")
	LeaveCombat()
	check(last(tHealth)[4] == 147, "nothing moved inside the event")
	Advance(0.05)
	check(last(tHealth)[4] == 149 and not ns.RetailFramesPending(), "combat over: retail's position, on the next frame")
	do -- Roster changes come in bursts (a group forming): the party frames are looked at once, on the next frame.
		local member = CreateFrame("Frame")
		PartyFrame = CreateFrame("Frame")
		member:SetParent(PartyFrame)
		PartyFrame._children = { member }
		PartyFrame.PartyMemberFramePool = { EnumerateActive = function() return pairs({ [member] = true }) end }
		local art = Tex(member, "UI-HUD-UnitFrame-CharacterFrameOnParty-PortraitOn")
		local walks, regions = 0, member.GetRegions
		member.GetRegions = function(self) walks = walks + 1; return regions(self) end
		for _ = 1, 5 do Fire("GROUP_ROSTER_UPDATE") end
		check(walks == 0 and not art.path, "a new party member: nothing done inside the events")
		Advance(0.05)
		check(walks == 1 and retail(art, "UI-HUD-UnitFrame-CharacterFrameOnParty-PortraitOn"),
			"on the next frame its frame gets retail's art, looked at once for the five events, got " .. walks)
		PartyFrame = nil
	end
	local printedAt = #PRINTED + 1
	lefthy("tweaks retailframes off"); Advance(0.05)
	check(TDB.retailFrames == false and table.concat(PRINTED, "\n", printedAt):find("/reload", 1, true), "off: a /reload brings Forever's frames back")
	PlayerFrame_UpdateHealthBarVisuals()
	check(last(health)[2] == 87, "and nothing is changed any more")
	PlayerFrame_UpdateHealthBarVisuals, PlayerFrame_UpdateLevel, PlayerLevelText, PlayerName = nil, nil, nil, nil
end)()

section("Misc Tweaks: quests that are new in WoW: Forever")
check(TDB.foreverQuests == true and REGISTERED_SETTINGS.LefthyTools_tweaks_foreverQuests, "on by default, with a checkbox")
check(ns.IsForeverQuest(86574) and ns.IsForeverQuest(99411) and not ns.IsForeverQuest(86575)
	and not ns.IsForeverQuest(176) and not ns.IsForeverQuest(8193), "the generated list: Forever's own quests, not Classic ones")
check(ns.IsMarkedQuest(86574) and ns.IsMarkedQuest(77568) and ns.IsMarkedQuest(55296) and not ns.IsMarkedQuest(176)
	and not ns.IsMarkedQuest(8193) and not ns.IsMarkedQuest(86575),
	"later Classic quests (Season of Discovery and the like, in Forever's client too) get the marker as well")
check(not ns.IsForeverQuest(77568), "... but don't count as new in Forever (Chronicle's statistic)")
local MARK = " |cff4de1ffNEW|r"
local savedQuests = QUESTS
local hogger = { id = 176, title = "Wanted: Hogger", objectives = {} }
local foreverQuest = { id = 86574, title = "A Forever quest", objectives = {} }
QUESTS = { hogger, foreverQuest }
QuestLogQuests_Update()
local function titleButton(id) for _, b in ipairs(QUEST_LOG_BUTTONS) do if b.questID == id then return b end end end
check(titleButton(86574).Text:GetText() == "A Forever quest" .. MARK, "quest log: NEW right after the Forever quest's name")
check(titleButton(176).Text:GetText() == "Wanted: Hogger", "... nothing on a Classic quest")
QUESTS = { foreverQuest, hogger } -- the pool hands the buttons out in a different order
QuestLogQuests_Update()
check(titleButton(86574).Text:GetText() == "A Forever quest" .. MARK and titleButton(176).Text:GetText() == "Wanted: Hogger",
	"reused title buttons: the marker follows the quest")
local forButton = titleButton(86574)
GameTooltip:SetOwner(forButton); TOOLTIP.shown = true -- Blizzard's own OnEnter shows the quest tooltip
forButton._scripts.OnEnter(forButton)
check(table.concat(TOOLTIP.lines, "|"):find("New in WoW: Forever", 1, true), "hovering the quest adds a line explaining NEW")
GameTooltip:Hide()
local seasonQuest = { id = 77568, title = "A season quest", objectives = {} }
QUESTS = { seasonQuest }
QuestLogQuests_Update()
local seasonButton = titleButton(77568)
check(seasonButton.Text:GetText() == "A season quest" .. MARK, "a later Classic quest: NEW too")
GameTooltip:SetOwner(seasonButton); TOOLTIP.shown = true
seasonButton._scripts.OnEnter(seasonButton)
local seasonTip = table.concat(TOOLTIP.lines, "|")
check(seasonTip:find("Not in the original Classic", 1, true) and not seasonTip:find("New in WoW: Forever", 1, true),
	"... and its tooltip says where it's from")
GameTooltip:Hide()
QUESTS = { foreverQuest, hogger }
QuestLogQuests_Update()
-- A title that would need another line with the marker: Blizzard already sized the entry.
local longQuest = { id = 86576, title = string.rep("x", 31), objectives = {} } -- 31 chars = 1 line, +4 = 2
QUESTS = { longQuest }
QuestLogQuests_Update()
local spare = ns.GetForeverQuestLabels()[titleButton(86576)]
check(titleButton(86576).Text:GetText() == longQuest.title and spare and spare:IsShown(),
	"a long title keeps its line count: NEW goes to the free spot at the end of the entry instead")
QUESTS = { foreverQuest }
QuestLogQuests_Update()
check(not spare:IsShown() and titleButton(86574).Text:GetText() == "A Forever quest" .. MARK,
	"that spare label goes away when the button shows another quest")
-- Details in the quest log, and the quest window.
SELECTED_QUEST = 86574
QuestInfo_Display({ questLog = true })
check(QuestInfoTitleHeader:GetText() == "A Forever quest" .. MARK, "quest details in the log: NEW after the title")
QUESTS = { hogger, foreverQuest }
DIALOG_QUEST = 176
QuestInfo_Display({ questLog = false })
check(QuestInfoTitleHeader:GetText() == "Wanted: Hogger", "quest window, Classic quest: no marker")
DIALOG_QUEST = 86574
QuestInfo_Display({ questLog = false })
check(QuestInfoTitleHeader:GetText() == "A Forever quest" .. MARK, "quest window, accepting or turning in a Forever quest: NEW")
QuestFrameProgressPanel:Show()
check(QuestProgressTitleText:GetText() == "A Forever quest" .. MARK, "... also on the progress page")
QuestFrameProgressPanel:Hide()
lefthy("tweaks newquests off"); Advance(0.05)
check(TDB.foreverQuests == false and titleButton(86574).Text:GetText() == "A Forever quest"
	and QuestInfoTitleHeader:GetText() == "A Forever quest", "/lefthy tweaks newquests off: the open log and window lose the marker")
QuestLogQuests_Update()
QuestInfo_Display({ questLog = false })
check(titleButton(86574).Text:GetText() == "A Forever quest" and QuestInfoTitleHeader:GetText() == "A Forever quest",
	"... and stay unmarked")
lefthy("tweaks newquests on"); Advance(0.05)
check(titleButton(86574).Text:GetText() == "A Forever quest" .. MARK, "on again: the open quest log is marked right away")
DIALOG_QUEST, SELECTED_QUEST = nil, nil
QUESTS = savedQuests

section("Misc Tweaks: module switch and /lefthy tweaks")
REGISTERED_SETTINGS.LefthyTools_module_tweaks:SetValue(false); Advance(0.05)
check(not Tweaks.enabled and CVARS.statusText == "0" and CVARS.statusTextDisplay == "PERCENT",
	"disabling the module undoes its tweaks")
check(not (ns.GetComboDots() and ns.GetComboDots():IsShown()), "including the combo points' dots")
lefthy("enable tweaks"); Advance(0.05)
check(Tweaks.enabled and CVARS.statusText == "1", "enabling re-applies them")
lefthy("tweaks statustext off"); Advance(0.05)
check(CVARS.statusText == "0" and TDB.statusText == false and REGISTERED_SETTINGS.LefthyTools_tweaks_statusText.uiUpdates > 0,
	"/lefthy tweaks statustext off, through the setting (an open settings page follows)")
lefthy("tweaks statustext on"); Advance(0.05)
check(CVARS.statusText == "1", "/lefthy tweaks statustext on")
local statusMark = #PRINTED + 1
lefthy("tweaks status")
local helpMark = #PRINTED + 1
lefthy("tweaks help")
local helpText, missingWords = table.concat(PRINTED, "\n", helpMark), {}
for i = statusMark, helpMark - 1 do
	local word = PRINTED[i]:match("%((%w+)%)$")
	if word and not helpText:find(word, 1, true) then missingWords[#missingWords + 1] = word end
end
check(helpMark - statusMark >= 8 and #missingWords == 0,
	"/lefthy tweaks help names every tweak's word, missing: " .. table.concat(missingWords, ", "))
check(Mirage.enabled, "Mirage is unaffected by the tweaks module")

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

section("Misc Tweaks: who has aggro, on enemy nameplates")
;(function()
	local function tagText(unit) local t = ns.GetAggroTag(unit); return t and t:IsShown() and t.Text:GetText() or nil end
	local function same(unit, r, g, b)
		local t = ns.GetAggroTag(unit)
		local c = t and t.Text.color
		return c ~= nil and math.abs(c[1] - r) < 0.01 and math.abs(c[2] - g) < 0.01 and math.abs(c[3] - b) < 0.01
	end
	check(LefthyToolsDB.settings.tweaks.aggroNameplate == true, "on by default")
	-- A party: me (the tank), Annabelle (healer), Ölrik (damage), two mobs fighting us.
	GROUP = "party"
	PARTY.party1 = { name = "Annabelle", guid = "Player-1-31" }
	PARTY.party2 = { name = "Ölrik", guid = "Player-1-32" }
	ROLES = { player = "TANK", party1 = "HEALER", party2 = "DAMAGER" }
	MOBS.nameplate1 = { name = "Defias Thug", guid = "Creature-0-1-0-1-120-00000001", combat = true, attacking = true,
		x = 0.5, y = 0.5, pinned = true }
	MOBS.nameplate2 = { name = "Defias Thug", guid = "Creature-0-1-0-1-120-00000002", combat = true, targetGUID = "Player-1-32",
		x = 0.6, y = 0.5, pinned = true }
	THREAT.nameplate1, THREATS["party2>nameplate2"] = 3, 3
	Fire("GROUP_ROSTER_UPDATE")
	Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
	Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
	Advance(0.1)
	local tag = ns.GetAggroTag("nameplate1")
	check(tagText("nameplate1") == ">YOU<" and same("nameplate1", 0.35, 0.62, 1) and tag:GetParent() == MOBS.nameplate1.unitFrame
		and select(1, tag:GetPoint(1)) == "LEFT", "on me: >YOU< in my role's colour (tank blue), at the left end of its health bar")
	check(tagText("nameplate2") == "Ölr" and same("nameplate2", 1, 0.32, 0.26),
		"on a damage dealer: the first three letters of the name (whole letters), red")
	-- Its target is the healer, but I'm the one tanking it (a spell at her): me.
	MOBS.nameplate2.targetGUID = "Player-1-31"
	THREATS["party1>nameplate2"], THREATS["party2>nameplate2"], THREAT.nameplate2 = 1, 0, 3
	Fire("UNIT_TARGET", "nameplate2")
	Advance(0.1)
	check(tagText("nameplate2") == ">YOU<", "its target isn't tanking it (a spell at the healer): whoever is, me")
	THREATS["party1>nameplate2"], THREAT.nameplate2 = 3, 1
	Fire("UNIT_THREAT_LIST_UPDATE", "nameplate2")
	Advance(0.1)
	check(tagText("nameplate2") == "Ann" and same("nameplate2", 0.3, 0.95, 0.4), "the healer has it: Ann, green")
	-- No roles (a group made by hand): white; a bear is a tank anyway.
	ROLES = {}
	Fire("PLAYER_ROLES_ASSIGNED")
	Advance(0.1)
	check(same("nameplate2", 0.92, 0.92, 0.92), "no roles: white")
	AURAS.party1 = { ["Bear Form"] = true, [C_Spell.GetSpellInfo(5487).name] = true } -- (other tests rename spells)
	EnterCombat() -- (roles are guessed again when a fight starts)
	Advance(0.1)
	check(same("nameplate2", 0.35, 0.62, 1), "in Bear Form: a tank")
	LeaveCombat()
	AURAS.party1 = nil
	-- Threat secret and its target not known: nothing said.
	THREATS["party1>nameplate2"], THREAT.nameplate2, MOBS.nameplate2.targetGUID = SECRET, SECRET, nil
	Fire("UNIT_THREAT_LIST_UPDATE", "nameplate2")
	Advance(0.1)
	check(tagText("nameplate2") == nil, "nothing readable: no tag")
	-- Someone outside the group (an escort): grey.
	MOBS.nameplate2.targetGUID, MOBS.nameplate2.targetName = "Creature-0-1-0-1-467-00000009", "The Defias Traitor"
	Fire("UNIT_TARGET", "nameplate2")
	Advance(0.1)
	check(tagText("nameplate2") == "The" and same("nameplate2", 0.6, 0.6, 0.6), "on someone outside the group: grey")
	-- Out of combat, or solo: nothing.
	MOBS.nameplate2.combat = false
	Fire("UNIT_FLAGS", "nameplate2")
	Advance(0.1)
	check(tagText("nameplate2") == nil, "a mob out of combat: no tag")
	GROUP = "none"
	Fire("GROUP_ROSTER_UPDATE")
	Advance(0.1)
	check(tagText("nameplate1") == nil, "solo: no tags")
	-- While I'm in combat in a group it looks again twice a second, also without events.
	GROUP = "party"
	EnterCombat()
	Advance(0.1)
	check(tagText("nameplate1") == ">YOU<", "in a group again: back")
	MOBS.nameplate1.attacking, THREAT.nameplate1, THREATS["party2>nameplate1"] = false, 0, 3
	MOBS.nameplate1.targetGUID = "Player-1-32"
	Advance(0.6)
	check(tagText("nameplate1") == "Ölr", "no event, but in combat: seen within half a second")
	LeaveCombat()
	EnterCombat() -- (inside PLAYER_REGEN_DISABLED the combat lockdown hasn't begun yet, like in the game)
	Advance(0.1)
	MOBS.nameplate1.targetGUID, THREATS["party1>nameplate1"] = "Player-1-31", 3
	Advance(0.6)
	check(tagText("nameplate1") == "Ann", "a fight starting: the half-second looks begin (combat taken from the event)")
	LeaveCombat()
	THREATS["party1>nameplate1"] = nil
	-- The examples: each enemy nameplate another one, for ten seconds.
	local pmark = #PRINTED + 1
	lefthy("tweaks aggrotest")
	Advance(0.1)
	check(printedSince(pmark):find("2 enemy nameplate", 1, true) and tagText("nameplate1") == ">YOU<" and tagText("nameplate2") == "Ann",
		"/lefthy tweaks aggrotest: examples on the enemy nameplates in sight")
	Advance(10.2)
	check(tagText("nameplate2") == nil, "ten seconds later: the real thing again")
	-- The role check: Blizzard's, for the whole group.
	pmark = #PRINTED + 1
	lefthy("tweaks rolecheck")
	check(ROLE_POLLS == 1 and printedSince(pmark):find("role check started", 1, true), "/lefthy tweaks rolecheck: Blizzard's role check")
	ROLE_POLL_OK = false
	pmark = #PRINTED + 1
	lefthy("tweaks rolecheck")
	check(printedSince(pmark):find("only the group's leader or an assistant", 1, true), "not the leader: said so")
	ROLE_POLL_OK = true
	-- Switched off: every tag goes.
	lefthy("tweaks aggro off")
	Advance(0.1)
	check(tagText("nameplate1") == nil, "switched off: no tags")
	lefthy("tweaks aggro on")
	Advance(0.1)
	Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
	Fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
	GROUP, PARTY.party1, PARTY.party2, ROLES, MOBS.nameplate1, MOBS.nameplate2 = "none", nil, nil, {}, nil, nil
	THREAT.nameplate1, THREAT.nameplate2, THREATS = nil, nil, {}
	Fire("GROUP_ROSTER_UPDATE")
	Advance(0.1)
end)()
