-- Minimal WoW API mock for smoke-testing LefthyTools outside the game.
unpack = table.unpack
local now = 0
function GetTime() return now end

PRINTED = {}
function print(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
	local line = table.concat(parts, " ")
	PRINTED[#PRINTED + 1] = line
	io.write("    [print] " .. line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "\n")
end

function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function strsplit(delim, str, pieces)
	local out, start = {}, 1
	while true do
		if pieces and #out == pieces - 1 then out[#out + 1] = str:sub(start); break end
		local i = str:find(delim, start, true)
		if not i then out[#out + 1] = str:sub(start); break end
		out[#out + 1] = str:sub(start, i - 1)
		start = i + 1
	end
	return unpack(out)
end

function hooksecurefunc(tbl, key, fn)
	if type(tbl) == "string" then tbl, key, fn = _G, tbl, key end
	local orig = tbl[key]
	assert(type(orig) == "function", "hooksecurefunc: no function " .. tostring(key))
	tbl[key] = function(...)
		local r = table.pack(orig(...))
		fn(...)
		return unpack(r, 1, r.n)
	end
end

function GetLocale() return MOCK_LOCALE or "enUS" end

-- TOC metadata; the installer stamps the exact build into "Version".
MOCK_VERSION = "0.4.0-3-gabc1234"
C_AddOns = { GetAddOnMetadata = function(addon, field)
	if addon == "LefthyTools" and field == "Version" then return MOCK_VERSION end
end }

-- secret values: a table marked SECRET
SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
function issecretvalue(v) return v == SECRET end

-- timers
local timers = {}
C_Timer = { After = function(d, fn) timers[#timers + 1] = { at = now + d, fn = fn } end }

-- frames
local allFrames, eventFrames = {}, {}
local FrameMethods = {}
FrameMethods.__index = FrameMethods
function FrameMethods:SetScript(k, fn) self._scripts[k] = fn end
function FrameMethods:GetScript(k) return self._scripts[k] end
function FrameMethods:RegisterEvent(e) eventFrames[e] = eventFrames[e] or {}; eventFrames[e][self] = true end
function FrameMethods:RegisterUnitEvent(e, ...) self._units[e] = { ... }; self:RegisterEvent(e) end
function FrameMethods:UnregisterEvent(e) if eventFrames[e] then eventFrames[e][self] = nil end end
function FrameMethods:UnregisterAllEvents() for _, set in pairs(eventFrames) do set[self] = nil end end
function FrameMethods:SetAlpha(a) self._alpha = a; self._setCount = (self._setCount or 0) + 1 end
function FrameMethods:GetAlpha() return self._alpha end
function FrameMethods:GetParent() return self._parent end
function FrameMethods:IsShown() return self._shown end
function FrameMethods:IsVisible()
	local f = self
	while f do if not f._shown then return false end f = f._parent end
	return true
end
function FrameMethods:Show()
	local wasShown = self._shown
	self._shown = true
	if not wasShown and self._scripts.OnShow then self._scripts.OnShow(self) end
end
function FrameMethods:Hide()
	local wasShown = self._shown
	self._shown = false
	if wasShown and self._scripts.OnHide then self._scripts.OnHide(self) end
end
function FrameMethods:IsMouseOver() return self._mouse == true end
function FrameMethods:IsForbidden() return false end
function FrameMethods:IsProtected() return false end
function FrameMethods:GetName() return self._name end
function FrameMethods:GetObjectType() return "Frame" end
-- positioning / dragging (bags)
function FrameMethods:SetScale(s) self._scale = s end
function FrameMethods:GetScale() return self._scale or 1 end
function FrameMethods:GetEffectiveScale() return self._scale or 1 end
function FrameMethods:ClearAllPoints() self._points = {} end
function FrameMethods:SetPoint(...) self._points = self._points or {}; self._points[#self._points + 1] = { ... } end
function FrameMethods:GetPoint(i) local p = (self._points or {})[i or 1]; if p then return unpack(p) end end
function FrameMethods:GetLeft() local p = (self._points or {})[1]; if p and p[1] == "TOPLEFT" then return p[4] end end
function FrameMethods:GetTop() local p = (self._points or {})[1]; if p and p[1] == "TOPLEFT" then return p[5] end end
function FrameMethods:SetParent(p) self._parent = p end
function FrameMethods:GetChildren() return unpack(self._children or {}) end
function FrameMethods:RegisterForDrag(...) self._dragButtons = { ... } end
function FrameMethods:HookScript(k, fn)
	local prev = self._scripts[k]
	self._scripts[k] = function(...) if prev then prev(...) end fn(...) end
end
function FrameMethods:SetMovable(m) self._movable = m end
function FrameMethods:SetClampedToScreen(c) self._clamped = c end
function FrameMethods:StartMoving() self._moving = true end
function FrameMethods:StopMovingOrSizing() -- the engine leaves the frame where the cursor dropped it
	self._moving = false
	if self._dropAt then
		self._points = { { "TOPLEFT", UIParent, "BOTTOMLEFT", self._dropAt.left, self._dropAt.top } }
	end
end
function FrameMethods:SetUserPlaced(u) self._userPlaced = u end
function FrameMethods:SetShown(s) self._shown = s and true or false end
function FrameMethods:SetSize(w, h)
	local changed = w ~= self._width or h ~= self._height
	self._width, self._height = w, h
	if changed and self._scripts.OnSizeChanged then self._scripts.OnSizeChanged(self, w, h) end
end
function FrameMethods:SetHeight(h) self:SetSize(self._width, h) end
function FrameMethods:SetWidth(w) self:SetSize(w, self._height) end
function FrameMethods:GetWidth() return self._width or 0 end
function FrameMethods:GetHeight() return self._height or 0 end
function FrameMethods:SetFrameLevel(l) self._level = l end
function FrameMethods:GetFrameLevel() return self._level or 1 end
function FrameMethods:SetFrameStrata(s) self._strata = s end
function FrameMethods:SetMouseMotionEnabled(e) self._motion = e end
function FrameMethods:SetMouseClickEnabled(e) self._click = e end
function FrameMethods:EnableMouse(e) self._mouseEnabled = e end
function FrameMethods:RegisterForClicks(...) self._clicks = { ... } end
function FrameMethods:SetHighlightTexture(t) self._highlight = t end
function FrameMethods:SetNormalTexture(t) self._normal = t end
function FrameMethods:SetPushedTexture(t) self._pushed = t end
function FrameMethods:SetDisabledTexture(t) self._disabled = t end
function FrameMethods:GetCenter() return self._centerX, self._centerY end -- set by tests where needed
CURSOR = { x = 0, y = 0 }
function GetCursorPosition() return CURSOR.x, CURSOR.y end
function FrameMethods:SetID(id) self._id = id end
function FrameMethods:GetID() return self._id or 0 end
-- Protected: blocked by the game in combat.
function FrameMethods:SetPassThroughButtons(...)
	if InCombatLockdown() then BLOCKED[#BLOCKED + 1] = "SetPassThroughButtons" return end
	self._passThrough = { ... }
end
function FrameMethods:SetPropagateMouseMotion(p)
	if InCombatLockdown() then BLOCKED[#BLOCKED + 1] = "SetPropagateMouseMotion" return end
	self._propagateMotion = p
end
function FrameMethods:SetAllPoints(rel) self._points = { { "TOPLEFT", rel }, { "BOTTOMRIGHT", rel } } end
-- PlayerModel
function FrameMethods:SetUnit(unit) self._unit = unit end
function FrameMethods:SetFacing(f) self._facing = f end
function FrameMethods:SetToplevel() end
-- Buttons and edit boxes
function FrameMethods:SetText(text)
	self._text = text
	if self._kind == "EditBox" and self._scripts.OnTextChanged then self._scripts.OnTextChanged(self, false) end
end
function FrameMethods:GetText() return self._text end
function FrameMethods:Click(button) if self._scripts.OnClick then self._scripts.OnClick(self, button or "LeftButton") end end
function FrameMethods:SetEnabled(e) self._enabled = e end
function FrameMethods:IsEnabled() return self._enabled ~= false end
function FrameMethods:SetMultiLine(m) self._multiLine = m end
function FrameMethods:SetAutoFocus(a) self._autoFocus = a end
function FrameMethods:SetFontObject(f) self._font = f end
function FrameMethods:HighlightText() self._highlighted = true end
function FrameMethods:SetFocus() self._focus = true end
function FrameMethods:ClearFocus() self._focus = false end
function FrameMethods:HasFocus() return self._focus == true end
function FrameMethods:SetMaxLetters(n) self._maxLetters = n end
function FrameMethods:SetCursorPosition() end
-- Scroll frames
function FrameMethods:SetScrollChild(child) self._scrollChild = child end
function FrameMethods:GetScrollChild() return self._scrollChild end
function FrameMethods:SetVerticalScroll(v) self._scroll = v end
function FrameMethods:GetVerticalScroll() return self._scroll or 0 end
-- Animation groups. With SetToFinalAlpha(true), Play() jumps straight to the end state: each
-- target gets the toAlpha of its last-ending Alpha step (what the game shows once it's done).
local function NewAnimationGroup(owner) -- (an animation without a target animates its owner, like the game)
	local g = { playing = false, anims = {}, plays = 0, owner = owner }
	function g:CreateAnimation(kind)
		local a = { kind = kind }
		function a:SetTarget(t) self.target = t end
		function a:SetFromAlpha(v) self.from = v end
		function a:SetToAlpha(v) self.to = v end
		function a:SetStartDelay(v) self.delay = v end
		function a:SetDuration(v) self.duration = v end
		function a:SetOrder() end
		function a:SetScaleFrom(x, y) self.scaleFrom = { x, y } end
		function a:SetScaleTo(x, y) self.scaleTo = { x, y } end
		function a:SetOffset(x, y) self.offset = { x, y } end
		function a:SetOrigin() end
		function a:SetSmoothing(s) self.smoothing = s end
		for _, m in ipairs({ "SetFlipBookRows", "SetFlipBookColumns", "SetFlipBookFrames", "SetFlipBookFrameWidth", "SetFlipBookFrameHeight" }) do
			a[m] = function() end
		end
		self.anims[#self.anims + 1] = a
		return a
	end
	function g:SetLooping(l) self.looping = l end
	function g:SetToFinalAlpha(v) self.final = v end
	function g:Play()
		self.playing, self.plays = true, self.plays + 1
		if self.final then
			local ends, last = {}, {}
			for _, a in ipairs(self.anims) do
				local target = a.target or self.owner
				if target and a.to ~= nil then
					local e = (a.delay or 0) + (a.duration or 0)
					if not ends[target] or e >= ends[target] then ends[target], last[target] = e, a.to end
				end
			end
			for target, alpha in pairs(last) do target:SetAlpha(alpha) end
		end
	end
	function g:Stop() self.playing = false end
	function g:IsPlaying() return self.playing end
	function g:SetScript(k, fn) self.scripts = self.scripts or {}; self.scripts[k] = fn end
	function g:Finish() -- tests: the animation ran to its end
		self.playing = false
		if self.scripts and self.scripts.OnFinished then self.scripts.OnFinished(self) end
	end
	return g
end
function FrameMethods:CreateAnimationGroup() return NewAnimationGroup(self) end
local function NewTexture()
	local t = { shown = true, alpha = 1 }
	function t:SetAllPoints() end
	function t:SetPoint() end
	function t:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
	function t:SetTexture(path) self.path = path end
	function t:AddMaskTexture() end
	function t:SetShown(s) self.shown = s and true or false end
	function t:Show() self.shown = true end
	function t:Hide() self.shown = false end
	function t:IsShown() return self.shown end
	function t:SetAlpha(a) self.alpha = a end
	function t:GetAlpha() return self.alpha end
	function t:CreateAnimationGroup() return NewAnimationGroup(self) end
	function t:SetAtlas(atlas) self.atlas, self.color = atlas, nil end
	function t:SetVertexColor(r, g, b, a) self.vertex, self.gradient = { r, g, b, a }, nil end -- replaces a gradient
	function t:SetBlendMode(mode) self.blend = mode end
	function t:ClearAllPoints() self.points = {} end
	function t:SetSize(w, h) self.width, self.height = w, h end
	function t:SetHeight(h) self.height = h end
	function t:SetWidth(w) self.width = w end
	function t:SetTexCoord(...) self.coords = { ... } end
	function t:SetDesaturated(d) self.desaturated = d end
	function t:SetScale(s) self.scale = s end
	function t:SetRotation(r) self.rotation = r end
	return t
end
function FrameMethods:CreateTexture(_, layer)
	local t = NewTexture()
	t.layer = layer
	self._textures = self._textures or {}
	self._textures[#self._textures + 1] = t
	function t:SetDrawLayer(layer) self.layer = layer end
	function t:SetGradient(orientation, from, to) self.gradient = { orientation, from, to } end
	return t
end
-- Line objects (graphs)
LINES_CREATED = 0
function FrameMethods:CreateLine()
	LINES_CREATED = LINES_CREATED + 1
	local l = { shown = true }
	function l:SetStartPoint(_, _, x, y) self.from = { x, y } end
	function l:SetEndPoint(_, _, x, y) self.to = { x, y } end
	function l:SetThickness(t) self.thickness = t end
	function l:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
	function l:Show() self.shown = true end
	function l:Hide() self.shown = false end
	function l:IsShown() return self.shown end
	return l
end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
function FrameMethods:CreateMaskTexture() return NewTexture() end
function FrameMethods:CreateFontString()
	local fs = {}
	function fs:SetAllPoints() end
	function fs:SetPoint(...) self._points = self._points or {}; self._points[#self._points + 1] = { ... } end
	function fs:ClearAllPoints() self._points = {} end
	function fs:SetText(text) self.text = text end
	function fs:GetText() return self.text end
	function fs:GetStringWidth() return #(self.text or "") * 6 end
	function fs:GetStringHeight() local n = 1 for _ in (self.text or ""):gmatch("\n") do n = n + 1 end return n * 14 end
	function fs:SetTextColor(r, g, b) self.color = { r, g, b } end
	function fs:SetJustifyH(j) self.justifyH = j end
	function fs:SetJustifyV(j) self.justifyV = j end
	function fs:SetSpacing() end
	function fs:SetWordWrap() end
	function fs:SetWidth(w) self.width = w end
	function fs:GetWidth() return (self.width or 0) > 0 and self.width or self:GetStringWidth() end -- 0: as wide as the text
	function fs:SetHeight(h) self.height = h end
	function fs:SetFontObject(f) self.font = f end
	function fs:SetFont(path, size, flags) self.fontFile, self.fontSize = path, size; return true end
	function fs:SetShadowOffset(x, y) self.shadow = { x, y } end
	function fs:SetShadowColor() end
	function fs:SetTextScale(s) self.textScale = s end
	function fs:SetAlpha(a) self.alpha = a end
	function fs:GetAlpha() return self.alpha or 1 end
	function fs:CreateAnimationGroup() return NewAnimationGroup(self) end
	function fs:SetShown(s) self.shown = s and true or false end
	fs.shown = true
	function fs:Show() self.shown = true end
	function fs:Hide() self.shown = false end
	function fs:IsShown() return self.shown end
	-- 6 px per visible character, wrapping at MOCK_LINE_WIDTH (escape codes take no space).
	function fs:GetNumLines()
		local plain = (self.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		return math.max(1, math.ceil(#plain * 6 / (MOCK_LINE_WIDTH or 200)))
	end
	return fs
end

-- What the Blizzard templates the addon uses add to a frame.
local function ApplyTemplate(f, template)
	f._template = template
	if template:find("ButtonFrameTemplate", 1, true) then
		f.TitleContainer = CreateFrame("Frame", nil, f)
		f.TitleContainer.TitleText = f.TitleContainer:CreateFontString()
		function f:SetTitle(title) self.TitleContainer.TitleText:SetText(title) end
		f.Inset = CreateFrame("Frame", nil, f)
		f.CloseButton = CreateFrame("Button", nil, f)
		f.CloseButton:SetScript("OnClick", function() f:Hide() end)
	elseif template:find("ScrollFrameTemplate", 1, true) then
		f.ScrollBar = CreateFrame("Slider", nil, f)
	elseif template:find("WowStyle1DropdownTemplate", 1, true) then
		-- Blizzard_Menu's dropdown: SetupMenu keeps the generator, GenerateMenu runs it (the text is
		-- the selected radio's); Pick(text) chooses the radio whose label contains text, like a click.
		function f:SetupMenu(generator) self._generator = generator; self:GenerateMenu() end
		function f:GenerateMenu()
			local entries, root = {}, {}
			function root:CreateTitle(text) entries[#entries + 1] = { kind = "title", text = text } end
			function root:CreateDivider() entries[#entries + 1] = { kind = "divider" } end
			function root:CreateRadio(text, isSelected, setSelected, data)
				entries[#entries + 1] = { kind = "radio", text = text, isSelected = isSelected, setSelected = setSelected, data = data }
			end
			self._generator(self, root)
			self._entries, self._generated = entries, (self._generated or 0) + 1
			self._text = nil
			for _, e in ipairs(entries) do if e.kind == "radio" and e.isSelected(e.data) then self._text = e.text end end
		end
		function f:Pick(text)
			self:GenerateMenu() -- the menu is built when it opens
			for _, e in ipairs(self._entries) do
				if e.kind == "radio" and e.text:find(text, 1, true) then e.setSelected(e.data) return true end
			end
		end
	end
end

function CreateFrame(kind, name, parent, template)
	local f = setmetatable({ _scripts = {}, _units = {}, _alpha = 1, _shown = true, _parent = parent, _name = name, _kind = kind }, FrameMethods)
	if name then _G[name] = f end
	if parent then
		parent._children = parent._children or {}
		parent._children[#parent._children + 1] = f
	end
	allFrames[#allFrames + 1] = f
	if template then ApplyTemplate(f, template) end
	return f
end
UIParent = CreateFrame("Frame", "UIParent")
UISpecialFrames = {}
function ButtonFrameTemplate_HidePortrait(f) f._noPortrait = true end

-- Wall clock: a fixed day (2030-05-15 12:00) plus the mock's game time.
MOCK_EPOCH = os.time({ year = 2030, month = 5, day = 15, hour = 12, min = 0, sec = 0 })
function time(t) if t then return os.time(t) end return MOCK_EPOCH + math.floor(now) end
function date(fmt, t) return os.date(fmt, t or time()) end
function GetBuildInfo() return "1.60.1", "70205", "Jan 1 2030", 16001 end
function debugstack() return debug.traceback("", 2) end

-- Blizzard_ScriptErrorsFrame: every Lua error reaches DisplayMessageInternal (also with the error
-- display off), like through Blizzard's HandleLuaError.
CreateFrame("Frame", "ScriptErrorsFrame", UIParent)
SCRIPT_ERRORS = {}
function ScriptErrorsFrame:DisplayMessageInternal(message, messageType, stack)
	SCRIPT_ERRORS[#SCRIPT_ERRORS + 1] = { message = message, messageType = messageType, stack = stack }
end

ERRORS = {}
BLOCKED = {} -- protected calls the game would block (ADDON_ACTION_BLOCKED)
function geterrorhandler()
	return function(err)
		ERRORS[#ERRORS + 1] = tostring(err)
		io.write("    [error handler] " .. tostring(err) .. "\n")
		ScriptErrorsFrame:DisplayMessageInternal(tostring(err), 0, debug.traceback("", 2))
	end
end

function Fire(event, ...)
	local targets = {}
	for f in pairs(eventFrames[event] or {}) do targets[#targets + 1] = f end
	for _, f in ipairs(targets) do
		local units = f._units[event]
		local ok = true
		if units then
			ok = false
			for _, u in ipairs(units) do if u == select(1, ...) then ok = true end end
		end
		if ok and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
	end
end

function Advance(seconds, step)
	step = step or 1 / 60
	local target = now + seconds
	while now < target - 1e-9 do
		local dt = math.min(step, target - now)
		now = now + dt
		for i = #timers, 1, -1 do
			local t = timers[i]
			if t.at <= now then table.remove(timers, i); t.fn() end
		end
		for _, f in ipairs(allFrames) do
			if f._scripts.OnUpdate and f:IsVisible() then f._scripts.OnUpdate(f, dt) end -- like the game: visible frames only
		end
	end
end

-- game state knobs used by the tests
STATE = { combat = false, target = false, targetDead = false, hostile = true, cursor = nil, dead = false, moving = false, panel = nil, bags = false }
function InCombatLockdown() return STATE.combat end
function UnitAffectingCombat() return STATE.combat end
function UnitExists(u) return u == "target" and STATE.target end
function UnitIsDead() return STATE.targetDead end
function UnitCanAttack() return STATE.hostile end
function UnitIsDeadOrGhost() return STATE.dead end
function UnitIsGhost() return STATE.ghost == true end
function UnitName(unit)
	if unit == "player" then return "Lefthy" end
	if unit == "NPC" then return TRADE_PARTNER, TRADE_SURNAME end -- Forever: the second return is a surname
	if unit == "target" and STATE.target then return STATE.targetName or "Hogger" end
end
PLAYER_CLASS = "ROGUE"
function UnitClass(unit) if unit == "player" then return PLAYER_CLASS:sub(1, 1) .. PLAYER_CLASS:sub(2):lower(), PLAYER_CLASS end end
PLAYER_LEVEL = 19
function UnitLevel(unit) if unit == "player" then return PLAYER_LEVEL end end
SUBZONE = "Goldshire"
function GetSubZoneText() return SUBZONE end
ZONE = "Elwynn Forest"
function GetZoneText() return ZONE end
function GetRealZoneText() return INSTANCE and INSTANCE.name or ZONE end -- (inside an instance: its name, like the game)
function UnitRace(unit) if unit == "player" then return "Human", "Human", 1 end end
function UnitFactionGroup(unit) if unit == "player" then return "Alliance", "Alliance" end end
-- Stats: [index] = { base, effective } (Strength, Agility, Stamina, Intellect, Spirit); SECRET for a secret value.
-- Like the client: the value with gear and buffs twice, then the plus and minus parts (base = value - plus - minus).
STATS = { { 40, 45 }, { 60, 70 }, { 50, 58 }, { 25, 25 }, { 30, 32 } }
function UnitStat(unit, i)
	local s = unit == "player" and STATS[i]
	if s == SECRET then return SECRET, SECRET, 0, 0 end
	if s then return s[2], s[2], s[2] - s[1], 0 end
end
-- Spells: KNOWN_SPELLS[id] = true for spells the player knows; names and icons are made up.
KNOWN_SPELLS = {}
function IsPlayerSpell(id) return KNOWN_SPELLS[id] == true end
SPELL_NAMES = {} -- [id] = a name of its own (default "Spell <id>")
C_Spell = { GetSpellInfo = function(id) return { name = SPELL_NAMES[id] or ("Spell " .. id), iconID = 100000 + id, spellID = id } end }
function SetPortraitTexture(texture, unit) texture.portrait = unit end
-- A link clicked in chat (ItemRef.lua): nothing opens here.
LINKS_CLICKED = {}
function SetItemRef(link) LINKS_CLICKED[#LINKS_CLICKED + 1] = link end
-- Players this client knows (name cache): [guid] = { name, realm }.
KNOWN_PLAYERS = {}
function GetPlayerInfoByGUID(guid)
	local p = KNOWN_PLAYERS[guid]
	if p then return "Mage", "MAGE", "Human", "Human", 3, p[1], p[2] end
end
-- Dungeons that open at a level (the dungeon finder): [level] = { names }.
UNLOCKED_DUNGEONS = {}
C_PlayerInfo = { GetInstancesUnlockedAtLevel = function(level, isRaid)
	local ids = {}
	for i, name in ipairs(UNLOCKED_DUNGEONS[level] or {}) do if not isRaid then ids[#ids + 1] = level * 100 + i end end
	return ids
end }
function GetLFGDungeonInfo(id) local list = UNLOCKED_DUNGEONS[math.floor(id / 100)]; return list and list[id % 100] end
-- Talents as Forever has them: one trait tree, a node group per talent tree with its spent points.
-- TALENT_NODES[nodeID] = { group, row, col, spellID, maxRanks, ranks }; rows are 600 apart (posY).
TALENT_GROUPS = { { groupID = 1, displayName = "Assassination", icon = 501, orderIndex = 0 },
	{ groupID = 2, displayName = "Combat", icon = 502, orderIndex = 1 }, { groupID = 3, displayName = "Subtlety", icon = 503, orderIndex = 2 } }
TALENT_SPENT, TALENT_NODES = { 0, 0, 0 }, {}
for g = 1, 3 do
	for row = 1, 7 do
		for col = 1, 2 do
			TALENT_NODES[g * 1000 + row * 10 + col] = { group = g, row = row, col = col, spellID = 900000 + g * 1000 + row * 10 + col, maxRanks = col == 1 and 5 or 1 }
		end
	end
end
C_ClassTalents = { GetActiveConfigID = function() return 7 end }
C_Traits = {
	GetConfigInfo = function(id) return { ID = id, treeIDs = { 77 } } end,
	GetGroupDisplayInfoByTreeID = function() return TALENT_GROUPS end,
	GetGroupCurrencyInfo = function(_, ids)
		local out = {}
		for _, id in ipairs(ids) do out[#out + 1] = { traitNodeGroupID = id, currencyInfos = { { spent = TALENT_SPENT[id] } } } end
		return out
	end,
	GetTreeNodes = function()
		local ids = {}
		for id in pairs(TALENT_NODES) do ids[#ids + 1] = id end
		table.sort(ids)
		return ids
	end,
	GetNodeInfo = function(_, id)
		local n = TALENT_NODES[id]
		return n and { ID = id, posX = n.col * 600, posY = n.row * 600, groupIDs = { n.group }, entryIDs = { id }, maxRanks = n.maxRanks, ranksPurchased = n.ranks or 0 }
	end,
	GetEntryInfo = function(_, id) return { definitionID = id, maxRanks = 1 } end,
	GetDefinitionInfo = function(id) local n = TALENT_NODES[id]; return { spellID = n and n.spellID } end,
}
XP = { current = 1500, max = 6000, rested = 1200 }
function UnitXP(unit) return unit == "player" and XP.current or 0 end
function UnitXPMax(unit) return unit == "player" and XP.max or 0 end
function GetXPExhaustion() return XP.rested end
function UnitIsAFK(unit) return unit == "player" and STATE.afk == true end
-- Chronicle: realm, money, travel, target classification, instances, collections, professions.
function GetRealmName() return "Realmy" end
MONEY = 52000 -- 5g 20s
function GetMoney() return MONEY end
TRAVEL = { swimming = false, mounted = false, taxi = false, flying = false }
function IsSwimming() return TRAVEL.swimming end
function IsMounted() return TRAVEL.mounted end
function IsFlying() return TRAVEL.flying end
function UnitOnTaxi() return TRAVEL.taxi end
THREAT = {} -- nameplate unit -> UnitThreatSituation("player", unit): nil (not on its list), 0-3, or SECRET
function UnitThreatSituation(unit, mob) if unit == "player" then return THREAT[mob] end end
TARGET_CLASS = "normal"
function UnitClassification(unit) return unit == "target" and TARGET_CLASS or "normal" end
function UnitIsPlayer(unit) return unit == "player" end
function UnitIsTapDenied() return STATE.tapDenied == true end
INSTANCE = nil -- { name, type } while inside
function IsInInstance() if INSTANCE then return true, INSTANCE.type end return false, "none" end
function GetInstanceInfo() if INSTANCE then return INSTANCE.name, INSTANCE.type end return ZONE, "none" end
JUMPS = 0
function JumpOrAscendStart() JUMPS = JUMPS + 1 end
ITEMS = { [19019] = { name = "Thunderfury", quality = 5 }, [2589] = { name = "Linen Cloth", quality = 1 },
	[6948] = { name = "Hearthstone", quality = 1 }, [1179] = { name = "Ice Cold Milk", quality = 1 },
	[2075] = { name = "Priest's Mace", quality = 2 }, [1155] = { name = "Rod of the Sleepwalker", quality = 3 } }
C_Item = {
	GetItemQualityByID = function(id) return ITEMS[id] and ITEMS[id].quality end,
	GetItemIconByID = function(id) return ITEMS[id] and 1000 + id end,
	GetItemQualityColor = function(q) local hex = ({ [2] = "ff1eff00", [3] = "ff0070dd", [4] = "ffa335ee", [5] = "ffff8000" })[q] or "ffffffff"; return 1, 1, 1, hex end,
}
function ItemLink(id, count) -- what CHAT_MSG_LOOT carries
	local q = ITEMS[id].quality
	return ("|cnIQ%d:|Hitem:%d::::::::20:::::|h[%s]|h|r"):format(q, id, ITEMS[id].name)
end
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
-- Item clicks (HandleModifiedItemClick: every modified click on an item ends up here) and loading.
STATE.ctrl, STATE.shift = false, false
MOCK_BUTTON = "LeftButton"
DRESSUPS = 0
function HandleModifiedItemClick(link) if IsControlKeyDown() then DRESSUPS = DRESSUPS + 1 end return false end
function GetMouseButtonClicked() return MOCK_BUTTON end
function IsControlKeyDown() return STATE.ctrl == true end
function IsShiftKeyDown() return STATE.shift == true end
PENDING_ITEM_LOADS = {} -- items the client still has to ask the server for (MOCK_ITEM_UNCACHED)
Item = { CreateFromItemLink = function(_, itemLink)
	local id = tonumber(itemLink:match("item:(%d+)"))
	return {
		IsItemEmpty = function() return not ITEMS[id] end,
		ContinueOnItemLoad = function(_, callback)
			if MOCK_ITEM_UNCACHED == id then table.insert(PENDING_ITEM_LOADS, callback) else callback() end
		end,
	}
end }
C_Item.GetItemInfo = function(itemLink)
	assert(itemLink ~= nil, "Usage: local itemInfo = C_Item.GetItemInfo(itemInfo)") -- not nilable, like the game's
	local id = tonumber(tostring(itemLink):match("item:(%d+)"))
	if ITEMS[id] and MOCK_ITEM_UNCACHED ~= id then
		-- name, link, ..., the 14th: bindType (ITEMS[id].bind: 1 = on pickup, 2 = on equip)
		return ITEMS[id].name, ItemLink(id), ITEMS[id].quality, 1, 1, "", "", 1, "", 0, 0, 0, 0, ITEMS[id].bind or 0
	end
end
ITEMS[19019].bind, ITEMS[1155].bind = 1, 2 -- Thunderfury binds on pickup, the rod on equip
-- What the mouse is over (GetMouseFoci), worn items, and per bag slot: bound, tooltip lines.
MOCK_FOCUS, EQUIPPED, BOUND, BAG_TOOLTIP = nil, {}, {}, {}
function GetMouseFoci() return { MOCK_FOCUS } end
function GetInventoryItemLink(unit, slot) return unit == "player" and EQUIPPED[slot] and ItemLink(EQUIPPED[slot]) or nil end
-- Item locations (bag and slot, or an equipment slot), bound state and instance GUIDs per slot.
ITEM_GUIDS = {} -- [bag .. ":" .. slot] = guid; default "Item-<bag>-<slot>"
local locationMethods = {
	IsValid = function(s)
		if s.equip then return EQUIPPED[s.equip] ~= nil end
		return BAGS[s.bag] ~= nil and BAGS[s.bag][s.slot] ~= nil
	end,
	IsBagAndSlot = function(s) return s.bag ~= nil end,
	GetBagAndSlot = function(s) return s.bag, s.slot end,
	IsEquipmentSlot = function(s) return s.equip ~= nil end,
}
ItemLocation = {
	CreateFromBagAndSlot = function(_, bag, slot) return setmetatable({ bag = bag, slot = slot }, { __index = locationMethods }) end,
	CreateFromEquipmentSlot = function(_, slot) return setmetatable({ equip = slot }, { __index = locationMethods }) end,
}
C_Item.IsBound = function(loc) return loc.equip ~= nil or BOUND[loc.slot] == true end
C_Item.GetItemGUID = function(loc)
	if not loc.bag then return nil end
	return ITEM_GUIDS[loc.bag .. ":" .. loc.slot] or ("Item-" .. loc.bag .. "-" .. loc.slot)
end
BIND_TRADE_TIME_REMAINING ="You may trade this item with players that were also eligible to loot this item for the next %s."
C_TooltipInfo = { GetBagItem = function(bag, slot)
	local lines = {}
	for i, text in ipairs(BAG_TOOLTIP[slot] or {}) do lines[i] = { leftText = text } end
	return { lines = lines }
end }
C_MountJournal = { GetMountInfoByID = function(id) return id == 6 and "Brown Horse" or nil end }
C_PetJournal = { GetPetInfoByPetID = function() return 40, nil, 1, 0, 100, 1, false, "Black Kingsnake" end }
C_ToyBox = { GetToyInfo = function(id) return id, "Toy Train Set", 2000 end }
function GetAchievementInfo(id) return id, "Level 20", 10, true, 10, 3, 26, "", 0, 3000 end
PROFESSIONS = {} -- { { name, level }, ... }
function GetProfessions() return PROFESSIONS[1] and 1 or nil, PROFESSIONS[2] and 2 or nil end
function GetProfessionInfo(i) local p = PROFESSIONS[i]; if p then return p.name, 4000 + i, p.level, 300 end end
CAMERA = { spinning = false, stops = 0, zoom = 10 }
function MoveViewLeftStart(speed) CAMERA.spinning, CAMERA.speed = true, speed end
function MoveViewLeftStop() CAMERA.spinning, CAMERA.stops = false, CAMERA.stops + 1 end
function GetCameraZoom() return CAMERA.zoom end
function CameraZoomOut(d) CAMERA.zoom = CAMERA.zoom + d end
function CameraZoomIn(d) CAMERA.zoom = math.max(0, CAMERA.zoom - d) end
-- Flight paths: TakeTaxiNode(slot) is what the flight map calls; TAXI_NODES[slot] = "Place, Zone".
TAXI_NODES, TAXI_TAKEN = {}, {}
function TakeTaxiNode(slot) TAXI_TAKEN[#TAXI_TAKEN + 1] = slot end
function TaxiNodeName(slot) return TAXI_NODES[slot] end
-- The taxi map's nodes (C_TaxiMap.GetAllTaxiNodes): { name, state (0 = where you are), slotIndex, position }.
TAXI_MAP_ID, TAXI_MAP_NODES, MAP_SIZES = 1415, {}, { [1415] = { 10000, 10000 } }
function GetTaxiMapID() return TAXI_MAP_ID end
-- A flight's legs, as GetNumRoutes / TaxiGetNodeSlot tell: [destination slot] = { { from slot, to slot }, ... }.
TAXI_ROUTES = {}
function GetNumRoutes(slot) return TAXI_ROUTES[slot] and #TAXI_ROUTES[slot] or 0 end
function TaxiGetNodeSlot(slot, leg, isSource)
	local l = TAXI_ROUTES[slot] and TAXI_ROUTES[slot][leg]
	return l and (isSource and l[1] or l[2])
end
C_TaxiMap = { GetAllTaxiNodes = function(mapID) return mapID == TAXI_MAP_ID and TAXI_MAP_NODES or {} end }
SOUNDS = {}
function PlaySound(id) SOUNDS[#SOUNDS + 1] = id; return MOCK_SOUND_MISSING ~= id, #SOUNDS end -- willPlay, handle
STOPPED_SOUNDS = {}
function StopSound(handle) STOPPED_SOUNDS[#STOPPED_SOUNDS + 1] = handle end
function UnitInVehicle() return false end
function HasVehicleActionBar() return false end
function HasOverrideActionBar() return false end
function GetCursorInfo() return STATE.cursor end
function IsPlayerMoving() return STATE.moving end
function GetUIPanel(area) return STATE.panel == area and {} or nil end
function IsAnyBagOpen() return STATE.bags end
function GetCurrentKeyBoardFocus() return nil end
ACTIVE_CHAT_EDIT_BOX = nil

-- Settings API
REGISTERED_SETTINGS = {}
CATEGORIES = {}
LAYOUTS = {} -- category name -> the initializers added to its layout (rows on that page)
-- The base of a settings list row (Blizzard_Settings_Shared): Init keeps the row's data.
SettingsListElementMixin = { OnLoad = function() end, Init = function(self, initializer) self.data = initializer:GetData() end }
local function NewCategory(name, parent)
	local id = #CATEGORIES + 100
	local cat = { name = name, parent = parent, GetID = function() return id end }
	CATEGORIES[#CATEGORIES + 1] = cat
	LAYOUTS[name] = {}
	return cat, { AddInitializer = function(_, initializer) table.insert(LAYOUTS[name], initializer) end }
end
ADDON_CATEGORIES = {}
SUBCATEGORIES_USED = 0
Settings = {
	RegisterVerticalLayoutCategory = function(name) return NewCategory(name) end,
	RegisterVerticalLayoutSubcategory = function(parent, name)
		SUBCATEGORIES_USED = SUBCATEGORIES_USED + 1
		return NewCategory(name, parent)
	end,
	RegisterAddOnSetting = function(cat, variable, key, tbl, vtype, name, default)
		assert(type(tbl) == "table" and tbl[key] ~= nil, "setting table missing key " .. key)
		assert(vtype == type(default), "type mismatch for " .. variable)
		assert(not REGISTERED_SETTINGS[variable], "duplicate variable " .. variable)
		local s = { variable = variable, category = cat, name = name }
		function s:SetValueChangedCallback(fn) self.cb = fn end
		function s:GetValue() return tbl[key] end
		s.uiUpdates = 0 -- how often an open settings page would have been told about a change
		function s:SetValue(v)
			if tbl[key] ~= v then
				tbl[key] = v
				self.uiUpdates = self.uiUpdates + 1
				if self.cb then self.cb(self, v) end
			end
		end
		function s:NotifyUpdate()
			self.uiUpdates = self.uiUpdates + 1
			if self.cb then self.cb(self, tbl[key]) end
		end
		REGISTERED_SETTINGS[variable] = s
		return s
	end,
	CreateCheckbox = function(_, setting, tooltip) setting.tooltip = tooltip end,
	CreateSlider = function(_, setting, options, tooltip) setting.tooltip, setting.sliderOptions = tooltip, options end,
	CreateSliderOptions = function(minValue, maxValue, step)
		return { min = minValue, max = maxValue, step = step,
			SetLabelFormatter = function(self, _, fn) assert(type(fn(0.5)) == "string"); self.formatter = fn end }
	end,
	-- A setting with its own getter and setter (Builder:Choice keeps a value, the slider an index).
	RegisterProxySetting = function(cat, variable, vtype, name, default, getValue, setValue)
		assert(type(getValue) == "function" and type(setValue) == "function" and vtype == type(default), "bad proxy setting " .. variable)
		assert(not REGISTERED_SETTINGS[variable], "duplicate variable " .. variable)
		local s = { variable = variable, category = cat, name = name, proxy = true, uiUpdates = 0 }
		function s:SetValueChangedCallback(fn) self.cb = fn end
		function s:GetValue() return getValue() end
		function s:SetValue(v)
			if getValue() ~= v then
				setValue(v)
				self.uiUpdates = self.uiUpdates + 1
				if self.cb then self.cb(self, v) end
			end
		end
		function s:NotifyUpdate()
			self.uiUpdates = self.uiUpdates + 1
			if self.cb then self.cb(self, getValue()) end
		end
		REGISTERED_SETTINGS[variable] = s
		return s
	end,
	RegisterAddOnCategory = function(cat) ADDON_CATEGORIES[#ADDON_CATEGORIES + 1] = cat end,
	OpenToCategory = function(id) OPENED_CATEGORY = id end,
	CreateSettingInitializerData = function(setting, options, tooltip)
		return { setting = setting, name = setting.name, options = options or {}, tooltip = tooltip }
	end,
	CreateElementInitializer = function(template, data)
		return { template = template, data = data, GetData = function(self) return self.data end }
	end,
	CreateControlTextContainer = function()
		local c = { data = {} }
		function c:Add(value, label) self.data[#self.data + 1] = { value = value, label = label } end
		function c:GetData() return self.data end
		return c
	end,
	CreateDropdown = function(_, setting, options, tooltip)
		setting.tooltip = tooltip
		DROPDOWNS[setting.variable] = options()
	end,
	CreateSettingInitializer = function(template, data)
		data.setting.tooltip = data.tooltip
		TEXT_INPUTS[data.setting.variable] = { template = template, data = data }
		return { AddSearchTags = function() end }
	end,
}
TEXT_INPUTS = {}     -- variable -> { template, data } for Builder:TextInput
DROPDOWNS = {}       -- variable -> { { value, label }, ... }
-- Atlases the client has: retail's rogue combo points unless a test says otherwise.
C_Texture = { GetAtlasInfo = function(atlas)
	if MOCK_NO_RETAIL_ATLAS and atlas:find("^uf%-roguecp") then return nil end
	return { width = 20, height = 20 }
end }
CHECKBOX_SLIDERS = {} -- checkbox variable -> { checkbox, slider, cbLabel, sliderLabel } (one settings row)
function CreateSettingsCheckboxSliderInitializer(cbSetting, cbLabel, cbTooltip, sliderSetting, options, sliderLabel, sliderTooltip)
	cbSetting.tooltip, sliderSetting.tooltip = cbTooltip, sliderTooltip
	CHECKBOX_SLIDERS[cbSetting.variable] = { checkbox = cbSetting, slider = sliderSetting, cbLabel = cbLabel, sliderLabel = sliderLabel }
	return { AddSearchTags = function() end }
end
SETTINGS_BUTTONS = {} -- name -> { text, onClick, tooltip }
function CreateSettingsButtonInitializer(name, text, onClick, tooltip, addSearchTags)
	assert(addSearchTags ~= nil, "Blizzard asserts addSearchTags is given")
	SETTINGS_BUTTONS[name] = { text = text, onClick = onClick, tooltip = tooltip }
	return {}
end
MinimalSliderWithSteppersMixin = { Label = { Right = 2 } }
HEADERS = {}
function CreateSettingsListSectionHeaderInitializer(t) HEADERS[#HEADERS + 1] = t; return { t = t } end
SlashCmdList = {}

-- A representative slice of the Forever HUD
CreateFrame("Frame", "MainActionBar", UIParent)
MainMenuBar = MainActionBar -- alias: must not be adopted twice
CreateFrame("Frame", "MainMenuBarVehicleLeaveButton", MainActionBar)
CreateFrame("Frame", "MultiBarBottomLeft", UIParent)
CreateFrame("Frame", "PlayerFrame", UIParent)
PlayerFrame._alpha = 0.8 -- Edit Mode opacity 80%
CreateFrame("Frame", "TargetFrame", UIParent)
CreateFrame("Frame", "MinimapCluster", UIParent)
CreateFrame("Frame", "Minimap", MinimapCluster) -- engine-drawn quest blobs live in here
function ToggleMinimap() -- Blizzard_Minimap: the Toggle Minimap key
	if Minimap:IsShown() then Minimap:Hide() else Minimap:Show() end
end
CreateFrame("Frame", "BuffFrame", UIParent)
CreateFrame("Frame", "ObjectiveTrackerFrame", UIParent)
CreateFrame("Frame", "GeneralDockManager", UIParent)
CreateFrame("Frame", "ChatFrame1", UIParent)
CreateFrame("Frame", "ChatFrame1Tab", GeneralDockManager) -- docked tab: child of the dock
CreateFrame("Frame", "ChatFrame2", UIParent)
CreateFrame("Frame", "ChatFrame2Tab", UIParent) -- undocked tab
CHAT_FRAMES = { "ChatFrame1", "ChatFrame2" }
NOT_A_FRAME = "string global"
CreateFrame("Frame", "EditModeManagerFrame", UIParent)
EditModeManagerFrame:Hide()

-- XP/rep bars: containers start at alpha 0 (XML) and Blizzard fades them with
-- animations, i.e. the engine writes alpha without going through SetAlpha.
CreateFrame("Frame", "StatusTrackingBarManager", UIParent)
CreateFrame("Frame", "MainStatusTrackingBarContainer", StatusTrackingBarManager)
CreateFrame("Frame", "SecondaryStatusTrackingBarContainer", StatusTrackingBarManager)
MainStatusTrackingBarContainer._alpha = 0
SecondaryStatusTrackingBarContainer._alpha = 0
function AnimateAlpha(frame, value) frame._alpha = value end -- engine-side alpha change

-- A faded frame that starts at alpha 0 and gets revealed by an animation later.
CreateFrame("Frame", "DurabilityFrame", UIParent)
DurabilityFrame._alpha = 0
CreateFrame("Frame", "VehicleSeatIndicator", UIParent) -- also starts hidden by alpha
VehicleSeatIndicator._alpha = 0

-- CVars (status text)
CVARS = { statusText = "0", statusTextDisplay = "PERCENT", rotateMinimap = "0", cameraDistanceMaxZoomFactor = "1.9",
	questPOI = "1" } -- the world map's "quest objectives" filter
function GetCVar(k) return CVARS[k] end
function GetCVarBool(k) return CVARS[k] == "1" end
function SetCVar(k, v) CVARS[k] = tostring(v) end

MENUS_CLOSED = 0
Menu = { GetManager = function() return { CloseMenus = function() MENUS_CLOSED = MENUS_CLOSED + 1 end } end }

-- Bags: Blizzard re-anchors every shown bag to the bottom right whenever bags change.
CreateFrame("Frame", "ContainerFrameCombinedBags", UIParent)
ContainerFrameCombinedBags:Hide()
function ContainerFrameCombinedBags:IsCombinedBagContainer() return true end
function ContainerFrameCombinedBags:GetBagID() return 0 end
BAG_TITLE_ROUTER = CreateFrame("Button", nil, ContainerFrameCombinedBags)
BAG_TITLE_ROUTER.routeToSibling = "PortraitButton"
CreateFrame("Frame", "ContainerFrameContainer", UIParent)
CreateFrame("Frame", "ContainerFrame1", ContainerFrameContainer)
ContainerFrame1:Hide()
function ContainerFrame1:IsCombinedBagContainer() return false end
function ContainerFrame1:GetBagID() return 0 end
ContainerFrameContainer.ContainerFrames = { ContainerFrame1 }
-- The clean-up button: Blizzard puts it on the backpack (or the combined bags) and hides it in
-- gamepad mode (ContainerFrameMixin:UpdateSearchBox).
CreateFrame("Button", "BagItemAutoSortButton", UIParent)
BagItemAutoSortButton:Hide()
for _, f in ipairs({ ContainerFrameCombinedBags, ContainerFrame1 }) do
	function f:IsBackpack() return self == ContainerFrame1 end
	function f:UpdateSearchBox()
		if GAMEPAD_STATE.ui then
			BagItemAutoSortButton:ClearAllPoints()
			BagItemAutoSortButton:Hide()
		else
			BagItemAutoSortButton:SetParent(self)
			BagItemAutoSortButton:SetPoint("TOPRIGHT", self, "TOPRIGHT", -9, -34)
			BagItemAutoSortButton:Show()
		end
	end
end
ANCHOR_CALLS = 0
function UpdateContainerFrameAnchors()
	ANCHOR_CALLS = ANCHOR_CALLS + 1
	for _, f in ipairs({ ContainerFrameCombinedBags, ContainerFrame1 }) do
		if f:IsShown() then
			f:SetScale(MOCK_CONTAINER_SCALE or 1) -- Blizzard shrinks bags when many are open
			f:ClearAllPoints()
			f:SetPoint("BOTTOMRIGHT", f:GetParent(), "BOTTOMRIGHT", -10, 90)
		end
	end
end
function OpenBags() -- what Blizzard does when the bag opens
	ContainerFrameCombinedBags:Show()
	UpdateContainerFrameAnchors()
	if ContainerFrameCombinedBags.UpdateItems then ContainerFrameCombinedBags:UpdateItems() end
end
function CloseBags() ContainerFrameCombinedBags:Hide() end

-- Quest log: QUESTS = { { id, title, objectives = { { text, finished } } , complete, header } }
QUESTS = {}
local function FindQuest(id) for _, q in ipairs(QUESTS) do if q.id == id then return q end end end
C_QuestLog = {
	GetNumQuestLogEntries = function()
		local n = 0
		for _, q in ipairs(QUESTS) do if not q.collapsed then n = n + 1 end end
		return n, #QUESTS
	end,
	GetInfo = function(index) -- collapsed quests are not listed, like under a collapsed header
		local i = 0
		for _, q in ipairs(QUESTS) do
			if not q.collapsed then
				i = i + 1
				if i == index then return { questID = q.id, title = q.title, isHeader = false, isHidden = false } end
			end
		end
	end,
	GetQuestObjectives = function(id)
		local q = FindQuest(id)
		if not q then return nil end
		local list = {}
		for i, o in ipairs(q.objectives) do list[i] = { text = o.text, finished = o.finished } end
		return list
	end,
	IsComplete = function(id)
		local q = FindQuest(id)
		if not q then return false end
		if q.complete ~= nil then return q.complete end
		for _, o in ipairs(q.objectives) do if not o.finished then return false end end
		return true
	end,
	GetTitleForQuestID = function(id) local q = FindQuest(id); return q and q.title end,
	GetLogIndexForQuestID = function(id) return FindQuest(id) and 1 or nil end,
}
function GetQuestLink(id) local q = FindQuest(id); return q and ("[" .. q.title .. "]") end
-- The objective tracker: WATCHED = { questID, ... }; SUPER_TRACKED = the quest with the arrow (0 = none).
WATCHED, SUPER_TRACKED = {}, 0
C_QuestLog.GetQuestIDForQuestWatchIndex = function(i) return WATCHED[i] end
C_QuestLog.GetNumQuestWatches = function() return #WATCHED end
C_SuperTrack = {
	GetSuperTrackedQuestID = function() return SUPER_TRACKED end,
	SetSuperTrackedQuestID = function(id) SUPER_TRACKED = id end,
	ClearAllSuperTracked = function() SUPER_TRACKED = 0 end,
}
C_QuestLog.GetQuestWatchType = function(id) for _, w in ipairs(WATCHED) do if w == id then return 0 end end end
C_QuestLog.AddQuestWatch = function(id) if not C_QuestLog.GetQuestWatchType(id) then WATCHED[#WATCHED + 1] = id end end
C_QuestLog.RemoveQuestWatch = function(id)
	for i = #WATCHED, 1, -1 do if WATCHED[i] == id then table.remove(WATCHED, i) end end
end
GROUP = "none" -- "none" | "party" | "instance" | "raid"
LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2
function IsInRaid() return GROUP == "raid" end
function IsInGroup(category)
	if category == LE_PARTY_CATEGORY_INSTANCE then return GROUP == "instance" end
	return GROUP == "party" or GROUP == "raid"
end
SENT = {}
C_ChatInfo = {
	InChatMessagingLockdown = function() return STATE.chatLockdown == true end,
	SendChatMessage = function(msg, channel) SENT[#SENT + 1] = { msg = msg, channel = channel } end,
	RegisterAddonMessagePrefix = function(prefix) ADDON_PREFIXES[prefix] = true; return 0 end,
}
ADDON_PREFIXES = {}

-- Battle.net friends (Beacon). Anna and Bob are online in WoW; the rest must be ignored.
BNET_CLIENT_WOW, WOW_PROJECT_ID = "WoW", 1
local function WoWAccount(id, name, class, extra)
	local a = { gameAccountID = id, isOnline = true, clientProgram = "WoW", wowProjectID = 1, isInCurrentRegion = true,
		characterName = name, classFilename = class, characterLevel = 20, areaName = "Elwynn Forest",
		playerGuid = "Player-1-" .. id, isGameAFK = false, isGameBusy = false, realmName = "Realmy", factionName = "Alliance" }
	for k, v in pairs(extra or {}) do a[k] = v end
	return a
end
BN_FRIENDS = {
	{ WoWAccount(11, "Anna", "MAGE"), battleTag = "Annie#1234" },
	{ WoWAccount(12, "Bob", "WARRIOR"), battleTag = "Bobby#2345" },
	{ WoWAccount(13, "Carl", "ROGUE", { isOnline = false }), battleTag = "Carl#3456" },
	{ WoWAccount(14, "Dora", "PRIEST", { clientProgram = "App" }), battleTag = "Dora#4567" },
	{ WoWAccount(15, "Eve", "DRUID", { isInCurrentRegion = false }), battleTag = "Eve#5678" },
	{ WoWAccount(16, "Finn", "HUNTER"), battleTag = "Finn#6789" }, -- runs an older LefthyTools
}
function BNGetNumFriends() return #BN_FRIENDS, #BN_FRIENDS end
GAMEDATA = {} -- every C_BattleNet.SendGameData call that went through
MOCK_SEND_RESULT = nil -- set to 3 to make the server answer "throttled"
C_BattleNet = {
	GetFriendNumGameAccounts = function(i) return BN_FRIENDS[i] and #BN_FRIENDS[i] or 0 end,
	GetFriendGameAccountInfo = function(i, j) return BN_FRIENDS[i] and BN_FRIENDS[i][j] end,
	GetGameAccountInfoByID = function(id)
		for _, friend in ipairs(BN_FRIENDS) do
			for _, account in ipairs(friend) do if account.gameAccountID == id then return account end end
		end
	end,
	GetAccountInfoByGUID = function(guid)
		for _, friend in ipairs(BN_FRIENDS) do
			for _, account in ipairs(friend) do
				if account.playerGuid == guid then return { battleTag = friend.battleTag, gameAccountInfo = account } end
			end
		end
	end,
	SendGameData = function(id, prefix, data)
		if MOCK_SEND_RESULT then return MOCK_SEND_RESULT end
		GAMEDATA[#GAMEDATA + 1] = { id = id, prefix = prefix, data = data }
		return 0
	end,
}
Enum = { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, AddOnMessageLockdown = 11, TargetOffline = 12 } }
function GameDataTo(id, startIndex) -- messages sent to one account since startIndex
	local list = {}
	for i = startIndex or 1, #GAMEDATA do if GAMEDATA[i].id == id then list[#list + 1] = GAMEDATA[i].data end end
	return list
end

-- Classes, group, vectors
CLASS_RGB = { MAGE = { 0.25, 0.78, 0.92 }, WARRIOR = { 0.78, 0.61, 0.43 }, ROGUE = { 1, 0.96, 0.41 } }
C_ClassColor = { GetClassColor = function(c)
	local t = CLASS_RGB[c]
	if t then return { GetRGB = function() return t[1], t[2], t[3] end } end
end }
GROUP_GUIDS = {}
-- Only the C_PartyInfo version: the global IsGUIDInGroup is a deprecated fallback that clients
-- without "loadDeprecationFallbacks" don't have.
C_PartyInfo = { IsGUIDInGroup = function(guid) return GROUP_GUIDS[guid] == true end }
-- Group units: unit token -> { guid, continent, north, west } (their live position)
PARTY = {}
function UnitGUID(unit)
	if unit == "player" then return "Player-1-0" end
	if unit == "target" then return STATE.target and (STATE.targetGUID or "Creature-0-1") or nil end
	return PARTY[unit] and PARTY[unit].guid
end
function CreateVector2D(x, y)
	return { x = x, y = y, GetXY = function(self) return self.x, self.y end,
		SetXY = function(self, nx, ny) self.x, self.y = nx, ny end }
end
function CreateFromMixins(...)
	local t = {}
	for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do t[k] = v end end
	return t
end

-- Maps, in the real world-coordinate convention: a world vector is (north, west) in yards, so
-- north = top - y * height and west = left - x * width. A zone (1429) and its continent (1415)
-- on continent 0, and another continent (1414) on 1.
MAPS = {
	[1429] = { continent = 0, top = 1000, left = 1000, width = 1000, height = 1000 },
	[1415] = { continent = 0, top = 2000, left = 2000, width = 4000, height = 4000 },
	[1414] = { continent = 1, top = 2000, left = 2000, width = 4000, height = 4000 },
}
PLAYER_MAP, PLAYER_POS = 1429, { 0.5, 0.5 }
function WorldFromMap(mapID, x, y) -- -> continent, north, west
	local m = MAPS[mapID]
	return m.continent, m.top - y * m.height, m.left - x * m.width
end
C_Map = {
	GetBestMapForUnit = function() return PLAYER_MAP end,
	GetPlayerMapPosition = function(mapID, unit)
		if STATE.inInstance then return nil end
		local member = unit and unit ~= "player" and PARTY[unit]
		if member then -- works for party members too, on whatever map is asked for
			local m = MAPS[mapID]
			if not m or m.continent ~= member.continent then return nil end
			return CreateVector2D((m.left - member.west) / m.width, (m.top - member.north) / m.height)
		elseif unit and unit ~= "player" then
			return nil
		end
		return CreateVector2D(PLAYER_POS[1], PLAYER_POS[2])
	end,
	GetWorldPosFromMapPos = function(mapID, pos)
		local continent, north, west = WorldFromMap(mapID, pos.x, pos.y)
		return continent, CreateVector2D(north, west)
	end,
	GetMapPosFromWorldPos = function(continent, world, overrideMapID)
		local m = MAPS[overrideMapID]
		if not m or m.continent ~= continent then return nil end
		return overrideMapID, CreateVector2D((m.left - world.y) / m.width, (m.top - world.x) / m.height)
	end,
}
UNIT_POSITION_CALLS = 0
MOCK_UNITPOS_OFFSET = 0 -- non-zero: UnitPosition disagrees with the map route
function UnitPosition(unit)
	if STATE.inInstance then return nil end
	if PARTY[unit] then
		local member = PARTY[unit]
		return member.north, member.west, 0, member.continent
	end
	if unit ~= "player" then return nil end
	UNIT_POSITION_CALLS = UNIT_POSITION_CALLS + 1
	local continent, north, west = WorldFromMap(PLAYER_MAP, PLAYER_POS[1], PLAYER_POS[2])
	return north + MOCK_UNITPOS_OFFSET, west, 0, continent
end
FACING = 0
function GetPlayerFacing() return FACING end
MINIMAP_RADIUS = 100 -- yards from the centre to the edge
C_Minimap = { GetViewRadius = function() return MINIMAP_RADIUS end }
Minimap:SetSize(140, 140)

-- World map canvas with data providers and pooled pins, like MapCanvasMixin.
MapCanvasDataProviderMixin = {
	OnAdded = function(self, map) self.owningMap = map end,
	OnRemoved = function(self) self:RemoveAllData(); self.owningMap = nil end,
	GetMap = function(self) return self.owningMap end,
	RemoveAllData = function() end,
	RefreshAllData = function() end,
	OnMapChanged = function(self) self:RefreshAllData() end,
	OnShow = function() end, -- the canvas calls these when the map opens and closes
	OnHide = function() end,
}
MapCanvasPinMixin = {
	UseFrameLevelType = function(self, level) self.frameLevelType = level end,
	SetScalingLimits = function() end,
	SetIgnoreGlobalPinScale = function() end,
	SetPosition = function(self, x, y) self.x, self.y = x, y end,
	GetMap = function() return WorldMapFrame end,
	-- A click on a pin that takes clicks (the canvas wires OnMouseUp to this).
	OnClick = function(self, ...) if self.OnMouseClickAction then self:OnMouseClickAction(...) end end,
	-- Like MapCanvas_DataProviderBase.lua: SetPassThroughButtons is protected, so calling it from
	-- addon code in combat is blocked by the game.
	CheckMouseButtonPassthrough = function(self) self:SetPassThroughButtons() end,
	SetPassThroughButtons = function(self, ...)
		if InCombatLockdown() then BLOCKED[#BLOCKED + 1] = "SetPassThroughButtons" return end
		self._passThrough = { ... }
	end,
}
PIN_MIXINS = { LefthyToolsBeaconPinTemplate = "LefthyToolsBeaconPinMixin", LefthyToolsBeaconPingPinTemplate = "LefthyToolsBeaconPingPinMixin",
	LefthyToolsQuestMapPinTemplate = "LefthyToolsQuestMapPinMixin", LefthyToolsQuestAreaPinTemplate = "LefthyToolsQuestAreaPinMixin" }
-- The engine's quest area frame (QuestPOIFrame): pin.blobs = the quests it draws, for pin.mapID.
local QuestPOIFrameMethods = {
	SetMapID = function(self, mapID) self.mapID = mapID end,
	DrawNone = function(self) self.blobs = {} end,
	DrawBlob = function(self, questID, draw) if draw then self.blobs[#self.blobs + 1] = questID end end,
}
for _, m in ipairs({ "SetFillTexture", "SetBorderTexture", "SetFillAlpha", "SetBorderAlpha", "SetBorderScalar" }) do
	QuestPOIFrameMethods[m] = function() end
end
PIN_TYPES = { LefthyToolsQuestAreaPinTemplate = QuestPOIFrameMethods }
PINS = {} -- currently acquired pins
PINS_CREATED = 0
local pinPools = {} -- one pool per template, like MapCanvasMixin
CreateFrame("Frame", "SettingsPanel", UIParent):Hide()
CreateFrame("Frame", "WorldMapFrame", UIParent)
WorldMapFrame:Hide()
WorldMapFrame.mapID = 1429
WorldMapFrame.providers = {}
function WorldMapFrame:GetMapID() return self.mapID end
-- The canvas the pins sit on: 1000 x 1000 at scale 1, so on map 1429 (1000 yd wide) 1 yd = 1 pixel.
WorldMapFrame.canvas = CreateFrame("Frame", nil, WorldMapFrame)
WorldMapFrame.canvas:SetSize(1000, 1000)
function WorldMapFrame:GetCanvas() return self.canvas end
function WorldMapFrame:AddDataProvider(p) self.providers[p] = true; p:OnAdded(self) end
function WorldMapFrame:RemoveDataProvider(p) self.providers[p] = nil; p:OnRemoved(self) end
function WorldMapFrame:AcquirePin(template, ...)
	pinPools[template] = pinPools[template] or {}
	local pin = table.remove(pinPools[template])
	if not pin then
		pin = CreateFrame("Frame", nil, self)
		for k, v in pairs(PIN_TYPES[template] or {}) do pin[k] = v end
		for k, v in pairs(_G[PIN_MIXINS[template]]) do pin[k] = v end
		pin:OnLoad() -- the canvas calls OnLoad once, for new pins only
		PINS_CREATED = PINS_CREATED + 1
	end
	pin.pinTemplate = template
	PINS[#PINS + 1] = pin
	pin:Show()
	if pin.OnAcquired then pin:OnAcquired(...) end
	pin:CheckMouseButtonPassthrough("RightButton") -- Blizzard does this on every acquire
	return pin
end
function WorldMapFrame:RemovePin(pin)
	for i = #PINS, 1, -1 do if PINS[i] == pin then table.remove(PINS, i) end end
	pin:Hide()
	table.insert(pinPools[pin.pinTemplate], pin)
end
function WorldMapFrame:RemoveAllPinsByTemplate(template)
	for i = #PINS, 1, -1 do
		if PINS[i].pinTemplate == template then
			PINS[i]:Hide()
			table.insert(pinPools[template], table.remove(PINS, i))
		end
	end
end
function WorldMapFrame:Hide() -- closing the map: the canvas tells every provider
	local closing = self:IsShown()
	FrameMethods.Hide(self)
	if closing then for p in pairs(self.providers) do p:OnHide() end end
end
function PinsOf(template) -- the acquired pins of one template, in acquire order
	local list = {}
	for _, pin in ipairs(PINS) do if pin.pinTemplate == template then list[#list + 1] = pin end end
	return list
end
-- Canvas units: the mock canvas is 1000 x 1000.
function WorldMapFrame:DenormalizeHorizontalSize(size) return size * 1000 end
function WorldMapFrame:DenormalizeVerticalSize(size) return size * 1000 end
-- Clicks land on the canvas' scroll container; the cursor is in map coordinates (0-1).
WorldMapFrame.ScrollContainer = CreateFrame("Frame", nil, WorldMapFrame)
MOCK_CURSOR = { 0.5, 0.5 }
function WorldMapFrame:GetNormalizedCursorPosition() return MOCK_CURSOR[1], MOCK_CURSOR[2] end
function ClickWorldMap(button) -- what the engine does on mouse down over the map
	local onDown = WorldMapFrame.ScrollContainer._scripts.OnMouseDown
	if onDown then onDown(WorldMapFrame.ScrollContainer, button or "LeftButton") end
end
function IsAltKeyDown() return STATE.alt == true end
local MODIFIED_CLICKS = { CHATLINK = "shift", DRESSUP = "ctrl" } -- (the game's default bindings)
function IsModifiedClick(action)
	if MODIFIED_CLICKS[action] then return STATE[MODIFIED_CLICKS[action]] == true end
	return STATE.alt == true or STATE.ctrl == true or STATE.shift == true
end
MAP_NAMES = { [1429] = "Elwynn Forest", [1415] = "Eastern Kingdoms", [1414] = "Kalimdor" }
MAP_PARENTS, MAP_TYPES = { [1429] = 1415 }, { [1415] = 2, [1414] = 2, [1429] = 3 } -- 2 = continent, 3 = zone
MAP_LEVELS = { [1429] = { 1, 10 } }
C_Map.GetMapInfo = function(mapID)
	return MAP_NAMES[mapID] and { mapID = mapID, name = MAP_NAMES[mapID], parentMapID = MAP_PARENTS[mapID], mapType = MAP_TYPES[mapID] }
end
C_Map.GetMapWorldSize = function(mapID) local s = MAP_SIZES[mapID]; if s then return s[1], s[2] end return 0, 0 end
C_Map.GetMapLevels = function(mapID) local l = MAP_LEVELS[mapID]; if l then return l[1], l[2], 0, 0 end return 0, 0, 0, 0 end
C_Map.GetMapInfoAtPosition = function(mapID, x, y) -- the zone under a spot of a continent map
	if mapID == 1415 and x >= 0.25 and x <= 0.5 and y >= 0.25 and y <= 0.5 then return C_Map.GetMapInfo(1429) end
end
-- More maps for quests on the map: Westfall (another zone), Stormwind City (a zone inside Elwynn
-- Forest) and the world map above both continents. Enum.UIMapType as in the game.
Enum.UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 }
MAPS[1436] = { continent = 0, top = 0, left = 1500, width = 1000, height = 1000 }
MAPS[1453] = { continent = 0, top = 900, left = 900, width = 200, height = 200 }
MAP_NAMES[1436], MAP_NAMES[1453], MAP_NAMES[947] = "Westfall", "Stormwind City", "Azeroth"
MAP_PARENTS[1436], MAP_PARENTS[1453], MAP_PARENTS[1415], MAP_PARENTS[1414] = 1415, 1429, 947, 947
MAP_TYPES[1436], MAP_TYPES[1453], MAP_TYPES[947] = 3, 3, 1
-- Rectangles of one map on another: worked out from the world coordinates on one continent; the
-- world map has none, so the continents' rectangles on it are given (and zones aren't, as when
-- the game has no direct answer).
MAP_RECTS = { [1415] = { [947] = { 0.5, 0.9, 0.1, 0.7 } }, [1414] = { [947] = { 0.05, 0.4, 0.1, 0.8 } } }
C_Map.GetMapRectOnMap = function(mapID, topID)
	local r = MAP_RECTS[mapID] and MAP_RECTS[mapID][topID]
	if r then return r[1], r[2], r[3], r[4] end
	local m, top = MAPS[mapID], MAPS[topID]
	if mapID == topID or not (m and top and m.continent == top.continent) then return nil end
	return (top.left - m.left) / top.width, (top.left - m.left + m.width) / top.width,
		(top.top - m.top) / top.height, (top.top - m.top + m.height) / top.height
end
C_Map.GetMapChildrenInfo = function(mapID, mapType, allDescendants)
	local list = {}
	for id, parent in pairs(MAP_PARENTS) do
		local p = parent
		while allDescendants and p and p ~= mapID do p = MAP_PARENTS[p] end
		if p == mapID and (not mapType or MAP_TYPES[id] == mapType) then list[#list + 1] = C_Map.GetMapInfo(id) end
	end
	table.sort(list, function(x, y) return x.mapID < y.mapID end)
	return list
end
-- What each map's quest icons are: QUESTS_ON_MAP[mapID] = { { questID, x, y [, mapID] }, ... } (mapID: a
-- map inside it the quest is really on, like the game reports quests in a city on its zone).
QUESTS_ON_MAP = {}
C_QuestLog.GetQuestsOnMap = function(mapID)
	local list = {}
	for _, q in ipairs(QUESTS_ON_MAP[mapID] or {}) do
		list[#list + 1] = { questID = q[1], x = q[2], y = q[3], mapID = q[4] or mapID, isMapIndicatorQuest = false }
	end
	return list
end
SOUNDKIT = { MAP_PING = 3175, TELL_MESSAGE = 3081 }
function OpenWorldMap(mapID) -- the canvas refreshes every provider when it opens or changes map
	WorldMapFrame.mapID = mapID or WorldMapFrame.mapID
	local opening = not WorldMapFrame:IsShown()
	WorldMapFrame:Show()
	for p in pairs(WorldMapFrame.providers) do p:OnMapChanged() end
	if opening then for p in pairs(WorldMapFrame.providers) do p:OnShow() end end
end
TOOLTIP = { lines = {} }
GameTooltip = {
	SetOwner = function(_, owner) TOOLTIP = { lines = {}, owner = owner } end,
	SetText = function(_, text, r, g, b) TOOLTIP.title, TOOLTIP.color = text, { r, g, b } end,
	AddLine = function(_, text) TOOLTIP.lines[#TOOLTIP.lines + 1] = text end,
	Show = function() TOOLTIP.shown = true end,
	Hide = function() TOOLTIP.shown = false end,
	IsOwned = function(_, frame) return TOOLTIP.shown and TOOLTIP.owner == frame end,
	SetSpellByID = function(_, id) TOOLTIP.spell, TOOLTIP.title = id, "Spell " .. id end,
	SetBagItem = function(self, bag, slot) -- its data knows the copy (guid)
		local id = BAGS[bag] and BAGS[bag][slot]
		if id then self:SetHyperlink("item:" .. id, C_Item.GetItemGUID(ItemLocation:CreateFromBagAndSlot(bag, slot))) end
	end,
	SetHyperlink = function(self, link, guid)
		TOOLTIP.link, TOOLTIP.shown = link, true
		local id = tonumber(link:match("item:(%d+)"))
		for _, call in ipairs(TOOLTIP_POSTCALLS) do
			if id and call[1] == Enum.TooltipDataType.Item then call[2](self, { type = call[1], id = id, guid = guid }) end
		end
	end,
}
-- Tooltip post-calls: run by SetHyperlink before the tooltip is shown, as the game's data processor does.
TOOLTIP_POSTCALLS = {}
Enum.TooltipDataType = { Item = 0, Unit = 2 }
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) TOOLTIP_POSTCALLS[#TOOLTIP_POSTCALLS + 1] = { kind, fn } end }

-- Trading and mail: TRADE_PARTNER is "NPC" (its GUID via PARTY.NPC), TRADE_ITEMS / MAIL_ITEMS hold
-- my item links / item IDs per slot.
TRADE_PARTNER, TRADE_ITEMS, MAIL_ITEMS, MAILS_SENT = nil, {}, {}, {}
ERR_TRADE_COMPLETE = "Trade complete."
ATTACHMENTS_MAX_SEND = 12
-- Forever's GetUnitName adds the surname ("Anna Smith").
function GetUnitName(unit)
	local name, surname = UnitName(unit)
	return surname and (name .. " " .. surname) or name
end
function strcmputf8i(a, b) a, b = a:lower(), b:lower(); return a == b and 0 or (a < b and -1 or 1) end
function GetTradePlayerItemLink(slot) return TRADE_ITEMS[slot] end
function HasSendMailItem(slot) return MAIL_ITEMS[slot] ~= nil end
function GetSendMailItem(slot) if MAIL_ITEMS[slot] then return "Item", MAIL_ITEMS[slot] end end
function SendMail(recipient) MAILS_SENT[#MAILS_SENT + 1] = recipient end
SendMailFrame = CreateFrame("Frame", "SendMailFrame", UIParent)
SendMailFrame:Hide()
SendMailNameEditBox = CreateFrame("EditBox", "SendMailNameEditBox", SendMailFrame)
SendMailNameEditBox:SetText("")

-- Bag contents: BAGS[bag][slot] = itemID. The combined bag (above) gets a button per slot of bag 0;
-- Blizzard's UpdateItems runs over EnumerateValidItems whenever the bag opens or changes.
BAGS, SOLD, PICKED_UP = { [0] = {} }, {}, {}
C_Container = {
	GetContainerItemID = function(bag, slot) return BAGS[bag] and BAGS[bag][slot] end,
	GetContainerItemLink = function(bag, slot) local id = BAGS[bag] and BAGS[bag][slot]; return id and ItemLink(id) end,
	GetContainerItemInfo = function(bag, slot)
		local id = BAGS[bag] and BAGS[bag][slot]
		return id and { itemID = id, hyperlink = ItemLink(id), isBound = BOUND[slot] == true } or nil
	end,
	UseContainerItem = function(bag, slot) SOLD[#SOLD + 1] = BAGS[bag][slot]; BAGS[bag][slot] = nil end,
	PickupContainerItem = function(bag, slot) PICKED_UP[#PICKED_UP + 1] = BAGS[bag][slot] end,
}
C_Item.GetItemCount = function(itemID)
	local n = 0
	for _, slots in pairs(BAGS) do for _, id in pairs(slots) do if id == itemID then n = n + 1 end end end
	return n
end
ContainerFrameCombinedBags.buttons = {}
for slot = 1, 16 do
	local b = CreateFrame("Button", nil, ContainerFrameCombinedBags)
	b:SetSize(37, 37)
	b:SetID(slot)
	function b:GetBagID() return 0 end
	ContainerFrameCombinedBags.buttons[slot] = b
end
function ContainerFrameCombinedBags:EnumerateValidItems() return ipairs(self.buttons) end
function ContainerFrameCombinedBags:UpdateItems() end -- Blizzard's own drawing: nothing to do here

-- Personal resource display: Forever builds retail's combo point bar on it (RogueComboPointBarTemplate,
-- bound to the target): classFrame.classResourceButtonTable, a point per max combo point, each with
-- retail's textures; UpdatePower lights the gems (Blizzard animates them).
CreateFrame("Frame", "PersonalResourceDisplayFrame", UIParent)
PersonalResourceDisplayFrame:SetSize(200, 30)
PersonalResourceDisplayFrame.PowerBar = CreateFrame("StatusBar", nil, PersonalResourceDisplayFrame)
PersonalResourceDisplayFrame.PowerBar:SetSize(200, 10)
function PersonalResourceDisplayFrame:GetBarPadding() return 4 end
COMBO_POINT_PARTS = { "BGShadow", "BGActive", "BGInactive", "BGGlow", "IconUncharged", "FXUncharged", "FrameGlow", "SlashFBUncharged" }
function PersonalResourceDisplayFrame:SetupClassBar()
	local bar = self.classFrame
	if not bar then -- (built once, its UpdatePower from the template's mixin)
		bar = CreateFrame("Frame", nil, self)
		self.classFrame = bar
		function bar:UpdatePower()
			local points = GetComboPoints("player", "target")
			for i, point in ipairs(self.classResourceButtonTable) do point.IconUncharged:SetAlpha(i <= points and 1 or 0) end
		end
	end
	bar.classResourceButtonTable = {}
	for i = 1, COMBO.max do
		local point = CreateFrame("Frame", nil, bar)
		for _, key in ipairs(COMBO_POINT_PARTS) do point[key] = point:CreateTexture(nil, "ARTWORK") end
		bar.classResourceButtonTable[i] = point
	end
	bar:UpdatePower()
end
Enum.PowerType = { Mana = 0, Energy = 3, ComboPoints = 4 }
COMBO = { points = 0, max = 5 }
POWER_TYPE = 3 -- energy
function GetComboPoints(unit, target)
	if unit == "player" and target == "target" and STATE.target then return COMBO.points end
	return 0
end
function UnitPowerMax(unit, powerType) if powerType == Enum.PowerType.ComboPoints then return COMBO.max end return 100 end
function UnitPowerType() return POWER_TYPE, POWER_TYPE == 3 and "ENERGY" or "MANA" end

-- Quest log (QuestMapFrame's pooled title buttons) and the quest dialog.
NEW_CAPS = "NEW"
CreateFrame("Frame", "QuestScrollFrame", UIParent)
QUEST_LOG_BUTTONS = {} -- the active title buttons; ShowQuestLog() fills them like Blizzard does
QuestScrollFrame.titleFramePool = { EnumerateActive = function()
	local i = 0
	return function() i = i + 1; return QUEST_LOG_BUTTONS[i] end
end }
local spareTitleButtons = {}
function QuestLogQuests_Update() -- Blizzard: release all, then acquire a button per quest
	for _, b in ipairs(QUEST_LOG_BUTTONS) do b:Hide(); spareTitleButtons[#spareTitleButtons + 1] = b end
	wipe(QUEST_LOG_BUTTONS)
	for _, q in ipairs(QUESTS) do
		local b = table.remove(spareTitleButtons)
		if not b then
			b = CreateFrame("Button", nil, QuestScrollFrame)
			b.Text = b:CreateFontString()
			b.Checkbox = CreateFrame("Frame", nil, b)
		end
		b.questID = q.id
		b.Text:SetText(q.title)
		b:Show()
		QUEST_LOG_BUTTONS[#QUEST_LOG_BUTTONS + 1] = b
	end
end
CreateFrame("Frame", "QuestFrame", UIParent)
QuestFrame:Hide()
DIALOG_QUEST = nil
function GetQuestID() return DIALOG_QUEST end
SELECTED_QUEST = nil -- the quest whose details the quest log shows
C_QuestLog.GetSelectedQuest = function() return SELECTED_QUEST end
-- QuestInfo_Display fills the shared title for the quest window (detail, reward) and the log details.
CreateFrame("Frame", "QuestInfoFrame", UIParent)
QuestInfoTitleHeader = QuestInfoFrame:CreateFontString()
local function TitleOf(id) for _, q in ipairs(QUESTS) do if q.id == id then return q.title end end return "?" end
function QuestInfo_Display(template)
	QuestInfoFrame.questLog = template.questLog
	QuestInfoTitleHeader:SetText(TitleOf(template.questLog and SELECTED_QUEST or DIALOG_QUEST))
end
-- The "progress" page has its own title, set in its OnShow script.
CreateFrame("Frame", "QuestFrameProgressPanel", QuestFrame)
QuestProgressTitleText = QuestFrameProgressPanel:CreateFontString()
QuestFrameProgressPanel:Hide()
QuestFrameProgressPanel:SetScript("OnShow", function() QuestProgressTitleText:SetText(TitleOf(DIALOG_QUEST)) end)

-- Forever controller UI
CreateFrame("Frame", "GamepadMainActionBarFrame", UIParent)
CreateFrame("Frame", "GamepadMainActionBarFramePageUnit", GamepadMainActionBarFrame)
CreateFrame("Frame", "GamepadPersistentInputLegend", UIParent)
CreateFrame("Frame", "GamepadReticle", UIParent)
CreateFrame("Frame", "GamepadHudMode", UIParent)
GamepadHudMode:Hide()
CreateFrame("Frame", "GamepadRadial", UIParent)
GamepadRadial:Hide()
GAMEPAD_STATE = { hudMod = false, targetMod = false, ui = false }
InputUtil = { IsGamepadUIEnabled = function() return GAMEPAD_STATE.ui end } -- gamepad mode's UI
GamepadMode = {
	IsHUDBindingModifierDown = function() return GAMEPAD_STATE.hudMod end,
	IsTargetingModifierDown = function() return GAMEPAD_STATE.targetMod end,
}

-- The chat box (Blizzard_ChatFrameBase), cut down to its flow: ChatFrame1EditBox with a chat type
-- and a sticky type. TypeChat(text) types a line and presses Enter: a chat type command (/s, /g,
-- ...) switches the type, a slash command runs, anything else fires the pre-send event and goes to
-- the box's chat type (SENT_CHAT). TypeChatSpace(text) types up to a space (ParseText(0)).
NUM_CHAT_WINDOWS = 1
ChatTypeInfo = { SAY = { sticky = 1 }, GUILD = { sticky = 1 }, PARTY = { sticky = 1 }, CHANNEL = { sticky = 1 },
	WHISPER = { sticky = 0 } }
hash_ChatTypeInfoList = { ["/S"] = "SAY", ["/G"] = "GUILD", ["/P"] = "PARTY", ["/W"] = "WHISPER" }
EventRegistry = { callbacks = {} }
function EventRegistry:RegisterCallback(event, fn, owner)
	self.callbacks[event] = self.callbacks[event] or {}
	table.insert(self.callbacks[event], { fn, owner })
end
function EventRegistry:TriggerEvent(event, ...)
	for _, c in ipairs(self.callbacks[event] or {}) do c[1](c[2], ...) end
end
local chatBox = CreateFrame("EditBox", "ChatFrame1EditBox", ChatFrame1)
chatBox.chatFrame = ChatFrame1
chatBox._chatType, chatBox._sticky = "SAY", "SAY"
ChatFrame1EditBoxHeader = chatBox:CreateFontString()
ChatFrame1EditBoxHeaderSuffix = chatBox:CreateFontString()
function chatBox:GetChatType() return self._chatType end
function chatBox:SetChatType(t) self._chatType = t end
function chatBox:GetStickyType() return self._sticky end
function chatBox:SetStickyType(t) self._sticky = t end
function chatBox:UpdateHeader()
	ChatFrame1EditBoxHeader:SetText(self._chatType .. ": ")
	ChatFrame1EditBoxHeader:SetTextColor(1, 1, 1)
end
function chatBox:UpdateLanguageHeader() return 0 end
function chatBox:SetTextInsets(left) self._inset = left end
function chatBox:SetTextColor(r, g, b) self._color = { r, g, b } end
function chatBox:AddHistoryLine(text) self._history = text end
function chatBox:HandleChatType(msg, command, send)
	local chatType = hash_ChatTypeInfoList[command]
	if chatType then
		self:SetChatType(chatType)
		self:SetText(msg)
		self:UpdateHeader()
		return true
	end
	return false
end
function chatBox:ClearChat() self:SetChatType(self._sticky); self:SetText("") end
SENT_CHAT = {}
local function SlashHandler(command)
	for key, value in pairs(_G) do
		local name = type(key) == "string" and type(value) == "string" and key:match("^SLASH_(.-)%d+$")
		if name and value:upper() == command then return SlashCmdList[name] end
	end
end
local function Split(text)
	return (text:match("^(/[^%s]+)") or ""):upper(), text:match("^/[^%s]+%s+(.*)$") or ""
end
function TypeChat(text)
	chatBox:SetText(text)
	if text:sub(1, 1) == "/" then
		local command, msg = Split(text)
		if not chatBox:HandleChatType(msg, command, 1) then
			local handler = SlashHandler(command)
			if handler then
				handler(strtrim(msg), chatBox)
				chatBox:ClearChat()
				return
			end
		end
	end
	EventRegistry:TriggerEvent("ChatFrame.OnEditBoxPreSendText", chatBox)
	local line = chatBox:GetText()
	if line:find("%S") then SENT_CHAT[#SENT_CHAT + 1] = { type = chatBox:GetChatType(), text = line } end
	local info = ChatTypeInfo[chatBox:GetChatType()]
	if info and info.sticky == 1 then chatBox:SetStickyType(chatBox:GetChatType()) end
	chatBox:ClearChat()
end
function TypeChatSpace(text)
	chatBox:SetText(text)
	local command, msg = Split(text)
	chatBox:HandleChatType(msg, command, 0)
end

-- Mobs with a nameplate (Beacon's fight stream): MOBS["nameplate1"] = { name, level, class, dead,
-- combat, attacking (its target is me), casting, yards, x, y (its nameplate's spot, 0-1 across and
-- up the screen; nil: no nameplate frame), guid, north, west }. Range calls answer by yards. Like
-- retail, items don't answer for hostile units in combat, and CheckInteractDistance fails there.
-- A mob with a place in the world (north, west): its distance follows from where I stand, and its
-- nameplate unit exists only while it's on my screen (within 45 degrees of where I face, 41 yd).
MOBS = {}
local function Placed(mob) -- yards, on my screen, how far off ahead (radians)
	if not mob.north then return mob.yards, true, 0 end
	local n, w = UnitPosition("player")
	local east, up = w - mob.west, mob.north - n
	local c, s = math.cos(FACING), math.sin(FACING)
	local x, y = east * c + up * s, up * c - east * s
	local d, off = math.sqrt(x * x + y * y), math.abs(math.atan(x, y))
	return d, d <= 41 and off <= math.rad(45), off
end
function MobYards(mob) return (Placed(mob)) end
-- The soft target (gamepad mode): the mob on my screen nearest to straight ahead, within 20 degrees.
function SoftEnemy()
	local best, bestOff
	for u, mob in pairs(MOBS) do
		if u ~= "target" and mob.north then
			local _, on, off = Placed(mob)
			if on and off <= math.rad(20) and (not bestOff or off < bestOff) then best, bestOff = u, off end
		end
	end
	return best
end
local baseUnit = { UnitExists = UnitExists, UnitName = UnitName, UnitLevel = UnitLevel, UnitIsDead = UnitIsDead,
	UnitCanAttack = UnitCanAttack, UnitAffectingCombat = UnitAffectingCombat, UnitClassification = UnitClassification,
	UnitGUID = UnitGUID }
function UnitExists(u)
	if u == "softenemy" then return SoftEnemy() ~= nil end
	if MOBS[u] then return u == "target" or MOBS[u].pinned or select(2, Placed(MOBS[u])) end -- (pinned: kept on screen in combat)
	return baseUnit.UnitExists(u)
end
function UnitName(u) if MOBS[u] then return MOBS[u].name end return baseUnit.UnitName(u) end
function UnitLevel(u) if MOBS[u] then return MOBS[u].level end return baseUnit.UnitLevel(u) end
function UnitIsDead(u) if MOBS[u] then return MOBS[u].dead == true end return baseUnit.UnitIsDead(u) end
function UnitCanAttack(a, u) if MOBS[u] then return true end return baseUnit.UnitCanAttack(a, u) end
function UnitAffectingCombat(u) if MOBS[u] then return MOBS[u].combat == true end return baseUnit.UnitAffectingCombat(u) end
function UnitClassification(u) if MOBS[u] then return MOBS[u].class or "normal" end return baseUnit.UnitClassification(u) end
function UnitGUID(u) if MOBS[u] then return MOBS[u].guid or ("Creature-0-" .. u) end return baseUnit.UnitGUID(u) end
function UnitIsUnit(a, b)
	if b == "softenemy" then return SoftEnemy() == a end
	local mob = MOBS[(a:gsub("target$", ""))]
	if mob and a:find("target$") then return b == "player" and mob.attacking == true end
	return a == b
end
-- PLAYER_CAST = { name, icon, start, finish (ms) }: what I'm casting now.
function UnitCastingInfo(u)
	if u == "player" and PLAYER_CAST then return PLAYER_CAST.name, PLAYER_CAST.name, PLAYER_CAST.icon, PLAYER_CAST.start, PLAYER_CAST.finish end
	if MOBS[u] and MOBS[u].casting then return MOBS[u].casting end
end
function UnitChannelInfo() return nil end
function UnitHealth() return SECRET end -- (Forever: always secret)
function UnitHealthPercent() return SECRET end
function GetRaidTargetIndex() return SECRET end
function UnitReaction(u) if MOBS[u] then return 2 end end
function UnitCreatureType(u) if MOBS[u] then return "Humanoid", 7 end end
function GetScreenWidth() return 1920 end
function GetScreenHeight() return 1080 end
-- A nameplate's unit frame, like Forever's: the health bars and, right of them, the level frame.
function PlateUnitFrame(mob)
	if not mob.unitFrame then
		local uf = CreateFrame("Frame")
		uf.HealthBarsContainer = CreateFrame("Frame", nil, uf)
		uf.PlayerLevelDiffFrame = CreateFrame("Frame", nil, uf)
		mob.unitFrame = uf
	end
	return mob.unitFrame
end
C_NamePlate = { GetNamePlateForUnit = function(u) -- mob.plateError: reading its position fails, like on Forever
	local mob = MOBS[u]
	if not (mob and mob.x) then return nil end
	local function center()
		if mob.plateError then error(mob.plateError, 0) end
		return mob.x * 1920, mob.y * 1080
	end
	return { GetCenter = center, GetEffectiveScale = function() return 1 end, IsForbidden = function() return false end,
		IsVisible = function() return true end, GetLeft = function() return (center()) - 50 end,
		GetRect = function() local x, y = center(); return x - 50, y - 10, 100, 20 end, GetPoint = function() return "CENTER" end,
		UnitFrame = PlateUnitFrame(mob) }
end }
-- The spellbook: one line; harmful spells with their range (0: melee), one passive.
SPELL_RANGES = { [1752] = 0, [2764] = 30 } -- Sinister Strike, Throw
SPELL_NAMES[1752], SPELL_NAMES[2764] = "Sinister Strike", "Throw"
BOOK = { { spellID = 1752, itemType = 1, isPassive = false }, { spellID = 2764, itemType = 1, isPassive = false },
	{ spellID = 9999, itemType = 1, isPassive = true } }
C_SpellBook = C_SpellBook or {}
C_SpellBook.GetNumSpellBookSkillLines = function() return 1 end
C_SpellBook.GetSpellBookSkillLineInfo = function(i) if i == 1 then return { itemIndexOffset = 0, numSpellBookItems = #BOOK, shouldHide = false } end end
C_SpellBook.GetSpellBookItemInfo = function(slot) return BOOK[slot] end
local baseSpellInfo = C_Spell.GetSpellInfo
C_Spell.GetSpellInfo = function(id)
	local info = baseSpellInfo(id)
	info.minRange, info.maxRange = 0, SPELL_RANGES[id] or 0
	return info
end
C_Spell.IsSpellHarmful = function(id) return SPELL_RANGES[id] ~= nil end
C_Spell.IsSpellInRange = function(id, u)
	local mob = MOBS[u]
	if not (mob and MobYards(mob) and SPELL_RANGES[id]) then return nil end
	local range = SPELL_RANGES[id] > 0 and SPELL_RANGES[id] or 5
	return MobYards(mob) <= range
end
ITEM_RANGES = { [10645] = 20, [835] = 30, [18904] = 35 } -- the rest: items this client doesn't know
C_Item.RequestLoadItemDataByID = function() end
C_Item.IsItemInRange = function(id, u)
	local mob = MOBS[u]
	if not (mob and MobYards(mob) and ITEM_RANGES[id]) or STATE.combat then return nil end
	return MobYards(mob) <= ITEM_RANGES[id]
end
function CheckInteractDistance(u, i)
	if STATE.combat then error("CheckInteractDistance: blocked in combat") end
	local mob = MOBS[u]
	return mob ~= nil and MobYards(mob) ~= nil and MobYards(mob) <= ({ 28, 11, 10 })[i]
end
CVARS.cameraFov, CVARS.nameplateShowEnemies, CVARS.nameplateMaxDistance = "90", "1", "41"
-- Map art (the fight stream's map): one layer of 4 x 3 tiles of 256 px, like a classic zone;
-- NO_MAP_ART: a map without (the stream falls back to its plain rings).
C_Map.GetMapArtLayers = function(mapID)
	if MAPS[mapID] and not NO_MAP_ART then
		return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256, minScale = 1, maxScale = 1, additionalZoomSteps = 0 } }
	end
end
C_Map.GetMapArtLayerTextures = function(mapID)
	local list = {}
	for i = 1, 12 do list[i] = mapID * 100 + i end
	return list
end
