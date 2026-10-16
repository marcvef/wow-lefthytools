local _, ns = ...
local L = ns.L
local B = ns.Beacon
local S = B.Stream

-- The fight stream's battle row, under the spells (StreamView.lua builds the window; the radar stays
-- above). On the left the one shown, their model; on the right the mobs they fight (S.Foes: fighting
-- them or their target; the target first, gold), each with a health bar. The fight is played on
-- them, Pokémon style (the user: "your model does something and affects the enemy models"), as an
-- approximation from what the picture already holds; nothing more goes over the network but their
-- look:
--   * they cast: a casting pose while the bar fills; a harmful spell that went off is cast at their
--     target and its icon flies over; a helpful one, a cast in place;
--   * an instant spell: a harmful one is a special attack on their target (its icon pops on it);
--   * their target loses health (the estimate): it was them (their spell or ability, else a swing:
--     they step forward and strike); it flinches, and roughly what it lost floats up from it (the
--     loss times what its kind has, S.MobMaxOf; a percent when that isn't known). Another mob losing
--     health only flinches (someone else's hit), its number smaller and grey;
--   * they're hit: the mob attacking them (their target first) lunges and strikes, they flinch (a
--     big hit harder), the number floats up from them; a dodge, parry or block: that move and the
--     word; a heal floats up green from them, loot rises through them, XP from the mob that died;
--   * a mob dies: it falls and fades; they die: so do they, and they stay down until they're up.
-- Played one after another like turns (an action about half a second); never more than QUEUE_MAX
-- waiting, an older one goes (its number still floats), so it stays close to live.
--
-- Their model: you are you (SetUnit, in the form you're in: cat, bear, ...); a friend whose
-- character your client has (in your group, nearby) is them; a friend elsewhere in a form is that
-- form's own model (a cat, a bear, a ghost wolf: textured, the tauren ones for tauren); out of one,
-- their race's plain model wearing their gear (O2;a, their look: race, sex, item IDs) under a light
-- in their class colour: the game can't give a plain race model a face or skin (it comes out white,
-- seen in game), so it's shown as meant, a spirit of them. The preview's made-up friend is that
-- too, from your own race and gear. Weapons: sheathed while they cast and out of a fight, drawn
-- when they swing (the user: "when I cast, the weapon should be sheathed"); casters (mages,
-- priests, warlocks) keep them sheathed, their instant spells cast too.
--
-- Cost: an OnUpdate per open window already runs (StreamView.lua); this adds a few comparisons per
-- frame, an animation set when it changes, a frame moved while it lunges.

local ROW_W = 226              -- the row's width (the window's less its edges)
local HERO_W, HERO_H = 50, 58  -- their model, px
local FOES = 4                 -- the mobs fought, right of them
local FOE_W, FOE_H = 38, 50    -- a foe's model (the whole mob), px
local FOE_GAP = 2
local FOE_X = ROW_W - FOES * (FOE_W + 2) - (FOES - 1) * FOE_GAP -- where the foes start (between: the stage)
local HERO_FACING, FOE_FACING = 0.75, -0.45 -- turned towards each other (radians)
local HERO_ZOOM = 1.05         -- the camera just a little back (1.4 was too far for a character, in game)
local FORM_ZOOM = 1.4          -- further for a form (in game a bear didn't fit)
local NO_CLOAK = 15            -- a cloak tried on a plain race model shows red squares inside (in game): left off
local RETRY, TRIES = 1, 5      -- a model not there yet: asked for again (a creature the client hasn't met)
local LUNGE = 16               -- px a strike steps forward (a mob's: 60% of it)
local DIE_TIME = 1.4           -- falling; then lying, fading (a dying mob keeps its place this long and FADE_TIME)
local FADE_TIME = 1.2
local QUEUE_MAX = 4
local QUEUE_STALE = 2.5        -- an action waiting longer goes (its number floats anyway)
local MINE_FOR = 1.3           -- their spell this recent: their target's loss came from it
local DROP_MIN = 0.004         -- a smaller loss (of its health) isn't one
local GOLD = { 1, 0.82, 0.3 }
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local DEALT_COLOR, OTHER_COLOR = { 1, 0.85, 0.4 }, { 0.75, 0.75, 0.75 }
local HURT_COLOR, HEAL_COLOR, AVOID_COLOR, XP_COLOR = { 1, 0.3, 0.25 }, { 0.35, 1, 0.4 }, { 0.9, 0.9, 0.9 }, { 0.75, 0.6, 1 }
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
local AVOID_ANIM = { DODGE = ANIM.dodge, PARRY = ANIM.parry, BLOCK = ANIM.block }
local CASTERS = { MAGE = true, PRIEST = true, WARLOCK = true } -- (weapons stay sheathed)

-- A form's own model (SpellShapeshiftForm.CreatureDisplayID, 1.60.1.70425; the tauren ones from
-- classic): by the form's spell ID, { the default, a tauren's }.
local FORM_DISPLAY = {
	[768] = { 892, 8571 },     -- Cat Form
	[5487] = { 2281, 2289 },   -- Bear Form
	[9634] = { 2281, 2289 },   -- Dire Bear Form
	[783] = { 918, 918 },      -- Travel Form
	[1066] = { 2428, 2428 },   -- Aquatic Form
	[24858] = { 15374, 15375 }, -- Moonkin Form
	[2645] = { 4613, 4613 },   -- Ghost Wolf
}
local TAUREN = { [6] = true, [28] = true }

-- Each playable race's plain model: { male, female } (ChrRaceXChrModel -> ChrModel.DisplayID, 1.60.1.70425).
local RACE_DISPLAY = {
	[1] = { 57899, 56658 }, [2] = { 51894, 53762 }, [3] = { 49242, 53768 }, [4] = { 54918, 54439 }, [5] = { 54041, 56327 },
	[6] = { 55077, 56316 }, [7] = { 51877, 53291 }, [8] = { 59071, 59223 }, [9] = { 6894, 6895 }, [10] = { 62127, 62128 },
	[11] = { 57027, 58232 }, [22] = { 29422, 29423 }, [24] = { 38551, 38552 }, [25] = { 38551, 38552 }, [26] = { 38551, 38552 },
	[27] = { 75078, 75079 }, [28] = { 75080, 75081 }, [29] = { 75082, 75083 }, [30] = { 75084, 75085 }, [31] = { 79100, 79101 },
	[32] = { 80387, 80388 }, [34] = { 83910, 83911 }, [35] = { 83913, 83914 }, [36] = { 84558, 84560 }, [37] = { 90786, 90787 },
	[52] = { 104597, 104597 }, [70] = { 104597, 104597 }, [84] = { 115279, 115281 }, [85] = { 115279, 115281 },
	[86] = { 116539, 116687 }, [91] = { 116539, 116687 }, [95] = { 139407, 139408 }, [96] = { 139407, 139408 },
}
-- The slots a look sends, in order (StreamNet.lua): head, shoulders, shirt, chest, waist, legs, feet,
-- wrists, hands, back, main hand, off hand, ranged, tabard.
S.LOOK_SLOTS = { 1, 3, 4, 5, 6, 7, 8, 9, 10, 15, 16, 17, 18, 19 }

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

local function ClassColor(classFile)
	local color = classFile and C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(classFile)
	if color then
		local r, g, b = color:GetRGB()
		return { r, g, b }
	end
	return { 0.6, 0.75, 1 }
end

-- A light in their class colour (the spirit: a plain race model is white).
local function Tint(model, color)
	if not (CreateVector3D and CreateColor) then
		return
	end
	local c = CreateColor(color[1], color[2], color[3])
	Call(model, "SetLight", true, { omnidirectional = false, point = CreateVector3D(-1, 1, -1),
		ambientIntensity = 0.9, ambientColor = c, diffuseIntensity = 0.8, diffuseColor = c })
end

-- The look of a character this client has (yours: the preview's made-up friend).
function S.OwnLook()
	local _, _, _, race = pcall(UnitRace, "player")
	local sex = select(2, pcall(UnitSex, "player")) == 3 and 2 or 1
	local items = {}
	for i, slot in ipairs(S.LOOK_SLOTS) do
		local ok, id = pcall(GetInventoryItemID, "player", slot)
		items[i] = ok and type(id) == "number" and not issecret(id) and id or 0
	end
	return { race = tonumber(race), sex = sex, items = items }
end

-- The form you're in (its spell ID; the preview's made-up friend takes it).
function S.OwnForm()
	local index = Value("GetShapeshiftForm")
	local spellID = index and index > 0 and GetShapeshiftFormInfo and select(5, pcall(GetShapeshiftFormInfo, index))
	return type(spellID) == "number" and not issecret(spellID) and spellID or nil
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

local function FoeOnEnter(slot)
	local mob = slot.mob
	if not mob then
		return
	end
	GameTooltip:SetOwner(slot, "ANCHOR_BOTTOM")
	GameTooltip:SetText(mob.level and ("%s (%s)"):format(mob.name, mob.level) or mob.name, 1, 1, 1)
	local class = mob.class == "elite" and L["Elite"] or mob.class == "rare" and L["Rare"] or mob.class == "rareelite" and L["Rare elite"]
	if class then
		GameTooltip:AddLine(class, GOLD[1], GOLD[2], GOLD[3])
	end
	if not slot.real then
		if mob.health then
			GameTooltip:AddLine(L["~%d%% health"]:format(math.floor(mob.health * 100 + 0.5)), 1, 0.4, 0.3)
			GameTooltip:AddLine(L["Estimated from the hits it took, against what its kind has: learned from kills, else what mobs of its level usually have."],
				0.7, 0.7, 0.7, true)
		else
			GameTooltip:AddLine(L["Health not known yet: it's learned when one of its kind is seen from full health to dead."],
				0.7, 0.7, 0.7, true)
		end
	end
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
local function LoadFoe(slot, creature, again)
	slot.loaded, slot.loadAt = false, GetTime()
	slot.tries = again and (slot.tries or 0) + 1 or 0
	slot.Model:ClearModel()
	slot.Model:SetCreature(creature)
	slot.Model:SetFacing(FOE_FACING)
	slot.Model.current = nil
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
	flash:SetColorTexture(1, 0.15, 0.1, 1)
	flash:SetBlendMode("ADD")
	flash:SetAlpha(0)
	return flash
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
	Call(model, "SetCamDistanceScale", hero.inForm and FORM_ZOOM or HERO_ZOOM)
	Call(model, "SetFacing", HERO_FACING)
	if model == hero.Spirit and hero.look and not hero.inForm then
		-- Undressed first: the model dresses itself in your own gear (in game the cloak came back though
		-- it wasn't tried on), then their look, the cloak taken off again.
		Call(model, "Undress")
		for i, item in ipairs(hero.look.items or {}) do
			if item > 0 and S.LOOK_SLOTS[i] ~= NO_CLOAK then
				Call(model, "TryOn", "item:" .. item)
			end
		end
		Call(model, "UndressSlot", NO_CLOAK)
		Tint(model, hero.color)
	end
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
	hero.Spirit = NewHeroModel(hero) -- (a race's plain model, their gear, their class's light)
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
			GameTooltip:AddLine(L["Their character isn't near you, and the game shows nobody's face and skin from afar: this is their race in their gear (in a form, the form), in their class's colour."],
				0.8, 0.8, 0.8, true)
			GameTooltip:Show()
		end
	end)
	hero:SetScript("OnLeave", function() GameTooltip:Hide() end)
	hero.dx = 0
	return hero
end

-- Who they are now: a unit this client has (you; a friend in your group nearby), else their look.
local function HeroSource(view)
	local picture = view.picture
	local form = picture.form and picture.form.spellID
	if view.kind == "me" then
		return "player", nil, form
	elseif view.kind == "friend" then
		local unit = picture.guid and Value("UnitTokenFromGUID", picture.guid)
		if type(unit) == "string" and Value("UnitIsVisible", unit) then
			return unit, nil, form
		end
		return nil, picture.look, form
	end
	view.ownLook = view.ownLook or S.OwnLook() -- (the preview: your race, gear and form)
	return nil, view.ownLook, S.OwnForm()
end

local function LoadHero(hero, unit, look, form, again)
	hero.loaded, hero.loadAt = false, GetTime()
	hero.tries = again and (hero.tries or 0) + 1 or 0
	hero.look = look
	local formDisplay = form and FORM_DISPLAY[form]
	hero.inForm = formDisplay and true or false
	hero.Away:SetShown(not unit)
	if unit then
		hero.model = hero.inForm and hero.Shifted or hero.Real
		hero.Spirit:Hide()
		hero[hero.inForm and "Real" or "Shifted"]:Hide()
		Call(hero.model, "ClearModel")
		if hero.inForm then
			Call(hero.model, "SetUnit", unit) -- (a PlayerModel shows the form they're in)
		else
			Call(hero.model, "SetUnit", unit, false, false)
		end
	else
		local display = look and RACE_DISPLAY[look.race]
		display = display and display[look.sex == 2 and 2 or 1] or RACE_DISPLAY[1][1] -- (no look yet: someone plain)
		if formDisplay then
			display = formDisplay[look and TAUREN[look.race] and 2 or 1]
		end
		hero.model = hero.Spirit
		hero.Real:Hide()
		hero.Shifted:Hide()
		Call(hero.Spirit, "ClearModel")
		Call(hero.Spirit, "SetAutoDress", false)
		Call(hero.Spirit, "SetDisplayInfo", display)
	end
	hero.model:Show()
	hero.model.current = nil
end

local function ShowHero(view, now)
	local hero, picture = view.win.Foes.Hero, view.picture
	local unit, look, form = HeroSource(view)
	hero.color = ClassColor(picture.classFile)
	local who = (unit and ("u:" .. unit) or ("l:" .. (look and look.race or "?") .. ":" .. (look and look.sex or "?") .. ":"
		.. table.concat(look and look.items or {}, ","))) .. ":f" .. (form or 0) -- (a new form: loaded anew)
	local scale = hero:GetEffectiveScale()
	if who ~= hero.who or not hero.scale or math.abs(hero.scale - scale) > 0.001 then
		hero.who, hero.scale = who, scale
		LoadHero(hero, unit, look, form)
	elseif not hero.loaded then
		if Loaded(hero.model) then
			HeroLoaded(hero.model) -- (OnModelLoaded may not have come)
		elseif hero.tries < TRIES and now - hero.loadAt >= RETRY then
			LoadHero(hero, unit, look, form, true)
		end
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
	-- A spell flying over: its icon.
	row.Shot = row:CreateTexture(nil, "OVERLAY", nil, 7)
	row.Shot:SetSize(14, 14)
	row.Shot:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.Shot:Hide()
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

local foeList = {}
local LAST_FIELDS = { "key", "name", "level", "class", "creature", "target", "health", "combat", "engaged" }
local function ShowFoes(view, now)
	local row, picture, b = view.win.Foes, view.picture, Battle(view)
	local foes = S.Foes(picture.mobs, foeList, 99)
	-- The dying go back where they were: dead in the picture, or killed and gone from it (its copy).
	local listed = {}
	for _, mob in ipairs(foes) do
		listed[mob.key] = true
	end
	for _, mob in ipairs(picture.mobs) do
		if Dying(b, mob, now) and not listed[mob.key] then
			listed[mob.key] = true
			table.insert(foes, math.min(#foes + 1, b.foe[mob.key].index), mob)
		end
	end
	for key, st in pairs(b.foe) do
		if st.deadAt and now - st.deadAt >= DIE_TIME + FADE_TIME + 5 then
			b.foe[key] = nil -- (long gone)
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
			st.index = shown
			if not mob.dead and not st.deadAt then -- (a copy: it may die and be gone from the picture at once)
				st.last = st.last or {}
				for _, field in ipairs(LAST_FIELDS) do
					st.last[field] = mob[field]
				end
			end
			local scale = slot:GetEffectiveScale()
			if slot.creature ~= mob.creature or not slot.scale or math.abs(slot.scale - scale) > 0.001 then
				slot.creature, slot.scale = mob.creature, scale
				LoadFoe(slot, mob.creature)
			end
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
			-- How it stands: ready while it fights, lying once dead, casting while it casts.
			slot.Model.base = mob.dead and ANIM.dead or mob.casting and ANIM.aim or (mob.combat or mob.engaged) and ANIM.ready or ANIM.stand
			slot:Show()
		end
	end
	for i = shown + 1, #row.slots do
		row.slots[i].mob, row.slots[i].key = nil, nil
		row.slots[i]:Hide()
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

-- The mob that hits them: one attacking them (their target first).
local function AttackerSlot(view)
	local best
	for _, slot in ipairs(view.win.Foes.slots) do
		local mob = slot:IsShown() and slot.mob
		if mob and not mob.dead and mob.attacking then
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

-- The waiting (or running) spell or ability at a mob that has no number yet: a loss joins it.
local function Pending(b, key)
	local a = b.action
	if a and (a.kind == "spell" or a.kind == "ability") and a.key == key and not a.loss and not a.impacted then
		return a
	end
	for _, q in ipairs(b.queue) do
		if (q.kind == "spell" or q.kind == "ability" or q.kind == "strike") and q.key == key and not q.loss then
			return q
		end
	end
end

-- When it lands: the one struck flinches, the number floats up from it.
function S.BattleImpact(view, a, now)
	local hero = view.win.Foes.Hero
	if a.kind == "strike" or a.kind == "ability" or a.kind == "spell" then
		local slot = SlotOf(view, a.key)
		local st = view.battle and view.battle.foe[a.key]
		if slot and not a.skipped and not (st and st.deadAt) then -- (a mob that fell doesn't flinch)
			Act(slot.Model, ANIM.wound, 0.4, now)
			slot.Flash:SetAlpha(0.55)
			if a.kind ~= "strike" and a.icon then
				local row = view.win.Foes
				row.Shot:SetTexture(a.icon)
				row.Shot:ClearAllPoints()
				row.Shot:SetPoint("CENTER", slot, "CENTER", 0, 6)
				row.Shot:SetAlpha(1)
				row.Shot:Show()
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
			row.Shot:SetTexture(a.icon)
			row.Shot:ClearAllPoints()
			row.Shot:SetPoint("CENTER", row, "TOPLEFT", hx + (sx - hx) * t, -HERO_H / 2 + 8 * math.sin(t * math.pi))
			row.Shot:SetAlpha(1)
			row.Shot:Show()
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

-- Their cast: a pose while it lasts; when it went off, cast at their target (harmful) or in place.
local function Casting(view, b, now)
	local picture, hero = view.picture, view.win.Foes.Hero
	local cast = picture.cast
	if cast and now <= (cast.finish or 0) + 0.3 then
		b.cast = b.cast or {}
		b.cast.spellID, b.cast.icon, b.cast.finish, b.cast.channel = cast.spellID, cast.icon, cast.finish, cast.channel
		b.cast.gather = Gathering(cast.spellID)
		return true
	end
	local was = b.cast
	b.cast = nil
	if was and was.gather then
		b.released, b.releasedAt = was.spellID, now -- (skinned, mined, picked: no cast at anyone)
	elseif was and not was.channel and now >= (was.finish or 0) - 0.4 then -- (went off: not stopped early)
		b.released, b.releasedAt = was.spellID, now
		local target = TargetSlot(view)
		if Harmful(was.spellID) and target then
			b.mineAt = now
			Enqueue(view, { kind = "spell", key = target.key, icon = was.icon }, now)
		else
			Enqueue(view, { kind = "release" }, now)
		end
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
	if Harmful(r.spellID) and target then
		b.mineAt = now
		Enqueue(view, { kind = "ability", key = target.key, icon = r.icon }, now)
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
	st.deadAt = now
	if st.last then
		st.ghost = {}
		for k, v in pairs(st.last) do
			st.ghost[k] = v
		end
		st.ghost.dead, st.ghost.health, st.ghost.target = true, 0, false
	end
	local slot = SlotOf(view, key)
	if slot then
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
-- flinches. A mob that died falls.
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
						slot.Flash:SetAlpha(0.35)
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
	hero.Real.base, hero.Shifted.base, hero.Spirit.base = base, base, base
	if casting or not picture.combat then
		Sheathe(hero, true)
	elseif not b.fighting then
		Sheathe(hero, CASTERS[picture.classFile] or false) -- (a fight starts: weapons drawn, not a caster's)
	end
	b.fighting = picture.combat and true or false
end

-- What happened to them (StreamView.lua's moments): true when it's shown here.
function S.BattleMoment(view, m)
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
		local text, color = S.LootText(m)
		Float(view, text, hero, 44, color, 0.9, 3.5)
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
			row.shotFade = nil
		else
			row.Shot:SetAlpha(alpha)
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
		slot.mob, slot.creature, slot.key, slot.dx = nil, nil, nil, 0
		slot.Model.act, slot.Model.current = nil, nil
		slot:SetAlpha(1)
		slot:Hide()
	end
	local hero = row.Hero
	hero.who, hero.dx, hero.loaded = nil, 0, false
	hero.Away:Hide()
	view.ownLook = nil -- (the preview: your gear as it is now)
	for _, model in ipairs({ hero.Real, hero.Shifted, hero.Spirit }) do
		model.act, model.current, model.base = nil, nil, nil
		model:Hide()
	end
	row.Shot:Hide()
	row.More:Hide()
end
