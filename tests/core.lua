-- Core: the version, the module framework, the error catcher, Core's shared helpers, map art, and
-- which client this is (the beta or the release).
-- Needs: no other file. It runs first: its framework checks see the modules as login left them
-- (Mirage off) and switch Mirage on; hardly any time passes in it (see mirage.lua).
local suite = ...
local check, near, section, ns, LT, lefthy = suite.check, suite.near, suite.section, suite.ns, suite.LT, suite.lefthy
local Mirage = LT:GetModule("mirage")

section("version")
check(LT.version == "0.4.0-3-gabc1234", "version comes from the installed TOC")
local function cmp(a, b) return LT.CompareVersions(a, b) end
check(cmp("0.4.0-5-gaaaaaaa", "0.4.0-3-gbbbbbbb") == 1 and cmp("0.4.0", "0.4.0-1-gaaaaaaa") == -1,
	"more commits since the same version = newer")
check(cmp("0.10.0", "0.9.9-40-gaaaaaaa") == 1 and cmp("1.0.0", "0.99.0") == 1, "numeric, not alphabetical")
check(cmp("0.4.0-gaaaaaaa", "0.4.0-3-gbbbbbbb") == nil and cmp("0.5.0-gaaaaaaa", "0.4.0-3-gbbbbbbb") == 1,
	"unknown commit count: only the base version can be compared")
check(cmp("0.4.0-2-gaaaaaaa-dirty", "0.4.0-1-gbbbbbbb") == 1 and cmp("garbage", "0.4.0") == nil, "dev builds and nonsense")
local versionMark = #PRINTED + 1
lefthy("version")
check(PRINTED[versionMark] and PRINTED[versionMark]:find("0.4.0-3-gabc1234", 1, true), "/lefthy version")

section("framework")
check(Mirage and not Mirage.enabled and LefthyToolsDB.modules.mirage == false, "Mirage is off by default (opt-in)")
check(LT:GetModule("tweaks").enabled and LT:GetModule("beacon").enabled, "the other modules are on by default")
do -- Mirage never on yet: a flight's film runs its engine (HideGroups), and the Toggle Minimap key mustn't
	-- bring a minimap hidden for the film back over it (its quest areas ignore opacity). (No time passes here.)
	local key = ToggleMinimap
	Mirage:HideGroups("test", { minimap = true }, 0)
	check(ToggleMinimap ~= key, "Mirage off: a film hiding the minimap watches the Toggle Minimap key too")
	Mirage:HideGroups("test", nil, 0)
end
lefthy("enable mirage")
Advance(0.3) -- let the debounced rebuild run
check(Mirage.enabled, "mirage switched on")
check(LefthyToolsDB.modules.mirage == true, "module switch saved in LefthyToolsDB.modules")
check(REGISTERED_SETTINGS.LefthyTools_module_mirage, "overview page has a switch for Mirage")
check(LT.category and LT.category.name == "LefthyTools", "LefthyTools overview category")
check(Mirage.category and Mirage.category.parent == LT.category and Mirage.category.name == "Mirage",
	"Mirage has its own sub-page under LefthyTools")
check(#ADDON_CATEGORIES == 1 and ADDON_CATEGORIES[1] == LT.category,
	"only the parent category is registered as an addon category")
do -- shared helpers for Forever's secret values
	check(LT.IsSecret(SECRET) and not LT.IsSecret(1) and not LT.IsSecret(nil), "LT.IsSecret")
	check(LT.Readable(0) and LT.Readable(false) and LT.Readable("") and not LT.Readable(nil) and not LT.Readable(SECRET),
		"LT.Readable: there and not a secret")
	local errorsBefore = #ERRORS
	check(LT.Value(function(n) return n + 1, "second" end, 1) == 2 and LT.Value(nil, 1) == nil
		and LT.Value(function() error("broken API") end) == nil and LT.Value(function() return SECRET end) == nil
		and #ERRORS == errorsBefore, "LT.Value: a call's first answer; nil if the API is missing, fails (quietly) or answers a secret")
	check(select("#", LT.Value(function() return SECRET end)) == 1 and select("#", LT.Value(function() error("x") end)) == 1
		and tonumber(LT.Value(function() return SECRET end)) == nil, "LT.Value: always one value, also when it's nil")
end
do -- shared text helpers
	local cut = LT.CutUTF8
	check(cut("Anna", 10) == "Anna" and cut("Anna", 2) == "An" and cut("Jäger", 2) == "J" and cut("Jäger", 3) == "Jä"
		and cut("äb", 1) == "\195" and cut("", 5) == "", "LT.CutUTF8: whole letters only (a letter ending at the limit stays), at least one byte")
	check(LefthyTools.CutUTF8 == ns.Beacon.CutUTF8, "Beacon's CutUTF8 is Core's")
	check(LT.Decimal("4.5") == "4.5" and LT.Decimal("12.3 km", true) == "12.3 km" and LT.Decimal("<0.1%") == "<0.1%",
		"LT.Decimal: an English client keeps the point (test_de.lua: the German comma)")
	local now = time()
	check(LT.Ago(now) == "just now" and LT.Ago(now + 60) == "just now" and LT.Ago(now - 300) == "5 min ago"
		and LT.Ago(now - 3 * 3600) == "3 h ago" and LT.Ago(now - 86400 - 60) == "yesterday" and LT.Ago(now - 4 * 86400) == "4 days ago",
		"LT.Ago: just now, minutes, hours, yesterday, days")
	check(ns.Chronicle.Ago == LT.Ago, "Chronicle's Ago is Core's")
end
do -- character names: a first name and a surname on Forever
	local N, surnameBefore = LT.Names, MY_SURNAME
	check(N.First("Anna Brook") == "Anna" and N.First("Anna-Realm") == "Anna" and N.First("Anna") == "Anna"
		and N.First(nil) == nil and N.First(SECRET) == nil, "LT.Names.First: the first name, nil for a secret")
	check(N.HasSurname("Anna Brook") and not N.HasSurname("Anna") and not N.HasSurname(nil) and not N.HasSurname(SECRET),
		"LT.Names.HasSurname")
	check(N.Same("anna", "Anna-Realm") and N.Same("Anna Brook", "ANNA") and not N.Same("Anna", "Bob") and not N.Same(nil, "Anna"),
		"LT.Names.Same: the same character however typed")
	MY_SURNAME = "Brook"
	local full, first, surname = N.Mine()
	check(full == "Lefthy Brook" and first == "Lefthy" and surname == "Brook" and N.IsMine("Lefthy") and N.IsMine("Lefthy Brook")
		and not N.IsMine("Lefthy Stone") and not N.IsMine(nil) and ns.Beacon.MyName() == "Lefthy Brook",
		"LT.Names.Mine and IsMine: my name as the game shows it, with or without the surname")
	MY_SURNAME = SECRET
	full, first, surname = N.Mine()
	check(full == "Lefthy" and first == "Lefthy" and surname == nil, "a surname the game keeps secret: the first name alone")
	MY_SURNAME = nil
	check(N.Mine() == "Lefthy" and select("#", ns.Beacon.MyName()) == 1, "no surname: the first name (Beacon's MyName: only the name)")
	MY_SURNAME = surnameBefore
end
do -- in a fight; windows open (what Mirage and Misc Tweaks ask)
	local combat, lockdown, affecting = STATE.combat, InCombatLockdown, UnitAffectingCombat
	STATE.combat = nil
	check(LT.InCombat() == false, "LT.InCombat: not in a fight")
	STATE.combat = true
	check(LT.InCombat() == true, "LT.InCombat: in a fight")
	InCombatLockdown = function() return false end
	check(LT.InCombat() == true, "LT.InCombat: also the moment before the combat lockdown begins")
	UnitAffectingCombat = function() return SECRET end
	check(LT.InCombat() == false, "LT.InCombat: an answer the game keeps secret isn't a fight")
	STATE.combat, InCombatLockdown, UnitAffectingCombat = combat, lockdown, affecting
	check(ns.TweakUtil.InCombat == LT.InCombat and ns.TweakUtil.OpenWindows == LT.Window.OpenCount, "Misc Tweaks ask Core")
	local panel, bags = STATE.panel, STATE.bags
	STATE.panel, STATE.bags = nil, nil
	local none = LT.Window.OpenCount()
	STATE.panel, STATE.bags = "left", true
	check(none == 0 and LT.Window.OpenCount() == 2, "LT.Window.OpenCount: a panel and the bags")
	STATE.panel, STATE.bags = panel, bags
end

section("error catcher")
local function errorRow() -- the overview's "Errors" info row
	for _, init in ipairs(LAYOUTS["LefthyTools"]) do
		if init.template == "LefthyToolsSettingsInfoTemplate" and init.data.name == "Errors" then return init.data.getValue() end
	end
end
local errorsBefore, emark = #ERRORS, #PRINTED + 1
check(LefthyToolsDB.errors and #LefthyToolsDB.errors == 0 and errorRow():find("None", 1, true), "no errors yet, the overview says so")
local ours = "Interface/AddOns/LefthyTools/Modules/Beacon/Beacon.lua:42: attempt to index a nil value (field 'peer')"
geterrorhandler()(ours)
geterrorhandler()(ours)
local kept = LefthyToolsDB.errors
check(#kept == 1 and kept[1].msg == ours and kept[1].count == 2 and kept[1].kind == "error" and kept[1].version == "0.4.0-3-gabc1234",
	"our error is kept once, counted twice, with the build it happened in")
geterrorhandler()("Interface/AddOns/SomeoneElse/Main.lua:1: oops")
check(#kept == 1, "another addon's error isn't ours")
ScriptErrorsFrame:DisplayMessageInternal("Interface/AddOns/Blizzard_MapCanvas/MapCanvas.lua:9: bad argument", 0,
	"[Interface/AddOns/Blizzard_MapCanvas/MapCanvas.lua]:9: in function 'AcquirePin'\n[Interface/AddOns/LefthyTools/Modules/Beacon/Dots.lua]:255: in function 'RefreshAllData'")
check(#kept == 2 and kept[2].stack:find("Dots.lua", 1, true), "a Blizzard error with our code in the stack is ours too")
ScriptErrorsFrame:DisplayMessageInternal(SECRET, 0, SECRET)
check(#kept == 2, "a secret error message is left alone")
Advance(0.05)
local notices = 0
for i = emark, #PRINTED do if PRINTED[i]:find("Type /lefthy errors", 1, true) then notices = notices + 1 end end
check(notices == 1, "one chat notice per session (not from inside the error handler), got " .. notices)
Fire("ADDON_ACTION_BLOCKED", "LefthyTools", "SetPassThroughButtons")
Fire("ADDON_ACTION_BLOCKED", "OtherAddon", "CastSpellByName")
check(#kept == 3 and kept[3].kind == "blocked" and kept[3].msg:find("SetPassThroughButtons", 1, true), "blocked actions of ours are kept too")
local function renderRow(name) -- an overview info row, built the way the settings list builds it
	for _, init in ipairs(LAYOUTS["LefthyTools"]) do
		if init.template == "LefthyToolsSettingsInfoTemplate" and init.data.name == name then
			local row = CreateFrame("Frame")
			for k, v in pairs(LefthyToolsSettingsInfoMixin) do row[k] = v end
			row.Value = row:CreateFontString()
			row:OnLoad()
			row:Init(init)
			return row
		end
	end
end
do
	local row = renderRow("Errors")
	check(row.Value:GetText():find("3", 1, true) and not row.Value:GetText():find("/lefthy", 1, true)
		and row.Button:IsShown() and row.Button:GetText() == "Show", "the overview shows how many, with a Show button (nothing to type)")
	row.Button:Click()
	check(LefthyToolsErrorsFrame and LefthyToolsErrorsFrame:IsShown(), "the button opens the error list")
	LefthyToolsErrorsFrame:Hide()
	check(not renderRow("Version").Button:IsShown(), "rows without a button don't show one")
end
lefthy("errors")
local errWindow = LefthyToolsErrorsFrame
local report = errWindow and errWindow.Box:GetText() or ""
check(errWindow and errWindow:IsShown(), "/lefthy errors opens the error window")
check(report:find("LefthyTools 0.4.0-3-gabc1234 | WoW 1.60.1.70205 (16001) | enUS", 1, true)
	and report:find("[1] blocked", 1, true) and report:find("[3] error, 2x", 1, true) and report:find(ours, 1, true),
	"the report: build, client, every error newest first, got\n" .. report)
check(not report:find("|c", 1, true), "plain text, no colour codes")
check(#UISpecialFrames > 0 and UISpecialFrames[#UISpecialFrames] == "LefthyToolsErrorsFrame", "Escape closes it")
for i = 1, 30 do geterrorhandler()("Interface/AddOns/LefthyTools/Core/Core.lua:" .. i .. ": test " .. i) end
check(#kept == 25 and kept[25].msg:find("test 30", 1, true) and not kept[1].msg:find(ours, 1, true), "at most 25 kept, the oldest go")
do -- LT.Guard (ticks call other files' hooks with it; more in guard.lua). No time passes here.
	local calls = 0
	local function brokenHook() calls = calls + 1; error("a hook that fails") end
	local first, again = LT.Guard("test.broken", brokenHook), LT.Guard("test.broken", brokenHook)
	local newest = kept[#kept]
	local where = debug.getinfo(brokenHook, "S")
	check(first == nil and again == nil and calls == 1, "LT.Guard: a hook that fails rests (called again right away, it isn't)")
	check(newest.msg:find("a hook that fails", 1, true) and newest.count == 1
		and newest.stack:find(where.short_src .. ":" .. where.linedefined .. ":", 1, true),
		"... and reaches the error catcher once, with the stack where it failed, got\n" .. newest.stack)
	local ok, one, two = LT.Guard("test.works", function(x) return x + 1, "two" end, 1)
	check(ok == true and one == 2 and two == "two" and LT.Guard("test.missing", nil) == nil,
		"a hook that works: true and its answers; one that isn't there (a file not loaded): nothing")
end
lefthy("errors clear")
check(#LefthyToolsDB.errors == 0 and errorRow():find("None", 1, true) and not renderRow("Errors").Button:IsShown(),
	"/lefthy errors clear (and the Show button goes)")
check(errWindow.Box:GetText():find("No errors.", 1, true), "the open window follows")
errWindow:Hide()
for i = #ERRORS, errorsBefore + 1, -1 do table.remove(ERRORS, i) end -- the test's own errors

section("a zone's map (LT.MapArt)")
do -- The world map's art of a zone and what you've explored of it, laid into a frame of ours (the
	-- Bestiary ledger's kill map, the fight stream's map without minimap tiles). The frame here notes
	-- each texture's draw sublevel and mask.
	local MapArt, errorsWere, made = LT.MapArt, #ERRORS, 0
	local host = CreateFrame("Frame")
	local mask = host:CreateMaskTexture()
	local frame = { CreateTexture = function(_, name, layer, inherits, sub)
		made = made + 1
		local t = host:CreateTexture(name, layer, inherits, sub)
		t.sub = sub
		function t:SetDrawLayer(l, s) self.layer, self.sub = l, s end
		function t:AddMaskTexture(m) self.mask = m end
		return t
	end }
	local function at(t) return select(4, t:GetPoint(1)) end
	local map = MapArt.New(frame, "BACKGROUND", 0, mask)
	local width, height = MapArt.Lay(map, 1429, 2004, 668) -- (twice the art's width, its height: x 2 and x 1)
	local tiles, overlays = map.tiles, map.overlays
	local x12, y12 = at(tiles[12])
	check(width == 2004 and height == 668 and #tiles == 12 and tiles[1].path == 142901 and tiles[12].path == 142912 and tiles[1].shown
		and tiles[1].width == 512 and tiles[1].height == 256 and tiles[1].layer == "BACKGROUND" and tiles[1].sub == 0 and tiles[1].mask == mask
		and tiles[4].width == 468 and near(tiles[4].coords[2], 234 / 256, 1e-9) and tiles[4].coords[4] == 1
		and tiles[12].height == 156 and near(tiles[12].coords[4], 156 / 256, 1e-9) and x12 == 1536 and y12 == -512,
		"the art: 4 x 3 tiles in rows at the size asked for, the last column and row cut to the map's edge, each cut by the mask")
	local o1, o2, o3 = overlays[1], overlays[2], overlays[3]
	local x2, y2 = at(o2)
	local x3, y3 = at(o3)
	check(#overlays == 3 and made == 15 and o1.path == 7001 and o2.path == 7002 and o3.path == 7004 and o1.shown and o3.shown
		and o1.width == 512 and o1.height == 200 and near(o1.coords[4], 200 / 256, 1e-9) and o1.sub == 1 and o1.mask == mask
		and x2 == 712 and y2 == -50 and o2.width == 88 and near(o2.coords[2], 44 / 64, 1e-9)
		and x3 == 1900 and y3 == -600 and o3.width == 104 and o3.height == 68 and near(o3.coords[2], 52 / 128, 1e-9)
		and near(o3.coords[4], 68 / 128, 1e-9) and o3.sub == 2,
		"what you've explored, over it: each area's tiles from its offset in the art's pixels, scaled like the art, the last a "
		.. "smaller file, cut at the edge, the top layer's over the others; not what only a mouseover shows")
	o1.path = nil
	check(MapArt.Lay(map, 1429, 2004, 668) == 2004 and o1.path == nil and not MapArt.Stale(map), "the same map at the same size: nothing laid again")
	width, height = MapArt.Lay(map, 1436, 400, 220, true)
	check(made == 15 and tiles[1].path == 143601 and near(width, 330) and near(height, 220) and near(tiles[1].width, 256 * 220 / 668, 1e-9)
		and not o1.shown and not o2.shown and not o3.shown,
		"another zone, fit into a box: as large as fits, the art's own shape; the pool's textures again; nothing explored there")
	MapArt.Lay(map, 1429, 2004, 668)
	check(made == 15 and o1.path == 7001 and o1.shown and o3.shown, "back: laid again from the pool")
	local elwynn = EXPLORED[1429]
	EXPLORED[1429] = { elwynn[1] }
	Fire("MAP_EXPLORATION_UPDATED")
	check(MapArt.Stale(map) and o3.shown, "explored more: the map is stale (the event only counts)")
	MapArt.Lay(map, 1429, 2004, 668)
	check(not MapArt.Stale(map) and o1.shown and o2.shown and not o3.shown, "laid again when next asked for")
	EXPLORED[1429] = elwynn
	-- Hidden (the fight stream's art while it shows minimap tiles): also what's laid meanwhile; shown
	-- again: only what's in use.
	MapArt.SetShown(map, false)
	local any = false
	for _, t in ipairs(tiles) do any = any or t.shown end
	for _, t in ipairs(overlays) do any = any or t.shown end
	MapArt.Lay(map, 1436, 2004, 668)
	check(not any and not tiles[1].shown and tiles[1].path == 143601, "hidden: all of it, also what's laid while hidden")
	MapArt.SetShown(map, true)
	check(tiles[1].shown and tiles[12].shown and not o1.shown and not o2.shown, "shown again: only what's in use")
	-- Forgotten (the fight stream's window opened again): all hidden, the same map laid anew.
	MapArt.Forget(map)
	tiles[1].path = nil
	check(not tiles[1].shown and not tiles[12].shown and not MapArt.Stale(map), "forgotten: nothing shown")
	check(MapArt.Lay(map, 1436, 2004, 668) == 2004 and tiles[1].path == 143601 and tiles[1].shown and made == 15,
		"the same map again: laid anew, from the pool")
	-- The game saying nothing.
	local layers, exploration = C_Map.GetMapArtLayers, C_MapExplorationInfo
	C_MapExplorationInfo = nil
	check(MapArt.Lay(map, 1429, 2004, 668) == 2004 and tiles[12].shown and not o1.shown, "no exploration API: the art alone")
	C_MapExplorationInfo = exploration
	C_Map.GetMapArtLayers = function() return SECRET end
	check(MapArt.Lay(map, 1436, 2004, 668) == nil and not tiles[1].shown, "the art a secret: none, nothing shown")
	C_Map.GetMapArtLayers = function() return { { layerWidth = 1002, layerHeight = 668, tileWidth = 0, tileHeight = SECRET } } end
	check(MapArt.Lay(map, 1429, 2004, 668) == nil and not tiles[1].shown, "nonsense or secret sizes: none")
	C_Map.GetMapArtLayers = nil
	check(MapArt.Lay(map, 1436, 2004, 668) == nil and MapArt.Lay(map, nil, 2004, 668) == nil, "no art API, or no map: none")
	Fire("MAP_EXPLORATION_UPDATED")
	check(not MapArt.Stale(map) and #ERRORS == errorsWere, "no art: never stale; no errors")
	C_Map.GetMapArtLayers = layers
end

section("the beta or the release")
do -- Which client this is (LT.WhichWorld): the release starts fresh, also from a copy of the beta's
	-- saved variables (release.lua loads the addon on each). No time passes here.
	check(LT.world == "beta" and not LT.betaForgotten and LefthyToolsDB.world == "beta" and LefthyToolsChronicleDB.world == "beta"
		and LefthyToolsBestiaryDB.world == "beta", "the mock is the beta: every saved table says so, nothing reset")
	local client, ptr, buildInfo = MOCK_CLIENT, IsPublicTestClient, GetBuildInfo
	local function world(beta, test, pt, build)
		MOCK_CLIENT, MOCK_BUILD = { beta = beta, test = test, ptr = pt }, build or "70532"
		return LT.WhichWorld()
	end
	check(world(true, true, false) == "beta" and world(true, false, false) == "beta" and world(false, true, false) == "beta"
		and world(false, false, true) == "beta" and world(true, false, false, "70600") == "beta",
		"the beta: the client says it's a beta, test or PTR build (whatever its build)")
	check(world(false, false, false) == "release" and world(false, false, false, "70533") == "release" and world(false, false, false, "71000") == "release",
		"the release: none of them, on the release's first build (70532) or later")
	check(world(false, false, false, "70531") == nil and world(false, false, false, "70450") == nil,
		"none of them on a build before the release's (a beta that doesn't say so): unknown")
	check(world(SECRET, false, false) == nil and world(false, SECRET, false) == nil and world(false, false, nil) == nil
		and world(false, "no", false) == nil, "an answer secret, missing or not a yes or no: unknown")
	world(false, false, false)
	IsPublicTestClient = nil
	local missing = LT.WhichWorld()
	IsPublicTestClient = function() error("broken") end
	local errorsWere = #ERRORS
	local broken = LT.WhichWorld()
	IsPublicTestClient = ptr
	check(missing == nil and broken == nil and #ERRORS == errorsWere, "a question the client doesn't have, or that fails: unknown (quietly)")
	GetBuildInfo = function() return "1.60.1", SECRET end
	local secretBuild = LT.WhichWorld()
	GetBuildInfo = nil
	local noBuild = LT.WhichWorld()
	GetBuildInfo = buildInfo
	check(secretBuild == nil and noBuild == nil and LT.WhichWorld() == "release", "the build secret or not there: unknown")
	MOCK_CLIENT, MOCK_BUILD = client, "70205"
	check(LT.WhichWorld() == "beta", "(the mock is the beta again)")
end
