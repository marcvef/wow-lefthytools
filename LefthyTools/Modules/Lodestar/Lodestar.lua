local _, ns = ...
local LT = ns.LT
local L = ns.L
local Q = ns.Lodestar or {}; ns.Lodestar = Q

-- Lodestar: quest chains for every zone of WoW: Forever. What a quest needs first, where it starts
-- and ends, what it leads to, and which friends have done it. The data is an add-on of its own
-- (LefthyTools_QuestData, load on demand), loaded the first time a Lodestar window opens, never at
-- login (Data.lua: Q.Load). The files share the table Q (ns.Lodestar), whatever order they load in:
--   Data.lua      loading the data, the accessors (Q.Quest, Q.Zones, Q.Search, Q.AddLearned, ...)
--   Engine.lua    my status for a quest, what it needs first, what it opens, what's next (Q.Status, ...)
--   Lodestar.lua this file: the module, its settings, /lodestar, what the windows share
--   MiniMap.lua   a zone's map with markers in a frame of ours (Q.NewMiniMap)
--   Small.lua     the small window, the companion: what I'm on now, what to pick up next, any quest
--                 (Q.ToggleSmall, Q.ShowQuest)
--   Browser.lua   the big window (Q.ToggleBrowser, Q.OpenBrowser)
--   Learn.lua     learning while playing (the setting learn)
--   Dialog.lua    in the game's quest UI: a panel beside the quest dialog, chain steps on the quest
--                 log's titles (settings dialog, logBadges)
-- This file also puts Lodestar's lines into NPC tooltips (setting tooltips) and lets the small
-- window follow the quest you open in your quest log (setting followLog), both post-hooks only.
-- docs/lodestar.md has each part. Nothing runs while no window is open: no data, no events, no
-- OnUpdate (the small window listens to the quest log only while it's shown); a tooltip's lines are
-- a table lookup.

-- The module was called Questtree in test builds (0.7.0-70 to -102): what it saved under that name
-- (on or off, its settings, what Learn.lua learned) goes over to Lodestar, before the modules read it.
table.insert(LT.onLoad, function(db)
	for _, t in ipairs({ db.modules, db.settings, db }) do
		if type(t) == "table" and t.questtree ~= nil then
			if t.lodestar == nil then
				t.lodestar = t.questtree
			end
			t.questtree = nil
		end
	end
end)

local M = LT:NewModule("lodestar", {
	title = "Lodestar",
	description = L["Quest chains for every zone: what a quest needs first, where it starts and ends, what it leads to and which friends have done it. /lodestar opens the small window."],
	defaults = {
		keepPlace = true, -- the small window opens where it was left, at its size
		followLog = true, -- the small window shows the quest opened in the quest log (or clicked in the tracker)
		tooltips = true,  -- "Lodestar: starts ..." in NPC tooltips
		itemTooltips = true, -- "Lodestar: for <quest> ..." in item tooltips, the sorted bags' mark (Items.lua)
		friends = true,   -- friends' progress (Beacon friends with LefthyTools; Learn.lua and QuestShare.lua)
		learn = true,     -- learning givers, turn-ins and prerequisites while playing (Learn.lua reads it)
		autoHide = true,  -- the companion hides itself when there's nothing to show, and comes back
		collapsed = false, -- the companion is one line (its title bar's button)
		stepsOpen = false, -- the companion shows the chain's steps (its "Steps (7)" line folds and unfolds them)
		dialog = true,    -- a panel beside the quest dialog: the chain, its steps, what it leads to (Dialog.lua)
		logBadges = true, -- "2/4" on the quest log's titles, the chain in their tooltip, Alt-click (Dialog.lua)
		small = {},       -- the small window: left, top, width, height (Small.lua)
		minimapButton = true,
		minimapAngle = 125, -- degrees, 0 = right, counter-clockwise: the upper left, above the Bestiary's
	},
})
Q.module = M

-- What each file does when Lodestar is switched on or off or a setting changes (Q.When "enable",
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

---------------------------------------------------------------------------
-- Difficulty colours, chain steps (for the windows and the tooltip lines)
---------------------------------------------------------------------------

-- The game's quest difficulty colours (QuestDifficultyColors), and blue for a repeatable quest.
Q.DIFFICULTY = {
	trivial = { 0.5, 0.5, 0.5 }, standard = { 0.25, 0.75, 0.25 }, difficult = { 1, 0.82, 0 },
	verydifficult = { 1, 0.5, 0.25 }, impossible = { 1, 0.1, 0.1 }, repeatable = { 0.25, 0.6, 1 },
}
local NATIVE_DIFFICULTY = { [0] = "trivial", [1] = "standard", [2] = "difficult", [3] = "verydifficult", [4] = "impossible" }

local function Hex(r, g, b)
	return ("|cff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- How hard a quest is for me: a key of Q.DIFFICULTY (nil: no level known) and its colour. Data.lua's
-- Q.LevelColor when it's there; else the game's own answer
-- (C_PlayerInfo.GetContentDifficultyQuestForPlayer) for a quest the client knows, else the level
-- difference as the game's quest log colours it: 5 or more above me impossible, 3 or more very
-- difficult, down to 4 below difficult, within UnitQuestTrivialLevelRange standard, else trivial.
function Q.DifficultyKey(id, quest, level)
	quest = quest or (id and Q.Quest and Q.Quest(id))
	if quest and quest.repeatable then
		return "repeatable"
	end
	level = tonumber(level or quest and quest.level)
	if Q.LevelColor and level and level > 0 then
		local ok, c = pcall(Q.LevelColor, level, id)
		if ok and type(c) == "table" and tonumber(c.r or c[1]) then
			return Q.DIFFICULTY[c.key] and c.key or "custom", c
		end
	end
	if id and C_PlayerInfo and C_PlayerInfo.GetContentDifficultyQuestForPlayer then
		local title = C_QuestLog and LT.Value(C_QuestLog.GetTitleForQuestID, id)
		if type(title) == "string" and title ~= "" then
			local native = NATIVE_DIFFICULTY[LT.Value(C_PlayerInfo.GetContentDifficultyQuestForPlayer, id)]
			if native then
				return native
			end
		end
	end
	if not level or level <= 0 then
		return nil
	end
	local me = tonumber(LT.Value(UnitLevel, "player")) or 1
	local diff = level - me
	if diff >= 5 then
		return "impossible"
	elseif diff >= 3 then
		return "verydifficult"
	elseif diff >= -4 then
		return "difficult"
	end
	local range = tonumber(LT.Value(UnitQuestTrivialLevelRange, "player"))
		or (me < 40 and 5 + math.floor(me / 10) or 1 + math.floor(me / 5))
	return -diff <= range and "standard" or "trivial"
end

-- "|cffRRGGBB" of a quest's difficulty for me (white without a level).
function Q.LevelCode(id, quest, level)
	local key, color = Q.DifficultyKey(id, quest, level)
	if color then
		return Hex(tonumber(color.r or color[1]) or 1, tonumber(color.g or color[2]) or 1, tonumber(color.b or color[3]) or 1)
	end
	local c = key and Q.DIFFICULTY[key]
	return c and Hex(c[1], c[2], c[3]) or "|cffffffff"
end

-- "[12] Title" in its difficulty colour, as the game's quest log writes it (no level: the title).
function Q.LevelTitle(id, quest)
	quest = quest or (Q.Quest and Q.Quest(id))
	local level = quest and tonumber(quest.level)
	local title = Q.Title(id, quest)
	if not level or level <= 0 then
		return Q.LevelCode(id, quest) .. title .. "|r"
	end
	return Q.LevelCode(id, quest) .. "[" .. level .. "] " .. title .. "|r"
end

-- Which step of its chain a quest is: step, total, the chain's name (its first quest's title);
-- nil when it's no chain's. Data.lua's Q.ChainStep when it's there, else its place in Q.Chain.
function Q.StepOf(id)
	if not id then
		return nil
	end
	if Q.ChainStep then
		local ok, step, total, name = pcall(Q.ChainStep, id)
		if ok and type(step) == "table" then
			step, total, name = step.step, step.total, step.chainTitle or step.title
		end
		step, total = ok and tonumber(step), ok and tonumber(total)
		if step and total and total > 1 then
			return step, total, type(name) == "string" and name or nil
		end
		return nil
	end
	local chain = Q.Chain and Q.Chain(id)
	if type(chain) ~= "table" or #chain < 2 then
		return nil
	end
	for i, other in ipairs(chain) do
		if other == id then
			return i, #chain, Q.Title(chain[1])
		end
	end
end

-- A quest's chain as I can do it: Q.Chain without the quests that aren't for me (the quest itself
-- stays), and where the quest is in it: list, at; nil when it's in no chain of two or more. These
-- are the steps the windows number ("Part 2 of 4", the quest log's "2/4"). Kept per data and
-- progress change.
local chainFor, chainForKey = {}, nil

function Q.ChainFor(id)
	id = tonumber(id)
	if not (id and Q.Chain) then
		return nil
	end
	Q.StatusOf(id) -- (the engine reads my progress first: a change there moves Q.progressGen)
	local key = tostring(Q.dataGen) .. ":" .. tostring(Q.progressGen)
	if key ~= chainForKey then
		chainFor, chainForKey = {}, key
	end
	local known = chainFor[id]
	if known == nil then
		known = false
		local chain = Q.Chain(id)
		if type(chain) == "table" and #chain >= 2 then
			local list, at = {}, nil
			for _, other in ipairs(chain) do
				if other == id or Q.StatusOf(other) ~= "other" then
					list[#list + 1] = other
					if other == id then
						at = #list
					end
				end
			end
			if at and #list >= 2 then
				known = { list = list, at = at }
			end
		end
		chainFor[id] = known
	end
	if known then
		return known.list, known.at
	end
	return nil
end

-- The colours the research found players know (docs/lodestar.md, Small window), as "|cff" codes:
-- done green, in progress gold, locked grey (always with a word or an icon too), what closes orange.
Q.COLOR = { done = "|cff5fba46", progress = "|cffd99b00", locked = "|cff737373", grey = "|cff9d9d9d",
	light = "|cffbebebe", gold = "|cffffd200", closes = "|cffff8040" }

-- Verb icons for a line: the game's own quest icons (atlases Forever has; else the gossip window's
-- files): "available" (!), "repeatable", "trivial" (the grey !), "level" (the ! dimmed: later),
-- "locked" (a lock), "turnin" (?), "progress" (in your log, not done), "done" (a tick), "here".
local ICONS = {
	available = { "QuestNormal", "Interface\\GossipFrame\\AvailableQuestIcon" },
	repeatable = { "QuestDaily", "Interface\\GossipFrame\\DailyQuestIcon" },
	trivial = { "TrivialQuests", "Interface\\GossipFrame\\AvailableQuestIcon" },
	level = { "QuestNormal", "Interface\\GossipFrame\\AvailableQuestIcon", "150:150:150" },
	locked = { "questlog-questtypeicon-lock", "Interface\\GossipFrame\\AvailableQuestIcon" },
	turnin = { "QuestTurnin", "Interface\\GossipFrame\\ActiveQuestIcon" },
	progress = { "SideInProgressquesticon", "Interface\\GossipFrame\\IncompleteQuestIcon" },
	done = { "UI-QuestTracker-Tracker-Check", "Interface\\RaidFrame\\ReadyCheck-Ready" },
	here = { nil, "Interface\\ChatFrame\\ChatFrameExpandArrow" },
}
local iconMarkup = {}

-- An icon's markup ("|A...|a" or "|T...|t"), size px (default 14); no space after it.
function Q.Icon(kind, size)
	size = size or 14
	local key = tostring(kind) .. ":" .. size
	local markup = iconMarkup[key]
	if not markup then
		local icon = ICONS[kind] or ICONS.available
		local atlas = icon[1] and C_Texture and C_Texture.GetAtlasInfo and LT.Value(C_Texture.GetAtlasInfo, icon[1])
		if atlas then
			markup = ("|A:%s:%d:%d%s|a"):format(icon[1], size, size, icon[3] and (":0:0:" .. icon[3]) or "")
		else
			markup = ("|T%s:%d:%d|t"):format(icon[2], size, size)
		end
		iconMarkup[key] = markup
	end
	return markup
end

-- A quest's verb icon for me, by its status (in my log: ready to turn in or not).
function Q.QuestIcon(id, status, size)
	status = status or Q.StatusOf(id)
	if status == "active" then
		return Q.Icon(C_QuestLog and LT.Value(C_QuestLog.IsComplete, id) == true and "turnin" or "progress", size)
	elseif status == "done" then
		return Q.Icon("done", size)
	elseif status == "available" then
		local quest = Q.Quest and Q.Quest(id)
		if quest and quest.repeatable then
			return Q.Icon("repeatable", size)
		end
		return Q.Icon(Q.DifficultyKey(id, quest) == "trivial" and "trivial" or "available", size)
	elseif status == "locked" then
		return Q.Icon("locked", size)
	end
	return Q.Icon("level", size)
end

-- What taking a quest closes (its exclusive ones: only one of them can be done) that isn't done or
-- closed already: a list of IDs.
function Q.Closes(id)
	local quest = Q.Quest and Q.Quest(id)
	local list = {}
	for _, other in ipairs(quest and quest.excl or {}) do
		local status = Q.StatusOf(other)
		if other ~= id and status ~= "done" and status ~= "other" then
			list[#list + 1] = other
		end
	end
	return list
end

-- A quest log objective's text as a pattern (the game's own formats: "%s slain: %d/%d", "%s: %d/%d";
-- positional ones too): the name captured. Made again only when the formats differ (they don't, in
-- the game).
local OBJECTIVE_FORMATS = { "QUEST_MONSTERS_KILLED", "QUEST_ITEMS_NEEDED", "QUEST_OBJECTS_FOUND" }
local objectivePatterns, objectiveFormats
local function ObjectivePatterns()
	local key = tostring(_G.QUEST_MONSTERS_KILLED) .. "\0" .. tostring(_G.QUEST_ITEMS_NEEDED) .. "\0" .. tostring(_G.QUEST_OBJECTS_FOUND)
	if objectivePatterns and key == objectiveFormats then
		return objectivePatterns
	end
	objectivePatterns, objectiveFormats = {}, key
	for _, name in ipairs(OBJECTIVE_FORMATS) do
		local format = _G[name]
		if type(format) == "string" and format:find("%%") then
			local p = format:gsub("%%%d*%$?s", "\1"):gsub("%%%d*%$?d", "\2")
			p = p:gsub("([%^%$%(%)%.%[%]%*%+%-%?%%])", "%%%1"):gsub("\1", "(.-)"):gsub("\2", "%%d+")
			objectivePatterns[#objectivePatterns + 1] = "^" .. p .. "$"
		end
	end
	return objectivePatterns
end

-- An objective's name without its count ("Defias Bandit slain: 3/10" -> "Defias Bandit").
local function ObjectiveName(text)
	for _, p in ipairs(ObjectivePatterns()) do
		local name = text:match(p)
		if name and name ~= "" then
			return name
		end
	end
	local name = text:gsub("%s*:?%s*%d+%s*/%s*%d+%s*$", ""):gsub("^%s*%d+%s*/%s*%d+%s*", "")
	return name ~= "" and name or text
end

local LOG_KIND = { monster = "kill", item = "item", object = "object" }

-- My quest's objectives from the quest log, each with what the data knows of it (Q.Objectives: the
-- n-th of a kind to the n-th of that kind, else by its name in the text, else by place when both
-- have as many): { { text, name, have, need, done, data } }, {} when it isn't in my log or has none.
-- name: the text without its count; have/need: the numbers (nil when it has none).
function Q.LogObjectives(id)
	local log = id and C_QuestLog and C_QuestLog.GetQuestObjectives and LT.Value(C_QuestLog.GetQuestObjectives, id)
	local out = {}
	if type(log) ~= "table" then
		return out
	end
	local data = Q.Objectives and Q.Objectives(id)
	data = type(data) == "table" and data or {}
	for _, o in ipairs(log) do
		if type(o) == "table" and type(o.text) == "string" and not LT.IsSecret(o.text) and o.text ~= "" then
			local have, need = tonumber(o.numFulfilled), tonumber(o.numRequired)
			if not (need and need > 0) then
				have, need = o.text:match("(%d+)%s*/%s*(%d+)")
				have, need = tonumber(have), tonumber(need)
			end
			out[#out + 1] = { text = o.text, name = ObjectiveName(o.text), have = have, need = need, done = o.finished == true,
				kind = LOG_KIND[o.type] }
		end
	end
	local used, seen = {}, {}
	for _, o in ipairs(out) do -- the n-th of a kind
		if o.kind then
			seen[o.kind] = (seen[o.kind] or 0) + 1
			local n = 0
			for i, d in ipairs(data) do
				if d.kind == o.kind then
					n = n + 1
					if n == seen[o.kind] and not used[i] then
						o.data, used[i] = d, true
					end
				end
			end
		end
	end
	for _, o in ipairs(out) do -- its name in the text
		local text = o.text:lower()
		for i, d in ipairs(data) do
			if not o.data and not used[i] and type(d.name) == "string" and d.name ~= "" and text:find(d.name:lower(), 1, true) then
				o.data, used[i] = d, true
			end
		end
	end
	if #out == #data then -- by place
		for i, o in ipairs(out) do
			if not o.data and not used[i] then
				o.data, used[i] = data[i], true
			end
		end
	end
	return out
end

-- Where to go for a quest's objective: the spot of an area of an objective not done yet (the data's,
-- Q.Objectives' sources' points) nearest my spot on map (else its first), and that objective. A quest
-- in my log takes its log's objectives (done ones left out); else the data's. nil: no place known.
function Q.ObjectiveSpot(id, map, x, y)
	local list = {}
	local logged = Q.LogObjectives(id)
	if logged[1] then
		for _, o in ipairs(logged) do
			if not o.done and o.data then
				list[#list + 1] = o
			end
		end
	else
		local data = Q.Objectives and Q.Objectives(id)
		for _, d in ipairs(type(data) == "table" and data or {}) do
			list[#list + 1] = { name = d.name, data = d }
		end
	end
	local best, bestO, bestD, first, firstO
	for _, o in ipairs(list) do
		local sources = o.data.sources or {}
		local point, _, d = Q.NearestPoint(sources, map, x, y)
		if point and (not bestD or (d or 0) < bestD) then
			best, bestO, bestD = point, o, d or 0
		end
		for _, source in ipairs(sources) do
			if not first and source.points and source.points[1] then
				first, firstO = source.points[1], o
			end
		end
	end
	if best then
		return best, bestO
	end
	return first, firstO
end

---------------------------------------------------------------------------
-- Where I am, how far a spot is, the game's map pin
---------------------------------------------------------------------------

-- My spot on a map (0..1; nil: not on it, or the game won't say, as in an instance).
function Q.PlayerAt(map)
	if not (map and C_Map and C_Map.GetPlayerMapPosition) then
		return nil
	end
	local pos = LT.Value(C_Map.GetPlayerMapPosition, map, "player")
	if type(pos) ~= "table" then
		return nil
	end
	local ok, x, y = pcall(pos.GetXY, pos)
	if not (ok and type(x) == "number" and type(y) == "number") or LT.IsSecret(x) or LT.IsSecret(y) then
		return nil
	end
	if x < 0 or x > 1 or y < 0 or y > 1 or (x == 0 and y == 0) then
		return nil
	end
	return x, y
end

-- The zone I'm in (a zone map, not a city's floor or a cave) and my spot on it.
function Q.HereZone()
	local map = C_Map and LT.Value(C_Map.GetBestMapForUnit, "player")
	if type(map) ~= "number" then
		return nil
	end
	local zone = map
	for _ = 1, 6 do
		local info = LT.Value(C_Map.GetMapInfo, zone)
		if type(info) ~= "table" or info.mapType == 3 then
			break
		end
		local parent = info.parentMapID
		if not parent or parent == 0 or (info.mapType and info.mapType < 3) then
			zone = map
			break
		end
		zone = parent
	end
	local x, y = Q.PlayerAt(zone)
	return zone, x, y
end

local DIRECTIONS = { L["N"], L["NE"], L["E"], L["SE"], L["S"], L["SW"], L["W"], L["NW"] }
local atan2 = math.atan2 or math.atan -- WoW's Lua 5.1 / the tests' Lua 5.3

local function World(map, x, y)
	if not (C_Map.GetWorldPosFromMapPos and CreateVector2D) then
		return nil
	end
	local ok, _, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
	if not ok or type(pos) ~= "table" or LT.IsSecret(pos) then
		return nil
	end
	local okXY, north, west = pcall(pos.GetXY, pos)
	if okXY and type(north) == "number" and type(west) == "number" then
		return north, west
	end
end

-- From (fx, fy) to (x, y) on a map: yards (nil: the game won't say) and the compass direction.
function Q.Toward(map, fx, fy, x, y)
	if not (map and fx and fy and x and y) then
		return nil
	end
	local n1, w1 = World(map, fx, fy)
	local n2, w2 = World(map, x, y)
	local north, east, yards
	if n1 and n2 then
		north, east = n2 - n1, w1 - w2
		yards = math.sqrt(north * north + east * east)
	else
		north, east = fy - y, (x - fx) * 1.5 -- (a zone's map is 3:2)
	end
	local angle = atan2(east, north) -- 0 north, clockwise
	return yards, DIRECTIONS[math.floor(angle / (math.pi / 4) + 0.5) % 8 + 1]
end

-- "170 yd SW", "right here"; nil without a spot.
function Q.TowardText(map, fx, fy, x, y)
	local yards, direction = Q.Toward(map, fx, fy, x, y)
	if not direction then
		return nil
	end
	if not yards then
		return direction
	elseif yards < 20 then
		return L["right here"]
	end
	return L["%d yd %s"]:format(yards < 100 and math.floor(yards / 5 + 0.5) * 5 or math.floor(yards / 10 + 0.5) * 10, direction)
end

-- The spot of a giver or turn-in on map nearest (x, y) (nil x: the first): the point, who, its
-- distance squared (in map units, 3:2).
function Q.NearestPoint(people, map, x, y)
	local best, bestWho, bestD
	for _, who in ipairs(people or {}) do
		for _, point in ipairs(who.points or {}) do
			if point.map == map then
				local d = x and ((point.x - x) * 1.5) ^ 2 + (point.y - y) ^ 2 or 0
				if not bestD or d < bestD then
					best, bestWho, bestD = point, who, d
				end
			end
		end
	end
	return best, bestWho, bestD
end

-- The quests I can take now in a zone, the nearest giver first when my spot is given: Data.lua's
-- Q.Available when it's there, else the zone's quests whose status is "available".
function Q.AvailableIn(map, x, y)
	if not map then
		return {}
	end
	if Q.Available then
		local ok, list = pcall(Q.Available, map, x, y)
		if ok and type(list) == "table" then
			local ids = {}
			for i, entry in ipairs(list) do
				ids[i] = type(entry) == "table" and entry.id or entry
			end
			return ids
		end
	end
	local list, far = {}, {}
	for _, id in ipairs(Q.ZoneQuests and Q.ZoneQuests(map) or {}) do
		if Q.StatusOf(id) == "available" then
			local quest = Q.Quest(id)
			local _, _, d = Q.NearestPoint(quest and quest.starts, map, x, y)
			list[#list + 1] = id
			far[id] = d or 99
		end
	end
	table.sort(list, function(a, b)
		if far[a] ~= far[b] then
			return far[a] < far[b]
		end
		return a < b
	end)
	return list
end

-- The game's own map pin at a spot, tracked (the arrow on screen and on the minimap; the world map
-- shows it when you open it): C_Map.SetUserWaypoint, never the world map's frames. share: its link
-- in the chat box too. true when it was set.
function Q.Waypoint(map, x, y, share)
	if not (map and x and y and C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
		return false
	end
	if C_Map.CanSetUserWaypointOnMap and LT.Value(C_Map.CanSetUserWaypointOnMap, map) ~= true then
		return false
	end
	local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(map, x, y))
	if not ok then
		return false
	end
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
		pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
	end
	local link = share and LT.Value(C_Map.GetUserWaypointHyperlink)
	if type(link) == "string" then
		local insert = ChatFrameUtil and ChatFrameUtil.InsertLink or ChatEdit_InsertLink
		if not (insert and LT.Value(insert, link)) and ChatFrameUtil and ChatFrameUtil.OpenChat then
			pcall(ChatFrameUtil.OpenChat, link)
		end
	end
	if PlaySound and SOUNDKIT and SOUNDKIT.UI_MAP_WAYPOINT_CONTROL_CLICK then
		pcall(PlaySound, SOUNDKIT.UI_MAP_WAYPOINT_CONTROL_CLICK)
	end
	return true
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

local function OpenBrowser()
	if Q.ToggleBrowser then
		Q.ToggleBrowser()
	else
		M:Print("the quest browser isn't there in this build.")
	end
end

-- The minimap button (Core/Window.lua's LT.Window.MinimapButton, as Chronicle's and the Bestiary's):
-- a star. Click: the quest browser; right-click: the companion. Its tooltip says what's here for you to
-- pick up within your levels (Q.InRange: not grey, red or an event's) once the quest data is loaded (a
-- hover never loads it).
local MINIMAP_ICON = "Interface\\Icons\\Spell_Arcane_StarFire"
local minimapButton

local function MinimapEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText("Lodestar", 1, 0.82, 0)
	local map = C_Map and C_Map.GetBestMapForUnit and tonumber(LT.Value(C_Map.GetBestMapForUnit, "player"))
	if map and Q.IsLoaded and Q.IsLoaded() and Q.Available then
		local okList, list = pcall(Q.Available, map)
		local name = C_Map.GetMapInfo and LT.Value(C_Map.GetMapInfo, map)
		if okList and type(list) == "table" and type(name) == "table" and type(name.name) == "string" then
			local n = 0
			for _, id in ipairs(list) do
				n = n + ((not Q.InRange or Q.InRange(id)) and 1 or 0)
			end
			GameTooltip:AddLine(L["%s: %d to pick up"]:format(name.name, n), 1, 1, 1)
		end
	end
	GameTooltip:AddLine(L["Click: the quest browser"], 0.8, 0.8, 0.8)
	GameTooltip:AddLine(L["Right-click: the companion"], 0.8, 0.8, 0.8)
	GameTooltip:AddLine(L["Drag: move it along the minimap"], 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

local function MinimapClick(_, mouseButton)
	if mouseButton == "RightButton" then
		Q.ToggleSmall()
	else
		OpenBrowser()
	end
end

-- After switching Lodestar on or off and the setting (on the next frame).
local function UpdateMinimapButton()
	local show = M.enabled and M.db and M.db.minimapButton and Minimap ~= nil
	if show and not minimapButton then
		minimapButton = LT.Window.MinimapButton("LefthyToolsLodestarMinimapButton", { icon = MINIMAP_ICON, db = M.db,
			angleKey = "minimapAngle", angle = 125, onClick = MinimapClick, onEnter = MinimapEnter })
	end
	if minimapButton then
		minimapButton:SetShown(show and true or false)
		if show then
			minimapButton:Place()
		end
	end
end

function Q.MinimapButton()
	return minimapButton
end

function M:OnEnable()
	Run("enable")
	C_Timer.After(0, UpdateMinimapButton)
end

function M:OnDisable()
	Run("disable")
	C_Timer.After(0, UpdateMinimapButton)
end

function M:OnSettingChanged()
	Run("settings")
	C_Timer.After(0, UpdateMinimapButton)
end

function M:BuildOptions(o)
	o:Header(L["Window"])
	o:Button(L["Open the small window"], L["Open"], function() Q.ToggleSmall() end,
		L["Your quest companion: the quest you're on with its chain and turn-in, and what to pick up next nearby, nearest first. It follows what you do. Also /lodestar, or /lodestar <name> for any quest."])
	o:Button(L["Open the quest browser"], L["Open"], OpenBrowser,
		L["Every zone's quest chains, with a search over all of them. Also /lodestar browse."])
	o:Checkbox("keepPlace", L["The small window keeps its place"],
		L["The small window opens where you left it, at the size you gave it. Off: it opens at its usual place and size."])
	o:Checkbox("followLog", L["Follow the quest log"],
		L["While the small window is open, a quest you open in your quest log (or click in the objective tracker) becomes the one it shows as now."])
	o:Checkbox("autoHide", L["The small window hides when there's nothing to do"],
		L["With no quest in your log and nothing to pick up nearby, the companion hides itself, and comes back when you take a quest or reach a zone with quests for you. Closed by you, it stays closed."])
	o:Checkbox("collapsed", L["The small window as one line"],
		L["The companion shrinks to its title and one line: the quest you're on, its step and how far its turn-in is. The button in its title bar does the same."])
	o:Header(L["In the game's quest UI"])
	o:Checkbox("dialog", L["Beside the quest dialog"],
		L["When an NPC offers you a quest, asks for it or rewards you, a panel beside the dialog shows its chain: which part this is, the steps around it, what it leads to, what taking it closes, friends who did it, and a button to open it in Lodestar. Hidden when there's nothing to tell."])
	o:Checkbox("logBadges", L["Chain steps in the quest log"],
		L["Each quest of a chain gets its step (\"2/4\") at the end of its line in your quest log, and its tooltip shows the chain. Alt-click a quest there to open it in Lodestar."])
	o:Checkbox("minimapButton", L["Minimap button"],
		L["A button on the edge of the minimap: click opens the quest browser, right-click the companion. Drag it to move it."])
	o:Header(L["Tooltips"])
	o:Checkbox("tooltips", L["Quest lines in NPC tooltips"],
		L["Pointing at someone who starts a quest you can take, or takes back one in your log, adds a line: \"Lodestar: starts ...\" with its step in the chain. For this the quest data loads a few seconds after the loading screen, never in a fight."])
	o:Checkbox("itemTooltips", L["Quest items in tooltips"],
		L["An item's tooltip says which quest it's for and where that quest stands: in your log with your progress, not taken yet, or done. When no quest needs it any more, it says you can discard it, and the sorted bags mark it."])
	o:Header(L["Friends"])
	o:Checkbox("friends", L["Friends' progress"],
		L["Which of your Beacon friends have done a quest, have it in their log or can take it. Needs Beacon, and friends with LefthyTools."])
	o:Header(L["Learning"])
	o:Checkbox("learn", L["Learn while questing"],
		L["Where the quest data has gaps, Lodestar notes quest givers, turn-ins and what a quest needed first while you play, and fills them in. Kept for all your characters."])
end

local function Help()
	M:Print("/lodestar - open or close the small window: the quest you're on, what to pick up next")
	M:Print("/lodestar <name or ID> - show a quest (a quest link works too)")
	M:Print("/lodestar browse - the quest browser: every zone's chains")
	M:Print("/lodestar minimap - show or hide the minimap button")
	M:Print("/lodestar settings - Lodestar's settings")
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
	elseif cmd == "minimap" then
		LT:SetModuleSetting(self, "minimapButton", not self.db.minimapButton)
		self:Print("minimap button " .. (self.db.minimapButton and "on." or "off."))
		return
	elseif not self.enabled then
		LT.Print("Lodestar is switched off (LefthyTools settings).")
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
			self:Print(("%d quests match \"%s\": showing %s. /lodestar browse to see them all."):format(count, text, Q.Title(id)))
			Q.ShowQuest(id)
		else
			Q.ShowQuest(id)
		end
	end
end

---------------------------------------------------------------------------
-- NPC tooltips: "Lodestar: starts <title> (step 2 of 5)"
---------------------------------------------------------------------------

-- A post-call on the game's unit tooltips (TooltipDataProcessor, as Chronicle's "Craftable by"),
-- GameTooltip only and its primary data, outside instances (there the data is secret), the NPC
-- from the data's GUID. Only once the quest data is loaded (below: a few seconds after the loading
-- screen, or when a Lodestar window opens), never loaded by a hover. An NPC's lines
-- are made once and kept until the data or my progress changes (Q.dataGen, Q.progressGen, the
-- quest log's size): a hover is a table lookup. Objects: the game's object tooltips carry no ID,
-- so they get nothing.
local TIP_MAX = 4
local START_ICON = "|TInterface\\GossipFrame\\AvailableQuestIcon:0|t "
local END_ICON = "|TInterface\\GossipFrame\\ActiveQuestIcon:0|t "
local tipLines, tipKey = {}, nil

-- The quests an NPC starts and ends, as two lists of IDs (Data.lua's Q.GiverQuests; nil: not there).
function Q.GiverLists(id, kind)
	if not Q.GiverQuests then
		return nil
	end
	local ok, a, b = pcall(Q.GiverQuests, id, kind)
	if not ok then
		return nil
	end
	if type(a) == "table" and (a.starts or a.ends) then
		a, b = a.starts, a.ends
	end
	local function Ids(list)
		local ids = {}
		for _, entry in ipairs(type(list) == "table" and list or {}) do
			local qid = type(entry) == "table" and entry.id or entry
			if type(qid) == "number" then
				ids[#ids + 1] = qid
			end
		end
		return ids
	end
	return Ids(a), Ids(b)
end

local function StepText(id)
	local step, total = Q.StepOf(id)
	return step and (" " .. L["(step %d of %d)"]:format(step, total)) or ""
end

-- The lines for an NPC: { { text, r, g, b }, ... } (an empty list: none).
local function TipLines(npc)
	local _, inLog = C_QuestLog.GetNumQuestLogEntries()
	local key = tostring(Q.dataGen) .. ":" .. tostring(Q.progressGen) .. ":" .. tostring(inLog)
	if key ~= tipKey then
		tipKey = key
		wipe(tipLines)
	end
	local lines = tipLines[npc]
	if lines then
		return lines
	end
	lines = {}
	local starts, ends = Q.GiverLists(npc)
	local more = 0
	local function Add(text, r, g, b)
		if #lines < TIP_MAX then
			lines[#lines + 1] = { text, r, g, b }
		else
			more = more + 1
		end
	end
	for _, id in ipairs(ends or {}) do
		if Q.StatusOf(id) == "active" then
			Add(END_ICON .. L["Lodestar: ends %s"]:format(Q.Title(id)), 1, 0.82, 0)
		end
	end
	for _, id in ipairs(starts or {}) do
		local status = Q.StatusOf(id)
		local quest = Q.Quest(id)
		if status == "available" then
			Add(START_ICON .. L["Lodestar: starts %s"]:format(Q.Title(id, quest)) .. StepText(id), 1, 0.82, 0)
		elseif status == "level" and quest and tonumber(quest.minLevel) then
			Add(START_ICON .. L["Lodestar: starts %s at level %d"]:format(Q.Title(id, quest), quest.minLevel), 0.6, 0.6, 0.6)
		end
	end
	if more > 0 then
		lines[#lines + 1] = { L["Lodestar: and %d more"]:format(more), 0.6, 0.6, 0.6 }
	end
	tipLines[npc] = lines
	return lines
end

-- The data for the tooltips (setting tooltips): loaded once, a few seconds after the loading screen,
-- out of a fight (in one: a few seconds after it), never at a hover; nothing when the data add-on
-- isn't installed (Q.HasData). Then Data.lua's NPC index is made a moment later, also not at a
-- hover. The frame stops listening once it's done.
local WARM_DELAY = 5
local warmer, warmed = nil, false

local function WarmNow()
	if warmed or not (M.enabled and (M.db.tooltips or M.db.itemTooltips)) then
		return
	end
	if LT.InCombat() then
		warmer:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	warmed = true
	warmer:UnregisterAllEvents()
	if Q.IsLoaded and not Q.IsLoaded() and Q.HasData and Q.HasData() then
		Q.Ready()
	end
	C_Timer.After(1, function()
		if Q.IsLoaded and Q.IsLoaded() and Q.GiverQuests and not LT.InCombat() then
			pcall(Q.GiverQuests, 0)
			if Q.ItemQuests and M.db.itemTooltips then
				pcall(Q.ItemQuests, 0) -- (the item index starts, made over the next frames: Items.lua)
			end
		end
	end)
end

local function Warm()
	if warmed or not warmer then
		return
	end
	C_Timer.After(WARM_DELAY, function() LT.Guard("Lodestar.warm", WarmNow) end)
end

warmer = CreateFrame("Frame")
warmer:RegisterEvent("PLAYER_ENTERING_WORLD")
warmer:SetScript("OnEvent", function(self, event)
	self:UnregisterEvent(event)
	Warm()
end)
Q.When("settings", Warm)
Q.When("enable", Warm)

local function OnUnitTooltip(tooltip, data)
	if tooltip ~= GameTooltip or not (M.enabled and M.db.tooltips) or (tooltip.IsForbidden and tooltip:IsForbidden()) then
		return
	end
	if type(data) ~= "table" or LT.IsSecret(data) or (IsInInstance and IsInInstance()) then
		return
	end
	if tooltip.GetPrimaryTooltipData and tooltip:GetPrimaryTooltipData() ~= data then
		return -- (an appended block: not the unit pointed at)
	end
	local npc = LT.CreatureOf(data.guid)
	if not npc then
		return
	end
	if not (Q.IsLoaded and Q.IsLoaded()) then
		return
	end
	for _, line in ipairs(TipLines(npc)) do
		tooltip:AddLine(line[1], line[2], line[3], line[4])
	end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
	and Enum.TooltipDataType.Unit then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
		LT.Guard("Lodestar.tooltip", OnUnitTooltip, tooltip, data)
	end)
end

---------------------------------------------------------------------------
-- The quest log: the small window follows the quest opened there
---------------------------------------------------------------------------

-- A post-hook on QuestMapFrame_ShowQuestDetails (a global function, as Misc Tweaks' quest markers
-- hook QuestLogQuests_Update): it runs when you open a quest's details in the quest log, and when
-- you click a quest in the objective tracker (which opens them). The hook only hands the quest's ID
-- to the small window (Q.SmallFollow), which notes it and, while it's shown, redraws a moment later
-- in its own code. Nothing of the quest log's frames is touched or read.
local logHooked = false

function Q.HookQuestLog()
	if logHooked or type(QuestMapFrame_ShowQuestDetails) ~= "function" then
		return
	end
	logHooked = true
	hooksecurefunc("QuestMapFrame_ShowQuestDetails", function(questID)
		if not (M.enabled and type(questID) == "number") or LT.IsSecret(questID) then
			return
		end
		if M.db.followLog and Q.SmallFollow then
			LT.Guard("Lodestar.log", Q.SmallFollow, questID)
		end
		-- Alt-click: Dialog.lua opens it in Lodestar on the next frame, in its own code.
		if Q.LogAltClick and IsAltKeyDown and IsAltKeyDown() then
			LT.Guard("Lodestar.logclick", Q.LogAltClick, questID)
		end
	end)
end

Q.When("enable", Q.HookQuestLog)

SLASH_LEFTHYTOOLS_LODESTAR1 = "/lodestar"
SlashCmdList.LEFTHYTOOLS_LODESTAR = function(msg)
	M:OnSlashCommand(msg)
end
