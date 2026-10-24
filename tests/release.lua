-- WoW: Forever's release starts fresh: saved data the beta wrote goes, once, also when a player copies
-- the beta's WTF folder over (Core.lua: LT.WhichWorld, each saved table's world). A suite of its own,
-- in a Lua state of its own like test_de.lua: it starts the game several times (MockReload, then the
-- addon loaded again), each time with the client and the saved variables it needs.
local failures, passes = 0, 0
local function check(cond, msg)
	if cond then passes = passes + 1 else failures = failures + 1; io.write("  FAIL: " .. msg .. "\n") end
end
io.write("\n== WoW: Forever's release: the beta's saved data\n")

-- The game loading LefthyTools (TOC order, then the events), with the saved variables as they are.
local LT
local function Start()
	local ns = {}
	for _, file in ipairs(SOURCES) do
		local chunk = assert(load(file.src, "@Interface/AddOns/LefthyTools/" .. file.name)) -- named like in game
		chunk("LefthyTools", ns)
	end
	Fire("ADDON_LOADED", "LefthyTools")
	Fire("PLAYER_LOGIN")
	Fire("PLAYER_ENTERING_WORLD", true, false)
	Advance(0.3)
	LT = LefthyTools
end
local function Restart() -- a /reload, or the game started again
	MockReload()
	Start()
end
local NOTICE = "data from the beta was reset; WoW: Forever starts fresh."
local function notices(mark) -- the chat line since PRINTED[mark], how often
	local n = 0
	for i = mark, #PRINTED do if PRINTED[i]:find(NOTICE, 1, true) then n = n + 1 end end
	return n
end
local function stamped(world)
	return LefthyToolsDB.world == world and LefthyToolsChronicleDB.world == world and LefthyToolsBestiaryDB.world == world
end
local function release() MOCK_CLIENT, MOCK_BUILD = { beta = false, test = false, ptr = false }, "70532" end

-- A player copied the beta's WTF folder to the release. Its LefthyTools settings (from a build before
-- the stamps: they say nothing), its error list, flight times, Chronicle's journal (stamped by the
-- beta) and the Bestiary's mobs (saying nothing).
release()
local betaDB = { modules = { mirage = true, beacon = false }, settings = { mirage = { delay = 9 }, tweaks = { movableBags = false } },
	errors = { { msg = "Interface/AddOns/LefthyTools/Core/Core.lua:1: on the beta", count = 1, kind = "error" } }, changelogSeen = 3,
	flightTimes = { ["Goldshire > Stormwind"] = 75 } }
local betaChronicle = { world = "beta", chars = { ["Lefthy-Realmy"] = { name = "Lefthy", realm = "Realmy", level = 12, events = {},
	stats = { kills = 500 } } }, friends = {}, friendStats = {}, book = {} }
local betaBestiary = { mobs = { [116] = { name = "Defias Bandit", level = 12, kills = 40, money = 900, items = {} } } }
LefthyToolsDB, LefthyToolsChronicleDB, LefthyToolsBestiaryDB = betaDB, betaChronicle, betaBestiary
local mark = #PRINTED + 1
Start()
local db = LefthyToolsDB
check(LT.world == "release" and LT.betaForgotten, "the release; the beta's data found")
check(db ~= betaDB and LefthyToolsChronicleDB ~= betaChronicle and LefthyToolsBestiaryDB ~= betaBestiary and stamped("release"),
	"all three saved tables are new ones, and say they're the release's")
check(db.modules.mirage == false and db.modules.beacon == true and db.modules.chronicle == true and LT:GetModule("beacon").enabled
	and not LT:GetModule("mirage").enabled, "the modules as on a first install: Mirage off, the others on")
check(db.settings.mirage.delay == LT:GetModule("mirage").defaults.delay and db.settings.tweaks.movableBags == true,
	"every setting is its default again")
check(#db.errors == 0 and next(db.flightTimes) == nil, "no errors from the beta, no flight times")
local me = LefthyToolsChronicleDB.chars["Lefthy-Realmy"]
check(me and me ~= betaChronicle.chars["Lefthy-Realmy"] and me.stats.kills == 0 and next(LefthyToolsBestiaryDB.mobs) == nil,
	"a new journal, an empty Bestiary")
check(LT.freshInstall and db.changelogSeen == LT.WhatsNew.LatestID(), "what's new: as on a first install, everything counts as seen")
check(notices(mark) == 1, "one chat line says so")
Advance(5)
check(not (LefthyToolsNewsFrame and LefthyToolsNewsFrame:IsShown()), "no what's-new window")

-- Playing on the release: what it writes stays, /reload after /reload.
db.settings.tweaks.movableBags = false
local chronicle, bestiary = LefthyToolsChronicleDB, LefthyToolsBestiaryDB
mark = #PRINTED + 1
Restart()
check(not LT.betaForgotten and LefthyToolsDB == db and LefthyToolsChronicleDB == chronicle and LefthyToolsBestiaryDB == bestiary
	and stamped("release") and notices(mark) == 0, "a /reload on the release: nothing goes, no chat line")
check(db.settings.tweaks.movableBags == false and LefthyToolsChronicleDB.chars["Lefthy-Realmy"] == me and not LT.freshInstall,
	"what was set and recorded on the release stays")
Restart()
check(LefthyToolsDB == db and LefthyToolsChronicleDB == chronicle and LefthyToolsBestiaryDB == bestiary and notices(mark) == 0,
	"and the next time too")

-- The beta's Bestiary copied over once more, alone (one file of the WTF folder): only it goes.
local betaAgain = { world = "beta", mobs = { [116] = { name = "Defias Bandit", level = 12, kills = 41, money = 900, items = {} } } }
LefthyToolsBestiaryDB = betaAgain
mark = #PRINTED + 1
Restart()
check(LT.betaForgotten and LefthyToolsBestiaryDB ~= betaAgain and next(LefthyToolsBestiaryDB.mobs) == nil
	and LefthyToolsDB == db and LefthyToolsChronicleDB == chronicle and stamped("release") and notices(mark) == 1,
	"only the table the beta wrote goes; the release's stay")
check(not LT.freshInstall, "(the settings stayed: not a first install)")

-- A new install on the release (no saved variables at all): nothing to reset.
LefthyToolsDB, LefthyToolsChronicleDB, LefthyToolsBestiaryDB = nil, nil, nil
mark = #PRINTED + 1
Restart()
check(not LT.betaForgotten and LT.freshInstall and stamped("release") and notices(mark) == 0,
	"a new install on the release: no chat line, every table says it's the release's")

-- The beta: its data stays as it is, from before the stamps too, and says it's the beta's.
MOCK_CLIENT, MOCK_BUILD = { beta = true, test = true, ptr = false }, "70450"
db, chronicle, bestiary = LefthyToolsDB, LefthyToolsChronicleDB, LefthyToolsBestiaryDB
db.world, chronicle.world, bestiary.world = nil, nil, nil
db.settings.tweaks.movableBags = false
mark = #PRINTED + 1
Restart()
check(LT.world == "beta" and not LT.betaForgotten and LefthyToolsDB == db and LefthyToolsChronicleDB == chronicle
	and LefthyToolsBestiaryDB == bestiary and stamped("beta") and notices(mark) == 0 and db.settings.tweaks.movableBags == false,
	"the beta: nothing goes, every table now says it's the beta's")

-- Not known which client (a build before the release's that calls itself no beta): nothing changes.
MOCK_CLIENT, MOCK_BUILD = { beta = false, test = false, ptr = false }, "70450"
LefthyToolsBestiaryDB = nil
Restart()
check(LT.world == nil and not LT.betaForgotten and LefthyToolsDB == db and LefthyToolsChronicleDB == chronicle
	and db.world == "beta" and chronicle.world == "beta" and LefthyToolsBestiaryDB and LefthyToolsBestiaryDB.world == nil
	and notices(mark) == 0, "unknown: nothing goes, no stamp changes (none on a new table either)")
IsBetaBuild = nil
Restart()
check(LT.world == nil and LefthyToolsDB == db and db.world == "beta" and notices(mark) == 0, "a question the client doesn't have: the same")
IsBetaBuild = function() return MOCK_CLIENT.beta end

-- Back on the release with that data (the beta's, and one table saying nothing): it all goes.
release()
Restart()
check(LT.betaForgotten and LefthyToolsDB ~= db and LefthyToolsChronicleDB ~= chronicle and stamped("release")
	and LefthyToolsDB.settings.tweaks.movableBags == true and notices(mark) == 1, "on the release the beta's data goes, settings and all")

check(#ERRORS == 0, "no errors reported through the error handler")
io.write(string.format("\n%d passed, %d failed (the release)\n", passes, failures))
if failures > 0 then error("release tests failed") end
