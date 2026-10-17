local _, ns = ...
local LT = ns.LT
local L = ns.L

-- Misc Tweaks: small annoyances fixed, each switchable on its own. Tweaks default to on (chosen
-- while the Forever beta still dropped SavedVariables on restart), except retail unit frames
-- (friends may like Forever's look). This file holds the module, the tweaks' list and switching,
-- the settings page and /lefthy tweaks, plus a few small tweaks; the bigger ones have files of
-- their own (the TWEAKS list below says which).

local M = LT:NewModule("tweaks", {
	title = "Misc Tweaks", -- module names are never translated
	description = L["Small quality-of-life fixes, each one switchable on its own."],
	defaults = {
		statusText = true,
		movableBags = true,
		gamepadBagSort = true,
		bagPositions = {},     -- key ("combined" / "bag<id>") -> { left, top } in UIParent units
		savedStatusText = {},  -- CVar values to restore when statusText is switched off
		questAnnounce = true,
		comboNameplate = true, -- (comboPoints, our own row under the personal resource display, is gone: Blizzard has its own now)
		comboDotSize = 6,      -- the dots in the target's health bar: each one's size in pixels
		comboColors = true,
		aggroNameplate = true, -- Aggro.lua: in a group, who an enemy is on, on its nameplate
		retailFrames = false,  -- RetailFrames.lua: retail's unit frames instead of Forever's classic ones (off: Forever's own look)
		foreverQuests = true,
		questMap = true,       -- QuestMap.lua
		questMapContinent = "both", -- "off" | "icons" | "areas" | "both"
		questMapWorld = "both",
		questMapZone = "blizzard", -- "blizzard" (the selected quest's area) | "areas" (every quest's)
		questMapClick = true,  -- clicking an icon selects its quest (off: the map zooms in)
		afkScreen = true,      -- AFK.lua
		afkSpin = true,
		levelUp = true,        -- LevelUp.lua
		levelUps = {},         -- "Name-Realm" -> the last level-up's gains (the preview shows them)
		cinematicFlights = true, -- Flight.lua
		flightFriends = true,  -- Beacon friends in the top bar
		flightHide = "all",    -- "all": the whole interface | "chosen": the elements in flightGroups
		flightGroups = (function() -- Mirage's groups (Groups.lua), all hidden until unticked
			local hide = {}
			for _, g in ipairs(ns.MirageData.GROUPS) do
				hide[g.key] = true
			end
			return hide
		end)(),
	},
})

local active = {} -- tweak key -> currently applied
local lastDotSize  -- the combo dots' size before the latest setting change (OnSettingChanged)

-- The AFK screen used to be part of Mirage: a choice made there carries over once.
function M:OnInitialize()
	local mirage = LT.db.settings.mirage
	if type(mirage) == "table" and mirage.afkScreen ~= nil then
		self.db.afkScreen, self.db.afkSpin = mirage.afkScreen == true, mirage.afkSpin ~= false
		mirage.afkScreen, mirage.afkSpin, mirage.afkSpinning = nil, nil, nil
	end
	lastDotSize = self.db.comboDotSize -- (so the slider's first move after login shows the dots too)
end

---------------------------------------------------------------------------
-- Hiding the whole interface (the AFK screen, cinematic flights)
--
-- UIParent:SetAlpha, not Hide: SetAlpha isn't protected, so the interface can come back at any
-- moment, in combat too. Several tweaks may want it hidden at once (owner keys); it comes back,
-- to the alpha it had, when none does. fade: seconds to get there; an OnUpdate runs only then.
---------------------------------------------------------------------------

local hiders, restoreAlpha = {}, nil
local fader = CreateFrame("Frame")
fader:Hide()
local fadeFrom, fadeTo, fadeTime, fadeElapsed = 1, 1, 1, 0

local function CurrentAlpha()
	local alpha = UIParent:GetAlpha()
	return (type(alpha) == "number" and not (issecretvalue and issecretvalue(alpha))) and alpha or 1
end

fader:SetScript("OnUpdate", function(self, elapsed)
	fadeElapsed = fadeElapsed + elapsed
	local p = math.min(fadeElapsed / fadeTime, 1)
	UIParent:SetAlpha(fadeFrom + (fadeTo - fadeFrom) * p)
	if p >= 1 then
		self:Hide()
	end
end)

function ns.HideInterface(owner, hide, fade)
	local before = next(hiders) ~= nil
	hiders[owner] = hide and true or nil
	local now = next(hiders) ~= nil
	if before == now then
		return
	end
	if now and not fader:IsShown() then
		restoreAlpha = CurrentAlpha() -- (mid-fade back, the alpha from before still holds)
	end
	local target = now and 0 or (restoreAlpha or 1)
	if fade and fade > 0 then
		fadeFrom, fadeTo, fadeTime, fadeElapsed = CurrentAlpha(), target, fade, 0
		fader:Show()
	else
		fader:Hide()
		UIParent:SetAlpha(target)
	end
end

---------------------------------------------------------------------------
-- Shared by the tweaks (ns.TweakUtil): what several of them ask
---------------------------------------------------------------------------

local Util = {}
ns.TweakUtil = Util

-- In a fight (also the moment before the combat lockdown begins).
function Util.InCombat()
	return InCombatLockdown() or UnitAffectingCombat("player")
end

-- Typing: a chat box open, or anything else that has the keyboard.
function Util.ChatActive()
	return ACTIVE_CHAT_EDIT_BOX ~= nil or (GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() ~= nil)
end

-- How many windows are open: Blizzard's panels, the bags and the windows in Mirage's lists
-- (LefthyTools' own too, LT.Window.Register). The lists are Mirage's data: they work with Mirage off.
function Util.OpenWindows()
	local data = ns.MirageData
	local count = 0
	if GetUIPanel then
		for _, area in ipairs(data.PANEL_AREAS) do
			if GetUIPanel(area) then
				count = count + 1
			end
		end
	end
	if IsAnyBagOpen and IsAnyBagOpen() then
		count = count + 1
	end
	for _, name in ipairs(data.WINDOWS) do
		local f = _G[name]
		if type(f) == "table" and f.IsShown and f:IsShown() then
			count = count + 1
		end
	end
	return count
end

-- Seconds as "1:05" or "1:02:03", rounded (refreshed right on the second: 64.9999 is 65).
function Util.Clock(seconds)
	seconds = math.max(0, math.floor(seconds + 0.5))
	local h, m, s = math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60
	if h > 0 then
		return ("%d:%02d:%02d"):format(h, m, s)
	end
	return ("%d:%02d"):format(m, s)
end

-- A unit's nameplate ("target", "nameplate3"): its unit frame, if it has one addons may touch.
function Util.PlateFrame(unit)
	if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
		return nil
	end
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
	if not ok or not plate or (issecretvalue and issecretvalue(plate)) or (plate.IsForbidden and plate:IsForbidden()) then
		return nil
	end
	return plate.UnitFrame
end

-- The health bar of a nameplate's unit frame (its container can be taller than the bar).
function Util.PlateHealthBar(frame)
	local container = frame.HealthBarsContainer
	return frame.healthBar or (type(container) == "table" and container.healthBar) or container or frame
end

---------------------------------------------------------------------------
-- Always show health / power values on unit frames (statusText)
--
-- The bars show their text permanently when the CVar "statusText" is "1"
-- ("statusTextDisplay" picks the format). That's exactly what Blizzard's own
-- Options > Interface > Status Text dropdown sets. Using the CVars keeps
-- Blizzard's code untainted: health is a secret value in Forever, and forcing
-- the text per bar from addon code (bar:SetForceShow) would make Blizzard's
-- comparisons on those secrets run tainted and error.
---------------------------------------------------------------------------

local function ApplyStatusText(on)
	local saved = M.db.savedStatusText
	if on then
		if saved.statusText == nil then
			saved.statusText = GetCVar("statusText")
			saved.statusTextDisplay = GetCVar("statusTextDisplay")
		end
		-- Display mode first: the bars refresh on the "statusText" CVAR_UPDATE.
		SetCVar("statusTextDisplay", "NUMERIC")
		SetCVar("statusText", "1")
	elseif saved.statusText ~= nil then
		SetCVar("statusTextDisplay", saved.statusTextDisplay or "NUMERIC")
		SetCVar("statusText", saved.statusText)
		saved.statusText, saved.statusTextDisplay = nil, nil
	end
end

---------------------------------------------------------------------------
-- Switching tweaks on and off
---------------------------------------------------------------------------

-- Every tweak: its setting, its /lefthy tweaks word, its name in chat (English) and what switches
-- it (each gets the wanted state on the next frame; the files' ns.Apply... are looked up then).
-- /lefthy tweaks status lists them in this order.
local TWEAKS = {
	{ key = "statusText", command = "statustext", label = "Always show health & power values", apply = ApplyStatusText },
	{ key = "movableBags", command = "bags", label = "Movable bags",
		apply = function(on) ns.ApplyMovableBags(on) end }, -- Bags.lua
	{ key = "gamepadBagSort", command = "bagsort", label = "Clean-up button on the bags",
		apply = function(on) ns.ApplyGamepadBagSort(on) end }, -- Bags.lua
	{ key = "questAnnounce", command = "quests", label = "Announce quest progress in party chat",
		apply = function(on) ns.ApplyQuestAnnounce(on) end }, -- QuestAnnounce.lua
	{ key = "comboNameplate", command = "combo", label = "Combo points on your target's nameplate",
		apply = function(on) ns.ApplyComboNameplate(on) end }, -- ComboPoints.lua
	{ key = "comboColors", command = "combocolors", label = "Colour combo points by count",
		apply = function(on) ns.ApplyComboColors(on) end },
	{ key = "aggroNameplate", command = "aggro", label = "Who has aggro, on enemy nameplates",
		apply = function(on) ns.ApplyAggro(on) end }, -- Aggro.lua
	{ key = "retailFrames", command = "retailframes", label = "Retail unit frames",
		apply = function(on) ns.ApplyRetailFrames(on) end }, -- RetailFrames.lua
	{ key = "foreverQuests", command = "newquests", label = "Mark quests that are new in WoW: Forever",
		apply = function(on) ns.ApplyForeverQuests(on) end }, -- ForeverQuests.lua
	{ key = "questMap", command = "questmap", label = "Quests on continent and world maps",
		apply = function(on) ns.ApplyQuestMap(on) end }, -- QuestMap.lua
	{ key = "afkScreen", command = "afk", label = "AFK screen",
		apply = function(on) ns.ApplyAFKScreen(on) end }, -- AFK.lua
	{ key = "levelUp", command = "levelup", label = "Level-up window",
		apply = function(on) ns.ApplyLevelUp(on) end }, -- LevelUp.lua
	{ key = "cinematicFlights", command = "flights", label = "Cinematic flights",
		apply = function(on) ns.ApplyCinematicFlights(on) end }, -- Flight.lua
}

local function Reconcile()
	for _, tweak in ipairs(TWEAKS) do
		local want = M.enabled and M.db[tweak.key] == true
		if want ~= (active[tweak.key] == true) then
			local ok, err = pcall(tweak.apply, want)
			if ok then
				active[tweak.key] = want
			else
				geterrorhandler()(err)
			end
		end
	end
end

-- Applied on the next frame, not inside the caller (settings panel, login event).
local reconcilePending = false
local function RequestReconcile()
	if reconcilePending then
		return
	end
	reconcilePending = true
	C_Timer.After(0, function()
		reconcilePending = false
		Reconcile()
	end)
end

function M:OnEnable()
	RequestReconcile()
end

function M:OnDisable()
	RequestReconcile()
end

function M:OnSettingChanged()
	RequestReconcile()
	ns.RefreshQuestMap() -- what each zoom level shows
	-- The combo dots' size slider: they show on the target for a moment, at the new size.
	local size = self.db.comboDotSize
	if lastDotSize and size ~= lastDotSize and active.comboNameplate and ns.PreviewComboNameplate then
		ns.PreviewComboNameplate()
	end
	lastDotSize = size
end

function M:IsTweakActive(key)
	return active[key] == true
end

-- Who has aggro: examples on the enemy nameplates in sight (Aggro.lua).
function M:AggroPreview()
	if not active.aggroNameplate then
		self:Print("who has aggro on nameplates is off: /lefthy tweaks aggro switches it on.")
		return
	end
	local count = ns.AggroPreview()
	if count == 0 then
		self:Print("no enemy nameplates in sight: look at some mobs (with enemy nameplates on) and try again.")
	else
		self:Print(("examples of who has aggro on %d enemy nameplate(s), for ten seconds."):format(count))
	end
end

---------------------------------------------------------------------------
-- Settings page and /lefthy tweaks
---------------------------------------------------------------------------

function M:BuildOptions(o)
	o:Header(L["Unit frames"])
	o:Checkbox("statusText", L["Always show health & power values"],
		L["Show current / max on the health and power bars all the time instead of only on mouseover. Applies to every unit frame (player, target, focus, pet, party), like Blizzard's Options > Interface > Status Text set to Numeric."])
	o:Checkbox("retailFrames", L["Retail unit frames"],
		L["Since its latest patch Forever draws the player, target, focus, party and pet frames in a classic style. This brings back retail's: its art, bars and layout (the game still has them). Bars that move in combat follow when it ends. Switching it off takes a /reload."])
	o:Checkbox("comboColors", L["Colour combo points by count"],
		L["Blizzard's combo points on the personal resource display (and the dots on your target's nameplate): green with one point, through yellow and orange, to red at full points. Off: retail's red."])
	o:Checkbox("comboNameplate", L["Combo points on your target's nameplate"],
		L["Small dots in the middle of your target's health bar, one for each combo point you can have: lit ones in the colour of your points, the rest dark. Only while you have points on it. They take no room of their own, so nothing else on the nameplate moves. Rogues, and druids in Cat Form."])
	local function Pixels(v) return ("%d px"):format(math.floor((tonumber(v) or 0) + 0.5)) end
	o:Slider("comboDotSize", L["Combo dots: size"],
		L["Each dot's size in pixels. While you move the slider, they show on your target's nameplate for a few seconds."],
		4, 12, 1, Pixels)
	o:Button(L["Combo dots: preview"], L["Try it"], function() ns.ComboTrial(true) end,
		L["A small window with a nameplate whose dots count up like your points will; - and + change their size. No mob needed, and the settings can be closed. /lefthy tweaks combopos does the same."])
	o:Checkbox("aggroNameplate", L["Who has aggro, on enemy nameplates"],
		L["In a group, the left end of each enemy's health bar says whom it's on: >YOU< when it's you, else the first three letters of their name in the colour of their role (tank blue, healer green, damage red, white when not known). Roles come from the dungeon finder or a role check; in a group you made yourself, the leader can start one below."])
	o:Button(L["Start a role check"], L["Start"], function() M:Print(ns.AggroRoleCheck()) end,
		L["Everyone in your group picks tank, healer or damage in Blizzard's role check window, LefthyTools or not, and the aggro colours follow. Only the group's leader or an assistant can start one. /lefthy tweaks rolecheck does the same."])
	o:Button(L["Aggro on nameplates: preview"], L["Try it"], function() M:AggroPreview() end,
		L["For ten seconds the enemy nameplates you can see show examples: you, a tank, a healer, a damage dealer and someone without a role. /lefthy tweaks aggrotest does the same."])
	o:Header(L["Bags"])
	o:Checkbox("movableBags", L["Movable bags"],
		L["Drag a bag by its title bar or any empty spot to move it. It reopens where you left it. /lefthy tweaks resetbags puts all bags back."])
	o:Checkbox("gamepadBagSort", L["Clean-up button on the bags"],
		L["Since Forever's latest patch the bags' clean-up button is gone, with mouse and keyboard and in gamepad mode. This puts it back, at the left of the bags' search box."])
	o:Header(L["Quests"])
	o:Checkbox("questAnnounce", L["Announce quest progress in party chat"],
		L["When you finish a quest objective or a whole quest while in a party, your character posts it in party chat, like Questie does. Not solo and not in raids."])
	o:Checkbox("foreverQuests", L["Mark quests that are new in WoW: Forever"],
		L["WoW: Forever adds over a thousand quests to the Classic world, plus about as many from Classic's later seasons that original Classic never had. They get a NEW right after their name: in the quest log (hover for details), in the quest details and in the quest window when you accept or turn one in."])
	o:Checkbox("questMap", L["Quests on continent and world maps"],
		L["Blizzard's world map shows your quests only on zone maps. This shows them on continent maps and the world map too: an icon where to go (hover it for the objectives) and the area where the mobs and items are. Choose below what each zoom level shows. The map's own filter for quest objectives hides them as well."])
	local shown = { { "off", L["Nothing"] }, { "icons", L["Icons"] }, { "areas", L["Areas"] }, { "both", L["Icons and areas"] } }
	o:Choice("questMapContinent", L["On continent maps"],
		L["What continent maps like Kalimdor show of your quests. With icons only, hovering one shows its area."], shown)
	o:Choice("questMapWorld", L["On the world map"],
		L["What the map of the whole world shows of your quests."], shown)
	o:Checkbox("questMapClick", L["Click an icon to select its quest"],
		L["As on zone maps: clicking a quest's icon selects that quest (waypoint arrow, its area on the map, and it's tracked if it wasn't); clicking it again unselects it, Shift-click stops tracking it. Off: a click zooms into the zone. With a controller, the button always zooms in."])
	o:Choice("questMapZone", L["Quest areas on zone maps"],
		L["Blizzard shows only the area of your selected quest. All quests: the areas of every quest in the zone, like Questie."],
		{ { "blizzard", L["Selected quest"] }, { "areas", L["All quests"] } })
	o:Header(L["Level-ups"])
	o:Checkbox("levelUp", L["Level-up window"],
		L["Like in old RPGs: when you level up, a window shows what each stat gained, the new spells at your class trainer (hover one for its tooltip), talent points, a class quest that opens at this level and how long the last level took. It waits until a fight is over and closes by itself."])
	o:Button(L["Show the level-up window"], L["Preview"], function() ns.LevelUp.Preview() end,
		L["Shows the window for your current level, with the gains of your last level-up (example numbers if there was none yet). /levelup does the same."])
	o:Header(L["AFK screen"])
	o:Checkbox("afkScreen", L["AFK screen"],
		L["While you're AFK the interface disappears and a panel shows your character, how long you've been away, whispers, friends' news and which friends are online. Moving, combat, a ready check or a click brings everything back."])
	o:Checkbox("afkSpin", L["Circle the camera"],
		L["The camera slowly circles your character while the AFK screen is up."])
	o:Header(L["Flights"])
	o:Checkbox("cinematicFlights", L["Cinematic flights"],
		L["On a flight path the interface fades out, black bars slide in like in a film, and a title card names your destination and every zone you fly into. The bottom bar shows the time left to landing, and whispers and party chat show as subtitles. Opening a window or typing in chat pauses it until you're done; landing brings everything back."])
	o:Checkbox("flightFriends", L["Friends in the top bar"],
		L["The black bars show what your Beacon friends are doing, three lines each: their level and where they are, their quest, and whom they're fighting. Three fit in the top bar and three more in the bottom one; with more than six, they take turns."])
	o:Choice("flightHide", L["What a flight hides"],
		L["Everything: the whole interface, other addons included. Chosen elements: only the ones ticked below, the rest stays (other addons too). Works with Mirage on or off."],
		{ { "all", L["Everything"] }, { "chosen", L["Chosen elements"] } })
	for _, g in ipairs(ns.MirageData.GROUPS) do
		o:Checkbox(g.key, g.label, L["Hidden during flights (with \"Chosen elements\")."],
			{ tbl = self.db.flightGroups, default = true, id = "flightGroup_" .. g.key })
	end
end

function M:OnSlashCommand(msg)
	local cmd, arg = strsplit(" ", strtrim(msg or ""):lower(), 2)
	if cmd == "" then
		LT:OpenSettings(self)
	elseif cmd == "resetbags" then
		self:ResetBagPositions()
		self:Print("bag positions reset.")
	elseif cmd == "combopos" then
		ns.ComboTrial(true) -- ComboPoints.lua: the nameplate dots' preview, without a mob
	elseif cmd == "rolecheck" then
		self:Print(ns.AggroRoleCheck()) -- Aggro.lua
	elseif cmd == "aggrotest" then
		self:AggroPreview()
	elseif cmd == "levelup" and arg == "test" then
		ns.LevelUp.Preview()
	elseif cmd == "status" then
		for _, tweak in ipairs(TWEAKS) do
			self:Print(string.format("  %s%s|r (%s)", active[tweak.key] and "|cff80ff80" or "|cffff8080",
				tweak.label, tweak.command))
		end
	else
		for _, tweak in ipairs(TWEAKS) do
			if cmd == tweak.command then
				local on
				if arg == "on" then
					on = true
				elseif arg == "off" then
					on = false
				else
					on = not self.db[tweak.key]
				end
				LT:SetModuleSetting(self, tweak.key, on) -- the checkbox follows; OnSettingChanged reconciles
				self:Print(tweak.label .. (on and ": on." or ": off.")
					.. (self.enabled and "" or " (Misc Tweaks itself is off: /lefthy enable tweaks)"))
				return
			end
		end
		self:Print("/lefthy tweaks - open settings")
		self:Print("/lefthy tweaks status - list tweaks")
		self:Print("/lefthy tweaks statustext | bags | bagsort | quests | newquests | combo | combocolors | aggro | retailframes | questmap | afk | levelup | flights [on|off] - switch a tweak")
		self:Print("/levelup (or /lefthy tweaks levelup test) - show the level-up window for your current level")
		self:Print("/lefthy tweaks resetbags - move all bags back to Blizzard's spot")
		self:Print("/lefthy tweaks combopos - preview the combo point dots on nameplates (no mob needed)")
		self:Print("/lefthy tweaks aggrotest - examples of who has aggro on the enemy nameplates you see")
		self:Print("/lefthy tweaks rolecheck - start a role check (group leader or assistant)")
	end
end
