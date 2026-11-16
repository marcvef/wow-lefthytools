local _, ns = ...
local LT = ns.LT
local L = ns.L
local W = ns.WhyPoor or {}
ns.WhyPoor = W

-- The window's Stocks tab (W.Stocks, St): a watch list of items and their price on your auction house over time.
-- The list: the watched items (LefthyToolsWhyPoorDB.watch, account-wide: item IDs in the order added), each with
-- its latest daily low (P.History) and the change since a week ago (else since the oldest day known). A search box
-- on the line above the list: while it has text, the list is the items of the auction house's prices (P.Items)
-- whose name has it (any case; an item link or "#1234" is that item). A click: the item's price graph (D.Graph)
-- and "Add to watch list" / "Remove from watch list". Informational only.
-- What it costs: nothing while the tab isn't shown. A search starts SEARCH_GAP after the last key, then goes over
-- the items a slice a frame (BUDGET_MS, at most PER_FRAME items) on a frame of its own, hidden once it's done;
-- items' names are kept lowercased (St.lower), so the next search only compares strings.

local St = { query = "", lower = {}, results = nil, total = 0 }
W.Stocks = St

local Wn = W.Window
local D = Wn.D
local GREY, GREEN, RED = "|cff888888", "|cff40c040", "|cffff4040"
local SEP = " · "
St.SEARCH_GAP, St.BUDGET_MS, St.PER_FRAME, St.CHECK = 0.2, 2, 2000, 50
St.SHOWN, St.WEEK, St.ASK = 50, 7, 50 -- results shown at most; a week in days; items' data asked for per search

local function Clock()
	local ok, ms = pcall(debugprofilestop)
	return ok and type(ms) == "number" and ms or nil
end

local function P()
	return W.Prices
end

---------------------------------------------------------------------------
-- The watch list
---------------------------------------------------------------------------

-- The saved list (item IDs, the order added); an empty one before the saved variables are there.
function St.List()
	local db = W.DB and W.DB()
	if not db then
		return {}
	end
	db.watch = type(db.watch) == "table" and db.watch or {}
	return db.watch
end

function St.Watched(item)
	for i, id in ipairs(St.List()) do
		if id == item then
			return i
		end
	end
end

function St.Watch(item)
	if type(item) == "number" and not St.Watched(item) and W.DB and W.DB() then
		local list = St.List()
		list[#list + 1] = item
	end
	Wn.state.due = true
end

function St.Unwatch(item)
	local i = St.Watched(item)
	if i then
		table.remove(St.List(), i)
	end
	Wn.state.due = true
end

---------------------------------------------------------------------------
-- An item's numbers
---------------------------------------------------------------------------

-- An entry: the item, its daily lows (P.History, the oldest first), the latest low, the change.
function St.Entry(item)
	local p = P()
	local list = p and p.History and p.History(item) or {}
	local e = { item = item, days = list }
	local last = list[#list]
	if last then
		e.low, e.day = last.low, last.day
	end
	if #list >= 2 then
		-- The change since a week ago: the latest day at least a week before the last, else the oldest.
		local ref = list[1]
		for _, d in ipairs(list) do
			if d.day <= last.day - St.WEEK then
				ref = d
			end
		end
		if ref.low > 0 then
			e.change, e.since = (last.low - ref.low) / ref.low, last.day - ref.day
		end
	end
	return e
end

-- "+12% vs. 7 days ago", green up, red down.
function St.ChangeText(e)
	if not e.change then
		return nil
	end
	local pct = math.floor(e.change * 100 + 0.5)
	local text = (pct > 0 and (GREEN .. "+" .. pct) or pct < 0 and (RED .. pct) or "0") .. "%" .. (pct ~= 0 and "|r" or "")
	return L["%s vs. %d days ago"]:format(text, e.since)
end

-- An item's plain name (nil: not known to the client yet).
function St.Name(item)
	local ok, name = pcall(C_Item.GetItemInfo, ("item:%d"):format(item))
	return ok and type(name) == "string" and not LT.IsSecret(name) and name or nil
end

---------------------------------------------------------------------------
-- The search
---------------------------------------------------------------------------

-- The items of the auction house's prices, fetched again only when the prices changed.
function St.Items()
	local p = P()
	local rev = p and p.Revision and p.Revision()
	if not St.items or St.itemsRev ~= rev then
		St.items, St.itemsRev = p and p.Items and p.Items() or {}, rev
	end
	return St.items
end

-- What's typed: "" clears the search; an item link or "#1234" is that item at once; else a search after SEARCH_GAP.
function St.SetQuery(text)
	text = strtrim(text or "")
	local q = text:lower()
	if q == St.query then
		return
	end
	St.query = q
	local id = tonumber(text:match("|Hitem:(%d+)") or text:match("^#(%d+)$") or "")
	if q == "" then
		St.search, St.results, St.total = nil, nil, 0
	elseif id then
		St.search, St.results, St.total = nil, { id }, 1
	else
		St.search = { q = q, at = GetTime() + St.SEARCH_GAP, i = 1, front = {}, rest = {}, total = 0, asked = 0 }
		St.driver:Show()
	end
	Wn.state.due = true
end

-- A slice of the search: the items' lowercased names (the first time each is seen), the matches; at the end the
-- names starting with what's typed first, then the others, each by name, SHOWN at most.
function St.SearchStep()
	local s = St.search
	local items = s.items
	if not items then
		items = St.Items()
		s.items = items
	end
	local started, n = Clock(), 0
	while items[s.i] do
		local item = items[s.i]
		local name = St.lower[item]
		if name == nil then
			local plain = St.Name(item)
			if plain then
				name = plain:lower()
				St.lower[item] = name
			elseif s.asked < St.ASK and C_Item.RequestLoadItemDataByID then
				s.asked = s.asked + 1
				pcall(C_Item.RequestLoadItemDataByID, item)
			end
		end
		if name then
			local at = name:find(s.q, 1, true)
			if at then
				s.total = s.total + 1
				local into = at == 1 and s.front or s.rest
				if #into < St.SHOWN then
					into[#into + 1] = item
				end
			end
		end
		s.i, n = s.i + 1, n + 1
		if n >= St.PER_FRAME or (n % St.CHECK == 0 and started and Clock() - started >= St.BUDGET_MS) then
			return false
		end
	end
	local function ByName(a, b)
		local x, y = St.lower[a], St.lower[b]
		if x ~= y then
			return x < y
		end
		return a < b
	end
	table.sort(s.front, ByName)
	table.sort(s.rest, ByName)
	local out = {}
	for _, list in ipairs({ s.front, s.rest }) do
		for _, item in ipairs(list) do
			if #out < St.SHOWN then
				out[#out + 1] = item
			end
		end
	end
	St.results, St.total, St.search = out, s.total, nil
	Wn.state.due = true
	return true
end

function St.Showing()
	return Wn.Shown() and Wn.state.tab == "stocks"
end

-- The search's frame: only while one is waiting or under way and the tab shows.
St.driver = CreateFrame("Frame")
St.driver:Hide()
St.driver:SetScript("OnUpdate", function(self)
	if not (St.search and St.Showing()) then
		self:Hide()
		return
	end
	if GetTime() >= St.search.at then
		LT.Guard("WhyPoor stocks", St.SearchStep)
	end
end)

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------

local T = { headWidth = 96 }
St.tab = T

function T.Entries()
	local ids
	if St.query == "" then
		ids = St.List()
	else
		if St.search and not St.driver:IsShown() then
			St.driver:Show() -- (a search left when the window closed goes on)
		end
		ids = St.results or {}
	end
	local list = {}
	for _, item in ipairs(ids) do
		if type(item) == "number" then
			list[#list + 1] = { item = item } -- (its numbers when its row is in sight: T.Fill)
		end
	end
	if St.query == "" then
		return list, L["%d watched"]:format(#list), L["Search for an item above and add it to watch its price."]
	elseif St.search then
		return {}, L["Searching..."], L["Searching..."]
	end
	local head = St.total > #list and L["%d of %d found"]:format(#list, St.total) or L["%d found"]:format(#list)
	return list, head, L["No item by that name in your auction house's prices."]
end

function T.Fill(row, e)
	e = St.Entry(e.item)
	row.Icon:SetTexture(Wn.ItemIcon(e.item))
	row.Title:SetText(Wn.ItemName(e.item))
	local p = P()
	local old = e.day and p and p.Today and e.day < p.Today() - 1 -- (not seen today or yesterday)
	row.Money:SetText(e.low and ((old and GREY or "") .. W.Money(e.low) .. (old and "|r" or "")) or (GREY .. "-|r"))
	local sub = St.ChangeText(e) or (#e.days == 1 and L["One day of prices so far"]) or L["No prices yet"]
	if St.query ~= "" and St.Watched(e.item) then
		sub = sub .. SEP .. L["watched"]
	end
	row.Sub:SetText(sub)
	for _, dot in ipairs(row.Dots) do
		dot:Hide()
	end
end

function T.Key(e)
	return e.item
end

-- Picked but not in the list (the search changed, or it left the watch list): its details all the same.
function T.Find(item)
	return type(item) == "number" and { item = item } or nil
end

function T.Enter(row, e)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if not pcall(GameTooltip.SetHyperlink, GameTooltip, ("item:%d"):format(e.item)) then
		GameTooltip:SetText(Wn.ItemName(e.item), 1, 1, 1)
	end
	GameTooltip:AddLine(L["Click: its details"], 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

function T.Details(e)
	local item = e.item
	D.Text(Wn.ItemName(item), "title")
	local p = P()
	local now = p and p.Get and p.Get(item)
	if type(now) == "table" and now.seen then
		D.Text(L["AH"] .. ": " .. (now.low and L["%s (%d listed, %s)"]:format(W.Money(now.low), now.qty or 0, LT.Ago(now.seen))
			or L["none listed (%s)"]:format(LT.Ago(now.seen))), "small")
	end
	D.Graph(item)
	D.y = D.y + 6
	if St.Watched(item) then
		D.Button(L["Remove from watch list"], function() St.Unwatch(item) end, true, 170)
	else
		D.Button(L["Add to watch list"], function() St.Watch(item) end, true, 170)
	end
end

-- Nothing picked: what the tab is.
function T.Overview()
	D.Text(L["Stocks"], "title")
	D.Text(L["Your watch list: each item's lowest price on your auction house, day by day, and how it changed in a week. Search an item above the list and add it."], "text", 0, 2)
end

-- The search box on the line above the list.
function T.Controls(view, shown)
	if not shown and not St.box then
		return
	end
	if not St.box then
		local box = CreateFrame("EditBox", nil, view.Head:GetParent(), "InputBoxTemplate")
		box:SetSize(180, 18)
		box:SetPoint("LEFT", view.Head, "RIGHT", 8, 0)
		box:SetAutoFocus(false)
		box:SetMaxLetters(60)
		box.Hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		box.Hint:SetPoint("LEFT", 2, 0)
		box.Hint:SetText(L["Search an item"])
		box:SetScript("OnEscapePressed", function(self)
			self:SetText("")
			self:ClearFocus()
		end)
		box:SetScript("OnEnterPressed", box.ClearFocus)
		box:SetScript("OnTextChanged", function(self)
			local text = self:GetText() or ""
			self.Hint:SetShown(text == "")
			St.SetQuery(text)
		end)
		St.box = box
	end
	St.box:SetShown(shown)
	if not shown then
		St.box:ClearFocus()
	end
end

Wn.AddTab("stocks", L["Stocks"], T)
