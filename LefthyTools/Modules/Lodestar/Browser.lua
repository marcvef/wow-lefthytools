local _, ns = ...
local LT = ns.LT
local L = ns.L
local Q = ns.Lodestar or {}
ns.Lodestar = Q

-- Lodestar's big window (Q.ToggleBrowser, Q.OpenBrowser(id)): every zone's quest chains. Near full
-- screen (at least 1400 x 760, wider where the screen has room, scaled down to fit a smaller one),
-- movable, Escape closes it. On top a search across all zones and two filters (all levels, show what
-- isn't for me; by default only what's within my levels, Q.InRange); under it the zones on the left
-- (by continent, each with its level range, how many of its quests I've done and a thin bar, dimmed
-- when it's far from my level; then the dungeons), in the middle a tab bar (the zone page, the quest
-- list, every view another file registers: Q.RegisterBrowserView, built the first time it's shown),
-- beside the tabs on the Zone tab a switch "Map | Chain: <name> 3/7" (the zone's map, or the chain of
-- the quest picked or opened last: one click each way), and on the right a pane that's never empty.
-- Each surface shows what to do now and how far along; the rest is in tooltips. A quest's chain
-- badge ("2/4") on the rows (the quest list, the right pane's) opens its chain, its card in sight
-- (Q.OpenChain does it for other files).
--   * The zone page: the zone's map, as large as the middle (3:2): its art, a pin per quest giver
--     with how many quests it has (the game's icons: available "!", a low level one's, a grey "!" for
--     later ones, "?" ready to turn in, a grey "?" still in progress, repeatable ones blue; where items
--     that start a quest drop; each pin's tooltip says what it is), my arrow. The wheel zooms where
--     the cursor is, dragging moves it, -, + and Fit on its strip. Hovering a pin lights its chain (and
--     its card on the right); a click picks its quest (several: a small list of ours beside it to pick
--     one); a right-click or Shift-click sets the game's map pin there. The quest picked: its giver
--     ringed, its turn-in, its objectives' areas (Q.Objectives) as soft circles in its chain's colour,
--     a dashed way giver -> objectives -> turn-in. Each chain has a colour of its own (from its first
--     quest's ID), drawn as a thin thread from giver to turn-in to the next giver while its card or a
--     pin of it is hovered or it has the quest picked. Under the map one line: what's here for me now
--     (ready to turn in, in progress, available), and when nothing is there to take, a zone that has
--     some. A dungeon has no map: its Zone tab is its quest list.
--   * The right pane, nothing picked: the briefing of what the middle shows. A zone's: its name,
--     levels, how far along with a bar, what's for my level; what to turn in now and what's in progress
--     here (my quest log); its chains as cards (the chain's own colour, how far along with a bar,
--     what's next and who gives it; levels, what it opens and friends in its tooltip; a click opens it;
--     the done chains folded; how many more outside my levels). An opened chain's: its steps as rows.
--   * The right pane, a quest picked: its details. The way back on top; its icon, title in its
--     difficulty colour and status with the reason; its chain's step with the steps around it (and a
--     button opening the chain); its objectives (with my progress from the quest log; hovering one
--     lights its area on the map); who gives it and takes it back (a click puts a map pin there); the
--     small map when the zone's isn't in sight; its rewards (the game's item icons and tooltips, money,
--     experience: Q.Rewards); requirements not met, the first quest it needs and what it leads to,
--     friends; at the bottom Map pin (where to go next) and Companion (Q.ShowQuest).
--   * A chain opened (a click on its card, a stub, a badge, "Chain" above the middle, "Open the
--     chain"): its quests (every level) as cards
--     from top to bottom, a row per stage (how many quests come before it), side by side where it
--     forks; lines in the gaps (their own lane each, so lines that aren't joined never look joined),
--     "one of" where any one of several is enough, dashed lines for a lead-in that isn't needed first,
--     the steps in another zone as stubs with the zone's name (a click goes there). A locked quest
--     picked: the way back to it (Q.Missing) lit and numbered, across zones (the stubs light up), the
--     rest dim. The next step pulses once when the chain opens.
--   * The quest list: the zone's quests grouped: in progress, available now, coming up (level),
--     blocked (needs another first), completed (with the skipped ones), not for you (with its filter).
-- A search (Q.Search: titles and giver names, across all zones) shows its results in the middle; a
-- click on a result or a zone goes there with "Back to the search results" on top, and the search
-- stays until the box is emptied. A click on a quest also shows it in the small window while that's
-- open (Q.IsSmallShown).
--
-- What it costs: built when first opened; the data addon loads then too (Q.Load), never at login.
-- A zone's chains are worked out once (Q.Chain, Q.Opens) and kept until the data changes; a chain's
-- cards, a zone's pins and threads when the filters or a status change; the quest picked's areas when
-- it's picked or the map is drawn. The chain's canvas has only the cards and lines near sight (pooled,
-- each card kept on its quest while it stays near, so a controller's cursor stays on it); the lists
-- (zones, overview, results) only their rows in sight; the right pane's rows, cards, lines and rewards
-- are pooled. Hovering only sets the alpha of what's there. Events (QUEST_TURNED_IN, QUEST_ACCEPTED,
-- QUEST_REMOVED, PLAYER_LEVEL_UP, QUEST_DATA_LOAD_RESULT, ITEM_DATA_LOAD_RESULT, QUEST_LOG_UPDATE,
-- ZONE_CHANGED_NEW_AREA) only while it's open; they note what changed and the redraw comes on the next
-- frame, at most every half second (my quest log's lines: once a second, only when they changed). My
-- arrow moves ten times a second only while I'm on the map shown. Closed, nothing runs. Our own frames
-- only, nothing protected (it opens in a fight), no Blizzard menu (gamepad mode), every card, pin,
-- area, row, line, reward, tab and filter a plain Button the controller's navigation reaches; a card or
-- pin the cursor moves to out of sight brings itself into view.

-- The window's size: at least 1400 x 760; wider (up to 1700) where the screen has room, the map
-- in the middle growing with it (3:2), its height following; scaled down to fit a smaller screen.
local WIDTH, HEIGHT = 1400, 760
local SIZE = { W = 1400, H = 760, MAX_W = 1700, STEP = 20, WIDE = 1560 }
local SCREEN_W, SCREEN_H = 40, 80 -- kept free around it on a small screen
local INSET_W, INSET_H = 10, 86   -- how much smaller than the window the template's Inset is
local PAD, GAP, EDGE = 6, 8, 10
local ZONES_W, DETAILS_W = 240, 360 -- (each with its scroll bar; the right one 400 on a wide window)
local BAR_W = 24
local ROW_H = 20
local TABS_H, HEAD_H, LEGEND_H = 28, 44, 22
local BEYOND = 2                  -- list rows laid beyond sight, above and below (the controller's next one)
local LINK_H = 18
local SHOWN = { needs = 1, leads = 3, friends = 3, others = 3, points = 20, threads = 500, dots = 5, chainFriends = 60,
	steps = 60, log = 6, areas = 40, dashes = 60, choose = 12 }
local SEARCH_GAP, REFRESH_GAP, NAMES_GAP, READY_GAP = 0.3, 0.5, 0.2, 1
local GOLD, GREY, SEP = "|cffffd200", "|cff888888", " · "
local EMPTY = {}

-- The zone page: the map (3:2) filling the middle, a line under it; the chains' cards in the
-- briefing on the right (8 px grid). MAP_W and MAP_H are set when the window is built.
local Z = { MAP_W = 752, CARD_H = 48, CARD_GAP = 8, DIM = 0.4, PIN_DIM = 0.3, BAR = 56, LINE_H = 24, TOOL = 22 }
Z.MAP_H = math.floor(Z.MAP_W * 2 / 3)

-- A chain's canvas: cards, gaps, lanes (canvas units, before the zoom).
local G = {
	W = 170, H = 48, HGAP = 14, VGAP = 34, DUMMY = 22, LINE = 2, ICON = 32,
	LANE = 6, DASH = 5, DASH_GAP = 4, PILL_W = 46, PILL_H = 14,
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
	daily = "Interface\\GossipFrame\\DailyQuestIcon",
	turnin = "Interface\\GossipFrame\\ActiveQuestIcon",
	progress = "Interface\\GossipFrame\\IncompleteQuestIcon",
	object = "Interface\\Icons\\INV_Misc_Note_01",
	item = "Interface\\Icons\\INV_Misc_Bag_10",
	map = "Interface\\Icons\\INV_Misc_Map_01",
	check = "Interface\\RaidFrame\\ReadyCheck-Ready",
	box = "Interface\\Buttons\\UI-CheckBox-Up", tick = "Interface\\Buttons\\UI-CheckBox-Check",
	glow = "Spells\\GenericGlow64",          -- (soft and round, black around it: drawn added)
	arrow = "Interface\\Minimap\\MinimapArrow",
	here = "Interface\\ChatFrame\\ChatFrameExpandArrow",
	bullet = "Interface\\QuestFrame\\UI-Quest-BulletPoint",
	border = "Interface\\Common\\WhiteIconFrame",
	question = "Interface\\Icons\\INV_Misc_QuestionMark",
}

-- The window's status colours (Attune's tones: done green, ready amber, the rest grey).
local TONE = {
	done = { 0.37, 0.73, 0.28 }, active = { 0.35, 0.65, 1 }, available = { 0.85, 0.61, 0 },
	locked = { 0.55, 0.55, 0.55 }, level = { 0.9, 0.45, 0.25 }, other = { 0.4, 0.4, 0.4 },
}
local PATH_TONE = { 1, 0.5, 0.15 } -- the way back to a locked quest
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
-- By default only what's within my levels (Q.InRange) on the zone page and in the quest list; the
-- quests not for me (race, class, faction, a profession I don't have) left out everywhere.
local filters = { allLevels = false, showOther = false }
local state = {
	where = nil,      -- the place shown: "z:<uiMapID>" or "d:<dungeon>"
	picked = nil,     -- the quest in the details
	tab = "zone",     -- "zone" | "overview" (the quest list) | a registered view's key
	chain = nil,      -- on the zone tab: the chain opened (its group's key), nil: the zone page
	lastChain = nil,  -- the chain left for the map (the switch's way back to it while nothing is picked)
	path = nil,       -- the way back to a locked quest picked in a chain (Path.Update)
	pulse = nil,      -- a card to pulse once when it's next filled (the next step of a chain opened)
	query = "",       -- the search shown
	results = nil,    -- its quest IDs
	drilled = false,  -- a zone or quest clicked during a search: it shows, the search stays
	folded = {},      -- group or continent key -> true (the done ones start folded)
	counts = {},      -- place -> { done, total }
	trees = {},       -- place -> its chains
	layouts = {},     -- chain -> its cards' places (for the filters and statuses of now)
	infos = {},       -- chain -> how far along, what's next (Chains.Info)
	spots = {},       -- place -> the zone map's pins and threads
	why = {}, range = {}, -- quest -> why it isn't for me (Q.WhyOther), whether it's within my levels (Q.InRange)
	suggest = nil,    -- a zone with quests for my level (ZonePage.Suggest), false: none
	zones = nil, dungeons = nil, places = nil,
	asked = {}, waiting = {}, -- titles asked of the client (QUEST_DATA_LOAD_RESULT)
	items = {},       -- items asked of the client (ITEM_DATA_LOAD_RESULT: a reward's quality, a name)
	logKey = nil,     -- what the right pane showed of my quest log (QUEST_LOG_UPDATE: drawn again when it changed)
	dataOld = false, statusOld = false, nextRefresh = 0, searchAt = nil, namesAt = nil, readyAt = nil, ready = nil,
	listening = false,
	draws = 0, trees_built = 0, layouts_built = 0, -- (for the tests)
}
-- Views other files add as tabs (Q.RegisterBrowserView): key -> { key, label, build, built, holder }.
local registry = { order = {}, byKey = {}, current = nil }
local Graph, Map, Overview, Details, Chains, ZonePage, Views, Head, Tabs, Path, Make, Rule = {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
-- The right pane (Side: the briefing or the details), its briefing (Brief: a zone's, a chain's), what a
-- quest asks (Task: its objectives, my progress on them, its rewards).
local Side, Brief, Task = {}, {}, {}

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

-- A status in a word (a friend's too; mine with its reason: Rule.Reason).
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

-- Shown with the filters as they are: what isn't for me only with its filter (one I skipped, closed
-- by another I took, is shown: it's grouped with the done ones).
local function Visible(id, status)
	return filters.showOther or not Rule.NotForMe(id, status)
end

local function Has(list, x)
	for _, v in ipairs(list or EMPTY) do
		if v == x then
			return true
		end
	end
	return false
end

-- An atlas when the client has it, else the file.
local atlasKnown = {}
local function Known(atlas)
	if atlas and atlasKnown[atlas] == nil then
		atlasKnown[atlas] = (C_Texture and LT.Value(C_Texture.GetAtlasInfo, atlas)) and true or false
	end
	return atlas ~= nil and atlasKnown[atlas]
end

local function Art(texture, atlas, file)
	if Known(atlas) then
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

-- A quest in my log that's ready to turn in.
local function IsReady(id)
	return C_QuestLog ~= nil and LT.Value(C_QuestLog.IsComplete, id) == true
end

-- Grey for me (the game's low-level "!"): Engine.lua's Q.IsTrivial.
local function Trivial(id)
	if not Q.IsTrivial then
		return false
	end
	local ok, grey = pcall(Q.IsTrivial, id)
	return ok and grey == true
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

-- The card's start: the giver's "!" (bright when I can take it, a low level one's when it's grey for
-- me), an item's icon, an object.
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
	elseif status == "available" and not (q and q.repeatable) and q and Trivial(q.id) then
		Art(texture, "TrivialQuests", T.available)
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

local function GamepadCursor(self)
	local pad = InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()
	return pad or not self:IsMouseOver() -- (the controller's cursor, not the mouse)
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

---------------------------------------------------------------------------
-- What a status means: why it isn't for me, my levels, the reason in words
---------------------------------------------------------------------------

-- Why a quest isn't for me (Q.WhyOther): "closed" and the quest that closed it (I took another, or
-- have what a lead-in leads to), "race", "class", "faction", "skill"; nil. Kept until a status changes.
function Rule.Why(id)
	local w = state.why[id]
	if w == nil then
		w = false
		if Q.WhyOther then
			local ok, why, by = pcall(Q.WhyOther, id)
			w = ok and why and { why, by } or false
		end
		state.why[id] = w
	end
	if w then
		return w[1], w[2]
	end
end

-- Closed by another quest I took: grouped with the done ones, not with "not for you".
function Rule.Skipped(id, status)
	return status == "other" and Rule.Why(id) == "closed"
end

function Rule.NotForMe(id, status)
	return status == "other" and Rule.Why(id) ~= "closed"
end

-- For my level (Q.InRange: in my log, or what I can take now and is worth it: from my level on, not
-- grey for me, not red); without Q.InRange everything. Kept until a status changes.
function Rule.InRange(id)
	if not Q.InRange then
		return true
	end
	local yes = state.range[id]
	if yes == nil then
		local ok, r = pcall(Q.InRange, id)
		yes = not ok or r ~= false
		state.range[id] = yes
	end
	return yes
end

-- For my level, as the counts say it: in my log, or one I can take now within my levels (not one that
-- needs another quest first, nor an event's: Q.InRange).
function Rule.ForMyLevel(id, status)
	return status == "active" or (status == "available" and Rule.InRange(id))
end

-- Within my levels, as the zone page and the quest list show them unless all levels are asked for;
-- done and skipped ones always are.
function Rule.InLevels(id, status)
	if filters.allLevels or status == "done" or Rule.Skipped(id, status) then
		return true
	end
	return Rule.InRange(id)
end

-- On the zone page (pins, threads) and in the quest list: the filters' both.
function Rule.Shown(id, status)
	return Visible(id, status) and Rule.InLevels(id, status)
end

-- A place far from my level: its top below mine - 10, or its bottom above mine + 5 (dimmed on the left).
function Rule.Far(place)
	local my = tonumber(UnitLevel and LT.Value(UnitLevel, "player")) or 1
	return (place.maxLevel ~= nil and place.maxLevel < my - 10) or (place.minLevel ~= nil and place.minLevel > my + 5)
end

-- What blocks a quest besides quests (Q.Needs: a reputation or a profession's rank), as a table.
function Rule.Needs(id)
	if not Q.Needs then
		return nil
	end
	local ok, need = pcall(Q.Needs, id)
	return ok and type(need) == "table" and need or nil
end

-- My status in words with its real reason: "Needs level 12", "Needs Friendly with Stormwind",
-- "Needs Leatherworking 50", "Needs <the first quest missing>", "Skipped", "Not for your race", ...
function Rule.Reason(id, status)
	local q = Quest(id)
	if status == "level" then
		return q and q.minLevel and L["Needs level %d"]:format(q.minLevel) or Word(status)
	elseif status == "locked" then
		local need = Rule.Needs(id)
		if need and need.kind == "rep" then
			return L["Needs %s"]:format(L["%s with %s"]:format(Standing(need.min or 0), FactionName(need.faction)))
		elseif need and need.kind == "skill" then
			return L["Needs %s"]:format(SkillName(need.id) .. " " .. tostring(need.value or 0))
		end
		local miss = Q.Missing and Q.Missing(id) or EMPTY
		if miss[1] and miss[1].id then
			return L["Needs %s"]:format(Title(miss[1].id))
		end
	elseif status == "other" then
		local why = Rule.Why(id)
		if why == "closed" then
			return L["Skipped"]
		elseif why == "race" then
			return L["Not for your race"]
		elseif why == "class" then
			return L["Not for your class"]
		elseif why == "faction" then
			return L["Not for your faction"]
		elseif why == "skill" and q and q.skill then
			return L["Needs %s"]:format(SkillName(q.skill.id))
		end
	end
	return Word(status)
end

-- A quest I skipped: which one I took instead (or, a lead-in, what I have that it led to).
function Rule.SkippedFor(id)
	local why, by = Rule.Why(id)
	if why ~= "closed" or not by then
		return nil
	end
	local q = Quest(id)
	return (q and q.breadcrumbFor == by and L["No longer needed: you have %s"] or L["You took %s instead"]):format(Title(by))
end

-- Which step of its chain a quest is, counted as the details count it (Q.ChainFor: the steps as I can
-- do them; else Q.ChainStep / Q.Chain): step, total; nil for a quest in no chain. (Q.ChainFor keeps
-- its answers until my progress changes: cheap for every row.)
function Rule.Step(id)
	if not id then
		return nil
	elseif Q.ChainFor then
		local list, at = Q.ChainFor(id)
		if type(list) == "table" and at and #list >= 2 then
			return at, #list
		end
		return nil
	end
	local step, total = StepOf(id)
	if step and total and total >= 2 then
		return step, total
	end
end

---------------------------------------------------------------------------
-- What a quest asks: its objectives (Q.Objectives), my progress on them (the quest log), its rewards
---------------------------------------------------------------------------

-- Q.Objectives (Data.lua): { { kind = "kill" | "item" | "object", id, name, count, sources = { { kind,
-- id, name, chance, points = { { map, x, y, r } } } } } } (shared: never written); {} without it.
function Task.List(id)
	if not (id and Q.Objectives) then
		return EMPTY
	end
	local ok, list = pcall(Q.Objectives, id)
	return ok and type(list) == "table" and list or EMPTY
end

-- Q.Rewards: { choice = { { id, count } }, items = { { id, count } }, money, xp }; nil: none known.
function Task.Rewards(id)
	if not (id and Q.Rewards) then
		return nil
	end
	local ok, r = pcall(Q.Rewards, id)
	if not (ok and type(r) == "table") then
		return nil
	end
	local any = (type(r.choice) == "table" and r.choice[1]) or (type(r.items) == "table" and r.items[1])
		or (tonumber(r.money) or 0) > 0 or (tonumber(r.xp) or 0) > 0
	return any and r or nil
end

-- An item the client doesn't know yet: asked for once (ITEM_DATA_LOAD_RESULT draws the details again).
function Task.AskItem(id)
	if not id or state.items[id] then
		return
	end
	state.items[id] = true
	if C_Item and C_Item.RequestLoadItemDataByID then
		pcall(C_Item.RequestLoadItemDataByID, id)
	end
end

-- An item's name: the client's (in its language), else the data's.
function Task.ItemName(id, fallback)
	local name = id and C_Item and LT.Value(C_Item.GetItemNameByID, id)
	if type(name) == "string" and name ~= "" then
		return name
	end
	Task.AskItem(id)
	return fallback or ("#" .. tostring(id))
end

-- An objective in words: "Kill 10 x Kobold Vermin", "Collect 8 x Wolf Fang", "Use Wanted Poster".
function Task.Text(o)
	local count = tonumber(o.count) or 0
	local name = o.kind == "item" and Task.ItemName(o.id, o.name) or o.name or "?"
	if o.kind == "kill" then
		return count > 1 and L["Kill %d x %s"]:format(count, name) or L["Kill %s"]:format(name)
	elseif o.kind == "item" then
		return count > 1 and L["Collect %d x %s"]:format(count, name) or L["Collect %s"]:format(name)
	end
	return count > 1 and L["Use %d x %s"]:format(count, name) or L["Use %s"]:format(name)
end

-- Where an item comes from: its likeliest source, "from Young Wolf, 32%".
function Task.From(o)
	local s = o.kind == "item" and type(o.sources) == "table" and o.sources[1]
	if not s then
		return nil
	elseif tonumber(s.chance) then
		return L["from %s, %s%%"]:format(s.name or "?", Chance(s.chance))
	end
	return L["from %s"]:format(s.name or "?")
end

-- My progress on a quest in my log: the quest log's lines { text, done, objective (its index in
-- Task.List, nil: not known) }, matched by the name in the line (an English client), else by the
-- order of their kind, else by their place; nil for a quest not in my log.
Task.LOG_KIND = { monster = "kill", item = "item", object = "object" }
function Task.Progress(id, list)
	if not (C_QuestLog and C_QuestLog.GetQuestObjectives) or StatusOf(id) ~= "active" then
		return nil
	end
	local log = LT.Value(C_QuestLog.GetQuestObjectives, id)
	if type(log) ~= "table" or not log[1] then
		return nil
	end
	local used, out = {}, {}
	for i, o in ipairs(log) do
		local text = type(o.text) == "string" and o.text or ""
		local lower, match = text:lower(), nil
		for k, d in ipairs(list) do
			if not match and not used[k] and type(d.name) == "string" and d.name ~= "" and lower:find(d.name:lower(), 1, true) then
				match = k
			end
		end
		for k, d in ipairs(list) do
			if not match and not used[k] and Task.LOG_KIND[o.type] and d.kind == Task.LOG_KIND[o.type] then
				match = k
			end
		end
		if not match and list[i] and not used[i] then
			match = i
		end
		if match then
			used[match] = true
		end
		out[#out + 1] = { text = text, done = o.finished == true, objective = match }
	end
	return out
end

-- The first line of my progress not done yet ("3/10 Kobold Vermin slain"), nil: none (or not in my log).
function Task.FirstOpen(id)
	for _, p in ipairs(Task.Progress(id, EMPTY) or EMPTY) do
		if not p.done and p.text ~= "" then
			return p.text
		end
	end
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
	local index, parents, children = {}, {}, {}
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
		children[from] = children[from] or {}
		table.insert(children[from], to)
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
	return { key = key, chain = chain, index = index, parents = parents, children = children, faction = not mixed and faction or nil }
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
	tree = { groups = {}, member = member, shown = {}, groupOf = {}, byKey = {}, ids = ids }
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
		group.single, group.parents, group.children = true, {}, {}
		tree.groups[#tree.groups + 1] = group
	end
	for _, group in ipairs(tree.groups) do
		tree.byKey[group.key] = group
		for _, id in ipairs(group.chain) do
			tree.shown[id] = true
			tree.groupOf[id] = tree.groupOf[id] or group
		end
	end
	state.trees[place.id] = tree
	return tree
end

-- Where a quest's chains are: the place shown if it's one of its quests, else its zone or its
-- dungeon, the one that lists it (a dungeon's quest may be given in a zone that doesn't).
local function PlaceOf(q, id)
	local current = state.where and state.places[state.where]
	if current and Structure(current).member[id] then
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
	if place then
		return place.id
	end
	return current and Structure(current).shown[id] and current.id or nil
end

-- A zone (a uiMap) or a dungeon (its name) on the left, walking up from a city's floor or a cave.
local function PlaceFor(map)
	if type(map) == "string" then
		return state.places["d:" .. map] and ("d:" .. map) or nil
	end
	for _ = 1, 4 do
		if type(map) ~= "number" then
			return nil
		end
		if state.places["z:" .. map] then
			return "z:" .. map
		end
		local info = C_Map and LT.Value(C_Map.GetMapInfo, map)
		map = type(info) == "table" and info.parentMapID or nil
	end
end

-- Where I am, or the first zone.
local function DefaultPlace()
	local here = PlaceFor(C_Map and LT.Value(C_Map.GetBestMapForUnit, "player"))
	if here then
		return here
	end
	local first = state.zones[1] or nil
	if first then
		return "z:" .. tostring(first.map)
	end
	local dungeon = state.dungeons[1]
	return dungeon and ("d:" .. tostring(dungeon.name)) or nil
end

-- Statuses changed (or the filters): what was laid out from them goes.
local function Restatus()
	wipe(state.layouts)
	wipe(state.infos)
	wipe(state.spots)
	wipe(state.why)
	wipe(state.range)
	state.suggest = nil
end

-- The data changed: everything worked out from it goes.
local function Forget()
	state.places, state.zones, state.dungeons = nil, nil, nil
	wipe(state.trees)
	wipe(state.counts)
	Restatus()
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

-- A tab there is: the zone page, the overview, a view registered.
local function TabKnown(key)
	return key == "zone" or key == "overview" or (type(key) == "string" and registry.byKey[key] ~= nil)
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
	if saved.tab == "chains" or saved.tab == "map" then
		state.tab = "zone" -- (the tabs before the zone page)
	elseif TabKnown(saved.tab) then
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
-- Lists: a pool of rows, each kept on its entry while it's in sight (zones, chain cards, the
-- overview, results)
---------------------------------------------------------------------------

local function NewList(parent, x, y, width, height, newRow, fillRow, rowH)
	rowH = rowH or ROW_H
	local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", x, -y)
	scroll:SetSize(width, height)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(width, 1)
	scroll:SetScrollChild(child)
	local sight = math.ceil(height / rowH) + 1
	local pool = sight + 2 * BEYOND
	local list = { scroll = scroll, child = child, rows = {}, entries = {}, first = 1, made = 0, fills = 0, height = height, pool = pool,
		sight = sight, rowH = rowH }

	-- The rows from just above to just below sight. Entry i always has row (i - 1) % pool + 1, so a row
	-- the controller's cursor is on keeps its entry when the list scrolls under it.
	function list:Lay(offset)
		local top = math.max(0, math.floor((offset or scroll:GetVerticalScroll() or 0) / rowH))
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
				row:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
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
		local total = #entries * rowH
		child:SetHeight(math.max(1, total))
		local now = scroll:GetVerticalScroll() or 0
		local want = offset == true and now or offset or 0
		want = math.max(0, math.min(want, total - height))
		self.first = math.floor(want / rowH) + 1
		if want ~= now then
			scroll:SetVerticalScroll(want)
		end
		for _, row in pairs(self.rows) do
			row.index = nil -- (their entries are others now)
		end
		self:Lay(want)
	end

	function list:Centered(i)
		return math.max(0, (i - 1) * rowH - height / 2 + rowH / 2)
	end

	-- Entry i in sight (in the middle, as far as the list goes).
	function list:ScrollTo(i)
		local want = math.max(0, math.min(self:Centered(i), #self.entries * rowH - height))
		scroll:SetVerticalScroll(want)
		self:Lay(want)
	end

	-- Whether entry i is in sight now.
	function list:InSight(i)
		return i >= self.first and i < self.first + sight - 1
	end

	scroll:HookScript("OnVerticalScroll", function(_, offset)
		if math.floor((offset or 0) / rowH) + 1 ~= list.first then
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

-- A quest's tooltip: title, status, level, chain step, where it starts, what's next, friends, what a
-- click does (badge: the row's chain badge, "2/4", which opens the chain).
local function QuestTip(owner, id, badge)
	local q = Quest(id)
	if not q then
		return
	end
	local status = StatusOf(id)
	local c = TONE[status]
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(Title(id), 1, 0.82, 0)
	GameTooltip:AddLine(Rule.Reason(id, status), c[1], c[2], c[3])
	local skipped = Rule.SkippedFor(id)
	if skipped then
		GameTooltip:AddLine(skipped, 0.8, 0.8, 0.8, true)
	end
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
		GameTooltip:AddLine(L["Step %d of %d"]:format(step, total) .. (name and (SEP .. name) or ""), 0.8, 0.8, 0.8)
	end
	local s = FirstStart(q)
	if s then
		GameTooltip:AddLine(L["Starts at: %s"]:format(StartWord(s)), 1, 1, 1)
		local d = s.drops and s.drops[1]
		if d then
			GameTooltip:AddLine(L["Drops from %s (%s%%)"]:format(d.name or "?", Chance(d.chance)), 0.8, 0.8, 0.8)
		end
	end
	if q.breadcrumbFor then
		GameTooltip:AddLine(L["A lead-in: not needed for what comes after."], 0.7, 0.7, 0.7, true)
	end
	if q.excl and q.excl[1] then
		local names = {}
		for i, x in ipairs(q.excl) do
			if i > 3 then
				names[#names + 1] = "..."
				break
			end
			names[#names + 1] = Title(x)
		end
		GameTooltip:AddLine(L["Taking it closes: %s"]:format(table.concat(names, ", ")), 1, 0.45, 0.35, true)
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
	if badge then
		GameTooltip:AddLine(L["Click %s: open the chain"]:format(badge), 0.5, 0.75, 1)
	end
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Chains: each one's colour, how far along, what's next (for its card and its page)
---------------------------------------------------------------------------

-- HSV (s 0.6, v 0.95) as r, g, b.
local function Hue(h)
	local s, v = 0.6, 0.95
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, qq, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
	i = i % 6
	if i == 0 then
		return v, t, p
	elseif i == 1 then
		return qq, v, p
	elseif i == 2 then
		return p, v, t
	elseif i == 3 then
		return p, qq, v
	elseif i == 4 then
		return t, p, v
	end
	return v, p, qq
end

-- A chain's own colour, the same everywhere (its first quest's ID, spread by the golden ratio).
function Chains.Color(group)
	if not group.color then
		if group.single then
			group.color = { 0.8, 0.8, 0.8 }
		else
			local h = ((tonumber(group.chain[1]) or 0) * 0.6180339887) % 1
			group.color = { Hue(h) }
		end
	end
	return group.color
end

function Chains.Name(group)
	if group.single then
		return L["Quests without a chain"]
	end
	local _, _, name = StepOf(group.chain[1])
	return name or Title(group.chain[1])
end

-- How many quests of the chain doing from comes before, not done yet (what it opens).
function Chains.Opens(group, from)
	local seen, queue, n, i = { [from] = true }, { from }, 0, 1
	while queue[i] do
		for _, c in ipairs(group.children[queue[i]] or EMPTY) do
			if not seen[c] then
				seen[c] = true
				queue[#queue + 1] = c
				local s = StatusOf(c)
				if s ~= "done" and s ~= "other" then
					n = n + 1
				end
			end
		end
		i = i + 1
	end
	return n
end

-- A chain's progress for me: done, total (not counting what isn't for me), visible (as the filters
-- show), whether one of its quests here not done yet is within my levels, its levels, steps in other
-- zones, what's next (kind: "active" | "available" | "coming" | "done") and what that opens. Kept
-- until a status or the filters change.
function Chains.Info(group, place)
	local info = state.infos[group.key]
	if info then
		return info
	end
	local member = place and Structure(place).member or EMPTY
	info = { done = 0, total = 0, visible = 0, elsewhere = 0, opens = 0, open = 0, inLevels = false }
	local first = {}
	for _, id in ipairs(group.chain) do
		local status = StatusOf(id)
		first[status] = first[status] or id
		if Visible(id, status) then
			info.visible = info.visible + 1
		end
		if status ~= "other" then
			info.total = info.total + 1
			local here = member[id] or group.single
			if status == "done" then
				info.done = info.done + 1
			elseif here and Rule.InLevels(id, status) then
				info.inLevels = true
				info.open = info.open + (status == "available" and 1 or 0)
			end
			local q = Quest(id)
			local level = q and tonumber(q.level)
			if level and level > 0 then
				info.low = math.min(info.low or level, level)
				info.high = math.max(info.high or level, level)
			end
			if not member[id] then
				info.elsewhere = info.elsewhere + 1
			end
		end
	end
	local coming = first.level
	if first.locked and (not coming or group.index[first.locked] < group.index[coming]) then
		coming = first.locked
	end
	if first.active then
		info.kind, info.next = "active", first.active
	elseif first.available then
		info.kind, info.next = "available", first.available
	elseif coming then
		info.kind, info.next = "coming", coming
	elseif first.done then
		info.kind = "done"
	end
	if info.next and not group.single then
		info.opens = Chains.Opens(group, info.next)
	end
	state.infos[group.key] = info
	return info
end

-- What's next in a chain (its card's and its page's line) and that quest.
function Chains.NextText(group, info)
	if group.single then
		if info.open > 0 then
			return L["%d to pick up now"]:format(info.open)
		end
		return L["%d quests"]:format(info.total)
	end
	local id = info.next
	if info.kind == "active" then
		return L["In your log: %s"]:format(Title(id)), id
	elseif info.kind == "available" then
		local q = Quest(id)
		local s = FirstStart(q)
		local where = s and s.name or (q and ZoneOf(q))
		return L["Next: %s"]:format(Title(id)) .. (where and (SEP .. where) or ""), id
	elseif info.kind == "coming" then
		return L["Coming up: %s"]:format(Title(id)), id
	elseif info.kind == "done" then
		return L["All done"], nil
	end
	return "", nil
end

-- Friends' progress on a chain: { name, classFile, done } each, the furthest first (Q.Friends).
function Chains.Friends(group, info)
	if info.friends then
		return info.friends
	end
	local list, by = {}, {}
	if Q.Friends then
		for i, id in ipairs(group.chain) do
			if i > SHOWN.chainFriends then
				break
			end
			for _, f in ipairs(Q.Friends(id) or EMPTY) do
				local key = tostring(f.name)
				local e = by[key]
				if not e then
					e = { name = f.name, classFile = f.classFile, done = 0 }
					by[key] = e
					list[#list + 1] = e
				end
				if f.status == "done" then
					e.done = e.done + 1
				end
			end
		end
		table.sort(list, function(a, b)
			if a.done ~= b.done then
				return a.done > b.done
			end
			return tostring(a.name) < tostring(b.name)
		end)
	end
	info.friends = list
	return list
end

local function LevelSpan(low, high)
	if not low then
		return nil
	end
	return L["Level %s"]:format(low == high and tostring(low) or (low .. "-" .. high))
end

---------------------------------------------------------------------------
-- A chain opened: the layout
---------------------------------------------------------------------------

-- Whether "to" needs "from" first (its pre, preAny, preActive), or only follows it (a lead-in: a
-- breadcrumb, or a quest the ender offers next that doesn't need it).
function Graph.Needed(from, to)
	local q = Quest(to)
	if not q then
		return true
	end
	return Has(q.pre, from) or Has(q.preAny, from) or q.preActive == from
end

-- Each gap between two stages: a lane (a height of its own) per quest the lines in it go to, so two
-- lines that aren't joined never share a stretch (EQ's gutters). Lines into one quest share one
-- (they join there), and so do the lines of a fork (one quest to several, each from it alone). A line
-- going into a quest right under another quest it doesn't come from would look like that one's: it
-- comes in a little to the side (a passing line's slot moves within itself). The lanes stay above
-- the "all of" / "one of" labels at the gap's bottom.
function Graph.Lanes(hops, maxStage)
	local byGap, groupOf = {}, {}
	for _, h in ipairs(hops) do
		local a, b = h[1], h[2]
		local g = groupOf[b]
		if not g then
			g = { b = b, from = {}, n = 0 }
			groupOf[b] = g
			local list = byGap[a.stage]
			if not list then
				list = {}
				byGap[a.stage] = list
			end
			list[#list + 1] = g
		end
		if not g.from[a] then
			g.from[a], g.n, g.one = true, g.n + 1, a
		end
		g.bottom = a.bottom
	end
	local function Apart(g, h)
		return h.max < g.min - G.HGAP / 2 or g.max < h.min - G.HGAP / 2 or (g.n == 1 and h.n == 1 and g.one == h.one)
	end
	local function Clear(g, x, exits)
		for a in pairs(exits) do
			if not g.from[a] and math.abs(a.cx - x) < 4 then
				return false
			end
		end
		return true
	end
	local top, bottom = 5, G.VGAP - G.PILL_H - 2 -- (the lanes' band in a gap)
	for s = 0, maxStage - 1 do -- (in order: a passing line's slot moved here goes on from there)
		local list = byGap[s] or EMPTY
		local exits = {}
		for _, g in ipairs(list) do
			for a in pairs(g.from) do
				exits[a] = true
			end
		end
		for _, g in ipairs(list) do
			local b = g.b
			local x = b.cx
			if not Clear(g, x, exits) then
				x = Clear(g, b.cx + 9, exits) and b.cx + 9 or b.cx - 9
				if b.dummy then
					b.cx = x
				else
					b.inX = x
				end
			end
			g.min, g.max = x, x
			for a in pairs(g.from) do
				g.min, g.max = math.min(g.min, a.cx), math.max(g.max, a.cx)
			end
		end
		table.sort(list, function(x, y)
			if x.min ~= y.min then
				return x.min < y.min
			elseif x.max ~= y.max then
				return x.max < y.max
			end
			return x.b.seq < y.b.seq
		end)
		local lanes = {}
		for _, g in ipairs(list) do
			if g.max - g.min >= 1 then -- (straight down: no stretch across, no lane)
				local lane
				for i, members in ipairs(lanes) do
					local ok = true
					for _, h in ipairs(members) do
						ok = ok and Apart(g, h)
					end
					if ok then
						lane = i
						break
					end
				end
				if not lane then
					lane = #lanes + 1
					lanes[lane] = {}
				end
				table.insert(lanes[lane], g)
				g.lane = lane
			end
		end
		local n = #lanes
		local step = n > 1 and math.min(G.LANE, (bottom - top) / (n - 1)) or 0
		for _, g in ipairs(list) do
			local off = g.lane and (g.lane - 1 - (n - 1) / 2) * step or 0
			g.b.laneY = g.bottom + (top + bottom) / 2 + off
		end
	end
end

-- A chain's cards by stage (how many quests come before it), with a slot of its own for a line that
-- passes a stage (so it never runs through a card), the stages' quests ordered by where what leads to
-- them is, each stage centred in the chain's width. Lines: down from a card, across in its lane, down
-- into the next. vis: the quests shown (their status), stub: those of another zone among them.
function Graph.LayChain(out, group, vis, stub, top, viewW)
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
	local rows, item, edgesTo, hops, seq = {}, {}, {}, {}, 0
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
		item[id] = New({ quest = id, stage = stage[id], w = G.W, order = index[id], status = vis[id], group = group, stub = stub[id] })
	end
	for _, id in ipairs(order) do
		edgesTo[id] = {}
		for _, p in ipairs(VP(id)) do
			local bridged = VP(id).bridged[p] == true
			local e = { from = p, to = id, bridged = bridged, dashed = not bridged and not Graph.Needed(p, id) }
			local prev = item[p]
			for s = stage[p] + 1, stage[id] - 1 do
				local d = New({ dummy = true, stage = s, w = G.DUMMY, order = index[id], preds = { prev } })
				hops[#hops + 1] = { prev, d, e }
				prev = d
			end
			local child = item[id]
			child.preds[#child.preds + 1] = prev
			hops[#hops + 1] = { prev, child, e }
			table.insert(edgesTo[id], e)
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
	Graph.Lanes(hops, maxStage)
	-- The lines: green between done ones, amber from a done or ready one, grey; a passed-through
	-- (hidden) step fainter; a lead-in that isn't needed first dashed and dim.
	local half = G.LINE / 2
	for _, h in ipairs(hops) do
		local a, b, e = h[1], h[2], h[3]
		local fs, ts = vis[e.from], vis[e.to]
		local tone = (fs == "done" and ts == "done") and 2 or (fs == "done" or fs == "available" or fs == "active") and 1 or 0
		local faint = e.bridged or e.dashed
		local ym = b.laneY or (a.bottom + G.VGAP / 2)
		local bx = b.inX or b.cx
		if math.abs(a.cx - bx) < 0.5 then
			Graph.Seg(out, a.cx, a.bottom, bx, b.y, tone, faint, e) -- (straight down)
		else
			Graph.Seg(out, a.cx, a.bottom, a.cx, ym + half, tone, faint, e)
			Graph.Seg(out, math.min(a.cx, bx) - half, ym, math.max(a.cx, bx) + half, ym, tone, faint, e)
			Graph.Seg(out, bx, ym - half, bx, b.y, tone, faint, e)
		end
		if b.dummy then
			Graph.Seg(out, b.cx, b.y - half, b.cx, b.bottom + half, tone, faint, e)
		end
	end
	-- Where several lead to one and any one of them is enough: "one of" (where each is needed, the
	-- lines just meet). A lead-in's card a bit dimmer (its line is dashed).
	for _, id in ipairs(order) do
		local q = Quest(id)
		local it = item[id]
		if q then
			local any = 0
			for _, e in ipairs(edgesTo[id]) do
				if not e.bridged and Has(q.preAny, e.from) then
					any = any + 1
				end
			end
			if any >= 2 then
				out.pills[#out.pills + 1] = { x = it.inX or it.cx, y = it.y - G.PILL_H / 2, kind = "any", quest = id }
			end
			it.lead = q.breadcrumbFor ~= nil and not stub[id]
		end
	end
	out.width = math.max(out.width, blockW + 2 * PAD)
	return top + (maxStage + 1) * G.PY - G.VGAP
end

-- A line segment (canvas units, y down) of an edge; zero-length ones aren't kept. A dashed edge's
-- in pieces.
function Graph.Seg(out, x1, y1, x2, y2, tone, faint, e)
	if math.abs(x2 - x1) < 0.5 and math.abs(y2 - y1) < 0.5 then
		return
	end
	local function Add(ax, ay, bx, by)
		out.segs[#out.segs + 1] = { x1 = ax, y1 = ay, x2 = bx, y2 = by, tone = tone, faint = faint, dashed = e and e.dashed,
			from = e and e.from, to = e and e.to,
			minX = math.min(ax, bx), maxX = math.max(ax, bx), minY = math.min(ay, by), maxY = math.max(ay, by) }
	end
	if not (e and e.dashed) then
		Add(x1, y1, x2, y2)
		return
	end
	local len = math.max(math.abs(x2 - x1), math.abs(y2 - y1))
	local dx, dy = (x2 - x1) / len, (y2 - y1) / len
	local d = 0
	while d < len do
		local stop = math.min(len, d + G.DASH)
		Add(x1 + dx * d, y1 + dy * d, x1 + dx * stop, y1 + dy * stop)
		d = stop + G.DASH_GAP
	end
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
			local q = Quest(id)
			it.lead = q and q.breadcrumbFor ~= nil
			out.cards[#out.cards + 1] = it
			out.byQuest[id] = it
		end
	end
	out.width = math.max(out.width, math.min(n, perRow) * (G.W + G.HGAP) - G.HGAP + 2 * PAD)
	return top + math.ceil(n / perRow) * G.PY - G.VGAP
end

-- A chain's cards and lines with the filters and statuses of now (kept until one changes). The
-- place's own quests, every level (cutting steps out would break the chain; only what isn't for me
-- goes, with its filter off); another zone's only next to one of them, as a stub (the rest are
-- passed through).
function Graph.Layout(place, group)
	local cached = state.layouts[group.key]
	if cached then
		return cached
	end
	state.layouts_built = state.layouts_built + 1
	local viewW = view.g.w
	local out = { cards = {}, segs = {}, pills = {}, byQuest = {}, width = viewW, height = 0, hidden = 0, group = group }
	local member = Structure(place).member
	local vis, stub, n = {}, {}, 0
	for _, id in ipairs(group.chain) do
		local status = StatusOf(id)
		if not Visible(id, status) then
			out.hidden = out.hidden + (member[id] and 1 or 0)
		elseif member[id] or group.single then
			vis[id], n = status, n + 1
		else
			local near = false
			for _, p in ipairs(group.parents[id] or EMPTY) do
				near = near or member[p] == true
			end
			for _, c in ipairs(group.children[id] or EMPTY) do
				near = near or member[c] == true
			end
			if near then
				vis[id], stub[id], n = status, true, n + 1
			end
		end
	end
	local bottom = PAD
	if n > 0 then
		if group.single then
			bottom = Graph.LaySingles(out, group, vis, PAD, viewW)
		else
			bottom = Graph.LayChain(out, group, vis, stub, PAD, viewW)
		end
	end
	out.height = math.max(1, bottom + PAD)
	state.layouts[group.key] = out
	return out
end

---------------------------------------------------------------------------
-- A chain opened: the canvas (our own scrolling both ways, a zoom) and its pools
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

-- A card the controller's cursor moved to out of sight: brought into view.
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

-- A line's look: its tone; on the way back to a locked quest picked: lit, the rest dim.
function Graph.LineLook(line, s)
	local c = LINE_TONES[s.tone]
	local a, w = s.faint and 0.45 or c[4], G.LINE
	local path = state.path
	if path and path.on[s.from] and path.on[s.to] then
		c, a, w = PATH_TONE, 1, G.LINE + 1
	elseif path then
		a = a * 0.3
	end
	line:SetThickness(w)
	line:SetColorTexture(c[1], c[2], c[3], a)
	if line.SetDrawLayer then
		line:SetDrawLayer("ARTWORK", (path and path.on[s.from] and path.on[s.to]) and 3 or s.tone) -- (the lit ones over the grey)
	end
end

-- The cards, lines and pills near sight, from the pools; laid again only when the view moved a
-- good bit (half a card), or force.
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
	-- Lines and pills: only what's near.
	local n = 0
	for _, s in ipairs(lay.segs) do
		if s.maxX >= x0 and s.minX <= x1 and s.maxY >= y0 and s.minY <= y1 then
			n = n + 1
			local line = g.lines[n]
			if not line then
				line = g.canvas:CreateLine(nil, "ARTWORK")
				g.lines[n] = line
			end
			line.seg = s
			Graph.LineLook(line, s)
			line:SetStartPoint("TOPLEFT", g.canvas, s.x1, -s.y1)
			line:SetEndPoint("TOPLEFT", g.canvas, s.x2, -s.y2)
			line:Show()
		end
	end
	for i = n + 1, #g.lines do
		g.lines[i].seg = nil
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
			Graph.FillPill(f, pill)
			f:Show()
		end
	end
	for i = p + 1, #g.pills do
		g.pills[i]:Hide()
	end
end

-- The cards in sight filled again (titles that came).
function Graph.Refill()
	for _, card in pairs(view.g.cards) do
		if card.item then
			Graph.FillCard(card, card.item)
		end
	end
end

-- A chain drawn (keep: where it's scrolled; focus: a quest to bring into the middle).
function Graph.Draw(place, group, keep, focus)
	local g = view.g
	g.layout = place and group and Graph.Layout(place, group) or nil
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

-- A card's tooltip: its quest's, or a stub's (the quest's zone, a click goes there).
local function CardEnter(self)
	local it = self.item
	if not it then
		return
	end
	if GamepadCursor(self) then
		Graph.Reveal(it, G.W, G.H)
	end
	if not it.stub then
		QuestTip(self, it.quest)
		return
	end
	local q = Quest(it.quest)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(q and ZoneOf(q) or "?", 1, 0.82, 0)
	GameTooltip:AddLine(L["In another zone: %s"]:format(LevelTag(q) .. Title(it.quest)), 1, 1, 1, true)
	local c = TONE[it.status] or TONE.other
	GameTooltip:AddLine(Rule.Reason(it.quest, it.status), c[1], c[2], c[3])
	GameTooltip:AddLine(L["Click: go there"], 0.5, 0.75, 1)
	GameTooltip:Show()
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
	-- The next step's one-time pulse when its chain opens.
	b.Pulse = b:CreateTexture(nil, "BACKGROUND", nil, -2)
	b.Pulse:SetPoint("TOPLEFT", -7, 7)
	b.Pulse:SetPoint("BOTTOMRIGHT", 7, -7)
	b.Pulse:SetColorTexture(1, 0.82, 0, 0.6)
	b.Pulse:SetAlpha(0)
	b.Pulse.Anim = b.Pulse:CreateAnimationGroup()
	local up = b.Pulse.Anim:CreateAnimation("Alpha")
	up:SetFromAlpha(0)
	up:SetToAlpha(1)
	up:SetDuration(0.35)
	up:SetOrder(1)
	local down = b.Pulse.Anim:CreateAnimation("Alpha")
	down:SetFromAlpha(1)
	down:SetToAlpha(0)
	down:SetDuration(0.9)
	down:SetOrder(2)
	b.Pulse.Anim:SetToFinalAlpha(true)
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
	-- Its place on the way back to a locked quest (1: do it first).
	b.OrderBack = b:CreateTexture(nil, "OVERLAY")
	b.OrderBack:SetTexture(T.circle)
	b.OrderBack:SetSize(18, 18)
	b.OrderBack:SetPoint("CENTER", b, "TOPLEFT", 2, -2)
	b.OrderBack:SetVertexColor(PATH_TONE[1], PATH_TONE[2], PATH_TONE[3], 1)
	b.Order = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.Order:SetPoint("CENTER", b.OrderBack, "CENTER", 0, 0)
	b.OrderBack:Hide()
	b.Order:Hide()
	b:SetHighlightTexture(T.highlight, "ADD")
	b:SetScript("OnEnter", CardEnter)
	b:SetScript("OnLeave", Untip)
	b:SetScript("OnClick", function(self)
		local it = self.item
		if it and it.stub then
			Untip(self)
			Graph.Jump(it.quest)
		elseif it then
			Graph.Pick(it.quest)
		end
	end)
	view.g.made = view.g.made + 1
	return b
end

-- A card: its tone (Attune's: done green, ready amber, in the log blue, the rest grey), the strip in
-- its status's colour, the start, "[12] Title", the giver (another zone: its name); friends, a
-- lead-in and what taking it closes are in its tooltip. A stub (a step in another zone): that zone's
-- name and the quest, dark. On the way back to a locked quest picked: lit and numbered, the rest dim.
function Graph.FillCard(b, it)
	local id = it.quest
	local q = Quest(id)
	local status = StatusOf(id)
	local c = TONE[status]
	local path = state.path
	local lit = path ~= nil and (path.on[id] ~= nil or (it.stub == true and q ~= nil and path.zones[ZoneOf(q) or ""] ~= nil))
	b.Glow:SetShown(id == state.picked)
	b.Strip:SetColorTexture(c[1], c[2], c[3], 1)
	b.Check:SetShown(status == "done")
	if it.stub then
		b.Bg:SetVertexColor(0.04, 0.04, 0.04, 0.9)
		Edges(b, 0.45, 0.45, 0.45, 0.7)
		b.Icon:SetTexture(T.map)
		b.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		b.Icon:SetDesaturated(status ~= "available" and status ~= "active")
		b.Icon:SetVertexColor(1, 1, 1)
		b.Title:SetText(q and ZoneOf(q) or "?")
		b.Title:SetTextColor(1, 0.82, 0)
		b.Info:SetText(LevelTag(q) .. GREY .. Title(id) .. "|r")
	else
		local bright = status == "done" or status == "available" or status == "active"
		b.Bg:SetVertexColor(bright and c[1] or 0.1, bright and c[2] or 0.1, bright and c[3] or 0.1, bright and 0.3 or 0.6)
		if id == state.picked then
			Edges(b, 1, 0.82, 0)
		elseif bright then
			Edges(b, c[1], c[2], c[3])
		else
			Edges(b, 0.4, 0.4, 0.4)
		end
		StartIcon(b.Icon, q, status)
		b.Title:SetText(LevelTag(q) .. Title(id))
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
		b.Info:SetText(GREY .. (where or "") .. "|r")
	end
	if lit and id ~= state.picked then
		Edges(b, PATH_TONE[1], PATH_TONE[2], PATH_TONE[3])
	end
	local order = path and path.order[id]
	b.Order:SetText(order and tostring(order) or "")
	b.Order:SetShown(order ~= nil)
	b.OrderBack:SetShown(order ~= nil)
	local alpha = status == "other" and 0.55 or it.lead and 0.8 or 1
	if path and not lit then
		alpha = alpha * Z.DIM
	end
	b:SetAlpha(alpha)
	if state.pulse == id then
		state.pulse = nil
		b.Pulse.Anim:Stop()
		b.Pulse.Anim:Play()
	end
end

function Graph.NewPill(canvas)
	local f = CreateFrame("Frame", nil, canvas)
	f:SetSize(G.PILL_W, G.PILL_H)
	f:SetFrameLevel(canvas:GetFrameLevel() + 5)
	local back = f:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0.05, 0.05, 0.05, 0.95)
	NewEdges(f)
	f.Text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.Text:SetPoint("CENTER", 0, 0)
	return f
end

-- "one of" (amber: any is enough), where the lines meet.
function Graph.FillPill(f)
	Edges(f, 0.851, 0.608, 0, 1)
	f.Text:SetText(L["one of"])
	f.Text:SetTextColor(1, 0.82, 0)
	f:SetWidth(math.max(G.PILL_W, f.Text:GetStringWidth() + 10))
end

---------------------------------------------------------------------------
-- Zone maps (the zone page's and the details' small one): the zone's art (LT.MapArt), markers and
-- threads of ours, the quest picked on it (its giver, turn-in, objective areas and the way between
-- them), my arrow
---------------------------------------------------------------------------

local NEAR = 8     -- px: markers this close are one
local MARKERS = 150
-- Markers' looks (the game's map icons): size, the art, the order a shared marker takes the look in.
local LOOK = {
	ready = { size = 24, atlas = "QuestTurnin", file = T.turnin, back = true, prio = 1 },
	repeatturnin = { size = 24, atlas = "QuestRepeatableTurnin", file = T.turnin, back = true, prio = 1 },
	["end"] = { size = 22, atlas = "QuestTurnin", file = T.turnin, back = true, prio = 1 },
	available = { size = 24, atlas = "QuestNormal", file = T.available, back = true, prio = 2 },
	daily = { size = 24, atlas = "QuestDaily", file = T.daily, back = true, prio = 2 },
	start = { size = 22, atlas = "QuestNormal", file = T.available, back = true, prio = 2 },
	trivial = { size = 20, atlas = "TrivialQuests", file = T.available, back = true, prio = 3 },
	progress = { size = 20, atlas = "QuestTurnin", file = T.progress, back = true, desat = true, tint = { 0.85, 0.85, 0.85 }, prio = 4 },
	level = { size = 18, atlas = "QuestNormal", file = T.available, back = true, desat = true, tint = { 0.85, 0.85, 0.85 }, prio = 5 },
	locked = { size = 16, atlas = "QuestNormal", file = T.available, back = true, desat = true, tint = { 0.6, 0.6, 0.6 }, prio = 6 },
	drop = { size = 34, circle = true, tint = { 1, 0.82, 0 }, alpha = 0.35, prio = 7 },
	done = { size = 11, circle = true, tint = TONE.done, alpha = 0.6, ring = true, prio = 8 },
	other = { size = 10, circle = true, tint = TONE.other, alpha = 0.55, ring = true, prio = 9 },
}
local OPEN = { ready = true, repeatturnin = true, available = true, daily = true, trivial = true, progress = true, level = true, locked = true }
Map.GOLD = { 1, 0.82, 0 }  -- (the colour of a quest without a chain on the map)
Map.AREA = { lit = { 0.42, 1 }, normal = { 0.22, 0.75 }, dim = { 0.07, 0.25 }, done = { 0.07, 0.2 } } -- fill, glow

-- The game's own map pin there (Q.Waypoint, Lodestar.lua; else C_Map's own here), a chat line saying so.
-- Nothing of the world map is touched.
function Map.PinAt(map, x, y, name)
	if not (map and x and y) then
		return false
	end
	local ok = false
	if Q.Waypoint then
		ok = Q.Waypoint(map, x, y) == true
	elseif C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates
		and not (C_Map.CanSetUserWaypointOnMap and not LT.Value(C_Map.CanSetUserWaypointOnMap, map)) then
		ok = pcall(function()
			C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x, y))
			if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
				C_SuperTrack.SetSuperTrackedUserWaypoint(true)
			end
		end)
	end
	if ok then
		LT.Print(("Lodestar: map pin set at %s (%s)."):format(name or "?", MapName(map) or "?"))
	end
	return ok
end

-- A marker's tooltip: each giver (or turn-in) at the spot and its quests, what each pin is; what a
-- click does. The zone page also lights the marker's chains (onEnter).
local function MarkerEnter(self)
	local m = self.owner
	if m.zoomable and GamepadCursor(self) then
		Map.Reveal(m, self.px, self.py)
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
			local note = spot.note or (m.noteOf and m.noteOf(spot)) -- (what the pin is: the zone page's, asked when shown)
			GameTooltip:AddLine("  " .. LevelTag(q) .. Title(spot.quest) .. (note and (GREY .. SEP .. note .. "|r") or ""), tone[1], tone[2], tone[3])
		elseif spot.note then
			GameTooltip:AddLine("  " .. spot.note, 0.8, 0.8, 0.8)
		end
	end
	if m.onClick and self.quests[2] then
		GameTooltip:AddLine(L["Click: choose one of its %d quests"]:format(#self.quests), 0.5, 0.75, 1)
	elseif m.onClick and self.quests[1] then
		GameTooltip:AddLine(L["Click: show %s"]:format(Title(self.quests[1])), 0.5, 0.75, 1)
		if m.zoomable and Rule.Step(self.quests[1]) then -- (the zone page's: the switch above it)
			GameTooltip:AddLine(L["Then Chain above the map: its quest chain"], 0.5, 0.75, 1)
		end
	end
	GameTooltip:AddLine(m.onClick and L["Right-click or Shift-click: map pin"] or L["Click: put a map pin there"], 0.5, 0.75, 1)
	GameTooltip:Show()
	if m.onEnter then
		m.onEnter(self)
	end
end

local function MarkerLeave(self)
	Untip(self)
	local m = self.owner
	if m.onLeave then
		m.onLeave(self)
	end
end

-- A click: its quest picked (several: a small list of them beside it to pick one); a right-click or
-- Shift-click (on the details' small map any click): the game's map pin there.
local function MarkerClick(self, button)
	local m = self.owner
	Untip(self)
	if button == "RightButton" or (IsShiftKeyDown and IsShiftKeyDown()) or not m.onClick then
		Map.PinAt(m.map, self.x, self.y, self.spots[1] and self.spots[1].label)
	elseif self.quests[2] then
		Map.Choose(m, self)
	elseif self.quests[1] then
		Map.CloseChooser(m)
		m.onClick(self.quests[1])
	end
end

-- The list of a pin's quests (a PopupList of ours, LT.Window: a click elsewhere closes it): each with
-- its icon, "[12] Title" in its status's colour and what it is; the quest picked ticked.
function Map.Choose(m, marker)
	if not m.chooser then
		m.chooser = LT.Window.PopupList(m.chooserOwner or m.frame, 300, function()
			return Map.Choices(m)
		end, function(id)
			if id and m.onClick then
				m.onClick(id)
			end
		end)
		-- A click anywhere but on it or its pin closes it (its owner is the whole page; the pin's own
		-- click opens or closes it).
		m.chooser:SetScript("OnEvent", function(self)
			if not (self:IsMouseOver() or (m.choosing and m.choosing:IsMouseOver())) then
				self:Hide()
			end
		end)
	end
	local list = m.chooser
	if list:IsShown() and m.choosing == marker then
		list:Hide() -- (the pin clicked again)
		return
	end
	m.choosing = marker
	list:ClearAllPoints()
	if m.ox + marker.px > m.width - 300 then
		list:SetPoint("TOPRIGHT", marker, "TOPLEFT", -4, 0)
	else
		list:SetPoint("TOPLEFT", marker, "TOPRIGHT", 4, 0)
	end
	list:Open()
end

function Map.Choices(m)
	local marker = m.choosing
	local entries = { { title = marker and marker.spots[1] and marker.spots[1].label or "" } }
	local status = {}
	for _, spot in ipairs(marker and marker.spots or EMPTY) do
		if spot.quest then
			status[spot.quest] = status[spot.quest] or spot
		end
	end
	for i, id in ipairs(marker and marker.quests or EMPTY) do
		if i > SHOWN.choose then
			entries[#entries + 1] = { note = L["... and %d more"]:format(#marker.quests - SHOWN.choose) }
			break
		end
		local spot = status[id]
		local tone = TONE[spot.status] or TONE.other
		local note = spot.note or (m.noteOf and m.noteOf(spot))
		entries[#entries + 1] = { value = id, selected = id == state.picked, text = (Q.QuestIcon and Q.QuestIcon(id, spot.status, 14) or "")
			.. " " .. LevelTag(Quest(id)) .. Hex(tone[1], tone[2], tone[3]) .. Title(id) .. "|r" .. (note and (GREY .. SEP .. note .. "|r") or "") }
	end
	return entries
end

function Map.CloseChooser(m)
	if m.chooser and m.chooser:IsShown() then
		m.chooser:Hide()
	end
end

-- A button on the map's strip (the zoom's: -, +, Fit): ours, the controller reaches it.
function Map.Tool(m, text, tip, onClick)
	local b = CreateFrame("Button", nil, m.StripFrame)
	b.Back = b:CreateTexture(nil, "BACKGROUND")
	b.Back:SetAllPoints()
	b.Back:SetColorTexture(0.12, 0.12, 0.12, 0.9)
	NewEdges(b)
	Edges(b, 1, 0.82, 0, 0.35)
	b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	b.Text:SetPoint("CENTER", 0, 0)
	b.Text:SetText(text)
	b:SetSize(math.max(Z.TOOL, b.Text:GetStringWidth() + 14), Z.TOOL - 4)
	b:SetHighlightTexture(T.highlight, "ADD")
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(tip, 1, 1, 1)
		GameTooltip:AddLine(L["Wheel: zoom where the cursor is. Drag: move the map."], 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", Untip)
	return b
end

-- The cursor's spot on the box (px from its top left), or nil (not over it, or the game won't say).
function Map.CursorOnBox(m)
	local left, top = m.frame:GetLeft(), m.frame:GetTop()
	local x, y = GetCursorPosition()
	local scale = m.frame:GetEffectiveScale()
	if not (left and top and x and y and scale and scale > 0) then
		return nil
	end
	local bx, by = x / scale - left, top - y / scale
	if bx < 0 or by < 0 or bx > m.width or by > m.height then
		return nil
	end
	return bx, by
end

function Map.New(parent, width, height, zoomable)
	local m = { markers = {}, used = 0, shown = 0, width = width, height = height, zoom = 1, ox = 0, oy = 0, zoomable = zoomable,
		lines = {}, linesShown = 0, areas = {}, areasShown = 0, route = {}, routeShown = 0, ends = {} }
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
	m.art = LT.MapArt.New(m.Map, nil, nil, nil, true) -- (every area uncovered)
	-- Over the art, under the pins: the quest picked's objective areas and the way between them.
	m.Areas = CreateFrame("Frame", nil, m.Map)
	m.Areas:SetAllPoints(m.Map)
	m.Areas:SetFrameLevel(m.Map:GetFrameLevel() + 1)
	-- Over the pins: my arrow, moved ten times a second while I'm on this map (else hidden: nothing runs).
	m.Top = CreateFrame("Frame", nil, m.Map)
	m.Top:SetAllPoints(m.Map)
	m.Top:SetFrameLevel(m.Map:GetFrameLevel() + 8)
	m.You = m.Top:CreateTexture(nil, "OVERLAY")
	m.You:SetTexture(T.arrow)
	m.You:SetSize(22, 22)
	m.You:Hide()
	m.Top:Hide()
	local wait = 0
	m.Top:SetScript("OnUpdate", function(_, elapsed)
		wait = wait - (elapsed or 0)
		if wait <= 0 then
			wait = 0.1
			Map.PlaceMe(m)
		end
	end)
	-- The strip over its top: the zone's name (and on the zone page the zoom's buttons at its right).
	m.StripFrame = CreateFrame("Frame", nil, box)
	m.StripFrame:SetPoint("TOPLEFT")
	m.StripFrame:SetPoint("TOPRIGHT")
	m.StripFrame:SetHeight(zoomable and Z.TOOL or 18)
	m.StripFrame:SetFrameLevel(m.Map:GetFrameLevel() + 10)
	m.Strip = m.StripFrame:CreateTexture(nil, "BACKGROUND")
	m.Strip:SetAllPoints()
	m.Strip:SetColorTexture(0, 0, 0, 0.6)
	m.Zone = m.StripFrame:CreateFontString(nil, "OVERLAY", zoomable and "GameFontNormal" or "GameFontNormalSmall")
	m.Zone:SetPoint("LEFT", 6, 0)
	m.Zone:SetPoint("RIGHT", zoomable and -160 or -6, 0)
	m.Zone:SetJustifyH("LEFT")
	m.Zone:SetWordWrap(false)
	m.Empty = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	m.Empty:SetPoint("CENTER", 0, -6)
	m.Empty:SetText(L["No map of this zone"])
	m.Empty:Hide()
	if zoomable then
		box:EnableMouse(true)
		box:EnableMouseWheel(true)
		box:RegisterForDrag("LeftButton")
		box:SetScript("OnMouseWheel", function(_, delta)
			Map.SetZoom(m, m.zoom * (delta > 0 and G.MAP_STEP or 1 / G.MAP_STEP), Map.CursorOnBox(m))
		end)
		box:SetScript("OnDragStart", function(self)
			Map.CloseChooser(m)
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
		-- -, +, Fit (the controller's way to zoom; its cursor on a pin out of sight moves the map there).
		local function Step(dir)
			Map.SetZoom(m, m.zoom * (dir > 0 and G.MAP_STEP or 1 / G.MAP_STEP))
		end
		m.buttons = {
			fit = Map.Tool(m, L["Fit"], L["The whole zone"], function() Map.SetZoom(m, 1) end),
			plus = Map.Tool(m, "+", L["Zoom in"], function() Step(1) end),
			minus = Map.Tool(m, "-", L["Zoom out"], function() Step(-1) end),
		}
		m.buttons.fit:SetPoint("RIGHT", m.StripFrame, "RIGHT", -4, 0)
		m.buttons.plus:SetPoint("RIGHT", m.buttons.fit, "LEFT", -4, 0)
		m.buttons.minus:SetPoint("RIGHT", m.buttons.plus, "LEFT", -4, 0)
		m.ZoomText = m.StripFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		m.ZoomText:SetPoint("RIGHT", m.buttons.minus, "LEFT", -6, 0)
		m.ZoomText:SetText("")
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

-- Zoomed (1: the whole zone, up to 8), the map's spot under (bx, by) (the box's px from its top left;
-- nil: its middle) staying where it is: the wheel zooms where the cursor is, the buttons in the middle.
function Map.SetZoom(m, zoom, bx, by)
	zoom = math.max(G.MAP_MIN, math.min(G.MAP_MAX, zoom))
	if zoom == m.zoom or not m.map then
		return
	end
	bx, by = bx or m.width / 2, by or m.height / 2
	local fx = (bx - m.ox) / (m.artW or m.width)
	local fy = (by - m.oy) / (m.artH or m.height)
	m.zoom = zoom
	Map.Show(m, m.map, m.spots, m.name, m.threads)
	Map.Pan(m, bx - fx * m.artW, by - fy * m.artH)
	if m.ZoomText then
		m.ZoomText:SetText(zoom > 1 and ("%d%%"):format(math.floor(zoom * 100 + 0.5)) or "")
	end
	if m.onZoom then
		m.onZoom(zoom)
	end
end

-- Me, where I am on this map (Q.PlayerAt: nil off it, in an instance, or when the game won't say),
-- turned the way I face. True when I'm on it.
function Map.PlaceMe(m)
	local x, y
	if m.map and m.frame:IsShown() and Q.PlayerAt then
		x, y = Q.PlayerAt(m.map)
	end
	if not (x and y) then
		m.You:Hide()
		m.Top:Hide()
		return false
	end
	m.You:ClearAllPoints()
	m.You:SetPoint("CENTER", m.Map, "TOPLEFT", x * (m.artW or m.width), -y * (m.artH or m.height))
	local facing = LT.Value(GetPlayerFacing)
	if type(facing) == "number" then
		m.You:SetRotation(facing)
	end
	m.You:Show()
	m.Top:Show()
	return true
end

-- The map's art, the markers and the threads on it. spots = { { x, y, look, label, quest, status,
-- note, chain } }: spots closer than a few px are one marker (its tooltip lists them all; its look the
-- first by LOOK's order; how many quests to do it has in a badge); a drop area only with drop areas.
-- threads = { { key, color, segs = { { x1, y1, x2, y2, done } } } } (0..1 on the map): a chain's
-- line from giver to turn-in to the next giver. The quest picked (Map.SetPick) over it, my arrow.
function Map.Show(m, map, spots, name, threads)
	local same = m.map == map
	m.map, m.spots, m.name, m.threads = map, spots, name, threads
	m.frame:Show()
	Map.CloseChooser(m)
	if not same then
		m.zoom, m.ox, m.oy = 1, 0, 0
		if m.ZoomText then
			m.ZoomText:SetText("")
		end
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
	m.StripFrame:SetShown(map ~= nil)
	local n = 0
	for _, spot in ipairs(map and spots or EMPTY) do
		local x, y = tonumber(spot.x), tonumber(spot.y)
		if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
			local px, py = x * width, y * height
			local drop = spot.look == "drop"
			local near
			for i = 1, n do
				local marker = m.markers[i]
				if marker.drop == drop and math.abs(marker.px - px) <= NEAR and math.abs(marker.py - py) <= NEAR then
					near = marker
					break
				end
			end
			if near then
				near.spots[#near.spots + 1] = spot
				if (LOOK[spot.look] or LOOK.other).prio < (LOOK[near.look] or LOOK.other).prio then
					near.look = spot.look
				end
			elseif n < MARKERS then
				n = n + 1
				local marker = Map.Marker(m, n)
				marker.px, marker.py, marker.x, marker.y, marker.look, marker.drop = px, py, x, y, spot.look, drop
				marker.area = tonumber(spot.r) and drop and math.floor(spot.r * width * 2 + 0.5) or nil
				marker.spots = { spot }
				marker:ClearAllPoints()
				marker:SetPoint("CENTER", m.Map, "TOPLEFT", px, -py)
			end
		end
	end
	-- Each marker's quests, the one to do first first, how many of them are still to do, its chains.
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
		local quests, seen, chains, open = {}, {}, {}, 0
		for _, spot in ipairs(marker.spots) do
			if spot.quest and not seen[spot.quest] then
				seen[spot.quest] = true
				quests[#quests + 1] = spot.quest
				open = open + (OPEN[spot.look] and 1 or 0)
			end
			if spot.chain then
				chains[spot.chain] = true
			end
		end
		marker.quests, marker.chains, marker.open = quests, chains, open
		Map.Paint(marker)
	end
	for i = n + 1, m.used do
		Untip(m.markers[i])
		m.markers[i]:Hide()
	end
	m.used = math.max(n, m.used)
	m.shown = n
	Map.DrawThreads(m, map and threads or nil, width, height)
	Map.DrawPick(m, width, height)
	Map.PlaceMe(m)
end

function Map.Marker(m, i)
	local marker = m.markers[i]
	if not marker then
		marker = CreateFrame("Button", nil, m.Map)
		marker.owner = m
		marker:SetFrameLevel(m.Map:GetFrameLevel() + 3)
		marker:RegisterForClicks("LeftButtonUp", "RightButtonUp")
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
		-- How many quests to do it has (two or more), on a dark dot at its top right.
		marker.BadgeBack = marker:CreateTexture(nil, "OVERLAY")
		marker.BadgeBack:SetTexture(T.circle)
		marker.BadgeBack:SetVertexColor(0.05, 0.05, 0.05, 0.95)
		marker.BadgeBack:SetSize(15, 15)
		marker.BadgeBack:SetPoint("CENTER", marker, "TOPRIGHT", 0, 0)
		marker.Badge = marker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		marker.Badge:SetPoint("CENTER", marker.BadgeBack, "CENTER", 0, 0)
		marker:SetScript("OnEnter", MarkerEnter)
		marker:SetScript("OnLeave", MarkerLeave)
		marker:SetScript("OnClick", MarkerClick)
		m.markers[i] = marker
	end
	marker:Show()
	return marker
end

-- A marker's look: solid and clear (a dark disc under the "!" and "?"), done and not-for-me dim dots,
-- drop areas soft circles; a gold ring when it has the quest picked; how many it has to do.
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
	local badge = (marker.open or 0) >= 2 and not marker.drop
	marker.Badge:SetText(badge and tostring(marker.open) or "")
	marker.Badge:SetShown(badge)
	marker.BadgeBack:SetShown(badge)
	marker:SetAlpha(1)
end

-- The markers' rings again (another quest picked).
function Map.Repaint(m)
	for i = 1, m.shown do
		Map.Paint(m.markers[i])
	end
	Map.Light(m, m.lit)
end

-- The chains' threads (pooled lines on the map, under the markers).
function Map.DrawThreads(m, threads, width, height)
	local n = 0
	for _, t in ipairs(threads or EMPTY) do
		for _, s in ipairs(t.segs) do
			if n >= SHOWN.threads then
				break
			end
			n = n + 1
			local line = m.lines[n]
			if not line then
				line = m.Map:CreateLine(nil, "OVERLAY", nil, 1)
				m.lines[n] = line
			end
			line.key, line.done, line.color = t.key, s.done, t.color
			line:SetStartPoint("TOPLEFT", m.Map, s.x1 * width, -s.y1 * height)
			line:SetEndPoint("TOPLEFT", m.Map, s.x2 * width, -s.y2 * height)
		end
	end
	for i = n + 1, #m.lines do
		m.lines[i].key = nil
		m.lines[i]:Hide()
	end
	m.linesShown = n
	Map.Light(m, m.lit)
end

-- Chains lit (lit: a chain's key, its card hovered; or a set of keys, a pin hovered: its chains): their
-- pins and threads, every other pin dim; nil: none. A thread shows only for the chains lit, else for
-- the one with the quest picked (m.keep: fainter while the quest's own way shows); the others hidden.
function Map.Light(m, lit)
	m.lit = lit
	local set = type(lit) == "table" and lit or nil
	local function On(key)
		if set then
			return key ~= nil and set[key] == true
		end
		return key ~= nil and key == lit
	end
	for i = 1, m.linesShown do
		local line = m.lines[i]
		local c = line.color
		if lit ~= nil and On(line.key) then
			line:SetThickness(3.5)
			line:SetColorTexture(c[1], c[2], c[3], 1)
			line:Show()
		elseif lit == nil and m.keep ~= nil and line.key == m.keep then
			local a = line.done and 0.25 or 0.7
			line:SetThickness(2)
			line:SetColorTexture(c[1], c[2], c[3], m.areasShown > 0 and a * 0.6 or a)
			line:Show()
		else
			line:Hide()
		end
	end
	for i = 1, m.shown do
		local marker = m.markers[i]
		local on = lit == nil
		for key in pairs(lit ~= nil and marker.chains or EMPTY) do
			on = on or On(key)
		end
		marker:SetAlpha(on and 1 or Z.PIN_DIM)
	end
end

-- The quest picked on this map (pick: { quest, map, color, areas = { { x, y, r, objective, label, note,
-- done } }, start = { x, y, label }, finish = { x, y, label, ready }, route = { { x, y } } }; nil: none),
-- drawn on it now.
function Map.SetPick(m, pick)
	m.pick = pick
	m.litArea = nil
	if m.frame:IsShown() and m.artW then
		Map.DrawPick(m, m.artW, m.artH)
		Map.Light(m, m.lit)
	end
end

-- An objective area: a soft circle (a flat disc and a glow around it, in the chain's colour) and a
-- small button at its middle (its tooltip says what's to do there; a click sets the map pin there).
function Map.Area(m, i)
	local a = m.areas[i]
	if not a then
		a = {}
		a.Glow = m.Areas:CreateTexture(nil, "BORDER")
		a.Glow:SetTexture(T.glow)
		a.Glow:SetBlendMode("ADD")
		a.Fill = m.Areas:CreateTexture(nil, "ARTWORK")
		a.Fill:SetTexture(T.circle)
		local b = CreateFrame("Button", nil, m.Map)
		b:SetFrameLevel(m.Map:GetFrameLevel() + 2)
		b:SetSize(16, 16)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b.Back = b:CreateTexture(nil, "BORDER")
		b.Back:SetTexture(T.circle)
		b.Back:SetVertexColor(0, 0, 0, 0.85)
		b.Back:SetAllPoints()
		b.Dot = b:CreateTexture(nil, "ARTWORK")
		b.Dot:SetTexture(T.circle)
		b.Dot:SetSize(9, 9)
		b.Dot:SetPoint("CENTER")
		b.Check = b:CreateTexture(nil, "OVERLAY")
		b.Check:SetSize(14, 14)
		b.Check:SetPoint("CENTER")
		Art(b.Check, "common-icon-checkmark", T.check)
		b:SetHighlightTexture(T.highlight, "ADD")
		b.owner, b.area = m, a
		b:SetScript("OnEnter", function(self)
			local spec = self.area.spec
			if m.zoomable and GamepadCursor(self) then
				Map.Reveal(m, spec.x * m.artW, spec.y * m.artH)
			end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(spec.label or "?", 1, 1, 1, 1, true)
			if spec.note then
				GameTooltip:AddLine(spec.note, 0.8, 0.8, 0.8, true)
			end
			if spec.done then
				GameTooltip:AddLine(L["Done"], TONE.done[1], TONE.done[2], TONE.done[3])
			end
			GameTooltip:AddLine(L["Click: put a map pin there"], 0.5, 0.75, 1)
			GameTooltip:Show()
			Map.LightArea(m, spec.objective)
		end)
		b:SetScript("OnLeave", function(self)
			Untip(self)
			Map.LightArea(m, nil)
		end)
		b:SetScript("OnClick", function(self)
			Untip(self)
			local spec = self.area.spec
			Map.PinAt(m.map, spec.x, spec.y, spec.label)
		end)
		a.Button = b
		m.areas[i] = a
	end
	return a
end

-- The giver or turn-in of the quest picked where no pin of it is (a "!" or "?", ringed): kind 1 the
-- giver, 2 the turn-in.
function Map.End(m, kind)
	local b = m.ends[kind]
	if not b then
		b = CreateFrame("Button", nil, m.Map)
		b:SetFrameLevel(m.Map:GetFrameLevel() + 3)
		b:SetSize(24, 24)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b.Ring = b:CreateTexture(nil, "BACKGROUND")
		b.Ring:SetTexture(T.circle)
		b.Ring:SetVertexColor(1, 0.82, 0, 0.8)
		b.Ring:SetSize(34, 34)
		b.Ring:SetPoint("CENTER")
		b.Back = b:CreateTexture(nil, "BORDER")
		b.Back:SetTexture(T.circle)
		b.Back:SetVertexColor(0, 0, 0, 0.8)
		b.Back:SetSize(28, 28)
		b.Back:SetPoint("CENTER")
		b.Icon = b:CreateTexture(nil, "ARTWORK")
		b.Icon:SetSize(22, 22)
		b.Icon:SetPoint("CENTER")
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.spec.label or "?", 1, 1, 1)
			GameTooltip:AddLine(kind == 1 and L["Quest giver"] or L["Turn-in"], 0.8, 0.8, 0.8)
			if m.pick then
				GameTooltip:AddLine(LevelTag(Quest(m.pick.quest)) .. Title(m.pick.quest), 1, 0.82, 0)
			end
			GameTooltip:AddLine(L["Click: put a map pin there"], 0.5, 0.75, 1)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", Untip)
		b:SetScript("OnClick", function(self)
			Untip(self)
			Map.PinAt(m.map, self.spec.x, self.spec.y, self.spec.label)
		end)
		m.ends[kind] = b
	end
	return b
end

-- Whether a marker of the quest picked is at (px, py) already (its giver's pin, or its turn-in's
-- for one in my log).
function Map.PinnedAt(m, id, px, py)
	for i = 1, m.shown do
		local marker = m.markers[i]
		if math.abs(marker.px - px) <= NEAR and math.abs(marker.py - py) <= NEAR then
			for _, q in ipairs(marker.quests) do
				if q == id then
					return true
				end
			end
		end
	end
	return false
end

-- The quest picked: its areas, its giver and turn-in where no pin of it is, the way between them
-- (dashed, in its chain's colour: giver -> objectives -> turn-in).
function Map.DrawPick(m, width, height)
	local pick = m.map and m.pick and m.pick.map == m.map and m.pick or nil
	local c = pick and pick.color or Map.GOLD
	local n = 0
	for _, spec in ipairs(pick and pick.areas or EMPTY) do
		if n >= SHOWN.areas then
			break
		end
		n = n + 1
		local a = Map.Area(m, n)
		a.spec = spec
		local px, py = spec.x * width, spec.y * height
		local size = math.max(28, math.min(width * 0.5, (tonumber(spec.r) or 0.02) * 2 * width))
		a.Fill:SetSize(size, size)
		a.Glow:SetSize(size * 1.5, size * 1.5)
		for _, t in ipairs({ a.Fill, a.Glow }) do
			t:ClearAllPoints()
			t:SetPoint("CENTER", m.Map, "TOPLEFT", px, -py)
			t:Show()
		end
		a.Button:ClearAllPoints()
		a.Button:SetPoint("CENTER", m.Map, "TOPLEFT", px, -py)
		a.Button.Dot:SetVertexColor(c[1], c[2], c[3], 1)
		a.Button.Dot:SetShown(not spec.done)
		a.Button.Check:SetShown(spec.done == true)
		a.Button:Show()
	end
	for i = n + 1, #m.areas do
		local a = m.areas[i]
		a.spec = nil
		a.Fill:Hide()
		a.Glow:Hide()
		Untip(a.Button)
		a.Button:Hide()
	end
	m.areasShown = n
	-- Its giver and turn-in where no pin of it is.
	for kind, spec in ipairs({ pick and pick.start or false, pick and pick.finish or false }) do
		local b = m.ends[kind]
		if spec and not Map.PinnedAt(m, pick.quest, spec.x * width, spec.y * height) then
			b = Map.End(m, kind)
			b.spec = spec
			Art(b.Icon, kind == 1 and "QuestNormal" or "QuestTurnin", kind == 1 and T.available or T.turnin)
			b.Icon:SetDesaturated(kind == 2 and not spec.ready)
			b:ClearAllPoints()
			b:SetPoint("CENTER", m.Map, "TOPLEFT", spec.x * width, -spec.y * height)
			b:Show()
		elseif b then
			Untip(b)
			b:Hide()
		end
	end
	-- The way: dashed (8 on, 6 off, longer dashes on a long way), at most so many dashes a stretch.
	local r = 0
	local route = pick and pick.route or EMPTY
	for i = 2, #route do
		local x1, y1, x2, y2 = route[i - 1].x * width, route[i - 1].y * height, route[i].x * width, route[i].y * height
		local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
		if len > 1 then
			local dash = math.max(8, len / SHOWN.dashes * 0.6)
			local gap = dash * 0.75
			local d = 0
			while d < len do
				local stop = math.min(len, d + dash)
				r = r + 1
				local line = m.route[r]
				if not line then
					line = m.Areas:CreateLine(nil, "OVERLAY")
					m.route[r] = line
				end
				line:SetThickness(2.5)
				line:SetColorTexture(c[1], c[2], c[3], 0.9)
				line:SetStartPoint("TOPLEFT", m.Map, x1 + (x2 - x1) * d / len, -(y1 + (y2 - y1) * d / len))
				line:SetEndPoint("TOPLEFT", m.Map, x1 + (x2 - x1) * stop / len, -(y1 + (y2 - y1) * stop / len))
				line:Show()
				d = stop + gap
			end
		end
	end
	for i = r + 1, #m.route do
		m.route[i]:Hide()
	end
	m.routeShown = r
	Map.LightArea(m, m.litArea)
end

-- One objective's areas lit (its line in the details hovered), the others dim; nil: all as they are.
-- A done objective's areas stay faint.
function Map.LightArea(m, objective)
	m.litArea = objective
	local c = m.pick and m.pick.color or Map.GOLD
	for i = 1, m.areasShown do
		local a = m.areas[i]
		local spec = a.spec
		local look = spec.done and Map.AREA.done or objective == nil and Map.AREA.normal
			or spec.objective == objective and Map.AREA.lit or Map.AREA.dim
		a.Fill:SetVertexColor(c[1], c[2], c[3], look[1])
		a.Glow:SetVertexColor(c[1], c[2], c[3], look[2])
	end
end

---------------------------------------------------------------------------
-- The zone page: the map with its pins and threads, the chains' cards, what's here for me
---------------------------------------------------------------------------

-- A quest's pin on the zone map: in my log its turn-in ("?", grey while not done yet), else its
-- giver: "!" (a low level one's, a repeatable one's), a grey "!" for later, dots for done and not for me.
function ZonePage.Look(id, q, status)
	if status == "active" then
		if IsReady(id) then
			return q.repeatable and "repeatturnin" or "ready"
		end
		return "progress"
	elseif status == "available" then
		if q.repeatable then
			return "daily"
		end
		return Trivial(id) and "trivial" or "available"
	end
	return status
end

-- The first spot on this map of a list of givers or enders, and who it is.
local function FirstOn(list, map)
	for _, s in ipairs(list or EMPTY) do
		for _, p in ipairs(s.points or EMPTY) do
			if p.map == map then
				return p, s
			end
		end
	end
end

-- The zone map's pins (every giver of the zone's quests as the filters show them, the turn-ins of
-- quests in my log, where items that start a quest drop; within my levels unless all are asked for)
-- and each chain's thread (giver -> turn-in -> the next giver, the spots on this map). Kept until a
-- status or the filters change.
function ZonePage.Spots(place)
	local cached = state.spots[place.id]
	if cached then
		return cached.spots, cached.threads
	end
	local tree = Structure(place)
	local map = place.map
	local spots, threads, segs = {}, {}, 0
	for _, id in ipairs(tree.ids) do
		local status = StatusOf(id)
		local q = Quest(id)
		if q and Rule.Shown(id, status) then
			local group = tree.groupOf[id]
			local key = group and group.key
			local look = ZonePage.Look(id, q, status)
			local list = status == "active" and q.ends or q.starts
			for _, s in ipairs(list or EMPTY) do
				for _, p in ipairs(s.points or EMPTY) do
					if p.map == map then
						spots[#spots + 1] = { x = p.x, y = p.y, look = look, label = s.name, quest = id, status = status, chain = key }
					end
				end
				if status ~= "active" and s.kind == "item" then
					for _, d in ipairs(s.drops or EMPTY) do
						for _, p in ipairs(d.points or EMPTY) do
							if p.map == map then
								spots[#spots + 1] = { x = p.x, y = p.y, r = p.r, look = "drop", label = L["%s drops here (%s%%)"]:format(s.name or "?", Chance(d.chance)),
									quest = id, status = status, chain = key, note = d.name }
							end
						end
					end
				end
			end
		end
	end
	for _, group in ipairs(tree.groups) do
		if not group.single then
			local list, giver, ender, shown = {}, {}, {}, {}
			local function Seg(a, b, done)
				if a and b and segs < SHOWN.threads and (math.abs(a.x - b.x) > 0.004 or math.abs(a.y - b.y) > 0.004) then
					segs = segs + 1
					list[#list + 1] = { x1 = a.x, y1 = a.y, x2 = b.x, y2 = b.y, done = done }
				end
			end
			for _, id in ipairs(group.chain) do
				local q = Quest(id)
				local status = StatusOf(id)
				if q and Rule.Shown(id, status) then
					shown[id] = status
					giver[id], ender[id] = FirstOn(q.starts, map), FirstOn(q.ends, map)
					Seg(giver[id], ender[id], status == "done")
				end
			end
			for _, to in ipairs(group.chain) do
				for _, from in ipairs(shown[to] and group.parents[to] or EMPTY) do
					if shown[from] then
						Seg(ender[from] or giver[from], giver[to], shown[from] == "done" and shown[to] == "done")
					end
				end
			end
			if list[1] then
				threads[#threads + 1] = { key = group.key, color = Chains.Color(group), segs = list }
			end
		end
	end
	state.spots[place.id] = { spots = spots, threads = threads }
	return spots, threads
end

-- The zone's map with its pins and threads, the quest picked on it. (A dungeon has no map: its
-- Zone tab is its quest list.)
function ZonePage.DrawMap(place)
	local zp = view.zp
	if not place or place.kind ~= "zone" then
		zp.map.frame:Hide()
		return
	end
	local spots, threads = ZonePage.Spots(place)
	ZonePage.Keep(place)
	zp.map.pick, zp.map.litArea = ZonePage.PickOn(place.map, state.picked, Structure(place).groupOf[state.picked or 0]), nil
	Map.Show(zp.map, place.map, spots, LevelSpan(place.minLevel, place.maxLevel) and (place.name .. GREY .. "  " .. Range(place) .. "|r") or place.name, threads)
end

-- The quest picked on a map: its chain's colour, its objectives' areas there (Q.Objectives; done
-- ones, as my quest log says, faint), its giver and turn-in there, and the way between them: from
-- the giver to each objective's nearest area in turn, then to the turn-in. nil: nothing of it there.
function ZonePage.PickOn(map, id, group)
	local q = id and map and Quest(id)
	if not q then
		return nil
	end
	local pick = { quest = id, map = map, color = group and not group.single and Chains.Color(group) or Map.GOLD, areas = {} }
	local p, who = FirstOn(q.starts, map)
	pick.start = p and { x = p.x, y = p.y, label = who.name }
	p, who = FirstOn(q.ends, map)
	pick.finish = p and { x = p.x, y = p.y, label = who.name, ready = IsReady(id) }
	local list = Task.List(id)
	local done = {}
	for _, line in ipairs(Task.Progress(id, list) or EMPTY) do
		if line.objective then
			done[line.objective] = line.done
		end
	end
	for i, o in ipairs(list) do
		local label = Task.Text(o)
		for _, s in ipairs(type(o.sources) == "table" and o.sources or EMPTY) do
			local note = o.kind == "item" and tonumber(s.chance) and L["Drops from %s (%s%%)"]:format(s.name or "?", Chance(s.chance)) or nil
			for _, point in ipairs(s.points or EMPTY) do
				if point.map == map and tonumber(point.x) and tonumber(point.y) then
					pick.areas[#pick.areas + 1] = { x = point.x, y = point.y, r = point.r, objective = i, label = label, note = note,
						done = done[i] == true }
				end
			end
		end
	end
	if not (pick.start or pick.finish or pick.areas[1]) then
		return nil
	end
	local route, at = {}, pick.start
	route[1] = at
	for i = 1, #list do
		local best, bestD
		for _, a in ipairs(pick.areas) do
			if a.objective == i and not a.done then
				local d = at and ((a.x - at.x) * 1.5) ^ 2 + (a.y - at.y) ^ 2 or 0
				if not bestD or d < bestD then
					best, bestD = a, d
				end
			end
		end
		if best then
			route[#route + 1] = best
			at = best
		end
	end
	route[#route + 1] = pick.finish
	pick.route = route
	return pick
end

-- The quest picked: on the zone's map now (its pins' rings, its chain's thread, its own way).
function ZonePage.ShowPick(place)
	local m = view.zp.map
	ZonePage.Keep(place)
	Map.SetPick(m, place and place.kind == "zone" and ZonePage.PickOn(place.map, state.picked, Structure(place).groupOf[state.picked or 0]) or nil)
	Map.Repaint(m)
end

-- Zoomed in, nothing of the quest picked in sight (its giver, turn-in, areas): the map centred on them.
function Map.Follow(m)
	local pick = m.pick
	if not (pick and m.zoom > 1 and m.artW) then
		return
	end
	local x0, x1, y0, y1
	for _, s in ipairs({ pick.start or false, pick.finish or false }) do
		if s then
			x0, x1, y0, y1 = math.min(x0 or s.x, s.x), math.max(x1 or s.x, s.x), math.min(y0 or s.y, s.y), math.max(y1 or s.y, s.y)
		end
	end
	for _, a in ipairs(pick.areas) do
		x0, x1, y0, y1 = math.min(x0 or a.x, a.x), math.max(x1 or a.x, a.x), math.min(y0 or a.y, a.y), math.max(y1 or a.y, a.y)
	end
	if not x0 then
		return
	end
	local function Seen(x, y)
		local px, py = m.ox + x * m.artW, m.oy + y * m.artH
		return px >= 0 and px <= m.width and py >= 0 and py <= m.height
	end
	for _, s in ipairs({ pick.start or false, pick.finish or false }) do
		if s and Seen(s.x, s.y) then
			return
		end
	end
	for _, a in ipairs(pick.areas) do
		if Seen(a.x, a.y) then
			return
		end
	end
	Map.CloseChooser(m)
	Map.Pan(m, m.width / 2 - (x0 + x1) / 2 * m.artW, m.height / 2 - (y0 + y1) / 2 * m.artH)
end

-- The thread shown while no card is hovered: the chain of the quest picked (none: no thread).
function ZonePage.Keep(place)
	local group = place and state.picked and Structure(place).groupOf[state.picked]
	view.zp.map.keep = group and not group.single and group.key or nil
end

-- What a pin is, in its tooltip (the legend there was): ready to turn in, in progress, low level,
-- repeatable, or the reason it can't be taken yet.
function ZonePage.PinNote(spot)
	local look = spot.look
	if look == "ready" or look == "repeatturnin" then
		return L["ready to turn in"]
	elseif look == "progress" then
		return L["in progress"]
	elseif look == "trivial" then
		return L["low level"]
	elseif look == "daily" then
		return L["repeatable"]
	elseif look ~= "available" and look ~= "drop" then
		return Rule.Reason(spot.quest, spot.status)
	end
end

-- A zone (my level, give or take 3) with the most quests for my level (Rule.ForMyLevel: I can take them
-- now within my levels, or have them), for when this one has none to pick up.
function ZonePage.Suggest(place)
	if state.suggest ~= nil and state.suggestFor == place.id then
		return state.suggest or nil
	end
	local my = tonumber(UnitLevel and LT.Value(UnitLevel, "player")) or 1
	local best, most = nil, 0
	for _, z in ipairs(state.zones or EMPTY) do
		if z.map ~= place.map and (z.minLevel or 1) <= my + 3 and (z.maxLevel or 60) >= my - 3 then
			local n = 0
			for _, id in ipairs(Q.ZoneQuests and Q.ZoneQuests(z.map) or EMPTY) do
				n = n + (Rule.ForMyLevel(id, StatusOf(id)) and 1 or 0)
			end
			if n > most then
				best, most = z, n
			end
		end
	end
	state.suggest = best and { map = best.map, name = best.name or MapName(best.map) or "?", n = most } or false
	state.suggestFor = place.id
	return state.suggest or nil
end

-- Under the map, one line: what of ready to turn in, in progress and available (within my levels as
-- the pins) there is (the briefing has how far along); with none to take here, a zone that has some;
-- else, at its right, how the map works.
function ZonePage.DrawSummary(place)
	local zp = view.zp
	local n = { active = 0, ready = 0, available = 0 }
	for _, id in ipairs(place and Structure(place).ids or EMPTY) do
		local s = StatusOf(id)
		if s == "active" then
			local ready = IsReady(id)
			n.active, n.ready = n.active + (ready and 0 or 1), n.ready + (ready and 1 or 0)
		elseif s == "available" and Rule.InLevels(id, s) then
			n.available = n.available + 1
		end
	end
	local parts = {}
	for _, p in ipairs({ { n.ready, GOLD, L["%d ready to turn in"] }, { n.active, HEX.active, L["%d in progress"] },
		{ n.available, HEX.available, L["%d available"] } }) do
		if p[1] > 0 then
			parts[#parts + 1] = p[2] .. p[3]:format(p[1]) .. "|r"
		end
	end
	zp.Counts:SetText(table.concat(parts, GREY .. SEP .. "|r"))
	local none = place ~= nil and n.available == 0
	local suggest = none and ZonePage.Suggest(place) or nil
	zp.Guide:SetShown(none)
	zp.Guide:SetText(L["Nothing for you to pick up here right now."])
	zp.Guide:ClearAllPoints()
	zp.Guide:SetPoint("LEFT", zp.Counts, "RIGHT", parts[1] and 12 or 0, 0)
	zp.Suggest.map = suggest and suggest.map or nil
	if suggest then
		zp.Suggest.Text:SetText(L["%s has %d for your level"]:format(suggest.name, suggest.n) .. "  >")
		zp.Suggest:SetWidth(zp.Suggest.Text:GetStringWidth() + 12)
	end
	zp.Suggest:SetShown(suggest ~= nil)
	zp.Hint:SetShown(not none)
	return n
end

-- The chains' cards: those with a quest here not done yet within my levels (all levels: any the
-- filters show), then the quests without a chain, then the done chains folded under "Completed (N)",
-- and when the level filter left some out, a quiet line that says how many (a click shows all
-- levels). Also how many chains are listed.
function ZonePage.Entries(place)
	local entries, done, single, hidden = {}, {}, nil, 0
	for _, group in ipairs(Structure(place).groups) do
		local info = Chains.Info(group, place)
		if info.visible > 0 then
			local e = { group = group, info = info, key = group.key }
			if info.kind == "done" and not group.single then
				done[#done + 1] = e
			elseif not info.inLevels then
				hidden = hidden + 1
			elseif group.single then
				single = e
			else
				entries[#entries + 1] = e
			end
		end
	end
	local chains = #entries + #done
	entries[#entries + 1] = single
	if done[1] then
		local key = place.id .. ":done"
		if state.folded[key] == nil then
			state.folded[key] = true -- (done ones start folded)
		end
		entries[#entries + 1] = { fold = true, key = key, n = #done, closed = state.folded[key] }
		for _, e in ipairs(not state.folded[key] and done or EMPTY) do
			entries[#entries + 1] = e
		end
	end
	if hidden > 0 then
		entries[#entries + 1] = { more = true, key = place.id .. ":more", n = hidden }
	end
	return entries, chains
end

-- The zone page: the map and the line under it (the chains' cards are in the briefing on the right).
function ZonePage.Draw(place)
	ZonePage.DrawMap(place)
	return ZonePage.DrawSummary(place)
end

-- A chain's card lit by a pin hovered, dim beside it, gold when it has the quest picked.
function ZonePage.PaintCard(b)
	local e = b.entry
	if not (e and e.group) then
		return
	end
	local lit = view.zp.lit
	local mine = state.picked ~= nil and e.group.index[state.picked] ~= nil
	if lit and lit[e.key] then
		Edges(b, 1, 0.82, 0)
		b.Glow:Show()
		b:SetAlpha(1)
	elseif lit then
		Edges(b, 0.25, 0.25, 0.25)
		b.Glow:Hide()
		b:SetAlpha(Z.DIM)
	else
		if mine then
			Edges(b, 1, 0.82, 0)
		else
			Edges(b, 0.3, 0.3, 0.3)
		end
		b.Glow:SetShown(mine)
		b:SetAlpha(1)
	end
end

-- Pins hovered: their chains' cards lit in the briefing (set: chain keys; nil: none); none of them in
-- sight: the briefing scrolls to the first.
function ZonePage.LightCards(set)
	local zp = view.zp
	zp.lit = set and next(set) and set or nil
	local first, seen
	for _, card in ipairs(view.b.cards) do
		if card:IsShown() and card.entry then
			ZonePage.PaintCard(card)
			if zp.lit and zp.lit[card.entry.key] then
				first = first or card
				seen = seen or Brief.InSight(card)
			end
		end
	end
	if first and not seen and view.b.Scroll:IsShown() then
		Brief.ScrollTo(first)
	end
end

-- A pin hovered (the mouse, or the controller's cursor): its chains lit, on the map and in the briefing.
function ZonePage.HoverPin(marker)
	Map.Light(view.zp.map, marker and next(marker.chains) and marker.chains or nil)
	ZonePage.LightCards(marker and marker.chains or nil)
end

-- A chain's card's tooltip: how far along, what's next, its levels, what the next step opens, its
-- steps elsewhere, friends; it lights its pins and thread on the map. The line under the cards: what
-- a click does.
local function ChainCardEnter(self)
	local e = self.entry
	if not e then
		return
	elseif e.more then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L["All levels"], 1, 0.82, 0)
		GameTooltip:AddLine(L["Also the quests far below or above your level. The search and an opened chain always show every level."], 1, 1, 1, true)
		GameTooltip:Show()
		return
	elseif not e.group then
		return
	end
	view.zp.hot = e.key
	Map.Light(view.zp.map, e.key)
	local info = e.info
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(Chains.Name(e.group), 1, 0.82, 0)
	if info.total > 0 then
		GameTooltip:AddLine(L["%d of %d steps done"]:format(info.done, info.total), 1, 1, 1)
	end
	local nextText = Chains.NextText(e.group, info)
	if nextText ~= "" then
		GameTooltip:AddLine(nextText, 0.9, 0.9, 0.9, true)
	end
	local span = LevelSpan(info.low, info.high)
	if span then
		GameTooltip:AddLine(span, 0.8, 0.8, 0.8)
	end
	if info.opens > 0 then
		GameTooltip:AddLine(L["Doing it opens %d more of the chain"]:format(info.opens), 0.8, 0.8, 0.8, true)
	end
	if info.elsewhere > 0 then
		GameTooltip:AddLine(L["%d steps elsewhere"]:format(info.elsewhere), 0.8, 0.8, 0.8)
	end
	for i, f in ipairs(Chains.Friends(e.group, info)) do
		if i > 6 then
			break
		end
		GameTooltip:AddLine(LT.Window.ClassColorCode(f.classFile) .. (f.name or "?") .. "|r  " .. L["%d of %d"]:format(f.done, info.total), 1, 1, 1)
	end
	GameTooltip:AddLine(L["Click: open the chain"], 0.5, 0.75, 1)
	GameTooltip:Show()
end

local function ChainCardLeave(self)
	local zp = view.zp
	if self.entry and zp.hot == self.entry.key then
		zp.hot = nil
		Map.Light(zp.map, nil)
	end
	Untip(self)
end

-- A chain's card: two lines (its colour, name, "3/7" and a bar; what's next and who gives it). The
-- same row also is the "Completed (N)" fold and the line saying what the level filter left out.
function ZonePage.NewCard(parent, width)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, Z.CARD_H)
	b.Bg = b:CreateTexture(nil, "BACKGROUND")
	b.Bg:SetAllPoints()
	b.Bg:SetColorTexture(0.07, 0.07, 0.07, 0.92)
	b.Glow = b:CreateTexture(nil, "BACKGROUND", nil, -1)
	b.Glow:SetPoint("TOPLEFT", -3, 3)
	b.Glow:SetPoint("BOTTOMRIGHT", 3, -3)
	b.Glow:SetColorTexture(1, 0.82, 0, 0.3)
	b.Glow:Hide()
	NewEdges(b)
	b.Dot = b:CreateTexture(nil, "ARTWORK")
	b.Dot:SetTexture(T.circle)
	b.Dot:SetSize(10, 10)
	b.Dot:SetPoint("TOPLEFT", 12, -10)
	b.Title = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	b.Title:SetPoint("TOPLEFT", 28, -8)
	b.Title:SetPoint("RIGHT", -(Z.BAR + 20), 0)
	b.Title:SetJustifyH("LEFT")
	b.Title:SetWordWrap(false)
	b.Count = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.Count:SetPoint("TOPRIGHT", -10, -8)
	b.Count:SetJustifyH("RIGHT")
	b.Check = b:CreateTexture(nil, "OVERLAY")
	b.Check:SetSize(14, 14)
	b.Check:SetPoint("RIGHT", b.Count, "LEFT", -3, 0)
	Art(b.Check, "common-icon-checkmark", T.check)
	b.BarBack = b:CreateTexture(nil, "ARTWORK")
	b.BarBack:SetPoint("TOPRIGHT", -10, -24)
	b.BarBack:SetSize(Z.BAR, 4)
	b.BarBack:SetColorTexture(0, 0, 0, 0.7)
	b.Bar = b:CreateTexture(nil, "ARTWORK", nil, 1)
	b.Bar:SetPoint("TOPLEFT", b.BarBack, "TOPLEFT")
	b.Bar:SetHeight(4)
	b.Next = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.Next:SetPoint("TOPLEFT", 28, -28)
	b.Next:SetPoint("RIGHT", -(Z.BAR + 20), 0)
	b.Next:SetJustifyH("LEFT")
	b.Next:SetWordWrap(false)
	b.Parts = { b.Dot, b.Title, b.Count, b.BarBack, b.Next }
	b.Dots = {}
	for i = 1, SHOWN.dots do
		local dot = b:CreateTexture(nil, "ARTWORK")
		dot:SetTexture(T.circle)
		dot:SetSize(8, 8)
		dot:SetPoint("BOTTOMRIGHT", -10 - (i - 1) * 10, 10)
		dot:Hide()
		b.Dots[i] = dot
	end
	-- The fold's and the level filter's line.
	b.Toggle = b:CreateTexture(nil, "ARTWORK")
	b.Toggle:SetSize(14, 14)
	b.Toggle:SetPoint("TOPLEFT", 8, -8)
	b.Line = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	b.Line:SetPoint("TOPLEFT", 28, -8)
	b.Line:SetPoint("RIGHT", -10, 0)
	b.Line:SetJustifyH("LEFT")
	b.Line:SetWordWrap(false)
	b:SetHighlightTexture(T.highlight, "ADD")
	b:SetScript("OnEnter", ChainCardEnter)
	b:SetScript("OnLeave", ChainCardLeave)
	b:SetScript("OnClick", function(self)
		local e = self.entry
		if not e then
			return
		end
		Untip(self)
		if e.group then
			ZonePage.OpenChain(e.key)
		else
			ZonePage.Toggle(e)
		end
	end)
	return b
end

-- A chain's card: its colour (its thread's on the map), its name, "3/7" (a check when done) and a
-- bar; what's next and who gives it, in grey; a dot per friend who's done some of it. Or the fold of
-- the done chains, or how many the level filter left out.
function ZonePage.FillCard(b, e)
	local special = e.group == nil
	for _, part in ipairs(b.Parts) do
		part:SetShown(not special)
	end
	b.Line:SetShown(special)
	b.Toggle:SetShown(e.fold == true)
	if special then
		b.Bg:SetShown(e.fold == true)
		Edges(b, 0.3, 0.3, 0.3, e.fold and 1 or 0)
		b.Glow:Hide()
		b.Check:Hide()
		b.Bar:Hide()
		for _, dot in ipairs(b.Dots) do
			dot:Hide()
		end
		b:SetAlpha(1)
		if e.fold then
			b.Toggle:SetTexture(e.closed and T.plus or T.minus)
			b.Line:SetText(HEX.done .. L["Completed (%d)"]:format(e.n) .. "|r")
		else
			b.Line:SetText(GREY .. L["%d more outside your levels"]:format(e.n) .. SEP .. "|r" .. GOLD .. L["Show all levels"] .. "|r")
		end
		return
	end
	local group, info = e.group, e.info
	local color = Chains.Color(group)
	local all = info.total > 0 and info.done == info.total
	b.Bg:Show()
	b.Dot:SetVertexColor(color[1], color[2], color[3], 1)
	b.Title:SetText(Chains.Name(group))
	if all then
		b.Title:SetTextColor(0.65, 0.65, 0.65)
	else
		b.Title:SetTextColor(1, 0.82, 0)
	end
	b.Count:SetText(info.total > 0 and (info.done .. "/" .. info.total) or "")
	b.Check:SetShown(all)
	local fill = info.total > 0 and info.done / info.total or 0
	b.Bar:SetWidth(math.max(1, Z.BAR * fill))
	b.Bar:SetShown(fill > 0)
	local bc = all and TONE.done or TONE.available
	b.Bar:SetColorTexture(bc[1], bc[2], bc[3], 1)
	b.Next:SetText(GREY .. (Chains.NextText(group, info)) .. "|r")
	local n = 0
	for _, f in ipairs(Chains.Friends(group, info)) do
		if f.done > 0 and n < #b.Dots then
			n = n + 1
			local fc = RAID_CLASS_COLORS and f.classFile and RAID_CLASS_COLORS[f.classFile]
			b.Dots[n]:SetVertexColor(fc and fc.r or 0.5, fc and fc.g or 0.75, fc and fc.b or 1, 1)
			b.Dots[n]:Show()
		end
	end
	for i = n + 1, #b.Dots do
		b.Dots[i]:Hide()
	end
	ZonePage.PaintCard(b)
end

-- A chain's card clicked: its page, its next step in sight and pulsing once.
function ZonePage.OpenChain(key)
	local place = CurrentPlace()
	local group = place and Structure(place).byKey[key]
	if not group then
		return
	end
	state.chain, state.path = key, nil
	local _, nextId = Chains.NextText(group, Chains.Info(group, place))
	state.pulse = nextId
	Graph.Open(nextId)
end

-- A quest's state on the map has changed when one in my log got ready to turn in (QUEST_LOG_UPDATE):
-- the zone's quests in my log and whether each is ready.
function ZonePage.ReadyKey(place)
	local parts = {}
	for _, id in ipairs(place and Structure(place).ids or EMPTY) do
		if StatusOf(id) == "active" then
			parts[#parts + 1] = id .. (IsReady(id) and "+" or "-")
		end
	end
	return table.concat(parts, ",")
end

---------------------------------------------------------------------------
-- The quest list (tab "overview"): the place's quests in groups
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

-- The groups, within my levels unless all are asked for: in progress, available now, coming up,
-- blocked, completed (folded; with the skipped ones), not for you (with its filter); then a line
-- saying how many the level filter left out.
function Overview.Entries(place)
	local by, hidden = {}, 0
	for _, id in ipairs(Structure(place).ids) do
		local status = StatusOf(id)
		local bucket = Rule.Skipped(id, status) and "done" or status
		if not Visible(id, status) then
			bucket = nil
		elseif not Rule.InLevels(id, status) then
			bucket, hidden = nil, hidden + 1
		end
		if bucket then
			by[bucket] = by[bucket] or {}
			table.insert(by[bucket], id)
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
	if hidden > 0 then
		entries[#entries + 1] = { more = true, key = place.id .. ":more", n = hidden }
	end
	return entries
end

-- What the quest list's row says at its right: the giver; why it can't be taken yet ("Needs ...");
-- "Skipped" among the completed ones; why it isn't for me.
local function OverviewRight(e, q, status)
	if e.bucket == "locked" or e.bucket == "level" or e.bucket == "other" or status == "other" then
		return Rule.Reason(e.quest, status)
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
	row.Name:SetText(Rule.Far(e) and (GREY .. e.name .. "|r") or e.name) -- (far from my level: dimmed)
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
-- Views other files add (Q.RegisterBrowserView): built the first time they're shown
---------------------------------------------------------------------------

local function Report(err)
	local handler = geterrorhandler and geterrorhandler()
	if handler then
		handler(err)
	end
end

-- A view's function, its errors reported (the error window) instead of breaking the big window.
function Views.Call(fn, self)
	if type(fn) == "function" then
		local ok, err = pcall(fn, self)
		if not ok then
			Report(err)
		end
	end
end

-- Its holder (the area under the tab bar, the zones and the details beside it) and what build(holder)
-- returns: { frame, Refresh, OnShow, OnHide } (a frame without points fills the holder).
function Views.Build(v)
	local holder = CreateFrame("Frame", nil, view.root)
	holder:SetPoint("TOPLEFT", view.viewX, -view.viewY)
	holder:SetSize(view.viewW, view.viewH)
	holder:Hide()
	v.holder = holder
	local ok, built = pcall(v.build, holder)
	if not ok then
		Report(built)
	end
	if type(built) ~= "table" then
		built = {}
		if not ok then
			local fs = holder:CreateFontString(nil, "OVERLAY", "GameFontDisable")
			fs:SetPoint("TOPLEFT", 12, -14)
			fs:SetText(L["This view couldn't be built."])
		end
	end
	if type(built.frame) ~= "table" then
		built.frame = holder
	elseif built.frame ~= holder and built.frame.GetNumPoints and built.frame:GetNumPoints() == 0 then
		built.frame:SetAllPoints(holder)
	end
	v.built = built
	state.viewsBuilt = (state.viewsBuilt or 0) + 1
end

-- A registered view shown (nil: none); the one shown before hidden (OnHide). Each time: Refresh.
function Views.Show(v)
	local current = registry.current
	if current and current ~= v then
		registry.current = nil
		Views.Call(current.built.OnHide, current.built)
		current.holder:Hide()
	end
	if not v then
		return
	end
	if not v.built then
		Views.Build(v)
	end
	if registry.current ~= v then
		registry.current = v
		v.holder:Show()
		if v.built.frame.Show then
			v.built.frame:Show()
		end
		Views.Call(v.built.OnShow, v.built)
	end
	Views.Call(v.built.Refresh, v.built)
end

---------------------------------------------------------------------------
-- The middle: the tab bar, the head over the page, the pages
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

local function Mode()
	if Searching() then
		return "results"
	end
	return TabKnown(state.tab) and state.tab or "zone"
end

-- The zone page, the quest list (its key "overview", as before), then each view registered.
function Tabs.List()
	local list = { { key = "zone", label = L["Zone"] }, { key = "overview", label = L["Quest list"] } }
	for _, v in ipairs(registry.order) do
		list[#list + 1] = { key = v.key, label = v.label }
	end
	return list
end

function Tabs.Paint()
	local mode = Mode()
	for key, tab in pairs(view.tabs) do
		local on = key == mode
		tab.Line:SetShown(on)
		tab.Back:SetColorTexture(1, 0.82, 0, on and 0.14 or 0.04)
		tab.Text:SetTextColor(on and 1 or 0.75, on and 0.82 or 0.75, on and 0 or 0.75)
	end
end

function Tabs.New(parent, key)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(TABS_H - 4)
	b.key = key
	b.Back = b:CreateTexture(nil, "BACKGROUND")
	b.Back:SetAllPoints()
	b.Line = b:CreateTexture(nil, "ARTWORK")
	b.Line:SetPoint("BOTTOMLEFT")
	b.Line:SetPoint("BOTTOMRIGHT")
	b.Line:SetHeight(2)
	b.Line:SetColorTexture(1, 0.82, 0, 1)
	b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	b.Text:SetPoint("CENTER", 0, 1)
	b:SetHighlightTexture(T.highlight, "ADD")
	b:SetScript("OnClick", function(self)
		Tabs.Set(self.key)
	end)
	return b
end

-- The tab bar laid again (a view registered after the window was built gets its tab).
function Tabs.Layout()
	if not view then
		return
	end
	local x, seen = 0, {}
	for _, t in ipairs(Tabs.List()) do
		local b = view.tabs[t.key]
		if not b then
			b = Tabs.New(view.tabBar, t.key)
			view.tabs[t.key] = b
		end
		b.Text:SetText(t.label)
		b:SetWidth(math.max(84, b.Text:GetStringWidth() + 28))
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", x, 0)
		b:Show()
		x = x + b:GetWidth() + 4
		seen[t.key] = true
	end
	for key, b in pairs(view.tabs) do
		if not seen[key] then
			b:Hide()
		end
	end
	-- The Zone tab's switch right after the tabs: always at that spot.
	local sw = view.switch
	if sw then
		sw.x = x + 12
		sw:ClearAllPoints()
		sw:SetPoint("TOPLEFT", sw.x, 0)
	end
	Tabs.Paint()
end

-- The chain the switch offers: the one opened; else the picked quest's (a chain of more than one
-- quest); nothing picked, the one left last for the map. nil: none applies.
function Tabs.SwitchChain(place)
	local tree = Structure(place)
	if state.chain then
		return tree.byKey[state.chain]
	end
	if state.picked then
		local group = tree.groupOf[state.picked]
		return group and not group.single and Rule.Step(state.picked) and group or nil
	end
	return state.lastChain and tree.byKey[state.lastChain] or nil
end

-- One half of the switch: on (shown now: gold, a line under it), off (greyed: nothing to show).
function Tabs.PaintHalf(b, on, off)
	b.on, b.off = on, off
	b.Line:SetShown(on)
	b.Back:SetColorTexture(1, 0.82, 0, on and 0.2 or 0.05)
	if off then
		b.Text:SetTextColor(0.45, 0.45, 0.45)
	elseif on then
		b.Text:SetTextColor(1, 0.82, 0)
	else
		b.Text:SetTextColor(0.8, 0.8, 0.8)
	end
end

-- The switch on the Zone tab: "Map" (a dungeon: "Quests") | "Chain: <name> 3/7" (greyed when no chain
-- applies), the half shown now lit; the chain's half as wide as there's room for (its name cut short).
-- Drawn with the middle and when a quest is picked: what it reads is all kept (Structure, Chains.Info).
function Tabs.Switch()
	local sw = view.switch
	local place = CurrentPlace()
	local shown = place ~= nil and Mode() == "zone"
	sw:SetShown(shown)
	if not shown then
		sw.group = nil
		return
	end
	local group = Tabs.SwitchChain(place)
	local open = group ~= nil and state.chain == group.key
	sw.group = group
	sw.map.Text:SetText(place.kind == "zone" and L["Map"] or L["Quests"])
	local mapW = math.max(64, sw.map.Text:GetStringWidth() + 28)
	sw.map:SetWidth(mapW)
	local chain = sw.chain
	local count = ""
	if group then
		local info = Chains.Info(group, place)
		chain.Text:SetText(group.single and Chains.Name(group) or L["Chain: %s"]:format(Chains.Name(group)))
		count = info.total > 0 and (info.done .. "/" .. info.total) or ""
	else
		chain.Text:SetText(L["Chain"])
	end
	chain.Count:SetText(count)
	local countW = count ~= "" and chain.Count:GetStringWidth() + 8 or 0
	local room = view.tabBar:GetWidth() - (sw.x or 0) - mapW - (view.Back:IsShown() and view.Back:GetWidth() + 8 or 0)
	local w = math.floor(math.max(72, math.min(chain.Text:GetStringWidth() + countW + 28, room)))
	chain:SetWidth(w)
	chain.Text:SetWidth(w - countW - 20)
	sw:SetWidth(mapW + w)
	Tabs.PaintHalf(sw.map, not open, false)
	Tabs.PaintHalf(chain, open, group == nil)
end

-- A half's tooltip: what it shows, what a click does; the chain's greyed half says why.
function Tabs.HalfEnter(self)
	local sw = view.switch
	local place = CurrentPlace()
	if not place then
		return
	end
	if not self.off then
		self.Hover:Show()
	end
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
	if self.key == "map" then
		GameTooltip:SetText(place.name, 1, 0.82, 0)
		GameTooltip:AddLine(self.on and L["Shown now"] or (place.kind == "zone" and L["Click: back to the map"] or L["Click: back to the quest list"]), 0.5, 0.75, 1)
	elseif sw.group then
		local info = Chains.Info(sw.group, place)
		GameTooltip:SetText(Chains.Name(sw.group), 1, 0.82, 0)
		if info.total > 0 then
			GameTooltip:AddLine(L["%d of %d steps done"]:format(info.done, info.total), 1, 1, 1)
		end
		GameTooltip:AddLine(self.on and L["Shown now"] or L["Click: open the chain"], 0.5, 0.75, 1)
	else
		GameTooltip:SetText(L["Chain"], 0.6, 0.6, 0.6)
		GameTooltip:AddLine(state.picked and Quest(state.picked) and L["%s is in no quest chain."]:format(Title(state.picked))
			or L["Pick a quest of a chain (on the map or on the right): its chain opens here."], 1, 1, 1, true)
	end
	GameTooltip:Show()
end

function Tabs.HalfLeave(self)
	self.Hover:Hide()
	Untip(self)
end

-- A click: the map (from a chain: the quest picked stays), or the chain offered; the half shown now
-- and a greyed one do nothing.
function Tabs.HalfClick(self)
	local sw = view.switch
	if self.on or self.off then
		return
	end
	Untip(self)
	self.Hover:Hide()
	if self.key == "map" then
		Tabs.BackToZone()
	elseif sw.group then
		Side.OpenChain(sw.group.key)
	end
end

-- The head over a page: the chain's colour, the title, a line under it, how far along.
function Head.Set(color, title, sub, countText, done, total)
	local h = view.head
	local x = 0
	h.Dot:SetShown(color ~= nil)
	if color then
		h.Dot:ClearAllPoints()
		h.Dot:SetPoint("TOPLEFT", x, -7)
		h.Dot:SetVertexColor(color[1], color[2], color[3], 1)
		x = x + 16
	end
	h.Title:ClearAllPoints()
	h.Title:SetPoint("TOPLEFT", x, -4)
	h.Title:SetPoint("RIGHT", h, "RIGHT", -360, 0)
	h.Title:SetText(title or "")
	h.Sub:SetText(sub or "")
	local bar = total and total > 0
	h.Count:SetText(bar and countText or "")
	h.BarBack:SetShown(bar == true)
	local fill = bar and done / total or 0
	h.Bar:SetShown(fill > 0)
	h.Bar:SetWidth(math.max(1, 150 * fill))
	local c = fill >= 1 and TONE.done or TONE.available
	h.Bar:SetColorTexture(c[1], c[2], c[3], 1)
end

-- The way back to a locked quest picked in a chain (Q.Missing, across zones): its quests numbered,
-- the zones of those not shown here.
function Path.Update()
	state.path = nil
	local id = state.picked
	local place = CurrentPlace()
	local group = id and state.chain and place and Structure(place).byKey[state.chain]
	if not (group and group.index[id] and Mode() == "zone") or StatusOf(id) ~= "locked" or not Q.Missing then
		return
	end
	local miss = Q.Missing(id) or EMPTY
	if not miss[1] then
		return
	end
	local path = { target = id, on = { [id] = 0 }, order = {}, zones = {}, n = 0, elsewhere = 0 }
	for _, m in ipairs(miss) do
		if m.id and not path.order[m.id] then
			path.n = path.n + 1
			path.on[m.id], path.order[m.id] = path.n, path.n
			local q = Quest(m.id)
			local zone = q and ZoneOf(q)
			if zone and not Structure(place).member[m.id] then -- (a quest given here isn't elsewhere)
				path.zones[zone] = (path.zones[zone] or 0) + 1
				path.elsewhere = path.elsewhere + 1
			end
		end
	end
	state.path = path
end

-- A chain's page: its head (back to the zone, how far along, what's next or what a locked quest
-- needs first) and its cards.
local function DrawChain(place, group, keep, focus)
	Path.Update()
	local info = Chains.Info(group, place)
	local sub = (Chains.NextText(group, info))
	local path = state.path
	if path and path.elsewhere > 0 then
		sub = HEX.level .. L["To take it, do %d quests first, %d of them in other zones"]:format(path.n, path.elsewhere) .. "|r"
	elseif path then
		sub = HEX.level .. L["To take it, do %d quests first"]:format(path.n) .. "|r"
	end
	Head.Set(Chains.Color(group), Chains.Name(group), sub, L["%d of %d steps done"]:format(info.done, info.total), info.done, info.total)
	Graph.Draw(place, group, keep, focus)
	view.ZoomText:SetText(("%d%%"):format(math.floor(view.g.zoom * 100 + 0.5)))
	local lay = view.g.layout
	if not (lay and lay.cards[1]) then
		return lay and lay.hidden > 0 and L["Nothing to show with these filters."] or L["No quests known here yet."]
	end
end

local function HeadZone(place, extra)
	local done, total = CountOf(place)
	local parts = { LevelSpan(place.minLevel, place.maxLevel) }
	parts[#parts + 1] = extra
	Head.Set(nil, place.name, GREY .. table.concat(parts, SEP) .. "|r", L["%d of %d done"]:format(done, total), done, total)
end

-- keep: the page stays where it's scrolled; focus: a quest to bring into sight; noSide: the right
-- pane is drawn by the caller (else it's drawn too).
local function DrawMiddle(keep, focus, noSide)
	state.draws = state.draws + 1
	local mode = Mode()
	local place = CurrentPlace()
	local v = registry.byKey[mode]
	local group = mode == "zone" and state.chain and place and Structure(place).byKey[state.chain] or nil
	if not group then
		state.chain = nil
	end
	-- The Zone tab: the zone's map, a chain opened, or for a dungeon (no map) its quest list.
	local onMap = mode == "zone" and group == nil and place ~= nil and place.kind == "zone"
	local dungeon = mode == "zone" and group == nil and place ~= nil and place.kind == "dungeon"
	view.zp:SetShown(onMap)
	view.g.frame:SetShown(group ~= nil)
	view.list.scroll:SetShown(mode == "results" or mode == "overview" or (mode == "zone" and group == nil and not onMap))
	view.Back:SetShown(state.query ~= "" and state.drilled)
	view.head:SetShown(v == nil and not onMap)
	view.Legend:SetText(dungeon and L["Dungeon quests are given in many places: each quest's details show where."]
		or L["dashed: lead-in · one of: any one is enough · orange: the way to a locked quest"])
	view.Legend:SetShown((group ~= nil and not group.single) or dungeon) -- (a chain's lines; the statuses say their reason themselves)
	view.Zoom:SetShown(group ~= nil)
	Views.Show(v)
	Tabs.Paint()
	Tabs.Switch()
	local message
	if v then
		message = nil
	elseif mode == "results" then
		Head.Set(nil, L["Search results"], state.results and GREY .. L["%d quests"]:format(#state.results) .. "|r" or "")
		if #state.query < 2 and not tonumber(state.query) then
			view.list:SetEntries({}, 0)
			message = L["Type at least two letters."]
		else
			view.list:SetEntries(SearchEntries(), keep and true or 0)
			message = not state.results[1] and L["Nothing found"] or nil
		end
	elseif group then
		message = DrawChain(place, group, keep, focus)
	elseif onMap then
		ZonePage.Draw(place)
	else
		if place then
			HeadZone(place)
		else
			Head.Set(nil, "", "")
		end
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
	end
	view.Message:SetText(message or "")
	view.Message:SetShown(message ~= nil)
	if not noSide then
		Side.Draw(not keep)
	end
end

function Graph.Open(focus)
	DrawMiddle(false, focus)
end

local function FillListRow(row, e)
	local header = e.header == true
	row.Toggle:SetShown(header and not e.search)
	row.Band:SetShown(header)
	row.Icon:SetShown(not header and not e.more)
	if header or e.more then
		Make.FillBadge(row.Badge, nil)
	end
	if e.more then -- (what the level filter left out; a click shows all levels)
		row.Picked:Hide()
		row.Name:SetText(GREY .. L["%d more outside your levels"]:format(e.n) .. SEP .. "|r" .. GOLD .. L["Show all levels"] .. "|r")
		row.Right:SetText("")
		row.Name:ClearAllPoints()
		row.Name:SetPoint("LEFT", 24, 0)
		row.Name:SetPoint("RIGHT", -4, 0)
		return
	elseif header then
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
		right = q and OverviewRight(e, q, status)
	end
	row.Right:SetText(right and (GREY .. right .. "|r") or "")
	row.Picked:SetShown(id == state.picked)
	-- Its chain's badge ("2/4": a click opens the chain), left of the right column.
	local badgeW = Make.FillBadge(row.Badge, id)
	row.Badge:ClearAllPoints()
	row.Badge:SetPoint("RIGHT", right and -168 or -4, 0)
	row.Name:ClearAllPoints()
	row.Name:SetPoint("LEFT", 24, 0)
	row.Name:SetPoint("RIGHT", (right and -170 or -4) - badgeW, 0)
end

---------------------------------------------------------------------------
-- The right, nothing picked: the briefing of what the middle shows (a zone's or dungeon's: how far
-- along, what to turn in, what's in progress there, its chains' cards; an opened chain's: its steps)
---------------------------------------------------------------------------

-- My quests in the log (the engine's statuses for the place's, the quest log for the rest).
function Brief.Log()
	local ids = {}
	local n = C_QuestLog and LT.Value(C_QuestLog.GetNumQuestLogEntries) or 0
	for i = 1, (type(n) == "number" and n or 0) do
		local info = LT.Value(C_QuestLog.GetInfo, i)
		local id = type(info) == "table" and not info.isHeader and not info.isHidden and info.questID
		if type(id) == "number" and id > 0 then
			ids[#ids + 1] = id
		end
	end
	return ids
end

-- Whether a quest has something on a map: its turn-in, or an objective's area.
function Brief.OnMap(q, map)
	if not (q and map) then
		return false
	end
	if FirstOn(q.ends, map) then
		return true
	end
	for _, o in ipairs(Task.List(q.id)) do
		for _, s in ipairs(type(o.sources) == "table" and o.sources or EMPTY) do
			if FirstOn({ s }, map) then
				return true
			end
		end
	end
	return false
end

-- My quests here (the place's in my log, and those turned in or done on its map): ready to turn in,
-- and the rest; the lowest level first.
function Brief.LogQuests(place)
	local member, seen, ready, going = Structure(place).member, {}, {}, {}
	local function Add(id)
		if seen[id] or StatusOf(id) ~= "active" then
			return
		end
		seen[id] = true
		local list = IsReady(id) and ready or going
		list[#list + 1] = id
	end
	for _, id in ipairs(Structure(place).ids) do
		if member[id] then
			Add(id)
		end
	end
	for _, id in ipairs(Brief.Log()) do
		if not seen[id] and place.kind == "zone" and Brief.OnMap(Quest(id), place.map) then
			Add(id)
		end
	end
	local function ByLevel(a, b)
		if LevelOf(a) ~= LevelOf(b) then
			return LevelOf(a) < LevelOf(b)
		end
		return a < b
	end
	table.sort(ready, ByLevel)
	table.sort(going, ByLevel)
	return ready, going
end

-- A row of the briefing: the quest's icon, "[12] Title", a grey line under it (or at its right: one line).
function Brief.NewRow(parent, width)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, 34)
	b:SetHighlightTexture(T.highlight, "ADD")
	b.Picked = b:CreateTexture(nil, "BACKGROUND")
	b.Picked:SetAllPoints()
	b.Picked:SetColorTexture(1, 0.82, 0, 0.18)
	b.Picked:Hide()
	b.Icon = b:CreateTexture(nil, "ARTWORK")
	b.Icon:SetSize(18, 18)
	b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	b.Text:SetJustifyH("LEFT")
	b.Text:SetWordWrap(false)
	b.Sub = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	b.Sub:SetJustifyH("LEFT")
	b.Sub:SetWordWrap(false)
	b.Right = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	b.Right:SetPoint("RIGHT", -4, 0)
	b.Right:SetJustifyH("RIGHT")
	b.Right:SetWordWrap(false)
	b.Badge = Make.NewBadge(b)
	b:SetScript("OnEnter", function(self)
		if self.quest then
			QuestTip(self, self.quest, Make.BadgeText(self.Badge))
		end
	end)
	b:SetScript("OnLeave", Untip)
	b:SetScript("OnClick", function(self)
		if self.quest then
			Untip(self)
			Side.Go(self.quest)
		end
	end)
	return b
end

-- text: "[12] Title" (and more); sub: the grey line under it; right: a grey word at its right (one line).
-- A quest of a chain has its badge ("2/4": a click opens the chain) at the right of its title line.
function Brief.FillRow(b, id, text, sub, right)
	local q = Quest(id)
	local status = StatusOf(id)
	b.quest = id
	if status == "active" and IsReady(id) then
		Art(b.Icon, "QuestTurnin", T.turnin)
		b.Icon:SetDesaturated(false)
		b.Icon:SetVertexColor(1, 1, 1)
	elseif status == "done" then
		Art(b.Icon, "common-icon-checkmark", T.check)
		b.Icon:SetDesaturated(false)
		b.Icon:SetVertexColor(1, 1, 1)
	else
		StartIcon(b.Icon, q, status)
	end
	b.Text:SetText(text or (LevelTag(q) .. Title(id)))
	b.Sub:SetText(sub or "")
	b.Sub:SetShown(sub ~= nil)
	b.Right:SetText(right or "")
	b.Right:SetShown(right ~= nil)
	b:SetHeight(sub and 34 or 20)
	b.Icon:ClearAllPoints()
	b.Icon:SetPoint(sub and "TOPLEFT" or "LEFT", 2, sub and -2 or 0)
	b.Text:ClearAllPoints()
	local badgeW = Make.FillBadge(b.Badge, id)
	b.Badge:ClearAllPoints()
	if sub then
		b.Badge:SetPoint("TOPRIGHT", -4, -2)
		b.Text:SetPoint("TOPLEFT", 26, -3)
		b.Text:SetPoint("RIGHT", -4 - badgeW, 0)
		b.Sub:ClearAllPoints()
		b.Sub:SetPoint("TOPLEFT", 26, -19)
		b.Sub:SetPoint("RIGHT", -4, 0)
	else
		local rightW = right and (b.Right:GetStringWidth() + 12) or 4
		b.Badge:SetPoint("RIGHT", -rightW, 0)
		b.Text:SetPoint("LEFT", 26, 0)
		b.Text:SetPoint("RIGHT", -rightW - badgeW, 0)
	end
	b.Picked:SetShown(id == state.picked)
end

-- The briefing's parts, from the top: each Put* lays one at y (body units) and gives the next y.
function Brief.Begin()
	local b = view.b
	b.nHeads, b.nRows, b.nCards = 0, 0, 0
	b.y = 0
end

function Brief.Text(fs, text, gap, x)
	local b = view.b
	if not text or text == "" then
		fs:Hide()
		return
	end
	fs:SetText(text)
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", x or 0, -b.y)
	fs:Show()
	b.y = b.y + fs:GetStringHeight() + (gap or 4)
end

function Brief.Head(text)
	local b = view.b
	b.nHeads = b.nHeads + 1
	local h = b.heads[b.nHeads]
	if not h then
		h = Make.NewHead(b.Body, b.w - 4)
		b.heads[b.nHeads] = h
	end
	h.Text:SetText(text)
	h:ClearAllPoints()
	h:SetPoint("TOPLEFT", 0, -b.y)
	h:Show()
	b.y = b.y + 22
end

function Brief.Row(id, text, sub, right)
	local b = view.b
	b.nRows = b.nRows + 1
	local row = b.rows[b.nRows]
	if not row then
		row = Brief.NewRow(b.Body, b.w - 4)
		b.rows[b.nRows] = row
	end
	Brief.FillRow(row, id, text, sub, right)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", 0, -b.y)
	row:Show()
	b.y = b.y + row:GetHeight() + 2
	return row
end

function Brief.Card(e)
	local b = view.b
	b.nCards = b.nCards + 1
	local card = b.cards[b.nCards]
	if not card then
		card = ZonePage.NewCard(b.Body, b.w - 4)
		b.cards[b.nCards] = card
	end
	card.entry, card.y = e, b.y
	card:ClearAllPoints()
	card:SetPoint("TOPLEFT", 0, -b.y)
	ZonePage.FillCard(card, e)
	card:Show()
	b.y = b.y + Z.CARD_H + Z.CARD_GAP
end

-- A bar across with "x of y" at its right.
function Brief.Bar(done, total, text)
	local b = view.b
	local bar = total and total > 0
	b.BarBack:SetShown(bar == true)
	b.Count:SetShown(bar == true)
	if not bar then
		b.Bar:Hide()
		return
	end
	b.Count:SetText(text)
	b.Count:ClearAllPoints()
	b.Count:SetPoint("TOPRIGHT", b.Body, "TOPRIGHT", -4, -(b.y - 3))
	b.BarBack:ClearAllPoints()
	b.BarBack:SetPoint("TOPLEFT", 0, -b.y)
	local w = b.w - 4 - b.Count:GetStringWidth() - 12
	b.BarBack:SetWidth(math.max(20, w))
	local fill = done / total
	b.Bar:SetShown(fill > 0)
	b.Bar:SetWidth(math.max(1, math.max(20, w) * fill))
	local c = fill >= 1 and TONE.done or TONE.available
	b.Bar:SetColorTexture(c[1], c[2], c[3], 1)
	b.y = b.y + 18
end

-- The rest of the pools hidden, the body as high as what's in it; top: from its top.
function Brief.End(top)
	local b = view.b
	for i = b.nHeads + 1, #b.heads do
		b.heads[i]:Hide()
	end
	for i = b.nRows + 1, #b.rows do
		b.rows[i].quest = nil
		b.rows[i]:Hide()
	end
	for i = b.nCards + 1, #b.cards do
		b.cards[i].entry = nil
		b.cards[i]:Hide()
	end
	b.Body:SetHeight(math.max(1, b.y))
	local most = math.max(0, b.y - b.height)
	local now = top and 0 or math.min(b.Scroll:GetVerticalScroll() or 0, most)
	b.Scroll:SetVerticalScroll(now)
end

function Brief.InSight(card)
	local b = view.b
	local top = b.Scroll:GetVerticalScroll() or 0
	return card.y >= top and card.y + Z.CARD_H <= top + b.height
end

function Brief.ScrollTo(card)
	local b = view.b
	b.Scroll:SetVerticalScroll(math.max(0, math.min(card.y - b.height / 2 + Z.CARD_H / 2, (b.Body:GetHeight() or 0) - b.height)))
end

-- A zone's (or dungeon's) briefing: its name, levels, how far along, what's for my level; what to
-- turn in now and what's in progress here (my quest log); then its chains' cards (within my levels),
-- the done ones folded, how many more outside my levels.
function Brief.Zone(place, top)
	local b = view.b
	Brief.Begin()
	b.Dot:Hide()
	Brief.Text(b.Title, place.name, 2)
	local parts = { LevelSpan(place.minLevel, place.maxLevel) }
	parts[#parts + 1] = place.kind == "zone" and ContinentName(place.continent) or L["Dungeon"]
	Brief.Text(b.Sub, GREY .. table.concat(parts, SEP) .. "|r", 8)
	local done, total = CountOf(place)
	Brief.Bar(done, total, L["%d of %d done"]:format(done, total))
	local mine, open = 0, 0
	for _, id in ipairs(Structure(place).ids) do
		if Rule.ForMyLevel(id, StatusOf(id)) then
			mine = mine + 1
			open = open + (StatusOf(id) == "available" and 1 or 0)
		end
	end
	local line = mine > 0 and (HEX.available .. L["%d for your level"]:format(mine) .. "|r" .. GREY .. SEP .. "|r" .. L["%d to pick up now"]:format(open))
		or (GREY .. L["Nothing for your level."] .. "|r")
	Brief.Text(b.Line, line, 10)
	local ready, going = Brief.LogQuests(place)
	if ready[1] then
		Brief.Head(L["Turn in now (%d)"]:format(#ready))
		for i, id in ipairs(ready) do
			if i > SHOWN.log then
				break
			end
			local q = Quest(id)
			local p, who = FirstOn(q and q.ends, place.map)
			who = who or (q and q.ends and q.ends[1])
			Brief.Row(id, nil, who and (L["Turn in at %s"]:format(who.name or "?") .. (p and "" or (SEP .. (ZoneOf(q) or "")))) or L["Ready to turn in"])
		end
	end
	if going[1] then
		Brief.Head(L["In progress here (%d)"]:format(#going))
		for i, id in ipairs(going) do
			if i > SHOWN.log then
				break
			end
			Brief.Row(id, nil, Task.FirstOpen(id) or L["In your quest log"])
		end
	end
	local entries = ZonePage.Entries(place)
	if entries[1] then
		Brief.Head(L["Quest chains"])
		for _, e in ipairs(entries) do
			Brief.Card(e)
		end
	end
	local message
	if not entries[1] then
		message = Structure(place).ids[1] and L["Nothing to show with these filters."] or L["No quests known here yet."]
	end
	Brief.Text(b.Empty, message, 8)
	Brief.End(top)
end

-- An opened chain's briefing: its colour and name, its levels and steps, how far along, what's
-- next; every step as a row (a tick when done, its badge "3/9", its status's reason or its giver at
-- the right; a click picks it); friends on it.
function Brief.Chain(place, group, top)
	local b = view.b
	Brief.Begin()
	local info = Chains.Info(group, place)
	local color = Chains.Color(group)
	b.Dot:ClearAllPoints()
	b.Dot:SetPoint("TOPLEFT", 0, -6)
	b.Dot:SetVertexColor(color[1], color[2], color[3], 1)
	b.Dot:SetShown(not group.single)
	Brief.Text(b.Title, Chains.Name(group), 2, group.single and 0 or 16)
	local parts = { LevelSpan(info.low, info.high), L["%d quests"]:format(info.total) }
	if info.elsewhere > 0 then
		parts[#parts + 1] = L["%d steps elsewhere"]:format(info.elsewhere)
	end
	Brief.Text(b.Sub, GREY .. table.concat(parts, SEP) .. "|r", 8)
	Brief.Bar(info.done, info.total, L["%d of %d steps done"]:format(info.done, info.total))
	Brief.Text(b.Line, (Chains.NextText(group, info)), 10)
	Brief.Head(group.single and L["Quests"] or L["Steps"])
	local n, shown = 0, 0
	for _, id in ipairs(group.chain) do
		local status = StatusOf(id)
		if Visible(id, status) then
			n = n + 1
			if shown < SHOWN.steps then
				shown = shown + 1
				local q = Quest(id)
				local right
				if status == "available" or status == "active" then
					local s = FirstStart(q)
					right = s and s.name or nil
				else
					right = Rule.Reason(id, status)
				end
				local c = TONE[status]
				-- (its step: the badge at its right, "3/9")
				Brief.Row(id, LevelTag(q) .. Hex(c[1], c[2], c[3]) .. Title(id) .. "|r", nil, right and (GREY .. right .. "|r") or nil)
			end
		end
	end
	Brief.Text(b.More, n > shown and (GREY .. L["... and %d more"]:format(n - shown) .. "|r") or nil, 8)
	local friends = {}
	for i, f in ipairs(Chains.Friends(group, info)) do
		if i > 6 then
			break
		end
		friends[#friends + 1] = LT.Window.ClassColorCode(f.classFile) .. (f.name or "?") .. "|r  " .. GREY .. L["%d of %d"]:format(f.done, info.total) .. "|r"
	end
	if friends[1] then
		Brief.Head(L["Friends"])
	end
	Brief.Text(b.Friends, friends[1] and table.concat(friends, "\n") or nil, 8)
	b.Empty:Hide()
	Brief.End(top)
end

-- The briefing of what the middle shows: an opened chain's, else the place's (the search, the quest
-- list and the views too: no empty pane).
function Brief.Draw(top)
	local b = view.b
	local place = CurrentPlace()
	local group = Mode() == "zone" and state.chain and place and Structure(place).byKey[state.chain] or nil
	b.More:Hide()
	b.Friends:Hide()
	if group then
		Brief.Chain(place, group, top)
	elseif place then
		Brief.Zone(place, top)
	else
		Brief.Begin()
		b.Dot:Hide()
		for _, fs in ipairs({ b.Title, b.Sub, b.Line, b.Empty }) do
			fs:Hide()
		end
		Brief.Bar(0, 0)
		Brief.End(true)
	end
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
			local name = _G[side[2] == "Alliance" and "FACTION_ALLIANCE" or "FACTION_HORDE"]
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

-- Requirements, only those not met: for a quest not for me the one that keeps me from it (race,
-- class, faction, a profession; without Q.WhyOther all of them), for a locked one the reputation or
-- profession rank it needs (Q.Needs); what taking it closes while it can still be taken.
function Details.Requirements(q, status)
	local lines = {}
	local why = status == "other" and Rule.Why(q.id) or nil
	local all = status == "other" and not Q.WhyOther
	if q.faction and (all or why == "faction") then
		local name = q.faction == "Alliance" and _G.FACTION_ALLIANCE or q.faction == "Horde" and _G.FACTION_HORDE or nil
		lines[#lines + 1] = L["Faction: %s"]:format(type(name) == "string" and name or q.faction)
	end
	if q.races and (all or why == "race") then
		lines[#lines + 1] = L["Races: %s"]:format(RaceNames(q.races))
	end
	if q.classes and (all or why == "class") then
		lines[#lines + 1] = L["Classes: %s"]:format(ClassNames(q.classes))
	end
	local need = status == "locked" and Rule.Needs(q.id) or nil
	if q.skill and q.skill.id and (all or why == "skill" or (need and need.kind == "skill")) then
		lines[#lines + 1] = L["Skill: %s %d"]:format(SkillName(q.skill.id), q.skill.value or 0)
	end
	if q.rep and q.rep.faction and (all or (need and need.kind == "rep")) then
		lines[#lines + 1] = L["Reputation: %s, %s"]:format(FactionName(q.rep.faction), Standing(q.rep.min or 0))
	end
	if q.excl and q.excl[1] and (status == "available" or status == "locked" or status == "level") then
		lines[#lines + 1] = L["Taking it closes: %s"]:format(Titles(q.excl))
	end
	return lines[1] and table.concat(lines, "\n") or nil
end

-- The status with its reason (a skipped one: what I took instead; one in my log that's done: ready
-- to turn in), its tags.
function Details.Summary(q, status)
	local line = HEX[status] .. Rule.Reason(q.id, status) .. "|r"
	if status == "active" and IsReady(q.id) then
		line = GOLD .. L["Ready to turn in"] .. "|r"
	end
	local skipped = Rule.SkippedFor(q.id)
	if skipped then
		line = line .. GREY .. SEP .. skipped .. "|r"
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
		line = line .. GREY .. SEP .. "|r|cff80c0ff" .. table.concat(tags, ", ") .. "|r"
	end
	return line
end

-- A giver's or ender's line ("Marshal Dughan · Elwynn Forest"), a drop's ("Drops from Young Wolf
-- (12%) · Elwynn Forest").
local function WhereText(o, drop)
	local p = o.points and o.points[1]
	local zone = p and MapName(p.map)
	local text
	if drop then
		text = (o.kind == "object" and L["In %s (%s%%)"] or L["Drops from %s (%s%%)"]):format(o.name or "?", Chance(o.chance))
	else
		text = StartWord(o)
	end
	return text .. (zone and (GREY .. SEP .. zone .. "|r") or "")
end

-- Where a quest starts or is turned in (which: "start" | "end"), one line (a button: it puts a map
-- pin there): the first giver (an item: its best drop under it) or ender and its zone; the others in
-- its tooltip (tip: its lines). nil: none known.
function Details.WhereLine(q, which)
	local list = q.starts
	if which == "end" then
		list = q.ends
	end
	local s = (list or EMPTY)[1]
	if not s then
		return nil
	end
	local line = { kind = which, tip = {}, name = s.name, point = s.points and s.points[1] }
	local best
	for _, d in ipairs(which == "start" and s.kind == "item" and s.drops or EMPTY) do
		if not best or (tonumber(d.chance) or 0) > (tonumber(best.chance) or 0) then
			best = d
		end
	end
	if best then
		line.kind, line.point, line.name = "drop", best.points and best.points[1], best.name
		line.text = StartWord(s) .. "\n" .. GREY .. WhereText(best, true) .. "|r"
	else
		line.text = WhereText(s)
	end
	local tip = line.tip
	local function Section(head, others, skip, drop)
		local n, total = 0, #(others or EMPTY) - (skip and 1 or 0)
		for _, o in ipairs(others or EMPTY) do
			if o ~= skip then
				if n == 0 and head then
					tip[#tip + 1] = GOLD .. head .. "|r"
				end
				n = n + 1
				if n > SHOWN.others then
					tip[#tip + 1] = GREY .. L["... and %d more"]:format(total - SHOWN.others) .. "|r"
					break
				end
				tip[#tip + 1] = WhereText(o, drop)
			end
		end
	end
	if best then
		Section(nil, s.drops, best, true)
	end
	Section(which == "end" and L["Turn in at"] or L["Starts at"], list, s)
	return line
end

-- The small map: for a quest in my log the map of its objectives (else its turn-in's); else its first
-- giver's (else a drop's, else the first ender's); every giver, ender and drop spot on it.
function Details.MapSpots(q, status)
	local map
	if status == "active" then
		for _, o in ipairs(Task.List(q.id)) do
			for _, s in ipairs(type(o.sources) == "table" and o.sources or EMPTY) do
				local p = s.points and s.points[1]
				map = map or (p and p.map)
			end
		end
		local p = q.ends and q.ends[1] and q.ends[1].points and q.ends[1].points[1]
		map = map or (p and p.map)
	end
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

-- Friends who shared progress on it: at most three names (class colour, their status), "+N" for the rest.
function Details.FriendsLine(id)
	local list = Q.Friends and Q.Friends(id) or EMPTY
	if not list[1] then
		return nil
	end
	local names = {}
	for i, f in ipairs(list) do
		if i > SHOWN.friends then
			names[#names] = names[#names] .. GREY .. "  +" .. (#list - SHOWN.friends) .. "|r"
			break
		end
		local status = TONE[f.status] and f.status or "other"
		names[#names + 1] = LT.Window.ClassColorCode(f.classFile) .. (f.name or "?") .. "|r " .. HEX[status] .. "(" .. Word(status) .. ")|r"
	end
	return table.concat(names, ", ")
end

-- A text in the details' column at y (x: from its left); the next y.
local function Put(fs, text, y, gap, x)
	if not text or text == "" then
		fs:Hide()
		return y
	end
	fs:SetText(text)
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", x or 0, -y)
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
	return y + 22
end

-- A link to a quest: its start's icon, "[12] Title" in its status's colour, its zone when it's another.
local function FillLink(b, id, text)
	local q = Quest(id)
	local status = StatusOf(id)
	b.quest = id
	StartIcon(b.Icon, q, status)
	local zone = q and ZoneOf(q)
	local here = CurrentPlace()
	local other = zone and here and zone ~= here.name
	local c = TONE[status]
	b.Text:SetText(text or (LevelTag(q) .. Hex(c[1], c[2], c[3]) .. Title(id) .. "|r" .. (other and (GREY .. SEP .. zone .. "|r") or "")))
end

-- "Needs first:" or "Leads to:" and a button per quest (at most max), "... and N more"; used: the
-- link buttons taken so far.
function Details.PutLinks(head, more, label, list, max, y, used)
	if not list[1] then
		head:Hide()
		more:Hide()
		return y, used
	end
	y = PutHead(head, label, y)
	local shown = 0
	for _, item in ipairs(list) do
		if shown >= max then
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

-- Its chain, as I can do it (Q.ChainFor; else the place's chain without what isn't for me): "Step 3
-- of 7 · <chain>", a bar, the steps around it (one before, this one, two after; more at the chain's
-- ends) as links, done ones ticked, this one marked; "Chain" at the heading's right opens the chain.
function Details.PutChain(q, y)
	local d = view.d
	local list, at
	if Q.ChainFor then
		list, at = Q.ChainFor(q.id)
	end
	local place = CurrentPlace()
	local group = place and Structure(place).groupOf[q.id]
	if not list and group and not group.single then
		list = {}
		for _, id in ipairs(group.chain) do
			if id == q.id or StatusOf(id) ~= "other" then
				list[#list + 1] = id
				at = id == q.id and #list or at
			end
		end
	end
	d.ChainBtn.key = group and not group.single and group.key or nil
	if not (list and at and #list >= 2) then
		d.ChainHead:Hide()
		d.ChainBtn:Hide()
		d.StepBack:Hide()
		d.StepBar:Hide()
		for _, fs in ipairs({ d.StepsBefore, d.StepsMore }) do
			fs:Hide()
		end
		for _, b in ipairs(d.steps) do
			b.quest = nil
			b:Hide()
		end
		return y
	end
	local _, _, name = StepOf(q.id)
	y = PutHead(d.ChainHead, L["Step %d of %d"]:format(at, #list) .. GREY .. SEP .. "|r" .. (name or Title(list[1])), y)
	d.ChainBtn:SetShown(d.ChainBtn.key ~= nil)
	local done = 0
	for _, id in ipairs(list) do
		done = done + (StatusOf(id) == "done" and 1 or 0)
	end
	d.StepBack:ClearAllPoints()
	d.StepBack:SetPoint("TOPLEFT", 0, -y)
	d.StepBack:Show()
	d.StepBar:SetWidth(math.max(1, (d.bodyW - 4) * done / #list))
	d.StepBar:SetShown(done > 0)
	local c = done == #list and TONE.done or TONE.available
	d.StepBar:SetColorTexture(c[1], c[2], c[3], 1)
	y = y + 10
	local from = math.max(1, at - 1)
	local to = math.min(#list, from + 3)
	from = math.max(1, to - 3)
	y = Put(d.StepsBefore, from > 1 and (GREY .. L["... %d before"]:format(from - 1) .. "|r") or nil, y, 2, 20)
	local n = 0
	for i = from, to do
		n = n + 1
		local id = list[i]
		local b = d.Step(n)
		local s = StatusOf(id)
		local c = TONE[s]
		local qq = Quest(id)
		local mark = i == at and (GOLD .. i .. ".|r ") or (GREY .. i .. ".|r ")
		FillLink(b, id, mark .. LevelTag(qq) .. (i == at and "|cffffffff" or Hex(c[1], c[2], c[3])) .. Title(id) .. "|r")
		if s == "done" then
			Art(b.Icon, "common-icon-checkmark", T.check)
			b.Icon:SetDesaturated(false)
			b.Icon:SetVertexColor(1, 1, 1)
		elseif i == at then
			b.Icon:SetTexture(T.here)
			b.Icon:SetTexCoord(0, 1, 0, 1)
			b.Icon:SetDesaturated(false)
			b.Icon:SetVertexColor(1, 0.82, 0)
		end
		b.Text:SetFontObject(i == at and "GameFontHighlight" or "GameFontHighlightSmall")
		b.Picked:SetShown(i == at)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 0, -y)
		b:Show()
		y = y + LINK_H
	end
	for i = n + 1, #d.steps do
		d.steps[i].quest = nil
		d.steps[i]:Hide()
	end
	y = Put(d.StepsMore, to < #list and (GREY .. L["... and %d more"]:format(#list - to) .. "|r") or nil, y, 2, 20)
	return y + 8
end

-- Which objective has an area on the map in sight (the zone page's, else the small one): its colour.
function Details.AreaColor(objective)
	local d = view.d
	local pick
	if view.zp:IsShown() then
		pick = view.zp.map.pick
	elseif d.mapWanted and d.small then
		pick = d.small.pick
	end
	if not (pick and objective and pick.quest == state.picked) then
		return nil
	end
	for _, a in ipairs(pick.areas) do
		if a.objective == objective then
			return pick.color
		end
	end
end

-- Its objectives (Q.Objectives): "Kill 10 x Kobold Vermin", "Collect 8 x Wolf Fang" and where it
-- drops; for a quest in my log the quest log's lines with my progress, done ones ticked. A dot in
-- its chain's colour when it has an area on the map: hovering the line lights it, a click sets the
-- map pin there.
function Details.PutObjectives(q, y)
	local d = view.d
	local list = Task.List(q.id)
	local progress = Task.Progress(q.id, list)
	local lines = {}
	if progress then
		for _, p in ipairs(progress) do
			local o = p.objective and list[p.objective]
			lines[#lines + 1] = { text = p.text ~= "" and p.text or (o and Task.Text(o)) or "?", done = p.done, objective = p.objective,
				from = o and Task.From(o) }
		end
	else
		for i, o in ipairs(list) do
			lines[#lines + 1] = { text = Task.Text(o), objective = i, from = Task.From(o) }
		end
	end
	y = PutHead(d.ObjHead, lines[1] and L["Objectives"] or nil, y)
	for i, line in ipairs(lines) do
		local b = d.Objective(i)
		b.line, b.quest = line, q.id
		if line.done then
			Art(b.Icon, "common-icon-checkmark", T.check)
			b.Icon:SetVertexColor(1, 1, 1)
		else
			b.Icon:SetTexture(T.bullet)
			b.Icon:SetTexCoord(0, 1, 0, 1)
			b.Icon:SetVertexColor(1, 0.82, 0)
		end
		b.Text:SetText((line.done and GREY or "") .. line.text .. (line.done and "|r" or "") .. (line.from and ("\n" .. GREY .. line.from .. "|r") or ""))
		local c = Details.AreaColor(line.objective)
		b.Dot:SetShown(c ~= nil)
		if c then
			b.Dot:SetVertexColor(c[1], c[2], c[3], 1)
		end
		local h = math.max(LINK_H, b.Text:GetStringHeight() + 4)
		b:SetHeight(h)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 0, -y)
		b:Show()
		y = y + h + 2
	end
	for i = #lines + 1, #d.objectives do
		d.objectives[i].line = nil
		d.objectives[i]:Hide()
	end
	return lines[1] and (y + 6) or y
end

-- Who gives it and takes it back: two lines (an item: its best drop under it), a click puts the map pin there.
function Details.PutWhere(q, y)
	local d = view.d
	local start, finish = Details.WhereLine(q, "start"), Details.WhereLine(q, "end")
	y = PutHead(d.WhereHead, (start or finish) and L["Quest giver and turn-in"] or nil, y)
	for i, line in ipairs({ start or false, finish or false }) do
		local b = d.places[i]
		if line then
			b.point, b.name, b.tip = line.point, line.name, line.tip
			b.Text:SetText(line.text)
			if line.kind == "drop" then
				local s = FirstStart(q)
				b.Icon:SetTexture(C_Item and LT.Value(C_Item.GetItemIconByID, s and s.id) or T.item)
				b.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				b.Icon:SetDesaturated(false)
				b.Icon:SetVertexColor(1, 1, 1, 1)
			else
				Art(b.Icon, i == 1 and "QuestNormal" or "QuestTurnin", i == 1 and T.available or T.turnin)
				b.Icon:SetDesaturated(i == 2 and not (StatusOf(q.id) == "active" and IsReady(q.id)))
				b.Icon:SetVertexColor(1, 1, 1, 1)
			end
			local h = math.max(LINK_H + 2, b.Text:GetStringHeight() + 4)
			b:SetHeight(h)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", 0, -y)
			b:Show()
			y = y + h + 2
		else
			b.point, b.tip = nil, nil
			b:Hide()
		end
	end
	return (start or finish) and (y + 6) or y
end

-- The small map, only when the zone page's map isn't in sight (it shows the same): giver, turn-in,
-- drops, and the quest's objective areas and its way on it.
function Details.PutMap(q, y)
	local d = view.d
	local m = d.map
	if not (d.mapWanted and d.small) then
		m.pick = nil
		m.frame:Hide()
		return y
	end
	m.frame:ClearAllPoints()
	m.frame:SetPoint("TOPLEFT", 0, -y)
	m.pick = d.small.pick
	Map.Show(m, d.small.map, d.small.spots)
	return y + m.height + 10
end

-- Money as the game writes it (its coins), else "1g 20s 5c".
function Details.Coins(copper)
	copper = math.floor((tonumber(copper) or 0) + 0.5)
	if GetCoinTextureString then
		return GetCoinTextureString(copper)
	end
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	return (g > 0 and g .. "g " or "") .. ((g > 0 or s > 0) and s .. "s " or "") .. c .. "c"
end

-- Item buttons in rows from y (36 px, the game's icon, the count, the quality's border); used: the
-- buttons taken so far.
function Details.PutItems(items, y, used)
	local d = view.d
	local per = math.max(1, math.floor((d.bodyW - 4 + 6) / 42))
	local n = 0
	for _, it in ipairs(items) do
		local id = type(it) == "table" and tonumber(it.id or it[1]) or tonumber(it)
		if id then
			used, n = used + 1, n + 1
			local b = d.Item(used)
			b.item = id
			b.Icon:SetTexture(C_Item and LT.Value(C_Item.GetItemIconByID, id) or T.question)
			local count = type(it) == "table" and tonumber(it.count or it[2]) or 1
			b.Count:SetText(count > 1 and tostring(count) or "")
			local quality = C_Item and LT.Value(C_Item.GetItemQualityByID, id)
			if quality == nil then
				Task.AskItem(id)
			end
			local r, g, bb
			if type(quality) == "number" and quality ~= 1 and C_Item.GetItemQualityColor then
				local ok, qr, qg, qb = pcall(C_Item.GetItemQualityColor, quality)
				if ok then
					r, g, bb = qr, qg, qb
				end
			end
			b.Border:SetShown(r ~= nil)
			if r then
				b.Border:SetVertexColor(r, g, bb, 1)
			end
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", ((n - 1) % per) * 42, -(y + math.floor((n - 1) / per) * 42))
			b:Show()
		end
	end
	return y + math.ceil(n / per) * 42 + 4, used
end

-- Its rewards (Q.Rewards): "Choose one of:" and the items to choose from, the items it gives, money and
-- experience; each item's tooltip the game's (GameTooltip:SetItemByID).
function Details.PutRewards(q, y)
	local d = view.d
	local r = Task.Rewards(q.id)
	y = PutHead(d.RewardHead, r and L["Rewards"] or nil, y)
	local used = 0
	local choice = r and type(r.choice) == "table" and r.choice or EMPTY
	local items = r and type(r.items) == "table" and r.items or EMPTY
	y = Put(d.ChoiceLabel, choice[1] and L["Choose one of:"] or nil, y, 4)
	if choice[1] then
		y, used = Details.PutItems(choice, y, used)
	end
	y = Put(d.GetLabel, items[1] and (choice[1] and L["You also get:"] or L["You get:"]) or nil, y, 4)
	if items[1] then
		y, used = Details.PutItems(items, y, used)
	end
	for i = used + 1, #d.items do
		d.items[i].item = nil
		d.items[i]:Hide()
	end
	local parts = {}
	if r and (tonumber(r.money) or 0) > 0 then
		parts[#parts + 1] = Details.Coins(r.money)
	end
	if r and (tonumber(r.xp) or 0) > 0 then
		parts[#parts + 1] = L["%d XP"]:format(r.xp)
	end
	y = Put(d.Money, parts[1] and table.concat(parts, GREY .. SEP .. "|r") or nil, y, 4)
	return r and (y + 6) or y
end

-- Where the map pin goes (the "Map pin" button): its turn-in when it's ready; in my log the first
-- objective not done yet that has an area (else the turn-in); else its giver (an item: its best drop).
function Details.PinTarget(q, status)
	if status == "active" and not IsReady(q.id) then
		local list = Task.List(q.id)
		local done = {}
		for _, p in ipairs(Task.Progress(q.id, list) or EMPTY) do
			if p.objective then
				done[p.objective] = p.done
			end
		end
		for i, o in ipairs(list) do
			for _, s in ipairs(not done[i] and type(o.sources) == "table" and o.sources or EMPTY) do
				local p = s.points and s.points[1]
				if p then
					return p, Task.Text(o)
				end
			end
		end
	end
	local line = Details.WhereLine(q, status == "active" and "end" or "start")
	if line and line.point then
		return line.point, line.name
	end
end

-- The way back, on top: to the briefing of what the middle shows (the zone's, the chain's).
function Details.PutBack()
	local d = view.d
	local place = CurrentPlace()
	local group = Mode() == "zone" and state.chain and place and Structure(place).byKey[state.chain] or nil
	d.Back.Text:SetText(group and Chains.Name(group) or place and place.name or "")
	d.Back:SetWidth(math.min(d.bodyW, d.Back.Text:GetStringWidth() + 28))
end

-- top: a new quest, shown from its top (else a refresh keeps the place). Its icon, title and status
-- with the reason, its chain and the steps around it, its objectives, who gives and takes it, the
-- small map, its rewards, requirements not met, the first quest it needs, what it leads to (three),
-- friends; at the bottom "Map pin" and "Companion".
local function FillDetails(top)
	local d = view.d
	local id = state.picked
	local q = Quest(id)
	d.mapWanted = not view.zp:IsShown()
	d.Body:SetShown(q ~= nil)
	d.Small:SetShown(q ~= nil and Q.ShowQuest ~= nil)
	d.Pin:SetShown(q ~= nil)
	if not q then
		for _, b in ipairs(d.links) do
			b.quest = nil
			b:Hide()
		end
		d.map.pick = nil
		d.map.frame:Hide()
		return
	end
	local status = StatusOf(id)
	d.small = nil
	if d.mapWanted then
		local map, spots = Details.MapSpots(q, status)
		local place = CurrentPlace()
		if map and spots then
			d.small = { map = map, spots = spots, pick = ZonePage.PickOn(map, id, place and Structure(place).groupOf[id]) }
		end
		if d.small and not (spots[1] or d.small.pick) then
			d.small = nil
		end
	end
	Details.PutBack()
	if status == "active" and IsReady(id) then
		Art(d.Icon, "QuestTurnin", T.turnin)
		d.Icon:SetDesaturated(false)
		d.Icon:SetVertexColor(1, 1, 1)
	else
		StartIcon(d.Icon, q, status)
	end
	local y = Put(d.Title, LevelTag(q) .. Title(id), 2, 2, 40)
	y = Put(d.Sub, Details.Summary(q, status), y, 10, 40)
	y = math.max(y, 42)
	y = Details.PutChain(q, y)
	y = Details.PutObjectives(q, y)
	y = Details.PutWhere(q, y)
	y = Details.PutMap(q, y)
	y = Details.PutRewards(q, y)
	local req = Details.Requirements(q, status)
	y = PutHead(d.ReqHead, req and L["Requirements"] or nil, y)
	y = Put(d.Req, req, y, 10)
	local used = 0
	y, used = Details.PutLinks(d.NeedsHead, d.NeedsMore, L["Needs first:"], Q.Missing and Q.Missing(id) or EMPTY, SHOWN.needs, y, used)
	y, used = Details.PutLinks(d.LeadsHead, d.LeadsMore, L["Leads to:"], Q.Opens and Q.Opens(id) or EMPTY, SHOWN.leads, y, used)
	for i = used + 1, #d.links do
		d.links[i].quest = nil
		d.links[i]:Hide()
	end
	local friends = Details.FriendsLine(id)
	y = PutHead(d.FriendsHead, friends and L["Friends"] or nil, y)
	y = Put(d.Friends, friends, y, 8)
	d.Body:SetHeight(math.max(1, y))
	local point, name = Details.PinTarget(q, status)
	d.Pin.point, d.Pin.name = point, name
	d.Pin:SetEnabled(point ~= nil)
	state.logKey = Side.LogKey()
	if top then
		d.Scroll:SetVerticalScroll(0)
	end
end

---------------------------------------------------------------------------
-- The right pane: the quest picked, else the briefing
---------------------------------------------------------------------------

-- The details of the quest picked, else the briefing of what the middle shows (never empty).
-- top: from its top.
function Side.Draw(top)
	local q = Quest(state.picked)
	view.d.Panel:SetShown(q ~= nil)
	view.b.Scroll:SetShown(q == nil)
	if q then
		FillDetails(top)
	else
		view.d.map.pick = nil
		view.d.map.frame:Hide()
		Brief.Draw(top)
		state.logKey = Side.LogKey()
	end
end

-- What the right pane shows of my quest log (the details' quest's lines, the briefing's quests in
-- progress): QUEST_LOG_UPDATE draws it again only when this changed.
function Side.LogKey()
	local parts = {}
	local function Add(id)
		parts[#parts + 1] = id .. (IsReady(id) and "+" or "-")
		for _, p in ipairs(Task.Progress(id, EMPTY) or EMPTY) do
			parts[#parts + 1] = p.text .. (p.done and "+" or "-")
		end
	end
	if view.d.Panel:IsShown() then
		if state.picked and StatusOf(state.picked) == "active" then
			Add(state.picked)
		end
	else
		for _, row in ipairs(view.b.rows) do
			if row:IsShown() and row.quest and StatusOf(row.quest) == "active" then
				Add(row.quest)
			end
		end
	end
	return table.concat(parts, "|")
end

---------------------------------------------------------------------------
-- Choosing
---------------------------------------------------------------------------

local function SmallOpen()
	return Q.IsSmallShown ~= nil and Q.IsSmallShown() == true
end

-- A quest into the right pane (nil: none, the briefing again); on the zone's map its pins ringed, its
-- objectives' areas and its way. user: a click, which the small window follows while it's open.
local function Pick(id, user)
	local changed = id ~= state.picked
	state.picked = id
	if view.g.frame:IsShown() then
		local before = state.path
		Path.Update()
		if before or state.path then
			DrawChain(CurrentPlace(), view.g.layout.group, true) -- (the way back lit, the head says what it needs)
		else
			Graph.Refill()
		end
	end
	if view.list.scroll:IsShown() then
		view.list:Lay()
	end
	if view.zp:IsShown() then
		ZonePage.ShowPick(CurrentPlace())
		Map.Follow(view.zp.map) -- (zoomed in with nothing of it in sight: the map goes to it)
	end
	Tabs.Switch() -- (the chain it offers is the quest's)
	Side.Draw(changed)
	if user and id and Q.ShowQuest and SmallOpen() then
		Q.ShowQuest(id)
	end
end

function Graph.Pick(id)
	Pick(id, true)
end

-- The details' way back: nothing picked, the briefing again.
function Side.Unpick()
	Pick(nil)
end

-- A place on the left: its zone page (or its quest list), its briefing; the search staying.
local function SelectPlace(id)
	if state.query ~= "" then
		state.drilled = true
	end
	state.where = id
	state.chain, state.path, state.picked, state.lastChain = nil, nil, nil, nil
	if state.tab ~= "zone" and state.tab ~= "overview" then
		state.tab = "zone"
		Save()
	end
	view.zones:Lay()
	DrawMiddle(false)
end

-- A quest anywhere: its zone (or dungeon) on the left, on the Zone tab its zone's map (a dungeon: its
-- quest list; chain: its chain opened, its card in sight), the quest picked (the quest list stays the
-- quest list).
local function Open(id, user, chain)
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
	end
	if state.tab ~= "overview" then
		state.tab = "zone"
		local place = CurrentPlace()
		local group = chain and place and Structure(place).groupOf[id]
		state.chain = group and group.key or nil
		Save()
	end
	state.picked, state.path = nil, nil
	if moved then
		DrawZones(true, target)
	else
		view.zones:Lay()
	end
	DrawMiddle(not moved, id, true)
	Pick(id, user)
end

-- A stub clicked: that step in its own zone, its chain opened there.
function Graph.Jump(id)
	Open(id, true, true)
end

-- A quest clicked in the right pane (a row, a link, a step): picked where it's shown (the zone's map,
-- the chain's page, the quest list), else its place opened (an opened chain stays one).
function Side.Go(id)
	local place = CurrentPlace()
	local mode = Mode()
	local g = view.g
	if place and Quest(id) then
		local it = g.frame:IsShown() and g.layout and g.layout.byQuest[id]
		if it then
			Pick(id, true)
			Graph.Reveal(it, G.W, G.H)
			return
		elseif (view.zp:IsShown() or (view.list.scroll:IsShown() and mode ~= "results")) and Structure(place).member[id] then
			Pick(id, true)
			return
		end
	end
	Open(id, true, mode == "zone" and state.chain ~= nil)
end

-- The details' "Open the chain" button, the switch's Chain: a chain of the place shown (key; else the
-- details' quest's) opened in the middle, the quest picked in sight.
function Side.OpenChain(key)
	key = key or view.d.ChainBtn.key
	if not key then
		return
	end
	if state.query ~= "" then
		state.drilled = true
	end
	state.tab = "zone"
	Save()
	state.chain, state.path = key, nil
	DrawMiddle(false, state.picked)
end

-- A quest's chain badge ("2/4") clicked, Q.OpenChain: its chain in the middle on the Zone tab, the
-- quest picked, its card in sight (on that chain's page already: picked there; else its place opens
-- with the chain, as a stub's click does). True when its chain shows.
function Side.ShowChain(id)
	if not Quest(id) then
		return false
	end
	local g = view.g
	local it = Mode() == "zone" and g.frame:IsShown() and g.layout and g.layout.byQuest[id]
	if it and not it.stub then
		Pick(id, true)
		Graph.Reveal(it, G.W, G.H)
		return true
	end
	state.tab = "zone" -- (Open keeps the quest list the quest list)
	Open(id, true, true)
	return state.chain ~= nil
end

local function BackToResults()
	state.drilled = false
	DrawMiddle(false)
end

-- From a chain back to its zone's page (the switch's Map; the quest picked stays): the chain is kept
-- as the switch's way back to it.
function Tabs.BackToZone()
	state.lastChain = state.chain or state.lastChain
	state.chain, state.path = nil, nil
	DrawMiddle(true)
end

function Tabs.Set(tab)
	if state.query ~= "" and not state.drilled then
		state.drilled = true -- (a tab clicked during a search: the place, the search stays)
	end
	if tab == "zone" and state.tab == "zone" then
		state.lastChain = state.chain or state.lastChain
		state.chain, state.path = nil, nil -- (the zone's tab again: its page)
	end
	state.tab = tab
	Save()
	DrawMiddle(false, state.picked)
end

local function SetFilter(key, on)
	filters[key] = on
	Save()
	Restatus()
	view.filters[key].Tick:SetShown(on)
	DrawMiddle(true)
end

-- The briefing's "Completed (N)" fold clicked, or the line saying what the level filter left out.
function ZonePage.Toggle(e)
	if e.more then
		SetFilter("allLevels", true)
	elseif e.fold then
		state.folded[e.key] = not state.folded[e.key]
		DrawMiddle(true)
	end
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
		state.statusOld, state.readyAt = false, nil
		state.nextRefresh = now + REFRESH_GAP
		Restatus() -- (statuses changed: what the filters show, the lines' colours, the pins)
		view.zones:Lay()
		DrawMiddle(true)
	end
	if state.readyAt and now >= state.readyAt then
		state.readyAt = nil
		-- (objectives done: a "?" may turn yellow, a line of progress change; only what shows them is
		-- drawn again, and only then)
		local place = CurrentPlace()
		local key = view.zp:IsShown() and ZonePage.ReadyKey(place) or nil
		if key and key ~= state.ready then
			state.ready = key
			state.spots[place.id] = nil
			ZonePage.DrawMap(place)
			ZonePage.DrawSummary(place)
		end
		if Side.LogKey() ~= state.logKey then
			if view.zp:IsShown() then
				ZonePage.ShowPick(place) -- (an objective done: its areas fade)
			end
			Side.Draw()
		end
		Map.PlaceMe(view.zp.map) -- (another zone: my arrow comes or goes)
	end
	if state.namesAt and now >= state.namesAt then
		state.namesAt = nil
		if view.g.frame:IsShown() then
			Graph.Refill()
		end
		if view.list.scroll:IsShown() then
			view.list:Lay()
		end
		Side.Draw()
	end
	if not (state.searchAt or state.statusOld or state.namesAt or state.readyAt) then
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

local EVENTS = { "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_LEVEL_UP", "QUEST_DATA_LOAD_RESULT", "QUEST_LOG_UPDATE",
	"ITEM_DATA_LOAD_RESULT", "ZONE_CHANGED_NEW_AREA" }

local function OnEvent(_, event, id)
	if event == "QUEST_DATA_LOAD_RESULT" or event == "ITEM_DATA_LOAD_RESULT" then
		local asked = event == "ITEM_DATA_LOAD_RESULT" and state.items or state.waiting
		if LT.IsSecret(id) or not asked[id] then
			return
		end
		if event == "QUEST_DATA_LOAD_RESULT" then
			state.waiting[id] = nil
		end
		state.namesAt = state.namesAt or GetTime() + NAMES_GAP
	elseif event == "QUEST_LOG_UPDATE" or event == "ZONE_CHANGED_NEW_AREA" then
		if state.readyAt then
			return -- (often: the pins, the progress lines and my arrow looked at once a second at most)
		end
		state.readyAt = GetTime() + READY_GAP
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

function Make.NewRowBase(parent, width)
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

function Make.NewZoneRow(parent, width)
	local row = Make.NewRowBase(parent, width)
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

function Make.ListTip(self)
	local e = self.entry
	if e and e.quest then
		QuestTip(self, e.quest, Make.BadgeText(self.Badge))
	end
end

-- A quest's chain badge on a row: "2/4" (its step, as the details count it) on a faint gold pill, a
-- Button of its own over the row (the controller reaches it): hovering lights it and says what it
-- is, a click opens the chain in the middle, the quest picked, its card in sight (Side.ShowChain).
function Make.NewBadge(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(36, 16)
	b.Back = b:CreateTexture(nil, "BACKGROUND")
	b.Back:SetAllPoints()
	b.Back:SetColorTexture(1, 0.82, 0, 0.1)
	NewEdges(b)
	Edges(b, 1, 0.82, 0, 0.3)
	b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.Text:SetPoint("CENTER", 0, 0)
	b:SetHighlightTexture(T.highlight, "ADD")
	b:SetScript("OnEnter", Make.BadgeTip)
	b:SetScript("OnLeave", Untip)
	b:SetScript("OnClick", function(self)
		Untip(self)
		if self.quest then
			Side.ShowChain(self.quest)
		end
	end)
	b:Hide()
	return b
end

-- A badge for a quest (nil: hidden); the room it takes (its width and a gap), 0 when hidden.
function Make.FillBadge(b, id)
	local step, total = Rule.Step(id)
	b.quest, b.step, b.total = step and id or nil, step, total
	if not step then
		b:Hide()
		return 0
	end
	b.label = step .. "/" .. total
	b.Text:SetText(HEX.available .. b.label .. "|r")
	b:SetWidth(math.max(30, b.Text:GetStringWidth() + 12))
	b:Show()
	return b:GetWidth() + 6
end

-- What a row's tooltip names as its badge ("2/4"), nil without one.
function Make.BadgeText(b)
	return b and b:IsShown() and b.quest and b.label or nil
end

-- The badge's tooltip: its chain, the step, what a click does.
function Make.BadgeTip(self)
	if not self.quest then
		return
	end
	local _, _, name = StepOf(self.quest)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(name or L["Chain"], 1, 0.82, 0)
	GameTooltip:AddLine(L["Step %d of %d"]:format(self.step, self.total), 1, 1, 1)
	GameTooltip:AddLine(L["Click: open the chain"], 0.5, 0.75, 1)
	GameTooltip:Show()
end

function Make.NewListRow(parent, width)
	local row = Make.NewRowBase(parent, width)
	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(16, 16)
	row.Icon:SetPoint("LEFT", 4, 0)
	row.Right = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.Right:SetPoint("RIGHT", -4, 0)
	row.Right:SetWidth(160)
	row.Right:SetJustifyH("RIGHT")
	row.Right:SetWordWrap(false)
	row.Badge = Make.NewBadge(row)
	row:SetScript("OnEnter", Make.ListTip)
	row:SetScript("OnLeave", Untip)
	row:SetScript("OnClick", function(self)
		local e = self.entry
		if not e then
			return
		elseif e.more then
			ZonePage.Toggle(e) -- (all levels)
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

function Make.NewLink(parent, width)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, LINK_H)
	b:SetHighlightTexture(T.highlight, "ADD")
	b.Picked = b:CreateTexture(nil, "BACKGROUND")
	b.Picked:SetAllPoints()
	b.Picked:SetColorTexture(1, 0.82, 0, 0.12)
	b.Picked:Hide()
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

-- Where it starts or is turned in: the spot, the other givers, drops and enders, what a click does.
function Make.PlaceTip(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(self.name or self.Text:GetText() or "", 1, 1, 1)
	if self.point then
		GameTooltip:AddLine(("%s  %.1f, %.1f"):format(MapName(self.point.map) or "?", self.point.x * 100, self.point.y * 100), 0.8, 0.8, 0.8)
	end
	for _, line in ipairs(self.tip or EMPTY) do
		GameTooltip:AddLine(line, 0.9, 0.9, 0.9)
	end
	if self.point then
		GameTooltip:AddLine(L["Click: put a map pin there"], 0.5, 0.75, 1)
	end
	GameTooltip:Show()
end

-- A gold divider (Blizzard's when the client has it).
function Make.NewDivider(parent)
	local line = parent:CreateTexture(nil, "ARTWORK")
	Art(line, "Options_HorizontalDivider", T.flat)
	if not atlasKnown.Options_HorizontalDivider then
		line:SetVertexColor(1, 0.82, 0, 0.25)
	end
	line:SetHeight(1)
	return line
end

function Make.NewHead(parent, width)
	local h = CreateFrame("Frame", nil, parent)
	h:SetSize(width, 18)
	h.Text = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	h.Text:SetPoint("TOPLEFT")
	local line = Make.NewDivider(h)
	line:SetPoint("BOTTOMLEFT", 0, 1)
	line:SetPoint("BOTTOMRIGHT", 0, 1)
	h:Hide()
	return h
end

-- An objective's line hovered: what it is, where it drops (each source and its zone), its areas lit
-- on the map in sight.
function Make.ObjectiveEnter(self)
	local line = self.line
	if not line then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(line.text, 1, 1, 1, 1, true)
	local o = line.objective and Task.List(self.quest)[line.objective]
	for _, s in ipairs(o and type(o.sources) == "table" and o.sources or EMPTY) do
		local p = s.points and s.points[1]
		local zone = p and MapName(p.map)
		local name = o.kind == "item" and tonumber(s.chance) and L["Drops from %s (%s%%)"]:format(s.name or "?", Chance(s.chance)) or (s.name or "?")
		GameTooltip:AddLine(name .. (zone and (GREY .. SEP .. zone .. "|r") or ""), 0.85, 0.85, 0.85)
	end
	if Make.ObjectivePoint(self) then
		GameTooltip:AddLine(L["Click: put a map pin there"], 0.5, 0.75, 1)
	end
	GameTooltip:Show()
	Map.LightArea(view.zp.map, line.objective)
	Map.LightArea(view.d.map, line.objective)
end

function Make.ObjectiveLeave(self)
	Untip(self)
	Map.LightArea(view.zp.map, nil)
	Map.LightArea(view.d.map, nil)
end

-- Where an objective's map pin goes: its area on the map in sight, else its first source's first spot.
function Make.ObjectivePoint(self)
	local line = self.line
	local o = line and line.objective and Task.List(self.quest)[line.objective]
	if not o then
		return nil
	end
	local m = view.zp:IsShown() and view.zp.map or view.d.map
	for i = 1, m.areasShown do
		local spec = m.areas[i].spec
		if spec.objective == line.objective then
			return { map = m.map, x = spec.x, y = spec.y }
		end
	end
	for _, s in ipairs(type(o.sources) == "table" and o.sources or EMPTY) do
		local p = s.points and s.points[1]
		if p then
			return p
		end
	end
end

-- A reward: the game's item icon, its count, a border in its quality's colour; its tooltip the game's.
function Make.NewItem(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(36, 36)
	b.Icon = b:CreateTexture(nil, "ARTWORK")
	b.Icon:SetAllPoints()
	b.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.Border = b:CreateTexture(nil, "OVERLAY")
	b.Border:SetTexture(T.border)
	b.Border:SetAllPoints()
	b.Border:Hide()
	b.Count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	b.Count:SetPoint("BOTTOMRIGHT", -2, 2)
	b.Count:SetJustifyH("RIGHT")
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b:SetScript("OnEnter", function(self)
		if not self.item then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if GameTooltip.SetItemByID then
			GameTooltip:SetItemByID(self.item)
		else
			GameTooltip:SetHyperlink("item:" .. self.item)
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", Untip)
	b:SetScript("OnClick", function(self) -- (Shift: its link in chat, Ctrl: try it on; the game's)
		local ok, _, link = false, nil, nil
		if self.item and C_Item and C_Item.GetItemInfo then
			ok, _, link = pcall(C_Item.GetItemInfo, "item:" .. self.item)
		end
		if ok and type(link) == "string" and HandleModifiedItemClick then
			HandleModifiedItemClick(link)
		end
	end)
	return b
end

-- The right pane's details: the way back on top, then (scrolling) the quest's icon, title and
-- status, its chain and steps, objectives, giver and turn-in, the small map, rewards, requirements,
-- what it needs and leads to, friends; "Map pin" and "Companion" at the bottom.
function Make.BuildDetails(root, x, y, width, height)
	local d = { links = {}, places = {}, steps = {}, objectives = {}, items = {} }
	view.d = d
	local panel = CreateFrame("Frame", nil, root)
	panel:SetPoint("TOPLEFT", x, -y)
	panel:SetSize(width, height)
	panel:Hide()
	d.Panel = panel
	local bodyW = width - BAR_W
	d.bodyW = bodyW
	d.Back = CreateFrame("Button", nil, panel)
	d.Back:SetSize(160, 22)
	d.Back:SetPoint("TOPLEFT", 0, 0)
	d.Back.Icon = d.Back:CreateTexture(nil, "ARTWORK")
	d.Back.Icon:SetTexture(T.back)
	d.Back.Icon:SetSize(18, 18)
	d.Back.Icon:SetPoint("LEFT")
	d.Back.Text = d.Back:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	d.Back.Text:SetPoint("LEFT", 22, 0)
	d.Back.Text:SetWordWrap(false)
	d.Back:SetHighlightTexture(T.highlight, "ADD")
	d.Back:SetScript("OnClick", function(self)
		Untip(self)
		Side.Unpick()
	end)
	d.Back:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(L["Back to the overview"], 1, 1, 1)
		GameTooltip:Show()
	end)
	d.Back:SetScript("OnLeave", Untip)
	d.Scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
	d.Scroll:SetPoint("TOPLEFT", 0, -28)
	d.Scroll:SetSize(bodyW, height - 28 - 34)
	d.Body = CreateFrame("Frame", nil, d.Scroll)
	d.Body:SetSize(bodyW, 1)
	d.Scroll:SetScrollChild(d.Body)
	local function Text(font, w)
		local fs = d.Body:CreateFontString(nil, "OVERLAY", font)
		fs:SetWidth(w or (bodyW - 4))
		fs:SetJustifyH("LEFT")
		fs:SetJustifyV("TOP")
		fs:SetSpacing(2)
		return fs
	end
	local function Head()
		return Make.NewHead(d.Body, bodyW - 4)
	end
	d.Icon = d.Body:CreateTexture(nil, "ARTWORK")
	d.Icon:SetSize(32, 32)
	d.Icon:SetPoint("TOPLEFT", 0, -2)
	d.Title = Text("GameFontNormalLarge", bodyW - 44)
	d.Sub = Text("GameFontHighlight", bodyW - 44)
	d.Req = Text("GameFontHighlightSmall")
	d.NeedsMore, d.LeadsMore = Text("GameFontHighlightSmall"), Text("GameFontHighlightSmall")
	d.StepsBefore, d.StepsMore = Text("GameFontHighlightSmall"), Text("GameFontHighlightSmall")
	d.ChoiceLabel, d.GetLabel = Text("GameFontHighlightSmall"), Text("GameFontHighlightSmall")
	d.Money = Text("GameFontHighlight")
	d.Friends = Text("GameFontHighlightSmall")
	d.ReqHead, d.NeedsHead, d.LeadsHead, d.FriendsHead = Head(), Head(), Head(), Head()
	d.ChainHead, d.ObjHead, d.WhereHead, d.RewardHead = Head(), Head(), Head(), Head()
	-- The chain's heading: how far along (a bar under it), "Chain" at its right opens it in the middle.
	d.ChainBtn = CreateFrame("Button", nil, d.ChainHead)
	d.ChainBtn:SetPoint("BOTTOMRIGHT", d.ChainHead, "BOTTOMRIGHT", 0, 2)
	d.ChainBtn.Text = d.ChainBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	d.ChainBtn.Text:SetPoint("RIGHT", -2, 0)
	d.ChainBtn.Text:SetText(L["Open the chain"] .. " >")
	d.ChainBtn:SetSize(d.ChainBtn.Text:GetStringWidth() + 8, 16)
	d.ChainBtn:SetHighlightTexture(T.highlight, "ADD")
	d.ChainBtn:SetScript("OnClick", function(self)
		Untip(self)
		Side.OpenChain()
	end)
	d.ChainBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(L["Click: open the chain"], 1, 1, 1)
		GameTooltip:Show()
	end)
	d.ChainBtn:SetScript("OnLeave", Untip)
	d.StepBack = d.Body:CreateTexture(nil, "ARTWORK")
	d.StepBack:SetSize(bodyW - 4, 4)
	d.StepBack:SetColorTexture(0, 0, 0, 0.6)
	d.StepBack:Hide()
	d.StepBar = d.Body:CreateTexture(nil, "ARTWORK", nil, 1)
	d.StepBar:SetPoint("TOPLEFT", d.StepBack, "TOPLEFT")
	d.StepBar:SetHeight(4)
	d.StepBar:Hide()
	d.map = Map.New(d.Body, bodyW - 4, math.floor((bodyW - 4) * 2 / 3), false)
	-- Links to quests (what it needs, what it leads to) and the chain's steps: a click goes to that one.
	local function Linker(pool)
		return function(i)
			local b = pool[i]
			if not b then
				b = Make.NewLink(d.Body, bodyW - 4)
				b:SetScript("OnEnter", function(self) QuestTip(self, self.quest) end)
				b:SetScript("OnLeave", Untip)
				b:SetScript("OnClick", function(self)
					if self.quest then
						Untip(self)
						Side.Go(self.quest)
					end
				end)
				pool[i] = b
			end
			return b
		end
	end
	d.Link, d.Step = Linker(d.links), Linker(d.steps)
	function d.Objective(i)
		local b = d.objectives[i]
		if not b then
			b = CreateFrame("Button", nil, d.Body)
			b:SetSize(bodyW - 4, LINK_H)
			b:SetHighlightTexture(T.highlight, "ADD")
			b.Icon = b:CreateTexture(nil, "ARTWORK")
			b.Icon:SetSize(12, 12)
			b.Icon:SetPoint("TOPLEFT", 4, -3)
			b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			b.Text:SetPoint("TOPLEFT", 20, -3)
			b.Text:SetWidth(bodyW - 4 - 20 - 18)
			b.Text:SetJustifyH("LEFT")
			b.Text:SetJustifyV("TOP")
			b.Dot = b:CreateTexture(nil, "ARTWORK")
			b.Dot:SetTexture(T.circle)
			b.Dot:SetSize(9, 9)
			b.Dot:SetPoint("TOPRIGHT", -4, -4)
			b:SetScript("OnEnter", Make.ObjectiveEnter)
			b:SetScript("OnLeave", Make.ObjectiveLeave)
			b:SetScript("OnClick", function(self)
				local p = Make.ObjectivePoint(self)
				if p then
					Map.PinAt(p.map, p.x, p.y, self.line and self.line.text)
				end
			end)
			d.objectives[i] = b
		end
		return b
	end
	function d.Item(i)
		local b = d.items[i]
		if not b then
			b = Make.NewItem(d.Body)
			d.items[i] = b
		end
		return b
	end
	-- Its giver and its turn-in: a line each (two with an item's drop), a click puts a map pin there.
	for i = 1, 2 do
		local b = Make.NewLink(d.Body, bodyW - 4)
		b.Icon:ClearAllPoints()
		b.Icon:SetSize(16, 16)
		b.Icon:SetPoint("TOPLEFT", 2, -2)
		b.Text:ClearAllPoints()
		b.Text:SetPoint("TOPLEFT", 22, -4)
		b.Text:SetWidth(bodyW - 4 - 24)
		b.Text:SetWordWrap(true)
		b.Text:SetFontObject("GameFontHighlight")
		b:SetScript("OnEnter", Make.PlaceTip)
		b:SetScript("OnLeave", Untip)
		b:SetScript("OnClick", function(self)
			if self.point then
				Map.PinAt(self.point.map, self.point.x, self.point.y, self.name)
			end
		end)
		d.places[i] = b
	end
	d.place = d.places[1]
	-- At the bottom: the game's map pin where to go next, the quest in the small window.
	d.Pin = LT.Window.AddButton(panel, L["Map pin"], function(self)
		if self.point then
			Map.PinAt(self.point.map, self.point.x, self.point.y, self.name)
		end
	end, { "BOTTOMLEFT", panel, "BOTTOMLEFT", 2, 4 })
	d.Pin:SetSize(math.floor((width - 12) / 2), 24)
	d.Pin:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L["Map pin"], 1, 1, 1)
		GameTooltip:AddLine(self.point and L["Where to go next: %s"]:format((self.name or "?") .. " (" .. (MapName(self.point.map) or "?") .. ")")
			or L["No spot known for it."], 0.9, 0.9, 0.9, true)
		GameTooltip:Show()
	end)
	d.Pin:SetScript("OnLeave", Untip)
	d.Small = LT.Window.AddButton(panel, L["Companion"], function()
		if state.picked and Q.ShowQuest then
			Q.ShowQuest(state.picked)
		end
	end, { "LEFT", d.Pin, "RIGHT", 6, 0 })
	d.Small:SetSize(math.floor((width - 12) / 2), 24)
	d.Small:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L["Show in the small window"], 1, 1, 1)
		GameTooltip:Show()
	end)
	d.Small:SetScript("OnLeave", Untip)
	d.Small:Hide()
	d.Pin:Hide()
	d.Body:Hide()
end

-- The right pane's briefing (nothing picked): a scroll area of its own, the same place as the details.
function Make.BuildBrief(root, x, y, width, height)
	local b = { heads = {}, rows = {}, cards = {}, w = width - BAR_W, height = height, nHeads = 0, nRows = 0, nCards = 0, y = 0 }
	view.b = b
	b.Scroll = CreateFrame("ScrollFrame", nil, root, "UIPanelScrollFrameTemplate")
	b.Scroll:SetPoint("TOPLEFT", x, -y)
	b.Scroll:SetSize(b.w, height)
	b.Body = CreateFrame("Frame", nil, b.Scroll)
	b.Body:SetSize(b.w, 1)
	b.Scroll:SetScrollChild(b.Body)
	local function Text(font, w)
		local fs = b.Body:CreateFontString(nil, "OVERLAY", font)
		fs:SetWidth(w or (b.w - 4))
		fs:SetJustifyH("LEFT")
		fs:SetJustifyV("TOP")
		fs:SetSpacing(2)
		fs:Hide()
		return fs
	end
	b.Title = Text("GameFontNormalLarge", b.w - 20)
	b.Sub, b.Line = Text("GameFontHighlightSmall"), Text("GameFontHighlight")
	b.Empty, b.More, b.Friends = Text("GameFontDisable"), Text("GameFontHighlightSmall"), Text("GameFontHighlightSmall")
	b.Dot = b.Body:CreateTexture(nil, "ARTWORK")
	b.Dot:SetTexture(T.circle)
	b.Dot:SetSize(10, 10)
	b.Dot:Hide()
	b.BarBack = b.Body:CreateTexture(nil, "ARTWORK")
	b.BarBack:SetHeight(6)
	b.BarBack:SetColorTexture(0, 0, 0, 0.6)
	b.BarBack:Hide()
	b.Bar = b.Body:CreateTexture(nil, "ARTWORK", nil, 1)
	b.Bar:SetPoint("TOPLEFT", b.BarBack, "TOPLEFT")
	b.Bar:SetHeight(6)
	b.Bar:Hide()
	b.Count = b.Body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.Count:SetJustifyH("RIGHT")
	b.Count:Hide()
end

function Make.OnSearchTyped(box)
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
function Make.NewFilter(parent, key, label, tip)
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

function Make.BuildTop()
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
		Make.OnSearchTyped(box)
	end)
	view.Clear:Hide()
	box:SetScript("OnTextChanged", Make.OnSearchTyped)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	-- The filters, on the right.
	view.filters = {
		allLevels = Make.NewFilter(frame, "allLevels", L["All levels"], L["Also the quests far below or above your level. The search and an opened chain always show every level."]),
		showOther = Make.NewFilter(frame, "showOther", L["Show quests not for you"], L["Also the quests for another race, class or faction (dimmed)."]),
	}
	local x = -16
	for _, key in ipairs({ "showOther", "allLevels" }) do
		local b = view.filters[key]
		b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", x, -36)
		x = x - b:GetWidth() - 12
	end
	view.Search = { label, box, view.filters.allLevels, view.filters.showOther }
end

-- -, the zoom, +, Fit: a chain's (the zone map has its own on its strip).
function Make.BuildZoom(parent)
	local z = CreateFrame("Frame", nil, parent)
	z:SetSize(170, 24)
	view.Zoom = z
	local minus = LT.Window.AddButton(z, "-", function() Graph.SetZoom(view.g.zoom - G.ZOOM_STEP) end, { "LEFT", z, "LEFT", 0, 0 })
	minus:SetSize(26, 22)
	view.ZoomText = z:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	view.ZoomText:SetPoint("LEFT", minus, "RIGHT", 4, 0)
	view.ZoomText:SetWidth(40)
	local plus = LT.Window.AddButton(z, "+", function() Graph.SetZoom(view.g.zoom + G.ZOOM_STEP) end, { "LEFT", view.ZoomText, "RIGHT", 4, 0 })
	plus:SetSize(26, 22)
	local fit = LT.Window.AddButton(z, L["Fit"], function()
		Graph.Fit()
	end, { "LEFT", plus, "RIGHT", 4, 0 })
	fit:SetSize(56, 22)
	view.ZoomButtons = { minus = minus, plus = plus, fit = fit }
end

-- A chain's viewport: our own scrolling (wheel up and down, Shift: sideways, Ctrl: zoom; dragging
-- moves it), a frame that clips the canvas.
function Make.BuildGraph(parent, x, y, w, h)
	local g = { w = w, h = h, sx = 0, sy = 0, zoom = 1, cards = {}, freeCards = {}, lines = {}, pills = {}, made = 0, lays = 0, linesShown = 0 }
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
	f:Hide()
end

-- The zone page: the zone's map filling the middle (3:2), one line under it: what's here for me now
-- (with none to take, a zone that has some), at its right how the map works.
function Make.BuildZonePage(parent, x, y, w, h)
	local zp = CreateFrame("Frame", nil, parent)
	zp:SetPoint("TOPLEFT", x, -y)
	zp:SetSize(w, h)
	view.zp = zp
	zp.map = Map.New(zp, Z.MAP_W, Z.MAP_H, true)
	zp.map.frame:SetPoint("TOPLEFT", zp, "TOPLEFT", 0, 0)
	zp.map.chooserOwner = zp -- (a pin's list of quests isn't clipped by the map)
	zp.map.onClick = function(id)
		Pick(id, true)
	end
	zp.map.onEnter = ZonePage.HoverPin
	zp.map.onLeave = function()
		ZonePage.HoverPin(nil)
	end
	zp.map.noteOf = ZonePage.PinNote -- (what each pin is, in its tooltip)
	zp.Line = CreateFrame("Frame", nil, zp)
	zp.Line:SetPoint("TOPLEFT", 0, -(Z.MAP_H + 4))
	zp.Line:SetSize(Z.MAP_W, Z.LINE_H)
	zp.Counts = zp.Line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	zp.Counts:SetPoint("LEFT", 4, 0)
	zp.Counts:SetJustifyH("LEFT")
	zp.Guide = zp.Line:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	zp.Guide:SetJustifyH("LEFT")
	zp.Guide:Hide()
	zp.Suggest = CreateFrame("Button", nil, zp.Line)
	zp.Suggest:SetSize(200, 22)
	zp.Suggest:SetPoint("LEFT", zp.Guide, "RIGHT", 10, 0)
	zp.Suggest.Back = zp.Suggest:CreateTexture(nil, "BACKGROUND")
	zp.Suggest.Back:SetAllPoints()
	zp.Suggest.Back:SetColorTexture(1, 0.82, 0, 0.1)
	zp.Suggest.Text = zp.Suggest:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	zp.Suggest.Text:SetPoint("LEFT", 6, 0)
	zp.Suggest:SetHighlightTexture(T.highlight, "ADD")
	zp.Suggest:SetScript("OnClick", function(self)
		if self.map then
			Q.SelectZone(self.map)
		end
	end)
	zp.Suggest:Hide()
	zp.Hint = zp.Line:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	zp.Hint:SetPoint("RIGHT", -4, 0)
	zp.Hint:SetJustifyH("RIGHT")
	zp.Hint:SetText(L["Wheel: zoom · drag: move · right-click a pin: map pin"])
	zp:Hide()
end

-- The head over a page (a chain's way back to the map is the switch's Map, above it): the title, a
-- line under it, how far along with a bar; the zoom at its right.
function Make.BuildHead(root, x, y, w)
	local h = CreateFrame("Frame", nil, root)
	h:SetPoint("TOPLEFT", x, -y)
	h:SetSize(w, HEAD_H)
	view.head = h
	h.Dot = h:CreateTexture(nil, "ARTWORK")
	h.Dot:SetTexture(T.circle)
	h.Dot:SetSize(10, 10)
	h.Dot:Hide()
	h.Title = h:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	h.Title:SetJustifyH("LEFT")
	h.Title:SetWordWrap(false)
	h.Sub = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	h.Sub:SetPoint("TOPLEFT", 0, -26)
	h.Sub:SetPoint("RIGHT", h, "RIGHT", -346, 0) -- (left of the bar)
	h.Sub:SetJustifyH("LEFT")
	h.Sub:SetWordWrap(false)
	h.Count = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	h.Count:SetPoint("TOPRIGHT", -186, -6)
	h.Count:SetJustifyH("RIGHT")
	h.BarBack = h:CreateTexture(nil, "ARTWORK")
	h.BarBack:SetPoint("TOPRIGHT", -186, -22)
	h.BarBack:SetSize(150, 5)
	h.BarBack:SetColorTexture(0, 0, 0, 0.6)
	h.Bar = h:CreateTexture(nil, "ARTWORK", nil, 1)
	h.Bar:SetPoint("TOPLEFT", h.BarBack, "TOPLEFT")
	h.Bar:SetHeight(5)
	local rule = Make.NewDivider(h)
	rule:SetPoint("BOTTOMLEFT", 0, 2)
	rule:SetPoint("BOTTOMRIGHT", 0, 2)
	Make.BuildZoom(h)
	view.Zoom:SetPoint("TOPRIGHT", h, "TOPRIGHT", 0, -6)
end

-- One half of the Zone tab's switch (key "map" or "chain"): a Button of ours, its own hover light (not
-- on a greyed half), a gold line under it while it's the one shown.
function Make.NewHalf(parent, key)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(TABS_H - 4)
	b.key = key
	b.Back = b:CreateTexture(nil, "BACKGROUND")
	b.Back:SetAllPoints()
	b.Hover = b:CreateTexture(nil, "ARTWORK") -- (shown by OnEnter: the controller's focus too)
	b.Hover:SetAllPoints()
	b.Hover:SetTexture(T.highlight)
	b.Hover:SetBlendMode("ADD")
	b.Hover:Hide()
	b.Line = b:CreateTexture(nil, "ARTWORK")
	b.Line:SetPoint("BOTTOMLEFT")
	b.Line:SetPoint("BOTTOMRIGHT")
	b.Line:SetHeight(2)
	b.Line:SetColorTexture(1, 0.82, 0, 1)
	b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	b.Text:SetJustifyH("LEFT")
	b.Text:SetWordWrap(false)
	b.Text:SetPoint("LEFT", 10, 1)
	b:SetScript("OnEnter", Tabs.HalfEnter)
	b:SetScript("OnLeave", Tabs.HalfLeave)
	b:SetScript("OnClick", Tabs.HalfClick)
	return b
end

-- The tab bar (the zone page, the overview, the views registered), the Zone tab's switch "Map |
-- Chain" right after the tabs, and the way back to the results.
function Make.BuildTabs(root, x, y, w)
	local bar = CreateFrame("Frame", nil, root)
	bar:SetPoint("TOPLEFT", x, -y)
	bar:SetSize(w, TABS_H)
	view.tabBar, view.tabs = bar, {}
	local sw = CreateFrame("Frame", nil, bar)
	sw:SetSize(200, TABS_H - 4)
	view.switch = sw
	sw.map, sw.chain = Make.NewHalf(sw, "map"), Make.NewHalf(sw, "chain")
	sw.map:SetPoint("TOPLEFT", 0, 0)
	sw.chain:SetPoint("TOPLEFT", sw.map, "TOPRIGHT", 0, 0)
	sw.chain.Count = sw.chain:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sw.chain.Count:SetPoint("RIGHT", -10, 1)
	sw.chain.Count:SetJustifyH("RIGHT")
	sw.Split = sw:CreateTexture(nil, "OVERLAY")
	sw.Split:SetPoint("TOPLEFT", sw.chain, "TOPLEFT", 0, -4)
	sw.Split:SetPoint("BOTTOMLEFT", sw.chain, "BOTTOMLEFT", 0, 4)
	sw.Split:SetWidth(1)
	sw.Split:SetColorTexture(1, 0.82, 0, 0.35)
	NewEdges(sw)
	Edges(sw, 1, 0.82, 0, 0.35)
	sw:Hide()
	view.Back = CreateFrame("Button", nil, bar)
	view.Back:SetSize(190, TABS_H - 4)
	view.Back:SetPoint("TOPRIGHT", 0, 0)
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
	Tabs.Layout()
end

-- The line under a chain's page: what its lines mean (the statuses say their reason themselves).
function Make.BuildLegend(parent, x, y, w)
	view.Legend = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	view.Legend:SetPoint("TOPLEFT", x + 4, -y)
	view.Legend:SetWidth(w - 8)
	view.Legend:SetJustifyH("LEFT")
	view.Legend:SetWordWrap(false)
	view.Legend:SetText(L["dashed: lead-in · one of: any one is enough · orange: the way to a locked quest"])
	view.Legend:Hide()
end

function Make.OnHidden(self)
	for _, event in ipairs(EVENTS) do
		self:UnregisterEvent(event)
	end
	state.listening = false
	state.searchAt, state.statusOld, state.namesAt, state.readyAt = nil, false, nil, nil
	self:SetScript("OnUpdate", nil)
	view.g.drag, view.zp.map.drag = nil, nil
	view.g.frame:SetScript("OnUpdate", nil)
	view.zp.map.frame:SetScript("OnUpdate", nil)
	Map.CloseChooser(view.zp.map)
	view.Box:ClearFocus()
	Views.Show(nil) -- (a view registered: its OnHide)
	GameTooltip:Hide()
end

-- How big the window is: wider where the screen has room (the right pane wider too, the map in the
-- middle growing with it at 3:2), as high as that map needs; at least SIZE.W x SIZE.H (scaled down to
-- fit a smaller screen: Fit). Returns the width, the height, the right pane's width.
function Make.Size()
	local sw = tonumber(GetScreenWidth and GetScreenWidth()) or SIZE.W
	local sh = tonumber(GetScreenHeight and GetScreenHeight()) or SIZE.H
	local function Right(w)
		return w >= SIZE.WIDE and 400 or 360
	end
	local function High(w)
		local mapW = w - INSET_W - 2 * PAD - EDGE - ZONES_W - 2 * GAP - Right(w)
		return math.max(SIZE.H, math.floor(mapW * 2 / 3) + INSET_H + 2 * PAD + TABS_H + 4 + Z.LINE_H + 40)
	end
	local w = math.max(SIZE.W, math.min(SIZE.MAX_W, math.floor((sw - SCREEN_W - 40) / SIZE.STEP) * SIZE.STEP))
	while w > SIZE.W and High(w) > sh - SCREEN_H - 20 do
		w = w - SIZE.STEP
	end
	return w, High(w), Right(w)
end

local function Build()
	WIDTH, HEIGHT, DETAILS_W = Make.Size()
	frame = LT.Window.Create("LefthyToolsLodestarBrowser", "Lodestar", WIDTH, HEIGHT)
	view = { registry = registry, W = WIDTH, H = HEIGHT, Size = Make.Size }
	LoadSaved()
	local width, height = WIDTH - INSET_W, HEIGHT - INSET_H
	local root = CreateFrame("Frame", nil, frame.Inset)
	root:SetPoint("TOPLEFT")
	root:SetSize(width, height)
	view.root = root
	Make.BuildTop()
	local paneH = height - 2 * PAD
	view.zones = NewList(root, PAD, PAD, ZONES_W - BAR_W, paneH, Make.NewZoneRow, FillZoneRow)
	local middleX = PAD + ZONES_W + GAP
	local detailX = width - PAD - EDGE - DETAILS_W
	local middleW = detailX - GAP - middleX
	Make.BuildTabs(root, middleX, PAD, middleW)
	Make.BuildHead(root, middleX, PAD + TABS_H, middleW)
	local contentY = PAD + TABS_H + HEAD_H
	local contentH = paneH - TABS_H - HEAD_H - LEGEND_H
	-- (a view registered gets everything under the tab bar)
	view.viewX, view.viewY, view.viewW, view.viewH = middleX, PAD + TABS_H, middleW, paneH - TABS_H
	-- The zone page right under the tab bar (no head: the briefing has it): the map as wide as the
	-- middle, 3:2, as long as the line under it fits.
	local pageH = paneH - TABS_H - 4
	Z.MAP_W, Z.MAP_H = middleW, math.floor(middleW * 2 / 3)
	if Z.MAP_H + Z.LINE_H + 8 > pageH then
		Z.MAP_H = pageH - Z.LINE_H - 8
		Z.MAP_W = math.floor(Z.MAP_H * 3 / 2)
	end
	Make.BuildZonePage(root, middleX, PAD + TABS_H + 4, middleW, pageH)
	Make.BuildGraph(root, middleX, contentY, middleW, contentH)
	view.list = NewList(root, middleX, contentY, middleW - BAR_W, contentH, Make.NewListRow, FillListRow)
	view.list.scroll:Hide()
	Make.BuildLegend(root, middleX, contentY + contentH + 5, middleW)
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
	Make.BuildDetails(root, detailX, PAD, DETAILS_W, paneH)
	Make.BuildBrief(root, detailX, PAD, DETAILS_W, paneH)
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
	frame:HookScript("OnHide", Make.OnHidden)
	if Q.OnDataChanged then
		Q.OnDataChanged(DataChanged)
	end
	if Q.OnFriendProgress then
		Q.OnFriendProgress(function() -- (QuestShare.lua: friends' answers came: redrawn)
			if frame and frame:IsShown() then
				wipe(state.infos) -- (the chains' friends)
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
	local m = LT:GetModule("lodestar")
	if m and not m.enabled then
		LT.Print("Lodestar is switched off (/lefthy enable lodestar).")
		return false
	end
	return true
end

-- Opens the big window, on a quest if one is given (its zone, its chain with its card in sight, its
-- details). True when it's open with the data.
function Q.OpenBrowser(id)
	if not Allowed() then
		return false
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
		Restatus()
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
	return ready
end

-- Opens the big window on a quest's chain (a chain badge elsewhere, My quests'): the quest's zone on
-- the Zone tab, the quest picked, its chain in the middle with its card in sight. A quest in no chain
-- opens as Q.OpenBrowser(id) does. True when its chain shows.
function Q.OpenChain(id)
	id = tonumber(id)
	if not (id and Q.OpenBrowser()) then
		return false
	end
	if not (Quest(id) and Rule.Step(id)) then
		Open(id, true)
		return false
	end
	return Side.ShowChain(id)
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

-- Opens the big window on a zone's page (a uiMapID: a city's floor or a cave counts as its zone; or
-- a dungeon's name). True when it's there.
function Q.SelectZone(map)
	local shown = frame ~= nil and frame:IsShown()
	if not shown and not Q.OpenBrowser() then
		return false
	end
	if not view.root:IsShown() then
		return false
	end
	Lists()
	local id = PlaceFor(map)
	if not id then
		return false
	end
	local place = state.places[id]
	state.folded[place.kind == "zone" and ("c:" .. tostring(place.continent)) or "c:dungeons"] = nil
	SelectPlace(id) -- (a view registered: the zone page)
	DrawZones(true, id)
	return true
end

-- A view of another file as a tab of the big window, after the zone page and the overview:
-- build(parent) is called the first time it's shown, with the frame it has (the area under the tab
-- bar, between the zones and the details), and returns { frame, Refresh = function(self) end,
-- OnShow = function(self) end, OnHide = function(self) end } (each optional; a frame without points
-- fills the parent). Refresh runs each time it's shown and when quests or the data change while it
-- is. The same key again: its label and build are replaced (a view already built stays). True when
-- registered ("zone" and "overview" are the window's own).
function Q.RegisterBrowserView(key, label, build)
	if type(key) ~= "string" or key == "" or key == "zone" or key == "overview" or key == "results" or type(build) ~= "function" then
		return false
	end
	local v = registry.byKey[key]
	if v then
		v.label, v.build = label or v.label, build
	else
		v = { key = key, label = label or key, build = build }
		registry.byKey[key] = v
		registry.order[#registry.order + 1] = v
	end
	Tabs.Layout()
	return true
end

-- Opens the big window on a tab: "zone", "overview" or a registered view's key. True when shown.
function Q.ShowBrowserView(key)
	if not TabKnown(key) then
		return false
	end
	local shown = frame ~= nil and frame:IsShown()
	if not shown and not Q.OpenBrowser() then
		return false
	end
	if not view.root:IsShown() then
		return false
	end
	if state.query ~= "" then
		state.drilled = true
	end
	if key == "zone" then
		state.chain, state.path = nil, nil
	end
	state.tab = key
	Save()
	DrawMiddle(false, state.picked)
	return true
end

-- The window's frames and state, what Q.OnDataChanged calls, the filters, the views (for the tests).
function Q.BrowserView()
	return view, state, frame, DataChanged, filters, registry
end
