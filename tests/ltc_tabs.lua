-- Beacon's LTC in chat tabs of the player's choice, and its colour.
-- Needs: beacon.lua, for its friends and Beacon on.
local suite = ...
local check, section, ns, LT, lefthy = suite.check, suite.section, suite.ns, suite.LT, suite.lefthy
local printedSince = suite.printedSince
local BB = ns.Beacon

section("Beacon: LTC in chat tabs")
do
	local got = {}
	local wasWindows = NUM_CHAT_WINDOWS
	NUM_CHAT_WINDOWS = 10
	local function tab(id, shown)
		local frame = _G["ChatFrame" .. id] or CreateFrame("Frame", "ChatFrame" .. id, UIParent)
		frame.GetID = function() return id end
		frame.AddMessage = function(_, line) got[id] = got[id] or {}; table.insert(got[id], line) end
		frame.name = "Tab " .. id
		frame:SetShown(shown)
		return frame
	end
	local main, combat, other = tab(1, true), tab(2, false), tab(3, false)
	local wasDefault, wasCombat, wasCurrent, wasFlash = DEFAULT_CHAT_FRAME, COMBATLOG, FCF_GetCurrentChatFrame, FCF_StartAlertFlash
	DEFAULT_CHAT_FRAME, COMBATLOG = main, combat
	local current, flashed = main, {}
	FCF_GetCurrentChatFrame = function() return current end
	FCF_StartAlertFlash = function(frame) flashed[#flashed + 1] = frame:GetID() end
	local peer = { name = "Anna Brook", classFile = "MAGE", rev = 0 }
	local function say(text)
		wipe(got)
		wipe(flashed)
		local mark = #PRINTED + 1
		BB.ReceiveChat(peer, text)
		return printedSince(mark)
	end
	LefthyToolsDB.ltcTabs = nil

	check(say("hello"):find("[LTC]", 1, true) and not next(got), "nothing chosen: printed, the main window as ever")

	-- Blizzard's Chat Settings page: a checkbox of ours, for the tab being set up.
	CreateFrame("Frame", "ChatConfigChatSettings", UIParent)
	CreateFrame("Frame", "ChatConfigBackgroundFrame", UIParent)
	local box = BB.BuildLTCTabBox()
	check(box and box:GetParent() == ChatConfigChatSettings, "on Blizzard's page, a frame of ours")
	check(box:GetChecked() == true, "the main window: ticked, it's the default")
	current = other
	ChatConfigChatSettings._scripts.OnShow(ChatConfigChatSettings)
	check(box:IsShown() and not box:GetChecked(), "another tab: not ticked")
	box:SetChecked(true)
	box._scripts.OnClick(box)
	local line = say("to the tab")
	check(got[3] and got[3][1]:find("to the tab", 1, true) and got[1] and got[1][1]:find("to the tab", 1, true) and line == "",
		"ticked: the new tab, and the main window until it's unticked")
	check(flashed[1] == 3 and #flashed == 1, "the tab out of sight flashes, the one in view doesn't")
	current = main
	ChatConfigChatSettings._scripts.OnShow(ChatConfigChatSettings)
	check(box:GetChecked() == true, "the main window: still ticked")
	box:SetChecked(false)
	box._scripts.OnClick(box)
	say("only there")
	check(got[3] and not got[1], "unticked on the main window: only the new tab")

	FCF_StartAlertFlash = function() error("flash failed") end
	say("still arrives")
	check(got[3] and got[3][1]:find("still arrives", 1, true), "the flash failing loses no line")
	FCF_StartAlertFlash = function(frame) flashed[#flashed + 1] = frame:GetID() end

	-- The last one off: the main window again, never nowhere.
	current = other
	ChatConfigChatSettings._scripts.OnShow(ChatConfigChatSettings)
	box:SetChecked(false)
	box._scripts.OnClick(box)
	line = say("back")
	check(line:find("back", 1, true) and not next(got), "nothing left: the main window again, never nowhere")
	current = main
	ChatConfigChatSettings._scripts.OnShow(ChatConfigChatSettings)
	check(box:GetChecked() == true, "and it says so")

	current = combat
	ChatConfigChatSettings._scripts.OnShow(ChatConfigChatSettings)
	check(not box:IsShown(), "the combat log: no such choice")
	local mark = #PRINTED + 1
	lefthy("beacon ltctab")
	check(printedSince(mark):find("can't show", 1, true), "nor by command")

	-- The command, for the tab in front; a closed tab forgets.
	current = other
	mark = #PRINTED + 1
	lefthy("beacon ltctab")
	check(printedSince(mark):find("LTC now shows in Tab 3", 1, true), "the command: on")
	say("x")
	check(got[3], "there it goes")
	FCF_Close(other)
	wipe(got)
	say("y")
	check(not got[3], "a closed tab starts over without LTC")
	other:Show()
	other:Hide()
	mark = #PRINTED + 1
	lefthy("beacon ltctab")
	lefthy("beacon ltctab")
	check(printedSince(mark):find("no longer shows", 1, true), "the command: off")
	LefthyToolsDB.ltcTabs = nil

	-- The colour.
	local shown
	ColorPickerFrame = {
		SetupColorPickerAndShow = function(_, info) shown = info end,
		GetColorRGB = function() return 1, 0, 0.5 end,
	}
	BB.PickLTCColour()
	check(shown and math.abs(shown.r - 1) < 0.01 and math.abs(shown.g - 184 / 255) < 0.01, "the picker starts on LTC's colour")
	shown.swatchFunc()
	check(say("red"):find("|cffff0080[LTC]", 1, true), "the lines take the chosen colour")
	shown.cancelFunc()
	check(say("back"):find("|cffffb84d[LTC]", 1, true), "cancelled: back to what it was")
	BB.module.db.lefthyChatColour = "nonsense"
	check(say("safe"):find("|cffffb84d[LTC]", 1, true), "a broken value: the usual colour")
	BB.module.db.lefthyChatColour = "ffb84d"
	ColorPickerFrame = nil

	DEFAULT_CHAT_FRAME, COMBATLOG, FCF_GetCurrentChatFrame, FCF_StartAlertFlash = wasDefault, wasCombat, wasCurrent, wasFlash
	main.AddMessage, main.GetID = nil, nil
	NUM_CHAT_WINDOWS = wasWindows
	ChatFrame3, ChatConfigChatSettings, ChatConfigBackgroundFrame = nil, nil, nil
end
