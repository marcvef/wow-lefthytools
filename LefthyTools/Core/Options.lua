local _, ns = ...
local LT = ns.LT
local L = ns.L

BINDING_HEADER_LEFTHYTOOLS = "LefthyTools"

-- The settings' data: pages (an overview, one per module) of rows, each row what the window needs to
-- draw it, and setting objects that read and write the module's saved table. The window itself is
-- SettingsWindow.lua. Not Blizzard's settings list: it reuses its rows from page to page, so our pages
-- could leave its own (Social, Audio) running tainted, and the game blamed us for what they do then
-- (seen in friends' reports: IsUserOAuthed, Frame:SetPoint with the panel open). Blizzard's AddOns list
-- only has a small page of its own with a button to this window.

local Options = {}
LT.Options = Options
Options.pages = {}      -- the overview, then the modules' pages
Options.registered = {} -- variable -> setting
Options.buttons = {}    -- a button's name -> its row
Options.headers = {}    -- every section header's text

function Options.Seconds(value)
	-- 0.25 -> "0.25 s", 1.50 -> "1.5 s", 3.00 -> "3 s" ("1,5 s" in German)
	return LT.Decimal((string.format("%.2f", value):gsub("%.?0+$", ""))) .. " s"
end

function Options.Percent(value)
	return string.format("%d%%", math.floor(value * 100 + 0.5))
end

---------------------------------------------------------------------------
-- A setting: what a row shows and changes, and what slash commands go through (LT:SetModuleSetting).
-- Every change runs the callback (the module's OnSettingChanged) and updates the rows showing it.
---------------------------------------------------------------------------

local SettingMethods = {}
SettingMethods.__index = SettingMethods

function SettingMethods:GetValue()
	return self.get()
end

function SettingMethods:SetValue(value)
	if self.get() ~= value then
		self.set(value)
		self:NotifyUpdate()
	end
end

-- The value may have changed: everyone who shows it, and the module, hear.
function SettingMethods:NotifyUpdate()
	self.uiUpdates = self.uiUpdates + 1
	if self.callback then
		self.callback(self, self.get())
	end
	if Options.SettingChanged then
		Options.SettingChanged(self)
	end
end

function SettingMethods:SetValueChangedCallback(callback)
	self.callback = callback
end

-- At its default (a setting without one, like a module's switch, always is). Numbers within a hair:
-- a slider's steps are rounded.
function SettingMethods:IsDefault()
	local default, value = self.default, self.get()
	if default == nil then
		return true
	end
	if type(default) == "number" and type(value) == "number" then
		return math.abs(value - default) < 1e-6
	end
	return value == default
end

-- Back to its default, like any change: the module and whoever shows it hear.
function SettingMethods:Reset()
	if not self:IsDefault() then
		self:SetValue(self.default)
	end
end

local function NewSetting(variable, name, tooltip, get, set)
	local setting = setmetatable({ variable = variable, name = name, tooltip = tooltip, get = get, set = set, uiUpdates = 0 },
		SettingMethods)
	Options.registered[variable] = setting
	return setting
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

-- Kept in module.settings, so slash commands and resets go through the setting too and an open page follows.
local function Keep(builder, setting, id)
	setting:SetValueChangedCallback(builder.onChange)
	builder.module.settings = builder.module.settings or {}
	builder.module.settings[id] = setting
	return setting
end

local function AddRow(builder, row)
	row.page = builder.page
	builder.page.rows[#builder.page.rows + 1] = row
	return row
end

function Builder:Header(text)
	Options.headers[#Options.headers + 1] = text
	AddRow(self, { kind = "header", name = text })
end

-- A setting whose value lives in a table (see Describe for opts). A value not saved yet takes the default.
function Builder:Register(key, name, tooltip, opts)
	local tbl, default, id, variable = Describe(self, key, opts or {})
	if tbl[key] == nil then
		tbl[key] = default
	end
	local setting = NewSetting(variable, name, tooltip, function() return tbl[key] end, function(value) tbl[key] = value end)
	if type(default) ~= "table" then
		setting.default = default -- (what Reset goes back to; nil: none)
	end
	return Keep(self, setting, id)
end

function Builder:Checkbox(key, name, tooltip, opts)
	local setting = self:Register(key, name, tooltip, opts)
	AddRow(self, { kind = "checkbox", name = name, tooltip = tooltip, setting = setting })
	return setting
end

function Builder:Slider(key, name, tooltip, minValue, maxValue, step, formatter, opts)
	local setting = self:Register(key, name, tooltip, opts)
	setting.sliderOptions = { min = minValue, max = maxValue, step = step, formatter = formatter }
	AddRow(self, { kind = "slider", name = name, tooltip = tooltip, setting = setting, min = minValue, max = maxValue,
		step = step, formatter = formatter })
	return setting
end

-- A checkbox and, under it, a slider that's greyed out while the checkbox is off. cbOpts/sliderOpts as for Register.
function Builder:CheckboxSlider(cbKey, cbName, cbTooltip, sliderKey, sliderName, sliderTooltip, minValue, maxValue, step,
		formatter, cbOpts, sliderOpts)
	local cbSetting = self:Checkbox(cbKey, cbName, cbTooltip, cbOpts)
	local sliderSetting = self:Slider(sliderKey, sliderName, sliderTooltip, minValue, maxValue, step, formatter, sliderOpts)
	self.page.rows[#self.page.rows].dependsOn = cbSetting
	return cbSetting, sliderSetting
end

-- Free text. opts.maxLetters limits the length.
function Builder:TextInput(key, name, tooltip, opts)
	local setting = self:Register(key, name, tooltip, opts)
	setting.maxLetters = opts and opts.maxLetters
	AddRow(self, { kind = "text", name = name, tooltip = tooltip, setting = setting, maxLetters = setting.maxLetters })
	return setting
end

-- One of a few values, as a dropdown; the module's db keeps the value itself, the setting its position
-- among them. LT:SetModuleSetting takes the value too: module.choices[id] finds its position.
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
	if tbl[key] == nil then
		tbl[key] = default
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
	local setting = NewSetting(variable, name, tooltip, Get, Set)
	setting.proxy, setting.values, setting.default = true, values, IndexOf(default) or 1
	Keep(self, setting, id)
	self.module.choices = self.module.choices or {}
	self.module.choices[id] = IndexOf
	AddRow(self, { kind = "choice", name = name, tooltip = tooltip, setting = setting, values = values })
	return setting
end

function Builder:Button(name, buttonText, onClick, tooltip)
	local row = AddRow(self, { kind = "button", name = name, text = buttonText, onClick = onClick, tooltip = tooltip })
	Options.buttons[name] = row
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

---------------------------------------------------------------------------
-- The pages: an overview (module switches, info) and one per module.
---------------------------------------------------------------------------

local function NewPage(name, module)
	local page = { name = name, module = module, rows = {} }
	Options.pages[#Options.pages + 1] = page
	return page
end

-- The overview: a switch per module (LT.db.modules is the single source of truth; keybindings and
-- slash commands go through the switch's setting, LT:SetModuleEnabled), then the Info rows.
local function BuildOverview(page)
	local function Row(row)
		row.page = page
		page.rows[#page.rows + 1] = row
		return row
	end
	Options.headers[#Options.headers + 1] = L["Modules"]
	Row({ kind = "header", name = L["Modules"] })
	for _, m in ipairs(LT.modules) do
		local tooltip = m.description .. "\n\n" .. L["Settings: LefthyTools > %s"]:format(m.title)
		if LT.db.modules[m.key] == nil then
			LT.db.modules[m.key] = m.defaultEnabled
		end
		local setting = NewSetting("LefthyTools_module_" .. m.key, m.title, tooltip,
			function() return LT.db.modules[m.key] end, function(value) LT.db.modules[m.key] = value end)
		setting:SetValueChangedCallback(function()
			LT:ApplyModuleState(m)
		end)
		Row({ kind = "checkbox", name = m.title, tooltip = tooltip, setting = setting, module = m })
		m.enabledSetting = setting
	end

	Options.headers[#Options.headers + 1] = L["General"]
	Row({ kind = "header", name = L["General"] })
	local combineTip = L["One LefthyTools button on the minimap's edge instead of one per module: a click opens a list with the modules' buttons. Off: each module's button on the edge as before."]
	local combine = NewSetting("LefthyTools_minimapCombined", L["Combine minimap buttons"], combineTip,
		function() return LT.db.minimapCombined ~= false end, function(value) LT.db.minimapCombined = value end)
	combine.default = true
	combine:SetValueChangedCallback(function()
		LT.Window.Dock.Lay()
	end)
	Row({ kind = "checkbox", name = L["Combine minimap buttons"], tooltip = combineTip, setting = combine })

	Options.headers[#Options.headers + 1] = L["Info"]
	Row({ kind = "header", name = L["Info"] })
	Row({ kind = "info", name = L["Version"],
		tooltip = L["The installed LefthyTools build. 0.4.0 is a release, 0.4.0-3-g1a2b3c4 is three changes after it."],
		getValue = function() return LT.version end })
	Row({ kind = "info", name = L["Updates"], tooltip = Options.UpdateTooltip, getValue = Options.UpdateStatus }) -- (a function: built on hover)
	local whatsNew = Row({ kind = "button", name = L["What's new"], text = L["Show"], onClick = function() LT.WhatsNew.Show(false) end,
		tooltip = L["Every change to LefthyTools, newest first. After an update this opens by itself once."] })
	Options.buttons[L["What's new"]] = whatsNew
	Row({ kind = "info", name = L["Errors"],
		tooltip = L["LefthyTools' own Lua errors, kept across sessions until you clear them. Show lists them, ready to copy; the list can clear them too."],
		getValue = Options.ErrorStatus,
		button = { text = L["Show"], onClick = function() LT.Errors.Show() end, shown = function() return LT.Errors.Count() > 0 end } })
end

---------------------------------------------------------------------------
-- What changed and what's new
---------------------------------------------------------------------------

-- How many of the page's settings aren't at their default.
function Options.Changed(page)
	local count = 0
	for _, row in ipairs(page.rows) do
		if row.setting and not row.setting:IsDefault() then
			count = count + 1
		end
	end
	return count
end

-- A page's settings back to their defaults: the module's own reset where it has one (Mirage's
-- ResetSettings, as /mirage reset), else each setting the page shows, through the setting. Nothing
-- else in its saved table changes (positions, lists, what it has learned), nor whether the module is
-- on. The window is told once, at the end.
function Options.ResetPage(page)
	local m = page.module
	LT.Trail((m and m.key or "overview") .. " page reset")
	Options.holding = true
	if m and type(m.ResetSettings) == "function" then
		LT.SafeCall(m, "ResetSettings")
	else
		for _, row in ipairs(page.rows) do
			if row.setting then
				row.setting:Reset()
			end
		end
	end
	Options.holding = nil
	if Options.SettingChanged then
		Options.SettingChanged()
	end
end

-- "New": settings the account hasn't seen yet. LefthyToolsDB.settingsSeen = { [variable] = true }
-- keeps what was shown when its page opened. Without that table (a fresh install, or the first build
-- with it) everything counts as seen, so only what later builds add is new. row.new: a "New" tag on
-- the row; page.new: one in the sidebar. Runs once, at login (SetupOptions).
function Options.FindNew()
	local seen = LT.db.settingsSeen
	local first = type(seen) ~= "table"
	if first then
		seen = {}
		LT.db.settingsSeen = seen
	end
	for _, page in ipairs(Options.pages) do
		page.new = nil
		for _, row in ipairs(page.rows) do
			local variable = row.setting and row.setting.variable
			if variable then
				if first then
					seen[variable] = true
				end
				row.new = not seen[variable] or nil
				page.new = page.new or row.new
			end
		end
	end
end

-- The page is open: what's new on it counts as seen from now on. Its tags stay while it's open.
function Options.Seen(page)
	local seen = LT.db.settingsSeen
	for _, row in ipairs(page.rows) do
		if row.new then
			seen[row.setting.variable] = true
		end
	end
	page.new = nil
end

-- The page was left: its tags go.
function Options.Forget(page)
	for _, row in ipairs(page.rows) do
		row.new = nil
	end
end

-- A module's own page, filled by its BuildOptions through a Builder; first its switch, at its foot a
-- way to reset it (when it has settings with a default).
local function BuildModulePage(m)
	local page = NewPage(m.title, m)
	m.category = page
	page.rows[1] = { kind = "checkbox", name = L["Switched on"], tooltip = m.description, setting = m.enabledSetting, page = page, module = m }
	local builder = setmetatable({
		module = m,
		page = page,
		onChange = function()
			LT.Trail(m.key .. " setting changed")
			LT.SafeCall(m, "OnSettingChanged")
		end,
	}, Builder)
	LT.SafeCall(m, "BuildOptions", builder)
	for _, row in ipairs(page.rows) do
		if row.setting and row.setting.default ~= nil then
			AddRow(builder, { kind = "reset", name = L["Reset this page"],
				tooltip = L["Every setting on this page back to its default. It asks first. Whether the module is on stays as it is."] })
			break
		end
	end
end

-- Blizzard's AddOns list: a page of our own (a canvas, none of its shared rows) with a way to the window.
local function AddBlizzardPage()
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
		return
	end
	local panel = CreateFrame("Frame")
	panel.name = "LefthyTools"
	local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("TOPLEFT", 16, -16)
	text:SetPoint("RIGHT", -16, 0)
	text:SetJustifyH("LEFT")
	text:SetText(L["LefthyTools has its own settings window."])
	local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	button:SetSize(220, 24)
	button:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -12)
	button:SetText(L["Open LefthyTools settings"])
	button:SetScript("OnClick", function() LT:OpenSettings() end)
	Options.blizzardButton = button
	Options.blizzardCategory = Settings.RegisterCanvasLayoutCategory(panel, "LefthyTools")
	Settings.RegisterAddOnCategory(Options.blizzardCategory)
end

function ns.SetupOptions()
	LT.category = NewPage(L["Overview"])
	BuildOverview(LT.category)
	for _, m in ipairs(LT.modules) do
		if type(m.BuildOptions) == "function" then
			BuildModulePage(m)
		end
	end
	Options.FindNew()
	AddBlizzardPage()
end

-- Opens the overview, or a module's page when given a module. Any time: it's a window of our own, so
-- neither a fight nor gamepad mode stands in the way.
function LT:OpenSettings(m)
	Options.Open((m and m.category) or self.category)
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
	LT.Trail("/lefthy " .. cmd) -- (only the word: what follows can be anything typed)
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
