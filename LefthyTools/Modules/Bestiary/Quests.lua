local _, ns = ...
local Bt = ns.Bestiary
local NONE, Value, issecret = Bt.NONE, Bt.Value, Bt.issecret

-- Quest drops: the quest log's item objectives matched by name to what a kind of mob can drop (yours
-- and the classic database's), so the window and the card can say "Gnoll Paw: 3/8, 40% each, about
-- 12 more kills" while you're on the quest.

-- The quest log's item objectives, read when first asked after it changed (QUEST_LOG_UPDATE comes
-- often: it only marks them old, and a look half a second later redraws what's up, once). The
-- objectives don't say which item they want, only its name, so a mob's drops (yours and the classic
-- database's) are matched by name.
local QUEST_GAP = 0.5
local wants = {}          -- item name (lower case) -> { name, have, need, done }
local wantsKey = ""       -- the same as text: did anything change?
local wantsOld = true     -- the quest log changed since they were read
local wantsSoon = false   -- a look after the changes is on its way (they come in bursts)
local questIDs = {}       -- quests seen in the log (one under a collapsed header isn't listed)

local function Plain(v)
	if not issecret(v) then
		return v
	end
end

-- "Gnoll Paw: 3/8" (classic) or "3/8 Gnoll Paw" (the modern client): its name, have, need.
local function ParseObjective(text)
	local have, need, name = text:match("^%s*(%d+)%s*/%s*(%d+)%s+(.-)%s*$")
	if not have then
		name, have, need = text:match("^%s*(.-)%s*:%s*(%d+)%s*/%s*(%d+)")
	end
	name = name and name:gsub("%s*%(.-%)$", "") -- (a "(Complete)" behind it)
	if name and name ~= "" then
		return name, tonumber(have), tonumber(need)
	end
end

-- Reads the quest log's objectives; returns whether what they want changed.
local function ReadWants()
	wantsOld = false
	wipe(wants)
	local log = C_QuestLog
	if log and log.GetNumQuestLogEntries and log.GetInfo and log.GetQuestObjectives then
		for index = 1, tonumber(Value(log.GetNumQuestLogEntries)) or 0 do
			local info = Value(log.GetInfo, index)
			local id = type(info) == "table" and not Plain(info.isHeader) and not Plain(info.isHidden) and Plain(info.questID)
			if type(id) == "number" and id > 0 then
				questIDs[id] = true
			end
		end
		for id in pairs(questIDs) do
			if log.GetLogIndexForQuestID and not Value(log.GetLogIndexForQuestID, id) then
				questIDs[id] = nil -- (turned in or abandoned)
			else
				local objectives = Value(log.GetQuestObjectives, id)
				for _, o in ipairs(type(objectives) == "table" and objectives or NONE) do
					local text, name, have, need = Plain(o.text), nil, nil, nil
					if type(text) == "string" then
						name, have, need = ParseObjective(text)
					end
					if name then
						have = type(Plain(o.numFulfilled)) == "number" and o.numFulfilled or have
						need = type(Plain(o.numRequired)) == "number" and o.numRequired > 0 and o.numRequired or need
						local key = name:lower()
						local was = wants[key]
						if not was or need > was.need then -- (two quests wanting the same: the bigger)
							wants[key] = { name = name, have = have, need = need, done = Plain(o.finished) == true or have >= need }
						end
					end
				end
			end
		end
	end
	local parts = {}
	for key, want in pairs(wants) do
		parts[#parts + 1] = ("%s:%d/%d"):format(key, want.have, want.need)
	end
	table.sort(parts)
	local text = table.concat(parts, ";")
	local changed = text ~= wantsKey
	wantsKey = text
	return changed
end

local function QuestWants()
	if wantsOld then
		ReadWants()
	end
	return wants
end

-- The quest log changed (or your bags): half a second later, if the window or the card is up and
-- what your quests want changed, they redraw.
local function QuestLogChanged()
	wantsOld = true
	if wantsSoon then
		return
	end
	wantsSoon = true
	C_Timer.After(QUEST_GAP, function()
		wantsSoon = false
		if wantsOld and Bt.QuestsShown and Bt.QuestsShown() and ReadWants() and Bt.QuestsChanged then
			Bt.QuestsChanged()
		end
	end)
end

Bt.On("QUEST_LOG_UPDATE", QuestLogChanged)
Bt.On("BAG_UPDATE_DELAYED", QuestLogChanged)
Bt.When("enable", function()
	wantsOld = true -- (the quest log may have changed while switched off)
end)

-- How likely a kind of mob drops an item, per kill: the classic database's chance (for a quest item,
-- while on its quest), else your own; nil: neither says it drops it. And how many come each time
-- (yours; 1 before you've had one).
function Bt.ChanceOf(creature, mob, id)
	local said = Bt.Known(creature)
	said = said and said.items[id]
	local item = mob and mob.items[id]
	local each = item and item[1] > 0 and item[2] / item[1] or 1
	if said then
		return said[1], each
	elseif item and mob.kills > 0 then
		return (Bt.Chance(mob, item)), each
	end
end

-- What your quests want collected that this kind of mob can drop: { { id, name, have, need, done,
-- chance (Bt.ChanceOf; nil: not known), more (about how many more kills) }, ... }, the ones still
-- wanted first.
function Bt.QuestDrops(creature, mob)
	local want = creature and QuestWants()
	if not (want and next(want)) then
		return NONE
	end
	local list, tried = {}, {}
	local said = Bt.Known(creature)
	for _, part in ipairs({ said and said.items or NONE, mob and mob.items or NONE }) do
		for id in pairs(part) do
			if not tried[id] then
				tried[id] = true
				local name = Bt.ItemNameOf(id, mob and mob.items[id])
				local wanted = name and want[name:lower()]
				if wanted then
					local chance, each = Bt.ChanceOf(creature, mob, id)
					local left = wanted.need - wanted.have
					list[#list + 1] = { id = id, name = wanted.name, have = wanted.have, need = wanted.need, done = wanted.done,
						chance = chance, more = chance and chance > 0 and not wanted.done and left > 0
							and math.max(1, math.floor(left / (chance * each) + 0.5)) or nil }
				end
			end
		end
	end
	table.sort(list, function(a, b)
		if a.done ~= b.done then
			return not a.done
		end
		return a.id < b.id
	end)
	return list
end
