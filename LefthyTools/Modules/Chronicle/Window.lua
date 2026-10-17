local _, ns = ...
local LT = ns.LT
local L = ns.L
local C = ns.Chronicle
local M = C.module

-- The Chronicle window: an account picker (you or a friend by BattleTag, each with their
-- characters) and six pages. Timeline (all your characters' journals in one, newest first, by
-- day), Statistics (yours, all your characters added up, plus this session and each character's
-- level; labels left and values right in two text blocks of the same line count), Graphs (you or a
-- friend, all their characters), Compare (every character, yours and your friends', in every graph,
-- Graphs.lua's G.DrawCompare), News (what friends' characters did: synced journals and live news,
-- Sync.lua's C.FriendNews) and Friends (who's online, who isn't: a row per character, its BattleTag
-- beside it; two tables, G.DrawTables; a click on a row opens their account's graphs). A character
-- is shown by the name the game shows (with its surname), and only ever once.
-- Built on first open; redrawn only while open and only when something changed (the Statistics
-- page also every few seconds, for the time and distance counters).

local TIMELINE_SHOW = 250  -- entries drawn; older ones are summarized in one line
local STATS_REFRESH = 5
local GRAPHS_MIN_GAP, GRAPHS_REFRESH = 10, 30 -- graphs: redraw on changes at most every 10 s, else every 30 s
local FEED_MIN_GAP = 3 -- friends' news: the News and Friends pages and the minimap dot follow at most this often
local TAB_WIDTH = 80 -- (six tabs and the picker fit in a row)

local ICONS = C.Graphs.EVENT_ICONS

local frame
local tab = "timeline"
local selectedKey
local lastStatsRefresh, lastGraphsRefresh, graphsPending = 0, 0, false
local feedPending, dotPending, lastDot = false, false, -math.huge
local graphState = { metric = "played", buttons = {} }
local compareState = { range = 14, hidden = {} }

local function Icon(e)
	return C.Graphs.IconText(e.icon or ICONS[e.k] or ICONS.quests)
end

local function Where(zone, sub)
	if zone and zone ~= "" and sub then
		return zone .. " - " .. sub
	end
	return (zone ~= "" and zone) or sub
end

-- One timeline line (localized), for my events and friends' alike.
local TEXT = {
	level = function(e)
		local text = L["Level %d"]:format(e.level or 0)
		if e.zone and e.zone ~= "" then
			text = text .. " - " .. e.zone
		end
		if e.took then
			text = text .. " " .. L["(took %s)"]:format(C.Duration(e.took))
		end
		return text
	end,
	death = function(e)
		local text = e.foe and L["Died to %s"]:format(e.foe) or L["Died"]
		local where = Where(e.zone, e.sub)
		if where then
			text = text .. " - " .. where
		end
		if e.level then
			text = text .. " " .. L["(level %d)"]:format(e.level)
		end
		return text
	end,
	zone = function(e) return L["Discovered %s"]:format(e.zone) end,
	dungeon = function(e) return L["First visit: %s"]:format(e.name) end,
	boss = function(e)
		return L["Defeated %s"]:format(e.name) .. ((e.instance and e.instance ~= "") and (" (" .. e.instance .. ")") or "")
	end,
	rare = function(e)
		return L["Killed the rare %s"]:format(e.name) .. ((e.zone and e.zone ~= "") and (" - " .. e.zone) or "")
	end,
	loot = function(e) return L["Looted %s"]:format(e.link or C.QualityText(e.name or "?", e.quality)) end,
	mount = function(e) return L["New mount: %s"]:format(e.name) end,
	pet = function(e) return L["New pet: %s"]:format(e.name) end,
	toy = function(e) return L["New toy: %s"]:format(e.name) end,
	achievement = function(e) return L["Achievement: %s"]:format(e.name) end,
	quests = function(e) return L["%s quests completed"]:format(C.Number(e.count)) end,
	gold = function(e) return L["Reached %s gold"]:format(C.Number(e.gold)) end,
	profession = function(e)
		return e.level and L["%s: skill %d"]:format(e.name, e.level) or L["Learned %s"]:format(e.name)
	end,
	quest = function(e) return L["Completed %s"]:format(e.name) end, -- friends' feed only
	online = function() return L["Came online"] end,
	offline = function() return L["Went offline"] end,
}

-- A friend's feed entry as an event of the same shape (highlights arrive as two text fields).
local function FriendEvent(f)
	local a, b, k = f.a, f.b, f.k
	local e -- (only the one shape it needs: this runs for every line drawn)
	if k == "level" then
		e = { level = f.level }
	elseif k == "death" then
		e = { foe = f.foe, zone = f.where }
	elseif k == "boss" then
		e = { name = a, instance = b }
	elseif k == "rare" then
		e = { name = a, zone = b }
	elseif k == "loot" then
		e = { name = a, quality = tonumber(b) }
	elseif k == "quests" then
		e = { count = tonumber(a) }
	elseif k == "gold" then
		e = { gold = tonumber(a) }
	elseif k == "profession" then
		e = { name = a, level = tonumber(b) }
	elseif k == "zone" then
		e = { zone = a }
	elseif k == "dungeon" or k == "mount" or k == "achievement" or k == "quest" then
		e = { name = a }
	elseif k == "online" or k == "offline" then
		e = {}
	end
	if e then
		e.k, e.t = k, f.t
	end
	return e
end

-- A death the game reported twice (PLAYER_DEAD again within seconds), saved twice by builds that
-- counted each: one this soon after the death shown before (lastDeath) isn't shown again.
local function RepeatedDeath(e, lastDeath)
	return e.k == "death" and lastDeath ~= nil and type(e.t) == "number" and math.abs(e.t - lastDeath) < C.DEATH_REPEAT
end

-- The Compare page's symbols: { [character key] = { [day] = { { icon, text, rank, t }, ... } } } over
-- the days shown, from my characters' journals and friends' news (C.FriendNews: each entry knows its
-- character). Only the notable kinds (Graphs.lua's MARK_KINDS); levels only every tenth.
local MARK_RANK = {}
for rank, kind in ipairs(C.Graphs.MARK_KINDS) do
	MARK_RANK[kind] = rank
end

compareState.marks = function(people, days)
	local marks, shown = {}, {}
	local first = days[1]
	for _, p in ipairs(people) do
		shown[p.key] = true
	end
	local function Put(key, e)
		local rank = MARK_RANK[e.k]
		if not rank or (e.k == "level" and (e.level or 0) % 10 ~= 0) or (e.k == "loot" and (e.quality or 4) < 4) then
			return
		end
		local text = TEXT[e.k](e)
		local day = text and date("%Y-%m-%d", e.t)
		if day and day >= first then
			marks[key] = marks[key] or {}
			local list = marks[key][day] or {}
			marks[key][day] = list
			list[#list + 1] = { icon = e.icon or ICONS[e.k], text = text, rank = rank, t = e.t }
		end
	end
	for storeKey, c in pairs(C.Store().chars) do
		local events = shown["me:" .. storeKey] and c.events or {}
		local from = #events + 1
		while from > 1 and type(events[from - 1].t) == "number" and date("%Y-%m-%d", events[from - 1].t) >= first do
			from = from - 1 -- (from the newest back to the first day shown)
		end
		local lastDeath
		for i = from, #events do
			local e = events[i]
			if not RepeatedDeath(e, lastDeath) then
				Put("me:" .. storeKey, e)
				lastDeath = e.k == "death" and e.t or lastDeath
			end
		end
	end
	for _, f in ipairs(C.FriendNews and C.FriendNews() or {}) do
		local key = shown[f.key] and f.key
		local e = key and type(f.t) == "number" and FriendEvent(f)
		if e then
			Put(key, e)
		end
	end
	return marks
end

local function LineFor(e, who)
	local text = TEXT[e.k] and TEXT[e.k](e)
	if not text then
		return nil
	end
	return date("%H:%M", e.t) .. "  " .. Icon(e) .. " " .. (who and (who .. ": ") or "") .. text
end

-- Newest first, a heading per day. empty: the text when there's nothing; older: entries left out
-- of the list already (counted in the summary line).
local function Journal(list, toLine, empty, older)
	local lines, lastDay = {}, nil
	local first = math.max(1, #list - TIMELINE_SHOW + 1)
	older = (older or 0) + first - 1
	for i = #list, first, -1 do
		local line, t = toLine(list[i])
		if line then
			local day = date(L["%Y-%m-%d"], t)
			if day ~= lastDay then
				if lastDay then
					lines[#lines + 1] = ""
				end
				lines[#lines + 1] = "|cffffd200" .. day .. "|r"
				lastDay = day
			end
			lines[#lines + 1] = line
		end
	end
	if older > 0 then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "|cff999999" .. L["... and %d older entries"]:format(older) .. "|r"
	end
	if #lines == 0 then
		lines[1] = "|cff999999" .. (empty or L["Nothing recorded yet."]) .. "|r"
	end
	return table.concat(lines, "\n")
end

-- A character's name in its class colour, marked while only its first name is known.
local function Named(name, classFile, partial)
	return LT.Window.ClassColorCode(classFile) .. (name or "?") .. "|r" .. C.Mark(partial)
end

-- A text page's lines plus, when a name on it is marked, what the mark means (me: my characters).
local function WithNote(text, partial, me)
	return partial and (text .. "\n\n" .. C.PartialHint(me, nil, true)) or text
end

-- My timeline: every character's journal in one (chars from C.Totals). With more than one character
-- each line says whose it is. Only the newest TIMELINE_SHOW of each can be drawn: only those are merged.
local function Timeline(chars)
	local list, older, keeping = {}, 0, 0
	for _, c in ipairs(chars) do
		keeping = keeping + (#c.events > 0 and 1 or 0)
	end
	for _, c in ipairs(chars) do
		local events = c.events
		local first = math.max(1, #events - TIMELINE_SHOW + 1)
		older = older + first - 1
		local who = keeping > 1 and Named(C.NameOf(c), c.classFile, C.Partial(c)) or nil
		local marked = who ~= nil and C.Partial(c)
		local lastDeath
		for i = first, #events do
			local e = events[i]
			if not RepeatedDeath(e, lastDeath) then
				local n = #list + 1
				list[n] = { e = e, who = who, n = n, marked = marked }
				lastDeath = e.k == "death" and e.t or lastDeath
			end
		end
	end
	table.sort(list, function(a, b) -- by time; the same second: as each journal has them
		local ta, tb = a.e.t or 0, b.e.t or 0
		return ta < tb or (ta == tb and a.n < b.n)
	end)
	local partial = false -- (a marked name among the lines drawn)
	local text = Journal(list, function(item)
		partial = partial or item.marked
		return LineFor(item.e, item.who), item.e.t
	end, nil, older)
	return WithNote(text, partial, true)
end

-- The Friends page: two tables (Graphs.lua's G.DrawTables), a row per character, named as the game
-- names it, with its account's BattleTag in a column of its own. Online now: Beacon's friends, where
-- they are and what they're doing. Not online: my friends' characters (C.Characters) whose account
-- has none online (someone playing one character isn't listed again with the others), most recently
-- played first, with when it last played, its week's time and its latest highlight. Hovering a row
-- shows all of it (and the account's characters), a click opens that account's graphs (when there
-- are any). What they all did is the News page.
local DASH = "|cff666666-|r"

-- A friend's latest highlight: an { icon, text } cell and a tooltip line (nil: none).
local function LatestCell(f)
	local e = f and FriendEvent(f)
	local text = e and TEXT[e.k] and TEXT[e.k](e)
	if not text then
		return DASH, nil
	end
	return { icon = e.icon or ICONS[e.k] or ICONS.quests, text = "|cffcccccc" .. text .. "|r  |cff888888" .. C.Ago(f.t) .. "|r" },
		Icon(e) .. " " .. text .. "  |cff888888" .. date(L["%Y-%m-%d"], f.t) .. "|r"
end

local function FriendTables(open)
	local accounts = {}
	for _, account in ipairs(C.Accounts()) do
		accounts[account.key] = account
	end
	-- Each character's latest highlight.
	local latest = {}
	for _, f in ipairs(C.FriendNews()) do
		if f.k ~= "online" and f.k ~= "offline" then
			latest[f.key] = f -- (oldest first: the last one stays)
		end
	end
	local function Tag(acct)
		local label = acct and C.AccountLabel(acct)
		return label and ("|cff80c0ff" .. label .. "|r") or nil
	end
	-- A click: the graphs of the account the character belongs to (a lone character's own).
	local function Open(key, acct)
		local account = accounts[acct and ("acct:" .. acct) or key]
		return account and function() open(account.key) end or nil
	end

	-- Online now.
	local beacon = LT:GetModule("beacon")
	local B = beacon and beacon.enabled and ns.Beacon
	local online = {}
	for _, friend in ipairs(B and B.FriendList() or {}) do
		local status = B.FriendStatus(friend.peer, friend.id)
		local key, acct = C.PeerChar(friend.peer)
		local tip = {}
		B.FriendLines(tip, friend.peer, friend.id)
		if Tag(acct) then
			table.insert(tip, 2, Tag(acct))
		end
		local _, latestLine = LatestCell(latest[key])
		tip[#tip + 1] = latestLine
		local click = Open(key, acct)
		if click then
			tip[#tip + 1] = "|cff80c0ff" .. L["Click: their graphs"] .. "|r"
		end
		online[#online + 1] = { cells = { status.name, status.level or DASH, Tag(acct) or DASH, status.where, status.doing or DASH },
			tip = tip, click = click }
	end

	-- Not online.
	local away = {}
	for _, c in ipairs(C.Characters()) do
		if not c.me and not c.online and not c.accountOnline then
			away[#away + 1] = c
		end
	end
	table.sort(away, function(a, b) return (a.last or 0) > (b.last or 0) or ((a.last or 0) == (b.last or 0) and a.key < b.key) end)
	local awayRows = {}
	for _, c in ipairs(away) do
		local week = C.Sum(c, "played", 7)
		local played = c.last and c.last > 0
		local cell, latestLine = LatestCell(latest[c.key])
		local name = Named(c.name, c.classFile, c.partial)
		local tip = { name }
		if c.partial then
			tip[#tip + 1] = C.PartialHint(false, c.account)
		end
		if c.level then
			tip[#tip + 1] = L["Level %d"]:format(c.level) .. (c.realm and (" - " .. c.realm) or "")
		end
		tip[#tip + 1] = Tag(c.acct)
		local account = c.acct and accounts["acct:" .. c.acct]
		if account and #account.chars > 1 then
			local names = {}
			for _, other in ipairs(account.chars) do
				names[#names + 1] = Named(other.name, other.classFile, other.partial) .. " " .. (other.level or "")
			end
			tip[#tip + 1] = L["All characters: %s"]:format(table.concat(names, ", "))
		end
		if played then
			tip[#tip + 1] = L["Last played %s"]:format(C.Ago(c.last))
		end
		if week > 0 then
			tip[#tip + 1] = L["%s this week"]:format(C.Duration(week))
		end
		tip[#tip + 1] = latestLine
		local click = Open(c.key, c.acct)
		if click then
			tip[#tip + 1] = "|cff80c0ff" .. L["Click: their graphs"] .. "|r"
		end
		awayRows[#awayRows + 1] = { cells = { name, c.level and tostring(c.level) or DASH, Tag(c.acct) or DASH,
			played and C.Ago(c.last) or DASH, week > 0 and C.Duration(week) or DASH, cell }, tip = tip, click = click }
	end

	local function Count(n, one, many)
		return n > 0 and ("|cff999999" .. (n == 1 and one or many:format(n)) .. "|r") or nil
	end
	return {
		{ title = L["Online now"], note = Count(#online, L["1 friend"], L["%d friends"]), rows = online,
			columns = { { title = L["Name"], w = 0.2 }, { title = L["Level"], w = 0.1, right = true }, { title = L["BattleTag"], w = 0.14 },
				{ title = L["Where"], w = 0.27 }, { title = L["Doing"], w = 0.29 } },
			empty = B and L["No friends with LefthyTools online"] or L["Unknown (Beacon is off)"] },
		{ title = L["Not online"], note = Count(#awayRows, L["1 character"], L["%d characters"]), rows = awayRows,
			columns = { { title = L["Name"], w = 0.18 }, { title = L["Level"], w = 0.07, right = true }, { title = L["BattleTag"], w = 0.15 },
				{ title = L["Last played"], w = 0.15 }, { title = L["This week"], w = 0.12 }, { title = L["Latest news"], w = 0.33 } },
			empty = L["Everyone with a journal is online, or no friend's journal has come yet."] },
	}
end


-- The News page: what friends did (synced journals and live news), newest first, by day.
local function News()
	local partial = false -- (a marked name among the lines drawn)
	local text = Journal(C.FriendNews(), function(f)
		local e = FriendEvent(f)
		partial = partial or (e ~= nil and f.partial)
		return e and LineFor(e, Named(f.name, f.classFile, f.partial)), f.t
	end, L["Your friends' level-ups, deaths, quests, new zones, dungeons, bosses, rares, epic loot, mounts and milestones show up here, and when they come online. They need an up-to-date LefthyTools for most of it."])
	return "|cffffd200" .. L["What they did"] .. "|r\n" .. WithNote(text, partial)
end

---------------------------------------------------------------------------
-- Statistics
---------------------------------------------------------------------------

local function Count(t)
	local n = 0
	for _ in pairs(t or {}) do
		n = n + 1
	end
	return n
end

-- The key with the highest value (ties: alphabetically first, so it doesn't change randomly).
local function Top(t)
	local best, most
	for key, value in pairs(t or {}) do
		if not most or value > most or (value == most and key < best) then
			best, most = key, value
		end
	end
	return best, most
end

-- A character's gold: now (the one I play), else where its last day played ended (whole gold).
local function GoldOf(c)
	if c == C.Char() then
		return GetMoney()
	end
	local last
	for day, b in pairs(c.daily) do
		if b.gold and (not last or day > last) then
			last = day
		end
	end
	return last and c.daily[last].gold * 10000 or 0
end

-- The person, not a character: t = C.Totals() (all my characters added up), each number once. Only
-- what makes sense per character is listed per character (who they are, their level); this session
-- is the one going on now. Time AFK is the Martin tracker's alone.
local function Statistics(t)
	local labels, values = {}, {}
	local function Section(title)
		if #labels > 0 then
			labels[#labels + 1], values[#values + 1] = "", ""
		end
		labels[#labels + 1], values[#values + 1] = "|cffffd200" .. title .. "|r", ""
	end
	local function Row(label, value)
		labels[#labels + 1], values[#values + 1] = label, "|cffffffff" .. tostring(value) .. "|r"
	end
	local s = t.stats

	local session = C.Session()
	if session then
		Section(L["This session"])
		Row(L["Time"], C.Duration(session.played))
		Row(L["Experience"], C.Number(session.xp))
		Row(L["Levels"], session.levels)
		Row(L["Quests"], session.quests)
		Row(L["Killing blows"], session.kills)
		Row(L["Deaths"], session.deaths)
		Row(L["Gold"], C.Money(session.money))
		Row(L["Distance"], C.Distance(session.distance))
	end

	Section(L["Characters"])
	local played, levelTotal, levels, gold, partial = 0, 0, 0, 0, false
	for _, c in ipairs(t.chars) do
		local realm = (c.realm and c.realm ~= GetRealmName()) and (" |cff999999- " .. c.realm .. "|r") or ""
		Row(Named(C.NameOf(c), c.classFile, C.Partial(c)) .. realm, L["Level %d"]:format(c.level or 0))
		partial = partial or C.Partial(c)
		played = played and c.playedTotal and played + c.playedTotal or nil -- (only if every one has said)
		for _, seconds in pairs(c.levelTimes) do
			levelTotal, levels = levelTotal + seconds, levels + 1
		end
		gold = gold + GoldOf(c)
	end

	Section(L["Time"])
	Row(L["Time played (since Chronicle)"], C.Duration(s.played))
	if played then
		Row(L["Time played (/played)"], C.Duration(played))
	end
	Row(L["Days played"], Count(t.days))
	Row(L["Sessions"], s.sessions)
	Row(L["Longest session"], C.Duration(s.longestSession))
	if t.fastestLevel then
		Row(L["Fastest level"], C.Duration(t.fastestLevel))
		Row(L["Average per level"], C.Duration(levelTotal / math.max(levels, 1)))
	end

	Section(L["Quests"])
	Row(L["Quests completed"], C.Number(s.quests))
	Row(L["New in WoW: Forever"], C.Number(s.foreverQuests))
	Row(L["Experience earned"], C.Number(s.xp))
	Row(L["Experience from quests"], C.Number(s.questXP))

	Section(L["Exploring"])
	Row(L["Zones discovered"], Count(t.seen.zones))
	local zone, seconds = Top(t.zoneTime)
	if zone then
		Row(L["Favourite zone"], ("%s (%s)"):format(zone, C.Duration(seconds)))
	end
	Row(L["Dungeons seen"], Count(t.seen.dungeons))
	Row(L["Dungeon runs"], s.dungeonRuns)

	Section(L["Combat"])
	Row(L["Killing blows"], C.Number(s.kills))
	Row(L["Rare elites killed"], s.rares)
	Row(L["Bosses defeated"], s.bosses)
	Row(L["Deaths"], s.deaths)
	local foe, times = Top(t.killers)
	if foe then
		Row(L["Deadliest foe"], ("%s (%d)"):format(foe, times))
	end

	Section(L["Travel"])
	Row(L["Distance"], C.Distance(s.walked + s.ridden + s.swum + s.flown))
	Row(L["On foot"], C.Distance(s.walked))
	Row(L["Riding"], C.Distance(s.ridden))
	Row(L["Swimming"], C.Distance(s.swum))
	Row(L["Flight paths"], ("%d, %s"):format(s.flights, C.Distance(s.flown)))
	Row(L["Jumps"], C.Number(s.jumps))

	Section(L["Gold and loot"])
	Row(L["Gold now"], C.Money(gold))
	Row(L["Most gold at once"], C.Money(s.maxMoney))
	Row(L["Gold earned"], C.Money(s.moneyIn))
	Row(L["Gold spent"], C.Money(s.moneyOut))
	Row(C.QualityText(L["Uncommon items"], 2), C.Number(s.loot2))
	Row(C.QualityText(L["Rare items"], 3), C.Number(s.loot3))
	Row(C.QualityText(L["Epic items"], 4), C.Number(s.loot4))

	Section(L["Collections"])
	Row(L["Mounts"], s.mounts)
	Row(L["Pets"], s.pets)
	Row(L["Toys"], s.toys)
	Row(L["Achievements"], s.achievements)

	-- The Martin tracker: time spent AFK, with a verdict by its share of the time played.
	Section(L["Martin tracker"])
	local share = s.played > 0 and s.afk / s.played or 0
	Row(L["Time AFK"], C.Duration(s.afk))
	Row(L["Share of time played"], ("%d%%"):format(math.floor(share * 100 + 0.5)))
	Row(L["Times AFK"], s.afkTimes)
	Row(L["Longest AFK"], C.Duration(s.longestAfk))
	local verdict = share < 0.05 and L["Always there"] or share < 0.15 and L["Takes a break now and then"]
		or share < 0.3 and L["Coffee enthusiast"] or L["Practically Martin"]
	Row(L["Verdict"], verdict)

	labels[#labels + 1], values[#values + 1] = "", ""
	labels[#labels + 1], values[#values + 1] = "|cff999999" .. L["Counted since %s."]:format(date(L["%Y-%m-%d"], t.first)) .. "|r", ""
	if partial then
		labels[#labels + 1], values[#values + 1] = C.PartialHint(true, nil, true), ""
	end
	return table.concat(labels, "\n"), table.concat(values, "\n")
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

-- The dropdown at the top left: accounts, each with its characters, so nobody is in it twice. "me"
-- (you: all your characters, C.Totals), then every friend (C.Accounts: "acct:<hash>" per BattleTag,
-- all their characters; a lone character whose BattleTag isn't known by its own key). Friends only
-- have graphs, so picking one opens the Graphs page.
local function IsFriend(key)
	return key ~= nil and key ~= "me"
end

local function Find(people, key)
	for _, person in ipairs(people) do
		if person.key == key then
			return person
		end
	end
end

-- "You  Cara Moss 20, Alty 12" or "Annie  Anna Brook 20, Annalt 12": whose (a friend by their
-- BattleTag's name, "(friend)" after the name while it isn't known), then their characters by name
-- with their levels, the one I play or they play most first.
local function Label(person)
	local names = {}
	for _, c in ipairs(person.chars or {}) do
		-- (mine: my records, C.Totals; a friend's: C.Characters' entries, which say partial)
		local partial = c.partial
		if partial == nil then
			partial = C.Partial(c)
		end
		names[#names + 1] = Named(C.NameOf(c), c.classFile, partial) .. (c.level and (" |cffcccccc" .. c.level .. "|r") or "")
	end
	local who = person.me and ("|cffffd200" .. L["You"] .. "|r") or person.account and ("|cff80c0ff" .. person.account .. "|r")
	if who then
		return who .. "  " .. table.concat(names, ", ")
	end
	return table.concat(names, ", ") .. "  |cff80c0ff" .. L["(friend)"] .. "|r"
end

-- A friend's latest feed entries (any of their characters'), with their date, for their graphs page.
graphState.newsLines = function(person)
	local lines, feed, keys = {}, C.FriendNews(), {}
	for _, c in ipairs(person.chars or {}) do
		keys[c.key] = true
	end
	local several = #(person.chars or {}) > 1 -- (then each line says whose)
	for i = #feed, 1, -1 do
		local f = feed[i]
		if keys[f.key] then
			local e = FriendEvent(f)
			local line = e and LineFor(e, several and Named(f.name, f.classFile, f.partial) or nil)
			if line then
				lines[#lines + 1] = "|cff999999" .. date(L["%Y-%m-%d"], f.t) .. "|r  " .. line
				if #lines == 6 then
					break
				end
			end
		end
	end
	return lines
end

local Refresh

local function Select(key)
	selectedKey = key
	if IsFriend(key) then
		tab = "graphs"
	end
	Refresh()
end

-- The picker's list, built when it opens (Core/Window.lua's own dropdown, not Blizzard's menu).
local function PickerEntries()
	local items = { { text = Label(C.Totals()), value = "me", selected = selectedKey == "me" } }
	local people = C.Accounts()
	if people[2] then
		items[#items + 1] = { divider = true }
		items[#items + 1] = { title = L["Friends"] }
		for i = 2, #people do
			local person = people[i]
			items[#items + 1] = { text = Label(person), value = person.key, selected = person.key == selectedKey }
		end
	end
	return items
end

local function Build()
	frame = LT.Window.Create("LefthyToolsChronicleFrame", "Chronicle", 780, 620)
	C.window = frame
	LT.Window.AddText(frame)
	frame.Canvas = C.Graphs.NewCanvas(frame.Content)
	for _, metric in ipairs(C.Graphs.METRICS) do
		local button = CreateFrame("Button", nil, frame.Content, "UIPanelButtonTemplate")
		button:SetSize(80, 18)
		button:SetText(C.Graphs.METRIC_LABEL[metric]())
		button:SetScript("OnClick", function()
			graphState.metric = metric
			Refresh(true)
		end)
		button:Hide()
		graphState.buttons[metric] = button
	end
	frame.Values = frame.Content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.Values:SetPoint("TOPRIGHT")
	frame.Values:SetJustifyH("RIGHT")
	frame.Values:SetJustifyV("TOP")
	frame.Values:SetSpacing(2)

	frame.Picker = LT.Window.AddPicker(frame, 240, PickerEntries, Select)
	frame.Picker:SetPoint("TOPLEFT", 14, -30)

	frame.Tabs = {}
	for i, info in ipairs({ { "friends", L["Friends"] }, { "news", L["News"] }, { "compare", L["Compare"] },
			{ "graphs", L["Graphs"] }, { "stats", L["Statistics"] }, { "timeline", L["Timeline"] } }) do
		local key = info[1]
		local button = LT.Window.AddButton(frame, info[2], function()
			tab = key
			Refresh()
		end, { "TOPRIGHT", frame, "TOPRIGHT", -10 - (i - 1) * (TAB_WIDTH + 4), -30 })
		button:SetSize(TAB_WIDTH, 22)
		frame.Tabs[key] = button
		-- New from friends: a blue count on the News tab.
		if key == "news" then
			button.New = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			button.New:SetPoint("TOPRIGHT", -2, 6)
			button.New:SetTextColor(0.4, 0.75, 1)
		end
	end
	frame:SetScript("OnHide", function() selectedKey = nil end)
end

-- top: scrolled to the top (a small chart picked for the big one).
local function RedrawCompare(top)
	Refresh(not top)
end

-- keepScroll: a refresh of the same page.
function Refresh(keepScroll)
	local people, friend -- (everyone's journals added up: only built where they're needed)
	if IsFriend(selectedKey) then
		people = C.Accounts()
		friend = tab == "graphs" and Find(people, selectedKey)
		if not friend then
			selectedKey = nil -- friends only have graphs
		end
	end
	selectedKey = selectedKey or "me"
	local picking = tab ~= "friends" and tab ~= "news" and tab ~= "compare" -- (the pages that are about one person)
	local mine = picking and not friend and C.Totals() -- all my characters
	if picking then
		frame.Picker:SetLabel(Label(friend or mine)) -- (its list is built only when it opens)
	end
	for key, button in pairs(frame.Tabs) do
		button:SetEnabled(key ~= tab) -- the open page's button is greyed out
	end
	local onCanvas = tab == "graphs" or tab == "compare" or tab == "friends"
	frame.Picker:SetShown(picking)
	if not onCanvas then
		frame.Canvas:Reset()
	end
	if tab ~= "graphs" then
		for _, button in pairs(graphState.buttons) do
			button:Hide()
		end
	end
	if tab == "news" and C.MarkFeedSeen then
		C.MarkFeedSeen() -- (before the count below)
	end
	local unseen = C.UnseenCount and C.UnseenCount() or 0
	frame.Tabs.news.New:SetText(unseen > 0 and tostring(unseen) or "")
	if onCanvas then
		frame.Text:SetText("")
		frame.Values:SetText("")
		local width = frame.Content:GetWidth()
		local height
		if tab == "friends" then
			height = C.Graphs.DrawTables(frame.Canvas, width, FriendTables(Select)) -- (a click on a row: their graphs)
			lastStatsRefresh, feedPending = GetTime(), false -- (online friends change all the time: every few seconds)
		elseif tab == "compare" then
			height = C.Graphs.DrawCompare(frame.Canvas, width, C.Characters(), compareState, RedrawCompare) -- (by character)
		elseif friend then
			height = C.Graphs.DrawFriend(frame.Canvas, width, friend, friend.name or "?", people[1], graphState)
		else
			height = C.Graphs.Draw(frame.Canvas, width, mine, graphState)
		end
		frame.Content:SetHeight(height)
		if not keepScroll then
			frame.Scroll:SetVerticalScroll(0)
		end
		lastGraphsRefresh, graphsPending = GetTime(), false
	elseif tab == "stats" then
		local labels, values = Statistics(mine)
		frame:SetBodyText(labels, keepScroll)
		frame.Values:SetText(values)
		lastStatsRefresh = GetTime()
	else
		frame:SetBodyText(tab == "news" and News() or Timeline(mine.chars), keepScroll)
		frame.Values:SetText("")
		lastStatsRefresh, feedPending = GetTime(), false
	end
end

function C.Toggle()
	if not M.enabled then
		return
	end
	if not frame then
		Build()
	end
	if frame:IsShown() then
		frame:Hide()
		return
	end
	selectedKey = "me"
	Refresh()
	frame:Show()
end

-- Opens the journal on a page ("compare", "friends", ...).
function C.Open(page)
	if not M.enabled then
		return
	end
	if not frame then
		Build()
	end
	tab = page or tab
	selectedKey = selectedKey or "me"
	Refresh()
	frame:Show()
end

-- Chronicle's 1-second tick: counters, timeline entries or the friends' feed changed since the
-- last one. Only the open page is redrawn, and only if its data changed (a kill updates a
-- counter, not the timeline).
function C.OnTick(now, statsChanged, eventsChanged, feedChanged)
	-- While journals stream in the feed changes every second: the dot and the News and Friends pages
	-- follow at most every few seconds.
	dotPending = dotPending or feedChanged
	if dotPending and now - lastDot >= FEED_MIN_GAP and C.UpdateNewDot then
		dotPending, lastDot = false, now
		C.UpdateNewDot() -- (the minimap button's blue dot)
	end
	if not (frame and frame:IsShown()) then
		return
	end
	feedPending = feedPending or feedChanged
	local redraw
	if tab == "timeline" then
		redraw = eventsChanged
	elseif tab == "friends" then
		local since = now - lastStatsRefresh
		redraw = (feedPending and since >= FEED_MIN_GAP) or since >= STATS_REFRESH -- "online now" changes all the time
	elseif tab == "news" then
		redraw = feedPending and now - lastStatsRefresh >= FEED_MIN_GAP
	elseif tab == "graphs" or tab == "compare" then
		graphsPending = graphsPending or statsChanged or eventsChanged or feedChanged -- kept until the next draw
		local since = now - lastGraphsRefresh
		redraw = (graphsPending and since >= GRAPHS_MIN_GAP) or since >= GRAPHS_REFRESH
	else
		redraw = statsChanged or eventsChanged or now - lastStatsRefresh >= STATS_REFRESH
	end
	if redraw then
		Refresh(true)
	end
end

-- For tests.
function C.ShowPage(page)
	tab = page
	if frame and frame:IsShown() then
		Refresh()
	end
end
