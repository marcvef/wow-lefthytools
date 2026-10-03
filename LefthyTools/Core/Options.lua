local _, ns = ...
local LT = ns.LT
local L = ns.L

BINDING_HEADER_LEFTHYTOOLS = "LefthyTools"

local Options = {}
LT.Options = Options

function Options.Seconds(value)
	-- 0.25 -> "0.25 s", 1.50 -> "1.5 s", 3.00 -> "3 s" ("1,5 s" in German)
	local text = string.format("%.2f", value):gsub("%.?0+$", "")
	if ns.DECIMAL_COMMA then
		text = text:gsub("%.", ",")
	end
	return text .. " s"
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

function Builder:Header(text)
	self.layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
end

-- opts (optional): tbl = table holding the value (default module.db),
-- default = default value (default module.defaults[key]), id = unique variable id (default key)
function Builder:Register(key, name, varType, opts)
	opts = opts or {}
	local tbl = opts.tbl or self.module.db
	local default = opts.default
	if default == nil then
		default = self.module.defaults[key]
	end
	local variable = "LefthyTools_" .. self.module.key .. "_" .. (opts.id or key)
	local setting = Settings.RegisterAddOnSetting(self.category, variable, key, tbl, varType or type(default), name, default)
	setting:SetValueChangedCallback(self.onChange)
	-- Kept so slash commands and resets go through the setting too (LT:SetModuleSetting).
	self.module.settings = self.module.settings or {}
	self.module.settings[opts.id or key] = setting
	return setting
end

function Builder:Checkbox(key, name, tooltip, opts)
	local setting = self:Register(key, name, "boolean", opts)
	Settings.CreateCheckbox(self.category, setting, tooltip)
	return setting
end

function Builder:Slider(key, name, tooltip, minValue, maxValue, step, formatter, opts)
	local setting = self:Register(key, name, "number", opts)
	local options = Settings.CreateSliderOptions(minValue, maxValue, step)
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter)
	Settings.CreateSlider(self.category, setting, options, tooltip)
	return setting
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

-- values: { { value, label }, ... } in display order.
function Builder:Dropdown(key, name, tooltip, values, opts)
	local setting = self:Register(key, name, nil, opts)
	local function GetOptions()
		local container = Settings.CreateControlTextContainer()
		for _, v in ipairs(values) do
			container:Add(v[1], v[2])
		end
		return container:GetData()
	end
	Settings.CreateDropdown(self.category, setting, GetOptions, tooltip)
	return setting
end

function Builder:Button(name, buttonText, onClick, tooltip)
	self.layout:AddInitializer(CreateSettingsButtonInitializer(name, buttonText, onClick, tooltip, true))
end

-- The text field's list element, built on Blizzard's SettingsControlMixin (Init subscribes
-- OnSettingValueChanged to the setting). Commits when focus leaves (Enter, Tab or a click
-- elsewhere); Escape restores the saved text.
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
-- Settings panel: "LefthyTools" overview (module switches) + one sub-page per module,
-- following Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua: only the parent
-- category is passed to RegisterAddOnCategory.
---------------------------------------------------------------------------

function ns.SetupOptions()
	if not (Settings and Settings.RegisterVerticalLayoutCategory) then
		return
	end

	local category, layout = Settings.RegisterVerticalLayoutCategory("LefthyTools")
	LT.category = category

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

	for _, m in ipairs(LT.modules) do
		if type(m.BuildOptions) == "function" then
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
	Settings.OpenToCategory(target:GetID())
end

-- Minimap addon compartment (## AddonCompartmentFunc).
function LefthyTools_OnAddonCompartmentClick()
	LT:OpenSettings()
end

---------------------------------------------------------------------------
-- /lefthy
---------------------------------------------------------------------------

local function ListModules()
	for _, m in ipairs(LT.modules) do
		LT.Print(string.format("  %s%s|r (%s) - %s", m.enabled and "|cff80ff80" or "|cffff8080",
			m.title, m.key, m.description))
	end
end

SLASH_LEFTHYTOOLS1 = "/lefthy"
SLASH_LEFTHYTOOLS2 = "/lt"
SlashCmdList.LEFTHYTOOLS = function(msg)
	if not LT.db then
		return
	end
	local cmd, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()
	local target = LT:GetModule(rest:lower())

	if cmd == "" or cmd == "config" or cmd == "options" then
		LT:OpenSettings()
	elseif cmd == "modules" or cmd == "list" then
		ListModules()
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
		LT.Print("/lefthy - open settings")
		LT.Print("/lefthy modules - list modules")
		LT.Print("/lefthy enable | disable | toggle <module>")
		LT.Print("/lefthy <module> ... - module commands, e.g. /lefthy mirage status")
	end
end
