-- Misc Tweaks: the level-up window.
-- Needs: no other file.
local suite = ...
local check, section, ns, lefthy = suite.check, suite.section, suite.ns, suite.lefthy
local printedSince = suite.printedSince

section("Misc Tweaks: level-up window")
do
	local TDB = LefthyToolsDB.settings.tweaks
	local function T(id) return REGISTERED_SETTINGS["LefthyTools_tweaks_" .. id] end
	local LU = ns.LevelUp
	local function plain(s) return (tostring(s or "")):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
	local function shown() return LefthyToolsLevelUpFrame ~= nil and LefthyToolsLevelUpFrame:IsShown() end
	local function cells()
		local out = {}
		for _, c in ipairs(LefthyToolsLevelUpFrame.Cells) do
			if c.Label:IsShown() then out[c.Label:GetText()] = plain(c.Value:GetText()) end
		end
		return out
	end
	local function icons()
		local out = {}
		for _, b in ipairs(LefthyToolsLevelUpFrame.Icons) do if b:IsShown() and b.spell then out[#out + 1] = b end end
		return out
	end
	check(TDB.levelUp == true and T("levelUp") and SETTINGS_BUTTONS["Show the level-up window"], "on by default, with a checkbox and a preview button")
	if LefthyToolsLevelUpFrame then LefthyToolsLevelUpFrame:Hide() end

	-- A rogue goes from 19 to 20: base stats +1 Str, +2 Agi, +1 Sta, +0 Int, +1 Spi (Spirit: only the snapshot knows).
	-- Chronicle times a level from the level-up that began it: an earlier file's, else an hour ago.
	local chronicled = LefthyToolsChronicleDB.chars["Lefthy-Realmy"]
	chronicled.levelStart = chronicled.levelStart or chronicled.stats.played - 3600
	PLAYER_LEVEL = 19
	LU.TakeSnapshot()
	PLAYER_LEVEL = 20
	STATS = { { 41, 46 }, { 62, 72 }, { 51, 59 }, { 25, 25 }, { 31, 33 } }
	local rogue20 = ns.CLASS_SPELLS.ROGUE[20]
	KNOWN_SPELLS[rogue20[1]] = true -- one of them already learned
	UNLOCKED_DUNGEONS[20] = { "Shadowfang Keep" }
	Fire("PLAYER_LEVEL_UP", 20, 30, 0, 1, 0, 1, 2, 1, 0)
	check(not shown(), "nothing inside the event")
	Advance(0.5)
	check(not shown(), "not right away: Blizzard's banner and fanfare first")
	Advance(1.2)
	local W = LefthyToolsLevelUpFrame
	check(shown() and W.Number:GetText() == 20 and W.Face.Portrait.portrait == "player", "1.5 s later: the window, with my portrait and level 20")
	check(W:GetAlpha() < 1 and W.NumberFrame.Punch.plays > 0 and W.TopBar.Grow.plays > 0, "it fades in, the gold bars grow and the number punches in")
	Advance(2)
	local c = cells()
	check(c.Health == "+30" and c.Strength == "45 > 46  +1" and c.Agility == "70 > 72  +2" and c.Spirit == "32 > 33  +1"
		and c.Intellect == "25" and c.Energy == nil, "stats counted up: old > new and the gain (Spirit too), health; no energy for a rogue")
	local list = icons()
	check(#list == #rogue20 - 1 and list[1].spell.id ~= rogue20[1], "the trainer's new spells for level 20, without the known one")
	local newOnes, ranked = 0, 0
	for _, b in ipairs(list) do
		if b.spell.rank then
			if b.Rank:GetText() == b.spell.rank then ranked = ranked + 1 end
		elseif b.New:GetText() == "NEW" then
			newOnes = newOnes + 1
		end
	end
	check(newOnes + ranked == #list and W:GetAlpha() == 1, "new spells marked NEW, upgrades with their rank")
	list[1]:GetScript("OnEnter")(list[1])
	check(TOOLTIP.spell == list[1].spell.id and TOOLTIP.shown, "hovering an icon shows the spell's tooltip")
	list[1]:GetScript("OnLeave")(list[1])
	local unlocks = plain(W.Unlocks:GetText())
	check(unlocks:find("+1 talent point", 1, true) and unlocks:find("Class quest: Poisons", 1, true)
		and unlocks:find("New dungeons: Shadowfang Keep", 1, true), "talent point, the rogue's poison quest and the new dungeon, got " .. unlocks)
	check(W.Took:IsShown() and W.Took:GetText():find("Level 19 took", 1, true), "how long level 19 took (Chronicle)")
	check(TDB.levelUps["Lefthy-Realmy"].level == 20 and TDB.levelUps["Lefthy-Realmy"].stats[5] == 1, "the gains are kept for the preview")
	local inList = false
	for _, name in ipairs(UISpecialFrames) do if name == "LefthyToolsLevelUpFrame" then inList = true end end
	check(inList, "Escape closes it")
	W._mouse = true
	Advance(30)
	check(shown(), "it stays while the mouse is on it")
	W._mouse = false
	Advance(26)
	check(not shown(), "and closes by itself after a while")

	-- In combat: it waits; a fight starting closes it.
	PLAYER_LEVEL = 21
	STATE.combat = true
	Fire("PLAYER_LEVEL_UP", 21, 31, 0, 1, 0, 1, 1, 1, 1)
	Advance(4)
	check(not shown(), "a level-up in combat: no window yet")
	STATE.combat = false
	Fire("PLAYER_REGEN_ENABLED")
	Advance(1.2)
	check(shown() and W.Number:GetText() == 21, "after the fight: there it is")
	STATE.combat = true
	Fire("PLAYER_REGEN_DISABLED")
	Advance(0.1)
	check(not shown(), "a fight starting closes it")
	STATE.combat = false

	-- Blizzard's level-up banner first.
	CreateFrame("Frame", "EventToastManagerFrame")
	Fire("PLAYER_LEVEL_UP", 21, 31, 0, 1, 0, 1, 1, 1, 1)
	Advance(3)
	check(not shown(), "while Blizzard's level-up banner is up: it waits")
	EventToastManagerFrame:Hide()
	Advance(0.6)
	check(shown(), "and comes once the banner is gone")
	_G.EventToastManagerFrame = nil
	W:Hide()

	-- The preview: the window for my current level.
	SETTINGS_BUTTONS["Show the level-up window"].onClick()
	check(shown() and W.Number:GetText() == 21 and plain(W.Tag:GetText()) == "Your last level-up, once more",
		"preview button: my level, my last gains")
	check(W.Close:IsShown() and W.Close._template == "UIPanelCloseButtonNoScripts", "with Blizzard's red X at the top")
	W:Hide()
	SlashCmdList.LEFTHYTOOLS_LEVELUP("")
	check(shown() and W.Number:GetText() == 21, "/levelup: the same, one quick command")
	Advance(2)
	check(cells().Strength == "45 > 46  +1" and cells().Spirit == "33",
		"... and its numbers: the event's own when the base stats didn't move (no Spirit gain then), got " .. tostring(cells().Spirit))
	W:Hide()
	wipe(TDB.levelUps)
	lefthy("tweaks levelup test")
	check(shown() and plain(W.Tag:GetText()):find("example", 1, true), "/lefthy tweaks levelup test, no level-up yet: example gains, said so")
	W:Hide()
	PLAYER_LEVEL = 20
	KNOWN_SPELLS[rogue20[2]] = true
	lefthy("tweaks levelup test")
	local known = 0
	for _, b in ipairs(icons()) do if b.spell.known and b.Icon.desaturated then known = known + 1 end end
	check(#icons() == #rogue20 and known == 2, "the preview lists every spell of the level, known ones greyed out")
	W:Hide()
	do -- In combat it says so in chat (English, like every chat line) instead.
		STATE.combat = true
		local mark = #PRINTED + 1
		SlashCmdList.LEFTHYTOOLS_LEVELUP("")
		check(not shown() and printedSince(mark):find("not in combat", 1, true), "/levelup in combat: a chat line, no window")
		STATE.combat = false
	end

	-- Talents: level 10 opens the first row of every tree; later, the next row of the tree with the most points.
	local function talentParts()
		local labels, list = {}, {}
		for _, l in ipairs(W.TalentLabels) do if l:IsShown() then labels[#labels + 1] = plain(l:GetText()) end end
		for _, b in ipairs(W.TalentIcons) do if b:IsShown() and b.talent then list[#list + 1] = b end end
		return labels, list
	end
	KNOWN_SPELLS = {}
	PLAYER_LEVEL = 10
	Fire("PLAYER_LEVEL_UP", 10, 20, 0, 1, 0, 1, 1, 1, 0)
	Advance(2)
	local labels, talentIcons = talentParts()
	check(shown() and W.TalentsTitle.Text:GetText() == "Talents unlocked" and #labels == 3 and labels[1]:find("Assassination", 1, true)
		and labels[3]:find("Subtlety", 1, true) and #talentIcons == 6, "level 10: the first row of every talent tree, got " .. #talentIcons .. " talents")
	talentIcons[1]:GetScript("OnEnter")(talentIcons[1])
	check(TOOLTIP.spell == 901011 and tostring(TOOLTIP.lines[1]):find("Talent in Assassination, row 1: up to 5 points", 1, true),
		"hovering one: the talent, its tree, row and points")
	talentIcons[1]:GetScript("OnLeave")(talentIcons[1])
	check(plain(W.Unlocks:GetText()):find("Talents unlocked: +1 talent point", 1, true), "and the first talent point")
	W:Hide()
	TALENT_SPENT[1] = 5
	PLAYER_LEVEL = 15
	Fire("PLAYER_LEVEL_UP", 15, 20, 0, 1, 0, 1, 1, 1, 0)
	Advance(2)
	labels, talentIcons = talentParts()
	check(W.TalentsTitle.Text:GetText() == "New talent row (row 2)" and #labels == 1 and labels[1]:find("Assassination", 1, true)
		and #talentIcons == 2 and talentIcons[1].talent.row == 2, "level 15: the second row of the tree with my points")
	W:Hide()
	-- A talent isn't the trainer's (like Templar's Bulwark), nor a rank of a talent I don't have.
	TALENT_SPENT[1] = 10
	PLAYER_LEVEL = 20
	TALENT_NODES[1031].spellID = rogue20[1]
	SPELL_NAMES[901032], SPELL_NAMES[rogue20[2]] = "Templar's Bulwark", "Templar's Bulwark"
	Fire("PLAYER_LEVEL_UP", 20, 30, 0, 1, 0, 1, 2, 1, 0)
	Advance(2)
	local listed = {}
	for _, b in ipairs(icons()) do listed[b.spell.id] = true end
	check(#icons() == #rogue20 - 2 and not listed[rogue20[1]] and not listed[rogue20[2]],
		"a talent's spell and a higher rank of a talent I don't have: not at the trainer")
	W:Hide()
	KNOWN_SPELLS[901032] = true
	lefthy("tweaks levelup test")
	listed = {}
	for _, b in ipairs(icons()) do listed[b.spell.id] = true end
	check(listed[rogue20[2]] and not listed[rogue20[1]], "with the talent, its next rank is at the trainer")
	W:Hide()
	TALENT_NODES[1031].spellID, SPELL_NAMES, KNOWN_SPELLS, TALENT_SPENT = 901031, {}, {}, { 0, 0, 0 }

	-- Pinned: it stays until closed, and steps aside during a fight.
	lefthy("tweaks levelup test")
	check(not W.pinned and W.Timer.shown, "a new window starts unpinned, with its timer line")
	W.Pin:Click()
	check(W.pinned and not W.Timer.shown, "the pin keeps it (no timer line)")
	Advance(30)
	check(shown(), "pinned: still there after 30 s")
	STATE.combat = true
	Fire("PLAYER_REGEN_DISABLED")
	check(not shown(), "a fight: it steps aside")
	Advance(2)
	STATE.combat = false
	Fire("PLAYER_REGEN_ENABLED")
	Advance(1.2)
	check(shown() and W.pinned and W:GetAlpha() == 1, "after the fight it's back, still pinned")
	STATE.combat = true
	Fire("PLAYER_REGEN_DISABLED")
	Fire("PLAYER_LEVEL_UP", PLAYER_LEVEL, 10, 0, 1, 0, 1, 1, 1, 1)
	Advance(2)
	STATE.combat = false
	Fire("PLAYER_REGEN_ENABLED")
	Advance(1.2)
	check(shown() and not W.pinned and W.Timer.shown, "a level-up during that fight: its window starts unpinned")
	W.Pin:Click() -- (pinned again for the arrows below)
	-- A buff that came between two levels isn't a gain: the base stats are what's compared.
	LU.TakeSnapshot()
	local spiritWas = STATS[5]
	STATS[5] = { spiritWas[1], spiritWas[2] + 8 }
	Fire("PLAYER_LEVEL_UP", PLAYER_LEVEL, 10, 0, 1, 0, 1, 1, 1, 1)
	Advance(3.5)
	check(cells().Spirit == tostring(spiritWas[2] + 8), "a buff since the last level isn't counted as a gain, got " .. tostring(cells().Spirit))
	STATS[5] = spiritWas
	W.Pin:Click()
	-- The arrows: what other levels bring.
	local level = W.Number:GetText()
	W.Next:Click()
	check(W.Number:GetText() == level + 1 and plain(W.Tag:GetText()):find("Coming up: what level " .. (level + 1), 1, true)
		and not W.StatsTitle.Text:IsShown(), "next level: what it brings, no stats")
	W.Prev:Click()
	W.Prev:Click()
	check(W.Number:GetText() == level - 1 and plain(W.Tag:GetText()):find("Looking back", 1, true), "and back")
	W.Close:Click()
	Advance(0.5)
	check(not shown() and not W.pinned, "closed: gone, and the next one starts unpinned")
	do -- Pinned, its X clicked just as a fight starts (still fading out): it stays closed.
		lefthy("tweaks levelup test")
		W.Pin:Click()
		W.Close:Click()
		STATE.combat = true
		Fire("PLAYER_REGEN_DISABLED")
		Advance(0.5)
		STATE.combat = false
		Fire("PLAYER_REGEN_ENABLED")
		Advance(1.2)
		check(not shown() and not W.pinned, "closed with its X as a fight starts: it doesn't come back after the fight")
	end
	lefthy("tweaks levelup test")
	W:GetScript("OnDragStart")(W)
	W:GetScript("OnDragStop")(W)
	check(W.pinned, "moving it pins it")
	W:Hide()
	W.Next:Click()
	check(shown() and W.pinned, "browsing pins it too")
	W:Hide()

	T("levelUp"):SetValue(false)
	Advance(0.1)
	Fire("PLAYER_LEVEL_UP", 21, 31, 0, 1, 0, 1, 1, 1, 1)
	Advance(3)
	check(not shown(), "switched off: no window")
	T("levelUp"):SetValue(true)
	Advance(0.1)
	PLAYER_LEVEL, KNOWN_SPELLS, UNLOCKED_DUNGEONS = 19, {}, {}
	STATS = { { 40, 45 }, { 60, 70 }, { 50, 58 }, { 25, 25 }, { 30, 32 } }
end
