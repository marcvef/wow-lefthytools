-- Mirage: the idle fade, what reveals each element, the controller UI, minimap quest areas, settings.
local suite = ...
local check, near, a, section, LT, lefthy = suite.check, suite.near, suite.a, suite.section, suite.LT, suite.lefthy
local Mirage = LT:GetModule("mirage")
local MDB = LefthyToolsDB.settings.mirage
local mirage = SlashCmdList.LEFTHYTOOLS_MIRAGE
local function S(id) return REGISTERED_SETTINGS["LefthyTools_mirage_" .. id] end

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
-- A cinematic flight's film hides the minimap (another part's override): Toggle Minimap then isn't "off for good".
STATE.target = true; Fire("PLAYER_TARGET_CHANGED"); Advance(0.4)
Mirage:HideGroups("test", { minimap = true }, 0)
Advance(0.3)
check(not Minimap:IsShown(), "hidden for a flight's film")
ToggleMinimap()
Advance(0.15)
check(not Minimap:IsShown(), "Toggle Minimap during the film: hidden again (its quest areas ignore alpha)")
Mirage:HideGroups("test", nil, 0)
Advance(0.3)
check(Minimap:IsShown(), "after the film: back (that press wasn't the player switching it off)")
STATE.target = false; Fire("PLAYER_TARGET_CHANGED"); Advance(8)
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
do -- /lefthy's list: Core's words and the ones modules add (LT:AddCommand), each where it always was.
	local hmark = #PRINTED + 1
	lefthy("help")
	local lines = {}
	for i = hmark, #PRINTED do lines[#lines + 1] = (PRINTED[i]:gsub("^|cff%x+LefthyTools|r: ", "")) end
	local want = {
		"/lefthy - open settings",
		"/lefthy modules - list modules",
		"/lefthy version - the installed LefthyTools version",
		"/lefthy errors [clear] - LefthyTools' own errors, ready to copy",
		"/lefthy report <what happened> - send a report to friends who collect them (Beacon)",
		"/lefthy reports - the reports your friends sent you",
		"/lefthy news - what's new in LefthyTools",
		"/lefthy announce <text> (or /la) - a line in the middle of your Beacon friends' screens (/ltc or /l <text>: LTC, LefthyTools chat)",
		"/lefthy stream watch <name> | stop | me | preview - a Beacon friend's fight, live (more: /lefthy stream)",
		"/lefthy enable | disable | toggle <module>",
		"/lefthy <module> ... - module commands, e.g. /lefthy mirage status",
	}
	check(table.concat(lines, "\n") == table.concat(want, "\n"), "/lefthy help: every word, Beacon's too, got\n" .. table.concat(lines, "\n"))
	local got
	LT:AddCommand("testword", function(rest) got = rest end) -- (no help line: not listed)
	lefthy("TestWord Some Text")
	check(got == "Some Text", "a word a module adds gets what follows it, as typed")
end
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
mirage("delay 1,5")
check(MDB.delay == 1.5, "/mirage delay 1,5: a decimal comma too (German clients show \"1,5 s\")")
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

section("Mirage: the minimap button pauses fading")
do
	local function has(text) for _, l in ipairs(TOOLTIP.lines) do if l == text then return true end end return false end
	local mb = Mirage:MinimapButton()
	check(MDB.minimapButton == true and mb and mb:IsShown() and mb:GetParent() == Minimap and not mb.Pause:IsShown(),
		"a minimap button while Mirage is on")
	Advance(8)
	check(near(a("MainActionBar"), 0), "faded")
	mb._scripts.OnClick(mb, "LeftButton")
	Advance(0.4)
	check(Mirage:IsPaused() and near(a("MainActionBar"), 1) and mb.Pause:IsShown() and mb.Icon.desaturated, "click: paused, everything back, the icon greyed with II")
	Advance(30)
	check(near(a("MainActionBar"), 1), "and it stays while paused")
	mb._scripts.OnEnter(mb)
	check(TOOLTIP.title == "Mirage" and has("Paused: the interface stays visible.") and has("Click: fade again when idle"),
		"hover: paused, and what a click does")
	mb._scripts.OnLeave(mb)
	local printed = #PRINTED
	mirage("status")
	check(table.concat(PRINTED, "\n", printed + 1):find("paused", 1, true), "/mirage status says so")
	mb._scripts.OnClick(mb, "LeftButton")
	Advance(8)
	check(not Mirage:IsPaused() and near(a("MainActionBar"), 0) and not mb.Pause:IsShown(), "click again: fading when idle again")
	mirage("pause")
	Advance(0.4)
	check(Mirage:IsPaused() and near(a("MainActionBar"), 1), "/mirage pause too")
	mirage("resume")
	check(not Mirage:IsPaused(), "/mirage resume")
	-- Shift-click: paused for good, also after a restart (Mirage switched off and on stands in for one).
	STATE.shift = true
	mb._scripts.OnClick(mb, "LeftButton")
	STATE.shift = false
	Advance(0.4)
	check(Mirage:IsPauseKept() and MDB.pauseKept == true and near(a("MainActionBar"), 1) and mb.Pause:IsShown()
		and mb.Pause.color[3] < 0.5, "Shift-click: paused for good, the II in orange")
	mb._scripts.OnEnter(mb)
	check(has("Paused for good: the interface stays visible, also after a restart."), "hover: paused for good")
	mb._scripts.OnLeave(mb)
	mirage("off")
	printed = #PRINTED
	mirage("on")
	Advance(8)
	check(Mirage:IsPauseKept() and near(a("MainActionBar"), 1)
		and table.concat(PRINTED, "\n", printed + 1):find("paused for good", 1, true), "after a restart still paused, and chat says so")
	mb._scripts.OnClick(mb, "LeftButton")
	check(not Mirage:IsPaused() and MDB.pauseKept == false and mb.Pause.color[3] == 1, "a click: fading again, not kept any more")
	mirage("pause keep")
	check(Mirage:IsPauseKept(), "/mirage pause keep too")
	mirage("resume")
	check(not Mirage:IsPaused() and MDB.pauseKept == false, "/mirage resume ends it")
	mirage("off")
	Advance(0.1)
	check(not mb:IsShown(), "Mirage off: no button")
	mirage("on")
	Advance(0.1)
	check(mb:IsShown(), "on again: back")
	REGISTERED_SETTINGS.LefthyTools_mirage_minimapButton:SetValue(false)
	Advance(0.1)
	check(not mb:IsShown(), "setting off: gone")
	REGISTERED_SETTINGS.LefthyTools_mirage_minimapButton:SetValue(true)
	Advance(0.1)
end

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
do -- "Faded opacity" changes every element's setting: the minimap button is updated once for all of them
	local after, scheduled = C_Timer.After, 0
	C_Timer.After = function(...) scheduled = scheduled + 1; return after(...) end
	mirage("alpha 40")
	mirage("alpha 50")
	C_Timer.After = after
	check(scheduled == 1, "one deferred button update for two changes of every element, got " .. scheduled)
end
