-- Core's LT.Guard: ticks call other files' hooks through it. One that fails doesn't stop the rest of
-- the tick, is reported once, and rests (1 s, 2 s, 4 s, ...) instead of failing on every tick or frame.
local suite = ...
local check, section, ns = suite.check, suite.section, suite.ns
local sentTo, anna, catchErrors = suite.sentTo, suite.anna, suite.catchErrors
local BB = ns.Beacon
local mark

section("Beacon: a hook that fails doesn't stop the tick")
do
	local health, calls, pings, reports, minimap = BB.StreamHealthTick, BB.UpdateCalls, BB.UpdatePings, BB.TickReports, BB.UpdateMinimap
	local ticks, healthCalls, reportTicks, minimapCalls = 0, 0, 0, 0
	BB.StreamHealthTick = function() healthCalls = healthCalls + 1; error("a broken health tick") end -- (before sending)
	BB.UpdateCalls = function(now) ticks = ticks + 1; return calls(now) end
	BB.UpdatePings = function() error("broken pings") end
	BB.TickReports = function(now) reportTicks = reportTicks + 1; return reports(now) end -- (after the pings)
	BB.UpdateMinimap = function() minimapCalls = minimapCalls + 1; error("a broken minimap") end -- (every frame)
	local reported, stop = catchErrors()
	mark = #GAMEDATA + 1
	anna("H2")
	Advance(3)
	stop()
	BB.StreamHealthTick, BB.UpdateCalls, BB.UpdatePings, BB.TickReports, BB.UpdateMinimap = health, calls, pings, reports, minimap
	check(sentTo(11, mark, "V2;")[1], "a hook before sending fails on every tick: Anna's hello is answered all the same")
	check(ticks >= 20 and reportTicks == ticks, "one in the middle fails: the rest of the tick runs, got " .. reportTicks .. " of " .. ticks)
	check(healthCalls <= 3 and minimapCalls <= 3,
		"the failing ones rest: " .. healthCalls .. " of " .. ticks .. " ticks, " .. minimapCalls .. " of 180 frames")
	check(#reported == 3, "each error reported once, got " .. #reported)
end

section("Chronicle: a hook that fails doesn't stop the tick")
do
	local C = ns.Chronicle
	local sync, share, onTick = C.SyncTick, C.ShareHighlights, C.OnTick
	local syncCalls, shares, redraws, feedSeen = 0, 0, 0, {}
	C.SyncTick = function() syncCalls = syncCalls + 1; error("a broken sync") end
	C.ShareHighlights = function(now) shares = shares + 1; return share(now) end -- (after Sync.lua's)
	C.OnTick = function(_, _, _, feedChanged) -- the window: fails the first time only
		redraws = redraws + 1
		feedSeen[redraws] = feedChanged
		if redraws == 1 then error("a broken redraw") end
	end
	local reported, stop = catchErrors()
	local ticks = C.ticks
	C.feedDirty = true
	Advance(5.5)
	stop()
	C.SyncTick, C.ShareHighlights, C.OnTick = sync, share, onTick
	local n = C.ticks - ticks
	check(n >= 5 and shares == n, "Sync.lua's hook fails on every tick: the rest of the tick runs, got " .. shares .. " of " .. n)
	check(syncCalls <= 3, "... and the failing hook rests, got " .. syncCalls .. " calls in " .. n .. " ticks")
	check(redraws >= 2 and feedSeen[1] and feedSeen[2], "a redraw that failed: its page stays marked for the next one")
	check(#reported == 2 and reported[1]:find("a broken sync", 1, true) and reported[2]:find("a broken redraw", 1, true),
		"each error reported once")
end
