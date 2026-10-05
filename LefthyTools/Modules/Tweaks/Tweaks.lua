local _, ns = ...
local LT = ns.LT
local L = ns.L

-- Misc Tweaks: small annoyances fixed, each switchable on its own. All tweaks default to on
-- (chosen while the Forever beta still dropped SavedVariables on restart).
-- The combo point tweak lives in ComboPoints.lua.

local M = LT:NewModule("tweaks", {
	title = "Misc Tweaks", -- module names are never translated
	description = L["Small quality-of-life fixes, each one switchable on its own."],
	defaults = {
		statusText = true,
		movableBags = true,
		bagPositions = {},     -- key ("combined" / "bag<id>") -> { left, top } in UIParent units
		savedStatusText = {},  -- CVar values to restore when statusText is switched off
		questAnnounce = true,
		comboPoints = true,
		comboColors = true,
		foreverQuests = true,
		questMap = true,       -- QuestMap.lua
		questMapContinent = "both", -- "off" | "icons" | "areas" | "both"
		questMapWorld = "both",
		questMapZone = "blizzard", -- "blizzard" (the selected quest's area) | "areas" (every quest's)
		questMapClick = true,  -- clicking an icon selects its quest (off: the map zooms in)
		afkScreen = true,      -- AFK.lua
		afkSpin = true,
		levelUp = true,        -- LevelUp.lua
		levelUps = {},         -- "Name-Realm" -> the last level-up's gains (the preview shows them)
		cinematicFlights = true, -- Flight.lua
		flightFriends = true,  -- Beacon friends in the top bar
		flightHide = "all",    -- "all": the whole interface | "chosen": the elements in flightGroups
		flightGroups = (function() -- Mirage's groups (Groups.lua), all hidden until unticked
			local hide = {}
			for _, g in ipairs(ns.MirageData.GROUPS) do
				hide[g.key] = true
			end
			return hide
		end)(),
	},
})

-- The AFK screen used to be part of Mirage: a choice made there carries over once.
function M:OnInitialize()
	local mirage = LT.db.settings.mirage
	if type(mirage) == "table" and mirage.afkScreen ~= nil then
		self.db.afkScreen, self.db.afkSpin = mirage.afkScreen == true, mirage.afkSpin ~= false
		mirage.afkScreen, mirage.afkSpin, mirage.afkSpinning = nil, nil, nil
	end
end

local active = {} -- tweak key -> currently applied

---------------------------------------------------------------------------
-- Hiding the whole interface (the AFK screen, cinematic flights)
--
-- UIParent:SetAlpha, not Hide: SetAlpha isn't protected, so the interface can come back at any
-- moment, in combat too. Several tweaks may want it hidden at once (owner keys); it comes back,
-- to the alpha it had, when none does. fade: seconds to get there; an OnUpdate runs only then.
---------------------------------------------------------------------------

local hiders, restoreAlpha = {}, nil
local fader = CreateFrame("Frame")
fader:Hide()
local fadeFrom, fadeTo, fadeTime, fadeElapsed = 1, 1, 1, 0

local function CurrentAlpha()
	local alpha = UIParent:GetAlpha()
	return (type(alpha) == "number" and not (issecretvalue and issecretvalue(alpha))) and alpha or 1
end

fader:SetScript("OnUpdate", function(self, elapsed)
	fadeElapsed = fadeElapsed + elapsed
	local p = math.min(fadeElapsed / fadeTime, 1)
	UIParent:SetAlpha(fadeFrom + (fadeTo - fadeFrom) * p)
	if p >= 1 then
		self:Hide()
	end
end)

function ns.HideInterface(owner, hide, fade)
	local before = next(hiders) ~= nil
	hiders[owner] = hide and true or nil
	local now = next(hiders) ~= nil
	if before == now then
		return
	end
	if now and not fader:IsShown() then
		restoreAlpha = CurrentAlpha() -- (mid-fade back, the alpha from before still holds)
	end
	local target = now and 0 or (restoreAlpha or 1)
	if fade and fade > 0 then
		fadeFrom, fadeTo, fadeTime, fadeElapsed = CurrentAlpha(), target, fade, 0
		fader:Show()
	else
		fader:Hide()
		UIParent:SetAlpha(target)
	end
end

---------------------------------------------------------------------------
-- 1. Always show health / power values on unit frames
--
-- The bars show their text permanently when the CVar "statusText" is "1"
-- ("statusTextDisplay" picks the format). That's exactly what Blizzard's own
-- Options > Interface > Status Text dropdown sets. Using the CVars keeps
-- Blizzard's code untainted: health is a secret value in Forever, and forcing
-- the text per bar from addon code (bar:SetForceShow) would make Blizzard's
-- comparisons on those secrets run tainted and error.
---------------------------------------------------------------------------

local function ApplyStatusText(on)
	local saved = M.db.savedStatusText
	if on then
		if saved.statusText == nil then
			saved.statusText = GetCVar("statusText")
			saved.statusTextDisplay = GetCVar("statusTextDisplay")
		end
		-- Display mode first: the bars refresh on the "statusText" CVAR_UPDATE.
		SetCVar("statusTextDisplay", "NUMERIC")
		SetCVar("statusText", "1")
	elseif saved.statusText ~= nil then
		SetCVar("statusTextDisplay", saved.statusTextDisplay or "NUMERIC")
		SetCVar("statusText", saved.statusText)
		saved.statusText, saved.statusTextDisplay = nil, nil
	end
end

---------------------------------------------------------------------------
-- 2. Movable bags
--
-- Blizzard re-anchors every bag to the bottom right in UpdateContainerFrameAnchors()
-- whenever bags open, close or the layout changes; a post-hook puts moved bags
-- back where the player left them. Dragging works on the title bar (an invisible
-- "router" button that opens the bag menu on mouse down; a drag closes that menu
-- again) and on any empty spot of the bag.
---------------------------------------------------------------------------

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

local function ApplyMovableBags(on)
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

---------------------------------------------------------------------------
-- 3. Announce quest progress in party chat (like Questie's QuestieAnnounce)
--
-- An objective is announced when it changes from unfinished to finished; when that
-- completes the whole quest, one "quest complete" line replaces it. Quests and
-- objectives that are already done when first seen (accepted that way, or at
-- login) stay silent. Quests are tracked by questID, so collapsed quest log headers
-- don't hide progress. Party chat in a normal party, instance chat in an instance
-- group, nothing solo or in a raid. Addon chat can be locked down by the client
-- (C_ChatInfo.InChatMessagingLockdown); messages wait until that lifts.
-- The objective text comes from the client in its language, so the wrapper text is
-- localized too (party members read it).
---------------------------------------------------------------------------

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
		if active.questAnnounce then
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

local function ApplyQuestAnnounce(on)
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

---------------------------------------------------------------------------
-- Switching tweaks on and off
---------------------------------------------------------------------------

local TWEAKS = {
	{ key = "statusText", command = "statustext", label = "Always show health & power values", apply = ApplyStatusText },
	{ key = "movableBags", command = "bags", label = "Movable bags", apply = ApplyMovableBags },
	{ key = "questAnnounce", command = "quests", label = "Announce quest progress in party chat", apply = ApplyQuestAnnounce },
	{ key = "comboPoints", command = "combo", label = "Combo points on the personal resource display",
		apply = function(on) ns.ApplyComboPoints(on) end }, -- ComboPoints.lua
	{ key = "comboColors", command = "combocolors", label = "Colour combo points by count",
		apply = function(on) ns.ApplyComboColors(on) end },
	{ key = "foreverQuests", command = "newquests", label = "Mark quests that are new in WoW: Forever",
		apply = function(on) ns.ApplyForeverQuests(on) end }, -- ForeverQuests.lua
	{ key = "questMap", command = "questmap", label = "Quests on continent and world maps",
		apply = function(on) ns.ApplyQuestMap(on) end }, -- QuestMap.lua
	{ key = "afkScreen", command = "afk", label = "AFK screen",
		apply = function(on) ns.ApplyAFKScreen(on) end }, -- AFK.lua
	{ key = "levelUp", command = "levelup", label = "Level-up window",
		apply = function(on) ns.ApplyLevelUp(on) end }, -- LevelUp.lua
	{ key = "cinematicFlights", command = "flights", label = "Cinematic flights",
		apply = function(on) ns.ApplyCinematicFlights(on) end }, -- Flight.lua
}

local function Reconcile()
	for _, tweak in ipairs(TWEAKS) do
		local want = M.enabled and M.db[tweak.key] == true
		if want ~= (active[tweak.key] == true) then
			local ok, err = pcall(tweak.apply, want)
			if ok then
				active[tweak.key] = want
			else
				geterrorhandler()(err)
			end
		end
	end
end

-- Applied on the next frame, not inside the caller (settings panel, login event).
local reconcilePending = false
local function RequestReconcile()
	if reconcilePending then
		return
	end
	reconcilePending = true
	C_Timer.After(0, function()
		reconcilePending = false
		Reconcile()
	end)
end

function M:OnEnable()
	RequestReconcile()
end

function M:OnDisable()
	RequestReconcile()
end

function M:OnSettingChanged()
	RequestReconcile()
	ns.RefreshQuestMap() -- what each zoom level shows
end

function M:IsTweakActive(key)
	return active[key] == true
end

---------------------------------------------------------------------------
-- Settings page and /lefthy tweaks
---------------------------------------------------------------------------

function M:BuildOptions(o)
	o:Header(L["Unit frames"])
	o:Checkbox("statusText", L["Always show health & power values"],
		L["Show current / max on the health and power bars all the time instead of only on mouseover. Applies to every unit frame (player, target, focus, pet, party), like Blizzard's Options > Interface > Status Text set to Numeric."])
	o:Checkbox("comboPoints", L["Combo points on the personal resource display"],
		L["Forever's personal resource display leaves combo points out. This adds them under its bars in retail's style, with Blizzard's animations; at full points they glow. Rogues, and druids in Cat Form. Shows when the personal resource display does."])
	o:Checkbox("comboColors", L["Colour combo points by count"],
		L["Green with one point, through yellow and orange, to red at full points. Off: retail's red."])
	o:Header(L["Bags"])
	o:Checkbox("movableBags", L["Movable bags"],
		L["Drag a bag by its title bar or any empty spot to move it. It reopens where you left it. /lefthy tweaks resetbags puts all bags back."])
	o:Header(L["Quests"])
	o:Checkbox("questAnnounce", L["Announce quest progress in party chat"],
		L["When you finish a quest objective or a whole quest while in a party, your character posts it in party chat, like Questie does. Not solo and not in raids."])
	o:Checkbox("foreverQuests", L["Mark quests that are new in WoW: Forever"],
		L["WoW: Forever adds over a thousand quests to the Classic world, plus about as many from Classic's later seasons that original Classic never had. They get a NEW right after their name: in the quest log (hover for details), in the quest details and in the quest window when you accept or turn one in."])
	o:Checkbox("questMap", L["Quests on continent and world maps"],
		L["Blizzard's world map shows your quests only on zone maps. This shows them on continent maps and the world map too: an icon where to go (hover it for the objectives) and the area where the mobs and items are. Choose below what each zoom level shows. The map's own filter for quest objectives hides them as well."])
	local shown = { { "off", L["Nothing"] }, { "icons", L["Icons"] }, { "areas", L["Areas"] }, { "both", L["Icons and areas"] } }
	o:Choice("questMapContinent", L["On continent maps"],
		L["What continent maps like Kalimdor show of your quests. With icons only, hovering one shows its area."], shown)
	o:Choice("questMapWorld", L["On the world map"],
		L["What the map of the whole world shows of your quests."], shown)
	o:Checkbox("questMapClick", L["Click an icon to select its quest"],
		L["As on zone maps: clicking a quest's icon selects that quest (waypoint arrow, its area on the map, and it's tracked if it wasn't); clicking it again unselects it, Shift-click stops tracking it. Off: a click zooms into the zone. With a controller, the button always zooms in."])
	o:Choice("questMapZone", L["Quest areas on zone maps"],
		L["Blizzard shows only the area of your selected quest. All quests: the areas of every quest in the zone, like Questie."],
		{ { "blizzard", L["Selected quest"] }, { "areas", L["All quests"] } })
	o:Header(L["Level-ups"])
	o:Checkbox("levelUp", L["Level-up window"],
		L["Like in old RPGs: when you level up, a window shows what each stat gained, the new spells at your class trainer (hover one for its tooltip), talent points, a class quest that opens at this level and how long the last level took. It waits until a fight is over and closes by itself."])
	o:Button(L["Show the level-up window"], L["Preview"], function() ns.LevelUp.Preview() end,
		L["Shows the window for your current level, with the gains of your last level-up (example numbers if there was none yet). /levelup does the same."])
	o:Header(L["AFK screen"])
	o:Checkbox("afkScreen", L["AFK screen"],
		L["While you're AFK the interface disappears and a panel shows your character, how long you've been away, whispers, friends' news and which friends are online. Moving, combat, a ready check or a click brings everything back."])
	o:Checkbox("afkSpin", L["Circle the camera"],
		L["The camera slowly circles your character while the AFK screen is up."])
	o:Header(L["Flights"])
	o:Checkbox("cinematicFlights", L["Cinematic flights"],
		L["On a flight path the interface fades out, black bars slide in like in a film, and a title card names your destination and every zone you fly into. The bottom bar shows the time left to landing, and whispers and party chat show as subtitles. Opening a window or typing in chat pauses it until you're done; landing brings everything back."])
	o:Checkbox("flightFriends", L["Friends in the top bar"],
		L["The top black bar shows what your Beacon friends are doing: a line each with their level, where they are, and whom they're fighting or which quest they're on. With more than two friends it goes through them in turn."])
	o:Choice("flightHide", L["What a flight hides"],
		L["Everything: the whole interface, other addons included. Chosen elements: only the ones ticked below, the rest stays (other addons too). Works with Mirage on or off."],
		{ { "all", L["Everything"] }, { "chosen", L["Chosen elements"] } })
	for _, g in ipairs(ns.MirageData.GROUPS) do
		o:Checkbox(g.key, g.label, L["Hidden during flights (with \"Chosen elements\")."],
			{ tbl = self.db.flightGroups, default = true, id = "flightGroup_" .. g.key })
	end
end

function M:OnSlashCommand(msg)
	local cmd, arg = strsplit(" ", strtrim(msg or ""):lower(), 2)
	if cmd == "" then
		LT:OpenSettings(self)
	elseif cmd == "resetbags" then
		self:ResetBagPositions()
		self:Print("bag positions reset.")
	elseif cmd == "levelup" and arg == "test" then
		ns.LevelUp.Preview()
	elseif cmd == "status" then
		for _, tweak in ipairs(TWEAKS) do
			self:Print(string.format("  %s%s|r (%s)", active[tweak.key] and "|cff80ff80" or "|cffff8080",
				tweak.label, tweak.command))
		end
	else
		for _, tweak in ipairs(TWEAKS) do
			if cmd == tweak.command then
				local on
				if arg == "on" then
					on = true
				elseif arg == "off" then
					on = false
				else
					on = not self.db[tweak.key]
				end
				LT:SetModuleSetting(self, tweak.key, on) -- the checkbox follows; OnSettingChanged reconciles
				self:Print(tweak.label .. (on and ": on." or ": off.")
					.. (self.enabled and "" or " (Misc Tweaks itself is off: /lefthy enable tweaks)"))
				return
			end
		end
		self:Print("/lefthy tweaks - open settings")
		self:Print("/lefthy tweaks status - list tweaks")
		self:Print("/lefthy tweaks statustext | bags | quests | newquests | combo | combocolors | questmap | afk | levelup | flights [on|off] - switch a tweak")
		self:Print("/levelup (or /lefthy tweaks levelup test) - show the level-up window for your current level")
		self:Print("/lefthy tweaks resetbags - move all bags back to Blizzard's spot")
	end
end
