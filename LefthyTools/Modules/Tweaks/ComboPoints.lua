local _, ns = ...

-- Misc Tweaks 4: combo points.
--
-- Blizzard's personal resource display shows combo points now: Forever's Camelot override of
-- GetClassFrameInfo builds retail's RogueComboPointBarTemplate (rogues) and
-- DruidComboPointBarTemplate (druids in Cat Form), bound to the target like Classic
-- (TargetBoundComboPointBarMixin: GetComboPoints("player", "target")). LefthyTools adds:
--
--   * Colour by count (comboColors): Blizzard's lit gems and their effects, green with one point,
--     through yellow, to red at full. A post-hook on the bar's UpdatePower (Blizzard has drawn the
--     points by then) tints them; the empty sockets and the shadow keep their look. The art is red,
--     so the tinted parts are desaturated first; a desaturated red gem is dark grey, so tinting
--     alone looked muted: an additive copy of each gem in the same colour (our own texture on the
--     point, its alpha following Blizzard's gem through the animations) keeps it bright.
--   * A gem on your target's nameplate (comboNameplate), right of the mob's level and a little
--     below it (clear of the buffs and debuffs): one gem in the display's own look, tinted like
--     it (Blizzard's red with colouring off), and the number small at its corner. Only while you
--     have points on that target. It's our own frame, put on the nameplate (it shows, fades and
--     scales with it) and found again whenever the target or the nameplates change.
--
-- Nothing of Blizzard's is replaced; the only hooks are hooksecurefunc post-hooks. Updates run on
-- the next frame, never inside an event.

local TINTED = { "BGActive", "BGGlow", "IconUncharged", "FXUncharged", "FrameGlow", "SlashFBUncharged" }
local ADDITIVE_WHEN_TINTED = { BGGlow = true, FXUncharged = true, FrameGlow = true, SlashFBUncharged = true }
-- The plain gem and the lit socket get a tint lifted towards white; the additive copy and the
-- effects keep the full colour, so the hue stays strong.
local LIGHTEN = { IconUncharged = 0.25, BGActive = 0.25 }
local GEM_ATLAS = "uf-roguecp-icon-red"
local FOLLOW_TIME = 1 -- seconds the copies follow Blizzard's gems after a change (its animations are shorter)
local GREEN, YELLOW, RED = { 0.15, 1, 0.15 }, { 1, 0.9, 0 }, { 1, 0.1, 0.05 }
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local DOT_SIZE = 12  -- the nameplate gem's default size (the display's are 20); a slider changes it
local DOT_DOWN = -6  -- default: below the level's middle, clear of the buffs and debuffs above the bar
local issecret = issecretvalue or function() return false end

local colorByCount = false -- switched by Tweaks.lua (ns.ApplyComboColors), on by default
local onNameplate = false  -- ns.ApplyComboNameplate, on by default
local hooked = {}          -- Blizzard frames already post-hooked
local followUntil = 0
local driver = CreateFrame("Frame")
local events = CreateFrame("Frame")
local dot -- the nameplate dot, built on first use

local function CountColor(points, count)
	local t = count > 1 and (points - 1) / (count - 1) or 1
	t = math.max(0, math.min(1, t))
	local from, to, f = GREEN, YELLOW, t * 2
	if t > 0.5 then
		from, to, f = YELLOW, RED, (t - 0.5) * 2
	end
	return from[1] + (to[1] - from[1]) * f, from[2] + (to[2] - from[2]) * f, from[3] + (to[3] - from[3]) * f
end

-- nil when the game keeps them secret.
local function CurrentPoints()
	local points = GetComboPoints("player", "target")
	if issecret(points) then
		return nil
	end
	return points or 0
end

local function MaxPoints()
	local comboPoints = Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4
	local max = UnitPowerMax("player", comboPoints)
	if issecret(max) or not max or max < 1 then
		max = 5
	end
	return max
end

---------------------------------------------------------------------------
-- Colouring Blizzard's combo points
---------------------------------------------------------------------------

local function Bar()
	local display = PersonalResourceDisplayFrame
	return display and display.classFrame
end

-- r == nil: Blizzard's own colours.
local function TintPoint(point, r, g, b)
	local tinted = r ~= nil
	for _, key in ipairs(TINTED) do
		local texture = point[key]
		if texture then
			texture:SetDesaturated(tinted)
			local lift = tinted and LIGHTEN[key] or 0
			texture:SetVertexColor((r or 1) + (1 - (r or 1)) * lift, (g or 1) + (1 - (g or 1)) * lift, (b or 1) + (1 - (b or 1)) * lift)
			if ADDITIVE_WHEN_TINTED[key] then
				texture:SetBlendMode(tinted and "ADD" or "BLEND")
			end
		end
	end
	local gem = point.IconUncharged
	if tinted and gem and not point.LefthyToolsBoost then
		local boost = point:CreateTexture(nil, "ARTWORK", nil, 7)
		boost:SetAtlas(GEM_ATLAS, true)
		boost:SetAllPoints(gem)
		boost:SetBlendMode("ADD")
		boost:SetDesaturated(true)
		point.LefthyToolsBoost = boost
	end
	if point.LefthyToolsBoost then
		point.LefthyToolsBoost:SetVertexColor(r or 1, g or 1, b or 1)
		point.LefthyToolsBoost:SetShown(tinted) -- retail's own red needs no boost
	end
end

-- The copies follow Blizzard's gems (their alpha, through the gain and spend animations).
local function Follow()
	local bar = Bar()
	for _, point in ipairs(bar and bar.classResourceButtonTable or {}) do
		local boost, gem = point.LefthyToolsBoost, point.IconUncharged
		if boost and gem and boost:IsShown() then
			local ok, alpha = pcall(gem.GetAlpha, gem)
			boost:SetAlpha(ok and not issecret(alpha) and alpha or 0)
		end
	end
end

local function Recolor()
	local bar = Bar()
	local points = CurrentPoints()
	if not (bar and bar.classResourceButtonTable and points) then
		return
	end
	-- At 0 points the gems keep their colour while they burst out.
	if points > 0 or not colorByCount then
		local r, g, b
		if colorByCount then
			r, g, b = CountColor(points, #bar.classResourceButtonTable)
		end
		for _, point in ipairs(bar.classResourceButtonTable) do
			TintPoint(point, r, g, b)
		end
	end
	followUntil = GetTime() + FOLLOW_TIME
	driver:Show()
end

-- Blizzard's bar, once it exists (the display builds it in SetupClassBar): recoloured after each
-- of its own updates.
local function Attach()
	local display = PersonalResourceDisplayFrame
	if display and display.SetupClassBar and not hooked[display] then
		hooked[display] = true
		hooksecurefunc(display, "SetupClassBar", Attach)
	end
	local bar = Bar()
	if bar and bar.UpdatePower and not hooked[bar] then
		hooked[bar] = true
		hooksecurefunc(bar, "UpdatePower", function()
			if colorByCount or bar.lefthyTinted then
				bar.lefthyTinted = colorByCount
				Recolor()
			end
		end)
	end
	if bar then
		bar.lefthyTinted = colorByCount
		Recolor()
	end
end

---------------------------------------------------------------------------
-- The dot on your target's nameplate
---------------------------------------------------------------------------

-- One gem in the display's own look. Copied from a point of Blizzard's bar when the display has one
-- (every base layer it draws: its atlases, layers, sizes and offsets, the socket with its border
-- included; not the effects, glows and slashes, nor the blue charged gem); otherwise retail's
-- RogueComboPointTemplate layers below. Sizes and offsets are kept as parts of the point's size, so
-- the gem scales to the chosen size. Without those atlases at all: a plain round dot.
local PARTS = {
	{ key = "BGShadow", atlas = "uf-roguecp-bg-shadow", layer = "BACKGROUND", sub = 0, w = 1, h = 1, x = 0, y = -0.15 },
	{ key = "BGInactive", atlas = "uf-roguecp-bg-dis", layer = "BACKGROUND", sub = 1, w = 1, h = 1, x = 0, y = 0 },
	{ key = "BGActive", atlas = "uf-roguecp-bg", layer = "BACKGROUND", sub = 2, w = 1, h = 1, x = 0, y = 0 },
	{ key = "IconUncharged", atlas = GEM_ATLAS, layer = "ARTWORK", sub = 1, w = 1, h = 1, x = 0, y = 0 },
}
local SKIP = { "FX", "Slash", "Glow", "Boost", "LefthyTools", "Charged" }

local function KeyOf(point, region)
	for key, value in pairs(point) do
		if value == region and type(key) == "string" then
			return key
		end
	end
end

local function Skipped(key)
	for _, word in ipairs(SKIP) do
		if key:find(word, 1, true) and not (word == "Charged" and key:find("Uncharged", 1, true)) then
			return true
		end
	end
	return false
end

-- The base layers of a point on Blizzard's bar, as parts of its size; nil without one.
local function PartsFromDisplay()
	local bar = Bar()
	local point = bar and bar.classResourceButtonTable and bar.classResourceButtonTable[1]
	if not (point and point.GetRegions) then
		return nil
	end
	local ok, pw, ph = pcall(point.GetSize, point)
	if not ok or issecret(pw) or issecret(ph) or not pw or pw <= 0 or not ph or ph <= 0 then
		return nil
	end
	local parts = {}
	for _, region in ipairs({ point:GetRegions() }) do
		local key = region.GetObjectType and region:GetObjectType() == "Texture" and KeyOf(point, region)
		local atlas = key and not Skipped(key) and region.GetAtlas and region:GetAtlas()
		if atlas and not issecret(atlas) then
			local layer, sub = region:GetDrawLayer()
			local okSize, w, h = pcall(region.GetSize, region)
			local anchor, _, _, x, y = region:GetPoint(1)
			if okSize and not issecret(w) and w and w > 0 and h and h > 0 then
				local centred = anchor == "CENTER" and not issecret(x)
				parts[#parts + 1] = { key = key, atlas = atlas, layer = layer or "ARTWORK", sub = sub or 0, w = w / pw, h = h / ph,
					x = centred and (x or 0) / pw or 0, y = centred and (y or 0) / ph or 0 }
			end
		end
	end
	return #parts > 0 and parts or nil
end

-- A gem's textures for a list of parts (reused by key; ones not in the list hidden).
local function LayGem(gem, parts, fromDisplay)
	gem.parts = gem.parts or {}
	for _, texture in pairs(gem.parts) do
		texture:Hide()
	end
	for _, part in ipairs(parts) do
		local texture = gem.parts[part.key]
		if not texture then
			texture = gem:CreateTexture(nil, part.layer, nil, part.sub)
			gem.parts[part.key] = texture
		end
		texture:SetDrawLayer(part.layer, part.sub)
		texture:SetAtlas(part.atlas)
		texture.part = part
		texture:Show()
	end
	gem.Gem, gem.Socket = gem.parts.IconUncharged, gem.parts.BGActive
	if gem.Gem and not gem.Boost then
		gem.Boost = gem:CreateTexture(nil, "ARTWORK", nil, 7)
		gem.Boost:SetAtlas(GEM_ATLAS)
		gem.Boost:SetBlendMode("ADD")
		gem.Boost:SetDesaturated(true)
	end
	gem.fromDisplay = fromDisplay
end

-- The display's look, if the display has come since the gem was built.
local function RelayGem(gem)
	if not gem.fromDisplay and not gem.round then
		local fromDisplay = PartsFromDisplay()
		if fromDisplay then
			LayGem(gem, fromDisplay, true)
		end
	end
end

-- Size and place every part (size: the gem's in pixels).
local function SizeGem(gem, size)
	gem:SetSize(size, size)
	for _, texture in pairs(gem.parts or {}) do
		local part = texture.part
		texture:ClearAllPoints()
		texture:SetSize(size * part.w, size * part.h)
		texture:SetPoint("CENTER", gem, "CENTER", size * part.x, size * part.y)
	end
	if gem.Boost and gem.Gem then
		gem.Boost:ClearAllPoints()
		gem.Boost:SetAllPoints(gem.Gem)
	end
	if gem.round then
		gem.Gem:SetAllPoints()
	end
end

-- A gem with its number (the nameplate's, and the trial mode's below).
local function NewGem(parent)
	local gem = CreateFrame("Frame", nil, parent)
	gem:SetSize(DOT_SIZE, DOT_SIZE)
	local fromDisplay = PartsFromDisplay()
	if fromDisplay then
		LayGem(gem, fromDisplay, true)
	elseif C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(GEM_ATLAS) then
		LayGem(gem, PARTS, false)
	else
		gem.Gem = gem:CreateTexture(nil, "ARTWORK")
		gem.Gem:SetAllPoints()
		local mask = gem:CreateMaskTexture()
		mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints()
		gem.Gem:AddMaskTexture(mask)
		gem.round = true
	end
	gem.Number = gem:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	gem.Number:SetPoint("LEFT", gem, "TOPRIGHT", -2, -2) -- like a footnote
	return gem
end

local function BuildDot()
	dot = NewGem()
	dot:Hide()
end

-- A gem in a colour (r == nil: Blizzard's red), tinted like the display's (Recolor).
local function StyleGem(gem, r, g, b)
	if gem.round then
		gem.Gem:SetColorTexture(r or RED[1], g or RED[2], b or RED[3], 1)
		return
	end
	local tinted = r ~= nil
	for _, texture in ipairs({ gem.Gem, gem.Socket }) do
		texture:SetDesaturated(tinted)
		local lift = tinted and 0.25 or 0
		texture:SetVertexColor((r or 1) + (1 - (r or 1)) * lift, (g or 1) + (1 - (g or 1)) * lift, (b or 1) + (1 - (b or 1)) * lift)
	end
	if gem.Boost then
		gem.Boost:SetVertexColor(r or 1, g or 1, b or 1)
		gem.Boost:SetShown(tinted)
	end
end

-- The colour for some points (Blizzard's red with colouring off).
local function StyleFor(gem, points)
	if colorByCount then
		StyleGem(gem, CountColor(points, MaxPoints()))
	else
		StyleGem(gem, nil)
	end
end

-- The nameplate of your target (its unit frame), if it has one addons may touch.
local function TargetPlate()
	if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
		return nil
	end
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, "target")
	if not ok or not plate or issecret(plate) or (plate.IsForbidden and plate:IsForbidden()) then
		return nil
	end
	return plate.UnitFrame
end

-- Where and how big (Misc Tweaks' sliders): x, y from the spot right of the level, size in pixels.
local function Placement()
	local tweaks = ns.LT:GetModule("tweaks")
	local db = tweaks and tweaks.db or {}
	return tonumber(db.comboNameplateX) or 2, tonumber(db.comboNameplateY) or DOT_DOWN, tonumber(db.comboNameplateSize) or DOT_SIZE
end

local previewUntil = 0 -- the sliders moved: shown a while on the target, also without points

local function UpdateDot()
	local points = onNameplate and CurrentPoints()
	if points == 0 and onNameplate and GetTime() < previewUntil then
		points = MaxPoints()
	end
	local plate = points and points > 0 and TargetPlate()
	if not plate then
		if dot then
			dot:Hide()
		end
		return
	end
	if not dot then
		BuildDot()
	else
		RelayGem(dot) -- (the display's bar came after the gem was built)
	end
	local x, y, size = Placement()
	SizeGem(dot, size)
	local level = plate.PlayerLevelDiffFrame
	local ok = pcall(function()
		if dot:GetParent() ~= plate then
			dot:SetParent(plate)
		end
		dot:ClearAllPoints()
		if level and level:IsShown() then
			dot:SetPoint("LEFT", level, "RIGHT", x, y)
		else
			dot:SetPoint("LEFT", plate.HealthBarsContainer or plate, "RIGHT", x + 1, y)
		end
		dot:SetFrameLevel(plate:GetFrameLevel() + 60) -- (over the level frame: 50)
	end)
	if not ok then
		dot:Hide()
		return
	end
	StyleFor(dot, points)
	dot.Number:SetText(points)
	dot:Show()
end

---------------------------------------------------------------------------
-- Trial mode: placing the gem without a mob and without the settings open (Misc Tweaks' button,
-- /lefthy tweaks combopos). A small window with a stand-in nameplate (at your target's nameplate's
-- scale and level box size when you have one): drag the gem, the mouse wheel over it sizes it,
-- arrow and +/- buttons nudge it a pixel (controllers too). Saved on release, through the
-- settings (an open settings page shows it); your target's nameplate shows the gem meanwhile.
---------------------------------------------------------------------------

local trial
local X_RANGE, Y_RANGE, SIZE_MIN, SIZE_MAX = 60, 40, 6, 30

local function Clamp(v, lo, hi)
	return math.max(lo, math.min(hi, math.floor(v + 0.5)))
end

local function Save(key, value)
	local tweaks = ns.LT:GetModule("tweaks")
	if tweaks and tweaks.db and tweaks.db[key] ~= value then
		ns.LT:SetModuleSetting(tweaks, key, value) -- (the settings page and your target's gem follow)
	end
end

-- The stand-in at your target's nameplate's scale, its level box as big as the real one.
local function MatchPlate()
	local plate = TargetPlate()
	local okScale, scale = false, nil
	if plate then
		okScale, scale = pcall(plate.GetEffectiveScale, plate)
	end
	local mine = trial:GetEffectiveScale()
	if okScale and type(scale) == "number" and not issecret(scale) and scale > 0 and mine > 0 then
		trial.Plate:SetScale(scale / mine)
	else
		trial.Plate:SetScale(1)
	end
	local level = plate and plate.PlayerLevelDiffFrame
	if level then
		local ok, w, h = pcall(level.GetSize, level)
		if ok and type(w) == "number" and not issecret(w) and w > 0 and h > 0 then
			trial.Level:SetSize(w, h)
		end
	end
end

-- The gem where x, y and size say (nil: the saved ones).
local function TrialLayout(x, y, size)
	local savedX, savedY, savedSize = Placement()
	x, y, size = x or savedX, y or savedY, size or savedSize
	RelayGem(trial.Gem)
	SizeGem(trial.Gem, size)
	trial.Gem:ClearAllPoints()
	trial.Gem:SetPoint("LEFT", trial.Level, "RIGHT", x, y)
	StyleFor(trial.Gem, MaxPoints())
	trial.Gem.Number:SetText(MaxPoints())
	trial.Values:SetText(ns.L["Right %d, up %d, size %d"]:format(x, y, size))
end

local function Nudge(dx, dy, dsize)
	local x, y, size = Placement()
	Save("comboNameplateX", Clamp(x + dx, -X_RANGE, X_RANGE))
	Save("comboNameplateY", Clamp(y + dy, -Y_RANGE, Y_RANGE))
	Save("comboNameplateSize", Clamp(size + dsize, SIZE_MIN, SIZE_MAX))
	MatchPlate()
	TrialLayout()
end

local function DragUpdate(gem)
	local cx, cy = GetCursorPosition()
	local scale = trial.Plate:GetEffectiveScale()
	gem.dragX = Clamp(gem.fromX + (cx - gem.startX) / scale, -X_RANGE, X_RANGE)
	gem.dragY = Clamp(gem.fromY + (cy - gem.startY) / scale, -Y_RANGE, Y_RANGE)
	TrialLayout(gem.dragX, gem.dragY)
end

local function ArrowButton(texture, size, dx, dy, dsize, x)
	local button = CreateFrame("Button", nil, trial)
	button:SetSize(size, size)
	button:SetNormalTexture(texture)
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button:SetPoint("BOTTOMLEFT", trial, "BOTTOMLEFT", x, 12)
	button:SetScript("OnClick", function() Nudge(dx, dy, dsize) end)
	return button
end

local function BuildTrial()
	trial = CreateFrame("Frame", "LefthyToolsComboTrial", UIParent)
	trial:SetSize(330, 210)
	trial:SetPoint("CENTER", 0, 140)
	trial:SetFrameStrata("FULLSCREEN_DIALOG") -- (above the settings, if they're open)
	trial:SetClampedToScreen(true)
	trial:EnableMouse(true)
	trial:SetMovable(true)
	trial:RegisterForDrag("LeftButton")
	trial:SetScript("OnDragStart", trial.StartMoving)
	trial:SetScript("OnDragStop", trial.StopMovingOrSizing)
	local bg = trial:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.04, 0.05, 0.07, 0.94)
	local edge = trial:CreateTexture(nil, "BORDER")
	edge:SetPoint("TOPLEFT")
	edge:SetPoint("TOPRIGHT")
	edge:SetHeight(1)
	edge:SetColorTexture(1, 0.82, 0, 0.5)
	trial.Title = trial:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	trial.Title:SetPoint("TOP", 0, -10)
	trial.Title:SetText(ns.L["Place the combo point gem"])
	trial.Hint = trial:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	trial.Hint:SetPoint("TOP", trial.Title, "BOTTOM", 0, -6)
	trial.Hint:SetWidth(300)
	trial.Hint:SetText(ns.L["Drag the gem; the mouse wheel over it changes its size. Your target's nameplate shows it too."])
	-- The stand-in nameplate: a name, a health bar and the level box right of it.
	trial.Plate = CreateFrame("Frame", nil, trial)
	trial.Plate:SetSize(1, 1)
	trial.Plate:SetPoint("CENTER", -20, 4)
	local bar = trial.Plate:CreateTexture(nil, "ARTWORK")
	bar:SetSize(120, 10)
	bar:SetPoint("CENTER")
	bar:SetColorTexture(0.75, 0.12, 0.1, 1)
	local barBack = trial.Plate:CreateTexture(nil, "BACKGROUND")
	barBack:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
	barBack:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
	barBack:SetColorTexture(0, 0, 0, 1)
	local name = trial.Plate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	name:SetPoint("BOTTOM", bar, "TOP", 0, 3)
	name:SetText(ns.L["Training Dummy"])
	trial.Level = CreateFrame("Frame", nil, trial.Plate)
	trial.Level:SetSize(18, 14)
	trial.Level:SetPoint("LEFT", bar, "RIGHT", 2, 0)
	local levelText = trial.Level:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	levelText:SetPoint("CENTER")
	levelText:SetText("60")
	trial.Gem = NewGem(trial.Plate)
	trial.Gem:SetFrameLevel(trial.Plate:GetFrameLevel() + 5)
	trial.Gem:EnableMouse(true)
	trial.Gem:EnableMouseWheel(true)
	trial.Gem:SetScript("OnMouseDown", function(gem, button)
		if button == "LeftButton" then
			gem.startX, gem.startY = GetCursorPosition()
			gem.fromX, gem.fromY = Placement()
			gem.dragX, gem.dragY = gem.fromX, gem.fromY
			gem:SetScript("OnUpdate", DragUpdate)
		end
	end)
	trial.Gem:SetScript("OnMouseUp", function(gem)
		if gem:GetScript("OnUpdate") then
			gem:SetScript("OnUpdate", nil)
			Save("comboNameplateX", gem.dragX)
			Save("comboNameplateY", gem.dragY)
			TrialLayout()
		end
	end)
	trial.Gem:SetScript("OnMouseWheel", function(_, delta) Nudge(0, 0, delta > 0 and 1 or -1) end)
	trial.Values = trial:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	trial.Values:SetPoint("BOTTOM", 0, 44)
	-- Nudges: left, right, up, down, smaller, bigger; then Reset and Done.
	trial.Left = ArrowButton("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up", 26, -1, 0, 0, 10)
	trial.Right = ArrowButton("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up", 26, 1, 0, 0, 36)
	trial.Up = ArrowButton("Interface\\Buttons\\Arrow-Up-Up", 22, 0, 1, 0, 66)
	trial.Down = ArrowButton("Interface\\Buttons\\Arrow-Down-Up", 22, 0, -1, 0, 90)
	trial.Smaller = ArrowButton("Interface\\Buttons\\UI-MinusButton-Up", 18, 0, 0, -1, 122)
	trial.Bigger = ArrowButton("Interface\\Buttons\\UI-PlusButton-Up", 18, 0, 0, 1, 144)
	trial.Reset = CreateFrame("Button", nil, trial, "UIPanelButtonTemplate")
	trial.Reset:SetSize(70, 22)
	trial.Reset:SetPoint("BOTTOMRIGHT", -88, 10)
	trial.Reset:SetText(ns.L["Reset"])
	trial.Reset:SetScript("OnClick", function()
		Save("comboNameplateX", 2)
		Save("comboNameplateY", DOT_DOWN)
		Save("comboNameplateSize", DOT_SIZE)
		TrialLayout()
	end)
	trial.Done = CreateFrame("Button", nil, trial, "UIPanelButtonTemplate")
	trial.Done:SetSize(70, 22)
	trial.Done:SetPoint("BOTTOMRIGHT", -12, 10)
	trial.Done:SetText(ns.L["Done"])
	trial.Done:SetScript("OnClick", function() trial:Hide() end)
	trial:SetScript("OnShow", function()
		previewUntil = math.huge -- (your target's nameplate shows the gem while placing it)
		MatchPlate()
		TrialLayout()
		UpdateDot()
	end)
	trial:SetScript("OnHide", function()
		trial.Gem:SetScript("OnUpdate", nil)
		previewUntil = 0
		UpdateDot()
	end)
	trial:Hide()
	if UISpecialFrames then
		table.insert(UISpecialFrames, "LefthyToolsComboTrial") -- Escape closes it
	end
end

-- Opens (or closes) the trial mode.
function ns.ComboTrial(on)
	if on == nil then
		on = not (trial and trial:IsShown())
	end
	if on and not trial then
		BuildTrial()
	end
	if trial and on then
		trial:Show()
	elseif trial then
		trial:Hide()
	end
end

function ns.GetComboTrial()
	return trial
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local pending = false
driver:Hide()
driver:SetScript("OnUpdate", function(self)
	if pending then
		pending = false
		Attach()
		UpdateDot()
	end
	Follow()
	if GetTime() >= followUntil then
		self:Hide()
	end
end)

local function Soon()
	pending = true
	driver:Show()
end

events:SetScript("OnEvent", function(_, event, unit, powerToken)
	if event == "UNIT_POWER_FREQUENT" and powerToken ~= "COMBO_POINTS" then
		return -- energy ticks come through here too
	elseif event == "ADDON_LOADED" and unit ~= "Blizzard_PersonalResourceDisplay" then
		return
	end
	Soon()
end)

local function Listen()
	events:UnregisterAllEvents()
	if not (colorByCount or onNameplate) then
		return
	end
	for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD", "ADDON_LOADED", "NAME_PLATE_UNIT_ADDED",
		"NAME_PLATE_UNIT_REMOVED", "COMBO_TARGET_CHANGED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	for _, event in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do
		pcall(events.RegisterUnitEvent, events, event, "player")
	end
end

-- Called by Tweaks.lua when a switch changes (on the next frame, never in a callback).
function ns.ApplyComboColors(on)
	colorByCount = on
	Listen()
	Attach() -- (off: Blizzard's colours back)
	UpdateDot()
end

function ns.ApplyComboNameplate(on)
	onNameplate = on
	Listen()
	UpdateDot()
end

-- The position or size sliders moved: the gem shows on your target for a few seconds (full points
-- if you have none), so you see where it goes.
function ns.PreviewComboNameplate()
	previewUntil = math.max(previewUntil, GetTime() + 5) -- (the trial mode's lasts while it's open)
	UpdateDot()
	C_Timer.After(5.1, UpdateDot)
end

-- For tests.
function ns.GetComboDot()
	return dot
end
