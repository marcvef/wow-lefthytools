local _, ns = ...
local L = ns.L
local C = ns.Chronicle

-- Chronicle's Compare page, drawn on Canvas.lua's canvas: every character, yours and your friends',
-- in every graph (C.Characters: a line, a chip, a row each, by the name the game shows). A toolbar
-- (the range, a chip per character), the big chart (anything, per day or adding up, with symbols),
-- the leaderboard over the range, a chart per number, the hall of fame and records.

local G = C.Graphs
local CARD_GAP, PAD, HEADER, GRID, GOLD_ICON = G.CARD_GAP, G.PAD, G.HEADER, G.GRID, G.GOLD_ICON
local Card, Empty = G.Card, G.Empty
local ICONS = G.EVENT_ICONS

-- What a chart shows: key (a day's field, or value(b) for a sum of fields), mode "day" (that
-- day's number), "sum" (adding up over the range) or "last" (where the day ended: level, gold).
local CHARTS = {
	{ key = "played", mode = "day" },
	{ key = "xp", mode = "day" },
	{ key = "quests", mode = "day" },
	{ key = "kills", mode = "day" },
	{ key = "deaths", mode = "sum" },
	{ key = "gold", mode = "last" },
	{ key = "dist", mode = "day" },
	{ key = "bossesRares", mode = "sum", value = function(b) return (b.bosses or 0) + (b.rares or 0) end },
	{ key = "afk", mode = "day" },
	{ key = "jumps", mode = "sum" },
}
local LEVEL_CHART = { key = "level", mode = "last" }
local BY_KEY = { level = LEVEL_CHART }
for _, chart in ipairs(CHARTS) do
	BY_KEY[chart.key] = chart
end

-- The big chart at the top shows any of these (icons above it pick); per day or adding up.
local BIG = { "level", "played", "xp", "quests", "kills", "deaths", "gold", "dist", "bossesRares", "afk", "jumps" }
local CHART_ICON = {
	level = ICONS.level,
	played = "Interface\\Icons\\INV_Misc_PocketWatch_01",
	xp = "Interface\\Icons\\Spell_Holy_HolyBolt",
	quests = ICONS.quests,
	kills = "Interface\\Icons\\Ability_DualWield",
	deaths = ICONS.death,
	gold = ICONS.gold,
	dist = "Interface\\Icons\\Ability_Rogue_Sprint",
	bossesRares = ICONS.boss,
	afk = "Interface\\Icons\\Spell_Nature_Sleep",
	jumps = "Interface\\Icons\\Spell_Magic_FeatherFall",
}
local CHART_NAME = {
	level = function() return L["Level"] end,
	played = function() return L["Time played"] end,
	xp = function() return L["Experience"] end,
	quests = function() return L["Quests"] end,
	kills = function() return L["Killing blows"] end,
	deaths = function() return L["Deaths"] end,
	gold = function() return L["Gold"] end,
	dist = function() return L["Distance"] end,
	bossesRares = function() return L["Bosses and rares"] end,
	afk = function() return L["Time AFK"] end,
	jumps = function() return L["Jumps"] end,
}
-- The symbols' legend.
local MARK_LABEL = {
	death = function() return L["Deaths"] end,
	boss = function() return L["Bosses defeated"] end,
	level = function() return L["Level 10, 20, 30, ..."] end,
	dungeon = function() return L["Dungeons seen"] end,
	rare = function() return L["Rare elites killed"] end,
	loot = function() return L["Epic items"] end,
	achievement = function() return L["Achievements"] end,
	mount = function() return L["Mounts"] end,
	gold = function() return L["Gold milestones"] end,
}

-- What the big chart shows (state.big, state.perDay); level and gold are where the day ended.
local function BigChart(state)
	local key = BY_KEY[state.big or ""] and state.big or "level"
	local base = BY_KEY[key]
	return { key = key, value = base.value, mode = base.mode == "last" and "last" or (state.perDay and "day" or "sum") }
end

local function BigTitle(chart)
	local name = CHART_NAME[chart.key]()
	if chart.mode == "day" then
		return L["%s per day"]:format(name)
	elseif chart.mode == "sum" then
		return L["%s, adding up"]:format(name)
	end
	return name
end

local CHART_LABEL = {
	level = function() return L["Level"] end,
	played = function() return L["Time played per day"] end,
	xp = function() return L["Experience per day"] end,
	quests = function() return L["Quests per day"] end,
	kills = function() return L["Killing blows per day"] end,
	deaths = function() return L["Deaths, adding up"] end,
	gold = function() return L["Gold"] end,
	dist = function() return L["Distance per day"] end,
	bossesRares = function() return L["Bosses and rares, adding up"] end,
	afk = function() return L["Time AFK per day"] end,
	jumps = function() return L["Jumps, adding up"] end,
}

-- Each person's colour: their class's; a second (third) of the same class lighter (darker).
local VARIANTS = { function(c) return c end, function(c) return c + (1 - c) * 0.55 end, function(c) return c * 0.55 end,
	function(c) return c + (1 - c) * 0.25 end }
local function Colours(people)
	local seen = {}
	for _, p in ipairs(people) do
		local r, g, b = 1, 1, 1
		if ns.Beacon and ns.Beacon.ClassColor then
			r, g, b = ns.Beacon.ClassColor(p.classFile)
		end
		local n = (seen[p.classFile or "?"] or 0) + 1
		seen[p.classFile or "?"] = n
		local f = VARIANTS[(n - 1) % #VARIANTS + 1]
		p.colour = { f(r), f(g), f(b) }
		p.hex = ("%02x%02x%02x"):format(math.floor(p.colour[1] * 255), math.floor(p.colour[2] * 255), math.floor(p.colour[3] * 255))
	end
end

-- (marked while only the first name is known, Characters.lua's C.Mark)
local function Named(p)
	return "|cff" .. p.hex .. (p.name or "?") .. "|r" .. C.Mark(p.partial)
end

-- A person's values over the range (days: YYYY-MM-DD, oldest first): nil where unknown.
local function Series(p, chart, days)
	local values, last = {}, nil
	local function Value(b)
		if chart.value then
			return chart.value(b)
		end
		return b[chart.key]
	end
	if chart.mode == "last" then
		local first = days[1]
		local before -- the latest value before the range starts
		for day, b in pairs(p.days) do
			if day < first and Value(b) ~= nil and (not before or day > before) then
				before = day
			end
		end
		last = before and Value(p.days[before]) or nil
	end
	local sum, any = 0, false
	for i, day in ipairs(days) do
		local b = p.days[day]
		local v = b and Value(b)
		if chart.mode == "last" then
			if v ~= nil and (chart.key ~= "level" or v > 0) then
				last = v
			end
			values[i] = last
			any = any or last ~= nil
		elseif chart.mode == "sum" then
			sum = sum + (v or 0)
			values[i] = sum
			any = any or (v or 0) > 0
		else
			values[i] = v or 0
			any = any or (v or 0) > 0
		end
	end
	return any and values or nil
end

-- Share a ranking in LTC (LefthyTools chat): "Chronicle, last 14 days, quests: Anna 142, Bob 98".
local function ShareRanking(title, ranking, key, days)
	local parts = {}
	for i = 1, math.min(5, #ranking) do
		parts[#parts + 1] = ranking[i].person.name .. C.Mark(ranking[i].person.partial, true) .. " "
			.. (key == "gold" and (C.Number(ranking[i].value) .. "g") or C.ChatValue(key == "bossesRares" and "kills" or key, ranking[i].value))
	end
	if #parts > 0 then
		C.ShareLine(("Chronicle, %s (%d days): %s"):format(title, days, table.concat(parts, ", ")))
	end
end

local CHART_CHAT = { level = "level", played = "time played", xp = "XP", quests = "quests", kills = "killing blows",
	deaths = "deaths", gold = "gold", dist = "distance", bossesRares = "bosses and rares", afk = "time AFK", jumps = "jumps" }

-- A line chart card: a line per person, the day's values in a tooltip, the leader in the corner.
-- opts (all optional): title; header(ix, iy, iw) draws a row above the plot and returns its height;
-- marks ([person key][day] = { { icon, text, rank, t } }: a symbol on their line that day, all of
-- them in the day's tooltip); pick() (a click on the plot: show this chart big at the top).
local function LineChart(canvas, x, y, w, h, chart, people, days, state, opts)
	opts = opts or {}
	local series, ranking = {}, {}
	local lo, hi = math.huge, -math.huge
	for _, p in ipairs(people) do
		if not state.hidden[p.key] then
			local values = Series(p, chart, days)
			if values then
				series[#series + 1] = { p = p, values = values }
				local final
				for _, v in pairs(values) do
					lo, hi = math.min(lo, v), math.max(hi, v)
				end
				for i = #days, 1, -1 do
					final = final or values[i]
				end
				-- The ranking: the range's total (per day), or where it ended (sum, last).
				local total = 0
				if chart.mode == "day" then
					for i = 1, #days do
						total = total + (values[i] or 0)
					end
				else
					total = final or 0
				end
				ranking[#ranking + 1] = { person = p, value = total }
			end
		end
	end
	table.sort(ranking, function(a, b) return a.value > b.value end)
	local note = ranking[1] and ranking[1].value > 0 and (Named(ranking[1].person) .. " " .. G.ValueText(chart.key, ranking[1].value)) or nil
	local ix, iy, iw, ih = Card(canvas, x, y, w, h, opts.title or CHART_LABEL[chart.key](), note)
	if opts.header then
		local used = opts.header(ix, iy, iw)
		iy, ih = iy + used, ih - used
	end
	-- Share, at the bottom right (under the day labels).
	canvas:Text("|cff80c0ff" .. L["Share"] .. "|r", ix + iw - 60, iy + ih - 11, "GameFontHighlightSmall", "RIGHT", 60)
	canvas:Hover(ix + iw - 60, iy + ih - 14, 60, 16, { L["Share"], L["Post this ranking in LTC."] },
		function() ShareRanking(CHART_CHAT[chart.key], ranking, chart.key, #days) end)
	ih = ih - 14
	if #series == 0 then
		Empty(canvas, ix, iy, iw, ih, L["Nothing recorded yet."])
		return
	end
	if chart.mode ~= "last" or chart.key == "gold" then
		lo = 0
	else
		lo = math.max(0, math.floor(lo) - 1)
	end
	hi = math.max(hi, lo + 1)
	local plotH = ih - 14
	for i = 1, 3 do
		canvas:Rect(ix, iy + plotH * (1 - i / 3), iw, 1, 1, 1, 1, GRID[i], "BORDER")
	end
	canvas:Text(G.ValueText(chart.key, hi), ix, iy - 2, "GameFontHighlightSmall", "LEFT", iw / 2)
	if lo > 0 then
		canvas:Text(G.ValueText(chart.key, lo), ix, iy + plotH - 12, "GameFontHighlightSmall", "LEFT", iw / 2)
	end
	local n = #days
	local function X(i)
		return ix + (n > 1 and (i - 1) / (n - 1) or 0.5) * iw
	end
	local function Y(v)
		return iy + plotH - plotH * (v - lo) / (hi - lo)
	end
	for _, s in ipairs(series) do
		local thick = s.p.me and 3 or 2
		local prev
		for i = 1, n do
			local v = s.values[i]
			if v ~= nil then
				if prev then
					canvas:Line(X(prev), Y(s.values[prev]), X(i), Y(v), s.p.colour, thick)
				end
				prev = i
			end
		end
		if n <= 14 then
			for i = 1, n do
				local v = s.values[i]
				if v ~= nil then
					canvas:Rect(X(i) - 2, Y(v) - 2, 4, 4, s.p.colour[1], s.p.colour[2], s.p.colour[3], 1, "OVERLAY")
				end
			end
		end
	end
	-- Symbols: each person's most notable highlight of the day, on their line (no line: at the bottom).
	local marks, marked, lined = opts.marks or {}, {}, {}
	for _, s in ipairs(series) do
		marked[#marked + 1], lined[s.p] = s, true
	end
	for _, p in ipairs(people) do
		if marks[p.key] and not state.hidden[p.key] and not lined[p] then
			marked[#marked + 1] = { p = p, values = {} }
		end
	end
	-- A symbol's own tooltip: only that person's moments of the day (two of a kind at most, so five
	-- deaths don't hide the boss; five in all). Symbols on the same spot share one.
	local function DayTitle(day)
		return date(L["%Y-%m-%d"], time({ year = tonumber(day:sub(1, 4)), month = tonumber(day:sub(6, 7)),
			day = tonumber(day:sub(9, 10)), hour = 12 }))
	end
	local function Moments(lines, p, list)
		lines[#lines + 1] = Named(p)
		local shown, ofKind = 0, {}
		for _, m in ipairs(list) do
			ofKind[m.rank] = (ofKind[m.rank] or 0) + 1
			if ofKind[m.rank] <= 2 and shown < 5 then
				lines[#lines + 1] = G.IconText(m.icon) .. " " .. m.text
				shown = shown + 1
			end
		end
		if #list > shown then
			lines[#lines + 1] = "|cff888888" .. L["... and %d more"]:format(#list - shown) .. "|r"
		end
	end
	local spots = {}
	for _, s in ipairs(marked) do
		local byDay = marks[s.p.key]
		for i, day in ipairs(byDay and days or {}) do
			local list = byDay[day]
			if list then
				table.sort(list, function(a, b) return a.rank < b.rank or (a.rank == b.rank and a.t > b.t) end)
				local mx, my = X(i), Y(s.values[i] or lo)
				canvas:Icon(list[1].icon, mx - 7, my - 7, 14)
				local spot
				for _, other in ipairs(spots) do
					if math.abs(other.x - mx) < 8 and math.abs(other.y - my) < 8 then
						spot = other
						break
					end
				end
				if not spot then
					spot = { x = mx, y = my, lines = { DayTitle(day) } }
					spots[#spots + 1] = spot
					canvas:Hover(mx - 8, my - 8, 16, 16, spot.lines, nil, true)
				end
				Moments(spot.lines, s.p, list) -- (the hover shows its lines table as it is when hovered)
			end
		end
	end
	-- Day labels under the plot, and a hover per day: everyone's value, small icons for what
	-- happened (a symbol's own hover tells what).
	local step = n <= 7 and 1 or n <= 14 and 2 or 5
	local slot = iw / math.max(n - 1, 1)
	for i, day in ipairs(days) do
		if (n - i) % step == 0 then
			canvas:Text(day:sub(9, 10), X(i) - 12, iy + plotH + 2, "GameFontHighlightSmall", "CENTER", 24)
		end
		local lines = { DayTitle(day) }
		local rows, anyMoments = {}, false
		for _, s in ipairs(marked) do
			local v, list = s.values[i], marks[s.p.key] and marks[s.p.key][day]
			if v ~= nil or list then
				rows[#rows + 1] = { p = s.p, v = v, list = list }
			end
		end
		table.sort(rows, function(a, b) return (a.v or -math.huge) > (b.v or -math.huge) end)
		for _, row in ipairs(rows) do
			local icons, kinds, count = "", {}, 0
			for _, m in ipairs(row.list or {}) do
				if not kinds[m.rank] and count < 3 then -- (each kind once, three at most)
					kinds[m.rank], count = true, count + 1
					icons = icons .. (count == 1 and "  " or " ") .. G.IconText(m.icon, 12)
				end
			end
			anyMoments = anyMoments or row.list ~= nil
			lines[#lines + 1] = Named(row.p) .. (row.v and ("  " .. G.ValueText(chart.key, row.v)) or "") .. icons
		end
		if anyMoments then
			lines[#lines + 1] = "|cff888888" .. L["Hover a symbol for what happened."] .. "|r"
		end
		if opts.pick then
			lines[#lines + 1] = "|cff80c0ff" .. L["Click: show it big at the top"] .. "|r"
		end
		canvas:Hover(X(i) - slot / 2, iy, slot, plotH, lines, opts.pick)
	end
end

-- The big chart's row above the plot: an icon per thing it can show, per day or adding up, and the
-- symbols switch (its tooltip: what they mean). Returns the row's height.
local function BigPicker(canvas, ix, iy, iw, chart, state, redraw)
	local size, gap = 20, 6
	local cx = ix
	for _, key in ipairs(BIG) do
		local on = key == chart.key
		if on then
			canvas:Rect(cx - 2, iy - 2, size + 4, size + 4, 1, 0.82, 0, 0.85, "BORDER")
		end
		canvas:Icon(CHART_ICON[key], cx, iy, size, not on)
		canvas:Hover(cx - 2, iy - 2, size + 4, size + 4, { CHART_NAME[key](), on and L["Shown now"] or L["Click: show this"] },
			function()
				state.big = key
				redraw()
			end)
		cx = cx + size + gap
	end
	-- From the right: the symbols switch, then per day | adding up.
	local marksOn = not state.noMarks
	local legend = { L["Symbols on the lines"], L["Everyone's most notable moment of the day. Hover a symbol for all of that day's."] }
	for _, kind in ipairs(G.MARK_KINDS) do
		legend[#legend + 1] = G.IconText(ICONS[kind]) .. " " .. MARK_LABEL[kind]()
	end
	legend[#legend + 1] = "|cff80c0ff" .. (marksOn and L["Click: hide the symbols"] or L["Click: show the symbols"]) .. "|r"
	local rx = ix + iw - 84
	canvas:Rect(rx, iy, 84, 20, 1, 1, 1, marksOn and 0.12 or 0.03, "BORDER")
	canvas:Icon(ICONS.death, rx + 4, iy + 3, 14, not marksOn)
	canvas:Text((marksOn and "|cffffffff" or "|cff888888") .. L["Symbols"] .. "|r", rx + 22, iy + 4, "GameFontHighlightSmall", "LEFT", 58)
	canvas:Hover(rx, iy, 84, 20, legend, function()
		state.noMarks = marksOn or nil
		redraw()
	end)
	if chart.mode ~= "last" then
		for _, perDay in ipairs({ true, false }) do
			local chipW = 92
			rx = rx - chipW - 4
			local on = (chart.mode == "day") == perDay
			canvas:Rect(rx, iy, chipW, 20, 1, 0.82, 0, on and 0.35 or 0.08, "BORDER")
			canvas:Text((on and "|cffffffff" or "|cffaaaaaa") .. (perDay and L["Per day"] or L["Adding up"]) .. "|r", rx, iy + 4,
				"GameFontHighlightSmall", "CENTER", chipW)
			canvas:Hover(rx, iy, chipW, 20, { perDay and L["Per day"] or L["Adding up"],
				perDay and L["Each day on its own."] or L["Each day adds to the days before it."] }, function()
				state.perDay = perDay or nil
				redraw()
			end)
		end
	end
	return size + 10
end

-- The legend: a chip per character (click: hide or show it everywhere), the range.
local RANGES = { 7, 14, 30 }

local function Toolbar(canvas, x, y, w, people, state, redraw)
	local h = 26
	local cx = x
	for _, days in ipairs(RANGES) do
		local text = L["%d days"]:format(days)
		local chipW = 58
		local on = state.range == days
		canvas:Rect(cx, y, chipW - 4, 20, 1, 0.82, 0, on and 0.35 or 0.08, "BORDER")
		canvas:Text((on and "|cffffffff" or "|cffaaaaaa") .. text .. "|r", cx, y + 4, "GameFontHighlightSmall", "CENTER", chipW - 4)
		canvas:Hover(cx, y, chipW - 4, 20, nil, function()
			state.range = days
			redraw()
		end)
		cx = cx + chipW
	end
	cx = cx + 10
	local rowY = y
	for _, p in ipairs(people) do
		local you = p.me and (" " .. L["(you)"]) or ""
		local chipW = 26 + math.min(110, (#(p.name or "?") + #you + (p.partial and 2 or 0)) * 6.5)
		if cx + chipW > x + w then
			cx, rowY = x, rowY + 24
			h = h + 24
		end
		local hidden = state.hidden[p.key]
		canvas:Rect(cx, rowY, chipW - 4, 20, 1, 1, 1, hidden and 0.02 or 0.07, "BORDER")
		canvas:Rect(cx + 6, rowY + 6, 8, 8, p.colour[1], p.colour[2], p.colour[3], hidden and 0.25 or 1)
		local colour = hidden and "|cff666666" or ("|cff" .. p.hex)
		canvas:Text(colour .. (p.name or "?") .. (p.partial and ("|r" .. C.Mark(true) .. colour) or "") .. you .. "|r", cx + 18, rowY + 4,
			"GameFontHighlightSmall", "LEFT", chipW - 22)
		local tip = { (p.name or "?") .. C.Mark(p.partial) }
		if p.partial then
			tip[#tip + 1] = C.PartialHint(p.me, p.account)
		end
		tip[#tip + 1] = p.level and L["Level %d"]:format(p.level) or nil
		if p.account then
			tip[#tip + 1] = "|cff80c0ff" .. p.account .. "|r" -- (whose character it is: their BattleTag)
		end
		if p.online then
			tip[#tip + 1] = L["Online now"]
		elseif p.last and p.last > 0 then
			tip[#tip + 1] = L["Last played %s"]:format(C.Ago(p.last))
		end
		tip[#tip + 1] = hidden and L["Click: show in the graphs"] or L["Click: hide from the graphs"]
		canvas:Hover(cx, rowY, chipW - 4, 20, tip, function()
			state.hidden[p.key] = not state.hidden[p.key] or nil
			redraw()
		end)
		cx = cx + chipW
	end
	return h + 6
end

-- The range picked above (7, 14 or 30 days, like every chart on the page): who leads in what, the
-- top three of each.
local BOARD_LABEL = {
	played = function() return L["Time played"] end, xp = function() return L["Experience"] end,
	quests = function() return L["Quests"] end, kills = function() return L["Killing blows"] end,
	levels = function() return L["Levels gained"] end, deaths = function() return L["Most deaths"] end,
	dist = function() return L["Distance"] end, jumps = function() return L["Jumps"] end,
	afk = function() return L["Martin award"] end,
}

local function Leaders(canvas, x, y, w, people, state)
	local days = state.range
	local board = C.Leaderboard(days, 0, people)
	local shown = {} -- (without the ones hidden by their chip, here and when shared)
	for _, metric in ipairs(C.BOARD) do
		shown[metric] = {}
		for _, entry in ipairs(board[metric] or {}) do
			if not state.hidden[entry.person.key] then
				table.insert(shown[metric], entry)
			end
		end
	end
	local columns, cellH = 3, 64
	local rows = math.ceil(#C.BOARD / columns)
	local h = HEADER + 4 + rows * cellH + PAD
	local ix, iy, iw = Card(canvas, x, y, w, h, L["Leaderboard, last %d days"]:format(days))
	canvas:Text("|cff80c0ff" .. L["Share"] .. "|r", x + w - PAD - 60, y + 9, "GameFontHighlightSmall", "RIGHT", 60)
	canvas:Hover(x + w - PAD - 60, y + 4, 60, 18, { L["Share"], L["Post the leaders in LTC."] }, function()
		local parts = {}
		for _, metric in ipairs({ "quests", "xp", "kills", "deaths", "afk" }) do
			local first = shown[metric][1]
			if first then
				local title = metric == "afk" and "Martin award" or ("most " .. CHART_CHAT[metric])
				parts[#parts + 1] = ("%s %s%s (%s)"):format(title, first.person.name, C.Mark(first.person.partial, true),
					C.ChatValue(metric, first.value))
			end
		end
		if #parts > 0 then
			C.ShareLine(("Chronicle, last %d days: %s"):format(days, table.concat(parts, ", ")))
		end
	end)
	local cellW = iw / columns
	local medals = { "|cffffd700", "|cffc0c0c0", "|cffcd7f32" }
	for i, metric in ipairs(C.BOARD) do
		local cx = ix + ((i - 1) % columns) * cellW
		local cy = iy + math.floor((i - 1) / columns) * cellH
		canvas:Rect(cx + 2, cy, cellW - 4, cellH - 6, 1, 1, 1, 0.03, "BORDER")
		canvas:Text(BOARD_LABEL[metric](), cx + 8, cy + 4, "GameFontNormalSmall", "LEFT", cellW - 16)
		local list = shown[metric]
		if #list == 0 then
			canvas:Text("|cff666666-|r", cx + 8, cy + 20, "GameFontHighlightSmall", "LEFT", cellW - 16)
		end
		for rank = 1, math.min(3, #list) do
			local entry = list[rank]
			canvas:Text(("%s%d.|r %s"):format(medals[rank], rank, Named(entry.person)), cx + 8, cy + 6 + rank * 13,
				"GameFontHighlightSmall", "LEFT", cellW * 0.6)
			canvas:Text(G.ValueText(metric, entry.value), cx + cellW * 0.5, cy + 6 + rank * 13, "GameFontHighlightSmall", "RIGHT",
				cellW * 0.5 - 10)
		end
	end
	return h
end

-- Everyone's lifetime numbers in a table; a column's header sorts by it; the best in gold.
local HALL = { "level", "played", "quests", "kills", "deaths", "zones", "dungeons", "bosses", "rares", "dist", "jumps" }
local HALL_SHORT = {
	level = function() return L["Level"] end, played = function() return L["Time"] end, quests = function() return L["Quests"] end,
	kills = function() return L["Kills"] end, deaths = function() return L["Deaths"] end, zones = function() return L["Zones"] end,
	dungeons = function() return L["Dungeons"] end, bosses = function() return L["Bosses"] end, rares = function() return L["Rares"] end,
	dist = function() return L["Distance"] end, jumps = function() return L["Jumps"] end,
}

local function Hall(canvas, x, y, w, people, state, redraw)
	local list = {}
	for _, p in ipairs(people) do
		if p.profile and not state.hidden[p.key] then
			list[#list + 1] = p
		end
	end
	local rowH = 18
	local h = HEADER + 4 + 20 + math.max(#list, 1) * rowH + PAD
	local ix, iy, iw, ih = Card(canvas, x, y, w, h, L["Hall of fame, all time"])
	if #list == 0 then
		Empty(canvas, ix, iy, iw, ih, L["Friends' lifetime numbers come with their synced journals."])
		return h
	end
	local sortBy = state.sortBy or "level"
	local function Value(p, key)
		if key == "level" then
			return p.level or 0
		end
		return p.profile[key] or 0
	end
	table.sort(list, function(a, b)
		local va, vb = Value(a, sortBy), Value(b, sortBy)
		return va > vb or (va == vb and (a.name or "") < (b.name or ""))
	end)
	local best = {}
	for _, key in ipairs(HALL) do
		for _, p in ipairs(list) do
			best[key] = math.max(best[key] or 0, Value(p, key))
		end
	end
	local nameW = iw * 0.16
	local colW = (iw - nameW) / #HALL
	for i, key in ipairs(HALL) do
		local hx = ix + nameW + (i - 1) * colW
		canvas:Text((key == sortBy and "|cffffffff" or "|cffffd200") .. HALL_SHORT[key]() .. "|r", hx, iy, "GameFontNormalSmall",
			"RIGHT", colW - 4)
		canvas:Hover(hx, iy - 2, colW, 16, { G.LifetimeLabel(key), L["Click: sort by this"] }, function()
			state.sortBy = key
			redraw()
		end)
	end
	for r, p in ipairs(list) do
		local ry = iy + 20 + (r - 1) * rowH
		canvas:Rect(ix, ry - 3, iw, rowH, 1, 1, 1, r % 2 == 0 and 0.03 or 0, "BORDER")
		canvas:Text(Named(p), ix + 2, ry, "GameFontHighlightSmall", "LEFT", nameW - 4)
		for i, key in ipairs(HALL) do
			local v = Value(p, key)
			local text = key == "level" and tostring(v) or key == "played" and C.Duration(v) or key == "dist" and C.Distance(v)
				or C.Number(v)
			canvas:Text(((v > 0 and v == best[key]) and "|cffffd200" or "|cffffffff") .. text .. "|r", ix + nameW + (i - 1) * colW, ry,
				"GameFontHighlightSmall", "RIGHT", colW - 4)
		end
	end
	return h
end

-- Records among everyone: fastest level, longest session, most gold, most deaths, deadliest foes.
local function Records(canvas, x, y, w, people, state)
	local lines = {}
	local function Best(key, lowest)
		local winner, value
		for _, p in ipairs(people) do
			local v = p.profile and p.profile[key]
			if v and v > 0 and not state.hidden[p.key] and (not value or (lowest and v < value) or (not lowest and v > value)) then
				winner, value = p, v
			end
		end
		return winner, value
	end
	local p, v = Best("fastest", true)
	if p then
		lines[#lines + 1] = L["Fastest level: %s (%s)"]:format(Named(p), C.Duration(v))
	end
	p, v = Best("longest")
	if p then
		lines[#lines + 1] = L["Longest session: %s (%s)"]:format(Named(p), C.Duration(v))
	end
	p, v = Best("gold")
	if p then
		lines[#lines + 1] = L["Most gold at once: %s (%s)"]:format(Named(p), C.Number(v) .. GOLD_ICON)
	end
	p, v = Best("deaths")
	if p then
		lines[#lines + 1] = L["Died the most: %s (%s)"]:format(Named(p), C.Number(v))
	end
	p, v = Best("afk")
	if p then
		lines[#lines + 1] = L["Martin of all time: %s (%s AFK)"]:format(Named(p), C.Duration(v))
	end
	for _, person in ipairs(people) do
		if person.foe and person.foe ~= "" and not state.hidden[person.key] then
			lines[#lines + 1] = L["%s's nemesis: %s"]:format(Named(person), person.foe)
		end
	end
	local lineH = 15
	local h = HEADER + 4 + math.max(#lines, 1) * lineH + PAD
	local ix, iy, iw, ih = Card(canvas, x, y, w, h, L["Records"])
	if #lines == 0 then
		Empty(canvas, ix, iy, iw, ih, L["Nothing recorded yet."])
	end
	for i, line in ipairs(lines) do
		canvas:Text(line, ix, iy + (i - 1) * lineH, "GameFontHighlightSmall", "LEFT", iw)
	end
	return h
end

-- The page: state = { range (days), hidden = { [character key] = true }, sortBy, big (what the big chart
-- shows), perDay, noMarks, marks(people, days) (the symbols, from the window) }; redraw(top) draws it
-- again (a click on a chip, a range or a column; top: scrolled to the top). Returns the page height.
local BIG_H = 260

function G.DrawCompare(canvas, width, people, state, redraw)
	canvas:Reset(true) -- (a redraw: the window calls Done after it)
	Colours(people)
	local days = {}
	for i = state.range - 1, 0, -1 do
		days[#days + 1] = date("%Y-%m-%d", C.DayAgo(i))
	end
	local y = 0
	y = y + Toolbar(canvas, 0, y, width, people, state, redraw)
	if #people < 2 then
		local h = 46
		local ix, iy, iw, ih = Card(canvas, 0, y, width, h, L["Just you so far"])
		Empty(canvas, ix, iy, iw, ih, L["Friends show up here once they run this LefthyTools: their journals come in whenever any friend who has them is online."])
		y = y + h + CARD_GAP
	end
	local big = BigChart(state)
	LineChart(canvas, 0, y, width, BIG_H, big, people, days, state, {
		title = BigTitle(big),
		header = function(ix, iy, iw) return BigPicker(canvas, ix, iy, iw, big, state, redraw) end,
		marks = not state.noMarks and state.marks and state.marks(people, days) or nil,
	})
	y = y + BIG_H + CARD_GAP
	y = y + Leaders(canvas, 0, y, width, people, state) + CARD_GAP
	local half = (width - CARD_GAP) / 2
	for i, chart in ipairs(CHARTS) do
		local column = (i - 1) % 2
		LineChart(canvas, column * (half + CARD_GAP), y, half, 160, chart, people, days, state, { pick = function()
			state.big, state.perDay = chart.key, chart.mode == "day" or nil
			redraw(true)
		end })
		if column == 1 or i == #CHARTS then
			y = y + 160 + CARD_GAP
		end
	end
	y = y + Hall(canvas, 0, y, width, people, state, redraw) + CARD_GAP
	y = y + Records(canvas, 0, y, width, people, state)
	return y + 4
end
