local _, ns = ...
local LT = ns.LT

-- Small windows (error report, what's new, Chronicle): Blizzard's ButtonFrameTemplate without the
-- portrait, movable, closed with Escape. The template leaves a band under the title for controls
-- (tabs, buttons) and a button bar at the bottom; content goes into its Inset.

local Window = {}
LT.Window = Window

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

-- "|cffRRGGBB" for a class.
function Window.ClassColorCode(classFile)
	local color = classFile and C_ClassColor and C_ClassColor.GetClassColor(classFile)
	local r, g, b = 1, 1, 1
	if color then
		r, g, b = color:GetRGB()
	end
	return ("|cff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end
