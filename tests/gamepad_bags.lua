-- Misc Tweaks: the bags with a controller: the bag buttons in a row, the items in sorted sections, the
-- tooltip beside the bag, SmartNavigation told (never in a fight), mouse and keyboard untouched, the setting.
-- Needs: no other file.
local suite = ...
local check, section, ns, LT, lefthy = suite.check, suite.section, suite.ns, suite.LT, suite.lefthy

section("Misc Tweaks: the bags with a controller")
do
	local M = LT:GetModule("tweaks")
	local bag = ContainerFrameCombinedBags
	local function T(key) return REGISTERED_SETTINGS["LefthyTools_tweaks_" .. key] end
	local waited = 0
	local function Wait(s) Advance(s); waited = waited + s end
	local function State() return ns.GamepadBagsState() end
	check(M.db.gamepadBags == true and T("gamepadBags"), "on by default, with a checkbox")
	check(M.db.gamepadBagButtons == false and M.db.gamepadBagAllFree == false and T("gamepadBagButtons") and T("gamepadBagAllFree"),
		"by default the backpack's button alone and one free slot for all, each with a checkbox")
	-- Every bag button and free slot for the checks below (the defaults are checked further down).
	M.db.gamepadBagButtons, M.db.gamepadBagAllFree = true, true

	-- Two bags: the mock's 16 slots of the backpack and 8 of bag 1.
	local made = {}
	for slot = 1, 8 do
		local b = CreateFrame("Button", nil, bag)
		b:SetSize(37, 37)
		b:SetID(slot)
		function b:GetBagID() return 1 end
		bag.buttons[#bag.buttons + 1] = b
		made[#made + 1] = b
	end
	local function Slot(bagID, slot)
		for _, b in ipairs(bag.buttons) do
			if b:GetBagID() == bagID and b:GetID() == slot then return b end
		end
	end
	local newItems = {
		[9001] = { name = "Iron Sword", quality = 2, classID = 2, equipLoc = "INVTYPE_WEAPON", level = 20 },
		[9002] = { name = "Bronze Helm", quality = 2, classID = 4, equipLoc = "INVTYPE_HEAD", level = 25 },
		[9003] = { name = "Fine Cloak", quality = 3, classID = 4, equipLoc = "INVTYPE_CLOAK", level = 15 },
		[9004] = { name = "Healing Potion", quality = 1, classID = 0 },
		[9005] = { name = "Arrows", quality = 1, classID = 6, equipLoc = "INVTYPE_AMMO" },
		[9006] = { name = "Copper Ore", quality = 1, classID = 7 },
		[9007] = { name = "Kobold Candle", quality = 1, classID = 15 },
		[9008] = { name = "Torn Pelt", quality = 0, classID = 15 },
		[9009] = { name = "Broken Fang", quality = 0, classID = 15 },
		[9010] = { name = "Mysterious Note", quality = 1, classID = 15 },
		[9011] = { name = "Grey Shoulders", quality = 0, classID = 4, equipLoc = "INVTYPE_SHOULDER", level = 5 },
		[9012] = { name = "Skeleton Key", quality = 1, classID = 13 },
		[9013] = { name = "Shiny Ring", quality = 4, classID = 4, equipLoc = "INVTYPE_FINGER", level = 30 },
	}
	for id, item in pairs(newItems) do ITEMS[id] = item end
	QUEST_BAG_ITEMS[9007] = 101
	local bagsBefore = BAGS
	BAGS = { [0] = { [1] = 9001, [2] = 9008, [3] = 9004, [5] = 9006, [7] = 9007, [8] = 9010, [10] = 9002, [12] = 9009 },
		[1] = { [1] = 9003, [2] = 9005, [4] = 9011, [6] = 9012 } }
	local blocked, errors = #BLOCKED, #ERRORS

	local function Order(list)
		local out = {}
		for _, b in ipairs(list) do out[#out + 1] = b:GetBagID() .. ":" .. b:GetID() end
		return table.concat(out, " ")
	end
	local function At(b) local _, rel, _, x, y = b:GetPoint(1); return x, y, rel end

	GAMEPAD_STATE.ui = true
	OpenBags()
	local st = State()
	check(st.applied, "the controller UI: our layout, right after Blizzard's")
	check(Order(st.order) == "1:1 0:10 0:1 1:2 0:3 0:5 0:7 0:8 1:6 0:12 1:4 0:2 0:4 0:6 0:9 0:11 0:13 0:14 0:15 0:16 1:3 1:5 1:7 1:8",
		"sections in order (gear, consumables, trade goods, quest items, other, junk, free), each sorted: got " .. Order(st.order))
	check(table.concat(st.headers, ", ") == "Gear, Consumables, Trade goods, Quest items, Other, Junk, Free slots",
		"a header for each section: " .. table.concat(st.headers, ", "))
	-- Heights: the row 37 + 7, six sections of one row (15 + 37 + 4), the free slots' two rows (15 + 79), = 474.
	local x, y, rel = At(GamepadBagBar.BagButtonArray[1])
	check(rel == bag.MoneyFrame and x == -378 and y == 4 + 474 - 37, "the backpack's button: top left, above the items")
	x, y = At(GamepadBagBar.BagButtonArray[2])
	check(x == -336 and y == 441, "bag 1's next to it: one row")
	x, y = At(Slot(1, 1))
	check(x == -378 and y == 4 + 474 - 59 - 37, "the best gear first, below the row and its header")
	x, y = At(Slot(0, 1))
	check(x == -294 and y == 382, "a section's items side by side")
	-- More columns: wider (12 × 37 + 11 × 5 + 15), the free slots' 12 fit one row (42 less high).
	local tallAs, wideAs = bag:GetHeight(), bag:GetWidth()
	check(T("gamepadBagColumns") and M.db.gamepadBagColumns == 10 and wideAs == 430, "10 columns by default, with a slider")
	T("gamepadBagColumns"):SetValue(12)
	Wait(1)
	x = At(Slot(1, 1))
	check(bag:GetWidth() == 514 and bag:GetHeight() == tallAs - 42 and x == -462,
		"12 columns: the bag wider and less tall, the first item further left, got " .. bag:GetWidth() .. " x " .. bag:GetHeight())
	T("gamepadBagColumns"):SetValue(10)
	Wait(1)
	x = At(Slot(1, 1))
	check(bag:GetWidth() == wideAs and bag:GetHeight() == tallAs and x == -378, "back to 10: as before")
	x, y = At(Slot(1, 2))
	check(x == -378 and y == 382 - 56, "the next section a row lower")
	x, y = At(Slot(0, 4))
	check(x == -378 and y == 4 + 474 - (44 + 6 * 56 + 15) - 37, "the free slots last")
	check(bag:GetHeight() == 214 - 121 + 15 + 474, "the bag as high as our rows and the \"Bags\" header (Blizzard's grid's height taken out): "
		.. bag:GetHeight())
	-- Up and down where the next row is shorter: a jump to its last button (SmartNavigation looks only
	-- 45 degrees to each side); straight below or above otherwise.
	local function Down(b) return b["smartNavigationOverride-down"] end
	local function Up(b) return b["smartNavigationOverride-up"] end
	check(Down(GamepadBagBar.BagButtonArray[4]) == Slot(0, 1) and Down(GamepadBagBar.BagButtonArray[5]) == Slot(0, 1)
		and Down(GamepadBagBar.BagButtonArray[3]) == nil, "down from a bag button past the first row's end: its last item")
	check(Down(Slot(0, 1)) == Slot(0, 3) and Down(Slot(0, 3)) == Slot(0, 5) and Down(Slot(1, 2)) == nil,
		"down into a shorter section: its last item; straight down where there's one below")
	check(Up(Slot(1, 6)) == Slot(0, 7) and Up(Slot(0, 2)) == Slot(1, 6) and Up(Slot(0, 11)) == Slot(0, 2) and Up(Slot(0, 4)) == nil,
		"up from past a shorter row's end: its last item")
	check(Down(Slot(0, 16)) == Slot(1, 8) and Down(Slot(0, 6)) == nil, "a section's short last row too")
	check(Up(GamepadBagBar.BagButtonArray[1]) == nil, "the bag buttons' up: Blizzard's (the backpack's goes to the bag menu)")

	-- SmartNavigation: its panel is made a frame after the bag opens, in grid mode; ours goes by direction.
	Wait(0.05)
	local info = SMART_NAV.panels[bag]
	check(info and info.useGrid == false and (SMART_NAV.calls.SetUseGridNavigation or 0) >= 1,
		"the bag's panel: by direction, not by grid (sections have part-filled rows)")
	check(Slot(1, 1)["smartNavigationOverride-up"] == nil and (SMART_NAV.calls.ClearJumpNavigationOverridesInDirection or 0) >= 1,
		"Blizzard's jump from the top left item to the bag menu: gone (the row of bag buttons is above it)")
	check(info and info.targetButton == GamepadBagBar.BagButtonArray[1], "the cursor starts on the backpack's button, as Blizzard has it")

	-- The tooltip beside the bag.
	GameTooltip:SetOwner(Slot(0, 10), "ANCHOR_NONE")
	GameTooltip:SetBagItem(0, 10)
	local p = TOOLTIP.points and TOOLTIP.points[1]
	check(p and p[1] == "TOPRIGHT" and p[2] == bag and p[3] == "TOPLEFT", "the selected item's tooltip: left of the bag, at its top")
	bag._centerX = 300
	GameTooltip:SetOwner(Slot(0, 10), "ANCHOR_NONE")
	GameTooltip:SetBagItem(0, 10)
	p = TOOLTIP.points and TOOLTIP.points[1]
	check(p and p[1] == "TOPLEFT" and p[3] == "TOPRIGHT", "a bag moved to the left half: right of it")
	bag._centerX = nil
	GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
	GameTooltip:SetBagItem(0, 10)
	check(TOOLTIP.points == nil, "another owner's tooltip: left alone")

	-- Selling a junk item: sorted again on the next frame, the cursor on the next junk.
	local refreshes = SMART_NAV.calls.RefreshButtonGroups or 0
	SMART_NAV.current = Slot(0, 12)
	BAGS[0][12] = nil
	bag:UpdateItems()
	check(Order(State().order):find("0:12 1:4 0:2", 1, true), "not inside Blizzard's update")
	Wait(0.05)
	st = State()
	check(Order(st.order):find("0:8 1:6 1:4 0:2 0:4 0:6 0:9 0:11 0:12", 1, true), "sold: the slot among the free ones: " .. Order(st.order))
	check(SMART_NAV.current == Slot(1, 4), "the cursor stays where it was: on the next junk item")
	check((SMART_NAV.calls.RefreshButtonGroups or 0) == refreshes + 1, "SmartNavigation told the buttons moved")
	bag:UpdateItems()
	Wait(0.05)
	check((SMART_NAV.calls.RefreshButtonGroups or 0) == refreshes + 1, "nothing changed: nothing moved, nothing told")

	-- Used up while another window has the cursor (a clam opened: its loot window): back in the bag,
	-- the cursor goes on to the item in its place, not the emptied slot.
	local used = Slot(0, 3)
	local usedAt
	for i, b in ipairs(State().order) do if b == used then usedAt = i end end
	SMART_NAV.panels[bag].lastButton = used
	SMART_NAV.current = nil -- (the loot window's button)
	BAGS[0][3] = nil
	bag:UpdateItems()
	Wait(0.05)
	local inPlace = State().order[usedAt]
	check(usedAt and inPlace and inPlace ~= used and SMART_NAV.panels[bag].targetButton == inPlace, "used up elsewhere: the bag's target, the item in its place")
	SmartNavigation:SelectButton(used) -- (the loot window closed: SmartNavigation goes back to its last button)
	Wait(0.05)
	check(SMART_NAV.current == inPlace, "back in the bag: the cursor on the item in its place, not the emptied slot")
	SMART_NAV.panels[bag].lastButton = nil
	BAGS[0][3] = 9004
	bag:UpdateItems()
	Wait(0.05)

	-- A fight: ours stays and sorts new items in (the bag and its buttons aren't protected); only
	-- SmartNavigation hears of it after the fight (it refuses addon calls then).
	EnterCombat()
	local told = SMART_NAV.calls.RefreshButtonGroups or 0
	BAGS[0][12] = 9013
	bag:UpdateItems()
	Wait(0.05)
	check(State().applied and State().order[1] == Slot(0, 12), "a new item in a fight: sorted in at once, the ring first")
	bag:UpdateFrameSize() -- Blizzard lays the bag out in the fight (a bag collapsed, ...)
	bag:UpdateItemLayout()
	st = State()
	x, y = At(GamepadBagBar.BagButtonArray[1])
	check(st.applied and #st.headers == 7 and y == 441, "Blizzard lays the bag out in a fight: ours right after it, headers and all")
	check(bag:GetHeight() ~= bag:CalculateHeight(), "and our height")
	GameTooltip:SetOwner(Slot(0, 10), "ANCHOR_NONE")
	GameTooltip:SetBagItem(0, 10)
	check(TOOLTIP.points ~= nil, "the tooltip beside the bag in a fight too")
	check((SMART_NAV.calls.RefreshButtonGroups or 0) == told and #BLOCKED == blocked, "SmartNavigation not called in the fight: nothing blocked")
	LeaveCombat()
	Wait(0.05)
	st = State()
	check(st.applied and st.order[1] == Slot(0, 12) and #st.headers == 7 and (SMART_NAV.calls.RefreshButtonGroups or 0) > told,
		"the fight over: SmartNavigation told of the new layout")
	check(#BLOCKED == blocked, "nothing blocked")

	-- A bag collapsed in its menu (Blizzard lays the bag out again): its slots stay out.
	GamepadBagBar.BagButtonArray[2].isCollapsed = true
	bag:UpdateFrameSize()
	bag:UpdateItemLayout()
	st = State()
	check(st.applied and not Order(st.order):find("1:", 1, true) and #st.strip == 5, "a collapsed bag: its slots out, its button still in the row")
	GamepadBagBar.BagButtonArray[2].isCollapsed = nil
	bag:UpdateFrameSize()
	bag:UpdateItemLayout()
	Wait(0.05)

	-- The defaults: the backpack's button alone (the bag menu), one free slot standing for all.
	local everyItem = #State().order
	T("gamepadBagButtons"):SetValue(false)
	T("gamepadBagAllFree"):SetValue(false)
	Wait(1)
	st = State()
	local freeHeader = st.headers[#st.headers] or ""
	local free = tonumber(freeHeader:match("^Free slots %((%d+)%)$"))
	local toggle = ns.GamepadBagsToggle()
	check(#st.strip == 0 and not GamepadBagBar.BagButtonArray[1]:IsShown() and not GamepadBagBar.BagButtonArray[2]:IsShown()
		and toggle and toggle:IsShown() and toggle.Text:GetText() == "Bags (5)",
		"the bag buttons' row folded away under its header, got " .. tostring(toggle and toggle.Text:GetText()))
	local foldedHigh = bag:GetHeight()
	toggle:Click()
	Wait(1)
	check(M.db.gamepadBagButtons == true and #State().strip == 5 and GamepadBagBar.BagButtonArray[2]:IsShown()
		and bag:GetHeight() == foldedHigh + 37 + 7 - 4, "clicking the header: the row open (its setting follows), the bag a row higher")
	toggle:Click()
	Wait(1)
	check(M.db.gamepadBagButtons == false and #State().strip == 0 and bag:GetHeight() == foldedHigh, "clicking it again: folded")
	-- The controller: the cursor on the header opens the row (not kept); down into the items folds it.
	check(not toggle.isBag and not toggle.buttonContext and not toggle.OnSmartNavClick,
		"none of Blizzard's values on the header (its bindings read them: B there ran tainted)")
	toggle:GetScript("OnEnter")(toggle)
	Wait(1)
	check(#State().strip == 5 and M.db.gamepadBagButtons == false and bag:GetHeight() == foldedHigh + 37 + 7 - 4,
		"the cursor on the header: the row open, the setting as it was")
	local down = SMART_NAV_INPUT_DIRECTION.DOWN
	local back = GamepadBagBar.BagButtonArray[2]["smartNavigationOutgoingCallbacks-" .. down.dirKey]
	check(back and #back == 1 and toggle["smartNavigationOutgoingCallbacks-" .. down.dirKey], "down out of the header and the bag buttons: watched, once")
	SMART_NAV.current = GamepadBagBar.BagButtonArray[2] -- (down from the header: onto a bag button, still open)
	for _, cb in ipairs(toggle["smartNavigationOutgoingCallbacks-" .. down.dirKey]) do cb() end
	Wait(1)
	check(#State().strip == 5, "from the header down onto the row: still open")
	SMART_NAV.current = Slot(1, 1) -- (down from a bag button into the items)
	for _, cb in ipairs(back) do cb() end
	Wait(1)
	check(#State().strip == 0 and bag:GetHeight() == foldedHigh, "down into the items: folded again")
	SMART_NAV.current = nil
	check(free and free > 1 and #st.order == everyItem - (free - 1), "one free slot for all, its header says how many: " .. freeHeader)
	check(#BLOCKED == blocked and #ERRORS == errors, "nothing blocked, no errors")
	T("gamepadBagButtons"):SetValue(true)
	T("gamepadBagAllFree"):SetValue(true)
	Wait(1)
	st = State()
	check(#st.strip == 5 and GamepadBagBar.BagButtonArray[2]:IsShown() and #st.order == everyItem,
		"both ticked: every bag's button and every free slot again")

	-- Mouse and keyboard: sorted too (mouseBags), without the "Bags" header and its row.
	check(M.db.mouseBags == true and T("mouseBags"), "with mouse and keyboard on by default, with a checkbox")
	GAMEPAD_STATE.ui = false
	CloseBags()
	OpenBags()
	st = State()
	check(st.applied and #st.strip == 0 and #st.headers >= 6 and not ns.GamepadBagsToggle():IsShown()
		and GamepadBagBar.BagButtonArray[1]:IsShown() == GamepadBagBar.BagButtonArray[1]:IsShown(),
		"mouse and keyboard: the sections, no bag header or row: " .. table.concat(st.headers, ", "))
	GameTooltip:SetOwner(Slot(1, 1), "ANCHOR_NONE")
	GameTooltip:SetBagItem(1, 1)
	check(TOOLTIP.points == nil, "its tooltip where Blizzard puts it (it follows the mouse)")
	-- The reagent bag's own window (mouse and keyboard): its items come into ours, the window unseen.
	BAGS[5] = { [1] = 9006, [3] = 9004 }
	ContainerFrame6:Show()
	Wait(1)
	st = State()
	local reagent = ContainerFrame6.buttons[1]
	check(reagent:GetParent() == bag and Order(st.order):find("5:1", 1, true) and ContainerFrame6:IsShown()
		and ContainerFrame6:GetAlpha() == 0 and not ContainerFrame6:IsMouseEnabled() and not ContainerFrame6.CloseButton:IsMouseEnabled(),
		"the reagent bag's items in ours (its window open for Blizzard, unseen and unclickable): " .. Order(st.order))
	ContainerFrame6:Hide()
	Wait(1)
	check(reagent:GetParent() == ContainerFrame6 and ContainerFrame6:GetAlpha() == 1 and ContainerFrame6:IsMouseEnabled()
		and ContainerFrame6.CloseButton:IsMouseEnabled() and not Order(State().order):find("5:", 1, true),
		"its window closed: its buttons back, the window as it was")
	ContainerFrame6:Show()
	Wait(1)
	check(reagent:GetParent() == bag, "open again: in ours again")
	CloseBags() -- (the bag's close button: only the combined bag closes)
	check(not ContainerFrame6:IsShown() and reagent:GetParent() == ContainerFrame6 and ContainerFrame6:GetAlpha() == 1,
		"ours closed: the unseen reagent window closes with it (else it stays open, counted as an open bag)")
	OpenBags()
	ContainerFrame6:Show()
	Wait(1)
	check(reagent:GetParent() == bag, "both open again: in ours")
	T("mouseBags"):SetValue(false)
	Wait(1)
	-- Off: Blizzard's bag as it is.
	st = State()
	x, y = At(Slot(0, 1))
	check(not st.applied and #st.headers == 0 and x == -126 and y == 88, "mouseBags off: Blizzard's grid, nothing of ours")
	check(reagent:GetParent() == ContainerFrame6 and ContainerFrame6:GetAlpha() == 1 and ContainerFrame6:IsMouseEnabled(),
		"... and the reagent bag's window its own again")
	ContainerFrame6:Hide()
	BAGS[5] = nil
	check(bag:GetHeight() == bag:CalculateHeight(), "Blizzard's height")
	GameTooltip:SetOwner(Slot(0, 10), "ANCHOR_NONE")
	GameTooltip:SetBagItem(0, 10)
	check(TOOLTIP.points == nil, "and its tooltip where Blizzard puts it")
	Wait(0.05)
	GAMEPAD_STATE.ui = true
	CloseBags()
	OpenBags()
	Wait(0.05)
	check(State().applied and SMART_NAV.panels[bag].useGrid == false, "the controller again: ours")

	-- The setting: off takes the headers now, Blizzard's layout from its next one.
	lefthy("tweaks padbags off")
	Wait(0.05)
	st = State()
	check(M.db.gamepadBags == false and not st.applied and #st.headers == 0, "/lefthy tweaks padbags off: the headers go")
	CloseBags()
	OpenBags()
	Wait(0.05)
	x, y = At(GamepadBagBar.BagButtonArray[1])
	check(not State().applied and y ~= 441 and SMART_NAV.panels[bag].useGrid == true, "opened again: Blizzard's layout and grid, untouched")
	T("gamepadBags"):SetValue(true)
	Wait(0.05)
	check(State().applied and SMART_NAV.panels[bag].useGrid == false, "on again with the bag open: ours at once")
	EnterCombat()
	lefthy("tweaks padbags off")
	Wait(0.05)
	check(not State().applied and Down(Slot(0, 16)) == Slot(1, 8) and #BLOCKED == blocked,
		"off in a fight: our jumps wait (SmartNavigation refuses addon calls then)")
	LeaveCombat()
	Wait(0.05)
	check(Down(Slot(0, 16)) == nil and Down(GamepadBagBar.BagButtonArray[4]) == nil, "and go when it ends")
	lefthy("tweaks padbags on")
	Wait(0.05)
	check(State().applied and Down(Slot(0, 16)) == Slot(1, 8), "on again: ours, with its jumps")

	-- Opened in a fight: ours at once; SmartNavigation keeps Blizzard's grid mode until the fight ends.
	CloseBags()
	EnterCombat()
	OpenBags()
	Wait(0.05)
	check(State().applied and #State().headers == 7 and SMART_NAV.panels[bag].useGrid == true and #BLOCKED == blocked,
		"opened in a fight: sorted at once (SmartNavigation's grid mode stays till the fight ends)")
	LeaveCombat()
	Wait(0.05)
	check(State().applied and SMART_NAV.panels[bag].useGrid == false, "and SmartNavigation told after it")
	check(#BLOCKED == blocked and #ERRORS == errors, "nothing blocked, no errors")

	CloseBags()
	check(Down(Slot(0, 16)) == nil and Down(GamepadBagBar.BagButtonArray[4]) == nil and Up(Slot(0, 11)) == nil,
		"the bag closed: our jumps gone")

	-- Back as it was for the files after this one.
	M.db.gamepadBagButtons, M.db.gamepadBagAllFree = false, false
	M.db.mouseBags = true
	GAMEPAD_STATE.ui = false
	for _, b in ipairs(made) do
		for i = #bag.buttons, 1, -1 do
			if bag.buttons[i] == b then table.remove(bag.buttons, i) end
		end
		b:Hide()
	end
	for id in pairs(newItems) do ITEMS[id] = nil end
	QUEST_BAG_ITEMS[9007] = nil
	BAGS = bagsBefore
	Advance(math.ceil(waited) - waited) -- (whole seconds, so the files after this one keep their phase)
end
