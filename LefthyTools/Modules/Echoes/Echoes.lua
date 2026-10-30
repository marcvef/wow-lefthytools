local _, ns = ...
local LT = ns.LT
local L = ns.L

-- Echoes: records the way you travel and what happens on it (level-ups, quests, kills, loot, deaths
-- and more) as lines of text, cut into pages kept in LefthyToolsEchoesDB, for a program outside the
-- game to read. Friends' clients can carry pages to whoever collects them (through Beacon). Nothing
-- shows in game. The module's switch is the recording's: off, nothing is recorded.
--
-- This file: the module, its settings, the saved table, Echoes' own event frame (E.On) and its one
-- driver (E.OnTick, every 0.25 s while recording). The others, in the order they load: Lines.lua
-- (the line encoder every recorded thing goes through: docs/echoes.md has the format).
--
-- Never lags the client: event handlers only note things, the tick's subscribers do the rest and
-- each throttles itself; nothing runs while it doesn't record. Its own event frame keeps it
-- recording while Chronicle, the Bestiary or Beacon are switched off (they unregister theirs).
-- Data from the beta never counts: on the beta Echoes stays switched on but idle (E.recording false).
--
-- LefthyToolsEchoesDB (account-wide) = { world (Core's stamp), v = 1 (the layout), store (8 random
--   hex digits, made once: this WTF folder's), acct (my BattleTag's hash, filled in later), session
--   (+1 at every load: what's from this session, what's from disk), n (the last closed page's
--   number), open (the page being written, plain text, never shared; nil: none), mine (my closed
--   pages), carry (friends' pages I relay), safe (what collectors hold), inbox and exported (a
--   collector's) }

local TICK = 0.25 -- seconds between the driver's ticks

local M = LT:NewModule("echoes", {
	title = "Echoes",
	description = L["Records the way you travel and what happens on it (level-ups, quests, kills, loot, deaths and more), on your computer. Nothing shows in game. Switched off, nothing is recorded."],
	defaults = {
		relay = true,    -- keep friends' recordings and pass them on to whoever collects them
		collect = false, -- gather friends' recordings here, for a program outside the game
	},
})

local E = { module = M }
ns.Echoes = E

-- Whether Echoes records right now: switched on, and not on the beta (an unknown client records).
E.recording = false

---------------------------------------------------------------------------
-- The saved table
---------------------------------------------------------------------------

local TABLES = { "mine", "carry", "safe", "inbox", "exported" }

-- A new store: 8 random lowercase hex digits (two 16-bit halves: %x above 2^31 isn't safe in every Lua).
local function NewStore()
	return ("%04x%04x"):format(math.random(0, 65535), math.random(0, 65535))
end

-- At load (Core has stamped the table's world, and dropped the beta's on the release).
table.insert(LT.onLoad, function()
	local data = type(LefthyToolsEchoesDB) == "table" and LefthyToolsEchoesDB or {}
	LefthyToolsEchoesDB = data
	if type(data.v) ~= "number" then
		data.v = 1
	end
	if type(data.store) ~= "string" or not data.store:match("^%x%x%x%x%x%x%x%x$") then
		data.store = NewStore()
	end
	data.session = (type(data.session) == "number" and data.session or 0) + 1
	if type(data.n) ~= "number" then
		data.n = 0
	end
	if type(data.open) ~= "table" then
		data.open = nil
	end
	for _, key in ipairs(TABLES) do
		data[key] = type(data[key]) == "table" and data[key] or {}
	end
	E.data = data
end)

---------------------------------------------------------------------------
-- Events: Echoes' own frame. E.On(event, handler, unit): handler(...) runs for event, after the
-- handlers added before it, each through LT.Guard (one that fails rests, the others still run).
-- unit: a unit event for that unit only. Registered while recording.
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
local handlers, guardNames, units = {}, {}, {} -- event -> { handler, ... }; event -> { LT.Guard's name, ... }; event -> unit

local function Register(event)
	if units[event] then
		pcall(events.RegisterUnitEvent, events, event, units[event])
	else
		pcall(events.RegisterEvent, events, event) -- (one the client doesn't know errors)
	end
end

function E.On(event, handler, unit)
	local list = handlers[event]
	if not list then
		list = {}
		handlers[event], guardNames[event] = list, {}
	end
	list[#list + 1] = handler
	guardNames[event][#list] = "E.On " .. event .. " " .. #list
	units[event] = unit or units[event]
	if E.recording then
		Register(event)
	end
end

events:SetScript("OnEvent", function(_, event, ...)
	local list, names = handlers[event], guardNames[event]
	for i = 1, (list and #list or 0) do
		LT.Guard(names[i], list[i], ...)
	end
end)

---------------------------------------------------------------------------
-- The driver: one tick every TICK seconds while recording. E.OnTick(fn): fn(now) on every tick (now
-- = GetTime()), each through LT.Guard; it throttles itself (most don't need 4 a second).
---------------------------------------------------------------------------

local ticks, tickNames = {}, {}
local sinceTick = 0

function E.OnTick(fn)
	ticks[#ticks + 1] = fn
	tickNames[#ticks] = "E.OnTick " .. #ticks
end

local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(_, elapsed)
	sinceTick = sinceTick + elapsed
	if sinceTick < TICK then
		return
	end
	sinceTick = 0 -- first: an error in a tick must not make it run every frame
	local now = GetTime()
	for i = 1, #ticks do
		LT.Guard(tickNames[i], ticks[i], now)
	end
end)
E.driver = driver -- (for tests)

---------------------------------------------------------------------------
-- Recording starts and stops. E.When("start" | "stop", fn): fn() once recording has started (login
-- with Echoes on, or switched on: events registered, the driver running), or just before it stops
-- (switched off; still recording, so it can write its last lines; then the events are unregistered
-- and the driver stops).
---------------------------------------------------------------------------

local hooks = { start = {}, stop = {} }

function E.When(what, fn)
	local list = hooks[what]
	list[#list + 1] = fn
end

local function Run(what)
	for i, fn in ipairs(hooks[what]) do
		LT.Guard("E.When " .. what .. " " .. i, fn)
	end
end

function M:OnEnable()
	if LT.world == "beta" then
		return -- data from the beta never counts: switched on, but idle
	end
	E.recording = true
	for event in pairs(handlers) do
		Register(event)
	end
	sinceTick = 0
	driver:Show()
	Run("start")
end

function M:OnDisable()
	if not E.recording then
		return
	end
	Run("stop") -- (still recording: the last lines)
	E.recording = false
	events:UnregisterAllEvents()
	driver:Hide()
end

---------------------------------------------------------------------------
-- Settings (what Delivery.lua will do with them)
---------------------------------------------------------------------------

function M:BuildOptions(o)
	o:Header(L["Friends"])
	o:Checkbox("relay", L["Relay friends' recordings"],
		L["Keeps your Battle.net friends' recordings for a while and passes them on to whoever collects them, also when the two are never online at the same time. Needs Beacon; nothing is sent in combat."])
	o:Checkbox("collect", L["Collect recordings"],
		L["Gathers your Battle.net friends' recordings, and your own from other computers, on this computer, for a program outside the game to read. They take space until it has them: leave this off unless you're the one collecting."])
end
