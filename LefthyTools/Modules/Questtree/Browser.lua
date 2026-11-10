local _, ns = ...
local LT = ns.LT
local L = ns.L
local Q = ns.Questtree or {}
ns.Questtree = Q

-- Questtree's big window (Q.ToggleBrowser, Q.OpenBrowser(id)): every zone's quest chains. Near full
-- screen (1320 x 800, scaled down to fit a smaller screen), movable, Escape closes it. On top a search
-- across all zones and three filters (hide done, only what I can take now, show what isn't for me);
-- under it three panes:
--   * left: the zones by continent (each continent folds), each with its level range, how many of its
--     quests I've done (Q.ZoneCount: every quest for me, any level) and a thin progress bar; then the
--     dungeons;
--   * middle: the zone in three views (tabs):
--       - Chains: each chain under a banner (its name, done of total with a bar, what's next), its
--         quests as cards from top to bottom, a row per stage (how many quests come before it), the
--         quests of a stage side by side and centred; lines from each quest down to what it leads to
--         (three straight segments; green between done ones, amber from a done or ready one, grey);
--         "OR" between quests of which one is enough. A card: the status strip on its left, the start
--         (the quest giver's "!", the item's icon, an object), the title, the level in its difficulty
--         colour and the giver or the zone, a check when done, friends who've done it;
--       - Overview: the zone's quests grouped: in progress, available now, coming up (level), blocked
--         (needs another first), done;
--       - Map: the zone's map art with every quest giver as a marker in its status (available now a
--         bright "!", turn-ins of what's in my log a "?", later ones grey, done ones a dim dot) and
--         where items that start a quest drop; zoom with the wheel, drag to move; a click on a marker
--         shows its quest;
--   * right: the quest picked: its title in its difficulty colour, status, level, chain step, who gives
--     it and where (an item: what drops it and how often), a click on a place puts a map pin there,
--     the small map, requirements, "Needs first" and "Leads to" (buttons to those quests), friends,
--     and a button that shows it in the small window (Q.ShowQuest).
-- A search (Q.Search: titles and giver names, across all zones) shows its results in the middle; a
-- click on a result or a zone goes there with "Back to the search results" on top, and the search
-- stays until the box is emptied. A click on a quest also shows it in the small window while that's
-- open (Q.IsSmallShown).
--
-- What it costs: built when first opened; the data addon loads then too (Q.Load), never at login. The
-- chains are a canvas of our own: only the cards, lines and banners near sight exist (pooled, each
-- card kept on its quest while it stays near, so a controller's cursor stays on it), laid again only
-- when the view moves a good bit. A zone's chains are worked out once (Q.Chain, Q.Opens) and kept
-- until the data changes; the cards' places when the filters, the folding or a status change. Events
-- (QUEST_TURNED_IN, QUEST_ACCEPTED, QUEST_REMOVED, PLAYER_LEVEL_UP, QUEST_DATA_LOAD_RESULT) only while
-- it's open; they note what changed and the redraw comes on the next frame, at most every half second.
-- Closed, nothing runs. Our own frames only, nothing protected (it opens in a fight), no Blizzard menu
-- (gamepad mode), every card, marker, row, tab and filter a plain Button the controller's navigation
-- reaches; a card the cursor moves to out of sight brings itself into view.

local WIDTH, HEIGHT = 1320, 800
local SCREEN_W, SCREEN_H = 40, 80 -- kept free around it on a small screen
local INSET_W, INSET_H = 10, 86   -- how much smaller than the window the template's Inset is
local PAD, GAP, EDGE = 6, 8, 10
local ZONES_W, DETAILS_W = 250, 350 -- (each with its scroll bar)
local BAR_W = 24
local ROW_H = 20
local HEAD_H, TABS_H, LEGEND_H = 24, 28, 22
local BEYOND = 2                  -- list rows laid beyond sight, above and below (the controller's next one)
local LINK_H = 18
local SHOWN = { links = 12, friends = 12, places = 3, drops = 3, points = 20 }
local SEARCH_GAP, REFRESH_GAP, NAMES_GAP = 0.3, 0.5, 0.2
local GOLD, GREY = "|cffffd200", "|cff888888"
local EMPTY = {}

-- The chains' canvas: cards, gaps, banners (canvas units, before the zoom).
local G = {
	W = 170, H = 48, HGAP = 14, VGAP = 30, DUMMY = 22, LINE = 2, ICON = 32,
	BANNER = 56, BANNER_GAP = 16, GROUP_GAP = 26,
	MARGIN = 190,                  -- laid beyond sight (the controller's next card)
	ZOOM_MIN = 0.5, ZOOM_MAX = 1, ZOOM_STEP = 0.1,
	MAP_MIN = 1, MAP_MAX = 8, MAP_STEP = 1.35,
}
G.PY = G.H + G.VGAP

-- Textures and atlases (an atlas only where the client has it, else the file).
local T = {
	lock = "Interface\\LFGFrame\\UI-LFG-ICON-LOCK",
	plus = "Interface\\Buttons\\UI-PlusButton-Up", minus = "Interface\\Buttons\\UI-MinusButton-Up",
	back = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up",
	highlight = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
	flat = "Interface\\ChatFrame\\ChatFrameBackground",
	circle = "Interface\\CharacterFrame\\TempPortraitAlphaMask",
	available = "Interface\\GossipFrame\\AvailableQuestIcon",
	turnin = "Interface\\GossipFrame\\ActiveQuestIcon",
	object = "Interface\\Icons\\INV_Misc_Note_01",
	item = "Interface\\Icons\\INV_Misc_Bag_10",
	check = "Interface\\RaidFrame\\ReadyCheck-Ready",
	box = "Interface\\Buttons\\UI-CheckBox-Up", tick = "Interface\\Buttons\\UI-CheckBox-Check",
}

-- The window's status colours (Attune's tones: done green, ready amber, the rest grey).
local TONE = {
	done = { 0.37, 0.73, 0.28 }, active = { 0.35, 0.65, 1 }, available = { 0.85, 0.61, 0 },
	locked = { 0.55, 0.55, 0.55 }, level = { 0.9, 0.45, 0.25 }, other = { 0.4, 0.4, 0.4 },
}
local STATUS_ORDER = { "active", "available", "level", "locked", "done", "other" }
local HEX = {}
local function Hex(r, g, b)
	return ("|cff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end
for key, c in pairs(TONE) do
	HEX[key] = Hex(c[1], c[2], c[3])
end

-- Classic's races and classes by ID (a quest's masks: bit ID - 1); the game's names when it has them.
local RACES = { "Human", "Orc", "Dwarf", "Night Elf", "Undead", "Tauren", "Gnome", "Troll" }
local SIDES = { { 77, "Alliance" }, { 178, "Horde" } } -- the classic races of each side, as a mask
local CLASSES = { [1] = "WARRIOR", [2] = "PALADIN", [3] = "HUNTER", [4] = "ROGUE", [5] = "PRIEST", [7] = "SHAMAN", [8] = "MAGE",
	[9] = "WARLOCK", [11] = "DRUID" }
local SKILLS = { [129] = "First Aid", [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy", [182] = "Herbalism",
	[185] = "Cooking", [186] = "Mining", [197] = "Tailoring", [202] = "Engineering", [333] = "Enchanting", [356] = "Fishing", [393] = "Skinning" }
local STANDINGS = { { -42000, "Hated" }, { -6000, "Hostile" }, { -3000, "Unfriendly" }, { 0, "Neutral" }, { 3000, "Friendly" },
	{ 9000, "Honored" }, { 21000, "Revered" }, { 42000, "Exalted" } }
-- Blizzard's quest difficulty colours: trivial, standard, difficult, very difficult, impossible.
local DIFFICULTY = { [0] = { 0.5, 0.5, 0.5 }, { 0.25, 0.75, 0.25 }, { 1, 0.82, 0 }, { 1, 0.5, 0.25 }, { 1, 0.1, 0.1 } }
local REPEATABLE = { 0.1, 0.6, 1 }

local frame, view
local filters = { hideDone = false, onlyAvailable = false, showOther = false }
local state = {
	where = nil,      -- the place shown: "z:<uiMapID>" or "d:<dungeon>"
	picked = nil,     -- the quest in the details
	tab = "chains",   -- "chains" | "overview" | "map"
	query = "",       -- the search shown
	results = nil,    -- its quest IDs
	drilled = false,  -- a zone or quest clicked during a search: it shows, the search stays
	folded = {},      -- group or continent key -> true (the overview's done bucket starts folded)
	counts = {},      -- place -> { done, total }
	trees = {},       -- place -> its chains
	layouts = {},     -- place -> the cards' places (for the filters and statuses of now)
	zones = nil, dungeons = nil, places = nil,
	asked = {}, waiting = {}, -- titles asked of the client (QUEST_DATA_LOAD_RESULT)
	turn = {},        -- a map marker clicked again: its next quest
	dataOld = false, statusOld = false, nextRefresh = 0, searchAt = nil, namesAt = nil,
	listening = false,
	draws = 0, trees_built = 0, layouts_built = 0, -- (for the tests)
}
local Graph, Map, Overview, Details = {}, {}, {}, {}

---------------------------------------------------------------------------
-- What's shown of a quest
---------------------------------------------------------------------------

local function Quest(id)
	return id and Q.Quest and Q.Quest(id) or nil
end

local function StatusOf(id)
	local status = Q.Status and Q.Status(id)
	return TONE[status] and status or "other"
end

local function Word(status)
	if status == "done" then
		return L["Completed"]
	elseif status == "active" then
		return L["In your quest log"]
	elseif status == "available" then
		return L["Available"]
	elseif status == "locked" then
		return L["Locked"]
	elseif status == "level" then
		return L["Level too low"]
	end
	return L["Not for you"]
end

-- Shown with the filters as they are.
local function Visible(status)
	if status == "other" and not filters.showOther then
		return false
	elseif status == "done" and filters.hideDone then
		return false
	elseif filters.onlyAvailable and status ~= "available" then
		return false
	end
	return true
end

-- An atlas when the client has it, else the file.
local atlasKnown = {}
local function Art(texture, atlas, file)
	if atlas and atlasKnown[atlas] == nil then
		atlasKnown[atlas] = (C_Texture and LT.Value(C_Texture.GetAtlasInfo, atlas)) and true or false
	end
	if atlas and atlasKnown[atlas] then
		texture:SetAtlas(atlas)
	else
		texture:SetTexture(file)
		texture:SetTexCoord(0, 1, 0, 1)
	end
end

-- The client's title, when it knows the quest (asked once, it may come later); else the data's.
local function Ask(id)
	if state.asked[id] or not (C_QuestLog and C_QuestLog.RequestLoadQuestByID) then
		return
	end
	state.asked[id], state.waiting[id] = true, true
	pcall(C_QuestLog.RequestLoadQuestByID, id)
end

local function ClientTitle(id)
	local title = C_QuestLog and LT.Value(C_QuestLog.GetTitleForQuestID, id)
	return type(title) == "string" and title ~= "" and title or nil
end

local function Title(id)
	local title = ClientTitle(id)
	if title then
		return title
	end
	Ask(id)
	local q = Quest(id)
	return q and q.title or ("#" .. tostring(id))
end

-- What Q.LevelColor answers (a colour table, three numbers or a colour code), as r, g, b.
local function Rgb(a, b, c)
	if type(a) == "table" then
		local r, g, bb = tonumber(a.r or a[1]), tonumber(a.g or a[2]), tonumber(a.b or a[3])
		if r and g and bb then
			return r, g, bb
		end
	elseif type(a) == "number" and type(b) == "number" and type(c) == "number" then
		return a, b, c
	elseif type(a) == "string" then
		local r, g, bb = a:match("|c%x%x(%x%x)(%x%x)(%x%x)")
		if r then
			return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(bb, 16) / 255
		end
	end
end

-- A quest's level in Blizzard's difficulty colours (as Forever's own quest log shows "[12] Title"):
-- Q.LevelColor (Data.lua: the game's answer where it has one), else the game's for a quest it knows,
-- else the level against mine;
-- repeatable ones blue.
local function LevelRgb(q)
	local level = q and tonumber(q.level)
	if not level or level <= 0 then
		return 1, 1, 1
	elseif q.repeatable then
		return REPEATABLE[1], REPEATABLE[2], REPEATABLE[3]
	end
	if Q.LevelColor then
		local ok, a, b, c = pcall(Q.LevelColor, level, q.id)
		local r, g, bb = Rgb(ok and a, b, c)
		if r then
			return r, g, bb
		end
	end
	if q.id and ClientTitle(q.id) and C_PlayerInfo and C_PlayerInfo.GetContentDifficultyQuestForPlayer then
		local d = DIFFICULTY[LT.Value(C_PlayerInfo.GetContentDifficultyQuestForPlayer, q.id)]
		if d then
			return d[1], d[2], d[3]
		end
	end
	local my = tonumber(UnitLevel and LT.Value(UnitLevel, "player")) or 1
	local diff = level - my
	local n
	if diff >= 5 then
		n = 4
	elseif diff >= 3 then
		n = 3
	elseif diff >= -4 then
		n = 2
	else
		local range = UnitQuestTrivialLevelRange and tonumber(LT.Value(UnitQuestTrivialLevelRange, "player"))
		if not range then -- (classic's GetQuestGreenRange)
			range = my <= 5 and 5 or my <= 39 and math.floor(my / 10) + 5 or my <= 59 and math.floor(my / 5) + 1 or 9
		end
		n = -diff <= range and 1 or 0
	end
	local d = DIFFICULTY[n]
	return d[1], d[2], d[3]
end

local function LevelCode(q)
	return Hex(LevelRgb(q))
end

-- "[12] " in its difficulty colour ("" without a level).
local function LevelTag(q)
	if not (q and tonumber(q.level) and q.level > 0) then
		return ""
	end
	return LevelCode(q) .. "[" .. q.level .. "]|r "
end

local function MapName(map)
	local place = map and state.places and state.places["z:" .. tostring(map)]
	if place then
		return place.name
	end
	local info = map and C_Map and LT.Value(C_Map.GetMapInfo, map)
	return type(info) == "table" and type(info.name) == "string" and info.name or nil
end

local function ZoneOf(q)
	return q.dungeon or MapName(q.zone) or q.zoneName
end

-- Which step of its chain a quest is: step, total, the chain's name (Q.ChainStep, else from Q.Chain).
local function StepOf(id)
	if Q.ChainStep then
		local ok, step, total, name = pcall(Q.ChainStep, id)
		if ok and tonumber(step) and tonumber(total) then
			return step, total, name
		end
	end
	local chain = Q.Chain and Q.Chain(id)
	if type(chain) == "table" and #chain > 1 then
		for i, c in ipairs(chain) do
			if c == id then
				return i, #chain, Title(chain[1])
			end
		end
	end
end

local function FirstStart(q)
	return q and q.starts and q.starts[1] or nil
end

-- The card's start: the giver's "!" (bright when I can take it), an item's icon, an object.
local function StartIcon(texture, q, status)
	local s = FirstStart(q)
	texture:SetDesaturated(false)
	texture:SetVertexColor(1, 1, 1)
	if s and s.kind == "item" then
		local icon = C_Item and LT.Value(C_Item.GetItemIconByID, s.id)
		texture:SetTexture(icon or T.item)
		texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	elseif s and s.kind == "object" then
		texture:SetTexture(T.object)
		texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	elseif status == "active" then
		Art(texture, "SideInProgressquesticon", T.turnin)
	else
		Art(texture, q and q.repeatable and "QuestDaily" or "QuestNormal", T.available)
		texture:SetDesaturated(status ~= "available")
	end
	if status == "other" or status == "locked" or status == "level" then
		texture:SetDesaturated(true)
	end
end

local function StartWord(s)
	if s.kind == "object" then
		return L["%s (an object)"]:format(s.name or "?")
	elseif s.kind == "item" then
		return L["%s (an item)"]:format(s.name or "?")
	end
	return s.name or ("#" .. tostring(s.id))
end

-- "12%" or "0.5%".
local function Chance(c)
	c = tonumber(c)
	if not c then
		return "?"
	elseif c >= 10 then
		return tostring(math.floor(c + 0.5))
	end
	return (("%.1f"):format(c):gsub("%.0$", ""))
end

---------------------------------------------------------------------------
-- Places: zones and dungeons, their counts and chains
---------------------------------------------------------------------------

local function ContinentName(id)
	local info = id and C_Map and LT.Value(C_Map.GetMapInfo, id)
	return type(info) == "table" and type(info.name) == "string" and info.name or L["Other zones"]
end

local function Lists()
	if state.places then
		return
	end
	state.zones = Q.Zones and Q.Zones() or {}
	state.dungeons = Q.Dungeons and Q.Dungeons() or {}
	state.places = {}
	for _, z in ipairs(state.zones) do
		local id = "z:" .. tostring(z.map)
		state.places[id] = { id = id, kind = "zone", map = z.map, name = z.name or MapName(z.map) or "?", continent = z.continent,
			minLevel = z.minLevel, maxLevel = z.maxLevel }
	end
	for _, dungeon in ipairs(state.dungeons) do
		local id = "d:" .. tostring(dungeon.name)
		state.places[id] = { id = id, kind = "dungeon", name = dungeon.name, minLevel = dungeon.minLevel, maxLevel = dungeon.maxLevel }
	end
end

local function QuestsOf(place)
	local list
	if place.kind == "zone" then
		list = Q.ZoneQuests and Q.ZoneQuests(place.map)
	else
		list = Q.DungeonQuests and Q.DungeonQuests(place.name)
	end
	return list or EMPTY
end

-- What a place's views show: its quests and, for a zone, those given there but listed elsewhere
-- (Q.ZoneGiven: the Deadmines' quests at Sentinel Hill), worked out once with its chains.
local function PlaceQuests(place)
	local given = place.kind == "zone" and Q.ZoneGiven and Q.ZoneGiven(place.map)
	if type(given) ~= "table" or not given[1] then
		return QuestsOf(place)
	end
	local list, seen = {}, {}
	for _, l in ipairs({ QuestsOf(place), given }) do
		for _, id in ipairs(l) do
			if not seen[id] then
				seen[id] = true
				list[#list + 1] = id
			end
		end
	end
	return list
end

-- How many of a place's quests are done, of those for me (any level): Q.ZoneCount (a zone's map or a
-- dungeon's name), else counted here.
local function CountOf(place)
	local c = state.counts[place.id]
	if not c then
		local done, total
		if Q.ZoneCount then
			local ok, d, t = pcall(Q.ZoneCount, place.kind == "zone" and place.map or place.name)
			if ok and type(d) == "number" and type(t) == "number" then
				done, total = d, t
			end
		end
		if not done then
			done, total = 0, 0
			for _, id in ipairs(QuestsOf(place)) do
				local status = StatusOf(id)
				if status ~= "other" then
					total = total + 1
					if status == "done" then
						done = done + 1
					end
				end
			end
		end
		c = { done, total }
		state.counts[place.id] = c
	end
	return c[1], c[2]
end

local function Range(place)
	local low, high = place.minLevel, place.maxLevel
	if not (low and high) then
		return low and tostring(low) or ""
	end
	return low == high and tostring(low) or (low .. "-" .. high)
end

local function LevelOf(id)
	local q = Quest(id)
	return q and q.level or 0
end

-- A chain's quests in order (Q.Chain's: each after what it needs) and who leads to whom inside it:
-- each quest's pre, preAny and preActive and Q.Opens, only from an earlier one to a later one.
local function NewGroup(key, chain)
	local index, parents = {}, {}
	for i, id in ipairs(chain) do
		index[id] = index[id] or i
	end
	local function Lead(from, to)
		if not (from and to and from ~= to and index[from] and index[to] and index[from] < index[to]) then
			return
		end
		local list = parents[to]
		if not list then
			list = {}
			parents[to] = list
		end
		for _, p in ipairs(list) do
			if p == from then
				return
			end
		end
		list[#list + 1] = from
	end
	local faction, mixed = nil, false
	for _, id in ipairs(chain) do
		local q = Quest(id)
		if q then
			for _, p in ipairs(q.pre or EMPTY) do
				Lead(p, id)
			end
			for _, p in ipairs(q.preAny or EMPTY) do
				Lead(p, id)
			end
			Lead(q.preActive, id)
			if q.faction ~= faction then
				mixed = mixed or faction ~= nil or q.faction == nil
				faction = faction or q.faction
			end
		end
		for _, o in ipairs(Q.Opens and Q.Opens(id) or EMPTY) do
			Lead(id, o)
		end
	end
	for _, list in pairs(parents) do
		table.sort(list, function(a, b) return index[a] < index[b] end)
	end
	return { key = key, chain = chain, index = index, parents = parents, faction = not mixed and faction or nil }
end

-- A place's chains (a group each, the lowest level first, then the quests without one), worked out once.
local function Structure(place)
	local tree = state.trees[place.id]
	if tree then
		return tree
	end
	state.trees_built = state.trees_built + 1
	local ids = PlaceQuests(place)
	local member, assigned, singles = {}, {}, {}
	tree = { groups = {}, member = member, shown = {}, groupOf = {}, ids = ids }
	for _, id in ipairs(ids) do
		member[id] = true
	end
	for _, id in ipairs(ids) do
		if not assigned[id] then
			local chain = Q.Chain and Q.Chain(id)
			if type(chain) == "table" and #chain > 1 then
				local low = math.huge
				for _, c in ipairs(chain) do
					assigned[c] = true
					if member[c] then
						low = math.min(low, LevelOf(c))
					end
				end
				local group = NewGroup(place.id .. ":" .. tostring(chain[1]), chain)
				group.low, group.order = low, #tree.groups
				tree.groups[#tree.groups + 1] = group
			else
				assigned[id] = true
				singles[#singles + 1] = id
			end
		end
	end
	table.sort(tree.groups, function(a, b)
		if a.low ~= b.low then
			return a.low < b.low
		end
		return a.order < b.order
	end)
	if singles[1] then
		table.sort(singles, function(a, b)
			local la, lb = LevelOf(a), LevelOf(b)
			if la ~= lb then
				return la < lb
			end
			return a < b
		end)
		local group = NewGroup(place.id .. ":single", singles)
		group.single, group.parents = true, {}
		tree.groups[#tree.groups + 1] = group
	end
	for _, group in ipairs(tree.groups) do
		for _, id in ipairs(group.chain) do
			tree.shown[id] = true
			tree.groupOf[id] = tree.groupOf[id] or group
		end
	end
	state.trees[place.id] = tree
	return tree
end

-- Where a quest's chains are: the place shown if it's in them, else its zone or its dungeon, the one
-- that lists it (a dungeon's quest may be given in a zone that doesn't).
local function PlaceOf(q, id)
	local current = state.where and state.places[state.where]
	if current and Structure(current).shown[id] then
		return current.id
	end
	local zone = q.zone and state.places["z:" .. tostring(q.zone)]
	local dungeon = q.dungeon and state.places["d:" .. tostring(q.dungeon)]
	if zone and Structure(zone).member[id] then
		return zone.id
	elseif dungeon and Structure(dungeon).member[id] then
		return dungeon.id
	end
	local place = zone or dungeon
	return place and place.id or nil
end

-- Where I am, or the first zone.
local function DefaultPlace()
	local map = C_Map and LT.Value(C_Map.GetBestMapForUnit, "player")
	for _ = 1, 4 do
		if type(map) ~= "number" then
			break
		end
		if state.places["z:" .. map] then
			return "z:" .. map
		end
		local info = LT.Value(C_Map.GetMapInfo, map)
		map = type(info) == "table" and info.parentMapID or nil
	end
	local first = state.zones[1] or nil
	if first then
		return "z:" .. tostring(first.map)
	end
	local dungeon = state.dungeons[1]
	return dungeon and ("d:" .. tostring(dungeon.name)) or nil
end

-- The data changed: everything worked out from it goes.
local function Forget()
	state.places, state.zones, state.dungeons = nil, nil, nil
	wipe(state.trees)
	wipe(state.layouts)
	wipe(state.counts)
	state.results = nil
end

local function CurrentPlace()
	return state.where and state.places and state.places[state.where] or nil
end

---------------------------------------------------------------------------
-- The filters, the tab (kept in the module's settings: browser = { ... })
---------------------------------------------------------------------------

local function Saved()
	local db = Q.module and Q.module.db
	if type(db) ~= "table" then
		return nil
	end
	if type(db.browser) ~= "table" then
		db.browser = {}
	end
	return db.browser
end

local function LoadSaved()
	local saved = Saved()
	if not saved then
		return
	end
	for key in pairs(filters) do
		if type(saved[key]) == "boolean" then
			filters[key] = saved[key]
		end
	end
	if saved.tab == "chains" or saved.tab == "overview" or saved.tab == "map" then
		state.tab = saved.tab
	end
end

local function Save()
	local saved = Saved()
	if saved then
		for key, on in pairs(filters) do
			saved[key] = on
		end
		saved.tab = state.tab
	end
end

---------------------------------------------------------------------------
-- Lists: a pool of rows, each kept on its entry while it's in sight (zones, the overview, results)
---------------------------------------------------------------------------

local function NewList(parent, x, y, width, height, newRow, fillRow)
	local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", x, -y)
	scroll:SetSize(width, height)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(width, 1)
	scroll:SetScrollChild(child)
	local sight = math.ceil(height / ROW_H) + 1
	local pool = sight + 2 * BEYOND
	local list = { scroll = scroll, child = child, rows = {}, entries = {}, first = 1, made = 0, fills = 0, height = height, pool = pool }

	-- The rows from just above to just below sight. Entry i always has row (i - 1) % pool + 1, so a row
	-- the controller's cursor is on keeps its entry when the list scrolls under it.
	function list:Lay(offset)
		local top = math.max(0, math.floor((offset or scroll:GetVerticalScroll() or 0) / ROW_H))
		self.first = top + 1
		local from, to = math.max(1, top + 1 - BEYOND), math.min(#self.entries, top + sight + BEYOND)
		for i = from, to do
			local k = (i - 1) % pool + 1
			local row = self.rows[k]
			if not row then
				row = newRow(child, width)
				self.rows[k] = row
				self.made = self.made + 1
			end
			if row.index ~= i then
				row.index = i
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
			end
			row.entry = self.entries[i]
			self.fills = self.fills + 1
			fillRow(row, row.entry)
			row:Show()
		end
		for k = 1, pool do
			local row = self.rows[k]
			if row and not (row.index and row.index >= from and row.index <= to) then
				row.entry, row.index = nil, nil
				row:Hide()
			end
		end
	end

	-- New entries, scrolled to offset (true: where it is, as far as it still goes).
	function list:SetEntries(entries, offset)
		self.entries = entries
		local total = #entries * ROW_H
		child:SetHeight(math.max(1, total))
		local now = scroll:GetVerticalScroll() or 0
		local want = offset == true and now or offset or 0
		want = math.max(0, math.min(want, total - height))
		self.first = math.floor(want / ROW_H) + 1
		if want ~= now then
			scroll:SetVerticalScroll(want)
		end
		for _, row in pairs(self.rows) do
			row.index = nil -- (their entries are others now)
		end
		self:Lay(want)
	end

	function list:Centered(i)
		return math.max(0, (i - 1) * ROW_H - height / 2 + ROW_H / 2)
	end

	scroll:HookScript("OnVerticalScroll", function(_, offset)
		if math.floor((offset or 0) / ROW_H) + 1 ~= list.first then
			list:Lay(offset)
		end
	end)
	return list
end

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------

local function Untip(self)
	if GameTooltip:IsOwned(self) then
		GameTooltip:Hide()
	end
end

-- A quest's tooltip: title, status, level, chain step, where it starts, what's next, friends.
local function QuestTip(owner, id)
	local q = Quest(id)
	if not q then
		return
	end
	local status = StatusOf(id)
	local c = TONE[status]
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(Title(id), 1, 0.82, 0)
	GameTooltip:AddLine(Word(status), c[1], c[2], c[3])
	if q.level and q.level > 0 then
		local r, g, b = LevelRgb(q)
		GameTooltip:AddLine(L["Level %d"]:format(q.level), r, g, b)
	end
	local zone = ZoneOf(q)
	if zone then
		GameTooltip:AddLine(zone, 0.8, 0.8, 0.8)
	end
	local step, total, name = StepOf(id)
	if step then
		GameTooltip:AddLine(L["Step %d of %d"]:format(step, total) .. (name and (" - " .. name) or ""), 0.8, 0.8, 0.8)
	end
	local s = FirstStart(q)
	if s then
		GameTooltip:AddLine(L["Starts at: %s"]:format(StartWord(s)), 1, 1, 1)
		local d = s.drops and s.drops[1]
		if d then
			GameTooltip:AddLine(L["Drops from %s (%s%%)"]:format(d.name or "?", Chance(d.chance)), 0.8, 0.8, 0.8)
		end
	end
	local opens = Q.Opens and Q.Opens(id) or EMPTY
	if opens[1] then
		local names = {}
		for i, o in ipairs(opens) do
			if i > 3 then
				names[#names + 1] = "..."
				break
			end
			names[#names + 1] = Title(o)
		end
		GameTooltip:AddLine(L["Then: %s"]:format(table.concat(names, ", ")), 0.8, 0.8, 0.8, true)
	end
	local friends = Q.Friends and Q.Friends(id) or EMPTY
	for i, f in ipairs(friends) do
		if i > 6 then
			break
		end
		local fs = TONE[f.status] and f.status or "other"
		GameTooltip:AddLine(LT.Window.ClassColorCode(f.classFile) .. (f.name or "?") .. "|r " .. HEX[fs] .. Word(fs) .. "|r")
	end
	GameTooltip:AddLine(L["Click: details"], 0.5, 0.75, 1)
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- The chains: the layout
---------------------------------------------------------------------------

-- A chain's cards by stage (how many quests come before it), with a slot of its own for a line that
-- passes a stage (so it never runs through a card), the stages' quests ordered by where what leads to
-- them is, each stage centred in the chain's width. Lines: down from a card, across, down into the next.
function Graph.LayChain(out, group, vis, top, viewW)
	local index, parents = group.index, group.parents
	local vpar = {}
	-- What leads to a quest among those shown: a hidden one is passed through to what leads to it.
	local function VP(id)
		local list = vpar[id]
		if list then
			return list
		end
		list = { bridged = {} }
		vpar[id] = list
		local seen = {}
		local function Add(p, bridged)
			if not seen[p] then
				seen[p] = true
				list[#list + 1] = p
				list.bridged[p] = bridged or nil
			end
		end
		for _, p in ipairs(parents[id] or EMPTY) do
			if vis[p] then
				Add(p, false)
			else
				for _, pp in ipairs(VP(p)) do
					Add(pp, true)
				end
			end
		end
		table.sort(list, function(a, b) return index[a] < index[b] end)
		return list
	end
	local stage, maxStage, order = {}, 0, {}
	for _, id in ipairs(group.chain) do
		if vis[id] then
			order[#order + 1] = id
			local s = 0
			for _, p in ipairs(VP(id)) do
				if stage[p] and stage[p] + 1 > s then
					s = stage[p] + 1
				end
			end
			stage[id] = s
			maxStage = math.max(maxStage, s)
		end
	end
	local rows, item, edges, seq = {}, {}, {}, 0
	for s = 0, maxStage do
		rows[s] = {}
	end
	local function New(it)
		seq = seq + 1
		it.seq, it.preds = seq, it.preds or {}
		local row = rows[it.stage]
		row[#row + 1] = it
		return it
	end
	for _, id in ipairs(order) do
		item[id] = New({ quest = id, stage = stage[id], w = G.W, order = index[id], status = vis[id], group = group })
	end
	for _, id in ipairs(order) do
		for _, p in ipairs(VP(id)) do
			local path, prev = { item[p] }, item[p]
			for s = stage[p] + 1, stage[id] - 1 do
				prev = New({ dummy = true, stage = s, w = G.DUMMY, order = index[id], preds = { prev } })
				path[#path + 1] = prev
			end
			local child = item[id]
			child.preds[#child.preds + 1] = prev
			path[#path + 1] = child
			edges[#edges + 1] = { path = path, from = p, to = id, bridged = VP(id).bridged[p] == true }
		end
	end
	-- Each stage ordered by where what leads to it is (the first stage in the chain's order), then sized.
	local widest = 0
	for s = 0, maxStage do
		local row = rows[s]
		for _, it in ipairs(row) do
			if s == 0 or not it.preds[1] then
				it.key = it.order
			else
				local sum = 0
				for _, p in ipairs(it.preds) do
					sum = sum + p.slot
				end
				it.key = sum / #it.preds
			end
		end
		table.sort(row, function(a, b)
			if a.key ~= b.key then
				return a.key < b.key
			elseif a.order ~= b.order then
				return a.order < b.order
			end
			return a.seq < b.seq
		end)
		local w = 0
		for i, it in ipairs(row) do
			it.slot = i
			w = w + it.w + (i > 1 and G.HGAP or 0)
		end
		row.w = w
		widest = math.max(widest, w)
	end
	local blockW = math.max(widest, viewW - 2 * PAD)
	for s = 0, maxStage do
		local row = rows[s]
		local x = PAD + (blockW - row.w) / 2
		for _, it in ipairs(row) do
			it.x, it.y = x, top + s * G.PY
			it.cx, it.bottom = x + it.w / 2, it.y + G.H
			x = x + it.w + G.HGAP
			if not it.dummy then
				out.cards[#out.cards + 1] = it
				out.byQuest[it.quest] = it
			end
		end
	end
	-- The lines: green between done ones, amber from a done or ready one, grey; a passed-through
	-- (hidden) step: fainter.
	local half = G.LINE / 2
	for _, e in ipairs(edges) do
		local fs, ts = vis[e.from], vis[e.to]
		local tone = (fs == "done" and ts == "done") and 2 or (fs == "done" or fs == "available" or fs == "active") and 1 or 0
		for i = 1, #e.path - 1 do
			local a, b = e.path[i], e.path[i + 1]
			local ym = a.bottom + G.VGAP / 2
			Graph.Seg(out, a.cx, a.bottom, a.cx, ym + half, tone, e.bridged)
			Graph.Seg(out, math.min(a.cx, b.cx) - half, ym, math.max(a.cx, b.cx) + half, ym, tone, e.bridged)
			Graph.Seg(out, b.cx, ym - half, b.cx, b.y, tone, e.bridged)
			if b.dummy then
				Graph.Seg(out, b.cx, b.y - half, b.cx, b.bottom + half, tone, e.bridged)
			end
		end
	end
	-- "OR" between quests next to each other of which one is enough (preAny).
	for _, id in ipairs(order) do
		local q = Quest(id)
		local any = q and q.preAny or EMPTY
		if any[2] then
			local mine = {}
			for _, p in ipairs(any) do
				local it = item[p]
				if it then
					mine[#mine + 1] = it
				end
			end
			table.sort(mine, function(a, b)
				if a.stage ~= b.stage then
					return a.stage < b.stage
				end
				return a.slot < b.slot
			end)
			for i = 2, #mine do
				local a, b = mine[i - 1], mine[i]
				if a.stage == b.stage and b.slot == a.slot + 1 then
					out.pills[#out.pills + 1] = { x = (a.x + a.w + b.x) / 2, y = a.y + G.H / 2 }
				end
			end
		end
	end
	out.width = math.max(out.width, blockW + 2 * PAD)
	return top + (maxStage + 1) * G.PY - G.VGAP
end

-- A line segment (canvas units, y down); zero-length ones aren't kept.
function Graph.Seg(out, x1, y1, x2, y2, tone, faint)
	if math.abs(x2 - x1) < 0.5 and math.abs(y2 - y1) < 0.5 then
		return
	end
	out.segs[#out.segs + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, tone = tone, faint = faint,
		minX = math.min(x1, x2), maxX = math.max(x1, x2), minY = math.min(y1, y2), maxY = math.max(y1, y2) }
end

-- The quests without a chain: cards in rows.
function Graph.LaySingles(out, group, vis, top, viewW)
	local perRow = math.max(1, math.floor((viewW - 2 * PAD + G.HGAP) / (G.W + G.HGAP)))
	local n = 0
	for _, id in ipairs(group.chain) do
		if vis[id] then
			local col, row = n % perRow, math.floor(n / perRow)
			n = n + 1
			local it = { quest = id, status = vis[id], group = group, w = G.W,
				x = PAD + col * (G.W + G.HGAP), y = top + row * G.PY }
			it.cx, it.bottom = it.x + G.W / 2, it.y + G.H
			out.cards[#out.cards + 1] = it
			out.byQuest[id] = it
		end
	end
	out.width = math.max(out.width, math.min(n, perRow) * (G.W + G.HGAP) - G.HGAP + 2 * PAD)
	return top + math.ceil(n / perRow) * G.PY - G.VGAP
end

-- A place's cards, banners and lines with the filters and statuses of now (kept until one changes).
function Graph.Layout(place)
	local cached = state.layouts[place.id]
	if cached then
		return cached
	end
	state.layouts_built = state.layouts_built + 1
	local viewW = view.g.w
	local out = { cards = {}, banners = {}, segs = {}, pills = {}, byQuest = {}, width = viewW, height = 0, hidden = 0 }
	local y = PAD
	for _, group in ipairs(Structure(place).groups) do
		local vis, n, done, total, nextUp = {}, 0, 0, 0, nil
		for _, id in ipairs(group.chain) do
			local status = StatusOf(id)
			if status ~= "other" then
				total = total + 1
				done = done + (status == "done" and 1 or 0)
			end
			if Visible(status) then
				vis[id], n = status, n + 1
			else
				out.hidden = out.hidden + 1
			end
		end
		if n > 0 then
			local closed = state.folded[group.key] == true
			local banner = { group = group, key = group.key, x = PAD, y = y, done = done, total = total, closed = closed, n = n }
			out.banners[#out.banners + 1] = banner
			local bottom = y + G.BANNER
			if not closed then
				local top = y + G.BANNER + G.BANNER_GAP
				if group.single then
					bottom = Graph.LaySingles(out, group, vis, top, viewW)
				else
					bottom = Graph.LayChain(out, group, vis, top, viewW)
				end
			end
			banner.w = math.max(viewW - 2 * PAD, out.width - 2 * PAD)
			y = bottom + G.GROUP_GAP
		end
	end
	for _, banner in ipairs(out.banners) do
		banner.w = math.max(banner.w, out.width - 2 * PAD) -- (as wide as the widest chain)
	end
	out.height = math.max(1, y - G.GROUP_GAP + PAD)
	state.layouts[place.id] = out
	return out
end

-- What the banner says is next: the quest in my log, else the first I can take, else the first coming.
local function NextOf(group)
	local found = {}
	for _, id in ipairs(group.chain) do
		local status = StatusOf(id)
		if not found[status] then
			found[status] = id
		end
	end
	if found.active then
		return L["In your log: %s"]:format(Title(found.active)), found.active
	elseif found.available then
		local s = FirstStart(Quest(found.available))
		local q = Quest(found.available)
		local where = s and s.name or (q and ZoneOf(q))
		return L["Next: %s"]:format(Title(found.available)) .. (where and (GREY .. " - " .. where .. "|r") or ""), found.available
	elseif found.level or found.locked then
		local id = found.level or found.locked
		return L["Coming up: %s"]:format(Title(id)), id
	elseif found.done then
		return L["All done"], nil
	end
	return nil, nil
end

---------------------------------------------------------------------------
-- The chains: the canvas (our own scrolling both ways, a zoom) and its pools
---------------------------------------------------------------------------

local LINE_TONES = {
	[0] = { 0.45, 0.45, 0.45, 1 }, { 0.851, 0.608, 0, 1 }, { 0.388, 0.686, 0.388, 1 },
}

-- What's in sight, in canvas units (and the margin beyond it).
local function SightRect(g, margin)
	local w, h = g.w / g.zoom, g.h / g.zoom
	return g.sx - margin, g.sx + w + margin, g.sy - margin, g.sy + h + margin
end

function Graph.Thumbs()
	local g = view.g
	local lay = g.layout
	local cw, ch = lay and lay.width or 0, lay and lay.height or 0
	local w, h = g.w / g.zoom, g.h / g.zoom
	if cw > w + 1 then
		local size = math.max(24, g.w * w / cw)
		g.HThumb:SetWidth(size)
		g.HThumb:ClearAllPoints()
		g.HThumb:SetPoint("BOTTOMLEFT", g.frame, "BOTTOMLEFT", (g.w - size) * math.max(0, g.sx) / (cw - w), 1)
		g.HThumb:Show()
	else
		g.HThumb:Hide()
	end
	if ch > h + 1 then
		local size = math.max(24, g.h * h / ch)
		g.VThumb:SetHeight(size)
		g.VThumb:ClearAllPoints()
		g.VThumb:SetPoint("TOPRIGHT", g.frame, "TOPRIGHT", -1, -(g.h - size) * math.max(0, g.sy) / (ch - h))
		g.VThumb:Show()
	else
		g.VThumb:Hide()
	end
end

-- Scrolled to sx, sy (canvas units), kept inside the canvas; a canvas smaller than sight is centred.
function Graph.ScrollTo(sx, sy, force)
	local g = view.g
	local lay = g.layout
	local cw, ch = lay and lay.width or 0, lay and lay.height or 0
	local w, h = g.w / g.zoom, g.h / g.zoom
	sx = cw <= w and -(w - cw) / 2 or math.max(0, math.min(sx, cw - w))
	sy = ch <= h and 0 or math.max(0, math.min(sy, ch - h))
	sx, sy = math.floor(sx + 0.5), math.floor(sy + 0.5)
	if force or sx ~= g.sx or sy ~= g.sy then
		g.sx, g.sy = sx, sy
		g.canvas:ClearAllPoints()
		g.canvas:SetPoint("TOPLEFT", g.frame, "TOPLEFT", -sx, sy) -- (in the canvas's own, zoomed units)
		Graph.Thumbs()
	end
	Graph.Lay(force)
end

-- A card (or banner) the controller's cursor moved to out of sight: brought into view.
function Graph.Reveal(it, w, h)
	local g = view.g
	local vx0, vx1, vy0, vy1 = SightRect(g, 0)
	local cx, cy = it.x + w / 2, it.y + h / 2
	if cx >= vx0 and cx <= vx1 and cy >= vy0 and cy <= vy1 then
		return
	end
	local sx, sy = g.sx, g.sy
	if it.x < vx0 then
		sx = it.x - G.HGAP
	elseif it.x + w > vx1 then
		sx = it.x + w + G.HGAP - (vx1 - vx0)
	end
	if it.y < vy0 then
		sy = it.y - G.VGAP
	elseif it.y + h > vy1 then
		sy = it.y + h + G.VGAP - (vy1 - vy0)
	end
	Graph.ScrollTo(sx, sy)
end

-- The cards, banners, lines and pills near sight, from the pools; laid again only when the view moved
-- a good bit (half a card), or force.
function Graph.Lay(force)
	local g = view.g
	local lay = g.layout
	if not lay then
		return
	end
	local bucket = math.floor(g.sx / (G.W / 2)) .. ":" .. math.floor(g.sy / (G.PY / 2)) .. ":" .. g.zoom
	if not force and bucket == g.bucket then
		return
	end
	g.bucket = bucket
	g.lays = g.lays + 1
	local x0, x1, y0, y1 = SightRect(g, G.MARGIN)
	-- Cards: each kept on its quest while it stays near.
	local want = {}
	for _, it in ipairs(lay.cards) do
		if it.x + G.W >= x0 and it.x <= x1 and it.y + G.H >= y0 and it.y <= y1 then
			want[it.quest] = it
		end
	end
	for id, card in pairs(g.cards) do
		if not want[id] then
			g.cards[id] = nil
			Untip(card)
			card.item = nil
			card:Hide()
			g.freeCards[#g.freeCards + 1] = card
		end
	end
	for id, it in pairs(want) do
		local card = g.cards[id]
		if not card then
			card = table.remove(g.freeCards) or Graph.NewCard(g.canvas)
			g.cards[id] = card
		end
		if card.px ~= it.x or card.py ~= it.y then
			card.px, card.py = it.x, it.y
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", g.canvas, "TOPLEFT", it.x, -it.y)
		end
		card.item = it
		Graph.FillCard(card, it)
		card:Show()
	end
	-- Banners, the same by their chain.
	local banners = {}
	for _, b in ipairs(lay.banners) do
		if b.y + G.BANNER >= y0 and b.y <= y1 and b.x <= x1 and b.x + b.w >= x0 then
			banners[b.key] = b
		end
	end
	for key, f in pairs(g.banners) do
		if not banners[key] then
			g.banners[key] = nil
			f.item = nil
			f:Hide()
			g.freeBanners[#g.freeBanners + 1] = f
		end
	end
	for key, b in pairs(banners) do
		local f = g.banners[key]
		if not f then
			f = table.remove(g.freeBanners) or Graph.NewBanner(g.canvas)
			g.banners[key] = f
		end
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", g.canvas, "TOPLEFT", b.x, -b.y)
		f:SetWidth(b.w)
		f.item = b
		Graph.FillBanner(f, b)
		f:Show()
	end
	-- Lines and pills: only what's near.
	local n = 0
	for _, s in ipairs(lay.segs) do
		if s.maxX >= x0 and s.minX <= x1 and s.maxY >= y0 and s.minY <= y1 then
			n = n + 1
			local line = g.lines[n]
			if not line then
				line = g.canvas:CreateLine(nil, "ARTWORK")
				line:SetThickness(G.LINE)
				g.lines[n] = line
			end
			local c = LINE_TONES[s.tone]
			line:SetColorTexture(c[1], c[2], c[3], s.faint and 0.45 or c[4])
			if line.SetDrawLayer then
				line:SetDrawLayer("ARTWORK", s.tone) -- (the lit ones over the grey)
			end
			line:SetStartPoint("TOPLEFT", g.canvas, s.x1, -s.y1)
			line:SetEndPoint("TOPLEFT", g.canvas, s.x2, -s.y2)
			line:Show()
		end
	end
	for i = n + 1, #g.lines do
		g.lines[i]:Hide()
	end
	g.linesShown = n
	local p = 0
	for _, pill in ipairs(lay.pills) do
		if pill.x >= x0 and pill.x <= x1 and pill.y >= y0 and pill.y <= y1 then
			p = p + 1
			local f = g.pills[p] or Graph.NewPill(g.canvas)
			g.pills[p] = f
			f:ClearAllPoints()
			f:SetPoint("CENTER", g.canvas, "TOPLEFT", pill.x, -pill.y)
			f:Show()
		end
	end
	for i = p + 1, #g.pills do
		g.pills[i]:Hide()
	end
end

-- The cards in sight filled again (a pick, titles that came).
function Graph.Refill()
	for _, card in pairs(view.g.cards) do
		if card.item then
			Graph.FillCard(card, card.item)
		end
	end
	for _, f in pairs(view.g.banners) do
		if f.item then
			Graph.FillBanner(f, f.item)
		end
	end
end

-- The place's chains drawn (keep: where it's scrolled; focus: a quest to bring into the middle).
function Graph.Draw(place, keep, focus)
	local g = view.g
	g.layout = place and Graph.Layout(place) or nil
	local lay = g.layout
	g.canvas:SetSize(math.max(1, lay and lay.width or 1), math.max(1, lay and lay.height or 1))
	local sx, sy = keep and g.sx or 0, keep and g.sy or 0
	local it = focus and lay and lay.byQuest[focus]
	if it then
		sx = it.x + G.W / 2 - g.w / g.zoom / 2
		sy = it.y + G.H / 2 - g.h / g.zoom / 2
	end
	Graph.ScrollTo(sx, sy, true)
end

function Graph.SetZoom(zoom)
	local g = view.g
	zoom = math.max(G.ZOOM_MIN, math.min(G.ZOOM_MAX, math.floor(zoom * 100 + 0.5) / 100))
	if zoom == g.zoom then
		return
	end
	local cx, cy = g.sx + g.w / g.zoom / 2, g.sy + g.h / g.zoom / 2 -- (the middle stays)
	g.zoom = zoom
	g.canvas:SetScale(zoom)
	Graph.ScrollTo(cx - g.w / zoom / 2, cy - g.h / zoom / 2, true)
	view.ZoomText:SetText(("%d%%"):format(math.floor(zoom * 100 + 0.5)))
end

-- The whole width in sight (as far as the zoom goes).
function Graph.Fit()
	local lay = view.g.layout
	local cw = lay and lay.width or 1
	Graph.SetZoom(math.min(G.ZOOM_MAX, view.g.w / cw))
end

local function Edges(f, r, g, b, a)
	for _, t in ipairs(f.Edges) do
		t:SetColorTexture(r, g, b, a or 1)
	end
end

-- Four 1 px edges around a frame (a flat border, BeautifulAttune's look).
local function NewEdges(f, layer)
	f.Edges = {}
	for i, spec in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
		local t = f:CreateTexture(nil, layer or "BORDER")
		t:SetPoint(spec[1])
		t:SetPoint(spec[2])
		if spec[3] then
			t:SetHeight(1)
		else
			t:SetWidth(1)
		end
		f.Edges[i] = t
	end
end

local function CardEnter(self)
	local it = self.item
	if not it then
		return
	end
	local pad = InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()
	if pad or not self:IsMouseOver() then -- (the controller's cursor, not the mouse)
		Graph.Reveal(it, G.W, G.H)
	end
	QuestTip(self, it.quest)
end

function Graph.NewCard(canvas)
	local b = CreateFrame("Button", nil, canvas)
	b:SetSize(G.W, G.H)
	b.Bg = b:CreateTexture(nil, "BACKGROUND")
	b.Bg:SetAllPoints()
	b.Bg:SetTexture(T.flat)
	b.Glow = b:CreateTexture(nil, "BACKGROUND", nil, -1)
	b.Glow:SetPoint("TOPLEFT", -3, 3)
	b.Glow:SetPoint("BOTTOMRIGHT", 3, -3)
	b.Glow:SetColorTexture(1, 0.82, 0, 0.35)
	b.Glow:Hide()
	NewEdges(b)
	b.Strip = b:CreateTexture(nil, "ARTWORK")
	b.Strip:SetPoint("TOPLEFT", 1, -1)
	b.Strip:SetPoint("BOTTOMLEFT", 1, 1)
	b.Strip:SetWidth(3)
	b.Icon = b:CreateTexture(nil, "ARTWORK")
	b.Icon:SetSize(G.ICON, G.ICON)
	b.Icon:SetPoint("LEFT", 8, 0)
	b.Check = b:CreateTexture(nil, "OVERLAY")
	b.Check:SetSize(16, 16)
	b.Check:SetPoint("BOTTOMRIGHT", b.Icon, "BOTTOMRIGHT", 4, -4)
	Art(b.Check, "common-icon-checkmark", T.check)
	b.Title = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	b.Title:SetPoint("TOPLEFT", G.ICON + 14, -7)
	b.Title:SetPoint("RIGHT", -6, 0)
	b.Title:SetJustifyH("LEFT")
	b.Title:SetWordWrap(false)
	b.Info = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.Info:SetPoint("BOTTOMLEFT", G.ICON + 14, 8)
	b.Info:SetPoint("RIGHT", -6, 0)
	b.Info:SetJustifyH("LEFT")
	b.Info:SetWordWrap(false)
	b.Friends = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.Friends:SetPoint("TOPRIGHT", -5, -4)
	b.Friends:SetJustifyH("RIGHT")
	b:SetHighlightTexture(T.highlight, "ADD")
	b:SetScript("OnEnter", CardEnter)
	b:SetScript("OnLeave", Untip)
	b:SetScript("OnClick", function(self)
		if self.item then
			Graph.Pick(self.item.quest)
		end
	end)
	view.g.made = view.g.made + 1
	return b
end

-- A card: its tone (Attune's: done green, ready amber, in the log blue, the rest grey), the strip in
-- its status's colour, the start, the title, "[12] Marshal Dughan" (another zone: its name), friends.
function Graph.FillCard(b, it)
	local id = it.quest
	local q = Quest(id)
	local status = StatusOf(id)
	local c = TONE[status]
	local bright = status == "done" or status == "available" or status == "active"
	b.Bg:SetVertexColor(bright and c[1] or 0.1, bright and c[2] or 0.1, bright and c[3] or 0.1, bright and 0.3 or 0.6)
	if id == state.picked then
		Edges(b, 1, 0.82, 0)
	elseif bright then
		Edges(b, c[1], c[2], c[3])
	else
		Edges(b, 0.4, 0.4, 0.4)
	end
	b.Glow:SetShown(id == state.picked)
	b.Strip:SetColorTexture(c[1], c[2], c[3], 1)
	StartIcon(b.Icon, q, status)
	b.Check:SetShown(status == "done")
	b.Title:SetText(Title(id))
	if status == "done" or status == "other" then
		b.Title:SetTextColor(0.7, 0.7, 0.7)
	else
		b.Title:SetTextColor(1, 1, 1)
	end
	local zone = q and ZoneOf(q)
	local here = CurrentPlace()
	local where
	if zone and here and zone ~= here.name then
		where = zone
	else
		local s = FirstStart(q)
		where = s and s.name or zone
	end
	b.Info:SetText(LevelTag(q) .. GREY .. (where or "") .. "|r")
	local friends = Q.Friends and Q.Friends(id) or EMPTY
	if friends[1] then
		local done = 0
		for _, f in ipairs(friends) do
			done = done + (f.status == "done" and 1 or 0)
		end
		b.Friends:SetText("|cff80c0ff" .. done .. "/" .. #friends .. "|r")
		b.Friends:Show()
	else
		b.Friends:Hide()
	end
	b:SetAlpha(status == "other" and 0.55 or 1)
end

local function BannerEnter(self)
	local it = self.item
	if not it then
		return
	end
	local pad = InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()
	if pad or not self:IsMouseOver() then
		Graph.Reveal({ x = view.g.sx > it.x and view.g.sx + PAD or it.x, y = it.y }, math.min(it.w, view.g.w / view.g.zoom - 2 * PAD), G.BANNER)
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(self.Name:GetText() or "", 1, 0.82, 0)
	GameTooltip:AddLine(L["%d of %d steps done"]:format(it.done, it.total), 1, 1, 1)
	GameTooltip:AddLine(it.closed and L["Click: open"] or L["Click: fold"], 0.5, 0.75, 1)
	GameTooltip:Show()
end

function Graph.NewBanner(canvas)
	local f = CreateFrame("Button", nil, canvas)
	f:SetHeight(G.BANNER)
	f.Art = f:CreateTexture(nil, "BACKGROUND")
	f.Art:SetAllPoints()
	f.Shade = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	f.Shade:SetAllPoints()
	f.Shade:SetColorTexture(0, 0, 0, 0.35)
	NewEdges(f)
	Edges(f, 1, 0.82, 0, 0.35)
	f.Toggle = f:CreateTexture(nil, "ARTWORK")
	f.Toggle:SetSize(14, 14)
	f.Toggle:SetPoint("TOPLEFT", 8, -9)
	f.Name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.Name:SetPoint("TOPLEFT", 28, -8)
	f.Name:SetPoint("RIGHT", -150, 0)
	f.Name:SetJustifyH("LEFT")
	f.Name:SetWordWrap(false)
	f.Count = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.Count:SetPoint("TOPRIGHT", -10, -10)
	f.Count:SetJustifyH("RIGHT")
	f.BarBack = f:CreateTexture(nil, "ARTWORK")
	f.BarBack:SetPoint("TOPRIGHT", -10, -26)
	f.BarBack:SetSize(130, 6)
	f.BarBack:SetColorTexture(0, 0, 0, 0.6)
	f.Bar = f:CreateTexture(nil, "ARTWORK", nil, 1)
	f.Bar:SetPoint("TOPLEFT", f.BarBack, "TOPLEFT")
	f.Bar:SetHeight(6)
	f.Next = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.Next:SetPoint("BOTTOMLEFT", 28, 9)
	f.Next:SetPoint("RIGHT", -10, 0)
	f.Next:SetJustifyH("LEFT")
	f.Next:SetWordWrap(false)
	f:SetHighlightTexture(T.highlight, "ADD")
	f:SetScript("OnEnter", BannerEnter)
	f:SetScript("OnLeave", Untip)
	f:SetScript("OnClick", function(self)
		local it = self.item
		if it then
			Untip(self)
			state.folded[it.key] = not state.folded[it.key] or nil
			state.layouts[state.where] = nil
			Graph.Draw(CurrentPlace(), true)
		end
	end)
	return f
end

-- A chain's banner (Blizzard's story header; a faction's chain its campaign's), desaturated when done.
function Graph.FillBanner(f, b)
	local group = b.group
	local atlas = group.faction == "Alliance" and "Campaign_Alliance" or group.faction == "Horde" and "Campaign_Horde" or "StoryHeader-BG"
	Art(f.Art, atlas, T.flat)
	local all = b.total > 0 and b.done == b.total
	f.Art:SetDesaturated(all)
	if not (atlasKnown[atlas]) then
		f.Art:SetVertexColor(0.16, 0.13, 0.08, 0.95)
	else
		f.Art:SetVertexColor(1, 1, 1, all and 0.55 or 1)
	end
	f.Toggle:SetTexture(b.closed and T.plus or T.minus)
	local name
	if group.single then
		name = L["Quests without a chain"]
	else
		local _, _, chainName = StepOf(group.chain[1])
		name = chainName or Title(group.chain[1])
	end
	f.Name:SetText(name)
	f.Count:SetText(L["%d of %d steps done"]:format(b.done, b.total))
	local fill = b.total > 0 and b.done / b.total or 0
	f.Bar:SetWidth(math.max(1, 130 * fill))
	f.Bar:SetShown(fill > 0)
	local c = all and TONE.done or TONE.available
	f.Bar:SetColorTexture(c[1], c[2], c[3], 1)
	local nextText = not group.single and NextOf(group) or nil
	if group.single then
		nextText = L["%d quests"]:format(b.n)
	end
	f.Next:SetText(nextText or "")
end

function Graph.NewPill(canvas)
	local f = CreateFrame("Frame", nil, canvas)
	f:SetSize(30, 16)
	f:SetFrameLevel(canvas:GetFrameLevel() + 5)
	local back = f:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0.05, 0.05, 0.05, 0.95)
	NewEdges(f)
	Edges(f, 0.851, 0.608, 0, 1)
	f.Text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.Text:SetPoint("CENTER")
	f.Text:SetText(L["OR"])
	return f
end

---------------------------------------------------------------------------
-- Zone maps (the map tab's and the details' small one): the zone's art (LT.MapArt), markers of ours
---------------------------------------------------------------------------

local NEAR = 8     -- px: markers this close are one
local MARKERS = 150
-- Markers' looks: size, the art, the order a shared marker takes the look in.
local LOOK = {
	available = { size = 24, atlas = "QuestNormal", file = T.available, back = true, prio = 1 },
	active = { size = 24, atlas = "QuestTurnin", file = T.turnin, back = true, prio = 2 },
	start = { size = 22, atlas = "QuestNormal", file = T.available, back = true, prio = 1 },
	["end"] = { size = 22, atlas = "QuestTurnin", file = T.turnin, back = true, prio = 2 },
	drop = { size = 34, circle = true, tint = { 1, 0.82, 0 }, alpha = 0.35, prio = 3 },
	level = { size = 18, atlas = "QuestNormal", file = T.available, back = true, desat = true, tint = TONE.level, prio = 4 },
	locked = { size = 18, atlas = "QuestNormal", file = T.available, back = true, desat = true, tint = { 0.8, 0.8, 0.8 }, prio = 5 },
	done = { size = 11, circle = true, tint = TONE.done, alpha = 0.6, ring = true, prio = 6 },
	other = { size = 10, circle = true, tint = TONE.other, alpha = 0.55, ring = true, prio = 7 },
}

local function MarkerEnter(self)
	local m = self.owner
	if m.zoomable then
		local pad = InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()
		if pad or not self:IsMouseOver() then
			Map.Reveal(m, self.px, self.py)
		end
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	local first, lastLabel = true, nil
	for i, spot in ipairs(self.spots) do
		if i > 12 then
			GameTooltip:AddLine(L["... and %d more"]:format(#self.spots - 12), 0.6, 0.6, 0.6)
			break
		end
		if spot.label ~= lastLabel then
			lastLabel = spot.label
			if first then
				GameTooltip:SetText(spot.label or "?", 1, 1, 1)
				first = false
			else
				GameTooltip:AddLine(spot.label or "?", 1, 1, 1)
			end
		end
		if spot.quest then
			local q = Quest(spot.quest)
			local tone = TONE[spot.status] or TONE.other
			GameTooltip:AddLine("  " .. LevelTag(q) .. Title(spot.quest) .. (spot.note and (" " .. spot.note) or ""), tone[1], tone[2], tone[3])
		elseif spot.note then
			GameTooltip:AddLine("  " .. spot.note, 0.8, 0.8, 0.8)
		end
	end
	if m.onClick and self.quests[1] then
		local turn = ((state.turn[self.key] or 0) % #self.quests) + 1
		GameTooltip:AddLine(L["Click: show %s"]:format(Title(self.quests[turn])), 0.5, 0.75, 1)
	end
	GameTooltip:Show()
end

local function MarkerClick(self)
	local m = self.owner
	if m.onClick and self.quests[1] then
		local turn = ((state.turn[self.key] or 0) % #self.quests) + 1
		state.turn[self.key] = turn
		Untip(self)
		m.onClick(self.quests[turn])
	end
end

function Map.New(parent, width, height, zoomable)
	local m = { markers = {}, used = 0, shown = 0, width = width, height = height, zoom = 1, ox = 0, oy = 0, zoomable = zoomable }
	local box = CreateFrame("Frame", nil, parent)
	box:SetSize(width, height)
	box:SetClipsChildren(true)
	local back = box:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.55)
	m.frame = box
	m.Map = CreateFrame("Frame", nil, box)
	m.Map:SetPoint("TOPLEFT")
	m.Map:SetSize(width, height)
	m.art = LT.MapArt.New(m.Map)
	m.Strip = box:CreateTexture(nil, "OVERLAY")
	m.Strip:SetPoint("TOPLEFT")
	m.Strip:SetPoint("TOPRIGHT")
	m.Strip:SetHeight(18)
	m.Strip:SetColorTexture(0, 0, 0, 0.6)
	m.Zone = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	m.Zone:SetPoint("TOPLEFT", 6, -3)
	m.Zone:SetPoint("TOPRIGHT", -6, -3)
	m.Zone:SetJustifyH("LEFT")
	m.Zone:SetWordWrap(false)
	m.Empty = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	m.Empty:SetPoint("CENTER", 0, -6)
	m.Empty:SetText(L["No map of this zone"])
	m.Empty:Hide()
	m.You = m.Map:CreateTexture(nil, "OVERLAY", nil, 7)
	m.You:SetTexture(T.circle)
	m.You:SetVertexColor(0.3, 0.8, 1)
	m.You:SetSize(10, 10)
	m.You:Hide()
	if zoomable then
		box:EnableMouse(true)
		box:EnableMouseWheel(true)
		box:RegisterForDrag("LeftButton")
		box:SetScript("OnMouseWheel", function(_, delta)
			Map.SetZoom(m, m.zoom * (delta > 0 and G.MAP_STEP or 1 / G.MAP_STEP))
		end)
		box:SetScript("OnDragStart", function(self)
			local x, y = GetCursorPosition()
			m.drag = { x, y, m.ox, m.oy, self:GetEffectiveScale() }
			self:SetScript("OnUpdate", function()
				local d = m.drag
				if not d then
					return
				end
				local cx, cy = GetCursorPosition()
				Map.Pan(m, d[3] + (cx - d[1]) / d[5], d[4] - (cy - d[2]) / d[5])
			end)
		end)
		box:SetScript("OnDragStop", function(self)
			m.drag = nil
			self:SetScript("OnUpdate", nil)
		end)
	end
	box:Hide()
	return m
end

-- Moved to ox, oy (px, the map's top left from the box's), inside the box; a map smaller than it centred.
function Map.Pan(m, ox, oy)
	local w, h = m.artW or m.width, m.artH or m.height
	ox = w <= m.width and (m.width - w) / 2 or math.max(m.width - w, math.min(0, ox))
	oy = h <= m.height and (m.height - h) / 2 or math.max(m.height - h, math.min(0, oy))
	m.ox, m.oy = math.floor(ox + 0.5), math.floor(oy + 0.5)
	m.Map:ClearAllPoints()
	m.Map:SetPoint("TOPLEFT", m.frame, "TOPLEFT", m.ox, -m.oy)
end

-- A marker the controller's cursor moved to out of sight: the map moves to it.
function Map.Reveal(m, px, py)
	local x, y = m.ox + px, m.oy + py
	if x < 0 or x > m.width or y < 0 or y > m.height then
		Map.Pan(m, m.width / 2 - px, m.height / 2 - py)
	end
end

function Map.SetZoom(m, zoom)
	zoom = math.max(G.MAP_MIN, math.min(G.MAP_MAX, zoom))
	if zoom == m.zoom or not m.map then
		return
	end
	-- (the middle of the box stays where it is on the map)
	local fx = ((m.width / 2) - m.ox) / (m.artW or m.width)
	local fy = ((m.height / 2) - m.oy) / (m.artH or m.height)
	m.zoom = zoom
	Map.Show(m, m.map, m.spots, m.name)
	Map.Pan(m, m.width / 2 - fx * m.artW, m.height / 2 - fy * m.artH)
	if m.onZoom then
		m.onZoom(zoom)
	end
end

-- The map's art and the markers on it. spots = { { x, y, look, label, quest, status, note } }: spots
-- closer than a few px are one marker (its tooltip lists them all; its look the first by LOOK's order).
function Map.Show(m, map, spots, name)
	local same = m.map == map
	m.map, m.spots, m.name = map, spots, name
	m.frame:Show()
	if not same then
		m.zoom, m.ox, m.oy = 1, 0, 0
	end
	local width, height
	if map then
		width, height = LT.MapArt.Lay(m.art, map, m.width * m.zoom, m.height * m.zoom, true)
	else
		LT.MapArt.Forget(m.art)
	end
	m.Empty:SetShown(width == nil)
	width, height = width or m.width * m.zoom, height or m.height * m.zoom
	m.artW, m.artH = width, height
	m.Map:SetSize(width, height)
	Map.Pan(m, m.ox, m.oy)
	m.Zone:SetText(name or (map and MapName(map)) or "")
	m.Strip:SetShown(map ~= nil)
	local n = 0
	for _, spot in ipairs(map and spots or EMPTY) do
		local x, y = tonumber(spot.x), tonumber(spot.y)
		if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
			local px, py = x * width, y * height
			local near
			for i = 1, n do
				local marker = m.markers[i]
				if math.abs(marker.px - px) <= NEAR and math.abs(marker.py - py) <= NEAR then
					near = marker
					break
				end
			end
			if near then
				near.spots[#near.spots + 1] = spot
				if spot.quest then
					near.quests[#near.quests + 1] = spot.quest
				end
				if (LOOK[spot.look] or LOOK.other).prio < (LOOK[near.look] or LOOK.other).prio then
					near.look = spot.look
				end
			elseif n < MARKERS then
				n = n + 1
				local marker = Map.Marker(m, n)
				marker.px, marker.py, marker.look = px, py, spot.look
				marker.area = tonumber(spot.r) and spot.look == "drop" and math.floor(spot.r * width * 2 + 0.5) or nil
				marker.spots, marker.quests = { spot }, { spot.quest }
				marker.key = ("%s:%d:%d"):format(tostring(map), math.floor(x * 1000), math.floor(y * 1000))
				marker:ClearAllPoints()
				marker:SetPoint("CENTER", m.Map, "TOPLEFT", px, -py)
			end
		end
	end
	-- Each marker's quests, the one to do first first (a click shows it; the next click the next one).
	local function Prio(spot)
		return (LOOK[spot.look] or LOOK.other).prio
	end
	for i = 1, n do
		local marker = m.markers[i]
		if marker.spots[2] then
			table.sort(marker.spots, function(a, b)
				if Prio(a) ~= Prio(b) then
					return Prio(a) < Prio(b)
				end
				return (a.quest or 0) < (b.quest or 0)
			end)
		end
		local quests, seen = {}, {}
		for _, spot in ipairs(marker.spots) do
			if spot.quest and not seen[spot.quest] then
				seen[spot.quest] = true
				quests[#quests + 1] = spot.quest
			end
		end
		marker.quests = quests
		Map.Paint(marker)
	end
	for i = n + 1, m.used do
		Untip(m.markers[i])
		m.markers[i]:Hide()
	end
	m.used = math.max(n, m.used)
	m.shown = n
	-- Me, when I'm on this map.
	local pos = map and C_Map and LT.Value(C_Map.GetPlayerMapPosition, map, "player")
	local px, py
	if type(pos) == "table" and pos.GetXY then
		px, py = pos:GetXY()
	elseif type(pos) == "table" then
		px, py = pos.x, pos.y
	end
	if not LT.IsSecret(px) and type(px) == "number" and type(py) == "number" and px > 0 and py > 0 and px < 1 and py < 1 then
		m.You:ClearAllPoints()
		m.You:SetPoint("CENTER", m.Map, "TOPLEFT", px * width, -py * height)
		m.You:Show()
	else
		m.You:Hide()
	end
end

function Map.Marker(m, i)
	local marker = m.markers[i]
	if not marker then
		marker = CreateFrame("Button", nil, m.Map)
		marker.owner = m
		marker:SetFrameLevel(m.Map:GetFrameLevel() + 2)
		marker.Ring = marker:CreateTexture(nil, "BACKGROUND")
		marker.Ring:SetTexture(T.circle)
		marker.Ring:SetVertexColor(1, 0.82, 0, 0.8)
		marker.Ring:SetPoint("CENTER")
		marker.Back = marker:CreateTexture(nil, "BORDER")
		marker.Back:SetTexture(T.circle)
		marker.Back:SetVertexColor(0, 0, 0, 0.8)
		marker.Back:SetPoint("CENTER")
		marker.Icon = marker:CreateTexture(nil, "ARTWORK")
		marker.Icon:SetPoint("CENTER")
		marker:SetScript("OnEnter", MarkerEnter)
		marker:SetScript("OnLeave", Untip)
		marker:SetScript("OnClick", MarkerClick)
		m.markers[i] = marker
	end
	marker:Show()
	return marker
end

-- A marker's look: solid and clear (a dark disc under the "!" and "?"), done and not-for-me dim dots,
-- drop areas soft circles; a gold ring when it has the quest picked.
function Map.Paint(marker)
	local look = LOOK[marker.look] or LOOK.other
	local size = look.circle and marker.area and math.max(look.size, math.min(160, marker.area)) or look.size
	marker:SetSize(math.max(size, 14), math.max(size, 14))
	marker.Icon:SetSize(size, size)
	if look.circle then
		marker.Icon:SetTexture(T.circle)
		marker.Icon:SetTexCoord(0, 1, 0, 1)
		marker.Icon:SetDesaturated(false)
		marker.Icon:SetVertexColor(look.tint[1], look.tint[2], look.tint[3], look.alpha or 1)
	else
		Art(marker.Icon, look.atlas, look.file)
		marker.Icon:SetDesaturated(look.desat == true)
		local tint = look.tint
		marker.Icon:SetVertexColor(tint and tint[1] or 1, tint and tint[2] or 1, tint and tint[3] or 1, 1)
	end
	marker.Back:SetShown(look.back == true or look.ring == true)
	marker.Back:SetSize(size + (look.ring and 3 or 6), size + (look.ring and 3 or 6))
	local picked = false
	for _, id in ipairs(marker.quests) do
		picked = picked or (id ~= nil and id == state.picked)
	end
	marker.Ring:SetShown(picked)
	marker.Ring:SetSize(size + 12, size + 12)
	marker:SetAlpha(1)
end

-- The markers' rings again (another quest picked).
function Map.Repaint(m)
	for i = 1, m.shown do
		Map.Paint(m.markers[i])
	end
end

-- The map tab: every giver of the place's quests (as the filters show them), turn-ins of quests in
-- my log, where items that start a quest drop.
function Map.Spots(place)
	local spots = {}
	local map = place.map
	for _, id in ipairs(Structure(place).ids) do
		local status = StatusOf(id)
		local q = Quest(id)
		if q and Visible(status) then
			local list = status == "active" and q.ends or q.starts
			for _, s in ipairs(list or EMPTY) do
				for _, p in ipairs(s.points or EMPTY) do
					if p.map == map then
						spots[#spots + 1] = { x = p.x, y = p.y, look = status, label = s.name, quest = id, status = status,
							note = status == "active" and L["(turn in)"] or nil }
					end
				end
				if status ~= "active" and s.kind == "item" then
					for _, d in ipairs(s.drops or EMPTY) do
						for _, p in ipairs(d.points or EMPTY) do
							if p.map == map then
								spots[#spots + 1] = { x = p.x, y = p.y, r = p.r, look = "drop", label = L["%s drops here (%s%%)"]:format(s.name or "?", Chance(d.chance)),
									quest = id, status = status, note = d.name and ("- " .. d.name) or nil }
							end
						end
					end
				end
			end
		end
	end
	return spots
end

function Map.Draw(place)
	local mp = view.mapPane
	if not place or place.kind ~= "zone" then
		mp.map.frame:Hide()
		mp.Note:SetText(L["Dungeon quests are given in many places: each quest's details show where."])
		return
	end
	local spots = Map.Spots(place)
	Map.Show(mp.map, place.map, spots, place.name)
	local counts = {}
	for _, s in ipairs(spots) do
		if s.look ~= "drop" then
			counts[s.status] = (counts[s.status] or 0) + 1
		end
	end
	mp.Note:SetText(L["Quest givers: %d available now, %d in your log, %d later, %d done"]:format(counts.available or 0, counts.active or 0,
		(counts.level or 0) + (counts.locked or 0), counts.done or 0))
end

---------------------------------------------------------------------------
-- The overview: the place's quests in groups
---------------------------------------------------------------------------

local BUCKETS = { "active", "available", "level", "locked", "done", "other" }

local function BucketLabel(status)
	if status == "active" then
		return L["In progress"]
	elseif status == "available" then
		return L["Available now"]
	elseif status == "level" then
		return L["Coming up"]
	elseif status == "locked" then
		return L["Blocked"]
	elseif status == "done" then
		return L["Completed"]
	end
	return L["Not for you"]
end

function Overview.Entries(place)
	local by = {}
	for _, id in ipairs(Structure(place).ids) do
		local status = StatusOf(id)
		if Visible(status) then
			by[status] = by[status] or {}
			table.insert(by[status], id)
		end
	end
	local entries = {}
	for _, status in ipairs(BUCKETS) do
		local list = by[status]
		if list then
			local key = place.id .. ":b:" .. status
			if state.folded[key] == nil and status == "done" then
				state.folded[key] = true -- (done ones start folded)
			end
			local closed = state.folded[key] == true
			entries[#entries + 1] = { header = true, key = key, label = BucketLabel(status), right = tostring(#list), closed = closed, status = status }
			if not closed then
				for _, id in ipairs(list) do
					entries[#entries + 1] = { quest = id, bucket = status }
				end
			end
		end
	end
	return entries
end

-- What the overview's row says at its right: the giver, what blocks it, the level it needs.
local function OverviewRight(e, q)
	if e.bucket == "locked" and Q.Missing then
		local miss = Q.Missing(e.quest) or EMPTY
		if miss[1] then
			return L["needs %s"]:format(Title(miss[1].id))
		end
	elseif e.bucket == "level" and q.minLevel then
		return L["from level %d"]:format(q.minLevel)
	end
	local s = FirstStart(q)
	return s and s.name or nil
end

---------------------------------------------------------------------------
-- The left: zones and dungeons
---------------------------------------------------------------------------

local function ZoneEntries()
	local entries, last = {}, nil
	for _, z in ipairs(state.zones) do
		local key = "c:" .. tostring(z.continent)
		if key ~= last then
			last = key
			entries[#entries + 1] = { header = true, key = key, label = ContinentName(z.continent), closed = state.folded[key] == true }
		end
		if not state.folded[key] then
			entries[#entries + 1] = state.places["z:" .. tostring(z.map)]
		end
	end
	if state.dungeons[1] then
		entries[#entries + 1] = { header = true, key = "c:dungeons", label = L["Dungeons"], closed = state.folded["c:dungeons"] == true }
		if not state.folded["c:dungeons"] then
			for _, dungeon in ipairs(state.dungeons) do
				entries[#entries + 1] = state.places["d:" .. tostring(dungeon.name)]
			end
		end
	end
	return entries
end

-- focus: a place to scroll to.
local function DrawZones(offset, focus)
	local entries = ZoneEntries()
	if focus then
		for i, e in ipairs(entries) do
			if e.id == focus then
				offset = view.zones:Centered(i)
				break
			end
		end
	end
	view.zones:SetEntries(entries, offset)
end

local function FillZoneRow(row, e)
	local header = e.header == true
	row.Toggle:SetShown(header)
	row.Band:SetShown(header)
	if header then
		row.Toggle:SetTexture(e.closed and T.plus or T.minus)
		row.Name:SetText(GOLD .. e.label .. "|r")
		row.Range:SetText("")
		row.Count:SetText("")
		row.Picked:Hide()
		row.BarBack:Hide()
		row.Bar:Hide()
		return
	end
	row.Name:SetText(e.name)
	row.Range:SetText(Range(e))
	local done, total = CountOf(e)
	if total == 0 then
		row.Count:SetText(GREY .. "-|r") -- (nothing here for me)
		row.BarBack:Hide()
		row.Bar:Hide()
	else
		local all = done == total
		row.Count:SetText((all and HEX.done or "") .. L["%d of %d"]:format(done, total) .. (all and "|r" or ""))
		row.BarBack:Show()
		row.Bar:SetShown(done > 0)
		row.Bar:SetWidth(math.max(1, (row:GetWidth() - 24) * done / total))
		local c = all and TONE.done or TONE.available
		row.Bar:SetColorTexture(c[1], c[2], c[3], 0.8)
	end
	row.Picked:SetShown(e.id == state.where)
end

---------------------------------------------------------------------------
-- The middle: the tabs, the search's results
---------------------------------------------------------------------------

local function Searching()
	return state.query ~= "" and not state.drilled
end

local function SearchEntries()
	local entries = { { header = true, key = "search", search = true, label = L["Search results"], right = tostring(#state.results) } }
	for _, id in ipairs(state.results) do
		entries[#entries + 1] = { quest = id, result = true }
	end
	return entries
end

local function HeadText(place)
	local done, total = CountOf(place)
	local range = Range(place)
	return GOLD .. place.name .. "|r" .. (range ~= "" and ("  " .. GREY .. L["Level %s"]:format(range) .. "|r") or "")
		.. "   " .. L["%d of %d done"]:format(done, total)
end

local function Mode()
	return Searching() and "results" or state.tab
end

local function PaintTabs()
	for key, tab in pairs(view.tabs) do
		local on = key == state.tab and not Searching()
		tab.Line:SetShown(on)
		tab.Back:SetColorTexture(1, 0.82, 0, on and 0.14 or 0.04)
		tab.Text:SetTextColor(on and 1 or 0.75, on and 0.82 or 0.75, on and 0 or 0.75)
	end
end

-- keep: the chains stay where they're scrolled; focus: a quest to bring into sight.
local function DrawMiddle(keep, focus)
	state.draws = state.draws + 1
	local mode = Mode()
	view.g.frame:SetShown(mode == "chains")
	view.mapPane:SetShown(mode == "map")
	view.list.scroll:SetShown(mode == "results" or mode == "overview")
	view.Zoom:SetShown(mode == "chains" or mode == "map")
	view.Back:SetShown(state.query ~= "" and state.drilled)
	PaintTabs()
	local place = CurrentPlace()
	local message, head
	if mode == "results" then
		if #state.query < 2 and not tonumber(state.query) then
			view.list:SetEntries({}, 0)
			message = L["Type at least two letters."]
		else
			view.list:SetEntries(SearchEntries(), keep and true or 0)
			message = not state.results[1] and L["Nothing found"] or nil
		end
		head = GOLD .. L["Search results"] .. "|r"
	else
		head = place and HeadText(place) or ""
		if mode == "chains" then
			Graph.Draw(place, keep, focus)
			local lay = view.g.layout
			if place and not (lay and lay.cards[1]) then
				message = (lay and lay.hidden > 0) and L["Nothing to show with these filters."] or L["No quests known here yet."]
			end
			view.ZoomText:SetText(("%d%%"):format(math.floor(view.g.zoom * 100 + 0.5)))
		elseif mode == "overview" then
			local entries = place and Overview.Entries(place) or {}
			local offset = keep and true or 0
			if focus then
				for i, e in ipairs(entries) do
					if e.quest == focus then
						offset = view.list:Centered(i)
						break
					end
				end
			end
			view.list:SetEntries(entries, offset)
			if place and not entries[1] then
				message = L["Nothing to show with these filters."]
			end
		else
			Map.Draw(place)
			view.ZoomText:SetText(("%d%%"):format(math.floor(view.mapPane.map.zoom * 100 + 0.5)))
		end
	end
	view.Head:SetText(head)
	view.Message:SetText(message or "")
	view.Message:SetShown(message ~= nil)
end

local function FillListRow(row, e)
	local header = e.header == true
	row.Toggle:SetShown(header and not e.search)
	row.Band:SetShown(header)
	row.Icon:SetShown(not header)
	if header then
		row.Picked:Hide()
		row.Toggle:SetTexture(e.closed and T.plus or T.minus)
		local c = e.status and TONE[e.status]
		row.Name:SetText((c and Hex(c[1], c[2], c[3]) or GOLD) .. e.label .. "|r")
		row.Right:SetText(e.right or "")
		row.Name:ClearAllPoints()
		row.Name:SetPoint("LEFT", 20, 0)
		row.Name:SetPoint("RIGHT", -50, 0)
		return
	end
	local id = e.quest
	local q = Quest(id)
	local status = StatusOf(id)
	StartIcon(row.Icon, q, status)
	local c = TONE[status]
	row.Name:SetText(LevelTag(q) .. Hex(c[1], c[2], c[3]) .. Title(id) .. "|r")
	local right
	if e.result then
		right = q and ZoneOf(q)
	else
		right = q and OverviewRight(e, q)
	end
	row.Right:SetText(right and (GREY .. right .. "|r") or "")
	row.Picked:SetShown(id == state.picked)
	row.Name:ClearAllPoints()
	row.Name:SetPoint("LEFT", 24, 0)
	row.Name:SetPoint("RIGHT", right and -170 or -4, 0)
end

---------------------------------------------------------------------------
-- The right: the details
---------------------------------------------------------------------------

local function HasBit(mask, bit)
	return math.floor(mask / 2 ^ (bit - 1)) % 2 == 1
end

-- A race's name: Q.RaceInfo (Data.lua: Forever's races, the Skyborne too), the game's, classic's.
local function RaceName(id)
	if Q.RaceInfo then
		local ok, info = pcall(Q.RaceInfo, id)
		if ok and type(info) == "table" and type(info.name) == "string" then
			return info.name
		elseif ok and type(info) == "string" then
			return info
		end
	end
	local info = C_CreatureInfo and LT.Value(C_CreatureInfo.GetRaceInfo, id)
	return type(info) == "table" and type(info.raceName) == "string" and info.raceName or RACES[id]
end

-- The races of a mask: a whole side's classic races as that side (it counts for its new races too);
-- else each race whose bit is set (Q.Races: each race's mask bit; without it, bit = race ID).
local function RaceNames(mask)
	local classic = mask % 256
	for _, side in ipairs(SIDES) do
		if classic == side[1] then
			local name = side[2] == "Alliance" and _G.FACTION_ALLIANCE or _G.FACTION_HORDE
			return L["every %s race"]:format(type(name) == "string" and name or side[2])
		end
	end
	local names = {}
	local races = Q.Races and Q.Races()
	if type(races) == "table" and races[1] then
		for _, r in ipairs(races) do
			local id = r.id or r.raceID
			local bit = r.bit or r.maskBit or id
			if bit and HasBit(mask, bit) then
				names[#names + 1] = type(r.name) == "string" and r.name or RaceName(id) or ("#" .. tostring(id))
			end
		end
	else
		for id = 1, 8 do
			if HasBit(mask, id) then
				names[#names + 1] = RaceName(id)
			end
		end
	end
	return table.concat(names, ", ")
end

local function ClassNames(mask)
	local names = {}
	for id = 1, 11 do
		local file = CLASSES[id]
		if file and HasBit(mask, id) then
			local name = LT.Value(GetClassInfo, id)
			names[#names + 1] = LT.Window.ClassColorCode(file) .. (type(name) == "string" and name or (file:sub(1, 1) .. file:sub(2):lower())) .. "|r"
		end
	end
	return table.concat(names, ", ")
end

local function SkillName(id)
	local name = C_TradeSkillUI and LT.Value(C_TradeSkillUI.GetTradeSkillDisplayName, id)
	return type(name) == "string" and name ~= "" and name or SKILLS[id] or ("#" .. tostring(id))
end

local function Standing(value)
	local n = 1
	for i, s in ipairs(STANDINGS) do
		if value >= s[1] then
			n = i
		end
	end
	local label = _G["FACTION_STANDING_LABEL" .. n]
	return type(label) == "string" and label or STANDINGS[n][2]
end

local function FactionName(id)
	local data = C_Reputation and LT.Value(C_Reputation.GetFactionDataByID, id)
	return type(data) == "table" and type(data.name) == "string" and data.name or ("#" .. tostring(id))
end

local function Titles(ids)
	local names = {}
	for i, id in ipairs(ids) do
		if i > 4 then
			names[#names + 1] = "..."
			break
		end
		names[#names + 1] = Title(id)
	end
	return table.concat(names, ", ")
end

function Details.Requirements(q)
	local lines = {}
	if q.faction then
		local name = q.faction == "Alliance" and _G.FACTION_ALLIANCE or q.faction == "Horde" and _G.FACTION_HORDE or nil
		lines[#lines + 1] = L["Faction: %s"]:format(type(name) == "string" and name or q.faction)
	end
	if q.races then
		lines[#lines + 1] = L["Races: %s"]:format(RaceNames(q.races))
	end
	if q.classes then
		lines[#lines + 1] = L["Classes: %s"]:format(ClassNames(q.classes))
	end
	if q.skill and q.skill.id then
		lines[#lines + 1] = L["Skill: %s %d"]:format(SkillName(q.skill.id), q.skill.value or 0)
	end
	if q.rep and q.rep.faction then
		lines[#lines + 1] = L["Reputation: %s, %s"]:format(FactionName(q.rep.faction), Standing(q.rep.min or 0))
	end
	if q.breadcrumbFor then
		lines[#lines + 1] = L["Leads you to: %s"]:format(Title(q.breadcrumbFor))
	end
	if q.excl and q.excl[1] then
		lines[#lines + 1] = L["Taking it closes: %s"]:format(Titles(q.excl))
	end
	return lines[1] and table.concat(lines, "\n") or nil
end

local function StatusLine(q, status)
	if status == "level" and q.minLevel then
		return L["Needs level %d"]:format(q.minLevel)
	elseif status == "locked" then
		return L["Locked: an earlier quest comes first"]
	end
	return Word(status)
end

function Details.Summary(q, status)
	local lines = { HEX[status] .. StatusLine(q, status) .. "|r" }
	local code = LevelCode(q)
	if q.level and q.minLevel and q.minLevel ~= q.level then
		lines[#lines + 1] = code .. L["Level %d, from level %d"]:format(q.level, q.minLevel) .. "|r"
	elseif q.level or q.minLevel then
		lines[#lines + 1] = code .. L["Level %d"]:format(q.level or q.minLevel) .. "|r"
	end
	local zone = ZoneOf(q)
	if zone then
		lines[#lines + 1] = zone
	end
	local step, total, name = StepOf(q.id)
	if step then
		lines[#lines + 1] = L["Step %d of %d"]:format(step, total) .. (name and (GREY .. " - " .. name .. "|r") or "")
	end
	local tags = {}
	if q.new then
		tags[#tags + 1] = L["New in WoW: Forever"]
	end
	if q.repeatable then
		tags[#tags + 1] = L["Repeatable"]
	end
	if q.source == "learned" then
		tags[#tags + 1] = L["Learned while playing"]
	end
	if tags[1] then
		lines[#lines + 1] = "|cff80c0ff" .. table.concat(tags, ", ") .. "|r"
	end
	return table.concat(lines, "\n")
end

-- A map pin there (the game's own waypoint, super-tracked): nothing of the world map is touched.
local function SetPin(map, x, y, name)
	if not (map and x and y and C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
		return false
	end
	if C_Map.CanSetUserWaypointOnMap and not LT.Value(C_Map.CanSetUserWaypointOnMap, map) then
		return false
	end
	local ok = pcall(function()
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x, y))
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
			C_SuperTrack.SetSuperTrackedUserWaypoint(true)
		end
	end)
	if ok then
		LT.Print(("Questtree: map pin set at %s (%s)."):format(name or "?", MapName(map) or "?"))
	end
	return ok
end

-- The places a quest starts and ends at: a line (a button: it puts a map pin there) per giver, ender
-- and, for an item, each place it drops (from what, how often).
function Details.PlaceLines(q)
	local lines = {}
	local function Add(kind, text, point, name)
		lines[#lines + 1] = { kind = kind, text = text, point = point, name = name }
	end
	for k, list in ipairs({ q.starts or EMPTY, q.ends or EMPTY }) do
		local kind = k == 1 and "start" or "end"
		for i, s in ipairs(list) do
			if i > SHOWN.places then
				Add(kind, GREY .. L["... and %d more"]:format(#list - SHOWN.places) .. "|r")
				break
			end
			local point = s.points and s.points[1]
			local zone = point and MapName(point.map)
			Add(kind, StartWord(s) .. (zone and (GREY .. " - " .. zone .. "|r") or ""), point, s.name)
			for j, d in ipairs(k == 1 and s.drops or EMPTY) do
				if j > SHOWN.drops then
					break
				end
				local dp = d.points and d.points[1]
				local dz = dp and MapName(dp.map)
				local text = d.kind == "object" and L["In %s (%s%%)"] or L["Drops from %s (%s%%)"]
				Add("drop", "   " .. text:format(d.name or "?", Chance(d.chance)) .. (dz and (GREY .. " - " .. dz .. "|r") or ""), dp, d.name)
			end
		end
	end
	return lines
end

-- The small map: the first giver's map (else a drop's, else the first ender's), and every spot on it.
function Details.MapSpots(q)
	local map
	for _, list in ipairs({ q.starts or EMPTY, q.ends or EMPTY }) do
		for _, s in ipairs(list) do
			local point = s.points and s.points[1]
			map = map or (point and point.map)
			for _, d in ipairs(not map and s.drops or EMPTY) do
				local dp = d.points and d.points[1]
				map = map or (dp and dp.map)
			end
		end
	end
	if not map then
		return nil
	end
	local spots = {}
	for k, list in ipairs({ q.starts or EMPTY, q.ends or EMPTY }) do
		local n = 0
		for _, s in ipairs(list) do
			for _, p in ipairs(s.points or EMPTY) do
				if p.map == map and n < SHOWN.points then
					n = n + 1
					spots[#spots + 1] = { x = p.x, y = p.y, look = k == 1 and "start" or "end", label = s.name,
						note = k == 1 and L["Quest giver"] or L["Turn-in"] }
				end
			end
			for _, d in ipairs(k == 1 and s.drops or EMPTY) do
				for _, p in ipairs(d.points or EMPTY) do
					if p.map == map then
						spots[#spots + 1] = { x = p.x, y = p.y, r = p.r, look = "drop", label = L["%s drops here (%s%%)"]:format(s.name or "?", Chance(d.chance)),
							note = d.name }
					end
				end
			end
		end
	end
	return map, spots
end

function Details.FriendsLine(id)
	local list = Q.Friends and Q.Friends(id) or EMPTY
	if not list[1] then
		return nil
	end
	local names = {}
	for i, f in ipairs(list) do
		if i > SHOWN.friends then
			names[#names + 1] = GREY .. L["... and %d more"]:format(#list - SHOWN.friends) .. "|r"
			break
		end
		local status = TONE[f.status] and f.status or "other"
		names[#names + 1] = LT.Window.ClassColorCode(f.classFile) .. (f.name or "?") .. "|r " .. HEX[status] .. "(" .. Word(status) .. ")|r"
	end
	return table.concat(names, ", ")
end

-- A text in the details' column at y; the next y.
local function Put(fs, text, y, gap)
	if not text or text == "" then
		fs:Hide()
		return y
	end
	fs:SetText(text)
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", 0, -y)
	fs:Show()
	return y + fs:GetStringHeight() + gap
end

-- A section's header (gold, a divider under it).
local function PutHead(h, text, y)
	if not text then
		h:Hide()
		return y
	end
	h.Text:SetText(text)
	h:ClearAllPoints()
	h:SetPoint("TOPLEFT", 0, -y)
	h:Show()
	return y + 20
end

local function FillLink(b, id)
	local q = Quest(id)
	local status = StatusOf(id)
	b.quest = id
	StartIcon(b.Icon, q, status)
	local zone = q and ZoneOf(q)
	local here = CurrentPlace()
	local other = zone and here and zone ~= here.name
	local c = TONE[status]
	b.Text:SetText(LevelTag(q) .. Hex(c[1], c[2], c[3]) .. Title(id) .. "|r" .. (other and (" " .. GREY .. "- " .. zone .. "|r") or ""))
end

-- "Needs first:" or "Leads to:" and a button per quest; used: the link buttons taken so far.
function Details.PutLinks(head, more, label, list, y, used)
	if not list[1] then
		head:Hide()
		more:Hide()
		return y, used
	end
	y = PutHead(head, label, y)
	local shown = 0
	for _, item in ipairs(list) do
		if shown >= SHOWN.links then
			break
		end
		local id = type(item) == "table" and item.id or item
		if id then
			used, shown = used + 1, shown + 1
			local b = view.d.Link(used)
			FillLink(b, id)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", 0, -y)
			b:Show()
			y = y + LINK_H
		end
	end
	if #list > shown then
		y = Put(more, GREY .. L["... and %d more"]:format(#list - shown) .. "|r", y, 2)
	else
		more:Hide()
	end
	return y + 8, used
end

function Details.PutPlaces(q, y)
	local d = view.d
	local lines = Details.PlaceLines(q)
	local used = 0
	local lastKind
	local heads = { start = d.StartsHead, ["end"] = d.EndsHead }
	d.StartsHead:Hide()
	d.EndsHead:Hide()
	for _, line in ipairs(lines) do
		local kind = line.kind == "drop" and "start" or line.kind
		if kind ~= lastKind then
			lastKind = kind
			y = PutHead(heads[kind], kind == "start" and L["Starts at"] or L["Turn in at"], y)
		end
		used = used + 1
		local b = d.Place(used)
		b.point, b.name = line.point, line.name
		b.Text:SetText(line.text)
		if line.kind == "drop" then
			b.Icon:SetTexture(T.circle)
			b.Icon:SetTexCoord(0, 1, 0, 1)
			b.Icon:SetVertexColor(1, 0.82, 0, 0.7)
		else
			Art(b.Icon, line.kind == "start" and "QuestNormal" or "QuestTurnin", line.kind == "start" and T.available or T.turnin)
			b.Icon:SetVertexColor(1, 1, 1, 1)
		end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 0, -y)
		b:Show()
		y = y + LINK_H
	end
	for i = used + 1, #d.places do
		d.places[i].point = nil
		d.places[i]:Hide()
	end
	return used > 0 and y + 8 or y
end

function Details.PutMap(q, y)
	local d = view.d
	local map, spots = Details.MapSpots(q)
	if not (map and spots[1]) then
		d.map.frame:Hide()
		return y
	end
	d.map.frame:ClearAllPoints()
	d.map.frame:SetPoint("TOPLEFT", 0, -y)
	Map.Show(d.map, map, spots)
	return y + d.map.height + 10
end

-- top: a new quest, shown from its top (else a refresh keeps the place).
local function FillDetails(top)
	local d = view.d
	local id = state.picked
	local q = Quest(id)
	d.Hint:SetShown(q == nil)
	d.Body:SetShown(q ~= nil)
	d.Small:SetShown(q ~= nil and Q.ShowQuest ~= nil)
	if not q then
		for _, b in ipairs(d.links) do
			b.quest = nil
			b:Hide()
		end
		d.map.frame:Hide()
		return
	end
	local status = StatusOf(id)
	local y = Put(d.Title, LevelTag(q) .. Title(id), 0, 4)
	y = Put(d.Sub, Details.Summary(q, status), y, 10)
	y = Details.PutPlaces(q, y)
	y = Details.PutMap(q, y)
	local req = Details.Requirements(q)
	y = PutHead(d.ReqHead, req and L["Requirements"] or nil, y)
	y = Put(d.Req, req, y, 10)
	local used = 0
	y, used = Details.PutLinks(d.NeedsHead, d.NeedsMore, L["Needs first:"], Q.Missing and Q.Missing(id) or EMPTY, y, used)
	y, used = Details.PutLinks(d.LeadsHead, d.LeadsMore, L["Leads to:"], Q.Opens and Q.Opens(id) or EMPTY, y, used)
	for i = used + 1, #d.links do
		d.links[i].quest = nil
		d.links[i]:Hide()
	end
	local friends = Details.FriendsLine(id)
	y = PutHead(d.FriendsHead, friends and L["Friends"] or nil, y)
	y = Put(d.Friends, friends, y, 8)
	d.Body:SetHeight(math.max(1, y))
	if top then
		d.Scroll:SetVerticalScroll(0)
	end
end

---------------------------------------------------------------------------
-- Choosing
---------------------------------------------------------------------------

local function SmallOpen()
	return Q.IsSmallShown ~= nil and Q.IsSmallShown() == true
end

-- A quest into the details (user: a click, which the small window follows while it's open).
local function Pick(id, user)
	local changed = id ~= state.picked
	state.picked = id
	if view.g.frame:IsShown() then
		Graph.Refill()
	end
	if view.list.scroll:IsShown() then
		view.list:Lay()
	end
	if view.mapPane:IsShown() then
		Map.Repaint(view.mapPane.map)
	end
	FillDetails(changed)
	if user and Q.ShowQuest and SmallOpen() then
		Q.ShowQuest(id)
	end
end

function Graph.Pick(id)
	Pick(id, true)
end

local function SelectPlace(id)
	if state.query ~= "" then
		state.drilled = true
	end
	state.where = id
	view.zones:Lay()
	DrawMiddle(false)
	if view.d.Body:IsShown() then
		FillDetails() -- (its links say which zone they're in)
	end
end

-- A quest anywhere: its zone (or dungeon) on the left, its chain open and in sight, the details.
local function Open(id, user)
	local q = Quest(id)
	if not q then
		return
	end
	Lists()
	local target = PlaceOf(q, id)
	if state.query ~= "" then
		state.drilled = true
	end
	local moved = target ~= nil and target ~= state.where
	if target then
		state.where = target
		local place = state.places[target]
		state.folded[place.kind == "zone" and ("c:" .. tostring(place.continent)) or "c:dungeons"] = nil
		local group = Structure(place).groupOf[id]
		if group and state.folded[group.key] then
			state.folded[group.key] = nil
			state.layouts[target] = nil
		end
	end
	state.picked = nil
	if moved then
		DrawZones(true, target)
	else
		view.zones:Lay()
	end
	if state.tab == "map" then
		state.tab = "chains" -- (a quest is found in its chain)
		Save()
	end
	DrawMiddle(not moved, id)
	Pick(id, user)
end

local function BackToResults()
	state.drilled = false
	DrawMiddle(false)
end

local function SetTab(tab)
	if state.query ~= "" and not state.drilled then
		state.drilled = true -- (a tab clicked during a search: the place, the search stays)
	end
	state.tab = tab
	Save()
	DrawMiddle(false, state.picked)
end

local function SetFilter(key, on)
	filters[key] = on
	Save()
	wipe(state.layouts)
	view.filters[key].Tick:SetShown(on)
	DrawMiddle(true)
end

---------------------------------------------------------------------------
-- The search, and what comes later
---------------------------------------------------------------------------

local function Search(text)
	local ids, seen = {}, {}
	local n = tonumber(text)
	if n and Quest(n) then
		ids[1], seen[n] = n, true
	end
	if #text >= 2 and Q.Search then
		for _, id in ipairs(Q.Search(text) or EMPTY) do
			if not seen[id] then
				seen[id] = true
				ids[#ids + 1] = id
			end
		end
	end
	return ids
end

local function RunSearch(text)
	state.query, state.drilled = text, false
	state.results = Search(text)
	DrawMiddle(false)
end

-- Emptied: back to the place, at once (the place clicked last stays).
local function EndSearch()
	state.searchAt = nil
	if state.query == "" then
		return
	end
	state.query, state.drilled, state.results = "", false, nil
	DrawMiddle(false, state.picked)
end

-- Everything drawn again from the data (it changed, or the window opens).
local function DrawAll()
	Lists()
	if not (state.where and state.places[state.where]) then
		state.where = DefaultPlace()
	end
	if state.query ~= "" and not state.results then
		state.results = Search(state.query)
	end
	DrawZones(true)
	DrawMiddle(true)
	FillDetails()
end

local function RunDue(self)
	local now = GetTime()
	if state.searchAt and now >= state.searchAt then
		state.searchAt = nil
		local text = strtrim(view.Box:GetText() or "")
		if text ~= "" and text ~= state.query then
			RunSearch(text)
		end
	end
	if state.dataOld then
		state.dataOld, state.statusOld = false, false
		state.nextRefresh = now + REFRESH_GAP
		Forget()
		DrawAll()
	end
	if state.statusOld and now >= state.nextRefresh then
		state.statusOld = false
		state.nextRefresh = now + REFRESH_GAP
		wipe(state.layouts) -- (statuses changed: what the filters show, the lines' colours)
		view.zones:Lay()
		DrawMiddle(true)
		FillDetails()
	end
	if state.namesAt and now >= state.namesAt then
		state.namesAt = nil
		if view.g.frame:IsShown() then
			Graph.Refill()
		end
		if view.list.scroll:IsShown() then
			view.list:Lay()
		end
		FillDetails()
	end
	if not (state.searchAt or state.statusOld or state.namesAt) then
		self:SetScript("OnUpdate", nil)
	end
end

local function Due()
	if frame then
		frame:SetScript("OnUpdate", RunDue) -- (only while something is due, only while it's open)
	end
end

-- A quest turned in: only its places' counts are counted again.
local function ForgetCounts(id)
	local q = not LT.IsSecret(id) and Quest(id)
	if not q then
		wipe(state.counts)
		return
	end
	state.counts["z:" .. tostring(q.zone)] = nil
	state.counts["d:" .. tostring(q.dungeon)] = nil
end

local EVENTS = { "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_LEVEL_UP", "QUEST_DATA_LOAD_RESULT" }

local function OnEvent(_, event, id)
	if event == "QUEST_DATA_LOAD_RESULT" then
		if LT.IsSecret(id) or not state.waiting[id] then
			return
		end
		state.waiting[id] = nil
		state.namesAt = state.namesAt or GetTime() + NAMES_GAP
	else
		if event == "QUEST_TURNED_IN" then
			ForgetCounts(id)
		elseif event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" then
			wipe(state.counts) -- (taking one can close others: Q.ZoneCount's total)
		end
		state.statusOld = true
	end
	Due()
end

-- Q.OnDataChanged: learned quests, the data loaded. Open: redrawn on the next frame; closed: when it opens.
local function DataChanged()
	state.dataOld = true
	if frame and frame:IsShown() then
		Due()
	end
end

---------------------------------------------------------------------------
-- The frames
---------------------------------------------------------------------------

local function NewRowBase(parent, width)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(width, ROW_H)
	row:SetHighlightTexture(T.highlight, "ADD")
	row.Band = row:CreateTexture(nil, "BACKGROUND")
	row.Band:SetAllPoints()
	row.Band:SetColorTexture(1, 0.82, 0, 0.08)
	row.Picked = row:CreateTexture(nil, "BACKGROUND")
	row.Picked:SetAllPoints()
	row.Picked:SetColorTexture(1, 0.82, 0, 0.2)
	row.Picked:Hide()
	row.Toggle = row:CreateTexture(nil, "ARTWORK")
	row.Toggle:SetSize(14, 14)
	row.Toggle:SetPoint("LEFT", 2, 0)
	row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.Name:SetJustifyH("LEFT")
	row.Name:SetWordWrap(false)
	return row
end

local function NewZoneRow(parent, width)
	local row = NewRowBase(parent, width)
	row.Name:SetPoint("LEFT", 20, 1)
	row.Name:SetPoint("RIGHT", -106, 1)
	row.Count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Count:SetPoint("RIGHT", -4, 1)
	row.Count:SetWidth(62)
	row.Count:SetJustifyH("RIGHT")
	row.Range = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.Range:SetPoint("RIGHT", -68, 1)
	row.Range:SetWidth(36)
	row.Range:SetJustifyH("RIGHT")
	row.BarBack = row:CreateTexture(nil, "ARTWORK")
	row.BarBack:SetPoint("BOTTOMLEFT", 20, 1)
	row.BarBack:SetPoint("BOTTOMRIGHT", -4, 1)
	row.BarBack:SetHeight(2)
	row.BarBack:SetColorTexture(1, 1, 1, 0.08)
	row.Bar = row:CreateTexture(nil, "ARTWORK", nil, 1)
	row.Bar:SetPoint("BOTTOMLEFT", 20, 1)
	row.Bar:SetHeight(2)
	row:SetScript("OnClick", function(self)
		local e = self.entry
		if not e then
			return
		elseif e.header then
			state.folded[e.key] = not state.folded[e.key] or nil
			DrawZones(true)
		else
			SelectPlace(e.id)
		end
	end)
	return row
end

local function ListTip(self)
	local e = self.entry
	if e and e.quest then
		QuestTip(self, e.quest)
	end
end

local function NewListRow(parent, width)
	local row = NewRowBase(parent, width)
	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(16, 16)
	row.Icon:SetPoint("LEFT", 4, 0)
	row.Right = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.Right:SetPoint("RIGHT", -4, 0)
	row.Right:SetWidth(160)
	row.Right:SetJustifyH("RIGHT")
	row.Right:SetWordWrap(false)
	row:SetScript("OnEnter", ListTip)
	row:SetScript("OnLeave", Untip)
	row:SetScript("OnClick", function(self)
		local e = self.entry
		if not e then
			return
		elseif e.header then
			if not e.search then
				state.folded[e.key] = not state.folded[e.key] -- (false: opened, the done ones too)
				DrawMiddle(true)
			end
		elseif e.result then
			Open(e.quest, true) -- (its zone's chains, inside the search)
		else
			Pick(e.quest, true)
		end
	end)
	return row
end

local function NewLink(parent, width)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, LINK_H)
	b:SetHighlightTexture(T.highlight, "ADD")
	b.Icon = b:CreateTexture(nil, "ARTWORK")
	b.Icon:SetSize(14, 14)
	b.Icon:SetPoint("LEFT", 2, 0)
	b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.Text:SetPoint("LEFT", 20, 0)
	b.Text:SetPoint("RIGHT", -2, 0)
	b.Text:SetJustifyH("LEFT")
	b.Text:SetWordWrap(false)
	b:Hide()
	return b
end

local function PlaceTip(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(self.name or self.Text:GetText() or "", 1, 1, 1)
	if self.point then
		GameTooltip:AddLine(("%s  %.1f, %.1f"):format(MapName(self.point.map) or "?", self.point.x * 100, self.point.y * 100), 0.8, 0.8, 0.8)
		GameTooltip:AddLine(L["Click: put a map pin there"], 0.5, 0.75, 1)
	end
	GameTooltip:Show()
end

local function NewHead(parent, width)
	local h = CreateFrame("Frame", nil, parent)
	h:SetSize(width, 18)
	h.Text = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	h.Text:SetPoint("TOPLEFT")
	local line = h:CreateTexture(nil, "ARTWORK")
	Art(line, "Options_HorizontalDivider", T.flat)
	if not atlasKnown.Options_HorizontalDivider then
		line:SetVertexColor(1, 0.82, 0, 0.25)
	end
	line:SetPoint("BOTTOMLEFT", 0, 1)
	line:SetPoint("BOTTOMRIGHT", 0, 1)
	line:SetHeight(1)
	h:Hide()
	return h
end

local function BuildDetails(root, x, y, width, height)
	local d = { links = {}, places = {} }
	view.d = d
	local panel = CreateFrame("Frame", nil, root)
	panel:SetPoint("TOPLEFT", x, -y)
	panel:SetSize(width, height)
	d.Panel = panel
	d.Hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	d.Hint:SetPoint("TOPLEFT", 4, -8)
	d.Hint:SetWidth(width - 8)
	d.Hint:SetJustifyH("LEFT")
	d.Hint:SetText(L["Click a quest to see it here."])
	local bodyW = width - BAR_W
	d.Scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
	d.Scroll:SetPoint("TOPLEFT", 0, 0)
	d.Scroll:SetSize(bodyW, height - 34)
	d.Body = CreateFrame("Frame", nil, d.Scroll)
	d.Body:SetSize(bodyW, 1)
	d.Scroll:SetScrollChild(d.Body)
	local function Text(font)
		local fs = d.Body:CreateFontString(nil, "OVERLAY", font)
		fs:SetWidth(bodyW - 4)
		fs:SetJustifyH("LEFT")
		fs:SetJustifyV("TOP")
		fs:SetSpacing(2)
		return fs
	end
	d.Title = Text("GameFontNormalLarge")
	d.Sub = Text("GameFontHighlight")
	d.Req = Text("GameFontHighlightSmall")
	d.NeedsMore, d.LeadsMore = Text("GameFontHighlightSmall"), Text("GameFontHighlightSmall")
	d.Friends = Text("GameFontHighlightSmall")
	d.StartsHead, d.EndsHead = NewHead(d.Body, bodyW - 4), NewHead(d.Body, bodyW - 4)
	d.ReqHead, d.NeedsHead = NewHead(d.Body, bodyW - 4), NewHead(d.Body, bodyW - 4)
	d.LeadsHead, d.FriendsHead = NewHead(d.Body, bodyW - 4), NewHead(d.Body, bodyW - 4)
	d.map = Map.New(d.Body, bodyW - 4, math.floor((bodyW - 4) * 2 / 3), false)
	function d.Link(i)
		local b = d.links[i]
		if not b then
			b = NewLink(d.Body, bodyW - 4)
			b:SetScript("OnEnter", function(self) QuestTip(self, self.quest) end)
			b:SetScript("OnLeave", Untip)
			b:SetScript("OnClick", function(self)
				if self.quest then
					Untip(self)
					Open(self.quest, true)
				end
			end)
			d.links[i] = b
		end
		return b
	end
	function d.Place(i)
		local b = d.places[i]
		if not b then
			b = NewLink(d.Body, bodyW - 4)
			b:SetScript("OnEnter", PlaceTip)
			b:SetScript("OnLeave", Untip)
			b:SetScript("OnClick", function(self)
				if self.point then
					SetPin(self.point.map, self.point.x, self.point.y, self.name)
				end
			end)
			d.places[i] = b
		end
		return b
	end
	d.Small = LT.Window.AddButton(panel, L["Show in the small window"], function()
		if state.picked and Q.ShowQuest then
			Q.ShowQuest(state.picked)
		end
	end, { "BOTTOMLEFT", panel, "BOTTOMLEFT", 2, 4 })
	d.Small:SetSize(math.min(width - 4, 220), 22)
	d.Small:Hide()
	d.Body:Hide()
end

local function OnSearchTyped(box)
	local text = strtrim(box:GetText() or "")
	view.Clear:SetShown(text ~= "")
	if text == "" then
		EndSearch()
	elseif text ~= state.query then
		state.searchAt = GetTime() + SEARCH_GAP
		Due()
	else
		state.searchAt = nil
	end
end

-- A checkbox of ours (a Button: the controller reaches it; no Blizzard template).
local function NewFilter(parent, key, label, tip)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(24, 24)
	b.Box = b:CreateTexture(nil, "ARTWORK")
	b.Box:SetTexture(T.box)
	b.Box:SetSize(24, 24)
	b.Box:SetPoint("LEFT")
	b.Tick = b:CreateTexture(nil, "OVERLAY")
	b.Tick:SetTexture(T.tick)
	b.Tick:SetAllPoints(b.Box)
	b.Tick:SetShown(filters[key])
	b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.Text:SetPoint("LEFT", 24, 0)
	b.Text:SetText(label)
	b:SetWidth(24 + b.Text:GetStringWidth() + 6)
	b:SetHighlightTexture(T.highlight, "ADD")
	b:SetScript("OnClick", function()
		SetFilter(key, not filters[key])
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(label, 1, 0.82, 0)
		GameTooltip:AddLine(tip, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", Untip)
	return b
end

local function BuildTop()
	local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("TOPLEFT", 16, -37)
	label:SetText(L["Search all zones:"])
	local box = CreateFrame("EditBox", nil, frame)
	view.Box = box
	box:SetSize(240, 22)
	box:SetPoint("LEFT", label, "RIGHT", 8, 0)
	box:SetAutoFocus(false)
	box:SetFontObject("ChatFontNormal")
	box:SetMaxLetters(40)
	if box.SetTextInsets then
		box:SetTextInsets(6, 20, 0, 0)
	end
	local back = box:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.55)
	local edge = box:CreateTexture(nil, "BORDER")
	edge:SetPoint("BOTTOMLEFT")
	edge:SetPoint("BOTTOMRIGHT")
	edge:SetHeight(1)
	edge:SetColorTexture(1, 0.82, 0, 0.5)
	view.Clear = CreateFrame("Button", nil, box, "UIPanelCloseButtonNoScripts")
	view.Clear:SetSize(20, 20)
	view.Clear:SetPoint("RIGHT", 0, 0)
	view.Clear:SetScript("OnClick", function()
		box:SetText("")
		box:ClearFocus()
		OnSearchTyped(box)
	end)
	view.Clear:Hide()
	box:SetScript("OnTextChanged", OnSearchTyped)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	-- The filters, on the right.
	view.filters = {
		hideDone = NewFilter(frame, "hideDone", L["Hide done"], L["Quests you've done aren't shown (a chain's line passes through them)."]),
		onlyAvailable = NewFilter(frame, "onlyAvailable", L["Only available now"], L["Only the quests you can take right now."]),
		showOther = NewFilter(frame, "showOther", L["Show quests not for you"], L["Also the quests for another race, class or faction (dimmed)."]),
	}
	local x = -16
	for _, key in ipairs({ "showOther", "onlyAvailable", "hideDone" }) do
		local b = view.filters[key]
		b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", x, -36)
		x = x - b:GetWidth() - 12
	end
	view.Search = { label, box, view.filters.hideDone, view.filters.onlyAvailable, view.filters.showOther }
end

local function NewTab(parent, key, label, x)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(96, TABS_H - 4)
	b:SetPoint("TOPLEFT", x, 0)
	b.Back = b:CreateTexture(nil, "BACKGROUND")
	b.Back:SetAllPoints()
	b.Line = b:CreateTexture(nil, "ARTWORK")
	b.Line:SetPoint("BOTTOMLEFT")
	b.Line:SetPoint("BOTTOMRIGHT")
	b.Line:SetHeight(2)
	b.Line:SetColorTexture(1, 0.82, 0, 1)
	b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	b.Text:SetPoint("CENTER", 0, 1)
	b.Text:SetText(label)
	b:SetHighlightTexture(T.highlight, "ADD")
	b:SetScript("OnClick", function()
		SetTab(key)
	end)
	return b
end

-- -, the zoom, +, Fit: the chains' zoom, or the map's.
local function BuildZoom(parent)
	local z = CreateFrame("Frame", nil, parent)
	z:SetSize(170, TABS_H - 4)
	view.Zoom = z
	local function Step(dir)
		if state.tab == "map" then
			local m = view.mapPane.map
			Map.SetZoom(m, m.zoom * (dir > 0 and G.MAP_STEP or 1 / G.MAP_STEP))
			view.ZoomText:SetText(("%d%%"):format(math.floor(m.zoom * 100 + 0.5)))
		else
			Graph.SetZoom(view.g.zoom + dir * G.ZOOM_STEP)
		end
	end
	local minus = LT.Window.AddButton(z, "-", function() Step(-1) end, { "LEFT", z, "LEFT", 0, 0 })
	minus:SetSize(26, 22)
	view.ZoomText = z:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	view.ZoomText:SetPoint("LEFT", minus, "RIGHT", 4, 0)
	view.ZoomText:SetWidth(40)
	local plus = LT.Window.AddButton(z, "+", function() Step(1) end, { "LEFT", view.ZoomText, "RIGHT", 4, 0 })
	plus:SetSize(26, 22)
	local fit = LT.Window.AddButton(z, L["Fit"], function()
		if state.tab == "map" then
			Map.SetZoom(view.mapPane.map, 1)
			view.ZoomText:SetText("100%")
		else
			Graph.Fit()
		end
	end, { "LEFT", plus, "RIGHT", 4, 0 })
	fit:SetSize(56, 22)
	view.ZoomButtons = { minus = minus, plus = plus, fit = fit }
end

-- The chains' viewport: our own scrolling (wheel up and down, Shift: sideways, Ctrl: zoom; dragging
-- moves it), a frame that clips the canvas.
local function BuildGraph(parent, x, y, w, h)
	local g = { w = w, h = h, sx = 0, sy = 0, zoom = 1, cards = {}, freeCards = {}, banners = {}, freeBanners = {}, lines = {},
		pills = {}, made = 0, lays = 0, linesShown = 0 }
	view.g = g
	local f = CreateFrame("Frame", nil, parent)
	f:SetPoint("TOPLEFT", x, -y)
	f:SetSize(w, h)
	f:SetClipsChildren(true)
	local back = f:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.3)
	f:EnableMouse(true)
	f:EnableMouseWheel(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnMouseWheel", function(_, delta)
		if IsControlKeyDown and IsControlKeyDown() then
			Graph.SetZoom(g.zoom + (delta > 0 and G.ZOOM_STEP or -G.ZOOM_STEP))
		elseif IsShiftKeyDown and IsShiftKeyDown() then
			Graph.ScrollTo(g.sx - delta * (G.W + G.HGAP) / 2, g.sy)
		else
			Graph.ScrollTo(g.sx, g.sy - delta * G.PY)
		end
	end)
	f:SetScript("OnDragStart", function(self)
		local cx, cy = GetCursorPosition()
		g.drag = { cx, cy, g.sx, g.sy, self:GetEffectiveScale() * g.zoom }
		self:SetScript("OnUpdate", function()
			local d = g.drag
			if not d then
				return
			end
			local nx, ny = GetCursorPosition()
			Graph.ScrollTo(d[3] - (nx - d[1]) / d[5], d[4] + (ny - d[2]) / d[5])
		end)
	end)
	f:SetScript("OnDragStop", function(self)
		g.drag = nil
		self:SetScript("OnUpdate", nil)
	end)
	g.frame = f
	g.canvas = CreateFrame("Frame", nil, f)
	g.canvas:SetPoint("TOPLEFT")
	g.canvas:SetSize(1, 1)
	g.HThumb = f:CreateTexture(nil, "OVERLAY")
	g.HThumb:SetHeight(4)
	g.HThumb:SetColorTexture(1, 0.82, 0, 0.45)
	g.HThumb:Hide()
	g.VThumb = f:CreateTexture(nil, "OVERLAY")
	g.VThumb:SetWidth(4)
	g.VThumb:SetColorTexture(1, 0.82, 0, 0.45)
	g.VThumb:Hide()
end

local function BuildMapPane(parent, x, y, w, h)
	local mp = CreateFrame("Frame", nil, parent)
	mp:SetPoint("TOPLEFT", x, -y)
	mp:SetSize(w, h)
	view.mapPane = mp
	mp.map = Map.New(mp, w, h - 22, true)
	mp.map.frame:SetPoint("TOPLEFT")
	mp.map.onClick = function(id)
		Pick(id, true)
	end
	mp.map.onZoom = function(zoom)
		view.ZoomText:SetText(("%d%%"):format(math.floor(zoom * 100 + 0.5)))
	end
	mp.Note = mp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	mp.Note:SetPoint("BOTTOMLEFT", 4, 4)
	mp.Note:SetPoint("BOTTOMRIGHT", -4, 4)
	mp.Note:SetJustifyH("LEFT")
	mp:Hide()
end

-- The legend under the middle: the statuses' colours, and what the map's markers mean.
local function BuildLegend(parent, x, y, w)
	local parts = {}
	for _, status in ipairs({ "done", "active", "available", "locked", "level", "other" }) do
		parts[#parts + 1] = HEX[status] .. "|T" .. T.flat .. ":10:10|t " .. Word(status) .. "|r"
	end
	view.Legend = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	view.Legend:SetPoint("TOPLEFT", x + 4, -y)
	view.Legend:SetWidth(w - 8)
	view.Legend:SetJustifyH("LEFT")
	view.Legend:SetWordWrap(false)
	view.Legend:SetText(table.concat(parts, "   "))
end

local function Build()
	frame = LT.Window.Create("LefthyToolsQuesttreeBrowser", "Questtree", WIDTH, HEIGHT)
	view = {}
	LoadSaved()
	local width, height = WIDTH - INSET_W, HEIGHT - INSET_H
	local root = CreateFrame("Frame", nil, frame.Inset)
	root:SetPoint("TOPLEFT")
	root:SetSize(width, height)
	view.root = root
	BuildTop()
	local paneH = height - 2 * PAD
	view.zones = NewList(root, PAD, PAD, ZONES_W - BAR_W, paneH, NewZoneRow, FillZoneRow)
	local middleX = PAD + ZONES_W + GAP
	local detailX = width - PAD - EDGE - DETAILS_W
	local middleW = detailX - GAP - middleX
	view.Head = root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	view.Head:SetPoint("TOPLEFT", middleX + 4, -PAD - 5)
	view.Head:SetWidth(middleW - 8)
	view.Head:SetJustifyH("LEFT")
	view.Head:SetWordWrap(false)
	-- Tabs, the way back to the results, the zoom.
	local tabs = CreateFrame("Frame", nil, root)
	tabs:SetPoint("TOPLEFT", middleX, -PAD - HEAD_H)
	tabs:SetSize(middleW, TABS_H)
	view.tabs = {
		chains = NewTab(tabs, "chains", L["Chains"], 0),
		overview = NewTab(tabs, "overview", L["Overview"], 100),
		map = NewTab(tabs, "map", L["Map"], 200),
	}
	BuildZoom(tabs)
	view.Zoom:SetPoint("TOPRIGHT", tabs, "TOPRIGHT", 0, 0)
	view.Back = CreateFrame("Button", nil, tabs)
	view.Back:SetSize(190, TABS_H - 4)
	view.Back:SetPoint("TOPLEFT", 306, 0)
	view.Back.Icon = view.Back:CreateTexture(nil, "ARTWORK")
	view.Back.Icon:SetTexture(T.back)
	view.Back.Icon:SetSize(18, 18)
	view.Back.Icon:SetPoint("LEFT")
	view.Back.Text = view.Back:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	view.Back.Text:SetPoint("LEFT", 20, 0)
	view.Back.Text:SetText(L["Back to the search results"])
	view.Back:SetHighlightTexture(T.highlight, "ADD")
	view.Back:SetScript("OnClick", BackToResults)
	view.Back:Hide()
	local contentY = PAD + HEAD_H + TABS_H
	local contentH = paneH - HEAD_H - TABS_H - LEGEND_H
	BuildGraph(root, middleX, contentY, middleW, contentH)
	BuildMapPane(root, middleX, contentY, middleW, contentH)
	view.list = NewList(root, middleX, contentY, middleW - BAR_W, contentH, NewListRow, FillListRow)
	view.list.scroll:Hide()
	BuildLegend(root, middleX, contentY + contentH + 5, middleW)
	view.Message = root:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	view.Message:SetPoint("TOPLEFT", middleX + 12, -contentY - 14)
	view.Message:SetWidth(middleW - 24)
	view.Message:SetJustifyH("LEFT")
	view.Message:Hide()
	for _, x in ipairs({ middleX - GAP / 2, detailX - GAP / 2 }) do
		local split = root:CreateTexture(nil, "ARTWORK")
		split:SetColorTexture(1, 0.82, 0, 0.2)
		split:SetWidth(1)
		split:SetPoint("TOPLEFT", x, -PAD)
		split:SetHeight(paneH)
	end
	BuildDetails(root, detailX, PAD, DETAILS_W, paneH)
	view.Empty = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	view.Empty:SetPoint("CENTER", frame.Inset, "CENTER", 0, 20)
	view.Empty:SetWidth(WIDTH - 200)
	view.Empty:SetText(L["The quest data isn't there: LefthyTools_QuestData is missing or switched off in the AddOns list."])
	view.Empty:Hide()
	frame:SetScript("OnEvent", OnEvent)
	frame:HookScript("OnShow", function(self)
		for _, event in ipairs(EVENTS) do
			self:RegisterEvent(event)
		end
		state.listening = true
	end)
	frame:HookScript("OnHide", function(self)
		for _, event in ipairs(EVENTS) do
			self:UnregisterEvent(event)
		end
		state.listening = false
		state.searchAt, state.statusOld, state.namesAt = nil, false, nil
		self:SetScript("OnUpdate", nil)
		view.g.drag, view.mapPane.map.drag = nil, nil
		view.g.frame:SetScript("OnUpdate", nil)
		view.mapPane.map.frame:SetScript("OnUpdate", nil)
		view.Box:ClearFocus()
		GameTooltip:Hide()
	end)
	if Q.OnDataChanged then
		Q.OnDataChanged(DataChanged)
	end
	if Q.OnFriendProgress then
		Q.OnFriendProgress(function() -- (QuestShare.lua: friends' answers came: redrawn)
			if frame and frame:IsShown() then
				state.namesAt = state.namesAt or GetTime()
				Due()
			end
		end)
	end
end

-- Scaled down to fit a smaller screen (or a large UI scale).
local function Fit()
	local sw = GetScreenWidth and GetScreenWidth() or WIDTH
	local sh = GetScreenHeight and GetScreenHeight() or HEIGHT
	local scale = math.min(1, (sw - SCREEN_W) / WIDTH, (sh - SCREEN_H) / HEIGHT)
	frame:SetScale(math.max(0.4, scale))
end

-- The data there (it loads now, the first time), or the empty window says so.
local function Ready()
	local ok = Q.Load ~= nil and Q.Load() == true
	view.root:SetShown(ok)
	view.Empty:SetShown(not ok)
	for _, part in ipairs(view.Search) do
		part:SetShown(ok)
	end
	return ok
end

---------------------------------------------------------------------------
-- What the others call
---------------------------------------------------------------------------

local function Allowed()
	local m = LT:GetModule("questtree")
	if m and not m.enabled then
		LT.Print("Questtree is switched off (/lefthy enable questtree).")
		return false
	end
	return true
end

-- Opens the big window, on a quest if one is given (its zone, its card, its details).
function Q.OpenBrowser(id)
	if not Allowed() then
		return
	end
	if not frame then
		Build()
	end
	Fit()
	local ready = Ready()
	if ready then
		if state.dataOld then
			state.dataOld = false
			Forget()
		end
		wipe(state.counts) -- (quests may have been turned in while it was closed)
		wipe(state.layouts)
		DrawAll()
	end
	local wasShown = frame:IsShown()
	frame:Show()
	if frame.Raise then
		frame:Raise()
	end
	if ready and id then
		Open(id)
	elseif ready and not wasShown and state.where and not state.opened then
		state.opened = true
		DrawZones(true, state.where) -- (the first time: the zone I'm in, in sight)
	end
	-- Closed while a search was still due: it's done now.
	local text = ready and strtrim(view.Box:GetText() or "") or state.query
	if text ~= state.query then
		if text == "" then
			EndSearch()
		else
			state.searchAt = GetTime()
			Due()
		end
	end
end

function Q.ToggleBrowser()
	if frame and frame:IsShown() then
		frame:Hide()
		return
	end
	Q.OpenBrowser()
end

-- The module switched off.
function Q.HideBrowser()
	if frame then
		frame:Hide()
	end
end

function Q.BrowserShown()
	return frame ~= nil and frame:IsShown()
end

-- The window's frames and state, what Q.OnDataChanged calls, the filters (for the tests).
function Q.BrowserView()
	return view, state, frame, DataChanged, filters
end
