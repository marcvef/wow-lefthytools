local _, ns = ...
local LT = ns.LT
local L = ns.L
local C = ns.Chronicle
local M = C.module

-- "Craftable by" in item tooltips (setting craftTooltip): which of my characters and my friends' know a
-- recipe that makes the item, best skill first, at most NAMES of them by the names the Professions tab
-- gives them; Shift held adds the recipe's reagents. Only what C.Recipes knows: R.Makers (what makes an
-- item, from the data), R.People (who has a profession and which recipes they know), R.Professions.
--
-- Cost: a hover is a table lookup. An item's lines are made the first time it's hovered and kept until
-- R.Revision moves (a list or a skill changed, mine or a friend's); R.Makers is built on Chronicle's
-- tick the first time a tooltip asks, so the very first hovers after logging in may show nothing yet.
-- The game's own tooltips only, GameTooltip and ItemRefTooltip (chat links): bags, vendors, the auction
-- house, quest rewards. Not the comparison tooltips, nor the Professions tab's own (it says who knows it).

local NAMES = 3
local GREY = "|cff888888"
local LABEL_R, LABEL_G, LABEL_B = 1, 0.82, 0 -- (the game's gold)
local issecret = LT.IsSecret

local lines, linesRev = {}, nil -- item -> { text, maker } or false (nobody); the revision they're of
local reagentText = {}          -- recipe -> its reagents' line, once every name was there
local asked = {}                -- items whose data was asked for

-- Who knows a recipe that makes the item: { { who, maker }, ... }, best skill first (the tab's order for
-- the same skill), each character once (two recipes or professions making it: the best).
local function Crafters(R, makers)
	local found, seen = {}, {}
	for _, maker in ipairs(makers) do
		for _, who in ipairs(R.People(maker.line)) do
			if who.known and who.known[maker.spell] then
				found[#found + 1] = { who = who, maker = maker, order = #found + 1 }
			end
		end
	end
	table.sort(found, function(x, y)
		if (x.who.skill or 0) ~= (y.who.skill or 0) then
			return (x.who.skill or 0) > (y.who.skill or 0)
		end
		return x.order < y.order
	end)
	local list = {}
	for _, entry in ipairs(found) do
		if not seen[entry.who.id] then
			seen[entry.who.id] = true
			list[#list + 1] = entry
		end
	end
	return list
end

-- "Craftable by: <name> (Tailoring 152), ..." and the best one's recipe; false: nobody knows one.
local function Build(R, item)
	local makers = R.Makers(item)
	if not makers then
		return makers -- (false: nothing makes it; nil: not known yet, asked again next time)
	end
	local list = Crafters(R, makers)
	if not list[1] then
		return false
	end
	local professionName = {}
	for _, prof in ipairs(R.Professions()) do
		professionName[prof.line] = prof.name
	end
	local names = {}
	for i = 1, math.min(NAMES, #list) do
		local who, line = list[i].who, list[i].maker.line
		names[i] = LT.Window.ClassColorCode(who.classFile) .. (who.name or "?") .. "|r" .. C.Mark(who.partial)
			.. GREY .. " (" .. (professionName[line] or tostring(line)) .. " " .. (who.skill or 0) .. ")|r"
	end
	local text = L["Craftable by: %s"]:format(table.concat(names, ", "))
	if #list > NAMES then
		text = text .. " " .. GREY .. L["+%d more"]:format(#list - NAMES) .. "|r"
	end
	return { text = text, maker = list[1].maker }
end

local function ItemName(id)
	local name = LT.Value(C_Item.GetItemInfo, ("item:%d"):format(id))
	if type(name) == "string" then
		return name
	end
	if not asked[id] and C_Item.RequestLoadItemDataByID then
		asked[id] = true
		pcall(C_Item.RequestLoadItemDataByID, id)
	end
end

-- "Reagents: Linen Cloth x2, Coarse Thread x1" (nil: the data has none). Kept once every name came;
-- until then "..." for a name, and made again on the next hover (the game asked for it meanwhile).
local function Reagents(R, maker)
	local recipe = R.MakerRecipe and R.MakerRecipe(maker)
	if not (recipe and recipe.reagents and recipe.reagents[1]) then
		return nil
	end
	local text = reagentText[recipe]
	if text then
		return text
	end
	local parts, complete = {}, true
	for i, reagent in ipairs(recipe.reagents) do
		local id, n = reagent.item or reagent[1], reagent.n or reagent[2] or 1
		local name = id and ItemName(id)
		complete = complete and name ~= nil
		parts[i] = ("%s x%d"):format(name or "...", n)
	end
	text = L["Reagents: %s"]:format(table.concat(parts, ", "))
	if complete then
		reagentText[recipe] = text
	end
	return text
end

local function OnItemTooltip(tooltip, info)
	if not (M.enabled and M.db.craftTooltip) or (tooltip ~= GameTooltip and tooltip ~= _G.ItemRefTooltip) then
		return
	end
	local item = info and info.id
	if type(item) ~= "number" or issecret(item) then
		return
	end
	local R = C.Recipes
	if not (R and R.Makers) then
		return
	end
	local rev = R.Revision()
	if rev ~= linesRev then
		linesRev = rev
		wipe(lines)
	end
	local entry = lines[item]
	if entry == nil then
		entry = Build(R, item)
		lines[item] = entry -- (nil, while R.Makers is being built: tried again)
	end
	if not entry then
		return
	end
	tooltip:AddLine(entry.text, LABEL_R, LABEL_G, LABEL_B, true)
	if IsShiftKeyDown() then
		local reagents = Reagents(R, entry.maker)
		if reagents then
			tooltip:AddLine(reagents, 0.8, 0.8, 0.8, true)
		end
	end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, info)
		LT.Guard("C.CraftedBy", OnItemTooltip, tooltip, info)
	end)
end
