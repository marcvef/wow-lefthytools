local _, ns = ...
local LT = ns.LT
local L = ns.L
local Q = ns.Lodestar or {}; ns.Lodestar = Q

-- The small window: the companion. It follows what you're doing without being asked.
--
-- Opened on its own (/lodestar) it shows, top down, only what to do now and how far along (the
-- rest is in the lines' tooltips or behind a click):
--   Plan (only while the plan, Plan.lua, has a stop not done): "Next (2/14): Pick up <quest> at
--     <giver>" with how far and which way, Skip, and a small map of its own with the next stops
--     numbered and joined by a line; a click shows the stop on the big window's map (Q.ShowOnMap).
--   Now: the quest you're on (the last one you accepted, super-tracked or opened in the quest log;
--     else the first on your tracker, else one of your log in this zone), "[18] Title" in its
--     difficulty colour (its tooltip: what it leads to), "Step 3 of 7 · <chain>" and a bar, friends
--     who did it (one line, only when there are any), its objectives or "Ready to turn in", where to
--     turn it in (one line, with how far and which way), and "Steps (7)": the chain's steps, folded
--     until clicked (setting stepsOpen keeps it).
--   The small map: not ready, the areas of its objectives not done (Q.Objectives; hovering an
--     objective's line lights its areas); else the turn-in's zone (else yours) with the turn-in; your
--     other quests' turn-ins and the givers of what you can pick up there, and your arrow.
--   Pick up next, in two groups of at most three, each in the one order of quests (Q.Compare: ready
--     first, then by level; for your level before hard ones): In progress (your other quests) and
--     Available now (for your levels, Q.InRange: follow-ups of what you just finished or have, and
--     this zone's quests, each with its giver, how far and which way; a hard one, orange, says so).
--     What's coming up later or blocked is the big window's. Titles are in their difficulty tier's
--     colour (Q.Tier: the quest's level, its mobs', a group quest one harder).
-- Each line of Pick up next has a verb icon (the game's own: ? to turn in, ! to pick up, in
-- progress, the grey ! of a low quest), the first line full size and the rest smaller with their
-- titles grey (the guides' "this now, then those"), and notes what taking a quest closes
-- (exclusive quests). The window can be one line (setting collapsed, the button in its title bar)
-- and hides itself when there's nothing to show (setting autoHide), coming back on its own when
-- there is. A status says its real reason: "Skipped" (you took another), "Not for your race",
-- "Needs Mining 75", "Needs Friendly with Stormwind", "Needs <the quest first>".
-- A click on a quest shows everything about it (its title, chain, status, what it needs first,
-- giver and turn-in, where its item drops, the map, what it leads to, friends); at the top then
-- "« Back to <the quest before>" and "Back to now". A click on a giver, turn-in or map marker sets
-- the game's own map pin there (Q.Waypoint), Shift-click puts it in the chat box too.
--
-- While it's shown it listens to the quest log (accepted, turned in, abandoned, progress), super
-- tracking, the tracker, level-ups and zone changes, and redraws a moment later; every 2 s it looks
-- whether you've moved (the distances); the quest log's "show details" (Lodestar.lua's hook) hands
-- it the quest you opened there. Hidden, it listens to nothing and nothing of it runs. A window of
-- ours (LT.Window.Create: Escape closes it, it counts as an open window for Mirage), movable and
-- resizable, where it is and its size kept (setting keepPlace). Built the first time it opens; the
-- data loads then too (Q.Ready), never at login. Every line that does something is a button, so a
-- controller's cursor reaches it.
--   Q.ToggleSmall(), Q.ShowQuest(id), Q.RedrawSmall(now), Q.IsSmallShown(), Q.SmallFollow(id);
--   Q.SmallFrame() for tests.

local NAME = "LefthyToolsLodestarSmall"
local WIDTH, HEIGHT = 340, 580
local MIN_W, MIN_H, MAX_W, MAX_H = 300, 300, 600, 950
local SCROLL_SIDE = 60 -- the scroll area's child is the window's width less this (LT.Window.AddScroll)
local GAP = 4
local INDENT = 10
local LIST_MAX = 8       -- lines of "Needs first" and "Leads to" (the rest: "and N more")
local STEPS_MAX = 8      -- a chain's steps in sight (from two before this one)
local OBJECTIVES_MAX = 6
local LOG_MAX, PICK_MAX = 3, 3 -- Pick up next: In progress, Available now
local HISTORY = 20       -- quests "back to" goes through
local REDRAW_DELAY = 0.3
local REDRAW_FIGHT = 1   -- s: in a fight (the quest log changes with every kill and loot)
local MOVE_EVERY, MOVE_FAR = 2, 0.02 -- s between looks whether I moved; how far (of the map) is a move
local COLLAPSED_H = 54   -- the window as one line: its title bar and the line
local CLOSES_MAX = 2     -- quests named in "closes ..."
local C = Q.COLOR
local GOLD, GREY, LIGHT, GREEN, CLOSES = C.gold, C.grey, C.light, C.done, C.closes
local DOT = "|TInterface\\CharacterFrame\\TempPortraitAlphaMask:8:8:0:0:64:64:0:64:0:64:%d:%d:%d|t"
local EVENTS = { "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED",
	"SUPER_TRACKING_CHANGED", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }
-- Hidden by itself (nothing to show): what may bring something (rare events, listened to only then).
local WAKE_EVENTS = { "QUEST_ACCEPTED", "SUPER_TRACKING_CHANGED", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA" }
local WHY = { accepted = L["just accepted"], track = L["tracked"], log = L["opened in your quest log"],
	watch = L["on your tracker"], zone = L["in this zone"], first = L["in your quest log"] }

local win, content, scroll, map
local mode = "now"       -- "now": the companion; "quest": a quest looked at
local shown              -- the quest looked at
local history = {}       -- the quests looked at before it, the last one last
local mapSide            -- "start" | "end" | "drop": whose map the small map shows (nil: by my status)
local focus, focusWhy    -- the quest I did something with last, and what
local superSeen = false  -- the super-tracked quest when I last looked (false: never looked)
local justDone           -- the last quest turned in while it was shown
local nowId              -- the quest "Now" shows
local drawnAt            -- { zone, x, y }: where I was when it was drawn
local mapUsed = false
local rows, rowsUsed = {}, 0
local texts, textsUsed = {}, 0
local rules, rulesUsed = {}, 0
local soon = false
local width = WIDTH - SCROLL_SIDE
local picked = 0         -- rows of Pick up next drawn (the first is full size)
local collapsedNow       -- whether the window is laid out as one line (nil: not laid out yet)
local asleep = false     -- hidden by itself: comes back when there's something to show
local selfHiding = false

-- A verb icon and a space (Lodestar.lua's Q.Icon: the game's quest icons).
local function I(kind, size)
	return Q.Icon(kind, size) .. " "
end

-- Difficulty for me (the engine's tiers, Q.Tier: the quest's level, its mobs', a group quest one
-- harder): a quest's colour code (Q.TierCode; without it, or for a quest the data doesn't know, its
-- level's), "[12] Title" in it, and whether it's hard (Q.IsHard: I can take it, orange).
local HARD = "|cffff8040"
local function TierCode(id, quest)
	local code = Q.TierCode and quest and Q.TierCode(id)
	return type(code) == "string" and code ~= "" and code or Q.LevelCode(id, quest)
end

local function TierTitle(id, quest)
	quest = quest or Q.Quest(id)
	if not quest then
		return Q.LevelTitle(id)
	end
	local level = tonumber(quest.level)
	return TierCode(id, quest) .. ((level and level > 0) and ("[" .. level .. "] ") or "") .. Q.Title(id, quest) .. "|r"
end

local function IsHard(id)
	return Q.IsHard ~= nil and Q.IsHard(id) == true
end

-- Grey for me (the game's grey "!" of a low quest).
local function Trivial(id, quest)
	if Q.Tier and quest then
		return Q.Tier(id) == "trivial"
	end
	return Q.DifficultyKey(id, quest) == "trivial"
end

-- "Hard" (Lodestar.lua's Q.TIER_WORD), orange; with "mobs up to 26" when its mobs (Q.MobLevels) are
-- above its level.
local function HardWord(id, quest)
	local word = Q.TIER_WORD and Q.TIER_WORD.difficult
	local _, high = nil, nil
	if Q.MobLevels and quest then
		_, high = Q.MobLevels(id)
	end
	local mobs = tonumber(high) and tonumber(high) > (tonumber(quest.level) or 0) and (", " .. L["mobs up to %d"]:format(high)) or ""
	return HARD .. (type(word) == "string" and word or "Hard") .. mobs .. "|r"
end

-- The one order of quests (Engine.lua's Q.Compare: ready, in my log, for my level, hard, ..., then by
-- level and title); without it by ID.
local function Before(a, b)
	if a == b then
		return false
	end
	if Q.Compare then
		return Q.Compare(a, b) == true
	end
	return a < b
end

---------------------------------------------------------------------------
-- Where it is
---------------------------------------------------------------------------

local function DB()
	return Q.module.db
end

local function SavePlace()
	local left, top = win:GetLeft(), win:GetTop()
	local saved = DB().small
	if left and top then
		local ratio = win:GetEffectiveScale() / UIParent:GetEffectiveScale()
		saved.left, saved.top = left * ratio, top * ratio
	end
	saved.width = math.floor(win:GetWidth() + 0.5)
	if not collapsedNow then
		saved.height = math.floor(win:GetHeight() + 0.5)
	end
end

local function Clamp(v, low, high, default)
	v = tonumber(v)
	return v and math.max(low, math.min(high, v)) or default
end

-- Where it was left (setting keepPlace), else right of the middle at its usual size.
local function Place()
	local saved = DB().small
	win:ClearAllPoints()
	if DB().keepPlace and tonumber(saved.left) and tonumber(saved.top) then
		win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.left, saved.top)
		win:SetSize(Clamp(saved.width, MIN_W, MAX_W, WIDTH), collapsedNow and COLLAPSED_H or Clamp(saved.height, MIN_H, MAX_H, HEIGHT))
	else
		win:SetPoint("CENTER", UIParent, "CENTER", 280, 40)
		win:SetSize(WIDTH, collapsedNow and COLLAPSED_H or HEIGHT)
	end
end

---------------------------------------------------------------------------
-- Lines: font strings, clickable rows, header rules and the chain's bar, pooled
---------------------------------------------------------------------------

local function Text(y, text, font, indent)
	textsUsed = textsUsed + 1
	local fs = texts[textsUsed]
	if not fs then
		fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetJustifyH("LEFT")
		texts[textsUsed] = fs
	end
	indent = indent or 0
	fs:SetFontObject(font or "GameFontHighlightSmall")
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", content, "TOPLEFT", indent, -y)
	fs:SetWidth(width - indent)
	fs:SetText(text)
	fs:Show()
	return y + math.ceil(fs:GetStringHeight()) + GAP
end

local function RowEnter(self)
	if self.onEnter then
		self.onEnter()
	end
	local tip = self.tooltip
	if not tip then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(tip[1], 1, 1, 1)
	for i = 2, #tip do
		GameTooltip:AddLine(tip[i], 0.8, 0.8, 0.8, true)
	end
	GameTooltip:Show()
end

local function RowLeave(self)
	if self.onLeave then
		self.onLeave()
	end
	if GameTooltip:IsOwned(self) then
		GameTooltip:Hide()
	end
end

local function RowClick(self, button)
	RowLeave(self)
	if self.onClick then
		self.onClick(button)
	end
end

-- A line that does something when clicked: o = { text, right (grey, at the right), font, onClick,
-- tooltip = { title, line, ... }, indent, x, w (a part of the line's width), onEnter, onLeave (also
-- run on hover: an objective lights its areas on the map) }.
local function Row(y, o)
	rowsUsed = rowsUsed + 1
	local row = rows[rowsUsed]
	if not row then
		row = CreateFrame("Button", nil, content)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.Text:SetPoint("TOPLEFT", 3, -2)
		row.Text:SetJustifyH("LEFT")
		row.Right = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		row.Right:SetPoint("TOPRIGHT", -3, -2)
		row.Right:SetJustifyH("RIGHT")
		row:RegisterForClicks("LeftButtonUp")
		row:SetScript("OnClick", RowClick)
		row:SetScript("OnEnter", RowEnter)
		row:SetScript("OnLeave", RowLeave)
		rows[rowsUsed] = row
	end
	local indent = o.indent or 0
	local w = (o.w or width) - indent
	row.onClick, row.tooltip, row.onEnter, row.onLeave = o.onClick, o.tooltip, o.onEnter, o.onLeave
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", content, "TOPLEFT", (o.x or 0) + indent, -y)
	row.Right:SetText(o.right or "")
	local rightWidth = o.right and math.ceil(row.Right:GetStringWidth()) + 8 or 0
	row.Text:SetFontObject(o.font or "GameFontHighlightSmall")
	row.Text:SetWidth(math.max(40, w - 6 - rightWidth))
	row.Text:SetText(o.text)
	local height = math.ceil(row.Text:GetStringHeight()) + 4
	row:SetSize(w, height)
	row:Show()
	return y + height + 1
end

-- A section's heading: gold, a grey note after it, a thin gold rule under it.
local function Header(y, text, note)
	y = Text(y + GAP, GOLD .. text .. "|r" .. (note and ("  " .. GREY .. note .. "|r") or ""), "GameFontNormal")
	rulesUsed = rulesUsed + 1
	local rule = rules[rulesUsed]
	if not rule then
		rule = content:CreateTexture(nil, "ARTWORK")
		rule:SetHeight(1)
		rules[rulesUsed] = rule
	end
	if C_Texture and C_Texture.GetAtlasInfo and LT.Value(C_Texture.GetAtlasInfo, "Options_HorizontalDivider") then
		rule:SetAtlas("Options_HorizontalDivider")
		rule:SetVertexColor(1, 0.82, 0, 0.6)
	else
		rule:SetColorTexture(1, 0.82, 0, 0.25)
	end
	rule:ClearAllPoints()
	rule:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(y - 2))
	rule:SetWidth(width)
	rule:Show()
	return y + 2
end

-- A group's heading inside a section (smaller, gold).
local function SubHeader(y, text)
	return Text(y + 2, GOLD .. text .. "|r", "GameFontNormalSmall")
end

-- The chain's bar: how far along it you are.
local function Bar(y, step, total)
	local bar = win.Bar
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
	bar:SetSize(width, 8)
	local done = math.max(0, math.min(1, (step - 1) / math.max(1, total)))
	bar.Fill:SetWidth(math.max(1, (width - 2) * done))
	bar.Fill:SetShown(done > 0)
	bar:Show()
	return y + 8 + GAP
end

---------------------------------------------------------------------------
-- What's drawn: the pieces
---------------------------------------------------------------------------

local Look, Draw -- (below: shows a quest looked at; draws it all)
local ObjectiveRow -- (Now's objective lines)

local function Shows(id)
	return function() Look(id) end
end

local function InLog(id)
	return type(id) == "number" and id > 0 and C_QuestLog and LT.Value(C_QuestLog.GetLogIndexForQuestID, id) ~= nil
end

local function IsComplete(id)
	return C_QuestLog and LT.Value(C_QuestLog.IsComplete, id) == true
end

-- The quests in my log, in its order.
local function LogQuests()
	local list = {}
	for i = 1, (C_QuestLog and tonumber(LT.Value(C_QuestLog.GetNumQuestLogEntries)) or 0) do
		local info = LT.Value(C_QuestLog.GetInfo, i)
		local id = type(info) == "table" and not info.isHeader and not info.isHidden and info.questID
		if type(id) == "number" and id > 0 then
			list[#list + 1] = id
		end
	end
	return list
end

local function SuperTracked()
	local id = C_SuperTrack and LT.Value(C_SuperTrack.GetSuperTrackedQuestID)
	return type(id) == "number" and id > 0 and id or nil
end

-- What I did something with last (accepted, tracked, opened in the log): "Now" from then on. A
-- quest super-tracked before this isn't news any more.
local function Focus(id, why)
	if type(id) == "number" and id > 0 then
		focus, focusWhy = id, why
		superSeen = SuperTracked()
	end
end

-- The quest I'm on and why that one.
local function NowQuest(zone)
	local super = SuperTracked()
	if super ~= superSeen then
		superSeen = super
		if super then
			focus, focusWhy = super, "track"
		end
	end
	if InLog(focus) then
		return focus, focusWhy
	end
	if InLog(super) then
		return super, "track"
	end
	for i = 1, (C_QuestLog and tonumber(LT.Value(C_QuestLog.GetNumQuestWatches)) or 0) do
		local id = LT.Value(C_QuestLog.GetQuestIDForQuestWatchIndex, i)
		if InLog(id) then
			return id, "watch"
		end
	end
	local first
	for _, id in ipairs(LogQuests()) do
		local quest = Q.Quest(id)
		if zone and quest and (quest.zone == zone or Q.NearestPoint(quest.ends, zone)) then
			return id, "zone"
		end
		first = first or id
	end
	return first, first and "first" or nil
end

-- Its chain as I can do it (quests not for me left out) and where it is in it; nil: no chain
-- (Lodestar.lua's Q.ChainFor, kept per data and progress change).
local function ChainOf(id)
	return Q.ChainFor(id)
end

local function Dot(r, g, b)
	return DOT:format(math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end

local function ClassRGB(classFile)
	local c = (C_ClassColor and C_ClassColor.GetClassColor and LT.Value(C_ClassColor.GetClassColor, classFile))
		or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile])
	if type(c) == "table" and c.r then
		return c.r, c.g, c.b
	end
	return 0.8, 0.8, 0.8
end

-- Why a quest has its status, in words (docs/lodestar.md, Small window): a status "other" closed by
-- another one "Skipped" (and a line saying by which), not for my race, class or faction, a
-- profession I don't have; "locked" by a reputation or a profession's rank, or by the quest to do
-- first. nil: the status's own words. The professions' and standings' names: the game's, else
-- these (as the big window's).
local SKILLS = { [129] = "First Aid", [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy", [182] = "Herbalism",
	[185] = "Cooking", [186] = "Mining", [197] = "Tailoring", [202] = "Engineering", [333] = "Enchanting", [356] = "Fishing", [393] = "Skinning" }
local STANDINGS = { { -42000, "Hated" }, { -6000, "Hostile" }, { -3000, "Unfriendly" }, { 0, "Neutral" }, { 3000, "Friendly" },
	{ 9000, "Honored" }, { 21000, "Revered" }, { 42000, "Exalted" } }

local function Named(kind, id)
	if kind == "skill" then
		local name = C_TradeSkillUI and LT.Value(C_TradeSkillUI.GetTradeSkillDisplayName, id)
		return type(name) == "string" and name ~= "" and name or SKILLS[id] or ("#" .. tostring(id))
	elseif kind == "standing" then
		local n = 1
		for i, s in ipairs(STANDINGS) do
			if (id or 0) >= s[1] then
				n = i
			end
		end
		local label = _G["FACTION_STANDING_LABEL" .. n]
		return type(label) == "string" and label or STANDINGS[n][2]
	end
	local data = C_Reputation and LT.Value(C_Reputation.GetFactionDataByID, id)
	return type(data) == "table" and type(data.name) == "string" and data.name or ("#" .. tostring(id))
end

local function Why(id, status)
	if status == "other" and Q.WhyOther then
		local why, by = Q.WhyOther(id)
		local quest = Q.Quest(id)
		if why == "closed" then
			local tip = by and (quest and quest.breadcrumbFor == by and L["No longer needed: you have %s"] or L["You took %s instead"]):format(Q.Title(by))
			return L["Skipped"], tip
		elseif why == "race" or why == "class" or why == "faction" then
			return why == "race" and L["Not for your race"] or why == "class" and L["Not for your class"] or L["Not for your faction"]
		elseif why == "skill" and quest and quest.skill then
			return L["Needs %s"]:format(Named("skill", quest.skill.id))
		end
	elseif status == "locked" then
		local need = Q.Needs and Q.Needs(id)
		if need and need.kind == "rep" then
			return L["Needs %s with %s"]:format(Named("standing", need.min), Named("faction", need.faction))
		elseif need and need.kind == "skill" then
			return L["Needs %s %d"]:format(Named("skill", need.id), need.value or 0)
		end
		local missing = Q.Missing and Q.Missing(id) or {}
		if missing[1] then
			return L["Needs %s"]:format(Q.Title(missing[1].id))
		end
	end
end

-- A status as a line ("Needs Fine Wolf Pelts", "You can take it") and as a word after a quest's name
-- ("needs Fine Wolf Pelts", "ready to take"), coloured; the second return: the reason's own line.
local function StatusLine(id, status)
	local why, tip = Why(id, status)
	return why and (Q.StatusCode(status) .. why .. "|r") or Q.StatusText(status), tip
end

local function StatusWord(id, status)
	local why = Why(id, status)
	return why and (Q.StatusCode(status) .. why:gsub("^%u", string.lower) .. "|r") or Q.StatusText(status, "word")
end

-- A quest line's tooltip: its title, its status, why, what a click does.
local function QuestTip(id, title)
	local line, why = StatusLine(id, Q.StatusOf(id))
	local tip = { title or Q.Title(id), line }
	tip[#tip + 1] = why
	tip[#tip + 1] = L["Click: show this quest"]
	return tip
end

-- Friends' progress on a quest: dots in their class colour for those who did it, how many of how
-- many, and a tooltip with each. nil: none known (or the setting off).
local function FriendsOf(id)
	if not (DB().friends and Q.Friends) then
		return nil
	end
	local list = Q.Friends(id) or {}
	if #list == 0 then
		return nil
	end
	local dots, done, tip = {}, 0, {}
	for _, friend in ipairs(list) do
		if friend.status == "done" then
			done = done + 1
			dots[#dots + 1] = Dot(ClassRGB(friend.classFile))
		end
		tip[#tip + 1] = LT.Window.ClassColorCode(friend.classFile) .. (friend.name or "?") .. "|r  " .. Q.StatusText(friend.status, "friend")
	end
	return table.concat(dots), done, #list, tip
end

-- A giver or turn-in: "Name, Zone" (an item or an object says so), "(+2 more)" when there are more.
local function Who(people, here)
	local first = people and people[1]
	if not first then
		return nil
	end
	local name = first.name or L["unknown"]
	if first.kind == "item" then
		name = L["%s (an item)"]:format(name)
	elseif first.kind == "object" then
		name = L["%s (an object)"]:format(name)
	end
	local point = Q.NearestPoint({ first }, here) or (first.points and first.points[1])
	local zone = point and Q.MapName(point.map)
	local text = zone and (name .. ", " .. zone) or name
	if #people > 1 then
		text = text .. " " .. L["(+%d more)"]:format(#people - 1)
	end
	return text
end

-- How far and which way a spot of people is from me ("170 yd SW"), when it's on my map.
local function Far(people, ctx)
	if not (ctx.zone and ctx.x) then
		return nil
	end
	local point = Q.NearestPoint(people, ctx.zone, ctx.x, ctx.y)
	return point and Q.TowardText(ctx.zone, ctx.x, ctx.y, point.x, point.y)
end

-- A click on a giver's or turn-in's line: that side on the small map, the game's pin at its spot
-- nearest me (Shift: in chat too).
local function PinTo(people, side, ctx)
	return function(button)
		mapSide = side
		local point = Q.NearestPoint(people, ctx.zone, ctx.x, ctx.y)
		if not point then
			for _, who in ipairs(people or {}) do
				point = point or (who.points and who.points[1])
			end
		end
		if point then
			Q.Waypoint(point.map, point.x, point.y, IsShiftKeyDown and IsShiftKeyDown())
		end
		Q.RedrawSmall(true)
	end
end

local function PlaceTip(title, people)
	local tip = { title }
	for _, who in ipairs(people) do
		local point = who.points and who.points[1]
		local zone = point and Q.MapName(point.map)
		tip[#tip + 1] = (who.name or L["unknown"]) .. (zone and (", " .. zone) or "")
	end
	tip[#tip + 1] = L["Click: map pin and on the small map. Shift-click: the pin in chat too."]
	return tip
end

-- "Quest giver: Name, Zone" or "Turn-in: ..." with how far, a click pins it.
local function PlaceRow(y, label, people, side, ctx, icon)
	local who = Who(people, ctx.zone)
	if not who then
		return Text(y, GOLD .. label .. "|r " .. L["not known"], "GameFontHighlightSmall", 3)
	end
	return Row(y, { text = (icon or "") .. GOLD .. label .. "|r " .. who, right = Far(people, ctx),
		onClick = PinTo(people, side, ctx), tooltip = PlaceTip(label, people) })
end

-- Where a quest's item drops: "Drops from: Defias Pillager (12%), ..." for each item that starts it.
local function DropLines(y, quest)
	for _, start in ipairs(quest.starts or {}) do
		if start.kind == "item" and type(start.drops) == "table" and start.drops[1] then
			local parts = {}
			for i = 1, math.min(3, #start.drops) do
				local drop = start.drops[i]
				parts[i] = (drop.name or L["unknown"]) .. (drop.chance and (" (" .. Q.Percent(drop.chance) .. ")") or "")
			end
			if #start.drops > 3 then
				parts[#parts + 1] = L["(+%d more)"]:format(#start.drops - 3)
			end
			y = Text(y, GREY .. L["Drops from: %s"]:format(table.concat(parts, ", ")) .. "|r", "GameFontHighlightSmall", INDENT)
		end
	end
	return y
end

-- A quest in a list: "[12] Title" and my status; its tooltip says why (reason) and what a click does.
local function QuestRow(y, id, prefix, reason)
	local quest = Q.Quest(id)
	local status = Q.StatusOf(id)
	local text = prefix .. TierTitle(id, quest) .. "  " .. StatusWord(id, status)
	local tooltip = QuestTip(id, Q.Title(id, quest))
	if type(reason) == "string" and reason ~= "" then
		table.insert(tooltip, #tooltip, reason)
	end
	return Row(y, { text = text, onClick = Shows(id), tooltip = tooltip, indent = INDENT })
end

local function List(y, heading, list, numbered)
	if #list == 0 then
		return y
	end
	y = SubHeader(y + 2, heading)
	for i = 1, math.min(#list, LIST_MAX) do
		local entry = list[i]
		local id = type(entry) == "table" and entry.id or entry
		y = QuestRow(y, id, numbered and (i .. ". ") or "", type(entry) == "table" and entry.reason)
	end
	if #list > LIST_MAX then
		y = Text(y, L["and %d more"]:format(#list - LIST_MAX), "GameFontDisableSmall", INDENT + 4)
	end
	return y
end

-- The small map at y with these points (nil map: none).
local function PutMap(y, mapID, points)
	if not mapID then
		return y
	end
	mapUsed = true
	local height = math.floor(width * 2 / 3 + 0.5)
	map:SetSize(width, height)
	map.frame:ClearAllPoints()
	map.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(y + GAP))
	map:Show(mapID, points)
	return y + GAP + height + GAP
end

-- "Steps (7)": a line that folds and unfolds the chain's steps (setting stepsOpen, folded at first);
-- unfolded, the steps around this one: done ticked green, this one bold, the rest grey.
local function Steps(y, chain, at)
	local open = DB().stepsOpen == true
	y = Row(y + 2, { text = "|TInterface\\Buttons\\UI-" .. (open and "Minus" or "Plus") .. "Button-Up:12:12|t " .. GOLD
		.. L["Steps (%d)"]:format(#chain) .. "|r", font = "GameFontNormalSmall",
		onClick = function()
			DB().stepsOpen = not open
			Draw()
		end, tooltip = { L["Steps (%d)"]:format(#chain), open and L["Click: hide the chain's steps"] or L["Click: show the chain's steps"] } })
	if not open then
		return y
	end
	local first = math.max(1, math.min(at - 2, #chain - STEPS_MAX + 1))
	local last = math.min(#chain, first + STEPS_MAX - 1)
	if first > 1 then
		y = Text(y, GREY .. L["... %d before"]:format(first - 1) .. "|r", "GameFontHighlightSmall", INDENT)
	end
	for i = first, last do
		local id = chain[i]
		local status = Q.StatusOf(id)
		local text, font
		if i == at then
			text, font = I("here") .. i .. ". " .. Q.Title(id), "GameFontNormal"
		elseif status == "done" then
			text = I("done") .. GREEN .. Q.Title(id) .. "|r"
		else
			text = LIGHT .. i .. ". " .. Q.Title(id) .. "|r"
		end
		y = Row(y, { text = text, font = font, indent = INDENT, onClick = Shows(id), tooltip = QuestTip(id, TierTitle(id)) })
	end
	if last < #chain then
		y = Text(y, GREY .. L["... %d more"]:format(#chain - last) .. "|r", "GameFontHighlightSmall", INDENT)
	end
	return y
end

-- "Step 3 of 7 · <chain>" and the bar.
local function ChainLine(y, chain, at)
	y = Text(y, GREY .. L["Step %d of %d · %s"]:format(at, #chain, Q.Title(chain[1])) .. "|r", "GameFontHighlightSmall")
	return Bar(y - 2, at, #chain)
end

local function FriendsRow(y, id)
	local dots, done, total, tip = FriendsOf(id)
	if not dots then
		return y
	end
	table.insert(tip, 1, L["Friends"])
	return Row(y, { text = GOLD .. L["Friends:"] .. "|r " .. L["%d of %d done"]:format(done, total) .. (dots ~= "" and ("  " .. dots) or ""),
		tooltip = tip })
end

---------------------------------------------------------------------------
-- The companion: Now, the map, Pick up next
---------------------------------------------------------------------------

-- Who gives a quest, how far, and what it follows or which step it is: its second line.
local function GiverNote(quest, id, ctx, follows)
	local parts = {}
	local giver = quest and quest.starts and quest.starts[1]
	if giver then
		local point = Q.NearestPoint(quest.starts, ctx.zone) or (giver.points and giver.points[1])
		local zone = point and point.map ~= ctx.zone and Q.MapName(point.map)
		parts[#parts + 1] = (giver.name or L["unknown"]) .. (zone and (", " .. zone) or "")
	end
	if follows then
		parts[#parts + 1] = L["after %s"]:format(Q.Title(follows))
	else
		local step, total = Q.StepOf(id)
		if step and step > 1 then
			parts[#parts + 1] = L["step %d of %d"]:format(step, total)
		end
	end
	return table.concat(parts, " · ")
end

-- What a follow-up follows: the first quest it needs that I've done.
local function Follows(quest)
	for _, key in ipairs({ "pre", "preAny" }) do
		for _, other in ipairs(quest and quest[key] or {}) do
			if Q.StatusOf(other) == "done" then
				return other
			end
		end
	end
end

-- The groups of "Pick up next": { log, now, more } of { id, follows } (more: what Available now
-- left out), each in the one order of quests (Q.Compare: ready first, then by level; for my level
-- before hard ones). In progress: my other quests. Available now only for my levels (Q.InRange):
-- follow-ups of what I just turned in and of everything done or in my log (Q.Next), and this zone's
-- (its givers' distance stays on each line). What's coming up later or blocked is the big window's.
local function PickLists(ctx)
	local seen = { [ctx.now or 0] = true }
	for _, id in ipairs(ctx.now and Q.Opens and Q.Opens(ctx.now) or {}) do
		seen[id] = true -- (what Now leads to: its tooltip says)
	end
	local lists = { log = {}, now = {}, more = 0 }
	local log = LogQuests()
	table.sort(log, Before)
	for _, id in ipairs(log) do
		if not seen[id] then
			seen[id] = true
			if #lists.log < LOG_MAX then
				lists.log[#lists.log + 1] = { id = id }
			end
		end
	end
	local takes, follows = {}, {}
	local function Take(id, after)
		if seen[id] or Q.StatusOf(id) ~= "available" or (Q.InRange and not Q.InRange(id)) then
			return
		end
		seen[id] = true
		takes[#takes + 1] = id
		follows[id] = after
	end
	for _, id in ipairs(justDone and Q.Opens and Q.Opens(justDone) or {}) do
		Take(id, justDone)
	end
	for _, id in ipairs(Q.Next and Q.Next() or {}) do
		Take(id, Follows(Q.Quest(id)))
	end
	for _, id in ipairs(Q.AvailableIn(ctx.zone, ctx.x, ctx.y)) do
		Take(id)
	end
	table.sort(takes, Before)
	for i, id in ipairs(takes) do
		if i <= PICK_MAX then
			lists.now[i] = { id = id, follows = follows[id] }
		else
			lists.more = lists.more + 1
		end
	end
	return lists
end

-- What taking a quest closes, for its second line: "closes X" (its exclusive ones, at most two named).
local function Closing(id)
	local closes = Q.Closes and Q.Closes(id) or {}
	if not closes[1] then
		return ""
	end
	local names = {}
	for i = 1, math.min(#closes, CLOSES_MAX) do
		names[i] = Q.Title(closes[i])
	end
	return CLOSES .. L["closes %s"]:format(table.concat(names, ", ")) .. "|r"
end

-- "[12] Title" with only the level in its difficulty colour, the title grey (the lines after the first).
local function GreyTitle(id, quest)
	local level = quest and tonumber(quest.level)
	return (level and level > 0 and (TierCode(id, quest) .. "[" .. level .. "]|r ") or "") .. LIGHT .. Q.Title(id, quest) .. "|r"
end

-- A quest of "Pick up next": its verb icon, "[12] Title", how far; its giver, what it follows and
-- what taking it closes under it. The first one drawn is full size, the rest smaller and grey.
local function PickRow(y, entry, ctx, group)
	local id = entry.id
	local quest = Q.Quest(id)
	local status = Q.StatusOf(id)
	picked = picked + 1
	local top = picked == 1
	local size = top and 16 or 13
	local icon, right, note
	if group == "log" then
		local ready = IsComplete(id)
		icon = I(ready and "turnin" or "progress", size)
		right = quest and Far(quest.ends, ctx)
		local ender = quest and quest.ends and quest.ends[1]
		note = (ready and (GREEN .. L["ready to turn in"] .. "|r") or L["in your log"])
			.. (ender and (" · " .. (ender.name or L["unknown"])) or "")
	else
		icon = Q.QuestIcon(id, status, size) .. " "
		right = quest and Far(quest.starts, ctx)
		note = GiverNote(quest, id, ctx, entry.follows)
		local closes = Closing(id)
		if closes ~= "" then
			note = (note ~= "" and (note .. " · ") or "") .. closes
		end
		if quest and IsHard(id) then -- (orange: after the ones for my level, marked)
			note = HardWord(id, quest) .. (note ~= "" and (GREY .. " · " .. note) or "")
		end
	end
	local text = icon .. (top and TierTitle(id, quest) or GreyTitle(id, quest))
	if note and note ~= "" then
		text = text .. "\n" .. GREY .. note .. "|r"
	end
	local tooltip = { Q.Title(id, quest), (StatusLine(id, status)) }
	local step, total, chain = Q.StepOf(id)
	if step then
		tooltip[#tooltip + 1] = L["Step %d of %d · %s"]:format(step, total, chain or "")
	end
	if group == "now" and quest and IsHard(id) then
		tooltip[#tooltip + 1] = HardWord(id, quest)
	end
	local closes = group == "now" and Q.Closes and Q.Closes(id) or {}
	if closes[1] then
		tooltip[#tooltip + 1] = CLOSES .. L["Taking it closes: %s"]:format(Q.Title(closes[1])) .. "|r " .. L["Only one of them can be done."]
	end
	tooltip[#tooltip + 1] = L["Click: show this quest"]
	return Row(y, { text = text, right = right, onClick = Shows(id), tooltip = tooltip, indent = 2,
		font = top and "GameFontHighlight" or "GameFontHighlightSmall" })
end

-- Where an objective is done, in words: "Defias Bandit", "Defias Pillager (32%), ..." (an item's
-- likeliest sources first).
local function Sources(data)
	local parts = {}
	for i, source in ipairs(data and data.sources or {}) do
		if i > 3 then
			break
		end
		local chance = tonumber(source.chance)
		parts[#parts + 1] = (source.name or L["unknown"]) .. (data.kind == "item" and chance and chance > 0 and (" (" .. Q.Percent(chance) .. ")") or "")
	end
	return table.concat(parts, ", ")
end

-- An objective of Now ("- Wolf Pelts: 2/5", a done one ticked). One not done whose areas the data
-- knows: its areas on the map (group i; hovering the line lights them), a click sets the map pin at
-- the nearest. Returns y and the map of its area nearest me (nil: none).
function ObjectiveRow(y, i, o, ctx)
	local text = o.done and (I("done", 12) .. GREY .. o.text .. "|r") or ("- " .. o.text)
	local sources = not o.done and o.data and o.data.sources or {}
	local nearest = Q.NearestPoint(sources, ctx.zone, ctx.x, ctx.y)
	local first
	for _, source in ipairs(sources) do
		for _, p in ipairs(source.points or {}) do
			first = first or p
			ctx.points[#ctx.points + 1] = { x = p.x, y = p.y, kind = "area", group = i, radius = tonumber(p.r), label = source.name or L["unknown"],
				note = o.name or o.text, map = p.map }
		end
	end
	local spot = nearest or first
	if not spot then
		return Text(y, text, "GameFontHighlightSmall", INDENT), nil
	end
	local where = Sources(o.data)
	local tip = { o.text }
	if where ~= "" then
		tip[#tip + 1] = L["Where: %s"]:format(where)
	end
	tip[#tip + 1] = L["Click: map pin at the nearest spot. Shift-click: in chat too."]
	y = Row(y, { text = text, indent = INDENT - 3, right = Far(sources, ctx), tooltip = tip,
		onClick = function() Q.Waypoint(spot.map, spot.x, spot.y, IsShiftKeyDown and IsShiftKeyDown()) end,
		onEnter = function() map:Light(i) end, onLeave = function() map:Light(nil) end })
	return y, spot.map
end

-- Now: the quest I'm on (none: says so): its title (the tooltip: what it leads to), its step and
-- bar, friends, its objectives or "Ready to turn in", the turn-in, the steps folded. Notes the map
-- it wants and its markers in ctx.
local function DrawNow(y, ctx)
	local id = ctx.now
	y = Header(y, L["Now"], id and WHY[ctx.why])
	if not id then
		return Text(y, L["No quest in your log. Pick one up below."], "GameFontDisableSmall", INDENT)
	end
	local quest = Q.Quest(id)
	local tip = { Q.Title(id, quest) }
	local opens = Q.Opens and Q.Opens(id) or {}
	if opens[1] then
		local nextQuest = Q.Quest(opens[1])
		local giver = nextQuest and Who(nextQuest.starts, ctx.zone)
		tip[2] = L["Leads to: %s"]:format(TierTitle(opens[1], nextQuest) .. (giver and (" - " .. giver) or "")
			.. (#opens > 1 and (" " .. L["(+%d more)"]:format(#opens - 1)) or ""))
	end
	tip[#tip + 1] = L["Click: everything about it"]
	y = Row(y, { text = TierTitle(id, quest), font = "GameFontNormalLarge", onClick = Shows(id), tooltip = tip })
	local chain, at = ChainOf(id)
	if chain then
		y = ChainLine(y, chain, at)
	end
	y = FriendsRow(y, id)
	local ready = IsComplete(id)
	local areaMap
	if ready then
		y = Text(y + 2, GREEN .. L["Ready to turn in"] .. "|r", "GameFontHighlight")
	else
		for i, o in ipairs(Q.LogObjectives(id)) do
			if i > OBJECTIVES_MAX then
				break
			end
			local map
			y, map = ObjectiveRow(y, i, o, ctx)
			areaMap = (map == ctx.zone and map) or areaMap or map
		end
	end
	if not quest then
		ctx.map = areaMap
		return y
	end
	-- Where to turn it in (on the map with it when it's ready, or no objective's area is known).
	y = PlaceRow(y + 2, L["Turn-in:"], quest.ends, "end", ctx, I(ready and "turnin" or "progress"))
	if areaMap then
		ctx.map = areaMap
	else
		local point = Q.NearestPoint(quest.ends, ctx.zone)
		local first = quest.ends and quest.ends[1]
		ctx.map = point and ctx.zone or (first and first.points and first.points[1] and first.points[1].map) or nil
		for _, who in ipairs(quest.ends or {}) do
			for _, p in ipairs(who.points or {}) do
				ctx.points[#ctx.points + 1] = { x = p.x, y = p.y, kind = "end", look = ready and "turnin" or "progress",
					label = who.name or L["unknown"], note = Q.Title(id, quest), map = p.map }
			end
		end
	end
	if chain then
		y = Steps(y, chain, at)
	end
	return y
end

-- The markers of "Pick up next" on the map shown: givers to pick up, my quests' turn-ins.
local function PickPoints(ctx, lists)
	local function Add(people, kind, look, note, hard)
		for _, who in ipairs(people or {}) do
			for _, p in ipairs(who.points or {}) do
				if p.map == ctx.map then
					ctx.points[#ctx.points + 1] = { x = p.x, y = p.y, kind = kind, look = look, label = who.name or L["unknown"],
						note = note, map = p.map, hard = hard }
				end
			end
		end
	end
	for _, entry in ipairs(lists.now) do
		local quest = Q.Quest(entry.id)
		local look = quest and quest.repeatable and "repeatable" or (Trivial(entry.id, quest) and "trivial" or "available")
		local hard = quest ~= nil and IsHard(entry.id)
		Add(quest and quest.starts, "start", look, Q.Title(entry.id, quest) .. (hard and ("  " .. HardWord(entry.id, quest)) or ""), hard)
	end
	for _, entry in ipairs(lists.log) do
		local quest = Q.Quest(entry.id)
		Add(quest and quest.ends, "end", IsComplete(entry.id) and "turnin" or "progress", Q.Title(entry.id, quest))
	end
end

local function DrawPick(y, ctx, lists)
	local count = ctx.zone and Q.ZoneCount and { pcall(Q.ZoneCount, ctx.zone) }
	local note = ctx.zone and Q.MapName(ctx.zone)
	if count and count[1] and tonumber(count[2]) and tonumber(count[3]) and count[3] > 0 then
		note = (note and (note .. " · ") or "") .. L["%d of %d done"]:format(count[2], count[3])
	end
	y = Header(y, L["Pick up next"], note)
	local groups = { { "log", L["In progress"] }, { "now", L["Available now"] } }
	local any = false
	picked = 0
	for _, group in ipairs(groups) do
		local list = lists[group[1]]
		if #list > 0 then
			any = true
			y = SubHeader(y, group[2])
			for _, entry in ipairs(list) do
				y = PickRow(y, entry, ctx, group[1])
			end
			if group[1] == "now" and lists.more > 0 and (Q.OpenBrowser or Q.ToggleBrowser) then
				local nextId = list[1].id
				y = Row(y, { text = GREY .. L["%d more here: the quest browser"]:format(lists.more) .. "|r", indent = INDENT,
					onClick = function()
						if Q.OpenBrowser then Q.OpenBrowser(nextId) else Q.ToggleBrowser() end
					end, tooltip = { L["Quest browser"], L["Every zone's quest chains, with a search over all of them. Also /lodestar browse."] } })
			end
		end
	end
	if not any then
		y = Text(y, L["Nothing to pick up nearby. The quest browser has every zone."], "GameFontDisableSmall", INDENT)
	end
	return y, any
end

---------------------------------------------------------------------------
-- The plan (Plan.lua): on top while it has a stop not done, where to go next and its own small map
---------------------------------------------------------------------------

-- The plan's map (a second small map, made the first time it's needed) and its stops numbered on a
-- layer of ours over the art, joined by a line; laid again when the art is (its size changes with
-- the zoom). Nothing runs for it but what MiniMap.lua runs for its own.
local PL = { marks = {}, lines = {}, MAX = 5 }

-- The quest's stop on the big window's map (Q.ShowOnMap; without it the quest, Q.OpenBrowser).
function PL.ShowOnMap(stop)
	if Q.ShowOnMap then
		Q.ShowOnMap(stop.quest, stop.spot)
	elseif Q.OpenBrowser then
		Q.OpenBrowser(stop.quest)
	end
end

function PL.MarkEnter(self)
	local e = self.entry
	if not e then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(e.n .. ". " .. Q.PlanStopText(e.stop, true), 1, 1, 1, true)
	if e.next then
		GameTooltip:AddLine(L["Next"], 1, 0.82, 0)
	end
	GameTooltip:AddLine(L["Click: show it on the map"], 0.5, 0.75, 1)
	GameTooltip:Show()
end

function PL.Mark(i)
	local mark = PL.marks[i]
	if not mark then
		mark = CreateFrame("Button", nil, PL.layer)
		mark:SetSize(18, 18)
		mark.Disc = mark:CreateTexture(nil, "ARTWORK")
		mark.Disc:SetAllPoints()
		mark.Disc:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
		mark.Num = mark:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		mark.Num:SetPoint("CENTER", 0, 0)
		mark:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
		mark:SetScript("OnEnter", PL.MarkEnter)
		mark:SetScript("OnLeave", RowLeave)
		mark:SetScript("OnClick", function(self)
			RowLeave(self)
			if self.entry then
				PL.ShowOnMap(self.entry.stop)
			end
		end)
		PL.marks[i] = mark
	end
	return mark
end

-- The numbers and the line where the stops are on the art laid now.
function PL.Lay()
	local m = PL.map
	if not (m and PL.layer) then
		return
	end
	local w, h = m.artW, m.artH
	local shown = PL.shown or {}
	local px, py
	for i, e in ipairs(shown) do
		local mark = PL.Mark(i)
		mark.entry = e
		local x, y = e.stop.spot.x * w, e.stop.spot.y * h
		mark:ClearAllPoints()
		mark:SetPoint("CENTER", m.Map, "TOPLEFT", x, -y)
		mark.Num:SetText(tostring(e.n))
		if e.next then
			mark.Disc:SetVertexColor(1, 0.82, 0, 1)
			mark.Num:SetTextColor(0, 0, 0)
		else
			mark.Disc:SetVertexColor(0.1, 0.1, 0.1, 0.9)
			mark.Num:SetTextColor(1, 0.82, 0)
		end
		mark:Show()
		if px then
			local line = PL.lines[i - 1]
			if not line then
				line = PL.layer:CreateLine(nil, "ARTWORK")
				line:SetThickness(2)
				line:SetColorTexture(1, 0.82, 0, 0.75)
				PL.lines[i - 1] = line
			end
			line:SetStartPoint("TOPLEFT", m.Map, px, -py)
			line:SetEndPoint("TOPLEFT", m.Map, x, -y)
			line:Show()
		end
		px, py = x, y
	end
	for i = #shown + 1, #PL.marks do
		RowLeave(PL.marks[i])
		PL.marks[i]:Hide()
	end
	for i = math.max(1, #shown), #PL.lines do
		PL.lines[i]:Hide()
	end
end

function PL.Map()
	if not PL.map then
		local m = Q.NewMiniMap(content)
		PL.map = m
		PL.layer = CreateFrame("Frame", nil, m.Map)
		PL.layer:SetAllPoints()
		PL.layer:SetFrameLevel(m.Map:GetFrameLevel() + 5)
		m.Map:HookScript("OnSizeChanged", PL.Lay)
	end
	return PL.map
end

function PL.Hide()
	if PL.map then
		for _, mark in ipairs(PL.marks) do
			RowLeave(mark)
		end
		PL.map:Hide()
	end
end

-- "Next (2/14): Pick up Wanted: Hogger at Marshal Dughan" with how far and which way (another zone:
-- its name), "Skip" beside it, and the plan's map: the next few stops on the next one's map,
-- numbered, joined by a line. Nothing without a plan (or with every stop done).
local function DrawPlan(y, ctx)
	local stop, at = nil, nil
	if Q.PlanNext then
		stop, at = Q.PlanNext()
	end
	if not stop then
		return y
	end
	local stops = Q.PlanStops()
	local spot = stop.spot
	local zone = Q.MapName(spot.map)
	y = Header(y, L["Plan"], spot.map ~= ctx.zone and zone or nil)
	local right = zone
	if ctx.zone and ctx.x and spot.map == ctx.zone then
		right = Q.TowardText(ctx.zone, ctx.x, ctx.y, spot.x, spot.y)
	end
	local skipW = 44
	local tip = { Q.PlanStopText(stop, true) }
	tip[#tip + 1] = zone
	tip[#tip + 1] = L["Click: show it on the map"]
	tip[#tip + 1] = L["Shift-click: map pin there, in chat too"]
	local y1 = Row(y, { text = GOLD .. L["Next (%d/%d):"]:format(at, #stops) .. "|r " .. Q.PlanStopText(stop, true), right = right,
		w = width - skipW - 4, onClick = function()
			if IsShiftKeyDown and IsShiftKeyDown() then
				Q.Waypoint(spot.map, spot.x, spot.y, true)
			else
				PL.ShowOnMap(stop)
			end
		end, tooltip = tip })
	local y2 = Row(y, { text = GREY .. L["Skip"] .. "|r", x = width - skipW, w = skipW, onClick = function()
			Q.PlanSkip(stop)
			Draw()
		end, tooltip = { L["Skip"], L["Marks this stop done for now: the next one comes up (until you log out or reload)."] } })
	y = math.max(y1, y2)
	local m = PL.Map()
	PL.used = true
	local shown = {}
	for i = at, #stops do
		local s = stops[i]
		if not s.done and s.spot.map == spot.map then
			shown[#shown + 1] = { stop = s, n = i, next = i == at }
			if #shown >= PL.MAX then
				break
			end
		end
	end
	PL.shown = shown
	local height = math.floor(width * 2 / 3 + 0.5)
	m:SetSize(width, height)
	m.frame:ClearAllPoints()
	m.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(y + GAP))
	m:Show(spot.map, {})
	PL.Lay()
	return y + GAP + height + GAP
end

local function DrawCompanion(y)
	local zone, x, py = Q.HereZone()
	drawnAt = { zone, x, py }
	local ctx = { zone = zone, x = x, y = py, points = {} }
	ctx.now, ctx.why = NowQuest(zone)
	nowId = ctx.now
	local lists = PickLists(ctx)
	y = DrawPlan(y, ctx)
	y = DrawNow(y, ctx)
	ctx.map = ctx.map or zone
	local points = {}
	for _, p in ipairs(ctx.points) do
		if p.map == ctx.map then
			points[#points + 1] = p
		end
	end
	ctx.points = points
	PickPoints(ctx, lists)
	y = PutMap(y, ctx.map, ctx.points)
	local any
	y, any = DrawPick(y, ctx, lists)
	return y, ctx.now ~= nil or any
end

-- Whether the companion has anything to show: a quest I'm on, or something to pick up nearby.
local function Useful()
	if Q.PlanNext and Q.PlanNext() then
		return true
	end
	local zone, x, y = Q.HereZone()
	local ctx = { zone = zone, x = x, y = y, points = {} }
	ctx.now = NowQuest(zone)
	if ctx.now then
		return true
	end
	local lists = PickLists(ctx)
	return #lists.log + #lists.now > 0
end

-- The window as one line: the quest I'm on ("[18] Title · 3/7 · 170 yd SW", its verb icon), else
-- the first thing to pick up, else a word. A click shows the whole companion. true: something to show.
local function DrawLine()
	local zone, x, py = Q.HereZone()
	drawnAt = { zone, x, py }
	local ctx = { zone = zone, x = x, y = py, points = {} }
	local text, id, useful
	if mode == "quest" and shown then
		id, useful = shown, true
		text = Q.QuestIcon(id) .. " " .. TierTitle(id)
	else
		ctx.now, ctx.why = NowQuest(zone)
		nowId = ctx.now
		id = ctx.now
		if id then
			useful = true
			local quest = Q.Quest(id)
			local list, at = ChainOf(id)
			text = Q.QuestIcon(id, "active") .. " " .. TierTitle(id, quest) .. (list and (GREY .. " · " .. at .. "/" .. #list .. "|r") or "")
			local far = quest and Far(quest.ends, ctx)
			if far then
				text = text .. GREY .. " · " .. far .. "|r"
			end
		else
			local lists = PickLists(ctx)
			local entry = lists.now[1]
			useful = entry ~= nil
			if entry then
				local quest = Q.Quest(entry.id)
				text = Q.QuestIcon(entry.id) .. " " .. TierTitle(entry.id, quest)
				local far = quest and Far(quest.starts, ctx)
				if far then
					text = text .. GREY .. " · " .. far .. "|r"
				end
			else
				text = GREY .. L["Nothing to pick up nearby."] .. "|r"
			end
		end
	end
	local line = win.Line
	line.Text:SetText(text)
	line.tooltip = { id and Q.Title(id) or L["Pick up next"], L["Click: the whole companion"] }
	line:Show()
	return useful
end

---------------------------------------------------------------------------
-- A quest looked at
---------------------------------------------------------------------------

local function BackTo()
	local id = table.remove(history)
	if id then
		shown, mapSide = id, nil
		scroll:SetVerticalScroll(0)
		Draw()
	end
end

local function ToNow()
	mode, shown, mapSide = "now", nil, nil
	wipe(history)
	scroll:SetVerticalScroll(0)
	Draw()
end

-- "« Back to <the quest before>" and "Back to now" (only the latter when there's none before).
local function DrawNav(y)
	local before = history[#history]
	if before then
		local half = math.floor(width * 0.62)
		Row(y, { text = GOLD .. L["« Back to %s"]:format(Q.Title(before)) .. "|r", w = half, onClick = BackTo,
			tooltip = { L["« Back to %s"]:format(Q.Title(before)), L["The quest you looked at before this one."] } })
		return Row(y, { text = GOLD .. L["Back to now"] .. "|r", x = half, w = width - half, onClick = ToNow,
			tooltip = { L["Back to now"], L["The quest you're on and what to pick up next."] } })
	end
	return Row(y, { text = GOLD .. L["« Back to now"] .. "|r", onClick = ToNow,
		tooltip = { L["Back to now"], L["The quest you're on and what to pick up next."] } })
end

-- The map of a quest looked at: the giver's zone (in my log: the turn-in's; an item that drops:
-- where it drops) unless a line picked one, every giver, turn-in and drop spot on it.
local function QuestMap(y, id, quest, status, ctx)
	local drops = {}
	for _, start in ipairs(quest.starts or {}) do
		for _, drop in ipairs(start.kind == "item" and type(start.drops) == "table" and start.drops or {}) do
			drops[#drops + 1] = { name = drop.name, points = drop.points, chance = drop.chance, item = start.name }
		end
	end
	local npcStarts = {}
	for _, who in ipairs(quest.starts or {}) do
		if who.kind ~= "item" then
			npcStarts[#npcStarts + 1] = who
		end
	end
	local side = mapSide or (status == "active" and "end") or (#npcStarts == 0 and drops[1] and "drop") or "start"
	local order = side == "end" and { quest.ends, npcStarts, drops } or side == "drop" and { drops, npcStarts, quest.ends }
		or { npcStarts, quest.ends, drops }
	local mapID
	for _, people in ipairs(order) do
		local point = Q.NearestPoint(people, ctx.zone) or nil
		if point then
			mapID = point.map
			break
		end
		for _, who in ipairs(people) do
			mapID = mapID or (who.points and who.points[1] and who.points[1].map)
		end
		if mapID then
			break
		end
	end
	mapID = mapID or quest.zone
	local points = {}
	local startLook = status == "available" and (quest.repeatable and "repeatable" or (Trivial(id, quest) and "trivial" or "available"))
		or (status == "done" and "trivial") or "locked"
	local endLook = status == "active" and (IsComplete(id) and "turnin" or "progress") or "turnin"
	for _, set in ipairs({ { npcStarts, "start", startLook }, { quest.ends or {}, "end", endLook }, { drops, "drop" } }) do
		for _, who in ipairs(set[1]) do
			for _, p in ipairs(who.points or {}) do
				if p.map == mapID then
					points[#points + 1] = { x = p.x, y = p.y, kind = set[2], look = set[3], label = who.name or L["unknown"],
						chance = who.chance, radius = set[2] == "drop" and tonumber(p.r) or nil, note = set[2] == "drop" and L["Drops %s (%s)"]:format(who.item or "", Q.Percent(who.chance))
							or Q.Title(id, quest) }
				end
			end
		end
	end
	return PutMap(y, mapID, points)
end

-- "Requires: <chain>": what it needs first from other chains.
local function Requires(y, id, chain)
	local inChain = {}
	for _, other in ipairs(chain or {}) do
		inChain[other] = true
	end
	local names, seen = {}, {}
	for _, entry in ipairs(Q.Missing and Q.Missing(id) or {}) do
		if not inChain[entry.id] then
			local step, _, name = Q.StepOf(entry.id)
			name = step and name or Q.Title(entry.id)
			if not seen[name] then
				seen[name] = true
				names[#names + 1] = name
			end
		end
	end
	if #names == 0 then
		return y
	end
	return Text(y, Q.StatusCode("locked") .. L["Requires: %s"]:format(table.concat(names, ", ")) .. "|r", "GameFontHighlightSmall")
end

local function DrawQuest(y, id)
	local quest = Q.Quest(id)
	y = Text(y + 2, quest and TierTitle(id, quest) or Q.Title(id), "GameFontNormalLarge")
	if not quest then
		return Text(y, L["This quest isn't in the quest data."], "GameFontDisableSmall")
	end
	local zone, x, py = Q.HereZone()
	local ctx = { zone = zone, x = x, y = py }
	local chain, at = ChainOf(id)
	if chain then
		y = ChainLine(y, chain, at)
	end
	local about = {}
	about[#about + 1] = Q.LevelText(quest)
	about[#about + 1] = Q.MapName(quest.zone) or quest.zoneName
	about[#about + 1] = quest.dungeon and L["Dungeon: %s"]:format(quest.dungeon)
	about[#about + 1] = quest.repeatable and L["Repeatable"] or nil
	about[#about + 1] = quest.new and L["New in WoW: Forever"] or nil
	if #about > 0 then
		y = Text(y, GREY .. table.concat(about, ", ") .. "|r", "GameFontHighlightSmall")
	end
	local status = Q.StatusOf(id)
	local line, why = StatusLine(id, status)
	if status == "level" and tonumber(quest.minLevel) then
		line = Q.StatusCode(status) .. L["Your level is too low: from level %d"]:format(quest.minLevel) .. "|r"
	elseif status == "active" and IsComplete(id) then
		line = GREEN .. L["Ready to turn in"] .. "|r"
	end
	y = Text(y + 2, line, "GameFontHighlight")
	if why then
		y = Text(y, GREY .. why .. "|r", "GameFontHighlightSmall")
	end
	y = Requires(y, id, chain)
	y = List(y, L["Needs first:"], Q.Missing and Q.Missing(id) or {}, true)
	local starter = quest.starts and quest.starts[1]
	y = PlaceRow(y + GAP, L["Quest giver:"], quest.starts, "start", ctx, I("available"))
	if starter and starter.kind == "item" then
		y = DropLines(y, quest)
	end
	y = PlaceRow(y, L["Turn-in:"], quest.ends, "end", ctx, I("turnin"))
	y = QuestMap(y, id, quest, status, ctx)
	y = List(y, L["Leads to:"], Q.Opens and Q.Opens(id) or {}, false)
	if chain then
		y = Steps(y, chain, at)
	end
	return FriendsRow(y + GAP, id)
end

---------------------------------------------------------------------------
-- Drawing it all
---------------------------------------------------------------------------

-- One line or the whole window (setting collapsed): the scroll area, its inset, the grip and the
-- bottom button only in the whole one; one line can't be made taller.
local function Lay(collapsed)
	if collapsedNow == collapsed then
		return
	end
	collapsedNow = collapsed
	scroll:SetShown(not collapsed)
	if win.Inset then
		win.Inset:SetShown(not collapsed)
	end
	win.Grip:SetShown(not collapsed)
	win.Line:SetShown(collapsed)
	win.Collapse.Icon:SetAtlas(collapsed and "QuestLog-icon-Expand" or "QuestLog-icon-shrink")
	if collapsed then
		win:SetResizeBounds(MIN_W, COLLAPSED_H, MAX_W, COLLAPSED_H)
		win:SetHeight(COLLAPSED_H)
	else
		win:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
		local height = Clamp(DB().keepPlace and DB().small.height, MIN_H, MAX_H, HEIGHT)
		if math.abs(win:GetHeight() - height) > 0.5 then
			win:SetHeight(height)
		end
	end
end

-- Hidden by itself: nothing to show. It comes back (Wake) when a rare event brings something.
local function Sleep()
	asleep = true
	selfHiding = true
	win:Hide()
	selfHiding = false
	for _, event in ipairs(WAKE_EVENTS) do
		win.Sleeper:RegisterEvent(event)
	end
end

local function Awake()
	asleep = false
	win.Sleeper:UnregisterAllEvents()
end

-- opened: drawn as it opens (then it never hides itself: you asked for it).
Draw = function(opened)
	if not (win and win:IsShown()) then
		return
	end
	rowsUsed, textsUsed, rulesUsed, mapUsed = 0, 0, 0, false
	PL.used = false
	win.Bar:Hide()
	width = math.max(100, win:GetWidth() - SCROLL_SIDE)
	content:SetWidth(width)
	local collapsed = DB().collapsed == true
	Lay(collapsed)
	local y, useful = 2, true
	local ready = Q.Ready()
	if not ready then
		nowId = nil
		y = Text(y, L["The quest data isn't there. It's an add-on of its own, LefthyTools Quest Data, installed with LefthyTools: run the updater again, then restart the game."], "GameFontHighlight")
		if collapsed then
			win.Line.Text:SetText(GREY .. L["The quest data isn't there."] .. "|r")
		end
	elseif collapsed then
		useful = DrawLine()
	elseif mode == "quest" and shown then
		y = DrawNav(y)
		y = DrawQuest(y, shown)
	else
		mode = "now"
		y, useful = DrawCompanion(y)
	end
	if ready and not useful and opened ~= true and DB().autoHide and mode == "now" then
		Sleep()
		return
	end
	if not mapUsed then
		map:Hide()
	end
	if not PL.used then
		PL.Hide()
	end
	for i = rowsUsed + 1, #rows do
		RowLeave(rows[i])
		rows[i]:Hide()
	end
	for i = textsUsed + 1, #texts do
		texts[i]:Hide()
	end
	for i = rulesUsed + 1, #rules do
		rules[i]:Hide()
	end
	content:SetHeight(math.max(y, 10))
	win.Browser:SetShown(not collapsed and ready and (Q.OpenBrowser ~= nil or Q.ToggleBrowser ~= nil))
end

-- A redraw in a moment (several changes at once: one), or now.
function Q.RedrawSmall(now)
	if now then
		Draw()
	elseif not soon and win and win:IsShown() then
		soon = true
		C_Timer.After(LT.InCombat() and REDRAW_FIGHT or REDRAW_DELAY, function()
			soon = false
			Draw()
		end)
	end
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function OnEvent(_, event, id)
	if event == "QUEST_ACCEPTED" then
		Focus(tonumber(id), "accepted")
	elseif event == "QUEST_TURNED_IN" then
		id = tonumber(id)
		if id and not LT.IsSecret(id) then
			justDone = id
			if focus == id then
				focus = nil
			end
		end
	elseif event == "SUPER_TRACKING_CHANGED" then
		local super = SuperTracked()
		if super then
			Focus(super, "track")
		end
		superSeen = super
	end
	Q.RedrawSmall()
end

-- Every few seconds while shown: moved far enough (or into another zone), the distances are drawn anew.
local function Moved()
	if mode ~= "now" or not drawnAt then
		return
	end
	local zone, x, y = Q.HereZone()
	if zone ~= drawnAt[1] or (x and not drawnAt[2]) or (x and drawnAt[2]
		and math.abs(x - drawnAt[2]) + math.abs(y - drawnAt[3]) > MOVE_FAR) then
		Q.RedrawSmall()
	end
end

local function Build()
	win = LT.Window.Create(NAME, "Lodestar", WIDTH, HEIGHT)
	win:SetResizable(true)
	win:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
	win:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		self:SetUserPlaced(false)
		SavePlace()
	end)
	scroll, content = LT.Window.AddScroll(win)
	map = Q.NewMiniMap(content)

	-- The chain's bar (Bar): a dark track, a green fill.
	local bar = CreateFrame("Frame", nil, content)
	bar.Back = bar:CreateTexture(nil, "BACKGROUND")
	bar.Back:SetAllPoints()
	bar.Back:SetColorTexture(0, 0, 0, 0.55)
	bar.Fill = bar:CreateTexture(nil, "ARTWORK")
	bar.Fill:SetPoint("TOPLEFT", 1, -1)
	bar.Fill:SetPoint("BOTTOMLEFT", 1, 1)
	if C_Texture and C_Texture.GetAtlasInfo and LT.Value(C_Texture.GetAtlasInfo, "UI-Frame-Bar-Fill-Green") then
		bar.Fill:SetAtlas("UI-Frame-Bar-Fill-Green")
	else
		bar.Fill:SetColorTexture(0.25, 0.75, 0.25, 1)
	end
	bar:Hide()
	win.Bar = bar

	-- The corner to resize it by.
	local grip = CreateFrame("Button", nil, win)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -3, 3)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function() win:StartSizing("BOTTOMRIGHT") end)
	grip:SetScript("OnMouseUp", function()
		win:StopMovingOrSizing()
		win:SetUserPlaced(false)
		SavePlace()
		Draw()
	end)
	win.Grip = grip
	win:SetScript("OnSizeChanged", function() Q.RedrawSmall() end)

	-- The title bar's button: one line or the whole window (setting collapsed).
	local collapse = CreateFrame("Button", nil, win)
	collapse:SetSize(20, 20)
	if win.CloseButton then
		collapse:SetPoint("RIGHT", win.CloseButton, "LEFT", -2, 0)
	else
		collapse:SetPoint("TOPRIGHT", -26, -2)
	end
	collapse.Icon = collapse:CreateTexture(nil, "ARTWORK")
	collapse.Icon:SetAllPoints()
	collapse.Icon:SetAtlas("QuestLog-icon-shrink")
	collapse:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	collapse:SetScript("OnClick", function()
		LT:SetModuleSetting(Q.module, "collapsed", not DB().collapsed)
	end)
	collapse:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(DB().collapsed and L["The whole companion"] or L["One line"], 1, 1, 1)
		GameTooltip:Show()
	end)
	collapse:SetScript("OnLeave", RowLeave)
	win.Collapse = collapse

	-- The one line (collapsed): under the title bar, a click shows the whole companion.
	local line = CreateFrame("Button", nil, win)
	line:SetPoint("TOPLEFT", win, "TOPLEFT", 10, -26)
	line:SetPoint("TOPRIGHT", win, "TOPRIGHT", -10, -26)
	line:SetHeight(20)
	line:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	line.Text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	line.Text:SetPoint("LEFT", 2, 0)
	line.Text:SetPoint("RIGHT", -2, 0)
	line.Text:SetJustifyH("LEFT")
	line.Text:SetWordWrap(false)
	line:SetScript("OnClick", function(self)
		RowLeave(self)
		LT:SetModuleSetting(Q.module, "collapsed", false)
	end)
	line:SetScript("OnEnter", RowEnter)
	line:SetScript("OnLeave", RowLeave)
	line:Hide()
	win.Line = line

	-- Hidden by itself: a few rare events may bring something to show (then it opens again).
	local sleeper = CreateFrame("Frame")
	local waking = false
	sleeper:SetScript("OnEvent", function()
		if waking then
			return
		end
		waking = true
		C_Timer.After(REDRAW_DELAY, function()
			waking = false
			if asleep and Q.module.enabled and DB().autoHide and Q.Ready() and Useful() then
				Awake()
				win:Show()
				Draw()
			end
		end)
	end)
	win.Sleeper = sleeper

	win.Browser = LT.Window.AddButton(win, L["Quest browser"], function()
		local id = mode == "quest" and shown or nowId
		if Q.OpenBrowser and id then
			Q.OpenBrowser(id)
		elseif Q.ToggleBrowser then
			Q.ToggleBrowser()
		end
	end, { "BOTTOMRIGHT", win, "BOTTOMRIGHT", -22, 3 })
	win.Browser:SetWidth(120)

	-- Whether I moved, every few seconds, only while it's shown (a child of it: hidden, it doesn't run).
	local mover = CreateFrame("Frame", nil, win)
	local wait = MOVE_EVERY
	mover:SetScript("OnUpdate", function(_, elapsed)
		wait = wait - elapsed
		if wait <= 0 then
			wait = MOVE_EVERY
			Moved()
		end
	end)
	win.Mover = mover

	-- The quest log, tracking, level-ups and zones, only while it's shown.
	win:HookScript("OnShow", function(self)
		for _, event in ipairs(EVENTS) do
			self:RegisterEvent(event)
		end
	end)
	win:HookScript("OnHide", function(self)
		if not selfHiding then
			Awake() -- (closed by you: it stays closed)
		end
		self:UnregisterAllEvents()
		for _, row in ipairs(rows) do
			RowLeave(row)
		end
		map:Hide()
		PL.Hide()
	end)
	win:SetScript("OnEvent", OnEvent)
	if Q.OnDataChanged then
		Q.OnDataChanged(function()
			Q.RedrawSmall()
		end)
	end
	if Q.OnPlanChanged then -- (the plan changed: added, moved, a stop skipped, a quest turned in)
		Q.OnPlanChanged(function()
			Q.RedrawSmall()
		end)
	end
end

local function Open()
	Awake()
	if not win:IsShown() then
		Place()
		win:Show()
	end
	if win.Raise then
		win:Raise()
	end
	Draw(true)
end

-- Shows a quest looked at, the one looked at before kept for "back to".
Look = function(id)
	id = tonumber(id)
	if mode == "quest" and shown and id ~= shown and win:IsShown() then
		history[#history + 1] = shown
		if #history > HISTORY then
			table.remove(history, 1)
		end
	end
	if id ~= shown or mode ~= "quest" then
		mapSide = nil
		scroll:SetVerticalScroll(0)
	end
	mode, shown = id and "quest" or "now", id
	Open()
end

function Q.ShowQuest(id)
	if not Q.module.enabled then
		return
	end
	if not win then
		Build()
	end
	if not win:IsShown() then
		wipe(history)
	end
	Look(id)
end

-- Whether the small window is open (the big window shows a clicked quest in it then).
function Q.IsSmallShown()
	return win ~= nil and win:IsShown() == true
end

-- Opens it on now (the quest I'm on, what to pick up next), or closes it.
function Q.ToggleSmall()
	if win and win:IsShown() then
		win:Hide()
		return
	end
	if not Q.module.enabled then
		return
	end
	if not win then
		Build()
	end
	mode, shown, mapSide = "now", nil, nil
	wipe(history)
	scroll:SetVerticalScroll(0)
	Open()
end

-- A quest opened in the quest log (Lodestar.lua's hook): it's what I'm on from now; shown, the
-- window goes to now and redraws a moment later (in its own code, not the quest log's).
function Q.SmallFollow(id)
	id = tonumber(id)
	if not id then
		return
	end
	Focus(id, "log")
	if win and win:IsShown() then
		mode, shown, mapSide = "now", nil, nil
		wipe(history)
		Q.RedrawSmall()
	end
end

Q.When("disable", function()
	if win then
		win:Hide()
	end
end)

Q.When("settings", function()
	if asleep and not DB().autoHide then -- (it hid itself: it comes back)
		Awake()
		win:Show()
	end
	if win and win:IsShown() then
		Draw(true)
	end
end)

-- For tests: the window, its small map, the rows in use (clickable lines), the texts in use (their
-- strings: the rows' first, then the other lines'), the quest looked at, the one "Now" shows, the
-- mode and the quests looked at before.
function Q.SmallFrame()
	local list, strings = {}, {}
	for i = 1, rowsUsed do
		list[i] = rows[i]
		strings[#strings + 1] = rows[i].Text:GetText()
	end
	for i = 1, textsUsed do
		strings[#strings + 1] = texts[i]:GetText()
	end
	local marks = {}
	for i = 1, #(PL.shown or {}) do
		marks[i] = PL.marks[i]
	end
	return { win = win, map = map, rows = list, texts = strings, quest = mode == "quest" and shown or nil, now = nowId,
		mode = mode, history = history, content = content, asleep = asleep, collapsed = collapsedNow,
		line = win and win.Line, planMap = PL.used and PL.map or nil, planMarks = marks, planLines = PL.lines }
end
