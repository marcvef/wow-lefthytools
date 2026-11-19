local _, ns = ...
local LT = ns.LT
local L = ns.L
local W = ns.WhyPoor or {}
ns.WhyPoor = W

-- WhyPoor?'s price charts (W.Chart, Ch), like a stock app's: docs/whypoor.md, Chart.
--   * The widget (Ch.NewWidget): an item's price on your auction house over a span of time as a line with the
--     area under it filled, green when the span went up, red when down, grey when flat; a dotted previous close
--     (1D), the usual price as a gold line, how many were listed in a panel under the price, each day's
--     low-high band (daily points); grid lines with money labels, time labels suited to the span and both axes'
--     titles. Hover: a crosshair on the nearest point and a tooltip (time, price, listed, the day's open, high,
--     low, close and change); dragging selects a span (its change, high and low) and zooms to it on release;
--     right-click goes back. Small ones (the details' graph, the dashboard's tiles) keep only the range's
--     lowest and highest price and its first and last day, and open the big chart on a click.
--   * The big chart (Ch.Open(item), /whypoor chart): its own window: the item, its latest price big, the change
--     over the range (a red or green box), when it was last scanned, + Watch, the ranges 1D 5D 1M 6M YTD 1Y Max
--     (greyed without prices that far back), the chart and a grid of numbers (open, high, low, listed now, usual,
--     steady, all known high and low, days of data, days of supply).
--   * The dashboard (Ch.OpenDashboard(), /whypoor dashboard): a window of two pages: My charts, tiles of a small
--     chart each over one range for all (Edit adds: a name, a link, #id, or every watched item; removes and moves
--     them), and Highlights (Highlights.lua, /whypoor highlights): items rising, falling, scarce, flooded or cheap.
-- Data: P.Series / P.SeriesSpan (Prices.lua), else P.History's daily lows. Both windows are movable, resizable
-- (the corner grip), closed by Escape, their place, size and choices kept in LefthyToolsWhyPoorDB.ui.
-- What it costs: a chart is drawn only when what it shows changed (item, range, size, P.Revision, a toggle), from
-- pools of lines and textures, at most MAX_SEG segments (the points thinned to the width); hovering moves only
-- the crosshair and the tooltip, when the nearest point changes. Closed, nothing of it runs.

local Ch = { lower = {} }
W.Chart = Ch

local GREY, ORANGE, SEP = "|cff888888", "|cffff9933", " · "
local HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local DAY = 86400
Ch.MAX_SEG, Ch.DOTS, Ch.TILE_SEG, Ch.TILE_MAX = 200, 30, 60, 40
Ch.RANGES = { "1D", "5D", "1M", "6M", "YTD", "1Y", "Max" }
Ch.LABELS = { ["1D"] = L["1D"], ["5D"] = L["5D"], ["1M"] = L["1M"], ["6M"] = L["6M"], YTD = L["YTD"], ["1Y"] = L["1Y"],
	Max = L["Max"] }
Ch.TIPS = { ["1D"] = L["Last 24 hours"], ["5D"] = L["Last 5 days"], ["1M"] = L["Last 30 days"], ["6M"] = L["Last 6 months"],
	YTD = L["Since 1 January"], ["1Y"] = L["Last 12 months"], Max = L["Everything known"] }
Ch.OVER = { ["1D"] = L["over the last 24 hours"], ["5D"] = L["over the last 5 days"], ["1M"] = L["over the last 30 days"],
	["6M"] = L["over the last 6 months"], YTD = L["since 1 January"], ["1Y"] = L["over the last 12 months"],
	Max = L["over everything known"] }
Ch.WD = { L["Sun"], L["Mon"], L["Tue"], L["Wed"], L["Thu"], L["Fri"], L["Sat"] }
Ch.MON = { L["Jan"], L["Feb"], L["Mar"], L["Apr"], L["May"], L["Jun"], L["Jul"], L["Aug"], L["Sep"], L["Oct"], L["Nov"], L["Dec"] }
Ch.UP, Ch.DOWN, Ch.FLAT = { 0.25, 0.85, 0.4 }, { 1, 0.35, 0.35 }, { 0.65, 0.65, 0.65 }

local function Num(v)
	return type(v) == "number" and not LT.IsSecret(v) and v or nil
end

local function Money(c)
	return W.Money(c) or "-"
end

local function Clock()
	local ok, ms = pcall(debugprofilestop)
	return ok and type(ms) == "number" and ms or nil
end

local function Untip(self)
	if GameTooltip:IsOwned(self) then
		GameTooltip:Hide()
	end
end

-- A tooltip of a title and lines (grey) on a frame.
function Ch.Tip(owner, title, ...)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(title, 1, 0.82, 0)
	for i = 1, select("#", ...) do
		local line = select(i, ...)
		if line then
			GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true)
		end
	end
	GameTooltip:Show()
end

-- A frame's OnEnter showing Ch.Tip of what self.tip() returns (title, lines...).
function Ch.TipEnter(self)
	if self.tip then
		Ch.Tip(self, self.tip(self))
	end
end

function Ch.SetTip(frame, fn)
	frame.tip = fn
	frame:SetScript("OnEnter", Ch.TipEnter)
	frame:SetScript("OnLeave", Untip)
end

---------------------------------------------------------------------------
-- Words: times, changes
---------------------------------------------------------------------------

-- "Tue 3 Nov" (and the year when it isn't this one), with the time for a scan's point: "Tue 3 Nov, 14:05".
function Ch.When(t, res)
	local d = date("*t", math.floor(t))
	local text = Ch.WD[d.wday] .. " " .. L["%d %s"]:format(d.day, Ch.MON[d.month])
	if d.year ~= date("*t", time()).year then
		text = text .. " " .. d.year
	end
	if res ~= "day" then
		text = text .. ", " .. ("%02d:%02d"):format(d.hour, d.min)
	end
	return text
end

-- "3 Nov" (a day short).
function Ch.Short(t)
	local d = date("*t", math.floor(t))
	return L["%d %s"]:format(d.day, Ch.MON[d.month])
end

-- From a to b: the text ("+1s 20c (+12.5%)"), its colour (Ch.UP, DOWN, FLAT) and the sign.
function Ch.Change(a, b)
	a, b = Num(a), Num(b)
	if not (a and b) then
		return nil, Ch.FLAT, 0
	end
	local diff = b - a
	local sign = diff > 0.5 and 1 or diff < -0.5 and -1 or 0
	local text = (sign > 0 and "+" or "") .. Money(diff)
	if a > 0 then
		text = text .. " (" .. (sign > 0 and "+" or "") .. LT.Decimal(("%.1f"):format(diff / a * 100)) .. "%)"
	end
	return text, sign > 0 and Ch.UP or sign < 0 and Ch.DOWN or Ch.FLAT, sign
end

function Ch.Hex(c)
	return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

-- How many were listed at the first and the last point with a count (or between two points): "listed 120 -> 40
-- (-67%)", so a price going up can be told from fewer being offered. nil: no counts.
function Ch.ListedChange(points, a, b)
	if not (a and b) then
		for _, p in ipairs(points or {}) do
			if (p.qty or 0) > 0 then
				a = a or p
				b = p
			end
		end
	end
	local x, y = a and Num(a.qty), b and Num(b.qty)
	if not (x and y and x > 0 and y > 0) then
		return nil
	end
	x, y = math.floor(x + 0.5), math.floor(y + 0.5)
	local pct = (y - x) / x * 100
	pct = pct >= 0 and math.floor(pct + 0.5) or -math.floor(-pct + 0.5)
	return L["listed %d -> %d (%s%d%%)"]:format(x, y, pct > 0 and "+" or "", pct), x, y
end

-- Estimated sales a day (P.SoldSeries: listings gone before they could expire, over the time they were watched):
-- the days touching from..to (oldest first) and over them all a day (nil: too little watched). Empty without it.
function Ch.Sold(item, from, to)
	local P = W.Prices
	if not (P and P.SoldSeries and Num(item)) then
		return {}, nil
	end
	local days, perDay = P.SoldSeries(item, from, to)
	return type(days) == "table" and days or {}, Num(perDay)
end

-- A count a day for the eye: "~25", "~2.5", "~0.3".
function Ch.PerDay(n)
	n = Num(n) or 0
	if n >= 10 then
		return "~" .. math.floor(n + 0.5)
	end
	return "~" .. LT.Decimal(("%.1f"):format(n))
end

-- "sells ~25 a day (est.)": over a range; nil without an estimate.
function Ch.SellsText(perDay)
	return Num(perDay) and L["sells %s a day (est.)"]:format(Ch.PerDay(perDay)) or nil
end

-- Days of supply: how many days the listings now would last at the estimated sales (listed now / sold a day,
-- P.SoldSeries over the last SUPPLY_DAYS). nil without a sales estimate or a scan's count; 0: none listed;
-- math.huge: none sold. Then how many were listed (the last scan's, P.Get) and the sales a day (nil: not known).
Ch.SUPPLY_DAYS = 14
function Ch.Supply(item)
	local P = W.Prices
	item = Num(item)
	if not (item and P and P.Get and P.SoldSeries) then
		return nil
	end
	local get = P.Get(item)
	if type(get) ~= "table" or not Num(get.qty) or not Num(get.seen) then
		return nil
	end
	local listed = get.low ~= nil and math.max(0, math.floor(get.qty + 0.5)) or 0
	local now = time()
	local _, perDay = P.SoldSeries(item, now - Ch.SUPPLY_DAYS * DAY, now)
	perDay = Num(perDay)
	if not perDay then
		return nil, listed, nil
	elseif listed == 0 then
		return 0, 0, perDay
	elseif perDay <= 0 then
		return math.huge, listed, perDay
	end
	return listed / perDay, listed, perDay
end

-- Days of supply in words: "~4 days", "~1 day", "under a day", "none listed", "none sold lately"; nil: not known.
function Ch.SupplyText(days)
	days = Num(days)
	if not days then
		return nil
	elseif days == 0 then
		return L["none listed"]
	elseif days == math.huge then
		return L["none sold lately"]
	end
	local n = math.floor(days + 0.5)
	if n < 1 then
		return L["under a day"]
	elseif n == 1 then
		return L["~1 day"]
	end
	return L["~%d days"]:format(n)
end

-- "~4 days of supply" for a line; nil when not known, none listed or none sold.
function Ch.SupplyLine(days)
	days = Num(days)
	if not days or days == 0 or days == math.huge then
		return nil
	end
	return L["%s of supply"]:format(Ch.SupplyText(days))
end

---------------------------------------------------------------------------
-- Data: P.Series / P.SeriesSpan, else P.History's daily lows
---------------------------------------------------------------------------

-- A point from the data layer, checked: { t, price, qty, open, high, low, close } or nil.
function Ch.Check(p)
	if type(p) ~= "table" or not Num(p.t) or not Num(p.price) or p.price < 0 then
		return nil
	end
	local out = { t = p.t, price = p.price, qty = Num(p.qty) or 0, from = type(p.from) == "string" and p.from or nil }
	if Num(p.open) and Num(p.high) and Num(p.low) and Num(p.close) then
		out.open, out.high, out.low, out.close = p.open, p.high, p.low, p.close
	end
	return out
end

-- The fallback's points: P.History's days, each at its noon (the newest at the last scan when that's the day).
function Ch.HistoryPoints(item)
	local P = W.Prices
	local list = P and P.History and P.History(item) or {}
	local get = P and P.Get and P.Get(item)
	local seen = type(get) == "table" and Num(get.seen)
	local now, out = time(), {}
	for _, d in ipairs(type(list) == "table" and list or {}) do
		if Num(d.day) and Num(d.low) then
			local t = d.day * DAY + DAY / 2
			if seen and math.floor(seen / DAY) == d.day then
				t = seen
			end
			out[#out + 1] = { t = math.min(t, now), price = d.low, qty = Num(d.qty) or 0 }
		end
	end
	return out
end

-- An item's prices between from and to, the oldest first, and their resolution ("scan" | "day").
function Ch.Points(item, from, to)
	local P = W.Prices
	local raw, res
	if P and P.Series then
		raw, res = P.Series(item, from, to)
	else
		raw, res = Ch.HistoryPoints(item), "day"
	end
	local out, sorted = {}, true
	for _, p in ipairs(type(raw) == "table" and raw or {}) do
		p = Ch.Check(p)
		if p and p.t >= from and p.t <= to then
			if out[#out] and p.t < out[#out].t then
				sorted = false
			end
			out[#out + 1] = p
		end
	end
	if not sorted then
		table.sort(out, function(a, b) return a.t < b.t end)
	end
	return out, res == "scan" and "scan" or "day"
end

-- What's known of it at all: the first and the last time (nil: nothing).
function Ch.Span(item)
	local P = W.Prices
	if P and P.SeriesSpan then
		local first, last = P.SeriesSpan(item)
		return Num(first), Num(last)
	end
	local list = Ch.HistoryPoints(item)
	if not list[1] then
		return nil
	end
	return list[1].t, list[#list].t
end

-- The last price before a time (the previous close of 1D): the last scan in the two days before (a short span:
-- every scan's point while they're kept), else the last day's close in the two weeks before; nil: none.
function Ch.PrevClose(item, from)
	local list = Ch.Points(item, from - 2 * DAY, from - 1)
	if not list[1] then
		list = Ch.Points(item, from - 14 * DAY, from - 1)
	end
	local p = list[#list]
	return p and (p.close or p.price) or nil
end

-- Everything known of an item (all its points), kept while the prices stay (P.Revision): its high, low, how many
-- days have a price, the latest point.
function Ch.All(item)
	local P = W.Prices
	local rev = P and P.Revision and P.Revision() or 0
	local c = Ch.allCache
	if c and c.item == item and c.rev == rev and c.minute == math.floor(time() / 60) then
		return c
	end
	c = { item = item, rev = rev, minute = math.floor(time() / 60), days = 0 }
	local first, last = Ch.Span(item)
	c.first, c.last = first, last
	if first then
		local points = Ch.Points(item, first, math.max(last or first, time()))
		local seen = {}
		for _, p in ipairs(points) do
			local hi, lo = p.high or p.price, p.low or p.price
			c.high = math.max(c.high or hi, hi)
			c.low = math.min(c.low or lo, lo)
			local day = math.floor(p.t / DAY) -- (the price engine's days: time() / 86400)
			if not seen[day] then
				seen[day] = true
				c.days = c.days + 1
			end
		end
		c.latest = points[#points]
		c.count = #points
	end
	Ch.allCache = c
	return c
end

-- Where a range starts (Max: the first known, else a day back).
function Ch.RangeStart(range, now, first)
	if range == "1D" then
		return now - DAY
	elseif range == "5D" then
		return now - 5 * DAY
	elseif range == "1M" then
		return now - 30 * DAY
	elseif range == "6M" then
		return now - 182 * DAY
	elseif range == "1Y" then
		return now - 365 * DAY
	elseif range == "YTD" then
		local d = date("*t", now)
		return time({ year = d.year, month = 1, day = 1, hour = 0, min = 0, sec = 0 })
	end
	return math.min(first or (now - DAY), now - 3600)
end

-- Which ranges show something more than a shorter one: 1D and Max when anything is known, the others when there
-- are prices before the start of the range that starts next after theirs.
function Ch.Available(first, now)
	local av = {}
	if not first then
		return av
	end
	local starts = {}
	for _, r in ipairs(Ch.RANGES) do
		if r ~= "Max" then
			starts[r] = Ch.RangeStart(r, now)
		end
	end
	for _, r in ipairs(Ch.RANGES) do
		if r == "1D" or r == "Max" then
			av[r] = true
		else
			local nextStart = now
			for _, st in pairs(starts) do
				if st > starts[r] and st < nextStart then
					nextStart = st
				end
			end
			av[r] = first < nextStart
		end
	end
	return av
end

-- The range to show when the kept one isn't available: 1M, 5D or 1D, else Max.
function Ch.DefaultRange(av, kept)
	if kept and av[kept] then
		return kept
	end
	for _, r in ipairs({ "1M", "5D", "1D" }) do
		if av[r] then
			return r
		end
	end
	return "Max"
end

-- At most n points, in time order: each of n/2 slices of [from, to] keeps its lowest and highest (the first
-- and the last point always), so peaks stay.
function Ch.Downsample(points, from, to, n)
	if #points <= n then
		return points
	end
	local slices = math.max(1, math.floor((n - 2) / 2))
	local span = math.max(1, to - from)
	local out = { points[1] }
	local lo, hi, slice
	local function Flush()
		if lo and hi then
			if lo == hi then
				out[#out + 1] = lo
			elseif lo.t < hi.t then
				out[#out + 1] = lo
				out[#out + 1] = hi
			else
				out[#out + 1] = hi
				out[#out + 1] = lo
			end
		end
		lo, hi = nil, nil
	end
	for i = 2, #points - 1 do
		local p = points[i]
		local s = math.min(slices - 1, math.max(0, math.floor((p.t - from) / span * slices)))
		if s ~= slice then
			Flush()
			slice = s
		end
		if not lo or p.price < lo.price then
			lo = p
		end
		if not hi or p.price > hi.price then
			hi = p
		end
	end
	Flush()
	out[#out + 1] = points[#points]
	return out
end

-- The point nearest a time (its index; points in time order).
function Ch.Nearest(points, t)
	local a, b = 1, #points
	if b == 0 then
		return nil
	end
	while b - a > 1 do
		local m = math.floor((a + b) / 2)
		if points[m].t <= t then
			a = m
		else
			b = m
		end
	end
	return (math.abs(points[b].t - t) < math.abs(points[a].t - t)) and b or a
end

-- A round step for about n grid lines over a span of copper (1, 2 or 5 times a power of ten; 1c at least).
function Ch.NiceStep(span, n)
	local raw = math.max(1, span / math.max(1, n))
	local mag = 10 ^ math.floor(math.log(raw) / math.log(10) + 1e-9)
	for _, m in ipairs({ 1, 2, 5, 10 }) do
		if m * mag >= raw - 1e-9 then
			return math.max(1, m * mag)
		end
	end
	return math.max(1, 10 * mag)
end

-- Time labels for [from, to], at most n: hours for a day or two, days up to ~2.5 months, else months. Each
-- { t, text }; and what they are ("hour", "day", "month": the x axis' title).
function Ch.Ticks(from, to, n)
	local span, out = to - from, {}
	n = math.max(2, n)
	if span <= 2 * DAY then
		local step = 24
		for _, h in ipairs({ 1, 2, 3, 4, 6, 12, 24 }) do
			if span / (h * 3600) <= n then
				step = h
				break
			end
		end
		local d = date("*t", math.floor(from))
		d.min, d.sec = 0, 0
		local t = time(d)
		while t <= to and #out < 60 do
			if t >= from then
				local h = date("*t", t)
				if h.hour % step == 0 then
					out[#out + 1] = { t = t, text = h.hour == 0 and Ch.Short(t) or ("%02d:00"):format(h.hour) }
				end
			end
			t = t + 3600
		end
		return out, "hour"
	elseif span <= 75 * DAY then
		local step = 14
		for _, k in ipairs({ 1, 2, 3, 5, 7, 14 }) do
			if span / (k * DAY) <= n then
				step = k
				break
			end
		end
		local d = date("*t", math.floor(from))
		d.hour, d.min, d.sec = 0, 0, 0
		local i = 0
		while #out < 80 do
			local t = time(d)
			if t > to then
				break
			end
			if t >= from then
				if i % step == 0 then
					local wd = date("*t", t).wday
					out[#out + 1] = { t = t, text = span <= 8 * DAY and Ch.WD[wd] or Ch.Short(t) }
				end
				i = i + 1
			end
			d.day = d.day + 1
		end
		return out, "day"
	end
	local step = 12
	for _, k in ipairs({ 1, 2, 3, 6, 12 }) do
		if span / (k * 30 * DAY) <= n then
			step = k
			break
		end
	end
	local d = date("*t", math.floor(from))
	d.day, d.hour, d.min, d.sec = 1, 0, 0, 0
	while #out < 200 do
		local t = time(d)
		if t > to then
			break
		end
		local m = date("*t", t)
		if t >= from and (m.month - 1) % step == 0 then
			out[#out + 1] = { t = t, text = m.month == 1 and tostring(m.year) or Ch.MON[m.month] }
		end
		d.month = d.month + 1
	end
	return out, "month"
end

---------------------------------------------------------------------------
-- The widget
---------------------------------------------------------------------------

local Wd = {}
Wd.__index = Wd
Ch.Widget = Wd

-- A chart on parent. opts: mini (small: no axes but the range's low and high and its first and last day; a
-- tooltip says "Click: the big chart"), drag (dragging selects and zooms), maxSeg (segments at most),
-- onClick(w), onZoom(w, from, to), onReset(w), onHover(w, point, i) (nil: left), onSpan(w, a, b) (nil: ended).
function Ch.NewWidget(parent, opts)
	opts = opts or {}
	local w = setmetatable({ opts = opts, mini = opts.mini, pools = {}, points = {}, pw = 1, ph = 1 }, Wd)
	local f = CreateFrame("Frame", nil, parent)
	w.frame = f
	local plot = CreateFrame("Button", nil, f)
	plot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	plot.widget = w
	w.plot = plot
	plot.Back = plot:CreateTexture(nil, "BACKGROUND")
	plot.Back:SetAllPoints()
	plot.Back:SetColorTexture(1, 1, 1, 0.035)
	w.Span = plot:CreateTexture(nil, "BORDER")
	w.Span:SetColorTexture(1, 1, 1, 0.1)
	w.Span:Hide()
	w.Cross = plot:CreateTexture(nil, "OVERLAY")
	w.Cross:SetColorTexture(1, 1, 1, 0.45)
	w.Cross:SetWidth(1)
	w.Cross:Hide()
	w.Dot = plot:CreateTexture(nil, "OVERLAY")
	w.Dot:SetSize(7, 7)
	w.Dot:Hide()
	w.Msg = plot:CreateFontString(nil, "OVERLAY", w.mini and "GameFontDisableSmall" or "GameFontDisable")
	w.Msg:SetPoint("TOP", 0, w.mini and -6 or -24)
	w.Msg:SetJustifyH("CENTER")
	w.Msg:Hide()
	w.YTitle = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	w.XTitle = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	w.YTitle:Hide()
	w.XTitle:Hide()
	plot:SetScript("OnEnter", function() w:Enter() end)
	plot:SetScript("OnLeave", function() w:Leave() end)
	plot:SetScript("OnMouseDown", function(_, button) w:MouseDown(button) end)
	plot:SetScript("OnMouseUp", function(_, button) w:MouseUp(button) end)
	plot:SetScript("OnClick", function(_, button) w:Clicked(button) end)
	return w
end

-- Margins around the plot: the big chart's labels on the right and below, its y title above.
function Wd:Margins()
	if self.mini then
		return 0, (self.height >= 48 and self.width >= 140) and 12 or 0
	end
	return 16, 30
end

function Wd:SetSize(width, height)
	self.width, self.height = math.max(20, math.floor(width)), math.max(20, math.floor(height))
	self.frame:SetSize(self.width, self.height)
	self.right = self.right or (self.mini and 0 or 56)
	self:Place()
end

function Wd:Place()
	local top, bottom = self:Margins()
	self.pw = math.max(10, self.width - self.right)
	self.ph = math.max(10, self.height - top - bottom)
	self.plot:ClearAllPoints()
	self.plot:SetPoint("TOPLEFT", 0, -top)
	self.plot:SetSize(self.pw, self.ph)
end

-- Pools: kind -> { list, n }; Begin counts from 0, Get the next (made on demand), Finish hides the rest.
function Wd:Get(kind)
	local pool = self.pools[kind]
	if not pool then
		pool = { list = {}, n = 0 }
		self.pools[kind] = pool
	end
	pool.n = pool.n + 1
	local o = pool.list[pool.n]
	if not o then
		local plot = self.plot
		if kind == "line" or kind == "sline" then
			o = plot:CreateLine(nil, "ARTWORK")
		elseif kind == "ylab" or kind == "xlab" then
			o = self.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		elseif kind == "note" or kind == "corner" or kind == "vtitle" then
			o = plot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		else
			local layer = (kind == "fill" or kind == "band" or kind == "vol" or kind == "grid" or kind == "vgrid") and "BORDER"
				or "ARTWORK"
			o = plot:CreateTexture(nil, layer)
		end
		pool.list[pool.n] = o
	end
	o:Show()
	return o
end

function Wd:Count(kind)
	local pool = self.pools[kind]
	local n = 0
	for _, o in ipairs(pool and pool.list or {}) do
		if o:IsShown() then
			n = n + 1
		end
	end
	return n
end

function Wd:Begin()
	for _, pool in pairs(self.pools) do
		pool.n = 0
	end
end

function Wd:Finish()
	for _, pool in pairs(self.pools) do
		for i = pool.n + 1, #pool.list do
			pool.list[i]:Hide()
		end
	end
end

function Wd:X(t)
	return (t - self.from) / math.max(1, self.to - self.from) * self.pw
end

function Wd:Y(v)
	local base = self.base or 0
	return base + (v - self.lo) / math.max(1e-9, self.hi - self.lo) * (self.ph - base)
end

-- The volume panel at the bottom of the plot (how many were listed): its height self.vh, the price area from
-- self.base up. Only with counts and room enough (a small chart's thin, the big one's about a quarter).
function Wd:VolumeRoom(pts)
	self.vh, self.base = 0, 0
	if not self.extra.volume then
		return
	end
	local most = 0
	for _, p in ipairs(pts) do
		most = math.max(most, p.qty or 0)
	end
	for _, d in ipairs(self.extra.sold or {}) do
		most = math.max(most, d.perDay or 0)
	end
	if most <= 0 or self.ph < (self.mini and 36 or 80) then
		return
	end
	if self.mini then
		self.vh = math.floor(math.max(8, math.min(20, self.ph * 0.24)))
		self.base = self.vh + 3
	else
		self.vh = math.floor(math.max(26, math.min(90, self.ph * 0.24)))
		self.base = self.vh + 10
	end
end

-- What it shows: points (Ch.Points'), the span, the resolution and extra = { prev (the previous close), usual
-- (the usual price), volume (bars of how many were listed), band (each day's low to high), empty (the message
-- without points), note (a message shown with the points) }. Draws at once.
function Wd:SetSeries(points, from, to, res, extra)
	self.points, self.from, self.to, self.res, self.extra = points or {}, from, math.max(to, from + 60), res, extra or {}
	self:Draw()
end

-- The y range: the big chart's round grid steps, a small one's lowest and highest with a margin.
function Wd:Bounds()
	local ex, pts = self.extra, self.points
	local lo, hi = math.huge, -math.huge
	for _, p in ipairs(pts) do
		lo, hi = math.min(lo, p.price), math.max(hi, p.price)
		if ex.band and p.low then
			lo, hi = math.min(lo, p.low), math.max(hi, p.high)
		end
	end
	self.dataLo, self.dataHi = lo, hi
	if Num(ex.prev) then
		lo, hi = math.min(lo, ex.prev), math.max(hi, ex.prev)
	end
	if Num(ex.usual) and ex.usual >= self.dataLo / 2 and ex.usual <= self.dataHi * 2 then
		lo, hi = math.min(lo, ex.usual), math.max(hi, ex.usual)
		self.usualIn = true
	else
		self.usualIn = false
	end
	if self.mini then
		local pad = math.max((hi - lo) * 0.12, hi * 0.03, 1)
		self.lo, self.hi, self.step = math.max(0, lo - pad), hi + pad, nil
		return
	end
	local _, bottom = self:Margins()
	local count = math.max(2, math.min(6, math.floor((self.height - 16 - bottom - (self.base or 0)) / 36)))
	local step = Ch.NiceStep(math.max(hi - lo, hi * 0.02, 1), count)
	self.lo = math.max(0, math.floor(lo / step) * step)
	self.hi = math.ceil(hi / step) * step
	if self.hi - self.lo < step * 0.99 or self.hi <= hi then
		self.hi = self.hi + (self.hi <= hi and step or 0)
	end
	if self.lo >= lo and self.lo > 0 then
		self.lo = math.max(0, self.lo - step)
	end
	self.step = step
end

function Wd:Draw()
	self:Begin()
	self:Unhover()
	local pts, ex = self.points, self.extra
	self.Msg:Hide()
	self.YTitle:Hide()
	self.XTitle:Hide()
	if #pts == 0 then
		self.Msg:SetText(ex.empty or "")
		self.Msg:SetWidth(math.max(40, self.pw - 12))
		self.Msg:Show()
		self:Finish()
		return
	end
	self:VolumeRoom(pts)
	self:Bounds()
	if not self.mini then
		self:Grid()
	end
	self:Place()
	local base = Num(ex.prev) or pts[1].price
	local _, color = Ch.Change(base, pts[#pts].price)
	self.color = color
	local ds = Ch.Downsample(pts, self.from, self.to, math.max(2, math.min(self.opts.maxSeg or Ch.MAX_SEG, math.floor(self.pw / 2) + 1)))
	self.ds = ds
	self.gap = math.max((self.to - self.from) / 8, self.res == "day" and 2.5 * DAY or 18 * 3600)
	if self.vh > 0 then
		self:Volume(ds)
	end
	if ex.band and self.res == "day" and pts[1].low then
		self:Columns(ds, "band")
	else
		self:Columns(ds, "fill")
	end
	self:Lines(ds)
	if #pts <= Ch.DOTS then
		for _, p in ipairs(pts) do
			local dot = self:Get("dot")
			local size = (self.mini and 3 or 4) + (p.from and 1 or 0)
			local c = p.from and Ch.FRIEND or color -- (a friend's scan: a bigger blue dot)
			dot:SetSize(size, size)
			dot:SetColorTexture(c[1], c[2], c[3], 1)
			dot:ClearAllPoints()
			dot:SetPoint("CENTER", self.plot, "BOTTOMLEFT", self:X(p.t), self:Y(p.price))
		end
	end
	if Num(ex.prev) then
		self:Dashes(ex.prev, 0.8, 0.8, 0.8, 0.7)
		if not self.mini then
			self:Note(L["Previous close %s"]:format(Money(ex.prev)), ex.prev, "right")
		end
	end
	if Num(ex.usual) and self.usualIn then
		if self.mini then
			local line = self:Get("level")
			line:SetColorTexture(1, 0.82, 0, 0.7)
			line:ClearAllPoints()
			line:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", 0, self:Y(ex.usual))
			line:SetSize(self.pw, 1)
		else
			self:Dashes(ex.usual, 1, 0.82, 0, 0.8)
			self:Note(L["Usual %s"]:format(Money(ex.usual)), ex.usual, "left")
		end
	end
	if self.mini then
		self:Corners()
	else
		self:TimeAxis()
	end
	if ex.note then
		self.Msg:SetText(ex.note)
		self.Msg:SetWidth(math.max(40, self.pw - 12))
		self.Msg:Show()
	end
	self:Finish()
	if self.over and self.lastX and not self.drag then
		self:HoverAt(self.lastX) -- (drawn again under the cursor: the crosshair stays)
	end
end

-- Grid lines with money labels on the right (the plot's width follows the widest label), and the y title.
function Wd:Grid()
	local step, widest = self.step, 0
	local labels = {}
	local v = self.lo
	while v <= self.hi + step * 0.01 and #labels < 12 do
		local fs = self:Get("ylab")
		fs:SetText(Money(v))
		widest = math.max(widest, fs:GetStringWidth() or 0)
		labels[#labels + 1] = { fs = fs, v = v }
		v = v + step
	end
	self.right = math.max(40, math.floor(widest + 12))
	self:Place()
	local lastY
	for _, l in ipairs(labels) do
		local y = self:Y(l.v)
		local line = self:Get("grid")
		line:SetColorTexture(1, 1, 1, 0.08)
		line:ClearAllPoints()
		line:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", 0, y)
		line:SetSize(self.pw, 1)
		if lastY and y - lastY < 13 then
			l.fs:Hide() -- (cramped: every other label)
		else
			l.fs:ClearAllPoints()
			l.fs:SetPoint("LEFT", self.plot, "BOTTOMRIGHT", 6, y)
			lastY = y
		end
	end
	self.YTitle:SetText(L["Lowest price for one"])
	self.YTitle:ClearAllPoints()
	self.YTitle:SetPoint("BOTTOMRIGHT", self.plot, "TOPRIGHT", self.right, 3)
	self.YTitle:Show()
end

-- Time labels below the plot (faint vertical lines at them), none overlapping, and the x title.
function Wd:TimeAxis()
	local ticks, kind = Ch.Ticks(self.from, self.to, math.max(2, math.min(8, math.floor(self.pw / 70))))
	local lastRight
	for _, tk in ipairs(ticks) do
		local x = self:X(tk.t)
		local fs = self:Get("xlab")
		fs:SetText(tk.text)
		local half = (fs:GetStringWidth() or 0) / 2
		if (lastRight and x - half < lastRight + 6) or x - half < -2 or x + half > self.pw + self.right then
			fs:Hide()
		else
			fs:ClearAllPoints()
			fs:SetPoint("TOP", self.plot, "BOTTOMLEFT", x, -3)
			lastRight = x + half
			local line = self:Get("vgrid")
			line:SetColorTexture(1, 1, 1, 0.05)
			line:ClearAllPoints()
			line:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", x, 0)
			line:SetSize(1, self.ph)
		end
	end
	self.XTitle:SetText(kind == "hour" and L["Time of day"] or kind == "day" and L["Day"] or L["Month"])
	self.XTitle:ClearAllPoints()
	self.XTitle:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 0, 0)
	self.XTitle:Show()
	self.ticks, self.tickKind = ticks, kind
end

-- A small chart's axes: the range's highest and lowest price at the right, its first and last day below.
function Wd:Corners()
	local hi = self:Get("corner")
	hi:SetText(Money(self.dataHi))
	hi:ClearAllPoints()
	hi:SetPoint("TOPRIGHT", self.plot, "TOPRIGHT", -2, -1)
	local lo = self:Get("corner")
	lo:SetText(Money(self.dataLo))
	lo:ClearAllPoints()
	lo:SetPoint("BOTTOMRIGHT", self.plot, "BOTTOMRIGHT", -2, 1)
	if self.dataHi == self.dataLo then
		lo:Hide()
	end
	local _, bottom = self:Margins()
	if bottom > 0 then
		local a = self:Get("xlab")
		a:SetText(Ch.Short(self.from))
		a:ClearAllPoints()
		a:SetPoint("TOPLEFT", self.plot, "BOTTOMLEFT", 0, -1)
		local b = self:Get("xlab")
		b:SetText(math.abs(time() - self.to) < 3600 and L["now"] or Ch.Short(self.to))
		b:ClearAllPoints()
		b:SetPoint("TOPRIGHT", self.plot, "BOTTOMRIGHT", 0, -1)
	end
end

-- The line: a segment between neighbouring points; across a gap (no scans for a long while) faint, as it
-- isn't known what happened there.
function Wd:Lines(ds)
	local c = self.color
	for i = 2, #ds do
		local a, b = ds[i - 1], ds[i]
		local line = self:Get("line")
		line:SetStartPoint("BOTTOMLEFT", self.plot, self:X(a.t), self:Y(a.price))
		line:SetEndPoint("BOTTOMLEFT", self.plot, self:X(b.t), self:Y(b.price))
		line:SetThickness(self.mini and 1.2 or 2)
		local gap = b.t - a.t > self.gap
		line:SetColorTexture(c[1], c[2], c[3], gap and 0.3 or 1)
		line.gap = gap
	end
end

-- The area under the line (kind "fill") or the days' low to high band ("band"): columns a few pixels wide,
-- each at the line's height there (none across a gap).
function Wd:Columns(ds, kind)
	local c = self.color
	local cols = math.max(1, math.min(self.opts.maxSeg or Ch.MAX_SEG, math.floor(self.pw / 3)))
	local cw = self.pw / cols
	local j = 1
	for k = 1, cols do
		local t = self.from + (k - 0.5) / cols * (self.to - self.from)
		while j < #ds - 1 and ds[j + 1].t < t do
			j = j + 1
		end
		local a, b = ds[j], ds[j + 1]
		if b and a.t <= t and t <= b.t and b.t - a.t <= self.gap then
			local f = (t - a.t) / math.max(1, b.t - a.t)
			local top, bottom
			if kind == "band" then
				top = self:Y((a.high or a.price) + ((b.high or b.price) - (a.high or a.price)) * f)
				bottom = self:Y((a.low or a.price) + ((b.low or b.price) - (a.low or a.price)) * f)
			else
				top, bottom = self:Y(a.price + (b.price - a.price) * f), self.base or 0
			end
			if top - bottom >= 0.5 then
				local tex = self:Get(kind)
				tex:ClearAllPoints()
				tex:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", (k - 1) * cw, bottom)
				tex:SetSize(cw + 0.3, top - bottom)
				if kind == "band" then
					tex:SetColorTexture(c[1], c[2], c[3], 0.22)
				else
					tex:SetColorTexture(1, 1, 1, 1)
					tex:SetGradient("VERTICAL", CreateColor(c[1], c[2], c[3], 0.02), CreateColor(c[1], c[2], c[3], 0.26))
				end
			end
		end
	end
end

-- How many were listed: bars in the volume panel at the bottom (self.vh), one per (thinned) point, from none to
-- the most in sight; a bar is brighter where fewer were listed than at the point before (scarcer), and the big
-- chart has the panel's title, its scale (the most) and a line above it.
function Wd:Volume(ds)
	local most = 0
	for _, p in ipairs(ds) do
		most = math.max(most, p.qty or 0)
	end
	local sold = self.extra.sold or {}
	for _, d in ipairs(sold) do
		most = math.max(most, d.perDay or 0)
	end
	if most <= 0 then
		return
	end
	self.mostListed = most
	local width = math.max(1, math.min(8, self.pw / math.max(1, #ds) * 0.7))
	local before
	for _, p in ipairs(ds) do
		local q = p.qty or 0
		if q > 0 then
			local bar = self:Get("vol")
			local fewer = before and q < before
			bar:SetColorTexture(fewer and 0.95 or 0.55, fewer and 0.7 or 0.68, fewer and 0.35 or 0.95, self.mini and 0.6 or 0.7)
			bar:ClearAllPoints()
			bar:SetPoint("BOTTOM", self.plot, "BOTTOMLEFT", self:X(p.t), 0)
			bar:SetSize(width, math.max(1, q / most * self.vh))
			before = q
		end
	end
	self:SoldLine(sold, most)
	if self.mini then
		return
	end
	local line = self:Get("grid")
	line:SetColorTexture(1, 1, 1, 0.12)
	line:ClearAllPoints()
	line:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", 0, self.vh + 4)
	line:SetSize(self.pw, 1)
	local top = self:Get("ylab")
	top:SetText(tostring(math.floor(most + 0.5)))
	top:ClearAllPoints()
	top:SetPoint("LEFT", self.plot, "BOTTOMRIGHT", 6, self.vh)
	local zero = self:Get("ylab")
	zero:SetText("0")
	zero:ClearAllPoints()
	zero:SetPoint("LEFT", self.plot, "BOTTOMRIGHT", 6, 4)
	local title = self:Get("vtitle")
	title:SetText(sold[1] and L["Listed (bars) · sold a day, est. (line)"] or L["Listed"])
	title:SetTextColor(0.6, 0.7, 0.95)
	title:ClearAllPoints()
	title:SetPoint("TOPLEFT", self.plot, "BOTTOMLEFT", 4, self.vh + 2)
end

-- Estimated sales a day as a gold step line in the volume panel, on its scale (most): a step a day (days grouped
-- when there are more than the width holds, their sums over their watched time), joined where days follow on.
function Wd:SoldLine(sold, most)
	if not sold[1] then
		return
	end
	local cap = math.max(4, math.floor(self.pw / 4))
	local size = math.max(1, math.ceil(#sold / cap))
	local steps = {}
	for i = 1, #sold, size do
		local gone, span, a, b = 0, 0, sold[i], sold[math.min(#sold, i + size - 1)]
		for k = i, math.min(#sold, i + size - 1) do
			gone, span = gone + sold[k].gone, span + sold[k].span
		end
		steps[#steps + 1] = { from = a.day * DAY, to = (b.day + 1) * DAY, perDay = span > 0 and gone * DAY / span or 0 }
	end
	local last
	for _, s in ipairs(steps) do
		local x1, x2 = self:X(math.max(self.from, s.from)), self:X(math.min(self.to, s.to))
		local y = math.max(1, s.perDay / most * self.vh)
		if x2 - x1 >= 1 then
			local line = self:Get("sline")
			line:SetColorTexture(1, 0.85, 0.3, 0.95)
			line:SetThickness(self.mini and 1.5 or 2)
			line:SetStartPoint("BOTTOMLEFT", self.plot, x1, y)
			line:SetEndPoint("BOTTOMLEFT", self.plot, x2, y)
			if last and last.to == s.from and math.abs(last.y - y) >= 1 then
				local up = self:Get("sline")
				up:SetColorTexture(1, 0.85, 0.3, 0.95)
				up:SetThickness(self.mini and 1.5 or 2)
				up:SetStartPoint("BOTTOMLEFT", self.plot, x1, last.y)
				up:SetEndPoint("BOTTOMLEFT", self.plot, x1, y)
			end
			last = { to = s.to, y = y }
		end
	end
end

-- A dotted level across the plot (the previous close, the usual price).
function Wd:Dashes(v, r, g, b, a)
	local y = self:Y(v)
	local n = math.max(2, math.min(60, math.floor(self.pw / 8)))
	local gap = self.pw / n
	for k = 0, n - 1 do
		local d = self:Get("dash")
		d:SetColorTexture(r, g, b, a)
		d:ClearAllPoints()
		d:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", k * gap, y)
		d:SetSize(math.min(4, gap / 2), 1)
	end
end

-- A label on a level: what the dotted line is.
function Wd:Note(text, v, side)
	local fs = self:Get("note")
	fs:SetText(text)
	fs:SetTextColor(0.85, 0.85, 0.85)
	fs:ClearAllPoints()
	local y = math.min(self:Y(v) + 2, self.ph - 12)
	if side == "right" then
		fs:SetPoint("BOTTOMRIGHT", self.plot, "BOTTOMLEFT", self.pw - 4, y)
	else
		fs:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", 4, y)
	end
end

---------------------------------------------------------------------------
-- The widget: hover, drag, clicks
---------------------------------------------------------------------------

-- The cursor's x in the plot.
function Wd:CursorX()
	local x = GetCursorPosition()
	local scale = self.plot:GetEffectiveScale() or 1
	return (x or 0) / (scale > 0 and scale or 1) - (self.plot:GetLeft() or 0)
end

function Ch.PlotUpdate(plot)
	local w = plot.widget
	local x = w:CursorX()
	if x ~= w.lastX then
		w.lastX = x
		if w.drag then
			w:DragMove(x)
		else
			w:HoverAt(x)
		end
	end
end

function Wd:Enter()
	self.over, self.lastX = true, nil
	self.plot:SetScript("OnUpdate", Ch.PlotUpdate)
	if #self.points == 0 and self.opts.onClick then
		Ch.Tip(self.plot, L["Price chart"], L["Click: the big chart"])
	end
end

function Wd:Leave()
	self.over = false
	if not self.drag then
		self.plot:SetScript("OnUpdate", nil)
		self:Unhover()
	end
end

function Wd:Index(x)
	local t = self.from + math.max(0, math.min(self.pw, x)) / self.pw * (self.to - self.from)
	return Ch.Nearest(self.points, t)
end

-- The crosshair and the dot on the point nearest x, and its tooltip (only when that point changed).
function Wd:HoverAt(x)
	local i = self:Index(x)
	if not i or i == self.hoverI then
		return
	end
	self.hoverI = i
	self:Mark(i)
	Ch.PointTip(self, i)
	if self.opts.onHover then
		self.opts.onHover(self, self.points[i], i)
	end
end

function Wd:Mark(i)
	local p = self.points[i]
	local x, c = self:X(p.t), self.color or Ch.FLAT
	self.Cross:ClearAllPoints()
	self.Cross:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", x, 0)
	self.Cross:SetSize(1, self.ph)
	self.Cross:Show()
	self.Dot:ClearAllPoints()
	self.Dot:SetPoint("CENTER", self.plot, "BOTTOMLEFT", x, self:Y(p.price))
	self.Dot:SetColorTexture(c[1], c[2], c[3], 1)
	self.Dot:Show()
end

function Wd:Unhover()
	local was = self.hoverI
	self.hoverI = nil
	self.Cross:Hide()
	self.Dot:Hide()
	if not self.drag then
		self.Span:Hide()
	end
	Untip(self.plot)
	if was and self.opts.onHover then
		self.opts.onHover(self, nil)
	end
end

function Wd:MouseDown(button)
	if button == "LeftButton" and self.opts.drag and #self.points >= 2 then
		self:DragStart(self:CursorX())
	end
end

function Wd:MouseUp(button)
	if button == "LeftButton" and self.drag then
		self:DragEnd(self:CursorX())
	end
end

function Wd:DragStart(x)
	self.drag = { a = self:Index(x), b = self:Index(x), x0 = x }
	self.dragged = false
	self.plot:SetScript("OnUpdate", Ch.PlotUpdate)
end

-- While dragging: the span shaded between the two points, its change in the tooltip (and onSpan).
function Wd:DragMove(x)
	local d = self.drag
	if not d then
		return
	end
	d.b = self:Index(x)
	if math.abs(x - d.x0) >= 4 then
		self.dragged = true
	end
	if not self.dragged then
		return
	end
	local xa, xb = self:X(self.points[d.a].t), self:X(self.points[d.b].t)
	self.Span:ClearAllPoints()
	self.Span:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", math.min(xa, xb), 0)
	self.Span:SetSize(math.max(1, math.abs(xb - xa)), self.ph)
	self.Span:Show()
	self.hoverI = d.b
	self:Mark(d.b)
	Ch.SpanTip(self, d.a, d.b)
	if self.opts.onSpan then
		self.opts.onSpan(self, self.points[d.a], self.points[d.b])
	end
end

-- Released: zoomed to the span (two different points, dragged at least 4 px).
function Wd:DragEnd(x)
	self:DragMove(x)
	local d = self.drag
	self.drag = nil
	self.Span:Hide()
	if self.opts.onSpan then
		self.opts.onSpan(self, nil)
	end
	if self.dragged and d and d.a ~= d.b and self.opts.onZoom then
		local ta, tb = self.points[d.a].t, self.points[d.b].t
		self.opts.onZoom(self, math.min(ta, tb), math.max(ta, tb))
	end
	if not self.over then
		self.plot:SetScript("OnUpdate", nil)
		self:Unhover()
	end
end

function Wd:Clicked(button)
	if button == "RightButton" then
		if self.opts.onReset then
			self.opts.onReset(self)
		end
		return
	end
	if self.dragged then
		self.dragged = false
		return
	end
	if self.opts.onClick then
		Untip(self.plot)
		self.opts.onClick(self)
	end
end

-- The tooltip at the crosshair (inside the plot, on the side away from the point).
function Ch.TipAt(w, x)
	GameTooltip:SetOwner(w.plot, "ANCHOR_NONE")
	GameTooltip:ClearAllPoints()
	if x > w.pw / 2 then
		GameTooltip:SetPoint("TOPRIGHT", w.plot, "TOPLEFT", x - 14, -4)
	else
		GameTooltip:SetPoint("TOPLEFT", w.plot, "TOPLEFT", x + 14, -4)
	end
end

function Ch.Pair(left, right, color)
	local c = color or { 1, 1, 1 }
	GameTooltip:AddDoubleLine(left, right, 0.75, 0.75, 0.75, c[1], c[2], c[3])
end

Ch.FRIEND = { 0.4, 0.75, 1 } -- a friend's scan's dot and tooltip line

-- A point's tooltip: when, the price for one, how many were listed, whose scan when a friend's; a day's open, high,
-- low, close and its change from the day before.
function Ch.PointTip(w, i)
	local p, prev = w.points[i], w.points[i - 1]
	Ch.TipAt(w, w:X(p.t))
	GameTooltip:SetText(Ch.When(p.t, w.res), 1, 1, 1)
	Ch.Pair(w.res == "day" and L["Lowest price that day"] or L["Lowest price for one"], Money(p.price))
	Ch.Pair(L["Listed"], (p.qty or 0) > 0 and tostring(math.floor(p.qty)) or L["not known"])
	if p.from then
		local c = Ch.FRIEND
		GameTooltip:AddLine(w.res == "day" and L["last scan that day from %s"]:format(p.from) or L["from %s"]:format(p.from),
			c[1], c[2], c[3])
	end
	local day = math.floor(p.t / DAY)
	for _, d in ipairs(w.extra and w.extra.sold or {}) do
		if d.day == day then
			Ch.Pair(L["Sold that day (est.)"], Ch.PerDay(d.perDay))
		end
	end
	if p.open then
		Ch.Pair(L["Open price"], Money(p.open))
		Ch.Pair(L["High"], Money(p.high))
		Ch.Pair(L["Low"], Money(p.low))
		Ch.Pair(L["Close"], Money(p.close))
	end
	if w.res == "day" and prev then
		local text, color = Ch.Change(prev.close or prev.price, p.close or p.price)
		if text then
			Ch.Pair(L["Change from the day before"], text, color)
		end
	elseif w.res == "day" and not p.open and not w.mini then
		GameTooltip:AddLine(L["Only each day's lowest price is known here."], 0.6, 0.6, 0.6, true)
	end
	if w.mini then
		GameTooltip:AddLine(L["Click: the big chart"], 0.6, 0.6, 0.6)
	elseif w.opts.drag then
		GameTooltip:AddLine(L["Drag: compare two points and zoom in"], 0.6, 0.6, 0.6)
		if w.extra and w.extra.zoomed then
			GameTooltip:AddLine(L["Right-click: back to the range"], 0.6, 0.6, 0.6)
		end
	end
	GameTooltip:Show()
end

-- The tooltip of a dragged span: from when to when, the change, its high and low.
function Ch.SpanTip(w, a, b)
	if a > b then
		a, b = b, a
	end
	local pa, pb = w.points[a], w.points[b]
	local hi, lo = 0, math.huge
	for k = a, b do
		local p = w.points[k]
		hi, lo = math.max(hi, p.high or p.price), math.min(lo, p.low or p.price)
	end
	Ch.TipAt(w, w:X(w.points[w.drag and w.drag.b or b].t))
	GameTooltip:SetText(L["%s to %s"]:format(Ch.When(pa.t, w.res), Ch.When(pb.t, w.res)), 1, 1, 1)
	local text, color = Ch.Change(pa.price, pb.price)
	Ch.Pair(L["Change"], text or "-", color)
	Ch.Pair(L["High"], Money(hi))
	Ch.Pair(L["Low"], Money(lo))
	GameTooltip:AddLine(L["Release: zoom in to it"], 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Windows: the frame both windows share
---------------------------------------------------------------------------

-- LefthyToolsWhyPoorDB.ui[key], a table (an empty one before the saved variables are there).
function Ch.UI(key)
	local db = W.DB and W.DB()
	if type(db) ~= "table" then
		Ch.scratch = Ch.scratch or {}
		Ch.scratch[key] = Ch.scratch[key] or {}
		return Ch.scratch[key]
	end
	db.ui = type(db.ui) == "table" and db.ui or {}
	db.ui[key] = type(db.ui[key]) == "table" and db.ui[key] or {}
	return db.ui[key]
end

function Ch.SavePlace(f)
	local s = Ch.UI(f.uiKey)
	local left, top = f:GetLeft(), f:GetTop()
	if Num(left) and Num(top) then
		s.left, s.top = math.floor(left + 0.5), math.floor(top + 0.5)
	end
	local width, height = f:GetSize()
	if Num(width) and Num(height) and width > 0 and height > 0 then
		s.w, s.h = math.floor(width + 0.5), math.floor(height + 0.5)
	end
end

-- A movable, resizable window of ours (Lodestar's look), closed by Escape; its place and size kept in ui[key].
-- onSize() runs on the next frame after its size changed (at most every 0.1 s while it's being resized).
function Ch.NewWindow(name, key, width, height, minW, minH)
	local f = CreateFrame("Frame", name, UIParent)
	f.uiKey = key
	local s = Ch.UI(key)
	local sw = Num(GetScreenWidth and GetScreenWidth()) or 1600
	local sh = Num(GetScreenHeight and GetScreenHeight()) or 1000
	local w = math.max(minW, math.min(Num(s.w) or width, sw - 20))
	local h = math.max(minH, math.min(Num(s.h) or height, sh - 20))
	f:SetSize(w, h)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetResizable(true)
	if f.SetResizeBounds then
		f:SetResizeBounds(minW, minH, math.max(minW, sw), math.max(minH, sh))
	end
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		self:SetUserPlaced(false)
		Ch.SavePlace(self)
	end)
	f:SetScript("OnSizeChanged", function(self)
		self.resized = true
	end)
	f:Hide()
	LT.Window.Dress(f)
	table.insert(UISpecialFrames, name) -- (Escape closes it)
	LT.Window.Register(name)
	f:HookScript("OnShow", function() LT.Trail("window " .. name) end)
	f:HookScript("OnHide", function(self)
		LT.Trail("window closed " .. name)
		GameTooltip:Hide()
		self:UnregisterAllEvents()
	end)
	if Num(s.left) and Num(s.top) then
		f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", s.left, s.top)
	else
		f:SetPoint("CENTER")
	end
	-- The corner grip.
	local grip = CreateFrame("Button", nil, f)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function()
		f.sizing = true
		f:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		f:SetUserPlaced(false)
		f.sizing = false
		f.resized = true
		Ch.SavePlace(f)
	end)
	Ch.SetTip(grip, function() return L["Resize"], L["Drag: resize the window"] end)
	f.Grip = grip
	f.Close = CreateFrame("Button", nil, f, "UIPanelCloseButtonNoScripts")
	f.Close:SetSize(24, 24)
	f.Close:SetPoint("TOPRIGHT", -2, -1)
	f.Close:SetScript("OnClick", function() f:Hide() end)
	return f
end

-- A ticker on a window: while shown, onTick(elapsed) each frame; hidden, nothing runs (a child's OnUpdate).
function Ch.Ticker(f, onTick)
	local ticker = CreateFrame("Frame", nil, f)
	ticker:SetScript("OnUpdate", function(_, elapsed)
		LT.Guard("WhyPoor.chart", onTick, elapsed)
	end)
	return ticker
end

-- A flat button (the picked one underlined: Ch.PaintFlat), as wide as its text; onClick(self).
function Ch.FlatButton(parent, text, onClick)
	local b = CreateFrame("Button", nil, parent)
	b.Back = b:CreateTexture(nil, "BACKGROUND")
	b.Back:SetAllPoints()
	b.Line = b:CreateTexture(nil, "ARTWORK")
	b.Line:SetPoint("BOTTOMLEFT")
	b.Line:SetPoint("BOTTOMRIGHT")
	b.Line:SetHeight(2)
	b.Line:SetColorTexture(1, 0.82, 0, 1)
	b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.Text:SetPoint("CENTER", 0, 1)
	b.Text:SetText(text)
	b:SetSize(math.floor((b.Text:GetStringWidth() or 40) + 16), 20)
	b:SetHighlightTexture(HIGHLIGHT, "ADD")
	b:SetScript("OnClick", onClick)
	return b
end

function Ch.PaintFlat(b, on)
	b.on = on and true or false
	b.Line:SetShown(b.on)
	b.Back:SetColorTexture(1, 0.82, 0, on and 0.16 or 0.04)
	b.Text:SetTextColor(on and 1 or 0.8, on and 0.82 or 0.8, on and 0 or 0.8)
end

-- The range buttons (flat, the picked one underlined); onPick(range). Returns the row's buttons by range.
function Ch.RangeButtons(parent, onPick)
	local buttons = {}
	for _, r in ipairs(Ch.RANGES) do
		local b = CreateFrame("Button", nil, parent)
		b:SetSize(38, 20)
		b.range = r
		b.Back = b:CreateTexture(nil, "BACKGROUND")
		b.Back:SetAllPoints()
		b.Line = b:CreateTexture(nil, "ARTWORK")
		b.Line:SetPoint("BOTTOMLEFT")
		b.Line:SetPoint("BOTTOMRIGHT")
		b.Line:SetHeight(2)
		b.Line:SetColorTexture(1, 0.82, 0, 1)
		b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		b.Text:SetPoint("CENTER", 0, 1)
		b.Text:SetText(Ch.LABELS[r])
		b:SetHighlightTexture(HIGHLIGHT, "ADD")
		b:SetScript("OnClick", function(self)
			if not self.off then
				onPick(self.range)
			end
		end)
		Ch.SetTip(b, function(self)
			return Ch.TIPS[self.range], self.off and (ORANGE .. L["No prices that far back yet"] .. "|r") or nil
		end)
		buttons[r] = b
		buttons[#buttons + 1] = b
	end
	return buttons
end

-- Picked, available (greyed when not).
function Ch.PaintRanges(buttons, picked, av)
	for _, b in ipairs(buttons) do
		local on, off = b.range == picked, av and not av[b.range]
		b.off = off and true or false
		b.Line:SetShown(on)
		b.Back:SetColorTexture(1, 0.82, 0, on and 0.16 or 0.04)
		if off then
			b.Text:SetTextColor(0.4, 0.4, 0.4)
		else
			b.Text:SetTextColor(on and 1 or 0.8, on and 0.82 or 0.8, on and 0 or 0.8)
		end
	end
end

---------------------------------------------------------------------------
-- The big chart
---------------------------------------------------------------------------

Ch.NAME = "LefthyToolsWhyPoorChart"
Ch.C = { W = 760, H = 520, MIN_W = 540, MIN_H = 400, PAD = 10, CHART_Y = 118, CELL_H = 18, ROWS = 3, COLS = 3 }
Ch.state = { draws = 0, due = false }

-- The numbers under the chart: their label, what they mean (the tooltip).
Ch.STATS = {
	{ key = "open", label = L["Open price"], tip = L["The first price in the range shown."] },
	{ key = "high", label = L["High"], tip = L["The highest price in the range shown (for daily points each day's highest scan)."] },
	{ key = "low", label = L["Low"], tip = L["The lowest price in the range shown (for daily points each day's lowest scan)."] },
	{ key = "listed", label = L["Listed now"], tip = L["How many were listed at the last scan that covered it (your own auctions count too)."] },
	{ key = "usual", label = L["Usual"], tip = L["The usual price: a time-weighted median of the daily lowest prices of the last 14 days. WhyPoor? judges deals and ideas by it."] },
	{ key = "steady", label = L["Steady?"], tip = L["Steady or jumps around: whether the daily lowest prices of the last 14 days stray far from their median. Ideas don't rank on prices that jump around."] },
	{ key = "known", label = L["Known high / low"], tip = L["The highest and the lowest price of everything known about it on your auction house."] },
	{ key = "days", label = L["Days of data"], tip = L["On how many days a scan saw it, and since when. Watched items keep their prices longest."] },
	{ key = "supply", label = L["Days of supply"], tip = L["How many days the listings on the auction house would last at the estimated sales (listed now divided by sold a day over the last 14 days). Under 2: scarce; over 14: flooded. Not known without a sales estimate: that needs two of your whole scans in one session."] },
}

-- The toggles right of the range buttons: what they add to the chart (kept in ui.chart).
Ch.TOGGLES = {
	{ key = "usual", label = L["Usual"], default = true, tip = L["The usual price as a dotted gold line."] },
	{ key = "volume", label = L["Listed"], default = true, tip = L["How many were listed at each point: the bars in the panel under the price (orange where fewer than before: scarcer). A price going up while fewer are listed is scarcity, not demand."] },
	{ key = "sold", label = L["Sold a day"], default = true, tip = L["Estimated sales a day, as a gold line in the panel under the price: listings that went before they could expire, over the time they were watched between two of your whole scans. Cancelled ones count too, so it's an estimate."] },
	{ key = "band", label = L["High/low"], default = false, tip = L["Daily points: a band from each day's lowest to its highest scan, instead of the area under the line."] },
}

function Ch.Toggle(key)
	local ui = Ch.UI("chart")
	for _, t in ipairs(Ch.TOGGLES) do
		if t.key == key then
			if ui[key] == nil then
				return t.default
			end
			return ui[key] == true
		end
	end
end

function Ch.Build()
	local C = Ch.C
	local f = Ch.NewWindow(Ch.NAME, "chart", C.W, C.H, C.MIN_W, C.MIN_H)
	Ch.frame = f
	-- The item: its icon and name (its tooltip on hover).
	local item = CreateFrame("Button", nil, f)
	item:SetPoint("TOPLEFT", C.PAD, -8)
	item:SetSize(300, 26)
	item.Icon = item:CreateTexture(nil, "ARTWORK")
	item.Icon:SetSize(24, 24)
	item.Icon:SetPoint("LEFT")
	item.Name = item:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	item.Name:SetPoint("LEFT", 30, 0)
	item.Name:SetJustifyH("LEFT")
	item.Name:SetWordWrap(false)
	item:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		if not pcall(GameTooltip.SetHyperlink, GameTooltip, ("item:%d"):format(Ch.state.item or 0)) then
			GameTooltip:SetText(W.Window.ItemName(Ch.state.item or 0), 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	item:SetScript("OnLeave", Untip)
	item:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	item:SetScript("OnClick", function(self, button)
		local Ia = W.ItemActions
		if Ia and Ch.state.item then
			Ia.Click(self, Ch.state.item, button)
		end
	end)
	f.Item = item
	f.Watch = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.Watch:SetSize(100, 20)
	f.Watch:SetPoint("TOPRIGHT", -32, -8)
	f.Watch:SetScript("OnClick", Ch.ToggleWatch)
	Ch.SetTip(f.Watch, function()
		local St = W.Stocks
		if St and St.Watched and St.Watched(Ch.state.item) then
			return L["Watching"], L["On your watch list (the Stocks tab): its prices are kept longest, every scan for about a month and a price a day for years."], L["Click: stop watching it"]
		end
		return L["+ Watch"], L["Adds it to your watch list (the Stocks tab): its prices are kept longest, every scan for about a month and a price a day for years."]
	end)
	-- The price, the change, the line under them.
	f.Price = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	f.Price:SetPoint("TOPLEFT", C.PAD, -40)
	f.Price:SetTextColor(1, 1, 1)
	local box = CreateFrame("Button", nil, f)
	box:SetSize(120, 22)
	box:SetPoint("LEFT", f.Price, "RIGHT", 12, 0)
	box.Back = box:CreateTexture(nil, "BACKGROUND")
	box.Back:SetAllPoints()
	box.Arrow = box:CreateTexture(nil, "ARTWORK")
	box.Arrow:SetSize(12, 12)
	box.Arrow:SetPoint("LEFT", 6, 0)
	box.Text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	box.Text:SetPoint("LEFT", 22, 0)
	Ch.SetTip(box, function()
		local v = Ch.view or {}
		return L["Change"], v.changeTip
	end)
	f.Change = box
	f.Over = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.Over:SetPoint("LEFT", box, "RIGHT", 8, 0)
	f.Info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.Info:SetPoint("TOPLEFT", C.PAD, -72)
	f.Info:SetJustifyH("LEFT")
	f.Info:SetWordWrap(false)
	-- The ranges, Reset, the toggles.
	f.Ranges = Ch.RangeButtons(f, Ch.PickRange)
	local x = C.PAD
	for _, b in ipairs(f.Ranges) do
		b:SetPoint("TOPLEFT", x, -92)
		x = x + b:GetWidth() + 3
	end
	f.Reset = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.Reset:SetSize(110, 20)
	f.Reset:SetPoint("TOPLEFT", x + 8, -92)
	f.Reset:SetText(L["Reset zoom"])
	f.Reset:SetScript("OnClick", Ch.ResetZoom)
	Ch.SetTip(f.Reset, function() return L["Reset zoom"], L["Back to the range picked (right-click on the chart does it too)."] end)
	f.Reset:Hide()
	f.Toggles = {}
	local right = -C.PAD
	for k = #Ch.TOGGLES, 1, -1 do
		local t = Ch.TOGGLES[k]
		local b = CreateFrame("Button", nil, f)
		b.key = t.key
		b.Box = b:CreateTexture(nil, "ARTWORK")
		b.Box:SetSize(10, 10)
		b.Box:SetPoint("LEFT", 2, 0)
		b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.Text:SetPoint("LEFT", 16, 0)
		b.Text:SetText(t.label)
		b:SetSize(math.floor((b.Text:GetStringWidth() or 30) + 22), 20)
		b:SetPoint("TOPRIGHT", right, -92)
		right = right - b:GetWidth() - 6
		b:SetHighlightTexture(HIGHLIGHT, "ADD")
		b:SetScript("OnClick", function(self)
			if self.off then
				return
			end
			Ch.UI("chart")[self.key] = not Ch.Toggle(self.key)
			Ch.Draw()
		end)
		Ch.SetTip(b, function(self)
			return t.label, t.tip, self.off and (ORANGE .. L["Only for daily points (the longer ranges)."] .. "|r") or nil
		end)
		f.Toggles[t.key] = b
	end
	-- The chart.
	Ch.widget = Ch.NewWidget(f, { drag = true, onZoom = Ch.Zoom, onReset = Ch.ResetZoom, onHover = Ch.Hovered, onSpan = Ch.Spanned })
	Ch.widget.frame:SetPoint("TOPLEFT", C.PAD, -C.CHART_Y)
	-- The numbers.
	f.Cells = {}
	for k, s in ipairs(Ch.STATS) do
		local cell = CreateFrame("Button", nil, f)
		cell:SetHeight(C.CELL_H)
		cell.Label = cell:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		cell.Label:SetPoint("LEFT", 2, 0)
		cell.Label:SetText(s.label)
		cell.Value = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		cell.Value:SetPoint("RIGHT", -2, 0)
		cell.Value:SetJustifyH("RIGHT")
		cell.Line = cell:CreateTexture(nil, "BACKGROUND")
		cell.Line:SetPoint("BOTTOMLEFT")
		cell.Line:SetPoint("BOTTOMRIGHT")
		cell.Line:SetHeight(1)
		cell.Line:SetColorTexture(1, 1, 1, 0.08)
		cell:SetHighlightTexture(HIGHLIGHT, "ADD")
		Ch.SetTip(cell, function() return s.label, s.tip, cell.from end)
		f.Cells[s.key] = cell
		f.Cells[k] = cell
	end
	Ch.Ticker(f, Ch.Tick)
	f:SetScript("OnEvent", function(_, event)
		if event == "GET_ITEM_INFO_RECEIVED" then
			Ch.state.due = true
		end
	end)
	f:HookScript("OnShow", function(self)
		self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	end)
end

-- What a drawn chart rests on besides its own choices: the prices' revision and the minute (the scan's age).
function Ch.Key()
	local P = W.Prices
	return (P and P.Revision and P.Revision() or 0) .. ":" .. math.floor(time() / 60)
end

-- While shown: the size laid out (0.1 s apart while resizing), the prices' revision and the scan's age looked
-- at every second, a draw on the next frame when anything changed.
function Ch.Tick(elapsed)
	local s, f = Ch.state, Ch.frame
	s.wait = (s.wait or 0) - elapsed
	s.sizeWait = (s.sizeWait or 0) - elapsed
	if f.resized and (not f.sizing or s.sizeWait <= 0) then
		f.resized, s.sizeWait = false, 0.1
		Ch.Layout()
		s.due = true
	end
	if s.wait <= 0 then
		s.wait = 1
		local key = Ch.Key()
		if key ~= s.key then
			s.key = key
			s.due = true
		end
	end
	if s.due then
		Ch.Draw()
	end
end

-- Sizes from the window's: the chart's, the numbers' cells.
function Ch.Layout()
	local f, C = Ch.frame, Ch.C
	local width, height = f:GetSize()
	local inner = width - 2 * C.PAD
	local gridH = C.ROWS * (C.CELL_H + 2) + 4
	Ch.widget:SetSize(inner, height - C.CHART_Y - gridH - C.PAD - 8)
	local cw = (inner - (C.COLS - 1) * 14) / C.COLS
	for k, cell in ipairs(f.Cells) do
		local col, row = (k - 1) % C.COLS, math.floor((k - 1) / C.COLS)
		cell:ClearAllPoints()
		cell:SetPoint("TOPLEFT", f, "BOTTOMLEFT", C.PAD + col * (cw + 14), C.PAD + 6 + gridH - row * (C.CELL_H + 2))
		cell:SetWidth(cw)
	end
	f.Info:SetWidth(inner)
	f.Item:SetWidth(math.max(120, width - 2 * C.PAD - 150))
	f.Item.Name:SetWidth(math.max(80, width - 2 * C.PAD - 186))
end

-- What the chart shows now: the span and its points.
function Ch.Data()
	local s = Ch.state
	local now = time()
	local all = Ch.All(s.item)
	local av = Ch.Available(all.first, now)
	if not s.zoom then
		s.range = Ch.DefaultRange(av, s.range or Ch.UI("chart").range)
	end
	local from, to = Ch.RangeStart(s.range, now, all.first), now
	if s.zoom then
		from, to = s.zoom[1], s.zoom[2]
	end
	local points, res = Ch.Points(s.item, from, to)
	local prev = (not s.zoom and s.range == "1D") and Ch.PrevClose(s.item, from) or nil
	return points, res, from, to, prev, all, av
end

function Ch.Draw()
	local s, f = Ch.state, Ch.frame
	if not (f and s.item) then
		return
	end
	s.draws, s.due = s.draws + 1, false
	local P = W.Prices
	local points, res, from, to, prev, all, av = Ch.Data()
	local get = P and P.Get and P.Get(s.item)
	get = type(get) == "table" and get or {}
	local band = Ch.Toggle("band") and res == "day"
	local empty = not all.first and L["No prices yet: open the auction house."] or L["No prices in this range: pick a longer one."]
	local note
	if (all.count or 0) == 1 then
		local p = all.latest
		note = L["One scan so far: %s on %s. Each visit to the auction house adds a point."]:format(Money(p.price), Ch.When(p.t, "scan"))
	elseif #points == 1 then
		note = L["Only one price in this range: a longer one shows more."]
	end
	local sold, perDay = {}, nil
	if Ch.Toggle("sold") then
		sold, perDay = Ch.Sold(s.item, from, to)
	end
	Ch.widget:SetSeries(points, from, to, res, { prev = prev, usual = Ch.Toggle("usual") and Num(get.value) or nil,
		volume = Ch.Toggle("volume") or sold[1] ~= nil, sold = sold, band = band, empty = empty, note = note,
		zoomed = s.zoom ~= nil })
	-- The header.
	local Wn = W.Window
	f.Item.Icon:SetTexture(Wn.ItemIcon(s.item))
	f.Item.Name:SetText(Wn.ItemName(s.item))
	local St = W.Stocks
	f.Watch:SetShown(St ~= nil and St.Watched ~= nil)
	f.Watch:SetText((St and St.Watched and St.Watched(s.item)) and L["Watching"] or L["+ Watch"])
	local current = Ch.Current(points, get, all, s.zoom ~= nil)
	local base = Ch.Base(points, prev)
	local span = s.zoom and L["%s to %s"]:format(Ch.When(from, res), Ch.When(to, res)) or Ch.OVER[s.range]
	local info = { s.zoom and span or Ch.TIPS[s.range] }
	if Num(get.seen) then
		info[#info + 1] = L["last scan %s"]:format(LT.Ago(get.seen)) .. (get.low == nil and (" (" .. L["none listed"] .. ")") or "")
	end
	if get.friend then
		info[#info + 1] = L["from %s"]:format(tostring(get.friend))
	end
	local friends = 0
	for _, p in ipairs(points) do
		friends = friends + (p.from and 1 or 0)
	end
	if friends > 0 then
		info[#info + 1] = res == "day" and L["days last scanned by friends: %d"]:format(friends) or L["friends' scans: %d"]:format(friends)
	end
	local listed = Ch.ListedChange(points)
	local sells = Ch.SellsText(perDay)
	local supply, supplyListed, supplyPerDay = Ch.Supply(s.item)
	local supplyLine = Ch.SupplyLine(supply)
	if supplyLine then
		table.insert(info, 2, supplyLine)
	end
	if sells then
		table.insert(info, 2, sells)
	end
	if listed then
		table.insert(info, 2, listed)
	end
	Ch.view = { current = current, base = base, span = span, info = table.concat(info, SEP), res = res, first = points[1],
		listed = listed, supply = supply, supplyListed = supplyListed, supplyPerDay = supplyPerDay }
	Ch.Header()
	if Ch.widget.hoverI then
		Ch.Header(Ch.widget.points[Ch.widget.hoverI])
	end
	s.key = Ch.Key()
	-- The ranges, Reset, the toggles.
	Ch.PaintRanges(f.Ranges, not s.zoom and s.range or nil, av)
	f.Reset:SetShown(s.zoom ~= nil)
	for _, t in ipairs(Ch.TOGGLES) do
		local b = f.Toggles[t.key]
		local on = Ch.Toggle(t.key)
		b.off = t.key == "band" and res ~= "day"
		b.Box:SetColorTexture(1, 0.82, 0, (b.off and 0.15) or (on and 0.9) or 0.2)
		b.Text:SetTextColor(b.off and 0.45 or 1, b.off and 0.45 or 1, b.off and 0.45 or 1)
	end
	Ch.Stats(points, get, all)
end

-- The price now: the last scan's lowest (P.Get) unless zoomed or none was listed, else the last point's (a day's
-- close); nil: none.
function Ch.Current(points, get, all, zoomed)
	local last = points[#points]
	if not zoomed and type(get) == "table" and Num(get.low) then
		return get.low
	end
	last = last or (not zoomed and all and all.latest)
	return last and (last.close or last.price) or nil
end

-- What a range's change starts from: the previous close (1D), else its first point (a day's open).
function Ch.Base(points, prev)
	local first = points[1]
	return Num(prev) or (first and (first.open or first.price)) or nil
end

-- The header: the price (the hovered point's while hovering), the change box, the line under it.
function Ch.Header(point, a, b)
	local f, v = Ch.frame, Ch.view or {}
	local shown = (point and point.price) or (b and b.price) or v.current
	f.Price:SetText(shown and Money(shown) or "-")
	local from, to = v.base, v.current
	if a and b then
		from, to = a.price, b.price
	elseif point then
		to = point.price
	end
	local text, color, sign = Ch.Change(from, to)
	local box = f.Change
	box:SetShown(text ~= nil)
	if text then
		box.Text:SetText(text)
		box.Text:SetTextColor(color[1], color[2], color[3])
		box.Back:SetColorTexture(color[1] * 0.5, color[2] * 0.5, color[3] * 0.5, 0.35)
		box.Arrow:SetShown(sign ~= 0)
		box.Arrow:SetTexture(sign > 0 and "Interface\\Buttons\\Arrow-Up-Up" or "Interface\\Buttons\\Arrow-Down-Up")
		box:SetWidth(math.floor((box.Text:GetStringWidth() or 60) + 30))
	end
	if a and b then
		f.Over:SetText(L["%s to %s"]:format(Ch.When(a.t, v.res), Ch.When(b.t, v.res)))
		v.changeTip = L["From %s to %s: %s"]:format(Money(a.price), Money(b.price), text or "-")
	elseif point then
		f.Over:SetText(L["since %s"]:format(Ch.When(v.first and v.first.t or point.t, v.res)))
		v.changeTip = nil
	else
		f.Over:SetText(v.span or "")
		v.changeTip = text and (L["From %s to %s: %s"]:format(Money(from), Money(to), text) .. "\n" .. (v.span or "")) or nil
	end
	if a and b then
		local listed = Ch.ListedChange(nil, a, b)
		f.Info:SetText(listed or v.info or "")
	elseif point then
		local parts = { Ch.When(point.t, v.res), Money(point.price) }
		if (point.qty or 0) > 0 then
			parts[#parts + 1] = L["%d listed"]:format(math.floor(point.qty))
		end
		if point.open then
			parts[#parts + 1] = L["open %s, high %s, low %s, close %s"]:format(Money(point.open), Money(point.high), Money(point.low),
				Money(point.close))
		end
		f.Info:SetText(table.concat(parts, SEP))
	else
		f.Info:SetText(v.info or "")
	end
end

function Ch.Hovered(_, point)
	if not Ch.state.dragging then
		Ch.Header(point)
	end
end

function Ch.Spanned(_, a, b)
	Ch.state.dragging = a ~= nil
	if a then
		Ch.Header(nil, a, b)
	else
		Ch.Header()
	end
end

-- The numbers under the chart.
function Ch.Stats(points, get, all)
	local cells = Ch.frame.Cells
	local function Set(key, text, from)
		cells[key].Value:SetText(text or "-")
		cells[key].from = from and (GREY .. from .. "|r") or nil
	end
	local hi, lo
	for _, p in ipairs(points) do
		hi = math.max(hi or 0, p.high or p.price)
		lo = math.min(lo or math.huge, p.low or p.price)
	end
	local first = points[1]
	Set("open", first and Money(first.open or first.price), first and L["At %s"]:format(Ch.When(first.t, Ch.view.res)))
	Set("high", hi and Money(hi))
	Set("low", lo and Money(lo))
	local listed = Num(get.qty) and (get.low and tostring(math.floor(get.qty)) or L["none listed"])
	local how = Num(get.seen) and L["Last scan %s"]:format(LT.Ago(get.seen))
	if Ch.view.listed then
		how = (how and (how .. "\n") or "") .. L["In this range: %s"]:format(Ch.view.listed)
	end
	Set("listed", listed, how)
	Set("usual", Num(get.value) and Money(get.value), Num(get.days) and L["From %d days of prices"]:format(math.floor(get.days)))
	Set("steady", Num(get.value) and (get.unstable and (ORANGE .. L["jumps around"] .. "|r") or L["steady"]))
	Set("known", all.high and (Money(all.high) .. " / " .. Money(all.low)))
	Set("days", all.first and tostring(all.days) or nil, all.first and L["Since %s"]:format(Ch.When(all.first, "day")))
	local v = Ch.view
	Set("supply", Ch.SupplyText(v.supply) or L["not known"], Num(v.supplyPerDay)
		and L["%d listed now, sells %s a day (est.)"]:format(v.supplyListed or 0, Ch.PerDay(v.supplyPerDay)) or nil)
end

function Ch.PickRange(range)
	local s = Ch.state
	s.range, s.zoom = range, nil
	Ch.UI("chart").range = range
	Ch.Draw()
end

function Ch.Zoom(_, from, to)
	if to - from < 60 then
		return
	end
	Ch.state.zoom = { from, to }
	Ch.Draw()
end

function Ch.ResetZoom()
	if Ch.state.zoom then
		Ch.state.zoom = nil
		Ch.Draw()
	end
end

function Ch.ToggleWatch()
	local St, item = W.Stocks, Ch.state.item
	if not (St and item) then
		return
	end
	if St.Watched(item) then
		St.Unwatch(item)
	else
		St.Watch(item)
	end
	Ch.allCache = nil
	Ch.Draw()
	if Ch.dash and Ch.dash.frame then
		Ch.dash.due = true
	end
end

-- An item from text: a link, "#1234" or a number; nil otherwise.
function Ch.ParseItem(text)
	text = type(text) == "string" and text or ""
	local id = text:match("item:(%d+)") or text:match("^%s*#(%d+)%s*$") or text:match("^%s*(%d+)%s*$")
	id = tonumber(id)
	return id and id > 0 and id or nil
end

function Ch.Enabled()
	local m = W.module
	if m and not m.enabled then
		LT.Print("WhyPoor? is switched off (/lefthy enable whypoor).")
		return false
	end
	return true
end

-- Opens the big chart of an item (its kept range, not zoomed). False: switched off or not an item.
function Ch.Open(item)
	item = Num(item)
	if not item or item <= 0 or not Ch.Enabled() then
		return false
	end
	if not Ch.frame then
		Ch.Build()
	end
	local s = Ch.state
	s.item, s.zoom, s.range, s.dragging = item, nil, nil, false
	Ch.allCache = nil
	Ch.frame:Show()
	if Ch.frame.Raise then
		Ch.frame:Raise()
	end
	Ch.Layout()
	Ch.frame.resized = false
	Ch.Draw()
	return true
end

function Ch.Shown()
	return Ch.frame ~= nil and Ch.frame:IsShown()
end

---------------------------------------------------------------------------
-- The dashboard
---------------------------------------------------------------------------

local Ds = { due = false, draws = 0, tiles = {} }
Ch.dash = Ds
Ds.NAME = "LefthyToolsWhyPoorDashboard"
Ds.C = { W = 780, H = 520, MIN_W = 560, MIN_H = 300, PAD = 10, TOP = 34, EDIT = 30, TILE_W = 220, TILE_H = 132, GAP = 8,
	COLS = 4, BAR = 22, BUDGET_MS = 2, PER_FRAME = 2000, PER_TICK = 8 }

function Ds.UI()
	local ui = Ch.UI("dashboard")
	ui.items = type(ui.items) == "table" and ui.items or {}
	return ui
end

-- The dashboard's items (checked: numbers, each once).
function Ds.Items()
	local list, out, seen = Ds.UI().items, {}, {}
	for _, id in ipairs(list) do
		if Num(id) and not seen[id] then
			seen[id] = true
			out[#out + 1] = id
		end
	end
	if #out ~= #list then
		Ds.UI().items = out
	end
	return out
end

function Ds.Range()
	local r = Ds.UI().range
	return Ch.LABELS[r] and r or "1M"
end

-- The page shown: "charts" (My charts, the tiles) or "highlights" (Highlights.lua); kept in ui.dashboard.page.
Ds.PAGES = { { key = "charts", label = L["My charts"] }, { key = "highlights", label = L["Highlights"] } }
function Ds.Page()
	return (Ds.UI().page == "highlights" and W.Highlights) and "highlights" or "charts"
end

function Ds.SetPage(page)
	Ds.UI().page = page == "highlights" and "highlights" or "charts"
	Ds.Draw()
end

function Ds.Build()
	local C = Ds.C
	local f = Ch.NewWindow(Ds.NAME, "dashboard", C.W, C.H, C.MIN_W, C.MIN_H)
	Ds.frame = f
	-- The pages' tabs, then the range buttons (My charts) or the highlights' spans on the title row.
	f.Tabs = {}
	local x = C.PAD
	for _, page in ipairs(Ds.PAGES) do
		local b = Ch.FlatButton(f, page.label, function() Ds.SetPage(page.key) end)
		b.page = page.key
		b:SetPoint("TOPLEFT", x, -5)
		x = x + b:GetWidth() + 3
		Ch.SetTip(b, function()
			if page.key == "highlights" then
				return L["Highlights"], L["Items of your auction house worth a look now: prices skyrocketing or falling, scarce or flooded, or under their usual price."]
			end
			return L["Price dashboard"], L["Your charts: the items you picked, a small chart each."]
		end)
		f.Tabs[#f.Tabs + 1] = b
	end
	x = x + 13
	f.tabsRight = x
	f.Ranges = Ch.RangeButtons(f, function(r)
		Ds.UI().range = r
		Ds.Draw()
	end)
	for _, b in ipairs(f.Ranges) do
		b:SetPoint("TOPLEFT", x, -5)
		x = x + b:GetWidth() + 3
	end
	f.Edit = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.Edit:SetSize(70, 20)
	f.Edit:SetPoint("TOPRIGHT", -32, -6)
	f.Edit:SetScript("OnClick", function()
		Ds.SetEdit(not Ds.editing)
	end)
	Ch.SetTip(f.Edit, function()
		if Ds.editing then
			return L["Done"], L["Leave edit mode."]
		end
		return L["Edit"], L["Add items, remove them or change their order."]
	end)
	-- Edit mode: the box, Add, Add all watched, what happened.
	local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	box:SetSize(220, 20)
	box:SetPoint("TOPLEFT", C.PAD + 6, -C.TOP - 4)
	box:SetAutoFocus(false)
	box:SetMaxLetters(120)
	box.Hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	box.Hint:SetPoint("LEFT", 2, 0)
	box.Hint:SetText(L["Item name, link or #ID"])
	box:SetScript("OnTextChanged", function(self)
		self.Hint:SetShown((self:GetText() or "") == "")
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	box:SetScript("OnEnterPressed", function(self)
		Ds.AddText(self:GetText())
	end)
	Ch.SetTip(box, function() return L["Add an item"], L["Type its name (as on your auction house), shift-click it into the box, or type #ID; then Enter or Add."] end)
	f.Box = box
	if W.ItemActions then
		W.ItemActions.AcceptLinks(box, function(item) Ds.AddItem(item) end)
	end
	f.Add = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.Add:SetSize(60, 20)
	f.Add:SetPoint("LEFT", box, "RIGHT", 6, 0)
	f.Add:SetText(L["Add"])
	f.Add:SetScript("OnClick", function() Ds.AddText(box:GetText()) end)
	Ch.SetTip(f.Add, function() return L["Add"], L["Adds the item in the box as a tile."] end)
	f.AddWatched = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.AddWatched:SetSize(130, 20)
	f.AddWatched:SetPoint("LEFT", f.Add, "RIGHT", 6, 0)
	f.AddWatched:SetText(L["Add all watched"])
	f.AddWatched:SetScript("OnClick", Ds.AddWatched)
	Ch.SetTip(f.AddWatched, function() return L["Add all watched"], L["Adds every item of your watch list (the Stocks tab) that isn't on the dashboard yet."] end)
	f.Status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.Status:SetPoint("LEFT", f.AddWatched, "RIGHT", 8, 0)
	f.Status:SetJustifyH("LEFT")
	f.Status:SetWordWrap(false)
	-- The tiles, in a scroll frame.
	local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	f.Scroll = scroll
	f.Child = CreateFrame("Frame", nil, scroll)
	f.Child:SetSize(100, 100)
	scroll:SetScrollChild(f.Child)
	f.Message = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	f.Message:SetJustifyH("LEFT")
	f.Message:Hide()
	Ds.driver = CreateFrame("Frame", nil, f)
	Ds.driver:Hide()
	Ds.driver:SetScript("OnUpdate", function()
		LT.Guard("WhyPoor.dashboard", Ds.SearchStep)
	end)
	Ch.Ticker(f, Ds.Tick)
	f:SetScript("OnEvent", function()
		Ds.due = true
	end)
	f:HookScript("OnShow", function(self)
		self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	end)
end

function Ds.Tick(elapsed)
	local f = Ds.frame
	Ds.wait = (Ds.wait or 0) - elapsed
	Ds.sizeWait = (Ds.sizeWait or 0) - elapsed
	if f.resized and (not f.sizing or Ds.sizeWait <= 0) then
		f.resized, Ds.sizeWait = false, 0.1
		Ds.due = true
	end
	if Ds.fill then
		Ds.FillSome()
	end
	if Ds.Page() == "highlights" then
		W.Highlights.Tick(elapsed)
	end
	if Ds.wait <= 0 then
		Ds.wait = 1
		local key = Ds.Key()
		if key ~= Ds.key then
			Ds.key = key
			Ds.due = true
		end
	end
	if Ds.due then
		Ds.Draw()
	end
end

function Ds.SetEdit(on)
	Ds.editing = on and true or false
	if Ds.frame and not Ds.editing then
		Ds.frame.Box:ClearFocus()
	end
	Ds.Draw()
end

function Ds.Say(text)
	if Ds.frame then
		Ds.frame.Status:SetText(text or "")
	end
end

-- Adds an item (once; TILE_MAX at most). True when added.
function Ds.AddItem(item)
	item = Num(item)
	if not item then
		return false
	end
	local list = Ds.Items()
	for _, id in ipairs(list) do
		if id == item then
			Ds.Say(L["Already on the dashboard: %s"]:format(W.Window.ItemName(item)))
			return false
		end
	end
	if #list >= Ch.TILE_MAX then
		Ds.Say(ORANGE .. L["The dashboard holds %d items at most."]:format(Ch.TILE_MAX) .. "|r")
		return false
	end
	list[#list + 1] = item
	Ds.UI().items = list
	Ds.Say(L["Added: %s"]:format(W.Window.ItemName(item)))
	if Ds.frame then
		Ds.frame.Box:SetText("")
	end
	Ds.due = true
	return true
end

function Ds.AddWatched()
	local St = W.Stocks
	local list = St and St.List and St.List() or {}
	local added = 0
	local items = Ds.Items()
	local have = {}
	for _, id in ipairs(items) do
		have[id] = true
	end
	for _, id in ipairs(list) do
		if Num(id) and not have[id] and #items < Ch.TILE_MAX then
			items[#items + 1] = id
			have[id] = true
			added = added + 1
		end
	end
	Ds.UI().items = items
	Ds.Say(#list == 0 and L["Your watch list is empty: add items in the Stocks tab."] or L["%d added"]:format(added))
	Ds.due = true
end

-- A name lowercased (kept), nil while the client doesn't know the item yet (asked for).
function Ch.LowerName(item)
	local name = Ch.lower[item]
	if name then
		return name
	end
	local ok, n = pcall(C_Item.GetItemInfo, ("item:%d"):format(item))
	if ok and type(n) == "string" and not LT.IsSecret(n) then
		name = n:lower()
		Ch.lower[item] = name
		return name
	end
	if C_Item.RequestLoadItemDataByID then
		pcall(C_Item.RequestLoadItemDataByID, item)
	end
end

-- What the box says: a link or #ID at once; a name the client knows at once; else the auction house's items
-- by name over frames (exact, then starting with it, then having it).
function Ds.AddText(text)
	text = strtrim(text or "")
	if text == "" then
		Ds.Say(L["Type an item's name, link or #ID first."])
		return
	end
	local id = Ch.ParseItem(text)
	if id then
		Ds.AddItem(id)
		return
	end
	local ok, _, link = pcall(C_Item.GetItemInfo, text)
	id = ok and Ch.ParseItem(link)
	if id then
		Ds.AddItem(id)
		return
	end
	local P = W.Prices
	local list = P and P.Items and P.Items() or {}
	Ds.search = { q = text:lower(), list = list, i = 1 }
	Ds.Say(L["Searching..."])
	Ds.driver:Show()
end

function Ds.SearchStep()
	local s = Ds.search
	if not s then
		Ds.driver:Hide()
		return
	end
	local start, n = Clock(), 0
	while s.i <= #s.list do
		local item = s.list[s.i]
		s.i, n = s.i + 1, n + 1
		local name = Ch.LowerName(item)
		if name then
			if name == s.q then
				s.exact = item
				break
			elseif not s.prefix and name:sub(1, #s.q) == s.q then
				s.prefix = item
			elseif not s.contains and name:find(s.q, 1, true) then
				s.contains = item
			end
		end
		if n >= Ds.C.PER_FRAME or (n % 50 == 0 and start and (Clock() or start) - start > Ds.C.BUDGET_MS) then
			return
		end
	end
	Ds.search = nil
	Ds.driver:Hide()
	local found = s.exact or s.prefix or s.contains
	if found then
		Ds.AddItem(found)
	else
		Ds.Say(ORANGE .. L["No item by that name in your auction house's prices."] .. "|r")
	end
end

function Ds.Remove(i)
	local list = Ds.Items()
	if list[i] then
		table.remove(list, i)
		Ds.UI().items = list
		Ds.Draw()
	end
end

function Ds.Move(i, delta)
	local list = Ds.Items()
	local j = i + delta
	if list[i] and list[j] then
		list[i], list[j] = list[j], list[i]
		Ds.UI().items = list
		Ds.Draw()
	end
end

-- A tile (pooled): a Button (a click: the big chart), its icon, name, price and change, a small chart, and in
-- edit mode < > and X.
function Ds.Tile(i)
	local t = Ds.tiles[i]
	if t then
		return t
	end
	local f = Ds.frame
	t = CreateFrame("Button", nil, f.Child)
	t.Back = t:CreateTexture(nil, "BACKGROUND")
	t.Back:SetAllPoints()
	t.Back:SetColorTexture(1, 1, 1, 0.04)
	t:SetHighlightTexture(HIGHLIGHT, "ADD")
	t.Icon = t:CreateTexture(nil, "ARTWORK")
	t.Icon:SetSize(16, 16)
	t.Icon:SetPoint("TOPLEFT", 6, -6)
	t.Name = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	t.Name:SetPoint("TOPLEFT", 26, -8)
	t.Name:SetJustifyH("LEFT")
	t.Name:SetWordWrap(false)
	t.Price = t:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	t.Price:SetPoint("TOPLEFT", 6, -26)
	t.Change = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	t.Change:SetPoint("LEFT", t.Price, "RIGHT", 8, 0)
	t:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	t:SetScript("OnClick", function(self, button)
		local Ia = W.ItemActions
		if button ~= "LeftButton" or (IsModifiedClick and IsModifiedClick()) then
			if Ia and Ia.Click(self, self.item, button) then
				return
			end
		end
		if button == "LeftButton" then
			Ch.Open(self.item)
		end
	end)
	Ch.SetTip(t, function(self)
		return W.Window.ItemName(self.item), self.tipLine, L["Click: the big chart"]
	end)
	t.widget = Ch.NewWidget(t, { mini = true, maxSeg = Ch.TILE_SEG, onClick = function(w) Ch.Open(w.item) end })
	t.widget.frame:SetPoint("TOPLEFT", 6, -44)
	local function Small(label, x, onClick, tip)
		local b = CreateFrame("Button", nil, t, "UIPanelButtonTemplate")
		b:SetSize(22, 18)
		b:SetText(label)
		b:SetPoint("TOPRIGHT", x, -4)
		b:SetScript("OnClick", function() onClick(t.index) end)
		Ch.SetTip(b, tip)
		b:Hide()
		return b
	end
	t.Remove = Small("x", -4, Ds.Remove, function() return L["Remove"], L["Takes it off the dashboard (its prices stay)."] end)
	t.Right = Small(">", -28, function(k) Ds.Move(k, 1) end, function() return L["Move right"], L["One place later on the dashboard."] end)
	t.Left = Small("<", -52, function(k) Ds.Move(k, -1) end, function() return L["Move left"], L["One place earlier on the dashboard."] end)
	Ds.tiles[i] = t
	return t
end

-- The tiles laid out in columns that fit the width (1 to COLS); their charts drawn for the dashboard's range,
-- PER_TICK tiles at once and the rest on the next frames (Ds.Tick), so a full dashboard never stalls a frame.
function Ds.Draw()
	local f, C = Ds.frame, Ds.C
	if not (f and f:IsShown()) then
		return
	end
	Ds.due, Ds.draws, Ds.key = false, Ds.draws + 1, Ds.Key()
	-- The page: My charts or Highlights.
	local charts = Ds.Page() == "charts"
	for _, b in ipairs(f.Tabs) do
		Ch.PaintFlat(b, (b.page == "charts") == charts)
	end
	for _, b in ipairs(f.Ranges) do
		b:SetShown(charts)
	end
	f.Edit:SetShown(charts)
	f.Scroll:SetShown(charts)
	if W.Highlights then
		W.Highlights.Page(f, not charts)
	end
	if not charts then
		for _, o in ipairs({ f.Box, f.Add, f.AddWatched, f.Status, f.Message }) do
			o:Hide()
		end
		Ds.fill = nil
		return
	end
	local items = Ds.Items()
	local range = Ds.Range()
	local now = time()
	Ch.PaintRanges(f.Ranges, range, nil)
	f.Edit:SetText(Ds.editing and L["Done"] or L["Edit"])
	local edit = Ds.editing or #items == 0
	for _, o in ipairs({ f.Box, f.Add, f.AddWatched, f.Status }) do
		o:SetShown(edit)
	end
	f.AddWatched:SetEnabled(W.Stocks ~= nil and W.Stocks.List ~= nil)
	local width, height = f:GetSize()
	local top = C.TOP + (edit and C.EDIT or 0)
	f.Scroll:ClearAllPoints()
	f.Scroll:SetPoint("TOPLEFT", C.PAD, -top)
	f.Scroll:SetSize(width - 2 * C.PAD - C.BAR, height - top - C.PAD - 8)
	local inner = width - 2 * C.PAD - C.BAR
	local cols = math.max(1, math.min(C.COLS, math.floor((inner + C.GAP) / (C.TILE_W + C.GAP))))
	local tw = math.floor((inner - (cols - 1) * C.GAP) / cols)
	f.Message:SetShown(#items == 0)
	f.Message:ClearAllPoints()
	f.Message:SetPoint("TOPLEFT", C.PAD + 8, -top - 12)
	f.Message:SetWidth(inner - 16)
	f.Message:SetText(L["No items on your dashboard yet: add one above, or all your watched items."])
	for i, item in ipairs(items) do
		local t = Ds.Tile(i)
		t.item, t.index, t.widget.item = item, i, item
		local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", f.Child, "TOPLEFT", col * (tw + C.GAP), -row * (C.TILE_H + C.GAP))
		t:SetSize(tw, C.TILE_H)
		t:Show()
		for _, b in ipairs({ t.Remove, t.Left, t.Right }) do
			b:SetShown(Ds.editing)
		end
		t.Left:SetEnabled(i > 1)
		t.Right:SetEnabled(i < #items)
		t.Name:SetWidth(tw - 32 - (Ds.editing and 76 or 0))
	end
	Ds.fill = { next = 1, range = range, now = now, items = items }
	Ds.FillSome()
	for i = #items + 1, #Ds.tiles do
		Ds.tiles[i]:Hide()
		Ds.tiles[i].item = nil
	end
	local rows = math.ceil(#items / cols)
	f.Child:SetSize(inner, math.max(1, rows * (C.TILE_H + C.GAP)))
end

-- The next PER_TICK tiles' charts (Ds.fill: where the last draw got to).
function Ds.FillSome()
	local job = Ds.fill
	if not job then
		return
	end
	for _ = 1, Ds.C.PER_TICK do
		local i = job.next
		local item = job.items[i]
		if not item then
			Ds.fill = nil
			return
		end
		job.next = i + 1
		if Ds.tiles[i] and Ds.tiles[i].item == item then
			Ds.FillTile(Ds.tiles[i], item, job.range, job.now)
		end
	end
end

-- What the tiles rest on: the prices' revision and five minutes (the ranges move on).
function Ds.Key()
	local P = W.Prices
	return (P and P.Revision and P.Revision() or 0) .. ":" .. math.floor(time() / 300)
end

function Ds.FillTile(t, item, range, now)
	local Wn = W.Window
	local first = Ch.Span(item)
	local from = Ch.RangeStart(range, now, first)
	local points, res = Ch.Points(item, from, now)
	local prev = range == "1D" and Ch.PrevClose(item, from) or nil
	t.Icon:SetTexture(Wn.ItemIcon(item))
	t.Name:SetText(Wn.ItemName(item))
	local P = W.Prices
	local get = P and P.Get and P.Get(item)
	local current = Ch.Current(points, get, nil, false)
	t.Price:SetText(current and Money(current) or GREY .. "-|r")
	local text, color = Ch.Change(Ch.Base(points, prev), points[1] and current)
	t.Change:SetText(text and (Ch.Hex(color) .. text .. "|r") or "")
	t.tipLine = text and (text .. " " .. Ch.OVER[range]) or nil
	local listed = Ch.ListedChange(points)
	local sold, perDay = Ch.Sold(item, from, now)
	for _, line in ipairs({ listed or false, Ch.SellsText(perDay) or false }) do
		if line then
			t.tipLine = (t.tipLine and (t.tipLine .. "\n") or "") .. line
		end
	end
	t.widget:SetSize(t:GetWidth() - 12, Ds.C.TILE_H - 50)
	local empty = first and L["No prices in this range."] or L["No prices yet: open the auction house."]
	t.widget:SetSeries(points, from, now, res, { prev = prev, empty = empty, volume = true, sold = sold })
end

-- Opens the dashboard (edit mode when it's empty) on a page ("charts" | "highlights"; nil: the one kept). False:
-- switched off.
function Ds.Open(page)
	if not Ch.Enabled() then
		return false
	end
	if not Ds.frame then
		Ds.Build()
	end
	if page then
		Ds.UI().page = page == "highlights" and "highlights" or "charts"
	end
	Ds.frame:Show()
	if Ds.frame.Raise then
		Ds.frame:Raise()
	end
	Ds.frame.resized = false
	Ds.Draw()
	return true
end

function Ch.OpenDashboard(page)
	return Ds.Open(page)
end

-- Switched off: both windows closed.
function Ch.SettingsChanged()
	local m = W.module
	if m and not m.enabled then
		if Ch.frame then
			Ch.frame:Hide()
		end
		if Ds.frame then
			Ds.frame:Hide()
		end
	end
end

-- For the tests: the big window, its state, its widget; the dashboard.
function Ch.View()
	return Ch.frame, Ch.state, Ch.widget, Ds
end

-- /lefthy perf: the windows and the highlights.
LT.PerfState("WhyPoor windows", function()
	local Wn, Hl = W.Window, W.Highlights
	local parts = {}
	parts[#parts + 1] = "window " .. ((Wn and Wn.Shown and Wn.Shown()) and ("shown (" .. tostring(Wn.state.tab) .. ", "
		.. tostring(Wn.state.draws) .. " draws)") or "hidden")
	parts[#parts + 1] = "big chart " .. ((Ch.frame and Ch.frame:IsShown()) and ("shown (item " .. tostring(Ch.state.item)
		.. ", " .. tostring(Ch.state.draws) .. " draws)") or "hidden")
	parts[#parts + 1] = "dashboard " .. ((Ds.frame and Ds.frame:IsShown()) and ("shown (" .. tostring(Ds.Page()) .. ", "
		.. #Ds.Items() .. " tiles, " .. tostring(Ds.draws) .. " draws)") or "hidden")
	local job = Hl and Hl.job
	parts[#parts + 1] = "highlights " .. (job and ("working (%d of %d)"):format(job.i or 0, job.list and #job.list or 0) or "idle")
	return table.concat(parts, ", ")
end)
