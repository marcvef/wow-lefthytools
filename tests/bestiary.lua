-- Bestiary: what mobs drop, quest drops, the wish list, counting.
local suite = ...
local check, near, section, ns, LT = suite.check, suite.near, suite.section, suite.ns, suite.LT
local printedSince = suite.printedSince
local _

section("Bestiary: what mobs drop")
;(function()
	local Bt = ns.Bestiary
	local function setting(id) return REGISTERED_SETTINGS["LefthyTools_bestiary_" .. id] end
	local function mob() return LefthyToolsBestiaryDB.mobs[116] end
	local function tipFind(text)
		for _, l in ipairs(TOOLTIP.lines) do if l:find(text, 1, true) then return true end end
		return false
	end
	local win, card, button = Bt.Frames()
	check(LT:GetModule("bestiary").enabled and button and button:IsShown() and not win and setting("hoverCard"):GetValue() == false,
		"on by default: a minimap button; no window yet; the card next to the mouse off")
	button._scripts.OnEnter(button)
	check(TOOLTIP.title == "Bestiary" and tipFind("0 kinds of mobs, 0 kills"), "the button's tooltip: how much it knows")
	button._scripts.OnClick(button, "LeftButton")
	win = Bt.Frames()
	check(win and win:IsShown() and win.Name:GetText() == "Bestiary" and win.Note:GetText() == "Target a mob to see what it drops."
		and button.Open:IsShown(), "a click opens the window: target a mob (a gold dot on the button)")
	local escapes = false
	for _, name in ipairs(UISpecialFrames) do if name == "LefthyToolsBestiaryFrame" then escapes = true end end
	check(not escapes, "Escape doesn't close it")

	-- A Defias Bandit (creature 116): targeted, killed, looted.
	local guid = "Creature-0-1-0-1-116-0000000A"
	MOBS.target, STATE.target = { name = "Defias Bandit", level = 9, guid = guid, combat = true, yards = 5 }, true
	Fire("PLAYER_TARGET_CHANGED")
	check(win.Name:GetText() == "Defias Bandit" and win.Kind:GetText() == "Level 9" and win.Portrait._creature == 116
		and win.Note:GetText() == "No kills of it yet: kill one on your own and loot it.", "it follows my target: its portrait, name, level; no kills yet")
	Fire("PARTY_KILL", "Player-1-0", guid)
	MOBS.target.dead = true
	LOOT = { { type = 1, id = 2589, quantity = 2, source = guid }, { type = 2, source = guid } }
	local money = MONEY
	Fire("LOOT_READY", false)
	MONEY = MONEY + 1234
	Fire("LOOT_CLOSED")
	LOOT = {}
	local cell = win.cells[1]
	check(mob().kills == 1 and mob().money == 1234 and mob().items[2589][1] == 1 and mob().items[2589][2] == 2
		and cell:IsShown() and cell.Count:GetText() == "2" and cell.Chance:GetText() == "100%" and cell.Icon.path == 3589
		and win.Kills:GetText():find("1 kill", 1, true) and win.Kills:GetText():find("12s 34c each", 1, true),
		"killed and looted: 1 kill, 2 Linen Cloth (100%), its coin (12s 34c each)")
	-- Another, its corpse empty: counted once the game says so (twice, a few seconds apart).
	local guid2 = "Creature-0-1-0-1-116-0000000B"
	LOOT_EMPTY[guid2] = true
	Fire("PARTY_KILL", "Player-1-0", guid2)
	Advance(2.1)
	check(mob().kills == 1, "an empty corpse: not yet (its loot can take a moment)")
	Advance(4.1)
	check(mob().kills == 2 and cell.Chance:GetText() == "50%", "still empty: counted, a kill without drops (Linen Cloth 50%)")
	-- One left lying with loot on it: not counted (it would look like nothing dropped).
	Fire("PARTY_KILL", "Player-1-0", "Creature-0-1-0-1-116-0000000C")
	Advance(7)
	check(mob().kills == 2, "a corpse with loot left lying: not counted")
	-- Looted once only; skinning it after, a pickpocket, fishing: not its drops.
	local guid4 = "Creature-0-1-0-1-116-0000000D"
	ITEMS[4865] = ITEMS[4865] or { name = "Ruined Pelt", quality = 0 }
	LOOT = { { type = 1, id = 2075, source = guid4 }, { type = 1, id = 4865, source = guid4 } }
	Fire("LOOT_READY", true) -- (no killing blow of mine seen: its loot says it was mine)
	Fire("LOOT_CLOSED")
	LOOT = { { type = 1, id = 2589, source = guid4 } }
	Fire("LOOT_READY", false)
	Fire("LOOT_CLOSED")
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-8", 921) -- (Pick Pocket)
	LOOT = { { type = 1, id = 1179, source = "Creature-0-1-0-1-116-0000000E" } }
	Fire("LOOT_READY", false)
	Fire("LOOT_CLOSED")
	Advance(2)
	LOOT_FISHING = true
	Fire("LOOT_READY", false)
	Fire("LOOT_CLOSED")
	LOOT, LOOT_FISHING = {}, false
	check(mob().kills == 3 and mob().items[2589][1] == 1 and not mob().items[1179],
		"a corpse looted again (skinning), a pickpocket, fishing: none of them counted")
	local cells = win.cells
	check(cells[1].drop.id == 2075 and cells[2].drop.id == 2589 and cells[3].drop.id == 4865 and cells[1].Chance:GetText() == "33%",
		"the likeliest first, the better first when even (the green mace, the white cloth, the grey pelt)")
	cells[1]._scripts.OnEnter(cells[1])
	check(TOOLTIP.link == "item:2075" and tipFind("Dropped in 1 of 3 kills: 33%") and tipFind("Shift-click: link it in chat"),
		"hover a drop: the item's tooltip, how often it dropped")
	cells[1]._scripts.OnLeave(cells[1])
	setting("showPoor"):SetValue(false)
	check(not (cells[3] and cells[3]:IsShown()) and cells[2]:IsShown(), "grey items off: the Ruined Pelt goes")
	setting("showPoor"):SetValue(true)
	-- In a group: nothing counted (the loot is shared), and the window says so.
	GROUP = "party"
	Fire("PARTY_KILL", "Player-1-0", "Creature-0-1-0-1-116-0000000F")
	LOOT = { { type = 1, id = 2589, source = "Creature-0-1-0-1-116-0000000F" } }
	Fire("LOOT_READY", false)
	Fire("LOOT_CLOSED")
	LOOT = {}
	Fire("PLAYER_TARGET_CHANGED")
	check(mob().kills == 3 and win.Note:GetText():find("In a group: kills aren't counted", 1, true), "in a group: not counted, and said")
	do -- (a note wraps in the window's width, as this one does in game: the window grows with it)
		local tall, measure = win:GetHeight(), win.Note.GetStringHeight
		win.Note.GetStringHeight = function() return 2 * 14 end
		Bt.Draw()
		check(win:GetHeight() == tall + 14, "a note on two lines: the window a line taller")
		win.Note.GetStringHeight = measure
		Bt.Draw()
	end
	GROUP = "none"
	-- No target, or a vendor: the last mob stays.
	MOBS.target, STATE.target = nil, false
	Fire("PLAYER_TARGET_CHANGED")
	check(win.Name:GetText() == "Defias Bandit", "target cleared: the last mob stays")
	-- Many drops: as many as fit, the rest in a "+N".
	for id = 50001, 50030 do mob().items[id] = { 1, 1, 1 } end
	Bt.Draw()
	check(cells[24]:IsShown() and cells[24].More:GetText() == "+10" and not cells[25], "33 drops: 23 fit, +10, the rest on hover")
	cells[24]._scripts.OnEnter(cells[24])
	check(TOOLTIP.title == "More drops" and #TOOLTIP.lines == 10, "hover: the rest, with their chances")
	cells[24]._scripts.OnLeave(cells[24])
	for id = 50031, 50060 do mob().items[id] = { 1, 1, 1 } end
	Bt.Draw()
	cells[24]._scripts.OnEnter(cells[24])
	check(#TOOLTIP.lines == 21 and tipFind("and 20 more (the Bestiary's ledger)"),
		"far more: the tooltip lists 20 and says how many more (it would be taller than the screen)")
	cells[24]._scripts.OnLeave(cells[24])
	for id = 50001, 50060 do mob().items[id] = nil end
	Bt.Draw()
	-- A Riverpaw Gnoll (117). A quick loot right after an instant spell (the killing blow) counts:
	-- only skinning, a pickpocket or gathering just before the loot window make it not a kill's.
	local gnolls = function() return LefthyToolsBestiaryDB.mobs[117] end
	local g1, g2, g3 = "Creature-0-1-0-1-117-00000020", "Creature-0-1-0-1-117-00000021", "Creature-0-1-0-1-117-00000022"
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-9", 2764) -- (Throw)
	Fire("PARTY_KILL", "Player-1-0", g1)
	LOOT = { { type = 1, id = 2589, source = g1 } }
	Fire("LOOT_READY", true)
	Fire("LOOT_CLOSED")
	check(gnolls().kills == 1 and gnolls().items[2589], "a spell just before looting (the killing blow): its loot counts")
	-- The game said a corpse was empty, but it's looted after all: its items join that kill.
	LOOT_EMPTY[g2] = true
	Fire("PARTY_KILL", "Player-1-0", g2)
	Advance(6.2)
	check(gnolls().kills == 2, "the game says it's empty: a kill without drops")
	LOOT = { { type = 1, id = 2075, source = g2 } }
	Fire("LOOT_READY", false)
	Fire("LOOT_CLOSED")
	check(gnolls().kills == 2 and gnolls().items[2075] and gnolls().items[2075][1] == 1,
		"looted after all: its items join that kill (not a second one)")
	-- The slots not there yet when the loot is ready: looked at again when the window opens.
	LOOT = {}
	Fire("LOOT_READY", false)
	LOOT = { { type = 1, id = 1179, source = g3 } }
	Fire("LOOT_OPENED", false, false)
	Fire("LOOT_CLOSED")
	LOOT = {}
	check(gnolls().kills == 3 and gnolls().items[1179], "slots filled only when the window opens: still read")
	local pmark = #PRINTED + 1
	SlashCmdList.LEFTHYTOOLS_BESTIARY("log")
	local logText = printedSince(pmark)
	check(logText:find("Riverpaw", 1, true) == nil and logText:find("looted (said empty before), 1 item(s)", 1, true)
		and logText:find("pickpocket or gathering", 1, true) and logText:find("Defias Bandit: looted, 2 item(s)", 1, true)
		and logText:find("empty (loot check false/true)", 1, true),
		"/bestiary log: what was made of each loot window and kill, got\n" .. logText)
	-- The card next to the mouse (setting): an enemy killed before, its drops small.
	MOBS.mouseover = { name = "Defias Bandit", level = 9, guid = "Creature-0-1-0-1-116-00000010", pinned = true }
	Fire("UPDATE_MOUSEOVER_UNIT")
	check(not (select(2, Bt.Frames()) and select(2, Bt.Frames()):IsShown()), "the card is off by default")
	setting("hoverCard"):SetValue(true)
	CURSOR.x, CURSOR.y = 400, 300
	Fire("UPDATE_MOUSEOVER_UNIT")
	card = select(2, Bt.Frames())
	check(card and card:IsShown() and card.Kills:GetText():find("3 kills", 1, true) and card.cells[1]:IsShown()
		and card.cells[1].Chance:GetText() == "33%", "over it: my kills and its drops, beside the mouse")
	-- Not in combat (a setting, on): it goes when a fight starts and comes back after.
	check(LefthyToolsDB.settings.bestiary.cardHideInCombat == true, "hidden in combat: on by default")
	STATE.combat = true
	Advance(0.1)
	check(not card:IsShown(), "a fight starts: the card goes")
	Fire("UPDATE_MOUSEOVER_UNIT")
	check(not card:IsShown(), "in combat: not shown")
	setting("cardHideInCombat"):SetValue(false)
	Fire("UPDATE_MOUSEOVER_UNIT")
	Advance(0.1)
	check(card:IsShown(), "the setting off: also in combat")
	setting("cardHideInCombat"):SetValue(true)
	Advance(0.1)
	check(not card:IsShown(), "on again: gone")
	STATE.combat = false
	Fire("PLAYER_REGEN_ENABLED")
	check(card:IsShown(), "the fight is over, the mouse still over it: back")
	-- A mob that never dropped coin: the card says nothing about coin (the window says "no coin").
	MOBS.mouseover = { guid = "Creature-0-1-0-1-117-00000011", pinned = true } -- (no name: later tests want it unnamed)
	Fire("UPDATE_MOUSEOVER_UNIT")
	check(card:IsShown() and card.Kills:GetText() == "3 kills", "no coin: not said on the card, got " .. tostring(card.Kills:GetText()))
	MOBS.mouseover = nil
	Advance(0.1)
	check(not card:IsShown(), "the mouse moves off: the card goes")
	setting("hoverCard"):SetValue(false)
	-- Skinning: what came, per skinning, apart from the drops, marked with Skinning's icon.
	local beast = "Creature-0-1-0-1-116-00000030"
	ITEMS[2318] = ITEMS[2318] or { name = "Light Leather", quality = 1 }
	Fire("PARTY_KILL", "Player-1-0", beast)
	LOOT = { { type = 1, id = 2589, source = beast } } -- (its loot first)
	Fire("LOOT_READY", false)
	Fire("LOOT_CLOSED")
	Advance(2)
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-10", 8613) -- (Skinning)
	LOOT = { { type = 1, id = 2318, quantity = 2, source = beast } }
	Fire("LOOT_READY", false)
	Fire("LOOT_CLOSED")
	check(mob().kills == 4 and mob().skinned == 1 and mob().skins[2318][1] == 1 and mob().skins[2318][2] == 2
		and mob().skins[2318][4] == "Light Leather" and not mob().items[2318], "skinned: kept apart, per skinning, with its name")
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-11", 8613)
	Fire("LOOT_READY", false)
	Fire("LOOT_CLOSED")
	LOOT = {}
	check(mob().skinned == 1, "the same corpse again: skinned once")
	local skinCell
	for _, c in ipairs(win.cells) do if c:IsShown() and c.drop and c.drop.skin then skinCell = c end end
	check(skinCell and skinCell.drop.id == 2318 and skinCell.Skin:IsShown() and skinCell.Chance:GetText() == "100%"
		and not win.cells[1].Skin:IsShown() and win.Kills:GetText():find("INV_Misc_Pelt_Wolf_01:12:12|t 1", 1, true),
		"the window: after the drops, with Skinning's icon, 100% per skinning; how often skinned")
	skinCell._scripts.OnEnter(skinCell)
	check(tipFind("Only from skinning: 1 of 1 skinnings, 100%"), "hover: only from skinning")
	skinCell._scripts.OnLeave(skinCell)
	Advance(2)
	-- Item tooltips (on by default): the three mobs an item comes from likeliest; a pelt for skinning.
	GameTooltip:SetOwner(UIParent)
	GameTooltip:SetHyperlink("item:2589")
	check(tipFind("Bestiary  drop chance (kills)") and tipFind("Defias Bandit (9)  50% |cff888888(4)|r") and tipFind("#117  33%"),
		"an item's tooltip: the mobs it comes from, the likeliest first, the chance and the kills behind it")
	GameTooltip:SetOwner(UIParent)
	GameTooltip:SetHyperlink("item:2318")
	check(tipFind("INV_Misc_Pelt_Wolf_01:14:14|t Defias Bandit (9)  100%"), "from skinning: the pelt")
	setting("itemTooltip"):SetValue(false)
	GameTooltip:SetOwner(UIParent)
	GameTooltip:SetHyperlink("item:2589")
	check(not tipFind("Bestiary"), "the setting off: nothing added")
	setting("itemTooltip"):SetValue(true)
	cells[1]._scripts.OnEnter(cells[1])
	check(not tipFind("drop chance (kills)"), "the window's own drop: its numbers, not the list again")
	cells[1]._scripts.OnLeave(cells[1])
	-- The minimap button: Shift-click switches the card next to the mouse, Ctrl-click the ledger.
	STATE.shift = true
	button._scripts.OnClick(button, "LeftButton")
	STATE.shift = false
	check(LefthyToolsDB.settings.bestiary.hoverCard == true and win:IsShown(), "Shift-click: the card next to the mouse on (the window stays)")
	STATE.shift = true
	button._scripts.OnClick(button, "LeftButton")
	STATE.shift = false
	check(LefthyToolsDB.settings.bestiary.hoverCard == false, "again: off")
	STATE.ctrl = true
	button._scripts.OnClick(button, "LeftButton")
	STATE.ctrl = false
	local ledger, entries, picked = Bt.Ledger()
	-- The ledger: every mob, the most kills first; the window's mob picked.
	check(ledger and ledger:IsShown() and picked == 116 and #entries == 2 and ledger.rows[1].Name:GetText():find("Defias Bandit", 1, true)
		and ledger.rows[1].Kills:GetText() == "4" and ledger.Pane.Name:GetText() == "Defias Bandit" and ledger.Pane.Model._creature == 116,
		"Ctrl-click: the ledger, every mob (the most kills first), the window's mob picked: its model and name")
	check(ledger.Summary:GetText() == "2 mobs  ·  7 kills  ·  5 items  ·  12s 34c coin, 1s 76c per kill" and ledger.rows[1].icons[1]:IsShown(),
		"at the top: all it knows, the coin per kill over all kills; a row's best drops as tiny icons")
	local escapes = false
	for _, name in ipairs(UISpecialFrames) do if name == "LefthyToolsBestiaryLedger" then escapes = true end end
	check(escapes, "Escape closes the ledger (unlike the window)")
	local facing = ledger.Pane.facing
	Advance(1)
	check(ledger.Pane.facing > facing and ledger.Pane.Model._facing == ledger.Pane.facing, "its model turns slowly")
	-- The fuzzy search: letters in order, over mob names and their drops' names.
	ledger.Search:SetText("dfbnd")
	_, entries = Bt.Ledger()
	check(#entries == 1 and entries[1].creature == 116 and ledger.rows[1].Name:GetText():find("|cffffd100D|r", 1, true)
		and ledger.Clear:IsShown() and not ledger.Placeholder:IsShown(), "\"dfbnd\": the Defias Bandit, its found letters in gold")
	ledger.Search:SetText("cold milk")
	_, entries, picked = Bt.Ledger()
	local milk
	for _, c in ipairs(ledger.Pane.sections.own.cells) do if c:IsShown() and c.drop and c.drop.id == 1179 then milk = c end end
	check(#entries == 1 and picked == 117 and ledger.rows[1].Found:GetText():find("Ice Cold Milk", 1, true)
		and ledger.rows[1].Found:GetText():find("33%", 1, true) and milk and milk:GetAlpha() == 1
		and ledger.Pane.sections.own.cells[1]:GetAlpha() < 1,
		"an item: the mob it came from, picked; the item and its chance in the row; the match stands out among its drops")
	-- Another result can be picked (in game a click went back to the first): it stays while the list
	-- redraws; typing again picks the best match.
	do
		ledger.Search:SetText("l") -- (both: their Linen Cloth)
		local _, found, first = Bt.Ledger()
		local other = found[2] and found[2].creature
		ledger.rows[2]:Click()
		local _, _, now = Bt.Ledger()
		check(#found == 2 and first == found[1].creature and other and other ~= first and now == other and ledger.Pane.creature == other
			and ledger.rows[2].Picked:IsShown() and not ledger.rows[1].Picked:IsShown(), "a search: another result clicked, picked")
		Bt.DrawLedger() -- (what names coming in and a kill do)
		_, _, now = Bt.Ledger()
		check(now == other and ledger.Pane.creature == other, "the list redraws: the click's pick stays")
		ledger.Search:SetText("li")
		_, found, now = Bt.Ledger()
		check(now == found[1].creature and now ~= other, "typing again: the best match picked")
	end
	ledger.Search:SetText("zzz")
	check(not ledger.rows[1]:IsShown() and ledger.NoMatch:GetText() == "Nothing found.", "nothing: said so")
	ledger.Clear._scripts.OnClick(ledger.Clear)
	_, entries = Bt.Ledger()
	check(#entries == 2 and ledger.Placeholder:IsShown(), "cleared: every mob again")
	ledger.Sort._scripts.OnClick(ledger.Sort)
	for _, row in ipairs(ledger.Sort.List.rows) do if row.value == "name" then row._scripts.OnClick(row) end end
	_, entries = Bt.Ledger()
	check(entries[1].creature == 116 and ledger.Sort.Label:GetText() == "Name", "sorted by name")
	ledger:Hide()
	SlashCmdList.LEFTHYTOOLS_BESTIARY("ledger milk")
	_, entries = Bt.Ledger()
	check(ledger:IsShown() and #entries == 1 and ledger.Search:GetText() == "milk", "/bestiary ledger milk: opened on that search")
	ledger:Hide()
	-- World drops: random green gear that doesn't bind on pickup drops from mobs anywhere; with a mob
	-- they gather in one place (the map), and their tooltip says so.
	ITEMS[15211] = { name = "Militant Shortsword", quality = 2, classID = 2, equipLoc = "INVTYPE_WEAPON", bind = 2 }
	local lucky = "Creature-0-1-0-1-116-00000040"
	Fire("PARTY_KILL", "Player-1-0", lucky)
	LOOT = { { type = 1, id = 15211, source = lucky } }
	Fire("LOOT_READY", false)
	Fire("LOOT_CLOSED")
	LOOT = {}
	local worldCell
	for _, c in ipairs(win.cells) do if c:IsShown() and c.world then worldCell = c end end
	check(worldCell and worldCell.Icon.path == "Interface\\Icons\\INV_Misc_Map_01" and worldCell.Count:GetText() == "1"
		and worldCell.Chance:GetText() == "world" and not (win.cells[1].drop and win.cells[1].drop.id == 15211),
		"a random green sword: not among its own drops, in the world drops (a map, 1)")
	worldCell._scripts.OnEnter(worldCell)
	check(TOOLTIP.title == "World drops" and tipFind("Militant Shortsword"), "hover: the world drops, with their chances")
	worldCell._scripts.OnLeave(worldCell)
	GameTooltip:SetOwner(UIParent)
	GameTooltip:SetHyperlink("item:15211")
	check(tipFind("A world drop: random gear from mobs of its level, anywhere."), "its item tooltip says it's a world drop")
	-- One that binds on pickup is a mob's own.
	ITEMS[15212] = { name = "Bandit's Own Blade", quality = 2, classID = 2, equipLoc = "INVTYPE_WEAPON", bind = 1 }
	check(not Bt.IsWorldDrop(15212, 2) and Bt.IsWorldDrop(15211, 2) and not Bt.IsWorldDrop(2589, 1),
		"bound on pickup, or not gear: not a world drop")
	-- Skinning doesn't count towards the kinds an item comes from: leather skinned from three kinds of
	-- beast, and looted from one mob, stays that mob's drop; looted from three kinds, it's a world drop.
	do
		local mobs = LefthyToolsBestiaryDB.mobs
		ITEMS[2318] = ITEMS[2318] or { name = "Light Leather", quality = 1 }
		for i, creature in ipairs({ 8101, 8102, 8103 }) do
			mobs[creature] = { name = "Beast " .. i, kills = 4, money = 0, items = {}, skinned = 2, skins = { [2318] = { 2, 3, 1 } } }
		end
		mobs[8104] = { name = "Leatherworker", kills = 5, money = 0, items = { [2318] = { 1, 1, 1 } } }
		Bt.Changed(8104)
		check(not Bt.IsWorldDrop(2318, 1), "leather skinned from three kinds, looted from one: not a world drop")
		mobs[8105] = { name = "Trapper", kills = 5, money = 0, items = { [2318] = { 1, 1, 1 } } }
		mobs[8106] = { name = "Tanner", kills = 5, money = 0, items = { [2318] = { 1, 1, 1 } } }
		Bt.Changed(8106)
		check(Bt.IsWorldDrop(2318, 1), "looted from three kinds of mobs: a world drop")
		for creature = 8101, 8106 do
			mobs[creature] = nil
		end
		Bt.Changed(8101)
	end
	-- In the ledger, world drops are a section of their own: each a drop with its item tooltip.
	Bt.ToggleLedger(116)
	local pane = ledger.Pane
	local own, world = pane.sections.own, pane.sections.world
	local sword = world.cells[1]
	local inOwn = false
	for _, c in ipairs(own.cells) do if c:IsShown() and (c.world or (c.drop and c.drop.id == 15211)) then inOwn = true end end
	check(world.Heading:IsShown() and world.Heading:GetText() == "World drops (1)" and sword and sword:IsShown() and sword.drop.id == 15211
		and not inOwn and own.Heading:GetText():find("^Drops %(") and pane.Drops:GetHeight() > 100,
		"the ledger: the sword in a World drops section of its own, not among its drops; the drops scroll")
	sword._scripts.OnEnter(sword)
	check(TOOLTIP.link == "item:15211" and tipFind("Dropped in 1 of 5 kills: 20%"), "hover it: the sword's own tooltip, with its numbers")
	sword._scripts.OnLeave(sword)
	Bt.ToggleLedger(117)
	check(not world.Heading:IsShown() and not world.Grid:IsShown(), "a mob without world drops: no such section")
	ledger:Hide()
	-- The classic drop database: an add-on of its own (LefthyTools_DropData), loaded the first time
	-- it's needed. Not there: said so.
	local pmark2 = #PRINTED + 1
	SlashCmdList.LEFTHYTOOLS_BESTIARY("data")
	check(printedSince(pmark2):find("isn't there", 1, true), "/bestiary data: no database yet, said so")
	local loads = {}
	C_AddOns.LoadAddOn = function(name)
		loads[#loads + 1] = name
		LefthyToolsDropData = { source = "test", mobs = {
			[116] = "1019:1:6600q,2070:1:5000,2589:1:2972,774:2:128;s=2318:1:9000;g=8-15;h=8-9:156-176",
			[117] = "2589:1:5000,1179:1:1000", -- (as before the health: none)
			[118] = "4865:0:4000,2589:1:1500;s=2318:1:9000;g=20-40",
			[119] = ";h=10-20:300-800", -- (no loot, its health only)
		} }
		return true
	end
	setting("dropData"):SetValue(false)
	setting("dropData"):SetValue(true) -- (a setting changed: loading it is tried again)
	check(#loads == 1 and loads[1] == "LefthyTools_DropData", "switched on: the database add-on is loaded, once")
	-- Each kind's health in it too (for the fight stream), read beside the drops; strings without it as before.
	do
		local bandit, gnoll, brute = Bt.Known(116), Bt.Known(117), Bt.Known(119)
		check(bandit.health and bandit.health[1] == 8 and bandit.health[2] == 9 and bandit.health[3] == 156 and bandit.health[4] == 176
			and bandit.coin[1] == 8 and bandit.coin[2] == 15 and bandit.items[1019] and bandit.skins[2318],
			"a mob's string with its health: the health read, its drops, skinning and coin as before")
		check(gnoll.health == nil and gnoll.items[2589][1] == 0.5 and gnoll.items[1179] and Bt.Health(117, 10) == nil,
			"a string from before the health: its drops, no health")
		check(brute.health and next(brute.items) == nil and brute.coin == nil, "health only: known, no drops")
		local function at(level) return table.concat({ Bt.Health(119, level) }, ",") end
		check(Bt.Health(116, 8) == 156 and Bt.Health(116, 9) == 176 and at(15) == "550,15" and at(12) == "400,12",
			"its health at a level: in a straight line between its lowest and highest")
		check(at(25) == "800,20" and at(5) == "300,10" and at(nil) == "800,20" and at(-1) == "800,20",
			"outside its levels: the nearest end's, with that level; a level not known: its highest")
		Bt.module.enabled = false
		check(Bt.Health(116, 9) == nil, "the Bestiary switched off: none")
		Bt.module.enabled = true
	end
	check(LefthyToolsDB.settings.bestiary.windowUnseen == false and not win.KnownLabel:IsShown()
		and not (win.knownCells[1] and win.knownCells[1]:IsShown()), "the window: not seen yet is off by default (only your drops)")
	setting("windowUnseen"):SetValue(true)
	-- Your drops: the database's chance beside yours, or that it doesn't list it.
	local function cellOf(list, id) for _, c in ipairs(list) do if c:IsShown() and c.drop and c.drop.id == id then return c end end end
	local linen = cellOf(win.cells, 2589)
	linen._scripts.OnEnter(linen)
	check(linen.drop.classic == 0.2972 and tipFind("Dropped in 2 of 5 kills: 40%") and tipFind("Classic database: 30%"),
		"hover a drop: your chance, then the classic database's")
	linen._scripts.OnLeave(linen)
	local mace = cellOf(win.cells, 2075)
	mace._scripts.OnEnter(mace)
	check(mace.drop.classic == false and tipFind("Not in the classic database"), "a drop the database doesn't list: said so")
	mace._scripts.OnLeave(mace)
	-- What it says the mob drops that you haven't had yet: under your drops, smaller and faded.
	local known = win.knownCells
	check(win.KnownLabel:IsShown() and win.KnownLabel:GetText() == "Not seen yet" and win.KnownCount:GetText() == "2 of 5 found"
		and known[1].drop.id == 1019 and known[2].drop.id == 2070 and known[3].drop.id == 774 and not (known[4] and known[4]:IsShown())
		and known[1].Icon.desaturated and known[1].Icon:GetAlpha() < 1 and known[1].Count:GetText() == "" and known[1].Chance:GetText() == "66%"
		and known[1].Quest:IsShown() and not known[2].Quest:IsShown() and not cells[1].Icon.desaturated,
		"not seen yet: the database's other drops, the likeliest first, grey and faded, its chance; a quest item marked; 2 of its 5 found")
	known[2]._scripts.OnEnter(known[2])
	check(not known[2].Icon.desaturated and tipFind("Classic database: 50%") and tipFind("Not seen in your 5 kills (about 3 expected)"),
		"hover one: in colour, the database's chance, how many you'd have expected by now")
	known[2]._scripts.OnLeave(known[2])
	check(known[2].Icon.desaturated, "and faded again")
	known[1]._scripts.OnEnter(known[1])
	check(tipFind("Classic database: 66%, only while on its quest") and tipFind("Not seen yet in your 5 kills"),
		"a quest item: only while on its quest (nothing expected)")
	known[1]._scripts.OnLeave(known[1])
	-- All of them found: said so.
	MOBS.target = { name = "Riverpaw Gnoll", level = 10, guid = "Creature-0-1-0-1-117-00000050" }
	Fire("PLAYER_TARGET_CHANGED")
	check(not win.KnownLabel:IsShown() and win.Note:GetText():find("All 2 drops of the classic database found.", 1, true),
		"every drop of the database found: nothing faded, a tick")
	-- A mob you haven't killed: what it can drop (skinning after, with its pelt).
	MOBS.target = { name = "Young Wolf", level = 2, guid = "Creature-0-1-0-1-118-00000051" }
	Fire("PLAYER_TARGET_CHANGED")
	check(known[3] == nil or not known[3]:IsShown(), "you can't skin: what skinning gives isn't among it")
	KNOWN_SPELLS[8613] = true -- (Skinning)
	Bt.Draw()
	check(win.KnownLabel:GetText() == "What it can drop" and win.KnownCount:GetText() == "classic database" and not cells[1]:IsShown()
		and known[1].drop.id == 4865 and known[2].drop.id == 2589 and known[3].drop.id == 2318 and known[3].Skin:IsShown()
		and win.Note:GetText():find("No kills of it yet", 1, true), "a mob not killed yet: what it can drop, then what skinning gives")
	known[1]._scripts.OnEnter(known[1])
	check(tipFind("You haven't killed one yet."), "hover: you haven't killed one yet")
	known[1]._scripts.OnLeave(known[1])
	setting("showPoor"):SetValue(false)
	check(known[1].drop.id == 2589, "grey items off: also the database's")
	setting("showPoor"):SetValue(true)
	-- The card beside the mouse stays small: a line and one row, also for a mob not killed yet.
	setting("hoverCard"):SetValue(true)
	MOBS.mouseover = { name = "Young Wolf", level = 2, guid = "Creature-0-1-0-1-118-00000052", pinned = true }
	Fire("UPDATE_MOUSEOVER_UNIT")
	card = select(2, Bt.Frames())
	check(LefthyToolsDB.settings.bestiary.cardUnseen == false and not card:IsShown(),
		"a mob not killed yet: no card by default (only the ones you've killed)")
	setting("cardUnseen"):SetValue(true)
	Fire("UPDATE_MOUSEOVER_UNIT")
	check(card:IsShown() and card.Kills:GetText():find("Not killed yet: classic database", 1, true) and card.cells[1].Icon.desaturated
		and select(2, card:GetSize()) < 70, "the card over a mob not killed yet: the database's drops, faded, one row")
	MOBS.mouseover = { name = "Defias Bandit", level = 9, guid = "Creature-0-1-0-1-116-00000053", pinned = true }
	Fire("UPDATE_MOUSEOVER_UNIT")
	local ghost = false
	for _, c in ipairs(card.cells) do if c:IsShown() and c.drop and c.drop.unseen then ghost = true end end
	check(card.Kills:GetText():find("5 kills", 1, true) and not ghost, "over one killed before: only your drops (nothing added)")
	MOBS.mouseover = nil
	Advance(0.1)
	setting("hoverCard"):SetValue(false)
	setting("cardUnseen"):SetValue(false)
	-- The ledger: a row says how many of its drops you've found; the picked mob's not seen yet in a
	-- section of its own, the database's coin.
	Bt.ToggleLedger(116)
	local unseenSection = ledger.Pane.sections.unseen
	check(ledger.rows[1].Known:GetText() == "2/5 found" and unseenSection.Heading:IsShown()
		and unseenSection.Heading:GetText() == "Not seen yet (3), classic database" and unseenSection.cells[1].drop.id == 1019
		and unseenSection.cells[1].Icon.desaturated and ledger.Pane.Stats:GetText():find("2 of its 5 drops found", 1, true)
		and ledger.Pane.Stats:GetText():find("Classic database: ", 1, true),
		"the ledger: 2/5 found in its row; not seen yet, faded, in a section of its own; the database's coin and how many found")
	ledger:Hide()
	local pmark3 = #PRINTED + 1
	SlashCmdList.LEFTHYTOOLS_BESTIARY("data")
	check(printedSince(pmark3):find("4 kinds of mobs, 2 of them with their health, from test", 1, true), "/bestiary data: what it holds")
	-- Switched off: your numbers alone.
	setting("dropData"):SetValue(false)
	MOBS.target = { name = "Defias Bandit", level = 9, guid = "Creature-0-1-0-1-116-00000054" }
	Fire("PLAYER_TARGET_CHANGED")
	check(not win.KnownLabel:IsShown() and not (known[1] and known[1]:IsShown()) and cellOf(win.cells, 2589).drop.classic == nil
		and Bt.Health(116, 9) == nil, "the setting off: no database anywhere (nor health)")
	setting("dropData"):SetValue(true)
	check(#loads == 1, "loaded once only")
	MOBS.target, KNOWN_SPELLS[8613] = nil, nil
	setting("windowUnseen"):SetValue(false)
	-- The pace: what each kill gave in XP (around its killing blow, also when the XP comes first; a
	-- level-up between wraps) and how long it took (since the fight began, or since the last kill in
	-- it). Kept for your level. A Kobold Vermin (119) of its own, so the numbers above stay.
	local kobold = {}
	for i = 1, 13 do kobold[i] = ("Creature-0-1-0-1-119-%08X"):format(0x60 + i) end
	local function kobolds() return LefthyToolsBestiaryDB.mobs[119] end
	local function koboldKill(guid, xp, xpFirst)
		if xp and xpFirst then XP.current = XP.current + xp; Fire("PLAYER_XP_UPDATE", "player") end
		Fire("PARTY_KILL", "Player-1-0", guid)
		if xp and not xpFirst then XP.current = XP.current + xp; Fire("PLAYER_XP_UPDATE", "player") end
	end
	ITEMS[2770] = ITEMS[2770] or { name = "Copper Ore", quality = 1 } -- (its own: Linen Cloth from a third kind would make it a world drop)
	local function koboldLoot(guid)
		LOOT = { { type = 1, id = 2770, source = guid }, { type = 2, source = guid } }
		Fire("LOOT_READY", false)
		MONEY = MONEY + 1500
		Fire("LOOT_CLOSED")
		LOOT = {}
	end
	local function ledgerSort(key)
		ledger.Sort._scripts.OnClick(ledger.Sort)
		for _, row in ipairs(ledger.Sort.List.rows) do if row.value == key then row._scripts.OnClick(row) end end
		_, entries = Bt.Ledger()
	end
	do
		MOBS.target, STATE.target = { name = "Kobold Vermin", level = 17, guid = kobold[1] }, true
		Fire("PLAYER_TARGET_CHANGED")
		Advance(2) -- (the kills above long done)
		Fire("PLAYER_XP_UPDATE", "player") -- (where the XP stands now: other tests set it)
		Advance(2)
		STATE.combat = true
		Fire("PLAYER_REGEN_DISABLED")
		Advance(12)
		koboldKill(kobold[1], 80)
		Advance(8)
		koboldKill(kobold[2], 90, true) -- (its XP first: still its own)
		STATE.combat = false
		Fire("PLAYER_REGEN_ENABLED")
		koboldLoot(kobold[1])
		koboldLoot(kobold[2])
		local pace = kobolds().pace
		check(pace and pace[1] == 19 and pace[2] == 2 and pace[3] == 170 and pace[4] == 2 and pace[5] == 20,
			"two kills in one fight: the XP each gave (80, 90) and the fight's 20 s shared (12 s, then 8 s since the first)")
		local line = win.Pace.Text:GetText() or ""
		check(win.Pace:IsShown() and line:find("Per kill: ", 1, true) and line:find("85 XP", 1, true) and line:find("10 s", 1, true)
			and not line:find("level", 1, true), "the window: a line on it under the portrait, got " .. line)
		win.Pace._scripts.OnEnter(win.Pace)
		check(tipFind("85 XP and 10 s per kill") and tipFind("About 31k XP per hour of fighting (the time between fights not counted)"),
			"hover it: in full, with the XP per hour of fighting")
		win.Pace._scripts.OnLeave(win.Pace)
		-- A kill that levels you up: the rest of the old level and what's in the new one, for the level
		-- it died at. The client may tell the new XP an update before the new level: still one kill's.
		Advance(2)
		XP.current = XP.max - 10
		Fire("PLAYER_XP_UPDATE", "player")
		Advance(2)
		STATE.combat = true
		Fire("PLAYER_REGEN_DISABLED")
		Advance(10)
		Fire("PARTY_KILL", "Player-1-0", kobold[3])
		XP.current, XP.max = 75, 7000
		Fire("PLAYER_XP_UPDATE", "player")
		PLAYER_LEVEL = 20 -- (told after the XP)
		STATE.combat = false
		Fire("PLAYER_REGEN_ENABLED")
		koboldLoot(kobold[3])
		check(pace[1] == 19 and pace[2] == 3 and pace[3] == 255 and pace[5] == 30, "a kill that levels you up: its 85 XP across the level-up, at 19")
		check(win.Pace.Text:GetText():find("(level 19)", 1, true), "now 20: the window says which level that's for")
		-- At the new level it starts again; a kill without XP gave 0 (grey); no fight seen: not timed.
		Advance(2)
		STATE.combat = true
		Fire("PLAYER_REGEN_DISABLED")
		Advance(6)
		koboldKill(kobold[4], 100)
		STATE.combat = false
		Fire("PLAYER_REGEN_ENABLED")
		koboldLoot(kobold[4])
		Advance(3)
		koboldKill(kobold[5])
		koboldLoot(kobold[5])
		pace = kobolds().pace
		check(pace[1] == 20 and pace[2] == 2 and pace[3] == 100 and pace[4] == 1 and pace[5] == 6 and not win.Pace.Text:GetText():find("level", 1, true),
			"a new level: started again (the level told late isn't a second level-up); a kill without XP counts 0; one after the fight ended: not timed")
		IsPlayerAtEffectiveMaxLevel = function() return true end
		koboldKill(kobold[6])
		koboldLoot(kobold[6])
		IsPlayerAtEffectiveMaxLevel = nil
		check(kobolds().kills == 6 and pace[2] == 2, "at the level cap: a kill without XP says nothing about XP")
		-- The ledger: the same in full under the model; sorted by XP per kill or per hour, a row says it.
		Bt.ToggleLedger(119)
		local paceText = ledger.Pane.Pace:GetText() or ""
		check(ledger.Pane.Pace:IsShown() and paceText:find("50 XP and 6 s per kill", 1, true) and paceText:find("About 30k XP per hour", 1, true),
			"the ledger: what a kill pays, under the model, got " .. paceText)
		ledgerSort("xp")
		check(entries[1].creature == 119 and ledger.rows[1].Known:GetText() == "50 XP" and ledger.Sort.Label:GetText() == "XP per kill",
			"sorted by XP per kill: the most first, each row says it")
		ledgerSort("xph")
		check(entries[1].creature == 119 and ledger.rows[1].Known:GetText() == "30k XP/h", "sorted by XP per hour of fighting")
		ledgerSort("name")
		ledger:Hide()
		PLAYER_LEVEL, XP.current, XP.max = 19, 1500, 6000
		MOBS.target = nil
	end
	-- Worth per kill: the coin and what the drops sell for at a vendor (how many per kill times the
	-- price, grey ones too). A price the client doesn't know yet is asked for, once; when it comes,
	-- the window redraws.
	do
		ITEMS[772] = { name = "Large Candle", quality = 0, price = 700 }
		MOCK_ITEM_UNCACHED = 772
		local asked, request = {}, C_Item.RequestLoadItemDataByID
		C_Item.RequestLoadItemDataByID = function(id) asked[#asked + 1] = id end
		Advance(2)
		Fire("PARTY_KILL", "Player-1-0", kobold[7])
		LOOT = { { type = 1, id = 772, quantity = 2, source = kobold[7] }, { type = 2, source = kobold[7] } }
		Fire("LOOT_READY", false)
		MONEY = MONEY + 1500
		Fire("LOOT_CLOSED")
		LOOT = {}
		Bt.Draw()
		local worth, coin, vendor = Bt.Worth(kobolds())
		check(kobolds().kills == 7 and worth == 1500 and coin == 1500 and vendor == 0 and #asked == 1 and asked[1] == 772
			and win.Pace.Text:GetText():find("worth ~15s", 1, true), "a price the client doesn't know yet: asked for, once; nothing meanwhile")
		MOCK_ITEM_UNCACHED = nil
		Fire("GET_ITEM_INFO_RECEIVED", 772, true)
		check(win.Pace.Text:GetText():find("worth ~15s", 1, true), "not at once (prices come in bunches)")
		Advance(0.6)
		worth, coin, vendor = Bt.Worth(kobolds())
		check(worth == 1700 and vendor == 200 and #asked == 1 and win.Pace.Text:GetText():find("Per kill: worth ~17s", 1, true),
			"it came: the window redraws with it (2 candles at 7s over 7 kills: 2s a kill, 17s in all)")
		C_Item.RequestLoadItemDataByID = request
		Bt.ToggleLedger(119)
		local paceText = ledger.Pane.Pace:GetText() or ""
		check(paceText:find("Worth about 17s 0c per kill (15s 0c coin, 2s 0c from drops at a vendor)", 1, true),
			"the ledger: its worth and what it's made of, got " .. paceText)
		ledgerSort("worth")
		check(entries[1].creature == 119 and entries[2].creature == 116 and ledger.rows[1].Known:GetText() == "~17s 0c"
			and ledger.Sort.Label:GetText() == "Worth per kill", "sorted by worth per kill: where farming pays, each row says it")
		ledgerSort("name")
		ledger:Hide()
	end
	-- Where you killed them: you on the map at each killing blow (not in instances), the last 50. The
	-- ledger shows it beside the mob's details: the zone with the most on the world map's art, a dot
	-- each, a picker of its zones.
	do
		local mapWas, posWas = PLAYER_MAP, PLAYER_POS
		kobolds().spots = nil -- (like a record from before)
		Bt.ToggleLedger(119)
		local where = ledger.Pane.where
		check(where.Heading:IsShown() and where.Empty:IsShown() and where.Empty:GetText() == "No kills on a map yet" and not where.Map:IsShown()
			and not where.Zone:IsShown() and not where.Pick:IsShown() and not where.Note:IsShown(),
			"a record from before: the map's box says so quietly, nothing else missing")
		-- The map beside the details, seen without scrolling (in game it was under the drops); the
		-- window still fits a 1366 x 768 screen at the default UI scale (768 high), clamped to it.
		local width, height = ledger:GetSize()
		local boxX, boxY = select(-2, where.Box:GetPoint(1))
		local dropsY = select(-1, ledger.Pane.Scroll:GetPoint(1))
		check(where.Box:GetParent() == ledger.Pane and boxX >= 300 and boxY > -40 and dropsY <= boxY - 220
			and width <= 1366 - 200 and height <= 768 - 120 and ledger._clamped,
			"the map: beside the details at the top of the pane, the drops under both; the window fits a small screen, clamped")
		local function killAt(map, x, y, guid)
			PLAYER_MAP, PLAYER_POS = map, { x, y }
			Fire("PARTY_KILL", "Player-1-0", guid)
			PLAYER_POS = { 0.99, 0.99 } -- (walked over to loot it: where it died counts)
			koboldLoot(guid)
		end
		Advance(2)
		killAt(1429, 0.25, 0.75, kobold[8])
		check(kobolds().spots and #kobolds().spots == 1 and kobolds().spots[1] == 1429250750,
			"a kill: where you were at its killing blow, in one number (map, x and y in thousandths)")
		killAt(1429, 0.5, 0.5, kobold[9])
		check(where.Zone:IsShown() and where.Zone:GetText() == "Elwynn Forest" and not where.Pick:IsShown() and where.Map:IsShown()
			and not where.Empty:IsShown(), "kills in one zone: its name over the map, no picker")
		killAt(1436, 0.4, 0.6, kobold[10])
		INSTANCE, STATE.inInstance = { name = "The Deadmines", type = "party" }, true
		killAt(1429, 0.3, 0.3, kobold[11])
		INSTANCE, STATE.inInstance = nil, nil
		check(kobolds().kills == 11 and #kobolds().spots == 3, "in an instance: counted, but no spot")
		local tiles = where.art.tiles
		check(where.Heading:GetText() == "Where you killed them" and where.Pick:IsShown() and where.Pick.Label:GetText() == "Elwynn Forest (2)"
			and not where.Zone:IsShown() and where.Map:IsShown()
			and #tiles == 12 and tiles[1].path == 142901 and tiles[12].path == 142912 and tiles[12].shown
			and math.abs(tiles[4].coords[2] - 234 / 256) < 1e-6 and tiles[4].coords[4] == 1 and math.abs(tiles[12].coords[4] - 156 / 256) < 1e-6,
			"the ledger: the zone with the most kills on its world map art (4 x 3 tiles, the last column and row cut to the map)")
		width, height = where.Map:GetSize()
		local dots = where.dots
		local _, _, _, x1, y1 = dots[1]:GetPoint(1)
		check(dots[1].shown and dots[2].shown and not (dots[3] and dots[3].shown) and math.abs(width - 330) < 0.01 and math.abs(height - 220) < 0.01
			and math.abs(x1 - 0.2505 * width) < 0.01 and math.abs(y1 + 0.7505 * height) < 0.01 and dots[1]:GetAlpha() < dots[2]:GetAlpha(),
			"a dot for each kill there, where it was; the older fainter")
		-- On the art, what you've explored (the art leaves the rest blank): each area's tiles from its
		-- offset, scaled like the art, the last column a smaller file, cut at the map's edge; not what
		-- only a mouseover shows.
		do
			local overlays, s = where.art.overlays, 330 / 1002
			local function near(a, b) return math.abs(a - b) < 1e-6 end
			local o1, o2, o3 = overlays[1], overlays[2], overlays[3]
			local _, _, _, x2, y2 = o2:GetPoint(1)
			local _, _, _, x3, y3 = o3:GetPoint(1)
			check(#overlays == 3 and o1.path == 7001 and o2.path == 7002 and o3.path == 7004 and o1.shown and o2.shown and o3.shown
				and o1.coords[2] == 1 and near(o1.coords[4], 200 / 256) and near(o1.width, 256 * s) and near(o1.height, 200 * s)
				and near(x2, 356 * s) and near(y2, -50 * s) and near(o2.width, 44 * s) and near(o2.coords[2], 44 / 64)
				and near(x3, 950 * s) and near(y3, -600 * s) and near(o3.width, 52 * s) and near(o3.height, 68 * s)
				and near(o3.coords[2], 52 / 128) and near(o3.coords[4], 68 / 128),
				"what you've explored on the art: its tiles where they go, the last one a smaller file, cut at the edge; not the mouseover one")
			o1.path = nil
			Bt.DrawLedger()
			check(o1.path == nil, "drawn again on the same map: not laid again")
			local elwynn = EXPLORED[1429]
			EXPLORED[1429] = { elwynn[3] }
			Fire("MAP_EXPLORATION_UPDATED")
			Bt.DrawLedger()
			check(o1.path == 7004 and o1.shown and not o2.shown and not o3.shown and #overlays == 3 and tiles[1].shown,
				"explored more (here: less): laid again, the pool's other tiles hidden")
			local api = C_MapExplorationInfo
			C_MapExplorationInfo = nil
			Fire("MAP_EXPLORATION_UPDATED")
			Bt.DrawLedger()
			check(not o1.shown and tiles[12].shown, "no exploration API: the art alone")
			C_MapExplorationInfo, EXPLORED[1429] = api, elwynn
			Fire("MAP_EXPLORATION_UPDATED")
			Bt.DrawLedger()
			check(#overlays == 3 and o1.path == 7001 and o3.shown, "back: laid again from the pool")
		end
		-- More than one zone: the picker lists them, the most kills first, each with its kills; one
		-- picked shows its map and dots; another mob and back: the most kills again.
		do
			where.Pick:Click()
			local list = where.Pick.List
			check(not where.Note:IsShown() and list:IsShown() and list.count == 2 and list.rows[1].Text:GetText() == "Elwynn Forest (2)"
				and list.rows[1].Check:IsShown() and list.rows[2].Text:GetText() == "Westfall (1)" and list.rows[2].value == 1436,
				"several zones: a picker of them, the most kills first, each with its kills")
			list.rows[2]:Click()
			check(not list:IsShown() and where.Pick.Label:GetText() == "Westfall (1)" and where.art.tiles[1].path == 143601 and not where.art.overlays[1].shown
				and where.dots[1].shown and not where.dots[2].shown, "Westfall picked: its map (nothing explored there), its one dot")
			Bt.DrawLedger()
			check(where.Pick.Label:GetText() == "Westfall (1)" and where.art.tiles[1].path == 143601, "the list redraws: the zone stays")
			Bt.ToggleLedger(116)
			Bt.ToggleLedger(119)
			check(where.Pick.Label:GetText() == "Elwynn Forest (2)" and where.art.tiles[1].path == 142901 and where.art.overlays[1].shown,
				"another mob and back: the zone with the most kills again")
		end
		-- A corpse looted without your killing blow seen: you at it then. The last 50 are kept.
		for _ = 1, 47 do table.insert(kobolds().spots, 1, 1429100100) end
		PLAYER_POS = { 0.6, 0.4 }
		koboldLoot(kobold[12])
		check(kobolds().kills == 12 and #kobolds().spots == 50 and kobolds().spots[50] == 1429600400 and kobolds().spots[1] == 1429100100
			and where.Note:IsShown() and where.Note:GetText() == "Your last 50 kills." and where.Pick.Label:GetText() == "Elwynn Forest (49)",
			"a corpse looted without a killing blow seen: where you are; the last 50 kept (said under the map), the oldest goes")
		ledger:Hide()
		PLAYER_MAP, PLAYER_POS = mapWas, posWas
	end
	-- Closed and open again: kept for next time.
	win.Close:Click()
	check(not win:IsShown() and LefthyToolsDB.settings.bestiary.window.shown == false and not button.Open:IsShown(), "the X closes it, kept")
	SlashCmdList.LEFTHYTOOLS_BESTIARY("")
	check(win:IsShown() and LefthyToolsDB.settings.bestiary.window.shown == true, "/bestiary opens it")
	win.Close:Click()
end)()

section("Bestiary: quest drops while questing")
;(function()
	local Bt = ns.Bestiary
	local function setting(id) return REGISTERED_SETTINGS["LefthyTools_bestiary_" .. id] end
	local savedQuests = QUESTS
	ITEMS[1019] = ITEMS[1019] or { name = "Red Linen Bandana", quality = 1 }
	-- Quests wanting items: written the classic way ("Name: 2/6") or the modern one ("0/2 Name", the
	-- numbers given too). The Defias Bandit (116) drops the bandana (the classic database: a quest
	-- item, 66%) and the mace (only yours: 1 in 5 kills).
	QUESTS = {
		{ id = 301, title = "The Defias Brotherhood", objectives = { { text = "Red Linen Bandana: 2/6", finished = false } } },
		{ id = 302, title = "Milk Run", objectives = {
			{ text = "0/2 Ice Cold Milk", finished = false, type = "item", numFulfilled = 0, numRequired = 2 },
			{ text = "Priest's Mace: 0/1", finished = false } } },
	}
	Fire("QUEST_LOG_UPDATE")
	MOCK_ITEM_UNCACHED = 1019 -- (the client doesn't know the bandana yet)
	MOBS.target, STATE.target = { name = "Defias Bandit", level = 9, guid = "Creature-0-1-0-1-116-00000060" }, true
	Bt.Toggle(true)
	local win = Bt.Frames()
	check(win:IsShown() and win.Quest:IsShown() and not win.Quest:GetText():find("Bandana", 1, true)
		and win.Quest:GetText():find("Priest's Mace: 0/1, 20% each, about 5 more kills", 1, true),
		"the window: a quest wants its mace (your chance, 1 in 5 kills); the bandana's name isn't known yet")
	MOCK_ITEM_UNCACHED = nil
	Fire("GET_ITEM_INFO_RECEIVED", 1019, true)
	Advance(0.6)
	local text = win.Quest:GetText()
	check(text:find("^|T[^|]*AvailableQuestIcon:12:12|t Red Linen Bandana: 2/6, 66%% each, about 6 more kills\n")
		and text:find("Priest's Mace", 1, true) and select(3, win.Grid:GetPoint(1)) < -70,
		"its name came: a line for it too (the database's quest chance, 4 more: about 6 kills), the quest's ! in front, the drops under them")
	-- The gnoll: the milk (the database's 10%) and the mace (yours: 1 in 3).
	MOBS.target = { name = "Riverpaw Gnoll", level = 10, guid = "Creature-0-1-0-1-117-00000061" }
	Fire("PLAYER_TARGET_CHANGED")
	text = win.Quest:GetText()
	check(text:find("Ice Cold Milk: 0/2, 10% each, about 20 more kills", 1, true) and text:find("Priest's Mace: 0/1, 33% each, about 3 more kills", 1, true)
		and not text:find("Bandana", 1, true), "another mob: what the quests want of its drops, with its chances")
	-- The log changes often: once, half a second later.
	QUESTS[2].objectives[1] = { text = "1/2 Ice Cold Milk", finished = false, type = "item", numFulfilled = 1, numRequired = 2 }
	for _ = 1, 3 do Fire("QUEST_LOG_UPDATE") end
	check(win.Quest:GetText():find("0/2", 1, true), "the quest log changed: not at once (it changes often)")
	Advance(0.6)
	check(win.Quest:GetText():find("Ice Cold Milk: 1/2, 10% each, about 10 more kills", 1, true), "half a second later: 1/2, about 10 more")
	QUESTS[2].objectives[1] = { text = "2/2 Ice Cold Milk", finished = true, type = "item", numFulfilled = 2, numRequired = 2 }
	Fire("BAG_UPDATE_DELAYED")
	Advance(0.6)
	text = win.Quest:GetText()
	check(text:find("^|T[^|]*AvailableQuestIcon[^\n]*Priest's Mace") and text:find("ReadyCheck-Ready:12:12|t |cff888888Ice Cold Milk: 2/2|r", 1, true),
		"done: a tick, grey, after the ones still wanted")
	-- The card beside the mouse: one line more, for a quest still wanting one of its drops.
	setting("hoverCard"):SetValue(true)
	MOBS.mouseover = { name = "Riverpaw Gnoll", level = 10, guid = "Creature-0-1-0-1-117-00000062", pinned = true }
	Fire("UPDATE_MOUSEOVER_UNIT")
	local card = select(2, Bt.Frames())
	check(card:IsShown() and card.Kills:GetText():find("3 kills", 1, true) and card.cells[1]:IsShown() and card.Quest:IsShown()
		and card.Quest:GetText():find("Priest's Mace: 0/1, 33% each, about 3 more kills", 1, true)
		and not card.Quest:GetText():find("Milk", 1, true) and select(2, card:GetSize()) == 80,
		"the card: its kills, its drops, and a line for the quest still wanting one (not the one done)")
	-- A mob you haven't killed: the card too, when a quest wants its drop (not otherwise).
	MOBS.mouseover = { name = "Young Wolf", level = 2, guid = "Creature-0-1-0-1-118-00000063", pinned = true }
	Fire("UPDATE_MOUSEOVER_UNIT")
	check(not card:IsShown(), "a mob not killed yet, no quest wanting its drops: no card")
	QUESTS[3] = { id = 303, title = "Pelts", objectives = { { text = "Ruined Pelt: 1/5", finished = false } } }
	Fire("QUEST_LOG_UPDATE")
	Advance(0.6)
	Fire("UPDATE_MOUSEOVER_UNIT")
	check(card:IsShown() and card.Kills:GetText():find("Not killed yet", 1, true) and not card.cells[1]:IsShown()
		and card.Quest:GetText():find("Ruined Pelt: 1/5, 40% each, about 10 more kills", 1, true) and select(2, card:GetSize()) < 50,
		"a quest wants its drop: the card for a mob not killed yet, a line and the quest's (no icons)")
	QUESTS[3] = nil
	Fire("QUEST_LOG_UPDATE")
	Advance(0.6)
	check(not card:IsShown(), "the quest gone: the card goes")
	MOBS.mouseover = nil
	Advance(0.1)
	setting("hoverCard"):SetValue(false)
	-- Names the client doesn't know yet, coming at different times: each line drawn when its name
	-- comes, each asked for once.
	do
		ITEMS[2070] = ITEMS[2070] or { name = "Darnassian Bleu", quality = 1 }
		ITEMS[774] = ITEMS[774] or { name = "Malachite", quality = 2 }
		local asked, request = {}, C_Item.RequestLoadItemDataByID
		C_Item.RequestLoadItemDataByID = function(id) asked[#asked + 1] = id end
		MOCK_ITEM_UNCACHED = { [2070] = true, [774] = true }
		QUESTS[3] = { id = 304, title = "Cheese and gems", objectives = {
			{ text = "Darnassian Bleu: 0/3", finished = false }, { text = "Malachite: 0/1", finished = false } } }
		Fire("QUEST_LOG_UPDATE")
		MOBS.target = { name = "Defias Bandit", level = 9, guid = "Creature-0-1-0-1-116-00000064" }
		Fire("PLAYER_TARGET_CHANGED")
		MOCK_ITEM_UNCACHED = { [774] = true }
		Fire("GET_ITEM_INFO_RECEIVED", 2070, true)
		Advance(0.6)
		local lines = win.Quest:GetText()
		check(lines:find("Darnassian Bleu: 0/3", 1, true) and not lines:find("Malachite", 1, true), "one name came: its line")
		MOCK_ITEM_UNCACHED = nil
		Fire("GET_ITEM_INFO_RECEIVED", 774, true)
		Advance(0.6)
		check(win.Quest:GetText():find("Malachite: 0/1", 1, true) and #asked == 0,
			"the other came after the window had redrawn: its line too (both asked for before, when the bandit's drops were first drawn: not again)")
		C_Item.RequestLoadItemDataByID, QUESTS[3] = request, nil
	end
	do -- (its own Value used to answer nothing at all for a secret, and tonumber() wants a value)
		local count = C_QuestLog.GetNumQuestLogEntries
		C_QuestLog.GetNumQuestLogEntries = function() return SECRET end
		Fire("QUEST_LOG_UPDATE")
		local ok = pcall(Bt.QuestDrops, 116, Bt.Mob(116))
		C_QuestLog.GetNumQuestLogEntries = count
		check(ok, "a quest log the game keeps secret doesn't break the quest drops")
	end
	QUESTS, MOBS.target, STATE.target = savedQuests, nil, false
	Fire("QUEST_LOG_UPDATE")
	Advance(0.6)
	check(not win.Quest:IsShown(), "no quest wanting its drops: no line")
	Bt.Toggle(false)
end)()

section("Bestiary: wish list and dry streak")
;(function()
	local Bt = ns.Bestiary
	local function setting(id) return REGISTERED_SETTINGS["LefthyTools_bestiary_" .. id] end
	local function tipFind(text)
		for _, l in ipairs(TOOLTIP.lines) do if l:find(text, 1, true) then return true end end
		return false
	end
	local function cellOf(list, id) for _, c in ipairs(list) do if c:IsShown() and c.drop and c.drop.id == id then return c end end end
	ITEMS[774] = ITEMS[774] or { name = "Malachite", quality = 2 }
	LefthyToolsDropData.mobs[8119] = "774:2:500" -- (a mob the Bestiary has never met: no name)
	check(LefthyToolsBestiaryDB.wishes == nil, "no wish list yet: nothing saved for it")
	-- Alt-click on a drop in the window: on the wish list, a star on it.
	MOBS.target, STATE.target = { name = "Defias Bandit", level = 9, guid = "Creature-0-1-0-1-116-00000070" }, true
	Bt.Toggle(true)
	local win = Bt.Frames()
	local linen = cellOf(win.cells, 2589)
	linen._scripts.OnEnter(linen)
	check(not linen.Star:IsShown() and tipFind("Alt-click: on your wish list"), "a drop: no star; its tooltip says how to pin it")
	local pmark = #PRINTED + 1
	STATE.alt = true
	linen._scripts.OnClick(linen)
	STATE.alt = false
	local wish = Bt.Wish(2589)
	linen = cellOf(win.cells, 2589)
	check(wish and wish[1] == time() and wish[2] == 0 and wish[4] == "Linen Cloth" and wish[5] == 1 and linen.Star:IsShown()
		and printedSince(pmark):find("is on your wish list", 1, true) and tipFind("On your Bestiary wish list (0 kills since you pinned it)")
		and tipFind("Alt-click: off your wish list"), "Alt-click: on the wish list (when, its name and quality kept), a star, a chat line")
	linen._scripts.OnLeave(linen)
	Advance(1)
	-- Item tooltips say so, also with the drop chances there switched off.
	GameTooltip:SetOwner(UIParent)
	GameTooltip:SetHyperlink("item:2589")
	check(tipFind("Bestiary  drop chance (kills)") and tipFind("On your Bestiary wish list (0 kills"), "an item's tooltip: on your wish list")
	setting("itemTooltip"):SetValue(false)
	GameTooltip:SetOwner(UIParent)
	GameTooltip:SetHyperlink("item:2589")
	check(not tipFind("drop chance") and tipFind("On your Bestiary wish list"), "the drop chances off: still on your wish list")
	setting("itemTooltip"):SetValue(true)
	-- /bestiary wish <item link or ID>: on, and off again; /bestiary wishes: the list.
	SlashCmdList.LEFTHYTOOLS_BESTIARY("wish 774")
	SlashCmdList.LEFTHYTOOLS_BESTIARY("wish " .. ItemLink(1179))
	check(Bt.Wish(774) and Bt.Wish(774)[4] == "Malachite" and Bt.Wish(1179), "/bestiary wish with an ID or a link: pinned")
	pmark = #PRINTED + 1
	SlashCmdList.LEFTHYTOOLS_BESTIARY("wish 1179")
	check(not Bt.Wish(1179) and printedSince(pmark):find("is off your wish list", 1, true), "again: off it")
	pmark = #PRINTED + 1
	SlashCmdList.LEFTHYTOOLS_BESTIARY("wish 99999")
	check(printedSince(pmark):find("there's no item 99999", 1, true) and not Bt.Wish(99999), "an item that doesn't exist: said so")
	pmark = #PRINTED + 1
	SlashCmdList.LEFTHYTOOLS_BESTIARY("wishes")
	local listed = printedSince(pmark)
	check(listed:find("your wish list (2)", 1, true) and listed:find("[Linen Cloth]|h|r: 0 kills since you pinned it, likeliest from", 1, true)
		and listed:find("[Malachite]|h|r: 0 kills since you pinned it, likeliest from Defias Bandit (1.3%)", 1, true),
		"/bestiary wishes: each, the kills since and where it comes from likeliest, got\n" .. listed)
	-- The card: wished items it drops first, with their star (from the database, faded, when not had yet).
	setting("hoverCard"):SetValue(true)
	MOBS.mouseover = { name = "Defias Bandit", level = 9, guid = "Creature-0-1-0-1-116-00000071", pinned = true }
	Fire("UPDATE_MOUSEOVER_UNIT")
	local card = select(2, Bt.Frames())
	local cells = card.cells
	check(card:IsShown() and cells[1].drop.id == 2589 and cells[1].Star:IsShown() and cells[2].drop.id == 774 and cells[2].drop.unseen
		and cells[2].Icon.desaturated and cells[2].Star:IsShown() and not cells[3].Star:IsShown(),
		"the card: wished items first with their star (the Malachite from the database, faded: not had yet)")
	MOBS.mouseover = { name = "Young Wolf", level = 2, guid = "Creature-0-1-0-1-118-00000072", pinned = true }
	Fire("UPDATE_MOUSEOVER_UNIT")
	check(card:IsShown() and card.Kills:GetText():find("Not killed yet", 1, true) and cells[1].drop.id == 2589 and cells[1].Star:IsShown()
		and not cells[2]:IsShown(), "a mob not killed yet that drops a wished item: its card, with just that")
	MOBS.mouseover = nil
	Advance(0.1)
	setting("hoverCard"):SetValue(false)
	-- The ledger: a strip of the wishes at the top; hover: where each drops; click: search for it.
	Bt.ToggleLedger(116)
	local ledger = Bt.Ledger()
	local strip = ledger.wishes
	check(strip[1]:IsShown() and strip[1].id == 2589 and strip[2]:IsShown() and strip[2].id == 774 and not (strip[3] and strip[3]:IsShown())
		and ledger.WishLabel:GetText():find("Wish list", 1, true), "the ledger: the wish list as a strip of icons, the first pinned first")
	strip[2]._scripts.OnEnter(strip[2])
	check(TOOLTIP.title:find("Malachite", 1, true) and tipFind("Defias Bandit  1.3% |cff888888classic database|r")
		and tipFind("and 1 more in the classic database") and tipFind("On your Bestiary wish list (0 kills"),
		"hover: the database's mobs you've met, named; the one you haven't, counted")
	strip[2]._scripts.OnLeave(strip[2])
	strip[1]._scripts.OnEnter(strip[1])
	check(tipFind("Defias Bandit  ") and tipFind("Young Wolf  15% |cff888888classic database|r") and not tipFind("more in the classic"),
		"your own drops with your kills, the database's for a mob you've only seen")
	strip[1]._scripts.OnLeave(strip[1])
	strip[2]._scripts.OnClick(strip[2])
	check(ledger.Search:GetText() == "Malachite", "a click searches for it")
	ledger.Search:SetText("")
	STATE.alt = true
	strip[2]._scripts.OnClick(strip[2])
	STATE.alt = false
	check(not Bt.Wish(774) and not strip[2]:IsShown(), "Alt-click: off the list")
	local mace = cellOf(ledger.Pane.sections.own.cells, 2075)
	STATE.alt = true
	mace._scripts.OnClick(mace)
	STATE.alt = false
	check(Bt.Wish(2075) and cellOf(ledger.Pane.sections.own.cells, 2075).Star:IsShown() and strip[2]:IsShown() and strip[2].id == 2075,
		"Alt-click on a drop in the ledger: pinned, a star, in the strip")
	ledger:Hide()
	-- The dry streak: kills of mobs that drop it count, their chances add up; when it drops, one quiet
	-- line (after how many, how many expected) and it's off the list.
	Advance(1)
	SlashCmdList.LEFTHYTOOLS_BESTIARY("wish 774")
	local function kill(guid, loot)
		Fire("PARTY_KILL", "Player-1-0", guid)
		for _, slot in ipairs(loot) do slot.source = guid end
		LOOT = loot
		Fire("LOOT_READY", false)
		Fire("LOOT_CLOSED")
		LOOT = {}
	end
	kill("Creature-0-1-0-1-116-00000073", { { type = 1, id = 4865 } })
	LOOT_EMPTY["Creature-0-1-0-1-116-00000074"] = true
	Fire("PARTY_KILL", "Player-1-0", "Creature-0-1-0-1-116-00000074")
	Advance(6.2)
	kill("Creature-0-1-0-1-117-00000075", { { type = 1, id = 1179 } }) -- (a gnoll: no Malachite)
	check(Bt.Wish(774)[2] == 2 and near(Bt.Wish(774)[3], 0.0256, 1e-9) and Bt.Wish(2589)[2] == 3,
		"kills of mobs that drop it count (an empty corpse too, not the gnoll for the Malachite), their chances add up")
	pmark = #PRINTED + 1
	kill("Creature-0-1-0-1-116-00000076", { { type = 1, id = 774 }, { type = 1, id = 4865 } })
	local said = printedSince(pmark)
	check(said == "|cffe0b060Bestiary|r: " .. ItemLink(774) .. " after 3 kills (about 78 expected); off your wish list."
		and not Bt.Wish(774) and cellOf(win.cells, 774) and not cellOf(win.cells, 774).Star:IsShown(),
		"it drops: one line, after 3 kills (78 expected: 1.28% each), and it's off the list, got\n" .. said)
	pmark = #PRINTED + 1
	kill("Creature-0-1-0-1-116-00000077", { { type = 1, id = 2589 } })
	check(printedSince(pmark):find("[Linen Cloth]|h|r after 5 kills (about 3 expected); off your wish list.", 1, true),
		"another: the chances of different mobs added up (5 kills, about 3 expected)")
	SlashCmdList.LEFTHYTOOLS_BESTIARY("wish 2075")
	check(LefthyToolsBestiaryDB.wishes == nil, "the last one off: nothing kept for it")
	LefthyToolsDropData.mobs[8119], MOBS.target, STATE.target = nil, nil, false
	Bt.Toggle(false)
end)()

section("Bestiary: counting, more cases")
;(function()
	local Bt = ns.Bestiary
	local function logged()
		local mark = #PRINTED + 1
		SlashCmdList.LEFTHYTOOLS_BESTIARY("log")
		return printedSince(mark)
	end
	-- Someone else's mob (they hit it first, my killing blow): its corpse isn't mine, so it's no kill
	-- without drops; the log says why.
	do
		local stolen = "Creature-0-1-0-1-116-00000080"
		MOBS.target, STATE.target, STATE.tapDenied = { name = "Defias Bandit", level = 9, guid = stolen, dead = true }, true, true
		LOOT_EMPTY[stolen] = true
		Fire("PARTY_KILL", "Player-1-0", stolen)
		check(Bt.Pending()[stolen] == nil and logged():find("Defias Bandit: tapped by someone else", 1, true),
			"someone else's tap: not waiting to be counted (it would count as a kill without drops), the log says so")
		MOBS.target, STATE.target, STATE.tapDenied = nil, false, false
	end
	-- A /reload forgets this session's corpses; the log (saved) still knows the last ones: a corpse
	-- looted again after it counts once, and one said empty and looted after it adds its items to
	-- that kill. (From the wish list's kills a moment ago.)
	do
		local bandits = LefthyToolsBestiaryDB.mobs[116]
		local kills, cloth = bandits.kills, bandits.items[2589][1]
		Bt.Forget() -- (what a /reload forgets)
		local function loot(guid, id)
			LOOT = { { type = 1, id = id, source = guid } }
			Fire("LOOT_READY", false)
			Fire("LOOT_CLOSED")
			LOOT = {}
		end
		loot("Creature-0-1-0-1-116-00000077", 2589) -- (looted before the /reload)
		check(bandits.kills == kills and bandits.items[2589][1] == cloth and logged():find("Defias Bandit: looted before", 1, true),
			"looted before a /reload, again after it: counted once")
		loot("Creature-0-1-0-1-116-00000074", 2589) -- (said empty before the /reload)
		check(bandits.kills == kills and bandits.items[2589][1] == cloth + 1 and logged():find("Defias Bandit: looted (said empty before)", 1, true),
			"said empty before a /reload, looted after it: its items join that kill")
		-- Switched off with the ledger open: it closes too. Switched off with a loot window open (its
		-- LOOT_CLOSED doesn't come then): on again, the next loot window still counts.
		Bt.ToggleLedger(116)
		local ledger = Bt.Ledger()
		LOOT = { { type = 1, id = 2589, source = "Creature-0-1-0-1-116-00000081" } }
		Fire("LOOT_READY", false)
		LT:SetModuleEnabled("bestiary", false)
		Fire("LOOT_CLOSED")
		check(bandits.kills == kills + 1 and not ledger:IsShown(), "switched off: the ledger closes too")
		LT:SetModuleEnabled("bestiary", true)
		loot("Creature-0-1-0-1-116-00000082", 2589)
		check(bandits.kills == kills + 2, "switched off in a loot window and on again: the next loot window counts")
	end
end)()
