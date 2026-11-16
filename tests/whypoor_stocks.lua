-- WhyPoor?'s Stocks tab (Stocks.lua): the watch list (saved, its order, add and remove), the search (any case, names
-- starting with it first, an item link, over frames, nothing while the window is closed), each row's latest daily
-- low and its change since a week ago, the details (the graph, the buttons), /whypoor stocks, the tab's box only on
-- its tab, German. On the real price engine: a few items' daily lows stored for this auction house, taken out again.
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
