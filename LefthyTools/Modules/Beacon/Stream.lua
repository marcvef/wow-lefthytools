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
-- hidden. The window looks the way your camera does (up = ahead): a mob's direction comes from
-- where its nameplate is on the screen, its distance from range checks (harmful spells you know,
-- items of known range, CheckInteractDistance). Whether those answer in combat is what the test
-- is for.
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
local WIDTH, HEIGHT, RADAR = 250, 300, 220
local MAX_DOTS = 20
local NAMES = 4          -- the nearest mobs show their name
local GLIDE = 6          -- how fast dots glide to their new spot
local DEAD_FADE = 3
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local ARROW = "Interface\\Minimap\\MinimapArrow"
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local GOLD = { 1, 0.82, 0.3 }
local issecret = issecretvalue or function() return false end

-- Items with a known use range (as LibRangeCheck lists them): C_Item.IsItemInRange works without
-- owning them, if the game knows the item. CheckInteractDistance: duel, trade, inspect.
local RANGE_ITEMS = { { 37727, 5 }, { 34368, 8 }, { 32321, 10 }, { 33069, 15 }, { 10645, 20 },
	{ 24268, 25 }, { 835, 30 }, { 24269, 35 }, { 28767, 40 } }
local INTERACT = { { 3, 10 }, { 2, 11 }, { 1, 28 } }

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

-- Harmful spells you know, one per range (melee counts as 5 yd), shortest first.
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
				if yards and not seen[yards] and #list < 6 then
					seen[yards] = true
					list[#list + 1] = { id = id, name = spell.name, yards = yards }
				end
			end
		end
	end
	table.sort(list, function(a, b) return a.yards < b.yards end)
	return list
end

-- Every way to tell how far a hostile unit is: { label, yards, path, arg, unitFirst }.
local function RangeChecks()
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
		checks[#checks + 1] = { label = ("item %d (about %d yd)"):format(item[1], item[2]), yards = item[2],
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

-- About how far a hostile unit is, from the range checks that answer; nil if none does.
local function Yards(unit, checks)
	local near, far -- the shortest range it's within, the longest it's beyond
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
	if near and far and far < near then
		return (near + far) / 2
	elseif near then
		return near * 0.6
	elseif far then
		return math.min(far + 5, OUTER_YARDS)
	end
	return nil
end

-- Where a unit's nameplate is on the screen (0-1 from the left and from the bottom), and what
-- kind of answer that was: "onscreen", "offscreen", "nil" (no nameplate), "hidden", "forbidden",
-- "error" or "missing".
local function PlateSpot(unit)
	local f = Api("C_NamePlate.GetNamePlateForUnit")
	if not f then
		return "missing"
	end
	local ok, plate = pcall(f, unit)
	if not ok then
		return "error"
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
		return "error"
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

-- The camera's horizontal field of view (cameraFov, degrees): how far left or right of ahead the
-- screen's edges are.
local function TanHalfFov()
	local fov = tonumber(GetCVar and GetCVar("cameraFov") or nil) or 90
	return math.tan(math.rad(fov) / 2)
end

-- Left (negative) or right of ahead, in radians, from a nameplate's spot across the screen.
local function Bearing(nx, tanHalf)
	return math.atan((nx - 0.5) * 2 * tanHalf)
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
		example = tostring(example):sub(1, 40)
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
	Note(label, phase, kind, kind == "value" and not NO_EXAMPLES[label] and v or nil)
end

local function Look()
	local phase = Value("UnitAffectingCombat", "player") and "combat" or "calm"
	test.looks[phase] = test.looks[phase] + 1
	Check("GetPlayerFacing", phase, "GetPlayerFacing", function(f) return f() end)
	Check("UnitPosition(player)", phase, "UnitPosition", nil, "player")
	if Value("UnitExists", "target") and Value("UnitCanAttack", "player", "target") then
		Note("your target's nameplate", phase, (PlateSpot("target")))
	end
	local units = 0
	for i = 1, MAX_UNITS do
		local unit = UNITS[i]
		if Value("UnitExists", unit) then
			units = units + 1
			for _, c in ipairs(UNIT_CHECKS) do
				Check(c[1], phase, c[2], c[3], unit)
			end
			local spot, nx, ny = PlateSpot(unit)
			Note("nameplate position", phase, spot, nx and ("%.2f,%.2f"):format(nx, ny))
			if Value("UnitCanAttack", "player", unit) then
				for _, check in ipairs(test.checks) do
					Note(check.label, phase, KindOf(RangeAnswer(check, unit)))
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
	local spots, target = test.lines["nameplate position"], test.lines["your target's nameplate"]
	lines[#lines + 1] = ("Direction: nameplates on screen %d, off screen %d, hidden or forbidden %d (in combat);"
		.. " your target without a nameplate %d of %d looks."):format(Sum(spots, "combat", "onscreen"),
		Sum(spots, "combat", "offscreen"), Sum(spots, "combat", "hidden", "forbidden"),
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
	test = { started = GetTime(), ends = GetTime() + TEST_TIME, nextLook = 0, checks = RangeChecks(),
		looks = { combat = 0, calm = 0 }, lines = {}, order = {}, most = 0,
		context = { at = date("%Y-%m-%d %H:%M"), wow = tostring(wow), build = tostring(build), locale = GetLocale(),
			class = classFile or "?", level = tostring(UnitLevel("player") or "?"), zone = GetRealZoneText() or "?",
			where = inInstance and tostring(instanceType) or "open world", plates = tostring(GetCVar("nameplateShowEnemies")),
			distance = tostring(GetCVar("nameplateMaxDistance")), fov = tostring(GetCVar("cameraFov")) } }
	testDriver:SetScript("OnUpdate", TestUpdate)
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
local checks, tanHalf -- "me": set when it opens
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
	GameTooltip:AddLine(mob.yards and L["about %d yd"]:format(mob.yards) or L["distance unknown"], 0.8, 0.8, 0.8)
	if not mob.angle then
		GameTooltip:AddLine(L["direction unknown: its nameplate isn't on screen"], 0.6, 0.6, 0.6, true)
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

-- Where a mob goes on the radar (up = ahead): its distance and direction; without a direction,
-- behind, spread out a little, and faint.
local function Spot(mob, n)
	local r = (mob.yards and math.min(mob.yards, OUTER_YARDS) or OUTER_YARDS * 0.85) / OUTER_YARDS * (RADAR / 2 - 8)
	local angle = mob.angle or (math.pi + ((n % 5) - 2) * 0.35)
	return math.sin(angle) * r, math.cos(angle) * r
end

local function Style(dot, mob, n, named)
	dot.mob = mob
	local r, g, b = 0.65, 0.65, 0.65 -- nearby, not fighting
	if mob.attacking then
		r, g, b = 1, 0.25, 0.2
	elseif mob.combat then
		r, g, b = 1, 0.6, 0.15
	end
	dot.Body:SetColorTexture(r, g, b, 1)
	dot.Body:SetAlpha(mob.angle and 1 or 0.45)
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
	dot.tx, dot.ty = Spot(mob, n)
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
		Style(dot, mob, n, n <= NAMES and not mob.dead)
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
	mob.dead, mob.combat, mob.attacking, mob.casting = false, false, false, nil
	return mob
end

local function FeedPreview()
	local t = clock % PREVIEW_LOOP
	wipe(mobs)
	local leader = PreviewMob(1, "leader", L["Bandit leader"], 16, "elite")
	leader.combat, leader.attacking = t > 2, t > 2
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
	gnoll.yards, gnoll.angle = 32 + 3 * math.sin(t * 0.4), nil -- behind: no nameplate on screen
	mobs[#mobs + 1] = gnoll
	local rare = PreviewMob(5, "rare", L["Greyfang"], 17, "rare")
	rare.yards, rare.angle = 37, 2.4 + 0.1 * math.sin(t * 0.5)
	mobs[#mobs + 1] = rare
end

-- "me": the mobs with a nameplate around you, as the game tells them.
local function FeedMe()
	local n = 0
	for i = 1, MAX_UNITS do
		local unit = UNITS[i]
		if Value("UnitExists", unit) and Value("UnitCanAttack", "player", unit) and n < MAX_DOTS then
			n = n + 1
			local mob = looks[n] or {}
			looks[n] = mob
			mob.key = Value("UnitGUID", unit) or unit
			mob.name = Value("UnitName", unit) or "?"
			mob.level = Value("UnitLevel", unit)
			mob.class = Value("UnitClassification", unit)
			mob.dead = Value("UnitIsDead", unit) == true
			mob.combat = Value("UnitAffectingCombat", unit) == true
			mob.attacking = Value("UnitIsUnit", TARGETS[i], "player") == true
			mob.casting = Value("UnitCastingInfo", unit) or Value("UnitChannelInfo", unit)
			mob.yards = Yards(unit, checks)
			local spot, nx = PlateSpot(unit)
			mob.angle = spot == "onscreen" and Bearing(nx, tanHalf) or nil
			mobs[n] = mob
		end
	end
	for i = #mobs, n + 1, -1 do
		mobs[i] = nil
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
	end
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

	-- The radar: distance bands (faint discs, darker inside), a cross, labels, you in the middle.
	local radar = CreateFrame("Frame", nil, win)
	win.Radar = radar
	radar:SetSize(RADAR, RADAR)
	radar:SetPoint("TOP", 0, -46)
	for i, yards in ipairs(RINGS) do
		local size = RADAR * yards / OUTER_YARDS
		local band = Circle(radar, "BACKGROUND", i - 8, size)
		band:SetColorTexture(0.35, 0.45, 0.55, 0.07 + i * 0.015)
		local label = radar:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		label:SetPoint("CENTER", radar, "CENTER", 0, size / 2 - 7)
		label:SetTextScale(0.8)
		label:SetText(i == 1 and L["%d yd"]:format(yards) or tostring(yards))
	end
	for _, vertical in ipairs({ true, false }) do
		local line = radar:CreateTexture(nil, "BORDER")
		line:SetColorTexture(1, 1, 1, 0.06)
		line:SetSize(vertical and 1 or RADAR, vertical and RADAR or 1)
		line:SetPoint("CENTER")
	end
	local ahead = radar:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	ahead:SetPoint("BOTTOM", radar, "TOP", 0, 1)
	ahead:SetText(L["ahead"])
	local meDot = Circle(radar, "OVERLAY", 1, 7) -- (also there if this client lacks the arrow)
	meDot:SetColorTexture(1, 1, 1, 0.9)
	local me = radar:CreateTexture(nil, "OVERLAY", nil, 2)
	me:SetTexture(ARROW)
	me:SetSize(24, 24)
	me:SetPoint("CENTER")

	win.Status = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	win.Status:SetPoint("BOTTOM", 0, 12)
	win.Status:SetWidth(WIDTH - 20)
end

local function OpenWindow(newMode)
	if not win then
		Build()
	end
	ReleaseAll()
	wipe(mobs)
	mode, clock, nextFeed = newMode, 0, 0
	local name, classFile
	if mode == "preview" then
		name, classFile = PREVIEW_FRIEND, PREVIEW_CLASS
		win.Where:SetText(L["Westfall"])
		win.Live.Text:SetText(L["DEMO"])
	else
		checks, tanHalf = RangeChecks(), TanHalfFov()
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
