-- Misc Tweaks: the controller's button symbols.
-- Needs: no other file.
local suite = ...
local check, section, ns, LT, lefthy = suite.check, suite.section, suite.ns, suite.LT, suite.lefthy
local printedSince = suite.printedSince

section("Misc Tweaks: controller button symbols")
do
	local M = LT:GetModule("tweaks")
	local devices = { [5] = { vendorID = 10462, productID = 4866, style = "Generic" } }
	local configs, applied = {}, 0
	local wasPad = C_GamePad
	C_GamePad = {
		GetAllDeviceIDs = function() local ids = {}; for id in pairs(devices) do ids[#ids + 1] = id end; return ids end,
		GetDeviceRawState = function(id) return devices[id] end,
		GetDeviceMappedState = function(id)
			local d = devices[id]
			local c = d and configs[d.vendorID .. ":" .. d.productID]
			return d and { labelStyle = c and c.labelStyle or d.style }
		end,
		SetConfig = function(c) configs[c.configID.vendorID .. ":" .. c.configID.productID] = c end,
		DeleteConfig = function(i) configs[i.vendorID .. ":" .. i.productID] = nil end,
		ApplyConfigs = function() applied = applied + 1 end,
	}
	local function set(value)
		REGISTERED_SETTINGS["LefthyTools_tweaks_gamepadSymbols"]:SetValue(value)
		Advance(0.1)
	end
	local KEY = "10462:4866"
	check(M.db.gamepadSymbols == "default" and not next(configs) and applied == 0, "the default: nothing touched")

	M:OnSettingChanged() -- (as at login: the setting as it is, nothing to say)
	Advance(0.1)
	local said = #PRINTED + 1
	set(3)
	check(printedSince(said):find("/reload", 1, true), "changed: it says to /reload")
	local c = configs[KEY]
	check(M.db.gamepadSymbols == "playstation" and c and c.labelStyle == "Shapes" and applied == 1, "PlayStation: its symbols, applied")
	check(c and #c.rawButtonMappings == 0 and #c.rawAxisMappings == 0 and #c.axisConfigs == 0 and #c.stickConfigs == 0, "nothing but the symbols: the game keeps the mappings")
	check(M.db.padSymbolConfigs[KEY] == true, "remembered, to undo it")

	local before = applied
	M:OnSettingChanged()
	Advance(0.1)
	check(applied == before, "already so: nothing done again")
	said = #PRINTED + 1
	M:OnSettingChanged()
	Fire("GAME_PAD_CONNECTED")
	Advance(0.1)
	check(printedSince(said) == "", "and nothing said")

	set(2)
	check(configs[KEY].labelStyle == "Letters" and applied == before + 1, "Xbox")

	-- Another controller, connected later.
	devices[6] = { vendorID = 1356, productID = 3302, style = "Generic" }
	Fire("GAME_PAD_CONNECTED")
	Advance(0.1)
	check(configs["1356:3302"] and configs["1356:3302"].labelStyle == "Letters", "a controller connected later: the same")

	-- Not in a fight.
	EnterCombat()
	before = applied
	set(3)
	check(configs[KEY].labelStyle == "Letters" and applied == before, "in a fight: it waits")
	LeaveCombat()
	Advance(0.1)
	check(configs[KEY].labelStyle == "Shapes" and applied == before + 1, "after it: done")

	-- Failing calls cost nothing.
	local realSet = C_GamePad.SetConfig
	C_GamePad.SetConfig = function() error("blocked") end
	set(2)
	check(configs[KEY].labelStyle == "Shapes", "the game refusing: no error, nothing changed")
	C_GamePad.SetConfig = realSet
	set(3)

	-- The command, and undoing.
	local mark = #PRINTED + 1
	lefthy("tweaks padsymbols")
	check(printedSince(mark):find("padsymbols xbox", 1, true), "the command: how to use it")
	lefthy("tweaks padsymbols xbox")
	Advance(0.1)
	check(M.db.gamepadSymbols == "xbox" and configs[KEY].labelStyle == "Letters", "the command: Xbox")
	lefthy("tweaks padsymbols default")
	Advance(0.1)
	check(M.db.gamepadSymbols == "default" and not next(configs) and not next(M.db.padSymbolConfigs), "the default: ours deleted, for every controller")
	before = applied
	devices[7] = { vendorID = 1, productID = 2, style = "Generic" }
	Fire("GAME_PAD_CONNECTED")
	Advance(0.1)
	check(not next(configs) and applied == before, "and no more listening")

	-- Module off: undone.
	set(3)
	check(configs[KEY], "(on again)")
	M.enabled = false
	M:OnDisable()
	Advance(0.1)
	check(not next(configs), "Misc Tweaks off: ours are gone")
	M.enabled = true
	M:OnEnable()
	Advance(0.1)
	check(configs[KEY] and configs[KEY].labelStyle == "Shapes", "on again: back")
	set(1)

	-- The button under the setting.
	local reloads, wasReload = 0, ReloadUI
	ReloadUI = function() reloads = reloads + 1 end
	local reload = SETTINGS_BUTTONS["Show the new symbols"]
	check(reload and reload.text == "Reload", "a button under the setting")
	if reload then reload.onClick() end
	check(reloads == 1, "it reloads")
	ReloadUI = wasReload

	-- No such API.
	C_GamePad = nil
	M:OnSettingChanged()
	Advance(0.1)
	C_GamePad = wasPad
end
