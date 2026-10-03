local _, ns = ...
local LT = ns.LT
local L = ns.L
local M = LT:GetModule("beacon")
local B = ns.Beacon

-- Level-ups: when I level up, my friends with LefthyTools see my own message ("{name} hit
-- {level}, drinks on me!"); when one of them levels up, I see theirs: big text at the top of
-- the screen, a chat line and a sound. An empty message means "use the default", which each
-- friend sees in their own client language.

local TEXT_MAX = 200     -- bytes on the wire (the text field allows 100 characters)
local TEXT_LETTERS = 100
local TOAST_TIME, TOAST_FADE = 5, 1.5
-- Sounds for a friend's level-up, picked in the settings: celebratory, but not the player's own
-- level-up fanfare (sound kit 888; tried first, it sounded like *you* had levelled).
-- Each one is played by Forever's own UI code, so the client has it. name = chat (English).
local SOUNDS = {
	{ kit = 50111, name = "Boss defeated fanfare", label = L["Boss defeated fanfare"] }, -- UI_RAID_BOSS_DEFEATED (boss banner)
	{ kit = 73277, name = "World quest complete", label = L["World quest complete"] },   -- UI_WORLDQUEST_COMPLETE
	{ kit = 63971, name = "Legendary loot", label = L["Legendary loot"] },               -- UI_LEGENDARY_LOOT_TOAST
	{ kit = 31578, name = "Epic loot", label = L["Epic loot"] },                         -- UI_EPICLOOT_TOAST
	{ kit = 31754, name = "Scenario complete", label = L["Scenario complete"] },         -- UI_SCENARIO_ENDING
	{ kit = 46893, name = "Gentle chime", label = L["Gentle chime"] },                   -- UI_GARRISON_COMMAND_TABLE_FOLLOWER_LEVEL_UP
}
local FALLBACK_SOUND = 18019 -- SOUNDKIT.UI_BNET_TOAST, if the picked one can't play

local function Render(template, name, classFile, level)
	if template == "" then
		template = L["{name} reached level {level}!"]
	end
	local r, g, b = B.ClassColor(classFile)
	local coloured = ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
		math.floor(b * 255 + 0.5), name or "?")
	local text = template:gsub("{name}", function() return coloured end)
	text = text:gsub("{level}", function() return tostring(level) end)
	return text
end

---------------------------------------------------------------------------
-- On screen
---------------------------------------------------------------------------

local toast

local function ToastOnUpdate(self)
	local age = GetTime() - (self.shownAt or 0)
	if age >= TOAST_TIME + TOAST_FADE then
		self:Hide()
	elseif age > TOAST_TIME then
		self:SetAlpha(1 - (age - TOAST_TIME) / TOAST_FADE)
	end
end

local function ShowToast(text)
	if not toast then
		toast = CreateFrame("Frame", nil, UIParent)
		toast:SetSize(900, 56)
		toast:SetPoint("TOP", UIParent, "TOP", 0, -160)
		toast:SetFrameStrata("HIGH")
		toast.Text = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
		toast.Text:SetAllPoints()
		if toast.Text.SetTextScale then
			toast.Text:SetTextScale(1.4) -- big: it's a party
		end
		-- It pops in: from big to its size.
		toast.Pop = toast:CreateAnimationGroup()
		local grow = toast.Pop:CreateAnimation("Scale")
		grow:SetScaleFrom(1.7, 1.7)
		grow:SetScaleTo(1, 1)
		grow:SetDuration(0.35)
		toast:SetScript("OnUpdate", ToastOnUpdate)
	end
	toast.Text:SetText(text)
	toast.shownAt = GetTime()
	toast:SetAlpha(1)
	toast:Show()
	toast.Pop:Play()
end

local function PlayDingSound()
	if not PlaySound(M.db.dingSoundKit) then
		PlaySound(FALLBACK_SOUND)
	end
end

local function Announce(name, classFile, level, template)
	local text = Render(template, name, classFile, level)
	ShowToast(text)
	M:Print(text)
	if M.db.dingSound then
		PlayDingSound()
	end
end

local function Preview()
	local _, classFile = UnitClass("player")
	Announce(UnitName("player"), classFile, (UnitLevel("player") or 0) + 1, B.Clean(M.db.dingText, TEXT_MAX))
end

---------------------------------------------------------------------------
-- Hooks for Beacon.lua
---------------------------------------------------------------------------

-- PLAYER_LEVEL_UP, on the next tick.
function B.AnnounceLevel(level)
	if M.db.dingAnnounce then
		B.QueueToPeers(("L%s;%d;%s"):format(B.VERSION, level, B.Clean(M.db.dingText, TEXT_MAX)))
	end
end

-- A friend's L message, on the next tick.
function B.ShowDing(peer, level, text)
	if M.db.dingShow then
		Announce(peer.name, peer.classFile, level, B.Clean(text, TEXT_MAX))
	end
	B.Notify("level", peer, { level = level })
end

function B.BuildDingOptions(o)
	o:Header(L["Level-ups"])
	o:Checkbox("dingAnnounce", L["Tell my friends when I level up"],
		L["Battle.net friends who also use LefthyTools see your level-up message."])
	B.dingTextSetting = o:TextInput("dingText", L["Level-up message"],
		L["What your friends see when you level up. {name} and {level} are filled in. Leave it empty for the default."],
		{ maxLetters = TEXT_LETTERS })
	o:Button(L["Test your message"], L["Preview"], Preview,
		L["Shows your level-up message the way your friends will see it."])
	o:Checkbox("dingShow", L["Show my friends' level-ups"],
		L["Big text on screen and a chat line when a friend levels up."])
	o:Checkbox("dingSound", L["Play a sound"],
		L["Plays a sound with a friend's level-up message."])
	local values = {}
	for _, sound in ipairs(SOUNDS) do
		values[#values + 1] = { sound.kit, sound.label }
	end
	B.dingSoundSetting = o:Dropdown("dingSoundKit", L["Level-up sound"],
		L["The sound for a friend's level-up. Picking one plays it."], values)
	B.lastSoundKit = M.db.dingSoundKit
end

-- Picking a sound in the settings plays it, on the next frame (not inside the settings callback).
function B.OnSettingChanged()
	if M.db.dingSoundKit ~= B.lastSoundKit then
		B.lastSoundKit = M.db.dingSoundKit
		C_Timer.After(0, PlayDingSound)
	end
end

-- /lefthy beacon sound [<number>]
function B.SoundCommand(arg)
	local index = tonumber(arg)
	local pick = index and SOUNDS[index]
	if pick then
		if M.db.dingSoundKit ~= pick.kit and B.dingSoundSetting then
			B.dingSoundSetting:SetValue(pick.kit) -- keeps the panel in sync; B.OnSettingChanged plays it
		else
			M.db.dingSoundKit, B.lastSoundKit = pick.kit, pick.kit
			PlayDingSound()
		end
		M:Print("level-up sound: " .. pick.name .. ".")
		return
	end
	for i, sound in ipairs(SOUNDS) do
		M:Print(string.format("  %d. %s%s", i, sound.name, sound.kit == M.db.dingSoundKit and " (current)" or ""))
	end
	M:Print("/lefthy beacon sound <number> - pick one and hear it")
end

local function SetText(text)
	text = strtrim(text)
	if B.dingTextSetting then
		B.dingTextSetting:SetValue(text) -- keeps the settings panel in sync
	else
		M.db.dingText = text
	end
end

-- /lefthy beacon ding [<text> | reset | test]
function B.DingCommand(arg)
	local word = arg:lower()
	if word == "test" then
		Preview()
		return
	elseif word == "reset" then
		SetText("")
	elseif arg ~= "" then
		SetText(arg)
	end
	local _, classFile = UnitClass("player")
	M:Print("level-up message" .. (M.db.dingText == "" and " (default)" or "") .. ": "
		.. Render(B.Clean(M.db.dingText, TEXT_MAX), UnitName("player"), classFile, (UnitLevel("player") or 0) + 1))
end
