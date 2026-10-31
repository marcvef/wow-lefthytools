local _, ns = ...
local LT = ns.LT
local E = ns.Echoes
local C = E.capture

-- What's compared with what was written before, a line when it changed (docs/echoes.md, Recording):
-- XP and rest (x), AFK (f), the group and the LefthyTools friends in it (g), gear (G), reputation
-- (R), professions (s), the hearthstone's place (H), honorable kills (p), dungeons (d) and
-- battlegrounds (b) entered and left, and the time played (/played, asked once per login: the
-- level-up line's). Baselines are kept per character in E.data.capture[<GUID>], so a /reload or the
-- next login writes only what changed.
--
-- Never lags the client: events only mark what to look at; the tick looks. What touches Blizzard's
-- frames or reads a lot (the silent /played: chat frames; gear, professions, reputation) waits until
-- you're out of combat.

local issecret, Value, Readable = LT.IsSecret, LT.Value, LT.Readable

local XP_EVERY = 60          -- seconds between XP checks (and on resting changes, level-ups, logins)
local FACTIONS_EVERY = 10    -- seconds: UPDATE_FACTION rescans at most this often
local PLAYED_WAIT = 10       -- seconds the chat frames go without /played's answer while it's asked silently
local RESULT_EVERY = 5       -- seconds between asking who won a battleground
local SLOTS = 19             -- equipment slots
-- The Classic professions' skill lines (C_SkillInfo): First Aid, Blacksmithing, Leatherworking,
-- Alchemy, Herbalism, Cooking, Mining, Tailoring, Engineering, Enchanting, Fishing, Skinning.
local PROFESSIONS = { 129, 164, 165, 171, 182, 185, 186, 197, 202, 333, 356, 393 }
local PARTY_UNITS, RAID_UNITS = {}, {}
for i = 1, 4 do
	PARTY_UNITS[i] = "party" .. i
end
for i = 1, 40 do
	RAID_UNITS[i] = "raid" .. i
end

local function Yes(f, ...)
	return Value(f, ...) == true
end

local S = {}
local gearDirty, repDirty = {}, {} -- slot -> true; faction ID -> true
local hidden = {}                  -- chat frames that don't get TIME_PLAYED_MSG while /played is asked
local friends, peersByGUID = {}, {} -- (one list and one map for every group check)

-- The chat frames get /played's answer again.
local function ShowPlayed()
	for i = #hidden, 1, -1 do
		pcall(hidden[i].RegisterEvent, hidden[i], "TIME_PLAYED_MSG")
		hidden[i] = nil
	end
end

local function Reset()
	ShowPlayed()
	wipe(gearDirty)
	wipe(repDirty)
	S.lastTick = nil
	S.xpAt = 0           -- (GetTime) the next XP check
	S.afk = nil          -- AFK as last written (nil: not known yet)
	S.afkDirty, S.groupDirty, S.bindDirty, S.skillsDirty, S.hkDirty = false, false, false, false, false
	S.gearAll = false
	S.factionsScan, S.factionsAt = false, -math.huge
	S.hk = nil           -- honorable kills as last read
	S.playedWanted, S.playedTotal, S.playedUntil = false, nil, nil
	S.resultAt = 0
end

---------------------------------------------------------------------------
-- XP, AFK
---------------------------------------------------------------------------

local function XP(cap)
	S.xpAt = GetTime() + XP_EVERY
	local level, xp, max = Value(UnitLevel, "player"), Value(UnitXP, "player"), Value(UnitXPMax, "player")
	if type(level) ~= "number" or type(xp) ~= "number" or type(max) ~= "number" then
		return
	end
	local rested = Value(GetXPExhaustion)
	rested = type(rested) == "number" and rested or 0
	local resting = Yes(IsResting)
	local key = level .. ":" .. xp .. ":" .. max .. ":" .. rested .. ":" .. (resting and 1 or 0)
	if key ~= cap.xp then
		cap.xp = key
		C.Spot()
		E.Line("x", level, xp, max, rested, resting)
	end
end

local function AFK()
	S.afkDirty = false
	local afk = Value(UnitIsAFK, "player")
	if afk == nil then
		return -- (secret in a chat lockdown: the last state stays)
	end
	afk = afk == true
	if afk ~= (S.afk or false) then
		C.Spot()
		E.Line("f", afk)
	end
	S.afk = afk
end

---------------------------------------------------------------------------
-- The group: its size, the LefthyTools friends in it (Beacon's friends, and the ones remembered
-- from it: E.data.friends), how many others
---------------------------------------------------------------------------

-- A character's key ("Anna-Realm"): first name and realm (the same realm's when the game says none).
local function Key(name, guid)
	local first = LT.Names.First(name)
	if not first then
		return nil
	end
	local ok, _, _, _, _, _, _, realm = pcall(GetPlayerInfoByGUID, guid)
	if not (ok and type(realm) == "string" and not issecret(realm) and realm ~= "") then
		realm = Value(GetRealmName)
	end
	return type(realm) == "string" and first .. "-" .. realm or first
end

local function Group(cap)
	S.groupDirty = false
	wipe(friends)
	wipe(peersByGUID)
	local beacon = LT:GetModule("beacon")
	if beacon and beacon.enabled and ns.Beacon and type(ns.Beacon.peers) == "table" then
		for _, peer in pairs(ns.Beacon.peers) do
			if type(peer.guid) == "string" and type(peer.name) == "string" then
				peersByGUID[peer.guid] = peer.name
			end
		end
	end
	local data = E.data
	if type(data.friends) ~= "table" then
		data.friends = {}
	end
	local remembered = data.friends
	local size = Value(GetNumGroupMembers)
	size = type(size) == "number" and size or 0
	local others = 0
	if size > 0 then
		local raid = Yes(IsInRaid)
		local me = Value(UnitGUID, "player")
		for i = 1, raid and math.min(size, 40) or math.min(size - 1, 4) do
			local unit = raid and RAID_UNITS[i] or PARTY_UNITS[i]
			local guid = Value(UnitGUID, unit)
			if guid ~= me or not guid then
				local key = guid and peersByGUID[guid] and Key(peersByGUID[guid], guid)
				if key then
					remembered[guid] = key -- (named while Beacon is off too)
				else
					key = guid and remembered[guid]
				end
				if key then
					friends[#friends + 1] = guid .. ":" .. key
				else
					others = others + 1 -- (a secret GUID too)
				end
			end
		end
		table.sort(friends)
	end
	local state = size .. ";" .. others .. ";" .. table.concat(friends, ";")
	if state ~= (cap.group or "0;0;") then
		cap.group = state
		C.Spot()
		E.Line("g", size, others, unpack(friends, 1, #friends))
	end
end

---------------------------------------------------------------------------
-- Gear: item, enchant, suffix per slot (only out of combat)
---------------------------------------------------------------------------

local function Gear(cap, slot)
	gearDirty[slot] = nil
	local link = Value(GetInventoryItemLink, "player", slot)
	local id, enchant, suffix
	local item = type(link) == "string" and link:match("item:([%-%d:]*)")
	if item then
		local i = 0
		for field in (item .. ":"):gmatch("([^:]*):") do
			i = i + 1
			if i == 1 then
				id = tonumber(field)
			elseif i == 2 then
				enchant = tonumber(field) or 0
			elseif i == 7 then
				suffix = tonumber(field) or 0
				break
			end
		end
	end
	local key = id and (id .. ":" .. (enchant or 0) .. ":" .. (suffix or 0)) or ""
	cap.gear = type(cap.gear) == "table" and cap.gear or {}
	local was = cap.gear[slot]
	cap.gear[slot] = key
	if key == was or (was == nil and key == "") then
		return
	end
	C.Spot()
	if id then
		E.Name("i", id, E.LinkName(link))
		E.Line("G", slot, id, enchant or 0, suffix or 0)
	else
		E.Line("G", slot, 0) -- (taken off)
	end
end

---------------------------------------------------------------------------
-- Reputation (standing 1-8; only out of combat): the faction FACTION_STANDING_CHANGED names, a scan
-- of every faction listed after login and on UPDATE_FACTION (at most every FACTIONS_EVERY seconds).
-- The first scan of a character is the baseline: no lines.
---------------------------------------------------------------------------

local function Faction(cap, id, data, quiet)
	data = data or (C_Reputation and Value(C_Reputation.GetFactionDataByID, id))
	local reaction = type(data) == "table" and data.reaction
	if type(reaction) ~= "number" or issecret(reaction) then
		return
	end
	cap.reps = type(cap.reps) == "table" and cap.reps or {}
	if cap.reps[id] ~= reaction then
		cap.reps[id] = reaction
		if not quiet then
			C.Spot()
			E.Line("R", id, reaction)
		end
	end
end

local function Factions(cap)
	S.factionsScan, S.factionsAt = false, GetTime()
	local count = C_Reputation and Value(C_Reputation.GetNumFactions)
	if type(count) ~= "number" then
		return
	end
	local quiet, read = not cap.repsKnown, false
	for i = 1, math.min(count, 300) do
		local data = Value(C_Reputation.GetFactionDataByIndex, i)
		local id = type(data) == "table" and data.factionID
		if type(id) == "number" and not issecret(id) and not data.isHeader then
			Faction(cap, id, data, quiet)
			read = true
		end
	end
	cap.repsKnown = cap.repsKnown or read or nil -- (the baseline: once a faction was read)
end

---------------------------------------------------------------------------
-- Professions (rank and maximum; only out of combat), the hearthstone's place, honorable kills
---------------------------------------------------------------------------

local function Professions(cap)
	S.skillsDirty = false
	local GetInfo = C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID
	if not GetInfo then
		return
	end
	cap.skills = type(cap.skills) == "table" and cap.skills or {}
	for _, id in ipairs(PROFESSIONS) do
		local info = Value(GetInfo, id)
		local rank = type(info) == "table" and info.rank
		local max = type(info) == "table" and info.maxRank
		if type(rank) == "number" and not issecret(rank) and type(max) == "number" and not issecret(max) and rank > 0 then
			local key = rank .. ":" .. max
			if cap.skills[id] ~= key then
				cap.skills[id] = key
				C.Spot()
				E.Line("s", id, rank, max)
			end
		elseif info ~= nil and cap.skills[id] then -- (unlearned)
			cap.skills[id] = nil
			C.Spot()
			E.Line("s", id, 0, 0)
		end
	end
end

local function Bind(cap)
	S.bindDirty = false
	local place = Value(GetBindLocation)
	if type(place) == "string" and place ~= "" and place ~= cap.bind then
		cap.bind = place
		C.Spot()
		E.Line("H", place)
	end
end

local function Honor()
	S.hkDirty = false
	local kills = Value(GetPVPSessionStats)
	if type(kills) ~= "number" then
		return
	end
	if S.hk and kills > S.hk then
		C.Spot()
		E.Line("p", kills - S.hk)
	end
	S.hk = kills
end

---------------------------------------------------------------------------
-- Dungeons and battlegrounds: entered and left (seen at each loading screen's end, kept across a
-- /reload in E.data.capture), a battleground's result
---------------------------------------------------------------------------

local function Instances(cap)
	local ok, inInstance, kind = pcall(IsInInstance)
	inInstance = ok and inInstance == true
	kind = inInstance and Readable(kind) and kind or nil
	local _, id = C.Instance()
	local got, _, _, difficulty = pcall(GetInstanceInfo)
	difficulty = got and type(difficulty) == "number" and not issecret(difficulty) and difficulty or nil
	local now = E.Now()
	local dungeon = type(cap.dungeon) == "table" and cap.dungeon or nil
	if id and (kind == "party" or kind == "raid") then
		if not dungeon or dungeon[1] ~= id then
			if dungeon then
				E.Line("d", "x", dungeon[1], dungeon[2])
			end
			cap.dungeon = { id, difficulty }
			E.Line("d", "e", id, difficulty)
		end
	elseif dungeon then
		cap.dungeon = nil
		E.Line("d", "x", dungeon[1], dungeon[2])
	end
	local bg = type(cap.bg) == "table" and cap.bg or nil
	if id and kind == "pvp" then
		if not bg or bg[1] ~= id then
			if bg then
				E.Line("b", bg[1], "x", now - (bg[2] or now))
			end
			cap.bg = { id, now }
			E.Line("b", id, "e")
		end
	elseif bg then
		cap.bg = nil
		E.Line("b", bg[1], "x", now - (bg[2] or now))
	end
end

-- Who won (PVP_MATCH_COMPLETE, or GetBattlefieldWinner): 0 the Horde, 1 the Alliance. Once.
function C.BattlegroundResult(winner, duration)
	local cap = C.Cap()
	local bg = cap and type(cap.bg) == "table" and cap.bg
	if not bg or bg[3] or (winner ~= 0 and winner ~= 1) then
		return
	end
	local faction = Value(UnitFactionGroup, "player")
	local mine = faction == "Alliance" and 1 or faction == "Horde" and 0 or nil
	if mine == nil then
		return
	end
	bg[3] = true
	C.Spot()
	E.Line("b", bg[1], winner == mine and "w" or "l", type(duration) == "number" and duration or (E.Now() - (bg[2] or E.Now())))
end

---------------------------------------------------------------------------
-- The time played: /played asked once per login, silently (the chat frames don't get the answer
-- for at most PLAYED_WAIT seconds; out of combat). Until it answers, and between answers, the time
-- recorded adds up (cap.played).
---------------------------------------------------------------------------

local function AskPlayed(now)
	S.playedWanted = false
	if type(RequestTimePlayed) ~= "function" then
		return
	end
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		local frame = _G["ChatFrame" .. i]
		if type(frame) == "table" and frame.IsEventRegistered and Yes(frame.IsEventRegistered, frame, "TIME_PLAYED_MSG") then
			frame:UnregisterEvent("TIME_PLAYED_MSG")
			hidden[#hidden + 1] = frame
		end
	end
	S.playedUntil = now + PLAYED_WAIT
	pcall(RequestTimePlayed)
end

E.On("TIME_PLAYED_MSG", function(total)
	if type(total) == "number" and not issecret(total) then
		S.playedTotal = total -- (asked by us, or typed)
	end
end)

E.On("PLAYER_ENTERING_WORLD", function(isInitialLogin)
	if isInitialLogin == true then
		S.playedWanted = true -- (a real login: not a /reload or a loading screen)
	end
end)

---------------------------------------------------------------------------
-- Events mark, the tick looks
---------------------------------------------------------------------------

E.On("PLAYER_FLAGS_CHANGED", function() S.afkDirty = true end, "player")
E.On("PLAYER_UPDATE_RESTING", function() S.xpAt = 0 end)
E.On("PLAYER_LEVEL_UP", function() S.xpAt = 0 end)
E.On("GROUP_ROSTER_UPDATE", function() S.groupDirty = true end)
E.On("PLAYER_EQUIPMENT_CHANGED", function(slot)
	if type(slot) == "number" and not issecret(slot) and slot >= 1 and slot <= SLOTS then
		gearDirty[slot] = true
	end
end)
E.On("FACTION_STANDING_CHANGED", function(factionID)
	if type(factionID) == "number" and not issecret(factionID) then
		repDirty[factionID] = true
	end
end)
E.On("UPDATE_FACTION", function() S.factionsScan = true end)
E.On("SKILL_LINES_CHANGED", function() S.skillsDirty = true end)
E.On("HEARTHSTONE_BOUND", function() S.bindDirty = true end)
E.On("PLAYER_PVP_KILLS_CHANGED", function() S.hkDirty = true end, "player")

-- A session's start (login, /reload, switched on): everything is looked at once.
local function SessionStart()
	S.xpAt, S.afkDirty, S.groupDirty, S.bindDirty, S.skillsDirty = 0, true, true, true, true
	S.gearAll, S.factionsScan, S.factionsAt = true, true, -math.huge
	S.hk = Value(GetPVPSessionStats) -- (the baseline: kills from before aren't written)
end

E.OnTick(function(now)
	local cap = C.Cap()
	if cap then -- the time played adds up while recording
		local elapsed = S.lastTick and now - S.lastTick or 0
		if elapsed > 0 then
			cap.played = (type(cap.played) == "number" and cap.played or 0) + elapsed
		end
		if S.playedTotal then
			cap.played, S.playedTotal = S.playedTotal, nil
			S.playedUntil = S.playedUntil and now
		end
	end
	S.lastTick = now
	if not (cap and C.Ready()) then
		return
	end
	if C.arrived then
		local start = C.arrived ~= "load"
		C.arrived = nil
		C.Spot()
		Instances(cap)
		if start then
			SessionStart()
		end
	end
	if now >= S.xpAt then
		XP(cap)
	end
	if S.afkDirty then
		AFK()
	end
	if S.groupDirty then
		Group(cap)
	end
	if S.bindDirty then
		Bind(cap)
	end
	if S.hkDirty then
		Honor()
	end
	local bg = type(cap.bg) == "table" and cap.bg
	if bg and not bg[3] and now >= S.resultAt then
		S.resultAt = now + RESULT_EVERY
		local winner = Value(GetBattlefieldWinner)
		if winner == 0 or winner == 1 then
			C.BattlegroundResult(winner)
		end
	end
	if LT.InCombat() then
		return -- (what follows waits for the fight's end)
	end
	if S.playedUntil and now >= S.playedUntil then
		S.playedUntil = nil
		ShowPlayed()
	end
	if S.playedWanted then
		AskPlayed(now)
	end
	if S.gearAll then
		S.gearAll = false
		for slot = 1, SLOTS do
			Gear(cap, slot)
		end
	else
		for slot in pairs(gearDirty) do
			Gear(cap, slot)
		end
	end
	if S.skillsDirty then
		Professions(cap)
	end
	if S.factionsScan and now - S.factionsAt >= FACTIONS_EVERY then
		Factions(cap)
	end
	if next(repDirty) then
		for id in pairs(repDirty) do
			repDirty[id] = nil
			Faction(cap, id, nil, not cap.repsKnown)
		end
	end
end)

E.When("stop", ShowPlayed)

Reset()
table.insert(C.resets, Reset)
