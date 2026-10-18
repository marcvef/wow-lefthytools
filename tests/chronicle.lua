-- Chronicle: recording, friends, the window, friends' journals, surnames, and its tick calling the
-- other files' hooks.
-- Needs: beacon.lua: Chronicle kept what happened there (my level-ups to 21, Anna's and Bob's
-- deaths and level-ups), and its pages, symbols and catch-up lines count on it.
local suite = ...
local check, section, ns, LT, lefthy = suite.check, suite.section, suite.ns, suite.LT, suite.lefthy
local printedSince, sentTo, anna, peers = suite.printedSince, suite.sentTo, suite.anna, suite.peers
local tooltipHas, afk, catchErrors = suite.tooltipHas, suite.afk, suite.catchErrors
local mark, pmark

section("Chronicle: recording")
local CH, CDB = ns.Chronicle, LefthyToolsChronicleDB
local me = CDB and CDB.chars["Lefthy-Realmy"]
local function lastEvent(kind)
	for i = #me.events, 1, -1 do if me.events[i].k == kind then return me.events[i] end end
end
local function friendsOnline() -- mocked friends only talk when told to; Beacon forgets them after 65 s
	anna("S2;;0;260.0;750.0;Goldshire;")
	Advance(0.15)
end
do
	check(LT:GetModule("chronicle").enabled and me and me.classFile == "ROGUE" and me.race == "Human" and me.realm == "Realmy",
		"on by default; a record for this character")
	check(me.stats.sessions == 1, "one session since login, got " .. tostring(me.stats.sessions))
	Fire("PLAYER_ENTERING_WORLD", false, true) -- a /reload
	check(me.stats.sessions == 1, "a /reload continues the session")
	local ticks = CH.ticks
	Advance(5)
	check(CH.ticks - ticks >= 4 and CH.ticks - ticks <= 6, "it ticks once a second, got " .. (CH.ticks - ticks))
	local played = me.stats.played
	Advance(10)
	check(math.abs(me.stats.played - played - 10) < 1.1, "time played counts")
	check(me.seen.zones["Elwynn Forest"] and lastEvent("zone"), "the zone you're in is discovered")
	check(lastEvent("level") and lastEvent("level").level == 21, "the level-ups so far are in it")
	local levels = me.stats.levels
	Fire("PLAYER_LEVEL_UP", 22)
	Advance(100)
	Fire("PLAYER_LEVEL_UP", 23)
	local lv = lastEvent("level")
	check(lv.level == 23 and lv.zone == "Elwynn Forest" and lv.took and math.abs(lv.took - 100) < 2 and me.stats.levels == levels + 2,
		"a level-up: where, and how long the level took, got " .. tostring(lv.took))

	STATE.combat, STATE.target, STATE.targetName = true, true, "Hogger"
	Advance(1.1)
	STATE.combat, STATE.target, STATE.dead = false, false, true
	Fire("PLAYER_DEAD")
	local death = lastEvent("death")
	check(death and death.foe == "Hogger" and death.zone == "Elwynn Forest" and death.sub == "Goldshire" and me.killers.Hogger == 1,
		"a death: where, and what you were fighting")
	STATE.dead = false
	Fire("PLAYER_ALIVE")

	local quests = me.stats.quests
	Fire("QUEST_TURNED_IN", 176, 450, 100)
	Fire("QUEST_TURNED_IN", 86574, 900, 0) -- new in WoW: Forever
	check(me.stats.quests == quests + 2 and me.stats.foreverQuests == 1 and me.stats.questXP == 1350,
		"quests turned in, the new-in-Forever ones counted too")
	me.stats.quests = 9
	friendsOnline()
	mark = #GAMEDATA + 1
	Fire("QUEST_TURNED_IN", 177, 100, 0)
	check(lastEvent("quests") and lastEvent("quests").count == 10, "milestone: 10 quests")
	Advance(1.2)
	check(sentTo(11, mark, "E2;")[1] == "E2;quests;10;", "milestones go to friends, got " .. tostring(sentTo(11, mark, "E2;")[1]))

	local kills = me.stats.kills
	Fire("PARTY_KILL", "Player-1-0", "Creature-0-5")
	Fire("PARTY_KILL", "Player-1-11", "Creature-0-6")
	Fire("PARTY_KILL", SECRET, "Creature-0-7")
	check(me.stats.kills == kills + 1, "my killing blows count; others' and secret ones don't")

	friendsOnline()
	STATE.target, STATE.targetName, STATE.targetGUID, TARGET_CLASS, STATE.targetDead = true, "Mor'Ladim", "Creature-0-77", "rareelite", true
	mark = #GAMEDATA + 1
	Advance(1.1)
	local rare = lastEvent("rare")
	check(rare and rare.name == "Mor'Ladim" and rare.zone == "Elwynn Forest" and me.stats.rares == 1, "a rare dies while targeted")
	Advance(2)
	check(me.stats.rares == 1, "once per spawn")
	check(sentTo(11, mark, "E2;")[1] == "E2;rare;Mor'Ladim;Elwynn Forest", "and friends hear about it, got " .. table.concat(GameDataTo(11, mark), " | ") .. " peer: " .. tostring(peers()[11]))
	STATE.tapDenied, STATE.targetGUID = true, "Creature-0-78"
	Advance(1.1)
	check(me.stats.rares == 1, "someone else's tap isn't your kill")
	STATE.target, STATE.targetDead, STATE.targetGUID, TARGET_CLASS, STATE.targetName, STATE.tapDenied = false, false, nil, "normal", nil, false

	INSTANCE = { name = "The Deadmines", type = "party" }
	friendsOnline()
	mark = #GAMEDATA + 1
	Fire("ZONE_CHANGED_NEW_AREA")
	Advance(1.1)
	check(lastEvent("dungeon") and lastEvent("dungeon").name == "The Deadmines" and me.stats.dungeonRuns == 1, "first visit to a dungeon")
	check(not me.seen.zones["The Deadmines"] and lastEvent("zone").zone ~= "The Deadmines", "... and not a zone discovered as well")
	Fire("ENCOUNTER_END", 1, "Edwin VanCleef", 1, 5, 1)
	Fire("BOSS_KILL", 1, "Edwin VanCleef")
	Fire("ENCOUNTER_END", 2, "Cookie", 1, 5, 0) -- a wipe
	check(me.stats.bosses == 1 and lastEvent("boss").name == "Edwin VanCleef" and lastEvent("boss").instance == "The Deadmines",
		"a boss kill counts once (ENCOUNTER_END and BOSS_KILL both report it), a wipe not at all")
	Advance(1.2)
	local shared = table.concat(sentTo(11, mark, "E2;"), " | ")
	check(shared:find("E2;dungeon;The Deadmines;", 1, true) and shared:find("E2;boss;Edwin VanCleef;The Deadmines", 1, true),
		"both go to friends, got " .. shared)
	INSTANCE = nil
	Fire("ZONE_CHANGED_NEW_AREA")
	Advance(1.1)
	INSTANCE = { name = "The Deadmines", type = "party" }
	Fire("ZONE_CHANGED_NEW_AREA")
	Advance(1.1)
	local dungeonEntries = 0
	for _, e in ipairs(me.events) do if e.k == "dungeon" then dungeonEntries = dungeonEntries + 1 end end
	check(me.stats.dungeonRuns == 2 and dungeonEntries == 1, "a second run is counted, but isn't news")
	lefthy("disable chronicle") -- like a /reload inside
	Advance(0.3)
	lefthy("enable chronicle")
	Advance(1.2)
	check(me.stats.dungeonRuns == 2, "a /reload inside isn't another run")
	-- A dungeon or raid boss ("worldboss" in Classic) isn't a rare; a world boss outdoors is.
	STATE.target, STATE.targetName, STATE.targetGUID, TARGET_CLASS, STATE.targetDead = true, "Edwin VanCleef", "Creature-0-90", "worldboss", true
	local raresBefore = me.stats.rares
	Advance(1.1)
	check(me.stats.rares == raresBefore, "a boss in a dungeon isn't a rare kill")
	INSTANCE = nil
	STATE.targetGUID, STATE.targetName = "Creature-0-91", "Azuregos"
	Advance(1.1)
	check(me.stats.rares == raresBefore + 1, "a world boss outdoors is")
	STATE.target, STATE.targetDead, STATE.targetGUID, TARGET_CLASS, STATE.targetName = false, false, nil, "normal", nil
	INSTANCE = nil
	ZONE = "Westfall"
	Fire("ZONE_CHANGED_NEW_AREA")
	Advance(5.1)
	check(lastEvent("zone").zone == "Westfall" and me.zoneTime.Westfall >= 3, "a new zone is discovered; time per zone counts")
	ZONE = "Elwynn Forest"
	Fire("ZONE_CHANGED_NEW_AREA")
	Advance(1.1)

	friendsOnline()
	mark = #GAMEDATA + 1
	MONEY = MONEY + 1500000
	Fire("PLAYER_MONEY")
	MONEY = MONEY - 2000
	Fire("PLAYER_MONEY")
	check(me.stats.moneyIn == 1500000 and me.stats.moneyOut == 2000 and me.stats.maxMoney == 1552000, "gold earned, spent, most at once")
	check(lastEvent("gold") and lastEvent("gold").gold == 100, "milestone: 100 gold")
	Advance(1.2)
	check(sentTo(11, mark, "E2;")[1] == "E2;gold;100;", "shared")

	friendsOnline()
	mark = #GAMEDATA + 1
	Fire("CHAT_MSG_LOOT", "You receive loot: " .. ItemLink(1155) .. ".", "Lefthy")
	Fire("CHAT_MSG_LOOT", "You receive loot: " .. ItemLink(2075) .. "x3.", "Lefthy")
	Fire("CHAT_MSG_LOOT", "Anna receives loot: " .. ItemLink(19019) .. ".", "Anna")
	Fire("CHAT_MSG_LOOT", SECRET, "Lefthy")
	Fire("CHAT_MSG_LOOT", "You receive item: " .. ItemLink(19019) .. ".", "Lefthy")
	check(me.stats.loot3 == 1 and me.stats.loot2 == 3 and me.stats.loot4 == 1, "my loot by quality (x3 counts three), not others'")
	check(lastEvent("loot").name == "Thunderfury" and lastEvent("loot").quality == 5 and lastEvent("loot").icon == 20019,
		"blue and better loot goes in the journal, with its icon")
	Advance(1.2)
	check(sentTo(11, mark, "E2;")[1] == "E2;loot;Thunderfury;5", "epic and better loot is shared")

	Fire("NEW_MOUNT_ADDED", 6)
	Fire("NEW_PET_ADDED", "BattlePet-0-1")
	Fire("NEW_TOY_ADDED", 44606)
	Fire("ACHIEVEMENT_EARNED", 6, false)
	Fire("ACHIEVEMENT_EARNED", 7, true) -- earned on another character before
	check(me.stats.mounts == 1 and me.stats.pets == 1 and me.stats.toys == 1 and me.stats.achievements == 1
		and lastEvent("mount").name == "Brown Horse" and lastEvent("pet").name == "Black Kingsnake"
		and lastEvent("toy").name == "Toy Train Set" and lastEvent("achievement").name == "Level 20", "collections and achievements")

	local jumps = me.stats.jumps
	JumpOrAscendStart()
	JumpOrAscendStart()
	TRAVEL.swimming = true
	JumpOrAscendStart()
	TRAVEL.swimming = false
	check(me.stats.jumps == jumps + 2 and JUMPS >= 3, "jumps (swimming up doesn't count)")

	local walked, ridden = me.stats.walked, me.stats.ridden
	for i = 1, 6 do PLAYER_POS = { 0.5 + i * 0.005, 0.5 }; Advance(1) end -- 5 yd a second
	check(me.stats.walked - walked >= 20 and me.stats.walked - walked <= 31, "distance on foot, got " .. (me.stats.walked - walked))
	TRAVEL.mounted = true
	for i = 1, 4 do PLAYER_POS = { 0.53 + i * 0.01, 0.5 }; Advance(1) end
	TRAVEL.mounted = false
	check(me.stats.ridden - ridden >= 30, "riding")
	local flights = me.stats.flights
	TRAVEL.taxi = true
	for i = 1, 3 do PLAYER_POS = { 0.57, 0.5 - i * 0.03 }; Advance(1) end
	TRAVEL.taxi = false
	check(me.stats.flights == flights + 1 and me.stats.flown >= 50, "flight paths and their distance")
	-- The Martin tracker: time AFK (the flag, read on the tick), how often, the longest stretch.
	local afkBefore, timesBefore, longestBefore = me.stats.afk, me.stats.afkTimes, me.stats.longestAfk
	STATE.afk = true
	Advance(30)
	STATE.afk = false
	Advance(2)
	STATE.afk = true
	Advance(10)
	STATE.afk = false
	Advance(2)
	check(math.abs(me.stats.afk - afkBefore - 40) <= 2 and me.stats.afkTimes == timesBefore + 2
		and math.abs(me.stats.longestAfk - math.max(longestBefore, 30)) <= 1.5,
		"AFK time counted: 40 s in two stretches, the longest kept (earlier tests were AFK longer), got "
		.. me.stats.afk - afkBefore .. ", " .. me.stats.afkTimes - timesBefore .. ", " .. me.stats.longestAfk)
	check(math.abs(CH.Session().afk - (me.stats.afk - me.session.stats.afk)) < 0.01 and CH.Session().afk >= 39, "and per session")
	check((me.daily[date("%Y-%m-%d")].afk or 0) >= 39, "and per day (for the graphs)")
	walked = me.stats.walked
	PLAYER_POS = { 0.95, 0.95 } -- hearthstone
	Advance(1.1)
	check(me.stats.walked == walked, "a teleport isn't travel")
	PLAYER_POS = { 0.5, 0.5 }
	Advance(1.1)

	PROFESSIONS = { { name = "Mining", level = 70 } }
	Fire("SKILL_LINES_CHANGED")
	Advance(1.1)
	check(lastEvent("profession") and lastEvent("profession").name == "Mining" and not lastEvent("profession").level, "a new profession")
	friendsOnline()
	mark = #GAMEDATA + 1
	PROFESSIONS[1].level = 76
	Fire("SKILL_LINES_CHANGED")
	Advance(1.1)
	check(lastEvent("profession").level == 75, "profession milestone: 75")
	Advance(1.2)
	check(sentTo(11, mark, "E2;")[1] == "E2;profession;Mining;75", "shared")
	PROFESSIONS = {}

	local xp = me.stats.xp
	XP.current = 1800
	Fire("PLAYER_XP_UPDATE")
	PLAYER_LEVEL, XP.current = 20, 200
	Fire("PLAYER_XP_UPDATE")
	check(me.stats.xp == xp + 300 + 4400, "experience, also across a level-up, got " .. (me.stats.xp - xp))
	PLAYER_LEVEL = 19
	Fire("TIME_PLAYED_MSG", 360000, 3600)
	check(me.playedTotal == 360000, "what /played said is kept")

	local session = CH.Session()
	check(session.levels >= 2 and session.quests >= 3 and session.deaths >= 1 and session.money == 1498000,
		"this session: levels, quests, deaths, gold")
	pmark = #PRINTED + 1
	SlashCmdList.LEFTHYTOOLS_CHRONICLE("session")
	check(printedSince(pmark):find("this session: ", 1, true), "/chronicle session")
end

section("Chronicle: friends")
do
	anna("H2") -- Anna is around (and known by name) again
	Advance(1.2)
	local feed = CDB.friends
	local before = #feed
	pmark = #PRINTED + 1
	Advance(60) -- a fresh highlight window for Anna
	anna("E2;boss;Hogger;Elwynn Forest")
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "E2;hack;x;y", "WHISPER", 11)
	check(#feed == before, "nothing recorded inside the event handler")
	Advance(0.15)
	check(#feed == before + 1 and feed[#feed].k == "boss" and feed[#feed].name == "Anna Brook" and feed[#feed].a == "Hogger",
		"a friend's highlight goes into the feed (unknown kinds are dropped)")
	check(printedSince(pmark):find("Anna Brook|r defeated Hogger (Elwynn Forest).", 1, true), "with a chat line")
	for i = 1, 10 do anna("E2;rare;Rare" .. i .. ";Duskwood") end
	Advance(0.15)
	check(#feed == before + 10, "at most 10 highlights a minute from one friend, got " .. (#feed - before))
	Advance(60)
	pmark = #PRINTED + 1
	anna("E2;quest;The Defias Brotherhood;")
	anna("E2;zone;Westfall;")
	Advance(0.15)
	check(feed[#feed - 1].k == "quest" and feed[#feed].k == "zone" and feed[#feed].a == "Westfall"
		and not printedSince(pmark):find("Westfall", 1, true) and not printedSince(pmark):find("Defias", 1, true),
		"friends' quests and new zones go into the feed, not into chat")
	QUESTS = { { id = 500, title = "The Defias Brotherhood", objectives = {} } }
	mark = #GAMEDATA + 1
	Fire("QUEST_TURNED_IN", 500, 0, 0)
	Advance(1.2)
	check(sentTo(11, mark, "E2;quest;")[1] == "E2;quest;The Defias Brotherhood;", "my quests go to my friends' feeds")
	QUESTS = {}
	anna("Q2") -- she switches Beacon off (or logs off)
	Advance(0.15)
	check(feed[#feed].k == "offline" and feed[#feed].name == "Anna Brook", "a friend going offline is in the feed")
	local dmark = #GAMEDATA + 1
	me.daily["2030-05-15"].afk = 600 -- 10 minutes AFK today
	anna("H2")
	Advance(1.2)
	check(feed[#feed].k == "online" and feed[#feed].name == "Anna Brook", "and coming back online")
	Advance(2)
	local days = sentTo(11, dmark, "D2;")
	check(#days >= 1 and days[#days]:find("^D2;20300515;%d+;%d+;%d+;%d+;%d+;%d+$"),
		"a friend who shows up gets my last days for their graphs, got " .. table.concat(days, " | "))
	check(sentTo(11, dmark, "K2;")[1] == "K2;20300515;10", "... and each day's AFK time, in a message of its own (older builds ignore it)")
	do -- back again soon (a /reload): she has the week, only today goes
		local newestWas = feed[#feed]
		anna("Q2")
		Advance(0.15)
		local again = #GAMEDATA + 1
		anna("H2")
		Advance(3.2)
		local sent = sentTo(11, again, "D2;")
		local onlyToday = #sent >= 1
		for _, m in ipairs(sent) do onlyToday = onlyToday and m:find("^D2;20300515;") ~= nil end -- (today's regular share may come too)
		check(onlyToday and #sentTo(11, again, "K2;") >= 1,
			"a friend back within 10 minutes: only today, not the whole week again, got " .. table.concat(sent, " | "))
		-- (her offline and online lines: the later checks count on her news; with the comings' share
		-- full, each pushed out an older one, so the feed didn't grow)
		while feed[#feed] ~= newestWas do table.remove(feed) end
	end
	anna("D2;20300514;90;5000;3;20;1;1")
	anna("K2;20300514;45")
	anna("D2;20300515;30;1200;2;8;0;0")
	anna("D2;2030051;1;1;1;1;1;1")
	anna("D2;20300513;2000;1;1;1;1;1") -- more minutes than a day has
	anna("K2;20300512;9999")
	Advance(0.15)
	local annaStats = CDB.friendStats["Anna Brook"]
	check(annaStats and annaStats.days["2030-05-14"].played == 5400 and annaStats.days["2030-05-14"].xp == 5000
		and annaStats.days["2030-05-15"].quests == 2 and not annaStats.days["2030-05-13"] and annaStats.classFile == "MAGE",
		"and I keep theirs (malformed days are dropped)")
	check(annaStats.days["2030-05-14"].afk == 2700 and not annaStats.days["2030-05-12"], "their AFK time joins the day")
	check(annaStats.acct == CH.Hash("Annie#1234"), "with their BattleTag's hash (from Battle.net): the days are that person's")
	annaStats.days["2030-05-14"].played = nil -- (to see it written again)
	anna("D2;20300514;90;5000;3;20;1;1") -- the day again, later
	Advance(0.15)
	check(annaStats.days["2030-05-14"].played == 5400 and annaStats.days["2030-05-14"].afk == 2700, "the day sent again keeps its AFK time")
	dmark = #GAMEDATA + 1
	-- Bob's build syncs journals (0.5.0-80 on): my days reach him with my journal, the old day
	-- messages don't (Anna's build isn't known: she gets them, as before).
	local function bob(text) Fire("BN_CHAT_MSG_ADDON", "LTBeacon", text, "WHISPER", 12) end
	bob("H2")
	peers()[12].version = "0.5.0-80-g94d1d36"
	for _ = 1, 11 do -- 5 minutes; they keep sending their heartbeats meanwhile
		anna("S2;;0;260.0;750.0;Goldshire;")
		bob("S2;;0;260.0;750.0;Goldshire;")
		Advance(30)
	end
	check(sentTo(11, dmark, "D2;20300515;")[1], "today's numbers go out again every 5 minutes while they change")
	check(sentTo(12, dmark, "V2;")[1] and #sentTo(12, dmark, "D2;") == 0 and #sentTo(12, dmark, "K2;") == 0,
		"not to a friend whose build syncs journals: neither when he shows up nor every 5 minutes")
	bob("Q2") -- (he's gone again: the later checks count on Anna alone)
	Advance(15)
	anna("L2;24;")
	Advance(0.15)
	check(feed[#feed].k == "level" and feed[#feed].level == 24, "friends' level-ups land in the feed too")
	REGISTERED_SETTINGS.LefthyTools_chronicle_friendsChat:SetValue(false)
	Advance(60)
	pmark = #PRINTED + 1
	anna("E2;mount;Brown Horse;")
	Advance(0.15)
	check(feed[#feed].k == "mount" and not printedSince(pmark):find("new mount", 1, true), "'show in chat' off: only the feed")
	REGISTERED_SETTINGS.LefthyTools_chronicle_friendsChat:SetValue(true)
	REGISTERED_SETTINGS.LefthyTools_chronicle_share:SetValue(false)
	mark = #GAMEDATA + 1
	Fire("NEW_MOUNT_ADDED", 6)
	Advance(1.2)
	check(#sentTo(11, mark, "E2;") == 0, "'share highlights' off: nothing sent")
	REGISTERED_SETTINGS.LefthyTools_chronicle_share:SetValue(true)
end

section("Chronicle: window")
do
	lefthy("chronicle")
	local win = LefthyToolsChronicleFrame
	check(win and win:IsShown() and win.Tabs.timeline and not win.Tabs.timeline:IsEnabled(), "/lefthy chronicle opens it on the timeline")
	local text = win.Text:GetText()
	for _, expected in ipairs({ "|cffffd2002030-05-15|r", "Level 23 - Elwynn Forest (took 1m)", "Died to Hogger - Elwynn Forest - Goldshire (level 19)",
			"Defeated Edwin VanCleef (The Deadmines)", "Killed the rare Mor'Ladim - Elwynn Forest", "First visit: The Deadmines",
			"Discovered Westfall", "10 quests completed", "Reached 100 gold", "Looted " .. ItemLink(19019), "New mount: Brown Horse",
			"Achievement: Level 20", "Mining: skill 75", "Learned Mining" }) do
		check(text:find(expected, 1, true), "timeline: " .. expected)
	end
	check(text:find("New mount: Brown Horse", 1, true) < text:find("Learned Mining", 1, true), "newest first")
	win.Tabs.stats:Click()
	local labels, values = win.Text:GetText(), win.Values:GetText()
	local function lines(s) local n = 1 for _ in s:gmatch("\n") do n = n + 1 end return n end
	check(lines(labels) == lines(values), "statistics: labels and values line up")
	for _, expected in ipairs({ "This session", "Killing blows", "Deadliest foe", "Rare elites killed", "Bosses defeated", "Dungeon runs",
			"Favourite zone", "On foot", "Flight paths", "Jumps", "Most gold at once", "Epic items", "Mounts", "Time played (/played)",
			"Martin tracker", "Time AFK", "Share of time played", "Times AFK", "Longest AFK", "Verdict", "Characters", "Lefthy|r" }) do
		check(labels:find(expected, 1, true), "statistics: " .. expected)
	end
	check(not labels:find("All your characters", 1, true) and not labels:find("AFK this session", 1, true)
		and select(2, labels:gsub("Time AFK", "")) == 1 and select(2, labels:gsub("Killing blows", "")) == 2,
		"each number once, for the person (the session's own aside): no character and all-characters versions side by side")
	check(values:find("Hogger (1)", 1, true) and values:find("100h 0m", 1, true) == nil and values:find("4d 4h", 1, true),
		"values: deadliest foe, /played as days and hours")
	local verdicts = { "Always there", "Takes a break now and then", "Coffee enthusiast", "Practically Martin" }
	local verdict
	for _, v in ipairs(verdicts) do if values:find(v, 1, true) then verdict = v end end
	check(verdict and labels:find("Martin tracker", 1, true), "the Martin tracker, with a verdict: " .. tostring(verdict))
	check(not win.Tabs.stats:IsEnabled() and win.Tabs.timeline:IsEnabled(), "the open page's button is greyed out")
	win.Tabs.news:Click()
	local friendsPage = win.Text:GetText()
	check(friendsPage:find("Anna Brook|r: ", 1, true) and friendsPage:find("Defeated Hogger (Elwynn Forest)", 1, true),
		"news: friends' highlights")
	check(friendsPage:find("Came online", 1, true) and friendsPage:find("Completed The Defias Brotherhood", 1, true)
		and friendsPage:find("Discovered Westfall", 1, true), "news: what happened, got\n" .. friendsPage)
	win.Tabs.friends:Click()
	friendsPage = "" -- (the Friends page's tables: everything drawn on the canvas)
	for i = 1, win.Canvas.used.text do friendsPage = friendsPage .. "\n" .. (win.Canvas.pools.text[i]:GetText() or "") end
	check(win.Text:GetText() == "" and friendsPage:find("Online now", 1, true) and friendsPage:find("\n|cff40c7ebAnna Brook|r\n", 1, true)
		and friendsPage:find("Where|r", 1, true) and friendsPage:find("Doing|r", 1, true) and friendsPage:find("1 friend|r", 1, true),
		"friends: a table of who's online now, where they are and what they're doing, got\n" .. friendsPage)
	me.daily[date("%Y-%m-%d", time() - 86400)] = { played = 3600, xp = 5000, quests = 3, kills = 20, deaths = 0, afk = 900 }
	me.daily[date("%Y-%m-%d", time() - 20 * 86400)] = { played = 99, xp = 1, quests = 1, kills = 1, deaths = 0 }
	local draws, draw = 0, CH.Graphs.Draw
	CH.Graphs.Draw = function(...) draws = draws + 1; return draw(...) end
	win.Tabs.graphs:Click()
	local canvas = win.Canvas
	local function hoverWith(title)
		for i = 1, canvas.used.hover do
			local f = canvas.pools.hover[i]
			if f.lines[1] == title then return f end
		end
	end
	local function drawnText(text)
		for i = 1, canvas.used.text do if canvas.pools.text[i]:GetText() == text then return true end end
	end
	check(draws == 1 and win.Text:GetText() == "" and not win.Tabs.graphs:IsEnabled() and canvas.used.tex > 30,
		"the Graphs page draws its cards")
	do
		local scratch = CH.Graphs.NewCanvas(CreateFrame("Frame"))
		local bar = scratch:Bar(0, 0, 10, 10, { 1, 0, 0 })
		scratch:Reset()
		local rect = scratch:Rect(0, 0, 5, 5, 0.2, 0.2, 0.2, 1)
		check(rect == bar and not rect.gradient and rect.color[1] == 0.2,
			"a texture that was a bar and is now a plain rectangle loses the bar's gradient")
	end
	local yesterday = hoverWith(date("%Y-%m-%d", time() - 86400))
	check(yesterday and yesterday.lines[2] == "Time: 1h 0m" and not hoverWith(date("%Y-%m-%d", time() - 20 * 86400)),
		"last 14 days: a bar per day with its value on hover (older days aren't shown)")
	yesterday._scripts.OnEnter(yesterday)
	check(TOOLTIP.shown and TOOLTIP.title == yesterday.lines[1] and tooltipHas("Time: 1h 0m"), "hovering a bar shows it")
	yesterday._scripts.OnLeave(yesterday)
	local xpButton -- the metric buttons live on the page
	for _, child in ipairs(win.Content._children) do if child:GetText() == "Experience" then xpButton = child end end
	xpButton:Click()
	check(not xpButton:IsEnabled() and hoverWith(date("%Y-%m-%d", time() - 86400)).lines[2] == "Experience: 5000",
		"switching the 14-day chart to experience")
	local afkButton
	for _, child in ipairs(win.Content._children) do if child:GetText() == "Time AFK" then afkButton = child end end
	afkButton:Click()
	check(hoverWith(date("%Y-%m-%d", time() - 86400)).lines[2] == "Time AFK: 15m", "the 14-day chart shows time AFK too (it's the person's)")
	xpButton:Click()
	check(canvas.used.line >= 2 and drawnText("This session"), "this session: an XP curve")
	local level22 = hoverWith("Level 22")
	check(level22 and level22.lines[2] == "1m", "time per level: a bar per level")
	check(drawnText("Elwynn Forest") and drawnText("Hogger"), "favourite zones and deadliest foes")
	check(hoverWith("On foot") and hoverWith("Epic items"), "travel and loot split bars")
	draws = 0
	Fire("PARTY_KILL", "Player-1-0", "Creature-0-100")
	Advance(2.2)
	check(draws == 0, "a change doesn't redraw the graphs right away")
	Advance(10)
	check(draws == 1, "but within 10 s (at most once)")
	CH.Graphs.Draw = draw
	-- A second character: the window is about the person, so its numbers join mine (its level stays its own).
	CDB.chars["Alty-Realmy"] = { name = "Alty", full = "Alty", realm = "Realmy", classFile = "MAGE", level = 12, -- (played with this build)
		events = { { t = time(), k = "level", level = 12 } }, stats = { quests = 7, afk = 600, played = 1200 },
		daily = { [date("%Y-%m-%d", time() - 86400)] = { played = 1800, xp = 100, quests = 1, kills = 2, deaths = 0, afk = 300 } } }
	-- The picker: our own dropdown (a Blizzard menu opened from addon code taints gamepad mode).
	local picker = win.Picker
	picker.GetText = function(self) return self.Label:GetText() end
	picker.Pick = function(self, name) -- open it and click the entry with that name
		self:Click()
		for i = 1, self.List.count do
			local row = self.List.rows[i]
			if row.kind == "entry" and row.Text:GetText():find(name, 1, true) then row:Click() return end
		end
		error("no entry " .. name)
	end
	check(picker._kind == "Button" and not picker._template, "the picker is a plain button of ours, not Blizzard's DropdownButton")
	local built = picker.List.builds
	Advance(12)
	check(picker.List.builds == built, "its list isn't built on refreshes, only when it opens")
	picker:Click()
	local menu = {}
	for i = 1, picker.List.count do
		local row = picker.List.rows[i]
		menu[#menu + 1] = row.kind == "divider" and "-" or (row.Text:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
	end
	menu = table.concat(menu, " / ")
	check(picker.List:IsShown() and menu == ("You  Lefthy %d, Alty 12 / - / Friends / Annie  Anna Brook 20"):format(me.level),
		"a click opens the list: people, not characters (you with all your characters, this one first; each friend once, by BattleTag), got " .. menu)
	check(picker.List.rows[1].Check.shown and not picker.List.rows[4].Check.shown and not picker.List.rows[3]._mouseEnabled,
		"the picked one is ticked; headings can't be clicked")
	picker.List:GetScript("OnEvent")(picker.List, "GLOBAL_MOUSE_DOWN")
	check(not picker.List:IsShown(), "a click elsewhere closes it")
	check(picker:GetText():find("^|cffffd200You|r  ") and picker:GetText():find("Lefthy|r", 1, true), "it shows who's picked: you, with your characters")
	for i = 1, 24 do CDB.friendStats["Friend" .. i] = { classFile = "MAGE", level = 10, days = { [date("%Y-%m-%d")] = { played = 60 } } } end
	picker:Click()
	local _, _, _, lastX = picker.List.rows[picker.List.count]:GetPoint(1)
	check(picker.List.count > 18 and lastX > 200 and picker.List:GetWidth() >= 480,
		"a long list goes on in a second column (every row stays on screen), got x " .. tostring(lastX))
	picker.List:Hide()
	for i = 1, 24 do CDB.friendStats["Friend" .. i] = nil end
	picker:Click()
	picker:Hide() -- (its window closing hides it)
	picker:Show()
	check(not picker.List:IsShown(), "the window closing closes the list: it doesn't come back open")
	-- Pooled textures: a gradient (bars, the session curve's fill) never stays on a plain rectangle.
	local function strayGradients()
		local n = 0
		for i = 1, canvas.used.tex do
			local t = canvas.pools.tex[i]
			if t.gradient and not t.hasGradient then n = n + 1 end
		end
		return n
	end
	picker:Pick("You")
	check(drawnText("This session") and strayGradients() == 0, "my graphs, with the session curve")
	check(hoverWith(date("%Y-%m-%d", time() - 86400)).lines[2] == "Experience: 5100" and drawnText("Time per level: Lefthy"),
		"my graphs add up all my characters (Alty's day joins Lefthy's); time per level is the one I play's own")
	picker:Pick("Anna")
	local function drawnContaining(text)
		for i = 1, canvas.used.text do if (canvas.pools.text[i]:GetText() or ""):find(text, 1, true) then return true end end
	end
	check(picker:GetText():find("^|cff80c0ffAnnie|r  ") and picker:GetText():find("Anna Brook|r |cffcccccc20|r", 1, true) and drawnText("Last 7 days")
		and drawnText("You and Annie, last 7 days") and drawnText("2h 0m") and drawnContaining("Completed The Defias Brotherhood"),
		"a friend's graphs: their days, their week, you and them (by their BattleTag: it's all their characters), their latest news")
	check(strayGradients() == 0, "no bar or curve gradient left on the textures they reused, got " .. strayGradients())
	local annaDay = hoverWith(date("%Y-%m-%d", time() - 86400))
	check(annaDay and annaDay.lines[2]:find("5000", 1, true), "their 14 days, from what they sent, got " .. tostring(annaDay and annaDay.lines[2]))
	check(drawnText("Time AFK") and drawnText("45m"), "their time AFK (the person's): a tile, and a row next to yours")
	win.Tabs.timeline:Click()
	check(picker:GetText():find("You", 1, true), "friends only have graphs: other pages show you")
	win.Tabs.graphs:Click()
	check(picker:GetText():find("You", 1, true), "back on the Graphs page: still you")
	win.Tabs.timeline:Click()
	picker:Pick("Anna")
	check(not win.Tabs.graphs:IsEnabled() and picker:GetText():find("Anna", 1, true) and drawnText("Last 7 days"),
		"picking a friend on another page opens their graphs")
	win.Tabs.friends:Click()
	check(not picker:IsShown(), "the Friends page has no dropdown")
	win.Tabs.timeline:Click()
	check(picker:IsShown(), "the others do")
	check(win.Text:GetText():find("Alty|r: Level 12", 1, true) and win.Text:GetText():find("Lefthy|r: Level 23 - Elwynn Forest", 1, true),
		"the timeline: all my characters' journals in one, each line saying whose")
	win.Tabs.stats:Click()
	do
		local function stat(label) -- the value on that label's line
			local values, i = {}, 0
			for line in (win.Values:GetText() .. "\n"):gmatch("(.-)\n") do values[#values + 1] = line end
			for line in (win.Text:GetText() .. "\n"):gmatch("(.-)\n") do
				i = i + 1
				if line:find(label, 1, true) then return ((values[i] or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
			end
		end
		check(stat("Quests completed") == CH.Number(me.stats.quests + 7) and stat("Time AFK") == CH.Duration(me.stats.afk + 600)
			and stat("Alty|r") == "Level 12" and stat("Lefthy|r") == "Level " .. me.level,
			"statistics: all my characters added up; per character only who they are and their level, got "
			.. tostring(stat("Quests completed")) .. ", " .. tostring(stat("Time AFK")) .. ", " .. tostring(stat("Alty|r")))
	end
	win.Tabs.timeline:Click()
	check(picker:GetText():find("You", 1, true) and win.Text:GetText():find("Level 20", 1, true), "back to the timeline")
	local redraws, setBody = 0, win.SetBodyText
	win.SetBodyText = function(...) redraws = redraws + 1; return setBody(...) end
	Advance(1.1)
	Fire("PARTY_KILL", "Player-1-0", "Creature-0-99")
	Advance(3)
	check(redraws == 0, "a kill changes a counter, not the timeline: no redraw, got " .. redraws)
	Fire("NEW_TOY_ADDED", 1)
	Advance(1.1)
	check(redraws == 1 and win.Text:GetText():find("New toy: Toy Train Set", 1, true), "the open window follows new entries within a second")
	win.SetBodyText = setBody
	win:Hide()
	check(BINDING_NAME_LEFTHYTOOLS_CHRONICLE_TOGGLE == "Chronicle: open or close the journal", "a key binding")
	LT:GetModule("chronicle"):Toggle()
	check(win:IsShown(), "the key binding opens it")
	LT:GetModule("chronicle"):Toggle()
	check(not win:IsShown(), "and closes it")
	afk(true)
	Advance(1.1)
	check(LefthyToolsAFKFrame.Info:GetText():find("This session: ", 1, true), "the AFK screen shows the session")
	afk(false)
	Advance(0.3)
	for _ = 1, 1100 do Fire("NEW_TOY_ADDED", 1) end
	check(#me.events == 1000, "at most 1000 entries per character, got " .. #me.events)
	lefthy("disable chronicle")
	local quests = me.stats.quests
	local ticks = CH.ticks
	Fire("QUEST_TURNED_IN", 1, 0, 0)
	Advance(3)
	check(me.stats.quests == quests and CH.ticks == ticks, "switched off: nothing recorded, nothing runs")
	lefthy("enable chronicle")
	check(me.stats.sessions == 1, "switching it back on continues the session")
	Advance(1.1)
	lefthy("disable chronicle")
	me.session.last = time() - 3 * 86400 -- as if it was off at login and the session is from days ago
	local longest = me.stats.longestSession
	lefthy("enable chronicle")
	Advance(1.1)
	check(me.stats.sessions == 2 and CH.Session().played < 5 and me.stats.longestSession == longest,
		"switched on long after the last session: a new one, not the old one going on for days")
	lefthy("disable chronicle")
	me.session.last, me.session.start = nil, time() - 3 * 86400 -- from a version that didn't stamp it yet
	lefthy("enable chronicle")
	Advance(1.1)
	check(me.stats.sessions == 3 and CH.Session().played < 5 and me.stats.longestSession == longest,
		"a session without the stamp goes by its start: days old, so a new one")

	-- The minimap button.
	local mmb = CH.MinimapButton()
	check(mmb and mmb:IsShown() and mmb:GetParent() == Minimap and CH.module.db.minimapButton == true,
		"a minimap button, on by default")
	local _, _, _, bx, by = mmb:GetPoint(1)
	check(math.abs(math.sqrt(bx * bx + by * by) - 75) < 0.01 and bx < 0 and by < 0, "on the minimap's edge, lower left")
	local journal = LefthyToolsChronicleFrame
	journal:Hide()
	mmb:Click("LeftButton")
	check(journal:IsShown(), "click: the journal opens")
	mmb:Click("LeftButton")
	check(not journal:IsShown(), "click again: it closes")
	mmb:Click("RightButton")
	check(OPENED_CATEGORY == CH.module.category:GetID(), "right-click: Chronicle's settings")
	mmb._scripts.OnEnter(mmb)
	check(TOOLTIP.title == "Chronicle" and (TOOLTIP.lines[1] or ""):find("^This session: ")
		and tooltipHas("Click: open or close the journal") and tooltipHas("Right-click: settings"),
		"hovering: this session and what the clicks do")
	mmb._scripts.OnLeave(mmb)
	Minimap._centerX, Minimap._centerY = 500, 500
	CURSOR.x, CURSOR.y = 500, 640 -- straight above the minimap
	mmb._scripts.OnDragStart(mmb)
	Advance(0.05)
	mmb._scripts.OnDragStop(mmb)
	_, _, _, bx, by = mmb:GetPoint(1)
	check(CH.module.db.minimapAngle == 90 and math.abs(bx) < 0.01 and math.abs(by - 75) < 0.01 and not mmb._scripts.OnUpdate,
		"dragging moves it along the edge, saved; nothing runs once dropped")
	mmb._scripts.OnDragStart(mmb)
	check(mmb._scripts.OnUpdate, "dragging again")
	mmb._scripts.OnHide(mmb) -- the minimap hidden mid-drag (Mirage, the minimap key): no OnDragStop
	check(not mmb._scripts.OnUpdate, "hidden mid-drag: it stops following the cursor")
	lefthy("chronicle minimap")
	Advance(0.05)
	check(not mmb:IsShown() and CH.module.db.minimapButton == false, "/chronicle minimap hides it")
	lefthy("chronicle minimap")
	Advance(0.05)
	check(mmb:IsShown(), "and shows it again")
	lefthy("disable chronicle")
	Advance(0.05)
	check(not mmb:IsShown(), "Chronicle off: no button")
	lefthy("enable chronicle")
	Advance(0.05)
	check(mmb:IsShown(), "on again: back")
end

section("Chronicle: friends' journals, also when they're offline")
do
	local H = CH.Hash
	local mine, annaAcct, bobAcct, carl, zed = H("Me#1111"), H("Annie#1234"), H("Bobby#2345"), H("Carl#3456"), H("Zed#9999")
	check(mine:match("^%x%x%x%x%x%x%x%x$") and mine ~= annaAcct and H("annie#1234") == annaAcct and CH.MyAccount() == mine,
		"accounts go by a hash of the BattleTag (8 hex, the same in any case)")
	local function bob(text) Fire("BN_CHAT_MSG_ADDON", "LTBeacon", text, "WHISPER", 12) end
	local function fields(m)
		local f = {}
		for x in (m .. ";"):gmatch("([^;]*);") do f[#f + 1] = x end
		return f
	end
	Advance(6)
	mark = #GAMEDATA + 1
	anna("H2")
	bob("H2")
	Advance(2)
	check(sentTo(11, mark, "J2;h;" .. mine)[1], "my answers say I sync journals, with my account's hash")
	anna("J2;h;" .. annaAcct)
	bob("J2;h;" .. bobAcct)
	Advance(1.2)
	local summary = sentTo(11, mark, "J2;s;")[1] or ""
	check(summary:find(mine .. ",%d+") and not summary:find(annaAcct, 1, true),
		"a friend who syncs hears what I hold: my journal (not theirs), got " .. summary)
	local myU = tonumber(summary:match(mine .. ",(%d+)"))

	-- Anna asks for my journal: my characters' profiles, days and highlights, then the end.
	Fire("NEW_MOUNT_ADDED", 6)
	Advance(1.1)
	local mount = me.events[#me.events]
	check(mount.k == "mount" and mount.n and mount.u and mount.u > myU - 1, "a new highlight gets its number and stamp")
	mark = #GAMEDATA + 1
	anna("J2;q;" .. mine .. ";0")
	Advance(8)
	local profiles, days, news = sentTo(11, mark, "J2;p;"), sentTo(11, mark, "J2;d;"), sentTo(11, mark, "J2;n;")
	local ends = sentTo(11, mark, "J2;e;" .. mine .. ";")
	check(#profiles >= 2 and #days >= 1 and #news >= 1 and #ends == 1, ("she gets it all: %d profiles, %d days, %d highlights, the end")
		:format(#profiles, #days, #news))
	local p = fields(profiles[1])
	check(#p == 11 and p[1] == "J2" and p[2] == "p" and p[3] == mine and (p[4] == "Lefthy-Realmy" or p[4] == "Alty-Realmy")
		and select(2, p[9]:gsub(",", "")) == 20, "a profile: account, character, stamp, class, level, last played, 21 numbers, foe, zone")
	local alts = false
	for _, m in ipairs(profiles) do alts = alts or m:find(";Alty%-Realmy;") ~= nil end
	check(alts, "all my characters (setting on)")
	local d = fields(days[#days])
	check(#d == 7 and d[6]:match("^%d%d%d%d%d%d%d%d$") and select(2, d[7]:gsub(",", "")) == 13, "a day: 14 numbers")
	local mountNews
	for _, m in ipairs(news) do if m:find(";mount;Brown Horse;") then mountNews = m end end
	check(mountNews and #mountNews <= 250, "the new mount among the highlights")
	for _, m in ipairs(sentTo(11, mark, "J2;")) do
		check(#m <= 250, "every message fits: " .. m:sub(1, 40))
	end

	-- Anna holds Carl's journal (Carl is my friend, offline) and a stranger's: I ask for Carl's only.
	mark = #GAMEDATA + 1
	anna("J2;s;" .. carl .. ",5000/" .. zed .. ",6000")
	Advance(0.3)
	check(sentTo(11, mark, "J2;q;" .. carl .. ";0")[1] and not sentTo(11, mark, "J2;q;" .. zed)[1],
		"a journal of a friend of mine is asked for; a stranger's isn't")
	bob("J2;s;" .. carl .. ",5000")
	Advance(0.3)
	check(not sentTo(12, mark, "J2;q;")[1], "asked of Anna already: not of Bob too")
	local yesterday = date("%Y%m%d", time() - 86400)
	local t = time() - 3 * 3600
	anna("J2;p;" .. carl .. ";Carl-Realmy;4000;ROGUE;18;" .. (t + 600) .. ";6000,12,140,900,7,15,2,4,3,1,250000,800,1,10,95,1800,14400,60,0,17,90000;Hogger;Westfall")
	anna("J2;d;" .. carl .. ";Carl-Realmy;4100;" .. yesterday .. ";120,9000,12,40,2,1,5,18,95,4000,1,0,1,77")
	anna("J2;n;" .. carl .. ";Carl-Realmy;4200;1;" .. t .. ";level;18;Westfall")
	anna("J2;n;" .. carl .. ";Carl-Realmy;4300;2;" .. (t + 60) .. ";death;Hogger;Elwynn Forest")
	anna("J2;n;" .. carl .. ";Carl-Realmy;4400;3;" .. (t + 120) .. ";hack;x;y")
	anna("J2;d;" .. zed .. ";Zed-Realmy;4100;" .. yesterday .. ";1,1,1,1,1,1,1,1,1,1,1,1,1,1")
	Advance(0.3)
	local book = CDB.book
	local c = book[carl] and book[carl].chars["Carl-Realmy"]
	check(c and c.classFile == "ROGUE" and c.level == 18 and c.profile.played == 360000 and c.profile.quests == 140
		and c.foe == "Hogger" and c.zone == "Westfall", "Carl's profile, kept (minutes back to seconds)")
	local cd = c and c.days[date("%Y-%m-%d", time() - 86400)]
	check(cd and cd.played == 7200 and cd.xp == 9000 and cd.level == 18 and cd.gold == 95 and cd.jumps == 77,
		"his day: played, XP, level, gold, jumps ...")
	check(c.news[1] and c.news[1].k == "level" and c.news[2].k == "death" and not c.news[3] and not book[zed],
		"his highlights (unknown kinds dropped); nothing of the stranger's")
	check(book[carl].u == 0 and CH.SyncPending()[carl], "not complete before the end")
	anna("J2;e;" .. carl .. ";5000")
	Advance(0.3)
	check(book[carl].u == 5000 and not CH.SyncPending()[carl], "the end: complete up to her stamp")
	mark = #GAMEDATA + 1
	bob("J2;s;" .. carl .. ",5000")
	Advance(0.3)
	check(not sentTo(12, mark, "J2;q;")[1], "Bob holds the same: nothing to ask")
	bob("J2;s;" .. carl .. ",6000")
	Advance(0.3)
	check(sentTo(12, mark, "J2;q;" .. carl .. ";5000")[1], "Bob holds more: only what's newer is asked for")
	bob("J2;e;" .. carl .. ";6000")
	Advance(0.3)

	-- Passing it on: Bob asks me for Carl's journal.
	mark = #GAMEDATA + 1
	bob("J2;q;" .. carl .. ";0")
	Advance(3)
	check(#sentTo(12, mark, "J2;n;" .. carl) == 2 and sentTo(12, mark, "J2;p;" .. carl)[1] and sentTo(12, mark, "J2;e;" .. carl .. ";6000")[1],
		"what I hold of a friend goes on to another friend who asks")
	mark = #GAMEDATA + 1
	bob("J2;q;" .. carl .. ";4250")
	Advance(3)
	check(#sentTo(12, mark, "J2;n;") == 1 and not sentTo(12, mark, "J2;p;")[1], "only what's newer than they have")
	REGISTERED_SETTINGS.LefthyTools_chronicle_relay:SetValue(false)
	mark = #GAMEDATA + 1
	bob("J2;q;" .. carl .. ";0")
	Advance(3)
	check(not sentTo(12, mark, "J2;n;")[1] and sentTo(12, mark, "J2;e;" .. carl .. ";0")[1], "'pass on' off: nothing of friends' journals")
	REGISTERED_SETTINGS.LefthyTools_chronicle_relay:SetValue(true)

	-- Characters, accounts, news and the feed.
	local carlChar
	for _, c in ipairs(CH.Characters()) do if c.name == "Carl" then carlChar = c end end
	check(carlChar and not carlChar.online and carlChar.account == "Carl" and carlChar.profile
		and CH.Characters()[1].me and CH.Characters()[1].current, "Carl is among the characters (offline), the one I play first")
	-- An account adds up its characters: Carl's alt's numbers join his on his page.
	anna("J2;d;" .. carl .. ";Carlbank-Realmy;4500;" .. yesterday .. ";30,100,1,2,1,0,10,5,20,300,0,0,0,23")
	Advance(0.3)
	local carlAccount
	for _, a in ipairs(CH.Accounts()) do if a.acct == carl then carlAccount = a end end
	local ad = carlAccount and carlAccount.days[date("%Y-%m-%d", time() - 86400)]
	check(carlAccount and #carlAccount.chars == 2 and carlAccount.name == "Carl" and ad.played == 9000 and ad.jumps == 100
		and ad.afk == 900 and ad.level == 18 and ad.gold == 115 and carlAccount.profile.quests == 140,
		"per account: time, AFK and jumps add up over his characters; level from his main, gold summed; named after his BattleTag")
	-- Days of a character his journal doesn't have yet (they go to everyone online): a character of
	-- his account, not a person of its own.
	CDB.friendStats.Carlnew = { classFile = "ROGUE", level = 5, updated = time(), acct = carl,
		days = { [date("%Y-%m-%d", time() - 86400)] = { played = 600, xp = 10, quests = 0, kills = 1, deaths = 0, levels = 0 } } }
	local carls, carlChars, loose = 0, 0, false
	for _, a in ipairs(CH.Accounts()) do
		if a.acct == carl then carls, carlChars = carls + 1, #a.chars end
		loose = loose or a.key == "friend:Carlnew"
	end
	check(carls == 1 and carlChars == 3 and not loose, "days from an older build's message join his account, got "
		.. carls .. " accounts, " .. carlChars .. " characters")
	CDB.friendStats.Carlnew = nil
	local mine = CH.Accounts()[1]
	check(mine.me and #mine.chars >= 2 and mine.name == "You" and mine.chars[1].current, "me: all my characters, the one I play first")
	local function newsOf(name, k)
		for _, f in ipairs(CH.FriendNews()) do if f.name == name and f.k == k then return f end end
	end
	check(newsOf("Carl", "level") and newsOf("Carl", "level").level == 18 and newsOf("Carl", "death").foe == "Hogger",
		"his highlights are in the friends' news")
	-- A live highlight and the same one synced later: once.
	Advance(60)
	anna("E2;boss;Murloc King;Westfall")
	Advance(0.3)
	anna("J2;n;" .. annaAcct .. ";Anna-Realmy;7000;9;" .. time() .. ";boss;Murloc King;Westfall")
	Advance(0.3)
	local kings = 0
	for _, f in ipairs(CH.FriendNews()) do if f.k == "boss" and f.a == "Murloc King" then kings = kings + 1 end end
	check(kings == 1, "a live highlight that a synced one repeats shows once, got " .. kings)
	check(CH.UnseenCount() >= 3, "new from friends, not seen yet: " .. CH.UnseenCount())
	CH.UpdateMinimapButton()
	check(CH.MinimapButton().New:IsShown(), "the book on the minimap gets a blue dot")

	-- The journal: News is what they all did; Friends everyone at a glance (who's online, who isn't,
	-- a table each); Compare has everyone in every graph.
	CH.Open("news")
	local win = LefthyToolsChronicleFrame
	local canvas = win.Canvas
	local function drawn(text)
		for i = 1, canvas.used.text do if (canvas.pools.text[i]:GetText() or ""):find(text, 1, true) then return canvas.pools.text[i] end end
	end
	local function hover(title)
		for i = 1, canvas.used.hover do
			local f = canvas.pools.hover[i]
			if f.lines and f.lines[1] == title then return f end
		end
	end
	local page = win.Text:GetText()
	check(page:find("^|cffffd200What they did|r") and not page:find("Online now", 1, true) and not win.Picker:IsShown(),
		"News: what they did, right at the top, got\n" .. page)
	check(page:find("Died to Hogger", 1, true) and CH.UnseenCount() == 0 and not CH.MinimapButton().New:IsShown()
		and win.Tabs.news.New:GetText() == "", "their news is there; seen now: the dot and the tab's count go")
	-- Anna's journal has a second character of hers; she's online (on Anna).
	anna("J2;d;" .. annaAcct .. ";Annalt-Realmy;7100;" .. yesterday .. ";60,100,1,1,0,0,0,10,5,100,0,0,0,1")
	Advance(0.3)
	CH.Open("friends")
	check(not win.Tabs.friends:IsEnabled() and not win.Picker:IsShown() and win.Text:GetText() == "" and drawn("Online now")
		and drawn("Where") and drawn("Doing") and drawn("Anna Brook|r") and drawn("Not online") and drawn("Last played")
		and drawn("BattleTag") and drawn("Carl|r") and drawn("Died to Hogger"),
		"Friends: a table of who's online (where, doing) and one of who isn't (last played, this week, latest news)")
	local function drawnTimes(text)
		local n = 0
		for i = 1, canvas.used.text do if (canvas.pools.text[i]:GetText() or ""):find(text, 1, true) then n = n + 1 end end
		return n
	end
	local tags = drawnTimes("|cff80c0ffCarl|r") -- (his BattleTag's name is Carl too)
	check(CDB.book[annaAcct].chars["Annalt-Realmy"] and not drawn("Annalt") and drawnTimes("Carl|r") - tags == 1
		and drawnTimes("Carlbank|r") == 1 and tags == 2,
		"a row per character, its BattleTag beside it: Anna is online, so her other character isn't under not online; Carl's two are, his BattleTag on each")
	CDB.book[annaAcct].chars["Annalt-Realmy"] = nil
	local carlRow, annaRow
	for i = 1, canvas.used.hover do
		local f = canvas.pools.hover[i]
		if f.lines and f.lines[1]:find("Carl|r", 1, true) then carlRow = f end
		if f.lines and f.lines[1]:find("Anna Brook|r", 1, true) then annaRow = f end
	end
	check(annaRow and #annaRow.lines >= 3 and annaRow.onClick, "an online friend's row: their full status on hover, a click opens their graphs")
	check(carlRow and table.concat(carlRow.lines, "\n"):find("Level 18", 1, true) and carlRow.lines[#carlRow.lines]:find("Click: their graphs", 1, true)
		and table.concat(carlRow.lines, "\n"):find("All characters: ", 1, true) and table.concat(carlRow.lines, "\n"):find("Carlbank", 1, true),
		"hovering a row: all of it (a long highlight is cut in its cell), all their characters")
	carlRow._scripts.OnMouseUp(carlRow, "LeftButton")
	check(not win.Tabs.graphs:IsEnabled() and win.Picker.Label:GetText():find("Carl", 1, true),
		"a click on a row: their graphs, got " .. tostring(win.Picker.Label:GetText()))
	-- Carl plays two characters: one person, in the dropdown and on his page.
	-- (his journal came from Anna, an older build's: only his first name is known, marked)
	local unsure = " |cff888888?|r"
	check(win.Picker.Label:GetText():find("Carlbank", 1, true) and drawn("You and Carl, last 7 days") and drawn("2h 30m")
		and drawn("Carl|r" .. unsure .. ": Died to Hogger"), "his graphs: both characters added up (2 h + 30 min), his news saying whose")
	do
		win.Picker:Click()
		local carls, annas = 0, 0
		for i = 1, win.Picker.List.count do
			local text = win.Picker.List.rows[i].Text:GetText() or ""
			carls = carls + (text:find("Carl", 1, true) and 1 or 0)
			annas = annas + (text:find("Anna", 1, true) and 1 or 0)
		end
		win.Picker.List:Hide()
		check(carls == 1 and annas == 1, "the dropdown: each friend once (Anna's journal and her days from older messages too), got "
			.. carls .. " Carl, " .. annas .. " Anna")
	end
	CH.Open("compare")
	check(not win.Tabs.compare:IsEnabled() and not win.Picker:IsShown() and drawn("Level") and drawn("Leaderboard, last 14 days")
		and drawn("Quests per day") and drawn("Deaths, adding up") and drawn("Hall of fame, all time") and drawn("Records"),
		"Compare: the level chart, the leaderboard, a graph per number, the hall of fame, records")
	check(drawn("Lefthy (you)") and drawn("Carl") and drawn("Anna"), "a chip per person in the legend")
	local carlDay = hover(date("%Y-%m-%d", time() - 86400))
	check(carlDay and table.concat(carlDay.lines, "|"):find("Carl", 1, true), "hovering a day: everyone's value that day")
	check(drawn("Fastest level: ") and drawn("nemesis: Hogger"), "records: the fastest level, nemeses")
	-- The big chart: any number (icons pick), per day or adding up, symbols on the lines.
	local function hoverWith(first, second)
		for i = 1, canvas.used.hover do
			local f = canvas.pools.hover[i]
			if f.lines and f.lines[1] == first and (not second or f.lines[2] == second) then return f end
		end
	end
	local function icons(path)
		local n = 0
		for i = 1, canvas.used.icon do if canvas.pools.icon[i].path == path then n = n + 1 end end
		return n
	end
	local function click(f) f._scripts.OnMouseUp(f, "LeftButton") end
	local bossIcon = "Interface\\Icons\\INV_Misc_Head_Dragon_01"
	local skull = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
	check(hoverWith("Level", "Shown now") and hoverWith("Jumps", "Click: show this") and drawn("Symbols"),
		"the big chart: level at first, an icon for each thing it can show")
	-- Today Anna died (more than once) and killed a boss, Carl died to Hogger: a skull on each line
	-- (deaths come first), besides the picker's and the switch's.
	check(icons(skull) >= 4 and icons(bossIcon) == 1, "symbols: the day's most notable on each line, got "
		.. icons(skull) .. " skulls, " .. icons(bossIcon) .. " dragons")
	-- A symbol's tooltip: only that person's moments that day; the day's: everyone's value and small icons.
	local annaSymbol, daySpot
	for i = 1, canvas.used.hover do
		local f = canvas.pools.hover[i]
		local text = table.concat(f.lines or {}, "\n")
		if f.raised and text:find("Murloc King", 1, true) then annaSymbol = text end
		if not f.raised and f.lines and f.lines[1] == date("%Y-%m-%d") and not daySpot then daySpot = text end
	end
	local _, annaDeaths = (annaSymbol or ""):gsub("Died", "")
	check(annaSymbol and annaSymbol:find("Anna", 1, true) and annaSymbol:find("Defeated Murloc King", 1, true)
		and not annaSymbol:find("Carl", 1, true) and not annaSymbol:find("Died to Hogger", 1, true) and annaDeaths <= 2,
		"hovering Anna's symbol: only her moments that day (two of a kind), got\n" .. tostring(annaSymbol))
	check(daySpot and daySpot:find("Carl", 1, true) and daySpot:find("Anna", 1, true) and not daySpot:find("Defeated", 1, true)
		and not daySpot:find("Died to", 1, true) and daySpot:find("Hover a symbol for what happened.", 1, true),
		"the day's tooltip: a line each, small icons instead of the moments, got\n" .. tostring(daySpot))
	click(hoverWith("Quests", "Click: show this"))
	check(hoverWith("Quests", "Shown now") and drawn("Quests, adding up") and drawn("|cffffffffAdding up|r"),
		"picking quests: the big chart shows them, adding up")
	click(hoverWith("Per day"))
	check(hoverWith("Quests", "Shown now") and drawn("|cffffffffPer day|r"), "or per day")
	click(hoverWith("Symbols on the lines"))
	check(canvas.used.icon == 12, "symbols off: only the picker's icons and the switch's, got " .. canvas.used.icon)
	click(hoverWith("Symbols on the lines"))
	check(canvas.used.icon > 12, "and on again")
	win.Scroll:SetVerticalScroll(300)
	local small
	for i = 1, canvas.used.hover do
		local f = canvas.pools.hover[i]
		if f.lines and f.lines[#f.lines]:find("show it big at the top", 1, true) then small = f; break end
	end
	click(small)
	check(hoverWith("Time played", "Shown now") and drawn("|cffffffffPer day|r") and win.Scroll:GetVerticalScroll() == 0,
		"a click on a small chart (time played per day): shown big at the top")
	click(hoverWith("Level", "Click: show this"))
	local lines = canvas.used.line
	local chip = hover("Carl" .. unsure)
	check(chip and chip.lines[2] == "|cff888888Surname not known yet: it shows once Carl plays the character while you're online, or with an up-to-date LefthyTools.|r",
		"his chip: his first name marked, its hover says when the surname comes")
	chip._scripts.OnMouseUp(chip, "LeftButton")
	check(canvas.used.line < lines, "a click on a chip hides that person from every graph")
	chip = hover("Carl" .. unsure)
	chip._scripts.OnMouseUp(chip, "LeftButton")
	local range = nil
	for i = 1, canvas.used.text do
		if canvas.pools.text[i]:GetText() == "|cffaaaaaa30 days|r" then range = canvas.pools.text[i] end
	end
	check(range, "range chips")
	mark = #GAMEDATA + 1
	local share = hover("Share")
	share._scripts.OnMouseUp(share, "LeftButton")
	Advance(0.5)
	local shared = sentTo(11, mark, "M2;Chronicle")[1]
	check(shared, "Share: a ranking goes to LTC, got " .. tostring(sentTo(11, mark, "M2;")[1]))
	do -- The leaderboard follows the range picked above, like the charts.
		local counts, board = {}, CH.Leaderboard
		CH.Leaderboard = function(count, ...) counts[#counts + 1] = count; return board(count, ...) end
		local thirty = canvas.pools.hover[3] -- (the toolbar comes first: 7, 14, 30 days)
		thirty._scripts.OnMouseUp(thirty, "LeftButton")
		CH.Leaderboard = board
		check(counts[#counts] == 30 and drawn("Leaderboard, last 30 days") and not drawn("Leaderboard, last 14 days"),
			"the leaderboard follows the range: 30 days picked, 30 days ranked, got " .. tostring(counts[#counts]))
		local leaders
		for i = 1, canvas.used.hover do
			local f = canvas.pools.hover[i]
			if f.lines and f.lines[2] == "Post the leaders in LTC." then leaders = f end
		end
		mark = #GAMEDATA + 1
		leaders._scripts.OnMouseUp(leaders, "LeftButton")
		Advance(0.5)
		check(sentTo(11, mark, "M2;Chronicle, last 30 days: ")[1], "and shared with its range, got " .. tostring(sentTo(11, mark, "M2;")[1]))
		local fourteen = canvas.pools.hover[2]
		fourteen._scripts.OnMouseUp(fourteen, "LeftButton")
		check(drawn("Leaderboard, last 14 days"), "back to 14 days")
	end
	win:Hide()

	-- Logging in later: what friends did meanwhile, in chat.
	lefthy("disable chronicle")
	CDB.lastSeenAt = time() - 6 * 3600
	lefthy("enable chronicle")
	pmark = #PRINTED + 1
	Advance(10)
	bob("E2;boss;Lord Liveone;Westfall") -- (after logging in: seen live, with its chat line)
	Advance(70)
	local said = printedSince(pmark)
	check(said:find("while you were away", 1, true) and said:find("Carl|r" .. unsure .. ": reached level 18", 1, true) and said:find("died once", 1, true),
		"a minute after logging in: what friends did while I was away, got\n" .. said)
	check(said:find("Bob Stone|r defeated Lord Liveone", 1, true) and said:find("Bob Stone|r: reached level 24, reached level 25", 1, true)
		and not said:match("while you were away.*Lord Liveone"),
		"what came live since logging in isn't told again, got\n" .. said)

	-- Once a week: last week's leaderboard.
	local lastWeek = CH.Monday(1)
	me.daily[lastWeek] = me.daily[lastWeek] or { played = 0, xp = 0, quests = 0, kills = 0, deaths = 0, levels = 0, afk = 0 }
	me.daily[lastWeek].played, me.daily[lastWeek].quests = 3600, 12
	anna("J2;d;" .. carl .. ";Carl-Realmy;8000;" .. lastWeek:gsub("-", "") .. ";90,500,30,5,4,0,0,17,50,100,0,0,0,3")
	Advance(0.3)
	CDB.recapWeek = nil
	lefthy("disable chronicle")
	lefthy("enable chronicle")
	pmark = #PRINTED + 1
	Advance(125)
	said = printedSince(pmark)
	check(said:find("last week's leaderboard", 1, true) and said:find("most quests: |c%x+Carl|r |cff888888%?|r %(30%)") and said:find("most deaths", 1, true),
		"the weekly recap: who led last week, got\n" .. said)
	pmark = #PRINTED + 1
	lefthy("disable chronicle")
	lefthy("enable chronicle")
	Advance(125)
	check(not printedSince(pmark):find("leaderboard", 1, true), "once a week")
end

section("Chronicle: one row per character, accounts beside them")
do
	local H = CH.Hash
	local mine, annaAcct, carl = H("Me#1111"), H("Annie#1234"), H("Carl#3456")
	local function bn(id) for _, f in ipairs(BN_FRIENDS) do if f[1].gameAccountID == id then return f[1] end end end
	local function bob(text) Fire("BN_CHAT_MSG_ADDON", "LTBeacon", text, "WHISPER", 12) end
	local win = LefthyToolsChronicleFrame
	local canvas = win.Canvas
	local function drawnTimes(text) -- how many of the page's texts have it
		local n = 0
		for i = 1, canvas.used.text do if (canvas.pools.text[i]:GetText() or ""):find(text, 1, true) then n = n + 1 end end
		return n
	end
	local function named(name, list) -- how many have that name
		local n = 0
		for _, item in ipairs(list) do if item.name == name then n = n + 1 end end
		return n
	end
	local yesterday = date("%Y-%m-%d", time() - 86400)

	-- WoW: Forever names have a surname. Battle.net (and so Beacon, and what an older build sends live)
	-- says "Anna Brook"; her own client's journal knows her by UnitName's first return ("Anna-Realmy").
	anna("H2")
	Advance(1.2)
	check(peers()[11] and peers()[11].name == "Anna Brook", "Beacon knows her by the full name")
	local today = date("%Y%m%d")
	anna("L2;25;")
	anna("J2;n;" .. annaAcct .. ";Anna-Realmy;9000;20;" .. time() .. ";level;25;Elwynn Forest")
	anna("D2;" .. today .. ";50;100;1;1;0;1")
	anna("J2;d;" .. annaAcct .. ";Anna-Realmy;9001;" .. today .. ";50,100,1,1,0,1,0,25,5,100,0,0,0,1")
	Advance(0.3)
	local levels = {}
	for _, f in ipairs(CH.FriendNews()) do
		if f.k == "level" and (f.level == 25 or f.a == "25") and f.name:find("^Anna") then levels[#levels + 1] = f.name end
	end
	check(#levels == 1 and levels[1] == "Anna Brook", "her level-up is in the news once (live and synced), by her full name, got "
		.. table.concat(levels, ", "))
	local annaBook = CDB.book[annaAcct].chars["Anna-Realmy"]
	check(annaBook.full == "Anna Brook" and annaBook.guid == "Player-1-11" and CDB.friendStats["Anna Brook"].acct == annaAcct,
		"her journal learns her full name and GUID from Battle.net; her live days know her account")
	local chars = CH.Characters()
	check(named("Anna Brook", chars) == 1 and named("Anna", chars) == 0, "one Anna among the characters, by her full name")
	local annaChar
	for _, c in ipairs(chars) do if c.name == "Anna Brook" then annaChar = c end end
	check(annaChar.online and annaChar.account == "Annie" and annaChar.days[date("%Y-%m-%d")].played == 3000,
		"online, her BattleTag beside her; today counted once (her journal's day, not also the one sent live)")
	local board = CH.Leaderboard(7, 0)
	check(named("Anna Brook", (function() local l = {} for _, e in ipairs(board.played) do l[#l + 1] = e.person end return l end)()) == 1,
		"the leaderboard: a row per character, Anna once")

	-- An older build's saved data, from before characters were matched: days and news kept by the
	-- full name, without the account (as builds before this one saved them), joined once when Chronicle starts.
	local carlBook, carlbank = CDB.book[carl].chars["Carl-Realmy"], CDB.book[carl].chars["Carlbank-Realmy"]
	carlBook.full, carlbank.full = nil, nil
	local death = carlBook.news[2]
	CDB.friendStats["Carl Vale"] = { classFile = "ROGUE", level = 18, updated = time() - 7200,
		days = { [yesterday] = { played = 7200, xp = 9000, quests = 12, kills = 40, deaths = 2, levels = 1 } } }
	CDB.friendStats["Carlbank Moor"] = { classFile = "ROGUE", level = 5, updated = time() - 7200, -- (not Carlbank: his days differ)
		days = { [yesterday] = { played = 30000, xp = 1, quests = 0, kills = 0, deaths = 0, levels = 0 } } }
	CDB.friendStats["Cedric Vale"] = { classFile = "PRIEST", level = 7, updated = time() - 7200, -- (no journal of his)
		days = { [yesterday] = { played = 600, xp = 1, quests = 0, kills = 0, deaths = 0, levels = 0 } } }
	-- Two friends with a "Bob": a "Bob Stone" without an account could be either, so he's neither.
	local function bobChar() return { name = "Bob", realm = "Realmy", classFile = "WARRIOR", u = 1, news = {},
		days = { [yesterday] = { played = 600, xp = 1, quests = 0, kills = 0, deaths = 0, levels = 0 } } } end
	CDB.book[annaAcct].chars["Bob-Realmy"], CDB.book[carl].chars["Bob-Realmy"] = bobChar(), bobChar()
	CDB.friendStats["Bob Stone"] = { classFile = "WARRIOR", level = 9, updated = time() - 7200,
		days = { [yesterday] = { played = 600, xp = 1, quests = 0, kills = 0, deaths = 0, levels = 0 } } }
	table.insert(CDB.friends, 1, { t = death.t, name = "Carl Vale", classFile = "ROGUE", k = "death", foe = "Hogger", where = "Elwynn Forest" })
	local liveDeath = CDB.friends[1]
	CDB.identity = nil
	lefthy("disable chronicle")
	lefthy("enable chronicle")
	Advance(0.3)
	check(CDB.identity == 1 and CDB.friendStats["Carl Vale"].acct == carl and carlBook.full == "Carl Vale" and liveDeath.acct == carl,
		"once: an older build's days find their character's journal (it learns the full name), the live news too")
	check(not CDB.friendStats["Carlbank Moor"].acct and not carlbank.full and not CDB.friendStats["Cedric Vale"].acct
		and not CDB.friendStats["Bob Stone"].acct and not CDB.book[annaAcct].chars["Bob-Realmy"].full and not CDB.book[carl].chars["Bob-Realmy"].full,
		"never two characters taken for one: days that disagree, no journal of his, two that could be him")
	chars = CH.Characters()
	local carlVale
	for _, c in ipairs(chars) do if c.name == "Carl Vale" then carlVale = c end end
	check(named("Carl Vale", chars) == 1 and named("Carl", chars) == 0 and named("Carlbank", chars) == 1 and named("Carlbank Moor", chars) == 1
		and named("Cedric Vale", chars) == 1 and named("Bob Stone", chars) == 1 and named("Bob", chars) == 2,
		"a row per character: Carl once (by his full name), his alt apart, the others on their own")
	check(carlVale and carlVale.account == "Carl" and carlVale.days[yesterday].played == 7200, "his days counted once, his BattleTag beside him")
	local deaths = 0
	for _, f in ipairs(CH.FriendNews()) do
		if f.k == "death" and f.foe == "Hogger" and f.key == carlVale.key then deaths = deaths + 1 end
	end
	check(deaths == 1, "his death is in the news once (saved live, and in his journal), got " .. deaths)
	local carlAccount
	for _, a in ipairs(CH.Accounts()) do if a.acct == carl then carlAccount = a end end
	check(carlAccount.name == "Carl" and #carlAccount.chars == 3 and carlAccount.days[yesterday].played == 7200 + 1800 + 600,
		"his account: his characters added up once each (Carl, Carlbank, a Bob), got " .. tostring(carlAccount.days[yesterday].played))
	CDB.friendStats["Carlbank Vale"] = { classFile = "ROGUE", level = 5, updated = time(),
		days = { [yesterday] = { played = 1800, xp = 1, quests = 0, kills = 0, deaths = 0, levels = 0 } } }
	lefthy("disable chronicle")
	lefthy("enable chronicle")
	check(not CDB.friendStats["Carlbank Vale"].acct, "the joining runs once")
	CDB.friendStats["Carlbank Vale"], CDB.friendStats["Carlbank Moor"], CDB.friendStats["Cedric Vale"], CDB.friendStats["Bob Stone"] = nil, nil, nil, nil
	CDB.book[annaAcct].chars["Bob-Realmy"], CDB.book[carl].chars["Bob-Realmy"] = nil, nil

	-- Full names on the wire: "a" records (older builds ignore words they don't know), with the
	-- profile's stamp; the key stays the first name's, so older builds see what they always saw.
	anna("H2")
	bob("H2")
	Advance(1.2)
	anna("J2;a;" .. carl .. ";Carlbank-Realmy;9100;Carlbank Vale;Player-1-77")
	anna("J2;a;" .. carl .. ";Carl-Realmy;9200;Bob Stone;") -- (not his name)
	anna("J2;a;" .. carl .. ";Carlbank-Realmy;9050;Carlbank Old;") -- (older)
	Advance(0.3)
	check(carlbank.full == "Carlbank Vale" and carlbank.guid == "Player-1-77" and carlBook.full == "Carl Vale",
		"a journal's full name and GUID from its author; one that names someone else, or is older, is ignored")
	local mark = #GAMEDATA + 1
	bob("J2;q;" .. carl .. ";0")
	Advance(3)
	check(sentTo(12, mark, "J2;a;" .. carl .. ";Carlbank-Realmy;9100;Carlbank Vale;Player-1-77")[1], "passed on with his journal")
	lefthy("disable chronicle")
	MY_SURNAME = "Mirewood"
	lefthy("enable chronicle")
	Advance(0.3)
	check(CH.CurrentKey() == "Lefthy-Realmy" and me.full == "Lefthy Mirewood" and me.guid == "Player-1-0",
		"my character: the full name and GUID kept, the key the first name's (the one friends' builds know)")
	anna("J2;h;" .. annaAcct)
	mark = #GAMEDATA + 1
	anna("J2;q;" .. mine .. ";0")
	Advance(8)
	local alias = sentTo(11, mark, "J2;a;" .. mine .. ";Lefthy-Realmy;")[1] or ""
	check(alias:find(";Lefthy Mirewood;Player%-1%-0$") and sentTo(11, mark, "J2;p;" .. mine .. ";Lefthy-Realmy;")[1]
		and not sentTo(11, mark, "J2;p;" .. mine .. ";Lefthy Mirewood")[1],
		"friends get my full name and GUID in a record of their own; the profile is as older builds know it, got " .. alias)

	-- Another character of mine with the same first name (another GUID): a record of its own.
	lefthy("disable chronicle")
	MY_GUID, MY_SURNAME = "Player-1-500", "Brightwater"
	lefthy("enable chronicle")
	Advance(0.3)
	local other = CDB.chars["Lefthy Brightwater-Realmy"]
	check(CH.CurrentKey() == "Lefthy Brightwater-Realmy" and other and other.name == "Lefthy Brightwater" and me.full == "Lefthy Mirewood",
		"my alt with the same first name isn't taken for me: its own record, by its full name")
	lefthy("disable chronicle")
	MY_GUID, MY_SURNAME = nil, "Mirewood"
	lefthy("enable chronicle")
	Advance(0.3)
	check(CH.CurrentKey() == "Lefthy-Realmy", "and back on mine")
	CDB.chars["Lefthy Brightwater-Realmy"] = nil

	-- Every page: one row per character, by the name the game shows.
	CH.Open("news")
	local page = win.Text:GetText()
	local _, annaLevels = page:gsub("Anna Brook|r: Level 25", "")
	check(annaLevels == 1 and not page:find("Anna|r: Level 25", 1, true) and page:find("Carl Vale|r: Died to Hogger", 1, true),
		"News: one line per event, by the character's full name")
	CH.Open("friends")
	check(drawnTimes("Anna Brook|r") == 1 and drawnTimes("Anna|r") == 0 and drawnTimes("|cff80c0ffAnnie|r") >= 1
		and drawnTimes("Carl Vale|r") == 1 and drawnTimes("Carlbank Vale|r") == 1 and drawnTimes("Carl|r") == drawnTimes("|cff80c0ffCarl|r"),
		"Friends: Anna online once with her BattleTag; not online a row per character, never a character's other name")
	CH.Open("compare")
	check(drawnTimes("Anna Brook") >= 1 and drawnTimes("Anna|r") == 0 and drawnTimes("Lefthy Mirewood (you)") == 1
		and drawnTimes("Alty (you)") == 1 and drawnTimes("Carl|r") == 0,
		"Compare: a chip, a line and a row per character, by character names only")
	local annaChip
	for i = 1, canvas.used.hover do
		local f = canvas.pools.hover[i]
		if f.lines and f.lines[1] == "Anna Brook" then annaChip = f end
	end
	check(annaChip and table.concat(annaChip.lines, "\n"):find("Annie", 1, true), "a chip's hover says whose: the BattleTag")
	win.Tabs.timeline:Click()
	check(win.Text:GetText():find("Lefthy Mirewood|r: ", 1, true), "the timeline says whose by the full name")
	win.Picker:Click()
	local annies, annaNames = 0, 0
	for i = 1, win.Picker.List.count do
		local text = win.Picker.List.rows[i].Text:GetText() or ""
		annies = annies + (text:find("Annie", 1, true) and 1 or 0)
		annaNames = annaNames + select(2, text:gsub("Anna Brook", ""))
	end
	win.Picker.List:Hide()
	check(annies == 1 and annaNames == 1, "the dropdown: accounts, each with its characters, Anna's once")
	win:Hide()

	-- UnitName not saying the surname this time (every character in Forever has one): the one known stays.
	lefthy("disable chronicle")
	MY_SURNAME = nil
	lefthy("enable chronicle")
	check(me.full == "Lefthy Mirewood", "my surname stays when UnitName doesn't say one this time")

	-- (back to how the later tests know me)
	lefthy("disable chronicle")
	me.full = nil
	lefthy("enable chronicle")
	Advance(1.2)
end

section("Chronicle: a surname not known yet says so")
do
	local carl = CH.Hash("Carl#3456")
	local unsure = " |cff888888?|r"
	local hint = "Surname not known yet: it shows once Carl plays the character while you're online, or with an up-to-date LefthyTools."
	local win = LefthyToolsChronicleFrame
	local canvas = win.Canvas
	local function drawn(text)
		for i = 1, canvas.used.text do if (canvas.pools.text[i]:GetText() or ""):find(text, 1, true) then return true end end
	end
	local function hoverOf(first)
		for i = 1, canvas.used.hover do
			local f = canvas.pools.hover[i]
			if f.lines and (f.lines[1] or ""):find(first, 1, true) then return f end
		end
	end
	-- A character of Carl's whose journal came from an older build (it only ever sends the first name)
	-- and that was never online while I was: nothing told its surname.
	local today = date("%Y%m%d")
	anna("H2")
	Advance(1.2)
	anna("J2;p;" .. carl .. ";Corin-Realmy;9400;PALADIN;9;" .. time() .. ";600,1,5,20,1,2,0,0,0,0,1000,10,0,0,1,600,600,0,0,8,3000;;")
	anna("J2;d;" .. carl .. ";Corin-Realmy;9401;" .. today .. ";30,300,5,20,1,1,0,9,1,1000,0,0,0,10")
	anna("J2;n;" .. carl .. ";Corin-Realmy;9402;1;" .. time() .. ";level;9;Westfall")
	Advance(0.3)
	local corin
	for _, c in ipairs(CH.Characters()) do
		if c.key == "book:" .. carl .. ":Corin-Realmy" then corin = c end
	end
	check(corin and corin.name == "Corin" and corin.partial, "only its first name is known: partial")
	check(not CH.Characters()[1].partial and CDB.book[CH.Hash("Annie#1234")].chars["Anna-Realmy"].full == "Anna Brook",
		"the one I play isn't (UnitName); a surname known isn't taken back by a name without (Battle.net's \"Anna\" again)")
	-- Every page: the first name with a muted mark; a hover, or a line under the list, says when the rest comes.
	CH.Open("friends")
	local row = hoverOf("Corin|r")
	check(drawn("Corin|r" .. unsure) and row and row.lines[1]:find("Corin|r" .. unsure, 1, true) and row.lines[2] == "|cff888888" .. hint .. "|r",
		"Friends, not online: Corin marked, the hover says when the surname comes")
	CH.Open("news")
	local page = win.Text:GetText()
	local note = "\n\n|cff888888?|r  |cff888888Surname not known yet: it shows once the character is played while you're online, or with an up-to-date LefthyTools.|r"
	check(page:find("Corin|r" .. unsure .. ": Level 9", 1, true) and page:sub(-#note) == note,
		"News: marked, and a line under the list says what the mark means")
	CH.Open("compare")
	local chip = hoverOf("Corin" .. unsure)
	check(drawn("Corin|r" .. unsure) and chip and chip.lines[2] == "|cff888888" .. hint .. "|r", "Compare: the chip and the charts marked, the chip's hover says when")
	CH.Open("graphs")
	win.Picker:Click()
	local entry
	for i = 1, win.Picker.List.count do
		local text = win.Picker.List.rows[i].Text:GetText() or ""
		if text:find("Corin", 1, true) then entry = text end
	end
	win.Picker.List:Hide()
	check(entry and entry:find("Corin|r" .. unsure .. " |cffcccccc9|r", 1, true), "the dropdown: marked, got " .. tostring(entry))
	-- An alt of mine not played since this build: its full name comes when I log in on it.
	CDB.chars["Oldalt-Realmy"] = { name = "Oldalt", realm = "Realmy", classFile = "WARRIOR", level = 5,
		events = { { t = time(), k = "level", level = 5 } } }
	local mine = "|cff888888?|r  |cff888888Surname not known yet: it shows once you log in on the character.|r"
	win.Tabs.timeline:Click()
	page = win.Text:GetText()
	check(page:find("Oldalt|r" .. unsure .. ": Level 5", 1, true) and page:sub(-#mine) == mine and not page:find("Lefthy|r" .. unsure, 1, true),
		"my timeline: the alt marked, the one I play not, and what the mark means")
	win.Tabs.stats:Click()
	check(win.Text:GetText():find("Oldalt|r" .. unsure, 1, true) and win.Text:GetText():sub(-#mine) == mine, "my statistics: the same")
	CDB.chars["Oldalt-Realmy"] = nil
	CDB.book[carl].chars["Corin-Realmy"] = nil
	win:Hide()
end

section("Chronicle: Battle.net tells a friend's surname, whatever they run")
do
	local carl = CH.Hash("Carl#3456")
	local function profile(key, u, class)
		anna("J2;p;" .. carl .. ";" .. key .. ";" .. u .. ";" .. class .. ";9;" .. time() .. ";600,1,5,20,1,2,0,0,0,0,1000,10,0,0,1,600,600,0,0,8,3000;;")
	end
	anna("H2")
	Advance(1.2)
	profile("Corin-Realmy", 9500, "PALADIN")
	profile("Cora-Realmy", 9501, "PRIEST")
	Advance(0.3)
	local book = CDB.book[carl].chars
	local corin, cora = book["Corin-Realmy"], book["Cora-Realmy"]
	check(corin and cora and not corin.full and not cora.full, "two of Carl's characters from an older build's journal: first names only")
	-- Carl comes online on his second game account, without LefthyTools: Battle.net still says who.
	-- (The walk runs on the tick every 30 s; called here, so the clock stays.)
	local carlFriend
	for _, f in ipairs(BN_FRIENDS) do if f.battleTag == "Carl#3456" then carlFriend = f end end
	local function online(name, class, extra)
		local game = { gameAccountID = 33, isOnline = true, clientProgram = "WoW", wowProjectID = 1, isInCurrentRegion = true,
			characterName = name, classFilename = class, characterLevel = 9, areaName = "Westfall", playerGuid = "Player-1-933",
			isGameAFK = false, isGameBusy = false, realmName = "Realmy", factionName = "Alliance" }
		for k, v in pairs(extra or {}) do game[k] = v end
		carlFriend[2] = game
		CH.Meet()
	end
	online("Corin Vale", "PALADIN")
	local item
	for _, c in ipairs(CH.Characters()) do if c.key == "book:" .. carl .. ":Corin-Realmy" then item = c end end
	check(corin.full == "Corin Vale" and corin.guid == "Player-1-933" and item and item.name == "Corin Vale" and not item.partial,
		"online on it (another game account of his, no LefthyTools): its surname and GUID, the mark gone")
	online("Cora Vale", "PRIEST", { wowProjectID = 2, playerGuid = "Player-1-934" })
	check(not cora.full, "another WoW (another project): nothing")
	online("Cora Vale", "MAGE", { playerGuid = "Player-1-934" })
	check(not cora.full and not cora.guid, "another class: another character with that first name, nothing")
	online("Cora", "PRIEST", { playerGuid = "Player-1-934" })
	check(cora.full == "Cora" and cora.guid == "Player-1-934", "a name Battle.net shows without a surname: that's all of it (not marked)")
	carlFriend[2] = setmetatable({}, { __index = function() error("a secret value") end })
	local ok = pcall(CH.Meet)
	online(SECRET, "PRIEST")
	check(ok and cora.full == "Cora", "what can't be read (a secret) is skipped, nothing breaks")
	carlFriend[2] = nil
	book["Corin-Realmy"], book["Cora-Realmy"] = nil, nil
end

section("Chronicle: friends pass on the surnames they learned")
do
	local H = CH.Hash
	local mine, annaAcct, carl = H("Me#1111"), H("Annie#1234"), H("Carl#3456")
	local function bob(text) Fire("BN_CHAT_MSG_ADDON", "LTBeacon", text, "WHISPER", 12) end
	local function profile(acct, key, u, class)
		anna("J2;p;" .. acct .. ";" .. key .. ";" .. u .. ";" .. class .. ";9;" .. time() .. ";600,1,5,20,1,2,0,0,0,0,1000,10,0,0,1,600,600,0,0,8,3000;;")
	end
	anna("H2")
	bob("H2")
	Advance(1.2)
	profile(carl, "Corin-Realmy", 9600, "PALADIN")
	profile(carl, "Cora-Realmy", 9601, "PRIEST")
	profile(annaAcct, "Annalt-Realmy", 9602, "MAGE")
	Advance(0.3)
	local corin, cora, annalt = CDB.book[carl].chars["Corin-Realmy"], CDB.book[carl].chars["Cora-Realmy"],
		CDB.book[annaAcct].chars["Annalt-Realmy"]
	-- Bob's client saw Corin and Annalt online (Battle.net): it says so, without a stamp of their author's.
	bob("J2;l;" .. carl .. ";Corin-Realmy;Corin Vale;Player-1-933")
	bob("J2;l;" .. carl .. ";Corin-Realmy;Corin Other;")
	bob("J2;l;" .. carl .. ";Cora-Realmy;Bob Stone;")
	bob("J2;l;" .. carl .. ";Cora-Realmy;Cora;")
	bob("J2;l;" .. annaAcct .. ";Annalt-Realmy;Annalt Brook;")
	bob("J2;l;" .. H("Zed#9999") .. ";Zed-Realmy;Zed Moor;")
	Advance(0.3)
	check(corin.full == "Corin Vale" and corin.guid == "Player-1-933" and not corin.aliasU and annalt.full == "Annalt Brook",
		"a surname a friend learned fills in a journal that didn't know it")
	check(not cora.full and not CDB.book[H("Zed#9999")], "one that names someone else, has no surname, or isn't my friend's: nothing")
	-- Passed on with every answer about the account (whatever it asked since), counted with it; a name
	-- from its author goes as its "a" record, not again.
	mark = #GAMEDATA + 1
	bob("J2;q;" .. carl .. ";9999999999")
	Advance(3)
	local count = tonumber((sentTo(12, mark, "J2;c;" .. carl .. ";")[1] or ""):match(";(%d+)$") or -1)
	local about = 0
	for _, m in ipairs(GameDataTo(12, mark)) do
		if m:find("^J2;[pdnal];" .. carl .. ";") then about = about + 1 end
	end
	local carlbank = CDB.book[carl].chars["Carlbank-Realmy"]
	check(sentTo(12, mark, "J2;l;" .. carl .. ";Corin-Realmy;Corin Vale;Player-1-933")[1] and count == about
		and not (carlbank and carlbank.aliasU and sentTo(12, mark, "J2;l;" .. carl .. ";Carlbank-Realmy")[1]),
		"an answer carries the names learned, counted (got " .. count .. " for " .. about .. ")")
	-- To the account's owner when they say hello: Anna's journal learns her alt's name from me.
	mark = #GAMEDATA + 1
	anna("J2;h;" .. annaAcct)
	Advance(3)
	check(sentTo(11, mark, "J2;l;" .. annaAcct .. ";Annalt-Realmy;Annalt Brook;")[1], "Anna says hello: her alt's name goes to her")
	-- Builds before "l" (0.5.0-176) ignore it: they aren't sent it (their answers count without it).
	-- One whose version hasn't come yet gets it, as before (the checks above).
	local annaVersion, bobVersion = peers()[11].version, peers()[12].version
	peers()[12].version = "0.5.0-175-g0000000"
	mark = #GAMEDATA + 1
	bob("J2;q;" .. carl .. ";0")
	Advance(3)
	count = tonumber((sentTo(12, mark, "J2;c;" .. carl .. ";")[1] or ""):match(";(%d+)$") or -1)
	about = 0
	for _, m in ipairs(GameDataTo(12, mark)) do
		if m:find("^J2;[pdnal];" .. carl .. ";") then about = about + 1 end
	end
	check(sentTo(12, mark, "J2;p;" .. carl)[1] and not sentTo(12, mark, "J2;l;")[1] and count == about,
		"an older build's answer: no names learned, counted without them (got " .. count .. " for " .. about .. ")")
	peers()[11].version = "0.5.0-175-g0000000"
	mark = #GAMEDATA + 1
	anna("J2;h;" .. annaAcct)
	Advance(3)
	check(not sentTo(11, mark, "J2;l;")[1], "... nor on its hello")
	peers()[11].version = "0.5.0-176-gba4dbad"
	mark = #GAMEDATA + 1
	anna("J2;h;" .. annaAcct)
	Advance(3)
	check(sentTo(11, mark, "J2;l;" .. annaAcct .. ";Annalt-Realmy;Annalt Brook;")[1], "the build that reads them gets them")
	peers()[11].version, peers()[12].version = annaVersion, bobVersion
	-- And mine: an alt not played since this build learns its surname, and sends it on as its own.
	CDB.chars["Oldalt-Realmy"] = { name = "Oldalt", realm = "Realmy", classFile = "WARRIOR", level = 5, events = {}, daily = {} }
	CH.Fill(CDB.chars["Oldalt-Realmy"])
	local before = CDB.myU
	anna("J2;l;" .. mine .. ";Oldalt-Realmy;Oldalt Mirewood;Player-1-78")
	anna("J2;l;" .. mine .. ";Lefthy-Realmy;Lefthy Otherone;")
	Advance(0.3)
	local oldalt = CDB.chars["Oldalt-Realmy"]
	check(oldalt.full == "Oldalt Mirewood" and oldalt.guid == "Player-1-78" and me.full == "Lefthy",
		"my alt takes the surname a friend saw; the one I play doesn't (UnitName says)")
	mark = #GAMEDATA + 1
	anna("J2;q;" .. mine .. ";" .. before)
	Advance(3)
	check(sentTo(11, mark, "J2;a;" .. mine .. ";Oldalt-Realmy;")[1] and sentTo(11, mark, "J2;a;" .. mine .. ";Oldalt-Realmy;")[1]:find(";Oldalt Mirewood;Player%-1%-78$"),
		"and friends get it from me as my own (\"a\", with its profile's stamp)")
	CDB.chars["Oldalt-Realmy"] = nil
	CDB.book[carl].chars["Corin-Realmy"], CDB.book[carl].chars["Cora-Realmy"], CDB.book[annaAcct].chars["Annalt-Realmy"] = nil, nil, nil
end

section("Chronicle: a death counts once")
do
	-- The game can say PLAYER_DEAD more than once for one death.
	local deaths, since = me.stats.deaths, time()
	local function entries()
		local n = 0
		for _, e in ipairs(me.events) do if e.k == "death" and e.t >= since then n = n + 1 end end
		return n
	end
	STATE.dead = true
	Fire("PLAYER_DEAD")
	Fire("PLAYER_DEAD")
	Advance(3.1)
	Fire("PLAYER_DEAD")
	check(me.stats.deaths == deaths + 1 and entries() == 1, "PLAYER_DEAD again for the same death: counted once")
	STATE.dead = false
	Fire("PLAYER_ALIVE")
	Advance(11)
	STATE.dead = true
	Fire("PLAYER_DEAD")
	check(me.stats.deaths == deaths + 2 and entries() == 2, "alive again, the next death counts")
	STATE.dead = false
	Fire("PLAYER_ALIVE")
	-- Saved twice by builds before (mine, friends'): shown once.
	Advance(30)
	local t = time()
	me.events[#me.events + 1] = { t = t, k = "death", foe = "Twicefoe", zone = "Duskwood" }
	me.events[#me.events + 1] = { t = t + 2, k = "death", foe = "Twicefoe", zone = "Duskwood" }
	local annaAcct = CH.Hash("Annie#1234")
	anna("H2")
	Advance(1.2)
	anna("J2;n;" .. annaAcct .. ";Anna-Realmy;9600;40;" .. t .. ";death;Twinfoe;Westfall")
	anna("J2;n;" .. annaAcct .. ";Anna-Realmy;9601;41;" .. (t + 3) .. ";death;Twinfoe;Westfall")
	anna("J2;n;" .. annaAcct .. ";Anna-Realmy;9602;42;" .. (t + 40) .. ";death;Twinfoe;Westfall") -- (another death)
	Advance(0.3)
	local twins = 0
	for _, f in ipairs(CH.FriendNews()) do if f.foe == "Twinfoe" then twins = twins + 1 end end
	check(twins == 2, "a friend's death saved twice: in the news once (a later one too), got " .. twins)
	CH.Open("timeline")
	local _, mine = LefthyToolsChronicleFrame.Text:GetText():gsub("Died to Twicefoe", "")
	check(mine == 1, "mine: once in the timeline, got " .. mine)
	LefthyToolsChronicleFrame:Hide()
end

section("Chronicle: a broken tick doesn't run every frame")
do
	local C = ns.Chronicle
	local c = C.Store().chars["Lefthy-Realmy"]
	-- Chronicle's own part of the tick fails (a broken record; other files' hooks are guarded, see the
	-- end of this file): it still runs once a second, not every frame.
	local ticks, stats = C.ticks, c.stats
	local played = stats.played
	c.stats = nil
	for _ = 1, 180 do pcall(Advance, 1 / 60) end
	c.stats = stats
	check(C.ticks - ticks <= 4 and c.stats.played == played,
		"an error in the tick: still once a second, got " .. (C.ticks - ticks) .. " ticks")
	-- Levelled while Chronicle was off: the new level's time doesn't count from the old level's start.
	c.level, c.levelStart, c.levelFrom = PLAYER_LEVEL - 1, c.stats.played - 100, { kills = 0, quests = 0 }
	C.Store().friendStats.Gone = { classFile = "MAGE", level = 10, days = { ["2020-01-01"] = { played = 60 } } }
	lefthy("disable chronicle")
	Advance(0.3)
	lefthy("enable chronicle")
	Advance(0.3)
	check(c.level == PLAYER_LEVEL and c.levelStart == nil and c.levelFrom == nil, "a level-up Chronicle missed: that level's start is unknown")
	check(not C.Store().friendStats.Gone, "a friend whose days have all run out leaves the dropdown")
	c.levelStart, c.levelFrom = c.stats.played - 50, { kills = 0, quests = 0 } -- (the level-up window's tests time this level)
	-- A quest hub doesn't use up friends' highlight budget: at most 5 feed-only shares a minute.
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "H2", "WHISPER", 11)
	Advance(1.2)
	local savedQuests = QUESTS
	QUESTS = {}
	for i = 1, 8 do QUESTS[i] = { id = 7000 + i, title = "Hub quest " .. i, objectives = {} } end
	local mark = #GAMEDATA + 1
	for i = 1, 8 do Fire("QUEST_TURNED_IN", 7000 + i, 100) end
	INSTANCE = { name = "The Deadmines", type = "party" }
	Fire("ENCOUNTER_END", 3, "Mr. Smite", 1, 5, 1)
	INSTANCE = nil
	Advance(1.5)
	local questShares, bossShared = 0, false
	for _, m in ipairs(GameDataTo(11, mark)) do
		if m:find("^E2;quest;") then questShares = questShares + 1 end
		if m:find("^E2;boss;Mr. Smite") then bossShared = true end
	end
	check(questShares == 5 and bossShared, "8 quests in a minute: 5 go to friends' feeds, the boss after them still goes, got " .. questShares)
	QUESTS = savedQuests
	-- Days by the calendar (stepping 86400 s skips or repeats one around a daylight saving change).
	local days, ok = {}, true
	for i = 0, 13 do days[i] = date("%Y-%m-%d", C.DayAgo(i)) end
	for i = 1, 13 do
		local t = date("*t", C.DayAgo(i - 1))
		ok = ok and days[i] == date("%Y-%m-%d", time({ year = t.year, month = t.month, day = t.day - 1, hour = 12 }))
	end
	check(ok and days[0] == date("%Y-%m-%d"), "14 days back, each the calendar day before the next")
	-- A friend's day from the future (a wrong clock) isn't kept: it would never be pruned.
	anna("D2;20990101;10;100;1;1;0;0")
	anna("D2;" .. date("%Y%m%d") .. ";11;100;1;1;0;0")
	Advance(1.5)
	local annaStats = C.Store().friendStats["Anna Brook"]
	check(annaStats and annaStats.days[date("%Y-%m-%d")] and not annaStats.days["2099-01-01"],
		"a friend's day after tomorrow is ignored (today's is kept)")
	-- A session past midnight: the new day counts as a day played.
	local today = date("%Y-%m-%d")
	c.days[today], c.daily[today] = nil, nil
	Advance(1.1)
	check(c.days[today] == true, "a day the session runs into counts as played")
	-- A /reload mid-flight isn't another flight.
	local flights = c.stats.flights
	TRAVEL.taxi = true
	Advance(1.1)
	check(c.stats.flights == flights + 1, "taking off counts a flight")
	lefthy("disable chronicle")
	Advance(0.3)
	lefthy("enable chronicle")
	Advance(2.2)
	check(c.stats.flights == flights + 1, "a /reload in the air doesn't count another")
	TRAVEL.taxi = false
	Advance(1.1)
end

section("Chronicle: spring cleaning")
do -- (clock-neutral: no Advance)
	local carl = CH.Hash("Carl#3456")
	local carlBook = CDB.book[carl].chars["Carl-Realmy"]
	-- While you were away: a profession learned has no skill level, only its milestones have.
	anna("J2;n;" .. carl .. ";Carl-Realmy;9700;50;" .. time() .. ";profession;Herbalism;")
	anna("J2;n;" .. carl .. ";Carl-Realmy;9701;51;" .. time() .. ";profession;Mining;150")
	local line
	for _, l in ipairs(CH.CatchUpLines(time() - 1)) do if l:find("Herbalism", 1, true) then line = l end end
	check(line and line:find("learned Herbalism", 1, true) and line:find("reached Mining 150", 1, true)
		and not line:find("reached Herbalism", 1, true), "the catch-up: a profession learned, and one's milestone, got " .. tostring(line))
	carlBook.news[50], carlBook.news[51] = nil, nil
	-- A friend's journal can't name a character with escape codes, or bring numbers nobody has (a
	-- broken or hostile client): the pages would draw them, and pass them on.
	local function fromAnna(word, more) ns.Beacon.ReceiveJournal(11, word, more) end -- (past Beacon's spam guard)
	local numbers = "600,1,5,20,1,2,0,0,0,0,1000,10,0,0,1,600,600,0,0,8,3000"
	local today = date("%Y%m%d")
	fromAnna("p", carl .. ";|Tx:300|t-Realmy;9710;ROGUE;9;" .. time() .. ";" .. numbers .. ";;")
	fromAnna("p", carl .. ";Carlhuge-Realmy;9711;ROGUE;9;" .. time() .. ";" .. numbers:gsub("^600", "99999999999999999999") .. ";;")
	fromAnna("p", carl .. ";Carlold-Realmy;9712;ROGUE;99999;" .. time() .. ";" .. numbers .. ";;")
	fromAnna("d", carl .. ";Carlday-Realmy;9713;" .. today .. ";1500,300,5,20,1,1,0,9,1,1000,0,0,0,10")
	fromAnna("p", carl .. ";Carlfine-Realmy;9714;ROGUE;9;" .. time() .. ";" .. numbers .. ";;")
	fromAnna("d", carl .. ";Carlfine-Realmy;9715;" .. today .. ";1440,300,5,20,1,1,1440,9,1,1000,0,0,0,10")
	local chars = CDB.book[carl].chars
	check(not chars["|Tx:300|t-Realmy"] and not chars["Carlhuge-Realmy"] and not chars["Carlday-Realmy"]
		and not (chars["Carlold-Realmy"] and chars["Carlold-Realmy"].level),
		"a friend's journal: no escape codes in a name, no numbers of 20 digits, no 25 hours in a day, no level 99999")
	check(chars["Carlfine-Realmy"] and chars["Carlfine-Realmy"].profile and chars["Carlfine-Realmy"].days[date("%Y-%m-%d")],
		"what a real client sends is kept (a whole day played, a whole day AFK)")
	chars["Carlfine-Realmy"], chars["Carlold-Realmy"] = nil, nil
	-- My clock was weeks ahead once: friends drop every record of mine stamped after it, and every new
	-- stamp went on from it. Switched on again, everything of mine is stamped anew from now.
	CDB.myU = time() + 30 * 86400
	lefthy("disable chronicle")
	lefthy("enable chronicle")
	local latest, week = 0, time() + 7 * 86400
	for _, c in pairs(CDB.chars) do
		latest = math.max(latest, c.sync.profileU or 0)
		for _, u in pairs(c.sync.dayU) do latest = math.max(latest, u) end
		for _, e in ipairs(c.events) do latest = math.max(latest, e.u or 0) end
	end
	check(CDB.myU <= week and latest <= week and latest > 0,
		"my stamps from a clock weeks ahead: all anew from now, got " .. tostring(CDB.myU - time()) .. " s ahead")
	-- A character keyed by its full name (another of the account's has its first name) whose "a" record
	-- was lost on the way (an older build passed the journal on): the key says its surname.
	fromAnna("d", carl .. ";Carl Moor-Realmy;9720;" .. today .. ";30,300,5,20,1,1,0,9,1,1000,0,0,0,10")
	fromAnna("l", carl .. ";Carl Moor-Realmy;Carl Other;")
	local moor
	for _, c in ipairs(CH.Characters()) do if c.key == "book:" .. carl .. ":Carl Moor-Realmy" then moor = c end end
	check(moor and moor.name == "Carl Moor" and not moor.partial, "a character keyed by its full name isn't marked: the key says the surname")
	check(not chars["Carl Moor-Realmy"].full, "... and no other name learned replaces it")
	chars["Carl Moor-Realmy"] = nil
end

section("Chronicle: a hook that fails doesn't stop the tick")
do
	local C = ns.Chronicle
	local sync, share, onTick = C.SyncTick, C.ShareHighlights, C.OnTick
	local syncCalls, shares, redraws, feedSeen = 0, 0, 0, {}
	C.SyncTick = function() syncCalls = syncCalls + 1; error("a broken sync") end
	C.ShareHighlights = function(now) shares = shares + 1; return share(now) end -- (after Sync.lua's)
	C.OnTick = function(_, _, _, feedChanged) -- the window: fails the first time only
		redraws = redraws + 1
		feedSeen[redraws] = feedChanged
		if redraws == 1 then error("a broken redraw") end
	end
	local reported, stop = catchErrors()
	local ticks = C.ticks
	C.feedDirty = true
	Advance(5.5)
	stop()
	C.SyncTick, C.ShareHighlights, C.OnTick = sync, share, onTick
	local n = C.ticks - ticks
	check(n >= 5 and shares == n, "Sync.lua's hook fails on every tick: the rest of the tick runs, got " .. shares .. " of " .. n)
	check(syncCalls <= 3, "... and the failing hook rests, got " .. syncCalls .. " calls in " .. n .. " ticks")
	check(redraws >= 2 and feedSeen[1] and feedSeen[2], "a redraw that failed: its page stays marked for the next one")
	check(#reported == 2 and reported[1]:find("a broken sync", 1, true) and reported[2]:find("a broken redraw", 1, true),
		"each error reported once")
end

section("Chronicle: what friends' journals and the feed keep")
do
	local C = ns.Chronicle
	local dora, carl = C.Hash("Dora#4567"), C.Hash("Carl#3456")
	anna("H2")
	Advance(1.2)
	local function fromAnna(word, more) ns.Beacon.ReceiveJournal(11, word, more) end -- (past Beacon's spam guard)
	local function day(back) return date("%Y%m%d", C.DayAgo(back)) end
	local numbers = "30,300,5,20,1,1,0,9,1,1000,0,0,0,10"
	-- A friend's account keeps its 30 most recently played characters (a broken or hostile client
	-- can't fill the saved data with characters).
	for i = 1, 30 do
		fromAnna("d", dora .. ";Dora" .. i .. "-Realmy;" .. (9800 + i) .. ";" .. day(i - 1) .. ";" .. numbers)
	end
	local chars = CDB.book[dora].chars
	check(C.Count(chars) == 30, "30 characters of an account are kept, got " .. C.Count(chars))
	fromAnna("d", dora .. ";Doranew-Realmy;9831;" .. day(2) .. ";" .. numbers)
	check(C.Count(chars) == 30 and chars["Doranew-Realmy"] and not chars["Dora30-Realmy"] and chars["Dora29-Realmy"],
		"a 31st: the least recently played goes")
	fromAnna("d", dora .. ";Doraold-Realmy;9832;" .. day(29) .. ";" .. numbers)
	check(C.Count(chars) == 30 and not chars["Doraold-Realmy"] and chars["Dora29-Realmy"],
		"one played longer ago than all of them isn't kept")
	fromAnna("d", dora .. ";Dora1-Realmy;9833;" .. day(1) .. ";" .. numbers)
	check(C.Count(chars) == 30 and chars["Dora1-Realmy"].days[date("%Y-%m-%d", C.DayAgo(1))], "a character it has: just its record")
	-- Saved before there was a cap: cut down on start, the least recently played first, nothing else lost.
	for i = 1, 5 do
		chars["Doraextra" .. i .. "-Realmy"] = { name = "Doraextra" .. i, realm = "Realmy", last = time() - 40 * 86400, days = {}, news = {},
			profile = { played = 60 } }
	end
	chars["Dorafresh-Realmy"] = { name = "Dorafresh", realm = "Realmy", last = time() - 60, days = {}, news = {}, profile = { played = 60 } }
	local carls = C.Count(CDB.book[carl].chars)
	local today = chars["Dora1-Realmy"].days[date("%Y-%m-%d")]

	-- The feed: each kind of news keeps a share of its own (300 in all), so a busy quest day can't
	-- push out a boss kill. A feed saved as one list of 300 before: cut down to the shares on start.
	local savedFeed = {}
	for i, f in ipairs(CDB.friends) do savedFeed[i] = f end
	wipe(CDB.friends)
	local t0 = time() - 1000
	local function entry(k, a) CDB.friends[#CDB.friends + 1] = { t = t0 + #CDB.friends, name = "Anna Brook", classFile = "MAGE", k = k, a = a } end
	entry("boss", "Old Boss")
	for i = 1, 120 do entry("quest", "Quest " .. i) end
	for i = 1, 70 do entry(i % 2 == 0 and "online" or "offline") end
	for i = 1, 50 do entry("zone", "Zone " .. i) end
	for i = 1, 40 do CDB.friends[#CDB.friends + 1] = { t = t0 + #CDB.friends, name = "Anna Brook", classFile = "MAGE", k = "level", level = i } end
	for i = 1, 35 do CDB.friends[#CDB.friends + 1] = { t = t0 + #CDB.friends, name = "Anna Brook", classFile = "MAGE", k = "death", foe = "Foe " .. i } end
	for i = 1, 10 do entry("rare", "Rare " .. i) end
	local function kinds()
		local n = {}
		for _, f in ipairs(CDB.friends) do
			local group = (f.k == "online" or f.k == "offline") and "comings" or (f.k == "rare" or f.k == "boss") and "highlight" or f.k
			n[group] = (n[group] or 0) + 1
		end
		return n
	end
	local function has(k, a)
		for _, f in ipairs(CDB.friends) do if f.k == k and f.a == a then return true end end
		return false
	end
	lefthy("disable chronicle")
	lefthy("enable chronicle")
	check(C.Count(chars) == 30 and chars["Dorafresh-Realmy"] and not chars["Dora29-Realmy"] and not chars["Doraextra1-Realmy"]
		and not chars["Doraextra5-Realmy"] and chars["Doranew-Realmy"] and chars["Dora1-Realmy"].days[date("%Y-%m-%d")] == today
		and C.Count(CDB.book[carl].chars) == carls,
		"saved before the cap: the least recently played go on start, the rest (and other accounts) stay as they were")
	local n = kinds()
	check(n.quest == 80 and n.comings == 50 and n.zone == 40 and n.level == 30 and n.death == 30 and n.highlight == 11 and #CDB.friends == 241,
		"a feed saved before: each kind down to its share, got quests " .. tostring(n.quest) .. ", comings " .. tostring(n.comings)
		.. ", zones " .. tostring(n.zone) .. ", levels " .. tostring(n.level) .. ", deaths " .. tostring(n.death) .. ", highlights "
		.. tostring(n.highlight) .. ", all " .. #CDB.friends)
	check(has("boss", "Old Boss") and not has("quest", "Quest 40") and has("quest", "Quest 41") and has("quest", "Quest 120"),
		"the oldest of each kind went; the boss kill older than every quest stayed")
	local peer = peers()[11]
	ns.Beacon.Notify("highlight", peer, { kind = "quest", a = "Quest 121", b = "" })
	ns.Beacon.Notify("highlight", peer, { kind = "boss", a = "New Boss", b = "" })
	n = kinds()
	check(n.quest == 80 and has("quest", "Quest 121") and not has("quest", "Quest 41") and n.highlight == 12 and has("boss", "Old Boss")
		and #CDB.friends == 242, "a new quest pushes out the oldest quest, not a boss; a new boss joins the highlights")
	wipe(CDB.friends)
	for i, f in ipairs(savedFeed) do CDB.friends[i] = f end
	CDB.book[dora] = nil
	C.NewsChanged()
end

section("Chronicle: old-style days only for builds that read nothing else")
do
	-- My days reach builds from 0.5.0-80 on with my journal; the old day messages go to builds before
	-- it, and to a friend whose build isn't known yet (or doesn't say its commit count), as before.
	anna("H2")
	Advance(1.2)
	local peer = peers()[11]
	local versionWas = peer.version
	local function daysFor(version)
		peer.version = version
		local from = #GAMEDATA + 1
		ns.Beacon.Notify("known", peer, { id = 11 }) -- (as when her name becomes known)
		Advance(2)
		return #sentTo(11, from, "D2;") + #sentTo(11, from, "K2;")
	end
	check(daysFor("0.5.0-80-g94d1d36") == 0 and daysFor("0.5.0-176-gba4dbad-dirty") == 0 and daysFor("0.6.0") == 0,
		"a friend whose build syncs journals gets no old day messages")
	check(daysFor("0.5.0-79-gaaaaaaa") >= 1 and daysFor("0.4.0") >= 1, "builds before it get them")
	check(daysFor(nil) >= 1 and daysFor("0.5.0-g1a2b3c4") >= 1,
		"as before, so does one whose build isn't known yet, or doesn't say its commit count")
	peer.version = versionWas
end

section("Chronicle: days in German")
do -- (clock-neutral: no Advance)
	local C = ns.Chronicle
	-- German writes a day as "T" (Tage): "4T 4h". Hours and minutes stay; chat lines stay English.
	local de = {} -- (the German entries, read from Locales/deDE.lua as a German client would)
	for _, file in ipairs(SOURCES) do
		if file.name == "Locales/deDE.lua" then load(file.src)("LefthyTools", { LOCALE = "deDE", L = de }) end
	end
	local long = 4 * 86400 + 4 * 3600 + 120
	check(C.Duration(long) == "4d 4h" and C.Duration(5400) == "1h 30m", "English: 4d 4h, 1h 30m")
	ns.L["%dd %dh"] = de["%dd %dh"]
	check(C.Duration(long) == "4T 4h" and C.Duration(5400) == "1h 30m" and C.Duration(150) == "2m",
		"German: 4T 4h, hours and minutes as they are, got " .. C.Duration(long))
	check(C.Duration(long, true) == "4d 4h" and C.ChatValue("played", long) == "4d 4h" and C.ChatValue("afk", long) == "4d 4h",
		"chat lines (the recap, Share in LTC, /chronicle session) stay English: 4d 4h")
	ns.L["%dd %dh"] = nil
end

section("Chronicle: tooltips")
do
	local C = ns.Chronicle
	local carl = C.Hash("Carl#3456")
	local win = LefthyToolsChronicleFrame
	local canvas = win.Canvas
	local function rowOf(name)
		for i = 1, canvas.used.hover do
			local f = canvas.pools.hover[i]
			if f.lines and (f.lines[1] or ""):find(name, 1, true) then return f end
		end
	end
	local function hover(f) -- shows its tooltip; whether every line was asked to wrap
		local wrapped, addLine = true, GameTooltip.AddLine
		GameTooltip.AddLine = function(self, text, r, g, b, wrap)
			wrapped = wrapped and wrap == true
			return addLine(self, text, r, g, b, wrap)
		end
		f._scripts.OnEnter(f)
		GameTooltip.AddLine = addLine
		return wrapped
	end
	local function lineAt(prefix)
		for i, line in ipairs(TOOLTIP.lines) do if line:sub(1, #prefix) == prefix then return i, line end end
	end
	-- A long line wraps instead of making the tooltip as wide as it is; a friend's characters: a few on
	-- one line, more one per line (at most 10, the most played first).
	CH.Open("friends")
	local row = rowOf("Carl Vale|r")
	local wrapped = row and hover(row)
	local _, all = lineAt("All characters: ")
	check(wrapped and all and all:find("Carlbank Vale", 1, true) and TOOLTIP.title == row.lines[1],
		"a few of a friend's characters on one line; every line may wrap, got " .. tostring(all))
	row._scripts.OnLeave(row)
	local book = CDB.book[carl].chars
	for i = 1, 12 do
		book["Carlalt" .. i .. "-Realmy"] = { name = "Carlalt" .. i, realm = "Realmy", classFile = "ROGUE", level = i, news = {},
			days = { [date("%Y-%m-%d")] = { played = 60 * i } } }
	end
	CH.Open("friends")
	row = rowOf("Carl Vale|r")
	hover(row)
	local at = lineAt("All characters:")
	local listed = 0
	for i = at and at + 1 or 1, at and #TOOLTIP.lines or 0 do
		if TOOLTIP.lines[i]:find("^   |c%x+Carl") then listed = listed + 1 end
	end
	check(at and TOOLTIP.lines[at] == "All characters:" and listed == 10 and TOOLTIP.lines[at + 1]:find("Carl Vale|r 18", 1, true)
		and TOOLTIP.lines[at + 3]:find("Carlalt12|r", 1, true) and TOOLTIP.lines[at + 10]:find("Carlalt5|r", 1, true)
		and TOOLTIP.lines[at + 11] == "   |cff888888... and 4 more|r",
		"many: one per line, the most played first, at most 10 (and how many more), got " .. listed)
	row._scripts.OnLeave(row)
	for i = 1, 12 do book["Carlalt" .. i .. "-Realmy"] = nil end

	-- The Friends page redraws every 5 s. The row under a resting mouse isn't hidden for it (that
	-- closed its tooltip, and the game opens it again only when the mouse moves): its tooltip stays,
	-- filled anew.
	anna("S2;;0;260.0;750.0;Goldshire;") -- (she stays online: the rows don't move)
	CH.Open("friends")
	row = rowOf("Carl Vale|r")
	row._mouse = true
	row._scripts.OnEnter(row)
	local hide, hidden = row.Hide, false
	row.Hide = function(self) hidden = true; return hide(self) end
	local draws, drawTables = 0, C.Graphs.DrawTables
	C.Graphs.DrawTables = function(...) draws = draws + 1; return drawTables(...) end
	book["Carl-Realmy"].level = 19 -- (to see the tooltip filled anew)
	Advance(6.5)
	check(draws >= 1 and not hidden and TOOLTIP.shown and TOOLTIP.owner == row and TOOLTIP.title:find("Carl Vale|r", 1, true)
		and tooltipHas("Level 19 - Realmy"), "a redraw under the mouse: the row's tooltip stays open, with its new lines")
	row._mouse = false
	row._scripts.OnLeave(row)
	draws = 0
	Advance(6.5)
	check(draws >= 1 and hidden and not TOOLTIP.shown, "the mouse gone: redrawn as usual, no tooltip")
	row.Hide, C.Graphs.DrawTables = nil, drawTables
	book["Carl-Realmy"].level = 18
	win:Hide()
	-- The rows moved (fewer areas this time): the area that had the tooltip goes, and the one under
	-- the mouse now shows its own; nothing under the mouse: the tooltip closes.
	local scratch = C.Graphs.NewCanvas(CreateFrame("Frame"))
	scratch:Reset(true)
	local first = scratch:Hover(0, 0, 10, 10, { "One", "first" })
	local second = scratch:Hover(0, 10, 10, 10, { "Two", "second" })
	scratch:Done()
	second._mouse = true
	second._scripts.OnEnter(second)
	scratch:Reset(true)
	check(scratch:Hover(0, 0, 10, 10, { "Three", "third" }) == first and second:IsShown(), "(the next draw reuses the first area)")
	first._mouse = true
	scratch:Done()
	check(not second:IsShown() and TOOLTIP.shown and TOOLTIP.owner == first and TOOLTIP.title == "Three",
		"the rows moved: the tooltip shows the area under the mouse now")
	first._mouse = false
	scratch:Reset(true)
	scratch:Hover(0, 0, 10, 10, { "Four" })
	scratch:Done()
	check(not TOOLTIP.shown, "nothing under the mouse any more: the tooltip closes")
end
