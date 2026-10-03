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
L["Modules"] ="Module"
L["Settings: LefthyTools > %s"] = "Einstellungen: LefthyTools > %s"

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
L["Opacity of faded elements. 0% hides them completely."] =
	"Deckkraft ausgeblendeter Elemente. Bei 0 % sind sie komplett unsichtbar."

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
L["Also hide minimap quest areas"] = "Questgebiete auf der Minimap auch ausblenden"
L["Quest areas on the minimap ignore transparency, so the minimap is hidden once it has faded out. Only applies with 0% faded opacity."] =
	"Questgebiete auf der Minimap ignorieren Transparenz, deshalb wird die Minimap ganz versteckt, sobald sie ausgeblendet ist. Gilt nur bei 0 % Deckkraft (ausgeblendet)."
L["Hide quest areas at"] = "Questgebiete verstecken bei"
L["Minimap opacity at which the minimap and its quest areas are hidden during the fade-out. 0% waits until the fade has finished."] =
	"Deckkraft der Minimap, bei der Minimap und Questgebiete beim Ausblenden versteckt werden. Bei 0 % erst, wenn das Ausblenden fertig ist."

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
L["WoW: Forever adds over a thousand quests to the Classic world. They get a NEW right after their name: in the quest log (hover for details), in the quest details and in the quest window when you accept or turn one in."] =
	"WoW: Forever bringt über tausend neue Quests in die Classic-Welt. Sie bekommen ein NEU direkt hinter ihrem Namen: im Questlog (Mouseover für Details), in den Questdetails und im Questfenster beim Annehmen und Abgeben."
L["New in WoW: Forever"] = "Neu in WoW: Forever"
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
L["In your group"] = "In deiner Gruppe"
L["Dead"] = "Tot"
L["Ghost"] = "Geist"
L["In combat"] = "Im Kampf"
L["Fighting %s"] = "Kämpft gegen %s"
L["Right next to you"] = "Direkt bei dir"
L["%d yd %s"] = "%d m %s" -- the German client says Meter for yards
L["north"] = "nördlich"
L["north-east"] = "nordöstlich"
L["east"] = "östlich"
L["south-east"] = "südöstlich"
L["south"] = "südlich"
L["south-west"] = "südwestlich"
L["west"] = "westlich"
L["north-west"] = "nordwestlich"

-- A friend's level-up with no message of their own: shown in your language
L["{name} reached level {level}!"] = "{name} hat Level {level} erreicht!"

-- Party chat announcements (party members read these, so they follow the client language too)
L["%s: quest complete!"] = "%s: Quest erledigt!"
