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
function FrameMethods:Show() self._shown = true end
function FrameMethods:Hide() self._shown = false end
function FrameMethods:IsMouseOver() return self._mouse == true end
function FrameMethods:IsForbidden() return false end
function FrameMethods:IsProtected() return false end
function FrameMethods:GetName() return self._name end
function FrameMethods:GetObjectType() return "Frame" end
-- positioning / dragging (bags)
function FrameMethods:SetScale(s) self._scale = s end
function FrameMethods:GetScale() return self._scale or 1 end
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
-- Animation groups. With SetToFinalAlpha(true), Play() jumps straight to the end state: each
-- target gets the toAlpha of its last-ending Alpha step (what the game shows once it's done).
local function NewAnimationGroup()
	local g = { playing = false, anims = {}, plays = 0 }
	function g:CreateAnimation(kind)
		local a = { kind = kind }
		function a:SetTarget(t) self.target = t end
		function a:SetFromAlpha(v) self.from = v end
		function a:SetToAlpha(v) self.to = v end
		function a:SetStartDelay(v) self.delay = v end
		function a:SetDuration(v) self.duration = v end
		function a:SetOrder() end
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
				if a.target and a.to ~= nil then
					local e = (a.delay or 0) + (a.duration or 0)
					if not ends[a.target] or e >= ends[a.target] then ends[a.target], last[a.target] = e, a.to end
				end
			end
			for target, alpha in pairs(last) do target:SetAlpha(alpha) end
		end
	end
	function g:Stop() self.playing = false end
	function g:IsPlaying() return self.playing end
	return g
end
function FrameMethods:CreateAnimationGroup() return NewAnimationGroup() end
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
	function t:CreateAnimationGroup() return NewAnimationGroup() end
	function t:SetAtlas(atlas) self.atlas, self.color = atlas, nil end
	function t:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a } end
	function t:SetBlendMode(mode) self.blend = mode end
	function t:ClearAllPoints() self.points = {} end
	function t:SetSize(w, h) self.width, self.height = w, h end
	function t:SetTexCoord(...) self.coords = { ... } end
	function t:SetDesaturated(d) self.desaturated = d end
	return t
end
function FrameMethods:CreateTexture() return NewTexture() end
function FrameMethods:CreateMaskTexture() return NewTexture() end
function FrameMethods:CreateFontString()
	local fs = {}
	function fs:SetAllPoints() end
	function fs:SetPoint() end
	function fs:SetText(text) self.text = text end
	function fs:GetText() return self.text end
	return fs
end

function CreateFrame(_, name, parent)
	local f = setmetatable({ _scripts = {}, _units = {}, _alpha = 1, _shown = true, _parent = parent, _name = name }, FrameMethods)
	if name then _G[name] = f end
	if parent then
		parent._children = parent._children or {}
		parent._children[#parent._children + 1] = f
	end
	allFrames[#allFrames + 1] = f
	return f
end
UIParent = CreateFrame("Frame", "UIParent")

ERRORS = {}
BLOCKED = {} -- protected calls the game would block (ADDON_ACTION_BLOCKED)
function geterrorhandler()
	return function(err)
		ERRORS[#ERRORS + 1] = tostring(err)
		io.write("    [error handler] " .. tostring(err) .. "\n")
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
	if unit == "target" and STATE.target then return STATE.targetName or "Hogger" end
end
PLAYER_CLASS = "ROGUE"
function UnitClass(unit) if unit == "player" then return PLAYER_CLASS:sub(1, 1) .. PLAYER_CLASS:sub(2):lower(), PLAYER_CLASS end end
function UnitLevel(unit) if unit == "player" then return 19 end end
SUBZONE = "Goldshire"
function GetSubZoneText() return SUBZONE end
SOUNDS = {}
function PlaySound(id) SOUNDS[#SOUNDS + 1] = id; return MOCK_SOUND_MISSING ~= id end
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
local function NewCategory(name, parent)
	local id = #CATEGORIES + 100
	local cat = { name = name, parent = parent, GetID = function() return id end }
	CATEGORIES[#CATEGORIES + 1] = cat
	return cat, { AddInitializer = function() end }
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
	CreateSlider = function(_, setting, _, tooltip) setting.tooltip = tooltip end,
	CreateSliderOptions = function() return { SetLabelFormatter = function(self, _, fn) assert(type(fn(0.5)) == "string") end } end,
	RegisterAddOnCategory = function(cat) ADDON_CATEGORIES[#ADDON_CATEGORIES + 1] = cat end,
	OpenToCategory = function(id) OPENED_CATEGORY = id end,
	CreateSettingInitializerData = function(setting, options, tooltip)
		return { setting = setting, name = setting.name, options = options or {}, tooltip = tooltip }
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
CVARS = { statusText = "0", statusTextDisplay = "PERCENT", rotateMinimap = "0" }
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
		playerGuid = "Player-1-" .. id, isGameAFK = false, isGameBusy = false }
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
	GetPlayerMapPosition = function(mapID)
		if STATE.inInstance then return nil end
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
	if unit ~= "player" or STATE.inInstance then return nil end
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
}
MapCanvasPinMixin = {
	UseFrameLevelType = function(self, level) self.frameLevelType = level end,
	SetScalingLimits = function() end,
	SetPosition = function(self, x, y) self.x, self.y = x, y end,
	-- Like MapCanvas_DataProviderBase.lua: SetPassThroughButtons is protected, so calling it from
	-- addon code in combat is blocked by the game.
	CheckMouseButtonPassthrough = function(self) self:SetPassThroughButtons() end,
	SetPassThroughButtons = function()
		if InCombatLockdown() then BLOCKED[#BLOCKED + 1] = "SetPassThroughButtons" end
	end,
}
PIN_MIXINS = { LefthyToolsBeaconPinTemplate = "LefthyToolsBeaconPinMixin" }
PINS = {} -- currently acquired pins
PINS_CREATED = 0
local pinPool = {}
CreateFrame("Frame", "WorldMapFrame", UIParent)
WorldMapFrame:Hide()
WorldMapFrame.mapID = 1429
WorldMapFrame.providers = {}
function WorldMapFrame:GetMapID() return self.mapID end
function WorldMapFrame:AddDataProvider(p) self.providers[p] = true; p:OnAdded(self) end
function WorldMapFrame:RemoveDataProvider(p) self.providers[p] = nil; p:OnRemoved(self) end
function WorldMapFrame:AcquirePin(template, ...)
	local pin = table.remove(pinPool)
	if not pin then
		pin = CreateFrame("Frame", nil, self)
		for k, v in pairs(_G[PIN_MIXINS[template]]) do pin[k] = v end
		pin:OnLoad() -- the canvas calls OnLoad once, for new pins only
		PINS_CREATED = PINS_CREATED + 1
	end
	pin.pinTemplate = template
	PINS[#PINS + 1] = pin
	pin:OnAcquired(...)
	pin:CheckMouseButtonPassthrough("RightButton") -- Blizzard does this on every acquire
	return pin
end
function WorldMapFrame:RemovePin(pin)
	for i = #PINS, 1, -1 do if PINS[i] == pin then table.remove(PINS, i) end end
	pinPool[#pinPool + 1] = pin
end
function WorldMapFrame:RemoveAllPinsByTemplate(template)
	for i = #PINS, 1, -1 do
		if PINS[i].pinTemplate == template then pinPool[#pinPool + 1] = table.remove(PINS, i) end
	end
end
function OpenWorldMap(mapID) -- the canvas refreshes every provider when it opens or changes map
	WorldMapFrame.mapID = mapID or WorldMapFrame.mapID
	WorldMapFrame:Show()
	for p in pairs(WorldMapFrame.providers) do p:OnMapChanged() end
end
TOOLTIP = { lines = {} }
GameTooltip = {
	SetOwner = function(_, owner) TOOLTIP = { lines = {}, owner = owner } end,
	SetText = function(_, text, r, g, b) TOOLTIP.title, TOOLTIP.color = text, { r, g, b } end,
	AddLine = function(_, text) TOOLTIP.lines[#TOOLTIP.lines + 1] = text end,
	Show = function() TOOLTIP.shown = true end,
	Hide = function() TOOLTIP.shown = false end,
	IsOwned = function(_, frame) return TOOLTIP.shown and TOOLTIP.owner == frame end,
}

-- Personal resource display (Forever leaves its class resource frame out) and combo points.
CreateFrame("Frame", "PersonalResourceDisplayFrame", UIParent)
PersonalResourceDisplayFrame:SetSize(200, 30)
PersonalResourceDisplayFrame.PowerBar = CreateFrame("StatusBar", nil, PersonalResourceDisplayFrame)
PersonalResourceDisplayFrame.PowerBar:SetSize(200, 10)
function PersonalResourceDisplayFrame:GetBarPadding() return 4 end
Enum.PowerType = { Mana = 0, Energy = 3, ComboPoints = 4 }
COMBO = { points = 0, max = 5 }
POWER_TYPE = 3 -- energy
function GetComboPoints(unit, target)
	if unit == "player" and target == "target" and STATE.target then return COMBO.points end
	return 0
end
function UnitPowerMax(unit, powerType) if powerType == Enum.PowerType.ComboPoints then return COMBO.max end return 100 end
function UnitPowerType() return POWER_TYPE, POWER_TYPE == 3 and "ENERGY" or "MANA" end

-- Forever controller UI
CreateFrame("Frame", "GamepadMainActionBarFrame", UIParent)
CreateFrame("Frame", "GamepadMainActionBarFramePageUnit", GamepadMainActionBarFrame)
CreateFrame("Frame", "GamepadPersistentInputLegend", UIParent)
CreateFrame("Frame", "GamepadReticle", UIParent)
CreateFrame("Frame", "GamepadHudMode", UIParent)
GamepadHudMode:Hide()
CreateFrame("Frame", "GamepadRadial", UIParent)
GamepadRadial:Hide()
GAMEPAD_STATE = { hudMod = false, targetMod = false }
GamepadMode = {
	IsHUDBindingModifierDown = function() return GAMEPAD_STATE.hudMod end,
	IsTargetingModifierDown = function() return GAMEPAD_STATE.targetMod end,
}
