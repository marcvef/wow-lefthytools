-- Misc Tweaks: who has aggro, on enemy nameplates.
local suite = ...
local check, section, ns, lefthy = suite.check, suite.section, suite.ns, suite.lefthy
local printedSince = suite.printedSince

section("Misc Tweaks: who has aggro, on enemy nameplates")
;(function()
	local function tagText(unit) local t = ns.GetAggroTag(unit); return t and t:IsShown() and t.Text:GetText() or nil end
	local function same(unit, r, g, b)
		local t = ns.GetAggroTag(unit)
		local c = t and t.Text.color
		return c ~= nil and math.abs(c[1] - r) < 0.01 and math.abs(c[2] - g) < 0.01 and math.abs(c[3] - b) < 0.01
	end
	check(LefthyToolsDB.settings.tweaks.aggroNameplate == true, "on by default")
	-- A party: me (the tank), Annabelle (healer), Ölrik (damage), two mobs fighting us.
	GROUP = "party"
	PARTY.party1 = { name = "Annabelle", guid = "Player-1-31" }
	PARTY.party2 = { name = "Ölrik", guid = "Player-1-32" }
	ROLES = { player = "TANK", party1 = "HEALER", party2 = "DAMAGER" }
	MOBS.nameplate1 = { name = "Defias Thug", guid = "Creature-0-1-0-1-120-00000001", combat = true, attacking = true,
		x = 0.5, y = 0.5, pinned = true }
	MOBS.nameplate2 = { name = "Defias Thug", guid = "Creature-0-1-0-1-120-00000002", combat = true, targetGUID = "Player-1-32",
		x = 0.6, y = 0.5, pinned = true }
	THREAT.nameplate1, THREATS["party2>nameplate2"] = 3, 3
	Fire("GROUP_ROSTER_UPDATE")
	Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
	Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
	Advance(0.1)
	local tag = ns.GetAggroTag("nameplate1")
	check(tagText("nameplate1") == ">YOU<" and same("nameplate1", 0.35, 0.62, 1) and tag:GetParent() == MOBS.nameplate1.unitFrame
		and select(1, tag:GetPoint(1)) == "LEFT", "on me: >YOU< in my role's colour (tank blue), at the left end of its health bar")
	check(tagText("nameplate2") == "Ölr" and same("nameplate2", 1, 0.32, 0.26),
		"on a damage dealer: the first three letters of the name (whole letters), red")
	-- Its target is the healer, but I'm the one tanking it (a spell at her): me.
	MOBS.nameplate2.targetGUID = "Player-1-31"
	THREATS["party1>nameplate2"], THREATS["party2>nameplate2"], THREAT.nameplate2 = 1, 0, 3
	Fire("UNIT_TARGET", "nameplate2")
	Advance(0.1)
	check(tagText("nameplate2") == ">YOU<", "its target isn't tanking it (a spell at the healer): whoever is, me")
	THREATS["party1>nameplate2"], THREAT.nameplate2 = 3, 1
	Fire("UNIT_THREAT_LIST_UPDATE", "nameplate2")
	Advance(0.1)
	check(tagText("nameplate2") == "Ann" and same("nameplate2", 0.3, 0.95, 0.4), "the healer has it: Ann, green")
	-- No roles (a group made by hand): white; a bear is a tank anyway.
	ROLES = {}
	Fire("PLAYER_ROLES_ASSIGNED")
	Advance(0.1)
	check(same("nameplate2", 0.92, 0.92, 0.92), "no roles: white")
	AURAS.party1 = { ["Bear Form"] = true, [C_Spell.GetSpellInfo(5487).name] = true } -- (other tests rename spells)
	Fire("PLAYER_REGEN_DISABLED") -- (roles are guessed again when a fight starts)
	Advance(0.1)
	check(same("nameplate2", 0.35, 0.62, 1), "in Bear Form: a tank")
	Fire("PLAYER_REGEN_ENABLED")
	AURAS.party1 = nil
	-- Threat secret and its target not known: nothing said.
	THREATS["party1>nameplate2"], THREAT.nameplate2, MOBS.nameplate2.targetGUID = SECRET, SECRET, nil
	Fire("UNIT_THREAT_LIST_UPDATE", "nameplate2")
	Advance(0.1)
	check(tagText("nameplate2") == nil, "nothing readable: no tag")
	-- Someone outside the group (an escort): grey.
	MOBS.nameplate2.targetGUID, MOBS.nameplate2.targetName = "Creature-0-1-0-1-467-00000009", "The Defias Traitor"
	Fire("UNIT_TARGET", "nameplate2")
	Advance(0.1)
	check(tagText("nameplate2") == "The" and same("nameplate2", 0.6, 0.6, 0.6), "on someone outside the group: grey")
	-- Out of combat, or solo: nothing.
	MOBS.nameplate2.combat = false
	Fire("UNIT_FLAGS", "nameplate2")
	Advance(0.1)
	check(tagText("nameplate2") == nil, "a mob out of combat: no tag")
	GROUP = "none"
	Fire("GROUP_ROSTER_UPDATE")
	Advance(0.1)
	check(tagText("nameplate1") == nil, "solo: no tags")
	-- While I'm in combat in a group it looks again twice a second, also without events.
	GROUP, STATE.combat = "party", true
	Fire("PLAYER_REGEN_DISABLED")
	Advance(0.1)
	check(tagText("nameplate1") == ">YOU<", "in a group again: back")
	MOBS.nameplate1.attacking, THREAT.nameplate1, THREATS["party2>nameplate1"] = false, 0, 3
	MOBS.nameplate1.targetGUID = "Player-1-32"
	Advance(0.6)
	check(tagText("nameplate1") == "Ölr", "no event, but in combat: seen within half a second")
	STATE.combat = false
	Fire("PLAYER_REGEN_ENABLED")
	-- Like the game: the combat lockdown begins only after PLAYER_REGEN_DISABLED, so inside it
	-- InCombatLockdown still says no.
	Fire("PLAYER_REGEN_DISABLED")
	STATE.combat = true
	Advance(0.1)
	MOBS.nameplate1.targetGUID, THREATS["party1>nameplate1"] = "Player-1-31", 3
	Advance(0.6)
	check(tagText("nameplate1") == "Ann", "a fight starting: the half-second looks begin (combat taken from the event)")
	STATE.combat = false
	Fire("PLAYER_REGEN_ENABLED")
	THREATS["party1>nameplate1"] = nil
	-- The examples: each enemy nameplate another one, for ten seconds.
	local pmark = #PRINTED + 1
	lefthy("tweaks aggrotest")
	Advance(0.1)
	check(printedSince(pmark):find("2 enemy nameplate", 1, true) and tagText("nameplate1") == ">YOU<" and tagText("nameplate2") == "Ann",
		"/lefthy tweaks aggrotest: examples on the enemy nameplates in sight")
	Advance(10.2)
	check(tagText("nameplate2") == nil, "ten seconds later: the real thing again")
	-- The role check: Blizzard's, for the whole group.
	pmark = #PRINTED + 1
	lefthy("tweaks rolecheck")
	check(ROLE_POLLS == 1 and printedSince(pmark):find("role check started", 1, true), "/lefthy tweaks rolecheck: Blizzard's role check")
	ROLE_POLL_OK = false
	pmark = #PRINTED + 1
	lefthy("tweaks rolecheck")
	check(printedSince(pmark):find("only the group's leader or an assistant", 1, true), "not the leader: said so")
	ROLE_POLL_OK = true
	-- Switched off: every tag goes.
	lefthy("tweaks aggro off")
	Advance(0.1)
	check(tagText("nameplate1") == nil, "switched off: no tags")
	lefthy("tweaks aggro on")
	Advance(0.1)
	Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
	Fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
	GROUP, PARTY.party1, PARTY.party2, ROLES, MOBS.nameplate1, MOBS.nameplate2 = "none", nil, nil, {}, nil, nil
	THREAT.nameplate1, THREAT.nameplate2, THREATS = nil, nil, {}
	Fire("GROUP_ROSTER_UPDATE")
	Advance(0.1)
end)()
