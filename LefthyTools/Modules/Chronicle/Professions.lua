local _, ns = ...
local LT = ns.LT
local L = ns.L
local C = ns.Chronicle

-- Chronicle's Professions tab: every friend's professions and recipes, since a profession's link
-- doesn't open across realms. On top the search and a button per profession; under them people (far
-- left, by skill, "Everyone" first), what they can make (the middle, under group headers that fold)
-- and the recipe hovered or clicked (the right: the real item tooltip, what it needs and who else
-- knows it). All its data comes from C.Recipes (Recipes.lua) and is read when drawing, so this file
-- doesn't care which loads first; the window (Window.lua) calls C.DrawProfessions, C.HideProfessions
-- and, every second, C.ProfessionsTick.
--
-- What it costs: both lists are pools of as many rows as can be in sight, laid where they're scrolled
-- to, so 600 recipes cost one screen of rows. A profession's recipes are put into their groups once
-- (Classified). The lists are only made again when R.Revision() moved or the selection changed, at
-- most every few seconds and not at the start of a fight; names coming in only fill the rows in sight.
-- Nothing here is protected, so all of it works in a fight, and no Blizzard menu is opened (they taint
-- gamepad mode, docs/forever-platform.md).

local PAD, GAP = 6, 8
local SEARCH_Y, SEARCH_H = 5, 24
local PROF_Y, PROF_H, PROF_GAP, PROF_PER_ROW, PROF_ROWS = 34, 24, 3, 6, 2
local PANES_Y = PROF_Y + PROF_ROWS * (PROF_H + PROF_GAP) + 4
local PEOPLE_W, MIDDLE_W = 170, 306 -- (each with its scroll bar)
local BAR_W = 24                    -- a scroll bar, right of its list
local EDGE = 10                     -- kept free at the window's right edge
local PERSON_H, ITEM_H = 32, 20
local HEAD_H = 40                   -- the details' icon and name
local REAGENT_H = 18
local COMPARE_H = 16                -- "Replaces: ..."; the stat lines come under it
local COMPARE_ROWS = 2              -- a second ring or trinket
local BACK = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up"
local OPEN_H = 26                   -- the button on my own profession window
local PERSON_PROFS, PERSON_ROW_H = 14, 22 -- a person's professions, in the details
local OPEN_SETTLE, OPEN_LATEST = 0.25, 3 -- seconds: its list has settled; or at the latest
local OPEN_CHECK = 0.2              -- seconds to go to the recipe, before it's selected directly
local REAGENTS = 8                  -- what a recipe can need (SpellReagents' columns)
local KNOWN_NAMES = 12              -- names in "Also known by", at most
local SEARCH_GAP = 0.3              -- typing: searched this long after the last key
local NAMES_GAP = 0.2               -- items' names come in bunches: one fill for a bunch
local REDRAW_GAP = 3                -- a friend's list arriving in parts: redrawn at most this often
local STALE_AFTER = 3 * 86400       -- a list older than this says how old
local EVERYONE = "everyone"
local TIP_NAME = "LefthyToolsProfessionsTooltip"
local PLUS, MINUS = "Interface\\Buttons\\UI-PlusButton-Up", "Interface\\Buttons\\UI-MinusButton-Up"
local GOLD_TEXT = "|cffffd200"
local GREY_TEXT = "|cff888888"
local SHORT_TEXT = "|cffff4040"

-- The skill-up colours, as in the profession window.
local HARD, MEDIUM, EASY, TRIVIAL = { 1, 0.5, 0.25 }, { 1, 1, 0 }, { 0.25, 0.75, 0.25 }, { 0.5, 0.5, 0.5 }
local DIFFICULTY_TEXT = {
	[HARD] = function() return "|cffff8040" .. L["hard (orange)"] .. "|r" end,
	[MEDIUM] = function() return "|cffffff00" .. L["medium (yellow)"] .. "|r" end,
	[EASY] = function() return "|cff40bf40" .. L["easy (green)"] .. "|r" end,
	[TRIVIAL] = function() return "|cff808080" .. L["trivial (grey)"] .. "|r" end,
}

-- Gear's groups, in the character sheet's order: the game's name for the slot, the inventory types
-- in it (ItemSparse's InventoryType). Chest and robe are one, and so are the kinds of off hand and
-- of ranged weapon the game calls the same.
local SLOTS = {
	{ "INVTYPE_HEAD", 1 }, { "INVTYPE_NECK", 2 }, { "INVTYPE_SHOULDER", 3 }, { "INVTYPE_CLOAK", 16 }, { "INVTYPE_CHEST", 5, 20 },
	{ "INVTYPE_BODY", 4 }, { "INVTYPE_TABARD", 19 }, { "INVTYPE_WRIST", 9 }, { "INVTYPE_HAND", 10 }, { "INVTYPE_WAIST", 6 },
	{ "INVTYPE_LEGS", 7 }, { "INVTYPE_FEET", 8 }, { "INVTYPE_FINGER", 11 }, { "INVTYPE_TRINKET", 12 },
	{ "INVTYPE_WEAPONMAINHAND", 21 }, { "INVTYPE_WEAPON", 13 }, { "INVTYPE_2HWEAPON", 17 }, { "INVTYPE_WEAPONOFFHAND", 22, 14 },
	{ "INVTYPE_HOLDABLE", 23 }, { "INVTYPE_RANGED", 15, 26 }, { "INVTYPE_THROWN", 25 }, { "INVTYPE_RELIC", 28 }, { "INVTYPE_BAG", 18 },
	{ "INVTYPE_QUIVER", 27 }, { "INVTYPE_AMMO", 24 },
}
-- The same by what C_Item.GetItemInfoInstant says, for a crafted item the data has no slot for.
local SLOT_OF_TYPE, SLOT_OF_LOCATION = {}, {}
for index, slot in ipairs(SLOTS) do
	SLOT_OF_LOCATION[slot[1]] = index
	for i = 2, #slot do
		SLOT_OF_TYPE[slot[i]] = index
	end
end
SLOT_OF_LOCATION.INVTYPE_ROBE = SLOT_OF_TYPE[20]
SLOT_OF_LOCATION.INVTYPE_SHIELD = SLOT_OF_TYPE[14]
SLOT_OF_LOCATION.INVTYPE_RANGEDRIGHT = SLOT_OF_TYPE[26]
local RANK_TYPE, RANK_CATEGORY, RANK_OTHER = 100, 200, 300 -- groups: gear (its slot's number), then these

local view                    -- the tab's frames, built on first open
local profs, people = {}, {}  -- R.Professions(), R.People(line): as of the last draw
local line, linePicked        -- the profession shown; chosen by the player (else the default follows the data)
local personId, personPicked  -- who is shown, or EVERYONE; the same
local person                  -- their entry in people (nil: Everyone)
local query = ""              -- the search drawn
local litLines = {}           -- the professions of the people the search found
local drilled                 -- a profession or person clicked during a search: its recipes show, the search stays
local beforeSearch            -- where the list and details were when a search began
local currentGroups = {}      -- what the middle shows: { key, label, entries, ... }
local collapsed = {}          -- group key -> true: folded
local shown, pinned           -- the entry in the details; the one clicked, which stays there
local classified = {}         -- R.Parse's list -> its groups, sorted
local itemTypes = {}          -- item ID -> { location, class, subclass } | false
local asked, waiting = {}, {} -- items asked for this session; those not here yet
local searchAt, fillAt        -- when the search or a fill of what's in sight is due
local namesOld, bagsOld       -- what the fill does
local tipCame, tipOld         -- the tooltip's item came in; it waits until the tab is in sight
local gearOld                 -- what I wear changed
local lastDraw = -math.huge

---------------------------------------------------------------------------
-- Items and spells: names, icons, types
---------------------------------------------------------------------------

local function AskItem(id)
	if asked[id] then
		return
	end
	asked[id], waiting[id] = true, true
	pcall(C_Item.RequestLoadItemDataByID, id)
end

-- An item's name, nil while the client doesn't know it yet (asked for: GET_ITEM_INFO_RECEIVED).
local function ItemName(id)
	local name = LT.Value(C_Item.GetItemInfo, ("item:%d"):format(id))
	if type(name) == "string" then
		return name
	end
	AskItem(id)
end

local function SpellInfo(spell)
	local info = LT.Value(C_Spell.GetSpellInfo, spell)
	return type(info) == "table" and info or nil
end

-- What a recipe is called: its item, or its spell (an enchant; an item not loaded yet).
local function RecipeName(recipe)
	local name = recipe.item and ItemName(recipe.item)
	if not name then
		local info = SpellInfo(recipe.spell)
		name = info and info.name
	end
	return name or ("#" .. tostring(recipe.spell))
end

local function RecipeText(recipe)
	local quality = recipe.quality or (recipe.item and LT.Value(C_Item.GetItemQualityByID, recipe.item))
	return C.QualityText(RecipeName(recipe), quality)
end

local function RecipeIcon(recipe)
	local icon = recipe.item and LT.Value(C_Item.GetItemIconByID, recipe.item)
	if not icon then
		local info = SpellInfo(recipe.spell)
		icon = info and info.iconID
	end
	return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- What GetItemInfoInstant says of an item (no loading needed), once each.
local function ItemType(id)
	local known = itemTypes[id]
	if known == nil then
		local ok, _, _, _, location, _, class, subclass = pcall(C_Item.GetItemInfoInstant, id)
		known = false
		if ok and class ~= nil and not (LT.IsSecret(class) or LT.IsSecret(subclass) or LT.IsSecret(location)) then
			known = { location = location, class = class, subclass = subclass }
		end
		itemTypes[id] = known
	end
	return known or nil
end

-- A person in their class colour.
local function NameText(who)
	return LT.Window.ClassColorCode(who.classFile) .. (who.name or "?") .. "|r" .. C.Mark(who.partial)
end

-- How hard a recipe is at a skill: a skill-up colour, nil when the data has no numbers for it.
local function Difficulty(skill, recipe)
	local low, high = recipe.low, recipe.high
	if not (skill and low and high and high > 0) then
		return nil
	end
	if skill < low then
		return HARD
	elseif skill < (low + high) / 2 then
		return MEDIUM
	elseif skill < high then
		return EASY
	end
	return TRIVIAL
end

---------------------------------------------------------------------------
-- Groups
---------------------------------------------------------------------------

-- A recipe's group: key, label, rank, whether it's gear.
local function GroupOf(recipe)
	if recipe.item then
		local kind = ItemType(recipe.item)
		local slot = SLOT_OF_TYPE[recipe.slot] or (kind and SLOT_OF_LOCATION[kind.location])
		if slot then
			return "slot" .. slot, _G[SLOTS[slot][1]] or L["Other"], slot, true
		end
		local label = kind and (LT.Value(C_Item.GetItemSubClassInfo, kind.class, kind.subclass) or LT.Value(C_Item.GetItemClassInfo, kind.class))
		if type(label) == "string" and label ~= "" then
			return "type" .. kind.class .. "." .. kind.subclass, label, RANK_TYPE
		end
	elseif recipe.cat then
		local names = ns.RecipeData and ns.RecipeData.categories and ns.RecipeData.categories[recipe.cat]
		local label = names and (ns.LOCALE == "deDE" and names[2] or names[1])
		if label then
			return "cat" .. recipe.cat, label, RANK_CATEGORY
		end
	end
	return "other", L["Other"], RANK_OTHER
end

local function BySkill(a, b)
	local la, lb = a.low or 0, b.low or 0
	if la ~= lb then
		return la > lb
	end
	return a.spell < b.spell
end

local function ByItemLevel(a, b)
	local ia, ib = a.ilvl or 0, b.ilvl or 0
	if ia ~= ib then
		return ia > ib
	end
	return BySkill(a, b)
end

local function GroupOrder(a, b)
	if a.rank ~= b.rank then
		return a.rank < b.rank
	end
	if a.label ~= b.label then
		return a.label < b.label
	end
	return a.key < b.key
end

-- A profession's recipes in their sorted groups: the data doesn't change, so once for each list.
local function Classified(list)
	local groups = classified[list]
	if groups then
		return groups
	end
	groups = {}
	local byKey = {}
	for _, recipe in ipairs(list) do
		local key, label, rank, gear = GroupOf(recipe)
		local group = byKey[key]
		if not group then
			group = { key = key, label = label, rank = rank, gear = gear, recipes = {} }
			byKey[key] = group
			groups[#groups + 1] = group
		end
		group.recipes[#group.recipes + 1] = recipe
	end
	for _, group in ipairs(groups) do
		table.sort(group.recipes, group.gear and ByItemLevel or BySkill)
	end
	table.sort(groups, GroupOrder)
	classified[list] = groups
	return groups
end

-- What the selected person knows, or (person nil) what anyone knows and how many do, as groups with
-- entries. Groups without any are left out.
local function KnownGroups(R)
	local groups = {}
	local counts
	if not person then
		counts = {}
		for _, who in ipairs(people) do
			for spell in pairs(who.known or {}) do
				counts[spell] = (counts[spell] or 0) + 1
			end
		end
	end
	local known = person and (person.known or {}) or counts
	local list = R.Parse(line)
	for _, group in ipairs(list and Classified(list) or {}) do
		local entries = {}
		for _, recipe in ipairs(group.recipes) do
			if known[recipe.spell] then
				entries[#entries + 1] = { recipe = recipe, count = counts and counts[recipe.spell], gear = group.gear }
			end
		end
		if entries[1] then
			groups[#groups + 1] = { key = line .. ":" .. group.key, label = group.label, entries = entries }
		end
	end
	return groups
end

-- During a search, what's shown of the profession or person clicked: all of it if the search found
-- that person, or nothing of its recipes; else the recipes that match.
local function DrilledGroups(R)
	local groups = KnownGroups(R)
	local found = R.SearchPeople and R.SearchPeople(query) or {}
	for _, match in ipairs(found) do
		if person and match.who.id == person.id then
			return groups
		end
	end
	local matches = {}
	for _, match in ipairs(R.Search(query)) do
		if match.line == line then
			matches[match.recipe.spell] = true
		end
	end
	if not next(matches) then
		return groups
	end
	local kept = {}
	for _, group in ipairs(groups) do
		local entries = {}
		for _, entry in ipairs(group.entries) do
			if matches[entry.recipe.spell] then
				entries[#entries + 1] = entry
			end
		end
		if entries[1] then
			kept[#kept + 1] = { key = group.key, label = group.label, entries = entries }
		end
	end
	return kept[1] and kept or groups
end

-- A search's matches: the people it finds, then recipes by profession in the buttons' order.
local function SearchGroups(R)
	local byLine = {}
	wipe(litLines)
	local found = R.SearchPeople and R.SearchPeople(query) or {}
	for _, match in ipairs(R.Search(query)) do
		local group = byLine[match.line]
		if not group then
			group = { key = "search:" .. tostring(match.line), entries = {} }
			byLine[match.line] = group
		end
		group.entries[#group.entries + 1] = match
	end
	local groups = {}
	if found[1] then
		for _, match in ipairs(found) do
			for _, prof in ipairs(match.professions) do
				litLines[prof.line] = true
			end
		end
		groups[1] = { key = "search:people", label = L["People"], entries = found }
	end
	for _, prof in ipairs(profs) do
		local group = byLine[prof.line]
		if group then
			group.label = prof.name
			groups[#groups + 1] = group
		end
	end
	return groups
end

local function GatheringNow()
	for _, prof in ipairs(profs) do
		if prof.line == line then
			return prof.gathering
		end
	end
end

---------------------------------------------------------------------------
-- Lists: a pool of rows, laid where the list is scrolled to
---------------------------------------------------------------------------

local function NewList(parent, x, y, width, height, rowHeight, newRow, fillRow)
	local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", x, -y)
	scroll:SetSize(width, height)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(width, 1)
	scroll:SetScrollChild(child)
	local list = { scroll = scroll, child = child, rows = {}, entries = {}, first = 1, made = 0, fills = 0 }
	local pool = math.ceil(height / rowHeight) + 1 -- (one more for rows cut at the top and the bottom)

	-- The rows in sight, filled; the rest of the pool hidden.
	function list:Lay(offset)
		local top = math.max(0, math.floor((offset or scroll:GetVerticalScroll() or 0) / rowHeight))
		self.first = top + 1
		for k = 1, pool do
			local entry, row = self.entries[top + k], self.rows[k]
			if entry then
				if not row then
					row = newRow(child, width, rowHeight)
					self.rows[k] = row
					self.made = self.made + 1
				end
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", 0, -(top + k - 1) * rowHeight)
				self.fills = self.fills + 1
				fillRow(row, entry)
				row:Show()
			elseif row then
				row.entry = nil
				row:Hide()
			end
		end
	end

	-- A new list of entries, scrolled to offset (true: where it is, as far as it still goes).
	function list:SetEntries(entries, offset)
		self.entries = entries
		local total = #entries * rowHeight
		child:SetHeight(math.max(1, total))
		local now = scroll:GetVerticalScroll() or 0
		local want = offset == true and now or offset or 0
		want = math.max(0, math.min(want, total - height))
		self.first = math.floor(want / rowHeight) + 1 -- (laid just below, not again by the scroll's script)
		if want ~= now then
			scroll:SetVerticalScroll(want)
		end
		self:Lay(want)
	end

	-- Scrolled (the wheel, the bar; after the template's own): the rows again when another is first.
	scroll:HookScript("OnVerticalScroll", function(_, offset)
		if math.floor((offset or 0) / rowHeight) + 1 ~= list.first then
			list:Lay(offset)
		end
	end)
	return list
end

---------------------------------------------------------------------------
-- Details: the recipe hovered or clicked
---------------------------------------------------------------------------

-- Everything of the real tooltip inside the panel is in here: a GameTooltip of our own, parented to a
-- frame that clips it, in the window's strata (the template's is TOOLTIP, over everything), not
-- clamped to the screen (the window may be half off it). Wider than the panel it's scaled down, taller
-- than the room left it's cut at the bottom. If it can't work (it can't be made, a call fails, a loaded
-- item gives no lines), the normal tooltip beside the window takes over for the session.
local function FitTip()
	local tip, room = view.Tip, view.tipRoom or 0
	if not (tip and tip:IsShown()) then
		view.TipClip:SetHeight(1)
		return
	end
	local width = tip:GetWidth() or 0
	local scale = width > view.detailW and view.detailW / width or 1
	tip:SetScale(scale)
	view.TipClip:SetHeight(math.max(1, math.min((tip:GetHeight() or 0) * scale, room)))
end

local function ShowTip(recipe)
	local tip = view.Tip
	if not view.tipBroken then
		if not tip then
			local ok, made = pcall(CreateFrame, "GameTooltip", TIP_NAME, view.TipClip, "GameTooltipTemplate")
			tip = ok and made or nil
			view.tipBroken = not ok
			view.Tip = tip
			if tip then
				tip:SetClampedToScreen(false)
				tip:HookScript("OnSizeChanged", FitTip) -- (an item arriving makes it grow)
			end
		end
	end
	if not view.tipBroken then
		local ok = pcall(function()
			tip:SetOwner(view.TipClip, "ANCHOR_NONE")
			tip:SetFrameStrata(view.root:GetFrameStrata())
			tip:SetFrameLevel(view.root:GetFrameLevel() + 5)
			tip:ClearAllPoints()
			tip:SetPoint("TOPLEFT", view.TipClip, "TOPLEFT")
			tip:SetScale(1)
			if recipe.item then
				tip:SetHyperlink(("item:%d"):format(recipe.item))
			else
				tip:SetSpellByID(recipe.spell)
			end
			tip:Show()
		end)
		-- (no lines for an item the client doesn't know yet says nothing: it comes when it's loaded)
		local loaded = not recipe.item or ItemName(recipe.item) ~= nil
		if ok and not (loaded and tip.NumLines and tip:NumLines() == 0) then
			FitTip()
			return
		end
		view.tipBroken = true
		tip:Hide()
	end
	view.TipClip:SetHeight(1)
	GameTooltip:SetOwner(view.Detail, "ANCHOR_RIGHT")
	if recipe.item then
		GameTooltip:SetHyperlink(("item:%d"):format(recipe.item))
	else
		GameTooltip:SetSpellByID(recipe.spell)
	end
	GameTooltip:Show()
end

local function HideTip()
	if view.Tip then
		view.Tip:Hide()
	end
	if GameTooltip:IsOwned(view.Detail) then
		GameTooltip:Hide()
	end
end

-- "Needs:", a row per reagent: its icon, name, how many, how many I have in my bags.
local function FillReagents(recipe)
	local list = recipe.reagents or {}
	view.Needs:SetShown(list[1] ~= nil)
	for i = 1, REAGENTS do
		local row = view.reagents[i]
		local reagent = list[i]
		if reagent then
			-- (either shape: { item, n } or { item = , n = })
			local id, n = reagent.item or reagent[1], reagent.n or reagent[2] or 1
			row.id = id
			row.Icon:SetTexture(LT.Value(C_Item.GetItemIconByID, id) or "Interface\\Icons\\INV_Misc_QuestionMark")
			row.Name:SetText(C.QualityText(ItemName(id) or "...", LT.Value(C_Item.GetItemQualityByID, id)))
			row.Count:SetText(tostring(n))
			local have = LT.Value(C_Item.GetItemCount, id)
			if type(have) == "number" then
				row.Have:SetText((have < n and SHORT_TEXT or GREY_TEXT) .. L["(you: %d)"]:format(have) .. "|r")
			else
				row.Have:SetText("")
			end
			row:Show()
		else
			row.id = nil
			row:Hide()
		end
	end
end

-- Who else knows it: under a person, the others; else everyone who does.
local function FillCrafters(recipe)
	local R = C.Recipes
	local names, more = {}, 0
	for _, who in ipairs(R and R.Crafters(recipe.spell) or {}) do
		if not (person and query == "" and who.id == person.id) then
			if #names < KNOWN_NAMES then
				names[#names + 1] = NameText(who)
			else
				more = more + 1
			end
		end
	end
	if not names[1] then
		view.Also:SetText("")
		return
	end
	local list = table.concat(names, ", ")
	if more > 0 then
		list = list .. " " .. GREY_TEXT .. L["... and %d more"]:format(more) .. "|r"
	end
	local under = person and query == ""
	view.Also:SetText((under and L["Also known by: %s"] or L["Known by: %s"]):format(list))
end

-- Against what I wear (this character, whoever's recipe it is): the game's own comparison, as in the
-- bags. It takes an item I don't have (tested in game). Only gear; nothing worn there: nothing to say.
local function CompareRow(i, worn, delta)
	local row = view.compare[i]
	local name = LT.Value(C_Item.GetItemNameByID, worn.guid or worn.hyperlink)
	row.worn = worn
	row.Name:SetText(L["Replaces: %s"]:format(
		C.QualityText(name or "...", LT.Value(C_Item.GetItemQualityByID, worn.guid or worn.hyperlink))))
	row.Lines:SetText(delta)
	row:Show()
end

local function ItemDelta(item, worn, paired, together)
	local ok, lines = pcall(C_TooltipComparison.GetItemComparisonDelta, item, worn, paired, together)
	return ok and type(lines) == "table" and table.concat(lines, "\n") or ""
end

local function FillCompare(recipe)
	for _, row in ipairs(view.compare) do
		row.worn = nil
		row:Hide()
	end
	if not (C_TooltipComparison and recipe.item and (recipe.slot or 0) > 0) then
		return
	end
	local item = { hyperlink = ("item:%d"):format(recipe.item) }
	local ok, info = pcall(C_TooltipComparison.GetItemComparisonInfo, item)
	local worn = ok and type(info) == "table" and type(info.item) == "table" and info.item or nil
	if not (worn and (worn.guid or worn.hyperlink)) then
		return
	end
	local more = type(info.additionalItems) == "table" and info.additionalItems[1] or nil
	if info.method == 0 then -- (TooltipComparisonMethod.Single: a second ring or trinket is its own comparison)
		CompareRow(1, worn, ItemDelta(item, worn))
		if more then
			CompareRow(2, more, ItemDelta(item, more))
		end
	else
		CompareRow(1, worn, ItemDelta(item, worn, more, info.method == 2 or info.method == 3))
	end
end

-- The part under the tooltip: its height decides how much room the tooltip has.
local function LayBelow(recipe)
	local y = 0
	for _, row in ipairs(view.compare) do
		if row:IsShown() then
			local lines = (row.Lines:GetText() or "") ~= "" and row.Lines:GetStringHeight() or 0
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", view.Below, "TOPLEFT", 0, -y)
			row:SetHeight(COMPARE_H + lines)
			y = y + COMPARE_H + lines + 6
		end
	end
	view.NeedsBox:ClearAllPoints()
	view.NeedsBox:SetPoint("TOPLEFT", view.Below, "TOPLEFT", 0, -y)
	local count = #(recipe.reagents or {})
	local needs = count > 0 and (16 + count * REAGENT_H) or 0
	view.Also:ClearAllPoints()
	view.Also:SetPoint("TOPLEFT", view.Below, "TOPLEFT", 0, -y - needs - 4)
	local also = (view.Also:GetText() or "") ~= "" and (view.Also:GetStringHeight() + 6) or 0
	local height = y + needs + also
	local mine = C_SpellBook and LT.Value(C_SpellBook.IsSpellKnown, recipe.spell) == true
	view.OpenMine:SetShown(mine)
	view.Below:SetHeight(math.max(1, height))
	view.tipRoom = view.detailH - HEAD_H - height - 12 - (mine and OPEN_H or 0)
end

-- My own profession window on this recipe (I know it). OpenTradeSkill makes the game open it itself,
-- so nothing of ours touches Blizzard's panels (no taint); OpenRecipe then picks the recipe, once
-- the window's list has settled: it selects its first recipe as the list loads, over one picked
-- earlier (seen in game). Settled: no list update for OPEN_SETTLE; at the latest OPEN_LATEST.
-- The window's list holds a recipe's first rank, and Forever has copies of some recipes under other
-- IDs, so the one to ask for is the one the list holds. The game's answer doesn't always move the
-- window (seen in game: the right answer comes, the selection stays), so if it hasn't moved a moment
-- later the recipe is selected directly: that kept Create working in game, but it's Blizzard's frame, so
-- only then.
local openWatch

local function RecipeInfo(id)
	local info = LT.Value(C_TradeSkillUI.GetRecipeInfo, id)
	return type(info) == "table" and info or nil
end

-- A recipe's first rank.
local function FirstRank(info)
	local previous = info.previousRecipeID
	while previous do
		local before = RecipeInfo(previous)
		if not before then
			break
		end
		info, previous = before, before.previousRecipeID
	end
	return info.recipeID
end

-- The ID the window's list has for it; nil: it isn't listed (a filter); the same if that can't be told.
local function ListedRecipe(spell)
	local info = RecipeInfo(spell)
	local list = LT.Value(C_TradeSkillUI.GetFilteredRecipeIDs)
	if not info or type(list) ~= "table" then
		return spell
	end
	local first = FirstRank(info)
	for _, id in ipairs(list) do
		if id == spell or id == first then
			return id
		end
	end
	for _, id in ipairs(list) do
		local other = RecipeInfo(id)
		if other and other.name == info.name then
			return id
		end
	end
	return nil
end

local function WindowShows(id)
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	local form = page and page.SchematicForm
	local ok, info = pcall(function() return form:GetRecipeInfo() end)
	return ok and type(info) == "table" and (info.recipeID == id or FirstRank(info) == id)
end

local function OpenRecipeNow(spell)
	if openWatch then
		openWatch:UnregisterAllEvents()
		openWatch.spell = nil
	end
	local id = ListedRecipe(spell)
	if not id then
		C.module:Print(L["Your profession window's filter hides that recipe."])
		return
	end
	pcall(C_TradeSkillUI.OpenRecipe, id)
	C_Timer.After(OPEN_CHECK, function()
		local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
		if not (page and page.RecipeList and ProfessionsFrame:IsShown()) or WindowShows(id) then
			return
		end
		pcall(page.RecipeList.SelectRecipe, page.RecipeList, RecipeInfo(id), true)
		if not WindowShows(id) then
			C.module:Print(L["Your profession window didn't go to that recipe. Its group may be folded."])
		end
	end)
end

local function OpenWhenSettled(spell)
	openWatch = openWatch or CreateFrame("Frame")
	openWatch.spell = spell
	local function After(seconds)
		local mine = {}
		openWatch.waiting = mine
		C_Timer.After(seconds, function()
			if openWatch.waiting == mine and openWatch.spell == spell then
				OpenRecipeNow(spell)
			end
		end)
	end
	openWatch:RegisterEvent("TRADE_SKILL_SHOW")
	openWatch:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
	openWatch:SetScript("OnEvent", function()
		After(OPEN_SETTLE)
	end)
	After(OPEN_LATEST)
end

local function OpenInMine()
	local recipe = shown and shown.recipe
	local R = C.Recipes
	local line = recipe and R and select(2, R.RecipeOf(recipe.spell))
	if not (line and C_TradeSkillUI) then
		return
	elseif InCombatLockdown() then
		C.module:Print(L["You can't open your profession window during a fight."])
		return
	end
	local base = LT.Value(C_TradeSkillUI.GetBaseProfessionInfo)
	if ProfessionsFrame and ProfessionsFrame:IsShown() and type(base) == "table" and base.professionID == line then
		OpenRecipeNow(recipe.spell)
		return
	end
	OpenWhenSettled(recipe.spell)
	if not pcall(C_TradeSkillUI.OpenTradeSkill, line) then
		openWatch:UnregisterAllEvents()
		openWatch.spell = nil
		C.module:Print(L["The game didn't open your profession window."])
	end
end

local function FillHead(recipe)
	view.Icon:SetTexture(RecipeIcon(recipe))
	view.Name:SetText(RecipeText(recipe) .. ((recipe.count or 1) > 1 and (" x" .. recipe.count) or ""))
	local color = person and query == "" and Difficulty(person.skill, recipe)
	view.Difficulty:SetText(color and L["%s finds it: %s"]:format(NameText(person), DIFFICULTY_TEXT[color]()) or "")
end

-- Who they are, in short: their BattleTag name and level.
local function PersonSub(who)
	local level = who.level and who.level > 0 and L["level %d"]:format(who.level) or nil
	return who.account and level and (who.account .. ", " .. level) or who.account or level or ""
end

-- A person the search found: who they are, and a row per profession; a click there selects it.
local function FillPerson(entry)
	local box = view.PersonBox
	box:SetShown(entry ~= nil)
	if not entry then
		return
	end
	box.Name:SetText(NameText(entry.who))
	box.Sub:SetText(PersonSub(entry.who))
	for i = 1, PERSON_PROFS do
		local row, prof = box.rows[i], entry.professions[i]
		if prof then
			row.line, row.who = prof.line, entry.who.id
			row.Icon:SetTexture(prof.icon)
			row.Name:SetText(prof.name)
			row.Skill:SetText(tostring(prof.skill or 0))
			row.Count:SetText(prof.gathering and "" or L["%d recipes"]:format(prof.count or 0))
			row:Show()
		else
			row:Hide()
		end
	end
end

-- Fills the panel from what's in it (shown).
local function FillDetail()
	local recipe = shown and shown.recipe
	view.DetailBody:SetShown(recipe ~= nil)
	view.Hint:SetShown(recipe == nil and currentGroups[1] ~= nil and not (shown and shown.who))
	FillPerson(shown and shown.who and shown or nil)
	if not recipe then
		HideTip()
		return
	end
	FillHead(recipe)
	FillReagents(recipe)
	FillCrafters(recipe)
	FillCompare(recipe)
	LayBelow(recipe)
	if view.root:IsVisible() then
		tipOld = false
		ShowTip(recipe)
	else
		tipOld = true -- (a tooltip measures itself only in sight: when the tab comes, OnShow)
	end
end

local function SameRecipe(a, b)
	if a == nil or b == nil then
		return false
	elseif a.who or b.who then
		return a.who ~= nil and b.who ~= nil and a.who.id == b.who.id
	end
	return a.recipe.spell == b.recipe.spell
end

local function ShowEntry(entry)
	if SameRecipe(entry, shown) then
		return
	end
	shown = entry
	FillDetail()
end

-- The clicked row's mark, on the rows in sight (nothing else about them changes).
local function MarkPinned()
	for _, row in ipairs(view.middle.rows) do
		row.Picked:SetShown(row.entry ~= nil and not row.entry.header and SameRecipe(row.entry, pinned))
	end
end

---------------------------------------------------------------------------
-- The middle
---------------------------------------------------------------------------

local function Flatten()
	local entries = {}
	if query ~= "" and drilled then
		entries[1] = { header = true, back = true, key = "search:back", label = L["Back to the search results"] }
	end
	for _, group in ipairs(currentGroups) do
		local closed = collapsed[group.key] == true
		entries[#entries + 1] = { header = true, key = group.key, label = group.label, n = #group.entries, closed = closed }
		if not closed then
			for _, entry in ipairs(group.entries) do
				entries[#entries + 1] = entry
			end
		end
	end
	return entries
end

local DrawButtons -- (below: the search lights them up)

-- The list again: what the selection or search asks for. offset: as in SetEntries.
local function DrawMiddle(offset)
	local R = C.Recipes
	local message
	view.groupings = view.groupings + 1
	currentGroups = {}
	if query ~= "" and not drilled then
		currentGroups = R and SearchGroups(R) or {}
		message = not currentGroups[1] and L["Nothing found"] or nil
		DrawButtons()
	elseif not (R and people[1]) then
		message = L["Nobody here has this profession yet. Friends appear when they've updated LefthyTools and logged in once."]
	elseif GatheringNow() then
		message = L["No recipes: gathering"]
	else
		currentGroups = query ~= "" and DrilledGroups(R) or KnownGroups(R)
		if not currentGroups[1] then
			message = person and L["No recipes from %s yet: their list comes when they've updated LefthyTools and logged in once."]:format(NameText(person))
				or L["No recipe lists here yet: they come when friends have updated LefthyTools and logged in once."]
		end
	end
	view.Message:SetText(message or "")
	view.Message:SetShown(message ~= nil)
	view.Hint:SetShown(not shown and currentGroups[1] ~= nil)
	view.middle:SetEntries(Flatten(), offset)
	MarkPinned()
end

local function FillItemRow(row, entry)
	row.entry = entry
	local header = entry.header == true
	row.Toggle:SetShown(header)
	row.Band:SetShown(header)
	row.Icon:SetShown(not header)
	local left, right
	if header then
		row.Toggle:SetTexture(entry.back and BACK or entry.closed and PLUS or MINUS)
		row.Dot:Hide()
		row.Count:Hide()
		row.Picked:Hide()
		row.Name:SetText(GOLD_TEXT .. entry.label .. "|r")
		row.Right:SetText(entry.n and tostring(entry.n) or "")
		left, right = 20, 30
	elseif entry.who then -- (a search found this person)
		local who = entry.who
		row.Icon:SetTexture(entry.professions[1] and entry.professions[1].icon or nil)
		row.Name:SetText(NameText(who))
		row.Picked:SetShown(SameRecipe(entry, pinned))
		row.Dot:Hide()
		row.Count:Hide()
		row.Right:SetText(PersonSub(who))
		left, right = 34, 110
	else
		local recipe = entry.recipe
		row.Icon:SetTexture(RecipeIcon(recipe))
		row.Name:SetText(RecipeText(recipe))
		row.Picked:SetShown(SameRecipe(entry, pinned))
		local searching = entry.people ~= nil
		-- A dot for the selected person, how many know it under Everyone, nothing in a search.
		local color = person and not searching and Difficulty(person.skill, recipe)
		if color then
			row.Dot:SetVertexColor(color[1], color[2], color[3])
		end
		row.Dot:SetShown(color and true or false)
		row.Count:SetText(entry.count and tostring(entry.count) or "")
		row.Count:SetShown(entry.count ~= nil)
		left = 34
		if searching then
			local first = entry.people[1]
			local others = #entry.people - 1
			row.Right:SetText(first and (NameText(first) .. (others > 0 and (" " .. GREY_TEXT .. "+" .. others .. "|r") or "")) or "")
			right = 96
		elseif entry.gear and recipe.ilvl and recipe.ilvl > 0 then
			row.Right:SetText(L["ilvl %d"]:format(recipe.ilvl))
			right = 46
		else
			row.Right:SetText("")
			right = 4
		end
	end
	if row.left ~= left or row.right ~= right then -- (the name's room: only when it differs)
		row.left, row.right = left, right
		row.Name:ClearAllPoints()
		row.Name:SetPoint("LEFT", left, 0)
		row.Name:SetPoint("RIGHT", -right, 0)
		row.Right:SetWidth(math.max(1, right - 6))
	end
end

local function NewItemRow(parent, width, height)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(width, height)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row.Band = row:CreateTexture(nil, "BACKGROUND")
	row.Band:SetAllPoints()
	row.Band:SetColorTexture(1, 0.82, 0, 0.08)
	row.Picked = row:CreateTexture(nil, "BACKGROUND")
	row.Picked:SetAllPoints()
	row.Picked:SetColorTexture(1, 0.82, 0, 0.2)
	row.Toggle = row:CreateTexture(nil, "ARTWORK")
	row.Toggle:SetSize(14, 14)
	row.Toggle:SetPoint("LEFT", 2, 0)
	row.Dot = row:CreateTexture(nil, "ARTWORK")
	row.Dot:SetColorTexture(1, 1, 1)
	row.Dot:SetSize(7, 7)
	row.Dot:SetPoint("LEFT", 4, 0)
	local mask = row:CreateMaskTexture()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(row.Dot)
	row.Dot:AddMaskTexture(mask)
	row.Count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.Count:SetPoint("LEFT", 0, 0)
	row.Count:SetWidth(14)
	row.Count:SetJustifyH("RIGHT")
	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(16, 16)
	row.Icon:SetPoint("LEFT", 16, 0)
	row.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.Name:SetJustifyH("LEFT")
	row.Name:SetWordWrap(false)
	row.Right = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.Right:SetPoint("RIGHT", -4, 0)
	row.Right:SetJustifyH("RIGHT")
	row.Right:SetWordWrap(false)
	-- Hover fills the details at once, unless a clicked recipe keeps them.
	row:SetScript("OnEnter", function(self)
		if self.entry and not self.entry.header and not pinned then
			ShowEntry(self.entry)
		end
	end)
	row:SetScript("OnClick", function(self)
		local entry = self.entry
		if not entry then
			return
		end
		if entry.back then
			view.BackToResults()
		elseif entry.header then
			collapsed[entry.key] = not collapsed[entry.key] or nil
			view.middle:SetEntries(Flatten(), true)
			MarkPinned()
		elseif SameRecipe(entry, pinned) then
			pinned = nil -- (clicked again: hovering shows others again; this one until then)
			MarkPinned()
		else
			pinned = entry
			ShowEntry(entry)
			MarkPinned()
		end
	end)
	return row
end

---------------------------------------------------------------------------
-- The people on the left, the buttons on top
---------------------------------------------------------------------------

local function ResolvePerson()
	person = nil
	local mine
	for _, who in ipairs(people) do
		if personPicked and who.id == personId then
			person = who
			return
		end
		mine = mine or (who.mine and who) or nil
	end
	if personPicked and personId == EVERYONE then
		return
	end
	personPicked = false
	person = mine
	personId = mine and mine.id or EVERYONE
end

local function DrawPeople(offset)
	local entries = {}
	if people[1] then
		entries[1] = { everyone = true }
		for _, who in ipairs(people) do
			entries[#entries + 1] = who
		end
	end
	view.people:SetEntries(entries, offset)
end

function DrawButtons()
	for i, prof in ipairs(profs) do
		local button = view.profs[i]
		if not button then
			button = view.NewProfButton(i)
			view.profs[i] = button
		end
		button.line = prof.line
		button.Icon:SetTexture(prof.icon)
		button.Name:SetText(prof.name)
		button.Count:SetText(tostring(prof.count or 0))
		local nobody = (prof.count or 0) == 0
		button.Name:SetTextColor(nobody and 0.5 or 1, nobody and 0.5 or 1, nobody and 0.5 or 1)
		local searching = query ~= "" and next(litLines) ~= nil -- (their professions light up, the rest dim)
		button.Picked:SetShown((searching and litLines[prof.line] == true) or (prof.line == line and (not searching or drilled == true)))
		button:SetAlpha((searching and not litLines[prof.line]) and 0.35 or 1)
		button:Show()
	end
	for i = #profs + 1, #view.profs do
		view.profs[i]:Hide()
	end
end

-- The first profession with people, one of mine if I have any.
local function DefaultLine(R)
	local first
	for _, prof in ipairs(profs) do
		if (prof.count or 0) > 0 then
			first = first or prof.line
			for _, who in ipairs(R.People(prof.line)) do
				if who.mine then
					return prof.line
				end
			end
		end
	end
	return first or (profs[1] and profs[1].line)
end

local function DrawAll()
	local R = C.Recipes
	view.drawnRecipes, view.drawnRevision, lastDraw = R, R and R.Revision(), GetTime()
	view.draws = view.draws + 1
	profs = R and R.Professions() or {}
	local still = false
	for _, prof in ipairs(profs) do
		still = still or prof.line == line
	end
	if R and not (linePicked and still) then
		linePicked = false
		line = DefaultLine(R)
	end
	people = R and line and R.People(line) or {}
	ResolvePerson()
	DrawButtons()
	DrawPeople(true)
	DrawMiddle(true)
	if shown then
		FillDetail()
	end
end

-- A click during a search: the search stays, and this is looked at inside it.
local function Drill()
	if query ~= "" then
		drilled = true
	end
end

-- A new selection: the list from the top, the details empty.
local function DrawSelection()
	pinned, shown = nil, nil
	ResolvePerson()
	DrawButtons()
	DrawPeople(true)
	DrawMiddle(0)
	FillDetail()
end

local function SelectProfession(picked)
	if picked == line and (query == "" or drilled) then
		return
	end
	Drill()
	local R = C.Recipes
	line, linePicked, personPicked = picked, true, false
	people = R and R.People(line) or {}
	-- (searching for a person: them, if they have it)
	for _, match in ipairs(query ~= "" and R and R.SearchPeople and R.SearchPeople(query) or {}) do
		local has = false
		for _, who in ipairs(people) do
			has = has or who.id == match.who.id
		end
		if has then
			personId, personPicked = match.who.id, true
			break
		end
	end
	view.people.scroll:SetVerticalScroll(0)
	DrawSelection()
end

local function SelectPerson(id)
	if id == personId and (query == "" or drilled) then
		return
	end
	Drill()
	personId, personPicked = id, true
	DrawSelection()
end

-- The search's results again.
local function BackToResults()
	drilled = nil
	pinned, shown = nil, nil
	DrawMiddle(0)
	DrawButtons()
	FillDetail()
end

-- A found person's profession, clicked: its recipes, inside the search.
local function OpenPerson(picked, id)
	Drill()
	local R = C.Recipes
	line, linePicked, personId, personPicked = picked, true, id, true
	people = R and R.People(line) or {}
	view.people.scroll:SetVerticalScroll(0)
	DrawSelection()
end

local function FillPersonRow(row, entry)
	row.entry = entry
	row.Line:SetShown(entry.everyone == true)
	if entry.everyone then
		row.Name:SetText(L["Everyone"])
		row.Skill:SetText("")
		row.Sub:SetText("")
		row.Picked:SetShown(personId == EVERYONE)
		return
	end
	row.Name:SetText(NameText(entry))
	row.Skill:SetText(tostring(entry.skill or ""))
	row.Picked:SetShown(entry.id == personId)
	local parts = {}
	parts[#parts + 1] = entry.account
	if entry.level then
		parts[#parts + 1] = L["lvl %d"]:format(entry.level)
	end
	if entry.updated and time() - entry.updated > STALE_AFTER then
		parts[#parts + 1] = C.Ago(entry.updated)
	end
	row.Sub:SetText(table.concat(parts, " - "))
end

local function NewPersonRow(parent, width, height)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(width, height)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row.Picked = row:CreateTexture(nil, "BACKGROUND")
	row.Picked:SetAllPoints()
	row.Picked:SetColorTexture(1, 0.82, 0, 0.2)
	row.Line = row:CreateTexture(nil, "ARTWORK")
	row.Line:SetColorTexture(1, 0.82, 0, 0.3)
	row.Line:SetHeight(1)
	row.Line:SetPoint("BOTTOMLEFT")
	row.Line:SetPoint("BOTTOMRIGHT")
	row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.Name:SetPoint("TOPLEFT", 4, -3)
	row.Name:SetPoint("RIGHT", -30, 0)
	row.Name:SetJustifyH("LEFT")
	row.Name:SetWordWrap(false)
	row.Skill = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.Skill:SetPoint("TOPRIGHT", -4, -3)
	row.Sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.Sub:SetPoint("BOTTOMLEFT", 4, 3)
	row.Sub:SetPoint("RIGHT", -2, 0)
	row.Sub:SetJustifyH("LEFT")
	row.Sub:SetWordWrap(false)
	row:SetScript("OnClick", function(self)
		local entry = self.entry
		if entry then
			SelectPerson(entry.everyone and EVERYONE or entry.id)
		end
	end)
	return row
end

---------------------------------------------------------------------------
-- The search, and what comes later
---------------------------------------------------------------------------

local function RunDue(self)
	local now = GetTime()
	if searchAt and now >= searchAt then
		searchAt = nil
		local text = strtrim(view.Box:GetText() or "")
		if text ~= "" then
			if query == "" then -- (a search begins: this is where clearing it goes back to)
				beforeSearch = { offset = view.middle.scroll:GetVerticalScroll() or 0, pinned = pinned, shown = shown }
			end
			if text ~= query then
				query, drilled = text, nil
				pinned, shown = nil, nil
				DrawMiddle(0)
				FillDetail()
			end
		end
	end
	if fillAt and now >= fillAt then
		fillAt = nil
		if namesOld then
			view.middle:Lay()
			if shown and shown.recipe then
				FillHead(shown.recipe)
				FillReagents(shown.recipe)
				if tipCame then
					ShowTip(shown.recipe)
				end
			end
		elseif bagsOld and shown and shown.recipe then
			FillReagents(shown.recipe)
		end
		if shown and shown.recipe and (gearOld or tipCame) then -- (what I wear changed; the item came: it can compare now)
			FillCompare(shown.recipe)
			LayBelow(shown.recipe)
			FitTip()
		end
		namesOld, bagsOld, tipCame, gearOld = false, false, false, false
	end
	if not (searchAt or fillAt) then
		self:SetScript("OnUpdate", nil)
	end
end

local function Due()
	view.root:SetScript("OnUpdate", RunDue) -- (only while something is due, only while in sight)
end

-- Emptied: back to where it was, at once.
local function EndSearch()
	searchAt = nil
	if query == "" then
		return
	end
	query = ""
	wipe(litLines)
	DrawButtons()
	local before = beforeSearch or {}
	beforeSearch = nil
	if drilled then -- (it stays on what was clicked last)
		drilled, pinned, shown = nil, nil, nil
		DrawMiddle(0)
	else
		pinned, shown = before.pinned, before.shown
		DrawMiddle(before.offset or 0)
	end
	FillDetail()
end

local function OnSearchTyped(box)
	local text = strtrim(box:GetText() or "")
	view.Clear:SetShown(text ~= "")
	if text == "" then
		EndSearch()
	elseif text ~= query then
		searchAt = GetTime() + SEARCH_GAP
		Due()
	else
		searchAt = nil
	end
end

local function OnEvent(_, event, id)
	if event == "GET_ITEM_INFO_RECEIVED" then
		if LT.IsSecret(id) or not waiting[id] then
			return
		end
		waiting[id] = nil
		namesOld = true
		tipCame = tipCame or (shown ~= nil and shown.recipe ~= nil and shown.recipe.item == id)
		fillAt = fillAt or GetTime() + NAMES_GAP
		Due()
	elseif shown then -- BAG_UPDATE_DELAYED: the "(you: 12)" lines; PLAYER_EQUIPMENT_CHANGED: the comparison
		bagsOld = true
		gearOld = gearOld or event == "PLAYER_EQUIPMENT_CHANGED"
		fillAt = fillAt or GetTime() + NAMES_GAP
		Due()
	end
end

---------------------------------------------------------------------------
-- The frames
---------------------------------------------------------------------------

local function BuildSearch(root)
	local label = root:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("TOPLEFT", PAD + 2, -SEARCH_Y - 5)
	label:SetText(L["Search everyone:"])
	local box = CreateFrame("EditBox", "LefthyToolsProfessionsSearch", root)
	view.Box = box
	box:SetSize(280, SEARCH_H - 2)
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
	view.Clear:SetScript("OnClick", function() box:SetText("") OnSearchTyped(box) end)
	view.Clear:Hide()
	box:SetScript("OnTextChanged", OnSearchTyped)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
end

-- A profession's button: its icon, its name, how many have it; the chosen one in gold.
local function ProfButtonMaker(root, width)
	local buttonW = math.floor((width - 2 * PAD - (PROF_PER_ROW - 1) * PROF_GAP) / PROF_PER_ROW)
	return function(i)
		local button = CreateFrame("Button", nil, root)
		button:SetSize(buttonW, PROF_H)
		button:SetPoint("TOPLEFT", PAD + ((i - 1) % PROF_PER_ROW) * (buttonW + PROF_GAP),
			-PROF_Y - math.floor((i - 1) / PROF_PER_ROW) * (PROF_H + PROF_GAP))
		button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		local back = button:CreateTexture(nil, "BACKGROUND")
		back:SetAllPoints()
		back:SetColorTexture(0, 0, 0, 0.45)
		button.Picked = button:CreateTexture(nil, "BORDER")
		button.Picked:SetAllPoints()
		button.Picked:SetColorTexture(1, 0.82, 0, 0.3)
		button.Icon = button:CreateTexture(nil, "ARTWORK")
		button.Icon:SetSize(18, 18)
		button.Icon:SetPoint("LEFT", 3, 0)
		button.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		button.Name = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		button.Name:SetPoint("LEFT", 24, 0)
		button.Name:SetPoint("RIGHT", -18, 0)
		button.Name:SetJustifyH("LEFT")
		button.Name:SetWordWrap(false)
		button.Count = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		button.Count:SetPoint("RIGHT", -4, 0)
		button:SetScript("OnClick", function(self) SelectProfession(self.line) end)
		return button
	end
end

local function NewReagentRow(parent, i)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(view.detailW, REAGENT_H)
	row:SetPoint("TOPLEFT", 0, -16 - (i - 1) * REAGENT_H)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(15, 15)
	row.Icon:SetPoint("LEFT", 2, 0)
	row.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Name:SetPoint("LEFT", 21, 0)
	row.Name:SetPoint("RIGHT", -86, 0)
	row.Name:SetJustifyH("LEFT")
	row.Name:SetWordWrap(false)
	row.Have = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Have:SetPoint("RIGHT", -2, 0)
	row.Have:SetWidth(60)
	row.Have:SetJustifyH("RIGHT")
	row.Count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Count:SetPoint("RIGHT", row.Have, "LEFT", -4, 0)
	-- Hovered: its normal tooltip, beside the window.
	row:SetScript("OnEnter", function(self)
		if self.id then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(("item:%d"):format(self.id))
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function(self)
		if GameTooltip:IsOwned(self) then
			GameTooltip:Hide()
		end
	end)
	row:Hide()
	return row
end

-- One of a found person's professions: a click selects it, with them.
local function NewPersonProfRow(parent, i)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(view.detailW - 4, PERSON_ROW_H)
	row:SetPoint("TOPLEFT", 2, -44 - (i - 1) * PERSON_ROW_H)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(16, 16)
	row.Icon:SetPoint("LEFT", 2, 0)
	row.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Name:SetPoint("LEFT", 22, 0)
	row.Name:SetPoint("RIGHT", -96, 0)
	row.Name:SetJustifyH("LEFT")
	row.Name:SetWordWrap(false)
	row.Count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.Count:SetPoint("RIGHT", -2, 0)
	row.Count:SetWidth(60)
	row.Count:SetJustifyH("RIGHT")
	row.Skill = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Skill:SetPoint("RIGHT", row.Count, "LEFT", -4, 0)
	row:SetScript("OnClick", function(self)
		if self.line then
			view.OpenPerson(self.line, self.who)
		end
	end)
	return row
end

-- "Replaces: <what I wear>" and the game's stat lines under it. Hovered: its tooltip, beside the window.
local function NewCompareRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(view.detailW, COMPARE_H)
	row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.Name:SetPoint("TOPLEFT", 2, -1)
	row.Name:SetPoint("RIGHT", -2, 0)
	row.Name:SetJustifyH("LEFT")
	row.Name:SetWordWrap(false)
	row.Lines = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Lines:SetPoint("TOPLEFT", 12, -COMPARE_H)
	row.Lines:SetWidth(view.detailW - 14)
	row.Lines:SetJustifyH("LEFT")
	row:SetScript("OnEnter", function(self)
		local worn = self.worn
		local link = worn and (worn.hyperlink or LT.Value(C_Item.GetItemLinkByGUID, worn.guid))
		if link then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(link)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function(self)
		if GameTooltip:IsOwned(self) then
			GameTooltip:Hide()
		end
	end)
	return row
end

local function BuildDetail(root, x, width, height)
	view.detailW, view.detailH = width, height
	local panel = CreateFrame("Frame", nil, root)
	view.Detail = panel
	panel:SetPoint("TOPLEFT", x, -PANES_Y)
	panel:SetSize(width, height)
	view.Hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	view.Hint:SetPoint("TOPLEFT", 4, -8)
	view.Hint:SetWidth(width - 8)
	view.Hint:SetJustifyH("LEFT")
	view.Hint:SetText(L["Hover a recipe to see it here, click it to keep it here."])
	local body = CreateFrame("Frame", nil, panel)
	view.DetailBody = body
	body:SetAllPoints()
	view.Icon = body:CreateTexture(nil, "ARTWORK")
	view.Icon:SetSize(32, 32)
	view.Icon:SetPoint("TOPLEFT", 2, -2)
	view.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	view.Name = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	view.Name:SetPoint("TOPLEFT", 40, -2)
	view.Name:SetPoint("RIGHT", 0, 0)
	view.Name:SetJustifyH("LEFT")
	view.Name:SetWordWrap(false)
	view.Difficulty = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	view.Difficulty:SetPoint("TOPLEFT", 40, -20)
	view.Difficulty:SetPoint("RIGHT", 0, 0)
	view.Difficulty:SetJustifyH("LEFT")
	view.Difficulty:SetWordWrap(false)
	view.TipClip = CreateFrame("Frame", nil, body)
	view.TipClip:SetPoint("TOPLEFT", 0, -HEAD_H)
	view.TipClip:SetSize(width, 1)
	if view.TipClip.SetClipsChildren then
		view.TipClip:SetClipsChildren(true)
	end
	view.Below = CreateFrame("Frame", nil, body)
	view.Below:SetPoint("TOPLEFT", view.TipClip, "BOTTOMLEFT", 0, -6)
	view.Below:SetSize(width, 1)
	view.compare = {}
	for i = 1, COMPARE_ROWS do
		view.compare[i] = NewCompareRow(view.Below)
	end
	view.NeedsBox = CreateFrame("Frame", nil, view.Below)
	view.NeedsBox:SetSize(width, 1)
	view.Needs = view.NeedsBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	view.Needs:SetPoint("TOPLEFT", 2, 0)
	view.Needs:SetText(L["Needs:"])
	view.reagents = {}
	for i = 1, REAGENTS do
		view.reagents[i] = NewReagentRow(view.NeedsBox, i)
	end
	view.Also = view.Below:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	view.Also:SetWidth(width - 4)
	view.Also:SetJustifyH("LEFT")
	view.OpenMine = LT.Window.AddButton(body, L["Show in my profession window"], OpenInMine, { "BOTTOMLEFT", body, "BOTTOMLEFT", 2, 2 })
	view.OpenMine:SetSize(math.min(width - 4, 220), 22)
	view.OpenMine:Hide()
	body:Hide()
	local box = CreateFrame("Frame", nil, panel)
	view.PersonBox = box
	box:SetAllPoints()
	box.Name = box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	box.Name:SetPoint("TOPLEFT", 4, -4)
	box.Name:SetPoint("RIGHT", -4, 0)
	box.Name:SetJustifyH("LEFT")
	box.Name:SetWordWrap(false)
	box.Sub = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	box.Sub:SetPoint("TOPLEFT", 4, -24)
	box.Sub:SetPoint("RIGHT", -4, 0)
	box.Sub:SetJustifyH("LEFT")
	box.rows = {}
	for i = 1, PERSON_PROFS do
		box.rows[i] = NewPersonProfRow(box, i)
	end
	box:Hide()
end

local function Build(parent, width, height)
	local root = CreateFrame("Frame", nil, parent)
	view = { root = root, profs = {}, draws = 0, groupings = 0 }
	root:SetPoint("TOPLEFT")
	root:SetSize(width, height)
	root:SetScript("OnEvent", OnEvent)
	root:SetScript("OnShow", function(self)
		self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
		self:RegisterEvent("BAG_UPDATE_DELAYED")
		self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
		if tipOld and shown then
			FillDetail()
		end
	end)
	root:SetScript("OnHide", function(self)
		self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
		self:UnregisterEvent("BAG_UPDATE_DELAYED")
		self:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")
	end)
	BuildSearch(root)
	view.NewProfButton = ProfButtonMaker(root, width)
	local paneH = height - PANES_Y - PAD
	local middleX = PAD + PEOPLE_W + GAP
	view.people = NewList(root, PAD, PANES_Y, PEOPLE_W - BAR_W, paneH, PERSON_H, NewPersonRow, FillPersonRow)
	view.middle = NewList(root, middleX, PANES_Y, MIDDLE_W - BAR_W, paneH, ITEM_H, NewItemRow, FillItemRow)
	view.Message = root:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	view.Message:SetPoint("TOPLEFT", middleX + 4, -PANES_Y - 8)
	view.Message:SetWidth(MIDDLE_W - BAR_W - 8)
	view.Message:SetJustifyH("LEFT")
	view.Message:Hide()
	for _, x in ipairs({ middleX - GAP / 2, middleX + MIDDLE_W + GAP / 2 }) do
		local split = root:CreateTexture(nil, "ARTWORK")
		split:SetColorTexture(1, 0.82, 0, 0.2)
		split:SetWidth(1)
		split:SetPoint("TOPLEFT", x, -PANES_Y)
		split:SetHeight(paneH)
	end
	view.OpenPerson, view.BackToResults = OpenPerson, BackToResults
	local detailX = middleX + MIDDLE_W + GAP
	BuildDetail(root, detailX, width - detailX - PAD - EDGE, paneH)
end

---------------------------------------------------------------------------
-- What the window calls
---------------------------------------------------------------------------

-- The tab opened: drawn again only when the data moved since last time.
function C.DrawProfessions(parent, width, height)
	if not view then
		Build(parent, width, height)
	end
	view.root:Show()
	local R = C.Recipes
	if view.draws == 0 or view.drawnRecipes ~= R or (R and R.Revision() ~= view.drawnRevision) then
		DrawAll()
	elseif shown then
		FillDetail() -- (the bags may have changed while it was closed)
	end
end

function C.HideProfessions()
	if not view then
		return
	end
	view.Box:ClearFocus()
	HideTip()
	tipOld = shown ~= nil -- (back with the tab)
	view.root:Hide()
end

-- Every second while the tab is open: only when the lists moved, at most every few seconds, and
-- not at the start of a fight (a click still draws).
function C.ProfessionsTick()
	local R = view and C.Recipes
	if R and view.root:IsVisible() and R.Revision() ~= view.drawnRevision
		and GetTime() - lastDraw >= REDRAW_GAP and not LT.InFight() then
		DrawAll()
	end
end

-- The tab's frames and counters (for the tests).
function C.ProfessionsView()
	return view
end
