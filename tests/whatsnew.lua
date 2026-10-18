-- Core: the what's new window.
local suite = ...
local check, section, ns, LT, lefthy = suite.check, suite.section, suite.ns, suite.LT, suite.lefthy

section("what's new")
local news = ns.CHANGELOG
local MODULES = { mirage = true, tweaks = true, beacon = true, chronicle = true, bestiary = true, general = true }
local goodData = #news > 0
for i, e in ipairs(news) do
	goodData = goodData and e.id == i and (e.version == nil or LT.ParseVersion(e.version) ~= nil) and MODULES[e.module]
	-- Lustre style: a version only once tagged, so no versioned entry after an unversioned one.
	goodData = goodData and not (e.version and i > 1 and news[i - 1].version == nil)
	for _, lang in ipairs({ e.en, e.de }) do
		goodData = goodData and type(lang) == "table" and type(lang[1]) == "string" and lang[1] ~= ""
			and type(lang[2]) == "string" and lang[2] ~= "" and #lang[1] <= 40
	end
end
check(goodData, "changelog: ids 1, 2, 3, ... in order, each with a tagged version (or none yet), a module, and a short title and a sentence in English and German")
check(LT.freshInstall and not (LefthyToolsNewsFrame and LefthyToolsNewsFrame:IsShown()),
	"a new install doesn't get a what's-new window")
LefthyToolsDB.changelogSeen = #news - 2 -- two entries arrived with an update
STATE.combat = true
LT.WhatsNew.Schedule()
Advance(4)
check(not (LefthyToolsNewsFrame and LefthyToolsNewsFrame:IsShown()), "not in combat")
STATE.combat = false
Advance(5)
local newsText = LefthyToolsNewsFrame and LefthyToolsNewsFrame.plain or ""
check(LefthyToolsNewsFrame and LefthyToolsNewsFrame:IsShown(), "after combat: the window opens by itself")
local function entryLine(e) return "- " .. e.en[1] .. ": " .. e.en[2] end -- (another entry's text may name a title)
check(newsText:find(entryLine(news[#news]), 1, true) and newsText:find(entryLine(news[#news - 1]), 1, true)
	and not newsText:find(entryLine(news[#news - 2]), 1, true), "only the entries not seen yet")
check(news[#news].version or newsText:sub(1, 29) == "LefthyTools 0.4.0-3-gabc1234\n",
	"entries since the last tagged version: under the installed build (no made-up version), got " .. newsText)
check(LefthyToolsDB.changelogSeen == #news, "and they count as seen")
check(LefthyToolsNewsFrame.Subtitle:GetText():find("0.4.0-3-gabc1234", 1, true), "the window shows the installed build")
LefthyToolsNewsFrame.AllButton:Click()
newsText = LefthyToolsNewsFrame.plain
check(newsText:find(news[1].en[1], 1, true) and not LefthyToolsNewsFrame.AllButton:IsShown(), "'All changes' shows everything")
local order = {}
local release = newsText:sub((newsText:find("LefthyTools 0.5.0", 1, true))) -- (newer versions come first)
for _, heading in ipairs({ "Mirage", "Misc Tweaks", "Beacon", "Chronicle", "General" }) do
	local _, count = release:gsub("\n" .. heading .. "\n", "")
	order[#order + 1] = count == 1 and release:find("\n" .. heading .. "\n", 1, true) or -1
end
check(order[1] > 0 and order[1] < order[2] and order[2] < order[3] and order[3] < order[4] and order[4] < order[5],
	"in a version: grouped by module, each heading once, in a fixed order, got\n" .. newsText)
check(newsText:find("LefthyTools 0.4.0-3-gabc1234", 1, true) < newsText:find("LefthyTools 0.5.0", 1, true),
	"the newest first: what came after the last tag, then the tagged versions")
check(newsText:find("\nBeacon\n- Friends in your group: ", 1, true) and newsText:find("- Level progress: ", 1, true),
	"each entry: a short title and a sentence")
local drawn = {}
for _, fs in ipairs(LefthyToolsNewsFrame.fontPool) do if fs:IsShown() then drawn[#drawn + 1] = fs:GetText() end end
local entryDrawn, bullets = false, 0
for _, text in ipairs(drawn) do
	if text == "Death alerts\n|cffbbbbbb" .. news[7].en[2] .. "|r" then entryDrawn = true end
	if text:find("•", 1, true) then bullets = bullets + 1 end
end
check(entryDrawn and bullets == #news and LefthyToolsNewsFrame.dividerPool[1]:IsShown(),
	"drawn as a heading with a divider, module headings, and a bullet, title and sentence per entry")
LefthyToolsNewsFrame:Hide()
lefthy("news")
check(LefthyToolsNewsFrame:IsShown() and LefthyToolsNewsFrame.plain:find(news[1].en[1], 1, true), "/lefthy news")
LefthyToolsNewsFrame:Hide()
SETTINGS_BUTTONS["What's new"].onClick()
check(LefthyToolsNewsFrame:IsShown(), "the settings overview's What's new button")
LefthyToolsNewsFrame:Hide()
Advance(10)
check(not LefthyToolsNewsFrame:IsShown(), "nothing new: it doesn't open again")

-- (Sections down here can let time pass without shifting any other section's timing.)
