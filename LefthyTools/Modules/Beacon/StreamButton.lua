local _, ns = ...
local LT = ns.LT
local L = ns.L
local M = LT:GetModule("beacon")
local B = ns.Beacon
local S = B.Stream

-- The fight stream's minimap button (Core/Window.lua's LT.Window.MinimapButton: the usual addon
-- look on the minimap's edge, dragged along it): a spyglass, with a small red dot while you watch
-- someone. Click: a list (our own, Blizzard's menu taints gamepad mode) titled "Stream" with the
-- friends online who share their fights (ticked: watching; red: in a fight); click one to open or
-- close their stream. Below: your own stream, and closing them all. Right-click: Beacon's settings.
-- Setting streamButton; nothing runs for it unless it's clicked or hovered.

local ICON = "Interface\\Icons\\INV_Misc_Spyglass_03"
local LIST_WIDTH = 260
local button, list

local function Friends()
	local friends = {}
	for id, peer in pairs(B.peers) do
		if S.CanWatch(id) or S.IsWatching(id) then
			friends[#friends + 1] = { id = id, peer = peer }
		end
	end
	table.sort(friends, function(a, b) return (a.peer.name or "") < (b.peer.name or "") end)
	return friends
end

local function Entries()
	local items = { { title = L["Stream"] } }
	local friends, any = Friends(), false
	for _, friend in ipairs(friends) do
		local peer = friend.peer
		local text = LT.Window.ClassColorCode(peer.classFile) .. (peer.name or "?") .. "|r"
		local where = peer.subzone ~= "" and peer.subzone or peer.area
		text = text .. "  |cff999999" .. L["Level %d"]:format(peer.level or 0) .. (where and ("  " .. where) or "") .. "|r"
		if peer.dead or peer.ghost then
			text = text .. "  |cffff5050" .. L["dead"] .. "|r"
		elseif peer.combat then
			text = text .. "  |cffff5050" .. L["in combat"] .. "|r"
		end
		local watching = S.IsWatching(friend.id)
		any = any or watching
		items[#items + 1] = { text = text, value = friend.id, selected = watching }
	end
	if #friends == 0 then
		items[#items + 1] = { note = L["No friend shares their fights right now."] }
	end
	items[#items + 1] = { divider = true }
	items[#items + 1] = { text = L["Your own stream"], value = "me" }
	if any then
		items[#items + 1] = { text = L["Close all streams"], value = "stop" }
	end
	return items
end

local function OnPick(value)
	if value == "me" then
		S.OpenView("me")
	elseif value == "stop" then
		S.StopWatching("")
	else
		B.StreamToggle(value, "button")
	end
	S.UpdateButton()
end

local function Names(ids)
	local names = {}
	for _, id in ipairs(ids) do
		local peer = B.peers[id]
		names[#names + 1] = LT.Window.ClassColorCode(peer and peer.classFile) .. S.FriendName(id) .. "|r"
	end
	return table.concat(names, ", ")
end

local function OnEnter(self)
	if list and list:IsShown() then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText(L["Fight stream"], 1, 0.82, 0)
	local watching, watchers = {}, {}
	for id in pairs(B.peers) do
		if S.IsWatching(id) then
			watching[#watching + 1] = id
		end
	end
	for id in pairs(S.Watchers()) do
		watchers[#watchers + 1] = id
	end
	if #watching > 0 then
		GameTooltip:AddLine(L["You watch: %s"]:format(Names(watching)), 1, 1, 1, true)
	end
	if #watchers > 0 then
		GameTooltip:AddLine(L["Watching you: %s"]:format(Names(watchers)), 1, 0.4, 0.35, true)
	end
	GameTooltip:AddLine(L["Click: watch a friend's fight"], 0.8, 0.8, 0.8)
	GameTooltip:AddLine(L["Right-click: settings"], 0.8, 0.8, 0.8)
	GameTooltip:AddLine(L["Drag: move it along the minimap"], 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

local function OnClick(self, mouseButton)
	if mouseButton == "RightButton" then
		list:Hide()
		LT:OpenSettings(M)
	else
		list:Toggle()
	end
end

local function Create()
	button = LT.Window.MinimapButton("LefthyToolsStreamMinimapButton", { icon = ICON, db = M.db,
		angleKey = "streamButtonAngle", angle = 235, onClick = OnClick, onEnter = OnEnter })
	button.Live = button:CreateTexture(nil, "OVERLAY", nil, 2)
	button.Live:SetSize(8, 8)
	button.Live:SetPoint("TOPRIGHT", -5, -4)
	button.Live:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
	button.Live:SetVertexColor(1, 0.2, 0.15)
	button.Live:Hide()
	list = LT.Window.PopupList(button, LIST_WIDTH, Entries, OnPick)
	list:SetPoint("TOPRIGHT", button, "BOTTOMLEFT", 8, 4)
	button.List = list
end

-- Beacon switched on or off, the setting, a stream opened or closed (always cheap).
function S.UpdateButton()
	local show = M.enabled and M.db.streamButton and Minimap ~= nil
	if show and not button then
		Create()
	end
	if not button then
		return
	end
	button:SetShown(show)
	if show then
		button:Place()
		local watching = false
		for id in pairs(B.peers) do
			watching = watching or S.IsWatching(id)
		end
		button.Live:SetShown(watching)
	else
		list:Hide()
	end
end

function S.Button()
	return button
end
