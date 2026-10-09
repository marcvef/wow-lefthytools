local _, ns = ...
local LT = ns.LT
local L = ns.L
local C = ns.Chronicle
local M = C.module

-- Chronicle's minimap button (Core/Window.lua's LT.Window.MinimapButton: the usual addon look, a
-- child of the Minimap, dragged along its edge): a book. Click opens or closes the journal,
-- right-click opens Chronicle's settings; the tooltip shows this session.

local ICON = "Interface\\Icons\\INV_Misc_Book_09"
local button

local function OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText("Chronicle", 1, 0.82, 0)
	local session = C.SessionLine and C.SessionLine(false)
	if session then
		GameTooltip:AddLine(session, 1, 1, 1, true)
	end
	local news = C.UnseenCount and C.UnseenCount() or 0
	if news > 0 then
		GameTooltip:AddLine(L["%d new from friends"]:format(news), 0.5, 0.8, 1)
	end
	GameTooltip:AddLine(L["Click: open or close the journal"], 0.8, 0.8, 0.8)
	GameTooltip:AddLine(L["Right-click: settings"], 0.8, 0.8, 0.8)
	GameTooltip:AddLine(L["Drag: move it along the minimap"], 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

local function OnClick(_, mouseButton)
	if mouseButton == "RightButton" then
		LT:OpenSettings(M)
	else
		M:Toggle()
	end
end

-- After login, switching Chronicle on or off and the setting (always on the next frame).
function C.UpdateMinimapButton()
	local show = M.enabled and M.db.minimapButton and Minimap ~= nil
	if show and not button then
		button = LT.Window.MinimapButton("LefthyToolsChronicleMinimapButton", { icon = ICON, db = M.db,
			angleKey = "minimapAngle", angle = 210, onClick = OnClick, onEnter = OnEnter })
		-- New from friends since the journal was last open: a small blue dot.
		button.New = button:CreateTexture(nil, "OVERLAY", nil, 2)
		button.New:SetSize(8, 8)
		button.New:SetPoint("TOPRIGHT", -5, -4)
		button.New:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
		button.New:SetVertexColor(0.35, 0.7, 1)
		button.New:Hide()
	end
	if button then
		button:SetShown(show)
		if show then
			button:Place()
		end
		C.UpdateNewDot()
	end
end

-- The blue dot: friends' news the journal hasn't shown yet.
function C.UpdateNewDot()
	if button then
		button.New:SetShown((C.UnseenCount and C.UnseenCount() or 0) > 0)
	end
end

function C.MinimapButton()
	return button
end
