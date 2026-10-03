local _, ns = ...
local LT = ns.LT
local L = ns.L

-- Error catcher: LefthyTools' own Lua errors and blocked actions are kept in LefthyToolsDB.errors,
-- across sessions, so players can copy them with /lefthy errors and send them along.
--
-- Every Lua error goes through Blizzard's handler (Blizzard_ScriptErrors: HandleLuaError) to
-- ScriptErrorsFrame:DisplayMessageInternal(message, messageType, stack, locals), also with "Show
-- Lua errors" off. A post-hook there sees each error with its stack without replacing the error
-- handler, which Blizzard and other addons rely on. Only errors whose message or stack mentions
-- this addon's folder are kept. Locals are left out: they can hold chat text and names.

local MAX_ERRORS = 25
local STACK_LINES = 12
local MESSAGE_TYPES = { [0] = "error", [1] = "warning" } -- ScriptErrorsFrame's message types
local issecret = issecretvalue or function() return false end

local Errors = {}
LT.Errors = Errors

local pending = {} -- caught before the saved variables are loaded
local list         -- LefthyToolsDB.errors, oldest first
local loggedIn, noticeShown, caughtBeforeLogin = false, false, false

local function IsOurs(text)
	return text:find("AddOns[/\\]LefthyTools[/\\]") ~= nil
end

-- Plain text: no colour codes or |K strings, at most STACK_LINES lines.
local function Plain(text, maxLines)
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|[kK]", "")
	if not maxLines then
		return text
	end
	local lines = {}
	for line in text:gmatch("[^\n]+") do
		if #lines == maxLines then
			lines[#lines + 1] = "..."
			break
		end
		lines[#lines + 1] = line
	end
	return table.concat(lines, "\n")
end

local function Notify()
	if noticeShown or not loggedIn then
		return
	end
	noticeShown = true
	-- Not from inside the error handler.
	C_Timer.After(0, function()
		LT.Print("caught an error in LefthyTools. Type /lefthy errors to see it and copy it.")
	end)
end

local function Store(entry)
	for _, e in ipairs(list) do
		if e.msg == entry.msg then
			e.count, e.last, e.version = e.count + entry.count, entry.last, entry.version
			return
		end
	end
	list[#list + 1] = entry
	while #list > MAX_ERRORS do
		table.remove(list, 1)
	end
end

function Errors.Add(kind, message, stack)
	local now = date("%Y-%m-%d %H:%M:%S")
	local entry = { kind = kind, msg = Plain(message), stack = Plain(stack or "", STACK_LINES), count = 1,
		first = now, last = now, version = LT.version }
	if list then
		Store(entry)
	else
		pending[#pending + 1] = entry
	end
	caughtBeforeLogin = caughtBeforeLogin or not loggedIn
	Notify()
end

local function OnDisplayMessage(_, message, messageType, stack)
	local kind = MESSAGE_TYPES[messageType]
	if not kind or type(message) ~= "string" or issecret(message) then
		return
	end
	if type(stack) ~= "string" or issecret(stack) then
		stack = ""
	end
	if IsOurs(message) or IsOurs(stack) then
		Errors.Add(kind, message, stack)
	end
end

if ScriptErrorsFrame and ScriptErrorsFrame.DisplayMessageInternal then
	hooksecurefunc(ScriptErrorsFrame, "DisplayMessageInternal", function(...)
		pcall(OnDisplayMessage, ...) -- an error in here must not cause another one
	end)
end

-- Protected calls the game refused; the event names the addon whose code made them.
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
events:SetScript("OnEvent", function(_, event, addon, func)
	if addon == "LefthyTools" then
		Errors.Add("blocked", ("%s: %s()"):format(event, tostring(func)))
	end
end)

table.insert(LT.onLoad, function(db)
	db.errors = type(db.errors) == "table" and db.errors or {}
	list = db.errors
	for _, entry in ipairs(pending) do
		Store(entry)
	end
	wipe(pending)
end)

table.insert(LT.onLogin, function()
	loggedIn = true
	if caughtBeforeLogin then
		Notify() -- an error while loading: tell now that the chat is there
	end
end)

function Errors.Count()
	return list and #list or 0
end

function Errors.Clear()
	if list then
		wipe(list)
	end
	if Errors.window and Errors.window:IsShown() then
		Errors.window:SetBodyText(Errors.Report())
	end
end

-- The text players copy: the build, the client and every kept error, newest first.
function Errors.Report()
	local version, build, _, interface = GetBuildInfo()
	local lines = {
		("LefthyTools %s | WoW %s.%s (%s) | %s | %s"):format(LT.version, tostring(version), tostring(build),
			tostring(interface), GetLocale(), date("%Y-%m-%d %H:%M")),
		"",
	}
	if Errors.Count() == 0 then
		lines[#lines + 1] = "No errors."
	end
	for i = Errors.Count(), 1, -1 do
		local e = list[i]
		lines[#lines + 1] = ("[%d] %s, %dx, first %s, last %s, LefthyTools %s"):format(Errors.Count() - i + 1,
			e.kind, e.count, e.first, e.last, e.version)
		lines[#lines + 1] = e.msg
		if e.stack ~= "" then
			lines[#lines + 1] = e.stack
		end
		lines[#lines + 1] = ""
	end
	return table.concat(lines, "\n")
end

function Errors.Show()
	local window = Errors.window
	if not window then
		window = LT.Window.Create("LefthyToolsErrorsFrame", L["LefthyTools errors"], 620, 440)
		local hint = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		hint:SetPoint("TOPLEFT", 16, -34)
		hint:SetPoint("TOPRIGHT", -16, -34)
		hint:SetJustifyH("LEFT")
		hint:SetText(L["Click into the text, press Ctrl+A and then Ctrl+C to copy it, and send it to whoever gave you LefthyTools."])
		LT.Window.AddCopyBox(window)
		LT.Window.AddButton(window, L["Clear"], Errors.Clear)
		Errors.window = window
	end
	window:SetBodyText(Errors.Report())
	window:Show()
end

-- /lefthy errors [clear]
function Errors.Command(arg)
	if (arg or ""):lower() == "clear" then
		Errors.Clear()
		LT.Print("errors cleared.")
	else
		Errors.Show()
	end
end
