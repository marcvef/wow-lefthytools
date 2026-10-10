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
--   * Dots on your target's nameplate (comboNameplate): small round dots set into the bottom edge
--     of its health bar, one per point the bar can hold. Lit ones take the colour of the count
--     (Blizzard's red with colouring off), the rest are dark, empty sockets; each sits on a dark
--     ring, so it reads on a red bar too. They take no room of their own: nothing above the bar
--     (buffs, debuffs) or beside it (the level) is touched. Only while you have points on that
--     target. Our own frame, put on the nameplate (it shows, fades and scales with it) and found
--     again whenever the target, the points or the target's nameplate change.
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
local DOT_SIZE = 6   -- default: each dot's size in pixels, its dark ring included (comboDotSize)
local SIZE_MIN, SIZE_MAX = 4, 12
local DOT_INSET = 1  -- the dots' bottom, this far above the bar's bottom edge
local issecret = issecretvalue or function() return false end

local colorByCount = false -- switched by Tweaks.lua (ns.ApplyComboColors), on by default
local onNameplate = false  -- ns.ApplyComboNameplate, on by default
local hooked = {}          -- Blizzard frames already post-hooked
local followUntil = 0
local driver = CreateFrame("Frame")
local events = CreateFrame("Frame")
local row -- the dots on the target's nameplate, built on first use

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
	return math.min(max, 10)
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

-- animating: Blizzard just updated its points (their animations run): the copies follow a while.
local function Recolor(animating)
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
	Follow()
	if animating then
		followUntil = GetTime() + FOLLOW_TIME
		driver:Show()
	end
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
				Recolor(true)
			end
		end)
	end
	if bar then
		bar.lefthyTinted = colorByCount
		Recolor(false)
	end
end

---------------------------------------------------------------------------
-- The dots on your target's nameplate
---------------------------------------------------------------------------

-- A round texture: a colour through a round mask (like Beacon's map dots).
local function Round(frame, sublevel)
	local texture = frame:CreateTexture(nil, "ARTWORK", nil, sublevel)
	local mask = frame:CreateMaskTexture()
	mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(texture)
	texture:AddMaskTexture(mask)
	return texture
end

local function NewRow(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame.dots = {}
	frame:Hide()
	return frame
end

-- The colour of lit dots for some points (Blizzard's red with colouring off).
local function DotColor(points)
	if colorByCount then
		return CountColor(points, MaxPoints())
	end
	return RED[1], RED[2], RED[3]
end

-- count dots of size pixels in a row, the first `points` lit.
local function LayRow(frame, count, points, size)
	local gap = math.max(2, math.floor(size * 0.5 + 0.5))
	local inner = math.max(2, size - 2)
	local r, g, b = DotColor(math.max(points, 1))
	frame:SetSize(count * size + (count - 1) * gap, size)
	for i = 1, math.max(count, #frame.dots) do
		local dot = frame.dots[i]
		if i <= count then
			if not dot then
				dot = { Ring = Round(frame, 1), Fill = Round(frame, 2) }
				frame.dots[i] = dot
			end
			dot.Ring:ClearAllPoints()
			dot.Ring:SetPoint("LEFT", frame, "LEFT", (i - 1) * (size + gap), 0)
			dot.Ring:SetSize(size, size)
			dot.Ring:SetColorTexture(0, 0, 0, 0.85)
			dot.Fill:ClearAllPoints()
			dot.Fill:SetPoint("CENTER", dot.Ring, "CENTER")
			dot.Fill:SetSize(inner, inner)
			if i <= points then
				dot.Fill:SetColorTexture(r, g, b, 1)
			else
				dot.Fill:SetColorTexture(0.22, 0.22, 0.22, 0.75) -- an empty socket
			end
			dot.lit = i <= points
			dot.Ring:Show()
			dot.Fill:Show()
		elseif dot then
			dot.Ring:Hide()
			dot.Fill:Hide()
		end
	end
	frame.points, frame.count, frame.size = points, count, size
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

-- The dots' size (Misc Tweaks' slider).
local function DotSize()
	local tweaks = ns.LT:GetModule("tweaks")
	local size = tweaks and tweaks.db and tonumber(tweaks.db.comboDotSize)
	return math.max(SIZE_MIN, math.min(SIZE_MAX, math.floor((size or DOT_SIZE) + 0.5)))
end

local previewUntil = 0 -- the slider moved or the preview is open: shown on the target, also without points

local function UpdateDots()
	local points = onNameplate and CurrentPoints()
	if points == 0 and onNameplate and GetTime() < previewUntil then
		points = MaxPoints()
	end
	local plate = points and points > 0 and TargetPlate()
	if not plate then
		if row then
			row:Hide()
		end
		return
	end
	row = row or NewRow()
	local bar = plate.healthBar or plate.HealthBarsContainer or plate
	local ok = pcall(function()
		if row:GetParent() ~= plate then
			row:SetParent(plate)
		end
		row:ClearAllPoints()
		row:SetPoint("BOTTOM", bar, "BOTTOM", 0, DOT_INSET) -- inside the bar, along its lower edge
		row:SetFrameLevel(bar:GetFrameLevel() + 10)
	end)
	if not ok then
		row:Hide()
		return
	end
	LayRow(row, MaxPoints(), math.min(points, MaxPoints()), DotSize())
	row:Show()
end

---------------------------------------------------------------------------
-- Preview: the dots on a stand-in nameplate, without a mob and without the settings open (Misc
-- Tweaks' button, /lefthy tweaks combopos). They count up from one point to full and again; - and
-- + change their size (saved through the settings: an open settings page shows it). Your target's
-- nameplate shows them meanwhile, also without points.
---------------------------------------------------------------------------

local trial
local COUNT_STEP = 0.8 -- seconds per point in the preview

local function Save(key, value)
	local tweaks = ns.LT:GetModule("tweaks")
	if tweaks and tweaks.db and tweaks.db[key] ~= value then
		ns.LT:SetModuleSetting(tweaks, key, value) -- (the settings page and your target's dots follow)
	end
end

local function TrialLayout()
	local count = MaxPoints()
	local points = trial.points or count
	LayRow(trial.Dots, count, points, DotSize())
	trial.Values:SetText(ns.L["Size %d px"]:format(DotSize()))
end

local function Resize(delta)
	Save("comboDotSize", math.max(SIZE_MIN, math.min(SIZE_MAX, DotSize() + delta)))
	TrialLayout()
	UpdateDots()
end

local function CountUp(self, elapsed)
	self.since = (self.since or 0) + elapsed
	if self.since >= COUNT_STEP then
		self.since = 0
		self.points = self.points % MaxPoints() + 1
		TrialLayout()
	end
end

local function SmallButton(texture, x, onClick)
	local button = CreateFrame("Button", nil, trial)
	button:SetSize(20, 20)
	button:SetNormalTexture(texture)
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button:SetPoint("BOTTOMLEFT", trial, "BOTTOMLEFT", x, 13)
	button:SetScript("OnClick", onClick)
	return button
end

local function BuildTrial()
	trial = CreateFrame("Frame", "LefthyToolsComboTrial", UIParent)
	trial:SetSize(300, 170)
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
	trial.Title:SetText(ns.L["Combo points on your target's nameplate"])
	trial.Hint = trial:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	trial.Hint:SetPoint("TOP", trial.Title, "BOTTOM", 0, -6)
	trial.Hint:SetWidth(280)
	trial.Hint:SetText(ns.L["They count up like your points will. - and + change their size; your target's nameplate shows them too."])
	-- The stand-in nameplate: a name, a health bar with the dots in it, the level right of it.
	trial.Plate = CreateFrame("Frame", nil, trial)
	trial.Plate:SetSize(120, 10)
	trial.Plate:SetPoint("CENTER", -10, 0)
	local bar = trial.Plate:CreateTexture(nil, "ARTWORK")
	bar:SetAllPoints()
	bar:SetColorTexture(0.75, 0.12, 0.1, 1)
	local barBack = trial.Plate:CreateTexture(nil, "BACKGROUND")
	barBack:SetPoint("TOPLEFT", -1, 1)
	barBack:SetPoint("BOTTOMRIGHT", 1, -1)
	barBack:SetColorTexture(0, 0, 0, 1)
	local name = trial.Plate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	name:SetPoint("BOTTOM", trial.Plate, "TOP", 0, 3)
	name:SetText(ns.L["Training Dummy"])
	local level = trial.Plate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	level:SetPoint("LEFT", trial.Plate, "RIGHT", 4, 0)
	level:SetText("60")
	trial.Dots = NewRow(trial.Plate)
	trial.Dots:SetPoint("BOTTOM", trial.Plate, "BOTTOM", 0, DOT_INSET)
	trial.Dots:SetFrameLevel(trial.Plate:GetFrameLevel() + 5)
	trial.Dots:Show()
	trial.Values = trial:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	trial.Values:SetPoint("BOTTOMLEFT", 62, 18)
	trial.Smaller = SmallButton("Interface\\Buttons\\UI-MinusButton-Up", 12, function() Resize(-1) end)
	trial.Bigger = SmallButton("Interface\\Buttons\\UI-PlusButton-Up", 36, function() Resize(1) end)
	trial.Reset = CreateFrame("Button", nil, trial, "UIPanelButtonTemplate")
	trial.Reset:SetSize(70, 22)
	trial.Reset:SetPoint("BOTTOMRIGHT", -88, 10)
	trial.Reset:SetText(ns.L["Reset"])
	trial.Reset:SetScript("OnClick", function() Resize(DOT_SIZE - DotSize()) end)
	trial.Done = CreateFrame("Button", nil, trial, "UIPanelButtonTemplate")
	trial.Done:SetSize(70, 22)
	trial.Done:SetPoint("BOTTOMRIGHT", -12, 10)
	trial.Done:SetText(ns.L["Done"])
	trial.Done:SetScript("OnClick", function() trial:Hide() end)
	trial:SetScript("OnShow", function(self)
		previewUntil = math.huge -- (your target's nameplate shows the dots while it's open)
		self.points, self.since = 1, 0
		self:SetScript("OnUpdate", CountUp)
		TrialLayout()
		UpdateDots()
	end)
	trial:SetScript("OnHide", function(self)
		self:SetScript("OnUpdate", nil)
		previewUntil = 0
		UpdateDots()
	end)
	trial:Hide()
	if UISpecialFrames then
		table.insert(UISpecialFrames, "LefthyToolsComboTrial") -- Escape closes it
	end
end

-- Opens (or closes) the preview.
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

local pendingAttach, pendingDots = false, false
driver:Hide()
driver:SetScript("OnUpdate", function(self)
	if pendingAttach then
		pendingAttach = false
		Attach()
	end
	if pendingDots then
		pendingDots = false
		UpdateDots()
	end
	if GetTime() < followUntil then
		Follow()
	elseif not (pendingAttach or pendingDots) then
		self:Hide()
	end
end)

local function Soon(attach)
	pendingAttach = pendingAttach or attach
	pendingDots = true
	driver:Show()
end

-- Only what can change the colouring or the dots: a nameplate coming or going matters only while
-- points wait for the target's (crowds bring nameplates all the time).
events:SetScript("OnEvent", function(_, event, unit, powerToken)
	if event == "UNIT_POWER_FREQUENT" then
		if powerToken == "COMBO_POINTS" then
			Soon(false) -- (Blizzard's bar updates itself: its hook recolours)
		end
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		local points = onNameplate and not (row and row:IsShown()) and CurrentPoints()
		if (points and points > 0) or (onNameplate and GetTime() < previewUntil) then
			Soon(false)
		end
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		if row and row:IsShown() then
			Soon(false)
		end
	elseif event == "ADDON_LOADED" then
		if unit == "Blizzard_PersonalResourceDisplay" then
			Soon(true)
		end
	elseif event == "PLAYER_ENTERING_WORLD" or event == "UNIT_DISPLAYPOWER" then
		Soon(true) -- (the display may build its bar: a druid's Cat Form)
	else
		Soon(false) -- target, max points, combo target
	end
end)

local function Listen()
	events:UnregisterAllEvents()
	if not (colorByCount or onNameplate) then
		return
	end
	for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD", "ADDON_LOADED", "COMBO_TARGET_CHANGED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	if onNameplate then
		pcall(events.RegisterEvent, events, "NAME_PLATE_UNIT_ADDED")
		pcall(events.RegisterEvent, events, "NAME_PLATE_UNIT_REMOVED")
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
	UpdateDots()
end

function ns.ApplyComboNameplate(on)
	onNameplate = on
	Listen()
	UpdateDots()
end

-- The size slider moved: the dots show on your target for a few seconds (full points if you have
-- none), so you see them.
function ns.PreviewComboNameplate()
	previewUntil = math.max(previewUntil, GetTime() + 5) -- (the preview window's lasts while it's open)
	UpdateDots()
	C_Timer.After(5.1, UpdateDots)
end

-- For tests.
function ns.GetComboDots()
	return row
end
