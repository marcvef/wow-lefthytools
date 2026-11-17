-- WhyPoor?'s Stocks tab (Stocks.lua): the watch list (saved, its order, add and remove), the search (any case, names
-- starting with it first, an item link, over frames, nothing while the window is closed), each row's latest daily
-- low and its change since a week ago, the details (the graph, the buttons), /whypoor stocks, the tab's box only on
-- its tab, German. The suggestions: from one letter, the order (the name's start, a word's start, anywhere; watched,
-- priced, shorter), the typed part marked, the keyboard (Up/Down/Enter/Tab/Escape), a click picks and shows the
-- details, closing (focus, a click elsewhere, the tab, the window), names awaited and in on GET_ITEM_INFO_RECEIVED,
-- the name index over many frames within the budget for 20000 items and a keystroke's bounded work. On the real
-- price engine: a few items' daily lows stored for this auction house, taken out again.
-- Needs: no other file.
local suite = ...
local check, section, ns, LT = suite.check, suite.section, suite.ns, suite.LT

local W = ns.WhyPoor
local St, P = W.Stocks, W.Prices
local function Step(s) Advance(s or 1 / 60) end
local function Plain(text) return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function Type(box, text) -- (as a player types: the box's text, then its OnTextChanged as typed input)
	box:SetText(text)
	box._scripts.OnTextChanged(box, true)
end

section("WhyPoor?: the Stocks tab")
local tabWas = W.module.db.window and W.module.db.window.tab
local watchWas = W.DB().watch
W.DB().watch = {}
local key = P.HomeKey()
local now = time()
local DAY = 86400
ITEMS[9501] = { name = "Stockwood Plank", quality = 1 }
ITEMS[9502] = { name = "Stockwood Beam", quality = 2 }
ITEMS[9503] = { name = "Iron Stockpot", quality = 1 }
-- Daily lows: the plank 10s, 11s a week ago, 12s, 13s 20c today (+20% in a week); the beam one day; the pot 20s
-- two days ago, 15s today (-25%).
for _, s in ipairs({ { 9501, 9, 1000 }, { 9501, 7, 1100 }, { 9501, 3, 1200 }, { 9501, 0, 1320 }, { 9502, 0, 500 },
		{ 9503, 2, 2000 }, { 9503, 0, 1500 } }) do
	P.Store(key, s[1], s[3], 4, now - s[2] * DAY)
end
local FILLER = 200 -- (items enough for a search over frames)
for i = 1, FILLER do
	ITEMS[9600 + i] = { name = "Filler Cloth " .. i, quality = 1 }
	P.Store(key, 9600 + i, 100 + i, 1, now)
end

local frame, state, view, D = W.Window.View()
SlashCmdList.LEFTHYTOOLS_WHYPOOR("stocks")
frame, state, view, D = W.Window.View()
Step()
check(frame:IsShown() and state.tab == "stocks" and view.tabs.stocks ~= nil, "/whypoor stocks: the window on Stocks")
check(Plain(view.Head:GetText()) == "0 watched" and view.Message:IsShown()
	and view.Message:GetText() == "Search for an item above and add it to watch its price.", "an empty watch list: what to do")
local function Texts()
	local out = {}
	for _, fs in ipairs(D.texts) do if fs:IsShown() then out[#out + 1] = Plain(fs:GetText()) end end
	return table.concat(out, "\n")
end
check(Texts():find("Stocks", 1, true) and Texts():find("Your watch list", 1, true), "nothing picked: what the tab is")
local box = St.box
check(box and box:IsShown(), "the search box on the line above the list")

-- The search.
Type(box, "stockwood")
Step()
check(Plain(view.Head:GetText()) == "Searching...", "typing: it searches")
Advance(St.SEARCH_GAP + 0.1)
Step()
local function Items()
	local out = {}
	for i, e in ipairs(view.entries) do out[i] = e.item end
	return table.concat(out, ",")
end
check(Items() == "9502,9501" and Plain(view.Head:GetText()) == "2 found", "the items with that name, by name: " .. Items())
Type(box, "STOCK")
Advance(St.SEARCH_GAP + 0.1)
Step()
check(Items() == "9502,9501,9503" and not St.driver:IsShown(), "any case; names starting with it first; the search's frame done: " .. Items())
local function Row(item)
	for _, row in pairs(view.list.rows) do
		if row:IsShown() and row.entry and row.entry.item == item then return row end
	end
end
local plank = Row(9501)
check(plank and Plain(plank.Title:GetText()) == "Stockwood Plank" and plank.Money:GetText() == "13s 20c"
	and Plain(plank.Sub:GetText()) == "+20% vs. 7 days ago", "a row: the latest daily low, the change in a week: "
	.. tostring(plank and plank.Money:GetText()) .. " " .. tostring(plank and Plain(plank.Sub:GetText())))
check(Plain(Row(9503).Sub:GetText()) == "-25% vs. 2 days ago" and Plain(Row(9502).Sub:GetText()) == "One day of prices so far",
	"fewer days: the change since the oldest; one day: says so")

-- The details: the graph, Add.
local function Button(label)
	for _, b in ipairs(D.buttons) do if b:IsShown() and Plain(b:GetText()) == label then return b end end
end
plank:Click()
local bars = 0
for _, bar in ipairs(D.graph and D.graph.bars or {}) do if bar:IsShown() then bars = bars + 1 end end
check(Texts():find("Stockwood Plank", 1, true) and Texts():find("Price on your auction house", 1, true) and D.graph:IsShown()
	and bars == 4, "a click: its price graph, a bar a day: " .. Texts())
check(Button("Add to watch list") ~= nil and Button("Remove from watch list") == nil, "not watched: Add")
Button("Add to watch list"):Click()
Step()
check(#W.DB().watch == 1 and W.DB().watch[1] == 9501, "added: saved")
check(Button("Remove from watch list") ~= nil and Plain(Row(9501).Sub:GetText()):find("watched", 1, true), "now Remove; the result says it's watched")
Row(9503):Click()
Button("Add to watch list"):Click()
Step()

-- The watch list.
Type(box, "")
Step()
check(Items() == "9501,9503" and Plain(view.Head:GetText()) == "2 watched", "the box empty: the watch list, in the order added")
check(not Plain(Row(9501).Sub:GetText()):find("watched", 1, true), "the watch list's rows don't say watched")
Row(9501):Click()
Button("Remove from watch list"):Click()
Step()
check(Items() == "9503" and W.DB().watch[1] == 9503 and #W.DB().watch == 1, "removed")
check(Texts():find("Stockwood Plank", 1, true) and Button("Add to watch list") ~= nil, "its details stay, with Add (undo)")

-- An item link; the box only on its tab.
Type(box, ItemLink(9502))
Step()
check(Items() == "9502" and Plain(view.Head:GetText()) == "1 found", "an item link: that item at once")
view.tabs.bags:Click()
check(not box:IsShown(), "another tab: no box")
view.tabs.stocks:Click()
check(box:IsShown() and Items() == "9502", "back: the box and its search")

-- Bounded: a search over frames; nothing while the window is closed.
local count = #St.Items()
St.PER_FRAME = math.max(1, math.ceil(count / 20))
Type(box, "plank")
Advance(St.SEARCH_GAP)
local frames = 0
while St.search and frames < 1000 do Step() frames = frames + 1 end
check(frames >= 15 and Items() == "9501", "a search over many items goes a slice a frame: " .. frames .. " frames for " .. count .. " items")
Type(box, "iron")
frame:Hide()
Advance(1)
check(St.search ~= nil and not St.driver:IsShown(), "the window closed: the search waits, its frame hidden")
W.Window.Open("stocks")
Advance(1)
check(St.search == nil and Items() == "9503", "opened again: it goes on")
St.PER_FRAME = 2000

-- The autocomplete: the dropdown under the box as you type, from the name index.
section("WhyPoor?: the Stocks tab's suggestions")
local function Settle(max)
	local n = 0
	while (St.Busy() or St.search) and n < (max or 3000) do Step() n = n + 1 end
	return n
end
check(St.index and St.index.started and not St.index.lists, "the name index: made when the tab first showed")
check(box.Hint:GetText() == "Search an item: name, link or #id", "the empty box's hint")
ITEMS[9901] = { name = "Zorbweave Cloth", quality = 1 }
ITEMS[9902] = { name = "Bolt of Zorbweave", quality = 2 }
ITEMS[9903] = { name = "Ultrazorb Gem", quality = 3 }
ITEMS[9904] = { name = "Zorb", quality = 1 }        -- (in the bags only: no price)
ITEMS[9905] = { name = "Zorbling Ring", quality = 2 } -- (watched)
for _, s in ipairs({ { 9901, 300 }, { 9902, 900 }, { 9903, 5000 }, { 9905, 12345 } }) do
	P.Store(key, s[1], s[2], 3, now)
end
BAGS[0][30] = 9904
St.Watch(9905)
Type(box, "")
Advance(St.REFRESH + 0.1)
St.Wake()
Settle()
check(St.index.has[9904] and St.index.priced[9901] and not St.index.priced[9904] and St.index.has[9905],
	"the prices changed: the new items, the bags' and the watch list's in the index")
local drop = St.drop
local function Sugg()
	local out = {}
	for i, c in ipairs(St.sugg) do out[i] = c.item end
	return table.concat(out, ",")
end
local function Shown()
	local n = 0
	for _, r in ipairs(drop.rows) do if r:IsShown() then n = n + 1 end end
	return n
end

-- One letter: suggestions at once; the order.
Type(box, "z")
check(drop:IsShown() and Shown() >= 4 and Shown() <= St.MAX and Plain(drop.rows[1].Name:GetText()):sub(1, 1) == "Z",
	"one letter: the dropdown at once: " .. Sugg())
local function Ordered(want)
	Type(box, "zorb")
	return Sugg() == want
end
check(Ordered("9905,9901,9904,9902"), "the names starting with it (watched, priced, shorter first), then a word starting with it: " .. Sugg())
check(St.work <= 2 * (St.SCAN + 20) + St.FRESH_MAX, "a keystroke looks at a bounded number of names: " .. St.work)
local rows = drop.rows
check(rows[2].Name:GetText() == "|cffffffff|r|cffffd200Zorb|r|cffffffffweave Cloth|r", "the typed part marked, the rest in its quality colour: " .. rows[2].Name:GetText())
check(rows[4].Name:GetText() == "|cff1eff00Bolt of |r|cffffd200Zorb|r|cff1eff00weave|r", "a word's start: marked there: " .. rows[4].Name:GetText())
check(Plain(rows[1].Right:GetText()) == "watched  " .. Plain(W.Money(12345)) and Plain(rows[3].Right:GetText()) == "-"
	and rows[1].Icon.path == 1000 + 9905, "each row: its icon, its lowest price, watched; no price: -")
Advance(St.SEARCH_GAP + 0.1)
Settle()
Step()
check(Sugg() == "9905,9901,9904,9902,9903" and rows[5].Name:GetText() == "|cff0070ddUltra|r|cffffd200zorb|r|cff0070dd Gem|r",
	"after the full search: the names that have it anywhere, last: " .. Sugg())
check(Items() == "9904,9905,9901,9902,9903", "the list: the full results, by the same kinds of match: " .. Items())
-- The same from the sorted keys (not the names come since the last sort).
St.FRESH_MAX = 1
St.Wake()
Settle()
check(St.index.sortedItems == #St.index.items, "sorted in")
check(Ordered("9905,9901,9904,9902,9903"), "the same order from the sorted keys (binary search): " .. Sugg())
St.FRESH_MAX = 200

-- The keyboard.
local function Key(script, arg) box._scripts[script](box, arg) end
Key("OnArrowPressed", "DOWN")
check(St.hl == 1 and rows[1].Sel:IsShown() and not rows[2].Sel:IsShown(), "Down: the first marked")
Key("OnArrowPressed", "DOWN")
Key("OnArrowPressed", "DOWN")
Key("OnArrowPressed", "UP")
check(St.hl == 2 and rows[2].Sel:IsShown(), "Down, Down, Up: the second")
Key("OnArrowPressed", "UP")
Key("OnArrowPressed", "UP")
check(St.hl == nil, "Up from the first: none marked")
Key("OnArrowPressed", "DOWN")
Key("OnArrowPressed", "DOWN")
box:SetFocus()
Key("OnEnterPressed")
Step()
check(not drop:IsShown() and box:GetText() == "Zorbweave Cloth" and state.sel.stocks == 9901 and not box:HasFocus(),
	"Enter: the marked one picked, its name in the box, selected")
check(Texts():find("Zorbweave Cloth", 1, true) and Button("Add to watch list") ~= nil, "its details: its name, Add")
Settle()
Step()
check(Items():find("9901", 1, true) and state.sel.stocks == 9901, "the list: the search for its name, it selected: " .. Items())
Type(box, "zorb")
Key("OnTabPressed")
check(state.sel.stocks == 9905 and box:GetText() == "Zorbling Ring" and not drop:IsShown(), "Tab, none marked: the first picked")
Type(box, "zorb")
Key("OnArrowPressed", "DOWN")
Key("OnArrowPressed", "DOWN")
Key("OnArrowPressed", "DOWN")
Key("OnTabPressed")
check(state.sel.stocks == 9904, "Tab: the marked one")
Type(box, "zorb")
box:SetFocus()
Key("OnEscapePressed")
check(not drop:IsShown() and box:GetText() == "zorb" and box:HasFocus(), "Escape: the dropdown closed, the text kept")
Key("OnEscapePressed")
check(box:GetText() == "" and not box:HasFocus(), "a second Escape: the box empty")
Type(box, "zorb")
Key("OnEnterPressed")
check(not drop:IsShown() and St.search and St.search.at <= GetTime(), "Enter, none marked: closed, the full search at once")
Step()
Settle()
Step()
check(Items() == "9904,9905,9901,9902,9903" and Plain(view.Head:GetText()) == "5 found", "the full results: " .. Items())
Key("OnArrowPressed", "DOWN")
check(drop:IsShown(), "Down in the box: the dropdown again")

-- The mouse.
Type(box, "zorb")
rows[4]:Click()
Step()
check(state.sel.stocks == 9902 and box:GetText() == "Bolt of Zorbweave" and not drop:IsShown()
	and Texts():find("Bolt of Zorbweave", 1, true), "a click on a suggestion: it picked, its details")
Type(box, "zorb")
rows[3]._scripts.OnEnter(rows[3])
check(St.hl == 3 and rows[3].Sel:IsShown(), "the mouse on a row marks it")

-- Closing: the focus gone (a moment later; not while the mouse is on it), a click elsewhere, the tab, the window.
box:SetFocus()
box:ClearFocus()
Key("OnEditFocusLost")
drop._mouse = true
Advance(St.CLOSE_DELAY + 0.05)
check(drop:IsShown(), "the focus gone with the mouse on the dropdown (a click on its way): still open")
drop._mouse = false
Advance(St.CLOSE_DELAY + 0.05)
check(not drop:IsShown(), "then closed")
Key("OnEditFocusGained")
check(drop:IsShown(), "the focus back with text: open again")
drop._mouse = true
Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
check(drop:IsShown(), "a click on it: open")
drop._mouse = false
Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
check(not drop:IsShown(), "a click elsewhere: closed")
Type(box, "zorb")
view.tabs.bags:Click()
check(not drop:IsShown(), "another tab: closed")
view.tabs.stocks:Click()
Type(box, "zorb")
frame:Hide()
check(not drop:IsShown(), "the window closed: closed")
W.Window.Open("stocks")
Step()

-- Above the rest, within the window.
Type(box, "filler")
check(Shown() == St.MAX and drop:GetFrameStrata() == "FULLSCREEN_DIALOG" and drop:GetFrameLevel() > frame:GetFrameLevel(),
	"at most " .. St.MAX .. " rows; above the window's frames")
check(drop:GetPoint(1) == "TOPLEFT" and select(2, drop:GetPoint(1)) == box and 8 + 4 + St.tab.headWidth + 8 - 6 + drop:GetWidth() <= frame:GetWidth()
	and 26 + 20 + 6 + 18 + 4 + drop:GetHeight() <= frame:GetHeight(), "under the box, within the window")
Type(box, "#9902")
check(Sugg() == "9902" and Plain(rows[1].Name:GetText()) == "Bolt of Zorbweave", "#id: that item")

-- Names the client doesn't have: asked for, in batches, and in when they come.
local requested = {}
local requestWas = C_Item.RequestLoadItemDataByID
C_Item.RequestLoadItemDataByID = function(id) requested[#requested + 1] = id end
ITEMS[9910] = { name = "Zorbmoss", quality = 1 }
ITEMS[9911] = { name = "Zorbgone", quality = 1 }
MOCK_ITEM_UNCACHED = { [9910] = true, [9911] = true }
P.Store(key, 9910, 70, 1, now)
P.Store(key, 9911, 71, 1, now)
Type(box, "")
Advance(St.REFRESH + 0.1)
St.Wake()
Step()
Step()
check(St.index.waiting[9910] and St.index.waiting[9911] and table.concat(requested, ","):find("9910,9911", 1, true)
	and St.listening, "names not known: awaited, asked for, GET_ITEM_INFO_RECEIVED listened to: " .. table.concat(requested, ","))
Type(box, "zorbm")
check(Sugg() == "" and not drop:IsShown() and St.wanted, "not there yet: nothing shown, still wanted")
view.tabs.bags:Click()
Step()
check(not St.listening and not St.indexer:IsShown(), "another tab: not listened to, the index waits")
view.tabs.stocks:Click()
Step()
check(St.listening, "back: listened to again")
Type(box, "zorbm")
MOCK_ITEM_UNCACHED = nil
Fire("GET_ITEM_INFO_RECEIVED", 9910, true)
Step()
check(St.index.has[9910] and not St.index.waiting[9910] and Sugg() == "9910", "a name came: in the index, suggested at once: " .. Sugg())
local waits = St.index.waitCount
Fire("GET_ITEM_INFO_RECEIVED", 9911, false)
Step()
check(not St.index.waiting[9911] and St.index.waitCount == waits - 1 and St.listening == (waits > 1),
	"an item that doesn't exist (success false): not awaited any more")
local left = {} -- (items earlier files left without a name: they don't exist either)
for item in pairs(St.index.waiting) do left[#left + 1] = item end
for _, item in ipairs(left) do Fire("GET_ITEM_INFO_RECEIVED", item, false) end
Step()
check(St.index.waitCount == 0 and not St.listening, "none awaited: not listened to")
C_Item.RequestLoadItemDataByID = requestWas

-- A big auction house: the index over many frames within the budget; a keystroke bounded.
do
	local BIG, big = 20000, {}
	local A = ("a"):byte()
	local function Code(i)
		local s = ""
		for _ = 1, 4 do s = string.char(A + i % 26) .. s; i = math.floor(i / 26) end
		return s
	end
	for i = 1, BIG do
		local id = 300000 + i
		ITEMS[id] = { name = "Bulk " .. Code(i), quality = 1 }
		big[i] = id
	end
	local itemsWas = P.Items
	P.Items = function() return big end
	P.Changed()
	Type(box, "")
	St.index, St.items = nil, nil
	St.Wake()
	-- A clock that goes on 0.5 ms a look: the budget ends a frame's work before INDEX_PER_FRAME.
	local ms = 0
	debugprofilestop = function() ms = ms + 0.5 return ms end
	Step()
	local budgeted = St.units
	debugprofilestop = nil
	check(budgeted > 0 and budgeted < St.INDEX_PER_FRAME, "the clock past BUDGET_MS: the frame's work stops: " .. tostring(budgeted))
	Type(box, "bulk")
	check(drop:IsShown() and drop.Status:IsShown() and Plain(drop.Status:GetText()) == "still reading names..." and Shown() > 0,
		"while it's read: suggestions from what's there, \"still reading names...\"")
	Type(box, "")
	local frames, most = 0, 0
	while St.Busy() and frames < 5000 do
		Step()
		frames = frames + 1
		most = math.max(most, St.units or 0)
	end
	check(not St.Busy() and St.index.sortedItems >= BIG and frames >= 20 and most <= St.INDEX_PER_FRAME
		and not St.indexer:IsShown(), ("%d names indexed over %d frames, at most %d a frame; then its frame hidden"):format(#St.index.items, frames, most))
	Type(box, "b")
	check(Shown() == St.MAX and St.work <= 2 * (St.SCAN + 20) + St.FRESH_MAX and not drop.Status:IsShown(),
		"one letter over 20000 names: " .. St.MAX .. " suggestions, " .. St.work .. " looked at")
	Type(box, "bulk aab")
	local ok = #St.sugg == St.MAX
	for _, c in ipairs(St.sugg) do ok = ok and ITEMS[c.item].name:lower():find("bulk aab", 1, true) == 1 end
	check(ok and St.work <= 2 * (St.SCAN + 20) + St.FRESH_MAX, "two words: the names starting with them: " .. Sugg())
	Type(box, "aab")
	ok = #St.sugg == St.MAX
	for _, c in ipairs(St.sugg) do ok = ok and c.tier == 2 end
	check(ok and St.work <= 2 * (St.SCAN + 20) + St.FRESH_MAX, "a later word's start, from the sorted keys: " .. St.work .. " looked at")
	Type(box, "")
	P.Items = itemsWas
	for i = 1, BIG do ITEMS[300000 + i] = nil end
	St.index, St.items = nil, nil
	P.Changed()
	Step()
end

-- Put back.
do
	local h = P.House(key)
	for _, item in ipairs({ 9901, 9902, 9903, 9904, 9905, 9910, 9911 }) do
		h.items[item], ITEMS[item] = nil, nil
	end
	BAGS[0][30] = nil
	St.Unwatch(9905)
	P.Changed()
end

-- German: the same placeholders, the name of nothing translated.
do
	local de, src = { LOCALE = "deDE", L = {} }, ""
	for _, file in ipairs(SOURCES) do
		if file.name == "Locales/deDE.lua" then
			assert(load(file.src, "@deDE.lua"))("LefthyTools", de)
		elseif file.name == "Modules/WhyPoor/Stocks.lua" then
			src = (("\n" .. file.src):gsub("\n%s*%-%-[^\n]*", "\n"))
		end
	end
	local function Holes(text) local out = {} for h in text:gmatch("%%[%%sd]") do out[#out + 1] = h end return table.concat(out) end
	local keys, bad = 0, {}
	for k in src:gmatch('L%["(.-)"%]') do
		keys = keys + 1
		if type(de.L[k]) ~= "string" or Holes(de.L[k]) ~= Holes(k) then bad[#bad + 1] = k end
	end
	check(keys > 10 and #bad == 0, "every text has its German with the same placeholders: " .. table.concat(bad, " | "))
end

-- Put back.
Type(box, "")
frame:Hide()
local h = P.House(key)
for _, item in ipairs({ 9501, 9502, 9503 }) do
	h.items[item] = nil
	ITEMS[item] = nil
end
for i = 1, FILLER do
	h.items[9600 + i], ITEMS[9600 + i] = nil, nil
end
P.Changed()
W.DB().watch = watchWas
if W.module.db.window then
	W.module.db.window.tab = tabWas
end
state.tab = tabWas or "ideas"
