local _, ns = ...
local LT = ns.LT
local L = ns.L
local Q = ns.Questtree or {}
ns.Questtree = Q

-- Questtree's big window (Q.ToggleBrowser, Q.OpenBrowser(id)): every zone's quest chains. Near full
-- screen (1400 x 820, scaled down to fit a smaller screen), movable, Escape closes it. On top a search
-- across all zones and two filters (all levels, show what isn't for me; by default only what's
-- within my levels, Q.InRange); under it the zones on the left (by continent, each with its level
-- range, how many of its quests I've done and a thin bar, dimmed when it's far from my level; then
-- the dungeons), the quest picked on the right, and in the middle a tab bar: the zone page, the quest
-- list, and every view another file registers (Q.RegisterBrowserView: built the first time it's
-- shown). Each surface shows what to do now and how far along; the rest is in tooltips.
--   * The zone page: the zone's map (its art, a pin per quest giver with how many quests it has, the
--     game's icons: available "!", a low level one's, a grey "!" for later ones, "?" ready to turn in,
--     a grey "?" still in progress, repeatable ones blue; where items that start a quest drop; each
--     pin's tooltip says what it is) beside the zone's chains as cards (the chain's own colour, how
--     far along with a bar, what's next and who gives it; levels, what it opens and friends in its
--     tooltip; the done chains folded at the end). Each chain has a colour of its own (from its first
--     quest's ID), drawn on the map as a thin thread from giver to turn-in to the next giver while its
--     card is hovered or it has the quest picked. Hovering a card lights its pins (the rest dim),
--     hovering a pin lights its chains' cards. Under the map: how many quests are in progress, ready
--     to turn in and available, and when nothing is there to take, a zone that has some.
--   * A chain opened (a click on its card, or any quest): its quests (every level) as cards from top
--     to bottom, a row per stage (how many quests come before it), side by side where it forks; lines
--     in the gaps (their own lane each, so lines that aren't joined never look joined), "one of" where
--     any one of several is enough, dashed lines for a lead-in that isn't needed first, the steps in
--     another zone as stubs with the zone's name (a click goes there). A locked quest picked: the way
--     back to it (Q.Missing) lit and numbered, across zones (the stubs light up), the rest dim. The
--     next step pulses once when the chain opens.
--   * The quest list: the zone's quests grouped: in progress, available now, coming up (level),
--     blocked (needs another first), completed (with the skipped ones), not for you (with its filter).
--   * The details: the quest's title in its difficulty colour, its status with the reason, its chain
--     step, where it starts (or, in my log, where it's turned in; an item: its best drop; a click puts
--     a map pin there), the small map when the zone's isn't in sight, requirements not met, the first
--     quest it needs and what it leads to (buttons to those quests), friends, and a button that shows
--     it in the small window (Q.ShowQuest).
-- A search (Q.Search: titles and giver names, across all zones) shows its results in the middle; a
-- click on a result or a zone goes there with "Back to the search results" on top, and the search
-- stays until the box is emptied. A click on a quest also shows it in the small window while that's
-- open (Q.IsSmallShown).
--
-- What it costs: built when first opened; the data addon loads then too (Q.Load), never at login.
-- A zone's chains are worked out once (Q.Chain, Q.Opens) and kept until the data changes; a chain's
-- cards, a zone's pins and threads when the filters or a status change. The chain's canvas has only
-- the cards and lines near sight (pooled, each card kept on its quest while it stays near, so a
-- controller's cursor stays on it); the lists (zones, chain cards, overview, results) only their
-- rows in sight. Hovering only sets the alpha of what's there. Events (QUEST_TURNED_IN,
-- QUEST_ACCEPTED, QUEST_REMOVED, PLAYER_LEVEL_UP, QUEST_DATA_LOAD_RESULT, QUEST_LOG_UPDATE) only while
-- it's open; they note what changed and the redraw comes on the next frame, at most every half
-- second. Closed, nothing runs. Our own frames only, nothing protected (it opens in a fight), no
-- Blizzard menu (gamepad mode), every card, pin, row, tab and filter a plain Button the controller's
-- navigation reaches; a card or pin the cursor moves to out of sight brings itself into view.

local WIDTH, HEIGHT = 1400, 820
local SCREEN_W, SCREEN_H = 40, 80 -- kept free around it on a small screen
local INSET_W, INSET_H = 10, 86   -- how much smaller than the window the template's Inset is
local PAD, GAP, EDGE = 6, 8, 10
local ZONES_W, DETAILS_W = 240, 330 -- (each with its scroll bar)
local BAR_W = 24
local ROW_H = 20
local TABS_H, HEAD_H, LEGEND_H = 28, 44, 22
local BEYOND = 2                  -- list rows laid beyond sight, above and below (the controller's next one)
local LINK_H = 18
local SHOWN = { needs = 1, leads = 3, friends = 3, others = 3, points = 20, threads = 500, dots = 5, chainFriends = 60 }
local SEARCH_GAP, REFRESH_GAP, NAMES_GAP, READY_GAP = 0.3, 0.5, 0.2, 1
local GOLD, GREY, SEP = "|cffffd200", "|cff888888", " · "
local EMPTY = {}

-- The zone page: the map (3:2) on the left, the chains' cards on the right (8 px grid).
local Z = { MAP_W = 432, CARD_H = 48, CARD_GAP = 8, DIM = 0.4, PIN_DIM = 0.3, BAR = 56 }
Z.MAP_H = Z.MAP_W * 2 / 3

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
	turn = {},        -- a map marker clicked again: its next quest
	dataOld = false, statusOld = false, nextRefresh = 0, searchAt = nil, namesAt = nil, readyAt = nil, ready = nil,
	listening = false,
	draws = 0, trees_built = 0, layouts_built = 0, -- (for the tests)
}
-- Views other files add as tabs (Q.RegisterBrowserView): key -> { key, label, build, built, holder }.
local registry = { order = {}, byKey = {}, current = nil }
local Graph, Map, Overview, Details, Chains, ZonePage, Views, Head, Tabs, Path, Make, Rule = {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}

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

-- Within my levels (Q.InRange: in my log, or neither grey for me nor too far above), as the zone page
-- and the quest list show them unless all levels are asked for; done and skipped ones always are.
function Rule.InLevels(id, status)
	if filters.allLevels or status == "done" or Rule.Skipped(id, status) or not Q.InRange then
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
-- threads of ours
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
	if m.onClick and self.quests[1] then
		local turn = ((state.turn[self.key] or 0) % #self.quests) + 1
		GameTooltip:AddLine(L["Click: show %s"]:format(Title(self.quests[turn])), 0.5, 0.75, 1)
	end
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
	local m = { markers = {}, used = 0, shown = 0, width = width, height = height, zoom = 1, ox = 0, oy = 0, zoomable = zoomable,
		lines = {}, linesShown = 0 }
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
	Map.Show(m, m.map, m.spots, m.name, m.threads)
	Map.Pan(m, m.width / 2 - fx * m.artW, m.height / 2 - fy * m.artH)
	if m.onZoom then
		m.onZoom(zoom)
	end
end

-- The map's art, the markers and the threads on it. spots = { { x, y, look, label, quest, status,
-- note, chain } }: spots closer than a few px are one marker (its tooltip lists them all; its look the
-- first by LOOK's order; how many quests to do it has in a badge); a drop area only with drop areas.
-- threads = { { key, color, segs = { { x1, y1, x2, y2, done } } } } (0..1 on the map): a chain's
-- line from giver to turn-in to the next giver.
function Map.Show(m, map, spots, name, threads)
	local same = m.map == map
	m.map, m.spots, m.name, m.threads = map, spots, name, threads
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
				marker.px, marker.py, marker.look, marker.drop = px, py, spot.look, drop
				marker.area = tonumber(spot.r) and drop and math.floor(spot.r * width * 2 + 0.5) or nil
				marker.spots = { spot }
				marker.key = ("%s:%d:%d"):format(tostring(map), math.floor(x * 1000), math.floor(y * 1000))
				marker:ClearAllPoints()
				marker:SetPoint("CENTER", m.Map, "TOPLEFT", px, -py)
			end
		end
	end
	-- Each marker's quests, the one to do first first (a click shows it; the next click the next one),
	-- how many of them are still to do, its chains.
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

-- One chain lit (a card hovered: its pins and thread, the rest dim), or none (nil). A thread shows
-- only for the chain lit, else for the one with the quest picked (m.keep); the others are hidden.
function Map.Light(m, key)
	m.lit = key
	local show = key or m.keep
	for i = 1, m.linesShown do
		local line = m.lines[i]
		local c = line.color
		if show ~= nil and line.key == show then
			local a, w = 1, 3.5
			if key == nil then
				a, w = line.done and 0.25 or 0.7, 2
			end
			line:SetThickness(w)
			line:SetColorTexture(c[1], c[2], c[3], a)
			line:Show()
		else
			line:Hide()
		end
	end
	for i = 1, m.shown do
		local marker = m.markers[i]
		marker:SetAlpha((key == nil or marker.chains[key]) and 1 or Z.PIN_DIM)
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

-- The first spot on this map of a list of givers or enders.
local function FirstOn(list, map)
	for _, s in ipairs(list or EMPTY) do
		for _, p in ipairs(s.points or EMPTY) do
			if p.map == map then
				return p
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

function ZonePage.DrawMap(place)
	local zp = view.zp
	if not place or place.kind ~= "zone" then
		zp.map.frame:Hide()
		zp.Note:SetText(place and L["Dungeon quests are given in many places: each quest's details show where."] or "")
		zp.Note:Show()
		return
	end
	zp.Note:Hide()
	local spots, threads = ZonePage.Spots(place)
	ZonePage.Keep(place)
	Map.Show(zp.map, place.map, spots, place.name, threads)
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

-- A zone (my level, give or take 3) with the most quests I can take now, for when this one has none.
function ZonePage.Suggest(place)
	if state.suggest ~= nil and state.suggestFor == place.id then
		return state.suggest or nil
	end
	local my = tonumber(UnitLevel and LT.Value(UnitLevel, "player")) or 1
	local best, most = nil, 0
	for _, z in ipairs(state.zones or EMPTY) do
		if z.map ~= place.map and (z.minLevel or 1) <= my + 3 and (z.maxLevel or 60) >= my - 3 then
			local n = 0
			if Q.Available then
				local ok, list = pcall(Q.Available, z.map)
				n = ok and type(list) == "table" and #list or 0
			else
				for _, id in ipairs(Q.ZoneQuests and Q.ZoneQuests(z.map) or EMPTY) do
					n = n + (StatusOf(id) == "available" and 1 or 0)
				end
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

-- Under the map, one line: what of in progress, ready to turn in and available (within my levels as
-- the pins) there is (the head has how far along); with none to take here, a zone that has some.
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
	for _, p in ipairs({ { n.active, HEX.active, L["%d in progress"] }, { n.ready, GOLD, L["%d ready to turn in"] },
		{ n.available, HEX.available, L["%d available"] } }) do
		if p[1] > 0 then
			parts[#parts + 1] = p[2] .. p[3]:format(p[1]) .. "|r"
		end
	end
	zp.Counts:SetText(table.concat(parts, GREY .. SEP .. "|r"))
	local suggest = place and (n.available or 0) == 0 and ZonePage.Suggest(place) or nil
	zp.Guide:SetShown(place ~= nil and (n.available or 0) == 0)
	zp.Guide:SetText(L["Nothing for you to pick up here right now."])
	zp.Suggest.map = suggest and suggest.map or nil
	if suggest then
		zp.Suggest.Text:SetText(L["%s has %d for your level"]:format(suggest.name, suggest.n) .. "  >")
		zp.Suggest:SetWidth(zp.Suggest.Text:GetStringWidth() + 12)
	end
	zp.Suggest:SetShown(suggest ~= nil)
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

-- keep: the cards stay where they're scrolled.
function ZonePage.Draw(place, keep)
	local zp = view.zp
	zp.lit = nil
	local entries, chains = {}, 0
	if place then
		entries, chains = ZonePage.Entries(place)
	end
	zp.cards:SetEntries(entries, keep and true or 0)
	local message
	if place and not entries[1] then
		message = Structure(place).ids[1] and L["Nothing to show with these filters."] or L["No quests known here yet."]
	end
	zp.Empty:SetText(message or "")
	zp.Empty:SetShown(message ~= nil)
	ZonePage.DrawMap(place)
	return ZonePage.DrawSummary(place), chains
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

-- Pins hovered: their chains' cards lit (set: chain keys; nil: none); none of them in sight: the
-- list goes to the first.
function ZonePage.LightCards(set)
	local zp = view.zp
	zp.lit = set and next(set) and set or nil
	local list = zp.cards
	local seen = false
	for _, row in pairs(list.rows) do
		if row.entry then
			ZonePage.PaintCard(row)
			seen = seen or (zp.lit ~= nil and zp.lit[row.entry.key] == true and list:InSight(row.index))
		end
	end
	if zp.lit and not seen then
		for i, e in ipairs(list.entries) do
			if zp.lit[e.key] then
				list:ScrollTo(i)
				break
			end
		end
	end
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
	Tabs.Paint()
end

-- The head over a page: (a way back,) the chain's colour, the title, a line under it, how far along.
function Head.Set(back, color, title, sub, countText, done, total)
	local h = view.head
	local x = 0
	h.Back:SetShown(back ~= nil)
	if back then
		h.Back.Text:SetText(back)
		h.Back:SetWidth(h.Back.Text:GetStringWidth() + 24)
		x = h.Back:GetWidth() + 8
	end
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
	Head.Set(place.name, Chains.Color(group), Chains.Name(group), sub, L["%d of %d steps done"]:format(info.done, info.total), info.done, info.total)
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
	Head.Set(nil, nil, place.name, GREY .. table.concat(parts, SEP) .. "|r", L["%d of %d done"]:format(done, total), done, total)
end

-- keep: the page stays where it's scrolled; focus: a quest to bring into sight.
local function DrawMiddle(keep, focus)
	state.draws = state.draws + 1
	local mode = Mode()
	local place = CurrentPlace()
	local v = registry.byKey[mode]
	local group = mode == "zone" and state.chain and place and Structure(place).byKey[state.chain] or nil
	if not group then
		state.chain = nil
	end
	view.zp:SetShown(mode == "zone" and group == nil)
	view.g.frame:SetShown(group ~= nil)
	view.list.scroll:SetShown(mode == "results" or mode == "overview")
	view.Back:SetShown(state.query ~= "" and state.drilled)
	view.head:SetShown(v == nil)
	view.Legend:SetShown(group ~= nil and not group.single) -- (a chain's lines; the statuses say their reason themselves)
	view.Zoom:SetShown(mode == "zone" and (group ~= nil or (place ~= nil and place.kind == "zone")))
	Views.Show(v)
	Tabs.Paint()
	local message
	if v then
		message = nil
	elseif mode == "results" then
		Head.Set(nil, nil, L["Search results"], state.results and GREY .. L["%d quests"]:format(#state.results) .. "|r" or "")
		if #state.query < 2 and not tonumber(state.query) then
			view.list:SetEntries({}, 0)
			message = L["Type at least two letters."]
		else
			view.list:SetEntries(SearchEntries(), keep and true or 0)
			message = not state.results[1] and L["Nothing found"] or nil
		end
	elseif group then
		message = DrawChain(place, group, keep, focus)
	elseif mode == "zone" then
		if place then
			local n, chains = ZonePage.Draw(place, keep)
			HeadZone(place, L["%d to pick up now"]:format(n.available or 0) .. SEP .. L["%d chains"]:format(chains))
		else
			ZonePage.Draw(nil)
			Head.Set(nil, nil, "", "")
		end
		view.ZoomText:SetText(("%d%%"):format(math.floor(view.zp.map.zoom * 100 + 0.5)))
	else
		if place then
			HeadZone(place)
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
	Details.Sight()
end

function Graph.Open(focus)
	DrawMiddle(false, focus)
end

local function FillListRow(row, e)
	local header = e.header == true
	row.Toggle:SetShown(header and not e.search)
	row.Band:SetShown(header)
	row.Icon:SetShown(not header and not e.more)
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

-- The status with its reason (a skipped one: what I took instead), its tags; the chain's step.
function Details.Summary(q, status)
	local line = HEX[status] .. Rule.Reason(q.id, status) .. "|r"
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
	local lines = { line }
	local step, total, name = StepOf(q.id)
	if step then
		lines[#lines + 1] = L["Step %d of %d"]:format(step, total) .. (name and (GREY .. SEP .. name .. "|r") or "")
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

-- Where a quest starts, as one line (a button: it puts a map pin there): the giver and its zone; an
-- item: its best drop (what drops it most often); in my log: where it's turned in instead. The rest
-- (other givers, drops, enders) in its tooltip (tip: its lines).
function Details.PlaceLine(q, status)
	local ends = status == "active" and q.ends and q.ends[1] ~= nil
	local s = (ends and q.ends or q.starts or EMPTY)[1]
	if not s then
		return nil
	end
	local line = { kind = ends and "end" or "start", tip = {} }
	local best
	for _, d in ipairs(not ends and s.kind == "item" and s.drops or EMPTY) do
		if not best or (tonumber(d.chance) or 0) > (tonumber(best.chance) or 0) then
			best = d
		end
	end
	if best then
		line.kind, line.point, line.name = "drop", best.points and best.points[1], best.name
		line.text = StartWord(s) .. GREY .. SEP .. "|r" .. WhereText(best, true)
	else
		line.point, line.name, line.text = s.points and s.points[1], s.name, WhereText(s)
	end
	local tip = line.tip
	local function Section(head, list, skip, drop)
		local n, total = 0, #(list or EMPTY) - (skip and 1 or 0)
		for _, o in ipairs(list or EMPTY) do
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
	if ends then
		Section(L["Turn in at"], q.ends, s)
		Section(L["Starts at"], q.starts)
	else
		Section(L["Starts at"], q.starts, s)
		Section(L["Turn in at"], q.ends)
	end
	return line
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
	b.Text:SetText(LevelTag(q) .. Hex(c[1], c[2], c[3]) .. Title(id) .. "|r" .. (other and (GREY .. SEP .. zone .. "|r") or ""))
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

-- Where it starts (or is turned in), one line.
function Details.PutPlace(q, status, y)
	local b = view.d.place
	local line = Details.PlaceLine(q, status)
	if not line then
		b.point, b.tip = nil, nil
		b:Hide()
		return y
	end
	b.point, b.name, b.tip = line.point, line.name, line.tip
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
	return y + LINK_H + 8
end

-- The small map, only when the zone page's map isn't in sight (it shows the same).
function Details.PutMap(q, y)
	local d = view.d
	local map, spots
	if d.mapWanted then
		map, spots = Details.MapSpots(q)
	end
	if not (map and spots[1]) then
		d.map.frame:Hide()
		return y
	end
	d.map.frame:ClearAllPoints()
	d.map.frame:SetPoint("TOPLEFT", 0, -y)
	Map.Show(d.map, map, spots)
	return y + d.map.height + 10
end

-- top: a new quest, shown from its top (else a refresh keeps the place). The title, the status with
-- its reason and the chain's step, where it starts, the small map, requirements not met, the first
-- quest it needs, what it leads to (three), friends (three).
local function FillDetails(top)
	local d = view.d
	local id = state.picked
	local q = Quest(id)
	d.mapWanted = not view.zp:IsShown()
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
	y = Details.PutPlace(q, status, y)
	y = Details.PutMap(q, y)
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
	if top then
		d.Scroll:SetVerticalScroll(0)
	end
end

-- The page changed: the details again when the small map comes into question or goes (the zone
-- page's map in sight or not).
function Details.Sight()
	local d = view.d
	if d.Body:IsShown() and d.mapWanted ~= not view.zp:IsShown() then
		FillDetails()
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
		ZonePage.Keep(CurrentPlace()) -- (its chain's thread)
		Map.Repaint(view.zp.map)
		view.zp.cards:Lay()
	end
	FillDetails(changed)
	if user and Q.ShowQuest and SmallOpen() then
		Q.ShowQuest(id)
	end
end

function Graph.Pick(id)
	Pick(id, true)
end

-- A place on the left: its zone page (or its overview), the search staying.
local function SelectPlace(id)
	if state.query ~= "" then
		state.drilled = true
	end
	state.where = id
	state.chain, state.path = nil, nil
	if state.tab ~= "zone" and state.tab ~= "overview" then
		state.tab = "zone"
		Save()
	end
	view.zones:Lay()
	DrawMiddle(false)
	if view.d.Body:IsShown() then
		FillDetails() -- (its links say which zone they're in)
	end
end

-- A quest anywhere: its zone (or dungeon) on the left, its chain opened with its card in sight (the
-- overview stays the overview), the details.
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
	end
	if state.tab ~= "overview" then
		state.tab = "zone"
		local place = CurrentPlace()
		local group = place and Structure(place).groupOf[id]
		state.chain = group and group.key or nil
		Save()
	end
	state.picked, state.path = nil, nil
	if moved then
		DrawZones(true, target)
	else
		view.zones:Lay()
	end
	DrawMiddle(not moved, id)
	Pick(id, user)
end

-- A stub clicked: that step in its own zone.
function Graph.Jump(id)
	Open(id, true)
end

local function BackToResults()
	state.drilled = false
	DrawMiddle(false)
end

-- From a chain back to its zone's page.
local function BackToZone()
	state.chain, state.path = nil, nil
	DrawMiddle(true)
end

function Tabs.Set(tab)
	if state.query ~= "" and not state.drilled then
		state.drilled = true -- (a tab clicked during a search: the place, the search stays)
	end
	if tab == "zone" and state.tab == "zone" then
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

-- The zone page's "Completed (N)" fold clicked, or the line saying what the level filter left out.
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
		state.statusOld, state.readyAt = false, nil
		state.nextRefresh = now + REFRESH_GAP
		Restatus() -- (statuses changed: what the filters show, the lines' colours, the pins)
		view.zones:Lay()
		DrawMiddle(true)
		FillDetails()
	end
	if state.readyAt and now >= state.readyAt then
		state.readyAt = nil
		-- (objectives done: a "?" may turn yellow; only the zone's pins and the line under them are drawn
		-- again, and only then)
		local place = CurrentPlace()
		local key = view.zp:IsShown() and ZonePage.ReadyKey(place) or nil
		if key and key ~= state.ready then
			state.ready = key
			state.spots[place.id] = nil
			ZonePage.DrawMap(place)
			ZonePage.DrawSummary(place)
		end
	end
	if state.namesAt and now >= state.namesAt then
		state.namesAt = nil
		if view.g.frame:IsShown() then
			Graph.Refill()
		end
		if view.list.scroll:IsShown() then
			view.list:Lay()
		end
		if view.zp:IsShown() then
			view.zp.cards:Lay()
		end
		FillDetails()
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

local EVENTS = { "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_LEVEL_UP", "QUEST_DATA_LOAD_RESULT", "QUEST_LOG_UPDATE" }

local function OnEvent(_, event, id)
	if event == "QUEST_DATA_LOAD_RESULT" then
		if LT.IsSecret(id) or not state.waiting[id] then
			return
		end
		state.waiting[id] = nil
		state.namesAt = state.namesAt or GetTime() + NAMES_GAP
	elseif event == "QUEST_LOG_UPDATE" then
		if state.readyAt or not view.zp:IsShown() then
			return -- (often, and only the zone page's pins can change: looked at once a second at most)
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
		QuestTip(self, e.quest)
	end
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

-- Where it starts: the spot, the other givers, drops and enders, what a click does.
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

function Make.BuildDetails(root, x, y, width, height)
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
	d.ReqHead, d.NeedsHead = Make.NewHead(d.Body, bodyW - 4), Make.NewHead(d.Body, bodyW - 4)
	d.LeadsHead, d.FriendsHead = Make.NewHead(d.Body, bodyW - 4), Make.NewHead(d.Body, bodyW - 4)
	d.map = Map.New(d.Body, bodyW - 4, math.floor((bodyW - 4) * 2 / 3), false)
	function d.Link(i)
		local b = d.links[i]
		if not b then
			b = Make.NewLink(d.Body, bodyW - 4)
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
	-- Where it starts (or is turned in): one line, a click puts a map pin there.
	d.place = Make.NewLink(d.Body, bodyW - 4)
	d.place:SetScript("OnEnter", Make.PlaceTip)
	d.place:SetScript("OnLeave", Untip)
	d.place:SetScript("OnClick", function(self)
		if self.point then
			SetPin(self.point.map, self.point.x, self.point.y, self.name)
		end
	end)
	d.places[1] = d.place
	d.Small = LT.Window.AddButton(panel, L["Show in the small window"], function()
		if state.picked and Q.ShowQuest then
			Q.ShowQuest(state.picked)
		end
	end, { "BOTTOMLEFT", panel, "BOTTOMLEFT", 2, 4 })
	d.Small:SetSize(math.min(width - 4, 220), 22)
	d.Small:Hide()
	d.Body:Hide()
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

-- -, the zoom, +, Fit: a chain's zoom, or the zone map's.
function Make.BuildZoom(parent)
	local z = CreateFrame("Frame", nil, parent)
	z:SetSize(170, 24)
	view.Zoom = z
	local function OnMap()
		return view.zp:IsShown()
	end
	local function Step(dir)
		if OnMap() then
			local m = view.zp.map
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
		if OnMap() then
			Map.SetZoom(view.zp.map, 1)
			view.ZoomText:SetText("100%")
		else
			Graph.Fit()
		end
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

-- The zone page: the map on the left with what's here under it, the chains' cards on the right.
function Make.BuildZonePage(parent, x, y, w, h)
	local zp = CreateFrame("Frame", nil, parent)
	zp:SetPoint("TOPLEFT", x, -y)
	zp:SetSize(w, h)
	view.zp = zp
	zp.map = Map.New(zp, Z.MAP_W, Z.MAP_H, true)
	zp.map.frame:SetPoint("TOPLEFT")
	zp.map.onClick = function(id)
		Pick(id, true)
	end
	zp.map.onZoom = function(zoom)
		view.ZoomText:SetText(("%d%%"):format(math.floor(zoom * 100 + 0.5)))
	end
	zp.map.onEnter = function(marker)
		ZonePage.LightCards(marker.chains)
	end
	zp.map.onLeave = function()
		ZonePage.LightCards(nil)
	end
	zp.map.noteOf = ZonePage.PinNote -- (what each pin is, in its tooltip)
	zp.Note = zp:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	zp.Note:SetPoint("TOPLEFT", 8, -8)
	zp.Note:SetWidth(Z.MAP_W - 16)
	zp.Note:SetJustifyH("LEFT")
	zp.Note:Hide()
	local below = Z.MAP_H + 16
	zp.Counts = zp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	zp.Counts:SetPoint("TOPLEFT", 4, -below)
	zp.Counts:SetWidth(Z.MAP_W - 8)
	zp.Counts:SetJustifyH("LEFT")
	zp.Guide = zp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	zp.Guide:SetPoint("TOPLEFT", 4, -(below + 24))
	zp.Guide:SetWidth(Z.MAP_W - 8)
	zp.Guide:SetJustifyH("LEFT")
	zp.Guide:Hide()
	zp.Suggest = CreateFrame("Button", nil, zp)
	zp.Suggest:SetSize(200, 22)
	zp.Suggest:SetPoint("TOPLEFT", 0, -(below + 44))
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
	-- The cards' column: a darker panel, the cards (a pooled list).
	local cx = Z.MAP_W + GAP
	local cw = w - cx
	local panel = zp:CreateTexture(nil, "BACKGROUND")
	panel:SetPoint("TOPLEFT", cx, 0)
	panel:SetSize(cw, h)
	panel:SetColorTexture(0, 0, 0, 0.25)
	zp.cards = NewList(zp, cx + 4, 4, cw - BAR_W - 4, h - 8, ZonePage.NewCard, ZonePage.FillCard, Z.CARD_H + Z.CARD_GAP)
	zp.Empty = zp:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	zp.Empty:SetPoint("TOPLEFT", cx + 12, -14)
	zp.Empty:SetWidth(cw - 24)
	zp.Empty:SetJustifyH("LEFT")
	zp.Empty:Hide()
	zp:Hide()
end

-- The head over a page: a way back (a chain's page), the title, a line under it, how far along with
-- a bar; the zoom at its right.
function Make.BuildHead(root, x, y, w)
	local h = CreateFrame("Frame", nil, root)
	h:SetPoint("TOPLEFT", x, -y)
	h:SetSize(w, HEAD_H)
	view.head = h
	h.Back = CreateFrame("Button", nil, h)
	h.Back:SetSize(120, 22)
	h.Back:SetPoint("TOPLEFT", 0, -1)
	h.Back.Icon = h.Back:CreateTexture(nil, "ARTWORK")
	h.Back.Icon:SetTexture(T.back)
	h.Back.Icon:SetSize(18, 18)
	h.Back.Icon:SetPoint("LEFT")
	h.Back.Text = h.Back:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	h.Back.Text:SetPoint("LEFT", 20, 0)
	h.Back:SetHighlightTexture(T.highlight, "ADD")
	h.Back:SetScript("OnClick", BackToZone)
	h.Back:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(L["Back to the zone's map and chains"], 1, 1, 1)
		GameTooltip:Show()
	end)
	h.Back:SetScript("OnLeave", Untip)
	h.Back:Hide()
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

-- The tab bar (the zone page, the overview, the views registered) and the way back to the results.
function Make.BuildTabs(root, x, y, w)
	local bar = CreateFrame("Frame", nil, root)
	bar:SetPoint("TOPLEFT", x, -y)
	bar:SetSize(w, TABS_H)
	view.tabBar, view.tabs = bar, {}
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
	view.Box:ClearFocus()
	Views.Show(nil) -- (a view registered: its OnHide)
	GameTooltip:Hide()
end

local function Build()
	frame = LT.Window.Create("LefthyToolsQuesttreeBrowser", "Questtree", WIDTH, HEIGHT)
	view = { registry = registry }
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
	Make.BuildZonePage(root, middleX, contentY, middleW, contentH)
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
	local m = LT:GetModule("questtree")
	if m and not m.enabled then
		LT.Print("Questtree is switched off (/lefthy enable questtree).")
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
