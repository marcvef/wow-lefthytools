-- Misc Tweaks: movable loot rolls (LootRolls.lua): Blizzard's spot while nothing is saved, a dragged roll
-- moving them all, the spot kept and used for the next rolls, placing without a roll, reset, off, the controller.
-- Needs: no other file.

local suite = ...
local check, section, LT, lefthy = suite.check, suite.section, suite.LT, suite.lefthy

section("Misc Tweaks: movable loot rolls")
do
	local M = LT:GetModule("tweaks")
	local function T(key) return REGISTERED_SETTINGS["LefthyTools_tweaks_" .. key] end
	local container = GroupLootContainer
	local function At(frame) local _, rel, _, x, y = frame:GetPoint(1); return rel, x, y end
	check(M.db.movableLootRolls == true and T("movableLootRolls") and M.db.lootRollPos == nil, "on by default, with a checkbox, no spot yet")

	-- A roll: on Blizzard's spot while nothing is saved.
	local first, second = GroupLootFrame1, GroupLootFrame2
	GroupLootContainer_AddFrame(container, first)
	local rel, x, y = At(first)
	check(rel == container and x == 0 and y == 50, "a roll with nothing saved: Blizzard's spot")
	check(first._dragButtons and first._dragButtons[1] == "LeftButton" and first:GetScript("OnDragStart"), "it can be dragged")

	-- Dragged: the anchor moves, the spot is kept, the roll sits on it.
	first:GetScript("OnDragStart")(first)
	local anchor = LefthyToolsLootRollAnchor
	check(anchor and anchor._moving, "dragging a roll moves our anchor")
	anchor._dropAt = { left = 300, top = 640 }
	first:GetScript("OnDragStop")(first)
	local pos = M.db.lootRollPos
	rel, x, y = At(first)
	check(pos and pos.left == 300 and pos.top == 640 and rel == anchor and x == 0 and y == 0,
		"dropped: the spot saved, the roll at the anchor's bottom")
	GroupLootContainer_AddFrame(container, second)
	rel, x, y = At(second)
	check(rel == anchor and y == 100 and select(2, At(first)) == 0, "the next roll stacked above it, 100 apart, as Blizzard does")
	GroupLootContainer_RemoveFrame(container, first)
	check(select(1, At(second)) == anchor, "a roll gone: the rest stay on our spot")

	-- Placing without a roll.
	lefthy("tweaks lootpos")
	check(anchor.Label:IsShown() and anchor:IsMouseEnabled(), "/lefthy tweaks lootpos: the spot shown, to drag")
	anchor:GetScript("OnMouseUp")(anchor, "RightButton")
	check(not anchor.Label:IsShown() and not anchor:IsMouseEnabled(), "right-click: hidden again, out of the way")

	-- Reset, off, the controller: Blizzard's spot.
	lefthy("tweaks resetloot")
	rel, x, y = At(second)
	check(M.db.lootRollPos == nil and rel == container and y == 150, "reset: back on Blizzard's spot")
	first:GetScript("OnDragStart")(first)
	anchor._dropAt = { left = 200, top = 500 }
	first:GetScript("OnDragStop")(first)
	check(select(1, At(second)) == anchor, "dragged again: ours")
	lefthy("tweaks lootrolls off")
	Advance(1)
	check(M.db.movableLootRolls == false and select(1, At(second)) == container, "switched off: Blizzard's spot, the saved one kept")
	lefthy("tweaks lootrolls on")
	Advance(1)
	check(select(1, At(second)) == anchor, "on again: ours")
	GAMEPAD_STATE.ui = true
	GroupLootContainer_AddFrame(container, GroupLootFrame3)
	check(GroupLootFrame3:GetPoint(1) == nil, "the controller UI: Blizzard's own roll window, nothing done")
	GAMEPAD_STATE.ui = false

	-- Back as it was.
	container.rollFrames, container.maxIndex = {}, 0
	M:ResetLootRolls()
end
