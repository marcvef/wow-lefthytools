-- LefthyTools' settings window (Core/SettingsWindow.lua, its data Core/Options.lua): pages, rows,
-- search; changed settings and resets; "New" tags.
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
	-- Closing that panel behind it: the way back to the game menu closes what Escape would.
	EventRegistry:TriggerEvent("SettingsPanel.OnHide")
	win:Hide()
	Advance(1)
	check(win:IsShown() and Options.shownPage == LT.category, "closing Blizzard's panel behind it leaves it open, on its page")
	win:Hide()
	Advance(1)
	check(not win:IsShown(), "closing it afterwards closes it")

	-- Saved values stay put: nothing in the window keeps a copy.
	local tbl = LefthyToolsDB.settings.beacon
	check(tbl == beacon.db and tbl.lefthyChatSoundKit ~= nil, "settings are the same saved tables as ever")
end

section("the settings window: changed settings, resets, new settings")
do
	local beacon, tweaks, mirage = LT:GetModule("beacon"), LT:GetModule("tweaks"), LT:GetModule("mirage")
	local db = beacon.db
	local DOT = "\226\128\162"
	local function rowOf(page, setting)
		for _, row in ipairs(page.rows) do
			if row.setting == setting then return row end
		end
	end
	local function name(row) return row.frame.Name:GetText() or "" end
	local function marked(row) return name(row):find(DOT, 1, true) ~= nil end
	local function tagged(text) return text:find("New", 1, true) ~= nil end
	local function undoShown(row) return row.frame.Undo ~= nil and row.frame.Undo:IsShown() end
	-- What the page's settings are now, to put back afterwards (later suites go on from here).
	local function snapshot(page)
		local values = {}
		for _, row in ipairs(page.rows) do
			if row.setting then values[row.setting] = row.setting:GetValue() end
		end
		return function()
			for setting, value in pairs(values) do setting:SetValue(value) end
		end
	end
	local putBack = snapshot(beacon.category)

	LT:OpenSettings(beacon)
	local win = LefthyToolsSettingsFrame
	local share = rowOf(beacon.category, beacon.settings.share)
	local shareSetting = beacon.settings.share
	check(shareSetting.default == beacon.defaults.share and type(shareSetting.default) == "boolean", "a setting knows its default")
	shareSetting:SetValue(shareSetting.default)
	check(name(share) == share.name and not undoShown(share), "at its default: no dot, no button")

	-- A checkbox changed: a dot before its name, a button back at the row's end.
	local changed = 0
	local wasChanged = beacon.OnSettingChanged
	beacon.OnSettingChanged = function(self) changed = changed + 1; return wasChanged(self) end
	share.frame.Check:SetChecked(not shareSetting.default)
	share.frame.Check._scripts.OnClick(share.frame.Check)
	check(db.share == not shareSetting.default and marked(share) and undoShown(share), "changed: a gold dot and the button back")
	check(select(2, share.frame.Undo:GetPoint()) == -12 and share.frame.Undo.Icon.atlas == "common-icon-undo", "a checkbox's sits at the row's end")
	share.frame.Undo._scripts.OnEnter(share.frame.Undo)
	check(TOOLTIP.title == "Back to the default" and TOOLTIP.lines[1] == "Default: " .. (shareSetting.default and "On" or "Off"),
		"its tooltip says what the default is")
	changed = 0
	share.frame.Undo:Click()
	check(db.share == shareSetting.default and changed == 1 and share.frame.Check:GetChecked() == db.share, "clicked: back to the default, the module hears")
	check(not marked(share) and not undoShown(share) and not TOOLTIP.shown, "and the dot and the button go")

	-- A slider, a dropdown, a text: the same, through the setting.
	local interval = rowOf(beacon.category, beacon.settings.interval)
	beacon.settings.interval:SetValue(beacon.defaults.interval)
	interval.frame.More:Click()
	check(marked(interval) and undoShown(interval) and select(2, interval.frame.Undo:GetPoint()) < -230, "a slider: the button left of it")
	interval.frame.Undo._scripts.OnEnter(interval.frame.Undo)
	check(TOOLTIP.lines[1] == "Default: " .. interval.formatter(beacon.defaults.interval), "... its default as the slider shows it")
	interval.frame.Undo:Click()
	check(db.interval == beacon.defaults.interval and interval.frame.Slider:GetValue() == db.interval and not undoShown(interval), "back")
	local ding = rowOf(beacon.category, beacon.settings.dingSoundKit)
	beacon.settings.dingSoundKit:Reset()
	local other = ding.setting.default == 1 and 2 or 1
	ding.setting:SetValue(other)
	check(db.dingSoundKit == ding.values[other][1] and undoShown(ding), "a dropdown")
	ding.frame.Undo:Click()
	check(db.dingSoundKit == beacon.defaults.dingSoundKit and ding.frame.Picker.Label:GetText() == ding.values[ding.setting.default][2],
		"back to the default's value, its label too")
	local text = rowOf(beacon.category, beacon.settings.dingText)
	beacon.settings.dingText:SetValue("something else")
	check(marked(text) and undoShown(text), "a text")
	text.frame.Undo:Click()
	check(db.dingText == beacon.defaults.dingText and text.frame.Box:GetText() == db.dingText, "back")
	beacon.OnSettingChanged = wasChanged

	-- The same marks in a search's list; a command's change shows too.
	LT:SetModuleSetting(beacon, "share", not shareSetting.default)
	win.SearchBox:SetText("share my position")
	Advance(1)
	check(share.frame:IsShown() and marked(share) and undoShown(share), "a search shows what's changed, a command's change too")
	share.frame.Undo:Click()
	check(db.share == shareSetting.default and not marked(share), "and can put it back there")
	win.Clear:Click()

	-- A module's switch has no default to go back to: on or off is the player's choice.
	LT:OpenSettings(tweaks)
	local switch = tweaks.category.rows[1]
	tweaks.enabledSetting:SetValue(false)
	check(switch.setting:IsDefault() and not marked(switch) and not undoShown(switch), "a module's switch: no dot, no button")
	tweaks.enabledSetting:SetValue(true)

	-- A page's foot: everything back, after asking.
	LT:OpenSettings(beacon)
	local foot = beacon.category.rows[#beacon.category.rows]
	check(foot.kind == "reset" and foot.frame and foot.frame:IsShown(), "a module's page ends with a reset")
	check(LT.category.rows[#LT.category.rows].kind ~= "reset", "the overview has none")
	for _, row in ipairs(beacon.category.rows) do
		if row.setting then row.setting:Reset() end
	end
	check(Options.Changed(beacon.category) == 0 and not foot.frame.Button:IsEnabled(), "nothing changed: nothing to reset")
	shareSetting:SetValue(not shareSetting.default)
	beacon.settings.interval:SetValue(beacon.defaults.interval + interval.step)
	check(Options.Changed(beacon.category) == 2 and foot.frame.Button:IsEnabled(), "two changed: it can")
	foot.frame.Button:Click()
	check(db.share ~= shareSetting.default and foot.frame.Button:GetText() == "Yes, reset" and name(foot):find("back to its default?", 1, true),
		"the first click only asks")
	Advance(6)
	check(foot.frame.Button:GetText() == "Reset" and name(foot) == "Reset this page" and db.share ~= shareSetting.default,
		"unanswered for a few seconds: it asks again next time")
	foot.frame.Button:Click()
	foot.frame.armed = GetTime() - 6 -- (asked long ago, its timer late)
	foot.frame.Button:Click()
	check(db.share ~= shareSetting.default and foot.frame.Button:GetText() == "Yes, reset", "an old question isn't an answer: it asks again")
	LT:OpenSettings(tweaks)
	LT:OpenSettings(beacon)
	foot.frame.Button:Click()
	LT:OpenSettings(tweaks)
	LT:OpenSettings(beacon)
	check(foot.frame.Button:GetText() == "Reset", "the page left: so does the question")
	foot.frame.Button:Click()
	win:Hide()
	win:Show()
	check(foot.frame.Button:GetText() == "Reset", "the window closed: too")
	changed = 0
	beacon.OnSettingChanged = function(self) changed = changed + 1; return wasChanged(self) end
	foot.frame.Button:Click()
	foot.frame.Button:Click()
	beacon.OnSettingChanged = wasChanged
	check(db.share == shareSetting.default and db.interval == beacon.defaults.interval and changed == 2, "asked and answered: back to the defaults, the module hears")
	check(not marked(share) and not undoShown(interval) and not foot.frame.Button:IsEnabled() and foot.frame.Button:GetText() == "Reset",
		"the page shows it")
	check(beacon.enabled and LefthyToolsDB.settings.beacon == db, "the module stays on; the same saved table")

	-- A module with a reset of its own (Mirage's ResetSettings, as /mirage reset): that one.
	local resets = 0
	local wasReset = mirage.ResetSettings
	mirage.ResetSettings = function(self) resets = resets + 1; self.settings.delay:Reset() end
	local delay = mirage.settings.delay
	delay:SetValue(delay.default + 1)
	LT:OpenSettings(mirage)
	local mirageFoot = mirage.category.rows[#mirage.category.rows]
	mirageFoot.frame.Button:Click()
	mirageFoot.frame.Button:Click()
	mirage.ResetSettings = wasReset
	check(resets == 1 and mirage.db.delay == delay.default and not marked(rowOf(mirage.category, delay)), "a module's own reset is used")

	-- Search: the resets aren't settings.
	win.SearchBox:SetText("reset this page")
	Advance(1)
	check(win.Empty:IsShown(), "a search doesn't list the pages' resets")
	win.Clear:Click()
	win:Hide()
	putBack()

	-- New settings: none on an install, none for players who had settings before this.
	local seen = LefthyToolsDB.settingsSeen
	local count, unseen = 0, 0
	for _ in pairs(seen) do count = count + 1 end
	for _, page in ipairs(Options.pages) do
		for _, row in ipairs(page.rows) do
			if row.new or (row.setting and not seen[row.setting.variable]) then unseen = unseen + 1 end
		end
	end
	check(unseen == 0 and seen[shareSetting.variable] and count > 50, "every setting counts as seen on a new install")
	local function pageButton(page)
		for _, b in ipairs(win.Pages) do
			if b.page == page then return b end
		end
	end
	LT:OpenSettings()
	local anyTag = false
	for _, b in ipairs(win.Pages) do anyTag = anyTag or tagged(b.Text:GetText()) end
	check(not anyTag, "no page says New")

	-- A later build brings two settings: they're new, and so are their pages.
	seen[shareSetting.variable], seen[tweaks.settings.statusText.variable] = nil, nil
	Options.FindNew()
	LT:OpenSettings()
	check(tagged(pageButton(beacon.category).Text:GetText()) and tagged(pageButton(tweaks.category).Text:GetText())
		and not tagged(pageButton(mirage.category).Text:GetText()), "pages with something new say so in the sidebar")
	win.SearchBox:SetText("share my position")
	Advance(1)
	check(tagged(name(share)) and not seen[shareSetting.variable], "a search shows the tag, and doesn't count as opening the page")
	win.Clear:Click()
	LT:OpenSettings(beacon)
	check(tagged(name(share)) and not tagged(name(interval)) and seen[shareSetting.variable], "its page opened: the tag on the new one, now seen")
	check(not tagged(pageButton(beacon.category).Text:GetText()) and tagged(pageButton(tweaks.category).Text:GetText()), "the sidebar: only the other page")
	local status = rowOf(tweaks.category, tweaks.settings.statusText)
	LT:OpenSettings(tweaks)
	check(tagged(name(status)) and not share.new, "another page: its tags; the first page's went")
	LT:OpenSettings(beacon)
	check(not tagged(name(share)), "back: no tag any more")
	win:Hide()
	LT:OpenSettings(tweaks)
	check(not tagged(name(status)) and seen[tweaks.settings.statusText.variable], "closed and opened again: none either")
	win:Hide()

	-- The first build with this, for a player who had settings already: nothing is new.
	LefthyToolsDB.settingsSeen = nil
	Options.FindNew()
	local all, newRows = 0, 0
	for _ in pairs(LefthyToolsDB.settingsSeen) do all = all + 1 end
	for _, page in ipairs(Options.pages) do
		for _, row in ipairs(page.rows) do
			if row.new then newRows = newRows + 1 end
		end
		if page.new then newRows = newRows + 1 end
	end
	check(newRows == 0 and all == count, "no saved list yet: everything counts as seen, no flood of tags")
	check(LefthyToolsDB.settings.beacon == db and LefthyToolsDB.settings.mirage == mirage.db, "settings are still the same saved tables")
end
Advance(0.1) -- (this file advances 11.9 s; whole seconds for the suites after it)
