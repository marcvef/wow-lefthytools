local _, ns = ...
if ns.LOCALE ~= "deDE" then
	return
end

-- Style: how German WoW players talk, not Blizzard's formal translations. Keep the
-- English terms players actually use (Interface, Minimap, Buffs, Cooldown, Raid,
-- Mouseover, Pet, HP, Damage Meter). Module and addon names are never translated.

local L = ns.L
ns.DECIMAL_COMMA = true -- "1,5 s" instead of "1.5 s"

-- Overview
L["Info"] = "Info"
L["Version"] = "Version"
L["The installed LefthyTools build. 0.4.0 is a release, 0.4.0-3-g1a2b3c4 is three changes after it."] =
	"Der installierte Stand von LefthyTools. 0.4.0 ist ein Release, 0.4.0-3-g1a2b3c4 drei Änderungen danach."
L["Updates"] = "Updates"
L["LefthyTools can't go online itself: it learns about newer versions from Battle.net friends who use it (Beacon). To update, run Update-LefthyTools.cmd again, then /reload."] =
	"LefthyTools kann selbst nicht online nachsehen: Von neueren Versionen erfährt es über Battle.net-Freunde, die es auch nutzen (Beacon). Zum Updaten Update-LefthyTools.cmd nochmal starten, dann /reload."
L["Newer version available: %s"] = "Neuere Version verfügbar: %s"
L["Unknown (Beacon is off)"] = "Unbekannt (Beacon ist aus)"
L["Unknown (no friend with LefthyTools online)"] = "Unbekannt (kein Freund mit LefthyTools online)"
L["Up to date (compared with %d friend(s))"] = "Aktuell (verglichen mit %d Freund(en))"
L["You: %s"] = "Du: %s"
L["No friend with LefthyTools online right now."] = "Gerade ist kein Freund mit LefthyTools online."
L["0.3.0 or older"] = "0.3.0 oder älter"
L["newer"] = "neuer"
L["older"] = "älter"
L["same"] = "gleich"
L["Modules"] ="Module"
L["Settings: LefthyTools > %s"] = "Einstellungen: LefthyTools > %s"

-- Error catcher
L["Errors"] = "Fehler"
L["LefthyTools' own Lua errors, kept across sessions. /lefthy errors shows them ready to copy, /lefthy errors clear removes them."] =
	"Lua-Fehler von LefthyTools selbst, auch über mehrere Sessions gespeichert. /lefthy errors zeigt sie zum Kopieren an, /lefthy errors clear löscht sie."
L["None"] = "Keine"
L["%d (type /lefthy errors)"] = "%d (/lefthy errors eingeben)"
L["LefthyTools errors"] = "LefthyTools-Fehler"
L["Click into the text, press Ctrl+A and then Ctrl+C to copy it, and send it to whoever gave you LefthyTools."] =
	"In den Text klicken, Strg+A und dann Strg+C drücken, um ihn zu kopieren, und ihn dem schicken, von dem du LefthyTools hast."
L["Clear"] = "Löschen"

-- What's new
L["What's new"] = "Neuigkeiten"
L["Show"] = "Anzeigen"
L["Every change to LefthyTools, newest first. After an update this opens by itself once."] =
	"Alle Änderungen an LefthyTools, die neuesten zuerst. Nach einem Update öffnet sich das einmal von selbst."
L["What's new in LefthyTools"] = "Neu in LefthyTools"
L["All changes"] = "Alle Änderungen"
L["You have LefthyTools %s."] = "Du hast LefthyTools %s."
L["%s (in development)"] = "%s (in Arbeit)"
L["General"] = "Allgemein"

-- Mirage
L["Fades the interface when you're out of combat and not using it, like Dune: Awakening's Dynamic HUD."] =
	"Blendet das Interface aus, wenn du nicht im Kampf bist und es gerade nicht benutzt, wie das Dynamic HUD in Dune: Awakening."
L["Mirage: toggle interface fading"] = "Mirage: Interface-Ausblenden an/aus"
L["Mirage: show interface (hold)"] = "Mirage: Interface zeigen (gedrückt halten)"

L["Timing"] = "Timing"
L["Idle delay"] = "Wartezeit bis zum Ausblenden"
L["How long you must be inactive before the interface starts fading."] =
	"Wie lange du inaktiv sein musst, bis das Interface ausgeblendet wird."
L["Fade-out duration"] = "Dauer des Ausblendens"
L["How long the fade-out takes once it starts."] = "Wie lange das Ausblenden dauert, sobald es beginnt."
L["Fade-in duration"] = "Dauer des Einblendens"
L["How long the interface takes to come back."] = "Wie lange das Interface braucht, um wieder zu erscheinen."
L["Faded opacity"] = "Deckkraft (ausgeblendet)"
L["Opacity of faded elements. 0% hides them completely. Sets every element at once; change single elements under Elements to fade."] =
	"Deckkraft ausgeblendeter Elemente. Bei 0 % sind sie komplett unsichtbar. Stellt alle Elemente auf einmal ein; einzelne Elemente änderst du unter Elemente zum Ausblenden."

L["Keep the interface visible"] = "Interface sichtbar lassen"
L["While you have a target"] = "Solange du ein Ziel hast"
L["Any living target keeps the interface visible."] = "Jedes lebende Ziel hält das Interface sichtbar."
L["Only for attackable targets"] = "Nur bei angreifbaren Zielen"
L["Only count targets you can attack (requires the option above)."] =
	"Zählt nur Ziele, die du angreifen kannst (benötigt die Option darüber)."
L["While a window is open"] = "Solange ein Fenster offen ist"
L["Bags, map, character sheet, vendors, quest dialogs and other windows."] =
	"Taschen, Weltkarte, Charakterfenster, Händler, Questfenster und andere Fenster."
L["While dead or a ghost"] = "Solange du tot oder ein Geist bist"
L["While moving"] = "Während du dich bewegst"
L["Off by default: running around counts as idle, like Dune's Dynamic HUD."] =
	"Standardmäßig aus: Herumlaufen zählt als inaktiv, wie beim Dynamic HUD in Dune."

L["Reveal briefly"] = "Kurz einblenden"
L["On mouseover"] = "Bei Mouseover"
L["Hovering where a faded element sits reveals that element."] =
	"Mouseover über ein ausgeblendetes Element blendet es wieder ein."
L["Player frame while regenerating"] = "Spielerfenster beim Regenerieren"
L["Show the player frame while health or mana is ticking back up out of combat."] =
	"Zeigt das Spielerfenster, solange HP oder Mana außerhalb des Kampfes regenerieren."
L["Chat on new messages"] = "Chat bei neuen Nachrichten"
L["Whispers, party, raid, guild and instance messages briefly reveal the chat."] =
	"Flüster-, Gruppen-, Raid-, Gilden- und Instanznachrichten blenden den Chat kurz ein."

L["Elements to fade"] = "Elemente zum Ausblenden"
L["Fade this element when idle."] = "Dieses Element ausblenden, wenn du inaktiv bist."
L["How much of this element stays visible when faded. 0% hides it."] =
	"Wie viel von diesem Element beim Ausblenden sichtbar bleibt. Bei 0 % ist es ganz weg."
L["Also hide minimap quest areas"] = "Questgebiete auf der Minimap auch ausblenden"
L["Quest areas on the minimap ignore transparency, so the minimap is hidden once it has faded out. Only applies when the minimap fades to 0%."] =
	"Questgebiete auf der Minimap ignorieren Transparenz, deshalb wird die Minimap ganz versteckt, sobald sie ausgeblendet ist. Gilt nur, wenn die Minimap auf 0 % ausgeblendet wird."
L["Hide quest areas at"] = "Questgebiete verstecken bei"
L["Minimap opacity at which the minimap and its quest areas are hidden during the fade-out. 0% waits until the fade has finished."] =
	"Deckkraft der Minimap, bei der Minimap und Questgebiete beim Ausblenden versteckt werden. Bei 0 % erst, wenn das Ausblenden fertig ist."

-- Mirage: AFK screen
L["AFK screen"] = "AFK-Bildschirm"
L["While you're AFK the interface disappears and a panel shows your character, how long you've been away, whispers, friends' news and which friends are online. Moving, combat, a ready check or a click brings everything back."] =
	"Solange du AFK bist, verschwindet das Interface und eine Leiste zeigt deinen Charakter, wie lange du weg bist, Flüsternachrichten, Neuigkeiten von Freunden und welche Freunde online sind. Bewegen, Kampf, ein Bereitschaftscheck oder ein Klick holt alles zurück."
L["Circle the camera"] = "Kamera kreisen lassen"
L["The camera slowly circles your character while the AFK screen is up."] =
	"Die Kamera kreist langsam um deinen Charakter, solange der AFK-Bildschirm zu sehen ist."
L["Move, or click anywhere, to come back."] = "Beweg dich oder klick irgendwohin, um zurückzukommen."
L["AFK"] = "AFK"
L["Level %d %s %s"] = "Level %d %s %s"
L["Time: %s"] = "Uhrzeit: %s"
L["Level progress: %d%%"] = "Level-Fortschritt: %d %%"
L["rested: %d%%"] = "erholt: %d %%"
L["Whispers: %d (last from %s)"] = "Flüsternachrichten: %d (zuletzt von %s)"
L["While you were away"] = "Während du weg warst"
L["%s reached level %d"] = "%s hat Level %d erreicht"
L["%s died, fighting %s"] = "%s ist gestorben, im Kampf gegen %s"
L["%s died"] = "%s ist gestorben"
L["Friends online"] = "Freunde online"
L["No friends with LefthyTools online"] = "Keine Freunde mit LefthyTools online"
L["and %d more"] = "und %d weitere"

-- Mirage element groups
L["Action bars"] = "Aktionsleisten"
L["Controller action bars & button legend"] = "Controller-Aktionsleisten & Tastenhinweise"
L["Controller aiming reticle"] = "Controller-Fadenkreuz"
L["Player, pet, target & focus frames"] = "Spieler-, Pet-, Ziel- & Fokusfenster"
L["Party & raid frames"] = "Gruppen- & Raidfenster"
L["Cooldown Manager & swing timer"] = "Cooldown Manager & Swing-Timer"
L["Buffs & debuffs"] = "Buffs & Debuffs"
L["Minimap"] = "Minimap"
L["Quest & objective tracker"] = "Quest-Tracker"
L["Micro menu & bag bar"] = "Menü- & Taschenleiste"
L["Experience & reputation bars"] = "EP- & Rufleiste"
L["Damage meter"] = "Damage Meter"
L["Chat"] = "Chat"
L["Durability & vehicle indicators"] = "Haltbarkeits- & Fahrzeuganzeige"

-- Misc Tweaks
L["Small quality-of-life fixes, each one switchable on its own."] =
	"Kleine Komfort-Verbesserungen, jede einzeln an- und abschaltbar."
L["Unit frames"] = "Unitframes"
L["Always show health & power values"] = "HP- & Ressourcenwerte immer anzeigen"
L["Show current / max on the health and power bars all the time instead of only on mouseover. Applies to every unit frame (player, target, focus, pet, party), like Blizzard's Options > Interface > Status Text set to Numeric."] =
	"Zeigt aktuell / maximal dauerhaft auf den HP- und Ressourcenleisten statt nur bei Mouseover. Gilt für alle Unitframes (Spieler, Ziel, Fokus, Pet, Gruppe), genau wie Blizzards Interface-Option „Statustext“ mit Zahlenwerten."
L["Bags"] = "Taschen"
L["Movable bags"] = "Verschiebbare Taschen"
L["Drag a bag by its title bar or any empty spot to move it. It reopens where you left it. /lefthy tweaks resetbags puts all bags back."] =
	"Zieh eine Tasche an der Titelleiste oder an einer freien Stelle, um sie zu verschieben. Sie öffnet sich wieder dort, wo du sie gelassen hast. /lefthy tweaks resetbags setzt alle Taschen zurück."
L["Quests"] = "Quests"
L["Announce quest progress in party chat"] = "Questfortschritt im Gruppenchat posten"
L["When you finish a quest objective or a whole quest while in a party, your character posts it in party chat, like Questie does. Not solo and not in raids."] =
	"Wenn du in einer Gruppe ein Questziel oder eine ganze Quest abschließt, postet dein Charakter das im Gruppenchat, so wie Questie. Nicht solo und nicht im Raid."

L["Mark quests that are new in WoW: Forever"] = "Quests markieren, die neu in WoW: Forever sind"
L["WoW: Forever adds over a thousand quests to the Classic world, plus about as many from Classic's later seasons that original Classic never had. They get a NEW right after their name: in the quest log (hover for details), in the quest details and in the quest window when you accept or turn one in."] =
	"WoW: Forever bringt über tausend neue Quests in die Classic-Welt, dazu etwa genauso viele aus den späteren Seasons von Classic, die es im ursprünglichen Classic nie gab. Sie bekommen ein NEU direkt hinter ihrem Namen: im Questlog (Mouseover für Details), in den Questdetails und im Questfenster beim Annehmen und Abgeben."
L["New in WoW: Forever"] = "Neu in WoW: Forever"
L["Not in the original Classic (from its later seasons)"] = "Nicht im ursprünglichen Classic (aus den späteren Seasons)"
L["Combo points on the personal resource display"] = "Combopunkte an der persönlichen Ressourcenanzeige"
L["Forever's personal resource display leaves combo points out. This adds them under its bars in retail's style, with Blizzard's animations; at full points they glow. Rogues, and druids in Cat Form. Shows when the personal resource display does."] =
	"Die persönliche Ressourcenanzeige in Forever zeigt keine Combopunkte. Das hier fügt sie unter ihren Balken hinzu, im Retail-Look mit Blizzards Animationen; bei vollen Punkten leuchten sie. Für Schurken und Druiden in Katzengestalt. Sichtbar, wenn die persönliche Ressourcenanzeige es ist."
L["Colour combo points by count"] = "Combopunkte nach Anzahl färben"
L["Green with one point, through yellow and orange, to red at full points. Off: retail's red."] =
	"Grün bei einem Punkt, über Gelb und Orange bis Rot bei vollen Punkten. Aus: das Rot aus Retail."

-- Beacon
L["Shares your position with Battle.net friends who also use LefthyTools and shows theirs on the world map and minimap, in their class colour."] =
	"Teilt deine Position mit Battle.net-Freunden, die auch LefthyTools nutzen, und zeigt ihre auf Weltkarte und Minimap, in Klassenfarbe."
L["Sharing"] = "Teilen"
L["Share my position"] = "Meine Position teilen"
L["Battle.net friends who also use LefthyTools see you on their maps, and whether you're dead or in combat. Not available in dungeons and raids."] =
	"Battle.net-Freunde mit LefthyTools sehen dich auf ihren Karten, und ob du tot oder im Kampf bist. In Dungeons und Raids nicht verfügbar."
L["Share the quest I'm tracking"] = "Meine verfolgte Quest teilen"
L["Friends see the quest you're tracking, and your progress, when they hover your dot."] =
	"Freunde sehen die Quest, die du verfolgst, und deinen Fortschritt, wenn sie mit der Maus über deinen Punkt fahren."
L["Update interval"] = "Update-Intervall"
L["How often your position is sent while you move. Standing still sends almost nothing."] =
	"Wie oft deine Position gesendet wird, während du dich bewegst. Wer stillsteht, sendet fast nichts."
L["Map"] = "Karte"
L["Show friends on the world map"] = "Freunde auf der Weltkarte zeigen"
L["Dots in their class colour, a skull when they're dead and a red ring in combat. Hover for details. Friends in your group are already shown by the game."] =
	"Punkte in Klassenfarbe, ein Totenkopf, wenn sie tot sind, und ein roter Ring im Kampf. Mouseover zeigt Details. Freunde in deiner Gruppe zeigt das Spiel schon selbst."
L["Show friends on the minimap"] = "Freunde auf der Minimap zeigen"
L["The same dots on the minimap. Friends in your group are already shown by the game."] =
	"Dieselben Punkte auf der Minimap. Freunde in deiner Gruppe zeigt das Spiel schon selbst."
L["Show friends in my group too"] = "Freunde in meiner Gruppe auch zeigen"
L["Friends in your group keep their Beacon dot, with a blue ring, on top of the game's own group dot, and the tooltip says they're in your group. Off: only the game's dot."] =
	"Freunde in deiner Gruppe behalten ihren Beacon-Punkt, mit blauem Ring, über dem Gruppenpunkt des Spiels, und der Tooltip zeigt, dass sie in deiner Gruppe sind. Aus: nur der Punkt des Spiels."
L["Keep far-away friends at the minimap edge"] = "Entfernte Freunde am Minimap-Rand zeigen"
L["Friends beyond the minimap's range stay faded at its edge, so you can see which way they are."] =
	"Freunde außerhalb der Minimap-Reichweite bleiben blass am Rand, damit du siehst, in welcher Richtung sie sind."
L["Alerts"] = "Meldungen"
L["Tell me when a friend dies"] = "Melden, wenn ein Freund stirbt"
L["A chat line when a friend dies: where, and what they were fighting."] =
	"Eine Chatzeile, wenn ein Freund stirbt: wo, und wogegen er gekämpft hat."
L["Show items to friends"] = "Items Freunden zeigen"
L["Ctrl+right-click an item (bags, character, bank, loot, chat links) to show it to your friends: they see it big on screen, with the whisper sound. Ctrl+Shift+right-click offers it: they can say Need or Pass, and if several need it, it is rolled out."] =
	"Strg+Rechtsklick auf ein Item (Taschen, Charakter, Bank, Loot, Chat-Links) zeigt es deinen Freunden: Sie sehen es groß auf dem Bildschirm, mit dem Flüster-Sound. Strg+Umschalt+Rechtsklick bietet es an: Sie können Bedarf oder Passen wählen, und wenn mehrere Bedarf haben, wird gewürfelt."
L["%s shares %s"] = "%s zeigt %s"
L["%s offers %s"] = "%s bietet %s an"
L["Need"] = "Bedarf"
L["Pass"] = "Passen"
L["You offer %s"] = "Du bietest %s an"
L["Waiting for your friends..."] = "Warte auf deine Freunde ..."
L["You need it. Fingers crossed!"] = "Du hast Bedarf. Daumen drücken!"
L["You passed."] = "Du hast gepasst."
L["Nobody needs it."] = "Keiner braucht es."
L["You win!"] = "Du gewinnst!"
L["%s wins!"] = "%s gewinnt!"
L["Rolling..."] = "Es wird gewürfelt ..."
L["Won by %s: still to hand over"] = "Gewonnen von %s: noch übergeben"
L["%s is reserved for %s: they won it. Sell it anyway?"] = "%s ist für %s reserviert, gewonnen beim Würfeln. Trotzdem verkaufen?"
L["Sell anyway"] = "Trotzdem verkaufen"
L["Keep it"] = "Behalten"
L["Map pings"] = "Karten-Pings"
L["Alt+click on the world map shows your friends a spot: a marker on their maps for a minute, with a sound. Their pings show up on your maps. /lefthy beacon ping pings where you stand."] =
	"Alt+Klick auf die Weltkarte zeigt deinen Freunden eine Stelle: eine Markierung auf ihren Karten für eine Minute, mit Sound. Ihre Pings erscheinen auf deinen Karten. /lefthy beacon ping pingt die Stelle, an der du stehst."
L["Map ping, %d s ago"] = "Karten-Ping, vor %d s"
L["Level-ups"] = "Level-Ups"
L["Tell my friends when I level up"] = "Freunden meine Level-Ups melden"
L["Battle.net friends who also use LefthyTools see your level-up message."] =
	"Battle.net-Freunde mit LefthyTools sehen deine Level-Up-Nachricht."
L["Level-up message"] = "Level-Up-Nachricht"
L["What your friends see when you level up. {name} and {level} are filled in. Leave it empty for the default."] =
	"Was deine Freunde sehen, wenn du levelst. {name} und {level} werden ersetzt. Leer lassen für die Standardnachricht."
L["Test your message"] = "Nachricht testen"
L["Preview"] = "Vorschau"
L["Shows your level-up message the way your friends will see it."] =
	"Zeigt deine Level-Up-Nachricht so, wie deine Freunde sie sehen."
L["Show my friends' level-ups"] = "Level-Ups von Freunden zeigen"
L["Big text on screen and a chat line when a friend levels up."] =
	"Großer Text auf dem Bildschirm und eine Chatzeile, wenn ein Freund levelt."
L["Play a sound"] = "Sound abspielen"
L["Plays a sound with a friend's level-up message."] = "Spielt einen Sound zur Level-Up-Nachricht eines Freundes."
L["Level-up sound"] = "Level-Up-Sound"
L["The sound for a friend's level-up. Picking one plays it."] = "Der Sound zum Level-Up eines Freundes. Beim Auswählen hörst du ihn."
L["Boss defeated fanfare"] = "Boss-besiegt-Fanfare"
L["World quest complete"] = "Weltquest abgeschlossen"
L["Legendary loot"] = "Legendärer Loot"
L["Epic loot"] = "Epischer Loot"
L["Scenario complete"] = "Szenario abgeschlossen"
L["Gentle chime"] = "Leises Glockenspiel"

-- Beacon tooltip on a friend's dot
L["Level %d"] = "Level %d"
L["Level %d (%d%%)"] = "Level %d (%d %%)"
L["In your group"] = "In deiner Gruppe"
L["Dead"] = "Tot"
L["Ghost"] = "Geist"
L["In combat"] = "Im Kampf"
L["Fighting %s"] = "Kämpft gegen %s"
L["Fighting %s and %d more"] = "Kämpft gegen %s und %d weitere"
L["In combat with %d enemies"] = "Im Kampf mit %d Gegnern"
L["In combat with 1 enemy"] = "Im Kampf mit 1 Gegner"
L["Right next to you"] = "Direkt bei dir"
L["Quest: %s"] = "Quest: %s"
L["Ready to turn in"] = "Bereit zum Abgeben"
L["You have this quest too"] = "Die Quest hast du auch"
L["%d yd %s"] = "%d m %s" -- the German client says Meter for yards
L["north"] = "nördlich"
L["north-east"] = "nordöstlich"
L["east"] = "östlich"
L["south-east"] = "südöstlich"
L["south"] = "südlich"
L["south-west"] = "südwestlich"
L["west"] = "westlich"
L["north-west"] = "nordwestlich"

-- Chronicle
L["A journal for each character, kept automatically: level-ups, deaths, dungeons, bosses, rares, loot, mounts and milestones, statistics, and what your friends did."] =
	"Ein Tagebuch für jeden Charakter, das sich von selbst schreibt: Level-Ups, Tode, Dungeons, Bosse, Rares, Loot, Mounts und Meilensteine, Statistiken und was deine Freunde so erlebt haben."
L["Share highlights with friends"] = "Highlights mit Freunden teilen"
L["Bosses, rares, first dungeon visits, epic loot, new mounts, achievements and milestones go to Battle.net friends with LefthyTools (needs Beacon)."] =
	"Bosse, Rares, erste Dungeon-Besuche, epischer Loot, neue Mounts, Erfolge und Meilensteine gehen an Battle.net-Freunde mit LefthyTools (braucht Beacon)."
L["Show friends' highlights in chat"] = "Highlights von Freunden im Chat zeigen"
L["A chat line when a friend shares a highlight. They're always in Chronicle's Friends tab."] =
	"Eine Chatzeile, wenn ein Freund ein Highlight teilt. Im Freunde-Tab von Chronicle stehen sie immer."
L["Journal"] = "Tagebuch"
L["Open the journal"] = "Tagebuch öffnen"
L["Open"] = "Öffnen"
L["Your timeline, your statistics and your friends' news. Also /chronicle or a key binding."] =
	"Deine Zeitleiste, deine Statistiken und die Neuigkeiten deiner Freunde. Auch mit /chronicle oder einer Tastenbelegung."
L["Chronicle: open or close the journal"] = "Chronicle: Tagebuch öffnen/schließen"
L["This session: %s played, %s XP, %d quests, %d kills"] = "Diese Session: %s gespielt, %s EP, %d Quests, %d Kills"
L["%.1f km"] = "%.1f km"
-- Chronicle window
L["Timeline"] = "Zeitleiste"
L["Statistics"] = "Statistiken"
L["Friends"] = "Freunde"
L["Characters"] = "Charaktere"
L["%Y-%m-%d"] = "%d.%m.%Y"
L["Nothing recorded yet."] = "Noch nichts aufgezeichnet."
L["... and %d older entries"] = "... und %d ältere Einträge"
L["(took %s)"] = "(hat %s gedauert)"
L["Died to %s"] = "Gestorben durch %s"
L["Died"] = "Gestorben"
L["(level %d)"] = "(Level %d)"
L["Discovered %s"] = "%s entdeckt"
L["First visit: %s"] = "Zum ersten Mal: %s"
L["Defeated %s"] = "%s besiegt"
L["Killed the rare %s"] = "Rare %s getötet"
L["Looted %s"] = "%s gelootet"
L["New mount: %s"] = "Neues Mount: %s"
L["New pet: %s"] = "Neues Pet: %s"
L["New toy: %s"] = "Neues Spielzeug: %s"
L["Achievement: %s"] = "Erfolg: %s"
L["%s quests completed"] = "%s Quests abgeschlossen"
L["Reached %s gold"] = "%s Gold erreicht"
L["%s: skill %d"] = "%s: Skill %d"
L["Learned %s"] = "%s gelernt"
L["This session"] = "Diese Session"
L["Time"] = "Zeit"
L["Experience"] = "EP"
L["Levels"] = "Level"
L["Killing blows"] = "Todesstöße"
L["Deaths"] = "Tode"
L["Gold"] = "Gold"
L["Distance"] = "Strecke"
L["Character"] = "Charakter"
L["Level"] = "Level"
L["Time played (since Chronicle)"] = "Spielzeit (seit Chronicle)"
L["Time played (/played)"] = "Spielzeit (/played)"
L["Days played"] = "Spieltage"
L["Sessions"] = "Sessions"
L["Longest session"] = "Längste Session"
L["Fastest level"] = "Schnellstes Level"
L["Average per level"] = "Schnitt pro Level"
L["Quests completed"] = "Abgeschlossene Quests"
L["Experience earned"] = "EP gesammelt"
L["Experience from quests"] = "EP aus Quests"
L["Exploring"] = "Erkunden"
L["Zones discovered"] = "Entdeckte Gebiete"
L["Favourite zone"] = "Lieblingsgebiet"
L["Dungeons seen"] = "Besuchte Dungeons"
L["Dungeon runs"] = "Dungeon-Runs"
L["Combat"] = "Kampf"
L["Rare elites killed"] = "Getötete Rares"
L["Bosses defeated"] = "Besiegte Bosse"
L["Deadliest foe"] = "Gefährlichster Gegner"
L["Travel"] = "Unterwegs"
L["On foot"] = "Zu Fuß"
L["Riding"] = "Reitend"
L["Swimming"] = "Schwimmend"
L["Flight paths"] = "Flugrouten"
L["Jumps"] = "Sprünge"
L["Gold and loot"] = "Gold und Loot"
L["Gold now"] = "Gold jetzt"
L["Most gold at once"] = "Meistes Gold auf einmal"
L["Gold earned"] = "Gold eingenommen"
L["Gold spent"] = "Gold ausgegeben"
L["Uncommon items"] = "Grüne Items"
L["Rare items"] = "Blaue Items"
L["Epic items"] = "Epische Items"
L["Collections"] = "Sammlungen"
L["Mounts"] = "Mounts"
L["Pets"] = "Pets"
L["Toys"] = "Spielzeuge"
L["Achievements"] = "Erfolge"
L["Counted since %s."] = "Gezählt seit %s."
L["Online now"] = "Gerade online"
L["What they did"] = "Was sie erlebt haben"
L["Your friends' level-ups, deaths, quests, new zones, dungeons, bosses, rares, epic loot, mounts and milestones show up here, and when they come online. They need an up-to-date LefthyTools for most of it."] =
	"Hier erscheinen Level-Ups, Tode, Quests, neue Gebiete, Dungeons, Bosse, Rares, epischer Loot, Mounts und Meilensteine deiner Freunde, und wann sie online kommen. Für das meiste brauchen sie ein aktuelles LefthyTools."
L["Completed %s"] = "%s abgeschlossen"
L["Came online"] = "Ist online gekommen"
L["Went offline"] = "Ist offline gegangen"
-- Chronicle graphs
L["Graphs"] = "Grafiken"
L["Last 14 days"] = "Letzte 14 Tage"
L["+%s XP, %s per hour"] = "+%s EP, %s pro Stunde"
L["Not enough data yet: check back in a few minutes."] = "Noch zu wenig Daten: Schau in ein paar Minuten nochmal rein."
L["Time per level"] = "Zeit pro Level"
L["Fastest: %d (%s), slowest: %d (%s)"] = "Am schnellsten: %d (%s), am langsamsten: %d (%s)"
L["Level up once with Chronicle on to see this."] = "Steig einmal mit Chronicle ein Level auf, dann siehst du das hier."
L["Favourite zones"] = "Lieblingsgebiete"
L["Deadliest foes"] = "Gefährlichste Gegner"
L["No deaths yet."] = "Noch keine Tode."
L["On the road"] = "Unterwegs"
L["Loot by quality"] = "Loot nach Qualität"
L["(friend)"] = "(Freund)"
L["Last 7 days"] = "Letzte 7 Tage"
L["You"] = "Du"
L["You and %s, last 7 days"] = "Du und %s, letzte 7 Tage"
L["Latest news"] = "Neueste Ereignisse"

-- A friend's level-up with no message of their own: shown in your language
L["{name} reached level {level}!"] = "{name} hat Level {level} erreicht!"

-- Party chat announcements (party members read these, so they follow the client language too)
L["%s: quest complete!"] = "%s: Quest erledigt!"
