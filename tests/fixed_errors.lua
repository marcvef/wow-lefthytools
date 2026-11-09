-- Beacon's error reports: a friend on an older build who reports an error fixed since is told to
-- update (Reports.lua's FIXED_ERRORS): matching, versions, once a day, fights, collecting off, the
-- line older builds show (M2) and the word newer ones read (B2;bf), sent and received.
-- Needs: beacon.lua, for its friends and Beacon on.
local suite = ...
local check, section, ns, LT, lefthy = suite.check, suite.section, suite.ns, suite.LT, suite.lefthy
local printedSince, sentTo, anna, peers = suite.printedSince, suite.sentTo, suite.anna, suite.peers
local BB = ns.Beacon
local Beacon = LT:GetModule("beacon")

-- A report as the sender's Reports.lua writes it (ErrorReport: context, kind and count, the error
-- line, then the stack and what was going on), newlines kept as the collector stores it.
local function report(version, line, rest, locale)
	return ("Error: LefthyTools %s (files aede37cc), WoW 1.60.1.70862, %s, Realmy, Alliance, level 17 HUNTER\n"
		.. "blocked, 1x, first 2026-11-07 17:23:04, LefthyTools %s\n%s\n%s"):format(version, locale or "enUS", version, line, rest or "")
end

section("Beacon: errors already fixed, matched")
do
	local old, panel = "0.7.0-24-g121bdc3", "combat: no, gamepad, mouse over: SettingsPanel.SearchBox, panels: SettingsPanel"
	local fix, version, language = BB.FixedFor(report(old, "ADDON_ACTION_FORBIDDEN: IsUserOAuthed()()", panel))
	check(fix and fix.fixed == "0.7.0-34-gdf90faf" and fix.sure and version == old and language == "en",
		"the settings panel's blocked call, from an older build: fixed in 0.7.0-34")
	check(not BB.FixedFor(report("0.7.0-34-gdf90faf", "ADDON_ACTION_FORBIDDEN: IsUserOAuthed()()", panel))
		and not BB.FixedFor(report("0.7.0-40-gabc1234-dirty", "ADDON_ACTION_FORBIDDEN: IsUserOAuthed()()", panel))
		and BB.FixedFor(report("0.7.0-33-g91aaf59-dirty", "ADDON_ACTION_FORBIDDEN: IsUserOAuthed()()", panel))
		and BB.FixedFor(report("0.7.0", "ADDON_ACTION_FORBIDDEN: IsUserOAuthed()()", panel))
		and not BB.FixedFor(report("?", "ADDON_ACTION_FORBIDDEN: IsUserOAuthed()()", panel)),
		"from the fix's build or newer (a dirty one too): not fixed for them; older ones are; an unknown build isn't told")
	local unknown = BB.FixedFor(report(old, "ADDON_ACTION_FORBIDDEN: UNKNOWN()()", panel))
	check(unknown and unknown.fixed == "0.7.0-34-gdf90faf" and not unknown.sure
		and not BB.FixedFor(report(old, "ADDON_ACTION_FORBIDDEN: UNKNOWN()()", "combat: no, panels: WorldMapFrame")),
		"an unnamed forbidden call: only with Blizzard's settings panel there, and as \"should be fixed\"")
	check(BB.FixedFor(report(old, "ADDON_ACTION_BLOCKED: Frame:SetPoint()()", "combat: yes, gamepad, panels: SettingsPanel"))
		and not BB.FixedFor(report(old, "ADDON_ACTION_BLOCKED: Frame:SetPoint()()", "combat: yes, gamepad")),
		"a frame call blocked with the settings panel open, not without it")
	local combo = BB.FixedFor(report("0.7.0-33-g91aaf59", "ADDON_ACTION_BLOCKED: UNKNOWN()()", "State: combat yes controller UI no instance party"))
	check(combo and combo.fixed == "0.7.0-62-g0000000" and not combo.sure
		and BB.FixedFor(report("0.7.0-38-ga809fad", "ADDON_ACTION_BLOCKED: UNKNOWN()()", ""))
		and not BB.FixedFor(report("0.7.0-62-gabcdef0", "ADDON_ACTION_BLOCKED: UNKNOWN()()", "")),
		"a blocked call in fights (the fight stream's range checks): should be fixed in 0.7.0-62")
	check(select(3, BB.FixedFor(report(old, "ADDON_ACTION_FORBIDDEN: IsUserOAuthed()()", panel, "deDE"))) == "de",
		"a German client's report: the German line")
	check(not BB.FixedFor(report(old, "ADDON_ACTION_FORBIDDEN: SetPreferredGamepadInteractTarget()()", ""))
		and not BB.FixedFor(report(old, "attempt to index a nil value", "ADDON_ACTION_FORBIDDEN: IsUserOAuthed()()"))
		and not BB.FixedFor("Report: LefthyTools " .. old .. " (files aede37cc), WoW 1.60.1.70862, enUS, Realmy\nWhat happened: "
			.. "ADDON_ACTION_FORBIDDEN: IsUserOAuthed()\nADDON_ACTION_FORBIDDEN: IsUserOAuthed()")
		and not BB.FixedFor(nil) and not BB.FixedFor("Error: nonsense"),
		"not fixed, the text only further down, a hand-written report, nothing: no match")

	-- What goes to each build: older ones an LTC line they show as it is, newer ones Beacon's word.
	local fits = true
	for _, f in ipairs(BB.FIXED_ERRORS) do
		local build = f.fixed:match("^[%d%.]+%-%d+")
		for _, lang in ipairs({ "en", "de" }) do
			local message = BB.FixedMessage(f, lang, old)
			local kind, text = BB.Parse(message)
			fits = fits and kind == "M" and #message <= 255 and #text <= 200 and not text:find("[{}|;]")
				and text:find(f[lang], 1, true) and text:find("Update-LefthyTools.cmd", 1, true)
				and (text:find(build .. " ", 1, true) or text:find(build .. ".", 1, true)) and not text:find("-g", 1, true)
		end
	end
	check(fits, "every fix, both languages: an LTC line (M2) that 0.7.0-24's parser takes whole (Protocol.lua is the same since), "
		.. "with what it was, the build and how to update")
	local en, de = select(2, BB.Parse(BB.FixedMessage(fix, "en", old))), select(2, BB.Parse(BB.FixedMessage(combo, "de", nil)))
	check(en == "LefthyTools note: the error you reported (a blocked action in Blizzard's settings panel) is fixed in build "
		.. "0.7.0-34. Update with Update-LefthyTools.cmd and restart the game.", "the English line, got " .. tostring(en))
	check(de:find("^LefthyTools%-Hinweis: Dein gemeldeter Fehler %(eine blockierte Aktion im Kampf, durch die Entfernungen des Kampf%-Streams%) "
		.. "sollte in Build 0%.7%.0%-62 behoben sein%."), "the German one, \"should be fixed\" (a build not known yet: the line), got " .. de)
	local word = BB.FixedMessage({ fixed = "0.7.0-90-g1234567", sure = true, en = "a test error", de = "ein Testfehler" }, "de", "0.7.0-60-gabcdef0")
	local kind, w, more = BB.Parse(word)
	check(kind == "B" and w == "bf" and more == "0.7.0-90-g1234567;1;a test error",
		"a build that reads it: Beacon's word, the whole build and what it was in English (its chat lines are), got " .. word)
	check(BB.FixedMessage(fix, "en", "0.7.0-38-gabcdef0"):sub(1, 3) == "M2;" and BB.FixedMessage(fix, "en", "garbage"):sub(1, 3) == "M2;",
		"a build before it, or one that can't be told: the LTC line")
end

section("Beacon: errors already fixed, told")
do
	local B = function(id) return REGISTERED_SETTINGS["LefthyTools_beacon_" .. id] end
	local panel = "combat: no, gamepad, mouse over: SettingsPanel.SearchBox, panels: SettingsPanel"
	local seq = 500
	-- Anna sends one, as Z2 parts (no ";", newlines as "^").
	local function annaReports(text)
		seq = seq + 1
		local flat = text:gsub("\n", "^")
		local parts = {}
		while #flat > 0 do
			parts[#parts + 1] = flat:sub(1, 150)
			flat = flat:sub(151)
		end
		for n, part in ipairs(parts) do
			anna(("Z2;%d;%d;%d;%s"):format(seq, n, #parts, part))
		end
	end
	local function toAnna(mark, prefix)
		return sentTo(11, mark, prefix)
	end
	anna("H2")
	anna("Y2;0")
	anna("V2;0.7.0-24-g121bdc3")
	B("collectReports"):SetValue(true)
	Advance(2)
	check(peers()[11] and peers()[11].name == "Anna Brook" and peers()[11].version == "0.7.0-24-g121bdc3", "Anna, on 0.7.0-24")
	LefthyToolsDB.fixedTold = nil

	local mark, pmark = #GAMEDATA + 1, #PRINTED + 1
	annaReports(report("0.7.0-24-g121bdc3", "ADDON_ACTION_FORBIDDEN: IsUserOAuthed()()", panel))
	Advance(1)
	local lines = toAnna(mark, "M2;")
	check(#lines == 1 and lines[1]:find("is fixed in build 0.7.0-34. Update with Update-LefthyTools.cmd and restart the game.", 1, true)
		and #toAnna(mark, "B2;bf") == 0, "her report of an error fixed since: one LTC line, which her build shows")
	check(printedSince(pmark):find("told Anna Brook the error they reported is fixed in 0.7.0-34 (they have 0.7.0-24-g121bdc3).", 1, true),
		"and I'm told I told her")
	local key = "Anna Brook / ADDON_ACTION_FORBIDDEN: IsUserOAuthed()"
	check(LefthyToolsDB.fixedTold and LefthyToolsDB.fixedTold[key] == date("%Y-%m-%d"), "saved: told today")

	-- Once a day per friend and fix.
	mark = #GAMEDATA + 1
	Advance(5)
	annaReports(report("0.7.0-24-g121bdc3", "ADDON_ACTION_FORBIDDEN: IsUserOAuthed()()", panel))
	Advance(5)
	check(#toAnna(mark, "M2;") == 0 and #LefthyToolsDB.friendReports > 0, "the same error again today: kept, but not told again")
	LefthyToolsDB.fixedTold[key] = "2000-01-01"
	LefthyToolsDB.fixedTold["Bob Stone / an old one"] = "2000-01-02"
	annaReports(report("0.7.0-24-g121bdc3", "ADDON_ACTION_FORBIDDEN: IsUserOAuthed()()", panel))
	Advance(1)
	check(#toAnna(mark, "M2;") == 1 and LefthyToolsDB.fixedTold[key] == date("%Y-%m-%d")
		and LefthyToolsDB.fixedTold["Bob Stone / an old one"] == nil, "another day: told again (and other days' marks go)")

	-- Never in a fight: mine, or hers.
	mark = #GAMEDATA + 1
	Advance(4)
	EnterCombat()
	annaReports(report("0.7.0-24-g121bdc3", "ADDON_ACTION_BLOCKED: UNKNOWN()()", "State: combat yes"))
	Advance(6)
	check(#toAnna(mark, "M2;") == 0, "in my fight: it waits")
	LeaveCombat()
	Advance(1)
	lines = toAnna(mark, "M2;")
	check(#lines == 1 and lines[1]:find("should be fixed in build 0.7.0-62", 1, true), "after it: told, \"should be fixed\"")
	mark = #GAMEDATA + 1
	anna("S2;C;;;;;")
	annaReports(report("0.7.0-24-g121bdc3", "ADDON_ACTION_FORBIDDEN: UNKNOWN()()", panel))
	Advance(6)
	check(peers()[11].combat and #toAnna(mark, "M2;") == 0, "in her fight: it waits")
	anna("S2;;;;;;")
	Advance(1)
	check(#toAnna(mark, "M2;") == 1, "after hers: told")

	-- A German client's report: her line in German.
	mark = #GAMEDATA + 1
	LefthyToolsDB.fixedTold = nil
	Advance(4)
	annaReports(report("0.7.0-24-g121bdc3", "ADDON_ACTION_FORBIDDEN: IsUserOAuthed()()", panel, "deDE"))
	Advance(1)
	lines = toAnna(mark, "M2;")
	check(#lines == 1 and lines[1]:find("Dein gemeldeter Fehler (eine blockierte Aktion in Blizzards Einstellungen) ist in Build 0.7.0-34 behoben.", 1, true),
		"German client: the German line")

	-- She updated meanwhile (her report waited from an older session): nothing to tell.
	mark = #GAMEDATA + 1
	LefthyToolsDB.fixedTold = nil
	anna("V2;0.7.0-34-gdf90faf")
	Advance(4)
	annaReports(report("0.7.0-24-g121bdc3", "ADDON_ACTION_FORBIDDEN: IsUserOAuthed()()", panel))
	Advance(6)
	check(#toAnna(mark, "M2;") == 0 and #toAnna(mark, "B2;bf") == 0 and not LefthyToolsDB.fixedTold,
		"a report from her old build, but she runs the fixed one now: not told")

	-- A build that reads Beacon's word gets that instead (a fix newer than hers, for the test).
	table.insert(BB.FIXED_ERRORS, { pattern = "A TEST ERROR", fixed = "0.7.0-90-g1234567", sure = true, en = "a test error", de = "ein Testfehler" })
	anna("V2;0.7.0-60-gabcdef0")
	annaReports(report("0.7.0-62-gabcdef0", "A TEST ERROR here", "", "deDE"))
	Advance(1)
	check(#toAnna(mark, "M2;") == 0 and toAnna(mark, "B2;bf;")[1] == "B2;bf;0.7.0-90-g1234567;1;a test error",
		"a friend whose build reads it: B2;bf, no LTC line")
	table.remove(BB.FIXED_ERRORS)

	-- Not collecting: nothing (what waited for a fight's end goes too).
	mark = #GAMEDATA + 1
	LefthyToolsDB.fixedTold = nil
	anna("V2;0.7.0-24-g121bdc3")
	Advance(4)
	EnterCombat()
	annaReports(report("0.7.0-24-g121bdc3", "ADDON_ACTION_FORBIDDEN: IsUserOAuthed()()", panel))
	Advance(1)
	B("collectReports"):SetValue(false)
	LeaveCombat()
	Advance(1)
	annaReports(report("0.7.0-24-g121bdc3", "ADDON_ACTION_FORBIDDEN: IsUserOAuthed()()", panel))
	Advance(6)
	check(#toAnna(mark, "M2;") == 0 and not LefthyToolsDB.fixedTold, "collecting off: no one is told")

	-- The friend's side: a collector's B2;bf, while my build is older than the fix.
	pmark = #PRINTED + 1
	anna("Y2;1")
	anna("B2;bf;0.7.0-90-g1234567;1;a test error")
	Advance(1)
	check(printedSince(pmark):find("the error you reported (a test error) is fixed in build 0.7.0-90 (you have " .. LT.version
		.. "). Update with Update-LefthyTools.cmd and restart the game.", 1, true), "a collector's word: one line in my chat")
	pmark = #PRINTED + 1
	Advance(4)
	anna("B2;bf;0.7.0-91-g1234567;0;another")
	Advance(4)
	check(printedSince(pmark):find("(another) should be fixed in build 0.7.0-91", 1, true), "\"should be fixed\" as sent")
	pmark = #PRINTED + 1
	anna("B2;bf;" .. LT.version .. ";1;mine") -- (not newer than mine)
	Advance(4)
	anna("B2;bf;nonsense;1;broken")
	Advance(4)
	anna("B2;bf;0.7.0-92-g1234567;1") -- (a field short)
	Advance(4)
	anna("Y2;0")
	anna("B2;bf;0.7.0-93-g1234567;1;not a collector")
	Advance(4)
	check(not printedSince(pmark):find("the error you reported", 1, true), "my build has it, a broken one, or not from a collector: nothing")
	check(Beacon.enabled and peers()[11], "Anna is still a friend with the addon (nothing broken)")
end
