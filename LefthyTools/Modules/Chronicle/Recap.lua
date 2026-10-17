local _, ns = ...
local LT = ns.LT
local C = ns.Chronicle
local M = C.module

-- Chronicle in chat (English, like all chat output): "while you were away" a minute after logging
-- in, the weekly recap, sharing a ranking in LTC; and the leaderboards (also the Compare page's).
-- Built from Characters.lua's lists. Sync.lua's tick drives the timing (C.RecapStart, C.RecapTick):
-- both wait while journals still come in (Sync.lua's requests), a few minutes at most.

local CATCHUP_AFTER, CATCHUP_WAIT = 75, 240 -- s after logging in; waiting for syncs at most this long
local RECAP_AFTER = 120

local catchUp -- { since, upTo (when it started), at, deadline }
local recapAt, recapDeadline = nil, 0 -- (the recap waits for journals until recapDeadline)

local function Beacon()
	local beacon = LT:GetModule("beacon")
	return beacon and beacon.enabled and ns.Beacon or nil
end

---------------------------------------------------------------------------
-- Leaderboards
---------------------------------------------------------------------------

-- The `count` days ending `ending` days ago, as YYYY-MM-DD, kept until the date changes: a leaderboard
-- sums them for every character and number, and asking the calendar for each (C.DayAgo) made the
-- Compare page's every draw slow.
local dayLists, dayListsOn = {}, nil
local function DaysBack(count, ending)
	ending = ending or 0
	local today = date("%Y-%m-%d")
	if dayListsOn ~= today then
		wipe(dayLists)
		dayListsOn = today
	end
	local id = count .. ":" .. ending
	local list = dayLists[id]
	if not list then
		list = {}
		for i = ending, ending + count - 1 do
			list[#list + 1] = date("%Y-%m-%d", C.DayAgo(i))
		end
		dayLists[id] = list
	end
	return list
end

-- Sums over the last `count` days (ending today, or `ending` days ago).
function C.Sum(person, metric, count, ending)
	local sum = 0
	for _, day in ipairs(DaysBack(count, ending)) do
		local b = person.days[day]
		sum = sum + (b and b[metric] or 0)
	end
	return sum
end

C.BOARD = { "played", "xp", "quests", "kills", "levels", "deaths", "dist", "jumps", "afk" }

-- Rankings over `count` days ending `ending` days ago: { [metric] = { { person, value }, ... } },
-- highest first, only those with some time played then. By character (C.Characters) by default.
function C.Leaderboard(count, ending, people)
	local board = {}
	people = people or C.Characters()
	for _, metric in ipairs(C.BOARD) do
		local list = {}
		for _, person in ipairs(people) do
			if C.Sum(person, "played", count, ending) > 0 then
				local value = C.Sum(person, metric, count, ending)
				if value > 0 then
					list[#list + 1] = { person = person, value = value }
				end
			end
		end
		table.sort(list, function(a, b)
			return a.value > b.value or (a.value == b.value and ((a.person.name or "") < (b.person.name or "")
				or (a.person.name == b.person.name and a.person.key < b.person.key)))
		end)
		board[metric] = list
	end
	return board
end

---------------------------------------------------------------------------
-- Chat: while you were away, the weekly recap, sharing
---------------------------------------------------------------------------

local NEWS_CHAT = {
	level = function(f) return ("reached level %s"):format(f.level or f.a or "?") end,
	death = function(f) return f.foe and ("died to %s"):format(f.foe) or "died" end,
	zone = function(f) return ("discovered %s"):format(f.a) end,
	dungeon = function(f) return ("entered %s"):format(f.a) end,
	boss = function(f) return ("defeated %s"):format(f.a) end,
	rare = function(f) return ("killed the rare %s"):format(f.a) end,
	loot = function(f) return ("looted %s"):format(C.QualityText(f.a or "?", tonumber(f.b))) end,
	mount = function(f) return ("got the mount %s"):format(f.a) end,
	achievement = function(f) return ("earned %s"):format(f.a) end,
	quests = function(f) return ("completed %s quests"):format(f.a) end,
	gold = function(f) return ("has %s gold"):format(f.a) end,
	-- (a profession learned has no skill level: only milestones do)
	profession = function(f)
		return (f.b or "") ~= "" and ("reached %s %s"):format(f.a, f.b) or ("learned %s"):format(f.a)
	end,
}
local CHAT_ORDER = { level = 1, boss = 2, rare = 3, dungeon = 4, achievement = 5, mount = 6, loot = 7, profession = 8,
	quests = 9, gold = 10, death = 11, zone = 12 }

local function Coloured(name, classFile)
	return LT.Window.ClassColorCode(classFile) .. (name or "?") .. "|r"
end

-- One line per friend's character, the most notable first: "Anna Brook: reached level 24, defeated
-- Hogger, died 2x (+5 more)". What happened after since (and up to upTo, if given).
function C.CatchUpLines(since, upTo)
	local byChar, order = {}, {}
	for _, f in ipairs(C.FriendNews()) do
		if f.t > since and (not upTo or f.t <= upTo) and NEWS_CHAT[f.k] then
			local entry = byChar[f.key]
			if not entry then
				entry = { name = f.name, partial = f.partial, classFile = f.classFile, items = {}, deaths = 0, zones = 0 }
				byChar[f.key] = entry
				order[#order + 1] = f.key
			end
			if f.k == "death" then
				entry.deaths = entry.deaths + 1
			elseif f.k == "zone" then
				entry.zones = entry.zones + 1
			else
				entry.items[#entry.items + 1] = f
			end
		end
	end
	local lines = {}
	for _, key in ipairs(order) do
		local entry = byChar[key]
		table.sort(entry.items, function(a, b) return (CHAT_ORDER[a.k] or 99) < (CHAT_ORDER[b.k] or 99) end)
		local parts = {}
		for i, f in ipairs(entry.items) do
			if i > 3 then
				break
			end
			parts[#parts + 1] = NEWS_CHAT[f.k](f)
		end
		if entry.zones > 0 then
			parts[#parts + 1] = entry.zones == 1 and "discovered a zone" or ("discovered %d zones"):format(entry.zones)
		end
		if entry.deaths > 0 then
			parts[#parts + 1] = entry.deaths == 1 and "died once" or ("died %d times"):format(entry.deaths)
		end
		local more = #entry.items - 3
		lines[#lines + 1] = Coloured(entry.name, entry.classFile) .. C.Mark(entry.partial) .. ": " .. table.concat(parts, ", ")
			.. (more > 0 and (" (+%d more)"):format(more) or "")
	end
	return lines
end

local LABEL_CHAT = { played = "time played", xp = "XP", quests = "quests", kills = "killing blows", levels = "levels",
	deaths = "deaths", dist = "distance", jumps = "jumps", afk = "time AFK" }

-- A value as chat text (English).
function C.ChatValue(metric, value)
	if metric == "played" or metric == "afk" then
		return C.Duration(value)
	elseif metric == "dist" then
		return C.Distance(value, true)
	end
	return C.Number(value)
end

-- The week's leaderboard in a few lines: the leader of each, plus the Martin award.
function C.RecapLines(count, ending)
	local board, lines = C.Leaderboard(count, ending), {}
	for _, metric in ipairs(C.BOARD) do
		local list = board[metric]
		if list[1] and #list >= 1 then
			local first = list[1]
			local title = metric == "deaths" and "most deaths" or metric == "afk" and "Martin award (most time AFK)"
				or ("most " .. LABEL_CHAT[metric])
			lines[#lines + 1] = ("%s: %s%s (%s)"):format(title, Coloured(first.person.name, first.person.classFile),
				C.Mark(first.person.partial), C.ChatValue(metric, first.value))
		end
	end
	return lines, board
end

-- Shares a line in LTC (Beacon's /ltc), or prints it if that isn't on.
function C.ShareLine(text)
	local B = Beacon()
	local beacon = LT:GetModule("beacon")
	if B and B.SendChat and beacon.db.lefthyChat then
		B.SendChat(text)
	else
		M:Print(text .. " (LTC is off: only you see this.)")
	end
end

-- Monday of the week `back` weeks ago, as YYYY-MM-DD.
local function Monday(back)
	local t = date("*t")
	local sinceMonday = (t.wday + 5) % 7 -- wday: 1 = Sunday
	return date("%Y-%m-%d", time({ year = t.year, month = t.month, day = t.day - sinceMonday - 7 * (back or 0), hour = 12 }))
end
C.Monday = Monday

-- Last week's leaderboard, once a week: once journals have come in (or a few minutes passed), and
-- only marked done when it was shown (alone or with nobody's data yet: tried again next login).
local function Recap(now)
	if next(C.SyncPending()) and now < recapDeadline then
		return -- (journals still coming in)
	end
	recapAt = nil
	local store, week = C.Store(), Monday(0)
	if store.recapWeek == week then
		return
	end
	-- Last week: Monday to Sunday, ending (days since this Monday + 1) days ago.
	local t = date("*t")
	local ending = (t.wday + 5) % 7 + 1
	local lines, board = C.RecapLines(7, ending)
	local people, count = {}, 0 -- (two of my own characters aren't a comparison)
	for _, entry in ipairs(board.played or {}) do
		local who = entry.person.me and "me" or entry.person.acct or entry.person.key
		if not people[who] then
			people[who], count = true, count + 1
		end
	end
	if count < 2 then
		return -- (alone, or nobody's days yet: nothing to compare)
	end
	store.recapWeek = week
	M:Print("last week's leaderboard (Chronicle):")
	for _, line in ipairs(lines) do
		print("   |cffffd200•|r " .. line)
	end
end

local function CatchUp(now)
	if next(C.SyncPending()) and now < catchUp.deadline then
		return -- (journals still coming in)
	end
	local since, upTo = catchUp.since, catchUp.upTo
	catchUp = nil
	local lines = C.CatchUpLines(since, upTo) -- (since logging in, friends' news came live, with chat lines)
	if #lines == 0 then
		return
	end
	M:Print(("while you were away (since %s):"):format(date("%H:%M %b %d", since)))
	for i, line in ipairs(lines) do
		if i > 6 then
			print(("   |cffffd200•|r and %d more friends: /chronicle"):format(#lines - 6))
			break
		end
		print("   |cffffd200•|r " .. line)
	end
end

-- Chronicle started (Sync.lua's C.SyncEnable): what friends did since my last tick, if that was
-- more than 5 minutes ago (a /reload isn't news), and the weekly recap a little later.
function C.RecapStart(now)
	local lastSeenAt = C.Store().lastSeenAt
	if lastSeenAt and time() - lastSeenAt > 300 then
		catchUp = { since = lastSeenAt, upTo = time(), at = now + CATCHUP_AFTER, deadline = now + CATCHUP_WAIT }
	end
	recapAt, recapDeadline = now + RECAP_AFTER, now + RECAP_AFTER + CATCHUP_WAIT
end

-- On Sync.lua's tick.
function C.RecapTick(now)
	if catchUp and now >= catchUp.at then
		if M.db.catchUp then
			CatchUp(now)
		else
			catchUp = nil
		end
	end
	if recapAt and now >= recapAt then
		if M.db.weeklyRecap then
			Recap(now)
		else
			recapAt = nil
		end
	end
end

function C.RecapStop()
	catchUp, recapAt = nil, nil
end
