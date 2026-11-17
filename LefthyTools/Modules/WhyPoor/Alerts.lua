local _, ns = ...
local LT = ns.LT
local L = ns.L
local W = ns.WhyPoor or {}
ns.WhyPoor = W

-- Price alerts for watched items (W.Alerts, A): after each of your own auction house scans, ONE line in chat with
-- what crossed a line: "WhyPoor?: [Copper Bar] 14s 80c (under your 15s) · [Linen Cloth] 1s 20c (+42% today)".
-- No pop-ups, nothing outside chat; informational only. docs/whypoor.md ("Price alerts") has the rules.
--   * An item's own rules (LefthyToolsWhyPoorDB.alerts[item] = { below = copper, above = copper, move = percent },
--     account-wide), set in the Stocks tab's details of a watched item (A.Details, one hook line in Stocks.lua's
--     T.Details) or cleared there; the module's setting moveAlerts / movePct: a move of every watched item (on,
--     30%: an item's own move wins).
--   * Once per crossing: under (over) fires once, then again only after the price went back over (under) the line
--     by MARGIN; a move fires once a day per direction. What fired is kept per auction house and item
--     (LefthyToolsWhyPoorDB.alertsFired[house][item] = { b = true, a = true, up = day, down = day }), so a /reload
--     or the next session doesn't say it again.
--   * Only your own scans' prices (P.Entry: the house's own items, never a friend's), only when its saved text changed
--     since the last look (A.seen: two scans in one second count) and its scan at most FRESH old. A move: against the latest earlier day's close (the
--     watched item's daily history), else that day's lowest, from the last REF_DAYS days.
-- What it costs: nothing idle. Prices.lua's P.Finish (a scan done: full or item by item) calls A.Scanned, which only
-- notes the house; a frame of its own (A.frame) then goes over the watched items PER_FRAME a frame (a decode the
-- engine caches and two days of the daily text each) and hides. In a fight the line waits for its end
-- (PLAYER_REGEN_ENABLED, listened to only then).

local A = { queue = {}, found = {}, seen = {} }
W.Alerts = A

A.MARGIN = 0.05     -- under/over fires again only after the price went back past the line by this much
A.FRESH = 15 * 60   -- a price older than this (seconds) isn't told about: not this scan's
A.REF_DAYS = 7      -- a move's earlier day: within this many days
A.MOVE_MIN = 10     -- the setting's move of every watched item: at least this many copper (not 1c to 2c)
A.PER_FRAME = 25    -- watched items looked at a frame
A.MOST = 10         -- items in the line at most ("and 3 more")
A.MAX = 2147483647  -- copper at most (the game's gold cap)
A.SOUND = SOUNDKIT and SOUNDKIT.LOOT_WINDOW_COIN_SOUND or 120

local GREY, GREEN, RED, ORANGE, SEP = "|cff888888", "|cff40c040", "|cffff4040", "|cffff9933", " · "
local DAY = 86400

local function P()
	return W.Prices
end

local function Module()
	return W.module
end

local function Print(msg)
	local m = Module()
	if m and m.Print then
		m:Print(msg)
	else
		LT.Print(msg, "WhyPoor?")
	end
end

---------------------------------------------------------------------------
-- The saved rules and what fired
---------------------------------------------------------------------------

-- The rules, by item (an empty table before the saved variables are there: nothing kept in it).
function A.Rules()
	local db = W.DB and W.DB()
	if not db then
		return {}
	end
	db.alerts = type(db.alerts) == "table" and db.alerts or {}
	return db.alerts
end

-- What fired, by house, then item.
function A.Fired()
	local db = W.DB and W.DB()
	if not db then
		return {}
	end
	db.alertsFired = type(db.alertsFired) == "table" and db.alertsFired or {}
	return db.alertsFired
end

-- An item's rules (nil: none).
function A.Get(item)
	local r = A.Rules()[item]
	return type(r) == "table" and (r.below or r.above or r.move) and r or nil
end

function A.Has(item)
	return A.Get(item) ~= nil
end

-- The setting: a move of every watched item (percent; nil: off).
function A.DefaultMove()
	local m = Module()
	local db = m and m.db
	if not (type(db) == "table" and db.moveAlerts ~= false) then
		return nil
	end
	local pct = tonumber(db.movePct) or 30
	return pct > 0 and pct or nil
end

-- An item's move in percent and whether it's its own (else the setting's); nil: none.
function A.MovePct(item)
	local r = A.Get(item)
	if r and r.move then
		return r.move, true
	end
	return A.DefaultMove(), false
end

-- Keeps an item's rules (rules: { below, above, move }; none of them: cleared); what fired for it is forgotten
-- (new lines: told again when they're crossed).
function A.Set(item, rules)
	if type(item) ~= "number" or not (W.DB and W.DB()) then
		return false
	end
	local r = type(rules) == "table" and { below = rules.below, above = rules.above, move = rules.move } or {}
	A.Rules()[item] = (r.below or r.above or r.move) and r or nil
	for _, house in pairs(A.Fired()) do
		if type(house) == "table" then
			house[item] = nil
		end
	end
	return true
end

function A.Clear(item)
	return A.Set(item, nil)
end

---------------------------------------------------------------------------
-- Money and percent typed
---------------------------------------------------------------------------

local UNIT = { g = 10000.0, s = 100.0, c = 1.0, k = 1.0 } -- (k: German copper, "Kupfer"; floats: no overflow)

-- What's typed as copper: "1.5" and "1,5" are gold, "150g", "15s", "80c" (or 80k), "2g 50s", "1.5g". nil: not a
-- price (empty, nothing above 0, more than the gold cap, letters or signs that aren't one).
function A.ParseMoney(text)
	text = strtrim(tostring(text or "")):lower():gsub(",", ".")
	if text == "" then
		return nil
	end
	local copper
	if not text:find("[gsck]") then
		local gold = text:find("^%d*%.?%d+$") and tonumber(text)
		copper = gold and gold * 10000.0
	else
		local total = 0
		local rest = text:gsub("(%d*%.?%d+)%s*([gsck])", function(n, unit)
			total = total + (tonumber(n) or 0) * UNIT[unit]
			return " "
		end)
		copper = not rest:find("%S") and total or nil
	end
	copper = copper and math.floor(copper + 0.5)
	if not copper or copper <= 0 or copper > A.MAX then
		return nil
	end
	return copper
end

-- A percent typed: "30", "30%", "12,5". nil: not one (above 0, 1000 at most).
function A.ParsePct(text)
	text = strtrim(tostring(text or "")):gsub(",", "."):gsub("%%$", "")
	text = strtrim(text)
	local pct = text:find("^%d*%.?%d+$") and tonumber(text)
	if not pct or pct <= 0 or pct > 1000 then
		return nil
	end
	return math.floor(pct * 10 + 0.5) / 10
end

-- Copper exactly, for a field: "2g 50s", "15s", "1g 5c" (German: k for copper).
function A.MoneyText(copper)
	copper = tonumber(copper)
	if not copper or copper <= 0 then
		return ""
	end
	copper = math.floor(copper + 0.5)
	local parts = {}
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	if g > 0 then
		parts[#parts + 1] = L["%dg"]:format(g)
	end
	if s > 0 then
		parts[#parts + 1] = L["%ds"]:format(s)
	end
	if c > 0 then
		parts[#parts + 1] = L["%dc"]:format(c)
	end
	return table.concat(parts, " ")
end

function A.PctText(pct)
	local text = ("%.1f"):format(pct):gsub("%.0$", "")
	return LT.Decimal and LT.Decimal(text) or text
end

-- An item's rules in words: "under 15s, over 2g, moves of 30% or more" (its own move, else the setting's,
-- said so). nil: none.
function A.RulesText(item, withDefault)
	local r = A.Get(item)
	local parts = {}
	if r and r.below then
		parts[#parts + 1] = L["under %s"]:format(W.Money(r.below))
	end
	if r and r.above then
		parts[#parts + 1] = L["over %s"]:format(W.Money(r.above))
	end
	local pct, own = A.MovePct(item)
	if pct and (own or withDefault) then
		parts[#parts + 1] = own and L["moves of %s%% or more"]:format(A.PctText(pct))
			or L["moves of %s%% or more (all watched items)"]:format(A.PctText(pct))
	end
	return parts[1] and table.concat(parts, ", ") or nil
end

-- An item's link for chat (a click shows it), else its name, else #id.
function A.Link(item)
	local ok, name, link = pcall(C_Item.GetItemInfo, ("item:%d"):format(item))
	if ok and type(link) == "string" and not LT.IsSecret(link) then
		return link
	end
	name = ok and type(name) == "string" and not LT.IsSecret(name) and name or ("#" .. item)
	return ("|cffffffff|Hitem:%d|h[%s]|h|r"):format(item, name)
end

---------------------------------------------------------------------------
-- After a scan
---------------------------------------------------------------------------

function A.On()
	local m = Module()
	return m and m.enabled and W.DB and W.DB() ~= nil and P() ~= nil and true or false
end

-- Prices.lua's P.Finish: a scan done (scan.key: the house it read). Only noted; the frame does the rest.
function A.Scanned(scan)
	if not A.On() then
		return
	end
	local key = type(scan) == "table" and scan.key or P().HomeKey()
	if type(key) ~= "string" then
		return
	end
	A.queue[key] = true
	A.frame:Show()
end

-- The latest earlier day's price (within REF_DAYS) of an item in a house: its close from the watched item's daily
-- history (its first entries only), else that day's lowest from the house's 14 days.
function A.PrevClose(h, e, item, today)
	local text = type(h) == "table" and type(h.daily) == "table" and h.daily[item]
	if type(text) == "string" then
		local n = 0
		for part in text:gmatch("[^;]+") do
			local d = P().DayEntry(part)
			if d and d[1] < today then
				return d[1] >= today - A.REF_DAYS and d[5] or nil
			end
			n = n + 1
			if n >= 3 then
				break
			end
		end
	end
	for _, d in ipairs(e.days or {}) do -- (newest first)
		if d[1] < today then
			return d[1] >= today - A.REF_DAYS and d[2] or nil
		end
	end
end

-- An item looked at after a scan of a house (job: { key, h, now }): what crossed, into A.found.
function A.Check(job, item)
	if type(item) ~= "number" then
		return
	end
	local r = A.Get(item)
	local pct, own = A.MovePct(item)
	if not (r or pct) then
		return
	end
	local text = type(job.h) == "table" and type(job.h.items) == "table" and job.h.items[item]
	local seen = A.seen[job.key]
	if not seen then
		seen = {}
		A.seen[job.key] = seen
	end
	if not text or seen[item] == text then
		return -- (never seen, or looked at already: the same scan, the same price)
	end
	seen[item] = text
	local e = P().Entry(job.key, item)
	if not (type(e) == "table" and e.low and e.seen) then
		return -- (none listed: nothing to say)
	end
	if job.now - e.seen > A.FRESH then
		return -- (not this scan's)
	end
	local fired = A.Fired()
	local house = type(fired[job.key]) == "table" and fired[job.key] or {}
	local st = type(house[item]) == "table" and house[item] or {}
	local low, reasons = e.low, {}
	if r and r.below then
		if low < r.below then
			if not st.b then
				st.b = true
				reasons[#reasons + 1] = L["under your %s"]:format(W.Money(r.below))
			end
		elseif low > r.below * (1 + A.MARGIN) then
			st.b = nil
		end
	end
	if r and r.above then
		if low > r.above then
			if not st.a then
				st.a = true
				reasons[#reasons + 1] = L["over your %s"]:format(W.Money(r.above))
			end
		elseif low < r.above * (1 - A.MARGIN) then
			st.a = nil
		end
	end
	if pct then
		local today = P().Today(e.seen)
		local ref = A.PrevClose(job.h, e, item, today)
		if ref and ref > 0 and low ~= ref then
			local change = (low - ref) / ref
			local side = change > 0 and "up" or "down"
			if math.abs(change) * 100 >= pct - 1e-9 and (own or math.abs(low - ref) >= A.MOVE_MIN) and st[side] ~= today then
				st[side] = today
				local whole = math.floor(math.abs(change) * 100 + 0.5)
				reasons[#reasons + 1] = L["%s today"]:format(change > 0 and (GREEN .. "+" .. whole .. "%|r")
					or (RED .. "-" .. whole .. "%|r"))
			end
		end
	end
	if next(st) then
		house[item] = st
		fired[job.key] = house
	elseif house[item] then
		house[item] = nil
	end
	if reasons[1] then
		A.Found(item, low, reasons)
	end
end

-- What crossed, waiting for the line (one per item: a newer one replaces it).
function A.Found(item, low, reasons)
	for _, f in ipairs(A.found) do
		if f.item == item then
			f.low, f.reasons = low, reasons
			return
		end
	end
	A.found[#A.found + 1] = { item = item, low = low, reasons = reasons }
end

-- A frame's work: the next house's watched items, PER_FRAME of them; all done: the line.
function A.Step()
	local job = A.job
	if not job then
		local key = next(A.queue)
		if not key then
			A.frame:Hide()
			A.Flush()
			return
		end
		A.queue[key] = nil
		local saved = P().Saved()
		local items = {}
		local db = W.DB and W.DB()
		for _, item in ipairs(db and type(db.watch) == "table" and db.watch or {}) do
			items[#items + 1] = item
		end
		job = { key = key, items = items, i = 1, now = time(),
			h = saved and type(saved.houses) == "table" and saved.houses[key] or nil }
		A.job = job
	end
	local stop = math.min(#job.items, job.i + A.PER_FRAME - 1)
	for i = job.i, stop do
		A.Check(job, job.items[i])
	end
	job.i = stop + 1
	if job.i > #job.items then
		A.job = nil
		if not next(A.queue) then
			A.frame:Hide()
			A.Flush()
		end
	end
end

-- The line: one for all that crossed, in chat; in a fight it waits for the fight's end.
function A.Line()
	local parts = {}
	for i, f in ipairs(A.found) do
		if i > A.MOST then
			parts[#parts + 1] = L["and %d more"]:format(#A.found - A.MOST)
			break
		end
		parts[#parts + 1] = ("%s %s (%s)"):format(A.Link(f.item), W.Money(f.low), table.concat(f.reasons, ", "))
	end
	return table.concat(parts, SEP)
end

function A.Flush()
	if not A.found[1] then
		A.Listen(false)
		return
	end
	if not A.On() then
		A.found = {}
		A.Listen(false)
		return
	end
	if LT.InFight() then
		A.Listen(true) -- (held: told when the fight ends)
		return
	end
	local line = A.Line()
	A.found = {}
	A.Listen(false)
	Print(line)
	local m = Module()
	if m and type(m.db) == "table" and m.db.alertSound then
		pcall(PlaySound, A.SOUND, "SFX")
	end
end

function A.Listen(on)
	if on ~= (A.listening or false) then
		A.listening = on
		if on then
			A.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
		else
			A.frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
		end
	end
end

A.frame = CreateFrame("Frame")
A.frame:Hide()
A.frame:SetScript("OnUpdate", function()
	LT.Guard("WhyPoor alerts", A.Step)
end)
A.frame:SetScript("OnEvent", function()
	LT.Guard("WhyPoor alerts", A.Flush)
end)

---------------------------------------------------------------------------
-- /whypoor alerts
---------------------------------------------------------------------------

function A.Slash(rest)
	rest = strtrim(rest or ""):lower()
	local m = Module()
	if rest == "on" or rest == "off" then
		LT:SetModuleSetting(m, "moveAlerts", rest == "on")
		Print(rest == "on" and L["big moves of watched items: on (%s%% or more in a day)."]:format(A.PctText(A.DefaultMove() or 30))
			or L["big moves of watched items: off."])
		return
	elseif rest ~= "" then
		Print(L["/whypoor alerts: your price alerts; /whypoor alerts on or off: big moves of every watched item."])
		return
	end
	local St, list = W.Stocks, {}
	for item in pairs(A.Rules()) do
		if type(item) == "number" and A.Has(item) then
			list[#list + 1] = item
		end
	end
	table.sort(list)
	local pct = A.DefaultMove()
	Print(pct and L["big moves of watched items: %s%% or more in a day (/whypoor alerts off)."]:format(A.PctText(pct))
		or L["big moves of watched items: off (/whypoor alerts on)."])
	if not list[1] then
		Print(L["no price alerts of your own: pick a watched item in the Stocks tab."])
		return
	end
	for _, item in ipairs(list) do
		local watched = St and St.Watched and St.Watched(item)
		Print(("%s: %s%s"):format(A.Link(item), A.RulesText(item) or "",
			watched and "" or (GREY .. " (" .. L["not watched: paused"] .. ")|r")))
	end
end

---------------------------------------------------------------------------
-- The Stocks tab's details: the alerts of a watched item
---------------------------------------------------------------------------

-- The fields (made once, on the details' child): Below, Above, Moves over ... %. Hidden at every details' start
-- (D.Begin, wrapped once below), shown again only by A.Details.
function A.Inputs(D)
	local i = A.inputs
	if i then
		return i
	end
	i = { parts = {} }
	local function Label(text)
		local fs = D.child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetText(text)
		i.parts[#i.parts + 1] = fs
		return fs
	end
	local function Box(width, letters)
		local box = CreateFrame("EditBox", nil, D.child, "InputBoxTemplate")
		box:SetSize(width, 20)
		box:SetAutoFocus(false)
		box:SetMaxLetters(letters)
		box:SetScript("OnEscapePressed", box.ClearFocus)
		box:SetScript("OnEnterPressed", function() A.SetTyped() end)
		box:SetScript("OnTextChanged", function(_, byUser)
			if byUser then
				i.typed = true -- (what's typed stays through the window's redraws until Set or Clear)
			end
		end)
		i.parts[#i.parts + 1] = box
		return box
	end
	i.BelowLabel = Label(L["Below"])
	i.Below = Box(62, 14)
	i.AboveLabel = Label(L["Above"])
	i.Above = Box(62, 14)
	i.MoveLabel = Label(L["Moves over"])
	i.Move = Box(36, 6)
	i.Pct = Label("%")
	A.inputs = i
	return i
end

function A.HideInputs()
	if A.inputs then
		for _, part in ipairs(A.inputs.parts) do
			part:Hide()
		end
	end
end

-- The window's details start: our fields hidden (drawn again only where they belong).
function A.HookWindow()
	local D = W.Window and W.Window.D
	if A.hooked or not (D and D.Begin) then
		return
	end
	A.hooked = true
	local begin = D.Begin
	D.Begin = function(...)
		begin(...)
		A.HideInputs()
	end
end

-- Stocks.lua's T.Details, at its end: "Price alerts" for the item picked.
function A.Details(item)
	local Wn = W.Window
	local D = Wn and Wn.D
	if not (D and D.child and type(item) == "number") then
		return
	end
	A.HookWindow()
	local i = A.inputs
	if i and i.item ~= item then
		i.item, i.typed, i.problem = item, false, nil -- (another item: what was typed for the last one goes)
	end
	D.Head(L["Price alerts"])
	local St = W.Stocks
	if not (St and St.Watched and St.Watched(item)) then
		D.Text(GREY .. L["Add it to your watch list for price alerts in chat after your scans."] .. "|r", "small", 4)
		return
	end
	local now = A.RulesText(item, true)
	D.Text(now and L["Now: %s."]:format(now) or (GREY .. L["None for it yet."] .. "|r"), "text", 4)
	i = A.Inputs(D)
	i.item = item
	local r = A.Get(item)
	if not i.typed then
		i.Below:SetText(A.MoneyText(r and r.below))
		i.Above:SetText(A.MoneyText(r and r.above))
		i.Move:SetText(r and r.move and A.PctText(r.move) or "")
	end
	i.BelowLabel:ClearAllPoints()
	i.BelowLabel:SetPoint("TOPLEFT", 8, -D.y - 4)
	i.Below:ClearAllPoints()
	i.Below:SetPoint("LEFT", i.BelowLabel, "RIGHT", 10, 0)
	i.AboveLabel:ClearAllPoints()
	i.AboveLabel:SetPoint("LEFT", i.Below, "RIGHT", 10, 0)
	i.Above:ClearAllPoints()
	i.Above:SetPoint("LEFT", i.AboveLabel, "RIGHT", 10, 0)
	i.MoveLabel:ClearAllPoints()
	i.MoveLabel:SetPoint("LEFT", i.Above, "RIGHT", 10, 0)
	i.Move:ClearAllPoints()
	i.Move:SetPoint("LEFT", i.MoveLabel, "RIGHT", 10, 0)
	i.Pct:ClearAllPoints()
	i.Pct:SetPoint("LEFT", i.Move, "RIGHT", 3, 0)
	for _, part in ipairs(i.parts) do
		part:Show()
	end
	D.y = D.y + 26
	D.Button(L["Set"], function() A.SetTyped() end, true, 80)
	if r then
		D.Button(L["Clear"], function()
			A.Clear(item)
			i.typed, i.problem = false, nil
			Print(L["price alerts for %s cleared."]:format(A.Link(item)))
			Wn.Draw()
		end, true, 80, true)
	end
	if i.problem then
		D.Text(ORANGE .. i.problem .. "|r", "small", 4)
	end
	D.Text(GREY .. L["A price for one: 15s, 2g 50s or 1.5 (gold); empty: none. Told once in chat after your scans, again once the price went back."] .. "|r", "small", 4)
end

-- What's in the fields, kept as the picked item's alerts (all empty: cleared).
function A.SetTyped()
	local i, Wn = A.inputs, W.Window
	local item = i and i.item
	if not (item and Wn) then
		return
	end
	for _, box in ipairs({ i.Below, i.Above, i.Move }) do
		box:ClearFocus()
	end
	local texts = { below = strtrim(i.Below:GetText() or ""), above = strtrim(i.Above:GetText() or ""),
		move = strtrim(i.Move:GetText() or "") }
	local rules = { below = A.ParseMoney(texts.below), above = A.ParseMoney(texts.above), move = A.ParsePct(texts.move) }
	if (texts.below ~= "" and not rules.below) or (texts.above ~= "" and not rules.above) then
		i.problem = L["Type a price like 15s, 2g 50s or 1.5 (gold)."]
	elseif texts.move ~= "" and not rules.move then
		i.problem = L["Type the move in percent, like 30."]
	elseif rules.below and rules.above and rules.below >= rules.above then
		i.problem = L["Below has to be under Above."]
	elseif not (rules.below or rules.above or rules.move) and not A.Has(item) then
		i.problem = L["Type a price or a percent first."]
	elseif not A.Set(item, rules) then
		i.problem = L["The alerts couldn't be kept yet: try again in a moment."]
	else
		i.typed, i.problem = false, nil
		local text = A.RulesText(item)
		Print(text and L["price alerts for %s: %s."]:format(A.Link(item), text)
			or L["price alerts for %s cleared."]:format(A.Link(item)))
	end
	Wn.Draw()
end

A.HookWindow()
