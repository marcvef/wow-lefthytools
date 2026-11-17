local _, ns = ...
local LT = ns.LT
local L = ns.L
local W = ns.WhyPoor or {}

-- WhyPoor?'s highlights (W.Highlights, Hl): the price dashboard's second page (docs/whypoor.md, Charts: the
-- highlights). Items of your auction house worth a look now, each section a short ranked list:
--   * Skyrocketing / Falling: the biggest price rises and drops in 1, 7 or 14 days (each day's lowest price);
--   * Scarce now: half as many listed or fewer than then while the price held or rose;
--   * Flooded: twice its usual count listed or more (the price usually follows);
--   * Below usual: the lowest price now well under its usual price (a buying chance).
-- Noise left out: a usual price under the "Min price" picked (1s by default), fewer than 5 listed, under 3 days of
-- prices, prices that jump around or are more than a day old (P.Confidence "low"); ties go to the bigger worth
-- (usual price x listed).
-- What it costs: every item of your auction house's prices (P.Entry: Prices' decoded entries, kept while their text
-- stays, which the ideas' market pass fills anyway) looked at over frames, 2 ms and 1000 items a frame at most, only
-- while the page shows; the answer kept by the prices' revision,
-- the min price and the hour (worked out again at most every 30 s while prices change). Only the rows shown ask
-- for their sales a day (P.SoldSeries) and days of supply.

local Hl = { rows = {}, draws = 0, runs = 0 }
W.Highlights = Hl
local Ch = W.Chart

local GREY, ORANGE, BLUE, GREEN, SEP = "|cff888888", "|cffff9933", "|cff66b3ff", "|cff40d966", " · "
local HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local DAY = 86400

Hl.C = { PAD = 10, TOP = 34, LIST_Y = 80, ROW_H = 30, SPARK_W = 72, SPARK_H = 20, RIGHT_W = 140, SPARK_MIN = 440, BAR = 22,
	BUDGET_MS = 2, PER_FRAME = 1000, STEP = 50, REFRESH = 30 }
Hl.ROWS = 10           -- rows a section shows at most
Hl.DAYS = 14           -- (the daily lows Prices.lua keeps)
Hl.MIN_DAYS = 3        -- days of prices an item needs
Hl.MIN_LISTED = 5      -- listed now at least (scarce: before)
Hl.MOVE = 0.10         -- skyrocketing and falling: 10% at least
Hl.SCARCE_FROM = 10    -- scarce: this many listed then at least,
Hl.SCARCE_DROP = 0.5   -- half as many now or fewer,
Hl.HELD = 0.95         -- and the price at least 95% of then (held or rose)
Hl.FLOOD = 2           -- flooded: twice its usual count listed at least,
Hl.FLOOD_USUAL = 5     -- its usual count (the median of the other days') this many at least
Hl.BELOW = 0.75        -- below usual: the lowest now at most 75% of the usual price
Hl.SPANS = { 1, 7, 14 }
-- The day a span compares with: the newest day with a price this many days before the newest day (14: what's kept).
Hl.BACK = { [1] = { 1, 2 }, [7] = { 6, 9 }, [14] = { 10, 13 } }
Hl.MINS = { 10, 100, 1000, 10000 } -- the min price's choices (copper): 10c, 1s, 10s, 1g
Hl.MIN_DEFAULT = 100
Hl.WORDS = { [1] = L["1 day"], [7] = L["7 days"], [14] = L["14 days"] }
Hl.SECTIONS = {
	{ key = "rise", label = L["Skyrocketing"], span = true },
	{ key = "fall", label = L["Falling"], span = true },
	{ key = "scarce", label = L["Scarce now"], span = true },
	{ key = "flood", label = L["Flooded"] },
	{ key = "below", label = L["Below usual"] },
}

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

local function Pct(x)
	return math.floor(x * 100 + 0.5)
end

---------------------------------------------------------------------------
-- The choices (kept in ui.dashboard)
---------------------------------------------------------------------------

function Hl.UI()
	return Ch.dash.UI()
end

function Hl.Span()
	local s = Hl.UI().hlSpan
	return Hl.BACK[s] and s or 7
end

function Hl.Section()
	local s = Hl.UI().hlSection
	for _, sec in ipairs(Hl.SECTIONS) do
		if sec.key == s then
			return s
		end
	end
	return "rise"
end

function Hl.Min()
	local m = Hl.UI().hlMin
	for _, v in ipairs(Hl.MINS) do
		if v == m then
			return m
		end
	end
	return Hl.MIN_DEFAULT
end

function Hl.SetSpan(span)
	Hl.UI().hlSpan = span
	Hl.Draw()
end

function Hl.SetSection(key)
	Hl.UI().hlSection = key
	Hl.Draw()
end

-- The next higher (1) or lower (-1) min price; worked out again at once.
function Hl.StepMin(delta)
	local m, k = Hl.Min(), 1
	for i, v in ipairs(Hl.MINS) do
		if v == m then
			k = i
		end
	end
	k = math.max(1, math.min(#Hl.MINS, k + delta))
	Hl.UI().hlMin = Hl.MINS[k]
	if Hl.Shown() then
		Hl.Start()
		Hl.Step()
	end
	Hl.Draw()
end

---------------------------------------------------------------------------
-- Working it out: every item, over frames
---------------------------------------------------------------------------

-- What an answer rests on: the prices' revision, the min price, the hour (prices more than a day old drop out).
function Hl.Key()
	local P = W.Prices
	return (P and P.Revision and P.Revision() or 0) .. ":" .. Hl.Min() .. ":" .. math.floor(time() / 3600)
end

-- A new answer: { total, enough (3+ days), fresh (and a day old at most), steady (and every filter met), flood,
-- below, spans = { [span] = { rise, fall, scarce } } }; each list ranked, ROWS at most, n: how many fit.
function Hl.NewAnswer(total)
	local a = { total = total, enough = 0, fresh = 0, steady = 0, flood = { n = 0 }, below = { n = 0 }, spans = {} }
	for _, s in ipairs(Hl.SPANS) do
		a.spans[s] = { rise = { n = 0 }, fall = { n = 0 }, scarce = { n = 0 } }
	end
	return a
end

-- Starts over: this realm's and faction's items (P.Saved, P.HomeKey: the house's items), their keys taken at once
-- (P.Keys: no sort, unlike P.Items; friends' items alone have no daily lows to compare).
function Hl.Start()
	local P = W.Prices
	local saved = P and P.Saved and P.Saved()
	local key = P and P.HomeKey and P.HomeKey()
	local h = saved and key and type(saved.houses) == "table" and saved.houses[key]
	local items = type(h) == "table" and type(h.items) == "table" and h.items or {}
	local list = (P and P.Keys) and P.Keys(items) or {}
	local now = time()
	Hl.runs = Hl.runs + 1
	Hl.job = { key = Hl.Key(), min = Hl.Min(), house = key, items = items, list = list, i = 1, now = now,
		today = math.floor(now / DAY), answer = Hl.NewAnswer(#list) }
end

-- A slice: BUDGET_MS and PER_FRAME items at most (the clock looked at every STEP items). Done: the answer kept.
function Hl.Step()
	local job = Hl.job
	if not job then
		return
	end
	local C = Hl.C
	local start, n = Clock(), 0
	local list, items = job.list, job.items
	while job.i <= #list do
		local item = list[job.i]
		job.i, n = job.i + 1, n + 1
		if type(item) == "number" and type(items[item]) == "string" then
			Hl.Look(job, item)
		end
		if job.i <= #list and (n >= C.PER_FRAME or (n % C.STEP == 0 and start and (Clock() or start) - start > C.BUDGET_MS)) then
			Hl.slice = n
			return
		end
	end
	Hl.slice = n
	local a = job.answer
	a.key, a.min, a.at = job.key, job.min, GetTime()
	Hl.answer, Hl.job = a, nil
	Hl.Draw()
end

-- r ranks before o: the bigger score, then the bigger worth, then the lower ID.
function Hl.Better(r, o)
	if r.score ~= o.score then
		return r.score > o.score
	end
	if r.worth ~= o.worth then
		return r.worth > o.worth
	end
	return r.item < o.item
end

-- Into a ranked list (ROWS at most); n counts every one that fit.
function Hl.Offer(list, r)
	list.n = list.n + 1
	local n = #list
	if n >= Hl.ROWS and not Hl.Better(r, list[n]) then
		return
	end
	local i = n + 1
	while i > 1 and Hl.Better(r, list[i - 1]) do
		list[i] = list[i - 1]
		i = i - 1
	end
	list[i] = r
	if #list > Hl.ROWS then
		list[#list] = nil
	end
end

-- The median of a few numbers (sorted in place).
function Hl.Median(values)
	table.sort(values)
	local n = #values
	if n == 0 then
		return nil
	end
	if n % 2 == 1 then
		return values[(n + 1) / 2]
	end
	return (values[n / 2] + values[n / 2 + 1]) / 2
end

-- One item: its entry (the last scan, its daily lows), the filters, then each section.
function Hl.Look(job, item)
	local P = W.Prices
	local e = P.Entry(job.house, item)
	if not (e and Num(e.seen)) then
		return
	end
	local a, today = job.answer, job.today
	local n, newest, maxQty, maxLow = 0, nil, 0, 0
	for _, d in ipairs(e.days) do
		local age = today - d[1]
		if age >= 0 and age < Hl.DAYS then
			n = n + 1
			if not newest or d[1] > newest[1] then
				newest = d
			end
			maxQty, maxLow = math.max(maxQty, d[3] or 0), math.max(maxLow, d[2])
		end
	end
	if n < Hl.MIN_DAYS then
		return
	end
	a.enough = a.enough + 1
	local age = job.now - e.seen
	if age > DAY or age < 0 then
		return -- (more than a day old: low confidence)
	end
	a.fresh = a.fresh + 1
	local qty = e.qty or 0
	if not e.low or maxLow < job.min or (qty < Hl.MIN_LISTED and maxQty < Hl.SCARCE_FROM) then
		return -- (none listed now; never as dear as the min price; too few listed)
	end
	local value = P.Value(e.days, today)
	if not value or value < job.min then
		return
	end
	local unstable = P.Unstable(e.days, today)
	if P.Confidence(n, unstable, age, qty) == "low" then
		return
	end
	a.steady = a.steady + 1
	local base = { item = item, value = value, low = e.low, qty = qty, seen = e.seen, worth = value * qty, days = e.days,
		today = today, newest = newest[1], to = newest[2] }
	local function Rec(score, extra)
		local r = { score = score }
		for k, v in pairs(base) do
			r[k] = v
		end
		for k, v in pairs(extra or {}) do
			r[k] = v
		end
		return r
	end
	local enough = qty >= Hl.MIN_LISTED
	if enough and e.low <= value * Hl.BELOW then
		Hl.Offer(a.below, Rec(Pct((value - e.low) / value), { price = e.low }))
	end
	if enough and qty >= Hl.FLOOD * Hl.FLOOD_USUAL then
		local counts = {}
		for _, d in ipairs(e.days) do
			if d ~= newest and today - d[1] >= 0 and today - d[1] < Hl.DAYS then
				counts[#counts + 1] = d[3] or 0
			end
		end
		local usual = Hl.Median(counts)
		if usual and usual >= Hl.FLOOD_USUAL and qty >= usual * Hl.FLOOD then
			Hl.Offer(a.flood, Rec(Pct(qty / usual), { price = e.low, usualQty = usual }))
		end
	end
	for _, s in ipairs(Hl.SPANS) do
		local back, then_ = Hl.BACK[s], nil
		for _, d in ipairs(e.days) do
			local gap = newest[1] - d[1]
			if gap >= back[1] and gap <= back[2] and (not then_ or d[1] > then_[1]) then
				then_ = d
			end
		end
		if then_ and then_[2] > 0 then
			local lists = a.spans[s]
			local change = (newest[2] - then_[2]) / then_[2]
			local extra = { from = then_[2], price = newest[2], fromQty = then_[3] or 0, fromDay = then_[1] }
			if enough and change >= Hl.MOVE then
				Hl.Offer(lists.rise, Rec(Pct(change), extra))
			elseif enough and change <= -Hl.MOVE then
				Hl.Offer(lists.fall, Rec(Pct(-change), extra))
			end
			local was = then_[3] or 0
			if was >= Hl.SCARCE_FROM and qty <= was * (1 - Hl.SCARCE_DROP) and newest[2] >= then_[2] * Hl.HELD then
				Hl.Offer(lists.scarce, Rec(Pct((was - qty) / was), extra))
			end
		end
	end
end

-- A section's list in an answer.
function Hl.List(a, key, span)
	if not a then
		return nil
	end
	if key == "flood" or key == "below" then
		return a[key]
	end
	return a.spans[span] and a.spans[span][key]
end

-- Worked out again when there's no answer, the min price changed, or the prices did and the last is REFRESH old.
function Hl.Want()
	if Hl.job then
		return
	end
	local a = Hl.answer
	if not a or a.min ~= Hl.Min() or (a.key ~= Hl.Key() and GetTime() - (a.at or 0) >= Hl.C.REFRESH) then
		Hl.Start()
		Hl.Step()
	end
end

function Hl.Shown()
	return Hl.panel ~= nil and Hl.panel:IsShown() and Ch.dash.frame ~= nil and Ch.dash.frame:IsShown()
end

-- Each frame while the page shows (the dashboard's ticker): a slice of the work; every second, whether it's due.
function Hl.Tick(elapsed)
	if not Hl.Shown() then
		return
	end
	if Hl.job then
		Hl.Step()
		Hl.Status()
		return
	end
	Hl.wait = (Hl.wait or 0) - elapsed
	if Hl.wait <= 0 then
		Hl.wait = 1
		Hl.Want()
		Hl.Status()
	end
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

-- A section's line under the buttons: what it lists.
function Hl.Describe(key, span)
	local words = Hl.WORDS[span]
	if key == "rise" then
		return L["The biggest price rises in %s (each day's lowest price)."]:format(words)
	elseif key == "fall" then
		return L["The biggest price drops in %s (each day's lowest price)."]:format(words)
	elseif key == "scarce" then
		return L["Half as many listed or fewer than %s ago, while the price held or rose."]:format(words)
	elseif key == "flood" then
		return L["Twice its usual count listed or more: the price usually follows."]
	end
	return L["The lowest price now %d%% or more under its usual price: a buying chance."]:format(Pct(1 - Hl.BELOW))
end

-- What the page says instead of rows (nil: rows, or still working it out).
function Hl.Empty(a, key, span)
	if not a then
		return nil
	end
	if a.total == 0 then
		return L["No prices yet: open the auction house."]
	elseif a.enough == 0 then
		return L["Open the auction house a few days in a row: highlights need 3 days of prices."]
	elseif a.fresh == 0 then
		return L["Your prices are more than a day old: open the auction house for fresh highlights."]
	end
	local list = Hl.List(a, key, span)
	if list and list.n > 0 then
		return nil
	end
	if key == "rise" then
		return L["No price rose %d%% or more in %s."]:format(Pct(Hl.MOVE), Hl.WORDS[span])
	elseif key == "fall" then
		return L["No price fell %d%% or more in %s."]:format(Pct(Hl.MOVE), Hl.WORDS[span])
	elseif key == "scarce" then
		return L["Nothing got scarce in %s."]:format(Hl.WORDS[span])
	elseif key == "flood" then
		return L["Nothing is flooded right now."]
	end
	return L["Nothing is listed well under its usual price right now."]
end

-- The filters, said (the min price's tooltip, an empty section).
function Hl.Filters()
	return L["Left out: fewer than %d listed, under %d days of prices, prices that jump around or are more than a day old."]:format(
		Hl.MIN_LISTED, Hl.MIN_DAYS)
end

function Hl.Status()
	local p = Hl.panel
	if not p then
		return
	end
	local job = Hl.job
	if job then
		local pct = #job.list > 0 and math.floor((job.i - 1) / #job.list * 100) or 0
		p.Status:SetText(L["Working it out: %d%%"]:format(pct))
	elseif Hl.answer then
		p.Status:SetText(L["%d items with steady prices"]:format(Hl.answer.steady))
	else
		p.Status:SetText("")
	end
end

function Hl.Build(f)
	local C = Hl.C
	local p = CreateFrame("Frame", nil, f)
	p:SetAllPoints()
	p:Hide()
	Hl.panel = p
	-- The spans, on the title row after the page tabs.
	p.Spans = {}
	local x = f.tabsRight or 200
	for _, s in ipairs(Hl.SPANS) do
		local b = Ch.FlatButton(p, Hl.WORDS[s], function() Hl.SetSpan(s) end)
		b.span = s
		b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -5)
		x = x + b:GetWidth() + 3
		Ch.SetTip(b, function()
			return Hl.WORDS[s], L["Skyrocketing, Falling and Scarce now compare the newest day's prices with those this long before."]
		end)
		p.Spans[#p.Spans + 1] = b
	end
	-- The min price.
	p.Min = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	p.Min:SetSize(110, 20)
	p.Min:SetPoint("TOPRIGHT", f, "TOPRIGHT", -32, -6)
	p.Min:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	p.Min:SetScript("OnClick", function(_, button)
		Hl.StepMin(button == "RightButton" and -1 or 1)
	end)
	Ch.SetTip(p.Min, function()
		return L["Min price"], L["Only items whose usual price is at least this much: cheaper ones are mostly noise."], Hl.Filters(),
			L["Click: higher; right-click: lower"]
	end)
	-- The sections.
	p.Sections = {}
	local prev
	for _, sec in ipairs(Hl.SECTIONS) do
		local b = Ch.FlatButton(p, sec.label, function() Hl.SetSection(sec.key) end)
		b.key, b.label = sec.key, sec.label
		if prev then
			b:SetPoint("LEFT", prev, "RIGHT", 3, 0)
		else
			b:SetPoint("TOPLEFT", f, "TOPLEFT", C.PAD, -C.TOP)
		end
		Ch.SetTip(b, function() return sec.label, Hl.Describe(sec.key, Hl.Span()) end)
		p.Sections[#p.Sections + 1] = b
		prev = b
	end
	p.Desc = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	p.Desc:SetPoint("TOPLEFT", f, "TOPLEFT", C.PAD + 2, -C.TOP - 27)
	p.Desc:SetJustifyH("LEFT")
	p.Desc:SetWordWrap(false)
	p.Status = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	p.Status:SetPoint("TOPRIGHT", f, "TOPRIGHT", -C.PAD - 4, -C.TOP - 27)
	p.Status:SetJustifyH("RIGHT")
	-- The rows, in a scroll frame.
	p.Scroll = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
	p.Child = CreateFrame("Frame", nil, p.Scroll)
	p.Child:SetSize(100, 100)
	p.Scroll:SetScrollChild(p.Child)
	p.Message = p:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	p.Message:SetJustifyH("LEFT")
	p.Message:SetPoint("TOPLEFT", f, "TOPLEFT", C.PAD + 8, -C.LIST_Y - 8)
	p.Message:Hide()
end

-- Shows or hides the page (the dashboard's Draw); shown, worked out when due and drawn.
function Hl.Page(f, shown)
	if not Hl.panel then
		Hl.Build(f)
	end
	Hl.panel:SetShown(shown)
	if shown then
		Hl.Want()
		Hl.Draw()
	end
end

-- A row (pooled): icon, name, its sub line (listed, sold a day, days of supply), a sparkline of its 14 days, the
-- change and the price. Click: the big chart; right-click or shift-click: the item's actions.
function Hl.Row(i)
	local row = Hl.rows[i]
	if row then
		return row
	end
	local C = Hl.C
	row = CreateFrame("Button", nil, Hl.panel.Child)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.Back = row:CreateTexture(nil, "BACKGROUND")
	row.Back:SetAllPoints()
	row.Back:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.035 or 0)
	row:SetHighlightTexture(HIGHLIGHT, "ADD")
	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(22, 22)
	row.Icon:SetPoint("LEFT", 4, 0)
	row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Name:SetPoint("TOPLEFT", 32, -3)
	row.Name:SetJustifyH("LEFT")
	row.Name:SetWordWrap(false)
	row.Sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.Sub:SetPoint("TOPLEFT", 32, -16)
	row.Sub:SetJustifyH("LEFT")
	row.Sub:SetWordWrap(false)
	row.Change = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Change:SetPoint("TOPRIGHT", -6, -3)
	row.Change:SetJustifyH("RIGHT")
	row.Price = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Price:SetPoint("TOPRIGHT", -6, -16)
	row.Price:SetJustifyH("RIGHT")
	row.Spark = CreateFrame("Frame", nil, row)
	row.Spark:SetSize(C.SPARK_W, C.SPARK_H)
	row.Spark:SetPoint("RIGHT", row, "RIGHT", -C.RIGHT_W - 6, 0)
	row.Lines = {}
	row:SetScript("OnClick", Hl.Click)
	row:SetScript("OnEnter", Hl.Enter)
	row:SetScript("OnLeave", function(self)
		if GameTooltip:IsOwned(self) then
			GameTooltip:Hide()
		end
	end)
	Hl.rows[i] = row
	return row
end

-- The right column's text: the change that put it in the section, coloured.
function Hl.Main(r, key)
	if key == "rise" or key == "fall" then
		local text, color = Ch.Change(r.from, r.price)
		return text and (Ch.Hex(color) .. text .. "|r") or ""
	elseif key == "scarce" then
		return ORANGE .. L["%d%% fewer listed"]:format(r.score) .. "|r"
	elseif key == "flood" then
		return BLUE .. L["%sx as many listed"]:format(LT.Decimal(("%.1f"):format(r.qty / r.usualQty))) .. "|r"
	end
	return GREEN .. L["%d%% under usual"]:format(r.score) .. "|r"
end

-- How many were listed, as the section sees it.
function Hl.Listed(r, key)
	if key == "flood" then
		return L["listed %d (usually %d)"]:format(r.qty, math.floor(r.usualQty + 0.5))
	elseif r.fromQty and r.fromQty > 0 then
		return Ch.ListedChange(nil, { qty = r.fromQty }, { qty = r.qty }) or L["%d listed"]:format(r.qty)
	end
	return L["%d listed"]:format(r.qty)
end

function Hl.Fill(row, r, key, width)
	local Wn, C = W.Window, Hl.C
	row.item, row.r, row.key = r.item, r, key
	row.Icon:SetTexture(Wn.ItemIcon(r.item))
	row.Name:SetText(Wn.ItemName(r.item))
	row.Change:SetText(Hl.Main(r, key))
	row.Price:SetText(Money(r.price))
	local days, _, perDay = Ch.Supply(r.item)
	row.supply, row.perDay = days, perDay
	local sub = { Hl.Listed(r, key) }
	if perDay then
		sub[#sub + 1] = L["sells %s/day"]:format(Ch.PerDay(perDay))
	end
	sub[#sub + 1] = Ch.SupplyLine(days)
	row.Sub:SetText(table.concat(sub, SEP))
	local spark = width >= C.SPARK_MIN
	local text = math.max(60, width - 32 - C.RIGHT_W - (spark and (C.SPARK_W + 12) or 0))
	row.Name:SetWidth(text)
	row.Sub:SetWidth(text)
	row.Spark:SetShown(spark)
	Hl.Spark(row, r, spark)
end

-- The sparkline: the 14 days' lowest prices as a thin line (a Line per day, 13 at most), green up, red down.
function Hl.Spark(row, r, show)
	local C = Hl.C
	local used = 0
	if show then
		local pts = {}
		for _, d in ipairs(r.days) do
			local age = r.today - d[1]
			if age >= 0 and age < Hl.DAYS then
				pts[#pts + 1] = d
			end
		end
		table.sort(pts, function(a, b) return a[1] < b[1] end)
		local lo, hi = math.huge, 0
		for _, d in ipairs(pts) do
			lo, hi = math.min(lo, d[2]), math.max(hi, d[2])
		end
		local _, color = Ch.Change(pts[1] and pts[1][2], pts[#pts] and pts[#pts][2])
		local first = r.today - Hl.DAYS + 1
		local function X(d) return (d[1] - first) / (Hl.DAYS - 1) * C.SPARK_W end
		local function Y(d) return hi > lo and (d[2] - lo) / (hi - lo) * (C.SPARK_H - 2) + 1 or C.SPARK_H / 2 end
		for k = 2, #pts do
			used = used + 1
			local line = row.Lines[used]
			if not line then
				line = row.Spark:CreateLine(nil, "ARTWORK")
				line:SetThickness(1.2)
				row.Lines[used] = line
			end
			line:SetStartPoint("BOTTOMLEFT", row.Spark, X(pts[k - 1]), Y(pts[k - 1]))
			line:SetEndPoint("BOTTOMLEFT", row.Spark, X(pts[k]), Y(pts[k]))
			line:SetColorTexture(color[1], color[2], color[3], 0.9)
			line:Show()
		end
	end
	for k = used + 1, #row.Lines do
		row.Lines[k]:Hide()
	end
	row.sparkLines = used
end

-- The tooltip: the item's, then the numbers.
function Hl.Enter(row)
	local r, key = row.r, row.key
	if not r then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if not pcall(GameTooltip.SetHyperlink, GameTooltip, ("item:%d"):format(r.item)) then
		GameTooltip:SetText(W.Window.ItemName(r.item), 1, 1, 1)
	end
	GameTooltip:AddLine(" ")
	if r.from then
		Ch.Pair(L["Lowest on %s"]:format(Ch.When(r.fromDay * DAY + DAY / 2, "day")), Money(r.from))
		Ch.Pair(L["Lowest on %s"]:format(Ch.When(r.newest * DAY + DAY / 2, "day")), Money(r.price))
		local text, color = Ch.Change(r.from, r.price)
		Ch.Pair(L["Change"], text or "-", color)
	end
	Ch.Pair(L["Lowest now"], Money(r.low) .. " (" .. LT.Ago(r.seen) .. ")")
	Ch.Pair(L["Usual"], Money(r.value))
	Ch.Pair(L["Listed"], Hl.Listed(r, key))
	Ch.Pair(L["Sold a day"], row.perDay and (Ch.PerDay(row.perDay) .. " " .. L["(est.)"]) or L["not known"])
	Ch.Pair(L["Days of supply"], Ch.SupplyText(row.supply) or L["not known"])
	GameTooltip:AddLine(L["Click: the big chart"], 0.6, 0.6, 0.6)
	if W.ItemActions and W.ItemActions.Click then
		GameTooltip:AddLine(L["Right-click: more"], 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

function Hl.Click(row, button)
	if not row.item then
		return
	end
	if (button ~= "LeftButton" or IsShiftKeyDown()) and W.ItemActions and W.ItemActions.Click then
		W.ItemActions.Click(row, row.item, button)
		return
	end
	if button == "LeftButton" then
		GameTooltip:Hide()
		Ch.Open(row.item)
	end
end

-- The page drawn from the answer kept (cheap: the rows in sight only).
function Hl.Draw()
	local p, f = Hl.panel, Ch.dash.frame
	if not (p and f and p:IsShown()) then
		return
	end
	Hl.draws = Hl.draws + 1
	local C = Hl.C
	local span, key, a = Hl.Span(), Hl.Section(), Hl.answer
	for _, b in ipairs(p.Spans) do
		Ch.PaintFlat(b, b.span == span)
	end
	p.Min:SetText(L["Min price: %s"]:format(Money(Hl.Min())))
	for _, b in ipairs(p.Sections) do
		local list = Hl.List(a, b.key, span)
		local n = list and list.n or 0
		b.Text:SetText(b.label .. (n > 0 and (" " .. GREY .. n .. "|r") or ""))
		b:SetWidth(math.floor((b.Text:GetStringWidth() or 60) + 16))
		Ch.PaintFlat(b, b.key == key)
	end
	local width, height = f:GetSize()
	local inner = width - 2 * C.PAD
	p.Desc:SetText(Hl.Describe(key, span))
	p.Desc:SetWidth(math.max(60, inner - 150))
	Hl.Status()
	p.Scroll:ClearAllPoints()
	p.Scroll:SetPoint("TOPLEFT", f, "TOPLEFT", C.PAD, -C.LIST_Y)
	p.Scroll:SetSize(inner - C.BAR, math.max(20, height - C.LIST_Y - C.PAD - 8))
	local rw = inner - C.BAR
	local list = Hl.List(a, key, span) or {}
	local msg = Hl.Empty(a, key, span)
	p.Message:SetShown(msg ~= nil)
	p.Message:SetText(msg and (msg .. ((list.n == 0 and a and a.fresh > 0) and ("\n\n" .. GREY .. L["Only items with a usual price of %s or more."]:format(Money(Hl.Min())) .. " " .. Hl.Filters() .. "|r") or "")) or "")
	p.Message:SetWidth(math.max(60, inner - 16))
	for i, r in ipairs(list) do
		local row = Hl.Row(i)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", p.Child, "TOPLEFT", 0, -(i - 1) * C.ROW_H)
		row:SetSize(rw, C.ROW_H)
		Hl.Fill(row, r, key, rw)
		row:Show()
	end
	for i = #list + 1, #Hl.rows do
		Hl.rows[i]:Hide()
		Hl.rows[i].item, Hl.rows[i].r = nil, nil
	end
	p.Child:SetSize(rw, math.max(1, #list * C.ROW_H))
end
