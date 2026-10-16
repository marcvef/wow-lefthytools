local _, ns = ...
local LT = ns.LT
local L = ns.L
local M = LT:GetModule("beacon")
local B = ns.Beacon

-- Fight stream: a small view of a fight from above, you (or a friend) in the middle, the mobs
-- around, on the map of the place. The parts:
--   Stream.lua       asking the game (shared helpers: B.Stream), the test, the commands
--   StreamSense.lua  what's around you: mobs, their distance and learned direction, what you do
--   StreamView.lua   the windows (yours, the preview, and one per friend you watch)
--   StreamNet.lua    between friends: who may watch, who watches, the pictures sent
--
-- Known from the API docs (1.60.1): health is always hidden (secret), mob positions aren't there
-- (UnitPosition answers for group members only), the combat log is closed, raid markers are
-- hidden. Found by the tests on Forever: range checks answer in combat (harmful spells you know,
-- items of known range, CheckInteractDistance), so distances work up to 30 yd (further: "beyond",
-- on the rim of the 40 yd ring); where a nameplate is on the screen can't be read at all ("Can't
-- measure restricted regions"); a mob has a nameplate only while it's on your screen; your own
-- place and facing are exact. So directions are learned as you move and turn (StreamSense.lua).
--
--   /lefthy stream me | preview | watch <name> | stop [<name>] | test | results

local S = {}
B.Stream = S

S.LOOK_GAP = 0.5     -- the sensor and the windows look around this often
S.OUTER_YARDS = 40   -- the windows' outer ring
S.MAX_UNITS = 40     -- nameplate1 .. nameplate40
S.MAX_MOBS = 20
local TEST_TIME = 60 -- seconds a test takes notes
local KEEP_TESTS = 3
local EXAMPLES = 3   -- example answers per line of a report
local issecret = issecretvalue or function() return false end
S.issecret = issecret

-- Items with a known use range: C_Item.IsItemInRange works without owning them, if the game knows
-- the item (Forever knows classic-era ones, and they answer in combat). Measured by the tests:
-- 8149 between 5 and 10 yd, 17626 between 11 and 20, 13289 between 20 and 28.
local RANGE_ITEMS = { { 8149, 8 }, { 17626, 15 }, { 10645, 20 }, { 13289, 24 }, { 835, 30 } }
local INTERACT = { { 3, 10 }, { 2, 11 }, { 1, 28 } } -- CheckInteractDistance: duel, trade, inspect

S.UNITS, S.TARGETS = {}, {}
for i = 1, S.MAX_UNITS do
	S.UNITS[i], S.TARGETS[i] = "nameplate" .. i, "nameplate" .. i .. "target"
end

---------------------------------------------------------------------------
-- Asking the game
---------------------------------------------------------------------------

-- The function at a path like "C_Spell.IsSpellInRange", or nil where this client has none.
local apis = {}
local function Api(path)
	local f = apis[path]
	if f == nil then
		f = _G
		for part in path:gmatch("[^%.]+") do
			f = type(f) == "table" and f[part] or nil
		end
		f = type(f) == "function" and f or false
		apis[path] = f
	end
	return f or nil
end
S.Api = Api

-- A call's first answer if addons may read it; nil if the call is missing, fails or is hidden.
local function Value(path, ...)
	local f = Api(path)
	if not f then
		return nil
	end
	local ok, v = pcall(f, ...)
	if not ok or issecret(v) then
		return nil
	end
	return v
end
S.Value = Value

-- Harmful spells you know, two per range (one may not work on every mob, like Soothe Animal), melee
-- counted as 5 yd, shortest first.
local function RangeSpells()
	local list, seen = {}, {}
	local book = C_SpellBook
	if not (book and book.GetNumSpellBookSkillLines and C_Spell and C_Spell.IsSpellHarmful) then
		return list
	end
	local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
	local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell or 1
	for line = 1, book.GetNumSpellBookSkillLines() do
		local info = book.GetSpellBookSkillLineInfo(line)
		if info and not info.shouldHide and not info.offSpecID then
			for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
				local item = book.GetSpellBookItemInfo(slot, bank)
				local id = item and item.itemType == spellType and not item.isPassive and item.spellID
				local spell = id and C_Spell.IsSpellHarmful(id) and C_Spell.GetSpellInfo(id)
				local yards = spell and (spell.maxRange > 0 and spell.maxRange or 5)
				if yards and (seen[yards] or 0) < 2 and #list < 10 then
					seen[yards] = (seen[yards] or 0) + 1
					list[#list + 1] = { id = id, name = spell.name, yards = yards }
				end
			end
		end
	end
	table.sort(list, function(a, b) return a.yards < b.yards end)
	return list
end

-- Every way to tell how far a hostile unit is: { label, yards, path, arg, unitFirst }.
function S.RangeChecks()
	local checks = {}
	local ok, spells = pcall(RangeSpells)
	for _, spell in ipairs(ok and spells or {}) do
		checks[#checks + 1] = { label = ("spell %s (%d yd)"):format(spell.name, spell.yards), yards = spell.yards,
			path = "C_Spell.IsSpellInRange", arg = spell.id }
	end
	local load = Api("C_Item.RequestLoadItemDataByID")
	for _, item in ipairs(RANGE_ITEMS) do
		if load then
			pcall(load, item[1])
		end
		checks[#checks + 1] = { label = ("item %d (%d yd)"):format(item[1], item[2]), yards = item[2],
			path = "C_Item.IsItemInRange", arg = item[1] }
	end
	for _, interact in ipairs(INTERACT) do
		checks[#checks + 1] = { label = ("CheckInteractDistance %d (%d yd)"):format(interact[1], interact[2]),
			yards = interact[2], path = "CheckInteractDistance", arg = interact[1], unitFirst = true }
	end
	return checks
end

-- ok, answer (like pcall); false, "missing" where this client has no such call.
local function RangeAnswer(check, unit)
	local f = Api(check.path)
	if not f then
		return false, "missing"
	end
	if check.unitFirst then
		return pcall(f, unit, check.arg)
	end
	return pcall(f, check.arg, unit)
end

-- The shortest known range a hostile unit is within, and the longest it's beyond (nil: none of the
-- range checks answered that way).
function S.Bounds(unit, checks)
	local near, far
	for _, check in ipairs(checks) do
		local ok, v = RangeAnswer(check, unit)
		if ok and not issecret(v) then
			if v == true and (not near or check.yards < near) then
				near = check.yards
			elseif v == false and (not far or check.yards > far) then
				far = check.yards
			end
		end
	end
	return near, far
end

-- About how far that is (nil: not known); and, when it's beyond every check, how far at least.
function S.YardsFrom(near, far)
	if near and far and far < near then
		return (near + far) / 2
	elseif near then
		return near * 0.6
	elseif far then
		return math.min(far + 5, S.OUTER_YARDS), far
	end
	return nil
end

-- An error message without the file and line in front.
local function ErrorText(err)
	return (tostring(err):gsub("^[^:]*:%d+: ", ""))
end

-- Where a unit's nameplate is on the screen, and what kind of answer that was: "onscreen",
-- "offscreen", "nil" (no nameplate), "hidden", "forbidden", "error" (and its message) or
-- "missing". (On Forever: "error", always; kept in the test to see if that ever changes.)
local function PlateSpot(unit)
	local f = Api("C_NamePlate.GetNamePlateForUnit")
	if not f then
		return "missing"
	end
	local ok, plate = pcall(f, unit)
	if not ok then
		return "error", nil, nil, ErrorText(plate)
	elseif issecret(plate) then
		return "hidden"
	elseif not plate then
		return "nil"
	elseif plate.IsForbidden and plate:IsForbidden() then
		return "forbidden"
	end
	local x, y, scale
	ok, x, y = pcall(plate.GetCenter, plate)
	if not ok then
		return "error", nil, nil, ErrorText(x)
	elseif issecret(x) or issecret(y) then
		return "hidden"
	elseif not x then
		return "nil"
	end
	ok, scale = pcall(plate.GetEffectiveScale, plate)
	if not ok or issecret(scale) then
		return "hidden"
	end
	local screen = UIParent:GetEffectiveScale()
	local nx, ny = x * scale / (GetScreenWidth() * screen), y * scale / (GetScreenHeight() * screen)
	return (nx < 0 or nx > 1 or ny < 0 or ny > 1) and "offscreen" or "onscreen", nx, ny
end

function S.Saved(key)
	local db = LT.db
	if not db then
		return {}
	end
	db[key] = type(db[key]) == "table" and db[key] or {}
	return db[key]
end
local Saved = S.Saved

---------------------------------------------------------------------------
-- The test: what answers, in and out of combat
---------------------------------------------------------------------------

-- What the test asks about every unit with a nameplate: { label, path, call(f, unit) or nil: f(unit) }.
local UNIT_CHECKS = {
	{ "UnitName", "UnitName" },
	{ "UnitLevel", "UnitLevel" },
	{ "UnitClassification", "UnitClassification" },
	{ "UnitIsDead", "UnitIsDead" },
	{ "UnitAffectingCombat", "UnitAffectingCombat" },
	{ "UnitCanAttack", "UnitCanAttack", function(f, u) return f("player", u) end },
	{ "UnitReaction", "UnitReaction", function(f, u) return f(u, "player") end },
	{ "UnitGUID", "UnitGUID" },
	{ "UnitCreatureType", "UnitCreatureType" },
	{ "targets me: UnitIsUnit(<unit>target, player)", "UnitIsUnit", function(f, u) return f(u .. "target", "player") end },
	{ "threat: UnitThreatSituation(player, <unit>)", "UnitThreatSituation", function(f, u) return f("player", u) end },
	{ "is the soft target: UnitIsUnit(<unit>, softenemy)", "UnitIsUnit", function(f, u) return f(u, "softenemy") end },
	{ "casting: UnitCastingInfo", "UnitCastingInfo" },
	{ "channeling: UnitChannelInfo", "UnitChannelInfo" },
	{ "UnitHealth", "UnitHealth" },
	{ "UnitHealthPercent", "UnitHealthPercent" },
	{ "GetRaidTargetIndex", "GetRaidTargetIndex" },
	{ "UnitPosition", "UnitPosition" },
	{ "UnitDistanceSquared", "UnitDistanceSquared" },
}
local KINDS = { "true", "false", "value", "nil", "hidden", "forbidden", "onscreen", "offscreen", "error", "missing" }
local NO_EXAMPLES = { UnitGUID = true, ["UnitPosition(player)"] = true } -- (not needed, and not for a report)

local test -- the running test
local testDriver = CreateFrame("Frame")
local resultsWindow

local function KindOf(ok, v)
	if not ok then
		return v == "missing" and "missing" or "error"
	elseif issecret(v) then
		return "hidden"
	elseif v == nil then
		return "nil"
	elseif v == true or v == false then
		return tostring(v)
	end
	return "value"
end

-- One answer for the report: counted per kind, in or out of combat, with a few examples.
local function Note(label, phase, kind, example)
	local line = test.lines[label]
	if not line then
		line = { combat = {}, calm = {}, examples = {} }
		test.lines[label] = line
		test.order[#test.order + 1] = label
	end
	line[phase][kind] = (line[phase][kind] or 0) + 1
	if example ~= nil and #line.examples < EXAMPLES then
		example = tostring(example):sub(1, 100)
		for _, seen in ipairs(line.examples) do
			if seen == example then
				return
			end
		end
		line.examples[#line.examples + 1] = example
	end
end

-- For StreamSense.lua's cast listener: noted only while a test runs.
function S.TestNote(label, kind, example)
	if test then
		Note(label, Value("UnitAffectingCombat", "player") and "combat" or "calm", kind, example)
	end
end

local function Check(label, phase, path, call, unit)
	local f = Api(path)
	if not f then
		Note(label, phase, "missing")
		return
	end
	local ok, v
	if call then
		ok, v = pcall(call, f, unit)
	else
		ok, v = pcall(f, unit)
	end
	local kind = KindOf(ok, v)
	if kind == "error" then
		Note(label, phase, kind, ErrorText(v))
	else
		Note(label, phase, kind, kind == "value" and not NO_EXAMPLES[label] and v or nil)
	end
end

local function Look()
	local phase = Value("UnitAffectingCombat", "player") and "combat" or "calm"
	test.looks[phase] = test.looks[phase] + 1
	Check("GetPlayerFacing", phase, "GetPlayerFacing", function(f) return f() end)
	Check("UnitPosition(player)", phase, "UnitPosition", nil, "player")
	Check("soft target: UnitExists(softenemy)", phase, "UnitExists", nil, "softenemy")
	if Value("UnitExists", "target") and Value("UnitCanAttack", "player", "target") then
		local spot, _, _, err = PlateSpot("target")
		Note("your target's nameplate", phase, spot, err)
		if spot == "nil" then -- (beyond nameplate range, or turned away): how far, from the range checks
			local yards, beyond = S.YardsFrom(S.Bounds("target", test.checks))
			Note("your target without a nameplate: distance", phase, yards and "value" or "nil",
				beyond and ("more than %d yd"):format(math.floor(beyond + 0.5)) or yards and ("about %d yd"):format(math.floor(yards + 0.5)) or nil)
		end
	end
	local units = 0
	for i = 1, S.MAX_UNITS do
		local unit = S.UNITS[i]
		if Value("UnitExists", unit) then
			units = units + 1
			for _, c in ipairs(UNIT_CHECKS) do
				Check(c[1], phase, c[2], c[3], unit)
			end
			local spot, nx, ny, err = PlateSpot(unit)
			Note("nameplate position: GetCenter", phase, spot, err or (nx and ("%.2f,%.2f"):format(nx, ny)))
			if Value("UnitCanAttack", "player", unit) then
				for _, check in ipairs(test.checks) do
					local ok, v = RangeAnswer(check, unit)
					local kind = KindOf(ok, v)
					Note(check.label, phase, kind, kind == "error" and ErrorText(v) or nil)
				end
			end
		end
	end
	test.most = math.max(test.most, units)
end

local function Counts(counts)
	local parts = {}
	for _, kind in ipairs(KINDS) do
		if counts[kind] then
			parts[#parts + 1] = kind .. " " .. counts[kind]
		end
	end
	return #parts > 0 and table.concat(parts, ", ") or "-"
end

local function Sum(line, phase, ...)
	local n = 0
	for i = 1, select("#", ...) do
		n = n + ((line and line[phase][select(i, ...)]) or 0)
	end
	return n
end

-- A few lines on what it means, for a quick look.
local function Summary()
	local lines, answered, calmOnly = {}, 0, 0
	for _, check in ipairs(test.checks) do
		local line = test.lines[check.label]
		if Sum(line, "combat", "true", "false") > 0 then
			answered = answered + 1
		elseif Sum(line, "calm", "true", "false") > 0 then
			calmOnly = calmOnly + 1
		end
	end
	lines[#lines + 1] = ("Distance: %d of %d range checks answered in combat, %d only out of combat."):format(answered,
		#test.checks, calmOnly)
	local spots, target = test.lines["nameplate position: GetCenter"], test.lines["your target's nameplate"]
	lines[#lines + 1] = ("Direction: nameplates on screen %d, off screen %d, hidden %d, errors %d (in combat);"
		.. " your target without a nameplate %d of %d looks."):format(Sum(spots, "combat", "onscreen"),
		Sum(spots, "combat", "offscreen"), Sum(spots, "combat", "hidden", "forbidden"), Sum(spots, "combat", "error"),
		Sum(target, "combat", "nil") + Sum(target, "calm", "nil"),
		Sum(target, "combat", unpack(KINDS)) + Sum(target, "calm", unpack(KINDS)))
	local targets = test.lines["targets me: UnitIsUnit(<unit>target, player)"]
	lines[#lines + 1] = ("Who attacks you: answered %d times in combat, hidden %d."):format(
		Sum(targets, "combat", "true", "false"), Sum(targets, "combat", "hidden"))
	if test.most == 0 then
		lines[#lines + 1] = "No nameplates seen at all: were enemy nameplates on, and mobs around?"
	end
	return lines
end

local function Report()
	local c = test.context
	local lines = {
		("Fight stream test: LefthyTools %s, WoW %s.%s, %s, %s level %s, %s (%s)"):format(LT.version, c.wow, c.build,
			c.locale, c.class, c.level, c.zone, c.where),
		("%s, %d s: %d looks, %d of them in combat; up to %d nameplates at once"):format(c.at,
			math.floor(GetTime() - test.started + 0.5), test.looks.combat + test.looks.calm, test.looks.combat, test.most),
		("Settings: enemy nameplates %s, nameplate distance %s, camera field of view %s"):format(c.plates, c.distance, c.fov),
		("Soft targeting: enemy %s, arc %s, range %s, gamepad mode %s; target nameplate kept on screen in combat %s")
			:format(c.soft, c.softArc, c.softRange, c.gamepad, c.radial),
		"",
		"Answers in combat | out of combat (value = something readable, nil = nothing, hidden = secret):",
	}
	for _, label in ipairs(test.order) do
		local line = test.lines[label]
		lines[#lines + 1] = ("%s: %s | %s%s"):format(label, Counts(line.combat), Counts(line.calm),
			#line.examples > 0 and ("   e.g. " .. table.concat(line.examples, "; ")) or "")
	end
	lines[#lines + 1] = ""
	for _, line in ipairs(Summary()) do
		lines[#lines + 1] = line
	end
	return table.concat(lines, "\n")
end

local function ResultsText()
	local list = Saved("streamTests")
	if #list == 0 then
		return L["No test yet: /lefthy stream test."]
	end
	local parts = {}
	for i = #list, 1, -1 do
		parts[#parts + 1] = list[i].text
	end
	return table.concat(parts, "\n\n")
end

local function ShowResults()
	if not resultsWindow then
		resultsWindow = LT.Window.Create("LefthyToolsStreamTestsFrame", L["Fight stream tests"], 680, 460)
		local hint = resultsWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		hint:SetPoint("TOPLEFT", 16, -34)
		hint:SetPoint("TOPRIGHT", -16, -34)
		hint:SetJustifyH("LEFT")
		hint:SetText(L["Click into the text, press Ctrl+A and then Ctrl+C to copy it."])
		LT.Window.AddCopyBox(resultsWindow)
		LT.Window.AddButton(resultsWindow, L["Clear"], function()
			wipe(Saved("streamTests"))
			ShowResults()
		end)
	end
	resultsWindow:SetBodyText(ResultsText())
	resultsWindow:Show()
end

local function StopTest(save)
	testDriver:SetScript("OnUpdate", nil)
	if S.SenseCasts then
		S.SenseCasts("test", false)
	end
	if save and test then
		local list = Saved("streamTests")
		list[#list + 1] = { at = test.context.at, text = Report() }
		while #list > KEEP_TESTS do
			table.remove(list, 1)
		end
		if resultsWindow and resultsWindow:IsShown() then
			resultsWindow:SetBodyText(ResultsText())
		end
	end
	test = nil
end

local function TestUpdate()
	local now = GetTime()
	if now >= test.nextLook then
		test.nextLook = now + S.LOOK_GAP
		Look()
	end
	if now >= test.ends then
		StopTest(true)
		M:Print("fight stream test done: /lefthy stream results shows it, ready to copy.")
	end
end

local function StartTest()
	local wow, build = GetBuildInfo()
	local _, classFile = UnitClass("player")
	local inInstance, instanceType = IsInInstance()
	test = { started = GetTime(), ends = GetTime() + TEST_TIME, nextLook = 0, checks = S.RangeChecks(),
		looks = { combat = 0, calm = 0 }, lines = {}, order = {}, most = 0,
		context = { at = date("%Y-%m-%d %H:%M"), wow = tostring(wow), build = tostring(build), locale = GetLocale(),
			class = classFile or "?", level = tostring(UnitLevel("player") or "?"), zone = GetRealZoneText() or "?",
			where = inInstance and tostring(instanceType) or "open world", plates = tostring(GetCVar("nameplateShowEnemies")),
			distance = tostring(GetCVar("nameplateMaxDistance")), fov = tostring(GetCVar("cameraFov")),
			soft = tostring(GetCVar("SoftTargetEnemy")), softArc = tostring(GetCVar("SoftTargetEnemyArc")),
			softRange = tostring(GetCVar("SoftTargetEnemyRange")),
			gamepad = tostring(InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() or false),
			radial = tostring(GetCVar("nameplateTargetRadialPosition")) } }
	testDriver:SetScript("OnUpdate", TestUpdate)
	if S.SenseCasts then
		S.SenseCasts("test", true)
	end
	M:Print(("fight stream test: %d s of notes on what the game tells addons about the mobs around you. Fight a few"
		.. " mobs; once, turn your camera away from your target for a few seconds. /lefthy stream test again stops it early.")
		:format(TEST_TIME))
	if GetCVar("nameplateShowEnemies") == "0" then
		M:Print("enemy nameplates are off: switch them on, the test needs them.")
	end
end

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------

-- /lefthy stream <me | preview | watch <name> | stop [<name>] | test | results>
function B.StreamCommand(arg)
	local cmd, rest = strtrim(arg or ""):match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()
	if cmd == "test" then
		if test then
			StopTest(true)
			M:Print("fight stream test stopped: /lefthy stream results shows it, ready to copy.")
		else
			StartTest()
		end
	elseif cmd == "results" then
		ShowResults()
	elseif (cmd == "preview" or cmd == "me") and S.OpenView then
		S.OpenView(cmd)
	elseif cmd == "watch" and S.WatchByName then
		S.WatchByName(rest)
	elseif cmd == "stop" and S.StopWatching then
		S.StopWatching(rest)
	else
		M:Print("/lefthy stream me - your own stream, live (what friends see when they watch you)")
		M:Print("/lefthy stream preview - the stream window with a made-up fight")
		M:Print("/lefthy stream watch <name> - watch a friend's fight (or click their dot on the world map)")
		M:Print("/lefthy stream stop [<name>] - stop watching (everyone, or one friend)")
		M:Print("/lefthy stream test - a minute of notes on what the game tells addons about the mobs around you")
		M:Print("/lefthy stream results - the last tests, ready to copy")
	end
end
