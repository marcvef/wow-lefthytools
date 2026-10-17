local ADDON, ns = ...
local L = ns.L

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
-- Secret values. Forever hides many API answers from addons (health always, names and casts while
-- restricted): a secret can be stored and passed on, but comparing it, doing arithmetic with it or
-- using it as a table key is an error. These are for code that only wants what it may read.
---------------------------------------------------------------------------

-- true if v is a secret (never on a client without them).
LT.IsSecret = issecretvalue or function() return false end

-- true if v is there and not a secret.
function LT.Readable(v)
	return v ~= nil and not LT.IsSecret(v)
end

-- What f(...) answers first, if the call works and the answer isn't a secret; nil if f is missing,
-- fails or answers a secret. For APIs that may be gone, broken or hidden on Forever. Always one
-- value, also nil (tonumber(LT.Value(...)) or a call's last argument can't come up empty).
function LT.Value(f, ...)
	if not f then
		return nil
	end
	local ok, v = pcall(f, ...)
	if ok and not LT.IsSecret(v) then
		return v
	end
	return nil
end

-- In a fight: the combat lockdown, or the moment before it (it begins only after
-- PLAYER_REGEN_DISABLED, so InCombatLockdown is still false inside that event). Always true or false.
function LT.InCombat()
	return (InCombatLockdown and InCombatLockdown()) or LT.Value(UnitAffectingCombat, "player") == true
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------

-- The first maxBytes bytes of text, cut before a UTF-8 character that wouldn't fit whole (a
-- letter that ends right at the limit stays). At least one byte, so a loop cutting a long text
-- into parts always gets on.
function LT.CutUTF8(text, maxBytes)
	local cut = math.min(#text, maxBytes)
	while cut < #text and cut > 1 and text:byte(cut + 1) >= 128 and text:byte(cut + 1) < 192 do
		cut = cut - 1 -- (the byte after the cut continues a character: it goes too)
	end
	return text:sub(1, cut)
end

-- A number written with a decimal point ("4.5", "12.3 km", "3.4%") with the decimal mark of the
-- client's language: "4,5" in German (ns.DECIMAL_COMMA, Locales/deDE.lua). english: keeps the point
-- (chat lines, which stay English).
function LT.Decimal(text, english)
	if ns.DECIMAL_COMMA and not english then
		return (text:gsub("%.", ","))
	end
	return text
end

-- How long ago a time() was: "just now", "5 min ago", "3 h ago", "yesterday", "4 days ago"
-- (in the client's language; a time still to come is just now).
function LT.Ago(t)
	local seconds = math.max(0, time() - (t or 0))
	if seconds < 120 then
		return L["just now"]
	elseif seconds < 3600 then
		return L["%d min ago"]:format(math.floor(seconds / 60))
	elseif seconds < 86400 then
		return L["%d h ago"]:format(math.floor(seconds / 3600))
	elseif seconds < 2 * 86400 then
		return L["yesterday"]
	end
	return L["%d days ago"]:format(math.floor(seconds / 86400))
end

---------------------------------------------------------------------------
-- Character names (LT.Names). In WoW: Forever every character has a first name and a surname:
-- UnitName gives them apart (the surname as its second return), the game and Battle.net show them
-- together ("Anna Brook"). Typed names may carry a realm instead ("Anna-Realm").
---------------------------------------------------------------------------

local Names = {}
LT.Names = Names

-- "Anna" of "Anna", "Anna Brook" or "Anna-Realm"; nil if it isn't a name addons may read.
function Names.First(name)
	return type(name) == "string" and not LT.IsSecret(name) and name:match("^[^%s%-]+") or nil
end

-- More than the first name: "Anna Brook" (or "Anna-Realm"), not "Anna".
function Names.HasSurname(name)
	return type(name) == "string" and not LT.IsSecret(name) and Names.First(name) ~= name
end

-- The same character, however it was typed ("anna", "Anna-Realm", "Anna Brook"): the first names,
-- whatever their case.
function Names.Same(a, b)
	a, b = Names.First(a), Names.First(b)
	if not (a and b) then
		return false
	end
	if strcmputf8i then
		return strcmputf8i(a, b) == 0
	end
	return a:lower() == b:lower()
end

-- My character's name as the game and Battle.net (a friend's peer.name) show it: "Anna Brook", the
-- first name alone where there's no surname; then the first name and the surname (nil: none, or the
-- game keeps it secret).
function Names.Mine()
	local first, surname = UnitName("player")
	if type(surname) == "string" and not LT.IsSecret(surname) and surname ~= "" then
		return first .. " " .. surname, first, surname
	end
	return first, first, nil
end

-- Whether a name a friend's client sent (a verdict, ...) is my character's: with the surname, or without.
function Names.IsMine(name)
	return name ~= nil and (name == UnitName("player") or name == (Names.Mine()))
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

-- Which files the game loads for LefthyTools (the TOC's files and saved variables), as a short
-- hash; npm test checks it against the TOC. The game reads the TOC only at startup, so an update
-- that changes it needs a restart, any other a /reload. Friends send theirs with their version.
LT.FILES = "b3297443"

-- The newest LefthyTools build seen from a friend (Beacon), if newer than ours, and its FILES
-- (nil if that friend's build doesn't send them). Addons can't go online, so friends are the
-- only way to learn about updates.
function LT:NoteFriendVersion(version, files)
	if LT.CompareVersions(version, LT.version) == 1
		and (not LT.newerVersion or LT.CompareVersions(version, LT.newerVersion) == 1) then
		LT.newerVersion, LT.newerFiles = version, files
	elseif version == LT.newerVersion and files then
		LT.newerFiles = files
	end
end

-- How to update to a friend's build with these FILES (nil: unknown). Chat text.
function LT.UpdateHint(files)
	local run = "To update, run Update-LefthyTools.cmd again, then "
	if files and files ~= LT.FILES then
		return run .. "restart the game: this update adds files, a /reload isn't enough."
	elseif files then
		return run .. "/reload (no restart needed)."
	end
	return run .. "/reload (or restart the game if the updater says so)."
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
-- Your own loot (Chronicle counts it, the fight stream shows it)
---------------------------------------------------------------------------

local lootPatterns

-- A CHAT_MSG_LOOT line about your own loot: its link, item ID, count and quality (nil if it's
-- someone else's; the quality nil if not known).
function LT.OwnLoot(text)
	if type(text) ~= "string" or LT.IsSecret(text) then
		return nil
	end
	if not lootPatterns then
		lootPatterns = {}
		for _, fmt in ipairs({ LOOT_ITEM_SELF_MULTIPLE or "You receive loot: %sx%d.", LOOT_ITEM_SELF or "You receive loot: %s.",
				LOOT_ITEM_PUSHED_SELF_MULTIPLE or "You receive item: %sx%d.", LOOT_ITEM_PUSHED_SELF or "You receive item: %s." }) do
			local pattern = fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
			pattern = pattern:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
			lootPatterns[#lootPatterns + 1] = "^" .. pattern .. "$"
		end
	end
	for _, pattern in ipairs(lootPatterns) do
		local link, count = text:match(pattern)
		if link then
			local itemID = tonumber(link:match("|Hitem:(%d+)"))
			local quality = itemID and C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID)
			if type(quality) ~= "number" then
				quality = tonumber(link:match("|cnIQ(%d):")) -- retail links carry their quality
			end
			return link, itemID, tonumber(count) or 1, quality
		end
	end
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
-- Guarded hooks. A tick (Beacon's, Chronicle's) calls other files' hooks several times a second,
-- some every frame. One that fails must not stop the rest of the tick (sending, say), nor fail
-- again ten times a second: LT.Guard reports its error once and lets it rest a while.
---------------------------------------------------------------------------

local GUARD_REST, GUARD_REST_MAX = 1, 60 -- seconds a failed hook rests: doubled each time it fails again
local guards = {} -- name -> { rest = seconds, resting = until (GetTime), told = { [message] = true } }
local guarded     -- the guard whose hook is running (for Report)

-- xpcall's error handler: it runs where the error happened, so the error catcher keeps that stack.
-- Each message once per hook and session.
local function Report(err)
	local key = (type(err) == "string" and not LT.IsSecret(err)) and err or "?"
	if not guarded.told[key] then
		guarded.told[key] = true
		geterrorhandler()(err)
	end
	return err
end

local function Finish(guard, outer, ok, ...)
	guarded = outer
	if ok then
		guard.rest = nil
		return true, ...
	end
	guard.rest = guard.rest and math.min(guard.rest * 2, GUARD_REST_MAX) or GUARD_REST
	guard.resting = GetTime() + guard.rest
end

-- Calls the hook fn(...), name being what it's known by (e.g. "B.UpdatePings"). Returns true and
-- what fn returned if it ran and worked; nothing if it failed, rests, or fn is nil (a file not
-- loaded). An error goes to the error handler, and so to the error catcher (Errors.lua), once per
-- message; then the hook rests: 1 s, twice as long each time it fails again (at most a minute),
-- until a call works. No garbage per call: fine for every frame.
function LT.Guard(name, fn, ...)
	if not fn then
		return
	end
	local guard = guards[name]
	if not guard then
		guard = { told = {} }
		guards[name] = guard
	end
	if guard.resting then
		if GetTime() < guard.resting then
			return
		end
		guard.resting = nil
	end
	local outer = guarded
	guarded = guard
	return Finish(guard, outer, xpcall(fn, Report, ...))
end

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
-- (its key, or the opts.id given to the builder); value is what the db keeps, for a choice too
-- (Builder:Choice: its slider is moved to that value; one that isn't a choice changes nothing).
-- tbl/key say where it lives if there is no settings panel (default m.db[id]).
function LT:SetModuleSetting(m, id, value, tbl, key)
	local setting = m.settings and m.settings[id]
	if setting then
		local position = m.choices and m.choices[id]
		if position then
			value = position(value) -- the slider's position
			if not value then
				return
			end
		end
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

-- Each function in list with these arguments; one that fails doesn't stop the others.
local function RunAll(list, ...)
	for _, fn in ipairs(list) do
		local ok, err = pcall(fn, ...)
		if not ok then
			geterrorhandler()(err)
		end
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, arg)
	if event == "ADDON_LOADED" and arg == ADDON then
		self:UnregisterEvent("ADDON_LOADED") -- (every add-on loaded later would fire it here too)
		LT.freshInstall = type(LefthyToolsDB) ~= "table" -- no saved settings yet: a new install
		LefthyToolsDB = type(LefthyToolsDB) == "table" and LefthyToolsDB or {}
		local db = LefthyToolsDB
		db.modules = type(db.modules) == "table" and db.modules or {}
		db.settings = type(db.settings) == "table" and db.settings or {}
		LT.db = db
		RunAll(LT.onLoad, db)

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
		self:UnregisterEvent("PLAYER_LOGIN")
		loggedIn = true
		RunAll(LT.onLogin)
		for _, m in ipairs(LT.modules) do
			if LT.db.modules[m.key] then
				m.enabled = true
				SafeCall(m, "OnEnable")
			end
		end
	end
end)
