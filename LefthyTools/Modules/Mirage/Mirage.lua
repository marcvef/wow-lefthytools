local _, ns = ...
local LT = ns.LT
local L = ns.L
local data = ns.MirageData

-- Mirage: fades the HUD when you're out of combat and idle (Dune: Awakening's
-- "Dynamic HUD"). Frame lists live in Groups.lua, settings UI in Options.lua.

local GetTime = GetTime
local min, max, abs = math.min, math.max, math.abs
local issecretvalue = issecretvalue or function() return false end

local defaults = {
	delay = 5,           -- seconds without activity before fading starts
	fadeOutTime = 1.5,   -- seconds a full fade-out takes
	fadeInTime = 0.25,   -- seconds a full fade-in takes
	fadedAlpha = 0,      -- opacity when faded (0 = invisible, like Dune); sets every groupAlpha
	groupAlpha = {},     -- per group: its opacity when faded
	mouseover = true,
	showWithTarget = true,
	hostileTargetOnly = false,
	showWithWindows = true,
	showWhenDead = true,
	showWhileMoving = false,
	showRegen = true,
	chatOnMessage = true,
	hideMinimapWhenFaded = true,
	minimapHideAt = 0,   -- minimap opacity at which it's hidden during the fade-out (0 = at the end)
	minimapButton = true, -- Options.lua: a button on the minimap that pauses fading
	minimapAngle = 185,  -- degrees, 0 = right, counter-clockwise: left, above Chronicle's book
	groups = {},
}
for _, g in ipairs(data.GROUPS) do
	defaults.groups[g.key] = g.default ~= false
	defaults.groupAlpha[g.key] = defaults.fadedAlpha
end

local M = LT:NewModule("mirage", {
	title = "Mirage",
	description = L["Fades the interface when you're out of combat and not using it, like Dune: Awakening's Dynamic HUD."],
	defaults = defaults,
	defaultEnabled = false, -- opt-in; a saved on/off choice always wins
})

local TICK = 0.1             -- how often visibility conditions are evaluated
local ENFORCE_INTERVAL = 1   -- re-assert faded alpha against animations we can't hook
local MOUSE_LINGER = 1       -- group stays visible this long after the cursor leaves
local CHAT_HOLD = 10
local REGEN_HOLD = 3         -- regen ticks arrive about every 2s
local QUEST_HOLD = 5
local XP_HOLD = 4
local ZONE_HOLD = 5

local db
local groups = data.GROUPS
local groupByKey = {}
for _, g in ipairs(groups) do
	groupByKey[g.key] = g
	g.live = {}          -- resolved frame objects
	g.hoverLive = {}     -- extra frames that only count for mouseover (never faded)
	g.alpha = 1          -- current fade multiplier
	g.from, g.to = 1, 1
	g.t, g.dur = 0, 0
	g.holdUntil = 0
end

-- Other parts hiding groups for a while (cinematic flights: M:HideGroups), with Mirage on or off:
-- owner -> { [group key] = true }. Hidden there beats everything else.
local overrides = {}
local pendingFade -- seconds for the fades the latest HideGroups call starts (nil: Mirage's own)

local function OverrideHidden(key)
	for _, set in pairs(overrides) do
		if set[key] then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------
-- Alpha ownership
--
-- Blizzard sets alpha on several of these frames itself (Edit Mode "Opacity"
-- settings, chat tab fading). We never overwrite that: a SetAlpha post-hook
-- records whatever anyone else sets as the frame's base alpha, and the frame
-- is drawn at base * group alpha. SetAlpha is not a protected function, so this
-- also works on secure frames in combat.
---------------------------------------------------------------------------

local base = setmetatable({}, { __mode = "k" })    -- frame -> alpha others want
local owner = setmetatable({}, { __mode = "k" })   -- frame -> group
local hooked = setmetatable({}, { __mode = "k" })
local secret = setmetatable({}, { __mode = "k" })  -- frames with a secret alpha; left alone
local lastSet = setmetatable({}, { __mode = "k" }) -- frame -> alpha we last applied
local applying = false

local function SetRaw(frame, value)
	applying = true
	local ok = pcall(frame.SetAlpha, frame, value)
	applying = false
	if ok then
		lastSet[frame] = value
	end
end

-- Alpha animations (e.g. Blizzard fades with setToFinalAlpha) change alpha inside the
-- engine without calling SetAlpha, so the hook never sees them. If a frame's alpha isn't
-- what we last applied, whatever changed it is Blizzard's intent: take it as the base.
-- Without this a base captured mid-animation (e.g. 0) would keep the frame hidden forever.
local function SyncBase(frame)
	local last = lastSet[frame]
	if last == nil then
		return
	end
	local ok, cur = pcall(frame.GetAlpha, frame)
	if ok and not issecretvalue(cur) and abs(cur - last) > 0.02 then
		base[frame] = cur
	end
end

local function OnSetAlpha(frame, alpha)
	if applying then
		return
	end
	if issecretvalue(alpha) then
		secret[frame] = true
		return
	end
	secret[frame] = nil
	base[frame] = alpha
	local g = owner[frame]
	if g and g.alpha < 1 then
		SetRaw(frame, alpha * g.alpha)
	end
end

local function Adopt(frame, g)
	if not hooked[frame] then
		hooked[frame] = true
		local a = frame:GetAlpha()
		if issecretvalue(a) then
			secret[frame] = true
		else
			base[frame] = a
		end
		-- Hooks can't be removed; once the module is disabled they only track the base alpha.
		hooksecurefunc(frame, "SetAlpha", OnSetAlpha)
	end
	owner[frame] = g
end

local function Release(frame)
	owner[frame] = nil
	if not secret[frame] then
		SyncBase(frame) -- an animation may have changed it while the group was fully visible
		SetRaw(frame, base[frame] or 1)
	end
end

---------------------------------------------------------------------------
-- Minimap quest areas
--
-- Quest/task/archaeology "blobs" are drawn by the engine inside the Minimap and
-- ignore frame alpha. Their own alpha setters (Minimap:SetQuestBlobInsideAlpha...)
-- have no getters and the engine defaults aren't known, so they could never be
-- restored exactly. Instead, the minimap fades out normally and, once its opacity
-- reaches db.minimapHideAt, the Minimap frame itself is hidden (taking the blobs
-- with it); it's shown again as soon as it fades back in. Blizzard's
-- ToggleMinimap() does the same Show/Hide; the frame isn't protected.
---------------------------------------------------------------------------

local minimapHiddenByUs = false
local hiddenForOverride = false -- hidden for another part (a cinematic flight's film), not a fade
-- The player pressed Toggle Minimap while we had it hidden. Blizzard's ToggleMinimap then shows
-- it (it looked hidden), but the player saw a faded minimap and meant "off".
local toggledWhileHidden = false

local function OnToggleMinimap()
	if (M.enabled or hiddenForOverride) and minimapHiddenByUs then
		toggledWhileHidden = true -- handled by the driver's next evaluation, not inside Blizzard's call
	end
end

local function SyncMinimap(g)
	local mm = Minimap
	if type(mm) ~= "table" or type(mm.Hide) ~= "function" then
		return
	end
	if mm:IsProtected() and InCombatLockdown() then
		return
	end
	if toggledWhileHidden then
		toggledWhileHidden = false
		if not hiddenForOverride then
			minimapHiddenByUs = false -- off by the player's choice now: hidden, but not by us, never shown again
		end
		-- (during a flight's film the player saw no interface at all: that press isn't "off for
		-- good"; hidden again for the film, its quest areas ignore alpha, and back after it)
		if mm:IsShown() then
			mm:Hide()
		end
		return
	end
	local override = OverrideHidden("minimap") and g.to == 0 and g.alpha <= 0 -- (its quest areas ignore alpha)
	local wantHidden = override or (M.enabled and db.hideMinimapWhenFaded and db.groups.minimap
		and db.groupAlpha.minimap == 0 and g.to == 0 and g.alpha <= db.minimapHideAt)
	if wantHidden then
		if not minimapHiddenByUs and mm:IsShown() then
			mm:Hide()
			minimapHiddenByUs = true
		end
		hiddenForOverride = minimapHiddenByUs and override
	elseif minimapHiddenByUs then
		minimapHiddenByUs, hiddenForOverride = false, false
		mm:Show()
	end
end

local function ApplyGroup(g)
	local a = g.alpha
	for i = 1, #g.live do
		local f = g.live[i]
		if not secret[f] then
			SyncBase(f)
			SetRaw(f, (base[f] or 1) * a)
		end
	end
	if g.key == "minimap" then
		SyncMinimap(g)
	end
end

---------------------------------------------------------------------------
-- Frame discovery
---------------------------------------------------------------------------

local function IsUsableFrame(f)
	return type(f) == "table"
		and type(f.SetAlpha) == "function"
		and type(f.GetParent) == "function"
		and not (f.IsForbidden and f:IsForbidden())
end

local function HasCandidateAncestor(frame, candidates)
	local p = frame:GetParent()
	while p do
		if candidates[p] then
			return true
		end
		p = p:GetParent()
	end
	return false
end

function M:Rebuild()
	local candidates, order = {}, {}
	for _, g in ipairs(groups) do
		local names = g.frames
		if type(names) == "function" then
			names = names()
		end
		for _, name in ipairs(names) do
			local f = _G[name]
			if IsUsableFrame(f) and not candidates[f] then
				candidates[f] = g
				order[#order + 1] = f
			end
		end
		wipe(g.live)
		wipe(g.hoverLive)
		for _, name in ipairs(g.hover or {}) do
			local f = _G[name]
			if IsUsableFrame(f) then
				g.hoverLive[#g.hoverLive + 1] = f
			end
		end
	end

	for _, f in ipairs(order) do
		if HasCandidateAncestor(f, candidates) then
			-- Already faded through its parent; fading it too would square the alpha.
			if owner[f] then
				Release(f)
			end
		else
			local g = candidates[f]
			Adopt(f, g)
			g.live[#g.live + 1] = f
		end
	end

	for f in pairs(owner) do
		if not candidates[f] then
			Release(f)
		end
	end

	for _, g in ipairs(groups) do
		ApplyGroup(g)
	end
end

-- Debounced; the rebuild itself runs from the OnUpdate driver (see below).
local rebuildAt
function M:RequestRebuild()
	if self.enabled and not rebuildAt then
		rebuildAt = GetTime() + 0.2
	end
end

---------------------------------------------------------------------------
-- Visibility conditions
---------------------------------------------------------------------------

local lastActivity = GetTime()
local castingCast, channeling = false, false
local peek = false
local paused = false -- the minimap button (or /mirage pause): everything stays visible until resumed
local reason              -- last global reason, for /mirage status
local reportedErrors = {}

local function ReportError(err)
	err = tostring(err)
	if not reportedErrors[err] then
		reportedErrors[err] = true
		M:Print("error while checking visibility (reported once): " .. err)
	end
end

local function AnyWindowOpen()
	if GetUIPanel then
		for _, area in ipairs(data.PANEL_AREAS) do
			if GetUIPanel(area) then
				return true
			end
		end
	end
	if IsAnyBagOpen and IsAnyBagOpen() then
		return true
	end
	for _, name in ipairs(data.WINDOWS) do
		local f = _G[name]
		if type(f) == "table" and f.IsShown and f:IsShown() then
			return true
		end
	end
	return false
end

local function HasTarget()
	if not UnitExists("target") or UnitIsDead("target") then
		return false
	end
	if db.hostileTargetOnly then
		return UnitCanAttack("player", "target")
	end
	return true
end

-- Holding a trigger/shoulder modifier brings up the controller bars or targeting,
-- so it counts as using the UI. Only reads Blizzard state; registering callbacks
-- with GamepadMode would run our code inside Blizzard's execution path.
local function ControllerInUse()
	local gm = GamepadMode
	if type(gm) == "table" then
		if type(gm.IsHUDBindingModifierDown) == "function" and gm.IsHUDBindingModifierDown() then
			return true
		end
		if type(gm.IsTargetingModifierDown) == "function" and gm.IsTargetingModifierDown() then
			return true
		end
	end
	for _, name in ipairs(data.CONTROLLER_WINDOWS) do
		local f = _G[name]
		if type(f) == "table" and f.IsShown and f:IsShown() then
			return true
		end
	end
	return false
end

local function InVehicle()
	return (UnitInVehicle and UnitInVehicle("player"))
		or (HasVehicleActionBar and HasVehicleActionBar())
		or (HasOverrideActionBar and HasOverrideActionBar())
end

-- Returns why the whole interface must be visible right now, or nil.
local function GlobalReason()
	if InCombatLockdown() or UnitAffectingCombat("player") then
		return "combat"
	end
	if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
		return "edit mode"
	end
	if ControllerInUse() then
		return "controller"
	end
	if GetCursorInfo() then
		return "dragging"
	end
	if castingCast or channeling then
		return "casting"
	end
	if InVehicle() then
		return "vehicle"
	end
	if db.showWhenDead and UnitIsDeadOrGhost("player") then
		return "dead"
	end
	if db.showWithTarget and HasTarget() then
		return "target"
	end
	if db.showWithWindows and AnyWindowOpen() then
		return "window open"
	end
	if db.showWhileMoving and IsPlayerMoving() then
		return "moving"
	end
	return nil
end

local function ChatActive()
	if ACTIVE_CHAT_EDIT_BOX then
		return true
	end
	local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
	local name = focus and focus.GetName and focus:GetName()
	return name ~= nil and name:find("^ChatFrame%d+EditBox$") ~= nil
end

local function AnyHovered(frames)
	for i = 1, #frames do
		local f = frames[i]
		if f:IsVisible() and f:IsMouseOver() then
			return true
		end
	end
	return false
end

local function GroupHovered(g)
	return AnyHovered(g.live) or AnyHovered(g.hoverLive)
end

-- One of our lists is open on the group (a minimap button's: it reaches past the minimap's edge,
-- and fading the minimap would fade the list with it): kept in view like an open window.
local function GroupPopup(g)
	local PopupOpenIn = LT.Window.PopupOpenIn
	if not (PopupOpenIn and LT.Window.AnyPopupOpen()) then
		return false
	end
	for i = 1, #g.live do
		if PopupOpenIn(g.live[i]) then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------
-- Fading
--
-- All frame work (alpha, minimap Show/Hide, rebuilds) happens in the OnUpdate
-- driver, never directly in an event handler or settings callback. Nearly every
-- event is a SynchronousEvent fired from inside engine code (e.g. PLAYER_STARTED_MOVING
-- from the movement update), so this is the safer place for UI changes.
-- Handlers only record state and call RequestEvaluate(), which runs on the next
-- frame. Blizzard's PlayerMovementFrameFader follows the same rule.
---------------------------------------------------------------------------

local function FadeTo(g, to, duration)
	if g.to == to then
		return
	end
	g.from, g.to, g.t = g.alpha, to, 0
	local full = duration or (to > g.alpha and db.fadeInTime or db.fadeOutTime)
	-- Partial fades (e.g. interrupted halfway) take proportionally less time.
	g.dur = full * abs(to - g.alpha)
end

local function Step(g, elapsed)
	g.t = g.t + elapsed
	local p = g.dur > 0 and min(1, g.t / g.dur) or 1
	if p >= 1 then
		g.alpha = g.to
	else
		p = p * p * (3 - 2 * p) -- smoothstep
		g.alpha = g.from + (g.to - g.from) * p
	end
	ApplyGroup(g)
end

local function Evaluate()
	local now = GetTime()

	local ok, r = pcall(GlobalReason)
	if not ok then
		ReportError(r)
		r = nil
	end
	reason = r
	if r then
		lastActivity = now
	end
	-- A reason (combat, target, window, ...) always keeps it visible, also with a delay of 0.
	local active = r ~= nil or (now - lastActivity) < db.delay

	local okChat, chatTyping = pcall(ChatActive)
	chatTyping = okChat and chatTyping

	local fade = pendingFade
	pendingFade = nil
	for _, g in ipairs(groups) do
		local show
		if OverrideHidden(g.key) then
			FadeTo(g, 0, fade)
		else
			if not M.enabled or peek or paused or not db.groups[g.key] then
				show = true
			else
				if db.mouseover then
					local okHover, hovered = pcall(GroupHovered, g)
					if okHover and hovered then
						g.holdUntil = max(g.holdUntil, now + MOUSE_LINGER)
					end
				end
				show = active or now < g.holdUntil or (g.key == "chat" and chatTyping) or GroupPopup(g)
			end
			FadeTo(g, show and 1 or db.groupAlpha[g.key], fade)
		end
	end
	-- Shows the minimap as soon as it starts fading in, and applies setting changes.
	SyncMinimap(groupByKey.minimap)
end

local driver = CreateFrame("Frame")
local sinceTick, sinceEnforce = 0, 0
local evaluatePending = false
local stopping = false -- disabled: finishing the fade-in before handing frames back

-- Evaluate on the next frame (from the driver), not in the caller's context.
local function RequestEvaluate()
	evaluatePending = true
end

local function FinishStopping()
	if next(overrides) then
		return -- another part still has groups hidden
	end
	for i = 1, #groups do
		local g = groups[i]
		if g.alpha ~= 1 or g.to ~= 1 then
			return
		end
	end
	for f in pairs(owner) do
		Release(f)
	end
	for _, g in ipairs(groups) do
		wipe(g.live)
	end
	SyncMinimap(groupByKey.minimap)
	stopping = false
	driver:SetScript("OnUpdate", nil)
end

local function OnUpdate(_, elapsed)
	if rebuildAt and GetTime() >= rebuildAt then
		rebuildAt = nil
		M:Rebuild()
	end

	sinceTick = sinceTick + elapsed
	if evaluatePending or sinceTick >= TICK then
		evaluatePending = false
		sinceTick = 0
		Evaluate()
	end

	for i = 1, #groups do
		local g = groups[i]
		if g.alpha ~= g.to then
			Step(g, elapsed)
		end
	end

	sinceEnforce = sinceEnforce + elapsed
	if sinceEnforce >= ENFORCE_INTERVAL then
		sinceEnforce = 0
		for i = 1, #groups do
			local g = groups[i]
			if g.alpha < 1 and g.alpha == g.to then
				ApplyGroup(g)
			end
		end
	end

	if stopping then
		FinishStopping()
	end
end

---------------------------------------------------------------------------
-- Public API (slash commands, settings, key bindings)
---------------------------------------------------------------------------

function M:Poke()
	lastActivity = GetTime()
end

function M:Pulse(key, seconds)
	local g = groupByKey[key]
	if g then
		g.holdUntil = max(g.holdUntil, GetTime() + seconds)
	end
end

function M:Refresh()
	if db and (self.enabled or stopping) then
		RequestEvaluate()
	end
end

-- "Faded opacity" sets every element's own faded opacity; each can then be changed on its own.
-- Through the settings, so an open settings page shows the new values.
local lastFadedAlpha
function M:OnSettingChanged()
	if db.fadedAlpha ~= lastFadedAlpha then
		lastFadedAlpha = db.fadedAlpha
		for _, g in ipairs(groups) do
			if db.groupAlpha[g.key] ~= db.fadedAlpha then
				LT:SetModuleSetting(self, "alpha_" .. g.key, db.fadedAlpha, db.groupAlpha, g.key)
			end
		end
	end
	self:Refresh()
	if self.UpdateButton then
		C_Timer.After(0, function() M:UpdateButton() end) -- (its checkbox)
	end
end

function M:SetPeek(down)
	if not self.enabled then
		return
	end
	peek = down and true or false
	if not peek then
		self:Poke()
	end
	self:Refresh()
end

function M:GetStatus()
	return {
		reason = reason,
		idleFor = GetTime() - lastActivity,
		peek = peek,
		paused = paused,
	}
end

-- Paused: nothing fades until resumed (the minimap button, /mirage pause). Not kept over a
-- restart: a forgotten pause would look like Mirage being broken.
function M:SetPaused(on)
	if not self.enabled then
		return
	end
	paused = on and true or false
	if not paused then
		self:Poke() -- (resuming starts the idle time over)
	end
	self:Refresh()
	if self.UpdateButton then
		self:UpdateButton()
	end
end

function M:IsPaused()
	return paused
end

function M:GetGroup(key)
	return groupByKey[key]
end

-- Another part hides some groups for a while (cinematic flights), whether Mirage is on or off:
-- hidden = { [group key] = true } or nil to give them back; fade = seconds for the change (0: at
-- once). With Mirage off the engine runs just for this and hands the frames back afterwards.
function M:HideGroups(ownerKey, hidden, fade)
	local set
	for key, on in pairs(hidden or {}) do
		if on and groupByKey[key] then
			set = set or {}
			set[key] = true
		end
	end
	overrides[ownerKey] = set
	pendingFade = fade
	if not db then
		return
	end
	if set and not driver:GetScript("OnUpdate") then
		self:Rebuild() -- Mirage is off: adopt the frames now
		driver:SetScript("OnUpdate", OnUpdate)
	end
	if not self.enabled and driver:GetScript("OnUpdate") then
		stopping = true -- once nothing is hidden any more, hand the frames back and go idle
	end
	RequestEvaluate()
end

function M:ResetSettings()
	LT:ResetModuleSettings(self)
	db.groupAlphaMigrated = true -- fresh settings: nothing to migrate at the next login
	self:Refresh()
end

---------------------------------------------------------------------------
-- Lifecycle and events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
local handlers = {}
local chatHooksInstalled = false

local EVENTS = {
	"ADDON_LOADED", "PLAYER_ENTERING_WORLD", "EDIT_MODE_LAYOUTS_UPDATED", "UPDATE_CHAT_WINDOWS",
	"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED", "CURSOR_CHANGED",
	"QUEST_WATCH_UPDATE", "QUEST_LOG_CRITERIA_UPDATE",
	"PLAYER_XP_UPDATE", "UPDATE_FACTION", "ZONE_CHANGED_NEW_AREA",
}
local PLAYER_EVENTS = {
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_SENT",
	"UNIT_SPELLCAST_SUCCEEDED", "UNIT_POWER_UPDATE",
}

function M:OnInitialize()
	db = self.db
	-- Settings from before per-element opacity: every element starts at the one faded opacity.
	if not db.groupAlphaMigrated then
		db.groupAlphaMigrated = true
		for key in pairs(db.groupAlpha) do
			db.groupAlpha[key] = db.fadedAlpha
		end
	end
	-- An element that comes with a later build starts at the player's faded opacity, like the
	-- others did (the defaults filled in its key with the default opacity before this runs).
	local first = type(db.groupsSeen) ~= "table" or next(db.groupsSeen) == nil -- (a reset empties it)
	db.groupsSeen = type(db.groupsSeen) == "table" and db.groupsSeen or {}
	for _, g in ipairs(data.GROUPS) do
		if not first and not db.groupsSeen[g.key] then
			db.groupAlpha[g.key] = db.fadedAlpha
		end
		db.groupsSeen[g.key] = true
	end
	lastFadedAlpha = db.fadedAlpha
end

function M:OnEnable()
	stopping = false
	if not chatHooksInstalled then
		chatHooksInstalled = true
		for _, name in ipairs({ "FCF_DockFrame", "FCF_UnDockFrame", "FCF_OpenTemporaryWindow", "FCF_Close" }) do
			if type(_G[name]) == "function" then
				hooksecurefunc(name, function() M:RequestRebuild() end)
			end
		end
		if type(ToggleMinimap) == "function" then
			hooksecurefunc("ToggleMinimap", OnToggleMinimap)
		end
	end

	for _, event in ipairs(EVENTS) do
		pcall(events.RegisterEvent, events, event)
	end
	for _, event in ipairs(data.CHAT_EVENTS) do
		pcall(events.RegisterEvent, events, event)
	end
	for _, event in ipairs(PLAYER_EVENTS) do
		pcall(events.RegisterUnitEvent, events, event, "player")
	end
	pcall(events.RegisterUnitEvent, events, "UNIT_HEALTH", "player", "pet")

	self:Poke()
	rebuildAt = 0 -- adopt frames on the next frame
	RequestEvaluate()
	driver:SetScript("OnUpdate", OnUpdate)
	C_Timer.After(0, function() if M.UpdateButton then M:UpdateButton() end end) -- (Options.lua)
end

function M:OnDisable()
	events:UnregisterAllEvents()
	peek, paused = false, false
	C_Timer.After(0, function() if M.UpdateButton then M:UpdateButton() end end)
	castingCast, channeling = false, false
	rebuildAt = nil
	-- Fade everything back in; FinishStopping() then hands the frames back and goes idle.
	stopping = true
	RequestEvaluate()
end

local function OnPlayerCastEvent(event)
	if event == "UNIT_SPELLCAST_START" then
		castingCast = true
	elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED" then
		castingCast = false
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
		channeling = true
	elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		channeling = false
	end
	M:Poke()
	RequestEvaluate()
end

-- Blizzard load-on-demand modules (raid frames, damage meter...) create frames late.
handlers.ADDON_LOADED = function() M:RequestRebuild() end

function handlers.PLAYER_ENTERING_WORLD()
	castingCast, channeling = false, false
	M:Poke()
	M:RequestRebuild()
end

handlers.EDIT_MODE_LAYOUTS_UPDATED = handlers.ADDON_LOADED
handlers.UPDATE_CHAT_WINDOWS = handlers.ADDON_LOADED

-- Reveal on the next frame instead of waiting for the next 0.1 s tick.
handlers.PLAYER_REGEN_DISABLED = RequestEvaluate

function handlers.PLAYER_REGEN_ENABLED()
	M:Poke() -- idle delay counts from the end of combat
end

handlers.PLAYER_TARGET_CHANGED = RequestEvaluate
handlers.CURSOR_CHANGED = RequestEvaluate

-- "While moving" is polled with IsPlayerMoving() in GlobalReason(), like Blizzard's
-- PlayerMovementFrameFader. PLAYER_STARTED_MOVING is deliberately not used.

handlers.UNIT_SPELLCAST_START = OnPlayerCastEvent
handlers.UNIT_SPELLCAST_STOP = OnPlayerCastEvent
handlers.UNIT_SPELLCAST_INTERRUPTED = OnPlayerCastEvent
handlers.UNIT_SPELLCAST_FAILED = OnPlayerCastEvent
handlers.UNIT_SPELLCAST_CHANNEL_START = OnPlayerCastEvent
handlers.UNIT_SPELLCAST_CHANNEL_STOP = OnPlayerCastEvent
handlers.UNIT_SPELLCAST_SENT = OnPlayerCastEvent
handlers.UNIT_SPELLCAST_SUCCEEDED = OnPlayerCastEvent

-- Health is a secret value for addons in Forever, so it can't be compared to max.
-- UNIT_HEALTH only fires while health changes, though, so "fired recently" means
-- "regenerating" (or taking damage) without ever reading the value.
function handlers.UNIT_HEALTH()
	if db.showRegen and not InCombatLockdown() then
		M:Pulse("unitframes", REGEN_HOLD)
	end
end

function handlers.UNIT_POWER_UPDATE(_, _, powerType)
	if db.showRegen and not InCombatLockdown()
		and not issecretvalue(powerType) and powerType == "MANA" then
		M:Pulse("unitframes", REGEN_HOLD)
	end
end

local function OnQuestProgress()
	M:Pulse("objectives", QUEST_HOLD)
end
handlers.QUEST_WATCH_UPDATE = OnQuestProgress
handlers.QUEST_LOG_CRITERIA_UPDATE = OnQuestProgress

local function OnXP()
	M:Pulse("xpbars", XP_HOLD)
end
handlers.PLAYER_XP_UPDATE = OnXP
handlers.UPDATE_FACTION = OnXP

function handlers.ZONE_CHANGED_NEW_AREA()
	M:Pulse("minimap", ZONE_HOLD)
end

local function OnChatMessage()
	if db.chatOnMessage then
		M:Pulse("chat", CHAT_HOLD)
	end
end
for _, event in ipairs(data.CHAT_EVENTS) do
	handlers[event] = OnChatMessage
end

events:SetScript("OnEvent", function(_, event, ...)
	local handler = handlers[event]
	if handler then
		handler(event, ...)
	end
end)
