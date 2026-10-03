local _, ns = ...
local L = ns.L

-- Misc Tweaks 6: mark quests that are new in WoW: Forever.
--
-- Forever adds over a thousand quests to the Classic world, and the client has no flag for them,
-- so Data/ForeverQuests.lua lists them (generated from the client's quest tables by
-- tools/update-forever-quests.ps1). Two places get a badge in Blizzard's own "new" look
-- (NEW_CAPS text with the collections-newglow glow):
--   * quest log: "NEW" left of the title, in the gap Blizzard only uses for bonus objectives;
--     hovering the quest adds a line to its tooltip;
--   * quest dialog (accept, progress, turn in): "New in WoW: Forever" in the top right corner.
-- The badges are our own frames; Blizzard's buttons and texts aren't changed. The quest log is
-- marked from a post-hook on QuestLogQuests_Update (only our frames are touched there, and doing
-- it right away keeps a reused title button from showing a stale badge for a frame); the
-- dialog on the frame after its events.

local GLOW_ATLAS = "collections-newglow"
local TIP_R, TIP_G, TIP_B = 0.4, 1, 0.75

local newQuests -- questID -> true, parsed on first use
local active = false
local logBadges = {}     -- quest log title button -> badge
local hookedButtons = {}
local logHooked = false
local dialogBadge
local driver = CreateFrame("Frame")
local events = CreateFrame("Frame")

local function IsNew(questID)
	if not newQuests then
		newQuests = {}
		for first, last in (ns.FOREVER_QUEST_IDS or ""):gmatch("(%d+)%-?(%d*)") do
			first = tonumber(first)
			for id = first, tonumber(last) or first do
				newQuests[id] = true
			end
		end
	end
	return type(questID) == "number" and newQuests[questID] == true
end

local function CreateBadge(parent, text, fontObject)
	local badge = CreateFrame("Frame", nil, parent)
	badge:SetFrameLevel(parent:GetFrameLevel() + 5)
	badge.Label = badge:CreateFontString(nil, "OVERLAY", fontObject)
	badge.Label:SetPoint("CENTER")
	badge.Label:SetText(text)
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(GLOW_ATLAS) then
		badge.Glow = badge:CreateTexture(nil, "BACKGROUND")
		badge.Glow:SetAtlas(GLOW_ATLAS)
		badge.Glow:SetPoint("TOPLEFT", badge.Label, "TOPLEFT", -12, 8)
		badge.Glow:SetPoint("BOTTOMRIGHT", badge.Label, "BOTTOMRIGHT", 12, -8)
	end
	badge:SetSize((badge.Label:GetStringWidth() or 20) + 4, 14)
	badge:Hide()
	return badge
end

---------------------------------------------------------------------------
-- Quest log
---------------------------------------------------------------------------

local function AddTooltipLine(button)
	local badge = logBadges[button]
	if badge and badge:IsShown() and GameTooltip:IsOwned(button) then
		GameTooltip:AddLine(L["New in WoW: Forever"], TIP_R, TIP_G, TIP_B)
		GameTooltip:Show()
	end
end

local function UpdateQuestLog()
	for _, badge in pairs(logBadges) do
		badge:Hide()
	end
	local pool = active and QuestScrollFrame and QuestScrollFrame.titleFramePool
	if not pool then
		return
	end
	for button in pool:EnumerateActive() do
		if IsNew(button.questID) then
			local badge = logBadges[button]
			if not badge then
				badge = CreateBadge(button, NEW_CAPS or "NEW", "GameFontHighlightSmall")
				badge:SetPoint("TOPRIGHT", button.Text, "TOPLEFT", -3, 1)
				logBadges[button] = badge
			end
			if not hookedButtons[button] then
				hookedButtons[button] = true
				button:HookScript("OnEnter", AddTooltipLine)
			end
			badge:Show()
		end
	end
end

local function HookQuestLog()
	if logHooked or type(QuestLogQuests_Update) ~= "function" then
		return
	end
	logHooked = true
	hooksecurefunc("QuestLogQuests_Update", function()
		local ok, err = pcall(UpdateQuestLog)
		if not ok then
			geterrorhandler()(err)
		end
	end)
end

---------------------------------------------------------------------------
-- Quest dialog
---------------------------------------------------------------------------

local function UpdateDialog()
	driver:Hide()
	if not QuestFrame then
		return
	end
	local questID = active and QuestFrame:IsShown() and GetQuestID and GetQuestID()
	local show = IsNew(questID)
	if show and not dialogBadge then
		dialogBadge = CreateBadge(QuestFrame, L["New in WoW: Forever"], "GameFontHighlight")
		dialogBadge:SetPoint("TOPRIGHT", QuestFrame, "TOPRIGHT", -14, -32)
	end
	if dialogBadge then
		dialogBadge:SetShown(show)
	end
end

driver:Hide()
driver:SetScript("OnUpdate", UpdateDialog)
events:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" then
		HookQuestLog()
	else -- QUEST_DETAIL, QUEST_PROGRESS, QUEST_COMPLETE, QUEST_FINISHED
		driver:Show() -- next frame: the quest frame has been shown or hidden by then
	end
end)

-- Called by Tweaks.lua when the tweak is switched (on the next frame, never in a callback).
function ns.ApplyForeverQuests(on)
	active = on
	if on then
		HookQuestLog()
		for _, event in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_FINISHED", "ADDON_LOADED" }) do
			pcall(events.RegisterEvent, events, event)
		end
	else
		events:UnregisterAllEvents()
	end
	UpdateQuestLog()
	UpdateDialog()
end

-- For tests and /lefthy tweaks status.
function ns.IsForeverQuest(questID)
	return IsNew(questID)
end

function ns.GetForeverQuestBadges()
	return logBadges, dialogBadge
end
