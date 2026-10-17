local _, ns = ...
local LT = ns.LT
local L = ns.L
local M = LT:GetModule("tweaks")

-- Level-up window (a Misc Tweak), like the level-up screens of old RPGs: your portrait and the
-- new level, what each stat gained (counting up from the old value), the spells your class
-- trainer now has for you (Data/ClassSpells.lua, hover one for its tooltip), a new row of talents,
-- talent points, a class quest that opens at this level, new dungeons, how long the last level
-- took (Chronicle) and where your friends are (Beacon). It comes a moment after the level-up,
-- once Blizzard's own level-up banner is gone, never in combat (it waits). This file: what a level
-- brings and when the window comes; LevelUpWindow.lua draws it (closing by itself, the pin,
-- stepping aside during fights, the arrows that browse other levels).
--
-- Stat gains: the base stats (UnitStat) compared with the last snapshot (taken at login and at
-- every level-up), so Spirit is there too; PLAYER_LEVEL_UP's own numbers (Strength to Intellect)
-- if there's no snapshot from the level before. Health and power gains come from the event only
-- (maximum health is a secret value on Forever). The last real gains are kept per character
-- (levelUps), so the settings' preview shows them for your current level.
--
-- Talents: Forever has classic's talent trees on retail's trait system: one trait tree per class
-- with a node group per talent tree (C_Traits.GetGroupDisplayInfoByTreeID), each with its spent
-- points. A tree's rows are its nodes' heights (posY); row N needs 5 * (N - 1) points in that tree,
-- so it opens at level 10 + 5 * (N - 1) if every point goes there. Level 10 shows the first row of
-- every tree; later row levels the new row of the tree with the most points. Talents (and higher
-- ranks of a talent you don't have, by name) are left out of the trainer's list.
--
-- Cost: nothing until a level-up: the events only note the numbers and start a timer. The talent
-- tree is read when the window is filled.

local SHOW_DELAY = 1.5     -- seconds after the level-up (Blizzard's banner and fanfare first)
local TOAST_WAIT = 8       -- at most this long for Blizzard's level-up banner to go away
local FIRST_TALENT_LEVEL, TALENT_ROW_POINTS = 10, 5
local issecret = issecretvalue or function() return false end

local LevelUp = {}
ns.LevelUp = LevelUp

-- Classic's class quests by the level they open at (the class trainers send you): what they give.
local CLASS_QUESTS = {
	WARRIOR = { [10] = L["Defensive Stance"], [30] = L["Berserker Stance and the Whirlwind Axe"] },
	PALADIN = { [12] = L["Redemption"], [60] = L["Charger (epic mount)"] },
	HUNTER = { [10] = L["Taming your first pet"] },
	ROGUE = { [20] = L["Poisons"] },
	SHAMAN = { [4] = L["Earth Totem"], [10] = L["Fire Totem"], [20] = L["Water Totem"], [30] = L["Air Totem"] },
	WARLOCK = { [10] = L["Summon Voidwalker"], [20] = L["Summon Succubus"], [30] = L["Summon Felhunter"],
		[60] = L["Dreadsteed (epic mount)"] },
	DRUID = { [10] = L["Bear Form"], [16] = L["Aquatic Form"] },
}

local events = CreateFrame("Frame")
local pending, pendingSince, showQueued
local snapshot -- { level, base = { 5 base stats } }

local function Num(v)
	return type(v) == "number" and not issecret(v) and v or nil
end

local InCombat = ns.TweakUtil.InCombat -- Tweaks.lua

local function CharKey()
	return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

-- The highest level to browse to: Forever's cap (60, the class spell data's end), or yours if higher.
local function MaxLevel()
	local cap = Num(GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion())
	if not cap or cap > 60 then
		cap = 60
	end
	return math.max(cap, UnitLevel("player") or 1)
end

-- The five base stats (without gear and buffs: UnitStat's value minus its plus and minus parts, as
-- Blizzard's character sheet works it out), or nil while they're secret.
local function BaseStats()
	local base = {}
	for i = 1, 5 do
		local stat, _, posBuff, negBuff = UnitStat("player", i)
		stat, posBuff, negBuff = Num(stat), Num(posBuff), Num(negBuff)
		if not (stat and posBuff and negBuff) then
			return nil
		end
		base[i] = stat - posBuff - negBuff
	end
	return base
end

local function TakeSnapshot()
	local base = BaseStats()
	if base then
		snapshot = { level = UnitLevel("player"), base = base }
	end
end
LevelUp.TakeSnapshot = TakeSnapshot -- (tests)

-- (LevelUpWindow.lua uses these too)
LevelUp.Num, LevelUp.MaxLevel, LevelUp.FIRST_TALENT_LEVEL = Num, MaxLevel, FIRST_TALENT_LEVEL

---------------------------------------------------------------------------
-- What a level brings
---------------------------------------------------------------------------

local function Known(spellID)
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID)
		if ok and known == true then
			return true
		end
	end
	return IsPlayerSpell and IsPlayerSpell(spellID) == true or false
end

local function RaceAllowed(mask)
	local raceID = select(3, UnitRace("player"))
	if not mask or not raceID then
		return true
	end
	return math.floor(mask / 2 ^ (raceID - 1)) % 2 == 1
end

local function SpellName(spellID)
	local info = C_Spell.GetSpellInfo(spellID)
	return info and info.name, info and info.iconID
end
LevelUp.SpellName = SpellName -- (the window's tooltips and talent icons)

-- The talent tree: { trees = { { name, icon, order, spent, nodes = { { spellID, row, posX, maxRanks,
-- ranks } } } }, spells = { [spellID] = true }, names = { [name] = { spellIDs } } }, or nil.
local function Talents()
	if not (C_Traits and C_Traits.GetConfigInfo and C_Traits.GetTreeNodes and C_Traits.GetGroupDisplayInfoByTreeID) then
		return nil
	end
	local configID = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
	if not configID and C_SpecializationInfo and C_SpecializationInfo.GetCombatConfigIDForSpecGroup then
		configID = C_SpecializationInfo.GetCombatConfigIDForSpecGroup(C_SpecializationInfo.GetActiveSpecGroup())
	end
	local config = configID and C_Traits.GetConfigInfo(configID)
	local treeID = config and config.treeIDs and config.treeIDs[1]
	if not treeID then
		return nil
	end
	local byGroup, groupIDs, result = {}, {}, { trees = {}, spells = {}, names = {} }
	for _, group in ipairs(C_Traits.GetGroupDisplayInfoByTreeID(treeID) or {}) do
		local tree = { name = group.displayName, icon = group.icon, order = group.orderIndex or 0, spent = 0, nodes = {} }
		byGroup[group.groupID] = tree
		groupIDs[#groupIDs + 1] = group.groupID
		result.trees[#result.trees + 1] = tree
	end
	for _, info in ipairs(C_Traits.GetGroupCurrencyInfo and C_Traits.GetGroupCurrencyInfo(configID, groupIDs) or {}) do
		local tree = byGroup[info.traitNodeGroupID]
		local currency = info.currencyInfos and info.currencyInfos[1]
		if tree and currency then
			tree.spent = Num(currency.spent) or 0
		end
	end
	for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
		local node = C_Traits.GetNodeInfo(configID, nodeID)
		local tree
		for _, groupID in ipairs(node and node.groupIDs or {}) do
			tree = tree or byGroup[groupID]
		end
		for _, entryID in ipairs(node and node.entryIDs or {}) do
			local entry = C_Traits.GetEntryInfo(configID, entryID)
			local definition = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
			local spellID = definition and definition.spellID
			if spellID then
				result.spells[spellID] = true
				local name = SpellName(spellID)
				if name then
					result.names[name] = result.names[name] or {}
					table.insert(result.names[name], spellID)
				end
				if tree then
					tree.nodes[#tree.nodes + 1] = { spellID = spellID, posX = node.posX or 0, posY = node.posY or 0,
						maxRanks = node.maxRanks or 1, ranks = node.ranksPurchased or 0, tree = tree.name }
				end
			end
		end
	end
	-- Rows: each tree's node heights, top to bottom.
	for _, tree in ipairs(result.trees) do
		local heights, seen = {}, {}
		for _, node in ipairs(tree.nodes) do
			if not seen[node.posY] then
				seen[node.posY] = true
				heights[#heights + 1] = node.posY
			end
		end
		table.sort(heights)
		for row, y in ipairs(heights) do
			seen[y] = row
		end
		for _, node in ipairs(tree.nodes) do
			node.row = seen[node.posY]
		end
	end
	table.sort(result.trees, function(a, b) return a.order < b.order end)
	return result
end

-- The talent row that opens at this level: { row, groups = { { name, icon, nodes } } }, or nil.
local function TalentRow(level, talents)
	if not talents or level < FIRST_TALENT_LEVEL or (level - FIRST_TALENT_LEVEL) % TALENT_ROW_POINTS ~= 0 then
		return nil
	end
	local row = (level - FIRST_TALENT_LEVEL) / TALENT_ROW_POINTS + 1
	local chosen = {}
	if row == 1 then
		chosen = talents.trees
	else
		local most = 0
		for _, tree in ipairs(talents.trees) do
			most = math.max(most, tree.spent)
		end
		for _, tree in ipairs(talents.trees) do
			if most > 0 and tree.spent == most then
				chosen[#chosen + 1] = tree
			end
		end
	end
	local groups = {}
	for _, tree in ipairs(chosen) do
		local nodes = {}
		for _, node in ipairs(tree.nodes) do
			if node.row == row then
				nodes[#nodes + 1] = node
			end
		end
		table.sort(nodes, function(a, b) return a.posX < b.posX end)
		if #nodes > 0 then
			groups[#groups + 1] = { name = tree.name, icon = tree.icon, nodes = nodes }
		end
	end
	return #groups > 0 and { row = row, groups = groups } or nil
end

-- The trainer's spells for this level: new ones first, then higher ranks. all: known ones too.
-- Talents aren't the trainer's; neither are higher ranks of a talent you don't have.
local function Spells(level, all, talents)
	local _, classFile = UnitClass("player")
	local byLevel = ns.CLASS_SPELLS and ns.CLASS_SPELLS[classFile]
	local list = {}
	for _, id in ipairs(byLevel and byLevel[level] or {}) do
		local need = ns.CLASS_SPELL_NEEDS[id]
		local name, icon = SpellName(id)
		local talentRanks = talents and name and talents.names[name]
		local haveTalent = not talentRanks
		for _, talentSpell in ipairs(talentRanks or {}) do
			haveTalent = haveTalent or Known(talentSpell)
		end
		if name and RaceAllowed(ns.CLASS_SPELL_RACES[id]) and (not need or Known(need))
			and not (talents and talents.spells[id]) and haveTalent then
			local known = Known(id)
			if all or not known then
				list[#list + 1] = { id = id, name = name, icon = icon, rank = ns.CLASS_SPELL_RANK[id], known = known }
			end
		end
	end
	table.sort(list, function(a, b)
		if (a.rank == nil) ~= (b.rank == nil) then
			return a.rank == nil
		end
		return a.name < b.name
	end)
	return list
end

-- Dungeons and raids that open at this level (the dungeon finder's list, where the client has one).
local function Dungeons(level)
	local names, seen = {}, {}
	if not (C_PlayerInfo and C_PlayerInfo.GetInstancesUnlockedAtLevel and GetLFGDungeonInfo) then
		return names
	end
	for _, raid in ipairs({ false, true }) do
		local ok, ids = pcall(C_PlayerInfo.GetInstancesUnlockedAtLevel, level, raid)
		if ok and type(ids) == "table" then
			for _, id in ipairs(ids) do
				local name = GetLFGDungeonInfo(id)
				if type(name) == "string" and not issecret(name) and name ~= "" and not seen[name] then
					seen[name] = true
					names[#names + 1] = name
				end
			end
		end
	end
	return names
end

-- Beacon friends and their levels, highest first (up to four).
local function Friends()
	local beacon = LT:GetModule("beacon")
	local B = ns.Beacon
	local list = {}
	if beacon and beacon.enabled and B and B.FriendList then
		for _, entry in ipairs(B.FriendList()) do
			if entry.peer.level then
				list[#list + 1] = entry.peer
			end
		end
	end
	table.sort(list, function(a, b) return a.level > b.level end)
	while #list > 4 do
		table.remove(list)
	end
	return list
end

-- Everything for the window at `level`; gains = { health, power, talents, stats = { 5 deltas } }
-- (nil when browsing another level).
local function Collect(level, gains, preview)
	local _, classFile = UnitClass("player")
	local chronicle = ns.Chronicle
	local talents = Talents()
	return {
		level = level,
		gains = gains,
		preview = preview,
		spells = Spells(level, preview, talents),
		talentRow = TalentRow(level, talents),
		quest = CLASS_QUESTS[classFile] and CLASS_QUESTS[classFile][level],
		dungeons = Dungeons(level),
		report = gains and chronicle and chronicle.LevelReport and chronicle.LevelReport(level),
		friends = Friends(),
	}
end

-- The arrows: what another level brings (spells, known ones greyed out; talents; class quest).
-- Browsing pins the window.
function LevelUp.Browse(level)
	level = math.max(2, math.min(MaxLevel(), level))
	local mine = UnitLevel("player")
	local record = M.db.levelUps[CharKey()]
	local data = Collect(level, (level == mine and record and record.level == level) and record or nil, true)
	data.browse = true
	LevelUp.Show(data, true) -- LevelUpWindow.lua
	LevelUp.SetPinned(true)
end

---------------------------------------------------------------------------
-- When the window comes: after the level-up, Blizzard's banner first, never in a fight
---------------------------------------------------------------------------

local function TryShow()
	showQueued = false
	if not pending or not M:IsTweakActive("levelUp") then
		return
	end
	if InCombat() then
		return -- PLAYER_REGEN_ENABLED asks again
	end
	local toast = EventToastManagerFrame
	if toast and toast.IsShown and toast:IsShown() and GetTime() - pendingSince < TOAST_WAIT then
		showQueued = true
		C_Timer.After(0.5, TryShow) -- Blizzard's level-up banner first
		return
	end
	local gains = pending
	pending = nil
	-- Base stats against the snapshot from the level before; the event's own numbers otherwise.
	local base = BaseStats()
	local stats = gains.event
	if base and snapshot and snapshot.level == gains.level - 1 then
		local diff, changed = {}, false
		for i = 1, 5 do
			diff[i] = base[i] - snapshot.base[i]
			changed = changed or diff[i] ~= 0
		end
		if changed then
			stats = diff
		end
	end
	gains.stats, gains.event = stats, nil
	TakeSnapshot()
	M.db.levelUps[CharKey()] = gains
	LevelUp.Show(Collect(gains.level, gains, false))
	LevelUp.SetPinned(false) -- a new level-up starts unpinned (also after a pinned one stepped aside for a fight)
end

local function QueueShow(delay)
	if not showQueued then
		showQueued = true
		C_Timer.After(delay, TryShow)
	end
end

-- A pinned window steps aside for a fight and comes back after it.
local function BackAfterFight()
	if not InCombat() and M:IsTweakActive("levelUp") then
		LevelUp.ComeBack()
	end
end

events:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_LEVEL_UP" then
		local level, health, power, talents, _, str, agi, sta, int = ...
		level = Num(level)
		if level then
			pending = { level = level, health = Num(health), power = Num(power), talents = Num(talents),
				event = { Num(str), Num(agi), Num(sta), Num(int) } }
			pendingSince = GetTime()
			QueueShow(SHOW_DELAY)
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pending then
			QueueShow(1)
		elseif LevelUp.IsAway() then
			C_Timer.After(1, BackAfterFight)
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		LevelUp.StepAside() -- (pinned: back after the fight; else it closes)
	elseif event == "PLAYER_ENTERING_WORLD" then
		C_Timer.After(1, TakeSnapshot)
	end
end)

-- The window for your current level, from the settings: the gains of your last real level-up
-- if it was to this level, example numbers otherwise.
function LevelUp.Preview()
	if InCombat() then
		M:Print("not in combat: try again after the fight.") -- (chat output stays English)
		return
	end
	local level = UnitLevel("player") or 1
	local gains = M.db.levelUps[CharKey()]
	local example = not (gains and gains.level == level)
	if example then
		local _, token = UnitPowerType("player")
		gains = { level = level, health = 15 + math.floor(level * 0.8), talents = level >= FIRST_TALENT_LEVEL and 1 or 0,
			power = token == "MANA" and 10 + math.floor(level * 0.6) or nil, stats = { 1, 1, 1, 1, 1 } }
	end
	local data = Collect(level, gains, true)
	data.example = example
	LevelUp.Show(data)
end

-- /levelup: the window again, for your current level.
SLASH_LEFTHYTOOLS_LEVELUP1 = "/levelup"
SlashCmdList.LEFTHYTOOLS_LEVELUP = function() LevelUp.Preview() end

function ns.ApplyLevelUp(on)
	if on then
		for _, event in ipairs({ "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD" }) do
			events:RegisterEvent(event)
		end
		TakeSnapshot()
	else
		events:UnregisterAllEvents()
		pending = nil
		LevelUp.Forget()
	end
end
