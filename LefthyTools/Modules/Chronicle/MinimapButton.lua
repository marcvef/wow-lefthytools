local _, ns = ...
local LT = ns.LT
local L = ns.L
local C = ns.Chronicle
local M = C.module

-- Chronicle's minimap button: a round button on the minimap's edge in the usual addon look
-- (tracking border, dark background, a book). Click opens or closes the journal, right-click
-- opens Chronicle's settings, dragging moves it along the edge (the angle is saved). It's a child
-- of the Minimap, so it hides and fades with it (Mirage). An OnUpdate runs only while dragging.

local ICON = "Interface\\Icons\\INV_Misc_Book_09"
local atan2 = math.atan2 or math.atan -- WoW's Lua 5.1 / the tests' Lua 5.3
local button

local function Place()
	local angle = math.rad(M.db.minimapAngle or 210)
	local x, y = math.cos(angle), math.sin(angle)
	if GetMinimapShape and GetMinimapShape() == "SQUARE" then
		local edge = math.max(math.abs(x), math.abs(y))
		x, y = x / edge, y / edge -- onto the square's edge
	end
	local radius = Minimap:GetWidth() / 2 + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x * radius, y * radius)
end

-- Degrees from the minimap's centre to the cursor: 0 = right, counter-clockwise.
local function OnDragUpdate()
	local mx, my = Minimap:GetCenter()
	if not mx then
		return
	end
	local scale = Minimap:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	M.db.minimapAngle = math.floor(math.deg(atan2(cy / scale - my, cx / scale - mx)) % 360 + 0.5)
	Place()
end

local function OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText("Chronicle", 1, 0.82, 0)
	local session = C.SessionLine and C.SessionLine(false)
	if session then
		GameTooltip:AddLine(session, 1, 1, 1, true)
	end
	GameTooltip:AddLine(L["Click: open or close the journal"], 0.8, 0.8, 0.8)
	GameTooltip:AddLine(L["Right-click: settings"], 0.8, 0.8, 0.8)
	GameTooltip:AddLine(L["Drag: move it along the minimap"], 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

local function OnLeave(self)
	if GameTooltip:IsOwned(self) then
		GameTooltip:Hide()
	end
end

local function OnClick(self, mouseButton)
	OnLeave(self)
	if mouseButton == "RightButton" then
		LT:OpenSettings(M)
	else
		M:Toggle()
	end
end

local function Create()
	button = CreateFrame("Button", "LefthyToolsChronicleMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetSize(20, 20)
	background:SetPoint("TOPLEFT", 7, -5)
	button.Icon = button:CreateTexture(nil, "ARTWORK")
	button.Icon:SetTexture(ICON)
	button.Icon:SetSize(17, 17)
	button.Icon:SetPoint("TOPLEFT", 7, -6)
	button.Icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	button:SetScript("OnEnter", OnEnter)
	button:SetScript("OnLeave", OnLeave)
	button:SetScript("OnClick", OnClick)
	button:SetScript("OnDragStart", function(self)
		OnLeave(self)
		self:SetScript("OnUpdate", OnDragUpdate)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
end

-- After login, switching Chronicle on or off and the setting (always on the next frame).
function C.UpdateMinimapButton()
	local show = M.enabled and M.db.minimapButton and Minimap ~= nil
	if show and not button then
		Create()
	end
	if button then
		button:SetShown(show)
		if show then
			Place()
		end
	end
end

function C.MinimapButton()
	return button
end
