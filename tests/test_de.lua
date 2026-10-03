-- German client: the settings panel is built in German, nothing falls back to English.
local failures, passes = 0, 0
local function check(cond, msg)
	if cond then passes = passes + 1 else failures = failures + 1; io.write("  FAIL: " .. msg .. "\n") end
end
io.write("\n== German client (deDE)\n")

MOCK_LOCALE = "deDE"
-- This player switched Mirage on in an earlier session: the saved choice beats the default (off).
-- They also set 40% faded opacity before there was one per element.
LefthyToolsDB = { modules = { mirage = true }, settings = { mirage = { fadedAlpha = 0.4 } } }
MOCK_NO_RETAIL_ATLAS = true -- a client without retail's combo point art: classic gems instead
local ns = {}
for _, file in ipairs(SOURCES) do
	local chunk = assert(load(file.src, "@Interface/AddOns/LefthyTools/" .. file.name)) -- named like in game
	chunk("LefthyTools", ns)
end
Fire("ADDON_LOADED", "LefthyTools")
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD", true, false)
Advance(0.3)

local missing = {}
for key in pairs(ns.L_MISSING) do missing[#missing + 1] = key end
table.sort(missing)
for _, key in ipairs(missing) do io.write("  untranslated: " .. key .. "\n") end
check(#missing == 0, "every settings text looked up while building the panel has a German translation")

local LT = LefthyTools
local function S(variable) return REGISTERED_SETTINGS[variable] end
check(LT:GetModule("mirage").enabled, "a saved 'Mirage on' survives the new default (off)")
local mdb = LefthyToolsDB.settings.mirage
check(mdb.groupAlpha.chat == 0.4 and mdb.groupAlpha.minimap == 0.4 and mdb.fadedAlpha == 0.4,
	"an older faded opacity becomes every element's own")
local comboRow, comboPips, comboStyle = ns.GetComboPointRow()
check(comboRow and comboStyle == "classic" and comboPips[1].Socket and comboPips[1].Socket.path == "Interface\\ComboFrame\\ComboPoint"
	and not comboPips[1].Slash, "no retail combo point art in the client: the classic target-frame gems")
check(S("LefthyTools_beacon_dingSoundKit").name == "Level-Up-Sound", "level-up sound dropdown in German")
check(LT:GetModule("mirage").category.name == "Mirage" and LT:GetModule("tweaks").category.name == "Misc Tweaks"
	and LT:GetModule("beacon").category.name == "Beacon", "module names are never translated")
check(S("LefthyTools_beacon_share").name == "Meine Position teilen", "Beacon settings are German")
check(S("LefthyTools_module_tweaks").name == "Misc Tweaks", "overview switch keeps the module name")
check(S("LefthyTools_mirage_delay").name == "Wartezeit bis zum Ausblenden", "Mirage slider label")
check(S("LefthyTools_mirage_delay").tooltip == "Wie lange du inaktiv sein musst, bis das Interface ausgeblendet wird.",
	"Mirage tooltip")
check(S("LefthyTools_mirage_group_minimap").name == "Minimap", "element group labels")
check(S("LefthyTools_tweaks_movableBags").name == "Verschiebbare Taschen", "Misc Tweaks checkbox")
check(S("LefthyTools_module_tweaks").tooltip:find("Einstellungen: LefthyTools > Misc Tweaks", 1, true) ~= nil,
	"overview tooltip points to the page by its real name")
local headers = table.concat(HEADERS, "|")
check(headers:find("Module", 1, true) and headers:find("Interface sichtbar lassen", 1, true) and headers:find("Taschen", 1, true),
	"section headers are German")
check(BINDING_NAME_LEFTHYTOOLS_MIRAGE_TOGGLE == "Mirage: Interface-Ausblenden an/aus", "keybinding names are German")

-- Style: the terms German players use, not Blizzard's formal ones.
local texts = { headers, BINDING_NAME_LEFTHYTOOLS_MIRAGE_TOGGLE, BINDING_NAME_LEFTHYTOOLS_MIRAGE_PEEK }
for _, setting in pairs(REGISTERED_SETTINGS) do
	texts[#texts + 1] = setting.name
	texts[#texts + 1] = setting.tooltip or ""
end
local all = table.concat(texts, "\n")
for _, formal in ipairs({ "Minikarte", "Oberfläche", "Schlachtzug", "Stärkungszauber", "Schwächungszauber",
		"Abklingzeit", "Begleiter", "Schadensanzeige", "Kleine Anpassungen" }) do
	check(not all:find(formal, 1, true), "no formal term '" .. formal .. "' in the German settings")
end
check(LT.Options.Seconds(1.5) == "1,5 s" and LT.Options.Seconds(3) == "3 s", "German decimal comma on sliders")

GROUP = "party"
QUESTS = { { id = 201, title = "Aufräumen im Koboldlager", objectives = { { text = "0/10 Koboldungeziefer getötet", finished = false } } } }
Fire("QUEST_LOG_UPDATE"); Advance(0.5)
QUESTS[1].objectives[1] = { text = "10/10 Koboldungeziefer getötet", finished = true }
Fire("QUEST_LOG_UPDATE"); Advance(0.5)
check(SENT[1] and SENT[1].msg == "{rt1} [Aufräumen im Koboldlager]: Quest erledigt!",
	"party announcement in German, got: " .. tostring(SENT[1] and SENT[1].msg))
GROUP = "none"

-- Beacon: a friend's tooltip and level-up in German.
Advance(1)
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "S2;C;0;250.0;750.0;Goldshire;Hogger", "WHISPER", 11)
Advance(1.5)
OpenWorldMap(1429)
PINS[1]:OnMouseEnter()
local lines = table.concat(TOOLTIP.lines, "|")
check(lines:find("Level 20", 1, true) and lines:find("Kämpft gegen Hogger", 1, true) and lines:find("355 m südwestlich", 1, true),
	"friend tooltip in German, got " .. lines)
PINS[1]:OnMouseLeave()
local before = #PRINTED
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "L2;21;", "WHISPER", 11)
Advance(0.2)
check(PRINTED[#PRINTED] and PRINTED[#PRINTED]:find("Anna|r hat Level 21 erreicht!", 1, true) and #PRINTED > before,
	"a friend's level-up without their own text uses the German default")
check(S("LefthyTools_beacon_dingText").name == "Level-Up-Nachricht" and SETTINGS_BUTTONS["Nachricht testen"],
	"level-up settings are German")

check(LefthyToolsNewsFrame and LefthyToolsNewsFrame:IsShown()
	and LefthyToolsNewsFrame.TitleContainer.TitleText:GetText() == "Neu in LefthyTools"
	and LefthyToolsNewsFrame.Text:GetText():find(ns.CHANGELOG[1].de, 1, true),
	"an existing install sees what's new after the update, in German")
LefthyToolsNewsFrame:Hide()

LT:GetModule("chronicle"):Toggle()
local cw = LefthyToolsChronicleFrame
check(cw and cw:IsShown() and cw.Tabs.timeline:GetText() == "Zeitleiste" and cw.Tabs.friends:GetText() == "Freunde"
	and cw.Text:GetText():find("|cffffd20003.10.2026|r", 1, true) and cw.Text:GetText():find("Elwynn Forest entdeckt", 1, true),
	"Chronicle in German, with German dates, got " .. tostring(cw and cw.Text:GetText()))
cw.Tabs.stats:Click()
check(cw.Text:GetText():find("Todesstöße", 1, true) and cw.Text:GetText():find("Diese Session", 1, true), "Chronicle statistics in German")
cw:Hide()
check(LT:GetModule("chronicle").category.name == "Chronicle", "Chronicle's name isn't translated either")

LT.Errors.Show()
check(LefthyToolsErrorsFrame.TitleContainer.TitleText:GetText() == "LefthyTools-Fehler", "error window in German")
LefthyToolsErrorsFrame:Hide()

SlashCmdList.LEFTHYTOOLS_MIRAGE("status")
check(#ns.L_MISSING == 0 and next(ns.L_MISSING) == nil, "chat commands don't look up settings texts")
check(#ERRORS == 0, "no errors reported through the error handler")

io.write(string.format("\n%d passed, %d failed (German)\n", passes, failures))
if failures > 0 then error("German tests failed") end
