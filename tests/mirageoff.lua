-- Mirage's engine hiding elements for another part while Mirage is off.
local suite = ...
local check, a, section, LT, lefthy = suite.check, suite.a, suite.section, suite.LT, suite.lefthy
local Mirage = LT:GetModule("mirage")

section("Mirage: another part's hiding with Mirage off")
do
	local wasOn = Mirage.enabled
	if wasOn then
		lefthy("disable mirage")
		Advance(3)
	end
	Mirage:HideGroups("test", { chat = true }, 0)
	Advance(0.3)
	check(a("ChatFrame1") == 0 and a("MainActionBar") == 1, "Mirage off: the chat goes for the film, the rest stays")
	local whisper = FCF_OpenTemporaryWindow() -- a whisper in a window of its own
	Advance(0.5)
	check(whisper:GetAlpha() == 0, "a chat window opening during the film goes with the chat, got " .. whisper:GetAlpha())
	Mirage:HideGroups("test", nil, 0)
	Advance(0.5)
	check(whisper:GetAlpha() == 1 and a("ChatFrame1") == 1, "after the film: back")
	FCF_Close(whisper)
	if wasOn then
		lefthy("enable mirage")
		Advance(0.5)
	end
end
