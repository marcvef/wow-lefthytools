local _, ns = ...
local LT = ns.LT
local L = ns.L
local Bt = ns.Bestiary
local M = Bt.module

-- The Bestiary's window: your target's drops. At the top the mob: a small still portrait, its
-- name, level and kind, your kills and the coin each brought. Under it its drops, the likeliest
-- first: an icon edged in its quality's colour, how many you got in its corner, the drop chance
-- under it; the item's tooltip with the numbers on hover, Shift-click links it. It follows your
-- target (a mob you can attack, or a dead one) and keeps the last when you clear it. It stays
-- open: Escape doesn't close it, only its X, the minimap button or /bestiary. Where it is and
-- whether it's open are kept.
--
-- The card next to the mouse (setting hoverCard): over an enemy you've killed before, your kills and
-- its likeliest drops, small, following the mouse while it's over it.

local WIDTH = 236
local PAD = 10
local ICON, GAP, PER_ROW, ROWS = 30, 8, 6, 4
local CELL_H = ICON + 16
local HEADER = 62
local PORTRAIT = 40
local LINE = 14
local CARD_ICON, CARD_GAP, CARD_CELLS = 22, 5, 6
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local BUTTON_ICON = "Interface\\Icons\\INV_Misc_Bag_10"
local GOLD = { 1, 0.82, 0.3 }
local issecret = issecretvalue or function() return false end

local win, card, button
local shown, shownInfo -- the creature the window shows, and what was seen of it (name, level, class)
local cardGUID
local ownTooltip = false -- showing our own drop's tooltip (it has the numbers already: no item tooltip lines)

local function Value(f, ...)
	if not f then
		return nil
	end
	local ok, v = pcall(f, ...)
	if ok and not issecret(v) then
		return v
	end
end

---------------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------------

local function QualityColor(quality)
	local f = C_Item and C_Item.GetItemQualityColor
	if f then
		local ok, r, g, b = pcall(f, quality or 1)
		if ok and type(r) == "number" then
			return r, g, b
		end
	end
	return 1, 1, 1
end

-- "35%", "3.4%", "<0.1%".
local function Percent(chance)
	local p = chance * 100
	if p >= 9.95 then
		return ("%d%%"):format(math.floor(p + 0.5))
	elseif p >= 0.05 then
		return ("%.1f%%"):format(p)
	end
	return "<0.1%"
end
Bt.Percent = Percent

local function Coins(copper)
	copper = math.floor(copper + 0.5)
	if GetCoinTextureString then
		return GetCoinTextureString(copper)
	end
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	return (g > 0 and g .. "g " or "") .. ((g > 0 or s > 0) and s .. "s " or "") .. c .. "c"
end

local function ItemName(id)
	local name = C_Item and Value(C_Item.GetItemInfo, ("item:%d"):format(id))
	return name or ("item " .. id)
end

local function ItemIcon(id)
	return C_Item and Value(C_Item.GetItemIconByID, id) or QUESTION
end

-- "Level 16 Elite" (what's known of it).
local function Kind(info)
	local parts = {}
	if info.level and info.level > 0 then
		parts[#parts + 1] = L["Level %d"]:format(info.level)
	elseif info.level then
		parts[#parts + 1] = L["Level ??"]
	end
	local class = info.class
	if class == "elite" then
		parts[#parts + 1] = L["Elite"]
	elseif class == "rare" then
		parts[#parts + 1] = L["Rare"]
	elseif class == "rareelite" then
		parts[#parts + 1] = L["Rare elite"]
	elseif class == "worldboss" then
		parts[#parts + 1] = L["Boss"]
	end
	return table.concat(parts, " ")
end

-- "34 kills · 12s 40c each · (pelt) 12" (the coin on average over all its kills, "no coin" for
-- beasts; skinnings when there were some).
local function KillsLine(mob)
	local text = mob.kills == 1 and L["1 kill"] or L["%d kills"]:format(mob.kills)
	if mob.kills > 0 then
		text = text .. "  |cff888888·|r  " .. (mob.money > 0 and L["%s each"]:format(Coins(mob.money / mob.kills)) or L["no coin"])
	end
	if (mob.skinned or 0) > 0 then
		text = text .. ("  |cff888888·|r  |T%s:12:12|t %d"):format(Bt.SKIN_ICON, mob.skinned)
	end
	return text
end
Bt.KillsLine, Bt.Coins = KillsLine, Coins

---------------------------------------------------------------------------
-- A drop: its icon, edged in its quality's colour, how many in the corner, the chance under it
---------------------------------------------------------------------------

-- A list of drops in a tooltip: icon, name (a pelt for skinning), chance.
local function ListDrops(list)
	for _, drop in ipairs(list) do
		if drop.group then
			GameTooltip:AddLine(L["World drops"] .. (" (%d)"):format(#drop.group), 0.7, 0.7, 0.7)
		else
			local r, g, b = QualityColor(drop.quality)
			GameTooltip:AddDoubleLine(("|T%s:14:14|t %s%s"):format(ItemIcon(drop.id), drop.name or ItemName(drop.id),
				drop.skin and (" |T%s:12:12|t"):format(Bt.SKIN_ICON) or ""), Percent(drop.chance), r, g, b, 1, 1, 1)
		end
	end
end

local function CellOnEnter(cell)
	GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
	if cell.more then -- (the drops that didn't fit)
		GameTooltip:SetText(L["More drops"], 1, 1, 1)
		ListDrops(cell.more)
		GameTooltip:Show()
		return
	elseif cell.world then -- (random gear: not this mob's own)
		GameTooltip:SetText(L["World drops"], 1, 1, 1)
		GameTooltip:AddLine(L["Random gear that drops from mobs of its level anywhere: not this mob's own."], 0.7, 0.7, 0.7, true)
		ListDrops(cell.world)
		GameTooltip:Show()
		return
	end
	local drop = cell.drop
	ownTooltip = true
	GameTooltip:SetHyperlink(("item:%d"):format(drop.id))
	ownTooltip = false
	GameTooltip:AddLine(" ")
	if drop.skin then
		GameTooltip:AddLine(("|T%s:14:14|t "):format(Bt.SKIN_ICON) .. L["Only from skinning: %d of %d skinnings, %s"]:format(drop.drops,
			drop.out or 0, Percent(drop.chance)), GOLD[1], GOLD[2], GOLD[3])
	else
		GameTooltip:AddLine(L["Dropped in %d of %d kills: %s"]:format(drop.drops, drop.out or cell.kills, Percent(drop.chance)),
			GOLD[1], GOLD[2], GOLD[3])
	end
	if drop.count > drop.drops then
		GameTooltip:AddLine(L["%d in all, %.1f each time"]:format(drop.count, drop.each), 0.8, 0.8, 0.8)
	end
	if cell.link then
		GameTooltip:AddLine(L["Shift-click: link it in chat"], 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

local function CellOnClick(cell)
	if cell.drop and cell.link then
		local link = select(2, C_Item.GetItemInfo(("item:%d"):format(cell.drop.id)))
		if link then
			HandleModifiedItemClick(link)
		end
	end
end

-- size: the icon's; link: Shift-click links it (the window's, not the card's).
local function NewCell(parent, size, link)
	local cell = CreateFrame("Button", nil, parent)
	cell:SetSize(size, size + LINE)
	cell.Edge = cell:CreateTexture(nil, "BACKGROUND")
	cell.Edge:SetPoint("TOP")
	cell.Edge:SetSize(size, size)
	cell.Icon = cell:CreateTexture(nil, "ARTWORK")
	cell.Icon:SetPoint("TOPLEFT", cell.Edge, "TOPLEFT", 1, -1)
	cell.Icon:SetPoint("BOTTOMRIGHT", cell.Edge, "BOTTOMRIGHT", -1, 1)
	cell.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	cell.Count = cell:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	cell.Count:SetPoint("BOTTOMRIGHT", cell.Edge, "BOTTOMRIGHT", -1, 2)
	-- Only from skinning: Skinning's own icon, small, in the top left corner.
	cell.Skin = cell:CreateTexture(nil, "OVERLAY", nil, 2)
	cell.Skin:SetSize(math.floor(size * 0.42), math.floor(size * 0.42))
	cell.Skin:SetPoint("TOPLEFT", cell.Edge, "TOPLEFT", -2, 2)
	cell.Skin:SetTexture(Bt.SKIN_ICON)
	cell.Skin:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	cell.Skin:Hide()
	cell.More = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	cell.More:SetPoint("CENTER", cell.Edge, "CENTER", 0, 0)
	cell.Chance = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cell.Chance:SetPoint("TOP", cell.Edge, "BOTTOM", 0, -2)
	if size < ICON then
		cell.Chance:SetTextScale(0.85)
		cell.Count:SetTextScale(0.85)
	end
	cell.link = link
	if link then
		cell:SetScript("OnEnter", CellOnEnter)
		cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
		cell:SetScript("OnClick", CellOnClick)
	else
		cell:EnableMouse(false)
	end
	return cell
end

local function FillCell(cell, drop, kills)
	cell.drop, cell.more, cell.world, cell.kills = drop, nil, nil, kills
	local r, g, b = QualityColor(drop.quality)
	cell.Edge:SetColorTexture(r, g, b, 0.9)
	cell.Icon:SetTexture(ItemIcon(drop.id))
	cell.Icon:Show()
	cell.Count:SetText(tostring(drop.count))
	cell.Skin:SetShown(drop.skin and true or false)
	cell.More:SetText("")
	cell.Chance:SetText(Percent(drop.chance))
	cell.Chance:SetTextColor(r, g, b)
	cell:Show()
end

-- A mob's world drops in one place: a map, how many, "world" under it; the list in its tooltip.
local WORLD_ICON = "Interface\\Icons\\INV_Misc_Map_01"

local function FillWorld(cell, entry, kills)
	cell.drop, cell.more, cell.world, cell.kills = nil, nil, entry.group, kills
	local r, g, b = QualityColor(entry.quality)
	cell.Edge:SetColorTexture(r, g, b, 0.9)
	cell.Icon:SetTexture(WORLD_ICON)
	cell.Icon:Show()
	cell.Skin:Hide()
	cell.Count:SetText(tostring(#entry.group))
	cell.More:SetText("")
	cell.Chance:SetText(L["world"])
	cell.Chance:SetTextColor(0.7, 0.7, 0.7)
	cell:Show()
end

-- The last place, when more drops than fit: "+N", the rest in its tooltip.
local function FillMore(cell, more, kills)
	cell.drop, cell.more, cell.world, cell.kills = nil, more, nil, kills
	cell.Edge:SetColorTexture(0.3, 0.3, 0.3, 0.9)
	cell.Icon:Hide()
	cell.Skin:Hide()
	cell.Count:SetText("")
	cell.More:SetText("+" .. #more)
	cell.Chance:SetText("")
	cell:Show()
end

-- Lays the drops out in rows of perRow from the top of grid; returns how many rows.
local function Lay(grid, cells, drops, kills, size, gap, perRow, maxCells, link)
	local fit = #drops > maxCells and maxCells - 1 or #drops
	for i = 1, math.max(#cells, maxCells) do
		local cell = cells[i]
		if i <= math.min(#drops, maxCells) then
			if not cell then
				cell = NewCell(grid, size, link)
				cells[i] = cell
			end
			cell:ClearAllPoints()
			cell:SetPoint("TOPLEFT", grid, "TOPLEFT", ((i - 1) % perRow) * (size + gap), -math.floor((i - 1) / perRow) * (size + LINE + 4))
			if i <= fit and drops[i].group then
				FillWorld(cell, drops[i], kills)
			elseif i <= fit then
				FillCell(cell, drops[i], kills)
			else
				local more = {}
				for j = i, #drops do
					more[#more + 1] = drops[j]
				end
				FillMore(cell, more, kills)
			end
		elseif cell then
			cell.drop, cell.more = nil, nil
			cell:Hide()
		end
	end
	return math.ceil(math.min(#drops, maxCells) / perRow)
end

Bt.Lay, Bt.QualityColor, Bt.ItemIcon, Bt.ItemName, Bt.Kind = Lay, QualityColor, ItemIcon, ItemName, Kind

-- Dark, thin gold edges (like the fight stream's windows).
local function Dress(frame)
	local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	bg:SetAllPoints()
	bg:SetColorTexture(1, 1, 1, 1)
	bg:SetGradient("VERTICAL", CreateColor(0.03, 0.04, 0.06, 0.94), CreateColor(0.07, 0.09, 0.12, 0.94))
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local edge = frame:CreateTexture(nil, "BORDER")
		edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], (side == "TOP" or side == "BOTTOM") and 0.4 or 0.2)
		if side == "TOP" or side == "BOTTOM" then
			edge:SetHeight(1)
			edge:SetPoint(side .. "LEFT")
			edge:SetPoint(side .. "RIGHT")
		else
			edge:SetWidth(1)
			edge:SetPoint("TOP" .. side)
			edge:SetPoint("BOTTOM" .. side)
		end
	end
end

Bt.Dress = Dress

---------------------------------------------------------------------------
-- Item tooltips: the mobs an item comes from likeliest (setting itemTooltip)
---------------------------------------------------------------------------

local TOOLTIP_SOURCES = 3

local function OnItemTooltip(tooltip, info)
	if ownTooltip or not (M.enabled and M.db.itemTooltip) or (tooltip ~= GameTooltip and tooltip ~= _G.ItemRefTooltip) then
		return
	end
	local id = info and info.id
	local list = type(id) == "number" and not issecret(id) and Bt.Sources(id)
	if not list then
		return
	end
	tooltip:AddLine(" ")
	tooltip:AddDoubleLine("Bestiary", L["drop chance (kills)"], GOLD[1], GOLD[2], GOLD[3], 0.6, 0.6, 0.6)
	for i = 1, math.min(TOOLTIP_SOURCES, #list) do
		local source = list[i]
		local mob = source.mob
		local name = (mob.name or ("#" .. source.creature)) .. (mob.level and mob.level > 0 and (" (" .. mob.level .. ")") or "")
		tooltip:AddDoubleLine((source.skin and ("|T%s:14:14|t "):format(Bt.SKIN_ICON) or "") .. name,
			("%s |cff888888(%d)|r"):format(Percent(source.chance), source.out), 1, 1, 1, 1, 1, 1)
	end
	if #list > TOOLTIP_SOURCES then
		tooltip:AddLine(L["and %d more (the Bestiary's ledger)"]:format(#list - TOOLTIP_SOURCES), 0.6, 0.6, 0.6)
	end
	if Bt.IsWorldDrop(id, list[1].quality) then
		tooltip:AddLine(L["A world drop: random gear from mobs of its level, anywhere."], 0.6, 0.6, 0.6)
	end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function SavePlace()
	local left, top = win:GetLeft(), win:GetTop()
	if left and top then
		local ratio = win:GetEffectiveScale() / UIParent:GetEffectiveScale()
		M.db.window.left, M.db.window.top = left * ratio, top * ratio
	end
end

local function Place()
	local saved = M.db.window
	win:ClearAllPoints()
	if tonumber(saved.left) and tonumber(saved.top) then
		win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.left, saved.top)
	else
		win:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -240, -200) -- (at first: right of the middle, out of the way)
	end
end

local function PortraitLoaded(model)
	model:RefreshCamera()
	model:SetPaused(true) -- (still)
end

local function Build()
	win = CreateFrame("Frame", "LefthyToolsBestiaryFrame", UIParent)
	win:SetSize(WIDTH, 120)
	win:SetFrameStrata("MEDIUM")
	win:SetClampedToScreen(true)
	win:EnableMouse(true)
	win:SetMovable(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		self:SetUserPlaced(false)
		SavePlace()
	end)
	win:Hide()
	Dress(win)

	win.Close = CreateFrame("Button", nil, win, "UIPanelCloseButtonNoScripts")
	win.Close:SetPoint("TOPRIGHT", -2, -2)
	win.Close:SetScript("OnClick", function() Bt.Toggle(false) end)
	-- The ledger (every mob, search): a small book left of the X.
	win.Ledger = CreateFrame("Button", nil, win)
	win.Ledger:SetSize(16, 16)
	win.Ledger:SetPoint("RIGHT", win.Close, "LEFT", -2, 0)
	win.Ledger:SetNormalTexture("Interface\\Icons\\INV_Misc_Book_11")
	win.Ledger:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	win.Ledger:SetScript("OnClick", function() Bt.LedgerButton() end)
	win.Ledger:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(L["The ledger"], 1, 1, 1)
		GameTooltip:AddLine(L["Every mob you've killed, its statistics and drops; search mobs and items."], 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	win.Ledger:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- The mob: a still portrait in a dark square, its name, level and kind, kills and coin.
	win.PortraitBack = win:CreateTexture(nil, "BORDER")
	win.PortraitBack:SetPoint("TOPLEFT", PAD, -PAD)
	win.PortraitBack:SetSize(PORTRAIT + 2, PORTRAIT + 2)
	win.PortraitBack:SetColorTexture(0, 0, 0, 0.6)
	win.Portrait = CreateFrame("PlayerModel", nil, win)
	win.Portrait:SetPoint("TOPLEFT", win.PortraitBack, "TOPLEFT", 1, -1)
	win.Portrait:SetSize(PORTRAIT, PORTRAIT)
	win.Portrait:SetPortraitZoom(1)
	win.Portrait:SetScript("OnModelLoaded", PortraitLoaded)
	win.Unknown = win:CreateTexture(nil, "ARTWORK")
	win.Unknown:SetAllPoints(win.Portrait)
	win.Unknown:SetTexture(QUESTION)
	win.Unknown:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	win.Unknown:SetAlpha(0.5)
	win.Name = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	win.Name:SetPoint("TOPLEFT", win.PortraitBack, "TOPRIGHT", 8, -1)
	win.Name:SetPoint("RIGHT", win.Ledger, "LEFT", -2, 0)
	win.Name:SetJustifyH("LEFT")
	win.Name:SetWordWrap(false)
	win.Kind = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	win.Kind:SetPoint("TOPLEFT", win.Name, "BOTTOMLEFT", 0, -2)
	win.Kills = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	win.Kills:SetPoint("TOPLEFT", win.Kind, "BOTTOMLEFT", 0, -3)
	win.Kills:SetPoint("RIGHT", -PAD, 0)
	win.Kills:SetJustifyH("LEFT")
	win.Kills:SetWordWrap(false)
	local line = win:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", PAD, -HEADER + 4)
	line:SetPoint("TOPRIGHT", -PAD, -HEADER + 4)

	-- The drops, and a line under them when there's something to say.
	win.Grid = CreateFrame("Frame", nil, win)
	win.Grid:SetPoint("TOPLEFT", PAD + 1, -HEADER - 4)
	win.Grid:SetSize(WIDTH - 2 * PAD, 10)
	win.cells = {}
	win.Note = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	win.Note:SetWidth(WIDTH - 2 * PAD)
	win.Note:SetJustifyH("CENTER")
	Place()
end

-- The window shows creature (nil: none yet); info: what was seen of it.
local function Draw()
	if not (win and win:IsShown()) then
		return
	end
	local mob = Bt.Mob(shown)
	local info = shownInfo or {}
	if win.creature ~= shown then
		win.creature = shown
		win.Portrait:ClearModel()
		if shown then
			win.Portrait:SetCreature(shown)
		end
	end
	win.Portrait:SetShown(shown ~= nil)
	win.Unknown:SetShown(shown == nil)
	local name = info.name or mob and mob.name
	win.Name:SetText(name or "Bestiary") -- (module names aren't translated)
	win.Kind:SetText(shown and Kind({ level = info.level or mob and mob.level, class = info.class or mob and mob.class }) or "")
	win.Kills:SetText(mob and KillsLine(mob) or "")
	local drops = Bt.Drops(mob, M.db.showPoor)
	local rows = Lay(win.Grid, win.cells, drops, mob and mob.kills or 0, ICON, GAP, PER_ROW, PER_ROW * ROWS, true)
	local notes = {}
	if not shown then
		notes[#notes + 1] = L["Target a mob to see what it drops."]
	elseif not mob or mob.kills == 0 then
		notes[#notes + 1] = L["No kills of it yet: kill one on your own and loot it."]
	elseif #drops == 0 then
		notes[#notes + 1] = next(mob.items) and L["Only grey items so far."] or L["Nothing dropped yet."]
	end
	if IsInGroup and IsInGroup() then
		notes[#notes + 1] = L["In a group: kills aren't counted (the loot is shared)."]
	end
	local height = HEADER + rows * (CELL_H + 4)
	win.Note:ClearAllPoints()
	win.Note:SetPoint("TOP", win, "TOP", 0, -height - (rows > 0 and 0 or 6))
	win.Note:SetText(table.concat(notes, "\n"))
	win.Note:SetShown(#notes > 0)
	height = height + (#notes > 0 and (#notes * LINE + (rows > 0 and 4 or 10)) or 0) + PAD
	win:SetHeight(math.max(height, HEADER + 16))
end
Bt.Draw = Draw

-- The window follows the target: a mob that can be attacked, or a dead one (not a vendor).
local function FollowTarget()
	if not (UnitExists("target") and (Value(UnitCanAttack, "player", "target") or Value(UnitIsDead, "target"))) then
		return false
	end
	local guid, creature = Bt.Look("target")
	if not creature then
		return false
	end
	shown = creature
	local seen = Bt.Seen(guid)
	shownInfo = seen and { name = seen.name, level = seen.level, class = seen.class } or nil
	return true
end

function Bt.TargetChanged()
	if win and win:IsShown() and FollowTarget() then
		Draw()
	end
end

-- The ledger's buttons (the window's book, Ctrl-click on the minimap's): open on the mob shown, or
-- close it when it's open.
function Bt.LedgerButton()
	local ledger = Bt.Ledger and Bt.Ledger()
	if ledger and ledger:IsShown() then
		ledger:Hide()
	else
		Bt.ToggleLedger(shown)
	end
end

-- Open (on true), close (false) or the other way round (nil). Kept for next time.
function Bt.Toggle(on)
	if not M.enabled then
		return
	end
	if on == nil then
		on = not (win and win:IsShown())
	end
	M.db.window.shown = on
	if on then
		if not win then
			Build()
		end
		win:Show()
		FollowTarget()
		Draw()
	elseif win then
		win:Hide()
		GameTooltip:Hide()
	end
	if button then
		button.Open:SetShown(on)
	end
end

---------------------------------------------------------------------------
-- The card next to the mouse
---------------------------------------------------------------------------

local function CardFollow(self)
	if not (UnitExists("mouseover") and Value(UnitGUID, "mouseover") == cardGUID) then
		self:Hide()
		cardGUID = nil
		return
	end
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	self:ClearAllPoints()
	self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 16, y / scale - 20)
end

local function BuildCard()
	card = CreateFrame("Frame", "LefthyToolsBestiaryCard", UIParent)
	card:SetFrameStrata("TOOLTIP")
	card:SetClampedToScreen(true)
	card:EnableMouse(false)
	card:Hide()
	Dress(card)
	card.Kills = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	card.Kills:SetPoint("TOPLEFT", 8, -7)
	card.Grid = CreateFrame("Frame", nil, card)
	card.Grid:SetPoint("TOPLEFT", 8, -24)
	card.Grid:SetSize(CARD_CELLS * (CARD_ICON + CARD_GAP), CARD_ICON + LINE)
	card.cells = {}
	card:SetScript("OnUpdate", CardFollow)
end

-- Over an enemy you've killed before: its card (setting hoverCard).
function Bt.MouseoverChanged()
	if not (M.enabled and M.db.hoverCard) or not UnitExists("mouseover")
		or not (Value(UnitCanAttack, "player", "mouseover") or Value(UnitIsDead, "mouseover")) then
		if card then
			card:Hide()
		end
		return
	end
	local guid, creature = Bt.Look("mouseover")
	local mob = Bt.Mob(creature)
	if not (mob and mob.kills > 0) then
		if card then
			card:Hide()
		end
		return
	end
	if not card then
		BuildCard()
	end
	cardGUID = guid
	card.Kills:SetText(KillsLine(mob))
	local drops = Bt.Drops(mob, M.db.showPoor)
	local rows = Lay(card.Grid, card.cells, drops, mob.kills, CARD_ICON, CARD_GAP, CARD_CELLS, CARD_CELLS, false)
	local width = math.max(card.Kills:GetStringWidth(), math.min(#drops, CARD_CELLS) * (CARD_ICON + CARD_GAP) - CARD_GAP)
	card:SetSize(width + 16, rows > 0 and (24 + CARD_ICON + LINE + 6) or 24)
	CardFollow(card)
	card:Show()
end

---------------------------------------------------------------------------
-- The minimap button
---------------------------------------------------------------------------

local function ButtonOnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText("Bestiary", 1, 0.82, 0)
	local count, kills = 0, 0
	for _, mob in pairs(LefthyToolsBestiaryDB and LefthyToolsBestiaryDB.mobs or {}) do
		count, kills = count + 1, kills + mob.kills
	end
	GameTooltip:AddLine(L["%d kinds of mobs, %d kills"]:format(count, kills), 1, 1, 1)
	GameTooltip:AddLine(L["Click: open or close the window"], 0.8, 0.8, 0.8)
	GameTooltip:AddLine((M.db.hoverCard and L["Shift-click: drops next to the mouse off"] or L["Shift-click: drops next to the mouse on"]),
		0.8, 0.8, 0.8)
	GameTooltip:AddLine(L["Ctrl-click: the ledger"], 0.8, 0.8, 0.8)
	GameTooltip:AddLine(L["Right-click: settings"], 0.8, 0.8, 0.8)
	GameTooltip:AddLine(L["Drag: move it along the minimap"], 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

local function ButtonOnClick(_, mouseButton)
	if mouseButton == "RightButton" then
		LT:OpenSettings(M)
	elseif IsShiftKeyDown() then
		LT:SetModuleSetting(M, "hoverCard", not M.db.hoverCard)
		M:Print(M.db.hoverCard and "drops next to the mouse: on." or "drops next to the mouse: off.")
	elseif IsControlKeyDown() then
		Bt.LedgerButton()
	else
		Bt.Toggle()
	end
end

local function UpdateButton()
	local show = M.enabled and M.db.minimapButton and Minimap ~= nil
	if show and not button then
		button = LT.Window.MinimapButton("LefthyToolsBestiaryMinimapButton", { icon = BUTTON_ICON, db = M.db,
			angleKey = "minimapAngle", angle = 150, onClick = ButtonOnClick, onEnter = ButtonOnEnter })
		-- The window is open: a small gold dot.
		button.Open = button:CreateTexture(nil, "OVERLAY", nil, 2)
		button.Open:SetSize(7, 7)
		button.Open:SetPoint("TOPRIGHT", -5, -4)
		button.Open:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
		button.Open:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
	end
	if button then
		button:SetShown(show)
		if show then
			button:Place()
		end
		button.Open:SetShown(win ~= nil and win:IsShown())
	end
end

---------------------------------------------------------------------------
-- Switching on and off, settings
---------------------------------------------------------------------------

Bt.OnChanged(function(creature)
	if creature == shown then
		Draw()
	end
end)

-- Switched on (and after login): the button, and the window if it was open.
function Bt.Start()
	C_Timer.After(0, function()
		UpdateButton()
		if M.enabled and M.db.window.shown then
			Bt.Toggle(true)
		end
	end)
end

-- Switched off: everything hides (whether the window was open stays kept).
function Bt.Stop()
	if win then
		win:Hide()
	end
	if card then
		card:Hide()
	end
	UpdateButton()
end

function Bt.Settings()
	UpdateButton()
	Draw()
	if card and not M.db.hoverCard then
		card:Hide()
	end
end

-- For tests.
function Bt.Frames()
	return win, card, button
end
