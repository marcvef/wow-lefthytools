local _, ns = ...
local L = ns.L
local M = ns.LT:GetModule("tweaks")

-- Misc Tweaks: movable bags (movableBags) and the bags' clean-up button (gamepadBagSort).
--
-- Movable bags: Blizzard re-anchors every bag to the bottom right in UpdateContainerFrameAnchors()
-- whenever bags open, close or the layout changes; a post-hook puts moved bags back where the
-- player left them. Dragging works on the title bar (an invisible "router" button that opens the
-- bag menu on mouse down; a drag closes that menu again) and on any empty spot of the bag.

local bagsHooked = false
local hookedBagFrames = {}
local dragging

local function BagsActive()
	return M.enabled and M.db.movableBags
end

local function ContainerFrames()
	local list = {}
	if ContainerFrameCombinedBags then
		list[#list + 1] = ContainerFrameCombinedBags
	end
	local frames = ContainerFrameContainer and ContainerFrameContainer.ContainerFrames
	if type(frames) == "table" then
		for _, f in ipairs(frames) do
			list[#list + 1] = f
		end
	else
		for i = 1, (NUM_CONTAINER_FRAMES or 13) do
			local f = _G["ContainerFrame" .. i]
			if f then
				list[#list + 1] = f
			end
		end
	end
	return list
end

local function BagKey(frame)
	if frame.IsCombinedBagContainer and frame:IsCombinedBagContainer() then
		return "combined"
	end
	local id = frame.GetBagID and frame:GetBagID()
	return id and ("bag" .. id) or nil
end

local function CanMove(frame)
	return not (InCombatLockdown() and frame:IsProtected())
end

local function ApplySavedPosition(frame)
	local key = BagKey(frame)
	local pos = key and M.db.bagPositions[key]
	if not pos or not frame:IsShown() or not CanMove(frame) then
		return
	end
	local scale = frame:GetScale()
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.left / scale, pos.top / scale)
end

local function OnBagsAnchored()
	if not BagsActive() then
		return
	end
	local anyMoved = next(M.db.bagPositions) ~= nil
	for _, frame in ipairs(ContainerFrames()) do
		ApplySavedPosition(frame)
		-- Blizzard stacks each separate bag on the one before: bags not moved hang off a moved one
		-- (above a backpack dragged to the top, off the screen). Kept on the screen.
		if anyMoved and frame:IsShown() and CanMove(frame) then
			frame:SetClampedToScreen(true)
		end
	end
end

local function StartDrag(frame)
	if not BagsActive() or not CanMove(frame) then
		return
	end
	-- The title bar opens the bag menu on mouse down; a drag shouldn't leave it open. Not in gamepad
	-- mode: a menu closed from addon code taints the controller's focus manager (forever-platform.md).
	if Menu and Menu.GetManager and not (InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()) then
		pcall(function() Menu.GetManager():CloseMenus() end)
	end
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:StartMoving()
	dragging = frame
end

local function StopDrag(frame)
	if dragging ~= frame then
		return
	end
	dragging = nil
	frame:StopMovingOrSizing()
	frame:SetUserPlaced(false) -- positions live in our settings, not the client layout cache
	local key = BagKey(frame)
	local left, top = frame:GetLeft(), frame:GetTop()
	if key and left and top then
		local scale = frame:GetScale()
		M.db.bagPositions[key] = { left = left * scale, top = top * scale }
	end
end

local function FindTitleRouter(frame)
	for _, child in ipairs({ frame:GetChildren() }) do
		if child.routeToSibling == "PortraitButton" then
			return child
		end
	end
end

local function HookBagFrame(frame)
	if hookedBagFrames[frame] then
		return
	end
	hookedBagFrames[frame] = true
	for _, handle in ipairs({ frame, FindTitleRouter(frame) }) do
		handle:RegisterForDrag("LeftButton")
		handle:HookScript("OnDragStart", function() StartDrag(frame) end)
		handle:HookScript("OnDragStop", function() StopDrag(frame) end)
	end
end

-- Called by Tweaks.lua when the switch changes (on the next frame, never in a callback).
function ns.ApplyMovableBags(on)
	if on then
		if not bagsHooked and type(UpdateContainerFrameAnchors) == "function" then
			bagsHooked = true
			hooksecurefunc("UpdateContainerFrameAnchors", OnBagsAnchored)
		end
		for _, frame in ipairs(ContainerFrames()) do
			HookBagFrame(frame)
		end
		OnBagsAnchored()
	elseif not InCombatLockdown() and type(UpdateContainerFrameAnchors) == "function" then
		-- Back to Blizzard's default spots; saved positions are kept for next time.
		UpdateContainerFrameAnchors()
	end
end

function M:ResetBagPositions()
	wipe(self.db.bagPositions)
	if not InCombatLockdown() and type(UpdateContainerFrameAnchors) == "function" then
		UpdateContainerFrameAnchors()
	end
end

-- The bags' clean-up button. Since Forever 1.60.1.70291 Blizzard's (BagItemAutoSortButton) no
-- longer shows on the bags, with or without gamepad mode, and gamepad mode's bag bar with its
-- clean-up menu is gone too: there was no way left to clean up. A post-hook on each bag frame's
-- UpdateSearchBox (and its OnShow, in case that isn't called any more) puts the button back on the
-- backpack or the combined bags, at the left end of the search row. A client without Blizzard's
-- button gets one of ours that does the same (C_Container.SortBags). (The setting's key still says
-- gamepad: it began there.)
local sortHooked = {}
local ownSortButton

local function OwnSortButtonOnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText(BAG_CLEANUP_BAGS or L["Clean up bags"], 1, 1, 1)
	GameTooltip:Show()
end

-- Blizzard's button, or ours where this client has none.
local function SortButton()
	if BagItemAutoSortButton then
		return BagItemAutoSortButton
	end
	if not ownSortButton then
		local button = CreateFrame("Button", "LefthyToolsBagSortButton", UIParent)
		button:SetSize(28, 26)
		if button.SetNormalAtlas then
			button:SetNormalAtlas("bags-button-autosort-up")
			button:SetPushedAtlas("bags-button-autosort-down")
		else
			button:SetNormalTexture("Interface\\Icons\\INV_Pet_Broom")
		end
		button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		button:SetScript("OnClick", function()
			if SOUNDKIT and SOUNDKIT.UI_BAG_SORTING_01 then
				PlaySound(SOUNDKIT.UI_BAG_SORTING_01)
			end
			if C_Container and C_Container.SortBags then
				C_Container.SortBags()
			end
		end)
		button:SetScript("OnEnter", OwnSortButtonOnEnter)
		button:SetScript("OnLeave", function() GameTooltip:Hide() end)
		button:Hide()
		ownSortButton = button
	end
	return ownSortButton
end

local SORT_ROOM = 32 -- the search box moves this far right (and gets as much narrower) for the button

-- The search box's width as Blizzard set it (we narrow it; Blizzard may set it again on an update).
local function SearchWidth(search)
	local width = search:GetWidth()
	if search.lefthyWidth and math.abs(width - search.lefthyWidth) < 0.5 then
		return width + SORT_ROOM -- (still ours)
	end
	return width
end

-- The button goes at the left end of the search row (top right something of Forever's sits where
-- Blizzard had it): where the search box starts, the box moved right to make room. Blizzard puts
-- the box back on each update, and this runs after it.
local function ShowSortButton(frame)
	if not (M.enabled and M.db.gamepadBagSort and frame:IsShown()) then
		return
	end
	if (frame.IsBackpack and frame:IsBackpack()) or (frame.IsCombinedBagContainer and frame:IsCombinedBagContainer()) then
		local button = SortButton()
		button:SetParent(frame)
		button:ClearAllPoints()
		local search = BagItemSearchBox
		local point, relative, relativePoint, x, y
		if search and search:IsShown() and search:GetParent() == frame and search:GetNumPoints() == 1 then
			point, relative, relativePoint, x, y = search:GetPoint(1)
		end
		if point == "TOPLEFT" and relative == frame and relativePoint == "TOPLEFT" then
			local width = SearchWidth(search)
			if search.lefthyX and math.abs(x - search.lefthyX) < 0.5 then
				x = x - SORT_ROOM -- (still where we put it, Blizzard didn't place it again: not moved twice)
			end
			search:ClearAllPoints()
			search:SetPoint("TOPLEFT", frame, "TOPLEFT", x + SORT_ROOM, y)
			search.lefthyX = x + SORT_ROOM
			search.lefthyWidth = math.max(40, width - SORT_ROOM)
			search:SetWidth(search.lefthyWidth)
			button:SetPoint("TOPLEFT", frame, "TOPLEFT", x - 4, y + 3)
		elseif search and search:IsShown() and search:GetParent() == frame then
			button:SetPoint("RIGHT", search, "LEFT", -6, 0)
		else
			button:SetPoint("TOPLEFT", frame, "TOPLEFT", 38, -34)
		end
		button:SetFrameLevel(frame:GetFrameLevel() + 10)
		button:Show()
	end
end

-- Off: the search box as Blizzard had it, its width and its place (also with the bags closed:
-- Blizzard may not place it again when they open).
local function RestoreSearchBox()
	local search = BagItemSearchBox
	if not (search and search.lefthyWidth) then
		return
	end
	search:SetWidth(SearchWidth(search))
	if search.lefthyX and search:GetNumPoints() == 1 then
		local point, relative, relativePoint, x, y = search:GetPoint(1)
		if point == "TOPLEFT" and math.abs(x - search.lefthyX) < 0.5 then
			search:ClearAllPoints()
			search:SetPoint(point, relative, relativePoint, x - SORT_ROOM, y)
		end
	end
	search.lefthyWidth, search.lefthyX = nil, nil
end

function ns.ApplyGamepadBagSort(on)
	if not on then
		RestoreSearchBox()
	end
	for _, frame in ipairs(ContainerFrames()) do
		if on and not sortHooked[frame] then
			sortHooked[frame] = true
			if frame.UpdateSearchBox then
				hooksecurefunc(frame, "UpdateSearchBox", ShowSortButton)
			end
			frame:HookScript("OnShow", ShowSortButton)
		end
		if on then
			ShowSortButton(frame)
		elseif frame:IsShown() and frame.UpdateSearchBox then
			frame:UpdateSearchBox() -- off: as Blizzard has it
		end
	end
	if not on and ownSortButton then
		ownSortButton:Hide()
		ownSortButton:ClearAllPoints()
		ownSortButton:SetParent(UIParent) -- (not left on a bag)
	end
end
