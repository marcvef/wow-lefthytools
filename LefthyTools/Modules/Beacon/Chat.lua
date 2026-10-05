local _, ns = ...
local LT = ns.LT
local M = LT:GetModule("beacon")
local B = ns.Beacon

-- Lefthy chat: a chat for your Battle.net friends with LefthyTools, like guild or party chat.
-- /l <text> sends a line (M2;<text>), and every friend's chat window shows "[Lefthy] [Anna]: text".
-- Announcements (/la or /lefthy announce <text>, A2;<text>) go to the middle of their screens instead, in
-- the notice stack of shared items (Items.lua: B.ShowAnnouncement), with the whisper sound. Both
-- also come as subtitles on a cinematic flight. Settings lefthyChat and announcements switch
-- sending and showing. The text goes through B.Clean (no colour codes, separators or escapes), so
-- item links travel as {item:<numbers>} (B.ItemString: only the numeric fields) and each client
-- builds the link again in its own language (B.WithLink). Map pins, professions, spells, quests,
-- achievements and the other kinds players link (LINK_KINDS) travel as
-- {<type>:<data>[<text>]<colour>} (the text in the sender's language) and become clickable links
-- again, in their own colour; any other link keeps its "[text]".

local TEXT_BYTES = 200
local CHAT_COLOUR = "|cffffb84d"
local SEND_GAP = { chat = 0.5, announce = 3 }
local lastSent = { chat = -math.huge, announce = -math.huge }
local CHAT_SOUND = SOUNDKIT and SOUNDKIT.IG_CHAT_SCROLL_UP or 826 -- a very soft tick (setting lefthyChatSound)
local SOUND_GAP = 1.5 -- a burst of lines ticks once
local lastSound = -math.huge

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

local function Token(colour, data, shown)
	local kind = data:match("^(%a+):")
	if kind == "item" then
		local itemString = B.ItemString and B.ItemString("|H" .. data .. "|h")
		return itemString and ("{item:" .. itemString:gsub(":+$", "") .. "}") or ""
	end
	local label = (shown:match("^%[(.*)%]$") or shown):gsub("|T.-|t", ""):gsub("|A.-|a", "")
	label = strtrim((label:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", "")))
	if kind and LINK_KINDS[kind] and data:find("^" .. LINK_DATA .. "+$") and not label:find("[%[%]{}|]") then
		return "{" .. data .. "[" .. label .. "]" .. (colour and colour:sub(3) or "") .. "}"
	end
	return "[" .. label .. "]"
end

-- Before sending: item links become {item:12345:...} (trailing empty fields dropped: the item is
-- the same), the kinds above {trade:...[Tailoring]ffd000}, any other link its text; colour codes,
-- textures and atlases go.
local function PackLinks(text)
	text = text:gsub("|c(%x%x%x%x%x%x%x%x)|H([^|]*)|h(.-)|h|r", Token)
	text = text:gsub("|H([^|]*)|h(.-)|h", function(data, shown) return Token(nil, data, shown) end)
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
local function UnpackLinks(text, callback)
	text = Relink(text)
	local wanted = {}
	for itemString in text:gmatch("{item:([%d:%-]+)}") do
		wanted[#wanted + 1] = itemString
	end
	if #wanted == 0 or not B.WithLink then
		callback(text)
		return
	end
	local links, pending = {}, #wanted
	for _, itemString in ipairs(wanted) do
		B.WithLink(itemString, function(link)
			links[itemString] = link or false
			pending = pending - 1
			if pending == 0 then
				callback((text:gsub("{item:([%d:%-]+)}", function(s) return links[s] or "[?]" end)))
			end
		end)
	end
end

-- "[Lefthy] [Anna]: text", the name in its class colour.
local function ChatLine(name, classFile, text)
	return ("%s[Lefthy] [|r%s%s|r%s]: %s|r"):format(CHAT_COLOUR, LT.Window.ClassColorCode(classFile), name or "?",
		CHAT_COLOUR, text)
end

-- Links other than items arrive as links from this build on (0.5.0-16: the token with its
-- colour); older builds show the token as text. Whoever is older gets named once (per build).
local LINKS_SINCE = "0.5.0-16-g5d0608d"
local warnedOld = {} -- "<name>/<their version>" -> true
local function WarnOldFriends(text)
	if not text:find("{%a+:[^}]*%[") then
		return
	end
	local names = {}
	for _, peer in pairs(M:GetPeers()) do
		local key = peer.name and (peer.name .. "/" .. tostring(peer.version))
		if key and not warnedOld[key] and LT.CompareVersions(peer.version or "0.0.0", LINKS_SINCE) == -1 then
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

local function Send(kind, text)
	text = PackLinks(strtrim(text or ""):gsub('^"(.*)"$', "%1")) -- /lefthy announce "text"
	-- (cut to size: a link cut in half goes)
	text = B.Clean(text, TEXT_BYTES):gsub("{%a+:[^}]*$", "")
	if not M.enabled then
		M:Print("Beacon is off: /lefthy enable beacon.")
		return
	end
	if not M.db[kind == "chat" and "lefthyChat" or "announcements"] then
		M:Print((kind == "chat" and "Lefthy chat is" or "announcements are") .. " off (Beacon settings).")
		return
	end
	if text == "" then
		M:Print(kind == "chat" and "/l <text> sends a line to every friend with LefthyTools."
			or "/la <text> (or /lefthy announce <text>) puts a line in the middle of your friends' screens.")
		return
	end
	local now = GetTime()
	if now - lastSent[kind] < SEND_GAP[kind] then
		M:Print("not so fast: try again in a moment.")
		return
	end
	if not next(B.peers) then
		M:Print("no friends with LefthyTools online.")
		return
	end
	lastSent[kind] = now
	B.QueueToPeers(((kind == "chat" and "M" or "A") .. "%s;%s"):format(B.VERSION, text))
	WarnOldFriends(text)
	UnpackLinks(text, function(shown) -- what my friends see
		if kind == "chat" then
			local _, classFile = UnitClass("player")
			print(ChatLine(UnitName("player"), classFile, shown)) -- my own line, as in guild chat
		else
			B.ShowAnnouncement(nil, shown)
		end
	end)
end

function B.SendChat(text)
	Send("chat", text)
end

function B.Announce(text)
	Send("announce", text)
end

-- On Beacon's tick (Beacon.lua hands them over).
function B.ReceiveChat(peer, text)
	if not M.db.lefthyChat then
		return
	end
	UnpackLinks(B.Clean(text, TEXT_BYTES), function(shown)
		if not (M.enabled and M.db.lefthyChat) then
			return -- (switched off while an item was loading)
		end
		local line = ChatLine(peer.name, peer.classFile, shown)
		print(line)
		local now = GetTime()
		if M.db.lefthyChatSound and now - lastSound >= SOUND_GAP then
			lastSound = now
			PlaySound(CHAT_SOUND, "SFX")
		end
		FlightSubtitle(line)
		B.Notify("chat", peer, { text = shown }) -- (the AFK screen)
	end)
end

function B.ReceiveAnnouncement(peer, text)
	if not M.db.announcements then
		return
	end
	UnpackLinks(B.Clean(text, TEXT_BYTES), function(shown)
		if not (M.enabled and M.db.announcements) then
			return
		end
		print(ChatLine(peer.name, peer.classFile, shown)) -- in the chat window too, for the record
		B.ShowAnnouncement(peer, shown)
		B.Notify("announce", peer, { text = shown })
	end)
end

---------------------------------------------------------------------------
-- Sticky /l, like /g or /p
--
-- The chat box can't have a chat type of ours: ChatTypeInfo and its lists are Blizzard's, and
-- writing to them would taint every line anyone sends. Instead, after /l the box is in Lefthy
-- mode: its header says "Lefthy:" in our colour (a post-hook on UpdateHeader), and a plain line
-- typed there goes to Lefthy chat. It's taken in Blizzard's own "ChatFrame.OnEditBoxPreSendText"
-- event, which runs callbacks through securecallfunction, so Blizzard's sending stays untainted:
-- the line goes to Lefthy chat and the box is emptied, so the game sends nothing. Typing another
-- sticky chat type (/s, /g, /p, /1, ...; a post-hook on HandleChatType) leaves Lefthy mode, as
-- switching from /g to /p does; whispers don't (they aren't sticky in the game either).
---------------------------------------------------------------------------

local HEADER = "Lefthy: "
local HEADER_R, HEADER_G, HEADER_B = 1, 0.72, 0.3 -- CHAT_COLOUR
local LEFTHY_COMMANDS = { ["/L"] = true, ["/LCHAT"] = true }
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
	header:SetTextColor(HEADER_R, HEADER_G, HEADER_B)
	if suffix then
		suffix:Hide()
	end
	local language = editBox.UpdateLanguageHeader and editBox:UpdateLanguageHeader() or 0
	editBox:SetTextInsets(15 + header:GetWidth() + language, 13, 0, 0) -- as Blizzard's UpdateHeader does
	editBox:SetTextColor(HEADER_R, HEADER_G, HEADER_B)
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

table.insert(LT.onLogin, function()
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

-- /l like /g or /p, and the box stays on it; /lchat in case another addon has /l. /la: announce.
SLASH_LEFTHYTOOLS_CHAT1 = "/l"
SLASH_LEFTHYTOOLS_CHAT2 = "/lchat"
SlashCmdList.LEFTHYTOOLS_CHAT = function(msg, editBox)
	EnterLefthyMode(editBox) -- (typed in a chat box; nil from a macro)
	if strtrim(msg or "") == "" and M.enabled and M.db.lefthyChat then
		M:Print("Lefthy chat: what you type now goes to your friends with LefthyTools. /s, /g, /p, ... switch back.")
	else
		B.SendChat(msg) -- (or why it can't)
	end
end
SLASH_LEFTHYTOOLS_ANNOUNCE1 = "/la"
SlashCmdList.LEFTHYTOOLS_ANNOUNCE = B.Announce
