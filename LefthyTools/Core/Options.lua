local _, ns = ...
local LT = ns.LT
local L = ns.L

BINDING_HEADER_LEFTHYTOOLS = "LefthyTools"

local Options = {}
LT.Options = Options

function Options.Seconds(value)
	-- 0.25 -> "0.25 s", 1.50 -> "1.5 s", 3.00 -> "3 s" ("1,5 s" in German)
	return LT.Decimal((string.format("%.2f", value):gsub("%.?0+$", ""))) .. " s"
end

function Options.Percent(value)
	return string.format("%d%%", math.floor(value * 100 + 0.5))
end

---------------------------------------------------------------------------
-- Builder handed to module:BuildOptions(). Setting variables are namespaced as
-- "LefthyTools_<module>_<id>" and write straight into the module's db.
---------------------------------------------------------------------------

local Builder = {}
Builder.__index = Builder

-- Where a setting keeps its value and what it's called. opts (optional): tbl = the table holding the
-- value (default the module's db), default = its default (default module.defaults[key]), id = a
-- unique id (default key). Returns tbl, default, id and the variable "LefthyTools_<module>_<id>".
local function Describe(builder, key, opts)
	local default = opts.default
	if default == nil then
		default = builder.module.defaults[key]
	end
	local id = opts.id or key
	return opts.tbl or builder.module.db, default, id, "LefthyTools_" .. builder.module.key .. "_" .. id
end

-- Every change runs the module's OnSettingChanged. Kept in module.settings, so slash commands and
-- resets go through the setting too (LT:SetModuleSetting) and an open settings page follows.
local function Keep(builder, setting, id)
	setting:SetValueChangedCallback(builder.onChange)
	builder.module.settings = builder.module.settings or {}
	builder.module.settings[id] = setting
	return setting
end

-- A slider's range and step, and the label at its right end (formatter(value) -> text).
local function SliderOptions(minValue, maxValue, step, formatter)
	local options = Settings.CreateSliderOptions(minValue, maxValue, step)
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter)
	return options
end

function Builder:Header(text)
	self.layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
end

-- A setting whose value lives in a table (see Describe for opts).
function Builder:Register(key, name, varType, opts)
	local tbl, default, id, variable = Describe(self, key, opts or {})
	local setting = Settings.RegisterAddOnSetting(self.category, variable, key, tbl, varType or type(default), name, default)
	return Keep(self, setting, id)
end

function Builder:Checkbox(key, name, tooltip, opts)
	local setting = self:Register(key, name, "boolean", opts)
	Settings.CreateCheckbox(self.category, setting, tooltip)
	return setting
end

function Builder:Slider(key, name, tooltip, minValue, maxValue, step, formatter, opts)
	local setting = self:Register(key, name, "number", opts)
	Settings.CreateSlider(self.category, setting, SliderOptions(minValue, maxValue, step, formatter), tooltip)
	return setting
end

-- A checkbox and a slider in one row (Blizzard's CreateSettingsCheckboxSliderInitializer); the
-- slider is greyed out while the checkbox is off. cbOpts/sliderOpts as for Register.
function Builder:CheckboxSlider(cbKey, cbName, cbTooltip, sliderKey, sliderName, sliderTooltip, minValue, maxValue, step,
		formatter, cbOpts, sliderOpts)
	local cbSetting = self:Register(cbKey, cbName, "boolean", cbOpts)
	local sliderSetting = self:Register(sliderKey, sliderName, "number", sliderOpts)
	local options = SliderOptions(minValue, maxValue, step, formatter)
	if CreateSettingsCheckboxSliderInitializer then
		self.layout:AddInitializer(CreateSettingsCheckboxSliderInitializer(cbSetting, cbName, cbTooltip,
			sliderSetting, options, sliderName, sliderTooltip))
	else
		Settings.CreateCheckbox(self.category, cbSetting, cbTooltip)
		Settings.CreateSlider(self.category, sliderSetting, options, sliderTooltip)
	end
	return cbSetting, sliderSetting
end

-- Free text. Blizzard's settings list has no text field, so this uses our own list element
-- (LefthyToolsSettingsTextTemplate in Options.xml). opts.maxLetters limits the length.
function Builder:TextInput(key, name, tooltip, opts)
	local setting = self:Register(key, name, "string", opts)
	local data = Settings.CreateSettingInitializerData(setting, { maxLetters = opts and opts.maxLetters }, tooltip)
	local initializer = Settings.CreateSettingInitializer("LefthyToolsSettingsTextTemplate", data)
	initializer:AddSearchTags(name)
	self.layout:AddInitializer(initializer)
	return setting
end

-- One of a few values, as a slider whose label names the value; the module's db keeps the value
-- itself (a proxy setting maps it to the slider's position). Not a dropdown: a Blizzard menu
-- opened from addon settings taints gamepad mode's focus manager, and a protected click through
-- it later (a role check's Accept) is blocked; see LT.Window.AddPicker. LT:SetModuleSetting takes
-- the value too: module.choices[id] finds its position.
-- values: { { value, label }, ... } in display order.
function Builder:Choice(key, name, tooltip, values, opts)
	local tbl, default, id, variable = Describe(self, key, opts or {})
	local function IndexOf(value)
		for i, v in ipairs(values) do
			if v[1] == value then
				return i
			end
		end
	end
	local function Get()
		return IndexOf(tbl[key]) or IndexOf(default) or 1
	end
	local function Set(index)
		local v = values[math.floor(index + 0.5)]
		if v then
			tbl[key] = v[1]
		end
	end
	local setting = Settings.RegisterProxySetting(self.category, variable, "number", name, IndexOf(default) or 1, Get, Set)
	Keep(self, setting, id)
	self.module.choices = self.module.choices or {}
	self.module.choices[id] = IndexOf
	Settings.CreateSlider(self.category, setting, SliderOptions(1, #values, 1, function(index)
		local v = values[math.floor(index + 0.5)]
		return v and v[2] or ""
	end), tooltip)
	return setting
end

function Builder:Button(name, buttonText, onClick, tooltip)
	self.layout:AddInitializer(CreateSettingsButtonInitializer(name, buttonText, onClick, tooltip, true))
end

-- The text field's list element, built on Blizzard's SettingsControlMixin (Init subscribes
-- OnSettingValueChanged to the setting). Commits when focus leaves: Enter, or a click elsewhere
-- (GLOBAL_MOUSE_DOWN clears keyboard focus). Tab does nothing here: InputBoxTemplate's
-- EditBox_OnTabPressed needs a nextEditBox. Escape restores the saved text.
LefthyToolsSettingsTextMixin = CreateFromMixins(SettingsControlMixin or {})

function LefthyToolsSettingsTextMixin:OnLoad()
	SettingsControlMixin.OnLoad(self)
	local box = self.EditBox
	box:SetScript("OnEnterPressed", box.ClearFocus)
	box:SetScript("OnEscapePressed", function()
		local setting = self.data and self:GetSetting()
		box:SetText(setting and setting:GetValue() or "")
		box:ClearFocus()
	end)
	box:HookScript("OnEditFocusLost", function()
		self:Commit()
	end)
end

function LefthyToolsSettingsTextMixin:Init(initializer)
	SettingsControlMixin.Init(self, initializer)
	local options = initializer:GetOptions()
	self.EditBox:SetMaxLetters(options and options.maxLetters or 0)
	self:SetValue(self:GetSetting():GetValue())
	self.EditBox:SetCursorPosition(0)
end

-- Also called when the value changes elsewhere, e.g. by a slash command while the panel is open.
function LefthyToolsSettingsTextMixin:SetValue(value)
	if not self.EditBox:HasFocus() then
		self.EditBox:SetText(value or "")
	end
end

function LefthyToolsSettingsTextMixin:Commit()
	local setting = self.data and self:GetSetting()
	if setting then
		local text = strtrim(self.EditBox:GetText() or "")
		if text ~= setting:GetValue() then
			setting:SetValue(text)
		end
	end
end

function LefthyToolsSettingsTextMixin:Release()
	self.EditBox:ClearFocus() -- commits a pending edit while self.data is still set
	SettingsControlMixin.Release(self)
end

---------------------------------------------------------------------------
-- Info rows on the overview page (version, updates): a label, and a value that is read every
-- time the settings list shows the row (Init), so it's current whenever the page is opened.
-- Optionally a button at the right end (data.button = { text, onClick, shown }). Template in
-- Options.xml.
---------------------------------------------------------------------------

LefthyToolsSettingsInfoMixin = CreateFromMixins(SettingsListElementMixin or {})

function LefthyToolsSettingsInfoMixin:OnLoad()
	SettingsListElementMixin.OnLoad(self)
	self.Button = CreateFrame("Button", nil, self, "UIPanelButtonTemplate")
	self.Button:SetSize(100, 22)
	self.Button:SetPoint("RIGHT", self, "RIGHT", -10, 0)
	self.Button:SetScript("OnClick", function()
		if self.button then
			self.button.onClick()
		end
	end)
end

function LefthyToolsSettingsInfoMixin:Init(initializer)
	SettingsListElementMixin.Init(self, initializer)
	local data = initializer:GetData()
	local ok, value = pcall(data.getValue)
	self.Value:SetText(ok and value or "?")
	self.button = data.button -- (rows are pooled: another row may have had one)
	local shown = data.button and (not data.button.shown or data.button.shown())
	self.Button:SetShown(shown and true or false)
	if shown then
		self.Button:SetText(data.button.text)
	end
end

local GREEN, ORANGE, GRAY = "|cff80ff80", "|cffffa040", "|cffa0a0a0"

-- Addons can't go online: what Beacon heard from friends who run LefthyTools is all there is.
function Options.UpdateStatus()
	if LT.newerVersion then
		local restart = LT.newerFiles and LT.newerFiles ~= LT.FILES
		local text = restart and L["Newer version available: %s (needs a game restart)"] or L["Newer version available: %s"]
		return ORANGE .. text:format(LT.newerVersion) .. "|r"
	end
	local beacon = LT:GetModule("beacon")
	if not (beacon and beacon.enabled) then
		return GRAY .. L["Unknown (Beacon is off)"] .. "|r"
	end
	local compared = 0
	for _, peer in pairs(beacon:GetPeers()) do
		if peer.version then
			compared = compared + 1
		end
	end
	if compared == 0 then
		return GRAY .. L["Unknown (no friend with LefthyTools online)"] .. "|r"
	end
	return GREEN .. L["Up to date (compared with %d friend(s))"]:format(compared) .. "|r"
end

-- The Updates row's tooltip, built each time it opens: my build and every Beacon friend's.
function Options.UpdateTooltip()
	local lines = {
		L["LefthyTools can't go online itself: it learns about newer versions from Battle.net friends who use it (Beacon). To update, run Update-LefthyTools.cmd again, then /reload, or restart the game if the update adds files (it says so)."],
		"",
		L["You: %s"]:format(LT.version),
	}
	local beacon = LT:GetModule("beacon")
	if not (beacon and beacon.enabled) then
		lines[#lines + 1] = GRAY .. L["Unknown (Beacon is off)"] .. "|r"
		return table.concat(lines, "\n")
	end
	local list = {}
	for _, peer in pairs(beacon:GetPeers()) do
		if peer.name then
			list[#list + 1] = peer
		end
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	if #list == 0 then
		lines[#lines + 1] = GRAY .. L["No friend with LefthyTools online right now."] .. "|r"
	end
	for _, peer in ipairs(list) do
		local name = LT.Window.ClassColorCode(peer.classFile) .. peer.name .. "|r"
		if not peer.version then
			lines[#lines + 1] = name .. ": " .. GRAY .. L["0.3.0 or older"] .. "|r"
		else
			local compared = LT.CompareVersions(peer.version, LT.version)
			local state = compared == 1 and (ORANGE .. L["newer"]) or compared == -1 and (GRAY .. L["older"])
				or compared == 0 and (GREEN .. L["same"]) or ""
			lines[#lines + 1] = ("%s: %s  %s|r"):format(name, peer.version, state)
		end
	end
	return table.concat(lines, "\n")
end

function Options.ErrorStatus()
	local count = LT.Errors.Count()
	if count == 0 then
		return GREEN .. L["None"] .. "|r"
	end
	return ORANGE .. count .. "|r"
end

local function AddInfoRow(layout, name, tooltip, getValue, button)
	local initializer = Settings.CreateElementInitializer("LefthyToolsSettingsInfoTemplate",
		{ name = name, tooltip = tooltip, getValue = getValue, button = button })
	layout:AddInitializer(initializer)
end

---------------------------------------------------------------------------
-- Settings panel: "LefthyTools" overview (module switches, info) + one sub-page per module,
-- following Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua: only the parent
-- category is passed to RegisterAddOnCategory.
---------------------------------------------------------------------------

-- The overview: a switch per module (LT.db.modules is the single source of truth; keybindings and
-- slash commands go through the switch's setting, LT:SetModuleEnabled), then the Info rows.
local function BuildOverview(category, layout)
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L["Modules"]))
	for _, m in ipairs(LT.modules) do
		local setting = Settings.RegisterAddOnSetting(category, "LefthyTools_module_" .. m.key, m.key,
			LT.db.modules, "boolean", m.title, m.defaultEnabled)
		setting:SetValueChangedCallback(function()
			LT:ApplyModuleState(m)
		end)
		Settings.CreateCheckbox(category, setting,
			m.description .. "\n\n" .. L["Settings: LefthyTools > %s"]:format(m.title))
		m.enabledSetting = setting
	end

	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L["Info"]))
	AddInfoRow(layout, L["Version"],
		L["The installed LefthyTools build. 0.4.0 is a release, 0.4.0-3-g1a2b3c4 is three changes after it."],
		function() return LT.version end)
	AddInfoRow(layout, L["Updates"], Options.UpdateTooltip, Options.UpdateStatus) -- a tooltip function: built on hover
	layout:AddInitializer(CreateSettingsButtonInitializer(L["What's new"], L["Show"], function() LT.WhatsNew.Show(false) end,
		L["Every change to LefthyTools, newest first. After an update this opens by itself once."], true))
	AddInfoRow(layout, L["Errors"],
		L["LefthyTools' own Lua errors, kept across sessions until you clear them. Show lists them, ready to copy; the list can clear them too."],
		Options.ErrorStatus,
		{ text = L["Show"], onClick = function() LT.Errors.Show() end, shown = function() return LT.Errors.Count() > 0 end })
end

-- A module's own page, filled by its BuildOptions through a Builder.
local function BuildModulePage(category, m)
	local sub, subLayout = Settings.RegisterVerticalLayoutSubcategory(category, m.title)
	m.category = sub
	local builder = setmetatable({
		module = m,
		category = sub,
		layout = subLayout,
		onChange = function()
			LT.SafeCall(m, "OnSettingChanged")
		end,
	}, Builder)
	LT.SafeCall(m, "BuildOptions", builder)
end

function ns.SetupOptions()
	if not (Settings and Settings.RegisterVerticalLayoutCategory) then
		return
	end
	local category, layout = Settings.RegisterVerticalLayoutCategory("LefthyTools")
	LT.category = category
	BuildOverview(category, layout)
	for _, m in ipairs(LT.modules) do
		if type(m.BuildOptions) == "function" then
			BuildModulePage(category, m)
		end
	end
	Settings.RegisterAddOnCategory(category)
end

-- Opens the overview, or a module's page when given a module.
function LT:OpenSettings(m)
	local target = (m and m.category) or self.category
	if not target then
		LT.Print("the settings panel isn't available; use /lefthy help.")
		return
	end
	if InCombatLockdown() then
		LT.Print("can't open settings in combat.")
		return
	end
	-- In gamepad mode the settings can't be opened from addon code safely: ShowUIPanel tells the
	-- gamepad's focus manager (FrameControlsManager) about the panel from our code, which taints
	-- it, and a protected click through it later (a role check's Accept) is blocked. The game
	-- menu's own way there is fine.
	if InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() then
		LT.Print("in gamepad mode, open the settings from the game menu: Options > AddOns > LefthyTools"
			.. " (opening them from an addon would block the next role check).")
		return
	end
	Settings.OpenToCategory(target:GetID())
end

-- Minimap addon compartment (## AddonCompartmentFunc).
function LefthyTools_OnAddonCompartmentClick()
	LT:OpenSettings()
end

---------------------------------------------------------------------------
-- /lefthy
--
-- Its words are registered: Core's own below, a module's in the file that does it
-- (LT:AddCommand), so Core doesn't have to know them. "/lefthy <module> ..." goes to the module's
-- OnSlashCommand.
---------------------------------------------------------------------------

local commands = {}  -- word -> run(rest)
local helpLines = {} -- { word, line }, in the order /lefthy lists them

-- "/lefthy <word> ..." runs run(rest), rest being what follows the word, as typed. help is its line
-- in /lefthy's list (nil: not listed, e.g. another word for the same thing), right after the line of
-- the word named by after (default: at the end). Registered when the file loads, so the word works
-- while its module is off too (the command says so where that matters). Not a module's key: the
-- word would hide that module's own commands.
function LT:AddCommand(word, run, help, after)
	commands[word] = run
	if help then
		local at = #helpLines + 1
		for i, line in ipairs(helpLines) do
			if line[1] == after then
				at = i + 1
			end
		end
		table.insert(helpLines, at, { word, help })
	end
end

local function OpenSettings()
	LT:OpenSettings()
end

local function ListModules()
	for _, m in ipairs(LT.modules) do
		LT.Print(string.format("  %s%s|r (%s) - %s", m.enabled and "|cff80ff80" or "|cffff8080",
			m.title, m.key, m.description))
	end
end

local function News()
	LT.WhatsNew.Show(false)
end

LT:AddCommand("", OpenSettings, "/lefthy - open settings")
LT:AddCommand("config", OpenSettings)
LT:AddCommand("options", OpenSettings)
LT:AddCommand("modules", ListModules, "/lefthy modules - list modules")
LT:AddCommand("list", ListModules)
LT:AddCommand("version", function()
	LT.Print("version " .. LT.version .. (LT.newerVersion and (", a friend has the newer " .. LT.newerVersion) or "")
		.. ". " .. LT.UpdateHint(LT.newerVersion and LT.newerFiles))
end, "/lefthy version - the installed LefthyTools version")
LT:AddCommand("errors", function(rest) LT.Errors.Command(rest) end, "/lefthy errors [clear] - LefthyTools' own errors, ready to copy")
LT:AddCommand("news", News, "/lefthy news - what's new in LefthyTools")
LT:AddCommand("whatsnew", News)
LT:AddCommand("changelog", News)

SLASH_LEFTHYTOOLS1 = "/lefthy"
SLASH_LEFTHYTOOLS2 = "/lt"
SlashCmdList.LEFTHYTOOLS = function(msg)
	if not LT.db then
		return
	end
	local cmd, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()
	local target = LT:GetModule(rest:lower())

	if commands[cmd] then
		commands[cmd](rest)
	elseif (cmd == "enable" or cmd == "disable" or cmd == "toggle") and target then
		if cmd == "toggle" then
			LT:ToggleModule(target.key)
		else
			LT:SetModuleEnabled(target.key, cmd == "enable")
		end
	elseif LT:GetModule(cmd) then
		local m = LT:GetModule(cmd)
		if type(m.OnSlashCommand) == "function" then
			m:OnSlashCommand(rest)
		else
			LT:OpenSettings(m)
		end
	else
		for _, line in ipairs(helpLines) do
			LT.Print(line[2])
		end
		LT.Print("/lefthy enable | disable | toggle <module>")
		LT.Print("/lefthy <module> ... - module commands, e.g. /lefthy mirage status")
	end
end
