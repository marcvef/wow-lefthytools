local _, ns = ...
local LT = ns.LT
local L = ns.L
local Bt = ns.Bestiary
local M = Bt.module

-- The Bestiary's window: your target's drops. At the top the mob: a small still portrait, its
-- name, level and kind, your kills and the coin each brought, and (when known) a small grey line on
-- what a kill pays: its worth (coin and the drops' vendor value), XP and how long it takes (hover:
-- in full). Under it its drops, the likeliest
-- first: an icon edged in its quality's colour, how many you got in its corner, the drop chance
-- under it; the item's tooltip with the numbers on hover, Shift-click links it. It follows your
-- target (a mob you can attack, or a dead one) and keeps the last when you clear it. It stays
-- open: Escape doesn't close it, only its X, the minimap button or /bestiary. Where it is and
-- whether it's open are kept.
--
-- The card next to the mouse (setting hoverCard): over an enemy you've killed before, your kills and
-- its likeliest drops, small, following the mouse while it's over it.
--
-- The classic drop database (Bestiary.lua, setting dropData) beside your numbers: each drop's
-- tooltip has its chance there. With the setting windowUnseen (off: the user wanted the window
-- without it), what it says the mob drops that you haven't had yet is a section of its own under
-- your drops, smaller and faded (grey icons, how many of its drops you've found), each with the
-- item's tooltip, the database's chance and how many you'd have expected by now; for a mob you
-- haven't killed, what it can drop. The card shows that for a mob you haven't killed with the
-- setting cardUnseen (off, like the window's: the user wanted both without it).
--
-- Quest drops (Bestiary.lua): while a quest wants an item this mob drops, the window has a line for
-- it under the header ("Gnoll Paw: 3/8, 40% each, about 12 more kills", the quest's "!" in front)
-- and the card one more small line, also over a mob you haven't killed yet.
--
-- The wish list (Bestiary.lua): Alt-click on a drop here or in the ledger pins it (or unpins it).
-- Wished drops have a small star wherever they show; the card puts a wished item a mob drops first
-- (from the classic database, faded, when you haven't had one), also over a mob you haven't killed;
-- item tooltips say it's on your wish list.

local WIDTH = 236
local PAD = 10
local ICON, GAP, PER_ROW, ROWS = 30, 8, 6, 4
local CELL_H = ICON + 16
local HEADER = 62
local PACE_H = 13       -- the header's line on what a kill pays, when there's something to say
local PORTRAIT = 40
local LINE = 14
local DOT = "  |cff888888·|r  "
local CARD_ICON, CARD_GAP, CARD_CELLS = 22, 5, 6
local KNOWN_ICON, KNOWN_GAP, KNOWN_ROWS = 22, 6, 2 -- not seen yet (the classic database): smaller, faded
local KNOWN_PER_ROW = math.floor((WIDTH - 2 * PAD + KNOWN_GAP) / (KNOWN_ICON + KNOWN_GAP))
local KNOWN_HEAD = 16   -- its heading's height
local QUEST_LINES = 3   -- quests wanting its drops: a line each in the window, at most
local TOOLTIP_LIST = 20 -- drops listed in a cell's tooltip (the rest: how many), at most
local CARD_QUEST_W = 250 -- the card's quest line, at most (longer: cut)
local UNSEEN_ALPHA = 0.5
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local ALL_FOUND = "Interface\\RaidFrame\\ReadyCheck-Ready"
local BUTTON_ICON = "Interface\\Icons\\INV_Misc_Bag_10"
local GOLD, NONE, Value, issecret = Bt.GOLD, Bt.NONE, Bt.Value, Bt.issecret

local win, card, button
local shown, shownInfo -- the creature the window shows, and what was seen of it (name, level, class)
local cardGUID
local ownTooltip = false -- showing our own drop's tooltip (it has the numbers already: no item tooltip lines)

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

-- A number's decimal point as the client's language writes it ("4,5" in German), unless plain (chat
-- lines, which stay English).
local function Decimal(text, plain)
	return ns.DECIMAL_COMMA and not plain and (text:gsub("%.", ",")) or text
end

-- "35%", "3.4%" ("3,4%" in German; plain: with a point, for chat lines), "<0.1%".
local function Percent(chance, plain)
	local p = chance * 100
	if p >= 9.95 then
		return ("%d%%"):format(math.floor(p + 0.5))
	elseif p >= 0.05 then
		return Decimal(("%.1f%%"):format(p), plain)
	end
	return Decimal("<0.1%", plain)
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
	return name or L["item %d"]:format(id) -- (one the client doesn't know yet)
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
-- beasts; skinnings when there were some). short: nothing about coin when there was none (the card
-- beside the mouse: the user didn't need "no coin" there).
local function KillsLine(mob, short)
	local text = mob.kills == 1 and L["1 kill"] or L["%d kills"]:format(mob.kills)
	if mob.kills > 0 and mob.money > 0 then
		text = text .. "  |cff888888·|r  " .. L["%s each"]:format(Coins(mob.money / mob.kills))
	elseif mob.kills > 0 and not short then
		text = text .. "  |cff888888·|r  " .. L["no coin"]
	end
	if (mob.skinned or 0) > 0 then
		text = text .. ("  |cff888888·|r  |T%s:12:12|t %d"):format(Bt.SKIN_ICON, mob.skinned)
	end
	return text
end
Bt.KillsLine, Bt.Coins = KillsLine, Coins

-- A quest wanting this mob's drop (Bt.QuestDrops): "Gnoll Paw: 3/8, 40% each, about 12 more kills"
-- after the quest's "!" (the chance: the classic database's, else yours); done: a tick, grey.
local function QuestLine(want)
	local counts = L["%s: %d/%d"]:format(want.name, want.have, want.need)
	if want.done then
		return ("|T%s:12:12|t |cff888888%s|r"):format(ALL_FOUND, counts)
	elseif want.more == 1 then
		counts = L["%s: %d/%d, %s each, about 1 more kill"]:format(want.name, want.have, want.need, Percent(want.chance))
	elseif want.more then
		counts = L["%s: %d/%d, %s each, about %d more kills"]:format(want.name, want.have, want.need, Percent(want.chance), want.more)
	end
	return ("|T%s:12:12|t "):format(QUEST_ICON) .. counts
end

-- "14 s", "4.5 s" (a tenth under 10 s; "4,5 s" in German).
local function Seconds(s)
	return LT.Options.Seconds(s >= 10 and math.floor(s + 0.5) or math.floor(s * 10 + 0.5) / 10)
end

-- XP per hour, short: "850", "4.3k", "21k".
local function Thousands(n)
	if n >= 9950 then
		return ("%dk"):format(math.floor(n / 1000 + 0.5))
	elseif n >= 1000 then
		return Decimal(("%.1fk"):format(n / 1000))
	end
	return tostring(math.floor(n + 0.5))
end

-- Worth the way a player says it: to the silver from 1s up, else to the copper.
local function Rounded(copper)
	return copper >= 100 and math.floor(copper / 100 + 0.5) * 100 or math.floor(copper + 0.5)
end

-- What a kill of a kind pays, the parts known (Bestiary.lua: its worth, its pace): short for the
-- window's line ("Per kill: worth ~45s · 85 XP · 14 s", "(level 12)" when the pace isn't for your
-- level), and in full, a line each, for its tooltip and the ledger (the worth's coin and vendor
-- parts, the XP per hour of fighting). nil and {} when nothing's known.
local function PaceText(mob)
	local parts, lines = {}, {}
	local worth, coin, vendor = Bt.Worth(mob)
	if worth and worth > 0 then
		local about = Coins(Rounded(worth))
		parts[#parts + 1] = L["worth ~%s"]:format(about)
		local line = L["Worth about %s per kill"]:format(about)
		if coin > 0 and vendor > 0 then -- (both: what it's made of)
			line = line .. (" (%s, %s)"):format(L["%s coin"]:format(Coins(coin)), L["%s from drops at a vendor"]:format(Coins(vendor)))
		end
		lines[#lines + 1] = line
	end
	local xp, seconds, perHour, level = Bt.Pace(mob)
	if xp then
		parts[#parts + 1] = L["%d XP"]:format(math.floor(xp + 0.5))
	end
	if seconds then
		parts[#parts + 1] = Seconds(seconds)
	end
	if #parts == 0 then
		return nil, lines
	end
	local other = level and level ~= Value(UnitLevel, "player") and (xp or seconds) and level or nil
	if xp or seconds then
		local each = xp and seconds and L["%d XP and %s per kill"]:format(math.floor(xp + 0.5), Seconds(seconds))
			or xp and L["%d XP per kill"]:format(math.floor(xp + 0.5)) or L["%s per kill"]:format(Seconds(seconds))
		lines[#lines + 1] = other and L["At level %d: %s"]:format(other, each) or each
	end
	if perHour and perHour > 0 then
		lines[#lines + 1] = L["About %s XP per hour of fighting (the time between fights not counted)"]:format(Thousands(perHour))
	end
	return L["Per kill: %s"]:format(table.concat(parts, DOT)) .. (other and (" " .. L["(level %d)"]:format(other)) or ""), lines
end
Bt.PaceText, Bt.Thousands, Bt.Rounded = PaceText, Thousands, Rounded

---------------------------------------------------------------------------
-- A drop: its icon, edged in its quality's colour, how many in the corner, the chance under it
---------------------------------------------------------------------------

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
	if wish then
		AddWish(tooltip, wish)
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
	-- What a kill pays (worth, XP, how long it takes), small and grey under the portrait, the window
	-- wide; hover: the same in full, with the XP per hour of fighting.
	win.Pace = CreateFrame("Button", nil, win)
	win.Pace:SetPoint("TOPLEFT", PAD, -(HEADER - 6))
	win.Pace:SetSize(WIDTH - 2 * PAD, PACE_H)
	win.Pace.Text = win.Pace:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	win.Pace.Text:SetPoint("LEFT")
	win.Pace.Text:SetPoint("RIGHT")
	win.Pace.Text:SetJustifyH("LEFT")
	win.Pace.Text:SetWordWrap(false)
	win.Pace:SetScript("OnEnter", function(self)
		local _, lines = PaceText(Bt.Mob(shown))
		if #lines > 0 then
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:SetText(lines[1], 1, 1, 1)
			for i = 2, #lines do
				GameTooltip:AddLine(lines[i], 0.8, 0.8, 0.8, true)
			end
			GameTooltip:Show()
		end
	end)
	win.Pace:SetScript("OnLeave", function() GameTooltip:Hide() end)
	win.Rule = win:CreateTexture(nil, "ARTWORK")
	win.Rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
	win.Rule:SetHeight(1)
	-- Quests wanting its drops: a line each, under the header (placed when drawn: under the line of
	-- what a kill pays, when there is one).
	win.Quest = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	win.Quest:SetWidth(WIDTH - 2 * PAD)
	win.Quest:SetJustifyH("LEFT")
	win.Quest:SetSpacing(2)

	-- The drops, and a line under them when there's something to say.
	win.Grid = CreateFrame("Frame", nil, win)
	win.Grid:SetSize(WIDTH - 2 * PAD, 10)
	win.cells = {}
	-- Not seen yet (the classic database): a heading with a rule and how many of its drops you've
	-- found, then its drops, smaller and faded.
	win.KnownLabel = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	win.KnownCount = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	win.KnownRule = win:CreateTexture(nil, "ARTWORK")
	win.KnownRule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.18)
	win.KnownRule:SetHeight(1)
	win.KnownRule:SetPoint("LEFT", win.KnownLabel, "RIGHT", 6, 0)
	win.KnownRule:SetPoint("RIGHT", win.KnownCount, "LEFT", -6, 0)
	win.Known = CreateFrame("Frame", nil, win)
	win.Known:SetSize(WIDTH - 2 * PAD, 10)
	win.knownCells = {}
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
	-- What a kill pays, when something's known: the header grows by a line.
	local pace = PaceText(mob)
	win.Pace.Text:SetText(pace or "")
	win.Pace:SetShown(pace ~= nil)
	local head = HEADER + (pace and PACE_H or 0)
	win.Rule:ClearAllPoints()
	win.Rule:SetPoint("TOPLEFT", PAD, -head + 4)
	win.Rule:SetPoint("TOPRIGHT", -PAD, -head + 4)
	-- Quests wanting its drops (the ones still wanted first), then its drops under them.
	local wanted, lines = Bt.QuestDrops(shown, mob), {}
	for i = 1, math.min(#wanted, QUEST_LINES) do
		lines[i] = QuestLine(wanted[i])
	end
	win.Quest:ClearAllPoints()
	win.Quest:SetPoint("TOPLEFT", PAD, -head)
	win.Quest:SetText(table.concat(lines, "\n"))
	win.Quest:SetShown(#lines > 0)
	local quests = #lines > 0 and math.ceil(win.Quest:GetStringHeight()) + 6 or 0
	win.Grid:ClearAllPoints()
	win.Grid:SetPoint("TOPLEFT", PAD + 1, -head - 4 - quests)
	local drops = Bt.Drops(mob, M.db.showPoor, shown)
	local rows = Lay(win.Grid, win.cells, drops, mob and mob.kills or 0, ICON, GAP, PER_ROW, PER_ROW * ROWS, true)
	local height = head + quests + rows * (CELL_H + 4)
	-- What the classic database says it drops that you haven't had yet (for a mob you haven't
	-- killed: what it can drop), when that's switched on for the window.
	local unseen, found, total
	if M.db.windowUnseen then
		unseen, found, total = Bt.Compare(shown, mob, M.db.showPoor)
	end
	local tried = mob and (mob.kills > 0 or (mob.skinned or 0) > 0)
	local known = unseen ~= nil and #unseen > 0
	if known then
		local top = height + (rows > 0 and 2 or 0)
		win.KnownLabel:ClearAllPoints()
		win.KnownLabel:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -top)
		win.KnownLabel:SetText(tried and L["Not seen yet"] or L["What it can drop"])
		win.KnownCount:ClearAllPoints()
		win.KnownCount:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD, -top)
		win.KnownCount:SetText(tried and L["%d of %d found"]:format(found, total) or L["classic database"])
		win.Known:ClearAllPoints()
		win.Known:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + 1, -(top + KNOWN_HEAD))
		local knownRows = Lay(win.Known, win.knownCells, unseen, mob and mob.kills or 0, KNOWN_ICON, KNOWN_GAP, KNOWN_PER_ROW,
			KNOWN_PER_ROW * KNOWN_ROWS, true)
		height = top + KNOWN_HEAD + knownRows * (KNOWN_ICON + LINE + 4)
	elseif win.knownCells[1] then
		Lay(win.Known, win.knownCells, NONE, 0, KNOWN_ICON, KNOWN_GAP, KNOWN_PER_ROW, KNOWN_PER_ROW * KNOWN_ROWS, true)
	end
	win.KnownLabel:SetShown(known)
	win.KnownCount:SetShown(known)
	win.KnownRule:SetShown(known)
	local notes = {}
	if not shown then
		notes[#notes + 1] = L["Target a mob to see what it drops."]
	elseif not mob or mob.kills == 0 then
		notes[#notes + 1] = L["No kills of it yet: kill one on your own and loot it."]
	elseif #drops == 0 then
		notes[#notes + 1] = next(mob.items) and L["Only grey items so far."] or L["Nothing dropped yet."]
	end
	if tried and unseen and #unseen == 0 and total > 0 then
		notes[#notes + 1] = ("|T%s:12:12|t "):format(ALL_FOUND) .. L["All %d drops of the classic database found."]:format(total)
	end
	if IsInGroup and IsInGroup() then
		notes[#notes + 1] = L["In a group: kills aren't counted (the loot is shared)."]
	end
	local any = rows > 0 or known or quests > 0
	win.Note:ClearAllPoints()
	win.Note:SetPoint("TOP", win, "TOP", 0, -height - (any and 0 or 6))
	win.Note:SetText(table.concat(notes, "\n"))
	win.Note:SetShown(#notes > 0)
	-- (a line each, or more when one wraps: most do in the window's width, in German more so)
	local noteHeight = math.max(#notes * LINE, math.ceil(win.Note:GetStringHeight()))
	height = height + (#notes > 0 and (noteHeight + (any and 4 or 10)) or 0) + PAD
	win:SetHeight(math.max(height, head + 16))
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

-- In combat with the setting cardHideInCombat (on): no card (the user: not while fighting).
local function CardHidden()
	if not M.db.cardHideInCombat then
		return false
	end
	if InCombatLockdown then
		return InCombatLockdown() == true
	end
	return Value(UnitAffectingCombat, "player") == true
end

local function CardFollow(self)
	if CardHidden() or not (UnitExists("mouseover") and Value(UnitGUID, "mouseover") == cardGUID) then
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
	card.Quest = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	card.Quest:SetJustifyH("LEFT")
	card.Quest:SetWordWrap(false)
	card:SetScript("OnUpdate", CardFollow)
end

-- Wished items a mob drops go first on its card, with their star: yours (a world drop's too), else the
-- classic database's, faded (you haven't had one). drops may be nil (nothing to show otherwise).
local function WishedFirst(creature, mob, drops)
	local wishes = Bt.Wishes()
	if not next(wishes) then
		return drops
	end
	local first, rest, had = {}, {}, {}
	for _, drop in ipairs(drops or NONE) do
		if not drop.group and wishes[drop.id] and not had[drop.id] then
			first[#first + 1], had[drop.id] = drop, true
		else
			rest[#rest + 1] = drop
		end
		for _, inside in ipairs(drop.group or NONE) do
			if wishes[inside.id] and not had[inside.id] then
				first[#first + 1], had[inside.id] = inside, true
			end
		end
	end
	local said = Bt.Known(creature)
	for id in pairs(wishes) do
		local item = not had[id] and said and said.items[id]
		if item then
			first[#first + 1] = { id = id, chance = item[1], quality = item[2], quest = item[3] or nil, unseen = true, drops = 0, count = 0,
				classic = item[1], out = mob and mob.kills or 0 }
		end
	end
	if #first == 0 then
		return drops
	end
	for _, drop in ipairs(rest) do
		first[#first + 1] = drop
	end
	return first
end

-- Over an enemy: its card (setting hoverCard), small on purpose (the user: not "too large and
-- intrusive"): a line and one row of CARD_CELLS icons, never more, and none in combat (setting
-- cardHideInCombat, on; it goes when a fight starts, comes back after). Killed before: your kills and
-- your likeliest drops (not the database's on top); not yet, with the setting cardUnseen (off): the
-- classic database's likeliest, faded. The only line more: a quest that still wants one of its drops
-- (then also over a mob you haven't killed: useful while questing). Wished items it drops come first
-- (also over a mob you haven't killed).
function Bt.MouseoverChanged()
	if not (M.enabled and M.db.hoverCard) or CardHidden() or not UnitExists("mouseover")
		or not (Value(UnitCanAttack, "player", "mouseover") or Value(UnitIsDead, "mouseover")) then
		if card then
			card:Hide()
		end
		return
	end
	local guid, creature = Bt.Look("mouseover")
	local mob = Bt.Mob(creature)
	local drops, line
	local notKilled = "|cff999999" .. L["Not killed yet: classic database"] .. "|r"
	if mob and mob.kills > 0 then
		drops, line = Bt.Drops(mob, M.db.showPoor, creature), KillsLine(mob, true)
	elseif M.db.cardUnseen then
		local unseen = Bt.Compare(creature, mob, M.db.showPoor)
		if unseen and #unseen > 0 then
			drops, line = unseen, notKilled
		end
	end
	drops = WishedFirst(creature, mob, drops)
	-- A quest that still wants one of its drops: a line (and how many more want others).
	local want, others = nil, 0
	for _, wanted in ipairs(Bt.QuestDrops(creature, mob)) do
		if not wanted.done then
			if want then
				others = others + 1
			else
				want = wanted
			end
		end
	end
	if not (drops or want) then
		if card then
			card:Hide()
		end
		return
	end
	if not card then
		BuildCard()
	end
	cardGUID = guid
	drops = drops or NONE
	card.Kills:SetText(line or notKilled)
	local rows = Lay(card.Grid, card.cells, drops, mob and mob.kills or 0, CARD_ICON, CARD_GAP, CARD_CELLS, CARD_CELLS, false)
	local width = math.max(card.Kills:GetStringWidth(), math.min(#drops, CARD_CELLS) * (CARD_ICON + CARD_GAP) - CARD_GAP)
	local height = rows > 0 and (24 + CARD_ICON + LINE + 6) or 24
	if want then
		card.Quest:SetWidth(0) -- (as wide as its text, to measure it)
		card.Quest:SetText(QuestLine(want) .. (others > 0 and ("  |cff888888+%d|r"):format(others) or ""))
		card.Quest:ClearAllPoints()
		card.Quest:SetPoint("TOPLEFT", 8, -(height - 2))
		local questWidth = math.min(card.Quest:GetStringWidth(), CARD_QUEST_W)
		card.Quest:SetWidth(questWidth)
		width, height = math.max(width, questWidth), height + LINE
	end
	card.Quest:SetShown(want ~= nil)
	card:SetSize(width + 16, height)
	CardFollow(card)
	card:Show()
end

-- The quest log changed what your quests want: the window and the card again.
function Bt.QuestsShown()
	return (win and win:IsShown()) or (card and card:IsShown()) or false
end

function Bt.QuestsChanged()
	if win and win:IsShown() then
		Draw()
	end
	if card and card:IsShown() then
		Bt.MouseoverChanged()
	end
end

-- Everything shown again: the wish list changed (its stars everywhere, the ledger's strip), or items
-- the client didn't know came (names, prices): the window, the card, the ledger.
function Bt.Redraw()
	Bt.QuestsChanged()
	if Bt.DrawLedger then
		Bt.DrawLedger()
	end
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
Bt.When("enable", function()
	C_Timer.After(0, function()
		UpdateButton()
		if M.enabled and M.db.window.shown then
			Bt.Toggle(true)
		end
	end)
end)

-- Switched off: the window and the card hide (whether the window was open stays kept).
Bt.When("disable", function()
	if win then
		win:Hide()
	end
	if card then
		card:Hide()
	end
	UpdateButton()
end)

Bt.When("settings", function()
	UpdateButton()
	Draw()
	if card and not M.db.hoverCard then
		card:Hide()
	end
end)

Bt.On("PLAYER_TARGET_CHANGED", function() Bt.TargetChanged() end)
Bt.On("UPDATE_MOUSEOVER_UNIT", function() Bt.MouseoverChanged() end)
Bt.On("PLAYER_REGEN_ENABLED", function()
	Bt.MouseoverChanged() -- (the fight is over, the mouse still over an enemy: its card)
end)

-- For tests.
function Bt.Frames()
	return win, card, button
end
