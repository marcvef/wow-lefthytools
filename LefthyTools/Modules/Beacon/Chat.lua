local _, ns = ...
local LT = ns.LT
local L = ns.L
local M = LT:GetModule("beacon")
local B = ns.Beacon

-- LTC (LefthyTools chat, once "Lefthy chat"): a chat for your Battle.net friends with LefthyTools,
-- like guild or party chat. /ltc or /l <text> sends a line (M2;<text>), and every friend's chat
-- window shows "[LTC] [Anna]: text" (older builds: "[Lefthy]"; only the name changed).
-- Announcements (/la or /lefthy announce <text>, A2;<text>) go to the middle of their screens instead, in
-- the notice stack of shared items (Items.lua: B.ShowAnnouncement), with the whisper sound. Both
-- also come as subtitles on a cinematic flight. Settings lefthyChat and announcements switch
-- sending and showing. The text goes through B.Clean (no colour codes, separators or escapes), so
-- item links travel as {item:<numbers>} (B.ItemString: only the numeric fields) and each client
-- builds the link again in its own language (B.WithLink). Map pins, professions, spells, quests,
-- achievements and the other kinds players link (LINK_KINDS) travel as
-- {<type>:<data>[<text>]<colour>} (the text in the sender's language) and become clickable links
-- again, in their own colour; any other link keeps its "[text]".
--
-- Which chat tabs show its lines is per character (LefthyToolsDB.ltcTabs[GUID] = { [window] = true };
-- none chosen: the main window, as ever). A checkbox of ours on Blizzard's Chat Settings page, for the
-- tab being set up: it can't be a row of theirs (see "Sticky /ltc" below), and a real channel would
-- take a numbered slot, could be joined by anyone and wouldn't reach other realms. A chosen tab out
-- of sight flashes. /lefthy beacon ltctab does the same for the tab in front. Its colour: a setting.
--
-- Friends on older builds get what theirs understands (LinkLevel, from their version): links as
-- tokens only where their build turns them back into links, everything else as "[text]", the way
-- it reached them before.
--
-- A line with my character's name or my BattleTag's name in it stands out (setting
-- lefthyChatMentions): the name in white, the game's taskbar icon and LTC's tab out of sight flash,
-- and LTC's sound plays. Lines a friend missed while offline: ChatMissed.lua; /ltc who <text>:
-- ChatCalls.lua. Both speak Beacon's B family (B2;b<word>), only to builds from LTC_SINCE on.

local TEXT_BYTES = 200
B.LTC_TEXT_BYTES = TEXT_BYTES
-- The first build that reads LTC's B2;b words (missed lines, who's in): older builds get none of them.
local LTC_SINCE = "0.7.0-39-g0000000"
local DEFAULT_COLOUR = "ffb84d"
-- The colour of LTC: "|cffrrggbb".
local function ChatColour()
	local hex = M.db and M.db.lefthyChatColour
	return "|cff" .. (type(hex) == "string" and hex:match("^%x%x%x%x%x%x$") and hex or DEFAULT_COLOUR)
end
-- Friends take 5 lines per 5 s and an announcement per 3 s from me (Beacon's CHAT_LIMIT and
-- ANNOUNCE_GAP); mine stay under that, with a second to spare for the way there.
local SEND_LIMIT = { chat = 5, announce = 1 } -- at most this many
local SEND_WINDOW = { chat = 6, announce = 4 } -- in any this many seconds
local sentAt = { chat = {}, announce = {} } -- my last ones, oldest first
local CHAT_SOUND = SOUNDKIT and SOUNDKIT.IG_CHAT_SCROLL_UP or 826 -- a very soft tick (setting lefthyChatSound)
-- What a friend's line can play (setting lefthyChatSoundKit; the game's own sounds, SoundKitConstants).
local CHAT_SOUNDS = {
	{ 826, L["Soft tick"] },            -- IG_CHAT_SCROLL_UP
	{ 3081, L["Whisper"] },             -- TELL_MESSAGE
	{ 18019, L["Battle.net message"] }, -- UI_BNET_TOAST
	{ 46893, L["Gentle chime"] },       -- as for a level-up (Ding.lua)
}
B.LTCSounds = CHAT_SOUNDS
local lastSoundKit
local SOUND_GAP = 1.5 -- a burst of lines ticks once
local lastSound, lastMention = -math.huge, -math.huge
local MENTION = "|cffffffff" -- my name in a friend's line
local MENTION_BYTES = 3 -- names shorter than this aren't looked for (they'd be in every other word)

-- The kinds of links that travel besides items (what players link in chat), with the colour the
-- game gives them for a link that comes without one. Their data may only hold these characters
-- (GUIDs, numbers, a profession's base64), their text no brackets, braces or escapes.
local LINK_KINDS = {
	worldmap = "ffffff00", trade = "ffffd000", enchant = "ffffd000", spell = "ff71d5ff", talent = "ff71d5ff",
	mount = "ff71d5ff", quest = "ffffff00", achievement = "ffffff00", journal = "ff66bbff", currency = "ffffffff",
	battlepet = "ff0070dd", battlePetAbil = "ff4e96f7", transmogappearance = "ffff80ff", transmogset = "ffff80ff",
	transmogillusion = "ffff80ff", instancelock = "ffff8000", keystone = "ffa335ee", dungeonScore = "ffffffff",
	worldquest = "ffffd100", eventpoi = "ffffd100", calendarEvent = "ffffd100", talentbuild = "ffffd100",
}
local LINK_DATA = "[%w:%-_%.%+/=]"
local LINK_TOKEN = "{(%a+)(:" .. LINK_DATA .. "*)%[([^%[%]{}]*)%](%x*)}"
-- A map pin's text has the game's pin icon in it; each client puts its own back (MAP_PIN_HYPERLINK).
local PIN_ICON = "|A:Waypoint-MapPin-ChatIcon:13:13:0:0|a "

-- What a build understands of the links in a line: 4 every kind above with its colour (0.5.0-16
-- on), 3 the kinds of 0.5.0-15 without colour, 2 only items (0.5.0-10 on), 1 none (older, or a
-- friend whose version hasn't arrived yet): links as their "[text]". A 0.5.0 build without its
-- commit count (0.5.0-g1a2b3c4: the updater couldn't ask GitHub) counts as new: it's a download
-- of the latest, and friends update.
local FULL = 4
local LINK_BUILDS = { { "0.5.0-16-g5d0608d", 4 }, { "0.5.0-15-g4322f60", 3 }, { "0.5.0-10-gbb4ebdb", 2 } }
local KINDS_15 = { trade = true, enchant = true, spell = true, talent = true, mount = true, quest = true,
	achievement = true, journal = true, currency = true }

local function LinkLevel(version)
	for _, build in ipairs(LINK_BUILDS) do
		local order = version and LT.CompareVersions(version, build[1])
		if order and order >= 0 then
			return build[2]
		elseif order == nil and LT.ParseVersion(version) then
			return FULL -- (the same base, commit count unknown)
		end
	end
	return 1
end
B.LTCLinkLevel, B.LTC_FULL = LinkLevel, FULL

-- Does their build read LTC's B2;b words? A build that doesn't say, or one without its commit count
-- (0.7.0, 0.7.0-g1a2b3c4), counts as older: it gets none.
function B.ReadsLTC(peer)
	if not (peer and peer.version) then
		return false
	end
	if peer.ltcBuild ~= peer.version then
		peer.ltcBuild = peer.version
		peer.readsLTC = (LT.CompareVersions(peer.version, LTC_SINCE) or -1) >= 0
	end
	return peer.readsLTC
end

local function Token(level, colour, data, shown)
	local kind = data:match("^(%a+):")
	local label = (shown:match("^%[(.*)%]$") or shown):gsub("|T.-|t", ""):gsub("|A.-|a", "")
	label = strtrim((label:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", "")))
	if kind == "item" and level >= 2 then
		local itemString = B.ItemString and B.ItemString("|H" .. data .. "|h")
		return itemString and ("{item:" .. itemString:gsub(":+$", "") .. "}") or ""
	end
	if kind and LINK_KINDS[kind] and data:find("^" .. LINK_DATA .. "+$") and not label:find("[%[%]{}|]")
		and (level >= 4 or (level == 3 and KINDS_15[kind])) then
		return "{" .. data .. "[" .. label .. "]" .. ((level >= 4 and colour) and colour:sub(3) or "") .. "}"
	end
	return "[" .. label .. "]"
end

-- Before sending: item links become {item:12345:...} (trailing empty fields dropped: the item is
-- the same), the kinds above {trade:...[Tailoring]ffd000}, any other link its text; colour codes,
-- textures and atlases go. level: what the receiving build understands (LinkLevel).
local function PackLinks(text, level)
	text = text:gsub("|c(%x%x%x%x%x%x%x%x)|H([^|]*)|h(.-)|h|r", function(colour, data, shown)
		return Token(level, colour, data, shown)
	end)
	text = text:gsub("|H([^|]*)|h(.-)|h", function(data, shown) return Token(level, nil, data, shown) end)
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", "")
	return (text:gsub("|T.-|t", ""):gsub("|A.-|a", ""))
end

-- {trade:...[Tailoring]ffd000} back into a clickable link.
local function Relink(text)
	return (text:gsub(LINK_TOKEN, function(kind, data, label, colour)
		if not LINK_KINDS[kind] then
			return nil
		end
		colour = #colour == 6 and ("ff" .. colour) or LINK_KINDS[kind]
		if kind == "worldmap" then
			label = MAP_PIN_HYPERLINK or (PIN_ICON .. label)
		end
		return "|c" .. colour .. "|H" .. kind .. data .. "|h[" .. label .. "]|h|r"
	end))
end

-- After receiving: the tokens back into links; items from this client's item cache (unknown
-- items are asked for first, so callback may come a moment later).
local function UnpackLinks(text, callback, wait)
	text = Relink(text)
	local wanted = {}
	for itemString in text:gmatch("{item:([%d:%-]+)}") do
		wanted[#wanted + 1] = itemString
	end
	if #wanted == 0 or not B.WithLink then
		callback(text)
		return
	end
	local links, pending, done = {}, #wanted, false
	local function Finish()
		if not done then
			done = true
			callback((text:gsub("{item:([%d:%-]+)}", function(s) return links[s] or "[?]" end)))
		end
	end
	for _, itemString in ipairs(wanted) do
		B.WithLink(itemString, function(link)
			links[itemString] = link or false
			pending = pending - 1
			if pending == 0 then
				Finish()
			end
		end)
	end
	if wait and not done then
		C_Timer.After(wait, Finish) -- (an item that never loads: "[?]")
	end
end

-- Friends' lines in the order they came, though an item in one may have to load first: the
-- lines after it wait (at most LOAD_WAIT seconds).
local LOAD_WAIT = 3
local arriving = {} -- { show, shown } oldest first

local function InOrder(text, show)
	local entry = { show = show }
	arriving[#arriving + 1] = entry
	UnpackLinks(text, function(shown)
		entry.shown = shown
		while arriving[1] and arriving[1].shown do
			local first = table.remove(arriving, 1)
			first.show(first.shown)
		end
	end, LOAD_WAIT)
end

-- "missed, 14:05" (or "missed, yesterday 23:50"): when a line I missed was written.
local function MissedNote(t)
	local clock = date("%H:%M", t)
	if date("%Y%m%d", t) ~= date("%Y%m%d") then
		clock = L["yesterday %s"]:format(clock)
	end
	return L["missed, %s"]:format(clock)
end

-- "[LTC] [Anna]: text", the name in its class colour; a line I missed: "[LTC] (missed, 14:05) [Anna]: text".
local function ChatLine(name, classFile, text, missedAt)
	local colour = ChatColour()
	local note = missedAt and ("|cffa0a0a0(" .. MissedNote(missedAt) .. ")|r" .. colour .. " ") or ""
	return ("%s[LTC] %s[|r%s%s]: %s|r"):format(colour, note, B.ColouredName(name, classFile), colour, text)
end

-- A line of LTC's own, not a friend's: "[LTC] text" (a call's tally, an answer given).
function B.LTCNoteLine(text)
	return ChatColour() .. "[LTC] " .. text .. "|r"
end

-- The names a friend's line may mention me by, in lower case: my character's first name and my
-- BattleTag's name ("Me" of "Me#1234"), each MENTION_BYTES long at least.
local function MyNames()
	local names = {}
	local first = LT.Names.First(LT.Value(UnitName, "player"))
	local tag = BNGetInfo and select(3, pcall(BNGetInfo)) -- (ok, presence ID, BattleTag)
	tag = LT.Readable(tag) and type(tag) == "string" and tag:match("^([^#]+)") or nil
	if first and #first >= MENTION_BYTES then
		names[#names + 1] = first:lower()
	end
	if tag and #tag >= MENTION_BYTES and tag:lower() ~= names[1] then
		names[#names + 1] = tag:lower()
	end
	return names
end

-- A letter or digit (UTF-8's bytes count as letters): what a name mustn't touch to be a word of its own.
local function IsLetter(byte)
	return byte ~= nil and (byte >= 128 or (byte >= 48 and byte <= 57) or (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122))
end

-- One piece of a line outside its links: my names in it in MENTION (then the line's colour again).
local function MarkNames(part, names, colour)
	local lower, out, pos, found = part:lower(), {}, 1, false
	while true do
		local first, last
		for _, name in ipairs(names) do
			local from = pos
			while true do
				local i, j = lower:find(name, from, true)
				if not i then
					break
				elseif not IsLetter(lower:byte(i - 1)) and not IsLetter(lower:byte(j + 1)) then
					if not first or i < first then
						first, last = i, j
					end
					break
				end
				from = i + 1
			end
		end
		if not first then
			break
		end
		out[#out + 1] = part:sub(pos, first - 1) .. MENTION .. part:sub(first, last) .. "|r" .. colour
		pos, found = last + 1, true
	end
	out[#out + 1] = part:sub(pos)
	return table.concat(out), found
end

-- A friend's line as shown: my names stand out, links stay as they are. Second value: it mentions me.
local function Highlight(text)
	local names = MyNames()
	if #names == 0 then
		return text, false
	end
	local colour, out, pos, found = ChatColour(), {}, 1, false
	while true do
		local i, j = text:find("|H[^|]*|h.-|h", pos)
		local part, mentioned = MarkNames(text:sub(pos, i and i - 1 or -1), names, colour)
		out[#out + 1] = part
		found = found or mentioned
		if not i then
			break
		end
		out[#out + 1] = text:sub(i, j)
		pos = j + 1
	end
	return table.concat(out), found
end
B.LTCHighlight = Highlight

-- This character's chosen tabs: { [window] = true }, nil if it can't be told.
local function ChosenTabs(create)
	local guid = LT.Value(UnitGUID, "player")
	if not (guid and LT.db) then
		return nil
	end
	local all = type(LT.db.ltcTabs) == "table" and LT.db.ltcTabs or (create and {}) or nil
	if not all then
		return nil
	end
	LT.db.ltcTabs = all
	if create and type(all[guid]) ~= "table" then
		all[guid] = {}
	end
	return type(all[guid]) == "table" and all[guid] or nil
end

local function ChatWindow(window)
	local frame = _G["ChatFrame" .. window]
	return frame and frame.AddMessage and frame or nil
end

-- A tab that can show LTC: one of the player's windows, not the combat log.
local function UsableTab(frame)
	local window = frame and frame.GetID and frame:GetID()
	if type(window) ~= "number" or window < 1 or window > (NUM_CHAT_WINDOWS or 10) or frame == COMBATLOG then
		return nil
	end
	return window
end

local function MainWindow()
	return UsableTab(DEFAULT_CHAT_FRAME) or 1
end

local function TabChosen(window)
	local tabs = ChosenTabs()
	if tabs and next(tabs) then
		return tabs[window] == true
	end
	return window == MainWindow()
end

-- A tab out of sight flashes, as for any chat line (Blizzard's function; its failing must not lose the line).
local function Flash(frame)
	if frame.IsShown and not frame:IsShown() and FCF_StartAlertFlash then
		pcall(FCF_StartAlertFlash, frame)
	end
end

-- A line of LTC, in the tabs chosen (a chosen tab out of sight flashes); none chosen: the main window,
-- which flashes too for a line that mentions me (alert). Returns the windows it went to (a call's
-- tally is redrawn there).
local function ShowInChat(line, alert)
	local frames = {}
	for window in pairs(ChosenTabs() or {}) do
		local frame = ChatWindow(window)
		if frame then
			frame:AddMessage(line)
			frames[#frames + 1] = frame
			Flash(frame)
		end
	end
	if not frames[1] then
		print(line)
		frames[1] = ChatWindow(MainWindow())
		if alert and frames[1] then
			Flash(frames[1])
		end
	end
	return frames
end
B.LTCShowInChat = ShowInChat

-- One tab switched. Nothing left: the main window again (a line is never shown nowhere).
local function SetTab(window, on)
	local tabs = ChosenTabs(true)
	if not tabs then
		return
	end
	if not next(tabs) then
		tabs[MainWindow()] = true -- (it was the default: it stays until unticked)
	end
	tabs[window] = on and true or nil
end

-- The tab in front, for Blizzard's settings and the command.
local function CurrentTab()
	local frame = FCF_GetCurrentChatFrame and FCF_GetCurrentChatFrame() or SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
	return UsableTab(frame), frame
end

function B.LTCTabCommand()
	local window, frame = CurrentTab()
	if not window then
		M:Print(L["LTC can't show in this tab."])
		return
	end
	SetTab(window, not TabChosen(window))
	local name = frame.name or (GetChatWindowInfo and GetChatWindowInfo(window)) or tostring(window)
	M:Print((TabChosen(window) and L["LTC now shows in %s."] or L["LTC no longer shows in %s."]):format(tostring(name)))
end

-- The checkbox on Blizzard's Chat Settings page: a frame of ours, parented there, with nothing of
-- ours in Blizzard's lists. The band over its list, at the right, stays free.
function B.BuildLTCTabBox()
	if B.ltcTabBox or not (ChatConfigChatSettings and ChatConfigBackgroundFrame) then
		return B.ltcTabBox
	end
	local box = CreateFrame("CheckButton", nil, ChatConfigChatSettings, "UICheckButtonTemplate")
	B.ltcTabBox = box
	box:SetSize(24, 24)
	box:SetPoint("TOPRIGHT", ChatConfigBackgroundFrame, "TOPRIGHT", -170, -3)
	box.Label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	box.Label:SetPoint("LEFT", box, "RIGHT", 2, 0)
	box.Label:SetText(L["LTC (LefthyTools chat)"])
	local function Refresh()
		local window = CurrentTab()
		box:SetShown(window ~= nil)
		box:SetChecked(window ~= nil and TabChosen(window))
	end
	box:SetScript("OnClick", function(self)
		local window = CurrentTab()
		if window then
			SetTab(window, self:GetChecked() and true or false)
		end
		Refresh()
	end)
	box:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L["LTC (LefthyTools chat)"])
		GameTooltip:AddLine(L["Shows your friends' LTC lines in this chat tab. /l works from any tab."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	box:SetScript("OnLeave", function(self)
		if GameTooltip:IsOwned(self) then
			GameTooltip:Hide()
		end
	end)
	box:SetScript("OnShow", Refresh)
	ChatConfigChatSettings:HookScript("OnShow", Refresh)
	Refresh()
	return box
end

-- A window closed may come back as another tab: it starts without LTC.
local function OnTabClosed(frame)
	local window = UsableTab(frame)
	local tabs = window and ChosenTabs()
	if tabs then
		tabs[window] = nil
	end
end

-- Picking a sound plays it.
function B.LTCSoundChanged()
	local kit = M.db.lefthyChatSoundKit
	if lastSoundKit and kit ~= lastSoundKit and kit then
		PlaySound(kit, "SFX")
	end
	lastSoundKit = kit
end

function B.LTCSoundKnown()
	lastSoundKit = M.db.lefthyChatSoundKit
end

-- The colour, from the settings: Blizzard's picker.
function B.PickLTCColour()
	if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then
		return
	end
	local was = ChatColour():sub(5)
	local function Hex(r, g, b)
		return ("%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
	end
	ColorPickerFrame:SetupColorPickerAndShow({
		r = tonumber(was:sub(1, 2), 16) / 255, g = tonumber(was:sub(3, 4), 16) / 255, b = tonumber(was:sub(5, 6), 16) / 255,
		swatchFunc = function()
			M.db.lefthyChatColour = Hex(ColorPickerFrame:GetColorRGB())
			if B.RepaintLTCHeaders then
				B.RepaintLTCHeaders()
			end
		end,
		cancelFunc = function()
			M.db.lefthyChatColour = was
			if B.RepaintLTCHeaders then
				B.RepaintLTCHeaders()
			end
		end,
	})
end

-- A friend whose build turns fewer links back into links than mine sent (they get "[text]"
-- instead) is named once (per build). Not before their version is known: that's not old.
local warnedOld = {} -- "<name>/<their version>" -> true
local function WarnOldFriends(text)
	if not text:find("{%a+:[^}]*%[") then
		return
	end
	local names = {}
	for _, peer in pairs(M:GetPeers()) do
		local key = peer.name and peer.version and (peer.name .. "/" .. peer.version)
		if key and not warnedOld[key] and LinkLevel(peer.version) < FULL then
			warnedOld[key] = true
			names[#names + 1] = peer.name
		end
	end
	if #names > 0 then
		table.sort(names)
		M:Print(("%s %s an older LefthyTools (%s): links other than items reach them as text until they update.")
			:format(table.concat(names, ", "), #names == 1 and "has" or "have", "/lefthy beacon status"))
	end
end

local function FlightSubtitle(text)
	local flight = ns.CinematicFlight
	if flight and flight.Subtitle then
		flight.Subtitle(text)
	end
end

-- The line as each build gets it: Packer(raw)(level), worked out once per level.
local function Packer(raw)
	local packed = {} -- level -> the line as that build gets it
	return function(level)
		if not packed[level] then
			-- (cut to size: a link cut in half goes)
			packed[level] = (B.Clean(PackLinks(raw, level), TEXT_BYTES):gsub("{%a+:[^}]*$", ""))
		end
		return packed[level]
	end
end
B.LTCPacker = Packer

local USAGE = {
	chat = "/ltc <text> (or /l) sends a line to every friend with LefthyTools.",
	announce = "/la <text> (or /lefthy announce <text>) puts a line in the middle of your friends' screens.",
	who = "/ltc who <text> asks your friends with LefthyTools who's in (/ltc who Deadmines): they answer with a click.",
}

-- Whether a line of this kind ("chat", "announce", "who": a call counts as a chat line) may go now; if
-- not, chat says why. empty: there's nothing to send. True: it's counted as sent.
local function MaySend(kind, empty)
	local announce = kind == "announce"
	if not M.enabled then
		M:Print("Beacon is off: /lefthy enable beacon.")
		return false
	end
	if not M.db[announce and "announcements" or "lefthyChat"] then
		M:Print((announce and "announcements are" or "LTC is") .. " off (Beacon settings).")
		return false
	end
	if empty then
		M:Print(USAGE[kind])
		return false
	end
	local now = GetTime()
	kind = announce and "announce" or "chat"
	local times, limit = sentAt[kind], SEND_LIMIT[kind]
	if #times >= limit and now - times[#times - limit + 1] < SEND_WINDOW[kind] then
		M:Print("not so fast: try again in a moment.")
		return false
	end
	if not next(B.peers) then
		M:Print("no friends with LefthyTools online.")
		return false
	end
	times[#times + 1] = now
	if #times > limit then
		table.remove(times, 1)
	end
	return true
end
B.LTCMaySend = MaySend

-- My own line in my chat window, as in guild chat (named as friends see me); then(shown) after it.
local function ShowMine(text, after)
	UnpackLinks(text, function(shown) -- what my friends see
		local _, classFile = UnitClass("player")
		ShowInChat(ChatLine(B.MyName(), classFile, shown))
		if after then
			after(shown)
		end
	end)
end
B.LTCShowMine = ShowMine

local function Send(kind, text)
	local raw = (strtrim(text or ""):gsub('^"(.*)"$', "%1")) -- /lefthy announce "text"
	local Packed = Packer(raw)
	text = Packed(FULL)
	if not MaySend(kind, text == "") then
		return
	end
	local prefix = (kind == "chat" and "M" or "A") .. B.VERSION .. ";"
	for gameAccountID, peer in pairs(M:GetPeers()) do
		local line = Packed(LinkLevel(peer.version))
		if line ~= "" then
			B.Queue(gameAccountID, prefix .. line)
		end
	end
	WarnOldFriends(text)
	if kind == "chat" then
		if B.LTCHold then
			B.LTCHold(text) -- ChatMissed.lua: kept for friends who aren't online now
		end
		ShowMine(text)
	else
		UnpackLinks(text, function(shown)
			B.ShowAnnouncement(nil, shown)
		end)
	end
end

function B.SendChat(text)
	Send("chat", text)
end

function B.Announce(text)
	Send("announce", text)
end

-- A friend's line plays LTC's sound: once for a burst; a line that mentions me always (but not
-- twice within SOUND_GAP), a line I missed only then (they come in a row).
local function LineSound(mention, missed)
	local now = GetTime()
	if not M.db.lefthyChatSound then
		return
	elseif mention then
		if now - lastMention < SOUND_GAP then
			return
		end
		lastMention = now
	elseif missed or now - lastSound < SOUND_GAP then
		return
	end
	lastSound = now
	if not PlaySound(M.db.lefthyChatSoundKit or CHAT_SOUND, "SFX") then
		PlaySound(CHAT_SOUND, "SFX")
	end
end

-- A friend's line (cleaned), in the order they came: links rebuilt, my name standing out, the sound.
-- opts: missed (the time it was written: a line I missed), after (text after it: a call's
-- buttons), peer (who sent it live: the AFK screen and flights hear of it).
local function ShowFriend(name, classFile, text, opts)
	InOrder(text, function(shown)
		if not (M.enabled and M.db.lefthyChat) then
			return -- (switched off while an item was loading)
		end
		local marked, mention = shown, false
		if M.db.lefthyChatMentions then
			marked, mention = Highlight(shown)
		end
		local line = ChatLine(name, classFile, marked .. (opts.after or ""), opts.missed)
		ShowInChat(line, mention)
		LineSound(mention, opts.missed)
		if mention and FlashClientIcon then
			pcall(FlashClientIcon) -- (the game's icon on the taskbar)
		end
		if opts.peer then
			FlightSubtitle(line)
			B.Notify("chat", opts.peer, { text = shown }) -- (the AFK screen)
		end
	end)
end
B.LTCShowFriend = ShowFriend

-- On Beacon's tick (Beacon.lua hands them over).
function B.ReceiveChat(peer, text)
	if not M.db.lefthyChat then
		return
	end
	text = B.Clean(text, TEXT_BYTES)
	if B.LTCHeard then
		B.LTCHeard(peer, text) -- ChatMissed.lua: seen, and kept for my friends who aren't online now
	end
	ShowFriend(peer.name, peer.classFile, text, { peer = peer })
end

-- LTC's B2;b words (Beacon.lua hands them over on its tick): who's in (ChatCalls.lua), missed lines
-- (ChatMissed.lua).
function B.ReceiveLTC(peer, id, word, rest)
	if word == "bw" or word == "ba" then
		if B.ReceiveCall then
			B.ReceiveCall(peer, id, word, rest)
		end
	elseif B.ReceiveMissed then
		B.ReceiveMissed(peer, id, word, rest)
	end
end

function B.ReceiveAnnouncement(peer, text)
	if not M.db.announcements then
		return
	end
	InOrder(B.Clean(text, TEXT_BYTES), function(shown)
		if not (M.enabled and M.db.announcements) then
			return
		end
		ShowInChat(ChatLine(peer.name, peer.classFile, shown)) -- in the chat window too, for the record
		B.ShowAnnouncement(peer, shown)
		B.Notify("announce", peer, { text = shown })
	end)
end

---------------------------------------------------------------------------
-- Sticky /ltc (/l), like /g or /p
--
-- The chat box can't have a chat type of ours: ChatTypeInfo and its lists are Blizzard's, and
-- writing to them would taint every line anyone sends. Instead, after /ltc the box is in LTC
-- mode: its header says "LTC:" in our colour (a post-hook on UpdateHeader), and a plain line
-- typed there goes to LTC. It's taken in Blizzard's own "ChatFrame.OnEditBoxPreSendText"
-- event, which runs callbacks through securecallfunction, so Blizzard's sending stays untainted:
-- the line goes to LTC and the box is emptied, so the game sends nothing. Typing another
-- sticky chat type (/s, /g, /p, /1, ...; a post-hook on HandleChatType) leaves LTC mode, as
-- switching from /g to /p does; whispers don't (they aren't sticky in the game either).
---------------------------------------------------------------------------

local HEADER = "LTC: "
-- The box's header, in LTC's colour.
local function HeaderColour()
	local hex = ChatColour():sub(5)
	return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end
local LEFTHY_COMMANDS = { ["/L"] = true, ["/LTC"] = true, ["/LCHAT"] = true }
local sticky = false -- Lefthy mode
local stickyType     -- the box's chat type it stands in for (what the box showed when /l came)

local function InLefthyMode(editBox)
	return sticky and M.enabled and M.db.lefthyChat and editBox:GetChatType() == stickyType
		and not (editBox.chatFrame and editBox.chatFrame.isTemporary) -- (whisper windows keep theirs)
end

local function EnterLefthyMode(editBox)
	if editBox and editBox.GetChatType then
		sticky, stickyType = true, editBox:GetChatType()
		editBox:UpdateHeader()
	end
end

local function PaintHeader(editBox)
	if not InLefthyMode(editBox) then
		return
	end
	local header = _G[editBox:GetName() .. "Header"]
	local suffix = _G[editBox:GetName() .. "HeaderSuffix"]
	if not header then
		return
	end
	header:SetWidth(0)
	header:SetText(HEADER)
	header:SetTextColor(HeaderColour())
	if suffix then
		suffix:Hide()
	end
	local language = editBox.UpdateLanguageHeader and editBox:UpdateLanguageHeader() or 0
	editBox:SetTextInsets(15 + header:GetWidth() + language, 13, 0, 0) -- as Blizzard's UpdateHeader does
	editBox:SetTextColor(HeaderColour())
end

-- A command typed in the box (also while typing, before Enter: send 0).
local function OnChatTypeCommand(editBox, msg, command, send)
	if LEFTHY_COMMANDS[command] then
		if send ~= 1 then -- "/l " typed: the box switches at once, like "/g "
			EnterLefthyMode(editBox)
			editBox:SetText(msg or "")
		end
		return
	end
	if not sticky then
		return
	end
	local chatType = command:match("^/%d+$") and "CHANNEL" or (hash_ChatTypeInfoList and hash_ChatTypeInfoList[command])
	local info = chatType and ChatTypeInfo and ChatTypeInfo[chatType]
	if info and info.sticky == 1 then
		sticky = false
		editBox:UpdateHeader() -- (Blizzard's ran before this hook, while still in Lefthy mode)
	end
end

local function OnPreSendText(_, editBox)
	if not InLefthyMode(editBox) then
		return
	end
	local text = editBox:GetText()
	if text and text:find("%S") then
		editBox:SetText("") -- the game sends nothing
		editBox:AddHistoryLine(text) -- (up arrow brings it back)
		B.SendChat(text)
	end
end

-- The colour changed: a box in LTC mode follows.
function B.RepaintLTCHeaders()
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		local editBox = _G["ChatFrame" .. i .. "EditBox"]
		if editBox and editBox.GetName then
			PaintHeader(editBox)
		end
	end
end

table.insert(LT.onLogin, function()
	B.BuildLTCTabBox()
	if FCF_Close then
		hooksecurefunc("FCF_Close", OnTabClosed)
	end
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		local editBox = _G["ChatFrame" .. i .. "EditBox"]
		if editBox and editBox.UpdateHeader and editBox.HandleChatType then
			hooksecurefunc(editBox, "UpdateHeader", PaintHeader)
			hooksecurefunc(editBox, "HandleChatType", OnChatTypeCommand)
		end
	end
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("ChatFrame.OnEditBoxPreSendText", OnPreSendText, B)
	end
end)

-- /ltc or /l like /g or /p, and the box stays on it; /lchat in case another addon has /l. /la: announce.
SLASH_LEFTHYTOOLS_CHAT1 = "/l"
SLASH_LEFTHYTOOLS_CHAT2 = "/lchat"
SlashCmdList.LEFTHYTOOLS_CHAT = function(msg, editBox)
	EnterLefthyMode(editBox) -- (typed in a chat box; nil from a macro)
	if strtrim(msg or "") == "" and M.enabled and M.db.lefthyChat then
		M:Print("LTC: what you type now goes to your friends with LefthyTools. /s, /g, /p, ... switch back.")
	else
		B.SendChat(msg) -- (or why it can't)
	end
end
-- /ltc is /l, and /ltc who <text> asks who's in (ChatCalls.lua). Only /ltc: "/l who wants to come?" is a line.
SLASH_LEFTHYTOOLS_LTC1 = "/ltc"
SlashCmdList.LEFTHYTOOLS_LTC = function(msg, editBox)
	local word, rest = strtrim(msg or ""):match("^(%S+)%s*(.-)$")
	if word and word:lower() == "who" and B.WhoCall then
		EnterLefthyMode(editBox)
		B.WhoCall(rest)
	else
		SlashCmdList.LEFTHYTOOLS_CHAT(msg, editBox)
	end
end
SLASH_LEFTHYTOOLS_ANNOUNCE1 = "/la"
SlashCmdList.LEFTHYTOOLS_ANNOUNCE = B.Announce
LT:AddCommand("announce", B.Announce, "/lefthy announce <text> (or /la) - a line in the middle of your Beacon friends' screens"
	.. " (/ltc or /l <text>: LTC, LefthyTools chat)", "news")
