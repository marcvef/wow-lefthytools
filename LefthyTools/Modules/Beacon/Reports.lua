local _, ns = ...
local LT = ns.LT
local L = ns.L
local M = LT:GetModule("beacon")
local B = ns.Beacon

-- Error reports for whoever looks after LefthyTools. A friend who switches on "Collect my friends'
-- error reports" says so (Y2;1, with every answer and when it's switched), and LefthyTools errors
-- (LT.Errors, each one once per session) go to them by Battle.net, like everything else (Z2 parts,
-- low priority). Players can also send one by hand, in their own words: /lefthy report <what
-- happened>, with diagnostics (build, client, language, realm, faction, friends, the last links
-- they clicked and whether a window opened). Reports wait (LefthyToolsDB.reportsOut) until a
-- collector is online. Collected ones are kept (LefthyToolsDB.friendReports); /lefthy reports
-- shows them, ready to copy. Setting sendReports (on) switches sending off, collectReports (off)
-- collecting on.
--
-- Protocol: Y2;<1|0> I collect reports (or stopped); Z2;<id>;<n>;<of>;<text> part n of a report.
-- The text has no colour codes, "|" or ";", and its newlines as "^".
--
-- Cost: nothing while nothing happens; the tick looks at waiting reports at most every 2 s.

local PART_BYTES, MAX_PARTS = 180, 16
local KEEP_COLLECTED, KEEP_WAITING = 40, 10
local ASSEMBLE_WAIT = 120 -- seconds before a report with parts missing is kept as it is
local FLUSH_GAP = 2
local CLICKS = 8          -- the last links clicked, for hand-written reports

local assembling = {}     -- "<sender>:<id>" -> { sender, id, of, parts = {}, at }
local errorsIn = {}       -- errors caught this session, waiting to become reports
local clicks = {}         -- { at, link, result }
local lastFlush = -math.huge
local announced           -- what friends were last told about collecting

local function Saved(key)
	local db = LT.db
	if not db then
		return {}
	end
	db[key] = type(db[key]) == "table" and db[key] or {}
	return db[key]
end

local function Collectors()
	local list = {}
	for gameAccountID, peer in pairs(M:GetPeers()) do
		if peer.collects then
			list[#list + 1] = gameAccountID
		end
	end
	return list
end

local function NameOf(gameAccountID)
	local peer = M:GetPeers()[gameAccountID]
	if peer and peer.name then
		return peer.name
	end
	local info = C_BattleNet and C_BattleNet.GetGameAccountInfoByID and C_BattleNet.GetGameAccountInfoByID(gameAccountID)
	return info and info.characterName or ("#" .. tostring(gameAccountID))
end

---------------------------------------------------------------------------
-- What a report says
---------------------------------------------------------------------------

-- The sender's side in one line: build, client, language, realm, faction, level and class.
local function Context()
	local version, build = GetBuildInfo()
	local _, classFile = UnitClass("player")
	return ("LefthyTools %s (files %s), WoW %s.%s, %s, %s, %s, level %s %s"):format(LT.version, LT.FILES or "?",
		tostring(version), tostring(build), GetLocale(), GetRealmName() or "?", UnitFactionGroup("player") or "?",
		tostring(UnitLevel("player") or "?"), classFile or "?")
end

local function ErrorReport(entry)
	local lines = { "Error: " .. Context(), ("%s, %dx, first %s, LefthyTools %s"):format(entry.kind, entry.count or 1,
		entry.first or "?", entry.version or "?"), entry.msg }
	if entry.stack and entry.stack ~= "" then
		lines[#lines + 1] = entry.stack
	end
	return table.concat(lines, "\n")
end

-- A hand-written report: the player's words and what may help to understand them.
local function HandReport(text)
	local lines = { "Report: " .. Context(), "What happened: " .. text }
	local friends = {}
	for gameAccountID, peer in pairs(M:GetPeers()) do
		friends[#friends + 1] = ("%s (%s)"):format(NameOf(gameAccountID), peer.version or "?")
	end
	table.sort(friends)
	lines[#lines + 1] = "Beacon " .. (M.enabled and "on" or "off") .. ", friends: "
		.. (#friends > 0 and table.concat(friends, ", ") or "none")
	if #clicks > 0 then
		lines[#lines + 1] = "Last links clicked:"
		for _, click in ipairs(clicks) do
			lines[#lines + 1] = ("  %s %s -> %s"):format(click.at, click.link, click.result or "clicked")
			if click.linker then
				lines[#lines + 1] = ("    linker: %s / me: %s / the game: %s"):format(click.linker, click.me or "?", click.events or "?")
			end
		end
	end
	local errors = LT.Errors.Count()
	lines[#lines + 1] = ("Errors kept: %d (/lefthy errors)"):format(errors)
	return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

-- The text in parts small enough for one message each (UTF-8 kept whole).
local function Parts(text)
	text = text:gsub("\r", ""):gsub("\n", "^"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[|;%c]", "")
	local parts = {}
	while #text > 0 and #parts < MAX_PARTS do
		local cut = math.min(#text, PART_BYTES)
		while cut < #text and cut > 1 and text:byte(cut + 1) >= 128 and text:byte(cut + 1) < 192 do
			cut = cut - 1 -- don't split a character
		end
		parts[#parts + 1] = text:sub(1, cut)
		text = text:sub(cut + 1)
	end
	if #text > 0 then
		parts[#parts] = parts[#parts]:sub(1, PART_BYTES - 3) .. "..."
	end
	return parts
end

local function Send(text, to)
	local db = LT.db
	db.reportSeq = ((tonumber(db.reportSeq) or 0) % 9999) + 1
	local parts = Parts(text)
	for _, gameAccountID in ipairs(to) do
		for n, part in ipairs(parts) do
			B.QueueLow(gameAccountID, ("Z%s;%d;%d;%d;%s"):format(B.VERSION, db.reportSeq, n, #parts, part))
		end
	end
end

-- Waiting reports go to every collector who is online; told in chat.
local function Flush()
	local waiting = Saved("reportsOut")
	local to = Collectors()
	if #waiting == 0 or #to == 0 then
		return
	end
	for _, report in ipairs(waiting) do
		Send(report.text, to)
	end
	local names = {}
	for _, gameAccountID in ipairs(to) do
		names[#names + 1] = NameOf(gameAccountID)
	end
	M:Print(("%d report(s) sent to %s (they collect LefthyTools error reports)."):format(#waiting, table.concat(names, ", ")))
	wipe(waiting)
end

local function Keep(text)
	local waiting = Saved("reportsOut")
	waiting[#waiting + 1] = { text = text }
	while #waiting > KEEP_WAITING do
		table.remove(waiting, 1)
	end
end

-- /lefthy report <what happened>
function B.ReportCommand(text)
	text = strtrim(text or "")
	if text == "" then
		M:Print("/lefthy report <what happened> - sends what you write, with what LefthyTools knows, to friends who collect error reports.")
		return
	end
	Keep(HandReport(text))
	if not M.enabled then
		M:Print("report kept: it goes out once Beacon is on (/lefthy enable beacon) and a friend who collects reports is online.")
	elseif #Collectors() == 0 then
		M:Print("report kept: it goes out when a friend who collects error reports is online.")
	else
		Flush()
	end
end

table.insert(LT.Errors.listeners, function(entry)
	errorsIn[#errorsIn + 1] = entry
end)

---------------------------------------------------------------------------
-- Receiving (collectors)
---------------------------------------------------------------------------

-- A Z2 part (OnMessage: state only; the tick stores and tells).
function B.ReceiveReportPart(sender, id, n, of, text)
	local key = sender .. ":" .. id
	local report = assembling[key]
	if not report or report.of ~= of then
		report = { sender = sender, id = id, of = of, parts = {}, at = GetTime() }
		assembling[key] = report
	end
	report.parts[n] = text
end

local function Store(report)
	local texts = {}
	for n = 1, report.of do
		texts[n] = report.parts[n] or ("[part %d of %d missing]"):format(n, report.of)
	end
	local list = Saved("friendReports")
	list[#list + 1] = { at = date("%Y-%m-%d %H:%M"), from = NameOf(report.sender), text = (table.concat(texts):gsub("%^", "\n")) }
	while #list > KEEP_COLLECTED do
		table.remove(list, 1)
	end
	M:Print(("%s sent a LefthyTools error report: /lefthy reports shows it."):format(list[#list].from))
	if B.reportsWindow and B.reportsWindow:IsShown() then
		B.ShowReports()
	end
end

-- The text collectors copy: every report, newest first.
function B.ReportsText()
	local list = Saved("friendReports")
	if #list == 0 then
		return L["No reports from friends yet."]
	end
	local lines = {}
	for i = #list, 1, -1 do
		local report = list[i]
		lines[#lines + 1] = ("[%d] from %s, %s"):format(#list - i + 1, report.from or "?", report.at or "?")
		lines[#lines + 1] = report.text
		lines[#lines + 1] = ""
	end
	return table.concat(lines, "\n")
end

function B.ShowReports()
	local window = B.reportsWindow
	if not window then
		window = LT.Window.Create("LefthyToolsReportsFrame", L["Friends' error reports"], 620, 440)
		local hint = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		hint:SetPoint("TOPLEFT", 16, -34)
		hint:SetPoint("TOPRIGHT", -16, -34)
		hint:SetJustifyH("LEFT")
		hint:SetText(L["Click into the text, press Ctrl+A and then Ctrl+C to copy it."])
		LT.Window.AddCopyBox(window)
		LT.Window.AddButton(window, L["Clear"], function()
			wipe(Saved("friendReports"))
			B.ShowReports()
		end)
		B.reportsWindow = window
	end
	window:SetBodyText(B.ReportsText())
	window:Show()
end

---------------------------------------------------------------------------
-- The tick (Beacon.lua): collect, tell friends I collect, send what waits
---------------------------------------------------------------------------

-- With every answer to a friend (Beacon.lua): whether I collect reports.
function B.CollectorMessage()
	return M.db.collectReports and ("Y" .. B.VERSION .. ";1") or nil
end

function B.TickReports(now)
	for key, report in pairs(assembling) do
		local complete = true
		for n = 1, report.of do
			complete = complete and report.parts[n] ~= nil
		end
		if complete or now - report.at >= ASSEMBLE_WAIT then
			assembling[key] = nil
			if M.db.collectReports then
				Store(report)
			end
		end
	end
	local collect = M.db.collectReports == true
	if announced ~= collect then
		if announced ~= nil then -- (the first answers tell friends at the start)
			B.QueueToPeers(("Y%s;%d"):format(B.VERSION, collect and 1 or 0))
		end
		announced = collect
	end
	if now - lastFlush < FLUSH_GAP then
		return
	end
	lastFlush = now
	while errorsIn[1] do
		local entry = table.remove(errorsIn, 1)
		if M.db.sendReports then
			Keep(ErrorReport(entry))
		end
	end
	Flush()
end

---------------------------------------------------------------------------
-- Links clicked, for reports: which kind, and whether a window opened
--
-- A profession link (trade:<GUID>:<spell>:<skill line>) is the game engine's business: Blizzard's
-- UI only hands it to ItemRefTooltip:SetHyperlink, the client asks the server for the linker's
-- recipes, and the profession window opens when they come; if the server says no, nothing
-- happens and no Lua error is raised. So for such a click we note what might matter (the linker's
-- server id against mine, whether this client knows the linker, their realm and faction from
-- Battle.net, combat, a modifier) and listen for 3 s to what the game says (UI error and info
-- messages, system messages, the trade skill events). If nothing opened, that goes to friends who
-- collect reports by itself (once per session).
---------------------------------------------------------------------------

local WATCH_TIME = 3
local WATCH_EVENTS = { "UI_ERROR_MESSAGE", "UI_INFO_MESSAGE", "CHAT_MSG_SYSTEM", "TRADE_SKILL_SHOW",
	"TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_CLOSE" }
local issecret = issecretvalue or function() return false end
local watcher = CreateFrame("Frame")
local watching -- the click being watched: { events = { ... } }
local linkFailureSent = false

watcher:SetScript("OnEvent", function(_, event, a, b)
	if not watching or #watching.events >= 12 then
		return
	end
	local text = event == "CHAT_MSG_SYSTEM" and a or b
	if type(text) ~= "string" then
		text = nil
	elseif issecret(text) then
		text = "(secret)"
	end
	watching.events[#watching.events + 1] = event .. (text and (": " .. text:sub(1, 80)) or "")
end)

local function Opened(kind)
	if kind == "trade" or kind == "enchant" then
		local frame = ProfessionsFrame or TradeSkillFrame
		return frame and frame:IsShown() and "the profession window opened" or "nothing opened"
	elseif kind == "worldmap" then
		return C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() and "the waypoint is set" or "no waypoint"
	end
end

local function ServerID(guid)
	return type(guid) == "string" and guid:match("^Player%-(%d+)%-") or nil
end

-- What this client knows about whoever linked it (the GUID in a profession link).
local function Linker(guid)
	local mine = UnitGUID("player")
	if guid == mine then
		return "my own link"
	end
	local parts = { ("their server id %s, mine %s"):format(ServerID(guid) or "?", ServerID(mine) or "?") }
	local ok, _, _, _, _, _, name, realm = pcall(GetPlayerInfoByGUID, guid)
	if ok and type(name) == "string" and name ~= "" and not issecret(name) then
		parts[#parts + 1] = ("this client knows them (%s%s)"):format(name, (type(realm) == "string" and realm ~= "") and ("-" .. realm) or "")
	else
		parts[#parts + 1] = "this client doesn't know them"
	end
	for gameAccountID, peer in pairs(M:GetPeers()) do
		if peer.guid == guid then
			local info = C_BattleNet.GetGameAccountInfoByID(gameAccountID)
			parts[#parts + 1] = ("Beacon friend %s on %s, %s"):format(peer.name or "?", info and info.realmName or "?",
				info and info.factionName or "?")
		end
	end
	return table.concat(parts, " - ")
end

local function LinkReport(click)
	return table.concat({ "Profession link: " .. Context(),
		("Clicked %s at %s -> %s"):format(click.link, click.at, click.result or "?"),
		"Linker: " .. (click.linker or "?"),
		"Me: " .. (click.me or "?"),
		"What the game did: " .. (click.events or "nothing") }, "\n")
end

local function OnLinkClicked(link)
	if type(link) ~= "string" then
		return
	end
	local click = { at = date("%H:%M:%S"), link = link:gsub("|", ""):sub(1, 80) }
	table.insert(clicks, click)
	while #clicks > CLICKS do
		table.remove(clicks, 1)
	end
	local kind = link:match("^(%a+):")
	if kind == "worldmap" then
		C_Timer.After(2, function() click.result = Opened(kind) end)
	elseif kind == "trade" or kind == "enchant" then
		click.linker = Linker(link:match("^trade:(Player%-[%w%-]+)") or "?")
		click.me = ("%s, %s%s%s"):format(GetRealmName() or "?", UnitFactionGroup("player") or "?",
			InCombatLockdown() and ", in combat" or "", (IsModifiedClick and IsModifiedClick()) and ", a modified click" or "")
		watching = { events = {} }
		for _, event in ipairs(WATCH_EVENTS) do
			pcall(watcher.RegisterEvent, watcher, event)
		end
		local watched = watching
		C_Timer.After(WATCH_TIME, function()
			if watching == watched then
				watcher:UnregisterAllEvents()
				watching = nil
			end
			click.result = Opened(kind)
			click.events = #watched.events > 0 and table.concat(watched.events, " / ") or "nothing"
			if click.result == "nothing opened" and not linkFailureSent and M.enabled and M.db.sendReports then
				linkFailureSent = true
				Keep(LinkReport(click)) -- goes out on the tick
			end
		end)
	end
end

if type(SetItemRef) == "function" then
	hooksecurefunc("SetItemRef", function(link) pcall(OnLinkClicked, link) end)
end
