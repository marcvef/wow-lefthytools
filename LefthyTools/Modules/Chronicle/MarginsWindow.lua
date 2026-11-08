local _, ns = ...
local LT = ns.LT
local L = ns.L
local C = ns.Chronicle
local M = C.module

-- Crafting margins, what's seen of them (the numbers and the scanning are Margins.lua's, C.Margins):
--   * a window of our own (LefthyToolsMarginsFrame): my recipes with prices, by gold per hour or profit per
--     craft, a profession to pick, "Scan all my recipes"; a click on one shows its numbers on the right
--     (reagents and where they come from, cost, both revenues, profit, time, gold per hour, the prices' age),
--     "Check AH" and "Show in my profession window";
--   * a "Margins" button on Blizzard's profession window (the recipe shown; with the auction house open it
--     checks its prices) and one on the auction house (the window).
-- The buttons are our own frames, children of Blizzard's (they show and hide with them; the controller's
-- navigation reaches them, at the window's top right corner where nothing of Blizzard's is near); nothing
-- of Blizzard's is changed, only post-hooked (the form's Init: another recipe shown). Nothing here is
-- protected. The window works only while it's shown: a quarter-second look at the scan, the list worked
-- out again a few recipes a frame when prices or recipes changed (during a scan at most every REBUILD_GAP).

local W, H = 800, 540
local INSET_X, INSET_Y = 4, 60        -- where ButtonFrameTemplate's Inset is
local LIST_W, BAR_W = 440, 24
local LIST_Y = 22                     -- under the column titles
local ROW_H, REAGENT_H, REAGENTS = 20, 18, 8
local DETAIL_X = INSET_X + LIST_W + BAR_W + 16
local DETAIL_W = W - DETAIL_X - 14
local TICK = 0.25
local REBUILD_GAP = 2
local BUILD_MS = 2
local NEXT_TO_GAP = 44                -- right of the profession window: its side tabs
local GREY, GREEN, RED = "|cff888888", "|cff40c040", "|cffff4040"

local issecret = LT.IsSecret
local frame, view
local filterLine          -- the profession picked (nil: all)
local sortBy = "hour"     -- or "craft"
local selected            -- the spell in the details
local results = {}        -- Mg.Compute of every recipe of mine, as of builtRev
local builtRev, building, dirty
local lastBuild, sinceTick = -math.huge, 0
local profButton, ahButton

local function Mg()
	return C.Margins
end

local function Clock()
	local ok, ms = pcall(debugprofilestop)
	return ok and type(ms) == "number" and ms or nil
end

-- Copper in short: "1g 20s", "35s 2c", "8c" (German: k for copper).
local function Short(copper, signed)
	if not copper then
		return "-"
	end
	local c = math.floor(math.abs(copper) + 0.5)
	local text
	if c >= 10000 then
		text = L["%dg %ds"]:format(math.floor(c / 10000), math.floor(c / 100) % 100)
	elseif c >= 100 then
		text = L["%ds %dc"]:format(math.floor(c / 100), c % 100)
	else
		text = L["%dc"]:format(c)
	end
	if copper <= -0.5 then
		return "-" .. text
	end
	return signed and c > 0 and ("+" .. text) or text
end

local function Profit(copper)
	if not copper then
		return GREY .. "-|r"
	end
	return (copper >= 0.5 and GREEN or copper <= -0.5 and RED or "") .. Short(copper, true) .. "|r"
end

local function ItemName(item)
	local ok, name = pcall(C_Item.GetItemInfo, ("item:%d"):format(item))
	return ok and type(name) == "string" and not issecret(name) and name or nil
end

local function ItemIcon(item)
	return LT.Value(C_Item.GetItemIconByID, item) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function RecipeName(recipe)
	local name = recipe.item and ItemName(recipe.item)
	if not name then
		local info = LT.Value(C_Spell.GetSpellInfo, recipe.spell)
		name = type(info) == "table" and type(info.name) == "string" and not issecret(info.name) and info.name or nil
	end
	return name or ("#" .. recipe.spell)
end

local function ProfessionName(line)
	local names = ns.RecipeData and ns.RecipeData.names and ns.RecipeData.names[line]
	return names and names[ns.LOCALE == "deDE" and 2 or 1] or tostring(line)
end

-- The skill-up colour of a recipe at a skill (as the profession window has them), nil without numbers.
local function Difficulty(skill, recipe)
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

local function Stale(r)
	return r.oldest and time() - r.oldest > Mg().STALE
end

local function Seconds(s)
	return LT.Decimal(("%.1f"):format(s)) .. " s"
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------

local function Sorted()
	local list = {}
	for _, r in ipairs(results) do
		if r.profit and (not filterLine or r.line == filterLine) then
			list[#list + 1] = r
		end
	end
	local key = sortBy == "craft" and "profit" or "perHour"
	table.sort(list, function(a, b)
		if a[key] ~= b[key] then
			return a[key] > b[key]
		end
		return a.spell < b.spell
	end)
	return list
end

local function FillRow(row, r)
	row.entry = r
	row.Icon:SetTexture(ItemIcon(r.recipe.item))
	local red, green, blue = Difficulty(r.who and r.who.skill, r.recipe)
	row.Dot:SetShown(red ~= nil)
	if red then
		row.Dot:SetColorTexture(red, green, blue)
	end
	row.Name:SetText(C.QualityText(RecipeName(r.recipe), r.recipe.quality))
	row.Profit:SetText(Profit(r.profit))
	row.Hour:SetText(Profit(r.perHour))
	row.Best:SetText(r.best == "ah" and L["AH"] or L["Vendor"])
	row.Age:SetText(r.oldest and LT.Ago(r.oldest) or GREY .. L["vendor"] .. "|r")
	row:SetAlpha(Stale(r) and 0.5 or 1)
	row.Selected:SetShown(r.spell == selected)
end

local function NewRow(parent, width, height)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(width, height)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	row.Selected = row:CreateTexture(nil, "BACKGROUND")
	row.Selected:SetAllPoints()
	row.Selected:SetColorTexture(1, 0.82, 0, 0.15)
	row.Dot = row:CreateTexture(nil, "ARTWORK")
	row.Dot:SetSize(6, 6)
	row.Dot:SetPoint("LEFT", 2, 0)
	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(16, 16)
	row.Icon:SetPoint("LEFT", 12, 0)
	local function Text(x, w, justify)
		local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("LEFT", x, 0)
		fs:SetWidth(w)
		fs:SetJustifyH(justify)
		fs:SetWordWrap(false)
		return fs
	end
	row.Name = Text(32, 170, "LEFT")
	row.Profit = Text(204, 66, "RIGHT")
	row.Hour = Text(272, 66, "RIGHT")
	row.Best = Text(344, 40, "CENTER")
	row.Age = Text(386, width - 388, "RIGHT")
	row:SetScript("OnClick", function(self)
		if self.entry then
			selected = self.entry.spell
			view.list:Lay()
			view.Fill()
		end
	end)
	return row
end

local function Refresh()
	if not view then
		return
	end
	local list = Sorted()
	view.list:SetEntries(list, true)
	local without = 0
	for _, r in ipairs(results) do
		if not r.profit and (not filterLine or r.line == filterLine) then
			without = without + 1
		end
	end
	view.Empty:SetShown(not list[1])
	view.Empty:SetText(results[1] and L["No prices yet: open the auction house and scan your recipes."]
		or L["None of your characters on this realm knows a recipe that makes an item yet."])
	view.Count:SetText(without > 0 and L["%d recipes, %d more without prices yet"]:format(#list, without)
		or L["%d recipes"]:format(#list))
	view.Fill()
end

-- Every recipe of mine worked out again, a few a frame (the frame's OnUpdate goes on with it).
local function Rebuild()
	building = { list = (Mg().MyRecipes()), i = 1, out = {}, rev = Mg().Revision() }
	dirty = false
end

local function BuildStep()
	local started = Clock()
	local b = building
	while b.list[b.i] do
		b.out[#b.out + 1] = Mg().Compute(b.list[b.i])
		b.i = b.i + 1
		if b.i % 10 == 0 and started and Clock() - started >= BUILD_MS then
			return
		end
	end
	results, builtRev, building, lastBuild = b.out, b.rev, nil, GetTime()
	Refresh()
end

---------------------------------------------------------------------------
-- The details
---------------------------------------------------------------------------

local function ReagentTip(row)
	local g = row.reagent
	if not g then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if not pcall(GameTooltip.SetHyperlink, GameTooltip, ("item:%d"):format(g.item)) then
		GameTooltip:AddLine(ItemName(g.item) or ("#" .. g.item))
	end
	local vendor = Mg().VendorPrice(g.item)
	local ah = Mg().AHPrice(g.item)
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine(L["Vendor"], vendor and Short(vendor) or "-", 1, 0.82, 0, 1, 1, 1)
	GameTooltip:AddDoubleLine(L["AH"], ah and ah.p and L["%s (%d listed, %s)"]:format(Short(ah.p), ah.q or 0, LT.Ago(ah.t))
		or ah and L["none listed (%s)"]:format(LT.Ago(ah.t)) or L["not scanned"], 1, 0.82, 0, 1, 1, 1)
	GameTooltip:AddDoubleLine(L["In your bags"], tostring(g.have), 1, 0.82, 0, 1, 1, 1)
	GameTooltip:Show()
end

local function SourceText(g)
	if g.source == "ah" then
		return (g.few and RED or "") .. L["AH"] .. "|r"
	elseif g.source == "vendor" then
		return L["Vendor"]
	end
	return RED .. L["no price"] .. "|r"
end

local function Fill()
	local d = view.detail
	local r = selected and Mg().Recipe(selected)
	d:SetShown(r ~= nil)
	view.Hint:SetShown(r == nil)
	if not r then
		return
	end
	local recipe = r.recipe
	d.Icon:SetTexture(ItemIcon(recipe.item))
	d.Name:SetText(C.QualityText(RecipeName(recipe), recipe.quality) .. (r.yield > 1 and (" x" .. r.yield) or ""))
	local who = r.who
	d.Who:SetText(who and L["%s, %s %d"]:format(LT.Window.ClassColorCode(who.classFile) .. (who.name or "?") .. "|r",
		ProfessionName(r.line), who.skill or 0) or ProfessionName(r.line))
	for i = 1, REAGENTS do
		local row, g = d.rows[i], r.reagents[i]
		row.reagent = g
		row:SetShown(g ~= nil)
		if g then
			row.Icon:SetTexture(ItemIcon(g.item))
			row.Name:SetText(("%s x%d"):format(ItemName(g.item) or "...", g.n))
			row.Price:SetText(SourceText(g) .. "  " .. (g.unit and Short(g.unit * g.n) or "-"))
		end
	end
	d.Numbers:ClearAllPoints()
	d.Numbers:SetPoint("TOPLEFT", d, "TOPLEFT", 0, -46 - #r.reagents * REAGENT_H - 8)
	local labels, values = {}, {}
	local function Line(label, value)
		labels[#labels + 1], values[#values + 1] = label, value
	end
	Line(L["Cost per craft"], r.complete and Short(r.cost) or RED .. L["missing a price"] .. "|r")
	Line(L["Sold to a vendor"], r.vendorRevenue and (Short(r.vendorRevenue) .. "  " .. Profit(r.vendorProfit))
		or GREY .. L["vendors don't buy it"] .. "|r")
	Line(L["On the AH, after the 5% cut"], r.ahRevenue and (Short(r.ahRevenue) .. "  " .. Profit(r.ahProfit))
		or GREY .. (r.ahScanned and L["none listed"] or L["not scanned"]) .. "|r")
	Line(L["Profit per craft"], r.profit and (Profit(r.profit) .. " " .. GREY .. "(" .. (r.best == "ah" and L["AH"] or L["Vendor"]) .. ")|r") or "-")
	Line(L["Time per craft"], Seconds(r.seconds))
	Line(L["Gold per hour"], Profit(r.perHour))
	Line(L["Your bags"], L["enough for %d crafts"]:format(r.covers))
	Line(L["Prices"], r.oldest and LT.Ago(r.oldest) or L["vendor prices only"])
	d.Labels:SetText(table.concat(labels, "\n"))
	d.Values:SetText(table.concat(values, "\n"))
	local notes = {}
	if r.few then
		local few = {}
		for _, g in ipairs(r.reagents) do
			if g.few then
				few[#few + 1] = ItemName(g.item) or ("#" .. g.item)
			end
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
	d.Notes:SetText(GREY .. table.concat(notes, "\n") .. "|r")
	local status = Mg().Status()
	d.Check:SetEnabled(status.open and not (status.running and status.kind == "replicate"))
	d.Check:SetText(status.running and status.spell == r.spell and L["Checking..."] or L["Check AH"])
	d.Open:SetShown(LT.Value(C_SpellBook.IsSpellKnown, r.spell) == true)
end

local function BuildDetail(parent)
	local d = CreateFrame("Frame", nil, parent)
	d:SetPoint("TOPLEFT", DETAIL_X, -INSET_Y - 8)
	d:SetSize(DETAIL_W, H - INSET_Y - 50)
	d.Icon = d:CreateTexture(nil, "ARTWORK")
	d.Icon:SetSize(36, 36)
	d.Icon:SetPoint("TOPLEFT")
	d.Name = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	d.Name:SetPoint("TOPLEFT", 42, -2)
	d.Name:SetWidth(DETAIL_W - 42)
	d.Name:SetJustifyH("LEFT")
	d.Who = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	d.Who:SetPoint("TOPLEFT", 42, -22)
	d.Who:SetWidth(DETAIL_W - 42)
	d.Who:SetJustifyH("LEFT")
	d.rows = {}
	for i = 1, REAGENTS do
		local row = CreateFrame("Button", nil, d)
		row:SetSize(DETAIL_W, REAGENT_H)
		row:SetPoint("TOPLEFT", 0, -46 - (i - 1) * REAGENT_H)
		row.Icon = row:CreateTexture(nil, "ARTWORK")
		row.Icon:SetSize(16, 16)
		row.Icon:SetPoint("LEFT")
		row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.Name:SetPoint("LEFT", 20, 0)
		row.Name:SetWidth(DETAIL_W - 130)
		row.Name:SetJustifyH("LEFT")
		row.Name:SetWordWrap(false)
		row.Price = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.Price:SetPoint("RIGHT")
		row.Price:SetJustifyH("RIGHT")
		row:SetScript("OnEnter", ReagentTip)
		row:SetScript("OnLeave", function(self)
			if GameTooltip:IsOwned(self) then
				GameTooltip:Hide()
			end
		end)
		d.rows[i] = row
	end
	d.Numbers = CreateFrame("Frame", nil, d)
	d.Numbers:SetSize(DETAIL_W, 130)
	d.Labels = d.Numbers:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	d.Labels:SetPoint("TOPLEFT")
	d.Labels:SetJustifyH("LEFT")
	d.Labels:SetSpacing(3)
	d.Values = d.Numbers:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	d.Values:SetPoint("TOPRIGHT")
	d.Values:SetJustifyH("RIGHT")
	d.Values:SetSpacing(3)
	d.Notes = d.Numbers:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	d.Notes:SetPoint("TOPLEFT", 0, -124)
	d.Notes:SetWidth(DETAIL_W)
	d.Notes:SetJustifyH("LEFT")
	d.Check = LT.Window.AddButton(d, L["Check AH"], function()
		if selected and Mg().ScanRecipe(selected) then
			Fill()
		end
	end, { "BOTTOMLEFT", d, "BOTTOMLEFT", 0, 0 })
	d.Check:SetWidth(110)
	d.Open = LT.Window.AddButton(d, L["Show in my profession window"], function()
		if selected and C.OpenInMyProfessionWindow then
			C.OpenInMyProfessionWindow(selected)
		end
	end, { "BOTTOMLEFT", d, "BOTTOMLEFT", 116, 0 })
	d.Open:SetWidth(DETAIL_W - 116)
	return d
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function UpdateScan()
	local status = Mg().Status()
	local b = view.Scan
	if status.running then
		b:SetText(L["Stop"])
		b:SetEnabled(true)
		if status.kind == "replicate" and status.total == 0 then
			view.Status:SetText(L["Asking the auction house for everything..."])
		elseif status.kind == "replicate" then
			view.Status:SetText(L["Reading the auction house: %d of %d"]:format(status.done, status.total))
		else
			view.Status:SetText(L["Scanning: %d of %d items"]:format(status.done, status.total))
		end
	else
		local resume = status.left and status.items and status.left > 0 and status.left < status.items
		b:SetText(resume and L["Go on (%d left)"]:format(status.left) or L["Scan all my recipes"])
		b:SetEnabled(status.open)
		view.Status:SetText(status.open and "" or L["Open the auction house to scan."])
	end
end

local function PickerEntries()
	local entries = { { text = L["All professions"], value = 0, selected = filterLine == nil } }
	local has = {}
	for _, entry in ipairs((Mg().MyRecipes())) do
		has[entry.line] = true
	end
	for _, line in ipairs(ns.RecipeData and ns.RecipeData.order or {}) do
		if has[line] then
			entries[#entries + 1] = { text = ProfessionName(line), value = line, selected = filterLine == line }
		end
	end
	return entries
end

local function Pick(value)
	filterLine = value ~= 0 and value or nil
	view.Picker:SetLabel(filterLine and ProfessionName(filterLine) or L["All professions"])
	Refresh()
end

local function SortLabel()
	return sortBy == "craft" and L["Sort: profit per craft"] or L["Sort: gold per hour"]
end

local function OnUpdate(_, elapsed)
	if building then
		BuildStep()
	end
	sinceTick = sinceTick + elapsed
	if sinceTick < TICK then
		return
	end
	sinceTick = 0
	if not Mg().Enabled() then
		frame:Hide()
		return
	end
	UpdateScan()
	-- Worked out again: at once when prices or recipes changed, else (items' data coming in, the bags, prices
	-- during a scan) at most every REBUILD_GAP.
	local status = Mg().Status()
	local changed = builtRev ~= Mg().Revision()
	local due = (changed and not status.running) or ((changed or dirty) and GetTime() - lastBuild >= REBUILD_GAP)
	if not building and due then
		Rebuild()
		view.Fill() -- (the details at once: a recipe checked shows its prices)
	end
end

local function OnEvent()
	dirty = true -- (GET_ITEM_INFO_RECEIVED, BAG_UPDATE_DELAYED: worked out again on the tick)
end

local function Build()
	frame = LT.Window.Create("LefthyToolsMarginsFrame", L["Crafting margins"], W, H)
	view = {}
	view.Picker = LT.Window.AddPicker(frame, 190, PickerEntries, Pick)
	view.Picker:SetPoint("TOPLEFT", 14, -30)
	view.Picker:SetLabel(L["All professions"])
	view.Sort = LT.Window.AddButton(frame, SortLabel(), function(self)
		sortBy = sortBy == "craft" and "hour" or "craft"
		self:SetText(SortLabel())
		Refresh()
	end, { "TOPLEFT", frame, "TOPLEFT", 212, -31 })
	view.Sort:SetWidth(170)
	view.Scan = LT.Window.AddButton(frame, L["Scan all my recipes"], function()
		local status = Mg().Status()
		if status.running then
			Mg().Cancel()
		else
			Mg().ScanAll()
		end
		UpdateScan()
	end, { "TOPRIGHT", frame, "TOPRIGHT", -14, -31 })
	view.Scan:SetWidth(170)
	local head = CreateFrame("Frame", nil, frame)
	head:SetPoint("TOPLEFT", INSET_X + 6, -INSET_Y - 4)
	head:SetSize(LIST_W, 16)
	local function Title(text, x, w, justify)
		local fs = head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		fs:SetPoint("LEFT", x, 0)
		fs:SetWidth(w)
		fs:SetJustifyH(justify)
		fs:SetText(text)
	end
	Title(L["Recipe"], 32, 170, "LEFT")
	Title(L["Profit"], 204, 66, "RIGHT")
	Title(L["Gold/hour"], 272, 66, "RIGHT")
	Title(L["Sells"], 344, 40, "CENTER")
	Title(L["Prices"], 386, LIST_W - 388, "RIGHT")
	view.list = C.NewList(frame, INSET_X + 6, INSET_Y + LIST_Y, LIST_W, H - INSET_Y - LIST_Y - 40, ROW_H, NewRow, FillRow)
	view.Empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	view.Empty:SetPoint("TOPLEFT", INSET_X + 16, -INSET_Y - LIST_Y - 12)
	view.Empty:SetWidth(LIST_W - 20)
	view.Empty:SetJustifyH("LEFT")
	view.detail = BuildDetail(frame)
	view.Hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	view.Hint:SetPoint("TOPLEFT", DETAIL_X, -INSET_Y - 12)
	view.Hint:SetWidth(DETAIL_W)
	view.Hint:SetJustifyH("LEFT")
	view.Hint:SetText(L["Click a recipe for its numbers."])
	view.Count = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	view.Count:SetPoint("BOTTOMLEFT", 14, 9)
	view.Status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	view.Status:SetPoint("BOTTOMRIGHT", -14, 9)
	view.Fill = Fill
	frame:SetScript("OnUpdate", OnUpdate)
	frame:SetScript("OnEvent", OnEvent)
	frame:HookScript("OnShow", function()
		frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
		frame:RegisterEvent("BAG_UPDATE_DELAYED")
		dirty, sinceTick, lastBuild = true, TICK, -math.huge
	end)
	frame:HookScript("OnHide", function()
		frame:UnregisterAllEvents()
		building = nil
	end)
	frame.view = view
	C.marginsFrame = frame
end

-- Right of a window of Blizzard's if there's room, else in the middle.
local function Place(nextTo)
	frame:ClearAllPoints()
	local ok, left, top, width, scale = pcall(function()
		return nextTo:GetLeft(), nextTo:GetTop(), nextTo:GetWidth(), nextTo:GetEffectiveScale() / frame:GetEffectiveScale()
	end)
	if ok and type(left) == "number" and type(top) == "number" and type(width) == "number" then
		local x = (left + width) * scale + NEXT_TO_GAP
		if x + W <= UIParent:GetWidth() then
			frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, top * scale)
			return
		end
	end
	frame:SetPoint("CENTER")
end

-- Opens the window, on a recipe (spell) if given, next to a frame of Blizzard's if given.
function C.OpenMargins(spell, nextTo)
	if not (Mg() and Mg().Enabled()) then
		M:Print(L["Crafting margins are off: Chronicle's settings switch them on."])
		return
	end
	if not frame then
		Build()
	end
	selected = spell or selected
	if nextTo and not frame:IsShown() then
		Place(nextTo)
	end
	frame:Show()
	Fill()
end

function C.ToggleMargins()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		C.OpenMargins()
	end
end

---------------------------------------------------------------------------
-- Buttons on Blizzard's windows
---------------------------------------------------------------------------

local function Form()
	local page = _G.ProfessionsFrame and ProfessionsFrame.CraftingPage
	return page and page.SchematicForm
end

-- The recipe the profession window shows, as the data has it: its ID, else one of mine of the same name
-- (Forever has copies of some recipes under other IDs).
local function ShownRecipe()
	local form = Form()
	local ok, info = pcall(function() return form:GetRecipeInfo() end)
	if not (ok and type(info) == "table") then
		return nil
	end
	local id = info.recipeID
	local R = C.Recipes
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

local function UpdateProfButton()
	if profButton then
		profButton:SetShown(Mg().Enabled() and ShownRecipe() ~= nil)
	end
end

local function ButtonTip(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(L["Crafting margins"])
	GameTooltip:AddLine(self.tip, 1, 1, 1, true)
	GameTooltip:Show()
end

local function SmallButton(parent, onClick, tip)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(80, 20)
	b:SetText(L["Margins"])
	b:SetScript("OnClick", onClick)
	b.tip = tip
	b:SetScript("OnEnter", ButtonTip)
	b:SetScript("OnLeave", function(self)
		if GameTooltip:IsOwned(self) then
			GameTooltip:Hide()
		end
	end)
	return b
end

local function HookProfessions()
	local form = Form()
	if profButton or not form then
		return
	end
	profButton = SmallButton(form, function()
		local spell = ShownRecipe()
		if spell then
			C.OpenMargins(spell, ProfessionsFrame)
			Mg().ScanRecipe(spell)
		end
	end, L["What this recipe costs and brings, and gold per hour. With the auction house open, its prices are checked there."])
	profButton:SetPoint("TOPRIGHT", form, "TOPRIGHT", -8, -8)
	if type(form.Init) == "function" then
		hooksecurefunc(form, "Init", function() C_Timer.After(0, UpdateProfButton) end)
	end
	form:HookScript("OnShow", function() C_Timer.After(0, UpdateProfButton) end)
	UpdateProfButton()
end

local function HookAuctionHouse()
	local ah = _G.AuctionHouseFrame
	if ahButton or not ah then
		return
	end
	ahButton = SmallButton(ah, function()
		C.OpenMargins(nil, AuctionHouseFrame)
	end, L["Your recipes' margins at this auction house: scan them all from there."])
	ahButton:SetPoint("TOPRIGHT", ah, "TOPRIGHT", -26, -1)
	ahButton:SetShown(Mg().Enabled())
end

-- Margins.lua: switched on or off.
function C.MarginsUIChanged()
	C_Timer.After(0, function()
		HookProfessions()
		HookAuctionHouse()
		UpdateProfButton()
		if ahButton then
			ahButton:SetShown(Mg().Enabled())
		end
		if frame and not Mg().Enabled() then
			frame:Hide()
		end
	end)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, addon)
	if addon == "Blizzard_Professions" then
		C_Timer.After(0, HookProfessions)
	elseif addon == "Blizzard_AuctionHouseUI" then
		C_Timer.After(0, HookAuctionHouse)
	end
end)
