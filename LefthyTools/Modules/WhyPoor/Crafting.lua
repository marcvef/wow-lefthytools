local _, ns = ...
local LT = ns.LT
local L = ns.L
local W = ns.WhyPoor or {}
ns.WhyPoor = W
local C = ns.Chronicle -- (C.QualityText, C.OpenInMyProfessionWindow)

-- The window's Crafting tab (W.Crafting, Cf): the crafting margins (they were Chronicle's own window until build
-- 0.7.0-193). My characters' recipes on this realm (W.Margins: Mg.MyRecipes) worked out a few a frame (Mg.Compute:
-- the crafting part's Cr.Recipe), those with a number in the list: by gold per hour or profit per craft, all
-- professions or one (the controls on the line above the list). A recipe's details: who makes it, its reagents and
-- the cheapest way to each (crafted ones with their own line, the whole way in the hover), cost, both revenues,
-- profit, time, gold per hour, how many crafts the bags cover, the prices' age, notes; "Check AH" and "Show in my
-- profession window". Nothing picked: the overview, with "Scan all my recipes" (item by item when the game
-- doesn't allow a whole scan again; a stopped one goes on where it was).
-- A "Margins" button on Blizzard's profession window (setting craftButton) opens the tab on the recipe shown and
-- checks its prices at an open auction house: our own frame, a child of the schematic form, post-hooked (its Init),
-- nothing of Blizzard's changed or protected.
-- What it costs: only while the window shows this tab, a driver looks four times a second whether prices or
-- recipes changed and works the list out again (BUILD_MS a frame; during a scan at most every REBUILD_GAP).

local Cf = { results = {}, sortBy = "hour", filter = nil, dirty = true, lastBuild = -math.huge, since = 0 }
W.Crafting = Cf

local Wn = W.Window
local D = Wn.D
local TICK, REBUILD_GAP, BUILD_MS = 0.25, 2, 2
local GREY, GREEN, RED, ORANGE = "|cff888888", "|cff40c040", "|cffff4040", "|cffff9933"
local SEP = " · "
local issecret = LT.IsSecret

local function Mg()
	return W.Margins
end

local function Crafts()
	return W.Crafts
end

local function Clock()
	local ok, ms = pcall(debugprofilestop)
	return ok and type(ms) == "number" and ms or nil
end

---------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------

-- Copper, green when a gain, red when a loss, "+" before a gain.
function Cf.Profit(copper)
	if type(copper) ~= "number" then
		return GREY .. "-|r"
	end
	local text = W.Money(copper)
	if copper >= 0.5 then
		return GREEN .. "+" .. text .. "|r"
	elseif copper <= -0.5 then
		return RED .. text .. "|r"
	end
	return text
end

function Cf.ItemName(item)
	local ok, name = pcall(C_Item.GetItemInfo, ("item:%d"):format(item))
	return ok and type(name) == "string" and not issecret(name) and name or nil
end

function Cf.RecipeName(recipe)
	local name = recipe.item and Cf.ItemName(recipe.item)
	if not name then
		local info = LT.Value(C_Spell.GetSpellInfo, recipe.spell)
		name = type(info) == "table" and type(info.name) == "string" and not issecret(info.name) and info.name or nil
	end
	return name or ("#" .. recipe.spell)
end

function Cf.Title(r)
	local recipe = r.recipe
	local name = Cf.RecipeName(recipe)
	if C and C.QualityText then
		name = C.QualityText(name, recipe.quality)
	end
	return name .. ((r.yield or 1) > 1 and (GREY .. " x" .. r.yield .. "|r") or "")
end

function Cf.ProfessionName(line)
	local names = ns.RecipeData and ns.RecipeData.names and ns.RecipeData.names[line]
	return names and names[ns.LOCALE == "deDE" and 2 or 1] or tostring(line)
end

-- The skill-up colour of a recipe at a skill (as the profession window has them), nil without numbers.
function Cf.Difficulty(skill, recipe)
	local low, high = recipe.low, recipe.high
	if not (skill and low and high and high > 0) then
		return nil
	elseif skill < low then
		return 1, 0.5, 0.25
	elseif skill < (low + high) / 2 then
		return 1, 1, 0
	elseif skill < high then
		return 0.25, 0.75, 0.25
	end
	return 0.5, 0.5, 0.5
end

function Cf.Stale(r)
	return r.oldest ~= nil and time() - r.oldest > Mg().STALE
end

function Cf.Seconds(s)
	return LT.Decimal(("%.1f"):format(s)) .. " s"
end

-- A count: whole, or with one decimal (a share of a craft: what a craft makes beyond it goes into the next one).
function Cf.Count(n)
	local whole = math.floor(n + 0.5)
	if math.abs(n - whole) < 0.01 then
		return tostring(whole)
	end
	return LT.Decimal(("%.1f"):format(n))
end

-- Where a step of Cr.Cost's answer comes from.
function Cf.WayText(c)
	if not (c and c.how) then
		return RED .. L["no price"] .. "|r"
	elseif c.how == "ah" then
		return (c.few and RED or "") .. L["AH"] .. "|r"
	elseif c.how == "vendor" then
		return L["Vendor"]
	elseif c.how == "craft" then
		return (c.complete and "" or RED) .. L["Craft"] .. "|r"
	end
	return L["Bags"]
end

-- The craft of an answer (also the rest of one partly from the bags), nil: bought.
function Cf.CraftOf(c)
	if c and c.how == "craft" then
		return c
	end
	return c and c.rest and c.rest.how == "craft" and c.rest or nil
end

-- "craft it: 1 Bolt of Linen Cloth from 2 Linen Cloth, 1.5 s": the recipe's own numbers, a craft's time ("~": what
-- a craft makes can vary, the data has the middle).
function Cf.CraftLine(c)
	local recipe, yield = c.recipe.data, c.recipe.yield
	local parts = {}
	for _, need in ipairs(recipe.reagents) do
		parts[#parts + 1] = ("%d %s"):format(need.n, Cf.ItemName(need.item) or "...")
	end
	local made = (yield > 1 and "~" or "") .. yield .. " " .. (Cf.ItemName(c.item) or "...")
	return L["craft it: %s from %s, %s"]:format(made, table.concat(parts, ", "),
		Cf.Seconds(Crafts().CastTime(recipe.spell) + Crafts().OVERHEAD))
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------

function Cf.Sorted()
	local list = {}
	for _, r in ipairs(Cf.results) do
		if r.profit and (not Cf.filter or r.line == Cf.filter) then
			list[#list + 1] = r
		end
	end
	local key = Cf.sortBy == "craft" and "profit" or "perHour"
	table.sort(list, function(a, b)
		if a[key] ~= b[key] then
			return a[key] > b[key]
		end
		return a.spell < b.spell
	end)
	return list
end

-- Every recipe of mine worked out again, a few a frame (the driver goes on with it).
function Cf.Rebuild()
	Cf.building = { list = (Mg().MyRecipes()), i = 1, out = {}, rev = Mg().Revision() }
	Cf.dirty = false
end

function Cf.BuildStep()
	local started = Clock()
	local b = Cf.building
	while b.list[b.i] do
		b.out[#b.out + 1] = Mg().Compute(b.list[b.i])
		b.i = b.i + 1
		if b.i % 10 == 0 and started and Clock() - started >= BUILD_MS then
			return
		end
	end
	Cf.results, Cf.builtRev, Cf.building, Cf.lastBuild = b.out, b.rev, nil, GetTime()
	Wn.state.due = true
end

function Cf.Showing()
	return Wn.Shown() and Wn.state.tab == "crafting"
end

-- The driver: only while the tab shows.
Cf.driver = CreateFrame("Frame")
Cf.driver:Hide()
Cf.driver:SetScript("OnUpdate", function(self, elapsed)
	if not Cf.Showing() then
		Cf.building = nil
		self:Hide()
		return
	end
	if Cf.building then
		LT.Guard("WhyPoor crafting", Cf.BuildStep)
	end
	Cf.since = Cf.since + elapsed
	if Cf.since < TICK then
		return
	end
	Cf.since = 0
	-- Worked out again: at once when prices or recipes changed, else (items' data coming in, the bags, prices during
	-- a scan) at most every REBUILD_GAP.
	local status = Mg().Status()
	local changed = Cf.builtRev ~= Mg().Revision()
	local due = (changed and not status.running) or ((changed or Cf.dirty) and GetTime() - Cf.lastBuild >= REBUILD_GAP)
	if not Cf.building and due then
		Cf.Rebuild()
	end
	if Wn.state.sel.crafting == nil and not Wn.state.goal then
		Wn.state.due = true -- (the overview's scan line)
	end
end)
Cf.events = CreateFrame("Frame")
Cf.events:SetScript("OnEvent", function()
	Cf.dirty = true -- (GET_ITEM_INFO_RECEIVED, BAG_UPDATE_DELAYED: worked out again on the tick)
end)

local T = { headWidth = 120 }
Cf.tab = T

function T.Entries()
	if not Cf.driver:IsShown() then
		Cf.since = TICK
		Cf.driver:Show()
	end
	local list = Cf.Sorted()
	local without = 0
	for _, r in ipairs(Cf.results) do
		if not r.profit and (not Cf.filter or r.line == Cf.filter) then
			without = without + 1
		end
	end
	local head = without > 0 and L["%d recipes, %d more without prices yet"]:format(#list, without) or L["%d recipes"]:format(#list)
	local empty
	if Cf.building and not Cf.results[1] then
		empty = L["Working out your recipes..."]
	elseif Cf.results[1] then
		empty = L["No prices yet: open the auction house and scan your recipes."]
	else
		empty = L["None of your characters on this realm knows a recipe that makes an item yet."]
	end
	return list, head, empty
end

function T.Fill(row, r)
	row.Icon:SetTexture(Wn.ItemIcon(r.recipe.item))
	row.Title:SetText(Cf.Title(r))
	local byHour = Cf.sortBy ~= "craft"
	local money = byHour and (Cf.Profit(r.perHour) .. L["/h"]) or Cf.Profit(r.profit)
	local other = byHour and L["%s a craft"]:format(Cf.Profit(r.profit)) or (Cf.Profit(r.perHour) .. L["/h"])
	local stale = Cf.Stale(r)
	row.Money:SetText(stale and (GREY .. money:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "|r") or money)
	local who = r.who and r.who.name
	local parts = { other, r.best == "ah" and L["AH"] or L["Vendor"],
		r.oldest and ((stale and ORANGE or "") .. W.Age(r.oldest) .. "|r") or L["vendor prices"] }
	if who then
		table.insert(parts, 1, LT.Window.ClassColorCode(r.who.classFile) .. who .. "|r")
	end
	row.Sub:SetText(table.concat(parts, SEP))
	local red, green, blue = Cf.Difficulty(r.who and r.who.skill, r.recipe)
	for i, dot in ipairs(row.Dots) do
		dot:SetShown(i == 3 and red ~= nil)
		if i == 3 and red then
			dot:SetColorTexture(red, green, blue, 1)
		end
	end
end

function T.Key(r)
	return r.spell
end

-- A recipe picked that isn't in the list (yet): its details all the same.
function T.Find(spell)
	return Mg().Recipe(spell)
end

function T.Enter(row, r)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetText(Cf.RecipeName(r.recipe), 1, 0.82, 0)
	GameTooltip:AddDoubleLine(L["Profit per craft"], Cf.Profit(r.profit), 1, 0.82, 0, 1, 1, 1)
	GameTooltip:AddDoubleLine(L["Gold per hour"], Cf.Profit(r.perHour), 1, 0.82, 0, 1, 1, 1)
	if r.who then
		GameTooltip:AddLine(L["%s, %s %d"]:format(r.who.name or "?", Cf.ProfessionName(r.line), r.who.skill or 0), 1, 1, 1)
	end
	GameTooltip:AddLine(L["Click: its details"], 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- The details
---------------------------------------------------------------------------

function Cf.ReagentTip(row)
	local g = row.data
	if not g then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_LEFT")
	if not pcall(GameTooltip.SetHyperlink, GameTooltip, ("item:%d"):format(g.item)) then
		GameTooltip:AddLine(Cf.ItemName(g.item) or ("#" .. g.item))
	end
	local Cr = Crafts()
	local vendor = Cr.VendorBuy(g.item)
	local ah, q, t, scanned = Cr.AHBuy(g.item)
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine(L["Vendor"], vendor and W.Money(vendor) or "-", 1, 0.82, 0, 1, 1, 1)
	GameTooltip:AddDoubleLine(L["AH"], ah and L["%s (%d listed, %s)"]:format(W.Money(ah), q or 0, LT.Ago(t))
		or scanned and t and L["none listed (%s)"]:format(LT.Ago(t)) or scanned and L["none listed"] or L["not scanned"],
		1, 0.82, 0, 1, 1, 1)
	GameTooltip:AddDoubleLine(L["In your bags"], tostring(g.have), 1, 0.82, 0, 1, 1, 1)
	if Cf.CraftOf(g.cost) then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(L["The cheapest way:"], 1, 0.82, 0)
		Cr.Walk(g.cost, function(step, level)
			local left = ("   "):rep(level) .. ("%s x%s"):format(Cf.ItemName(step.item) or ("#" .. step.item), Cf.Count(step.n))
			local right = Cf.WayText(step) .. "  " .. (step.complete and step.total and W.Money(step.total) or "-")
			GameTooltip:AddDoubleLine(left, right, 1, 1, 1, 1, 1, 1)
		end)
	end
	GameTooltip:Show()
end

function Cf.Notes(r)
	local notes = {}
	if r.few then
		local few, named = {}, {}
		for _, g in ipairs(r.reagents) do
			Crafts().Walk(g.cost, function(step)
				if step.how == "ah" and step.few and not named[step.item] then
					named[step.item] = true
					few[#few + 1] = Cf.ItemName(step.item) or ("#" .. step.item)
				end
			end)
		end
		notes[#notes + 1] = RED .. L["Few on the AH: %s"]:format(table.concat(few, ", ")) .. "|r"
	end
	if not Mg().IsAHOpen() then
		notes[#notes + 1] = L["Open the auction house to update the prices."]
	end
	if r.best == "ah" then
		notes[#notes + 1] = L["The AH's deposit isn't counted, and it may not sell."]
	end
	if not r.castKnown then
		notes[#notes + 1] = L["Its cast time isn't known: 3 s counted."]
	end
	if not r.subCastKnown then
		notes[#notes + 1] = L["A reagent's cast time isn't known: 3 s counted."]
	end
	if r.crafted then
		notes[#notes + 1] = L["Reagents you can make count as crafted where that's cheaper."]
	end
	if r.mayVary then
		notes[#notes + 1] = L["~ What a craft makes can vary: the data's middle is counted."]
	end
	if r.verdict == "sell reagents" then
		notes[#notes + 1] = GREEN .. L["Its reagents would sell for %s: more than what it makes."]:format(W.Money(r.reagentsSale)) .. "|r"
	end
	return notes
end

function T.Details(e)
	local r = Mg().Recipe(e.spell) or e -- (its numbers now: a recipe just checked shows its new prices)
	D.Text(Cf.Title(r), "title")
	local who = r.who
	D.Text(who and L["%s, %s %d"]:format(LT.Window.ClassColorCode(who.classFile) .. (who.name or "?") .. "|r",
		Cf.ProfessionName(r.line), who.skill or 0) or Cf.ProfessionName(r.line), "small")
	D.Head(L["Reagents"])
	for _, g in ipairs(r.reagents or {}) do
		D.Item(g.item, g.n, Cf.WayText(g.cost) .. "  " .. (g.unit and W.Money(g.unit * g.n) or "-"), Cf.ReagentTip, g)
		local craft = Cf.CraftOf(g.cost)
		if craft then
			D.Text(GREY .. Cf.CraftLine(craft) .. "|r", "small", 20)
		end
	end
	D.Head(L["The numbers"])
	local function Line(label, value)
		D.Text(label .. ": " .. value, "text", 4)
	end
	Line(L["Cost per craft"], r.complete and W.Money(r.cost) or RED .. L["missing a price"] .. "|r")
	Line(L["Sold to a vendor"], r.vendorRevenue and (W.Money(r.vendorRevenue) .. "  " .. Cf.Profit(r.vendorProfit))
		or GREY .. L["vendors don't buy it"] .. "|r")
	Line(L["On the AH, after the 5% cut"], r.ahRevenue and (W.Money(r.ahRevenue) .. "  " .. Cf.Profit(r.ahProfit))
		or GREY .. (r.ahScanned and L["none listed"] or L["not scanned"]) .. "|r")
	Line(L["Profit per craft"], r.profit and (Cf.Profit(r.profit) .. " " .. GREY .. "(" .. (r.best == "ah" and L["AH"] or L["Vendor"]) .. ")|r") or "-")
	Line(L["Time per craft"], Cf.Seconds(r.seconds) .. ((r.subSeconds or 0) > 0
		and (" " .. GREY .. L["(%s crafting reagents)"]:format(Cf.Seconds(r.subSeconds)) .. "|r") or ""))
	Line(L["Gold per hour"], Cf.Profit(r.perHour))
	Line(L["Your bags"], L["enough for %d crafts"]:format(r.covers or 0))
	Line(L["Prices"], r.oldest and LT.Ago(r.oldest) or L["vendor prices only"])
	local notes = Cf.Notes(r)
	if notes[1] then
		D.Head(L["Notes"])
		for _, note in ipairs(notes) do
			D.Text(note, "small", 4)
		end
	end
	D.y = D.y + 6
	local status = Mg().Status()
	local checking = status.running and status.spell == r.spell
	D.Button(checking and L["Checking..."] or L["Check AH"], function()
		if Mg().ScanRecipe(r.spell) then
			Wn.state.due = true
		end
	end, status.open and not (status.running and status.kind == "replicate"), 110)
	if LT.Value(C_SpellBook.IsSpellKnown, r.spell) == true and C and C.OpenInMyProfessionWindow then
		D.Button(L["Show in my profession window"], function()
			C.OpenInMyProfessionWindow(r.spell)
		end, true, 200, true)
	end
end

-- Nothing picked: what the list is, the scan, "Scan all my recipes".
function T.Overview()
	D.Text(L["Crafting margins"], "title")
	D.Text(L["What your recipes cost to make and bring, and gold per hour, at the auction house's and vendors' prices. Reagents you can make count as crafted where that's cheaper. Click a recipe for its numbers."], "text", 0, 2)
	local status = Mg().Status()
	D.Head(L["Prices"])
	local scan = Wn.ScanLine()
	if scan then
		D.Text(scan, "text", 4)
	elseif not status.open then
		D.Text(L["Open the auction house to scan."], "text", 4)
	end
	local P = W.Prices
	local last = P and P.LastScan and P.LastScan()
	if type(last) == "number" and last > 0 then
		D.Text(L["Last whole scan: %s ago"]:format(W.Age(last)), "small", 4)
	end
	D.y = D.y + 4
	local label
	if status.running then
		label = L["Stop"]
	else
		local resume = status.left and status.items and status.left > 0 and status.left < status.items
		label = resume and L["Go on (%d left)"]:format(status.left) or L["Scan all my recipes"]
	end
	D.Button(label, function()
		if Mg().Status().running then
			Mg().Cancel()
		else
			Mg().ScanAll()
		end
		Wn.state.due = true
	end, status.running or status.open, 180)
end

---------------------------------------------------------------------------
-- The controls on the line above the list: the profession, the order
---------------------------------------------------------------------------

function Cf.PickerEntries()
	local entries = { { text = L["All professions"], value = 0, selected = Cf.filter == nil } }
	local has = {}
	for _, entry in ipairs((Mg().MyRecipes())) do
		has[entry.line] = true
	end
	for _, line in ipairs(ns.RecipeData and ns.RecipeData.order or {}) do
		if has[line] then
			entries[#entries + 1] = { text = Cf.ProfessionName(line), value = line, selected = Cf.filter == line }
		end
	end
	return entries
end

function Cf.SortLabel()
	return Cf.sortBy == "craft" and L["By profit"] or L["By gold/h"]
end

function T.Controls(view, shown)
	if not shown and not Cf.picker then
		return
	end
	if not Cf.picker then
		local parent = view.Head:GetParent()
		Cf.picker = LT.Window.AddPicker(parent, 96, Cf.PickerEntries, function(value)
			Cf.filter = value ~= 0 and value or nil
			Cf.picker:SetLabel(Cf.filter and Cf.ProfessionName(Cf.filter) or L["All professions"])
			Wn.state.due = true
		end)
		Cf.picker:SetPoint("LEFT", view.Head, "RIGHT", 2, 0)
		Cf.picker:SetLabel(L["All professions"])
		Cf.sort = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
		Cf.sort:SetSize(66, 18)
		Cf.sort:SetPoint("LEFT", Cf.picker, "RIGHT", 2, 0)
		Cf.sort:SetText(Cf.SortLabel())
		Cf.sort:SetScript("OnClick", function(self)
			Cf.sortBy = Cf.sortBy == "craft" and "hour" or "craft"
			self:SetText(Cf.SortLabel())
			Wn.state.due = true
		end)
	end
	Cf.picker:SetShown(shown)
	Cf.sort:SetShown(shown)
	if shown then
		Cf.events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
		Cf.events:RegisterEvent("BAG_UPDATE_DELAYED")
	else
		Cf.events:UnregisterAllEvents()
	end
end

Wn.AddTab("crafting", L["Crafting"], T)

---------------------------------------------------------------------------
-- The "Margins" button on Blizzard's profession window
---------------------------------------------------------------------------

function Cf.Form()
	local page = _G.ProfessionsFrame and ProfessionsFrame.CraftingPage
	return page and page.SchematicForm
end

-- The recipe the profession window shows, as the data has it: its ID, else one of mine of the same name
-- (Forever has copies of some recipes under other IDs).
function Cf.ShownRecipe()
	local form = Cf.Form()
	local ok, info = pcall(function() return form:GetRecipeInfo() end)
	if not (ok and type(info) == "table") then
		return nil
	end
	local id = info.recipeID
	local R = C and C.Recipes
	if type(id) ~= "number" or issecret(id) or not R then
		return nil
	end
	local recipe = R.RecipeOf(id)
	if recipe then
		return recipe.item and id or nil
	end
	local name = info.name
	if type(name) == "string" and not issecret(name) then
		for _, entry in ipairs((Mg().MyRecipes())) do
			local spell = LT.Value(C_Spell.GetSpellInfo, entry.spell)
			if type(spell) == "table" and spell.name == name then
				return entry.spell
			end
		end
	end
end

function Cf.ButtonWanted()
	local m = W.module
	return m ~= nil and m.enabled and type(m.db) == "table" and m.db.craftButton ~= false
end

function Cf.UpdateProfButton()
	if Cf.profButton then
		Cf.profButton:SetShown(Cf.ButtonWanted() and Cf.ShownRecipe() ~= nil)
	end
end

-- Opens the tab on a recipe (and checks its prices at an open auction house).
function Cf.OpenOn(spell)
	if not Wn.Open("crafting") then
		return false
	end
	if spell then
		Wn.state.sel.crafting, Wn.state.goal = spell, false
		Mg().ScanRecipe(spell)
		Wn.Draw()
	end
	return true
end

function Cf.HookProfessions()
	local form = Cf.Form()
	if Cf.profButton or not form then
		return
	end
	local b = CreateFrame("Button", nil, form, "UIPanelButtonTemplate")
	b:SetSize(80, 20)
	b:SetText(L["Margins"])
	b:SetPoint("TOPRIGHT", form, "TOPRIGHT", -8, -8)
	b:SetScript("OnClick", function()
		local spell = Cf.ShownRecipe()
		if spell then
			Cf.OpenOn(spell)
		end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L["Crafting margins"])
		GameTooltip:AddLine(L["What this recipe costs and brings, and gold per hour (WhyPoor?'s Crafting tab). With the auction house open, its prices are checked there."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self)
		if GameTooltip:IsOwned(self) then
			GameTooltip:Hide()
		end
	end)
	Cf.profButton = b
	if type(form.Init) == "function" then
		hooksecurefunc(form, "Init", function() C_Timer.After(0, Cf.UpdateProfButton) end)
	end
	form:HookScript("OnShow", function() C_Timer.After(0, Cf.UpdateProfButton) end)
	Cf.UpdateProfButton()
end

-- WhyPoor.lua's W.Changed: switched on or off, a setting changed.
function Cf.SettingsChanged()
	Cf.HookProfessions()
	Cf.UpdateProfButton()
end

Cf.loader = CreateFrame("Frame")
Cf.loader:RegisterEvent("ADDON_LOADED")
Cf.loader:SetScript("OnEvent", function(_, _, addon)
	if addon == "Blizzard_Professions" then
		C_Timer.After(0, Cf.HookProfessions)
	end
end)
