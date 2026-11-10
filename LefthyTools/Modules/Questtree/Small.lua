local _, ns = ...
local LT = ns.LT
local L = ns.L
local Q = ns.Questtree or {}; ns.Questtree = Q

-- The small window: one quest at a time. Its title (the client's when it answers, else the data's),
-- level and zone, my status in its colour, "Needs first:" (Q.Missing: the chain walked back, the
-- one to do first at the top; each line shows that quest), the giver and the turn-in (name, zone;
-- each line puts its map in the small map below), the small map with both on it (Q.NewMiniMap),
-- "Leads to:" (Q.Opens, each line shows that quest) and friends' progress (Q.Friends). Opened on
-- its own (/questtree) it shows what's next for me (Q.Next()[1]). Buttons: Back (the quest shown
-- before), Next up, the quest browser (Browser.lua, when it's there).
--
-- A window of ours (LT.Window.Create: Escape closes it, it counts as an open window for Mirage),
-- movable and resizable, where it is and its size kept (setting keepPlace). Built the first time
-- it opens; the data loads then too (Q.Ready), never at login. While it's shown it listens to the
-- quest log (accepted, turned in, abandoned) and level-ups and redraws a moment later; hidden, it
-- listens to nothing and nothing of it runs. Every line that does something is a button, so a
-- controller's cursor reaches it.
--   Q.ShowQuest(id), Q.ToggleSmall(), Q.RedrawSmall(); Q.SmallFrame() for tests.

local NAME = "LefthyToolsQuesttreeSmall"
local WIDTH, HEIGHT = 320, 470
local MIN_W, MIN_H, MAX_W, MAX_H = 300, 260, 600, 900
local SCROLL_SIDE = 60 -- the scroll area's child is the window's width less this (LT.Window.AddScroll)
local GAP = 4
local INDENT = 8
local LIST_MAX = 8     -- lines of "Needs first" and "Leads to" (the rest: "and N more")
local HISTORY = 20     -- quests Back goes through
local REDRAW_DELAY = 0.3
local GOLD = "|cffffd200"
local EVENTS = { "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "PLAYER_LEVEL_UP" }

local win, content, scroll, map
local shown          -- the quest shown (nil: none)
local history = {}   -- the quests shown before it, the last one last
local mapSide        -- "start" | "end": whose map the small map shows (nil: by my status)
local rows, rowsUsed = {}, 0
local texts, textsUsed = {}, 0
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
-- Lines: font strings and clickable rows, pooled
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

local function RowClick(self)
	RowLeave(self)
	if self.onClick then
		self.onClick()
	end
end

-- A line that does something when clicked; tooltip = { title, line, ... }.
local function Row(y, text, onClick, tooltip, indent)
	rowsUsed = rowsUsed + 1
	local row = rows[rowsUsed]
	if not row then
		row = CreateFrame("Button", nil, content)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.Text:SetPoint("TOPLEFT", 3, -2)
		row.Text:SetJustifyH("LEFT")
		row:SetScript("OnClick", RowClick)
		row:SetScript("OnEnter", RowEnter)
		row:SetScript("OnLeave", RowLeave)
		rows[rowsUsed] = row
	end
	indent = indent or 0
	row.onClick, row.tooltip = onClick, tooltip
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", content, "TOPLEFT", indent, -y)
	row.Text:SetWidth(width - indent - 6)
	row.Text:SetText(text)
	local height = math.ceil(row.Text:GetStringHeight()) + 4
	row:SetSize(width - indent, height)
	row:Show()
	return y + height + 1
end

local function Heading(y, text)
	return Text(y + GAP, GOLD .. text .. "|r", "GameFontNormal")
end

---------------------------------------------------------------------------
-- What's drawn
---------------------------------------------------------------------------

local Go -- (below: shows a quest, the one before kept for Back)

local function Shows(id)
	return function() Go(id) end
end

-- A quest in a list: its title, level and my status; its tooltip says why (reason) and what a click does.
local function QuestRow(y, id, prefix, reason)
	local quest = Q.Quest(id)
	local level = quest and tonumber(quest.level)
	local status = Q.StatusOf(id)
	local text = ("%s%s%s  %s"):format(prefix, Q.Title(id, quest), level and (" (" .. level .. ")") or "", Q.StatusText(status, "word"))
	local tooltip = { Q.Title(id, quest), Q.StatusText(status) }
	if type(reason) == "string" and reason ~= "" then
		tooltip[#tooltip + 1] = reason
	end
	tooltip[#tooltip + 1] = L["Click: show this quest"]
	return Row(y, text, Shows(id), tooltip, INDENT)
end

local function List(y, heading, list, numbered)
	if #list == 0 then
		return y
	end
	y = Heading(y, heading)
	for i = 1, math.min(#list, LIST_MAX) do
		local entry = list[i]
		local id = type(entry) == "table" and entry.id or entry
		y = QuestRow(y, id, numbered and (i .. ". ") or "- ", type(entry) == "table" and entry.reason)
	end
	if #list > LIST_MAX then
		y = Text(y, L["and %d more"]:format(#list - LIST_MAX), "GameFontDisableSmall", INDENT + 4)
	end
	return y
end

local function HereMap()
	return C_Map and C_Map.GetBestMapForUnit and LT.Value(C_Map.GetBestMapForUnit, "player")
end

-- Whose map: a point of theirs on the map I'm on, else their first point's map.
local function MapOf(people, here)
	local first
	for _, who in ipairs(people or {}) do
		for _, point in ipairs(who.points or {}) do
			if point.map == here then
				return here
			end
			first = first or point.map
		end
	end
	return first
end

-- A giver or turn-in: "Name, Zone" (an item or an object says so), "+2 more" when there are more.
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
	local zone = Q.MapName(MapOf({ first }, here))
	local text = zone and (name .. ", " .. zone) or name
	if #people > 1 then
		text = text .. " " .. L["(+%d more)"]:format(#people - 1)
	end
	return text
end

local function WhoTooltip(title, people, here)
	local tip = { title }
	for _, who in ipairs(people) do
		local zone = Q.MapName(MapOf({ who }, here))
		tip[#tip + 1] = (who.name or L["unknown"]) .. (zone and (", " .. zone) or "")
	end
	tip[#tip + 1] = L["Click: show it on the map"]
	return tip
end

local function ShowSide(side)
	return function()
		mapSide = side
		Q.RedrawSmall(true)
	end
end

-- The giver's and the turn-in's lines.
local function People(y, quest, here)
	local labels = { start = L["Quest giver:"], ["end"] = L["Turn-in:"] }
	for _, side in ipairs({ "start", "end" }) do
		local people = side == "start" and quest.starts or quest.ends
		local who = Who(people, here)
		local label = GOLD .. labels[side] .. "|r "
		if who then
			y = Row(y, label .. who, ShowSide(side), WhoTooltip(labels[side], people, here))
		else
			y = Text(y, label .. L["not known"], "GameFontHighlightSmall", 3)
		end
	end
	return y
end

-- The small map: the giver's (or, for a quest in my log, the turn-in's) zone unless a line picked
-- one, with every giver and turn-in on it.
local function DrawMap(y, quest, status, here)
	local side = mapSide or (status == "active" and "end" or "start")
	local mapID = MapOf(side == "end" and quest.ends or quest.starts, here)
		or MapOf(side == "end" and quest.starts or quest.ends, here) or quest.zone
	if not mapID then
		map:Hide()
		return y
	end
	local points = {}
	for _, kind in ipairs({ "start", "end" }) do
		for _, who in ipairs((kind == "start" and quest.starts or quest.ends) or {}) do
			for _, point in ipairs(who.points or {}) do
				if point.map == mapID then
					points[#points + 1] = { x = point.x, y = point.y, kind = kind, label = who.name or L["unknown"] }
				end
			end
		end
	end
	local height = math.floor(width * 2 / 3 + 0.5)
	map:SetSize(width, height)
	map.frame:ClearAllPoints()
	map.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(y + GAP))
	map:Show(mapID, points)
	return y + GAP + height + GAP
end

local function FriendsLine(y, id)
	if not (DB().friends and Q.Friends) then
		return y
	end
	local parts = {}
	for _, friend in ipairs(Q.Friends(id) or {}) do
		local name = friend.name and LT.Window.ClassColorCode(friend.classFile) .. friend.name .. "|r"
		if name then
			parts[#parts + 1] = name .. " (" .. Q.StatusText(friend.status, "friend") .. ")"
		end
	end
	if #parts == 0 then
		return y
	end
	return Text(y + GAP, GOLD .. L["Friends:"] .. "|r " .. table.concat(parts, ", "))
end

local function DrawQuest(y, id)
	local quest = Q.Quest(id)
	y = Text(y, Q.Title(id, quest), "GameFontNormalLarge")
	if not quest then
		return Text(y, L["This quest isn't in the quest data."], "GameFontDisableSmall")
	end
	local here = HereMap()
	local about = {}
	about[#about + 1] = Q.LevelText(quest)
	about[#about + 1] = Q.MapName(quest.zone) or quest.zoneName
	about[#about + 1] = quest.dungeon and L["Dungeon: %s"]:format(quest.dungeon)
	about[#about + 1] = quest.repeatable and L["Repeatable"] or nil
	about[#about + 1] = quest.new and L["New in WoW: Forever"] or nil
	if #about > 0 then
		y = Text(y, table.concat(about, ", "), "GameFontDisableSmall")
	end
	local status = Q.StatusOf(id)
	local line = Q.StatusText(status)
	if status == "level" and tonumber(quest.minLevel) then
		line = Q.StatusCode(status) .. L["Your level is too low: from level %d"]:format(quest.minLevel) .. "|r"
	end
	y = Text(y + 2, line, "GameFontHighlight")
	y = List(y, L["Needs first:"], Q.Missing and Q.Missing(id) or {}, true)
	y = People(y + GAP, quest, here)
	y = DrawMap(y, quest, status, here)
	y = List(y, L["Leads to:"], Q.Opens and Q.Opens(id) or {}, false)
	return FriendsLine(y, id)
end

local function Draw()
	if not (win and win:IsShown()) then
		return
	end
	rowsUsed, textsUsed = 0, 0
	width = math.max(100, win:GetWidth() - SCROLL_SIDE)
	content:SetWidth(width)
	local y = 2
	local ready = Q.Ready()
	if not ready then
		y = Text(y, L["The quest data isn't there. It's an add-on of its own, LefthyTools Quest Data, installed with LefthyTools: run the updater again, then restart the game."], "GameFontHighlight")
	elseif not shown then
		y = Text(y, L["Nothing up next found for you. Show a quest with /questtree and its name, or pick one in the quest browser."], "GameFontHighlight")
	else
		y = DrawQuest(y, shown)
	end
	if not (ready and shown and Q.Quest(shown)) then
		map:Hide()
	end
	for i = rowsUsed + 1, #rows do
		RowLeave(rows[i])
		rows[i]:Hide()
	end
	for i = textsUsed + 1, #texts do
		texts[i]:Hide()
	end
	content:SetHeight(math.max(y, 10))
	win.Back:SetShown(#history > 0)
	win.Next:SetEnabled(ready)
	win.Browser:SetShown(Q.OpenBrowser ~= nil or Q.ToggleBrowser ~= nil)
end

-- A redraw in a moment (several changes at once: one), or now.
function Q.RedrawSmall(now)
	if now then
		Draw()
	elseif not soon and win and win:IsShown() then
		soon = true
		C_Timer.After(REDRAW_DELAY, function()
			soon = false
			Draw()
		end)
	end
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

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

	win.Back = LT.Window.AddButton(win, L["Back"], function()
		local id = table.remove(history)
		if id then
			shown, mapSide = id, nil
			scroll:SetVerticalScroll(0)
			Draw()
		end
	end, { "BOTTOMLEFT", win, "BOTTOMLEFT", 8, 3 })
	win.Back:SetWidth(70)
	win.Next = LT.Window.AddButton(win, L["Next up"], function()
		local list = Q.Ready() and Q.Next and Q.Next() or {}
		if list[1] then
			Go(list[1])
		else
			Q.module:Print("nothing up next found for you.")
		end
	end, { "BOTTOMLEFT", win, "BOTTOMLEFT", 82, 3 })
	win.Next:SetWidth(84)
	win.Browser = LT.Window.AddButton(win, L["Quest browser"], function()
		if Q.OpenBrowser and shown then
			Q.OpenBrowser(shown)
		elseif Q.ToggleBrowser then
			Q.ToggleBrowser()
		end
	end, { "BOTTOMRIGHT", win, "BOTTOMRIGHT", -22, 3 })
	win.Browser:SetWidth(110)

	-- The quest log and level-ups, only while it's shown.
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
	win:SetScript("OnEvent", function()
		Q.RedrawSmall()
	end)
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

-- Shows a quest (nil: none), the one shown before kept for Back.
Go = function(id)
	if shown and id ~= shown and win:IsShown() then
		history[#history + 1] = shown
		if #history > HISTORY then
			table.remove(history, 1)
		end
	end
	if id ~= shown then
		mapSide = nil
		scroll:SetVerticalScroll(0)
	end
	shown = id
	Open()
end

function Q.ShowQuest(id)
	if not Q.module.enabled then
		return
	end
	if not win then
		Build()
	end
	Go(tonumber(id))
end

-- Opens it on what's next for me (Q.Next()[1]; none: what it showed last), or closes it.
-- Whether the small window is open (the big window shows a clicked quest in it then).
function Q.IsSmallShown()
	return win ~= nil and win:IsShown() == true
end

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
	local list = Q.Ready() and Q.Next and Q.Next() or {}
	Go(list[1] or shown)
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
-- strings: the rows' first, then the other lines'), the quest shown and the ones before it.
function Q.SmallFrame()
	local list, strings = {}, {}
	for i = 1, rowsUsed do
		list[i] = rows[i]
		strings[#strings + 1] = rows[i].Text:GetText()
	end
	for i = 1, textsUsed do
		strings[#strings + 1] = texts[i]:GetText()
	end
	return { win = win, map = map, rows = list, texts = strings, quest = shown, history = history, content = content }
end
