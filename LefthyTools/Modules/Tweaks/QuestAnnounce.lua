local _, ns = ...
local L = ns.L
local M = ns.LT:GetModule("tweaks")

-- Misc Tweaks: quest progress in party chat (questAnnounce; like Questie's QuestieAnnounce).
--
-- An objective is announced when it changes from unfinished to finished; when that completes the
-- whole quest, one "quest complete" line replaces it. Quests and objectives that are already done
-- when first seen (accepted that way, or at login) stay silent. Quests are tracked by questID, so
-- collapsed quest log headers don't hide progress. Party chat in a normal party, instance chat in
-- an instance group, nothing solo or in a raid. Addon chat can be locked down by the client
-- (C_ChatInfo.InChatMessagingLockdown); messages wait until that lifts. The objective text comes
-- from the client in its language, so the wrapper text is localized too (party members read it).

local ANNOUNCE_MARKER = "{rt1} " -- star icon, like Questie
local ANNOUNCE_MAX_AGE = 10       -- seconds a line waits for a chat lockdown to lift; then it's old news
local questEvents = CreateFrame("Frame")
local questState = {}    -- questID -> { complete = bool, objectives = { [i] = finished } }
local announceQueue = {} -- { text, at }
local scanScheduled, flushScheduled = false, false

local function AnnounceChannel()
	if IsInRaid() then
		return nil
	end
	if IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2) then
		return "INSTANCE_CHAT"
	end
	if IsInGroup(LE_PARTY_CATEGORY_HOME or 1) then
		return "PARTY"
	end
	return nil
end

local function FlushAnnouncements()
	flushScheduled = false
	local now = GetTime()
	while announceQueue[1] and now - announceQueue[1].at > ANNOUNCE_MAX_AGE do
		table.remove(announceQueue, 1) -- a lockdown that lasts (a whole dungeon): old news by now
	end
	if #announceQueue == 0 then
		return
	end
	local chat = C_ChatInfo
	if chat and chat.InChatMessagingLockdown and chat.InChatMessagingLockdown() then
		flushScheduled = true
		C_Timer.After(1, FlushAnnouncements) -- no event for the lockdown ending; retry
		return
	end
	local channel = AnnounceChannel()
	if channel then
		local send = (chat and chat.SendChatMessage) or SendChatMessage
		for _, item in ipairs(announceQueue) do
			pcall(send, item.text, channel)
		end
	end
	wipe(announceQueue)
end

local function Announce(message)
	if not AnnounceChannel() then
		return
	end
	announceQueue[#announceQueue + 1] = { text = ANNOUNCE_MARKER .. message, at = GetTime() }
	if not flushScheduled then
		flushScheduled = true
		C_Timer.After(0, FlushAnnouncements)
	end
end

local function QuestLabel(questID)
	local link = GetQuestLink and GetQuestLink(questID)
	if link then
		return link
	end
	return "[" .. (C_QuestLog.GetTitleForQuestID(questID) or questID) .. "]"
end

local function ReadQuest(questID)
	local state = {
		complete = C_QuestLog.IsComplete(questID) and true or false,
		objectives = {},
		texts = {},
	}
	for i, objective in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
		state.objectives[i] = objective.finished and true or false
		state.texts[i] = objective.text
	end
	return state
end

local function ScanQuests(announce)
	-- Pick up new quests from the log (silently); quests under collapsed headers are
	-- already known by ID from earlier scans.
	for index = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(index)
		if info and not info.isHeader and not info.isHidden and info.questID and info.questID > 0
			and not questState[info.questID] then
			questState[info.questID] = ReadQuest(info.questID)
		end
	end

	for questID, before in pairs(questState) do
		if not C_QuestLog.GetLogIndexForQuestID(questID) then
			questState[questID] = nil -- turned in or abandoned
		else
			local now = ReadQuest(questID)
			if announce then
				if now.complete and not before.complete then
					Announce(L["%s: quest complete!"]:format(QuestLabel(questID)))
				else
					for i, finished in ipairs(now.objectives) do
						if finished and before.objectives[i] == false and now.texts[i] then
							Announce(("%s: %s"):format(QuestLabel(questID), now.texts[i]))
						end
					end
				end
			end
			questState[questID] = now
		end
	end
end

local function RequestQuestScan()
	if scanScheduled then
		return
	end
	scanScheduled = true
	C_Timer.After(0.3, function() -- quest log events come in bursts
		scanScheduled = false
		if M:IsTweakActive("questAnnounce") then
			ScanQuests(true)
		end
	end)
end

questEvents:SetScript("OnEvent", function(_, event, questID)
	if (event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN") and questID then
		questState[questID] = nil
	end
	RequestQuestScan()
end)

-- Called by Tweaks.lua when the switch changes (on the next frame, never in a callback).
function ns.ApplyQuestAnnounce(on)
	wipe(questState)
	wipe(announceQueue)
	if on then
		for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "QUEST_ACCEPTED",
			"QUEST_REMOVED", "QUEST_TURNED_IN" }) do
			pcall(questEvents.RegisterEvent, questEvents, event)
		end
		pcall(questEvents.RegisterUnitEvent, questEvents, "UNIT_QUEST_LOG_CHANGED", "player")
		ScanQuests(false) -- baseline: whatever is already done now isn't news
	else
		questEvents:UnregisterAllEvents()
	end
end
