local _, ns = ...
local LT = ns.LT
local L = ns.L
local Options = LT.Options

-- LefthyTools' settings window (the data: Options.lua). The pages on the left, each with whether its
-- module is on; a search over all of them; the rows of the page, or of what was found, on the right.
-- A plain window, nothing protected: it opens in a fight and in gamepad mode, and it never touches
-- Blizzard's settings panel. Built when first opened; a row's frame when it's first shown.

local WIDTH, HEIGHT = 860, 620
local SIDEBAR = 176          -- the left column's width
local PAGE_H = 26            -- a page's button
local ROW_H = { header = 34, checkbox = 30, slider = 34, choice = 32, text = 32, button = 32, info = 30 }
local CONTROL_W = 230        -- what's at the right of a row: slider, dropdown, text field, button
local RIGHT_GAP = 12
local SEARCH_GAP = 0.2       -- seconds after the last key
local GOLD = "|cffffd200"
local ON, OFF = "|cff80ff80", "|cff808080"

local frame, content, scroll, searchBox, clearButton
local pageButtons = {}
local current          -- the page shown
local found            -- what's being searched for, or nil
local searchAt
local shownRows = {}   -- the rows laid out now
local titles = {}      -- the search's headers, reused

local function ShowTip(owner, row)
	if not row.tooltip then
		return
	end
	local text = row.tooltip
	if type(text) == "function" then
		text = text()
	end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(row.name, 1, 1, 1)
	GameTooltip:AddLine(text, nil, nil, nil, true)
	GameTooltip:Show()
end

local function HideTip(owner)
	if GameTooltip:IsOwned(owner) then
		GameTooltip:Hide()
	end
end

-- A row's plain frame: the hover's tooltip and light, its name at the left.
local function NewRowFrame(row)
	local f = CreateFrame("Frame", nil, content)
	f:SetHeight(ROW_H[row.kind])
	f:EnableMouse(true)
	f.Hover = f:CreateTexture(nil, "BACKGROUND")
	f.Hover:SetAllPoints()
	f.Hover:SetColorTexture(1, 1, 1, 0.04)
	f.Hover:Hide()
	f:SetScript("OnEnter", function(self)
		self.Hover:Show()
		ShowTip(self, row)
	end)
	f:SetScript("OnLeave", function(self)
		self.Hover:Hide()
		HideTip(self)
	end)
	f.Name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.Name:SetPoint("LEFT", row.kind == "checkbox" and 30 or 6, 0)
	f.Name:SetPoint("RIGHT", row.kind == "checkbox" and -6 or -(CONTROL_W + RIGHT_GAP + 8), 0)
	f.Name:SetJustifyH("LEFT")
	f.Name:SetWordWrap(false)
	f.Name:SetText(row.name)
	return f
end

-- Controls keep the row's tooltip: the mouse over them is over the row.
local function KeepsTip(control, f, row)
	control:HookScript("OnEnter", function()
		f.Hover:Show()
		ShowTip(control, row)
	end)
	control:HookScript("OnLeave", function()
		f.Hover:Hide()
		HideTip(control)
	end)
end

local Build = {}

function Build.header(row)
	local f = CreateFrame("Frame", nil, content)
	f:SetHeight(ROW_H.header)
	f.Name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.Name:SetPoint("BOTTOMLEFT", 4, 6)
	f.Name:SetText(row.name)
	local line = f:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 0.82, 0, 0.25)
	line:SetHeight(1)
	line:SetPoint("BOTTOMLEFT", 2, 2)
	line:SetPoint("BOTTOMRIGHT", -2, 2)
	f.Refresh = function() end
	return f
end

function Build.checkbox(row)
	local f = NewRowFrame(row)
	local check = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	check:SetSize(24, 24)
	check:SetPoint("LEFT", 2, 0)
	f.Check = check
	local function Set(on)
		if SOUNDKIT then
			PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		end
		row.setting:SetValue(on)
	end
	check:SetScript("OnClick", function(self) Set(self:GetChecked() and true or false) end)
	f:SetScript("OnMouseUp", function(_, mouseButton) -- (the name is part of it)
		if mouseButton == "LeftButton" then
			Set(not row.setting:GetValue())
		end
	end)
	KeepsTip(check, f, row)
	f.Refresh = function()
		check:SetChecked(row.setting:GetValue() == true)
	end
	return f
end

local function RoundedToStep(row, value)
	local steps = math.floor((value - row.min) / row.step + 0.5)
	value = row.min + steps * row.step
	return math.floor(math.max(row.min, math.min(row.max, value)) * 1000 + 0.5) / 1000
end

function Build.slider(row)
	local f = NewRowFrame(row)
	f.Value = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.Value:SetPoint("RIGHT", -RIGHT_GAP, 0)
	f.Value:SetWidth(64)
	f.Value:SetJustifyH("RIGHT")
	local slider = CreateFrame("Slider", nil, f)
	f.Slider = slider
	slider:SetOrientation("HORIZONTAL")
	slider:SetSize(CONTROL_W - 112, 16)
	slider:SetPoint("RIGHT", f.Value, "LEFT", -26, 0)
	slider:SetMinMaxValues(row.min, row.max)
	slider:SetValueStep(row.step)
	if slider.SetObeyStepOnDrag then
		slider:SetObeyStepOnDrag(true)
	end
	slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	local track = slider:CreateTexture(nil, "BACKGROUND")
	track:SetColorTexture(1, 1, 1, 0.18)
	track:SetHeight(4)
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	local function Step(by)
		row.setting:SetValue(RoundedToStep(row, row.setting:GetValue() + by * row.step))
	end
	local function Stepper(text, by, anchorPoint, anchorTo, anchorRelative, x)
		local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		b:SetSize(20, 20)
		b:SetText(text)
		b:SetPoint(anchorPoint, anchorTo, anchorRelative, x, 0)
		b:SetScript("OnClick", function() Step(by) end)
		KeepsTip(b, f, row)
		return b
	end
	f.Less = Stepper("-", -1, "RIGHT", slider, "LEFT", -4)
	f.More = Stepper("+", 1, "LEFT", slider, "RIGHT", 4)
	slider:SetScript("OnValueChanged", function(_, value)
		if not f.refreshing then
			row.setting:SetValue(RoundedToStep(row, value))
		end
	end)
	slider:EnableMouseWheel(true)
	slider:SetScript("OnMouseWheel", function(_, delta) Step(delta > 0 and 1 or -1) end)
	KeepsTip(slider, f, row)
	f.Refresh = function()
		local value = row.setting:GetValue()
		f.refreshing = true
		slider:SetValue(value)
		f.refreshing = false
		f.Value:SetText(row.formatter and row.formatter(value) or tostring(value))
	end
	return f
end

function Build.choice(row)
	local f = NewRowFrame(row)
	local function Entries()
		local entries, position = {}, row.setting:GetValue()
		for i, v in ipairs(row.values) do
			entries[i] = { text = v[2], value = i, selected = i == position }
		end
		return entries
	end
	local picker = LT.Window.AddPicker(f, CONTROL_W, Entries, function(index) row.setting:SetValue(index) end)
	picker:SetPoint("RIGHT", -RIGHT_GAP, 0)
	picker.List:SetParent(frame) -- (the scrolling area would cut it off)
	picker.List:SetFrameStrata("FULLSCREEN_DIALOG")
	f.Picker = picker
	KeepsTip(picker, f, row)
	f.Refresh = function()
		local v = row.values[row.setting:GetValue()]
		picker:SetLabel(v and v[2] or "")
	end
	return f
end

function Build.text(row)
	local f = NewRowFrame(row)
	local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	f.Box = box
	box:SetSize(CONTROL_W, 22)
	box:SetPoint("RIGHT", -RIGHT_GAP, 0)
	box:SetAutoFocus(false)
	box:SetMaxLetters(row.maxLetters or 0)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText(row.setting:GetValue() or "")
		self:ClearFocus()
	end)
	box:HookScript("OnEditFocusLost", function(self)
		local text = strtrim(self:GetText() or "")
		if text ~= row.setting:GetValue() then
			row.setting:SetValue(text)
		end
	end)
	KeepsTip(box, f, row)
	f.Refresh = function()
		if not box:HasFocus() then
			box:SetText(row.setting:GetValue() or "")
			box:SetCursorPosition(0)
		end
	end
	return f
end

function Build.button(row)
	local f = NewRowFrame(row)
	local button = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.Button = button
	button:SetSize(CONTROL_W, 24)
	button:SetPoint("RIGHT", -RIGHT_GAP, 0)
	button:SetText(row.text)
	button:SetScript("OnClick", function() row.onClick() end)
	KeepsTip(button, f, row)
	f.Refresh = function() end
	return f
end

function Build.info(row)
	local f = NewRowFrame(row)
	f.Value = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.Value:SetPoint("RIGHT", -RIGHT_GAP, 0)
	f.Value:SetJustifyH("RIGHT")
	local button = row.button and CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	if button then
		f.Button = button
		button:SetSize(80, 22)
		button:SetPoint("RIGHT", -RIGHT_GAP, 0)
		button:SetText(row.button.text)
		button:SetScript("OnClick", function() row.button.onClick() end)
	end
	f.Refresh = function()
		local ok, value = pcall(row.getValue)
		f.Value:SetText(ok and value or "?")
		local shown = button and (not row.button.shown or row.button.shown())
		if button then
			button:SetShown(shown and true or false)
			f.Value:ClearAllPoints()
			f.Value:SetPoint("RIGHT", shown and button or f, shown and "LEFT" or "RIGHT", shown and -8 or -RIGHT_GAP, 0)
		end
	end
	return f
end

-- A row whose module is off, or whose checkbox is, is dimmer; it can still be changed.
local function RefreshRow(row)
	local f = row.frame
	if not f then
		return
	end
	f.Refresh()
	local module = row.page and row.page.module
	local off = row.dependsOn and row.dependsOn:GetValue() ~= true
	local moduleOff = module and row.kind ~= "header" and row.setting ~= module.enabledSetting and not module.enabled
	f:SetAlpha((off or moduleOff) and 0.55 or 1)
	if f.Slider then
		f.Slider:EnableMouse(not off)
		f.Less:SetEnabled(not off)
		f.More:SetEnabled(not off)
	end
end

local function RefreshPages()
	for _, button in ipairs(pageButtons) do
		local page = button.page
		local state = ""
		if page.module then
			state = page.module.enabled and (ON .. "\226\128\162|r ") or (OFF .. "\226\128\162|r ")
		end
		button.Text:SetText(state .. page.name)
		button.Picked:SetShown(found == nil and page == current)
	end
end

-- Hides what's laid out, then lays out rows from the top. A search's list also has its pages' titles.
local function Lay(rows)
	for _, row in ipairs(shownRows) do
		row.frame:Hide()
	end
	for _, title in ipairs(titles) do
		title:Hide()
	end
	wipe(shownRows)
	local y, width, usedTitles = 6, content:GetWidth(), 0
	for _, row in ipairs(rows) do
		if row.title then
			usedTitles = usedTitles + 1
			local title = titles[usedTitles]
			if not title then
				title = CreateFrame("Frame", nil, content)
				title:SetHeight(ROW_H.header)
				title.Name = title:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
				title.Name:SetPoint("BOTTOMLEFT", 4, 6)
				titles[usedTitles] = title
			end
			title.Name:SetText(row.title)
			title:ClearAllPoints()
			title:SetPoint("TOPLEFT", 0, -y)
			title:SetWidth(width)
			title:Show()
			y = y + ROW_H.header
		else
			if not row.frame then
				row.frame = Build[row.kind](row)
			end
			local f = row.frame
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", 0, -y)
			f:SetWidth(width)
			f:Show()
			RefreshRow(row)
			shownRows[#shownRows + 1] = row
			y = y + ROW_H[row.kind]
		end
	end
	content:SetHeight(math.max(y + 8, 1))
	scroll:SetVerticalScroll(0)
end

local function ShowPage(page)
	current, found = page, nil
	Options.shownPage = page
	Lay(page.rows)
	RefreshPages()
	frame.Empty:Hide()
end

-- What matches the words: anywhere in a setting's name or (a text) tooltip, by page; the page's own
-- headers aren't results.
local function Search(text)
	local needle = text:lower()
	local rows = {}
	for _, page in ipairs(Options.pages) do
		local first = true
		for _, row in ipairs(page.rows) do
			if row.kind ~= "header" then
				local tip = type(row.tooltip) == "string" and row.tooltip or ""
				if row.name:lower():find(needle, 1, true) or tip:lower():find(needle, 1, true) then
					if first then
						rows[#rows + 1] = { title = page.name }
						first = false
					end
					rows[#rows + 1] = row
				end
			end
		end
	end
	return rows
end

local function ShowSearch(text)
	found = text
	local rows = Search(text)
	Lay(rows)
	RefreshPages()
	frame.Empty:SetShown(rows[1] == nil)
end

local function RunDue(self)
	if searchAt and GetTime() >= searchAt then
		searchAt = nil
		self:SetScript("OnUpdate", nil)
		local text = strtrim(searchBox:GetText() or "")
		if text == "" then
			ShowPage(current)
		else
			ShowSearch(text)
		end
	end
end

local function BuildWindow()
	frame = LT.Window.Create("LefthyToolsSettingsFrame", L["LefthyTools settings"], WIDTH, HEIGHT)
	-- Blizzard's panel closing goes back to the game menu, which first closes what Escape would close:
	-- this window too, though it may have just been opened from that panel. So it comes straight back.
	local panelClosedAt
	if EventRegistry then
		EventRegistry:RegisterCallback("SettingsPanel.OnHide", function() panelClosedAt = GetTime() end, frame)
	end
	frame:HookScript("OnHide", function()
		if panelClosedAt == GetTime() then
			panelClosedAt = nil
			C_Timer.After(0, function() frame:Show() end)
		end
	end)
	local inset = frame.Inset
	local side = CreateFrame("Frame", nil, frame)
	side:SetPoint("TOPLEFT", inset, "TOPLEFT", 6, -6)
	side:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 6, 6)
	side:SetWidth(SIDEBAR - 12)

	searchBox = CreateFrame("EditBox", nil, side, "InputBoxTemplate")
	searchBox:SetHeight(22)
	searchBox:SetPoint("TOPLEFT", 6, -2)
	searchBox:SetPoint("TOPRIGHT", -16, -2)
	searchBox:SetAutoFocus(false)
	searchBox:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	searchBox:SetScript("OnEnterPressed", searchBox.ClearFocus)
	frame.SearchHint = side:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	frame.SearchHint:SetPoint("LEFT", searchBox, "LEFT", 2, 0)
	frame.SearchHint:SetText(L["Search"])
	searchBox:SetScript("OnTextChanged", function(self)
		local text = self:GetText() or ""
		frame.SearchHint:SetShown(text == "")
		clearButton:SetShown(text ~= "")
		searchAt = GetTime() + SEARCH_GAP
		frame:SetScript("OnUpdate", RunDue)
	end)
	clearButton = CreateFrame("Button", nil, side)
	clearButton:SetSize(16, 16)
	clearButton:SetPoint("LEFT", searchBox, "RIGHT", 2, 0)
	clearButton:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
	clearButton:SetScript("OnClick", function()
		searchBox:SetText("")
		searchBox:ClearFocus()
		searchAt = nil
		ShowPage(current)
	end)
	clearButton:Hide()
	frame.Clear, frame.SearchBox = clearButton, searchBox

	for i, page in ipairs(Options.pages) do
		local button = CreateFrame("Button", nil, side)
		button.page = page
		button:SetSize(SIDEBAR - 12, PAGE_H)
		button:SetPoint("TOPLEFT", 0, -30 - (i - 1) * PAGE_H)
		button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		button.Picked = button:CreateTexture(nil, "BACKGROUND")
		button.Picked:SetAllPoints()
		button.Picked:SetColorTexture(1, 0.82, 0, 0.2)
		button.Text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		button.Text:SetPoint("LEFT", 8, 0)
		button.Text:SetPoint("RIGHT", -4, 0)
		button.Text:SetJustifyH("LEFT")
		button:SetScript("OnClick", function()
			searchBox:SetText("")
			searchBox:ClearFocus()
			searchAt = nil
			ShowPage(page)
		end)
		pageButtons[i] = button
	end

	local split = frame:CreateTexture(nil, "ARTWORK")
	split:SetColorTexture(1, 1, 1, 0.1)
	split:SetWidth(1)
	split:SetPoint("TOP", inset, "TOPLEFT", SIDEBAR, -6)
	split:SetPoint("BOTTOM", inset, "BOTTOMLEFT", SIDEBAR, 6)

	scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", SIDEBAR + 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -26, 6)
	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(WIDTH - SIDEBAR - 56, 10)
	scroll:SetScrollChild(content)
	frame.Empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	frame.Empty:SetPoint("TOP", scroll, "TOP", 0, -30)
	frame.Empty:SetText(L["No setting found"])
	frame.Empty:Hide()
	frame:HookScript("OnShow", function()
		if found then
			ShowSearch(found)
		elseif current then
			ShowPage(current)
		end
	end)
end

-- A setting changed, here or by a command: whoever shows it follows; a module's switch, the pages too.
function Options.SettingChanged(setting)
	if not (frame and frame:IsShown()) then
		return
	end
	for _, row in ipairs(shownRows) do
		RefreshRow(row)
	end
	RefreshPages()
end

function Options.Open(page)
	if not frame then
		BuildWindow()
	end
	current = page or current or Options.pages[1]
	found = nil
	searchBox:SetText("")
	searchAt = nil
	frame:SetScript("OnUpdate", nil)
	frame:Show()
	if frame.Raise then
		frame:Raise()
	end
	ShowPage(current)
end

-- For whoever wants to know what's in it.
function Options.Frame()
	return frame
end
