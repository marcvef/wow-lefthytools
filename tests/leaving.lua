-- Beacon: a friend switching it off, and switching it off and on here.
local suite = ...
local check, section, ns, LT, lefthy = suite.check, suite.section, suite.ns, suite.LT, suite.lefthy
local printedSince, peers = suite.printedSince, suite.peers
local BB = ns.Beacon
local function updateStatus() -- the settings overview's Updates row
	for _, init in ipairs(LAYOUTS["LefthyTools"]) do
		if init.template == "LefthyToolsSettingsInfoTemplate" and init.data.name == "Updates" then return init.data.getValue() end
	end
end
local mark, pmark

section("Beacon: leaving")
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "Q2", "WHISPER", 12)
Advance(0.15)
check(not peers()[12] and peers()[11], "a friend switching Beacon off (Q2) is forgotten")
-- A reserved item at a vendor, then Beacon goes off (below).
local owedList = LefthyToolsDB.handover
BB.AddHandover("1155::::::::20:::::", ItemLink(1155), "Bob", "Player-1-12", 12)
BAGS[0] = { [3] = 1155 }
OpenBags()
Fire("MERCHANT_SHOW")
Advance(0.1)
local reservedButton = ContainerFrameCombinedBags.buttons[3]
check(reservedButton.LefthyToolsReserved:IsShown() and reservedButton.LefthyToolsSellGuard:IsShown(), "a reserved item at a vendor, Beacon on")
mark = #GAMEDATA + 1
MOCK_SEND_RESULT = 3 -- the server is throttling right now
local mapProviders = {} -- (Beacon's and others' on the world map)
for p in pairs(WorldMapFrame.providers) do mapProviders[p] = true end
lefthy("disable beacon")
check(#GameDataTo(11, mark) == 0, "switching off sends nothing inside the settings callback")
Advance(1)
check(#GameDataTo(11, mark) == 0, "throttled: the goodbye waits")
MOCK_SEND_RESULT = nil
Advance(3)
check(GameDataTo(11, mark)[1] == "Q2", "... and then tells friends (through the rate limiter, not lost)")
local providersLeft, providersGone = 0, 0
for p in pairs(mapProviders) do
	if WorldMapFrame.providers[p] then providersLeft = providersLeft + 1 else providersGone = providersGone + 1 end
end
check(providersGone == 2 and providersLeft == 1 and next(BB.GetMinimapPins()) == nil,
	"and removes the dots from both maps (its two map providers go, the quest map's stays)")
check(not reservedButton.LefthyToolsReserved:IsShown() and not reservedButton.LefthyToolsSellGuard:IsShown(),
	"and the reserved item's border and vendor question")
pmark = #PRINTED + 1
TRADE_PARTNER, PARTY.NPC = "Bob", { guid = "Player-1-12" }
Fire("TRADE_SHOW")
SendMailFrame:Show()
SendMailNameEditBox:SetText("")
MAIL_ITEMS = { 1155 }
Fire("MAIL_SEND_INFO_UPDATE")
BAGS[0][3] = nil
Fire("BAG_UPDATE_DELAYED")
Advance(0.1)
check(printedSince(pmark) == "" and SendMailNameEditBox:GetText() == "", "while off: no trade nudge, no mail help, no vendor warning, got " .. printedSince(pmark))
BAGS[0][3] = 1155
SendMailFrame:Hide()
MAIL_ITEMS, TRADE_PARTNER, PARTY.NPC = {}, nil, nil
mark = #GAMEDATA + 1
Fire("BN_CHAT_MSG_ADDON", "LTBeacon", "H2", "WHISPER", 11)
Advance(5)
check(#GameDataTo(11, mark) == 0, "while off: no answers, no positions")
local seenNewer = LT.newerVersion
LT.newerVersion = nil
check(updateStatus():find("Unknown (Beacon is off)", 1, true), "update status with Beacon off: unknown")
LT.newerVersion = seenNewer
do -- Beacon's /lefthy words while it's off: they answer as they always did (no time passes here).
	pmark = #PRINTED + 1
	lefthy("announce hello")
	lefthy("stream watch anna")
	check(printedSince(pmark):find("Beacon is off: /lefthy enable beacon.", 1, true)
		and printedSince(pmark):find("no friend called anna online with LefthyTools.", 1, true),
		"Beacon off: /lefthy announce and /lefthy stream say why nothing happens, got " .. printedSince(pmark))
	lefthy("reports")
	check(LefthyToolsReportsFrame:IsShown(), "... and /lefthy reports still shows the collected ones")
	LefthyToolsReportsFrame:Hide()
end
lefthy("enable beacon")
Advance(0.15)
check(next(WorldMapFrame.providers) ~= nil, "on again: back on the map")
check(reservedButton.LefthyToolsReserved:IsShown() and reservedButton.LefthyToolsSellGuard:IsShown(),
	"and the reserved item's border and vendor question")
Fire("MERCHANT_CLOSED")
wipe(owedList)
BAGS = { [0] = {} }
CloseBags()
Advance(0.1)
