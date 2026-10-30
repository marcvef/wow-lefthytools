-- Echoes: the module and its settings, the saved table, its own events and driver, recording only
-- off the beta; the line encoder (Lines.lua: the format in docs/echoes.md).
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
	local stopRecording -- (whether Echoes still recorded when the stop hook ran)
	E.When("stop", function() stops, stopRecording = stops + 1, E.recording end)

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
	check(stopRecording == true, "the stop hooks run just before: still recording (for their last lines)")
	LT:SetModuleEnabled("echoes", true)
	check(E.recording and starts == 2, "on again: recording again")

	-- The release records too; back on the beta it doesn't.
	restart("release")
	check(E.recording, "the release records")
	restart("beta")
	check(not E.recording and not E.driver:IsShown() and stops == 3, "the beta again: idle")
end

section("Echoes: the line encoder")
do
	local serverTime, clock = GetServerTime, 1793452800
	GetServerTime = function() return clock end -- (the realm's clock, moved by the test)
	local function at(seconds) clock = clock + seconds end
	local heard = {}
	E.OnLine(function(line, kind) heard[#heard + 1] = { line, kind } end)
	-- A page's time after its last line: t0 from its header, then every line's dt (a clock line sets it).
	local function timeAfter(text, t)
		for line in text:gmatch("[^\n]+") do
			if line:find("^E1;") then
				t = tonumber((select(5, strsplit(";", line))))
			elseif line:find("^%d") then
				t = t + tonumber(line:match("^(%d+),"))
			elseif line:sub(1, 1) == "!" then
				t = tonumber(line:match("^!%d+;(%d+)$"))
			else
				t = t + tonumber(line:match("^.(%d+)"))
			end
		end
		return t
	end
	local function unescape(s) return (s:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)) end

	-- The beta (the mock): nothing is written.
	E.Take()
	check(E.Line("k", 327) == nil and E.Anchor(0, 1, 2, "f", "s") == nil and E.Point(3, 4) == nil and E.Name("c", 327, "Kobold") == false
		and E.Mode("m") == nil and E.Zone(1429, "Goldshire") == nil and E.Continue() == false and #E.buffer == 0 and #heard == 0,
		"the beta: nothing is written")
	check(not pcall(E.Line, "1") and not pcall(E.Line, "ab") and not pcall(E.Line, nil) and not pcall(E.Line, ";"),
		"a line's kind is one letter or @ = ! . (anything else is an error, on the beta too)")

	restart(nil)
	-- docs/echoes.md's example page.
	E.PageStart(clock)
	check(E.bytes == 0 and E.count == 0 and #E.buffer == 0, "a new page: nothing counted yet")
	E.Raw("E1;1a2b3c4d;9f3a61c2;214;1793452800;deDE;70532;0.7.0-12-gabc1234")
	E.Line("C", "Anna-Realm", "Anna Brook", "Player-1234-0ABCDEF0", "MAGE", "Human", 2, 12, "Alliance")
	check(E.Point(-9046, -160) == nil, "no points before the page's first anchor")
	E.Anchor(0, -9046.4, -159.6, "f", "s")
	E.Zone(1429, "Goldshire")
	at(2); E.Point(-9051.2, -173.4)
	at(2); E.Point(-9059, -184)
	at(9); E.Name("c", 327, "Kobold Vermin")
	E.Line("k", 327, 5, "n", "m")
	at(3); E.Mode("m")
	at(12); E.Line("Q", 7, 250, 40)
	at(5); E.Anchor(0, -8950, -60, "f", "h", 8690)
	at(3); E.Anchor(36, nil, nil, "f", "i")
	at(1); check(E.Point(-8950, -60) == nil, "no points after an anchor without a position (an instance)")
	E.Line(".", "t")
	local bytes, count = E.bytes, E.count
	local page = E.Take()
	local expected = table.concat({ "E1;1a2b3c4d;9f3a61c2;214;1793452800;deDE;70532;0.7.0-12-gabc1234",
		"C0;Anna-Realm;Anna Brook;Player-1234-0ABCDEF0;MAGE;Human;2;12;Alliance", "@0;0;-9046;-160;f;s", "z0;1429;Goldshire",
		"2,-5,-13", "2,-8,-11", "=9;c;327;Kobold Vermin", "k0;327;5;n;m", "m3;m", "Q12;7;250;40", "@5;0;-8950;-60;f;h;8690",
		"@3;36;;;f;i", ".1;t" }, "\n") .. "\n"
	check(page == expected, "the example page: anchors and points in whole yards, points from the position before, got\n" .. page)
	check(timeAfter(page) == clock, "every line's dt adds up to the time it was written")
	check(bytes == #page and count == 13 and #E.buffer == 0 and E.Take() == "",
		"E.bytes and E.count: the page's bytes (with each \"\\n\") and lines; taken, the buffer is empty")
	check(#heard == 13 and heard[1][1]:find("^E1;") and heard[1][2] == nil and heard[2][2] == "C" and heard[5][1] == "2,-5,-13"
		and heard[5][2] == nil and heard[13][1] == ".1;t" and heard[13][2] == ".", "E.OnLine hears every line with its kind (none for points and raw lines)")

	-- The clock going back: a clock line first, then the line at dt 0.
	E.PageStart(clock)
	E.Anchor(0, 100, 200, "m", "l")
	at(-30); E.Line("k", 327)
	at(4); E.Point(110.4, 189.6)
	local t0 = clock + 26
	page = E.Take()
	check(page == "@0;0;100;200;m;l\n!0;" .. (clock - 4) .. "\nk0;327\n4,10,-10\n" and timeAfter(page, t0) == clock,
		"the clock went back: \"!0;<now>\" first, the line at dt 0, and the times still add up, got\n" .. page)

	-- Fields: markup gone, escapes, numbers, the empty ones at the end left out.
	E.PageStart(clock)
	local odd = "Kobold; Vermin, 100%|x\nend\tJ\195\164ger"
	local line = E.Line("=", "q", 11, odd)
	check(line == "=0;q;11;Kobold%3B Vermin%2C 100%25%7Cx%0Aend%09J\195\164ger" and unescape(line:match("^=0;q;11;(.*)$")) == odd,
		"%, ;, , and | and bytes below 0x20 as %XX (upper case), UTF-8 as it is; unescaped, the text again")
	line = E.Line("l", "|cff1eff00|Hitem:1234::::::::|h[Sword of Light]|h|r", "|TInterface\\Icons\\INV_Misc_Pelt_Wolf_01:0|tPelt",
		"|A:groupfinder-icon-class-mage:16:16|aMage", "|cnIQ4:Epic|r Robe", "a || b")
	check(line == "l0;Sword of Light;Pelt;Mage;Epic Robe;a %7C%7C b", "WoW's markup is gone (a link is its text), got " .. tostring(line))
	line = E.Line("x", 12, 1500.0, -0.0, 3.25, 2.5000001, -1.5, 1e10, -9046, true, false, 0 / 0, math.huge)
	check(line == "x0;12;1500;0;3.25;2.5;-1.5;10000000000;-9046;1;0", "numbers: whole ones as integers, others with at most two decimals; "
		.. "true 1, false 0; not a number or infinite: empty, got " .. tostring(line))
	check(E.Line("l", 2589, 1, nil, "", nil) == "l0;2589;1" and E.Line("D", 12, "c", nil, 14) == "D0;12;c;;14" and E.Line("o") == "o0"
		and E.Line("g", 2, SECRET, "x") == "g0;2;;x" and E.Line("r", {}, SECRET) == "r0",
		"empty fields at the end are left out, inner ones stay; nil, a secret or a table: empty")

	-- Names: once per page.
	E.Take()
	E.PageStart(clock)
	check(E.Name("c", 327, "Kobold Vermin") == true and E.Name("c", 327, "Kobold Vermin") == false and E.Name("q", 327, "Kobold Camp") == true
		and E.Name("c", 116, nil) == false and E.Name("c", 116, SECRET) == false and E.Name("c", 116, "") == false and E.Name("c", nil, "x") == false,
		"a name once per page for each namespace and id; none without a name or an id")
	E.ResetNames()
	check(E.Name("c", 327, "Kobold Vermin") == true, "E.ResetNames: named again")
	E.PageStart(clock)
	check(E.Name("c", 327, "Kobold Vermin") == true and E.Take() == "=0;c;327;Kobold Vermin\n=0;q;327;Kobold Camp\n=0;c;327;Kobold Vermin\n=0;c;327;Kobold Vermin\n",
		"a new page names everything again")

	-- A new page goes on where the last one left off.
	E.PageStart(clock)
	E.Anchor(1, 500, -300, "f", "s")
	E.Zone(1438, "Dolanaar")
	at(1); E.Mode("m")
	at(2); E.Point(510, -290)
	E.Take()
	at(5); E.PageStart(clock)
	check(E.Point(520, -280) == nil and E.Continue() == true, "a new page: no points until it goes on (E.Continue)")
	at(2); E.Point(520, -280)
	page = E.Take()
	check(page == "@0;1;510;-290;m;c\nz0;1438;Dolanaar\n2,10,10\n",
		"E.Continue: an anchor at the last position (why c), the mode and the zone again; points go on from it, got\n" .. page)
	local kept = E.state
	E.state = { anchored = false, names = {} } -- (nothing known yet: a new encoder's state)
	check(E.Continue() == false and E.Line("o", 1) == "o0;1" and E.Take() == "!0;" .. clock .. "\no0;1\n",
		"nothing known: E.Continue writes nothing; the first line without a page's time gets a clock line first")
	E.state = kept

	GetServerTime = serverTime
	restart("beta")
	check(E.Line("k", 327) == nil and E.Take() == "", "(the beta again: nothing written)")
end
