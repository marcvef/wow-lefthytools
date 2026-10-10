local _, ns = ...
local LT = ns.LT
local L = ns.L
local C = ns.Chronicle
local M = C.module

-- The Chronicle window: a character switcher and five pages. Timeline (this character's journal,
-- newest first, by day), Statistics (session and lifetime, labels left and values right in two text
-- blocks of the same line count), Graphs (one character or friend), Compare (you and every friend
-- in every graph, Graphs.lua's G.DrawCompare) and Friends (who's online, who isn't and since when,
-- and what they all did: synced journals and live news, Sync.lua's C.FriendNews).
-- Built on first open; redrawn only while open and only when something changed (the Statistics
-- page also every few seconds, for the time and distance counters).

local TIMELINE_SHOW = 250  -- entries drawn; older ones are summarized in one line
local STATS_REFRESH = 5
local GRAPHS_MIN_GAP, GRAPHS_REFRESH = 10, 30 -- graphs: redraw on changes at most every 10 s, else every 30 s
local FEED_MIN_GAP = 3 -- friends' news: the Friends page and the minimap dot follow at most this often
local TAB_WIDTH = 88

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

-- The Compare page's symbols: { [person key] = { [day] = { { icon, text, rank, t }, ... } } } over the
-- days shown, from my characters' journals and friends' feed (matched to their accounts by
-- character name). Only the notable kinds (Graphs.lua's MARK_KINDS); levels only every tenth.
local MARK_RANK = {}
for rank, kind in ipairs(C.Graphs.MARK_KINDS) do
	MARK_RANK[kind] = rank
end

compareState.marks = function(people, days)
	local marks, byName = {}, {}
	local first = days[1]
	for _, p in ipairs(people) do
		for _, c in ipairs(not p.me and p.chars or {}) do
			if c.name then
				byName[c.name] = p.key
			end
		end
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
	if people[1] and people[1].me then
		for _, c in pairs(C.Store().chars) do
			local events = c.events or {}
			for i = #events, 1, -1 do -- (newest first: stops at the first day shown)
				local e = events[i]
				if type(e.t) ~= "number" or date("%Y-%m-%d", e.t) < first then
					break
				end
				Put(people[1].key, e)
			end
		end
	end
	for _, f in ipairs(C.FriendNews and C.FriendNews() or {}) do
		local key = f.name and byName[f.name]
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

-- Newest first, a heading per day. empty: the text when there's nothing.
local function Journal(list, toLine, empty)
	local lines, lastDay = {}, nil
	local first = math.max(1, #list - TIMELINE_SHOW + 1)
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
	if first > 1 then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "|cff999999" .. L["... and %d older entries"]:format(first - 1) .. "|r"
	end
	if #lines == 0 then
		lines[1] = "|cff999999" .. (empty or L["Nothing recorded yet."]) .. "|r"
	end
	return table.concat(lines, "\n")
end

local function Timeline(c)
	return Journal(c.events, function(e) return LineFor(e), e.t end)
end

-- Friends not online now, from their journals: level, when they last played, this week's time,
-- and their latest highlight. Most recently played first.
local function Away(lines)
	local away = {}
	for _, person in ipairs(C.People()) do
		if not person.me and not person.online then
			away[#away + 1] = person
		end
	end
	if #away == 0 then
		return
	end
	table.sort(away, function(a, b) return (a.last or 0) > (b.last or 0) end)
	local latest = {}
	for _, f in ipairs(C.FriendNews()) do
		if f.k ~= "online" and f.k ~= "offline" then
			latest[f.name] = f -- (oldest first: the last one stays)
		end
	end
	-- Like "Online now" above: the name and level, then plain grey lines (no indenting: the font's
	-- spaces don't line up), a blank line between friends.
	lines[#lines + 1] = ""
	lines[#lines + 1] = "|cffffd200" .. L["Not online"] .. "|r"
	for i, person in ipairs(away) do
		if i > 20 then
			lines[#lines + 1] = "|cff999999" .. L["... and %d more"]:format(#away - 20) .. "|r"
			break
		end
		if i > 1 then
			lines[#lines + 1] = " "
		end
		local head = LT.Window.ClassColorCode(person.classFile) .. (person.name or "?") .. "|r"
		if person.level then
			head = head .. "  |cffcccccc" .. L["Level %d"]:format(person.level) .. "|r"
		end
		if person.account then
			head = head .. "  |cff80c0ff(" .. person.account .. ")|r"
		end
		lines[#lines + 1] = head
		local when = {}
		if person.last and person.last > 0 then
			when[#when + 1] = L["Last played %s"]:format(C.Ago(person.last))
		end
		local week = C.Sum(person, "played", 7)
		if week > 0 then
			when[#when + 1] = L["%s this week"]:format(C.Duration(week))
		end
		if #when > 0 then
			lines[#lines + 1] = "|cffaaaaaa" .. table.concat(when, "   ·   ") .. "|r"
		end
		local f = latest[person.name]
		local e = f and FriendEvent(f)
		local text = e and TEXT[e.k] and TEXT[e.k](e)
		if text then
			lines[#lines + 1] = Icon(e) .. " |cffaaaaaa" .. text .. "   ·   " .. C.Ago(f.t) .. "|r"
		end
	end
end

-- Who's online right now (each friend in a few lines, from Beacon), who isn't, then what they did.
local function Friends()
	local lines = { "|cffffd200" .. L["Online now"] .. "|r" }
	local beacon = LT:GetModule("beacon")
	local list = beacon and beacon.enabled and ns.Beacon and ns.Beacon.FriendList() or {}
	if #list == 0 then
		lines[#lines + 1] = "|cff999999" .. (beacon and beacon.enabled and L["No friends with LefthyTools online"]
			or L["Unknown (Beacon is off)"]) .. "|r"
	end
	for i, friend in ipairs(list) do
		if i > 1 then
			lines[#lines + 1] = " "
		end
		ns.Beacon.FriendLines(lines, friend.peer, friend.id)
	end
	Away(lines)
	lines[#lines + 1] = ""
	lines[#lines + 1] = "|cffffd200" .. L["What they did"] .. "|r"
	lines[#lines + 1] = Journal(C.FriendNews(), function(f)
		local e = FriendEvent(f)
		return e and LineFor(e, LT.Window.ClassColorCode(f.classFile) .. (f.name or "?") .. "|r"), f.t
	end, L["Your friends' level-ups, deaths, quests, new zones, dungeons, bosses, rares, epic loot, mounts and milestones show up here, and when they come online. They need an up-to-date LefthyTools for most of it."])
	return table.concat(lines, "\n")
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

local function Statistics(c)
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
	local s = c.stats
	local current = c == C.Char()

	if current then
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
	end

	Section(L["Character"])
	Row(L["Level"], c.level or "?")
	Row(L["Time played (since Chronicle)"], C.Duration(s.played))
	if c.playedTotal then
		Row(L["Time played (/played)"], C.Duration(c.playedTotal))
	end
	Row(L["Days played"], Count(c.days))
	Row(L["Sessions"], s.sessions)
	Row(L["Longest session"], C.Duration(s.longestSession))
	if c.fastestLevel then
		local total, levels = 0, 0
		for _, seconds in pairs(c.levelTimes) do
			total, levels = total + seconds, levels + 1
		end
		Row(L["Fastest level"], C.Duration(c.fastestLevel))
		Row(L["Average per level"], C.Duration(total / math.max(levels, 1)))
	end

	Section(L["Quests"])
	Row(L["Quests completed"], C.Number(s.quests))
	Row(L["New in WoW: Forever"], C.Number(s.foreverQuests))
	Row(L["Experience earned"], C.Number(s.xp))
	Row(L["Experience from quests"], C.Number(s.questXP))

	Section(L["Exploring"])
	Row(L["Zones discovered"], Count(c.seen.zones))
	local zone, seconds = Top(c.zoneTime)
	if zone then
		Row(L["Favourite zone"], ("%s (%s)"):format(zone, C.Duration(seconds)))
	end
	Row(L["Dungeons seen"], Count(c.seen.dungeons))
	Row(L["Dungeon runs"], s.dungeonRuns)

	Section(L["Combat"])
	Row(L["Killing blows"], C.Number(s.kills))
	Row(L["Rare elites killed"], s.rares)
	Row(L["Bosses defeated"], s.bosses)
	Row(L["Deaths"], s.deaths)
	local foe, times = Top(c.killers)
	if foe then
		Row(L["Deadliest foe"], ("%s (%d)"):format(foe, times))
	end

	Section(L["Travel"])
	Row(L["On foot"], C.Distance(s.walked))
	Row(L["Riding"], C.Distance(s.ridden))
	Row(L["Swimming"], C.Distance(s.swum))
	Row(L["Flight paths"], ("%d, %s"):format(s.flights, C.Distance(s.flown)))

	Section(L["Gold and loot"])
	if current then
		Row(L["Gold now"], C.Money(GetMoney()))
	end
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

	-- The person behind the characters (per character these mean little): all my characters
	-- together. The Martin tracker: time spent AFK, with a verdict by its share of the time played.
	local all = { played = 0, afk = 0, afkTimes = 0, longestAfk = 0, jumps = 0, quests = 0, kills = 0, deaths = 0,
		distance = 0, count = 0 }
	for _, other in pairs(C.Store().chars) do
		C.Fill(other)
		local o = other.stats
		all.count = all.count + 1
		all.played, all.afk, all.afkTimes = all.played + o.played, all.afk + o.afk, all.afkTimes + o.afkTimes
		all.longestAfk, all.jumps = math.max(all.longestAfk, o.longestAfk), all.jumps + o.jumps
		all.quests, all.kills, all.deaths = all.quests + o.quests, all.kills + o.kills, all.deaths + o.deaths
		all.distance = all.distance + o.walked + o.ridden + o.swum + o.flown
	end
	Section(L["All your characters"])
	Row(L["Characters"], all.count)
	Row(L["Time played (since Chronicle)"], C.Duration(all.played))
	Row(L["Quests completed"], C.Number(all.quests))
	Row(L["Killing blows"], C.Number(all.kills))
	Row(L["Deaths"], C.Number(all.deaths))
	Row(L["Distance"], C.Distance(all.distance))
	Row(L["Jumps"], C.Number(all.jumps))

	Section(L["Martin tracker (all your characters)"])
	local share = all.played > 0 and all.afk / all.played or 0
	Row(L["Time AFK"], C.Duration(all.afk))
	Row(L["Share of time played"], ("%d%%"):format(math.floor(share * 100 + 0.5)))
	Row(L["Times AFK"], all.afkTimes)
	Row(L["Longest AFK"], C.Duration(all.longestAfk))
	if current then
		local session = C.Session()
		if session then
			Row(L["AFK this session"], C.Duration(session.afk))
		end
	end
	local verdict = share < 0.05 and L["Always there"] or share < 0.15 and L["Takes a break now and then"]
		or share < 0.3 and L["Coffee enthusiast"] or L["Practically Martin"]
	Row(L["Verdict"], verdict)

	labels[#labels + 1], values[#values + 1] = "", ""
	labels[#labels + 1], values[#values + 1] = "|cff999999" .. L["Counted since %s."]:format(date(L["%Y-%m-%d"], c.first)) .. "|r", ""
	return table.concat(labels, "\n"), table.concat(values, "\n")
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

-- The dropdown at the top left: my characters (this one first, then the others by name), then
-- friends' characters (Sync.lua's C.People: synced journals "book:<acct>:<Name-Realm>", older
-- builds' days "friend:<Name>"; friends only have graphs, so picking one opens the Graphs page).
local function IsFriend(key)
	return key and (key:find("^book:") or key:find("^friend:")) and true or false
end

local function Keys()
	local keys, current = {}, C.CurrentKey()
	for key in pairs(C.Store().chars) do
		if key ~= current then
			keys[#keys + 1] = key
		end
	end
	table.sort(keys)
	table.insert(keys, 1, current)
	return keys
end

local function FriendPeople()
	local list = {}
	for _, person in ipairs(C.People()) do
		if not person.me then
			list[#list + 1] = person
		end
	end
	return list
end

-- "Name  Level 20" in class colour; friends marked (with their BattleTag's name), other realms named.
-- person: the friend's entry when the caller has it (else it's looked up).
local function Label(key, person)
	if IsFriend(key) then
		person = person or C.Person(key) or {}
		return LT.Window.ClassColorCode(person.classFile) .. (person.name or "?") .. "|r  |cffcccccc"
			.. (person.level and L["Level %d"]:format(person.level) or "") .. "|r  |cff80c0ff"
			.. (person.account and ("(" .. person.account .. ")") or L["(friend)"]) .. "|r"
	end
	local c = C.Store().chars[key] or {}
	return LT.Window.ClassColorCode(c.classFile) .. (c.name or "?") .. "|r  |cffcccccc" .. L["Level %d"]:format(c.level or 0)
		.. ((c.realm and c.realm ~= GetRealmName()) and (" - " .. c.realm) or "") .. "|r"
end

-- A friend's latest feed entries, with their date, for their graphs page.
graphState.newsLines = function(name)
	local lines, feed = {}, C.FriendNews()
	for i = #feed, 1, -1 do
		local f = feed[i]
		if f.name == name then
			local e = FriendEvent(f)
			local line = e and LineFor(e)
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
	local items = { { title = L["Characters"] } }
	for _, key in ipairs(Keys()) do
		items[#items + 1] = { text = Label(key), value = key, selected = key == selectedKey }
	end
	local friends = FriendPeople()
	if friends[1] then
		items[#items + 1] = { divider = true }
		items[#items + 1] = { title = L["Friends"] }
		for _, person in ipairs(friends) do
			items[#items + 1] = { text = Label(person.key, person), value = person.key, selected = person.key == selectedKey }
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
	for i, info in ipairs({ { "friends", L["Friends"] }, { "compare", L["Compare"] }, { "graphs", L["Graphs"] },
			{ "stats", L["Statistics"] }, { "timeline", L["Timeline"] } }) do
		local key = info[1]
		local button = LT.Window.AddButton(frame, info[2], function()
			tab = key
			Refresh()
		end, { "TOPRIGHT", frame, "TOPRIGHT", -10 - (i - 1) * (TAB_WIDTH + 4), -30 })
		button:SetSize(TAB_WIDTH, 22)
		frame.Tabs[key] = button
		-- New from friends: a blue count on the Friends tab.
		if key == "friends" then
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
	local keys = Keys()
	local friend = IsFriend(selectedKey) and tab == "graphs" and C.Person(selectedKey)
	if IsFriend(selectedKey) and not friend then
		selectedKey = nil -- friends only have graphs
	end
	selectedKey = selectedKey or keys[1]
	local c = not friend and (C.Store().chars[selectedKey] or C.Char())
	if c then
		C.Fill(c)
	end
	frame.Picker:SetLabel(Label(selectedKey)) -- (its list is built only when it opens)
	for key, button in pairs(frame.Tabs) do
		button:SetEnabled(key ~= tab) -- the open page's button is greyed out
	end
	frame.Picker:SetShown(tab ~= "friends" and tab ~= "compare")
	if tab ~= "graphs" and tab ~= "compare" then
		frame.Canvas:Reset()
	end
	if tab ~= "graphs" then
		for _, button in pairs(graphState.buttons) do
			button:Hide()
		end
	end
	if tab == "friends" and C.MarkFeedSeen then
		C.MarkFeedSeen() -- (before the count below)
	end
	local unseen = C.UnseenCount and C.UnseenCount() or 0
	frame.Tabs.friends.New:SetText(unseen > 0 and tostring(unseen) or "")
	if tab == "graphs" or tab == "compare" then
		frame.Text:SetText("")
		frame.Values:SetText("")
		local width = frame.Content:GetWidth()
		local height
		if tab == "compare" then
			height = C.Graphs.DrawCompare(frame.Canvas, width, C.Accounts(), compareState, RedrawCompare)
		elseif friend then
			height = C.Graphs.DrawFriend(frame.Canvas, width, friend, friend.name or "?", C.Char(), graphState)
		else
			height = C.Graphs.Draw(frame.Canvas, width, c, graphState)
		end
		frame.Content:SetHeight(height)
		if not keepScroll then
			frame.Scroll:SetVerticalScroll(0)
		end
		lastGraphsRefresh, graphsPending = GetTime(), false
	elseif tab == "stats" then
		local labels, values = Statistics(c)
		frame:SetBodyText(labels, keepScroll)
		frame.Values:SetText(values)
		lastStatsRefresh = GetTime()
	else
		frame:SetBodyText(tab == "friends" and Friends() or Timeline(c), keepScroll)
		frame.Values:SetText("")
		lastStatsRefresh, feedPending = GetTime(), false -- the friends page refreshes every few seconds too
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
	selectedKey = C.CurrentKey()
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
	selectedKey = selectedKey or C.CurrentKey()
	Refresh()
	frame:Show()
end

-- Chronicle's 1-second tick: counters, timeline entries or the friends' feed changed since the
-- last one. Only the open page is redrawn, and only if its data changed (a kill updates a
-- counter, not the timeline).
function C.OnTick(now, statsChanged, eventsChanged, feedChanged)
	-- While journals stream in the feed changes every second: the dot and the Friends page follow
	-- at most every few seconds.
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
