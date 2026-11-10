local _, ns = ...
local LT = ns.LT
local L = ns.L
local Q = ns.Questtree or {}; ns.Questtree = Q

-- The small window: the companion. It follows what you're doing without being asked.
--
-- Opened on its own (/questtree) it shows, top down:
--   Now: the quest you're on (the last one you accepted, super-tracked or opened in the quest log;
--     else the first on your tracker, else one of your log in this zone), "[18] Title" in its
--     difficulty colour, its chain ("The Defias Brotherhood: step 3 of 7" and a bar), friends who
--     did it, whether it's ready to turn in and its objectives, where to turn it in (with how far
--     and which way), what it leads to ("Next: ..."), and the chain's steps (done ones ticked
--     green, this one bold, the rest grey, friends' dots on each).
--   The small map: the turn-in's zone (else yours) with the turn-in, your other quests' turn-ins and
--     the givers of what you can pick up there, and your arrow.
--   Pick up next, in groups: In progress (your other quests, ready ones first), Available now
--     (follow-ups of what you just finished or have, then this zone's quests, the nearest giver
--     first, each with its giver, how far and which way), Coming up (level too low yet) and
--     Blocked (what each needs first).
-- A click on a quest shows everything about it (its title, chain, status, what it needs first,
-- giver and turn-in, where its item drops, the map, what it leads to, friends); at the top then
-- "« Back to <the quest before>" and "Back to now". A click on a giver, turn-in or map marker sets
-- the game's own map pin there (Q.Waypoint), Shift-click puts it in the chat box too.
--
-- While it's shown it listens to the quest log (accepted, turned in, abandoned, progress), super
-- tracking, the tracker, level-ups and zone changes, and redraws a moment later; every 2 s it looks
-- whether you've moved (the distances); the quest log's "show details" (Questtree.lua's hook) hands
-- it the quest you opened there. Hidden, it listens to nothing and nothing of it runs. A window of
-- ours (LT.Window.Create: Escape closes it, it counts as an open window for Mirage), movable and
-- resizable, where it is and its size kept (setting keepPlace). Built the first time it opens; the
-- data loads then too (Q.Ready), never at login. Every line that does something is a button, so a
-- controller's cursor reaches it.
--   Q.ToggleSmall(), Q.ShowQuest(id), Q.RedrawSmall(now), Q.IsSmallShown(), Q.SmallFollow(id);
--   Q.SmallFrame() for tests.

local NAME = "LefthyToolsQuesttreeSmall"
local WIDTH, HEIGHT = 340, 580
local MIN_W, MIN_H, MAX_W, MAX_H = 300, 300, 600, 950
local SCROLL_SIDE = 60 -- the scroll area's child is the window's width less this (LT.Window.AddScroll)
local GAP = 4
local INDENT = 10
local LIST_MAX = 8       -- lines of "Needs first" and "Leads to" (the rest: "and N more")
local STEPS_MAX = 8      -- a chain's steps in sight (from two before this one)
local OBJECTIVES_MAX = 6
local LOG_MAX, PICK_MAX, SOON_MAX = 4, 6, 3
local HISTORY = 20       -- quests "back to" goes through
local REDRAW_DELAY = 0.3
local REDRAW_FIGHT = 1   -- s: in a fight (the quest log changes with every kill and loot)
local MOVE_EVERY, MOVE_FAR = 2, 0.02 -- s between looks whether I moved; how far (of the map) is a move
local GOLD, GREY, LIGHT, GREEN = "|cffffd200", "|cff9d9d9d", "|cffbebebe", "|cff40c040"
local ICON = {
	start = "|TInterface\\GossipFrame\\AvailableQuestIcon:0|t ",
	turnin = "|TInterface\\GossipFrame\\ActiveQuestIcon:0|t ",
	progress = "|TInterface\\GossipFrame\\IncompleteQuestIcon:0|t ",
	check = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t ",
	here = "|TInterface\\ChatFrame\\ChatFrameExpandArrow:0|t ",
}
local DOT = "|TInterface\\CharacterFrame\\TempPortraitAlphaMask:8:8:0:0:64:64:0:64:0:64:%d:%d:%d|t"
local EVENTS = { "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED",
	"SUPER_TRACKING_CHANGED", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }
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
	saved.width, saved.height = math.floor(win:GetWidth() + 0.5), math.floor(win:GetHeight() + 0.5)
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
		win:SetSize(Clamp(saved.width, MIN_W, MAX_W, WIDTH), Clamp(saved.height, MIN_H, MAX_H, HEIGHT))
	else
		win:SetPoint("CENTER", UIParent, "CENTER", 280, 40)
		win:SetSize(WIDTH, HEIGHT)
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
-- tooltip = { title, line, ... }, indent, x, w (a part of the line's width) }.
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
	row.onClick, row.tooltip = o.onClick, o.tooltip
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
	rule:SetColorTexture(1, 0.82, 0, 0.25)
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

-- Its chain as I can do it (quests not for me left out) and where it is in it; nil: no chain.
local function ChainOf(id)
	local chain = Q.Chain and Q.Chain(id)
	if type(chain) ~= "table" or #chain < 2 then
		return nil
	end
	local list, at = {}, nil
	for _, other in ipairs(chain) do
		if other == id or Q.StatusOf(other) ~= "other" then
			list[#list + 1] = other
			if other == id then
				at = #list
			end
		end
	end
	if not at or #list < 2 then
		return nil
	end
	return list, at
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
	local text = prefix .. Q.LevelTitle(id, quest) .. "  " .. Q.StatusText(status, "word")
	local tooltip = { Q.Title(id, quest), Q.StatusText(status) }
	if type(reason) == "string" and reason ~= "" then
		tooltip[#tooltip + 1] = reason
	end
	tooltip[#tooltip + 1] = L["Click: show this quest"]
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

-- The chain's steps around this one: done ticked green, this one bold, the rest grey; friends'
-- dots after each.
local function Steps(y, chain, at)
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
			text, font = ICON.here .. i .. ". " .. Q.Title(id), "GameFontNormal"
		elseif status == "done" then
			text = ICON.check .. GREEN .. Q.Title(id) .. "|r"
		else
			text = LIGHT .. i .. ". " .. Q.Title(id) .. "|r"
		end
		local dots = FriendsOf(id)
		y = Row(y, { text = text .. (dots and dots ~= "" and ("  " .. dots) or ""), font = font, indent = INDENT,
			onClick = Shows(id), tooltip = { Q.LevelTitle(id), Q.StatusText(status), L["Click: show this quest"] } })
	end
	if last < #chain then
		y = Text(y, GREY .. L["... %d more"]:format(#chain - last) .. "|r", "GameFontHighlightSmall", INDENT)
	end
	return y
end

-- "Its chain: step 3 of 7" and the bar.
local function ChainLine(y, chain, at)
	y = Text(y, GREY .. L["%s: step %d of %d"]:format(Q.Title(chain[1]), at, #chain) .. "|r", "GameFontHighlightSmall")
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

-- The groups of "Pick up next": { log, now, soon, blocked, more } of { id, follows }.
local function PickLists(ctx)
	local seen = { [ctx.now or 0] = true }
	for _, id in ipairs(ctx.now and Q.Opens and Q.Opens(ctx.now) or {}) do
		seen[id] = true -- (Now's "Next:")
	end
	local lists = { log = {}, now = {}, soon = {}, blocked = {}, more = 0 }
	local function Add(list, id, max, follows)
		if seen[id] then
			return
		end
		seen[id] = true
		if #list < max then
			list[#list + 1] = { id = id, follows = follows }
		elseif list == lists.now then
			lists.more = lists.more + 1
		end
	end
	-- In progress: ready to turn in first, then those turned in here.
	local log = LogQuests()
	local rank = {}
	for _, id in ipairs(log) do
		local quest = Q.Quest(id)
		rank[id] = (IsComplete(id) and 0 or 2) + ((ctx.zone and quest and Q.NearestPoint(quest.ends, ctx.zone)) and 0 or 1)
	end
	table.sort(log, function(a, b)
		if rank[a] ~= rank[b] then
			return rank[a] < rank[b]
		end
		return a < b
	end)
	for _, id in ipairs(log) do
		Add(lists.log, id, LOG_MAX)
	end
	-- Follow-ups: of what I just turned in, then of everything done or in my log (Q.Next).
	for _, id in ipairs(justDone and Q.Opens and Q.Opens(justDone) or {}) do
		if Q.StatusOf(id) == "available" then
			Add(lists.now, id, PICK_MAX, justDone)
		end
	end
	for _, id in ipairs(Q.Next and Q.Next() or {}) do
		local status = Q.StatusOf(id)
		if status == "available" then
			Add(lists.now, id, PICK_MAX, Follows(Q.Quest(id)))
		elseif status == "locked" and not seen[id] and #lists.blocked < SOON_MAX then
			Add(lists.blocked, id, SOON_MAX)
		elseif status == "level" and not seen[id] and #lists.soon < SOON_MAX then
			Add(lists.soon, id, SOON_MAX)
		end
	end
	-- This zone's, the nearest giver first.
	for _, id in ipairs(Q.AvailableIn(ctx.zone, ctx.x, ctx.y)) do
		Add(lists.now, id, PICK_MAX)
	end
	-- Coming up here: the next levels' quests.
	if ctx.zone and #lists.soon < SOON_MAX then
		local later = {}
		for _, id in ipairs(Q.ZoneQuests and Q.ZoneQuests(ctx.zone) or {}) do
			if not seen[id] and Q.StatusOf(id) == "level" then
				later[#later + 1] = id
			end
		end
		local function From(id)
			local q = Q.Quest(id)
			return q and (q.minLevel or q.level) or 0
		end
		table.sort(later, function(a, b)
			if From(a) ~= From(b) then
				return From(a) < From(b)
			end
			return a < b
		end)
		for _, id in ipairs(later) do
			Add(lists.soon, id, SOON_MAX)
		end
	end
	return lists
end

-- A quest of "Pick up next": icon, "[12] Title", how far; its giver and what it follows under it.
local function PickRow(y, entry, ctx, group)
	local id = entry.id
	local quest = Q.Quest(id)
	local status = Q.StatusOf(id)
	local icon, right, note = ICON.start, nil, nil
	if group == "log" then
		local ready = IsComplete(id)
		icon = ready and ICON.turnin or ICON.progress
		right = quest and Far(quest.ends, ctx)
		local ender = quest and quest.ends and quest.ends[1]
		note = (ready and (GREEN .. L["ready to turn in"] .. "|r") or L["in your log"])
			.. (ender and (" · " .. (ender.name or L["unknown"])) or "")
	elseif group == "soon" then
		note = Q.StatusCode("level") .. L["from level %d"]:format(quest and (quest.minLevel or quest.level) or 0) .. "|r"
			.. " · " .. GiverNote(quest, id, ctx)
	elseif group == "blocked" then
		local missing = Q.Missing and Q.Missing(id) or {}
		note = Q.StatusCode("locked") .. (missing[1] and L["needs %s"]:format(Q.Title(missing[1].id)) or L["needs one first"]) .. "|r"
	else
		right = quest and Far(quest.starts, ctx)
		note = GiverNote(quest, id, ctx, entry.follows)
	end
	local text = icon .. Q.LevelTitle(id, quest)
	if note and note ~= "" then
		text = text .. "\n" .. GREY .. note .. "|r"
	end
	local tooltip = { Q.Title(id, quest), Q.StatusText(status) }
	local step, total, chain = Q.StepOf(id)
	if step then
		tooltip[#tooltip + 1] = L["%s: step %d of %d"]:format(chain or "", step, total)
	end
	tooltip[#tooltip + 1] = L["Click: show this quest"]
	return Row(y, { text = text, right = right, onClick = Shows(id), tooltip = tooltip, indent = 2 })
end

-- Now: the quest I'm on (none: says so). Notes the map it wants and its markers in ctx.
local function DrawNow(y, ctx)
	local id = ctx.now
	y = Header(y, L["Now"], id and WHY[ctx.why])
	if not id then
		return Text(y, L["No quest in your log. Pick one up below."], "GameFontDisableSmall", INDENT)
	end
	local quest = Q.Quest(id)
	y = Row(y, { text = Q.LevelTitle(id, quest), font = "GameFontNormalLarge", onClick = Shows(id),
		tooltip = { Q.Title(id, quest), L["Click: everything about it"] } })
	local chain, at = ChainOf(id)
	if chain then
		y = ChainLine(y, chain, at)
	end
	y = FriendsRow(y, id)
	local ready = IsComplete(id)
	y = Text(y + 2, ready and (GREEN .. L["Ready to turn in"] .. "|r") or Q.StatusText("active"), "GameFontHighlight")
	local objectives = C_QuestLog and LT.Value(C_QuestLog.GetQuestObjectives, id)
	for i, o in ipairs(type(objectives) == "table" and objectives or {}) do
		if i > OBJECTIVES_MAX then
			break
		end
		if type(o) == "table" and type(o.text) == "string" and not LT.IsSecret(o.text) and o.text ~= "" then
			y = Text(y, o.finished and (ICON.check .. GREY .. o.text .. "|r") or ("- " .. o.text), "GameFontHighlightSmall", INDENT)
		end
	end
	if not quest then
		return y
	end
	-- Where to turn it in (on the map with it), and what it leads to.
	y = PlaceRow(y + 2, L["Turn-in:"], quest.ends, "end", ctx, ready and ICON.turnin or ICON.progress)
	local point = Q.NearestPoint(quest.ends, ctx.zone)
	local first = quest.ends and quest.ends[1]
	ctx.map = point and ctx.zone or (first and first.points and first.points[1] and first.points[1].map) or nil
	for _, who in ipairs(quest.ends or {}) do
		for _, p in ipairs(who.points or {}) do
			ctx.points[#ctx.points + 1] = { x = p.x, y = p.y, kind = "end", look = ready and "turnin" or "progress",
				label = who.name or L["unknown"], note = Q.Title(id, quest), map = p.map }
		end
	end
	local opens = Q.Opens and Q.Opens(id) or {}
	if opens[1] then
		local nextQuest = Q.Quest(opens[1])
		local giver = nextQuest and nextQuest.starts and nextQuest.starts[1]
		local text = GOLD .. L["Next:"] .. "|r " .. Q.LevelTitle(opens[1], nextQuest)
			.. (giver and (GREY .. " - " .. (Who(nextQuest.starts, ctx.zone) or "") .. "|r") or "")
		if #opens > 1 then
			text = text .. " " .. GREY .. L["(+%d more)"]:format(#opens - 1) .. "|r"
		end
		y = Row(y, { text = text, onClick = Shows(opens[1]),
			tooltip = { Q.Title(opens[1], nextQuest), Q.StatusText(Q.StatusOf(opens[1])), L["Click: show this quest"] } })
	end
	if chain then
		y = SubHeader(y + 2, L["Steps"])
		y = Steps(y, chain, at)
	end
	return y
end

-- The markers of "Pick up next" on the map shown: givers to pick up, my quests' turn-ins.
local function PickPoints(ctx, lists)
	local function Add(people, kind, look, note)
		for _, who in ipairs(people or {}) do
			for _, p in ipairs(who.points or {}) do
				if p.map == ctx.map then
					ctx.points[#ctx.points + 1] = { x = p.x, y = p.y, kind = kind, look = look, label = who.name or L["unknown"],
						note = note, map = p.map }
				end
			end
		end
	end
	for _, entry in ipairs(lists.now) do
		local quest = Q.Quest(entry.id)
		local look = quest and quest.repeatable and "repeatable" or (Q.DifficultyKey(entry.id, quest) == "trivial" and "trivial" or "available")
		Add(quest and quest.starts, "start", look, Q.Title(entry.id, quest))
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
	local groups = { { "log", L["In progress"] }, { "now", L["Available now"] }, { "soon", L["Coming up"] },
		{ "blocked", L["Blocked"] } }
	local any = false
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
					end, tooltip = { L["Quest browser"], L["Every zone's quest chains, with a search over all of them. Also /questtree browse."] } })
			end
		end
	end
	if not any then
		y = Text(y, L["Nothing to pick up nearby. The quest browser has every zone."], "GameFontDisableSmall", INDENT)
	end
	return y
end

local function DrawCompanion(y)
	local zone, x, py = Q.HereZone()
	drawnAt = { zone, x, py }
	local ctx = { zone = zone, x = x, y = py, points = {} }
	ctx.now, ctx.why = NowQuest(zone)
	nowId = ctx.now
	local lists = PickLists(ctx)
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
	return DrawPick(y, ctx, lists)
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
	local startLook = status == "available" and (quest.repeatable and "repeatable" or (Q.DifficultyKey(id, quest) == "trivial" and "trivial" or "available"))
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
	y = Text(y + 2, quest and Q.LevelTitle(id, quest) or Q.Title(id), "GameFontNormalLarge")
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
	local line = Q.StatusText(status)
	if status == "level" and tonumber(quest.minLevel) then
		line = Q.StatusCode(status) .. L["Your level is too low: from level %d"]:format(quest.minLevel) .. "|r"
	elseif status == "active" and IsComplete(id) then
		line = GREEN .. L["Ready to turn in"] .. "|r"
	end
	y = Text(y + 2, line, "GameFontHighlight")
	y = Requires(y, id, chain)
	y = List(y, L["Needs first:"], Q.Missing and Q.Missing(id) or {}, true)
	local starter = quest.starts and quest.starts[1]
	y = PlaceRow(y + GAP, L["Quest giver:"], quest.starts, "start", ctx, ICON.start)
	if starter and starter.kind == "item" then
		y = DropLines(y, quest)
	end
	y = PlaceRow(y, L["Turn-in:"], quest.ends, "end", ctx, ICON.turnin)
	y = QuestMap(y, id, quest, status, ctx)
	y = List(y, L["Leads to:"], Q.Opens and Q.Opens(id) or {}, false)
	if chain then
		y = SubHeader(y + 2, L["Steps"])
		y = Steps(y, chain, at)
	end
	return FriendsRow(y + GAP, id)
end

---------------------------------------------------------------------------
-- Drawing it all
---------------------------------------------------------------------------

Draw = function()
	if not (win and win:IsShown()) then
		return
	end
	rowsUsed, textsUsed, rulesUsed, mapUsed = 0, 0, 0, false
	win.Bar:Hide()
	width = math.max(100, win:GetWidth() - SCROLL_SIDE)
	content:SetWidth(width)
	local y = 2
	local ready = Q.Ready()
	if not ready then
		nowId = nil
		y = Text(y, L["The quest data isn't there. It's an add-on of its own, LefthyTools Quest Data, installed with LefthyTools: run the updater again, then restart the game."], "GameFontHighlight")
	elseif mode == "quest" and shown then
		y = DrawNav(y)
		y = DrawQuest(y, shown)
	else
		mode = "now"
		y = DrawCompanion(y)
	end
	if not mapUsed then
		map:Hide()
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
	win.Browser:SetShown(ready and (Q.OpenBrowser ~= nil or Q.ToggleBrowser ~= nil))
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
	win = LT.Window.Create(NAME, "Questtree", WIDTH, HEIGHT)
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
		self:UnregisterAllEvents()
		for _, row in ipairs(rows) do
			RowLeave(row)
		end
		map:Hide()
	end)
	win:SetScript("OnEvent", OnEvent)
	if Q.OnDataChanged then
		Q.OnDataChanged(function()
			Q.RedrawSmall()
		end)
	end
end

local function Open()
	if not win:IsShown() then
		Place()
		win:Show()
	end
	if win.Raise then
		win:Raise()
	end
	Draw()
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

-- A quest opened in the quest log (Questtree.lua's hook): it's what I'm on from now; shown, the
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
	Q.RedrawSmall()
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
	return { win = win, map = map, rows = list, texts = strings, quest = mode == "quest" and shown or nil, now = nowId,
		mode = mode, history = history, content = content }
end
