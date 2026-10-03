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

-- Core parts that aren't modules (Errors.lua, ...): onLoad(db) runs once the saved variables are
-- there, before the modules initialize; onLogin() at PLAYER_LOGIN, before the modules start.
LT.onLoad, LT.onLogin = {}, {}

function LT.Print(msg, source)
	print("|cffe0b060" .. (source or "LefthyTools") .. "|r: " .. msg)
end

---------------------------------------------------------------------------
-- Version. The repo's TOC holds the base version (e.g. 0.3.0, git tag v0.3.0); install.ps1
-- writes the exact build into the installed copy, like `git describe`:
--   0.3.0               the tagged commit itself
--   0.3.0-12-g1a2b3c4   12 commits later (comparable: more commits = newer)
--   0.3.0-g1a2b3c4      commit count unknown (GitHub couldn't be asked)
--   ...-dirty / -dev    a development install
---------------------------------------------------------------------------

local GetMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
LT.version = GetMetadata and GetMetadata(ADDON, "Version") or "?"

-- major, minor, patch, commits since that version (nil if unknown); nil if not a version.
function LT.ParseVersion(v)
	if type(v) ~= "string" then
		return nil
	end
	local major, minor, patch, rest = v:match("^(%d+)%.(%d+)%.(%d+)(.*)$")
	if not major then
		return nil
	end
	local count
	if rest == "" then
		count = 0
	else
		count = tonumber(rest:match("^%-(%d+)%-g%x+"))
	end
	return tonumber(major), tonumber(minor), tonumber(patch), count
end

-- The newest LefthyTools build seen from a friend (Beacon), if newer than ours. Addons can't go
-- online, so friends are the only way to learn about updates.
function LT:NoteFriendVersion(version)
	if LT.CompareVersions(version, LT.version) == 1
		and (not LT.newerVersion or LT.CompareVersions(version, LT.newerVersion) == 1) then
		LT.newerVersion = version
	end
end

-- 1 if a is newer than b, -1 if older, 0 if the same; nil if that can't be told.
function LT.CompareVersions(a, b)
	local a1, a2, a3, ac = LT.ParseVersion(a)
	local b1, b2, b3, bc = LT.ParseVersion(b)
	if not a1 or not b1 then
		return nil
	end
	for _, pair in ipairs({ { a1, b1 }, { a2, b2 }, { a3, b3 } }) do
		if pair[1] ~= pair[2] then
			return pair[1] > pair[2] and 1 or -1
		end
	end
	if ac == nil or bc == nil then
		return nil
	end
	return ac > bc and 1 or (ac < bc and -1 or 0)
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
	-- Tell an open settings page about every reset value (it would keep showing the old ones).
	for _, setting in pairs(m.settings or {}) do
		setting:NotifyUpdate()
	end
end

-- Changes a setting the way its checkbox or slider would: through the setting object, so an
-- open settings page shows the new value and OnSettingChanged runs. id is the setting's id
-- (its key, or the opts.id given to the builder); tbl/key say where it lives if there is no
-- settings panel (default m.db[id]).
function LT:SetModuleSetting(m, id, value, tbl, key)
	local setting = m.settings and m.settings[id]
	if setting then
		setting:SetValue(value)
	else
		(tbl or m.db)[key or id] = value
		SafeCall(m, "OnSettingChanged")
	end
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
		LT.freshInstall = type(LefthyToolsDB) ~= "table" -- no saved settings yet: a new install
		LefthyToolsDB = type(LefthyToolsDB) == "table" and LefthyToolsDB or {}
		local db = LefthyToolsDB
		db.modules = type(db.modules) == "table" and db.modules or {}
		db.settings = type(db.settings) == "table" and db.settings or {}
		LT.db = db
		for _, fn in ipairs(LT.onLoad) do
			local ok, err = pcall(fn, db)
			if not ok then
				geterrorhandler()(err)
			end
		end

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
		for _, fn in ipairs(LT.onLogin) do
			local ok, err = pcall(fn)
			if not ok then
				geterrorhandler()(err)
			end
		end
		for _, m in ipairs(LT.modules) do
			if LT.db.modules[m.key] then
				m.enabled = true
				SafeCall(m, "OnEnable")
			end
		end
	end
end)
