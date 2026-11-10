-- Questtree: the module (on by default, its settings, /questtree and /lefthy questtree, the best
-- pick of a search), the small window (nothing loaded or listened to until it opens; what's next
-- when opened on its own; title, level, status, "Needs first", giver and turn-in, the small map,
-- "Leads to", friends; Back; the data missing; an unknown quest; its place and size kept; Escape;
-- in a fight; switched off) and the small map (art, markers and their tooltips, one marker for a
-- giver who's also the turn-in, no map).
-- Without Data.lua and Engine.lua in the build (the parts are made in parallel) this file puts
-- stand-ins of their Q.* functions on ns.Questtree (below, "Stand-ins"); with them it installs its
-- quests through Data's Q.SetTestData and checks against what the engine says. Whatever it replaces
-- is put back at its end.
-- Needs: no other file.

local suite = ...
local check, section, ns, LT, lefthy = suite.check, suite.section, suite.ns, suite.LT, suite.lefthy
local printedSince = suite.printedSince
local Q = ns.Questtree
local M = LT:GetModule("questtree")
local slash = SlashCmdList.LEFTHYTOOLS_QUESTTREE

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

-- The quests: a chain of three over two zones (Elwynn Forest 1429, Westfall 1436), a quest whose
-- giver is also its turn-in, one started by an item, one for a higher level, and one to search for.
local QUESTS_DATA = {
	[9001] = { id = 9001, title = "A Fine Start", level = 5, minLevel = 3, zone = 1429, opens = { 9002 },
		starts = { { kind = "npc", id = 900, name = "Marshal Dughan", points = { { map = 1429, x = 0.42, y = 0.65 } } } },
		ends = { { kind = "npc", id = 901, name = "Guard Thomas", points = { { map = 1429, x = 0.74, y = 0.72 } } } } },
	[9002] = { id = 9002, title = "The Second Step", level = 6, minLevel = 4, zone = 1429, pre = { 9001 }, opens = { 9003 },
		starts = { { kind = "npc", id = 901, name = "Guard Thomas", points = { { map = 1429, x = 0.74, y = 0.72 } } } },
		ends = { { kind = "npc", id = 902, name = "Farmer Saldean", points = { { map = 1436, x = 0.56, y = 0.31 } } } } },
	[9003] = { id = 9003, title = "Westward Bound", level = 10, minLevel = 8, zone = 1436, pre = { 9002 },
		starts = { { kind = "npc", id = 902, name = "Farmer Saldean", points = { { map = 1436, x = 0.56, y = 0.31 } } } },
		ends = { { kind = "object", id = 5, name = "Old Chest", points = { { map = 1436, x = 0.3, y = 0.4 } } } } },
	[9005] = { id = 9005, title = "Fine Wolf Pelts", level = 7, minLevel = 5, zone = 1429,
		starts = { { kind = "npc", id = 903, name = "Tailor Ann", points = { { map = 1429, x = 0.5, y = 0.5 } } } },
		ends = { { kind = "npc", id = 903, name = "Tailor Ann", points = { { map = 1429, x = 0.5, y = 0.5 } } } } },
	[9006] = { id = 9006, title = "A Dusty Letter", level = 12, minLevel = 10, zoneName = "Duskwood",
		starts = { { kind = "item", id = 7000, name = "Dusty Letter", points = {} } }, ends = {} },
	[9008] = { id = 9008, title = "Far Too Hard", level = 32, minLevel = 30, zone = 1436,
		starts = { { kind = "npc", id = 904, name = "Old Bill", points = { { map = 1436, x = 0.2, y = 0.2 } } } }, ends = {} },
}
local ZONES = { { map = 1429, name = "Elwynn Forest", continent = 1415, minLevel = 1, maxLevel = 10, count = 4 },
	{ map = 1436, name = "Westfall", continent = 1415, minLevel = 9, maxLevel = 18, count = 2 } }

---------------------------------------------------------------------------
-- Stand-ins for Data.lua and Engine.lua (only while they aren't in the build)
---------------------------------------------------------------------------

local stubbed = Q.SetTestData == nil
local completed = {} -- the stand-ins' completed quests
if stubbed then
	local data, listeners = nil, {}
	local function InLog(id) return C_QuestLog.GetLogIndexForQuestID(id) ~= nil end
	Replace("HasData", function() return true end)
	Replace("Load", function() data = data or {}; return true end)
	Replace("SetTestData", function(quests)
		data = quests
		for _, fn in ipairs(listeners) do fn() end
	end)
	Replace("OnDataChanged", function(fn) listeners[#listeners + 1] = fn end)
	Replace("Quest", function(id) return data and data[id] end)
	Replace("Search", function(text)
		local list, want = {}, text:lower()
		for id, q in pairs(data or {}) do
			local hit = q.title:lower():find(want, 1, true)
			for _, who in ipairs(q.starts or {}) do hit = hit or (who.name or ""):lower():find(want, 1, true) end
			if hit then list[#list + 1] = id end
		end
		table.sort(list)
		return list
	end)
	Replace("Status", function(id)
		local q = data and data[id]
		if completed[id] then return "done" end
		if InLog(id) then return "active" end
		if not q then return "other" end
		for _, pre in ipairs(q.pre or {}) do
			if not completed[pre] then return "locked" end
		end
		if (q.minLevel or 0) > UnitLevel("player") then return "level" end
		return "available"
	end)
	Replace("Missing", function(id)
		local list, seen = {}, {}
		local function Walk(qid)
			local q = data and data[qid]
			for _, pre in ipairs(q and q.pre or {}) do
				if not completed[pre] and not seen[pre] then
					seen[pre] = true
					Walk(pre)
					list[#list + 1] = { id = pre, status = Q.Status(pre), reason = "Must be done first." }
				end
			end
		end
		Walk(id)
		return list
	end)
	Replace("Opens", function(id) local q = data and data[id]; return q and q.opens or {} end)
	Replace("Next", function()
		local list = {}
		for id in pairs(data or {}) do
			local s = Q.Status(id)
			if s == "available" then list[#list + 1] = id end
		end
		table.sort(list)
		return list
	end)
	Replace("Friends", function() return {} end)
end

-- Counts what's loaded and asked for from here on.
local loads, asked = 0, 0
local realLoad, realStatus = Q.Load, Q.Status
Replace("Load", function(...) loads = loads + 1; return realLoad(...) end)
Replace("Status", function(...) asked = asked + 1; return realStatus(...) end)

local function S(key) return REGISTERED_SETTINGS["LefthyTools_questtree_" .. key] end
local function Small() return Q.SmallFrame() end
-- A text without its colours; the first line (of a list of texts) that has text in it, colours left out.
local function Plain(text) return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function Has(list, text)
	for _, line in ipairs(list) do
		if type(line) == "string" and Plain(line):find(Plain(text), 1, true) then return line end
	end
end
local function RowWith(text)
	for _, row in ipairs(Small().rows) do
		if Plain(row.Text:GetText()):find(text, 1, true) then return row end
	end
end

section("Questtree: the module")
check(M and M.title == "Questtree" and M.enabled, "the module is there and on by default")
check(M.db.learn == true and M.db.friends == true and M.db.keepPlace == true and type(M.db.small) == "table",
	"its defaults: learning, friends' progress, the small window keeps its place")
check(S("keepPlace") and S("friends") and S("learn") and SETTINGS_BUTTONS["Open the small window"]
	and SETTINGS_BUTTONS["Open the quest browser"], "its settings page: three checkboxes and the two windows' buttons")
check(LefthyToolsQuesttreeSmall == nil and loads == 0, "nothing built or loaded before a window opens")

---------------------------------------------------------------------------
section("Questtree: the small window")
Q.SetTestData(QUESTS_DATA, ZONES)
local mark = #PRINTED
slash("")
local s = Small()
local nextUp = Q.Next()
local firstShown = s.quest
check(s.win and s.win:IsShown() and loads > 0, "/questtree opens it, and the data loads now")
check(s.quest == nextUp[1], "opened on its own it shows what's next for me: " .. tostring(nextUp[1]) .. ", got " .. tostring(s.quest))
local escapes = false
for _, name in ipairs(UISpecialFrames) do if name == "LefthyToolsQuesttreeSmall" then escapes = true end end
check(escapes and s.win:GetScript("OnUpdate") == nil, "Escape closes it; no OnUpdate")
check(s.win.TitleContainer.TitleText:GetText() == "Questtree", "its title is the module's name")

slash("9002")
s = Small()
local status = Q.StatusOf(9002)
check(s.quest == 9002 and s.texts and Has(s.texts, "The Second Step"), "/questtree 9002: the quest, its title")
check(Has(s.texts, "Level 6 (from 4)") and Has(s.texts, "Elwynn Forest"), "its level and zone")
check(Has(s.texts, Q.StatusText(status)), "my status in its colour: " .. Q.StatusText(status))
local missing = Q.Missing(9002)
check(#missing > 0 and missing[1].id == 9001 and Has(s.texts, "Needs first:") and RowWith("1. A Fine Start"),
	"Needs first: the quest before it, numbered")
check(RowWith("Quest giver: Guard Thomas, Elwynn Forest") and RowWith("Turn-in: Farmer Saldean, Westfall"),
	"the giver and the turn-in with their zones")
check(RowWith("- Westward Bound") and Has(s.texts, "Leads to:"), "Leads to: what it opens")
local giverMap = s.map.map
check(s.map.frame:IsShown() and giverMap == (status == "active" and 1436 or 1429) and #s.map:Markers() == 1,
	"the small map: the giver's zone (not in my log), its marker")

-- A row's tooltip, a click on it, Back.
local row = RowWith("1. A Fine Start")
row:GetScript("OnEnter")(row)
check(TOOLTIP.shown and TOOLTIP.title == "A Fine Start" and Has(TOOLTIP.lines, "Click: show this quest"), "a row's tooltip says what a click does")
row:Click()
s = Small()
check(s.quest == 9001 and s.win.Back:IsShown() and s.history[#s.history] == 9002 and not TOOLTIP.shown,
	"a click on it shows that quest; Back is there")
check(#s.map:Markers() == 2, "the giver and the turn-in, both in Elwynn Forest: two markers")
RowWith("- The Second Step"):Click()
check(Small().quest == 9002, "a quest it leads to, clicked: shown")
s.win.Back:Click()
check(Small().quest == 9001, "Back: the one before")
s.win.Back:Click()
check(Small().quest == 9002, "and the one before that")
s.win.Back:Click()
check(Small().quest == (firstShown or 9002) and #Small().history == 0 and not s.win.Back:IsShown(), "back to the first (what was next up): nothing left to go back to")
slash("9002")

-- The turn-in's line puts its zone on the map; its marker's tooltip.
RowWith("Turn-in:"):Click()
s = Small()
local markers = s.map:Markers()
check(s.map.map == 1436 and #markers == 1 and s.map.Zone:GetText() == "Westfall", "the turn-in's line: its zone on the small map")
markers[1]:GetScript("OnEnter")(markers[1])
check(TOOLTIP.title == "Farmer Saldean" and Has(TOOLTIP.lines, "Turn-in"), "a marker's tooltip: who, and that it's the turn-in")
markers[1]:GetScript("OnLeave")(markers[1])
RowWith("Quest giver:"):Click()
check(Small().map.map == 1429, "the giver's line: back to the giver's zone")

-- In my quest log: the client's title, the turn-in's map.
local questsBefore = QUESTS
QUESTS = { { id = 9002, title = "Der zweite Schritt", objectives = {} } }
slash("9001") -- (another quest first: a new quest's map follows my status)
slash("9002")
s = Small()
check(Has(s.texts, "Der zweite Schritt") and not Has(s.texts, "The Second Step"), "the client's title when it answers")
check(Q.StatusOf(9002) ~= "active" or (s.map.map == 1436 and Has(s.texts, Q.StatusText("active"))),
	"in my log: the turn-in's zone on the map, the status says so")
QUESTS = questsBefore

-- Same giver and turn-in: one marker, both in its tooltip.
slash("9005")
markers = Small().map:Markers()
check(#markers == 1 and #markers[1].lines == 2, "a giver who's also the turn-in: one marker")
markers[1]:GetScript("OnEnter")(markers[1])
check(TOOLTIP.title == "Tailor Ann" and Has(TOOLTIP.lines, "Quest giver") and Has(TOOLTIP.lines, "Turn-in"), "its tooltip says both")
markers[1]:GetScript("OnLeave")(markers[1])

-- Started by an item, no turn-in known, no map; an object; too high a level.
slash("9006")
s = Small()
check(RowWith("Quest giver: Dusty Letter (an item)") and Has(s.texts, "Turn-in: not known") and Has(s.texts, "Duskwood")
	and not s.map.frame:IsShown(), "an item starts it, the turn-in isn't known, no map: none shown, the data's zone name")
lefthy("questtree 9003")
s = Small()
check(s.quest == 9003 and RowWith("Turn-in: Old Chest (an object), Westfall"), "/lefthy questtree 9003; an object for a turn-in")
slash("9008")
check(Q.StatusOf(9008) ~= "level" or Has(Small().texts, "Your level is too low: from level 30"), "too low: from which level")

-- Friends' progress (Q.Friends: Learn.lua's), and the setting.
Replace("Friends", function(id) return id == 9008 and { { name = "Anna Brook", classFile = "MAGE", status = "done" } } or {} end)
Q.RedrawSmall(true)
local friendsLine = Has(Small().texts, "Friends:")
check(friendsLine and friendsLine:find("Anna Brook", 1, true) and friendsLine:find(Q.StatusText("done", "friend"), 1, true),
	"friends' progress: their name and status")
LT:SetModuleSetting(M, "friends", false)
Q.RedrawSmall(true)
check(not Has(Small().texts, "Friends:"), "friends' progress switched off: no line")
LT:SetModuleSetting(M, "friends", true)
PutBack("Friends")

-- An unknown quest; the data missing.
slash("123456")
s = Small()
check(Has(s.texts, "Quest 123456") and Has(s.texts, "This quest isn't in the quest data.") and not s.map.frame:IsShown(),
	"a quest the data doesn't know: says so")
local loadNow = Q.Load
Replace("Load", function() return false end)
Q.RedrawSmall(true)
s = Small()
check(Has(s.texts, "The quest data isn't there") and #s.rows == 0 and not s.map.frame:IsShown() and not s.win.Next:IsEnabled(),
	"the data add-on missing: the window says so, nothing else")
Q.Load = loadNow
Q.RedrawSmall(true)

-- The search: an exact title first, then one starting with the text; none.
mark = #PRINTED
slash("a fine start")
check(Small().quest == 9001, "/questtree <name>: the quest with that title")
slash("fine")
check(Small().quest == 9005 and printedSince(mark + 1):find("2 quests match \"fine\": showing Fine Wolf Pelts", 1, true),
	"several match: the one whose title starts with it, and chat says how many")
mark = #PRINTED
slash("zzzz")
check(Small().quest == 9005 and printedSince(mark + 1):find("no quest matches \"zzzz\"", 1, true), "none: chat says so, the window stays")
local link = "|cffffff00|Hquest:9003:10|h[Westward Bound]|h|r"
slash(link)
check(Small().quest == 9003, "a quest link")

-- /questtree browse: the big window (Browser.lua), when it's there.
mark = #PRINTED
local browsed = 0
if Q.ToggleBrowser then
	Replace("ToggleBrowser", function() browsed = browsed + 1 end)
	slash("browse")
	check(browsed == 1, "/questtree browse opens the quest browser")
	PutBack("ToggleBrowser")
else
	slash("browse")
	check(printedSince(mark + 1):find("the quest browser isn't there", 1, true), "/questtree browse without the browser: says so")
end

-- Only while it's shown it listens to the quest log, and redraws a moment later.
asked = 0
Fire("QUEST_REMOVED", 9001)
Advance(0.5)
check(asked > 0, "shown: a quest abandoned redraws it")
Small().win:Hide()
asked = 0
Fire("QUEST_REMOVED", 9001)
Advance(0.5)
check(asked == 0, "hidden: nothing listened to, nothing drawn")

---------------------------------------------------------------------------
section("Questtree: the small window's place and size")
slash("9001")
s = Small()
local win = s.win
local _, _, _, x = win:GetPoint(1)
check(win:GetWidth() == 320 and win:GetHeight() == 470 and x == 280, "at first: right of the middle, its usual size")
win._dropAt = { left = 100, top = 600 }
win:GetScript("OnDragStart")(win)
win:GetScript("OnDragStop")(win)
check(M.db.small.left == 100 and M.db.small.top == 600, "dragged: where it is kept")
win._dropAt = nil
win.Grip:GetScript("OnMouseDown")(win.Grip)
check(win._sizing == "BOTTOMRIGHT", "the corner resizes it")
win._dropSize = { 420, 2000 }
win.Grip:GetScript("OnMouseUp")(win.Grip)
check(M.db.small.width == 420 and M.db.small.height == 900, "resized: its size kept (within its bounds)")
check(Small().content:GetWidth() == 360 and Small().map.width == 360, "its lines and the small map follow its width")
win:Hide()
slash("")
local _, _, _, left, top = win:GetPoint(1)
check(win:IsShown() and left == 100 and top == 600 and win:GetWidth() == 420, "opened again: where it was left, at its size")
win:Hide()
LT:SetModuleSetting(M, "keepPlace", false)
slash("")
_, _, _, x = win:GetPoint(1)
check(x == 280 and win:GetWidth() == 320, "the setting off: its usual place and size")
LT:SetModuleSetting(M, "keepPlace", true)

-- In a fight it opens and works the same (nothing protected).
win:Hide()
EnterCombat()
slash("9002")
check(win:IsShown() and Small().quest == 9002, "in a fight it opens")
LeaveCombat()

-- Controller: every line that does something is a button of ours, nothing of Blizzard's set on them.
local allButtons = true
for _, r in ipairs(Small().rows) do allButtons = allButtons and r._kind == "Button" end
for _, m in ipairs(Small().map:Markers()) do allButtons = allButtons and m._kind == "Button" end
allButtons = allButtons and win.Back._kind == "Button" and win.Next._kind == "Button" and win.Browser._kind == "Button"
check(allButtons, "rows, markers and the window's buttons are buttons (the controller's cursor reaches them)")
local blizzard = false
for _, f in ipairs({ win, win.Back, win.Next, win.Browser, Small().rows[1] }) do
	for k in pairs(f) do
		if type(k) == "string" and k:lower():find("smartnav", 1, true) then blizzard = true end
	end
end
check(not blizzard, "no SmartNavigation values on our frames")

-- Next up.
win.Next:Click()
check(Small().quest == Q.Next()[1] or (Q.Next()[1] == nil and Small().quest == 9002), "Next up: what's next for me")

-- Switched off: the window goes, /questtree says so.
LT:SetModuleEnabled("questtree", false)
mark = #PRINTED
slash("")
check(not win:IsShown() and printedSince(mark + 1):find("Questtree is switched off", 1, true), "switched off: hidden, /questtree says so")
LT:SetModuleEnabled("questtree", true)

---------------------------------------------------------------------------
section("Questtree: the small map")
do
	local m = Q.NewMiniMap(UIParent)
	check(not m.frame:IsShown() and m.width == 240 and m.height == 160, "made hidden, 240 x 160")
	m:Show(1429, { { x = 0.5, y = 0.25, kind = "start", label = "A" }, { x = 2, y = 0.5, kind = "end", label = "off the map" } })
	local list = m:Markers()
	local _, _, _, mx, my = list[1]:GetPoint(1)
	check(m.frame:IsShown() and not m.Empty:IsShown() and m.art.tileCount > 0 and #list == 1, "the zone's art and a marker (one off the map left out)")
	check(mx == m.Map:GetWidth() * 0.5 and my == -m.Map:GetHeight() * 0.25, "the marker where its point is on the art")
	check(list[1].Icon.path == "Interface\\GossipFrame\\AvailableQuestIcon", "a giver's marker: the quest giver's !")
	m:Show(9999, { { x = 0.5, y = 0.5, kind = "end", label = "B" } })
	check(m.Empty:IsShown() and #m:Markers() == 1 and m:Markers()[1].Icon.path == "Interface\\GossipFrame\\ActiveQuestIcon",
		"a map without art: says so, the marker on the dark box (a turn-in's ?)")
	m:Show(nil, {})
	check(m.Empty:IsShown() and #m:Markers() == 0 and not m.markers[1]:IsShown(), "no map: no markers")
	m:Hide()
	check(not m.frame:IsShown(), "hidden")
end

-- Put back what this file replaced (the stand-ins too: the real parts, once they're in the build,
-- keep theirs).
for name in pairs(replaced) do PutBack(name) end
Advance(1)
