-- WhyPoor?: the module, its settings, the window, the bags, the tooltip line, the goal (WhyPoor.lua, Window.lua, Bags.lua, Goal.lua).
-- Needs: no other file.
-- The prices (W.Prices) and the ideas (W.Ideas) are stand-ins here (their own files have their own tests),
-- as are Chronicle's record (the gold rate) and a riding trainer; everything is put back at the end.
local suite = ...
local check, section, ns, LT, lefthy, tooltipHas = suite.check, suite.section, suite.ns, suite.LT, suite.lefthy, suite.tooltipHas

local W = ns.WhyPoor
local M = LT:GetModule("whypoor")
local function Step(s) Advance(s or 1 / 60) end
local function Plain(text) return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

-- Stand-ins: the prices and the ideas (as their contracts in docs/whypoor.md say).
local saved = { Prices = W.Prices, Ideas = W.Ideas, BAGS = BAGS, MONEY = MONEY, CLASS = PLAYER_CLASS, LEVEL = PLAYER_LEVEL,
	XP = { XP.current, XP.max }, AH = AuctionHouseFrame }
local prices = { data = {}, vendor = {}, rev = 1, open = false }
W.Prices = {
	STALE = 3 * 3600, AH_CUT = 0.05,
	Vendor = function(item) return prices.vendor[item] end,
	Get = function(item) return prices.data[item] end,
	AHSale = function(item, n)
		local d = prices.data[item]
		local unit = d and (d.value or d.low)
		if not unit then return nil end
		return math.floor(unit * n * 0.95), unit
	end,
	Revision = function() return prices.rev end,
	IsOpen = function() return prices.open end,
	LastScan = function() return prices.last end,
}
W.Prices.Best = function(item, n)
	local ah, v = W.Prices.AHSale(item, n), prices.vendor[item]
	v = v and v * n
	if ah and (not v or ah > v) then return "ah", ah, "ah" end
	if v and v > 0 then return "vendor", v, "vendor" end
end
local ideas = { list = {}, ready = false, watchers = {}, requests = 0 }
W.Ideas = {
	Get = function() return ideas.list, ideas.ready end,
	Request = function() ideas.requests = ideas.requests + 1 end,
	Watch = function(fn) ideas.watchers[#ideas.watchers + 1] = fn end,
	Revision = function() return 1 end,
}
local function Changed(list, ready)
	ideas.list, ideas.ready = list, ready
	for _, fn in ipairs(ideas.watchers) do fn() end
end

ITEMS[9301] = { name = "Bolt of Linen", quality = 1, classID = 7 }
ITEMS[9302] = { name = "Bound Helm", quality = 2, classID = 4, equipLoc = "INVTYPE_HEAD", level = 30 }
ITEMS[9303] = { name = "Kobold Note", quality = 1, classID = 12 }
ITEMS[9304] = { name = "Rusty Dagger", quality = 1, classID = 2, equipLoc = "INVTYPE_WEAPON", level = 5 }
ITEMS[9305] = { name = "Gray Ram", quality = 3, classID = 15, subClassID = 5 }
ITEMS[9306] = { name = "Swift White Ram", quality = 4, classID = 15, subClassID = 5 }
local now = time()
prices.data[9301] = { low = 1300, qty = 12, seen = now - 7200, value = 1200, days = 5, sells = 0.8, confidence = "high" }
prices.data[9304] = { low = 90, qty = 1, seen = now - 7200, value = 90, days = 2, sells = 0.1, confidence = "low" }
prices.vendor[9301], prices.vendor[9302], prices.vendor[9303], prices.vendor[9304] = 300, 2500, 0, 150
BAGS = { [0] = { [1] = 9301, [2] = 9302, [3] = 9303, [4] = 9304, [5] = 9301 } }
BAG_STACKS["0:1"], BAG_STACKS["0:5"] = 5, 2
BOUND[2] = true
QUEST_BAG_ITEMS[9303] = 7001

---------------------------------------------------------------------------
section("WhyPoor?: the module, its settings, its commands, the minimap button")
do
	local function T(key) return REGISTERED_SETTINGS["LefthyTools_whypoor_" .. key] end
	check(M and M.enabled and M.db.minimapButton == true and M.db.craftButton == true and M.db.autoScan == true, "on, with its defaults")
	check(T("minimapButton") and T("craftButton") and T("autoScan") and T("sharePrices"), "a checkbox for each setting")
	check(SETTINGS_BUTTONS["Open WhyPoor?"] ~= nil, "an Open button on its page")
	check(W.Money(1234567) == "123g" and W.Money(12345) == "1g 23s" and W.Money(345) == "3s 45c" and W.Money(7) == "7c"
		and W.Money(-12345) == "-1g 23s" and W.Money(nil) == nil, "money in short")
	check(W.Age(time() - 30) == "1 min" and W.Age(time() - 7200) == "2 h" and W.Age(time() - 3 * 86400) == "3 d", "ages in short")

	Step()
	W.Window.state.tab = "ideas" -- (as a first opening has it)
	local button = _G.LefthyToolsWhyPoorMinimapButton
	check(button and button:IsShown(), "the minimap button")
	button:GetScript("OnEnter")(button)
	check(TOOLTIP.title == "WhyPoor?" and tooltipHas("Click: ideas for making money") and tooltipHas("Right-click: your bags"),
		"its tooltip: what a click does")
	button:Click("LeftButton")
	local frame, state = W.Window.View()
	check(frame and frame:IsShown() and state.tab == "ideas", "a click: the window, on Ideas")
	button:Click("LeftButton")
	check(not frame:IsShown(), "again: closed")
	button:Click("RightButton")
	check(frame:IsShown() and state.tab == "bags", "a right-click: the window on Bags")
	frame:Hide()
	LT:SetModuleSetting(M, "minimapButton", false)
	Step()
	check(not button:IsShown(), "the setting off: the button gone")
	SlashCmdList.LEFTHYTOOLS_WHYPOOR("minimap")
	Step()
	check(M.db.minimapButton == true and button:IsShown(), "/whypoor minimap: back")

	SlashCmdList.LEFTHYTOOLS_WHYPOOR("")
	check(frame:IsShown(), "/whypoor: open")
	SlashCmdList.LEFTHYTOOLS_WHYPOOR("")
	check(not frame:IsShown(), "/whypoor again: closed")
	lefthy("whypoor market")
	check(frame:IsShown() and state.tab == "market", "/lefthy whypoor market: on Market")
	lefthy("whypoor ideas")
	check(state.tab == "ideas", "/lefthy whypoor ideas")
	frame:Hide()
	local mark = #PRINTED
	SlashCmdList.LEFTHYTOOLS_WHYPOOR("help")
	check(#PRINTED > mark, "/whypoor help: the commands")
end

---------------------------------------------------------------------------
section("WhyPoor?: the window")
do
	local frame, state, view, D = W.Window.View()
	check(UISpecialFrames[#UISpecialFrames] == "LefthyToolsWhyPoorFrame" or (function()
		for _, n in ipairs(UISpecialFrames) do if n == "LefthyToolsWhyPoorFrame" then return true end end
	end)(), "Escape closes it")
	check(view.tabs.ideas and view.tabs.bags and view.tabs.market and view.tabs.ideas:GetScript("OnClick") ~= nil,
		"three tabs, buttons the controller reaches")

	-- Loading: nothing worked out yet.
	ideas.list, ideas.ready = {}, false
	local requests = ideas.requests
	W.Window.Open("ideas")
	check(ideas.requests == requests + 1, "opened: the ideas asked for (I.Request)")
	check(view.Message:IsShown() and view.Message:GetText() == "Working them out..." and view.Head:GetText() == "Working them out...",
		"not worked out yet: says so")

	-- I.Watch: drawn on the next frame.
	local list = {
		{ key = "grind:1", kind = "grind", title = "Kobolds in Fargodeep Mine", sub = "Elwynn Forest", perHour = 32000,
			confidence = "medium", basis = "yours", why = { "You killed 120 of them" }, how = { "Kill them and loot them" },
			numbers = { { label = "Kills per hour", value = "85", basis = "yours" } },
			items = { { item = 9301, n = 3, each = 1200, source = "ah", age = now - 7200 } },
			place = { map = 1429, name = "Fargodeep Mine", points = { { x = 0.4, y = 0.8, r = 0.03 } } },
			warnings = { "Prices 2 h old" }, needs = { "Skinning 1" }, oldest = now - 7200 },
		{ key = "flip:9301", kind = "flip", title = "Flip Bolt of Linen", once = 5000, confidence = "low", basis = "prices",
			oldest = now - 20000 },
		{ key = "sell:bags", kind = "sell", title = "Sell what's in your bags", confidence = "high", basis = "prices" },
	}
	local draws = state.draws
	Changed(list, true)
	check(state.draws == draws, "I.Watch: not drawn at once")
	Step()
	check(state.draws == draws + 1 and not view.Message:IsShown() and view.Head:GetText() == "3 worth your time",
		"drawn on the next frame: the list")
	local rows = view.list.rows
	check(rows[1]:IsShown() and rows[1].Title:GetText() == "Kobolds in Fargodeep Mine" and rows[1].Money:GetText() == "~3g 20s/h",
		"a row: its title and gold per hour (~: not sure)")
	check(rows[1].Sub:GetText() == "yours · Elwynn Forest" and rows[1].Dots[2]:IsShown(), "what it rests on, its place, the dots")
	check(Plain(rows[2].Money:GetText()) == "~50s once" and rows[2].Money:GetText():find("|cff888888", 1, true) == 1,
		"once, greyed: its prices are old")
	check(Plain(rows[3].Money:GetText()) == "needs a price", "no number: needs a price")
	check(rows[1]:GetScript("OnClick") ~= nil and view.Strip:GetScript("OnClick") ~= nil, "rows and the strip are buttons (the controller)")

	-- Nothing picked: the goal's details; a row picked: its details.
	check(D.texts[1]:GetText() == "Your money goal", "nothing picked: the goal on the right")
	local Q = ns.Lodestar
	local shown
	local showPlace = Q.ShowPlace
	Q.ShowPlace = function(map, points) shown = { map, points } return true end
	rows[1]:Click()
	local texts = {}
	for i, fs in ipairs(D.texts) do if fs:IsShown() then texts[#texts + 1] = Plain(fs:GetText()) end end
	local all = table.concat(texts, "\n")
	check(texts[1] == "Kobolds in Fargodeep Mine" and all:find("Confidence: medium · rests on: your own kills, loot and sales", 1, true)
		and all:find("Needs: Skinning 1", 1, true) and all:find("Prices 2 h old", 1, true), "its details: title, confidence, needs, warnings")
	check(all:find("\nWhy\n- You killed 120 of them", 1, true) and all:find("\nHow\n- Kill them and loot them", 1, true)
		and all:find("Kills per hour: 85 (yours)", 1, true), "why, how, the working with what each rests on")
	check(D.items[1]:IsShown() and Plain(D.items[1].Text:GetText()) == "Bolt of Linen x3"
		and Plain(D.items[1].Right:GetText()) == "12s AH 2 h", "its items: price, where, age")
	check(rows[1].Sel:IsShown() and not view.Strip.Sel:IsShown(), "the row picked is lit")
	check(D.map ~= nil, "Lodestar's small map is there")
	if D.map then
		check(D.map.frame:IsShown() and D.MapButton:IsShown(), "its place: the small map and Show on map")
		D.MapButton:Click()
		check(shown and shown[1] == 1429 and shown[2][1].x == 0.4, "Show on map: Lodestar's big map on the place (Q.ShowPlace)")
	end
	Q.ShowPlace = showPlace
	check(Q.ShowPlace(1429, {}) == false and Q.ShowPlace(nil, nil) == false, "Q.ShowPlace without points: nothing")
	-- The goal strip: its details.
	view.Strip:Click()
	check(D.texts[1]:GetText() == "Your money goal" and view.Strip.Sel:IsShown() and not rows[1].Sel:IsShown(), "the strip: the goal's details")

	-- Market: only the deals, and how old the prices are.
	view.tabs.market:Click()
	check(state.tab == "market" and rows[1].Title:GetText() == "Flip Bolt of Linen" and not rows[2]:IsShown(), "Market: the deals only")
	check(Plain(view.Head:GetText()) == "No auction house prices yet: open the auction house", "no scan yet: says to open the auction house")
	prices.last = now - 5 * 3600
	W.Window.Draw()
	check(Plain(view.Head:GetText()) == "Auction house prices from 5 h ago" and view.Head:GetText():find("|cffff9933", 1, true),
		"a scan: its age (orange when old)")
	prices.open = true
	W.Window.Draw()
	check(view.Head:GetText() == "The auction house is open", "the auction house open: says so")
	-- What's being worked on, above the list (and drawn again twice a second meanwhile).
	local status = { running = true, kind = "replicate", waiting = true, done = 0, total = 0 }
	W.Prices.Status = function() return status end
	W.Window.Draw()
	check(view.Head:GetText() == "Asking the auction house for all its listings...", "a whole scan asked for: says so")
	status.waiting, status.done, status.total = false, 50, 200
	Advance(0.6)
	check(view.Head:GetText() == "Reading the auction house: 25%", "reading it: how far, drawn again by itself, got " .. tostring(view.Head:GetText()))
	status.committing = true
	Advance(0.6)
	check(view.Head:GetText() == "Keeping the auction house's prices...", "keeping the prices")
	status.running = false
	status.nextFull = time() + 14 * 60 + 5
	W.Ideas.Progress = function() return { step = 7, steps = 11 }, false end
	Advance(0.6)
	check(view.Head:GetText() == "Working them out: step 7 of 11", "then the ideas: their step, got " .. tostring(view.Head:GetText()))
	W.Ideas.Progress = function() return nil, true end
	Advance(0.6)
	check(Plain(view.Head:GetText()) == "Working them out failed: /lefthy errors shows why", "a run that failed: says so, and where to look")
	W.Ideas.Progress = function() return nil, false end
	Advance(0.6)
	check(view.Head:GetText() == "The auction house is open · next whole scan in 15 min", "nothing worked on: when the next whole scan can be, got " .. tostring(view.Head:GetText()))
	W.Prices.Status, W.Ideas.Progress = nil, nil
	prices.open = false
	Changed({}, true)
	Step()
	check(view.Message:IsShown() and view.Message:GetText() == "No deals in the auction house's prices right now.", "no deals: says so")
	view.tabs.ideas:Click()
	check(view.Message:GetText():find("Nothing worth extra time right now: playing normally pays as well.", 1, true) ~= nil,
		"nothing worth it: says so, honestly")
	Changed(list, true)
	Step()

	-- Bags.
	view.tabs.bags:Click()
	check(state.tab == "bags" and M.db.window.tab == "bags", "Bags (the tab kept)")
	local function Row(name)
		for _, r in ipairs(rows) do if r:IsShown() and Plain(r.Title:GetText()):find(name, 1, true) then return r end end
	end
	local linen = Row("Bolt of Linen")
	check(linen and Plain(linen.Title:GetText()) == "Bolt of Linen x7" and Plain(linen.Money:GetText()) == "79s 80c AH",
		"stacks added up: the auction house's 7 x 12s after the cut")
	local helm = Row("Bound Helm")
	check(helm and Plain(helm.Sub:GetText()) == "keep: soulbound: you might wear it" and Plain(helm.Money:GetText()) == "25s vendor",
		"soulbound gear you might wear: kept, a vendor's price only")
	local note = Row("Kobold Note")
	check(note and Plain(note.Sub:GetText()) == "keep: a quest item", "a quest item: kept")
	check(Plain(view.Head:GetText()) == "Your bags would fetch 81s 30c", "what they'd fetch: the rest (the dagger: 1s 50c at a vendor)")
	linen:Click()
	texts = {}
	for _, fs in ipairs(D.texts) do if fs:IsShown() then texts[#texts + 1] = Plain(fs:GetText()) end end
	all = table.concat(texts, "\n")
	check(all:find("Best at the auction house: 79s 80c", 1, true) and all:find("79s 80c for all, after the cut and lost deposits (12s each)", 1, true)
		and all:find("price 2 h old · sells: 80% · confidence: high", 1, true) and all:find("21s for all", 1, true),
		"its details: both ways, the price's age, how well it sells: " .. all)

	-- Hidden: nothing runs.
	frame:Hide()
	requests, draws = ideas.requests, state.draws
	Changed(list, true)
	Advance(25)
	check(ideas.requests == requests and state.draws == draws and state.old, "closed: no requests, no drawing (only noted)")
	W.Window.Open("ideas")
	check(state.draws == draws + 1 and ideas.requests == requests + 1, "opened again on the ideas: drawn and asked")
	Advance(10.5)
	check(ideas.requests == requests + 2, "while open: asked again every 10 s")
	W.Window.SetTab("bags")
	requests = ideas.requests
	Advance(10.5)
	check(ideas.requests == requests, "on the Bags tab: the ideas aren't asked for (only Ideas and Market show them)")
	W.Window.SetTab("ideas")
	check(ideas.requests == requests + 1, "back on the ideas: asked at once")
	frame:Hide()

	-- The auction house's button.
	if W.Window.ahButton then -- (made on an earlier file's auction house: as on a fresh start)
		W.Window.ahButton:Hide()
		W.Window.ahButton = nil
		W.Window.loader:RegisterEvent("AUCTION_HOUSE_SHOW")
	end
	local ah = CreateFrame("Frame", "AuctionHouseFrame", UIParent)
	Fire("AUCTION_HOUSE_SHOW")
	check(W.Window.ahButton == nil, "not made in the event")
	Step()
	local b = W.Window.ahButton
	check(b and b:GetParent() == ah and b:IsShown() and b:GetText() == "WhyPoor?", "a WhyPoor? button on the auction house")
	b:Click()
	check(frame:IsShown() and state.tab == "market", "it opens the window on Market")
	frame:Hide()
	_G.AuctionHouseFrame = saved.AH
end

---------------------------------------------------------------------------
section("WhyPoor?: nothing in item tooltips, nothing on the bags")
do
	check(W.Bags.Line == nil and W.Bags.Coin == nil and M.db.tooltip == nil and M.db.bagCoins == nil,
		"no tooltip line and no coin in the sorted bags (no settings for them either)")
end

section("WhyPoor?: the goal")
do
	local G = W.Goal
	local C = ns.Chronicle
	local char = { daily = {} }
	local session
	local realChar, realSession = C.Char, C.Session
	C.Char = function() return char end
	C.Session = function() return session end
	PLAYER_CLASS, PLAYER_LEVEL, MONEY = "ROGUE", 30, 340000
	XP.current, XP.max = 20000, 47400 -- (level 30's 47,400 to 31, as the classic table)
	G.Forget()
	-- No trainer seen, nothing recorded.
	local g = G.Current()
	check(g and g.key == "riding40" and g.name == "Mount" and g.cost == 1000000 and g.about and g.basis == "estimate"
		and g.have == 340000 and g.rate == nil and g.eta == nil, "the mount: about 100g (guides), no rate yet")
	check(W.Window.GoalLine() == "Mount: 34g of ~100g", "the strip: " .. tostring(W.Window.GoalLine()))
	check(g.bags == W.Bags.Total() and g.bags == 8130, "what the bags would fetch")
	-- A session of 30 minutes: its rate.
	session = { played = 1800, money = 15000, xp = 30000 }
	G.Forget()
	g = G.Current()
	check(g.how == "session" and g.rate == 30000 and g.xp == 60000, "half an hour: the session's 3g per hour")
	-- Days: the last ones with the day before them.
	char.daily = {
		["2026-11-10"] = { played = 7200, gold = 10, xp = 0 },
		["2026-11-11"] = { played = 7200, gold = 20, xp = 60000 },
		["2026-11-12"] = { played = 3600, gold = 30, xp = 30000 },
	}
	G.Forget()
	g = G.Current()
	-- 10.5g at the end of the 10th (the middle of that gold piece), 34g now: 23.5g in 3 h.
	check(g.how == "days" and g.played == 10800 and math.abs(g.rate - 235000 / 3) < 1 and g.xp == 30000,
		"three hours over two days: their net gold per hour and XP per hour")
	-- 66g to go at ~7.8g/h: 8.4 h; 8.4 h x 30,000 XP: 252,766 XP from level 30 (27,400 to go, then 50,800, 54,500, 58,600, 62,800).
	check(math.abs(g.eta - 660000 / (235000 / 3)) < 1e-6 and g.etaLevel == 34, "when, and the level then: " .. tostring(g.etaLevel))
	check(W.Window.GoalLine() == "Mount: 34g of ~100g · ~7g 83s/h · at this rate at level 34", "the strip: " .. tostring(W.Window.GoalLine()))
	-- The table not matching the game: no level.
	XP.max = 47000
	G.Forget()
	g = G.Current()
	check(g.eta and g.etaLevel == nil and W.Window.GoalLine():find("at this rate in 8 h played", 1, true),
		"the XP table doesn't match the game: no level, the time instead")
	XP.max = 47400

	-- A riding trainer: its price, kept.
	SPELL_NAMES[33388], SPELL_NAMES[33391] = "Apprentice Riding", "Journeyman Riding"
	local services = { { "Apprentice Riding", 900000 }, { "Journeyman Riding", 9000000 }, { "Swimming", 10 } }
	GetNumTrainerServices = function() return #services end
	GetTrainerServiceInfo = function(i) return services[i][1], "available" end
	GetTrainerServiceCost = function(i) return services[i][2], false end
	Fire("TRAINER_SHOW")
	check(not (G.Mine().costs[33388]), "the trainer's window: read on the next frame, not in the event")
	Step()
	G.Forget()
	g = G.Current()
	check(g.cost == 900000 and not g.about and g.basis == "forever" and g.seen and W.Window.GoalLine():find("of 90g", 1, true),
		"the trainer's price (its discount in): 90g, the game's")
	-- A mount vendor's.
	MERCHANT = { { 9305, 180000, 1 }, { 9306, 1800000, 1 }, { 2589, 10, 1 } }
	Fire("MERCHANT_SHOW")
	Step()
	G.Forget()
	g = G.Current()
	check(#g.mounts == 1 and g.mounts[1].item == 9305 and g.mounts[1].price == 180000, "the mounts seen at a vendor (the goal's kind)")
	MERCHANT = {}
	-- Enough: says so.
	MONEY = 950000
	G.Forget()
	check(W.Window.GoalLine() == "Mount: 95g of 90g · you have enough", "enough: " .. tostring(W.Window.GoalLine()))
	-- Riding known: the epic mount at 60.
	KNOWN_SPELLS[33388] = true
	G.Forget()
	g = G.Current()
	check(g.key == "riding60" and g.name == "Epic mount" and g.cost == 9000000 and not g.about, "Apprentice Riding known: the epic mount")
	KNOWN_SPELLS[33391] = true
	G.Forget()
	check(G.Current() == nil and G.Why() == "done" and W.Window.GoalLine() == "No money goal: you have your riding", "Journeyman known: none")
	KNOWN_SPELLS[33388], KNOWN_SPELLS[33391] = nil, nil
	PLAYER_CLASS = "PALADIN"
	G.Forget()
	check(G.Current() == nil and G.Why() == "class", "a Paladin: no riding goal (the class quest)")
	PLAYER_CLASS = "ROGUE"
	-- The details.
	G.Forget()
	W.Window.Open("goal")
	local _, _, _, D = W.Window.View()
	local texts = {}
	for _, fs in ipairs(D.texts) do if fs:IsShown() then texts[#texts + 1] = Plain(fs:GetText()) end end
	local all = table.concat(texts, "\n")
	check(all:find("Costs 90g: the riding trainer's price, seen 1 min ago.", 1, true) and all:find("You have 95g", 1, true)
		and all:find("You have enough: off to the riding trainer!", 1, true) and all:find("From Chronicle", 1, true),
		"its details: the cost and where it's from, what you have: " .. all)
	-- Your own goal: the fields under the details, Set and Clear.
	check(D.inputs and D.inputs.Amount:IsShown() and D.inputs.Name:IsShown(), "the details end with the fields for your own goal")
	D.inputs.Amount:SetText("150")
	D.inputs.Name:SetText("Swift ram")
	local set
	for _, b in ipairs(D.buttons) do if b:IsShown() and Plain(b:GetText()) == "Set" then set = b end end
	set:Click()
	G.Forget()
	g = G.Current()
	check(g and g.custom and g.name == "Swift ram" and g.cost == 1500000 and g.costBasis == "yours", "Set: your goal, 150g, its name")
	check(W.Window.GoalLine():find("^Swift ram: 95g of 150g") ~= nil, "the strip shows it: " .. tostring(W.Window.GoalLine()))
	texts = {}
	for _, fs in ipairs(D.texts) do if fs:IsShown() then texts[#texts + 1] = Plain(fs:GetText()) end end
	all = table.concat(texts, "\n")
	check(all:find("Your own goal: 150g", 1, true) and all:find("Change your goal", 1, true) and not all:find("riding trainer", 1, true),
		"its details: your own goal, nothing about riding: " .. all)
	local clear
	for _, b in ipairs(D.buttons) do if b:IsShown() and Plain(b:GetText()) == "Clear" then clear = b end end
	check(clear ~= nil, "Clear, now there's one")
	clear:Click()
	G.Forget()
	check(G.Custom() == nil and G.Current().key == "riding40", "cleared: the mount again")
	SlashCmdList.LEFTHYTOOLS_WHYPOOR("goal 2,5 New bags")
	G.Forget()
	check(G.Custom() and G.Custom().cost == 25000 and G.Current().name == "New bags", "/whypoor goal 2,5 New bags: 2g 50s")
	SlashCmdList.LEFTHYTOOLS_WHYPOOR("goal clear")
	G.Forget()
	check(G.Custom() == nil, "/whypoor goal clear")
	-- The price graph: a bar a day.
	local realHistory = W.Prices.History
	local today = math.floor(time() / 86400)
	W.Prices.History = function()
		return { { day = today - 3, low = 1000 }, { day = today - 2, low = 1200 }, { day = today, low = 1100 } }, 1100, false
	end
	D.Begin()
	D.Graph(9301)
	D.End()
	local bars = 0
	for _, bar in ipairs(D.graph.bars) do if bar:IsShown() then bars = bars + 1 end end
	texts = {}
	for _, fs in ipairs(D.texts) do if fs:IsShown() then texts[#texts + 1] = Plain(fs:GetText()) end end
	all = table.concat(texts, "\n")
	check(D.graph:IsShown() and bars == 3 and all:find("3 days: lowest 10s, highest 12s, usually 11s · steady", 1, true),
		"the graph: a bar for each day with a price, what it says: " .. all)
	W.Prices.History = function() return { { day = today, low = 1100 } }, 1100, false end
	D.Begin()
	D.Graph(9301)
	D.End()
	check(not D.graph:IsShown(), "one day: no graph yet, says so")
	W.Prices.History = realHistory
	W.Window.View():Hide()
	C.Char, C.Session = realChar, realSession
	GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceCost = nil, nil, nil
end

---------------------------------------------------------------------------
section("WhyPoor?: switched off")
do
	local frame = W.Window.View()
	W.Window.Open()
	LT:SetModuleEnabled("whypoor", false)
	Step()
	check(not frame:IsShown() and not _G.LefthyToolsWhyPoorMinimapButton:IsShown(), "off: the window closed, the button gone")
	local mark = #PRINTED
	SlashCmdList.LEFTHYTOOLS_WHYPOOR("")
	check(not frame:IsShown() and #PRINTED > mark, "/whypoor: says it's off")
	LT:SetModuleEnabled("whypoor", true)
	Step()
	check(_G.LefthyToolsWhyPoorMinimapButton:IsShown(), "on again: the button back")
end

---------------------------------------------------------------------------
section("WhyPoor?: German")
do
	-- The German texts of these files: each has its placeholders in the same order (a %d where the code
	-- gives a number), and the module's name isn't translated.
	local de, src = { LOCALE = "deDE", L = {} }, {}
	for _, file in ipairs(SOURCES) do
		if file.name == "Locales/deDE.lua" then
			assert(load(file.src, "@deDE.lua"))("LefthyTools", de)
		elseif file.name:find("^Modules/WhyPoor/") and (file.name:find("WhyPoor.lua", 1, true) or file.name:find("Window.lua", 1, true)
				or file.name:find("Bags.lua", 1, true) or file.name:find("Goal.lua", 1, true)) then
			src[#src + 1] = (("\n" .. file.src):gsub("\n%s*%-%-[^\n]*", "\n")) -- (comments aren't lookups)
		end
	end
	local function Holes(text) local out = {} for h in text:gmatch("%%[%%sd]") do out[#out + 1] = h end return table.concat(out) end
	local keys, bad = 0, {}
	for _, text in ipairs(src) do
		for key in text:gmatch('L%["(.-)"%]') do
			keys = keys + 1
			local german = de.L[key]
			if type(german) ~= "string" or Holes(german) ~= Holes(key) then bad[#bad + 1] = key end
		end
	end
	check(keys > 100 and #bad == 0, "every text has its German with the same placeholders: " .. table.concat(bad, " | "))
	check(de.L["Open WhyPoor?"]:find("WhyPoor?", 1, true) and de.L["Ideas"] == "Ideen" and de.L["Market"] == "Markt",
		"German tabs, the name kept")
end

-- Put back.
W.Prices, W.Ideas = saved.Prices, saved.Ideas
BAGS, MONEY, PLAYER_CLASS, PLAYER_LEVEL = saved.BAGS, saved.MONEY, saved.CLASS, saved.LEVEL
XP.current, XP.max = saved.XP[1], saved.XP[2]
BAG_STACKS["0:1"], BAG_STACKS["0:5"], BOUND[2], QUEST_BAG_ITEMS[9303] = nil, nil, nil, nil
SPELL_NAMES[33388], SPELL_NAMES[33391] = nil, nil
W.Goal.Forget()
