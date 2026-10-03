local _, ns = ...
local LT = ns.LT
local M = LT:GetModule("beacon")
local B = ns.Beacon

-- Alerts about friends: a chat line when one of them dies (Beacon.lua spots the change from alive
-- to dead or ghost in their state). Chat output stays English, like the rest of the chat lines.

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

-- A friend just died; foe is whom they were fighting, if anyone. On the driver tick.
function B.ShowDeath(peer, gameAccountID, foe)
	local where = B.WhereText(peer, gameAccountID)
	if M.db.deathAlert then
		M:Print(("%s %s died%s%s."):format(SKULL, ColouredName(peer), where and (" in " .. where) or "",
			foe and (", fighting " .. foe) or ""))
	end
	B.Notify("death", peer, { where = where, foe = foe, level = peer.level })
end
