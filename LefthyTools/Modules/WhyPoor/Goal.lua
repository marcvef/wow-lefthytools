local _, ns = ...
local LT = ns.LT
local L = ns.L
local W = ns.WhyPoor or {}
ns.WhyPoor = W

-- The money goal (the mount): what it costs, what you have, when you'll have it (W.Goal).
-- docs/whypoor.md has the contract and where each number comes from.
--
-- Your own goal first (G.SetCustom: an amount and a name you give it, kept per character; /whypoor goal), else
-- the goals, one at a time, by what this character knows (its spells):
--   * no riding yet: "Mount", Apprentice Riding (spell 33388, Forever's riding skill line 762; level 40);
--   * Apprentice but not Journeyman Riding (33391; level 60): "Epic mount".
--   Paladins and Warlocks get none (their mounts come from class quests).
-- The cost: what the game showed, a riding trainer's price for that spell (already with its reputation
-- discount), kept per character; until then about what guides say (100g, 1000g: "about", basis
-- "estimate"). Mount vendors' prices seen are kept too and shown in the details.
-- The rate: your gold's net change per hour played from Chronicle's days (the last RATE_DAYS days
-- played with a day before them; at least RATE_MIN_DAYS of play), else this session's (at least
-- RATE_MIN_SESSION); nil without enough. The level you'd be then: your XP per hour played (the same
-- span) through the classic XP table (CMaNGOS' player_xp_for_level), only while the table agrees with the
-- game at your level (UnitXPMax), else left out.
-- Cost: nothing runs on its own. The trainer's and merchant's windows are read on the next frame after
-- they open or change; G.Current() is worked out when asked (the window, its strip, the minimap button's
-- tooltip), kept for a second.

local G = {}
W.Goal = G

G.APPRENTICE, G.JOURNEYMAN = 33388, 33391
-- Riding spells that count as having riding: Apprentice and the old racial ones (also in Forever's riding
-- skill line 762), and Forever's Galestrider Riding.
G.RIDING = { 33388, 824, 825, 826, 828, 10861, 10906, 10907, 18995, 1285849 }
G.ABOUT = { [33388] = 1000000, [33391] = 10000000 } -- copper: what guides say (method.gg, 2026-11)
G.NO_GOAL_CLASS = { PALADIN = true, WARLOCK = true }
G.RATE_DAYS, G.RATE_MIN_DAYS, G.RATE_MIN_SESSION = 7, 3 * 3600, 20 * 60
G.KEEP = 1 -- s: G.Current() kept this long

-- XP from one level to the next (CMaNGOS classic: player_xp_for_level).
G.XP = { 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400, 16000, 17700,
	19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400, 50800, 54500, 58600,
	62800, 67100, 71600, 76100, 80800, 85700, 90700, 95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100,
	141200, 147500, 153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800 }

local function Num(v)
	return type(v) == "number" and not LT.IsSecret(v) and v or nil
end

-- This character's saved goal data: { costs = { [spell] = { cost, seen } }, mounts = { [item] = { price, seen,
-- quality } }, custom = { cost (copper), name } (your own goal) }; nil before the saved variables.
function G.Mine()
	local db = W.DB and W.DB()
	local guid = LT.Value(UnitGUID, "player")
	if not (db and db.goal and type(guid) == "string") then
		return nil
	end
	local mine = db.goal[guid]
	if type(mine) ~= "table" then
		mine = {}
		db.goal[guid] = mine
	end
	mine.costs = type(mine.costs) == "table" and mine.costs or {}
	mine.mounts = type(mine.mounts) == "table" and mine.mounts or {}
	return mine
end

function G.Knows(spell)
	if IsPlayerSpell and LT.Value(IsPlayerSpell, spell) == true then
		return true
	end
	return C_SpellBook ~= nil and C_SpellBook.IsSpellKnown ~= nil and LT.Value(C_SpellBook.IsSpellKnown, spell) == true
end

function G.HasRiding()
	for _, spell in ipairs(G.RIDING) do
		if G.Knows(spell) then
			return true
		end
	end
	return false
end

local function SpellName(spell)
	local info = C_Spell and C_Spell.GetSpellInfo and LT.Value(C_Spell.GetSpellInfo, spell)
	return type(info) == "table" and type(info.name) == "string" and not LT.IsSecret(info.name) and info.name or nil
end

---------------------------------------------------------------------------
-- What the game shows: a riding trainer, a mount vendor
---------------------------------------------------------------------------

-- The trainer's list: the riding spells' costs (by the spell's name, as the trainer lists it).
function G.ReadTrainer()
	local mine = G.Mine()
	local n = GetNumTrainerServices and Num(LT.Value(GetNumTrainerServices))
	if not (mine and n) then
		return
	end
	local wanted = {}
	for _, spell in ipairs({ G.APPRENTICE, G.JOURNEYMAN }) do
		local name = SpellName(spell)
		if name then
			wanted[name] = spell
		end
	end
	for i = 1, n do
		local name = LT.Value(GetTrainerServiceInfo, i)
		local spell = type(name) == "string" and wanted[name]
		local cost = spell and GetTrainerServiceCost and Num(LT.Value(GetTrainerServiceCost, i))
		if cost and cost > 0 then
			mine.costs[spell] = { cost = cost, seen = time() }
			G.cached = nil
		end
	end
end

-- A merchant's mounts (item class 15, subclass 5) for gold, with their prices (the reputation discount in).
function G.ReadMerchant()
	local mine = G.Mine()
	local n = GetMerchantNumItems and Num(LT.Value(GetMerchantNumItems))
	if not (mine and n and C_MerchantFrame and C_MerchantFrame.GetItemInfo) then
		return
	end
	for i = 1, n do
		local id = Num(LT.Value(GetMerchantItemID, i))
		local class, subclass
		if id then
			class, subclass = select(6, C_Item.GetItemInfoInstant(id))
			class, subclass = Num(class), Num(subclass)
		end
		if class == 15 and subclass == 5 then
			local info = LT.Value(C_MerchantFrame.GetItemInfo, i)
			local price = type(info) == "table" and Num(info.price)
			if price and price > 0 and not info.hasExtendedCost then
				mine.mounts[id] = { price = math.floor(price / math.max(1, Num(info.stackCount) or 1)), seen = time(),
					quality = Num(LT.Value(C_Item.GetItemQualityByID, id)) }
				G.cached = nil
			end
		end
	end
end

G.events = CreateFrame("Frame")
for _, event in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "MERCHANT_SHOW", "MERCHANT_UPDATE", "PLAYER_MONEY",
		"LEARNED_SPELL_IN_SKILL_LINE", "SPELLS_CHANGED", "PLAYER_LEVEL_UP" }) do -- (Forever has no LEARNED_SPELL_IN_TAB)
	G.events:RegisterEvent(event)
end
G.events:SetScript("OnEvent", function(_, event)
	G.cached = nil
	if event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
		if not G.trainerDue then
			G.trainerDue = true
			C_Timer.After(0, function()
				G.trainerDue = false
				LT.Guard("WhyPoor.trainer", G.ReadTrainer)
			end)
		end
	elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
		if not G.merchantDue then
			G.merchantDue = true
			C_Timer.After(0, function()
				G.merchantDue = false
				LT.Guard("WhyPoor.merchant", G.ReadMerchant)
			end)
		end
	end
end)

---------------------------------------------------------------------------
-- Rate and pace (Chronicle)
---------------------------------------------------------------------------

-- Your gold's net change and your XP per hour played: rate (copper per hour), xp (per hour), the seconds
-- played they rest on, how ("days": Chronicle's days, "session": this session). nil: not enough played,
-- or Chronicle isn't recording.
function G.Rate()
	local C = ns.Chronicle
	local char = C and C.module and C.module.enabled and C.Char and C.Char()
	if type(char) ~= "table" then
		return nil
	end
	local daily = type(char.daily) == "table" and char.daily or {}
	local days = {}
	for day, bucket in pairs(daily) do
		if type(bucket) == "table" then
			days[#days + 1] = day
		end
	end
	table.sort(days)
	-- From today back: each day with the day before it in the list (its gold at its end), up to RATE_DAYS.
	local played, xp, base, used = 0, 0, nil, 0
	for i = #days, 2, -1 do
		local d, before = daily[days[i]], daily[days[i - 1]]
		if not (tonumber(d.played) and tonumber(before.gold)) then
			break
		end
		played, xp, used = played + d.played, xp + (tonumber(d.xp) or 0), used + 1
		base = before.gold
		if used >= G.RATE_DAYS then
			break
		end
	end
	local money = Num(GetMoney())
	if base and money and played >= G.RATE_MIN_DAYS then
		-- (whole gold at a day's end: the middle of that gold piece)
		return (money - (base + 0.5) * 10000) * 3600 / played, xp * 3600 / played, played, "days"
	end
	local s = C.Session and C.Session()
	if type(s) == "table" and tonumber(s.played) and s.played >= G.RATE_MIN_SESSION and tonumber(s.money) then
		return s.money * 3600 / s.played, (tonumber(s.xp) or 0) * 3600 / s.played, s.played, "session"
	end
	return nil
end

-- The level you'd be after `hours` played at `xpPerHour` (rested XP not counted); nil when the classic
-- table doesn't match the game at your level, or no pace.
function G.LevelAfter(hours, xpPerHour)
	local level, have, need = Num(UnitLevel("player")), Num(UnitXP("player")), Num(UnitXPMax("player"))
	local cap = Num(GetMaxPlayerLevel and LT.Value(GetMaxPlayerLevel)) or 60
	if not (level and hours and xpPerHour and xpPerHour > 0) then
		return nil
	end
	if level >= cap then
		return level
	end
	if not (have and need and G.XP[level] == need) then
		return nil
	end
	local gain, left = hours * xpPerHour, need - have
	while gain >= left and level < cap do
		gain = gain - left
		level = level + 1
		left = G.XP[level]
		if not left then
			return level
		end
	end
	return level
end

---------------------------------------------------------------------------
-- The goal
---------------------------------------------------------------------------

-- Your own goal: an amount (copper, more than nothing) and a name (nil: "Your goal"); nil or 0 clears it.
-- True when it's kept.
function G.SetCustom(copper, name)
	local mine = G.Mine()
	if not mine then
		return false
	end
	copper = Num(copper)
	if copper and copper > 0 then
		name = type(name) == "string" and strtrim(name) or ""
		mine.custom = { cost = math.floor(copper + 0.5), name = name ~= "" and LT.CutUTF8(name, 40) or nil }
	else
		mine.custom = nil
	end
	G.Forget()
	return true
end

-- Your own goal: { cost, name } or nil.
function G.Custom()
	local mine = G.Mine()
	local custom = mine and mine.custom
	if type(custom) == "table" and Num(custom.cost) and custom.cost > 0 then
		return custom
	end
end

-- Your own bar for the ideas (Methods' X.Bar): copper an hour an idea must bring to be listed, kept per
-- character; nil or 0 goes back to the automatic one. True when it's kept.
function G.SetBar(copper)
	local mine = G.Mine()
	if not mine then
		return false
	end
	copper = Num(copper)
	mine.bar = copper and copper > 0 and math.floor(copper + 0.5) or nil
	return true
end

-- Your own bar: copper an hour, or nil.
function G.OwnBar()
	local mine = G.Mine()
	local bar = mine and Num(mine.bar)
	return bar and bar > 0 and bar or nil
end

-- Why there's no goal: "class" (Paladins, Warlocks), "done" (Journeyman Riding known), nil (there is one).
function G.Why()
	local _, class = UnitClass("player")
	if G.NO_GOAL_CLASS[class] then
		return "class"
	end
	if G.Knows(G.JOURNEYMAN) then
		return "done"
	end
	return nil
end

-- The goal now, before the numbers: { key, name, level, spell } or nil.
function G.Next()
	local custom = G.Custom()
	if custom then
		return { key = "custom", name = custom.name or L["Your goal"], custom = true, cost = custom.cost }
	end
	if G.Why() then
		return nil
	end
	if not G.HasRiding() then
		return { key = "riding40", name = L["Mount"], level = 40, spell = G.APPRENTICE }
	end
	return { key = "riding60", name = L["Epic mount"], level = 60, spell = G.JOURNEYMAN }
end

-- The contract's goal: { name, cost, have, bags, rate, eta, etaLevel, basis } and more: key, level, spell,
-- about (true: the cost isn't the game's), seen (when the game showed it), costBasis, played (what the
-- rate rests on), how ("days", "session"), xp (per hour), mounts ({ { item, price, seen, quality } }
-- seen at vendors for this goal: rare ones for the mount, epic ones for the epic mount). nil: no goal.
function G.Current()
	local now = GetTime()
	if G.cached and now - G.cachedAt < G.KEEP then
		return G.cached or nil
	end
	G.cachedAt = now
	local goal = G.Next()
	if not goal then
		G.cached = false
		return nil
	end
	local mine = G.Mine() or { costs = {}, mounts = {} }
	local seen = goal.spell and mine.costs[goal.spell]
	if goal.custom then
		goal.costBasis = "yours" -- (what you set)
	elseif type(seen) == "table" and Num(seen.cost) then
		goal.cost, goal.seen, goal.costBasis = seen.cost, seen.seen, "forever"
	else
		goal.cost, goal.about, goal.costBasis = G.ABOUT[goal.spell], true, "estimate"
	end
	goal.have = Num(GetMoney()) or 0
	if W.Bags and W.Bags.Total then
		local ok, total = pcall(W.Bags.Total)
		goal.bags = ok and Num(total) or nil
	end
	goal.rate, goal.xp, goal.played, goal.how = G.Rate()
	if goal.rate and goal.rate > 0 and goal.have < goal.cost then
		goal.eta = (goal.cost - goal.have) / goal.rate
		goal.etaLevel = G.LevelAfter(goal.eta, goal.xp)
	end
	-- The weakest of what it rests on: the cost's, the rate's ("yours").
	goal.basis = goal.costBasis
	goal.mounts = {}
	local quality = goal.spell == G.JOURNEYMAN and 4 or 3
	for item, m in pairs(goal.custom and {} or mine.mounts) do
		if type(m) == "table" and Num(m.price) and (m.quality == nil or m.quality == quality) then
			goal.mounts[#goal.mounts + 1] = { item = item, price = m.price, seen = m.seen, quality = m.quality }
		end
	end
	table.sort(goal.mounts, function(a, b)
		return a.price < b.price or (a.price == b.price and a.item < b.item)
	end)
	G.cached = goal
	return goal
end

-- Forgets the goal kept (money, bags or prices changed).
function G.Forget()
	G.cached = nil
end
