local _, ns = ...
local LT = ns.LT
local M = LT:GetModule("tweaks")

-- Misc Tweaks: movable loot rolls (movableLootRolls), like the movable bags: drag the roll window, it
-- comes up there from then on. /lefthy tweaks resetloot puts it back.
--
--   * Controller UI: rolls show in GamepadGroupLootRollFrame. Blizzard gave it OnDragStart/OnDragStop
--     (StartMoving, StopMovingOrSizing) but never made it movable or registered a drag: that's all
--     this adds, plus its spot kept (lootRollPadPos) and put back whenever it shows.
--   * Mouse and keyboard: the Need / Greed windows (GroupLootFrame1..4) sit in GroupLootContainer, one
--     of the bottom managed frames laid out with the action bars (taking it out of that stack from
--     addon code would touch the action bars' layout, protected in a fight). So the container stays;
--     its roll windows are placed anew right after Blizzard places them (a post-hook on
--     GroupLootContainer_Update), stacked on an anchor of ours that dragging any of them moves
--     (lootRollPos). The roll windows aren't protected, so this works in fights too.

local DEFAULT_GAP = 100 -- between rolls, like the container's reservedSize
local PAD_DEFAULT = { "TOPLEFT", 38, -347 } -- GamepadGroupLootRollFrame's anchor in Blizzard's XML
local anchor            -- ours (mouse and keyboard): the rolls stack up from its bottom
local on = false
local hooked, padHooked = false, false
local hookedFrames = {}
local moved = false     -- roll windows on our anchor (to give back when switched off or reset)
local padMoved = false  -- the controller's roll window on our saved spot
local dragging = false

local function PadUI()
	return InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() == true
end

local function Container()
	return GroupLootContainer
end

local function Gap(container)
	return (container and tonumber(container.reservedSize)) or DEFAULT_GAP
end

-- Where a dragged frame was dropped, in UIParent units (left, top), or nil.
local function Spot(frame)
	local left, top = frame:GetLeft(), frame:GetTop()
	if left and top then
		local scale = (frame.GetEffectiveScale and frame:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
		return { left = left * scale, top = top * scale }
	end
end

---------------------------------------------------------------------------
-- Controller UI: Blizzard's own roll window, made movable
---------------------------------------------------------------------------

local function PlacePad()
	local frame = GamepadGroupLootRollFrame
	if not frame then
		return
	end
	local pos = on and M.db.lootRollPadPos
	if pos then
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.left, pos.top)
		padMoved = true
	elseif padMoved then
		frame:ClearAllPoints()
		frame:SetPoint(PAD_DEFAULT[1], UIParent, PAD_DEFAULT[1], PAD_DEFAULT[2], PAD_DEFAULT[3])
		padMoved = false
	end
end

local function PadDragStopped(frame)
	if not on then
		return
	end
	frame:SetUserPlaced(false) -- (the spot lives in our settings, not the client's layout cache)
	M.db.lootRollPadPos = Spot(frame)
	padMoved = M.db.lootRollPadPos ~= nil
end

local function SetupPad()
	local frame = GamepadGroupLootRollFrame
	if not frame then
		return
	end
	if not padHooked then
		padHooked = true
		frame:HookScript("OnDragStop", PadDragStopped)
		frame:HookScript("OnShow", PlacePad)
	end
	frame:SetMovable(on)
	frame:SetClampedToScreen(true)
	if on then
		frame:RegisterForDrag("LeftButton") -- (Blizzard's OnDragStart / OnDragStop do the moving)
	else
		frame:RegisterForDrag()
	end
	PlacePad()
end

---------------------------------------------------------------------------
-- Mouse and keyboard: the roll windows on an anchor of ours
---------------------------------------------------------------------------

local function Anchor()
	if not anchor then
		anchor = CreateFrame("Frame", "LefthyToolsLootRollAnchor", UIParent)
		anchor:SetSize(243, 84) -- (a roll window's size)
		anchor:SetMovable(true)
		anchor:SetClampedToScreen(true)
	end
	return anchor
end

local function PlaceAnchor()
	local pos = M.db.lootRollPos
	if pos then
		Anchor():ClearAllPoints()
		anchor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.left, pos.top)
	end
end

-- The roll windows on our anchor (stacked up, the first at the bottom), or back on Blizzard's spot
-- (what GroupLootContainer_Update does).
local function Relayout(container)
	container = container or Container()
	if not (container and container.rollFrames) or PadUI() then
		return -- (the controller UI: Blizzard's own roll window, the container hidden)
	end
	local ours = on and M.db.lootRollPos ~= nil
	if not ours and not moved then
		return -- (Blizzard's own placing stands)
	end
	local gap = Gap(container)
	if ours then
		PlaceAnchor()
	end
	for i = 1, container.maxIndex or 0 do
		local frame = container.rollFrames[i]
		if frame then
			frame:ClearAllPoints()
			if ours then
				frame:SetPoint("BOTTOM", anchor, "BOTTOM", 0, gap * (i - 1))
			else
				frame:SetPoint("CENTER", container, "BOTTOM", 0, gap * (i - 1 + 0.5))
			end
		end
	end
	moved = ours
end

-- A roll window dragged: the first time (nothing saved) the anchor starts where that window's stack is.
local function StartDrag(frame)
	if not on or PadUI() or dragging then
		return
	end
	local container = Container()
	if not M.db.lootRollPos then
		local index = 1
		for i, f in pairs(container and container.rollFrames or {}) do
			if f == frame then
				index = i
			end
		end
		local spot = Spot(frame)
		if not spot then
			return -- (where it is can't be read)
		end
		spot.top = spot.top - Gap(container) * (index - 1)
		M.db.lootRollPos = spot
		Relayout(container)
	end
	dragging = true
	Anchor():StartMoving()
end

local function StopDrag()
	if not dragging then
		return
	end
	dragging = false
	anchor:StopMovingOrSizing()
	anchor:SetUserPlaced(false)
	M.db.lootRollPos = Spot(anchor) or M.db.lootRollPos
	Relayout()
end

local function HookFrame(frame)
	if not frame or hookedFrames[frame] then
		return
	end
	hookedFrames[frame] = true
	frame:RegisterForDrag("LeftButton")
	frame:HookScript("OnDragStart", StartDrag)
	frame:HookScript("OnDragStop", StopDrag)
end

local function OnUpdate(container)
	if on and not PadUI() then
		for i = 1, (container and container.maxIndex) or 0 do
			HookFrame(container.rollFrames[i])
		end
	end
	Relayout(container)
end

local function Hook()
	if hooked or type(GroupLootContainer_Update) ~= "function" then
		return
	end
	hooked = true
	hooksecurefunc("GroupLootContainer_Update", OnUpdate)
end

-- Back to Blizzard's spots (/lefthy tweaks resetloot).
function M:ResetLootRolls()
	self.db.lootRollPos, self.db.lootRollPadPos = nil, nil
	Relayout()
	PlacePad()
end

-- Called by Tweaks.lua when the switch changes (on the next frame).
function ns.ApplyLootRolls(value)
	on = value
	if on then
		Hook()
	end
	Relayout()
	SetupPad()
end
