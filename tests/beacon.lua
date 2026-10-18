-- Beacon: friends on the maps, sharing, updates, alerts, pings, quests, level-ups, items, LTC, error
-- reports, switching it off, and its tick calling the other files' hooks. (The fight stream: stream.lua.)
-- Needs: no other file: Anna, Bob and Finn (the mock's Battle.net friends) are online at login.
local suite = ...
local check, section, ns, LT, lefthy = suite.check, suite.section, suite.ns, suite.LT, suite.lefthy
local printedSince, sentTo, anna, peers = suite.printedSince, suite.sentTo, suite.anna, suite.peers
local pinOf, tooltipHas, afk, catchErrors = suite.pinOf, suite.tooltipHas, suite.afk, suite.catchErrors

section("Beacon: setup")
local Beacon = LT:GetModule("beacon")
local BB = ns.Beacon
local BDB = LefthyToolsDB.settings.beacon
local function B(id) return REGISTERED_SETTINGS["LefthyTools_beacon_" .. id] end
local function last(list) return list[#list] end
check(Beacon and Beacon.enabled, "beacon module registered and enabled at login")
check(Beacon.category and Beacon.category.parent == LT.category and Beacon.category.name == "Beacon",
	"Beacon has its own sub-page under LefthyTools")
local allSettings = true
for _, id in ipairs({ "share", "interval", "showFriends", "showMinimap", "minimapEdge", "dingAnnounce", "dingText", "dingShow", "dingSound" }) do
	allSettings = allSettings and B(id) ~= nil
end
check(allSettings and REGISTERED_SETTINGS.LefthyTools_module_beacon, "settings and module switch")
check(BDB.interval == 3 and BDB.share and BDB.showFriends and BDB.showMinimap and BDB.minimapEdge
	and BDB.dingAnnounce and BDB.dingText == "" and BDB.dingShow and BDB.dingSound, "defaults: everything on, default ding text")
local textInput = TEXT_INPUTS.LefthyTools_beacon_dingText
check(textInput and textInput.template == "LefthyToolsSettingsTextTemplate" and textInput.data.options.maxLetters == 100,
	"level-up message is a text field in the settings panel")
check(SETTINGS_BUTTONS["Test your message"] and SETTINGS_BUTTONS["Test your message"].text == "Preview", "preview button")
check(ADDON_PREFIXES.LTBeacon, "addon message prefix registered")
check(next(WorldMapFrame.providers) ~= nil, "data provider attached to the world map")
do -- Free text cut to a size: no letter split, and none dropped that fits whole ("\195\164" is a two-byte letter).
	local cut = BB.Clean("ab\195\164c", 4)
	check(cut == "ab\195\164" and BB.Clean("abc\195\164", 4) == "abc" and BB.Clean("ab\226\130\172", 4) == "ab"
		and BB.Clean("|cffff0000a;b|r", 10) == "ab", "free text cut at a byte limit keeps whole letters only, got " .. cut)
end

section("Beacon: finding friends with the addon")
local greeted = {}
for _, m in ipairs(GAMEDATA) do if m.data == "H2" then greeted[m.id] = true end end
check(greeted[11] and greeted[12] and greeted[16], "online WoW friends get a hello")
check(not greeted[13] and not greeted[14] and not greeted[15], "offline, non-WoW and other-region friends don't")
local mark = #GAMEDATA + 1
Advance(30)
local onlyHellos = true
for _, m in ipairs(GameDataTo(11, mark)) do if m ~= "H2" then onlyHellos = false end end
check(onlyHellos, "friends without the addon get nothing but an occasional hello")
mark = #GAMEDATA + 1
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;250.0;750.0;Goldshire;", "WHISPER", 11) -- Anna answers
check(#GameDataTo(11, mark) == 0, "no sending inside the event handler")
Advance(0.15)
check(sentTo(11, mark, "S2;")[1] == "S2;;0;500.0;500.0;Goldshire;",
	"Anna answered: my state goes out right away, got " .. tostring(sentTo(11, mark, "S2;")[1]))
check(sentTo(11, mark, "V2;")[1] == "V2;0.4.0-3-gabc1234", "... together with my LefthyTools version")
Advance(1) -- the Battle.net lookup is coalesced to once a second
check(peers()[11] and peers()[11].name == "Anna" and peers()[11].classFile == "MAGE", "her name and class come from Battle.net")
mark = #GAMEDATA + 1
Advance(15)
check(#GameDataTo(11, mark) == 0, "standing still: nothing is sent")
Advance(9) -- checks run every 3 s, so the heartbeat lands 20-23 s after the last send
check(#GameDataTo(11, mark) == 1, "except a heartbeat every 20 s, got " .. #GameDataTo(11, mark))
mark = #GAMEDATA + 1
PLAYER_POS = { 0.51, 0.5 }
Advance(3.2)
check(#GameDataTo(11, mark) == 1 and GameDataTo(11, mark)[1] == "S2;;0;500.0;490.0;Goldshire;",
	"moving: the new position within the interval, got " .. tostring(GameDataTo(11, mark)[1]))
PLAYER_POS = { 0.52, 0.5 }
Advance(3.2)
check(#GameDataTo(11, mark) == 2, "and again every 3 s while moving")
mark = #GAMEDATA + 1
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "H2", "WHISPER", 12) -- Bob starts the addon and says hello
Advance(0.15)
check(#sentTo(12, mark, "S2;") == 1 and #sentTo(12, mark, "V2;") == 1, "a hello is answered with my state and version")
Fire("BN_CHAT_MSG_ADDON", "OtherAddon", "S2;;0;1;1;;", "WHISPER", 14)
for _, bad in ipairs({ "garbage", "S2;bad", "S2;;0;abc;1;;", "S2;;0;1;;;", "S2;x;0;1;1;;", "H2extra" }) do
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", bad, "WHISPER", 14)
end
Advance(0.15)
check(not peers()[14], "other prefixes and malformed messages are ignored")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "H1", "WHISPER", 16) -- Finn runs the old Beacon
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "P1:0:500.0:500.0", "WHISPER", 16)
Advance(0.15)
check(not peers()[16], "a friend on another LefthyTools version isn't treated as a peer")
local pmark = #PRINTED + 1
lefthy("beacon status")
local status = printedSince(pmark)
check(status:find("Finn runs another LefthyTools version", 1, true) ~= nil, "... and /lefthy beacon status says why")
check(status:find("traffic:", 1, true) ~= nil and status:find("2 friend(s)", 1, true) ~= nil, "status: friends and message traffic")
Advance(1.1) -- a fresh one-second window
for i = 1, 30 do -- a client gone haywire
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;900.0;400.0;Zone" .. i .. ";", "WHISPER", 12)
end
check(peers()[12].subzone == "Zone20", "flood guard: at most 20 messages a second from one friend")

section("Beacon: friends on the world map")
PLAYER_POS = { 0.5, 0.5 } -- me: north 500, west 500
Advance(0.6)
check(#PinsOf("LefthyToolsBeaconPinTemplate") == 0, "map closed: nothing drawn")
OpenWorldMap(1429)
local annaPin = pinOf(11)
check(#PINS == 2 and annaPin and pinOf(12), "map open: Anna's and Bob's dots")
check(math.abs(annaPin.x - 0.25) < 1e-6 and math.abs(annaPin.y - 0.75) < 1e-6, "at her position on the zone map")
local c = annaPin.Dot.color
check(c and math.abs(c[1] - 0.25) < 1e-6 and math.abs(c[3] - 0.92) < 1e-6, "in mage blue")
check(annaPin.frameLevelType == "PIN_FRAME_LEVEL_VEHICLE_ABOVE_GROUP_MEMBER", "drawn just above Blizzard's group member dots")
STATE.combat = true
OpenWorldMap(1414); OpenWorldMap(1429) -- dots are released and acquired again, in combat
check(#PINS == 2 and #BLOCKED == 0, "opening the map in combat creates dots without blocked actions, got " .. table.concat(BLOCKED, ", "))
STATE.combat = false
annaPin = pinOf(11)
check(annaPin.Ring.color[1] == 0 and not annaPin.Skull.shown and not annaPin.Pulse:IsPlaying(), "normal look: dark ring, no skull")
annaPin:OnMouseEnter()
check(TOOLTIP.title == "Anna" and TOOLTIP.shown, "tooltip: name")
check(TOOLTIP.lines[1] == "Annie" and tooltipHas("Level 20") and tooltipHas("Elwynn Forest - Goldshire"),
	"tooltip: BattleTag, level, zone and subzone; got " .. table.concat(TOOLTIP.lines, " | "))
check(tooltipHas("355 yd south-west"), "tooltip: distance and direction from me")
annaPin:OnMouseLeave()
check(not TOOLTIP.shown, "tooltip hides on leave")
OpenWorldMap(1415)
check(#PINS == 2 and math.abs(pinOf(11).x - 0.3125) < 1e-6 and math.abs(pinOf(11).y - 0.4375) < 1e-6,
	"continent map: same friends, continent coordinates")
OpenWorldMap(1414)
check(#PINS == 0, "map of another continent: not shown")
OpenWorldMap(1429)
annaPin = pinOf(11)
local created = PINS_CREATED
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;C;0;260.0;750.0;Goldshire;Hogger", "WHISPER", 11)
Advance(0.6)
check(pinOf(11) == annaPin and PINS_CREATED == created and math.abs(annaPin.y - 0.74) < 1e-6,
	"moving dots are updated in place, not recreated")
check(annaPin.Ring.color[1] == 1 and annaPin.Pulse:IsPlaying(), "in combat: red pulsing ring")
annaPin:OnMouseEnter()
check(tooltipHas("Fighting Hogger"), "tooltip: who she's fighting")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;D;0;260.0;750.0;Goldshire;", "WHISPER", 11)
Advance(0.6)
check(annaPin.Skull.shown and not annaPin.Dot.shown and not annaPin.Pulse:IsPlaying(), "dead: a skull instead of the dot")
check(tooltipHas("Dead") and TOOLTIP.owner == annaPin, "the open tooltip updates too")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;G;0;260.0;750.0;Goldshire;", "WHISPER", 11)
Advance(0.6)
check(annaPin.Skull.shown and annaPin.Skull.alpha < 1 and tooltipHas("Ghost"), "ghost: a faded skull")
annaPin:OnMouseLeave()
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;260.0;750.0;Goldshire;", "WHISPER", 11)
BN_FRIENDS[1][1].isGameAFK = true
Advance(0.6)
annaPin:OnMouseEnter()
check(TOOLTIP.title == "Anna <AFK>" and not annaPin.Skull.shown, "alive again; AFK shows in the tooltip")
annaPin:OnMouseLeave()
BN_FRIENDS[1][1].isGameAFK = false
GROUP_GUIDS["Player-1-11"] = true
PARTY.party1 = { guid = "Player-1-11", continent = 0, north = 300, west = 700 } -- her live position
GROUP = "party"
Fire("GROUP_ROSTER_UPDATE")
Advance(0.6)
annaPin = pinOf(11)
check(#PINS == 2 and annaPin, "Anna joined the group: her Beacon dot stays")
check(math.abs(annaPin.x - 0.3) < 1e-6 and math.abs(annaPin.y - 0.7) < 1e-6,
	"at her live group position (where Blizzard's dot is), not her last Beacon report")
check(annaPin.Ring.color[3] == 1 and annaPin.Ring.color[1] < 0.5, "marked as a group member: blue ring")
annaPin:OnMouseEnter()
check(tooltipHas("In your group"), "tooltip: in your group")
annaPin:OnMouseLeave()
PARTY.party1.north = 320
Advance(0.05)
check(math.abs(annaPin.y - 0.68) < 1e-6, "follows her live position every frame while the map is open")
B("showGroup"):SetValue(false)
Advance(0.6)
check(#PINS == 1 and pinOf(12), "'show friends in my group too' off: only Blizzard's dot")
B("showGroup"):SetValue(true)
GROUP_GUIDS["Player-1-11"], PARTY.party1, GROUP = nil, nil, "none"
Fire("GROUP_ROSTER_UPDATE")
Advance(0.6)
check(#PINS == 2 and pinOf(11) and pinOf(11).Ring.color[1] == 0, "left the group: a normal dot again")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;;;;;", "WHISPER", 12)
Advance(0.6)
check(#PINS == 1 and pinOf(11), "Bob went into a dungeon (no position): his dot goes away")
BN_FRIENDS[1][1].isOnline = false
Fire("BN_FRIEND_ACCOUNT_OFFLINE", 1, false)
Advance(1.2)
check(not peers()[11] and #PINS == 0, "Anna logged off: forgotten at once")
BN_FRIENDS[1][1].isOnline = true
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;250.0;750.0;Goldshire;", "WHISPER", 11)
Advance(1.2)
check(#PINS == 1, "she's back")
B("showFriends"):SetValue(false)
Advance(0.6)
check(#PINS == 0, "'show friends on the world map' off: no dots")
B("showFriends"):SetValue(true)
Advance(0.6)
check(#PINS == 1, "on again: dots back")
WorldMapFrame:Hide()
Advance(70)
check(not peers()[12], "Bob went silent (no heartbeat for over a minute): forgotten")

section("Beacon: friends on the minimap")
local mm = BB.GetMinimapPins()
PLAYER_POS = { 0.5, 0.5 } -- me: north 500, west 500
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;550.0;500.0;;", "WHISPER", 11) -- Anna 50 yd north
Advance(1.6) -- new friend: name and class arrive on the next check
local function at(pin) local _, rel, _, x, y = pin:GetPoint(1); return rel, x, y end
local rel, x, y = at(mm[11])
check(mm[11] and mm[11]:GetParent() == Minimap and mm[11]:IsShown(), "Anna's dot is on the minimap")
check(rel == Minimap and math.abs(x) < 1e-6 and math.abs(y - 35) < 1e-6,
	"50 yd north at 100 yd view radius on a 140 px minimap: 35 px up, got " .. tostring(x) .. ", " .. tostring(y))
check(mm[11]._motion == true and mm[11]._click == false, "hover for the tooltip, clicks go through to the minimap")
local calls = UNIT_POSITION_CALLS
Advance(0.5)
check(UNIT_POSITION_CALLS > calls, "my position comes from UnitPosition once it agrees with the map position")
do -- a loading screen: checked again (another continent or instance may not agree)
	MOCK_UNITPOS_OFFSET = 50
	Fire("PLAYER_ENTERING_WORLD", false, false)
	local _, north = BB.MyWorldPosition()
	check(north and math.abs(north - 500) < 1e-6, "after a loading screen: the map route until UnitPosition agrees again, got " .. tostring(north))
	MOCK_UNITPOS_OFFSET = 0
	BB.MyWorldPosition() -- they agree again
	MOCK_UNITPOS_OFFSET = 0.5 -- (only UnitPosition says so)
	_, north = BB.MyWorldPosition()
	check(north and math.abs(north - 500.5) < 1e-6, "... and UnitPosition again once it does, got " .. tostring(north))
	MOCK_UNITPOS_OFFSET = 0
	Advance(0.5)
end
local points = mm[11]._points
Advance(1)
check(mm[11]._points == points, "nothing moved: the dot isn't touched")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;550.0;480.0;;", "WHISPER", 11) -- 20 yd further east
Advance(0.5)
rel, x, y = at(mm[11])
check(x > 0.1 and x < 13.5, "her dot glides towards the new position, got x = " .. tostring(x))
Advance(5)
rel, x, y = at(mm[11])
check(math.abs(x - 14) < 1e-6 and math.abs(y - 35) < 1e-6, "and arrives there, got " .. tostring(x) .. ", " .. tostring(y))
CVARS.rotateMinimap, FACING = "1", math.pi / 2 -- rotating minimap, facing west
Advance(0.05)
rel, x, y = at(mm[11])
check(math.abs(x - 35) < 1e-6 and math.abs(y + 14) < 1e-6,
	"rotating minimap: facing west, north is to the right, got " .. tostring(x) .. ", " .. tostring(y))
CVARS.rotateMinimap, FACING = "0", 0
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;999.0;500.0;;", "WHISPER", 11) -- 499 yd north: off the minimap
Advance(0.6)
rel, x, y = at(mm[11])
check(math.abs(x) < 1e-6 and math.abs(y - 65) < 1e-6 and mm[11]._alpha == 0.6, "far away: faded at the edge, in her direction")
B("minimapEdge"):SetValue(false)
Advance(0.6)
check(not mm[11], "edge option off: far-away friends aren't shown")
B("minimapEdge"):SetValue(true)
Advance(0.6)
check(mm[11] ~= nil, "edge option on again")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;C;0;550.0;500.0;;Hogger", "WHISPER", 11)
Advance(0.6)
check(mm[11].Ring.color[1] == 1 and mm[11].Pulse:IsPlaying(), "same status look on the minimap")
BB.GetMinimapPins()[11]._scripts.OnEnter(mm[11])
check(TOOLTIP.title == "Anna" and tooltipHas("Fighting Hogger") and tooltipHas("50 yd north"), "same tooltip on the minimap")
mm[11]._scripts.OnLeave(mm[11])
GROUP_GUIDS["Player-1-11"] = true
PARTY.party1 = { guid = "Player-1-11", continent = 0, north = 560, west = 490 } -- live: 60 yd N, 10 yd E
GROUP = "party"
Fire("GROUP_ROSTER_UPDATE")
Advance(0.6)
rel, x, y = at(mm[11])
check(mm[11] and math.abs(x - 7) < 1e-6 and math.abs(y - 42) < 1e-6,
	"group member on the minimap: at her live position, got " .. tostring(x) .. ", " .. tostring(y))
check(mm[11].Ring.color[1] == 1 and mm[11].Pulse:IsPlaying(), "in combat the red ring still wins over the group ring")
PARTY.party1.north = 570
Advance(0.05)
rel, x, y = at(mm[11])
check(math.abs(y - 49) < 1e-6, "and follows her every frame")
B("showGroup"):SetValue(false)
Advance(0.6)
check(not mm[11], "'show friends in my group too' off: left to Blizzard's minimap blip")
B("showGroup"):SetValue(true)
GROUP_GUIDS["Player-1-11"], PARTY.party1, GROUP = nil, nil, "none"
Fire("GROUP_ROSTER_UPDATE")
Advance(0.6)
B("showMinimap"):SetValue(false)
Advance(0.6)
check(next(mm) == nil, "'show friends on the minimap' off: no dots")
B("showMinimap"):SetValue(true)
Advance(0.6)
check(mm[11] ~= nil, "on again")

section("Beacon: sharing my state")
mark = #GAMEDATA + 1
STATE.target, STATE.targetName = true, "Hogger"
EnterCombat()
Advance(1.2)
check(last(GameDataTo(11, mark)) == "S2;C;0;500.0;500.0;Goldshire;Hogger",
	"entering combat goes out within a second, with my target, got " .. tostring(last(GameDataTo(11, mark))))
mark = #GAMEDATA + 1
for i = 1, 5 do
	STATE.targetName = "Mob" .. i
	Fire("PLAYER_TARGET_CHANGED")
	Advance(0.1)
end
-- (states only: a version repeat or level progress may go out in here too)
check(#sentTo(11, mark, "S2;") <= 1, "tab-targeting: at most one update a second, got " .. table.concat(GameDataTo(11, mark), " | "))
Advance(1.2)
check((last(sentTo(11, mark, "S2;")) or ""):find(";Mob5$") ~= nil, "the latest target wins")
STATE.targetName = SECRET
Fire("PLAYER_TARGET_CHANGED")
Advance(1.2)
check(last(GameDataTo(11, mark)) == "S2;C;0;500.0;500.0;Goldshire;", "a name the game keeps secret isn't sent")
STATE.target, STATE.targetName = false, nil
LeaveCombat()
Advance(1.2)
check(last(GameDataTo(11, mark)) == "S2;;0;500.0;500.0;Goldshire;", "leaving combat")
STATE.dead = true
Fire("PLAYER_DEAD")
Advance(1.2)
check(last(sentTo(11, mark, "S2;")) == "S2;D;0;500.0;500.0;Goldshire;", "dead")
STATE.ghost = true
Fire("PLAYER_ALIVE")
Advance(1.2)
check(last(GameDataTo(11, mark)) == "S2;G;0;500.0;500.0;Goldshire;", "released: ghost")
STATE.dead, STATE.ghost = false, false
Fire("PLAYER_UNGHOST")
Advance(1.2)
mark = #GAMEDATA + 1
STATE.inInstance = true
Fire("ZONE_CHANGED_NEW_AREA")
Advance(1.2)
check((last(GameDataTo(11, mark)) or ""):find("^S2;;;;;") ~= nil, "in a dungeon: no position")
mark = #GAMEDATA + 1
Advance(12)
check(#sentTo(11, mark, "S2;") == 0, "and no more states while inside") -- (a journal summary may still go)
STATE.inInstance = false
Fire("ZONE_CHANGED_NEW_AREA")
Advance(1.2)
check((last(GameDataTo(11, mark)) or ""):find("^S2;;0;500.0;500.0;") ~= nil, "back outside: position again")
mark = #GAMEDATA + 1
B("share"):SetValue(false)
Advance(1.2)
check(last(sentTo(11, mark, "S2;")) == "S2;;;;;;" and last(sentTo(11, mark, "O2;v;")) == "O2;v;",
	"sharing off: no position, no status, no health")
B("share"):SetValue(true)
Advance(1.2)
B("interval"):SetValue(5)
Advance(5)
mark = #GAMEDATA + 1
for i = 1, 10 do
	PLAYER_POS = { 0.5 + i / 1000, 0.5 }
	Advance(1)
end
local n = #sentTo(11, mark, "S2;") -- (states only: a journal summary may fall in here too)
check(n >= 2 and n <= 3, "interval 5 s while moving: every 5 s, got " .. n)
lefthy("beacon interval 3")
check(BDB.interval == 3 and B("interval").uiUpdates > 0, "/lefthy beacon interval 3, through the setting (an open settings page follows)")
mark = #GAMEDATA + 1
MOCK_SEND_RESULT = 3 -- the server says: slow down
PLAYER_POS = { 0.6, 0.5 }
Advance(3.2)
check(#GameDataTo(11, mark) == 0, "throttled: nothing gets through")
MOCK_SEND_RESULT = nil
Advance(2.5)
check(#GameDataTo(11, mark) >= 1, "after a short pause it's sent again")
-- 30 more friends with the addon show up at once: answers are spread out, not one burst.
for i = 1, 30 do
	BN_FRIENDS[#BN_FRIENDS + 1] = { { gameAccountID = 100 + i, isOnline = true, clientProgram = "WoW", wowProjectID = 1,
		isInCurrentRegion = true, characterName = "Extra" .. i, classFilename = "MAGE", characterLevel = 10,
		areaName = "Westfall", playerGuid = "Player-1-" .. (100 + i) }, battleTag = "Extra#" .. i }
end
Advance(1.1) -- let the rate limiter fill up
mark = #GAMEDATA + 1
for i = 1, 30 do Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;;;;;", "WHISPER", 100 + i) end
Advance(0.15)
local burst = #GAMEDATA - mark + 1
check(burst >= 5 and burst <= 12, "rate limit: about 10 messages at once, got " .. burst)
Advance(12.5) -- 30 friends x (files + version + state + level progress) at 10 messages a second
local answered = 0
for i = 1, 30 do if #sentTo(100 + i, mark, "S2;") == 1 then answered = answered + 1 end end
check(answered == 30, "the rest follow within a few seconds, got " .. answered)
for i = 1, 30 do BN_FRIENDS[#BN_FRIENDS] = nil end
Fire("BN_FRIEND_INFO_CHANGED")
Advance(1.2)
local extras = 0
for id in pairs(peers()) do if id > 100 then extras = extras + 1 end end
check(extras == 0, "friends that left the friend list are forgotten")
-- 60 friends in WoW without LefthyTools: greeted, but behind everything live.
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;260.0;750.0;Goldshire;", "WHISPER", 11) -- (Anna's here)
Advance(1.2)
for i = 1, 60 do
	BN_FRIENDS[#BN_FRIENDS + 1] = { { gameAccountID = 200 + i, isOnline = true, clientProgram = "WoW", wowProjectID = 1,
		isInCurrentRegion = true, characterName = "Other" .. i, classFilename = "MAGE", characterLevel = 10,
		areaName = "Westfall", playerGuid = "Player-1-" .. (200 + i) }, battleTag = "Other#" .. i }
end
local hellosFrom = #GAMEDATA + 1
Fire("BN_FRIEND_ACCOUNT_ONLINE")
for _ = 1, 150 do
	if sentTo(201, hellosFrom, "H2")[1] then break end
	Advance(0.1)
end
mark = #GAMEDATA + 1
SlashCmdList.LEFTHYTOOLS_CHAT("hello there")
Advance(0.3)
check(sentTo(201, hellosFrom, "H2")[1] and sentTo(11, mark, "M2;")[1], "a chat line isn't held up by 60 hellos")
Advance(8)
local greeted = 0
for i = 1, 60 do if sentTo(200 + i, hellosFrom, "H2")[1] then greeted = greeted + 1 end end
check(greeted == 60, "and they're all greeted soon after, got " .. greeted)
for i = 1, 60 do BN_FRIENDS[#BN_FRIENDS] = nil end
-- A friend just found has no name until the next check: their first chat line waits for it.
BN_FRIENDS[#BN_FRIENDS + 1] = { { gameAccountID = 300, isOnline = true, clientProgram = "WoW", wowProjectID = 1,
	isInCurrentRegion = true, characterName = "Newbie", classFilename = "MAGE", characterLevel = 10,
	areaName = "Westfall", playerGuid = "Player-1-300" }, battleTag = "Newbie#1" }
Fire("BN_FRIEND_INFO_CHANGED")
Advance(0.15) -- (a check right now: the next one a second later)
pmark = #PRINTED + 1
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "M2;hello there", "WHISPER", 300)
Advance(0.15)
check(peers()[300] and not peers()[300].name, "a new friend, name not known yet")
Advance(1.2)
check(printedSince(pmark):find("Newbie|r|cffffb84d]: hello there", 1, true), "their first line shows once the name is known, got "
	.. printedSince(pmark))
BN_FRIENDS[#BN_FRIENDS] = nil
Fire("BN_FRIEND_INFO_CHANGED")
Advance(1.2)

section("Beacon: a friend with a newer LefthyTools")
local function infoRow(name)
	for _, init in ipairs(LAYOUTS["LefthyTools"]) do
		if init.template == "LefthyToolsSettingsInfoTemplate" and init.data.name == name then return init end
	end
end
local function updateStatus() return infoRow("Updates").data.getValue() end
check(infoRow("Version") and infoRow("Version").data.getValue() == "0.4.0-3-gabc1234", "settings overview: Info section with the installed version")
check(updateStatus():find("Unknown (no friend with LefthyTools online)", 1, true),
	"update status before any friend told us their version, got " .. updateStatus())
local vmark = #PRINTED + 1
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "V2;0.3.9-50-gaaaaaaa", "WHISPER", 11) -- older than mine
Advance(0.15)
check(updateStatus():find("Up to date (compared with 1 friend(s))", 1, true), "a friend on an older build: up to date, got " .. updateStatus())
check(not printedSince(vmark):find("newer LefthyTools", 1, true), "a friend on an older build: no notice here (they get one)")
check(peers()[11].version == "0.3.9-50-gaaaaaaa", "their version is remembered")
local newsMark = #GAMEDATA + 1
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "F2;0123abcd", "WHISPER", 11) -- their build loads other files than mine
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "V2;0.4.0-9-gbbbbbbb", "WHISPER", 11)
check(not printedSince(vmark):find("newer LefthyTools", 1, true), "nothing printed inside the event handler")
Advance(0.15)
check(sentTo(11, newsMark, "U2;")[1] == "U2;" .. LT.WhatsNew.LatestID() .. ";en",
	"I ask them what's new in their build after my newest changelog entry, in my language")
-- They answer: one line per change (newest few, oldest first), then the end, with how many older ones they left out.
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "W2;140;tweaks;Quests on the moon", "WHISPER", 11)
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "W2;141;stargazer;A whole new module", "WHISPER", 11)
Advance(1)
check(not printedSince(vmark):find("newer LefthyTools", 1, true), "the notice waits until their news are complete")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "W2;0;;3", "WHISPER", 11)
Advance(0.15)
local notice = printedSince(vmark)
check(notice:find("What's coming:\n   |cffffd200•|r Misc Tweaks: Quests on the moon\n   |cffffd200•|r stargazer: A whole new module\n"
	.. "   |cffffd200•|r and 3 more", 1, true), "... then lists them, one line each (a module I don't have yet by its key), got\n" .. notice)
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "W2;142;tweaks;Unasked news", "WHISPER", 11)
Advance(0.15)
check(not printedSince(vmark):find("Unasked news", 1, true), "news nobody asked for are ignored")
check(notice:find("Anna has a newer LefthyTools (0.4.0-9-gbbbbbbb, you have 0.4.0-3-gabc1234)", 1, true)
	and notice:find("run Update-LefthyTools.cmd again, then restart the game: this update adds files, a /reload isn't enough.", 1, true),
	"a friend on a newer build that loads other files: told to update and restart the game, got " .. notice)
check(LT.UpdateHint(LT.FILES):find("then /reload (no restart needed).", 1, true)
	and LT.UpdateHint(nil):find("then /reload (or restart the game if the updater says so).", 1, true),
	"the same files: a /reload is enough; a build that doesn't say: the updater tells")
-- And the other way round: Bob's build is older and asks what's new in mine.
do
local askMark = #GAMEDATA + 1
local latest = LT.WhatsNew.LatestID()
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "U2;" .. (latest - 2) .. ";de", "WHISPER", 12)
Advance(0.3)
local answer = sentTo(12, askMark, "W2;")
local newest = ns.CHANGELOG[#ns.CHANGELOG]
check(#answer == 3 and answer[2] == ("W2;%d;%s;%s"):format(newest.id, newest.module, newest.de[1]) and answer[3] == "W2;0;;0",
	"a friend on an older build asks: my newer entries, in their language, then the end, got " .. table.concat(answer, " | "))
askMark = #GAMEDATA + 1
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "U2;0;en", "WHISPER", 12)
Advance(0.3)
check(#sentTo(12, askMark, "W2;") == 0, "... at most once a minute per friend")
Advance(30)
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;260.0;750.0;Goldshire;", "WHISPER", 11) -- (Anna stays around)
Advance(30)
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "U2;0;en", "WHISPER", 12)
Advance(1.5)
answer = sentTo(12, askMark, "W2;")
check(#answer == 9 and answer[8]:find(newest.en[1], 1, true) and answer[9] == "W2;0;;" .. (#ns.CHANGELOG - 8),
	"a long way behind: the 8 newest, and how many older ones were left out, got " .. #answer)
end
vmark = #PRINTED + 1
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "V2;0.5.0", "WHISPER", 11)
Advance(0.15)
check(not printedSince(vmark):find("newer LefthyTools", 1, true), "only once per login")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "V2;not a version!", "WHISPER", 11)
Advance(0.15)
check(peers()[11].version == "0.5.0", "a malformed version message is ignored")
vmark = #PRINTED + 1
lefthy("beacon status")
check(printedSince(vmark):find("LefthyTools 0.5.0", 1, true), "/lefthy beacon status shows each friend's version")
check(updateStatus():find("Newer version available: 0.5.0 (needs a game restart)", 1, true),
	"settings overview: the newest version seen from a friend, and that it needs a restart, got " .. updateStatus())
local updatesTip = infoRow("Updates").data.tooltip
check(type(updatesTip) == "function", "the Updates tooltip is built when it opens")
local tip = updatesTip()
check(tip:find("You: 0.4.0-3-gabc1234", 1, true) and tip:find("Anna|r: 0.5.0  |cffffa040newer", 1, true),
	"it lists my build and each friend's, marked newer / same / older, got\n" .. tip)
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "V2;0.4.0-3-gabc1234", "WHISPER", 11)
Advance(0.15)
check(updatesTip():find("Anna|r: 0.4.0-3-gabc1234  |cff80ff80same", 1, true), "same build")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "V2;0.5.0", "WHISPER", 11) -- back to what the next checks expect
Advance(0.15)
vmark = #PRINTED + 1
lefthy("version")
check(printedSince(vmark):find("a friend has the newer 0.5.0. To update, run Update-LefthyTools.cmd again, then restart the game", 1, true),
	"/lefthy version mentions it too, with the restart, got " .. printedSince(vmark))
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "F2;" .. LT.FILES, "WHISPER", 11) -- the same files as mine after all
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "V2;0.5.0", "WHISPER", 11)
Advance(0.15)
vmark = #PRINTED + 1
lefthy("version")
check(printedSince(vmark):find("then /reload (no restart needed)", 1, true) and not updateStatus():find("restart", 1, true),
	"a newer build with the same files: a /reload is enough")
-- Forgotten and back (65 s of silence, a loading screen, Beacon off and on): their version only
-- comes in answers, and they don't see me as new, so I greet them and they answer.
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "Q2", "WHISPER", 11)
Advance(0.15)
check(not peers()[11], "(Anna is forgotten)")
local hmark = #GAMEDATA + 1
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;260.0;750.0;Goldshire;", "WHISPER", 11)
Advance(0.15)
check(peers()[11] and peers()[11].version == nil and sentTo(11, hmark, "H2")[1] == "H2",
	"back with an ordinary message: I greet them, so they answer with their version")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "V2;0.5.0", "WHISPER", 11)
Advance(0.15)
check(peers()[11].version == "0.5.0" and #sentTo(11, hmark, "H2") == 1, "and it's known again (one hello)")
-- My version also goes to every friend every 10 minutes, whatever happened to the answers.
local versionMark = #GAMEDATA + 1
do -- Meanwhile the server holds my messages back for 3 minutes: a WoW friend without LefthyTools
	-- waits for one hello, not one more each time the friend list is looked at.
	BN_FRIENDS[#BN_FRIENDS + 1] = { { gameAccountID = 450, isOnline = true, clientProgram = "WoW", wowProjectID = 1,
		isInCurrentRegion = true, characterName = "Gus", classFilename = "PRIEST", characterLevel = 10,
		areaName = "Westfall", playerGuid = "Player-1-450" }, battleTag = "Gus#1" }
	MOCK_SEND_RESULT = 3
	local released, afterRelease
	for i = 1, 21 do
		Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;260.0;750.0;Goldshire;", "WHISPER", 11) -- Anna stays around
		Advance(30)
		if i == 6 then
			MOCK_SEND_RESULT, released = nil, #GAMEDATA + 1
		elseif i == 7 then
			afterRelease = #sentTo(450, released, "H2")
		end
	end
	BN_FRIENDS[#BN_FRIENDS] = nil
	check(afterRelease == 1, "held back for minutes: one hello waits for a friend without LefthyTools, got " .. tostring(afterRelease))
end
local repeats = sentTo(11, versionMark, "V2;")
check(#repeats == 1 and repeats[1] == "V2;0.4.0-3-gabc1234", "my version, repeated once in 10 minutes, got " .. #repeats)
do
	local filesRepeats, filesAt, versionAt = sentTo(11, versionMark, "F2;"), nil, nil
	for i, message in ipairs(GameDataTo(11, versionMark)) do
		if message:find("^F2;") then filesAt = i elseif message:find("^V2;") then versionAt = i end
	end
	check(#filesRepeats == 1 and filesRepeats[1] == "F2;" .. LT.FILES and filesAt and versionAt and filesAt < versionAt,
		"... with my files just before it")
end

section("Beacon: death alerts")
check(BDB.deathAlert == true and B("deathAlert") ~= nil, "a setting, on by default")
local heard = {} -- what other modules (Chronicle) are told
table.insert(BB.listeners, function(kind, peer, data) heard[#heard + 1] = { kind = kind, name = peer.name, data = data } end)
Advance(10)
afk(true) -- away while it happens: the AFK screen lists it
Advance(0.05)
anna("S2;C;0;260.0;750.0;Raven Hill;Stitches")
Advance(1.2)
pmark = #PRINTED + 1
anna("S2;D;0;260.0;750.0;Raven Hill;")
check(#PRINTED < pmark, "nothing printed inside the event handler")
Advance(0.15)
local deathLine = printedSince(pmark)
check(deathLine:find("Anna|r died in Elwynn Forest - Raven Hill, fighting Stitches.", 1, true),
	"a chat line: who died, where, and what they were fighting, got " .. deathLine)
check(heard[#heard] and heard[#heard].kind == "death" and heard[#heard].name == "Anna" and heard[#heard].data.foe == "Stitches"
	and heard[#heard].data.where == "Elwynn Forest - Raven Hill", "other modules hear about it")
Advance(1.1)
check(LefthyToolsAFKFrame:IsShown() and LefthyToolsAFKFrame.Info:GetText():find("While you were away|r\n", 1, true)
	and LefthyToolsAFKFrame.Info:GetText():find("Anna|r died, fighting Stitches", 1, true),
	"the AFK screen: 'While you were away' lists it, got " .. LefthyToolsAFKFrame.Info:GetText())
check(LefthyToolsAFKFrame.Friends:GetText():find("Anna|r  |cffccccccLevel 20|r", 1, true)
	and LefthyToolsAFKFrame.Friends:GetText():find("Elwynn Forest - Raven Hill", 1, true)
	and LefthyToolsAFKFrame.Friends:GetText():find("|cffff5050Dead|r", 1, true),
	"and the friends online, with their zone and status, got " .. LefthyToolsAFKFrame.Friends:GetText())
afk(false)
Advance(0.3)
pmark = #PRINTED + 1
anna("S2;G;0;260.0;750.0;Raven Hill;")
Advance(1.2)
anna("S2;;0;260.0;750.0;Raven Hill;")
Advance(1.2)
check(not printedSince(pmark):find("died", 1, true), "releasing and coming back: no more alerts")
anna("S2;D;0;260.0;750.0;Raven Hill;")
Advance(0.15)
check(not printedSince(pmark):find("died", 1, true), "dying again within 10 s: not repeated")
Advance(10)
anna("S2;;0;260.0;750.0;Raven Hill;")
Advance(1.2)
anna("S2;D;0;260.0;750.0;Raven Hill;")
Advance(0.15)
check(printedSince(pmark):find("Anna|r died in Elwynn Forest - Raven Hill.", 1, true), "died out of combat (a fall): no killer")
Advance(10)
pmark = #PRINTED + 1
anna("Q2")
anna("S2;D;0;260.0;750.0;Raven Hill;")
Advance(1.2)
check(not printedSince(pmark):find("died", 1, true), "already dead when first heard of: no alert")
anna("S2;;0;260.0;750.0;Raven Hill;")
Advance(1.2)
B("deathAlert"):SetValue(false)
Advance(10)
local heardBefore = #heard
anna("S2;D;0;260.0;750.0;Raven Hill;")
Advance(0.15)
check(not printedSince(pmark):find("died", 1, true) and #heard == heardBefore + 1, "alerts off: no chat line (other modules still hear it)")
B("deathAlert"):SetValue(true)
anna("S2;;0;260.0;750.0;Goldshire;")
Advance(1.2)
-- Sharing switched on while dead: her first real state says dead, but that's no news.
Advance(10)
pmark = #PRINTED + 1
anna("S2;;;;;;")
Advance(1.2)
anna("S2;D;0;260.0;750.0;Goldshire;")
Advance(0.15)
check(not printedSince(pmark):find("died", 1, true), "sharing switched on while dead: no alert (she may have died before)")
anna("S2;;0;260.0;750.0;Goldshire;")
Advance(1.2)

section("Beacon: map pings")
check(BDB.pings == true and B("pings") ~= nil, "a setting, on by default")
local function pingPin(key)
	for _, p in ipairs(PINS) do if p.pinTemplate == "LefthyToolsBeaconPingPinTemplate" and p.key == key then return p end end
end
PLAYER_POS = { 0.5, 0.5 } -- me: north 500, west 500
OpenWorldMap(1429)
Advance(0.2)
mark, pmark = #GAMEDATA + 1, #PRINTED + 1
MOCK_CURSOR = { 0.25, 0.75 }
ClickWorldMap()
Advance(0.15)
check(#sentTo(11, mark, "P2;") == 0, "a click without Alt doesn't ping")
STATE.alt = true
ClickWorldMap()
Advance(0.15)
check(sentTo(11, mark, "P2;")[1] == "P2;0;250.0;750.0;1429", "Alt+click: the spot goes to my friends, got " .. tostring(sentTo(11, mark, "P2;")[1]))
check(printedSince(pmark):find("pinged Elwynn Forest for 1 friend(s).", 1, true) and SOUNDS[#SOUNDS] == 3175,
	"with a chat line and the map ping sound")
Advance(0.15)
local myPing = pingPin("me")
check(myPing and math.abs(myPing.x - 0.25) < 1e-6 and math.abs(myPing.y - 0.75) < 1e-6 and myPing.RippleAnim:IsPlaying(),
	"my own marker on my map, rippling")
check(myPing.Icon.atlas == "Ping_Marker_Icon_NonThreat", "the game's 'look here' ping icon")
pmark = #PRINTED + 1
ClickWorldMap()
Advance(0.15)
check(#sentTo(11, mark, "P2;") == 1 and printedSince(pmark):find("not so fast", 1, true),
	"at most one ping every 2.5 s (friends drop more than one per 2 s), and it says so")
Advance(2)
ClickWorldMap()
Advance(0.15)
check(#sentTo(11, mark, "P2;") == 1, "still too soon 2.3 s later")
Advance(0.3)
OpenWorldMap(1415)
MOCK_CURSOR = { 0.375, 0.375 } -- inside Elwynn on the continent map: north 500, west 500
ClickWorldMap()
STATE.alt = false
Advance(0.15)
check(sentTo(11, mark, "P2;")[2] == "P2;0;500.0;500.0;1429", "on a continent map the zone under the cursor names the spot")
OpenWorldMap(1429)
pmark = #PRINTED + 1
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "P2;0;550.0;500.0;1429", "WHISPER", 11)
check(#PRINTED < pmark, "receiving: nothing printed inside the event handler")
Advance(0.15)
check(printedSince(pmark):find("Anna|r pinged a spot in Elwynn Forest: see your map.", 1, true) and SOUNDS[#SOUNDS] == 3175,
	"a friend's ping: chat line and sound, got " .. printedSince(pmark))
check(printedSince(pmark):find("map. |cffffff00|Hworldmap:1429:5000:4500|h[Map pin]|h|r", 1, true),
	"with the game's map pin link for the spot (a click sets the waypoint), got " .. printedSince(pmark))
Advance(0.15)
local annaPing = pingPin(11)
check(annaPing and math.abs(annaPing.x - 0.5) < 1e-6 and math.abs(annaPing.y - 0.45) < 1e-6
	and math.abs(annaPing.Ripple.color[3] - 0.92) < 1e-6, "her marker on my map, rippling in her class colour")
annaPing:OnMouseEnter()
check(TOOLTIP.title == "Anna" and tooltipHas("Map ping, 0 s ago") and tooltipHas("Elwynn Forest") and tooltipHas("50 yd north"),
	"tooltip: whose ping, how old, where, how far, got " .. table.concat(TOOLTIP.lines, " | "))
annaPing:OnMouseLeave()
local mmPings = BB.GetMinimapPings()
local _, _, _, pingX, pingY = mmPings[11]:GetPoint(1)
check(math.abs(pingX) < 1e-6 and math.abs(pingY - 35) < 1e-6 and mmPings[11]:GetParent() == Minimap, "and on the minimap, 50 yd north")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "P2;0;100.0;100.0;1429", "WHISPER", 11)
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "P2;0;abc;1;1429", "WHISPER", 11)
Advance(0.15)
check(BB.pings[11].north == 550, "another ping within 2 s and malformed pings are ignored")
Advance(51)
check(annaPing:GetAlpha() < 1 and not annaPing.RippleAnim:IsPlaying(), "after a while: the ripple stops and the marker fades")
Advance(10)
check(not BB.pings[11] and not pingPin(11) and not mmPings[11], "after a minute it's gone from both maps")
B("pings"):SetValue(false)
mark = #GAMEDATA + 1
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "P2;0;550.0;500.0;1429", "WHISPER", 11)
STATE.alt = true
ClickWorldMap()
STATE.alt = false
Advance(2.5)
check(not BB.pings[11] and #sentTo(11, mark, "P2;") == 0, "pings off: none shown, none sent")
B("pings"):SetValue(true)
lefthy("beacon ping")
Advance(0.15)
check(sentTo(11, mark, "P2;")[1] == "P2;0;500.0;500.0;1429", "/lefthy beacon ping: where I stand")
-- Taking it back: Alt+click on my own marker (or /lefthy beacon ping clear), for everyone.
Advance(2)
local mine = pingPin("me")
mine:OnMouseEnter()
check(tooltipHas("Alt+click it on the world map to take it back."), "my own marker's tooltip says how to take it back")
mine:OnMouseLeave()
mark, pmark = #GAMEDATA + 1, #PRINTED + 1
mine._mouse, STATE.alt = true, true
ClickWorldMap()
mine._mouse, STATE.alt = false, false
Advance(0.15)
check(not BB.pings.me and #sentTo(11, mark, "P2;") == 0 and sentTo(11, mark, "G2")[1] == "G2"
	and printedSince(pmark):find("ping taken back.", 1, true), "Alt+click on my own marker: taken back and my friends told, no new ping")
Advance(0.15)
check(not pingPin("me") and not BB.GetMinimapPings().me, "gone from my maps")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "P2;0;550.0;500.0;1429", "WHISPER", 11)
Advance(0.15)
check(BB.pings[11] and pingPin(11), "Anna pings")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "G2", "WHISPER", 11)
Advance(0.15)
check(not BB.pings[11] and not pingPin(11) and not BB.GetMinimapPings()[11], "... and takes it back: gone from both maps")
lefthy("beacon ping")
Advance(0.15)
lefthy("beacon ping clear")
Advance(0.15)
check(not BB.pings.me and not pingPin("me"), "/lefthy beacon ping clear")
Advance(2.1)
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "P2;0;550.0;500.0;1429", "WHISPER", 11)
Advance(0.15)
check(BB.pings[11] and pingPin(11), "Anna pings again")
B("pings"):SetValue(false)
Advance(0.15)
check(not BB.pings[11] and not pingPin(11) and not BB.GetMinimapPings()[11], "'Map pings' switched off: her marker goes at once")
B("pings"):SetValue(true)
pmark = #PRINTED + 1
lefthy("beacon ping clear")
check(printedSince(pmark):find("no ping out", 1, true), "nothing to take back: said so")
WorldMapFrame:Hide()

section("Beacon: tracked quest")
check(BDB.shareQuest == true and B("shareQuest") ~= nil, "a setting, on by default")
QUESTS = {
	{ id = 176, title = 'Wanted: "Hogger"', objectives = { { text = "Huge Gnoll Claw: 0/1", finished = false } } },
	{ id = 177, title = "Kobold Camp Cleanup", objectives = { { text = "Kobold Vermin slain: 4/10", finished = false } } },
}
WATCHED = { 176, 177 }
mark = #GAMEDATA + 1
Fire("QUEST_WATCH_LIST_CHANGED")
check(#sentTo(11, mark, "T2;") == 0, "nothing sent inside the event handler")
Advance(2.2)
check(sentTo(11, mark, "T2;")[1] == 'T2;176;0;Wanted: "Hogger";Huge Gnoll Claw: 0/1',
	"the first quest on my tracker goes to my friends, got " .. tostring(sentTo(11, mark, "T2;")[1]))
for _ = 1, 20 do
	Fire("QUEST_LOG_UPDATE")
	Advance(0.1)
end
check(#sentTo(11, mark, "T2;") == 1, "the quest log updates often: nothing more sent while nothing changed")
QUESTS[1].objectives[1] = { text = "Huge Gnoll Claw: 1/1", finished = true }
Fire("QUEST_LOG_UPDATE")
Advance(2.2)
check(sentTo(11, mark, "T2;")[2] == 'T2;176;1;Wanted: "Hogger";', "ready to turn in")
SUPER_TRACKED = 177
Fire("SUPER_TRACKING_CHANGED")
Advance(2.2)
check(sentTo(11, mark, "T2;")[3] == "T2;177;0;Kobold Camp Cleanup;Kobold Vermin slain: 4/10", "the super-tracked quest wins")
local tmark = #GAMEDATA + 1
for i = 5, 9 do
	QUESTS[2].objectives[1].text = "Kobold Vermin slain: " .. i .. "/10"
	Fire("QUEST_LOG_UPDATE")
	Advance(0.2)
end
check(#sentTo(11, tmark, "T2;") <= 1, "progress goes out at most every 2 s, got " .. #sentTo(11, tmark, "T2;"))
Advance(2.2)
check(last(sentTo(11, tmark, "T2;")):find("9/10$") ~= nil, "and the latest progress follows")
tmark = #GAMEDATA + 1
anna("H2")
Advance(0.15)
check(sentTo(11, tmark, "T2;")[1] == "T2;177;0;Kobold Camp Cleanup;Kobold Vermin slain: 9/10", "a hello is answered with my quest too")
B("shareQuest"):SetValue(false)
Advance(0.2)
check(last(sentTo(11, tmark, "T2;")) == "T2;0;;;", "not shared: friends are told there's none")
B("shareQuest"):SetValue(true)
Advance(0.2)
OpenWorldMap(1429)
anna("T2;176;0;Wanted: Hogger;Huge Gnoll Claw: 0/1")
Advance(0.6)
pinOf(11):OnMouseEnter()
check(tooltipHas("Quest: Wanted: Hogger") and tooltipHas("  Huge Gnoll Claw: 0/1") and tooltipHas("  You have this quest too"),
	"tooltip: their quest, their progress, and that I have it too, got " .. table.concat(TOOLTIP.lines, " | "))
anna("T2;176;1;Wanted: Hogger;")
Advance(0.6)
check(tooltipHas("  Ready to turn in"), "the open tooltip follows: ready to turn in")
anna("T2;900;0;Some Other Quest;Thing: 1/2")
Advance(0.6)
check(tooltipHas("Quest: Some Other Quest") and not tooltipHas("  You have this quest too"), "a quest I don't have")
anna("T2;abc;0;x;y")
Advance(0.6)
check(peers()[11].quest and peers()[11].quest.id == 900, "malformed quest messages are ignored")
anna("T2;0;;;")
Advance(0.6)
local questLine = false
for _, l in ipairs(TOOLTIP.lines) do if l:find("^Quest: ") then questLine = true end end
check(not questLine, "none tracked: no quest lines")
pinOf(11):OnMouseLeave()
WorldMapFrame:Hide()
QUESTS, WATCHED, SUPER_TRACKED = {}, {}, 0
Fire("QUEST_LOG_UPDATE")
Advance(2.2)

section("Beacon: level-ups")
lefthy("beacon ding {name} hit {level}, drinks on me!")
check(BDB.dingText == "{name} hit {level}, drinks on me!" and B("dingText"):GetValue() == BDB.dingText,
	"/lefthy beacon ding <text> keeps upper case and goes through the setting")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "H2", "WHISPER", 12) -- Bob is back
Advance(0.3)
mark = #GAMEDATA + 1
Fire("PLAYER_LEVEL_UP", 20, 0, 0, 0, 0, 0, 0, 0, 0)
check(#GameDataTo(11, mark) == 0, "nothing sent inside the event handler")
Advance(0.15)
check(GameDataTo(11, mark)[1] == "L2;20;{name} hit {level}, drinks on me!" and GameDataTo(12, mark)[1] == GameDataTo(11, mark)[1],
	"my level-up goes to every friend with my own text, got " .. tostring(GameDataTo(11, mark)[1]))
mark = #GAMEDATA + 1
MOCK_SEND_RESULT = 11 -- addon messages locked (e.g. during an encounter)
Fire("PLAYER_LEVEL_UP", 21)
Advance(1)
check(#GameDataTo(11, mark) == 0, "level-up during an addon message lockdown: nothing gets through")
MOCK_SEND_RESULT = nil
Advance(3)
local delivered = false
for _, m in ipairs(GameDataTo(11, mark)) do if m:find("^L2;21;") then delivered = true end end
check(delivered, "... and it's delivered once the lockdown ends instead of being lost")
B("dingAnnounce"):SetValue(false)
mark = #GAMEDATA + 1
Fire("PLAYER_LEVEL_UP", 21)
Advance(0.15)
local dingSent = false
for _, m in ipairs(GameDataTo(11, mark)) do if m:sub(1, 2) == "L2" then dingSent = true end end
check(not dingSent, "'tell my friends' off: not announced")
B("dingAnnounce"):SetValue(true)

pmark = #PRINTED + 1
local soundMark = #SOUNDS
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "L2;21;{name} is now {level}!", "WHISPER", 11)
check(#PRINTED < pmark, "nothing shown inside the event handler")
Advance(0.15)
local shown = printedSince(pmark)
check(shown:find("Anna|r is now 21!", 1, true) ~= nil and shown:find("|cff40c7eb", 1, true) ~= nil,
	"Anna's own message, her name in class colour, got " .. shown)
check(SOUNDS[#SOUNDS] == 50111 and #SOUNDS == soundMark + 1, "with the picked sound (default: boss defeated fanfare, not the level-up fanfare)")
check(heard[#heard].kind == "level" and heard[#heard].data.level == 21, "other modules hear about level-ups too")
local toastFrame
for _, f in ipairs(UIParent._children) do if f.Text and f.shownAt then toastFrame = f end end
check(toastFrame and toastFrame:IsShown() and toastFrame.Text.text:find("is now 21!", 1, true), "big text on screen")
check(toastFrame.Text.textScale == 1.4 and toastFrame.Pop.plays > 0, "extra big, and it pops in")
Advance(7)
check(not toastFrame:IsShown(), "and it fades out after a few seconds")
pmark = #PRINTED + 1
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "L2;22;", "WHISPER", 11)
Advance(0.15)
check(#PRINTED < pmark, "a second level-up message within 10 s is ignored (spam guard)")
for _ = 1, 3 do -- switching Beacon off and on in between doesn't reset the guard
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "Q2", "WHISPER", 11)
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "L2;22;", "WHISPER", 11)
	Advance(1.2)
end
check(#PRINTED < pmark, "... also when the friend sends Q2 in between")
mark = #GAMEDATA + 1
for _ = 1, 8 do
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "H2", "WHISPER", 11)
	Advance(0.3)
end
-- (counted by what only answers carry: a heartbeat state may fall in here too)
check(#sentTo(11, mark, "F2;") <= 1 and #sentTo(11, mark, "V2;") <= 1,
	"repeated hellos get at most one answer per 5 s, got " .. #GameDataTo(11, mark) .. " messages: " .. table.concat(GameDataTo(11, mark), " | "))
Advance(10)
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "L2;22;", "WHISPER", 11)
Advance(0.15)
check(printedSince(pmark):find("Anna|r reached level 22!", 1, true) ~= nil, "no text of her own: my default")
Advance(10)
pmark = #PRINTED + 1
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "L2;23;|cffff0000evil|r {name}", "WHISPER", 11)
Advance(0.15)
shown = printedSince(pmark)
check(shown:find("evil", 1, true) and not shown:find("ff0000", 1, true), "escape sequences in a friend's text are stripped")
Advance(10)
B("dingSound"):SetValue(false)
soundMark = #SOUNDS
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "L2;24;", "WHISPER", 12)
Advance(0.15)
check(#SOUNDS == soundMark, "'play a sound' off: silent")
B("dingSound"):SetValue(true)
Advance(10)
MOCK_SOUND_MISSING = 50111
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "L2;25;", "WHISPER", 12)
Advance(0.15)
check(SOUNDS[#SOUNDS - 1] == 50111 and SOUNDS[#SOUNDS] == 18019, "sound missing in this client: the Battle.net toast sound instead")
MOCK_SOUND_MISSING = nil
B("dingShow"):SetValue(false)
Advance(10)
pmark = #PRINTED + 1
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "L2;26;", "WHISPER", 11)
Advance(0.15)
check(#PRINTED < pmark, "'show my friends' level-ups' off: nothing shown")
B("dingShow"):SetValue(true)
pmark = #PRINTED + 1
SETTINGS_BUTTONS["Test your message"].onClick()
check(printedSince(pmark):find("Lefthy|r hit 20, drinks on me!", 1, true) ~= nil, "preview button shows my own message")
lefthy("beacon ding reset")
check(BDB.dingText == "", "/lefthy beacon ding reset")
pmark = #PRINTED + 1
MY_SURNAME = "Mirewood" -- (Battle.net names me with my surname: so do my friends' clients)
lefthy("beacon ding test")
MY_SURNAME = nil
check(printedSince(pmark):find("Lefthy Mirewood|r reached level 20!", 1, true) ~= nil,
	"/lefthy beacon ding test: as friends see it, my name with its surname, got " .. printedSince(pmark))
-- A slider whose label names the sound (no dropdown: a Blizzard menu from addon settings taints gamepad mode).
local soundSlider = B("dingSoundKit")
local soundOptions = soundSlider and soundSlider.sliderOptions
check(soundSlider and soundSlider.proxy and not DROPDOWNS.LefthyTools_beacon_dingSoundKit and BDB.dingSoundKit == 50111
	and soundSlider:GetValue() == 1 and soundOptions.min == 1 and soundOptions.max == 6 and soundOptions.formatter(1) == "Boss defeated fanfare",
	"level-up sound: a slider over 6 sounds that names them, boss defeated fanfare by default")
local hasLevelUpFanfare = false
for i = 1, 6 do if soundOptions.formatter(i):find("Level up", 1, true) then hasLevelUpFanfare = true end end
check(not hasLevelUpFanfare, "the player's own level-up fanfare isn't offered (it sounds like you levelled)")
soundMark = #SOUNDS
soundSlider:SetValue(2)
check(BDB.dingSoundKit == 73277 and #SOUNDS == soundMark, "sliding to the second: its sound kit is kept; nothing plays inside the settings callback")
Advance(0.05)
check(#SOUNDS == soundMark + 1 and SOUNDS[#SOUNDS] == 73277, "picking a sound plays it")
Advance(10)
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "L2;27;", "WHISPER", 11)
Advance(0.15)
check(SOUNDS[#SOUNDS] == 73277, "a friend's level-up uses the picked sound")
soundMark = #SOUNDS
pmark = #PRINTED + 1
lefthy("beacon sound")
check(#printedSince(pmark) > 0 and printedSince(pmark):find("2. World quest complete (current)", 1, true) ~= nil,
	"/lefthy beacon sound lists the sounds and marks the current one")
lefthy("beacon sound 1")
Advance(0.05)
check(BDB.dingSoundKit == 50111 and SOUNDS[#SOUNDS] == 50111 and #SOUNDS == soundMark + 1, "/lefthy beacon sound 1 picks it and plays it once")
lefthy("beacon sound 1")
Advance(0.05)
check(#SOUNDS == soundMark + 2, "picking the current one again still plays it")
do -- A choice is set by the value the db keeps (LT:SetModuleSetting finds its slider's position). No time passes.
	local updates = soundSlider.uiUpdates
	LT:SetModuleSetting(Beacon, "dingSoundKit", 31578)
	check(BDB.dingSoundKit == 31578 and soundSlider:GetValue() == 4 and soundSlider.uiUpdates == updates + 1,
		"LT:SetModuleSetting takes a choice's value; its slider moves to it")
	LT:SetModuleSetting(Beacon, "dingSoundKit", 12345)
	check(BDB.dingSoundKit == 31578 and soundSlider.uiUpdates == updates + 1, "a value that isn't one of the choices changes nothing")
	LT:SetModuleSetting(Beacon, "dingSoundKit", 50111) -- (back to the default; both play on the next frame)
end

section("Beacon: how many enemies")
do
	anna("S2;;0;260.0;750.0;Goldshire;")
	Advance(1.2)
	for i = 1, 3 do Fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. i) end
	THREAT = { nameplate1 = 3, nameplate2 = 0 } -- two mobs have me on their list, the third doesn't
	mark = #GAMEDATA + 1
	EnterCombat()
	Advance(1.2)
	check(sentTo(11, mark, "C2;")[1] == "C2;2", "in combat: how many enemies are on me, got " .. tostring(sentTo(11, mark, "C2;")[1]))
	Advance(3)
	check(#sentTo(11, mark, "C2;") == 1, "unchanged: nothing more")
	THREAT.nameplate3 = 1
	Advance(1.1)
	check(sentTo(11, mark, "C2;")[2] == "C2;3", "a third one joins")
	THREAT.nameplate1 = SECRET
	Advance(2.2)
	check(#sentTo(11, mark, "C2;") == 2, "threat kept secret: no count")
	Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
	Fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
	Advance(1.1)
	check(sentTo(11, mark, "C2;")[3] == "C2;1", "nameplates gone (dead or out of range): fewer")
	LeaveCombat()
	Advance(3)
	check(#sentTo(11, mark, "C2;") == 3, "out of combat: nothing (the state says the fight is over)")
	Fire("NAME_PLATE_UNIT_REMOVED", "nameplate3")
	THREAT = {}
	mark = #GAMEDATA + 1
	EnterCombat()
	Advance(2.2)
	check(#sentTo(11, mark, "C2;") == 0, "a fight without nameplates: nothing sent")
	LeaveCombat()
	Advance(1.2)

	OpenWorldMap(1429)
	anna("S2;C;0;260.0;750.0;Goldshire;Stitches")
	anna("C2;3")
	Advance(0.6)
	local pin = pinOf(11)
	pin:OnMouseEnter()
	check(tooltipHas("Fighting Stitches and 2 more") and pin.Count.shown and pin.Count.text == "3",
		"her dot: a 3, and the tooltip says it, got " .. table.concat(TOOLTIP.lines, " | "))
	anna("S2;C;0;260.0;750.0;Goldshire;")
	anna("C2;4")
	Advance(0.6)
	check(tooltipHas("In combat with 4 enemies"), "no target: how many")
	anna("C2;1")
	Advance(0.6)
	check(tooltipHas("In combat with 1 enemy"), "one")
	anna("C2;abc")
	Advance(0.6)
	check(peers()[11].mobs == 1, "malformed counts are ignored")
	anna("S2;;0;260.0;750.0;Goldshire;")
	Advance(0.6)
	check(not pin.Count.shown and tooltipHas("Level 20") and not tooltipHas("In combat with 1 enemy"), "fight over: the count goes")
	pin:OnMouseLeave()
	WorldMapFrame:Hide()
end

section("Beacon: level progress")
do
	anna("S2;;0;260.0;750.0;Goldshire;")
	Advance(0.2)
	mark = #GAMEDATA + 1
	XP.current = 3000
	Fire("PLAYER_XP_UPDATE")
	check(#sentTo(11, mark, "X2;") == 0, "nothing sent inside the event handler")
	Advance(2.2)
	check(sentTo(11, mark, "X2;")[1] == "X2;50", "my progress on this level goes to friends, got " .. tostring(sentTo(11, mark, "X2;")[1]))
	XP.current = 3010
	for _ = 1, 10 do Fire("PLAYER_XP_UPDATE"); Advance(0.3) end
	check(#sentTo(11, mark, "X2;") == 1, "only when the whole percent changes")
	XP.current = 3700
	Fire("PLAYER_XP_UPDATE")
	Advance(2.2)
	check(sentTo(11, mark, "X2;")[2] == "X2;61", "61%")
	local hmark = #GAMEDATA + 1
	Advance(5)
	anna("H2")
	Advance(0.15)
	check(sentTo(11, hmark, "X2;")[1] == "X2;61", "a hello is answered with it too")
	B("share"):SetValue(false)
	Advance(0.3)
	check(last(sentTo(11, hmark, "X2;")) == "X2;", "sharing off: friends are told it's not shared")
	B("share"):SetValue(true)
	Advance(0.3)
	XP.current = 1500
	Fire("PLAYER_XP_UPDATE")
	Advance(2.2)

	OpenWorldMap(1429)
	anna("X2;64")
	Advance(0.6)
	local pin = pinOf(11)
	pin:OnMouseEnter()
	check(tooltipHas("Level 20 (64%)"), "her tooltip: level and progress, got " .. table.concat(TOOLTIP.lines, " | "))
	anna("X2;abc")
	Advance(0.6)
	check(tooltipHas("Level 20 (64%)"), "malformed: ignored")
	anna("X2;")
	Advance(0.6)
	check(tooltipHas("Level 20"), "not shared: just the level")
	pin:OnMouseLeave()
	WorldMapFrame:Hide()
end

section("Beacon: friends' health")
do
	-- Hers (estimated on her side), for everyone, not only who watches her stream: beside her level
	-- on her dot's tooltip and in her lines (AFK screen, flights); no line of its own.
	OpenWorldMap(1429)
	Advance(0.6)
	local pin = pinOf(11)
	pin:OnMouseEnter()
	local lines = #TOOLTIP.lines
	anna("O2;v;80")
	Advance(0.6)
	check(tooltipHas("Level 20  |cff66dd66~80% health|r") and #TOOLTIP.lines == lines,
		"her health beside her level, green, no new line, got " .. table.concat(TOOLTIP.lines, " | "))
	anna("O2;v;20")
	Advance(0.6)
	check(tooltipHas("Level 20  |cffff5050~20% health|r"), "low: red")
	anna("O2;v;abc")
	Advance(0.6)
	check(tooltipHas("Level 20  |cffff5050~20% health|r"), "malformed: ignored")
	local peer, friendLines = BB.peers[11], {}
	BB.FriendLines(friendLines, peer, 11)
	check(friendLines[1]:find("~20% health", 1, true) and BB.FriendRows(peer, 11):find("~20% health", 1, true),
		"her lines (AFK screen, flights): beside her level too")
	anna("O2;v;")
	Advance(0.6)
	check(tooltipHas("Level 20") and #TOOLTIP.lines == lines, "not known (or not shared): just the level")
	pin:OnMouseLeave()
	WorldMapFrame:Hide()
	-- Mine, to every friend: when it changes (in steps of 5), at most every 2 s, and with answers.
	STATE.combat, STATE.dead = false, false
	BB.Stream.LifeStart()
	Advance(4.5) -- (no ticks: full)
	local hmark = #GAMEDATA + 1
	EnterCombat()
	Fire("UNIT_COMBAT", "player", "WOUND", "", 300, 1)
	Advance(0.6)
	check(last(sentTo(11, hmark, "O2;v;")) == "O2;v;70" and last(sentTo(12, hmark, "O2;v;")) == "O2;v;70",
		"hit for 300 of 1000: every friend hears ~70%")
	Fire("UNIT_COMBAT", "player", "WOUND", "", 100, 1)
	Advance(0.6)
	check(#sentTo(11, hmark, "O2;v;") == 1, "again at once: not yet (at most every 2 s)")
	Advance(2)
	check(last(sentTo(11, hmark, "O2;v;")) == "O2;v;60", "then the new one")
	hmark = #GAMEDATA + 1
	anna("H2")
	Advance(2)
	check(sentTo(11, hmark, "O2;v;60")[1], "with every answer")
	LeaveCombat()
	Advance(5)
end

section("AFK screen: what friends are doing")
do
	anna("S2;C;0;260.0;750.0;Raven Hill;Stitches")
	anna("C2;3")
	anna("X2;64")
	anna("T2;176;0;Wanted: Hogger;Huge Gnoll Claw: 0/1")
	Advance(0.3)
	afk(true)
	Advance(1.1)
	local text = LefthyToolsAFKFrame.Friends:GetText()
	check(text:find("Anna|r  |cffccccccLevel 20 (64%)|r", 1, true) and text:find("Elwynn Forest - Raven Hill", 1, true)
		and text:find("Fighting Stitches and 2 more", 1, true)
		and text:find("Quest: Wanted: Hogger|r|cffcccccc - Huge Gnoll Claw: 0/1", 1, true),
		"each friend: level and progress, where, whom and how many they fight, their quest, got\n" .. text)
	anna("S2;;0;260.0;750.0;Raven Hill;")
	anna("T2;176;1;Wanted: Hogger;")
	Advance(1.1)
	text = LefthyToolsAFKFrame.Friends:GetText()
	check(not text:find("Fighting", 1, true) and text:find("Quest: Wanted: Hogger|r|cffcccccc - Ready to turn in", 1, true),
		"out of combat: still what they're doing")
	BN_FRIENDS[1][1].isGameAFK = true
	Advance(1.1)
	check(LefthyToolsAFKFrame.Friends:GetText():find("Anna|r |cff999999<AFK>|r", 1, true), "friends who are AFK too")
	BN_FRIENDS[1][1].isGameAFK = false
	afk(false)
	Advance(0.3)
	anna("X2;")
	anna("T2;0;;;")
	Advance(0.3)
end

section("Beacon: friends on top of each other")
do
	local function bob(state) Fire("BN_CHAT_MSG_ADDON", "LTBeacon", state, "WHISPER", 12) end
	PLAYER_POS = { 0.5, 0.5 } -- me: north 500, west 500
	anna("S2;;0;520.0;500.0;Goldshire;")
	bob("S2;;0;520.0;500.0;Goldshire;") -- the same spot, 20 yd north of me
	Advance(1.2)
	OpenWorldMap(1429)
	Advance(0.6)
	local a, b = pinOf(11), pinOf(12)
	check(a and b and math.abs(a.y - b.y) < 1e-9 and math.abs((b.x - a.x) * 1000 - 11.2) < 0.01 and math.abs((a.x + b.x) / 2 - 0.5) < 1e-6,
		"two friends on one spot: their dots sit side by side around it (map: 1 yd = 1 px here), got "
		.. tostring(a and a.x) .. " / " .. tostring(b and b.x))
	a:OnMouseEnter()
	check(TOOLTIP.title == "Anna" and tooltipHas("Bob") and tooltipHas("Level 20"), "hovering either shows both")
	bob("S2;C;0;520.0;500.0;Goldshire;Hogger")
	Advance(0.6)
	check(tooltipHas("Fighting Hogger"), "the open tooltip follows the other one too")
	a:OnMouseLeave()
	b:OnMouseEnter()
	check(TOOLTIP.title == "Bob" and tooltipHas("Anna"), "the hovered one comes first")
	b:OnMouseLeave()
	bob("S2;;0;380.0;500.0;Goldshire;") -- 140 yd apart now
	Advance(0.6)
	check(math.abs(pinOf(11).x - 0.5) < 1e-6 and not pinOf(11).group and not pinOf(12).group, "apart again: exact positions")
	bob("S2;;0;520.0;500.0;Goldshire;")
	Advance(0.6)
	WorldMapFrame:Hide()
	Advance(0.6)
	local mm = BB.GetMinimapPins()
	local _, _, _, ax, ay = mm[11]:GetPoint(1)
	local _, _, _, bx, by = mm[12]:GetPoint(1)
	check(math.abs(bx - ax - 8) < 1e-6 and math.abs(ay - by) < 1e-6 and math.abs((ax + bx) / 2) < 1e-6,
		"on the minimap too, got " .. tostring(ax) .. " / " .. tostring(bx))
	mm[12]._scripts.OnEnter(mm[12])
	check(TOOLTIP.title == "Bob" and tooltipHas("Anna"), "and hovering shows both")
	mm[12]._scripts.OnLeave(mm[12])
	local spreads, spread = 0, BB.Spread
	BB.Spread = function(...) spreads = spreads + 1; return spread(...) end
	for i = 1, 10 do
		PLAYER_POS = { 0.5, 0.5 + i * 0.002 } -- I walk: both dots move on the minimap, but not apart
		Advance(0.05)
	end
	_, _, _, ax, ay = mm[11]:GetPoint(1)
	_, _, _, bx, by = mm[12]:GetPoint(1)
	check(spreads == 0 and math.abs(bx - ax - 8) < 1e-6 and math.abs(ay - by) < 1e-6,
		"while I walk, the spread is reused instead of worked out every frame, got " .. spreads)
	bob("S2;;0;525.0;500.0;Goldshire;") -- Bob steps 5 yd north (3.5 px here): still overlapping
	Advance(1.2)
	_, _, _, ax, ay = mm[11]:GetPoint(1)
	_, _, _, bx, by = mm[12]:GetPoint(1)
	check(spreads >= 1 and math.abs(by - ay) < 1 and math.abs(bx - ax - 8) < 1,
		"one of them moving: worked out again (still side by side, within a pixel), got " .. spreads .. ", " .. (by - ay))
	BB.Spread = spread
	PLAYER_POS = { 0.5, 0.5 }
	Advance(0.6)
end

section("Beacon: showing and offering items")
do
	local function ctrlRight(link, shift, location)
		STATE.ctrl, STATE.shift, MOCK_BUTTON = true, shift == true, "RightButton"
		HandleModifiedItemClick(link, location)
		STATE.ctrl, STATE.shift = false, false
	end
	local function soundsSince(n)
		local list = {}
		for i = n + 1, #SOUNDS do list[#list + 1] = SOUNDS[i] end
		return "," .. table.concat(list, ",") .. ","
	end
	anna("S2;;0;260.0;750.0;Goldshire;")
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;260.0;750.0;Goldshire;", "WHISPER", 12)
	Advance(1.2)
	check(BDB.shareItems == true and B("shareItems") ~= nil, "a setting, on by default")
	mark, pmark = #GAMEDATA + 1, #PRINTED + 1
	local dressups = DRESSUPS
	ctrlRight(ItemLink(1155))
	check(DRESSUPS == dressups + 1, "Blizzard's own handling runs first")
	local emptyOk, emptyErr = pcall(ctrlRight, nil) -- an empty slot: Blizzard passes no link
	check(emptyOk, "Ctrl+right-click on an empty slot: no error, got " .. tostring(emptyErr))
	Advance(0.15)
	check(sentTo(11, mark, "I2;")[1] == "I2;1155::::::::20:::::", "Ctrl+right-click shows the item to my friends, got " .. tostring(sentTo(11, mark, "I2;")[1]))
	check(printedSince(pmark):find("shared " .. ItemLink(1155) .. " with ", 1, true), "and I'm told")
	ctrlRight(ItemLink(1155))
	Advance(0.15)
	check(#sentTo(11, mark, "I2;") == 1 and printedSince(pmark):find("one item every 3 seconds: try again in a moment", 1, true),
		"at most one every 3 s, and I'm told")
	Advance(3)
	-- A link that can't be read: said so, with the link, instead of nothing happening.
	pmark = #PRINTED + 1
	ctrlRight("|cff0070dd|Hitem:abc|h[Odd Staff]|h|r")
	Advance(0.15)
	check(#sentTo(11, mark, "I2;") == 1 and printedSince(pmark):find("can't read this item's link", 1, true)
		and printedSince(pmark):find("||Hitem:abc", 1, true), "an unreadable link: a message with the link, nothing sent")
	-- A crafted item's link carries the crafter's GUID: shown anyway, without it (every build's
	-- message check only takes numbers).
	ctrlRight("|cnIQ3:|Hitem:1155::::::::25:1490:::::::::Player-1234-0ABCDEF0:|h[Rod of the Sleepwalker]|h|r")
	Advance(0.15)
	check(sentTo(11, mark, "I2;")[2] == "I2;1155::::::::25:1490::::::::::",
		"a crafted item: shown, the crafter's GUID left out, got " .. tostring(sentTo(11, mark, "I2;")[2]))
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "I2;1155::::::::25:1490::::::::::", "WHISPER", 12)
	Advance(0.15)
	local craftedShown
	for _, call in pairs(BB.calls) do if call.itemString == "1155::::::::25:1490::::::::::" then craftedShown = call end end
	check(craftedShown, "and a friend receives it")
	Advance(9)
	-- The same without a click: /lefthy beacon show | offer <item>.
	pmark = #PRINTED + 1
	lefthy("beacon show")
	check(printedSince(pmark):find("Shift-click the item into the chat box", 1, true), "/lefthy beacon show without an item: how to use it")
	lefthy("beacon offer " .. ItemLink(19019))
	check(printedSince(pmark):find(ItemLink(19019) .. " is soulbound or can't be traded: it can't be offered", 1, true),
		"/lefthy beacon offer a Bind on Pickup item: refused")
	lefthy("beacon show " .. ItemLink(19019))
	Advance(0.15)
	check(sentTo(11, mark, "I2;")[3] == "I2;19019::::::::20:::::", "/lefthy beacon show <item>: shown, soulbound or not")
	Advance(3)
	mark = #GAMEDATA + 1
	STATE.ctrl, MOCK_BUTTON = true, "LeftButton"
	HandleModifiedItemClick(ItemLink(1155)) -- Ctrl+left-click: the game's preview, nothing else
	STATE.ctrl, MOCK_BUTTON = false, "RightButton"
	HandleModifiedItemClick(ItemLink(1155)) -- no modifier
	Advance(0.15)
	check(#sentTo(11, mark, "I2;") == 0, "Ctrl+left-click and plain clicks don't share")

	-- Any item can be shown; only items that can change hands can be offered.
	Advance(3)
	mark, pmark = #GAMEDATA + 1, #PRINTED + 1
	local function offers() -- offers carry a call id at the end
		local n = 0
		for _, m in ipairs(sentTo(11, mark, "I2;")) do if m:find(";%d+$") then n = n + 1 end end
		return n
	end
	ctrlRight(ItemLink(19019), true) -- offering a chat link to a Bind on Pickup item
	Advance(0.15)
	check(offers() == 0 and printedSince(pmark):find(ItemLink(19019) .. " is soulbound or can't be traded: it can't be offered", 1, true),
		"a Bind on Pickup item (chat link, loot window): not offered, and I'm told why")
	ctrlRight(ItemLink(19019)) -- just showing it
	Advance(0.15)
	check(#sentTo(11, mark, "I2;") == 1 and offers() == 0, "showing it works: any item can be shown")
	Advance(3)
	BAGS[0] = { [2] = 1155 }
	MOCK_FOCUS = ContainerFrameCombinedBags.buttons[2]
	BOUND[2] = true -- worn once: bound now
	ctrlRight(ItemLink(1155), true)
	Advance(0.15)
	check(offers() == 0, "a soulbound item in the bags: not offered")
	BAG_TOOLTIP[2] = { "Rod of the Sleepwalker",
		"You may trade this item with players that were also eligible to loot this item for the next 1 hour 52 min." }
	ctrlRight(ItemLink(1155), true)
	Advance(0.15)
	check(offers() == 1, "soulbound, but its loot trade timer still runs: offered")
	BOUND[2], BAG_TOOLTIP[2] = nil, nil
	Advance(3)
	ctrlRight(ItemLink(1155), true)
	Advance(0.15)
	check(offers() == 2, "Bind on Equip, not bound yet: offered")
	MOCK_FOCUS = CreateFrame("Button")
	MOCK_FOCUS:SetID(16)
	EQUIPPED[16] = 1155
	Advance(3)
	ctrlRight(ItemLink(1155), true)
	Advance(0.15)
	check(offers() == 2, "a worn item: not offered")
	-- With the location Blizzard passes (bags, bank, character frame), the mouse doesn't matter.
	MOCK_FOCUS = nil
	BAGS[6] = { [1] = 1155 } -- a bank bag
	BOUND[1] = true
	ctrlRight(ItemLink(1155), true, ItemLocation:CreateFromBagAndSlot(6, 1))
	Advance(0.15)
	check(offers() == 2, "a soulbound item in the bank: not offered")
	BOUND[1] = nil
	ctrlRight(ItemLink(1155), true, ItemLocation:CreateFromBagAndSlot(6, 1))
	Advance(0.15)
	check(offers() == 3, "not bound yet, in the bank: offered")
	Advance(3)
	ctrlRight(ItemLink(1155), true, ItemLocation:CreateFromEquipmentSlot(16))
	Advance(0.15)
	check(offers() == 3, "worn, clicked on the character frame: not offered")
	MOCK_FOCUS, EQUIPPED, BAGS = nil, {}, { [0] = {} }
	Advance(30) -- nobody answers: the offers run out and fade
	anna("S2;;0;260.0;750.0;Goldshire;")
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;260.0;750.0;Goldshire;", "WHISPER", 12)
	Advance(3)

	pmark = #PRINTED + 1
	local sounds = #SOUNDS
	anna("I2;19019::::::::20:::::")
	check(#PRINTED < pmark, "receiving: nothing inside the event handler")
	Advance(0.15)
	check(printedSince(pmark):find("Anna|r shares " .. ItemLink(19019) .. ".", 1, true), "a chat line with the link")
	local shown
	for _, call in pairs(BB.calls) do if call.frame and call.frame:IsShown() then shown = call.frame end end
	check(shown and shown.Line:GetText():find("^|T%d+:0|t ") and shown.Line:GetText():find("Anna|r shares " .. ItemLink(19019), 1, true)
		and not shown.Need:IsShown() and SOUNDS[#SOUNDS] == 3081 and #SOUNDS == sounds + 1,
		"a notice with the icon and the item (no buttons when just shown) and the whisper sound")
	local boxes = 0
	for _, t in ipairs(shown._textures or {}) do if t.layer == "BACKGROUND" or t.layer == "BORDER" then boxes = boxes + 1 end end
	check(boxes == 0 and not shown.Line:GetText():find("\n", 1, true) and shown:GetHeight() <= 24
		and shown.Line.textScale <= 1.2, "one line of text, not too big, no box behind it")
	shown.Hover._scripts.OnEnter(shown.Hover)
	check(TOOLTIP.shown and TOOLTIP.owner == shown.Hover and TOOLTIP.link == "item:19019::::::::20:::::",
		"hovering the line shows the item's tooltip")
	shown.Hover._scripts.OnLeave(shown.Hover)
	check(not TOOLTIP.shown, "... and moving away hides it")
	local dressed = DRESSUPS
	shown.Hover._scripts.OnClick(shown.Hover)
	STATE.ctrl = true
	shown.Hover._scripts.OnClick(shown.Hover)
	STATE.ctrl = false
	check(DRESSUPS == dressed + 1, "a plain click does nothing, Ctrl-click previews it (the game's item click handling)")
	GAMEPAD_STATE.ui, STATE.ctrl = true, true
	shown.Hover._scripts.OnClick(shown.Hover)
	GAMEPAD_STATE.ui, STATE.ctrl = false, false
	check(DRESSUPS == dressed + 1, "in gamepad mode no dressing room from here (it would taint the gamepad's focus)")
	shown.Hover._scripts.OnEnter(shown.Hover)
	Advance(9)
	check(not shown:IsShown() and not TOOLTIP.shown, "it goes away by itself, its tooltip too if it was still up")
	pmark = #PRINTED + 1
	MOCK_ITEM_UNCACHED = 6948
	anna("I2;6948::::::::20:::::")
	Advance(0.15)
	check(not printedSince(pmark):find("shares", 1, true), "an item the client doesn't know yet: it waits for it")
	MOCK_ITEM_UNCACHED = nil
	for _, callback in ipairs(PENDING_ITEM_LOADS) do callback() end
	PENDING_ITEM_LOADS = {}
	check(printedSince(pmark):find("Anna|r shares " .. ItemLink(6948), 1, true), "... and shows it once it's loaded")
	pmark = #PRINTED + 1
	anna("I2;1179::::::::20:::::")
	anna("I2;abc")
	Advance(0.15)
	check(not printedSince(pmark):find("shares", 1, true), "another one within 3 s and malformed ones are ignored")
	Advance(9)

	-- Offering: Ctrl+Shift+right-click. Both friends need it: a roll.
	mark, pmark, sounds = #GAMEDATA + 1, #PRINTED + 1, #SOUNDS
	ctrlRight(ItemLink(1155), true)
	Advance(0.15)
	local offer = sentTo(11, mark, "I2;")[1]
	local callID = offer and tonumber(offer:match("^I2;1155::::::::20:::::;(%d+)$"))
	check(callID and sentTo(12, mark, "I2;")[1] == offer, "Ctrl+Shift+right-click offers it to everyone, with a call id, got " .. tostring(offer))
	local mine = callID and BB.calls["me:" .. callID]
	check(mine and mine.frame:IsShown() and mine.frame.Line:GetText():find("|t You offer " .. ItemLink(1155), 1, true)
		and mine.frame.Status:GetText():find("Waiting", 1, true),
		"my notice: waiting for their answers")
	anna("N2;" .. callID .. ";1")
	Advance(0.15)
	check(mine.frame.Status:GetText():find("Anna: |cff40ff40Need", 1, true), "answers show up live")
	anna("N2;" .. callID .. ";0") -- she can't change her mind
	local verdictMark = #GAMEDATA + 1
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "N2;" .. callID .. ";1", "WHISPER", 12) -- Bob needs it too
	Advance(0.3)
	local verdict = sentTo(11, verdictMark, "R2;")[1]
	check(verdict and verdict:find("^R2;" .. callID .. ";%a+:%d+,%a+:%d+$") and sentTo(12, verdictMark, "R2;")[1] == verdict,
		"everyone answered: rolled right away, the verdict goes to everyone, got " .. tostring(verdict))
	local winner, top, second = verdict:match("^R2;%d+;(%a+):(%d+),%a+:(%d+)$")
	check(winner == "Anna" or winner == "Bob", "the two who needed it")
	check(tonumber(top) > tonumber(second), "highest first, never a tie")
	check(mine.state == "rolling" and mine.frame.Winner:GetText():find("Rolling", 1, true)
		and soundsSince(sounds):find(",31579,31580,", 1, true), "a drumroll: the bonus roll spinner, numbers whirling")
	Advance(2.6)
	check(mine.state == "done" and #STOPPED_SOUNDS > 0 and soundsSince(sounds):find(",31581,31578,", 1, true),
		"then the spinner stops and a fanfare plays")
	check(mine.frame.Winner:GetText():find(winner .. " wins!", 1, true)
		and printedSince(pmark):find(winner .. " wins " .. ItemLink(1155) .. " with " .. top, 1, true),
		"the winner in big letters, and in chat")
	Advance(9)
	check(not mine.frame, "and after a while it's gone")

	-- A friend's offer: Need / Pass. I need it and win.
	mark = #GAMEDATA + 1
	anna("I2;1179::::::::20:::::;4242")
	Advance(0.15)
	local theirs = BB.calls["11:4242"]
	check(theirs and theirs.frame.Need:IsShown() and theirs.frame.Pass:IsShown() and theirs.frame.Timer:IsShown(),
		"a friend's offer: Need and Pass buttons and a timer")
	theirs.frame.Need:Click()
	Advance(0.15)
	check(sentTo(11, mark, "N2;")[1] == "N2;4242;1" and not theirs.frame.Need:IsShown()
		and theirs.frame.Status:GetText():find("Fingers crossed", 1, true), "Need: my answer goes to her")
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "R2;4242;Bob:99", "WHISPER", 12)
	Advance(0.15)
	check(theirs.state == "open", "a verdict from someone else than the sharer is ignored")
	anna("R2;4242;|cffff0000Lefthy|r:87,Bob:12")
	Advance(0.15)
	check(theirs.state == "rolling", "her verdict: the drumroll here too")
	Advance(2.6)
	check(theirs.frame.Winner:GetText():find("You win!", 1, true) and theirs.frame.Status:GetText():find("Lefthy  87", 1, true)
		and not theirs.frame.Status:GetText():find("ff0000", 1, true), "and I won (names in a verdict cleaned of escape codes)")
	Advance(9)

	-- Only one needs it: no roll. Nobody: nobody.
	anna("I2;6948::::::::20:::::;5151")
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "I2;1179::::::::20:::::;6262", "WHISPER", 12) -- (Bob offers one too)
	Advance(0.15)
	BB.calls["11:5151"].frame.Pass:Click()
	BB.calls["12:6262"].frame.Need:Click()
	anna("R2;5151;Bob:0")
	MY_SURNAME = "Mirewood" -- Battle.net names characters with their surname: so does Bob's verdict
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "R2;6262;Lefthy Mirewood:0", "WHISPER", 12)
	Advance(0.15)
	MY_SURNAME = nil
	local single, bobs = BB.calls["11:5151"], BB.calls["12:6262"]
	check(single.state == "done" and single.frame.Winner:GetText():find("Bob wins!", 1, true), "a single Need: they get it, no roll")
	check(bobs.state == "done" and bobs.frame.Winner:GetText():find("You win!", 1, true),
		"a verdict naming me with my surname: I win, got " .. tostring(bobs.frame.Winner:GetText()))
	Advance(9)
	ctrlRight(ItemLink(1155), true)
	Advance(0.15)
	local open
	for _, call in pairs(BB.calls) do if call.mine and call.state == "open" then open = call end end
	Advance(21)
	check(open and open.state == "done" and open.frame.Status:GetText():find("Nobody needs it.", 1, true),
		"nobody answered within 20 s: nobody needs it")
	Advance(9)

	-- Many long names: the verdict is cut to what friends take (200 bytes), the winner first.
	ctrlRight(ItemLink(1155), true)
	Advance(0.15)
	local big
	for _, call in pairs(BB.calls) do if call.mine and call.state == "open" then big = call end end
	for i = 1, 4 do
		big.recipients[100 + i] = true
		big.answers[100 + i] = { name = ("x"):rep(47) .. i, need = true }
	end
	anna("N2;" .. big.id .. ";1")
	verdictMark = #GAMEDATA + 1
	Advance(21)
	local cut = (sentTo(11, verdictMark, "R2;")[1] or ""):match("^R2;%d+;(.*)$")
	check(cut and #cut <= 200 and #big.result == 5 and cut:find("^" .. big.result[1].name .. ":" .. big.result[1].roll .. ","),
		"too long for friends: cut, the winner first (I still see all five), got " .. tostring(cut and #cut))
	Advance(9)

	-- Four notices at once: three fit. A finished one makes room and lets go of its frame for good.
	anna("I2;1179::::::::20:::::;7001")
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "I2;6948::::::::20:::::", "WHISPER", 12) -- Bob just shows one
	Advance(2.1)
	anna("I2;19019::::::::20:::::;7003")
	Advance(0.15)
	local showOnly, showKey
	for key, call in pairs(BB.calls) do if call.from == 12 and not call.id then showOnly, showKey = call, key end end
	local spareFrame = showOnly and showOnly.frame
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "I2;1155::::::::20:::::;7004", "WHISPER", 12)
	Advance(0.15)
	local fourth, oldest = BB.calls["12:7004"], BB.calls["11:7001"]
	check(spareFrame and fourth and fourth.frame == spareFrame and not showOnly.frame and oldest.frame and oldest.frame:IsShown(),
		"a fourth notice takes the frame of one that's only shown, not of an open offer")
	check(fourth.frame.Line:GetText():find("Bob|r offers " .. ItemLink(1155), 1, true) and fourth.frame.Need:IsShown(),
		"... filled in for the new one (a friend's offer says so)")
	Advance(6.5)
	check(not BB.calls[showKey] and fourth.frame and fourth.frame:IsShown() and fourth.frame.Line:GetText():find(ItemLink(1155), 1, true),
		"the one that gave up its frame runs out without touching it")
	Advance(30)
	check(not next(BB.calls), "all of them run out")

	-- Four open offers: the oldest makes room, and comes back with its buttons once there's room.
	anna("I2;1179::::::::20:::::;8001")
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "I2;6948::::::::20:::::;8002", "WHISPER", 12)
	Advance(2.1)
	anna("I2;19019::::::::20:::::;8003")
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "I2;1155::::::::20:::::;8004", "WHISPER", 12)
	Advance(0.15)
	local pushedOut = BB.calls["11:8001"]
	check(pushedOut and not pushedOut.frame and BB.calls["12:8004"].frame, "the oldest open offer made room")
	anna("R2;8003;") -- nobody needed hers
	Advance(9)
	check(pushedOut.frame and pushedOut.frame:IsShown() and pushedOut.frame.Need:IsShown()
		and pushedOut.frame.Line:GetText():find(ItemLink(1179), 1, true), "once there's room it's back, with Need and Pass")
	Advance(14) -- no verdict from Anna: it runs out
	check(pushedOut.state == "done" and pushedOut.frame and not pushedOut.frame.Need:IsShown() and not pushedOut.frame.Timer:IsShown(),
		"an offer that runs out without a verdict loses its buttons right away")
	Advance(10)
	check(not next(BB.calls), "and all of them go")

	-- Answers to two of my offers in the same moment: both count.
	ctrlRight(ItemLink(1155), true)
	Advance(3.1)
	ctrlRight(ItemLink(6948), true)
	Advance(0.15)
	local myCalls = {}
	for _, call in pairs(BB.calls) do if call.mine then myCalls[#myCalls + 1] = call end end
	check(#myCalls == 2, "two offers of mine")
	anna("N2;" .. myCalls[1].id .. ";1")
	anna("N2;" .. myCalls[2].id .. ";0")
	Advance(0.15)
	check(myCalls[1].answers[11] and myCalls[1].answers[11].need and myCalls[2].answers[11] and not myCalls[2].answers[11].need,
		"Anna answers both at once: both count")
	Advance(30)

	-- A won item's tooltip reminds me until it's handed over: traded or mailed to the winner.
	local owed = LefthyToolsDB.handover
	check(type(owed) == "table", "the reminders are saved")
	wipe(owed)
	lefthy("beacon handover")
	check(PRINTED[#PRINTED]:find("nothing to hand over", 1, true), "/lefthy beacon handover: nothing yet")
	pmark = #PRINTED + 1
	BAGS[0] = { [3] = 6948 }
	ctrlRight(ItemLink(6948), true, ItemLocation:CreateFromBagAndSlot(0, 3)) -- from the bags
	Advance(0.15)
	local giveaway
	for _, call in pairs(BB.calls) do if call.mine and call.state == "open" then giveaway = call end end
	anna("N2;" .. giveaway.id .. ";1")
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "N2;" .. giveaway.id .. ";0", "WHISPER", 12)
	Advance(0.3)
	check(#owed == 1 and owed[1].itemID == 6948 and owed[1].winner == "Anna" and owed[1].guid == "Player-1-11"
		and owed[1].itemGUID == "Item-0-3"
		and printedSince(pmark):find("its tooltip reminds you until you trade or mail it to Anna.", 1, true),
		"Anna won my item: noted (this very copy), and I'm told")
	BAGS = { [0] = {} }
	GameTooltip:SetOwner(UIParent)
	GameTooltip:SetHyperlink("item:6948::::::::20:::::")
	check(tooltipHas("Won by Anna: still to hand over"), "its tooltip says so")
	GameTooltip:SetOwner(UIParent)
	GameTooltip:SetHyperlink("item:1155::::::::20:::::")
	check(not tooltipHas("Won by"), "other items' tooltips don't")
	GameTooltip:Hide()
	-- Traded to Bob: still owed, and no nudge.
	TRADE_PARTNER, PARTY.NPC = "Bob", { guid = "Player-1-12" }
	pmark = #PRINTED + 1
	Fire("TRADE_SHOW")
	TRADE_ITEMS = { ItemLink(6948) }
	Fire("TRADE_PLAYER_ITEM_CHANGED", 1)
	Fire("TRADE_ACCEPT_UPDATE", 1, 1)
	Fire("TRADE_CLOSED")
	Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
	Advance(0.1)
	check(#owed == 1 and not printedSince(pmark):find("put it in", 1, true), "traded to someone else: still owed, no nudge")
	-- Trading with Anna: a nudge; she gets it: gone.
	TRADE_PARTNER, PARTY.NPC, TRADE_ITEMS = "Anna", { guid = "Player-1-11" }, {}
	pmark = #PRINTED + 1
	Fire("TRADE_SHOW")
	check(not printedSince(pmark):find("put it in", 1, true), "nothing printed inside the event handler")
	Advance(0.1)
	check(printedSince(pmark):find("Anna won " .. ItemLink(6948) .. ": put it in the trade.", 1, true), "trading with the winner: a nudge in chat")
	Fire("TRADE_PLAYER_ITEM_CHANGED", 2)
	Fire("TRADE_CLOSED")
	Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
	check(#owed == 1, "a trade without the item: still owed")
	Fire("TRADE_SHOW")
	TRADE_ITEMS = { nil, ItemLink(6948) }
	Fire("TRADE_PLAYER_ITEM_CHANGED", 2)
	Fire("TRADE_ACCEPT_UPDATE", 1, 1)
	Fire("TRADE_CLOSED")
	Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
	Advance(0.1)
	check(#owed == 0 and printedSince(pmark):find(ItemLink(6948) .. " handed over to Anna.", 1, true), "traded to the winner: the reminder is gone")
	-- A partner with a surname and no GUID: still her.
	BB.AddHandover("6948::::::::20:::::", ItemLink(6948), "Anna", nil)
	TRADE_PARTNER, TRADE_SURNAME, PARTY.NPC, TRADE_ITEMS = "Anna", "Smith", nil, {}
	pmark = #PRINTED + 1
	Fire("TRADE_SHOW")
	Advance(0.1)
	check(printedSince(pmark):find("Anna won " .. ItemLink(6948), 1, true), "a trade partner with a surname (no GUID): still matched")
	TRADE_ITEMS = { ItemLink(6948) }
	Fire("TRADE_PLAYER_ITEM_CHANGED", 1)
	Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
	check(#owed == 0, "... and handed over")
	TRADE_SURNAME = nil
	TRADE_PARTNER, PARTY.NPC, TRADE_ITEMS = nil, nil, {}
	-- Mail.
	BB.AddHandover("1179::::::::20:::::", ItemLink(1179), "Bob", "Player-1-12")
	MAIL_ITEMS = { 1179 }
	SendMail("Anna", "hi", "")
	Fire("MAIL_SEND_SUCCESS")
	check(#owed == 1, "mailed to someone else: still owed")
	SendMail("Bob-Realmy", "yours", "")
	Fire("MAIL_FAILED")
	Fire("MAIL_SEND_SUCCESS") -- a later, unrelated mail
	check(#owed == 1, "a mail that failed: still owed")
	SendMail("Bob-Realmy", "yours", "")
	Fire("MAIL_SEND_SUCCESS")
	check(#owed == 0, "mailed to the winner (name with realm): gone")
	BB.AddHandover("1179::::::::20:::::", ItemLink(1179), "Bob", "Player-1-12")
	SendMail("bob", "yours", "")
	Fire("MAIL_SEND_SUCCESS")
	check(#owed == 0, "the name typed in lower case: still them")
	MAIL_ITEMS = {}

	-- Rolled again: only the newest winner keeps it reserved.
	wipe(owed)
	BB.AddHandover("1179::::::::20:::::", ItemLink(1179), "Bob", "Player-1-12", 12)
	pmark = #PRINTED + 1
	BB.AddHandover("1179::::::::20:::::", ItemLink(1179), "Anna", "Player-1-11", 11)
	check(#owed == 1 and owed[1].winner == "Anna" and printedSince(pmark):find(ItemLink(1179) .. " is no longer reserved for Bob.", 1, true),
		"rolled again: only the newest winner, and I'm told who no longer has it")
	GameTooltip:SetOwner(UIParent)
	GameTooltip:SetHyperlink("item:1179::::::::20:::::")
	check(tooltipHas("Won by Anna: still to hand over") and not tooltipHas("Won by Bob: still to hand over"), "its tooltip names only them")
	GameTooltip:Hide()
	-- Two copies of an item, offered from the bags and won by two people: two reservations.
	wipe(owed)
	BAGS[0] = { [3] = 1155, [4] = 1155 }
	pmark = #PRINTED + 1
	BB.AddHandover("1155::::::::20:::::", ItemLink(1155), "Anna", "Player-1-11", 11, "Item-0-3")
	BB.AddHandover("1155::::::::20:::::", ItemLink(1155), "Bob", "Player-1-12", 12, "Item-0-4")
	check(#owed == 2 and not printedSince(pmark):find("no longer reserved", 1, true), "two copies won by two people: both reserved")
	GameTooltip:SetOwner(UIParent)
	GameTooltip:SetBagItem(0, 3)
	check(tooltipHas("Won by Anna: still to hand over") and not tooltipHas("Won by Bob: still to hand over"), "each copy's tooltip names its winner")
	GameTooltip:SetOwner(UIParent)
	GameTooltip:SetHyperlink("item:1155::::::::20:::::")
	check(tooltipHas("Won by Anna: still to hand over") and tooltipHas("Won by Bob: still to hand over"), "a link (no copy known) names both")
	GameTooltip:Hide()
	BB.AddHandover("1155::::::::20:::::", ItemLink(1155), "Bob", "Player-1-12", 12, "Item-0-3")
	check(#owed == 2 and owed[1].winner == "Bob" and owed[2].winner == "Bob" and printedSince(pmark):find("no longer reserved for Anna", 1, true),
		"one copy rolled again: only that one changes hands")
	wipe(owed)
	BAGS = { [0] = {} }

	-- Reserved items: a border in the bags; at a vendor, right-click asks first.
	BB.AddHandover("1179::::::::20:::::", ItemLink(1179), "Bob", "Player-1-12", 12)
	BAGS[0] = { [3] = 1179, [5] = 6948 }
	OpenBags()
	Advance(0.1)
	local bagButtons = ContainerFrameCombinedBags.buttons
	check(bagButtons[3].LefthyToolsReserved and bagButtons[3].LefthyToolsReserved:IsShown() and not bagButtons[5].LefthyToolsReserved
		and not bagButtons[3].LefthyToolsSellGuard, "a reserved item's bag slot gets a border, other slots don't")
	Fire("MERCHANT_SHOW")
	Advance(0.1)
	local guard = bagButtons[3].LefthyToolsSellGuard
	check(guard and guard:IsShown() and guard._passThrough[1] == "LeftButton" and guard._propagateMotion == true
		and not bagButtons[5].LefthyToolsSellGuard, "at a vendor: a guard over the slot, left-clicks and hovering pass through")
	local soundsBefore = #SOUNDS
	guard:Click("RightButton")
	local dlg = LefthyToolsSellReservedDialog
	check(dlg and dlg:IsShown() and dlg.Text:GetText():find(ItemLink(1179) .. " is reserved for Bob: they won it. Sell it anyway?", 1, true)
		and #SOLD == 0 and #SOUNDS == soundsBefore + 1, "right-click: a question (with an alert sound) instead of selling")
	dlg.Keep:Click()
	check(not dlg:IsShown() and #SOLD == 0 and BAGS[0][3] == 1179, "Keep it: nothing sold")
	Advance(3) -- the last share was a moment ago
	STATE.ctrl = true
	MOCK_BUTTON = "RightButton"
	local shares = #sentTo(11, 1, "I2;")
	guard:Click("RightButton")
	STATE.ctrl = false
	Advance(0.15)
	check(not dlg:IsShown() and #sentTo(11, 1, "I2;") == shares + 1, "Ctrl+right-click still shows it to friends, no question")
	Advance(3)
	do
		local dressed = DRESSUPS
		GAMEPAD_STATE.ui, STATE.ctrl, MOCK_BUTTON = true, true, "RightButton"
		guard:Click("RightButton")
		GAMEPAD_STATE.ui, STATE.ctrl = false, false
		Advance(0.15)
		check(not dlg:IsShown() and #sentTo(11, 1, "I2;") == shares + 2 and DRESSUPS == dressed,
			"in gamepad mode too, without the dressing room (it would taint the gamepad's focus)")
	end
	guard:Click("RightButton")
	pmark = #PRINTED + 1
	dlg.Sell:Click()
	Advance(0.1)
	check(SOLD[#SOLD] == 1179 and #owed == 0 and not bagButtons[3].LefthyToolsReserved:IsShown() and not guard:IsShown()
		and printedSince(pmark):find("no longer reserved", 1, true), "Sell anyway: sold, no longer reserved, border and guard gone")
	-- Two copies, one of them reserved: only that one has a border and asks.
	BAGS[0][8], BAGS[0][9] = 1155, 1155
	BB.AddHandover("1155::::::::20:::::", ItemLink(1155), "Anna", "Player-1-11", 11, "Item-0-8")
	Advance(0.1)
	check(bagButtons[8].LefthyToolsReserved:IsShown() and bagButtons[8].LefthyToolsSellGuard:IsShown()
		and not (bagButtons[9].LefthyToolsReserved and bagButtons[9].LefthyToolsReserved:IsShown())
		and not (bagButtons[9].LefthyToolsSellGuard and bagButtons[9].LefthyToolsSellGuard:IsShown()),
		"two copies, one reserved: only that one has a border and asks")
	bagButtons[8].LefthyToolsSellGuard:Click("RightButton")
	dlg.Sell:Click()
	Advance(0.1)
	check(SOLD[#SOLD] == 1155 and BAGS[0][8] == nil and #owed == 0, "Sell anyway on it: sold, reservation over")
	-- Reserved without a known copy (offered from a link), two copies: selling one keeps it.
	BAGS[0][8] = 1155
	BB.AddHandover("1155::::::::20:::::", ItemLink(1155), "Bob", "Player-1-12", 12)
	Advance(0.1)
	check(bagButtons[8].LefthyToolsReserved:IsShown() and bagButtons[9].LefthyToolsReserved:IsShown(), "any copy reserved: both have a border")
	pmark = #PRINTED + 1
	bagButtons[8].LefthyToolsSellGuard:Click("RightButton")
	dlg.Sell:Click()
	Advance(0.1)
	check(BAGS[0][8] == nil and #owed == 1 and printedSince(pmark):find("another one is still reserved for Bob", 1, true),
		"selling one of two: the other is still reserved")
	bagButtons[9].LefthyToolsSellGuard:Click("RightButton")
	dlg.Sell:Click()
	Advance(0.1)
	check(BAGS[0][9] == nil and #owed == 0, "selling the last one: reservation over")
	Fire("MERCHANT_CLOSED")
	-- Gone another way (dragged onto the vendor, a bag addon): how to buy it back.
	BB.AddHandover("6948::::::::20:::::", ItemLink(6948), "Anna", "Player-1-11", 11)
	Fire("MERCHANT_SHOW")
	Advance(0.1)
	pmark = #PRINTED + 1
	BAGS[0][5] = nil
	Fire("BAG_UPDATE_DELAYED")
	Advance(0.1)
	check(printedSince(pmark):find(ItemLink(6948) .. ", which Anna won, is gone: if you sold it, buy it back", 1, true),
		"a reserved item gone at a vendor: a warning while it can be bought back")
	Fire("MERCHANT_CLOSED")
	Advance(0.1)
	-- Won while already at a vendor (nothing reserved when it opened): watched too.
	wipe(owed)
	BAGS[0][5] = 6948
	Fire("MERCHANT_SHOW")
	Advance(0.1)
	BB.AddHandover("6948::::::::20:::::", ItemLink(6948), "Anna", "Player-1-11", 11)
	pmark = #PRINTED + 1
	BAGS[0][5] = nil
	Fire("BAG_UPDATE_DELAYED")
	Advance(0.1)
	check(printedSince(pmark):find("which Anna won, is gone", 1, true), "reserved while at the vendor, then gone: the warning too")
	Fire("MERCHANT_CLOSED")
	Advance(0.1)
	-- In combat no guard is made (pass-through can't be set then).
	wipe(owed)
	BB.AddHandover("1155::::::::20:::::", ItemLink(1155), "Bob", "Player-1-12", 12)
	BAGS[0][7] = 1155
	local blocked = #BLOCKED
	STATE.combat = true
	Fire("MERCHANT_SHOW")
	Advance(0.1)
	check(not bagButtons[7].LefthyToolsSellGuard and #BLOCKED == blocked and bagButtons[7].LefthyToolsReserved:IsShown(),
		"in combat: the border, but no guard (nothing blocked)")
	STATE.combat = false
	Fire("MERCHANT_CLOSED")
	Advance(0.1)
	-- Mail: attaching it fills in the winner.
	wipe(owed)
	BN_FRIENDS[1][1].realmName = "Argent Dawn"
	BB.AddHandover("6948::::::::20:::::", ItemLink(6948), "Anna Brook", "Player-1-11", 11) -- (Battle.net's name: with her surname)
	BN_FRIENDS[1][1].realmName = "Realmy"
	check(owed[1].mailName == "Anna-ArgentDawn", "a winner on another realm: mailed as Name-Realm, her character name without the surname, got "
		.. tostring(owed[1].mailName))
	owed[1].mailName = "Anna Brook" -- (on my realm, as builds before saved it)
	SendMailFrame:Show()
	SendMailNameEditBox:SetText("")
	MAIL_ITEMS = { 6948 }
	pmark = #PRINTED + 1
	Fire("MAIL_SEND_INFO_UPDATE")
	check(SendMailNameEditBox:GetText() == "", "nothing done inside the event handler")
	Advance(0.1)
	check(SendMailNameEditBox:GetText() == "Anna" and printedSince(pmark):find("mail to Anna Brook: they won " .. ItemLink(6948), 1, true),
		"attaching a reserved item fills in its winner's character name (a mail takes no surname), got " .. tostring(SendMailNameEditBox:GetText()))
	SendMailNameEditBox:SetText("anna")
	Fire("MAIL_SEND_INFO_UPDATE")
	Advance(0.1)
	check(not printedSince(pmark):find("heads up", 1, true), "her name in lower case: no warning")
	SendMailNameEditBox:SetText("Bob")
	Fire("MAIL_SEND_INFO_UPDATE")
	Advance(0.1)
	Fire("MAIL_SEND_INFO_UPDATE")
	Advance(0.1)
	local _, warnings = printedSince(pmark):gsub("is reserved for Anna Brook, not Bob", "")
	check(SendMailNameEditBox:GetText() == "Bob" and warnings == 1, "another name typed: kept, with one warning")
	SendMailFrame:Hide()
	MAIL_ITEMS = {}
	wipe(owed)
	BAGS = { [0] = {} }
	ContainerFrameCombinedBags:Hide()
	Advance(0.1)

	BB.AddHandover("1179::::::::20:::::", ItemLink(1179), "Bob", "Player-1-12")
	lefthy("beacon handover")
	check(printedSince(#PRINTED - 1):find(ItemLink(1179) .. " to Bob", 1, true), "/lefthy beacon handover lists what's owed")
	lefthy("beacon handover clear")
	check(#owed == 0, "/lefthy beacon handover clear")
	BB.AddHandover("1179::::::::20:::::", ItemLink(1179), "Bob", "Player-1-12")
	local clearButton = SETTINGS_BUTTONS["Hand-over reminders"]
	check(clearButton and clearButton.text == "Clear", "a Clear button on Beacon's settings page")
	clearButton.onClick()
	check(#owed == 0, "... that forgets them too")
	Advance(10)

	-- An item that only loads after sharing was switched off: no notice.
	pmark = #PRINTED + 1
	MOCK_ITEM_UNCACHED = 6948
	anna("I2;6948::::::::20:::::")
	Advance(0.15)
	B("shareItems"):SetValue(false)
	MOCK_ITEM_UNCACHED = nil
	for _, callback in ipairs(PENDING_ITEM_LOADS) do callback() end
	PENDING_ITEM_LOADS = {}
	check(not printedSince(pmark):find("shares", 1, true) and not next(BB.calls), "an item that loads after sharing was switched off: no notice")
	B("shareItems"):SetValue(true)

	B("shareItems"):SetValue(false)
	pmark = #PRINTED + 1
	anna("I2;1179::::::::20:::::")
	mark = #GAMEDATA + 1
	ctrlRight(ItemLink(1155))
	Advance(0.15)
	check(not printedSince(pmark):find("shares", 1, true) and #sentTo(11, mark, "I2;") == 0
		and printedSince(pmark):find("showing items is off in Beacon's settings", 1, true), "switched off: nothing shown, nothing sent, and I'm told why")
	B("shareItems"):SetValue(true)
end

section("Beacon: LTC (LefthyTools chat) and announcements")
do
	check(BDB.lefthyChat == true and BDB.announcements == true and B("lefthyChat") and B("announcements"),
		"both on by default, each with a checkbox")
	anna("H2")
	Advance(0.2)
	local mark, pmark = #GAMEDATA + 1, #PRINTED + 1
	SlashCmdList.LEFTHYTOOLS_CHAT("anyone up for Deadmines?")
	Advance(0.15)
	check(sentTo(11, mark, "M2;")[1] == "M2;anyone up for Deadmines?", "/l sends the line to my friends")
	check(printedSince(pmark):find("[LTC] [|r", 1, true) and printedSince(pmark):find("Lefthy|r|cffffb84d]: anyone up for Deadmines?", 1, true),
		"... and shows it in my chat window, like guild chat, got " .. printedSince(pmark))
	pmark = #PRINTED + 1
	anna("M2;sure, 5 min")
	Advance(0.15)
	check(printedSince(pmark):find("Anna|r|cffffb84d]: sure, 5 min", 1, true), "a friend's line in my chat window")
	pmark = #PRINTED + 1
	for i = 1, 8 do anna("M2;spam " .. i) end
	Advance(0.15)
	local spam = 0
	for i = pmark, #PRINTED do if PRINTED[i]:find("spam", 1, true) then spam = spam + 1 end end
	check(spam == 4, "a flood: at most 5 lines per 5 seconds from one friend, got " .. spam)
	mark = #GAMEDATA + 1
	Advance(1)
	pmark = #PRINTED + 1
	MY_SURNAME = "Mirewood"
	SlashCmdList.LEFTHYTOOLS_CHAT("|cffff0000red|r; sneaky")
	MY_SURNAME = nil
	Advance(0.15)
	check(sentTo(11, mark, "M2;")[1] == "M2;red sneaky", "colour codes and separators are taken out")
	check(printedSince(pmark):find("Lefthy Mirewood|r|cffffb84d]: red sneaky", 1, true),
		"my own line names me the way friends see me, with my surname, got " .. printedSince(pmark))
	-- Mine stay within what friends take (5 lines per 5 s, an announcement per 3 s), with room to spare.
	Advance(6)
	mark, pmark = #GAMEDATA + 1, #PRINTED + 1
	for i = 1, 6 do SlashCmdList.LEFTHYTOOLS_CHAT("quick " .. i) end
	Advance(0.15)
	check(#sentTo(11, mark, "M2;") == 5 and printedSince(pmark):find("not so fast", 1, true), "at most 5 lines in 6 s, and I'm told")
	Advance(6)
	SlashCmdList.LEFTHYTOOLS_CHAT("quick 7")
	Advance(0.15)
	check(#sentTo(11, mark, "M2;") == 6, "a moment later: on again")
	lefthy("announce one")
	Advance(3.5)
	lefthy("announce two")
	Advance(0.15)
	check(#sentTo(11, mark, "A2;") == 1, "one announcement in 4 s")
	-- Announcements: the middle of the screen.
	Advance(5)
	mark, pmark = #GAMEDATA + 1, #PRINTED + 1
	lefthy('announce "Ony in 10 minutes, meet at the flight master"')
	Advance(0.15)
	check(sentTo(11, mark, "A2;")[1] == "A2;Ony in 10 minutes, meet at the flight master",
		"/lefthy announce: the line goes to my friends (quotes optional), got " .. tostring(sentTo(11, mark, "A2;")[1]))
	local mine, theirs
	for _, call in pairs(BB.calls) do if call.message and call.mine then mine = call end end
	check(mine and mine.frame and mine.frame.Line:GetText():find("|r: Ony in 10 minutes", 1, true), "... and shows in my notices too")
	local soundMark = #SOUNDS
	anna("A2;Boss down, loot time!")
	Advance(0.15)
	for _, call in pairs(BB.calls) do if call.message and not call.mine then theirs = call end end
	check(theirs and theirs.frame:IsShown() and theirs.frame.Line:GetText():find("Anna|r: Boss down, loot time!", 1, true)
		and #SOUNDS > soundMark and not theirs.frame.Need:IsShown() and printedSince(pmark):find("]: Boss down, loot time!", 1, true),
		"a friend's announcement: in the middle of my screen with the whisper sound (and in chat), no buttons")
	Advance(9)
	check(theirs.frame and theirs.frame:IsShown(), "it stays for 10 seconds ...")
	Advance(2.5)
	check(not theirs.frame and not next(BB.calls), "... then fades away")
	B("announcements"):SetValue(false)
	B("lefthyChat"):SetValue(false)
	mark, pmark = #GAMEDATA + 1, #PRINTED + 1
	anna("A2;hello?")
	anna("M2;hello??")
	lefthy("announce hi")
	SlashCmdList.LEFTHYTOOLS_CHAT("hi")
	Advance(0.15)
	check(not printedSince(pmark):find("hello?", 1, true) and not next(BB.calls) and #sentTo(11, mark, "A2;") == 0
		and #sentTo(11, mark, "M2;") == 0 and printedSince(pmark):find("announcements are off", 1, true)
		and printedSince(pmark):find("LTC is off", 1, true), "switched off: nothing shown or sent, and I'm told why")
	B("announcements"):SetValue(true)
	B("lefthyChat"):SetValue(true)
	mark = #GAMEDATA + 1
	SlashCmdList.LEFTHYTOOLS_ANNOUNCE("pull in 5")
	Advance(0.15)
	check(sentTo(11, mark, "A2;")[1] == "A2;pull in 5", "/la: announcing the short way")
	-- Item links: they travel as their numbers and each client builds the link again.
	local chatPeers = BB.module:GetPeers()
	local annaWas = chatPeers[11].version
	chatPeers[11].version = "0.5.0-21-g51edb8a" -- (a build that knows every link token)
	mark, pmark = #GAMEDATA + 1, #PRINTED + 1
	SlashCmdList.LEFTHYTOOLS_CHAT("look: " .. ItemLink(1155) .. " and |cffffff00|Hquest:176:10|h[Wanted: Hogger]|h|r")
	Advance(0.15)
	check(sentTo(11, mark, "M2;")[1] == "M2;look: {item:1155::::::::20} and {quest:176:10[Wanted: Hogger]ffff00}",
		"an item link goes as its numbers, a quest link as its data, text and colour, got " .. tostring(sentTo(11, mark, "M2;")[1]))
	check(printedSince(pmark):find("]: look: " .. ItemLink(1155) .. " and |cffffff00|Hquest:176:10|h[Wanted: Hogger]|h|r", 1, true),
		"my own line shows both links, got " .. printedSince(pmark))
	-- Professions (and spells, achievements, ...): clickable on the other side too.
	Advance(1.1)
	mark, pmark = #GAMEDATA + 1, #PRINTED + 1
	SlashCmdList.LEFTHYTOOLS_CHAT("my |cffffd000|Htrade:Player-1-0000ABCD:3908:197|h[Tailoring]|h|r, not |cff00ff00|Hgarrmission:12|h[Mission]|h|r")
	Advance(0.15)
	check(sentTo(11, mark, "M2;")[1] == "M2;my {trade:Player-1-0000ABCD:3908:197[Tailoring]ffd000}, not [Mission]",
		"a profession link goes as its data, text and colour; a kind not on the list as its text, got " .. tostring(sentTo(11, mark, "M2;")[1]))
	check(printedSince(pmark):find("my |cffffd000|Htrade:Player-1-0000ABCD:3908:197|h[Tailoring]|h|r, not [Mission]", 1, true),
		"my own line: the profession as a link, got " .. printedSince(pmark))
	-- A map pin (Shift-click on the pin): its icon goes, each client puts its own back.
	Advance(1.1)
	mark, pmark = #GAMEDATA + 1, #PRINTED + 1
	SlashCmdList.LEFTHYTOOLS_CHAT("here |cffffff00|Hworldmap:1429:4924:5568|h[|A:Waypoint-MapPin-ChatIcon:13:13:0:0|a Map Pin Location]|h|r")
	Advance(0.15)
	check(sentTo(11, mark, "M2;")[1] == "M2;here {worldmap:1429:4924:5568[Map Pin Location]ffff00}",
		"a map pin goes as its map, spot and text, got " .. tostring(sentTo(11, mark, "M2;")[1]))
	check(printedSince(pmark):find("here |cffffff00|Hworldmap:1429:4924:5568|h[|A:Waypoint-MapPin-ChatIcon:13:13:0:0|a Map Pin Location]|h|r", 1, true),
		"and comes back as a clickable map pin with its icon, got " .. printedSince(pmark))
	-- Friends on older builds get what theirs understands: never a token it would show as text.
	if chatPeers[12] then
		local line = "|cffffd000|Htrade:Player-1-0000ABCD:3908:197|h[Tailoring]|h|r " .. ItemLink(1155)
			.. " |cffffff00|Hworldmap:1429:4924:5568|h[|A:Waypoint-MapPin-ChatIcon:13:13:0:0|a Map Pin Location]|h|r"
		local bobWas = chatPeers[12].version
		for _, case in ipairs({
			{ "0.5.0-15-g4322f60", "M2;{trade:Player-1-0000ABCD:3908:197[Tailoring]} {item:1155::::::::20} [Map Pin Location]",
				"0.5.0-15: its kinds as tokens without colour, a map pin as text" },
			{ "0.5.0-12-gbb4062c", "M2;[Tailoring] {item:1155::::::::20} [Map Pin Location]", "0.5.0-10 to -14: items only" },
			{ "0.5.0-9-gda764bc", "M2;[Tailoring] [Rod of the Sleepwalker] [Map Pin Location]", "older: every link as its text" },
			{ nil, "M2;[Tailoring] [Rod of the Sleepwalker] [Map Pin Location]", "version not known yet: text too" },
			{ "0.5.0-g1a2b3c4", "M2;{trade:Player-1-0000ABCD:3908:197[Tailoring]ffd000} {item:1155::::::::20} {worldmap:1429:4924:5568[Map Pin Location]ffff00}",
				"commit count unknown (the updater couldn't ask GitHub): a download of the latest, the full line" },
			{ "0.4.2-g1a2b3c4", "M2;[Tailoring] [Rod of the Sleepwalker] [Map Pin Location]", "... but not on an older base" },
		}) do
			chatPeers[12].version = case[1]
			Advance(1.1)
			mark = #GAMEDATA + 1
			SlashCmdList.LEFTHYTOOLS_CHAT(line)
			Advance(0.15)
			check(sentTo(12, mark, "M2;")[1] == case[2], "Bob on " .. tostring(case[1]) .. ": " .. case[3] .. ", got " .. tostring(sentTo(12, mark, "M2;")[1]))
			check(sentTo(11, mark, "M2;")[1]:find("{trade:Player-1-0000ABCD:3908:197[Tailoring]ffd000}", 1, true), "... Anna, on a new build, gets the full line")
		end
		chatPeers[12].version = bobWas
	end
	chatPeers[11].version = annaWas
	pmark = #PRINTED + 1
	anna("M2;{trade:Player-1-0000EEEE:2259:171[Alchemy]} and {spell:133:0[Fireball]} {garrmission:12[x]} {spell:133 0[y]}")
	Advance(0.15)
	local got = printedSince(pmark)
	check(got:find("|cffffd000|Htrade:Player-1-0000EEEE:2259:171|h[Alchemy]|h|r and |cff71d5ff|Hspell:133:0|h[Fireball]|h|r", 1, true)
		and got:find("{garrmission:12[x]} {spell:133 0[y]}", 1, true),
		"a friend's profession and spell links are clickable; other kinds and broken data stay plain text, got " .. got)
	Advance(0.6)
	pmark = #PRINTED + 1
	MOCK_ITEM_UNCACHED = 19019 -- not in my item cache yet
	anna("M2;need {item:19019::::::::20}?")
	Advance(0.15)
	anna("M2;anyone?")
	Advance(0.15)
	check(not printedSince(pmark):find("need", 1, true) and not printedSince(pmark):find("anyone", 1, true),
		"an item I don't have cached: the line waits for it, and her next line behind it")
	MOCK_ITEM_UNCACHED = nil
	for _, callback in ipairs(PENDING_ITEM_LOADS) do callback() end
	PENDING_ITEM_LOADS = {}
	local shownAll = printedSince(pmark)
	local needAt, anyoneAt = shownAll:find("Anna|r|cffffb84d]: need " .. ItemLink(19019) .. "?", 1, true), shownAll:find("anyone?", 1, true)
	check(needAt and anyoneAt and needAt < anyoneAt,
		"... and comes with a real link once it's loaded, then the next one: in the order she wrote them, got " .. shownAll)
	pmark = #PRINTED + 1
	MOCK_ITEM_UNCACHED = 19019
	anna("M2;{item:19019::::::::20} never loads")
	Advance(2.5)
	check(not printedSince(pmark):find("never loads", 1, true), "an item that takes long: waited for ...")
	Advance(0.7)
	check(printedSince(pmark):find("]: [?] never loads", 1, true), "... 3 seconds at most, then the line comes without it")
	MOCK_ITEM_UNCACHED, PENDING_ITEM_LOADS = nil, {}
	-- Sticky /l (/ltc): the chat box stays on LTC, like /g, until another chat type.
	local box, header = ChatFrame1EditBox, ChatFrame1EditBoxHeader
	Advance(6) -- (my last chat lines out of the way: 5 per 6 s)
	mark = #GAMEDATA + 1
	TypeChat("/l first line")
	Advance(0.6)
	check(sentTo(11, mark, "M2;")[1] == "M2;first line", "/l in the chat box: sent")
	box:UpdateHeader() -- the box opens again
	check(header:GetText() == "LTC: " and header.color[2] == 0.72 and box._inset > 15,
		"the box stays on LTC, and its header says so, got " .. tostring(header:GetText()))
	local said = #SENT_CHAT
	TypeChat("second line, no /l")
	Advance(0.6)
	check(sentTo(11, mark, "M2;")[2] == "M2;second line, no /l" and #SENT_CHAT == said and box._history == "second line, no /l",
		"a plain line goes to LTC, not to /say (and into the box's history)")
	TypeChat("/w Bob psst")
	check(SENT_CHAT[#SENT_CHAT].type == "WHISPER", "a whisper goes out as a whisper")
	TypeChat("third")
	Advance(0.6)
	check(sentTo(11, mark, "M2;")[3] == "M2;third", "... and LTC stays (whispers aren't sticky)")
	TypeChat("/g hi guild")
	check(SENT_CHAT[#SENT_CHAT].type == "GUILD" and SENT_CHAT[#SENT_CHAT].text == "hi guild", "/g: to the guild")
	box:UpdateHeader()
	TypeChat("guild again")
	check(header:GetText() == "GUILD: " and SENT_CHAT[#SENT_CHAT].type == "GUILD" and #sentTo(11, mark, "M2;") == 3,
		"another sticky chat type ends LTC mode, as /p after /g does")
	TypeChatSpace("/l ")
	check(box:GetText() == "" and header:GetText() == "LTC: ", "typing /l and a space switches the box at once, like /g")
	TypeChat("from guild mode")
	Advance(0.6)
	check(sentTo(11, mark, "M2;")[4] == "M2;from guild mode", "... and the line goes to LTC")
	TypeChat("/s back to say")
	check(SENT_CHAT[#SENT_CHAT].type == "SAY" and SENT_CHAT[#SENT_CHAT].text == "back to say", "/s: back to say")
	TypeChatSpace("/ltc ")
	check(header:GetText() == "LTC: ", "/ltc is /l too: typing it and a space switches the box")
	TypeChat("/ltc via ltc")
	Advance(0.6)
	check(sentTo(11, mark, "M2;")[5] == "M2;via ltc", "... and /ltc <text> sends")
	TypeChat("/s back to say")
	-- A soft tick when a friend writes: once for a burst, not for my own lines, a setting.
	local ticks = #SOUNDS
	anna("M2;one")
	anna("M2;two")
	Advance(0.15)
	SlashCmdList.LEFTHYTOOLS_CHAT("mine")
	Advance(0.15)
	local soft = 0
	for i = ticks + 1, #SOUNDS do if SOUNDS[i] == 826 then soft = soft + 1 end end
	check(BDB.lefthyChatSound == true and B("lefthyChatSound") and soft == 1,
		"a friend's lines: one soft tick for the burst, none for mine (a setting, on), got " .. soft)
	B("lefthyChatSound"):SetValue(false)
	Advance(2)
	ticks = #SOUNDS
	anna("M2;three")
	Advance(0.15)
	check(#SOUNDS == ticks, "switched off: silent")
	B("lefthyChatSound"):SetValue(true)
	-- While I'm AFK the notices are hidden with the interface: the AFK screen lists them.
	Advance(3.5)
	afk(true)
	Advance(1.1)
	anna("I2;1179::::::::20:::::")
	Advance(2.1)
	anna("I2;6948::::::::20:::::;7171")
	anna("M2;brb, getting coffee")
	anna("A2;Raid in 10!")
	anna("M2;" .. ("x"):rep(85) .. "äyyyyyyyyyy") -- (a long line, cut at 87 bytes: right after the ä)
	Advance(1.1)
	local info = LefthyToolsAFKFrame.Info:GetText()
	check(LefthyToolsAFKFrame:IsShown() and info:find("While you were away", 1, true) and info:find("Anna|r shares", 1, true)
		and info:find("Anna|r offers", 1, true) and info:find("[LTC]|r ", 1, true) and info:find("|r: brb, getting coffee", 1, true)
		and info:find("|r: |cffffd200Raid in 10!", 1, true),
		"AFK: items shown and offered, LTC lines and announcements are listed, got\n" .. info)
	check(info:find("|r: " .. ("x"):rep(85) .. "ä...", 1, true), "a long line is cut on a whole letter, and one that fits whole stays")
	afk(false)
	Advance(0.3)
	BB.calls["11:7171"].frame.Pass:Click() -- back: the offer's buttons are there
	Advance(0.2)
end

section("Beacon: error reports")
do
	check(BDB.sendReports == true and BDB.collectReports == false and B("sendReports") and B("collectReports")
		and SETTINGS_BUTTONS["Friends' error reports"], "sending on, collecting off, by default; a button for the collected ones")
	wipe(LefthyToolsDB.reportsOut or {})
	local function bobAlive() -- (friends silent for over a minute are forgotten)
		Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;;0;260.0;750.0;Goldshire;", "WHISPER", 12)
		anna("S2;;0;260.0;750.0;Goldshire;")
	end
	Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "H2", "WHISPER", 12)
	Advance(1.2)
	-- Anna's profession link, clicked: nothing opens, the game says why; that's a report by itself.
	SetItemRef("trade:Player-1-11:2259:171", "[Alchemy]", "LeftButton")
	Fire("UI_ERROR_MESSAGE", 51, "That player is on another realm.")
	Fire("UI_ERROR_MESSAGE", 52, ("x"):rep(79) .. "äz") -- (cut at 80 bytes: in the middle of the ä)
	local realTradeSkill = C_TradeSkillUI
	C_TradeSkillUI = { IsTradeSkillLinked = function() return true end, GetAllRecipeIDs = function() return { 1, 2, 3 } end,
		GetBaseProfessionInfo = function() return { professionName = "Alchemy" } end, IsTradeSkillReady = function() return true end }
	Fire("TRADE_SKILL_LIST_UPDATE")
	C_TradeSkillUI = realTradeSkill
	Advance(3.1)
	check(#LefthyToolsDB.reportsOut == 1, "a profession link that opened nothing: kept as a report")
	-- Nobody collects: a hand-written report waits too.
	pmark = #PRINTED + 1
	lefthy("report the profession link does nothing")
	check(printedSince(pmark):find("report kept", 1, true) and #LefthyToolsDB.reportsOut == 2, "nobody collects: the reports wait")
	mark, pmark = #GAMEDATA + 1, #PRINTED + 1
	anna("Y2;1")
	Advance(3)
	local byID = {}
	for _, p in ipairs(sentTo(11, mark, "Z2;")) do
		local id, n, text = p:match("^Z2;(%d+);(%d+);%d+;(.*)$")
		byID[id] = byID[id] or {}
		byID[id][tonumber(n)] = text
	end
	local texts = {}
	for _, list in pairs(byID) do texts[#texts + 1] = table.concat(list) end
	table.sort(texts)
	check(#texts == 2 and #LefthyToolsDB.reportsOut == 0 and printedSince(pmark):find("2 report(s) sent to Anna", 1, true),
		"Anna collects: both go to her, in parts, and I'm told")
	check(#sentTo(12, mark, "Z2;") == 0, "only to friends who collect")
	local linkReport, handReport = texts[1], texts[2] -- ("Profession link: ..." sorts before "Report: ...")
	check(linkReport:find("^Profession link: LefthyTools ") and linkReport:find("Clicked trade:Player-1-11:2259:171 at ", 1, true)
		and linkReport:find(" -> nothing opened^", 1, true)
		and linkReport:find("their server id 1, mine 1 - this client doesn't know them - Beacon friend Anna on Realmy, Alliance", 1, true)
		and linkReport:find("Me: Realmy, Alliance", 1, true)
		and linkReport:find("UI_ERROR_MESSAGE: That player is on another realm.", 1, true)
		and linkReport:find("TRADE_SKILL_LIST_UPDATE (linked true, recipes 3, profession Alchemy, ready true, window not loaded)", 1, true),
		"the profession link report: the linker's server, whether I know them, their realm and faction, mine, what the game said, got " .. linkReport)
	check(linkReport:find("UI_ERROR_MESSAGE: " .. ("x"):rep(79) .. " / ", 1, true), "what the game said is cut on a whole letter")
	check(handReport:find("What happened: the profession link does nothing", 1, true) and handReport:find(", Realmy, Alliance, ", 1, true)
		and handReport:find("trade:Player-1-11:2259:171 -> nothing opened", 1, true) and handReport:find("linker: their server id 1", 1, true)
		and handReport:find("^", 1, true) and not handReport:find("\n", 1, true),
		"the hand-written one: my words, build, realm, faction and the link I clicked; lines as ^")
	mark = #GAMEDATA + 1
	KNOWN_PLAYERS["Player-1-11"] = { "Anna", "" }
	SetItemRef("trade:Player-1-11:2259:171", "[Alchemy]", "LeftButton")
	Advance(5.5)
	check(#sentTo(11, mark, "Z2;") == 0 and #LefthyToolsDB.reportsOut == 0, "a second one this session: no second report")
	KNOWN_PLAYERS = {}
	bobAlive()
	Advance(0.3)
	-- /lefthy beacon status: realm and faction of every friend and mine, to compare.
	pmark = #PRINTED + 1
	lefthy("beacon status")
	check(printedSince(pmark):find("Anna (Realmy, Alliance) - ", 1, true) and printedSince(pmark):find("you (Realmy, Alliance), LefthyTools ", 1, true),
		"status: each friend's realm and faction, and mine")
	-- A link other than an item, to a friend on a build from before link tokens: I'm told, once.
	local peerList = BB.module:GetPeers()
	local annaVersion, bobVersion = peerList[11].version, peerList[12] and peerList[12].version
	peerList[11].version = "0.5.0-20-g99df530"
	if peerList[12] then peerList[12].version = "0.5.0-14-g5ae6ba6" end
	Advance(1)
	pmark = #PRINTED + 1
	SlashCmdList.LEFTHYTOOLS_CHAT("my |cffffd000|Htrade:Player-1-0:2259:171|h[Alchemy]|h|r")
	Advance(0.6)
	check(peerList[12] and printedSince(pmark):find("Bob has an older LefthyTools", 1, true) and not printedSince(pmark):find("Anna has", 1, true),
		"a friend on an older build: named (links reach them as text), got " .. printedSince(pmark))
	pmark = #PRINTED + 1
	SlashCmdList.LEFTHYTOOLS_CHAT("again |cffffd000|Htrade:Player-1-0:2259:171|h[Alchemy]|h|r")
	Advance(0.6)
	check(not printedSince(pmark):find("older LefthyTools", 1, true), "only once")
	if peerList[12] then
		for _, case in ipairs({ { nil, "a friend whose version hasn't come yet: not called old" },
			{ "0.5.0-g5ae6ba6", "nor one whose commit count is unknown" } }) do
			peerList[12].version = case[1]
			pmark = #PRINTED + 1
			SlashCmdList.LEFTHYTOOLS_CHAT("and |cffffd000|Htrade:Player-1-0:2259:171|h[Alchemy]|h|r")
			Advance(0.6)
			check(not printedSince(pmark):find("older LefthyTools", 1, true), case[2])
		end
	end
	peerList[11].version = annaVersion
	if peerList[12] then peerList[12].version = bobVersion end
	-- An error goes by itself, once per session.
	mark = #GAMEDATA + 1
	LT.Errors.Add("error", "Interface/AddOns/LefthyTools/Core/Core.lua:9: something broke", "the stack")
	LT.Errors.Add("error", "Interface/AddOns/LefthyTools/Core/Core.lua:9: something broke", "the stack")
	Advance(3)
	local first = sentTo(11, mark, "Z2;")[1] or ""
	check(first:find(";1;%d+;Error: LefthyTools ") and #sentTo(11, mark, "Z2;") <= 3,
		"a LefthyTools error goes to her by itself, once, got " .. first)
	B("sendReports"):SetValue(false)
	mark = #GAMEDATA + 1
	LT.Errors.Add("error", "Interface/AddOns/LefthyTools/Core/Core.lua:10: another one", "")
	Advance(3)
	check(#sentTo(11, mark, "Z2;") == 0, "sending off: errors stay here")
	B("sendReports"):SetValue(true)
	LT.Errors.Clear()
	-- A backlog goes over a few minutes, each report whole: friends take 60 parts a minute.
	local function minute()
		for _ = 1, 3 do
			Advance(22)
			bobAlive()
		end
	end
	minute()
	mark, pmark = #GAMEDATA + 1, #PRINTED + 1
	for i = 1, 6 do lefthy("report " .. ("a long story, number " .. i .. ". "):rep(150)) end
	check(#LefthyToolsDB.reportsOut == 6, "queued, but kept (a /reload now) until their last part has gone")
	Advance(5) -- (the queue lets 10 a second go)
	check(#sentTo(11, mark, "Z2;") == 32 and #LefthyToolsDB.reportsOut == 4, "six long reports (16 parts each): two go now, got "
		.. #sentTo(11, mark, "Z2;") .. " parts")
	pmark = #PRINTED + 1
	minute()
	check(#sentTo(11, mark, "Z2;") == 64 and #LefthyToolsDB.reportsOut == 2
		and printedSince(pmark):find("2 report(s) sent to Anna (they collect LefthyTools error reports), 2 more in a moment.", 1, true),
		"two more a minute later, and I'm told more are coming")
	minute()
	local parts = sentTo(11, mark, "Z2;")
	check(#parts == 96 and #LefthyToolsDB.reportsOut == 0 and parts[96]:find("^Z2;%d+;16;16;"), "and the last two: each one whole")
	anna("Y2;0")

	-- Collecting: friends are told, and their reports arrive whole.
	bobAlive()
	Advance(0.3)
	mark = #GAMEDATA + 1
	B("collectReports"):SetValue(true)
	Advance(0.5)
	check(sentTo(11, mark, "Y2;1")[1] and sentTo(12, mark, "Y2;1")[1], "switched on: my friends are told I collect")
	pmark = #PRINTED + 1
	anna("Z2;7;2;2; and more")
	anna("Z2;7;1;2;Error, |cffff0000LefthyTools|r 0.5.0^line two")
	Advance(0.3)
	local reports = LefthyToolsDB.friendReports
	check(reports[#reports].from == "Anna" and reports[#reports].text == "Error, cffff0000LefthyToolsr 0.5.0\nline two and more"
		and printedSince(pmark):find("Anna sent a LefthyTools error report: /lefthy reports shows it.", 1, true),
		"a friend's report, put together (parts in any order, no escape codes), and a chat line")
	anna("Z2;8;1;3;first part")
	-- Meanwhile one of mine to her can't go for minutes (the server holds everything back): it waits
	-- in the queue, and isn't queued again on top of itself.
	anna("Y2;1")
	MOCK_SEND_RESULT = 3
	local heldMark = #PRINTED + 1
	lefthy("report stuck behind the server")
	for i = 1, 5 do
		if i < 5 then
			Advance(25)
		else -- (the same 25 s: let go after 2 minutes and a bit, when a report not gone yet would be sent again)
			Advance(22)
			MOCK_SEND_RESULT = nil
			Advance(3)
		end
		bobAlive()
	end
	local _, sendings = printedSince(heldMark):gsub("report%(s%) sent to Anna", "")
	check(sendings == 1, "a report held up for minutes is queued once, not again on top, got " .. sendings)
	check(reports[#reports].text == "first part[part 2 of 3 missing][part 3 of 3 missing]", "parts that never came: kept with a note")
	lefthy("reports")
	check(LefthyToolsReportsFrame:IsShown() and BB.ReportsText():find("from Anna", 1, true)
		and BB.ReportsText():find("line two and more", 1, true), "/lefthy reports: all of them, ready to copy")
	LefthyToolsReportsFrame:Hide()
	mark = #GAMEDATA + 1
	B("collectReports"):SetValue(false)
	Advance(0.5)
	check(sentTo(11, mark, "Y2;0")[1], "switched off: told too")
	local count = #reports
	anna("Z2;9;1;1;ignored")
	Advance(0.3)
	check(#reports == count, "not collecting: friends' reports are ignored")
	check(#LefthyToolsDB.reportsOut == 0, "the held-up report went once the server let it")
	anna("Y2;0")
	wipe(reports)
end

section("Beacon: leaving")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "Q2", "WHISPER", 12)
Advance(0.15)
check(not peers()[12] and peers()[11], "a friend switching Beacon off (Q2) is forgotten")
-- A reserved item at a vendor, then Beacon goes off (below).
local owedList = LefthyToolsDB.handover
BB.AddHandover("1155::::::::20:::::", ItemLink(1155), "Bob", "Player-1-12", 12)
BAGS[0] = { [3] = 1155 }
OpenBags()
Fire("MERCHANT_SHOW")
Advance(0.1)
local reservedButton = ContainerFrameCombinedBags.buttons[3]
check(reservedButton.LefthyToolsReserved:IsShown() and reservedButton.LefthyToolsSellGuard:IsShown(), "a reserved item at a vendor, Beacon on")
mark = #GAMEDATA + 1
MOCK_SEND_RESULT = 3 -- the server is throttling right now
local mapProviders = {} -- (Beacon's and others' on the world map)
for p in pairs(WorldMapFrame.providers) do mapProviders[p] = true end
lefthy("disable beacon")
check(#GameDataTo(11, mark) == 0, "switching off sends nothing inside the settings callback")
Advance(1)
check(#GameDataTo(11, mark) == 0, "throttled: the goodbye waits")
MOCK_SEND_RESULT = nil
Advance(3)
check(GameDataTo(11, mark)[1] == "Q2", "... and then tells friends (through the rate limiter, not lost)")
local providersLeft, providersGone = 0, 0
for p in pairs(mapProviders) do
	if WorldMapFrame.providers[p] then providersLeft = providersLeft + 1 else providersGone = providersGone + 1 end
end
check(providersGone == 2 and providersLeft == 1 and next(BB.GetMinimapPins()) == nil,
	"and removes the dots from both maps (its two map providers go, the quest map's stays)")
check(not reservedButton.LefthyToolsReserved:IsShown() and not reservedButton.LefthyToolsSellGuard:IsShown(),
	"and the reserved item's border and vendor question")
pmark = #PRINTED + 1
TRADE_PARTNER, PARTY.NPC = "Bob", { guid = "Player-1-12" }
Fire("TRADE_SHOW")
SendMailFrame:Show()
SendMailNameEditBox:SetText("")
MAIL_ITEMS = { 1155 }
Fire("MAIL_SEND_INFO_UPDATE")
BAGS[0][3] = nil
Fire("BAG_UPDATE_DELAYED")
Advance(0.1)
check(printedSince(pmark) == "" and SendMailNameEditBox:GetText() == "", "while off: no trade nudge, no mail help, no vendor warning, got " .. printedSince(pmark))
BAGS[0][3] = 1155
SendMailFrame:Hide()
MAIL_ITEMS, TRADE_PARTNER, PARTY.NPC = {}, nil, nil
mark = #GAMEDATA + 1
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "H2", "WHISPER", 11)
Advance(5)
check(#GameDataTo(11, mark) == 0, "while off: no answers, no positions")
local seenNewer = LT.newerVersion
LT.newerVersion = nil
check(updateStatus():find("Unknown (Beacon is off)", 1, true), "update status with Beacon off: unknown")
LT.newerVersion = seenNewer
do -- Beacon's /lefthy words while it's off: they answer as they always did (no time passes here).
	pmark = #PRINTED + 1
	lefthy("announce hello")
	lefthy("stream watch anna")
	check(printedSince(pmark):find("Beacon is off: /lefthy enable beacon.", 1, true)
		and printedSince(pmark):find("no friend called anna online with LefthyTools.", 1, true),
		"Beacon off: /lefthy announce and /lefthy stream say why nothing happens, got " .. printedSince(pmark))
	lefthy("reports")
	check(LefthyToolsReportsFrame:IsShown(), "... and /lefthy reports still shows the collected ones")
	LefthyToolsReportsFrame:Hide()
end
lefthy("enable beacon")
Advance(0.15)
check(next(WorldMapFrame.providers) ~= nil, "on again: back on the map")
check(reservedButton.LefthyToolsReserved:IsShown() and reservedButton.LefthyToolsSellGuard:IsShown(),
	"and the reserved item's border and vendor question")
Fire("MERCHANT_CLOSED")
wipe(owedList)
BAGS = { [0] = {} }
CloseBags()
Advance(0.1)

section("Beacon: a hook that fails doesn't stop the tick")
do
	local health, calls, pings, reports, minimap = BB.StreamHealthTick, BB.UpdateCalls, BB.UpdatePings, BB.TickReports, BB.UpdateMinimap
	local ticks, healthCalls, reportTicks, minimapCalls = 0, 0, 0, 0
	BB.StreamHealthTick = function() healthCalls = healthCalls + 1; error("a broken health tick") end -- (before sending)
	BB.UpdateCalls = function(now) ticks = ticks + 1; return calls(now) end
	BB.UpdatePings = function() error("broken pings") end
	BB.TickReports = function(now) reportTicks = reportTicks + 1; return reports(now) end -- (after the pings)
	BB.UpdateMinimap = function() minimapCalls = minimapCalls + 1; error("a broken minimap") end -- (every frame)
	local reported, stop = catchErrors()
	mark = #GAMEDATA + 1
	anna("H2")
	Advance(3)
	stop()
	BB.StreamHealthTick, BB.UpdateCalls, BB.UpdatePings, BB.TickReports, BB.UpdateMinimap = health, calls, pings, reports, minimap
	check(sentTo(11, mark, "V2;")[1], "a hook before sending fails on every tick: Anna's hello is answered all the same")
	check(ticks >= 20 and reportTicks == ticks, "one in the middle fails: the rest of the tick runs, got " .. reportTicks .. " of " .. ticks)
	check(healthCalls <= 3 and minimapCalls <= 3,
		"the failing ones rest: " .. healthCalls .. " of " .. ticks .. " ticks, " .. minimapCalls .. " of 180 frames")
	check(#reported == 3, "each error reported once, got " .. #reported)
end
