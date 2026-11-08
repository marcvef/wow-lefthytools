local _, ns = ...
local LT = ns.LT
local L = ns.L
local M = LT:GetModule("beacon")
local B = ns.Beacon

-- /ltc who <text> ("/ltc who Deadmines"): a call in LTC. Friends on a build from Chat.lua's LTC_SINCE
-- on see the line with two links, [I'm in] and [Not now]; the caller gets a tally line under their
-- own, redrawn in place as answers come (ScrollingMessageFrame's TransformMessages, at most every
-- TALLY_GAP seconds; a window without it, or one where the line is gone, gets a new one), with
-- [Invite all], which invites those who are in (C_BattleNet.InviteFriend, from the click only).
-- A call ends after CALL_TIME: the tally says so, the links say it's over.
--
--   B2;bw;<call id>;<text>   the call, to friends whose build reads it (B.ReadsLTC); an older build
--                            gets an LTC line instead, M2;Who's in? <text>, in the caller's language
--   B2;ba;<call id>;<1|0>    an answer, to the caller: I'm in (1), not now (0); the last one counts
--
-- The links are "addon" links (|Haddon:lefthytools:who:...|h): Blizzard's SetItemRef hands those to
-- EventRegistry's "SetItemRef" event, which this listens to; they only exist in my own chat window.
-- A call goes into friends' missed lines (ChatMissed.lua) as a plain line, "Who's in? <text>".

local CALL_TIME = 900   -- a call ends after 15 minutes
local TALLY_GAP = 1     -- a tally is redrawn at most this often
local ANSWER_GAP = 1    -- one answer per click and second
local MAX_THEIRS = 50   -- friends' calls remembered (their links)
local IN_COLOUR, OUT_COLOUR, INVITE_COLOUR = "ff40d040", "ffa0a0a0", "ff66bbff"

local myCalls = {}      -- id -> { id, label, at, asked = { [gameAccountID] = true }, answers = { [id] = true | false }, names, frames, marker, dirty, drawnAt }
local theirCalls = {}   -- "<gameAccountID>:<id>" -> { gid, id, name, at, answeredAt }
local lastId = 0
local session = tostring(math.random(10000, 99999)) -- (a tally's link from before a /reload isn't mine)

local function Link(colour, data, label)
	return ("|c%s|Haddon:lefthytools:who:%s|h[%s]|h|r"):format(colour, data, label)
end

local function Note(text)
	return B.LTCShowInChat(B.LTCNoteLine(text))
end

---------------------------------------------------------------------------
-- My calls: sending, the tally, Invite all
---------------------------------------------------------------------------

-- The tally line: who's in, who isn't; [Invite all] until it ends.
local function Tally(call, ended)
	local yes, no = {}, {}
	for id, answer in pairs(call.answers) do
		local list = answer and yes or no
		list[#list + 1] = call.names[id] or "?"
	end
	table.sort(yes)
	table.sort(no)
	local parts = {}
	if yes[1] then
		parts[#parts + 1] = L["%d in (%s)"]:format(#yes, table.concat(yes, ", "))
	end
	if no[1] then
		parts[#parts + 1] = L["%d not now (%s)"]:format(#no, table.concat(no, ", "))
	end
	local text = L["Who's in? %s: %s."]:format(call.label, parts[1] and table.concat(parts, ", ") or L["no answers yet"])
	if ended then
		return B.LTCNoteLine(text .. " " .. L["The call has ended."])
	end
	return B.LTCNoteLine(text) .. " " .. Link(INVITE_COLOUR, call.marker, L["Invite all"])
end

-- The tally again, in place where the windows can (else a new line).
local function Redraw(call, ended)
	call.dirty, call.drawnAt = false, GetTime()
	local line, found = Tally(call, ended), false
	local marker = "lefthytools:who:" .. call.marker .. "|h"
	local function Mine(message)
		return not LT.IsSecret(message) and type(message) == "string" and message:find(marker, 1, true) ~= nil
	end
	local function Replace(_, ...)
		found = true
		return line, ...
	end
	for _, frame in ipairs(call.frames or {}) do
		if frame.TransformMessages then
			pcall(frame.TransformMessages, frame, Mine, Replace)
		end
	end
	if not found and not ended then
		call.frames = B.LTCShowInChat(line) -- (scrolled away, or a window that can't: a new line)
	end
end

function B.WhoCall(text)
	local raw = strtrim(text or "")
	if not B.LTCMaySend("who", raw == "") then
		return
	end
	local Packed, Plain = B.LTCPacker(raw), B.LTCPacker(L["Who's in?"] .. " " .. raw)
	lastId = lastId % 999 + 1
	local call = { id = lastId, at = GetTime(), asked = {}, answers = {}, names = {}, marker = "all:" .. lastId .. ":" .. session }
	call.label = LT.CutUTF8(Packed(1), 60) -- (in the tally: the text with its links as their names, not too long)
	for gameAccountID, peer in pairs(M:GetPeers()) do
		if B.ReadsLTC(peer) then
			if Packed(B.LTC_FULL) ~= "" then
				B.Queue(gameAccountID, ("B%s;bw;%d;%s"):format(B.VERSION, call.id, Packed(B.LTC_FULL)))
				call.asked[gameAccountID] = true
			end
		else
			local line = Plain(B.LTCLinkLevel(peer.version))
			if line ~= "" then
				B.Queue(gameAccountID, "M" .. B.VERSION .. ";" .. line) -- (an older build: a line it can read)
			end
		end
	end
	myCalls[call.id] = call
	if B.LTCHold then
		B.LTCHold(Plain(B.LTC_FULL)) -- friends offline get it as a line they missed
	end
	B.LTCShowMine(Plain(B.LTC_FULL), function()
		call.frames = B.LTCShowInChat(Tally(call))
	end)
end

-- Invite all: everyone who's in, online and not in my group yet (from the click).
local function InviteAll(id, from)
	local call = myCalls[id]
	if from ~= session or not call then
		Note(L["The call has ended."])
		return
	end
	local names = {}
	for gameAccountID, answer in pairs(call.answers) do
		local peer = B.peers[gameAccountID]
		if answer and peer and peer.name and not peer.groupUnit and C_BattleNet and C_BattleNet.InviteFriend
			and pcall(C_BattleNet.InviteFriend, gameAccountID) then
			names[#names + 1] = peer.name
		end
	end
	table.sort(names)
	Note(names[1] and L["Invited %s."]:format(table.concat(names, ", ")) or L["Nobody to invite: no one is in yet, or they're in your group already."])
end

---------------------------------------------------------------------------
-- Friends' calls: the line with its links, answering
---------------------------------------------------------------------------

local function Forget(now)
	local count, oldest, oldestKey = 0, nil, nil
	for key, call in pairs(theirCalls) do
		if now - call.at > CALL_TIME then
			theirCalls[key] = nil
		else
			count = count + 1
			if not oldest or call.at < oldest then
				oldest, oldestKey = call.at, key
			end
		end
	end
	if count >= MAX_THEIRS then
		theirCalls[oldestKey] = nil
	end
end

local function Answer(gameAccountID, id, yes)
	local call, now = theirCalls[gameAccountID .. ":" .. id], GetTime()
	if not call or now - call.at > CALL_TIME then
		Note(L["The call has ended."])
		return
	elseif not (M.enabled and B.peers[gameAccountID]) then
		Note(L["%s isn't online any more."]:format(call.name))
		return
	elseif call.answeredAt and now - call.answeredAt < ANSWER_GAP then
		return
	end
	call.answeredAt = now
	B.Queue(gameAccountID, ("B%s;ba;%d;%d"):format(B.VERSION, id, yes and 1 or 0))
	Note((yes and L["You told %s you're in."] or L["You told %s: not now."]):format(call.name))
end

-- From Chat.lua (B.ReceiveLTC): a friend's call, or an answer to mine.
function B.ReceiveCall(peer, gameAccountID, word, rest)
	if not M.db.lefthyChat then
		return
	end
	local now = GetTime()
	if word == "bw" then
		local id, text = rest:match("^(%d%d?%d?);([^;]+)$")
		text = text and B.Clean(text, B.LTC_TEXT_BYTES) or ""
		if text == "" then
			return
		end
		id = tonumber(id)
		Forget(now)
		theirCalls[gameAccountID .. ":" .. id] = { gid = gameAccountID, id = id, name = peer.name, at = now }
		local line = L["Who's in?"] .. " " .. text
		if B.LTCHeard then
			B.LTCHeard(peer, line) -- (seen, and kept for my friends offline as a plain line)
		end
		local data = gameAccountID .. ":" .. id
		B.LTCShowFriend(peer.name, peer.classFile, line, { peer = peer,
			after = " " .. Link(IN_COLOUR, "in:" .. data, L["I'm in"]) .. " " .. Link(OUT_COLOUR, "out:" .. data, L["Not now"]) })
	elseif word == "ba" then
		local id, answer = rest:match("^(%d+);([01])$")
		local call = id and myCalls[tonumber(id)]
		if call and call.asked[gameAccountID] and now - call.at <= CALL_TIME then
			call.answers[gameAccountID], call.names[gameAccountID] = answer == "1", peer.name
			call.dirty = true
		end
	end
end

-- On Beacon's tick: tallies redrawn, calls ending (nothing to do while there are none).
local lastForget = -math.huge
function B.TickCalls(now)
	for id, call in pairs(myCalls) do
		if now - call.at > CALL_TIME then
			myCalls[id] = nil
			Redraw(call, true)
		elseif call.dirty and call.frames and now - (call.drawnAt or 0) >= TALLY_GAP then
			Redraw(call)
		end
	end
	if next(theirCalls) and now - lastForget >= 5 then
		lastForget = now
		Forget(now)
	end
end

-- A click on one of the links (Blizzard's SetItemRef hands "addon" links to this event).
local function OnLink(_, link)
	if type(link) ~= "string" or LT.IsSecret(link) then
		return
	end
	local what, a, b = link:match("^addon:lefthytools:who:(%l+):(%d+):(%d+)$")
	if what == "in" or what == "out" then
		Answer(tonumber(a), tonumber(b), what == "in")
	elseif what == "all" then
		InviteAll(tonumber(a), b)
	end
end

table.insert(LT.onLogin, function()
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("SetItemRef", OnLink, myCalls)
	end
end)
