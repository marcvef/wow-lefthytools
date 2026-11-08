local _, ns = ...
local L = ns.L
local LT = ns.LT

-- Misc Tweaks: the sorted bags, with a controller (gamepadBags) and with mouse and keyboard (mouseBags).
-- With mouse and keyboard the same sections, without the "Bags" header and its row (the bag buttons
-- sit on the main bar there), the navigation (SmartNavigation) and the tooltip beside the bag. There
-- the reagent bag has a window of its own (the combined bag holds bags 0 to 4 then; with a controller
-- all): its item buttons come into ours, and its window stays open for Blizzard (so it keeps them
-- up to date) but can't be seen or clicked. Given back whenever ours goes or that window closes.
--
-- With the controller UI the combined bag puts each bag's button (GamepadBagBar) into its item grid,
-- in front of that bag's slots: one long grid of bags and items. This places the same buttons anew,
-- after Blizzard's own layout (a post-hook on the bag's UpdateItemLayout) and after its item updates
-- (UpdateItems, on the next frame): the bag buttons in a row at the top, then the items in sections
-- with a small header each (gear, consumables, trade goods, quest items, other, junk, the free
-- slots), sorted in each. The bag buttons' row folds away under a "Bags" header of its own, since
-- they're needed only to change bags: the controller's cursor on the header opens it, the cursor going
-- down from there into the items folds it again; a click (the mouse) keeps it open (Misc Tweaks'
-- gamepadBagButtons). Not A on the header: the bag's A only takes an item or a bag button, and passing
-- the header off as one (its buttonContext, isBag) had Blizzard's bindings read our values, which
-- tainted them (B on the header: "SpellStopCasting" forbidden). And unless asked for, one free slot
-- stands for all, its header saying how many. The selected item's tooltip goes beside the bag. Blizzard's item buttons stay
-- Blizzard's (they do the secure use, equip, sell, split and drag); only where they sit changes.
--
-- Navigation: SmartNavigation's grid mode counts the buttons of each column, which sections with
-- part-filled rows throw off, so while ours is shown the bag goes by the nearest button in a direction
-- (its other mode). SmartNavigation's calls that addon code may make (RefreshButtonGroups,
-- SetUseGridNavigation, ...) are refused in a fight, so nothing is placed then: in a fight the layout
-- stays as it is (Blizzard's, if Blizzard laid the bag out), and ours comes after it.

local SECTIONS = {
	{ key = "gear", title = L["Gear"] },
	{ key = "consumables", title = L["Consumables"] },
	{ key = "trade", title = L["Trade goods"] },
	{ key = "quest", title = L["Quest items"] },
	{ key = "other", title = L["Other"] },
	{ key = "junk", title = L["Junk"] },
	{ key = "empty", title = L["Free slots"] },
}
local GEAR, CONSUMABLES, TRADE, QUEST, OTHER, JUNK, EMPTY = 1, 2, 3, 4, 5, 6, 7

local CLASS = (Enum and Enum.ItemClass) or {}
local WEAPON, ARMOR, QUEST_CLASS = CLASS.Weapon or 2, CLASS.Armor or 4, CLASS.Questitem or 12
local USED_UP = { [CLASS.Consumable or 0] = true, [CLASS.Projectile or 6] = true }
local MATERIALS = { [CLASS.Tradegoods or 7] = true, [CLASS.Reagent or 5] = true, [CLASS.Gem or 3] = true,
	[CLASS.ItemEnhancement or 8] = true }
local NOT_WORN = { INVTYPE_NON_EQUIP = true, INVTYPE_NON_EQUIP_IGNORE = true, INVTYPE_BAG = true,
	INVTYPE_QUIVER = true, INVTYPE_AMMO = true }
local POOR = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0

local SPACING = 5     -- between buttons (Blizzard's ITEM_SPACING_X and _Y)
local HEADER = 15     -- a section's header row
local STRIP_GAP = 7   -- below the row of bag buttons
local SECTION_GAP = 4 -- below a section's last row

local wanted = false  -- the tweak is on (with a controller)
local wantedMouse = false -- ... with mouse and keyboard (mouseBags)
local applied = false -- the bag shows our layout
local order = {}      -- the item buttons in our order (the last layout)
local laidOut = {}    -- item button -> its place in `order`
local starts = {}     -- the section each place in `order` begins (place -> section), for comparing layouts
local stripped = {}   -- the bag buttons in the row
local contentHeight   -- the items' and the row's height in our layout
local contentWidth    -- the bag's width for our columns (Misc Tweaks' gamepadBagColumns)
local freeCount = 0   -- free slots in the last layout (one of them shown, unless all are wanted)
local tucked = {}     -- Blizzard's buttons we hid (the other bags' buttons, the other free slots)
local countText       -- the free slots' count on the one shown
local bagsToggle      -- the "Bags" header: a button that folds the bag buttons' row away and back
local peeking = false -- the row open while the controller's cursor is up there (not kept)
local REAGENT_BAG = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or 5
local adopted = {}    -- the reagent bag's item buttons in ours -> the window they belong to
local hushed = {}     -- that window (and its clickable parts) we made unseen -> how they were
local folding = {}    -- buttons with our "down out of the row: fold" callback (SmartNavigation's)
local placedColumns   -- the columns of the last layout
local placedCount     -- the free slots' count in the last layout
local placedAllFree   -- whether that layout had every free slot
local buttonHeight    -- an item button's height (Blizzard's grid rows are as high)
local overlay, headers = nil, {}
local wantUp, wantDown = {}, {} -- button -> the button its up / down jump goes to (our layout's short rows)
local jumped = {}     -- buttons that have a jump of ours
local bagButtons = {} -- the bag buttons ever in our row (their up is Blizzard's)
local hooked, hookedCallback = false, nil

-- A Misc Tweaks setting (the bag buttons, the free slots, the columns).
local function Setting(key, default)
	local tweaks = LT:GetModule("tweaks")
	local v = tweaks and tweaks.db and tweaks.db[key]
	if v == nil then
		return default
	end
	return v
end

-- The bag buttons' row: open for good (the setting), or while the cursor is up there.
local function RowOpen()
	return Setting("gamepadBagButtons", false) == true or peeking
end
local dirty, navPending = false, false
local driver = CreateFrame("Frame")
driver:Hide()
local watch = CreateFrame("Frame")

local function Bag()
	return ContainerFrameCombinedBags
end

local function PadUI()
	return InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() == true
end

-- Ours wanted in the interface's mode now.
local function Active()
	if PadUI() then
		return wanted
	end
	return wantedMouse
end

local function BagButton(bagID)
	if GamepadBagBar and GamepadBagBar.GetBagButton then
		return GamepadBagBar:GetBagButton(bagID)
	end
end

-- What SmartNavigation's guard asks (its SecureHelper): addon calls are refused while this holds.
local function Restricted()
	if InCombatLockdown() then
		return true
	end
	local api, kind = C_RestrictedActions, Enum and Enum.AddOnRestrictionType and Enum.AddOnRestrictionType.Combat
	if api and api.IsAddOnRestrictionActive and kind ~= nil then
		return LT.Value(api.IsAddOnRestrictionActive, kind) == true
	end
	return false
end

-- SmartNavigation's calls addon code may make (it runs them securely, out of combat only).
local function Nav(method, ...)
	local nav = SmartNavigation
	if not (nav and type(nav[method]) == "function") or Restricted() then
		return
	end
	local ok, err = pcall(nav[method], nav, ...)
	if not ok then
		geterrorhandler()(err)
	end
end

---------------------------------------------------------------------------
-- Sorting: a section for each item, and its place in the section
---------------------------------------------------------------------------

local function SlotOrder(bag, slot)
	if bag == KEYRING_CONTAINER then
		bag = 99 -- (the key ring after the bags, as Blizzard has it)
	end
	return bag * 1000 + slot
end

local function Classify(button)
	local bag, slot = button:GetBagID(), button:GetID()
	local e = { button = button, section = EMPTY, quality = -1, level = 0, name = "", count = 0, order = SlotOrder(bag, slot) }
	if button.IsExtended and button:IsExtended() then
		e.order = e.order + 1000000 -- slots the account can't use yet: after the free ones
		return e
	end
	local info = C_Container.GetContainerItemInfo(bag, slot)
	local id = info and info.itemID
	if not LT.Readable(id) then
		return e
	end
	local link = LT.Readable(info.hyperlink) and info.hyperlink or nil
	local quality = LT.Readable(info.quality) and info.quality or LT.Value(C_Item.GetItemQualityByID, id) or 1
	e.quality, e.name = quality, link and link:match("%[(.-)%]") or ""
	e.count = LT.Readable(info.stackCount) and info.stackCount or 1
	local _, _, _, equipLoc, _, classID = C_Item.GetItemInfoInstant(id)
	local quest = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
	if quality == POOR then
		e.section = JUNK
	elseif classID == QUEST_CLASS or (type(quest) == "table" and (quest.isQuestItem or quest.questID)) then
		e.section = QUEST
	elseif (classID == WEAPON or classID == ARMOR) and type(equipLoc) == "string" and equipLoc ~= "" and not NOT_WORN[equipLoc] then
		e.section = GEAR
		e.level = (link and C_Item.GetDetailedItemLevelInfo and tonumber(LT.Value(C_Item.GetDetailedItemLevelInfo, link))) or 0
	elseif USED_UP[classID] then
		e.section = CONSUMABLES
	elseif MATERIALS[classID] then
		e.section = TRADE
	else
		e.section = OTHER
	end
	return e
end

-- Best quality first, then item level (gear), name, the bigger stack; the bag's order last.
local function Before(a, b)
	if a.quality ~= b.quality then
		return a.quality > b.quality
	end
	if a.level ~= b.level then
		return a.level > b.level
	end
	if a.name ~= b.name then
		return a.name < b.name
	end
	if a.count ~= b.count then
		return a.count > b.count
	end
	return a.order < b.order
end

-- The reagent bag's own window, open (mouse and keyboard, ours wanted there), or nil.
local function ReagentWindow(frame)
	if PadUI() or not wantedMouse or not ContainerFrameUtil_GetShownFrameForID then
		return nil
	end
	local ok, window = pcall(ContainerFrameUtil_GetShownFrameForID, REAGENT_BAG)
	if ok and window and window ~= frame and window:IsShown() and window.EnumerateValidItems then
		return window
	end
end

-- The sections' items, sorted: groups[section] = { entry, ... }. Only the slots Blizzard lays out
-- (a bag collapsed in its menu keeps its slots hidden).
local function Sort(frame)
	local groups = {}
	for i = 1, #SECTIONS do
		groups[i] = {}
	end
	for _, button in frame:EnumerateValidItems() do
		local bagButton = BagButton(button:GetBagID())
		if not (bagButton and bagButton.isCollapsed == true) then
			local e = Classify(button)
			table.insert(groups[e.section], e)
		end
	end
	local reagents = ReagentWindow(frame)
	groups.reagents = reagents
	if reagents then
		for _, button in reagents:EnumerateValidItems() do
			local e = Classify(button)
			table.insert(groups[e.section], e)
		end
	end
	for i = 1, #SECTIONS do
		table.sort(groups[i], Before)
	end
	-- One free slot for all (the first in the bags' order, where loot goes first), unless all are wanted.
	local empty = groups[EMPTY]
	freeCount = 0
	for _, e in ipairs(empty) do
		if e.order < 1000000 then
			freeCount = freeCount + 1
		end
	end
	if not Setting("gamepadBagAllFree", false) then
		groups.tucked = {}
		for i = #empty, 2, -1 do
			table.insert(groups.tucked, table.remove(empty, i).button)
		end
		if empty[1] and empty[1].order >= 1000000 then
			table.insert(groups.tucked, table.remove(empty, 1).button) -- (slots the account can't use yet)
		end
	end
	return groups
end

-- The bag buttons Blizzard puts into the grid, backpack first, the key ring last.
local function StripButtons()
	local list = {}
	if not PadUI() then
		list.count = 0
		return list -- (mouse and keyboard: the bag buttons are on the main bar)
	end
	local first, last = STARTING_BAG_INDEX or 0, ENDING_BAG_INDEX or 4
	for bag = first, last do
		local b = bag ~= KEYRING_CONTAINER and BagButton(bag)
		if b then
			list[#list + 1] = b
		end
	end
	local keyring = KEYRING_CONTAINER and first <= KEYRING_CONTAINER and BagButton(KEYRING_CONTAINER)
	if keyring then
		list[#list + 1] = keyring
	end
	list.count = #list
	if not RowOpen() then
		list.tucked = {}
		for i = #list, 1, -1 do
			table.insert(list.tucked, table.remove(list, i)) -- (folded under the "Bags" header)
		end
	end
	return list
end

-- The "Bags" header: a button on the bag (so the controller can land on it), folding the row away or
-- back. The choice goes through the setting (its checkbox follows); laid out again on the next frame.
local function Toggle(frame)
	if not bagsToggle then
		bagsToggle = CreateFrame("Button", nil, frame)
		bagsToggle.Sign = bagsToggle:CreateTexture(nil, "ARTWORK")
		bagsToggle.Sign:SetSize(12, 12)
		bagsToggle.Sign:SetPoint("LEFT", 1, 0)
		bagsToggle.Text = bagsToggle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		bagsToggle.Text:SetPoint("LEFT", bagsToggle.Sign, "RIGHT", 4, 0)
		bagsToggle.Line = bagsToggle:CreateTexture(nil, "ARTWORK")
		bagsToggle.Line:SetColorTexture(1, 0.82, 0, 0.25)
		bagsToggle.Line:SetHeight(1)
		bagsToggle.Line:SetPoint("LEFT", bagsToggle.Text, "RIGHT", 5, 0)
		bagsToggle:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		-- A click (the mouse): open for good, or folded.
		bagsToggle:SetScript("OnClick", function()
			local tweaks = LT:GetModule("tweaks")
			peeking = false
			if tweaks and tweaks.db then
				LT:SetModuleSetting(tweaks, "gamepadBagButtons", not RowOpen())
			end
		end)
		-- The controller's cursor on it (SmartNavigation's FocusEnter runs OnEnter): the row opens,
		-- laid out on the next frame (the header stays where it is, under the cursor).
		bagsToggle:SetScript("OnEnter", function()
			if PadUI() and not RowOpen() then
				peeking = true
				dirty = true
				driver:Show()
			end
		end)
	end
	bagsToggle:SetParent(frame)
	bagsToggle:SetFrameLevel(frame:GetFrameLevel() + 4)
	return bagsToggle
end

-- The cursor went down out of the row (or the header) into the items: folded again, if it was only
-- open for the cursor. SmartNavigation runs the callback after moving (each callback keeps its own
-- taint), registered once per button.
local function FoldBelow()
	local now = SmartNavigation and SmartNavigation.GetCurrentButton and SmartNavigation:GetCurrentButton()
	if peeking and now and laidOut[now] then
		peeking = false
		dirty = true
		driver:Show()
	end
end

local function WatchDown(button)
	local dirs = SMART_NAV_INPUT_DIRECTION
	if button and not folding[button] and dirs and dirs.DOWN and SmartNavigation_RegisterOutgoingDirNavCallback
		and not Restricted() then
		folding[button] = true
		SmartNavigation_RegisterOutgoingDirNavCallback(button, dirs.DOWN, FoldBelow)
	end
end

-- The reagent bag's window unseen and unclickable (it stays open: Blizzard updates its buttons then),
-- or as it was. Its clickable parts too (the close button, the portrait), not its item buttons.
local function Hush(window, on)
	if on and not hushed[window] then
		local parts = { [window] = { window:GetAlpha(), window:IsMouseEnabled() } }
		for _, child in ipairs({ window:GetChildren() }) do
			if not adopted[child] and child.IsMouseEnabled and child:IsMouseEnabled() then
				parts[child] = { nil, true }
			end
		end
		hushed[window] = parts
		window:SetAlpha(0)
		for part in pairs(parts) do
			part:EnableMouse(false)
		end
	elseif not on and hushed[window] then
		for part, was in pairs(hushed[window]) do
			if part == window then
				window:SetAlpha(was[1] or 1)
			end
			part:EnableMouse(was[2])
		end
		hushed[window] = nil
	end
end

-- The reagent bag's buttons into ours (laid out with the rest), or all given back to their window,
-- which lays them out again (its own Blizzard layout).
local function Adopt(frame, window)
	if not window then
		return
	end
	local level
	for _, b in frame:EnumerateValidItems() do
		level = b:GetFrameLevel()
		break
	end
	for _, b in window:EnumerateValidItems() do
		adopted[b] = window
		if b:GetParent() ~= frame then
			b:SetParent(frame)
		end
		if level then
			b:SetFrameLevel(level)
		end
	end
	Hush(window, true)
end

local function GiveBack()
	local windows = {}
	for b, window in pairs(adopted) do
		if not (InCombatLockdown() and b:IsProtected()) then
			b:SetParent(window)
			adopted[b] = nil
			windows[window] = true
		end
	end
	for window in pairs(hushed) do
		windows[window] = true
	end
	for window in pairs(windows) do
		Hush(window, false)
		if window:IsShown() and window.UpdateItemLayout then
			window:UpdateItemLayout() -- (its grid again)
		end
	end
end

-- Blizzard's buttons back that we hid (ours gone, or wanted again). Not a protected one in a fight.
local function Untuck(keep)
	for b in pairs(tucked) do
		if not (keep and keep[b]) and not (InCombatLockdown() and b:IsProtected()) then
			b:Show()
			tucked[b] = nil
		end
	end
end

local function Tuck(list, keep)
	for _, b in ipairs(list or {}) do
		keep[b] = true
		if b:IsShown() then
			b:Hide() -- (again, if Blizzard showed it since)
		end
		tucked[b] = true
	end
end

-- The same order and sections as the last layout: nothing to move.
local function SameLayout(groups)
	local n = 0
	for s, group in ipairs(groups) do
		for i, e in ipairs(group) do
			n = n + 1
			if order[n] ~= e.button or (i == 1) ~= (starts[n] == s) then
				return false
			end
		end
	end
	return n == #order
end

---------------------------------------------------------------------------
-- Jumps between rows of different length (SmartNavigation)
---------------------------------------------------------------------------

-- Up and down go to the nearest button within 45 degrees: straight below or above where the next row
-- is as long, but a shorter row's last button (two columns or more away) is outside that, so it went on
-- to the section after. Where the row below (above) is shorter, a jump goes to its last button.
local function PlanJumps(rows)
	wipe(wantUp); wipe(wantDown)
	for r = 1, #rows - 1 do
		local row, below = rows[r], rows[r + 1]
		for c = #below + 1, #row do
			wantDown[row[c]] = below[#below]
		end
		for c = #row + 1, #below do
			wantUp[below[c]] = row[#row]
		end
	end
end

local function Jump(button, dir, key, want)
	if button[key] ~= want then
		if want then
			SmartNavigation_AddJumpNavigationOverride(button, dir, want)
		else
			SmartNavigation_ClearJumpNavigationOverridesInDirection(button, dir)
		end
	end
end

-- SmartNavigation's jumps as planned (all == false: ours cleared). Its own keeps them (values addon code
-- may set out of combat, through its SecureHelper). Blizzard's on our items go (the top left one's jump
-- up to the bag menu: the bag buttons are above it now); on the bag buttons only down is ours (the
-- backpack's up to the bag menu is Blizzard's).
local function ApplyJumps(all)
	local dirs = SMART_NAV_INPUT_DIRECTION
	local UP, DOWN = dirs and dirs.UP, dirs and dirs.DOWN
	if not (UP and DOWN and SmartNavigation_AddJumpNavigationOverride
		and SmartNavigation_ClearJumpNavigationOverridesInDirection) or Restricted() then
		return -- (kept in `jumped`: cleared or set when it may)
	end
	local up, down = "smartNavigationOverride-" .. UP.dirKey, "smartNavigationOverride-" .. DOWN.dirKey
	local seen = {}
	if all ~= false then
		for _, b in ipairs(order) do
			Jump(b, UP, up, wantUp[b])
			Jump(b, DOWN, down, wantDown[b])
			seen[b] = true
		end
		for _, b in ipairs(stripped) do
			Jump(b, DOWN, down, wantDown[b])
			seen[b] = true
		end
	end
	for b in pairs(jumped) do
		if not seen[b] then
			if not bagButtons[b] then
				Jump(b, UP, up, nil)
			end
			Jump(b, DOWN, down, nil)
		end
	end
	wipe(jumped)
	if all ~= false then
		for b in pairs(wantUp) do jumped[b] = true end
		for b in pairs(wantDown) do jumped[b] = true end
	end
end

---------------------------------------------------------------------------
-- Placing: the row of bag buttons, the headers, the items, the bag's height
---------------------------------------------------------------------------

local function Header(i)
	local h = headers[i]
	if not h then
		h = { text = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"), line = overlay:CreateTexture(nil, "ARTWORK") }
		h.line:SetColorTexture(1, 0.82, 0, 0.25)
		h.line:SetHeight(1)
		headers[i] = h
	end
	return h
end

local function HideHeaders(from)
	for i = from, #headers do
		headers[i].text:Hide()
		headers[i].line:Hide()
	end
end

-- The height Blizzard gives the bag, with our rows in place of its grid.
local function OurHeight(frame, h)
	local rows = frame:GetRows()
	return frame:CalculateHeight() - (rows * h + (rows - 1) * SPACING) + contentHeight
end

local function SetBagHeight(frame, height)
	if math.abs(frame:GetHeight() - height) > 0.5 then
		frame:SetHeight(height)
	end
	if NineSliceUtil and NineSliceUtil.UpdateCornerCropping then
		NineSliceUtil.UpdateCornerCropping(frame, height)
	end
end

-- Items side by side (Misc Tweaks' slider; Blizzard's grid has 10): more make the bag wider, less tall.
local function Columns()
	local tweaks = LT:GetModule("tweaks")
	local n = tweaks and tweaks.db and tonumber(tweaks.db.gamepadBagColumns)
	return math.max(6, math.min(24, math.floor((n or 10) + 0.5)))
end

local function SetBagWidth(frame, width)
	if width and math.abs(frame:GetWidth() - width) > 0.5 then
		frame:SetWidth(width)
	end
end

local function ButtonSize(groups, strip)
	for _, group in ipairs(groups) do
		if group[1] then
			return group[1].button:GetWidth(), group[1].button:GetHeight()
		end
	end
	local b = strip[1]
	return b and b:GetWidth() or 37, b and b:GetHeight() or 37
end

-- Everything anchored like Blizzard's grid (BOTTOMRIGHT at its first item's anchor, the money frame),
-- worked out from the top: `top` is how far an element's top is below the content's top.
local function Place(frame, groups, strip)
	local anchor = frame.GetInitialItemAnchor and frame:GetInitialItemAnchor()
	local point, rel, relPoint, ax, ay
	if anchor and anchor.Get then
		point, rel, relPoint, ax, ay = anchor:Get()
	end
	if point ~= "BOTTOMRIGHT" or not rel or not (frame.GetRows and frame.CalculateHeight) then
		return false -- not the grid this was made for: Blizzard's layout stays
	end
	local keep = {}
	Tuck(strip.tucked, keep)
	Tuck(groups.tucked, keep)
	Untuck(keep) -- (the ones wanted again: shown)
	if groups.reagents then
		Adopt(frame, groups.reagents)
	elseif next(adopted) or next(hushed) then
		GiveBack()
	end
	local w, h = ButtonSize(groups, strip)
	local cols = Columns()
	placedColumns, placedCount = cols, freeCount
	placedAllFree = Setting("gamepadBagAllFree", false)
	contentWidth = cols * w + (cols - 1) * SPACING + (frame.GetPaddingWidth and frame:GetPaddingWidth() or 15)
	local pad, open = PadUI(), #strip > 0
	local base = pad and HEADER + (open and h + STRIP_GAP or SECTION_GAP) or 0 -- (the "Bags" header, the row when open)
	local height = base
	for _, group in ipairs(groups) do
		if group[1] then
			local rows = math.ceil(#group / cols)
			height = height + HEADER + rows * h + (rows - 1) * SPACING + SECTION_GAP
		end
	end
	height = height - SECTION_GAP
	contentHeight, buttonHeight = height, h
	local function Put(button, col, top)
		button:ClearAllPoints()
		button:SetPoint("BOTTOMRIGHT", rel, relPoint, ax - (cols - col) * (w + SPACING), ay + height - top - h)
	end
	local left, gridWidth = ax - cols * (w + SPACING) + SPACING, cols * w + (cols - 1) * SPACING
	local toggle = pad and Toggle(frame)
	if toggle then
	toggle:ClearAllPoints()
	toggle:SetPoint("BOTTOMLEFT", rel, relPoint, left, ay + height - HEADER)
	toggle:SetSize(gridWidth, HEADER)
	toggle.Sign:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
	WatchDown(toggle)
	toggle.Text:SetText(L["Bags (%d)"]:format(strip.count or #strip))
	toggle.Line:SetWidth(math.max(1, gridWidth - toggle.Text:GetStringWidth() - 25))
	toggle:Show()
	elseif bagsToggle then
		bagsToggle:Hide()
	end
	wipe(stripped)
	stripped.all = RowOpen()
	for i, b in ipairs(strip) do
		Put(b, math.min(i, cols), HEADER)
		stripped[i] = b
		bagButtons[b] = true
		WatchDown(b)
	end
	local rows = { toggle and { toggle } or nil }
	rows[#rows + 1] = stripped[1] and stripped or nil
	overlay:SetParent(frame)
	overlay:ClearAllPoints()
	overlay:SetAllPoints(frame)
	overlay:SetFrameLevel(frame:GetFrameLevel() + 3)
	overlay:Show()
	wipe(order); wipe(laidOut); wipe(starts)
	local top, shown = base, 0
	for s, group in ipairs(groups) do
		if group[1] then
			shown = shown + 1
			local hd = Header(shown)
			hd.text:ClearAllPoints()
			hd.text:SetPoint("BOTTOMLEFT", rel, relPoint, left + 1, ay + height - top - HEADER + 3)
			hd.text:SetText(s == EMPTY and groups.tucked and L["Free slots (%d)"]:format(freeCount) or SECTIONS[s].title)
			hd.text:Show()
			hd.line:ClearAllPoints()
			hd.line:SetPoint("LEFT", hd.text, "RIGHT", 5, 0)
			hd.line:SetWidth(math.max(1, gridWidth - hd.text:GetStringWidth() - 8))
			hd.line:Show()
			top = top + HEADER
			for i, e in ipairs(group) do
				local row, col = math.floor((i - 1) / cols), (i - 1) % cols + 1
				Put(e.button, col, top + row * (h + SPACING))
				if col == 1 then
					rows[#rows + 1] = {}
				end
				table.insert(rows[#rows], e.button)
				order[#order + 1] = e.button
				laidOut[e.button] = #order
				if i == 1 then
					starts[#order] = s
				end
			end
			local rows = math.ceil(#group / cols)
			top = top + rows * h + (rows - 1) * SPACING + SECTION_GAP
		end
	end
	HideHeaders(shown + 1)
	countText = countText or overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	local free = groups.tucked and groups[EMPTY][1]
	if free and freeCount > 1 then
		countText:ClearAllPoints()
		countText:SetPoint("BOTTOMRIGHT", free.button, "BOTTOMRIGHT", -3, 3)
		countText:SetText(freeCount)
		countText:Show()
	else
		countText:Hide()
	end
	SetBagWidth(frame, contentWidth)
	SetBagHeight(frame, OurHeight(frame, h))
	applied = true
	if pad then
		PlanJumps(rows)
	else
		wipe(wantUp); wipe(wantDown) -- (no cursor with the mouse: none of ours)
	end
	ApplyJumps()
	return true
end

-- Ours gone (off, mouse and keyboard, or Blizzard laid the bag out in a fight): the headers hidden.
-- Blizzard's next layout puts its own back (with mouse and keyboard and in a fight it already has).
local function Unapply()
	local frame = applied and Bag()
	if frame and frame.CalculateWidth and not (InCombatLockdown() and frame:IsProtected()) then
		SetBagWidth(frame, frame:CalculateWidth()) -- (Blizzard's columns again)
	end
	applied = false
	wipe(wantUp); wipe(wantDown)
	ApplyJumps(false)
	wipe(order); wipe(laidOut); wipe(starts); wipe(stripped)
	Untuck() -- (Blizzard's layout has them all)
	GiveBack()
	if overlay then
		overlay:Hide()
	end
	if bagsToggle then
		bagsToggle:Hide()
	end
end

---------------------------------------------------------------------------
-- Navigation (SmartNavigation) and the tooltip
---------------------------------------------------------------------------

-- The bag's SmartNavigation panel goes by direction (not by grid), with our jumps (Blizzard set its own
-- just before: the top left item's up to the bag menu). refresh: our buttons moved outside Blizzard's
-- own layout calls.
local function FixNavigation(frame, refresh)
	if not (applied and frame:IsShown() and SmartNavigation) or Restricted() then
		return
	end
	local info = SmartNavigation.GetPanelInfo and SmartNavigation:GetPanelInfo(frame, true)
	if not info then
		return -- (not open for the controller yet: the hook on its panel's creation does it then)
	end
	if info.useGrid then
		Nav("SetUseGridNavigation", frame, false)
	end
	if refresh then
		Nav("RefreshButtonGroups", frame)
	end
	ApplyJumps()
end

-- The bag's panel made anew (each time it opens): Blizzard's callback has just set grid mode.
local function OnPanelAdded()
	if applied then
		FixNavigation(Bag())
	end
end

local function HookPanelCallback(frame)
	local callback = frame.smartNavPanelInfoAddedCallback
	if type(callback) == "function" and callback ~= hookedCallback then
		hooksecurefunc(frame, "smartNavPanelInfoAddedCallback", OnPanelAdded)
		hookedCallback = frame.smartNavPanelInfoAddedCallback
	end
end

-- The selected item's tooltip beside the bag (the side with room), not over the other items. Blizzard
-- sets it up on selecting (OnEnter) and every refresh; this runs after each SetBagItem.
local function PlaceTooltip(tooltip)
	if not applied or not PadUI() then -- (with the mouse it follows the mouse, as ever)
		return
	end
	local owner = tooltip.GetOwner and tooltip:GetOwner()
	local frame = Bag()
	if not (owner and laidOut[owner] and frame:IsShown()) then
		return
	end
	local x = frame:GetCenter()
	local onLeft = x and x * frame:GetEffectiveScale() < GetScreenWidth() * UIParent:GetEffectiveScale() / 2
	tooltip:ClearAllPoints()
	if onLeft then
		tooltip:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0)
	else
		tooltip:SetPoint("TOPRIGHT", frame, "TOPLEFT", -4, 0)
	end
end

---------------------------------------------------------------------------
-- When it runs
---------------------------------------------------------------------------

local function Wanted(frame)
	return Active() and frame:IsShown()
end

-- Blizzard's layout of the bag (opening it, a bag collapsed, a bag changed, ...): ours after it.
local function OnItemLayout(frame)
	HookPanelCallback(frame)
	if not Wanted(frame) then
		Unapply()
		return
	end
	if Restricted() then
		-- In a fight: Blizzard's layout stands (SmartNavigation knows it), ours when the fight ends.
		if applied and frame.CalculateHeight and not frame:IsProtected() then
			SetBagHeight(frame, frame:CalculateHeight())
			SetBagWidth(frame, frame.CalculateWidth and frame:CalculateWidth())
		end
		Unapply()
		dirty = true
		watch:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	if Place(frame, Sort(frame), StripButtons()) then
		navPending = true
		driver:Show()
	else
		Unapply()
	end
end

-- Blizzard sized the bag (also without laying it out, a currency watched): ours while ours is shown.
local function OnFrameSize(frame)
	if applied and Wanted(frame) and not (InCombatLockdown() and frame:IsProtected()) then
		SetBagWidth(frame, contentWidth)
		SetBagHeight(frame, OurHeight(frame, buttonHeight))
	end
end

-- Items changed (Blizzard redrew them): sorted again on the next frame.
local function OnItemsUpdated(frame)
	if wanted and applied and frame:IsShown() then
		dirty = true
		driver:Show()
	end
end

-- Sorted again; only moved if the order changed. The selected slot's place stays selected (selling
-- junk goes on to the next junk).
local function Relayout()
	local frame = Bag()
	if not Wanted(frame) then
		wipe(wantUp); wipe(wantDown)
		ApplyJumps(false) -- (ours gone or the bag closed in a fight: our jumps go now)
		return
	end
	if Restricted() then
		if InCombatLockdown() then
			watch:RegisterEvent("PLAYER_REGEN_ENABLED")
		else
			C_Timer.After(1, function() dirty = true; driver:Show() end)
		end
		return
	end
	local groups = Sort(frame)
	if applied and SameLayout(groups) and placedColumns == Columns() and placedCount == freeCount
		and (groups.reagents ~= nil) == (next(adopted) ~= nil)
		and stripped.all == RowOpen() and placedAllFree == Setting("gamepadBagAllFree", false) then
		return
	end
	local current = SmartNavigation and SmartNavigation.GetCurrentButton and SmartNavigation:GetCurrentButton()
	local was = current and laidOut[current]
	if not Place(frame, groups, StripButtons()) then
		Unapply()
		return
	end
	FixNavigation(frame, true)
	if was and laidOut[current] ~= was then
		local now = order[math.min(was, #order)]
		if now and now ~= current then
			Nav("SetTargetButtonForFrame", frame, now)
		end
	end
end

-- The bag closed: our jumps go (a bag opened in a fight gets Blizzard's layout, which they don't fit).
local function OnBagHidden()
	peeking = false -- (opened for the cursor: folded at the next opening)
	wipe(wantUp); wipe(wantDown)
	ApplyJumps(false)
	if next(jumped) then
		watch:RegisterEvent("PLAYER_REGEN_ENABLED") -- (closed in a fight: after it)
	end
end

driver:SetScript("OnUpdate", function(self)
	self:Hide()
	if dirty then
		dirty = false
		Relayout()
	end
	if navPending then
		navPending = false
		FixNavigation(Bag(), true) -- (our "Bags" header among its buttons, also the first time it's made)
	end
end)

watch:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	dirty = true
	driver:Show() -- (not inside the event)
end)

-- A bag window (the reagent bag's) opening or closing: ours laid out again on the next frame; closing,
-- its buttons go back to it at once.
local function OnWindowShown(window)
	if window ~= Bag() and wantedMouse and not PadUI() and window.GetBagID and window:GetBagID() == REAGENT_BAG then
		dirty = true
		driver:Show()
	end
end

local function OnWindowHidden(window)
	if hushed[window] then
		GiveBack()
		dirty = true
		driver:Show()
	end
end

local function Hook()
	local frame = Bag()
	if hooked or not (frame and type(frame.UpdateItemLayout) == "function" and frame.EnumerateValidItems) then
		return
	end
	hooked = true
	overlay = CreateFrame("Frame") -- (made without a parent: SmartNavigation looks at frames made on a panel)
	overlay:Hide()
	hooksecurefunc(frame, "UpdateItemLayout", OnItemLayout)
	if type(frame.UpdateFrameSize) == "function" then
		hooksecurefunc(frame, "UpdateFrameSize", OnFrameSize)
	end
	if type(frame.UpdateItems) == "function" then
		hooksecurefunc(frame, "UpdateItems", OnItemsUpdated)
	end
	frame:HookScript("OnHide", OnBagHidden)
	for i = 1, (NUM_CONTAINER_FRAMES or 13) + 1 do
		local window = _G["ContainerFrame" .. i]
		if window and window.HookScript then
			window:HookScript("OnShow", OnWindowShown)
			window:HookScript("OnHide", OnWindowHidden)
		end
	end
	if type(frame.ApplySmartNavOverrideForLeftmostButton) == "function" then
		hooksecurefunc(frame, "ApplySmartNavOverrideForLeftmostButton", OnPanelAdded) -- (the bag's first frame open)
	end
	if GameTooltip and type(GameTooltip.SetBagItem) == "function" then
		hooksecurefunc(GameTooltip, "SetBagItem", PlaceTooltip)
	end
	HookPanelCallback(frame)
end

-- Called by Tweaks.lua when the switch changes (on the next frame). Off: the headers go now, Blizzard's
-- layout comes with its next one (the bag opened again).
function ns.ApplyGamepadBags(on)
	wanted = on
	if on then
		Hook()
		local frame = Bag()
		if frame and hooked and frame:IsShown() and PadUI() then
			dirty = true
			driver:Show()
		end
	elseif not PadUI() then
		return -- (the mouse's sorted bags may stay)
	else
		Unapply()
		dirty, navPending = false, false
		if next(jumped) then
			watch:RegisterEvent("PLAYER_REGEN_ENABLED") -- (off in a fight: our jumps go after it)
		else
			watch:UnregisterAllEvents()
		end
	end
end

-- Called by Tweaks.lua for mouseBags (on the next frame): the same, with mouse and keyboard.
function ns.ApplyMouseBags(on)
	wantedMouse = on
	if on then
		Hook()
	end
	local frame = Bag()
	if PadUI() or not (frame and hooked and frame:IsShown()) then
		return
	end
	if on then
		dirty = true
		driver:Show()
	else
		if frame.CalculateHeight then
			SetBagHeight(frame, frame:CalculateHeight()) -- (Blizzard's own, before ours lets go)
		end
		Unapply()
		dirty = false
		if frame.UpdateItemLayout then
			frame:UpdateItemLayout() -- (Blizzard's grid back now, not at the next opening)
		end
	end
end

-- Misc Tweaks' columns slider moved, or what's shown of the bag buttons and free slots: laid out
-- again (on the next frame).
function ns.GamepadBagsColumns()
	local frame = Bag()
	if Active() and hooked and frame and frame:IsShown() and applied
		and (placedColumns ~= Columns() or (stripped.all ~= nil and stripped.all ~= RowOpen())
			or (placedAllFree ~= nil and placedAllFree ~= Setting("gamepadBagAllFree", false))) then
		dirty = true
		driver:Show()
	end
end

-- For the tests: the "Bags" header's button.
function ns.GamepadBagsToggle()
	return bagsToggle
end

-- For the tests: whether ours is shown, the item buttons in its order, the bag buttons' row, the
-- headers shown.
function ns.GamepadBagsState()
	local shown = {}
	for _, h in ipairs(headers) do
		if h.text:IsShown() and overlay:IsShown() then
			shown[#shown + 1] = h.text:GetText()
		end
	end
	return { applied = applied, order = order, strip = stripped, headers = shown }
end
