local _, ns = ...
local L = ns.L
local B = ns.Beacon
local S = B.Stream

-- The fight stream's battle row, under the spells (StreamView.lua builds the window; the radar stays
-- above). On the left the one shown, their model; on the right the mobs they fight (S.Foes: fighting
-- them or their target; the target first, gold), each with a health bar. The fight is played on
-- them, Pokémon style (the user: "your model does something and affects the enemy models"), as an
-- approximation from what the picture already holds; nothing more goes over the network but their
-- look (and who has aggro, below):
--   * they cast: a casting pose while the bar fills; a harmful spell that went off is cast at their
--     target and its icon flies over; a helpful one, a cast in place;
--   * an instant spell: a harmful one is a special attack on their target (its icon pops on it);
--     either way the icon glows in its school's colour and the hit flashes in it (fire orange,
--     frost blue, shadow purple, ...; Data/SpellSchools.lua), a physical one as before;
--   * their Polymorph: the mob it went off at becomes a sheep (a pig, a turtle, a cow) until it
--     takes damage, dies, the spell's time runs out or it leaves the row;
--   * their target loses health (the estimate): it was them (their spell or ability, else a swing:
--     they step forward and strike); it flinches, and roughly what it lost floats up from it (the
--     loss times what its kind has, S.MobMaxOf: learned, the classic database or usual for its
--     level; a percent when that isn't known). Another mob losing health only flinches (someone
--     else's hit), its number smaller and grey;
--   * they're hit: the mob attacking them (their target first) lunges and strikes, they flinch (a
--     big hit harder), the number floats up from them; a dodge, parry or block: that move and the
--     word; a heal floats up green from them, loot rises through them (a rare find with its drop
--     chance, in gold: StreamView.lua), XP from the mob that died;
--   * a mob dies: it falls and fades; they die: so do they, and they stay down until they're up.
-- Played one after another like turns (an action about half a second); never more than QUEUE_MAX
-- waiting, an older one goes (its number still floats), so it stays close to live.
--
-- Who has aggro on each foe, in a group: the tag of Misc Tweaks' nameplates (Aggro.lua, the same
-- look: ">YOU<" in your own window, else the first three letters of the name in the colour of the
-- role), small on the top edge of its box at the left. Yours read at the sensor's look, a friend's
-- sent with their frame (StreamNet.lua); a friend's build from before it, in a group: a mob
-- attacking them says their name, uncoloured. Drawn only when it changes.
--
-- Their model: you are you (SetUnit, in the form you're in: cat, bear, ...); a friend whose
-- character your client has (in your group, nearby) is them. A friend elsewhere is their class's
-- emblem, "out of reach" under it (the user chose it, after a race's plain model, a ghost of it
-- and an NPC of their class: the game shows no player as they look from afar, and "if you cant
-- render their actual model" the emblem). In your group, their face sits on it: the portrait
-- their party frame has from afar (SetPortraitTexture), a bobblehead on a smaller emblem (the
-- user: "use the head of this 2d ... and then the class emblem as the body"). It still steps up,
-- flashes when hit, pulses while they cast and greys when they die (the head nods as they step
-- up, jolts back when hit and lolls over when they die); the numbers float up from it. The
-- preview's made-up friend is that too, with your face. Weapons: sheathed while they cast and out
-- of a fight, drawn when they swing (the user: "when I cast, the weapon should be sheathed");
-- casters (mages, priests, warlocks) keep them sheathed, their instant spells cast too.
--
-- Cost: an OnUpdate per open window already runs (StreamView.lua); this adds a few comparisons per
-- frame, an animation set when it changes, a frame moved while it lunges.

local ROW_W = 226              -- the row's width (the window's less its edges)
local HERO_W, HERO_H = 50, 58  -- their model, px
local FACE, BODY = 26, 24      -- out of reach in your group: their portrait on their class's emblem, px
local FACE_EVERY = 5           -- s; their portrait asked for again (their look may come late, or change)
local DEAD_TILT = 1.1          -- radians the head lolls over when they die
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local FOES = 4                 -- the mobs fought, right of them
local FOE_W, FOE_H = 38, 50    -- a foe's model (the whole mob), px
local FOE_GAP = 2
local FOE_X = ROW_W - FOES * (FOE_W + 2) - (FOES - 1) * FOE_GAP -- where the foes start (between: the stage)
local AGGRO_SIZE = 8           -- who has aggro: the letters (px, outlined), as on the nameplates
local HERO_FACING, FOE_FACING = 0.75, -0.45 -- turned towards each other (radians)
local HERO_ZOOM = 1.05         -- the camera just a little back (1.4 was too far for a character, in game)
-- Further or closer in a form, from what fit in game: a bear at 1.4 (closer it didn't fit); a cat
-- at 1.4 was too small; a Skyborne's travel form (a bird) too large at 1.4, like the bear before.
-- Another race's travel form (a cheetah): as a cat.
local FORM_ZOOM, CAT_ZOOM, BIRD_ZOOM = 1.4, 1, 2
local CAT, TRAVEL = 768, 783
local SKYBORNE = { [95] = true, [96] = true } -- (race IDs: High Order, Windshaper)

local RETRY, TRIES = 1, 5      -- a model not there yet: asked for again (a creature the client hasn't met)
local LUNGE = 16               -- px a strike steps forward (a mob's: 60% of it)
local DIE_TIME = 1.4           -- falling; then lying, fading (a dying mob keeps its place this long and FADE_TIME)
local FADE_TIME = 1.2
local QUEUE_MAX = 4
local QUEUE_STALE = 2.5        -- an action waiting longer goes (its number floats anyway)
-- A foe out of the row this long (s) is forgotten: back later, what it lost meanwhile wasn't their
-- doing (and a friend's mob id comes round again for another mob).
local FOE_FORGET = 10
local MINE_FOR = 1.3           -- their spell this recent: their target's loss came from it
local RARE_LIFE = 5            -- seconds a rare find floats (other loot: 3.5)
local DROP_MIN = 0.004         -- a smaller loss (of its health) isn't one
local GOLD = { 1, 0.82, 0.3 }
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local DEALT_COLOR, OTHER_COLOR = { 1, 0.85, 0.4 }, { 0.75, 0.75, 0.75 }
local HURT_COLOR, HEAL_COLOR, AVOID_COLOR, XP_COLOR = { 1, 0.3, 0.25 }, { 0.35, 1, 0.4 }, { 0.9, 0.9, 0.9 }, { 0.75, 0.6, 1 }
-- A spell's school (Data/SpellSchools.lua: the game tells addons none, so it comes from the
-- client's own tables): the icon flying over glows in its colour, and the hit it lands flashes in
-- it. A physical one, and a blow, stay as they were: no glow, a red flash.
local SCHOOL_COLORS = { holy = GOLD, fire = { 1, 0.5, 0.1 }, nature = { 0.4, 1, 0.3 }, frost = { 0.45, 0.8, 1 },
	shadow = { 0.6, 0.3, 1 }, arcane = { 1, 0.4, 0.9 } }
local HIT_COLOR = { 1, 0.15, 0.1 }
local GLOW = "Spells\\GenericGlow64" -- (soft and round, black around it: drawn added)
local GLOW_SIZE, GLOW_ALPHA = 32, 0.85
local Value, issecret = S.Value, S.issecret

-- Animation IDs (AnimationData 1.60.1.70425, checked by their fallbacks; seen playing in game).
local ANIM = { stand = 0, death = 1, dead = 6, wound = 9, crit = 10, punch = 16, strike = 17, parry = 21, block = 24,
	ready = 26, dodge = 30, loot = 50, aim = 51, cast = 53, release = 54, special = 57 }
-- Casts that kneel (the loot animation) instead of casting, and go off without a cast at anyone:
-- Skinning, Mining, Herb Gathering, Pick Pocket (each rank; other ranks by name). The user: "the
-- skinning animation is wrong in the box".
local GATHER = { 8613, 8617, 8618, 10768, 2575, 2576, 3564, 10248, 2366, 2368, 3570, 11993, 921 }
local gatherIDs, gatherNames
local function Gathering(spellID)
	if not spellID then
		return false
	end
	if not gatherIDs then
		gatherIDs, gatherNames = {}, {}
		for _, id in ipairs(GATHER) do
			gatherIDs[id] = true
			local name = Value("C_Spell.GetSpellName", id)
			if name then
				gatherNames[name] = true
			end
		end
	end
	if gatherIDs[spellID] then
		return true
	end
	local name = Value("C_Spell.GetSpellName", spellID)
	return name ~= nil and gatherNames[name] == true
end

-- A spell's school ("fire", "frost", ...; nil: physical, or not a class spell). The list is
-- turned into [spell ID] = school the first time a spell is looked at (when an action starts).
local schoolOf
local function School(spellID)
	if type(spellID) ~= "number" or issecret(spellID) then
		return nil
	end
	if not schoolOf then
		schoolOf = {}
		for school, list in pairs(ns.SPELL_SCHOOLS or {}) do
			for _, id in ipairs(list) do
				if type(id) == "table" then -- (a range: { first, last })
					for each = id[1], id[2] do
						schoolOf[each] = school
					end
				else
					schoolOf[id] = school
				end
			end
		end
	end
	return schoolOf[spellID]
end
S.SpellSchool = School

-- Polymorph: the mob it hits becomes the animal in the row (picked by the user: "polymorphed mobs
-- as sheep in the battle row").
-- Known from their own spells only (a Polymorph of theirs that went off at their target; a mob's
-- debuffs aren't read, nothing more goes over the network), until it takes damage (a loss on it),
-- dies, the spell's time runs out or it leaves the row. { spell ID, creature display, seconds }:
-- each rank (SpellMisc's DurationIndex: 20 to 50 s), Pig, Turtle and Cow (wago.tools, 1.60.1.70450).
-- The animal: the first model of the creature the spell turns a mob into (its SpellEffect's
-- transform; the creature's models aren't in the client's tables, the server's are: 856 the white
-- sheep, 16358 a pink pig, 16361 a turtle, 1060 a cow; all in this client's CreatureDisplayInfo).
-- Other IDs by name: the first of that name (Polymorph: rank 1).
local SHEEP, PIG, TURTLE, COW = 856, 16358, 16361, 1060
local POLYMORPH = { { 118, SHEEP, 20 }, { 12824, SHEEP, 30 }, { 12825, SHEEP, 40 }, { 12826, SHEEP, 50 },
	{ 28272, PIG, 50 }, { 28271, TURTLE, 50 }, { 28270, COW, 50 } }
local polyIDs, polyNames
local function Polymorph(spellID)
	if type(spellID) ~= "number" or issecret(spellID) then
		return nil
	end
	if not polyIDs then
		polyIDs, polyNames = {}, {}
		for _, poly in ipairs(POLYMORPH) do
			polyIDs[poly[1]] = poly
			local name = Value("C_Spell.GetSpellName", poly[1])
			if name and not polyNames[name] then
				polyNames[name] = poly
			end
		end
	end
	if polyIDs[spellID] then
		return polyIDs[spellID]
	end
	local name = Value("C_Spell.GetSpellName", spellID)
	return name and polyNames[name]
end

-- Their Polymorph at a slot: only one that's their target (other spells go to the first foe when
-- their target isn't in the row, a guess no sheep should rest on).
local function PolymorphAt(slot, spellID)
	return slot and slot.mob and slot.mob.target and Polymorph(spellID) or nil
end
local AVOID_ANIM = { DODGE = ANIM.dodge, PARRY = ANIM.parry, BLOCK = ANIM.block }
local CASTERS = { MAGE = true, PRIEST = true, WARLOCK = true } -- (weapons stay sheathed)

-- Druid forms and Ghost Wolf by spell ID: a character in one shows on a PlayerModel (in game a
-- DressUpModel kept the native form).
local FORMS = { [768] = true, [5487] = true, [9634] = true, [783] = true, [1066] = true, [24858] = true, [2645] = true }

-- A class's emblem on a texture: the atlas the game uses (GetClassAtlas), else the round icons.
local function Emblem(texture, classFile)
	local atlas = classFile and GetClassAtlas and Value("GetClassAtlas", classFile:lower())
	if atlas and C_Texture and C_Texture.GetAtlasInfo and Value("C_Texture.GetAtlasInfo", atlas) then
		texture:SetAtlas(atlas)
		return
	end
	local coords = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
	texture:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
	if coords then
		texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
	else
		texture:SetTexCoord(0, 0.25, 0, 0.25) -- (a warrior's: not known)
	end
end

local function Call(obj, method, ...)
	local f = obj and obj[method]
	if f then
		local ok, a = pcall(f, obj, ...)
		if ok then
			return a
		end
	end
end

local function Loaded(model)
	local file = Call(model, "GetModelFileID")
	return type(file) == "number" and not issecret(file) and file > 0
end

-- The animation a model should play now: a move while it lasts, else how it stands.
local function Play(model, now)
	local want = model.act and now < model.actUntil and model.act or model.base or ANIM.stand
	if want ~= model.current then
		model.current = want
		Call(model, "SetAnimation", want)
	end
end

local function Act(model, anim, length, now)
	if model then
		model.act, model.actUntil = anim, now + length
	end
end

---------------------------------------------------------------------------
-- The foes: a model and a health bar each (from StreamView.lua)
---------------------------------------------------------------------------

-- Your own window: the real health of a mob with a unit (hidden values go straight into the bar:
-- StatusBar takes them, AllowedWhenTainted). A friend's (or no unit): the estimate, 0-1.
local function RealHealth(bar, unit)
	bar:SetMinMaxValues(0, UnitHealthMax(unit))
	bar:SetValue(UnitHealth(unit))
end

-- Where a kind's health comes from (S.MobMaxOf), for the hover.
local HEALTH_FROM = { learned = L["learned from kills"], database = L["the classic database"], usual = L["usual for its level"] }

-- Your own Bestiary card for a foe's kind, under the rest of its tooltip (the user picked it:
-- "Hovering a foe in the row shows your own card for it: kills and drops"), short: your kills and
-- the coin each brought, its CARD_DROPS likeliest drops with their chances in their quality's colour;
-- a kind you haven't killed: "Not killed yet" and the classic database's likeliest, greyed. Read
-- on hover only; nothing without the Bestiary (switched off) or a creature ID.
local CARD_DROPS = 3

local function FoeBestiary(creature)
	local Bt = ns.Bestiary
	if not (creature and Bt and Bt.module and Bt.module.enabled and Bt.ListDrops) then
		return
	end
	local showPoor, mob = Bt.module.db.showPoor, Bt.Mob(creature)
	local killed = mob and mob.kills > 0
	local list, line
	if killed then
		list, line = Bt.Drops(mob, showPoor), Bt.KillsLine(mob, true)
	else
		list = Bt.Compare(creature, mob, showPoor)
		line = list and #list > 0 and L["Not killed yet: classic database"] or L["Not killed yet"]
	end
	local drops = {}
	for _, drop in ipairs(list or {}) do
		if #drops == CARD_DROPS then
			break
		elseif not drop.group then -- (the world drops in one place: not this kind's own)
			drops[#drops + 1] = drop
			if not drop.name and not Value("C_Item.GetItemInfo", ("item:%d"):format(drop.id)) then
				local load = S.Api("C_Item.RequestLoadItemDataByID")
				if load then
					pcall(load, drop.id) -- (named on the next hover)
				end
			end
		end
	end
	local shade = killed and 1 or 0.6
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine("Bestiary", line, GOLD[1], GOLD[2], GOLD[3], shade, shade, shade)
	Bt.ListDrops(drops)
end

local function FoeOnEnter(slot)
	local mob = slot.mob
	if not mob then
		return
	end
	GameTooltip:SetOwner(slot, "ANCHOR_BOTTOM")
	GameTooltip:SetText(S.MobTitle(mob), 1, 1, 1)
	local class = S.ClassLabel(mob.class)
	if class then
		GameTooltip:AddLine(class, GOLD[1], GOLD[2], GOLD[3])
	end
	if not slot.real then
		if mob.health then
			GameTooltip:AddLine(L["~%d%% health"]:format(math.floor(mob.health * 100 + 0.5)), 1, 0.4, 0.3)
			-- (as this client knows its kind: a friend's own estimate may know it otherwise)
			local _, from = S.MobMaxOf(mob.creature, mob.level, mob.class)
			GameTooltip:AddLine(HEALTH_FROM[from] and L["Estimated from the hits it took, against its kind's health: %s."]:format(HEALTH_FROM[from])
				or L["Estimated by their client from the hits it took."], 0.7, 0.7, 0.7, true)
		else
			GameTooltip:AddLine(L["Health not known yet: it's learned when one of its kind is seen from full health to dead."],
				0.7, 0.7, 0.7, true)
		end
	end

	FoeBestiary(mob.creature) -- (your own card for its kind)
	GameTooltip:Show()
end

-- Loaded: the camera fits the model to the frame as big as it is now, turned towards them.
local function FoeLoaded(model)
	model:GetParent().loaded = true
	model:RefreshCamera()
	model:SetFacing(FOE_FACING)
	model:SetPaused(false) -- (it moves now: it fights)
	model.current = nil
end

-- A creature this client hasn't met yet loads nothing at first (in game: the first try gave no
-- model, the next one did, once the game had asked for it), and nothing tries again by itself: so
-- a slot asks again every RETRY seconds, TRIES times, and shows the mob's initials meanwhile.
-- Polymorphed (slot.display): the animal instead.
local function LoadFoe(slot, creature, again)
	slot.loaded, slot.loadAt = false, GetTime()
	slot.tries = again and (slot.tries or 0) + 1 or 0
	slot.Model:ClearModel()
	if slot.display then
		Call(slot.Model, "SetDisplayInfo", slot.display)
	else
		slot.Model:SetCreature(creature)
	end
	slot.Model:SetFacing(FOE_FACING)
	slot.Model.current = nil
end

-- A slot's model: the mob's creature, or the animal while it's polymorphed (st.sheep); loaded anew
-- when that changes, or the slot's size (its camera fits the size it loaded at).
local function Look(slot, mob, st)
	local display, scale = st.sheep, slot:GetEffectiveScale()
	if slot.creature ~= mob.creature or slot.display ~= display or not slot.scale or math.abs(slot.scale - scale) > 0.001 then
		slot.creature, slot.display, slot.scale = mob.creature, display, scale
		LoadFoe(slot, mob.creature)
	end
end

-- "DB" for Defias Bandit (the first letter of the first two words; a letter of several bytes whole).
local function Initials(name)
	local letters = {}
	for word in (name or "?"):gmatch("%S+") do
		letters[#letters + 1] = word:match("^[\1-\127\194-\244][\128-\191]*") or ""
		if #letters == 2 then
			break
		end
	end
	return table.concat(letters):upper()
end

-- A red flash over a slot when it's hit (its alpha falls back in BattleUpdate).
local function NewFlash(slot, w, h)
	local flash = slot:CreateTexture(nil, "OVERLAY", nil, 6)
	flash:SetPoint("TOPLEFT", 1, -1)
	flash:SetSize(w, h)
	flash:SetColorTexture(HIT_COLOR[1], HIT_COLOR[2], HIT_COLOR[3], 1)
	flash:SetBlendMode("ADD")
	flash:SetAlpha(0)
	slot.flashColor = HIT_COLOR
	return flash
end

-- A foe's flash: red for a blow, a spell's in its school's colour.
local function Flash(slot, alpha, color)
	color = color or HIT_COLOR
	if slot.flashColor ~= color then
		slot.flashColor = color
		slot.Flash:SetColorTexture(color[1], color[2], color[3], 1)
	end
	slot.Flash:SetAlpha(alpha)
end

local function NewFoe(row)
	local slot = CreateFrame("Frame", nil, row)
	slot:SetSize(FOE_W + 2, FOE_H + 8)
	slot.Ring = slot:CreateTexture(nil, "BACKGROUND", nil, -1) -- (gold: their target)
	slot.Ring:SetPoint("TOPLEFT")
	slot.Ring:SetSize(FOE_W + 2, FOE_H + 2)
	slot.Ring:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.8)
	slot.Back = slot:CreateTexture(nil, "BACKGROUND")
	slot.Back:SetPoint("TOPLEFT", 1, -1)
	slot.Back:SetSize(FOE_W, FOE_H)
	slot.Back:SetColorTexture(0, 0, 0, 0.55)
	slot.Model = CreateFrame("PlayerModel", nil, slot)
	slot.Model:SetPoint("TOPLEFT", 1, -1)
	slot.Model:SetSize(FOE_W, FOE_H)
	slot.Model:SetPortraitZoom(0) -- (the whole mob, not its portrait)
	slot.Model:SetScript("OnModelLoaded", FoeLoaded)
	slot.Flash = NewFlash(slot, FOE_W, FOE_H)
	-- Until its model is there: a faint question mark and the mob's initials.
	slot.Stand = slot:CreateTexture(nil, "ARTWORK")
	slot.Stand:SetPoint("CENTER", slot.Back, "CENTER", 0, 0)
	slot.Stand:SetSize(FOE_W - 8, FOE_W - 8)
	slot.Stand:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
	slot.Stand:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	slot.Stand:SetDesaturated(true)
	slot.Stand:SetAlpha(0.3)
	slot.Initials = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	slot.Initials:SetPoint("CENTER", slot.Back, "CENTER", 0, 0)
	slot.Initials:SetTextColor(1, 1, 1)
	slot.BarBack = slot:CreateTexture(nil, "BORDER")
	slot.BarBack:SetPoint("TOPLEFT", slot.Back, "BOTTOMLEFT", 0, -2)
	slot.BarBack:SetSize(FOE_W, 4)
	slot.BarBack:SetColorTexture(1, 1, 1, 0.15)
	slot.Bar = CreateFrame("StatusBar", nil, slot)
	slot.Bar:SetAllPoints(slot.BarBack)
	slot.Bar:SetStatusBarTexture(BAR_TEXTURE)
	slot.Bar:SetStatusBarColor(0.85, 0.2, 0.15)
	slot.Unknown = slot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	slot.Unknown:SetPoint("CENTER", slot.BarBack, "CENTER", 0, 0)
	slot.Unknown:SetTextScale(0.7)
	slot.Unknown:SetText("?")
	-- Who has aggro on it: on the box's top edge at the left (half over the gap above, the mob's head
	-- mostly free), above its model; outlined with a shadow, no backing, like the nameplates' tag.
	slot.Aggro = CreateFrame("Frame", nil, slot)
	slot.Aggro:SetSize(FOE_W, AGGRO_SIZE + 3)
	slot.Aggro:SetPoint("LEFT", slot.Back, "TOPLEFT", 1, 0)
	slot.Aggro:SetFrameLevel(slot.Model:GetFrameLevel() + 2)
	slot.Aggro.Text = slot.Aggro:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	slot.Aggro.Text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", AGGRO_SIZE, "OUTLINE")
	slot.Aggro.Text:SetShadowColor(0, 0, 0, 1)
	slot.Aggro.Text:SetShadowOffset(1, -1)
	slot.Aggro.Text:SetPoint("LEFT", slot.Aggro, "LEFT", 0, 0)
	slot.Aggro:Hide()
	slot:SetMouseMotionEnabled(true)
	slot:SetMouseClickEnabled(false)
	slot:SetScript("OnEnter", FoeOnEnter)
	slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
	slot.dx = 0
	slot:Hide()
	return slot
end

---------------------------------------------------------------------------
-- The one shown: their model
---------------------------------------------------------------------------

local function HeroLoaded(model)
	local hero = model:GetParent()
	if hero.model ~= model or hero.loaded then
		return
	end
	hero.loaded = true
	Call(model, "RefreshCamera")
	Call(model, "SetCamDistanceScale", hero.zoom)
	Call(model, "SetFacing", HERO_FACING)
	Call(model, "SetSheathed", hero.sheathed ~= false)
	model.current = nil
end

-- Their weapons: sheathed (casting, out of a fight) or drawn (swinging).
local function Sheathe(hero, on)
	if hero.sheathed ~= on then
		hero.sheathed = on
		Call(hero.model, "SetSheathed", on)
	end
end

local function NewHeroModel(hero, kind)
	local model = CreateFrame(kind or "DressUpModel", nil, hero)
	model:SetPoint("TOPLEFT", 1, -1)
	model:SetSize(HERO_W, HERO_H)
	Call(model, "SetPortraitZoom", 0)
	model:SetScript("OnModelLoaded", HeroLoaded)
	model:Hide()
	return model
end

local function NewHero(row)
	local hero = CreateFrame("Frame", nil, row)
	hero:SetSize(HERO_W + 2, HERO_H + 2)
	hero:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	hero.Back = hero:CreateTexture(nil, "BACKGROUND")
	hero.Back:SetPoint("TOPLEFT", 1, -1)
	hero.Back:SetSize(HERO_W, HERO_H)
	hero.Back:SetColorTexture(0, 0, 0, 0.55)
	hero.Real = NewHeroModel(hero)   -- (a character this client has: SetUnit; weapons can be sheathed)
	hero.Shifted = NewHeroModel(hero, "PlayerModel") -- (the same in a form: a DressUpModel shows the native one, in game)
	-- Out of reach: their class's emblem (a ring of their class colour behind it read as a blue disc,
	-- in game: the icon has a rim of its own); in your group, their face on top (LoadHero places them).
	hero.Emblem = hero:CreateTexture(nil, "ARTWORK", nil, 2)
	hero.Emblem:Hide()
	hero.Face = hero:CreateTexture(nil, "ARTWORK", nil, 3)
	hero.Face:SetSize(FACE, FACE)
	hero.Face:SetPoint("TOP", hero.Back, "TOP", 0, -3)
	local round = hero:CreateMaskTexture()
	round:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	round:SetAllPoints(hero.Face)
	hero.Face:AddMaskTexture(round)
	hero.Face:Hide()
	hero.Flash = NewFlash(hero, HERO_W, HERO_H)
	-- Not their own look (their character isn't on this client): said under them, small.
	hero.Away = hero:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hero.Away:SetPoint("BOTTOM", hero, "BOTTOM", 0, 3)
	hero.Away:SetTextScale(0.75)
	hero.Away:SetText(L["out of reach"])
	hero.Away:Hide()
	hero:SetMouseMotionEnabled(true)
	hero:SetMouseClickEnabled(false)
	hero:SetScript("OnEnter", function(self)
		if self.Away:IsShown() then
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:SetText(L["Out of reach"], 1, 1, 1)
			GameTooltip:AddLine(self.face
				and L["Their character isn't near you, and the game can't show anyone as they look from afar: their portrait from the party frame, on their class's emblem."]
				or L["Their character isn't near you, and the game can't show anyone as they look from afar: their class instead."],
				0.8, 0.8, 0.8, true)
			GameTooltip:Show()
		end
	end)
	hero:SetScript("OnLeave", function() GameTooltip:Hide() end)
	hero.dx = 0
	return hero
end

-- Who they are now: a unit this client has (you; a friend in your group nearby), else nobody (the
-- emblem); the form they're in; and whose face goes on the emblem (a friend in your group far away;
-- the preview's made-up friend has yours).
local function HeroSource(view)
	local picture = view.picture
	local form = picture.form and picture.form.spellID
	if view.kind == "me" then
		return "player", form
	elseif view.kind == "friend" then
		local unit = picture.guid and Value("UnitTokenFromGUID", picture.guid)
		if type(unit) == "string" then
			if Value("UnitIsVisible", unit) then
				return unit, form
			end
			return nil, form, unit
		end
	elseif view.kind == "preview" then
		return nil, form, "player"
	end
	return nil, form
end

local function LoadHero(hero, unit, form, classFile, face, again)
	hero.loaded, hero.loadAt = false, GetTime()
	hero.tries = again and (hero.tries or 0) + 1 or 0
	hero.inForm = form and FORMS[form] or false
	hero.face = not unit and face or nil
	hero.Away:SetShown(not unit)
	hero.Emblem:SetShown(not unit)
	hero.Face:SetShown(hero.face ~= nil)
	if not unit then
		hero.model = nil
		hero.Real:Hide()
		hero.Shifted:Hide()
		Emblem(hero.Emblem, classFile)
		hero.Emblem:ClearAllPoints()
		if hero.face then -- (the body, under their head)
			hero.Emblem:SetSize(BODY, BODY)
			hero.Emblem:SetPoint("TOP", hero.Face, "BOTTOM", 0, 6)
			SetPortraitTexture(hero.Face, hero.face)
			hero.faceAt, hero.tilt = GetTime(), 0
			Call(hero.Face, "SetRotation", 0)
		else
			hero.Emblem:SetSize(HERO_W - 12, HERO_W - 12)
			hero.Emblem:SetPoint("CENTER", hero.Back, "CENTER", 0, 4)
		end
		hero.loaded = true
		return
	end
	hero.model = hero.inForm and hero.Shifted or hero.Real
	hero[hero.inForm and "Real" or "Shifted"]:Hide()
	hero.zoom = HERO_ZOOM
	if form == CAT then
		hero.zoom = CAT_ZOOM
	elseif form == TRAVEL then
		local ok, _, _, race = pcall(UnitRace, unit) -- (hidden where their identity is: no table key then)
		hero.zoom = ok and not issecret(race) and SKYBORNE[race] and BIRD_ZOOM or CAT_ZOOM
	elseif hero.inForm then
		hero.zoom = FORM_ZOOM
	end
	Call(hero.model, "ClearModel")
	if hero.inForm then
		Call(hero.model, "SetUnit", unit) -- (a PlayerModel shows the form they're in)
	else
		Call(hero.model, "SetUnit", unit, false, false)
	end
	hero.model:Show()
	hero.model.current = nil
end

local function ShowHero(view, now)
	local hero, picture = view.win.Foes.Hero, view.picture
	local unit, form, face = HeroSource(view)
	local classFile = picture.classFile
	local who = unit and ("u:" .. unit .. ":f" .. (form or 0)) or ("e:" .. (classFile or "?") .. ":" .. (face or "")) -- (a new form: loaded anew)
	local scale = hero:GetEffectiveScale()
	if who ~= hero.who or not hero.scale or math.abs(hero.scale - scale) > 0.001 then
		hero.who, hero.scale = who, scale
		LoadHero(hero, unit, form, classFile, face)
	elseif not hero.loaded then
		if Loaded(hero.model) then
			HeroLoaded(hero.model) -- (OnModelLoaded may not have come)
		elseif hero.tries < TRIES and now - hero.loadAt >= RETRY then
			LoadHero(hero, unit, form, classFile, face, true)
		end
	elseif hero.face and now - hero.faceAt >= FACE_EVERY then
		hero.faceAt = now
		SetPortraitTexture(hero.Face, hero.face)
	end
end
---------------------------------------------------------------------------
-- The row: their model, then the mobs they fight
---------------------------------------------------------------------------

function S.BattleBuild(win, above)
	local row = CreateFrame("Frame", nil, win)
	win.Foes = row
	row:SetSize(ROW_W, FOE_H + 8)
	row:SetPoint("TOP", above, "BOTTOM", 0, -6)
	row.slots = {}
	row.Hero = NewHero(row)
	-- A spell flying over: its icon, a soft glow in its school's colour behind it.
	row.Shot = row:CreateTexture(nil, "OVERLAY", nil, 7)
	row.Shot:SetSize(14, 14)
	row.Shot:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.Shot:Hide()
	row.ShotGlow = row:CreateTexture(nil, "OVERLAY", nil, 6)
	row.ShotGlow:SetSize(GLOW_SIZE, GLOW_SIZE)
	row.ShotGlow:SetPoint("CENTER", row.Shot, "CENTER", 0, 0)
	row.ShotGlow:SetTexture(GLOW)
	row.ShotGlow:SetBlendMode("ADD")
	row.ShotGlow:Hide()
	-- More mobs than fit: "+2" over the last.
	row.More = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.More:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -2)
	row.More:Hide()
	return row
end

local function Battle(view)
	local b = view.battle
	if not b then
		b = { queue = {}, foe = {} }
		view.battle = b
	end
	return b
end

-- A mob that died keeps its place a while (it falls and fades there).
local function Dying(b, mob, now)
	local st = b.foe[mob.key]
	return mob.dead and st and st.index and (not st.deadAt or now - st.deadAt < DIE_TIME + FADE_TIME)
end

-- Who has aggro on a foe (the nameplates' tag, Aggro.lua): ">YOU<" in your own window; else the
-- holder's name, theirs when it's the one shown (a friend's, the preview's). Set only when it changes.
local function ShowAggro(view, slot, mob)
	local text, color
	if mob.aggro and not mob.dead and ns.AggroTag then
		local name = mob.aggroSelf and view.picture.name or mob.aggroName
		text, color = ns.AggroTag(mob.aggro, name, view.kind == "me" and mob.aggroSelf)
	end
	if text == slot.aggroText and color == slot.aggroColor then
		return
	end
	slot.aggroText, slot.aggroColor = text, color
	if text then
		slot.Aggro.Text:SetText(text)
		slot.Aggro.Text:SetTextColor(color[1], color[2], color[3])
		slot.Aggro:Show()
	else
		slot.Aggro:Hide()
	end
end

-- A polymorphed mob keeps its place while it's in combat: a sheep may not count as fighting them
-- (off their target, perhaps off its threat list).
local function Sheep(b, mob, now)
	local st = b.foe[mob.key]
	return st and st.sheep and st.index and not mob.dead and mob.combat and now < st.sheepUntil
end

local foeList = {}
local LAST_FIELDS = { "key", "name", "level", "class", "creature", "target", "health", "combat", "engaged" }
local function ShowFoes(view, now)
	local row, picture, b = view.win.Foes, view.picture, Battle(view)
	local foes = S.Foes(picture.mobs, foeList, 99)
	-- The dying go back where they were: dead in the picture, or killed and gone from it (its copy);
	-- so do sheep.
	local listed = {}
	for _, mob in ipairs(foes) do
		listed[mob.key] = true
	end
	for _, mob in ipairs(picture.mobs) do
		if (Dying(b, mob, now) or Sheep(b, mob, now)) and not listed[mob.key] then
			listed[mob.key] = true
			table.insert(foes, math.min(#foes + 1, b.foe[mob.key].index), mob)
		end
	end
	for key, st in pairs(b.foe) do
		if st.deadAt and now - st.deadAt >= DIE_TIME + FADE_TIME + 5 then
			b.foe[key] = nil -- (long gone)
		elseif not st.deadAt and now - st.shownAt >= FOE_FORGET then
			b.foe[key] = nil -- (out of the row a while, alive)
		elseif st.ghost and st.index and not listed[key] and now - st.deadAt < DIE_TIME + FADE_TIME then
			listed[key] = true
			table.insert(foes, math.min(#foes + 1, st.index), st.ghost)
		end
	end
	local shown, total = 0, 0
	for _, mob in ipairs(foes) do
		if mob.creature then
			total = total + 1
		end
		if mob.creature and shown < FOES then
			shown = shown + 1
			local slot = row.slots[shown] or NewFoe(row)
			row.slots[shown] = slot
			slot.x = FOE_X + (shown - 1) * (FOE_W + 2 + FOE_GAP)
			slot:ClearAllPoints()
			slot:SetPoint("TOPLEFT", row, "TOPLEFT", slot.x + slot.dx, 0)
			if slot.key ~= mob.key then -- (another mob: the same one may come in another table)
				slot.key = mob.key
				slot.Model.act, slot.Model.current = nil, nil
				slot:SetAlpha(1)
			end
			slot.mob = mob
			local st = b.foe[mob.key] or {}
			b.foe[mob.key] = st
			st.index, st.shownAt = shown, now
			if not mob.dead and not st.deadAt then -- (a copy: it may die and be gone from the picture at once)
				st.last = st.last or {}
				for _, field in ipairs(LAST_FIELDS) do
					st.last[field] = mob[field]
				end
			end
			if st.sheep and now >= st.sheepUntil then
				st.sheep = nil -- (its time ran out)
			end
			Look(slot, mob, st)
			if not slot.loaded then
				if Loaded(slot.Model) then
					slot.loaded = true -- (OnModelLoaded may not have come)
					Call(slot.Model, "SetPaused", false)
				elseif slot.tries < TRIES and GetTime() - slot.loadAt >= RETRY then
					LoadFoe(slot, mob.creature, true)
				end
			end
			slot.Stand:SetShown(not slot.loaded)
			slot.Initials:SetShown(not slot.loaded)
			slot.Initials:SetText(Initials(mob.name))
			slot.Ring:SetShown(mob.target and not mob.dead and true or false)
			local unit = view.kind == "me" and mob.unit
			slot.real = unit and Value("UnitGUID", unit) == mob.key and pcall(RealHealth, slot.Bar, unit) or false
			if not slot.real then
				slot.Bar:SetMinMaxValues(0, 1)
				slot.Bar:SetValue(mob.dead and 0 or mob.health or 0)
			end
			slot.Unknown:SetShown(not slot.real and not mob.health and not mob.dead)
			ShowAggro(view, slot, mob)
			-- How it stands: ready while it fights, lying once dead, casting while it casts; a sheep stands.
			slot.Model.base = mob.dead and ANIM.dead or st.sheep and ANIM.stand or mob.casting and ANIM.aim
				or (mob.combat or mob.engaged) and ANIM.ready or ANIM.stand
			slot:Show()
		end
	end
	for i = shown + 1, #row.slots do
		row.slots[i].mob, row.slots[i].key = nil, nil
		row.slots[i]:Hide()
	end
	for _, st in pairs(b.foe) do
		if st.sheep and st.shownAt ~= now then
			st.sheep = nil -- (out of the row)
		end
	end
	row.More:SetText("+" .. (total - shown))
	row.More:SetShown(total > shown)
end

local function SlotOf(view, key)
	for _, slot in ipairs(view.win.Foes.slots) do
		if key and slot.key == key and slot:IsShown() then
			return slot
		end
	end
end

-- Their target's slot (the gold one), else the first.
local function TargetSlot(view)
	local first
	for _, slot in ipairs(view.win.Foes.slots) do
		if slot:IsShown() and slot.mob and not slot.mob.dead then
			if slot.mob.target then
				return slot
			end
			first = first or slot
		end
	end
	return first
end

-- The mob that hits them: one attacking them (their target first; never a sheep).
local function AttackerSlot(view)
	local best
	for _, slot in ipairs(view.win.Foes.slots) do
		local mob = slot:IsShown() and slot.mob
		if mob and not mob.dead and mob.attacking and not slot.display then
			if mob.target then
				return slot
			end
			best = best or slot
		end
	end
	return best
end

---------------------------------------------------------------------------
-- The actions, one after another
---------------------------------------------------------------------------

local function Number(n)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

-- What a mob lost, as text: roughly how much (its kind's health), else the percent.
local function LossText(loss)
	if loss.amount then
		return "-" .. Number(math.max(1, math.floor(loss.amount + 0.5)))
	end
	return ("-%d%%"):format(math.max(1, math.floor(loss.frac * 100 + 0.5)))
end

local function Float(view, text, anchor, dy, color, scale, life)
	S.Float(view, text, 0, 6, (math.random() - 0.5) * 10, dy or 30, color, scale, life, anchor)
end

-- The spell's icon over the row (flying, or popping on the one it hit), glowing in its school's
-- colour (a physical one doesn't).
local function ShowShot(row, a)
	row.Shot:SetTexture(a.icon)
	row.Shot:SetAlpha(1)
	row.Shot:Show()
	local color = a.school and SCHOOL_COLORS[a.school]
	if color then
		row.ShotGlow:SetVertexColor(color[1], color[2], color[3])
		row.ShotGlow:SetAlpha(GLOW_ALPHA)
	end
	row.ShotGlow:SetShown(color ~= nil)
end

local LENGTH = { strike = 0.55, ability = 0.55, spell = 0.6, hit = 0.5, miss = 0.5, release = 0.5 }
local HIT_AT = { strike = 0.22, ability = 0.25, spell = 0.42, hit = 0.2, miss = 0.2, release = 0 }

local function Enqueue(view, action, now)
	local b = Battle(view)
	action.at = now
	b.queue[#b.queue + 1] = action
	while #b.queue > QUEUE_MAX do
		local old = table.remove(b.queue, 1)
		old.skipped = true
		S.BattleImpact(view, old, now) -- (its number still floats)
	end
end

-- What a loss at a mob joins: the waiting (or running) spell or ability at it that has no number yet
-- (not a Polymorph's: it hurts nobody), else a swing at it still waiting its turn (what it lost adds
-- up: one swing, not one per picture, while the turns before it play); nil: a swing of its own.
local function Pending(b, key)
	local a = b.action
	if a and (a.kind == "spell" or a.kind == "ability") and a.key == key and not a.loss and not a.impacted and not a.poly then
		return a
	end
	for _, q in ipairs(b.queue) do
		if (q.kind == "spell" or q.kind == "ability") and q.key == key and not q.loss and not q.poly then
			return q
		end
	end
	for _, q in ipairs(b.queue) do
		if q.kind == "strike" and q.key == key then
			return q
		end
	end
end

-- When it lands: the one struck flinches, the number floats up from it; a Polymorph's turns into
-- the animal (also when its turn was skipped), unless it lost health after the spell went off.
function S.BattleImpact(view, a, now)
	local hero = view.win.Foes.Hero
	if a.kind == "strike" or a.kind == "ability" or a.kind == "spell" then
		local slot = SlotOf(view, a.key)
		local st = view.battle and view.battle.foe[a.key]
		if a.poly and slot and st and not st.deadAt and not (st.lostAt and st.lostAt > a.at) then
			st.sheep, st.sheepUntil = a.poly[2], a.at + a.poly[3]
			Look(slot, slot.mob, st)
		end
		if slot and not a.skipped and not (st and st.deadAt) then -- (a mob that fell doesn't flinch)
			Act(slot.Model, ANIM.wound, 0.4, now)
			Flash(slot, 0.55, a.kind ~= "strike" and a.school and SCHOOL_COLORS[a.school] or nil)
			if a.kind ~= "strike" and a.icon then
				local row = view.win.Foes
				ShowShot(row, a)
				row.Shot:ClearAllPoints()
				row.Shot:SetPoint("CENTER", slot, "CENTER", 0, 6)
				row.shotFade = now
			end
		end
		if a.loss and (slot or a.skipped) then
			Float(view, LossText(a.loss), slot or hero, 30, DEALT_COLOR, 1)
		end
	elseif a.kind == "hit" then
		if not a.skipped then
			Act(hero.model, a.big and ANIM.crit or ANIM.wound, 0.45, now)
			hero.Flash:SetAlpha(a.big and 0.7 or 0.5)
		end
		Float(view, "-" .. Number(a.amount), hero, 34, HURT_COLOR, a.big and 1.35 or 1)
	elseif a.kind == "miss" then
		if not a.skipped and AVOID_ANIM[a.avoid] then
			Act(hero.model, AVOID_ANIM[a.avoid], 0.5, now)
		end
		Float(view, S.Word(a.avoid), hero, 26, AVOID_COLOR, 0.85)
	end
end

local function Begin(view, a, now)
	local hero, b = view.win.Foes.Hero, Battle(view)
	a.start, a.length, a.hitAt = now, LENGTH[a.kind] or 0.5, HIT_AT[a.kind] or 0.2
	local caster = CASTERS[view.picture.classFile]
	if a.kind == "strike" then
		Sheathe(hero, false)
		Act(hero.model, ANIM.strike, 0.5, now)
	elseif a.kind == "ability" then
		Sheathe(hero, caster or false) -- (a caster's instant spell: cast; else a weapon's special attack)
		Act(hero.model, caster and ANIM.cast or ANIM.special, 0.5, now)
	elseif a.kind == "spell" then
		Sheathe(hero, true)
		Act(hero.model, ANIM.cast, 0.55, now)
	elseif a.kind == "release" then
		Sheathe(hero, true)
		Act(hero.model, ANIM.release, 0.5, now)
	elseif a.kind == "hit" or a.kind == "miss" then
		a.attacker = AttackerSlot(view)
		if a.attacker then
			a.attackerKey = a.attacker.key
			Act(a.attacker.Model, ANIM.punch, 0.45, now)
		end
	end
	b.action = a
end

-- Out and back: 0 -> 1 over the first 40%, back to 0 by the end.
local function Bump(p)
	if p < 0.4 then
		return p / 0.4
	end
	return math.max(0, (1 - p) / 0.6)
end

local function Step(view, a, p, now)
	local row = view.win.Foes
	if a.kind == "strike" or (a.kind == "ability" and not CASTERS[view.picture.classFile]) then
		row.Hero.dx = math.floor(LUNGE * Bump(p) + 0.5)
	elseif (a.kind == "hit" or a.kind == "miss") and a.attacker and a.attacker.key == a.attackerKey then
		a.attacker.dx = -math.floor(LUNGE * 0.6 * Bump(p) + 0.5)
	elseif a.kind == "spell" and a.icon then
		-- Its icon flies from them to the one it's cast at.
		local slot = SlotOf(view, a.key)
		local from, to = 0.12, a.hitAt / a.length
		if slot and p >= from and p < to then
			local t = (p - from) / (to - from)
			local hx, sx = HERO_W / 2 + 4, slot.x + FOE_W / 2
			if not a.flying then
				a.flying = true
				ShowShot(row, a)
			end
			row.Shot:ClearAllPoints()
			row.Shot:SetPoint("CENTER", row, "TOPLEFT", hx + (sx - hx) * t, -HERO_H / 2 + 8 * math.sin(t * math.pi))
		end
	end
end

local function Finish(view, a)
	local row = view.win.Foes
	row.Hero.dx = 0
	if a.attacker then
		a.attacker.dx = 0
	end
	Battle(view).action = nil
end

---------------------------------------------------------------------------
-- Reading the picture: what happened since the last one
---------------------------------------------------------------------------

local function Harmful(spellID)
	return spellID and Value("C_Spell.IsSpellHarmful", spellID) == true
end

-- A cast of theirs ended: one that went off is cast at their target (harmful) or in place; a
-- Polymorph (always at their target) turns it into the animal when it lands.
local function CastEnded(view, b, was, now)
	if was.gather then
		b.released, b.releasedAt = was.spellID, now -- (skinned, mined, picked: no cast at anyone)
	elseif not was.channel and now >= (was.finish or 0) - 0.4 then -- (went off: not stopped early)
		b.released, b.releasedAt = was.spellID, now
		local target = TargetSlot(view)
		local poly = PolymorphAt(target, was.spellID)
		if (poly or Harmful(was.spellID)) and target then
			b.mineAt = now
			Enqueue(view, { kind = "spell", key = target.key, icon = was.icon, school = School(was.spellID), poly = poly }, now)
		else
			Enqueue(view, { kind = "release" }, now)
		end
	end
end

-- Their cast: a pose while it lasts, and what it did when it ended. A cast that began at the end of
-- the one before ended that one (chain casting: the next began before a picture saw the gap; a
-- cast pushed back by a hit keeps its start, so it's still the same).
local function Casting(view, b, now)
	local cast = view.picture.cast
	if cast and now <= (cast.finish or 0) + 0.3 then
		local was = b.cast
		if was and cast.start and cast.start >= (was.finish or 0) - 0.4 then
			CastEnded(view, b, was, now)
		end
		b.cast = was or {}
		b.cast.spellID, b.cast.icon, b.cast.finish, b.cast.channel = cast.spellID, cast.icon, cast.finish, cast.channel
		b.cast.gather = Gathering(cast.spellID)
		return true
	end
	local was = b.cast
	b.cast = nil
	if was then
		CastEnded(view, b, was, now)
	end
	return false
end

-- Their last spells: a new instant one (not the cast that just went off).
local function Instants(view, b, now)
	local r = view.picture.recent and view.picture.recent[1]
	if not (r and r.spellID) then
		return
	end
	local new = r.spellID ~= b.recentID or r.at > (b.recentAt or 0) + 1.5
	local first = b.recentID == nil -- (what's there when the window opens is old)
	if not new then
		return
	end
	b.recentID, b.recentAt = r.spellID, r.at
	if first or now - r.at > MINE_FOR + 1 or (r.spellID == b.released and now - (b.releasedAt or 0) < 2.5) then
		return
	end
	local target = TargetSlot(view)
	local poly = PolymorphAt(target, r.spellID) -- (a Polymorph whose cast wasn't seen)
	if (poly or Harmful(r.spellID)) and target then
		b.mineAt = now
		Enqueue(view, { kind = "ability", key = target.key, icon = r.icon, school = School(r.spellID), poly = poly }, now)
	else
		Enqueue(view, { kind = "release" }, now)
	end
end

-- A mob died (dead in the picture, or their killing blow): its box falls now, before anything
-- waiting (the user: the nameplate's death "should take preference"). Turns at it go (their numbers
-- float now); a copy keeps its place while it falls and fades, even if it's gone from the picture.
local function Fall(view, b, key, now)
	local st = key and b.foe[key]
	if not st or st.deadAt then
		return
	end
	st.deadAt, st.sheep = now, nil -- (a sheep dies as itself)
	if st.last then
		st.ghost = {}
		for k, v in pairs(st.last) do
			st.ghost[k] = v
		end
		st.ghost.dead, st.ghost.health, st.ghost.target = true, 0, false
	end
	local slot = SlotOf(view, key)
	if slot then
		if st.last or slot.mob then
			Look(slot, st.last or slot.mob, st) -- (its copy: a friend's picture reuses its mob tables)
		end
		Act(slot.Model, ANIM.death, DIE_TIME, now)
		slot.Model.base = ANIM.dead
		slot.Bar:SetMinMaxValues(0, 1)
		slot.Bar:SetValue(0)
	end
	for i = #b.queue, 1, -1 do
		local q = b.queue[i]
		if q.key == key then
			table.remove(b.queue, i)
			q.skipped = true
			S.BattleImpact(view, q, now)
		end
	end
end

-- Their killing blow (a moment): it falls, also when its nameplate is already gone.
function S.BattleKill(view, key)
	Fall(view, Battle(view), key, GetTime())
end

-- Mobs losing health: their target's loss was theirs (their spell, else a swing); another's only
-- flinches. A sheep is itself again. A mob that died falls.
local function Losses(view, b, now)
	local picture = view.picture
	for _, slot in ipairs(view.win.Foes.slots) do
		local mob = slot:IsShown() and slot.mob
		local st = mob and b.foe[mob.key]
		if st then
			if mob.dead then
				Fall(view, b, mob.key, now)
			elseif st.deadAt then
				-- (fallen already: their killing blow came first)
			elseif mob.health then
				if st.health and mob.health < st.health - DROP_MIN then
					st.lostAt = now
					if st.sheep then -- (damage breaks it)
						st.sheep = nil
						Look(slot, mob, st)
					end
					local frac = st.health - mob.health
					local max = S.MobMaxOf and S.MobMaxOf(mob.creature, mob.level, mob.class)
					local loss = { frac = frac, amount = max and frac * max or nil }
					if mob.target and not picture.dead then
						local pending = Pending(b, mob.key)
						if pending and pending.loss then -- (a strike waiting: what it lost adds up)
							pending.loss.frac = pending.loss.frac + loss.frac
							pending.loss.amount = pending.loss.amount and loss.amount and pending.loss.amount + loss.amount or nil
						elseif pending then
							pending.loss = loss -- (their spell or ability landed)
						else
							Enqueue(view, { kind = "strike", key = mob.key, loss = loss }, now) -- (a swing)
						end
					else
						Act(slot.Model, ANIM.wound, 0.35, now) -- (someone else's hit)
						Flash(slot, 0.35)
						Float(view, LossText(loss), slot, 26, OTHER_COLOR, 0.8)
					end
				end
				st.health = mob.health
			end
		end
	end
end

-- After each new picture (StreamView.lua): the row, then what happened.
function S.BattleShow(view)
	local now, b = GetTime(), Battle(view)
	for _, m in ipairs(view.picture.moments or {}) do -- (their killing blows first: its mob may be gone already)
		if m.kind == "kill" and m.key then
			Fall(view, b, m.key, now)
		end
	end
	ShowFoes(view, now)
	ShowHero(view, now)
	local hero, picture = view.win.Foes.Hero, view.picture
	local casting = Casting(view, b, now)
	Instants(view, b, now)
	Losses(view, b, now)
	-- How they stand: lying while dead (falling first), casting, ready in a fight.
	if picture.dead and not b.deadAt then
		b.deadAt = now
		Act(hero.model, ANIM.death, DIE_TIME, now)
	elseif not picture.dead then
		b.deadAt = nil
	end
	local gathering = casting and b.cast and b.cast.gather
	local base = picture.dead and ANIM.dead or gathering and ANIM.loot or casting and ANIM.aim
		or picture.combat and ANIM.ready or ANIM.stand
	hero.Real.base, hero.Shifted.base = base, base
	hero.casting, hero.dead = casting, picture.dead -- (the emblem pulses, greys)
	if casting or not picture.combat then
		Sheathe(hero, true)
	elseif not b.fighting then
		Sheathe(hero, CASTERS[picture.classFile] or false) -- (a fight starts: weapons drawn, not a caster's)
	end
	b.fighting = picture.combat and true or false
end

-- What happened to them (StreamView.lua's moments): true when it's shown here. rare: a rare find's
-- drop chance (loot: StreamView.lua's RareChance), said after its name; it stands out a little.
function S.BattleMoment(view, m, rare)
	local now, hero = GetTime(), view.win.Foes.Hero
	if m.kind == "hurt" then
		Enqueue(view, { kind = "hit", amount = m.amount, big = m.big }, now)
	elseif m.kind == "avoid" then
		Enqueue(view, { kind = "miss", avoid = m.avoid }, now)
	elseif m.kind == "heal" then
		Float(view, "+" .. Number(m.amount), hero, 34, HEAL_COLOR, m.big and 1.35 or 1)
	elseif m.kind == "xp" then
		Float(view, L["+%d XP"]:format(m.amount), SlotOf(view, m.key) or hero, 28, XP_COLOR, 0.9)
	elseif m.kind == "loot" then
		local text, color = S.LootText(m, rare)
		Float(view, text, hero, 44, color, rare and 1.05 or 0.9, rare and RARE_LIFE or 3.5)
	else
		return false
	end
	return true
end

-- Every frame: the action running (or the next), the models' moves, lunges, flashes, the spell.
function S.BattleUpdate(view, elapsed)
	local row = view.win.Foes
	if not (row and row.Hero) then
		return
	end
	local now, b = GetTime(), Battle(view)
	while not b.action and b.queue[1] do
		local a = table.remove(b.queue, 1)
		if now - a.at > QUEUE_STALE then
			a.skipped = true
			S.BattleImpact(view, a, now)
		else
			Begin(view, a, now)
		end
	end
	local a = b.action
	if a then
		local p = (now - a.start) / a.length
		if not a.impacted and now - a.start >= a.hitAt then
			a.impacted = true
			S.BattleImpact(view, a, now)
		end
		Step(view, a, math.min(1, p), now)
		if p >= 1 then
			Finish(view, a)
		end
	end
	local hero = row.Hero
	if hero.model then
		Play(hero.model, now)
	elseif hero.Emblem:IsShown() then -- (out of reach: greyed when dead, pulsing while casting)
		local grey, alpha = hero.dead and true or false, hero.casting and 0.75 + 0.25 * math.sin(now * 6) or 1
		hero.Emblem:SetDesaturated(grey)
		hero.Emblem:SetAlpha(alpha)
		if hero.face then -- (the bobblehead: nods as they step up, jolts back when hit, lolls over dead)
			hero.Face:SetDesaturated(grey)
			hero.Face:SetAlpha(alpha)
			local tilt = hero.dead and DEAD_TILT or -0.5 * hero.dx / LUNGE + 0.4 * (hero.Flash:GetAlpha() or 0)
			if math.abs(tilt - hero.tilt) > 0.01 then
				hero.tilt = tilt
				Call(hero.Face, "SetRotation", tilt)
			end
		end
	end
	if hero.dx ~= hero.shownDx then
		hero.shownDx = hero.dx
		hero:ClearAllPoints()
		hero:SetPoint("TOPLEFT", row, "TOPLEFT", hero.dx, 0)
	end
	local fade = math.min(1, elapsed * 4)
	hero.Flash:SetAlpha(math.max(0, (hero.Flash:GetAlpha() or 0) - fade))
	for _, slot in ipairs(row.slots) do
		if slot:IsShown() then
			Play(slot.Model, now)
			if slot.dx ~= slot.shownDx then
				slot.shownDx = slot.dx
				slot:ClearAllPoints()
				slot:SetPoint("TOPLEFT", row, "TOPLEFT", (slot.x or 0) + slot.dx, 0)
			end
			slot.Flash:SetAlpha(math.max(0, (slot.Flash:GetAlpha() or 0) - fade))
			local st = slot.key and b.foe[slot.key]
			if st and st.deadAt and now - st.deadAt > DIE_TIME then
				slot:SetAlpha(math.max(0, 1 - (now - st.deadAt - DIE_TIME) / FADE_TIME))
			end
		end
	end
	if row.Shot:IsShown() and not (a and a.kind == "spell" and not a.impacted) then
		row.shotFade = row.shotFade or now
		local alpha = 1 - (now - row.shotFade) / 0.35
		if alpha <= 0 then
			row.Shot:Hide()
			row.ShotGlow:Hide()
			row.shotFade = nil
		else
			row.Shot:SetAlpha(alpha)
			row.ShotGlow:SetAlpha(alpha * GLOW_ALPHA)
		end
	elseif a and a.kind == "spell" then
		row.shotFade = nil
	end
end

-- A view shown anew: nothing waiting, everyone standing.
function S.BattleReset(view)
	view.battle = nil
	local row = view.win.Foes
	for _, slot in ipairs(row.slots) do
		slot.mob, slot.creature, slot.display, slot.key, slot.dx = nil, nil, nil, nil, 0
		slot.Model.act, slot.Model.current = nil, nil
		slot:SetAlpha(1)
		slot:Hide()
	end
	local hero = row.Hero
	hero.who, hero.dx, hero.loaded, hero.face = nil, 0, false, nil
	hero.Away:Hide()
	hero.Emblem:Hide()
	hero.Face:Hide()
	for _, model in ipairs({ hero.Real, hero.Shifted }) do
		model.act, model.current, model.base = nil, nil, nil
		model:Hide()
	end
	row.Shot:Hide()
	row.ShotGlow:Hide()
	row.More:Hide()
end
