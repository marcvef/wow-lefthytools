-- Questtree in the game's quest UI (Dialog.lua): the panel beside the quest dialog (offered,
-- progress, reward, an NPC's greeting): "Part 2 of 6 · <chain>", the numbered steps around it (one
-- before, this one bold, two after, done ones ticked, "... N more"), what it leads to (not when it's
-- a step listed; "Opens 2 quests" with their names in its tooltip), what the next step needs besides
-- it that isn't listed or done, what taking it closes, a lead-in, friends on one line (at most three);
-- "Open in Questtree"; hidden with nothing to tell, when the dialog closes (also
-- without QUEST_FINISHED), with the setting off; drawn on the next frame, never in the event; the
-- data not loaded in a fight; a frame of ours on UIParent, nothing written into QuestFrame. The quest
-- log: "2/5" on a chain quest's line (left of Misc Tweaks' NEW when that's there), kept until the
-- data or progress changes, the chain in its tooltip (at most 5 steps, from one before), the setting
-- off, Alt-click (Q.LogAltClick).
-- Data.lua and Engine.lua are in the build: the quests go in through Q.SetTestData. Whatever this
-- file replaces is put back at its end.
-- Needs: no other file.

local suite = ...
local check, section, ns, LT = suite.check, suite.section, suite.ns, suite.LT
local Q = ns.Questtree
local M = LT:GetModule("questtree")

-- What this file replaces on Q, put back at the end.
local replaced = {}
local function Replace(name, fn)
	if replaced[name] == nil then
		replaced[name] = Q[name] or false
	end
	Q[name] = fn
end
local function PutBack(name)
	if replaced[name] ~= nil then
		Q[name] = replaced[name] or nil
		replaced[name] = nil
	end
end

-- The clock moves in quarters of a second here (and whole seconds in all at the end).
local spent = 0
local function Step(seconds)
	spent = spent + (seconds or 0.25)
	Advance(seconds or 0.25)
end

-- A chain in Elwynn Forest: Into the Woods (done) -> The Lost Axe (which closes A Different Path, its
-- exclusive one) -> Back to Camp (which also needs Wolf Trouble) -> a long-titled Forever quest
-- (86576: Misc Tweaks marks it NEW). A quest on its own; a lead-in to another.
local function Npc(id, name, x, y) return { kind = "npc", id = id, name = name, points = { { map = 1429, x = x, y = y } } } end
local QUESTS_DATA = {
	[9101] = { id = 9101, title = "Into the Woods", level = 5, zone = 1429, starts = { Npc(920, "Ranger Ash", 0.4, 0.4) }, ends = { Npc(920, "Ranger Ash", 0.4, 0.4) } },
	[9102] = { id = 9102, title = "The Lost Axe", level = 6, zone = 1429, pre = { 9101 }, excl = { 9107 },
		starts = { Npc(920, "Ranger Ash", 0.4, 0.4) }, ends = { Npc(921, "Woodcutter Lin", 0.5, 0.5) } },
	[9107] = { id = 9107, title = "A Different Path", level = 6, zone = 1429, excl = { 9102 },
		starts = { Npc(922, "Old Mara", 0.6, 0.6) }, ends = { Npc(922, "Old Mara", 0.6, 0.6) } },
	[9108] = { id = 9108, title = "Wolf Trouble", level = 6, zone = 1429,
		starts = { Npc(923, "Hunter Bo", 0.3, 0.7) }, ends = { Npc(923, "Hunter Bo", 0.3, 0.7) } },
	[9103] = { id = 9103, title = "Back to Camp", level = 7, zone = 1429, pre = { 9102, 9108 },
		starts = { Npc(921, "Woodcutter Lin", 0.5, 0.5) }, ends = { Npc(920, "Ranger Ash", 0.4, 0.4) } },
	[86576] = { id = 86576, title = "The Final Word of the Old Guard", level = 8, zone = 1429, pre = { 9103 },
		starts = { Npc(920, "Ranger Ash", 0.4, 0.4) }, ends = { Npc(920, "Ranger Ash", 0.4, 0.4) } },
	[9109] = { id = 9109, title = "Lonely Errand", level = 5, zone = 1429,
		starts = { Npc(924, "Peasant Jo", 0.7, 0.3) }, ends = { Npc(924, "Peasant Jo", 0.7, 0.3) } },
	[9110] = { id = 9110, title = "Herald's Call", level = 6, zone = 1429, breadcrumbFor = 9111,
		starts = { Npc(925, "Herald Kim", 0.45, 0.45) }, ends = { Npc(926, "Captain Lee", 0.55, 0.2) } },
	[9111] = { id = 9111, title = "The Captain's Need", level = 7, zone = 1429,
		starts = { Npc(926, "Captain Lee", 0.55, 0.2) }, ends = { Npc(926, "Captain Lee", 0.55, 0.2) } },
}
-- A second chain: Scout Ahead opens Side Errand and Report Back; Report Back also needs the last of
-- five herb quests (far down the chain, out of sight beside Scout Ahead).
local function Herbs(id, title, level, extra)
	local q = { id = id, title = title, level = level, zone = 1429, starts = { Npc(927, "Herbalist Una", 0.2, 0.2) }, ends = { Npc(927, "Herbalist Una", 0.2, 0.2) } }
	for k, v in pairs(extra or {}) do q[k] = v end
	QUESTS_DATA[id] = q
end
Herbs(9120, "Scout Ahead", 3)
Herbs(9127, "Side Errand", 4, { pre = { 9120 } })
Herbs(9122, "Herbs One", 4)
Herbs(9123, "Herbs Two", 5, { pre = { 9122 } })
Herbs(9124, "Herbs Three", 6, { pre = { 9123 } })
Herbs(9125, "Herbs Four", 7, { pre = { 9124 } })
Herbs(9126, "Herbs Five", 8, { pre = { 9125 } })
Herbs(9121, "Report Back", 9, { pre = { 9120, 9126 } })
local ZONES = { { map = 1429, name = "Elwynn Forest", continent = 1415, minLevel = 1, maxLevel = 10 } }

-- My progress: Into the Woods done; the quest log as each part needs it.
local completed = { [9101] = true }
local savedCompleted = C_QuestLog.GetAllCompletedQuestIDs
C_QuestLog.GetAllCompletedQuestIDs = function()
	local list = {}
	for id in pairs(completed) do list[#list + 1] = id end
	return list
end
local savedQuests, savedDialogQuest = QUESTS, DIALOG_QUEST
local function Log(ids)
	QUESTS = {}
	for _, id in ipairs(ids) do QUESTS[#QUESTS + 1] = { id = id, title = QUESTS_DATA[id].title, objectives = {} } end
end
local function Progress()
	Fire("PLAYER_ENTERING_WORLD", false, false)
	Fire("QUEST_LOG_UPDATE")
end
-- The quest dialog: an NPC's page (QuestFrame shows itself in its own handler, as in the game).
local function Dialog(event, id)
	DIALOG_QUEST = id
	QuestFrame:Show()
	Fire(event)
end
local function CloseDialog()
	Fire("QUEST_FINISHED")
	QuestFrame:Hide()
	DIALOG_QUEST = nil
end
local function View() return Q.DialogView() end
local function Plain(text) return (text:gsub("|[TA].-|[ta]", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function Has(text)
	for _, line in ipairs(View().texts) do
		if Plain(line):find(text, 1, true) then return line end
	end
end
local function RowWith(text)
	for _, row in ipairs(View().rows) do
		if Plain(row.Text:GetText()):find(text, 1, true) then return row end
	end
end
local opened = {}
Replace("OpenBrowser", function(id) opened[#opened + 1] = id end)

Q.SetTestData(QUESTS_DATA, ZONES)
Log({})
Progress()

section("Questtree: beside the quest dialog")
check(LefthyToolsQuesttreeDialog == nil and M.db.dialog == true and M.db.logBadges == true,
	"on by default, nothing built before a quest dialog opens")
-- Offered: The Lost Axe.
local questFrameKeys = {}
for k in pairs(QuestFrame) do questFrameKeys[k] = true end
local questFrameScripts = {}
for k, fn in pairs(QuestFrame._scripts) do questFrameScripts[k] = fn end
Dialog("QUEST_DETAIL", 9102)
check(not (View().panel and View().panel:IsShown()), "nothing drawn in the event itself")
Step()
local v = View()
local list, at = Q.ChainFor(9102)
check(v.panel and v.panel:IsShown() and v.quest == 9102 and v.page == "detail" and #list == 6 and at == 2,
	"the next frame: the panel shows the quest offered, part 2 of the chain's 6")
check(Has("Part 2 of 6 · Into the Woods"), "its heading: which part of which chain")
local first, current, later = RowWith("1. Into the Woods"), RowWith("2. The Lost Axe"), RowWith("4. ")
check(first and first.Text:GetText():find("UI-QuestTracker-Tracker-Check", 1, true) and current
	and current.Text.font == "GameFontHighlight" and later and later.Text.font == "GameFontHighlightSmall",
	"the steps numbered: done ticked, this one bold, the rest small")
check(not RowWith("5. ") and not RowWith("6. ") and Has("... 2 more"), "one before, this one, two after; ... 2 more")
check(RowWith("Leads to: [7] Back to Camp"), "what it leads to (step 5: not listed)")
check(RowWith("4. Wolf Trouble") and not RowWith("Requires:"), "what the next step needs besides it is a step listed: no Requires")
check(Has("Taking it closes: A Different Path"), "what taking it closes (its exclusive one)")
check(v.panel.Open:IsShown() and v.panel.Open:GetText() == "Open in Questtree", "the button to open it in Questtree")
v.panel.Open:Click()
check(opened[#opened] == 9102, "the button opens it in the quest browser")
first:Click()
check(opened[#opened] == 9101, "a step's line opens that one")
local _, anchor, relPoint = v.panel:GetPoint(1)
check(v.panel:GetParent() == UIParent and anchor == QuestFrame and relPoint == "TOPRIGHT",
	"a frame of ours on UIParent, only anchored beside the dialog (not part of its panel for the controller)")
local wrote = {}
for k in pairs(QuestFrame) do if not questFrameKeys[k] then wrote[#wrote + 1] = tostring(k) end end
for k, fn in pairs(QuestFrame._scripts) do if questFrameScripts[k] ~= fn then wrote[#wrote + 1] = "script " .. k end end
local children = 0
for _, child in ipairs(QuestFrame._children or {}) do if child == v.panel then children = children + 1 end end
check(#wrote == 0 and children == 0, "nothing written into QuestFrame, none of its scripts hooked, got " .. table.concat(wrote, ", "))
local buttons = true
for _, row in ipairs(v.rows) do buttons = buttons and row._kind == "Button" end
check(buttons and v.panel.Open._kind == "Button", "its lines and button are buttons of ours (the mouse's)")

-- Closed: QUEST_FINISHED, or the dialog gone without it.
CloseDialog()
check(not View().panel:IsShown(), "the dialog closes: the panel goes")
Dialog("QUEST_DETAIL", 9102)
Step()
QuestFrame:Hide()
Step(0.75)
check(not View().panel:IsShown(), "the dialog hidden without QUEST_FINISHED: gone a moment later")
Fire("QUEST_FINISHED")

-- Nothing to tell: a quest on its own.
Dialog("QUEST_DETAIL", 9109)
Step()
check(not View().panel:IsShown(), "a quest in no chain that leads nowhere: no panel")
CloseDialog()

-- A lead-in.
Dialog("QUEST_DETAIL", 9110)
Step()
check(View().panel:IsShown() and Has("A lead-in: The Captain's Need can be taken without it."), "a lead-in says so")
CloseDialog()

-- Progress and reward pages: the chain, no "closes" (it's taken). Taken, it has closed A Different
-- Path: the chain as I can do it has 5 steps now.
Log({ 9102 })
Fire("QUEST_ACCEPTED", 9102)
Progress()
Dialog("QUEST_PROGRESS", 9102)
Step()
check(View().page == "progress" and Has("Part 2 of 5") and not Has("Taking it closes") and not RowWith("A Different Path"),
	"asked for it: the chain without the quest it closed, nothing it would close")
Fire("QUEST_COMPLETE")
Step()
check(View().page == "complete" and View().panel:IsShown() and RowWith("4. Back to Camp") and not RowWith("Leads to:"),
	"rewarded: what it leads to is the next step listed, no Leads to")
CloseDialog()

-- Two quests it opens, a need far down the chain.
Dialog("QUEST_DETAIL", 9120)
Step()
local opens = RowWith("Opens 2 quests")
check(opens and not RowWith("[4] Side Errand") and not RowWith("Leads to:"), "two it opens: how many, no names under it")
opens._scripts.OnEnter(opens)
local tip = {}
for _, line in ipairs(TOOLTIP.lines) do tip[#tip + 1] = Plain(line) end
check(table.concat(tip, "|"):find("[9] Report Back", 1, true) and table.concat(tip, "|"):find("[4] Side Errand", 1, true), "... their names in its tooltip")
opens._scripts.OnLeave(opens)
check(RowWith("Requires: Herbs Three (for Report Back)") and not RowWith("Requires: Herbs One") and not RowWith("Requires: Herbs Two"),
	"what the next step needs that isn't a step listed (nor done): Requires")
CloseDialog()

-- Friends who did it.
local requests = 0
Replace("RequestFriendProgress", function() requests = requests + 1; return true end)
Replace("Friends", function(id) return id == 9102 and { { name = "Anna Brook", classFile = "MAGE", status = "done" },
	{ name = "Bo", classFile = "WARRIOR", status = "active" }, { name = "Cy", classFile = "PRIEST", status = "available" },
	{ name = "Dee", classFile = "ROGUE", status = "done" }, { name = "Eve", classFile = "MAGE", status = "done" } } or {} end)
Dialog("QUEST_DETAIL", 9102)
Step()
Fire("QUEST_DETAIL")
Step()
local friends = Has("Friends: Anna Brook")
check(friends and friends:find("UI-QuestTracker-Tracker-Check", 1, true) and Plain(friends):find("Bo", 1, true) and Plain(friends):find("Dee", 1, true)
	and not Plain(friends):find("Cy", 1, true) and not Plain(friends):find("Eve", 1, true) and Plain(friends):find("+1", 1, true)
	and requests == 1, "friends who did it or are on it, three on one line, +1; their progress asked for once while the dialog is open")
CloseDialog()
PutBack("Friends")
PutBack("RequestFriendProgress")

-- An NPC with several quests: each in a chain with its part; the one on its own isn't listed.
local greeting = { active = { 9102 }, available = { 9109, 9110 } }
GetNumActiveQuests = function() return #greeting.active end
GetActiveQuestID = function(i) return greeting.active[i] end
GetNumAvailableQuests = function() return #greeting.available end
GetAvailableQuestInfo = function(i) return false, 0, false, false, greeting.available[i] end
Dialog("QUEST_GREETING")
Step()
v = View()
check(v.panel:IsShown() and v.page == "greeting" and RowWith("[6] The Lost Axe") and RowWith("Part 2 of 5 · Into the Woods")
	and RowWith("[6] Herald's Call") and not RowWith("Lonely Errand") and not v.panel.Open:IsShown(),
	"a greeting: each quest in a chain with its part, a click opens it; no button")
CloseDialog()
GetNumActiveQuests, GetActiveQuestID, GetNumAvailableQuests, GetAvailableQuestInfo = nil, nil, nil, nil

-- The setting off; the data not loaded in a fight.
LT:SetModuleSetting(M, "dialog", false)
Dialog("QUEST_DETAIL", 9102)
Step()
check(not View().panel:IsShown(), "the setting off: no panel")
CloseDialog()
LT:SetModuleSetting(M, "dialog", true)
local loads = 0
Replace("IsLoaded", function() return false end)
local realReady = Q.Ready
Replace("Ready", function() loads = loads + 1; return realReady() end)
EnterCombat()
Dialog("QUEST_DETAIL", 9102)
Step()
check(not View().panel:IsShown() and loads == 0, "in a fight with the data not loaded: nothing loaded, no panel")
CloseDialog()
LeaveCombat()
Dialog("QUEST_DETAIL", 9102)
Step()
check(View().panel:IsShown() and loads == 1, "out of the fight: loaded, then shown")
CloseDialog()
PutBack("Ready")
PutBack("IsLoaded")

---------------------------------------------------------------------------
section("Questtree: chain steps in the quest log")
Log({ 9102, 9109, 86576, 9125 })
Progress()
local function TitleButton(id) for _, b in ipairs(QUEST_LOG_BUTTONS) do if b.questID == id then return b end end end
local chainAsks = 0
local realChainFor = Q.ChainFor
Replace("ChainFor", function(...) chainAsks = chainAsks + 1; return realChainFor(...) end)
QuestLogQuests_Update()
local axe, errand, final = TitleButton(9102), TitleButton(9109), TitleButton(86576)
local badges = View().badges
check(badges[axe] and badges[axe]:IsShown() and Plain(badges[axe]:GetText()) == "2/5" and axe.Text:GetText() == "The Lost Axe",
	"a chain quest: its step at the end of its line, the title left as Blizzard wrote it")
check(not (badges[errand] and badges[errand]:IsShown()), "a quest in no chain: nothing")
local spare = ns.GetForeverQuestLabels()[final]
local beside = badges[final]._points and badges[final]._points[1] and badges[final]._points[1][2] -- (the mock's font strings keep their points)
check(spare and spare:IsShown() and badges[final]:IsShown() and beside == spare, "left of Misc Tweaks' NEW where that's at the line's end")
local asks = chainAsks
QuestLogQuests_Update()
check(chainAsks == asks, "the log drawn again: the steps kept (a table lookup)")
completed[9108] = true
Fire("QUEST_TURNED_IN", 9108, 0, 0)
Progress()
QuestLogQuests_Update()
check(chainAsks > asks, "my progress changed: worked out again")
PutBack("ChainFor")
-- The tooltip: the chain.
GameTooltip:SetOwner(axe); TOOLTIP.shown = true -- (Blizzard's own OnEnter shows the quest's tooltip)
axe._scripts.OnEnter(axe)
local tip = {}
for _, line in ipairs(TOOLTIP.lines) do tip[#tip + 1] = Plain(line) end
tip = table.concat(tip, "|")
check(tip:find("Questtree: Part 2 of 5 · Into the Woods", 1, true) and tip:find("2. The Lost Axe", 1, true)
	and tip:find("Leads to: Back to Camp", 1, true) and tip:find("Alt-click: open it in Questtree", 1, true),
	"its tooltip: the chain, its steps, what it leads to, Alt-click")
GameTooltip:Hide()
local herb = TitleButton(9125)
GameTooltip:SetOwner(herb); TOOLTIP.shown = true
herb._scripts.OnEnter(herb)
tip = {}
for _, line in ipairs(TOOLTIP.lines) do tip[#tip + 1] = Plain(line) end
tip = table.concat(tip, "|")
check(tip:find("Part 6 of 8", 1, true) and tip:find("... 3 before", 1, true) and tip:find("5. Herbs Three", 1, true)
	and tip:find("8. Report Back", 1, true) and not tip:find("3. ", 1, true), "a long chain in the tooltip: five steps from one before (" .. tip .. ")")
GameTooltip:Hide()
-- Alt-click (Questtree.lua's hook on the quest log's details hands it over): opened on the next frame.
local before = #opened
Q.LogAltClick(9102)
check(#opened == before, "Alt-click: nothing opened in the quest log's own click")
Step()
check(opened[#opened] == 9102, "... it opens on the next frame, in our own code")
-- The setting off: the open log loses them at once.
LT:SetModuleSetting(M, "logBadges", false)
check(not badges[axe]:IsShown(), "the setting off: the open log's steps go")
QuestLogQuests_Update()
axe = TitleButton(9102) -- (the pool may hand out the buttons in another order)
GameTooltip:SetOwner(axe); TOOLTIP.shown = true
axe._scripts.OnEnter(axe)
check(not (badges[axe] and badges[axe]:IsShown()) and #TOOLTIP.lines == 0, "... and stay away, nothing in the tooltip")
GameTooltip:Hide()
before = #opened
Q.LogAltClick(9102)
Step()
check(#opened == before, "... and Alt-click does nothing")
LT:SetModuleSetting(M, "logBadges", true)
check(badges[axe] and badges[axe]:IsShown(), "on again: the open log has them at once")

-- Put back what this file replaced, the mock's world; the clock on a whole second.
for name in pairs(replaced) do PutBack(name) end
QUESTS, DIALOG_QUEST = savedQuests, savedDialogQuest
C_QuestLog.GetAllCompletedQuestIDs = savedCompleted
QuestLogQuests_Update()
Progress()
if spent ~= math.ceil(spent) then
	Advance(math.ceil(spent) - spent)
end
