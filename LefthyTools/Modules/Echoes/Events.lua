local _, ns = ...
local LT = ns.LT
local E = ns.Echoes
local C = E.capture

-- What happens on the way, as lines (docs/echoes.md, Recording): level-ups (L), quests accepted,
-- turned in and abandoned (a, Q, A), deaths (D) and coming back to life (r), every kill of yours, your
-- pet's or your group's (k), loot green and better (l), gathering (h), new mounts, pets, toys,
-- achievements and recipes (n), bosses (B), flights (F) and battleground results (b). Names go with
-- them once per page (E.Name: creatures, quests, items). Changes.lua writes what's compared with what
-- was written before (XP, gear, reputation, ...); Path.lua the path.
--
-- Never lags the client: handlers note what happened in a queue (a few values each; LOOT_READY reads
-- the loot window's slots at once, as it may be gone by the next tick); the tick writes the queue,
-- each tick's events at one spot (E.capture.Spot first: the path brought up to now). Secret values
-- are skipped: a secret kill, cast or loot line is left out, never stored.

local issecret, Value, Readable = LT.IsSecret, LT.Value, LT.Readable

local QUEUE_MAX = 100        -- events noted and not written yet (more in one tick: the rest are dropped)
local SEEN_KEEP = 200        -- mobs remembered (level, classification, name) from target, mouseover and nameplates
local KILLS_KEEP = 64        -- corpses remembered: each counts once
local NODES_KEEP = 32        -- gathered nodes remembered: each counts once
local FOE_MEMORY = 15        -- seconds: the last enemy you fought counts as your killer this long
local DEATH_REPEAT = 10      -- PLAYER_DEAD again this soon (or while still dead) is the same death
local QUEST_DECIDE = 1.5     -- seconds after QUEST_REMOVED: turned in or abandoned?
local GATHER_GAP = 1.5       -- seconds from a gathering spell to its loot window
local LOOT_SOURCE_FOR = 5    -- seconds a loot window's corpses explain loot lines
local REZ_FOR, SPIRIT_FOR = 70, 120 -- seconds a resurrection offer, the spirit healer's question count
local BOSS_DEDUPE = 30       -- ENCOUNTER_END and BOSS_KILL report the same kill
local HEARTHSTONE = 8690

-- UnitClassification -> the line's letter (docs/echoes.md: n e r x w).
local CLASS = { normal = "n", elite = "e", rare = "r", rareelite = "x", worldboss = "w", trivial = "n", minus = "n" }
E.CLASS = CLASS

-- Teleport spells (why p): the mage's teleports, Astral Recall, Teleport: Moonglade, the engineers'
-- Dimensional Ripper - Everlook and Ultrasafe Transporter: Gadgetzan.
local TELEPORTS = { [3561] = true, [3562] = true, [3563] = true, [3565] = true, [3566] = true, [3567] = true,
	[556] = true, [18960] = true, [23442] = true, [23453] = true }
-- Gathering spells (each rank's ID; ranks not listed by their name): Herb Gathering, Mining, Skinning.
local GATHERING = { [2366] = "h", [2368] = "h", [3570] = "h", [11993] = "h", [2575] = "o", [2576] = "o", [3564] = "o",
	[10248] = "o", [8613] = "s", [8617] = "s", [8618] = "s", [10768] = "s" }

local function Yes(f, ...)
	return Value(f, ...) == true
end

---------------------------------------------------------------------------
-- What the capture remembers this session (reset at every start; E.capture.Reset)
---------------------------------------------------------------------------

local S = {}
local seenInfo, seenOrder = {}, {}   -- GUID -> { level, cls, name }; the GUIDs, a ring of SEEN_KEEP
local killed, killedOrder = {}, {}   -- corpse GUID -> true; a ring of KILLS_KEEP
local nodes, nodesOrder = {}, {}     -- gathered node GUID -> true; a ring of NODES_KEEP
local titles = {}                    -- quest ID -> title (it may be gone from the log when it's turned in)
local removed, turnedIn = {}, {}     -- quest ID -> GetTime(): removed from the log, turned in
local lootFrom = {}                  -- item ID -> the creature whose corpse the last loot window was
local foe = {}                       -- the last enemy you fought: at, kind, id, level, cls, pvp, name

local function DeadOrGhost()
	return Yes(UnitIsDeadOrGhost, "player")
end

local function Reset()
	S.seenNext, S.killedNext, S.nodesNext = 0, 0, 0
	wipe(seenInfo)
	wipe(seenOrder)
	wipe(killed)
	wipe(killedOrder)
	wipe(nodes)
	wipe(nodesOrder)
	wipe(titles)
	wipe(removed)
	wipe(turnedIn)
	wipe(lootFrom)
	wipe(foe)
	S.lootAt = -math.huge
	S.gatherKind, S.gatherAt, S.gatheredAt = nil, -math.huge, -math.huge
	-- Dead or a ghost since a death seen; and (GetTime) the death counted: the next counts once alive
	-- and DEATH_REPEAT after. Logged in or /reloaded dead (no PLAYER_DEAD then): that death was
	-- counted before it, its release and coming back to life still are.
	S.down = DeadOrGhost()
	S.deadAt = S.down and GetTime() or nil
	S.spiritAt, S.rezAt = nil, nil -- the spirit healer asked, a resurrection offered
	S.bossID, S.bossAt = nil, -math.huge
	S.n = 0
end

---------------------------------------------------------------------------
-- The queue: handlers note, the tick writes (in the order they happened)
---------------------------------------------------------------------------

local qk, q1, q2, q3, q4, q5, q6 = {}, {}, {}, {}, {}, {}, {}

local function Note(kind, a, b, c, d, e, f)
	local n = S.n
	if n >= QUEUE_MAX then
		return
	end
	n = n + 1
	S.n = n
	qk[n], q1[n], q2[n], q3[n], q4[n], q5[n], q6[n] = kind, a, b, c, d, e, f
end

local W = {} -- kind -> function(...) writing its line(s)
local guardNames = setmetatable({}, { __index = function(t, kind)
	t[kind] = "E.capture " .. kind
	return t[kind]
end }) -- (LT.Guard's name for each kind, made once)
local fields = {} -- (one list for lines with a list at the end: no table per line)

-- Writes what's noted, at one spot (the path brought up to now first): on the tick, and when the
-- session ends (Path.lua).
function C.Flush()
	local n = S.n
	if n == 0 then
		return
	end
	C.Spot()
	S.n = 0
	for i = 1, n do
		local write = W[qk[i]]
		if write then
			LT.Guard(guardNames[qk[i]], write, q1[i], q2[i], q3[i], q4[i], q5[i], q6[i])
		end
		qk[i], q1[i], q2[i], q3[i], q4[i], q5[i], q6[i] = nil, nil, nil, nil, nil, nil, nil
	end
end

---------------------------------------------------------------------------
-- Mobs seen: level, classification, name (for kills and deaths)
---------------------------------------------------------------------------

-- Remembers a creature unit; returns what's known of it, its GUID and its creature ID.
local function Look(unit)
	local guid = Value(UnitGUID, unit)
	local creature = LT.CreatureOf(guid)
	if not creature or Yes(UnitIsPlayer, unit) then
		return nil
	end
	local info = seenInfo[guid]
	if not info then
		S.seenNext = S.seenNext % SEEN_KEEP + 1
		local old = seenOrder[S.seenNext]
		if old then -- (its table goes to this one)
			info, seenInfo[old] = seenInfo[old], nil
			info.level, info.cls, info.name = nil, nil, nil
		end
		info = info or {}
		seenOrder[S.seenNext], seenInfo[guid] = guid, info
	end
	info.level = Value(UnitLevel, unit) or info.level
	local class = Value(UnitClassification, unit)
	info.cls = class and CLASS[class] or info.cls
	local name = Value(UnitName, unit)
	info.name = type(name) == "string" and name or info.name
	return info, guid, creature
end

E.On("PLAYER_TARGET_CHANGED", function() Look("target") end)
E.On("UPDATE_MOUSEOVER_UNIT", function() Look("mouseover") end)
E.On("NAME_PLATE_UNIT_ADDED", function(unit)
	if Readable(unit) then
		Look(unit)
	end
end)

-- Remembers in a ring of size keep: true if it was new.
local function Once(set, order, key, field, keep)
	if set[key] then
		return false
	end
	S[field] = S[field] % keep + 1
	local old = order[S[field]]
	if old then
		set[old] = nil
	end
	order[S[field]], set[key] = key, true
	return true
end

---------------------------------------------------------------------------
-- Level-ups, quests
---------------------------------------------------------------------------

E.On("PLAYER_LEVEL_UP", function(level)
	Note("L", Readable(level) and level or nil)
end)

W.L = function(level)
	local cap = C.Cap()
	E.Line("L", level or Value(UnitLevel, "player"), cap and type(cap.played) == "number" and math.floor(cap.played) or nil)
end

local function Title(id)
	local title = titles[id]
	if not title then
		title = C_QuestLog and Value(C_QuestLog.GetTitleForQuestID, id)
		title = type(title) == "string" and title ~= "" and title or nil
		titles[id] = title
	end
	return title
end

E.On("QUEST_ACCEPTED", function(questID)
	if Readable(questID) then
		Note("a", questID)
	end
end)

E.On("QUEST_TURNED_IN", function(questID, xp, money)
	if Readable(questID) then
		turnedIn[questID] = GetTime()
		Note("Q", questID, Readable(xp) and xp or nil, Readable(money) and money or nil)
	end
end)

E.On("QUEST_REMOVED", function(questID)
	if Readable(questID) then
		removed[questID] = GetTime()
		Title(questID) -- (while it may still be known)
	end
end)

W.a = function(id)
	E.Name("q", id, Title(id))
	E.Line("a", id)
end

W.Q = function(id, xp, money)
	E.Name("q", id, Title(id))
	E.Line("Q", id, xp, money)
end

W.A = function(id)
	E.Name("q", id, Title(id))
	E.Line("A", id)
end

-- Removed from the log: turned in (QUEST_TURNED_IN came, or the game says it's done) or abandoned.
local function Quests(now)
	if next(removed) == nil then
		return
	end
	for id, at in pairs(removed) do
		if now - at >= QUEST_DECIDE then
			removed[id] = nil
			if not (turnedIn[id] and now - turnedIn[id] < 30) then
				local done = C_QuestLog and Yes(C_QuestLog.IsQuestFlaggedCompleted, id)
				Note(done and "Q" or "A", id)
			end
		end
	end
	for id, at in pairs(turnedIn) do
		if now - at >= 30 then
			turnedIn[id] = nil
		end
	end
end

---------------------------------------------------------------------------
-- Deaths, the last enemy, coming back
---------------------------------------------------------------------------

-- In a fight: your attackable target is the one that'll have killed you (FOE_MEMORY). The same
-- target as on the last tick: only its time and level are read again.
local function TrackFoe(now)
	if not (LT.InCombat() and Yes(UnitExists, "target") and Yes(UnitCanAttack, "player", "target")) then
		return
	end
	local guid = Value(UnitGUID, "target")
	if guid and guid == foe.guid and foe.at then
		foe.at, foe.level = now, Value(UnitLevel, "target") or foe.level
		return
	end
	foe.at, foe.name, foe.guid = now, nil, guid
	if Yes(UnitIsPlayer, "target") then -- (a player: only class and level, no name)
		local ok, _, class = pcall(UnitClass, "target")
		foe.kind, foe.id, foe.level, foe.cls, foe.pvp = "p", ok and Readable(class) and class or nil, Value(UnitLevel, "target"), nil, true
		return
	end
	local info, _, creature = Look("target")
	if creature then
		foe.kind, foe.id, foe.level, foe.cls, foe.name = "c", creature, info.level, info.cls, info.name
		foe.pvp = false
	else -- (not readable, or a player's pet)
		foe.kind, foe.id, foe.level, foe.cls = "-", nil, nil, nil
		foe.pvp = Yes(UnitPlayerControlled, "target")
	end
end

E.On("PLAYER_DEAD", function()
	if S.deadAt then
		return -- (the same death again)
	end
	S.deadAt, S.down = GetTime(), true
	S.spiritAt, S.rezAt = nil, nil
	Note("D")
end)

W.D = function()
	local level = Value(UnitLevel, "player")
	if foe.at and GetTime() - foe.at <= FOE_MEMORY then
		if foe.kind == "c" then
			E.Name("c", foe.id, foe.name)
		end
		E.Line("D", level, foe.kind, foe.id, foe.level, foe.cls, foe.pvp)
	else
		E.Line("D", level, "-", nil, nil, nil, false)
	end
	wipe(foe)
end

E.On("CONFIRM_XP_LOSS", function() S.spiritAt = GetTime() end)
E.On("RESURRECT_REQUEST", function() S.rezAt = GetTime() end)
E.On("CONFIRM_SUMMON", function() C.NoteCause("u") end)

local function How()
	local now = GetTime()
	if S.spiritAt and now - S.spiritAt <= SPIRIT_FOR then
		return "s"
	elseif S.rezAt and now - S.rezAt <= REZ_FOR then
		return "p"
	end
	return "c"
end

-- Released (a ghost at the graveyard: a new segment), or back to life without releasing (a player's
-- resurrection, a soulstone).
E.On("PLAYER_ALIVE", function()
	if not S.down then
		return
	end
	if Yes(UnitIsGhost, "player") then
		C.NoteCause("r")
	else
		S.down = false
		Note("r", (S.rezAt and GetTime() - S.rezAt <= REZ_FOR) and "p" or "c")
	end
end)

-- A ghost alive again: at the spirit healer, by a player or at the corpse.
E.On("PLAYER_UNGHOST", function()
	S.down = false
	Note("r", How())
end)

W.r = function(how)
	E.Line("r", how)
	C.CheckMode()
end

---------------------------------------------------------------------------
-- Kills: yours, your pet's, your group's (PARTY_KILL), each corpse once
---------------------------------------------------------------------------

local function InGroup(guid)
	local IsIn = (C_PartyInfo and C_PartyInfo.IsGUIDInGroup) or IsGUIDInGroup
	return Yes(IsIn, guid)
end

E.On("PARTY_KILL", function(attackerGUID, targetGUID)
	if not (Readable(attackerGUID) and Readable(targetGUID)) then
		return -- (secret while the game restricts who's who: encounters, battlegrounds)
	end
	local who
	if attackerGUID == Value(UnitGUID, "player") then
		who = "m"
	elseif attackerGUID == Value(UnitGUID, "pet") then
		who = "p"
	elseif InGroup(attackerGUID) then
		who = "g"
	else
		return
	end
	local creature = LT.CreatureOf(targetGUID)
	if creature and Once(killed, killedOrder, targetGUID, "killedNext", KILLS_KEEP) then
		Note("k", creature, who, targetGUID)
	end
end)

W.k = function(creature, who, guid)
	local info = seenInfo[guid]
	if Value(UnitGUID, "target") == guid then
		info = Look("target") or info
	end
	if info then
		E.Name("c", creature, info.name)
	end
	E.Line("k", creature, info and info.level, info and info.cls, who)
end

---------------------------------------------------------------------------
-- Loot (green and better), gathering
---------------------------------------------------------------------------

-- A gathering spell's kind (h herb, o ore, s skin), by ID or, for a rank not listed, by name.
local gatherNames
local function GatherKind(spellID)
	if GATHERING[spellID] then
		return GATHERING[spellID]
	end
	local GetName = C_Spell and C_Spell.GetSpellName
	if not gatherNames then
		gatherNames = {}
		for id, kind in pairs(GATHERING) do
			local name = Value(GetName, id)
			if type(name) == "string" then
				gatherNames[name] = kind
			end
		end
	end
	local name = Value(GetName, spellID)
	return type(name) == "string" and gatherNames[name] or nil
end

E.On("UNIT_SPELLCAST_SUCCEEDED", function(_, _, spellID)
	if type(spellID) ~= "number" or issecret(spellID) then
		return
	elseif spellID == HEARTHSTONE then
		C.NoteCause("h")
	elseif TELEPORTS[spellID] then
		C.NoteCause("p", spellID)
	else
		local kind = GatherKind(spellID)
		if kind then
			S.gatherKind, S.gatherAt = kind, GetTime()
		end
	end
end, "player")

-- A game object's ID from its GUID ("GameObject-0-<server>-<instance>-<zone>-<ID>-<spawn>").
local function ObjectOf(guid)
	return type(guid) == "string" and not issecret(guid) and tonumber(guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")) or nil
end

local function ItemOf(link)
	return type(link) == "string" and not issecret(link) and tonumber(link:match("item:(%d+)")) or nil
end

-- The loot window: whose corpse each item is from (for the loot lines), and whether it's a node
-- you gathered (a gathering spell just before, or fishing): its kind, the node and the items.
-- Read now: with auto loot the window is gone by the next tick.
E.On("LOOT_READY", function()
	local now = GetTime()
	wipe(lootFrom)
	S.lootAt = now
	local kind = (Yes(IsFishingLoot) and "f") or (now - S.gatherAt <= GATHER_GAP and S.gatherKind) or nil
	local items, source
	for slot = 1, Value(GetNumLootItems) or 0 do
		local guid = Value(GetLootSourceInfo, slot)
		guid = type(guid) == "string" and guid or nil
		local id = ItemOf(Value(GetLootSlotLink, slot))
		if id and guid then
			lootFrom[id] = LT.CreatureOf(guid)
		end
		if kind then
			source = source or guid
			if id then
				local ok, _, _, count = pcall(GetLootSlotInfo, slot)
				count = ok and type(count) == "number" and not issecret(count) and count or 1
				items = (items and items .. " " or "") .. id .. ":" .. count
			end
		end
	end
	if not kind or now - S.gatheredAt < 1 or (source and not Once(nodes, nodesOrder, source, "nodesNext", NODES_KEEP)) then
		return -- (not a node, the same window again, a node gathered before)
	end
	S.gatherAt, S.gatheredAt = -math.huge, now
	local node = kind == "s" and LT.CreatureOf(source) or ObjectOf(source)
	Note("h", kind, node, items)
end)

W.h = function(kind, node, items)
	local n = 0
	for item in (items or ""):gmatch("%S+") do
		n = n + 1
		fields[n] = item
	end
	E.Line("h", kind, node, unpack(fields, 1, n))
	for i = 1, n do
		fields[i] = nil
	end
end

-- Your loot, green and better: looted (from the corpse the loot window said) or pushed (rewards,
-- purchases).
E.On("CHAT_MSG_LOOT", function(text)
	local link, id, count, quality, pushed = LT.OwnLoot(text)
	if not id or type(quality) ~= "number" or quality < 2 then
		return
	end
	local from = not pushed and GetTime() - S.lootAt <= LOOT_SOURCE_FOR and lootFrom[id] or nil
	Note("l", id, count, quality, pushed and "p" or "l", from, link)
end)

local function LinkName(link)
	return type(link) == "string" and link:match("|h%[(.-)%]|h") or nil
end
E.LinkName = LinkName

W.l = function(id, count, quality, how, from, link)
	E.Name("i", id, LinkName(link))
	E.Line("l", id, count, quality, how, from)
end

---------------------------------------------------------------------------
-- Collections, bosses, flights, battleground results
---------------------------------------------------------------------------

local function New(kind)
	return function(id)
		if Readable(id) then
			Note("n", kind, id)
		end
	end
end
E.On("NEW_MOUNT_ADDED", New("m"))
E.On("NEW_TOY_ADDED", New("t"))
E.On("NEW_RECIPE_LEARNED", New("r"))
E.On("ACHIEVEMENT_EARNED", function(id, alreadyEarned)
	if Readable(id) and alreadyEarned ~= true then
		Note("n", "a", id)
	end
end)
E.On("NEW_PET_ADDED", function(petGUID)
	if Readable(petGUID) then
		Note("pet", petGUID)
	end
end)

W.n = function(kind, id)
	E.Line("n", kind, id)
end

W.pet = function(petGUID) -- (its species)
	local species = C_PetJournal and Value(C_PetJournal.GetPetInfoByPetID, petGUID)
	if type(species) == "number" then
		E.Line("n", "p", species)
	end
end

E.On("ENCOUNTER_END", function(encounterID, _, _, _, success)
	if Readable(encounterID) and (success == 1 or success == true) then
		Note("B", encounterID)
	end
end)
E.On("BOSS_KILL", function(encounterID)
	if Readable(encounterID) then
		Note("B", encounterID)
	end
end)

W.B = function(id)
	if id == S.bossID and GetTime() - S.bossAt < BOSS_DEDUPE then
		return
	end
	S.bossID, S.bossAt = id, GetTime()
	E.Line("B", id)
end

-- A flight path picked on the flight map (a post-hook, like Flight.lua's): from and to taxi nodes.
if type(TakeTaxiNode) == "function" then
	hooksecurefunc("TakeTaxiNode", function(slot)
		if E.recording and ns.FlightTime then
			local ok, _, from, to = pcall(ns.FlightTime.Pick, slot)
			if ok and (from or to) then
				Note("F", from, to)
			end
		end
	end)
end

W.F = function(from, to)
	E.Line("F", from, to)
end

E.On("PVP_MATCH_COMPLETE", function(winner, duration)
	if Readable(winner) then
		Note("bres", winner, Readable(duration) and duration or nil)
	end
end)

W.bres = function(winner, duration)
	if C.BattlegroundResult then
		C.BattlegroundResult(winner, duration) -- Changes.lua
	end
end

---------------------------------------------------------------------------
-- The tick
---------------------------------------------------------------------------

E.OnTick(function(now)
	if not C.Ready() then
		return -- (the session's anchor first; what's noted waits)
	end
	TrackFoe(now)
	Quests(now)
	if S.deadAt and now - S.deadAt >= DEATH_REPEAT and not DeadOrGhost() then
		S.deadAt = nil -- (alive again: the next death counts)
	end
	C.Flush()
end)

Reset()
table.insert(C.resets, Reset)
