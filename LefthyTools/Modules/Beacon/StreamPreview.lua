local _, ns = ...
local L = ns.L
local B = ns.Beacon
local S = B.Stream

-- The fight stream's preview (/lefthy stream preview, Beacon's settings: Stream window, Preview):
-- your window showing a made-up friend in a made-up fight, on a loop, so every part of a window can
-- be seen without a fight: mobs closing in, one dying, a rare far off, players of her group and not,
-- her casts and instant spells (a Polymorph too), hits, heals, a dodge, loot (a rare find), who has
-- aggro, and the line after her fight. S.FeedPreview(view) makes its next picture (StreamView.lua,
-- every LOOK_GAP while the window is open).

local Value = S.Value
local PREVIEW_FRIEND, PREVIEW_CLASS = "Anna", "MAGE"
local PREVIEW_LOOP = 24
local PREVIEW_CALM = 21.5 -- her fight is over (the rest run off), so its line shows; a new one each loop
local previewMobs = {}
-- What happens to her (seconds into the loop): hits while the bandits are on her, heals, a dodge,
-- the bandit's death (her killing blow, its XP), loot.
local PREVIEW_MOMENTS = {
	{ 3, "hurt", 24 }, { 4.6, "hurt", 31 }, { 5.5, "avoid", "DODGE" }, { 6.3, "hurt", 27 }, { 7.5, "heal", 120 },
	{ 9, "hurt", 26 }, { 10.4, "hurt", 158, true }, { 11.6, "heal", 310, true }, { 12.8, "hurt", 25 },
	{ 14, "kill" }, { 14.1, "xp", 87 }, { 16.5, "loot", 774 }, { 19, "hurt", 30 }, { 21, "avoid", "PARRY" },
}

-- Her spells: a cast every 4 s, { start, spell ID, cast time, its name if the game has none },
-- each joining her last spells when it goes off; a Fire Blast (an instant) now and then.
local PREVIEW_CASTS = { { 0, 133, 2.5, L["Fireball"] }, { 4, 133, 2.5, L["Fireball"] }, { 8, 116, 2.5, L["Frostbolt"] },
	{ 12, 118, 1.5, L["Polymorph"] }, { 16, 133, 2.5, L["Fireball"] } } -- (the last before the fight is over)
local PREVIEW_BLASTS = { 7, 15 }
-- Once a loop she sheeps the mage: her target from a moment before her Polymorph until after it went
-- off (then the leader again). It's a sheep until the fight is over: it leaves the row then.
local PREVIEW_POLYMORPH, PREVIEW_ON_MAGE, PREVIEW_SHEEP = 118, { 11.5, 14.5 }, 13.5

-- Whether a moment of the loop passed since the last step (also over the loop's end).
local function Passed(at, was, t)
	return (was < at and at <= t) or (t < was and (at > was or at <= t))
end

-- The moments passed since the last step, newest first, kept 2.5 s.
local function PreviewMoments(view, was, t)
	local moments = view.picture.moments
	for _, e in ipairs(PREVIEW_MOMENTS) do
		local at, kind = e[1], e[2]
		if Passed(at, was, t) then
			view.previewSeq = (view.previewSeq or 0) % 99 + 1
			local m = { seq = view.previewSeq, kind = kind, at = view.clock }
			if kind == "hurt" or kind == "heal" then
				m.amount, m.big = e[3], e[4] or false
			elseif kind == "avoid" then
				m.avoid = e[3]
			elseif kind == "xp" then
				m.amount, m.key = e[3], "bandit"
			elseif kind == "kill" then
				m.key = "bandit"
			else
				m.item, m.quality, m.chance = e[3], 2, 0.0128 -- (Malachite: a rare find, the classic database's chance from a Defias Bandit)
			end
			table.insert(moments, 1, m)
		end
	end
	while moments[1] and view.clock - moments[#moments].at > 2.5 do
		moments[#moments] = nil
	end
end

local function PreviewMob(n, key, name, level, class, creature)
	local mob = previewMobs[n] or {}
	previewMobs[n] = mob
	mob.key, mob.name, mob.level, mob.class, mob.creature, mob.health, mob.engaged = key, name, level, class, creature, nil, false
	mob.dead, mob.combat, mob.attacking, mob.casting, mob.target, mob.sure = false, false, false, nil, false, 1
	mob.player, mob.classFile, mob.friendly, mob.group, mob.exact = false, nil, false, false, nil
	mob.aggro, mob.aggroName, mob.aggroSelf = nil, nil, false
	return mob
end

function S.FeedPreview(view)
	local picture, t = view.picture, view.clock % PREVIEW_LOOP
	local fighting = t > 2 and t < PREVIEW_CALM
	local mobs = picture.mobs
	wipe(mobs)
	picture.name, picture.classFile, picture.where, picture.facing = PREVIEW_FRIEND, PREVIEW_CLASS, L["Westfall"], 0
	picture.combat = fighting
	picture.power = picture.power or { token = "MANA" }
	picture.power.frac = 0.4 + 0.3 * math.cos(t / 4)
	picture.health = 0.65 + 0.3 * math.cos(t / 3)
	local was = view.previewAt or t
	view.previewAt = t
	PreviewMoments(view, was, t)
	-- (Their models: Hogger, a Defias Bandit, a Defias Rogue Wizard, a Riverpaw Gnoll, Thuros
	-- Lightfingers. Health: the leader's goes down, the bandit's faster, the mage's isn't known.
	-- Who has aggro: her Fireball pulls the leader, Bob, the tank, takes it from her at 8 s; the
	-- bandit stays on her; the mage is on Cedric, passing by, outside her group, until she sheeps it.)
	local onMage = t >= PREVIEW_ON_MAGE[1] and t < PREVIEW_ON_MAGE[2] -- (her target for her Polymorph)
	local leader = PreviewMob(1, "leader", L["Bandit leader"], 16, "elite", 448)
	leader.combat, leader.attacking, leader.target, leader.engaged = fighting, fighting and t < 8, not onMage, fighting
	leader.yards, leader.bearing = math.max(6, 30 - t * 2), -0.6 + 0.15 * math.sin(t)
	leader.casting = fighting and (t % 8 >= 3 and t % 8 < 5) and L["Fireball"] or nil
	local landed = 0 -- (her spells land; the Polymorph hurts nobody)
	for _, c in ipairs(PREVIEW_CASTS) do
		if c[2] ~= PREVIEW_POLYMORPH and t >= c[1] + c[3] then
			landed = landed + 1
		end
	end
	leader.health = math.max(0.1, 1 - 0.13 * landed)
	if leader.attacking then
		leader.aggro, leader.aggroSelf = "DAMAGER", true
	elseif leader.combat then
		leader.aggro, leader.aggroName = "TANK", "Bob"
	end
	mobs[#mobs + 1] = leader
	if t < 18 then
		local bandit = PreviewMob(2, "bandit", L["Bandit"], 15, "normal", 116)
		bandit.dead = t >= 14
		bandit.combat, bandit.attacking, bandit.engaged = not bandit.dead, not bandit.dead, not bandit.dead
		bandit.yards, bandit.bearing = 5 + math.sin(t * 1.3), 0.35 + 0.15 * math.sin(t * 0.8)
		bandit.health = bandit.dead and 0 or math.max(0.05, 1 - 0.12 * math.floor(math.max(0, t - 2) / 1.5)) -- (Bob's hits)
		bandit.aggro, bandit.aggroSelf = not bandit.dead and "DAMAGER" or nil, not bandit.dead
		mobs[#mobs + 1] = bandit
	end
	local mage = PreviewMob(3, "mage", L["Bandit mage"], 15, "normal", 474)
	mage.combat, mage.engaged, mage.target = fighting, fighting, onMage -- (she's on its threat list)
	mage.yards, mage.bearing = 24, 1.1 + 0.03 * t -- (casting at her, until it's a sheep)
	mage.casting = fighting and (t % 6 < 2 and t < PREVIEW_SHEEP) and L["Frostbolt"] or nil
	if fighting and t < PREVIEW_SHEEP then
		mage.aggro, mage.aggroName = "OUTSIDER", "Cedric"
	end
	mobs[#mobs + 1] = mage
	local gnoll = PreviewMob(4, "gnoll", L["Gnoll"], 14, "normal", 117)
	gnoll.yards, gnoll.bearing, gnoll.sure = 32 + 3 * math.sin(t * 0.4), 2.9, 0.25 -- behind, not sure yet: faint
	mobs[#mobs + 1] = gnoll
	local rare = PreviewMob(5, "rare", L["Greyfang"], 17, "rare", 61)
	rare.yards, rare.bearing = 37, 2.4 + 0.1 * math.sin(t * 0.5)
	mobs[#mobs + 1] = rare
	-- Her group: a warrior in front of her, at the leader (placed exactly); and someone passing by.
	local tank = PreviewMob(6, "tank", "Bob", 16)
	tank.player, tank.classFile, tank.friendly, tank.group, tank.combat = true, "WARRIOR", true, true, fighting
	tank.yards, tank.bearing = math.max(4, leader.yards - 2), leader.bearing + 0.25
	tank.exact = math.floor(tank.yards + 0.5)
	mobs[#mobs + 1] = tank
	local passer = PreviewMob(7, "passer", "Cedric", 22)
	passer.player, passer.classFile, passer.friendly, passer.sure = true, "PRIEST", true, 0.5
	passer.yards, passer.bearing = 28, -2.2 + 0.05 * t
	mobs[#mobs + 1] = passer
	-- What she's doing: her cast now, and the spells before it.
	local now = GetTime()
	picture.cast = nil
	for _, c in ipairs(PREVIEW_CASTS) do
		if t >= c[1] and t < c[1] + c[3] then
			local info = Value("C_Spell.GetSpellInfo", c[2])
			local cast = picture.castPreview or {}
			picture.castPreview = cast
			cast.name, cast.icon, cast.spellID = info and info.name or c[4], info and info.iconID, c[2]
			cast.start, cast.finish, cast.channel = now - (t - c[1]), now - (t - c[1]) + c[3], false
			picture.cast = cast
		end
	end
	if not picture.recent[1] then
		for i, id in ipairs({ 2136, 116, 122, 133 }) do -- Fire Blast, Frostbolt, Frost Nova, Fireball (oldest last)
			S.AddRecent(picture.recent, id, now - 8 + i)
		end
	end
	-- A cast that went off joins her last spells; so does a Fire Blast.
	for _, c in ipairs(PREVIEW_CASTS) do
		if Passed(c[1] + c[3], was, t) then
			S.AddRecent(picture.recent, c[2], now)
		end
	end
	for _, at in ipairs(PREVIEW_BLASTS) do
		if Passed(at, was, t) then
			S.AddRecent(picture.recent, 2136, now)
		end
	end
end
