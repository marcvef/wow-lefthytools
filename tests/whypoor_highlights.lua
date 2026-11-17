-- WhyPoor?'s highlights (Highlights.lua, the dashboard's second page) and days of supply (Chart.lua): the page
-- switch (tabs, /whypoor highlights, kept), the sections ranked (skyrocketing, falling, scarce now, flooded, below
-- usual; ties by worth), the spans (1, 7, 14 days), the noise filters (min price and its picker, too few listed,
-- under 3 days, prices that jump around, more than a day old), the empty states, a row (its change, price, sub line,
-- sparkline, tooltip; a click opens the big chart, right-click and shift-click the item actions), the work over
-- frames within the budget for 20000 items and nothing while the page isn't shown; days of supply's numbers and
-- words, in the big chart's numbers and info line and in a Stocks row. On the real price engine: this auction
-- house's items replaced by fixtures, put back at the end.
-- Needs: no other file.
local suite = ...
local check, section, ns, LT = suite.check, suite.section, suite.ns, suite.LT

local W = ns.WhyPoor
local Ch, P, Hl, St = W.Chart, W.Prices, W.Highlights, W.Stocks
local Ds = Ch.dash
local function Step(s) Advance(s or 1 / 60) end
local function Plain(text) return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function Lines() return table.concat(TOOLTIP.lines or {}, "\n") end
local function Enter(f) f._scripts.OnEnter(f) end
local DAY = 86400

section("WhyPoor?: highlights")
local key = P.HomeKey()
local h = P.House(key)
local itemsWas, flowWas, soldWas, uiWas, watchWas = h.items, h.flow, h.sold, W.DB().ui, W.DB().watch
local actionsWas = W.ItemActions
h.items, h.flow, h.sold, W.DB().ui, W.DB().watch = {}, {}, {}, {}, {}
W.ItemActions = nil
local now = time()
local today = P.Today(now)
-- An item's saved text: lows[k] is the lowest k days ago (nil: no scan that day), counts the same (or one for all);
-- seen: its last scan's age.
local function Put(item, lows, counts, seen, lowNow)
	local e = { seen = now - (seen or 600), qty = 0, days = {} }
	for k = 0, 13 do
		local low = lows[k]
		if low then
			local qty = type(counts) == "table" and (counts[k] or counts.rest) or counts
			e.days[#e.days + 1] = { today - k, low, qty }
		end
	end
	local newest = e.days[1]
	e.low, e.qty = lowNow or (newest and newest[2]), newest and newest[3] or 0
	h.items[item] = P.Encode(e)
end
local function Days(from, to, low, t)
	t = t or {}
	for k = from, to do t[k] = low end
	return t
end
local ROCKET, CRASH, SCARCE, FLOOD, BARGAIN, JUNK, FEW, YOUNG, JUMPY, OLD, TIE_A, TIE_B, SLOW =
	9801, 9802, 9803, 9804, 9805, 9806, 9807, 9808, 9809, 9810, 9811, 9812, 9813
local names = { [ROCKET] = "Hl Rocket", [CRASH] = "Hl Crash", [SCARCE] = "Hl Scarce", [FLOOD] = "Hl Flood",
	[BARGAIN] = "Hl Bargain", [JUNK] = "Hl Junk", [FEW] = "Hl Few", [YOUNG] = "Hl Young", [JUMPY] = "Hl Jumpy", [OLD] = "Hl Old",
	[TIE_A] = "Hl Tie A", [TIE_B] = "Hl Tie B", [SLOW] = "Hl Slow" }
for id, name in pairs(names) do ITEMS[id] = { name = name, quality = id == ROCKET and 3 or 1 } end
-- The rocket: 10s for two weeks, 11s yesterday, 20s today (+82% in a day, +100% in 7 and 14).
local lows = Days(2, 13, 1000)
lows[1], lows[0] = 1100, 2000
Put(ROCKET, lows, 20)
-- The crash: 20s, 16s today (-20%).
lows = Days(1, 13, 2000)
lows[0] = 1600
Put(CRASH, lows, 30)
-- Scarce: 5s steady, 100 listed, 30 today at 5s 20c (-70% listed, the price held).
lows = Days(1, 13, 500)
lows[0] = 520
Put(SCARCE, lows, { [0] = 30, rest = 100 })
-- Flooded: 8s steady, 10 listed usually, 40 today.
lows = Days(1, 13, 800)
lows[0] = 790
Put(FLOOD, lows, { [0] = 40, rest = 10 })
-- A bargain: 30s usually, the lowest now 20s (-33% under usual; a fall too).
lows = Days(1, 13, 3000)
lows[0] = 2000
Put(BARGAIN, lows, 12)
-- Noise: a cheap one doubling (50c), one with 2 listed, one with 2 days, one jumping around, one seen 2 days ago.
lows = Days(1, 13, 50)
lows[0] = 100
Put(JUNK, lows, 50)
lows = Days(1, 13, 1000)
lows[0] = 1500
Put(FEW, lows, 2)
Put(YOUNG, { [1] = 1000, [0] = 3000 }, 20)
lows = {}
for k, v in ipairs({ 4000, 5000, 1000, 8000, 200, 3000, 6000, 400, 9000, 700, 2000, 7000, 300, 500 }) do lows[k - 1] = v end
Put(JUMPY, lows, 20)
lows = Days(3, 13, 1000)
lows[2] = 2000
Put(OLD, lows, 20, 2 * DAY + 600)
-- Two the same rise (+50% in 7 days), the second worth more (more listed).
lows = Days(1, 13, 1000)
lows[0] = 1500
Put(TIE_A, lows, 10)
Put(TIE_B, lows, 50)
-- Slow: up 35% in 14 days, flat in the last week.
lows = Days(10, 13, 1000)
Days(1, 9, 1300, lows)
lows[0] = 1350
Put(SLOW, lows, 20)
P.Changed()

local function Items(list)
	local out = {}
	for _, r in ipairs(list or {}) do out[#out + 1] = names[r.item] or r.item end
	return table.concat(out, ", ")
end

-- The page switch.
check(Ch.OpenDashboard() == true and Ds.Page() == "charts" and Ds.frame.Scroll:IsShown(), "the dashboard opens on My charts")
local f = Ds.frame
local tabs = f.Tabs
check(#tabs == 2 and Plain(tabs[1].Text:GetText()) == "My charts" and Plain(tabs[2].Text:GetText()) == "Highlights"
	and tabs[1].on and not tabs[2].on, "two tabs on the title row: My charts (picked), Highlights")
Enter(tabs[2])
check(TOOLTIP.title == "Highlights" and Lines():find("skyrocketing", 1, true), "the Highlights tab's tooltip")
tabs[2]:Click()
local p = Hl.panel
check(Ds.Page() == "highlights" and W.DB().ui.dashboard.page == "highlights" and p:IsShown() and not f.Scroll:IsShown()
	and not f.Edit:IsShown() and not f.Ranges["1M"]:IsShown() and tabs[2].on, "Highlights: its page, the charts' controls hidden, kept")
-- 13 items: done in the first slice.
check(Hl.job == nil and Hl.answer and Hl.answer.total == 13, "worked out: 13 items")
local a = Hl.answer
check(a.enough == 12 and a.fresh == 11, "3 days of prices or more: 12 (not the young one); a day old at most: 11 (not the old one)")
check(Items(Hl.List(a, "rise", 7)) == "Hl Rocket, Hl Tie B, Hl Tie A",
	"skyrocketing in 7 days: the rocket, then the same rise by worth (more listed first): " .. Items(Hl.List(a, "rise", 7)))
check(Items(Hl.List(a, "fall", 7)) == "Hl Bargain, Hl Crash", "falling: the bargain (-33%), the crash (-20%): " .. Items(Hl.List(a, "fall", 7)))
check(Items(Hl.List(a, "scarce", 7)) == "Hl Scarce" and Hl.List(a, "scarce", 7)[1].score == 70, "scarce now: 100 -> 30 listed, the price held")
check(Items(a.flood) == "Hl Flood" and a.flood[1].usualQty == 10, "flooded: 40 listed, 10 usually")
check(Items(a.below) == "Hl Bargain" and a.below[1].score == 33, "below usual: 33% under")
-- The spans.
check(Items(Hl.List(a, "rise", 1)) == "Hl Rocket, Hl Tie B, Hl Tie A" and Hl.List(a, "rise", 1)[1].score == 82
	and Hl.List(a, "rise", 1)[1].from == 1100, "1 day: against yesterday (the rocket +82%, the others +50%)")
check(Items(Hl.List(a, "rise", 14)) == "Hl Rocket, Hl Tie B, Hl Tie A, Hl Slow", "14 days: the slow riser too: " .. Items(Hl.List(a, "rise", 14)))
check(Hl.List(a, "rise", 14)[4].fromDay == today - 10, "14 days: against the newest day 10 to 13 days back")
-- The page: rows.
check(Hl.Section() == "rise" and Hl.Span() == 7 and p.Spans[2].on, "picked at first: Skyrocketing, 7 days")
local rows = Hl.rows
check(rows[1]:IsShown() and rows[3]:IsShown() and not (rows[4] and rows[4]:IsShown()), "three rows")
local r1 = rows[1]
check(Plain(r1.Name:GetText()) == "Hl Rocket" and r1.Name:GetText():find("|c", 1, true) and r1.Icon.path == 1000 + ROCKET,
	"a row: icon, name in its quality's colour")
check(Plain(r1.Change:GetText()) == "+10s (+100.0%)" and r1.Change:GetText():find(Ch.Hex(Ch.UP), 1, true) and r1.Price:GetText() == "20s",
	"the change in green, absolute and %; the latest price: " .. Plain(r1.Change:GetText()))
check(Plain(r1.Sub:GetText()) == "listed 20 -> 20 (0%)", "the sub line: listed then and now: " .. Plain(r1.Sub:GetText()))
check(r1.Spark:IsShown() and r1.sparkLines == 13, "a sparkline: 14 days, 13 lines")
check(Plain(p.Sections[1].Text:GetText()) == "Skyrocketing 3" and Plain(p.Desc:GetText()):find("7 days", 1, true)
	and Plain(p.Status:GetText()) == "8 items with steady prices", "the section's count, what it lists, what was looked at: " .. Plain(p.Status:GetText()))
Enter(r1)
check(TOOLTIP.link == "item:9801" and Lines():find("Lowest on ", 1, true) and Lines():find("Usual", 1, true)
	and Lines():find("Days of supply", 1, true) and Lines():find("Click: the big chart", 1, true)
	and not Lines():find("Right-click", 1, true), "hover: the item's tooltip and the numbers")
-- Sections and spans picked.
p.Spans[1]:Click()
check(Hl.Span() == 1 and W.DB().ui.dashboard.hlSpan == 1 and Plain(rows[1].Change:GetText()) == "+9s (+81.8%)",
	"1 day: the rocket's change against yesterday")
p.Spans[2]:Click()
p.Sections[2]:Click()
check(Plain(rows[1].Name:GetText()) == "Hl Bargain" and rows[1].Change:GetText():find(Ch.Hex(Ch.DOWN), 1, true), "Falling: red")
p.Sections[3]:Click()
check(Plain(rows[1].Change:GetText()) == "70% fewer listed" and Plain(rows[1].Sub:GetText()) == "listed 100 -> 30 (-70%)", "Scarce now")
p.Sections[4]:Click()
check(Plain(rows[1].Change:GetText()) == "4.0x as many listed" and Plain(rows[1].Sub:GetText()) == "listed 40 (usually 10)",
	"Flooded: " .. Plain(rows[1].Change:GetText()))
p.Sections[5]:Click()
check(Plain(rows[1].Change:GetText()) == "33% under usual" and rows[1].Price:GetText() == "20s" and W.DB().ui.dashboard.hlSection == "below",
	"Below usual, kept")
-- Days of supply in a row: with a sales estimate.
h.flow[BARGAIN] = P.B36(today) .. "," .. P.B36(3) .. "," .. P.B36(DAY)
Hl.Draw()
check(Plain(rows[1].Sub:GetText()) == "12 listed · sells ~3.0/day · ~4 days of supply", "with sales: sold a day and days of supply: "
	.. Plain(rows[1].Sub:GetText()))
-- The min price.
check(Plain(p.Min:GetText()) == "Min price: 1s", "min price: 1s at first")
Enter(p.Min)
check(TOOLTIP.title == "Min price" and Lines():find("fewer than 5 listed", 1, true), "its tooltip: what's left out")
local runs = Hl.runs
p.Min:Click("RightButton")
check(Hl.Min() == 10 and Hl.runs == runs + 1 and Plain(p.Min:GetText()) == "Min price: 10c", "right-click: lower (10c), worked out again")
check(Items(Hl.List(Hl.answer, "rise", 7)) == "Hl Rocket, Hl Junk, Hl Tie B, Hl Tie A", "10c: the cheap one too (after the rocket: worth less)")
p.Min:Click()
p.Min:Click()
check(Hl.Min() == 1000 and Items(Hl.List(Hl.answer, "scarce", 7)) == "" and Items(Hl.answer.flood) == "" and Items(Hl.answer.below) == "Hl Bargain",
	"10s: only the dear ones")
p.Sections[3]:Click()
check(p.Message:IsShown() and Plain(p.Message:GetText()):find("Nothing got scarce in 7 days.", 1, true)
	and Plain(p.Message:GetText()):find("usual price of 10s or more", 1, true) and not rows[1]:IsShown(), "an empty section says so, and the filters")
p.Min:Click("RightButton")
p.Min:Click("RightButton")
check(Hl.Min() == 10 and W.DB().ui.dashboard.hlMin == 10, "kept")
p.Min:Click()
p.Sections[1]:Click()
-- A click: the big chart; right-click, shift-click: the item's actions.
rows[1]:Click("LeftButton")
local frame, state = Ch.View()
check(frame:IsShown() and state.item == ROCKET, "a click: the big chart")
frame:Hide()
local got
W.ItemActions = { Click = function(owner, item, button) got = { owner, item, button } end }
check(rows[1]._clicks and rows[1]._clicks[2] == "RightButtonUp", "rows take right clicks")
rows[1]:Click("RightButton")
check(got and got[1] == rows[1] and got[2] == ROCKET and got[3] == "RightButton" and not frame:IsShown(), "right-click: the item's actions")
got = nil
STATE.shift = true
rows[1]:Click("LeftButton")
STATE.shift = false
check(got and got[3] == "LeftButton" and not frame:IsShown(), "shift-click: the item's actions (a link)")
Enter(rows[1])
check(Lines():find("Right-click: more", 1, true), "with item actions: the tooltip says right-click")
W.ItemActions = nil

-- Empty states.
local itemsKept = h.items
h.items = {}
P.Changed()
Hl.StepMin(0)
check(Plain(p.Message:GetText()) == "No prices yet: open the auction house.", "no prices")
h.items = { [YOUNG] = itemsKept[YOUNG] }
P.Changed()
Hl.StepMin(0)
check(Plain(p.Message:GetText()) == "Open the auction house a few days in a row: highlights need 3 days of prices.", "under 3 days")
h.items = { [OLD] = itemsKept[OLD] }
P.Changed()
Hl.StepMin(0)
check(Plain(p.Message:GetText()) == "Your prices are more than a day old: open the auction house for fresh highlights.", "old prices")
h.items = itemsKept
P.Changed()
Hl.StepMin(0)
check(not p.Message:IsShown() and rows[1]:IsShown(), "back")

-- Over frames, within the budget; only while the page shows.
do
	local BIG = 20000
	local text = itemsKept[CRASH]
	local big = {}
	for i = 1, BIG do big[300000 + i] = text end
	h.items = big
	P.Changed()
	local answer = Hl.answer
	-- A clock that goes on 0.5 ms a look: the budget ends a frame's work early.
	local ms = 0
	debugprofilestop = function() ms = ms + 0.5 return ms end
	Hl.StepMin(0)
	debugprofilestop = nil
	check(Hl.job and Hl.slice > 0 and Hl.slice < Hl.C.PER_FRAME and Hl.answer == answer,
		"the clock past BUDGET_MS: the frame's work stops (" .. tostring(Hl.slice) .. " items); the old answer stays meanwhile")
	Step()
	check(Plain(p.Status:GetText()):match("^Working it out: %d+%%$"), "the status: " .. Plain(p.Status:GetText()))
	local frames, most = 1, 0
	while Hl.job and frames < 1000 do
		Step()
		frames = frames + 1
		most = math.max(most, Hl.slice or 0)
	end
	check(not Hl.job and frames >= 20 and most <= Hl.C.PER_FRAME and Hl.answer.total == BIG
		and Hl.List(Hl.answer, "fall", 7).n == BIG and #Hl.List(Hl.answer, "fall", 7) == Hl.ROWS,
		("%d items over %d frames, at most %d a frame; %d rows of the %d that fit"):format(BIG, frames, most, #Hl.List(Hl.answer, "fall", 7), BIG))
	-- Nothing while the page doesn't show; prices changing: again, at most every REFRESH seconds.
	tabs[1]:Click()
	check(not p:IsShown(), "My charts: the highlights hidden")
	h.items = itemsKept
	P.Changed()
	runs = Hl.runs
	Advance(Hl.C.REFRESH + 2)
	check(Hl.runs == runs and not Hl.job, "not shown: nothing worked out")
	tabs[2]:Click()
	check(Hl.runs == runs + 1 and Hl.answer.total == 13, "shown again, prices changed: worked out again")
	P.Changed()
	Advance(3)
	check(Hl.runs == runs + 1, "prices changing: not again before " .. Hl.C.REFRESH .. " s")
	Advance(Hl.C.REFRESH)
	check(Hl.runs == runs + 2, "then once more")
	f:Hide()
	P.Changed()
	runs = Hl.runs
	Advance(Hl.C.REFRESH + 2)
	check(Hl.runs == runs, "closed: nothing")
end

-- /whypoor highlights, /whypoor dashboard.
W.DB().ui.dashboard.page = "charts"
SlashCmdList.LEFTHYTOOLS_WHYPOOR("highlights")
check(f:IsShown() and Ds.Page() == "highlights" and p:IsShown(), "/whypoor highlights: the dashboard on Highlights")
SlashCmdList.LEFTHYTOOLS_WHYPOOR("dashboard")
check(f:IsShown() and Ds.Page() == "charts" and not p:IsShown() and f.Scroll:IsShown(), "/whypoor dashboard: My charts")
f:Hide()

---------------------------------------------------------------------------
section("WhyPoor?: days of supply")
check(Ch.SupplyText(nil) == nil and Ch.SupplyText(0) == "none listed" and Ch.SupplyText(math.huge) == "none sold lately"
	and Ch.SupplyText(0.3) == "under a day" and Ch.SupplyText(1.2) == "~1 day" and Ch.SupplyText(4.4) == "~4 days",
	"in words: not known, none listed, none sold, under a day, ~1 day, ~4 days")
check(Ch.SupplyLine(4) == "~4 days of supply" and Ch.SupplyLine(0) == nil and Ch.SupplyLine(math.huge) == nil and Ch.SupplyLine(nil) == nil,
	"in a line only when it's a number of days")
-- The flood: 40 listed; 10 a day sold (est.): 4 days.
check(Ch.Supply(FLOOD) == nil and select(2, Ch.Supply(FLOOD)) == 40, "no sales estimate: not known")
h.flow[FLOOD] = P.B36(today) .. "," .. P.B36(10) .. "," .. P.B36(DAY)
local days, listed, perDay = Ch.Supply(FLOOD)
check(days == 4 and listed == 40 and perDay == 10, "40 listed, 10 sold a day (an unwatched item: its flow alone, no sold text): 4 days")
h.flow[FLOOD] = P.B36(today) .. "," .. P.B36(0) .. "," .. P.B36(DAY)
check(Ch.Supply(FLOOD) == math.huge, "none sold while watched: none sold lately")
h.flow[FLOOD] = P.B36(today) .. "," .. P.B36(1) .. "," .. P.B36(1800)
check(Ch.Supply(FLOOD) == nil, "watched too short (under 2 hours): not known")
h.flow[FLOOD] = P.B36(today - 20) .. "," .. P.B36(10) .. "," .. P.B36(DAY)
check(Ch.Supply(FLOOD) == nil, "sales older than 14 days: not counted")
local fe = P.Decode(h.items[FLOOD])
fe.low = nil
local floodText = h.items[FLOOD]
h.items[FLOOD] = P.Encode(fe)
h.flow[FLOOD] = P.B36(today) .. "," .. P.B36(10) .. "," .. P.B36(DAY)
check(Ch.Supply(FLOOD) == 0 and Ch.SupplyText(Ch.Supply(FLOOD)) == "none listed", "none listed at the last scan: 0")
h.items[FLOOD] = floodText
P.Changed()
-- The big chart: a number and the info line.
Ch.Open(FLOOD)
local cells = frame.Cells
check(cells.supply and cells.supply.Value:GetText() == "~4 days" and Plain(frame.Info:GetText()):find("~4 days of supply", 1, true)
	and Plain(frame.Info:GetText()):find("sells ~", 1, true), "the big chart: Days of supply ~4 days; in the info line by the sales: "
	.. Plain(frame.Info:GetText()))
Enter(cells.supply)
check(TOOLTIP.title == "Days of supply" and Lines():find("Under 2: scarce; over 14: flooded", 1, true)
	and Lines():find("40 listed now, sells ~10 a day (est.)", 1, true), "its tooltip: what it means, from what")
check(#frame.Cells == 9 and select(4, cells[4]:GetPoint(1)) == select(4, cells[1]:GetPoint(1)), "nine numbers in three rows of three")
h.flow[FLOOD] = nil
P.Changed()
Ch.Draw()
check(cells.supply.Value:GetText() == "not known" and not Plain(frame.Info:GetText()):find("of supply", 1, true), "no sales estimate: not known")
frame:Hide()
-- A Stocks row: after the change.
do
	local parent = CreateFrame("Frame")
	local row = { Icon = parent:CreateTexture(), Title = parent:CreateFontString(), Money = parent:CreateFontString(),
		Sub = parent:CreateFontString(), Dots = {} }
	St.tab.Fill(row, { item = FLOOD })
	local plain = Plain(row.Sub:GetText())
	h.flow[FLOOD] = P.B36(today) .. "," .. P.B36(10) .. "," .. P.B36(DAY)
	St.tab.Fill(row, { item = FLOOD })
	check(not plain:find("supply", 1, true) and Plain(row.Sub:GetText()) == plain .. " · ~4 days of supply",
		"a Stocks row: after the change, only with a sales estimate: " .. Plain(row.Sub:GetText()))
end

-- Put back.
h.items, h.flow, h.sold, W.DB().ui, W.DB().watch = itemsWas, flowWas, soldWas, uiWas, watchWas
W.ItemActions = actionsWas
Hl.answer, Hl.job = nil, nil
for id in pairs(names) do ITEMS[id] = nil end
P.Changed()
GameTooltip:Hide()
