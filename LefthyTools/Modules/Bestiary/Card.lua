local _, ns = ...
local LT = ns.LT
local L = ns.L
local Bt = ns.Bestiary
local M = Bt.module
local NONE, Value = Bt.NONE, Bt.Value
local Dress, Lay, KillsLine, QuestLine = Bt.Dress, Bt.Lay, Bt.KillsLine, Bt.QuestLine

-- The card next to the mouse (setting hoverCard): over an enemy you've killed before, your kills and
-- its likeliest drops, small, following the mouse while it's over it. With the setting cardUnseen
-- (off, like the window's windowUnseen: the user wanted both without it), a mob you haven't killed
-- gets the classic database's likeliest drops, faded. A quest that wants one of its drops adds a
-- line; wished items it drops come first.

local CARD_ICON, CARD_GAP, CARD_CELLS = 22, 5, 6
local CARD_QUEST_W = 250 -- the card's quest line, at most (longer: cut)
local LINE = 14

local card, cardGUID

-- In combat with the setting cardHideInCombat (on): no card (the user: not while fighting). Core's
-- LT.InCombat: the lockdown begins only after PLAYER_REGEN_DISABLED, so InCombatLockdown alone still
-- says no inside it (the card stayed a frame into the fight).
local function CardHidden()
	return M.db.cardHideInCombat and LT.InCombat()
end

local function CardFollow(self)
	if CardHidden() or not (UnitExists("mouseover") and Value(UnitGUID, "mouseover") == cardGUID) then
		self:Hide()
		cardGUID = nil
		return
	end
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	self:ClearAllPoints()
	self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 16, y / scale - 20)
end

local function BuildCard()
	card = CreateFrame("Frame", "LefthyToolsBestiaryCard", UIParent)
	card:SetFrameStrata("TOOLTIP")
	card:SetClampedToScreen(true)
	card:EnableMouse(false)
	card:Hide()
	Dress(card)
	card.Kills = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	card.Kills:SetPoint("TOPLEFT", 8, -7)
	card.Grid = CreateFrame("Frame", nil, card)
	card.Grid:SetPoint("TOPLEFT", 8, -24)
	card.Grid:SetSize(CARD_CELLS * (CARD_ICON + CARD_GAP), CARD_ICON + LINE)
	card.cells = {}
	card.Quest = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	card.Quest:SetJustifyH("LEFT")
	card.Quest:SetWordWrap(false)
	card:SetScript("OnUpdate", CardFollow)
end

-- Wished items a mob drops go first on its card, with their star: yours (a world drop's too), else the
-- classic database's, faded (you haven't had one). drops may be nil (nothing to show otherwise).
local function WishedFirst(creature, mob, drops)
	local wishes = Bt.Wishes()
	if not next(wishes) then
		return drops
	end
	local first, rest, had = {}, {}, {}
	for _, drop in ipairs(drops or NONE) do
		if not drop.group and wishes[drop.id] and not had[drop.id] then
			first[#first + 1], had[drop.id] = drop, true
		else
			rest[#rest + 1] = drop
		end
		for _, inside in ipairs(drop.group or NONE) do
			if wishes[inside.id] and not had[inside.id] then
				first[#first + 1], had[inside.id] = inside, true
			end
		end
	end
	local said = Bt.Known(creature)
	for id in pairs(wishes) do
		local item = not had[id] and said and said.items[id]
		if item then
			first[#first + 1] = { id = id, chance = item[1], quality = item[2], quest = item[3] or nil, unseen = true, drops = 0, count = 0,
				classic = item[1], out = mob and mob.kills or 0 }
		end
	end
	if #first == 0 then
		return drops
	end
	for _, drop in ipairs(rest) do
		first[#first + 1] = drop
	end
	return first
end

-- Over an enemy: its card (setting hoverCard), small on purpose (the user: not "too large and
-- intrusive"): a line and one row of CARD_CELLS icons, never more, and none in combat (setting
-- cardHideInCombat, on; it goes when a fight starts, comes back after). Killed before: your kills and
-- your likeliest drops (not the database's on top); not yet, with the setting cardUnseen (off): the
-- classic database's likeliest, faded. The only line more: a quest that still wants one of its drops
-- (then also over a mob you haven't killed: useful while questing). Wished items it drops come first
-- (also over a mob you haven't killed).
function Bt.MouseoverChanged()
	if not (M.enabled and M.db.hoverCard) or CardHidden() or not UnitExists("mouseover")
		or not (Value(UnitCanAttack, "player", "mouseover") or Value(UnitIsDead, "mouseover")) then
		if card then
			card:Hide()
		end
		return
	end
	local guid, creature = Bt.Look("mouseover")
	local mob = Bt.Mob(creature)
	local drops, line
	local notKilled = "|cff999999" .. L["Not killed yet: classic database"] .. "|r"
	if mob and mob.kills > 0 then
		drops, line = Bt.Drops(mob, M.db.showPoor, creature), KillsLine(mob, true)
	elseif M.db.cardUnseen then
		local unseen = Bt.Compare(creature, mob, M.db.showPoor)
		if unseen and #unseen > 0 then
			drops, line = unseen, notKilled
		end
	end
	drops = WishedFirst(creature, mob, drops)
	-- A quest that still wants one of its drops: a line (and how many more want others).
	local want, others = nil, 0
	for _, wanted in ipairs(Bt.QuestDrops(creature, mob)) do
		if not wanted.done then
			if want then
				others = others + 1
			else
				want = wanted
			end
		end
	end
	if not (drops or want) then
		if card then
			card:Hide()
		end
		return
	end
	if not card then
		BuildCard()
	end
	cardGUID = guid
	drops = drops or NONE
	card.Kills:SetText(line or notKilled)
	local rows = Lay(card.Grid, card.cells, drops, mob and mob.kills or 0, CARD_ICON, CARD_GAP, CARD_CELLS, CARD_CELLS, false)
	local width = math.max(card.Kills:GetStringWidth(), math.min(#drops, CARD_CELLS) * (CARD_ICON + CARD_GAP) - CARD_GAP)
	local height = rows > 0 and (24 + CARD_ICON + LINE + 6) or 24
	if want then
		card.Quest:SetWidth(0) -- (as wide as its text, to measure it)
		card.Quest:SetText(QuestLine(want) .. (others > 0 and ("  |cff888888+%d|r"):format(others) or ""))
		card.Quest:ClearAllPoints()
		card.Quest:SetPoint("TOPLEFT", 8, -(height - 2))
		local questWidth = math.min(card.Quest:GetStringWidth(), CARD_QUEST_W)
		card.Quest:SetWidth(questWidth)
		width, height = math.max(width, questWidth), height + LINE
	end
	card.Quest:SetShown(want ~= nil)
	card:SetSize(width + 16, height)
	CardFollow(card)
	card:Show()
end

-- Whether it's up (the quest log changed, item names came: Window.lua draws it again), and the
-- frame (for tests).
function Bt.CardShown()
	return card ~= nil and card:IsShown()
end

function Bt.CardFrame()
	return card
end

-- Switched off: it hides; the setting off: too.
Bt.When("disable", function()
	if card then
		card:Hide()
	end
end)
Bt.When("settings", function()
	if card and not M.db.hoverCard then
		card:Hide()
	end
end)

Bt.On("UPDATE_MOUSEOVER_UNIT", function() Bt.MouseoverChanged() end)
Bt.On("PLAYER_REGEN_DISABLED", function()
	if card and card:IsShown() and CardHidden() then -- (a fight starts: it goes at once, not on the next frame)
		card:Hide()
		cardGUID = nil
	end
end)
Bt.On("PLAYER_REGEN_ENABLED", function()
	Bt.MouseoverChanged() -- (the fight is over, the mouse still over an enemy: its card)
end)
