local _, ns = ...
local LT = ns.LT
local L = ns.L
local Bt = ns.Bestiary
local M = Bt.module

-- The Bestiary's ledger: every kind of mob you've killed, with its statistics and drops, and one
-- search over mobs and items. On the left the mobs (name, level, kind, your kills, their best drops
-- as tiny icons), sorted by kills, name, level, coin or when you last killed one. On the right the
-- one picked: its whole model turning slowly, kills, coin, first and last kill, skinnings, and all
-- its drops (as in the window: quality edge, how many, chance; skinning marked). At the top what
-- the Bestiary knows in all, and your rarest find.
--
-- The search is fuzzy: a query's letters in order, not necessarily together ("dfbnd" finds Defias
-- Bandit), case and spaces ignored. Letters together, at a word's start and early count more. It
-- looks at mob names and at the names of everything they dropped: a mob found by one of its items
-- shows that item and its chance in its row, and the picked mob's matching drops stand out.
-- Escape closes it (it's for looking things up, unlike the window, which stays).

local WIDTH, HEIGHT = 640, 470
local PAD = 12
local LIST_W, ROW_H = 282, 36
local TOP = 104             -- where the list and the picked mob start
local MODEL_W, MODEL_H = 112, 132
local CELL, CELL_GAP, PER_ROW, ROWS = 28, 6, 9, 5
local ROW_ICONS = 6
local GOLD = { 1, 0.82, 0.3 }
local SORTS = { "kills", "name", "level", "coin", "last" }
local issecret = issecretvalue or function() return false end

local ledger
local entries = {}       -- the list as shown: { creature, mob, score, positions, items (found by the search) }
local selected           -- the picked creature
local query = ""         -- the search, lower case, without spaces
local sortBy = "kills"
local namesWanted = false -- an item's name was asked for (the list redraws when it comes)

---------------------------------------------------------------------------
-- The search
---------------------------------------------------------------------------

-- How well the query matches a text: nil when its letters aren't all in it in order; else a score
-- (letters together, at a word's start, early, in a short text: more) and where they are.
local function Fuzzy(q, text)
	if q == "" or type(text) ~= "string" then
		return nil
	end
	local lower = text:lower()
	local score, from, run, positions = 0, 1, 0, {}
	for i = 1, #q do
		local at = lower:find(q:sub(i, i), from, true)
		if not at then
			return nil
		end
		run = (i > 1 and at == from) and run + 1 or 0
		local wordStart = at == 1 or lower:sub(at - 1, at - 1):find("[%s%-%(%.']") ~= nil
		score = score + 1 + run * 3 + (wordStart and 4 or 0)
		positions[#positions + 1] = at
		from = at + 1
	end
	return score - (positions[1] - 1) * 0.2 - #lower * 0.02, positions
end
Bt.Fuzzy = Fuzzy

-- The name with the found letters in gold (only plain-letter names: a letter of several bytes
-- can't be coloured on its own).
local function Marked(name, positions)
	if not positions or name:find("[\128-\255]") then
		return name
	end
	local marked, last = {}, 0
	for _, at in ipairs(positions) do
		marked[#marked + 1] = name:sub(last + 1, at - 1)
		marked[#marked + 1] = "|cffffd100" .. name:sub(at, at) .. "|r"
		last = at
	end
	marked[#marked + 1] = name:sub(last + 1)
	return table.concat(marked)
end

-- An item's name: as it was looted, else the client's (asked for when it doesn't know it yet).
local function NameOf(id, item)
	if not item then
		return nil
	elseif item[4] then
		return item[4]
	end
	local ok, name = false, nil
	if C_Item and C_Item.GetItemInfo then
		ok, name = pcall(C_Item.GetItemInfo, ("item:%d"):format(id))
	end
	if ok and type(name) == "string" and not issecret(name) then
		item[4] = name
		return name
	end
	if C_Item and C_Item.RequestLoadItemDataByID then
		pcall(C_Item.RequestLoadItemDataByID, id)
		namesWanted = true
	end
end

local SORT_KEYS = {
	kills = function(mob) return -mob.kills end,
	name = function(mob) return (mob.name or "~"):lower() end,
	level = function(mob) return -(mob.level or 0) end,
	coin = function(mob) return mob.kills > 0 and -(mob.money / mob.kills) or 0 end,
	last = function(mob) return -(mob.last or 0) end,
}

-- The list: everything (sorted) or what the search finds (the best match first).
local function Collect()
	wipe(entries)
	local key = SORT_KEYS[sortBy] or SORT_KEYS.kills
	for creature, mob in pairs(LefthyToolsBestiaryDB and LefthyToolsBestiaryDB.mobs or {}) do
		if mob.kills > 0 or (mob.skinned or 0) > 0 then
			local entry = { creature = creature, mob = mob, sort = key(mob) }
			if query ~= "" then
				local score, positions = Fuzzy(query, mob.name)
				entry.positions = positions
				local found = {}
				for _, skin in ipairs({ false, true }) do
					for id, item in pairs(Bt.Part(mob, skin)) do
						local itemScore = Fuzzy(query, NameOf(id, item))
						if itemScore then
							found[#found + 1] = { id = id, score = itemScore, skin = skin, chance = Bt.Chance(mob, item, skin), quality = item[3] }
						end
					end
				end
				table.sort(found, function(a, b) return a.score > b.score end)
				entry.items = #found > 0 and found or nil
				local best = math.max(score or -math.huge, found[1] and found[1].score * 0.95 or -math.huge)
				if best > -math.huge then
					entry.score = best
					entries[#entries + 1] = entry
				end
			else
				entries[#entries + 1] = entry
			end
		end
	end
	table.sort(entries, function(a, b)
		if a.score and b.score and a.score ~= b.score then
			return a.score > b.score
		elseif a.sort ~= b.sort then
			return a.sort < b.sort
		end
		return a.creature < b.creature
	end)
end

---------------------------------------------------------------------------
-- What the Bestiary knows in all, and your rarest find
---------------------------------------------------------------------------

local function Totals()
	local mobs, kills, coin, items = 0, 0, 0, {}
	local rarest
	for creature, mob in pairs(LefthyToolsBestiaryDB and LefthyToolsBestiaryDB.mobs or {}) do
		mobs, kills, coin = mobs + 1, kills + mob.kills, coin + mob.money
		for id, item in pairs(mob.items) do
			items[id] = true
			local chance = Bt.Chance(mob, item)
			-- (the rarest: the lowest chance, from enough kills to mean something)
			if mob.kills >= 5 and (not rarest or chance < rarest.chance) then
				rarest = { id = id, item = item, chance = chance, mob = mob, creature = creature }
			end
		end
		for id in pairs(mob.skins or {}) do
			items[id] = true
		end
	end
	local count = 0
	for _ in pairs(items) do
		count = count + 1
	end
	return mobs, kills, count, coin, rarest
end

---------------------------------------------------------------------------
-- A mob's row
---------------------------------------------------------------------------

local function Select(creature)
	selected = creature
	Bt.DrawLedger()
end

local function NewRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(LIST_W - 26, ROW_H)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row.Picked = row:CreateTexture(nil, "BACKGROUND")
	row.Picked:SetAllPoints()
	row.Picked:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.14)
	row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.Name:SetPoint("TOPLEFT", 6, -4)
	row.Name:SetPoint("RIGHT", -46, 0)
	row.Name:SetJustifyH("LEFT")
	row.Name:SetWordWrap(false)
	row.Kills = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.Kills:SetPoint("TOPRIGHT", -6, -4)
	row.KillsLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.KillsLabel:SetPoint("TOPRIGHT", row.Kills, "BOTTOMRIGHT", 0, -1)
	row.KillsLabel:SetTextScale(0.85)
	row.icons = {}
	for i = 1, ROW_ICONS do
		local icon = row:CreateTexture(nil, "ARTWORK")
		icon:SetSize(14, 14)
		icon:SetPoint("TOPLEFT", 6 + (i - 1) * 17, -19)
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		row.icons[i] = icon
	end
	row.Found = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Found:SetPoint("LEFT", row.icons[1], "RIGHT", 4, 0)
	row.Found:SetPoint("RIGHT", -46, 0)
	row.Found:SetJustifyH("LEFT")
	row.Found:SetWordWrap(false)
	row:SetScript("OnClick", function(self) Select(self.creature) end)
	return row
end

-- Its best drops as tiny icons (the best quality first, then the likeliest), or what the search
-- found among its drops: the best one's icon, name and chance.
local function FillRow(row, entry)
	local mob = entry.mob
	row.creature = entry.creature
	local tag = mob.class == "elite" and (" |cffffd100" .. L["Elite"] .. "|r") or mob.class == "rare" and (" |cffc0c0ff" .. L["Rare"] .. "|r")
		or mob.class == "rareelite" and (" |cffc0c0ff" .. L["Rare elite"] .. "|r") or ""
	local name = Marked(mob.name or ("#" .. entry.creature), entry.positions)
	row.Name:SetText(name .. (mob.level and mob.level > 0 and (" |cff888888" .. mob.level .. "|r") or "") .. tag)
	row.Kills:SetText(tostring(mob.kills))
	row.KillsLabel:SetText(mob.kills == 1 and L["kill"] or L["kills"])
	row.Picked:SetShown(entry.creature == selected)
	for _, icon in ipairs(row.icons) do
		icon:Hide()
	end
	if entry.items then
		local found = entry.items[1]
		local r, g, b = Bt.QualityColor(found.quality)
		row.icons[1]:SetTexture(Bt.ItemIcon(found.id))
		row.icons[1]:Show()
		row.Found:SetText(("|cff%02x%02x%02x%s|r  %s%s"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5),
			NameOf(found.id, Bt.Part(mob, found.skin)[found.id]) or "?",
			Bt.Percent(found.chance), found.skin and (" |T%s:12:12|t"):format(Bt.SKIN_ICON) or "")
			.. (#entry.items > 1 and ("  |cff888888+" .. (#entry.items - 1) .. "|r") or ""))
		row.Found:Show()
	else
		row.Found:Hide()
		local best = Bt.Drops(mob, M.db.showPoor)
		table.sort(best, function(a, b)
			if a.quality ~= b.quality then
				return a.quality > b.quality
			end
			return a.chance > b.chance
		end)
		for i = 1, math.min(ROW_ICONS, #best) do
			row.icons[i]:SetTexture(Bt.ItemIcon(best[i].id))
			row.icons[i]:Show()
		end
	end
	row:Show()
end

---------------------------------------------------------------------------
-- The picked mob
---------------------------------------------------------------------------

local function Ago(t)
	local seconds = math.max(0, time() - (t or 0))
	if seconds < 120 then
		return L["just now"]
	elseif seconds < 3600 then
		return L["%d min ago"]:format(math.floor(seconds / 60))
	elseif seconds < 86400 then
		return L["%d h ago"]:format(math.floor(seconds / 3600))
	elseif seconds < 2 * 86400 then
		return L["yesterday"]
	end
	return L["%d days ago"]:format(math.floor(seconds / 86400))
end

local function DrawPicked()
	local pane, mob = ledger.Pane, Bt.Mob(selected)
	pane:SetShown(mob ~= nil)
	ledger.Empty:SetShown(mob == nil)
	if not mob then
		return
	end
	if pane.creature ~= selected then
		pane.creature, pane.facing = selected, 0.4
		pane.Model:ClearModel()
		pane.Model:SetCreature(selected)
	end
	pane.Name:SetText(mob.name or ("#" .. selected))
	pane.Kind:SetText(Bt.Kind({ level = mob.level, class = mob.class }))
	local lines = { (mob.kills == 1 and L["1 kill"] or L["%d kills"]:format(mob.kills)) }
	if mob.kills > 0 then
		lines[#lines + 1] = mob.money > 0 and L["%s each, %s in all"]:format(Bt.Coins(mob.money / mob.kills), Bt.Coins(mob.money))
			or L["no coin"]
	end
	if mob.first then
		lines[#lines + 1] = L["First: %s"]:format(Ago(mob.first))
	end
	if mob.last then
		lines[#lines + 1] = L["Last: %s"]:format(Ago(mob.last))
	end
	if (mob.skinned or 0) > 0 then
		lines[#lines + 1] = ("|T%s:12:12|t "):format(Bt.SKIN_ICON) .. L["Skinned %d times"]:format(mob.skinned)
	end
	pane.Stats:SetText(table.concat(lines, "\n"))
	local drops = Bt.Drops(mob, M.db.showPoor)
	pane.Heading:SetText(L["Drops (%d)"]:format(#drops))
	Bt.Lay(pane.Grid, pane.cells, drops, mob.kills, CELL, CELL_GAP, PER_ROW, PER_ROW * ROWS, true)
	-- What the search found stands out; the rest steps back.
	local found = {}
	for _, entry in ipairs(entries) do
		if entry.creature == selected and entry.items then
			for _, item in ipairs(entry.items) do
				found[item.id] = true
			end
		end
	end
	for _, cell in ipairs(pane.cells) do
		cell:SetAlpha((not next(found) or (cell.drop and found[cell.drop.id])) and 1 or 0.35)
	end
end

---------------------------------------------------------------------------
-- Drawing it all
---------------------------------------------------------------------------

function Bt.DrawLedger()
	if not (ledger and ledger:IsShown()) then
		return
	end
	local mobs, kills, items, coin, rarest = Totals()
	ledger.Summary:SetText(L["%d mobs  ·  %d kills  ·  %d items  ·  %s coin, %s per kill"]:format(mobs, kills, items, Bt.Coins(coin),
		Bt.Coins(kills > 0 and coin / kills or 0)))
	if rarest then
		ledger.Rarest:SetText(L["Rarest find: %s, %s from %s"]:format(("|T%s:14:14|t %s"):format(Bt.ItemIcon(rarest.id),
			NameOf(rarest.id, rarest.item) or "?"), Bt.Percent(rarest.chance), rarest.mob.name or ("#" .. rarest.creature)))
	else
		ledger.Rarest:SetText("")
	end
	Collect()
	if not selected or not Bt.Mob(selected) or (query ~= "" and entries[1] and not ledger.keepPick) then
		selected = entries[1] and entries[1].creature or selected
	end
	local rows = ledger.rows
	for i, entry in ipairs(entries) do
		rows[i] = rows[i] or NewRow(ledger.ListContent)
		rows[i]:ClearAllPoints()
		rows[i]:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
		FillRow(rows[i], entry)
	end
	for i = #entries + 1, #rows do
		rows[i]:Hide()
	end
	ledger.ListContent:SetHeight(math.max(1, #entries * ROW_H))
	ledger.NoMatch:SetShown(#entries == 0)
	ledger.NoMatch:SetText(query ~= "" and L["Nothing found."] or L["No mobs yet: kill something on your own and loot it."])
	DrawPicked()
end

local function Search(text)
	query = (text or ""):lower():gsub("%s", "")
	ledger.keepPick = false
	ledger.Placeholder:SetShown(text == nil or text == "")
	ledger.Clear:SetShown(text ~= nil and text ~= "")
	ledger.List:SetVerticalScroll(0)
	Bt.DrawLedger()
end

---------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------

local SORT_LABELS = { kills = L["Most kills"], name = L["Name"], level = L["Level"], coin = L["Coin per kill"], last = L["Last killed"] }

local function Build()
	ledger = CreateFrame("Frame", "LefthyToolsBestiaryLedger", UIParent)
	ledger:SetSize(WIDTH, HEIGHT)
	ledger:SetPoint("CENTER")
	ledger:SetFrameStrata("HIGH")
	ledger:SetToplevel(true)
	ledger:SetClampedToScreen(true)
	ledger:EnableMouse(true)
	ledger:SetMovable(true)
	ledger:RegisterForDrag("LeftButton")
	ledger:SetScript("OnDragStart", ledger.StartMoving)
	ledger:SetScript("OnDragStop", ledger.StopMovingOrSizing)
	ledger:Hide()
	Bt.Dress(ledger)
	table.insert(UISpecialFrames, "LefthyToolsBestiaryLedger") -- (Escape closes it)
	LT.Window.Register("LefthyToolsBestiaryLedger")
	ledger.rows = {}

	ledger.Close = CreateFrame("Button", nil, ledger, "UIPanelCloseButtonNoScripts")
	ledger.Close:SetPoint("TOPRIGHT", -2, -2)
	ledger.Close:SetScript("OnClick", function() ledger:Hide() end)
	local title = ledger:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", PAD + 2, -12)
	title:SetText("Bestiary")
	local subtitle = ledger:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	subtitle:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 1)
	subtitle:SetText(L["the ledger"])
	ledger.Summary = ledger:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	ledger.Summary:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	ledger.Rarest = ledger:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	ledger.Rarest:SetPoint("TOPLEFT", ledger.Summary, "BOTTOMLEFT", 0, -4)

	-- The search: a box with a magnifier, a grey hint while empty, an x to clear it.
	local box = CreateFrame("EditBox", "LefthyToolsBestiarySearch", ledger)
	ledger.Search = box
	box:SetSize(LIST_W - 26, 22)
	box:SetPoint("TOPLEFT", PAD, -74)
	box:SetAutoFocus(false)
	box:SetFontObject("ChatFontNormal")
	box:SetMaxLetters(40)
	if box.SetTextInsets then
		box:SetTextInsets(22, 20, 0, 0)
	end
	local back = box:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.55)
	local edge = box:CreateTexture(nil, "BORDER")
	edge:SetPoint("BOTTOMLEFT")
	edge:SetPoint("BOTTOMRIGHT")
	edge:SetHeight(1)
	edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.5)
	local glass = box:CreateTexture(nil, "OVERLAY")
	glass:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
	glass:SetSize(14, 14)
	glass:SetPoint("LEFT", 5, -1)
	ledger.Placeholder = box:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	ledger.Placeholder:SetPoint("LEFT", 24, 0)
	ledger.Placeholder:SetText(L["Search mobs and items"])
	ledger.Clear = CreateFrame("Button", nil, box, "UIPanelCloseButtonNoScripts")
	ledger.Clear:SetSize(20, 20)
	ledger.Clear:SetPoint("RIGHT", 0, 0)
	ledger.Clear:SetScript("OnClick", function() box:SetText("") Search("") end)
	ledger.Clear:Hide()
	box:SetScript("OnTextChanged", function(self) Search(self:GetText()) end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

	-- The order: a picker of our own (Core/Window.lua).
	local sortLabel = ledger:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sortLabel:SetPoint("LEFT", box, "RIGHT", 18, 0)
	sortLabel:SetText(L["Sort:"])
	ledger.Sort = LT.Window.AddPicker(ledger, 130, function()
		local list = {}
		for _, key in ipairs(SORTS) do
			list[#list + 1] = { text = SORT_LABELS[key], value = key, selected = key == sortBy }
		end
		return list
	end, function(key)
		sortBy = key
		ledger.Sort:SetLabel(SORT_LABELS[key])
		Bt.DrawLedger()
	end)
	ledger.Sort:SetPoint("LEFT", sortLabel, "RIGHT", 6, 0)
	ledger.Sort:SetLabel(SORT_LABELS[sortBy])

	-- The list, scrolling.
	ledger.List = CreateFrame("ScrollFrame", nil, ledger, "UIPanelScrollFrameTemplate")
	ledger.List:SetPoint("TOPLEFT", PAD, -TOP)
	ledger.List:SetPoint("BOTTOMLEFT", PAD, PAD)
	ledger.List:SetWidth(LIST_W - 24)
	ledger.ListContent = CreateFrame("Frame", nil, ledger.List)
	ledger.ListContent:SetSize(LIST_W - 26, 1)
	ledger.List:SetScrollChild(ledger.ListContent)
	ledger.NoMatch = ledger:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	ledger.NoMatch:SetPoint("TOPLEFT", PAD + 4, -TOP - 8)
	ledger.NoMatch:SetWidth(LIST_W - 30)
	ledger.NoMatch:SetJustifyH("LEFT")
	local split = ledger:CreateTexture(nil, "ARTWORK")
	split:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.2)
	split:SetWidth(1)
	split:SetPoint("TOPLEFT", PAD + LIST_W, -TOP + 4)
	split:SetPoint("BOTTOMLEFT", PAD + LIST_W, PAD)

	-- The picked mob: its model turning slowly, its numbers, all its drops.
	local x = PAD + LIST_W + 14
	local pane = CreateFrame("Frame", nil, ledger)
	ledger.Pane = pane
	pane:SetPoint("TOPLEFT", x, -TOP)
	pane:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	local modelBack = pane:CreateTexture(nil, "BACKGROUND")
	modelBack:SetPoint("TOPLEFT")
	modelBack:SetSize(MODEL_W, MODEL_H)
	modelBack:SetColorTexture(0, 0, 0, 0.45)
	pane.Model = CreateFrame("PlayerModel", nil, pane)
	pane.Model:SetAllPoints(modelBack)
	pane.Model:SetPortraitZoom(0)
	pane.Model:SetScript("OnModelLoaded", function(self) self:RefreshCamera() end)
	pane.Name = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	pane.Name:SetPoint("TOPLEFT", modelBack, "TOPRIGHT", 12, -2)
	pane.Name:SetPoint("RIGHT", 0, 0)
	pane.Name:SetJustifyH("LEFT")
	pane.Name:SetWordWrap(false)
	pane.Kind = pane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	pane.Kind:SetPoint("TOPLEFT", pane.Name, "BOTTOMLEFT", 0, -3)
	pane.Stats = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pane.Stats:SetPoint("TOPLEFT", pane.Kind, "BOTTOMLEFT", 0, -8)
	pane.Stats:SetPoint("RIGHT", 0, 0)
	pane.Stats:SetJustifyH("LEFT")
	pane.Stats:SetSpacing(3)
	pane.Heading = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	pane.Heading:SetPoint("TOPLEFT", modelBack, "BOTTOMLEFT", 0, -12)
	local rule = pane:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
	rule:SetHeight(1)
	rule:SetPoint("LEFT", pane.Heading, "RIGHT", 8, 0)
	rule:SetPoint("RIGHT", pane, "RIGHT", 0, 0)
	pane.Grid = CreateFrame("Frame", nil, pane)
	pane.Grid:SetPoint("TOPLEFT", pane.Heading, "BOTTOMLEFT", 0, -8)
	pane.Grid:SetSize(PER_ROW * (CELL + CELL_GAP), ROWS * (CELL + 18))
	pane.cells = {}
	ledger.Empty = ledger:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	ledger.Empty:SetPoint("CENTER", pane, "CENTER", 0, 0)
	ledger.Empty:SetText(L["Pick a mob on the left."])

	-- The model turns slowly while the ledger is open (an OnUpdate only then).
	ledger:SetScript("OnUpdate", function(_, elapsed)
		if pane:IsShown() and pane.facing then
			pane.facing = pane.facing + elapsed * 0.35
			pane.Model:SetFacing(pane.facing)
		end
	end)
	ledger:SetScript("OnEvent", function(self, event)
		if event == "GET_ITEM_INFO_RECEIVED" and namesWanted and not self.redrawSoon then
			self.redrawSoon = true -- (names come in bunches: once, a moment later)
			C_Timer.After(0.5, function()
				self.redrawSoon, namesWanted = false, false
				Bt.DrawLedger()
			end)
		end
	end)
	ledger:SetScript("OnShow", function(self) self:RegisterEvent("GET_ITEM_INFO_RECEIVED") end)
	ledger:SetScript("OnHide", function(self)
		self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
		self.Search:ClearFocus()
	end)
end

-- Opens the ledger (on a creature, with a search), or closes it when it's open and nothing's asked.
function Bt.ToggleLedger(creature, search)
	if not M.enabled then
		return
	end
	if not ledger then
		Build()
	end
	if ledger:IsShown() and not creature and not search then
		ledger:Hide()
		return
	end
	if creature and Bt.Mob(creature) then
		selected = creature
	end
	ledger:Show()
	ledger.Search:SetText(search or "")
	query = (search or ""):lower():gsub("%s", "")
	ledger.keepPick = creature ~= nil and not search
	ledger.Placeholder:SetShown(query == "")
	ledger.Clear:SetShown(query ~= "")
	Bt.DrawLedger()
end

Bt.OnChanged(function()
	Bt.DrawLedger()
end)

-- For tests.
function Bt.Ledger()
	return ledger, entries, selected
end
