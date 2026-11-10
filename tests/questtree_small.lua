-- Questtree: the module (on by default, its settings, /questtree and /lefthy questtree, the best
-- pick of a search), the companion (nothing loaded or listened to until it opens; Now: the quest
-- I'm on and why, its chain and steps, objectives, turn-in, what's next; it follows super tracking,
-- the quest log's details, accepting and turning in; Pick up next: in progress, available now
-- nearest first with distance and direction, follow-ups first, coming up, blocked), a quest looked
-- at ("« Back to", "Back to now", the drops of an item that starts it, Requires), the game's map
-- pin from a giver's line or a marker, NPC tooltip lines, events only while shown, its place and
-- size, a fight, the controller, switched off; difficulty colours; the small map alone (the game's
-- icons, drop spots, zoom, your arrow).
-- Data.lua and Engine.lua are in the build: the quests go in through Q.SetTestData. The calls the
-- data part adds in parallel (Q.ChainStep, Q.Available, Q.LevelColor, Q.ZoneCount, Q.GiverQuests)
-- get stand-ins here only while they're missing; with them gone it checks the window still works.
-- Whatever it replaces is put back at its end.
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
-- A stand-in only where the data part hasn't put its own yet.
local function StandIn(name, fn)
	if Q[name] == nil then Replace(name, fn) end
end

-- The quests (Elwynn Forest 1429, Westfall 1436): a chain of three over both zones, a quest whose
-- giver is also its turn-in, one started by an item that drops in Westfall, one for a higher level
-- in Westfall, two more to pick up in Elwynn (near me and far), one there for later, one after the
-- giver-and-turn-in one.
local function Npc(id, name, map, x, y) return { kind = "npc", id = id, name = name, points = { { map = map, x = x, y = y } } } end
local QUESTS_DATA = {
	[9001] = { id = 9001, title = "A Fine Start", level = 5, minLevel = 3, zone = 1429, opens = { 9002 },
		starts = { Npc(900, "Marshal Dughan", 1429, 0.42, 0.65) }, ends = { Npc(901, "Guard Thomas", 1429, 0.74, 0.72) } },
	[9002] = { id = 9002, title = "The Second Step", level = 6, minLevel = 4, zone = 1429, pre = { 9001 }, opens = { 9003 },
		starts = { Npc(901, "Guard Thomas", 1429, 0.74, 0.72) }, ends = { Npc(902, "Farmer Saldean", 1436, 0.56, 0.31) } },
	[9003] = { id = 9003, title = "Westward Bound", level = 10, minLevel = 8, zone = 1436, pre = { 9002 },
		starts = { Npc(902, "Farmer Saldean", 1436, 0.56, 0.31) },
		ends = { { kind = "object", id = 5, name = "Old Chest", points = { { map = 1436, x = 0.3, y = 0.4 } } } } },
	[9005] = { id = 9005, title = "Fine Wolf Pelts", level = 7, minLevel = 5, zone = 1429,
		starts = { Npc(903, "Tailor Ann", 1429, 0.5, 0.5) }, ends = { Npc(903, "Tailor Ann", 1429, 0.5, 0.5) } },
	[9006] = { id = 9006, title = "A Dusty Letter", level = 12, minLevel = 10, zoneName = "Duskwood",
		starts = { { kind = "item", id = 7000, name = "Dusty Letter", points = {}, drops = {
			{ kind = "npc", id = 950, name = "Defias Pillager", chance = 12, points = { { map = 1436, x = 0.4, y = 0.5, r = 0.1 } } },
			{ kind = "npc", id = 951, name = "Defias Looter", chance = 0.5, points = { { map = 1436, x = 0.7, y = 0.2 } } } } } },
		ends = {} },
	[9008] = { id = 9008, title = "Far Too Hard", level = 32, minLevel = 30, zone = 1436,
		starts = { Npc(904, "Old Bill", 1436, 0.2, 0.2) }, ends = {} },
	[9010] = { id = 9010, title = "Kobold Candles", level = 8, minLevel = 4, zone = 1429,
		starts = { Npc(905, "William Pestle", 1429, 0.52, 0.48) }, ends = { Npc(906, "Maybell", 1429, 0.6, 0.6) } },
	[9011] = { id = 9011, title = "Far Away Farm", level = 9, minLevel = 5, zone = 1429,
		starts = { Npc(907, "Farmer Ray", 1429, 0.9, 0.1) }, ends = { Npc(907, "Farmer Ray", 1429, 0.9, 0.1) } },
	[9014] = { id = 9014, title = "Ann's Second Order", level = 8, minLevel = 5, zone = 1429, pre = { 9005 },
		starts = { Npc(903, "Tailor Ann", 1429, 0.5, 0.5) }, ends = { Npc(903, "Tailor Ann", 1429, 0.5, 0.5) } },
	[9012] = { id = 9012, title = "Later Wolves", level = 25, minLevel = 22, zone = 1429,
		starts = { Npc(908, "Hunter Kay", 1429, 0.3, 0.3) }, ends = {} },
}
local ZONES = { { map = 1429, name = "Elwynn Forest", continent = 1415, minLevel = 1, maxLevel = 10 },
	{ map = 1436, name = "Westfall", continent = 1415, minLevel = 9, maxLevel = 18 } }

---------------------------------------------------------------------------
-- My progress (completed quests, the quest log) and what the mock lacks
---------------------------------------------------------------------------

local completed = {}
local savedCompleted = C_QuestLog.GetAllCompletedQuestIDs
C_QuestLog.GetAllCompletedQuestIDs = function()
	local list = {}
	for id in pairs(completed) do list[#list + 1] = id end
	return list
end
local savedQuests, savedSuper, savedPos, savedMap = QUESTS, SUPER_TRACKED, { PLAYER_POS[1], PLAYER_POS[2] }, PLAYER_MAP
local function Log(list) -- the quest log: { id, ... } or { { id, complete } }
	QUESTS = {}
	for _, e in ipairs(list) do
		local id = type(e) == "table" and e[1] or e
		QUESTS[#QUESTS + 1] = { id = id, title = QUESTS_DATA[id].title, complete = type(e) == "table" and e[2] or nil,
			objectives = { { text = "Wolf Pelts: 2/5", finished = false }, { text = "Candles: 3/3", finished = true } } }
	end
end
-- The game's map pin and the chat box.
local pins, links = {}, {}
local savedMapApi = { SetUserWaypoint = C_Map.SetUserWaypoint, CanSetUserWaypointOnMap = C_Map.CanSetUserWaypointOnMap,
	GetUserWaypointHyperlink = C_Map.GetUserWaypointHyperlink }
local savedPoint, savedChat, savedSuperPin = UiMapPoint, ChatFrameUtil, C_SuperTrack.SetSuperTrackedUserWaypoint
UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { uiMapID = map, position = { x = x, y = y } } end }
C_Map.CanSetUserWaypointOnMap = function(map) return map ~= 9999 end
C_Map.SetUserWaypoint = function(point) pins[#pins + 1] = point end
C_Map.GetUserWaypointHyperlink = function() return "|cffffff00|Hworldmap:1429:5000:5000|h[Map Pin]|h|r" end
C_SuperTrack.SetSuperTrackedUserWaypoint = function(on) pins.tracked = on end
ChatFrameUtil = setmetatable({ InsertLink = function(link) links[#links + 1] = link; return true end }, { __index = savedChat or {} })
-- The quest log's details (Blizzard_UIPanels_Game): opening a quest there.
local madeDetails = QuestMapFrame_ShowQuestDetails == nil
if madeDetails then QuestMapFrame_ShowQuestDetails = function() end end

---------------------------------------------------------------------------
-- Stand-ins for what the data part adds in parallel (only while missing)
---------------------------------------------------------------------------

local giverAsks = 0
StandIn("ChainStep", function(id)
	local chain = Q.Chain(id)
	if #chain < 2 then return nil end
	for i, other in ipairs(chain) do if other == id then return i, #chain, Q.Quest(chain[1]).title, chain[1] end end
end)
StandIn("Available", function(map, x, y)
	local list, far = {}, {}
	for _, id in ipairs(Q.ZoneQuests(map)) do
		if Q.Status(id) == "available" then
			local _, _, d = Q.NearestPoint(Q.Quest(id).starts, map, x, y)
			list[#list + 1], far[id] = id, d or 99
		end
	end
	table.sort(list, function(a, b) if far[a] ~= far[b] then return far[a] < far[b] end return a < b end)
	return list
end)
StandIn("LevelColor", function(level)
	local diff = level - UnitLevel("player")
	local key = diff >= 5 and "impossible" or diff >= 3 and "verydifficult" or diff >= -4 and "difficult" or diff >= -9 and "standard" or "trivial"
	local c = Q.DIFFICULTY[key]
	return { r = c[1], g = c[2], b = c[3], hex = "", key = key }
end)
StandIn("ZoneCount", function(map)
	local done, total = 0, 0
	for _, id in ipairs(Q.ZoneQuests(map)) do
		local s = Q.Status(id)
		if s ~= "other" then total = total + 1; if s == "done" then done = done + 1 end end
	end
	return done, total
end)
StandIn("GiverQuests", function(npc)
	giverAsks = giverAsks + 1
	local starts, ends = {}, {}
	for id, q in pairs(QUESTS_DATA) do
		for _, who in ipairs(q.starts) do if who.kind == "npc" and who.id == npc then starts[#starts + 1] = id end end
		for _, who in ipairs(q.ends) do if who.kind == "npc" and who.id == npc then ends[#ends + 1] = id end end
	end
	table.sort(starts)
	table.sort(ends)
	return starts, ends
end)

-- Counts what's loaded and asked for from here on.
local loads, asked = 0, 0
local realLoad, realStatus = Q.Load, Q.Status
Replace("Load", function(...) loads = loads + 1; return realLoad(...) end)
Replace("Status", function(...) asked = asked + 1; return realStatus(...) end)

local function S(key) return REGISTERED_SETTINGS["LefthyTools_questtree_" .. key] end
local function Small() return Q.SmallFrame() end
local function Plain(text) return (text:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
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
local function RowIndex(text)
	for i, row in ipairs(Small().rows) do
		if Plain(row.Text:GetText()):find(text, 1, true) then return i end
	end
end
local function RowLast(text) -- the last row with text (a group's, after Now's lines)
	local found
	for _, row in ipairs(Small().rows) do
		if Plain(row.Text:GetText()):find(text, 1, true) then found = row end
	end
	return found
end
local function Progress() -- the engine reads my progress again (as after a loading screen)
	Fire("PLAYER_ENTERING_WORLD", false, false)
	Fire("QUEST_LOG_UPDATE")
end

section("Questtree: the module")
check(M and M.title == "Questtree" and M.enabled, "the module is there and on by default")
check(M.db.learn == true and M.db.friends == true and M.db.keepPlace == true and M.db.followLog == true and M.db.tooltips == true
	and type(M.db.small) == "table", "its defaults: learning, friends, keeps its place, follows the quest log, tooltip lines")
check(S("keepPlace") and S("followLog") and S("tooltips") and S("friends") and S("learn") and SETTINGS_BUTTONS["Open the small window"]
	and SETTINGS_BUTTONS["Open the quest browser"], "its settings page: five checkboxes and the two windows' buttons")
check(LefthyToolsQuesttreeSmall == nil and loads == 0, "nothing built or loaded before a window opens")

---------------------------------------------------------------------------
section("Questtree: difficulty colours")
do
	local levelColor = Q.LevelColor
	Q.LevelColor = nil
	PLAYER_LEVEL = 19
	check(Q.DifficultyKey(nil, nil, 32) == "impossible" and Q.DifficultyKey(nil, nil, 22) == "verydifficult"
		and Q.DifficultyKey(nil, nil, 15) == "difficult" and Q.DifficultyKey(nil, nil, 13) == "standard"
		and Q.DifficultyKey(nil, nil, 5) == "trivial", "by the level difference, as the game's quest log: red, orange, yellow, green, grey")
	check(Q.LevelCode(nil, nil, 32) == "|cffff1a1a" and Q.LevelCode(nil, nil, 5) == "|cff808080"
		and Q.LevelCode(nil, { repeatable = true, level = 30 }) == "|cff4099ff", "the game's colours; a repeatable quest blue")
	Q.LevelColor = levelColor
	check(Q.LevelCode(nil, nil, 32) == "|cffff1a1a", "with the data part's Q.LevelColor: its colour")
end

---------------------------------------------------------------------------
section("Questtree: the companion (Now)")
Q.SetTestData(QUESTS_DATA, ZONES)
completed = { [9001] = true }
Log({ 9002, { 9005, true } })
PLAYER_MAP, PLAYER_POS[1], PLAYER_POS[2], SUPER_TRACKED = 1429, 0.5, 0.5, 0
Progress()
slash("")
local s = Small()
check(s.win and s.win:IsShown() and loads > 0 and s.mode == "now", "/questtree opens it on now, and the data loads now")
local escapes = false
for _, name in ipairs(UISpecialFrames) do if name == "LefthyToolsQuesttreeSmall" then escapes = true end end
check(escapes and s.win:GetScript("OnUpdate") == nil and s.win.TitleContainer.TitleText:GetText() == "Questtree",
	"Escape closes it, no OnUpdate on it, its title is the module's name")
check(s.now == 9002 and Has(s.texts, "Now  in this zone"), "now: the quest of my log in this zone, and why: " .. tostring(s.now))
check(RowWith("[6] The Second Step") and Has(s.texts, "A Fine Start: step 2 of 3") and s.win.Bar:IsShown(),
	"its title with its level, its chain's step and the bar")
check(Has(s.texts, "In your quest log") and Has(s.texts, "- Wolf Pelts: 2/5") and Has(s.texts, "Candles: 3/3"),
	"in my log, its objectives (done ones ticked)")
check(RowWith("Turn-in: Farmer Saldean, Westfall") and RowWith("Next: [10] Westward Bound - Farmer Saldean, Westfall"),
	"where to turn it in, what comes next and who gives it")
local done, current, future = RowWith("A Fine Start"), RowWith("2. The Second Step"), RowWith("3. Westward Bound")
check(Has(s.texts, "Steps") and done and done.Text:GetText():find("ReadyCheck-Ready", 1, true) and current
	and current.Text.font == "GameFontNormal" and future, "the chain's steps: done ticked, this one bold, the next one numbered")
check(s.map.frame:IsShown() and s.map.map == 1436 and #s.map:Markers() == 1 and s.map:Markers()[1].look == "progress",
	"the small map: the turn-in's zone, its marker (not done yet)")

section("Questtree: the companion (Pick up next)")
check(Has(s.texts, "Pick up next  Elwynn Forest") and Has(s.texts, "In progress") and Has(s.texts, "Available now")
	and Has(s.texts, "Coming up") and Has(s.texts, "Blocked"), "Pick up next: this zone, in groups")
local pelts = RowWith("[7] Fine Wolf Pelts")
check(pelts and Plain(pelts.Text:GetText()):find("ready to turn in · Tailor Ann", 1, true) and pelts.Right:GetText() == "right here",
	"in progress: my other quest, ready, its turn-in right here")
local candles, farm = RowIndex("[8] Kobold Candles"), RowIndex("[9] Far Away Farm")
check(candles and farm and candles < farm and Small().rows[candles].Right:GetText() == "30 yd NE"
	and Small().rows[farm].Right:GetText() == "570 yd NE", "available now: the nearest giver first, how far and which way")
check(Plain(Small().rows[candles].Text:GetText()):find("William Pestle", 1, true), "each with its giver")
local later = RowWith("[25] Later Wolves")
check(later and Plain(later.Text:GetText()):find("from level 22", 1, true), "coming up: a quest of this zone for a higher level")
local blocked = RowLast("[10] Westward Bound")
check(not (blocked and Plain(blocked.Text:GetText()):find("needs", 1, true)), "what now leads to isn't blocked again (it's its Next)")
local order = RowWith("[8] Ann's Second Order")
check(order and Plain(order.Text:GetText()):find("needs Fine Wolf Pelts", 1, true), "blocked: what it needs first")
check(Has(s.texts, "Elwynn Forest · 1 of 7 done"), "the zone's count (Q.ZoneCount)")

-- It follows: super tracking, the quest log's details, accepting, turning in.
SUPER_TRACKED = 9005
Fire("SUPER_TRACKING_CHANGED")
Advance(0.5)
s = Small()
check(s.now == 9005 and Has(s.texts, "Now  tracked") and Has(s.texts, "Ready to turn in"), "super-tracked: that's now, ready to turn in")
local markers = s.map:Markers()
check(s.map.map == 1429 and markers[1].look == "turnin" and #markers == 2 and #markers[1].lines == 2,
	"the map: my zone, its turn-in and the givers to pick up (one right next to it: in its marker)")
Advance(0.2)
check(s.map.Me:IsShown() and s.map.meX == 0.5, "my arrow on it")
Q.HookQuestLog()
QuestMapFrame_ShowQuestDetails(9002)
Advance(0.5)
check(Small().now == 9002 and Has(Small().texts, "opened in your quest log"), "a quest opened in the quest log: now")
LT:SetModuleSetting(M, "followLog", false)
QuestMapFrame_ShowQuestDetails(9005)
Advance(0.5)
check(Small().now == 9002, "the setting off: the quest log isn't followed")
LT:SetModuleSetting(M, "followLog", true)
Log({ 9002, { 9005, true }, 9010 })
Fire("QUEST_ACCEPTED", 9010)
Advance(0.5)
check(Small().now == 9010 and Has(Small().texts, "just accepted"), "a quest accepted: now")
Log({ { 9005, true }, 9010 })
completed[9002] = true
Fire("QUEST_TURNED_IN", 9002, 0, 0)
Fire("QUEST_REMOVED", 9002)
Advance(0.5)
s = Small()
local follow = RowIndex("[10] Westward Bound")
local firstPick = RowIndex("[9] Far Away Farm")
check(follow and Plain(s.rows[follow].Text:GetText()):find("after The Second Step", 1, true) and firstPick and follow < firstPick,
	"turned in: what it opens comes first in Available now, saying what it follows")

---------------------------------------------------------------------------
section("Questtree: a quest looked at")
s.rows[follow]:Click()
s = Small()
check(s.mode == "quest" and s.quest == 9003 and RowWith("« Back to now") and #s.history == 0, "a click shows it, with « Back to now")
check(Has(s.texts, "[10] Westward Bound") and Has(s.texts, "A Fine Start: step 3 of 3") and RowWith("Turn-in: Old Chest (an object), Westfall"),
	"its title, chain and turn-in")
RowWith("A Fine Start"):Click()
s = Small()
check(s.quest == 9001 and RowWith("« Back to Westward Bound") and RowWith("Back to now"), "a step clicked: « Back to the one before, and Back to now")
RowWith("« Back to Westward Bound"):Click()
check(Small().quest == 9003 and #Small().history == 0, "back: the one before")
RowWith("« Back to now"):Click()
check(Small().mode == "now" and Small().quest == nil, "back to now")

slash("9006")
s = Small()
check(RowWith("Quest giver: Dusty Letter (an item)") and Has(s.texts, "Drops from: Defias Pillager (12%), Defias Looter (0.5%)")
	and Has(s.texts, "Turn-in: not known") and Has(s.texts, "Duskwood"), "an item starts it: where it drops, the data's zone name")
markers = s.map:Markers()
check(s.map.map == 1436 and #markers == 2 and markers[1].kind == "drop" and markers[1].size > 34 and s.map.Label:IsShown()
	and s.map.Label:GetText() == "drops here (12%)", "the map: where it drops, the likeliest spot says so, as big as its area")
slash("9008")
check(Q.StatusOf(9008) ~= "level" or Has(Small().texts, "Your level is too low: from level 30"), "too low: from which level")
slash("9002")
check(Has(Small().texts, "You've done it") and #Small().history == 2, "done; the ones looked at before kept")

-- A giver's line and a marker: the game's map pin (Shift: in chat too).
slash("9010")
RowWith("Quest giver: William Pestle"):Click()
local pin = pins[#pins]
check(pin and pin.uiMapID == 1429 and pin.position.x == 0.52 and pins.tracked == true and #links == 0,
	"the giver's line: the game's map pin at the giver, tracked")
STATE.shift = true
markers = Small().map:Markers()
markers[1]:Click()
STATE.shift = false
check(#pins == 2 and links[1] and links[1]:find("worldmap", 1, true), "a marker, Shift-clicked: the pin, and its link in chat")
markers[1]:GetScript("OnEnter")(markers[1])
check(TOOLTIP.title == "William Pestle" and Has(TOOLTIP.lines, "Click: map pin"), "a marker's tooltip: who, what a click does")
markers[1]:GetScript("OnLeave")(markers[1])

-- Friends' dots on the steps and their line.
Replace("Friends", function(id) return id == 9001 and { { name = "Anna Brook", classFile = "MAGE", status = "done" },
	{ name = "Bo", classFile = "WARRIOR", status = "active" } } or {} end)
slash("9001")
local friends = RowWith("Friends: 1 of 2 done")
check(friends and friends.Text:GetText():find("TempPortraitAlphaMask", 1, true), "friends: how many did it, a dot in their class colour")
friends:GetScript("OnEnter")(friends)
check(Has(TOOLTIP.lines, "Anna Brook") and Has(TOOLTIP.lines, "Bo"), "its tooltip names each")
friends:GetScript("OnLeave")(friends)
LT:SetModuleSetting(M, "friends", false)
Q.RedrawSmall(true)
check(not RowWith("Friends:"), "friends' progress switched off: no line")
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
check(Has(s.texts, "The quest data isn't there") and #s.rows == 0 and not s.map.frame:IsShown() and not s.win.Browser:IsShown(),
	"the data add-on missing: the window says so, nothing else")
Q.Load = loadNow
Q.RedrawSmall(true)

-- The search: an exact title first, then one starting with the text; none; a link.
local mark = #PRINTED
slash("a fine start")
check(Small().quest == 9001, "/questtree <name>: the quest with that title")
slash("fine")
check(Small().quest == 9005 and printedSince(mark + 1):find("2 quests match \"fine\": showing Fine Wolf Pelts", 1, true),
	"several match: the one whose title starts with it, and chat says how many")
mark = #PRINTED
slash("zzzz")
check(Small().quest == 9005 and printedSince(mark + 1):find("no quest matches \"zzzz\"", 1, true), "none: chat says so, the window stays")
slash("|cffffff00|Hquest:9003:10|h[Westward Bound]|h|r")
check(Small().quest == 9003, "a quest link")
lefthy("questtree 9011")
check(Small().quest == 9011, "/lefthy questtree 9011")

-- /questtree browse: the big window (Browser.lua), when it's there.
mark = #PRINTED
if Q.ToggleBrowser then
	local browsed = 0
	Replace("ToggleBrowser", function() browsed = browsed + 1 end)
	slash("browse")
	check(browsed == 1, "/questtree browse opens the quest browser")
	PutBack("ToggleBrowser")
else
	slash("browse")
	check(printedSince(mark + 1):find("the quest browser isn't there", 1, true), "/questtree browse without the browser: says so")
end

---------------------------------------------------------------------------
section("Questtree: NPC tooltips")
do
	local call
	for _, c in ipairs(TOOLTIP_POSTCALLS) do if c[1] == Enum.TooltipDataType.Unit then call = c[2] end end
	local function Hover(npc, tooltip)
		GameTooltip:SetOwner(UIParent)
		call(tooltip or GameTooltip, { type = 2, guid = ("Creature-0-1-2-3-%d-0000ABCD"):format(npc) })
		return TOOLTIP.lines
	end
	check(call ~= nil, "a post-call on unit tooltips")
	check(Has(Hover(902), "Questtree: starts Westward Bound (step 3 of 3)"), "a giver: the quest I can take there, its step")
	check(Has(Hover(906), "Questtree: ends Kobold Candles"), "a turn-in of a quest in my log")
	check(Has(Hover(908), "Questtree: starts Later Wolves at level 22"), "a quest for later: from which level")
	check(Has(Hover(904), "Questtree: starts Far Too Hard at level 30") and #Hover(900) == 0 and #Hover(901) == 0,
		"too high a level: from which; done: nothing")
	local asks = giverAsks
	Hover(902)
	check(giverAsks == asks, "the same NPC again: its lines kept (a table lookup)")
	check(#Hover(902, ItemRefTooltip or {}) == 0, "only GameTooltip")
	INSTANCE = { type = "party" }
	check(#Hover(902) == 0, "in an instance: nothing (its data is secret there)")
	INSTANCE = nil
	LT:SetModuleSetting(M, "tooltips", false)
	check(#Hover(902) == 0, "the setting off: nothing")
	LT:SetModuleSetting(M, "tooltips", true)
	local isLoaded = Q.IsLoaded
	Replace("IsLoaded", function() return false end)
	loads = 0
	check(#Hover(902) == 0 and loads == 0, "the data not loaded: nothing, and a hover never loads it")
	Q.IsLoaded = isLoaded
	PutBack("IsLoaded")
	Q.IsLoaded = isLoaded
end

---------------------------------------------------------------------------
section("Questtree: only while it's shown")
Small().win:Hide()
slash("")
asked = 0
Fire("QUEST_REMOVED", 9001)
Advance(0.5)
check(asked > 0, "shown: a quest abandoned redraws it")
asked = 0
PLAYER_POS[1], PLAYER_POS[2] = 0.7, 0.7
Advance(2.5)
check(asked > 0, "moved far enough: drawn anew (the distances)")
Small().win:Hide()
asked = 0
Fire("QUEST_REMOVED", 9001)
SUPER_TRACKED = 9010
Fire("SUPER_TRACKING_CHANGED")
PLAYER_POS[1], PLAYER_POS[2] = 0.2, 0.2
Advance(3)
check(asked == 0, "hidden: nothing listened to, nothing drawn")
SUPER_TRACKED = 0

---------------------------------------------------------------------------
section("Questtree: the small window's place and size")
slash("9001")
s = Small()
local win = s.win
win:Hide()
slash("9001")
local _, _, _, x = win:GetPoint(1)
check(win:GetWidth() == 340 and win:GetHeight() == 580 and x == 280, "at first: right of the middle, its usual size")
win._dropAt = { left = 100, top = 600 }
win:GetScript("OnDragStart")(win)
win:GetScript("OnDragStop")(win)
check(M.db.small.left == 100 and M.db.small.top == 600, "dragged: where it is kept")
win._dropAt = nil
win.Grip:GetScript("OnMouseDown")(win.Grip)
check(win._sizing == "BOTTOMRIGHT", "the corner resizes it")
win._dropSize = { 420, 2000 }
win.Grip:GetScript("OnMouseUp")(win.Grip)
check(M.db.small.width == 420 and M.db.small.height == 950, "resized: its size kept (within its bounds)")
check(Small().content:GetWidth() == 360 and Small().map.width == 360, "its lines and the small map follow its width")
win:Hide()
slash("")
local _, _, _, left, top = win:GetPoint(1)
check(win:IsShown() and left == 100 and top == 600 and win:GetWidth() == 420, "opened again: where it was left, at its size")
win:Hide()
LT:SetModuleSetting(M, "keepPlace", false)
slash("")
_, _, _, x = win:GetPoint(1)
check(x == 280 and win:GetWidth() == 340, "the setting off: its usual place and size")
LT:SetModuleSetting(M, "keepPlace", true)

-- In a fight it opens and works the same (nothing protected).
win:Hide()
EnterCombat()
slash("9002")
check(win:IsShown() and Small().quest == 9002, "in a fight it opens")
LeaveCombat()

-- Controller: every line that does something is a button of ours, nothing of Blizzard's set on them.
win:Hide()
slash("")
local allButtons = #Small().rows > 0
for _, r in ipairs(Small().rows) do allButtons = allButtons and r._kind == "Button" end
for _, m in ipairs(Small().map:Markers()) do allButtons = allButtons and m._kind == "Button" end
allButtons = allButtons and win.Browser._kind == "Button"
check(allButtons, "rows, markers and the window's button are buttons (the controller's cursor reaches them)")
local blizzard = false
for _, f in ipairs({ win, win.Browser, Small().rows[1], Small().map.frame }) do
	for k in pairs(f) do
		if type(k) == "string" and k:lower():find("smartnav", 1, true) then blizzard = true end
	end
end
check(not blizzard, "no SmartNavigation values on our frames")

-- Without the data part's new calls the companion still works (its own way).
do
	local saved = {}
	for _, name in ipairs({ "ChainStep", "Available", "LevelColor", "ZoneCount", "GiverQuests" }) do saved[name], Q[name] = Q[name], nil end
	Log({ 9002 })
	completed[9002] = nil
	Progress()
	Q.RedrawSmall(true)
	s = Small()
	check(s.now == 9002 and Has(s.texts, "A Fine Start: step 2 of 3") and RowWith("[8] Kobold Candles"),
		"without Q.ChainStep, Q.Available, Q.LevelColor: its chain from Q.Chain, the zone's quests, the level colours")
	for name, fn in pairs(saved) do Q[name] = fn end
end

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
	check(not m.frame:IsShown() and m.width == 240 and m.height == 160 and m.frame._clips == true, "made hidden, 240 x 160, clipping its art")
	m:Show(1429, { { x = 0.5, y = 0.25, kind = "start", label = "A" }, { x = 2, y = 0.5, kind = "end", label = "off the map" } })
	local list = m:Markers()
	local _, _, _, mx, my = list[1]:GetPoint(1)
	check(m.frame:IsShown() and not m.Empty:IsShown() and m.art.tileCount > 0 and #list == 1, "the zone's art and a marker (one off the map left out)")
	check(mx == m.Map:GetWidth() * 0.5 and my == -m.Map:GetHeight() * 0.25, "the marker where its point is on the art")
	check(list[1].Icon.atlas == "QuestNormal" and list[1].Icon.vertex[4] == 1 and list[1].Shadow:IsShown(),
		"a giver: the game's yellow !, solid, on a dark outline")
	m:Show(1429, { { x = 0.5, y = 0.5, kind = "end", label = "B" }, { x = 0.51, y = 0.5, kind = "start", label = "C" },
		{ x = 0.2, y = 0.2, kind = "end", grey = true, label = "D" }, { x = 0.8, y = 0.8, kind = "start", look = "repeatable", label = "E" },
		{ x = 0.3, y = 0.7, kind = "start", look = "trivial", label = "F" } })
	list = m:Markers()
	check(#list == 4 and list[1].Icon.atlas == "QuestTurnin" and #list[1].lines == 2, "a turn-in's ?, and a giver at the same spot in one marker")
	check(list[2].Icon.atlas == "SideInProgressquesticon" and list[3].Icon.atlas == "QuestDaily" and list[4].Icon.vertex[4] < 1,
		"not done yet; repeatable; low level paler")
	list[1]:GetScript("OnEnter")(list[1])
	check(TOOLTIP.title == "B" and Has(TOOLTIP.lines, "C") and Has(TOOLTIP.lines, "Quest giver") and Has(TOOLTIP.lines, "Turn-in"),
		"its tooltip lists both")
	list[1]:GetScript("OnLeave")(list[1])
	-- Your arrow.
	PLAYER_POS[1], PLAYER_POS[2], FACING = 0.25, 0.5, 1.5
	m:Show(1429, {})
	local _, _, _, ax, ay = m.Me:GetPoint(1)
	check(m.Me:IsShown() and ax == m.Map:GetWidth() * 0.25 and m.Me.rotation == 1.5, "my arrow where I am, my facing")
	PLAYER_POS[1] = 0.75
	Advance(0.2)
	_, _, _, ax = m.Me:GetPoint(1)
	check(ax == m.Map:GetWidth() * 0.75, "it follows me while shown")
	m:ShowPlayer(false)
	check(not m.Me:IsShown(), "switched off: no arrow")
	m:ShowPlayer(true)
	FACING = 0
	-- Zoom: the wheel, a right-click; another map shows all of it.
	local whole = m.Map:GetWidth()
	m.frame:GetScript("OnMouseWheel")(m.frame, 1)
	check(m.zoom > 1 and math.abs(m.Map:GetWidth() - whole * 1.35) < 0.01 and m.Hint:GetText() == "right-click: whole zone",
		"the wheel zooms in")
	m.frame:GetScript("OnMouseDown")(m.frame, "RightButton")
	check(m.zoom == 1 and m.Map:GetWidth() == whole and m.Hint:GetText() == "wheel: zoom", "a right-click: the whole zone")
	m:Zoom(4)
	m:Show(1436, {})
	check(m.zoom == 1, "another map: the whole of it")
	m:Show(9999, { { x = 0.5, y = 0.5, kind = "end", label = "B" } })
	check(m.Empty:IsShown() and #m:Markers() == 1, "a map without art: says so, the marker on the dark box")
	m:Show(nil, {})
	check(m.Empty:IsShown() and #m:Markers() == 0 and not m.markers[1]:IsShown(), "no map: no markers")
	m:Hide()
	check(not m.frame:IsShown(), "hidden")
end

-- Put back what this file replaced (the stand-ins too: the real parts, once they're in the build,
-- keep theirs) and the mock's world.
for name in pairs(replaced) do PutBack(name) end
Small().win:Hide()
QUESTS, SUPER_TRACKED, PLAYER_MAP = savedQuests, savedSuper, savedMap
PLAYER_POS[1], PLAYER_POS[2] = savedPos[1], savedPos[2]
C_QuestLog.GetAllCompletedQuestIDs = savedCompleted
C_Map.SetUserWaypoint, C_Map.CanSetUserWaypointOnMap, C_Map.GetUserWaypointHyperlink =
	savedMapApi.SetUserWaypoint, savedMapApi.CanSetUserWaypointOnMap, savedMapApi.GetUserWaypointHyperlink
UiMapPoint, ChatFrameUtil, C_SuperTrack.SetSuperTrackedUserWaypoint = savedPoint, savedChat, savedSuperPin
if madeDetails then QuestMapFrame_ShowQuestDetails = nil end -- (the hook stays on the function, unreachable)
Progress()
Advance(1)
