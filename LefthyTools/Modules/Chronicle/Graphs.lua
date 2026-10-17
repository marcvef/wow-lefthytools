local _, ns = ...
local L = ns.L
local C = ns.Chronicle

-- Chronicle's Graphs page, drawn on Canvas.lua's canvas. The person, not a character: all my
-- characters added up (Chronicle.lua's C.Totals), except what only a character has (the session
-- going on, time per level: the character I play).
--   Last 14 days      bars per day: time played, XP, quests, kills or time AFK (buttons switch)
--   This session      XP over the session, a line with a soft fill under it
--   Time per level    a bar per level, green (fast) to red (slow)
--   Favourite zones | Deadliest foes        horizontal bars
--   On the road     | Loot by quality       one split bar each, with a legend
-- And a friend's: their account (all their characters), compared with mine.

local G = C.Graphs
local CARD_GAP, PAD, HEADER = G.CARD_GAP, G.PAD, G.HEADER
local Card, Empty, Bars, HBars, Split, Curve, Heat = G.Card, G.Empty, G.Bars, G.HBars, G.Split, G.Curve, G.Heat
local BAR_BLUE = { 0.25, 0.6, 1 }
local BAR_TODAY = { 1, 0.78, 0.2 }
local LINE_COLOR = { 0.35, 0.85, 0.45 }
local DAYS = 14
local LEVELS = 20
local METRICS = { "played", "xp", "quests", "kills", "afk" }

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

local METRIC_LABEL = {
	played = function() return L["Time"] end,
	xp = function() return L["Experience"] end,
	quests = function() return L["Quests"] end,
	kills = function() return L["Killing blows"] end,
	afk = function() return L["Time AFK"] end, -- the Martin tracker
}

local function MetricText(metric, value)
	return (metric == "played" or metric == "afk") and C.Duration(value) or C.Number(value)
end

local function Days(canvas, x, y, w, c, metric)
	local h = 170
	local items, total, played = {}, 0, 0
	for i = DAYS - 1, 0, -1 do
		local t = C.DayAgo(i)
		local day = date("%Y-%m-%d", t)
		local value = (c.daily[day] or {})[metric] or 0
		total, played = total + value, played + ((c.daily[day] or {}).played or 0)
		items[#items + 1] = { value = value, label = date("%d", t), color = i == 0 and BAR_TODAY or nil,
			tooltip = { date(L["%Y-%m-%d"], t), METRIC_LABEL[metric]() .. ": " .. MetricText(metric, value) } }
	end
	local note = METRIC_LABEL[metric]() .. ": " .. MetricText(metric, total)
	local ix, iy, iw, ih = Card(canvas, x, y, w, h, L["Last 14 days"], note)
	Bars(canvas, ix, iy + 22, iw, ih - 22, items, BAR_BLUE)
	return h, ix, iy
end

local function Session(canvas, x, y, w, c)
	local h = 140
	local s = c.session
	local series = s and s.series or {}
	local last = series[#series]
	local note
	if last and last.played > 0 then
		note = L["+%s XP, %s per hour"]:format(C.Number(last.xp), C.Number(last.xp / last.played * 3600))
	end
	local ix, iy, iw, ih = Card(canvas, x, y, w, h, L["This session"], note)
	if #series < 2 or last.played <= 0 then
		Empty(canvas, ix, iy, iw, ih, L["Not enough data yet: check back in a few minutes."])
		return h
	end
	local points = {}
	for _, p in ipairs(series) do
		points[#points + 1] = { x = p.played / last.played, y = p.xp }
	end
	Curve(canvas, ix, iy + 10, iw, ih - 10, points, LINE_COLOR)
	canvas:Text(C.Duration(last.played), ix, iy + ih + 1, "GameFontHighlightSmall", "RIGHT", iw)
	return h
end

local function Levels(canvas, x, y, w, c)
	local h = 150
	local levels = {}
	for level in pairs(c.levelTimes) do
		levels[#levels + 1] = level
	end
	table.sort(levels)
	while #levels > LEVELS do
		table.remove(levels, 1)
	end
	local fastest, slowest
	for _, level in ipairs(levels) do
		local t = c.levelTimes[level]
		if not fastest or t < c.levelTimes[fastest] then fastest = level end
		if not slowest or t > c.levelTimes[slowest] then slowest = level end
	end
	local note = fastest and L["Fastest: %d (%s), slowest: %d (%s)"]:format(fastest, C.Duration(c.levelTimes[fastest]),
		slowest, C.Duration(c.levelTimes[slowest])) or nil
	local ix, iy, iw, ih = Card(canvas, x, y, w, h, L["Time per level: %s"]:format(C.NameOf(c) or "?"), note) -- (a character's own)
	if #levels == 0 then
		Empty(canvas, ix, iy, iw, ih, L["Level up once with Chronicle on to see this."])
		return h
	end
	local low, high = c.levelTimes[fastest], c.levelTimes[slowest]
	local items = {}
	for _, level in ipairs(levels) do
		local t = c.levelTimes[level]
		items[#items + 1] = { value = t, label = tostring(level), color = Heat(high > low and (t - low) / (high - low) or 0),
			tooltip = { L["Level %d"]:format(level), C.Duration(t) } }
	end
	Bars(canvas, ix, iy, iw, ih, items, BAR_BLUE)
	return h
end

-- The count highest of t: { { key, value }, ... }, highest first.
local function Ranked(t, count)
	local list = {}
	for key, value in pairs(t) do
		list[#list + 1] = { key = key, value = value }
	end
	table.sort(list, function(a, b) return a.value > b.value or (a.value == b.value and a.key < b.key) end)
	while #list > count do
		table.remove(list)
	end
	return list
end

local function Zones(canvas, x, y, w, h, c)
	local ix, iy, iw, ih = Card(canvas, x, y, w, h, L["Favourite zones"])
	local items = {}
	for _, entry in ipairs(Ranked(c.zoneTime, 5)) do
		items[#items + 1] = { label = entry.key, value = entry.value, text = C.Duration(entry.value) }
	end
	if #items == 0 then
		Empty(canvas, ix, iy, iw, ih, L["Nothing recorded yet."])
	else
		HBars(canvas, ix, iy, iw, ih, items, { 0.4, 0.75, 0.4 })
	end
end

local function Foes(canvas, x, y, w, h, c)
	local ix, iy, iw, ih = Card(canvas, x, y, w, h, L["Deadliest foes"])
	local items = {}
	for _, entry in ipairs(Ranked(c.killers, 5)) do
		items[#items + 1] = { label = entry.key, value = entry.value, text = tostring(entry.value) }
	end
	if #items == 0 then
		Empty(canvas, ix, iy, iw, ih, L["No deaths yet."])
	else
		HBars(canvas, ix, iy, iw, ih, items, { 0.9, 0.3, 0.25 })
	end
end

local function Travel(canvas, x, y, w, h, c)
	local ix, iy, iw, ih = Card(canvas, x, y, w, h, L["On the road"])
	local s = c.stats
	local parts = {
		{ value = s.walked, label = L["On foot"], text = C.Distance(s.walked), color = { 0.85, 0.7, 0.4 } },
		{ value = s.ridden, label = L["Riding"], text = C.Distance(s.ridden), color = { 0.6, 0.45, 0.25 } },
		{ value = s.swum, label = L["Swimming"], text = C.Distance(s.swum), color = { 0.3, 0.6, 0.95 } },
		{ value = s.flown, label = L["Flight paths"], text = C.Distance(s.flown), color = { 0.75, 0.75, 0.9 } },
	}
	if s.walked + s.ridden + s.swum + s.flown <= 0 then
		Empty(canvas, ix, iy, iw, ih, L["Nothing recorded yet."])
	else
		Split(canvas, ix, iy, iw, ih, parts)
	end
end

local QUALITY = { [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 } }

local function Loot(canvas, x, y, w, h, c)
	local ix, iy, iw, ih = Card(canvas, x, y, w, h, L["Loot by quality"])
	local s = c.stats
	local parts = {
		{ value = s.loot2, label = L["Uncommon items"], text = C.Number(s.loot2), color = QUALITY[2] },
		{ value = s.loot3, label = L["Rare items"], text = C.Number(s.loot3), color = QUALITY[3] },
		{ value = s.loot4, label = L["Epic items"], text = C.Number(s.loot4), color = QUALITY[4] },
	}
	if s.loot2 + s.loot3 + s.loot4 <= 0 then
		Empty(canvas, ix, iy, iw, ih, L["Nothing recorded yet."])
	else
		Split(canvas, ix, iy, iw, ih, parts)
	end
end

-- The 14-day chart's metric buttons sit in its header row.
local function PlaceButtons(canvas, ix, iy, state)
	for i, metric in ipairs(METRICS) do
		local button = state.buttons[metric]
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", canvas.parent, "TOPLEFT", ix + (i - 1) * 84, -(iy - 2))
		button:SetEnabled(metric ~= state.metric)
		button:Show()
	end
end

-- Draws the whole page for c, all my characters (C.Totals; c.current: the one I play, whose session
-- and time per level it shows); state.metric is the 14-day chart's metric, state.buttons the metric
-- buttons (created by the window). Returns the page height.
function G.Draw(canvas, width, c, state)
	canvas:Reset()
	local current = c.current or c
	local y = 0
	local h, ix, iy = Days(canvas, 0, y, width, c, state.metric)
	PlaceButtons(canvas, ix, iy, state)
	y = y + h + CARD_GAP
	if current == C.Char() then -- a session only exists for the character you're playing
		y = y + Session(canvas, 0, y, width, current) + CARD_GAP
	end
	y = y + Levels(canvas, 0, y, width, current) + CARD_GAP
	local half = (width - CARD_GAP) / 2
	Zones(canvas, 0, y, half, 120, c)
	Foes(canvas, half + CARD_GAP, y, half, 120, c)
	y = y + 120 + CARD_GAP
	Travel(canvas, 0, y, half, 90, c)
	Loot(canvas, half + CARD_GAP, y, half, 90, c)
	return y + 90 + 4
end

---------------------------------------------------------------------------
-- A friend's page: an account from C.Accounts (their journals, passed on between friends, and the
-- days their older builds sent live), so it also covers the time you weren't online
---------------------------------------------------------------------------

local MY_COLOR = { 1, 0.78, 0.2 }
local THEIR_COLOR = BAR_BLUE
local WEEK = { "played", "xp", "levels", "quests", "kills", "deaths", "afk" }

local function Sum(days, count)
	local sum = { played = 0, xp = 0, levels = 0, quests = 0, kills = 0, deaths = 0, afk = 0 }
	for i = 0, count - 1 do
		local b = days[date("%Y-%m-%d", C.DayAgo(i))]
		if b then
			for key in pairs(sum) do
				sum[key] = sum[key] + (b[key] or 0)
			end
		end
	end
	return sum
end

local function Label(key)
	if METRIC_LABEL[key] then
		return METRIC_LABEL[key]()
	end
	return key == "levels" and L["Levels"] or L["Deaths"]
end

-- Seven numbers for the last 7 days, as tiles.
local function Week(canvas, x, y, w, days)
	local h = 84
	local ix, iy, iw = Card(canvas, x, y, w, h, L["Last 7 days"])
	local sum = Sum(days, 7)
	local tileW = iw / #WEEK
	for i, key in ipairs(WEEK) do
		local tx = ix + (i - 1) * tileW
		canvas:Rect(tx + 2, iy, tileW - 4, 46, 1, 1, 1, 0.04, "BORDER")
		canvas:Text(MetricText(key, sum[key]), tx, iy + 6, "GameFontHighlightLarge", "CENTER", tileW)
		canvas:Text(Label(key), tx, iy + 30, "GameFontNormalSmall", "CENTER", tileW)
	end
	return h
end

-- You and them over the last 7 days, two bars per number.
local function Versus(canvas, x, y, w, mine, theirs, name)
	local rows = { "played", "xp", "quests", "kills", "afk" }
	local rowH = 32
	local h = HEADER + 4 + #rows * rowH + PAD
	local function Hex(c)
		return ("%02x%02x%02x"):format(math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
	end
	local note = ("|cff%s%s|r   |cff%s%s|r"):format(Hex(MY_COLOR), L["You"], Hex(THEIR_COLOR), name)
	local ix, iy, iw = Card(canvas, x, y, w, h, L["You and %s, last 7 days"]:format(name), note)
	local labelW, valueW = iw * 0.22, 80
	local barW = iw - labelW - valueW
	for i, key in ipairs(rows) do
		local ry = iy + (i - 1) * rowH
		canvas:Text(Label(key), ix, ry + 9, "GameFontHighlightSmall", "LEFT", labelW - 4)
		local max = math.max(mine[key], theirs[key])
		for j, side in ipairs({ { mine[key], MY_COLOR }, { theirs[key], THEIR_COLOR } }) do
			local by = ry + (j - 1) * 13
			canvas:Rect(ix + labelW, by, barW, 11, 1, 1, 1, 0.05, "BORDER")
			if max > 0 and side[1] > 0 then
				canvas:Bar(ix + labelW, by, barW * side[1] / max, 11, side[2])
			end
			canvas:Text(MetricText(key, side[1]), ix + labelW + barW + 6, by, "GameFontHighlightSmall", "LEFT", valueW - 6)
		end
	end
	return h
end

-- Their latest entries from the friends' feed.
local function News(canvas, x, y, w, lines)
	local lineH = 15
	local h = HEADER + 4 + math.max(#lines, 1) * lineH + PAD
	local ix, iy, iw, ih = Card(canvas, x, y, w, h, L["Latest news"])
	if #lines == 0 then
		Empty(canvas, ix, iy, iw, ih, L["Nothing recorded yet."])
	end
	for i, line in ipairs(lines) do
		canvas:Text(line, ix, iy + (i - 1) * lineH, "GameFontHighlightSmall", "LEFT", iw)
	end
	return h
end

-- You and them, lifetime: from their journal's profile (synced friends only).
local LIFETIME = { "played", "quests", "kills", "deaths", "zones", "dungeons", "bosses", "rares", "dist", "jumps",
	"achievements" }

local function Lifetime(canvas, x, y, w, mine, theirs, name, person)
	local rowH = 17
	local h = HEADER + 4 + #LIFETIME * rowH + 22 + PAD
	local ix, iy, iw = Card(canvas, x, y, w, h, L["You and %s, all time"]:format(name),
		person.last and person.last > 0 and L["Last played %s"]:format(C.Ago(person.last)) or nil)
	local labelW, colW = iw * 0.4, iw * 0.3
	canvas:Text(L["You"], ix + labelW, iy, "GameFontNormalSmall", "RIGHT", colW - 10)
	canvas:Text(name, ix + labelW + colW, iy, "GameFontNormalSmall", "RIGHT", colW - 10)
	for i, key in ipairs(LIFETIME) do
		local ry = iy + 16 + (i - 1) * rowH
		local a, b = mine[key] or 0, theirs[key] or 0
		canvas:Rect(ix, ry - 2, iw, rowH, 1, 1, 1, i % 2 == 0 and 0.03 or 0, "BORDER")
		canvas:Text(G.LifetimeLabel(key), ix + 4, ry, "GameFontHighlightSmall", "LEFT", labelW)
		canvas:Text((a > b and "|cffffd200" or "|cffffffff") .. G.ValueText(key, a) .. "|r", ix + labelW, ry,
			"GameFontHighlightSmall", "RIGHT", colW - 10)
		canvas:Text((b > a and "|cffffd200" or "|cffffffff") .. G.ValueText(key, b) .. "|r", ix + labelW + colW, ry,
			"GameFontHighlightSmall", "RIGHT", colW - 10)
	end
	local facts = {}
	if person.foe and person.foe ~= "" then
		facts[#facts + 1] = L["Deadliest foe: %s"]:format(person.foe)
	end
	if person.zone and person.zone ~= "" then
		facts[#facts + 1] = L["Favourite zone: %s"]:format(person.zone)
	end
	canvas:Text("|cff999999" .. table.concat(facts, "   ") .. "|r", ix + 4, iy + 18 + #LIFETIME * rowH, "GameFontHighlightSmall",
		"LEFT", iw - 8)
	return h
end

-- Draws a friend's page: friend = an account from C.Accounts() (all their characters added up: days;
-- with a synced journal also a profile), name = the account's (their BattleTag's), me = mine from
-- there (for the comparison: all my characters too); state as for G.Draw, plus
-- state.newsLines(friend) from the window.
function G.DrawFriend(canvas, width, friend, name, me, state)
	canvas:Reset()
	local y = 0
	local h, ix, iy = Days(canvas, 0, y, width, { daily = friend.days }, state.metric)
	PlaceButtons(canvas, ix, iy, state)
	y = y + h + CARD_GAP
	y = y + Week(canvas, 0, y, width, friend.days) + CARD_GAP
	y = y + Versus(canvas, 0, y, width, Sum(me.days, 7), Sum(friend.days, 7), name) + CARD_GAP
	if friend.profile then
		y = y + Lifetime(canvas, 0, y, width, me.profile or {}, friend.profile, name, friend) + CARD_GAP
	end
	y = y + News(canvas, 0, y, width, state.newsLines and state.newsLines(friend) or {})
	return y + 4
end

G.METRICS = METRICS
G.METRIC_LABEL = METRIC_LABEL
