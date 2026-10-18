local _, ns = ...
local L = ns.L
local Bt = ns.Bestiary
local M = Bt.module
local GOLD, issecret = Bt.GOLD, Bt.issecret
local Percent, QualityColor, ItemIcon, ItemName, Decimal = Bt.Percent, Bt.QualityColor, Bt.ItemIcon, Bt.ItemName, Bt.Decimal

-- Drops as cells, shared by the window, the card and the ledger: an icon edged in its quality's
-- colour, how many you got in its corner, the drop chance under it; hover: the item's tooltip with
-- your numbers and the classic database's; Shift-click links it, Alt-click pins it to the wish list.
-- Not seen yet (the classic database's): grey and faded. Also the look of the Bestiary's frames (Dress)
-- and the lines it adds to item tooltips anywhere.

local ICON = 30          -- the window's cells (smaller ones: smaller text)
local LINE = 14
local TOOLTIP_LIST = 20  -- drops listed in a cell's tooltip (the rest: how many), at most
local UNSEEN_ALPHA = 0.5
local QUEST_ICON = Bt.QUEST_ICON
local ownTooltip = false -- showing our own drop's tooltip (it has the numbers already: no item tooltip lines)

-- A list of drops in a tooltip: icon, name (a pelt for skinning), chance; not seen yet: greyed, the
-- classic database's chance. At most max (then how many more: a mob farmed for long can have dozens
-- of world drops, and a tooltip taller than the screen shows none of them well).
local function ListDrops(list, max)
	local shown = math.min(#list, max or #list)
	for i = 1, shown do
		local drop = list[i]
		if drop.group then
			GameTooltip:AddLine(L["World drops"] .. (" (%d)"):format(#drop.group), 0.7, 0.7, 0.7)
		else
			local r, g, b = QualityColor(drop.quality)
			local right = drop.unseen and 0.55 or 1
			if drop.unseen then
				r, g, b = 0.55, 0.55, 0.55
			end
			GameTooltip:AddDoubleLine(("|T%s:14:14|t %s%s%s"):format(ItemIcon(drop.id), drop.name or ItemName(drop.id),
				drop.skin and (" |T%s:12:12|t"):format(Bt.SKIN_ICON) or drop.quest and (" |T%s:12:12|t"):format(QUEST_ICON) or "",
				Bt.Wish(drop.id) and (" |T%s:12:12|t"):format(Bt.STAR) or ""), Percent(drop.chance), r, g, b, right, right, right)
		end
	end
	if shown < #list then
		GameTooltip:AddLine(L["and %d more (the Bestiary's ledger)"]:format(#list - shown), 0.6, 0.6, 0.6)
	end
end
Bt.ListDrops = ListDrops -- (also the fight stream's battle row: a foe's tooltip)

-- The classic database's word on a drop: its chance there (a quest item's: only while on its
-- quest), or that it doesn't list it; nothing when it doesn't know the mob.
local function AddClassic(drop, r, g, b)
	if drop.classic then
		GameTooltip:AddLine((drop.quest and L["Classic database: %s, only while on its quest"] or L["Classic database: %s"])
			:format(Percent(drop.classic)), r, g, b)
	elseif drop.classic == false then
		GameTooltip:AddLine(L["Not in the classic database"], 0.6, 0.6, 0.6)
	end
end

-- Not seen yet: the database's chance, and how many you'd have expected in your kills (or
-- skinnings) by now; red-ish when that's a few (Forever may differ, or bad luck).
local function AddUnseen(drop)
	AddClassic(drop, GOLD[1], GOLD[2], GOLD[3])
	local out = drop.out or 0
	local expected = drop.quest and 0 or drop.chance * out
	if out == 0 then
		GameTooltip:AddLine(drop.skin and L["You haven't skinned one yet."] or L["You haven't killed one yet."], 0.7, 0.7, 0.7)
	elseif expected >= 1.5 then
		GameTooltip:AddLine((drop.skin and L["Not seen in your %d skinnings (about %d expected)"] or L["Not seen in your %d kills (about %d expected)"])
			:format(out, math.floor(expected + 0.5)), 0.95, 0.55, 0.45)
	else
		GameTooltip:AddLine((drop.skin and L["Not seen yet in your %d skinnings"] or L["Not seen yet in your %d kills"]):format(out), 0.7, 0.7, 0.7)
	end
end

-- "On your Bestiary wish list (37 kills since you pinned it)", with its star.
local function AddWish(tooltip, wish)
	tooltip:AddLine(("|T%s:12:12|t "):format(Bt.STAR) .. L["On your Bestiary wish list (%d kills since you pinned it)"]:format(wish[2] or 0),
		GOLD[1], GOLD[2], GOLD[3])
end
Bt.AddWish = AddWish

local function CellOnEnter(cell)
	GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
	if cell.more then -- (the drops that didn't fit)
		GameTooltip:SetText(L["More drops"], 1, 1, 1)
		ListDrops(cell.more, TOOLTIP_LIST)
		GameTooltip:Show()
		return
	elseif cell.world then -- (random gear: not this mob's own)
		GameTooltip:SetText(L["World drops"], 1, 1, 1)
		GameTooltip:AddLine(L["Random gear that drops from mobs of its level anywhere: not this mob's own."], 0.7, 0.7, 0.7, true)
		ListDrops(cell.world, TOOLTIP_LIST)
		GameTooltip:Show()
		return
	end
	local drop = cell.drop
	ownTooltip = true
	GameTooltip:SetHyperlink(("item:%d"):format(drop.id))
	ownTooltip = false
	GameTooltip:AddLine(" ")
	if drop.unseen then -- (the database's, not had yet: in colour while hovered)
		cell.Icon:SetDesaturated(false)
		cell.Icon:SetAlpha(1)
		AddUnseen(drop)
	else
		if drop.skin then
			GameTooltip:AddLine(("|T%s:14:14|t "):format(Bt.SKIN_ICON) .. L["Only from skinning: %d of %d skinnings, %s"]:format(drop.drops,
				drop.out or 0, Percent(drop.chance)), GOLD[1], GOLD[2], GOLD[3])
		else
			GameTooltip:AddLine(L["Dropped in %d of %d kills: %s"]:format(drop.drops, drop.out or cell.kills, Percent(drop.chance)),
				GOLD[1], GOLD[2], GOLD[3])
		end
		if drop.count > drop.drops then
			GameTooltip:AddLine(L["%d in all, %s each time"]:format(drop.count, Decimal(("%.1f"):format(drop.each))), 0.8, 0.8, 0.8)
		end
		AddClassic(drop, 0.8, 0.8, 0.8)
	end
	local wish = Bt.Wish(drop.id)
	if wish then
		AddWish(GameTooltip, wish)
	end
	if cell.link then
		GameTooltip:AddLine(L["Shift-click: link it in chat"], 0.6, 0.6, 0.6)
		GameTooltip:AddLine(wish and L["Alt-click: off your wish list"] or L["Alt-click: on your wish list"], 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

local function CellOnLeave(cell)
	GameTooltip:Hide()
	if cell.drop and cell.drop.unseen then
		cell.Icon:SetDesaturated(true)
		cell.Icon:SetAlpha(UNSEEN_ALPHA)
	end
end

local function CellOnClick(cell)
	if cell.drop and cell.link and IsAltKeyDown() then -- (the wish list: on, or off again)
		Bt.ToggleWish(cell.drop.id, cell.drop)
		if GameTooltip:IsOwned(cell) then
			CellOnEnter(cell)
		end
	elseif cell.drop and cell.link then
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
	-- A quest item (the classic database: it drops only while you're on its quest): a "!" there.
	cell.Quest = cell:CreateTexture(nil, "OVERLAY", nil, 2)
	cell.Quest:SetSize(math.floor(size * 0.5), math.floor(size * 0.5))
	cell.Quest:SetPoint("TOPLEFT", cell.Edge, "TOPLEFT", -3, 3)
	cell.Quest:SetTexture(QUEST_ICON)
	cell.Quest:Hide()
	-- On your wish list: a small star in the top right corner.
	cell.Star = cell:CreateTexture(nil, "OVERLAY", nil, 3)
	cell.Star:SetSize(math.floor(size * 0.45), math.floor(size * 0.45))
	cell.Star:SetPoint("TOPRIGHT", cell.Edge, "TOPRIGHT", 3, 3)
	cell.Star:SetTexture(Bt.STAR)
	cell.Star:Hide()
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
		cell:SetScript("OnLeave", CellOnLeave)
		cell:SetScript("OnClick", CellOnClick)
	else
		cell:EnableMouse(false)
	end
	return cell
end

-- A drop; not seen yet (the classic database's): grey and faded, no count, the database's chance.
local function FillCell(cell, drop, kills)
	cell.drop, cell.more, cell.world, cell.kills = drop, nil, nil, kills
	local r, g, b = QualityColor(drop.quality)
	local unseen = drop.unseen and true or false
	cell.Edge:SetColorTexture(r, g, b, unseen and 0.3 or 0.9)
	cell.Icon:SetTexture(ItemIcon(drop.id))
	cell.Icon:SetDesaturated(unseen)
	cell.Icon:SetAlpha(unseen and UNSEEN_ALPHA or 1)
	cell.Icon:Show()
	cell.Count:SetText(unseen and "" or tostring(drop.count))
	cell.Skin:SetShown(drop.skin and true or false)
	cell.Quest:SetShown(drop.quest and not drop.skin and true or false)
	cell.Star:SetShown(Bt.Wish(drop.id) ~= nil)
	cell.More:SetText("")
	cell.Chance:SetText(Percent(drop.chance))
	if unseen then
		cell.Chance:SetTextColor(0.55, 0.55, 0.55)
	else
		cell.Chance:SetTextColor(r, g, b)
	end
	cell:Show()
end

-- Back to a plain icon (the world drops' map, the "+N").
local function Plain(cell)
	cell.Icon:SetDesaturated(false)
	cell.Icon:SetAlpha(1)
	cell.Skin:Hide()
	cell.Quest:Hide()
	cell.Star:Hide()
end

-- A mob's world drops in one place: a map, how many, "world" under it; the list in its tooltip.
local WORLD_ICON = "Interface\\Icons\\INV_Misc_Map_01"

local function FillWorld(cell, entry, kills)
	cell.drop, cell.more, cell.world, cell.kills = nil, nil, entry.group, kills
	local r, g, b = QualityColor(entry.quality)
	cell.Edge:SetColorTexture(r, g, b, 0.9)
	cell.Icon:SetTexture(WORLD_ICON)
	cell.Icon:Show()
	Plain(cell)
	for _, drop in ipairs(entry.group) do
		if Bt.Wish(drop.id) then
			cell.Star:Show() -- (a wished one among them)
		end
	end
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
	Plain(cell)
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

Bt.Lay = Lay

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
	if ownTooltip or not M.enabled or (tooltip ~= GameTooltip and tooltip ~= _G.ItemRefTooltip) then
		return
	end
	local id = info and info.id
	if type(id) ~= "number" or issecret(id) then
		return
	end
	-- On your wish list: said (also with the setting off: you pinned it).
	local list, wish = M.db.itemTooltip and Bt.Sources(id), Bt.Wish(id)
	if wish and not list then
		tooltip:AddLine(" ")
		AddWish(tooltip, wish)
	end
	if not list then
		return
	end
	tooltip:AddLine(" ")
	tooltip:AddDoubleLine("Bestiary", L["drop chance (kills)"], GOLD[1], GOLD[2], GOLD[3], 0.6, 0.6, 0.6)
	for i = 1, math.min(TOOLTIP_SOURCES, #list) do
		local source = list[i]
		local mob = source.mob
		local levels = Bt.LevelRange(source.creature, mob) -- ("9–10": two kinds of one name told apart)
		local name = (mob.name or ("#" .. source.creature)) .. (levels and (" (" .. levels .. ")") or "")
		tooltip:AddDoubleLine((source.skin and ("|T%s:14:14|t "):format(Bt.SKIN_ICON) or "") .. name,
			("%s |cff888888(%d)|r"):format(Percent(source.chance), source.out), 1, 1, 1, 1, 1, 1)
	end
	if #list > TOOLTIP_SOURCES then
		tooltip:AddLine(L["and %d more (the Bestiary's ledger)"]:format(#list - TOOLTIP_SOURCES), 0.6, 0.6, 0.6)
	end
	if Bt.IsWorldDrop(id, list[1].quality) then
		tooltip:AddLine(L["A world drop: random gear from mobs of its level, anywhere."], 0.6, 0.6, 0.6)
	end
	if wish then
		AddWish(tooltip, wish)
	end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
end
