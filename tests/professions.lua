-- Chronicle: the Professions tab, with made-up lists. C.Recipes is the tab's whole source, so a fake one
-- makes every expected row certain; the last section draws the real C.Recipes' data, when it's there.
-- Needs: no other file.
local suite = ...
local check, section, ns, LT = suite.check, suite.section, suite.ns, suite.LT
local C = ns.Chronicle

local function plain(text)
	return ((text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- The game's item data. Reagents and what's crafted, in ids nothing else uses.
for id, item in pairs({
	[95001] = { name = "Barbaric Harness", quality = 2 }, [95002] = { name = "Dark Leather Tunic", quality = 2 },
	[95003] = { name = "Rugged Leather Pants", quality = 3 }, [95004] = { name = "Dark Leather Pants", quality = 2 },
	[95005] = { name = "Fine Leather Boots", quality = 2 }, [95006] = { name = "Leather Cap", quality = 1 },
	[95007] = { name = "Medium Armor Kit", quality = 1, classID = 7, subClassID = 5 },
	[95008] = { name = "Heavy Armor Kit", quality = 1, classID = 7, subClassID = 5 },
	[95009] = { name = "Leg Potion", quality = 1, classID = 0, subClassID = 1 },
	[95011] = { name = "Soft Boots", quality = 2, equipLoc = "INVTYPE_FEET" }, -- (not in the data's table of items)
	[95012] = { name = "Odd Thing", quality = 1, classID = 15, subClassID = 9 }, -- (a subclass without a name: the class's)
	[95101] = { name = "Medium Leather", quality = 1 }, [95102] = { name = "Fine Thread", quality = 1 },
	[95201] = { name = "Light Bag", quality = 1 },
}) do
	ITEMS[id] = item
end

-- Leatherworking: gear in the wrong order on purpose, chest and robe, things without slots.
local LEATHER, ENCHANTING, TAILORING, HERBALISM, MINING = 165, 333, 197, 182, 186
local PANTS = { spell = 91003, item = 95003, count = 1, slot = 7, ilvl = 28, quality = 3, low = 180, high = 220, cat = 9,
	reagents = { { item = 95101, n = 6 }, { 95102, 2 } } } -- (both shapes the contract's words allow)
local HARNESS = { spell = 91001, item = 95001, count = 1, slot = 5, ilvl = 28, quality = 2, low = 200, high = 260, reagents = {} }
local TUNIC = { spell = 91002, item = 95002, count = 1, slot = 20, ilvl = 20, quality = 2, low = 100, high = 140, reagents = { { 95101, 3 } } }
local DARK_PANTS = { spell = 91004, item = 95004, count = 1, slot = 7, ilvl = 25, quality = 2, low = 120, high = 160, reagents = { { 95101, 1 } } }
local BOOTS = { spell = 91005, item = 95005, count = 1, slot = 8, ilvl = 18, quality = 2, low = 90, high = 130, reagents = { { 95101, 1 } } }
local CAP = { spell = 91006, item = 95006, count = 1, slot = 1, ilvl = 12, quality = 1, low = 250, high = 290, reagents = { { 95101, 1 } } }
local MEDIUM_KIT = { spell = 91007, item = 95007, count = 2, low = 100, high = 130, reagents = { { 95101, 1 } } }
local HEAVY_KIT = { spell = 91008, item = 95008, count = 1, slot = 0, low = 150, high = 180, reagents = { { 95101, 1 } } } -- (slot 0: not gear)
local POTION = { spell = 91009, item = 95009, count = 1, low = 240, high = 280, reagents = { { 95101, 1 } } }
local UNKNOWN_ITEM = { spell = 91010, item = 95010, count = 1, low = 1, high = 2, reagents = { { 95101, 1 } } } -- (no such item in this client)
local SOFT_BOOTS = { spell = 91011, item = 95011, count = 1, low = 60, high = 90, reagents = { { 95101, 1 } } }
local ODD = { spell = 91012, item = 95012, count = 1, low = 5, high = 10, reagents = { { 95101, 1 } } }
local ENCHANT_A = { spell = 92001, cat = 21, low = 100, high = 140, reagents = { { 95101, 1 } } }
local ENCHANT_B = { spell = 92002, cat = 21, low = 200, high = 240, reagents = { { 95101, 1 } } }
local ENCHANT_C = { spell = 92003, cat = 22, low = 50, high = 90, reagents = { { 95101, 1 } } }
local ENCHANT_D = { spell = 92004, low = 10, high = 20, reagents = { { 95101, 1 } } } -- (no category)
local BAG = { spell = 93001, item = 95201, count = 1, slot = 18, ilvl = 5, quality = 1, low = 10, high = 40, reagents = { { 95102, 1 } } }
for spell, name in pairs({ [91003] = "Spell: Rugged Pants", [92001] = "Enchant Boots", [92002] = "Enchant Chest", [92003] = "Enchant Bracer", [92004] = "Enchant Odd" }) do
	SPELL_NAMES[spell] = name
end

local RECIPES = {
	[LEATHER] = { BOOTS, DARK_PANTS, MEDIUM_KIT, HARNESS, UNKNOWN_ITEM, CAP, PANTS, HEAVY_KIT, POTION, TUNIC, SOFT_BOOTS, ODD },
	[ENCHANTING] = { ENCHANT_C, ENCHANT_A, ENCHANT_D, ENCHANT_B },
	[TAILORING] = { BAG },
}
-- 600 recipes of one profession, in one group.
local BIG = {}
for i = 1, 600 do
	ITEMS[96000 + i] = { name = "Robe " .. i, quality = 1 }
	BIG[i] = { spell = 97000 + i, item = 96000 + i, count = 1, slot = 5, ilvl = i, quality = 1, low = i, high = i + 40, reagents = { { 95102, 1 } } }
end
RECIPES[TAILORING + 1] = BIG

local function set(...)
	local known = {}
	for _, recipe in ipairs({ ... }) do known[recipe.spell] = true end
	return known
end
local ANNA = { id = "anna", name = "Anna Brook", classFile = "MAGE", level = 41, account = "annie", skill = 245, max = 300, updated = MOCK_EPOCH,
	known = set(PANTS, HARNESS, CAP, POTION, ODD) }
local BOB = { id = "bob", name = "Bob Stone", classFile = "WARRIOR", level = 33, account = "bobby", skill = 180, max = 225, updated = MOCK_EPOCH - 5 * 86400,
	known = set(PANTS, DARK_PANTS) }
local ALT = { id = "alt", name = "Annalt", classFile = "MAGE", level = 18, account = "annie", skill = 95, max = 150, updated = MOCK_EPOCH, known = {} }
local ME = { id = "me", name = "Cara Moss", classFile = "ROGUE", level = 9, account = "you", mine = true, skill = 62, max = 75, updated = MOCK_EPOCH,
	known = set(TUNIC, BOOTS, DARK_PANTS, MEDIUM_KIT, HEAVY_KIT, UNKNOWN_ITEM, SOFT_BOOTS) }

local NAMES = { [171] = "Alchemy", [LEATHER] = "Leatherworking", [ENCHANTING] = "Enchanting", [TAILORING] = "Tailoring", [TAILORING + 1] = "Big Tailoring",
	[HERBALISM] = "Herbalism", [MINING] = "Mining" }
local world = { people = {} } -- line -> people in it
local revision = 1
local calls = { Parse = 0, Professions = 0, People = 0, Search = 0, Crafters = 0 }
local fake = {
	Parse = function(line) calls.Parse = calls.Parse + 1; return RECIPES[line] or {} end,
	RecipeOf = function(spell)
		for line, list in pairs(RECIPES) do
			for _, recipe in ipairs(list) do
				if recipe.spell == spell then return recipe, line end
			end
		end
	end,
	Professions = function()
		calls.Professions = calls.Professions + 1
		local list = {}
		for _, line in ipairs({ 171, LEATHER, ENCHANTING, TAILORING, TAILORING + 1, HERBALISM, MINING }) do
			list[#list + 1] = { line = line, name = NAMES[line], icon = 1000 + line, count = #(world.people[line] or {}),
				gathering = line == HERBALISM or line == MINING }
		end
		return list
	end,
	People = function(line) calls.People = calls.People + 1; return world.people[line] or {} end,
	Search = function(text)
		calls.Search = calls.Search + 1
		local out = {}
		for _, line in ipairs({ LEATHER, ENCHANTING, TAILORING }) do
			for _, recipe in ipairs(RECIPES[line]) do
				local item = recipe.item and ITEMS[recipe.item]
				local name = (item and item.name or SPELL_NAMES[recipe.spell] or ""):lower()
				if name:find(text:lower(), 1, true) then
					local who = {}
					for _, person in ipairs(world.people[line] or {}) do
						if person.known[recipe.spell] then who[#who + 1] = person end
					end
					out[#out + 1] = { recipe = recipe, line = line, people = who }
				end
			end
		end
		return out
	end,
	Crafters = function(spell)
		calls.Crafters = calls.Crafters + 1
		local out = {}
		for _, person in ipairs({ ANNA, BOB, ALT, ME }) do
			if person.known[spell] then out[#out + 1] = person end
		end
		return out
	end,
	Revision = function() return revision end,
}
local realRecipes, realData = C.Recipes, ns.RecipeData
C.Recipes = fake
ns.RecipeData = { categories = { [21] = { "Boots and such", "Stiefel" }, [22] = { "Armour bits", "Rüstung" } } }

local win, v
local function open()
	C.Open("professions")
	win = LefthyToolsChronicleFrame
	v = C.ProfessionsView()
end
local function moved() -- the lists changed: the tab follows
	revision = revision + 1
	Advance(4)
end
local function button(line)
	for _, b in ipairs(v.profs) do
		if b.line == line and b:IsShown() then return b end
	end
end
local function personRow(id)
	for _, row in ipairs(v.people.rows) do
		local e = row:IsShown() and row.entry
		if e and (e.id == id or (id == "everyone" and e.everyone)) then return row end
	end
end
local function recipeRow(spell)
	for _, row in ipairs(v.middle.rows) do
		local e = row:IsShown() and row.entry
		if e and e.recipe and e.recipe.spell == spell then return row end
	end
end
local function headerRow(label)
	for _, row in ipairs(v.middle.rows) do
		local e = row:IsShown() and row.entry
		if e and e.header and e.label == label then return row end
	end
end
-- The middle as lines: "# Label" for a header, a spell's number for a recipe.
local function outline()
	local out = {}
	for _, e in ipairs(v.middle.entries) do
		out[#out + 1] = e.header and ("# " .. e.label) or tostring(e.recipe.spell)
	end
	return table.concat(out, " ")
end
local function hover(spell) local row = recipeRow(spell); row._scripts.OnEnter(row) end

section("Chronicle: the Professions tab, its place in the window")
do
	open()
	check(win:IsShown() and not win.Tabs.professions:IsEnabled() and win.Tabs.professions:GetText() == "Professions"
		and not win.Picker:IsShown() and not win.Scroll:IsShown() and v.root:IsShown(),
		"it opens on the tab: its button greyed out, no picker, no journal text under it")
	local function left(b)
		local _, _, _, x = b:GetPoint(1)
		return win:GetWidth() + x - b:GetWidth()
	end
	local _, _, x = win.Picker:GetPoint(1)
	local order = { "friends", "news", "compare", "graphs", "stats", "timeline", "professions" }
	local fits = x + win.Picker:GetWidth() + 4 <= left(win.Tabs.professions) and left(win.Tabs.friends) + win.Tabs.friends:GetWidth() <= win:GetWidth() - 10
	for i = 2, #order do
		fits = fits and left(win.Tabs[order[i]]) + win.Tabs[order[i]]:GetWidth() < left(win.Tabs[order[i - 1]])
	end
	check(fits, "seven tabs and the picker fit in the row without overlapping")
	for key, b in pairs(win.Tabs) do
		check(#b:GetText() * 6 <= b:GetWidth() - 6, "its label fits (6 px a letter): " .. key)
	end
	check(win.Picker.List:GetWidth() == 240, "the picker's list keeps its width")
	win.Tabs.timeline:Click()
	check(win.Picker:IsShown() and win.Scroll:IsShown() and not v.root:IsShown(), "another page: the picker and the text back, the tab gone")
	win.Tabs.professions:Click()
	check(v.root:IsShown() and not win.Scroll:IsShown(), "and back")
	win:Hide()
	check(not v.root:IsShown(), "closing the window closes the tab")
	C.Toggle()
	check(win:IsShown() and v.root:IsShown() and not win.Picker:IsShown(), "opening the window again: still on it")
end

section("Chronicle: the Professions tab, empty")
do
	check(v.Message:IsShown() and v.Message:GetText():find("Friends appear when they've updated LefthyTools", 1, true)
		and #v.people.entries == 0 and #v.middle.entries == 0, "nobody yet: a friendly line, no rows")
	check(#v.profs == 7 and button(171).Count:GetText() == "0" and button(171).Name:GetText() == "Alchemy" and button(171).Icon.path == 1171
		and button(171).Picked.shown, "a button per profession, with its icon and how many have it; the first chosen")
	local saved = C.Recipes
	C.Recipes = nil
	C.DrawProfessions(win.Inset, 770, 534)
	check(v.Message:IsShown() and #v.people.entries == 0, "without C.Recipes at all it says the same")
	C.Recipes = saved
	C.DrawProfessions(win.Inset, 770, 534)
end

section("Chronicle: the Professions tab, defaults")
do
	world.people[TAILORING] = { ANNA }
	world.people[LEATHER] = { ANNA, BOB, ALT }
	moved()
	check(button(LEATHER).Count:GetText() == "3", "the counts follow")
	check(button(LEATHER).Picked.shown and not button(171).Picked.shown, "chosen by itself: the first with people")
	check(personRow("everyone").Picked.shown, "nobody's mine: Everyone")
	world.people[ENCHANTING] = { ANNA, ME }
	moved()
	check(button(ENCHANTING).Picked.shown and personRow("me").Picked.shown, "one of mine beats it, and I'm selected in it")
	button(TAILORING):Click()
	check(button(TAILORING).Picked.shown and not button(ENCHANTING).Picked.shown and personRow("everyone").Picked.shown,
		"a click chooses; no profession of mine there: Everyone")
	world.people[LEATHER] = { ANNA, BOB, ALT, ME }
	moved()
	check(button(TAILORING).Picked.shown, "chosen stays chosen when the lists move")
	button(LEATHER):Click()
	check(personRow("me").Picked.shown and not personRow("everyone").Picked.shown, "a profession I have: I'm selected")
end

section("Chronicle: the Professions tab, people")
do
	local rows = v.people.entries
	check(rows[1].everyone and rows[2].id == "anna" and rows[3].id == "bob" and rows[4].id == "alt" and rows[5].id == "me",
		"Everyone, then R.People's order")
	local anna, bob, me = personRow("anna"), personRow("bob"), personRow("me")
	check(personRow("everyone").Name:GetText() == "Everyone", "the first row says so")
	check(anna.Name:GetText():find("^|cff40c7eb") and plain(anna.Name:GetText()) == "Anna Brook" and anna.Skill:GetText() == "245",
		"a name in its class colour, the skill on the right, got " .. tostring(anna.Name:GetText()))
	check(anna.Sub:GetText() == "annie - lvl 41", "under it the account and level, got " .. tostring(anna.Sub:GetText()))
	check(bob.Sub:GetText() == "bobby - lvl 33 - 5 days ago", "a list more than a few days old says how old, got " .. tostring(bob.Sub:GetText()))
	check(me.Sub:GetText() == "you - lvl 9", "mine, got " .. tostring(me.Sub:GetText()))
	anna:Click()
	check(anna.Picked.shown and not me.Picked.shown and outline():find("91003", 1, true) and not outline():find("91002", 1, true),
		"a click selects them: their list")
end

section("Chronicle: the Professions tab, groups and sorting")
do
	personRow("everyone"):Click()
	local text = outline()
	local want = table.concat({ "# Head 91006", "# Chest 91001 91002", "# Legs 91003 91004", "# Feet 91005 91011",
		"# Cloth 91008 91007", "# Miscellaneous 91012", "# Potion 91009", "# Other 91010" }, " ")
	check(text == want, "gear by slot in the sheet's order, chest and robe in one, highest ilvl first; the rest by type, then by skill; "
		.. "an item the client doesn't know under Other, got: " .. text)
	local pants = recipeRow(91003)
	check(plain(pants.Name:GetText()) == "Rugged Leather Pants" and pants.Name:GetText():find("^|cff") and pants.Icon.path == 96003 and pants.Right:GetText() == "ilvl 28",
		"a row: the icon, the name in its quality's colour, the ilvl")
	check(pants.Count:GetText() == "2" and pants.Count:IsShown() and not pants.Dot:IsShown(), "under Everyone: how many know it, no dot")
	check(recipeRow(91007).Right:GetText() == "" and plain(recipeRow(91010).Name:GetText()) == "Spell 91010",
		"no ilvl for what isn't gear; an unknown item by its spell's name")
	local legs = headerRow("Legs")
	check(legs.Toggle:IsShown() and legs.Toggle.path:find("Minus", 1, true) and legs.Right:GetText() == "2" and plain(legs.Name:GetText()) == "Legs",
		"a group header: open, its name, how many")
	legs:Click()
	check(outline():find("# Legs # Feet", 1, true) and headerRow("Legs").Toggle.path:find("Plus", 1, true), "a click folds it")
	personRow("anna"):Click()
	check(not outline():find("91003", 1, true) and outline():find("# Legs", 1, true), "still folded for someone else with those")
	headerRow("Legs"):Click()
	check(outline():find("# Legs 91003", 1, true), "and opens again")
end

section("Chronicle: the Professions tab, difficulty")
do
	local function dot(spell)
		local row = recipeRow(spell)
		return row.Dot:IsShown() and table.concat(row.Dot.vertex, ",", 1, 3)
	end
	check(dot(91006) == "1,0.5,0.25", "under their skill's low: orange (245 < 250), got " .. tostring(dot(91006)))
	check(dot(91009) == "1,1,0", "under the middle: yellow (245 < 260)")
	check(dot(91001) == "0.25,0.75,0.25", "under high: green (245 < 260, 245 >= 230)")
	check(dot(91003) == "0.5,0.5,0.5", "above: grey")
	check(not recipeRow(91003).Count:IsShown(), "no count under a person")
	hover(91001)
	check(plain(v.Difficulty:GetText()) == "Anna Brook finds it: easy (green)", "the details say so, got " .. tostring(v.Difficulty:GetText()))
	personRow("everyone"):Click()
	hover(91001)
	check(v.Difficulty:GetText() == "", "under Everyone no such line")
	-- A recipe with no numbers: no dot.
	local low, high = HARNESS.low, HARNESS.high
	HARNESS.low, HARNESS.high = nil, nil
	personRow("anna"):Click()
	check(not recipeRow(91001).Dot:IsShown(), "no skill numbers: no dot")
	HARNESS.low, HARNESS.high = low, high
end

section("Chronicle: the Professions tab, details")
do
	local tip
	local bags = BAGS[0]
	BAGS[0] = {}
	for slot = 1, 12 do BAGS[0][slot] = 95101 end
	personRow("anna"):Click()
	check(not v.DetailBody:IsShown() and v.Hint:IsShown(), "nothing hovered yet: a hint")
	hover(91003)
	tip = LefthyToolsProfessionsTooltip
	check(v.DetailBody:IsShown() and not v.Hint:IsShown() and plain(v.Name:GetText()) == "Rugged Leather Pants" and v.Icon.path == 96003,
		"hovering fills them at once: icon, name")
	check(tip and tip:GetParent() == v.TipClip and tip._owner == v.TipClip and tip._anchor == "ANCHOR_NONE" and tip._hyperlink == "item:95003" and tip:IsShown()
		and tip._strata == v.root:GetFrameStrata() and tip._clamped == false and v.TipClip._clips == true,
		"the real item's tooltip, inside the panel, in the window's strata, clipped")
	-- Too wide: scaled to the panel. Too tall: cut at what's left.
	tip:SetSize(v.detailW * 2, 100)
	check(tip:GetScale() == 0.5 and v.TipClip:GetHeight() == 50, "wider than the panel: scaled down, got " .. tip:GetScale() .. ", " .. v.TipClip:GetHeight())
	tip:SetSize(200, 5000)
	check(tip:GetScale() == 1 and v.TipClip:GetHeight() == v.tipRoom and v.tipRoom > 100 and v.tipRoom < v.detailH, "taller than the room: cut")
	tip:SetSize(200, 150)
	check(v.TipClip:GetHeight() == 150 and v.Below:GetPoint(1) == "TOPLEFT" and select(2, v.Below:GetPoint(1)) == v.TipClip,
		"it grows with the tooltip, and what's under it follows")

	-- Reagents.
	local leather, thread = v.reagents[1], v.reagents[2]
	check(v.Needs:IsShown() and leather:IsShown() and thread:IsShown() and not v.reagents[3]:IsShown(), "Needs: a row per reagent")
	check(leather.Name:GetText():find("Medium Leather", 1, true) and leather.Icon.path == 96101 and leather.Count:GetText() == "6"
		and plain(leather.Have:GetText()) == "(you: 12)" and not leather.Have:GetText():find("|cffff4040", 1, true),
		"its icon, name, how many, how many I have, got " .. tostring(leather.Have:GetText()))
	check(thread.Count:GetText() == "2" and plain(thread.Have:GetText()) == "(you: 0)" and thread.Have:GetText():find("|cffff4040", 1, true), "too few: red")
	BAGS[0][13] = 95102
	Fire("BAG_UPDATE_DELAYED")
	Advance(0.3)
	check(plain(thread.Have:GetText()) == "(you: 1)", "the bags changing updates it")
	thread._scripts.OnEnter(thread)
	check(TOOLTIP.owner == thread and TOOLTIP.link == "item:95102" and TOOLTIP.shown, "a reagent hovered: its normal tooltip")
	thread._scripts.OnLeave(thread)
	check(not TOOLTIP.shown, "and gone")
	local count = C_Item.GetItemCount
	C_Item.GetItemCount = function() return SECRET end
	hover(91001)
	hover(91003)
	check(leather.Have:GetText() == "", "a secret count: not shown")
	C_Item.GetItemCount = count

	-- Who else.
	check(plain(v.Also:GetText()) == "Also known by: Bob Stone", "also known by, not the one selected, got " .. tostring(v.Also:GetText()))
	hover(91001)
	check(v.Also:GetText() == "", "nobody else: no line")
	check(not v.Needs:IsShown() and not v.reagents[1]:IsShown(), "no reagents: no Needs")
	personRow("everyone"):Click()
	hover(91003)
	check(plain(v.Also:GetText()) == "Known by: Anna Brook, Bob Stone", "under Everyone all of them")

	-- Hover and pin.
	local pants, harness = recipeRow(91003), recipeRow(91001)
	harness._scripts.OnEnter(harness)
	check(plain(v.Name:GetText()) == "Barbaric Harness", "the mouse moves on: the details follow")
	pants:Click()
	check(pants.Picked.shown and plain(v.Name:GetText()) == "Rugged Leather Pants", "a click shows it and marks it")
	harness._scripts.OnEnter(harness)
	check(plain(v.Name:GetText()) == "Rugged Leather Pants" and tip._hyperlink == "item:95003", "clicked: it stays while the mouse moves on")
	harness:Click()
	check(plain(v.Name:GetText()) == "Barbaric Harness" and harness.Picked.shown and not pants.Picked.shown, "another clicked: that one")
	harness:Click()
	check(not harness.Picked.shown and plain(v.Name:GetText()) == "Barbaric Harness", "clicked again: free, it stays until the next hover")
	pants._scripts.OnEnter(pants)
	check(plain(v.Name:GetText()) == "Rugged Leather Pants", "and hovering works again")
	pants:Click()
	personRow("bob"):Click()
	check(not v.DetailBody:IsShown() and v.Hint:IsShown(), "another person: the details empty")

	-- An enchant: the spell's tooltip, no item.
	world.people[ENCHANTING] = { ANNA, ME }
	ANNA.known[92001] = true
	button(ENCHANTING):Click()
	personRow("anna"):Click()
	hover(92001)
	check(tip._spellID == 92001 and tip._hyperlink == nil and tip:IsShown() and plain(v.Name:GetText()) == "Enchant Boots" and v.Icon.path == 192001,
		"an enchant: the spell's tooltip, its name and icon")
	ANNA.known[92001] = nil

	-- A window closed and opened: the tooltip back with it.
	button(LEATHER):Click()
	personRow("anna"):Click()
	recipeRow(91003):Click()
	win:Hide()
	check(not tip:IsShown(), "closed: the tooltip goes")
	C.Toggle()
	v.root._scripts.OnShow(v.root) -- (the game: when the tab comes in sight)
	check(tip:IsShown() and tip._hyperlink == "item:95003" and plain(v.Name:GetText()) == "Rugged Leather Pants", "opened: the clicked recipe is still there")
	recipeRow(91003):Click()
	BAGS[0] = bags
end

section("Chronicle: the Professions tab, search")
do
	personRow("anna"):Click()
	recipeRow(91003):Click()
	local before, outlineBefore = calls.Search, outline()
	v.Box:SetText("l")
	Advance(0.1)
	v.Box:SetText("le")
	Advance(0.1)
	v.Box:SetText("leather")
	Advance(0.25)
	check(calls.Search == before and outline() == outlineBefore and v.Clear:IsShown(), "still typing: not searched yet")
	Advance(0.1)
	check(calls.Search == before + 1 and outline() == "# Leatherworking 91005 91004 91006 91003 91002", "searched once, about 0.3 s after the last key: by profession, got " .. outline())
	check(not v.DetailBody:IsShown(), "the details empty")
	local pants = recipeRow(91003)
	check(plain(pants.Right:GetText()) == "Anna Brook +1" and not pants.Dot:IsShown() and not pants.Count:IsShown(), "a row says who knows it, got " .. tostring(pants.Right:GetText()))
	check(recipeRow(91002).Right:GetText():find("Cara Moss", 1, true), "whoever does")
	pants:Click()
	check(plain(v.Also:GetText()) == "Known by: Anna Brook, Bob Stone" and v.Difficulty:GetText() == "", "a click: all who know it, no person's difficulty")
	moved()
	check(calls.Search == before + 2 and outline():find("# Leatherworking", 1, true), "the lists moving: searched again")
	v.Box:SetText("bag")
	Advance(0.35)
	check(outline() == "# Tailoring 93001", "another search, another profession, got " .. outline())
	v.Box:SetText("zzz")
	Advance(0.35)
	check(#v.middle.entries == 0 and v.Message:IsShown() and v.Message:GetText() == "No recipes found", "nothing: it says so")
	v.Clear:Click()
	check(not v.Clear:IsShown() and outline() == outlineBefore and not v.Message:IsShown()
		and plain(v.Name:GetText()) == "Rugged Leather Pants" and recipeRow(91003).Picked.shown,
		"emptied: at once back where it was, its clicked recipe too")
	recipeRow(91003):Click()
	v.Box:SetText("bag")
	v.Box:SetText("")
	Advance(0.5)
	check(calls.Search == before + 4 and outline() == outlineBefore, "emptied before it ran: no search")
	-- A selection while searching: the search ends and the new selection stays.
	v.Box:SetText("bag")
	Advance(0.35)
	personRow("bob"):Click()
	check(v.Box:GetText() == "" and not v.Clear:IsShown() and outline():find("91004", 1, true) and not outline():find("93001", 1, true), "a person clicked: the search ends")
	v.Box:SetText("bag")
	Advance(0.35)
	button(ENCHANTING):Click()
	check(v.Box:GetText() == "" and outline():find("# Armour bits", 1, true) == nil and personRow("me").Picked.shown, "a profession clicked too")
end

section("Chronicle: the Professions tab, enchants")
do
	ME.known[92001], ME.known[92002], ME.known[92003], ME.known[92004] = true, true, true, true
	personRow("anna"):Click()
	personRow("me"):Click()
	check(outline() == "# Armour bits 92003 # Boots and such 92002 92001 # Other 92004",
		"no item: by the data's category, by skill, highest first; without one: Other, got " .. outline())
	local row = recipeRow(92002)
	check(plain(row.Name:GetText()) == "Enchant Chest" and row.Icon.path == 192002 and row.Right:GetText() == "", "the spell's name and icon, no ilvl")
end

section("Chronicle: the Professions tab, gathering and empty lists")
do
	world.people[HERBALISM] = { { id = "anna", name = "Anna Brook", classFile = "MAGE", level = 41, account = "annie", skill = 150, max = 225, updated = MOCK_EPOCH, known = {} } }
	moved()
	button(HERBALISM):Click()
	check(personRow("anna").Skill:GetText() == "150" and #v.middle.entries == 0 and v.Message:GetText() == "No recipes: gathering" and not v.Hint:IsShown(),
		"gathering: people and skill, no recipes")
	personRow("anna"):Click()
	check(v.Message:GetText() == "No recipes: gathering", "under a person too")
	button(MINING):Click()
	check(#v.people.entries == 0 and v.Message:GetText():find("Friends appear", 1, true), "a profession nobody has: the friendly line")
	button(LEATHER):Click()
	personRow("alt"):Click()
	check(v.Message:IsShown() and plain(v.Message:GetText()):find("No recipes from Annalt yet", 1, true) and #v.middle.entries == 0,
		"a person with an empty list: it says so, got " .. tostring(v.Message:GetText()))
	world.people[TAILORING] = { ALT }
	button(TAILORING):Click()
	check(personRow("everyone").Picked.shown and v.Message:GetText():find("No recipe lists here yet", 1, true), "everyone's empty: it says so")
	world.people[TAILORING] = { ANNA }
end

section("Chronicle: the Professions tab, 600 recipes and what's redrawn")
do
	world.people[TAILORING + 1] = { { id = "big", name = "Anna Brook", classFile = "MAGE", level = 60, account = "annie", skill = 400, max = 400, updated = MOCK_EPOCH, known = set(unpack(BIG)) } }
	moved()
	button(TAILORING + 1):Click()
	local pool = math.ceil(v.middle.scroll:GetHeight() / 20) + 1
	check(#v.middle.entries == 601, "all of them in the list")
	check(v.middle.made <= pool and #v.middle.rows <= pool, "a pool of what can be in sight: " .. v.middle.made .. " rows")
	check(v.middle.rows[2].entry.recipe.ilvl == 600 and v.middle.child:GetHeight() == 601 * 20, "the scroll child is as tall as all of them, the highest ilvl first")
	local made, fills = v.middle.made, v.middle.fills
	local scroll = v.middle.scroll
	scroll:SetVerticalScroll(4000)
	scroll._scripts.OnVerticalScroll(scroll, 4000)
	check(v.middle.made == made and v.middle.rows[1].entry == v.middle.entries[201] and v.middle.fills - fills <= pool
		and select(3, v.middle.rows[1]:GetPoint(1)) == -4000, "scrolled: the same rows, laid where it is, filled once")
	fills = v.middle.fills
	scroll._scripts.OnVerticalScroll(scroll, 4005)
	check(v.middle.fills == fills, "within a row's height: nothing to do")

	-- Nothing moved: nothing's made again.
	local draws, groupings, people, professions, parse = v.draws, v.groupings, calls.People, calls.Professions, calls.Parse
	Advance(10)
	win.Tabs.timeline:Click()
	win.Tabs.professions:Click()
	win:Hide()
	C.Toggle()
	check(v.draws == draws and v.groupings == groupings and calls.People == people and calls.Professions == professions and calls.Parse == parse and v.middle.fills == fills,
		"without a change: no redraw, however often it's opened")
	check(scroll:GetVerticalScroll() == 4000, "and it's still where it was")
	v.Box:SetText("bag")
	Advance(0.35)
	check(scroll:GetVerticalScroll() == 0, "a search starts from the top")
	v.Box:SetText("")
	check(scroll:GetVerticalScroll() == 4000 and v.middle.rows[1].entry == v.middle.entries[201], "emptied: back where the list was")
	draws, groupings, fills = v.draws, v.groupings, v.middle.fills
	-- It moved: once, at most every few seconds, kept in place.
	local function step()
		revision = revision + 1
		Advance(1)
	end
	step()
	step()
	local drawsNow = v.draws
	step()
	step()
	check(v.draws - draws <= 2 and drawsNow - draws <= 1, "the lists moving every second: redrawn at most every 3 s, got " .. (v.draws - draws))
	Advance(4)
	check(scroll:GetVerticalScroll() == 4000, "a redraw keeps the scroll")
	local stable = v.draws
	Advance(10)
	check(v.draws == stable, "and then nothing")
	-- Closed: not followed.
	win:Hide()
	revision = revision + 1
	Advance(5)
	check(v.draws == stable, "closed: it isn't drawn")
	C.Toggle()
	check(v.draws == stable + 1, "opened: drawn once")
	-- Hovering costs no list.
	groupings = v.groupings
	local row = v.middle.rows[3]
	row._scripts.OnEnter(row)
	row:Click()
	row:Click()
	check(v.groupings == groupings and v.draws == stable + 1, "hovering and clicking draw no list")
end

section("Chronicle: the Professions tab, names coming in")
do
	button(LEATHER):Click()
	personRow("anna"):Click()
	MOCK_ITEM_UNCACHED = { [95001] = true, [95006] = true, [95101] = true }
	personRow("bob"):Click()
	personRow("anna"):Click()
	local head = recipeRow(91006)
	check(plain(head.Name:GetText()) == "Spell 91006", "an item not loaded yet: the spell's name, got " .. tostring(head.Name:GetText()))
	hover(91001)
	check(plain(v.Name:GetText()) == "Spell 91001", "in the details too")
	local tip = LefthyToolsProfessionsTooltip
	check(tip:IsShown() and not v.tipBroken, "no lines for it yet isn't a failure")
	local fills = v.middle.fills
	MOCK_ITEM_UNCACHED = nil
	Fire("GET_ITEM_INFO_RECEIVED", SECRET)
	Fire("GET_ITEM_INFO_RECEIVED", 12345)
	Advance(0.5)
	check(v.middle.fills == fills, "another item's, or a secret: nothing")
	tip._hyperlink = nil
	Fire("GET_ITEM_INFO_RECEIVED", 95006)
	Fire("GET_ITEM_INFO_RECEIVED", 95101)
	check(plain(head.Name:GetText()) == "Spell 91006", "not in the event itself")
	Advance(0.3)
	check(plain(head.Name:GetText()) == "Leather Cap" and head.Name:GetText():find("^|c"), "shortly after: the name in the rows")
	local once = v.middle.fills - fills
	check(once > 0 and once <= #v.middle.rows, "both in one fill of the rows in sight, " .. once)
	check(tip._hyperlink == nil, "the tooltip's own item didn't come: left alone")
	Fire("GET_ITEM_INFO_RECEIVED", 95001)
	Advance(0.3)
	check(plain(v.Name:GetText()) == "Barbaric Harness" and tip._hyperlink == "item:95001", "its item came: the details and the tooltip")
	Fire("GET_ITEM_INFO_RECEIVED", 95001)
	fills = v.middle.fills
	Advance(0.3)
	check(v.middle.fills == fills, "an item already here: nothing")
end

section("Chronicle: the Professions tab, in a fight")
do
	local blocked = #BLOCKED
	EnterCombat()
	personRow("bob"):Click()
	check(personRow("bob").Picked.shown and outline():find("91004", 1, true), "clicks work")
	hover(91004)
	check(plain(v.Name:GetText()) == "Dark Leather Pants" and LefthyToolsProfessionsTooltip:IsShown(), "hovering and the tooltip too")
	v.Box:SetText("bag")
	Advance(0.35)
	check(outline() == "# Tailoring 93001", "the search too")
	v.Clear:Click()
	local draws = v.draws
	revision = revision + 1
	Advance(1.5)
	check(v.draws == draws, "the lists moving at the start of a fight: not now")
	LeaveCombat()
	Advance(4)
	check(v.draws == draws + 1, "after it")
	check(#BLOCKED == blocked, "nothing blocked")
end

section("Chronicle: the Professions tab, when the real tooltip can't work")
do
	local tip = LefthyToolsProfessionsTooltip
	hover(91004)
	personRow("anna"):Click()
	tip._numLines = 0
	hover(91003)
	check(v.tipBroken and not tip:IsShown() and TOOLTIP.owner == v.Detail and TOOLTIP.link == "item:95003" and TOOLTIP.shown and v.TipClip:GetHeight() == 1,
		"a loaded item without lines: the normal tooltip beside the window instead")
	tip._numLines = nil
	hover(91001)
	check(TOOLTIP.link == "item:95001" and not tip:IsShown(), "from then on")
	win:Hide()
	check(not TOOLTIP.shown, "gone with the window")
	C.Toggle()
	v.tipBroken = false
	local set = tip.SetHyperlink
	tip.SetHyperlink = function() error("no such thing") end
	hover(91003)
	check(v.tipBroken and TOOLTIP.link == "item:95003", "a call that fails: the same")
	tip.SetHyperlink = set
	v.tipBroken = false
	local hide = recipeRow(91001)
	hide._scripts.OnEnter(hide)
	check(tip:IsShown() and tip._hyperlink == "item:95001", "(the real one again, for what follows)")
end

-- The real thing, if it's loaded: everyone knowing everything, in every crafting profession.
section("Chronicle: the Professions tab, comparing with what I wear and opening my window")
do
	local wasCompare, wasTrade, wasItemName, wasLink = C_TooltipComparison, C_TradeSkillUI, C_Item.GetItemNameByID, C_Item.GetItemLinkByGUID
	local worn = { [1] = { guid = "Item-1", name = "Old Pants", quality = 1 }, [2] = { guid = "Item-2", name = "Old Ring", quality = 2 } }
	local method, additional = 0, {}
	local nothingWorn = false
	C_Item.GetItemNameByID = function(id)
		for _, item in pairs(worn) do if item.guid == id then return item.name end end
		return wasItemName and wasItemName(id)
	end
	C_Item.GetItemLinkByGUID = function(guid) return guid == worn[1].guid and "item:42" or nil end
	C_TooltipComparison = {
		GetItemComparisonInfo = function() return { method = method, item = nothingWorn and {} or { guid = worn[1].guid }, additionalItems = additional } end,
		GetItemComparisonDelta = function(_, against, paired, together)
			return { "+2 Armor", "-1 Agility " .. against.guid .. (paired and " paired" or "") .. (together and " together" or "") }
		end,
	}
	local opened, picked = {}, {}
	local base
	C_TradeSkillUI = {
		OpenTradeSkill = function(line) opened[#opened + 1] = line; return true end,
		OpenRecipe = function(spell) picked[#picked + 1] = spell end,
		GetBaseProfessionInfo = function() return base end,
	}
	world.people = { [LEATHER] = { ANNA, BOB, ME } }
	open()
	moved()
	button(LEATHER):Click()
	personRow("anna"):Click()
	hover(91003)
	local row = v.compare[1]
	check(row:IsShown() and plain(row.Name:GetText()) == "Replaces: Old Pants" and row.Lines:GetText():find("+2 Armor\n-1 Agility Item-1", 1, true)
		and not v.compare[2]:IsShown(), "gear: what I wear, and the game's stat lines")
	row._scripts.OnEnter(row)
	check(TOOLTIP.owner == row and TOOLTIP.link == "item:42", "the name hovered: my item's tooltip")
	row._scripts.OnLeave(row)
	additional = { { guid = worn[2].guid } }
	hover(91001)
	check(v.compare[2]:IsShown() and plain(v.compare[2].Name:GetText()) == "Replaces: Old Ring", "a second ring or trinket: a row of its own")
	method = 1
	hover(91003)
	check(v.compare[1].Lines:GetText():find("Item-1 paired", 1, true) and not v.compare[2]:IsShown(), "both hands: one comparison, as the game does")
	method = 2
	hover(91001)
	check(v.compare[1].Lines:GetText():find("Item-1 paired together", 1, true), "paired with a bag item")
	method, additional = 0, {}
	nothingWorn = true
	hover(91003)
	check(not v.compare[1]:IsShown(), "nothing worn there: nothing to compare")
	nothingWorn = false
	hover(91009)
	check(not v.compare[1]:IsShown(), "not gear: nothing to compare")
	local stale = worn[1].name
	hover(91003)
	worn[1].name = "New Pants"
	v.root._scripts.OnEvent(v.root, "PLAYER_EQUIPMENT_CHANGED")
	Advance(1)
	check(plain(v.compare[1].Name:GetText()) == "Replaces: New Pants", "what I wear changes: it follows")
	worn[1].name = stale
	C_TooltipComparison = nil
	hover(91001)
	check(not v.compare[1]:IsShown() and v.DetailBody:IsShown(), "no such API: the rest still works")
	C_TooltipComparison = wasCompare

	-- My own window: only for a recipe this character knows.
	local wasKnown = KNOWN_SPELLS[91003]
	KNOWN_SPELLS[91003] = nil
	hover(91003)
	check(not v.OpenMine:IsShown(), "a recipe I don't know: no button")
	KNOWN_SPELLS[91003] = true
	hover(91001)
	hover(91003)
	check(v.OpenMine:IsShown() and v.tipRoom > 0, "one I know: the button")
	v.OpenMine:Click()
	check(opened[1] == LEATHER and #picked == 0, "the game opens my window on its profession, the recipe waits")
	Fire("TRADE_SKILL_SHOW")
	Advance(0.1)
	check(picked[1] == 91003, "then the window hears which recipe")
	Fire("TRADE_SKILL_SHOW")
	Advance(0.1)
	check(#picked == 1, "only once")
	local wasFrame = ProfessionsFrame
	ProfessionsFrame = { IsShown = function() return true end }
	base = { professionID = LEATHER }
	v.OpenMine:Click()
	check(#opened == 1 and picked[2] == 91003, "that profession's window is open already: just the recipe")
	ProfessionsFrame = wasFrame
	base = nil
	STATE.combat = true
	local mark = #PRINTED + 1
	v.OpenMine:Click()
	check(#opened == 1 and suite.printedSince(mark):find("during a fight", 1, true), "in a fight: it says so")
	STATE.combat = false
	KNOWN_SPELLS[91003] = wasKnown
	C_TradeSkillUI, C_Item.GetItemNameByID, C_Item.GetItemLinkByGUID = wasTrade, wasItemName, wasLink
	win:Hide()
end

section("Chronicle: the Professions tab, on C.Recipes' own data")
do
	local source = realRecipes or fake
	local rows = 0
	local whole = {
		Parse = source.Parse, RecipeOf = source.RecipeOf, Professions = source.Professions, Search = source.Search,
		Crafters = function() return {} end,
		Revision = function() return 1 end,
		People = function(line)
			local known = {}
			for _, recipe in ipairs(source.Parse(line) or {}) do known[recipe.spell] = true end
			return { { id = "all", name = "Anna Brook", classFile = "MAGE", level = 60, account = "annie", skill = 300, max = 300, updated = MOCK_EPOCH, known = known } }
		end,
	}
	ns.RecipeData = realData or ns.RecipeData
	C.Recipes = whole
	win.Tabs.timeline:Click()
	win.Tabs.professions:Click()
	check(#v.profs >= #source.Professions(), "its professions have buttons")
	for _, prof in ipairs(source.Professions()) do
		local line = prof.line
		local parsed = whole.Parse(line) or {}
		if not prof.gathering and #parsed > 0 then
			local b = button(line)
			if b.Picked.shown then
				local all = source.Professions()
				button(all[#all].line):Click() -- (the last is a gathering one: then this one's click is a change)
			end
			b:Click()
			local recipes, sorted, last = 0, true, nil
			local seen = {}
			for _, e in ipairs(v.middle.entries) do
				if e.header then
					check(type(e.label) == "string" and e.label ~= "" and e.n > 0 and not seen[e.key], "a group with a name, once: " .. tostring(e.key))
					seen[e.key] = true
					last = nil
				else
					recipes = recipes + 1
					local key = e.gear and (e.recipe.ilvl or 0) or (e.recipe.low or 0)
					sorted = sorted and (last == nil or key <= last)
					last = key
				end
			end
			rows = rows + recipes
			check(recipes == #parsed and sorted, prof.name .. ": every recipe once, each group sorted: " .. recipes .. " of " .. #parsed)
			check(v.middle.made <= math.ceil(v.middle.scroll:GetHeight() / 20) + 1, prof.name .. ": a pool")
			local row = v.middle.rows[2]
			if row and row.entry and row.entry.recipe then
				row._scripts.OnEnter(row)
				check(v.DetailBody:IsShown() and (v.Name:GetText() or "") ~= "", prof.name .. ": a recipe's details")
			end
		end
	end
	check(rows > 0, "there were recipes to draw, " .. rows)
	if realRecipes then
		v.Box:SetText("a")
		Advance(0.35)
		check(#v.middle.entries > 0 or v.Message:IsShown(), "its search draws")
		v.Clear:Click()
	end
	win.Tabs.timeline:Click()
	win:Hide()
	C.Recipes, ns.RecipeData = realRecipes, realData
end
