local _, ns = ...
local B = ns.Beacon

-- Beacon's messages between friends: what each one says, and B.Parse, which reads them. They go
-- as Battle.net addon messages (Beacon.lua sends and receives them), ";"-separated, at most 255
-- bytes, each starting with its kind's letter and the protocol version:
--
--   H2                  hello: "I run Beacon". Sent to online WoW friends we don't know yet;
--                       anyone running it answers with their state. Friends without the addon
--                       get this one message (at most every HELLO_RETRY seconds) and nothing else.
--   S2;<flags>;<continent>;<north>;<west>;<subzone>;<target>
--                       my state. flags: D dead, G ghost, C in combat. The position is a world
--                       position (C_Map.GetWorldPosFromMapPos), empty in dungeons/raids or with
--                       sharing off; <target> is who I'm fighting, only while in combat.
--   L2;<level>;<text>   I levelled up; <text> is my own level-up message (empty = their default)
--   V2;<version>        my LefthyTools build (LT.version), sent with every answer and to every
--                       friend every VERSION_EVERY seconds (low priority); a friend on an
--                       older build gets told once per login. Builds before 0.4.0 ignore it.
--   F2;<files>          which files my build loads (LT.FILES), sent just before every V2: a friend
--                       updating to it learns whether a /reload is enough or the game needs a
--                       restart. (Its own message: older builds reject a V2 with more fields.)
--   K2;<YYYYMMDD>;<minutes AFK>
--                       that day's AFK time, sent after its D2 (Chronicle; its own message because
--                       older builds reject a D2 with another field)
--   M2;<text>           an LTC line (/ltc, /l), to everyone (Chat.lua)
--   A2;<text>           an announcement for the middle of everyone's screen (/lefthy announce)
--   U2;<after>;<de|en>  to a friend on a newer build: what's new in it after my newest changelog
--                       id (Data/Changelog.lua), in my language. Answered with
--   W2;<id>;<module>;<title>
--                       one changelog entry each (the newest NEWS_LINES, oldest first), then
--                       W2;0;;<left out> to end. The update notice lists them, one line each.
--   P2;<continent>;<north>;<west>;<uiMapID>
--                       a map ping (Pings.lua): "look here", shown on friends' maps for a minute
--   G2                  my map ping is gone (taken back before its minute is up)
--   Y2;<1|0>            I collect friends' error reports (or stopped); with every answer while on
--   Z2;<id>;<n>;<of>;<text>
--                       part n of an error report for a friend who collects them (Reports.lua)
--   T2;<questID>;<done>;<title>;<objective>
--                       the quest I'm tracking (super-tracked, else the first watched one), for
--                       the tooltip: done 1 = ready to turn in, objective = the first unfinished
--                       one. questID 0 = none or not shared. Sent when it changes (at most every
--                       QUEST_GAP seconds) and with every answer.
--   E2;<kind>;<a>;<b>   a Chronicle highlight (boss, rare, dungeon, loot, ...: HIGHLIGHTS below) with
--                       up to two text fields; see Chronicle.lua
--   C2;<count>          in combat: how many enemies have me on their threat list (counted on the
--                       nameplates the game shows). Sent when it changes, at most once a second;
--                       a state without C clears it.
--   I2;<item string>[;<call id>]
--                       an item I show my friends (Ctrl+right-click, Items.lua); with a call id
--                       (Ctrl+Shift+right-click) they can say Need or Pass:
--   N2;<call id>;<1|0>  my Need (1) or Pass (0) for a friend's item, to them
--   R2;<call id>;<name>:<roll>,...
--                       the verdict on my item, to everyone: highest roll first (0 = no roll)
--   D2;<YYYYMMDD>;<minutes played>;<xp>;<quests>;<kills>;<deaths>;<levels>
--                       a day of my Chronicle statistics, for friends' graphs: my last 7 days
--                       when a friend shows up, then today's at most every 5 minutes if changed
--   X2;<percent>        progress on my current level (0-99), empty at max level or with sharing
--                       off. Sent when the whole percent changes (at most every XP_GAP seconds)
--                       and with every answer.
--   O2;<word>;<...>     the fight stream (StreamNet.lua): h I can be watched (with every answer),
--                       w I watch you, f what's around me (to watchers only), n a mob's name,
--                       v my health (estimated; to everyone, when it changes, and with answers);
--                       StreamNet.lua has all its words
--   J2;<word>;<...>     Chronicle's journals (Chronicle/Sync.lua): h I sync, s what I hold, q send me
--                       an account's records, p/d/n a profile, day or highlight, e that's all
--   Q2                  module switched off: forget me
--
-- Builds that don't know a message kind ignore it (Parse returns nil, before the sender counts as
-- a friend with the addon), so new kinds can be added without breaking older friends. Older builds
-- read every kind they know strictly: a field more or less and they drop the message. So new data
-- goes in a new kind (or a new word of O2 / J2), and a changed format to each friend as their build
-- reads it (their version: Chat.lua's link levels). Every letter but B is taken.

local VERSION = B.VERSION

-- The Chronicle highlights friends take (E2), and the only ones mine go out as (B.ShareHighlight).
local HIGHLIGHTS = { boss = true, rare = true, dungeon = true, loot = true, mount = true, achievement = true,
	quests = true, gold = true, profession = true, quest = true, zone = true }
B.HIGHLIGHTS = HIGHLIGHTS

-- Returns the message kind and its fields, "version" plus their version for another
-- LefthyTools version, or nil for anything that isn't exactly our protocol.
function B.Parse(text)
	if type(text) ~= "string" or #text > 255 then
		return nil
	end
	local kind, version, rest = text:match("^(%u)(%d+)(.*)$")
	if not kind then
		return nil
	elseif version ~= VERSION then
		return "version", version
	elseif (kind == "H" or kind == "Q" or kind == "G") and rest == "" then
		return kind
	elseif kind == "S" then
		local flags, continent, north, west, subzone, target =
			rest:match("^;(%u*);(%-?%d*);(%-?[%d%.]*);(%-?[%d%.]*);([^;]*);([^;]*)$")
		if not flags then
			return nil
		end
		local c, n, w = tonumber(continent), tonumber(north), tonumber(west)
		local hasPos = c ~= nil and n ~= nil and w ~= nil
		if not hasPos and (continent ~= "" or north ~= "" or west ~= "") then
			return nil
		end
		return "S", flags, hasPos and c, n, w, subzone, target
	elseif kind == "L" then
		local level, message = rest:match("^;(%d+);([^;]*)$")
		if level then
			return "L", tonumber(level), message
		end
	elseif kind == "V" then
		local version = rest:match("^;([%w%.%-]+)$")
		if version and #version <= 40 then
			return "V", version
		end
	elseif kind == "M" or kind == "A" then
		local text = rest:match("^;([^;]+)$")
		if text and #text <= 220 then
			return kind, text
		end
	elseif kind == "F" then
		local files = rest:match("^;(%x+)$")
		if files and #files <= 16 then
			return "F", files
		end
	elseif kind == "U" then
		local after, language = rest:match("^;(%d+);(%l%l)$")
		if after then
			return "U", tonumber(after), language
		end
	elseif kind == "W" then
		local id, module, title = rest:match("^;(%d+);(%l*);([^;]*)$")
		if id then
			return "W", tonumber(id), module, title
		end
	elseif kind == "P" then
		local continent, north, west, mapID = rest:match("^;(%d+);(%-?%d+%.?%d*);(%-?%d+%.?%d*);(%d+)$")
		if continent then
			return "P", tonumber(continent), tonumber(north), tonumber(west), tonumber(mapID)
		end
	elseif kind == "T" then
		local questID, done, title, objective = rest:match("^;(%d+);([01]?);([^;]*);([^;]*)$")
		if questID then
			return "T", tonumber(questID), done == "1", title, objective
		end
	elseif kind == "E" then
		local highlight, a, b = rest:match("^;(%l+);([^;]*);([^;]*)$")
		if highlight and HIGHLIGHTS[highlight] then
			return "E", highlight, a, b
		end
	elseif kind == "C" then
		local count = rest:match("^;(%d%d?)$")
		if count then
			return "C", tonumber(count)
		end
	elseif kind == "X" then
		local percent = rest:match("^;(%d?%d?)$")
		if percent then
			return "X", tonumber(percent) -- nil: not shared
		end
	elseif kind == "I" then
		local itemString, callID = rest:match("^;(%d+[%-%d:]*);(%d+)$")
		itemString = itemString or rest:match("^;(%d+[%-%d:]*)$")
		if itemString then
			return "I", itemString, tonumber(callID) -- no call id: just showing it
		end
	elseif kind == "N" then
		local callID, need = rest:match("^;(%d+);([01])$")
		if callID then
			return "N", tonumber(callID), need == "1"
		end
	elseif kind == "R" then
		local callID, result = rest:match("^;(%d+);([^;]*)$")
		if callID and #result <= 200 then
			return "R", tonumber(callID), result
		end
	elseif kind == "D" then
		local y, mo, d, played, xp, quests, kills, deaths, levels =
			rest:match("^;(%d%d%d%d)(%d%d)(%d%d);(%d+);(%d+);(%d+);(%d+);(%d+);(%d+)$")
		if y and tonumber(played) <= 1440 and #xp <= 9 and #quests <= 5 and #kills <= 6 and #deaths <= 4 and #levels <= 3 then
			return "D", { day = y .. "-" .. mo .. "-" .. d, played = tonumber(played) * 60, xp = tonumber(xp),
				quests = tonumber(quests), kills = tonumber(kills), deaths = tonumber(deaths), levels = tonumber(levels) }
		end
	elseif kind == "K" then
		local y, mo, d, minutes = rest:match("^;(%d%d%d%d)(%d%d)(%d%d);(%d+)$")
		if y and #minutes <= 4 and tonumber(minutes) <= 1440 then
			return "K", { day = y .. "-" .. mo .. "-" .. d, afk = tonumber(minutes) * 60 }
		end
	elseif kind == "Y" then
		local on = rest:match("^;([01])$")
		if on then
			return "Y", on == "1"
		end
	elseif kind == "Z" then
		local id, n, of, text = rest:match("^;(%d+);(%d+);(%d+);([^;]*)$")
		n, of = tonumber(n), tonumber(of)
		if id and #id <= 4 and n >= 1 and n <= of and of <= 16 and #text <= 200 then
			return "Z", tonumber(id), n, of, text
		end
	elseif kind == "O" or kind == "J" then
		local word, more = rest:match("^;(%l);(.*)$")
		if word and #more <= 250 then
			return kind, word, more
		end
	end
	return nil
end
