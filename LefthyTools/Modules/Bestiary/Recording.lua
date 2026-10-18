local _, ns = ...
local Bt = ns.Bestiary
local M = Bt.module
local Value, issecret = Bt.Value, Bt.issecret

-- Recording your kills and what they drop into LefthyToolsBestiaryDB (its format: Bestiary.lua).
--
-- Counting so the chances hold:
--   * a kill counts once its corpse is looted, or once the game says it's empty (CanLootUnit, a
--     moment after it died): a corpse left lying would count as a kill that dropped nothing. The
--     game can be wrong (in game: "empty" for a corpse with two items): looted after all, its items
--     join that kill;
--   * your (or your pet's) killing blow (PARTY_KILL), or any corpse you loot: it was yours; not a
--     mob someone else tagged first (its corpse isn't yours);
--   * on your own only: in a group the loot goes round, so you'd see only part of it;
--   * a corpse's loot once (the first time it opens); not right after skinning, a pickpocket or
--     gathering (NOT_A_KILL), nor what isn't a creature's (herbs, ore, chests, fishing, a bag's
--     contents: their source isn't a creature);
--   * coin: what your money grew by while the loot window was open.
-- Skinning is kept apart: what you skin from a kind of mob, each corpse once, per skinning (also in
-- a group: what you skin is yours). /bestiary log shows the last loot windows and kills and what was
-- made of them.
--
-- The pace: what a counted kill of yours gave in XP (PLAYER_XP_UPDATE in the moment around its
-- PARTY_KILL) and how long it took (since the fight began, or since your last kill in it: several
-- mobs in one fight share its length). XP per kill depends on your level, so it's kept for one level
-- (the level you were at the kill): a kill at another level starts it again.

local EMPTY_CHECKS = { 2, 6 }  -- seconds after a kill: is its corpse empty? (both times: then it counts)
local PENDING_FOR = 300         -- a corpse not looted in this long: not counted
local CAST_GAP = 1.5            -- skinning (a pickpocket, gathering) this shortly before the loot window: not a kill's loot
local LOG_KEEP = 12             -- loot windows remembered with what was made of them (/bestiary log)
local XP_FROM_KILL = 1.5        -- seconds: XP this close to a kill of yours came from it
local FIGHT_AFTER = 2           -- seconds a kill may come after the fight ended and still be timed
local RECENT_KEEP = 8           -- your last kills, for the XP that comes a moment after them
local SPOTS_KEEP = 50           -- where you killed each kind: the last this many kills
Bt.SPOTS_KEEP = SPOTS_KEEP
local TAP_UNITS = { "target", "mouseover" } -- whose tap a killing blow can be checked on
-- Spells whose loot isn't a kill's (each rank's ID, and by name for ranks not listed): Skinning,
-- Pick Pocket, Mining, Herb Gathering. Any other spell just before looting (a killing blow, then a
-- quick loot) doesn't matter.
local NOT_A_KILL = { 8613, 8617, 8618, 10768, 921, 2575, 2576, 3564, 10248, 2366, 2368, 3570, 11993 }
local SKINNING = { [8613] = true, [8617] = true, [8618] = true, [10768] = true }
Bt.SKINNING = SKINNING -- (Classic.lua: can you skin?)

local pending = {}               -- GUID -> { at, creature }: killed, its loot not seen yet
local done = {}                  -- GUID -> { at (time()), how }: counted (or its loot seen); kept a while
local castAt = -math.huge        -- when one of the NOT_A_KILL spells went off
local castSkin = false           -- and it was Skinning
local notKillIDs, notKillNames   -- NOT_A_KILL as a set, and their names (read once); Skinning's name
local skinName
local skinnedCorpse = {}         -- GUID -> time: skinned (once each)
local lootMoney, lootSource      -- while the loot window is open: money before, the corpse
local lootSeen = false           -- this loot window was looked at (LOOT_READY or LOOT_OPENED)
local recent = {}                -- your last kills (their pending entries), the oldest first
local xpWas = {}                 -- your XP as last read (xp, max): what each update added
local looseXP                    -- XP that came just before its kill: { amount, at }
local fightFrom, fightEnd        -- when the fight began (PLAYER_REGEN_DISABLED) and ended (nil: still on)
local lastKillAt = -math.huge    -- your last kill in this fight: the next one's time starts there

-- A kind of mob's record, made at its first kill.
local function MobFor(creature)
	local data = Bt.Data()
	local mob = data.mobs[creature]
	if not mob then
		mob = { kills = 0, money = 0, items = {} }
		data.mobs[creature] = mob
	end
	return mob
end

local function Solo()
	return not (IsInGroup and IsInGroup())
end

-- What was made of a loot window or a kill, the last LOG_KEEP (/bestiary log; kept for a look
-- after a /reload): { time, mob (creature ID), what, items (how many), check (CanLootUnit's
-- answers), the corpse's GUID (when it was counted: Counted) }.
local function Log(creature, what, items, check, guid)
	local data = Bt.Data()
	if not data then
		return
	end
	data.log = type(data.log) == "table" and data.log or {}
	table.insert(data.log, 1, { time(), creature, what, items, check, guid })
	for i = #data.log, LOG_KEEP + 1, -1 do
		data.log[i] = nil
	end
end

-- A corpse counted already (done: { at, how }), also before a /reload: that forgets the session's
-- corpses, but the log is saved, and a corpse looted, a /reload and looted again would count twice
-- (said empty, then looted after the /reload: a second kill instead of its items joining the first).
local COUNTED = { empty = "empty", looted = "looted", ["looted (said empty before)"] = "looted", ["looted before"] = "looted" }

local function Counted(guid)
	local data = Bt.Data()
	if done[guid] or not (data and type(data.log) == "table") then
		return done[guid]
	end
	local now = time()
	for _, entry in ipairs(data.log) do -- (the newest first)
		if entry[6] == guid and COUNTED[entry[3]] and now - (tonumber(entry[1]) or 0) <= PENDING_FOR then
			done[guid] = { at = entry[1], how = COUNTED[entry[3]] }
			return done[guid]
		end
	end
end

-- /bestiary log: the newest first, in chat (English, like the other chat lines).
function Bt.PrintLog()
	local data = Bt.Data()
	local log = data and type(data.log) == "table" and data.log or {}
	if #log == 0 then
		M:Print("nothing yet: no loot window or kill since the log began.")
		return
	end
	M:Print("the last loot windows and kills, newest first:")
	for _, entry in ipairs(log) do
		local mob = entry[2] and data.mobs[entry[2]]
		local who = mob and mob.name or entry[2] and ("creature " .. entry[2]) or "?"
		print(("  %s  %s: %s%s%s"):format(date("%H:%M:%S", entry[1]), who, entry[3],
			(entry[4] or 0) > 0 and (", " .. entry[4] .. " item(s)") or "", entry[5] and (" (loot check " .. entry[5] .. ")") or ""))
	end
end

-- What your XP grew by since it was last read (a level-up in between: the rest of the old level
-- and what's in the new one); nil when it can't be told. A level-up shows as the XP going down, not
-- as UnitLevel changing: the client may tell the new XP an update before the new level, and taking
-- the level then would count a whole level as one kill's XP.
local function ReadXP()
	local xp, max = Value(UnitXP, "player"), Value(UnitXPMax, "player")
	if type(xp) ~= "number" or type(max) ~= "number" then
		return nil
	end
	local gained = xpWas.xp and (xp >= xpWas.xp and xp - xpWas.xp or (xpWas.max - xpWas.xp) + xp)
	xpWas.xp, xpWas.max = xp, max
	return gained
end

-- Kills give you XP (the XP bar's own rule: not at the level cap, not switched off): a kill without
-- any then gave 0 (a grey mob), else it says nothing about XP.
local function XPGrows()
	return not (Value(IsPlayerAtEffectiveMaxLevel) or Value(IsXPUserDisabled))
end

-- A counted kill's XP and how long it took, for the level you were at when it died (another level
-- starts the pace again: XP per kill depends on it). XP still to come joins it then (kill.pace).
local function AddPace(mob, kill)
	if not (kill and kill.level) then
		return -- (a corpse looted without your killing blow seen: nothing known)
	end
	local pace = mob.pace
	if type(pace) ~= "table" or pace[1] ~= kill.level then
		pace = { kill.level, 0, 0, 0, 0 }
		mob.pace = pace
	end
	if kill.xp or XPGrows() then
		pace[2], pace[3] = pace[2] + 1, pace[3] + (kill.xp or 0)
		kill.pace = not kill.xp and pace or nil
	end
	if kill.seconds then
		pace[4], pace[5] = pace[4] + 1, pace[5] + math.floor(kill.seconds * 10 + 0.5) / 10
	end
end

-- Your XP grew: a kill's from the moment before (the oldest still without, when several died at
-- once), else it waits a moment for its kill (the XP can come first).
local function OnXP()
	local gained = ReadXP()
	if not gained or gained <= 0 then
		return
	end
	local now = GetTime()
	for _, kill in ipairs(recent) do
		if not kill.xp and now - kill.at <= XP_FROM_KILL then
			kill.xp = gained
			if kill.pace then -- (counted already, as 0: it's added now)
				kill.pace[3], kill.pace = kill.pace[3] + gained, nil
				Bt.Changed(kill.creature)
			end
			return
		end
	end
	looseXP = { amount = gained, at = now }
end

-- Where you are, packed in one number (map ID * 1e6 + x * 1e3 + y, x and y in thousandths of the
-- map: a yard or two); nil in an instance or when the game doesn't say.
local function Spot()
	if Value(IsInInstance) or not C_Map then
		return nil
	end
	local map = Value(C_Map.GetBestMapForUnit, "player")
	local pos = type(map) == "number" and Value(C_Map.GetPlayerMapPosition, map, "player")
	if type(pos) ~= "table" or type(pos.GetXY) ~= "function" then
		return nil
	end
	local ok, x, y = pcall(pos.GetXY, pos)
	if not ok or issecret(x) or issecret(y) or type(x) ~= "number" or type(y) ~= "number"
		or x < 0 or x > 1 or y < 0 or y > 1 or (x == 0 and y == 0) then
		return nil
	end
	return map * 1e6 + math.min(999, math.floor(x * 1e3)) * 1e3 + math.min(999, math.floor(y * 1e3))
end

-- A kill's spot joins its kind's, the last SPOTS_KEEP.
local function AddSpot(mob, spot)
	if not spot then
		return
	end
	mob.spots = type(mob.spots) == "table" and mob.spots or {}
	mob.spots[#mob.spots + 1] = spot
	while #mob.spots > SPOTS_KEEP do
		table.remove(mob.spots, 1)
	end
end

-- A kill counted (once per corpse). how: "looted" or "empty" (the game said there's nothing on it:
-- if it's looted after all, its items still join this kill).
local function Count(guid, creature, how)
	local kill = pending[guid]
	done[guid] = { at = time(), how = how }
	pending[guid] = nil
	local mob = MobFor(creature)
	mob.kills, mob.last = mob.kills + 1, time()
	mob.first = mob.first or mob.last
	local info = Bt.Seen(guid)
	if info then
		Bt.NoteSeen(mob, info)
	end
	AddPace(mob, kill)
	-- Where: you at its killing blow; a corpse looted without one seen, you at it now.
	if kill then
		AddSpot(mob, kill.spot)
	else
		AddSpot(mob, Spot())
	end
	return mob
end

-- A corpse not looted yet: empty? (CanLootUnit: hasLoot.) Twice, a few seconds apart: its loot can
-- take a moment to show.
local function CheckEmpty(guid, round)
	local kill = pending[guid]
	if not kill then
		return
	end
	local ok, hasLoot, canLoot = pcall(CanLootUnit, guid)
	kill.check = ("%s/%s"):format(tostring(ok and not issecret(hasLoot) and hasLoot), tostring(ok and not issecret(canLoot) and canLoot))
	if not ok or issecret(hasLoot) or hasLoot then
		return -- (has loot, or can't tell: counted when it's looted)
	end
	if round < #EMPTY_CHECKS then
		C_Timer.After(EMPTY_CHECKS[round + 1] - EMPTY_CHECKS[round], function() CheckEmpty(guid, round + 1) end)
	else
		Bt.WishKill(kill.creature, Count(guid, kill.creature, "empty"))
		Log(kill.creature, "empty", 0, kill.check, guid)
		Bt.Changed(kill.creature)
	end
end

local function OnKill(attacker, target)
	if issecret(attacker) or issecret(target) or not Solo() or done[target] or pending[target] then
		return
	end
	if attacker ~= Value(UnitGUID, "player") and attacker ~= Value(UnitGUID, "pet") then
		return
	end
	local creature = Bt.CreatureOf(target)
	if not creature then
		return
	end
	-- Someone else's mob (they hit it first, you finished it): its corpse isn't yours, and the game
	-- would say it's empty, a kill without drops. Told by your target or the mouseover.
	for _, unit in ipairs(TAP_UNITS) do
		if Value(UnitGUID, unit) == target and Value(UnitIsTapDenied, unit) == true then
			return Log(creature, "tapped by someone else", 0)
		end
	end
	if Value(UnitGUID, "target") == target then
		Bt.Look("target")
	end
	local now = GetTime()
	local kill = { at = now, creature = creature, level = Value(UnitLevel, "player"), spot = Spot() }
	-- How long it took: since the fight began, or since your last kill in it; not when the fight's
	-- start wasn't seen (switched on in it, a /reload).
	if fightFrom and (not fightEnd or now - fightEnd <= FIGHT_AFTER) then
		kill.seconds = now - math.max(fightFrom, lastKillAt)
	end
	lastKillAt = now
	if looseXP and now - looseXP.at <= XP_FROM_KILL then -- (its XP came first)
		kill.xp, looseXP = looseXP.amount, nil
	end
	pending[target] = kill
	recent[#recent + 1] = kill
	if #recent > RECENT_KEEP then
		table.remove(recent, 1)
	end
	if CanLootUnit then
		C_Timer.After(EMPTY_CHECKS[1], function() CheckEmpty(target, 1) end)
	end
end

-- The corpse a loot window is for: its GUID (GetLootSourceInfo; when that says nothing, your dead
-- target, else the one kill waiting from the last minute).
local function LootSource()
	local source
	for slot = 1, GetNumLootItems() do
		local guid = GetLootSourceInfo and Value(GetLootSourceInfo, slot)
		if guid then
			if source and source ~= guid then
				return nil -- (several corpses at once: not told apart)
			end
			source = guid
		end
	end
	if not source and Value(UnitIsDead, "target") then
		source = Bt.CreatureOf(Value(UnitGUID, "target")) and Value(UnitGUID, "target")
	end
	if not source then
		local now, only = GetTime(), nil
		for guid, kill in pairs(pending) do
			if now - kill.at < 60 then
				if only then
					return nil
				end
				only = guid
			end
		end
		source = only
	end
	return source
end

-- Is this spell one whose loot isn't a kill's (skinning, a pickpocket, gathering)? And is it Skinning?
local function NotAKill(spellID)
	local GetName = C_Spell and C_Spell.GetSpellName
	if not notKillIDs then
		notKillIDs, notKillNames = {}, {}
		for _, id in ipairs(NOT_A_KILL) do
			notKillIDs[id] = true
			local name = Value(GetName, id)
			if name then
				notKillNames[name] = true
			end
		end
		skinName = Value(GetName, 8613)
	end
	local name = not notKillIDs[spellID] and Value(GetName, spellID)
	if notKillIDs[spellID] or (name and notKillNames[name]) then
		return true, SKINNING[spellID] or (name ~= nil and name == skinName)
	end
	return false
end

-- Skinned: what came, per skinning of its kind (each corpse once; also in a group).
local function OnSkinned(guid, creature)
	if skinnedCorpse[guid] then
		return Log(creature, "skinned before", 0)
	end
	skinnedCorpse[guid] = time()
	local mob = MobFor(creature)
	mob.skinned = (mob.skinned or 0) + 1
	mob.skins = mob.skins or {}
	local items = 0
	for slot = 1, GetNumLootItems() do
		if Value(GetLootSlotType, slot) == 1 then
			local _, name, quantity, _, quality = GetLootSlotInfo(slot)
			local link = Value(GetLootSlotLink, slot)
			local id = type(link) == "string" and tonumber(link:match("|Hitem:(%d+)"))
			if id and not issecret(quantity) and not issecret(quality) then
				local skin = mob.skins[id] or { 0, 0, quality }
				mob.skins[id] = skin
				skin[1], skin[2], skin[3] = skin[1] + 1, skin[2] + math.max(1, tonumber(quantity) or 1), tonumber(quality) or skin[3]
				skin[4] = not issecret(name) and type(name) == "string" and name or skin[4]
				items = items + 1
			end
		end
	end
	Log(creature, "skinned", items)
	Bt.Changed(creature)
end

-- The loot window opened (LOOT_READY, before anything is taken; LOOT_OPENED if its slots weren't
-- there yet): a corpse's loot, the first time.
local function OnLoot()
	if lootSeen or not Bt.Data() then
		return
	end
	lootMoney, lootSource = nil, nil
	if GetNumLootItems() == 0 then
		return -- (not filled yet: LOOT_OPENED looks again)
	end
	lootSeen = true
	local guid = LootSource()
	local creature = Bt.CreatureOf(guid)
	local gathered = GetTime() - castAt < CAST_GAP
	if gathered and castSkin and creature then
		return OnSkinned(guid, creature)
	elseif IsFishingLoot and IsFishingLoot() then
		return
	elseif gathered then
		return Log(creature, "pickpocket or gathering", 0)
	elseif not Solo() then
		return Log(creature, "group", 0)
	elseif not creature then
		return Log(nil, guid and "not a mob" or "no corpse", 0)
	end
	local was, check = Counted(guid), pending[guid] and pending[guid].check
	if was and was.how ~= "empty" then
		return Log(creature, "looted before", 0, nil, guid)
	end
	local mob
	if was then -- (the game said it was empty: its items join that kill)
		mob = MobFor(creature)
		was.how = "looted"
	else
		mob = Count(guid, creature, "looted")
	end
	local coin, items, got = false, 0, {}
	for slot = 1, GetNumLootItems() do
		local kind = Value(GetLootSlotType, slot)
		if kind == 2 then -- (Enum.LootSlotType.Money)
			coin = true
		elseif kind == 1 then -- (Item)
			local _, name, quantity, _, quality = GetLootSlotInfo(slot)
			local link = Value(GetLootSlotLink, slot)
			local id = type(link) == "string" and tonumber(link:match("|Hitem:(%d+)"))
			if id and not issecret(quantity) and not issecret(quality) then
				local item = mob.items[id] or { 0, 0, quality }
				mob.items[id] = item
				item[1], item[2], item[3] = item[1] + 1, item[2] + math.max(1, tonumber(quantity) or 1), tonumber(quality) or item[3]
				item[4] = not issecret(name) and type(name) == "string" and name or item[4] -- (for the search)
				items, got[id] = items + 1, link
			end
		end
	end
	if coin then
		lootMoney, lootSource = GetMoney(), creature
	end
	local fulfilled = Bt.WishKill(creature, mob, got, was ~= nil)
	Log(creature, was and "looted (said empty before)" or "looted", items, check, guid)
	Bt.Changed(creature)
	if fulfilled and Bt.Redraw then
		Bt.Redraw() -- (its star goes everywhere)
	end
end

-- The loot window closed: its coin is what the money grew by.
local function OnLootClosed()
	if lootMoney and lootSource then
		local gained = GetMoney() - lootMoney
		local mob = Bt.Mob(lootSource)
		if mob and gained > 0 then
			mob.money = mob.money + gained
			Bt.Changed(lootSource)
		end
	end
	lootMoney, lootSource, lootSeen = nil, nil, false
end

-- Old waiting kills and counted corpses go.
local function Prune()
	local now, wall = GetTime(), time()
	for guid, kill in pairs(pending) do
		if now - kill.at > PENDING_FOR then
			pending[guid] = nil
		end
	end
	for guid, counted in pairs(done) do
		if wall - counted.at > PENDING_FOR then
			done[guid] = nil
		end
	end
	for guid, at in pairs(skinnedCorpse) do
		if wall - at > PENDING_FOR then
			skinnedCorpse[guid] = nil
		end
	end
end

Bt.On("PARTY_KILL", function(attacker, target)
	OnKill(attacker, target)
	Prune()
end)
Bt.On("LOOT_READY", OnLoot)
Bt.On("LOOT_OPENED", OnLoot)
Bt.On("LOOT_CLOSED", OnLootClosed)
Bt.On("UNIT_SPELLCAST_SUCCEEDED", function(_, _, spellID)
	local notKill, skin = false, false
	if not issecret(spellID) then
		notKill, skin = NotAKill(spellID)
	end
	if notKill then
		castAt, castSkin = GetTime(), skin
	end
end, "player")
Bt.On("PLAYER_XP_UPDATE", OnXP)
Bt.On("PLAYER_REGEN_DISABLED", function() -- (a fight began: the next kill's time starts here)
	fightFrom, fightEnd, lastKillAt = GetTime(), nil, -math.huge
end)
Bt.On("PLAYER_REGEN_ENABLED", function()
	fightEnd = GetTime()
end)

Bt.When("enable", function()
	xpWas.xp = nil
	ReadXP() -- (where counting XP starts)
end)

Bt.When("disable", function()
	wipe(pending)
	wipe(recent)
	-- (switched off with the loot window open: its LOOT_CLOSED won't come, and the next window would
	-- look already seen)
	lootMoney, lootSource, lootSeen, looseXP, fightFrom = nil, nil, false, nil, nil
end)


-- For tests: the kills waiting to be counted, and what a /reload forgets.
function Bt.Pending()
	return pending
end

function Bt.Forget()
	wipe(pending)
	wipe(done)
	wipe(skinnedCorpse)
	wipe(recent)
end
