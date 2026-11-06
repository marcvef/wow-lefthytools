local _, ns = ...
local B = ns.Beacon
local S = B.Stream

-- Health, estimated, for the fight stream: yours (UnitHealth is always secret: what you lack is
-- added up from hits and heals and set right at checkpoints; while Beacon is on, a few events) and
-- the mobs' (their maximum is secret too: what one lost is added up per GUID, against what its kind
-- has; while the sensor runs, StreamSense.lua). Your window shows yours as "~80%", friends get it
-- (O2;v, and in frames: StreamNet.lua), the battle row plays the mobs' losses (StreamBattle.lua).
--   S.Health(), S.HealthWhy(), S.HealthMax()     yours (S.LifeStart / S.LifeStop: Beacon on, off)
--   S.MobHealth(mob, now), S.MobMaxOf(...)       a mob's at a look; what its kind has
--   S.SenseMobHealth(on), S.ForgetMobHealth(now) with the sensor: start or stop; forget what's stale
--   S.AmountsHidden()                            the client hides what a hit took (below)

local Value, issecret = S.Value, S.issecret

---------------------------------------------------------------------------
-- Hits without amounts
---------------------------------------------------------------------------

-- Since build 1.60.1.70755 UNIT_COMBAT's amount is secret (seen in game, 70790); that a unit was hit,
-- and how, isn't. So each hit counts as what one usually takes: its weight (a crit about two) times
-- the average, per character in LefthyToolsDB.streamHitSize[GUID] = { dealt = { size, fights },
-- taken = ..., heal = ... }. The damage meter's totals give the averages: C_DamageMeter's current
-- session is secret in combat, exact once out of it (seen in game, with Blizzard's meter switched
-- off), and holds the last fight only. A little after each fight they're divided by the hits counted,
-- my health is set right, and a mob killed alone tells its kind's health. An amount that can be read
-- is simply used. A wrong guess never kills: an estimate stays at SURVIVES while its owner lives.
local HIDDEN_SINCE = 70755
local HIT_WEIGHT = { CRITICAL = 2, CRUSHING = 1.5, GLANCING = 0.7 }
local HIT_GUESS = { taken = 0.06, heal = 0.25 } -- what a hit takes (a share of my maximum), until learned
local HITS_TO_KILL = 6      -- my hits on a mob, until what they take is learned
local HIT_FIGHTS = 5        -- fights behind an average
local SURVIVES = 0.05
local METER_WAIT = 1        -- seconds after a fight: then its totals
local METER_AGAIN = 2       -- and once more if they don't answer yet
local METER_CURRENT = 1     -- Enum.DamageMeterSessionType.Current
local METER_DONE, METER_HEALING, METER_TAKEN = 0, 2, 7 -- Enum.DamageMeterType

local fight -- this fight (from what the game calls combat): { at, missing, dealt, taken, heal, mobs, count, died, dead }

-- This client hides the amounts: a friend's hits have no number to show either.
function S.AmountsHidden()
	return (tonumber((select(2, GetBuildInfo()))) or 0) >= HIDDEN_SINCE
end

-- What a hit counts as, in usual hits; 0: nothing got through (its flag says so).
local function HitWeight(kind, flags)
	if issecret(flags) then
		return 1
	elseif kind == "WOUND" and S.AVOIDED[flags] then
		return 0
	end
	return HIT_WEIGHT[flags] or 1
end

local function HitSizes()
	local key = Value("UnitGUID", "player")
	if not key then
		return {}
	end
	local saved = S.Saved("streamHitSize")
	if type(saved[key]) ~= "table" then
		saved[key] = {}
	end
	return saved[key]
end

-- What one of my hits usually takes ("dealt"), or a hit or heal on me ("taken", "heal"); nil: not learned.
local function HitSize(field)
	local entry = HitSizes()[field]
	return type(entry) == "table" and tonumber(entry[1]) or nil
end

local function LearnHitSize(field, sample)
	local sizes = HitSizes()
	local entry = type(sizes[field]) == "table" and sizes[field] or {}
	local size, fights = tonumber(entry[1]), tonumber(entry[2]) or 0
	if size then
		local n = math.min(fights, HIT_FIGHTS - 1)
		sample = (size * n + sample) / (n + 1)
	end
	sizes[field] = { math.floor(sample * 10 + 0.5) / 10, fights + 1 }
end

local function CountDealt(key, weight)
	if fight then
		fight.dealt = fight.dealt + weight
		if not fight.mobs[key] then
			fight.mobs[key] = true
			fight.count = fight.count + 1
		end
	end
end

---------------------------------------------------------------------------
-- Your health, estimated
---------------------------------------------------------------------------

-- The game hides your health from addons (UnitHealth is always secret), but not what changes it:
-- UNIT_COMBAT tells every hit and heal on you with its amount, and your maximum health answers
-- (UnitHealthMax: hidden only where the game restricts it; then the last one known stays). So what
-- you lack is added up from hits and heals, between nothing and your maximum, and checkpoints set
-- it right again: out of combat your health comes back in ticks (UNIT_HEALTH without a hit or heal
-- at the same moment), and when they stop for FULL_AFTER seconds you're full; dead is empty; a
-- level-up fills you up. Unknown after a /reload until the first checkpoint. What a tick gives is
-- learned (what you lacked when they began, over how many it took). Not seen: health lost or won in
-- combat without a hit or heal (drains, some regeneration), until the next checkpoint. Runs while
-- Beacon is on (a few events, a sum each), so it's known when someone starts watching.

local FULL_AFTER = 4       -- seconds out of combat without a tick: full
local LONGEST_REGEN = 180  -- out of combat this long: full, whatever the ticks say
local TICK_GUESS = 0.03    -- what a tick gives (a share of your maximum), until learned
local LIFE_CHECK = 0.25

-- missing (nil: unknown), max, share (what a tick gives, learned), from (missing when the ticks
-- began), ticks, taken (what the last tick took: given back if a hit or heal came at that moment),
-- tickAt, hitAt (the last tick, hit or heal), calmAt (out of combat or alive since)
local life = { ticks = 0, tickAt = -1, hitAt = -1, calmAt = 0 }
local lifeWatch = CreateFrame("Frame")
lifeWatch:Hide()

local function Dead()
	return Value("UnitIsDeadOrGhost", "player") == true
end

local function Fighting()
	return Value("UnitAffectingCombat", "player") == true
end

-- Your maximum health (hidden where the game restricts it, as perhaps in dungeons: then the last
-- one known, also from before a /reload: kept per character and level in streamHealthMax).
local function ReadMax()
	local max, level = Value("UnitHealthMax", "player"), Value("UnitLevel", "player")
	local key = Value("UnitGUID", "player")
	local saved = key and S.Saved("streamHealthMax")
	if type(max) == "number" and max > 0 then
		life.max = max
		if life.missing then
			life.missing = math.min(life.missing, max)
		end
		local kept = saved and saved[key]
		if saved and not (type(kept) == "table" and kept[1] == max and kept[2] == level) then
			saved[key] = { max, level }
		end
	elseif not life.max and saved and type(saved[key]) == "table" and saved[key][2] == level then
		life.max = tonumber(saved[key][1])
	end
end

-- Full again: what the ticks gave is learned (from two or more).
local function Full()
	if life.from and life.from > 0 and life.ticks >= 2 and life.max then
		local share = life.from / life.ticks / life.max
		life.share = life.share and (life.share + share) / 2 or share
	end
	life.missing, life.from, life.ticks, life.taken, life.guessed = 0, nil, 0, nil, nil
end

-- Out of combat and alive: wait for the ticks to stop.
local function Calm()
	if not Dead() and not Fighting() then
		lifeWatch:Show()
	end
end

lifeWatch:SetScript("OnUpdate", function(self, elapsed)
	self.since = (self.since or 0) + elapsed
	if self.since < LIFE_CHECK then
		return
	end
	self.since = 0
	if Dead() or Fighting() then
		self:Hide() -- (on again when the fight ends, or alive again)
		return
	end
	local now = GetTime()
	if now - math.max(life.tickAt, life.hitAt, life.calmAt) >= FULL_AFTER or now - life.calmAt >= LONGEST_REGEN then
		Full()
		self:Hide()
	end
end)

lifeWatch:SetScript("OnEvent", function(_, event, _, kind, flags, amount)
	local now = GetTime()
	if event == "UNIT_COMBAT" then -- unit, event, flagText, amount, schoolMask
		if S.SenseRunning() then
			S.Happened(kind, flags, amount) -- (StreamSense.lua: a moment, for whoever watches)
		end
		if issecret(kind) or (kind ~= "WOUND" and kind ~= "HEAL") then
			return
		end
		local hidden = issecret(amount)
		local weight = hidden and HitWeight(kind, flags)
		if hidden and weight == 0 or not hidden and (type(amount) ~= "number" or amount <= 0) then
			return
		end
		life.hitAt = now
		if life.taken and life.tickAt == now then -- (that change was this, not a tick)
			life.missing, life.ticks, life.taken = life.missing and life.missing + life.taken, life.ticks - 1, nil
		end
		local field = kind == "WOUND" and "taken" or "heal"
		if hidden and fight then
			fight[field] = fight[field] + weight
		end
		if life.missing and life.max then
			local size = hidden and weight * (HitSize(field) or HIT_GUESS[field] * life.max) or amount
			life.guessed = life.guessed or hidden
			if kind == "WOUND" then
				life.missing = math.min(life.max, life.missing + size)
			else
				life.missing = math.max(0, life.missing - size) -- (more than you lack: overhealed)
			end
		end
		Calm()
	elseif event == "UNIT_HEALTH" then
		if life.hitAt == now or Fighting() then
			return -- (a hit or heal, counted; or a change in combat: why isn't known)
		end
		life.tickAt, life.taken = now, nil
		if life.missing and life.missing > 0 and life.max then
			life.from = life.from or life.missing
			life.ticks = life.ticks + 1
			life.taken = math.min(life.missing, (life.share or TICK_GUESS) * life.max)
			life.missing = life.missing - life.taken
		end
		Calm()
	elseif event == "UNIT_MAXHEALTH" or event == "PLAYER_ENTERING_WORLD" then
		ReadMax()
	elseif event == "PLAYER_REGEN_DISABLED" then
		lifeWatch:Hide()
		fight = { at = now, missing = life.missing, dealt = 0, taken = 0, heal = 0, mobs = {}, count = 0 }
	elseif event == "PLAYER_REGEN_ENABLED" then
		life.calmAt = now
		Calm()
		S.FightOver(now)
	elseif event == "PLAYER_DEAD" then
		life.missing, life.from, life.ticks, life.taken = life.max, nil, 0, nil
		lifeWatch:Hide()
		if fight then
			fight.dead = true
		end
	elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
		if not Dead() then -- (PLAYER_ALIVE also comes on releasing: then a ghost)
			-- About what being brought back gives; the ticks tell the rest.
			life.missing, life.from, life.ticks, life.taken, life.calmAt = life.max and life.max / 2, nil, 0, nil, now
			Calm()
		end
	elseif event == "PLAYER_LEVEL_UP" then
		life.missing, life.from, life.ticks, life.taken = life.max and 0, nil, 0, nil
	end
end)

local LIFE_UNIT_EVENTS = { "UNIT_COMBAT", "UNIT_HEALTH", "UNIT_MAXHEALTH" }
local LIFE_EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
	"PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD" }

-- My hits on my target, while the sensor doesn't run (it counts them, and those on nameplates): so
-- what they take is known when someone starts watching.
local targetWatch = CreateFrame("Frame")
targetWatch:SetScript("OnEvent", function(_, _, _, kind, flags, amount)
	if issecret(kind) or kind ~= "WOUND" or not issecret(amount) or S.SenseRunning() then
		return
	end
	local weight, key = HitWeight(kind, flags), Value("UnitGUID", "target")
	if weight > 0 and key then
		CountDealt(key, weight)
	end
end)

-- Your health now, 0 to 1 (estimated); nil while it isn't known.
function S.Health()
	if Dead() then
		return 0
	elseif not (life.missing and life.max) then
		return nil
	end
	return math.max(life.guessed and SURVIVES or 0, math.min(1, 1 - life.missing / life.max))
end

-- Why your health isn't known: "max" (your maximum is hidden here, none known from before) or
-- "wait" (no checkpoint yet).
function S.HealthWhy()
	return life.max and "wait" or "max"
end

-- Your maximum health (nil: not known): what makes a hit or heal a big one (StreamSense.lua).
function S.HealthMax()
	return life.max
end

-- Beacon on: the estimate starts (unknown until the first checkpoint). Off: it stops.
function S.LifeStart()
	lifeWatch:UnregisterAllEvents()
	for _, event in ipairs(LIFE_UNIT_EVENTS) do
		lifeWatch:RegisterUnitEvent(event, "player")
	end
	for _, event in ipairs(LIFE_EVENTS) do
		lifeWatch:RegisterEvent(event)
	end
	targetWatch:RegisterUnitEvent("UNIT_COMBAT", "target")
	fight = nil
	life.missing, life.max, life.from, life.ticks, life.taken, life.calmAt, life.guessed = nil, nil, nil, 0, nil, GetTime(), nil
	ReadMax()
	Calm()
end

function S.LifeStop()
	lifeWatch:UnregisterAllEvents()
	targetWatch:UnregisterAllEvents()
	lifeWatch:Hide()
	fight = nil
	life.missing, life.from, life.ticks, life.taken, life.guessed = nil, nil, 0, nil, nil
end

---------------------------------------------------------------------------
-- Mobs' health, estimated (your own window's battle row shows the real one: StreamBattle.lua)
---------------------------------------------------------------------------

-- A mob's health is hidden, its maximum too (UnitHealthMax of a mob: secret, seen in game), but
-- UNIT_COMBAT tells every hit and heal on your target and on nameplates with its amount (anyone's
-- hits). So what a mob lost is added up per GUID while the sensor runs (a hit reported for its
-- nameplate and for your target counts once), and set back to nothing whenever it's seen out of
-- combat (full; also after it evades). Its maximum: what a normal mob of its level usually has
-- (EXPECTED_HEALTH) times its kind's own ratio to that, learned: a mob seen out of combat before
-- its fight and seen dying lost all of it. One ratio per creature ID serves every level of it.
-- Kept for good in LefthyToolsDB.streamMobHealth[<creature ID>] = { ratio, kills } (the average of
-- the last MOB_SAMPLES), each player's own (friends get the percent, not the numbers). Beside it the
-- classic database's health (the Bestiary's LefthyTools_DropData, Bt.Health; not while the Bestiary
-- or its database is switched off): a ratio learned from LEARNED_FIRST kills or more comes first (it's
-- measured on Forever, the database is classic), then the database, then a ratio from one kill. Known
-- by none: a normal mob is taken as usual (ratio 1); an elite or rare isn't known. Hits while a mob
-- has neither a nameplate nor is your target aren't seen; a killing blow counts in full.
local MOB_SAMPLES = 5
local LEARNED_FIRST = 2     -- kills behind a learned ratio: then it counts before the classic database
local MOB_KEEP = 300        -- mobs not seen for this long are forgotten
-- A normal mob's health by level (ExpectedStat.db2 CreatureHealth, classic content, levels 1-63).
-- Checked in game: one kind had 620 at level 20 against 629 here, another 874 at 22 against 731.
local EXPECTED_HEALTH = { 42, 55, 71, 86, 102, 120, 137, 156, 180, 208, 239, 272, 307, 345, 385, 427, 473, 521, 572,
	629, 677, 731, 787, 846, 909, 975, 1040, 1109, 1177, 1242, 1308, 1374, 1443, 1512, 1586, 1660, 1737, 1814, 1897,
	1981, 2061, 2146, 2231, 2317, 2402, 2495, 2587, 2681, 2779, 2909, 3040, 3174, 3317, 3458, 3602, 3755, 3909, 4105,
	4234, 4365, 4496, 4629, 4763 }
local USUAL = { normal = true, trivial = true, minus = true } -- (taken as usual until learned)
local mobLost = {}          -- GUID -> health lost since it was last full
local mobHits = {}          -- GUID -> hits on it since then, in usual hits, when amounts are hidden
local mobFresh = {}         -- GUID -> true: seen out of combat, so its fight is seen from the start
local mobKind = {}          -- GUID -> { creature, level, class }
local mobSeen = {}          -- GUID -> when last looked at
local hitAt, hitAmount = {}, {} -- GUID -> the last hit (the same one comes for nameplate and target)
local mobCombat = CreateFrame("Frame")

-- A hit whose amount is hidden. The same one comes for its nameplate and for my target, so one per
-- frame for each mob and kind of hit (two real ones in a frame count once).
local function HiddenMobHit(key, kind, flags, now)
	local weight = HitWeight(kind, flags)
	if weight == 0 then
		return
	end
	local mark = issecret(flags) and kind or kind .. tostring(flags)
	if hitAt[key] == now and hitAmount[key] == mark then
		return
	end
	hitAt[key], hitAmount[key] = now, mark
	if kind == "WOUND" then
		mobHits[key] = (mobHits[key] or 0) + weight
		CountDealt(key, weight)
	else
		mobHits[key] = math.max(0, (mobHits[key] or 0) - weight)
	end
end

mobCombat:SetScript("OnEvent", function(_, _, unit, kind, flags, amount)
	if type(unit) ~= "string" or issecret(unit) or (unit ~= "target" and unit:sub(1, 9) ~= "nameplate")
		or issecret(kind) or (kind ~= "WOUND" and kind ~= "HEAL") then
		return
	end
	local hidden = issecret(amount)
	if not hidden and (type(amount) ~= "number" or amount <= 0) then
		return
	end
	local key = Value("UnitGUID", unit)
	if not key then
		return
	end
	if hidden then
		HiddenMobHit(key, kind, flags, GetTime())
		return
	end
	local now, signed = GetTime(), kind == "WOUND" and amount or -amount
	if hitAt[key] == now and hitAmount[key] == signed then
		return -- (the same hit, reported for its other unit)
	end
	hitAt[key], hitAmount[key] = now, signed
	mobLost[key] = math.max(0, (mobLost[key] or 0) + signed)
end)

-- What the classic database says a kind has at a level (nil: not known, or the Bestiary or its
-- database switched off; ns.Bestiary may not be there at all). A level outside the database's range:
-- the nearest end's, scaled like a usual mob's; a level not known (a boss's "??"): its highest.
local function ClassicMax(creature, level, expected)
	local Bt = ns.Bestiary
	if not (creature and Bt and Bt.Health) then
		return nil
	end
	local health, at = Bt.Health(creature, level)
	if health and expected and at ~= level then
		local there = EXPECTED_HEALTH[at]
		health = there and health / there * expected or nil
	end
	return health
end

-- A kind's maximum at a level (nil: not known), and where it comes from ("learned", "database",
-- "usual"): its ratio learned from LEARNED_FIRST kills or more, else the classic database, else a
-- ratio from fewer kills, else 1 for a normal mob.
local function MobMax(kind)
	if not kind then
		return nil
	end
	local expected = type(kind[2]) == "number" and EXPECTED_HEALTH[kind[2]]
	local learned = expected and kind[1] and S.Saved("streamMobHealth")[kind[1]]
	local ratio = type(learned) == "table" and tonumber(learned[1]) or nil
	if ratio and (tonumber(learned[2]) or 0) >= LEARNED_FIRST then
		return ratio * expected, "learned"
	end
	local classic = ClassicMax(kind[1], kind[2], expected)
	if classic then
		return classic, "database"
	elseif ratio then
		return ratio * expected, "learned"
	elseif expected and USUAL[kind[3]] then
		return expected, "usual"
	end
	return nil
end

-- What a kind of mob has at a level (the battle row's damage: a loss times this; nil: not known),
-- and where that comes from ("learned", "database", "usual").
function S.MobMaxOf(creature, level, class)
	return MobMax({ creature, level, class or "normal" })
end

-- If a mob's whole fight was seen, its kind's ratio learns from what it lost.
local function LearnKind(key, lost)
	local kind = mobKind[key]
	local expected = kind and type(kind[2]) == "number" and EXPECTED_HEALTH[kind[2]]
	if not (mobFresh[key] and kind and kind[1] and expected and lost and lost > 0) then
		return
	end
	mobFresh[key] = nil -- (once)
	local saved, sample = S.Saved("streamMobHealth"), lost / expected
	local learned = type(saved[kind[1]]) == "table" and saved[kind[1]] or nil
	local ratio, kills = learned and tonumber(learned[1]), learned and tonumber(learned[2]) or 0
	if ratio then
		local n = math.min(kills, MOB_SAMPLES - 1)
		sample = (ratio * n + sample) / (n + 1)
	end
	saved[kind[1]] = { math.floor(sample * 1000 + 0.5) / 1000, kills + 1 }
end

-- A mob died. Amounts hidden: what it lost comes from the meter when the fight's over (FightOver).
local function MobDied(key)
	if fight then
		fight.died = key
	end
	LearnKind(key, mobLost[key])
end
S.MobDied = MobDied

-- What the damage meter says of the last fight: everyone's total, mine, how long; nil while it's
-- secret (in combat) or not there.
local function ReadMeter(meterType)
	local session = C_DamageMeter.GetCombatSessionFromType(METER_CURRENT, meterType)
	local total = session.totalAmount
	if issecret(total) or type(total) ~= "number" then
		return nil
	end
	local mine
	if not issecret(session.combatSources) then
		for _, source in ipairs(session.combatSources or {}) do
			if source.isLocalPlayer == true and not issecret(source.totalAmount) then
				mine = source.totalAmount
			end
		end
	end
	local length = session.durationSeconds
	return total, mine, not issecret(length) and length or nil
end

local function Meter(meterType)
	if type(C_DamageMeter) ~= "table" or not C_DamageMeter.GetCombatSessionFromType then
		return nil
	end
	local ok, total, mine, length = pcall(ReadMeter, meterType)
	if ok then
		return total, mine, length
	end
end

-- The fight's totals: the averages, a mob killed alone, my health. (In a group the meter's total is
-- everyone's and so are the hits counted; on me only my own counts.)
local function ReadFight(over, again)
	local done, _, length = Meter(METER_DONE)
	if not done then
		if again and not Fighting() then
			C_Timer.After(METER_AGAIN, function() ReadFight(over) end)
		end
		return
	elseif type(length) == "number" and length > over.endAt - over.at + METER_AGAIN + METER_WAIT + 2 then
		return -- (it holds more than this fight)
	end
	local solo = not (IsInGroup and IsInGroup())
	if over.dealt > 0 and done > 0 then
		LearnHitSize("dealt", done / over.dealt)
	end
	if solo and over.died and over.count == 1 then
		LearnKind(over.died, done)
	end
	local allTaken, myTaken = Meter(METER_TAKEN)
	local taken = myTaken or (solo and allTaken) or nil
	if not taken then
		return
	end
	if over.taken > 0 and taken > 0 then
		LearnHitSize("taken", taken / over.taken)
	end
	local allHealed, myHealed = Meter(METER_HEALING)
	local healed = myHealed or (solo and allHealed) or nil
	if healed and over.heal > 0 and healed > 0 then
		LearnHitSize("heal", healed / over.heal)
	end
	if not solo then
		healed = over.heal * (HitSize("heal") or (life.max or 0) * HIT_GUESS.heal) -- (others heal me too)
	end
	if over.missing and life.missing and life.max and not over.dead and not Fighting() and not Dead() then
		life.missing = math.max(0, math.min(life.max, over.missing + taken - (healed or 0)))
		life.from, life.ticks, life.taken = nil, 0, nil
	end
end

-- Out of combat: a little later the meter has the fight, if any of it went uncounted.
function S.FightOver(now)
	local over = fight
	fight = nil
	if over and over.dealt + over.taken + over.heal > 0 then
		over.endAt = now
		C_Timer.After(METER_WAIT, function() ReadFight(over, true) end)
	end
end

-- Learned before ratios (0.5.0-119/120): "<creature>:<level>" = { maximum, kills }, as ratios now.
local function MigrateMobHealth()
	local saved, old = S.Saved("streamMobHealth"), {}
	for key in pairs(saved) do
		if type(key) == "string" and key:match("^%d+:%-?%d+$") then
			old[#old + 1] = key -- (not changed while going through it)
		end
	end
	for _, key in ipairs(old) do
		local entry = saved[key]
		saved[key] = nil
		local creature, level = key:match("^(%d+):(%-?%d+)$")
		local expected = EXPECTED_HEALTH[tonumber(level)]
		creature = tonumber(creature)
		if expected and type(entry) == "table" and tonumber(entry[1]) then
			local kills = tonumber(entry[2]) or 1
			local was = type(saved[creature]) == "table" and saved[creature] or nil
			local ratio, n = tonumber(entry[1]) / expected, was and tonumber(was[2]) or 0
			if was and tonumber(was[1]) then
				ratio = (tonumber(was[1]) * n + ratio * kills) / (n + kills)
			end
			saved[creature] = { math.floor(ratio * 1000 + 0.5) / 1000, n + kills }
		end
	end
end

-- At a look (StreamSense.lua): a mob's health, 0-1 (nil: not known). Out of combat it's full.
function S.MobHealth(mob, now)
	local key = mob.key
	mobSeen[key] = now
	local kind = mobKind[key] or {}
	mobKind[key] = kind
	kind[1], kind[2], kind[3] = mob.creature, mob.level, mob.class
	if not mob.combat and not mob.dead then
		mobLost[key], mobHits[key], mobFresh[key] = 0, nil, true
	end
	if mob.dead then
		MobDied(key)
		return 0
	end
	local max = MobMax(kind)
	if not max then
		return nil
	end
	local hits = mobHits[key]
	if hits and hits > 0 then
		local lost = (mobLost[key] or 0) + hits * (HitSize("dealt") or max / HITS_TO_KILL)
		return math.max(SURVIVES, math.min(1, 1 - lost / max))
	end
	return math.max(0, math.min(1, 1 - (mobLost[key] or 0) / max))
end

-- Mobs not looked at for a while are forgotten; so are hits on units never looked at (UNIT_COMBAT
-- counts every nameplate's: a player's, mobs past the ones looked at). Now and then, while the
-- sensor runs.
function S.ForgetMobHealth(now)
	for key, at in pairs(mobSeen) do
		if now - at > MOB_KEEP then
			mobSeen[key], mobLost[key], mobFresh[key], mobKind[key], hitAt[key], hitAmount[key] = nil, nil, nil, nil, nil, nil
			mobHits[key] = nil
		end
	end
	for key, at in pairs(hitAt) do
		if now - at > MOB_KEEP and not mobSeen[key] then
			mobLost[key], mobFresh[key], mobKind[key], hitAt[key], hitAmount[key] = nil, nil, nil, nil, nil
			mobHits[key] = nil
		end
	end
end

-- The sensor starts (counting from nothing) or stops.
function S.SenseMobHealth(on)
	mobCombat:UnregisterAllEvents()
	for _, t in ipairs({ mobLost, mobHits, mobFresh, mobKind, mobSeen, hitAt, hitAmount }) do
		wipe(t)
	end
	if on then
		MigrateMobHealth()
		mobCombat:RegisterEvent("UNIT_COMBAT") -- (every unit's: the target's and nameplates' are kept)
	end
end

-- For tests: what mobs lost, and their last hits.
function S.MobHealthBooks()
	return mobLost, hitAt
end
