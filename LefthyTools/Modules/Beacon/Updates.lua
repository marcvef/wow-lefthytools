local _, ns = ...
local LT = ns.LT
local M = LT:GetModule("beacon")
local B = ns.Beacon

-- A friend on a newer LefthyTools build: told once per login (a /reload counts as one), with how to
-- update (a /reload, or a restart when their build loads other files: LT.UpdateHint) and what's
-- coming, one line per change in their build. Their V2 says the build; I ask what's new in it after
-- my newest changelog id (U2, in my language), and they answer with those entries (W2, the newest
-- NEWS_LINES, then the end). A friend on an older build asks me the same: answered from
-- Data/Changelog.lua. Builds before 0.5.0 answer nothing: the notice waits NEWS_WAIT at most.

local VERSION = B.VERSION
local NEWS_LINES = 8         -- what's new in a friend's newer build: at most this many changes
local NEWS_WAIT = 5          -- the update notice waits this long for them (older builds don't send any)

local newerFrom         -- gameAccountID of a friend with a newer LefthyTools, told on a tick
local newerAt = 0       -- when their version came (the notice waits up to NEWS_WAIT for their news)
local news              -- what's new in their build: { lines = { { module, title } }, more, done }
local newerNoticeShown = false -- that notice comes once per login
local newsAsked = {}    -- { gameAccountID, after id, language }: friends who asked what's new in mine

---------------------------------------------------------------------------
-- From friends (Beacon.lua's OnMessage: state only, the tick does the rest)
---------------------------------------------------------------------------

-- Their V2 (peer.version is set): the settings overview learns it, and a build newer than mine is
-- asked what's new in it.
function B.FriendBuild(gameAccountID, peer, now)
	LT:NoteFriendVersion(peer.version, peer.files) -- the settings overview shows it
	if not newerNoticeShown and not newerFrom and LT.CompareVersions(peer.version, LT.version) == 1 then
		-- Told on a tick, once their name is known and their news are in: ask what's new.
		newerFrom, newerAt, news = gameAccountID, now, { lines = {}, more = 0 }
		B.Queue(gameAccountID, ("U%s;%d;%s"):format(VERSION, LT.WhatsNew.LatestID(), ns.LOCALE == "deDE" and "de" or "en"))
	end
end

-- Their U2 (at most one per NEWS_GAP, Beacon.lua): what's new in mine, answered on the tick.
function B.NewsAsked(gameAccountID, after, language)
	newsAsked[#newsAsked + 1] = { gameAccountID, after, language }
end

-- Their W2: a change in their newer build, or (id 0) the end, with how many were left out.
function B.ReceiveNews(gameAccountID, id, module, title)
	if news and gameAccountID == newerFrom and not news.done then -- only the news I asked for
		if id == 0 then
			news.done, news.more = true, tonumber(title) or 0
		elseif #news.lines < NEWS_LINES then
			news.lines[#news.lines + 1] = { module = module, title = B.Clean(title, 80) }
		end
	end
end

---------------------------------------------------------------------------
-- On the driver tick
---------------------------------------------------------------------------

-- A friend asked what's new in my build after their newest changelog id: my newest entries
-- above it, one message each (oldest first), then the end with how many older ones were left out.
local function SendNews(gameAccountID, after, language)
	local entries = {}
	for _, entry in ipairs(ns.CHANGELOG or {}) do
		if entry.id > after then
			entries[#entries + 1] = entry
		end
	end
	table.sort(entries, function(x, y) return x.id < y.id end)
	local first = math.max(1, #entries - NEWS_LINES + 1)
	for i = first, #entries do
		local entry = entries[i]
		local text = (language == "de" and entry.de or entry.en)[1]
		B.Queue(gameAccountID, ("W%s;%d;%s;%s"):format(VERSION, entry.id, entry.module or "general", B.Clean(text, 80)))
	end
	B.Queue(gameAccountID, ("W%s;0;;%d"):format(VERSION, first - 1))
end

local function ModuleTitle(key)
	local m = key ~= "general" and key ~= "" and LT:GetModule(key)
	return m and m.title or (key ~= "general" and key ~= "" and key) or "LefthyTools" -- (a module newer than mine: its key)
end

-- Once per login (a /reload counts as one): who has a newer build, whether a /reload is enough,
-- and one line per change in it.
local function ShowUpdateNotice(friend)
	M:Print(string.format("%s has a newer LefthyTools (%s, you have %s). %s", friend.name, friend.version,
		LT.version, LT.UpdateHint(friend.files)))
	if news and #news.lines > 0 then
		M:Print("What's coming:")
		for _, line in ipairs(news.lines) do
			print("   |cffffd200•|r " .. ModuleTitle(line.module) .. ": " .. line.title)
		end
		if news.more > 0 then
			print(("   |cffffd200•|r and %d more (/lefthy news lists everything once you've updated)"):format(news.more))
		end
	end
end

function B.TickUpdates(now)
	-- A friend runs a newer LefthyTools: say so once their news are in (or NEWS_WAIT has passed).
	local newer = newerFrom and B.peers[newerFrom]
	if newer and newer.name and not newerNoticeShown and (news.done or now - newerAt >= NEWS_WAIT) then
		newerNoticeShown, newerFrom = true, nil
		ShowUpdateNotice(newer)
		news = nil
	elseif newerFrom and not B.peers[newerFrom] then
		newerFrom, news = nil, nil
	end
	while #newsAsked > 0 do
		local asked = table.remove(newsAsked, 1)
		SendNews(asked[1], asked[2], asked[3])
	end
end
