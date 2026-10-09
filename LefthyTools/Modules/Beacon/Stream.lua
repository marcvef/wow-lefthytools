local _, ns = ...
local LT = ns.LT
local L = ns.L
local M = LT:GetModule("beacon")
local B = ns.Beacon

-- Fight stream: a test behind the setting fightStream (off by default). The idea: a small view of
-- a friend's fight from above (them in the middle, the mobs around them), e.g. during your flight.
-- How it goes between friends isn't decided yet, so nothing is sent; this build finds out what
-- the game tells addons about the mobs around you, and shows the window:
--   /lefthy stream test     a minute of notes while you fight: which unit, range and nameplate
--                           calls answer, in and out of combat (a report to copy)
--   /lefthy stream results  the last tests' reports (LefthyToolsDB.streamTests)
--   /lefthy stream preview  the window with made-up mobs moving around
--   /lefthy stream me       the window with your own surroundings, live, to compare with the screen
--
-- Known from the API docs (1.60.1): health is always hidden (secret), mob positions aren't there
-- (UnitPosition answers for group members only), the combat log is closed, raid markers are
-- hidden. Found by the tests on Forever: range checks answer in combat (harmful spells you know,
-- items of known range, CheckInteractDistance), so distances work; where a nameplate is on the
-- screen can't be read at all ("Can't measure restricted regions"), so there's no left or right.
-- But a mob has a nameplate only while it's on your screen, and your own place and facing are
-- exact: the window learns where mobs are as you move and turn (see "Learning where the mobs are").
-- Up is where you face.
--
-- Cost: nothing unless a test runs or the window is open. Then a look at up to 40 nameplate
-- units every half second; the window's OnUpdate (only while it's shown) glides at most 20 dots.

local TEST_TIME = 60     -- seconds a test takes notes
local LOOK_GAP = 0.5     -- the test and the window look around this often
local MAX_UNITS = 40     -- nameplate1 .. nameplate40
local KEEP_TESTS = 3
local EXAMPLES = 3       -- example answers per line of a report
local OUTER_YARDS = 40   -- the window's outer ring
local RINGS = { 40, 30, 20, 10 }
local WIDTH, HEIGHT, RADAR = 250, 350, 220
local MAX_DOTS = 20
local NAMES = 4          -- the nearest mobs show their name
local GLIDE = 6          -- how fast dots glide to their new spot
local DEAD_FADE = 3
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local ARROW = "Interface\\Minimap\\MinimapArrow"
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local GOLD = { 1, 0.82, 0.3 }
local issecret = issecretvalue or function() return false end

-- Items with a known use range: C_Item.IsItemInRange works without owning them, if the game knows
-- the item (Forever knows classic-era ones, and they answer in combat). Measured by the tests:
-- 8149 between 5 and 10 yd, 17626 between 11 and 20, 13289 between 20 and 28.
local RANGE_ITEMS = { { 8149, 8 }, { 17626, 15 }, { 10645, 20 }, { 13289, 24 }, { 835, 30 } }
-- Classic-era items used on a target whose range isn't known yet: the test measures it against the
-- checks of known range (between the longest a unit was beyond and the shortest it was within).
-- So far 18904 and 4945 are more than 30 yd, the others more than 28: a mob further away tells more.
local CANDIDATE_ITEMS = { 18904, 4945, 4941, 10720, 7734, 2091, 17202 }
local INTERACT = { { 3, 10 }, { 2, 11 }, { 1, 28 } } -- CheckInteractDistance: duel, trade, inspect

local UNITS, TARGETS = {}, {}
for i = 1, MAX_UNITS do
	UNITS[i], TARGETS[i] = "nameplate" .. i, "nameplate" .. i .. "target"
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

-- Every way to tell how far a hostile unit is: { label, yards, path, arg, unitFirst }; with
-- candidates (the test), also the items whose range is still to be measured (yards nil).
local function RangeChecks(candidates)
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
	for _, id in ipairs(candidates and CANDIDATE_ITEMS or {}) do
		if load then
			pcall(load, id)
		end
		checks[#checks + 1] = { label = ("item %d (range to measure)"):format(id), path = "C_Item.IsItemInRange", arg = id }
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
-- range checks of known range answered that way).
local function Bounds(unit, checks)
	local near, far
	for _, check in ipairs(checks) do
		if check.yards then
			local ok, v = RangeAnswer(check, unit)
			if ok and not issecret(v) then
				if v == true and (not near or check.yards < near) then
					near = check.yards
				elseif v == false and (not far or check.yards > far) then
					far = check.yards
				end
			end
		end
	end
	return near, far
end

-- About how far that is (nil: not known); and, when it's beyond every check, how far at least.
local function YardsFrom(near, far)
	if near and far and far < near then
		return (near + far) / 2
	elseif near then
		return near * 0.6
	elseif far then
		return math.min(far + 5, OUTER_YARDS), far
	end
	return nil
end

local function Yards(unit, checks)
	return YardsFrom(Bounds(unit, checks))
end

-- An error message without the file and line in front.
local function ErrorText(err)
	return (tostring(err):gsub("^[^:]*:%d+: ", ""))
end

-- Where a unit's nameplate is on the screen (0-1 from the left and from the bottom), and what
-- kind of answer that was: "onscreen", "offscreen", "nil" (no nameplate), "hidden", "forbidden",
-- "error" (and its message) or "missing".
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


local function Saved(key)
	local db = LT.db
	if not db then
		return {}
	end
	db[key] = type(db[key]) == "table" and db[key] or {}
	return db[key]
end

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

-- More about a nameplate. The second test showed that no position can be read (GetCenter,
-- GetLeft, GetRect, GetPoint, the plate's UnitFrame, a frame anchored to it: "Can't measure
-- restricted regions"), so only what does answer is asked now. f(plate) runs in a pcall.
local PLATE_PROBES = {
	{ "nameplate: IsVisible", function(plate) return plate:IsVisible() end },
	{ "nameplate: GetEffectiveScale", function(plate) return plate:GetEffectiveScale() end },
}

local test -- the running test
local testDriver = CreateFrame("Frame")

-- Your own casts and the game's error messages (the learning below uses them for your target; the
-- test notes them): listened to only while the test runs or the window shows you.
local castWatch = CreateFrame("Frame")
local watching = { test = false, me = false }
local CAST_EVENTS = { "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
	"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" }
local function Rewatch()
	castWatch:UnregisterAllEvents()
	if watching.test or watching.me then
		for _, event in ipairs(CAST_EVENTS) do
			castWatch:RegisterUnitEvent(event, "player")
		end
		castWatch:RegisterEvent("UI_ERROR_MESSAGE")
	end
end

-- What you're doing (the window's row under the radar): the spell you're casting or channelling
-- now, and the last RECENT spells you cast, newest first, each fading over RECENT_TIME.
local RECENT, RECENT_TIME = 5, 12
local doing = { recent = {} } -- cast = { name, icon, start, finish (GetTime seconds), channel } or nil
local castNow = {}

-- The spell being cast or channelled now (none, or hidden by the game: nil).
local function ReadCast()
	doing.cast, doing.dirty = nil, false
	for _, path in ipairs({ "UnitCastingInfo", "UnitChannelInfo" }) do
		local f = Api(path)
		local ok, name, _, icon, startMs, endMs
		if f then
			ok, name, _, icon, startMs, endMs = pcall(f, "player")
		end
		if ok and name and startMs and endMs and not (issecret(name) or issecret(icon) or issecret(startMs) or issecret(endMs)) then
			castNow.name, castNow.icon, castNow.start, castNow.finish = name, icon, startMs / 1000, endMs / 1000
			castNow.channel = path == "UnitChannelInfo"
			doing.cast = castNow
			return
		end
	end
end

-- A spell you cast: in front of the recent ones.
local function Recent(spellID, at)
	local info = Value("C_Spell.GetSpellInfo", spellID)
	if type(info) ~= "table" or not info.name or issecret(info.name) or issecret(info.iconID) then
		return
	end
	local list = doing.recent
	local entry = #list >= RECENT and table.remove(list) or {}
	entry.name, entry.icon, entry.at = info.name, info.iconID, at or GetTime()
	table.insert(list, 1, entry)
end
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

-- A range check's answer for the report; known ranges also narrow down where the unit is
-- (test.within, test.beyond), for measuring the candidates' ranges.
local function NoteRange(check, phase, unit)
	local ok, v = RangeAnswer(check, unit)
	local kind = KindOf(ok, v)
	Note(check.label, phase, kind, kind == "error" and ErrorText(v) or nil)
	if check.yards then
		if kind == "true" and (not test.within or check.yards < test.within) then
			test.within = check.yards
		elseif kind == "false" and (not test.beyond or check.yards > test.beyond) then
			test.beyond = check.yards
		end
	end
	check.answer = kind
end

-- A candidate's range: more than the longest known range a unit was beyond while it said yes,
-- less than the shortest one it was within while it said no.
local function Measure(check)
	local bounds = test.bounds[check.label] or {}
	test.bounds[check.label] = bounds
	if check.answer == "true" and test.beyond then
		bounds.more = math.max(bounds.more or 0, test.beyond)
	elseif check.answer == "false" and test.within then
		bounds.less = math.min(bounds.less or math.huge, test.within)
	end
end

-- A nameplate's size against how far its mob is (from the range checks just asked): if it shrinks
-- with distance, it tells the distance exactly. Your target's apart (the game may draw it bigger).
local SIZE_BANDS = { { 8, "up to 8 yd" }, { 15, "8-15 yd" }, { 24, "15-24 yd" }, { 30, "24-30 yd" }, { math.huge, "beyond 30 yd" } }
local function NoteSize(plate, isTarget)
	local ok, scale = pcall(plate.GetEffectiveScale, plate)
	local within, beyond = test.within, test.beyond
	if not ok or issecret(scale) or not (within or beyond) then
		return
	end
	local yards = within and beyond and (within + beyond) / 2 or within and within * 0.6 or beyond + 5
	local label
	for _, band in ipairs(SIZE_BANDS) do
		if yards <= band[1] then
			label = band[2]
			break
		end
	end
	label = (isTarget and "your target " or "") .. label
	local size = test.sizes[label]
	if not size then
		size = { n = 0, sum = 0, low = scale, high = scale }
		test.sizes[label] = size
	end
	size.n, size.sum = size.n + 1, size.sum + scale
	size.low, size.high = math.min(size.low, scale), math.max(size.high, scale)
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
			local yards, beyond = Yards("target", test.checks)
			Note("your target without a nameplate: distance", phase, yards and "value" or "nil",
				beyond and ("more than %d yd"):format(beyond) or yards and ("about %d yd"):format(yards) or nil)
		end
	end
	local units = 0
	for i = 1, MAX_UNITS do
		local unit = UNITS[i]
		if Value("UnitExists", unit) then
			units = units + 1
			for _, c in ipairs(UNIT_CHECKS) do
				Check(c[1], phase, c[2], c[3], unit)
			end
			local spot, nx, ny, err = PlateSpot(unit)
			Note("nameplate position: GetCenter", phase, spot, err or (nx and ("%.2f,%.2f"):format(nx, ny)))
			local plate = Value("C_NamePlate.GetNamePlateForUnit", unit)
			if plate then
				for _, probe in ipairs(PLATE_PROBES) do
					Check(probe[1], phase, "C_NamePlate.GetNamePlateForUnit", function() return probe[2](plate, unit) end)
				end
			end
			if Value("UnitCanAttack", "player", unit) then
				test.within, test.beyond = nil, nil
				for _, check in ipairs(test.checks) do
					NoteRange(check, phase, unit)
				end
				for _, check in ipairs(test.checks) do
					if not check.yards then
						Measure(check)
					end
				end
				if plate then
					NoteSize(plate, Value("UnitIsUnit", unit, "target") == true)
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
	local lines, answered, calmOnly, known = {}, 0, 0, 0
	for _, check in ipairs(test.checks) do
		if check.yards then
			known = known + 1
			local line = test.lines[check.label]
			if Sum(line, "combat", "true", "false") > 0 then
				answered = answered + 1
			elseif Sum(line, "calm", "true", "false") > 0 then
				calmOnly = calmOnly + 1
			end
		end
	end
	lines[#lines + 1] = ("Distance: %d of %d range checks of known range answered in combat, %d only out of combat."):format(
		answered, known, calmOnly)
	local spots, target = test.lines["nameplate position: GetCenter"], test.lines["your target's nameplate"]
	local readable = {}
	for _, probe in ipairs(PLATE_PROBES) do
		local line = test.lines[probe[1]]
		if Sum(line, "combat", "value", "true") > 0 then
			readable[#readable + 1] = probe[1]
		end
	end
	lines[#lines + 1] = ("Direction: nameplates on screen %d, off screen %d, hidden %d, errors %d (in combat);"
		.. " readable in combat: %s; your target without a nameplate %d of %d looks."):format(Sum(spots, "combat", "onscreen"),
		Sum(spots, "combat", "offscreen"), Sum(spots, "combat", "hidden", "forbidden"), Sum(spots, "combat", "error"),
		#readable > 0 and table.concat(readable, ", ") or "nothing", Sum(target, "combat", "nil") + Sum(target, "calm", "nil"),
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
		("Soft targeting: enemy %s, arc %s, range %s, gamepad mode %s; nameplate scale %s to %s (from %s to %s yd), target %s; target nameplate kept on screen in combat %s")
			:format(c.soft, c.softArc, c.softRange, c.gamepad, c.maxScale, c.minScale, c.maxScaleAt, c.minScaleAt, c.targetScale, c.radial),
		"",
		"Answers in combat | out of combat (value = something readable, nil = nothing, hidden = secret):",
	}
	for _, label in ipairs(test.order) do
		local line, bounds = test.lines[label], test.bounds[label]
		local measured = ""
		if bounds and (bounds.more or bounds.less) then
			measured = ("   -> %s"):format(bounds.more and bounds.less and ("between %d and %d yd"):format(bounds.more, bounds.less)
				or bounds.more and ("more than %d yd"):format(bounds.more) or ("less than %d yd"):format(bounds.less))
		end
		lines[#lines + 1] = ("%s: %s | %s%s%s"):format(label, Counts(line.combat), Counts(line.calm),
			#line.examples > 0 and ("   e.g. " .. table.concat(line.examples, "; ")) or "", measured)
	end
	local sizes = {}
	for _, prefix in ipairs({ "", "your target " }) do
		for _, band in ipairs(SIZE_BANDS) do
			local size = test.sizes[prefix .. band[2]]
			if size then
				sizes[#sizes + 1] = ("%s%s %.3f (%.3f-%.3f, %d)"):format(prefix, band[2], size.sum / size.n, size.low, size.high, size.n)
			end
		end
	end
	if #sizes > 0 then
		lines[#lines + 1] = "nameplate size by distance (average, lowest-highest, looks): " .. table.concat(sizes, "; ")
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
	watching.test = false
	Rewatch()
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
		test.nextLook = now + LOOK_GAP
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
	test = { started = GetTime(), ends = GetTime() + TEST_TIME, nextLook = 0, checks = RangeChecks(true),
		looks = { combat = 0, calm = 0 }, lines = {}, order = {}, most = 0, bounds = {}, sizes = {},
		context = { at = date("%Y-%m-%d %H:%M"), wow = tostring(wow), build = tostring(build), locale = GetLocale(),
			class = classFile or "?", level = tostring(UnitLevel("player") or "?"), zone = GetRealZoneText() or "?",
			where = inInstance and tostring(instanceType) or "open world", plates = tostring(GetCVar("nameplateShowEnemies")),
			distance = tostring(GetCVar("nameplateMaxDistance")), fov = tostring(GetCVar("cameraFov")),
			soft = tostring(GetCVar("SoftTargetEnemy")), softArc = tostring(GetCVar("SoftTargetEnemyArc")),
			softRange = tostring(GetCVar("SoftTargetEnemyRange")),
			gamepad = tostring(InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() or false),
			maxScale = tostring(GetCVar("nameplateMaxScale")), minScale = tostring(GetCVar("nameplateMinScale")),
			maxScaleAt = tostring(GetCVar("nameplateMaxScaleDistance")), minScaleAt = tostring(GetCVar("nameplateMinScaleDistance")),
			targetScale = tostring(GetCVar("nameplateSelectedScale")),
			radial = tostring(GetCVar("nameplateTargetRadialPosition")) } }
	testDriver:SetScript("OnUpdate", TestUpdate)
	watching.test = true
	Rewatch()
	M:Print(("fight stream test: %d s of notes on what the game tells addons about the mobs around you. Fight a few"
		.. " mobs; once, turn your camera away from your target for a few seconds. /lefthy stream test again stops it early.")
		:format(TEST_TIME))
	if GetCVar("nameplateShowEnemies") == "0" then
		M:Print("enemy nameplates are off: switch them on, the test needs them.")
	end
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local win          -- built on first use
local mode         -- "preview" or "me"
local dots, dotFor = {}, {} -- the pool; mob key -> its dot
local mobs = {}    -- what the window shows now: { key, name, level, class, dead, combat, attacking, casting, yards, angle }
local looks = {}   -- "me": reused tables, one per nameplate
local checks -- "me": set when it opens
local clock, nextFeed = 0, 0

local PREVIEW_FRIEND, PREVIEW_CLASS = "Anna", "MAGE"

local function Circle(parent, layer, sublevel, size)
	local texture = parent:CreateTexture(nil, layer, nil, sublevel)
	texture:SetSize(size, size)
	texture:SetPoint("CENTER")
	local mask = parent:CreateMaskTexture()
	mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetSize(size, size)
	mask:SetPoint("CENTER")
	texture:AddMaskTexture(mask)
	return texture
end

local function ClassLabel(class)
	if class == "elite" or class == "worldboss" then
		return L["Elite"]
	elseif class == "rare" then
		return L["Rare"]
	elseif class == "rareelite" then
		return L["Rare elite"]
	end
end

local function DotOnEnter(dot)
	local mob = dot.mob
	if not mob then
		return
	end
	GameTooltip:SetOwner(dot, "ANCHOR_RIGHT")
	GameTooltip:SetText(mob.level and ("%s (%s)"):format(mob.name, mob.level) or mob.name, 1, 1, 1)
	local class = ClassLabel(mob.class)
	if class then
		GameTooltip:AddLine(class, GOLD[1], GOLD[2], GOLD[3])
	end
	if mob.dead then
		GameTooltip:AddLine(L["dead"], 0.7, 0.7, 0.7)
	else
		if mob.attacking then
			GameTooltip:AddLine(mode == "preview" and L["attacking %s"]:format(PREVIEW_FRIEND) or L["attacking you"], 1, 0.3, 0.25)
		elseif mob.combat then
			GameTooltip:AddLine(L["in combat"], 1, 0.6, 0.2)
		end
		if mob.casting then
			GameTooltip:AddLine(L["casting %s"]:format(mob.casting), 0.8, 0.6, 1)
		end
	end
	GameTooltip:AddLine(mob.beyond and L["more than %d yd away"]:format(mob.beyond)
		or mob.yards and L["about %d yd"]:format(math.floor(mob.yards + 0.5)) or L["distance unknown"], 0.8, 0.8, 0.8)
	if mob.target then
		GameTooltip:AddLine(mode == "preview" and L["%s's target"]:format(PREVIEW_FRIEND) or L["your target"], 0.8, 0.8, 0.8)
	end
	if mob.remembered then
		GameTooltip:AddLine(L["off your screen for %d s"]:format(math.floor(mob.age + 0.5)), 0.6, 0.6, 0.6)
	end
	if (mob.sure or 1) < 0.6 then
		GameTooltip:AddLine(L["direction still unsure: move and turn"], 0.6, 0.6, 0.6, true)
	end
	GameTooltip:Show()
end

local function NewDot()
	local dot = CreateFrame("Frame", nil, win.Radar)
	dot:SetSize(16, 16)
	dot.Glow = Circle(dot, "BACKGROUND", 0, 26)
	dot.Glow:SetColorTexture(0.75, 0.45, 1, 1)
	dot.Glow:SetBlendMode("ADD")
	dot.Ring = Circle(dot, "BORDER", 0, 16)
	dot.Body = Circle(dot, "ARTWORK", 0, 11)
	dot.Skull = dot:CreateTexture(nil, "OVERLAY")
	dot.Skull:SetTexture(SKULL)
	dot.Skull:SetSize(14, 14)
	dot.Skull:SetPoint("CENTER")
	dot.Name = dot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	dot.Name:SetPoint("LEFT", dot, "RIGHT", 1, 0)
	dot.Name:SetTextScale(0.85)
	dot:EnableMouse(true)
	dot:SetScript("OnEnter", DotOnEnter)
	dot:SetScript("OnLeave", function() GameTooltip:Hide() end)
	dot:Hide()
	return dot
end

local function FreeDot()
	for i = 1, MAX_DOTS do
		dots[i] = dots[i] or NewDot()
		if not dots[i].key then
			return dots[i]
		end
	end
end

local function Release(dot)
	if dot.key then
		dotFor[dot.key] = nil
	end
	dot.key, dot.mob, dot.deadAt = nil, nil, nil
	dot:Hide()
end

local function ReleaseAll()
	for _, dot in ipairs(dots) do
		Release(dot)
	end
end

-- The window's dots (a dot in use has .key and .mob; tx, ty: where it's gliding to).
function B.StreamDots()
	return dots
end

-- One scale for the rings, the dots and the map under them.
local PX_PER_YARD = (RADAR / 2 - 8) / OUTER_YARDS
local facingNow = 0 -- your facing at this look ("me"; the preview's friend faces north)

-- Where a mob goes on the radar, north up like the map: its direction (radians, right of where you
-- face) turned by your facing, and its distance (beyond every check: on the rim).
local function Spot(mob)
	local yards = mob.beyond and OUTER_YARDS or mob.yards and math.min(mob.yards, OUTER_YARDS) or OUTER_YARDS * 0.85
	local r = yards * PX_PER_YARD
	local angle = (mob.angle or 0) - facingNow -- (facing turns counterclockwise; angles go clockwise)
	return math.sin(angle) * r, math.cos(angle) * r
end

---------------------------------------------------------------------------
-- The map under the radar: your zone's map, to scale (a yard on it is a yard on the rings), north
-- up, moving with you; your arrow turns with your facing. The world map's own art
-- (C_Map.GetMapArtLayerTextures), its tiles laid out like Blizzard's (Blizzard_MapCanvasDetailLayer:
-- columns of tileWidth, rows of tileHeight, row by row), placed by the map's corners in the world
-- (C_Map.GetWorldPosFromMapPos), cut round. Without your place on a map (an instance), no map: the
-- dark rings as before.
---------------------------------------------------------------------------

local map = { tiles = {} } -- id, ok, north0, west0 (the map's top left in the world), x, y (where it's drawn)

local function MapCorner(mapID, x, y)
	local ok, _, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
	if ok and pos and not issecret(pos) then
		return pos:GetXY()
	end
end

local function SetupMap(mapID)
	map.id, map.ok, map.x = mapID, false, nil
	local layers = mapID and Value("C_Map.GetMapArtLayers", mapID)
	local layer = type(layers) == "table" and layers[1]
	local textures = layer and Value("C_Map.GetMapArtLayerTextures", mapID, 1)
	local north0, west0 = MapCorner(mapID, 0, 0)
	local north1, west1 = MapCorner(mapID, 1, 1)
	if type(textures) == "table" and north0 and north1 and west0 > west1 and north0 > north1 then
		map.ok, map.north0, map.west0 = true, north0, west0
		local sx = (west0 - west1) * PX_PER_YARD / layer.layerWidth
		local sy = (north0 - north1) * PX_PER_YARD / layer.layerHeight
		local cols = math.ceil(layer.layerWidth / layer.tileWidth)
		local rows = math.ceil(layer.layerHeight / layer.tileHeight)
		local n = 0
		for row = 1, rows do
			for col = 1, cols do
				n = n + 1
				local tile = map.tiles[n]
				if not tile then
					tile = win.Map:CreateTexture(nil, "BACKGROUND")
					tile:AddMaskTexture(win.Map.Round)
					map.tiles[n] = tile
				end
				tile:SetTexture(textures[(row - 1) * cols + col])
				tile:SetSize(layer.tileWidth * sx, layer.tileHeight * sy)
				tile:ClearAllPoints()
				tile:SetPoint("TOPLEFT", win.Map, "TOPLEFT", (col - 1) * layer.tileWidth * sx, -(row - 1) * layer.tileHeight * sy)
			end
		end
		map.count = n
	end
	for _, tile in ipairs(map.tiles) do
		tile:Hide() -- (MoveMap shows them when they're the ones in use)
	end
	if map.source == "art" then
		map.source = nil
	end
end

-- Better than the world map's art, where there is one: the minimap's own terrain tiles
-- (Data/MinimapTiles.lua, by file ID): the 3 x 3 tiles of the world's grid around you (a tile is
-- 533.33 yd; the rings reach 40), laid again only when you step onto another tile.
local TILE_YARDS = 1600 / 3
local function LayMinimap(tiles, continent, x0, y0)
	map.continent, map.x0, map.y0, map.x = continent, x0, y0, nil
	local size = TILE_YARDS * PX_PER_YARD
	map.mini = map.mini or {}
	for i = 0, 2 do
		for j = 0, 2 do
			local n = i * 3 + j + 1
			local tile = map.mini[n]
			if not tile then
				tile = win.Map:CreateTexture(nil, "BACKGROUND", nil, 1)
				tile:AddMaskTexture(win.Map.Round)
				tile:SetSize(size, size)
				map.mini[n] = tile
			end
			local file = tiles[(x0 + i) * 100 + (y0 + j)]
			if file then
				tile:SetTexture(file)
				tile:ClearAllPoints()
				tile:SetPoint("TOPLEFT", win.Map, "TOPLEFT", i * size, -j * size)
			end
			tile.has = file ~= nil
		end
	end
end

-- Which tiles show: the minimap's ("mini"), the world map's art ("art") or none.
local function UseTiles(source)
	if source ~= map.source then
		map.source, map.x = source, nil
	end
	for _, tile in ipairs(map.mini or {}) do
		tile:SetShown(source == "mini" and tile.has)
	end
	for i, tile in ipairs(map.tiles) do
		tile:SetShown(source == "art" and i <= (map.count or 0))
	end
end

-- Every frame: the map under you (where you are now), your arrow (where you face now).
local function MoveMap()
	local ok, north, west, _, continent = pcall(UnitPosition, "player")
	ok = ok and north and not (issecret(north) or issecret(west) or issecret(continent))
	local tiles = ok and ns.MINIMAP_TILES and ns.MINIMAP_TILES[continent]
	local x, y
	if tiles then
		local tx, ty = 32 - west / TILE_YARDS, 32 - north / TILE_YARDS
		local x0, y0 = math.floor(tx) - 1, math.floor(ty) - 1
		if not map.mini or x0 ~= map.x0 or y0 ~= map.y0 or continent ~= map.continent or map.source ~= "mini" then
			LayMinimap(tiles, continent, x0, y0)
			UseTiles("mini")
		end
		x, y = -(tx - x0) * TILE_YARDS * PX_PER_YARD, (ty - y0) * TILE_YARDS * PX_PER_YARD
	elseif ok and map.ok then
		if map.source ~= "art" then
			UseTiles("art")
		end
		x, y = -(map.west0 - west) * PX_PER_YARD, (map.north0 - north) * PX_PER_YARD
	end
	win.Map:SetShown(x ~= nil)
	win.Plain:SetShown(x == nil)
	if x and (not map.x or math.abs(x - map.x) + math.abs(y - map.y) > 0.2) then
		map.x, map.y = x, y
		win.Map:ClearAllPoints()
		win.Map:SetPoint("TOPLEFT", win.Radar, "CENTER", x, y)
	end
	local facing = mode == "me" and Value("GetPlayerFacing") or 0
	if facing ~= win.Me.facing then
		win.Me.facing = facing
		win.Me:SetRotation(facing)
	end
end

---------------------------------------------------------------------------
-- Learning where the mobs are ("me")
--
-- The game gives addons no direction to a mob (nameplates can't be measured), but every look says
-- something, and that adds up. Each mob is a cloud of SPOTS possible places in the world (kept by
-- GUID); every look keeps only the places that fit what's known now:
--   * how far it is: between the longest range it's beyond and the shortest it's within (with
--     SLACK: ranges count from the mob's edge);
--   * a mob with a nameplate is on your screen: within VIEW of where you face (the camera mostly
--     looks where your character faces);
--   * your target without a nameplate, nearer than nameplates reach: outside that view;
--   * the soft target (gamepad mode: the enemy the game picks in front of you): within SOFT;
--   * a mob that left your screen (still remembered for REMEMBER seconds): outside the view.
-- Your own place and facing are exact, so walking and turning narrow the cloud down: a mob that
-- stays on screen while you turn right is on your right; one that drops off as you turn left was on
-- the right. Between looks every place drifts a little (mobs move; one attacking you comes closer).
-- When too few places fit any more (it ran, the camera looked elsewhere), the cloud starts over
-- from what's known now. The dot sits in the cloud's middle: solid when the cloud points one way,
-- faint when it's still spread out.
---------------------------------------------------------------------------

local SPOTS = 48
local VIEW = math.rad(50)   -- the camera's view, either side of where you face, with some slack
local SOFT_ARCS = { [0] = math.rad(15), [1] = math.rad(35) } -- SoftTargetEnemyArc: 0 narrow, 1 front, 2 anywhere
local FRONT = math.rad(110) -- a spell you cast at it needs it in front (180 degrees), with slack
local HINT_TIME = 1.5       -- seconds a cast (or "not in front") still counts
local SLACK = 2             -- yards
local FAR = 60              -- yards: further than anything is looked at
local DRIFT = 1             -- yards a place may wander per look
local CHASE = 3             -- yards a mob attacking you comes closer per look, at most
local REMEMBER = 8          -- seconds a mob that left your screen stays, fading
local MIN_KEPT = 6          -- fewer places still fit: start over
local plateReach = 40       -- nameplateMaxDistance, read when the window opens
local soft                  -- the soft target's arc (nil: wide, tells nothing), read when the window opens
local pinned = 1            -- nameplateTargetRadialPosition: 2 keeps every mob's nameplate in combat on
                            -- screen (at its edge) while it's behind you
local hint                  -- { side = "front" or "back", at }: from your own casts at your target
local atan2 = math.atan2 or math.atan -- (Lua 5.1 / 5.3)
local clouds = {}           -- mob key -> { north = {}, west = {}, seenAt, info (the mob as last seen) }
local here = {}             -- this look: north, west, cos, sin (of your facing), facing

-- A place in the world as seen from here, where you face up: x (right), y (ahead). The same turn as
-- the minimap's (Dots.lua, B.MinimapOffset).
local function Relative(north, west)
	local east, up = here.west - west, north - here.north
	return east * here.cos + up * here.sin, up * here.cos - east * here.sin
end

-- And back: x (right), y (ahead) from here, as a place in the world.
local function World(x, y)
	local east, up = x * here.cos - y * here.sin, x * here.sin + y * here.cos
	return here.north + up, here.west - east
end

-- Does a place (x, y from here) fit what's known: between lo and hi yards away, and on the side
-- ("view", "soft", "away" or nil: any)?
local function Fits(x, y, lo, hi, side)
	local d = math.sqrt(x * x + y * y)
	if d < lo or d > hi then
		return false
	elseif not (side and here.facing) then
		return true
	end
	local off = math.abs(atan2(x, y)) -- 0 straight ahead, pi behind
	if side == "soft" then
		return off <= soft
	elseif side == "view" then
		return off <= VIEW
	elseif side == "front" then
		return off <= FRONT
	elseif side == "back" then
		return off >= math.pi - FRONT
	end
	return off >= VIEW * 0.8 -- "away"
end

-- A new place that fits.
local function Seed(cloud, i, lo, hi, side)
	local d = lo + math.random() * (hi - lo)
	local a
	if side == "soft" then
		a = (math.random() * 2 - 1) * soft
	elseif side == "view" then
		a = (math.random() * 2 - 1) * VIEW
	elseif side == "front" then
		a = (math.random() * 2 - 1) * FRONT
	elseif side == "back" then
		a = math.pi + (math.random() * 2 - 1) * FRONT
	elseif side == "away" then
		a = VIEW + math.random() * (2 * math.pi - 2 * VIEW)
	else
		a = (math.random() * 2 - 1) * math.pi
	end
	cloud.north[i], cloud.west[i] = World(math.sin(a) * d, math.cos(a) * d)
end

-- One look: drift, keep what fits, refill from that (or start over).
local function Learn(cloud, lo, hi, side, chase)
	local north, west = cloud.north, cloud.west
	local kept = 0
	for i = 1, #north do
		local x, y = Relative(north[i] + (math.random() * 2 - 1) * DRIFT, west[i] + (math.random() * 2 - 1) * DRIFT)
		local d = math.sqrt(x * x + y * y)
		if chase and d > 4 then -- (attacking you: on its way)
			local step = math.min(CHASE, d - 3) / d
			x, y = x - x * step, y - y * step
		end
		if Fits(x, y, lo, hi, side) then
			kept = kept + 1
			north[kept], west[kept] = World(x, y)
		end
	end
	if kept < MIN_KEPT then
		for i = 1, SPOTS do
			Seed(cloud, i, lo, hi, side)
		end
		return
	end
	for i = kept + 1, SPOTS do
		local j = math.random(kept)
		north[i], west[i] = north[j] + (math.random() - 0.5), west[j] + (math.random() - 0.5)
	end
end

-- The cloud's middle: direction (radians, right of ahead), mean distance, and how sure, 0 to 1:
-- how closely its places point the same way (spread over the whole view, about 50 degrees either
-- side, is still unsure; within about 15 degrees, sure).
local function Estimate(cloud)
	local sx, sy, sd, n = 0, 0, 0, #cloud.north
	for i = 1, n do
		local x, y = Relative(cloud.north[i], cloud.west[i])
		local d = math.sqrt(x * x + y * y)
		if d > 0 then
			sx, sy = sx + x / d, sy + y / d
		end
		sd = sd + d
	end
	local together = math.sqrt(sx * sx + sy * sy) / n -- 1: all one way, 0: all around
	return atan2(sx, sy), sd / n, math.max(0, math.min(1, (together - 0.85) / 0.14))
end

-- What a mob's distance says: lo to hi yards.
local function Band(near, far, onScreen)
	local lo = far and math.max(0, far - SLACK) or 0
	local hi = near and near + SLACK or onScreen and plateReach + 5 or FAR
	if lo > hi then
		lo = math.max(0, hi - SLACK)
	end
	return lo, hi
end

-- This look's place and facing (no place, in an instance: learning goes by turning only).
local function Here()
	local ok, north, west = pcall(UnitPosition, "player")
	if not ok or issecret(north) or issecret(west) or not north then
		north, west = 0, 0
	end
	local facing = Value("GetPlayerFacing")
	here.north, here.west, here.facing = north, west, facing
	here.combat, here.now = Value("UnitAffectingCombat", "player") == true, GetTime()
	here.cos, here.sin = math.cos(facing or 0), math.sin(facing or 0)
end

-- Your own casts at your target tell where it is: a harmful spell that went off needed it in front
-- of you; "Target needs to be in front of you" (or facing the wrong way) means it's behind. The
-- test notes what came (to see that these events answer, and the errors' exact words).
castWatch:SetScript("OnEvent", function(_, event, a, b, c)
	local side
	if event ~= "UNIT_SPELLCAST_SUCCEEDED" and event ~= "UI_ERROR_MESSAGE" then
		doing.dirty = a == "player" or doing.dirty -- (a cast started or stopped: the row looks again)
		return
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then -- unit, castGUID, spellID
		if a ~= "player" then
			return
		end
		if watching.me and not issecret(c) and c then
			Recent(c)
		end
		local harmful = not issecret(c) and c and Value("C_Spell.IsSpellHarmful", c)
		if harmful and Value("UnitExists", "target") and Value("UnitCanAttack", "player", "target") then
			side = "front"
		end
		if test then
			Note("your casts: UNIT_SPELLCAST_SUCCEEDED (true: harmful, at a hostile target)",
				Value("UnitAffectingCombat", "player") and "combat" or "calm", issecret(c) and "hidden" or tostring(side == "front"),
				not issecret(c) and c and Value("C_Spell.GetSpellName", c) or nil)
		end
	else -- UI_ERROR_MESSAGE: errorType, message
		if not issecret(b) and b and (b == SPELL_FAILED_UNIT_NOT_INFRONT or b == ERR_BADATTACKFACING) then
			side = "back"
		end
		if test then
			Note("the game's error messages: UI_ERROR_MESSAGE (true: not in front)",
				Value("UnitAffectingCombat", "player") and "combat" or "calm", issecret(b) and "hidden" or tostring(side == "back"),
				not issecret(b) and b or nil)
		end
	end
	if side then
		hint = hint or {}
		hint.side, hint.at = side, GetTime()
	end
end)

-- A mob seen now: its cloud learns, and it gets its direction and how sure that is.
local function LearnSeen(mob, now)
	local cloud = clouds[mob.key]
	if not cloud then
		cloud = { north = {}, west = {} }
		clouds[mob.key] = cloud
	end
	cloud.seenAt = now
	local lo, hi = Band(mob.near, mob.far, mob.onScreen)
	-- Your target's nameplate says nothing: the game keeps it up while the mob is behind the camera
	-- too (the fifth and sixth tests: always there in combat, whatever nameplateTargetRadialPosition
	-- says). With that setting on 2, every mob's in combat neither.
	local plateSays = mob.onScreen and not mob.target and not (here.combat and mob.combat and pinned >= 2)
	local side
	if mob.target and hint and here.now - hint.at <= HINT_TIME then
		side = hint.side -- (a spell you just cast at it: in front; "not in front": behind)
	elseif mob.soft and soft then
		side = "soft"
	elseif plateSays then
		side = "view"
	elseif not mob.onScreen and mob.yards and not mob.beyond and mob.yards < plateReach then
		side = "away" -- (your target, without a nameplate though near: you turned away from it)
	end
	if #cloud.north == 0 then
		-- (a far target without a nameplate: most likely where you look; your target: anywhere)
		local seed = side or (not mob.onScreen and mob.beyond and "view") or nil
		for i = 1, SPOTS do
			Seed(cloud, i, lo, hi, seed)
		end
	end
	Learn(cloud, lo, hi, side, mob.attacking)
	mob.angle, mob.est, mob.sure = Estimate(cloud)
	local info = cloud.info or {} -- (its own copy: the look's tables are reused)
	cloud.info = info
	info.name, info.level, info.class, info.combat, info.attacking = mob.name, mob.level, mob.class, mob.combat, mob.attacking
	info.dead, info.est = mob.dead, mob.est
end

-- Mobs that left your screen (not dead): remembered a while, outside your view, fading. Appended
-- to mobs from n + 1; returns the new count.
local function Remember(n, now)
	for key, cloud in pairs(clouds) do
		if cloud.seenAt ~= now then
			local age = now - cloud.seenAt
			local info = cloud.info
			if age > REMEMBER or info.dead or n >= MAX_DOTS then
				clouds[key] = nil
			else
				Learn(cloud, 0, FAR, info.est and info.est < plateReach - 3 and "away" or nil, false)
				local ghost = cloud.ghost or {}
				cloud.ghost = ghost
				ghost.key, ghost.name, ghost.level, ghost.class = key, info.name, info.level, info.class
				ghost.combat, ghost.attacking, ghost.target, ghost.casting, ghost.dead = info.combat, info.attacking, false, nil, false
				ghost.angle, ghost.est, ghost.sure = Estimate(cloud)
				ghost.yards, ghost.beyond, ghost.remembered, ghost.age = ghost.est, nil, true, age
				ghost.fade = 1 - age / REMEMBER
				n = n + 1
				mobs[n] = ghost
			end
		end
	end
	return n
end

local function Style(dot, mob, named)
	dot.mob = mob
	local r, g, b = 0.65, 0.65, 0.65 -- nearby, not fighting
	if mob.attacking then
		r, g, b = 1, 0.25, 0.2
	elseif mob.combat then
		r, g, b = 1, 0.6, 0.15
	end
	dot.Body:SetColorTexture(r, g, b, 1)
	dot.Body:SetAlpha((0.3 + 0.7 * (mob.sure or 1)) * (mob.fade or 1)) -- solid when sure; remembered ones fade
	dot.Name:SetAlpha(mob.fade or 1)
	dot.Body:SetShown(not mob.dead)
	dot.Skull:SetShown(mob.dead)
	local class = mob.class
	if class == "elite" or class == "worldboss" or class == "rareelite" then
		dot.Ring:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
		dot.Ring:Show()
	elseif class == "rare" then
		dot.Ring:SetColorTexture(0.8, 0.85, 0.95, 1)
		dot.Ring:Show()
	else
		dot.Ring:Hide()
	end
	dot.casting = mob.casting and not mob.dead
	dot.Glow:SetShown(dot.casting and true or false)
	dot.Name:SetText(named and (mob.level and ("%s %s"):format(mob.name, mob.level) or mob.name) or "")
	if mob.dead and not dot.deadAt then
		dot.deadAt = clock
	elseif not mob.dead then
		dot.deadAt = nil
		dot:SetAlpha(1)
	end
	dot.tx, dot.ty = Spot(mob)
	if dot.fresh then
		dot.x, dot.y, dot.fresh = dot.tx, dot.ty, nil
		dot:ClearAllPoints()
		dot:SetPoint("CENTER", win.Radar, "CENTER", dot.x, dot.y)
	end
	dot:Show()
end

local function Nearer(a, b)
	return (a.yards or 999) < (b.yards or 999)
end

-- The mobs onto the dots: a dot follows its mob from look to look, so it glides.
local function Apply()
	table.sort(mobs, Nearer)
	win.Hint:SetShown(mode == "me")
	for _, dot in ipairs(dots) do
		dot.seen = false
	end
	for n, mob in ipairs(mobs) do
		local dot = dotFor[mob.key]
		if not dot then
			dot = FreeDot()
			if not dot then
				break
			end
			dot.key, dot.fresh = mob.key, true
			dotFor[mob.key] = dot
		end
		dot.seen = true
		Style(dot, mob, n <= NAMES and not mob.dead)
	end
	for _, dot in ipairs(dots) do
		if dot.key and not dot.seen then
			Release(dot)
		end
	end
end

-- The bottom line: how many are on them, how many near, who's casting what.
local function Status()
	local on, near, cast = 0, 0, nil
	for _, mob in ipairs(mobs) do
		if not mob.dead then
			near = near + 1
			on = on + (mob.attacking and 1 or 0)
			if mob.casting and not cast then
				cast = L["%s casts %s"]:format(mob.name, mob.casting)
			end
		end
	end
	if near == 0 then
		return mode == "me" and L["No mobs with a nameplate near you."] or ""
	end
	local parts = { mode == "preview" and L["%d on %s"]:format(on, PREVIEW_FRIEND) or L["%d on you"]:format(on),
		L["%d near"]:format(near) }
	parts[#parts + 1] = cast
	return table.concat(parts, "  ·  ")
end

-- The preview: made-up mobs around a made-up friend, on a loop.
local PREVIEW_LOOP = 24
local preview = {}
local function PreviewMob(n, key, name, level, class)
	local mob = preview[n] or {}
	preview[n] = mob
	mob.key, mob.name, mob.level, mob.class = key, name, level, class
	mob.dead, mob.combat, mob.attacking, mob.casting, mob.target, mob.sure = false, false, false, nil, false, 1
	return mob
end

local function FeedPreview()
	local t = clock % PREVIEW_LOOP
	facingNow = 0 -- (she faces north)
	wipe(mobs)
	local leader = PreviewMob(1, "leader", L["Bandit leader"], 16, "elite")
	leader.combat, leader.attacking, leader.target = t > 2, t > 2, true
	leader.yards, leader.angle = math.max(6, 30 - t * 2), -0.6 + 0.15 * math.sin(t)
	leader.casting = (t % 8 >= 3 and t % 8 < 5) and L["Fireball"] or nil
	mobs[#mobs + 1] = leader
	if t < 18 then
		local bandit = PreviewMob(2, "bandit", L["Bandit"], 15, "normal")
		bandit.dead = t >= 14
		bandit.combat, bandit.attacking = not bandit.dead, not bandit.dead
		bandit.yards, bandit.angle = 5 + math.sin(t * 1.3), 0.35 + 0.15 * math.sin(t * 0.8)
		mobs[#mobs + 1] = bandit
	end
	local mage = PreviewMob(3, "mage", L["Bandit mage"], 15, "normal")
	mage.combat, mage.yards, mage.angle = true, 24, 1.1 + 0.03 * t
	mage.casting = (t % 6 < 2) and L["Frostbolt"] or nil
	mobs[#mobs + 1] = mage
	local gnoll = PreviewMob(4, "gnoll", L["Gnoll"], 14, "normal")
	gnoll.yards, gnoll.angle, gnoll.sure = 32 + 3 * math.sin(t * 0.4), 2.9, 0.25 -- behind, not sure yet: faint
	mobs[#mobs + 1] = gnoll
	local rare = PreviewMob(5, "rare", L["Greyfang"], 17, "rare")
	rare.yards, rare.angle = 37, 2.4 + 0.1 * math.sin(t * 0.5)
	mobs[#mobs + 1] = rare
	-- What she's doing: a Fireball every 4 s (2.5 s to cast), and the spells before it.
	local now, cycle = GetTime(), t % 4
	if cycle < 2.5 then
		local info = Value("C_Spell.GetSpellInfo", 133)
		castNow.name, castNow.icon = info and info.name or L["Fireball"], info and info.iconID
		castNow.start, castNow.finish, castNow.channel = now - cycle, now - cycle + 2.5, false
		doing.cast = castNow
	else
		doing.cast = nil
	end
	if not doing.recent[1] then
		for i, id in ipairs({ 2136, 116, 122, 133 }) do -- Fire Blast, Frostbolt, Frost Nova, Fireball (oldest last)
			Recent(id, now - 8 + i)
		end
	end
	for i, entry in ipairs(doing.recent) do
		entry.at = now - (i - 1) * 2 -- (kept from fading away in the preview)
	end
end

-- "me": the mobs with a nameplate around you (on your screen), as the game tells them, and your
-- target (also without one: turned away, or further than nameplates reach).
local function Fill(n, unit, unitTarget, targetKey, onScreen, now)
	local mob = looks[n] or {}
	looks[n] = mob
	mob.key = Value("UnitGUID", unit) or unit
	mob.name = Value("UnitName", unit) or "?"
	mob.level = Value("UnitLevel", unit)
	mob.class = Value("UnitClassification", unit)
	mob.dead = Value("UnitIsDead", unit) == true
	mob.combat = Value("UnitAffectingCombat", unit) == true
	mob.attacking = Value("UnitIsUnit", unitTarget, "player") == true
	mob.casting = Value("UnitCastingInfo", unit) or Value("UnitChannelInfo", unit)
	mob.near, mob.far = Bounds(unit, checks)
	mob.yards, mob.beyond = YardsFrom(mob.near, mob.far)
	mob.onScreen, mob.soft = onScreen, Value("UnitIsUnit", unit, "softenemy") == true
	mob.target = targetKey ~= nil and mob.key == targetKey
	mob.remembered, mob.fade = nil, nil
	LearnSeen(mob, now)
	mobs[n] = mob
	return mob.target
end

local function FeedMe()
	local n, targetShown, now = 0, false, GetTime()
	Here()
	facingNow = here.facing or 0
	local mapID = Value("C_Map.GetBestMapForUnit", "player")
	if mapID ~= map.id then
		SetupMap(mapID) -- (another zone)
	end
	local targetKey = Value("UnitExists", "target") and Value("UnitCanAttack", "player", "target")
		and (Value("UnitGUID", "target") or "target") or nil
	for i = 1, MAX_UNITS do
		local unit = UNITS[i]
		if n < MAX_DOTS and Value("UnitExists", unit) and Value("UnitCanAttack", "player", unit) then
			n = n + 1
			targetShown = Fill(n, unit, TARGETS[i], targetKey, true, now) or targetShown
		end
	end
	if targetKey and not targetShown and n < MAX_DOTS then
		n = n + 1
		Fill(n, "target", "targettarget", targetKey, false, now)
	end
	n = Remember(n, now)
	for i = #mobs, n + 1, -1 do
		mobs[i] = nil
	end
	ReadCast()
end

-- The row under the radar: the spell being cast (icon, name, a bar that fills while casting and
-- empties while channelling), and the last spells on the right, fading.
local CAST_BAR = 100
local function ShowDoing(now)
	local act, cast = win.Act, doing.cast
	if cast and now > cast.finish + 0.3 then
		cast, doing.cast = nil, nil -- (over; a new one shows on its start event or the next look)
	end
	if cast then
		local p = math.max(0, math.min(1, (now - cast.start) / math.max(0.1, cast.finish - cast.start)))
		if cast.channel then
			p = 1 - p
		end
		if act.icon ~= cast.icon then
			act.icon = cast.icon
			act.Icon:SetTexture(cast.icon)
		end
		act.Icon:Show()
		act.Name:SetText(cast.name)
		act.Bar:SetWidth(math.max(1, CAST_BAR * p))
		act.Bar:Show()
		act.BarBack:Show()
	else
		act.Icon:Hide()
		act.Name:SetText("")
		act.Bar:Hide()
		act.BarBack:Hide()
	end
	for i, icon in ipairs(act.Recent) do
		local entry = doing.recent[i]
		local age = entry and now - entry.at
		if age and age < RECENT_TIME then
			if icon.icon ~= entry.icon then
				icon.icon = entry.icon
				icon:SetTexture(entry.icon)
			end
			icon:SetAlpha(1 - 0.8 * age / RECENT_TIME)
			icon:Show()
		else
			icon:Hide()
		end
	end
end

local function OnUpdate(_, elapsed)
	clock = clock + elapsed
	if clock >= nextFeed then
		nextFeed = clock + LOOK_GAP
		if mode == "preview" then
			FeedPreview()
		else
			FeedMe()
		end
		Apply()
		win.Status:SetText(Status())
	elseif doing.dirty and mode == "me" then
		ReadCast() -- (a cast just started or stopped)
	end
	MoveMap()
	ShowDoing(GetTime())
	local k = math.min(1, elapsed * GLIDE)
	local pulse = 0.5 + 0.5 * math.sin(clock * 5)
	for _, dot in ipairs(dots) do
		if dot.key then
			local dx, dy = dot.tx - dot.x, dot.ty - dot.y
			if dx * dx + dy * dy > 0.01 then
				dot.x, dot.y = dot.x + dx * k, dot.y + dy * k
				dot:ClearAllPoints()
				dot:SetPoint("CENTER", win.Radar, "CENTER", dot.x, dot.y)
			end
			if dot.casting then
				dot.Glow:SetAlpha(0.2 + 0.5 * pulse)
			end
			if dot.deadAt then
				dot:SetAlpha(math.max(0, 1 - (clock - dot.deadAt) / DEAD_FADE))
			end
		end
	end
	win.Live.Dot:SetAlpha(0.35 + 0.65 * pulse)
end

local function Build()
	win = CreateFrame("Frame", "LefthyToolsStreamFrame", UIParent)
	win:SetSize(WIDTH, HEIGHT)
	win:SetPoint("RIGHT", -60, 40)
	win:SetFrameStrata("HIGH")
	win:SetClampedToScreen(true)
	win:EnableMouse(true)
	win:SetMovable(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		self:SetUserPlaced(false)
	end)
	win:SetScript("OnUpdate", OnUpdate) -- (only runs while it's shown)
	win:SetScript("OnHide", function()
		ReleaseAll()
		wipe(mobs)
		wipe(clouds)
		watching.me = false
		Rewatch()
		GameTooltip:Hide()
	end)
	win:Hide()
	if UISpecialFrames then
		table.insert(UISpecialFrames, "LefthyToolsStreamFrame") -- Escape closes it
	end
	LT.Window.Register("LefthyToolsStreamFrame")

	-- Dark blue-grey, thin gold edges.
	local bg = win:CreateTexture(nil, "BACKGROUND", nil, -8)
	bg:SetAllPoints()
	bg:SetColorTexture(1, 1, 1, 1)
	bg:SetGradient("VERTICAL", CreateColor(0.03, 0.04, 0.06, 0.94), CreateColor(0.07, 0.09, 0.12, 0.94))
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local edge = win:CreateTexture(nil, "BORDER")
		edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], (side == "TOP" or side == "BOTTOM") and 0.4 or 0.2)
		if side == "TOP" or side == "BOTTOM" then
			edge:SetHeight(1)
			edge:SetPoint(side .. "LEFT")
			edge:SetPoint(side .. "RIGHT")
		else
			edge:SetWidth(1)
			edge:SetPoint("TOP" .. side)
			edge:SetPoint("BOTTOM" .. side)
		end
	end

	win.Close = CreateFrame("Button", nil, win, "UIPanelCloseButtonNoScripts")
	win.Close:SetPoint("TOPRIGHT", -2, -2)
	win.Close:SetScript("OnClick", function() win:Hide() end)
	win.Title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	win.Title:SetPoint("TOPLEFT", 12, -10)
	win.Where = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	win.Where:SetPoint("TOPLEFT", win.Title, "BOTTOMLEFT", 0, -2)
	-- "● LIVE" (or DEMO), the dot breathing.
	win.Live = CreateFrame("Frame", nil, win)
	win.Live:SetSize(60, 14)
	win.Live:SetPoint("RIGHT", win.Close, "LEFT", 0, 0)
	win.Live.Text = win.Live:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	win.Live.Text:SetPoint("RIGHT")
	win.Live.Text:SetTextColor(1, 0.3, 0.25)
	local dotFrame = CreateFrame("Frame", nil, win.Live) -- (its own frame: the round mask sits in its middle)
	dotFrame:SetSize(8, 8)
	dotFrame:SetPoint("RIGHT", win.Live.Text, "LEFT", -4, 0)
	win.Live.Dot = Circle(dotFrame, "OVERLAY", 0, 8)
	win.Live.Dot:SetColorTexture(1, 0.2, 0.15, 1)

	-- The map (SetupMap, MoveMap): its own frame under the radar, its tiles cut round.
	local ring = (OUTER_YARDS * PX_PER_YARD + 8) * 2 -- (the round cut: the outer ring and a little more)
	win.Map = CreateFrame("Frame", nil, win)
	win.Map:SetSize(1, 1)
	win.Map.Round = win.Map:CreateMaskTexture()
	win.Map.Round:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	win.Map.Round:SetSize(ring, ring)
	win.Map:Hide()

	-- The radar, over the map: north up; rings every 10 yd (thin lines over the map; without one,
	-- faint discs, darker inside), labels, you in the middle (your arrow turns with your facing).
	local radar = CreateFrame("Frame", nil, win)
	win.Radar = radar
	radar:SetSize(RADAR, RADAR)
	radar:SetPoint("TOP", 0, -46)
	radar:SetFrameLevel(win.Map:GetFrameLevel() + 1)
	win.Map.Round:SetPoint("CENTER", radar, "CENTER")
	local dim = Circle(radar, "BACKGROUND", -8, ring) -- (the map a little darker: the dots stand out)
	dim:SetColorTexture(0, 0, 0, 0.35)
	win.Plain = CreateFrame("Frame", nil, radar) -- (no map: the discs)
	win.Plain:SetAllPoints()
	for i, yards in ipairs(RINGS) do
		local radius = yards * PX_PER_YARD
		local band = Circle(win.Plain, "BACKGROUND", i - 8, radius * 2)
		band:SetColorTexture(0.35, 0.45, 0.55, 0.07 + i * 0.015)
		local segments = 48
		for s = 1, segments do
			local a, b = 2 * math.pi * (s - 1) / segments, 2 * math.pi * s / segments
			local line = radar:CreateLine(nil, "ARTWORK")
			line:SetThickness(1)
			line:SetColorTexture(1, 1, 1, i == 1 and 0.35 or 0.22)
			line:SetStartPoint("CENTER", radar, math.sin(a) * radius, math.cos(a) * radius)
			line:SetEndPoint("CENTER", radar, math.sin(b) * radius, math.cos(b) * radius)
		end
		local label = radar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("CENTER", radar, "CENTER", 0, radius - 6)
		label:SetTextScale(0.75)
		label:SetAlpha(0.8)
		label:SetText(i == 1 and L["%d yd"]:format(yards) or tostring(yards))
	end
	local north = radar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	north:SetPoint("BOTTOM", radar, "TOP", 0, 1)
	north:SetText("N")
	local meDot = Circle(radar, "OVERLAY", 1, 7) -- (also there if this client lacks the arrow)
	meDot:SetColorTexture(1, 1, 1, 0.9)
	local me = radar:CreateTexture(nil, "OVERLAY", nil, 2)
	win.Me = me
	me:SetTexture(ARROW)
	me:SetSize(24, 24)
	me:SetPoint("CENTER")

	-- What you're doing (ShowDoing): the cast on the left, the last spells on the right.
	local act = CreateFrame("Frame", nil, win)
	win.Act = act
	act:SetSize(WIDTH - 24, 22)
	act:SetPoint("TOP", radar, "BOTTOM", 0, -8)
	act.Icon = act:CreateTexture(nil, "ARTWORK")
	act.Icon:SetSize(20, 20)
	act.Icon:SetPoint("LEFT")
	act.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	act.Name = act:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	act.Name:SetPoint("TOPLEFT", act.Icon, "TOPRIGHT", 5, 0)
	act.Name:SetWidth(CAST_BAR)
	act.Name:SetJustifyH("LEFT")
	act.Name:SetWordWrap(false)
	act.Name:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	act.BarBack = act:CreateTexture(nil, "BORDER")
	act.BarBack:SetColorTexture(1, 1, 1, 0.12)
	act.BarBack:SetSize(CAST_BAR, 3)
	act.BarBack:SetPoint("BOTTOMLEFT", act.Icon, "BOTTOMRIGHT", 5, 1)
	act.Bar = act:CreateTexture(nil, "ARTWORK")
	act.Bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
	act.Bar:SetSize(1, 3)
	act.Bar:SetPoint("LEFT", act.BarBack, "LEFT")
	act.Recent = {}
	for i = 1, RECENT do
		local icon = act:CreateTexture(nil, "ARTWORK")
		icon:SetSize(16, 16)
		icon:SetPoint("RIGHT", act, "RIGHT", -(i - 1) * 18, 0)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		icon:Hide()
		act.Recent[i] = icon
	end

	win.Status = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	win.Status:SetPoint("BOTTOM", 0, 12)
	win.Status:SetWidth(WIDTH - 20)
	-- Said when directions are guesses (the game gives none for some mobs).
	win.Hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	win.Hint:SetPoint("BOTTOM", win.Status, "TOP", 0, 4)
	win.Hint:SetWidth(WIDTH - 20)
	win.Hint:SetText(L["Move and turn: faint dots find their place."])
	win.Hint:Hide()
end

local function OpenWindow(newMode)
	if not win then
		Build()
	end
	ReleaseAll()
	wipe(mobs)
	mode, clock, nextFeed = newMode, 0, 0
	SetupMap(Value("C_Map.GetBestMapForUnit", "player"))
	wipe(doing.recent)
	doing.cast, doing.dirty = nil, false
	local name, classFile
	if mode == "preview" then
		name, classFile = PREVIEW_FRIEND, PREVIEW_CLASS
		win.Where:SetText(L["Westfall"])
		win.Live.Text:SetText(L["DEMO"])
		watching.me = false
		Rewatch()
	else
		checks, plateReach = RangeChecks(), tonumber(GetCVar("nameplateMaxDistance")) or 40
		wipe(clouds)
		soft = GetCVar("SoftTargetEnemy") == "1" and SOFT_ARCS[tonumber(GetCVar("SoftTargetEnemyArc"))] or nil
		pinned, hint = tonumber(GetCVar("nameplateTargetRadialPosition")) or 1, nil
		watching.me = true
		Rewatch()
		name = UnitName("player")
		local _, file = UnitClass("player")
		classFile = file
		local sub = GetSubZoneText()
		win.Where:SetText(sub ~= "" and sub or GetRealZoneText())
		win.Live.Text:SetText(L["LIVE"])
	end
	win.Title:SetText(LT.Window.ClassColorCode(classFile) .. (name or "?") .. "|r")
	win.Status:SetText("")
	win:Show()
end

---------------------------------------------------------------------------
-- Setting and commands
---------------------------------------------------------------------------

-- Beacon's OnSettingChanged: switched off, the test stops and the window closes.
function B.StreamSettingChanged()
	if M.db.fightStream then
		return
	end
	if test then
		StopTest(false)
	end
	if win and win:IsShown() then
		win:Hide()
	end
end

-- /lefthy stream <test | results | preview | me>
function B.StreamCommand(arg)
	local cmd = strtrim(arg or ""):lower()
	if not M.db.fightStream then
		M:Print("the fight stream is a test and off: switch on \"Fight stream (test)\" in the Beacon settings first.")
	elseif cmd == "test" then
		if test then
			StopTest(true)
			M:Print("fight stream test stopped: /lefthy stream results shows it, ready to copy.")
		else
			StartTest()
		end
	elseif cmd == "results" then
		ShowResults()
	elseif cmd == "preview" or cmd == "me" then
		OpenWindow(cmd)
	else
		M:Print("/lefthy stream test - a minute of notes on what the game tells addons about the mobs around you (again: stop early)")
		M:Print("/lefthy stream results - the last tests, ready to copy")
		M:Print("/lefthy stream preview - the fight stream window with made-up mobs")
		M:Print("/lefthy stream me - the window with the mobs around you, live")
	end
end
