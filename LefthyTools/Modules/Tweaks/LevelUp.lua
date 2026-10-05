local _, ns = ...
local LT = ns.LT
local L = ns.L
local M = LT:GetModule("tweaks")

-- Level-up window (a Misc Tweak), like the level-up screens of old RPGs: your portrait and the
-- new level, what each stat gained (counting up from the old value), the spells your class
-- trainer now has for you (Data/ClassSpells.lua, hover one for its tooltip), a new row of talents,
-- talent points, a class quest that opens at this level, new dungeons, how long the last level
-- took (Chronicle) and where your friends are (Beacon). It comes a moment after the level-up,
-- once Blizzard's own level-up banner is gone, never in combat (it waits), and closes by itself
-- after a while (not while the mouse is on it), with Escape, its X, or when a fight starts.
-- Pinned (the pin, or dragging it) it stays until closed and steps aside during fights; the
-- arrows next to the level browse what other levels bring.
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
-- Cost: nothing until a level-up. The window's OnUpdate (count-ups, fading, closing by itself)
-- runs only while it's on screen; the talent tree is read when the window is filled.

local SHOW_DELAY = 1.5     -- seconds after the level-up (Blizzard's banner and fanfare first)
local TOAST_WAIT = 8       -- at most this long for Blizzard's level-up banner to go away
local HOLD = 25            -- seconds on screen before it closes by itself (unless pinned)
local FADE_IN, FADE_OUT = 0.3, 0.4
local COUNT_START, COUNT_TIME, COUNT_STAGGER = 0.6, 0.7, 0.09 -- stats count up one after another
local WIDTH = 440
local COLUMN = 180          -- a stat cell; two side by side
local ICON, ICON_GAP, ICONS_PER_ROW, MAX_ICONS = 36, 8, 8, 16
local TALENT_ICON, TALENT_X, TALENTS_PER_ROW = 32, 140, 7
local FIRST_TALENT_LEVEL, TALENT_ROW_POINTS = 10, 5
local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local DOT = "|A:levelup-dot-gold:12:12|a "
local GOLD = { 1, 0.82, 0.3 }
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
local STAT_NAMES = { L["Strength"], L["Agility"], L["Stamina"], L["Intellect"], L["Spirit"] }
local POWER_NAMES = { MANA = L["Mana"], RAGE = L["Rage"], ENERGY = L["Energy"] }

local win -- built on first use
local events = CreateFrame("Frame")
local pending, pendingSince, showQueued
local snapshot -- { level, base = { 5 base stats } }

local function Num(v)
	return type(v) == "number" and not issecret(v) and v or nil
end

local function InCombat()
	return InCombatLockdown() or UnitAffectingCombat("player")
end

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

-- The five base stats (without gear and buffs), or nil while they're secret.
local function BaseStats()
	local base = {}
	for i = 1, 5 do
		base[i] = Num((UnitStat("player", i)))
		if not base[i] then
			return nil
		end
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

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function Art(texture, atlas, r, g, b, a)
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
		texture:SetAtlas(atlas)
		return true
	end
	texture:SetColorTexture(r or GOLD[1], g or GOLD[2], b or GOLD[3], a or 1)
	return false
end

local function Circle(parent, layer, sublevel, size)
	local texture = parent:CreateTexture(nil, layer, nil, sublevel)
	texture:SetSize(size, size)
	texture:SetPoint("CENTER")
	local mask = parent:CreateMaskTexture()
	mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetSize(size, size)
	mask:SetPoint("CENTER")
	texture:AddMaskTexture(mask)
	return texture
end

-- A gold line that grows from the middle when the window opens.
local function Bar(point, y)
	local bar = win:CreateTexture(nil, "BORDER")
	if not Art(bar, "levelup-bar-gold") then
		bar:SetHeight(1)
	else
		bar:SetHeight(8)
	end
	bar:SetWidth(WIDTH + 40)
	bar:SetPoint(point, win, point, 0, y)
	bar.Grow = bar:CreateAnimationGroup()
	local grow = bar.Grow:CreateAnimation("Scale")
	grow:SetScaleFrom(0.05, 1)
	grow:SetScaleTo(1, 1)
	grow:SetDuration(0.5)
	grow:SetSmoothing("OUT")
	local dot = win:CreateTexture(nil, "ARTWORK")
	Art(dot, "levelup-dot-gold")
	dot:SetSize(18, 18)
	dot:SetPoint("CENTER", bar, "CENTER")
	return bar
end

-- A section title between two thin gold lines that fade out to the sides.
local function Section()
	local s = {}
	s.Text = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	s.Text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	s.Left = win:CreateTexture(nil, "ARTWORK")
	s.Left:SetColorTexture(1, 1, 1, 1)
	s.Left:SetGradient("HORIZONTAL", CreateColor(GOLD[1], GOLD[2], GOLD[3], 0), CreateColor(GOLD[1], GOLD[2], GOLD[3], 0.7))
	s.Left:SetSize(120, 1)
	s.Left:SetPoint("RIGHT", s.Text, "LEFT", -10, 0)
	s.Right = win:CreateTexture(nil, "ARTWORK")
	s.Right:SetColorTexture(1, 1, 1, 1)
	s.Right:SetGradient("HORIZONTAL", CreateColor(GOLD[1], GOLD[2], GOLD[3], 0.7), CreateColor(GOLD[1], GOLD[2], GOLD[3], 0))
	s.Right:SetSize(120, 1)
	s.Right:SetPoint("LEFT", s.Text, "RIGHT", 10, 0)
	function s:Place(y, text)
		self.Text:SetText(text)
		self.Text:ClearAllPoints()
		self.Text:SetPoint("TOP", win, "TOP", 0, y)
		self.Text:Show()
		self.Left:Show()
		self.Right:Show()
	end
	function s:Hide()
		self.Text:Hide()
		self.Left:Hide()
		self.Right:Hide()
	end
	return s
end

local function IconTooltip(button)
	local spell, talent = button.spell, button.talent
	if not (spell or talent) then
		return
	end
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	local spellID = spell and spell.id or talent.spellID
	if GameTooltip.SetSpellByID then
		GameTooltip:SetSpellByID(spellID)
	else
		GameTooltip:SetText(SpellName(spellID) or "?", 1, 1, 1)
	end
	if talent then
		GameTooltip:AddLine(L["Talent in %s, row %d: up to %d points"]:format(talent.tree or "?", talent.row or 0,
			talent.maxRanks or 1), GOLD[1], GOLD[2], GOLD[3])
		if talent.ranks > 0 then
			GameTooltip:AddLine(L["You have %d of them."]:format(talent.ranks), 0.3, 1, 0.3)
		end
	elseif spell.known then
		GameTooltip:AddLine(L["You know this one already."], 0.6, 0.6, 0.6)
	elseif spell.rank then
		GameTooltip:AddLine(L["Rank %d: an upgrade from your class trainer"]:format(spell.rank), 0.3, 1, 0.3)
	else
		GameTooltip:AddLine(L["New: learn it from your class trainer"], GOLD[1], GOLD[2], GOLD[3])
	end
	GameTooltip:Show()
end

local function IconButton(size)
	local b = CreateFrame("Button", nil, win)
	b:SetSize(size, size)
	b.Icon = b:CreateTexture(nil, "ARTWORK")
	b.Icon:SetAllPoints()
	b.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.Border = b:CreateTexture(nil, "OVERLAY")
	b.Border:SetTexture("Interface\\Common\\WhiteIconFrame")
	b.Border:SetAllPoints()
	b.Rank = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	b.Rank:SetPoint("BOTTOMRIGHT", -2, 2)
	b.New = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.New:SetPoint("BOTTOM", b, "TOP", 0, 1)
	b.New:SetTextColor(0.3, 1, 0.3)
	b:SetScript("OnEnter", IconTooltip)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b.Pop = b:CreateAnimationGroup()
	local grow = b.Pop:CreateAnimation("Scale")
	grow:SetScaleFrom(0.4, 0.4)
	grow:SetScaleTo(1, 1)
	grow:SetDuration(0.25)
	grow:SetSmoothing("OUT")
	b.Appear = b.Pop:CreateAnimation("Alpha")
	b.Appear:SetFromAlpha(0)
	b.Appear:SetToAlpha(1)
	b.Appear:SetDuration(0.25)
	b.Appear:SetTarget(b)
	b.Pop:SetToFinalAlpha(true)
	return b
end

-- An arrow next to the level (the spell book's page arrows): the level before or after.
local function ArrowButton(direction)
	local b = CreateFrame("Button", nil, win)
	b:SetSize(28, 28)
	local page = direction < 0 and "Prev" or "Next"
	b:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. page .. "Page-Up")
	b:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. page .. "Page-Down")
	b:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. page .. "Page-Disabled")
	b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	b:SetScript("OnClick", function() LevelUp.Browse(win.data.level + direction) end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L["What level %d brings"]:format(win.data.level + direction), 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

local Close, SetPinned

local function Build()
	win = CreateFrame("Frame", "LefthyToolsLevelUpFrame", UIParent)
	win:SetSize(WIDTH, 400)
	win:SetPoint("CENTER", 0, 40)
	win:SetFrameStrata("DIALOG")
	win:SetClampedToScreen(true)
	win:EnableMouse(true)
	win:SetMovable(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", function(self)
		SetPinned(true) -- moved somewhere: you want to keep it
		self:StartMoving()
	end)
	win:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		self:SetUserPlaced(false)
	end)
	win:Hide()
	if UISpecialFrames then
		table.insert(UISpecialFrames, "LefthyToolsLevelUpFrame") -- Escape closes it
	end
	LT.Window.Register("LefthyToolsLevelUpFrame") -- a flight pauses for it, Mirage stays up

	-- Dark, warmer towards the bottom; a soft gold glow at the top; gold bars top and bottom.
	local bg = win:CreateTexture(nil, "BACKGROUND", nil, -8)
	bg:SetAllPoints()
	bg:SetColorTexture(1, 1, 1, 1)
	bg:SetGradient("VERTICAL", CreateColor(0.10, 0.07, 0.03, 0.95), CreateColor(0.02, 0.02, 0.03, 0.95))
	local topGlow = win:CreateTexture(nil, "BACKGROUND", nil, -7)
	if Art(topGlow, "levelup-glow-gold", 1, 0.8, 0.3, 0.15) then
		topGlow:SetBlendMode("ADD")
		topGlow:SetAlpha(0.45)
	end
	topGlow:SetPoint("TOPLEFT")
	topGlow:SetPoint("TOPRIGHT")
	topGlow:SetHeight(150)
	for _, side in ipairs({ "LEFT", "RIGHT" }) do
		local edge = win:CreateTexture(nil, "BORDER")
		edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
		edge:SetWidth(1)
		edge:SetPoint("TOP" .. side)
		edge:SetPoint("BOTTOM" .. side)
	end
	win.TopBar = Bar("TOP", 4)
	win.BottomBar = Bar("BOTTOM", -4)

	win.Close = CreateFrame("Button", nil, win, "UIPanelCloseButtonNoScripts")
	win.Close:SetPoint("TOPRIGHT", -2, -6)
	win.Close:SetScript("OnClick", function() Close() end)
	-- The pin: keeps it open (also while you look around other levels).
	win.Pin = CreateFrame("Button", nil, win)
	win.Pin:SetSize(22, 22)
	win.Pin:SetPoint("RIGHT", win.Close, "LEFT", -2, 0)
	win.Pin.Icon = win.Pin:CreateTexture(nil, "ARTWORK")
	win.Pin.Icon:SetAllPoints()
	Art(win.Pin.Icon, "Waypoint-MapPin-ChatIcon", 1, 0.82, 0.3, 1)
	win.Pin:SetScript("OnClick", function() SetPinned(not win.pinned) end)
	win.Pin:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(win.pinned and L["Pinned: it stays until you close it"] or L["Pin it: it stays until you close it"], 1, 1, 1)
		GameTooltip:AddLine(L["Pinned, it steps aside during a fight and comes back after. Drag it to move it."], 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	win.Pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
	win.Tag = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	win.Tag:SetPoint("TOPLEFT", 12, -12)
	win.Tag:SetJustifyH("LEFT")
	win.Tag:SetWidth(WIDTH - 90)

	-- The portrait: round, in a gold ring, with a glow that breathes behind it.
	local face = CreateFrame("Frame", nil, win)
	win.Face = face
	face:SetSize(84, 84)
	face:SetPoint("TOP", 0, -22)
	face.Glow = face:CreateTexture(nil, "BACKGROUND")
	if Art(face.Glow, "GarrLanding-CircleGlow", 1, 0.8, 0.3, 0.2) then
		face.Glow:SetBlendMode("ADD")
		face.Glow:SetVertexColor(1, 0.8, 0.35)
	end
	face.Glow:SetSize(160, 160)
	face.Glow:SetPoint("CENTER")
	face.Breathe = face.Glow:CreateAnimationGroup()
	face.Breathe:SetLooping("BOUNCE")
	local breathe = face.Breathe:CreateAnimation("Alpha")
	breathe:SetFromAlpha(0.35)
	breathe:SetToAlpha(0.9)
	breathe:SetDuration(1.4)
	breathe:SetSmoothing("IN_OUT")
	face.Ring = Circle(face, "BORDER", 0, 84)
	face.Ring:SetColorTexture(1, 1, 1, 1)
	face.Ring:SetGradient("VERTICAL", CreateColor(0.55, 0.38, 0.12, 1), CreateColor(1, 0.88, 0.5, 1))
	face.Gap = Circle(face, "ARTWORK", 0, 78)
	face.Gap:SetColorTexture(0.05, 0.04, 0.03, 1)
	face.Portrait = Circle(face, "ARTWORK", 1, 74)

	win.LevelLabel = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	win.LevelLabel:SetPoint("TOP", face, "BOTTOM", 0, -10)
	win.LevelLabel:SetTextColor(0.9, 0.8, 0.55)

	-- The new level: big, in the quest font; it punches in and a shine sweeps over it.
	local number = CreateFrame("Frame", nil, win)
	win.NumberFrame = number
	number:SetSize(220, 70)
	number:SetPoint("TOP", win.LevelLabel, "BOTTOM", 0, 2)
	win.Number = number:CreateFontString(nil, "OVERLAY")
	win.Number:SetFont(TITLE_FONT, 64, "")
	win.Number:SetShadowOffset(2, -2)
	win.Number:SetShadowColor(0, 0, 0, 1)
	win.Number:SetTextColor(1, 0.85, 0.35)
	win.Number:SetPoint("CENTER")
	number.Punch = number:CreateAnimationGroup()
	local punch = number.Punch:CreateAnimation("Scale")
	punch:SetScaleFrom(1.9, 1.9)
	punch:SetScaleTo(1, 1)
	punch:SetDuration(0.35)
	punch:SetStartDelay(0.15)
	punch:SetSmoothing("IN")
	local show = number.Punch:CreateAnimation("Alpha")
	show:SetFromAlpha(0)
	show:SetToAlpha(1)
	show:SetDuration(0.2)
	show:SetStartDelay(0.15)
	show:SetTarget(number)
	number.Punch:SetToFinalAlpha(true)
	win.Shine = number:CreateTexture(nil, "OVERLAY")
	if Art(win.Shine, "challenges-bannershine", 1, 1, 1, 0.3) then
		win.Shine:SetBlendMode("ADD")
	end
	win.Shine:SetSize(70, 90)
	win.Shine:SetPoint("CENTER", -120, 0) -- sweeps from left to right
	win.Shine:SetAlpha(0)
	win.Shine.Sweep = win.Shine:CreateAnimationGroup()
	local move = win.Shine.Sweep:CreateAnimation("Translation")
	move:SetOffset(240, 0)
	move:SetDuration(0.9)
	move:SetStartDelay(0.6)
	local shineIn = win.Shine.Sweep:CreateAnimation("Alpha")
	shineIn:SetFromAlpha(0)
	shineIn:SetToAlpha(0.9)
	shineIn:SetDuration(0.3)
	shineIn:SetStartDelay(0.6)
	shineIn:SetTarget(win.Shine)
	local shineOut = win.Shine.Sweep:CreateAnimation("Alpha")
	shineOut:SetFromAlpha(0.9)
	shineOut:SetToAlpha(0)
	shineOut:SetDuration(0.5)
	shineOut:SetStartDelay(1.0)
	shineOut:SetTarget(win.Shine)
	win.Shine.Sweep:SetToFinalAlpha(true)
	-- Arrows on both sides of the number: other levels.
	win.Prev = ArrowButton(-1)
	win.Prev:SetPoint("RIGHT", number, "LEFT", 6, -2)
	win.Next = ArrowButton(1)
	win.Next:SetPoint("LEFT", number, "RIGHT", -6, -2)

	win.Name = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	win.Name:SetPoint("TOP", number, "BOTTOM", 0, -2)
	win.Took = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	win.Took:SetPoint("TOP", win.Name, "BOTTOM", 0, -5)
	win.Took:SetTextColor(0.7, 0.7, 0.7)

	win.StatsTitle, win.SpellsTitle, win.TalentsTitle, win.UnlockTitle = Section(), Section(), Section(), Section()
	win.Cells = {}
	for i = 1, 8 do
		local cell = {}
		cell.Label = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		cell.Label:SetJustifyH("LEFT")
		cell.Label:SetTextColor(0.85, 0.82, 0.75)
		cell.Value = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		cell.Value:SetJustifyH("RIGHT")
		win.Cells[i] = cell
	end
	win.Icons, win.TalentIcons, win.TalentLabels = {}, {}, {}
	win.SpellNote = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	win.Unlocks = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	win.Unlocks:SetJustifyH("LEFT")
	win.Unlocks:SetWidth(WIDTH - 80)
	win.Unlocks:SetSpacing(5)
	win.Friends = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")

	-- Time left before it closes by itself: a thin line that shrinks above the bottom bar.
	win.Timer = win:CreateTexture(nil, "ARTWORK")
	win.Timer:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.5)
	win.Timer:SetHeight(1)
	win.Timer:SetPoint("BOTTOM", 0, 10)

	win:SetScript("OnUpdate", function(self, elapsed) LevelUp.OnUpdate(self, elapsed) end)
	win:SetScript("OnHide", function(self) -- also Escape
		self.Face.Breathe:Stop()
		self.closing = nil
		if not self.stepAside then
			SetPinned(false) -- closed: the next one starts unpinned
		end
		self.stepAside = nil
		GameTooltip:Hide()
	end)
end

function SetPinned(on)
	if not win then
		return
	end
	win.pinned = on and true or false
	win.Pin.Icon:SetDesaturated(not win.pinned)
	win.Pin:SetAlpha(win.pinned and 1 or 0.55)
	win.Timer:SetShown(not win.pinned)
	if win.pinned then
		win.closing = nil
		win:SetAlpha(1)
	else
		win.left = HOLD
	end
end
LevelUp.SetPinned = SetPinned

---------------------------------------------------------------------------
-- Filling it in
---------------------------------------------------------------------------

local function Clock(seconds)
	seconds = math.floor(seconds + 0.5)
	local h, m, s = math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60
	if h > 0 then
		return ("%d:%02d:%02d"):format(h, m, s)
	end
	return ("%d:%02d"):format(m, s)
end

-- One stat cell's text at p (0..1) of its count-up.
local function CellText(row, p)
	local eased = 1 - (1 - p) ^ 3
	local delta = row.delta
	if row.to then
		local shown = math.floor(row.from + (row.to - row.from) * eased + 0.5)
		local text = (delta ~= 0 and "|cff9a9a9a" .. row.from .. "|r |cff777777>|r " or "") .. "|cffffffff" .. shown .. "|r"
		if delta ~= 0 and p >= 1 then
			text = text .. "  |cff4cff4c+" .. delta .. "|r"
		end
		return text
	end
	return "|cff4cff4c+" .. math.floor(delta * eased + 0.5) .. "|r"
end

local function StatRows(gains)
	local rows = {}
	if not gains then
		return rows
	end
	if gains.health and gains.health > 0 then
		rows[#rows + 1] = { label = L["Health"], delta = gains.health }
	end
	local _, token = UnitPowerType("player")
	if gains.power and gains.power > 0 and POWER_NAMES[token] then
		rows[#rows + 1] = { label = POWER_NAMES[token], delta = gains.power }
	end
	-- Each stat: old > new and the gain; just the gain while the values are secret.
	for i = 1, 5 do
		local delta = gains.stats and gains.stats[i]
		local now = Num(select(2, UnitStat("player", i)))
		if now then
			rows[#rows + 1] = { label = STAT_NAMES[i], delta = delta or 0, to = now, from = now - (delta or 0) }
		elseif delta then
			rows[#rows + 1] = { label = STAT_NAMES[i], delta = delta }
		end
	end
	return rows
end

local function UnlockLines(data)
	local lines = {}
	local talents = data.gains and data.gains.talents
	if talents and talents > 0 then
		lines[#lines + 1] = DOT .. (data.level == FIRST_TALENT_LEVEL and L["Talents unlocked: +1 talent point"]
			or talents == 1 and L["+1 talent point"] or L["+%d talent points"]:format(talents))
	end
	if data.quest then
		lines[#lines + 1] = DOT .. L["Class quest: %s"]:format("|cffffd200" .. data.quest .. "|r")
			.. "\n     |cff999999" .. L["Your class trainer can point you to it."] .. "|r"
	end
	if #data.dungeons > 0 then
		lines[#lines + 1] = DOT .. L["New dungeons: %s"]:format(table.concat(data.dungeons, ", "))
	end
	return lines
end

local function TagText(data)
	if data.browse then
		local mine = UnitLevel("player") or 0
		if data.level > mine then
			return L["Coming up: what level %d brings"]:format(data.level)
		elseif data.level < mine then
			return L["Looking back: what level %d brought"]:format(data.level)
		end
		return L["Your level"]
	elseif data.preview then
		return data.example and L["Preview, with example gains (your next level-up shows the real ones)"] or L["Preview"]
	end
	return ""
end

local function PlaceIcon(b, icon, x, y)
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", win, "TOPLEFT", x, y)
	b.Icon:SetTexture(icon)
	b:SetAlpha(0)
	b.Pop:Stop()
	b:Show()
end

local function Fill(data)
	local className, classFile = UnitClass("player")
	local race = UnitRace("player")
	local y = -22 - 84 - 10 -- below the portrait

	win.data = data
	win.Tag:SetText(TagText(data))
	SetPortraitTexture(win.Face.Portrait, "player")
	win.LevelLabel:SetText(L["LEVEL"])
	win.Number:SetText(data.level)
	win.Prev:SetEnabled(data.level > 2)
	win.Next:SetEnabled(data.level < MaxLevel())
	win.Name:SetText(LT.Window.ClassColorCode(classFile) .. (UnitName("player") or "") .. "|r  |cffbbbbbb"
		.. (race or "") .. " " .. (className or "") .. "|r")
	y = y - 14 - 68 - 22
	local report = data.report
	if report and report.took then
		local parts = { L["Level %d took %s"]:format(data.level - 1, Clock(report.took)) }
		if report.kills then
			parts[#parts + 1] = L["%d kills"]:format(report.kills)
		end
		if report.quests then
			parts[#parts + 1] = L["%d quests"]:format(report.quests)
		end
		local text = table.concat(parts, "  -  ")
		if report.fastest then
			text = text .. "  |cffffd200" .. L["Your fastest level yet!"] .. "|r"
		end
		win.Took:SetText(text)
		win.Took:Show()
		y = y - 18
	else
		win.Took:Hide()
	end

	-- Stats, two to a row (only for a level-up of yours: browsing other levels has none).
	local rows = StatRows(data.gains)
	win.rows = rows
	if #rows > 0 then
		y = y - 16
		win.StatsTitle:Place(y, L["Stats gained"])
		y = y - 24
	else
		win.StatsTitle:Hide()
	end
	for i, cell in ipairs(win.Cells) do
		local row = rows[i]
		if row then
			local x = 30 + ((i - 1) % 2) * (COLUMN + 20)
			local rowY = y - math.floor((i - 1) / 2) * 22
			cell.Label:ClearAllPoints()
			cell.Label:SetPoint("TOPLEFT", win, "TOPLEFT", x, rowY)
			cell.Label:SetText(row.label)
			cell.Value:ClearAllPoints()
			cell.Value:SetPoint("TOPRIGHT", win, "TOPLEFT", x + COLUMN, rowY)
			cell.Value:SetText(CellText(row, data.browse and 1 or 0))
			cell.Label:Show()
			cell.Value:Show()
		else
			cell.Label:Hide()
			cell.Value:Hide()
		end
	end
	y = y - math.ceil(#rows / 2) * 22 - 10

	-- Spells from the trainer.
	local popAt = 1.0
	for _, b in ipairs(win.Icons) do
		b:Hide()
		b.spell = nil
	end
	local spells = data.spells
	if #spells > 0 then
		y = y - 6
		win.SpellsTitle:Place(y, L["New at your class trainer"])
		y = y - 34 -- room for "NEW" above the icons
		local shown = math.min(#spells, MAX_ICONS)
		for i = 1, shown do
			local spell = spells[i]
			local b = win.Icons[i] or IconButton(ICON)
			win.Icons[i] = b
			local inRow = math.min(ICONS_PER_ROW, shown - math.floor((i - 1) / ICONS_PER_ROW) * ICONS_PER_ROW)
			local col = (i - 1) % ICONS_PER_ROW
			local rowWidth = inRow * ICON + (inRow - 1) * ICON_GAP
			PlaceIcon(b, spell.icon, (WIDTH - rowWidth) / 2 + col * (ICON + ICON_GAP),
				y - math.floor((i - 1) / ICONS_PER_ROW) * (ICON + 20))
			b.spell = spell
			b.Icon:SetDesaturated(spell.known)
			b.Rank:SetText(spell.rank or "")
			b.New:SetText((not spell.rank and not spell.known) and L["NEW"] or "")
			if spell.rank then
				b.Border:SetVertexColor(0.75, 0.75, 0.75)
			else
				b.Border:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
			end
			b.Appear:SetToAlpha(spell.known and 0.45 or 1)
			b.delay = popAt + i * 0.05
		end
		popAt = popAt + shown * 0.05
		y = y - math.ceil(shown / ICONS_PER_ROW) * (ICON + 20) + 10
		local allKnown = true
		for _, spell in ipairs(spells) do
			if not spell.known then
				allKnown = false
			end
		end
		local note = allKnown and L["You know these already."] or L["Learn them from your class trainer."]
		if #spells > shown then
			note = note .. " " .. L["(and %d more)"]:format(#spells - shown)
		end
		win.SpellNote:SetText(note)
		win.SpellNote:ClearAllPoints()
		win.SpellNote:SetPoint("TOP", win, "TOP", 0, y)
		win.SpellNote:Show()
		y = y - 22
	else
		win.SpellsTitle:Hide()
		win.SpellNote:Hide()
	end

	-- A new talent row: per tree, its name and the row's talents.
	for _, b in ipairs(win.TalentIcons) do
		b:Hide()
		b.talent = nil
	end
	for _, label in ipairs(win.TalentLabels) do
		label:Hide()
	end
	local talentRow = data.talentRow
	if talentRow then
		y = y - 6
		win.TalentsTitle:Place(y, talentRow.row == 1 and L["Talents unlocked"] or L["New talent row (row %d)"]:format(talentRow.row))
		y = y - 26
		local n = 0
		for g, group in ipairs(talentRow.groups) do
			local label = win.TalentLabels[g] or win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			win.TalentLabels[g] = label
			label:SetJustifyH("RIGHT")
			label:SetWidth(TALENT_X - 40)
			label:ClearAllPoints()
			label:SetPoint("RIGHT", win, "TOPLEFT", TALENT_X - 10, y - TALENT_ICON / 2)
			label:SetText((group.icon and ("|T" .. group.icon .. ":14:14|t ") or "") .. (group.name or ""))
			label:Show()
			for i, node in ipairs(group.nodes) do
				if i > TALENTS_PER_ROW then
					break
				end
				n = n + 1
				local b = win.TalentIcons[n] or IconButton(TALENT_ICON)
				win.TalentIcons[n] = b
				PlaceIcon(b, (select(2, SpellName(node.spellID))), TALENT_X + (i - 1) * (TALENT_ICON + 8), y)
				b.talent = node
				b.Icon:SetDesaturated(false)
				b.Rank:SetText(node.maxRanks > 1 and node.maxRanks or "")
				b.New:SetText("")
				b.Border:SetVertexColor(0.55, 0.85, 1)
				b.Appear:SetToAlpha(1)
				b.delay = popAt + n * 0.05
			end
			y = y - TALENT_ICON - 8
		end
		y = y - 8
	else
		win.TalentsTitle:Hide()
	end

	-- Also unlocked: talent points, a class quest, dungeons.
	local lines = UnlockLines(data)
	if #lines > 0 then
		y = y - 6
		win.UnlockTitle:Place(y, L["Also unlocked"])
		y = y - 26
		win.Unlocks:SetText(table.concat(lines, "\n"))
		win.Unlocks:ClearAllPoints()
		win.Unlocks:SetPoint("TOPLEFT", win, "TOPLEFT", 40, y)
		win.Unlocks:Show()
		y = y - win.Unlocks:GetStringHeight() - 14
	else
		win.UnlockTitle:Hide()
		win.Unlocks:Hide()
	end
	if data.browse and #spells == 0 and not talentRow and #lines == 0 then
		win.SpellNote:SetText(L["Nothing new at this level."])
		win.SpellNote:ClearAllPoints()
		win.SpellNote:SetPoint("TOP", win, "TOP", 0, y - 6)
		win.SpellNote:Show()
		y = y - 28
	end

	-- Friends at the bottom.
	if #data.friends > 0 then
		local names = {}
		for _, peer in ipairs(data.friends) do
			names[#names + 1] = LT.Window.ClassColorCode(peer.classFile) .. peer.name .. "|r |cffbbbbbb" .. peer.level .. "|r"
		end
		win.Friends:SetText("|cff999999" .. L["Friends:"] .. "|r  " .. table.concat(names, "   "))
		win.Friends:ClearAllPoints()
		win.Friends:SetPoint("TOP", win, "TOP", 0, y - 2)
		win.Friends:Show()
		y = y - 22
	else
		win.Friends:Hide()
	end
	win:SetHeight(-y + 22)
end

---------------------------------------------------------------------------
-- Showing, counting up, closing
---------------------------------------------------------------------------

-- quiet: no fade-in, gold bars or count-ups (browsing, or back after a fight).
local function Show(data, quiet)
	if not win then
		Build()
		SetPinned(false)
	end
	Fill(data)
	win.t, win.left, win.closing, win.counted, win.awayForFight = quiet and 10 or 0, HOLD, nil, false, nil
	if quiet then
		for _, b in ipairs(win.Icons) do
			b.delay = b.spell and 0 or nil
		end
		for _, b in ipairs(win.TalentIcons) do
			b.delay = b.talent and 0 or nil
		end
	else
		win:SetAlpha(0)
		win.TopBar.Grow:Play()
		win.BottomBar.Grow:Play()
		win.Shine.Sweep:Play()
	end
	win:Show()
	win.NumberFrame:SetAlpha(0)
	win.NumberFrame.Punch:Play()
	win.Face.Breathe:Play()
	LevelUp.shown = data
end

function Close(fast)
	if win and win:IsShown() and not win.closing then
		win.closing = fast and 0.01 or FADE_OUT
		win.closeTime = win.closing
	end
end
LevelUp.Close = Close

function LevelUp.OnUpdate(self, elapsed)
	self.t = self.t + elapsed
	if self.closing then
		self.closing = self.closing - elapsed
		if self.closing <= 0 then
			self:Hide()
			return
		end
		self:SetAlpha(self.closing / self.closeTime)
		return
	end
	self:SetAlpha(math.min(1, self.t / FADE_IN))
	-- Stats count up one after another; icons pop in after them.
	if not self.counted then
		local done = true
		for i, row in ipairs(self.rows) do
			local p = math.max(0, math.min(1, (self.t - COUNT_START - (i - 1) * COUNT_STAGGER) / COUNT_TIME))
			if p < 1 then
				done = false
			end
			if row.p ~= p then
				row.p = p
				self.Cells[i].Value:SetText(CellText(row, p))
			end
		end
		for _, list in ipairs({ self.Icons, self.TalentIcons }) do
			for _, b in ipairs(list) do
				if (b.spell or b.talent) and b.delay and self.t >= b.delay then
					b.delay = nil
					b.Pop:Play()
				elseif b.delay then
					done = false
				end
			end
		end
		self.counted = done
	end
	-- Pinned, or the mouse on it: it stays; otherwise it closes by itself.
	if self.pinned or self:IsMouseOver() then
		self.left = HOLD
	else
		self.left = self.left - elapsed
		if self.left <= 0 then
			Close()
		end
	end
	self.Timer:SetWidth(math.max(1, (WIDTH - 60) * self.left / HOLD))
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
	Show(data, true)
	SetPinned(true)
end

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
	Show(Collect(gains.level, gains, false))
end

local function QueueShow(delay)
	if not showQueued then
		showQueued = true
		C_Timer.After(delay, TryShow)
	end
end

-- A pinned window steps aside for a fight and comes back after it.
local function BackAfterFight()
	if win and win.awayForFight and not InCombat() and M:IsTweakActive("levelUp") and not win:IsShown() then
		Show(win.data, true)
		SetPinned(true)
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
		elseif win and win.awayForFight then
			C_Timer.After(1, BackAfterFight)
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		if win and win:IsShown() and win.pinned then
			win.awayForFight, win.stepAside = true, true
			win:Hide()
		else
			Close(true)
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		C_Timer.After(1, TakeSnapshot)
	end
end)

-- The window for your current level, from the settings: the gains of your last real level-up
-- if it was to this level, example numbers otherwise.
function LevelUp.Preview()
	if InCombat() then
		M:Print(L["Not in combat."])
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
	Show(data)
end

function ns.ApplyLevelUp(on)
	if on then
		for _, event in ipairs({ "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD" }) do
			events:RegisterEvent(event)
		end
		TakeSnapshot()
	else
		events:UnregisterAllEvents()
		pending = nil
		if win then
			win.awayForFight = nil
			win:Hide()
		end
	end
end
