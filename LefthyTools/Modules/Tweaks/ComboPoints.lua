local _, ns = ...

-- Misc Tweaks 4: combo points on the personal resource display.
--
-- Forever's personal resource display (Blizzard_PersonalResourceDisplay) leaves class
-- resources out: its Camelot override of GetClassFrameInfo() returns nil ("Class resource
-- templates are not loaded in Camelot"), so combo points only show on the target frame
-- (ComboFrame). This adds a centred row of combo points under the display's lowest bar.
--
-- The row is our own child of PersonalResourceDisplayFrame: it moves, scales, hides (combat-only
-- setting, Edit Mode) and fades (Mirage) with it. It is anchored under the display's bottom edge,
-- which Blizzard sizes to the visible bars (UpdateFrameHeight), and shrinks to fit the display's
-- width (the Edit Mode bar width). Nothing of Blizzard's is changed; the only hook is the
-- display's OnSizeChanged, which just schedules a re-layout.
--
-- Look: retail's rogue combo points (RogueComboPointTemplate's uf-roguecp-* atlases, rebuilt here
-- because Camelot doesn't load that template), with Blizzard's own gain and spend animations,
-- when the client has the atlases; otherwise the classic gems from the target frame
-- (Interface\ComboFrame\ComboPoint). At full points the row pulses: ready for a finisher.
--
-- Combo points sit on the target like in Classic: GetComboPoints("player", "target"), as
-- Blizzard's ComboFrame reads them. Rogues always; druids in Cat Form (energy).

local MAX_PIPS = 10

-- Layers per style. Static layers are always visible; the others start at alpha 0 and are
-- driven by the animations below (Inactive = empty socket, Active = lit socket, Icon = the gem,
-- Glow/Burst/FrameGlow/Slash = effects).
local STYLES = {
	retail = {
		size = 20, gap = 2,
		probe = "uf-roguecp-icon-red",
		layers = {
			{ key = "Shadow", atlas = "uf-roguecp-bg-shadow", layer = "BACKGROUND", sub = 0, y = -4, static = true },
			{ key = "Inactive", atlas = "uf-roguecp-bg-dis", layer = "BACKGROUND", sub = 1 },
			{ key = "Active", atlas = "uf-roguecp-bg", layer = "BACKGROUND", sub = 2 },
			{ key = "Glow", atlas = "uf-roguecp-bg", layer = "BACKGROUND", sub = 3 },
			{ key = "Icon", atlas = "uf-roguecp-icon-red", layer = "ARTWORK", sub = 1 },
			{ key = "IconBoost", atlas = "uf-roguecp-icon-red", layer = "ARTWORK", sub = 2, blend = "ADD" },
			{ key = "Burst", atlas = "uf-roguecp-fx-red", layer = "ARTWORK", sub = 3 },
			{ key = "FrameGlow", atlas = "uf-roguecp-frame-glow", layer = "OVERLAY", sub = 0 },
			{ key = "Slash", atlas = "uf-roguecp-slash-red", layer = "OVERLAY", sub = 1, width = 43, height = 43,
				flipBook = { rows = 3, columns = 6, frames = 17, duration = 0.57 } },
		},
	},
	classic = {
		size = 16, gap = 3,
		layers = {
			{ key = "Socket", file = "Interface\\ComboFrame\\ComboPoint", coords = { 0, 0.375, 0, 1 },
				layer = "BACKGROUND", sub = 0, width = 15, height = 20, x = 0, y = -2, static = true },
			{ key = "Icon", file = "Interface\\ComboFrame\\ComboPoint", coords = { 0.375, 0.5625, 0, 1 },
				layer = "ARTWORK", sub = 1, width = 10, height = 20, x = 0, y = -2 },
			{ key = "IconBoost", file = "Interface\\ComboFrame\\ComboPoint", coords = { 0.375, 0.5625, 0, 1 },
				layer = "ARTWORK", sub = 2, width = 10, height = 20, x = 0, y = -2, blend = "ADD" },
			{ key = "Glow", file = "Interface\\ComboFrame\\ComboPoint", coords = { 0.5625, 1, 0, 1 },
				layer = "OVERLAY", sub = 0, width = 18, height = 20, x = 1, y = 3, blend = "ADD" },
			{ key = "FrameGlow", file = "Interface\\ComboFrame\\ComboPoint", coords = { 0.5625, 1, 0, 1 },
				layer = "OVERLAY", sub = 1, width = 18, height = 20, x = 1, y = 3, blend = "ADD" },
		},
	},
}

-- { key, fromAlpha, toAlpha, startDelay, duration }; keys a style doesn't have are skipped.
-- Timings from RogueComboPointTemplate (unchargedEmptyToUnchargedFull / unchargedFullToUnchargedEmpty).
local GAIN = {
	{ "Slash", 0, 1, 0, 0 },
	{ "Icon", 0, 0.5, 0, 0.1 }, { "Icon", 0.5, 1, 0.27, 0.27 },
	{ "IconBoost", 0, 0.5, 0, 0.1 }, { "IconBoost", 0.5, 1, 0.27, 0.27 },
	{ "Active", 0, 0, 0, 0.2 }, { "Active", 0, 1, 0.2, 0.17 },
	{ "Inactive", 1, 1, 0, 0.37 }, { "Inactive", 1, 0, 0.37, 0.1 },
	{ "Glow", 0, 1, 0, 0.17 }, { "Glow", 1, 0, 0.17, 0.4 },
}
local SPEND = {
	{ "FrameGlow", 1, 0, 0, 0.5 },
	{ "Icon", 1, 0, 0, 0.17 },
	{ "IconBoost", 1, 0, 0, 0.17 },
	{ "Burst", 1, 0, 0, 0.4 },
	{ "Active", 1, 1, 0, 0.2 }, { "Active", 1, 0, 0.2, 0.17 },
	{ "Inactive", 0, 0, 0, 0.37 }, { "Inactive", 0, 1, 0.37, 0.1 },
}
local READY_PULSE = { from = 0.15, to = 0.7, duration = 0.6 } -- FrameGlow while at full points

-- Colour by count: green with one point, through yellow, to red at full.
-- The art is red, so the coloured layers are desaturated first and then tinted; the empty
-- socket and the shadow keep their own look. A desaturated red gem is dark grey, so tinting
-- alone looked muted: IconBoost, an additive copy of the gem in the same colour, brightens it
-- (the plain gem underneath keeps its shape and outline), and the effects blend additively.
local TINTED = { "Active", "Glow", "Icon", "IconBoost", "Burst", "FrameGlow", "Slash" }
local ADDITIVE_WHEN_TINTED = { Glow = true, Burst = true, FrameGlow = true, Slash = true }
-- "A bit brighter still": the plain gem and the lit socket get a tint lifted towards white;
-- the additive copy and the effects keep the full colour, so the hue stays strong.
local LIGHTEN = { Icon = 0.25, Active = 0.25 }
local GREEN, YELLOW, RED = { 0.15, 1, 0.15 }, { 1, 0.9, 0 }, { 1, 0.1, 0.05 }
local colorByCount = false -- switched by Tweaks.lua (ns.ApplyComboColors), on by default

local function CountColor(points, count)
	local t = count > 1 and (points - 1) / (count - 1) or 1
	t = math.max(0, math.min(1, t))
	local from, to, f = GREEN, YELLOW, t * 2
	if t > 0.5 then
		from, to, f = YELLOW, RED, (t - 0.5) * 2
	end
	return from[1] + (to[1] - from[1]) * f, from[2] + (to[2] - from[2]) * f, from[3] + (to[3] - from[3]) * f
end

local row
local pips = {}
local style
local shownPoints = 0
local active, layoutDirty = false, true
local driver = CreateFrame("Frame")
local events = CreateFrame("Frame")

local function Display()
	return PersonalResourceDisplayFrame
end

local function PickStyle()
	local probe = STYLES.retail.probe
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(probe) then
		return STYLES.retail
	end
	return STYLES.classic
end

local function UsesComboPoints()
	local _, classFile = UnitClass("player")
	if classFile == "ROGUE" then
		return true
	end
	local energy = Enum and Enum.PowerType and Enum.PowerType.Energy or 3
	return classFile == "DRUID" and UnitPowerType("player") == energy
end

-- nil when the game keeps the value secret (it shouldn't for combo points).
local function CurrentPoints()
	local points = GetComboPoints("player", "target")
	if issecretvalue and issecretvalue(points) then
		return nil
	end
	return points or 0
end

local function MaxPoints()
	local comboPoints = Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4
	local max = UnitPowerMax("player", comboPoints)
	if (issecretvalue and issecretvalue(max)) or not max or max < 1 then
		max = 5
	end
	return math.min(max, MAX_PIPS)
end

local function MarkDirty()
	if active then
		driver:Show() -- runs the update on the next frame, never inside the event
	end
end

local function MarkLayoutDirty()
	layoutDirty = true
	MarkDirty()
end

---------------------------------------------------------------------------
-- One combo point
---------------------------------------------------------------------------

local function BuildAnimation(pip, steps)
	local group = pip:CreateAnimationGroup()
	group:SetToFinalAlpha(true)
	for _, step in ipairs(steps) do
		local texture = pip[step[1]]
		if texture then
			local alpha = group:CreateAnimation("Alpha")
			alpha:SetTarget(texture)
			alpha:SetFromAlpha(step[2])
			alpha:SetToAlpha(step[3])
			alpha:SetStartDelay(step[4])
			alpha:SetDuration(step[5])
			alpha:SetOrder(1)
		end
	end
	return group
end

local function CreatePip()
	local pip = CreateFrame("Frame", nil, row)
	pip:SetSize(style.size, style.size)
	pip.effects = {}
	for _, spec in ipairs(style.layers) do
		local texture = pip:CreateTexture(nil, spec.layer, nil, spec.sub)
		if spec.atlas then
			texture:SetAtlas(spec.atlas, not spec.width)
		else
			texture:SetTexture(spec.file)
			texture:SetTexCoord(spec.coords[1], spec.coords[2], spec.coords[3], spec.coords[4])
		end
		if spec.width then
			texture:SetSize(spec.width, spec.height)
		end
		texture.baseBlend = spec.blend or "BLEND"
		texture:SetBlendMode(texture.baseBlend)
		texture:SetPoint("CENTER", pip, "CENTER", spec.x or 0, spec.y or 0)
		if not spec.static then
			texture:SetAlpha(0)
			pip.effects[#pip.effects + 1] = texture
		end
		pip[spec.key] = texture
	end
	pip.Gain = BuildAnimation(pip, GAIN)
	pip.Spend = BuildAnimation(pip, SPEND)
	local slash = style.layers[#style.layers].flipBook and pip.Slash
	if slash then
		local book = style.layers[#style.layers].flipBook
		local ok = pcall(function()
			local flip = pip.Gain:CreateAnimation("FlipBook")
			flip:SetTarget(slash)
			flip:SetFlipBookRows(book.rows)
			flip:SetFlipBookColumns(book.columns)
			flip:SetFlipBookFrames(book.frames)
			flip:SetFlipBookFrameWidth(0)
			flip:SetFlipBookFrameHeight(0)
			flip:SetDuration(book.duration)
			flip:SetOrder(1)
		end)
		if not ok then
			pip.Slash:Hide() -- without the flipbook the slash would show its whole sprite sheet
		end
	end
	-- Full points: the glow breathes until a finisher spends them.
	pip.Ready = pip:CreateAnimationGroup()
	pip.Ready:SetLooping("BOUNCE")
	local breathe = pip.Ready:CreateAnimation("Alpha")
	breathe:SetTarget(pip.FrameGlow)
	breathe:SetFromAlpha(READY_PULSE.from)
	breathe:SetToAlpha(READY_PULSE.to)
	breathe:SetDuration(READY_PULSE.duration)
	return pip
end

-- r == nil: the art's own colours.
local function TintPip(pip, r, g, b)
	local tinted = r ~= nil
	for _, key in ipairs(TINTED) do
		local texture = pip[key]
		if texture then
			texture:SetDesaturated(tinted)
			local lift = tinted and LIGHTEN[key] or 0
			texture:SetVertexColor((r or 1) + (1 - (r or 1)) * lift, (g or 1) + (1 - (g or 1)) * lift,
				(b or 1) + (1 - (b or 1)) * lift)
			if ADDITIVE_WHEN_TINTED[key] then
				texture:SetBlendMode(tinted and "ADD" or texture.baseBlend)
			end
		end
	end
	pip.IconBoost:SetShown(tinted) -- retail's own red needs no boost
end

-- Shows a point empty or full, animated like retail when it changes, instantly when not
-- (first draw, row coming back, or a point that didn't exist before).
local function SetPip(pip, full, animate, ready)
	if pip.full ~= full then
		animate = animate and pip.full ~= nil
		pip.Gain:Stop()
		pip.Spend:Stop()
		pip.Ready:Stop()
		for _, texture in ipairs(pip.effects) do
			texture:SetAlpha(0)
		end
		if animate then
			if full then
				pip.Gain:Play()
			else
				pip.Spend:Play()
			end
		else
			-- Final state of the animation without playing it.
			if pip.Inactive then pip.Inactive:SetAlpha(full and 0 or 1) end
			if pip.Active then pip.Active:SetAlpha(full and 1 or 0) end
			pip.Icon:SetAlpha(full and 1 or 0)
			pip.IconBoost:SetAlpha(full and 1 or 0)
		end
		pip.full = full
	end
	if ready and full then
		if not pip.Ready:IsPlaying() then
			pip.Ready:Play()
		end
	elseif pip.Ready:IsPlaying() then
		pip.Ready:Stop()
		pip.FrameGlow:SetAlpha(0)
	end
end

---------------------------------------------------------------------------
-- The row
---------------------------------------------------------------------------

local function CreateRow()
	style = PickStyle()
	local display = Display()
	row = CreateFrame("Frame", nil, display)
	display:HookScript("OnSizeChanged", MarkLayoutDirty) -- Edit Mode bar width and visible bars
end

local function Layout()
	layoutDirty = false
	local display = Display()
	local padding = display.GetBarPadding and display:GetBarPadding() or 4
	local count = MaxPoints()
	local width = count * style.size + (count - 1) * style.gap
	-- Shrink to fit narrow bars (Edit Mode bar width); never grow past Blizzard's size.
	local available = display:GetWidth()
	local scale = (available and available > 0 and width > available) and available / width or 1
	row:SetScale(scale)
	row:ClearAllPoints()
	row:SetPoint("TOP", display, "BOTTOM", 0, -(padding + 2) / scale)
	row:SetSize(width, style.size)
	for i = 1, MAX_PIPS do
		local pip = pips[i]
		if i <= count then
			pip = pip or CreatePip()
			pips[i] = pip
			pip:ClearAllPoints()
			pip:SetPoint("LEFT", row, "LEFT", (i - 1) * (style.size + style.gap), 0)
			pip:Show()
		elseif pip then
			pip:Hide()
		end
	end
	row.count = count
	shownPoints = -1 -- re-evaluate every point
end

local function Update()
	driver:Hide()
	local display = Display()
	if not active or not display then
		if row then
			row:Hide()
		end
		return
	end
	local points = UsesComboPoints() and CurrentPoints()
	if not points then
		if row then
			row:Hide()
		end
		return
	end
	if not row then
		CreateRow()
	end
	local firstDraw = layoutDirty and shownPoints == 0
	if layoutDirty then
		Layout()
	end
	local wasHidden = not row:IsShown()
	row:Show()
	if points == shownPoints then
		return
	end
	local count = row.count
	local animate = not (firstDraw or wasHidden)
	-- Recolour first, so a gained point animates in its new colour. At 0 points the gems keep
	-- their colour while they burst out.
	if points > 0 or shownPoints < 0 then
		local r, g, b
		if colorByCount and points > 0 then
			r, g, b = CountColor(points, count)
		end
		for i = 1, count do
			TintPip(pips[i], r, g, b)
		end
	end
	for i = 1, count do
		SetPip(pips[i], i <= points, animate, points >= count)
	end
	shownPoints = points
end

driver:Hide()
driver:SetScript("OnUpdate", Update)

events:SetScript("OnEvent", function(_, event, unit, powerToken)
	if event == "UNIT_POWER_FREQUENT" then
		if powerToken == "COMBO_POINTS" then -- energy ticks come through here too; ignore them
			MarkDirty()
		end
	elseif event == "UNIT_MAXPOWER" or event == "PLAYER_ENTERING_WORLD" or event == "EDIT_MODE_LAYOUTS_UPDATED" then
		MarkLayoutDirty()
	elseif event == "ADDON_LOADED" then
		if unit == "Blizzard_PersonalResourceDisplay" then
			MarkLayoutDirty()
		end
	else -- target changed, shapeshift (UNIT_DISPLAYPOWER)
		MarkDirty()
	end
end)

-- Called by Tweaks.lua when the tweak is switched (on the next frame, never in a callback).
function ns.ApplyComboPoints(on)
	active = on
	if on then
		for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD", "EDIT_MODE_LAYOUTS_UPDATED", "ADDON_LOADED" }) do
			pcall(events.RegisterEvent, events, event)
		end
		for _, event in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do
			pcall(events.RegisterUnitEvent, events, event, "player")
		end
		layoutDirty = true
		Update()
	else
		events:UnregisterAllEvents()
		Update() -- hides the row
	end
end

-- The "colour by number of points" switch (a Misc Tweaks entry of its own).
function ns.ApplyComboColors(on)
	colorByCount = on
	MarkLayoutDirty() -- recolours on the next frame
end

-- For tests.
function ns.GetComboPointRow()
	return row, pips, style == STYLES.retail and "retail" or (style and "classic")
end
