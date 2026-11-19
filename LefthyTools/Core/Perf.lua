local _, ns = ...
local LT = ns.LT
local L = ns.L

-- /lefthy perf [seconds]: what slows the game down, measured for a few seconds (10 by default, 3 to 60)
-- while it happens, written as a log to copy (a window) or send (/lefthy perf send: to friends who
-- collect error reports, like /lefthy report). What it measures:
--   * Frames: how many, the average and the worst frame time, frames over 50, 100 and 250 ms (stutter).
--   * Every addon's time from Blizzard's own profiler (C_AddOnProfiler, always on: no /reload): each
--     addon's average a frame (RecentAverageTime, read once a second), its worst second, and its frames
--     over 10 and 50 ms while measuring (the profiler's counters before and after); all addons together
--     each frame (GetOverallMetric's LastTime) and the whole game's average.
--   * Memory: the Lua memory each second (collectgarbage) and every addon's before and after
--     (UpdateAddOnMemoryUsage, twice: it takes a few ms): who makes garbage (collecting it stutters).
--   * Events: how often each fired (a frame of ours registered for all of them while measuring).
--   * LefthyTools inside: every hook run through LT.Guard, its time (with the hooks it calls), calls, and
--     the longest one; the outermost ones' sum is LefthyTools' guarded time.
--   * LefthyTools' state at the start and the end (LT.PerfState: the auction house scan, queues, windows).
--   * Each second on its own line, to see when it began and what came with it.
-- Cost: nothing until asked (LT.Guard looks at one local); while measuring, a frame's OnUpdate, one
-- profiler call a frame and one per addon a second. The last KEEP logs are kept (LefthyToolsDB.perfLogs):
-- /lefthy perf show opens the last one again, /lefthy perf send sends it.

local Perf = { states = {} }
LT.Perf = Perf
Perf.SECONDS, Perf.MIN, Perf.MAX, Perf.KEEP = 10, 3, 60, 5
Perf.TOP_ADDONS, Perf.TOP_EVENTS, Perf.TOP_HOOKS, Perf.TOP_MEMORY = 10, 12, 12, 6
Perf.SEND_BYTES, Perf.SEND_MAX = 2700, 3 -- a sent log: reports this big at most (Beacon's 16 parts), this many
Perf.HITCHES = { 50, 100, 250 }          -- ms: a frame this long is a stutter

-- A line about what a part of LefthyTools is doing: fn() returns text (several lines allowed) or nil.
-- Asked at the start and the end of a measurement only.
function LT.PerfState(name, fn)
	Perf.states[#Perf.states + 1] = { name = name, fn = fn }
end

local METRIC = (Enum and Enum.AddOnProfilerMetric) or { RecentAverageTime = 1, LastTime = 3, PeakTime = 4,
	CountTimeOver10Ms = 7, CountTimeOver50Ms = 8 }

local function Num(v)
	return type(v) == "number" and not LT.IsSecret(v) and v or nil
end

local function Clock()
	local ok, ms = pcall(debugprofilestop)
	return ok and type(ms) == "number" and ms or nil
end

local function LuaKB()
	local ok, kb = pcall(collectgarbage, "count")
	return ok and Num(kb) or nil
end

-- 0.25 / 3.4 / 120 (ms)
local function Ms(ms)
	if ms >= 100 then
		return ("%d"):format(math.floor(ms + 0.5))
	elseif ms >= 10 then
		return ("%.1f"):format(ms)
	end
	return ("%.2f"):format(ms)
end

-- 820 KB / 12.4 MB, with its sign when asked
local function Size(kb, signed)
	local sign = signed and (kb < 0 and "-" or "+") or (kb < 0 and "-" or "")
	kb = math.abs(kb)
	if kb >= 1024 then
		return ("%s%.1f MB"):format(sign, kb / 1024)
	end
	return ("%s%d KB"):format(sign, math.floor(kb + 0.5))
end

---------------------------------------------------------------------------
-- What the game tells
---------------------------------------------------------------------------

local function Profiler()
	local P = C_AddOnProfiler
	if not (P and P.GetAddOnMetric) or (P.IsEnabled and LT.Value(P.IsEnabled) == false) then
		return nil
	end
	return P
end

local function AddonMetric(name, metric)
	local P = Profiler()
	return P and Num(LT.Value(P.GetAddOnMetric, name, METRIC[metric])) or nil
end

local function OverallMetric(metric)
	local P = Profiler()
	return P and P.GetOverallMetric and Num(LT.Value(P.GetOverallMetric, METRIC[metric])) or nil
end

local function GameMetric(metric)
	local P = Profiler()
	return P and P.GetApplicationMetric and Num(LT.Value(P.GetApplicationMetric, METRIC[metric])) or nil
end

-- The addons loaded (Blizzard's own too: the profiler counts them).
local function Addons()
	local api, list = C_AddOns, {}
	if not (api and api.GetNumAddOns and api.GetAddOnInfo and api.IsAddOnLoaded) then
		return list
	end
	for i = 1, Num(LT.Value(api.GetNumAddOns)) or 0 do
		local name = LT.Value(api.GetAddOnInfo, i)
		if type(name) == "string" and LT.Value(api.IsAddOnLoaded, i) then
			list[#list + 1] = name
		end
	end
	return list
end

-- Every addon's memory (KB) and what reading it took (ms); nil: the game doesn't tell.
local function Memory(addons)
	local get = GetAddOnMemoryUsage or (C_AddOns and C_AddOns.GetAddOnMemoryUsage)
	local update = UpdateAddOnMemoryUsage or (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage)
	if not (get and update) then
		return nil
	end
	local started = Clock()
	pcall(update)
	local out = {}
	for _, name in ipairs(addons) do
		out[name] = Num(LT.Value(get, name))
	end
	local now = Clock()
	return out, started and now and now - started or nil
end

local function Where()
	local zone = LT.Value(GetRealZoneText) or "?"
	local sub = LT.Value(GetSubZoneText)
	local parts = { "Where: " .. zone .. ((sub and sub ~= "" and sub ~= zone) and (", " .. sub) or "") }
	local ok, _, kind = pcall(IsInInstance)
	if ok and type(kind) == "string" and not LT.IsSecret(kind) and kind ~= "none" then
		parts[#parts + 1] = "instance " .. kind
	end
	parts[#parts + 1] = "in a fight: " .. (LT.InCombat() and "yes" or "no")
	local ah = _G.AuctionHouseFrame
	parts[#parts + 1] = "auction house: " .. ((type(ah) == "table" and ah.IsShown and ah:IsShown()) and "open" or "closed")
	local fps = Num(LT.Value(GetFramerate))
	if fps then
		parts[#parts + 1] = ("%d fps when asked"):format(math.floor(fps + 0.5))
	end
	return table.concat(parts, ", ")
end

-- Each part's state, as lines.
function Perf.States()
	local lines = {}
	for _, s in ipairs(Perf.states) do
		local ok, text = pcall(s.fn)
		if not ok then
			text = "(failed: " .. tostring(text) .. ")"
		end
		if type(text) == "string" and text ~= "" then
			local first = true
			for line in text:gmatch("[^\n]+") do
				lines[#lines + 1] = (first and ("  " .. s.name .. ": ") or "    ") .. line
				first = false
			end
		end
	end
	return lines
end

---------------------------------------------------------------------------
-- Measuring
---------------------------------------------------------------------------

local run -- the measurement under way, nil: none
local driver = CreateFrame("Frame")
driver:Hide()
local listener = CreateFrame("Frame")
Perf.driver, Perf.listener = driver, listener

local function NewSecond()
	return { frames = 0, time = 0, worst = 0, addons = 0, events = {}, eventCount = 0, hooks = 0 }
end

-- A guarded hook ran (LT.Guard): its time, with the hooks it called.
local function Hook(name, ms, outermost)
	local r = run
	if not r then
		return
	end
	local h = r.hooks[name]
	if not h then
		h = { ms = 0, calls = 0, max = 0 }
		r.hooks[name] = h
	end
	h.ms, h.calls = h.ms + ms, h.calls + 1
	if ms > h.max then
		h.max = ms
	end
	if outermost then
		r.guarded = r.guarded + ms
		r.sec.hooks = r.sec.hooks + ms
	end
end

-- A second done: every addon's average over the last 60 frames (the profiler's), the memory, its line.
local function CloseSecond(r)
	local sec = r.sec
	local top = {}
	for _, name in ipairs(r.addons) do
		local avg = AddonMetric(name, "RecentAverageTime")
		if avg then
			local c = r.cpu[name]
			if not c then
				c = { sum = 0, n = 0, worst = 0 }
				r.cpu[name] = c
			end
			c.sum, c.n = c.sum + avg, c.n + 1
			if avg > c.worst then
				c.worst = avg
			end
			if avg >= 0.05 then
				top[#top + 1] = { name = name, ms = avg }
			end
		end
	end
	table.sort(top, function(a, b) return a.ms > b.ms end)
	sec.top = { top[1], top[2], top[3] }
	local kb = LuaKB()
	if kb and r.luaLast then
		sec.lua = kb - r.luaLast
	end
	r.luaLast = kb or r.luaLast
	local most, mostN = nil, 0
	for event, n in pairs(sec.events) do
		if n > mostN then
			most, mostN = event, n
		end
	end
	sec.events, sec.most, sec.mostN = nil, most, mostN
	r.secs[#r.secs + 1] = sec
	r.sec = NewSecond()
end

local function OnUpdate(_, elapsed)
	local r = run
	if not r then
		driver:Hide()
		return
	end
	local ms = elapsed * 1000
	r.frames, r.time = r.frames + 1, r.time + elapsed
	if ms > r.worst then
		r.worst = ms
	end
	for i, limit in ipairs(Perf.HITCHES) do
		if ms > limit then
			r.hitches[i] = r.hitches[i] + 1
		end
	end
	local sec = r.sec
	sec.frames, sec.time = sec.frames + 1, sec.time + elapsed
	if ms > sec.worst then
		sec.worst = ms
	end
	local all = OverallMetric("LastTime")
	if all then
		sec.addons = sec.addons + all
		r.allSum = r.allSum + all
		r.addonsN = r.addonsN + 1
		if all > r.addonsWorst then
			r.addonsWorst = all
		end
	end
	if sec.time >= 1 - 1e-6 then -- (a float sum of frame times)
		CloseSecond(r)
	end
	if r.time >= r.seconds - 1e-6 then
		Perf.Finish()
	end
end
driver:SetScript("OnUpdate", function(self, elapsed)
	local ok, err = pcall(OnUpdate, self, elapsed)
	if not ok then
		run = nil
		driver:Hide()
		listener:UnregisterAllEvents()
		LT.MeasureGuards(nil)
		geterrorhandler()(err)
	end
end)

listener:SetScript("OnEvent", function(_, event)
	local r = run
	if not (r and type(event) == "string") then
		return
	end
	r.events[event] = (r.events[event] or 0) + 1
	r.eventCount = r.eventCount + 1
	local sec = r.sec
	sec.events[event] = (sec.events[event] or 0) + 1
	sec.eventCount = sec.eventCount + 1
end)

function Perf.Running()
	return run ~= nil
end

-- Starts measuring for seconds (3 to 60; nil: 10). False when one is under way already.
function Perf.Start(seconds)
	if run then
		LT.Print("already measuring: the log comes when it's done (/lefthy perf stop ends it now).")
		return false
	end
	seconds = math.max(Perf.MIN, math.min(Perf.MAX, math.floor(tonumber(seconds) or Perf.SECONDS)))
	local addons = Addons()
	local r = { seconds = seconds, at = date("%Y-%m-%d %H:%M:%S"), frames = 0, time = 0, worst = 0,
		hitches = { 0, 0, 0 }, addons = addons, cpu = {}, before = {}, hooks = {}, guarded = 0, events = {},
		eventCount = 0, secs = {}, sec = NewSecond(), allSum = 0, addonsN = 0, addonsWorst = 0,
		profiler = Profiler() ~= nil }
	for _, name in ipairs(addons) do
		r.before[name] = { AddonMetric(name, "CountTimeOver10Ms"), AddonMetric(name, "CountTimeOver50Ms") }
	end
	r.memBefore, r.memMs = Memory(addons)
	r.luaBefore = LuaKB()
	r.luaLast = r.luaBefore
	r.where = Where()
	r.stateBefore = Perf.States()
	run = r
	LT.MeasureGuards(Hook)
	r.allEvents = pcall(listener.RegisterAllEvents, listener)
	driver:Show()
	LT.Print(("measuring for %d s: carry on as you were (it's meant to catch the stutter while it happens)..."):format(seconds))
	return true
end

-- Ends the measurement (early: what it has so far), keeps and shows the log, says the gist in chat.
function Perf.Finish()
	local r = run
	if not r then
		return nil
	end
	run = nil
	driver:Hide()
	listener:UnregisterAllEvents()
	LT.MeasureGuards(nil)
	if r.sec.frames > 0 then
		CloseSecond(r)
	end
	r.memAfter = Memory(r.addons)
	r.luaAfter = LuaKB()
	r.after = {}
	for _, name in ipairs(r.addons) do
		r.after[name] = { AddonMetric(name, "CountTimeOver10Ms"), AddonMetric(name, "CountTimeOver50Ms") }
	end
	r.game = GameMetric("RecentAverageTime")
	r.stateAfter = Perf.States()
	local text = Perf.Log(r)
	Perf.Keep(text)
	for _, line in ipairs(Perf.Gist(r)) do
		LT.Print(line)
	end
	Perf.Show(text)
	return text
end

---------------------------------------------------------------------------
-- The log
---------------------------------------------------------------------------

-- The addons by their average time a frame, the slowest first: { name, avg, worst, over10, over50 }.
local function Slowest(r)
	local list = {}
	for name, c in pairs(r.cpu) do
		local b, a = r.before[name] or {}, r.after and r.after[name] or {}
		local over10 = a[1] and b[1] and a[1] - b[1] or nil
		local over50 = a[2] and b[2] and a[2] - b[2] or nil
		list[#list + 1] = { name = name, avg = c.n > 0 and c.sum / c.n or 0, worst = c.worst, over10 = over10, over50 = over50 }
	end
	table.sort(list, function(a, b)
		if a.avg ~= b.avg then
			return a.avg > b.avg
		end
		return a.name < b.name
	end)
	return list
end

local function Fps(frames, time)
	return time > 0 and frames / time or 0
end

-- Three lines for the chat.
function Perf.Gist(r)
	local lines = {}
	local avg = r.frames > 0 and r.time * 1000 / r.frames or 0
	lines[1] = ("measured %.1f s: %d fps (%s ms a frame), the worst frame %s ms, %d frames over %d ms."):format(r.time,
		math.floor(Fps(r.frames, r.time) + 0.5), Ms(avg), Ms(r.worst), r.hitches[1], Perf.HITCHES[1])
	local slow = Slowest(r)
	if slow[1] then
		local parts = {}
		for i = 1, math.min(3, #slow) do
			parts[#parts + 1] = ("%s %s ms"):format(slow[i].name, Ms(slow[i].avg))
		end
		lines[2] = "most time a frame: " .. table.concat(parts, ", ") .. "."
	elseif not r.profiler then
		lines[2] = "the game's addon profiler isn't there: no time per addon."
	end
	lines[#lines + 1] = "the whole log is in the window (copy it); /lefthy perf send sends it to friends who collect reports."
	return lines
end

function Perf.Log(r)
	local lines = {}
	local function Add(text)
		lines[#lines + 1] = text
	end
	local version, build = GetBuildInfo()
	Add(("LefthyTools perf log, %s, LefthyTools %s (files %s), WoW %s.%s, %s"):format(r.at, tostring(LT.version),
		tostring(LT.FILES or "?"), tostring(version), tostring(build), tostring(GetLocale())))
	Add(r.where)
	local avg = r.frames > 0 and r.time * 1000 / r.frames or 0
	Add(("Frames: %d in %.1f s = %.1f fps, %s ms a frame on average, the worst %s ms, over 50 ms: %d, over 100 ms: %d, over 250 ms: %d"):format(
		r.frames, r.time, Fps(r.frames, r.time), Ms(avg), Ms(r.worst), r.hitches[1], r.hitches[2], r.hitches[3]))
	-- Addons.
	if not r.profiler then
		Add("Addons: the game's addon profiler (C_AddOnProfiler) isn't there: no time per addon.")
	else
		local all = r.addonsN > 0 and r.allSum / r.addonsN or 0
		Add(("Addons (the game's profiler): all addons %s ms a frame on average, the worst frame %s ms%s"):format(Ms(all),
			Ms(r.addonsWorst), r.game and (", the whole game " .. Ms(r.game) .. " ms a frame lately") or ""))
		local slow = Slowest(r)
		for i = 1, math.min(Perf.TOP_ADDONS, #slow) do
			local s = slow[i]
			local over = ""
			if s.over10 or s.over50 then
				over = (", frames over 10 ms: %s, over 50 ms: %s"):format(tostring(s.over10 or "?"), tostring(s.over50 or "?"))
			end
			Add(("  %d. %s: %s ms a frame on average, the worst second %s ms%s"):format(i, s.name, Ms(s.avg), Ms(s.worst), over))
		end
	end
	-- LefthyTools inside.
	local hooks = {}
	for name, h in pairs(r.hooks) do
		hooks[#hooks + 1] = { name = name, ms = h.ms, calls = h.calls, max = h.max }
	end
	table.sort(hooks, function(a, b) return a.ms > b.ms end)
	Add(("LefthyTools inside (hooks run through LT.Guard): %s ms in all, %s ms a frame%s"):format(Ms(r.guarded),
		Ms(r.frames > 0 and r.guarded / r.frames or 0), hooks[1] and "" or ", none ran"))
	for i = 1, math.min(Perf.TOP_HOOKS, #hooks) do
		local h = hooks[i]
		Add(("  %s: %s ms, %d calls, the longest %s ms"):format(h.name, Ms(h.ms), h.calls, Ms(h.max)))
	end
	-- Memory.
	if r.luaBefore and r.luaAfter then
		Add(("Lua memory: %s -> %s (%s a second)"):format(Size(r.luaBefore), Size(r.luaAfter),
			Size(r.time > 0 and (r.luaAfter - r.luaBefore) / r.time or 0, true)))
	end
	if r.memBefore and r.memAfter then
		local grew, big = {}, {}
		for name, before in pairs(r.memBefore) do
			local after = r.memAfter[name]
			if after then
				grew[#grew + 1] = { name = name, kb = after - before }
				big[#big + 1] = { name = name, kb = after }
			end
		end
		table.sort(grew, function(a, b) return a.kb > b.kb end)
		table.sort(big, function(a, b) return a.kb > b.kb end)
		local parts = {}
		for i = 1, math.min(Perf.TOP_MEMORY, #grew) do
			if grew[i].kb > 0 then
				parts[#parts + 1] = ("%s %s"):format(grew[i].name, Size(grew[i].kb, true))
			end
		end
		Add("  grew most: " .. (parts[1] and table.concat(parts, ", ") or "none"))
		parts = {}
		for i = 1, math.min(Perf.TOP_MEMORY, #big) do
			parts[#parts + 1] = ("%s %s"):format(big[i].name, Size(big[i].kb))
		end
		Add("  the biggest: " .. table.concat(parts, ", ") .. (r.memMs and (" (reading it took " .. Ms(r.memMs) .. " ms)") or ""))
	end
	-- Events.
	if r.allEvents then
		local list = {}
		for event, n in pairs(r.events) do
			list[#list + 1] = { event = event, n = n }
		end
		table.sort(list, function(a, b)
			if a.n ~= b.n then
				return a.n > b.n
			end
			return a.event < b.event
		end)
		local parts = {}
		for i = 1, math.min(Perf.TOP_EVENTS, #list) do
			parts[#parts + 1] = ("%s %d"):format(list[i].event, list[i].n)
		end
		Add(("Events: %d (%d a second), most: %s"):format(r.eventCount, math.floor((r.time > 0 and r.eventCount / r.time or 0) + 0.5),
			parts[1] and table.concat(parts, ", ") or "none"))
	else
		Add("Events: not counted (the game refused RegisterAllEvents).")
	end
	-- State.
	Add("LefthyTools at the start:")
	for _, line in ipairs(r.stateBefore) do
		Add(line)
	end
	Add("LefthyTools at the end:")
	for _, line in ipairs(r.stateAfter) do
		Add(line)
	end
	-- Each second.
	Add("Each second (fps, the worst frame, all addons' time a frame, the slowest addons, LefthyTools' hooks, Lua memory, events):")
	for i, sec in ipairs(r.secs) do
		local top = {}
		for _, t in ipairs(sec.top) do
			top[#top + 1] = ("%s %s"):format(t.name, Ms(t.ms))
		end
		Add(("  %ds: %d fps, worst %s ms, addons %s ms, %s, hooks %s ms, Lua %s, events %d%s"):format(i,
			math.floor(Fps(sec.frames, sec.time) + 0.5), Ms(sec.worst), Ms(sec.frames > 0 and sec.addons / sec.frames or 0),
			top[1] and table.concat(top, ", ") or "-", Ms(sec.hooks), sec.lua and Size(sec.lua, true) or "?",
			sec.eventCount, sec.most and (" (" .. sec.most .. " " .. sec.mostN .. ")") or ""))
	end
	Add("Addons loaded: " .. #r.addons .. " (Blizzard's own too)")
	return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Kept, shown, sent
---------------------------------------------------------------------------

table.insert(LT.onLoad, function(db)
	db.perfLogs = type(db.perfLogs) == "table" and db.perfLogs or {}
end)

local function Logs()
	local db = LT.db
	if not db then
		return {}
	end
	db.perfLogs = type(db.perfLogs) == "table" and db.perfLogs or {}
	return db.perfLogs
end

function Perf.Keep(text)
	local logs = Logs()
	logs[#logs + 1] = { at = time(), text = text }
	while #logs > Perf.KEEP do
		table.remove(logs, 1)
	end
end

function Perf.Last()
	local logs = Logs()
	local last = logs[#logs]
	return type(last) == "table" and type(last.text) == "string" and last.text or nil
end

-- The log in pieces for reports (Beacon's 16 parts each): whole lines, SEND_BYTES each at most, SEND_MAX
-- of them (the each-second lines last: what's cut).
function Perf.Pieces(text)
	local pieces, current = {}, {}
	local size = 0
	for line in text:gmatch("[^\n]+") do
		if size + #line + 1 > Perf.SEND_BYTES and current[1] then
			pieces[#pieces + 1] = table.concat(current, "\n")
			current, size = {}, 0
			if #pieces == Perf.SEND_MAX then
				return pieces
			end
		end
		current[#current + 1] = line:sub(1, Perf.SEND_BYTES)
		size = size + #line + 1
	end
	if current[1] then
		pieces[#pieces + 1] = table.concat(current, "\n")
	end
	return pieces
end

function Perf.Send()
	local text = Perf.Last()
	if not text then
		LT.Print("no perf log yet: /lefthy perf measures one.")
		return false
	end
	local B = ns.Beacon
	if not (B and B.SendReportText) then
		LT.Print("Beacon isn't loaded: copy the log from the window (/lefthy perf show) and send it.")
		return false
	end
	local pieces = Perf.Pieces(text)
	for i, piece in ipairs(pieces) do
		B.SendReportText(("Perf log (%d of %d)"):format(i, #pieces), piece, i < #pieces)
	end
	return true
end

function Perf.Show(text)
	text = text or Perf.Last()
	if not text then
		LT.Print("no perf log yet: /lefthy perf measures one.")
		return
	end
	local window = Perf.window
	if not window then
		window = LT.Window.Create("LefthyToolsPerfFrame", L["LefthyTools performance"], 680, 460)
		local hint = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		hint:SetPoint("TOPLEFT", 16, -34)
		hint:SetPoint("TOPRIGHT", -16, -34)
		hint:SetJustifyH("LEFT")
		hint:SetText(L["What slowed the game while measuring. Send it with the button (friends who collect reports get it), or click into the text, press Ctrl+A and Ctrl+C and send it to whoever gave you LefthyTools."])
		LT.Window.AddCopyBox(window)
		window.Send = LT.Window.AddButton(window, L["Send"], function() Perf.Send() end)
		window.Again = LT.Window.AddButton(window, L["Measure again"], function()
			window:Hide()
			Perf.Start()
		end, { "RIGHT", window.Send, "LEFT", -6, 0 })
		Perf.window = window
	end
	window:SetBodyText(text)
	window:Show()
end

-- /lefthy perf [seconds | show | send | stop]
function Perf.Command(rest)
	rest = strtrim(rest or ""):lower()
	if rest == "show" then
		Perf.Show()
	elseif rest == "send" then
		Perf.Send()
	elseif rest == "stop" then
		if not Perf.Finish() then
			LT.Print("not measuring.")
		end
	elseif rest == "" or tonumber(rest) then
		Perf.Start(tonumber(rest))
	else
		LT.Print("/lefthy perf [seconds]: measures what slows the game (10 s), then a log to copy or send; /lefthy perf show, send, stop.")
	end
end

LT:AddCommand("perf", function(rest) Perf.Command(rest) end,
	"/lefthy perf [seconds|show|send|stop] - what slows the game: measured while it happens, a log to copy or send", "errors")
