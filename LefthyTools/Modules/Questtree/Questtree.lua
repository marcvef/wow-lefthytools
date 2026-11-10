local _, ns = ...
local LT = ns.LT
local L = ns.L
local Q = ns.Questtree or {}; ns.Questtree = Q

-- Questtree: quest chains for every zone of WoW: Forever. What a quest needs first, where it starts
-- and ends, what it leads to, and which friends have done it. The data is an add-on of its own
-- (LefthyTools_QuestData, load on demand), loaded the first time a Questtree window opens, never at
-- login (Data.lua: Q.Load). The files share the table Q (ns.Questtree), whatever order they load in:
--   Data.lua      loading the data, the accessors (Q.Quest, Q.Zones, Q.Search, Q.AddLearned, ...)
--   Engine.lua    my status for a quest, what it needs first, what it opens, what's next (Q.Status, ...)
--   Questtree.lua this file: the module, its settings, /questtree, what the windows share
--   MiniMap.lua   a zone's map with markers in a frame of ours (Q.NewMiniMap)
--   Small.lua     the small window: one quest (Q.ShowQuest, Q.ToggleSmall)
--   Browser.lua   the big window (Q.ToggleBrowser, Q.OpenBrowser)
--   Learn.lua     learning while playing (the setting learn)
-- docs/questtree.md has each part. Nothing runs while no window is open: no data, no events, no
-- OnUpdate (the small window listens to the quest log only while it's shown).

local M = LT:NewModule("questtree", {
	title = "Questtree",
	description = L["Quest chains for every zone: what a quest needs first, where it starts and ends, what it leads to and which friends have done it. /questtree opens the small window."],
	defaults = {
		keepPlace = true, -- the small window opens where it was left, at its size
		friends = true,   -- friends' progress (Beacon friends with LefthyTools; Learn.lua and QuestShare.lua)
		learn = true,     -- learning givers, turn-ins and prerequisites while playing (Learn.lua reads it)
		small = {},       -- the small window: left, top, width, height (Small.lua)
	},
})
Q.module = M

-- What each file does when Questtree is switched on or off or a setting changes (Q.When "enable",
-- "disable", "settings").
local hooks = { enable = {}, disable = {}, settings = {} }

function Q.When(what, fn)
	table.insert(hooks[what], fn)
end

local function Run(what)
	for _, fn in ipairs(hooks[what]) do
		local ok, err = pcall(fn)
		if not ok then
			geterrorhandler()(err)
		end
	end
end

---------------------------------------------------------------------------
-- What the windows share
---------------------------------------------------------------------------

-- The data is there (loads it the first time: only call this when a window opens or is shown).
-- false when Data.lua or the data add-on isn't there.
function Q.Ready()
	return type(Q.Load) == "function" and Q.Load() == true
end

-- A quest's title: the client's (in its language) when it answers, else the data's (English), else
-- its number.
function Q.Title(id, quest)
	local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and LT.Value(C_QuestLog.GetTitleForQuestID, id)
	if type(title) == "string" and title ~= "" then
		return title
	end
	quest = quest or (Q.Quest and Q.Quest(id))
	if quest and type(quest.title) == "string" and quest.title ~= "" then
		return quest.title
	end
	return L["Quest %d"]:format(id or 0)
end

-- My status for a quest (Engine.lua's; "other" when it isn't there).
function Q.StatusOf(id, who)
	return Q.Status and Q.Status(id, who) or "other"
end

-- Each status's colour, its line in the window (mine) and its word after a quest's name (mine, and
-- a friend's).
Q.STATUS = {
	done = { 0.35, 0.85, 0.35, L["You've done it"], L["done"], L["done"] },
	active = { 1, 0.82, 0, L["In your quest log"], L["in your log"], L["on it"] },
	available = { 0.45, 0.8, 1, L["You can take it"], L["ready to take"], L["can take it"] },
	locked = { 1, 0.55, 0.2, L["Needs another quest first"], L["needs one first"], L["not yet"] },
	level = { 0.95, 0.35, 0.35, L["Your level is too low"], L["level too low"], L["level too low"] },
	other = { 0.6, 0.6, 0.6, L["Not for this character"], L["not for you"], L["not for them"] },
}

local function Status(status)
	return Q.STATUS[status] or Q.STATUS.other
end

-- "|cffRRGGBB" for a status.
function Q.StatusCode(status)
	local s = Status(status)
	return ("|cff%02x%02x%02x"):format(math.floor(s[1] * 255 + 0.5), math.floor(s[2] * 255 + 0.5), math.floor(s[3] * 255 + 0.5))
end

-- The status in words, coloured: "line" (the window's), "word" (after a quest's name) or "friend".
function Q.StatusText(status, kind)
	local s = Status(status)
	local text = kind == "friend" and s[6] or kind == "word" and s[5] or s[4]
	return Q.StatusCode(status) .. text .. "|r"
end

-- "Level 12" or "Level 12 (from 10)"; nil without a level.
function Q.LevelText(quest)
	local level, from = quest and tonumber(quest.level), quest and tonumber(quest.minLevel)
	if not level or level <= 0 then
		return nil
	end
	if from and from > 0 and from ~= level then
		return L["Level %d (from %d)"]:format(level, from)
	end
	return L["Level %d"]:format(level)
end

-- A map's name (nil: the game doesn't know it).
function Q.MapName(map)
	local info = map and C_Map and C_Map.GetMapInfo and LT.Value(C_Map.GetMapInfo, map)
	local name = type(info) == "table" and info.name
	return not LT.IsSecret(name) and type(name) == "string" and name ~= "" and name or nil
end

-- What a typed text means: a quest's number, a quest link's, or the best of Q.Search's quests (the
-- title just that, then one starting with it, then one containing it or its giver's name; among
-- those: in your log, ready to take, then the others, nearest your level). Returns the id (nil:
-- none) and how many matched.
local ORDER = { active = 1, available = 2, locked = 3, level = 4, done = 5, other = 6 }

function Q.Find(text)
	text = strtrim(text or "")
	local id = tonumber(text:match("|Hquest:(%d+)") or text:match("^#?(%d+)$"))
	if id then
		return id, 1
	end
	if text == "" or not Q.Search then
		return nil, 0
	end
	local found = Q.Search(text) or {}
	local want = text:lower()
	local me = UnitLevel and LT.Value(UnitLevel, "player") or 1
	local best, bestKey
	for _, qid in ipairs(found) do
		local quest = Q.Quest and Q.Quest(qid)
		local titles = { Q.Title(qid, quest):lower(), quest and type(quest.title) == "string" and quest.title:lower() or "" }
		local match = 3
		for _, title in ipairs(titles) do
			if title == want then
				match = 1
			elseif match > 2 and title:sub(1, #want) == want then
				match = 2
			end
		end
		local level = quest and tonumber(quest.level) or me
		local key = { match, ORDER[Q.StatusOf(qid)] or 6, math.abs(level - me), qid }
		local better = not bestKey
		for i = 1, bestKey and #key or 0 do
			if key[i] ~= bestKey[i] then
				better = key[i] < bestKey[i]
				break
			end
		end
		if better then
			best, bestKey = qid, key
		end
	end
	return best, #found
end

---------------------------------------------------------------------------
-- The module
---------------------------------------------------------------------------

function M:OnEnable()
	Run("enable")
end

function M:OnDisable()
	Run("disable")
end

function M:OnSettingChanged()
	Run("settings")
end

local function OpenBrowser()
	if Q.ToggleBrowser then
		Q.ToggleBrowser()
	else
		M:Print("the quest browser isn't there in this build.")
	end
end

function M:BuildOptions(o)
	o:Header(L["Window"])
	o:Button(L["Open the small window"], L["Open"], function() Q.ToggleSmall() end,
		L["One quest at a time: what it needs first, where it starts and ends, what it leads to. Opened on its own it shows what's next for you. Also /questtree, or /questtree <name> for a quest."])
	o:Button(L["Open the quest browser"], L["Open"], OpenBrowser,
		L["Every zone's quest chains, with a search over all of them. Also /questtree browse."])
	o:Checkbox("keepPlace", L["The small window keeps its place"],
		L["The small window opens where you left it, at the size you gave it. Off: it opens at its usual place and size."])
	o:Header(L["Friends"])
	o:Checkbox("friends", L["Friends' progress"],
		L["Which of your Beacon friends have done a quest, have it in their log or can take it. Needs Beacon, and friends with LefthyTools."])
	o:Header(L["Learning"])
	o:Checkbox("learn", L["Learn while questing"],
		L["Where the quest data has gaps, Questtree notes quest givers, turn-ins and what a quest needed first while you play, and fills them in. Kept for all your characters."])
end

local function Help()
	M:Print("/questtree - open or close the small window (what's next for you)")
	M:Print("/questtree <name or ID> - show a quest (a quest link works too)")
	M:Print("/questtree browse - the quest browser: every zone's chains")
	M:Print("/questtree settings - Questtree's settings")
end

function M:OnSlashCommand(msg)
	local text = strtrim(msg or "")
	local cmd = text:lower()
	if cmd == "settings" or cmd == "options" then
		LT:OpenSettings(self)
		return
	elseif cmd == "help" or cmd == "?" then
		Help()
		return
	elseif not self.enabled then
		LT.Print("Questtree is switched off (LefthyTools settings).")
		return
	end
	if cmd == "" then
		Q.ToggleSmall()
	elseif cmd == "browse" or cmd == "browser" then
		OpenBrowser()
	elseif not Q.Ready() then
		Q.ShowQuest(nil) -- (the window says the data isn't there)
	else
		local id, count = Q.Find(text)
		if not id then
			self:Print(("no quest matches \"%s\"."):format(text))
		elseif count > 1 then
			self:Print(("%d quests match \"%s\": showing %s. /questtree browse to see them all."):format(count, text, Q.Title(id)))
			Q.ShowQuest(id)
		else
			Q.ShowQuest(id)
		end
	end
end

SLASH_LEFTHYTOOLS_QUESTTREE1 = "/questtree"
SlashCmdList.LEFTHYTOOLS_QUESTTREE = function(msg)
	M:OnSlashCommand(msg)
end
