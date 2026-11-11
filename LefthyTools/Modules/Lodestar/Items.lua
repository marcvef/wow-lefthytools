local _, ns = ...
local LT = ns.LT
local L = ns.L
local Q = ns.Lodestar or {}; ns.Lodestar = Q

-- Quest items (docs/lodestar.md, "Quest items"): which quests an item in your bags is for and where
-- they stand for you, so you know what to keep and what to discard.
--
--   * Item tooltips (setting itemTooltips): "Lodestar: for <quest> · in your log (3/8)", "... · ready
--     to turn in", "... · not taken yet: you can take it", "... · done"; for an item that starts one
--     "Lodestar: starts the quest <quest> · you can start it" (or "already done: you can discard it");
--     those that need it first, each in the one order of quests (Q.Compare), at most four, then "and N
--     more". Last, when no quest needs it any more: "No quest needs it any
--     more: you can discard it"; when only some do: "Still needed for <quest>". The data's (Data.lua's
--     Q.ItemQuests) and, for a quest the data doesn't know with it (Forever's own), the quest log: a
--     quest of my log whose objective names the item (its name from the client, so any language).
--   * Q.ItemDone(item): no quest needs it any more (each one done, skipped or not for me, and nothing
--     it starts I can still take). The sorted bags (Misc Tweaks) mark such items in their quest items
--     section (Q.ItemMarked: the same with Lodestar and the setting on).
--
-- A post-call on the game's item tooltips (TooltipDataProcessor, as Chronicle's "Craftable by"):
-- GameTooltip and ItemRefTooltip (chat links), so bags, the bank, loot, vendors and links. Only once
-- the quest data is loaded (Lodestar.lua loads it a few seconds after the loading screen, and starts
-- the item index a second later): a hover never loads it. An item's lines are made the first time
-- it's hovered and kept until the data, my progress or my quest log changes (Q.dataGen,
-- Q.progressGen, the quest log's events counted here): a hover is a table lookup.

local TIP_MAX = 4
local ACTIVE = { 1, 0.82, 0 }
local TURNIN = { 0.35, 0.85, 0.35 }
local AVAILABLE = { 0.45, 0.8, 1 }
local LOCKED = { 1, 0.55, 0.2 }
local GREY = { 0.6, 0.6, 0.6 }
local DISCARD = { 0.55, 0.8, 0.55 }
local KEEP = { 0.85, 0.85, 0.85 }
-- The one order's statuses (Engine.lua's Q.Compare: ready, in my log, to take, coming up, blocked, done,
-- other), also for a quest of my log the data doesn't have (Q.Compare doesn't know it).
local RANK = { ready = 1, active = 2, available = 3, level = 4, locked = 5, done = 6, other = 7 }

local M = Q.module
local lines, linesKey = {}, nil -- item -> { { text, r, g, b } }, and what they're of
local doneOf, doneKey = {}, nil -- Q.ItemDone: item -> true / false
local logGen = 0                -- the quest log's changes (its events, counted while listening)
local logIndex, logKey          -- my quest log's item objectives, and what it's of

-- Whether a quest still needs the item for its role, by my status: a quest done, skipped or not
-- for me doesn't; nor a quest it starts that's in my log.
local function Needs(role, status)
	if status == "done" or status == "other" then
		return false
	end
	if role == "starts" then
		return status ~= "active"
	end
	return true
end

-- What the caches are of. Asking the engine first reads a changed quest log (its events only note
-- it), so progressGen has moved by then.
local function Key()
	if Q.Status then
		Q.Status(0)
	end
	return tostring(Q.dataGen) .. ":" .. tostring(Q.progressGen) .. ":" .. logGen .. ":" .. tostring(Q.itemGen)
end

-- The item's name from the client (its language), nil when it doesn't know it yet.
local function ItemName(item)
	local name = C_Item and C_Item.GetItemInfo and LT.Value(C_Item.GetItemInfo, ("item:%d"):format(item))
	if type(name) ~= "string" or name == "" then
		name = C_Item and C_Item.GetItemNameByID and LT.Value(C_Item.GetItemNameByID, item)
	end
	return type(name) == "string" and name ~= "" and name or nil
end

-- My quest log's item objectives (Q.LogObjectives): { byQuest = { [quest] = { [item] = entry } } (the
-- ones the data names), byName = { [lower name] = { entry } }, list = { entry } }, entry = { quest,
-- have, need, text (lower) }. Made again when the log or the data changes.
local function LogIndex()
	local key = logGen .. ":" .. tostring(Q.dataGen)
	if logIndex and logKey == key then
		return logIndex
	end
	local index = { byQuest = {}, byName = {}, list = {} }
	local log = C_QuestLog
	local n = log and log.GetNumQuestLogEntries and LT.Value(log.GetNumQuestLogEntries)
	for i = 1, type(n) == "number" and n or 0 do
		local info = LT.Value(log.GetInfo, i)
		local id = type(info) == "table" and not info.isHeader and info.questID
		if type(id) == "number" and LT.Readable(id) and Q.LogObjectives then
			for _, o in ipairs(Q.LogObjectives(id)) do
				if o.kind == "item" or o.kind == nil then
					local entry = { quest = id, have = o.have, need = o.need, text = o.text:lower() }
					index.list[#index.list + 1] = entry
					local name = type(o.name) == "string" and o.name:lower()
					if name and name ~= "" then
						index.byName[name] = index.byName[name] or {}
						table.insert(index.byName[name], entry)
					end
					local data = o.data
					if type(data) == "table" and data.kind == "item" and data.id then
						index.byQuest[id] = index.byQuest[id] or {}
						index.byQuest[id][data.id] = entry
					end
				end
			end
		end
	end
	logIndex, logKey = index, key
	return index
end

-- The log's objectives that are the item by name: exactly its name, else its name in the text.
local function ByName(index, name)
	local lower = name:lower()
	local found = index.byName[lower]
	if found then
		return found
	end
	found = {}
	for _, entry in ipairs(index.list) do
		if entry.text:find(lower, 1, true) then
			found[#found + 1] = entry
		end
	end
	return found
end

-- The item's objective in a quest of my log: the one the data names, else by name.
local function LogEntry(index, quest, item, name)
	local mine = index.byQuest[quest]
	if mine and mine[item] then
		return mine[item]
	end
	if name then
		for _, entry in ipairs(ByName(index, name)) do
			if entry.quest == quest then
				return entry
			end
		end
	end
end

-- What a quest's line says after its name, and its colour.
local function State(id, role, status, entry)
	local starts = role == "starts"
	if status == "active" then
		if starts then
			return L["in your log"], ACTIVE
		end
		if C_QuestLog and C_QuestLog.IsComplete and LT.Value(C_QuestLog.IsComplete, id) == true then
			return L["ready to turn in"], TURNIN
		end
		if entry and entry.have and entry.need then
			return L["in your log (%d/%d)"]:format(entry.have, entry.need), ACTIVE
		end
		return L["in your log"], ACTIVE
	elseif status == "done" then
		return starts and L["already done: you can discard it"] or L["done"], GREY
	elseif status == "other" then
		return Q.WhyOther and Q.WhyOther(id) == "closed" and L["skipped"] or L["not for you"], GREY
	elseif status == "available" then
		return starts and L["you can start it"] or L["not taken yet: you can take it"], AVAILABLE
	elseif status == "level" then
		local quest = Q.Quest and Q.Quest(id)
		local level = quest and tonumber(quest.minLevel)
		if level then
			return (starts and L["from level %d"] or L["not taken yet: from level %d"]):format(level), GREY
		end
		return L["level too low"], GREY
	end
	return starts and L["needs another quest first"] or L["not taken yet: needs another quest first"], LOCKED
end

-- Whether quest line a goes before b: the ones that need the item first, then by status (ready, in my
-- log, to take, coming up, blocked, done), then the one order of quests (Q.Compare: for my level, hard,
-- ...; by level and title); a quest of my log the data doesn't have after those it has, by its ID.
local function Before(a, b)
	if a.needed ~= b.needed then
		return a.needed
	end
	if a.id == b.id then
		return a.role ~= "starts" and b.role == "starts"
	end
	if a.rank ~= b.rank then
		return a.rank < b.rank
	end
	if a.known ~= b.known then
		return a.known
	end
	if Q.Compare and a.known then
		return Q.Compare(a.id, b.id) == true
	end
	return a.id < b.id
end

-- The item's quests: the data's (Q.ItemQuests), then quests of my log whose objective names the item
-- that the data doesn't have with it: { { id, role, status, needed, entry } }, the ones that need it
-- first, in the one order. nil: the index isn't made yet. complete: false when the item's name was wanted but the
-- client doesn't know it yet (then not kept).
local function Entries(item)
	local data = Q.ItemQuests and Q.ItemQuests(item)
	if not data then
		return nil
	end
	local index = LogIndex()
	local name = ItemName(item)
	local list, seen = {}, {}
	for _, e in ipairs(data) do
		local status = Q.StatusOf(e.id)
		list[#list + 1] = { id = e.id, role = e.role, status = status, needed = Needs(e.role, status), known = true,
			entry = status == "active" and LogEntry(index, e.id, item, name) or nil }
		if e.role ~= "starts" then
			seen[e.id] = true
		end
	end
	if name then
		for _, entry in ipairs(ByName(index, name)) do
			if not seen[entry.quest] then
				seen[entry.quest] = true
				list[#list + 1] = { id = entry.quest, role = "objective", status = "active", needed = true, entry = entry,
					known = Q.Quest and Q.Quest(entry.quest) ~= nil }
			end
		end
	end
	for _, e in ipairs(list) do
		local ready = e.status == "active" and C_QuestLog and C_QuestLog.IsComplete and LT.Value(C_QuestLog.IsComplete, e.id) == true
		e.rank = RANK[ready and "ready" or e.status] or 9
	end
	table.sort(list, Before)
	return list, name ~= nil or #index.list == 0
end

-- The lines for an item: { { text, r, g, b } } (an empty list: none); nil: not ready yet.
local function Build(item)
	local list, complete = Entries(item)
	if not list then
		return nil
	end
	local out, needed = {}, {}
	for _, e in ipairs(list) do
		if e.needed then
			needed[#needed + 1] = e
		end
	end
	for i, e in ipairs(list) do
		if i > TIP_MAX then
			out[#out + 1] = { L["Lodestar: and %d more"]:format(#list - TIP_MAX), GREY[1], GREY[2], GREY[3] }
			break
		end
		local title = Q.Title(e.id)
		local head = e.role == "starts" and L["Lodestar: starts the quest %s"]:format(title) or L["Lodestar: for %s"]:format(title)
		local text, color = State(e.id, e.role, e.status, e.entry)
		out[#out + 1] = { head .. " · " .. text, color[1], color[2], color[3] }
	end
	if #list > 0 and #needed == 0 and not (#list == 1 and list[1].role == "starts") then
		out[#out + 1] = { L["No quest needs it any more: you can discard it"], DISCARD[1], DISCARD[2], DISCARD[3] }
	elseif #needed > 0 and #needed < #list then
		local first = Q.Title(needed[1].id)
		local text = #needed == 1 and L["Still needed for %s"]:format(first) or L["Still needed for %s and %d more"]:format(first, #needed - 1)
		out[#out + 1] = { text, KEEP[1], KEEP[2], KEEP[3] }
	end
	return out, complete
end

local function Lines(item)
	local key = Key()
	if key ~= linesKey then
		linesKey = key
		wipe(lines)
	end
	local known = lines[item]
	if known then
		return known
	end
	local out, complete = Build(item)
	if out and complete then
		lines[item] = out -- (not kept while the index is being made or the client doesn't know its name yet)
	end
	return out
end

-- No quest needs the item any more: the data ties it to quests and each is done, skipped or not for
-- me, and it starts nothing I can still take (a quest it starts that's in my log doesn't need it).
-- false: one still does; nil: the item is for no quest the data knows, or the data or its index isn't
-- there yet (never loads it). Kept per data, progress and quest log change.
function Q.ItemDone(item)
	item = tonumber(item)
	if not (item and Q.IsLoaded and Q.IsLoaded() and Q.ItemQuests) then
		return nil
	end
	local key = Key()
	if key ~= doneKey then
		doneKey = key
		wipe(doneOf)
	end
	local done = doneOf[item]
	if done == nil then
		local data = Q.ItemQuests(item)
		if not data then
			return nil
		end
		done = #data > 0 or "none"
		for _, e in ipairs(data) do
			if Needs(e.role, Q.StatusOf(e.id)) then
				done = false
				break
			end
		end
		doneOf[item] = done
	end
	if done == "none" then
		return nil
	end
	return done
end

-- What the sorted bags mark (Misc Tweaks): Q.ItemDone, with Lodestar and the setting on.
function Q.ItemMarked(item)
	return M and M.enabled and M.db and M.db.itemTooltips and Q.ItemDone(item) == true or false
end

---------------------------------------------------------------------------
-- The tooltip
---------------------------------------------------------------------------

local function OnItemTooltip(tooltip, info)
	if not (M and M.enabled and M.db and M.db.itemTooltips) or (tooltip ~= GameTooltip and tooltip ~= _G.ItemRefTooltip) then
		return
	end
	if (tooltip.IsForbidden and tooltip:IsForbidden()) or type(info) ~= "table" or LT.IsSecret(info) then
		return
	end
	local item = info.id
	if type(item) ~= "number" or LT.IsSecret(item) then
		return
	end
	if not (Q.IsLoaded and Q.IsLoaded()) then
		return -- (never loaded by a hover)
	end
	local list = Lines(item)
	for _, line in ipairs(list or {}) do
		tooltip:AddLine(line[1], line[2], line[3], line[4])
	end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
	and Enum.TooltipDataType.Item then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, info)
		LT.Guard("Lodestar.items", OnItemTooltip, tooltip, info)
	end)
end

-- The quest log's changes, counted (the lines' progress "3/8" and the log's quests), only while the
-- setting is on: the handler only counts.
local listener = CreateFrame("Frame")
listener:SetScript("OnEvent", function()
	logGen = logGen + 1
end)
local LOG_EVENTS = { "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }

local function Listen()
	if M and M.enabled and M.db and M.db.itemTooltips then
		for _, event in ipairs(LOG_EVENTS) do
			pcall(listener.RegisterEvent, listener, event)
		end
	else
		listener:UnregisterAllEvents()
	end
	logGen = logGen + 1 -- (what happened meanwhile: not counted)
end

Q.When("enable", Listen)
Q.When("disable", Listen)
Q.When("settings", Listen)
