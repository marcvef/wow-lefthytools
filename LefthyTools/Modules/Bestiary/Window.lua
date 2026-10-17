local _, ns = ...
local LT = ns.LT
local L = ns.L
local Bt = ns.Bestiary
local M = Bt.module

-- The Bestiary's window: your target's drops. At the top the mob: a small still portrait, its
-- name, level and kind, your kills and the coin each brought, and (when known) a small grey line on
-- what a kill pays: its worth (coin and the drops' vendor value), XP and how long it takes (hover:
-- in full). Under it its drops, the likeliest
-- first: an icon edged in its quality's colour, how many you got in its corner, the drop chance
-- under it; the item's tooltip with the numbers on hover, Shift-click links it. It follows your
-- target (a mob you can attack, or a dead one) and keeps the last when you clear it. It stays
-- open: Escape doesn't close it, only its X, the minimap button or /bestiary. Where it is and
-- whether it's open are kept. (Its drops are cells: Cells.lua; its texts: Format.lua.)
--
-- The classic drop database (Classic.lua, setting dropData) beside your numbers: each drop's
-- tooltip has its chance there. With the setting windowUnseen (off: the user wanted the window
-- without it), what it says the mob drops that you haven't had yet is a section of its own under
-- your drops, smaller and faded (grey icons, how many of its drops you've found), each with the
-- item's tooltip, the database's chance and how many you'd have expected by now; for a mob you
-- haven't killed, what it can drop.
--
-- Quest drops (Quests.lua): while a quest wants an item this mob drops, the window has a line for
-- it under the header ("Gnoll Paw: 3/8, 40% each, about 12 more kills", the quest's "!" in front).
--
-- The wish list (Wishes.lua): Alt-click on a drop here or in the ledger pins it (or unpins it).
-- Wished drops have a small star wherever they show; item tooltips say it's on your wish list.
--
-- Also here: the minimap button, and what's drawn again when things change (Bt.Redraw).

local WIDTH = 236
local PAD = 10
local ICON, GAP, PER_ROW, ROWS = 30, 8, 6, 4
local CELL_H = ICON + 16
local HEADER = 62
local PACE_H = 13       -- the header's line on what a kill pays, when there's something to say
local PORTRAIT = 40
local LINE = 14
local KNOWN_ICON, KNOWN_GAP, KNOWN_ROWS = 22, 6, 2 -- not seen yet (the classic database): smaller, faded
local KNOWN_PER_ROW = math.floor((WIDTH - 2 * PAD + KNOWN_GAP) / (KNOWN_ICON + KNOWN_GAP))
local KNOWN_HEAD = 16   -- its heading's height
local QUEST_LINES = 3   -- quests wanting its drops: a line each in the window, at most
local BUTTON_ICON = "Interface\\Icons\\INV_Misc_Bag_10"
local GOLD, NONE, Value, QUESTION, ALL_FOUND = Bt.GOLD, Bt.NONE, Bt.Value, Bt.QUESTION, Bt.ALL_FOUND
local Dress, Lay, Kind, KillsLine, PaceText, QuestLine = Bt.Dress, Bt.Lay, Bt.Kind, Bt.KillsLine, Bt.PaceText, Bt.QuestLine

local win, button
local shown, shownInfo -- the creature the window shows, and what was seen of it (name, level, class)

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function SavePlace()
	local left, top = win:GetLeft(), win:GetTop()
	if left and top then
		local ratio = win:GetEffectiveScale() / UIParent:GetEffectiveScale()
		M.db.window.left, M.db.window.top = left * ratio, top * ratio
	end
end

local function Place()
	local saved = M.db.window
	win:ClearAllPoints()
	if tonumber(saved.left) and tonumber(saved.top) then
		win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.left, saved.top)
	else
		win:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -240, -200) -- (at first: right of the middle, out of the way)
	end
end

local function PortraitLoaded(model)
	model:RefreshCamera()
	model:SetPaused(true) -- (still)
end

local function Build()
	win = CreateFrame("Frame", "LefthyToolsBestiaryFrame", UIParent)
	win:SetSize(WIDTH, 120)
	win:SetFrameStrata("MEDIUM")
	win:SetClampedToScreen(true)
	win:EnableMouse(true)
	win:SetMovable(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		self:SetUserPlaced(false)
		SavePlace()
	end)
	win:Hide()
	Dress(win)

	win.Close = CreateFrame("Button", nil, win, "UIPanelCloseButtonNoScripts")
	win.Close:SetPoint("TOPRIGHT", -2, -2)
	win.Close:SetScript("OnClick", function() Bt.Toggle(false) end)
	-- The ledger (every mob, search): a small book left of the X.
	win.Ledger = CreateFrame("Button", nil, win)
	win.Ledger:SetSize(16, 16)
	win.Ledger:SetPoint("RIGHT", win.Close, "LEFT", -2, 0)
	win.Ledger:SetNormalTexture("Interface\\Icons\\INV_Misc_Book_11")
	win.Ledger:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	win.Ledger:SetScript("OnClick", function() Bt.LedgerButton() end)
	win.Ledger:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(L["The ledger"], 1, 1, 1)
		GameTooltip:AddLine(L["Every mob you've killed, its statistics and drops; search mobs and items."], 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	win.Ledger:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- The mob: a still portrait in a dark square, its name, level and kind, kills and coin.
	win.PortraitBack = win:CreateTexture(nil, "BORDER")
	win.PortraitBack:SetPoint("TOPLEFT", PAD, -PAD)
	win.PortraitBack:SetSize(PORTRAIT + 2, PORTRAIT + 2)
	win.PortraitBack:SetColorTexture(0, 0, 0, 0.6)
	win.Portrait = CreateFrame("PlayerModel", nil, win)
	win.Portrait:SetPoint("TOPLEFT", win.PortraitBack, "TOPLEFT", 1, -1)
	win.Portrait:SetSize(PORTRAIT, PORTRAIT)
	win.Portrait:SetPortraitZoom(1)
	win.Portrait:SetScript("OnModelLoaded", PortraitLoaded)
	win.Unknown = win:CreateTexture(nil, "ARTWORK")
	win.Unknown:SetAllPoints(win.Portrait)
	win.Unknown:SetTexture(QUESTION)
	win.Unknown:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	win.Unknown:SetAlpha(0.5)
	win.Name = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	win.Name:SetPoint("TOPLEFT", win.PortraitBack, "TOPRIGHT", 8, -1)
	win.Name:SetPoint("RIGHT", win.Ledger, "LEFT", -2, 0)
	win.Name:SetJustifyH("LEFT")
	win.Name:SetWordWrap(false)
	win.Kind = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	win.Kind:SetPoint("TOPLEFT", win.Name, "BOTTOMLEFT", 0, -2)
	win.Kills = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	win.Kills:SetPoint("TOPLEFT", win.Kind, "BOTTOMLEFT", 0, -3)
	win.Kills:SetPoint("RIGHT", -PAD, 0)
	win.Kills:SetJustifyH("LEFT")
	win.Kills:SetWordWrap(false)
	-- What a kill pays (worth, XP, how long it takes), small and grey under the portrait, the window
	-- wide; hover: the same in full, with the XP per hour of fighting.
	win.Pace = CreateFrame("Button", nil, win)
	win.Pace:SetPoint("TOPLEFT", PAD, -(HEADER - 6))
	win.Pace:SetSize(WIDTH - 2 * PAD, PACE_H)
	win.Pace.Text = win.Pace:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	win.Pace.Text:SetPoint("LEFT")
	win.Pace.Text:SetPoint("RIGHT")
	win.Pace.Text:SetJustifyH("LEFT")
	win.Pace.Text:SetWordWrap(false)
	win.Pace:SetScript("OnEnter", function(self)
		local _, lines = PaceText(Bt.Mob(shown))
		if #lines > 0 then
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:SetText(lines[1], 1, 1, 1)
			for i = 2, #lines do
				GameTooltip:AddLine(lines[i], 0.8, 0.8, 0.8, true)
			end
			GameTooltip:Show()
		end
	end)
	win.Pace:SetScript("OnLeave", function() GameTooltip:Hide() end)
	win.Rule = win:CreateTexture(nil, "ARTWORK")
	win.Rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
	win.Rule:SetHeight(1)
	-- Quests wanting its drops: a line each, under the header (placed when drawn: under the line of
	-- what a kill pays, when there is one).
	win.Quest = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	win.Quest:SetWidth(WIDTH - 2 * PAD)
	win.Quest:SetJustifyH("LEFT")
	win.Quest:SetSpacing(2)

	-- The drops, and a line under them when there's something to say.
	win.Grid = CreateFrame("Frame", nil, win)
	win.Grid:SetSize(WIDTH - 2 * PAD, 10)
	win.cells = {}
	-- Not seen yet (the classic database): a heading with a rule and how many of its drops you've
	-- found, then its drops, smaller and faded.
	win.KnownLabel = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	win.KnownCount = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	win.KnownRule = win:CreateTexture(nil, "ARTWORK")
	win.KnownRule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.18)
	win.KnownRule:SetHeight(1)
	win.KnownRule:SetPoint("LEFT", win.KnownLabel, "RIGHT", 6, 0)
	win.KnownRule:SetPoint("RIGHT", win.KnownCount, "LEFT", -6, 0)
	win.Known = CreateFrame("Frame", nil, win)
	win.Known:SetSize(WIDTH - 2 * PAD, 10)
	win.knownCells = {}
	win.Note = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	win.Note:SetWidth(WIDTH - 2 * PAD)
	win.Note:SetJustifyH("CENTER")
	Place()
end

-- Drawn from the top down, each part where the one above it ends (the window shows creature
-- `shown`, nil: none yet; shownInfo: what was seen of it).

-- You've killed or skinned one: what it can drop is "not seen yet" rather than "what it can drop".
local function Tried(mob)
	return mob and (mob.kills > 0 or (mob.skinned or 0) > 0)
end

-- The header: portrait, name, level and kind, kills and coin; what a kill pays, when something's
-- known (the header grows by a line). Returns its height.
local function DrawHeader(mob, info)
	if win.creature ~= shown then
		win.creature = shown
		win.Portrait:ClearModel()
		if shown then
			win.Portrait:SetCreature(shown)
		end
	end
	win.Portrait:SetShown(shown ~= nil)
	win.Unknown:SetShown(shown == nil)
	local name = info.name or mob and mob.name
	win.Name:SetText(name or "Bestiary") -- (module names aren't translated)
	win.Kind:SetText(shown and Kind({ level = info.level or mob and mob.level, class = info.class or mob and mob.class }) or "")
	win.Kills:SetText(mob and KillsLine(mob) or "")
	local pace = PaceText(mob)
	win.Pace.Text:SetText(pace or "")
	win.Pace:SetShown(pace ~= nil)
	local head = HEADER + (pace and PACE_H or 0)
	win.Rule:ClearAllPoints()
	win.Rule:SetPoint("TOPLEFT", PAD, -head + 4)
	win.Rule:SetPoint("TOPRIGHT", -PAD, -head + 4)
	return head
end

-- Quests wanting its drops, a line each (the ones still wanted first), at y; returns their height
-- (0: none).
local function DrawQuests(mob, y)
	local wanted, lines = Bt.QuestDrops(shown, mob), {}
	for i = 1, math.min(#wanted, QUEST_LINES) do
		lines[i] = QuestLine(wanted[i])
	end
	win.Quest:ClearAllPoints()
	win.Quest:SetPoint("TOPLEFT", PAD, -y)
	win.Quest:SetText(table.concat(lines, "\n"))
	win.Quest:SetShown(#lines > 0)
	return #lines > 0 and math.ceil(win.Quest:GetStringHeight()) + 6 or 0
end

-- What the classic database says it drops that you haven't had yet (for a mob you haven't killed:
-- what it can drop), when that's switched on for the window, at top; else nothing, and height stays
-- where everything ends. Returns where everything ends, whether it shows, and the database's list
-- and total (nil: it doesn't know the mob, or the setting is off).
local function DrawUnseen(mob, top, height)
	local unseen, found, total
	if M.db.windowUnseen then
		unseen, found, total = Bt.Compare(shown, mob, M.db.showPoor)
	end
	local tried = Tried(mob)
	local known = unseen ~= nil and #unseen > 0
	if known then
		win.KnownLabel:ClearAllPoints()
		win.KnownLabel:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -top)
		win.KnownLabel:SetText(tried and L["Not seen yet"] or L["What it can drop"])
		win.KnownCount:ClearAllPoints()
		win.KnownCount:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD, -top)
		win.KnownCount:SetText(tried and L["%d of %d found"]:format(found, total) or L["classic database"])
		win.Known:ClearAllPoints()
		win.Known:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + 1, -(top + KNOWN_HEAD))
		local knownRows = Lay(win.Known, win.knownCells, unseen, mob and mob.kills or 0, KNOWN_ICON, KNOWN_GAP, KNOWN_PER_ROW,
			KNOWN_PER_ROW * KNOWN_ROWS, true)
		height = top + KNOWN_HEAD + knownRows * (KNOWN_ICON + LINE + 4)
	elseif win.knownCells[1] then
		Lay(win.Known, win.knownCells, NONE, 0, KNOWN_ICON, KNOWN_GAP, KNOWN_PER_ROW, KNOWN_PER_ROW * KNOWN_ROWS, true)
	end
	win.KnownLabel:SetShown(known)
	win.KnownCount:SetShown(known)
	win.KnownRule:SetShown(known)
	return height, known, unseen, total
end

-- A line under it all when there's something to say (target a mob, no kills yet, nothing or only
-- grey items dropped, all of the database's drops found, in a group nothing counts), at height (a
-- little lower when nothing's above it: any); returns the window's height.
local function DrawNotes(mob, drops, unseen, total, height, any)
	local notes = {}
	if not shown then
		notes[#notes + 1] = L["Target a mob to see what it drops."]
	elseif not mob or mob.kills == 0 then
		notes[#notes + 1] = L["No kills of it yet: kill one on your own and loot it."]
	elseif #drops == 0 then
		notes[#notes + 1] = next(mob.items) and L["Only grey items so far."] or L["Nothing dropped yet."]
	end
	if Tried(mob) and unseen and #unseen == 0 and total > 0 then
		notes[#notes + 1] = ("|T%s:12:12|t "):format(ALL_FOUND) .. L["All %d drops of the classic database found."]:format(total)
	end
	if IsInGroup and IsInGroup() then
		notes[#notes + 1] = L["In a group: kills aren't counted (the loot is shared)."]
	end
	win.Note:ClearAllPoints()
	win.Note:SetPoint("TOP", win, "TOP", 0, -height - (any and 0 or 6))
	win.Note:SetText(table.concat(notes, "\n"))
	win.Note:SetShown(#notes > 0)
	-- (a line each, or more when one wraps: most do in the window's width, in German more so)
	local noteHeight = math.max(#notes * LINE, math.ceil(win.Note:GetStringHeight()))
	return height + (#notes > 0 and (noteHeight + (any and 4 or 10)) or 0) + PAD
end

local function Draw()
	if not (win and win:IsShown()) then
		return
	end
	local mob = Bt.Mob(shown)
	local head = DrawHeader(mob, shownInfo or {})
	local quests = DrawQuests(mob, head)
	-- Its drops under them.
	win.Grid:ClearAllPoints()
	win.Grid:SetPoint("TOPLEFT", PAD + 1, -head - 4 - quests)
	local drops = Bt.Drops(mob, M.db.showPoor, shown)
	local rows = Lay(win.Grid, win.cells, drops, mob and mob.kills or 0, ICON, GAP, PER_ROW, PER_ROW * ROWS, true)
	local height = head + quests + rows * (CELL_H + 4)
	local known, unseen, total
	height, known, unseen, total = DrawUnseen(mob, height + (rows > 0 and 2 or 0), height)
	height = DrawNotes(mob, drops, unseen, total, height, rows > 0 or known or quests > 0)
	win:SetHeight(math.max(height, head + 16))
end
Bt.Draw = Draw

-- The window follows the target: a mob that can be attacked, or a dead one (not a vendor).
local function FollowTarget()
	if not (UnitExists("target") and (Value(UnitCanAttack, "player", "target") or Value(UnitIsDead, "target"))) then
		return false
	end
	local guid, creature = Bt.Look("target")
	if not creature then
		return false
	end
	shown = creature
	local seen = Bt.Seen(guid)
	shownInfo = seen and { name = seen.name, level = seen.level, class = seen.class } or nil
	return true
end

function Bt.TargetChanged()
	if win and win:IsShown() and FollowTarget() then
		Draw()
	end
end

-- The ledger's buttons (the window's book, Ctrl-click on the minimap's): open on the mob shown, or
-- close it when it's open.
function Bt.LedgerButton()
	local ledger = Bt.Ledger and Bt.Ledger()
	if ledger and ledger:IsShown() then
		ledger:Hide()
	else
		Bt.ToggleLedger(shown)
	end
end

-- Open (on true), close (false) or the other way round (nil). Kept for next time.
function Bt.Toggle(on)
	if not M.enabled then
		return
	end
	if on == nil then
		on = not (win and win:IsShown())
	end
	M.db.window.shown = on
	if on then
		if not win then
			Build()
		end
		win:Show()
		FollowTarget()
		Draw()
	elseif win then
		win:Hide()
		GameTooltip:Hide()
	end
	if button then
		button.Open:SetShown(on)
	end
end

-- The quest log changed what your quests want: the window and the card (Card.lua) again.
function Bt.QuestsShown()
	return (win and win:IsShown()) or Bt.CardShown()
end

function Bt.QuestsChanged()
	if win and win:IsShown() then
		Draw()
	end
	if Bt.CardShown() then
		Bt.MouseoverChanged()
	end
end

-- Everything shown again: the wish list changed (its stars everywhere, the ledger's strip), or items
-- the client didn't know came (names, prices): the window, the card, the ledger.
function Bt.Redraw()
	Bt.QuestsChanged()
	if Bt.DrawLedger then
		Bt.DrawLedger()
	end
end

---------------------------------------------------------------------------
-- The minimap button
---------------------------------------------------------------------------

local function ButtonOnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText("Bestiary", 1, 0.82, 0)
	local count, kills = 0, 0
	for _, mob in pairs(LefthyToolsBestiaryDB and LefthyToolsBestiaryDB.mobs or {}) do
		count, kills = count + 1, kills + mob.kills
	end
	GameTooltip:AddLine(L["%d kinds of mobs, %d kills"]:format(count, kills), 1, 1, 1)
	GameTooltip:AddLine(L["Click: open or close the window"], 0.8, 0.8, 0.8)
	GameTooltip:AddLine((M.db.hoverCard and L["Shift-click: drops next to the mouse off"] or L["Shift-click: drops next to the mouse on"]),
		0.8, 0.8, 0.8)
	GameTooltip:AddLine(L["Ctrl-click: the ledger"], 0.8, 0.8, 0.8)
	GameTooltip:AddLine(L["Right-click: settings"], 0.8, 0.8, 0.8)
	GameTooltip:AddLine(L["Drag: move it along the minimap"], 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

local function ButtonOnClick(_, mouseButton)
	if mouseButton == "RightButton" then
		LT:OpenSettings(M)
	elseif IsShiftKeyDown() then
		LT:SetModuleSetting(M, "hoverCard", not M.db.hoverCard)
		M:Print(M.db.hoverCard and "drops next to the mouse: on." or "drops next to the mouse: off.")
	elseif IsControlKeyDown() then
		Bt.LedgerButton()
	else
		Bt.Toggle()
	end
end

local function UpdateButton()
	local show = M.enabled and M.db.minimapButton and Minimap ~= nil
	if show and not button then
		button = LT.Window.MinimapButton("LefthyToolsBestiaryMinimapButton", { icon = BUTTON_ICON, db = M.db,
			angleKey = "minimapAngle", angle = 150, onClick = ButtonOnClick, onEnter = ButtonOnEnter })
		-- The window is open: a small gold dot.
		button.Open = button:CreateTexture(nil, "OVERLAY", nil, 2)
		button.Open:SetSize(7, 7)
		button.Open:SetPoint("TOPRIGHT", -5, -4)
		button.Open:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
		button.Open:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
	end
	if button then
		button:SetShown(show)
		if show then
			button:Place()
		end
		button.Open:SetShown(win ~= nil and win:IsShown())
	end
end

---------------------------------------------------------------------------
-- Switching on and off, settings
---------------------------------------------------------------------------

Bt.OnChanged(function(creature)
	if creature == shown then
		Draw()
	end
end)

-- Switched on (and after login): the button, and the window if it was open.
Bt.When("enable", function()
	C_Timer.After(0, function()
		UpdateButton()
		if M.enabled and M.db.window.shown then
			Bt.Toggle(true)
		end
	end)
end)

-- Switched off: the window hides (whether it was open stays kept).
Bt.When("disable", function()
	if win then
		win:Hide()
	end
	UpdateButton()
end)

Bt.When("settings", function()
	UpdateButton()
	Draw()
end)

Bt.On("PLAYER_TARGET_CHANGED", function() Bt.TargetChanged() end)

-- For tests.
function Bt.Frames()
	return win, Bt.CardFrame(), button
end
