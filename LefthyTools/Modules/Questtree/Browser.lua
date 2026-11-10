local _, ns = ...
local LT = ns.LT
local L = ns.L
local Q = ns.Questtree or {}
ns.Questtree = Q

-- Questtree's big window (Q.ToggleBrowser, Q.OpenBrowser(id)): every zone's quest chains. Near full
-- screen (1200 x 760, scaled down to fit a smaller screen), movable, Escape closes it. On top a search
-- across all zones and a legend of the status colours; under it three panes:
--   * left: the zones by continent (each continent folds), each with its level range and how many of
--     its quests I've done ("12 of 40": quests that aren't for me, another race, class or faction,
--     aren't counted), then the dungeons;
--   * middle: the selected zone's chains as a tree. A chain is a group (its first quest's title, done of
--     total, folds); its quests are rows in the order they're done: a quest that leads to one other
--     keeps that one in its own column under it, one that leads to several has them one column further
--     in, with a line from it to each (like a file tree). A quest needing two earlier ones is drawn
--     once, under the first. Quests of the chain in another zone say which. Quests without a chain are
--     listed in a group of their own at the end. Each row in its status's colour (Q.Status): done
--     green, in my log yellow, available white, locked grey with a lock, my level too low orange, not
--     for me dim;
--   * right: the quest clicked: its title (the client's, when it knows it), status, level, what it
--     needs (race, class, faction, skill, reputation), who gives it and where to turn it in, the small
--     map (Q.NewMiniMap, when there is one), "Needs first" (Q.Missing, across zones) and "Leads to"
--     (Q.Opens), each a button that goes to that quest, friends' progress (Q.Friends) and a button that
--     shows it in the small window (Q.ShowQuest).
-- A search (Q.Search: titles and giver names, across all zones) shows its results in the middle; a
-- click on a result or a zone goes to that quest's or zone's tree with "Back to the search results"
-- on top, and the search stays until the box is emptied. A click on a quest also shows it in the small
-- window while that's open (Q.IsSmallShown).
--
-- What it costs: built when first opened; the data addon loads then too (Q.Load), never at login. Both
-- lists are pools of the rows in sight (and a few beyond them, so a controller's cursor finds the next
-- one), each row kept on its entry while scrolling. A zone's tree is worked out once (Q.Chain, Q.Opens)
-- and kept until the data changes (Q.OnDataChanged); statuses are read for the rows in sight and the
-- open zone's groups, a zone's count once until a quest of it is turned in. Events (QUEST_TURNED_IN,
-- QUEST_ACCEPTED, QUEST_REMOVED, PLAYER_LEVEL_UP, QUEST_DATA_LOAD_RESULT) are listened to only while it's
-- open, they only note what changed, and the redraw comes on the next frame, at most every half second.
-- Closed, nothing runs. Our own frames only, nothing protected (it opens in a fight), no Blizzard menu
-- (gamepad mode), every row and link a plain Button the controller's navigation can reach.

local WIDTH, HEIGHT = 1200, 760
local SCREEN_W, SCREEN_H = 40, 80 -- kept free around it on a small screen
local INSET_W, INSET_H = 10, 86   -- how much smaller than the window the template's Inset is
local PAD, GAP, EDGE = 6, 8, 10
local ZONES_W, MIDDLE_W = 270, 500 -- (each with its scroll bar)
local BAR_W = 24
local ROW_H = 20
local HEAD_H = 26                 -- the middle's title, above the tree
local INDENT = 14                 -- a column of the tree
local MAX_DEPTH = 10              -- deeper branches stay in the last column
local BEYOND = 2                  -- rows laid beyond sight, above and below (the controller's next one)
local LINK_H = 18
local LINKS_SHOWN = 12            -- per section of the details; more: "... and N more"
local FRIENDS_SHOWN = 12
local PLACES_SHOWN = 3            -- givers or enders named
local POINTS_SHOWN = 20           -- per kind on the small map
local SEARCH_GAP = 0.3            -- typing: searched this long after the last key
local REFRESH_GAP = 0.5           -- quest events: redrawn at most this often
local NAMES_GAP = 0.2             -- titles coming in: one fill for a bunch
local GOLD, GREY = "|cffffd200", "|cff888888"
local DOT = "\226\128\162"
local LOCK = "Interface\\LFGFrame\\UI-LFG-ICON-LOCK"
local PLUS, MINUS = "Interface\\Buttons\\UI-PlusButton-Up", "Interface\\Buttons\\UI-MinusButton-Up"
local BACK = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up"
local HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local EMPTY = {}

local STATUS = {
	done = { 0.3, 0.85, 0.3 }, active = { 1, 0.85, 0.1 }, available = { 1, 1, 1 },
	locked = { 0.6, 0.6, 0.6 }, level = { 1, 0.55, 0.2 }, other = { 0.42, 0.42, 0.42 },
}
local STATUS_ORDER = { "done", "active", "available", "locked", "level", "other" }
local STATUS_HEX = {}
for key, c in pairs(STATUS) do
	STATUS_HEX[key] = ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- Classic's races and classes by ID (a quest's masks: bit ID - 1); the game's names when it has them.
local RACES = { "Human", "Orc", "Dwarf", "Night Elf", "Undead", "Tauren", "Gnome", "Troll" }
local CLASSES = { [1] = "WARRIOR", [2] = "PALADIN", [3] = "HUNTER", [4] = "ROGUE", [5] = "PRIEST", [7] = "SHAMAN", [8] = "MAGE",
	[9] = "WARLOCK", [11] = "DRUID" }
local SKILLS = { [129] = "First Aid", [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy", [182] = "Herbalism",
	[185] = "Cooking", [186] = "Mining", [197] = "Tailoring", [202] = "Engineering", [333] = "Enchanting", [356] = "Fishing", [393] = "Skinning" }
local STANDINGS = { { -42000, "Hated" }, { -6000, "Hostile" }, { -3000, "Unfriendly" }, { 0, "Neutral" }, { 3000, "Friendly" },
	{ 9000, "Honored" }, { 21000, "Revered" }, { 42000, "Exalted" } }

local frame, view
local state = {
	where = nil,      -- the place shown: "z:<uiMapID>" or "d:<dungeon>"
	picked = nil,     -- the quest in the details
	query = "",       -- the search shown
	results = nil,    -- its quest IDs
	drilled = false,  -- a zone or quest clicked during a search: its tree shows, the search stays
	folded = {},      -- group or continent key -> true
	counts = {},      -- place -> { done, total }
	trees = {},       -- place -> its tree
	zones = nil,      -- Q.Zones(), Q.Dungeons() as of the last build, and the places made of them
	places = nil,
	asked = {}, waiting = {}, -- titles asked of the client (QUEST_DATA_LOAD_RESULT)
	dataOld = false, statusOld = false, nextRefresh = 0, searchAt = nil, namesAt = nil,
	listening = false,
	draws = 0, trees_built = 0, -- (for the tests)
}

---------------------------------------------------------------------------
-- What's shown of a quest
---------------------------------------------------------------------------

local function Quest(id)
	return id and Q.Quest and Q.Quest(id) or nil
end

local function StatusOf(id)
	local status = Q.Status and Q.Status(id)
	return STATUS[status] and status or "other"
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

-- The client's title, when it knows the quest (asked once, it may come later); else the data's.
local function Ask(id)
	if state.asked[id] or not (C_QuestLog and C_QuestLog.RequestLoadQuestByID) then
		return
	end
	state.asked[id], state.waiting[id] = true, true
	pcall(C_QuestLog.RequestLoadQuestByID, id)
end

local function Title(id)
	local title = C_QuestLog and LT.Value(C_QuestLog.GetTitleForQuestID, id)
	if type(title) == "string" and title ~= "" then
		return title
	end
	Ask(id)
	local q = Quest(id)
	return q and q.title or ("#" .. tostring(id))
end

local function LevelTag(q)
	return (q and q.level and q.level > 0) and ("[" .. q.level .. "] ") or ""
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

---------------------------------------------------------------------------
-- Places: zones and dungeons, their counts and trees
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

-- How many of a place's quests are done, of those for me.
local function CountOf(place)
	local c = state.counts[place.id]
	if not c then
		local done, total = 0, 0
		for _, id in ipairs(QuestsOf(place)) do
			local status = StatusOf(id)
			if status ~= "other" then
				total = total + 1
				if status == "done" then
					done = done + 1
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

-- A vertical line in a tree row's column: 1 the top half, 2 the bottom half, 3 both.
local function Rail(row, col, bits)
	local rails = row.rails
	if not rails then
		rails = {}
		row.rails = rails
	end
	local old = rails[col]
	rails[col] = (old == nil or old == bits) and bits or 3
end

-- The line from a row down to a later one, in the parent's column.
local function Link(rows, from, to, col)
	Rail(rows[from], col, 2)
	for k = from + 1, to - 1 do
		Rail(rows[k], col, 3)
	end
	Rail(rows[to], col, 1)
end

-- A chain's rows in the order they're done. Who leads to whom: each quest's pre, preAny and preActive
-- and what Q.Opens says, inside the chain; the first quests are those nothing in it leads to.
local function ChainRows(chain)
	local index, kids, led = {}, {}, {}
	for i, id in ipairs(chain) do
		index[id] = index[id] or i
	end
	local function Lead(from, to)
		if from == to or not (from and to and index[from] and index[to]) then
			return
		end
		local list = kids[from]
		if not list then
			list = {}
			kids[from] = list
		end
		for _, k in ipairs(list) do
			if k == to then
				return
			end
		end
		list[#list + 1] = to
		led[to] = true
	end
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
		end
		for _, o in ipairs(Q.Opens and Q.Opens(id) or EMPTY) do
			Lead(id, o)
		end
	end
	local function ByIndex(a, b)
		return index[a] < index[b]
	end
	for _, list in pairs(kids) do
		table.sort(list, ByIndex)
	end
	local rows, seen = {}, {}
	local function Visit(id, depth, parentRow, parentCol)
		if seen[id] then
			return
		end
		seen[id] = true
		local row = { quest = id, depth = depth }
		rows[#rows + 1] = row
		local me = #rows
		if parentRow then
			Link(rows, parentRow, me, parentCol)
			if parentCol < depth then
				row.stub = parentCol
			end
		end
		local open = {}
		for _, k in ipairs(kids[id] or EMPTY) do
			if not seen[k] then
				open[#open + 1] = k
			end
		end
		if #open == 1 then
			Visit(open[1], depth, me, depth) -- (the next step: the same column)
		else
			for _, k in ipairs(open) do
				Visit(k, math.min(depth + 1, MAX_DEPTH), me, depth)
			end
		end
	end
	for _, id in ipairs(chain) do
		if not led[id] then
			Visit(id, 0)
		end
	end
	for _, id in ipairs(chain) do
		Visit(id, 0) -- (a circle in the data: what's left, from the top)
	end
	return rows
end

local function LevelOf(id)
	local q = Quest(id)
	return q and q.level or 0
end

-- A place's tree: groups (a chain each, then the quests without one), worked out once.
local function BuildTree(place)
	local tree = state.trees[place.id]
	if tree then
		return tree
	end
	state.trees_built = state.trees_built + 1
	local ids = QuestsOf(place)
	local member, assigned, singles = {}, {}, {}
	tree = { groups = {}, member = member, shown = {}, groupOf = {} }
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
				local rows = ChainRows(chain)
				tree.groups[#tree.groups + 1] = { key = place.id .. ":" .. tostring(rows[1].quest), first = rows[1].quest, rows = rows,
					low = low, order = #tree.groups }
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
		local rows = {}
		for i, id in ipairs(singles) do
			rows[i] = { quest = id, depth = 0 }
		end
		tree.groups[#tree.groups + 1] = { key = place.id .. ":single", single = true, rows = rows }
	end
	for _, group in ipairs(tree.groups) do
		for _, row in ipairs(group.rows) do
			row.out = not member[row.quest]
			tree.shown[row.quest] = true
			tree.groupOf[row.quest] = tree.groupOf[row.quest] or group
		end
	end
	state.trees[place.id] = tree
	return tree
end

-- Where a quest's tree is: the place shown if it's in it, else its zone or its dungeon, the one that
-- lists it (a dungeon's quest may be given in a zone that doesn't).
local function PlaceOf(q, id)
	local current = state.where and state.places[state.where]
	if current and BuildTree(current).shown[id] then
		return current.id
	end
	local zone = q.zone and state.places["z:" .. tostring(q.zone)]
	local dungeon = q.dungeon and state.places["d:" .. tostring(q.dungeon)]
	if zone and BuildTree(zone).member[id] then
		return zone.id
	elseif dungeon and BuildTree(dungeon).member[id] then
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
	wipe(state.counts)
	state.results = nil
end

---------------------------------------------------------------------------
-- Lists: a pool of rows, each kept on its entry while it's in sight
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
	-- the controller's cursor is on keeps its quest when the list scrolls under it.
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
		self.first = math.floor(want / ROW_H) + 1 -- (laid just below, not again by the scroll's script)
		if want ~= now then
			scroll:SetVerticalScroll(want)
		end
		for _, row in pairs(self.rows) do
			row.index = nil -- (their entries are others now)
		end
		self:Lay(want)
	end

	-- An entry in the middle of sight.
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
		row.Toggle:SetTexture(e.closed and PLUS or MINUS)
		row.Name:SetText(GOLD .. e.label .. "|r")
		row.Range:SetText("")
		row.Count:SetText("")
		row.Picked:Hide()
		return
	end
	row.Name:SetText(e.name)
	row.Range:SetText(Range(e))
	local done, total = CountOf(e)
	if total == 0 then
		row.Count:SetText(GREY .. "-|r") -- (nothing here for me)
	else
		local all = done == total
		row.Count:SetText((all and STATUS_HEX.done or "") .. L["%d of %d"]:format(done, total) .. (all and "|r" or ""))
	end
	row.Picked:SetShown(e.id == state.where)
end

---------------------------------------------------------------------------
-- The middle: the tree, or the search's results
---------------------------------------------------------------------------

local function Searching()
	return state.query ~= "" and not state.drilled
end

local function TreeEntries(place)
	local tree = BuildTree(place)
	local entries = {}
	for _, group in ipairs(tree.groups) do
		local done, total = 0, 0
		for _, row in ipairs(group.rows) do
			local status = StatusOf(row.quest)
			if status ~= "other" then
				total = total + 1
				if status == "done" then
					done = done + 1
				end
			end
		end
		local closed = state.folded[group.key] == true
		entries[#entries + 1] = { header = true, key = group.key, group = group, done = done, total = total, closed = closed }
		if not closed then
			for _, row in ipairs(group.rows) do
				entries[#entries + 1] = row
			end
		end
	end
	return entries
end

local function SearchEntries()
	local entries = { { header = true, key = "search", search = true, n = #state.results } }
	for _, id in ipairs(state.results) do
		entries[#entries + 1] = { quest = id, result = true, depth = 0 }
	end
	return entries
end

local function HeadText(place)
	local done, total = CountOf(place)
	local range = Range(place)
	return GOLD .. place.name .. "|r" .. (range ~= "" and ("  " .. GREY .. L["Level %s"]:format(range) .. "|r") or "")
		.. "   " .. L["%d of %d done"]:format(done, total)
end

-- focus: a quest to scroll to.
local function DrawMiddle(offset, focus)
	state.draws = state.draws + 1
	local entries, message, head
	if Searching() then
		if #state.query < 2 and not tonumber(state.query) then
			entries, message = {}, L["Type at least two letters."]
		else
			entries = SearchEntries()
			message = not state.results[1] and L["Nothing found"] or nil
		end
		head = GOLD .. L["Search results"] .. "|r"
	else
		local place = state.where and state.places[state.where]
		entries = place and TreeEntries(place) or {}
		if place and not entries[1] then
			message = L["No quests known here yet."]
		end
		head = place and HeadText(place) or ""
		if state.query ~= "" then
			table.insert(entries, 1, { header = true, back = true, key = "back" })
		end
	end
	if focus then
		for i, e in ipairs(entries) do
			if e.quest == focus then
				offset = view.tree:Centered(i)
				break
			end
		end
	end
	view.Head:SetText(head)
	view.Message:SetText(message or "")
	view.Message:SetShown(message ~= nil)
	view.tree:SetEntries(entries, offset)
end

local function RailTexture(row, n)
	local t = row.rails[n]
	if not t then
		t = row:CreateTexture(nil, "BORDER")
		t:SetColorTexture(1, 1, 1, 0.22)
		row.rails[n] = t
	end
	return t
end

local function FillTreeRow(row, e)
	local header = e.header == true
	row.Toggle:SetShown(header and not e.search) -- (the results' header doesn't fold)
	row.Band:SetShown(header)
	for _, t in ipairs(row.rails) do
		t:Hide()
	end
	row.Stub:Hide()
	local left, right
	if header then
		row.Marker:Hide()
		row.Lock:Hide()
		row.Picked:Hide()
		row.Name:SetTextColor(1, 1, 1)
		row.Toggle:SetTexture(e.back and BACK or e.closed and PLUS or MINUS)
		if e.back then
			row.Name:SetText(GOLD .. L["Back to the search results"] .. "|r")
			row.Right:SetText("")
		elseif e.search then
			row.Name:SetText(GOLD .. L["Search results"] .. "|r")
			row.Right:SetText(tostring(e.n))
		else
			local label = e.group.single and L["Quests without a chain"] or Title(e.group.first)
			row.Name:SetText(GOLD .. label .. "|r")
			row.Right:SetText(("%d/%d"):format(e.done, e.total))
		end
		left, right = 20, 50
	else
		local id = e.quest
		local q = Quest(id)
		local status = StatusOf(id)
		local c = STATUS[status]
		local x = 10 + e.depth * INDENT -- (the marker's centre)
		local n = 0
		for col, bits in pairs(e.rails or EMPTY) do
			n = n + 1
			local t = RailTexture(row, n)
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", 10 + col * INDENT, bits == 2 and -ROW_H / 2 or 0)
			t:SetSize(1, bits == 3 and ROW_H or ROW_H / 2)
			t:Show()
		end
		if e.stub then
			local from = 10 + e.stub * INDENT
			row.Stub:ClearAllPoints()
			row.Stub:SetPoint("TOPLEFT", from, -ROW_H / 2)
			row.Stub:SetSize(math.max(1, x - from - 4), 1)
			row.Stub:Show()
		end
		local locked = status == "locked"
		row.Marker:SetShown(not locked)
		row.Lock:SetShown(locked)
		if locked then
			row.Lock:ClearAllPoints()
			row.Lock:SetPoint("CENTER", row, "LEFT", x, 0)
		else
			row.Marker:ClearAllPoints()
			row.Marker:SetPoint("CENTER", row, "LEFT", x, 0)
			row.Marker:SetVertexColor(c[1], c[2], c[3])
		end
		row.Name:SetText(LevelTag(q) .. Title(id))
		row.Name:SetTextColor(c[1], c[2], c[3])
		local where = (e.out or e.result) and q and ZoneOf(q)
		row.Right:SetText(where and (GREY .. where .. "|r") or "")
		row.Picked:SetShown(id == state.picked)
		left, right = x + 9, where and 130 or 4
	end
	if row.left ~= left or row.right ~= right then -- (the name's room: only when it differs)
		row.left, row.right = left, right
		row.Name:ClearAllPoints()
		row.Name:SetPoint("LEFT", left, 0)
		row.Name:SetPoint("RIGHT", -right, 0)
		row.Right:SetWidth(math.max(1, right - 6))
	end
end

---------------------------------------------------------------------------
-- The right: the details
---------------------------------------------------------------------------

local function HasBit(mask, bit)
	return math.floor(mask / 2 ^ (bit - 1)) % 2 == 1
end

local function RaceNames(mask)
	local names = {}
	for id, english in ipairs(RACES) do
		if HasBit(mask, id) then
			local info = C_CreatureInfo and LT.Value(C_CreatureInfo.GetRaceInfo, id)
			names[#names + 1] = type(info) == "table" and type(info.raceName) == "string" and info.raceName or english
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

local function Requirements(q)
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
	if not lines[1] then
		return nil
	end
	return GOLD .. L["Requirements"] .. "|r\n" .. table.concat(lines, "\n")
end

local function StatusLine(q, status)
	if status == "level" and q.minLevel then
		return L["Needs level %d"]:format(q.minLevel)
	elseif status == "locked" then
		return L["Locked: an earlier quest comes first"]
	end
	return Word(status)
end

local function Summary(q, status)
	local lines = { STATUS_HEX[status] .. StatusLine(q, status) .. "|r" }
	if q.level and q.minLevel and q.minLevel ~= q.level then
		lines[#lines + 1] = L["Level %d, from level %d"]:format(q.level, q.minLevel)
	elseif q.level or q.minLevel then
		lines[#lines + 1] = L["Level %d"]:format(q.level or q.minLevel)
	end
	local zone = ZoneOf(q)
	if zone then
		lines[#lines + 1] = zone
	end
	local chain = Q.Chain and Q.Chain(q.id)
	if type(chain) == "table" and #chain > 1 then
		for i, id in ipairs(chain) do
			if id == q.id then
				lines[#lines + 1] = L["Step %d of %d in its chain"]:format(i, #chain)
				break
			end
		end
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

-- "Starts at: ..." and "Turn in at: ...": who or what, and where.
local function PlaceList(list)
	local names = {}
	for i, s in ipairs(list or EMPTY) do
		if i > PLACES_SHOWN then
			names[#names + 1] = "..."
			break
		end
		local name = s.name or ("#" .. tostring(s.id))
		if s.kind == "object" then
			name = L["%s (an object)"]:format(name)
		elseif s.kind == "item" then
			name = L["%s (an item)"]:format(name)
		end
		local point = s.points and s.points[1]
		local zone = point and MapName(point.map)
		names[#names + 1] = zone and (name .. " " .. GREY .. "- " .. zone .. "|r") or name
	end
	return table.concat(names, ", ")
end

local function Places(q)
	local lines = {}
	if q.starts and q.starts[1] then
		lines[#lines + 1] = L["Starts at: %s"]:format(PlaceList(q.starts))
	end
	if q.ends and q.ends[1] then
		lines[#lines + 1] = L["Turn in at: %s"]:format(PlaceList(q.ends))
	end
	return lines[1] and table.concat(lines, "\n") or nil
end

-- The small map: the map of the first giver's spot (else the first ender's), and everyone's spots on it.
local function MapPoints(q)
	local map
	for _, list in ipairs({ q.starts or EMPTY, q.ends or EMPTY }) do
		for _, s in ipairs(list) do
			local point = s.points and s.points[1]
			map = map or (point and point.map)
		end
	end
	if not map then
		return nil
	end
	local points = {}
	for k, list in ipairs({ q.starts or EMPTY, q.ends or EMPTY }) do
		local n = 0
		for _, s in ipairs(list) do
			for _, p in ipairs(s.points or EMPTY) do
				if p.map == map and n < POINTS_SHOWN then
					n = n + 1
					points[#points + 1] = { x = p.x, y = p.y, kind = k == 1 and "start" or "end", label = s.name }
				end
			end
		end
	end
	return map, points
end

local function FriendsLine(id)
	local list = Q.Friends and Q.Friends(id) or EMPTY
	if not list[1] then
		return nil
	end
	local names = {}
	for i, f in ipairs(list) do
		if i > FRIENDS_SHOWN then
			names[#names + 1] = GREY .. L["... and %d more"]:format(#list - FRIENDS_SHOWN) .. "|r"
			break
		end
		local status = STATUS[f.status] and f.status or "other"
		names[#names + 1] = LT.Window.ClassColorCode(f.classFile) .. (f.name or "?") .. "|r " .. STATUS_HEX[status] .. "(" .. Word(status) .. ")|r"
	end
	return GOLD .. L["Friends"] .. "|r\n" .. table.concat(names, ", ")
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

local function FillLink(b, id)
	local q = Quest(id)
	local status = StatusOf(id)
	local c = STATUS[status]
	b.quest = id
	b.Marker:SetShown(status ~= "locked")
	b.Lock:SetShown(status == "locked")
	b.Marker:SetVertexColor(c[1], c[2], c[3])
	local zone = q and ZoneOf(q)
	local here = state.where and state.places[state.where]
	local other = zone and here and zone ~= here.name
	b.Text:SetText(STATUS_HEX[status] .. LevelTag(q) .. Title(id) .. "|r" .. (other and (" " .. GREY .. "- " .. zone .. "|r") or ""))
end

-- "Needs first:" or "Leads to:" and a button per quest; used: the link buttons taken so far.
local function PutLinks(head, more, label, list, y, used)
	if not list[1] then
		head:Hide()
		more:Hide()
		return y, used
	end
	y = Put(head, GOLD .. label .. "|r", y, 2)
	local shown = 0
	for _, item in ipairs(list) do
		if shown >= LINKS_SHOWN then
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

local function PutMap(q, y)
	local d = view.d
	local map, points = MapPoints(q)
	if not (map and points[1] and Q.NewMiniMap) or d.mapBroken then
		d.MapBox:Hide()
		return y
	end
	if not d.map then
		local ok, m = pcall(Q.NewMiniMap, d.MapBox)
		if not (ok and type(m) == "table" and m.Show) then
			d.mapBroken = true
			d.MapBox:Hide()
			return y
		end
		d.map = m
		local f = m.SetAllPoints and m or (type(m.frame) == "table" and m.frame) or nil
		if f and f.SetAllPoints then
			f:ClearAllPoints()
			f:SetAllPoints(d.MapBox)
		end
	end
	d.MapBox:ClearAllPoints()
	d.MapBox:SetPoint("TOPLEFT", 0, -y)
	d.MapBox:Show()
	d.map:Show(map, points)
	return y + d.MapBox:GetHeight() + 8
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
		d.MapBox:Hide()
		return
	end
	local status = StatusOf(id)
	local y = Put(d.Title, Title(id), 0, 4)
	y = Put(d.Sub, Summary(q, status), y, 8)
	y = Put(d.Req, Requirements(q), y, 8)
	y = Put(d.Places, Places(q), y, 8)
	y = PutMap(q, y)
	local used = 0
	y, used = PutLinks(d.NeedsHead, d.NeedsMore, L["Needs first:"], Q.Missing and Q.Missing(id) or EMPTY, y, used)
	y, used = PutLinks(d.LeadsHead, d.LeadsMore, L["Leads to:"], Q.Opens and Q.Opens(id) or EMPTY, y, used)
	for i = used + 1, #d.links do
		d.links[i].quest = nil
		d.links[i]:Hide()
	end
	y = Put(d.Friends, FriendsLine(id), y, 8)
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
	view.tree:Lay()
	FillDetails(changed)
	if user and Q.ShowQuest and SmallOpen() then
		Q.ShowQuest(id)
	end
end

local function SelectPlace(id)
	if state.query ~= "" then
		state.drilled = true
	end
	state.where = id
	view.zones:Lay()
	DrawMiddle(0)
	if view.d.Body:IsShown() then
		FillDetails() -- (its links say which zone they're in)
	end
end

-- A quest anywhere: its zone (or dungeon) on the left, its group open, the row in sight, the details.
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
		local group = BuildTree(place).groupOf[id]
		if group then
			state.folded[group.key] = nil
		end
	end
	state.picked = nil
	if moved then
		DrawZones(true, target)
	else
		view.zones:Lay()
	end
	DrawMiddle(0, id)
	Pick(id, user)
end

local function BackToResults()
	state.drilled = false
	DrawMiddle(0)
end

local function Fold(key)
	state.folded[key] = not state.folded[key] or nil
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
	DrawMiddle(0)
end

-- Emptied: back to the tree, at once (the place clicked last stays).
local function EndSearch()
	state.searchAt = nil
	if state.query == "" then
		return
	end
	state.query, state.drilled, state.results = "", false, nil
	DrawMiddle(0, state.picked)
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
		view.zones:Lay()
		DrawMiddle(true)
		FillDetails()
	end
	if state.namesAt and now >= state.namesAt then
		state.namesAt = nil
		view.tree:Lay()
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

local function Tip(self)
	local id = self.quest or (self.entry and self.entry.quest)
	local q = Quest(id)
	if not q then
		return
	end
	local status = StatusOf(id)
	local c = STATUS[status]
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(Title(id), 1, 0.82, 0)
	GameTooltip:AddLine(StatusLine(q, status), c[1], c[2], c[3])
	local zone = ZoneOf(q)
	if zone then
		GameTooltip:AddLine(zone, 0.8, 0.8, 0.8)
	end
	GameTooltip:AddLine(L["Click: details"], 0.5, 0.75, 1)
	GameTooltip:Show()
end

local function Untip(self)
	if GameTooltip:IsOwned(self) then
		GameTooltip:Hide()
	end
end

local function NewMarker(row)
	local marker = row:CreateTexture(nil, "ARTWORK")
	marker:SetColorTexture(1, 1, 1)
	marker:SetSize(8, 8)
	local mask = row:CreateMaskTexture()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(marker)
	marker:AddMaskTexture(mask)
	local lock = row:CreateTexture(nil, "ARTWORK")
	lock:SetTexture(LOCK)
	lock:SetSize(13, 13)
	lock:Hide()
	return marker, lock
end

local function NewRowBase(parent, width)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(width, ROW_H)
	row:SetHighlightTexture(HIGHLIGHT, "ADD")
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
	row.Name:SetPoint("LEFT", 20, 0)
	row.Name:SetPoint("RIGHT", -106, 0)
	row.Count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Count:SetPoint("RIGHT", -4, 0)
	row.Count:SetWidth(62)
	row.Count:SetJustifyH("RIGHT")
	row.Range = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.Range:SetPoint("RIGHT", -68, 0)
	row.Range:SetWidth(36)
	row.Range:SetJustifyH("RIGHT")
	row:SetScript("OnClick", function(self)
		local e = self.entry
		if not e then
			return
		elseif e.header then
			Fold(e.key)
			DrawZones(true)
		else
			SelectPlace(e.id)
		end
	end)
	return row
end

local function NewTreeRow(parent, width)
	local row = NewRowBase(parent, width)
	row.Marker, row.Lock = NewMarker(row)
	row.Stub = row:CreateTexture(nil, "BORDER")
	row.Stub:SetColorTexture(1, 1, 1, 0.22)
	row.Stub:Hide()
	row.rails = {}
	row.Right = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.Right:SetPoint("RIGHT", -4, 0)
	row.Right:SetJustifyH("RIGHT")
	row.Right:SetWordWrap(false)
	row:SetScript("OnEnter", Tip)
	row:SetScript("OnLeave", Untip)
	row:SetScript("OnClick", function(self)
		local e = self.entry
		if not e then
			return
		elseif e.back then
			BackToResults()
		elseif e.header then
			if not e.search then
				Fold(e.key)
				DrawMiddle(true)
			end
		elseif e.result then
			Open(e.quest, true) -- (its zone's tree, inside the search)
		else
			Pick(e.quest, true)
		end
	end)
	return row
end

local function NewLink(parent, width)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, LINK_H)
	b:SetHighlightTexture(HIGHLIGHT, "ADD")
	b.Marker, b.Lock = NewMarker(b)
	b.Marker:SetPoint("CENTER", b, "LEFT", 8, 0)
	b.Lock:SetPoint("CENTER", b, "LEFT", 8, 0)
	b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.Text:SetPoint("LEFT", 18, 0)
	b.Text:SetPoint("RIGHT", -2, 0)
	b.Text:SetJustifyH("LEFT")
	b.Text:SetWordWrap(false)
	b:SetScript("OnEnter", Tip)
	b:SetScript("OnLeave", Untip)
	b:SetScript("OnClick", function(self)
		if self.quest then
			Untip(self)
			Open(self.quest, true)
		end
	end)
	b:Hide()
	return b
end

local function BuildDetails(root, x, y, width, height)
	local d = { links = {} }
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
	d.Places = Text("GameFontHighlightSmall")
	d.NeedsHead, d.NeedsMore = Text("GameFontNormal"), Text("GameFontHighlightSmall")
	d.LeadsHead, d.LeadsMore = Text("GameFontNormal"), Text("GameFontHighlightSmall")
	d.Friends = Text("GameFontHighlightSmall")
	d.MapBox = CreateFrame("Frame", nil, d.Body)
	d.MapBox:SetSize(bodyW - 4, math.floor((bodyW - 4) * 2 / 3))
	d.MapBox:Hide()
	function d.Link(i)
		local b = d.links[i]
		if not b then
			b = NewLink(d.Body, bodyW - 4)
			d.links[i] = b
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

local function BuildTop()
	local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("TOPLEFT", 16, -37)
	label:SetText(L["Search all zones:"])
	local box = CreateFrame("EditBox", nil, frame)
	view.Box = box
	box:SetSize(280, 22)
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
	local legend = {}
	for _, status in ipairs(STATUS_ORDER) do
		local mark = status == "locked" and ("|T" .. LOCK .. ":12:12|t") or (STATUS_HEX[status] .. DOT .. "|r")
		legend[#legend + 1] = mark .. " " .. STATUS_HEX[status] .. Word(status) .. "|r"
	end
	view.Legend = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	view.Legend:SetPoint("TOPRIGHT", -16, -41)
	view.Legend:SetText(table.concat(legend, "    "))
	view.Search = { label, box }
end

local function Build()
	frame = LT.Window.Create("LefthyToolsQuesttreeBrowser", "Questtree", WIDTH, HEIGHT)
	view = {}
	local width, height = WIDTH - INSET_W, HEIGHT - INSET_H
	local root = CreateFrame("Frame", nil, frame.Inset)
	root:SetPoint("TOPLEFT")
	root:SetSize(width, height)
	view.root = root
	BuildTop()
	local paneH = height - 2 * PAD
	view.zones = NewList(root, PAD, PAD, ZONES_W - BAR_W, paneH, NewZoneRow, FillZoneRow)
	local middleX = PAD + ZONES_W + GAP
	view.Head = root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	view.Head:SetPoint("TOPLEFT", middleX + 4, -PAD - 5)
	view.Head:SetWidth(MIDDLE_W - 8)
	view.Head:SetJustifyH("LEFT")
	view.Head:SetWordWrap(false)
	view.tree = NewList(root, middleX, PAD + HEAD_H, MIDDLE_W - BAR_W, paneH - HEAD_H, NewTreeRow, FillTreeRow)
	view.Message = root:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	view.Message:SetPoint("TOPLEFT", middleX + 4, -PAD - HEAD_H - 8)
	view.Message:SetWidth(MIDDLE_W - BAR_W - 8)
	view.Message:SetJustifyH("LEFT")
	view.Message:Hide()
	for _, x in ipairs({ middleX - GAP / 2, middleX + MIDDLE_W + GAP / 2 }) do
		local split = root:CreateTexture(nil, "ARTWORK")
		split:SetColorTexture(1, 0.82, 0, 0.2)
		split:SetWidth(1)
		split:SetPoint("TOPLEFT", x, -PAD)
		split:SetHeight(paneH)
	end
	local detailX = middleX + MIDDLE_W + GAP
	BuildDetails(root, detailX, PAD, width - detailX - PAD - EDGE, paneH)
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
		view.Box:ClearFocus()
		GameTooltip:Hide()
	end)
	if Q.OnDataChanged then
		Q.OnDataChanged(DataChanged)
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
	view.Legend:SetShown(ok)
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

-- Opens the big window, on a quest if one is given (its zone, its row, its details).
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

-- The window's frames and state, and what Q.OnDataChanged calls (for the tests).
function Q.BrowserView()
	return view, state, frame, DataChanged
end
