-- WhyPoor?: every part together, nothing stood in for: the real money data and drop data (their files), the
-- price engine, crafting, the ideas and the window, for the suite's character (a level 19 rogue of the
-- Alliance in Elwynn Forest): the ideas come, over frames and without an error; none suggests a creature
-- that isn't hostile to the Alliance (a neutral beast aside), a civilian or one of a reputation's faction; each
-- says what it rests on; the window shows them.
-- Needs: whypoor_window.lua
local suite = ...
local check, section, ns, LT = suite.check, suite.section, suite.ns, suite.LT
local W = ns.WhyPoor
local I, Dt = W.Ideas, W.Data

section("WhyPoor?: all parts together")
local ctx = W.Context()
check(ctx.level == 19 and ctx.faction == "Alliance" and ctx.map == 1429, "the character: level 19, Alliance, Elwynn Forest")

-- The data add-ons as the game would load them: their real files.
local loader = C_AddOns.LoadAddOn
local loaded = {}
C_AddOns.LoadAddOn = function(name)
	local file = ({ LefthyTools_MoneyData = "LefthyTools_MoneyData/MoneyData.lua", LefthyTools_DropData = "LefthyTools_DropData/Drops.lua" })[name]
	if not file then
		return loader(name)
	end
	loaded[name] = true
	assert(loadfile(file))()
	return true
end
Dt.db, Dt.tried, Dt.why, Dt.cache = nil, false, nil, {}
LefthyToolsMoneyData = nil
-- (the Bestiary's tests leave a small drop database of their own: the Bestiary reads it again, loading the real one)
local bestiary = LT:GetModule("bestiary")
local dropDataWas = LefthyToolsDropData
LefthyToolsDropData = nil
LT:SetModuleSetting(bestiary, "dropData", false)
LT:SetModuleSetting(bestiary, "dropData", true)

local errorsBefore = #ERRORS

I.Request()
local frames = 0
local list, ready = I.Get()
while not ready and frames < 20000 do
	Advance(1 / 60)
	frames = frames + 1
	list, ready = I.Get()
end
check(ready and #list > 0, "the ideas come: " .. #list .. " after " .. frames .. " frames")
check(#ERRORS == errorsBefore, "without an error")
check(loaded.LefthyTools_MoneyData and loaded.LefthyTools_DropData, "both data add-ons loaded when needed")

local kinds, bad, unlabeled, wrongMob = {}, {}, {}, {}
for _, idea in ipairs(list) do
	kinds[idea.kind] = (kinds[idea.kind] or 0) + 1
	if not (idea.basis and idea.confidence and idea.title and (idea.perHour or idea.once or idea.missing)) then
		bad[#bad + 1] = idea.key
	end
	for _, n in ipairs(idea.numbers or {}) do
		if not (n[1] or n.label) or not (n[2] or n.value) or not (n[3] or n.basis) then
			unlabeled[#unlabeled + 1] = idea.key
			break
		end
	end
	if idea.kind == "grind" or idea.kind == "pickpocket" then
		local creature = tonumber(idea.key:match(":(%d+)$"))
		local mob = creature and Dt.Mob(creature)
		local ok = mob and not mob.instance and not mob.civilian
			and (mob.reactA == "hostile" or (mob.reactA == "neutral" and mob.type == "Beast" and not mob.rep))
		if not ok then
			wrongMob[#wrongMob + 1] = idea.key .. " " .. tostring(mob and mob.name)
		end
	end
end
local seen = {}
for kind, n in pairs(kinds) do seen[#seen + 1] = kind .. " " .. n end
table.sort(seen)
check(kinds.grind and kinds.grind > 0, "grind spots for a level 19: " .. table.concat(seen, ", "))
check(#bad == 0, "every idea has its title, basis, confidence and a number or what it misses: " .. table.concat(bad, ", "))
check(#unlabeled == 0, "every line of the working has its label, value and basis: " .. table.concat(unlabeled, ", "))
check(#wrongMob == 0, "no mob that isn't hostile to the Alliance (a neutral beast aside), no civilian, nothing in a dungeon: "
	.. table.concat(wrongMob, ", "))
local first = list[1]
print("    first: " .. tostring(first and first.title) .. " | " .. tostring(first and first.sub))
if os.getenv("WHYPOOR_DUMP") then
	for i, idea in ipairs(list) do
		print(("#%d %s | %s | %s/h once %s | %s %s"):format(i, idea.title, idea.sub or "", tostring(idea.perHour and math.floor(idea.perHour)), tostring(idea.once), idea.basis, idea.confidence))
		for _, n in ipairs(idea.numbers or {}) do print("      " .. tostring(n[1] or n.label) .. " = " .. tostring(n[2] or n.value) .. " (" .. tostring(n[3] or n.basis) .. ")") end
		for _, w in ipairs(idea.warnings or {}) do print("      ! " .. w) end
		for _, w in ipairs(idea.why or {}) do print("      why: " .. w) end
	end
end

-- The window shows them.
W.Window.Open("ideas")
Advance(0.2)
local frame = _G.LefthyToolsWhyPoorFrame
check(frame and frame:IsShown(), "the window opens on the ideas")
check(#ERRORS == errorsBefore, "drawn without an error")
frame:Hide()

C_AddOns.LoadAddOn = loader
Dt.db, Dt.tried, Dt.why, Dt.cache = nil, false, nil, {}
LefthyToolsMoneyData, LefthyToolsDropData = nil, dropDataWas
LT:SetModuleSetting(bestiary, "dropData", false)
LT:SetModuleSetting(bestiary, "dropData", true)
