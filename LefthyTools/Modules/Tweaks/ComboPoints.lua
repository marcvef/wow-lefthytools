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
local DOT_SIZE = 15  -- the nameplate gem (the display's are 20)
local DOT_DOWN = -6  -- below the level's middle: clear of the buffs and debuffs above the bar
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

-- One gem in the display's look (retail's uf-roguecp-* atlases: a shadow, the lit socket, the gem
-- and, when coloured, the additive copy that keeps the tint bright), smaller. Without those
-- atlases: a plain round dot.
local function BuildDot()
	dot = CreateFrame("Frame")
	dot:SetSize(DOT_SIZE, DOT_SIZE)
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(GEM_ATLAS) then
		dot.Shadow = dot:CreateTexture(nil, "BACKGROUND", nil, 0)
		dot.Shadow:SetAtlas("uf-roguecp-bg-shadow")
		dot.Shadow:SetSize(DOT_SIZE, DOT_SIZE)
		dot.Shadow:SetPoint("CENTER", 0, -3)
		dot.Socket = dot:CreateTexture(nil, "BACKGROUND", nil, 2)
		dot.Socket:SetAtlas("uf-roguecp-bg")
		dot.Socket:SetAllPoints()
		dot.Gem = dot:CreateTexture(nil, "ARTWORK", nil, 1)
		dot.Gem:SetAtlas(GEM_ATLAS)
		dot.Gem:SetAllPoints()
		dot.Boost = dot:CreateTexture(nil, "ARTWORK", nil, 2)
		dot.Boost:SetAtlas(GEM_ATLAS)
		dot.Boost:SetAllPoints()
		dot.Boost:SetBlendMode("ADD")
		dot.Boost:SetDesaturated(true)
	else
		dot.Gem = dot:CreateTexture(nil, "ARTWORK")
		dot.Gem:SetAllPoints()
		local mask = dot:CreateMaskTexture()
		mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints()
		dot.Gem:AddMaskTexture(mask)
		dot.round = true
	end
	dot.Number = dot:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	dot.Number:SetPoint("LEFT", dot, "TOPRIGHT", -3, -2) -- like a footnote
	dot:Hide()
end

-- The gem in a colour (r == nil: Blizzard's red), tinted like the display's (Recolor).
local function StyleDot(r, g, b)
	if dot.round then
		dot.Gem:SetColorTexture(r or RED[1], g or RED[2], b or RED[3], 1)
		return
	end
	local tinted = r ~= nil
	for _, texture in ipairs({ dot.Gem, dot.Socket }) do
		texture:SetDesaturated(tinted)
		local lift = tinted and 0.25 or 0
		texture:SetVertexColor((r or 1) + (1 - (r or 1)) * lift, (g or 1) + (1 - (g or 1)) * lift, (b or 1) + (1 - (b or 1)) * lift)
	end
	dot.Boost:SetVertexColor(r or 1, g or 1, b or 1)
	dot.Boost:SetShown(tinted)
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

local function UpdateDot()
	local points = onNameplate and CurrentPoints()
	local plate = points and points > 0 and TargetPlate()
	if not plate then
		if dot then
			dot:Hide()
		end
		return
	end
	if not dot then
		BuildDot()
	end
	local level = plate.PlayerLevelDiffFrame
	local ok = pcall(function()
		if dot:GetParent() ~= plate then
			dot:SetParent(plate)
		end
		dot:ClearAllPoints()
		if level and level:IsShown() then
			dot:SetPoint("LEFT", level, "RIGHT", 2, DOT_DOWN)
		else
			dot:SetPoint("LEFT", plate.HealthBarsContainer or plate, "RIGHT", 3, DOT_DOWN)
		end
		dot:SetFrameLevel(plate:GetFrameLevel() + 60) -- (over the level frame: 50)
	end)
	if not ok then
		dot:Hide()
		return
	end
	if colorByCount then
		StyleDot(CountColor(points, MaxPoints()))
	else
		StyleDot(nil)
	end
	dot.Number:SetText(points)
	dot:Show()
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

-- For tests.
function ns.GetComboDot()
	return dot
end
