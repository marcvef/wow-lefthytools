local _, ns = ...
local LT = ns.LT
local L = ns.L
local W = ns.WhyPoor or {}
ns.WhyPoor = W

-- The window (Lodestar's style): Ideas, Bags, Market, the goal's strip (W.Window).
-- docs/whypoor.md has the contract.
--
-- A slim dark frame of our own (LT.Window.Dress, as Lodestar's companion and the Bestiary's windows): along
-- its top "WhyPoor?", the tabs Ideas | Bags | Market and the X; under it the goal's strip, one line ("Mount:
-- 34g of 90g · ~3g/h · at this rate at level 44"; a click shows the goal's details); then a line about
-- what the list shows, the list on the left and the details on the right (never empty: nothing picked,
-- the goal's details).
--   * Ideas: W.Ideas' list as it is (I.Get), each row its title, gold per hour or once (greyed with old
--     prices, "~" where it isn't sure), three dots for its confidence and what it rests on. The details:
--     why, how, the working (each number with what it rests on), the items with their prices and age,
--     what it needs, warnings, and its place on a small zone map (Lodestar's Q.NewMiniMap) with "Show on
--     map" (Lodestar's big map, Q.ShowPlace).
--   * Market: the deals among the ideas (flip, vendorflip, limited, disenchant) and how old the prices are,
--     or "open the auction house".
--   * Bags: W.Bags.List(), the best way to sell each, what the bags would fetch.
-- Opened by /whypoor, the minimap button, the settings and a "WhyPoor?" button on the auction house's
-- window (left of Margins', made when the auction house first opens). Escape closes it and it counts as an open window (LT.Window.Register), as
-- Lodestar's big window; its place and tab are kept (setting window).
-- What it costs: built when first opened. While shown: I.Request() at opening and every TICK seconds,
-- I.Watch's news and money or bag changes noted and drawn on the next frame (a child frame's OnUpdate:
-- hidden, it doesn't run); the list draws only the rows in sight. Closed, nothing of it runs (I.Watch's
-- call only notes that the list is old). Our own frames only: nothing protected (it opens in a fight), no
-- Blizzard menu (gamepad mode); every tab, row, item, the strip and the buttons are plain Buttons the
-- controller's cursor reaches.

local Wn = {}
W.Window = Wn

local NAME = "LefthyToolsWhyPoorFrame"
local C = { W = 780, H = 480, PAD = 6, TOP = 26, GOAL_H = 20, HEAD_H = 18, LIST_W = 300, BAR_W = 22, ROW_H = 32,
	GAP = 8, MAP_W = 240, MAP_H = 160, ITEM_H = 18, TICK = 10, BEYOND = 2, SCREEN = 40 }
local GOLD, GREY, ORANGE, RED, SEP = "|cffffd200", "|cff888888", "|cffff9933", "|cffff4040", " · "
local HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

Wn.TABS = { "ideas", "bags", "market" }
Wn.LABELS = { ideas = L["Ideas"], bags = L["Bags"], market = L["Market"] }
-- Tabs other files add (Wn.AddTab, before the window is built): T = { Entries() -> entries, head, empty;
-- Fill(row, e); Key(e); Enter(row, e) (the row's tooltip); Details(e); Controls(view, shown) (its own controls
-- on the line above the list), headWidth (that line's width while it's shown) }.
Wn.EXTRA = {}

function Wn.AddTab(key, label, T)
	Wn.TABS[#Wn.TABS + 1] = key
	Wn.LABELS[key] = label
	Wn.EXTRA[key] = T
end

-- A tab's key is one of the window's (a page to open on).
function Wn.IsTab(key)
	return Wn.LABELS[key] ~= nil
end
Wn.MARKET = { flip = true, vendorflip = true, limited = true, disenchant = true }
Wn.ICONS = {
	grind = "Interface\\Icons\\Ability_DualWield", gather = "Interface\\Icons\\Trade_Herbalism",
	fish = "Interface\\Icons\\Trade_Fishing", pickpocket = "Interface\\Icons\\INV_Misc_Bag_11",
	quest = "Interface\\Icons\\INV_Misc_Note_01", craft = "Interface\\Icons\\Trade_BlackSmithing",
	flip = "Interface\\Icons\\INV_Misc_Coin_01", vendorflip = "Interface\\Icons\\INV_Misc_Coin_03",
	limited = "Interface\\Icons\\INV_Misc_Note_02", disenchant = "Interface\\Icons\\Trade_Engraving",
	sell = "Interface\\Icons\\INV_Misc_Bag_10", learn = "Interface\\Icons\\INV_Misc_Book_09",
	saving = "Interface\\Icons\\INV_Misc_Coin_02",
}
Wn.state = { tab = "ideas", sel = {}, goal = false, old = true, due = false, draws = 0, requests = 0 }

local function Num(v)
	return type(v) == "number" and not LT.IsSecret(v) and v or nil
end

local function Money(c)
	return W.Money(c) or "-"
end

local function Settings()
	local m = W.module
	if m and m.db then
		m.db.window = type(m.db.window) == "table" and m.db.window or {}
		return m.db.window
	end
	return {}
end

---------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------

-- What a number rests on (contract's basis): short for the rows, long for the details.
function Wn.Basis(basis, long)
	if long then
		return ({ yours = L["your own kills, loot and sales"], prices = L["the auction house's prices"],
			forever = L["WoW: Forever's own data"], classic = L["the classic database (Forever may differ)"],
			estimate = L["an estimate"] })[basis] or ""
	end
	return ({ yours = L["yours"], prices = L["AH prices"], forever = L["Forever's data"], classic = L["classic data"],
		estimate = L["estimate"] })[basis] or ""
end

function Wn.Confidence(c)
	return ({ high = L["high"], medium = L["medium"], low = L["low"] })[c] or ""
end

-- A stretch of play: "40 min", "12 h".
function Wn.Hours(seconds)
	seconds = Num(seconds)
	if not seconds then
		return nil
	end
	if seconds < 5400 then
		return L["%d min"]:format(math.max(1, math.floor(seconds / 60 + 0.5)))
	end
	return L["%d h"]:format(math.floor(seconds / 3600 + 0.5))
end

function Wn.Stale(t)
	local P = W.Prices
	return Num(t) ~= nil and time() - t > ((P and Num(P.STALE)) or 10800)
end

-- An idea's money: "~3g 20s/h", "12g once", grey with old prices; "needs a price" without one.
function Wn.IdeaMoney(idea)
	local tilde = (idea.confidence ~= "high" or idea.basis == "estimate" or idea.basis == "classic") and "~" or ""
	local text
	if Num(idea.perHour) then
		text = tilde .. Money(idea.perHour) .. L["/h"]
	elseif Num(idea.once) then
		text = tilde .. Money(idea.once) .. " " .. L["once"]
	else
		return GREY .. L["needs a price"] .. "|r"
	end
	return Wn.Stale(idea.oldest) and (GREY .. text .. "|r") or text
end

function Wn.ItemName(item)
	local ok, name, _, quality = pcall(C_Item.GetItemInfo, ("item:%d"):format(item))
	if not (ok and type(name) == "string" and not LT.IsSecret(name)) then
		if C_Item.RequestLoadItemDataByID then
			pcall(C_Item.RequestLoadItemDataByID, item)
		end
		return "#" .. item
	end
	local hex = C_Item.GetItemQualityColor and select(4, C_Item.GetItemQualityColor(Num(quality) or 1))
	return type(hex) == "string" and ("|c" .. hex .. name .. "|r") or name
end

function Wn.ItemIcon(item)
	return LT.Value(C_Item.GetItemIconByID, item) or QUESTION
end

---------------------------------------------------------------------------
-- The goal's line (the strip, the minimap button's tooltip)
---------------------------------------------------------------------------

function Wn.GoalLine()
	local G = W.Goal
	if not (G and G.Current) then
		return nil
	end
	local g = G.Current()
	if not g then
		local why = G.Why and G.Why()
		if why == "class" then
			return L["No money goal: your mount comes from a class quest"]
		elseif why == "done" then
			return L["No money goal: you have your riding"]
		end
		return nil
	end
	local parts = { g.name .. ": " .. L["%s of %s"]:format(Money(g.have), (g.about and "~" or "") .. Money(g.cost)) }
	if g.have >= g.cost then
		parts[#parts + 1] = L["you have enough"]
	elseif g.rate and g.rate > 0 then
		parts[#parts + 1] = "~" .. Money(g.rate) .. L["/h"]
		if g.etaLevel then
			parts[#parts + 1] = L["at this rate at level %d"]:format(g.etaLevel)
		elseif g.eta then
			parts[#parts + 1] = L["at this rate in %s played"]:format(Wn.Hours(g.eta * 3600))
		end
	elseif g.rate then
		parts[#parts + 1] = L["not growing lately"]
	end
	return table.concat(parts, SEP)
end

---------------------------------------------------------------------------
-- The list: only the rows in sight (Lodestar's pattern; entry i always on row (i - 1) % pool + 1, so the
-- controller's cursor stays on its entry while the list scrolls under it)
---------------------------------------------------------------------------

function Wn.NewList(parent, x, y, width, height, newRow, fillRow)
	local rowH = C.ROW_H
	local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", x, -y)
	scroll:SetSize(width, height)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(width, 1)
	scroll:SetScrollChild(child)
	local sight = math.ceil(height / rowH) + 1
	local list = { scroll = scroll, child = child, rows = {}, entries = {}, first = 1, pool = sight + 2 * C.BEYOND, sight = sight,
		fills = 0 }

	function list:Lay(offset)
		local top = math.max(0, math.floor((offset or scroll:GetVerticalScroll() or 0) / rowH))
		self.first = top + 1
		local from, to = math.max(1, top + 1 - C.BEYOND), math.min(#self.entries, top + sight + C.BEYOND)
		for i = from, to do
			local k = (i - 1) % self.pool + 1
			local row = self.rows[k]
			if not row then
				row = newRow(child, width)
				self.rows[k] = row
			end
			if row.index ~= i then
				row.index = i
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
			end
			row.entry = self.entries[i]
			self.fills = self.fills + 1
			fillRow(row, row.entry)
			row:Show()
		end
		for k = 1, self.pool do
			local row = self.rows[k]
			if row and not (row.index and row.index >= from and row.index <= to) then
				row.entry, row.index = nil, nil
				row:Hide()
			end
		end
	end

	-- New entries; keep: stay where it was (as far as it still goes).
	function list:SetEntries(entries, keep)
		self.entries = entries
		local total = #entries * rowH
		child:SetHeight(math.max(1, total))
		local want = keep and (scroll:GetVerticalScroll() or 0) or 0
		want = math.max(0, math.min(want, total - height))
		scroll:SetVerticalScroll(want)
		for _, row in pairs(self.rows) do
			row.index = nil
		end
		self:Lay(want)
	end

	scroll:HookScript("OnVerticalScroll", function(_, offset)
		if math.floor((offset or 0) / rowH) + 1 ~= list.first then
			list:Lay(offset)
		end
	end)
	return list
end

local function Untip(self)
	if GameTooltip:IsOwned(self) then
		GameTooltip:Hide()
	end
end

function Wn.RowEnter(self)
	local e = self.entry
	if not e then
		return
	end
	local T = Wn.EXTRA[Wn.state.tab]
	if T then
		T.Enter(self, e)
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if Wn.state.tab == "bags" then
		if e.link and GameTooltip.SetHyperlink then
			GameTooltip:SetHyperlink(e.link)
		else
			GameTooltip:SetText(Wn.ItemName(e.item), 1, 1, 1)
		end
	else
		GameTooltip:SetText(e.title or "", 1, 0.82, 0)
		if e.confidence then
			GameTooltip:AddLine(L["Confidence: %s · rests on: %s"]:format(Wn.Confidence(e.confidence), Wn.Basis(e.basis, true)), 1, 1, 1, true)
		end
	end
	GameTooltip:AddLine(L["Click: its details"], 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

function Wn.NewRow(parent, width)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, C.ROW_H - 2)
	b:SetHighlightTexture(HIGHLIGHT, "ADD")
	b.Sel = b:CreateTexture(nil, "BACKGROUND")
	b.Sel:SetAllPoints()
	b.Sel:SetColorTexture(1, 0.82, 0, 0.12)
	b.Icon = b:CreateTexture(nil, "ARTWORK")
	b.Icon:SetSize(24, 24)
	b.Icon:SetPoint("LEFT", 2, 0)
	b.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.Money = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.Money:SetPoint("TOPRIGHT", -4, -3)
	b.Money:SetJustifyH("RIGHT")
	b.Title = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.Title:SetPoint("TOPLEFT", 31, -3)
	b.Title:SetPoint("RIGHT", b.Money, "LEFT", -6, 0)
	b.Title:SetJustifyH("LEFT")
	b.Title:SetWordWrap(false)
	b.Dots = {}
	for i = 1, 3 do
		local dot = b:CreateTexture(nil, "ARTWORK")
		dot:SetSize(5, 5)
		dot:SetPoint("BOTTOMRIGHT", -4 - (3 - i) * 7, 6)
		b.Dots[i] = dot
	end
	b.Sub = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	b.Sub:SetPoint("BOTTOMLEFT", 31, 3)
	b.Sub:SetPoint("RIGHT", -28, 0)
	b.Sub:SetJustifyH("LEFT")
	b.Sub:SetWordWrap(false)
	b:SetScript("OnClick", function(self)
		Untip(self)
		if self.entry then
			Wn.Pick(self.entry)
		end
	end)
	b:SetScript("OnEnter", Wn.RowEnter)
	b:SetScript("OnLeave", Untip)
	return b
end

local DOT_COLORS = { high = { 3, 0.3, 0.85, 0.3 }, medium = { 2, 1, 0.82, 0 }, low = { 1, 1, 0.5, 0.2 } }

function Wn.FillRow(row, e)
	local state = Wn.state
	local T = Wn.EXTRA[state.tab]
	if T then
		T.Fill(row, e)
	elseif state.tab == "bags" then
		row.Icon:SetTexture(Wn.ItemIcon(e.item))
		row.Title:SetText(Wn.ItemName(e.item) .. (e.count > 1 and (GREY .. " x" .. e.count .. "|r") or ""))
		if e.best then
			local how = e.best == "ah" and L["AH"] or L["vendor"]
			local text = Money(e.value) .. " " .. GREY .. how .. "|r"
			row.Money:SetText((e.keep or (e.best == "ah" and e.price and Wn.Stale(e.price.seen))) and (GREY .. Money(e.value) .. " " .. how .. "|r") or text)
		else
			row.Money:SetText(GREY .. "-|r")
		end
		row.Sub:SetText(e.keep and (ORANGE .. L["keep: %s"]:format(e.keep) .. "|r")
			or e.bound and L["soulbound"] or (not e.best and L["no price known"]) or "")
		for _, dot in ipairs(row.Dots) do
			dot:Hide()
		end
	else
		row.Icon:SetTexture(e.icon or Wn.ICONS[e.kind] or QUESTION)
		row.Title:SetText(e.title or "")
		row.Money:SetText(Wn.IdeaMoney(e))
		local basis = Wn.Basis(e.basis)
		row.Sub:SetText(e.sub and e.sub ~= "" and (basis ~= "" and (basis .. SEP .. e.sub) or e.sub) or basis)
		local look = DOT_COLORS[e.confidence]
		for i, dot in ipairs(row.Dots) do
			dot:Show()
			if look and i <= look[1] then
				dot:SetColorTexture(look[2], look[3], look[4], 1)
			else
				dot:SetColorTexture(1, 1, 1, 0.15)
			end
		end
	end
	row.Sel:SetShown(not state.goal and state.sel[state.tab] == Wn.Key(e))
end

-- An entry's key in its list (the pick stays on it when the list changes).
function Wn.Key(e)
	local T = Wn.EXTRA[Wn.state.tab]
	if T then
		return T.Key(e)
	elseif Wn.state.tab == "bags" then
		return e.item .. (e.bound and ":b" or "")
	end
	return e.key
end

---------------------------------------------------------------------------
-- The details (pooled lines, item rows, the small map, a button)
---------------------------------------------------------------------------

local D = { texts = {}, items = {}, y = 0, n = 0, ni = 0 }
Wn.D = D

function D.Begin()
	D.y, D.n, D.ni, D.nb = 4, 0, 0, 0
	if D.graph then
		D.graph:Hide()
	end
	if D.inputs then
		D.inputs.Amount:Hide()
		D.inputs.Name:Hide()
		D.inputs.AmountLabel:Hide()
		D.inputs.NameLabel:Hide()
	end
	if D.barInputs then
		D.barInputs.Amount:Hide()
		D.barInputs.Label:Hide()
	end
	if D.map then
		D.map:Hide()
	end
	D.MapButton:Hide()
end

-- A line: font ("head", "title", "text", "small"), its colour code in text.
function D.Text(text, font, indent, gap)
	if not text or text == "" then
		return
	end
	D.n = D.n + 1
	local fs = D.texts[D.n]
	if not fs then
		fs = D.child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetJustifyH("LEFT")
		fs:SetJustifyV("TOP")
		D.texts[D.n] = fs
	end
	local name = font == "title" and "GameFontNormal" or font == "head" and "GameFontNormalSmall"
		or font == "small" and "GameFontDisableSmall" or "GameFontHighlightSmall"
	fs:SetFontObject(_G[name] or name)
	D.y = D.y + (gap or 0)
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", 4 + (indent or 0), -D.y)
	fs:SetWidth(D.width - 8 - (indent or 0))
	fs:SetText(text)
	fs:Show()
	D.y = D.y + math.max(12, fs:GetStringHeight() or 12) + 2
	return fs
end

function D.Head(text)
	return D.Text(text, "head", 0, 6)
end

function D.ItemEnter(self)
	if not self.item then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	if GameTooltip.SetHyperlink then
		GameTooltip:SetHyperlink(("item:%d"):format(self.item))
	end
	GameTooltip:Show()
end

-- An item's row: its icon and name (x n), at its right what's said of it; enter: its own tooltip (else the
-- item's), data: kept on the row for it (row.data).
function D.Item(item, n, right, enter, data)
	D.ni = D.ni + 1
	local b = D.items[D.ni]
	if not b then
		b = CreateFrame("Button", nil, D.child)
		b:SetHeight(C.ITEM_H)
		b:SetHighlightTexture(HIGHLIGHT, "ADD")
		b.Icon = b:CreateTexture(nil, "ARTWORK")
		b.Icon:SetSize(C.ITEM_H - 2, C.ITEM_H - 2)
		b.Icon:SetPoint("LEFT", 1, 0)
		b.Right = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.Right:SetPoint("RIGHT", -2, 0)
		b.Right:SetJustifyH("RIGHT")
		b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.Text:SetPoint("LEFT", C.ITEM_H + 3, 0)
		b.Text:SetPoint("RIGHT", b.Right, "LEFT", -4, 0)
		b.Text:SetJustifyH("LEFT")
		b.Text:SetWordWrap(false)
		b:SetScript("OnEnter", D.ItemEnter)
		b:SetScript("OnLeave", Untip)
		D.items[D.ni] = b
	end
	b.item, b.data = item, data
	b:SetScript("OnEnter", enter or D.ItemEnter)
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", 4, -D.y)
	b:SetWidth(D.width - 8)
	b.Icon:SetTexture(Wn.ItemIcon(item))
	b.Text:SetText(Wn.ItemName(item) .. ((Num(n) and n > 1) and (GREY .. " x" .. n .. "|r") or ""))
	b.Right:SetText(right or "")
	b:Show()
	D.y = D.y + C.ITEM_H + 1
	return b
end

-- An item's price on this auction house as a small chart (W.Chart's widget): its line over the last GRAPH_DAYS days
-- (from its first price in them), green up, red down, the usual price as a gold line, the lowest and highest at the
-- right, the first and last day below; a hover shows each point, a click opens the big chart (W.Chart.Open). Under it
-- the daily lows' lowest, highest, the usual price and whether it's steady. Fewer than two prices: says so.
D.GRAPH_H, D.GRAPH_DAYS = 92, 30
function D.Graph(item)
	local P, Ch = W.Prices, W.Chart
	if not (P and P.History and Num(item)) then
		return
	end
	local list, value, unstable = P.History(item)
	local get = P.Get and P.Get(item)
	value = Num(value) or (type(get) == "table" and Num(get.value)) or nil
	D.Head(L["Price on your auction house"])
	local now = time()
	local points, res = {}, "day"
	if Ch then
		points, res = Ch.Points(item, now - D.GRAPH_DAYS * 86400, now)
	end
	if #points < 2 then
		D.Text(GREY .. ((#points == 1 or #list == 1) and L["One day of prices so far: a few more days show whether it's steady."]
			or L["No prices yet: open the auction house."]) .. "|r", "small", 4)
		return
	end
	local w = D.chart
	if not w then
		w = Ch.NewWidget(D.child, { mini = true, onClick = function(self) Ch.Open(self.item) end })
		w.pools.dot = { list = {}, n = 0 }
		D.chart, D.graph = w, w.frame
		D.graph.bars = w.pools.dot.list -- (a dot per price while there are few: the Stocks tab's tests count them)
	end
	w.item = item
	w.frame:ClearAllPoints()
	w.frame:SetPoint("TOPLEFT", 4, -D.y)
	w.frame:Show()
	w:SetSize(D.width - 8, D.GRAPH_H)
	local from = points[1].t - math.max(60, (now - points[1].t) * 0.03)
	w:SetSeries(points, from, now, res, { usual = Num(value), empty = "", volume = true })
	D.y = D.y + D.GRAPH_H + 3
	if #list > 0 then
		local low, high = math.huge, 0
		for _, d in ipairs(list) do
			low, high = math.min(low, d.low), math.max(high, d.low)
		end
		D.Text(L["%d days: lowest %s, highest %s, usually %s"]:format(#list, Money(low), Money(high), Money(value))
			.. SEP .. (unstable and (ORANGE .. L["jumps around"] .. "|r") or L["steady"]), "small", 4)
	end
	local listed = Ch.ListedChange and Ch.ListedChange(points)
	if listed then
		D.Text(L["Bars below: how many were listed. %s"]:format(listed), "small", 4)
	end
	D.Text(GREY .. L["Click the graph: the big chart, with longer ranges."] .. "|r", "small", 4)
end

-- A place on the small map ({ map, name, points = { { x, y, r } } }) and "Show on map".
function D.Place(place)
	local Q = ns.Lodestar
	if not (type(place) == "table" and Num(place.map) and type(place.points) == "table" and place.points[1]) then
		return
	end
	if not D.map and Q and Q.NewMiniMap then
		D.map = Q.NewMiniMap(D.child, C.MAP_W, C.MAP_H)
	end
	if not D.map then
		return
	end
	local points = {}
	for i, p in ipairs(place.points) do
		if Num(p.x) and Num(p.y) then
			points[#points + 1] = { x = p.x, y = p.y, kind = "area", radius = Num(p.r) or 0.02, group = i, label = place.name }
		end
	end
	if not points[1] then
		return
	end
	D.Head(place.name or L["Where"])
	D.map.frame:ClearAllPoints()
	D.map.frame:SetPoint("TOPLEFT", 4, -D.y)
	D.map:Show(place.map, points, place.name)
	D.y = D.y + C.MAP_H + 4
	D.place = place
	if Q.ShowPlace then
		D.MapButton:ClearAllPoints()
		D.MapButton:SetPoint("TOPLEFT", 4, -D.y)
		D.MapButton:Show()
		D.y = D.y + 24
	end
end

-- A button in the details (pooled): its label, what a click does, whether it can be clicked; two may share a
-- line (second = true: right of the one before).
D.buttons = {}
function D.Button(label, onClick, enabled, width, second)
	D.nb = D.nb + 1
	local b = D.buttons[D.nb]
	if not b then
		b = CreateFrame("Button", nil, D.child, "UIPanelButtonTemplate")
		b:SetHeight(20)
		b:SetScript("OnClick", function(self)
			if self.onClick then
				self.onClick()
			end
		end)
		D.buttons[D.nb] = b
	end
	b:SetText(label)
	b:SetWidth(width or 120)
	b.onClick = onClick
	b:SetEnabled(enabled ~= false)
	b:ClearAllPoints()
	local before = second and D.buttons[D.nb - 1]
	if before then
		b:SetPoint("LEFT", before, "RIGHT", 6, 0)
	else
		b:SetPoint("TOPLEFT", 4, -D.y)
		D.y = D.y + 24
	end
	b:Show()
	return b
end

function D.End()
	for i = D.nb + 1, #D.buttons do
		D.buttons[i]:Hide()
		D.buttons[i].onClick = nil
	end
	for i = D.n + 1, #D.texts do
		D.texts[i]:Hide()
	end
	for i = D.ni + 1, #D.items do
		D.items[i]:Hide()
		D.items[i].item = nil
	end
	D.child:SetHeight(math.max(1, D.y + 4))
end

function D.Idea(idea)
	D.Text(idea.title, "title")
	D.Text(idea.sub, "small")
	D.Text(Wn.IdeaMoney(idea), "title", 0, 2)
	D.Text(L["Confidence: %s · rests on: %s"]:format(Wn.Confidence(idea.confidence), Wn.Basis(idea.basis, true)), "small")
	if type(idea.needs) == "table" and idea.needs[1] then
		D.Text(RED .. L["Needs: %s"]:format(table.concat(idea.needs, ", ")) .. "|r", "text", 0, 2)
	elseif type(idea.needs) == "string" and idea.needs ~= "" then
		D.Text(RED .. L["Needs: %s"]:format(idea.needs) .. "|r", "text", 0, 2)
	end
	for _, line in ipairs(type(idea.warnings) == "table" and idea.warnings or {}) do
		D.Text(ORANGE .. tostring(line) .. "|r", "text")
	end
	if type(idea.why) == "table" and idea.why[1] then
		D.Head(L["Why"])
		for _, line in ipairs(idea.why) do
			D.Text("- " .. tostring(line), "text", 4)
		end
	end
	if type(idea.how) == "table" and idea.how[1] then
		D.Head(L["How"])
		for _, line in ipairs(idea.how) do
			D.Text("- " .. tostring(line), "text", 4)
		end
	end
	if type(idea.numbers) == "table" and idea.numbers[1] then
		D.Head(L["The working"])
		for _, n in ipairs(idea.numbers) do
			if type(n) == "table" then
				local basis = Wn.Basis(n.basis)
				D.Text(tostring(n.label or "") .. ": " .. (n.value ~= nil and tostring(n.value) or "-")
					.. (basis ~= "" and (GREY .. " (" .. basis .. ")|r") or ""), "text", 4)
			end
		end
	end
	if type(idea.items) == "table" and idea.items[1] then
		D.Head(L["Items"])
		local sources = { ah = L["AH"], vendor = L["vendor"], drop = L["drops"], craft = L["crafted"], bags = L["in your bags"] }
		for _, it in ipairs(idea.items) do
			if type(it) == "table" and Num(it.item) then
				local right = Num(it.each) and Money(it.each) or ""
				local source = sources[it.source]
				if source then
					right = right .. (right ~= "" and " " or "") .. GREY .. source .. "|r"
				end
				if Num(it.age) then
					local age = W.Age(it.age)
					right = right .. " " .. (Wn.Stale(it.age) and ORANGE or GREY) .. age .. "|r"
				end
				D.Item(it.item, it.n, right)
			end
		end
	end
	if idea.star then
		D.Graph(idea.star)
	end
	D.Place(idea.place)
end

function D.Bag(e)
	D.Text(Wn.ItemName(e.item) .. (e.count > 1 and (GREY .. " x" .. e.count .. "|r") or ""), "title")
	if e.best == "ah" then
		D.Text(L["Best at the auction house: %s"]:format(Money(e.value)), "text", 0, 2)
	elseif e.best == "vendor" then
		D.Text(L["Best at a vendor: %s"]:format(Money(e.value)), "text", 0, 2)
	else
		D.Text(GREY .. L["No price known: open the auction house"] .. "|r", "text", 0, 2)
	end
	if e.keep then
		D.Text(ORANGE .. L["Keep it: %s"]:format(e.keep) .. "|r", "text")
	end
	D.Head(L["Auction house"])
	if e.bound then
		D.Text(L["Soulbound: it can't be auctioned"], "text", 4)
	elseif e.ah then
		D.Text(L["%s for all, after the cut and lost deposits"]:format(Money(e.ah))
			.. (Num(e.unit) and (GREY .. " (" .. L["%s each"]:format(Money(e.unit)) .. ")|r") or ""), "text", 4)
		local p = type(e.price) == "table" and e.price or {}
		local notes = {}
		if Num(p.seen) then
			notes[#notes + 1] = (Wn.Stale(p.seen) and ORANGE or "") .. L["price %s old"]:format(W.Age(p.seen)) .. "|r"
		end
		if p.friend then
			notes[#notes + 1] = L["from %s"]:format(tostring(p.friend))
		end
		if Num(p.sells) then
			notes[#notes + 1] = L["sells: %d%%"]:format(math.floor(p.sells * 100 + 0.5))
		end
		if p.confidence then
			notes[#notes + 1] = L["confidence: %s"]:format(Wn.Confidence(p.confidence))
		end
		if p.unstable then
			notes[#notes + 1] = L["jumps around"]
		end
		D.Text(table.concat(notes, SEP), "small", 4)
	else
		D.Text(GREY .. L["No price: open the auction house"] .. "|r", "text", 4)
	end
	D.Head(L["Vendor"])
	if e.vendor and e.vendor > 0 then
		D.Text(L["%s for all"]:format(Money(e.vendor)), "text", 4)
	elseif e.vendor == 0 then
		D.Text(L["Vendors don't buy it"], "text", 4)
	else
		D.Text(GREY .. L["Not known yet"] .. "|r", "text", 4)
	end
	D.Item(e.item, e.count, nil)
	if not e.bound then
		D.Graph(e.item)
	end
end

-- Your own goal's fields: an amount in gold and a name, then Set (and Clear when there is one).
function D.GoalInputs()
	local G = W.Goal
	if not D.inputs then
		local i = {}
		i.AmountLabel = D.child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		i.AmountLabel:SetText(L["Gold"])
		i.Amount = CreateFrame("EditBox", nil, D.child, "InputBoxTemplate")
		i.Amount:SetSize(60, 20)
		i.Amount:SetAutoFocus(false)
		i.Amount:SetMaxLetters(7)
		i.NameLabel = D.child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		i.NameLabel:SetText(L["Name"])
		i.Name = CreateFrame("EditBox", nil, D.child, "InputBoxTemplate")
		i.Name:SetSize(150, 20)
		i.Name:SetAutoFocus(false)
		i.Name:SetMaxLetters(40)
		for _, box in ipairs({ i.Amount, i.Name }) do
			box:SetScript("OnEscapePressed", box.ClearFocus)
			box:SetScript("OnEnterPressed", function() D.SetGoal() end)
			box:SetScript("OnTextChanged", function(_, byUser)
				if byUser then
					i.typed = true -- (what's typed stays through the window's redraws until Set or Clear)
				end
			end)
		end
		D.inputs = i
	end
	local i = D.inputs
	local custom = G and G.Custom and G.Custom()
	if not i.typed then
		i.Amount:SetText(custom and tostring(math.floor(custom.cost / 10000 + 0.5)) or "")
		i.Name:SetText(custom and custom.name or "")
	end
	i.AmountLabel:ClearAllPoints()
	i.AmountLabel:SetPoint("TOPLEFT", 8, -D.y - 4)
	i.Amount:ClearAllPoints()
	i.Amount:SetPoint("LEFT", i.AmountLabel, "RIGHT", 10, 0)
	i.NameLabel:ClearAllPoints()
	i.NameLabel:SetPoint("LEFT", i.Amount, "RIGHT", 10, 0)
	i.Name:ClearAllPoints()
	i.Name:SetPoint("LEFT", i.NameLabel, "RIGHT", 10, 0)
	for _, part in ipairs({ i.AmountLabel, i.Amount, i.NameLabel, i.Name }) do
		part:Show()
	end
	D.y = D.y + 26
	D.Button(L["Set"], D.SetGoal, true, 80)
	if custom then
		D.Button(L["Clear"], function()
			G.SetCustom(nil)
			i.typed, i.problem = false, nil
			LT.Print("WhyPoor?: your own goal cleared.")
			Wn.state.goal = true
			Wn.Draw()
		end, true, 80, true)
	end
	if i.problem then
		D.Text(ORANGE .. i.problem .. "|r", "small", 4)
	end
end

-- What's in the fields, kept as your goal (gold; "1,5" or "1.5" both work).
function D.SetGoal()
	local i, G = D.inputs, W.Goal
	if not (i and G and G.SetCustom) then
		return
	end
	-- "150", "150g", "1,5", " 2.5 g": the number in it, in gold.
	local text = (i.Amount:GetText() or ""):gsub(",", "."):gsub("[^%d%.]", "")
	local gold = tonumber(text)
	i.Amount:ClearFocus()
	i.Name:ClearFocus()
	if gold and gold > 0 and G.SetCustom(gold * 10000, i.Name:GetText()) then
		i.typed, i.problem = false, nil
		local name = strtrim(i.Name:GetText() or "")
		LT.Print(("WhyPoor?: goal set: %s, %s."):format(name ~= "" and name or "your goal", W.Money(gold * 10000)))
	elseif gold and gold > 0 then
		i.problem = L["The goal couldn't be kept yet: try again in a moment."]
	else
		i.problem = L["Type the gold as a number, like 150."]
	end
	Wn.state.goal = true
	Wn.Draw()
end

function D.Goal()
	local G = W.Goal
	local g = G and G.Current and G.Current()
	D.Text(L["Your money goal"], "title")
	if not g then
		local why = G and G.Why and G.Why()
		D.Text(why == "class" and L["Paladins and Warlocks get their mounts from class quests, so there's no riding to save for here."]
			or why == "done" and L["You have Journeyman Riding: no mount to save for."]
			or L["No goal right now."], "text", 0, 2)
		D.Head(L["Set your own goal"])
		D.GoalInputs()
		D.Bar()
		return
	end
	D.Text(g.name .. (g.level and (GREY .. " (" .. L["level %d"]:format(g.level) .. ")|r") or ""), "text", 0, 2)
	if g.custom then
		D.Text(L["Your own goal: %s"]:format(Money(g.cost)), "text")
	elseif g.about then
		D.Text(L["Costs about %s: what guides say for WoW: Forever (10%% less at Honored with your home city). Talk to a riding trainer and WhyPoor? takes the real price."]:format(Money(g.cost)), "text")
	else
		D.Text(L["Costs %s: the riding trainer's price, seen %s ago."]:format(Money(g.cost), W.Age(g.seen) or "?"), "text")
	end
	if g.spell == G.APPRENTICE then
		D.Text(GREY .. L["Guides say the first mount comes with Apprentice Riding; more mounts cost 20g each at your race's vendor (Forever's item data, before discounts)."] .. "|r", "small")
	elseif g.spell == G.JOURNEYMAN then
		D.Text(GREY .. L["An epic mount costs 200g at your race's vendor (Forever's item data, before discounts), if it doesn't come with Journeyman Riding."] .. "|r", "small")
	end
	D.Head(L["Where you are"])
	D.Text(L["You have %s"]:format(Money(g.have)), "text", 4)
	if g.bags and g.bags > 0 then
		D.Text(L["Your bags would fetch about %s more"]:format(Money(g.bags)), "text", 4)
	end
	if g.have >= g.cost then
		D.Text(L["You have enough: off to the riding trainer!"], "text", 4)
	else
		D.Text(L["Still to go: %s"]:format(Money(g.cost - g.have)), "text", 4)
	end
	D.Head(L["Your pace"])
	if g.rate then
		local span = Wn.Hours(g.played)
		if g.rate > 0 then
			D.Text(L["Your gold grows ~%s per hour played (net, over your last %s played)"]:format(Money(g.rate), span), "text", 4)
		else
			D.Text(L["Your gold went down lately: %s per hour played (net, over your last %s played)"]:format(Money(g.rate), span), "text", 4)
		end
		if g.eta then
			D.Text(L["At this rate you have it in ~%s played"]:format(Wn.Hours(g.eta * 3600))
				.. (g.etaLevel and (", " .. L["around level %d"]:format(g.etaLevel)) or ""), "text", 4)
		end
		D.Text(L["From Chronicle: your gold and time played."], "small", 4)
	else
		D.Text(GREY .. L["Not enough play recorded yet (Chronicle) for a gold rate."] .. "|r", "text", 4)
	end
	if g.mounts and g.mounts[1] then
		D.Head(L["Mounts seen at vendors"])
		for i, m in ipairs(g.mounts) do
			if i > 5 then
				break
			end
			D.Item(m.item, 1, Money(m.price) .. " " .. GREY .. (W.Age(m.seen) or "") .. "|r")
		end
	end
	D.Head(g.custom and L["Change your goal"] or L["Set your own goal"])
	D.GoalInputs()
	D.Bar()
end

-- The bar's line: what it is and where it comes from.
function Wn.BarLine(bar)
	local money = Money(bar.hour)
	if bar.how == "own" then
		return L["The bar: %s an hour, your own."]:format(money)
	elseif bar.how == "rate" then
		return L["The bar: %s an hour, half again the %s you earn an hour playing (Chronicle)."]:format(money, Money(bar.rate))
	elseif bar.how == "least" then
		return L["The bar: %s an hour, the least for your level (you earn %s an hour playing, Chronicle)."]:format(money, Money(bar.rate))
	elseif bar.how == "spent" then
		return L["The bar: %s an hour, by your level (your gold went down lately, Chronicle)."]:format(money)
	end
	return L["The bar: %s an hour, by your level (Chronicle doesn't know what you earn playing yet)."]:format(money)
end

-- The bar, at the end of the goal's details (under your own goal's fields): what it is, and your own.
function D.Bar()
	local I = W.Ideas
	local bar = I and I.Bar and I.Bar()
	if type(bar) ~= "table" then
		return
	end
	D.Head(L["The bar for ideas"])
	D.Text(L["Ideas lists only what brings at least this, so it's worth more than playing normally."], "small", 4)
	D.Text(Wn.BarLine(bar), "text", 4)
	D.Text(L["A one-off (a flip, a craft) must bring half an hour's worth: %s."]:format(Money(bar.once)), "small", 4)
	local i = D.barInputs
	if not i then
		i = {}
		i.Label = D.child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		i.Label:SetText(L["Gold an hour"])
		i.Amount = CreateFrame("EditBox", nil, D.child, "InputBoxTemplate")
		i.Amount:SetSize(60, 20)
		i.Amount:SetAutoFocus(false)
		i.Amount:SetMaxLetters(7)
		i.Amount:SetScript("OnEscapePressed", i.Amount.ClearFocus)
		i.Amount:SetScript("OnEnterPressed", function() D.SetBar() end)
		i.Amount:SetScript("OnTextChanged", function(_, byUser)
			if byUser then
				i.typed = true -- (what's typed stays through the window's redraws until Set or Clear)
			end
		end)
		D.barInputs = i
	end
	if not i.typed then
		i.Amount:SetText(bar.how == "own" and (("%.2f"):format(bar.hour / 10000):gsub("%.?0+$", "")) or "")
	end
	i.Label:ClearAllPoints()
	i.Label:SetPoint("TOPLEFT", 8, -D.y - 4)
	i.Amount:ClearAllPoints()
	i.Amount:SetPoint("LEFT", i.Label, "RIGHT", 10, 0)
	i.Label:Show()
	i.Amount:Show()
	D.y = D.y + 26
	D.Button(L["Set"], D.SetBar, true, 80)
	if bar.how == "own" then
		D.Button(L["Automatic"], function()
			W.Goal.SetBar(nil)
			i.typed, i.problem = false, nil
			LT.Print("WhyPoor?: the bar is automatic again.")
			D.BarChanged()
		end, true, 100, true)
	end
	if i.problem then
		D.Text(ORANGE .. i.problem .. "|r", "small", 4)
	end
	D.Text(L["Or type /whypoor bar 1.5 (/whypoor bar auto: back to automatic)."], "small", 0, 4)
end

-- What's in the bar's field, kept as your own bar (gold an hour; "1,5", "1.5g" work).
function D.SetBar()
	local i, G = D.barInputs, W.Goal
	if not (i and G and G.SetBar) then
		return
	end
	local gold = tonumber(((i.Amount:GetText() or ""):gsub(",", "."):gsub("[^%d%.]", "")))
	i.Amount:ClearFocus()
	if gold and gold > 0 and G.SetBar(gold * 10000) then
		i.typed, i.problem = false, nil
		LT.Print(("WhyPoor?: bar set: %s an hour."):format(W.Money(gold * 10000)))
		D.BarChanged()
		return
	elseif gold and gold > 0 then
		i.problem = L["The bar couldn't be kept yet: try again in a moment."]
	else
		i.problem = L["Type the gold as a number, like 1.5."]
	end
	Wn.Draw()
end

-- The bar changed: the ideas worked out again, the window drawn.
function D.BarChanged()
	local I = W.Ideas
	if I and I.BarChanged then
		I.BarChanged()
	end
	Wn.Draw()
end

-- The goal's details on the right, where the bar is set too (the line above the Ideas list, its message).
function Wn.ShowBar()
	local state = Wn.state
	state.goal = true
	if Wn.view then
		Wn.view.list:Lay()
		Wn.DrawDetails()
	end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

-- What's being worked on, for the line above the list: the auction house scan (asking, reading, keeping), the
-- ideas' run (step of steps), a run that failed. nil: nothing.
function Wn.ScanLine()
	local P = W.Prices
	local s = P and P.Status and P.Status()
	if type(s) ~= "table" or not s.running then
		return nil
	end
	if s.kind == "replicate" then
		if s.waiting then
			return L["Asking the auction house for all its listings..."]
		elseif s.committing then
			return L["Keeping the auction house's prices..."]
		end
		local total = Num(s.total) or 0
		return L["Reading the auction house: %d%%"]:format(total > 0 and math.floor((Num(s.done) or 0) * 100 / total) or 0)
	end
	return L["Checking prices: %d of %d"]:format(Num(s.done) or 0, Num(s.total) or 0)
end

function Wn.WorkLine()
	local I = W.Ideas
	if not (I and I.Progress) then
		return nil
	end
	local p, failed = I.Progress()
	if type(p) == "table" then
		return L["Working them out: step %d of %d"]:format(p.step, p.steps)
	elseif failed then
		return ORANGE .. L["Working them out failed: /lefthy errors shows why"] .. "|r"
	end
end

-- The Ideas tab without an idea: an honest answer, and why.
function Wn.NothingWorth()
	local I = W.Ideas
	local hidden = I and I.Hidden and I.Hidden()
	local lines = { L["Nothing worth extra time right now: playing normally pays as well. Keep playing; open the auction house now and then."] }
	local bar = I and I.Bar and I.Bar()
	if type(bar) == "table" then
		lines[#lines + 1] = Wn.BarLine(bar) .. " " .. L["Click to change it."]
	end
	if type(hidden) == "table" and (hidden.young or 0) > 0 then
		lines[#lines + 1] = L["%d more may count once their auction house prices are a few days old."]:format(hidden.young)
	end
	return table.concat(lines, "\n\n")
end

-- The list's entries for the tab, the line above it, the message when it's empty.
function Wn.Entries(tab)
	local P, I = W.Prices, W.Ideas
	local T = Wn.EXTRA[tab]
	if T then
		return T.Entries()
	elseif tab == "bags" then
		if not (W.Bags and W.Bags.List) then
			return {}, "", L["Nothing in your bags to sell."]
		end
		local list, total = W.Bags.List()
		return list, L["Your bags would fetch %s"]:format(Money(total)), L["Nothing in your bags to sell."]
	end
	if not (I and I.Get) then
		return {}, "", L["The ideas aren't there in this build."]
	end
	local list, ready = I.Get()
	list = type(list) == "table" and list or {}
	if tab == "market" then
		local deals = {}
		for _, idea in ipairs(list) do
			if Wn.MARKET[idea.kind] then
				deals[#deals + 1] = idea
			end
		end
		local last = P and P.LastScan and Num(P.LastScan())
		local head = Wn.ScanLine() or Wn.WorkLine() -- (what's going on first)
		if head == nil and P and P.IsOpen and P.IsOpen() then
			local s = P.Status and P.Status()
			local nextFull = type(s) == "table" and Num(s.nextFull)
			if nextFull and nextFull > time() then
				head = L["The auction house is open · next whole scan in %d min"]:format(math.ceil((nextFull - time()) / 60))
			else
				head = L["The auction house is open"]
			end
		elseif head == nil and last then
			head = (Wn.Stale(last) and ORANGE or "") .. L["Auction house prices from %s ago"]:format(W.Age(last)) .. "|r"
		elseif head == nil then
			head = ORANGE .. L["No auction house prices yet: open the auction house"] .. "|r"
		end
		local empty = not ready and (Wn.WorkLine() or L["Working them out..."])
			or last and L["No deals in the auction house's prices right now."]
			or L["Open the auction house: its prices show the deals."]
		return deals, head, empty
	end
	local work = Wn.WorkLine()
	local bar = I.Bar and I.Bar()
	local worth = L["%d worth your time"]:format(#list)
		.. (type(bar) == "table" and (SEP .. L["bar %s an hour"]:format(Money(bar.hour))) or "")
	local head = ready and worth
		or #list > 0 and work and worth .. SEP .. work
		or work or L["Working them out..."]
	local empty = not ready and (work or L["Working them out..."]) or Wn.NothingWorth()
	return list, head, empty
end

function Wn.DrawDetails()
	local state, view = Wn.state, Wn.view
	D.Begin()
	local e
	if not state.goal then
		local key = state.sel[state.tab]
		for _, entry in ipairs(view.entries or {}) do
			if key ~= nil and Wn.Key(entry) == key then
				e = entry
				break
			end
		end
		local T = Wn.EXTRA[state.tab]
		if not e and key ~= nil and T and T.Find then
			e = T.Find(key) -- (picked but not listed yet: its list is still being worked out)
		end
	end
	if e and Wn.EXTRA[state.tab] then
		Wn.EXTRA[state.tab].Details(e)
	elseif e and state.tab == "bags" then
		D.Bag(e)
	elseif e then
		D.Idea(e)
	elseif not state.goal and Wn.EXTRA[state.tab] and Wn.EXTRA[state.tab].Overview then
		Wn.EXTRA[state.tab].Overview()
	else
		D.Goal()
	end
	D.End()
	view.Strip.Sel:SetShown(state.goal or e == nil)
end

function Wn.Draw()
	local state, view = Wn.state, Wn.view
	if not view then
		return
	end
	state.draws, state.old, state.due = state.draws + 1, false, false
	for key, tab in pairs(view.tabs) do
		local on = key == state.tab
		tab.Line:SetShown(on)
		tab.Back:SetColorTexture(1, 0.82, 0, on and 0.14 or 0.04)
		tab.Text:SetTextColor(on and 1 or 0.75, on and 0.82 or 0.75, on and 0 or 0.75)
	end
	local line = Wn.GoalLine()
	view.Strip.Text:SetText(line or GREY .. L["No money goal: click to set one"] .. "|r")
	local entries, head, empty = Wn.Entries(state.tab)
	view.entries = entries
	local T = Wn.EXTRA[state.tab]
	view.Head:SetWidth(T and T.headWidth or (C.LIST_W - 8))
	for key, other in pairs(Wn.EXTRA) do
		if other.Controls then
			other.Controls(view, key == state.tab)
		end
	end
	view.Head:SetText(head or "")
	view.Message:SetText(empty or "")
	view.Message:SetShown(#entries == 0)
	view.HeadButton:SetShown(state.tab == "ideas")
	view.MessageButton:SetShown(state.tab == "ideas" and #entries == 0)
	view.list:SetEntries(entries, state.shownTab == state.tab)
	state.shownTab = state.tab
	Wn.DrawDetails()
end

-- Only the line above the list and the message (what's worked on changed); the list when its count changed.
function Wn.DrawStatus()
	local view = Wn.view
	if not view then
		return
	end
	local entries, head, empty = Wn.Entries(Wn.state.tab)
	view.Head:SetText(head or "")
	view.Message:SetText(empty or "")
	if #entries ~= #(view.entries or {}) then
		Wn.state.due = true
	end
end

function Wn.Pick(e)
	local state = Wn.state
	state.goal = false
	state.sel[state.tab] = Wn.Key(e)
	Wn.view.list:Lay()
	Wn.DrawDetails()
end

function Wn.SetTab(tab)
	local state = Wn.state
	state.tab = tab
	state.goal = false
	Settings().tab = tab
	Wn.Request()
	Wn.Draw()
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

function Wn.NewTab(parent, key, label)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(C.TOP - 6)
	b.key = key
	b.Back = b:CreateTexture(nil, "BACKGROUND")
	b.Back:SetAllPoints()
	b.Line = b:CreateTexture(nil, "ARTWORK")
	b.Line:SetPoint("BOTTOMLEFT")
	b.Line:SetPoint("BOTTOMRIGHT")
	b.Line:SetHeight(2)
	b.Line:SetColorTexture(1, 0.82, 0, 1)
	b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.Text:SetPoint("CENTER", 0, 1)
	b.Text:SetText(label)
	b:SetWidth(math.max(64, b.Text:GetStringWidth() + 24))
	b:SetHighlightTexture(HIGHLIGHT, "ADD")
	b:SetScript("OnClick", function(self)
		Wn.SetTab(self.key)
	end)
	return b
end

function Wn.SavePlace(f)
	local s = Settings()
	local left, top = f:GetLeft(), f:GetTop()
	if Num(left) and Num(top) then
		s.left, s.top = math.floor(left + 0.5), math.floor(top + 0.5)
	end
end

function Wn.Build()
	local f = CreateFrame("Frame", NAME, UIParent)
	f:SetSize(C.W, C.H)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		self:SetUserPlaced(false)
		Wn.SavePlace(self)
	end)
	f:Hide()
	LT.Window.Dress(f)
	table.insert(UISpecialFrames, NAME) -- (Escape closes it)
	LT.Window.Register(NAME)
	f:HookScript("OnShow", function() LT.Trail("window " .. NAME) end)
	f:HookScript("OnHide", function() LT.Trail("window closed " .. NAME) end)
	local view = { tabs = {}, entries = {} }
	Wn.frame, Wn.view = f, view

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -7)
	title:SetText("WhyPoor?")
	local x = 10 + title:GetStringWidth() + 14
	for _, key in ipairs(Wn.TABS) do
		local tab = Wn.NewTab(f, key, Wn.LABELS[key])
		tab:SetPoint("TOPLEFT", x, -3)
		x = x + tab:GetWidth() + 4
		view.tabs[key] = tab
	end
	view.Close = CreateFrame("Button", nil, f, "UIPanelCloseButtonNoScripts")
	view.Close:SetSize(24, 24)
	view.Close:SetPoint("TOPRIGHT", -2, -1)
	view.Close:SetScript("OnClick", function() f:Hide() end)

	-- The goal's strip.
	local strip = CreateFrame("Button", nil, f)
	strip:SetPoint("TOPLEFT", C.PAD, -C.TOP)
	strip:SetPoint("TOPRIGHT", -C.PAD, -C.TOP)
	strip:SetHeight(C.GOAL_H)
	strip.Back = strip:CreateTexture(nil, "BACKGROUND")
	strip.Back:SetAllPoints()
	strip.Back:SetColorTexture(1, 0.82, 0, 0.06)
	strip.Sel = strip:CreateTexture(nil, "BORDER")
	strip.Sel:SetPoint("BOTTOMLEFT")
	strip.Sel:SetPoint("BOTTOMRIGHT")
	strip.Sel:SetHeight(1)
	strip.Sel:SetColorTexture(1, 0.82, 0, 0.6)
	strip.Icon = strip:CreateTexture(nil, "ARTWORK")
	strip.Icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
	strip.Icon:SetSize(14, 14)
	strip.Icon:SetPoint("LEFT", 4, 0)
	strip.Text = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	strip.Text:SetPoint("LEFT", 22, 0)
	strip.Text:SetPoint("RIGHT", -4, 0)
	strip.Text:SetJustifyH("LEFT")
	strip.Text:SetWordWrap(false)
	strip:SetHighlightTexture(HIGHLIGHT, "ADD")
	strip:SetScript("OnClick", function(self)
		Untip(self)
		Wn.state.goal = true
		view.list:Lay()
		Wn.DrawDetails()
	end)
	strip:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(L["Your money goal"], 1, 0.82, 0)
		GameTooltip:AddLine(L["Click: how it's worked out; set your own goal or the bar for ideas"], 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	strip:SetScript("OnLeave", Untip)
	view.Strip = strip

	-- The list on the left, the details on the right.
	local bodyY = C.TOP + C.GOAL_H + 6
	local bodyH = C.H - bodyY - C.PAD
	view.Head = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	view.Head:SetPoint("TOPLEFT", C.PAD + 4, -bodyY - 2)
	view.Head:SetWidth(C.LIST_W - 8)
	view.Head:SetJustifyH("LEFT")
	view.Head:SetWordWrap(false)
	view.list = Wn.NewList(f, C.PAD, bodyY + C.HEAD_H, C.LIST_W - C.BAR_W, bodyH - C.HEAD_H, Wn.NewRow, Wn.FillRow)
	view.Message = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	view.Message:SetPoint("TOPLEFT", C.PAD + 10, -bodyY - C.HEAD_H - 12)
	view.Message:SetWidth(C.LIST_W - C.BAR_W - 20)
	view.Message:SetJustifyH("LEFT")
	view.Message:Hide()
	-- On the Ideas tab the line above the list and its message open the bar's details (Wn.ShowBar).
	local function BarButton(over)
		local b = CreateFrame("Button", nil, f)
		b:SetAllPoints(over)
		b:SetScript("OnClick", function(self)
			Untip(self)
			Wn.ShowBar()
		end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:SetText(L["The bar for ideas"], 1, 0.82, 0)
			GameTooltip:AddLine(L["Click: what an idea must bring to be listed, or set your own"], 0.8, 0.8, 0.8)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", Untip)
		b:Hide()
		return b
	end
	view.HeadButton = BarButton(view.Head)
	view.MessageButton = BarButton(view.Message)
	local split = f:CreateTexture(nil, "ARTWORK")
	split:SetColorTexture(1, 0.82, 0, 0.2)
	split:SetWidth(1)
	split:SetPoint("TOPLEFT", C.PAD + C.LIST_W + C.GAP / 2, -bodyY)
	split:SetHeight(bodyH)
	local detailX = C.PAD + C.LIST_W + C.GAP
	D.width = C.W - detailX - C.PAD - C.BAR_W
	local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", detailX, -bodyY)
	scroll:SetSize(D.width, bodyH)
	D.child = CreateFrame("Frame", nil, scroll)
	D.child:SetSize(D.width, 1)
	scroll:SetScrollChild(D.child)
	D.scroll = scroll
	D.MapButton = CreateFrame("Button", nil, D.child, "UIPanelButtonTemplate")
	D.MapButton:SetSize(120, 20)
	D.MapButton:SetText(L["Show on map"])
	D.MapButton:SetScript("OnClick", function()
		local Q, place = ns.Lodestar, D.place
		if Q and Q.ShowPlace and place then
			Q.ShowPlace(place.map, place.points)
		end
	end)
	D.MapButton:Hide()

	-- While shown: what changed drawn on the next frame, I.Request every TICK seconds.
	local ticker = CreateFrame("Frame", nil, f)
	local wait, busyWait = C.TICK, 0.5
	ticker:SetScript("OnUpdate", function(_, elapsed)
		wait = wait - elapsed
		if wait <= 0 then
			wait = C.TICK
			Wn.Request()
			Wn.state.due = true
			if W.Goal and W.Goal.Forget then
				W.Goal.Forget()
			end
		end
		-- What's being worked on (the scan, the ideas' run): looked at twice a second, the line above the list
		-- (and the message) drawn again when it changed.
		busyWait = busyWait - elapsed
		if busyWait <= 0 then
			busyWait = 0.5
			local work = (Wn.ScanLine() or "") .. "|" .. (Wn.WorkLine() or "")
			if work ~= Wn.state.work then
				Wn.state.work = work
				if not Wn.state.due then
					LT.Guard("WhyPoor.status", Wn.DrawStatus)
				end
			end
		end
		if Wn.state.due then
			Wn.state.due = false
			LT.Guard("WhyPoor.draw", Wn.Draw)
		end
	end)
	view.ticker = ticker
	f:SetScript("OnEvent", function()
		Wn.state.due = true
	end)
	f:HookScript("OnShow", function(self)
		for _, event in ipairs({ "PLAYER_MONEY", "BAG_UPDATE_DELAYED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" }) do
			self:RegisterEvent(event)
		end
		wait = C.TICK
	end)
	f:HookScript("OnHide", function(self)
		self:UnregisterAllEvents()
		GameTooltip:Hide()
	end)
	local s = Settings()
	if Num(s.left) and Num(s.top) then
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", s.left, s.top)
	else
		f:SetPoint("CENTER")
	end
	if Wn.IsTab(s.tab) then
		Wn.state.tab = s.tab
	end
end

-- Scaled down to fit a small screen (or a large UI scale).
function Wn.Fit()
	local sw = Num(GetScreenWidth and GetScreenWidth()) or C.W
	local sh = Num(GetScreenHeight and GetScreenHeight()) or C.H
	Wn.frame:SetScale(math.max(0.5, math.min(1, (sw - C.SCREEN) / C.W, (sh - C.SCREEN) / C.H)))
end

-- I.Watch's call: drawn on the next frame while shown, else only noted.
function Wn.IdeasChanged()
	if Wn.frame and Wn.frame:IsShown() then
		Wn.state.due = true
	else
		Wn.state.old = true
	end
end

-- The ideas asked for: only on the tabs that show them (Ideas, Market); the others never make them work.
function Wn.Request()
	local I = W.Ideas
	if I and I.Watch and Wn.watched ~= I then
		Wn.watched = I -- (once per W.Ideas)
		I.Watch(Wn.IdeasChanged)
	end
	local tab = Wn.state.tab
	if I and I.Request and (tab == "ideas" or tab == "market") then
		Wn.state.requests = Wn.state.requests + 1
		LT.Guard("WhyPoor.request", I.Request)
	end
end

---------------------------------------------------------------------------
-- What the others call
---------------------------------------------------------------------------

-- Opens the window, on a tab ("ideas", "bags", "market", "crafting") or the goal ("goal"; nil: as it was).
function Wn.Open(tab)
	local m = W.module
	if m and not m.enabled then
		LT.Print("WhyPoor? is switched off (/lefthy enable whypoor).")
		return false
	end
	if not Wn.frame then
		Wn.Build()
	end
	if tab == "goal" or tab == "bar" then
		Wn.state.goal = true
	elseif Wn.IsTab(tab) then
		Wn.state.tab, Wn.state.goal = tab, false
		Settings().tab = tab
	end
	Wn.Fit()
	Wn.frame:Show()
	if Wn.frame.Raise then
		Wn.frame:Raise()
	end
	Wn.Request()
	Wn.Draw()
	return true
end

function Wn.Toggle()
	if Wn.frame and Wn.frame:IsShown() then
		Wn.frame:Hide()
	else
		Wn.Open()
	end
end

function Wn.Shown()
	return Wn.frame ~= nil and Wn.frame:IsShown()
end

-- Switched off: closed, the auction house's button hidden.
function Wn.SettingsChanged()
	local m = W.module
	local on = m and m.enabled
	if Wn.frame and not on then
		Wn.frame:Hide()
	end
	if Wn.ahButton then
		Wn.ahButton:SetShown(on and true or false)
	end
	if Wn.frame and Wn.frame:IsShown() then
		Wn.state.due = true
	end
end

-- The "WhyPoor?" button on the auction house's window, at its top right left of the close button, made the
-- first time the auction house opens (on the next frame: Blizzard's window is there then).
function Wn.HookAuctionHouse()
	local ah = _G.AuctionHouseFrame
	if Wn.ahButton or type(ah) ~= "table" then
		return
	end
	local b = CreateFrame("Button", nil, ah, "UIPanelButtonTemplate")
	b:SetSize(80, 20)
	b:SetText("WhyPoor?")
	b:SetPoint("TOPRIGHT", ah, "TOPRIGHT", -26, -1)
	b:SetScript("OnClick", function()
		Wn.Open("market")
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("WhyPoor?")
		GameTooltip:AddLine(L["The deals in the auction house's prices, your recipes' margins and your bags' best sales."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", Untip)
	local m = W.module
	b:SetShown(m and m.enabled and true or false)
	Wn.ahButton = b
end

Wn.loader = CreateFrame("Frame")
Wn.loader:RegisterEvent("AUCTION_HOUSE_SHOW")
Wn.loader:SetScript("OnEvent", function(self)
	C_Timer.After(0, function()
		Wn.HookAuctionHouse()
		if Wn.ahButton then
			self:UnregisterAllEvents() -- (made: it shows and hides with Blizzard's window)
		end
	end)
end)

-- For the tests: the frame, its state and views, the details' pools.
function Wn.View()
	return Wn.frame, Wn.state, Wn.view, D
end
