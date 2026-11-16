local _, ns = ...
local LT = ns.LT
local W = ns.WhyPoor or {}
ns.WhyPoor = W

-- Who I am now: level, class, race, faction, professions, recipes, place, gold (W.Context).
-- docs/whypoor.md has the contract and "The ideas" what each field rests on.
--
-- Everything is read from the game when asked (a few calls, no event of its own): the ideas ask
-- once per run of theirs (Methods.lua), the window when it draws. A value the game hides (a secret)
-- or doesn't answer is left out, never guessed.

local Value, Readable = LT.Value, LT.Readable

local Cx = {}
W.ContextParts = Cx -- (Methods.lua and the tests: the skill lines and the rules below)

-- The skill lines a character can have that make money (Data/Recipes.lua's lines, plus Lockpicking).
Cx.LINES = {
	herbalism = 182, mining = 186, skinning = 393, fishing = 356, -- gathering
	alchemy = 171, blacksmithing = 164, enchanting = 333, engineering = 202, leatherworking = 165, tailoring = 197, -- crafting
	cooking = 185, firstAid = 129, lockpicking = 633, -- secondary (Lockpicking: rogues)
}
-- The primary professions: a character can have two of them (classic's rule, Forever's too).
Cx.PRIMARY = { [182] = true, [186] = true, [393] = true, [171] = true, [164] = true, [333] = true, [202] = true,
	[165] = true, [197] = true }
Cx.PRIMARY_MAX = 2
Cx.PICK_POCKET = 921 -- the rogue's Pick Pocket (trained at level 4)

-- The zone I'm in: the best map for the player, up to its zone (a cave or a city's floor counts as its
-- zone: map type 3 is a zone, 4 a micro-dungeon, 5 an orphan, 6 a dungeon). nil where there's none.
function Cx.Zone()
	local map = Value(C_Map and C_Map.GetBestMapForUnit, "player")
	local seen = 0
	while type(map) == "number" and seen < 5 do
		local info = Value(C_Map.GetMapInfo, map)
		if type(info) ~= "table" or info.mapType == nil or info.mapType <= 3 then
			return map
		end
		if not info.parentMapID or info.parentMapID == 0 then
			return map
		end
		map, seen = info.parentMapID, seen + 1
	end
	return map
end

-- A skill line's rank, or nil when the character doesn't have it. C_SkillInfo first (every line,
-- Lockpicking too), else the professions the game lists (GetProfessions: no Lockpicking there).
function Cx.ReadSkills()
	local found = {}
	local byID = C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID
	if byID then
		for _, line in pairs(Cx.LINES) do
			local info = Value(byID, line)
			if type(info) == "table" and Readable(info.rank) and type(info.rank) == "number" and info.rank > 0
				and (info.skillID == nil or info.skillID == line) then
				found[line] = info.rank
			end
		end
	end
	if not next(found) and GetProfessions and GetProfessionInfo then
		local parents = ns.RecipeData and ns.RecipeData.parents or {}
		local ok, a, b, c, d, e = pcall(GetProfessions)
		for _, index in ipairs(ok and { a or false, b or false, c or false, d or false, e or false } or {}) do
			if index then
				local okInfo, _, _, rank, _, _, _, line = pcall(GetProfessionInfo, index)
				if okInfo and Readable(line) and Readable(rank) and type(line) == "number" and type(rank) == "number" then
					line = parents[line] or line
					if rank > 0 then
						found[line] = rank
					end
				end
			end
		end
	end
	return found
end

-- This character's known recipes, from Chronicle's record of it (its scan: Recipes.lua). Empty when
-- Chronicle is off or hasn't scanned yet.
function Cx.ReadRecipes(professions)
	local known = {}
	local C = ns.Chronicle
	local R = C and C.Recipes
	local key = C and C.CurrentKey and C.CurrentKey()
	if not (R and R.People and key) then
		return known
	end
	local me = "me:" .. tostring(key)
	for line in pairs(professions) do
		local ok, people = pcall(R.People, line)
		for _, person in ipairs(ok and type(people) == "table" and people or {}) do
			if person.id == me then
				for spell in pairs(person.known or {}) do
					known[spell] = true
				end
			end
		end
	end
	return known
end

-- How many are in my group (1: alone).
function Cx.GroupSize()
	local n = Value(GetNumGroupMembers)
	if type(n) == "number" and n > 1 then
		return n
	end
	if Value(IsInGroup) == true then
		return 2
	end
	return 1
end

function W.Context()
	local professions = Cx.ReadSkills()
	local level = Value(UnitLevel, "player")
	local okClass, _, class = pcall(UnitClass, "player")
	class = okClass and Readable(class) and class or nil
	local okRace, _, race = pcall(UnitRace, "player")
	race = okRace and Readable(race) and race or nil
	local faction = Value(UnitFactionGroup, "player")
	local primaries = 0
	for line in pairs(professions) do
		if Cx.PRIMARY[line] then
			primaries = primaries + 1
		end
	end
	local pick = Value(C_SpellBook and C_SpellBook.IsSpellKnown, Cx.PICK_POCKET)
	local ctx = {
		level = type(level) == "number" and level > 0 and level or nil,
		class = type(class) == "string" and class or nil,
		race = type(race) == "string" and race or nil,
		faction = (faction == "Alliance" or faction == "Horde") and faction or nil,
		gold = Value(GetMoney),
		map = Cx.Zone(),
		professions = professions,
		recipes = Cx.ReadRecipes(professions),
		group = Cx.GroupSize(),
		primaries = primaries,
		freePrimary = primaries < Cx.PRIMARY_MAX,
		canSkin = professions[393] ~= nil,
		canHerb = professions[182] ~= nil,
		canMine = professions[186] ~= nil,
		canFish = professions[356] ~= nil,
		canDisenchant = professions[333] ~= nil,
	}
	ctx.grouped = ctx.group > 1
	-- Pick Pocket: the spell when the game answers, else a rogue of level 4 or more (when it's trained).
	if class == "ROGUE" then
		if pick == nil then
			ctx.canPick = (ctx.level or 0) >= 4
		else
			ctx.canPick = pick == true
		end
	else
		ctx.canPick = false
	end
	return ctx
end
