-- WhyPoor?'s charts (Chart.lua) on stand-ins for the data layer (P.Series, P.SeriesSpan, P.Get, P.Items: scan points
-- for five days, daily points with open/high/low/close before): the helpers (ranges and when they're available,
-- the default, thinning, round steps, time labels, the previous close), the big chart (the header, the change box,
-- the axes and their titles, scan vs daily points, segments bounded, gaps, dots, the previous close and the usual
-- price, the listed bars and the low-high band toggles, the numbers and their tooltips, the range buttons and
-- their tooltips, hover with its tooltip and the header, drag-select with the span's change, zoom and its reset),
-- + Watch, the saved size and place, the grip, Escape, no and one price, drawing only on changes and never while
-- closed, /whypoor chart; the small graph in the details (its axes, its tooltip, a click opens the big chart); the
-- dashboard (empty, adding by #ID, link, name over frames, watched, removing, moving, its range, tiles reflowing
-- with the width, tile tooltips, a click opens the big chart, saved); switched off.
-- Needs: whypoor_stocks.lua (runs after the Stocks tab's file, which leaves the watch list and the window as they were).
local suite = ...
local check, section, ns, LT = suite.check, suite.section, suite.ns, suite.LT

local W = ns.WhyPoor
local Ch, P, St = W.Chart, W.Prices, W.Stocks
local function Step(s) Advance(s or 1 / 60) end
local function Plain(text) return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function Lines() return table.concat(TOOLTIP.lines or {}, "\n") end
local function Enter(f) f._scripts.OnEnter(f) end
local DAY = 86400

section("WhyPoor?: the chart's data")
-- The stand-ins: an item's scans { t, price, qty }; P.Series gives them as they are when the span starts at most
-- five days back ("scan"), else a point a day (its last scan's time, the lowest, open/high/low/close: "day").
local real = { Series = P.Series, SeriesSpan = P.SeriesSpan, Get = P.Get, Items = P.Items }
local watchWas, uiWas = W.DB().watch, W.DB().ui
W.DB().watch, W.DB().ui = {}, {}
local FIX = {}
local now = time()
local ORE, GRAIN, GEM, SINGLE, NOTHING = 9701, 9702, 9703, 9704, 9705
ITEMS[ORE] = { name = "Chart Ore", quality = 1 }
ITEMS[GRAIN] = { name = "Chart Grain", quality = 1 }
ITEMS[GEM] = { name = "Chart Gem", quality = 2 }
ITEMS[SINGLE] = { name = "Chart Single", quality = 1 }
ITEMS[NOTHING] = { name = "Chart Nothing", quality = 1 }
local function Scans(item, list) FIX[item] = list end
do -- the ore: every 3 hours for 20 days, going up (10s to 14s), every other scan 15c higher; 10 to 17 listed
	local list = {}
	for k = 160, 0, -1 do
		local t = now - k * 3 * 3600 - 600 -- (10 minutes off the hour: no point on a range's edge)
		list[#list + 1] = { t = t, price = 1000 + math.floor((160 - k) * 2.5) + (k % 2) * 15, qty = 10 + k % 8 }
	end
	Scans(ORE, list)
end
do -- the grain: 2000 scans in the last day
	local list = {}
	for k = 1999, 0, -1 do
		list[#list + 1] = { t = now - k * 40, price = 500 + math.floor(100 * math.sin(k / 30)) + k % 7, qty = 5 }
	end
	Scans(GRAIN, list)
end
do -- the gem: a scan a day from 25 to 15 days ago and from 8 days ago on (a week without scans), going down
	local list = {}
	for d = 25, 0, -1 do
		if d >= 15 or d <= 8 then
			list[#list + 1] = { t = now - d * DAY - 600, price = 5000 + d * 100, qty = 3 }
		end
	end
	Scans(GEM, list)
end
Scans(SINGLE, { { t = now - 7200, price = 777, qty = 2 } })
Scans(NOTHING, {})
local function SeriesStub(item, from, to)
	local list = FIX[item] or {}
	if from >= time() - 5 * DAY - 60 then
		local out = {}
		for _, s in ipairs(list) do
			if s.t >= from and s.t <= to then out[#out + 1] = { t = s.t, price = s.price, qty = s.qty } end
		end
		return out, "scan"
	end
	local days, order = {}, {}
	for _, s in ipairs(list) do
		local d = math.floor(s.t / DAY)
		local e = days[d]
		if not e then
			e = { open = s.price, high = s.price, low = s.price }
			days[d] = e
			order[#order + 1] = d
		end
		e.t, e.close, e.qty = s.t, s.price, s.qty
		e.high, e.low = math.max(e.high, s.price), math.min(e.low, s.price)
	end
	local out = {}
	for _, d in ipairs(order) do
		local e = days[d]
		if e.t >= from and e.t <= to then
			out[#out + 1] = { t = e.t, price = e.low, qty = e.qty, open = e.open, high = e.high, low = e.low, close = e.close }
		end
	end
	return out, "day"
end
local function SpanStub(item)
	local list = FIX[item]
	if not (list and list[1]) then return nil end
	return list[1].t, list[#list].t, false
end
P.Series, P.SeriesSpan = SeriesStub, SpanStub
P.Get = function(item)
	local list = FIX[item]
	if not list then return real.Get(item) end
	local last = list[#list]
	if not last then return nil end
	return { low = last.price, qty = last.qty, seen = last.t, value = 1200, days = 14, unstable = item == GEM, confidence = "medium" }
end
P.Items = function() return { ORE, GRAIN, GEM, SINGLE, NOTHING } end
P.Changed()

-- Ranges.
local av = Ch.Available(now - 3 * DAY, now)
check(av["1D"] and av["5D"] and av.Max and not av["1M"] and not av["6M"] and not av["1Y"],
	"three days of prices: 1D, 5D and Max, not 1M and longer")
check(Ch.DefaultRange(av) == "5D" and Ch.DefaultRange(av, "1D") == "1D" and Ch.DefaultRange(av, "1Y") == "5D",
	"the default: the kept range when it shows something, else 1M, 5D or 1D")
av = Ch.Available(now - 400 * DAY, now)
local all = true
for _, r in ipairs(Ch.RANGES) do all = all and av[r] == true end
check(all, "more than a year: every range")
check(next(Ch.Available(nil, now)) == nil and Ch.DefaultRange(Ch.Available(nil, now)) == "Max", "nothing known: none")
local ytd = date("*t", Ch.RangeStart("YTD", now))
check(ytd.month == 1 and ytd.day == 1 and ytd.hour == 0 and Ch.RangeStart("1M", now) == now - 30 * DAY
	and Ch.RangeStart("Max", now, now - 50 * DAY) == now - 50 * DAY, "where ranges start (YTD: 1 January)")
-- Thinning, steps, time labels.
local many = {}
for k = 1, 1000 do many[k] = { t = k * 60, price = (k == 400 and 9999) or (k == 700 and 1) or 500 + k % 13 } end
local ds = Ch.Downsample(many, 60, 60000, 200)
local peak, dip, ordered = false, false, true
for i, p in ipairs(ds) do
	peak, dip = peak or p.price == 9999, dip or p.price == 1
	if i > 1 and p.t < ds[i - 1].t then ordered = false end
end
check(#ds <= 200 and ds[1] == many[1] and ds[#ds] == many[1000] and peak and dip and ordered,
	"1000 points thinned to 200 at most, in order, the first, the last, the peak and the dip kept: " .. #ds)
check(Ch.Downsample({ many[1], many[2] }, 0, 100, 200)[2] == many[2], "few points stay as they are")
check(Ch.NiceStep(1000, 4) == 500 and Ch.NiceStep(37, 4) == 10 and Ch.NiceStep(3, 4) == 1 and Ch.NiceStep(90000, 5) == 20000,
	"round steps: 1, 2 or 5 times a power of ten, 1c at least")
local ticks, kind = Ch.Ticks(now - DAY, now, 8)
check(kind == "hour" and #ticks >= 4 and #ticks <= 9 and (ticks[1].text:match("^%d%d:00$") or ticks[1].text:match("^%d+ %a+$")),
	"a day: hours, " .. #ticks .. " labels, " .. tostring(ticks[1] and ticks[1].text))
ticks, kind = Ch.Ticks(now - 5 * DAY, now, 8)
local weekday = { Sun = true, Mon = true, Tue = true, Wed = true, Thu = true, Fri = true, Sat = true }
check(kind == "day" and #ticks >= 4 and weekday[ticks[1].text], "five days: weekdays, got " .. tostring(ticks[1] and ticks[1].text))
ticks, kind = Ch.Ticks(now - 30 * DAY, now, 6)
check(kind == "day" and #ticks <= 7 and ticks[1].text:match("^%d+ %a+$"), "a month: dates, at most as many as fit")
ticks, kind = Ch.Ticks(now - 182 * DAY, now, 8)
check(kind == "month" and #ticks >= 5 and #ticks <= 8, "six months: months")
check(Ch.When(now - 7200, "scan"):match("^%a+ %d+ %a+, %d%d:%d%d$") and Ch.When(now, "day"):match("^%a+ %d+ %a+$"),
	"when: the day, and the time for a scan: " .. Ch.When(now - 7200, "scan"))
local text = Ch.Change(1000, 1100)
check(text == "+1s (+10.0%)" and select(3, Ch.Change(1000, 900)) == -1 and select(3, Ch.Change(5, 5)) == 0,
	"a change: absolute and percent, its sign: " .. tostring(text))
check(Ch.PrevClose(ORE, now - DAY) == FIX[ORE][153].price, "the previous close: the last price before the range")
check(Ch.ParseItem("#9701") == ORE and Ch.ParseItem(ItemLink(ORE)) == ORE and Ch.ParseItem("9701") == ORE
	and Ch.ParseItem("ore") == nil, "an item from text: #ID, a link, a number")
-- The fallback without the data layer: P.History's days.
P.Series, P.SeriesSpan = nil, nil
local pts, res = Ch.Points(ORE, now - 30 * DAY, now)
check(res == "day" and type(pts) == "table" and Ch.Span(NOTHING) == nil, "without P.Series: P.History's daily lows")
P.Series, P.SeriesSpan = SeriesStub, SpanStub

---------------------------------------------------------------------------
section("WhyPoor?: the big chart")
check(Ch.Open(ORE) == true, "Ch.Open: true")
local frame, state, w, Ds = Ch.View()
check(frame:IsShown() and frame:GetName() == "LefthyToolsWhyPoorChart" and frame:GetFrameStrata() == "DIALOG", "its own window")
local escape = false
for _, name in ipairs(UISpecialFrames) do escape = escape or name == "LefthyToolsWhyPoorChart" end
check(escape and frame._movable and frame._resizable and frame._resizeBounds ~= nil, "Escape closes it; movable, resizable")
check(Plain(frame.Item.Name:GetText()) == "Chart Ore" and frame.Item.Icon.path == 1000 + ORE, "the item's icon and name")
Enter(frame.Item)
check(TOOLTIP.link == "item:9701", "the name's tooltip: the item's")
-- 20 days of prices: 1M by default (daily points).
check(state.range == "1M" and w.res == "day" and #w.points == 21, "20 days: 1M, a point a day, got " .. tostring(state.range) .. " " .. #w.points)
local last = FIX[ORE][#FIX[ORE]]
check(frame.Price:GetText() == W.Money(last.price), "the latest price big: " .. tostring(frame.Price:GetText()))
local first1M = w.points[1]
check(frame.Change:IsShown() and frame.Change.Text:GetText() == Ch.Change(first1M.open, last.price) and frame.Change.Arrow.path == "Interface\\Buttons\\Arrow-Up-Up"
	and w.color == Ch.UP, "up over the range: green, the arrow up, the change: " .. tostring(frame.Change.Text:GetText()))
check(Plain(frame.Over:GetText()) == "over the last 30 days" and Plain(frame.Info:GetText()):find("Last 30 days", 1, true)
	and Plain(frame.Info:GetText()):find("last scan", 1, true), "over what, when it was last scanned: " .. Plain(frame.Info:GetText()))
Enter(frame.Change)
check(TOOLTIP.title == "Change" and Lines():find("From ", 1, true) and Lines():find("over the last 30 days", 1, true),
	"the change's tooltip: from what to what, over the range")
-- The axes.
check(w:Count("ylab") >= 2 and w:Count("grid") >= 2 and w.YTitle:IsShown() and w.YTitle:GetText() == "Lowest price for one",
	"the y axis: grid lines with money labels and its title")
local ylabs = {}
for _, fs in ipairs(w.pools.ylab.list) do if fs:IsShown() then ylabs[#ylabs + 1] = fs:GetText() end end
check(ylabs[1]:match("s") ~= nil, "the labels are money: " .. table.concat(ylabs, ", "))
check(w:Count("xlab") >= 3 and w.XTitle:GetText() == "Day" and w.tickKind == "day", "the x axis: dates and its title")
check(w:Count("line") == 20 and w:Count("fill") > 20 and w:Count("fill") <= 200 and w:Count("dot") == 21,
	"the line, the area under it (columns), a dot per point while few: " .. w:Count("line") .. " " .. w:Count("fill") .. " " .. w:Count("dot"))
check(w:Count("dash") > 0 and w:Count("note") == 1 and Plain(w.pools.note.list[1]:GetText()) == "Usual 12s",
	"the usual price: a dotted gold line, labelled")
check(w:Count("vol") == 21, "how many were listed: a bar a point")
-- The numbers.
local cells = frame.Cells
local oreDays, seenDay = 0, {} -- (the engine's days with a scan: time() / 86400)
for _, scan in ipairs(FIX[ORE]) do
	local day = math.floor(scan.t / DAY)
	if not seenDay[day] then seenDay[day], oreDays = true, oreDays + 1 end
end
check(cells.open.Value:GetText() == W.Money(first1M.open) and cells.listed.Value:GetText() == tostring(last.qty)
	and cells.usual.Value:GetText() == "12s" and cells.steady.Value:GetText() == "steady" and cells.days.Value:GetText() == tostring(oreDays),
	"the numbers: open, listed now, usual, steady, days of data: " .. tostring(cells.open.Value:GetText()) .. " " .. tostring(cells.listed.Value:GetText())
	.. " " .. tostring(cells.usual.Value:GetText()) .. " " .. tostring(cells.steady.Value:GetText()) .. " " .. tostring(cells.days.Value:GetText()))
local hi = 0
for _, p in ipairs(w.points) do hi = math.max(hi, p.high) end
check(cells.high.Value:GetText() == W.Money(hi) and cells.known.Value:GetText():find(" / ", 1, true), "high, known high / low")
Enter(cells.usual)
check(TOOLTIP.title == "Usual" and Lines():find("time-weighted median", 1, true) and Lines():find("From 14 days of prices", 1, true),
	"a number's tooltip: what it means, where it comes from")
Enter(cells.days)
check(Lines():find("Since ", 1, true), "days of data: since when")
-- The ranges.
local ranges = frame.Ranges
check(not ranges["1D"].off and not ranges["5D"].off and not ranges["1M"].off and not ranges.Max.off and ranges["6M"].off
	and ranges["1Y"].off and ranges["1M"].Line:IsShown(), "20 days: 1D 5D 1M Max, the longer ones greyed; 1M underlined")
Enter(ranges["1Y"])
check(TOOLTIP.title == "Last 12 months" and Lines():find("No prices that far back yet", 1, true), "a greyed range's tooltip says why")
Enter(ranges["5D"])
check(TOOLTIP.title == "Last 5 days" and Lines() == "", "a range's tooltip")
ranges["1Y"]:Click()
check(state.range == "1M", "a greyed range does nothing")
-- 1D: scans, the previous close.
ranges["1D"]:Click()
check(state.range == "1D" and w.res == "scan" and #w.points == 8 and W.DB().ui.chart.range == "1D",
	"1D: every scan of the last 24 hours, kept: " .. #w.points)
check(w.extra.prev == Ch.PrevClose(ORE, now - DAY) and Plain(w.pools.note.list[1]:GetText()):find("Previous close", 1, true)
	and w:Count("dash") > 60, "1D: the previous close as a dotted line with its label")
check(frame.Change.Text:GetText() == Ch.Change(w.extra.prev, last.price), "1D's change: from the previous close")
check(w.XTitle:GetText() == "Time of day" and w.tickKind == "hour", "1D: hours")
check(frame.Toggles.band.off, "the low-high band only for daily points")
Enter(frame.Toggles.band)
check(Lines():find("Only for daily points", 1, true), "its tooltip says so")
ranges.Max:Click()
check(state.range == "Max" and w.res == "day" and #w.points == 21, "Max: everything known")
-- Hover.
ranges["5D"]:Click()
local draws = state.draws
local p5 = w.points[10]
w:HoverAt(w:X(p5.t))
check(w.Cross:IsShown() and w.Dot:IsShown() and w.hoverI == 10, "hover: the crosshair and the dot on the nearest point")
check(TOOLTIP.shown and TOOLTIP.owner == w.plot and TOOLTIP.title == Ch.When(p5.t, "scan")
	and Lines():find("Lowest price for one  " .. W.Money(p5.price), 1, true) and Lines():find("Listed  " .. p5.qty, 1, true)
	and Lines():find("Drag: compare two points", 1, true), "its tooltip: when, the price for one, how many were listed")
check(TOOLTIP.points and TOOLTIP.points[1] and TOOLTIP.points[1][2] == w.plot, "the tooltip at the crosshair")
check(frame.Price:GetText() == W.Money(p5.price) and Plain(frame.Info:GetText()):find(p5.qty .. " listed", 1, true)
	and frame.Change.Text:GetText() == Ch.Change(w.points[1].price, p5.price), "the header follows: its price, since the range's start")
check(state.draws == draws, "hovering doesn't redraw")
-- The cursor through the plot's scripts.
w.plot._scripts.OnEnter(w.plot)
CURSOR.x = w:X(w.points[3].t)
Step()
check(w.hoverI == 3, "the cursor moved: the nearest point, got " .. tostring(w.hoverI) .. " " .. tostring(w.plot._scripts.OnUpdate))
w.plot._scripts.OnLeave(w.plot)
check(not w.Cross:IsShown() and not TOOLTIP.shown and frame.Price:GetText() == W.Money(last.price), "left: gone, the header back")
-- A day's tooltip.
ranges["1M"]:Click()
w:HoverAt(w:X(w.points[5].t))
check(Lines():find("Open price", 1, true) and Lines():find("High", 1, true) and Lines():find("Close", 1, true)
	and Lines():find("Change from the day before", 1, true) and Lines():find("Lowest price that day", 1, true),
	"a day's tooltip: open, high, low, close, the change from the day before")
w:Unhover()
-- Drag to select, zoom, reset.
local a, b = w.points[4], w.points[12]
w.plot._scripts.OnEnter(w.plot)
CURSOR.x = w:X(a.t)
w.plot._scripts.OnMouseDown(w.plot, "LeftButton")
CURSOR.x = w:X(b.t)
Step()
check(w.Span:IsShown() and w.dragged and TOOLTIP.title == Ch.When(a.t, "day") .. " to " .. Ch.When(b.t, "day")
	and Lines():find("Change  " .. Ch.Change(a.price, b.price), 1, true), "dragging: the span shaded, its change in the tooltip")
check(frame.Change.Text:GetText() == Ch.Change(a.price, b.price) and Plain(frame.Over:GetText()):find(" to ", 1, true),
	"and in the header")
w.plot._scripts.OnMouseUp(w.plot, "LeftButton")
w.plot._scripts.OnClick(w.plot, "LeftButton")
check(state.zoom and state.zoom[1] == a.t and state.zoom[2] == b.t and w.from == a.t and w.to == b.t and #w.points == 9
	and frame.Reset:IsShown() and not ranges["1M"].Line:IsShown(), "released: zoomed to the span, Reset shown, no range picked")
check(w.hoverI ~= nil, "drawn again under the cursor: the crosshair stays")
w.plot._scripts.OnLeave(w.plot)
check(Plain(frame.Info:GetText()):find(" to ", 1, true) and Plain(frame.Over:GetText()):find(" to ", 1, true),
	"the line under the price: the span")
w.plot._scripts.OnClick(w.plot, "RightButton")
check(state.zoom == nil and state.range == "1M" and not frame.Reset:IsShown(), "right-click: back to the range")
w:DragStart(w:X(a.t))
w:DragEnd(w:X(a.t + 1))
check(state.zoom == nil, "a click without dragging doesn't zoom")
w:DragStart(w:X(a.t))
w:DragEnd(w:X(b.t))
frame.Reset:Click()
check(state.zoom == nil, "Reset: back")
w:DragStart(w:X(a.t))
w:DragEnd(w:X(b.t))
ranges["5D"]:Click()
check(state.zoom == nil and state.range == "5D", "a range: not zoomed any more")
w.plot._scripts.OnLeave(w.plot)
-- Toggles.
frame.Toggles.volume:Click()
check(W.DB().ui.chart.volume == false and w:Count("vol") == 0 and w.vh == 0, "Listed off: no bars, the price uses the whole height, kept")
frame.Toggles.volume:Click()
do -- The volume panel: under the price, its title and scale, how many changed over the range.
	local most = 0
	for _, p in ipairs(w.ds) do most = math.max(most, p.qty or 0) end
	local title = w.pools.vtitle and w.pools.vtitle.list[1]
	local lowest = math.huge
	for _, p in ipairs(w.points) do lowest = math.min(lowest, w:Y(p.price)) end
	check(w.vh > 0 and w:Count("vol") > 0 and title and title:IsShown() and Plain(title:GetText()) == "Listed" and lowest >= w.base,
		"Listed on: bars in a panel of their own, titled, the price line above it")
	local scale = false
	for _, fs in ipairs(w.pools.ylab.list) do scale = scale or (fs:IsShown() and fs:GetText() == tostring(math.floor(most + 0.5))) end
	check(scale, "the panel's scale: the most listed in sight (" .. most .. ")")
	local listed = Ch.ListedChange(w.points)
	check(listed ~= nil and Plain(frame.Info:GetText()):find(listed, 1, true) ~= nil,
		"the header says how many were listed at the start and now: " .. Plain(frame.Info:GetText()))
	check(Ch.ListedChange(nil, { qty = 120 }, { qty = 40 }) == "listed 120 -> 40 (-67%)"
		and Ch.ListedChange(nil, { qty = 10 }, { qty = 15 }) == "listed 10 -> 15 (+50%)" and Ch.ListedChange({ { qty = 0 } }) == nil,
		"the listed change: counts and percent; none without counts")
end
do -- Sold a day (estimated): a gold step line in the volume panel, its title, the header, a point's tooltip.
	local realSold = P.SoldSeries
	local today = math.floor(time() / DAY)
	local days = {}
	for d = today - 4, today do
		days[#days + 1] = { t = d * DAY + DAY / 2, day = d, gone = 10 + (today - d), span = 4 * 3600, perDay = (10 + (today - d)) * 6 }
	end
	P.SoldSeries = function(item, from, to)
		local out = {}
		for _, d in ipairs(days) do if (d.day + 1) * DAY > from and d.day * DAY <= to then out[#out + 1] = d end end
		return out, 72, 0, 0
	end
	Ch.Draw()
	local title = w.pools.vtitle.list[1]
	check(w:Count("sline") >= 5 and Plain(title:GetText()) == "Listed (bars) · sold a day, est. (line)",
		"sold a day: a step a day as a line in the panel, the title says which is which (" .. w:Count("sline") .. " lines)")
	check(Plain(frame.Info:GetText()):find("sells ~72 a day (est.)", 1, true) ~= nil, "the header: sells ~72 a day: " .. Plain(frame.Info:GetText()))
	local p = w.points[#w.points]
	w:HoverAt(w:X(p.t))
	local want
	for _, d in ipairs(days) do if d.day == math.floor(p.t / DAY) then want = Ch.PerDay(d.perDay) end end
	check(want and Lines():find("Sold that day (est.)  " .. want, 1, true), "a point's tooltip: that day's estimate")
	w.plot._scripts.OnLeave(w.plot)
	frame.Toggles.sold:Click()
	check(w:Count("sline") == 0 and not Plain(frame.Info:GetText()):find("sells", 1, true) and W.DB().ui.chart.sold == false,
		"Sold a day off: no line, kept")
	frame.Toggles.sold:Click()
	Enter(frame.Toggles.sold)
	check(TOOLTIP.title == "Sold a day" and Lines():find("Cancelled ones count too", 1, true), "its tooltip says what it is, and that it's an estimate")
	check(Ch.PerDay(240) == "~240" and Ch.PerDay(2.46) == "~2.5" and Ch.SellsText(nil) == nil, "how a count a day reads")
	P.SoldSeries = realSold
	Ch.Draw()
end
frame.Toggles.usual:Click()
check(w:Count("note") == 0 and w:Count("dash") == 0, "Usual off: no gold line")
frame.Toggles.usual:Click()
ranges["1M"]:Click()
frame.Toggles.band:Click()
check(not frame.Toggles.band.off and w:Count("band") > 0 and w:Count("fill") == 0, "High/low on daily points: the band instead of the area")
frame.Toggles.band:Click()
Enter(frame.Toggles.volume)
check(TOOLTIP.title == "Listed" and Lines():find("panel under the price", 1, true), "a toggle's tooltip")
-- Segments bounded, gaps.
Ch.Open(GRAIN)
check(state.range == "1D" and #w.points == 2000 and w:Count("line") <= 200 and w:Count("fill") <= 200 and w:Count("dot") == 0
	and w:Count("vol") <= 200, "2000 scans: 200 segments at most, no dots: " .. w:Count("line") .. " " .. w:Count("fill"))
w:HoverAt(w:X(w.points[1500].t))
check(w.hoverI == 1500, "hover still finds every point")
w:Unhover()
Ch.Open(GEM)
local faint = 0
for _, l in ipairs(w.pools.line.list) do if l:IsShown() and l.gap then faint = faint + 1 end end
check(state.range == "1M" and faint == 1 and w.color == Ch.DOWN and frame.Change.Arrow.path == "Interface\\Buttons\\Arrow-Down-Up",
	"a week without scans: that segment faint; going down: red")
check(cells.steady.Value:GetText():find("jumps around", 1, true), "jumps around: said")
-- + Watch.
check(frame.Watch:IsShown() and frame.Watch:GetText() == "+ Watch", "not watched: + Watch")
Enter(frame.Watch)
check(Lines():find("watch list", 1, true), "its tooltip")
frame.Watch:Click()
check(St.Watched(GEM) and frame.Watch:GetText() == "Watching", "clicked: watched (the Stocks tab's list)")
Enter(frame.Watch)
check(TOOLTIP.title == "Watching" and Lines():find("stop watching", 1, true), "Watching's tooltip")
frame.Watch:Click()
check(not St.Watched(GEM) and frame.Watch:GetText() == "+ Watch", "again: not watched")
-- No price, one price.
Ch.Open(NOTHING)
check(#w.points == 0 and w.Msg:IsShown() and w.Msg:GetText() == "No prices yet: open the auction house." and frame.Price:GetText() == "-"
	and not frame.Change:IsShown() and w:Count("line") == 0, "no prices: says so, nothing drawn")
check(ranges["1D"].off and ranges.Max.off, "no ranges")
Ch.Open(SINGLE)
check(#w.points == 1 and w:Count("dot") == 1 and w:Count("line") == 0 and w.Msg:IsShown()
	and w.Msg:GetText():find("One scan so far: 7s 77c", 1, true), "one scan: its dot, and says so: " .. tostring(w.Msg:GetText()))
-- Size and place: kept, and taken by a new window.
Ch.Open(ORE)
Enter(frame.Grip)
check(TOOLTIP.title == "Resize" and Lines():find("resize the window", 1, true), "the grip's tooltip")
frame.Grip._scripts.OnMouseDown(frame.Grip)
check(frame._sizing == "BOTTOMRIGHT", "the grip: resizing from the corner")
frame._dropSize = { 900, 600 }
frame.Grip._scripts.OnMouseUp(frame.Grip)
draws = state.draws
Step()
check(W.DB().ui.chart.w == 900 and W.DB().ui.chart.h == 600 and w.width == 880 and state.draws == draws + 1,
	"resized: the size kept, the chart laid out and drawn again")
frame._dropAt = { left = 120, top = 700 }
frame._scripts.OnDragStop(frame)
check(W.DB().ui.chart.left == 120 and W.DB().ui.chart.top == 700, "moved: the place kept")
local again = Ch.NewWindow("LefthyToolsWhyPoorChartTest", "chart", 760, 520, 540, 400)
check(again:GetWidth() == 900 and again:GetHeight() == 600 and again:GetLeft() == 120 and again:GetTop() == 700,
	"a window made again takes the kept size and place")
-- Drawing only on changes, nothing while closed.
Step()
draws = state.draws
Advance(2.5)
check(state.draws <= draws + 1, "nothing changed: no redraw (but the minute's age)")
draws = state.draws
P.Changed()
Advance(1.1)
check(state.draws == draws + 1, "the prices changed: drawn once")
frame:Hide()
draws = state.draws
P.Changed()
Advance(2)
check(state.draws == draws, "closed: nothing")
-- /whypoor chart.
SlashCmdList.LEFTHYTOOLS_WHYPOOR("chart #9703")
check(frame:IsShown() and state.item == GEM, "/whypoor chart #ID")
SlashCmdList.LEFTHYTOOLS_WHYPOOR("chart " .. ItemLink(ORE))
check(state.item == ORE, "/whypoor chart <link>")
SlashCmdList.LEFTHYTOOLS_WHYPOOR("chart Chart Single")
check(state.item == SINGLE, "/whypoor chart <a name the game knows>")
local mark = #PRINTED
SlashCmdList.LEFTHYTOOLS_WHYPOOR("chart")
check(#PRINTED > mark and PRINTED[#PRINTED]:find("/whypoor chart <item link or #id>", 1, true), "without an item: how")
frame:Hide()

---------------------------------------------------------------------------
section("WhyPoor?: the small graph in the details")
do
	W.Window.Open("stocks")
	local _, _, _, D = W.Window.View()
	D.Begin()
	D.Graph(ORE)
	D.End()
	local m = D.chart
	check(D.graph:IsShown() and m.mini and #m.points == 21 and m:Count("line") == 20 and m:Count("fill") > 0 and m:Count("ylab") == 0,
		"the details' graph: a small chart of the last 30 days, line and fill, no grid")
	check(m:Count("corner") == 2 and m:Count("xlab") == 2 and Plain(m.pools.xlab.list[2]:GetText()) == "now",
		"its axes: the lowest and highest price, the first day and now")
	check(m:Count("level") == 1, "the usual price as a line")
	m:HoverAt(m:X(m.points[3].t))
	check(TOOLTIP.shown and Lines():find("Click: the big chart", 1, true), "its tooltip: the point, click for the big chart")
	m:Unhover()
	local texts = {}
	for _, fs in ipairs(D.texts) do if fs:IsShown() then texts[#texts + 1] = Plain(fs:GetText()) end end
	check(table.concat(texts, "\n"):find("Click the graph", 1, true), "a line says it opens the big chart")
	m.plot:Click("LeftButton")
	check(frame:IsShown() and state.item == ORE, "a click: the big chart of it")
	frame:Hide()
	D.Begin()
	D.Graph(SINGLE)
	D.End()
	check(not D.graph:IsShown(), "one price: no graph, says so")
	W.Window.View():Hide()
end

---------------------------------------------------------------------------
section("WhyPoor?: the dashboard")
do
	check(Ch.OpenDashboard() == true, "Ch.OpenDashboard: true")
	local f = Ds.frame
	check(f:IsShown() and f:GetName() == "LefthyToolsWhyPoorDashboard" and f.Message:IsShown() and f.Box:IsShown() and f.AddWatched:IsShown(),
		"empty: says so, the add controls shown")
	f:Hide()
	SlashCmdList.LEFTHYTOOLS_WHYPOOR("dashboard")
	check(f:IsShown(), "/whypoor dashboard")
	Enter(f.Box)
	check(TOOLTIP.title == "Add an item", "the box's tooltip")
	Enter(f.Edit)
	check(TOOLTIP.title == "Edit", "Edit's tooltip")
	f.Box:SetText("#9701")
	f.Box._scripts.OnEnterPressed(f.Box)
	check(Ds.Items()[1] == ORE and Plain(f.Status:GetText()) == "Added: Chart Ore" and f.Box:GetText() == "", "#ID: added")
	f.Box:SetText(ItemLink(GEM))
	f.Add:Click()
	check(Ds.Items()[2] == GEM, "a link: added")
	f.Box:SetText("#9701")
	f.Add:Click()
	check(#Ds.Items() == 2 and Plain(f.Status:GetText()):find("Already on the dashboard", 1, true), "twice: said")
	f.Box:SetText("chart gr")
	f.Add:Click()
	check(Plain(f.Status:GetText()) == "Searching..." and Ds.driver:IsShown(), "part of a name: searched over frames")
	Step()
	check(Ds.Items()[3] == GRAIN and not Ds.driver:IsShown(), "found by name: added")
	f.Box:SetText("no such thing")
	f.Add:Click()
	Step()
	check(#Ds.Items() == 3 and Plain(f.Status:GetText()):find("No item by that name", 1, true), "not found: said")
	W.DB().watch = { SINGLE, ORE }
	f.AddWatched:Click()
	check(#Ds.Items() == 4 and Ds.Items()[4] == SINGLE and Plain(f.Status:GetText()) == "1 added", "Add all watched: the ones missing")
	W.DB().watch = {}
	check(W.DB().ui.dashboard.items[3] == GRAIN, "saved in the module's saved variables")
	Step()
	-- Many tiles: their charts over frames.
	local kept = W.DB().ui.dashboard.items
	local many = { ORE, GEM, GRAIN, SINGLE }
	for k = 1, 10 do many[#many + 1] = 9710 + k end
	W.DB().ui.dashboard.items = many
	Ds.Draw()
	check(Ds.fill and Ds.fill.next == Ds.C.PER_TICK + 1 and Ds.tiles[12]:IsShown() and Ds.tiles[12].widget.from == nil,
		"14 tiles: laid out at once, " .. Ds.C.PER_TICK .. " charts drawn, the rest waiting")
	Step()
	check(Ds.fill == nil and Ds.tiles[14].widget.from ~= nil and Ds.tiles[14].widget.Msg:GetText() == "No prices yet: open the auction house.",
		"the next frame: the rest (no prices: says so)")
	W.DB().ui.dashboard.items = kept
	Ds.Draw()
	Step()
	-- Tiles.
	local t1 = Ds.tiles[1]
	check(t1:IsShown() and Plain(t1.Name:GetText()) == "Chart Ore" and t1.Price:GetText() == W.Money(FIX[ORE][#FIX[ORE]].price)
		and Plain(t1.Change:GetText()):find("%+"), "a tile: name, price, change (green)")
	check(t1.widget:Count("line") > 0 and t1.widget:Count("line") <= Ch.TILE_SEG, "its chart")
	local t3 = Ds.tiles[3]
	check(t3.widget.res == "day" and #t3.widget.points <= 2, "the grain on 1M: daily points")
	f.Ranges["1D"]:Click()
	check(W.DB().ui.dashboard.range == "1D" and #t3.widget.points == 2000 and t3.widget:Count("line") <= Ch.TILE_SEG,
		"the range for all, kept; 2000 scans in a tile: 60 segments at most, got " .. t3.widget:Count("line"))
	check(t1.widget.extra.prev ~= nil, "1D: the previous close in a tile")
	Enter(t1)
	check(Plain(TOOLTIP.title) == "Chart Ore" and Lines():find("over the last 24 hours", 1, true) and Lines():find("Click: the big chart", 1, true),
		"a tile's tooltip: its change over the range, click for the big chart")
	t1.widget:HoverAt(t1.widget:X(t1.widget.points[2].t))
	check(TOOLTIP.owner == t1.widget.plot and Lines():find("Lowest price for one", 1, true), "hover on a tile's chart: the point")
	t1.widget:Unhover()
	-- Columns follow the width.
	f._dropSize = { 1100, 520 }
	f.Grip._scripts.OnMouseDown(f.Grip)
	f.Grip._scripts.OnMouseUp(f.Grip)
	Step()
	local x2 = select(4, Ds.tiles[2]:GetPoint(1))
	local x4 = select(4, Ds.tiles[4]:GetPoint(1))
	check(x2 > 0 and x4 > 0 and W.DB().ui.dashboard.w == 1100, "wide: four columns")
	f._dropSize = { 500, 520 }
	f.Grip._scripts.OnMouseDown(f.Grip)
	f.Grip._scripts.OnMouseUp(f.Grip)
	Step()
	x2 = select(4, Ds.tiles[2]:GetPoint(1))
	local x3 = select(4, Ds.tiles[3]:GetPoint(1))
	check(x2 > 0 and x3 == 0, "narrow: two columns")
	-- Edit: move, remove.
	f.Edit:Click()
	check(Ds.editing and t1.Remove:IsShown() and t1.Right:IsShown() and not t1.Left:IsEnabled() and f.Edit:GetText() == "Done",
		"Edit: each tile's < > x, Done")
	Enter(t1.Remove)
	check(TOOLTIP.title == "Remove", "x's tooltip")
	t1.Right:Click()
	check(Ds.Items()[1] == GEM and Ds.Items()[2] == ORE, "> : one place later")
	Ds.tiles[2].Left:Click()
	check(Ds.Items()[1] == ORE, "< : one place earlier")
	Ds.tiles[4].Remove:Click()
	check(#Ds.Items() == 3 and not Ds.tiles[4]:IsShown(), "x: off the dashboard")
	f.Edit:Click()
	check(not Ds.editing and not t1.Remove:IsShown() and not f.Box:IsShown(), "Done: the controls gone")
	-- A click: the big chart.
	Ds.tiles[2]:Click()
	check(frame:IsShown() and state.item == GEM, "a tile's click: its big chart")
	frame:Hide()
	Ds.tiles[1].widget.plot:Click("LeftButton")
	check(frame:IsShown() and state.item == ORE, "a click on its chart too")
	frame:Hide()
	-- Only on changes, nothing while closed.
	Step()
	local d = Ds.draws
	Step(0.5)
	check(Ds.draws == d, "nothing changed: no redraw")
	f:Hide()
	P.Changed()
	Advance(2)
	check(Ds.draws == d, "closed: nothing")
end

---------------------------------------------------------------------------
section("WhyPoor?: the charts switched off")
do
	Ch.Open(ORE)
	Ch.OpenDashboard()
	LT:SetModuleEnabled("whypoor", false)
	Step()
	check(not frame:IsShown() and not Ds.frame:IsShown() and Ch.Open(ORE) == false, "off: both closed, not opened")
	LT:SetModuleEnabled("whypoor", true)
	Step()
end

-- Put back.
P.Series, P.SeriesSpan, P.Get, P.Items = real.Series, real.SeriesSpan, real.Get, real.Items
W.DB().watch, W.DB().ui = watchWas, uiWas
for _, item in ipairs({ ORE, GRAIN, GEM, SINGLE, NOTHING }) do ITEMS[item] = nil end
P.Changed()
GameTooltip:Hide()
