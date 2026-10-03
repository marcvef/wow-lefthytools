local _, ns = ...
local LT = ns.LT
local L = ns.L
local M = LT:GetModule("beacon")
local B = ns.Beacon

-- Alerts about friends: a chat line when one of them dies (Beacon.lua spots the change from alive
-- to dead or ghost in their state). Chat output stays English, like the rest of the chat lines.
-- Also a friend summed up in a few lines for lists (B.FriendLines).

local SKULL = "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:14:14|t"

local function ColouredName(peer)
	return LT.Window.ClassColorCode(peer.classFile) .. (peer.name or "?") .. "|r"
end

-- "Duskwood - Raven Hill", from Battle.net (current) and their last state.
function B.WhereText(peer, gameAccountID)
	local info = gameAccountID and C_BattleNet.GetGameAccountInfoByID(gameAccountID)
	local area = info and info.areaName or peer.area
	local subzone = peer.subzone ~= "" and peer.subzone ~= area and peer.subzone or nil
	if area and subzone then
		return area .. " - " .. subzone
	end
	return area or subzone
end

---------------------------------------------------------------------------
-- A friend in a few lines, for lists (the AFK screen, Chronicle's Friends page)
---------------------------------------------------------------------------

-- Friends with LefthyTools whose name is known, by name: { { id = gameAccountID, peer }, ... }.
function B.FriendList()
	local list = {}
	for gameAccountID, peer in pairs(B.peers) do
		if peer.name then
			list[#list + 1] = { id = gameAccountID, peer = peer }
		end
	end
	table.sort(list, function(a, b) return a.peer.name < b.peer.name end)
	return list
end

-- What a friend is doing right now: dead, or fighting (and how many), and the quest they track.
local function Doing(peer)
	local parts = {}
	if peer.ghost then
		parts[#parts + 1] = "|cffff5050" .. L["Ghost"] .. "|r"
	elseif peer.dead then
		parts[#parts + 1] = "|cffff5050" .. L["Dead"] .. "|r"
	elseif peer.combat then
		local mobs, text = peer.mobs or 0, nil
		if peer.target and peer.target ~= "" then
			text = mobs > 1 and L["Fighting %s and %d more"]:format(peer.target, mobs - 1) or L["Fighting %s"]:format(peer.target)
		elseif mobs > 1 then
			text = L["In combat with %d enemies"]:format(mobs)
		elseif mobs == 1 then
			text = L["In combat with 1 enemy"]
		else
			text = L["In combat"]
		end
		parts[#parts + 1] = "|cffff5050" .. text .. "|r"
	end
	local quest = peer.quest
	if quest then
		local progress = quest.done and L["Ready to turn in"] or (quest.objective ~= "" and quest.objective or nil)
		parts[#parts + 1] = "|cffffd200" .. L["Quest: %s"]:format(quest.title) .. "|r"
			.. (progress and ("|cffcccccc - " .. progress .. "|r") or "")
	end
	return #parts > 0 and table.concat(parts, "  ") or nil
end

-- Appends up to three lines to `lines`: name (and <AFK>), level and progress, "In your group";
-- zone - subzone and distance; what they're doing (only when there's something).
function B.FriendLines(lines, peer, gameAccountID)
	local info = C_BattleNet.GetGameAccountInfoByID(gameAccountID)
	local level = info and info.characterLevel or peer.level
	local head = ColouredName(peer)
	if info and info.isGameAFK then
		head = head .. " |cff999999<AFK>|r"
	end
	if level then
		head = head .. "  |cffcccccc" .. (peer.xpPercent and L["Level %d (%d%%)"]:format(level, peer.xpPercent)
			or L["Level %d"]:format(level)) .. "|r"
	end
	if peer.groupUnit then
		head = head .. "  |cff4da6ff" .. L["In your group"] .. "|r"
	end
	lines[#lines + 1] = head
	local where = B.WhereText(peer, gameAccountID) or "?"
	local distance = peer.hasPos and B.DistanceText and B.DistanceText(peer.continent, peer.north, peer.west)
	lines[#lines + 1] = "|cffaaaaaa" .. where .. (distance and (", " .. distance) or "") .. "|r"
	local doing = Doing(peer)
	if doing then
		lines[#lines + 1] = doing
	end
end

-- A friend just died; foe is whom they were fighting, if anyone. On the driver tick.
function B.ShowDeath(peer, gameAccountID, foe)
	local where = B.WhereText(peer, gameAccountID)
	if M.db.deathAlert then
		M:Print(("%s %s died%s%s."):format(SKULL, ColouredName(peer), where and (" in " .. where) or "",
			foe and (", fighting " .. foe) or ""))
	end
	B.Notify("death", peer, { where = where, foe = foe, level = peer.level })
end
