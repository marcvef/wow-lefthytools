local _, ns = ...
local LT = ns.LT
local L = ns.L

-- What's new: after an update, a window lists the changelog entries (Data/Changelog.lua) the
-- player hasn't seen yet. Entries have ids instead of versions, so builds between two releases
-- (0.4.0-12-g...) show their news too. LefthyToolsDB.changelogSeen holds the highest id shown;
-- a fresh install starts with everything seen, an existing install without it sees all entries.

local SHOW_DELAY = 3   -- seconds after login, so it doesn't open into the loading screen
local COMBAT_RETRY = 5
-- Sections inside a version, in this order (the overview's module order, then the addon as a whole).
local SECTIONS = { "mirage", "tweaks", "beacon", "chronicle", "general" }
local BULLET_X, TEXT_X = 8, 22  -- an entry's bullet, and its text (wrapped lines stay under the text)
local GAP = { version = 22, section = 14, entry = 8 } -- space above each kind of line

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

-- { title, sentence } in the client's language.
local function EntryText(entry)
	return ns.LOCALE == "deDE" and entry.de or entry.en
end

local function SectionTitle(key)
	local m = key ~= "general" and LT:GetModule(key)
	return m and m.title or L["General"] -- module names are never translated
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

-- The entries with an id above `after` as a list of lines: { kind = "version" | "section" |
-- "entry", text, title }. Versions newest first; in each, a section per module in SECTIONS order;
-- in each section, the entries in the order they were added.
function WhatsNew.Lines(after)
	local versions, byVersion = {}, {}
	for _, entry in ipairs(ns.CHANGELOG or {}) do
		if entry.id > after then
			local v = byVersion[entry.version]
			if not v then
				v = { version = entry.version, sections = {} }
				byVersion[entry.version], versions[#versions + 1] = v, v
			end
			local key = entry.module or "general"
			v.sections[key] = v.sections[key] or {}
			table.insert(v.sections[key], entry)
		end
	end
	table.sort(versions, function(a, b) return LT.CompareVersions(a.version, b.version) == 1 end)
	local lines = {}
	for _, v in ipairs(versions) do
		lines[#lines + 1] = { kind = "version", text = "LefthyTools " .. VersionLabel(v.version) }
		for _, key in ipairs(SECTIONS) do
			for i, entry in ipairs(v.sections[key] or {}) do
				if i == 1 then
					lines[#lines + 1] = { kind = "section", text = SectionTitle(key) }
				end
				local text = EntryText(entry)
				lines[#lines + 1] = { kind = "entry", title = text[1], text = text[2] }
			end
		end
	end
	return lines
end

-- The same as plain text (for tests and the record).
function WhatsNew.Text(after)
	local out = {}
	for _, line in ipairs(WhatsNew.Lines(after)) do
		out[#out + 1] = line.kind == "entry" and ("- " .. line.title .. ": " .. line.text) or line.text
	end
	return table.concat(out, "\n")
end

-- Draws the lines into the scroll area: a large gold heading and a divider per version, a
-- heading per module, and each entry as a bullet with its title on top and the sentence below.
-- Font strings and dividers are pooled and reused.
local function Render(window, lines)
	local content, width = window.Content, window.Content:GetWidth()
	local fonts, dividers, usedFonts, usedDividers = window.fontPool, window.dividerPool, 0, 0
	local function Font(font, x, y, w)
		usedFonts = usedFonts + 1
		local fs = fonts[usedFonts]
		if not fs then
			fs = content:CreateFontString(nil, "OVERLAY")
			fs:SetJustifyH("LEFT")
			fs:SetJustifyV("TOP")
			fonts[usedFonts] = fs
		end
		fs:SetFontObject(font)
		fs:SetWidth(w)
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
		fs:Show()
		return fs
	end
	local y = 0
	for i, line in ipairs(lines) do
		if i > 1 then
			y = y + GAP[line.kind]
		end
		if line.kind == "version" then
			local fs = Font("GameFontNormalLarge", 0, y, width)
			fs:SetText(line.text)
			y = y + fs:GetStringHeight() + 4
			usedDividers = usedDividers + 1
			local divider = dividers[usedDividers]
			if not divider then
				divider = content:CreateTexture(nil, "ARTWORK")
				divider:SetColorTexture(1, 0.82, 0, 0.35)
				divider:SetHeight(1)
				dividers[usedDividers] = divider
			end
			divider:ClearAllPoints()
			divider:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
			divider:SetWidth(width)
			divider:Show()
			y = y + 1
		elseif line.kind == "section" then
			local fs = Font("GameFontNormal", 0, y, width)
			fs:SetText("|cff80c0ff" .. line.text .. "|r")
			y = y + fs:GetStringHeight()
		else
			Font("GameFontHighlight", BULLET_X, y, TEXT_X - BULLET_X):SetText("|cffffd200•|r")
			local fs = Font("GameFontHighlight", TEXT_X, y, width - TEXT_X)
			fs:SetText(line.title .. "\n|cffbbbbbb" .. line.text .. "|r")
			y = y + fs:GetStringHeight()
		end
	end
	for j = usedFonts + 1, #fonts do
		fonts[j]:Hide()
	end
	for j = usedDividers + 1, #dividers do
		dividers[j]:Hide()
	end
	content:SetHeight(math.max(y + 10, 10))
	window.Scroll:SetVerticalScroll(0)
end

function WhatsNew.Show(onlyUnseen)
	local window = WhatsNew.window
	if not window then
		window = LT.Window.Create("LefthyToolsNewsFrame", L["What's new in LefthyTools"], 540, 480)
		window.Subtitle = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		window.Subtitle:SetPoint("TOPLEFT", 16, -34)
		window.Subtitle:SetPoint("TOPRIGHT", -16, -34)
		window.Subtitle:SetJustifyH("LEFT")
		window.Scroll, window.Content = LT.Window.AddScroll(window)
		window.fontPool, window.dividerPool = {}, {}
		window.AllButton = LT.Window.AddButton(window, L["All changes"], function() WhatsNew.Show(false) end)
		WhatsNew.window = window
	end
	local after = onlyUnseen and db and db.changelogSeen or 0
	window.Subtitle:SetText(L["You have LefthyTools %s."]:format(LT.version))
	Render(window, WhatsNew.Lines(after))
	window.plain = WhatsNew.Text(after)
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
