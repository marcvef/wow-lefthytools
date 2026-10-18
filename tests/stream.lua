-- Beacon's fight stream: the sensor, the window, watching friends, the battle row.
-- Needs: beacon.lua, only for the clock: the battle row plays a look's moments one after another,
-- looks come every 0.5 s on Beacon's tick, and which numbers float at a check depends on where that
-- tick stands when this file begins.
local suite = ...
local check, section, ns, LT, lefthy = suite.check, suite.section, suite.ns, suite.LT, suite.lefthy
local printedSince, sentTo, anna = suite.printedSince, suite.sentTo, suite.anna
local pinOf, tooltipHas = suite.pinOf, suite.tooltipHas
local BB = ns.Beacon
local BDB = LefthyToolsDB.settings.beacon
local function B(id) return REGISTERED_SETTINGS["LefthyTools_beacon_" .. id] end
local mark, pmark

section("Beacon: fight stream")
do
	check(BDB.streamShare == true and BDB.streamWatchedDot == true and BDB.streamFlights == true and BDB.streamMapClick == true
		and B("streamShare") and B("streamWatchedDot") and B("streamFlights") and B("streamMapClick") and not B("fightStream")
		and SETTINGS_BUTTONS["Your own stream"] and SETTINGS_BUTTONS["Stream window"],
		"on by default (friends can watch my fights), its settings and buttons; the test switch is gone")
	local S = BB.Stream
	local function dot(name, key)
		for _, d in ipairs(BB.StreamDots(key)) do if d.key and d.mob.name == name then return d end end
	end
	local function used(key)
		local n = 0
		for _, d in ipairs(BB.StreamDots(key)) do if d.key and d:IsShown() then n = n + 1 end end
		return n
	end
	local function tooltipFind(text)
		for _, l in ipairs(TOOLTIP.lines) do if l:find(text, 1, true) then return true end end
		return false
	end
	-- The floating numbers in a window (mine by default): the one with this text, how many float.
	local function floatWith(text, w)
		for _, f in ipairs((w or LefthyToolsStreamFrame).Floats.list) do
			if f.on and f:IsShown() and f:GetText():find(text, 1, true) then return f end
		end
	end
	local function floating(w)
		local n = 0
		for _, f in ipairs((w or LefthyToolsStreamFrame).Floats.list) do if f.on and f:IsShown() then n = n + 1 end end
		return n
	end
	-- A number floating twice (each moment shows once, though it comes again).
	local function twice(w)
		local seen = {}
		for _, f in ipairs((w or LefthyToolsStreamFrame).Floats.list) do
			if f.on and f:IsShown() then
				if seen[f:GetText()] then return true end
				seen[f:GetText()] = true
			end
		end
		return false
	end

	-- The preview: made-up mobs around a made-up friend.
	math.randomseed(3) -- (the learning draws random places: the same ones every run)
	local realTiles = ns.MINIMAP_TILES
	ns.MINIMAP_TILES = { [0] = {} } -- (made-up minimap tiles around the test world)
	for x = 25, 37 do for y = 25, 37 do ns.MINIMAP_TILES[0][x * 100 + y] = 900000 + x * 100 + y end end
	lefthy("stream preview")
	Advance(0.6)
	local win = LefthyToolsStreamFrame
	check(win and win:IsShown() and win.Title:GetText():find("Anna", 1, true) and win.Live.Text:GetText() == "DEMO"
		and used() == 7 and not win.Hint:IsShown(), "/lefthy stream preview: the window, a friend, five mobs and two players (no word about guessing)")
	local tank, passer = dot("Bob"), dot("Cedric")
	check(tank and tank.Ring.color[3] == 1 and tank.Ring.color[1] < 0.5 and tank.Name:GetText() == "Bob" and tank.Body.color[1] > 0.7
		and passer and passer.Ring.color[1] > 0.8 and passer.Ring.color[3] > 0.8,
		"players: class colours; her group member with a blue ring and his name, someone passing by with a white one")
	check(math.abs(win._scale - 0.8) < 0.001 and win._strata == "HIGH", "compact: four fifths of its old size")
	local leader, gnoll = dot("Bandit leader"), dot("Gnoll")
	check(leader.Ring:IsShown() and gnoll.ty < 0 and gnoll.Body.alpha < 1 and not gnoll.Ring:IsShown(),
		"an elite has a gold ring; a mob without a direction sits behind, faint")
	check(win.Power:IsShown() and win.Power.color[3] == 1, "her mana, a thin blue bar under where she is")
	check(win.Health:IsShown() and win.Health.color[2] > 0.7 and win.HealthText:GetText():find("^~%d+%%$"), "her health above it, green, about")
	-- Resizing: the corner at the bottom right; the size is kept, the top left corner stays.
	do
		local p = win._points[1]
		local left, top = p[4] * win._scale, p[5] * win._scale
		CURSOR.x, CURSOR.y = 500, 300
		win.Grip._scripts.OnMouseDown(win.Grip)
		CURSOR.x = 550
		win.Grip._scripts.OnUpdate(win.Grip, 0.05)
		win.Grip._scripts.OnMouseUp(win.Grip)
		p = win._points[1]
		check(math.abs(win._scale - 1) < 0.001 and math.abs(LefthyToolsDB.streamWindows.me - 1) < 0.001 and not win.Grip._scripts.OnUpdate
			and math.abs(p[4] * win._scale - left) < 0.01 and math.abs(p[5] * win._scale - top) < 0.01,
			"dragging the corner: bigger, kept for next time, its top left corner where it was")
		win.Grip._scripts.OnMouseDown(win.Grip)
		CURSOR.x = 500
		win.Grip._scripts.OnUpdate(win.Grip, 0.05)
		win.Grip._scripts.OnMouseUp(win.Grip)
		check(math.abs(win._scale - 0.8) < 0.001 and math.abs(LefthyToolsDB.streamWindows.me - 0.8) < 0.001, "and back")
	end
	-- The map under it, to scale (a yard on the map is a yard on the rings), where I stand in the
	-- middle: the minimap's own tiles (3 x 3 of the world's 533 yd grid; here made-up file IDs) ...
	local px = (220 / 2 - 8) / 40 -- pixels per yard
	local function shownTiles(w)
		local list = {}
		for _, t in ipairs((w or win).Map._textures or {}) do
			if t.shown and t.path and t:GetObjectType() ~= "MaskTexture" then list[#list + 1] = t end
		end
		return list
	end
	local hereN, hereW = UnitPosition("player")
	local tx, ty = 32 - hereW / (1600 / 3), 32 - hereN / (1600 / 3)
	local x0, y0 = math.floor(tx) - 1, math.floor(ty) - 1
	local tiles = shownTiles()
	local mapPoint = win.Map._points[#win.Map._points]
	check(win.Map:IsShown() and not win.Plain:IsShown() and #tiles == 9 and tiles[1].path == 900000 + x0 * 100 + y0
		and tiles[9].path == 900000 + (x0 + 2) * 100 + y0 + 2 and math.abs(tiles[1].width - 1600 / 3 * px) < 0.01
		and math.abs(mapPoint[4] + (tx - x0) * 1600 / 3 * px) < 0.01 and math.abs(mapPoint[5] - (ty - y0) * 1600 / 3 * px) < 0.01,
		"the map under the rings: the minimap's tiles around me, to scale, where I stand in the middle")
	-- ... or, where there are none, the world map's art of my zone (LT.MapArt, like the ledger's map),
	-- with what I've explored of it.
	ns.MINIMAP_TILES = {}
	lefthy("stream preview")
	Advance(0.6)
	tiles = shownTiles()
	mapPoint = win.Map._points[#win.Map._points]
	do
		local art = S.View("me").map.art
		check(#tiles == 15 and art.tiles[1].shown and art.tiles[1].path == 142901 and art.tiles[12].path == 142912
			and math.abs(art.tiles[1].width - 256 * 1000 * px / 1002) < 0.01
			and math.abs(mapPoint[4] + (1000 - hereW) * px) < 0.01 and math.abs(mapPoint[5] - (1000 - hereN) * px) < 0.01,
			"no minimap tiles: my zone's world map art (12 tiles), to scale, where I stand in the middle")
		local sx, sy = 1000 * px / 1002, 1000 * px / 668 -- (the zone's yards: the art's pixels a little wider than tall here)
		local o = art.overlays
		local _, _, _, x2, y2 = o[2]:GetPoint(1)
		check(o[1].shown and o[1].path == 7001 and o[2].shown and o[3].shown and o[3].path == 7004 and math.abs(x2 - 356 * sx) < 0.01
			and math.abs(y2 + 50 * sy) < 0.01 and math.abs(o[1].height - 200 * sy) < 0.01,
			"... and what I've explored of it on the art, scaled like it (the minimap's tiles have it already)")
		-- Explored more while it shows: laid again on the next frame, not in the event. (MoveMap called
		-- as a frame would: no time passes.)
		local view, elwynn = S.View("me"), EXPLORED[1429]
		EXPLORED[1429] = { elwynn[3] }
		Fire("MAP_EXPLORATION_UPDATED")
		check(o[2].shown and o[1].path == 7001, "explored more: nothing laid in the event")
		S.MoveMap(view, hereN, hereW, 0, 1429)
		check(o[1].path == 7004 and o[1].shown and not o[2].shown and not o[3].shown and art.tiles[12].shown and win.Map:IsShown(),
			"the next frame: laid again, still shown")
		EXPLORED[1429] = elwynn
		Fire("MAP_EXPLORATION_UPDATED")
		S.MoveMap(view, hereN, hereW, 0, 1429)
		check(o[1].path == 7001 and o[3].shown, "and back")
		-- At sea the minimap has no tile under you (here only land to the east): not an empty map (as
		-- the first round found it), the zone's art; no art either, or far off it: the plain rings.
		local here = math.floor(tx) * 100 + math.floor(ty)
		ns.MINIMAP_TILES = { [0] = { [here + 100] = 900001 } }
		S.MoveMap(view, hereN, hereW, 0, 1429)
		check(win.Map:IsShown() and not win.Plain:IsShown() and #shownTiles() == 15 and art.tiles[1].shown,
			"at sea, no minimap tile under me: my zone's art, not an empty map")
		S.MoveMap(view, hereN, hereW, 0, nil)
		check(not win.Map:IsShown() and win.Plain:IsShown(), "at sea without art: the plain rings")
		S.MoveMap(view, hereN - 1100, hereW, 0, 1429)
		check(not win.Map:IsShown() and win.Plain:IsShown(), "far off the zone's art (nothing of it in the rings): the plain rings")
		ns.MINIMAP_TILES = { [0] = { [here] = 900002 } }
		S.MoveMap(view, hereN, hereW, 0, 1429)
		check(win.Map:IsShown() and #shownTiles() == 1 and shownTiles()[1].path == 900002 and not art.tiles[1].shown,
			"back by the shore: the minimap's tile under me (the sea around it stays empty, as on the minimap)")
		ns.MINIMAP_TILES = {}
		S.MoveMap(view, hereN, hereW, 0, 1429)
	end
	local act = win.Act
	check(act.Name:GetText() == "Spell 133" and act.Icon:IsShown() and act.Bar.width > 1 and act.Bar.width < 50
		and act.Recent[1]:IsShown() and act.Recent[1].path == 100133 and act.Recent[4]:IsShown() and not act.Recent[5]:IsShown(),
		"what she's doing: the spell she's casting, with its bar, and the ones before it, newest first")
	local before = leader.tx * leader.tx + leader.ty * leader.ty
	Advance(3)
	check(leader.tx * leader.tx + leader.ty * leader.ty < before and math.abs(leader.x - leader.tx) < 3,
		"mobs move, and their dots glide after them")
	Advance(0.8) -- (her Fireball lands first; then the bandit's hit, a turn later)
	do
		local dump = {}
		for _, f in ipairs(win.Floats.list) do dump[#dump + 1] = tostring(f.on) .. ":" .. tostring(f:GetText()) .. "@" .. tostring(f.age) end
		local b = S.View("me").battle or {}
		local q = {}
		for _, a in ipairs(b.queue or {}) do q[#q + 1] = a.kind end
		check(floatWith("-24") and floatWith("-24").anchor == win.Foes.Hero, "the bandits hit her: the numbers float up from her model; floats "
			.. table.concat(dump, " | ") .. " action " .. tostring(b.action and b.action.kind) .. " queue " .. table.concat(q, ","))
	end
	-- The battle row: on the left the preview's made-up friend, out of reach (her character isn't on
	-- this client): her class's emblem; the mobs she fights on the right, the
	-- fight played on them.
	do
		local row = win.Foes
		local hero, leaderSlot = row.Hero, row.slots[1]
		check(hero.Emblem:IsShown() and (hero.Emblem.atlas or hero.Emblem.path) and not hero.Real:IsShown() and not hero.Shifted:IsShown()
			and hero.Away:IsShown() and hero.Away:GetText() == "out of reach", "her model, out of reach: her class's emblem, 'out of reach' under it")
		check(hero.Face:IsShown() and hero.Face.portrait == "player" and hero.Emblem.width == 24,
			"with a face on it (the preview's: mine), the emblem smaller under it: a bobblehead")
		check(leaderSlot.Model._anims and leaderSlot.Model._anims[9] and leaderSlot.Model._anims[16] and leaderSlot.Model._paused == false
			and leaderSlot.Model._facing == -0.45, "her target flinched at her Fireball and struck back; the mobs move and face her")
		local loss = floatWith("-13%")
		check(loss and loss.anchor == leaderSlot, "what her Fireball took floats up from it: a percent (an elite's health isn't known)")
		local flash = leaderSlot.Flash.color
		check(flash[1] == 1 and flash[2] == 0.5 and flash[3] == 0.1 and leaderSlot.Flash.blend == "ADD",
			"her Fireball's hit flashed in fire's orange (not the red of a blow)")
		-- Spell schools: generated from the client's tables (Data/SpellSchools.lua), every rank (some as
		-- ranges); physical ones aren't listed.
		check(S.SpellSchool(133) == "fire" and S.SpellSchool(10150) == "fire" and S.SpellSchool(116) == "frost" and S.SpellSchool(2136) == "fire"
			and S.SpellSchool(686) == "shadow" and S.SpellSchool(585) == "holy" and S.SpellSchool(403) == "nature"
			and S.SpellSchool(5143) == "arcane" and S.SpellSchool(1752) == nil and S.SpellSchool(SECRET) == nil and S.SpellSchool(nil) == nil,
			"spell schools: Fireball (also a rank inside a range), Frostbolt, Fire Blast, Shadow Bolt, Smite, Lightning Bolt, Arcane "
			.. "Missiles; Sinister Strike is physical; a hidden ID asks nothing")
	end
	do
		local slots = win.Foes.slots
		check(slots[1]:IsShown() and slots[1].Model._creature == 448 and slots[1].Ring:IsShown() and slots[2].Model._creature == 116
			and slots[3]:IsShown() and slots[3].Unknown:IsShown() and not (slots[4] and slots[4]:IsShown())
			and slots[1].Bar._value > 0.8 and slots[1].Bar._value < 1,
			"under her spells, the three she fights: her target first (gold), still models, health (the mage's not known)")
		local loads = slots[1].Model._loads
		win:SetScale(0.5)
		Advance(0.6)
		check(slots[1].Model._loads == loads + 1 and math.abs(slots[1].scale - slots[1]:GetEffectiveScale()) < 0.001,
			"the window smaller: the models load again (their camera fits the new size)")
		win:SetScale(0.8)
		Advance(0.6)
	end
	check(leader.Target:IsShown() and leader.Name:GetText() == "Bandit leader 16", "her target: a white ring, named with its level")
	check(win.Status:GetText():find("on Anna", 1, true) and win.Status:GetText():find("near", 1, true), "the bottom line: how many on her, how many near")
	Advance(10) -- (12 s after the mobs moved: 1.2 of them went to the size check, 0.8 to her hit)
	local bandit = dot("Bandit")
	check(bandit and bandit.Skull:IsShown() and not bandit.Body:IsShown(), "a mob that dies: a skull ...")
	check(floatWith("+87 XP") and win.Kills:GetText() == "1 kill", "her kill: its XP floats up, 1 kill")
	do -- Her Polymorph at the mage (it went off 13.5 s into the loop): a sheep in the row.
		local sheep
		for _, s in ipairs(win.Foes.slots) do
			if s:IsShown() and s.key == "mage" then sheep = s end
		end
		check(sheep and sheep.Model._display == 856 and sheep.Model._creature == nil and sheep.Model._anim == 0 and not sheep.Ring:IsShown()
			and win.Foes.slots[1].key == "leader" and win.Foes.slots[1].Ring:IsShown() and not dot("Bandit mage").casting,
			"her Polymorph turned the mage into a sheep (standing, no more Frostbolts); her target the leader again")
	end
	Advance(2.5)
	check(bandit:GetAlpha() < 0.5, "... that fades")
	check(floatWith("an item, |cffffd14c1.3%|r") and floatWith("an item, |cffffd14c1.3%|r").anchor == win.Foes.Hero,
		"her loot from it: a rare find (the classic database's chance for a Defias Bandit), in gold")
	do -- The fight ends (the mage leaves the row), the loop starts over: in the next fight it's itself again.
		local wasSheep, mage = false
		for _, s in ipairs(win.Foes.slots) do
			if s:IsShown() and s.key == "mage" then wasSheep = s.Model._display == 856 end
		end
		Advance(10)
		for _, s in ipairs(win.Foes.slots) do
			if s:IsShown() and s.key == "mage" then mage = s end
		end
		check(wasSheep and mage and mage.Model._creature == 474 and mage.Model._display == nil,
			"still a sheep near the loop's end; once it starts over, the mage again")
	end

	win.Close:Click()
	check(not win:IsShown() and used() == 0, "the X closes it, its dots let go")

	-- "me": the mobs around me, as the game tells them.
	MOBS = {
		nameplate1 = { name = "Defias Thug", level = 15, combat = true, attacking = true, yards = 4, x = 0.5, y = 0.45 },
		nameplate2 = { name = "Defias Pillager", level = 16, class = "elite", combat = true, casting = "Fireball", yards = 25, x = 0.25, y = 0.6 },
		nameplate3 = { name = "Gnoll", level = 14, yards = 35 }, -- no nameplate frame: no direction
	}
	lefthy("stream me")
	Advance(0.6)
	local thug, pillager = dot("Defias Thug"), dot("Defias Pillager")
	gnoll = dot("Gnoll")
	check(win:IsShown() and win.Title:GetText():find("Lefthy", 1, true) and win.Live.Text:GetText() == "LIVE" and used() == 3
		and S.SenseRunning(), "/lefthy stream me: my own surroundings, live")
	check(win.Foes.Hero.Real:IsShown() and win.Foes.Hero.Real._unit == "player" and win.Foes.Hero.Real._nativeForm == false
		and not win.Foes.Hero.Emblem:IsShown(), "in the battle row: me, my own model (in the form I'm in, not my native one)")
	SHAPESHIFT_SPELL = 768
	Fire("UPDATE_SHAPESHIFT_FORM")
	Advance(1.1)
	check(win.Foes.Hero.Shifted:IsShown() and win.Foes.Hero.Shifted._unit == "player" and not win.Foes.Hero.Real:IsShown()
		and win.Foes.Hero.Shifted._camScale == 1, "in Cat Form: my model as I am now (a PlayerModel: it shows the form), the camera closer")
	SHAPESHIFT_SPELL = nil
	Fire("UPDATE_SHAPESHIFT_FORM")
	Advance(0.6)
	check(act.Name:GetText() == "" and not act.Icon:IsShown() and not act.Recent[1]:IsShown(), "not casting yet: the row is empty (the preview's spells are gone)")
	-- The map moves with me, my arrow turns with me.
	do
		local before = win.Map._points[#win.Map._points][4]
		local wasPos, wasFacing = PLAYER_POS[1], FACING
		PLAYER_POS[1], FACING = PLAYER_POS[1] + 0.01, 1 -- 10 yd east, turned
		Advance(0.05)
		local after = win.Map._points[#win.Map._points][4]
		check(math.abs((before - after) - 10 * px) < 0.01 and win.Me.rotation == 1,
			"10 yd east: the map slides 10 yd west under me; my arrow turns with my facing")
		PLAYER_POS[1], FACING = wasPos, wasFacing
		Advance(0.6)
		NO_MAP_ART = true
		lefthy("stream me")
		Advance(0.6)
		check(not win.Map:IsShown() and win.Plain:IsShown(), "a map without art (or an instance): the plain rings")
		NO_MAP_ART = nil
		lefthy("stream me")
		Advance(0.6)
	end
	-- What I'm doing: the spell I'm casting (right away, on its start), then in the row of the last ones.
	PLAYER_CAST = { name = "Wrath", icon = 136006, start = GetTime() * 1000, finish = (GetTime() + 1.5) * 1000, spellID = 5176 }
	Fire("UNIT_SPELLCAST_START", "player", "Cast-3", 5176)
	Advance(0.05)
	check(act.Name:GetText() == "Wrath" and act.Icon.path == 136006 and act.Bar.width < 10, "casting: the spell, at once, its bar just started")
	Advance(0.75)
	check(act.Bar.width > 45 and act.Bar.width < 60, "... and filling, got " .. act.Bar.width)
	PLAYER_CAST = nil
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", 2764)
	Fire("UNIT_SPELLCAST_STOP", "player", "Cast-3", 2764)
	Fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast-4", 116) -- (someone else's: not mine)
	Advance(0.05)
	check(act.Name:GetText() == "" and act.Recent[1]:IsShown() and act.Recent[1].path == 100000 + 2764 and not act.Recent[2]:IsShown(),
		"done: the row clears, the spell joins the last ones (only mine)")
	Advance(12.5)
	check(not act.Recent[1]:IsShown(), "after a while it fades away")
	local function radius(d) return math.sqrt(d.tx ^ 2 + d.ty ^ 2) end
	check(thug.ty > 0 and pillager.ty > 0 and gnoll.ty > 0, "mobs with a nameplate are on my screen: ahead")
	check(radius(thug) < 15 and radius(pillager) > 30 and radius(pillager) < 80 and radius(gnoll) > 100,
		"at their distance: close, further, beyond every check (on the rim)")
	check(gnoll.Body.alpha < 0.8 and win.Hint:IsShown() and win.Hint:GetText() == "Move and turn: faint dots find their place.",
		"faint while left or right isn't known yet, and the window says how it learns")
	check(win.Status:GetText():find("1 on you", 1, true) and win.Status:GetText():find("3 near", 1, true)
		and win.Status:GetText():find("Defias Pillager casts Fireball", 1, true), "the bottom line, got " .. tostring(win.Status:GetText()))
	gnoll._scripts.OnEnter(gnoll)
	check(TOOLTIP.title == "Gnoll (14)" and tooltipHas("direction still unsure: move and turn") and tooltipHas("more than 30 yd away"),
		"hover: what's known about it")
	gnoll._scripts.OnLeave(gnoll)
	pillager._scripts.OnEnter(pillager)
	check(tooltipHas("about 24 yd"), "a distance between two checks: in the middle")
	pillager._scripts.OnLeave(pillager)
	-- My group: placed exactly (the game gives their position); other players with a nameplate: learned like mobs.
	do
		local n0, w0 = UnitPosition("player")
		GROUP = "party"
		PARTY.party1 = { name = "Bobby", classFile = "WARRIOR", level = 18, guid = "Player-1-77", north = n0 + 12, west = w0, continent = 0,
			channel = "Mind Flay", channelID = 15407 }
		MOBS.nameplate5 = { name = "Cedric", level = 22, player = true, friendly = true, classFile = "PRIEST", yards = 20, x = 0.4, y = 0.5 }
		Advance(0.6)
		local bobby, cedric = dot("Bobby"), dot("Cedric")
		check(bobby and bobby.mob.group and bobby.mob.exact == 12 and bobby.mob.sure == 1 and math.abs(bobby.tx) < 0.5
			and math.abs(bobby.ty - 12 * px) < 0.5 and bobby.Name:GetText() == "Bobby" and bobby.Ring.color[3] == 1,
			"a party member 12 yd north: exactly there, named, a blue ring")
		check(bobby.mob.casting == "Mind Flay" and bobby.mob.castID == 15407 and bobby.Glow:IsShown(),
			"his channel (Mind Flay): casting, like a mob's")
		check(cedric and cedric.mob.player and cedric.mob.friendly and not cedric.mob.group and cedric.ty > 0,
			"another player with a friendly nameplate: on my screen, learned like a mob")
		check(win.Status:GetText():find("3 near", 1, true), "players aren't counted as enemies near")
		bobby._scripts.OnEnter(bobby)
		check(tooltipHas("In your group") and tooltipHas("12 yd away"), "hover: in my group, the exact distance")
		bobby._scripts.OnLeave(bobby)
		PARTY.party1, GROUP, MOBS.nameplate5 = nil, "none", nil
		Advance(8.6) -- (Cedric is remembered a while, then gone)
		check(not dot("Bobby") and not dot("Cedric"), "gone with them")
	end
	-- My target without a nameplate though near: I turned away from it, so it's behind me. Further
	-- than nameplates reach: no telling, so at first where I look.
	MOBS.target, STATE.target = { name = "Kodo", level = 26, yards = 15, guid = "Creature-0-kodo" }, true
	Advance(0.6)
	local kodo = dot("Kodo")
	check(kodo and kodo.ty < 0 and used() == 4 and kodo.Target:IsShown(), "my target near but without a nameplate: behind me, ringed")
	kodo._scripts.OnEnter(kodo)
	check(tooltipHas("your target"), "... and it says it's my target")
	kodo._scripts.OnLeave(kodo)
	MOBS.target = { name = "Far Kodo", level = 26, yards = 60, guid = "Creature-0-far" }
	Advance(0.6)
	local far = dot("Far Kodo")
	check(far and far.ty > 0 and radius(far) > 100, "a target beyond nameplate range: where I look, on the rim")
	far._scripts.OnEnter(far)
	check(tooltipHas("more than 30 yd away"), "... further than the range checks reach")
	far._scripts.OnLeave(far)
	MOBS.target, STATE.target = nil, false
	MOBS.nameplate1 = nil
	Advance(0.6)
	thug = dot("Defias Thug")
	check(thug and thug.mob.remembered and thug.Body.alpha < 1, "a mob gone from my screen: remembered a while, fading")
	thug._scripts.OnEnter(thug)
	check(tooltipHas("off your screen for 1 s") or tooltipHas("off your screen for 0 s"), "... and it says so")
	thug._scripts.OnLeave(thug)
	Advance(8)
	check(not dot("Defias Thug") and not dot("Kodo") and used() == 2, "after a while the ones not seen again are gone")
	-- The camera per form (what fit in game): a bear further back; Travel Form a Skyborne's bird
	-- further still, another race's cheetah as a cat.
	do
		local race, scales = UnitRace, {}
		for _, case in ipairs({ { 783, 95 }, { 5487 }, { 783 } }) do
			UnitRace = case[2] and function() return "Skyborne", "Skyborne", case[2] end or race
			SHAPESHIFT_SPELL = case[1]
			Fire("UPDATE_SHAPESHIFT_FORM")
			Advance(1.1)
			scales[#scales + 1] = win.Foes.Hero.Shifted._camScale
		end
		UnitRace, SHAPESHIFT_SPELL = race, nil
		Fire("UPDATE_SHAPESHIFT_FORM")
		Advance(0.6)
		check(scales[1] == 2 and scales[2] == 1.4 and scales[3] == 1 and win.Foes.Hero.Real:IsShown(),
			"the camera per form: a Skyborne's Travel Form (a bird) 2, a bear 1.4, a human's Travel Form (a cheetah) 1; "
			.. table.concat(scales, ", "))
	end

	-- Learning: two gnolls 20 yd ahead, one 30 degrees to the left, one to the right. Looking left and
	-- right tells which is which (nameplates come and go, the soft target is the one straight ahead).
	math.randomseed(7)
	MOBS, FACING = {}, 0
	local hereNorth, hereWest = UnitPosition("player")
	MOBS.nameplate1 = { name = "Left Gnoll", level = 14, guid = "Creature-0-left", north = hereNorth + 17.32, west = hereWest + 10 }
	MOBS.nameplate2 = { name = "Right Gnoll", level = 14, guid = "Creature-0-right", north = hereNorth + 17.32, west = hereWest - 10 }
	Advance(0.6)
	local left, right = dot("Left Gnoll"), dot("Right Gnoll")
	check(left and right and left.mob.sure < 0.5 and right.mob.sure < 0.5 and left.ty > 0 and right.ty > 0,
		"two mobs ahead: which is left and which right isn't known yet")
	FACING = math.rad(40)
	Advance(2)
	check(left.mob.soft and right.mob.remembered, "looking left: the left one straight ahead (the soft target), the right one off my screen")
	FACING = math.rad(-40)
	Advance(2)
	FACING = 0
	Advance(1)
	left, right = dot("Left Gnoll"), dot("Right Gnoll")
	check(left.tx < 0 and right.tx > 0 and left.mob.sure > 0.6 and right.mob.sure > 0.6,
		("looking left and right taught it: each on its side, and sure, got %.1f (%.2f), %.1f (%.2f)"):format(left.tx,
			left.mob.sure, right.tx, right.mob.sure))
	MOBS, FACING = {}, 0
	Advance(9)

	-- In combat the game keeps my target's nameplate at the screen's edge while it's behind me, so
	-- then its nameplate says nothing; my own casts do (a spell that went off: in front; "Target
	-- needs to be in front of you": behind).
	math.randomseed(11)
	local hn, hw = UnitPosition("player")
	MOBS.nameplate1 = { name = "Hyena", level = 26, guid = "Creature-0-hyena", north = hn - 15, west = hw, pinned = true,
		combat = true, attacking = true }
	MOBS.target, STATE.target, STATE.combat = MOBS.nameplate1, true, true
	Advance(0.6)
	local hyena = dot("Hyena")
	check(hyena and hyena.mob.target and hyena.mob.sure < 0.5, "my target behind me, its nameplate kept on screen in combat: not put in front")
	SPELL_FAILED_UNIT_NOT_INFRONT = "Target needs to be in front of you."
	Fire("UI_ERROR_MESSAGE", 50, SPELL_FAILED_UNIT_NOT_INFRONT)
	Advance(1)
	check(hyena.ty < 0, "\"Target needs to be in front of you\": behind me, got " .. hyena.ty)
	FACING = math.pi -- turned around to face it
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 2764)
	Advance(1)
	check(hyena.ty < 0 and math.abs(hyena.tx) < 40, "turned around to it, a spell cast at it: still south of me (north is up), now where I face, got " .. hyena.ty)
	-- Dead: a skull where I stand, my name greyed.
	STATE.dead = true
	Advance(0.6)
	check(win.MeSkull:IsShown() and not win.Me:IsShown() and win.Title:GetText():find("dead", 1, true), "dead: a skull in the middle")
	STATE.dead = false
	Advance(0.6)
	check(not win.MeSkull:IsShown() and win.Me:IsShown(), "alive again: my arrow")
	MOBS, FACING, STATE.target, STATE.combat = {}, 0, false, false
	Advance(9)
	MOBS = {
		nameplate2 = { name = "Defias Pillager", level = 16, class = "elite", combat = true, casting = "Fireball", yards = 25, x = 0.25, y = 0.6 },
		nameplate3 = { name = "Gnoll", level = 14, yards = 35 },
	}
	Advance(0.6)
	check(used() == 2, "two mobs again")
	-- My health: the game hides it, so it's added up from hits and heals (StreamSense.lua). Out of
	-- combat it comes back in ticks; when they stop for 4 s, I'm full.
	do
		local function near(a, b) return a and math.abs(a - b) < 0.001 end
		local function hit(kind, amount) Fire("UNIT_COMBAT", "player", kind, "", amount, 1) end
		S.LifeStart() -- (as after a /reload)
		Advance(1)
		check(S.Health() == nil and not win.Health:IsShown() and win.HealthBack:IsShown() and win.HealthText:GetText() == "~?",
			"after a /reload: not known yet, an empty bar, ~?")
		win.HealthHover._scripts.OnEnter(win.HealthHover)
		check(tooltipFind("Not known yet: it is after a few seconds out of combat at full health"), "hover: why, and when it will be")
		win.HealthHover._scripts.OnLeave(win.HealthHover)
		Fire("UNIT_HEALTH", "player")
		Advance(2)
		Fire("UNIT_HEALTH", "player")
		Advance(3)
		check(S.Health() == nil, "ticks coming back: not full yet, still not known")
		Advance(1.5)
		check(S.Health() == 1, "no tick for 4 s: full")
		Advance(0.6)
		check(win.Health:IsShown() and win.HealthText:GetText() == "~100%" and win.Health.width == 120,
			"the window: a green bar over the power bar, ~100%")
		win.HealthHover._scripts.OnEnter(win.HealthHover)
		check(TOOLTIP.title == "Health (estimated)" and tooltipFind("added up from hits and heals"), "hover: it's estimated, and how")
		win.HealthHover._scripts.OnLeave(win.HealthHover)
		hit("WOUND", 250)
		Advance(0.6)
		check(near(S.Health(), 0.75) and win.HealthText:GetText() == "~75%" and near(win.Health.width, 90), "hit for 250 of 1000: ~75%")
		hit("HEAL", 100)
		check(near(S.Health(), 0.85), "healed 100: 85%")
		hit("HEAL", 500)
		hit("MISS", 0)
		check(S.Health() == 1, "overhealed: full, not more (a miss changes nothing)")
		EnterCombat()
		hit("WOUND", 700)
		Advance(1)
		Fire("UNIT_HEALTH", "player") -- (in combat, without a hit or heal: why isn't known)
		Advance(5)
		check(near(S.Health(), 0.3), "in combat: hits count, nothing else, got " .. tostring(S.Health()))
		LeaveCombat()
		for _ = 1, 3 do
			Advance(2)
			Fire("UNIT_HEALTH", "player")
		end
		check(near(S.Health(), 0.39), "out of combat: each tick gives a guess, got " .. tostring(S.Health()))
		Advance(4.5)
		check(S.Health() == 1, "the ticks stopped: full")
		hit("WOUND", 500)
		Fire("UNIT_HEALTH", "player") -- (the same moment: that hit, not a tick)
		Advance(2)
		Fire("UNIT_HEALTH", "player")
		check(near(S.Health(), 0.5 + 0.7 / 3), "a tick now gives what they gave last time (70% in 3), got " .. tostring(S.Health()))
		Advance(1)
		Fire("UNIT_HEALTH", "player")
		hit("HEAL", 100) -- (after its health change, at the same moment: a heal, not a tick)
		check(near(S.Health(), 0.5 + 0.7 / 3 + 0.1), "a heal right after its health change: counted once, got " .. tostring(S.Health()))
		HEALTH_MAX = SECRET -- (where the game restricts it)
		Fire("UNIT_MAXHEALTH", "player")
		check(near(S.Health(), 0.5 + 0.7 / 3 + 0.1), "my maximum hidden: the last one known stays")
		HEALTH_MAX = 1200
		Fire("UNIT_MAXHEALTH", "player")
		check(near(S.Health(), 1 - (1 - 0.5 - 0.7 / 3 - 0.1) * 1000 / 1200), "more maximum (a buff): what I lack stays")
		HEALTH_MAX = 1000
		Fire("UNIT_MAXHEALTH", "player")
		-- A /reload where the maximum is hidden: the one from before (this character, this level).
		HEALTH_MAX = SECRET
		S.LifeStart()
		Advance(4.5)
		check(S.Health() == 1, "a /reload where my maximum is hidden: the one known from before")
		LefthyToolsDB.streamHealthMax["Player-1-0"][2] = 99 -- (as if from another level)
		S.LifeStart()
		Advance(0.6)
		check(S.Health() == nil and win.HealthText:GetText() == "~?", "... not from another level: not known")
		win.HealthHover._scripts.OnEnter(win.HealthHover)
		check(tooltipFind("the game hides the maximum health in this place"), "hover: the maximum is hidden here")
		win.HealthHover._scripts.OnLeave(win.HealthHover)
		Advance(4)
		HEALTH_MAX = 1000
		Fire("UNIT_MAXHEALTH", "player")
		check(S.Health() == 1 and LefthyToolsDB.streamHealthMax["Player-1-0"][2] ~= 99, "it answers again: known, and kept")
		STATE.dead = true
		Fire("PLAYER_DEAD")
		Advance(0.6)
		check(S.Health() == 0 and not win.Health:IsShown(), "dead: nothing (the skull says it)")
		Fire("PLAYER_ALIVE") -- (released: a ghost, still dead)
		check(S.Health() == 0, "a ghost: still nothing")
		STATE.dead = false
		Fire("PLAYER_UNGHOST")
		check(near(S.Health(), 0.5), "alive again: about half")
		Advance(5)
		check(S.Health() == 1, "no ticks after that: full")
	end
	-- What happens to me floats up over the radar: hits and heals (added up per look), a dodge, XP
	-- from the mob that died, loot; my kills count at the top right.
	do
		Fire("UNIT_COMBAT", "player", "WOUND", "", 52, 1)
		Fire("UNIT_COMBAT", "player", "WOUND", "", 30, 1)
		Fire("UNIT_COMBAT", "player", "HEAL", "", 300, 2)
		Fire("UNIT_COMBAT", "player", "DODGE", "", 0, 1)
		Advance(1.2) -- (played one after another: the hit, then the dodge)
		local hurt, heal, dodge = floatWith("-82"), floatWith("+300"), floatWith("Dodge")
		local hero = win.Foes.Hero
		check(hurt and heal and dodge and floating() == 3 and hurt.anchor == hero and heal.anchor == hero and dodge.anchor == hero
			and hurt.color[1] == 1 and heal.color[2] == 1, "hit twice, healed, dodged: -82 in red, +300 in green, Dodge, all from my model")
		check(heal.textScale > 1 and hurt.textScale == 1, "the heal is big (a sixth of my health): bigger")
		Advance(0.5)
		check(floating() > 0 and not twice(), "shown once, though still in the picture")
		Advance(1.5)
		check(floating() == 0, "gone after a moment")
		local pillager = dot("Defias Pillager")
		local xpWas = XP.current
		Fire("PARTY_KILL", "Player-1-0", "Creature-0-nameplate2")
		XP.current = XP.current + 120
		Fire("PLAYER_XP_UPDATE", "player")
		Advance(0.6)
		local xp = floatWith("+120 XP")
		check(xp and (xp.anchor == win.Foes.Hero or xp.anchor.mob and xp.anchor.mob.name == "Defias Pillager") and win.Kills:GetText() == "1 kill",
			"my killing blow: +120 XP floats up (from its model if it's in the row, else from mine), 1 kill at the top")
		local chronicled = LefthyToolsChronicleDB.chars["Lefthy-Realmy"].stats -- (Chronicle counts loot too: not this test's)
		local loot2 = chronicled.loot2
		Fire("CHAT_MSG_LOOT", LOOT_ITEM_SELF:format(ItemLink(2589))) -- (Linen Cloth: not green)
		Fire("CHAT_MSG_LOOT", LOOT_ITEM_SELF:format(ItemLink(2075)))
		chronicled.loot2 = loot2
		Advance(0.6)
		local loot = floatWith("Priest's Mace")
		check(loot and loot:GetText():find("|T3075:16:16|t", 1, true) and not floatWith("Linen Cloth"),
			"loot, green and better: its icon and name float up")
		XP.current = xpWas
		Advance(4)
	end
	-- A mob's cast is hidden by the game (all of it, on Forever), but not that it began or ended.
	do
		MOBS.nameplate4 = { name = "Kobold Geomancer", level = 12, combat = true, casting = SECRET, yards = 20, x = 0.6, y = 0.5 }
		Advance(0.6)
		local geo = dot("Kobold Geomancer")
		check(geo and not geo.casting and not geo.Glow:IsShown(), "its cast hidden: nothing to tell yet")
		Fire("UNIT_SPELLCAST_START", "nameplate4", "Cast-7", SECRET)
		Advance(0.6)
		check(geo.casting and geo.Glow:IsShown() and geo.mob.casting == "a spell", "it began casting: the purple glow, \"a spell\"")
		geo._scripts.OnEnter(geo)
		check(tooltipHas("casting a spell"), "hover: casting a spell")
		geo._scripts.OnLeave(geo)
		Fire("UNIT_SPELLCAST_STOP", "nameplate4", "Cast-7", SECRET)
		Advance(0.6)
		check(not geo.casting and not geo.Glow:IsShown(), "it stopped: no glow")
		Fire("UNIT_SPELLCAST_CHANNEL_START", "nameplate4", "Cast-8", SECRET)
		Advance(0.6)
		check(geo.casting, "a channel too")
		Advance(10)
		check(not geo.casting, "never seen to end: over after 10 s")
		MOBS.nameplate4 = nil
		Advance(9)
	end
	-- The foes under my spells: a still model each (its creature, from its GUID) with its health:
	-- the real one in my own window (the hidden values straight into the bar); for friends an
	-- estimate, its kind's maximum learned from a kill seen from full health.
	do
		local wolf = { name = "Young Wolf", level = 3, guid = "Creature-0-1-0-1-299-0000000A", yards = 6, x = 0.5, y = 0.5 }
		MOBS.nameplate5 = wolf
		Advance(0.6)
		check(not win.Foes.slots[1] or not win.Foes.slots[1]:IsShown(), "a mob not fought: not in the row")
		wolf.combat, wolf.attacking, MOBS.target, STATE.target = true, true, wolf, true
		Advance(0.6)
		local slot = win.Foes.slots[1]
		check(slot and slot:IsShown() and slot.Model._creature == 299 and slot.Model._zoom == 0 and slot.Model._facing == -0.45
			and slot.Ring:IsShown() and slot.real and slot.Bar._max == SECRET and slot.Bar._value == SECRET and not slot.Unknown:IsShown(),
			"fought: its whole model (creature 299, turned towards me), gold as my target, its real health (hidden, straight into the bar)")
		check(dot("Young Wolf").mob.health == 1, "not hit, not learned yet: a normal mob, taken as usual for its level (for friends)")
		local busy = { name = "Busy Wolf", level = 3, class = "elite", guid = "Creature-0-1-0-1-300-0000000D", combat = true, yards = 12,
			x = 0.45, y = 0.5 }
		MOBS.nameplate6 = busy
		Advance(0.6)
		check(not (win.Foes.slots[2] and win.Foes.slots[2]:IsShown()), "a mob in combat with someone else: not in the row")
		THREAT.nameplate6 = 1
		Advance(0.6)
		check(win.Foes.slots[2] and win.Foes.slots[2]:IsShown() and win.Foes.slots[2].mob.name == "Busy Wolf"
			and win.Foes.slots[1].mob.name == "Young Wolf", "I'm on its threat list: in the row, after my target")
		check(win.Foes.slots[2].mob.health == nil, "an elite not learned yet: its health not known (for friends)")
		-- With the classic database (the Bestiary's LefthyTools_DropData) it is: its health there.
		local dropData = LefthyToolsDropData
		LefthyToolsDropData = { source = "test", mobs = { [300] = "2589:1:5000;h=2-4:60-100" } }
		Fire("UNIT_COMBAT", "nameplate6", "WOUND", "", 20, 1)
		Advance(0.6)
		check(win.Foes.slots[2].mob.health and math.abs(win.Foes.slots[2].mob.health - 0.75) < 0.001,
			"an elite in the classic database: its health there (80 at level 3, between 60 at 2 and 100 at 4), 20 lost: ~75% (for friends)")
		LefthyToolsDropData = dropData
		MOBS.nameplate6, THREAT.nameplate6 = nil, nil
		Fire("UNIT_COMBAT", "nameplate5", "WOUND", "", 60, 1)
		Fire("UNIT_COMBAT", "target", "WOUND", "", 60, 1) -- (the same hit, for my target)
		Advance(0.3)
		Fire("UNIT_COMBAT", "nameplate5", "WOUND", "", 40, 1)
		wolf.dead = true
		Advance(0.6)
		local learned = LefthyToolsDB.streamMobHealth[299]
		check(learned and math.abs(learned[1] - 100 / 71) < 0.001 and learned[2] == 1,
			"it died, seen from full: 100 (the hit counted once), its kind's ratio to a usual level 3 mob (71) learned")
		wolf = { name = "Young Wolf", level = 3, guid = "Creature-0-1-0-1-299-0000000B", yards = 6, x = 0.5, y = 0.5 }
		MOBS.nameplate5, MOBS.target = wolf, wolf
		Advance(0.6)
		wolf.combat, wolf.attacking = true, true
		Fire("UNIT_COMBAT", "nameplate5", "WOUND", "", 25, 1)
		Advance(0.6)
		check(math.abs(dot("Young Wolf").mob.health - 0.75) < 0.001, "another of its kind: 25 of 100 lost, ~75% (for friends' windows)")
		wolf.level = 5
		Advance(0.6)
		check(math.abs(dot("Young Wolf").mob.health - (1 - 25 / (100 / 71 * 102))) < 0.001,
			"the same kind at another level: its ratio times a usual level 5 mob (102)")
		for _, s in ipairs(win.Foes.slots) do -- (the first wolf still falls in its place: the new one's box)
			if s:IsShown() and s.key == "Creature-0-1-0-1-299-0000000B" then slot = s end
		end
		slot._scripts.OnEnter(slot)
		check(TOOLTIP.title == "Young Wolf (5)" and not tooltipFind("health"), "hover: who (its health is the real bar)")
		slot._scripts.OnLeave(slot)
		MOBS.nameplate5, MOBS.target, STATE.target = nil, nil, false
		Advance(9)
		check(not slot:IsShown(), "gone: the row empties")
	end
	-- A kind's health: a ratio learned from 2 kills or more first (measured on Forever), then the
	-- classic database, then a ratio from 1 kill, then usual for its level (a normal mob); else not known.
	do
		local dropData, learned, bestiary = LefthyToolsDropData, LefthyToolsDB.streamMobHealth, ns.Bestiary
		LefthyToolsDropData = { source = "test", mobs = { [9101] = ";h=10-20:300-800", [9102] = ";h=10-20:300-800",
			[9103] = "2589:1:5000;g=8-15" } }
		learned[9101], learned[9102], learned[9104] = { 1.5, 2 }, { 1.5, 1 }, { 1.5, 1 }
		local max, from = S.MobMaxOf(9101, 15, "elite")
		check(math.abs(max - 1.5 * 385) < 0.001 and from == "learned", "learned from 2 kills: its ratio, before the database")
		max, from = S.MobMaxOf(9102, 15, "elite")
		check(max == 550 and from == "database", "learned from 1 kill: the database first (550 at level 15, between 300 at 10 and 800 at 20)")
		max, from = S.MobMaxOf(9103, 15)
		check(max == 385 and from == "usual", "in the database without its health, a normal mob: usual for its level")
		max, from = S.MobMaxOf(9104, 15, "elite")
		check(math.abs(max - 1.5 * 385) < 0.001 and from == "learned", "not in the database, 1 kill: its ratio")
		check(S.MobMaxOf(9105, 15, "rare") == nil, "a rare nobody knows: not known")
		max = S.MobMaxOf(9102, 22, "elite")
		check(math.abs(max - 800 / 629 * 731) < 0.001, "a level the database doesn't have: its nearest (20) scaled like a usual mob")
		check(S.MobMaxOf(9102, -1, "worldboss") == 800, "a boss's \"??\": its highest level's")
		-- No database: the Bestiary switched off, its database off, or not there at all.
		bestiary.module.enabled = false
		check(select(2, S.MobMaxOf(9102, 15, "elite")) == "learned", "the Bestiary switched off: as before")
		bestiary.module.enabled = true
		LefthyToolsDB.settings.bestiary.dropData = false
		check(select(2, S.MobMaxOf(9102, 15, "elite")) == "learned", "its database switched off: as before")
		LefthyToolsDB.settings.bestiary.dropData = true
		ns.Bestiary = nil
		check(select(2, S.MobMaxOf(9102, 15, "elite")) == "learned" and select(2, S.MobMaxOf(9103, 15)) == "usual",
			"no Bestiary at all: as before")
		ns.Bestiary = bestiary
		learned[9101], learned[9102], learned[9104] = nil, nil, nil
		LefthyToolsDropData = dropData
	end
	win.Close:Click()
	check(not win:IsShown() and not S.SenseRunning(), "closed: the sensor stops")

	-- The test: what answers, in and out of combat.
	MOBS.nameplate1 = { name = "Defias Thug", level = 15, combat = true, attacking = true, yards = 4, x = 0.5, y = 0.45 }
	MOBS.nameplate2.plateError = "can't measure this region" -- (like the first test on Forever)
	pmark = #PRINTED + 1
	lefthy("stream test")
	check(printedSince(pmark):find("fight stream test: 60 s of notes", 1, true), "/lefthy stream test: it starts and says what to do")
	STATE.combat = true
	Advance(30)
	Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 2764) -- (no target: doesn't tell where it is)
	Fire("UI_ERROR_MESSAGE", 50, SPELL_FAILED_UNIT_NOT_INFRONT)
	STATE.combat = false
	pmark = #PRINTED + 1
	Advance(30.5)
	local tests = LefthyToolsDB.streamTests
	local report = tests and tests[1] and tests[1].text or ""
	check(#tests == 1 and printedSince(pmark):find("fight stream test done", 1, true), "after a minute: done, kept, and I'm told")
	local function has(text) return report:find(text, 1, true) ~= nil end
	check(has("Fight stream test: LefthyTools ") and has("(open world)") and has("up to 3 nameplates at once")
		and has("Settings: enemy nameplates 1, nameplate distance 41, camera field of view 90"), "the report: where, when, the settings")
	check(has("UnitName: value 180 | value 180") and has("e.g. Defias Thug; Defias Pillager") and has("UnitHealth: hidden 180 | hidden 180")
		and has("UnitGUID: value 180 | value 180\n") and has("UnitPosition(player): value 60 | value 60\n"),
		"what answers and what's hidden, in and out of combat, with examples (none of GUIDs and my position)")
	check(has("spell Throw (30 yd): true 120, false 60 | true 120, false 60") and has("item 835 (30 yd): nil 180 | true 120, false 60")
		and has("CheckInteractDistance 3 (10 yd): error 180 |") and has("e.g. CheckInteractDistance: blocked in combat"),
		"each range check, in and out of combat, with what the errors say")
	check(has("nameplate position: GetCenter: nil 60, onscreen 60, error 60 |") and has("e.g. 0.50,0.45; can't measure this region"),
		"nameplate positions, with what the errors say")
	check(has("soft target: UnitExists(softenemy): false 60 | false 60") and has("is the soft target: UnitIsUnit(<unit>, softenemy): false 180 | false 180")
		and has("Soft targeting: enemy "), "the soft target and its settings, got\n" .. report)
	check(has("your casts: UNIT_SPELLCAST_SUCCEEDED (true: harmful, at a hostile target): false 1 |")
		and has("the game's error messages: UI_ERROR_MESSAGE (true: not in front): true 1 | -   e.g. Target needs to be in front of you."),
		"my casts and the game's error messages, with their words, got\n" .. report)
	check(has("Distance: 2 of 10 range checks answered in combat, 5 only out of combat."), "a short summary, got\n" .. report)
	lefthy("stream results")
	check(LefthyToolsStreamTestsFrame and LefthyToolsStreamTestsFrame:IsShown(), "/lefthy stream results: ready to copy")
	LefthyToolsStreamTestsFrame:Hide()


	pmark = #PRINTED + 1
	lefthy("stream test")
	Advance(2)
	lefthy("stream test")
	check(#tests == 2 and printedSince(pmark):find("fight stream test stopped", 1, true), "again while it runs: stopped early, kept")
	for _ = 1, 2 do
		lefthy("stream test")
		Advance(1)
		lefthy("stream test")
	end
	check(#tests == 3, "the last three are kept")
	MOBS = {}

	-- Between friends. Anna's LefthyTools says she can be watched; Bob's doesn't (older).
	local function bob(text) Fire("BN_CHAT_MSG_ADDON", "LTBeacon", text, "WHISPER", 12) end
	anna("S2;;0;260.0;750.0;Goldshire;")
	bob("S2;;0;260.0;750.0;Goldshire;")
	Advance(6)
	mark = #GAMEDATA + 1
	anna("H2")
	Advance(1)
	check(sentTo(11, mark, "O2;h;1")[1], "my answers tell friends they can watch my fights")
	anna("O2;h;1")
	pmark = #PRINTED + 1
	lefthy("stream watch bob")
	check(printedSince(pmark):find("Bob Stone can't be watched", 1, true) and not S.IsWatching(12), "Bob's LefthyTools is older: he can't be watched, and I'm told why")
	lefthy("stream watch nobody")
	check(printedSince(pmark):find("no friend called nobody", 1, true), "an unknown name: said so")
	mark = #GAMEDATA + 1
	lefthy("stream watch anna")
	Advance(0.6)
	local fwin = LefthyToolsStreamFriend1
	check(fwin and fwin:IsShown() and S.IsWatching(11) and sentTo(11, mark, "O2;w;1")[1],
		"/lefthy stream watch anna: her window opens, and she's told I watch")
	check(fwin._strata == "FULLSCREEN_DIALOG" and math.abs(fwin._scale - 0.55) < 0.001 and fwin._points[1][1] == "TOPLEFT"
		and fwin._points[1][4] < 40, "small, at the top left, above everything (also a flight's film)")
	check(fwin.Status:GetText() == "Waiting for Anna Brook's stream...", "nothing from her yet: waiting")
	-- Her frames: mob names first (once), then what's around her twice a second.
	anna("O2;n;1;16;Defias Pillager")
	anna("O2;f;0;1429;260;750;90;c;M40;;133,10,25;116,3/122,6;1,45,20,9,actes,133/2,180,30,4,cb")
	Advance(0.6)
	local fpill, other = dot("Defias Pillager", 11), dot("?", 11)
	check(fwin.Title:GetText():find("Anna", 1, true) and used(11) == 2 and fpill and other and fwin.Map:IsShown(),
		"her fight on her map: two mobs, one not named yet")
	check(fpill.tx > 0 and fpill.ty > 0 and math.abs(radius(fpill) - 20 * px) < 0.5 and fpill.Ring:IsShown()
		and fpill.Target:IsShown() and fpill.casting, "north-east of her at 20 yd: elite, her target, casting")
	check(other.ty < 0 and math.abs(radius(other) - 40 * px) < 0.5 and other.Body.alpha < 0.8,
		"south, beyond the range checks: on the rim, faint (unsure)")
	check(fwin.Act.Name:GetText() == "Spell 133" and fwin.Act.Recent[1].path == 100116 and fwin.Act.Recent[2].path == 100122
		and fwin.Power:IsShown() and math.abs(fwin.Me.rotation - math.pi / 2) < 0.01,
		"what she's doing: her cast, her last spells (newest first), her mana; her arrow turned")
	check(fwin.Status:GetText():find("1 on Anna", 1, true) and fwin.Status:GetText():find("Defias Pillager casts Spell 133", 1, true),
		"the bottom line, got " .. tostring(fwin.Status:GetText()))
	do
		local annaVersion = BB.peers[11].version
		BB.peers[11].version = "0.5.0-113-g4661d7b"
		Advance(0.1)
		check(not fwin.Health:IsShown() and fwin.HealthText:GetText() == "~?", "no health in her frame: ~?")
		fwin.HealthHover._scripts.OnEnter(fwin.HealthHover)
		check(tooltipFind("Anna Brook's LefthyTools is older and doesn't send health"), "hover: her build is older (it sends none)")
		fwin.HealthHover._scripts.OnLeave(fwin.HealthHover)
		BB.peers[11].version = annaVersion
	end
	anna("O2;f;0;1429;260;750;90;c;M40;;133,10,25;116,3/122,6;v,?m/1,45,20,9,actes,133/2,180,30,4,cb")
	Advance(0.6)
	fwin.HealthHover._scripts.OnEnter(fwin.HealthHover)
	check(fwin.HealthText:GetText() == "~?" and tooltipFind("the game hides the maximum health in this place") and used(11) == 2,
		"her health not known, and why (her maximum is hidden there)")
	fwin.HealthHover._scripts.OnLeave(fwin.HealthHover)
	anna("O2;f;0;1429;260;750;90;c;M40;;133,10,25;116,3/122,6;v63/1,45,20,9,actes,133/2,180,30,4,cb")
	Advance(0.6)
	check(fwin.Health:IsShown() and fwin.HealthText:GetText() == "~65%" and math.abs(fwin.Health.width - 0.63 * 120) < 0.01
		and used(11) == 2, "her health first among the mobs: ~65% (steps of 5), the mobs as before")
	-- What happens to her, after her health: hits and heals (big in capitals), a miss, XP from mob 1,
	-- her killing blow on it, loot.
	local herFrame = "O2;f;0;1429;260;750;90;c;M40;;133,10,25;116,3/122,6;v63,5w52,6H300,7am,8x120.1,9k1,10l2075.2/1,45,20,9,actes,133/2,180,30,4,cb"
	anna(herFrame)
	Advance(0.6)
	anna(herFrame) -- (the next frame still carries them)
	Advance(0.6) -- (played one after another: the hit, then the miss)
	local herXP = floatWith("+120 XP", fwin)
	check(floatWith("-52", fwin) and floatWith("+300", fwin).textScale > 1 and floatWith("Miss", fwin) and herXP
		and (herXP.anchor == fwin.Foes.Hero or herXP.anchor.mob and herXP.anchor.mob.name == "Defias Pillager") and floatWith("Priest's Mace", fwin)
		and fwin.Kills:GetText() == "1 kill" and used(11) == 2, "her hits, heals, a miss, XP from the mob it came from, loot, her kill: all float up")
	check(not twice(fwin) and fwin.Kills:GetText() == "1 kill", "each once, though they came again")

	fpill._scripts.OnEnter(fpill)
	check(TOOLTIP.title == "Defias Pillager (16)" and tooltipHas("attacking Anna Brook") and tooltipHas("Anna Brook's target")
		and tooltipHas("about 20 yd") and not tooltipHas("direction still unsure"), "hover: about her mob")
	fpill._scripts.OnLeave(fpill)
	mark = #GAMEDATA + 1
	Advance(6)
	check(#sentTo(11, mark, "O2;w;1") == 1, "every 5 s: still watching")
	check(fwin.Status:GetText() == "Waiting for Anna Brook's stream...", "no frames for a while: waiting again")
	mark = #GAMEDATA + 1
	bob("O2;f;0;1429;260;750;0;;;;;;")
	bob("O2;f;0;1429;260;750;0;;;;;;")
	Advance(0.3)
	check(#sentTo(12, mark, "O2;w;0") == 1, "frames from someone I don't watch (after my /reload, say): told once to stop")
	-- Her model: her character isn't on my client: her class's emblem; in my group and near (her
	-- character loaded here): her own model, also in Cat Form; away again: the emblem (in a form too).
	check(fwin.Foes.Hero.Emblem:IsShown() and fwin.Foes.Hero.Away:IsShown() and not fwin.Foes.Hero.Real:IsShown()
		and not fwin.Foes.Hero.Face:IsShown() and fwin.Foes.Hero.Emblem.width == 38, "out of reach: her class's emblem")
	PARTY.party1 = { name = "Anna", guid = "Player-1-11", visible = false }
	Advance(0.6)
	check(fwin.Foes.Hero.Emblem:IsShown() and fwin.Foes.Hero.Face:IsShown() and fwin.Foes.Hero.Face.portrait == "party1"
		and fwin.Foes.Hero.Away:IsShown() and not fwin.Foes.Hero.Real:IsShown(),
		"in my group but far away: her portrait (the party frame's) on her class's emblem")
	PARTY.party1 = { name = "Anna", guid = "Player-1-11", visible = true }
	Advance(0.6)
	check(fwin.Foes.Hero.Real:IsShown() and fwin.Foes.Hero.Real._unit == "party1" and not fwin.Foes.Hero.Emblem:IsShown()
		and not fwin.Foes.Hero.Face:IsShown(), "in my group and near: her own model")
	anna((herFrame:gsub(";M40;;", ";M40;768;"))) -- (in Cat Form)
	Advance(1.1) -- (loaded, then its camera set on the next picture)
	check(fwin.Foes.Hero.Shifted:IsShown() and fwin.Foes.Hero.Shifted._unit == "party1" and not fwin.Foes.Hero.Real:IsShown()
		and fwin.Foes.Hero.Shifted._camScale == 1 and not fwin.Foes.Hero.Away:IsShown(),
		"near and in Cat Form: her own model as she is (a PlayerModel shows the form), the camera as for a cat")
	PARTY.party1 = nil
	Advance(0.6)
	check(fwin.Foes.Hero.Emblem:IsShown() and not fwin.Foes.Hero.Shifted:IsShown(), "away again, in Cat Form too: the emblem")
	anna("O2;a;1;2;1001,0,0,1002") -- (a look, as dev builds sent it: ignored)
	anna(herFrame) -- (out of the form)
	Advance(0.6)
	check(fwin.Foes.Hero.Emblem:IsShown() and fwin.Foes.Hero.Away:IsShown(), "a look from a dev build: ignored, the emblem")
	-- The ones she fights: their models (creature IDs come with the names) and health (estimated
	-- on her side; one she hasn't learned yet: "?").
	anna("O2;n;3;12;Kobold Miner")
	anna("O2;c;3;40")
	anna("O2;n;4;11;Kobold Vermin")
	anna("O2;c;4;6")
	MODEL_UNKNOWN[40] = 2 -- (a creature my client hasn't met: no model the first two times)
	anna("O2;f;0;1429;260;750;90;c;M40;;;;v80,3=45/4,90,8,9,ac/3,30,6,9,act")
	Advance(0.6)
	do
		local first, second = fwin.Foes.slots[1], fwin.Foes.slots[2]
		check(first.Initials:IsShown() and first.Initials:GetText() == "KM" and first.Stand:IsShown() and not second.Initials:IsShown(),
			"a creature my client hasn't met: no model yet, its initials meanwhile (the other one's model is there)")
		Advance(3)
		check(not first.Initials:IsShown() and not first.Stand:IsShown() and first.Model._loads == 3,
			"asked again every second: the model came")
		check(first:IsShown() and first.Model._creature == 40 and first.Ring:IsShown() and first.Bar._value == 0.45
			and second:IsShown() and second.Model._creature == 6 and second.Unknown:IsShown() and not first.Unknown:IsShown(),
			"her foes: her target first (a Kobold Miner at ~45%), then a Kobold Vermin (its health not known)")
		first._scripts.OnEnter(first)
		check(TOOLTIP.title == "Kobold Miner (12)" and tooltipFind("~45% health") and tooltipFind("against its kind's health: usual for its level."),
			"hover: who, ~45%, estimated against what its level usually has")
		first._scripts.OnLeave(first)
		second._scripts.OnEnter(second)
		check(tooltipFind("Health not known yet"), "hover the other: not known yet, and how it will be")
		second._scripts.OnLeave(second)
		-- Her target loses health: her swing (she steps up), it flinches, roughly what it lost floats
		-- up from it (15% of a usual level 12 mob, 272: 41).
		anna("O2;f;0;1429;260;750;90;c;M40;;;;v80,3=30/4,90,8,9,ac/3,30,6,9,act")
		Advance(0.15)
		local b = S.View(11).battle
		check(b.action and b.action.kind == "strike" and b.action.key == first.key and fwin.Foes.Hero.dx > 0,
			"her target lost health: her swing, she steps up")
		Advance(0.3)
		check(floatWith("-41", fwin) and floatWith("-41", fwin).anchor == first and first.Model._anims[9], "it flinches, -41 floats up from it")
		-- Her killing blow: it falls at once, and keeps its place while it fades, though gone from her frames.
		anna("O2;f;0;1429;260;750;90;c;M40;;;;v80,31k3/4,90,8,9,ac")
		Advance(0.6)
		check(first:IsShown() and first.key == b.foe[first.key].ghost.key and first.mob.dead and first.Model._anims[1]
			and first.Bar._value == 0, "her killing blow: it falls at once (its box stays, though it's gone from her frames)")
		Advance(3)
		check(not (first:IsShown() and first.mob and first.mob.name == "Kobold Miner"), "fallen and faded: its box goes")
		-- Skinning (a cast): she kneels; nothing is cast at anyone when it's done.
		anna("O2;f;0;1429;260;750;90;;M40;;8613,5,30;;v80")
		Advance(0.6)
		check(b.cast and b.cast.gather, "skinning: a kneel (the loot animation), not a cast")
		anna("O2;f;0;1429;260;750;90;;M40;;;;v80")
		Advance(0.6)
		check(not (b.action and b.action.kind == "release") and #b.queue == 0, "done: no cast at anyone")
		-- Her Fireball goes off at her target: its icon flies over glowing in fire's orange, and the
		-- hit flashes in it; a physical spell (Sinister Strike): no glow, the red flash of a blow.
		do
			local row = fwin.Foes
			anna("O2;f;0;1429;260;750;90;c;M40;;133,20,25;;v80,4=90/4,90,8,9,act")
			Advance(0.6)
			anna("O2;f;0;1429;260;750;90;c;M40;;;133,0;v80,4=90/4,90,8,9,act")
			Advance(0.2)
			local glow = row.ShotGlow
			check(b.action and b.action.kind == "spell" and b.action.school == "fire" and row.Shot:IsShown() and row.Shot.path == 100133
				and glow:IsShown() and glow.vertex[1] == 1 and glow.vertex[2] == 0.5 and glow.blend == "ADD" and glow.points[1][2] == row.Shot,
				"her Fireball flies over, glowing orange behind its icon")
			Advance(0.4)
			local slot = row.slots[1]
			check(slot.mob.name == "Kobold Vermin" and slot.Flash.color[2] == 0.5 and slot.Model._anims[9], "it lands: the Kobold Vermin flinches, an orange flash")
			Advance(0.4)
			check(not row.Shot:IsShown() and not glow:IsShown(), "the icon and its glow fade away")
			anna("O2;f;0;1429;260;750;90;c;M40;;;1752,0/133,2;v80,4=90/4,90,8,9,act")
			Advance(0.4)
			check(row.Shot:IsShown() and row.Shot.path == 101752 and not glow:IsShown() and slot.Flash.color[2] == 0.15,
				"Sinister Strike (physical): its icon pops on it without a glow, the flash red")
			Advance(0.6)
		end
		-- Her Polymorph (known from her own spells: a mob's debuffs aren't read): the mob it went off at
		-- is a sheep until it takes damage, dies, the spell's time runs out or it leaves the row.
		do
			local row, slot = fwin.Foes, fwin.Foes.slots[1]
			local function frame(recent, rest) -- (her frame: no cast, these last spells, then vitals and mobs)
				return "O2;f;0;1429;260;750;90;c;M40;;;" .. recent .. ";" .. rest
			end
			anna("O2;f;0;1429;260;750;90;c;M40;;118,10,15;;v80,4=80/4,90,8,9,act")
			Advance(0.6)
			anna(frame("118,0", "v80,4=80/4,90,8,9,act"))
			Advance(0.2)
			check(b.action and b.action.kind == "spell" and b.action.poly and row.ShotGlow:IsShown() and row.ShotGlow.vertex[2] == 0.4,
				"her Polymorph flies over, glowing arcane pink-violet")
			Advance(0.4)
			local st = b.foe[slot.key]
			check(slot.mob.name == "Kobold Vermin" and slot.Model._display == 856 and slot.Model._creature == nil and st.sheep == 856
				and math.abs(st.sheepUntil - GetTime() - 19.4) < 0.2, "it lands: the Kobold Vermin is a sheep (rank 1: for 20 s)")
			anna(frame("118,1", "v80,4=80/4,90,8,9,c"))
			Advance(0.6)
			check(slot:IsShown() and slot.key == st.last.key and slot.Model._display == 856 and slot.Model._anim == 0,
				"off her target and merely in combat: the sheep keeps its place, standing")
			anna(frame("118,2", "v80,4=70/4,90,8,9,act"))
			Advance(0.6)
			check(slot.Model._creature == 6 and slot.Model._display == nil and not st.sheep, "it takes damage: itself again")
			anna(frame("12826,0/118,3", "v80,4=70/4,90,8,9,act"))
			Advance(0.6)
			check(slot.Model._display == 856 and math.abs(st.sheepUntil - GetTime() - 49.4) < 0.2,
				"rank 4, its cast not seen (only in her last spells): a sheep for 50 s")
			st.sheepUntil = GetTime() -- (as if its time were over)
			Advance(0.6)
			check(slot.Model._creature == 6 and not st.sheep, "its time runs out: itself again")
			anna(frame("28272,0/12826,1", "v80,4=70/4,90,8,9,act"))
			Advance(0.6)
			check(slot.Model._display == 16358 and st.sheep, "Polymorph: Pig: a pig")
			anna(frame("28272,1", "v80"))
			Advance(0.6)
			check(not slot:IsShown() and not st.sheep, "gone from her frames, out of the row: no pig any more")
			anna(frame("118,0", "v80,4=70/4,90,8,9,ac"))
			Advance(0.6)
			check(slot:IsShown() and slot.Model._creature == 6 and not st.sheep,
				"back, but her Polymorph went off at someone not in the row: no sheep guessed")
			anna(frame("12825,0/118,1", "v80,4=70/4,90,8,9,act"))
			Advance(0.6)
			check(slot.Model._display == 856, "her target again, rank 3: a sheep")
			anna(frame("12825,1", "v80,41k4"))
			Advance(0.6)
			check(slot:IsShown() and slot.Model._creature == 6 and slot.Model._display == nil and slot.Model._anims[1] and not st.sheep,
				"her killing blow: it falls as itself")
		end
	end
	-- An elite she fights, in the classic database (my client knows no other health for it): the hover
	-- says where its kind's health comes from, and what it lost floats up as a number, not a percent.
	do
		local dropData = LefthyToolsDropData
		LefthyToolsDropData = { source = "test", mobs = { [9201] = ";h=17-18:1180-1260" } }
		anna("O2;n;26;18;Riverpaw Brute")
		anna("O2;c;26;9201")
		anna("O2;f;0;1429;260;750;90;c;M40;;;;v80,26=50/26,90,8,9,acte")
		Advance(0.6)
		local brute -- (its own box: one that died before may still be falling in the first)
		for _, s in ipairs(fwin.Foes.slots) do
			if s:IsShown() and s.key == 26 then brute = s end
		end
		brute._scripts.OnEnter(brute)
		check(brute.mob.name == "Riverpaw Brute" and brute.mob.class == "elite" and tooltipFind("~50% health")
			and tooltipFind("against its kind's health: the classic database."), "hover an elite she fights: ~50%, its kind's health from the classic database")
		brute._scripts.OnLeave(brute)
		anna("O2;f;0;1429;260;750;90;c;M40;;;;v80,26=40/26,90,8,9,acte")
		Advance(0.15)
		Advance(0.3)
		check(floatWith("-126", fwin) and floatWith("-126", fwin).anchor == brute, "it loses 10%: -126 floats up from it (of 1260, its health at level 18 there)")
		LefthyToolsDropData = dropData
		anna("O2;f;0;1429;260;750;90;;M40;;;;v80")
		Advance(0.6)
	end

	-- Anna watches me: the sensor runs, a small red dot with 1 right of the calendar button, frames
	-- go to her (only her), each mob's name once.
	MOBS = {
		nameplate1 = { name = "Defias Thug", level = 15, combat = true, attacking = true, yards = 4, x = 0.5, y = 0.45 },
		nameplate2 = { name = "Defias Pillager", level = 16, class = "elite", combat = true, casting = "Fireball", castID = 133, yards = 25,
			x = 0.25, y = 0.6, guid = "Creature-0-1-0-1-589-0000000C" },
	}
	LefthyToolsDB.streamMobHealth["589:16"] = { 800, 2 } -- (its kind learned before)
	THREAT.nameplate2 = 1 -- (the pillager fights me: I'm on its threat list)
	mark = #GAMEDATA + 1
	anna("O2;w;1")
	Advance(0.1)
	local watched = LefthyToolsStreamWatched
	check(S.SenseRunning() and watched and watched:IsShown() and watched.Count:GetText() == "1", "Anna watches me: a small red dot and 1")
	watched._scripts.OnEnter(watched)
	check(TOOLTIP.title == "Watching your fights" and tooltipFind("Anna"), "hover: who")
	watched._scripts.OnLeave(watched)
	Fire("UNIT_COMBAT", "player", "WOUND", "", 40, 1)
	Advance(1.1)
	local frames, names = sentTo(11, mark, "O2;f;"), sentTo(11, mark, "O2;n;")
	check(#frames >= 2 and #names == 2 and #sentTo(12, mark, "O2;f;") == 0 and #sentTo(12, mark, "O2;n;") == 0,
		"frames go to her twice a second, each mob's name once, nothing to Bob, got " .. #frames .. " frames, " .. #names .. " names")
	check((names[1] .. names[2]):find(";15;Defias Thug", 1, true), "a name with its level")
	local fields = {}
	for f in (frames[#frames]:sub(6) .. ";"):gmatch("([^;]*);") do fields[#fields + 1] = f end
	check(#fields == 11 and fields[1] == "0" and #frames[#frames] <= 250 and fields[11]:find(",133$"),
		"a frame: where I am, how I face, and the mobs (the caster with its spell), got " .. frames[#frames])
	local vitals = fields[11]:match("^(v[^/]*)/")
	check(vitals and vitals:find("^v%d+,1=100,2=100,%d+w40$") and not vitals:match("^(%d+),(%d+),(%d*),(%d),(%l*),?(%d*)$"),
		"my health, my foes' (the thug: as usual for its level, the pillager: its kind learned; neither hit), the hit I took, first "
		.. "among the mobs, which older builds skip, got " .. fields[11])
	check(#sentTo(11, mark, "O2;c;") == 1 and sentTo(11, mark, "O2;c;")[1]:find(";589$"), "the pillager's creature (for its model), once")

	check(LefthyToolsDB.streamMobHealth["589:16"] == nil and math.abs(LefthyToolsDB.streamMobHealth[589][1] - 800 / 427) < 0.001
		and LefthyToolsDB.streamMobHealth[589][2] == 2, "learned the old way (a maximum per level): now its ratio, kills kept")
	-- What I send is what she sees: my frames, fed back as hers.
	for _, m in ipairs(names) do anna(m) end
	for _, m in ipairs(sentTo(11, mark, "O2;c;")) do anna(m) end

	anna(frames[#frames])
	Advance(0.6)
	check(fwin.Foes.Hero.Emblem:IsShown(), "what she sees of me (her client doesn't have my character): the class's emblem")
	local back = dot("Defias Pillager", 11)
	check(dot("Defias Thug", 11) and back and back.mob.casting == "Spell 133" and back.mob.level == 16 and back.Ring:IsShown()
		and fwin.HealthText:GetText() == ("~%d%%"):format(math.floor(tonumber(vitals:match("^v(%d+)")) / 5 + 0.5) * 5)
		and floatWith("-40", fwin) and back.mob.creature == 589 and back.mob.health == 1 and back.mob.engaged,
		"what I send is what she sees: my mobs, named, the spell named in her client's language, my health, my hit, my foe")
	THREAT.nameplate2 = nil
	anna("O2;w;1")
	MOBS = {}
	Advance(9) -- (the remembered ones fade first)
	anna("O2;w;1")
	mark = #GAMEDATA + 1
	Advance(4.1)
	local quiet = #sentTo(11, mark, "O2;f;")
	check(quiet >= 3 and quiet <= 5, "nothing going on: a frame every second (where I am), got " .. quiet)
	Advance(13)
	check(not watched:IsShown() and not S.SenseRunning(), "no word from her for 12 s: gone; the dot goes, the sensor stops")
	anna("O2;w;1")
	Advance(0.6)
	check(watched:IsShown() and S.SenseRunning(), "she's back")
	B("streamWatchedDot"):SetValue(false)
	check(not watched:IsShown() and S.SenseRunning(), "the dot switched off: hidden (she still watches)")
	B("streamWatchedDot"):SetValue(true)
	check(watched:IsShown(), "on again")
	anna("O2;w;0")
	Advance(0.1)
	check(not watched:IsShown() and not S.SenseRunning(), "she stopped: at once")
	mark = #GAMEDATA + 1
	B("streamShare"):SetValue(false)
	Advance(0.5)
	check(sentTo(11, mark, "O2;h;0")[1] and sentTo(12, mark, "O2;h;0")[1], "not sharing any more: every friend is told")
	anna("O2;w;1")
	Advance(0.6)
	check(not S.SenseRunning() and not watched:IsShown() and #sentTo(11, mark, "O2;f;") == 0, "... and nobody can watch")
	B("streamShare"):SetValue(true)
	Advance(0.5)
	check(sentTo(11, mark, "O2;h;1")[1], "on again: told too")

	-- She stops sharing while I watch her.
	pmark = #PRINTED + 1
	mark = #GAMEDATA + 1
	anna("O2;h;0")
	Advance(1.1)
	check(not fwin:IsShown() and not S.IsWatching(11) and printedSince(pmark):find("Anna Brook stopped sharing their fights.", 1, true)
		and sentTo(11, mark, "O2;w;0")[1], "she stops sharing: her window closes, I'm told")
	anna("O2;h;1")

	-- The world map: a click on her dot opens her stream, again closes it.
	OpenWorldMap(1429)
	local pin = pinOf(11)
	pin._mouse = true
	pin:OnMouseEnter()
	check(tooltipHas("Click: watch their fight"), "her dot's tooltip: a click watches her")
	ClickWorldMap()
	check(S.IsWatching(11) and fwin:IsShown() and tooltipHas("Click: close their fight stream"), "clicked: her stream opens; the tooltip says how to close it")
	STATE.shift = true
	ClickWorldMap()
	STATE.shift = false
	check(S.IsWatching(11), "with Shift: nothing")
	ClickWorldMap()
	check(not S.IsWatching(11), "clicked again: closed")
	pin._mouse = false
	pin:OnMouseLeave()
	local bobPin = pinOf(12)
	bobPin._mouse = true
	bobPin:OnMouseEnter()
	ClickWorldMap()
	check(not tooltipHas("Click: watch their fight") and not S.IsWatching(12), "Bob can't be watched: no hint, a click does nothing")
	bobPin._mouse = false
	bobPin:OnMouseLeave()
	B("streamMapClick"):SetValue(false)
	pin._mouse = true
	ClickWorldMap()
	check(not S.IsWatching(11), "setting off: clicks don't open streams")
	pin._mouse = false
	B("streamMapClick"):SetValue(true)
	WorldMapFrame:Hide()

	-- Flights: the friend with the most going on; more from the top bar; they close on landing.
	bob("O2;h;1")
	anna("S2;C;0;260.0;750.0;Goldshire;Hogger")
	anna("C2;3")
	Advance(0.3)
	check(BB.StreamFlightStart() == 11 and S.IsWatching(11) and not S.IsWatching(12), "a flight: the friend in a fight is picked")
	check(BB.StreamToggle(12, "flight") and S.IsWatching(12) and LefthyToolsStreamFriend2 and LefthyToolsStreamFriend2:IsShown()
		and LefthyToolsStreamFriend2._points[1][4] > fwin._points[1][4] + 100, "another opens beside it")
	BB.StreamFlightEnd()
	check(not S.IsWatching(11) and not S.IsWatching(12) and not fwin:IsShown(), "landed: the flight's streams close")
	S.OpenFriend(11, "map")
	BB.StreamFlightEnd()
	check(S.IsWatching(11), "one opened on the map stays")
	do -- Battle.net shows Forever's names with the surname: her first name is enough, her full name too.
		check(BB.peers[11].name == "Anna Brook", "Battle.net: Anna Brook")
		lefthy("stream stop Anna Brook")
		check(not S.IsWatching(11), "/lefthy stream stop by her full name")
		lefthy("stream watch anna")
		Advance(0.6)
		check(S.IsWatching(11), "/lefthy stream watch anna: Anna Brook's stream opens")
		lefthy("stream stop anna stone")
		check(S.IsWatching(11), "... a surname that isn't hers: not her")
		lefthy("stream stop anna")
		check(not S.IsWatching(11), "/lefthy stream stop anna: it closes")
		lefthy("stream watch anna brook")
		check(S.IsWatching(11), "... and opens by her full name")
	end
	lefthy("stream stop")
	check(not S.IsWatching(11), "/lefthy stream stop: every stream closes")
	anna("S2;;0;260.0;750.0;Goldshire;")
	Advance(0.3)
	local pick = BB.StreamFlightStart()
	check((pick == 11 or pick == 12) and S.IsWatching(pick), "nobody fighting: anyone who can be watched")
	BB.StreamFlightEnd()
	B("streamFlights"):SetValue(false)
	check(BB.StreamFlightStart() == nil and not S.IsWatching(11) and not S.IsWatching(12), "setting off: no stream on flights")
	B("streamFlights"):SetValue(true)

	-- The minimap button: a click lists the friends who share; picking one opens their stream.
	Advance(0.1)
	local sb = S.Button()
	check(BDB.streamButton == true and sb and sb:IsShown() and sb:GetParent() == Minimap and not sb.Live:IsShown(),
		"a spyglass on the minimap's edge")
	sb._scripts.OnClick(sb, "LeftButton")
	local rows = sb.List.rows
	check(sb.List:IsShown() and rows[1].Text:GetText():find("Stream", 1, true) and rows[2].Text:GetText():find("Anna", 1, true)
		and rows[3].Text:GetText():find("Bob", 1, true) and rows[5].Text:GetText() == "Your own stream" and not (rows[6] and rows[6]:IsShown()),
		"click: Stream, the friends who share, your own stream")
	rows[2]:Click()
	check(S.IsWatching(11) and sb.Live:IsShown() and not sb.List:IsShown(), "picked: her stream opens, a red dot on the button")
	sb._scripts.OnClick(sb, "LeftButton")
	check(rows[2].Check:IsShown() and not rows[3].Check:IsShown() and rows[6]:IsShown() and rows[6].Text:GetText() == "Close all streams",
		"open again: she's ticked, and all can be closed")
	rows[6]:Click()
	check(not S.IsWatching(11) and not sb.Live:IsShown(), "closed")
	sb._scripts.OnEnter(sb)
	check(TOOLTIP.title == "Fight stream" and tooltipHas("Click: watch a friend's fight"), "hover: what it does")
	sb._scripts.OnLeave(sb)
	B("streamButton"):SetValue(false)
	check(not sb:IsShown(), "setting off: gone")
	B("streamButton"):SetValue(true)
	check(sb:IsShown(), "on again")

	-- She goes offline while I watch her.
	S.OpenFriend(11, "command")
	pmark = #PRINTED + 1
	BN_FRIENDS[1][1].isOnline = false
	Fire("BN_FRIEND_ACCOUNT_OFFLINE", 1, false)
	Advance(2.2)
	check(not S.IsWatching(11) and not fwin:IsShown() and printedSince(pmark):find("Anna Brook went offline: their stream closed.", 1, true),
		"she went offline: her stream closes, I'm told")
	BN_FRIENDS[1][1].isOnline = true
	anna("S2;;0;260.0;750.0;Goldshire;")
	Advance(1.2)

	-- After a fight, a line on how it went (how long, kills, XP, the lowest health) in the bottom
	-- line's place for a few seconds, fading; only for fights seen from their start.
	;(function()
		local function line(w) return w.Summary:IsShown() and w.Summary:GetAlpha() > 0 and w.Summary:GetText() or nil end
		-- Anna's fight, from its start: out of combat, in, her killing blow and its XP, out again.
		local fwin = S.OpenFriend(11, "command").win -- (a window kept from before: whichever is free)
		anna("O2;f;0;1429;260;750;90;;M40;;;;v90")
		Advance(0.6)
		anna("O2;f;0;1429;260;750;90;c;M40;;;;v60")
		Advance(3)
		anna("O2;f;0;1429;260;750;90;c;M40;;;;v35,41k,42x200")
		Advance(0.6)
		anna("O2;f;0;1429;260;750;90;;M40;;;;v40")
		Advance(0.6)
		check(not fwin.Summary:IsShown() and fwin.Status:GetAlpha() == 1, "her fight is over: its line waits a moment (the last XP can come late)")
		Advance(1)
		local text = line(fwin)
		check(text and text:find("^%d s  ·  1 kill  ·  200 XP  ·  lowest ~35%%$") and fwin.Status:GetAlpha() < 1,
			"... then a line in the bottom line's place: how long, her kill, the XP, her lowest health, got " .. tostring(text))
		Advance(6)
		check(not fwin.Summary:IsShown() and fwin.Status:GetAlpha() == 1, "a few seconds later it's gone, the bottom line back")
		-- A fight going on when the window opens: no line (its numbers would be short).
		S.CloseView(11)
		fwin = S.OpenFriend(11, "command").win
		Advance(0.6) -- (nothing from her yet)
		anna("O2;f;0;1429;260;750;90;c;M40;;;;v80")
		Advance(0.6)
		anna("O2;f;0;1429;260;750;90;;M40;;;;v80,43k")
		Advance(2)
		check(not fwin.Summary:IsShown(), "a fight joined halfway: no line")
		S.CloseView(11)
		-- The preview's fight ends now and then: its line shows there too.
		lefthy("stream preview")
		Advance(23.5)
		text = line(win)
		check(text and text:find("^%d+ s  ·  1 kill  ·  87 XP  ·  lowest ~35%%$") and win.Summary.color[2] == 0.82,
			"the preview: her fight ends, its line in gold, got " .. tostring(text))
		win.Close:Click()
		-- My own: a hit, my killing blow and its XP; then a fight I die in; then combat that only flickers.
		MOBS = {}
		S.LifeStart()
		lefthy("stream me")
		Advance(4.6) -- (out of combat: my health known, full)
		local xpWas = XP.current
		EnterCombat()
		Advance(0.6)
		Fire("UNIT_COMBAT", "player", "WOUND", "", 400, 1)
		Advance(2)
		Fire("PARTY_KILL", "Player-1-0", "Creature-0-thug") -- (not a creature's GUID: the Bestiary doesn't count it)
		XP.current = XP.current + 120
		Fire("PLAYER_XP_UPDATE", "player")
		Advance(0.6)
		LeaveCombat()
		Advance(1.6)
		text = line(win)
		check(text and text:find("^%d s  ·  1 kill  ·  120 XP  ·  lowest ~60%%$") and win.Hint:GetAlpha() < 1,
			"my own fight: its line (the hint above the bottom line gives way too), got " .. tostring(text))
		Advance(6)
		STATE.combat = true
		Advance(0.6)
		STATE.dead = true
		Fire("PLAYER_DEAD")
		Advance(2)
		text = line(win)
		check(text and text:find("^Died after %d s$") and win.Summary.color[2] < 0.5, "I die: the fight ends, its line says so, in red, got " .. tostring(text))
		STATE.dead, STATE.combat = false, false
		Fire("PLAYER_UNGHOST")
		Fire("PLAYER_REGEN_ENABLED")
		Advance(6)
		STATE.combat = true
		Advance(0.6)
		STATE.combat = false
		Advance(2)
		check(not win.Summary:IsShown(), "combat that only flickered, nothing in it: no line")
		win.Close:Click()
		XP.current = xpWas
	end)()

	-- Rare finds: a loot's drop chance where it most likely came from (the mobs killed lately), by the
	-- Bestiary's classic database, else my own record of that kind (10 kills or more); below 2% it's
	-- said after its name, in gold, and floats a little bigger and longer. (Creatures the Bestiary's
	-- own tests don't use: it keeps what it read of the database.)
	;(function()
		local chronicled = LefthyToolsChronicleDB.chars["Lefthy-Realmy"].stats -- (Chronicle counts loot too: not this test's)
		local loot2 = chronicled.loot2
		LefthyToolsDropData = { source = "test", mobs = { [9001] = "2075:2:40,2589:1:5000", [9002] = "2075:2:2500" } }
		LefthyToolsBestiaryDB.mobs[9003] = { kills = 100, money = 0, items = { [2075] = { 1, 1, 2, "Priest's Mace" } } }
		local function looted(creatures)
			win.Close:Click()
			lefthy("stream me")
			Advance(0.6)
			for i, creature in ipairs(creatures) do
				Fire("PARTY_KILL", "Player-1-0", ("Creature-0-1-0-1-%d-000000A%d"):format(creature, i))
			end
			Advance(0.6)
			Fire("CHAT_MSG_LOOT", LOOT_ITEM_SELF:format(ItemLink(2075)))
			Advance(0.6)
			return floatWith("Priest's Mace")
		end
		MOBS = {}
		lefthy("stream me")
		local mace = looted({ 9001 })
		check(mace and mace:GetText():find("Priest's Mace, |cffffd14c0.4%|r", 1, true) and mace.textScale > 1 and mace.life == 5,
			"loot from a kind that seldom drops it (the classic database: 0.4%): its chance after its name, in gold, a little longer")
		mace = looted({ 9001, 9002 })
		check(mace and not mace:GetText():find("%", 1, true) and mace.life == 3.5,
			"two killed: from the one that drops it often (25%) likeliest, so not a rare find")
		mace = looted({ 9003 })
		check(mace and mace:GetText():find("Priest's Mace, |cffffd14c1.0%|r", 1, true),
			"a kind the database doesn't know: my own record (1 in 100 kills)")
		LT:SetModuleEnabled("bestiary", false)
		mace = looted({ 9001 })
		check(mace and not mace:GetText():find("%", 1, true), "the Bestiary switched off: plain loot")
		LT:SetModuleEnabled("bestiary", true)
		win.Close:Click()
		-- A friend's: the mob's creature from the names her stream sent, also once it's gone from her frames.
		local fwin = S.OpenFriend(11, "command").win
		anna("O2;n;7;12;Defias Cutpurse")
		anna("O2;c;7;9001")
		anna("O2;f;0;1429;260;750;90;c;M40;;;;v80,51k7")
		Advance(0.6)
		anna("O2;f;0;1429;260;750;90;;M40;;;;v80,51k7,52l2075.2")
		Advance(0.6)
		mace = floatWith("Priest's Mace", fwin)
		check(mace and mace:GetText():find("Priest's Mace, |cffffd14c0.4%|r", 1, true), "her loot, from the mob she killed: a rare find too")
		S.CloseView(11)
		LefthyToolsDropData, LefthyToolsBestiaryDB.mobs[9003] = nil, nil
		chronicled.loot2 = loot2
	end)()

	-- The battle row: hovering a foe shows my own Bestiary card for its kind under the rest, short:
	-- my kills and coin, its three likeliest drops; a kind I haven't killed: "Not killed yet" and the
	-- classic database's three likeliest, greyed.
	;(function()
		LefthyToolsDropData = { source = "test", mobs = { [9005] = "2589:1:5000,2075:2:40,1179:1:900,6948:1:10" } }
		LefthyToolsBestiaryDB.mobs[9006] = { kills = 20, money = 2400, items = { [2589] = { 8, 10, 1, "Linen Cloth" },
			[2075] = { 1, 1, 2, "Priest's Mace" }, [1179] = { 3, 3, 1, "Ice Cold Milk" }, [6948] = { 2, 2, 1, "Hearthstone" } } }
		local fwin = S.OpenFriend(11, "command").win
		anna("O2;n;8;12;Kobold Tunneler")
		anna("O2;c;8;9005")
		anna("O2;n;9;13;Kobold Digger")
		anna("O2;c;9;9006")
		anna("O2;f;0;1429;260;750;90;c;M40;;;;v80/8,90,8,9,act/9,30,6,9,ac")
		Advance(0.6)
		local first, second = fwin.Foes.slots[1], fwin.Foes.slots[2]
		first._scripts.OnEnter(first)
		check(TOOLTIP.title == "Kobold Tunneler (12)" and tooltipFind("Health not known yet") and tooltipFind("Bestiary  Not killed yet: classic database")
			and tooltipFind("Linen Cloth  50%") and tooltipFind("Ice Cold Milk  9.0%") and tooltipFind("Priest's Mace  0.4%")
			and not tooltipFind("Hearthstone"), "hover a foe I haven't killed: under its health, the classic database's three likeliest drops")
		first._scripts.OnLeave(first)
		second._scripts.OnEnter(second)
		check(tooltipFind("Bestiary  20 kills") and tooltipFind("each") and tooltipFind("Linen Cloth  40%") and tooltipFind("Ice Cold Milk  15%")
			and tooltipFind("Hearthstone  10%") and not tooltipFind("Priest's Mace"), "one I've killed: my kills and coin, my three likeliest drops")
		second._scripts.OnLeave(second)
		LT:SetModuleEnabled("bestiary", false)
		second._scripts.OnEnter(second)
		check(TOOLTIP.title == "Kobold Digger (13)" and not tooltipFind("Bestiary"), "the Bestiary switched off: nothing of it")
		second._scripts.OnLeave(second)
		LT:SetModuleEnabled("bestiary", true)
		S.CloseView(11)
		LefthyToolsDropData, LefthyToolsBestiaryDB.mobs[9006] = nil, nil
		-- The preview's foes too: my card for each kind (here: none killed, no database).
		lefthy("stream preview")
		Advance(5)
		local leader = win.Foes.slots[1]
		leader._scripts.OnEnter(leader)
		check(TOOLTIP.title == "Bandit leader (16)" and tooltipFind("Bestiary  Not killed yet"), "the preview: hover a foe, my card for its kind")
		leader._scripts.OnLeave(leader)
		win.Close:Click()
	end)()

	-- The battle row, with pictures handed to it directly (no time passes): a friend's (her mage's)
	-- pictures, her target in each. show(fields): the row after a picture with these fields.
	;(function()
		local view = S.View("me")
		local kind, picture0 = view.kind, view.picture
		local target = { key = "row-target", name = "Kobold Vermin", level = 5, creature = 6, target = true, combat = true,
			engaged = true, health = 1 }
		local function show(fields)
			local picture = { mobs = { target }, recent = {}, moments = {}, classFile = "MAGE", combat = true }
			for k, v in pairs(fields or {}) do picture[k] = v end
			view.picture = picture
			S.BattleShow(view)
			return view.battle
		end
		view.kind = "friend"
		S.BattleReset(view)

		-- Chain casting: her next Fireball began before a picture saw the gap between them; the one
		-- before still went off at her target (not taken for an instant). Pushed back by a hit, a cast
		-- keeps its start: still the same one.
		do
			local now, old = GetTime(), { spellID = 116, icon = 100116, at = GetTime() - 5 }
			show({ cast = { spellID = 133, icon = 100133, start = now - 2.7, finish = now - 0.2 }, recent = { old } })
			local b = show({ cast = { spellID = 133, icon = 100133, start = now - 2.7, finish = now - 0.1 }, recent = { old } })
			check(#b.queue == 0 and not b.action, "a cast pushed back by a hit: still the same cast, nothing went off yet")
			show({ cast = { spellID = 133, icon = 100133, start = now - 0.05, finish = now + 2.45 },
				recent = { { spellID = 133, icon = 100133, at = now - 0.1 }, old } })
			check(#b.queue == 1 and b.queue[1].kind == "spell" and b.queue[1].key == "row-target" and b.queue[1].school == "fire",
				"chain casting: the Fireball before the one she's casting went off at her target, its icon flying over (not an instant)")
		end

		-- Her target loses health picture after picture while her swing still waits its turn: what it
		-- lost adds up on that swing (one swing, not one per picture).
		do
			S.BattleReset(view)
			target.health = 1
			show()
			target.health = 0.9
			local b = show()
			S.BattleUpdate(view, 0) -- (her first swing begins)
			target.health = 0.8
			show()
			target.health = 0.7
			show()
			check(b.action and b.action.kind == "strike" and #b.queue == 1 and b.queue[1].kind == "strike"
				and math.abs(b.queue[1].loss.frac - 0.2) < 1e-6, "losses while her next swing waits: they add up on it")
			target.health = 1
		end

		-- A foe out of the row a while is forgotten: back (or in a friend's stream another mob with its
		-- id, a minute later), what it lost meanwhile isn't her hit.
		do
			S.BattleReset(view)
			target.health = 1
			local b = show()
			show({ mobs = {} })
			local kept = b.foe["row-target"] ~= nil
			b.foe["row-target"].shownAt = GetTime() - 10 -- (as if 10 s had passed)
			show({ mobs = {} })
			target.health = 0.5
			show()
			check(kept and not b.action and #b.queue == 0 and b.foe["row-target"].health == 0.5,
				"a foe back in the row after 10 s away: forgotten meanwhile, no hit of hers made up")
			target.health = 1
		end

		-- A mob too high to tell (the game says level -1: a boss, or far above you): "??", as the game
		-- shows it, in the row and on the radar; a world boss is called elite in both.
		do
			S.BattleReset(view)
			target.level, target.class = -1, "worldboss"
			show()
			local slot = view.win.Foes.slots[1]
			slot._scripts.OnEnter(slot)
			local inRow = TOOLTIP.title == "Kobold Vermin (??)" and tooltipFind("Elite")
			slot._scripts.OnLeave(slot)
			view.kind, view.looked = "me", nil
			view.picture = { mobs = { { key = "skull", name = "Hogger", level = -1, class = "worldboss", yards = 10, bearing = 0, sure = 1 } },
				recent = {}, moments = {}, looked = -1 }
			view.win._scripts.OnUpdate(view.win, 0) -- (a new picture: drawn)
			local dot = view.dotFor.skull
			dot._scripts.OnEnter(dot)
			check(inRow and dot.Name:GetText() == "Hogger ??" and TOOLTIP.title == "Hogger (??)" and tooltipFind("Elite"),
				"level -1: \"??\" in the row's tooltip, on the radar and in its tooltip; a world boss is elite")
			dot._scripts.OnLeave(dot)
			view.kind, target.level, target.class = "friend", 5, nil
		end

		-- Every frame of an open window costs little: what didn't change isn't set again (the cast's
		-- name while it fills its bar, a flash at rest).
		do
			local now = GetTime()
			view.kind, view.looked = "me", nil
			view.picture = { mobs = {}, recent = {}, moments = {}, looked = -2,
				cast = { name = "Frostbolt", icon = 100116, spellID = 116, start = now - 1, finish = now + 1.5 } }
			local name, flash = view.win.Act.Name, view.win.Foes.Hero.Flash
			flash:SetAlpha(0)
			local texts, flashes, setText, setAlpha = 0, 0, name.SetText, flash.SetAlpha
			name.SetText = function(self, ...) texts = texts + 1 return setText(self, ...) end
			flash.SetAlpha = function(self, ...) flashes = flashes + 1 return setAlpha(self, ...) end
			for _ = 1, 3 do view.win._scripts.OnUpdate(view.win, 0.016) end
			name.SetText, flash.SetAlpha = setText, setAlpha
			check(texts == 1 and flashes == 0 and name:GetText() == "Frostbolt",
				"three frames of a cast: its name set once, a flash at rest left alone; got " .. texts .. ", " .. flashes)
			view.kind = "friend"
		end

		-- Hovering a foe whose kind I've killed: my drops with what the classic database says of them,
		-- as on the Bestiary's own card (a drop only while on a quest has its quest mark).
		do
			local dropData = LefthyToolsDropData
			LefthyToolsDropData = { source = "test", mobs = { [9007] = "2589:1:5000q" } }
			LefthyToolsBestiaryDB.mobs[9007] = { kills = 20, money = 0, items = { [2589] = { 8, 10, 1, "Linen Cloth" } } }
			S.BattleReset(view)
			target.creature = 9007
			show()
			local slot = view.win.Foes.slots[1]
			slot._scripts.OnEnter(slot)
			check(tooltipFind("Linen Cloth") and tooltipFind("AvailableQuestIcon"), "a foe I've killed: my drops, a quest drop with its mark")
			slot._scripts.OnLeave(slot)
			target.creature = 6
			LefthyToolsDropData, LefthyToolsBestiaryDB.mobs[9007] = dropData, nil
		end

		view.kind, view.picture = kind, picture0
		S.BattleReset(view)
	end)()

	-- The sensor's books on mobs keep only what's recent: hits on units it never looks at (a player's
	-- nameplate) and casts not seen to end (the nameplate went first) are forgotten after a while too.
	;(function()
		MOBS = {
			nameplate1 = { name = "Cedric", level = 22, player = true, friendly = true, classFile = "PRIEST", guid = "Player-1-90", yards = 20 },
			nameplate2 = { name = "Kobold Vermin", level = 5, guid = "Creature-0-1-0-1-6-00000091", yards = 10 },
		}
		lefthy("stream me") -- (no time passes: the sensor listens from the start)
		Fire("UNIT_COMBAT", "nameplate1", "WOUND", "", 30, 1)
		Fire("UNIT_SPELLCAST_START", "nameplate2", "Cast-9", SECRET)
		local books, forget = S.MobBooks()
		local had = books.lost["Player-1-90"] == 30 and books.casting["Creature-0-1-0-1-6-00000091"] ~= nil
		forget(GetTime() + 301)
		check(had and books.lost["Player-1-90"] == nil and books.hitAt["Player-1-90"] == nil
			and books.casting["Creature-0-1-0-1-6-00000091"] == nil,
			"the sensor forgets, after a while, hits on units it never looks at and casts not seen to end")
		win.Close:Click()
		MOBS = {}
	end)()
	ns.MINIMAP_TILES = realTiles
end

section("Beacon: fight stream: who has aggro, on the battle row")
;(function()
	local S = BB.Stream
	local function slotOf(w, name)
		for _, s in ipairs(w.Foes.slots) do
			if s:IsShown() and s.mob and s.mob.name == name then return s end
		end
	end
	local function tagOf(w, name)
		local s = slotOf(w, name)
		return s and s.Aggro:IsShown() and s.Aggro.Text:GetText() or nil
	end
	local function coloured(w, name, r, g, b)
		local s = slotOf(w, name)
		local c = s and s.Aggro.Text.color
		return c ~= nil and math.abs(c[1] - r) < 0.01 and math.abs(c[2] - g) < 0.01 and math.abs(c[3] - b) < 0.01
	end
	-- My group: me (damage), Bob (the tank), Ölrik (the healer); a mob on each of us, all three on my
	-- threat list (so in my row).
	GROUP = "party"
	PARTY.party1 = { name = "Bob", guid = "Player-1-41" }
	PARTY.party2 = { name = "Ölrik", guid = "Player-1-42" }
	ROLES = { player = "DAMAGER", party1 = "TANK", party2 = "HEALER" }
	MOBS = {
		nameplate1 = { name = "Defias Thug", level = 15, guid = "Creature-0-1-0-1-94-00000021", combat = true, attacking = true,
			yards = 5, x = 0.5, y = 0.45 },
		nameplate2 = { name = "Defias Pillager", level = 16, guid = "Creature-0-1-0-1-589-00000022", combat = true,
			targetGUID = "Player-1-41", yards = 8, x = 0.45, y = 0.5 },
		nameplate3 = { name = "Defias Looter", level = 15, guid = "Creature-0-1-0-1-590-00000023", combat = true,
			targetGUID = "Player-1-42", yards = 12, x = 0.55, y = 0.5 },
	}
	THREAT = { nameplate1 = 3, nameplate2 = 1, nameplate3 = 1 }
	THREATS = { ["party1>nameplate2"] = 3, ["party2>nameplate3"] = 3 }
	Fire("GROUP_ROSTER_UPDATE")
	lefthy("stream me")
	Advance(0.6)
	local win = LefthyToolsStreamFrame
	local thug = slotOf(win, "Defias Thug")
	check(tagOf(win, "Defias Thug") == ">YOU<" and coloured(win, "Defias Thug", 1, 0.32, 0.26)
		and tagOf(win, "Defias Pillager") == "Bob" and coloured(win, "Defias Pillager", 0.35, 0.62, 1)
		and tagOf(win, "Defias Looter") == "Ölr" and coloured(win, "Defias Looter", 0.3, 0.95, 0.4),
		"my window, in a group: who has each foe's aggro, as on the nameplates: >YOU< (my role, damage: red), Bob (tank: blue), Ölr (healer: green)")
	check(thug.Aggro:GetParent() == thug and select(1, thug.Aggro:GetPoint(1)) == "LEFT" and select(3, thug.Aggro:GetPoint(1)) == "TOPLEFT"
		and thug.Aggro:GetFrameLevel() > thug.Model:GetFrameLevel() and thug.Aggro.Text.fontSize == 8,
		"small, on its box's top edge at the left, above its model")
	-- Drawn only when it changes: nothing for a second, then Bob taunts the thug off me.
	do
		local text, sets = thug.Aggro.Text, 0
		local setText = text.SetText
		text.SetText = function(self, ...) sets = sets + 1 return setText(self, ...) end
		Advance(1.1)
		local still = sets
		MOBS.nameplate1.attacking, MOBS.nameplate1.targetGUID = false, "Player-1-41"
		THREAT.nameplate1, THREATS["party1>nameplate1"] = 1, 3
		Advance(0.6)
		text.SetText = setText
		check(still == 0 and sets == 1 and tagOf(win, "Defias Thug") == "Bob", "drawn only when it changes: Bob taunted it off me")
	end
	-- The nameplate tweak off (as with Misc Tweaks off): the same, the group still read again when it changes.
	lefthy("tweaks aggro off")
	Advance(0.1)
	ROLES.party1 = "DAMAGER"
	Fire("PLAYER_ROLES_ASSIGNED")
	Advance(0.6)
	check(not ns.GetAggroTag("nameplate2") and tagOf(win, "Defias Pillager") == "Bob" and coloured(win, "Defias Pillager", 1, 0.32, 0.26),
		"the nameplate tweak off: still there, and roles followed (Bob picked damage: red)")
	ROLES.party1 = "TANK"
	lefthy("tweaks aggro on")
	Fire("PLAYER_ROLES_ASSIGNED")
	Advance(0.6)
	-- Its target and the group's threat hidden: nothing said (not a wrong one). Solo: nothing at all.
	MOBS.nameplate3.targetGUID, THREATS["party2>nameplate3"] = SECRET, SECRET
	Advance(0.6)
	check(slotOf(win, "Defias Looter") and tagOf(win, "Defias Looter") == nil, "its target and the group's threat hidden: no tag")
	MOBS.nameplate3.targetGUID, THREATS["party2>nameplate3"] = "Player-1-42", 3
	GROUP = "none"
	Fire("GROUP_ROSTER_UPDATE")
	Advance(0.6)
	check(slotOf(win, "Defias Thug") and not tagOf(win, "Defias Thug") and not tagOf(win, "Defias Pillager"), "solo: no tags")
	GROUP = "party"
	Fire("GROUP_ROSTER_UPDATE")
	MOBS.nameplate1.attacking, MOBS.nameplate1.targetGUID, THREAT.nameplate1, THREATS["party1>nameplate1"] = true, nil, 3, nil

	-- Anna watches me: who has aggro goes with my frames, after my foes' health, "<id>@<role><name>"
	-- (no name: me).
	local from = #GAMEDATA + 1
	anna("O2;w;1")
	Fire("UNIT_COMBAT", "player", "WOUND", "", 40, 1)
	Advance(1.1)
	local ids = {}
	for _, m in ipairs(sentTo(11, from, "O2;n;")) do
		local id, name = m:match("^O2;n;(%d+);%d*;(.+)$")
		ids[name or "?"] = id
	end
	local frames = sentTo(11, from, "O2;f;")
	local frame = frames[#frames] or ""
	local fields = {}
	for f in (frame:sub(6) .. ";"):gmatch("([^;]*);") do fields[#fields + 1] = f end
	local vitals = (fields[11] or ""):match("^(v[^/]*)") or ""
	local function has(name, part) return ids[name] ~= nil and ("," .. vitals .. ","):find("," .. ids[name] .. part .. ",", 1, true) ~= nil end
	check(#fields == 11 and #frame <= 250 and has("Defias Thug", "@d") and has("Defias Pillager", "@tBob") and has("Defias Looter", "@hÖlr")
		and has("Defias Thug", "=100") and vitals:find(",%d+w40$"),
		"my frames say who has my foes' aggro: me (no name), Bob, Ölr (whole letters); my health, theirs and my hit as before; got " .. frame)
	-- What a build from before reads from it (its DecodeVitals, as it was): the same health, foes'
	-- health and moments; the new parts match none of its patterns (a moment needs a letter after
	-- its number, "@" isn't one), so they're skipped.
	do
		local function oldRead(entry)
			local got, first = { foes = {}, moments = {} }, true
			for part in entry:gmatch("[^,]+") do
				if first then
					first = false
					got.health = part:match("^v(%d?%d?%d?)$")
					if not got.health then return nil end
				elseif part:match("^%?%a$") then
					got.why = part
				elseif part:match("^%d+=%d+$") then
					got.foes[#got.foes + 1] = part
				elseif part:match("^(%d%d?)(%a)(%w*)%.?(%d*)$") then
					got.moments[#got.moments + 1] = part
				end
			end
			return got
		end
		local a, b = oldRead(vitals), oldRead((vitals:gsub(",%d+@[^,]*", "")))
		local skipped = true
		for _, part in ipairs({ "1@t", "12@dÄbc", "999@o???", "5@h中文字", "7@nÖlr", "42@p", "3@tB=1" }) do
			if part:match("^%?%a$") or part:match("^%d+=%d+$") or part:match("^(%d%d?)(%a)(%w*)%.?(%d*)$") then skipped = false end
		end
		check(a and b and a.health == b.health and a.why == b.why and table.concat(a.foes, ",") == table.concat(b.foes, ",")
			and table.concat(a.moments, ",") == table.concat(b.moments, ",") and #a.moments == 1 and #a.foes == 3 and skipped,
			"a build from before reads the same from it (health, foes' health, moments): the new parts match none of its patterns")
	end
	-- What I send is what she sees: my frames fed back as hers. On her window she's the one shown:
	-- the thug on her says her name (in her role's colour, damage: red).
	anna("O2;h;1")
	S.OpenFriend(11, "command")
	local fwin = S.View(11).win
	for _, m in ipairs(sentTo(11, from, "O2;n;")) do anna(m) end
	for _, m in ipairs(sentTo(11, from, "O2;c;")) do anna(m) end
	anna(frame)
	Advance(0.6)
	check(tagOf(fwin, "Defias Thug") == "Ann" and coloured(fwin, "Defias Thug", 1, 0.32, 0.26) and tagOf(fwin, "Defias Pillager") == "Bob"
		and coloured(fwin, "Defias Pillager", 0.35, 0.62, 1) and tagOf(fwin, "Defias Looter") == "Ölr"
		and coloured(fwin, "Defias Looter", 0.3, 0.95, 0.4), "her window: who has her foes' aggro, from her frames: Ann (herself), Bob, Ölr")
	-- A build from before it (no such part), in a group (someone of it near her, "g"): a mob
	-- attacking her is on her, white (no role known); nobody of her group near: nothing.
	anna("O2;n;31;15;Defias Thug")
	anna("O2;c;31;94")
	anna("O2;n;32;16;Defias Pillager")
	anna("O2;c;32;589")
	anna("O2;u;33;18;WARRIOR;Bob")
	anna("O2;f;0;1429;260;750;90;c;M40;;;;v80,31=60/31,0,5,9,ach/32,40,8,9,ch/33,10,6,9,pfg")
	Advance(0.6)
	check(tagOf(fwin, "Defias Thug") == "Ann" and coloured(fwin, "Defias Thug", 0.92, 0.92, 0.92) and slotOf(fwin, "Defias Pillager")
		and tagOf(fwin, "Defias Pillager") == nil, "a frame from a build before it, in a group: the mob attacking her says her name, white")
	anna("O2;f;0;1429;260;750;90;c;M40;;;;v80,31=60/31,0,5,9,ach/32,40,8,9,ch")
	Advance(0.6)
	check(slotOf(fwin, "Defias Thug") and tagOf(fwin, "Defias Thug") == nil, "... nobody of her group near (solo, maybe): nothing")
	anna("O2;f;0;1429;260;750;90;c;M40;;;;v80,32@tBob/31,0,5,9,ach/32,40,8,9,ch/33,10,6,9,pfg")
	Advance(0.6)
	check(tagOf(fwin, "Defias Thug") == nil and tagOf(fwin, "Defias Pillager") == "Bob", "her build sends it: only what it says")
	anna("O2;f;0;1429;260;750;90;c;M40;;;;v80,31@xÉvilname,32@t/31,0,5,9,ach/32,40,8,9,ch")
	Advance(0.6)
	check(tagOf(fwin, "Defias Thug") == "Évi" and coloured(fwin, "Defias Thug", 0.92, 0.92, 0.92) and tagOf(fwin, "Defias Pillager") == "Ann"
		and coloured(fwin, "Defias Pillager", 0.35, 0.62, 1), "a role letter this build doesn't know: white; three whole letters at most; no name: her")
	S.CloseView(11)

	-- The preview: her Fireball pulls the leader (her name, red) until Bob takes it at 8 s (blue); the
	-- bandit is on her, the mage on Cedric, passing by, outside her group (grey).
	lefthy("stream preview")
	Advance(3)
	check(tagOf(win, "Bandit leader") == "Ann" and coloured(win, "Bandit leader", 1, 0.32, 0.26) and tagOf(win, "Bandit") == "Ann"
		and tagOf(win, "Bandit mage") == "Ced" and coloured(win, "Bandit mage", 0.6, 0.6, 0.6),
		"the preview: the leader and the bandit on her, the mage on someone outside her group")
	Advance(6)
	check(tagOf(win, "Bandit leader") == "Bob" and coloured(win, "Bandit leader", 0.35, 0.62, 1), "... and Bob, the tank, takes the leader at 8 s")
	win.Close:Click()
	anna("O2;w;0")
	for i = 1, 3 do Fire("NAME_PLATE_UNIT_REMOVED", "nameplate" .. i) end -- (the nameplate tweak, on again, took them up)
	GROUP, PARTY.party1, PARTY.party2, ROLES, MOBS, THREAT, THREATS = "none", nil, nil, {}, {}, {}, {}
	Fire("GROUP_ROSTER_UPDATE")
	Advance(0.6)
	check(not S.SenseRunning() and not S.IsWatching(11), "closed, nobody watching: the sensor stops")
end)()

section("Beacon: a busy fight doesn't pile up messages")
do
	anna("S2;;0;260.0;750.0;Goldshire;")
	Advance(0.2)
	mark = #GAMEDATA + 1
	MOCK_SEND_RESULT = 3 -- the server is throttling: everything waits in the queue
	EnterCombat()
	for i = 1, 4 do
		THREAT["nameplate" .. i] = 1
		Fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. i)
		Advance(1.05)
	end
	MOCK_SEND_RESULT = nil
	Advance(3)
	local counts = sentTo(11, mark, "C2;")
	check(#counts == 1 and counts[1] == "C2;4", "only the newest count goes out once the queue moves, got " .. table.concat(counts, ","))
	LeaveCombat()
	for i = 1, 4 do Fire("NAME_PLATE_UNIT_REMOVED", "nameplate" .. i) end
	THREAT = {}
	Advance(1.2)
end
