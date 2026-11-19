-- Core: /lefthy perf (Perf.lua): a measurement while the game stutters (frames, the worst one, stutters), every
-- addon's time from the game's profiler and its frames over 50 ms, memory growth, events, LefthyTools' guarded
-- hooks (nested ones not counted twice), the parts' states, a line a second; the log kept, shown and sent in
-- pieces to friends who collect reports; seconds clamped, one at a time, stop; nothing measured afterwards;
-- without the profiler it says so.
-- Needs: no other file.
local suite = ...
local check, section, ns, LT, lefthy = suite.check, suite.section, suite.ns, suite.LT, suite.lefthy
local Perf = LT.Perf

local function PrintedSince(mark)
	return table.concat(PRINTED, "\n", mark + 1)
end
local function Count(text, pattern)
	local n = 0
	for _ in text:gmatch(pattern) do n = n + 1 end
	return n
end

section("Core: /lefthy perf")
do
	-- The game's side: a clock the test moves, three addons, the profiler, memory, all events.
	local clock = 0
	debugprofilestop = function() return clock end
	local realAddOns = C_AddOns
	local addons = { "LefthyTools", "SlowAddon", "Blizzard_AuctionHouseUI" }
	C_AddOns = setmetatable({ GetNumAddOns = function() return #addons end, GetAddOnInfo = function(i) return addons[i] end,
		IsAddOnLoaded = function(i) return addons[i] ~= nil end }, { __index = realAddOns })
	local avg = { LefthyTools = 0.4, SlowAddon = 6, Blizzard_AuctionHouseUI = 0.1 }
	local over10, over50 = { SlowAddon = 100 }, { SlowAddon = 20 }
	C_AddOnProfiler = {
		IsEnabled = function() return true end,
		GetAddOnMetric = function(name, metric)
			if metric == 1 then return avg[name] or 0 end
			if metric == 7 then return over10[name] or 0 end
			if metric == 8 then return over50[name] or 0 end
			return 0
		end,
		GetOverallMetric = function(metric) return metric == 3 and 7 or 0 end,
		GetApplicationMetric = function(metric) return metric == 1 and 16 or 0 end,
	}
	local mem = { LefthyTools = 30000, SlowAddon = 1000, Blizzard_AuctionHouseUI = 500 }
	UpdateAddOnMemoryUsage = function() end
	GetAddOnMemoryUsage = function(name) return mem[name] end
	local methods = getmetatable(Perf.listener).__index
	methods.RegisterAllEvents = function(self) self._all = true end
	local listener = Perf.listener
	listener.UnregisterAllEvents = function(self) self._all = nil; methods.UnregisterAllEvents(self) end

	check(not LT.MeasuringGuards() and not Perf.driver:IsShown(), "nothing measured until asked")
	local mark = #PRINTED
	lefthy("perf 3")
	check(PrintedSince(mark):find("measuring for 3 s", 1, true) and Perf.Running() and LT.MeasuringGuards()
		and Perf.driver:IsShown() and listener._all, "/lefthy perf 3: measuring, the hooks timed, every event counted")
	mark = #PRINTED
	lefthy("perf")
	check(PrintedSince(mark):find("already measuring", 1, true), "one at a time")

	Advance(1)
	-- The stutter: a frame of 300 ms; the slow addon's counters go up, it grows by 2 MB, an event storm.
	Advance(0.3, 0.3)
	over10.SlowAddon, over50.SlowAddon = 104, 23
	mem.SlowAddon = mem.SlowAddon + 2048
	for _ = 1, 300 do listener._scripts.OnEvent(listener, "GET_ITEM_INFO_RECEIVED") end
	for _ = 1, 20 do listener._scripts.OnEvent(listener, "BAG_UPDATE") end
	-- Guarded hooks: five of 4 ms, and one of 1 ms calling one of 2 ms (3 ms in all, not 5).
	for _ = 1, 5 do LT.Guard("Test slow hook", function() clock = clock + 4 end) end
	LT.Guard("Test outer hook", function()
		clock = clock + 1
		LT.Guard("Test inner hook", function() clock = clock + 2 end)
	end)
	mark = #PRINTED
	Advance(2)
	check(not Perf.Running() and not LT.MeasuringGuards() and not Perf.driver:IsShown() and not listener._all,
		"done after 3 s: nothing measured any more")
	local log = Perf.Last()
	check(type(log) == "string" and log:find("^LefthyTools perf log, ") and log:find("LefthyTools " .. LT.version, 1, true),
		"the log: when, the build")
	check(log:find("the worst 300 ms, over 50 ms: 1, over 100 ms: 1, over 250 ms: 1", 1, true), "frames: the stutter, got " .. log)
	check(log:find("all addons 7.00 ms a frame on average, the worst frame 7.00 ms, the whole game 16.0 ms", 1, true)
		and log:find("  1. SlowAddon: 6.00 ms a frame on average, the worst second 6.00 ms, frames over 10 ms: 4, over 50 ms: 3", 1, true)
		and log:find("  2. LefthyTools: 0.40 ms", 1, true), "addons: the slowest first, its frames over 10 and 50 ms while measuring")
	check(log:find("LefthyTools inside (hooks run through LT.Guard): 23.0 ms in all", 1, true)
		and log:find("  Test slow hook: 20.0 ms, 5 calls, the longest 4.00 ms", 1, true)
		and log:find("  Test outer hook: 3.00 ms, 1 calls", 1, true) and log:find("  Test inner hook: 2.00 ms, 1 calls", 1, true),
		"LefthyTools' hooks: each, nested ones once in the sum")
	check(log:find("grew most: SlowAddon +2.0 MB", 1, true) and log:find("the biggest: LefthyTools 29.3 MB", 1, true), "memory: who grew")
	check(log:find("Events: 320 (", 1, true) and log:find("most: GET_ITEM_INFO_RECEIVED 300, BAG_UPDATE 20", 1, true), "events: the most first")
	check(log:find("LefthyTools at the start:\n  Beacon: ", 1, true) and log:find("  WhyPoor prices: auction house ", 1, true) and log:find("LefthyTools at the end:", 1, true)
		and log:find("  Beacon: ", 1, true) and log:find("  WhyPoor stocks: tab ", 1, true) and log:find("  WhyPoor windows: window ", 1, true),
		"what LefthyTools' parts were doing")
	check(Count(log, "\n  %ds: ") == 3 and log:find("  2s: 43 fps, worst 300 ms, addons 7.00 ms", 1, true)
		and log:find("SlowAddon 6.00, LefthyTools 0.40, Blizzard_AuctionHouseUI 0.10", 1, true)
		and log:find("(GET_ITEM_INFO_RECEIVED 300)", 1, true), "a line a second: the stutter in the second one, got " .. log)
	local said = PrintedSince(mark)
	check(said:find("measured 3.0 s:", 1, true) and said:find("the worst frame 300 ms, 1 frames over 50 ms", 1, true)
		and said:find("most time a frame: SlowAddon 6.00 ms, LefthyTools 0.40 ms", 1, true) and said:find("/lefthy perf send", 1, true),
		"the gist in chat, got " .. said)
	check(Perf.window and Perf.window:IsShown() and Perf.window.Box:GetText() == log, "the log in a window, to copy")
	local logs = LefthyToolsDB.perfLogs
	check(logs[#logs].text == log, "kept (LefthyToolsDB.perfLogs)")
	Perf.window:Hide()
	lefthy("perf show")
	check(Perf.window:IsShown() and Perf.window.Box:GetText() == log, "/lefthy perf show: the last one again")
	Perf.window:Hide()
	local before = clock
	LT.Guard("Test slow hook", function() clock = clock + 4 end)
	check(clock == before + 4 and not LT.MeasuringGuards(), "afterwards a hook just runs")

	-- Sent: in pieces of whole lines, to friends who collect reports (none online: kept, said once).
	local out = LefthyToolsDB.reportsOut or {}
	LefthyToolsDB.reportsOut = out
	local had = #out
	mark = #PRINTED
	lefthy("perf send")
	local pieces = Perf.Pieces(log)
	check(#out == had + #pieces and out[had + 1].text:find("^Perf log %(1 of " .. #pieces .. "%): LefthyTools ")
		and out[#out].text:find("Perf log (" .. #pieces .. " of " .. #pieces .. ")", 1, true), "/lefthy perf send: every piece kept to send")
	check(Count(PrintedSince(mark), "report kept") == 1, "said once")
	for i = #out, had + 1, -1 do table.remove(out, i) end
	local long = string.rep(string.rep("x", 99) .. "\n", 200)
	pieces = Perf.Pieces(long)
	local fits = #pieces == Perf.SEND_MAX
	for _, p in ipairs(pieces) do fits = fits and #p <= Perf.SEND_BYTES and (#p + 1) % 100 == 0 end -- (lines of 99, whole)
	check(fits, "a long log: SEND_MAX pieces of whole lines, SEND_BYTES each at most")

	-- Seconds clamped; stopped early.
	mark = #PRINTED
	lefthy("perf 1000")
	check(PrintedSince(mark):find("measuring for 60 s", 1, true), "60 s at most")
	Advance(0.5)
	lefthy("perf stop")
	check(not Perf.Running() and Perf.Last():find("Frames: 30 in 0.5 s", 1, true), "/lefthy perf stop: the log so far")
	Perf.window:Hide()

	-- Without the game's profiler.
	C_AddOnProfiler = nil
	lefthy("perf 3")
	Advance(3.1)
	check(Perf.Last():find("Addons: the game's addon profiler (C_AddOnProfiler) isn't there", 1, true), "no profiler: said")
	Perf.window:Hide()

	debugprofilestop, C_AddOns, UpdateAddOnMemoryUsage, GetAddOnMemoryUsage = nil, realAddOns, nil, nil
	methods.RegisterAllEvents, listener.UnregisterAllEvents = nil, nil
end
