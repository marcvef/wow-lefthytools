local _, ns = ...
local LT = ns.LT

-- Small windows (error report, what's new, Chronicle): Blizzard's ButtonFrameTemplate without the
-- portrait, movable, closed with Escape. The template leaves a band under the title for controls
-- (tabs, buttons) and a button bar at the bottom; content goes into its Inset.

local Window = {}
LT.Window = Window

-- A window of ours counts as "using the interface", like Blizzard's (ns.MirageData.WINDOWS): a
-- cinematic flight pauses for it, Mirage keeps the interface up and the AFK screen stays away.
function Window.Register(name)
	local data = ns.MirageData
	if data and data.WINDOWS then
		table.insert(data.WINDOWS, name)
	end
end

function Window.Create(name, title, width, height)
	local frame = CreateFrame("Frame", name, UIParent, "ButtonFrameTemplate")
	if ButtonFrameTemplate_HidePortrait then
		ButtonFrameTemplate_HidePortrait(frame)
	end
	frame:SetSize(width, height)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	if frame.SetTitle then
		frame:SetTitle(title)
	end
	table.insert(UISpecialFrames, name) -- Escape closes it
	Window.Register(name)
	frame:Hide()
	return frame
end

-- A scrolling area filling the window's inset, scrolling `child` (default: a new plain frame).
function Window.AddScroll(frame, child)
	local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", frame.Inset, "BOTTOMRIGHT", -28, 6)
	child = child or CreateFrame("Frame", nil, scroll)
	child:SetSize(frame:GetWidth() - 60, 10)
	scroll:SetScrollChild(child)
	return scroll, child
end

-- Read-only text in a scroll area. SetBodyText resizes the content so the scroll bar fits.
function Window.AddText(frame)
	local scroll, content = Window.AddScroll(frame)
	local text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("TOPLEFT")
	text:SetWidth(content:GetWidth())
	text:SetJustifyH("LEFT")
	text:SetJustifyV("TOP")
	text:SetSpacing(2)
	frame.Scroll, frame.Content, frame.Text = scroll, content, text
	-- keepScroll: a refresh of the same page, so the reader's place stays.
	function frame.SetBodyText(_, value, keepScroll)
		text:SetText(value)
		content:SetHeight(math.max(text:GetStringHeight() + 4, 10))
		if not keepScroll then
			scroll:SetVerticalScroll(0)
		end
	end
	return text
end

-- Selectable text for copying (Ctrl+C): a multi-line edit box that puts back its text if typed in.
-- It is the scroll child itself: a multi-line edit box grows with its text, like the one in
-- Blizzard's script error window.
function Window.AddCopyBox(frame)
	local box = CreateFrame("EditBox", nil, frame)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetFontObject("ChatFontNormal")
	local scroll = Window.AddScroll(frame, box)
	box:SetScript("OnEscapePressed", function() frame:Hide() end)
	box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	box:SetScript("OnTextChanged", function(self, userInput)
		if userInput and self.fixedText then
			self:SetText(self.fixedText) -- read-only
			self:HighlightText()
		end
	end)
	frame.Scroll, frame.Box = scroll, box
	function frame.SetBodyText(_, value)
		box.fixedText = value
		box:SetText(value)
		scroll:SetVerticalScroll(0)
	end
	return box
end

function Window.AddButton(frame, label, onClick, anchor)
	local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	button:SetSize(120, 22)
	button:SetText(label)
	button:SetPoint(unpack(anchor or { "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 3 }))
	button:SetScript("OnClick", onClick)
	return button
end

-- A list of our own that pops up from a frame (a dropdown's button, a minimap button). Not
-- Blizzard's menu (Blizzard_Menu): one opened from addon code runs tainted, and in gamepad mode its
-- MenuProxy.OnShow makes the focus manager (FrameControlsManager) store tainted state; a protected
-- click through it later, like a role check's Accept, is then blocked (ADDON_ACTION_BLOCKED).
-- entries() returns the list when it opens: { title = "..." } | { divider = true } |
-- { note = "..." } (grey, not clickable) | { text, value, selected }; onPick(value) runs when an
-- entry is clicked. A click anywhere else closes it (GLOBAL_MOUSE_DOWN, listened to only while
-- it's open). The caller anchors it (list:SetPoint) and opens it with list:Toggle() or list:Open().
local PICKER_ROW = 20
local PICKER_ROWS = 18 -- a longer list goes on in another column, so every row stays on screen
local openLists = {}   -- lists shown now (Window.PopupOpenIn)

function Window.AnyPopupOpen()
	return next(openLists) ~= nil
end

-- A list is open on frame or one of its children (Mirage: a minimap button's list keeps the minimap
-- in view: the list reaches past the minimap's edge).
function Window.PopupOpenIn(frame)
	for list in pairs(openLists) do
		local parent = list:GetParent()
		while parent do
			if parent == frame then
				return true
			end
			parent = parent:GetParent()
		end
	end
	return false
end

function Window.PopupList(owner, width, entries, onPick)
	local list = CreateFrame("Frame", nil, owner)
	list:SetFrameStrata("FULLSCREEN_DIALOG")
	list:SetWidth(width)
	list:EnableMouse(true)
	list:Hide()
	local listBackground = list:CreateTexture(nil, "BACKGROUND")
	listBackground:SetAllPoints()
	listBackground:SetColorTexture(0.05, 0.05, 0.05, 0.95)
	local listEdge = list:CreateTexture(nil, "BORDER")
	listEdge:SetPoint("TOPLEFT")
	listEdge:SetPoint("TOPRIGHT")
	listEdge:SetHeight(1)
	listEdge:SetColorTexture(1, 0.82, 0, 0.5)
	list.rows, list.count, list.builds = {}, 0, 0

	local function Row(i)
		local row = list.rows[i]
		if not row then
			row = CreateFrame("Button", nil, list)
			row:SetSize(width - 8, PICKER_ROW)
			row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
			row.Check = row:CreateTexture(nil, "ARTWORK")
			row.Check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
			row.Check:SetSize(16, 16)
			row.Check:SetPoint("LEFT", 0, 0)
			row.Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			row.Text:SetPoint("LEFT", 18, 0)
			row.Text:SetPoint("RIGHT")
			row.Text:SetJustifyH("LEFT")
			row.Text:SetWordWrap(false)
			row.Line = row:CreateTexture(nil, "ARTWORK")
			row.Line:SetColorTexture(1, 1, 1, 0.15)
			row.Line:SetHeight(1)
			row.Line:SetPoint("LEFT", 4, 0)
			row.Line:SetPoint("RIGHT", -4, 0)
			row:SetScript("OnClick", function(self)
				if self.kind == "entry" then
					list:Hide()
					onPick(self.value)
				end
			end)
			list.rows[i] = row
		end
		return row
	end

	function list:Open()
		local items = entries()
		local columns = math.max(1, math.ceil(#items / PICKER_ROWS))
		local perColumn = math.max(1, math.ceil(#items / columns))
		for i, item in ipairs(items) do
			local row = Row(i)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", list, "TOPLEFT", 4 + math.floor((i - 1) / perColumn) * width,
				-4 - ((i - 1) % perColumn) * PICKER_ROW)
			row.kind = item.title and "title" or item.divider and "divider" or item.note and "note" or "entry"
			row.value = item.value
			row.Text:SetText(item.title and ("|cffffd200" .. item.title .. "|r") or item.note and ("|cff999999" .. item.note .. "|r")
				or item.text or "")
			row.Line:SetShown(row.kind == "divider")
			row.Check:SetShown(item.selected == true)
			row:EnableMouse(row.kind == "entry")
			row:Show()
		end
		for i = #items + 1, #list.rows do
			list.rows[i]:Hide()
		end
		list.count, list.builds = #items, list.builds + 1
		list:SetSize(width * columns, perColumn * PICKER_ROW + 8)
		list:Show()
	end

	function list:Toggle()
		if self:IsShown() then
			self:Hide()
		else
			self:Open()
		end
	end

	list:SetScript("OnShow", function(self)
		self:RegisterEvent("GLOBAL_MOUSE_DOWN")
		openLists[self] = true
	end)
	list:SetScript("OnHide", function(self)
		self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
		openLists[self] = nil
	end)
	-- Its owner hiding (its window closing with Escape) closes it too, or it would come back open.
	owner:HookScript("OnHide", function() list:Hide() end)
	list:SetScript("OnEvent", function(self)
		if not (self:IsMouseOver() or owner:IsMouseOver()) then
			self:Hide() -- a click somewhere else
		end
	end)
	return list
end

-- A dropdown of our own: a button showing the pick, and a PopupList under it.
function Window.AddPicker(parent, width, entries, onPick)
	local picker = CreateFrame("Button", nil, parent)
	picker:SetSize(width, 24)
	local background = picker:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0, 0, 0, 0.55)
	local edge = picker:CreateTexture(nil, "BORDER")
	edge:SetPoint("BOTTOMLEFT")
	edge:SetPoint("BOTTOMRIGHT")
	edge:SetHeight(1)
	edge:SetColorTexture(1, 0.82, 0, 0.5)
	picker:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	picker.Label = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	picker.Label:SetPoint("LEFT", 8, 0)
	picker.Label:SetPoint("RIGHT", -24, 0)
	picker.Label:SetJustifyH("LEFT")
	picker.Label:SetWordWrap(false)
	local arrow = picker:CreateTexture(nil, "ARTWORK")
	arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
	arrow:SetSize(22, 22)
	arrow:SetPoint("RIGHT", 0, 0)

	local list = Window.PopupList(picker, width, entries, onPick)
	list:SetPoint("TOPLEFT", picker, "BOTTOMLEFT", 0, -2)
	picker.List = list

	function picker:Open()
		list:Open()
	end

	function picker:SetLabel(text)
		self.Label:SetText(text)
	end

	picker:SetScript("OnClick", function() list:Toggle() end)
	return picker
end

-- A round button on the minimap's edge in the usual addon look (tracking border, dark background,
-- an icon), a child of the Minimap (it hides and fades with it). Dragging moves it along the edge;
-- the angle (degrees, 0 = right, counter-clockwise) is kept in db[angleKey]. options = { icon,
-- db, angleKey, angle (default), onClick(self, mouseButton), onEnter(self) }. An OnUpdate runs
-- only while dragging. button:Place() puts it where its angle says (square minimaps: on the edge).
local atan2 = math.atan2 or math.atan -- WoW's Lua 5.1 / the tests' Lua 5.3

function Window.MinimapButton(name, options)
	local button = CreateFrame("Button", name, Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetSize(20, 20)
	background:SetPoint("TOPLEFT", 7, -5)
	button.Icon = button:CreateTexture(nil, "ARTWORK")
	button.Icon:SetTexture(options.icon)
	button.Icon:SetSize(17, 17)
	button.Icon:SetPoint("TOPLEFT", 7, -6)
	button.Icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	function button:Place()
		local angle = math.rad(options.db[options.angleKey] or options.angle or 210)
		local x, y = math.cos(angle), math.sin(angle)
		if GetMinimapShape and GetMinimapShape() == "SQUARE" then
			local edge = math.max(math.abs(x), math.abs(y))
			x, y = x / edge, y / edge -- onto the square's edge
		end
		local radius = Minimap:GetWidth() / 2 + 5
		self:ClearAllPoints()
		self:SetPoint("CENTER", Minimap, "CENTER", x * radius, y * radius)
	end

	-- Degrees from the minimap's centre to the cursor.
	local function OnDragUpdate(self)
		local mx, my = Minimap:GetCenter()
		if not mx then
			return
		end
		local scale = Minimap:GetEffectiveScale()
		local cx, cy = GetCursorPosition()
		options.db[options.angleKey] = math.floor(math.deg(atan2(cy / scale - my, cx / scale - mx)) % 360 + 0.5)
		self:Place()
	end

	local function OnLeave(self)
		if GameTooltip:IsOwned(self) then
			GameTooltip:Hide()
		end
	end
	button:SetScript("OnEnter", options.onEnter)
	button:SetScript("OnLeave", OnLeave)
	button:SetScript("OnClick", function(self, mouseButton)
		OnLeave(self)
		options.onClick(self, mouseButton)
	end)
	button:SetScript("OnDragStart", function(self)
		OnLeave(self)
		self:SetScript("OnUpdate", OnDragUpdate)
	end)
	local function StopDrag(self)
		self:SetScript("OnUpdate", nil)
	end
	button:SetScript("OnDragStop", StopDrag)
	button:SetScript("OnHide", StopDrag) -- hidden mid-drag (Mirage, the minimap key): no OnDragStop may come
	return button
end

-- "|cffRRGGBB" for a class.
function Window.ClassColorCode(classFile)
	local color = classFile and C_ClassColor and C_ClassColor.GetClassColor(classFile)
	local r, g, b = 1, 1, 1
	if color then
		r, g, b = color:GetRGB()
	end
	return ("|cff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end
