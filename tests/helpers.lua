-- What every test file shares. tests/run.js runs this first (after mock.lua), then the test files in
-- order, all in one Lua state, and hands each file the table this returns: `local suite = ...`.
-- It loads the addon like the client does and keeps the count; suite.Finish() runs after the last file.
local suite = {}

local failures, passes = 0, 0
local function check(cond, msg)
	if cond then passes = passes + 1 else failures = failures + 1; io.write("  FAIL: " .. msg .. "\n") end
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 0.01) end
local function a(name) return _G[name]:GetAlpha() end
local function section(t) io.write("\n== " .. t .. "\n") end

-- Globals that exist before the addon loads (the mock); anything new at the end must be ours.
local globalsBefore = {}
for k in pairs(_G) do globalsBefore[k] = true end

-- Load the addon like the client would: TOC order, each file gets (addonName, ns).
local ns = {}
for _, file in ipairs(SOURCES) do
	local chunk = assert(load(file.src, "@Interface/AddOns/LefthyTools/" .. file.name)) -- named like in game
	chunk("LefthyTools", ns)
end
Fire("ADDON_LOADED", "LefthyTools")
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD", true, false)
Advance(0.3) -- let the debounced rebuild run

local LT = LefthyTools
local lefthy = SlashCmdList.LEFTHYTOOLS

-- What was printed to chat since PRINTED[mark], one line each.
local function printedSince(mark)
	local out = {}
	for i = mark, #PRINTED do out[#out + 1] = PRINTED[i] end
	return table.concat(out, "\n")
end

-- Beacon's messages: to a friend's game account since GAMEDATA[from] that start with prefix, and one
-- from Anna (game account 11) to me.
local function sentTo(id, from, prefix)
	local list = {}
	for _, m in ipairs(GameDataTo(id, from)) do if m:sub(1, #prefix) == prefix then list[#list + 1] = m end end
	return list
end
local function anna(state) Fire("BN_CHAT_MSG_ADDON", "LTBeacon", state, "WHISPER", 11) end
local function peers() return LT:GetModule("beacon"):GetPeers() end

-- A friend's dot on the world map; a line of the tooltip.
local function pinOf(id) for _, p in ipairs(PINS) do if p.gameAccountID == id then return p end end end
local function tooltipHas(text) for _, l in ipairs(TOOLTIP.lines) do if l == text then return true end end return false end

-- Going away (/afk) and coming back.
local function afk(on) STATE.afk = on; Fire("PLAYER_FLAGS_CHANGED", "player") end

-- What reaches the error handler from now on; call the second result to stop.
local function catchErrors()
	local reported, errorHandler = {}, geterrorhandler
	geterrorhandler = function() return function(err) reported[#reported + 1] = tostring(err) end end
	return reported, function() geterrorhandler = errorHandler end
end

-- Where the addon kept a secret it mustn't: as a table key anywhere it can reach (in the game
-- that errors; Lua has no hook to catch it when it happens, so this looks afterwards), or anywhere
-- in its saved variables. A few paths, nil if none.
local function secretsKept()
	local found, seen = {}, {}
	local function walk(t, path, saved)
		if seen[t] or #found >= 5 then return end
		seen[t] = true
		for k, v in next, t do
			local at = path .. (issecretvalue(k) and "[secret]" or "." .. tostring(k))
			if issecretvalue(k) or (saved and issecretvalue(v)) then found[#found + 1] = at end
			if type(k) == "table" and not issecretvalue(k) then walk(k, path .. "[key]", saved) end
			if type(v) == "table" and not issecretvalue(v) then walk(v, at, saved) end
		end
	end
	for _, name in ipairs({ "LefthyToolsDB", "LefthyToolsChronicleDB", "LefthyToolsBestiaryDB" }) do
		if type(_G[name]) == "table" then walk(_G[name], name, true) end
	end
	walk(ns, "ns")
	return found[1] and table.concat(found, ", ")
end

-- After the last file: nothing reached the error handler, no secret kept, no globals leaked, the count.
function suite.Finish()
	check(#ERRORS == 0, "no errors reported through the error handler")
	local kept = secretsKept()
	check(not kept, "no secret as a table key, none in saved variables, found: " .. tostring(kept))

	-- A forgotten `local` leaks a global, which in game can clash with other addons. Ours start with
	-- LefthyTools (incl. mixins); SLASH_/BINDING_ names and the tests' own MOCK_* knobs are all caps.
	local leaked = {}
	for k in pairs(_G) do
		if not globalsBefore[k] and type(k) == "string" and not k:match("^[A-Z][A-Z0-9_]*$") and not k:match("^LefthyTools") then
			leaked[#leaked + 1] = k
		end
	end
	table.sort(leaked)
	check(#leaked == 0, "no accidental globals, found: " .. table.concat(leaked, ", "))
	io.write(string.format("\n%d passed, %d failed\n", passes, failures))
	if failures > 0 then error("tests failed") end
end

suite.check, suite.near, suite.a, suite.section = check, near, a, section
suite.ns, suite.LT, suite.lefthy = ns, LT, lefthy
suite.printedSince, suite.sentTo, suite.anna, suite.peers = printedSince, sentTo, anna, peers
suite.pinOf, suite.tooltipHas, suite.afk, suite.catchErrors = pinOf, tooltipHas, afk, catchErrors
return suite
