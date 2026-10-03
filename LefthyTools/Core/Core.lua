local ADDON, ns = ...

-- LefthyTools: a collection of small UI modules for WoW: Forever.
-- Each module registers itself with LT:NewModule() and implements any of:
--   module:OnInitialize()          once, after saved settings are loaded (module.db is ready)
--   module:OnEnable()              at login if enabled, or when switched on later
--   module:OnDisable()             when switched off at runtime
--   module:BuildOptions(builder)   fill the module's page in the settings panel
--   module:OnSettingChanged()      a setting on the module's page changed
--   module:OnSlashCommand(msg)     "/lefthy <module> ..." (modules may add their own alias too)

local LT = {}
ns.LT = LT
_G.LefthyTools = LT

LT.modules = {}
local moduleByKey = {}
local loggedIn = false

function LT.Print(msg, source)
	print("|cffe0b060" .. (source or "LefthyTools") .. "|r: " .. msg)
end

---------------------------------------------------------------------------
-- Modules
---------------------------------------------------------------------------

local Module = {}
Module.__index = Module

function Module:Print(msg)
	LT.Print(msg, self.title)
end

function Module:IsEnabled()
	return self.enabled
end

function LT:NewModule(key, info)
	assert(type(key) == "string" and not moduleByKey[key], "LefthyTools: bad or duplicate module key " .. tostring(key))
	local m = setmetatable({
		key = key,
		title = info.title or key,
		description = info.description or "",
		defaults = info.defaults or {},
		defaultEnabled = info.defaultEnabled ~= false,
		enabled = false,
	}, Module)
	moduleByKey[key] = m
	self.modules[#self.modules + 1] = m
	return m
end

function LT:GetModule(key)
	return moduleByKey[key]
end

local function SafeCall(m, method, ...)
	local fn = m[method]
	if type(fn) ~= "function" then
		return
	end
	local ok, err = pcall(fn, m, ...)
	if not ok then
		geterrorhandler()(err)
	end
end
LT.SafeCall = SafeCall

---------------------------------------------------------------------------
-- Saved settings: LefthyToolsDB = { modules = { key = bool }, settings = { key = {...} } }
---------------------------------------------------------------------------

local function ApplyDefaults(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then
				dst[k] = {}
			end
			ApplyDefaults(dst[k], v)
		elseif type(dst[k]) ~= type(v) then
			dst[k] = v
		end
	end
end

-- Keeps the same tables: the settings panel holds references to them.
function LT:ResetModuleSettings(m)
	for k, v in pairs(m.db) do
		if type(v) == "table" then
			wipe(v)
		else
			m.db[k] = nil
		end
	end
	ApplyDefaults(m.db, m.defaults)
end

---------------------------------------------------------------------------
-- Enable / disable
---------------------------------------------------------------------------

-- Brings a module's running state in line with LT.db.modules. Safe to call repeatedly.
function LT:ApplyModuleState(m)
	local want = self.db.modules[m.key] == true
	if want == m.enabled or not loggedIn then
		return
	end
	m.enabled = want
	SafeCall(m, want and "OnEnable" or "OnDisable")
	m:Print(want and "enabled." or "disabled.")
end

function LT:SetModuleEnabled(key, on)
	local m = moduleByKey[key]
	if not m then
		return
	end
	on = on and true or false
	local setting = m.enabledSetting
	if setting and setting:GetValue() ~= on then
		setting:SetValue(on) -- updates the DB and the settings panel, then calls ApplyModuleState
	else
		self.db.modules[key] = on
	end
	self:ApplyModuleState(m)
end

function LT:ToggleModule(key)
	local m = moduleByKey[key]
	if m then
		self:SetModuleEnabled(key, not m.enabled)
	end
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, arg)
	if event == "ADDON_LOADED" and arg == ADDON then
		LefthyToolsDB = type(LefthyToolsDB) == "table" and LefthyToolsDB or {}
		local db = LefthyToolsDB
		db.modules = type(db.modules) == "table" and db.modules or {}
		db.settings = type(db.settings) == "table" and db.settings or {}
		LT.db = db

		for _, m in ipairs(LT.modules) do
			if type(db.modules[m.key]) ~= "boolean" then
				db.modules[m.key] = m.defaultEnabled
			end
			db.settings[m.key] = type(db.settings[m.key]) == "table" and db.settings[m.key] or {}
			ApplyDefaults(db.settings[m.key], m.defaults)
			m.db = db.settings[m.key]
			SafeCall(m, "OnInitialize")
		end

		ns.SetupOptions()
	elseif event == "PLAYER_LOGIN" then
		loggedIn = true
		for _, m in ipairs(LT.modules) do
			if LT.db.modules[m.key] then
				m.enabled = true
				SafeCall(m, "OnEnable")
			end
		end
	end
end)
