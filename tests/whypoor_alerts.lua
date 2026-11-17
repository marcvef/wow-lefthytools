-- WhyPoor?'s price alerts (Alerts.lua) on the real price engine: what's typed (gold, "2g 50s", "1,5", percent), the
-- setting's defaults and its rows, a line after a scan with every crossing in it (item links, the reasons), once per
-- crossing (under and over again only after going back past the margin; a move once a day each way, against the day
-- before's close; the setting's move not for a few copper, an item's own move is), an item's own move winning over
-- the setting, the setting off (and /whypoor alerts on/off), held in a fight until it ends, the sound setting, the
-- module off, items looked at a few a frame and nothing idle, the hook in Prices.lua (a search and a full scan),
-- /whypoor alerts' list, the Stocks tab's details (the fields, Set, Clear, Enter, wrong input, typed text kept
-- through redraws, an unwatched item, the fields hidden elsewhere).
-- Needs: no other file.
local suite = ...
local check, section, ns, LT = suite.check, suite.section, suite.ns, suite.LT

local W = ns.WhyPoor
local A, P, St = W.Alerts, W.Prices, W.Stocks
local WP = LT:GetModule("whypoor")
local DAY = 86400
local key = P.HomeKey()
local function Step(n) for _ = 1, n or 1 do Advance(1 / 60) end end
local function Plain(text) -- (colours off; a link: its name)
	return (tostring(text or ""):gsub("|H.-|h%[(.-)%]|h", "%1"):gsub("|H.-|h(.-)|h", "%1"):gsub("|cn[^:]*:", "")
		:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end
local mark = #PRINTED
local function Said() -- (the lines printed since the last look, plain)
	local out = {}
	for i = mark + 1, #PRINTED do out[#out + 1] = PRINTED[i] end
	mark = #PRINTED
	return out
end
local function Lines(list)
	local out = {}
	for i, line in ipairs(list) do out[i] = Plain(line) end
	return table.concat(out, " / ")
end

local watchWas, alertsWas, firedWas = W.DB().watch, W.DB().alerts, W.DB().alertsFired
W.DB().watch, W.DB().alerts, W.DB().alertsFired = {}, {}, {}
local BAR, CLOTH, STONE, GEM = 9801, 9802, 9803, 9804
ITEMS[BAR] = { name = "Alertium Bar", quality = 1 }
ITEMS[CLOTH] = { name = "Alert Cloth", quality = 1 }
ITEMS[STONE] = { name = "Quiet Stone", quality = 2 }
ITEMS[GEM] = { name = "Unwatched Gem", quality = 3 }
for _, item in ipairs({ BAR, CLOTH, STONE }) do St.Watch(item) end

-- A scan of these prices ({ item, low }, a second after the last), then the frames that look at them.
local function Scan(list)
	Advance(1)
	for _, s in ipairs(list) do P.Store(key, s[1], s[2], 5, time()) end
	A.Scanned({ kind = "search", key = key })
	Step(4)
	return Said()
end

---------------------------------------------------------------------------
section("WhyPoor? alerts: what's typed")
check(A.ParseMoney("1.5") == 15000 and A.ParseMoney("1,5") == 15000 and A.ParseMoney("150") == 1500000
	and A.ParseMoney("150g") == 1500000 and A.ParseMoney("150 G") == 1500000, "gold: 1.5, 1,5, 150, 150g")
check(A.ParseMoney("2g 50s") == 25000 and A.ParseMoney(" 2g50s ") == 25000 and A.ParseMoney("15s") == 1500
	and A.ParseMoney("80c") == 80 and A.ParseMoney("80k") == 80 and A.ParseMoney("1.5g") == 15000
	and A.ParseMoney("1g 2s 3c") == 10203, "with units: 2g 50s, 15s, 80c (80k: German copper), 1.5g, 1g 2s 3c")
local bad = {}
for _, text in ipairs({ "", "  ", "abc", "-5", "0", "0g", "1.2.3", "5x", "15 s 3", "g", "999999g", "1e5" }) do
	if A.ParseMoney(text) ~= nil then bad[#bad + 1] = "'" .. text .. "'" end
end
check(#bad == 0, "not a price: empty, letters, below 1c, signs, more than the gold cap: " .. table.concat(bad, ", "))
check(A.ParsePct("30") == 30 and A.ParsePct("30%") == 30 and A.ParsePct(" 12,5 % ") == 12.5 and A.ParsePct("abc") == nil
	and A.ParsePct("0") == nil and A.ParsePct("2000") == nil and A.ParsePct("") == nil, "percent: 30, 30%, 12,5; not 0, 2000, letters")
check(A.MoneyText(25080) == "2g 50s 80c" and A.MoneyText(1500) == "15s" and A.MoneyText(10005) == "1g 5c" and A.MoneyText(nil) == "",
	"a price for a field: exactly, as typed")

---------------------------------------------------------------------------
section("WhyPoor? alerts: the setting")
check(WP.defaults.moveAlerts == true and WP.defaults.movePct == 30 and WP.defaults.alertSound == false
	and WP.db.moveAlerts == true and WP.db.movePct == 30, "on by default: moves of 30%; no sound")
check(REGISTERED_SETTINGS.LefthyTools_whypoor_moveAlerts and REGISTERED_SETTINGS.LefthyTools_whypoor_movePct
	and REGISTERED_SETTINGS.LefthyTools_whypoor_alertSound, "its rows on WhyPoor?'s settings page")
check(A.DefaultMove() == 30 and select(2, A.MovePct(CLOTH)) == false, "every watched item: the setting's move")

---------------------------------------------------------------------------
section("WhyPoor? alerts: after a scan")
-- Yesterday: the bar 16s, the cloth 10s, the stone 5c.
local today = time()
for _, s in ipairs({ { BAR, 1600 }, { CLOTH, 1000 }, { STONE, 5 } }) do P.Store(key, s[1], s[2], 5, today - DAY) end
check(A.Set(BAR, { below = 1500, above = 3000 }) and A.Has(BAR) and not A.Has(CLOTH), "the bar's rules kept")
check(not A.frame:IsShown(), "nothing runs before a scan")
local sounds = #SOUNDS
local said = Scan({ { BAR, 1480 }, { CLOTH, 1420 }, { STONE, 9 } })
check(#said == 1, "one line for the scan: " .. Lines(said))
local line = said[1] or ""
check(Plain(line) == "WhyPoor?: Alertium Bar 14s 80c (under your 15s) · Alert Cloth 14s 20c (+42% today)",
	"under the bar's line, the cloth's move against yesterday: " .. Plain(line))
check(line:find("|Hitem:" .. BAR, 1, true) and line:find("|Hitem:" .. CLOTH, 1, true), "the items as links (a click shows them)")
check(not Plain(line):find("Quiet Stone", 1, true), "5c to 9c: +80%, but 4c: not for the setting's move")
check(#SOUNDS == sounds and not A.frame:IsShown(), "no sound (the setting is off); the frame hidden when done")
said = Scan({ { BAR, 1470 }, { CLOTH, 1450 }, { STONE, 9 } })
check(#said == 0, "the next scan, still under, still up: nothing again: " .. Lines(said))
said = Scan({ { BAR, 1550 } })
said = #said + #Scan({ { BAR, 1490 } })
check(said == 0, "back over by less than 5% and under again: not again")
said = Scan({ { BAR, 1600 } })
check(#said == 0, "over by more than 5%: nothing said, ready again")
said = Scan({ { BAR, 1450 } })
check(#said == 1 and Plain(said[1]) == "WhyPoor?: Alertium Bar 14s 50c (under your 15s)", "under again: told again: " .. Lines(said))
said = Scan({ { BAR, 3200 } })
check(#said == 1 and Plain(said[1]) == "WhyPoor?: Alertium Bar 32s (over your 30s, +100% today)",
	"over its line and up 100%: both in its part: " .. Lines(said))
said = Scan({ { BAR, 3300 } })
check(#said == 0, "still over: nothing")
said = Scan({ { BAR, 2900 } })
said = #said + #Scan({ { BAR, 3100 } })
check(said == 0, "under by less than 5% and over again: not again")
said = Scan({ { BAR, 2000 } })
check(#said == 0, "well under: ready again (and +25% isn't a big move)")
said = Scan({ { BAR, 3500 } })
check(#said == 1 and Plain(said[1]) == "WhyPoor?: Alertium Bar 35s (over your 30s)", "over again: told; up 119% today told already: " .. Lines(said))
local fired = W.DB().alertsFired[key]
check(fired and fired[BAR] and fired[BAR].a == true and fired[BAR].up == P.Today(), "what was told is kept (a /reload doesn't say it again)")

-- Moves: once a day each way, against the day before's close.
said = Scan({ { CLOTH, 600 } })
check(#said == 1 and Plain(said[1]) == "WhyPoor?: Alert Cloth 6s (-40% today)", "down 40% the same day: the other way, told: " .. Lines(said))
said = Scan({ { CLOTH, 1500 } })
said = #said + #Scan({ { CLOTH, 650 } })
check(said == 0, "up and down again the same day: not again")
MOCK_EPOCH = MOCK_EPOCH + DAY -- (the next day: yesterday's close was 6s 50c)
said = Scan({ { CLOTH, 900 } })
check(#said == 1 and Plain(said[1]) == "WhyPoor?: Alert Cloth 9s (+38% today)", "the next day: against yesterday's close: " .. Lines(said))
said = Scan({ { CLOTH, 800 } })
check(#said == 0, "+23%: not a big move")

-- An item's own move wins over the setting (and isn't held to a few copper).
A.Set(STONE, { move = 50 })
check(select(1, A.MovePct(STONE)) == 50 and select(2, A.MovePct(STONE)) == true, "the stone's own move: 50%")
said = Scan({ { STONE, 14 } })
check(#said == 1 and Plain(said[1]) == "WhyPoor?: Quiet Stone 14c (+56% today)", "9c to 14c: its own move, told: " .. Lines(said))

-- Prices not this scan's, none listed, a friend's: nothing.
P.Store(key, CLOTH, 300, 5, time() - 3600)
A.Scanned({ kind = "search", key = key })
Step(4)
check(#Said() == 0, "a price an hour old: not this scan's, not told")
said = Scan({ { CLOTH, nil } })
check(#said == 0, "none listed: nothing to say")

---------------------------------------------------------------------------
section("WhyPoor? alerts: the setting off, a fight, the sound, the module off")
SlashCmdList.LEFTHYTOOLS_WHYPOOR("alerts off")
said = Said()
check(WP.db.moveAlerts == false and A.DefaultMove() == nil and Plain(said[1]) == "WhyPoor?: big moves of watched items: off.",
	"/whypoor alerts off: the setting off: " .. Lines(said))
check(Scan({ { CLOTH, 2000 } })[1] == nil, "a big move with the setting off: nothing")
SlashCmdList.LEFTHYTOOLS_WHYPOOR("alerts on")
said = Said()
check(WP.db.moveAlerts == true and Plain(said[1]) == "WhyPoor?: big moves of watched items: on (30% or more in a day).",
	"/whypoor alerts on: on again: " .. Lines(said))
check(Scan({ { STONE, 4 } })[1] ~= nil, "an item's own move: down 56%, told")

EnterCombat()
said = Scan({ { BAR, 1000 } })
check(#said == 0 and A.listening, "in a fight: held, PLAYER_REGEN_ENABLED listened to")
said = Scan({ { CLOTH, 300 } })
check(#said == 0, "a second scan in the fight: held too")
LeaveCombat()
said = Said()
check(#said == 1 and Plain(said[1]) == "WhyPoor?: Alertium Bar 10s (under your 15s, -71% today) · Alert Cloth 3s (-54% today)"
	and not A.listening, "the fight over: one line with both, not listened to any more: " .. Lines(said))

WP.db.alertSound = true
sounds = #SOUNDS
said = Scan({ { BAR, 3600 } })
check(#said == 1 and #SOUNDS == sounds + 1 and SOUNDS[#SOUNDS] == A.SOUND, "the sound setting on: a coin sound with the line")
WP.db.alertSound = false

LT:SetModuleEnabled("whypoor", false)
Step()
A.Scanned({ kind = "search", key = key })
check(not A.frame:IsShown(), "the module off: a scan isn't looked at")
LT:SetModuleEnabled("whypoor", true)
Step()
Said()

---------------------------------------------------------------------------
section("WhyPoor? alerts: a few a frame; the hook in Prices.lua")
do
	local many = {}
	for i = 1, 60 do
		local id = 9850 + i
		ITEMS[id] = { name = "Bulk Alert " .. i, quality = 1 }
		St.Watch(id)
		many[#many + 1] = id
		P.Store(key, id, 1000, 5, time() - DAY)
	end
	for _, id in ipairs(many) do P.Store(key, id, 2000, 5, time()) end
	A.Scanned({ kind = "search", key = key })
	local frames = 0
	while A.frame:IsShown() and frames < 50 do Step() frames = frames + 1 end
	local text = Plain(Said()[1])
	check(frames >= math.ceil(63 / A.PER_FRAME) and not A.frame:IsShown(), "63 watched items over " .. frames .. " frames, "
		.. A.PER_FRAME .. " a frame, then hidden")
	check(text:find("Bulk Alert 1 20s (+100% today)", 1, true) and text:find("and 50 more", 1, true),
		"at most " .. A.MOST .. " in the line, then \"and 50 more\": " .. text:sub(1, 80) .. "...")
	for _, id in ipairs(many) do St.Unwatch(id) end
end

-- Two scans in the same second (a full scan, then a search of the item): the second's price is looked at all the
-- same; the same price again isn't.
local T = time()
P.Store(key, BAR, 3600, 5, T)
A.Scanned({ kind = "search", key = key })
Step(4)
check(#Said() == 0, "the same price again in the same second: nothing")
P.Store(key, BAR, 1300, 5, T)
A.Scanned({ kind = "search", key = key })
Step(4)
said = Said()
check(#said == 1 and Plain(said[1]) == "WhyPoor?: Alertium Bar 13s (under your 15s)", "another price in the same second: told: " .. Lines(said))

-- A search on the auction house and a full scan: P.Finish tells Alerts.lua.
W.DB().prices.replicated = time()
Fire("AUCTION_HOUSE_SHOW")
Step()
AH_COMMODITY[BAR] = true
AH_LISTINGS[BAR] = { { 3700, 4 } }
Said()
check(P.ScanItems({ BAR }), "a search of the bar")
Advance(3)
said = Said()
check(#said == 1 and Plain(said[1]) == "WhyPoor?: Alertium Bar 37s (over your 30s)", "searched: told after it: " .. Lines(said))
AH_LISTINGS[BAR] = { { 1200, 2 } }
W.DB().prices.replicated = time() - 1000
check(P.ScanFull(), "a full scan")
Advance(4)
said = Said()
check(#said == 1 and Plain(said[1]) == "WhyPoor?: Alertium Bar 12s (under your 15s)", "the full scan kept: told after it: " .. Lines(said))
AH_LISTINGS[BAR], AH_COMMODITY[BAR] = nil, nil
Fire("AUCTION_HOUSE_CLOSED")
Step()

---------------------------------------------------------------------------
section("WhyPoor? alerts: /whypoor alerts")
A.Set(GEM, { below = 500 })
SlashCmdList.LEFTHYTOOLS_WHYPOOR("alerts")
said = Said()
check(#said == 4 and Plain(said[1]) == "WhyPoor?: big moves of watched items: 30% or more in a day (/whypoor alerts off)."
	and Plain(said[2]) == "WhyPoor?: Alertium Bar: under 15s, over 30s" and Plain(said[3]) == "WhyPoor?: Quiet Stone: moves of 50% or more"
	and Plain(said[4]) == "WhyPoor?: Unwatched Gem: under 5s (not watched: paused)", "the setting, then each item's alerts: " .. Lines(said))
check(said[2]:find("|Hitem:" .. BAR, 1, true), "as links")
SlashCmdList.LEFTHYTOOLS_WHYPOOR("alerts what")
check(Plain(Said()[1]):find("/whypoor alerts on or off", 1, true), "anything else: how it goes")
SlashCmdList.LEFTHYTOOLS_WHYPOOR("help")
check(Lines(Said()):find("/whypoor alerts [on | off]", 1, true), "in the help")
A.Clear(GEM)

---------------------------------------------------------------------------
section("WhyPoor? alerts: in the Stocks tab's details")
SlashCmdList.LEFTHYTOOLS_WHYPOOR("stocks")
Step()
local frame, state, view, D = W.Window.View()
local function Texts()
	local out = {}
	for _, fs in ipairs(D.texts) do if fs:IsShown() then out[#out + 1] = Plain(fs:GetText()) end end
	return table.concat(out, "\n")
end
local function Button(label)
	for _, b in ipairs(D.buttons) do if b:IsShown() and Plain(b:GetText()) == label then return b end end
end
local function Type(box, text)
	box:SetText(text)
	box._scripts.OnTextChanged(box, true)
end
St.Pick(BAR)
Step()
local i = A.inputs
check(Texts():find("Price alerts", 1, true) and Texts():find("Now: under 15s, over 30s, moves of 30% or more (all watched items).", 1, true),
	"a watched item: Price alerts, what's set now: " .. Texts())
check(i and i.Below:IsShown() and i.Above:IsShown() and i.Move:IsShown() and i.BelowLabel:GetText() == "Below"
	and i.MoveLabel:GetText() == "Moves over", "the fields Below, Above, Moves over ... %")
check(i.Below:GetText() == "15s" and i.Above:GetText() == "30s" and i.Move:GetText() == "", "filled with its rules")
check(Button("Set") ~= nil and Button("Clear") ~= nil, "Set and Clear")
Type(i.Below, "abc")
W.Window.Draw()
check(i.Below:GetText() == "abc", "what's typed stays through a redraw")
Button("Set"):Click()
check(Texts():find("Type a price like 15s, 2g 50s or 1.5 (gold).", 1, true) and A.Get(BAR).below == 1500, "not a price: said, nothing kept")
Type(i.Below, "2g")
Type(i.Above, "1.5")
Button("Set"):Click()
check(Texts():find("Below has to be under Above.", 1, true) and A.Get(BAR).above == 3000, "below over above: said")
Type(i.Below, "12s")
Type(i.Above, "2g 50s")
Type(i.Move, "abc")
Button("Set"):Click()
check(Texts():find("Type the move in percent, like 30.", 1, true), "not a percent: said")
Type(i.Move, "45%")
Said()
Button("Set"):Click()
local r = A.Get(BAR)
said = Said()
check(r.below == 1200 and r.above == 25000 and r.move == 45 and Plain(said[1]) == "WhyPoor?: price alerts for Alertium Bar: under 12s, over 2g 50s, moves of 45% or more.",
	"Set: kept, said in chat: " .. Lines(said))
check(not Texts():find("Type", 1, true) and Texts():find("Now: under 12s, over 2g 50s, moves of 45% or more.", 1, true)
	and i.Below:GetText() == "12s" and i.Above:GetText() == "2g 50s" and i.Move:GetText() == "45", "the details show them")
check(W.DB().alertsFired[key][BAR] == nil, "new lines: what was told forgotten (told again when crossed)")
Type(i.Below, "")
Type(i.Above, "")
Type(i.Move, "60")
i.Move._scripts.OnEnterPressed(i.Move)
said = Said()
check(A.Get(BAR).below == nil and A.Get(BAR).move == 60 and #said == 1, "Enter in a field: Set; an empty field: that rule gone")
Button("Clear"):Click()
said = Said()
check(not A.Has(BAR) and Plain(said[1]) == "WhyPoor?: price alerts for Alertium Bar cleared." and i.Move:GetText() == ""
	and Button("Clear") == nil, "Clear: gone, said, the fields empty, no Clear")
check(Texts():find("Now: moves of 30% or more (all watched items).", 1, true), "the setting's move still on it")
Button("Set"):Click()
check(Texts():find("Type a price or a percent first.", 1, true), "Set with nothing typed: said")
St.Pick(GEM)
Step()
check(Texts():find("Add it to your watch list for price alerts in chat after your scans.", 1, true) and not i.Below:IsShown()
	and not Texts():find("Type a price", 1, true), "an unwatched item: watch it first, no fields")
St.Pick(BAR)
Step()
check(i.Below:IsShown(), "a watched one again: the fields")
view.tabs.bags:Click()
Step()
check(not i.Below:IsShown() and not i.Move:IsShown() and not i.Pct:IsShown(), "another tab: the fields hidden")
frame:Hide()

-- German: the same placeholders.
do
	local de, src = { LOCALE = "deDE", L = {} }, ""
	for _, file in ipairs(SOURCES) do
		if file.name == "Locales/deDE.lua" then
			assert(load(file.src, "@deDE.lua"))("LefthyTools", de)
		elseif file.name == "Modules/WhyPoor/Alerts.lua" then
			src = (("\n" .. file.src):gsub("\n%s*%-%-[^\n]*", "\n"))
		end
	end
	local function Holes(text) local out = {} for h in text:gmatch("%%[%%sd]") do out[#out + 1] = h end return table.concat(out) end
	local keys, bad = 0, {}
	for k in src:gmatch('L%["(.-)"%]') do
		keys = keys + 1
		if type(de.L[k]) ~= "string" or Holes(de.L[k]) ~= Holes(k) then bad[#bad + 1] = k end
	end
	check(keys > 20 and #bad == 0, "every text has its German with the same placeholders: " .. table.concat(bad, " | "))
end

-- Put back (the clock stays a day on, as time went by).
local h = P.House(key)
for _, item in ipairs({ BAR, CLOTH, STONE, GEM }) do
	h.items[item], h.daily[item], h.scans[item], h.unwatched[item] = nil, nil, nil, nil
end
for i = 1, 60 do
	h.items[9850 + i], h.daily[9850 + i], h.scans[9850 + i], h.unwatched[9850 + i] = nil, nil, nil, nil
end
P.Changed()
W.DB().watch, W.DB().alerts, W.DB().alertsFired = watchWas, alertsWas, firedWas
