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
check(errorRow():find("3 (type /lefthy errors)", 1, true), "the overview shows how many")
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
check(#LefthyToolsDB.errors == 0 and errorRow():find("None", 1, true), "/lefthy errors clear")
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
local AFK = ns.MirageAFK
local function afk(on) STATE.afk = on; Fire("PLAYER_FLAGS_CHANGED", "player") end
check(MDB.afkScreen and MDB.afkSpin and S("afkScreen") and S("afkSpin"), "settings, on by default")
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
S("afkSpin"):SetValue(false)
afk(true)
Advance(0.05)
check(afkScreen:IsShown() and not CAMERA.spinning, "camera circling off")
S("afkSpin"):SetValue(true)
lefthy("disable mirage")
Advance(0.05)
check(not afkScreen:IsShown() and UIParent:GetAlpha() == 1, "Mirage off while AFK: back")
afk(false)
S("afkScreen"):SetValue(false)
lefthy("enable mirage")
afk(true)
Advance(0.3)
check(not afkScreen:IsShown(), "AFK screen off: nothing")
afk(false)
S("afkScreen"):SetValue(true)
MDB.afkSpinning, CAMERA.spinning = true, true -- a /reload while the camera was circling
local stops = CAMERA.stops
lefthy("disable mirage")
lefthy("enable mirage")
check(CAMERA.stops == stops + 1 and not CAMERA.spinning and not MDB.afkSpinning, "after a reload mid-circle the camera is stopped")
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
lefthy("tweaks status")
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
Advance(6) -- 30 friends x (version + state) at 10 messages a second
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
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "V2;0.4.0-9-gbbbbbbb", "WHISPER", 11)
check(not printedSince(vmark):find("newer LefthyTools", 1, true), "nothing printed inside the event handler")
Advance(0.15)
local notice = printedSince(vmark)
check(notice:find("Anna has a newer LefthyTools (0.4.0-9-gbbbbbbb, you have 0.4.0-3-gabc1234)", 1, true)
	and notice:find("Update-LefthyTools.cmd", 1, true), "a friend on a newer build: told how to update, got " .. notice)
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
check(updateStatus():find("Newer version available: 0.5.0", 1, true), "settings overview: the newest version seen from a friend, got " .. updateStatus())
vmark = #PRINTED + 1
lefthy("version")
check(printedSince(vmark):find("a friend has the newer 0.5.0", 1, true), "/lefthy version mentions it too")

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
check(LefthyToolsAFKFrame.Friends:GetText():find("Anna|r (20) - Elwynn Forest |cffff5050(dead)", 1, true),
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
ClickWorldMap()
Advance(0.15)
check(#sentTo(11, mark, "P2;") == 1, "at most one ping every 1.5 s")
Advance(2)
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
local choices = DROPDOWNS.LefthyTools_beacon_dingSoundKit
check(BDB.dingSoundKit == 50111 and choices and #choices == 6 and choices[1].label == "Boss defeated fanfare",
	"level-up sound: a dropdown of 6 sounds, boss defeated fanfare by default")
local hasLevelUpFanfare = false
for _, c in ipairs(choices) do if c.value == 888 then hasLevelUpFanfare = true end end
check(not hasLevelUpFanfare, "the player's own level-up fanfare isn't offered (it sounds like you levelled)")
soundMark = #SOUNDS
B("dingSoundKit"):SetValue(73277)
check(#SOUNDS == soundMark, "picking a sound plays nothing inside the settings callback")
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

	STATE.target, STATE.targetName, STATE.targetGUID, TARGET_CLASS, STATE.targetDead = true, "Mor'Ladim", "Creature-0-77", "rareelite", true
	friendsOnline()
	mark = #GAMEDATA + 1
	Advance(1.1)
	local rare = lastEvent("rare")
	check(rare and rare.name == "Mor'Ladim" and rare.zone == "Elwynn Forest" and me.stats.rares == 1, "a rare dies while targeted")
	Advance(2)
	check(me.stats.rares == 1, "once per spawn")
	check(sentTo(11, mark, "E2;")[1] == "E2;rare;Mor'Ladim;Elwynn Forest", "and friends hear about it")
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
	check(#feed == before + 6, "at most 6 highlights a minute from one friend, got " .. (#feed - before))
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
	for _, expected in ipairs({ "|cffffd2002026-10-03|r", "Level 23 - Elwynn Forest (took 1m)", "Died to Hogger - Elwynn Forest - Goldshire (level 19)",
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
			"Favourite zone", "On foot", "Flight paths", "Jumps", "Most gold at once", "Epic items", "Mounts", "Time played (/played)" }) do
		check(labels:find(expected, 1, true), "statistics: " .. expected)
	end
	check(values:find("Hogger (1)", 1, true) and values:find("100h 0m", 1, true) == nil and values:find("4d 4h", 1, true),
		"values: deadliest foe, /played as days and hours")
	check(not win.Tabs.stats:IsEnabled() and win.Tabs.timeline:IsEnabled(), "the open page's button is greyed out")
	win.Tabs.friends:Click()
	check(win.Text:GetText():find("Anna|r: ", 1, true) and win.Text:GetText():find("Defeated Hogger (Elwynn Forest)", 1, true),
		"friends: their highlights")
	CDB.chars["Alty-Realmy"] = { name = "Alty", realm = "Realmy", classFile = "MAGE", level = 12,
		events = { { t = time(), k = "level", level = 12 } } }
	win.Tabs.timeline:Click()
	win.Next:Click()
	check(win.CharName:GetText():find("Alty", 1, true) and win.Text:GetText():find("Level 12", 1, true), "your other characters' journals")
	win.Tabs.stats:Click()
	check(win.Values:GetText() ~= "" and not win.Text:GetText():find("This session", 1, true), "and their statistics (no session)")
	win.Tabs.timeline:Click()
	win.Prev:Click()
	check(win.CharName:GetText():find("Lefthy", 1, true), "back to this character")
	Fire("NEW_TOY_ADDED", 1)
	Advance(1.1)
	check(win.Text:GetText():find("New toy: Toy Train Set", 1, true), "the open window follows new entries within a second")
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
end

section("Beacon: leaving")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "Q2", "WHISPER", 12)
Advance(0.15)
check(not peers()[12] and peers()[11], "a friend switching Beacon off (Q2) is forgotten")
mark = #GAMEDATA + 1
MOCK_SEND_RESULT = 3 -- the server is throttling right now
lefthy("disable beacon")
check(#GameDataTo(11, mark) == 0, "switching off sends nothing inside the settings callback")
Advance(1)
check(#GameDataTo(11, mark) == 0, "throttled: the goodbye waits")
MOCK_SEND_RESULT = nil
Advance(3)
check(GameDataTo(11, mark)[1] == "Q2", "... and then tells friends (through the rate limiter, not lost)")
check(next(WorldMapFrame.providers) == nil and next(BB.GetMinimapPins()) == nil, "and removes the dots from both maps")
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

section("what's new")
local news = ns.CHANGELOG
local goodData = #news > 0
for i, e in ipairs(news) do
	goodData = goodData and e.id == i and type(e.en) == "string" and e.en ~= "" and type(e.de) == "string" and e.de ~= ""
		and LT.ParseVersion(e.version) ~= nil
end
check(goodData, "changelog: ids 1, 2, 3, ... in order, each with a version and English and German text")
check(LT.freshInstall and not (LefthyToolsNewsFrame and LefthyToolsNewsFrame:IsShown()),
	"a new install doesn't get a what's-new window")
LefthyToolsDB.changelogSeen = #news - 2 -- two entries arrived with an update
STATE.combat = true
LT.WhatsNew.Schedule()
Advance(4)
check(not (LefthyToolsNewsFrame and LefthyToolsNewsFrame:IsShown()), "not in combat")
STATE.combat = false
Advance(5)
local newsText = LefthyToolsNewsFrame and LefthyToolsNewsFrame.Text:GetText() or ""
check(LefthyToolsNewsFrame and LefthyToolsNewsFrame:IsShown(), "after combat: the window opens by itself")
check(newsText:find(news[#news].en, 1, true) and newsText:find(news[#news - 1].en, 1, true)
	and not newsText:find(news[#news - 2].en, 1, true), "only the entries not seen yet")
check(newsText:find("LefthyTools 0.5.0 (in development)", 1, true), "a version still in development is marked, got " .. newsText)
check(LefthyToolsDB.changelogSeen == #news, "and they count as seen")
check(LefthyToolsNewsFrame.Subtitle:GetText():find("0.4.0-3-gabc1234", 1, true), "the window shows the installed build")
LefthyToolsNewsFrame.AllButton:Click()
check(LefthyToolsNewsFrame.Text:GetText():find(news[1].en, 1, true) and not LefthyToolsNewsFrame.AllButton:IsShown(), "'All changes' shows everything")
LefthyToolsNewsFrame:Hide()
lefthy("news")
check(LefthyToolsNewsFrame:IsShown() and LefthyToolsNewsFrame.Text:GetText():find(news[1].en, 1, true), "/lefthy news")
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
