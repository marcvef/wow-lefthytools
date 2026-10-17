local _, ns = ...
local LT = ns.LT
local L = ns.L
local Bt = ns.Bestiary
local Value = Bt.Value

-- How the Bestiary writes things, in the window, the card and the ledger (and the fight stream's
-- tooltips): quality colours, chances, coin, a mob's kind, its kills, what a kill pays, quest lines.

local DOT = "  |cff888888·|r  "
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local ALL_FOUND = "Interface\\RaidFrame\\ReadyCheck-Ready"
Bt.QUESTION, Bt.QUEST_ICON, Bt.ALL_FOUND = QUESTION, QUEST_ICON, ALL_FOUND

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
Bt.QuestLine, Bt.QualityColor, Bt.Decimal, Bt.ItemIcon, Bt.ItemName, Bt.Kind = QuestLine, QualityColor, Decimal, ItemIcon, ItemName, Kind

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

-- What a kill of a kind pays, the parts known (Bt.Worth, Bt.Pace): short for the
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
