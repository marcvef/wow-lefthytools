# Testing

## Automated (`npm test`)

`npm install` once, then `npm test`. `tests/run.js`:

1. reads the file list from the TOC and checks each Lua file's syntax as Lua 5.1 (luaparse);
2. checks translations: every `L["..."]` used in code has a German entry and every German entry is
   used (comment lines are ignored);
3. checks that `Update-LefthyTools.cmd` is the current build of `install.ps1`
   (`npm run build-installer` regenerates it);
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
9. Watch for Lua errors (`/console scriptErrors 1`), especially "action blocked" taint in combat.
10. Controller: the bar cluster and legend fade when idle; holding a trigger brings them back
    instantly; HUD mode, the radial menu and open bar flyouts keep them visible.
11. Misc Tweaks: player/target bars show `current / max` without hovering; a dragged bag reopens
    where it was left. In a party, finishing a quest objective posts `[Quest]: 10/10 ...` with a
    star icon; finishing the quest posts `quest complete!`.
12. New Forever quests: in the quest log, a coloured NEW right after the name of quests from new
    Forever content (e.g. the Skyborne start), none on old Classic quests, and no icon covered;
    hovering adds "New in WoW: Forever" to the tooltip. Open the quest: NEW after the title in the
    details. Accept and turn one in: NEW after the title in the quest window. A very long title
    shows NEW at the right end of its entry instead (no overlap with the next entry).
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
    Level-ups: `/lefthy beacon sound` to try the sounds, `/lefthy beacon ding test` for the message.
    Traffic in `/lefthy beacon status` stays at a few messages per minute while standing still.
