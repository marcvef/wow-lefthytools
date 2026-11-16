local _, ns = ...
local LT = ns.LT
local L = ns.L
local E = ns.Echoes
local M = E.module

-- Echoes' admin window (/lefthy echoes window, or the button in Echoes' settings): what a collector
-- has of each friend's recording, where it is (exported, on disk, waiting for a /reload, sent early)
-- and whether more is still coming (offered by friends online, being fetched now). A table with a
-- row per friend's store and one for my own pages, under a few lines about collecting, the traffic
-- and the exporter's receipt.
--
-- Never lags the client: it only reads what Store.lua and Delivery.lua keep (E.Store.Collected,
-- MineCounts, Inbox, ReceiptInfo; E.Delivery.Stores, Traffic: counts and new tables, nothing
-- unpacked or hashed), once a second while the window is open (its OnUpdate, which runs only while
-- it's shown); nothing at all while it's closed. Built the first time it opens.
--
-- With a controller: every cell is text in the table, nothing needs hovering; the scroll bar's
-- buttons move a long list.

local Admin = {}
E.Admin = Admin

local REFRESH = 1          -- seconds between refreshes while open
local WIDTH, HEIGHT = 940, 520
local ROW = 18             -- a row's height
local LINES = 5            -- summary lines above the table
local GREEN, ORANGE, GRAY, GOLD = "|cff80ff80", "|cffffa040", "|cff909090", "|cffffd200"

-- The table's columns: key (the row field shown), title, width.
local COLUMNS = {
	{ key = "name", title = L["Friend"], width = 140 },
	{ key = "online", title = L["Online"], width = 70 },
	{ key = "pages", title = L["Pages"], width = 90 },
	{ key = "upto", title = L["Up to"], width = 80 },
	{ key = "exported", title = L["Exported"], width = 66 },
	{ key = "disk", title = L["On disk"], width = 62 },
	{ key = "fresh", title = L["Needs /reload"], width = 86 },
	{ key = "early", title = L["Early"], width = 56 },
	{ key = "offered", title = L["Offered"], width = 62 },
	{ key = "coming", title = L["Coming"], width = 80 },
	{ key = "arrived", title = L["Last page"], width = 88 },
}

local frame -- the window, made the first time it opens
local rows = {} -- pooled row frames
Admin.refreshes = 0 -- (tests: how often it was worked out)

local function Amount(n)
	if n >= 1024 * 1024 then
		return LT.Decimal(("%.1f MB"):format(n / 1024 / 1024))
	end
	return LT.Decimal(("%.1f KB"):format(n / 1024))
end

-- A time of the realm's clock: "21:30" today, with the date another day.
local function Clock(t)
	if type(t) ~= "number" then
		return GRAY .. "-|r"
	end
	local ok, at = pcall(date, "*t", t)
	if not ok or type(at) ~= "table" then
		return "?"
	end
	local today = date("*t", E.Now())
	if at.year == today.year and at.yday == today.yday then
		return date("%H:%M", t)
	end
	return date(L["%m/%d %H:%M"], t)
end

-- A count: grey "-" for none, else in colour (if given).
local function Num(n, colour)
	if not n or n == 0 then
		return GRAY .. "-|r"
	end
	return colour and (colour .. n .. "|r") or tostring(n)
end

---------------------------------------------------------------------------
-- What's shown, worked out from what Store.lua and Delivery.lua keep
---------------------------------------------------------------------------

-- The rows: my own pages first, then every friend's store I have anything of or that friends online
-- offer, by name (stores whose newest page is over 30 days old last). Each row: its cells' texts.
-- Also the sums the summary needs.
local function Rows(stores)
	local data = E.data
	local list, sums = {}, { session = 0, offered = 0, coming = 0 }
	local mine = E.Store.MineCounts()
	list[1] = {
		name = GOLD .. L["You (this computer)"] .. "|r",
		online = "",
		pages = Num(mine.count + mine.exported),
		upto = Clock(mine.newest),
		exported = Num(mine.exported),
		disk = Num(mine.count - mine.later),
		fresh = Num(mine.later, ORANGE),
		early = Num(mine.early),
		offered = GRAY .. "-|r",
		coming = GRAY .. "-|r",
		arrived = GRAY .. "-|r",
	}
	local byKey, friends = {}, {}
	for _, row in ipairs(E.Store.Collected()) do
		byKey[row.key] = row
		friends[#friends + 1] = row
	end
	local names = type(data.names) == "table" and data.names or {}
	for key, s in pairs(stores) do
		if not byKey[key] and (s.online or s.offered > 0 or s.coming > 0 or s.waiting > 0) then
			local acct, store = key:sub(1, 8), key:sub(10)
			local row = { key = key, acct = acct, store = store, all = {}, exported = 0, disk = 0, fresh = 0, early = 0, session = 0,
				yours = acct == data.acct, name = type(names[key]) == "string" and names[key] or (s.online and LT.Names.First(s.online)) or nil }
			byKey[key] = row
			friends[#friends + 1] = row
		end
	end
	local seen = {}
	for _, row in ipairs(friends) do
		row.label = row.yours and L["You (%s)"]:format(row.store) or row.name or row.acct
		seen[row.label] = (seen[row.label] or 0) + 1
	end
	table.sort(friends, function(a, b)
		if (a.old == true) ~= (b.old == true) then
			return not a.old
		end
		local x, y = a.label:lower(), b.label:lower()
		if x ~= y then
			return x < y
		end
		return a.key < b.key
	end)
	for _, row in ipairs(friends) do
		local s = stores[row.key] or { offered = 0, coming = 0, have = 0, len = 0, waiting = 0 }
		local count = 0
		for _, r in ipairs(row.all) do
			count = count + r[2] - r[1] + 1
		end
		local pages = Num(count)
		if #row.all > 1 then
			pages = L["%d (gaps: %d)"]:format(count, #row.all - 1)
		end
		local coming = s.coming + s.waiting
		local comingText = Num(coming, GREEN)
		if s.coming > 0 and s.len > 0 then
			comingText = GREEN .. L["%d (%d%%)"]:format(coming, math.floor(s.have / s.len * 100)) .. "|r"
		end
		local label = seen[row.label] > 1 and ("%s (%s)"):format(row.label, row.store) or row.label
		list[#list + 1] = {
			name = row.old and (GRAY .. label .. "|r") or label,
			online = s.online and (GREEN .. L["online"] .. "|r") or (GRAY .. "-|r"),
			pages = pages,
			upto = Clock(row.newest),
			exported = Num(row.exported),
			disk = Num(row.disk),
			fresh = Num(row.fresh, ORANGE),
			early = Num(row.early),
			offered = Num(s.offered, GREEN),
			coming = comingText,
			arrived = row.arrived and LT.Ago(row.arrived) or (GRAY .. "-|r"),
		}
		sums.session = sums.session + row.session
		sums.offered = sums.offered + s.offered
		sums.coming = sums.coming + coming
	end
	return list, sums
end

-- The lines above the table: collecting and the inbox, the traffic, the exporter's receipt, a hint.
local function Summary(sums)
	local lines = {}
	local collecting = M.db and M.db.collect
	local inbox, note, full = E.Store.Inbox()
	if collecting then
		local line = L["Collecting: on. Inbox: %s of %s."]:format(Amount(inbox), Amount(full))
		if inbox >= full then
			line = line .. " " .. ORANGE .. L["Full: no more pages are fetched and friends send none early, until the exporter has run."] .. "|r"
		elseif inbox >= note then
			line = line .. " " .. ORANGE .. L["Over 4 MB: run the exporter."] .. "|r"
		end
		lines[1] = line
	else
		lines[1] = L["Collecting: off. Friends' recordings don't come here (/lefthy echoes collect on, only where the exporter runs)."]
	end
	local traffic = E.Delivery.Traffic()
	if traffic.running then
		lines[2] = L["Friends with Echoes online: %d. Pages being fetched: %d. Serving: %d, %d waiting."]:format(traffic.friends, traffic.coming,
			traffic.serving, traffic.queued)
	else
		lines[2] = GRAY .. L["Not passing pages on: needs Echoes recording, Beacon on and your BattleTag known."] .. "|r"
	end
	lines[3] = L["Traffic: %d messages sent, %d received, %d pages got, %s served, %d failed their hash."]:format(traffic.sent, traffic.received,
		traffic.pages, Amount(traffic.served), traffic.badHash)
	if traffic.paused > 0 then
		lines[3] = lines[3] .. " " .. ORANGE .. L["Paused for %d s: the server asked Beacon to slow down."]:format(math.ceil(traffic.paused)) .. "|r"
	end
	local receipt = E.Store.ReceiptInfo()
	if receipt and receipt.at and receipt.upto then
		lines[4] = L["Exporter's receipt: written %s; it had read the pages that arrived up to %s."]:format(Clock(receipt.at), Clock(receipt.upto))
	elseif receipt and receipt.at then
		lines[4] = L["Exporter's receipt: written %s."]:format(Clock(receipt.at))
	elseif collecting then
		lines[4] = GRAY .. L["No exporter's receipt read this session (it's read once, after a login or /reload)."] .. "|r"
	else
		lines[4] = ""
	end
	if sums.session > 0 then
		lines[5] = ORANGE .. L["%d pages arrived this session, not on disk yet: /reload or log out to hand them to the exporter."]:format(sums.session) .. "|r"
	elseif collecting and (sums.offered > 0 or sums.coming > 0) then
		lines[5] = GREEN .. L["More is on its way: friends online offer %d pages you don't have, %d being fetched."]:format(sums.offered, sums.coming) .. "|r"
	elseif collecting then
		lines[5] = L["Nothing waits for a /reload, and friends online offer nothing you don't have."]
	else
		lines[5] = ""
	end
	return lines
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function Cells(parent, y)
	local cells, x = {}, 0
	for _, column in ipairs(COLUMNS) do
		local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
		text:SetWidth(column.width - 6)
		text:SetJustifyH("LEFT")
		text:SetWordWrap(false)
		text.x = x
		cells[column.key] = text
		x = x + column.width
	end
	return cells
end

local function Row(i)
	local row = rows[i]
	if not row then
		row = CreateFrame("Frame", nil, frame.Content)
		row:SetSize(frame.Content:GetWidth(), ROW)
		row:SetPoint("TOPLEFT", frame.Content, "TOPLEFT", 0, -(i - 1) * ROW)
		if i % 2 == 0 then
			local stripe = row:CreateTexture(nil, "BACKGROUND")
			stripe:SetAllPoints()
			stripe:SetColorTexture(1, 1, 1, 0.04)
		end
		row.Cells = Cells(row, -3)
		rows[i] = row
	end
	return row
end

-- Worked out and drawn: once a second while open.
local function Refresh()
	Admin.refreshes = Admin.refreshes + 1
	if not E.data then
		return
	end
	local list, sums = Rows(E.Delivery.Stores())
	for i, text in ipairs(Summary(sums)) do
		frame.Lines[i]:SetText(text)
	end
	for i, cells in ipairs(list) do
		local row = Row(i)
		for key, text in pairs(cells) do
			row.Cells[key]:SetText(text)
		end
		row:Show()
	end
	for i = #list + 1, #rows do
		rows[i]:Hide()
	end
	frame.Content:SetHeight(math.max(#list * ROW, 10))
	frame.shown = list -- (tests: what the rows say)
end
Admin.Refresh = function()
	if frame and frame:IsShown() then
		LT.Guard("Echoes admin window", Refresh)
	end
end

local function Build()
	frame = LT.Window.Create("LefthyToolsEchoesAdminFrame", L["Echoes: collected recordings"], WIDTH, HEIGHT)
	frame.Lines = {}
	for i = 1, LINES do
		local line = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		line:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -32 - (i - 1) * 15)
		line:SetWidth(WIDTH - 32)
		line:SetJustifyH("LEFT")
		line:SetWordWrap(false)
		frame.Lines[i] = line
	end
	local top = 32 + LINES * 15 + 26
	frame.Inset:ClearAllPoints()
	frame.Inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -top)
	frame.Inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 46)
	frame.Header = Cells(frame, -(top - 16))
	for _, column in ipairs(COLUMNS) do
		local cell = frame.Header[column.key]
		cell:ClearAllPoints()
		cell:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", 8 + cell.x, 14)
		cell:SetText(GOLD .. column.title .. "|r")
	end
	frame.Scroll, frame.Content = LT.Window.AddScroll(frame)
	frame.Legend = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.Legend:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 10)
	frame.Legend:SetWidth(WIDTH - 32)
	frame.Legend:SetJustifyH("LEFT")
	frame.Legend:SetText(L["Needs /reload: arrived this session; the exporter sees them after a /reload or logout. Early: sent before the friend's game saved them, kept until a copy from their disk confirms them. Offered: friends online have them, you don't yet. Coming: being fetched now."])
	local since = 0
	frame:HookScript("OnShow", function() -- (Window.Create hooks it too)
		since = 0
		LT.Guard("Echoes admin window", Refresh)
	end)
	frame:SetScript("OnUpdate", function(_, elapsed) -- (only while shown)
		since = since + elapsed
		if since < REFRESH then
			return
		end
		since = 0 -- first: an error in it must not make it run every frame
		LT.Guard("Echoes admin window", Refresh)
	end)
	Admin.frame = frame
end

function Admin.Show()
	if not frame then
		Build()
	end
	frame:Show()
end

function Admin.Toggle()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		Admin.Show()
	end
end

E.Command("window", function() Admin.Toggle() end,
	"/lefthy echoes window - what you've collected of each friend, and what's still coming (a window)")
