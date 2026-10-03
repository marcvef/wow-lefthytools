local _, ns = ...
local L = ns.L

-- Misc Tweaks 6: mark quests that are new in WoW: Forever.
--
-- Forever adds over a thousand quests to the Classic world, and the client has no flag for them,
-- so Data/ForeverQuests.lua lists them (generated from the client's quest tables by
-- tools/update-forever-quests.ps1). It also lists the later Classic quests (Season of Discovery,
-- Hardcore, Anniversary) Forever's client carries: never in original Classic either, so they're
-- marked too. The marker is a coloured "NEW" (Blizzard's NEW_CAPS, so "NEU" on a German client)
-- right after the quest's name:
--   * quest log: appended to the title of the entry (post-hook on QuestLogQuests_Update);
--     hovering the entry adds "New in WoW: Forever" (or "Not in the original Classic") to its
--     tooltip;
--   * quest details in the log and the quest window (accept, turn in): appended to the title
--     (post-hook on QuestInfo_Display), and on the "progress" page of the quest window
--     (QuestFrameProgressPanel's OnShow).
-- Quest log entries are sized for their title before our hook runs, so the marker is only
-- appended if the title keeps its number of lines; otherwise it goes into the free space at the
-- right end of the entry (an own label), so nothing overlaps. Detail titles may wrap: the text
-- below is anchored to them.

local MARKER_COLOR = "|cff4de1ff"
local TIP_R, TIP_G, TIP_B = 0.3, 0.88, 1

local NEW_IN_FOREVER, LATER_CLASSIC = 1, 2
local newQuests -- questID -> NEW_IN_FOREVER or LATER_CLASSIC, parsed on first use
local active = false
local spareLabels = {}   -- quest log title button -> our "NEW" label for long titles
local hookedButtons = {}
local hooked = false

-- Which kind of new a quest is, or nil for original Classic quests. Two lists (Data/ForeverQuests.lua):
-- new in WoW: Forever, and later Classic content (Season of Discovery, Hardcore, Anniversary) that
-- Forever has too; both were never in original Classic, so both get the marker.
local function Kind(questID)
	if not newQuests then
		newQuests = {}
		for _, list in ipairs({ { ns.LATER_CLASSIC_QUEST_IDS, LATER_CLASSIC }, { ns.FOREVER_QUEST_IDS, NEW_IN_FOREVER } }) do
			for first, last in (list[1] or ""):gmatch("(%d+)%-?(%d*)") do
				first = tonumber(first)
				for id = first, tonumber(last) or first do
					newQuests[id] = list[2]
				end
			end
		end
	end
	return type(questID) == "number" and newQuests[questID] or nil
end

local function IsNew(questID)
	return Kind(questID) ~= nil
end

local function Marker()
	return " " .. MARKER_COLOR .. (NEW_CAPS or "NEW") .. "|r"
end

local function HasMarker(text)
	local marker = Marker()
	return type(text) == "string" and text:sub(-#marker) == marker
end

-- Appends the marker to a title. keepLines: only if the title doesn't get another line.
local function AppendMarker(fontString, keepLines)
	local text = fontString and fontString:GetText()
	if type(text) ~= "string" or text == "" then
		return false
	end
	if HasMarker(text) then
		return true
	end
	local lines = keepLines and fontString:GetNumLines()
	fontString:SetText(text .. Marker())
	if keepLines and fontString:GetNumLines() > lines then
		fontString:SetText(text) -- the entry was sized for the shorter title
		return false
	end
	return true
end

local function RemoveMarker(fontString)
	local text = fontString and fontString:GetText()
	if HasMarker(text) then
		fontString:SetText(text:sub(1, -#Marker() - 1))
	end
end

---------------------------------------------------------------------------
-- Quest log entries
---------------------------------------------------------------------------

local function AddTooltipLine(button)
	local kind = active and Kind(button.questID)
	if kind and GameTooltip:IsOwned(button) then
		GameTooltip:AddLine(kind == NEW_IN_FOREVER and L["New in WoW: Forever"] or L["Not in the original Classic (from its later seasons)"],
			TIP_R, TIP_G, TIP_B)
		GameTooltip:Show()
	end
end

-- A title too long for the marker: our own label at the right end of the entry, in front of the
-- track checkbox, where Forever never shows the quest type icon.
local function SpareLabel(button)
	local label = spareLabels[button]
	if not label then
		label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetPoint("RIGHT", button.Checkbox or button, button.Checkbox and "LEFT" or "RIGHT", -4, 0)
		label:SetText(MARKER_COLOR .. (NEW_CAPS or "NEW") .. "|r")
		spareLabels[button] = label
	end
	return label
end

local function UpdateQuestLog()
	for _, label in pairs(spareLabels) do
		label:Hide()
	end
	local pool = QuestScrollFrame and QuestScrollFrame.titleFramePool
	if not pool then
		return
	end
	for button in pool:EnumerateActive() do
		if active and IsNew(button.questID) then
			if not AppendMarker(button.Text, true) then
				SpareLabel(button):Show()
			end
			if not hookedButtons[button] then
				hookedButtons[button] = true
				button:HookScript("OnEnter", AddTooltipLine)
			end
		else
			RemoveMarker(button.Text) -- switched off: the open log loses its markers right away
		end
	end
end

---------------------------------------------------------------------------
-- Quest details (log) and quest window
---------------------------------------------------------------------------

local function UpdateDetailsTitle()
	if not QuestInfoTitleHeader then
		return
	end
	local questID
	if QuestInfoFrame and QuestInfoFrame.questLog then
		questID = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
	else
		questID = GetQuestID and GetQuestID()
	end
	if active and IsNew(questID) then
		AppendMarker(QuestInfoTitleHeader, false)
	else
		RemoveMarker(QuestInfoTitleHeader)
	end
end

local function UpdateProgressTitle()
	if not QuestProgressTitleText then
		return
	end
	if active and IsNew(GetQuestID and GetQuestID()) then
		AppendMarker(QuestProgressTitleText, false)
	else
		RemoveMarker(QuestProgressTitleText)
	end
end

local function Safely(fn)
	return function()
		local ok, err = pcall(fn)
		if not ok then
			geterrorhandler()(err)
		end
	end
end

-- Post-hooks run right after Blizzard filled in the titles, and only change those texts.
local function Hook()
	if hooked then
		return
	end
	hooked = true
	if type(QuestLogQuests_Update) == "function" then
		hooksecurefunc("QuestLogQuests_Update", Safely(UpdateQuestLog))
	end
	if type(QuestInfo_Display) == "function" then
		hooksecurefunc("QuestInfo_Display", Safely(UpdateDetailsTitle))
	end
	if QuestFrameProgressPanel then
		QuestFrameProgressPanel:HookScript("OnShow", Safely(UpdateProgressTitle))
	end
end

-- Called by Tweaks.lua when the tweak is switched (on the next frame, never in a callback).
function ns.ApplyForeverQuests(on)
	active = on
	if on then
		Hook()
	end
	UpdateQuestLog()
	UpdateDetailsTitle()
	UpdateProgressTitle()
end

-- New in WoW: Forever itself (Chronicle counts those); later Classic quests don't count.
function ns.IsForeverQuest(questID)
	return Kind(questID) == NEW_IN_FOREVER
end

-- For tests: whether a quest gets the marker.
function ns.IsMarkedQuest(questID)
	return IsNew(questID)
end

function ns.GetForeverQuestLabels()
	return spareLabels
end
