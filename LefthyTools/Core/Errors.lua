local _, ns = ...
local LT = ns.LT
local L = ns.L

-- Error catcher: LefthyTools' own Lua errors and blocked actions are kept in LefthyToolsDB.errors,
-- across sessions, so players can copy them with /lefthy errors and send them along. Each error new
-- in a session also goes to Errors.listeners (Beacon sends it to friends who collect reports).
--
-- Every Lua error goes through Blizzard's handler (Blizzard_ScriptErrors: HandleLuaError) to
-- ScriptErrorsFrame:DisplayMessageInternal(message, messageType, stack, locals), also with "Show
-- Lua errors" off. A post-hook there sees each error with its stack without replacing the error
-- handler, which Blizzard and other addons rely on. Only errors whose message or stack mentions
-- this addon's folder are kept. Locals are left out: they can hold chat text and names.

local MAX_ERRORS = 25
local STACK_LINES = 12
local MESSAGE_TYPES = { [0] = "error", [1] = "warning" } -- ScriptErrorsFrame's message types
local issecret = LT.IsSecret

local Errors = {}
LT.Errors = Errors
-- function(entry), on the next frame: an error new this session (Beacon's Reports.lua sends it to
-- friends who collect error reports).
Errors.listeners = {}

local pending = {} -- caught before the saved variables are loaded
local list         -- LefthyToolsDB.errors, oldest first
local loggedIn, noticeShown, caughtBeforeLogin = false, false, false
local toldThisSession = {} -- message -> true

local function Tell(entry)
	if toldThisSession[entry.msg] then
		return
	end
	toldThisSession[entry.msg] = true
	C_Timer.After(0, function() -- not from inside the error handler
		for _, listener in ipairs(Errors.listeners) do
			pcall(listener, entry)
		end
	end)
end

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

---------------------------------------------------------------------------
-- What was going on: for whoever fixes it, who wasn't there. Saved with an error the first time it
-- comes in a session and sent with it, so a report can be read without asking the player. No chat
-- text, no names and no typed words: slash words only, string settings by their key only.
---------------------------------------------------------------------------

local TRAIL_KEEP = 16  -- the last things that happened
local CONTEXT_BYTES = 1000
local ADDONS_SHOWN = 30
local trail = {}

-- Something happened that may explain a later error (a window, a command, a setting, a fight).
function LT.Trail(text)
	trail[#trail + 1] = { GetTime(), text }
	if #trail > TRAIL_KEEP then
		table.remove(trail, 1)
	end
end

local function Named(frame)
	local ok, name = pcall(function() return frame:GetDebugName() end)
	return ok and type(name) == "string" and not issecret(name) and name ~= "" and name or nil
end

local function StateLine()
	local parts = { "combat " .. (InCombatLockdown() and "yes" or "no"),
		"controller UI " .. ((InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()) and "yes" or "no") }
	if IsInInstance then
		local inside, kind = IsInInstance()
		parts[#parts + 1] = "instance " .. (inside and tostring(kind) or "no")
	end
	local focus = GetMouseFoci and GetMouseFoci()
	local over = focus and focus[1] and Named(focus[1])
	if over then
		parts[#parts + 1] = "mouse over " .. over
	end
	if GetUIPanel then
		local panels = {}
		for _, area in ipairs({ "left", "center", "right", "doublewide", "fullscreen" }) do
			local panel = GetUIPanel(area)
			panels[#panels + 1] = panel and Named(panel) or nil
		end
		if panels[1] then
			parts[#parts + 1] = "panels " .. table.concat(panels, ", ")
		end
	end
	local data = ns.MirageData
	local open = {}
	for _, name in ipairs(data and data.WINDOWS or {}) do
		local frame = _G[name]
		if type(name) == "string" and name:find("^LefthyTools") and type(frame) == "table" and frame.IsShown and frame:IsShown() then
			open[#open + 1] = (name:gsub("^LefthyTools", ""):gsub("Frame$", ""))
		end
	end
	if open[1] then
		parts[#parts + 1] = "our windows " .. table.concat(open, ", ")
	end
	return "State: " .. table.concat(parts, "; ")
end

local function TrailLine()
	local now, parts = GetTime(), {}
	for i = #trail, 1, -1 do
		parts[#parts + 1] = ("-%ds %s"):format(math.floor(now - trail[i][1] + 0.5), trail[i][2])
	end
	return parts[1] and ("Before it, newest first: " .. table.concat(parts, " | ")) or nil
end

-- The modules switched off and the settings not at their default (strings: only that they're changed).
local function SetupLine()
	local off, changed = {}, {}
	for _, m in ipairs(LT.modules) do
		if not m.enabled then
			off[#off + 1] = m.key
		end
		for key, default in pairs(type(m.defaults) == "table" and m.defaults or {}) do
			local value = m.db and m.db[key]
			if value ~= default and value ~= nil and type(default) ~= "table" then
				changed[#changed + 1] = m.key .. "." .. key .. (type(value) == "string" and "" or ("=" .. tostring(value)))
			end
		end
	end
	table.sort(changed)
	return ("Modules off: %s. Settings changed: %s"):format(off[1] and table.concat(off, ", ") or "none",
		changed[1] and table.concat(changed, ", ") or "none")
end

-- The other addons loaded: whose code it may really be.
local function AddonsLine()
	local api = C_AddOns
	if not (api and api.GetNumAddOns and api.GetAddOnInfo and api.IsAddOnLoaded) then
		return nil
	end
	local names, more = {}, 0
	for i = 1, api.GetNumAddOns() do
		local name = api.GetAddOnInfo(i)
		if type(name) == "string" and not name:find("^LefthyTools") and not name:find("^Blizzard_") and api.IsAddOnLoaded(i) then
			if #names < ADDONS_SHOWN then
				names[#names + 1] = name
			else
				more = more + 1
			end
		end
	end
	return "Other addons: " .. (names[1] and table.concat(names, ", ") or "none") .. (more > 0 and (" and " .. more .. " more") or "")
end

-- All of it, as lines; each part on its own, so one failing loses only itself.
function Errors.Context()
	local lines = {}
	for _, part in ipairs({ StateLine, TrailLine, SetupLine, AddonsLine }) do
		local ok, line = pcall(part)
		if ok and line then
			lines[#lines + 1] = Plain(line)
		end
	end
	return LT.CutUTF8 and LT.CutUTF8(table.concat(lines, "\n"), CONTEXT_BYTES) or table.concat(lines, "\n")
end

-- Blizzard's panels coming and going: post-hooks only, so nothing of ours runs in their path.
if ShowUIPanel and HideUIPanel then
	hooksecurefunc("ShowUIPanel", function(frame)
		pcall(function() LT.Trail("panel " .. tostring(Named(frame))) end)
	end)
	hooksecurefunc("HideUIPanel", function(frame)
		pcall(function() LT.Trail("panel closed " .. tostring(Named(frame))) end)
	end)
end

local function Store(entry)
	for _, e in ipairs(list) do
		if e.msg == entry.msg then
			e.count, e.last, e.version = e.count + entry.count, entry.last, entry.version
			e.context = entry.context or e.context -- (the latest session's: an old error, seen again)
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
	local msg = Plain(message)
	local entry = { kind = kind, msg = msg, stack = Plain(stack or "", STACK_LINES), count = 1,
		first = now, last = now, version = LT.version,
		context = not toldThisSession[msg] and Errors.Context() or nil } -- (a repeat in a loop costs nothing)
	if list then
		Store(entry)
	else
		pending[#pending + 1] = entry
	end
	caughtBeforeLogin = caughtBeforeLogin or not loggedIn
	Notify()
	Tell(entry)
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
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ZONE_CHANGED_NEW_AREA" }) do
	events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, addon, func)
	if event == "PLAYER_ENTERING_WORLD" then
		LT.Trail(addon and "logged in" or func and "reloaded" or "loading screen")
	elseif event == "PLAYER_REGEN_DISABLED" then
		LT.Trail("combat")
	elseif event == "PLAYER_REGEN_ENABLED" then
		LT.Trail("combat over")
	elseif event == "ZONE_CHANGED_NEW_AREA" then
		LT.Trail("zone " .. tostring(GetRealZoneText and GetRealZoneText() or "?"))
	elseif addon == "LefthyTools" then
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
		if e.context then
			lines[#lines + 1] = e.context
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
