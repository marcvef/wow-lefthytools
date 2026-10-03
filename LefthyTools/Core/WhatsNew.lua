local _, ns = ...
local LT = ns.LT
local L = ns.L

-- What's new: after an update, a window lists the changelog entries (Data/Changelog.lua) the
-- player hasn't seen yet. Entries have ids instead of versions, so builds between two releases
-- (0.4.0-12-g...) show their news too. LefthyToolsDB.changelogSeen holds the highest id shown;
-- a fresh install starts with everything seen, an existing install without it sees all entries.

local SHOW_DELAY = 3   -- seconds after login, so it doesn't open into the loading screen
local COMBAT_RETRY = 5

local WhatsNew = {}
LT.WhatsNew = WhatsNew

local db

local function LatestID()
	local latest = 0
	for _, entry in ipairs(ns.CHANGELOG or {}) do
		latest = math.max(latest, entry.id)
	end
	return latest
end

local function EntryText(entry)
	return ns.LOCALE == "deDE" and entry.de or entry.en
end

-- "0.5.0", or "0.5.0 (in development)" while the installed build is older than that version.
local function VersionLabel(version)
	local a1, a2, a3 = LT.ParseVersion(version)
	local b1, b2, b3 = LT.ParseVersion(LT.version)
	if a1 and b1 and (a1 > b1 or a1 == b1 and (a2 > b2 or a2 == b2 and a3 > b3)) then
		return L["%s (in development)"]:format(version)
	end
	return version
end

-- Entries with an id above `after`, newest first, under a heading per version.
function WhatsNew.Text(after)
	local lines, lastVersion = {}, nil
	local entries = ns.CHANGELOG or {}
	for i = #entries, 1, -1 do
		local entry = entries[i]
		if entry.id > after then
			if entry.version ~= lastVersion then
				if lastVersion then
					lines[#lines + 1] = ""
				end
				lines[#lines + 1] = "|cffffd200LefthyTools " .. VersionLabel(entry.version) .. "|r"
				lastVersion = entry.version
			end
			lines[#lines + 1] = "- " .. EntryText(entry)
		end
	end
	return table.concat(lines, "\n")
end

function WhatsNew.Show(onlyUnseen)
	local window = WhatsNew.window
	if not window then
		window = LT.Window.Create("LefthyToolsNewsFrame", L["What's new in LefthyTools"], 500, 420)
		window.Subtitle = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		window.Subtitle:SetPoint("TOPLEFT", 16, -34)
		window.Subtitle:SetPoint("TOPRIGHT", -16, -34)
		window.Subtitle:SetJustifyH("LEFT")
		LT.Window.AddText(window)
		window.AllButton = LT.Window.AddButton(window, L["All changes"], function() WhatsNew.Show(false) end)
		WhatsNew.window = window
	end
	local after = onlyUnseen and db and db.changelogSeen or 0
	window.Subtitle:SetText(L["You have LefthyTools %s."]:format(LT.version))
	window:SetBodyText(WhatsNew.Text(after))
	window.AllButton:SetShown(after > 0)
	window:Show()
	if db then
		db.changelogSeen = LatestID()
	end
end

-- Shows the unseen entries, a few seconds after login and never in combat.
local function TryShow()
	if not db or db.changelogSeen >= LatestID() then
		return
	end
	if InCombatLockdown() then
		C_Timer.After(COMBAT_RETRY, TryShow)
		return
	end
	WhatsNew.Show(true)
end

table.insert(LT.onLoad, function(saved)
	db = saved
	if type(db.changelogSeen) ~= "number" then
		db.changelogSeen = LT.freshInstall and LatestID() or 0
	end
end)

function WhatsNew.Schedule()
	C_Timer.After(SHOW_DELAY, TryShow)
end

table.insert(LT.onLogin, WhatsNew.Schedule)
