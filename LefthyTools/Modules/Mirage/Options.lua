local _, ns = ...
local LT = ns.LT
local L = ns.L
local M = LT:GetModule("mirage")
local data = ns.MirageData
local Seconds, Percent = LT.Options.Seconds, LT.Options.Percent

BINDING_NAME_LEFTHYTOOLS_MIRAGE_TOGGLE = L["Mirage: toggle interface fading"]
BINDING_NAME_LEFTHYTOOLS_MIRAGE_PEEK = L["Mirage: show interface (hold)"]

function M:BuildOptions(o)
	o:Header(L["Timing"])
	o:Slider("delay", L["Idle delay"],
		L["How long you must be inactive before the interface starts fading."],
		0, 30, 0.5, Seconds)
	o:Slider("fadeOutTime", L["Fade-out duration"],
		L["How long the fade-out takes once it starts."],
		0, 10, 0.1, Seconds)
	o:Slider("fadeInTime", L["Fade-in duration"],
		L["How long the interface takes to come back."],
		0, 2, 0.05, Seconds)
	o:Slider("fadedAlpha", L["Faded opacity"],
		L["Opacity of faded elements. 0% hides them completely. Sets every element at once; change single elements under Elements to fade."],
		0, 1, 0.05, Percent)

	o:Header(L["Keep the interface visible"])
	o:Checkbox("showWithTarget", L["While you have a target"],
		L["Any living target keeps the interface visible."])
	o:Checkbox("hostileTargetOnly", L["Only for attackable targets"],
		L["Only count targets you can attack (requires the option above)."])
	o:Checkbox("showWithWindows", L["While a window is open"],
		L["Bags, map, character sheet, vendors, quest dialogs and other windows."])
	o:Checkbox("showWhenDead", L["While dead or a ghost"])
	o:Checkbox("showWhileMoving", L["While moving"],
		L["Off by default: running around counts as idle, like Dune's Dynamic HUD."])

	o:Header(L["Reveal briefly"])
	o:Checkbox("mouseover", L["On mouseover"],
		L["Hovering where a faded element sits reveals that element."])
	o:Checkbox("showRegen", L["Player frame while regenerating"],
		L["Show the player frame while health or mana is ticking back up out of combat."])
	o:Checkbox("chatOnMessage", L["Chat on new messages"],
		L["Whispers, party, raid, guild and instance messages briefly reveal the chat."])

	o:Header(L["Elements to fade"])
	for _, g in ipairs(data.GROUPS) do
		o:CheckboxSlider(g.key, g.label, L["Fade this element when idle."],
			g.key, L["Faded opacity"], L["How much of this element stays visible when faded. 0% hides it."],
			0, 1, 0.05, Percent,
			{ tbl = self.db.groups, default = self.defaults.groups[g.key], id = "group_" .. g.key },
			{ tbl = self.db.groupAlpha, default = self.defaults.groupAlpha[g.key], id = "alpha_" .. g.key })
	end
	o:Checkbox("hideMinimapWhenFaded", L["Also hide minimap quest areas"],
		L["Quest areas on the minimap ignore transparency, so the minimap is hidden once it has faded out. Only applies when the minimap fades to 0%."])
	o:Slider("minimapHideAt", L["Hide quest areas at"],
		L["Minimap opacity at which the minimap and its quest areas are hidden during the fade-out. 0% waits until the fade has finished."],
		0, 1, 0.01, Percent)
end

---------------------------------------------------------------------------
-- /mirage (also /lefthy mirage ...)
---------------------------------------------------------------------------

local HELP = {
	"/mirage - open settings",
	"/mirage on | off | toggle - enable or disable the module",
	"/mirage delay <seconds> - idle time before fading starts",
	"/mirage fade <seconds> - how long the fade-out takes",
	"/mirage fadein <seconds> - how long the fade-in takes",
	"/mirage alpha <0-100> - faded opacity in percent, for every element",
	"/mirage overlay <0-100> - minimap opacity at which its quest areas are hidden",
	"/mirage groups - list elements; /mirage group <name> on|off|<0-100> (faded opacity of one element)",
	"/mirage status - show what's keeping the interface visible",
	"/mirage reset - restore defaults",
}

local function SetNumber(key, value, minValue, maxValue, label, formatter)
	local n = tonumber(value)
	if not n then
		M:Print(label .. " is " .. formatter(M.db[key]) .. ".")
		return
	end
	LT:SetModuleSetting(M, key, math.max(minValue, math.min(maxValue, n))) -- runs OnSettingChanged
	M:Print(label .. " set to " .. formatter(M.db[key]) .. ".")
end

local function SetPercent(key, value, label)
	local n = tonumber(value)
	SetNumber(key, n and n / 100, 0, 1, label, Percent)
end

local function ListGroups()
	for _, g in ipairs(data.GROUPS) do
		M:Print(string.format("  %s%s|r - %s (%d frames, fades to %s)",
			M.db.groups[g.key] and "|cff80ff80" or "|cffff8080", g.key, g.label, #M:GetGroup(g.key).live,
			Percent(M.db.groupAlpha[g.key])))
	end
end

local function Status()
	local db = M.db
	local s = M:GetStatus()
	local state
	if not M.enabled then
		state = "disabled"
	elseif s.peek then
		state = "peeking (key held)"
	elseif s.reason then
		state = "visible: " .. s.reason
	elseif s.idleFor < db.delay then
		state = string.format("visible: fading in %.1f s", db.delay - s.idleFor)
	else
		state = "idle (faded)"
	end
	M:Print(state)
	M:Print(string.format("delay %s, fade-out %s, fade-in %s, faded opacity %s, quest area cutoff %s",
		Seconds(db.delay), Seconds(db.fadeOutTime), Seconds(db.fadeInTime), Percent(db.fadedAlpha),
		Percent(db.minimapHideAt)))
	for _, g in ipairs(data.GROUPS) do
		local group = M:GetGroup(g.key)
		M:Print(string.format("  %s: %d frames, alpha %.2f%s", g.key, #group.live, group.alpha,
			db.groups[g.key] and (", fades to " .. Percent(db.groupAlpha[g.key])) or " (not faded)"))
	end
end

function M:OnSlashCommand(msg)
	local cmd, arg, arg2 = strsplit(" ", strtrim(msg or ""):lower(), 3)
	if cmd == "" or cmd == "config" or cmd == "options" then
		LT:OpenSettings(self)
	elseif cmd == "on" or cmd == "off" then
		LT:SetModuleEnabled(self.key, cmd == "on")
	elseif cmd == "toggle" then
		LT:ToggleModule(self.key)
	elseif cmd == "delay" then
		SetNumber("delay", arg, 0, 300, "Idle delay", Seconds)
	elseif cmd == "fade" or cmd == "fadeout" then
		SetNumber("fadeOutTime", arg, 0, 60, "Fade-out duration", Seconds)
	elseif cmd == "fadein" then
		SetNumber("fadeInTime", arg, 0, 10, "Fade-in duration", Seconds)
	elseif cmd == "alpha" then
		SetPercent("fadedAlpha", arg, "Faded opacity")
	elseif cmd == "overlay" then
		SetPercent("minimapHideAt", arg, "Minimap quest area cutoff")
	elseif cmd == "groups" then
		ListGroups()
	elseif cmd == "group" then
		if not arg or self.db.groups[arg] == nil then
			self:Print("unknown element. Choose one of:")
			ListGroups()
			return
		end
		local percent = tonumber(arg2)
		if percent then
			LT:SetModuleSetting(self, "alpha_" .. arg, math.max(0, math.min(100, percent)) / 100, self.db.groupAlpha, arg)
			self:Print(arg .. " fades to " .. Percent(self.db.groupAlpha[arg]) .. ".")
			return
		end
		local on
		if arg2 == "on" then
			on = true
		elseif arg2 == "off" then
			on = false
		else
			on = not self.db.groups[arg]
		end
		LT:SetModuleSetting(self, "group_" .. arg, on, self.db.groups, arg)
		self:Print(arg .. (self.db.groups[arg] and " will fade." or " stays visible."))
	elseif cmd == "status" then
		Status()
	elseif cmd == "reset" then
		self:ResetSettings()
		self:Print("settings reset to defaults.")
	else
		for _, line in ipairs(HELP) do
			self:Print(line)
		end
	end
end

SLASH_LEFTHYTOOLS_MIRAGE1 = "/mirage"
SlashCmdList.LEFTHYTOOLS_MIRAGE = function(msg)
	if M.db then
		M:OnSlashCommand(msg)
	end
end
