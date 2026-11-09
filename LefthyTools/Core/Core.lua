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

-- Whether work that can wait (bulk sending, packing, building what's shared) waits for the fight's
-- end: in combat (LT.InCombat), for up to 15 minutes unbroken. The game's combat flag can stick out of
-- any fight; after that the work goes on as it would out of combat. The fight's start is noted at
-- PLAYER_REGEN_DISABLED (or the first call that finds one), and forgotten at PLAYER_REGEN_ENABLED.
local FIGHT_HOLD = 900
local fightSince -- (GetTime() of the fight's start; nil: none noted)
function LT.InFight()
	if not LT.InCombat() then
		fightSince = nil
		return false
	end
	local now = GetTime()
	fightSince = fightSince or now
	return now - fightSince < FIGHT_HOLD
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

-- text's 32-bit hash as 8 lowercase hex digits, case-sensitive: two 32-bit rolling hashes folded
-- into one, written as two 16-bit halves (%x of a number above 2^31 isn't safe in every Lua).
-- Chronicle's account hash is this of the lowercased BattleTag (C.Hash): it must never change.
-- Echoes hashes whole pages with it, so it reads four bytes per string.byte call.
local byte = string.byte
function LT.Hash32(text)
	local h1, h2 = 5381, 0
	local n, i = #text, 1
	while i + 3 <= n do
		local a, b, c, d = byte(text, i, i + 3)
		h1 = (((((h1 * 33 + a) % 4294967296) * 33 + b) % 4294967296 * 33 + c) % 4294967296 * 33 + d) % 4294967296
		h2 = (((((h2 * 131 + a) % 4294967296) * 131 + b) % 4294967296 * 131 + c) % 4294967296 * 131 + d) % 4294967296
		i = i + 4
	end
	for j = i, n do
		local b = byte(text, j)
		h1 = (h1 * 33 + b) % 4294967296
		h2 = (h2 * 131 + b) % 4294967296
	end
	local h = (h1 + h2 * 7) % 4294967296
	return ("%04x%04x"):format(math.floor(h / 65536), h % 65536)
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
--   ...-local           installed from a clone before that commit was on GitHub: a test build
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
LT.FILES = "7b634569"

-- The newest LefthyTools build seen from a friend (Beacon), if newer than ours, and its FILES
-- (nil if that friend's build doesn't send them). Addons can't go online, so friends are the
-- only way to learn about updates.
function LT:NoteFriendVersion(version, files)
	if LT.IsPublishedBuild(version) and LT.CompareVersions(version, LT.version) == 1
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

-- False for a build nobody can update to: a test build (-local) or a development install (-dirty,
-- -dev). Its number still counts everywhere else (which messages a friend gets); it just isn't
-- an update to tell anyone about.
function LT.IsPublishedBuild(version)
	return type(version) == "string" and not (version:find("-local", 1, true)
		or version:find("-dirty", 1, true) or version:find("-dev", 1, true))
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
-- Where I am: my position in world yards (Beacon's state, dots, minimap and pings)
---------------------------------------------------------------------------

-- The map route (C_Map: the best map for me, my spot on it, that spot in the world; verified in
-- game) is what Beacon sends. The minimap needs my position every frame while moving; UnitPosition
-- gives it without creating tables, so it's used once it has been seen to agree with the map route
-- (HereBeDragons relies on the two matching). That is checked again after every loading screen
-- (another continent or an instance may not agree; Core's PLAYER_ENTERING_WORLD below): until it
-- agrees again, the map route.
local unitPositionAgrees = false
local issecret = LT.IsSecret

-- continent, north, west in world yards by the map route; nil where the game has no map position
-- (dungeons, raids). Also notes whether UnitPosition agrees with it (same continent, < 2 yd).
function LT.MapRoutePosition()
	local mapID = C_Map.GetBestMapForUnit("player")
	local mapPos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not mapPos then
		return nil -- dungeons, raids and other places without a map position
	end
	local continent, worldPos = C_Map.GetWorldPosFromMapPos(mapID, mapPos)
	if not continent or not worldPos then
		return nil
	end
	local north, west = worldPos:GetXY()
	if UnitPosition and not unitPositionAgrees then
		local uNorth, uWest, _, uContinent = UnitPosition("player")
		unitPositionAgrees = uNorth ~= nil and not (issecret(uNorth) or issecret(uWest) or issecret(uContinent))
			and uContinent == continent and math.abs(uNorth - north) < 2 and math.abs(uWest - west) < 2
	end
	return continent, north, west
end

-- continent, north, west in world yards, or nil where the game hides positions: UnitPosition once
-- it agrees with the map route, else the map route.
function LT.Position()
	if unitPositionAgrees then
		local north, west, _, continent = UnitPosition("player")
		if north and not (issecret(north) or issecret(west) or issecret(continent)) then
			return continent, north, west
		end
	end
	return LT.MapRoutePosition()
end

---------------------------------------------------------------------------
-- Creatures (the Bestiary's records, the fight stream's mobs)
---------------------------------------------------------------------------

-- A creature's ID from its GUID ("Creature-0-<server>-<instance>-<zone>-<ID>-<spawn>", also
-- "Vehicle-"); nil for players, pets of players, objects, a secret and anything else.
function LT.CreatureOf(guid)
	if type(guid) ~= "string" or issecret(guid) then
		return nil
	end
	return tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-") or guid:match("^Vehicle%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
end

---------------------------------------------------------------------------
-- Your own loot (Chronicle counts it, the fight stream shows it)
---------------------------------------------------------------------------

local lootPatterns
local PUSHED_FROM = 3 -- lootPatterns from this one on are the "pushed" lines

-- The quality colours (ITEM_QUALITY_COLORS' hex: poor to WoW Token, 0-8) as classic has them: what
-- Forever's links carry ("|cff1eff00|Hitem:..."). The game's own table comes first (QualityOfColour).
local CLASSIC_QUALITY_HEX = { [0] = "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000", "e6cc80", "00ccff", "00ccff" }
local qualityOfHex -- "1eff00" -> 2, made at the first loot line

-- A quality from a colour's last six hex digits ("|cff1eff00", "ff1eff00": "1eff00"), or nil.
local function HexOf(colour)
	return type(colour) == "string" and not LT.IsSecret(colour) and colour:match("(%x%x%x%x%x%x)$") or nil
end
local function QualityOfColour(hex)
	if not qualityOfHex then
		qualityOfHex = {}
		local function Add(q, colour)
			colour = HexOf(colour)
			if colour and qualityOfHex[colour:lower()] == nil then -- (the first quality keeps a colour two share)
				qualityOfHex[colour:lower()] = q
			end
		end
		for q = 0, 8 do
			local entry = type(ITEM_QUALITY_COLORS) == "table" and ITEM_QUALITY_COLORS[q]
			Add(q, type(entry) == "table" and entry.hex or nil)
		end
		for q = 0, 8 do
			Add(q, CLASSIC_QUALITY_HEX[q])
		end
	end
	return qualityOfHex[hex:lower()]
end

-- A CHAT_MSG_LOOT line about your own loot: its link, item ID, count, quality and whether the item
-- was pushed (nil if it's someone else's; the quality nil if not known). Pushed: "You receive
-- item:" (LOOT_ITEM_PUSHED_SELF: quest rewards, purchases and the like), not "You receive loot:"
-- (LOOT_ITEM_SELF: looted from a corpse, a chest, a node): true or false. The quality: what the game
-- knows of the item, else (not in the cache yet) the link's: retail's "|cnIQ<n>:", or its colour
-- ("|cff1eff00": Forever's, like classic's).
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
	for i, pattern in ipairs(lootPatterns) do
		local link, count = text:match(pattern)
		if link then
			local itemID = tonumber(link:match("|Hitem:(%d+)"))
			local quality = itemID and C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID)
			if type(quality) ~= "number" then
				quality = tonumber(link:match("|cnIQ(%d):")) -- retail links carry their quality
			end
			if type(quality) ~= "number" then
				local colour = link:match("|c%x%x(%x%x%x%x%x%x)|H")
				quality = colour and QualityOfColour(colour)
			end
			return link, itemID, tonumber(count) or 1, quality, i >= PUSHED_FROM
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
-- The beta or the release. WoW: Forever's release is an install of its own (_forever_, beside the
-- beta's _classic_beta_), with saved variables of its own, so LefthyTools starts empty there, unless
-- a player copies the beta's WTF folder over. The release starts fresh all the same (no data
-- from the beta is used, even from a copied WTF folder): each saved table says
-- where it was written (its world), and on the release one the beta wrote is replaced by a new one,
-- as on a first install. Only our own saved variables; nothing else of the game's is touched.
---------------------------------------------------------------------------

LT.FIRST_RELEASE_BUILD = 70532 -- the release's first build (1.60.1.70532)
-- Forever's launch day, UTC ("YYYY-MM-DD"; nil: not known). A friend on an older LefthyTools
-- that didn't start fresh can still pass on the beta's journals: on the release Chronicle leaves out
-- what's dated before it (LT.BeforeLaunch).
LT.LAUNCH_DAY = "2026-11-04"

-- The client's own answers: true on a beta, test or PTR client (Blizzard's code asks IsTestBuild).
local CLIENT_CHECKS = { "IsBetaBuild", "IsTestBuild", "IsPublicTestClient" }

-- Which client this is, the one rule for it: "beta" when any of CLIENT_CHECKS answers true;
-- "release" when all of them answer false and the build is the release's first or later; nil
-- (unknown) otherwise: an answer missing, broken or secret, or a client that calls itself none of
-- them on a build before the release's (a beta that doesn't say so). Unknown changes nothing.
function LT.WhichWorld()
	local none = true
	for _, name in ipairs(CLIENT_CHECKS) do
		local answer = LT.Value(_G[name])
		if answer == true then
			return "beta"
		end
		none = none and answer == false
	end
	local ok, _, build = pcall(GetBuildInfo)
	build = ok and LT.Readable(build) and tonumber(build)
	if none and build and build >= LT.FIRST_RELEASE_BUILD then
		return "release"
	end
	return nil
end

-- The launch day's first second (UTC) as a time(), worked out once; nil if LT.LAUNCH_DAY isn't a date.
local launch = {}
local function LaunchTime()
	if launch.day ~= LT.LAUNCH_DAY then
		local y, m, d = tostring(LT.LAUNCH_DAY):match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
		launch.day, launch.at = LT.LAUNCH_DAY, nil
		if y then
			-- That day's noon here: in UTC that day too, unless 12 hours or more off UTC (a day either
			-- way, put right below). Back from it to UTC's midnight.
			local noon = time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
			local utc = date("!*t", noon)
			local at = noon - (utc.hour * 3600 + utc.min * 60 + utc.sec)
			local utcDay = ("%04d-%02d-%02d"):format(utc.year, utc.month, utc.day)
			launch.at = at + (utcDay < LT.LAUNCH_DAY and 86400 or utcDay > LT.LAUNCH_DAY and -86400 or 0)
		end
	end
	return launch.at
end

-- Whether something dated day ("YYYY-MM-DD", or a time()) is from before the launch day: only on the
-- release, and only once LT.LAUNCH_DAY is set. (A friend's day is their own date, the launch day
-- UTC's: a few hours either way.) Cheap: friends' journals ask it for every record.
function LT.BeforeLaunch(day)
	if LT.world ~= "release" or not LT.LAUNCH_DAY or not LaunchTime() then
		return false
	elseif type(day) == "number" then
		return day < LaunchTime()
	end
	return type(day) == "string" and day < LT.LAUNCH_DAY
end

local SAVED = { "LefthyToolsDB", "LefthyToolsChronicleDB", "LefthyToolsBestiaryDB", "LefthyToolsEchoesDB" } -- the TOC's SavedVariables

-- At load, before anything reads them. On the release, each table the beta wrote goes (one that says
-- so, or says nothing: written before the stamps, so on the beta), as if LefthyTools had never been
-- installed; true if one went. What the release wrote says so, and stays for good.
local function ForgetTheBeta(world)
	local forgot = false
	for _, name in ipairs(SAVED) do
		if world == "release" and type(_G[name]) == "table" and _G[name].world ~= "release" then
			_G[name], forgot = nil, true
		end
	end
	return forgot
end

-- Then every table says where it's written: made now if it isn't there yet (one a module makes later
-- would say nothing, and count as the beta's next time). Unknown: nothing changes.
local function Stamp(world)
	if not world then
		return
	end
	for _, name in ipairs(SAVED) do
		_G[name] = type(_G[name]) == "table" and _G[name] or {}
		_G[name].world = world
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
	if LT.Trail then
		LT.Trail(m.key .. (want and " on" or " off"))
	end
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
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(self, event, arg)
	if event == "PLAYER_REGEN_DISABLED" then
		fightSince = fightSince or GetTime() -- (LT.InFight: when the fight began)
	elseif event == "PLAYER_REGEN_ENABLED" then
		fightSince = nil
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- A loading screen (another continent or an instance): UnitPosition has to agree with the map
		-- route again before LT.Position uses it.
		unitPositionAgrees = false
	elseif event == "ADDON_LOADED" and arg == ADDON then
		self:UnregisterEvent("ADDON_LOADED") -- (every add-on loaded later would fire it here too)
		-- First of all, before anything reads the saved variables: the beta's go on the release.
		LT.world = LT.WhichWorld()
		LT.betaForgotten = ForgetTheBeta(LT.world)
		LT.freshInstall = type(LefthyToolsDB) ~= "table" -- no saved settings yet: a new install (or the beta's went)
		LefthyToolsDB = type(LefthyToolsDB) == "table" and LefthyToolsDB or {}
		Stamp(LT.world)
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
		if LT.betaForgotten then -- (now that the chat is there)
			LT.Print("data from the beta was reset; WoW: Forever starts fresh.")
		end
		RunAll(LT.onLogin)
		for _, m in ipairs(LT.modules) do
			if LT.db.modules[m.key] then
				m.enabled = true
				SafeCall(m, "OnEnable")
			end
		end
	end
end)
