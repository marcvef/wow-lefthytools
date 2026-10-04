local _, ns = ...
local LT = ns.LT
local M = LT:GetModule("beacon")
local B = ns.Beacon

-- Lefthy chat: a chat for your Battle.net friends with LefthyTools, like guild or party chat.
-- /l <text> sends a line (M2;<text>), and every friend's chat window shows "[Lefthy] [Anna]: text".
-- Announcements (/la or /lefthy announce <text>, A2;<text>) go to the middle of their screens instead, in
-- the notice stack of shared items (Items.lua: B.ShowAnnouncement), with the whisper sound. Both
-- also come as subtitles on a cinematic flight. Settings lefthyChat and announcements switch
-- sending and showing. The text goes through B.Clean (no colour codes, separators or escapes).

local TEXT_BYTES = 200
local CHAT_COLOUR = "|cffffb84d"
local SEND_GAP = { chat = 0.5, announce = 3 }
local lastSent = { chat = -math.huge, announce = -math.huge }

-- "[Lefthy] [Anna]: text", the name in its class colour.
local function ChatLine(name, classFile, text)
	return ("%s[Lefthy] [|r%s%s|r%s]: %s|r"):format(CHAT_COLOUR, LT.Window.ClassColorCode(classFile), name or "?",
		CHAT_COLOUR, text)
end

local function FlightSubtitle(text)
	local flight = ns.CinematicFlight
	if flight and flight.Subtitle then
		flight.Subtitle(text)
	end
end

local function Send(kind, text)
	text = B.Clean(strtrim(text or ""):gsub('^"(.*)"$', "%1"), TEXT_BYTES) -- /lefthy announce "text"
	if text == "" then
		M:Print(kind == "chat" and "/l <text> sends a line to every friend with LefthyTools."
			or "/la <text> (or /lefthy announce <text>) puts a line in the middle of your friends' screens.")
		return
	end
	if not M.enabled then
		M:Print("Beacon is off: /lefthy enable beacon.")
		return
	end
	if not M.db[kind == "chat" and "lefthyChat" or "announcements"] then
		M:Print((kind == "chat" and "Lefthy chat is" or "announcements are") .. " off (Beacon settings).")
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
	if kind == "chat" then
		local _, classFile = UnitClass("player")
		print(ChatLine(UnitName("player"), classFile, text)) -- my own line, as in guild chat
	else
		B.ShowAnnouncement(nil, text)
	end
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
	text = B.Clean(text, TEXT_BYTES)
	local line = ChatLine(peer.name, peer.classFile, text)
	print(line)
	FlightSubtitle(line)
	B.Notify("chat", peer, { text = text }) -- (the AFK screen)
end

function B.ReceiveAnnouncement(peer, text)
	if not M.db.announcements then
		return
	end
	text = B.Clean(text, TEXT_BYTES)
	print(ChatLine(peer.name, peer.classFile, text)) -- in the chat window too, for the record
	B.ShowAnnouncement(peer, text)
	B.Notify("announce", peer, { text = text })
end

-- /l like /g or /p; /lchat in case another addon has /l. /la: /lefthy announce.
SLASH_LEFTHYTOOLS_CHAT1 = "/l"
SLASH_LEFTHYTOOLS_CHAT2 = "/lchat"
SlashCmdList.LEFTHYTOOLS_CHAT = B.SendChat
SLASH_LEFTHYTOOLS_ANNOUNCE1 = "/la"
SlashCmdList.LEFTHYTOOLS_ANNOUNCE = B.Announce
