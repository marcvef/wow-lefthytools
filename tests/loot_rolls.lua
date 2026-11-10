-- Misc Tweaks: movable loot rolls (LootRolls.lua): the controller's roll window made movable and its spot
-- kept; with mouse and keyboard, a dragged roll moving them all, the spot kept and used for the next rolls;
-- reset, off.
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

	-- The controller UI: Blizzard's roll window, which has drag scripts but wasn't movable.
	local pad = GamepadGroupLootRollFrame
	check(pad._movable == true and pad._dragButtons and pad._dragButtons[1] == "LeftButton", "the controller's roll window: movable, dragged with the mouse")
	pad:GetScript("OnDragStart")(pad)
	check(pad._moving, "dragging it moves it (Blizzard's own OnDragStart)")
	pad._dropAt = { left = 120, top = 700 }
	pad:GetScript("OnDragStop")(pad)
	check(M.db.lootRollPadPos and M.db.lootRollPadPos.left == 120 and M.db.lootRollPadPos.top == 700, "dropped: its spot kept")
	pad:Hide()
	pad:ClearAllPoints()
	pad:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 38, -347) -- (a /reload: Blizzard's XML spot)
	pad:Show() -- (a roll comes)
	local rel, x, y = At(pad)
	check(rel == UIParent and x == 120 and y == 700, "shown again: on its kept spot")
	pad:Hide()

	-- Mouse and keyboard: a roll on Blizzard's spot while nothing is saved.
	local first, second = GroupLootFrame1, GroupLootFrame2
	GroupLootContainer_AddFrame(container, first)
	rel, x, y = At(first)
	check(rel == container and x == 0 and y == 50, "a roll with nothing saved: Blizzard's spot")
	check(first._dragButtons and first._dragButtons[1] == "LeftButton" and first:GetScript("OnDragStart"), "it can be dragged")
	-- Dragged (its spot read as the drag starts): the anchor moves, the spot is kept, the roll sits on it.
	first._points = { { "TOPLEFT", UIParent, "BOTTOMLEFT", 500, 300 } }
	first:GetScript("OnDragStart")(first)
	local anchor = LefthyToolsLootRollAnchor
	check(anchor and anchor._moving, "dragging a roll moves our anchor")
	anchor._dropAt = { left = 300, top = 640 }
	first:GetScript("OnDragStop")(first)
	local pos = M.db.lootRollPos
	rel, x, y = At(first)
	check(pos and pos.left == 300 and pos.top == 640 and rel == anchor and x == 0 and y == 0,
		"dropped: the spot kept, the roll at the anchor's bottom")
	GroupLootContainer_AddFrame(container, second)
	rel, x, y = At(second)
	check(rel == anchor and y == 100, "the next roll stacked above it, 100 apart, as Blizzard does")
	GroupLootContainer_RemoveFrame(container, first)
	check(select(1, At(second)) == anchor, "a roll gone: the rest stay on our spot")

	-- Reset and off: Blizzard's spots.
	lefthy("tweaks resetloot")
	rel, x, y = At(second)
	check(M.db.lootRollPos == nil and M.db.lootRollPadPos == nil and rel == container and y == 150, "/lefthy tweaks resetloot: Blizzard's spot")
	rel, x, y = At(pad)
	check(rel == UIParent and x == 38 and y == -347, "... and the controller's window back on its own")
	second._points = { { "TOPLEFT", UIParent, "BOTTOMLEFT", 500, 300 } }
	second:GetScript("OnDragStart")(second)
	anchor._dropAt = { left = 200, top = 500 }
	second:GetScript("OnDragStop")(second)
	check(select(1, At(second)) == anchor, "dragged again: ours")
	lefthy("tweaks lootrolls off")
	Advance(1)
	check(M.db.movableLootRolls == false and select(1, At(second)) == container and not pad._movable,
		"switched off: Blizzard's spot, the controller's window not movable, the saved spot kept")
	lefthy("tweaks lootrolls on")
	Advance(1)
	check(select(1, At(second)) == anchor and pad._movable, "on again: ours")

	-- Back as it was.
	container.rollFrames, container.maxIndex = {}, 0
	M:ResetLootRolls()
end
