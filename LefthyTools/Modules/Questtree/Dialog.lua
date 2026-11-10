local _, ns = ...
local LT = ns.LT
local L = ns.L
local Q = ns.Questtree or {}; ns.Questtree = Q

-- Questtree in the game's quest UI (docs/questtree.md, "In the game's quest UI"):
--
--   * Beside the quest dialog (setting dialog): when an NPC offers a quest (QUEST_DETAIL), asks for
--     it (QUEST_PROGRESS), rewards it (QUEST_COMPLETE) or lists several (QUEST_GREETING), a panel of
--     ours next to QuestFrame says "Part 2 of 4 · <chain>", numbers the chain's steps around it (one
--     before, this one bold, two after, done ones ticked, "... N more"), what it leads to when that
--     isn't the next step listed ("Leads to ..." / "Opens 3 quests"), what the next steps need
--     besides it that isn't listed or done ("Requires ..."), what taking it closes, which friends did
--     it (one line), and has a button "Open in Questtree". Nothing to tell (no chain, nothing it
--     opens): no panel.
--   * The quest log (setting logBadges): "2/4" at the right end of each chain quest's line (a font
--     string of ours on Blizzard's title button, the way Misc Tweaks' NEW label is: a post-hook on
--     QuestLogQuests_Update), the chain in the line's tooltip (a HookScript on its OnEnter, as Misc
--     Tweaks does), and Alt-click opens the quest in Questtree (Questtree.lua's post-hook on
--     QuestMapFrame_ShowQuestDetails hands it here; it opens on the next frame, in our own code).
--
-- Taint and the controller: the panel is a frame of ours on UIParent, only anchored to QuestFrame,
-- never its child, so it isn't part of the dialog's panel for SmartNavigation: the controller's
-- cursor stays on Blizzard's own buttons (Accept, Decline, Complete), nothing of ours is run from
-- Blizzard's code, and nothing of ours is created inside the open panel (SmartNavigation's
-- CreateFrame hook). Its button and lines are for the mouse. Nothing is written into QuestFrame and
-- no script of it is hooked: the panel follows the events and, while shown, looks twice a second
-- whether QuestFrame is still shown. The quest log gets only what ForeverQuests.lua already puts
-- there: a font string per title button and one HookScript("OnEnter").
--
-- Never lags: the events only note the page and draw on the next frame; the data is loaded for the
-- panel only out of a fight (the first dialog after login, unless the tooltips already loaded it).
-- A badge is a table lookup, kept per data and progress change (Q.ChainFor).

local WIDTH = 250
local PAD = 10
local GAP = 3
local INDENT = 8
local STEPS_MAX = 4        -- steps in sight: one before this one, this one, two after
local TIP_STEPS = 5        -- steps in the quest log's tooltip (from one before this one)
local NAMES_MAX = 3        -- quests named in a tooltip ("Opens 3 quests"), needs listed ("Requires ...")
local FRIENDS_MAX = 3      -- friends named (one line)
local GREETING_MAX = 8
local WATCH_EVERY = 0.5    -- s: whether QuestFrame is still shown, while the panel is
local HOOK_DELAY = 1       -- s after Questtree is switched on: the quest log's hook (after Misc Tweaks')
local C = Q.COLOR or {}
local GOLD, GREY, LIGHT, GREEN = C.gold or "|cffffd200", C.grey or "|cff9d9d9d", C.light or "|cffbebebe", C.done or "|cff5fba46"
local CLOSES, BADGE = C.closes or "|cffff8040", C.progress or "|cffd99b00"
local EVENTS = { "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_GREETING", "QUEST_FINISHED" }
local PAGES = { QUEST_DETAIL = "detail", QUEST_PROGRESS = "progress", QUEST_COMPLETE = "complete", QUEST_GREETING = "greeting" }

local Soon                 -- (below: a draw on the next frame)
local panel                -- our frame beside the quest dialog (built the first time it has something to say)
local listener             -- the quest dialog's events (while Questtree and the setting are on)
local page                 -- the dialog's page: "detail" | "progress" | "complete" | "greeting" | nil (closed)
local shownQuest           -- the quest the panel shows (nil: the greeting's list)
local due = false
local asked = {}           -- friends' progress asked for, per quest, while the dialog is open
local rows, rowsUsed = {}, 0
local texts, textsUsed = {}, 0

local function DB()
	return Q.module.db
end

local function On(key)
	return Q.module and Q.module.enabled and DB()[key] == true
end

local function Loaded()
	return Q.IsLoaded == nil or Q.IsLoaded() == true
end

-- Opens a quest in Questtree: the big window on it, else the small one.
local function OpenQuest(id)
	if not (id and Q.module.enabled) then
		return
	end
	if Q.OpenBrowser then
		Q.OpenBrowser(id)
	elseif Q.ShowQuest then
		Q.ShowQuest(id)
	end
end

-- The chain's name: its first quest's title (the client's when it knows it).
local function ChainName(list)
	return Q.Title(list[1])
end

-- "A, B, C (+2 more)" of quest titles.
local function Names(ids, max)
	local parts = {}
	for i = 1, math.min(#ids, max or NAMES_MAX) do
		parts[i] = Q.Title(ids[i])
	end
	if #ids > #parts then
		parts[#parts + 1] = L["(+%d more)"]:format(#ids - #parts)
	end
	return table.concat(parts, ", ")
end

---------------------------------------------------------------------------
-- The panel's lines, pooled
---------------------------------------------------------------------------

local function Text(y, text, font, indent, oneLine)
	textsUsed = textsUsed + 1
	local fs = texts[textsUsed]
	if not fs then
		fs = panel.Body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetJustifyH("LEFT")
		texts[textsUsed] = fs
	end
	indent = indent or 0
	fs:SetWordWrap(not oneLine)
	fs:SetFontObject(font or "GameFontHighlightSmall")
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", panel.Body, "TOPLEFT", indent, -y)
	fs:SetWidth(WIDTH - 2 * PAD - indent)
	fs:SetText(text)
	fs:Show()
	return y + math.ceil(fs:GetStringHeight()) + GAP
end

local function RowEnter(self)
	local tip = self.tooltip
	if not tip then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(tip[1], 1, 1, 1)
	for i = 2, #tip do
		GameTooltip:AddLine(tip[i], 0.8, 0.8, 0.8, true)
	end
	GameTooltip:Show()
end

local function RowLeave(self)
	if GameTooltip:IsOwned(self) then
		GameTooltip:Hide()
	end
end

local function RowClick(self)
	RowLeave(self)
	OpenQuest(self.questID)
end

-- A line for a quest (a click opens it in Questtree): o = { text, id, font, indent, tooltip }.
local function Row(y, o)
	rowsUsed = rowsUsed + 1
	local row = rows[rowsUsed]
	if not row then
		row = CreateFrame("Button", nil, panel.Body)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.Text:SetPoint("TOPLEFT", 2, -1)
		row.Text:SetJustifyH("LEFT")
		row:RegisterForClicks("LeftButtonUp")
		row:SetScript("OnClick", RowClick)
		row:SetScript("OnEnter", RowEnter)
		row:SetScript("OnLeave", RowLeave)
		rows[rowsUsed] = row
	end
	local indent = o.indent or 0
	local w = WIDTH - 2 * PAD - indent
	row.questID = o.id
	row.tooltip = o.tooltip or { Q.LevelTitle(o.id), Q.StatusText(Q.StatusOf(o.id)), L["Click: open it in Questtree"] }
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", panel.Body, "TOPLEFT", indent, -y)
	row.Text:SetFontObject(o.font or "GameFontHighlightSmall")
	row.Text:SetWidth(w - 4)
	row.Text:SetText(o.text)
	local height = math.ceil(row.Text:GetStringHeight()) + 2
	row:SetSize(w, height)
	row:Show()
	return y + height + 1
end

---------------------------------------------------------------------------
-- What the panel says
---------------------------------------------------------------------------

-- Which of a chain's steps are in sight: from one before this one, at most max (fewer before it at
-- the chain's start, more before it at its end): first, last.
local function Window(list, at, max)
	local first = math.max(1, math.min(at - 1, #list - max + 1))
	return first, math.min(#list, first + max - 1)
end

-- The chain's steps around this one, numbered: done ones ticked green, this one bold with an
-- arrow, the rest grey; "... N before" and "... N more" for the rest.
local function Steps(y, list, at)
	local first, last = Window(list, at, STEPS_MAX)
	if first > 1 then
		y = Text(y, GREY .. L["... %d before"]:format(first - 1) .. "|r", "GameFontHighlightSmall", INDENT)
	end
	for i = first, last do
		local id = list[i]
		local text, font
		if i == at then
			text, font = Q.Icon("here") .. " " .. i .. ". " .. Q.Title(id), "GameFontHighlight"
		elseif Q.StatusOf(id) == "done" then
			text = Q.Icon("done") .. " " .. GREEN .. i .. ". " .. Q.Title(id) .. "|r"
		else
			text = LIGHT .. i .. ". " .. Q.Title(id) .. "|r"
		end
		y = Row(y, { text = text, id = id, font = font, indent = INDENT })
	end
	if last < #list then
		y = Text(y, GREY .. L["... %d more"]:format(#list - last) .. "|r", "GameFontHighlightSmall", INDENT)
	end
	return y
end

-- What the quests it leads to need besides it that isn't one of the steps listed (listed: a set) or
-- done: { { id, forID } } (at most NAMES_MAX).
local function OtherNeeds(id, opens, listed)
	local list, seen = {}, { [id] = true }
	for _, nextID in ipairs(opens) do
		for _, entry in ipairs(Q.Missing and Q.Missing(nextID) or {}) do
			if not (seen[entry.id] or listed[entry.id]) and Q.StatusOf(entry.id) ~= "done" and #list < NAMES_MAX then
				seen[entry.id] = true
				list[#list + 1] = { id = entry.id, forID = nextID }
			end
		end
	end
	return list
end

-- Friends who did it or are on it, on one line: "Friends: Anna, Bo" in their class colours, each with
-- a tick or the in-progress icon (at most FRIENDS_MAX, then "+2"); nil: none (or the setting off).
-- Asks their progress once per dialog (QuestShare.lua).
local function FriendsText(id)
	if not (DB().friends and Q.Friends) then
		return nil
	end
	if Q.RequestFriendProgress and not asked[id] then
		asked[id] = true
		pcall(Q.RequestFriendProgress, id)
	end
	local list = {}
	for _, friend in ipairs(Q.Friends(id) or {}) do
		if friend.status == "done" or friend.status == "active" then
			list[#list + 1] = friend
		end
	end
	local parts = {}
	for i = 1, math.min(#list, FRIENDS_MAX) do
		local friend = list[i]
		parts[i] = LT.Window.ClassColorCode(friend.classFile) .. (friend.name or "?") .. "|r "
			.. Q.Icon(friend.status == "done" and "done" or "progress", 12)
	end
	if #parts == 0 then
		return nil
	end
	local more = #list > #parts and (" " .. GREY .. "+" .. (#list - #parts) .. "|r") or ""
	return GOLD .. L["Friends:"] .. "|r " .. table.concat(parts, ", ") .. more
end

-- A quest's panel: nil when there's nothing to tell (no chain, nothing it leads to or closes, no
-- friends).
local function DrawQuest(y, id)
	local quest = id and Q.Quest(id)
	if not quest then
		return nil
	end
	local list, at = Q.ChainFor(id)
	local opens = Q.Opens and Q.Opens(id) or {}
	local offered = page == "detail"
	local closes = offered and Q.Closes and Q.Closes(id) or {}
	local crumb = offered and quest.breadcrumbFor
	local friends = FriendsText(id)
	if not (list or opens[1] or closes[1] or crumb or friends) then
		return nil
	end
	local listed = {}
	if list then
		y = Text(y, GOLD .. L["Part %d of %d"]:format(at, #list) .. " · " .. ChainName(list) .. "|r", "GameFontNormal")
		y = Steps(y + 1, list, at)
		local first, last = Window(list, at, STEPS_MAX)
		for i = first, last do
			listed[list[i]] = true
		end
	else
		y = Text(y, GOLD .. Q.Title(id, quest) .. "|r", "GameFontNormal")
	end
	y = y + GAP
	-- What it leads to: the one quest (unless it's a step listed already), else how many (their names
	-- in the line's tooltip).
	if #opens == 1 and not listed[opens[1]] then
		y = Row(y, { id = opens[1], text = GOLD .. L["Leads to:"] .. "|r " .. Q.LevelTitle(opens[1]) })
	elseif #opens > 1 then
		local tip = { L["Opens %d quests"]:format(#opens) }
		for i = 1, math.min(#opens, NAMES_MAX) do
			tip[#tip + 1] = Q.LevelTitle(opens[i])
		end
		if #opens > NAMES_MAX then
			tip[#tip + 1] = L["and %d more"]:format(#opens - NAMES_MAX)
		end
		tip[#tip + 1] = L["Click: open it in Questtree"]
		y = Row(y, { id = id, text = GOLD .. L["Opens %d quests"]:format(#opens) .. "|r", tooltip = tip })
	end
	for _, need in ipairs(OtherNeeds(id, opens, listed)) do
		y = Row(y, { id = need.id, text = Q.StatusCode("locked") .. L["Requires: %s"]:format(Q.Title(need.id)) .. "|r"
			.. GREY .. " " .. L["(for %s)"]:format(Q.Title(need.forID)) .. "|r",
			tooltip = { Q.LevelTitle(need.id), Q.StatusText(Q.StatusOf(need.id)),
				L["%s needs it too, not only this quest."]:format(Q.Title(need.forID)), L["Click: open it in Questtree"] } })
	end
	if closes[1] then
		y = Text(y, CLOSES .. L["Taking it closes: %s"]:format(Names(closes)) .. "|r", "GameFontHighlightSmall")
	end
	if crumb then
		y = Text(y, GREY .. L["A lead-in: %s can be taken without it."]:format(Q.Title(crumb)) .. "|r", "GameFontHighlightSmall")
	end
	if friends then
		y = Text(y + 2, friends, "GameFontHighlightSmall", nil, true)
	end
	return y
end

-- An NPC with several quests (the greeting): each that's in a chain or leads on, with its part.
local function DrawGreeting(y)
	local ids = {}
	local function Add(id)
		id = tonumber(id)
		if id and not LT.IsSecret(id) and #ids < GREETING_MAX then
			ids[#ids + 1] = id
		end
	end
	for i = 1, tonumber(LT.Value(GetNumActiveQuests)) or 0 do
		Add(LT.Value(GetActiveQuestID, i))
	end
	for i = 1, tonumber(LT.Value(GetNumAvailableQuests)) or 0 do
		if GetAvailableQuestInfo then
			local ok, _, _, _, _, id = pcall(GetAvailableQuestInfo, i)
			if ok then
				Add(id)
			end
		end
	end
	local any = false
	for _, id in ipairs(ids) do
		local quest = Q.Quest(id)
		local list, at = Q.ChainFor(id)
		local opens = Q.Opens and Q.Opens(id) or {}
		if quest and (list or opens[1]) then
			if not any then
				any = true
				y = Text(y, GOLD .. "Questtree" .. "|r", "GameFontNormal")
			end
			local note = list and (L["Part %d of %d"]:format(at, #list) .. " · " .. ChainName(list)) or L["opens %d"]:format(#opens)
			y = Row(y, { id = id, text = Q.QuestIcon(id) .. " " .. Q.LevelTitle(id, quest) .. "\n" .. GREY .. note .. "|r" })
		end
	end
	return any and y or nil
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------

local function Hide()
	shownQuest = nil
	if panel and panel:IsShown() then
		panel:Hide()
	end
end

local function Build()
	panel = CreateFrame("Frame", "LefthyToolsQuesttreeDialog", UIParent)
	panel:SetSize(WIDTH, 100)
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	local back = panel:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0.05, 0.05, 0.05, 0.92)
	-- A thin gold edge, brighter on top: { from, to, across (width or height), alpha }.
	for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", "height", 0.5 }, { "BOTTOMLEFT", "BOTTOMRIGHT", "height", 0.25 },
		{ "TOPLEFT", "BOTTOMLEFT", "width", 0.25 }, { "TOPRIGHT", "BOTTOMRIGHT", "width", 0.25 } }) do
		local edge = panel:CreateTexture(nil, "BORDER")
		edge:SetPoint(side[1])
		edge:SetPoint(side[2])
		if side[3] == "width" then
			edge:SetWidth(1)
		else
			edge:SetHeight(1)
		end
		edge:SetColorTexture(1, 0.82, 0, side[4])
	end
	panel.Body = CreateFrame("Frame", nil, panel)
	panel.Body:SetPoint("TOPLEFT", PAD, -PAD)
	panel.Body:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	panel.Open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	panel.Open:SetSize(WIDTH - 2 * PAD, 22)
	panel.Open:SetPoint("BOTTOM", 0, PAD)
	panel.Open:SetText(L["Open in Questtree"])
	panel.Open:SetScript("OnClick", function() OpenQuest(shownQuest) end)
	-- While shown: is the dialog still there (it can close without QUEST_FINISHED reaching us first).
	local wait = WATCH_EVERY
	panel:SetScript("OnUpdate", function(self, elapsed)
		wait = wait - elapsed
		if wait <= 0 then
			wait = WATCH_EVERY
			if not (QuestFrame and QuestFrame:IsVisible()) then
				page = nil
				Hide()
			end
		end
	end)
	panel:HookScript("OnHide", function()
		for i = 1, #rows do
			RowLeave(rows[i])
		end
	end)
	panel:Hide()
	-- Friends' answers came (QuestShare.lua): drawn again while shown.
	if Q.OnFriendProgress then
		Q.OnFriendProgress(function()
			if panel:IsShown() then
				Soon()
			end
		end)
	end
end

local function Draw()
	if not (On("dialog") and page) then
		return Hide()
	end
	if not (QuestFrame and QuestFrame:IsShown()) then
		return Hide()
	end
	-- The data: loaded already, or loaded now out of a fight (only when the add-on is there).
	if not Loaded() and (LT.InCombat() or not (Q.HasData and Q.HasData())) then
		return Hide()
	end
	if not Q.Ready() then
		return Hide()
	end
	if not panel then
		Build()
	end
	rowsUsed, textsUsed = 0, 0
	local id = page ~= "greeting" and tonumber(LT.Value(GetQuestID)) or nil
	if id and (id <= 0 or LT.IsSecret(id)) then
		id = nil
	end
	local y
	if page == "greeting" then
		y = DrawGreeting(0)
	elseif id then
		y = DrawQuest(0, id)
	end
	for i = rowsUsed + 1, #rows do
		RowLeave(rows[i])
		rows[i]:Hide()
	end
	for i = textsUsed + 1, #texts do
		texts[i]:Hide()
	end
	if not y then
		return Hide()
	end
	shownQuest = page ~= "greeting" and id or nil
	local button = shownQuest ~= nil and (Q.OpenBrowser ~= nil or Q.ShowQuest ~= nil)
	panel.Open:SetShown(button)
	panel:SetHeight(math.ceil(y) + 2 * PAD + (button and 26 or 0))
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", QuestFrame, "TOPRIGHT", 4, 0)
	panel:SetFrameStrata(QuestFrame:GetFrameStrata() or "MEDIUM")
	panel:SetFrameLevel((QuestFrame:GetFrameLevel() or 1) + 10)
	panel:Show()
end

-- On the next frame (the dialog's events come in bursts; the dialog shows itself in its own handler).
Soon = function()
	if due then
		return
	end
	due = true
	C_Timer.After(0, function()
		due = false
		LT.Guard("Questtree.dialog", Draw)
	end)
end

local function OnEvent(_, event)
	if event == "QUEST_FINISHED" then
		page = nil
		wipe(asked)
		Hide()
		return
	end
	page = PAGES[event]
	Soon()
end

-- The dialog's events, while Questtree and the setting are on.
local function Listen()
	local want = On("dialog")
	if want and not listener then
		listener = CreateFrame("Frame")
		listener:SetScript("OnEvent", OnEvent)
	end
	if listener then
		for _, event in ipairs(EVENTS) do
			if want then
				listener:RegisterEvent(event)
			else
				listener:UnregisterEvent(event)
			end
		end
	end
	if not want then
		page = nil
		Hide()
	end
end

---------------------------------------------------------------------------
-- The quest log: "2/4" on a chain quest's line, the chain in its tooltip, Alt-click
---------------------------------------------------------------------------

local badges = {}          -- quest log title button -> our label
local tipHooked = {}       -- title buttons with our OnEnter hook
local badgeOf, badgeKey = {}, nil
local logHooked, loading = false, false

-- "2/4" for a quest (false: in no chain), kept per data and progress change.
local function BadgeText(id)
	Q.StatusOf(id) -- (the engine reads my progress first: a change there moves Q.progressGen)
	local key = tostring(Q.dataGen) .. ":" .. tostring(Q.progressGen)
	if key ~= badgeKey then
		badgeOf, badgeKey = {}, key
	end
	local text = badgeOf[id]
	if text == nil then
		local list, at = Q.ChainFor(id)
		text = list and (BADGE .. at .. "/" .. #list .. "|r") or false
		badgeOf[id] = text
	end
	return text
end

-- The quest's chain in its quest log tooltip (Blizzard's own OnEnter made it; ours adds to it).
local function BadgeTip(button)
	local id = button.questID
	if not (On("logBadges") and Loaded() and type(id) == "number") or not GameTooltip:IsOwned(button) then
		return
	end
	local list, at = Q.ChainFor(id)
	if not list then
		return
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Questtree: " .. L["Part %d of %d"]:format(at, #list) .. " · " .. ChainName(list), 1, 0.82, 0, true)
	local first, last = Window(list, at, TIP_STEPS)
	if first > 1 then
		GameTooltip:AddLine("   " .. L["... %d before"]:format(first - 1), 0.6, 0.6, 0.6)
	end
	for i = first, last do
		local other = list[i]
		if i == at then
			GameTooltip:AddLine(Q.Icon("here") .. " " .. i .. ". " .. Q.Title(other), 1, 1, 1)
		elseif Q.StatusOf(other) == "done" then
			GameTooltip:AddLine(Q.Icon("done") .. " " .. i .. ". " .. Q.Title(other), 0.373, 0.729, 0.275)
		else
			GameTooltip:AddLine("   " .. i .. ". " .. Q.Title(other), 0.6, 0.6, 0.6)
		end
	end
	if last < #list then
		GameTooltip:AddLine("   " .. L["... %d more"]:format(#list - last), 0.6, 0.6, 0.6)
	end
	local opens = Q.Opens and Q.Opens(id) or {}
	if opens[1] then
		GameTooltip:AddLine(L["Leads to:"] .. " " .. Names(opens), 0.8, 0.8, 0.8, true)
	end
	if Q.OpenBrowser or Q.ShowQuest then
		GameTooltip:AddLine(L["Alt-click: open it in Questtree"], 0.5, 0.8, 1)
	end
	GameTooltip:Show()
end

local function SafeTip(button)
	LT.Guard("Questtree.logtip", BadgeTip, button)
end

-- Our label on a title button, at the right end of its line (left of Misc Tweaks' NEW when that's
-- there), in front of the track checkbox, where Forever never shows the quest type icon.
local function Badge(button)
	local label = badges[button]
	if not label then
		label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		badges[button] = label
	end
	label:ClearAllPoints()
	local spare = ns.GetForeverQuestLabels and ns.GetForeverQuestLabels()[button]
	if spare and spare:IsShown() then
		label:SetPoint("RIGHT", spare, "LEFT", -3, 0)
	else
		label:SetPoint("RIGHT", button.Checkbox or button, button.Checkbox and "LEFT" or "RIGHT", -4, 0)
	end
	return label
end

local UpdateBadges

-- The data isn't loaded: load it once on the next frame, out of a fight, then mark the open log.
local function LoadSoon()
	if loading or LT.InCombat() or not (Q.HasData and Q.HasData()) then
		return
	end
	loading = true
	C_Timer.After(0, function()
		loading = false
		if not LT.InCombat() and On("logBadges") and Q.Ready() then
			LT.Guard("Questtree.badges", UpdateBadges)
		end
	end)
end

UpdateBadges = function()
	for _, label in pairs(badges) do
		label:Hide()
	end
	local pool = QuestScrollFrame and QuestScrollFrame.titleFramePool
	if not (pool and On("logBadges")) then
		return
	end
	if not Loaded() then
		return LoadSoon()
	end
	for button in pool:EnumerateActive() do
		local id = button.questID
		local text = type(id) == "number" and not LT.IsSecret(id) and BadgeText(id)
		if text then
			local label = Badge(button)
			label:SetText(text)
			label:Show()
			if not tipHooked[button] then
				tipHooked[button] = true
				button:HookScript("OnEnter", SafeTip)
			end
		end
	end
end

-- A post-hook on QuestLogQuests_Update (Blizzard has just filled the titles), as Misc Tweaks' NEW
-- marker; made a second after Questtree is switched on, so it runs after that one's (its label's
-- place is known then).
local function HookLog()
	if logHooked or type(QuestLogQuests_Update) ~= "function" then
		return
	end
	logHooked = true
	hooksecurefunc("QuestLogQuests_Update", function()
		LT.Guard("Questtree.badges", UpdateBadges)
	end)
end

-- Alt-click on a quest in the log (Questtree.lua's hook): opened on the next frame, in our code.
function Q.LogAltClick(id)
	if not On("logBadges") then
		return
	end
	C_Timer.After(0, function()
		LT.Guard("Questtree.logopen", OpenQuest, id)
	end)
end

---------------------------------------------------------------------------
-- Switching
---------------------------------------------------------------------------

Q.When("enable", function()
	Listen()
	C_Timer.After(HOOK_DELAY, function()
		HookLog()
		UpdateBadges()
	end)
end)

Q.When("disable", function()
	Listen()
	UpdateBadges()
end)

Q.When("settings", function()
	Listen()
	UpdateBadges()
	if page then
		Soon()
	end
end)

-- For tests: the panel, its strings (rows' first), the quest shown, the page, the quest log's labels.
function Q.DialogView()
	local strings, list = {}, {}
	for i = 1, rowsUsed do
		list[i] = rows[i]
		strings[#strings + 1] = rows[i].Text:GetText()
	end
	for i = 1, textsUsed do
		strings[#strings + 1] = texts[i]:GetText()
	end
	return { panel = panel, rows = list, texts = strings, quest = shownQuest, page = page, badges = badges }
end
