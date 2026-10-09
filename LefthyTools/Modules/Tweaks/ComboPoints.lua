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
--   * A dot on your target's nameplate (comboNameplate), right of the mob's level: one round dot
--     in the colour of the count (red with colouring off) and the number small at its corner.
--     Only while you have points on that target. It's our own frame, put on the nameplate (it
--     shows, fades and scales with it) and found again whenever the target or the nameplates change.
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
local DOT_SIZE = 10
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

local function BuildDot()
	dot = CreateFrame("Frame")
	dot:SetSize(DOT_SIZE, DOT_SIZE)
	dot.Body = dot:CreateTexture(nil, "ARTWORK")
	dot.Body:SetAllPoints()
	local mask = dot:CreateMaskTexture()
	mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints()
	dot.Body:AddMaskTexture(mask)
	dot.Number = dot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	dot.Number:SetPoint("BOTTOMLEFT", dot, "TOPRIGHT", -3, -5) -- like a footnote
	dot.Number:SetTextScale(0.8)
	dot.Number:SetShadowOffset(1, -1)
	dot:Hide()
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
			dot:SetPoint("LEFT", level, "RIGHT", 3, 0)
		else
			dot:SetPoint("LEFT", plate.HealthBarsContainer or plate, "RIGHT", 4, 0)
		end
		dot:SetFrameLevel(plate:GetFrameLevel() + 60) -- (over the level frame: 50)
	end)
	if not ok then
		dot:Hide()
		return
	end
	local r, g, b = RED[1], RED[2], RED[3]
	if colorByCount then
		r, g, b = CountColor(points, MaxPoints())
	end
	dot.Body:SetColorTexture(r, g, b, 1)
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
