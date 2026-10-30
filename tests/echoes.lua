-- Echoes: the module and its settings, the saved table, its own events and driver, recording only
-- off the beta.
-- Needs: no other file (it switches Echoes off and on itself, and the mock's client back to the beta).
local suite = ...
local check, section, ns, LT, lefthy = suite.check, suite.section, suite.ns, suite.LT, suite.lefthy
local catchErrors = suite.catchErrors
local E = ns.Echoes
local M = LT:GetModule("echoes")

-- Echoes switched off and on again (the module's switch: what the settings' checkbox does), on the
-- client world says ("beta", "release" or nil: unknown).
local function restart(world)
	LT:SetModuleEnabled("echoes", false)
	LT.world = world
	LT:SetModuleEnabled("echoes", true)
end

section("Echoes: the module")
do
	check(M and M.title == "Echoes" and M.enabled and LefthyToolsDB.modules.echoes == true, "on by default")
	check(M.category and M.category.name == "Echoes" and M.category.parent == LT.category, "its own settings page, its name untranslated")
	local relay, collect = REGISTERED_SETTINGS.LefthyTools_echoes_relay, REGISTERED_SETTINGS.LefthyTools_echoes_collect
	check(relay and relay:GetValue() == true and M.db.relay == true and relay.name == "Relay friends' recordings",
		"\"Relay friends' recordings\": on by default")
	check(collect and collect:GetValue() == false and M.db.collect == false and collect.name == "Collect recordings",
		"\"Collect recordings\": off by default")
	check(REGISTERED_SETTINGS.LefthyTools_module_echoes, "a switch on the overview page (the recording's switch)")
end

section("Echoes: the saved table")
do
	local data = LefthyToolsEchoesDB
	check(E.data == data and data.world == "beta" and data.v == 1 and data.n == 0 and data.open == nil, "made at load: layout 1, no pages yet")
	check(type(data.store) == "string" and data.store:match("^[0-9a-f]+$") and #data.store == 8, "a store of 8 random lowercase hex digits, got " .. tostring(data.store))
	check(data.session == 1, "the first load: session 1 (release.lua: +1 at each)")
	check(type(data.mine) == "table" and type(data.carry) == "table" and type(data.safe) == "table" and type(data.inbox) == "table"
		and type(data.exported) == "table" and data.acct == nil, "mine, carry, safe, inbox, exported; the account comes later")
end

section("Echoes: recording, its events and its driver")
do
	local ticks, seen, starts, stops = 0, {}, 0, 0
	E.OnTick(function() ticks = ticks + 1 end)
	E.On("ECHOES_TEST_EVENT", function(a, b) seen[#seen + 1] = "first " .. tostring(a) .. " " .. tostring(b) end)
	E.On("ECHOES_TEST_EVENT", function(a) error("a handler that fails") end)
	E.On("ECHOES_TEST_EVENT", function(a) seen[#seen + 1] = "third " .. tostring(a) end)
	E.On("ECHOES_TEST_UNIT", function(unit) seen[#seen + 1] = "unit " .. unit end, "player")
	E.When("start", function() starts = starts + 1 end)
	E.When("stop", function() stops = stops + 1 end)

	-- The mock is the beta: switched on, but nothing runs.
	Advance(1)
	Fire("ECHOES_TEST_EVENT", 1, 2)
	check(M.enabled and not E.recording and not E.driver:IsShown() and ticks == 0 and #seen == 0,
		"the beta: Echoes is on but records nothing (no driver, no events)")

	-- An unknown client records (only the beta doesn't).
	restart(nil)
	check(E.recording and E.driver:IsShown() and starts == 1 and stops == 0, "not the beta: switched on, it records")
	Advance(1)
	check(ticks >= 3 and ticks <= 4, "the driver ticks 4 times a second, got " .. ticks)
	local reported, stop = catchErrors()
	Fire("ECHOES_TEST_EVENT", 1, 2)
	stop()
	check(seen[1] == "first 1 2" and seen[2] == "third 1" and #reported == 1 and reported[1]:find("a handler that fails", 1, true),
		"its events: every handler in order, with the event's arguments; one that fails is reported and the rest still run")
	Fire("ECHOES_TEST_UNIT", "target")
	Fire("ECHOES_TEST_UNIT", "player")
	check(#seen == 3 and seen[3] == "unit player", "a unit event: only for its unit")
	local added = 0
	E.On("ECHOES_TEST_LATE", function() added = added + 1 end)
	Fire("ECHOES_TEST_LATE")
	check(added == 1, "a handler added while recording: registered at once")

	-- Switched off: the recording's off switch.
	LT:SetModuleEnabled("echoes", false)
	local ticksWere = ticks
	Advance(1)
	Fire("ECHOES_TEST_EVENT", 3, 4)
	check(not E.recording and not E.driver:IsShown() and ticks == ticksWere and #seen == 3 and stops == 1,
		"switched off: no ticks, no events (nothing runs)")
	LT:SetModuleEnabled("echoes", true)
	check(E.recording and starts == 2, "on again: recording again")

	-- The release records too; back on the beta it doesn't.
	restart("release")
	check(E.recording, "the release records")
	restart("beta")
	check(not E.recording and not E.driver:IsShown() and stops == 3, "the beta again: idle")
end
