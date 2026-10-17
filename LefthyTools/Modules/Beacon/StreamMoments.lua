local _, ns = ...
local L = ns.L
local B = ns.Beacon
local S = B.Stream

-- What happens to the one a fight stream window shows (StreamView.lua builds the window and calls
-- these after each new picture, and every frame): the picture's moments (hits, heals, what they
-- avoided, XP, killing blows, loot: StreamSense.lua makes yours, StreamNet.lua reads a friend's),
-- each played once in the battle row (StreamBattle.lua) as numbers floating up (S.Float); loot with
-- its icon and, when it's rare, its drop chance; their kills since the window opened; and after a
-- fight, a line on how it went.
--   S.Happenings(view)            a picture's new moments, each number once
--   S.FightLook(view)             a fight begins, goes on, ends (after each new picture)
--   S.MoveFloats(view, elapsed)   every frame; S.FadeSummary(view) too while the fight's line shows
--   S.ClearFloats(view)           a window shown anew

local Value = S.Value
local GOLD = S.GOLD
local FLOATS = 10          -- floating numbers at once, per window
local FLOAT_TIME = 1.6     -- seconds one floats
local SEEN_FOR = 6         -- seconds a moment's number counts as shown (they come round: 1-99)

---------------------------------------------------------------------------
-- After a fight: one line, fading
---------------------------------------------------------------------------

-- The user: "if it remains only in the stream". A fight seen from its start (out of combat, then
-- in) is followed per window: how long it lasted, their kills (killing blows), the XP, their lowest
-- health (estimated). When it's over, a line takes the bottom line's place for SUMMARY_TIME, fading
-- in and out: "38 s · 3 kills · 420 XP · lowest ~10%", only what's known (no XP: none said). Their
-- death ends it too: "Died after 38 s · ...". A fight joined halfway isn't summed up (its numbers
-- would be short). Nothing in chat. Cost: a look per new picture, a fade while the line shows.
local SUMMARY_TIME = 6     -- seconds the line stays, fading in and out
local SUMMARY_WAIT = 1     -- seconds after the fight before it shows (the last kill's XP can come a moment later)
local SHORT_FIGHT = 4      -- shorter, with no kill, XP or death: no line (combat that only flickered)

-- "38 s", "1:12 min".
local function Duration(seconds)
	seconds = math.floor(seconds + 0.5)
	if seconds < 60 then
		return L["%d s"]:format(seconds)
	end
	return L["%d:%02d min"]:format(math.floor(seconds / 60), seconds % 60)
end

-- A moment while a fight is followed (also in the moment after it ends): kills and XP add up.
local function Tally(view, m)
	local fight = view.fight
	if not fight then
		return
	elseif m.kind == "kill" then
		fight.kills = fight.kills + 1
	elseif m.kind == "xp" and m.amount then
		fight.xp = fight.xp + m.amount
	end
end

-- What's known of it, in a line.
local function FightLine(fight)
	local length = Duration(fight.endAt - fight.startAt)
	local parts = { fight.died and L["Died after %s"]:format(length) or length }
	if fight.kills > 0 then
		parts[#parts + 1] = fight.kills == 1 and L["1 kill"] or L["%d kills"]:format(fight.kills)
	end
	if fight.xp > 0 then
		parts[#parts + 1] = L["%s XP"]:format(S.Number(fight.xp))
	end
	if fight.lowest and not fight.died then
		parts[#parts + 1] = L["lowest ~%d%%"]:format(S.Fives(fight.lowest)) -- (in steps of 5, like the bar's)
	end
	return table.concat(parts, "  ·  ")
end

local function ShowSummary(view, fight)
	local win = view.win
	if not fight.died and fight.kills == 0 and fight.xp == 0 and fight.endAt - fight.startAt < SHORT_FIGHT then
		return
	end
	win.Summary:SetText(FightLine(fight))
	if fight.died then
		win.Summary:SetTextColor(1, 0.45, 0.4)
	else
		win.Summary:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	end
	win.Summary:SetAlpha(0)
	win.Summary:Show()
	view.summaryAt = view.clock
end

-- After each new picture: a fight begins (in combat after a picture out of it), goes on, ends (out
-- of combat, or dead); its line shows SUMMARY_WAIT later. In combat again before that: the same
-- fight, pulled on.
function S.FightLook(view)
	local picture, fight = view.picture, view.fight
	if (view.kind == "friend" and view.stale) or (view.kind == "me" and (picture.looked or 0) < view.since) then
		return -- (nothing new from them yet: a picture from before the window opened says nothing)
	end
	local combat = picture.combat and not picture.dead and true or false
	if fight then
		if picture.dead and not fight.died then
			fight.died, fight.endAt = true, fight.endAt or view.clock
		elseif fight.endAt and combat and not fight.died then
			fight.endAt = nil
		elseif not fight.endAt and not combat then
			fight.endAt = view.clock
		end
		if not fight.endAt and picture.health then
			fight.lowest = math.min(fight.lowest or 1, picture.health)
		elseif fight.endAt and view.clock - fight.endAt >= SUMMARY_WAIT then
			view.fight = nil
			ShowSummary(view, fight)
		end
	elseif combat and view.wasCombat == false then
		view.fight = { startAt = view.clock, kills = 0, xp = 0, lowest = picture.health }
	end
	view.wasCombat = combat
end

-- Every frame while the line shows: it fades in, stays, fades out; the bottom line (and the hint
-- above it) gives way meanwhile.
function S.FadeSummary(view)
	local win, age = view.win, view.clock - view.summaryAt
	local alpha = math.max(0, math.min(1, age / 0.3, (SUMMARY_TIME - age) / 1.5))
	if age >= SUMMARY_TIME then
		view.summaryAt = nil
		win.Summary:Hide()
	end
	win.Summary:SetAlpha(alpha)
	win.Status:SetAlpha(1 - alpha)
	win.Hint:SetAlpha(1 - alpha)
end

---------------------------------------------------------------------------
-- What happens to them: numbers floating up over the radar
---------------------------------------------------------------------------


-- The game's own word for a miss, dodge, ... (in its language).
local function Word(token)
	local word = _G[token]
	return type(word) == "string" and word or token:sub(1, 1) .. token:sub(2):lower()
end
S.Word = Word

-- One floating text: from x, y (off its anchor's middle: a model in the battle row, else the radar's)
-- by dx, dy over its life, fading in and out.
local function Float(view, text, x, y, dx, dy, color, scale, life, anchor)
	local list = view.win.Floats.list
	local float
	for _, f in ipairs(list) do
		if not f.on then
			float = f
			break
		end
	end
	if not float and #list < FLOATS then
		float = view.win.Floats:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		list[#list + 1] = float
	elseif not float then
		float = list[1] -- (all in use: the oldest goes)
		for _, f in ipairs(list) do
			if f.age > float.age then
				float = f
			end
		end
	end
	float.on, float.age, float.life = true, 0, life or FLOAT_TIME
	float.x, float.y, float.dx, float.dy, float.anchor = x, y, dx, dy, anchor or view.win.Radar
	float:SetText(text)
	float:SetTextColor(color[1], color[2], color[3])
	float:SetTextScale(scale or 1)
	float:SetAlpha(0)
	float:ClearAllPoints()
	float:SetPoint("CENTER", float.anchor, "CENTER", x, y)
	float:Show()
end
S.Float = Float

function S.MoveFloats(view, elapsed)
	for _, f in ipairs(view.win.Floats.list) do
		if f.on then
			f.age = f.age + elapsed
			local p = f.age / f.life
			if p >= 1 then
				f.on = false
				f:Hide()
			else
				f:ClearAllPoints()
				f:SetPoint("CENTER", f.anchor or view.win.Radar, "CENTER", f.x + f.dx * p, f.y + f.dy * p)
				f:SetAlpha(p < 0.1 and p * 10 or p > 0.65 and (1 - p) / 0.35 or 1)
			end
		end
	end
end

local function ShowKills(view)
	local kills = view.kills
	view.win.Kills:SetText(kills == 1 and L["1 kill"] or kills > 1 and L["%d kills"]:format(kills) or "")
end

-- Loot: its icon and name in its quality's colour (an item the client doesn't know yet: asked for);
-- a rare find (chance: RareChance) has its drop chance after it, in gold.
local function LootText(m, chance)
	local name = Value("C_Item.GetItemInfo", ("item:%d"):format(m.item))
	if not name then
		S.AskItem(m.item)
	end
	local icon = Value("C_Item.GetItemIconByID", m.item)
	local color, colorOf = { 1, 1, 1 }, S.Api("C_Item.GetItemQualityColor")
	if colorOf then
		local ok, r, g, b = pcall(colorOf, m.quality)
		if ok and type(r) == "number" then
			color = { r, g, b }
		end
	end
	local text = (icon and ("|T%s:16:16|t "):format(icon) or "") .. (name or L["an item"])
	if chance then
		local Bt = ns.Bestiary
		text = text .. ", |cffffd14c" .. (Bt and Bt.Percent and Bt.Percent(chance) or ("%.1f%%"):format(chance * 100)) .. "|r"
	end
	return text, color
end
S.LootText = LootText

-- Rare finds (the user picked it: "When a friend loots something rare, the database chance pops up
-- with it"). A loot moment carries only the item and its quality, so the chance is worked out here,
-- from what this client has (nothing more over the network): the mobs killed lately (their kill and
-- XP moments, the last LATELY seconds; a friend's by the creature their stream named) and the dead
-- ones in the picture now are where it may have come from; the one likeliest to drop it is taken,
-- by the Bestiary's classic database (Bt.Known), else your own record of that kind once it has
-- RARE_KILLS kills (Bt.Mob). Below RARE it's a rare find: its float says the chance, in gold, a
-- little bigger and longer. Looked up when loot comes, never per frame; the classic database loads
-- the first time it's asked, as for the Bestiary's window. Without the Bestiary (switched off):
-- plain loot, as before.
local RARE = 0.02
local RARE_KILLS = 10
local LATELY = 45          -- seconds a kill counts as where loot may come from
local LATELY_MAX = 8

-- A mob's creature ID by its key: from the picture; gone from it already, from your own mob's GUID
-- or from the names a friend's stream sent.
local function CreatureFor(view, key)
	for _, mob in ipairs(view.picture.mobs) do
		if mob.key == key then
			return mob.creature
		end
	end
	if view.kind == "friend" then
		return S.FriendCreature(view.id, key)
	end
	return S.CreatureOf(key)
end

-- A kill or its XP: that kind was killed just now (each mob once).
local function Lately(view, key)
	local list = view.lately
	for _, kill in ipairs(list) do
		if kill.key == key then
			kill.at = view.clock
			return
		end
	end
	local creature = CreatureFor(view, key)
	if creature then
		table.insert(list, 1, { key = key, creature = creature, at = view.clock })
		list[LATELY_MAX + 1] = nil
	end
end

-- What a kind of mob drops an item with (0-1; nil: not known).
local function DropChance(Bt, creature, item)
	local known = Bt.Known(creature)
	local said = known and known.items[item]
	if said then
		return said[1]
	end
	local mob = Bt.Mob(creature)
	local own = mob and mob.kills >= RARE_KILLS and mob.items[item]
	return own and (Bt.Chance(mob, own)) or nil
end

-- A loot's chance where it most likely came from, if that's rare (nil: not rare, or not known).
local function RareChance(view, m)
	if m.chance then
		return m.chance < RARE and m.chance or nil -- (the preview's, made up)
	end
	local Bt = ns.Bestiary
	if not (Bt and Bt.module and Bt.module.enabled and m.item) then
		return nil
	end
	local best
	for _, kill in ipairs(view.lately) do
		local chance = view.clock - kill.at <= LATELY and DropChance(Bt, kill.creature, m.item)
		if chance and chance > 0 and chance > (best or 0) then
			best = chance
		end
	end
	for _, mob in ipairs(view.picture.mobs) do
		local chance = mob.dead and mob.creature and DropChance(Bt, mob.creature, m.item)
		if chance and chance > 0 and chance > (best or 0) then
			best = chance
		end
	end
	return best and best < RARE and best or nil
end

-- A moment: played in the battle row (StreamBattle.lua: a hit lands on their model, a heal or loot
-- floats up from it, XP from the mob that died); a kill counts (and adds to a fight's line).
local function Spawn(view, m)
	Tally(view, m)
	if (m.kind == "kill" or m.kind == "xp") and m.key then
		Lately(view, m.key) -- (loot may come from it)
	end
	if m.kind == "kill" then
		view.kills = view.kills + 1
		ShowKills(view)
		S.BattleKill(view, m.key) -- (its box falls now)
	else
		S.BattleMoment(view, m, m.kind == "loot" and RareChance(view, m) or nil)
	end
end

-- The picture's new moments (each number once), oldest first.
function S.Happenings(view)
	local moments = view.picture.moments
	for i = #(moments or {}), 1, -1 do
		local m = moments[i]
		local seen = view.seen[m.seq]
		if not seen or view.clock - seen > SEEN_FOR then
			view.seen[m.seq] = view.clock
			Spawn(view, m)
		end
	end
end

function S.ClearFloats(view)
	for _, f in ipairs(view.win.Floats.list) do
		f.on = false
		f:Hide()
	end
	wipe(view.seen)
	wipe(view.lately)
	view.kills = 0
	ShowKills(view)
end
