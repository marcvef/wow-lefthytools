# Testing

## Automated (`npm test`)

`npm install` once, then `npm test`. `tests/run.js`:

1. reads the file list from the TOC and checks each Lua file's syntax as Lua 5.1 (luaparse);
2. checks translations: every `L["..."]` used in code has a German entry and every German entry is
   used (comment lines are ignored);
3. checks that `LT.FILES` in `Core/Core.lua` matches the TOC's files and saved variables (it
   prints the value to set after adding or removing a file), and that `Update-LefthyTools.cmd`
   is the current build of `install.ps1` (`npm run build-installer` regenerates it);
4. runs the addon in fengari (Lua 5.3) against `tests/mock.lua`, which fakes the WoW API: once as
   an English client (`tests/test.lua`) and once as German (`tests/test_de.lua`, which also fails
   on formal terms, translated module names and runtime translation fallbacks).

The mock runs OnUpdate only on visible frames, like the game, and animation groups with
`SetToFinalAlpha(true)` jump to their end state on `Play()`. It does not replace testing in game.

## In game

1. `/lefthy` opens Options → AddOns → LefthyTools; module pages sit under it. Change a setting and
   close the panel with gamepad mode off (see the known issue in forever-platform.md).
2. Mirage (switch it on first): `/mirage status` lists a sensible frame count per group; 0 means a
   wrong frame name or a Blizzard module that isn't loaded (`meter` and `cooldowns` can be 0).
3. Wait 5 s idle: the HUD fades over 1.5 s. Hover the action bars: only they come back.
4. Pull a mob: everything is back instantly; after combat plus 5 s it fades again.
5. Edit Mode: everything visible. Change a frame's Opacity slider, close Edit Mode: the frame
   comes back at that opacity after fading.
6. Get a whisper: chat reveals for 10 s. Press Enter to type: chat stays visible.
7. Drag a spell from the spellbook: bars are visible.
8. Untick Mirage (or the toggle keybinding): everything fades back in and stays.
   AFK screen (Misc Tweaks, also with Mirage off): `/afk`: the interface goes, the camera circles, the panel shows your
   character, timer, time, XP, Beacon friends. Get whispered: it's counted. Press W: everything
   is back at once and the camera stops. `/afk` again, get attacked: back instantly, no "action
   blocked". `/afk`, then `/reload`: the camera doesn't keep circling.
   Cinematic flights (Misc Tweaks): take a flight path: the interface fades out, black bars come
   in, "Next stop / <place> / <zone>" appears, the bottom bar says "Landing in about m:ss". Each zone
   on the way gets a card (continent, level range, friends there). Get whispered: a subtitle just
   above the bottom bar. The camera stays where you put it and can be dragged. Land: everything
   fades back. Fly the same route again: "Landing in m:ss" counts down exactly. Press M: the
   interface is back; close the map and the film returns 2 s later. A ready check ends it.
   A Beacon friend Ctrl+right-clicks an item while you fly: "Anna shares [item]" as a subtitle.
   They Ctrl+Shift+right-click one: the interface comes back with Need / Pass; answer, and 2 s
   later the film resumes; the winner ("[item]: Anna wins!") comes as a subtitle.
   Settings, Flights, "What a flight hides" on Chosen elements, untick Chat: on the next flight
   the ticked elements fade out (minimap included, quest areas too), chat stays, other addons stay;
   landing brings everything back at its own opacity. Try with Mirage on and off.
   Per element: set the minimap's slider to 50%: it stays half visible while the rest fades.
9. Watch for Lua errors (`/console scriptErrors 1`), especially "action blocked" taint in combat.
   `/lefthy errors` lists LefthyTools' own errors from all sessions (also with the error display
   off); `/run error("x")` from chat must *not* show up there (not ours).
10. Controller: the bar cluster and legend fade when idle; holding a trigger brings them back
    instantly; HUD mode, the radial menu and open bar flyouts keep them visible.
11. Misc Tweaks: player/target bars show `current / max` without hovering; a dragged bag reopens
    where it was left. In a party, finishing a quest objective posts `[Quest]: 10/10 ...` with a
    star icon; finishing the quest posts `quest complete!`.
12. New Forever quests: in the quest log, a coloured NEW right after the name of quests from new
    Forever content (e.g. the Skyborne start), none on old Classic quests, and no icon covered;
    hovering adds "New in WoW: Forever" to the tooltip. Quests you don't know from original
    Classic but from its later seasons: NEW too, the tooltip says "Not in the original Classic
    (from its later seasons)". Open the quest: NEW after the title in the
    details. Accept and turn one in: NEW after the title in the quest window. A very long title
    shows NEW at the right end of its entry instead (no overlap with the next entry).
    Quests on the map: with a few quests in the log, open the map and zoom out to the continent:
    every quest has Blizzard's icon at the spot the zone map shows, and its area sits on the right
    spot of its zone (compare one with the zone map; the outline shouldn't be much thicker). Hover
    an icon: title, zone, what's left or "Ready to turn in". Click an icon: the quest is selected
    (arrow, tracked, its area shows; Blizzard's own icon replaces ours on the continent), click
    it again: unselected; Shift-click: untracked; right-click on an icon zooms out; also in combat,
    no "action blocked". Setting "Click an icon to select its quest" off: a click zooms into the
    zone. Gamepad mode: the A button zooms in as before. Zoom out to the world map: the same, smaller. Settings, Misc Tweaks,
    Quests: "On continent maps" on Icons: no areas, hovering an icon shows its area; Areas; Nothing.
    "Quest areas on zone maps" on All quests: every quest's area on a zone map. Open a quest's
    details on the map: only that quest. The map's filter menu, quest objectives off: all gone.
13. Combo points (rogue, personal resource display on): 5 empty sockets under its bars (retail art;
    classic gems mean the `uf-roguecp` atlases are missing). Gems fill green → red with the slash
    animation; at full they breathe; a finisher bursts them out. Narrow the bars and hide the power
    bar in Edit Mode: the row follows. Switching target empties the row.
14. Beacon (needs a Battle.net friend on Forever with the same LefthyTools): within ~30 s
    `/lefthy beacon status` lists them. Their dot moves on the zone and continent map and glides on
    the minimap, in their class colour; hover shows name, BattleTag, level, zone, distance. They
    pull a mob: red pulsing ring, "Fighting <mob>". They die: skull. Rotate Minimap on: dots keep
    the right direction. Invite them: their dot gets a blue ring and sits exactly on Blizzard's
    group dot on both maps, moving along live; the tooltip says "In your group". With "Show
    friends in my group too" off, only Blizzard's dot is left.
    Updates (both on this build or newer): when one of you has a newer build, the other gets one
    notice per login that ends with "then /reload (no restart needed)" or, if that build adds
    files, "then restart the game"; the settings overview's Updates row says "(needs a game
    restart)" then. Below it, "What's coming:" and one line per change in their build
    ("Misc Tweaks: ..."), in your client's language.
    Level-ups: `/lefthy beacon sound` to try the sounds, `/lefthy beacon ding test` for the message.
    They die: a chat line with zone and what they fought. Alt+click your world map: they get a
    rippling marker on both maps, a chat line and a sound; on a continent map the line names the
    zone under the cursor. A plain click still zooms/navigates as before, also in combat.
    They track a quest: their tooltip shows it with progress within a few seconds, "Ready to
    turn in" when done, "You have this quest too" if it's in your log.
    Items: Ctrl+right-click one in your bags: they see "<you> shares [item]" at the top, one line,
    no box, and hovering it shows the item's tooltip. Ctrl+Shift+right-click: they get Need and
    Pass; once someone wins, the item's tooltip in your bags says "Won by <them>: still to hand
    over" and its slot has an orange border. At a vendor: hovering and dragging it work as usual,
    right-clicking asks "Sell it anyway?" (Keep it: nothing happens; Sell anyway: sold, border
    gone); dragging it onto the vendor warns in chat to buy it back. At a mailbox, attaching it
    fills in their name. Opening a trade with them says so in chat, and trading (or mailing) it to
    them removes the line and the border. `/lefthy beacon handover` lists what's still owed.
15. Chronicle: the book button on the minimap's edge opens and closes the journal (right-click:
    settings; drag it around the edge, it stays there after `/reload`); `/chronicle` too; the zone you're in is "discovered". Kill a few
    mobs, loot a green, turn in a quest, jump, ride: the Statistics page counts them (time and
    distance update every few seconds). Enter a dungeon: "First visit"; kill a boss: one entry.
    Die to a mob: "Died to <mob>". `/reload`: the session continues (Sessions stays). Log in a
    second character: the dropdown at the top left lists both (and friends who sent their days;
    picking one opens their graphs). With a friend: their level-up
    and a highlight (e.g. a boss) appear under Friends and in chat. `/chronicle session`.
    Traffic in `/lefthy beacon status` stays at a few messages per minute while standing still.
