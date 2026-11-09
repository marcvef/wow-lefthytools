local _, ns = ...
local L = ns.L
local LT = ns.LT
local M = LT:GetModule("tweaks")

-- Misc Tweaks: movable loot rolls (movableLootRolls).
--
-- Blizzard's Need / Greed windows (GroupLootFrame1..4) sit in GroupLootContainer, which Blizzard keeps
-- in its bottom stack of managed frames (BottomManagedFrameTemplate: above the action bars, laid out
-- with them) and never lets you move. Moving that container from addon code would mean taking it
-- out of the stack the action bars are laid out in (a protected layout in a fight). So the container
-- stays; its roll windows are placed anew right after Blizzard places them (a post-hook on
-- GroupLootContainer_Update, which runs for each roll added or gone): stacked on an anchor of ours,
-- where the player dragged them (any roll window drags them all), saved in Misc Tweaks' settings.
-- The roll windows aren't protected, so this works in fights too. With nothing saved, Blizzard's spot.
-- Controller UI: Blizzard shows rolls in a window of its own (the container is hidden then), untouched.

local DEFAULT_GAP = 100 -- between rolls, like the container's reservedSize
local anchor            -- ours: the rolls stack up from its bottom
local on = false
local hooked = false
local hookedFrames = {}
local moved = false     -- roll windows are on our anchor (to give back when switched off or reset)
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

local function Anchor()
	if anchor then
		return anchor
	end
	anchor = CreateFrame("Frame", "LefthyToolsLootRollAnchor", UIParent)
	anchor:SetSize(243, 84) -- (a roll window's size)
	anchor:SetFrameStrata("DIALOG")
	anchor:SetMovable(true)
	anchor:SetClampedToScreen(true)
	anchor:EnableMouse(false) -- (only while being placed: it's not in the way otherwise)
	anchor.Back = anchor:CreateTexture(nil, "BACKGROUND")
	anchor.Back:SetAllPoints()
	anchor.Back:SetColorTexture(0.04, 0.05, 0.07, 0.85)
	anchor.Edge = anchor:CreateTexture(nil, "BORDER")
	anchor.Edge:SetPoint("TOPLEFT")
	anchor.Edge:SetPoint("TOPRIGHT")
	anchor.Edge:SetHeight(1)
	anchor.Edge:SetColorTexture(1, 0.82, 0, 0.6)
	anchor.Label = anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	anchor.Label:SetPoint("CENTER")
	anchor.Label:SetWidth(225)
	anchor.Label:SetText(L["Loot rolls appear here. Drag to move, right-click when done."])
	anchor.Back:Hide()
	anchor.Edge:Hide()
	anchor.Label:Hide()
	return anchor
end

-- Where the anchor goes: the saved spot, or (being placed with nothing saved) above the action bars.
local function PlaceAnchor()
	local a = Anchor()
	local pos = M.db.lootRollPos
	a:ClearAllPoints()
	if pos then
		a:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.left, pos.top)
	else
		a:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 260)
	end
end

local function Save()
	local a = Anchor()
	local left, top = a:GetLeft(), a:GetTop()
	if left and top then
		M.db.lootRollPos = { left = left, top = top }
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
	local a = Anchor()
	if not M.db.lootRollPos then
		local index = 1
		for i, f in pairs(container and container.rollFrames or {}) do
			if f == frame then
				index = i
			end
		end
		local left, top = frame:GetLeft(), frame:GetTop()
		if left and top then
			local scale = (frame:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
			M.db.lootRollPos = { left = left * scale, top = top * scale - Gap(container) * (index - 1) }
		else
			PlaceAnchor() -- (its spot can't be read: above the action bars)
			Save()
		end
		Relayout(container)
	end
	dragging = true
	a:StartMoving()
end

local function StopDrag()
	if not dragging then
		return
	end
	dragging = false
	anchor:StopMovingOrSizing()
	anchor:SetUserPlaced(false) -- (the spot lives in our settings, not the client's layout cache)
	Save()
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
	local a = Anchor()
	a:RegisterForDrag("LeftButton")
	a:SetScript("OnDragStart", function()
		dragging = true
		a:StartMoving()
	end)
	a:SetScript("OnDragStop", StopDrag)
	a:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then
			ns.LootRollPreview(false)
		end
	end)
end

-- The anchor shown to place the rolls without one (Misc Tweaks' button, /lefthy tweaks lootpos);
-- show == nil: the other way round.
function ns.LootRollPreview(show)
	local a = Anchor()
	if show == nil then
		show = not a.Label:IsShown()
	end
	show = show and on and not PadUI()
	if show then
		Hook()
		PlaceAnchor()
	end
	a:EnableMouse(show)
	a.Back:SetShown(show)
	a.Edge:SetShown(show)
	a.Label:SetShown(show)
	return show
end

-- Back to Blizzard's spot (/lefthy tweaks resetloot, the settings' button).
function M:ResetLootRolls()
	self.db.lootRollPos = nil
	ns.LootRollPreview(false)
	Relayout()
end

-- Called by Tweaks.lua when the switch changes (on the next frame).
function ns.ApplyLootRolls(value)
	on = value
	if on then
		Hook()
	else
		ns.LootRollPreview(false)
	end
	Relayout()
end
