-- LefthyTools' settings window (Core/SettingsWindow.lua, its data Core/Options.lua).
-- Needs: no other file.
local suite = ...
local check, section, ns, LT, lefthy = suite.check, suite.section, suite.ns, suite.LT, suite.lefthy
local Options = LT.Options

section("the settings window")
do
	local beacon, tweaks = LT:GetModule("beacon"), LT:GetModule("tweaks")
	local db = beacon.db
	local function rowOf(page, setting)
		for _, row in ipairs(page.rows) do
			if row.setting == setting then return row end
		end
	end
	local function visible(text)
		local n = 0
		for _, row in ipairs(Options.pages) do
			for _, r in ipairs(row.rows) do
				if r.frame and r.frame:IsShown() and r.name == text then n = n + 1 end
			end
		end
		return n
	end

	LT:OpenSettings()
	local win = LefthyToolsSettingsFrame
	check(win and win:IsShown() and Options.shownPage == LT.category, "/lefthy's way: the overview, in a window of its own")
	check(visible("Version") == 1 and visible("Updates") == 1, "the overview's rows are drawn")
	local mod = rowOf(LT.category, beacon.enabledSetting)
	check(mod and mod.frame and mod.frame.Check:GetChecked() == true and not beacon.category.rows[1].frame, "a page is built when first opened")

	-- Each kind of row, against a real setting.
	local changed = 0
	local wasChanged = beacon.OnSettingChanged
	beacon.OnSettingChanged = function(self) changed = changed + 1; return wasChanged(self) end
	LT:OpenSettings(beacon)
	check(Options.shownPage == beacon.category and beacon.category.rows[1].setting == beacon.enabledSetting, "a module's page: its switch first")

	local share = rowOf(beacon.category, beacon.settings.share)
	local was = db.share
	share.frame.Check:SetChecked(not was)
	share.frame.Check._scripts.OnClick(share.frame.Check)
	check(db.share == not was and changed == 1, "a checkbox writes the saved setting, the module hears")
	share.frame._scripts.OnMouseUp(share.frame, "LeftButton")
	check(db.share == was and share.frame.Check:GetChecked() == was and changed == 2, "its name is part of it, and the box follows")

	local interval = rowOf(beacon.category, beacon.settings.interval)
	local value = db.interval
	interval.frame.More:Click()
	check(db.interval == value + interval.step and interval.frame.Slider:GetValue() == db.interval, "a slider's +: one step")
	interval.frame.Less:Click()
	check(db.interval == value, "-: one back")
	interval.frame.Slider:SetValue(interval.max + 100)
	check(db.interval == interval.max, "dragged past the end: its maximum")
	interval.frame.Slider._scripts.OnMouseWheel(interval.frame.Slider, -1)
	check(db.interval == interval.max - interval.step, "the wheel: a step")
	beacon.settings.interval:SetValue(value)
	check(interval.frame.Slider:GetValue() == value and interval.frame.Value:GetText() ~= "", "a value changed elsewhere: the row follows")

	local ding = rowOf(beacon.category, beacon.settings.dingSoundKit)
	check(ding and ding.frame.Picker, "a choice is a dropdown of ours, not a slider")
	ding.frame.Picker:Click()
	local list = ding.frame.Picker.List
	check(list:IsShown() and list:GetParent() == win and list.rows[2], "it opens, where the scrolling area can't cut it off")
	list.rows[2]:Click()
	check(db.dingSoundKit == ding.values[2][1] and ding.frame.Picker.Label:GetText() == ding.values[2][2] and not list:IsShown(),
		"picking one keeps its value in the saved setting, and the label says it")
	beacon.settings.dingSoundKit:SetValue(1)
	check(db.dingSoundKit == ding.values[1][1], "by its position too")

	local text = rowOf(beacon.category, beacon.settings.dingText)
	check(text.frame.Box:GetText() == db.dingText, "a text field shows the saved text")
	local wasText = db.dingText
	text.frame.Box:SetText("  a new one ")
	text.frame.Box._scripts.OnEditFocusLost(text.frame.Box)
	check(db.dingText == "a new one", "leaving it saves it, trimmed")
	text.frame.Box:SetText("thrown away")
	text.frame.Box._scripts.OnEscapePressed(text.frame.Box)
	check(db.dingText == "a new one" and text.frame.Box:GetText() == "a new one", "Escape: back to what's saved")
	beacon.settings.dingText:SetValue(wasText)

	local clicks = 0
	local button = Options.buttons["Test your message"]
	local wasClick = button.onClick
	button.onClick = function() clicks = clicks + 1 end
	button.frame.Button:Click()
	check(clicks == 1 and button.frame.Button:GetText() == "Preview", "a button")
	button.onClick = wasClick
	beacon.OnSettingChanged = wasChanged

	-- Tooltips: the row's, also over its control; a function is built when it opens.
	share.frame._scripts.OnEnter(share.frame)
	check(TOOLTIP.title == share.name, "hovering a row: its name and text")
	share.frame._scripts.OnLeave(share.frame)

	-- A module off: its page says so, and the rows can still be changed.
	local tweakRow = rowOf(tweaks.category, tweaks.settings.statusText)
	LT:OpenSettings(tweaks)
	check(tweakRow.frame:GetAlpha() == 1, "a module that's on: as it is")
	tweaks.enabledSetting:SetValue(false)
	check(tweakRow.frame:GetAlpha() < 1 and not tweaks.enabled, "switched off: the page is dimmer")
	tweaks.enabledSetting:SetValue(true)
	check(tweakRow.frame:GetAlpha() == 1 and tweaks.enabled, "on again")

	-- A slider that depends on a checkbox.
	local mirage = LT:GetModule("mirage")
	local dependent
	for _, row in ipairs(mirage.category.rows) do
		if row.dependsOn then dependent = row; break end
	end
	LT:OpenSettings(mirage)
	dependent.dependsOn:SetValue(true)
	check(dependent.frame.Less:IsEnabled() ~= false, "its checkbox on: it can be moved")
	dependent.dependsOn:SetValue(false)
	check(dependent.frame:GetAlpha() < 1, "off: greyed out")
	dependent.dependsOn:SetValue(true)

	-- Search: every page, by name or tooltip, and back.
	LT:OpenSettings(beacon)
	win.SearchBox:SetText("colour")
	Advance(0.3)
	check(visible("LTC colour") == 1 and visible("Share my position") == 0 and win.Clear:IsShown(), "search finds a setting by its name, in any page")
	win.SearchBox:SetText("cinematic")
	Advance(0.3)
	check(visible("Cinematic flights") == 1, "... another module's")
	win.SearchBox:SetText("zzzz nothing")
	Advance(0.3)
	check(win.Empty:IsShown(), "nothing: it says so")
	win.Clear:Click()
	check(Options.shownPage == beacon.category and visible("Share my position") == 1 and not win.Empty:IsShown() and win.SearchBox:GetText() == "", "cleared: the page again")

	-- It's a plain window: any time.
	win:Hide()
	EnterCombat()
	lefthy("")
	check(win:IsShown(), "in a fight: it opens")
	LeaveCombat()
	win:Hide()
	GAMEPAD_STATE.ui = true
	lefthy("beacon")
	GAMEPAD_STATE.ui = false
	win:Hide()
	win:Show()
	check(#Options.pages == 1 + #(function() local m = {}; for _, x in ipairs(LT.modules) do if type(x.BuildOptions) == "function" then m[#m + 1] = x end end return m end)(), "a page per module, and the overview")
	win:Hide()

	-- Blizzard's list only leads here.
	Options.blizzardButton:Click()
	check(win:IsShown() and Options.shownPage == LT.category, "the button on Blizzard's page opens it")
	win:Hide()

	-- Saved values stay put: nothing in the window keeps a copy.
	local tbl = LefthyToolsDB.settings.beacon
	check(tbl == beacon.db and tbl.lefthyChatSoundKit ~= nil, "settings are the same saved tables as ever")
end
