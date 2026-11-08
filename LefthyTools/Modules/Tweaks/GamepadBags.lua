local _, ns = ...
local L = ns.L
local LT = ns.LT

-- Misc Tweaks: the bags with a controller (gamepadBags).
--
-- With the controller UI the combined bag puts each bag's button (GamepadBagBar) into its item grid,
-- in front of that bag's slots: one long grid of bags and items. This places the same buttons anew,
-- after Blizzard's own layout (a post-hook on the bag's UpdateItemLayout) and after its item updates
-- (UpdateItems, on the next frame): the bag buttons in a row at the top, then the items in sections
-- with a small header each (gear, consumables, trade goods, quest items, other, junk, the free
-- slots), sorted in each. The selected item's tooltip goes beside the bag. Blizzard's item buttons stay
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

local wanted = false  -- the tweak is on
local applied = false -- the bag shows our layout
local order = {}      -- the item buttons in our order (the last layout)
local laidOut = {}    -- item button -> its place in `order`
local starts = {}     -- the section each place in `order` begins (place -> section), for comparing layouts
local stripped = {}   -- the bag buttons in the row
local contentHeight   -- the items' and the row's height in our layout
local buttonHeight    -- an item button's height (Blizzard's grid rows are as high)
local overlay, headers = nil, {}
local wantUp, wantDown = {}, {} -- button -> the button its up / down jump goes to (our layout's short rows)
local jumped = {}     -- buttons that have a jump of ours
local bagButtons = {} -- the bag buttons ever in our row (their up is Blizzard's)
local hooked, hookedCallback = false, nil
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
	for i = 1, #SECTIONS do
		table.sort(groups[i], Before)
	end
	return groups
end

-- The bag buttons Blizzard puts into the grid, backpack first, the key ring last.
local function StripButtons()
	local list = {}
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
	return list
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
	local w, h = ButtonSize(groups, strip)
	local cols = frame.GetColumns and frame:GetColumns() or 10
	local height = #strip > 0 and h + STRIP_GAP or 0
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
	wipe(stripped)
	for i, b in ipairs(strip) do
		Put(b, math.min(i, cols), 0)
		stripped[i] = b
		bagButtons[b] = true
	end
	local rows = { stripped[1] and stripped or nil }
	overlay:SetParent(frame)
	overlay:ClearAllPoints()
	overlay:SetAllPoints(frame)
	overlay:SetFrameLevel(frame:GetFrameLevel() + 3)
	overlay:Show()
	wipe(order); wipe(laidOut); wipe(starts)
	local top, shown = #strip > 0 and h + STRIP_GAP or 0, 0
	local left, gridWidth = ax - cols * (w + SPACING) + SPACING, cols * w + (cols - 1) * SPACING
	for s, group in ipairs(groups) do
		if group[1] then
			shown = shown + 1
			local hd = Header(shown)
			hd.text:ClearAllPoints()
			hd.text:SetPoint("BOTTOMLEFT", rel, relPoint, left + 1, ay + height - top - HEADER + 3)
			hd.text:SetText(SECTIONS[s].title)
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
	SetBagHeight(frame, OurHeight(frame, h))
	applied = true
	PlanJumps(rows)
	ApplyJumps()
	return true
end

-- Ours gone (off, mouse and keyboard, or Blizzard laid the bag out in a fight): the headers hidden.
-- Blizzard's next layout puts its own back (with mouse and keyboard and in a fight it already has).
local function Unapply()
	applied = false
	wipe(wantUp); wipe(wantDown)
	ApplyJumps(false)
	wipe(order); wipe(laidOut); wipe(starts); wipe(stripped)
	if overlay then
		overlay:Hide()
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
	if not applied then
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
	return wanted and PadUI() and frame:IsShown()
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
	if applied and SameLayout(groups) then
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
		FixNavigation(Bag())
	end
end)

watch:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	dirty = true
	driver:Show() -- (not inside the event)
end)

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
