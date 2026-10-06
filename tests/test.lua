local failures, passes = 0, 0
local function check(cond, msg)
	if cond then passes = passes + 1 else failures = failures + 1; io.write("  FAIL: " .. msg .. "\n") end
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 0.01) end
local function a(name) return _G[name]:GetAlpha() end
local function section(t) io.write("\n== " .. t .. "\n") end

-- Globals that exist before the addon loads (the mock); anything new at the end must be ours.
local globalsBefore = {}
for k in pairs(_G) do globalsBefore[k] = true end

-- Load the addon like the client would: TOC order, each file gets (addonName, ns).
local ns = {}
for _, file in ipairs(SOURCES) do
	local chunk = assert(load(file.src, "@Interface/AddOns/LefthyTools/" .. file.name)) -- named like in game
	chunk("LefthyTools", ns)
end
Fire("ADDON_LOADED", "LefthyTools")
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD", true, false)
Advance(0.3) -- let the debounced rebuild run

local LT = LefthyTools
local Mirage = LT:GetModule("mirage")
local MDB = LefthyToolsDB.settings.mirage
local mirage = SlashCmdList.LEFTHYTOOLS_MIRAGE
local lefthy = SlashCmdList.LEFTHYTOOLS
local function S(id) return REGISTERED_SETTINGS["LefthyTools_mirage_" .. id] end

section("version")
check(LT.version == "0.4.0-3-gabc1234", "version comes from the installed TOC")
local function cmp(a, b) return LT.CompareVersions(a, b) end
check(cmp("0.4.0-5-gaaaaaaa", "0.4.0-3-gbbbbbbb") == 1 and cmp("0.4.0", "0.4.0-1-gaaaaaaa") == -1,
	"more commits since the same version = newer")
check(cmp("0.10.0", "0.9.9-40-gaaaaaaa") == 1 and cmp("1.0.0", "0.99.0") == 1, "numeric, not alphabetical")
check(cmp("0.4.0-gaaaaaaa", "0.4.0-3-gbbbbbbb") == nil and cmp("0.5.0-gaaaaaaa", "0.4.0-3-gbbbbbbb") == 1,
	"unknown commit count: only the base version can be compared")
check(cmp("0.4.0-2-gaaaaaaa-dirty", "0.4.0-1-gbbbbbbb") == 1 and cmp("garbage", "0.4.0") == nil, "dev builds and nonsense")
local versionMark = #PRINTED + 1
lefthy("version")
check(PRINTED[versionMark] and PRINTED[versionMark]:find("0.4.0-3-gabc1234", 1, true), "/lefthy version")

section("framework")
check(Mirage and not Mirage.enabled and LefthyToolsDB.modules.mirage == false, "Mirage is off by default (opt-in)")
check(LT:GetModule("tweaks").enabled and LT:GetModule("beacon").enabled, "the other modules are on by default")
lefthy("enable mirage")
Advance(0.3) -- let the debounced rebuild run
check(Mirage.enabled, "mirage switched on")
check(LefthyToolsDB.modules.mirage == true, "module switch saved in LefthyToolsDB.modules")
check(REGISTERED_SETTINGS.LefthyTools_module_mirage, "overview page has a switch for Mirage")
check(LT.category and LT.category.name == "LefthyTools", "LefthyTools overview category")
check(Mirage.category and Mirage.category.parent == LT.category and Mirage.category.name == "Mirage",
	"Mirage has its own sub-page under LefthyTools")
check(#ADDON_CATEGORIES == 1 and ADDON_CATEGORIES[1] == LT.category,
	"only the parent category is registered as an addon category")

section("error catcher")
local function errorRow() -- the overview's "Errors" info row
	for _, init in ipairs(LAYOUTS["LefthyTools"]) do
		if init.template == "LefthyToolsSettingsInfoTemplate" and init.data.name == "Errors" then return init.data.getValue() end
	end
end
local errorsBefore, emark = #ERRORS, #PRINTED + 1
check(LefthyToolsDB.errors and #LefthyToolsDB.errors == 0 and errorRow():find("None", 1, true), "no errors yet, the overview says so")
local ours = "Interface/AddOns/LefthyTools/Modules/Beacon/Beacon.lua:42: attempt to index a nil value (field 'peer')"
geterrorhandler()(ours)
geterrorhandler()(ours)
local kept = LefthyToolsDB.errors
check(#kept == 1 and kept[1].msg == ours and kept[1].count == 2 and kept[1].kind == "error" and kept[1].version == "0.4.0-3-gabc1234",
	"our error is kept once, counted twice, with the build it happened in")
geterrorhandler()("Interface/AddOns/SomeoneElse/Main.lua:1: oops")
check(#kept == 1, "another addon's error isn't ours")
ScriptErrorsFrame:DisplayMessageInternal("Interface/AddOns/Blizzard_MapCanvas/MapCanvas.lua:9: bad argument", 0,
	"[Interface/AddOns/Blizzard_MapCanvas/MapCanvas.lua]:9: in function 'AcquirePin'\n[Interface/AddOns/LefthyTools/Modules/Beacon/Dots.lua]:255: in function 'RefreshAllData'")
check(#kept == 2 and kept[2].stack:find("Dots.lua", 1, true), "a Blizzard error with our code in the stack is ours too")
ScriptErrorsFrame:DisplayMessageInternal(SECRET, 0, SECRET)
check(#kept == 2, "a secret error message is left alone")
Advance(0.05)
local notices = 0
for i = emark, #PRINTED do if PRINTED[i]:find("Type /lefthy errors", 1, true) then notices = notices + 1 end end
check(notices == 1, "one chat notice per session (not from inside the error handler), got " .. notices)
Fire("ADDON_ACTION_BLOCKED", "LefthyTools", "SetPassThroughButtons")
Fire("ADDON_ACTION_BLOCKED", "OtherAddon", "CastSpellByName")
check(#kept == 3 and kept[3].kind == "blocked" and kept[3].msg:find("SetPassThroughButtons", 1, true), "blocked actions of ours are kept too")
local function renderRow(name) -- an overview info row, built the way the settings list builds it
	for _, init in ipairs(LAYOUTS["LefthyTools"]) do
		if init.template == "LefthyToolsSettingsInfoTemplate" and init.data.name == name then
			local row = CreateFrame("Frame")
			for k, v in pairs(LefthyToolsSettingsInfoMixin) do row[k] = v end
			row.Value = row:CreateFontString()
			row:OnLoad()
			row:Init(init)
			return row
		end
	end
end
do
	local row = renderRow("Errors")
	check(row.Value:GetText():find("3", 1, true) and not row.Value:GetText():find("/lefthy", 1, true)
		and row.Button:IsShown() and row.Button:GetText() == "Show", "the overview shows how many, with a Show button (nothing to type)")
	row.Button:Click()
	check(LefthyToolsErrorsFrame and LefthyToolsErrorsFrame:IsShown(), "the button opens the error list")
	LefthyToolsErrorsFrame:Hide()
	check(not renderRow("Version").Button:IsShown(), "rows without a button don't show one")
end
lefthy("errors")
local errWindow = LefthyToolsErrorsFrame
local report = errWindow and errWindow.Box:GetText() or ""
check(errWindow and errWindow:IsShown(), "/lefthy errors opens the error window")
check(report:find("LefthyTools 0.4.0-3-gabc1234 | WoW 1.60.1.70205 (16001) | enUS", 1, true)
	and report:find("[1] blocked", 1, true) and report:find("[3] error, 2x", 1, true) and report:find(ours, 1, true),
	"the report: build, client, every error newest first, got\n" .. report)
check(not report:find("|c", 1, true), "plain text, no colour codes")
check(#UISpecialFrames > 0 and UISpecialFrames[#UISpecialFrames] == "LefthyToolsErrorsFrame", "Escape closes it")
for i = 1, 30 do geterrorhandler()("Interface/AddOns/LefthyTools/Core/Core.lua:" .. i .. ": test " .. i) end
check(#kept == 25 and kept[25].msg:find("test 30", 1, true) and not kept[1].msg:find(ours, 1, true), "at most 25 kept, the oldest go")
lefthy("errors clear")
check(#LefthyToolsDB.errors == 0 and errorRow():find("None", 1, true) and not renderRow("Errors").Button:IsShown(),
	"/lefthy errors clear (and the Show button goes)")
check(errWindow.Box:GetText():find("No errors.", 1, true), "the open window follows")
errWindow:Hide()
for i = #ERRORS, errorsBefore + 1, -1 do table.remove(ERRORS, i) end -- the test's own errors

section("discovery")
local ab = Mirage:GetGroup("actionbars")
check(#ab.live == 2, "actionbars should have MainActionBar + MultiBarBottomLeft (alias/child deduped), got " .. #ab.live)
local chat = Mirage:GetGroup("chat")
local names = {}
for _, f in ipairs(chat.live) do names[#names + 1] = f:GetName() end
io.write("  chat frames: " .. table.concat(names, ", ") .. "\n")
check(#chat.live == 4, "chat should have GeneralDockManager, ChatFrame1, ChatFrame2, ChatFrame2Tab (docked tab deduped)")
check(MDB.fadeOutTime == 1.5, "defaults applied")
check(S("fadeOutTime") and S("delay"), "timing sliders registered")
check(S("group_chat"), "group checkboxes registered")

section("XP bars and animation-driven alpha")
local xp = Mirage:GetGroup("xpbars")
check(#xp.live == 1 and xp.live[1] == StatusTrackingBarManager, "xpbars fades the manager, not Blizzard's animated containers")
check(#xp.hoverLive == 2, "the containers still count for mouseover")
AnimateAlpha(MainStatusTrackingBarContainer, 1) -- Blizzard fades the XP bar in (engine-side)
AnimateAlpha(DurabilityFrame, 1)                -- an animation reveals a frame Mirage adopted at alpha 0

section("idle fade")
check(near(a("MainActionBar"), 1) and near(a("PlayerFrame"), 0.8), "visible right after login (PlayerFrame keeps Edit Mode 80%)")
Advance(4.4) -- t = 4.7s since login
check(near(a("MainActionBar"), 1), "still visible before the 5s delay")
Advance(0.3 + 0.75) -- delay reached, ~half of the 1.5s fade
io.write(string.format("  mid-fade alpha: bar %.2f, player %.2f\n", a("MainActionBar"), a("PlayerFrame")))
check(a("MainActionBar") < 0.9 and a("MainActionBar") > 0.1, "mid-fade")
check(near(a("PlayerFrame") / 0.8, a("MainActionBar"), 0.02), "player frame fades proportionally to its base alpha")
Advance(1.0)
check(near(a("MainActionBar"), 0) and near(a("PlayerFrame"), 0) and near(a("ChatFrame1"), 0), "fully faded after the fade-out time")
check(near(a("StatusTrackingBarManager"), 0), "XP bars faded through their parent")
check(MainStatusTrackingBarContainer._setCount == nil and a("MainStatusTrackingBarContainer") == 1,
	"Mirage never touches the XP containers, so Blizzard's GetAlpha() logic still sees 1")

section("Blizzard changes alpha while faded")
PlayerFrame:SetAlpha(0.6) -- Edit Mode opacity slider moved to 60%
check(near(a("PlayerFrame"), 0), "stays hidden, new base is remembered")

section("combat reveals")
STATE.combat = true
local setsBefore, minimapBefore = MainActionBar._setCount, Minimap:IsShown()
Fire("PLAYER_REGEN_DISABLED")
check(MainActionBar._setCount == setsBefore and Minimap:IsShown() == minimapBefore,
	"no frame changes inside the event handler itself (deferred to the next frame)")
Advance(0.3)
check(near(a("MainActionBar"), 1), "action bars back in combat")
check(near(a("PlayerFrame"), 0.6), "player frame back at the new Edit Mode opacity (60%)")
check(near(a("DurabilityFrame"), 1), "a frame an animation revealed isn't stuck at its initial alpha 0")
check(near(a("StatusTrackingBarManager"), 1), "XP bars back in combat")
Advance(20)
check(near(a("MainActionBar"), 1), "stays visible during long combat")
STATE.combat = false
Fire("PLAYER_REGEN_ENABLED")
Advance(4.5)
check(near(a("MainActionBar"), 1), "lingers after combat")
Advance(2.5)
check(near(a("MainActionBar"), 0), "fades after combat + delay + fade")

section("mouseover reveals only its group")
PlayerFrame._mouse = true
Advance(0.4)
check(near(a("PlayerFrame"), 0.6), "hovered group revealed")
check(near(a("MainActionBar"), 0), "other groups stay faded")
PlayerFrame._mouse = false
Advance(0.5)
check(near(a("PlayerFrame"), 0.6), "lingers briefly after the mouse leaves")
Advance(3)
check(near(a("PlayerFrame"), 0), "fades again")
MainStatusTrackingBarContainer._mouse = true -- XP bar moved away from its parent in Edit Mode
Advance(0.4)
check(near(a("StatusTrackingBarManager"), 1), "hovering the XP bar itself reveals it")
MainStatusTrackingBarContainer._mouse = false
Advance(3)
check(near(a("StatusTrackingBarManager"), 0), "XP bar fades again")

section("chat message pulse")
Fire("CHAT_MSG_WHISPER", "hi", "Someone")
Advance(0.4)
check(near(a("ChatFrame1"), 1), "chat revealed by whisper")
check(near(a("MainActionBar"), 0), "action bars unaffected by chat")
Advance(12)
check(near(a("ChatFrame1"), 0), "chat fades after the hold")

section("regen pulse")
Fire("UNIT_HEALTH", "player")
Advance(0.4)
check(near(a("PlayerFrame"), 0.6), "player frame shown while health ticks")
Fire("UNIT_POWER_UPDATE", "player", "ENERGY")
Fire("UNIT_POWER_UPDATE", "player", SECRET)
Advance(5)
check(near(a("PlayerFrame"), 0), "energy/secret power events don't hold it")

section("target, windows, cursor, casting, edit mode")
local function reveals(label, set, clear)
	set(); Fire("PLAYER_TARGET_CHANGED"); Advance(0.4)
	check(near(a("MainActionBar"), 1), label .. " reveals")
	clear(); Fire("PLAYER_TARGET_CHANGED"); Advance(7)
	check(near(a("MainActionBar"), 0), label .. " fades after clearing")
end
reveals("target", function() STATE.target = true end, function() STATE.target = false end)
reveals("bag open", function() STATE.bags = true end, function() STATE.bags = false end)
reveals("ui panel", function() STATE.panel = "left" end, function() STATE.panel = nil end)
reveals("cursor item", function() STATE.cursor = "item" end, function() STATE.cursor = nil end)
reveals("edit mode", function() EditModeManagerFrame:Show() end, function() EditModeManagerFrame:Hide() end)
reveals("channel", function() Fire("UNIT_SPELLCAST_CHANNEL_START", "player") end, function() Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player") end)
STATE.target, STATE.targetDead = true, true
Fire("PLAYER_TARGET_CHANGED"); Advance(0.4)
check(near(a("MainActionBar"), 0), "dead target does not reveal")
STATE.target, STATE.targetDead = false, false

section("while moving (polled, no movement event)")
S("showWhileMoving"):SetValue(true)
Advance(0.3)
local setsBeforeMove = MainActionBar._setCount
Fire("PLAYER_STARTED_MOVING")
check(MainActionBar._setCount == setsBeforeMove, "PLAYER_STARTED_MOVING does nothing (moving is polled)")
STATE.moving = true; Advance(0.4)
check(near(a("MainActionBar"), 1) and Minimap:IsShown(), "moving reveals everything, minimap included, from the driver")
STATE.moving = false; Advance(7)
check(near(a("MainActionBar"), 0) and not Minimap:IsShown(), "fades again after stopping")
S("showWhileMoving"):SetValue(false)
STATE.moving = true; Advance(0.4)
check(near(a("MainActionBar"), 0), "moving doesn't reveal with the option off")
STATE.moving = false

section("controller UI")
local pad = Mirage:GetGroup("controller")
check(#pad.live == 2, "controller group has the bar cluster and legend (PageUnit child deduped), got " .. #pad.live)
check(near(a("GamepadMainActionBarFrame"), 0) and near(a("GamepadPersistentInputLegend"), 0), "controller bars and legend fade when idle")
check(MDB.groups.reticle == false and near(a("GamepadReticle"), 1), "aiming reticle stays visible by default")
GamepadMainActionBarFramePageUnit:SetAlpha(0.35) -- Blizzard dims the page unit while a flyout is open
check(GamepadMainActionBarFramePageUnit:GetAlpha() == 0.35, "Blizzard-managed child alpha is left alone")
GamepadMainActionBarFramePageUnit:SetAlpha(1)
GAMEPAD_STATE.targetMod = true; Advance(0.4)
check(near(a("GamepadMainActionBarFrame"), 1), "holding a targeting modifier reveals the controller bars")
GAMEPAD_STATE.targetMod = false; Advance(7)
check(near(a("GamepadMainActionBarFrame"), 0), "fades again after letting go")
reveals("HUD modifier", function() GAMEPAD_STATE.hudMod = true end, function() GAMEPAD_STATE.hudMod = false end)
reveals("HUD mode", function() GamepadHudMode:Show() end, function() GamepadHudMode:Hide() end)
reveals("radial menu", function() GamepadRadial:Show() end, function() GamepadRadial:Hide() end)
mirage("group reticle on")
Advance(0.1)
Advance(1.6)
check(near(a("GamepadReticle"), 0), "reticle fades once its group is enabled")
mirage("group reticle off")
Advance(0.4)

section("minimap quest areas")
Advance(8)
check(not Minimap:IsShown(), "minimap hidden once fully faded (takes the quest areas with it)")
STATE.combat = true
Fire("PLAYER_REGEN_DISABLED")
Advance(0.02)
check(Minimap:IsShown(), "shown on the very next frame when combat starts")
Advance(0.4)
STATE.combat = false
Fire("PLAYER_REGEN_ENABLED")
Advance(5 + 0.1 + 0.6)
check(Minimap:IsShown(), "still shown while the minimap is visibly fading")
Advance(0.65)
local tail = MinimapCluster:GetAlpha()
check(Minimap:IsShown() and tail > 0 and tail < 0.1,
	"still shown near the end of the fade (alpha " .. string.format("%.3f", tail) .. "), fades all the way down")
Advance(0.6)
check(not Minimap:IsShown(), "hidden again at the end of the fade")
STATE.target = true; Fire("PLAYER_TARGET_CHANGED"); Advance(0.4)
check(Minimap:IsShown(), "back when revealed")
Minimap:Hide() -- player presses Toggle Minimap
STATE.target = false; Fire("PLAYER_TARGET_CHANGED"); Advance(8)
STATE.target = true; Fire("PLAYER_TARGET_CHANGED"); Advance(0.4)
check(not Minimap:IsShown(), "a minimap the player turned off stays off")
Minimap:Show()
STATE.target = false; Fire("PLAYER_TARGET_CHANGED"); Advance(8)
mirage("alpha 20"); Advance(0.5)
check(Minimap:IsShown(), "not hidden when faded opacity is above 0% (it's still partly visible)")
mirage("alpha 0"); Advance(3)
check(not Minimap:IsShown(), "hidden again at 0%")
ToggleMinimap() -- the player presses Toggle Minimap while Mirage has it hidden (Blizzard shows it)
check(Minimap:IsShown(), "(Blizzard's ToggleMinimap showed it)")
Advance(0.15)
check(not Minimap:IsShown(), "Toggle Minimap while faded means off: no invisible minimap with quest areas")
STATE.target = true; Fire("PLAYER_TARGET_CHANGED"); Advance(0.4)
check(not Minimap:IsShown(), "... and it stays off when the HUD comes back: the player's choice")
ToggleMinimap()
check(Minimap:IsShown(), "the next press turns it on again")
STATE.target = false; Fire("PLAYER_TARGET_CHANGED"); Advance(8)
check(not Minimap:IsShown(), "and Mirage hides it with the fade again")
S("hideMinimapWhenFaded"):SetValue(false)
Advance(0.02)
check(Minimap:IsShown(), "turning the option off shows it right away")
S("hideMinimapWhenFaded"):SetValue(true)
Advance(0.02)
check(not Minimap:IsShown(), "turning it back on hides it again")
mirage("group minimap off")
Advance(0.02)
check(Minimap:IsShown(), "excluding the minimap group shows it")
mirage("group minimap on")
Advance(3)
check(S("minimapHideAt"), "quest area threshold slider registered")
mirage("overlay 30")
check(near(MDB.minimapHideAt, 0.3), "/mirage overlay 30")
STATE.target = true; Fire("PLAYER_TARGET_CHANGED"); Advance(0.4)
check(Minimap:IsShown(), "shown again when revealed")
STATE.target = false; Fire("PLAYER_TARGET_CHANGED")
Advance(5 + 0.1 + 0.6)
check(Minimap:IsShown() and MinimapCluster:GetAlpha() > 0.3, "above 30%: still shown")
Advance(0.65)
check(not Minimap:IsShown() and MinimapCluster:GetAlpha() > 0, "below 30%: hidden while the rest keeps fading")
Advance(1)
mirage("overlay 0")
mirage("alpha 1")
check(near(MDB.fadedAlpha, 0.01), "/mirage alpha 1 means 1%, not 100%")
mirage("alpha 0")
Advance(1)

section("module switch: overview checkbox, keybinding, /lefthy")
check(not Minimap:IsShown(), "faded and minimap hidden before disabling")
REGISTERED_SETTINGS.LefthyTools_module_mirage:SetValue(false) -- untick Mirage on the overview page
check(not Mirage.enabled and LefthyToolsDB.modules.mirage == false, "overview checkbox disables the module")
Advance(0.02)
check(Minimap:IsShown(), "minimap shown right away when disabled")
Advance(0.5)
check(near(a("MainActionBar"), 1) and near(a("PlayerFrame"), 0.6), "everything back at Blizzard's own opacity")
local sets = MainActionBar._setCount
Advance(5)
check(MainActionBar._setCount == sets, "fully unhooked: no more alpha updates while disabled")
Fire("CHAT_MSG_WHISPER", "hi", "Someone"); STATE.combat = true; Fire("PLAYER_REGEN_DISABLED"); STATE.combat = false
Advance(1)
check(MainActionBar._setCount == sets, "events are ignored while disabled")
Mirage:SetPeek(true); Advance(0.3); Mirage:SetPeek(false)
check(MainActionBar._setCount == sets, "peek binding does nothing while disabled")
LT:ToggleModule("mirage") -- keybinding
check(Mirage.enabled and REGISTERED_SETTINGS.LefthyTools_module_mirage:GetValue() == true,
	"keybinding re-enables and the overview checkbox follows")
Advance(0.5)
check(near(a("MainActionBar"), 1), "visible right after enabling")
Advance(7)
check(near(a("MainActionBar"), 0), "fades again after enabling")
lefthy("disable mirage")
Advance(0.5)
check(not Mirage.enabled and near(a("MainActionBar"), 1), "/lefthy disable mirage")
lefthy("enable mirage")
check(Mirage.enabled, "/lefthy enable mirage")
lefthy("")
check(OPENED_CATEGORY == LT.category:GetID(), "/lefthy opens the overview")
-- Gamepad mode: opening the panel from addon code would taint its focus manager (a role check's
-- Accept then gets blocked), so it says where to find the settings instead.
OPENED_CATEGORY, GAMEPAD_STATE.ui = nil, true
lefthy("")
check(OPENED_CATEGORY == nil and (PRINTED[#PRINTED] or ""):find("in gamepad mode, open the settings from the game menu", 1, true),
	"gamepad mode: /lefthy points to the game menu instead of opening the panel")
GAMEPAD_STATE.ui = false
lefthy("modules")
lefthy("mirage status")
lefthy("mirage")
check(OPENED_CATEGORY == Mirage.category:GetID(), "/lefthy mirage opens Mirage's page")

section("switching off after an engine-side alpha change")
STATE.target = true; Fire("PLAYER_TARGET_CHANGED"); Advance(1) -- HUD fully visible
AnimateAlpha(VehicleSeatIndicator, 1) -- an animation reveals a frame Mirage adopted at alpha 0
lefthy("disable mirage"); Advance(0.6)
check(near(a("VehicleSeatIndicator"), 1), "switching off keeps what the animation set, got " .. a("VehicleSeatIndicator"))
lefthy("enable mirage"); Advance(0.3)
STATE.target = false; Fire("PLAYER_TARGET_CHANGED")

section("slash commands")
mirage("fade 3")
check(MDB.fadeOutTime == 3, "/mirage fade 3")
mirage("delay 60")
check(MDB.delay == 30, "/mirage delay 60: the slider's limit (30 s), so the settings page can show it")
do -- An element new in a later build starts at the player's faded opacity (not the default's).
	local chatAlpha, fadedAlpha, barsAlpha = MDB.groupAlpha.chat, MDB.fadedAlpha, MDB.groupAlpha.actionbars
	MDB.fadedAlpha, MDB.groupsSeen.chat, MDB.groupAlpha.chat = 0.45, nil, 0
	Mirage:OnInitialize()
	check(MDB.groupAlpha.chat == 0.45 and MDB.groupsSeen.chat and MDB.groupAlpha.actionbars == barsAlpha,
		"a new element: the player's faded opacity; the known ones keep theirs")
	MDB.groupAlpha.chat, MDB.fadedAlpha = chatAlpha, fadedAlpha
	Mirage:OnInitialize()
end
mirage("delay 2")
check(MDB.delay == 2 and S("delay").uiUpdates > 0, "/mirage delay 2, through the setting (an open settings page follows)")
mirage("alpha 20")
check(near(MDB.fadedAlpha, 0.2), "/mirage alpha 20")
Advance(0.3)
Advance(2.1 + 3.2)
check(near(a("MainActionBar"), 0.2, 0.02), "faded opacity applied live, got " .. a("MainActionBar"))
STATE.target = true; Fire("PLAYER_TARGET_CHANGED"); Advance(0.5)
STATE.target = false; Fire("PLAYER_TARGET_CHANGED")
Advance(2.1 + 1.5)
local midway = a("MainActionBar")
Advance(1.6)
io.write(string.format("  with 3s fade-out: %.2f halfway, %.2f at end\n", midway, a("MainActionBar")))
check(midway > 0.3 and midway < 0.9, "3s fade-out is still in progress halfway")
check(near(a("MainActionBar"), 0.2, 0.02), "reaches faded opacity")
mirage("group chat off")
Advance(0.5)
check(near(a("ChatFrame1"), 1) and MDB.groups.chat == false, "disabled group becomes visible")
check(S("group_chat").uiUpdates > 0, "/mirage group goes through the setting (an open settings page follows)")
mirage("off")
Advance(0.5)
check(near(a("MainActionBar"), 1) and not Mirage.enabled, "/mirage off shows everything")
mirage("on")
check(Mirage.enabled, "/mirage on")
mirage("status")
mirage("")
check(OPENED_CATEGORY == Mirage.category:GetID(), "/mirage opens Mirage's settings page")
local delayUpdates, chatUpdates = S("delay").uiUpdates, S("group_chat").uiUpdates
mirage("reset")
check(MDB.fadeOutTime == 1.5 and MDB.groups.chat == true and MDB.delay == 5, "/mirage reset")
check(S("delay").uiUpdates > delayUpdates and S("group_chat").uiUpdates > chatUpdates,
	"/mirage reset tells an open settings page about every reset value")
check(MDB.groups.reticle == false, "/mirage reset keeps per-group defaults")
check(MDB.minimapHideAt == 0, "/mirage reset restores the quest area threshold")
check(LefthyToolsDB.settings.mirage == MDB, "reset keeps the same settings table")
MDB.groupAlpha.minimap = 0.5
Mirage:OnInitialize() -- the next login
check(MDB.groupAlpha.minimap == 0.5, "after a reset the next login keeps per-element opacity (no second migration)")

section("idle delay 0")
mirage("delay 0")
Advance(0.3 + 2)
check(near(a("MainActionBar"), 0), "delay 0: fades as soon as nothing is going on")
STATE.combat = true; Fire("PLAYER_REGEN_DISABLED"); Advance(0.5)
check(near(a("MainActionBar"), 1), "delay 0: still visible in combat, got " .. a("MainActionBar"))
STATE.target = true; STATE.combat = false; Fire("PLAYER_REGEN_ENABLED"); Fire("PLAYER_TARGET_CHANGED"); Advance(0.5)
check(near(a("MainActionBar"), 1), "delay 0: still visible with a target")
STATE.target = false; Fire("PLAYER_TARGET_CHANGED")
mirage("reset")
Advance(0.3)

section("peek binding")
Advance(8)
check(near(a("MainActionBar"), 0), "faded before peek")
Mirage:SetPeek(true); Advance(0.4)
check(near(a("MainActionBar"), 1), "peek shows")
Mirage:SetPeek(false); Advance(0.4)
check(near(a("MainActionBar"), 1), "stays briefly after peek")

section("secret alpha is left alone")
Advance(8)
PlayerFrame:SetAlpha(SECRET)
Advance(2)
check(PlayerFrame:GetAlpha() == SECRET, "frame with secret alpha isn't touched")
PlayerFrame:SetAlpha(0.9)
Advance(1.2)
check(near(a("PlayerFrame"), 0), "managed again after a normal SetAlpha")

section("settings callback")
S("fadedAlpha"):SetValue(0.5)
Advance(0.5)
check(near(a("MainActionBar"), 0.5, 0.02), "settings panel change applies live")

section("fade strength per element")
local row = CHECKBOX_SLIDERS.LefthyTools_mirage_group_minimap
check(row and row.checkbox == S("group_minimap") and row.slider == S("alpha_minimap") and row.cbLabel == "Minimap",
	"each element: its checkbox and its own opacity slider in one row")
check(MDB.groupAlpha.minimap == 0.5 and MDB.groupAlpha.chat == 0.5 and S("alpha_chat").uiUpdates > 0,
	"'Faded opacity' sets every element (and an open settings page shows it)")
S("alpha_minimap"):SetValue(0.8)
Advance(0.5)
check(near(a("MinimapCluster"), 0.8, 0.02) and near(a("MainActionBar"), 0.5, 0.02), "one element can stay more visible than the rest")
mirage("group actionbars 10")
Advance(1)
check(near(MDB.groupAlpha.actionbars, 0.1) and near(a("MainActionBar"), 0.1, 0.02) and S("alpha_actionbars").uiUpdates > 0,
	"/mirage group actionbars 10, through the setting")
mirage("alpha 0")
Advance(3)
check(near(a("MinimapCluster"), 0) and near(a("MainActionBar"), 0) and not Minimap:IsShown(),
	"'Faded opacity' again: every element follows, the minimap hides its quest areas at 0%")
S("alpha_minimap"):SetValue(0.3)
Advance(1)
check(Minimap:IsShown() and near(a("MinimapCluster"), 0.3, 0.02), "a minimap fading to 30% stays shown")
S("alpha_minimap"):SetValue(0)
Advance(1.5)
check(not Minimap:IsShown(), "and at 0% it hides again")
local sameUpdates = S("alpha_chat").uiUpdates
mirage("delay 5")
check(S("alpha_chat").uiUpdates == sameUpdates, "other settings leave the element opacities alone")
mirage("alpha 50") -- as before this section
Advance(1)
check(Minimap:IsShown(), "minimap back at 50%")

section("AFK screen")
local AFK = ns.AFKScreen
local function afk(on) STATE.afk = on; Fire("PLAYER_FLAGS_CHANGED", "player") end
local function AFKS(id) return REGISTERED_SETTINGS["LefthyTools_tweaks_" .. id] end
check(LefthyToolsDB.settings.tweaks.afkScreen and LefthyToolsDB.settings.tweaks.afkSpin and AFKS("afkScreen") and AFKS("afkSpin")
	and MDB.afkScreen == nil and not S("afkScreen"), "a Misc Tweak (not part of Mirage), on by default")
Advance(0.1)
check(not AFK.driver:IsShown(), "not AFK: nothing runs at all")
afk(true)
check(UIParent:GetAlpha() == 1 and not LefthyToolsAFKFrame, "nothing happens inside the event handler")
Advance(0.05)
local afkScreen = LefthyToolsAFKFrame
check(afkScreen and afkScreen:IsShown() and UIParent:GetAlpha() == 0, "AFK: the interface disappears, the AFK screen shows")
check(afkScreen:GetParent() == nil and afkScreen._mouseEnabled and afkScreen._strata == "FULLSCREEN_DIALOG",
	"the screen isn't part of the interface, sits on top and catches clicks")
check(CAMERA.spinning and CAMERA.speed < 0.1, "the camera slowly circles")
check(afkScreen.Model._unit == "player", "your character")
check(afkScreen.Name:GetText():find("Lefthy|r", 1, true) and afkScreen.Name:GetText():find("Level 19 Human Rogue", 1, true),
	"name, level, race and class, got " .. afkScreen.Name:GetText())
local afkInfo = afkScreen.Info:GetText()
check(afkInfo:find("Elwynn Forest - Goldshire", 1, true) and afkInfo:find("Time: 12:", 1, true)
	and afkInfo:find("Level progress: 25%, rested: 20%", 1, true), "zone, time, level progress, got " .. afkInfo)
check(afkScreen.Friends:GetText():find("No friends with LefthyTools online", 1, true), "friends: none online yet")
Advance(65.5)
check(afkScreen.Title:GetText():find("1:05", 1, true), "the timer counts (once a second), got " .. afkScreen.Title:GetText())
Fire("CHAT_MSG_WHISPER", "you there?", "Anna-Realm")
Advance(1.1)
check(afkScreen.Info:GetText():find("Whispers: 1 (last from Anna)", 1, true), "whispers while away")
STATE.moving = true
Advance(0.3)
check(not afkScreen:IsShown() and UIParent:GetAlpha() == 1 and not CAMERA.spinning, "moving brings everything back, the camera stops")
STATE.moving = false
Advance(1)
check(not afkScreen:IsShown() and not AFK.driver:IsShown(), "still flagged AFK, but you were back: it stays away, nothing runs")
afk(false)
Advance(0.1)
afk(true)
Advance(0.05)
check(afkScreen:IsShown(), "the next AFK shows it again")
STATE.combat = true
Fire("PLAYER_REGEN_DISABLED")
Advance(0.02)
check(not afkScreen:IsShown() and UIParent:GetAlpha() == 1, "combat: back on the next frame (SetAlpha works in combat)")
afk(false)
afk(true)
Advance(0.1)
check(not afkScreen:IsShown(), "not while in combat")
STATE.combat = false
afk(false)
afk(true)
Advance(0.05)
afkScreen._scripts.OnMouseDown(afkScreen, "LeftButton")
Advance(0.02)
check(not afkScreen:IsShown() and UIParent:GetAlpha() == 1, "a click brings everything back")
afk(false)
afk(true)
Advance(0.05)
Fire("READY_CHECK", "Anna", 30)
Advance(0.02)
check(not afkScreen:IsShown(), "a ready check needs you: back")
afk(false)
afk(true)
Advance(0.05)
afk(false)
Advance(0.3)
check(not afkScreen:IsShown() and UIParent:GetAlpha() == 1 and not AFK.driver:IsShown(), "no longer AFK: back, nothing runs")
AFKS("afkSpin"):SetValue(false)
afk(true)
Advance(0.05)
check(afkScreen:IsShown() and not CAMERA.spinning, "camera circling off")
AFKS("afkSpin"):SetValue(true)
afk(false)
lefthy("disable mirage")
afk(true)
Advance(0.05)
check(afkScreen:IsShown() and UIParent:GetAlpha() == 0, "it doesn't need Mirage")
lefthy("disable tweaks")
Advance(0.05)
check(not afkScreen:IsShown() and UIParent:GetAlpha() == 1, "Misc Tweaks off while AFK: back")
afk(false)
lefthy("enable tweaks")
lefthy("enable mirage")
Advance(0.05)
afk(true)
Advance(0.05)
check(afkScreen:IsShown(), "on again: the next AFK shows it (leaving by switching off isn't 'you were back')")
afk(false)
Advance(0.05)
AFKS("afkScreen"):SetValue(false)
Advance(0.05)
afk(true)
Advance(0.3)
check(not afkScreen:IsShown(), "AFK screen off: nothing")
afk(false)
AFKS("afkScreen"):SetValue(true)
Advance(0.05)
LefthyToolsDB.settings.tweaks.afkSpinning, CAMERA.spinning = true, true -- a /reload while the camera was circling
local stops = CAMERA.stops
AFK.Enable() -- what the login after a /reload does
Advance(0.05)
check(CAMERA.stops == stops + 1 and not CAMERA.spinning and not LefthyToolsDB.settings.tweaks.afkSpinning,
	"after a reload mid-circle the camera is stopped")
do -- A narrower screen (a big UI scale): the two columns get narrower instead of overlapping.
	local width = UIParent:GetWidth()
	UIParent:SetWidth(1100)
	afk(true)
	Advance(0.1)
	local info, friends = LefthyToolsAFKFrame.Info.width, LefthyToolsAFKFrame.Friends.width
	check(LefthyToolsAFKFrame:IsShown() and 300 + info + 20 <= 1100 - 40 - friends,
		"1100 wide: info ends before the friends begin, got " .. info .. " and " .. friends)
	afk(false)
	Advance(0.1)
	UIParent:SetWidth(width)
end
Advance(8) -- let the HUD settle again

section("Misc Tweaks: framework")
local Tweaks = LT:GetModule("tweaks")
local TDB = LefthyToolsDB.settings.tweaks
local function T(id) return REGISTERED_SETTINGS["LefthyTools_tweaks_" .. id] end
check(Tweaks and Tweaks.enabled, "tweaks module registered and enabled at login")
check(REGISTERED_SETTINGS.LefthyTools_module_tweaks, "overview page has a switch for Misc Tweaks")
check(Tweaks.category and Tweaks.category.parent == LT.category and Tweaks.category.name == "Misc Tweaks",
	"Misc Tweaks has its own sub-page under LefthyTools")
check(T("statusText") and T("movableBags") and T("questAnnounce") and not T("gamepadSortButton"),
	"one checkbox per tweak (sort button removed)")

section("Misc Tweaks: always show health / power values")
check(CVARS.statusText == "1" and CVARS.statusTextDisplay == "NUMERIC", "values shown permanently as current / max")
T("statusText"):SetValue(false)
check(CVARS.statusText == "1", "not applied inside the settings callback itself")
Advance(0.05)
check(CVARS.statusText == "0" and CVARS.statusTextDisplay == "PERCENT", "switching off restores the previous Status Text setting")
T("statusText"):SetValue(true); Advance(0.05)
check(CVARS.statusText == "1" and CVARS.statusTextDisplay == "NUMERIC", "on again")

section("Misc Tweaks: movable bags")
OpenBags()
check(ContainerFrameCombinedBags:GetPoint(1) == "BOTTOMRIGHT", "no saved position: Blizzard's default spot")
check(ContainerFrameCombinedBags._dragButtons and BAG_TITLE_ROUTER._dragButtons, "bag and its title bar accept drags")
BAG_TITLE_ROUTER._scripts.OnDragStart(BAG_TITLE_ROUTER)
check(ContainerFrameCombinedBags._moving and MENUS_CLOSED > 0, "dragging the title bar moves the bag and closes the bag menu")
ContainerFrameCombinedBags._dropAt = { left = 300, top = 700 }
BAG_TITLE_ROUTER._scripts.OnDragStop(BAG_TITLE_ROUTER)
local saved = TDB.bagPositions.combined
check(saved and saved.left == 300 and saved.top == 700 and ContainerFrameCombinedBags._userPlaced == false, "position saved")
do -- In gamepad mode the menu stays: closing a Blizzard menu from addon code taints the controller's focus manager.
	local closed = MENUS_CLOSED
	GAMEPAD_STATE.ui = true
	BAG_TITLE_ROUTER._scripts.OnDragStart(BAG_TITLE_ROUTER)
	BAG_TITLE_ROUTER._scripts.OnDragStop(BAG_TITLE_ROUTER)
	GAMEPAD_STATE.ui = false
	check(MENUS_CLOSED == closed, "gamepad mode: dragging doesn't close Blizzard's menu from our code")
	ContainerFrame1:Show()
	UpdateContainerFrameAnchors()
	check(ContainerFrame1._clamped == true, "a bag not moved while another one is: kept on the screen")
	ContainerFrame1:Hide()
end
CloseBags(); OpenBags()
local point, _, _, x, y = ContainerFrameCombinedBags:GetPoint(1)
check(point == "TOPLEFT" and x == 300 and y == 700, "reopens where it was left instead of Blizzard's spot")
MOCK_CONTAINER_SCALE = 0.5
CloseBags(); OpenBags()
point, _, _, x, y = ContainerFrameCombinedBags:GetPoint(1)
check(x == 600 and y == 1400, "same screen spot when Blizzard shrinks the bags (offsets scale with the bag)")
MOCK_CONTAINER_SCALE = nil
CloseBags(); OpenBags()
ContainerFrameCombinedBags._scripts.OnDragStart(ContainerFrameCombinedBags)
ContainerFrameCombinedBags._dropAt = { left = 100, top = 500 }
ContainerFrameCombinedBags._scripts.OnDragStop(ContainerFrameCombinedBags)
check(TDB.bagPositions.combined.left == 100, "dragging an empty spot of the bag works too")
ContainerFrameCombinedBags.IsProtected = function() return true end
STATE.combat = true
ContainerFrameCombinedBags._scripts.OnDragStart(ContainerFrameCombinedBags)
check(not ContainerFrameCombinedBags._moving, "a protected bag isn't moved in combat")
STATE.combat = false
ContainerFrameCombinedBags.IsProtected = nil
T("movableBags"):SetValue(false); Advance(0.05)
check(ContainerFrameCombinedBags:GetPoint(1) == "BOTTOMRIGHT", "switching off puts the bag back at Blizzard's spot")
ContainerFrameCombinedBags._scripts.OnDragStart(ContainerFrameCombinedBags)
check(not ContainerFrameCombinedBags._moving, "and dragging does nothing while off")
T("movableBags"):SetValue(true); Advance(0.05)
point, _, _, x, y = ContainerFrameCombinedBags:GetPoint(1)
check(point == "TOPLEFT" and x == 100 and y == 500, "switching on again restores the saved spot")
lefthy("tweaks resetbags")
check(ContainerFrameCombinedBags:GetPoint(1) == "BOTTOMRIGHT" and next(TDB.bagPositions) == nil, "/lefthy tweaks resetbags")
CloseBags()

section("Misc Tweaks: quest progress in party chat")
check(T("questAnnounce"), "checkbox for quest announcements")
local function QuestUpdate() Fire("QUEST_LOG_UPDATE"); Advance(0.5) end
local function Q(id, title, ...)
	local objectives = {}
	for i, text in ipairs({ ... }) do objectives[i] = { text = text, finished = false } end
	return { id = id, title = title, objectives = objectives }
end
local function Finish(quest, i, text) quest.objectives[i] = { text = text, finished = true } end
GROUP = "party"
QUESTS = {
	Q(101, "Kobold Camp Cleanup", "0/10 Kobold Vermin slain", "0/5 Kobold Workers slain"),
	{ id = 102, title = "Already Done", objectives = { { text = "1/1 Letter delivered", finished = true } } },
}
QuestUpdate()
check(#SENT == 0, "quests seen for the first time stay silent (just accepted, or already done)")
QUESTS[1].objectives[1] = { text = "5/10 Kobold Vermin slain", finished = false }
QuestUpdate()
check(#SENT == 0, "no message for every single kill")
Finish(QUESTS[1], 1, "10/10 Kobold Vermin slain")
QuestUpdate()
check(#SENT == 1 and SENT[1].channel == "PARTY" and SENT[1].msg == "{rt1} [Kobold Camp Cleanup]: 10/10 Kobold Vermin slain",
	"finished objective posted in party chat, got: " .. tostring(SENT[1] and SENT[1].msg))
Finish(QUESTS[1], 2, "5/5 Kobold Workers slain")
QuestUpdate()
check(#SENT == 2 and SENT[2].msg == "{rt1} [Kobold Camp Cleanup]: quest complete!",
	"last objective: one 'quest complete' line instead of the objective")
QuestUpdate()
check(#SENT == 2, "nothing repeated on later updates")

QUESTS[3] = Q(103, "Collapsed Header Quest", "0/1 Thing found")
QuestUpdate()
QUESTS[3].collapsed = true
Finish(QUESTS[3], 1, "1/1 Thing found")
QuestUpdate()
check(#SENT == 3 and SENT[3].msg:find("Collapsed Header Quest", 1, true), "quests under a collapsed header still announce")

GROUP = "none"
QUESTS[4] = Q(104, "Solo Quest", "0/1 X")
QuestUpdate(); Finish(QUESTS[4], 1, "1/1 X"); QuestUpdate()
check(#SENT == 3, "nothing is posted when solo")
GROUP = "raid"
QUESTS[5] = Q(105, "Raid Quest", "0/1 Y")
QuestUpdate(); Finish(QUESTS[5], 1, "1/1 Y"); QuestUpdate()
check(#SENT == 3, "nothing is posted in a raid")
GROUP = "instance"
QUESTS[6] = Q(106, "Dungeon Quest", "0/1 Z")
QuestUpdate(); Finish(QUESTS[6], 1, "1/1 Z"); QuestUpdate()
check(#SENT == 4 and SENT[4].channel == "INSTANCE_CHAT", "instance group uses instance chat")

GROUP = "party"
STATE.chatLockdown = true
QUESTS[7] = Q(107, "Locked Quest", "0/1 W")
QuestUpdate(); Finish(QUESTS[7], 1, "1/1 W"); QuestUpdate()
check(#SENT == 4, "held while the client locks down addon chat")
STATE.chatLockdown = false
Advance(1.2)
check(#SENT == 5 and SENT[5].msg:find("Locked Quest", 1, true), "sent once the lockdown lifts")
STATE.chatLockdown = true -- a lockdown that lasts (a whole dungeon run)
QUESTS[8] = Q(108, "Long Locked Quest", "0/1 V")
QuestUpdate(); Finish(QUESTS[8], 1, "1/1 V"); QuestUpdate()
Advance(15)
STATE.chatLockdown = false
Advance(1.2)
check(#SENT == 5, "a line that waited longer than 10 s is old news: dropped, not sent late")
table.remove(QUESTS, 8)
QuestUpdate()

table.remove(QUESTS, 1) -- turned in
Fire("QUEST_TURNED_IN", 101)
QuestUpdate()
check(#SENT == 5, "turning a quest in doesn't post anything")

lefthy("tweaks quests off"); Advance(0.05)
QUESTS[#QUESTS + 1] = Q(108, "Muted Quest", "0/1 V")
QuestUpdate(); Finish(QUESTS[#QUESTS], 1, "1/1 V"); QuestUpdate()
check(#SENT == 5, "switched off: silent")
lefthy("tweaks quests on"); Advance(0.05)
QuestUpdate()
check(#SENT == 5, "switching on again doesn't re-announce what's already done")
GROUP = "none"

section("Misc Tweaks: combo points on the personal resource display")
local PRD = PersonalResourceDisplayFrame
local row, pips, comboStyle = ns.GetComboPointRow()
check(TDB.comboPoints == true and REGISTERED_SETTINGS.LefthyTools_tweaks_comboPoints, "on by default, with a checkbox")
check(row and row:GetParent() == PRD and row:IsShown(), "a row inside the personal resource display (rogue)")
check(comboStyle == "retail", "retail's rogue combo point art when the client has it")
local p1, rel, p2, x, y = row:GetPoint(1)
check(p1 == "TOP" and rel == PRD and p2 == "BOTTOM" and x == 0 and y == -6, "centred under the display's lowest bar")
check(#pips == 5 and row:GetWidth() == 108 and row:GetScale() == 1, "5 points, 20 px each with 2 px gaps")
check(pips[1].Shadow and pips[1].Slash.width == 43 and pips[1].Icon.atlas == "uf-roguecp-icon-red", "retail layers: shadow, sockets, gem, effects")
local function isFull(i) return pips[i].Icon.alpha == 1 and pips[i].Active.alpha == 1 and pips[i].Inactive.alpha == 0 end
local function isEmpty(i) return pips[i].Icon.alpha == 0 and pips[i].Active.alpha == 0 and pips[i].Inactive.alpha == 1 end
local function fullCount() local n = 0 for i = 1, 5 do if isFull(i) then n = n + 1 end end return n end
check(isEmpty(1) and isEmpty(5) and pips[1].Gain.plays == 0 and pips[1].Spend.plays == 0,
	"no combo points: empty sockets, no animation on the first draw")
STATE.target, COMBO.points = true, 2
Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
check(fullCount() == 0, "nothing drawn inside the event handler")
Advance(0.05)
check(isFull(1) and isFull(2) and isEmpty(3), "2 points: two lit gems")
check(pips[2].Gain.plays == 1 and pips[3].Gain.plays == 0, "gaining a point plays Blizzard's gain animation (slash, glow)")
local function tint(i, key) local v = pips[i][key or "IconBoost"].vertex; return v[1], v[2], v[3] end -- the full colour
local function near3(i, r, g, b, key) local x, y, z = tint(i, key); return math.abs(x - r) < 0.01 and math.abs(y - g) < 0.01 and math.abs(z - b) < 0.01 end
check(pips[1].Icon.desaturated and near3(1, 0.575, 0.95, 0.075) and near3(2, 0.575, 0.95, 0.075)
	and near3(2, 0.575, 0.95, 0.075, "Slash") and near3(2, 0.68125, 0.9625, 0.30625, "Icon")
	and near3(2, 0.68125, 0.9625, 0.30625, "Active"),
	"2 of 5: every gem and its effects tinted yellow-green (plain gem and socket a quarter lighter)")
check(not pips[1].Inactive.desaturated and pips[1].Shadow.vertex == nil, "empty sockets and the shadow keep their own look")
check(pips[1].IconBoost.shown and pips[1].IconBoost.blend == "ADD" and pips[1].IconBoost.alpha == 1
	and near3(1, 0.575, 0.95, 0.075, "IconBoost") and pips[3].IconBoost.alpha == 0,
	"an additive copy of each lit gem in the same colour keeps the colours bright")
check(pips[1].Glow.blend == "ADD" and pips[1].FrameGlow.blend == "ADD" and pips[1].Active.blend == "BLEND",
	"glows blend additively while coloured; the socket doesn't")
COMBO.points = 3
Fire("UNIT_POWER_FREQUENT", "player", "ENERGY")
Advance(0.05)
check(fullCount() == 2, "energy ticks don't redraw")
COMBO.points = 5
Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
Advance(0.05)
check(fullCount() == 5 and pips[1].Ready:IsPlaying() and pips[5].Ready:IsPlaying() and pips[1].Gain.plays == 1,
	"all 5: every gem glows and breathes (finisher ready); already lit gems don't replay")
check(near3(1, 1, 0.1, 0.05) and near3(5, 1, 0.1, 0.05), "all 5: red")
COMBO.points = 0
Fire("PLAYER_TARGET_CHANGED")
Advance(0.05)
check(isEmpty(1) and isEmpty(5) and pips[1].Spend.plays == 1 and not pips[1].Ready:IsPlaying(),
	"new target: points gone, each gem bursts out (spend animation)")
check(near3(1, 1, 0.1, 0.05, "Burst"), "the burst keeps the colour the gems had")
COMBO.max = 6
Fire("UNIT_MAXPOWER", "player", "COMBO_POINTS")
Advance(0.05)
check(pips[6] and pips[6]:IsShown() and row:GetWidth() == 130 and pips[6].Spend.plays == 0 and pips[6].Inactive.alpha == 1,
	"6 max combo points: a sixth socket, without a burst")
PRD:SetSize(100, 30)
Advance(0.05)
check(math.abs(row:GetScale() - 100 / 130) < 1e-6, "narrow bars (Edit Mode): the row shrinks to fit")
PRD:SetSize(200, 30)
Advance(0.05)
check(row:GetScale() == 1, "and grows back, never past its normal size")
COMBO.max = 5
Fire("UNIT_MAXPOWER", "player", "COMBO_POINTS")
Advance(0.05)
check(not pips[6]:IsShown() and row:GetWidth() == 108, "back to 5")
PLAYER_CLASS, POWER_TYPE = "DRUID", 0
Fire("UNIT_DISPLAYPOWER", "player")
Advance(0.05)
check(not row:IsShown(), "druid in caster form: no combo points")
POWER_TYPE = 3
COMBO.points = 2
Fire("UNIT_DISPLAYPOWER", "player")
Advance(0.05)
check(row:IsShown() and fullCount() == 2 and pips[2].Gain.plays == 1, "druid in Cat Form: combo points, shown without replaying animations")
PLAYER_CLASS = "MAGE"
Fire("PLAYER_ENTERING_WORLD")
Advance(0.05)
check(not row:IsShown(), "other classes: nothing")
PLAYER_CLASS = "ROGUE"
COMBO.points = SECRET
Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
Advance(0.05)
check(not row:IsShown(), "secret combo points: the row hides instead of erroring")
COMBO.points = 1
Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
Advance(0.05)
check(row:IsShown() and fullCount() == 1, "readable again: back")
check(near3(1, 0.15, 1, 0.15), "1 point: green")
COMBO.points = 3
Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
Advance(0.05)
check(near3(1, 1, 0.9, 0) and near3(3, 1, 0.9, 0), "3 of 5: yellow, the earlier gems recoloured too")
lefthy("tweaks combocolors off"); Advance(0.05)
check(TDB.comboColors == false and not pips[1].Icon.desaturated and near3(1, 1, 1, 1), "/lefthy tweaks combocolors off: retail's red art")
check(not pips[1].IconBoost.shown and pips[1].Glow.blend == "BLEND", "... without the boost and with retail's blending")
lefthy("tweaks combocolors on"); Advance(0.05)
check(pips[1].Icon.desaturated and near3(1, 1, 0.9, 0), "and on again")
COMBO.points = 1
Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
Advance(0.05)
lefthy("tweaks combo off"); Advance(0.05)
check(not row:IsShown() and TDB.comboPoints == false, "/lefthy tweaks combo off")
COMBO.points = 3
Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
Advance(0.05)
check(not row:IsShown(), "and stays off")
lefthy("tweaks combo on"); Advance(0.05)
check(row:IsShown() and fullCount() == 3, "/lefthy tweaks combo on")
COMBO.points, STATE.target = 0, false

section("Misc Tweaks: quests that are new in WoW: Forever")
check(TDB.foreverQuests == true and REGISTERED_SETTINGS.LefthyTools_tweaks_foreverQuests, "on by default, with a checkbox")
check(ns.IsForeverQuest(86574) and ns.IsForeverQuest(99411) and not ns.IsForeverQuest(86575)
	and not ns.IsForeverQuest(176) and not ns.IsForeverQuest(8193), "the generated list: Forever's own quests, not Classic ones")
check(ns.IsMarkedQuest(86574) and ns.IsMarkedQuest(77568) and ns.IsMarkedQuest(55296) and not ns.IsMarkedQuest(176)
	and not ns.IsMarkedQuest(8193) and not ns.IsMarkedQuest(86575),
	"later Classic quests (Season of Discovery and the like, in Forever's client too) get the marker as well")
check(not ns.IsForeverQuest(77568), "... but don't count as new in Forever (Chronicle's statistic)")
local MARK = " |cff4de1ffNEW|r"
local savedQuests = QUESTS
local hogger = { id = 176, title = "Wanted: Hogger", objectives = {} }
local foreverQuest = { id = 86574, title = "A Forever quest", objectives = {} }
QUESTS = { hogger, foreverQuest }
QuestLogQuests_Update()
local function titleButton(id) for _, b in ipairs(QUEST_LOG_BUTTONS) do if b.questID == id then return b end end end
check(titleButton(86574).Text:GetText() == "A Forever quest" .. MARK, "quest log: NEW right after the Forever quest's name")
check(titleButton(176).Text:GetText() == "Wanted: Hogger", "... nothing on a Classic quest")
QUESTS = { foreverQuest, hogger } -- the pool hands the buttons out in a different order
QuestLogQuests_Update()
check(titleButton(86574).Text:GetText() == "A Forever quest" .. MARK and titleButton(176).Text:GetText() == "Wanted: Hogger",
	"reused title buttons: the marker follows the quest")
local forButton = titleButton(86574)
GameTooltip:SetOwner(forButton); TOOLTIP.shown = true -- Blizzard's own OnEnter shows the quest tooltip
forButton._scripts.OnEnter(forButton)
check(table.concat(TOOLTIP.lines, "|"):find("New in WoW: Forever", 1, true), "hovering the quest adds a line explaining NEW")
GameTooltip:Hide()
local seasonQuest = { id = 77568, title = "A season quest", objectives = {} }
QUESTS = { seasonQuest }
QuestLogQuests_Update()
local seasonButton = titleButton(77568)
check(seasonButton.Text:GetText() == "A season quest" .. MARK, "a later Classic quest: NEW too")
GameTooltip:SetOwner(seasonButton); TOOLTIP.shown = true
seasonButton._scripts.OnEnter(seasonButton)
local seasonTip = table.concat(TOOLTIP.lines, "|")
check(seasonTip:find("Not in the original Classic", 1, true) and not seasonTip:find("New in WoW: Forever", 1, true),
	"... and its tooltip says where it's from")
GameTooltip:Hide()
QUESTS = { foreverQuest, hogger }
QuestLogQuests_Update()
-- A title that would need another line with the marker: Blizzard already sized the entry.
local longQuest = { id = 86576, title = string.rep("x", 31), objectives = {} } -- 31 chars = 1 line, +4 = 2
QUESTS = { longQuest }
QuestLogQuests_Update()
local spare = ns.GetForeverQuestLabels()[titleButton(86576)]
check(titleButton(86576).Text:GetText() == longQuest.title and spare and spare:IsShown(),
	"a long title keeps its line count: NEW goes to the free spot at the end of the entry instead")
QUESTS = { foreverQuest }
QuestLogQuests_Update()
check(not spare:IsShown() and titleButton(86574).Text:GetText() == "A Forever quest" .. MARK,
	"that spare label goes away when the button shows another quest")
-- Details in the quest log, and the quest window.
SELECTED_QUEST = 86574
QuestInfo_Display({ questLog = true })
check(QuestInfoTitleHeader:GetText() == "A Forever quest" .. MARK, "quest details in the log: NEW after the title")
QUESTS = { hogger, foreverQuest }
DIALOG_QUEST = 176
QuestInfo_Display({ questLog = false })
check(QuestInfoTitleHeader:GetText() == "Wanted: Hogger", "quest window, Classic quest: no marker")
DIALOG_QUEST = 86574
QuestInfo_Display({ questLog = false })
check(QuestInfoTitleHeader:GetText() == "A Forever quest" .. MARK, "quest window, accepting or turning in a Forever quest: NEW")
QuestFrameProgressPanel:Show()
check(QuestProgressTitleText:GetText() == "A Forever quest" .. MARK, "... also on the progress page")
QuestFrameProgressPanel:Hide()
lefthy("tweaks newquests off"); Advance(0.05)
check(TDB.foreverQuests == false and titleButton(86574).Text:GetText() == "A Forever quest"
	and QuestInfoTitleHeader:GetText() == "A Forever quest", "/lefthy tweaks newquests off: the open log and window lose the marker")
QuestLogQuests_Update()
QuestInfo_Display({ questLog = false })
check(titleButton(86574).Text:GetText() == "A Forever quest" and QuestInfoTitleHeader:GetText() == "A Forever quest",
	"... and stay unmarked")
lefthy("tweaks newquests on"); Advance(0.05)
check(titleButton(86574).Text:GetText() == "A Forever quest" .. MARK, "on again: the open quest log is marked right away")
DIALOG_QUEST, SELECTED_QUEST = nil, nil
QUESTS = savedQuests

section("Misc Tweaks: module switch and /lefthy tweaks")
REGISTERED_SETTINGS.LefthyTools_module_tweaks:SetValue(false); Advance(0.05)
check(not Tweaks.enabled and CVARS.statusText == "0" and CVARS.statusTextDisplay == "PERCENT",
	"disabling the module undoes its tweaks")
check(not row:IsShown(), "including the combo points")
lefthy("enable tweaks"); Advance(0.05)
check(Tweaks.enabled and CVARS.statusText == "1", "enabling re-applies them")
lefthy("tweaks statustext off"); Advance(0.05)
check(CVARS.statusText == "0" and TDB.statusText == false and REGISTERED_SETTINGS.LefthyTools_tweaks_statusText.uiUpdates > 0,
	"/lefthy tweaks statustext off, through the setting (an open settings page follows)")
lefthy("tweaks statustext on"); Advance(0.05)
check(CVARS.statusText == "1", "/lefthy tweaks statustext on")
local statusMark = #PRINTED + 1
lefthy("tweaks status")
local helpMark = #PRINTED + 1
lefthy("tweaks help")
local helpText, missingWords = table.concat(PRINTED, "\n", helpMark), {}
for i = statusMark, helpMark - 1 do
	local word = PRINTED[i]:match("%((%w+)%)$")
	if word and not helpText:find(word, 1, true) then missingWords[#missingWords + 1] = word end
end
check(helpMark - statusMark >= 8 and #missingWords == 0,
	"/lefthy tweaks help names every tweak's word, missing: " .. table.concat(missingWords, ", "))
check(Mirage.enabled, "Mirage is unaffected by the tweaks module")

section("Beacon: setup")
local Beacon = LT:GetModule("beacon")
local BB = ns.Beacon
local BDB = LefthyToolsDB.settings.beacon
local function B(id) return REGISTERED_SETTINGS["LefthyTools_beacon_" .. id] end
local function peers() return Beacon:GetPeers() end
local function last(list) return list[#list] end
local function printedSince(mark)
	local out = {}
	for i = mark, #PRINTED do out[#out + 1] = PRINTED[i] end
	return table.concat(out, "\n")
end
check(Beacon and Beacon.enabled, "beacon module registered and enabled at login")
check(Beacon.category and Beacon.category.parent == LT.category and Beacon.category.name == "Beacon",
	"Beacon has its own sub-page under LefthyTools")
local allSettings = true
for _, id in ipairs({ "share", "interval", "showFriends", "showMinimap", "minimapEdge", "dingAnnounce", "dingText", "dingShow", "dingSound" }) do
	allSettings = allSettings and B(id) ~= nil
end
check(allSettings and REGISTERED_SETTINGS.LefthyTools_module_beacon, "settings and module switch")
check(BDB.interval == 3 and BDB.share and BDB.showFriends and BDB.showMinimap and BDB.minimapEdge
	and BDB.dingAnnounce and BDB.dingText == "" and BDB.dingShow and BDB.dingSound, "defaults: everything on, default ding text")
local textInput = TEXT_INPUTS.LefthyTools_beacon_dingText
check(textInput and textInput.template == "LefthyToolsSettingsTextTemplate" and textInput.data.options.maxLetters == 100,
	"level-up message is a text field in the settings panel")
check(SETTINGS_BUTTONS["Test your message"] and SETTINGS_BUTTONS["Test your message"].text == "Preview", "preview button")
check(ADDON_PREFIXES.LTBeacon, "addon message prefix registered")
check(next(WorldMapFrame.providers) ~= nil, "data provider attached to the world map")

section("Beacon: finding friends with the addon")
local greeted = {}
for _, m in ipairs(GAMEDATA) do if m.data == "H2" then greeted[m.id] = true end end
check(greeted[11] and greeted[12] and greeted[16], "online WoW friends get a hello")
check(not greeted[13] and not greeted[14] and not greeted[15], "offline, non-WoW and other-region friends don't")
local mark = #GAMEDATA + 1
Advance(30)
local onlyHellos = true
for _, m in ipairs(GameDataTo(11, mark)) do if m ~= "H2" then onlyHellos = false end end
check(onlyHellos, "friends without the addon get nothing but an occasional hello")
mark = #GAMEDATA + 1
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;250.0;750.0;Goldshire;", "WHISPER", 11) -- Anna answers
check(#GameDataTo(11, mark) == 0, "no sending inside the event handler")
Advance(0.15)
local function sentTo(id, from, prefix) -- messages to id since `from` that start with prefix
	local list = {}
	for _, m in ipairs(GameDataTo(id, from)) do if m:sub(1, #prefix) == prefix then list[#list + 1] = m end end
	return list
end
check(sentTo(11, mark, "S2;")[1] == "S2;;0;500.0;500.0;Goldshire;",
	"Anna answered: my state goes out right away, got " .. tostring(sentTo(11, mark, "S2;")[1]))
check(sentTo(11, mark, "V2;")[1] == "V2;0.4.0-3-gabc1234", "... together with my LefthyTools version")
Advance(1) -- the Battle.net lookup is coalesced to once a second
check(peers()[11] and peers()[11].name == "Anna" and peers()[11].classFile == "MAGE", "her name and class come from Battle.net")
mark = #GAMEDATA + 1
Advance(15)
check(#GameDataTo(11, mark) == 0, "standing still: nothing is sent")
Advance(9) -- checks run every 3 s, so the heartbeat lands 20-23 s after the last send
check(#GameDataTo(11, mark) == 1, "except a heartbeat every 20 s, got " .. #GameDataTo(11, mark))
mark = #GAMEDATA + 1
PLAYER_POS = { 0.51, 0.5 }
Advance(3.2)
check(#GameDataTo(11, mark) == 1 and GameDataTo(11, mark)[1] == "S2;;0;500.0;490.0;Goldshire;",
	"moving: the new position within the interval, got " .. tostring(GameDataTo(11, mark)[1]))
PLAYER_POS = { 0.52, 0.5 }
Advance(3.2)
check(#GameDataTo(11, mark) == 2, "and again every 3 s while moving")
mark = #GAMEDATA + 1
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "H2", "WHISPER", 12) -- Bob starts the addon and says hello
Advance(0.15)
check(#sentTo(12, mark, "S2;") == 1 and #sentTo(12, mark, "V2;") == 1, "a hello is answered with my state and version")
Fire("BN_CHAT_MSG_ADDON", "OtherAddon", "S2;;0;1;1;;", "WHISPER", 14)
for _, bad in ipairs({ "garbage", "S2;bad", "S2;;0;abc;1;;", "S2;;0;1;;;", "S2;x;0;1;1;;", "H2extra" }) do
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", bad, "WHISPER", 14)
end
Advance(0.15)
check(not peers()[14], "other prefixes and malformed messages are ignored")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "H1", "WHISPER", 16) -- Finn runs the old Beacon
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "P1:0:500.0:500.0", "WHISPER", 16)
Advance(0.15)
check(not peers()[16], "a friend on another LefthyTools version isn't treated as a peer")
local pmark = #PRINTED + 1
lefthy("beacon status")
local status = printedSince(pmark)
check(status:find("Finn runs another LefthyTools version", 1, true) ~= nil, "... and /lefthy beacon status says why")
check(status:find("traffic:", 1, true) ~= nil and status:find("2 friend(s)", 1, true) ~= nil, "status: friends and message traffic")
Advance(1.1) -- a fresh one-second window
for i = 1, 30 do -- a client gone haywire
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;900.0;400.0;Zone" .. i .. ";", "WHISPER", 12)
end
check(peers()[12].subzone == "Zone20", "flood guard: at most 20 messages a second from one friend")

section("Beacon: friends on the world map")
PLAYER_POS = { 0.5, 0.5 } -- me: north 500, west 500
Advance(0.6)
check(#PINS == 0, "map closed: nothing drawn")
OpenWorldMap(1429)
local function pinOf(id) for _, p in ipairs(PINS) do if p.gameAccountID == id then return p end end end
local annaPin = pinOf(11)
check(#PINS == 2 and annaPin and pinOf(12), "map open: Anna's and Bob's dots")
check(math.abs(annaPin.x - 0.25) < 1e-6 and math.abs(annaPin.y - 0.75) < 1e-6, "at her position on the zone map")
local c = annaPin.Dot.color
check(c and math.abs(c[1] - 0.25) < 1e-6 and math.abs(c[3] - 0.92) < 1e-6, "in mage blue")
check(annaPin.frameLevelType == "PIN_FRAME_LEVEL_VEHICLE_ABOVE_GROUP_MEMBER", "drawn just above Blizzard's group member dots")
STATE.combat = true
OpenWorldMap(1414); OpenWorldMap(1429) -- dots are released and acquired again, in combat
check(#PINS == 2 and #BLOCKED == 0, "opening the map in combat creates dots without blocked actions, got " .. table.concat(BLOCKED, ", "))
STATE.combat = false
annaPin = pinOf(11)
check(annaPin.Ring.color[1] == 0 and not annaPin.Skull.shown and not annaPin.Pulse:IsPlaying(), "normal look: dark ring, no skull")
annaPin:OnMouseEnter()
local function tooltipHas(text) for _, l in ipairs(TOOLTIP.lines) do if l == text then return true end end return false end
check(TOOLTIP.title == "Anna" and TOOLTIP.shown, "tooltip: name")
check(TOOLTIP.lines[1] == "Annie" and tooltipHas("Level 20") and tooltipHas("Elwynn Forest - Goldshire"),
	"tooltip: BattleTag, level, zone and subzone; got " .. table.concat(TOOLTIP.lines, " | "))
check(tooltipHas("355 yd south-west"), "tooltip: distance and direction from me")
annaPin:OnMouseLeave()
check(not TOOLTIP.shown, "tooltip hides on leave")
OpenWorldMap(1415)
check(#PINS == 2 and math.abs(pinOf(11).x - 0.3125) < 1e-6 and math.abs(pinOf(11).y - 0.4375) < 1e-6,
	"continent map: same friends, continent coordinates")
OpenWorldMap(1414)
check(#PINS == 0, "map of another continent: not shown")
OpenWorldMap(1429)
annaPin = pinOf(11)
local created = PINS_CREATED
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;C;0;260.0;750.0;Goldshire;Hogger", "WHISPER", 11)
Advance(0.6)
check(pinOf(11) == annaPin and PINS_CREATED == created and math.abs(annaPin.y - 0.74) < 1e-6,
	"moving dots are updated in place, not recreated")
check(annaPin.Ring.color[1] == 1 and annaPin.Pulse:IsPlaying(), "in combat: red pulsing ring")
annaPin:OnMouseEnter()
check(tooltipHas("Fighting Hogger"), "tooltip: who she's fighting")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;D;0;260.0;750.0;Goldshire;", "WHISPER", 11)
Advance(0.6)
check(annaPin.Skull.shown and not annaPin.Dot.shown and not annaPin.Pulse:IsPlaying(), "dead: a skull instead of the dot")
check(tooltipHas("Dead") and TOOLTIP.owner == annaPin, "the open tooltip updates too")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;G;0;260.0;750.0;Goldshire;", "WHISPER", 11)
Advance(0.6)
check(annaPin.Skull.shown and annaPin.Skull.alpha < 1 and tooltipHas("Ghost"), "ghost: a faded skull")
annaPin:OnMouseLeave()
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;260.0;750.0;Goldshire;", "WHISPER", 11)
BN_FRIENDS[1][1].isGameAFK = true
Advance(0.6)
annaPin:OnMouseEnter()
check(TOOLTIP.title == "Anna <AFK>" and not annaPin.Skull.shown, "alive again; AFK shows in the tooltip")
annaPin:OnMouseLeave()
BN_FRIENDS[1][1].isGameAFK = false
GROUP_GUIDS["Player-1-11"] = true
PARTY.party1 = { guid = "Player-1-11", continent = 0, north = 300, west = 700 } -- her live position
GROUP = "party"
Fire("GROUP_ROSTER_UPDATE")
Advance(0.6)
annaPin = pinOf(11)
check(#PINS == 2 and annaPin, "Anna joined the group: her Beacon dot stays")
check(math.abs(annaPin.x - 0.3) < 1e-6 and math.abs(annaPin.y - 0.7) < 1e-6,
	"at her live group position (where Blizzard's dot is), not her last Beacon report")
check(annaPin.Ring.color[3] == 1 and annaPin.Ring.color[1] < 0.5, "marked as a group member: blue ring")
annaPin:OnMouseEnter()
check(tooltipHas("In your group"), "tooltip: in your group")
annaPin:OnMouseLeave()
PARTY.party1.north = 320
Advance(0.05)
check(math.abs(annaPin.y - 0.68) < 1e-6, "follows her live position every frame while the map is open")
B("showGroup"):SetValue(false)
Advance(0.6)
check(#PINS == 1 and pinOf(12), "'show friends in my group too' off: only Blizzard's dot")
B("showGroup"):SetValue(true)
GROUP_GUIDS["Player-1-11"], PARTY.party1, GROUP = nil, nil, "none"
Fire("GROUP_ROSTER_UPDATE")
Advance(0.6)
check(#PINS == 2 and pinOf(11) and pinOf(11).Ring.color[1] == 0, "left the group: a normal dot again")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;;;;;", "WHISPER", 12)
Advance(0.6)
check(#PINS == 1 and pinOf(11), "Bob went into a dungeon (no position): his dot goes away")
BN_FRIENDS[1][1].isOnline = false
Fire("BN_FRIEND_ACCOUNT_OFFLINE", 1, false)
Advance(1.2)
check(not peers()[11] and #PINS == 0, "Anna logged off: forgotten at once")
BN_FRIENDS[1][1].isOnline = true
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;250.0;750.0;Goldshire;", "WHISPER", 11)
Advance(1.2)
check(#PINS == 1, "she's back")
B("showFriends"):SetValue(false)
Advance(0.6)
check(#PINS == 0, "'show friends on the world map' off: no dots")
B("showFriends"):SetValue(true)
Advance(0.6)
check(#PINS == 1, "on again: dots back")
WorldMapFrame:Hide()
Advance(70)
check(not peers()[12], "Bob went silent (no heartbeat for over a minute): forgotten")

section("Beacon: friends on the minimap")
local mm = BB.GetMinimapPins()
PLAYER_POS = { 0.5, 0.5 } -- me: north 500, west 500
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;550.0;500.0;;", "WHISPER", 11) -- Anna 50 yd north
Advance(1.6) -- new friend: name and class arrive on the next check
local function at(pin) local _, rel, _, x, y = pin:GetPoint(1); return rel, x, y end
local rel, x, y = at(mm[11])
check(mm[11] and mm[11]:GetParent() == Minimap and mm[11]:IsShown(), "Anna's dot is on the minimap")
check(rel == Minimap and math.abs(x) < 1e-6 and math.abs(y - 35) < 1e-6,
	"50 yd north at 100 yd view radius on a 140 px minimap: 35 px up, got " .. tostring(x) .. ", " .. tostring(y))
check(mm[11]._motion == true and mm[11]._click == false, "hover for the tooltip, clicks go through to the minimap")
local calls = UNIT_POSITION_CALLS
Advance(0.5)
check(UNIT_POSITION_CALLS > calls, "my position comes from UnitPosition once it agrees with the map position")
do -- a loading screen: checked again (another continent or instance may not agree)
	MOCK_UNITPOS_OFFSET = 50
	Fire("PLAYER_ENTERING_WORLD", false, false)
	local _, north = BB.MyWorldPosition()
	check(north and math.abs(north - 500) < 1e-6, "after a loading screen: the map route until UnitPosition agrees again, got " .. tostring(north))
	MOCK_UNITPOS_OFFSET = 0
	BB.MyWorldPosition() -- they agree again
	MOCK_UNITPOS_OFFSET = 0.5 -- (only UnitPosition says so)
	_, north = BB.MyWorldPosition()
	check(north and math.abs(north - 500.5) < 1e-6, "... and UnitPosition again once it does, got " .. tostring(north))
	MOCK_UNITPOS_OFFSET = 0
	Advance(0.5)
end
local points = mm[11]._points
Advance(1)
check(mm[11]._points == points, "nothing moved: the dot isn't touched")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;550.0;480.0;;", "WHISPER", 11) -- 20 yd further east
Advance(0.5)
rel, x, y = at(mm[11])
check(x > 0.1 and x < 13.5, "her dot glides towards the new position, got x = " .. tostring(x))
Advance(5)
rel, x, y = at(mm[11])
check(math.abs(x - 14) < 1e-6 and math.abs(y - 35) < 1e-6, "and arrives there, got " .. tostring(x) .. ", " .. tostring(y))
CVARS.rotateMinimap, FACING = "1", math.pi / 2 -- rotating minimap, facing west
Advance(0.05)
rel, x, y = at(mm[11])
check(math.abs(x - 35) < 1e-6 and math.abs(y + 14) < 1e-6,
	"rotating minimap: facing west, north is to the right, got " .. tostring(x) .. ", " .. tostring(y))
CVARS.rotateMinimap, FACING = "0", 0
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;999.0;500.0;;", "WHISPER", 11) -- 499 yd north: off the minimap
Advance(0.6)
rel, x, y = at(mm[11])
check(math.abs(x) < 1e-6 and math.abs(y - 65) < 1e-6 and mm[11]._alpha == 0.6, "far away: faded at the edge, in her direction")
B("minimapEdge"):SetValue(false)
Advance(0.6)
check(not mm[11], "edge option off: far-away friends aren't shown")
B("minimapEdge"):SetValue(true)
Advance(0.6)
check(mm[11] ~= nil, "edge option on again")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;C;0;550.0;500.0;;Hogger", "WHISPER", 11)
Advance(0.6)
check(mm[11].Ring.color[1] == 1 and mm[11].Pulse:IsPlaying(), "same status look on the minimap")
BB.GetMinimapPins()[11]._scripts.OnEnter(mm[11])
check(TOOLTIP.title == "Anna" and tooltipHas("Fighting Hogger") and tooltipHas("50 yd north"), "same tooltip on the minimap")
mm[11]._scripts.OnLeave(mm[11])
GROUP_GUIDS["Player-1-11"] = true
PARTY.party1 = { guid = "Player-1-11", continent = 0, north = 560, west = 490 } -- live: 60 yd N, 10 yd E
GROUP = "party"
Fire("GROUP_ROSTER_UPDATE")
Advance(0.6)
rel, x, y = at(mm[11])
check(mm[11] and math.abs(x - 7) < 1e-6 and math.abs(y - 42) < 1e-6,
	"group member on the minimap: at her live position, got " .. tostring(x) .. ", " .. tostring(y))
check(mm[11].Ring.color[1] == 1 and mm[11].Pulse:IsPlaying(), "in combat the red ring still wins over the group ring")
PARTY.party1.north = 570
Advance(0.05)
rel, x, y = at(mm[11])
check(math.abs(y - 49) < 1e-6, "and follows her every frame")
B("showGroup"):SetValue(false)
Advance(0.6)
check(not mm[11], "'show friends in my group too' off: left to Blizzard's minimap blip")
B("showGroup"):SetValue(true)
GROUP_GUIDS["Player-1-11"], PARTY.party1, GROUP = nil, nil, "none"
Fire("GROUP_ROSTER_UPDATE")
Advance(0.6)
B("showMinimap"):SetValue(false)
Advance(0.6)
check(next(mm) == nil, "'show friends on the minimap' off: no dots")
B("showMinimap"):SetValue(true)
Advance(0.6)
check(mm[11] ~= nil, "on again")

section("Beacon: sharing my state")
mark = #GAMEDATA + 1
STATE.combat, STATE.target, STATE.targetName = true, true, "Hogger"
Fire("PLAYER_REGEN_DISABLED")
Advance(1.2)
check(last(GameDataTo(11, mark)) == "S2;C;0;500.0;500.0;Goldshire;Hogger",
	"entering combat goes out within a second, with my target, got " .. tostring(last(GameDataTo(11, mark))))
mark = #GAMEDATA + 1
for i = 1, 5 do
	STATE.targetName = "Mob" .. i
	Fire("PLAYER_TARGET_CHANGED")
	Advance(0.1)
end
check(#GameDataTo(11, mark) <= 1, "tab-targeting: at most one update a second, got " .. #GameDataTo(11, mark))
Advance(1.2)
check(last(GameDataTo(11, mark)):find(";Mob5$") ~= nil, "the latest target wins")
STATE.targetName = SECRET
Fire("PLAYER_TARGET_CHANGED")
Advance(1.2)
check(last(GameDataTo(11, mark)) == "S2;C;0;500.0;500.0;Goldshire;", "a name the game keeps secret isn't sent")
STATE.combat, STATE.target, STATE.targetName = false, false, nil
Fire("PLAYER_REGEN_ENABLED")
Advance(1.2)
check(last(GameDataTo(11, mark)) == "S2;;0;500.0;500.0;Goldshire;", "leaving combat")
STATE.dead = true
Fire("PLAYER_DEAD")
Advance(1.2)
check(last(GameDataTo(11, mark)) == "S2;D;0;500.0;500.0;Goldshire;", "dead")
STATE.ghost = true
Fire("PLAYER_ALIVE")
Advance(1.2)
check(last(GameDataTo(11, mark)) == "S2;G;0;500.0;500.0;Goldshire;", "released: ghost")
STATE.dead, STATE.ghost = false, false
Fire("PLAYER_UNGHOST")
Advance(1.2)
mark = #GAMEDATA + 1
STATE.inInstance = true
Fire("ZONE_CHANGED_NEW_AREA")
Advance(1.2)
check((last(GameDataTo(11, mark)) or ""):find("^S2;;;;;") ~= nil, "in a dungeon: no position")
mark = #GAMEDATA + 1
Advance(12)
check(#GameDataTo(11, mark) == 0, "and nothing more while inside")
STATE.inInstance = false
Fire("ZONE_CHANGED_NEW_AREA")
Advance(1.2)
check((last(GameDataTo(11, mark)) or ""):find("^S2;;0;500.0;500.0;") ~= nil, "back outside: position again")
mark = #GAMEDATA + 1
B("share"):SetValue(false)
Advance(1.2)
check(last(GameDataTo(11, mark)) == "S2;;;;;;", "sharing off: no position and no status")
B("share"):SetValue(true)
Advance(1.2)
B("interval"):SetValue(5)
Advance(5)
mark = #GAMEDATA + 1
for i = 1, 10 do
	PLAYER_POS = { 0.5 + i / 1000, 0.5 }
	Advance(1)
end
local n = #GameDataTo(11, mark)
check(n >= 2 and n <= 3, "interval 5 s while moving: every 5 s, got " .. n)
lefthy("beacon interval 3")
check(BDB.interval == 3 and B("interval").uiUpdates > 0, "/lefthy beacon interval 3, through the setting (an open settings page follows)")
mark = #GAMEDATA + 1
MOCK_SEND_RESULT = 3 -- the server says: slow down
PLAYER_POS = { 0.6, 0.5 }
Advance(3.2)
check(#GameDataTo(11, mark) == 0, "throttled: nothing gets through")
MOCK_SEND_RESULT = nil
Advance(2.5)
check(#GameDataTo(11, mark) >= 1, "after a short pause it's sent again")
-- 30 more friends with the addon show up at once: answers are spread out, not one burst.
for i = 1, 30 do
	BN_FRIENDS[#BN_FRIENDS + 1] = { { gameAccountID = 100 + i, isOnline = true, clientProgram = "WoW", wowProjectID = 1,
		isInCurrentRegion = true, characterName = "Extra" .. i, classFilename = "MAGE", characterLevel = 10,
		areaName = "Westfall", playerGuid = "Player-1-" .. (100 + i) }, battleTag = "Extra#" .. i }
end
Advance(1.1) -- let the rate limiter fill up
mark = #GAMEDATA + 1
for i = 1, 30 do Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;;;;;", "WHISPER", 100 + i) end
Advance(0.15)
local burst = #GAMEDATA - mark + 1
check(burst >= 5 and burst <= 12, "rate limit: about 10 messages at once, got " .. burst)
Advance(12.5) -- 30 friends x (files + version + state + level progress) at 10 messages a second
local answered = 0
for i = 1, 30 do if #sentTo(100 + i, mark, "S2;") == 1 then answered = answered + 1 end end
check(answered == 30, "the rest follow within a few seconds, got " .. answered)
for i = 1, 30 do BN_FRIENDS[#BN_FRIENDS] = nil end
Fire("BN_FRIEND_INFO_CHANGED")
Advance(1.2)
local extras = 0
for id in pairs(peers()) do if id > 100 then extras = extras + 1 end end
check(extras == 0, "friends that left the friend list are forgotten")

section("Beacon: a friend with a newer LefthyTools")
local function infoRow(name)
	for _, init in ipairs(LAYOUTS["LefthyTools"]) do
		if init.template == "LefthyToolsSettingsInfoTemplate" and init.data.name == name then return init end
	end
end
local function updateStatus() return infoRow("Updates").data.getValue() end
check(infoRow("Version") and infoRow("Version").data.getValue() == "0.4.0-3-gabc1234", "settings overview: Info section with the installed version")
check(updateStatus():find("Unknown (no friend with LefthyTools online)", 1, true),
	"update status before any friend told us their version, got " .. updateStatus())
local vmark = #PRINTED + 1
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "V2;0.3.9-50-gaaaaaaa", "WHISPER", 11) -- older than mine
Advance(0.15)
check(updateStatus():find("Up to date (compared with 1 friend(s))", 1, true), "a friend on an older build: up to date, got " .. updateStatus())
check(not printedSince(vmark):find("newer LefthyTools", 1, true), "a friend on an older build: no notice here (they get one)")
check(peers()[11].version == "0.3.9-50-gaaaaaaa", "their version is remembered")
local newsMark = #GAMEDATA + 1
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "F2;0123abcd", "WHISPER", 11) -- their build loads other files than mine
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "V2;0.4.0-9-gbbbbbbb", "WHISPER", 11)
check(not printedSince(vmark):find("newer LefthyTools", 1, true), "nothing printed inside the event handler")
Advance(0.15)
check(sentTo(11, newsMark, "U2;")[1] == "U2;" .. LT.WhatsNew.LatestID() .. ";en",
	"I ask them what's new in their build after my newest changelog entry, in my language")
-- They answer: one line per change (newest few, oldest first), then the end, with how many older ones they left out.
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "W2;140;tweaks;Quests on the moon", "WHISPER", 11)
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "W2;141;stargazer;A whole new module", "WHISPER", 11)
Advance(1)
check(not printedSince(vmark):find("newer LefthyTools", 1, true), "the notice waits until their news are complete")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "W2;0;;3", "WHISPER", 11)
Advance(0.15)
local notice = printedSince(vmark)
check(notice:find("What's coming:\n   |cffffd200•|r Misc Tweaks: Quests on the moon\n   |cffffd200•|r stargazer: A whole new module\n"
	.. "   |cffffd200•|r and 3 more", 1, true), "... then lists them, one line each (a module I don't have yet by its key), got\n" .. notice)
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "W2;142;tweaks;Unasked news", "WHISPER", 11)
Advance(0.15)
check(not printedSince(vmark):find("Unasked news", 1, true), "news nobody asked for are ignored")
check(notice:find("Anna has a newer LefthyTools (0.4.0-9-gbbbbbbb, you have 0.4.0-3-gabc1234)", 1, true)
	and notice:find("run Update-LefthyTools.cmd again, then restart the game: this update adds files, a /reload isn't enough.", 1, true),
	"a friend on a newer build that loads other files: told to update and restart the game, got " .. notice)
check(LT.UpdateHint(LT.FILES):find("then /reload (no restart needed).", 1, true)
	and LT.UpdateHint(nil):find("then /reload (or restart the game if the updater says so).", 1, true),
	"the same files: a /reload is enough; a build that doesn't say: the updater tells")
-- And the other way round: Bob's build is older and asks what's new in mine.
do
local askMark = #GAMEDATA + 1
local latest = LT.WhatsNew.LatestID()
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "U2;" .. (latest - 2) .. ";de", "WHISPER", 12)
Advance(0.3)
local answer = sentTo(12, askMark, "W2;")
local newest = ns.CHANGELOG[#ns.CHANGELOG]
check(#answer == 3 and answer[2] == ("W2;%d;%s;%s"):format(newest.id, newest.module, newest.de[1]) and answer[3] == "W2;0;;0",
	"a friend on an older build asks: my newer entries, in their language, then the end, got " .. table.concat(answer, " | "))
askMark = #GAMEDATA + 1
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "U2;0;en", "WHISPER", 12)
Advance(0.3)
check(#sentTo(12, askMark, "W2;") == 0, "... at most once a minute per friend")
Advance(30)
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;260.0;750.0;Goldshire;", "WHISPER", 11) -- (Anna stays around)
Advance(30)
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "U2;0;en", "WHISPER", 12)
Advance(1.5)
answer = sentTo(12, askMark, "W2;")
check(#answer == 9 and answer[8]:find(newest.en[1], 1, true) and answer[9] == "W2;0;;" .. (#ns.CHANGELOG - 8),
	"a long way behind: the 8 newest, and how many older ones were left out, got " .. #answer)
end
vmark = #PRINTED + 1
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "V2;0.5.0", "WHISPER", 11)
Advance(0.15)
check(not printedSince(vmark):find("newer LefthyTools", 1, true), "only once per login")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "V2;not a version!", "WHISPER", 11)
Advance(0.15)
check(peers()[11].version == "0.5.0", "a malformed version message is ignored")
vmark = #PRINTED + 1
lefthy("beacon status")
check(printedSince(vmark):find("LefthyTools 0.5.0", 1, true), "/lefthy beacon status shows each friend's version")
check(updateStatus():find("Newer version available: 0.5.0 (needs a game restart)", 1, true),
	"settings overview: the newest version seen from a friend, and that it needs a restart, got " .. updateStatus())
local updatesTip = infoRow("Updates").data.tooltip
check(type(updatesTip) == "function", "the Updates tooltip is built when it opens")
local tip = updatesTip()
check(tip:find("You: 0.4.0-3-gabc1234", 1, true) and tip:find("Anna|r: 0.5.0  |cffffa040newer", 1, true),
	"it lists my build and each friend's, marked newer / same / older, got\n" .. tip)
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "V2;0.4.0-3-gabc1234", "WHISPER", 11)
Advance(0.15)
check(updatesTip():find("Anna|r: 0.4.0-3-gabc1234  |cff80ff80same", 1, true), "same build")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "V2;0.5.0", "WHISPER", 11) -- back to what the next checks expect
Advance(0.15)
vmark = #PRINTED + 1
lefthy("version")
check(printedSince(vmark):find("a friend has the newer 0.5.0. To update, run Update-LefthyTools.cmd again, then restart the game", 1, true),
	"/lefthy version mentions it too, with the restart, got " .. printedSince(vmark))
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "F2;" .. LT.FILES, "WHISPER", 11) -- the same files as mine after all
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "V2;0.5.0", "WHISPER", 11)
Advance(0.15)
vmark = #PRINTED + 1
lefthy("version")
check(printedSince(vmark):find("then /reload (no restart needed)", 1, true) and not updateStatus():find("restart", 1, true),
	"a newer build with the same files: a /reload is enough")
-- Forgotten and back (65 s of silence, a loading screen, Beacon off and on): their version only
-- comes in answers, and they don't see me as new, so I greet them and they answer.
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "Q2", "WHISPER", 11)
Advance(0.15)
check(not peers()[11], "(Anna is forgotten)")
local hmark = #GAMEDATA + 1
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;260.0;750.0;Goldshire;", "WHISPER", 11)
Advance(0.15)
check(peers()[11] and peers()[11].version == nil and sentTo(11, hmark, "H2")[1] == "H2",
	"back with an ordinary message: I greet them, so they answer with their version")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "V2;0.5.0", "WHISPER", 11)
Advance(0.15)
check(peers()[11].version == "0.5.0" and #sentTo(11, hmark, "H2") == 1, "and it's known again (one hello)")
-- My version also goes to every friend every 10 minutes, whatever happened to the answers.
local versionMark = #GAMEDATA + 1
for _ = 1, 21 do
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;260.0;750.0;Goldshire;", "WHISPER", 11) -- Anna stays around
	Advance(30)
end
local repeats = sentTo(11, versionMark, "V2;")
check(#repeats == 1 and repeats[1] == "V2;0.4.0-3-gabc1234", "my version, repeated once in 10 minutes, got " .. #repeats)
do
	local filesRepeats, filesAt, versionAt = sentTo(11, versionMark, "F2;"), nil, nil
	for i, message in ipairs(GameDataTo(11, versionMark)) do
		if message:find("^F2;") then filesAt = i elseif message:find("^V2;") then versionAt = i end
	end
	check(#filesRepeats == 1 and filesRepeats[1] == "F2;" .. LT.FILES and filesAt and versionAt and filesAt < versionAt,
		"... with my files just before it")
end

section("Beacon: death alerts")
check(BDB.deathAlert == true and B("deathAlert") ~= nil, "a setting, on by default")
local heard = {} -- what other modules (Chronicle) are told
table.insert(BB.listeners, function(kind, peer, data) heard[#heard + 1] = { kind = kind, name = peer.name, data = data } end)
local function anna(state) Fire("BN_CHAT_MSG_ADDON", "LTBeacon", state, "WHISPER", 11) end
Advance(10)
afk(true) -- away while it happens: the AFK screen lists it
Advance(0.05)
anna("S2;C;0;260.0;750.0;Raven Hill;Stitches")
Advance(1.2)
pmark = #PRINTED + 1
anna("S2;D;0;260.0;750.0;Raven Hill;")
check(#PRINTED < pmark, "nothing printed inside the event handler")
Advance(0.15)
local deathLine = printedSince(pmark)
check(deathLine:find("Anna|r died in Elwynn Forest - Raven Hill, fighting Stitches.", 1, true),
	"a chat line: who died, where, and what they were fighting, got " .. deathLine)
check(heard[#heard] and heard[#heard].kind == "death" and heard[#heard].name == "Anna" and heard[#heard].data.foe == "Stitches"
	and heard[#heard].data.where == "Elwynn Forest - Raven Hill", "other modules hear about it")
Advance(1.1)
check(LefthyToolsAFKFrame:IsShown() and LefthyToolsAFKFrame.Info:GetText():find("While you were away|r\n", 1, true)
	and LefthyToolsAFKFrame.Info:GetText():find("Anna|r died, fighting Stitches", 1, true),
	"the AFK screen: 'While you were away' lists it, got " .. LefthyToolsAFKFrame.Info:GetText())
check(LefthyToolsAFKFrame.Friends:GetText():find("Anna|r  |cffccccccLevel 20|r", 1, true)
	and LefthyToolsAFKFrame.Friends:GetText():find("Elwynn Forest - Raven Hill", 1, true)
	and LefthyToolsAFKFrame.Friends:GetText():find("|cffff5050Dead|r", 1, true),
	"and the friends online, with their zone and status, got " .. LefthyToolsAFKFrame.Friends:GetText())
afk(false)
Advance(0.3)
pmark = #PRINTED + 1
anna("S2;G;0;260.0;750.0;Raven Hill;")
Advance(1.2)
anna("S2;;0;260.0;750.0;Raven Hill;")
Advance(1.2)
check(not printedSince(pmark):find("died", 1, true), "releasing and coming back: no more alerts")
anna("S2;D;0;260.0;750.0;Raven Hill;")
Advance(0.15)
check(not printedSince(pmark):find("died", 1, true), "dying again within 10 s: not repeated")
Advance(10)
anna("S2;;0;260.0;750.0;Raven Hill;")
Advance(1.2)
anna("S2;D;0;260.0;750.0;Raven Hill;")
Advance(0.15)
check(printedSince(pmark):find("Anna|r died in Elwynn Forest - Raven Hill.", 1, true), "died out of combat (a fall): no killer")
Advance(10)
pmark = #PRINTED + 1
anna("Q2")
anna("S2;D;0;260.0;750.0;Raven Hill;")
Advance(1.2)
check(not printedSince(pmark):find("died", 1, true), "already dead when first heard of: no alert")
anna("S2;;0;260.0;750.0;Raven Hill;")
Advance(1.2)
B("deathAlert"):SetValue(false)
Advance(10)
local heardBefore = #heard
anna("S2;D;0;260.0;750.0;Raven Hill;")
Advance(0.15)
check(not printedSince(pmark):find("died", 1, true) and #heard == heardBefore + 1, "alerts off: no chat line (other modules still hear it)")
B("deathAlert"):SetValue(true)
anna("S2;;0;260.0;750.0;Goldshire;")
Advance(1.2)

section("Beacon: map pings")
check(BDB.pings == true and B("pings") ~= nil, "a setting, on by default")
local function pingPin(key)
	for _, p in ipairs(PINS) do if p.pinTemplate == "LefthyToolsBeaconPingPinTemplate" and p.key == key then return p end end
end
PLAYER_POS = { 0.5, 0.5 } -- me: north 500, west 500
OpenWorldMap(1429)
Advance(0.2)
mark, pmark = #GAMEDATA + 1, #PRINTED + 1
MOCK_CURSOR = { 0.25, 0.75 }
ClickWorldMap()
Advance(0.15)
check(#sentTo(11, mark, "P2;") == 0, "a click without Alt doesn't ping")
STATE.alt = true
ClickWorldMap()
Advance(0.15)
check(sentTo(11, mark, "P2;")[1] == "P2;0;250.0;750.0;1429", "Alt+click: the spot goes to my friends, got " .. tostring(sentTo(11, mark, "P2;")[1]))
check(printedSince(pmark):find("pinged Elwynn Forest for 1 friend(s).", 1, true) and SOUNDS[#SOUNDS] == 3175,
	"with a chat line and the map ping sound")
Advance(0.15)
local myPing = pingPin("me")
check(myPing and math.abs(myPing.x - 0.25) < 1e-6 and math.abs(myPing.y - 0.75) < 1e-6 and myPing.RippleAnim:IsPlaying(),
	"my own marker on my map, rippling")
check(myPing.Icon.atlas == "Ping_Marker_Icon_NonThreat", "the game's 'look here' ping icon")
pmark = #PRINTED + 1
ClickWorldMap()
Advance(0.15)
check(#sentTo(11, mark, "P2;") == 1 and printedSince(pmark):find("not so fast", 1, true),
	"at most one ping every 2.5 s (friends drop more than one per 2 s), and it says so")
Advance(2)
ClickWorldMap()
Advance(0.15)
check(#sentTo(11, mark, "P2;") == 1, "still too soon 2.3 s later")
Advance(0.3)
OpenWorldMap(1415)
MOCK_CURSOR = { 0.375, 0.375 } -- inside Elwynn on the continent map: north 500, west 500
ClickWorldMap()
STATE.alt = false
Advance(0.15)
check(sentTo(11, mark, "P2;")[2] == "P2;0;500.0;500.0;1429", "on a continent map the zone under the cursor names the spot")
OpenWorldMap(1429)
pmark = #PRINTED + 1
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "P2;0;550.0;500.0;1429", "WHISPER", 11)
check(#PRINTED < pmark, "receiving: nothing printed inside the event handler")
Advance(0.15)
check(printedSince(pmark):find("Anna|r pinged a spot in Elwynn Forest: see your map.", 1, true) and SOUNDS[#SOUNDS] == 3175,
	"a friend's ping: chat line and sound, got " .. printedSince(pmark))
check(printedSince(pmark):find("map. |cffffff00|Hworldmap:1429:5000:4500|h[Map pin]|h|r", 1, true),
	"with the game's map pin link for the spot (a click sets the waypoint), got " .. printedSince(pmark))
Advance(0.15)
local annaPing = pingPin(11)
check(annaPing and math.abs(annaPing.x - 0.5) < 1e-6 and math.abs(annaPing.y - 0.45) < 1e-6
	and math.abs(annaPing.Ripple.color[3] - 0.92) < 1e-6, "her marker on my map, rippling in her class colour")
annaPing:OnMouseEnter()
check(TOOLTIP.title == "Anna" and tooltipHas("Map ping, 0 s ago") and tooltipHas("Elwynn Forest") and tooltipHas("50 yd north"),
	"tooltip: whose ping, how old, where, how far, got " .. table.concat(TOOLTIP.lines, " | "))
annaPing:OnMouseLeave()
local mmPings = BB.GetMinimapPings()
local _, _, _, pingX, pingY = mmPings[11]:GetPoint(1)
check(math.abs(pingX) < 1e-6 and math.abs(pingY - 35) < 1e-6 and mmPings[11]:GetParent() == Minimap, "and on the minimap, 50 yd north")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "P2;0;100.0;100.0;1429", "WHISPER", 11)
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "P2;0;abc;1;1429", "WHISPER", 11)
Advance(0.15)
check(BB.pings[11].north == 550, "another ping within 2 s and malformed pings are ignored")
Advance(51)
check(annaPing:GetAlpha() < 1 and not annaPing.RippleAnim:IsPlaying(), "after a while: the ripple stops and the marker fades")
Advance(10)
check(not BB.pings[11] and not pingPin(11) and not mmPings[11], "after a minute it's gone from both maps")
B("pings"):SetValue(false)
mark = #GAMEDATA + 1
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "P2;0;550.0;500.0;1429", "WHISPER", 11)
STATE.alt = true
ClickWorldMap()
STATE.alt = false
Advance(2.5)
check(not BB.pings[11] and #sentTo(11, mark, "P2;") == 0, "pings off: none shown, none sent")
B("pings"):SetValue(true)
lefthy("beacon ping")
Advance(0.15)
check(sentTo(11, mark, "P2;")[1] == "P2;0;500.0;500.0;1429", "/lefthy beacon ping: where I stand")
-- Taking it back: Alt+click on my own marker (or /lefthy beacon ping clear), for everyone.
Advance(2)
local mine = pingPin("me")
mine:OnMouseEnter()
check(tooltipHas("Alt+click it on the world map to take it back."), "my own marker's tooltip says how to take it back")
mine:OnMouseLeave()
mark, pmark = #GAMEDATA + 1, #PRINTED + 1
mine._mouse, STATE.alt = true, true
ClickWorldMap()
mine._mouse, STATE.alt = false, false
Advance(0.15)
check(not BB.pings.me and #sentTo(11, mark, "P2;") == 0 and sentTo(11, mark, "G2")[1] == "G2"
	and printedSince(pmark):find("ping taken back.", 1, true), "Alt+click on my own marker: taken back and my friends told, no new ping")
Advance(0.15)
check(not pingPin("me") and not BB.GetMinimapPings().me, "gone from my maps")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "P2;0;550.0;500.0;1429", "WHISPER", 11)
Advance(0.15)
check(BB.pings[11] and pingPin(11), "Anna pings")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "G2", "WHISPER", 11)
Advance(0.15)
check(not BB.pings[11] and not pingPin(11) and not BB.GetMinimapPings()[11], "... and takes it back: gone from both maps")
lefthy("beacon ping")
Advance(0.15)
lefthy("beacon ping clear")
Advance(0.15)
check(not BB.pings.me and not pingPin("me"), "/lefthy beacon ping clear")
pmark = #PRINTED + 1
lefthy("beacon ping clear")
check(printedSince(pmark):find("no ping out", 1, true), "nothing to take back: said so")
WorldMapFrame:Hide()

section("Beacon: tracked quest")
check(BDB.shareQuest == true and B("shareQuest") ~= nil, "a setting, on by default")
QUESTS = {
	{ id = 176, title = 'Wanted: "Hogger"', objectives = { { text = "Huge Gnoll Claw: 0/1", finished = false } } },
	{ id = 177, title = "Kobold Camp Cleanup", objectives = { { text = "Kobold Vermin slain: 4/10", finished = false } } },
}
WATCHED = { 176, 177 }
mark = #GAMEDATA + 1
Fire("QUEST_WATCH_LIST_CHANGED")
check(#sentTo(11, mark, "T2;") == 0, "nothing sent inside the event handler")
Advance(2.2)
check(sentTo(11, mark, "T2;")[1] == 'T2;176;0;Wanted: "Hogger";Huge Gnoll Claw: 0/1',
	"the first quest on my tracker goes to my friends, got " .. tostring(sentTo(11, mark, "T2;")[1]))
for _ = 1, 20 do
	Fire("QUEST_LOG_UPDATE")
	Advance(0.1)
end
check(#sentTo(11, mark, "T2;") == 1, "the quest log updates often: nothing more sent while nothing changed")
QUESTS[1].objectives[1] = { text = "Huge Gnoll Claw: 1/1", finished = true }
Fire("QUEST_LOG_UPDATE")
Advance(2.2)
check(sentTo(11, mark, "T2;")[2] == 'T2;176;1;Wanted: "Hogger";', "ready to turn in")
SUPER_TRACKED = 177
Fire("SUPER_TRACKING_CHANGED")
Advance(2.2)
check(sentTo(11, mark, "T2;")[3] == "T2;177;0;Kobold Camp Cleanup;Kobold Vermin slain: 4/10", "the super-tracked quest wins")
local tmark = #GAMEDATA + 1
for i = 5, 9 do
	QUESTS[2].objectives[1].text = "Kobold Vermin slain: " .. i .. "/10"
	Fire("QUEST_LOG_UPDATE")
	Advance(0.2)
end
check(#sentTo(11, tmark, "T2;") <= 1, "progress goes out at most every 2 s, got " .. #sentTo(11, tmark, "T2;"))
Advance(2.2)
check(last(sentTo(11, tmark, "T2;")):find("9/10$") ~= nil, "and the latest progress follows")
tmark = #GAMEDATA + 1
anna("H2")
Advance(0.15)
check(sentTo(11, tmark, "T2;")[1] == "T2;177;0;Kobold Camp Cleanup;Kobold Vermin slain: 9/10", "a hello is answered with my quest too")
B("shareQuest"):SetValue(false)
Advance(0.2)
check(last(sentTo(11, tmark, "T2;")) == "T2;0;;;", "not shared: friends are told there's none")
B("shareQuest"):SetValue(true)
Advance(0.2)
OpenWorldMap(1429)
anna("T2;176;0;Wanted: Hogger;Huge Gnoll Claw: 0/1")
Advance(0.6)
pinOf(11):OnMouseEnter()
check(tooltipHas("Quest: Wanted: Hogger") and tooltipHas("  Huge Gnoll Claw: 0/1") and tooltipHas("  You have this quest too"),
	"tooltip: their quest, their progress, and that I have it too, got " .. table.concat(TOOLTIP.lines, " | "))
anna("T2;176;1;Wanted: Hogger;")
Advance(0.6)
check(tooltipHas("  Ready to turn in"), "the open tooltip follows: ready to turn in")
anna("T2;900;0;Some Other Quest;Thing: 1/2")
Advance(0.6)
check(tooltipHas("Quest: Some Other Quest") and not tooltipHas("  You have this quest too"), "a quest I don't have")
anna("T2;abc;0;x;y")
Advance(0.6)
check(peers()[11].quest and peers()[11].quest.id == 900, "malformed quest messages are ignored")
anna("T2;0;;;")
Advance(0.6)
local questLine = false
for _, l in ipairs(TOOLTIP.lines) do if l:find("^Quest: ") then questLine = true end end
check(not questLine, "none tracked: no quest lines")
pinOf(11):OnMouseLeave()
WorldMapFrame:Hide()
QUESTS, WATCHED, SUPER_TRACKED = {}, {}, 0
Fire("QUEST_LOG_UPDATE")
Advance(2.2)

section("Beacon: level-ups")
lefthy("beacon ding {name} hit {level}, drinks on me!")
check(BDB.dingText == "{name} hit {level}, drinks on me!" and B("dingText"):GetValue() == BDB.dingText,
	"/lefthy beacon ding <text> keeps upper case and goes through the setting")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "H2", "WHISPER", 12) -- Bob is back
Advance(0.3)
mark = #GAMEDATA + 1
Fire("PLAYER_LEVEL_UP", 20, 0, 0, 0, 0, 0, 0, 0, 0)
check(#GameDataTo(11, mark) == 0, "nothing sent inside the event handler")
Advance(0.15)
check(GameDataTo(11, mark)[1] == "L2;20;{name} hit {level}, drinks on me!" and GameDataTo(12, mark)[1] == GameDataTo(11, mark)[1],
	"my level-up goes to every friend with my own text, got " .. tostring(GameDataTo(11, mark)[1]))
mark = #GAMEDATA + 1
MOCK_SEND_RESULT = 11 -- addon messages locked (e.g. during an encounter)
Fire("PLAYER_LEVEL_UP", 21)
Advance(1)
check(#GameDataTo(11, mark) == 0, "level-up during an addon message lockdown: nothing gets through")
MOCK_SEND_RESULT = nil
Advance(3)
local delivered = false
for _, m in ipairs(GameDataTo(11, mark)) do if m:find("^L2;21;") then delivered = true end end
check(delivered, "... and it's delivered once the lockdown ends instead of being lost")
B("dingAnnounce"):SetValue(false)
mark = #GAMEDATA + 1
Fire("PLAYER_LEVEL_UP", 21)
Advance(0.15)
local dingSent = false
for _, m in ipairs(GameDataTo(11, mark)) do if m:sub(1, 2) == "L2" then dingSent = true end end
check(not dingSent, "'tell my friends' off: not announced")
B("dingAnnounce"):SetValue(true)

pmark = #PRINTED + 1
local soundMark = #SOUNDS
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "L2;21;{name} is now {level}!", "WHISPER", 11)
check(#PRINTED < pmark, "nothing shown inside the event handler")
Advance(0.15)
local shown = printedSince(pmark)
check(shown:find("Anna|r is now 21!", 1, true) ~= nil and shown:find("|cff40c7eb", 1, true) ~= nil,
	"Anna's own message, her name in class colour, got " .. shown)
check(SOUNDS[#SOUNDS] == 50111 and #SOUNDS == soundMark + 1, "with the picked sound (default: boss defeated fanfare, not the level-up fanfare)")
check(heard[#heard].kind == "level" and heard[#heard].data.level == 21, "other modules hear about level-ups too")
local toastFrame
for _, f in ipairs(UIParent._children) do if f.Text and f.shownAt then toastFrame = f end end
check(toastFrame and toastFrame:IsShown() and toastFrame.Text.text:find("is now 21!", 1, true), "big text on screen")
check(toastFrame.Text.textScale == 1.4 and toastFrame.Pop.plays > 0, "extra big, and it pops in")
Advance(7)
check(not toastFrame:IsShown(), "and it fades out after a few seconds")
pmark = #PRINTED + 1
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "L2;22;", "WHISPER", 11)
Advance(0.15)
check(#PRINTED < pmark, "a second level-up message within 10 s is ignored (spam guard)")
for _ = 1, 3 do -- switching Beacon off and on in between doesn't reset the guard
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "Q2", "WHISPER", 11)
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "L2;22;", "WHISPER", 11)
	Advance(1.2)
end
check(#PRINTED < pmark, "... also when the friend sends Q2 in between")
mark = #GAMEDATA + 1
for _ = 1, 8 do
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "H2", "WHISPER", 11)
	Advance(0.3)
end
check(#sentTo(11, mark, "S2;") <= 1 and #sentTo(11, mark, "V2;") <= 1,
	"repeated hellos get at most one answer per 5 s, got " .. #GameDataTo(11, mark) .. " messages")
Advance(10)
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "L2;22;", "WHISPER", 11)
Advance(0.15)
check(printedSince(pmark):find("Anna|r reached level 22!", 1, true) ~= nil, "no text of her own: my default")
Advance(10)
pmark = #PRINTED + 1
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "L2;23;|cffff0000evil|r {name}", "WHISPER", 11)
Advance(0.15)
shown = printedSince(pmark)
check(shown:find("evil", 1, true) and not shown:find("ff0000", 1, true), "escape sequences in a friend's text are stripped")
Advance(10)
B("dingSound"):SetValue(false)
soundMark = #SOUNDS
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "L2;24;", "WHISPER", 12)
Advance(0.15)
check(#SOUNDS == soundMark, "'play a sound' off: silent")
B("dingSound"):SetValue(true)
Advance(10)
MOCK_SOUND_MISSING = 50111
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "L2;25;", "WHISPER", 12)
Advance(0.15)
check(SOUNDS[#SOUNDS - 1] == 50111 and SOUNDS[#SOUNDS] == 18019, "sound missing in this client: the Battle.net toast sound instead")
MOCK_SOUND_MISSING = nil
B("dingShow"):SetValue(false)
Advance(10)
pmark = #PRINTED + 1
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "L2;26;", "WHISPER", 11)
Advance(0.15)
check(#PRINTED < pmark, "'show my friends' level-ups' off: nothing shown")
B("dingShow"):SetValue(true)
pmark = #PRINTED + 1
SETTINGS_BUTTONS["Test your message"].onClick()
check(printedSince(pmark):find("Lefthy|r hit 20, drinks on me!", 1, true) ~= nil, "preview button shows my own message")
lefthy("beacon ding reset")
check(BDB.dingText == "", "/lefthy beacon ding reset")
pmark = #PRINTED + 1
lefthy("beacon ding test")
check(printedSince(pmark):find("Lefthy|r reached level 20!", 1, true) ~= nil, "/lefthy beacon ding test")
-- A slider whose label names the sound (no dropdown: a Blizzard menu from addon settings taints gamepad mode).
local soundSlider = B("dingSoundKit")
local soundOptions = soundSlider and soundSlider.sliderOptions
check(soundSlider and soundSlider.proxy and not DROPDOWNS.LefthyTools_beacon_dingSoundKit and BDB.dingSoundKit == 50111
	and soundSlider:GetValue() == 1 and soundOptions.min == 1 and soundOptions.max == 6 and soundOptions.formatter(1) == "Boss defeated fanfare",
	"level-up sound: a slider over 6 sounds that names them, boss defeated fanfare by default")
local hasLevelUpFanfare = false
for i = 1, 6 do if soundOptions.formatter(i):find("Level up", 1, true) then hasLevelUpFanfare = true end end
check(not hasLevelUpFanfare, "the player's own level-up fanfare isn't offered (it sounds like you levelled)")
soundMark = #SOUNDS
soundSlider:SetValue(2)
check(BDB.dingSoundKit == 73277 and #SOUNDS == soundMark, "sliding to the second: its sound kit is kept; nothing plays inside the settings callback")
Advance(0.05)
check(#SOUNDS == soundMark + 1 and SOUNDS[#SOUNDS] == 73277, "picking a sound plays it")
Advance(10)
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "L2;27;", "WHISPER", 11)
Advance(0.15)
check(SOUNDS[#SOUNDS] == 73277, "a friend's level-up uses the picked sound")
soundMark = #SOUNDS
pmark = #PRINTED + 1
lefthy("beacon sound")
check(#printedSince(pmark) > 0 and printedSince(pmark):find("2. World quest complete (current)", 1, true) ~= nil,
	"/lefthy beacon sound lists the sounds and marks the current one")
lefthy("beacon sound 1")
Advance(0.05)
check(BDB.dingSoundKit == 50111 and SOUNDS[#SOUNDS] == 50111 and #SOUNDS == soundMark + 1, "/lefthy beacon sound 1 picks it and plays it once")
lefthy("beacon sound 1")
Advance(0.05)
check(#SOUNDS == soundMark + 2, "picking the current one again still plays it")

section("Beacon: how many enemies")
do
	anna("S2;;0;260.0;750.0;Goldshire;")
	Advance(1.2)
	for i = 1, 3 do Fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. i) end
	THREAT = { nameplate1 = 3, nameplate2 = 0 } -- two mobs have me on their list, the third doesn't
	mark = #GAMEDATA + 1
	STATE.combat = true
	Fire("PLAYER_REGEN_DISABLED")
	Advance(1.2)
	check(sentTo(11, mark, "C2;")[1] == "C2;2", "in combat: how many enemies are on me, got " .. tostring(sentTo(11, mark, "C2;")[1]))
	Advance(3)
	check(#sentTo(11, mark, "C2;") == 1, "unchanged: nothing more")
	THREAT.nameplate3 = 1
	Advance(1.1)
	check(sentTo(11, mark, "C2;")[2] == "C2;3", "a third one joins")
	THREAT.nameplate1 = SECRET
	Advance(2.2)
	check(#sentTo(11, mark, "C2;") == 2, "threat kept secret: no count")
	Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
	Fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
	Advance(1.1)
	check(sentTo(11, mark, "C2;")[3] == "C2;1", "nameplates gone (dead or out of range): fewer")
	STATE.combat = false
	Fire("PLAYER_REGEN_ENABLED")
	Advance(3)
	check(#sentTo(11, mark, "C2;") == 3, "out of combat: nothing (the state says the fight is over)")
	Fire("NAME_PLATE_UNIT_REMOVED", "nameplate3")
	THREAT = {}
	mark = #GAMEDATA + 1
	STATE.combat = true
	Fire("PLAYER_REGEN_DISABLED")
	Advance(2.2)
	check(#sentTo(11, mark, "C2;") == 0, "a fight without nameplates: nothing sent")
	STATE.combat = false
	Fire("PLAYER_REGEN_ENABLED")
	Advance(1.2)

	OpenWorldMap(1429)
	anna("S2;C;0;260.0;750.0;Goldshire;Stitches")
	anna("C2;3")
	Advance(0.6)
	local pin = pinOf(11)
	pin:OnMouseEnter()
	check(tooltipHas("Fighting Stitches and 2 more") and pin.Count.shown and pin.Count.text == "3",
		"her dot: a 3, and the tooltip says it, got " .. table.concat(TOOLTIP.lines, " | "))
	anna("S2;C;0;260.0;750.0;Goldshire;")
	anna("C2;4")
	Advance(0.6)
	check(tooltipHas("In combat with 4 enemies"), "no target: how many")
	anna("C2;1")
	Advance(0.6)
	check(tooltipHas("In combat with 1 enemy"), "one")
	anna("C2;abc")
	Advance(0.6)
	check(peers()[11].mobs == 1, "malformed counts are ignored")
	anna("S2;;0;260.0;750.0;Goldshire;")
	Advance(0.6)
	check(not pin.Count.shown and tooltipHas("Level 20") and not tooltipHas("In combat with 1 enemy"), "fight over: the count goes")
	pin:OnMouseLeave()
	WorldMapFrame:Hide()
end

section("Beacon: level progress")
do
	anna("S2;;0;260.0;750.0;Goldshire;")
	Advance(0.2)
	mark = #GAMEDATA + 1
	XP.current = 3000
	Fire("PLAYER_XP_UPDATE")
	check(#sentTo(11, mark, "X2;") == 0, "nothing sent inside the event handler")
	Advance(2.2)
	check(sentTo(11, mark, "X2;")[1] == "X2;50", "my progress on this level goes to friends, got " .. tostring(sentTo(11, mark, "X2;")[1]))
	XP.current = 3010
	for _ = 1, 10 do Fire("PLAYER_XP_UPDATE"); Advance(0.3) end
	check(#sentTo(11, mark, "X2;") == 1, "only when the whole percent changes")
	XP.current = 3700
	Fire("PLAYER_XP_UPDATE")
	Advance(2.2)
	check(sentTo(11, mark, "X2;")[2] == "X2;61", "61%")
	local hmark = #GAMEDATA + 1
	Advance(5)
	anna("H2")
	Advance(0.15)
	check(sentTo(11, hmark, "X2;")[1] == "X2;61", "a hello is answered with it too")
	B("share"):SetValue(false)
	Advance(0.3)
	check(last(sentTo(11, hmark, "X2;")) == "X2;", "sharing off: friends are told it's not shared")
	B("share"):SetValue(true)
	Advance(0.3)
	XP.current = 1500
	Fire("PLAYER_XP_UPDATE")
	Advance(2.2)

	OpenWorldMap(1429)
	anna("X2;64")
	Advance(0.6)
	local pin = pinOf(11)
	pin:OnMouseEnter()
	check(tooltipHas("Level 20 (64%)"), "her tooltip: level and progress, got " .. table.concat(TOOLTIP.lines, " | "))
	anna("X2;abc")
	Advance(0.6)
	check(tooltipHas("Level 20 (64%)"), "malformed: ignored")
	anna("X2;")
	Advance(0.6)
	check(tooltipHas("Level 20"), "not shared: just the level")
	pin:OnMouseLeave()
	WorldMapFrame:Hide()
end

section("AFK screen: what friends are doing")
do
	anna("S2;C;0;260.0;750.0;Raven Hill;Stitches")
	anna("C2;3")
	anna("X2;64")
	anna("T2;176;0;Wanted: Hogger;Huge Gnoll Claw: 0/1")
	Advance(0.3)
	afk(true)
	Advance(1.1)
	local text = LefthyToolsAFKFrame.Friends:GetText()
	check(text:find("Anna|r  |cffccccccLevel 20 (64%)|r", 1, true) and text:find("Elwynn Forest - Raven Hill", 1, true)
		and text:find("Fighting Stitches and 2 more", 1, true)
		and text:find("Quest: Wanted: Hogger|r|cffcccccc - Huge Gnoll Claw: 0/1", 1, true),
		"each friend: level and progress, where, whom and how many they fight, their quest, got\n" .. text)
	anna("S2;;0;260.0;750.0;Raven Hill;")
	anna("T2;176;1;Wanted: Hogger;")
	Advance(1.1)
	text = LefthyToolsAFKFrame.Friends:GetText()
	check(not text:find("Fighting", 1, true) and text:find("Quest: Wanted: Hogger|r|cffcccccc - Ready to turn in", 1, true),
		"out of combat: still what they're doing")
	BN_FRIENDS[1][1].isGameAFK = true
	Advance(1.1)
	check(LefthyToolsAFKFrame.Friends:GetText():find("Anna|r |cff999999<AFK>|r", 1, true), "friends who are AFK too")
	BN_FRIENDS[1][1].isGameAFK = false
	afk(false)
	Advance(0.3)
	anna("X2;")
	anna("T2;0;;;")
	Advance(0.3)
end

section("Beacon: friends on top of each other")
do
	local function bob(state) Fire("BN_CHAT_MSG_ADDON", "LTBeacon", state, "WHISPER", 12) end
	PLAYER_POS = { 0.5, 0.5 } -- me: north 500, west 500
	anna("S2;;0;520.0;500.0;Goldshire;")
	bob("S2;;0;520.0;500.0;Goldshire;") -- the same spot, 20 yd north of me
	Advance(1.2)
	OpenWorldMap(1429)
	Advance(0.6)
	local a, b = pinOf(11), pinOf(12)
	check(a and b and math.abs(a.y - b.y) < 1e-9 and math.abs((b.x - a.x) * 1000 - 11.2) < 0.01 and math.abs((a.x + b.x) / 2 - 0.5) < 1e-6,
		"two friends on one spot: their dots sit side by side around it (map: 1 yd = 1 px here), got "
		.. tostring(a and a.x) .. " / " .. tostring(b and b.x))
	a:OnMouseEnter()
	check(TOOLTIP.title == "Anna" and tooltipHas("Bob") and tooltipHas("Level 20"), "hovering either shows both")
	bob("S2;C;0;520.0;500.0;Goldshire;Hogger")
	Advance(0.6)
	check(tooltipHas("Fighting Hogger"), "the open tooltip follows the other one too")
	a:OnMouseLeave()
	b:OnMouseEnter()
	check(TOOLTIP.title == "Bob" and tooltipHas("Anna"), "the hovered one comes first")
	b:OnMouseLeave()
	bob("S2;;0;380.0;500.0;Goldshire;") -- 140 yd apart now
	Advance(0.6)
	check(math.abs(pinOf(11).x - 0.5) < 1e-6 and not pinOf(11).group and not pinOf(12).group, "apart again: exact positions")
	bob("S2;;0;520.0;500.0;Goldshire;")
	Advance(0.6)
	WorldMapFrame:Hide()
	Advance(0.6)
	local mm = BB.GetMinimapPins()
	local _, _, _, ax, ay = mm[11]:GetPoint(1)
	local _, _, _, bx, by = mm[12]:GetPoint(1)
	check(math.abs(bx - ax - 8) < 1e-6 and math.abs(ay - by) < 1e-6 and math.abs((ax + bx) / 2) < 1e-6,
		"on the minimap too, got " .. tostring(ax) .. " / " .. tostring(bx))
	mm[12]._scripts.OnEnter(mm[12])
	check(TOOLTIP.title == "Bob" and tooltipHas("Anna"), "and hovering shows both")
	mm[12]._scripts.OnLeave(mm[12])
	local spreads, spread = 0, BB.Spread
	BB.Spread = function(...) spreads = spreads + 1; return spread(...) end
	for i = 1, 10 do
		PLAYER_POS = { 0.5, 0.5 + i * 0.002 } -- I walk: both dots move on the minimap, but not apart
		Advance(0.05)
	end
	_, _, _, ax, ay = mm[11]:GetPoint(1)
	_, _, _, bx, by = mm[12]:GetPoint(1)
	check(spreads == 0 and math.abs(bx - ax - 8) < 1e-6 and math.abs(ay - by) < 1e-6,
		"while I walk, the spread is reused instead of worked out every frame, got " .. spreads)
	bob("S2;;0;525.0;500.0;Goldshire;") -- Bob steps 5 yd north (3.5 px here): still overlapping
	Advance(1.2)
	_, _, _, ax, ay = mm[11]:GetPoint(1)
	_, _, _, bx, by = mm[12]:GetPoint(1)
	check(spreads >= 1 and math.abs(by - ay) < 1 and math.abs(bx - ax - 8) < 1,
		"one of them moving: worked out again (still side by side, within a pixel), got " .. spreads .. ", " .. (by - ay))
	BB.Spread = spread
	PLAYER_POS = { 0.5, 0.5 }
	Advance(0.6)
end

section("Beacon: showing and offering items")
do
	local function ctrlRight(link, shift, location)
		STATE.ctrl, STATE.shift, MOCK_BUTTON = true, shift == true, "RightButton"
		HandleModifiedItemClick(link, location)
		STATE.ctrl, STATE.shift = false, false
	end
	local function soundsSince(n)
		local list = {}
		for i = n + 1, #SOUNDS do list[#list + 1] = SOUNDS[i] end
		return "," .. table.concat(list, ",") .. ","
	end
	anna("S2;;0;260.0;750.0;Goldshire;")
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;260.0;750.0;Goldshire;", "WHISPER", 12)
	Advance(1.2)
	check(BDB.shareItems == true and B("shareItems") ~= nil, "a setting, on by default")
	mark, pmark = #GAMEDATA + 1, #PRINTED + 1
	local dressups = DRESSUPS
	ctrlRight(ItemLink(1155))
	check(DRESSUPS == dressups + 1, "Blizzard's own handling runs first")
	local emptyOk, emptyErr = pcall(ctrlRight, nil) -- an empty slot: Blizzard passes no link
	check(emptyOk, "Ctrl+right-click on an empty slot: no error, got " .. tostring(emptyErr))
	Advance(0.15)
	check(sentTo(11, mark, "I2;")[1] == "I2;1155::::::::20:::::", "Ctrl+right-click shows the item to my friends, got " .. tostring(sentTo(11, mark, "I2;")[1]))
	check(printedSince(pmark):find("shared " .. ItemLink(1155) .. " with ", 1, true), "and I'm told")
	ctrlRight(ItemLink(1155))
	Advance(0.15)
	check(#sentTo(11, mark, "I2;") == 1 and printedSince(pmark):find("one item every 3 seconds: try again in a moment", 1, true),
		"at most one every 3 s, and I'm told")
	Advance(3)
	-- A link that can't be read: said so, with the link, instead of nothing happening.
	pmark = #PRINTED + 1
	ctrlRight("|cff0070dd|Hitem:abc|h[Odd Staff]|h|r")
	Advance(0.15)
	check(#sentTo(11, mark, "I2;") == 1 and printedSince(pmark):find("can't read this item's link", 1, true)
		and printedSince(pmark):find("||Hitem:abc", 1, true), "an unreadable link: a message with the link, nothing sent")
	-- A crafted item's link carries the crafter's GUID: shown anyway, without it (every build's
	-- message check only takes numbers).
	ctrlRight("|cnIQ3:|Hitem:1155::::::::25:1490:::::::::Player-1234-0ABCDEF0:|h[Rod of the Sleepwalker]|h|r")
	Advance(0.15)
	check(sentTo(11, mark, "I2;")[2] == "I2;1155::::::::25:1490::::::::::",
		"a crafted item: shown, the crafter's GUID left out, got " .. tostring(sentTo(11, mark, "I2;")[2]))
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "I2;1155::::::::25:1490::::::::::", "WHISPER", 12)
	Advance(0.15)
	local craftedShown
	for _, call in pairs(BB.calls) do if call.itemString == "1155::::::::25:1490::::::::::" then craftedShown = call end end
	check(craftedShown, "and a friend receives it")
	Advance(9)
	-- The same without a click: /lefthy beacon show | offer <item>.
	pmark = #PRINTED + 1
	lefthy("beacon show")
	check(printedSince(pmark):find("Shift-click the item into the chat box", 1, true), "/lefthy beacon show without an item: how to use it")
	lefthy("beacon offer " .. ItemLink(19019))
	check(printedSince(pmark):find(ItemLink(19019) .. " is soulbound or can't be traded: it can't be offered", 1, true),
		"/lefthy beacon offer a Bind on Pickup item: refused")
	lefthy("beacon show " .. ItemLink(19019))
	Advance(0.15)
	check(sentTo(11, mark, "I2;")[3] == "I2;19019::::::::20:::::", "/lefthy beacon show <item>: shown, soulbound or not")
	Advance(3)
	mark = #GAMEDATA + 1
	STATE.ctrl, MOCK_BUTTON = true, "LeftButton"
	HandleModifiedItemClick(ItemLink(1155)) -- Ctrl+left-click: the game's preview, nothing else
	STATE.ctrl, MOCK_BUTTON = false, "RightButton"
	HandleModifiedItemClick(ItemLink(1155)) -- no modifier
	Advance(0.15)
	check(#sentTo(11, mark, "I2;") == 0, "Ctrl+left-click and plain clicks don't share")

	-- Any item can be shown; only items that can change hands can be offered.
	Advance(3)
	mark, pmark = #GAMEDATA + 1, #PRINTED + 1
	local function offers() -- offers carry a call id at the end
		local n = 0
		for _, m in ipairs(sentTo(11, mark, "I2;")) do if m:find(";%d+$") then n = n + 1 end end
		return n
	end
	ctrlRight(ItemLink(19019), true) -- offering a chat link to a Bind on Pickup item
	Advance(0.15)
	check(offers() == 0 and printedSince(pmark):find(ItemLink(19019) .. " is soulbound or can't be traded: it can't be offered", 1, true),
		"a Bind on Pickup item (chat link, loot window): not offered, and I'm told why")
	ctrlRight(ItemLink(19019)) -- just showing it
	Advance(0.15)
	check(#sentTo(11, mark, "I2;") == 1 and offers() == 0, "showing it works: any item can be shown")
	Advance(3)
	BAGS[0] = { [2] = 1155 }
	MOCK_FOCUS = ContainerFrameCombinedBags.buttons[2]
	BOUND[2] = true -- worn once: bound now
	ctrlRight(ItemLink(1155), true)
	Advance(0.15)
	check(offers() == 0, "a soulbound item in the bags: not offered")
	BAG_TOOLTIP[2] = { "Rod of the Sleepwalker",
		"You may trade this item with players that were also eligible to loot this item for the next 1 hour 52 min." }
	ctrlRight(ItemLink(1155), true)
	Advance(0.15)
	check(offers() == 1, "soulbound, but its loot trade timer still runs: offered")
	BOUND[2], BAG_TOOLTIP[2] = nil, nil
	Advance(3)
	ctrlRight(ItemLink(1155), true)
	Advance(0.15)
	check(offers() == 2, "Bind on Equip, not bound yet: offered")
	MOCK_FOCUS = CreateFrame("Button")
	MOCK_FOCUS:SetID(16)
	EQUIPPED[16] = 1155
	Advance(3)
	ctrlRight(ItemLink(1155), true)
	Advance(0.15)
	check(offers() == 2, "a worn item: not offered")
	-- With the location Blizzard passes (bags, bank, character frame), the mouse doesn't matter.
	MOCK_FOCUS = nil
	BAGS[6] = { [1] = 1155 } -- a bank bag
	BOUND[1] = true
	ctrlRight(ItemLink(1155), true, ItemLocation:CreateFromBagAndSlot(6, 1))
	Advance(0.15)
	check(offers() == 2, "a soulbound item in the bank: not offered")
	BOUND[1] = nil
	ctrlRight(ItemLink(1155), true, ItemLocation:CreateFromBagAndSlot(6, 1))
	Advance(0.15)
	check(offers() == 3, "not bound yet, in the bank: offered")
	Advance(3)
	ctrlRight(ItemLink(1155), true, ItemLocation:CreateFromEquipmentSlot(16))
	Advance(0.15)
	check(offers() == 3, "worn, clicked on the character frame: not offered")
	MOCK_FOCUS, EQUIPPED, BAGS = nil, {}, { [0] = {} }
	Advance(30) -- nobody answers: the offers run out and fade
	anna("S2;;0;260.0;750.0;Goldshire;")
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;260.0;750.0;Goldshire;", "WHISPER", 12)
	Advance(3)

	pmark = #PRINTED + 1
	local sounds = #SOUNDS
	anna("I2;19019::::::::20:::::")
	check(#PRINTED < pmark, "receiving: nothing inside the event handler")
	Advance(0.15)
	check(printedSince(pmark):find("Anna|r shares " .. ItemLink(19019) .. ".", 1, true), "a chat line with the link")
	local shown
	for _, call in pairs(BB.calls) do if call.frame and call.frame:IsShown() then shown = call.frame end end
	check(shown and shown.Line:GetText():find("^|T%d+:0|t ") and shown.Line:GetText():find("Anna|r shares " .. ItemLink(19019), 1, true)
		and not shown.Need:IsShown() and SOUNDS[#SOUNDS] == 3081 and #SOUNDS == sounds + 1,
		"a notice with the icon and the item (no buttons when just shown) and the whisper sound")
	local boxes = 0
	for _, t in ipairs(shown._textures or {}) do if t.layer == "BACKGROUND" or t.layer == "BORDER" then boxes = boxes + 1 end end
	check(boxes == 0 and not shown.Line:GetText():find("\n", 1, true) and shown:GetHeight() <= 24
		and shown.Line.textScale <= 1.2, "one line of text, not too big, no box behind it")
	shown.Hover._scripts.OnEnter(shown.Hover)
	check(TOOLTIP.shown and TOOLTIP.owner == shown.Hover and TOOLTIP.link == "item:19019::::::::20:::::",
		"hovering the line shows the item's tooltip")
	shown.Hover._scripts.OnLeave(shown.Hover)
	check(not TOOLTIP.shown, "... and moving away hides it")
	local dressed = DRESSUPS
	shown.Hover._scripts.OnClick(shown.Hover)
	STATE.ctrl = true
	shown.Hover._scripts.OnClick(shown.Hover)
	STATE.ctrl = false
	check(DRESSUPS == dressed + 1, "a plain click does nothing, Ctrl-click previews it (the game's item click handling)")
	GAMEPAD_STATE.ui, STATE.ctrl = true, true
	shown.Hover._scripts.OnClick(shown.Hover)
	GAMEPAD_STATE.ui, STATE.ctrl = false, false
	check(DRESSUPS == dressed + 1, "in gamepad mode no dressing room from here (it would taint the gamepad's focus)")
	shown.Hover._scripts.OnEnter(shown.Hover)
	Advance(9)
	check(not shown:IsShown() and not TOOLTIP.shown, "it goes away by itself, its tooltip too if it was still up")
	pmark = #PRINTED + 1
	MOCK_ITEM_UNCACHED = 6948
	anna("I2;6948::::::::20:::::")
	Advance(0.15)
	check(not printedSince(pmark):find("shares", 1, true), "an item the client doesn't know yet: it waits for it")
	MOCK_ITEM_UNCACHED = nil
	for _, callback in ipairs(PENDING_ITEM_LOADS) do callback() end
	PENDING_ITEM_LOADS = {}
	check(printedSince(pmark):find("Anna|r shares " .. ItemLink(6948), 1, true), "... and shows it once it's loaded")
	pmark = #PRINTED + 1
	anna("I2;1179::::::::20:::::")
	anna("I2;abc")
	Advance(0.15)
	check(not printedSince(pmark):find("shares", 1, true), "another one within 3 s and malformed ones are ignored")
	Advance(9)

	-- Offering: Ctrl+Shift+right-click. Both friends need it: a roll.
	mark, pmark, sounds = #GAMEDATA + 1, #PRINTED + 1, #SOUNDS
	ctrlRight(ItemLink(1155), true)
	Advance(0.15)
	local offer = sentTo(11, mark, "I2;")[1]
	local callID = offer and tonumber(offer:match("^I2;1155::::::::20:::::;(%d+)$"))
	check(callID and sentTo(12, mark, "I2;")[1] == offer, "Ctrl+Shift+right-click offers it to everyone, with a call id, got " .. tostring(offer))
	local mine = callID and BB.calls["me:" .. callID]
	check(mine and mine.frame:IsShown() and mine.frame.Line:GetText():find("|t You offer " .. ItemLink(1155), 1, true)
		and mine.frame.Status:GetText():find("Waiting", 1, true),
		"my notice: waiting for their answers")
	anna("N2;" .. callID .. ";1")
	Advance(0.15)
	check(mine.frame.Status:GetText():find("Anna: |cff40ff40Need", 1, true), "answers show up live")
	anna("N2;" .. callID .. ";0") -- she can't change her mind
	local verdictMark = #GAMEDATA + 1
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "N2;" .. callID .. ";1", "WHISPER", 12) -- Bob needs it too
	Advance(0.3)
	local verdict = sentTo(11, verdictMark, "R2;")[1]
	check(verdict and verdict:find("^R2;" .. callID .. ";%a+:%d+,%a+:%d+$") and sentTo(12, verdictMark, "R2;")[1] == verdict,
		"everyone answered: rolled right away, the verdict goes to everyone, got " .. tostring(verdict))
	local winner, top, second = verdict:match("^R2;%d+;(%a+):(%d+),%a+:(%d+)$")
	check(winner == "Anna" or winner == "Bob", "the two who needed it")
	check(tonumber(top) > tonumber(second), "highest first, never a tie")
	check(mine.state == "rolling" and mine.frame.Winner:GetText():find("Rolling", 1, true)
		and soundsSince(sounds):find(",31579,31580,", 1, true), "a drumroll: the bonus roll spinner, numbers whirling")
	Advance(2.6)
	check(mine.state == "done" and #STOPPED_SOUNDS > 0 and soundsSince(sounds):find(",31581,31578,", 1, true),
		"then the spinner stops and a fanfare plays")
	check(mine.frame.Winner:GetText():find(winner .. " wins!", 1, true)
		and printedSince(pmark):find(winner .. " wins " .. ItemLink(1155) .. " with " .. top, 1, true),
		"the winner in big letters, and in chat")
	Advance(9)
	check(not mine.frame, "and after a while it's gone")

	-- A friend's offer: Need / Pass. I need it and win.
	mark = #GAMEDATA + 1
	anna("I2;1179::::::::20:::::;4242")
	Advance(0.15)
	local theirs = BB.calls["11:4242"]
	check(theirs and theirs.frame.Need:IsShown() and theirs.frame.Pass:IsShown() and theirs.frame.Timer:IsShown(),
		"a friend's offer: Need and Pass buttons and a timer")
	theirs.frame.Need:Click()
	Advance(0.15)
	check(sentTo(11, mark, "N2;")[1] == "N2;4242;1" and not theirs.frame.Need:IsShown()
		and theirs.frame.Status:GetText():find("Fingers crossed", 1, true), "Need: my answer goes to her")
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "R2;4242;Bob:99", "WHISPER", 12)
	Advance(0.15)
	check(theirs.state == "open", "a verdict from someone else than the sharer is ignored")
	anna("R2;4242;|cffff0000Lefthy|r:87,Bob:12")
	Advance(0.15)
	check(theirs.state == "rolling", "her verdict: the drumroll here too")
	Advance(2.6)
	check(theirs.frame.Winner:GetText():find("You win!", 1, true) and theirs.frame.Status:GetText():find("Lefthy  87", 1, true)
		and not theirs.frame.Status:GetText():find("ff0000", 1, true), "and I won (names in a verdict cleaned of escape codes)")
	Advance(9)

	-- Only one needs it: no roll. Nobody: nobody.
	anna("I2;6948::::::::20:::::;5151")
	Advance(0.15)
	BB.calls["11:5151"].frame.Pass:Click()
	anna("R2;5151;Bob:0")
	Advance(0.15)
	local single = BB.calls["11:5151"]
	check(single.state == "done" and single.frame.Winner:GetText():find("Bob wins!", 1, true), "a single Need: they get it, no roll")
	Advance(9)
	ctrlRight(ItemLink(1155), true)
	Advance(0.15)
	local open
	for _, call in pairs(BB.calls) do if call.mine and call.state == "open" then open = call end end
	Advance(21)
	check(open and open.state == "done" and open.frame.Status:GetText():find("Nobody needs it.", 1, true),
		"nobody answered within 20 s: nobody needs it")
	Advance(9)

	-- Many long names: the verdict is cut to what friends take (200 bytes), the winner first.
	ctrlRight(ItemLink(1155), true)
	Advance(0.15)
	local big
	for _, call in pairs(BB.calls) do if call.mine and call.state == "open" then big = call end end
	for i = 1, 4 do
		big.recipients[100 + i] = true
		big.answers[100 + i] = { name = ("x"):rep(47) .. i, need = true }
	end
	anna("N2;" .. big.id .. ";1")
	verdictMark = #GAMEDATA + 1
	Advance(21)
	local cut = (sentTo(11, verdictMark, "R2;")[1] or ""):match("^R2;%d+;(.*)$")
	check(cut and #cut <= 200 and #big.result == 5 and cut:find("^" .. big.result[1].name .. ":" .. big.result[1].roll .. ","),
		"too long for friends: cut, the winner first (I still see all five), got " .. tostring(cut and #cut))
	Advance(9)

	-- Four notices at once: three fit. A finished one makes room and lets go of its frame for good.
	anna("I2;1179::::::::20:::::;7001")
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "I2;6948::::::::20:::::", "WHISPER", 12) -- Bob just shows one
	Advance(2.1)
	anna("I2;19019::::::::20:::::;7003")
	Advance(0.15)
	local showOnly, showKey
	for key, call in pairs(BB.calls) do if call.from == 12 and not call.id then showOnly, showKey = call, key end end
	local spareFrame = showOnly and showOnly.frame
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "I2;1155::::::::20:::::;7004", "WHISPER", 12)
	Advance(0.15)
	local fourth, oldest = BB.calls["12:7004"], BB.calls["11:7001"]
	check(spareFrame and fourth and fourth.frame == spareFrame and not showOnly.frame and oldest.frame and oldest.frame:IsShown(),
		"a fourth notice takes the frame of one that's only shown, not of an open offer")
	check(fourth.frame.Line:GetText():find("Bob|r offers " .. ItemLink(1155), 1, true) and fourth.frame.Need:IsShown(),
		"... filled in for the new one (a friend's offer says so)")
	Advance(6.5)
	check(not BB.calls[showKey] and fourth.frame and fourth.frame:IsShown() and fourth.frame.Line:GetText():find(ItemLink(1155), 1, true),
		"the one that gave up its frame runs out without touching it")
	Advance(30)
	check(not next(BB.calls), "all of them run out")

	-- Four open offers: the oldest makes room, and comes back with its buttons once there's room.
	anna("I2;1179::::::::20:::::;8001")
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "I2;6948::::::::20:::::;8002", "WHISPER", 12)
	Advance(2.1)
	anna("I2;19019::::::::20:::::;8003")
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "I2;1155::::::::20:::::;8004", "WHISPER", 12)
	Advance(0.15)
	local pushedOut = BB.calls["11:8001"]
	check(pushedOut and not pushedOut.frame and BB.calls["12:8004"].frame, "the oldest open offer made room")
	anna("R2;8003;") -- nobody needed hers
	Advance(9)
	check(pushedOut.frame and pushedOut.frame:IsShown() and pushedOut.frame.Need:IsShown()
		and pushedOut.frame.Line:GetText():find(ItemLink(1179), 1, true), "once there's room it's back, with Need and Pass")
	Advance(14) -- no verdict from Anna: it runs out
	check(pushedOut.state == "done" and pushedOut.frame and not pushedOut.frame.Need:IsShown() and not pushedOut.frame.Timer:IsShown(),
		"an offer that runs out without a verdict loses its buttons right away")
	Advance(10)
	check(not next(BB.calls), "and all of them go")

	-- Answers to two of my offers in the same moment: both count.
	ctrlRight(ItemLink(1155), true)
	Advance(3.1)
	ctrlRight(ItemLink(6948), true)
	Advance(0.15)
	local myCalls = {}
	for _, call in pairs(BB.calls) do if call.mine then myCalls[#myCalls + 1] = call end end
	check(#myCalls == 2, "two offers of mine")
	anna("N2;" .. myCalls[1].id .. ";1")
	anna("N2;" .. myCalls[2].id .. ";0")
	Advance(0.15)
	check(myCalls[1].answers[11] and myCalls[1].answers[11].need and myCalls[2].answers[11] and not myCalls[2].answers[11].need,
		"Anna answers both at once: both count")
	Advance(30)

	-- A won item's tooltip reminds me until it's handed over: traded or mailed to the winner.
	local owed = LefthyToolsDB.handover
	check(type(owed) == "table", "the reminders are saved")
	wipe(owed)
	lefthy("beacon handover")
	check(PRINTED[#PRINTED]:find("nothing to hand over", 1, true), "/lefthy beacon handover: nothing yet")
	pmark = #PRINTED + 1
	BAGS[0] = { [3] = 6948 }
	ctrlRight(ItemLink(6948), true, ItemLocation:CreateFromBagAndSlot(0, 3)) -- from the bags
	Advance(0.15)
	local giveaway
	for _, call in pairs(BB.calls) do if call.mine and call.state == "open" then giveaway = call end end
	anna("N2;" .. giveaway.id .. ";1")
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "N2;" .. giveaway.id .. ";0", "WHISPER", 12)
	Advance(0.3)
	check(#owed == 1 and owed[1].itemID == 6948 and owed[1].winner == "Anna" and owed[1].guid == "Player-1-11"
		and owed[1].itemGUID == "Item-0-3"
		and printedSince(pmark):find("its tooltip reminds you until you trade or mail it to Anna.", 1, true),
		"Anna won my item: noted (this very copy), and I'm told")
	BAGS = { [0] = {} }
	GameTooltip:SetOwner(UIParent)
	GameTooltip:SetHyperlink("item:6948::::::::20:::::")
	check(tooltipHas("Won by Anna: still to hand over"), "its tooltip says so")
	GameTooltip:SetOwner(UIParent)
	GameTooltip:SetHyperlink("item:1155::::::::20:::::")
	check(not tooltipHas("Won by"), "other items' tooltips don't")
	GameTooltip:Hide()
	-- Traded to Bob: still owed, and no nudge.
	TRADE_PARTNER, PARTY.NPC = "Bob", { guid = "Player-1-12" }
	pmark = #PRINTED + 1
	Fire("TRADE_SHOW")
	TRADE_ITEMS = { ItemLink(6948) }
	Fire("TRADE_PLAYER_ITEM_CHANGED", 1)
	Fire("TRADE_ACCEPT_UPDATE", 1, 1)
	Fire("TRADE_CLOSED")
	Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
	Advance(0.1)
	check(#owed == 1 and not printedSince(pmark):find("put it in", 1, true), "traded to someone else: still owed, no nudge")
	-- Trading with Anna: a nudge; she gets it: gone.
	TRADE_PARTNER, PARTY.NPC, TRADE_ITEMS = "Anna", { guid = "Player-1-11" }, {}
	pmark = #PRINTED + 1
	Fire("TRADE_SHOW")
	check(not printedSince(pmark):find("put it in", 1, true), "nothing printed inside the event handler")
	Advance(0.1)
	check(printedSince(pmark):find("Anna won " .. ItemLink(6948) .. ": put it in the trade.", 1, true), "trading with the winner: a nudge in chat")
	Fire("TRADE_PLAYER_ITEM_CHANGED", 2)
	Fire("TRADE_CLOSED")
	Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
	check(#owed == 1, "a trade without the item: still owed")
	Fire("TRADE_SHOW")
	TRADE_ITEMS = { nil, ItemLink(6948) }
	Fire("TRADE_PLAYER_ITEM_CHANGED", 2)
	Fire("TRADE_ACCEPT_UPDATE", 1, 1)
	Fire("TRADE_CLOSED")
	Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
	Advance(0.1)
	check(#owed == 0 and printedSince(pmark):find(ItemLink(6948) .. " handed over to Anna.", 1, true), "traded to the winner: the reminder is gone")
	-- A partner with a surname and no GUID: still her.
	BB.AddHandover("6948::::::::20:::::", ItemLink(6948), "Anna", nil)
	TRADE_PARTNER, TRADE_SURNAME, PARTY.NPC, TRADE_ITEMS = "Anna", "Smith", nil, {}
	pmark = #PRINTED + 1
	Fire("TRADE_SHOW")
	Advance(0.1)
	check(printedSince(pmark):find("Anna won " .. ItemLink(6948), 1, true), "a trade partner with a surname (no GUID): still matched")
	TRADE_ITEMS = { ItemLink(6948) }
	Fire("TRADE_PLAYER_ITEM_CHANGED", 1)
	Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
	check(#owed == 0, "... and handed over")
	TRADE_SURNAME = nil
	TRADE_PARTNER, PARTY.NPC, TRADE_ITEMS = nil, nil, {}
	-- Mail.
	BB.AddHandover("1179::::::::20:::::", ItemLink(1179), "Bob", "Player-1-12")
	MAIL_ITEMS = { 1179 }
	SendMail("Anna", "hi", "")
	Fire("MAIL_SEND_SUCCESS")
	check(#owed == 1, "mailed to someone else: still owed")
	SendMail("Bob-Realmy", "yours", "")
	Fire("MAIL_FAILED")
	Fire("MAIL_SEND_SUCCESS") -- a later, unrelated mail
	check(#owed == 1, "a mail that failed: still owed")
	SendMail("Bob-Realmy", "yours", "")
	Fire("MAIL_SEND_SUCCESS")
	check(#owed == 0, "mailed to the winner (name with realm): gone")
	BB.AddHandover("1179::::::::20:::::", ItemLink(1179), "Bob", "Player-1-12")
	SendMail("bob", "yours", "")
	Fire("MAIL_SEND_SUCCESS")
	check(#owed == 0, "the name typed in lower case: still them")
	MAIL_ITEMS = {}

	-- Rolled again: only the newest winner keeps it reserved.
	wipe(owed)
	BB.AddHandover("1179::::::::20:::::", ItemLink(1179), "Bob", "Player-1-12", 12)
	pmark = #PRINTED + 1
	BB.AddHandover("1179::::::::20:::::", ItemLink(1179), "Anna", "Player-1-11", 11)
	check(#owed == 1 and owed[1].winner == "Anna" and printedSince(pmark):find(ItemLink(1179) .. " is no longer reserved for Bob.", 1, true),
		"rolled again: only the newest winner, and I'm told who no longer has it")
	GameTooltip:SetOwner(UIParent)
	GameTooltip:SetHyperlink("item:1179::::::::20:::::")
	check(tooltipHas("Won by Anna: still to hand over") and not tooltipHas("Won by Bob: still to hand over"), "its tooltip names only them")
	GameTooltip:Hide()
	-- Two copies of an item, offered from the bags and won by two people: two reservations.
	wipe(owed)
	BAGS[0] = { [3] = 1155, [4] = 1155 }
	pmark = #PRINTED + 1
	BB.AddHandover("1155::::::::20:::::", ItemLink(1155), "Anna", "Player-1-11", 11, "Item-0-3")
	BB.AddHandover("1155::::::::20:::::", ItemLink(1155), "Bob", "Player-1-12", 12, "Item-0-4")
	check(#owed == 2 and not printedSince(pmark):find("no longer reserved", 1, true), "two copies won by two people: both reserved")
	GameTooltip:SetOwner(UIParent)
	GameTooltip:SetBagItem(0, 3)
	check(tooltipHas("Won by Anna: still to hand over") and not tooltipHas("Won by Bob: still to hand over"), "each copy's tooltip names its winner")
	GameTooltip:SetOwner(UIParent)
	GameTooltip:SetHyperlink("item:1155::::::::20:::::")
	check(tooltipHas("Won by Anna: still to hand over") and tooltipHas("Won by Bob: still to hand over"), "a link (no copy known) names both")
	GameTooltip:Hide()
	BB.AddHandover("1155::::::::20:::::", ItemLink(1155), "Bob", "Player-1-12", 12, "Item-0-3")
	check(#owed == 2 and owed[1].winner == "Bob" and owed[2].winner == "Bob" and printedSince(pmark):find("no longer reserved for Anna", 1, true),
		"one copy rolled again: only that one changes hands")
	wipe(owed)
	BAGS = { [0] = {} }

	-- Reserved items: a border in the bags; at a vendor, right-click asks first.
	BB.AddHandover("1179::::::::20:::::", ItemLink(1179), "Bob", "Player-1-12", 12)
	BAGS[0] = { [3] = 1179, [5] = 6948 }
	OpenBags()
	Advance(0.1)
	local bagButtons = ContainerFrameCombinedBags.buttons
	check(bagButtons[3].LefthyToolsReserved and bagButtons[3].LefthyToolsReserved:IsShown() and not bagButtons[5].LefthyToolsReserved
		and not bagButtons[3].LefthyToolsSellGuard, "a reserved item's bag slot gets a border, other slots don't")
	Fire("MERCHANT_SHOW")
	Advance(0.1)
	local guard = bagButtons[3].LefthyToolsSellGuard
	check(guard and guard:IsShown() and guard._passThrough[1] == "LeftButton" and guard._propagateMotion == true
		and not bagButtons[5].LefthyToolsSellGuard, "at a vendor: a guard over the slot, left-clicks and hovering pass through")
	local soundsBefore = #SOUNDS
	guard:Click("RightButton")
	local dlg = LefthyToolsSellReservedDialog
	check(dlg and dlg:IsShown() and dlg.Text:GetText():find(ItemLink(1179) .. " is reserved for Bob: they won it. Sell it anyway?", 1, true)
		and #SOLD == 0 and #SOUNDS == soundsBefore + 1, "right-click: a question (with an alert sound) instead of selling")
	dlg.Keep:Click()
	check(not dlg:IsShown() and #SOLD == 0 and BAGS[0][3] == 1179, "Keep it: nothing sold")
	Advance(3) -- the last share was a moment ago
	STATE.ctrl = true
	MOCK_BUTTON = "RightButton"
	local shares = #sentTo(11, 1, "I2;")
	guard:Click("RightButton")
	STATE.ctrl = false
	Advance(0.15)
	check(not dlg:IsShown() and #sentTo(11, 1, "I2;") == shares + 1, "Ctrl+right-click still shows it to friends, no question")
	Advance(3)
	do
		local dressed = DRESSUPS
		GAMEPAD_STATE.ui, STATE.ctrl, MOCK_BUTTON = true, true, "RightButton"
		guard:Click("RightButton")
		GAMEPAD_STATE.ui, STATE.ctrl = false, false
		Advance(0.15)
		check(not dlg:IsShown() and #sentTo(11, 1, "I2;") == shares + 2 and DRESSUPS == dressed,
			"in gamepad mode too, without the dressing room (it would taint the gamepad's focus)")
	end
	guard:Click("RightButton")
	pmark = #PRINTED + 1
	dlg.Sell:Click()
	Advance(0.1)
	check(SOLD[#SOLD] == 1179 and #owed == 0 and not bagButtons[3].LefthyToolsReserved:IsShown() and not guard:IsShown()
		and printedSince(pmark):find("no longer reserved", 1, true), "Sell anyway: sold, no longer reserved, border and guard gone")
	-- Two copies, one of them reserved: only that one has a border and asks.
	BAGS[0][8], BAGS[0][9] = 1155, 1155
	BB.AddHandover("1155::::::::20:::::", ItemLink(1155), "Anna", "Player-1-11", 11, "Item-0-8")
	Advance(0.1)
	check(bagButtons[8].LefthyToolsReserved:IsShown() and bagButtons[8].LefthyToolsSellGuard:IsShown()
		and not (bagButtons[9].LefthyToolsReserved and bagButtons[9].LefthyToolsReserved:IsShown())
		and not (bagButtons[9].LefthyToolsSellGuard and bagButtons[9].LefthyToolsSellGuard:IsShown()),
		"two copies, one reserved: only that one has a border and asks")
	bagButtons[8].LefthyToolsSellGuard:Click("RightButton")
	dlg.Sell:Click()
	Advance(0.1)
	check(SOLD[#SOLD] == 1155 and BAGS[0][8] == nil and #owed == 0, "Sell anyway on it: sold, reservation over")
	-- Reserved without a known copy (offered from a link), two copies: selling one keeps it.
	BAGS[0][8] = 1155
	BB.AddHandover("1155::::::::20:::::", ItemLink(1155), "Bob", "Player-1-12", 12)
	Advance(0.1)
	check(bagButtons[8].LefthyToolsReserved:IsShown() and bagButtons[9].LefthyToolsReserved:IsShown(), "any copy reserved: both have a border")
	pmark = #PRINTED + 1
	bagButtons[8].LefthyToolsSellGuard:Click("RightButton")
	dlg.Sell:Click()
	Advance(0.1)
	check(BAGS[0][8] == nil and #owed == 1 and printedSince(pmark):find("another one is still reserved for Bob", 1, true),
		"selling one of two: the other is still reserved")
	bagButtons[9].LefthyToolsSellGuard:Click("RightButton")
	dlg.Sell:Click()
	Advance(0.1)
	check(BAGS[0][9] == nil and #owed == 0, "selling the last one: reservation over")
	Fire("MERCHANT_CLOSED")
	-- Gone another way (dragged onto the vendor, a bag addon): how to buy it back.
	BB.AddHandover("6948::::::::20:::::", ItemLink(6948), "Anna", "Player-1-11", 11)
	Fire("MERCHANT_SHOW")
	Advance(0.1)
	pmark = #PRINTED + 1
	BAGS[0][5] = nil
	Fire("BAG_UPDATE_DELAYED")
	Advance(0.1)
	check(printedSince(pmark):find(ItemLink(6948) .. ", which Anna won, is gone: if you sold it, buy it back", 1, true),
		"a reserved item gone at a vendor: a warning while it can be bought back")
	Fire("MERCHANT_CLOSED")
	Advance(0.1)
	-- Won while already at a vendor (nothing reserved when it opened): watched too.
	wipe(owed)
	BAGS[0][5] = 6948
	Fire("MERCHANT_SHOW")
	Advance(0.1)
	BB.AddHandover("6948::::::::20:::::", ItemLink(6948), "Anna", "Player-1-11", 11)
	pmark = #PRINTED + 1
	BAGS[0][5] = nil
	Fire("BAG_UPDATE_DELAYED")
	Advance(0.1)
	check(printedSince(pmark):find("which Anna won, is gone", 1, true), "reserved while at the vendor, then gone: the warning too")
	Fire("MERCHANT_CLOSED")
	Advance(0.1)
	-- In combat no guard is made (pass-through can't be set then).
	wipe(owed)
	BB.AddHandover("1155::::::::20:::::", ItemLink(1155), "Bob", "Player-1-12", 12)
	BAGS[0][7] = 1155
	local blocked = #BLOCKED
	STATE.combat = true
	Fire("MERCHANT_SHOW")
	Advance(0.1)
	check(not bagButtons[7].LefthyToolsSellGuard and #BLOCKED == blocked and bagButtons[7].LefthyToolsReserved:IsShown(),
		"in combat: the border, but no guard (nothing blocked)")
	STATE.combat = false
	Fire("MERCHANT_CLOSED")
	Advance(0.1)
	-- Mail: attaching it fills in the winner.
	wipe(owed)
	BN_FRIENDS[1][1].realmName = "Argent Dawn"
	BB.AddHandover("6948::::::::20:::::", ItemLink(6948), "Anna", "Player-1-11", 11)
	BN_FRIENDS[1][1].realmName = "Realmy"
	check(owed[1].mailName == "Anna-ArgentDawn", "a winner on another realm: mailed as Name-Realm")
	owed[1].mailName = "Anna"
	SendMailFrame:Show()
	SendMailNameEditBox:SetText("")
	MAIL_ITEMS = { 6948 }
	pmark = #PRINTED + 1
	Fire("MAIL_SEND_INFO_UPDATE")
	check(SendMailNameEditBox:GetText() == "", "nothing done inside the event handler")
	Advance(0.1)
	check(SendMailNameEditBox:GetText() == "Anna" and printedSince(pmark):find("mail to Anna: they won " .. ItemLink(6948), 1, true),
		"attaching a reserved item fills in its winner")
	SendMailNameEditBox:SetText("anna")
	Fire("MAIL_SEND_INFO_UPDATE")
	Advance(0.1)
	check(not printedSince(pmark):find("heads up", 1, true), "her name in lower case: no warning")
	SendMailNameEditBox:SetText("Bob")
	Fire("MAIL_SEND_INFO_UPDATE")
	Advance(0.1)
	Fire("MAIL_SEND_INFO_UPDATE")
	Advance(0.1)
	local _, warnings = printedSince(pmark):gsub("is reserved for Anna, not Bob", "")
	check(SendMailNameEditBox:GetText() == "Bob" and warnings == 1, "another name typed: kept, with one warning")
	SendMailFrame:Hide()
	MAIL_ITEMS = {}
	wipe(owed)
	BAGS = { [0] = {} }
	ContainerFrameCombinedBags:Hide()
	Advance(0.1)

	BB.AddHandover("1179::::::::20:::::", ItemLink(1179), "Bob", "Player-1-12")
	lefthy("beacon handover")
	check(printedSince(#PRINTED - 1):find(ItemLink(1179) .. " to Bob", 1, true), "/lefthy beacon handover lists what's owed")
	lefthy("beacon handover clear")
	check(#owed == 0, "/lefthy beacon handover clear")
	BB.AddHandover("1179::::::::20:::::", ItemLink(1179), "Bob", "Player-1-12")
	local clearButton = SETTINGS_BUTTONS["Hand-over reminders"]
	check(clearButton and clearButton.text == "Clear", "a Clear button on Beacon's settings page")
	clearButton.onClick()
	check(#owed == 0, "... that forgets them too")
	Advance(10)

	-- An item that only loads after sharing was switched off: no notice.
	pmark = #PRINTED + 1
	MOCK_ITEM_UNCACHED = 6948
	anna("I2;6948::::::::20:::::")
	Advance(0.15)
	B("shareItems"):SetValue(false)
	MOCK_ITEM_UNCACHED = nil
	for _, callback in ipairs(PENDING_ITEM_LOADS) do callback() end
	PENDING_ITEM_LOADS = {}
	check(not printedSince(pmark):find("shares", 1, true) and not next(BB.calls), "an item that loads after sharing was switched off: no notice")
	B("shareItems"):SetValue(true)

	B("shareItems"):SetValue(false)
	pmark = #PRINTED + 1
	anna("I2;1179::::::::20:::::")
	mark = #GAMEDATA + 1
	ctrlRight(ItemLink(1155))
	Advance(0.15)
	check(not printedSince(pmark):find("shares", 1, true) and #sentTo(11, mark, "I2;") == 0
		and printedSince(pmark):find("showing items is off in Beacon's settings", 1, true), "switched off: nothing shown, nothing sent, and I'm told why")
	B("shareItems"):SetValue(true)
end

section("Beacon: Lefthy chat and announcements")
do
	check(BDB.lefthyChat == true and BDB.announcements == true and B("lefthyChat") and B("announcements"),
		"both on by default, each with a checkbox")
	anna("H2")
	Advance(0.2)
	local mark, pmark = #GAMEDATA + 1, #PRINTED + 1
	SlashCmdList.LEFTHYTOOLS_CHAT("anyone up for Deadmines?")
	Advance(0.15)
	check(sentTo(11, mark, "M2;")[1] == "M2;anyone up for Deadmines?", "/l sends the line to my friends")
	check(printedSince(pmark):find("[Lefthy] [|r", 1, true) and printedSince(pmark):find("Lefthy|r|cffffb84d]: anyone up for Deadmines?", 1, true),
		"... and shows it in my chat window, like guild chat, got " .. printedSince(pmark))
	pmark = #PRINTED + 1
	anna("M2;sure, 5 min")
	Advance(0.15)
	check(printedSince(pmark):find("Anna|r|cffffb84d]: sure, 5 min", 1, true), "a friend's line in my chat window")
	pmark = #PRINTED + 1
	for i = 1, 8 do anna("M2;spam " .. i) end
	Advance(0.15)
	local spam = 0
	for i = pmark, #PRINTED do if PRINTED[i]:find("spam", 1, true) then spam = spam + 1 end end
	check(spam == 4, "a flood: at most 5 lines per 5 seconds from one friend, got " .. spam)
	mark = #GAMEDATA + 1
	Advance(1)
	SlashCmdList.LEFTHYTOOLS_CHAT("|cffff0000red|r; sneaky")
	Advance(0.15)
	check(sentTo(11, mark, "M2;")[1] == "M2;red sneaky", "colour codes and separators are taken out")
	-- Mine stay within what friends take (5 lines per 5 s, an announcement per 3 s), with room to spare.
	Advance(6)
	mark, pmark = #GAMEDATA + 1, #PRINTED + 1
	for i = 1, 6 do SlashCmdList.LEFTHYTOOLS_CHAT("quick " .. i) end
	Advance(0.15)
	check(#sentTo(11, mark, "M2;") == 5 and printedSince(pmark):find("not so fast", 1, true), "at most 5 lines in 6 s, and I'm told")
	Advance(6)
	SlashCmdList.LEFTHYTOOLS_CHAT("quick 7")
	Advance(0.15)
	check(#sentTo(11, mark, "M2;") == 6, "a moment later: on again")
	lefthy("announce one")
	Advance(3.5)
	lefthy("announce two")
	Advance(0.15)
	check(#sentTo(11, mark, "A2;") == 1, "one announcement in 4 s")
	-- Announcements: the middle of the screen.
	Advance(5)
	mark, pmark = #GAMEDATA + 1, #PRINTED + 1
	lefthy('announce "Ony in 10 minutes, meet at the flight master"')
	Advance(0.15)
	check(sentTo(11, mark, "A2;")[1] == "A2;Ony in 10 minutes, meet at the flight master",
		"/lefthy announce: the line goes to my friends (quotes optional), got " .. tostring(sentTo(11, mark, "A2;")[1]))
	local mine, theirs
	for _, call in pairs(BB.calls) do if call.message and call.mine then mine = call end end
	check(mine and mine.frame and mine.frame.Line:GetText():find("|r: Ony in 10 minutes", 1, true), "... and shows in my notices too")
	local soundMark = #SOUNDS
	anna("A2;Boss down, loot time!")
	Advance(0.15)
	for _, call in pairs(BB.calls) do if call.message and not call.mine then theirs = call end end
	check(theirs and theirs.frame:IsShown() and theirs.frame.Line:GetText():find("Anna|r: Boss down, loot time!", 1, true)
		and #SOUNDS > soundMark and not theirs.frame.Need:IsShown() and printedSince(pmark):find("]: Boss down, loot time!", 1, true),
		"a friend's announcement: in the middle of my screen with the whisper sound (and in chat), no buttons")
	Advance(9)
	check(theirs.frame and theirs.frame:IsShown(), "it stays for 10 seconds ...")
	Advance(2.5)
	check(not theirs.frame and not next(BB.calls), "... then fades away")
	B("announcements"):SetValue(false)
	B("lefthyChat"):SetValue(false)
	mark, pmark = #GAMEDATA + 1, #PRINTED + 1
	anna("A2;hello?")
	anna("M2;hello??")
	lefthy("announce hi")
	SlashCmdList.LEFTHYTOOLS_CHAT("hi")
	Advance(0.15)
	check(not printedSince(pmark):find("hello?", 1, true) and not next(BB.calls) and #sentTo(11, mark, "A2;") == 0
		and #sentTo(11, mark, "M2;") == 0 and printedSince(pmark):find("announcements are off", 1, true)
		and printedSince(pmark):find("Lefthy chat is off", 1, true), "switched off: nothing shown or sent, and I'm told why")
	B("announcements"):SetValue(true)
	B("lefthyChat"):SetValue(true)
	mark = #GAMEDATA + 1
	SlashCmdList.LEFTHYTOOLS_ANNOUNCE("pull in 5")
	Advance(0.15)
	check(sentTo(11, mark, "A2;")[1] == "A2;pull in 5", "/la: announcing the short way")
	-- Item links: they travel as their numbers and each client builds the link again.
	local chatPeers = BB.module:GetPeers()
	local annaWas = chatPeers[11].version
	chatPeers[11].version = "0.5.0-21-g51edb8a" -- (a build that knows every link token)
	mark, pmark = #GAMEDATA + 1, #PRINTED + 1
	SlashCmdList.LEFTHYTOOLS_CHAT("look: " .. ItemLink(1155) .. " and |cffffff00|Hquest:176:10|h[Wanted: Hogger]|h|r")
	Advance(0.15)
	check(sentTo(11, mark, "M2;")[1] == "M2;look: {item:1155::::::::20} and {quest:176:10[Wanted: Hogger]ffff00}",
		"an item link goes as its numbers, a quest link as its data, text and colour, got " .. tostring(sentTo(11, mark, "M2;")[1]))
	check(printedSince(pmark):find("]: look: " .. ItemLink(1155) .. " and |cffffff00|Hquest:176:10|h[Wanted: Hogger]|h|r", 1, true),
		"my own line shows both links, got " .. printedSince(pmark))
	-- Professions (and spells, achievements, ...): clickable on the other side too.
	Advance(1.1)
	mark, pmark = #GAMEDATA + 1, #PRINTED + 1
	SlashCmdList.LEFTHYTOOLS_CHAT("my |cffffd000|Htrade:Player-1-0000ABCD:3908:197|h[Tailoring]|h|r, not |cff00ff00|Hgarrmission:12|h[Mission]|h|r")
	Advance(0.15)
	check(sentTo(11, mark, "M2;")[1] == "M2;my {trade:Player-1-0000ABCD:3908:197[Tailoring]ffd000}, not [Mission]",
		"a profession link goes as its data, text and colour; a kind not on the list as its text, got " .. tostring(sentTo(11, mark, "M2;")[1]))
	check(printedSince(pmark):find("my |cffffd000|Htrade:Player-1-0000ABCD:3908:197|h[Tailoring]|h|r, not [Mission]", 1, true),
		"my own line: the profession as a link, got " .. printedSince(pmark))
	-- A map pin (Shift-click on the pin): its icon goes, each client puts its own back.
	Advance(1.1)
	mark, pmark = #GAMEDATA + 1, #PRINTED + 1
	SlashCmdList.LEFTHYTOOLS_CHAT("here |cffffff00|Hworldmap:1429:4924:5568|h[|A:Waypoint-MapPin-ChatIcon:13:13:0:0|a Map Pin Location]|h|r")
	Advance(0.15)
	check(sentTo(11, mark, "M2;")[1] == "M2;here {worldmap:1429:4924:5568[Map Pin Location]ffff00}",
		"a map pin goes as its map, spot and text, got " .. tostring(sentTo(11, mark, "M2;")[1]))
	check(printedSince(pmark):find("here |cffffff00|Hworldmap:1429:4924:5568|h[|A:Waypoint-MapPin-ChatIcon:13:13:0:0|a Map Pin Location]|h|r", 1, true),
		"and comes back as a clickable map pin with its icon, got " .. printedSince(pmark))
	-- Friends on older builds get what theirs understands: never a token it would show as text.
	if chatPeers[12] then
		local line = "|cffffd000|Htrade:Player-1-0000ABCD:3908:197|h[Tailoring]|h|r " .. ItemLink(1155)
			.. " |cffffff00|Hworldmap:1429:4924:5568|h[|A:Waypoint-MapPin-ChatIcon:13:13:0:0|a Map Pin Location]|h|r"
		local bobWas = chatPeers[12].version
		for _, case in ipairs({
			{ "0.5.0-15-g4322f60", "M2;{trade:Player-1-0000ABCD:3908:197[Tailoring]} {item:1155::::::::20} [Map Pin Location]",
				"0.5.0-15: its kinds as tokens without colour, a map pin as text" },
			{ "0.5.0-12-gbb4062c", "M2;[Tailoring] {item:1155::::::::20} [Map Pin Location]", "0.5.0-10 to -14: items only" },
			{ "0.5.0-9-gda764bc", "M2;[Tailoring] [Rod of the Sleepwalker] [Map Pin Location]", "older: every link as its text" },
			{ nil, "M2;[Tailoring] [Rod of the Sleepwalker] [Map Pin Location]", "version not known yet: text too" },
			{ "0.5.0-g1a2b3c4", "M2;{trade:Player-1-0000ABCD:3908:197[Tailoring]ffd000} {item:1155::::::::20} {worldmap:1429:4924:5568[Map Pin Location]ffff00}",
				"commit count unknown (the updater couldn't ask GitHub): a download of the latest, the full line" },
			{ "0.4.2-g1a2b3c4", "M2;[Tailoring] [Rod of the Sleepwalker] [Map Pin Location]", "... but not on an older base" },
		}) do
			chatPeers[12].version = case[1]
			Advance(1.1)
			mark = #GAMEDATA + 1
			SlashCmdList.LEFTHYTOOLS_CHAT(line)
			Advance(0.15)
			check(sentTo(12, mark, "M2;")[1] == case[2], "Bob on " .. tostring(case[1]) .. ": " .. case[3] .. ", got " .. tostring(sentTo(12, mark, "M2;")[1]))
			check(sentTo(11, mark, "M2;")[1]:find("{trade:Player-1-0000ABCD:3908:197[Tailoring]ffd000}", 1, true), "... Anna, on a new build, gets the full line")
		end
		chatPeers[12].version = bobWas
	end
	chatPeers[11].version = annaWas
	pmark = #PRINTED + 1
	anna("M2;{trade:Player-1-0000EEEE:2259:171[Alchemy]} and {spell:133:0[Fireball]} {garrmission:12[x]} {spell:133 0[y]}")
	Advance(0.15)
	local got = printedSince(pmark)
	check(got:find("|cffffd000|Htrade:Player-1-0000EEEE:2259:171|h[Alchemy]|h|r and |cff71d5ff|Hspell:133:0|h[Fireball]|h|r", 1, true)
		and got:find("{garrmission:12[x]} {spell:133 0[y]}", 1, true),
		"a friend's profession and spell links are clickable; other kinds and broken data stay plain text, got " .. got)
	Advance(0.6)
	pmark = #PRINTED + 1
	MOCK_ITEM_UNCACHED = 19019 -- not in my item cache yet
	anna("M2;need {item:19019::::::::20}?")
	Advance(0.15)
	anna("M2;anyone?")
	Advance(0.15)
	check(not printedSince(pmark):find("need", 1, true) and not printedSince(pmark):find("anyone", 1, true),
		"an item I don't have cached: the line waits for it, and her next line behind it")
	MOCK_ITEM_UNCACHED = nil
	for _, callback in ipairs(PENDING_ITEM_LOADS) do callback() end
	PENDING_ITEM_LOADS = {}
	local shownAll = printedSince(pmark)
	local needAt, anyoneAt = shownAll:find("Anna|r|cffffb84d]: need " .. ItemLink(19019) .. "?", 1, true), shownAll:find("anyone?", 1, true)
	check(needAt and anyoneAt and needAt < anyoneAt,
		"... and comes with a real link once it's loaded, then the next one: in the order she wrote them, got " .. shownAll)
	pmark = #PRINTED + 1
	MOCK_ITEM_UNCACHED = 19019
	anna("M2;{item:19019::::::::20} never loads")
	Advance(2.5)
	check(not printedSince(pmark):find("never loads", 1, true), "an item that takes long: waited for ...")
	Advance(0.7)
	check(printedSince(pmark):find("]: [?] never loads", 1, true), "... 3 seconds at most, then the line comes without it")
	MOCK_ITEM_UNCACHED, PENDING_ITEM_LOADS = nil, {}
	-- Sticky /l: the chat box stays on Lefthy chat, like /g, until another chat type.
	local box, header = ChatFrame1EditBox, ChatFrame1EditBoxHeader
	Advance(6) -- (my last chat lines out of the way: 5 per 6 s)
	mark = #GAMEDATA + 1
	TypeChat("/l first line")
	Advance(0.6)
	check(sentTo(11, mark, "M2;")[1] == "M2;first line", "/l in the chat box: sent")
	box:UpdateHeader() -- the box opens again
	check(header:GetText() == "Lefthy: " and header.color[2] == 0.72 and box._inset > 15,
		"the box stays on Lefthy chat, and its header says so, got " .. tostring(header:GetText()))
	local said = #SENT_CHAT
	TypeChat("second line, no /l")
	Advance(0.6)
	check(sentTo(11, mark, "M2;")[2] == "M2;second line, no /l" and #SENT_CHAT == said and box._history == "second line, no /l",
		"a plain line goes to Lefthy chat, not to /say (and into the box's history)")
	TypeChat("/w Bob psst")
	check(SENT_CHAT[#SENT_CHAT].type == "WHISPER", "a whisper goes out as a whisper")
	TypeChat("third")
	Advance(0.6)
	check(sentTo(11, mark, "M2;")[3] == "M2;third", "... and Lefthy chat stays (whispers aren't sticky)")
	TypeChat("/g hi guild")
	check(SENT_CHAT[#SENT_CHAT].type == "GUILD" and SENT_CHAT[#SENT_CHAT].text == "hi guild", "/g: to the guild")
	box:UpdateHeader()
	TypeChat("guild again")
	check(header:GetText() == "GUILD: " and SENT_CHAT[#SENT_CHAT].type == "GUILD" and #sentTo(11, mark, "M2;") == 3,
		"another sticky chat type ends Lefthy mode, as /p after /g does")
	TypeChatSpace("/l ")
	check(box:GetText() == "" and header:GetText() == "Lefthy: ", "typing /l and a space switches the box at once, like /g")
	TypeChat("from guild mode")
	Advance(0.6)
	check(sentTo(11, mark, "M2;")[4] == "M2;from guild mode", "... and the line goes to Lefthy chat")
	TypeChat("/s back to say")
	check(SENT_CHAT[#SENT_CHAT].type == "SAY" and SENT_CHAT[#SENT_CHAT].text == "back to say", "/s: back to say")
	-- A soft tick when a friend writes: once for a burst, not for my own lines, a setting.
	local ticks = #SOUNDS
	anna("M2;one")
	anna("M2;two")
	Advance(0.15)
	SlashCmdList.LEFTHYTOOLS_CHAT("mine")
	Advance(0.15)
	local soft = 0
	for i = ticks + 1, #SOUNDS do if SOUNDS[i] == 826 then soft = soft + 1 end end
	check(BDB.lefthyChatSound == true and B("lefthyChatSound") and soft == 1,
		"a friend's lines: one soft tick for the burst, none for mine (a setting, on), got " .. soft)
	B("lefthyChatSound"):SetValue(false)
	Advance(2)
	ticks = #SOUNDS
	anna("M2;three")
	Advance(0.15)
	check(#SOUNDS == ticks, "switched off: silent")
	B("lefthyChatSound"):SetValue(true)
	-- While I'm AFK the notices are hidden with the interface: the AFK screen lists them.
	Advance(3.5)
	afk(true)
	Advance(1.1)
	anna("I2;1179::::::::20:::::")
	Advance(2.1)
	anna("I2;6948::::::::20:::::;7171")
	anna("M2;brb, getting coffee")
	anna("A2;Raid in 10!")
	Advance(1.1)
	local info = LefthyToolsAFKFrame.Info:GetText()
	check(LefthyToolsAFKFrame:IsShown() and info:find("While you were away", 1, true) and info:find("Anna|r shares", 1, true)
		and info:find("Anna|r offers", 1, true) and info:find("[Lefthy]|r ", 1, true) and info:find("|r: brb, getting coffee", 1, true)
		and info:find("|r: |cffffd200Raid in 10!", 1, true),
		"AFK: items shown and offered, Lefthy chat and announcements are listed, got\n" .. info)
	afk(false)
	Advance(0.3)
	BB.calls["11:7171"].frame.Pass:Click() -- back: the offer's buttons are there
	Advance(0.2)
end

section("Beacon: error reports")
do
	check(BDB.sendReports == true and BDB.collectReports == false and B("sendReports") and B("collectReports")
		and SETTINGS_BUTTONS["Friends' error reports"], "sending on, collecting off, by default; a button for the collected ones")
	wipe(LefthyToolsDB.reportsOut or {})
	local function bobAlive() -- (friends silent for over a minute are forgotten)
		Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;260.0;750.0;Goldshire;", "WHISPER", 12)
		anna("S2;;0;260.0;750.0;Goldshire;")
	end
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "H2", "WHISPER", 12)
	Advance(1.2)
	-- Anna's profession link, clicked: nothing opens, the game says why; that's a report by itself.
	SetItemRef("trade:Player-1-11:2259:171", "[Alchemy]", "LeftButton")
	Fire("UI_ERROR_MESSAGE", 51, "That player is on another realm.")
	Advance(3.1)
	check(#LefthyToolsDB.reportsOut == 1, "a profession link that opened nothing: kept as a report")
	-- Nobody collects: a hand-written report waits too.
	pmark = #PRINTED + 1
	lefthy("report the profession link does nothing")
	check(printedSince(pmark):find("report kept", 1, true) and #LefthyToolsDB.reportsOut == 2, "nobody collects: the reports wait")
	mark, pmark = #GAMEDATA + 1, #PRINTED + 1
	anna("Y2;1")
	Advance(3)
	local byID = {}
	for _, p in ipairs(sentTo(11, mark, "Z2;")) do
		local id, n, text = p:match("^Z2;(%d+);(%d+);%d+;(.*)$")
		byID[id] = byID[id] or {}
		byID[id][tonumber(n)] = text
	end
	local texts = {}
	for _, list in pairs(byID) do texts[#texts + 1] = table.concat(list) end
	table.sort(texts)
	check(#texts == 2 and #LefthyToolsDB.reportsOut == 0 and printedSince(pmark):find("2 report(s) sent to Anna", 1, true),
		"Anna collects: both go to her, in parts, and I'm told")
	check(#sentTo(12, mark, "Z2;") == 0, "only to friends who collect")
	local linkReport, handReport = texts[1], texts[2] -- ("Profession link: ..." sorts before "Report: ...")
	check(linkReport:find("^Profession link: LefthyTools ") and linkReport:find("Clicked trade:Player-1-11:2259:171 at ", 1, true)
		and linkReport:find(" -> nothing opened^", 1, true)
		and linkReport:find("their server id 1, mine 1 - this client doesn't know them - Beacon friend Anna on Realmy, Alliance", 1, true)
		and linkReport:find("Me: Realmy, Alliance", 1, true)
		and linkReport:find("UI_ERROR_MESSAGE: That player is on another realm.", 1, true),
		"the profession link report: the linker's server, whether I know them, their realm and faction, mine, what the game said, got " .. linkReport)
	check(handReport:find("What happened: the profession link does nothing", 1, true) and handReport:find(", Realmy, Alliance, ", 1, true)
		and handReport:find("trade:Player-1-11:2259:171 -> nothing opened", 1, true) and handReport:find("linker: their server id 1", 1, true)
		and handReport:find("^", 1, true) and not handReport:find("\n", 1, true),
		"the hand-written one: my words, build, realm, faction and the link I clicked; lines as ^")
	mark = #GAMEDATA + 1
	KNOWN_PLAYERS["Player-1-11"] = { "Anna", "" }
	SetItemRef("trade:Player-1-11:2259:171", "[Alchemy]", "LeftButton")
	Advance(5.5)
	check(#sentTo(11, mark, "Z2;") == 0 and #LefthyToolsDB.reportsOut == 0, "a second one this session: no second report")
	KNOWN_PLAYERS = {}
	bobAlive()
	Advance(0.3)
	-- /lefthy beacon status: realm and faction of every friend and mine, to compare.
	pmark = #PRINTED + 1
	lefthy("beacon status")
	check(printedSince(pmark):find("Anna (Realmy, Alliance) - ", 1, true) and printedSince(pmark):find("you (Realmy, Alliance), LefthyTools ", 1, true),
		"status: each friend's realm and faction, and mine")
	-- A link other than an item, to a friend on a build from before link tokens: I'm told, once.
	local peerList = BB.module:GetPeers()
	local annaVersion, bobVersion = peerList[11].version, peerList[12] and peerList[12].version
	peerList[11].version = "0.5.0-20-g99df530"
	if peerList[12] then peerList[12].version = "0.5.0-14-g5ae6ba6" end
	Advance(1)
	pmark = #PRINTED + 1
	SlashCmdList.LEFTHYTOOLS_CHAT("my |cffffd000|Htrade:Player-1-0:2259:171|h[Alchemy]|h|r")
	Advance(0.6)
	check(peerList[12] and printedSince(pmark):find("Bob has an older LefthyTools", 1, true) and not printedSince(pmark):find("Anna has", 1, true),
		"a friend on an older build: named (links reach them as text), got " .. printedSince(pmark))
	pmark = #PRINTED + 1
	SlashCmdList.LEFTHYTOOLS_CHAT("again |cffffd000|Htrade:Player-1-0:2259:171|h[Alchemy]|h|r")
	Advance(0.6)
	check(not printedSince(pmark):find("older LefthyTools", 1, true), "only once")
	if peerList[12] then
		for _, case in ipairs({ { nil, "a friend whose version hasn't come yet: not called old" },
			{ "0.5.0-g5ae6ba6", "nor one whose commit count is unknown" } }) do
			peerList[12].version = case[1]
			pmark = #PRINTED + 1
			SlashCmdList.LEFTHYTOOLS_CHAT("and |cffffd000|Htrade:Player-1-0:2259:171|h[Alchemy]|h|r")
			Advance(0.6)
			check(not printedSince(pmark):find("older LefthyTools", 1, true), case[2])
		end
	end
	peerList[11].version = annaVersion
	if peerList[12] then peerList[12].version = bobVersion end
	-- An error goes by itself, once per session.
	mark = #GAMEDATA + 1
	LT.Errors.Add("error", "Interface/AddOns/LefthyTools/Core/Core.lua:9: something broke", "the stack")
	LT.Errors.Add("error", "Interface/AddOns/LefthyTools/Core/Core.lua:9: something broke", "the stack")
	Advance(3)
	local first = sentTo(11, mark, "Z2;")[1] or ""
	check(first:find(";1;%d+;Error: LefthyTools ") and #sentTo(11, mark, "Z2;") <= 3,
		"a LefthyTools error goes to her by itself, once, got " .. first)
	B("sendReports"):SetValue(false)
	mark = #GAMEDATA + 1
	LT.Errors.Add("error", "Interface/AddOns/LefthyTools/Core/Core.lua:10: another one", "")
	Advance(3)
	check(#sentTo(11, mark, "Z2;") == 0, "sending off: errors stay here")
	B("sendReports"):SetValue(true)
	LT.Errors.Clear()
	-- A backlog goes over a few minutes, each report whole: friends take 60 parts a minute.
	local function minute()
		for _ = 1, 3 do
			Advance(22)
			bobAlive()
		end
	end
	minute()
	mark, pmark = #GAMEDATA + 1, #PRINTED + 1
	for i = 1, 6 do lefthy("report " .. ("a long story, number " .. i .. ". "):rep(150)) end
	Advance(5) -- (the queue lets 10 a second go)
	check(#sentTo(11, mark, "Z2;") == 32 and #LefthyToolsDB.reportsOut == 4, "six long reports (16 parts each): two go now, got "
		.. #sentTo(11, mark, "Z2;") .. " parts")
	pmark = #PRINTED + 1
	minute()
	check(#sentTo(11, mark, "Z2;") == 64 and #LefthyToolsDB.reportsOut == 2
		and printedSince(pmark):find("2 report(s) sent to Anna (they collect LefthyTools error reports), 2 more in a moment.", 1, true),
		"two more a minute later, and I'm told more are coming")
	minute()
	local parts = sentTo(11, mark, "Z2;")
	check(#parts == 96 and #LefthyToolsDB.reportsOut == 0 and parts[96]:find("^Z2;%d+;16;16;"), "and the last two: each one whole")
	anna("Y2;0")

	-- Collecting: friends are told, and their reports arrive whole.
	bobAlive()
	Advance(0.3)
	mark = #GAMEDATA + 1
	B("collectReports"):SetValue(true)
	Advance(0.5)
	check(sentTo(11, mark, "Y2;1")[1] and sentTo(12, mark, "Y2;1")[1], "switched on: my friends are told I collect")
	pmark = #PRINTED + 1
	anna("Z2;7;2;2; and more")
	anna("Z2;7;1;2;Error, |cffff0000LefthyTools|r 0.5.0^line two")
	Advance(0.3)
	local reports = LefthyToolsDB.friendReports
	check(reports[#reports].from == "Anna" and reports[#reports].text == "Error, cffff0000LefthyToolsr 0.5.0\nline two and more"
		and printedSince(pmark):find("Anna sent a LefthyTools error report: /lefthy reports shows it.", 1, true),
		"a friend's report, put together (parts in any order, no escape codes), and a chat line")
	anna("Z2;8;1;3;first part")
	for _ = 1, 5 do
		Advance(25)
		bobAlive()
	end
	check(reports[#reports].text == "first part[part 2 of 3 missing][part 3 of 3 missing]", "parts that never came: kept with a note")
	lefthy("reports")
	check(LefthyToolsReportsFrame:IsShown() and BB.ReportsText():find("from Anna", 1, true)
		and BB.ReportsText():find("line two and more", 1, true), "/lefthy reports: all of them, ready to copy")
	LefthyToolsReportsFrame:Hide()
	mark = #GAMEDATA + 1
	B("collectReports"):SetValue(false)
	Advance(0.5)
	check(sentTo(11, mark, "Y2;0")[1], "switched off: told too")
	local count = #reports
	anna("Z2;9;1;1;ignored")
	Advance(0.3)
	check(#reports == count, "not collecting: friends' reports are ignored")
	wipe(reports)
end

section("Beacon: fight stream (a test)")
do
	check(BDB.fightStream == false and B("fightStream") and SETTINGS_BUTTONS["Fight stream window"]
		and SETTINGS_BUTTONS["What the game tells addons"] and SETTINGS_BUTTONS["Test results"]
		and SETTINGS_BUTTONS["Your own fight, live"], "off by default, a checkbox and its buttons")
	local pmark = #PRINTED + 1
	lefthy("stream preview")
	lefthy("beacon stream me")
	check(not (LefthyToolsStreamFrame and LefthyToolsStreamFrame:IsShown()) and not LefthyToolsDB.streamTests
		and select(2, printedSince(pmark):gsub("is a test and off", "")) == 2, "off: nothing opens, and I'm told how to switch it on")
	B("fightStream"):SetValue(true)
	local function dot(name)
		for _, d in ipairs(BB.StreamDots()) do if d.key and d.mob.name == name then return d end end
	end
	local function used()
		local n = 0
		for _, d in ipairs(BB.StreamDots()) do if d.key and d:IsShown() then n = n + 1 end end
		return n
	end

	-- The preview: made-up mobs around a made-up friend.
	lefthy("stream preview")
	Advance(0.6)
	local win = LefthyToolsStreamFrame
	check(win and win:IsShown() and win.Title:GetText():find("Anna", 1, true) and win.Live.Text:GetText() == "DEMO"
		and used() == 5, "/lefthy stream preview: the window, a friend and five mobs")
	local leader, gnoll = dot("Bandit leader"), dot("Gnoll")
	check(leader.Ring:IsShown() and gnoll.ty < 0 and gnoll.Body.alpha < 1 and not gnoll.Ring:IsShown(),
		"an elite has a gold ring; a mob without a direction sits behind, faint")
	local before = leader.tx * leader.tx + leader.ty * leader.ty
	Advance(3)
	check(leader.tx * leader.tx + leader.ty * leader.ty < before and math.abs(leader.x - leader.tx) < 3,
		"mobs move, and their dots glide after them")
	check(win.Status:GetText():find("on Anna", 1, true) and win.Status:GetText():find("near", 1, true), "the bottom line: how many on her, how many near")
	Advance(12)
	local bandit = dot("Bandit")
	check(bandit and bandit.Skull:IsShown() and not bandit.Body:IsShown(), "a mob that dies: a skull ...")
	Advance(2.5)
	check(bandit:GetAlpha() < 0.5, "... that fades")
	win.Close:Click()
	check(not win:IsShown() and used() == 0, "the X closes it, its dots let go")

	-- "me": the mobs around me, as the game tells them.
	MOBS = {
		nameplate1 = { name = "Defias Thug", level = 15, combat = true, attacking = true, yards = 4, x = 0.5, y = 0.45 },
		nameplate2 = { name = "Defias Pillager", level = 16, class = "elite", combat = true, casting = "Fireball", yards = 25, x = 0.25, y = 0.6 },
		nameplate3 = { name = "Gnoll", level = 14, yards = 35 }, -- no nameplate frame: no direction
	}
	lefthy("stream me")
	Advance(0.6)
	local thug, pillager = dot("Defias Thug"), dot("Defias Pillager")
	gnoll = dot("Gnoll")
	check(win:IsShown() and win.Title:GetText():find("Lefthy", 1, true) and win.Live.Text:GetText() == "LIVE" and used() == 3,
		"/lefthy stream me: my own surroundings, live")
	check(math.abs(thug.tx) < 0.01 and thug.ty > 0 and thug.ty < 15, "a mob in the middle of my screen, close: just ahead of me")
	check(pillager.tx < 0 and math.sqrt(pillager.tx ^ 2 + pillager.ty ^ 2) > 30, "one left on my screen, further away: ahead to the left")
	check(gnoll.ty < 0 and gnoll.Body.alpha < 1 and win.Hint:IsShown(),
		"one without a direction: spread out (alone: behind me), faint, and the window says directions are guessed")
	check(win.Status:GetText():find("1 on you", 1, true) and win.Status:GetText():find("3 near", 1, true)
		and win.Status:GetText():find("Defias Pillager casts Fireball", 1, true), "the bottom line, got " .. tostring(win.Status:GetText()))
	gnoll._scripts.OnEnter(gnoll)
	check(TOOLTIP.title == "Gnoll (14)" and tooltipHas("direction unknown"), "hover: what's known about it")
	gnoll._scripts.OnLeave(gnoll)
	-- My target beyond nameplate range: shown all the same, ahead (I face what I fight), on the rim.
	MOBS.target, STATE.target = { name = "Far Kodo", level = 26, yards = 60, guid = "Creature-0-far" }, true
	Advance(0.6)
	local kodo = dot("Far Kodo")
	check(kodo and math.abs(kodo.tx) < 0.01 and kodo.ty > 100 and used() == 4, "my target beyond nameplate range: shown, ahead, on the rim")
	kodo._scripts.OnEnter(kodo)
	check(tooltipHas("more than 30 yd away") and tooltipHas("your target"), "... further than the range checks reach, and it's my target")
	kodo._scripts.OnLeave(kodo)
	MOBS.target, STATE.target = nil, false
	MOBS.nameplate3 = nil
	Advance(0.6)
	check(not win.Hint:IsShown(), "every mob with a direction: no word about guessing")
	MOBS.nameplate3 = { name = "Gnoll", level = 14, yards = 35 }
	MOBS.nameplate1 = nil
	Advance(0.6)
	check(not dot("Defias Thug") and used() == 2, "a mob gone: its dot goes")
	B("fightStream"):SetValue(false)
	check(not win:IsShown(), "switched off: the window closes")
	B("fightStream"):SetValue(true)

	-- The test: what answers, in and out of combat.
	MOBS.nameplate1 = { name = "Defias Thug", level = 15, combat = true, attacking = true, yards = 4, x = 0.5, y = 0.45 }
	MOBS.nameplate2.plateError = "can't measure this region" -- (like the first test on Forever)
	pmark = #PRINTED + 1
	lefthy("stream test")
	check(printedSince(pmark):find("fight stream test: 60 s of notes", 1, true), "/lefthy stream test: it starts and says what to do")
	STATE.combat = true
	Advance(30)
	STATE.combat = false
	pmark = #PRINTED + 1
	Advance(30.5)
	local tests = LefthyToolsDB.streamTests
	local report = tests and tests[1] and tests[1].text or ""
	check(#tests == 1 and printedSince(pmark):find("fight stream test done", 1, true), "after a minute: done, kept, and I'm told")
	local function has(text) return report:find(text, 1, true) ~= nil end
	check(has("Fight stream test: LefthyTools ") and has("(open world)") and has("up to 3 nameplates at once")
		and has("Settings: enemy nameplates 1, nameplate distance 41, camera field of view 90"), "the report: where, when, the settings")
	check(has("UnitName: value 180 | value 180") and has("e.g. Defias Thug; Defias Pillager") and has("UnitHealth: hidden 180 | hidden 180")
		and has("UnitGUID: value 180 | value 180\n") and has("UnitPosition(player): value 60 | value 60\n"),
		"what answers and what's hidden, in and out of combat, with examples (none of GUIDs and my position)")
	check(has("spell Throw (30 yd): true 120, false 60 | true 120, false 60") and has("item 835 (30 yd): nil 180 | true 120, false 60")
		and has("CheckInteractDistance 3 (10 yd): error 180 |") and has("e.g. CheckInteractDistance: blocked in combat"),
		"each range check, in and out of combat, with what the errors say")
	check(has("item 18904 (range to measure): nil 180 | true 180   -> more than 30 yd") and has("item 4941 (range to measure): nil 180 | nil 180\n"),
		"items of unknown range: measured against the others")
	check(has("nameplate position: GetCenter: nil 60, onscreen 60, error 60 |") and has("e.g. 0.50,0.45; can't measure this region")
		and has("nameplate.UnitFrame: GetCenter: value 60, error 60 |") and has("own frame anchored to it: GetCenter: nil 120 |"),
		"nameplate positions, with what the errors say, and other ways to read them")
	check(has("Distance: 2 of 7 range checks of known range answered in combat, 5 only out of combat.")
		and has("readable in combat: GetNamePlateForUnit(<unit>, includeForbidden), nameplate: IsVisible"),
		"a short summary, got\n" .. report)
	lefthy("stream results")
	check(LefthyToolsStreamTestsFrame and LefthyToolsStreamTestsFrame:IsShown(), "/lefthy stream results: ready to copy")
	LefthyToolsStreamTestsFrame:Hide()
	pmark = #PRINTED + 1
	lefthy("stream test")
	Advance(2)
	lefthy("stream test")
	check(#tests == 2 and printedSince(pmark):find("fight stream test stopped", 1, true), "again while it runs: stopped early, kept")
	for _ = 1, 2 do
		lefthy("stream test")
		Advance(1)
		lefthy("stream test")
	end
	check(#tests == 3, "the last three are kept")
	lefthy("stream test")
	B("fightStream"):SetValue(false)
	Advance(61)
	check(#tests == 3, "switched off: a running test stops, unsaved")
	MOBS = {}
end

section("Beacon: a busy fight doesn't pile up messages")
do
	anna("S2;;0;260.0;750.0;Goldshire;")
	Advance(0.2)
	mark = #GAMEDATA + 1
	MOCK_SEND_RESULT = 3 -- the server is throttling: everything waits in the queue
	STATE.combat = true
	Fire("PLAYER_REGEN_DISABLED")
	for i = 1, 4 do
		THREAT["nameplate" .. i] = 1
		Fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. i)
		Advance(1.05)
	end
	MOCK_SEND_RESULT = nil
	Advance(3)
	local counts = sentTo(11, mark, "C2;")
	check(#counts == 1 and counts[1] == "C2;4", "only the newest count goes out once the queue moves, got " .. table.concat(counts, ","))
	STATE.combat = false
	Fire("PLAYER_REGEN_ENABLED")
	for i = 1, 4 do Fire("NAME_PLATE_UNIT_REMOVED", "nameplate" .. i) end
	THREAT = {}
	Advance(1.2)
end

section("Misc Tweaks: cinematic flights")
do
	local TDB = LefthyToolsDB.settings.tweaks
	check(TDB.cinematicFlights == true and REGISTERED_SETTINGS.LefthyTools_tweaks_cinematicFlights
		and not REGISTERED_SETTINGS.LefthyTools_tweaks_flightCamera, "on by default, with a checkbox (no camera option)")
	local uiW, uiH = UIParent:GetWidth(), UIParent:GetHeight()
	UIParent:SetSize(1920, 1080)
	anna("H2") -- friends online, in Elwynn Forest (whatever earlier tests took long enough to forget)
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "H2", "WHISPER", 12)
	Advance(0.2)
	-- The flight map: where you are (state 0) and the destination, 1118 yd apart in a straight line.
	TAXI_MAP_NODES = {
		{ name = "Stormwind, Elwynn", state = 0, slotIndex = 1, position = CreateVector2D(0.5, 0.5) },
		{ name = "Sentinel Hill, Westfall", state = 1, slotIndex = 3, position = CreateVector2D(0.45, 0.6) },
	}
	TAXI_NODES[3] = "Sentinel Hill, Westfall"
	local route = "Stormwind, Elwynn > Sentinel Hill, Westfall"
	LefthyToolsDB.flightTimes[route], LefthyToolsDB.flightPace = nil, nil
	TakeTaxiNode(3) -- picked on the flight map
	ZONE, CAMERA.zoom, CAMERA.spinning = "Stormwind City", 10, false
	Fire("PLAYER_CONTROL_LOST") -- a stun, say: no taxi
	Advance(0.5)
	check(UIParent:GetAlpha() == 1 and not (LefthyToolsFlightFrame and LefthyToolsFlightFrame:IsShown()), "losing control without a flight: nothing")
	Advance(3)
	TRAVEL.taxi = true
	Fire("PLAYER_CONTROL_LOST")
	Advance(0.3)
	local film = LefthyToolsFlightFrame
	check(film and film:IsShown() and not film._mouseEnabled and film.Top.height == 76 and film.Bottom.height == 76,
		"on the flight: black bars top and bottom (7% of the screen, room for friends' lines); clicks and camera drags go through")
	check(film.Timer:GetText() == "Landing in about 0:43",
		"a first flight on this route: the time left, estimated from the distance, got " .. tostring(film.Timer:GetText()))
	local alphaMidway = UIParent:GetAlpha()
	check(alphaMidway > 0 and alphaMidway < 1, "the interface fades out, got " .. alphaMidway)
	Advance(1.5)
	check(UIParent:GetAlpha() == 0, "... and is gone")
	local card = film.Card
	check(card and card.Title:GetText() == "Sentinel Hill" and card.Sub:GetText() == "Westfall" and card.Header:GetText() == "Next stop"
		and card.Title.fontFile == "Fonts\\MORPHEUS.TTF" and card.Anim.plays == 1, "a title card: the destination")
	check(CAMERA.zoom == 10 and not CAMERA.spinning, "the camera is left alone")
	-- A zone on the way, with its level range and a friend who is there.
	ZONE = "Elwynn Forest"
	Fire("ZONE_CHANGED_NEW_AREA")
	Advance(0.3)
	check(card.Title:GetText() == "Elwynn Forest" and card.Header:GetText() == "Eastern Kingdoms"
		and card.Sub:GetText():find("Levels 1-10", 1, true) and card.Sub:GetText():find("Anna|r, |cffc79c6eBob|r are here", 1, true)
		and card.Anim.plays == 2,
		"each new zone gets a card: continent, levels, friends there, got " .. tostring(card.Sub:GetText()))
	Fire("ZONE_CHANGED_NEW_AREA") -- same zone again
	Advance(0.3)
	check(card.Anim.plays == 2, "the same zone again: no new card")
	-- Whispers and party chat as subtitles.
	Fire("CHAT_MSG_WHISPER", "where are you?", "Bob-Realmy")
	Fire("CHAT_MSG_PARTY", "pull in 5", "Anna")
	Advance(0.3)
	check(film.Subtitles:GetText() == "|cffff80ff[Bob]|r where are you?\n|cffaaaaff[Anna]|r pull in 5", "subtitles, got " .. tostring(film.Subtitles:GetText()))
	check(film.Timer:GetText() == "Landing in about 0:40", "the time left counts down, got " .. tostring(film.Timer:GetText()))
	Advance(8)
	check(film.Subtitles:GetText() == "", "subtitles fade after a few seconds")
	Advance(35)
	check(film.Timer:GetText() == "Landing any moment", "past the estimate: any moment")
	-- Landing: everything back, and this route's time is kept.
	TRAVEL.taxi = false
	Fire("PLAYER_CONTROL_GAINED")
	Advance(0.3)
	local took = LefthyToolsDB.flightTimes[route]
	check(took and took >= 44 and took <= 48 and LefthyToolsDB.flightPace
		and math.abs(LefthyToolsDB.flightPace - took / 1118.03) < 0.001,
		"landed: the flight's time is kept for the route, the pace learned, got " .. tostring(took) .. ", pace " .. tostring(LefthyToolsDB.flightPace))
	Advance(1.5)
	check(UIParent:GetAlpha() == 1, "and the interface fades back in")
	film.FadeOut:Finish()
	check(not film:IsShown(), "the bars fade away")
	check(not ns.CinematicFlight.driver:IsShown(), "on the ground nothing runs")
	-- The same route again: counted down exactly. Opening the map pauses the film; closing it brings it back.
	TakeTaxiNode(3)
	TRAVEL.taxi = true
	Fire("PLAYER_CONTROL_LOST")
	Advance(2)
	check(film:IsShown() and UIParent:GetAlpha() == 0, "the next flight")
	do -- The top bar: friends side by side, three lines each that keep their place.
		local anna, bob = film.FriendColumns[1], film.FriendColumns[2]
		local function y(line) return line._points and line._points[1] and line._points[1][5] end
		local function x(line) return line._points and line._points[1] and line._points[1][4] end
		check(anna.Who:GetText():find("Anna", 1, true) and anna.Who:GetText():find("Level 20", 1, true)
			and bob.Who:GetText():find("Bob", 1, true) and x(anna.Who) < 0 and x(bob.Who) > 0,
			"the top bar: my Beacon friends side by side, name, level and where first, got " .. anna.Who:GetText())
		check(y(anna.Who) > 0 and y(anna.Quest) == 0 and y(anna.Fight) < 0, "three lines: who and where, quest, fighting")
		local fadeIns = anna.FightIn.plays
		Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "T2;176;0;Wanted: Hogger;Hogger slain: 0/1", "WHISPER", 11)
		Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;C;0;260.0;750.0;Goldshire;Hogger", "WHISPER", 11)
		ns.CinematicFlight.UpdateFriends(GetTime())
		check(anna.Quest:GetText():find("Quest: Wanted: Hogger", 1, true) and anna.Fight:GetText():find("Fighting Hogger", 1, true)
			and anna.FightIn.plays == fadeIns + 1 and anna.Fight:GetAlpha() == 1 and y(anna.Who) > 0 and y(anna.Quest) == 0,
			"her quest on its own line; a fight fades in on the third, nothing else moves, got " .. tostring(anna.Fight:GetText()))
		ns.CinematicFlight.UpdateFriends(GetTime())
		check(anna.FightIn.plays == fadeIns + 1, "still fighting: no new fade")
		Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;260.0;750.0;Goldshire;", "WHISPER", 11)
		ns.CinematicFlight.UpdateFriends(GetTime())
		check(anna.FightOut.plays == 1 and anna.Fight:GetAlpha() == 0 and anna.Fight:GetText():find("Fighting Hogger", 1, true),
			"the fight over: the line fades out (its words stay while it does)")
		LefthyToolsDB.settings.tweaks.flightFriends = false
		ns.CinematicFlight.UpdateFriends(GetTime())
		check(anna.Who:GetText() == "" and anna.Quest:GetText() == "" and bob.Who:GetText() == "", "setting off: the top bar stays black")
		LefthyToolsDB.settings.tweaks.flightFriends = true
	end
	check(film.Timer:GetText() == ("Landing in 0:%02d"):format(took - 2), "the same route: an exact countdown, got " .. tostring(film.Timer:GetText()))
	OpenWorldMap(1429)
	Advance(0.3)
	check(not film:IsShown() and UIParent:GetAlpha() == 1, "opening the map: the interface is back at once")
	Advance(3)
	check(not film:IsShown(), "while it's open the film waits")
	WorldMapFrame:Hide()
	Advance(1)
	check(not film:IsShown(), "just closed: not yet")
	Advance(1.5)
	check(film:IsShown(), "a moment later the film is back")
	Advance(1.5)
	check(UIParent:GetAlpha() == 0, "... the interface faded out again")
	-- The settings panel and LefthyTools' own windows (Chronicle, what's new, ...) count too.
	SettingsPanel:Show()
	Advance(0.3)
	check(not film:IsShown() and UIParent:GetAlpha() == 1, "the settings panel: the interface is back")
	Advance(3)
	check(not film:IsShown(), "and the film waits while it's open")
	SettingsPanel:Hide()
	Advance(2.5)
	check(film:IsShown(), "settings closed: the film again")
	SlashCmdList.LEFTHYTOOLS_CHRONICLE("")
	Advance(0.3)
	check(LefthyToolsChronicleFrame:IsShown() and not film:IsShown() and UIParent:GetAlpha() == 1, "the Chronicle window: the interface is back")
	Advance(3)
	check(not film:IsShown(), "and the film waits while it's open")
	LefthyToolsChronicleFrame:Hide()
	Advance(2.5)
	check(film:IsShown(), "Chronicle closed: the film again")
	-- Typing in chat pauses it the same way.
	ACTIVE_CHAT_EDIT_BOX = {}
	Advance(0.3)
	check(not film:IsShown() and UIParent:GetAlpha() == 1, "typing: the interface is back")
	ACTIVE_CHAT_EDIT_BOX = nil
	Advance(2.5)
	check(film:IsShown(), "done typing: the film again")
	-- A popup that needs you ends it for this flight; the flight is still timed.
	Fire("READY_CHECK")
	Advance(0.05)
	check(not film:IsShown() and UIParent:GetAlpha() == 1, "a ready check: everything back at once")
	Advance(4)
	check(not film:IsShown(), "and it stays back for this flight")
	local taxiChecks, onTaxi = 0, UnitOnTaxi
	UnitOnTaxi = function(...) taxiChecks = taxiChecks + 1; return onTaxi(...) end
	Advance(1)
	UnitOnTaxi = onTaxi
	check(taxiChecks <= 8, "ended for this flight: the driver checks a few times a second, not every frame, got " .. taxiChecks)
	Advance(8.4) -- (36 s in the air, with the windows above)
	TRAVEL.taxi = false
	Fire("PLAYER_CONTROL_GAINED")
	Advance(0.5)
	check(math.abs(LefthyToolsDB.flightTimes[route] - 36) <= 2 and not ns.CinematicFlight.driver:IsShown(),
		"landed: that flight's time is kept too, got " .. tostring(LefthyToolsDB.flightTimes[route]))
	-- With the flight path data (Data/FlightPaths.lua, the client's own paths): a route's real
	-- length, all its legs, at ~29.9 yd/s. Real node IDs: Undercity 11, Tarren Mill 13, Hammerfall 17.
	TAXI_MAP_NODES = {
		{ name = "Undercity, Tirisfal", state = 0, slotIndex = 1, nodeID = 11, position = CreateVector2D(0.5, 0.5) },
		{ name = "Tarren Mill, Hillsbrad", state = 1, slotIndex = 3, nodeID = 13, position = CreateVector2D(0.55, 0.6) },
		{ name = "Hammerfall, Arathi", state = 1, slotIndex = 4, nodeID = 17, position = CreateVector2D(0.6, 0.7) },
	}
	TAXI_NODES[3], TAXI_NODES[4] = "Tarren Mill, Hillsbrad", "Hammerfall, Arathi"
	TAXI_ROUTES = { [3] = { { 1, 3 } }, [4] = { { 1, 3 }, { 3, 4 } } }
	LefthyToolsDB.flightPathPace = nil
	TakeTaxiNode(4) -- two legs: Undercity > Tarren Mill > Hammerfall, 4222 + 3532 yd
	TRAVEL.taxi = true
	Fire("PLAYER_CONTROL_LOST")
	Advance(0.3)
	check(film.Timer:GetText() == "Landing in 4:19", "a route never flown: its real length, all legs, no \"about\", got " .. tostring(film.Timer:GetText()))
	Advance(270)
	TRAVEL.taxi = false
	Fire("PLAYER_CONTROL_GAINED")
	Advance(0.5)
	check(LefthyToolsDB.flightPathPace and math.abs(LefthyToolsDB.flightPathPace - (0.7 / 29.9 + 0.3 * 271 / 7754)) < 0.0005,
		"landed a bit later: the pace learns from it, got " .. tostring(LefthyToolsDB.flightPathPace))
	-- A route flown at another speed (some of Forever's own) keeps its own time and doesn't skew the pace.
	local pace = LefthyToolsDB.flightPathPace
	TakeTaxiNode(3)
	TRAVEL.taxi = true
	Fire("PLAYER_CONTROL_LOST")
	-- On the way: a friend's item share is a subtitle; an offer pauses the film so its buttons show.
	anna("H2")
	Advance(2)
	anna("I2;1179::::::::20:::::")
	Advance(0.3)
	check(film:IsShown() and film.Subtitles:GetText():find("Anna|r shares", 1, true),
		"a friend shows an item: a subtitle, got " .. tostring(film.Subtitles:GetText()))
	Advance(2.1)
	anna("I2;6948::::::::20:::::;6161")
	Advance(0.3)
	check(not film:IsShown() and UIParent:GetAlpha() == 1 and BB.calls["11:6161"].frame.Need:IsShown(),
		"a friend's offer: the film pauses for its Need and Pass buttons")
	BB.calls["11:6161"].frame.Pass:Click()
	Advance(2.5)
	check(film:IsShown(), "answered: the film comes back")
	anna("R2;6161;Bob:0")
	Advance(0.3)
	check(film.Subtitles:GetText():find("Bob wins!", 1, true), "and the outcome comes as a subtitle, got " .. tostring(film.Subtitles:GetText()))
	Advance(62.5) -- 4222 yd in 70 s: much faster than the rest
	TRAVEL.taxi = false
	Fire("PLAYER_CONTROL_GAINED")
	Advance(0.5)
	check(LefthyToolsDB.flightPathPace == pace and math.abs(LefthyToolsDB.flightTimes["Undercity, Tirisfal > Tarren Mill, Hillsbrad"] - 70) <= 1,
		"an odd one: its time is kept, the pace isn't moved")
	-- A leg the data doesn't know: the straight line again, "about".
	TAXI_ROUTES[4] = { { 1, 3 }, { 3, 99 } }
	LefthyToolsDB.flightTimes["Undercity, Tirisfal > Hammerfall, Arathi"] = nil
	TakeTaxiNode(4)
	TRAVEL.taxi = true
	Fire("PLAYER_CONTROL_LOST")
	Advance(0.3)
	check(film.Timer:GetText():find("^Landing in about "), "a leg not in the data: the straight-line estimate, got " .. tostring(film.Timer:GetText()))
	TRAVEL.taxi = false
	Fire("PLAYER_CONTROL_GAINED")
	Advance(0.5)
	TAXI_ROUTES = {}
	-- The first version moved the camera: one left zoomed out or circling (a /reload mid-flight) is put back once.
	TDB.flightZoom, TDB.flightOrbit, TDB.flightMaxZoom, TDB.flightCamera, CAMERA.zoom, CAMERA.spinning = 10, true, 1.9, true, 22, true
	CVARS.cameraDistanceMaxZoomFactor = "2.6"
	lefthy("tweaks flights off")
	Advance(0.1)
	lefthy("tweaks flights on")
	Advance(0.1)
	check(CAMERA.zoom == 10 and not CAMERA.spinning and CVARS.cameraDistanceMaxZoomFactor == "1.9"
		and TDB.flightZoom == nil and TDB.flightCamera == nil, "the old camera settings: put back and gone")
	-- With the AFK screen at the same time, the interface stays hidden until both are done.
	ns.HideInterface("afk", true)
	TRAVEL.taxi = true
	Fire("PLAYER_CONTROL_LOST")
	Advance(2)
	check(film.Timer:GetText() == "", "a flight not picked on the map (a reload mid-flight): no time shown")
	TRAVEL.taxi = false
	Fire("PLAYER_CONTROL_GAINED")
	Advance(2)
	check(UIParent:GetAlpha() == 0, "landing while the AFK screen still hides it: still hidden")
	ns.HideInterface("afk", false)
	check(UIParent:GetAlpha() == 1, "both done: back")
	lefthy("tweaks flights off")
	Advance(0.1)
	check(TDB.cinematicFlights == false, "/lefthy tweaks flights off")
	TRAVEL.taxi = true
	Fire("PLAYER_CONTROL_LOST")
	Advance(2)
	check(UIParent:GetAlpha() == 1, "off: flights stay normal")
	TRAVEL.taxi = false
	Fire("PLAYER_CONTROL_GAINED")
	lefthy("tweaks flights on")
	Advance(0.5)
	UIParent:SetSize(uiW, uiH)
	ZONE = "Elwynn Forest"
end

section("Misc Tweaks: a flight that starts while typing")
do
	TAXI_NODES[3] = "Sentinel Hill, Westfall"
	TAXI_MAP_NODES = {
		{ name = "Stormwind, Elwynn", state = 0, slotIndex = 1, position = CreateVector2D(0.5, 0.5) },
		{ name = "Sentinel Hill, Westfall", state = 1, slotIndex = 3, position = CreateVector2D(0.45, 0.6) },
	}
	local route = "Stormwind, Elwynn > Sentinel Hill, Westfall"
	LefthyToolsDB.flightTimes[route] = nil
	local film = LefthyToolsFlightFrame
	if film:IsShown() then film.FadeOut:Finish() end
	ACTIVE_CHAT_EDIT_BOX = {} -- still typing as the flight starts
	TakeTaxiNode(3)
	TRAVEL.taxi = true
	Fire("PLAYER_CONTROL_LOST")
	Advance(6)
	check(not film:IsShown(), "typing at takeoff: no film yet")
	ACTIVE_CHAT_EDIT_BOX = nil
	Advance(0.5)
	check(film:IsShown(), "done typing (6 s in): the film starts after all")
	Advance(20)
	TRAVEL.taxi = false
	Fire("PLAYER_CONTROL_GAINED")
	Advance(0.5)
	local took = LefthyToolsDB.flightTimes[route]
	check(took and took >= 26 and took <= 27, "and the flight is timed from the takeoff, got " .. tostring(took))
	Advance(2)
	film.FadeOut:Finish()
	-- Switched on in the air: the film comes, but a flight it didn't see from the takeoff isn't kept.
	LefthyToolsDB.flightTimes[route] = nil
	lefthy("tweaks flights off")
	Advance(0.2)
	TakeTaxiNode(3)
	TRAVEL.taxi = true
	Fire("PLAYER_CONTROL_LOST")
	Advance(5)
	lefthy("tweaks flights on")
	Advance(0.5)
	Fire("PLAYER_ENTERING_WORLD", false, false) -- (as if the film looked again)
	Advance(0.5)
	Advance(20)
	TRAVEL.taxi = false
	Fire("PLAYER_CONTROL_GAINED")
	Advance(0.5)
	check(LefthyToolsDB.flightTimes[route] == nil, "a flight the film joined late isn't kept as the route's time")
	Advance(2)
	if film:IsShown() then film.FadeOut:Finish() end
end

section("Misc Tweaks: what a flight hides")
do
	local TDB = LefthyToolsDB.settings.tweaks
	local function T(id) return REGISTERED_SETTINGS["LefthyTools_tweaks_" .. id] end
	check(TDB.flightHide == "all" and TDB.flightGroups.chat == true and TDB.flightGroups.actionbars == true
		and T("flightHide") and T("flightGroup_chat") and T("flightGroup_minimap"), "default: everything; every element ticked")
	local mirageWasOn = Mirage.enabled
	if mirageWasOn then
		lefthy("disable mirage")
		Advance(3)
	end
	local barsBefore, playerBefore = a("MainActionBar"), a("PlayerFrame")
	T("flightHide"):SetValue(2) -- chosen elements
	T("flightGroup_chat"):SetValue(false)
	TRAVEL.taxi = true
	Fire("PLAYER_CONTROL_LOST")
	Advance(2.5)
	check(LefthyToolsFlightFrame:IsShown() and UIParent:GetAlpha() == 1 and a("MainActionBar") == 0 and a("PlayerFrame") == 0
		and a("ChatFrame1") == 1, "chosen elements, Mirage off: those go (action bars, unit frames), chat stays")
	check(not Minimap:IsShown(), "... a hidden minimap is taken away altogether (its quest areas ignore opacity)")
	ACTIVE_CHAT_EDIT_BOX = {}
	Advance(0.3)
	check(a("MainActionBar") == barsBefore and Minimap:IsShown(), "typing: back at once")
	ACTIVE_CHAT_EDIT_BOX = nil
	Advance(4.5)
	check(a("MainActionBar") == 0, "done typing: hidden again")
	TRAVEL.taxi = false
	Fire("PLAYER_CONTROL_GAINED")
	Advance(2.5)
	check(a("MainActionBar") == barsBefore and a("PlayerFrame") == playerBefore and Minimap:IsShown(),
		"landed: everything back at its own opacity (Edit Mode's, too)")
	T("flightHide"):SetValue(1)
	T("flightGroup_chat"):SetValue(true)
	if mirageWasOn then
		lefthy("enable mirage")
		Advance(0.5)
	end
end

section("Misc Tweaks: quests on continent and world maps")
do
	local TDB = LefthyToolsDB.settings.tweaks
	local function T(id) return REGISTERED_SETTINGS["LefthyTools_tweaks_" .. id] end
	check(TDB.questMap == true and TDB.questMapContinent == "both" and TDB.questMapWorld == "both"
		and TDB.questMapZone == "blizzard" and T("questMap") and T("questMapContinent") and T("questMapWorld") and T("questMapZone"),
		"on by default: icons and areas on continent maps and the world map, zone maps as Blizzard has them")
	local savedQuests = QUESTS
	QUESTS = {
		{ id = 101, title = "Kobold Camp Cleanup",
			objectives = { { text = "Kobold Vermin slain: 4/10", finished = false }, { text = "Map found", finished = true } } },
		{ id = 102, title = "The Defias Brotherhood", objectives = {}, complete = true },
		{ id = 103, title = "A city errand", objectives = { { text = "Package delivered: 0/1", finished = false } } },
	}
	-- What the zone maps show: Elwynn Forest its quest and the city's (reported on the zone too),
	-- the city its own, Westfall one.
	QUESTS_ON_MAP = { [1429] = { { 101, 0.5, 0.5 }, { 103, 0.2, 0.2, 1453 } }, [1453] = { { 103, 0.5, 0.5 } },
		[1436] = { { 102, 0.5, 0.25 } } }
	SUPER_TRACKED = 0
	local asked = 0
	local getQuestsOnMap = C_QuestLog.GetQuestsOnMap
	C_QuestLog.GetQuestsOnMap = function(mapID) asked = asked + 1; return getQuestsOnMap(mapID) end
	local ICONS, AREAS = "LefthyToolsQuestMapPinTemplate", "LefthyToolsQuestAreaPinTemplate"
	local function iconOf(id) for _, pin in ipairs(PinsOf(ICONS)) do if pin.quest.questID == id then return pin end end end
	local function areaOf(zone) for _, pin in ipairs(PinsOf(AREAS)) do if pin.mapID == zone then return pin end end end

	OpenWorldMap(1429)
	check(#PinsOf(ICONS) == 0 and #PinsOf(AREAS) == 0, "a zone map: Blizzard's own icons and area, nothing added")
	OpenWorldMap(1415)
	local kobolds, defias, errand = iconOf(101), iconOf(102), iconOf(103)
	check(#PinsOf(ICONS) == 3 and kobolds and defias and errand, "continent map: an icon per quest in its zones, the city's quest once")
	check(near(kobolds.x, 0.375) and near(kobolds.y, 0.375) and near(defias.x, 0.25) and near(defias.y, 0.5625),
		"... at the zone map's spot, carried over to the continent")
	check(near(errand.x, 0.3) and near(errand.y, 0.3), "... a quest in the city at its spot in the city")
	check(kobolds.Icon.atlas == "Quest-In-Progress-Icon-yellow" and defias.Icon.atlas == "UI-QuestIcon-TurnIn-Normal"
		and kobolds.Back.atlas == "UI-QuestPoi-QuestNumber", "Blizzard's quest icons: in progress, ready to turn in")
	local elwynn = areaOf(1429)
	check(#PinsOf(AREAS) == 3 and elwynn and #elwynn.blobs == 1 and elwynn.blobs[1] == 101 and areaOf(1453).blobs[1] == 103
		and areaOf(1436).blobs[1] == 102, "... and the quest areas, each drawn for its own zone")
	check(elwynn:GetWidth() == 250 and elwynn:GetHeight() == 250 and near(elwynn.x, 0.375) and near(elwynn.y, 0.375),
		"... laid over that zone on the continent")
	kobolds:OnMouseEnter()
	local tip = table.concat(TOOLTIP.lines, "|")
	check(TOOLTIP.title == "Kobold Camp Cleanup" and tip:find("Elwynn Forest", 1, true) and tip:find("Kobold Vermin slain: 4/10", 1, true)
		and not tip:find("Map found", 1, true), "hovering an icon: the quest, its zone and what's left, got " .. tip)
	check(#PinsOf(AREAS) == 3, "... areas already shown: none added")
	kobolds:OnMouseLeave()
	check(not TOOLTIP.shown, "the tooltip goes on leave")
	defias:OnMouseEnter()
	check(table.concat(TOOLTIP.lines, "|"):find("Ready to turn in", 1, true), "a finished quest: ready to turn in")
	defias:OnMouseLeave()

	OpenWorldMap(947)
	check(#PinsOf(ICONS) == 3 and near(iconOf(101).x, 0.65) and near(iconOf(101).y, 0.325) and near(iconOf(103).x, 0.62),
		"world map: the same quests, placed through their continent")
	check(areaOf(1429) and near(areaOf(1429).x, 0.65) and near(areaOf(1429):GetWidth(), 100), "... with their areas")

	SUPER_TRACKED = 101
	OpenWorldMap(1415)
	check(not iconOf(101) and #PinsOf(ICONS) == 2 and areaOf(1429).blobs[1] == 101,
		"the selected quest: Blizzard shows its icon on continent maps, so only its area is added")
	OpenWorldMap(947)
	check(iconOf(101) and iconOf(101).Back.atlas == "UI-QuestPoi-QuestNumber-SuperTracked"
		and iconOf(101).frameLevelType == "PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST", "... the world map shows it, marked as selected")
	SUPER_TRACKED = 0

	-- Clicking an icon selects its quest, as on zone maps.
	local savedWatched = WATCHED
	WATCHED = {}
	OpenWorldMap(1415)
	check(TDB.questMapClick == true and T("questMapClick") and iconOf(102)._click == true
		and iconOf(102)._passThrough and iconOf(102)._passThrough[1] == "RightButton",
		"icons take left clicks (a setting, on); right-clicks go through to the map, which zooms out")
	local soundMark = #SOUNDS
	iconOf(102):OnClick("LeftButton")
	check(SUPER_TRACKED == 102 and WATCHED[1] == 102 and #SOUNDS == soundMark + 1, "a click selects the quest and tracks it, with a click sound")
	Advance(0.05)
	check(not iconOf(102) and #PinsOf(ICONS) == 2, "... the map is redrawn right away: on continent maps Blizzard shows the selected quest's icon")
	OpenWorldMap(947)
	iconOf(102):OnClick("LeftButton")
	check(SUPER_TRACKED == 0 and WATCHED[1] == 102, "clicking the selected quest unselects it (it stays tracked)")
	STATE.shift = true
	iconOf(102):OnClick("LeftButton")
	STATE.shift = false
	check(SUPER_TRACKED == 0 and #WATCHED == 0, "Shift-click on a tracked quest stops tracking it")
	iconOf(101):OnClick("RightButton")
	check(SUPER_TRACKED == 0, "a right-click doesn't select")
	T("questMapContinent"):SetValue(2) -- icons only
	SUPER_TRACKED = 101
	OpenWorldMap(1415)
	check(#PinsOf(AREAS) == 1 and areaOf(1429).blobs[1] == 101 and #areaOf(1429).blobs == 1,
		"icons only: the selected quest's area still shows, as on zone maps")
	SUPER_TRACKED = 0
	T("questMapContinent"):SetValue(4)
	T("questMapClick"):SetValue(false)
	OpenWorldMap(1415)
	iconOf(102):OnClick("LeftButton")
	check(iconOf(102)._click == false and SUPER_TRACKED == 0, "setting off: icons take no clicks, a click zooms the map in")
	T("questMapClick"):SetValue(true)
	GAMEPAD_STATE.ui = true
	OpenWorldMap(1415)
	check(iconOf(102)._click == false and not iconOf(102).OnMouseClickAction,
		"gamepad mode: no click action (the controller's button would run it inside Blizzard's map code)")
	GAMEPAD_STATE.ui = false
	WATCHED = savedWatched
	Advance(0.6)

	T("questMapContinent"):SetValue(2) -- the slider: icons only
	check(TDB.questMapContinent == "icons", "continent maps: icons only")
	OpenWorldMap(1415)
	check(#PinsOf(ICONS) == 3 and #PinsOf(AREAS) == 0, "... no areas")
	kobolds = iconOf(101)
	kobolds:OnMouseEnter()
	check(#PinsOf(AREAS) == 1 and areaOf(1429).blobs[1] == 101 and #areaOf(1429).blobs == 1, "... hovering an icon shows its area")
	kobolds:OnMouseLeave()
	check(#PinsOf(AREAS) == 0, "... until the mouse leaves")
	T("questMapContinent"):SetValue(3) -- areas only
	Advance(0.6) -- the open map follows the setting
	check(#PinsOf(ICONS) == 0 and #PinsOf(AREAS) == 3, "areas only")
	T("questMapContinent"):SetValue(1)
	Advance(0.6)
	check(#PinsOf(ICONS) == 0 and #PinsOf(AREAS) == 0, "nothing")
	T("questMapContinent"):SetValue(4)
	Advance(0.6)

	T("questMapZone"):SetValue(2) -- every quest's area on zone maps
	SUPER_TRACKED = 103
	OpenWorldMap(1429)
	check(#PinsOf(ICONS) == 0 and #PinsOf(AREAS) == 1 and areaOf(1429).blobs[1] == 101 and #areaOf(1429).blobs == 1
		and areaOf(1429):GetWidth() == 1000, "zone maps, all quests: their areas over the whole map, not the selected one's (Blizzard draws it)")
	T("questMapZone"):SetValue(1)
	SUPER_TRACKED = 0

	FOCUSED_QUEST = 102
	QuestMapFrame_GetFocusedQuestID = function() return FOCUSED_QUEST end
	OpenWorldMap(1415)
	check(#PinsOf(ICONS) == 1 and iconOf(102) and #PinsOf(AREAS) == 1, "a quest's details open: only that quest, as on zone maps")
	QuestMapFrame_GetFocusedQuestID = nil

	-- Quest changes while the map is open: one redraw for a burst of events.
	OpenWorldMap(1415)
	QUESTS[#QUESTS + 1] = { id = 104, title = "Another one", objectives = {} }
	table.insert(QUESTS_ON_MAP[1436], { 104, 0.7, 0.7 })
	asked = 0
	for _ = 1, 5 do Fire("QUEST_LOG_UPDATE") end
	check(asked == 0, "quest events only queue a redraw")
	Advance(0.6)
	check(asked == 3 and iconOf(104), "... half a second later the map is redrawn once (3 zones asked), with the new quest")
	CVARS.questPOI = "0"
	Fire("CVAR_UPDATE", "questPOI")
	Advance(0.6)
	check(#PinsOf(ICONS) == 0 and #PinsOf(AREAS) == 0, "the map's quest objectives filter off: nothing")
	CVARS.questPOI = "1"
	local blockedMark = #BLOCKED
	STATE.combat = true
	OpenWorldMap(1414); OpenWorldMap(1415)
	check(#PinsOf(ICONS) == 4 and #BLOCKED == blockedMark, "drawn in combat without blocked actions, got " .. table.concat(BLOCKED, ", "))
	STATE.combat = false

	WorldMapFrame:Hide()
	asked = 0
	Fire("QUEST_LOG_UPDATE"); Fire("QUEST_POI_UPDATE")
	Advance(1)
	check(asked == 0, "map closed: quest events cost nothing")
	lefthy("tweaks questmap off")
	Advance(0.1)
	OpenWorldMap(1415)
	check(TDB.questMap == false and #PinsOf(ICONS) == 0 and #PinsOf(AREAS) == 0 and asked == 0, "/lefthy tweaks questmap off")
	lefthy("tweaks questmap on")
	Advance(0.1)
	OpenWorldMap(1415)
	check(#PinsOf(ICONS) == 4, "on again")
	WorldMapFrame:Hide()
	C_QuestLog.GetQuestsOnMap = getQuestsOnMap
	QUESTS, QUESTS_ON_MAP = savedQuests, {}
end


section("Chronicle: recording")
local CH, CDB = ns.Chronicle, LefthyToolsChronicleDB
local me = CDB and CDB.chars["Lefthy-Realmy"]
local function lastEvent(kind)
	for i = #me.events, 1, -1 do if me.events[i].k == kind then return me.events[i] end end
end
local function friendsOnline() -- mocked friends only talk when told to; Beacon forgets them after 65 s
	anna("S2;;0;260.0;750.0;Goldshire;")
	Advance(0.15)
end
do
	check(LT:GetModule("chronicle").enabled and me and me.classFile == "ROGUE" and me.race == "Human" and me.realm == "Realmy",
		"on by default; a record for this character")
	check(me.stats.sessions == 1, "one session since login, got " .. tostring(me.stats.sessions))
	Fire("PLAYER_ENTERING_WORLD", false, true) -- a /reload
	check(me.stats.sessions == 1, "a /reload continues the session")
	local ticks = CH.ticks
	Advance(5)
	check(CH.ticks - ticks >= 4 and CH.ticks - ticks <= 6, "it ticks once a second, got " .. (CH.ticks - ticks))
	local played = me.stats.played
	Advance(10)
	check(math.abs(me.stats.played - played - 10) < 1.1, "time played counts")
	check(me.seen.zones["Elwynn Forest"] and lastEvent("zone"), "the zone you're in is discovered")
	check(lastEvent("level") and lastEvent("level").level == 21, "the level-ups so far are in it")
	local levels = me.stats.levels
	Fire("PLAYER_LEVEL_UP", 22)
	Advance(100)
	Fire("PLAYER_LEVEL_UP", 23)
	local lv = lastEvent("level")
	check(lv.level == 23 and lv.zone == "Elwynn Forest" and lv.took and math.abs(lv.took - 100) < 2 and me.stats.levels == levels + 2,
		"a level-up: where, and how long the level took, got " .. tostring(lv.took))

	STATE.combat, STATE.target, STATE.targetName = true, true, "Hogger"
	Advance(1.1)
	STATE.combat, STATE.target, STATE.dead = false, false, true
	Fire("PLAYER_DEAD")
	local death = lastEvent("death")
	check(death and death.foe == "Hogger" and death.zone == "Elwynn Forest" and death.sub == "Goldshire" and me.killers.Hogger == 1,
		"a death: where, and what you were fighting")
	STATE.dead = false
	Fire("PLAYER_ALIVE")

	local quests = me.stats.quests
	Fire("QUEST_TURNED_IN", 176, 450, 100)
	Fire("QUEST_TURNED_IN", 86574, 900, 0) -- new in WoW: Forever
	check(me.stats.quests == quests + 2 and me.stats.foreverQuests == 1 and me.stats.questXP == 1350,
		"quests turned in, the new-in-Forever ones counted too")
	me.stats.quests = 9
	friendsOnline()
	mark = #GAMEDATA + 1
	Fire("QUEST_TURNED_IN", 177, 100, 0)
	check(lastEvent("quests") and lastEvent("quests").count == 10, "milestone: 10 quests")
	Advance(1.2)
	check(sentTo(11, mark, "E2;")[1] == "E2;quests;10;", "milestones go to friends, got " .. tostring(sentTo(11, mark, "E2;")[1]))

	local kills = me.stats.kills
	Fire("PARTY_KILL", "Player-1-0", "Creature-0-5")
	Fire("PARTY_KILL", "Player-1-11", "Creature-0-6")
	Fire("PARTY_KILL", SECRET, "Creature-0-7")
	check(me.stats.kills == kills + 1, "my killing blows count; others' and secret ones don't")

	friendsOnline()
	STATE.target, STATE.targetName, STATE.targetGUID, TARGET_CLASS, STATE.targetDead = true, "Mor'Ladim", "Creature-0-77", "rareelite", true
	mark = #GAMEDATA + 1
	Advance(1.1)
	local rare = lastEvent("rare")
	check(rare and rare.name == "Mor'Ladim" and rare.zone == "Elwynn Forest" and me.stats.rares == 1, "a rare dies while targeted")
	Advance(2)
	check(me.stats.rares == 1, "once per spawn")
	check(sentTo(11, mark, "E2;")[1] == "E2;rare;Mor'Ladim;Elwynn Forest", "and friends hear about it, got " .. table.concat(GameDataTo(11, mark), " | ") .. " peer: " .. tostring(peers()[11]))
	STATE.tapDenied, STATE.targetGUID = true, "Creature-0-78"
	Advance(1.1)
	check(me.stats.rares == 1, "someone else's tap isn't your kill")
	STATE.target, STATE.targetDead, STATE.targetGUID, TARGET_CLASS, STATE.targetName, STATE.tapDenied = false, false, nil, "normal", nil, false

	INSTANCE = { name = "The Deadmines", type = "party" }
	friendsOnline()
	mark = #GAMEDATA + 1
	Fire("ZONE_CHANGED_NEW_AREA")
	Advance(1.1)
	check(lastEvent("dungeon") and lastEvent("dungeon").name == "The Deadmines" and me.stats.dungeonRuns == 1, "first visit to a dungeon")
	check(not me.seen.zones["The Deadmines"] and lastEvent("zone").zone ~= "The Deadmines", "... and not a zone discovered as well")
	Fire("ENCOUNTER_END", 1, "Edwin VanCleef", 1, 5, 1)
	Fire("BOSS_KILL", 1, "Edwin VanCleef")
	Fire("ENCOUNTER_END", 2, "Cookie", 1, 5, 0) -- a wipe
	check(me.stats.bosses == 1 and lastEvent("boss").name == "Edwin VanCleef" and lastEvent("boss").instance == "The Deadmines",
		"a boss kill counts once (ENCOUNTER_END and BOSS_KILL both report it), a wipe not at all")
	Advance(1.2)
	local shared = table.concat(sentTo(11, mark, "E2;"), " | ")
	check(shared:find("E2;dungeon;The Deadmines;", 1, true) and shared:find("E2;boss;Edwin VanCleef;The Deadmines", 1, true),
		"both go to friends, got " .. shared)
	INSTANCE = nil
	Fire("ZONE_CHANGED_NEW_AREA")
	Advance(1.1)
	INSTANCE = { name = "The Deadmines", type = "party" }
	Fire("ZONE_CHANGED_NEW_AREA")
	Advance(1.1)
	local dungeonEntries = 0
	for _, e in ipairs(me.events) do if e.k == "dungeon" then dungeonEntries = dungeonEntries + 1 end end
	check(me.stats.dungeonRuns == 2 and dungeonEntries == 1, "a second run is counted, but isn't news")
	lefthy("disable chronicle") -- like a /reload inside
	Advance(0.3)
	lefthy("enable chronicle")
	Advance(1.2)
	check(me.stats.dungeonRuns == 2, "a /reload inside isn't another run")
	-- A dungeon or raid boss ("worldboss" in Classic) isn't a rare; a world boss outdoors is.
	STATE.target, STATE.targetName, STATE.targetGUID, TARGET_CLASS, STATE.targetDead = true, "Edwin VanCleef", "Creature-0-90", "worldboss", true
	local raresBefore = me.stats.rares
	Advance(1.1)
	check(me.stats.rares == raresBefore, "a boss in a dungeon isn't a rare kill")
	INSTANCE = nil
	STATE.targetGUID, STATE.targetName = "Creature-0-91", "Azuregos"
	Advance(1.1)
	check(me.stats.rares == raresBefore + 1, "a world boss outdoors is")
	STATE.target, STATE.targetDead, STATE.targetGUID, TARGET_CLASS, STATE.targetName = false, false, nil, "normal", nil
	INSTANCE = nil
	ZONE = "Westfall"
	Fire("ZONE_CHANGED_NEW_AREA")
	Advance(5.1)
	check(lastEvent("zone").zone == "Westfall" and me.zoneTime.Westfall >= 3, "a new zone is discovered; time per zone counts")
	ZONE = "Elwynn Forest"
	Fire("ZONE_CHANGED_NEW_AREA")
	Advance(1.1)

	friendsOnline()
	mark = #GAMEDATA + 1
	MONEY = MONEY + 1500000
	Fire("PLAYER_MONEY")
	MONEY = MONEY - 2000
	Fire("PLAYER_MONEY")
	check(me.stats.moneyIn == 1500000 and me.stats.moneyOut == 2000 and me.stats.maxMoney == 1552000, "gold earned, spent, most at once")
	check(lastEvent("gold") and lastEvent("gold").gold == 100, "milestone: 100 gold")
	Advance(1.2)
	check(sentTo(11, mark, "E2;")[1] == "E2;gold;100;", "shared")

	friendsOnline()
	mark = #GAMEDATA + 1
	Fire("CHAT_MSG_LOOT", "You receive loot: " .. ItemLink(1155) .. ".", "Lefthy")
	Fire("CHAT_MSG_LOOT", "You receive loot: " .. ItemLink(2075) .. "x3.", "Lefthy")
	Fire("CHAT_MSG_LOOT", "Anna receives loot: " .. ItemLink(19019) .. ".", "Anna")
	Fire("CHAT_MSG_LOOT", SECRET, "Lefthy")
	Fire("CHAT_MSG_LOOT", "You receive item: " .. ItemLink(19019) .. ".", "Lefthy")
	check(me.stats.loot3 == 1 and me.stats.loot2 == 3 and me.stats.loot4 == 1, "my loot by quality (x3 counts three), not others'")
	check(lastEvent("loot").name == "Thunderfury" and lastEvent("loot").quality == 5 and lastEvent("loot").icon == 20019,
		"blue and better loot goes in the journal, with its icon")
	Advance(1.2)
	check(sentTo(11, mark, "E2;")[1] == "E2;loot;Thunderfury;5", "epic and better loot is shared")

	Fire("NEW_MOUNT_ADDED", 6)
	Fire("NEW_PET_ADDED", "BattlePet-0-1")
	Fire("NEW_TOY_ADDED", 44606)
	Fire("ACHIEVEMENT_EARNED", 6, false)
	Fire("ACHIEVEMENT_EARNED", 7, true) -- earned on another character before
	check(me.stats.mounts == 1 and me.stats.pets == 1 and me.stats.toys == 1 and me.stats.achievements == 1
		and lastEvent("mount").name == "Brown Horse" and lastEvent("pet").name == "Black Kingsnake"
		and lastEvent("toy").name == "Toy Train Set" and lastEvent("achievement").name == "Level 20", "collections and achievements")

	local jumps = me.stats.jumps
	JumpOrAscendStart()
	JumpOrAscendStart()
	TRAVEL.swimming = true
	JumpOrAscendStart()
	TRAVEL.swimming = false
	check(me.stats.jumps == jumps + 2 and JUMPS >= 3, "jumps (swimming up doesn't count)")

	local walked, ridden = me.stats.walked, me.stats.ridden
	for i = 1, 6 do PLAYER_POS = { 0.5 + i * 0.005, 0.5 }; Advance(1) end -- 5 yd a second
	check(me.stats.walked - walked >= 20 and me.stats.walked - walked <= 31, "distance on foot, got " .. (me.stats.walked - walked))
	TRAVEL.mounted = true
	for i = 1, 4 do PLAYER_POS = { 0.53 + i * 0.01, 0.5 }; Advance(1) end
	TRAVEL.mounted = false
	check(me.stats.ridden - ridden >= 30, "riding")
	local flights = me.stats.flights
	TRAVEL.taxi = true
	for i = 1, 3 do PLAYER_POS = { 0.57, 0.5 - i * 0.03 }; Advance(1) end
	TRAVEL.taxi = false
	check(me.stats.flights == flights + 1 and me.stats.flown >= 50, "flight paths and their distance")
	-- The Martin tracker: time AFK (the flag, read on the tick), how often, the longest stretch.
	local afkBefore, timesBefore, longestBefore = me.stats.afk, me.stats.afkTimes, me.stats.longestAfk
	STATE.afk = true
	Advance(30)
	STATE.afk = false
	Advance(2)
	STATE.afk = true
	Advance(10)
	STATE.afk = false
	Advance(2)
	check(math.abs(me.stats.afk - afkBefore - 40) <= 2 and me.stats.afkTimes == timesBefore + 2
		and math.abs(me.stats.longestAfk - math.max(longestBefore, 30)) <= 1.5,
		"AFK time counted: 40 s in two stretches, the longest kept (earlier tests were AFK longer), got "
		.. me.stats.afk - afkBefore .. ", " .. me.stats.afkTimes - timesBefore .. ", " .. me.stats.longestAfk)
	check(math.abs(CH.Session().afk - (me.stats.afk - me.session.stats.afk)) < 0.01 and CH.Session().afk >= 39, "and per session")
	check((me.daily[date("%Y-%m-%d")].afk or 0) >= 39, "and per day (for the graphs)")
	walked = me.stats.walked
	PLAYER_POS = { 0.95, 0.95 } -- hearthstone
	Advance(1.1)
	check(me.stats.walked == walked, "a teleport isn't travel")
	PLAYER_POS = { 0.5, 0.5 }
	Advance(1.1)

	PROFESSIONS = { { name = "Mining", level = 70 } }
	Fire("SKILL_LINES_CHANGED")
	Advance(1.1)
	check(lastEvent("profession") and lastEvent("profession").name == "Mining" and not lastEvent("profession").level, "a new profession")
	friendsOnline()
	mark = #GAMEDATA + 1
	PROFESSIONS[1].level = 76
	Fire("SKILL_LINES_CHANGED")
	Advance(1.1)
	check(lastEvent("profession").level == 75, "profession milestone: 75")
	Advance(1.2)
	check(sentTo(11, mark, "E2;")[1] == "E2;profession;Mining;75", "shared")
	PROFESSIONS = {}

	local xp = me.stats.xp
	XP.current = 1800
	Fire("PLAYER_XP_UPDATE")
	PLAYER_LEVEL, XP.current = 20, 200
	Fire("PLAYER_XP_UPDATE")
	check(me.stats.xp == xp + 300 + 4400, "experience, also across a level-up, got " .. (me.stats.xp - xp))
	PLAYER_LEVEL = 19
	Fire("TIME_PLAYED_MSG", 360000, 3600)
	check(me.playedTotal == 360000, "what /played said is kept")

	local session = CH.Session()
	check(session.levels >= 2 and session.quests >= 3 and session.deaths >= 1 and session.money == 1498000,
		"this session: levels, quests, deaths, gold")
	pmark = #PRINTED + 1
	SlashCmdList.LEFTHYTOOLS_CHRONICLE("session")
	check(printedSince(pmark):find("this session: ", 1, true), "/chronicle session")
end

section("Chronicle: friends")
do
	anna("H2") -- Anna is around (and known by name) again
	Advance(1.2)
	local feed = CDB.friends
	local before = #feed
	pmark = #PRINTED + 1
	Advance(60) -- a fresh highlight window for Anna
	anna("E2;boss;Hogger;Elwynn Forest")
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "E2;hack;x;y", "WHISPER", 11)
	check(#feed == before, "nothing recorded inside the event handler")
	Advance(0.15)
	check(#feed == before + 1 and feed[#feed].k == "boss" and feed[#feed].name == "Anna" and feed[#feed].a == "Hogger",
		"a friend's highlight goes into the feed (unknown kinds are dropped)")
	check(printedSince(pmark):find("Anna|r defeated Hogger (Elwynn Forest).", 1, true), "with a chat line")
	for i = 1, 10 do anna("E2;rare;Rare" .. i .. ";Duskwood") end
	Advance(0.15)
	check(#feed == before + 10, "at most 10 highlights a minute from one friend, got " .. (#feed - before))
	Advance(60)
	pmark = #PRINTED + 1
	anna("E2;quest;The Defias Brotherhood;")
	anna("E2;zone;Westfall;")
	Advance(0.15)
	check(feed[#feed - 1].k == "quest" and feed[#feed].k == "zone" and feed[#feed].a == "Westfall"
		and not printedSince(pmark):find("Westfall", 1, true) and not printedSince(pmark):find("Defias", 1, true),
		"friends' quests and new zones go into the feed, not into chat")
	QUESTS = { { id = 500, title = "The Defias Brotherhood", objectives = {} } }
	mark = #GAMEDATA + 1
	Fire("QUEST_TURNED_IN", 500, 0, 0)
	Advance(1.2)
	check(sentTo(11, mark, "E2;quest;")[1] == "E2;quest;The Defias Brotherhood;", "my quests go to my friends' feeds")
	QUESTS = {}
	anna("Q2") -- she switches Beacon off (or logs off)
	Advance(0.15)
	check(feed[#feed].k == "offline" and feed[#feed].name == "Anna", "a friend going offline is in the feed")
	local dmark = #GAMEDATA + 1
	me.daily["2030-05-15"].afk = 600 -- 10 minutes AFK today
	anna("H2")
	Advance(1.2)
	check(feed[#feed].k == "online" and feed[#feed].name == "Anna", "and coming back online")
	Advance(2)
	local days = sentTo(11, dmark, "D2;")
	check(#days >= 1 and days[#days]:find("^D2;20300515;%d+;%d+;%d+;%d+;%d+;%d+$"),
		"a friend who shows up gets my last days for their graphs, got " .. table.concat(days, " | "))
	check(sentTo(11, dmark, "K2;")[1] == "K2;20300515;10", "... and each day's AFK time, in a message of its own (older builds ignore it)")
	do -- back again soon (a /reload): she has the week, only today goes
		local feedWas = #feed
		anna("Q2")
		Advance(0.15)
		local again = #GAMEDATA + 1
		anna("H2")
		Advance(3.2)
		local sent = sentTo(11, again, "D2;")
		check(#sent == 1 and sent[1]:find("^D2;20300515;") and #sentTo(11, again, "K2;") == 1,
			"a friend back within 10 minutes: only today, not the whole week again, got " .. table.concat(sent, " | "))
		while #feed > feedWas do table.remove(feed) end -- (her offline and online lines: the later checks count on her news)
	end
	anna("D2;20300514;90;5000;3;20;1;1")
	anna("K2;20300514;45")
	anna("D2;20300515;30;1200;2;8;0;0")
	anna("D2;2030051;1;1;1;1;1;1")
	anna("D2;20300513;2000;1;1;1;1;1") -- more minutes than a day has
	anna("K2;20300512;9999")
	Advance(0.15)
	local annaStats = CDB.friendStats.Anna
	check(annaStats and annaStats.days["2030-05-14"].played == 5400 and annaStats.days["2030-05-14"].xp == 5000
		and annaStats.days["2030-05-15"].quests == 2 and not annaStats.days["2030-05-13"] and annaStats.classFile == "MAGE",
		"and I keep theirs (malformed days are dropped)")
	check(annaStats.days["2030-05-14"].afk == 2700 and not annaStats.days["2030-05-12"], "their AFK time joins the day")
	annaStats.days["2030-05-14"].played = nil -- (to see it written again)
	anna("D2;20300514;90;5000;3;20;1;1") -- the day again, later
	Advance(0.15)
	check(annaStats.days["2030-05-14"].played == 5400 and annaStats.days["2030-05-14"].afk == 2700, "the day sent again keeps its AFK time")
	dmark = #GAMEDATA + 1
	for _ = 1, 11 do -- 5 minutes; she keeps sending her heartbeat meanwhile
		anna("S2;;0;260.0;750.0;Goldshire;")
		Advance(30)
	end
	check(sentTo(11, dmark, "D2;20300515;")[1], "today's numbers go out again every 5 minutes while they change")
	Advance(15)
	anna("L2;24;")
	Advance(0.15)
	check(feed[#feed].k == "level" and feed[#feed].level == 24, "friends' level-ups land in the feed too")
	REGISTERED_SETTINGS.LefthyTools_chronicle_friendsChat:SetValue(false)
	Advance(60)
	pmark = #PRINTED + 1
	anna("E2;mount;Brown Horse;")
	Advance(0.15)
	check(feed[#feed].k == "mount" and not printedSince(pmark):find("new mount", 1, true), "'show in chat' off: only the feed")
	REGISTERED_SETTINGS.LefthyTools_chronicle_friendsChat:SetValue(true)
	REGISTERED_SETTINGS.LefthyTools_chronicle_share:SetValue(false)
	mark = #GAMEDATA + 1
	Fire("NEW_MOUNT_ADDED", 6)
	Advance(1.2)
	check(#sentTo(11, mark, "E2;") == 0, "'share highlights' off: nothing sent")
	REGISTERED_SETTINGS.LefthyTools_chronicle_share:SetValue(true)
end

section("Chronicle: window")
do
	lefthy("chronicle")
	local win = LefthyToolsChronicleFrame
	check(win and win:IsShown() and win.Tabs.timeline and not win.Tabs.timeline:IsEnabled(), "/lefthy chronicle opens it on the timeline")
	local text = win.Text:GetText()
	for _, expected in ipairs({ "|cffffd2002030-05-15|r", "Level 23 - Elwynn Forest (took 1m)", "Died to Hogger - Elwynn Forest - Goldshire (level 19)",
			"Defeated Edwin VanCleef (The Deadmines)", "Killed the rare Mor'Ladim - Elwynn Forest", "First visit: The Deadmines",
			"Discovered Westfall", "10 quests completed", "Reached 100 gold", "Looted " .. ItemLink(19019), "New mount: Brown Horse",
			"Achievement: Level 20", "Mining: skill 75", "Learned Mining" }) do
		check(text:find(expected, 1, true), "timeline: " .. expected)
	end
	check(text:find("New mount: Brown Horse", 1, true) < text:find("Learned Mining", 1, true), "newest first")
	win.Tabs.stats:Click()
	local labels, values = win.Text:GetText(), win.Values:GetText()
	local function lines(s) local n = 1 for _ in s:gmatch("\n") do n = n + 1 end return n end
	check(lines(labels) == lines(values), "statistics: labels and values line up")
	for _, expected in ipairs({ "This session", "Killing blows", "Deadliest foe", "Rare elites killed", "Bosses defeated", "Dungeon runs",
			"Favourite zone", "On foot", "Flight paths", "Jumps", "Most gold at once", "Epic items", "Mounts", "Time played (/played)",
			"Martin tracker", "Time AFK", "Share of time played", "Times AFK", "Longest AFK", "AFK this session", "Verdict" }) do
		check(labels:find(expected, 1, true), "statistics: " .. expected)
	end
	check(values:find("Hogger (1)", 1, true) and values:find("100h 0m", 1, true) == nil and values:find("4d 4h", 1, true),
		"values: deadliest foe, /played as days and hours")
	local verdicts = { "Always there", "Takes a break now and then", "Coffee enthusiast", "Practically Martin" }
	local verdict
	for _, v in ipairs(verdicts) do if values:find(v, 1, true) then verdict = v end end
	check(verdict and labels:find("Martin tracker", 1, true), "the Martin tracker, with a verdict: " .. tostring(verdict))
	check(not win.Tabs.stats:IsEnabled() and win.Tabs.timeline:IsEnabled(), "the open page's button is greyed out")
	win.Tabs.friends:Click()
	local friendsPage = win.Text:GetText()
	check(friendsPage:find("Anna|r: ", 1, true) and friendsPage:find("Defeated Hogger (Elwynn Forest)", 1, true),
		"friends: their highlights")
	check(friendsPage:find("|cffffd200Online now|r\n|cff40c7ebAnna|r  |cffccccccLevel 20", 1, true)
		and friendsPage:find("Came online", 1, true) and friendsPage:find("Completed The Defias Brotherhood", 1, true)
		and friendsPage:find("Discovered Westfall", 1, true),
		"friends: who's online now and what they're doing, then what happened, got\n" .. friendsPage)
	me.daily[date("%Y-%m-%d", time() - 86400)] = { played = 3600, xp = 5000, quests = 3, kills = 20, deaths = 0, afk = 900 }
	me.daily[date("%Y-%m-%d", time() - 20 * 86400)] = { played = 99, xp = 1, quests = 1, kills = 1, deaths = 0 }
	local draws, draw = 0, CH.Graphs.Draw
	CH.Graphs.Draw = function(...) draws = draws + 1; return draw(...) end
	win.Tabs.graphs:Click()
	local canvas = win.Canvas
	local function hoverWith(title)
		for i = 1, canvas.used.hover do
			local f = canvas.pools.hover[i]
			if f.lines[1] == title then return f end
		end
	end
	local function drawnText(text)
		for i = 1, canvas.used.text do if canvas.pools.text[i]:GetText() == text then return true end end
	end
	check(draws == 1 and win.Text:GetText() == "" and not win.Tabs.graphs:IsEnabled() and canvas.used.tex > 30,
		"the Graphs page draws its cards")
	do
		local scratch = CH.Graphs.NewCanvas(CreateFrame("Frame"))
		local bar = scratch:Bar(0, 0, 10, 10, { 1, 0, 0 })
		scratch:Reset()
		local rect = scratch:Rect(0, 0, 5, 5, 0.2, 0.2, 0.2, 1)
		check(rect == bar and not rect.gradient and rect.color[1] == 0.2,
			"a texture that was a bar and is now a plain rectangle loses the bar's gradient")
	end
	local yesterday = hoverWith(date("%Y-%m-%d", time() - 86400))
	check(yesterday and yesterday.lines[2] == "Time: 1h 0m" and not hoverWith(date("%Y-%m-%d", time() - 20 * 86400)),
		"last 14 days: a bar per day with its value on hover (older days aren't shown)")
	yesterday._scripts.OnEnter(yesterday)
	check(TOOLTIP.shown and TOOLTIP.title == yesterday.lines[1] and tooltipHas("Time: 1h 0m"), "hovering a bar shows it")
	yesterday._scripts.OnLeave(yesterday)
	local xpButton -- the metric buttons live on the page
	for _, child in ipairs(win.Content._children) do if child:GetText() == "Experience" then xpButton = child end end
	xpButton:Click()
	check(not xpButton:IsEnabled() and hoverWith(date("%Y-%m-%d", time() - 86400)).lines[2] == "Experience: 5000",
		"switching the 14-day chart to experience")
	local afkButton
	for _, child in ipairs(win.Content._children) do if child:GetText() == "Time AFK" then afkButton = child end end
	afkButton:Click()
	local afkNote
	for i = 1, canvas.used.text do
		local text = canvas.pools.text[i]:GetText() or ""
		if text:find("^Time AFK: ") then afkNote = text end
	end
	check(hoverWith(date("%Y-%m-%d", time() - 86400)).lines[2] == "Time AFK: 15m" and afkNote and afkNote:find("% of time played)", 1, true),
		"the Martin tracker on the graphs: AFK per day, and its share of the time played, got " .. tostring(afkNote))
	xpButton:Click()
	check(canvas.used.line >= 2 and drawnText("This session"), "this session: an XP curve")
	local level22 = hoverWith("Level 22")
	check(level22 and level22.lines[2] == "1m", "time per level: a bar per level")
	check(drawnText("Elwynn Forest") and drawnText("Hogger"), "favourite zones and deadliest foes")
	check(hoverWith("On foot") and hoverWith("Epic items"), "travel and loot split bars")
	draws = 0
	Fire("PARTY_KILL", "Player-1-0", "Creature-0-100")
	Advance(2.2)
	check(draws == 0, "a change doesn't redraw the graphs right away")
	Advance(10)
	check(draws == 1, "but within 10 s (at most once)")
	CH.Graphs.Draw = draw
	CDB.chars["Alty-Realmy"] = { name = "Alty", realm = "Realmy", classFile = "MAGE", level = 12,
		events = { { t = time(), k = "level", level = 12 } } }
	-- The picker: our own dropdown (a Blizzard menu opened from addon code taints gamepad mode).
	local picker = win.Picker
	picker.GetText = function(self) return self.Label:GetText() end
	picker.Pick = function(self, name) -- open it and click the entry with that name
		self:Click()
		for i = 1, self.List.count do
			local row = self.List.rows[i]
			if row.kind == "entry" and row.Text:GetText():find(name, 1, true) then row:Click() return end
		end
		error("no entry " .. name)
	end
	check(picker._kind == "Button" and not picker._template, "the picker is a plain button of ours, not Blizzard's DropdownButton")
	local built = picker.List.builds
	Advance(12)
	check(picker.List.builds == built, "its list isn't built on refreshes, only when it opens")
	picker:Click()
	local menu = {}
	for i = 1, picker.List.count do
		local row = picker.List.rows[i]
		menu[#menu + 1] = row.kind == "divider" and "-" or row.Text:GetText():match("|c%x%x%x%x%x%x%x%x(%a+)|r")
	end
	check(picker.List:IsShown() and table.concat(menu, ",") == "Characters,Lefthy,Alty,-,Friends,Anna",
		"a click opens the list: my characters (this one first), then friends who sent their days, got " .. table.concat(menu, ","))
	check(picker.List.rows[2].Check.shown and not picker.List.rows[3].Check.shown and not picker.List.rows[1]._mouseEnabled,
		"the picked one is ticked; headings can't be clicked")
	picker.List:GetScript("OnEvent")(picker.List, "GLOBAL_MOUSE_DOWN")
	check(not picker.List:IsShown(), "a click elsewhere closes it")
	check(picker:GetText():find("Lefthy|r  |cffccccccLevel ", 1, true), "it shows who's picked")
	for i = 1, 24 do CDB.friendStats["Friend" .. i] = { classFile = "MAGE", level = 10, days = { [date("%Y-%m-%d")] = { played = 60 } } } end
	picker:Click()
	local _, _, _, lastX = picker.List.rows[picker.List.count]:GetPoint(1)
	check(picker.List.count > 18 and lastX > 200 and picker.List:GetWidth() >= 480,
		"a long list goes on in a second column (every row stays on screen), got x " .. tostring(lastX))
	picker.List:Hide()
	for i = 1, 24 do CDB.friendStats["Friend" .. i] = nil end
	picker:Click()
	picker:Hide() -- (its window closing hides it)
	picker:Show()
	check(not picker.List:IsShown(), "the window closing closes the list: it doesn't come back open")
	-- Pooled textures: a gradient (bars, the session curve's fill) never stays on a plain rectangle.
	local function strayGradients()
		local n = 0
		for i = 1, canvas.used.tex do
			local t = canvas.pools.tex[i]
			if t.gradient and not t.hasGradient then n = n + 1 end
		end
		return n
	end
	check(drawnText("This session") and strayGradients() == 0, "my graphs, with the session curve")
	picker:Pick("Alty")
	check(not drawnText("This session") and drawnText("|cff888888Level up once with Chronicle on to see this.|r")
		and picker:GetText():find("Alty", 1, true), "another character's graphs: no session, and a hint where there's no data yet")
	check(strayGradients() == 0, "no bar or curve gradient left on the textures they reused, got " .. strayGradients())
	picker:Pick("Anna")
	local function drawnContaining(text)
		for i = 1, canvas.used.text do if (canvas.pools.text[i]:GetText() or ""):find(text, 1, true) then return true end end
	end
	check(picker:GetText():find("Anna|r  |cffccccccLevel 20|r  |cff80c0ff(friend)", 1, true) and drawnText("Last 7 days")
		and drawnText("You and Anna, last 7 days") and drawnText("2h 0m") and drawnContaining("Completed The Defias Brotherhood"),
		"a friend's graphs: their days, their week, you and them, their latest news")
	local annaDay = hoverWith(date("%Y-%m-%d", time() - 86400))
	check(annaDay and annaDay.lines[2]:find("5000", 1, true), "their 14 days, from what they sent, got " .. tostring(annaDay and annaDay.lines[2]))
	check(drawnText("Time AFK") and drawnText("45m"), "... their AFK time too: a tile for the week and a row next to mine")
	win.Tabs.timeline:Click()
	check(picker:GetText():find("Lefthy", 1, true), "friends only have graphs: other pages show your own characters")
	win.Tabs.graphs:Click()
	check(picker:GetText():find("Lefthy", 1, true), "back on the Graphs page: still your own character")
	win.Tabs.timeline:Click()
	picker:Pick("Anna")
	check(not win.Tabs.graphs:IsEnabled() and picker:GetText():find("Anna", 1, true) and drawnText("Last 7 days"),
		"picking a friend on another page opens their graphs")
	win.Tabs.friends:Click()
	check(not picker:IsShown(), "the Friends page has no dropdown")
	win.Tabs.timeline:Click()
	check(picker:IsShown(), "the others do")
	picker:Pick("Alty")
	check(picker:GetText():find("Alty", 1, true) and win.Text:GetText():find("Level 12", 1, true), "your other characters' journals")
	win.Tabs.stats:Click()
	check(win.Values:GetText() ~= "" and not win.Text:GetText():find("This session", 1, true), "and their statistics (no session)")
	win.Tabs.timeline:Click()
	picker:Pick("Lefthy")
	check(picker:GetText():find("Lefthy", 1, true) and win.Text:GetText():find("Level 20", 1, true), "back to this character")
	local redraws, setBody = 0, win.SetBodyText
	win.SetBodyText = function(...) redraws = redraws + 1; return setBody(...) end
	Advance(1.1)
	Fire("PARTY_KILL", "Player-1-0", "Creature-0-99")
	Advance(3)
	check(redraws == 0, "a kill changes a counter, not the timeline: no redraw, got " .. redraws)
	Fire("NEW_TOY_ADDED", 1)
	Advance(1.1)
	check(redraws == 1 and win.Text:GetText():find("New toy: Toy Train Set", 1, true), "the open window follows new entries within a second")
	win.SetBodyText = setBody
	win:Hide()
	check(BINDING_NAME_LEFTHYTOOLS_CHRONICLE_TOGGLE == "Chronicle: open or close the journal", "a key binding")
	LT:GetModule("chronicle"):Toggle()
	check(win:IsShown(), "the key binding opens it")
	LT:GetModule("chronicle"):Toggle()
	check(not win:IsShown(), "and closes it")
	afk(true)
	Advance(1.1)
	check(LefthyToolsAFKFrame.Info:GetText():find("This session: ", 1, true), "the AFK screen shows the session")
	afk(false)
	Advance(0.3)
	for _ = 1, 1100 do Fire("NEW_TOY_ADDED", 1) end
	check(#me.events == 1000, "at most 1000 entries per character, got " .. #me.events)
	lefthy("disable chronicle")
	local quests = me.stats.quests
	local ticks = CH.ticks
	Fire("QUEST_TURNED_IN", 1, 0, 0)
	Advance(3)
	check(me.stats.quests == quests and CH.ticks == ticks, "switched off: nothing recorded, nothing runs")
	lefthy("enable chronicle")
	check(me.stats.sessions == 1, "switching it back on continues the session")
	Advance(1.1)
	lefthy("disable chronicle")
	me.session.last = time() - 3 * 86400 -- as if it was off at login and the session is from days ago
	local longest = me.stats.longestSession
	lefthy("enable chronicle")
	Advance(1.1)
	check(me.stats.sessions == 2 and CH.Session().played < 5 and me.stats.longestSession == longest,
		"switched on long after the last session: a new one, not the old one going on for days")
	lefthy("disable chronicle")
	me.session.last, me.session.start = nil, time() - 3 * 86400 -- from a version that didn't stamp it yet
	lefthy("enable chronicle")
	Advance(1.1)
	check(me.stats.sessions == 3 and CH.Session().played < 5 and me.stats.longestSession == longest,
		"a session without the stamp goes by its start: days old, so a new one")

	-- The minimap button.
	local mmb = CH.MinimapButton()
	check(mmb and mmb:IsShown() and mmb:GetParent() == Minimap and CH.module.db.minimapButton == true,
		"a minimap button, on by default")
	local _, _, _, bx, by = mmb:GetPoint(1)
	check(math.abs(math.sqrt(bx * bx + by * by) - 75) < 0.01 and bx < 0 and by < 0, "on the minimap's edge, lower left")
	local journal = LefthyToolsChronicleFrame
	journal:Hide()
	mmb:Click("LeftButton")
	check(journal:IsShown(), "click: the journal opens")
	mmb:Click("LeftButton")
	check(not journal:IsShown(), "click again: it closes")
	mmb:Click("RightButton")
	check(OPENED_CATEGORY == CH.module.category:GetID(), "right-click: Chronicle's settings")
	mmb._scripts.OnEnter(mmb)
	check(TOOLTIP.title == "Chronicle" and (TOOLTIP.lines[1] or ""):find("^This session: ")
		and tooltipHas("Click: open or close the journal") and tooltipHas("Right-click: settings"),
		"hovering: this session and what the clicks do")
	mmb._scripts.OnLeave(mmb)
	Minimap._centerX, Minimap._centerY = 500, 500
	CURSOR.x, CURSOR.y = 500, 640 -- straight above the minimap
	mmb._scripts.OnDragStart(mmb)
	Advance(0.05)
	mmb._scripts.OnDragStop(mmb)
	_, _, _, bx, by = mmb:GetPoint(1)
	check(CH.module.db.minimapAngle == 90 and math.abs(bx) < 0.01 and math.abs(by - 75) < 0.01 and not mmb._scripts.OnUpdate,
		"dragging moves it along the edge, saved; nothing runs once dropped")
	mmb._scripts.OnDragStart(mmb)
	check(mmb._scripts.OnUpdate, "dragging again")
	mmb._scripts.OnHide(mmb) -- the minimap hidden mid-drag (Mirage, the minimap key): no OnDragStop
	check(not mmb._scripts.OnUpdate, "hidden mid-drag: it stops following the cursor")
	lefthy("chronicle minimap")
	Advance(0.05)
	check(not mmb:IsShown() and CH.module.db.minimapButton == false, "/chronicle minimap hides it")
	lefthy("chronicle minimap")
	Advance(0.05)
	check(mmb:IsShown(), "and shows it again")
	lefthy("disable chronicle")
	Advance(0.05)
	check(not mmb:IsShown(), "Chronicle off: no button")
	lefthy("enable chronicle")
	Advance(0.05)
	check(mmb:IsShown(), "on again: back")
end

section("Chronicle: a broken tick doesn't run every frame")
do
	local C = ns.Chronicle
	local c = C.Store().chars["Lefthy-Realmy"]
	local ticks, played = C.ticks, c.stats.played
	local onTick = C.OnTick
	C.OnTick = function() error("a broken redraw") end
	for _ = 1, 180 do pcall(Advance, 1 / 60) end
	C.OnTick = onTick
	check(C.ticks - ticks <= 4 and c.stats.played - played <= 4,
		"an error in the tick: still once a second, no time made up, got " .. (C.ticks - ticks) .. " ticks")
	-- Levelled while Chronicle was off: the new level's time doesn't count from the old level's start.
	c.level, c.levelStart, c.levelFrom = PLAYER_LEVEL - 1, c.stats.played - 100, { kills = 0, quests = 0 }
	C.Store().friendStats.Gone = { classFile = "MAGE", level = 10, days = { ["2020-01-01"] = { played = 60 } } }
	lefthy("disable chronicle")
	Advance(0.3)
	lefthy("enable chronicle")
	Advance(0.3)
	check(c.level == PLAYER_LEVEL and c.levelStart == nil and c.levelFrom == nil, "a level-up Chronicle missed: that level's start is unknown")
	check(not C.Store().friendStats.Gone, "a friend whose days have all run out leaves the dropdown")
	c.levelStart, c.levelFrom = c.stats.played - 50, { kills = 0, quests = 0 } -- (the level-up window's tests time this level)
	-- A quest hub doesn't use up friends' highlight budget: at most 5 feed-only shares a minute.
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "H2", "WHISPER", 11)
	Advance(1.2)
	local savedQuests = QUESTS
	QUESTS = {}
	for i = 1, 8 do QUESTS[i] = { id = 7000 + i, title = "Hub quest " .. i, objectives = {} } end
	local mark = #GAMEDATA + 1
	for i = 1, 8 do Fire("QUEST_TURNED_IN", 7000 + i, 100) end
	INSTANCE = { name = "The Deadmines", type = "party" }
	Fire("ENCOUNTER_END", 3, "Mr. Smite", 1, 5, 1)
	INSTANCE = nil
	Advance(1.5)
	local questShares, bossShared = 0, false
	for _, m in ipairs(GameDataTo(11, mark)) do
		if m:find("^E2;quest;") then questShares = questShares + 1 end
		if m:find("^E2;boss;Mr. Smite") then bossShared = true end
	end
	check(questShares == 5 and bossShared, "8 quests in a minute: 5 go to friends' feeds, the boss after them still goes, got " .. questShares)
	QUESTS = savedQuests
	-- Days by the calendar (stepping 86400 s skips or repeats one around a daylight saving change).
	local days, ok = {}, true
	for i = 0, 13 do days[i] = date("%Y-%m-%d", C.DayAgo(i)) end
	for i = 1, 13 do
		local t = date("*t", C.DayAgo(i - 1))
		ok = ok and days[i] == date("%Y-%m-%d", time({ year = t.year, month = t.month, day = t.day - 1, hour = 12 }))
	end
	check(ok and days[0] == date("%Y-%m-%d"), "14 days back, each the calendar day before the next")
	-- A friend's day from the future (a wrong clock) isn't kept: it would never be pruned.
	anna("D2;20990101;10;100;1;1;0;0")
	anna("D2;" .. date("%Y%m%d") .. ";11;100;1;1;0;0")
	Advance(1.5)
	local annaStats = C.Store().friendStats.Anna
	check(annaStats and annaStats.days[date("%Y-%m-%d")] and not annaStats.days["2099-01-01"],
		"a friend's day after tomorrow is ignored (today's is kept)")
	-- A session past midnight: the new day counts as a day played.
	local today = date("%Y-%m-%d")
	c.days[today], c.daily[today] = nil, nil
	Advance(1.1)
	check(c.days[today] == true, "a day the session runs into counts as played")
	-- A /reload mid-flight isn't another flight.
	local flights = c.stats.flights
	TRAVEL.taxi = true
	Advance(1.1)
	check(c.stats.flights == flights + 1, "taking off counts a flight")
	lefthy("disable chronicle")
	Advance(0.3)
	lefthy("enable chronicle")
	Advance(2.2)
	check(c.stats.flights == flights + 1, "a /reload in the air doesn't count another")
	TRAVEL.taxi = false
	Advance(1.1)
end

section("Beacon: leaving")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "Q2", "WHISPER", 12)
Advance(0.15)
check(not peers()[12] and peers()[11], "a friend switching Beacon off (Q2) is forgotten")
-- A reserved item at a vendor, then Beacon goes off (below).
local owedList = LefthyToolsDB.handover
BB.AddHandover("1155::::::::20:::::", ItemLink(1155), "Bob", "Player-1-12", 12)
BAGS[0] = { [3] = 1155 }
OpenBags()
Fire("MERCHANT_SHOW")
Advance(0.1)
local reservedButton = ContainerFrameCombinedBags.buttons[3]
check(reservedButton.LefthyToolsReserved:IsShown() and reservedButton.LefthyToolsSellGuard:IsShown(), "a reserved item at a vendor, Beacon on")
mark = #GAMEDATA + 1
MOCK_SEND_RESULT = 3 -- the server is throttling right now
local mapProviders = {} -- (Beacon's and others' on the world map)
for p in pairs(WorldMapFrame.providers) do mapProviders[p] = true end
lefthy("disable beacon")
check(#GameDataTo(11, mark) == 0, "switching off sends nothing inside the settings callback")
Advance(1)
check(#GameDataTo(11, mark) == 0, "throttled: the goodbye waits")
MOCK_SEND_RESULT = nil
Advance(3)
check(GameDataTo(11, mark)[1] == "Q2", "... and then tells friends (through the rate limiter, not lost)")
local providersLeft, providersGone = 0, 0
for p in pairs(mapProviders) do
	if WorldMapFrame.providers[p] then providersLeft = providersLeft + 1 else providersGone = providersGone + 1 end
end
check(providersGone == 2 and providersLeft == 1 and next(BB.GetMinimapPins()) == nil,
	"and removes the dots from both maps (its two map providers go, the quest map's stays)")
check(not reservedButton.LefthyToolsReserved:IsShown() and not reservedButton.LefthyToolsSellGuard:IsShown(),
	"and the reserved item's border and vendor question")
pmark = #PRINTED + 1
TRADE_PARTNER, PARTY.NPC = "Bob", { guid = "Player-1-12" }
Fire("TRADE_SHOW")
SendMailFrame:Show()
SendMailNameEditBox:SetText("")
MAIL_ITEMS = { 1155 }
Fire("MAIL_SEND_INFO_UPDATE")
BAGS[0][3] = nil
Fire("BAG_UPDATE_DELAYED")
Advance(0.1)
check(printedSince(pmark) == "" and SendMailNameEditBox:GetText() == "", "while off: no trade nudge, no mail help, no vendor warning, got " .. printedSince(pmark))
BAGS[0][3] = 1155
SendMailFrame:Hide()
MAIL_ITEMS, TRADE_PARTNER, PARTY.NPC = {}, nil, nil
mark = #GAMEDATA + 1
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "H2", "WHISPER", 11)
Advance(5)
check(#GameDataTo(11, mark) == 0, "while off: no answers, no positions")
local seenNewer = LT.newerVersion
LT.newerVersion = nil
check(updateStatus():find("Unknown (Beacon is off)", 1, true), "update status with Beacon off: unknown")
LT.newerVersion = seenNewer
lefthy("enable beacon")
Advance(0.15)
check(next(WorldMapFrame.providers) ~= nil, "on again: back on the map")
check(reservedButton.LefthyToolsReserved:IsShown() and reservedButton.LefthyToolsSellGuard:IsShown(),
	"and the reserved item's border and vendor question")
Fire("MERCHANT_CLOSED")
wipe(owedList)
BAGS = { [0] = {} }
CloseBags()
Advance(0.1)

section("Misc Tweaks: level-up window")
do
	local TDB = LefthyToolsDB.settings.tweaks
	local function T(id) return REGISTERED_SETTINGS["LefthyTools_tweaks_" .. id] end
	local LU = ns.LevelUp
	local function plain(s) return (tostring(s or "")):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
	local function shown() return LefthyToolsLevelUpFrame ~= nil and LefthyToolsLevelUpFrame:IsShown() end
	local function cells()
		local out = {}
		for _, c in ipairs(LefthyToolsLevelUpFrame.Cells) do
			if c.Label:IsShown() then out[c.Label:GetText()] = plain(c.Value:GetText()) end
		end
		return out
	end
	local function icons()
		local out = {}
		for _, b in ipairs(LefthyToolsLevelUpFrame.Icons) do if b:IsShown() and b.spell then out[#out + 1] = b end end
		return out
	end
	check(TDB.levelUp == true and T("levelUp") and SETTINGS_BUTTONS["Show the level-up window"], "on by default, with a checkbox and a preview button")
	if LefthyToolsLevelUpFrame then LefthyToolsLevelUpFrame:Hide() end

	-- A rogue goes from 19 to 20: base stats +1 Str, +2 Agi, +1 Sta, +0 Int, +1 Spi (Spirit: only the snapshot knows).
	PLAYER_LEVEL = 19
	LU.TakeSnapshot()
	PLAYER_LEVEL = 20
	STATS = { { 41, 46 }, { 62, 72 }, { 51, 59 }, { 25, 25 }, { 31, 33 } }
	local rogue20 = ns.CLASS_SPELLS.ROGUE[20]
	KNOWN_SPELLS[rogue20[1]] = true -- one of them already learned
	UNLOCKED_DUNGEONS[20] = { "Shadowfang Keep" }
	Fire("PLAYER_LEVEL_UP", 20, 30, 0, 1, 0, 1, 2, 1, 0)
	check(not shown(), "nothing inside the event")
	Advance(0.5)
	check(not shown(), "not right away: Blizzard's banner and fanfare first")
	Advance(1.2)
	local W = LefthyToolsLevelUpFrame
	check(shown() and W.Number:GetText() == 20 and W.Face.Portrait.portrait == "player", "1.5 s later: the window, with my portrait and level 20")
	check(W:GetAlpha() < 1 and W.NumberFrame.Punch.plays > 0 and W.TopBar.Grow.plays > 0, "it fades in, the gold bars grow and the number punches in")
	Advance(2)
	local c = cells()
	check(c.Health == "+30" and c.Strength == "45 > 46  +1" and c.Agility == "70 > 72  +2" and c.Spirit == "32 > 33  +1"
		and c.Intellect == "25" and c.Energy == nil, "stats counted up: old > new and the gain (Spirit too), health; no energy for a rogue")
	local list = icons()
	check(#list == #rogue20 - 1 and list[1].spell.id ~= rogue20[1], "the trainer's new spells for level 20, without the known one")
	local newOnes, ranked = 0, 0
	for _, b in ipairs(list) do
		if b.spell.rank then
			if b.Rank:GetText() == b.spell.rank then ranked = ranked + 1 end
		elseif b.New:GetText() == "NEW" then
			newOnes = newOnes + 1
		end
	end
	check(newOnes + ranked == #list and W:GetAlpha() == 1, "new spells marked NEW, upgrades with their rank")
	list[1]:GetScript("OnEnter")(list[1])
	check(TOOLTIP.spell == list[1].spell.id and TOOLTIP.shown, "hovering an icon shows the spell's tooltip")
	list[1]:GetScript("OnLeave")(list[1])
	local unlocks = plain(W.Unlocks:GetText())
	check(unlocks:find("+1 talent point", 1, true) and unlocks:find("Class quest: Poisons", 1, true)
		and unlocks:find("New dungeons: Shadowfang Keep", 1, true), "talent point, the rogue's poison quest and the new dungeon, got " .. unlocks)
	check(W.Took:IsShown() and W.Took:GetText():find("Level 19 took", 1, true), "how long level 19 took (Chronicle)")
	check(TDB.levelUps["Lefthy-Realmy"].level == 20 and TDB.levelUps["Lefthy-Realmy"].stats[5] == 1, "the gains are kept for the preview")
	local inList = false
	for _, name in ipairs(UISpecialFrames) do if name == "LefthyToolsLevelUpFrame" then inList = true end end
	check(inList, "Escape closes it")
	W._mouse = true
	Advance(30)
	check(shown(), "it stays while the mouse is on it")
	W._mouse = false
	Advance(26)
	check(not shown(), "and closes by itself after a while")

	-- In combat: it waits; a fight starting closes it.
	PLAYER_LEVEL = 21
	STATE.combat = true
	Fire("PLAYER_LEVEL_UP", 21, 31, 0, 1, 0, 1, 1, 1, 1)
	Advance(4)
	check(not shown(), "a level-up in combat: no window yet")
	STATE.combat = false
	Fire("PLAYER_REGEN_ENABLED")
	Advance(1.2)
	check(shown() and W.Number:GetText() == 21, "after the fight: there it is")
	STATE.combat = true
	Fire("PLAYER_REGEN_DISABLED")
	Advance(0.1)
	check(not shown(), "a fight starting closes it")
	STATE.combat = false

	-- Blizzard's level-up banner first.
	CreateFrame("Frame", "EventToastManagerFrame")
	Fire("PLAYER_LEVEL_UP", 21, 31, 0, 1, 0, 1, 1, 1, 1)
	Advance(3)
	check(not shown(), "while Blizzard's level-up banner is up: it waits")
	EventToastManagerFrame:Hide()
	Advance(0.6)
	check(shown(), "and comes once the banner is gone")
	_G.EventToastManagerFrame = nil
	W:Hide()

	-- The preview: the window for my current level.
	SETTINGS_BUTTONS["Show the level-up window"].onClick()
	check(shown() and W.Number:GetText() == 21 and plain(W.Tag:GetText()) == "Your last level-up, once more",
		"preview button: my level, my last gains")
	check(W.Close:IsShown() and W.Close._template == "UIPanelCloseButtonNoScripts", "with Blizzard's red X at the top")
	W:Hide()
	SlashCmdList.LEFTHYTOOLS_LEVELUP("")
	check(shown() and W.Number:GetText() == 21, "/levelup: the same, one quick command")
	Advance(2)
	check(cells().Strength == "45 > 46  +1" and cells().Spirit == "33",
		"... and its numbers: the event's own when the base stats didn't move (no Spirit gain then), got " .. tostring(cells().Spirit))
	W:Hide()
	wipe(TDB.levelUps)
	lefthy("tweaks levelup test")
	check(shown() and plain(W.Tag:GetText()):find("example", 1, true), "/lefthy tweaks levelup test, no level-up yet: example gains, said so")
	W:Hide()
	PLAYER_LEVEL = 20
	KNOWN_SPELLS[rogue20[2]] = true
	lefthy("tweaks levelup test")
	local known = 0
	for _, b in ipairs(icons()) do if b.spell.known and b.Icon.desaturated then known = known + 1 end end
	check(#icons() == #rogue20 and known == 2, "the preview lists every spell of the level, known ones greyed out")
	W:Hide()

	-- Talents: level 10 opens the first row of every tree; later, the next row of the tree with the most points.
	local function talentParts()
		local labels, list = {}, {}
		for _, l in ipairs(W.TalentLabels) do if l:IsShown() then labels[#labels + 1] = plain(l:GetText()) end end
		for _, b in ipairs(W.TalentIcons) do if b:IsShown() and b.talent then list[#list + 1] = b end end
		return labels, list
	end
	KNOWN_SPELLS = {}
	PLAYER_LEVEL = 10
	Fire("PLAYER_LEVEL_UP", 10, 20, 0, 1, 0, 1, 1, 1, 0)
	Advance(2)
	local labels, talentIcons = talentParts()
	check(shown() and W.TalentsTitle.Text:GetText() == "Talents unlocked" and #labels == 3 and labels[1]:find("Assassination", 1, true)
		and labels[3]:find("Subtlety", 1, true) and #talentIcons == 6, "level 10: the first row of every talent tree, got " .. #talentIcons .. " talents")
	talentIcons[1]:GetScript("OnEnter")(talentIcons[1])
	check(TOOLTIP.spell == 901011 and tostring(TOOLTIP.lines[1]):find("Talent in Assassination, row 1: up to 5 points", 1, true),
		"hovering one: the talent, its tree, row and points")
	talentIcons[1]:GetScript("OnLeave")(talentIcons[1])
	check(plain(W.Unlocks:GetText()):find("Talents unlocked: +1 talent point", 1, true), "and the first talent point")
	W:Hide()
	TALENT_SPENT[1] = 5
	PLAYER_LEVEL = 15
	Fire("PLAYER_LEVEL_UP", 15, 20, 0, 1, 0, 1, 1, 1, 0)
	Advance(2)
	labels, talentIcons = talentParts()
	check(W.TalentsTitle.Text:GetText() == "New talent row (row 2)" and #labels == 1 and labels[1]:find("Assassination", 1, true)
		and #talentIcons == 2 and talentIcons[1].talent.row == 2, "level 15: the second row of the tree with my points")
	W:Hide()
	-- A talent isn't the trainer's (like Templar's Bulwark), nor a rank of a talent I don't have.
	TALENT_SPENT[1] = 10
	PLAYER_LEVEL = 20
	TALENT_NODES[1031].spellID = rogue20[1]
	SPELL_NAMES[901032], SPELL_NAMES[rogue20[2]] = "Templar's Bulwark", "Templar's Bulwark"
	Fire("PLAYER_LEVEL_UP", 20, 30, 0, 1, 0, 1, 2, 1, 0)
	Advance(2)
	local listed = {}
	for _, b in ipairs(icons()) do listed[b.spell.id] = true end
	check(#icons() == #rogue20 - 2 and not listed[rogue20[1]] and not listed[rogue20[2]],
		"a talent's spell and a higher rank of a talent I don't have: not at the trainer")
	W:Hide()
	KNOWN_SPELLS[901032] = true
	lefthy("tweaks levelup test")
	listed = {}
	for _, b in ipairs(icons()) do listed[b.spell.id] = true end
	check(listed[rogue20[2]] and not listed[rogue20[1]], "with the talent, its next rank is at the trainer")
	W:Hide()
	TALENT_NODES[1031].spellID, SPELL_NAMES, KNOWN_SPELLS, TALENT_SPENT = 901031, {}, {}, { 0, 0, 0 }

	-- Pinned: it stays until closed, and steps aside during a fight.
	lefthy("tweaks levelup test")
	check(not W.pinned and W.Timer.shown, "a new window starts unpinned, with its timer line")
	W.Pin:Click()
	check(W.pinned and not W.Timer.shown, "the pin keeps it (no timer line)")
	Advance(30)
	check(shown(), "pinned: still there after 30 s")
	STATE.combat = true
	Fire("PLAYER_REGEN_DISABLED")
	check(not shown(), "a fight: it steps aside")
	Advance(2)
	STATE.combat = false
	Fire("PLAYER_REGEN_ENABLED")
	Advance(1.2)
	check(shown() and W.pinned and W:GetAlpha() == 1, "after the fight it's back, still pinned")
	STATE.combat = true
	Fire("PLAYER_REGEN_DISABLED")
	Fire("PLAYER_LEVEL_UP", PLAYER_LEVEL, 10, 0, 1, 0, 1, 1, 1, 1)
	Advance(2)
	STATE.combat = false
	Fire("PLAYER_REGEN_ENABLED")
	Advance(1.2)
	check(shown() and not W.pinned and W.Timer.shown, "a level-up during that fight: its window starts unpinned")
	W.Pin:Click() -- (pinned again for the arrows below)
	-- A buff that came between two levels isn't a gain: the base stats are what's compared.
	LU.TakeSnapshot()
	local spiritWas = STATS[5]
	STATS[5] = { spiritWas[1], spiritWas[2] + 8 }
	Fire("PLAYER_LEVEL_UP", PLAYER_LEVEL, 10, 0, 1, 0, 1, 1, 1, 1)
	Advance(3.5)
	check(cells().Spirit == tostring(spiritWas[2] + 8), "a buff since the last level isn't counted as a gain, got " .. tostring(cells().Spirit))
	STATS[5] = spiritWas
	W.Pin:Click()
	-- The arrows: what other levels bring.
	local level = W.Number:GetText()
	W.Next:Click()
	check(W.Number:GetText() == level + 1 and plain(W.Tag:GetText()):find("Coming up: what level " .. (level + 1), 1, true)
		and not W.StatsTitle.Text:IsShown(), "next level: what it brings, no stats")
	W.Prev:Click()
	W.Prev:Click()
	check(W.Number:GetText() == level - 1 and plain(W.Tag:GetText()):find("Looking back", 1, true), "and back")
	W.Close:Click()
	Advance(0.5)
	check(not shown() and not W.pinned, "closed: gone, and the next one starts unpinned")
	lefthy("tweaks levelup test")
	W:GetScript("OnDragStart")(W)
	W:GetScript("OnDragStop")(W)
	check(W.pinned, "moving it pins it")
	W:Hide()
	W.Next:Click()
	check(shown() and W.pinned, "browsing pins it too")
	W:Hide()

	T("levelUp"):SetValue(false)
	Advance(0.1)
	Fire("PLAYER_LEVEL_UP", 21, 31, 0, 1, 0, 1, 1, 1, 1)
	Advance(3)
	check(not shown(), "switched off: no window")
	T("levelUp"):SetValue(true)
	Advance(0.1)
	PLAYER_LEVEL, KNOWN_SPELLS, UNLOCKED_DUNGEONS = 19, {}, {}
	STATS = { { 40, 45 }, { 60, 70 }, { 50, 58 }, { 25, 25 }, { 30, 32 } }
end

section("what's new")
local news = ns.CHANGELOG
local MODULES = { mirage = true, tweaks = true, beacon = true, chronicle = true, general = true }
local goodData = #news > 0
for i, e in ipairs(news) do
	goodData = goodData and e.id == i and (e.version == nil or LT.ParseVersion(e.version) ~= nil) and MODULES[e.module]
	-- Lustre style: a version only once tagged, so no versioned entry after an unversioned one.
	goodData = goodData and not (e.version and i > 1 and news[i - 1].version == nil)
	for _, lang in ipairs({ e.en, e.de }) do
		goodData = goodData and type(lang) == "table" and type(lang[1]) == "string" and lang[1] ~= ""
			and type(lang[2]) == "string" and lang[2] ~= "" and #lang[1] <= 40
	end
end
check(goodData, "changelog: ids 1, 2, 3, ... in order, each with a tagged version (or none yet), a module, and a short title and a sentence in English and German")
check(LT.freshInstall and not (LefthyToolsNewsFrame and LefthyToolsNewsFrame:IsShown()),
	"a new install doesn't get a what's-new window")
LefthyToolsDB.changelogSeen = #news - 2 -- two entries arrived with an update
STATE.combat = true
LT.WhatsNew.Schedule()
Advance(4)
check(not (LefthyToolsNewsFrame and LefthyToolsNewsFrame:IsShown()), "not in combat")
STATE.combat = false
Advance(5)
local newsText = LefthyToolsNewsFrame and LefthyToolsNewsFrame.plain or ""
check(LefthyToolsNewsFrame and LefthyToolsNewsFrame:IsShown(), "after combat: the window opens by itself")
local function entryLine(e) return "- " .. e.en[1] .. ": " .. e.en[2] end -- (another entry's text may name a title)
check(newsText:find(entryLine(news[#news]), 1, true) and newsText:find(entryLine(news[#news - 1]), 1, true)
	and not newsText:find(entryLine(news[#news - 2]), 1, true), "only the entries not seen yet")
check(news[#news].version or newsText:sub(1, 29) == "LefthyTools 0.4.0-3-gabc1234\n",
	"entries since the last tagged version: under the installed build (no made-up version), got " .. newsText)
check(LefthyToolsDB.changelogSeen == #news, "and they count as seen")
check(LefthyToolsNewsFrame.Subtitle:GetText():find("0.4.0-3-gabc1234", 1, true), "the window shows the installed build")
LefthyToolsNewsFrame.AllButton:Click()
newsText = LefthyToolsNewsFrame.plain
check(newsText:find(news[1].en[1], 1, true) and not LefthyToolsNewsFrame.AllButton:IsShown(), "'All changes' shows everything")
local order = {}
local release = newsText:sub((newsText:find("LefthyTools 0.5.0", 1, true))) -- (newer versions come first)
for _, heading in ipairs({ "Mirage", "Misc Tweaks", "Beacon", "Chronicle", "General" }) do
	local _, count = release:gsub("\n" .. heading .. "\n", "")
	order[#order + 1] = count == 1 and release:find("\n" .. heading .. "\n", 1, true) or -1
end
check(order[1] > 0 and order[1] < order[2] and order[2] < order[3] and order[3] < order[4] and order[4] < order[5],
	"in a version: grouped by module, each heading once, in a fixed order, got\n" .. newsText)
check(newsText:find("LefthyTools 0.4.0-3-gabc1234", 1, true) < newsText:find("LefthyTools 0.5.0", 1, true),
	"the newest first: what came after the last tag, then the tagged versions")
check(newsText:find("\nBeacon\n- Friends in your group: ", 1, true) and newsText:find("- Level progress: ", 1, true),
	"each entry: a short title and a sentence")
local drawn = {}
for _, fs in ipairs(LefthyToolsNewsFrame.fontPool) do if fs:IsShown() then drawn[#drawn + 1] = fs:GetText() end end
local entryDrawn, bullets = false, 0
for _, text in ipairs(drawn) do
	if text == "Death alerts\n|cffbbbbbb" .. news[7].en[2] .. "|r" then entryDrawn = true end
	if text:find("•", 1, true) then bullets = bullets + 1 end
end
check(entryDrawn and bullets == #news and LefthyToolsNewsFrame.dividerPool[1]:IsShown(),
	"drawn as a heading with a divider, module headings, and a bullet, title and sentence per entry")
LefthyToolsNewsFrame:Hide()
lefthy("news")
check(LefthyToolsNewsFrame:IsShown() and LefthyToolsNewsFrame.plain:find(news[1].en[1], 1, true), "/lefthy news")
LefthyToolsNewsFrame:Hide()
SETTINGS_BUTTONS["What's new"].onClick()
check(LefthyToolsNewsFrame:IsShown(), "the settings overview's What's new button")
LefthyToolsNewsFrame:Hide()
Advance(10)
check(not LefthyToolsNewsFrame:IsShown(), "nothing new: it doesn't open again")

check(#ERRORS == 0, "no errors reported through the error handler")

-- A forgotten `local` leaks a global, which in game can clash with other addons. Ours start with
-- LefthyTools (incl. mixins); SLASH_/BINDING_ names and the tests' own MOCK_* knobs are all caps.
local leaked = {}
for k in pairs(_G) do
	if not globalsBefore[k] and type(k) == "string" and not k:match("^[A-Z][A-Z0-9_]*$") and not k:match("^LefthyTools") then
		leaked[#leaked + 1] = k
	end
end
table.sort(leaked)
check(#leaked == 0, "no accidental globals, found: " .. table.concat(leaked, ", "))
io.write(string.format("\n%d passed, %d failed\n", passes, failures))
if failures > 0 then error("tests failed") end
