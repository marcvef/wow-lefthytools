# Testing

## Automated (`npm test`)

`npm install` once, then `npm test` (about 2 minutes), or a part of it (below). `tests/run.js`:

1. reads the file list from the TOC, checks that every file it names exists (XML too) and each
   Lua file's syntax as Lua 5.1 (luaparse);
2. checks translations: every `L["..."]` used in code has a German entry and every German entry is
   used (comment lines are ignored);
3. checks that `LT.FILES` in `Core/Core.lua` matches the TOC's files and saved variables (it
   prints the value to set after adding or removing a file), and that `Update-LefthyTools.cmd`
   is the current build of `install.ps1` (`npm run build-installer` regenerates it);
4. runs the addon in fengari (Lua 5.3) against `tests/mock.lua`, which fakes the WoW API: once as
   an English client (the files below), once as German (`tests/test_de.lua`, which also fails
   on formal terms, translated module names and runtime translation fallbacks) and once for
   WoW: Forever's release (`tests/release.lua`, below). The German and release suites need nothing
   of the English one, so each runs in a process of its own (`node tests/run.js --side <job>`,
   with the sources the main run read at its start) while the English suite runs; their output is
   printed after the English suite's, in that order, and the first suite that fails ends the run
   (exit code 1), as if they ran one after the other.

The mock runs OnUpdate only on visible frames, like the game, and animation groups with
`SetToFinalAlpha(true)` jump to their end state on `Play()`. It does not replace testing in game.

Where the time goes: almost all of it is the English suite's `Advance` steps (OnUpdate scripts and
timers, 60 steps per simulated second), most in `echoes_net.lua` (its clients), `beacon.lua`,
`echoes_capture.lua` and `chronicle.lua`. So `Advance` goes only over the frames that ever had an
OnUpdate (in the order they were made, as going over every frame would) and looks at the timers
only once one is due. run.js's `load` compiles a source text once per Lua state and loads it
again from its bytecode (the same function, a new closure), since the addon is loaded once per
client and fengari's compiler is slow. The suite's files can't be split over processes: they share
the clock, the world and `math.random` (seeded by `echoes_pages.lua`; before that fengari's is
random, so e.g. Beacon's item rolls in `beacon.lua` differ from run to run), so each file's
results depend on everything before it.

What Lua can't fake comes from Node (`tests/native.js`, put into each Lua state before mock.lua):
`C_EncodingUtil` with Node's real zlib and Base64, so Echoes' pages really round-trip, and
`MOCK_EXPORTER(text)`: the Echoes exporter's own readers on a saved file's text, when the
environment variable `ECHOES_EXPORTER` names the exporter's folder (`echoes_pages.lua` then checks
that it archives every page byte for byte with matching hashes; without it that check is skipped).

### The English suite

One Lua state, in the order `ENGLISH` in `tests/run.js` lists the files. `tests/helpers.lua` loads
the addon like the client does (TOC order, then `ADDON_LOADED`, `PLAYER_LOGIN`,
`PLAYER_ENTERING_WORLD`) and returns the shared helpers; each test file is then a chunk of its own
and gets that table as `...`. After the last file, helpers.lua's `Finish()` makes the last checks
(nothing reached the error handler, no secret kept as a table key or in saved variables, no
global leaked) and prints the count. The files share the mock's clock and world: each goes on
from where the one before left time, Beacon's friends, saved variables and open windows.

| File | What it tests | Needs before it |
|---|---|---|
| `core.lua` | version, module framework, error catcher, Core's helpers, map art, which client (beta or release) | (runs first) |
| `mirage.lua` | the idle fade, reveals, controller UI, minimap quest areas, settings, Mirage off | - |
| `tweaks.lua` | Misc Tweaks: AFK screen, bags, quest progress, combo points, retail frames, new quests, quests on maps, aggro tags | - |
| `beacon.lua` | Beacon: maps, sharing, updates, alerts, pings, level-ups, items, LTC, reports, switching off | - |
| `stream.lua` | Beacon's fight stream | `beacon.lua` (the clock) |
| `flights.lua` | Misc Tweaks: cinematic flights | - |
| `chronicle.lua` | Chronicle | `beacon.lua` (what happened there) |
| `levelup.lua` | Misc Tweaks: the level-up window | - |
| `bestiary.lua` | Bestiary | - |
| `whatsnew.lua` | Core: the what's new window | - |
| `echoes.lua` | Echoes: the module, its saved table, events and driver, recording only off the beta; the line encoder | - |
| `echoes_capture.lua` | Echoes' capture: the path (store rule, travel modes, segments), every event kind's line, secrets, combat, a `/reload`, a whole session read back | - |
| `echoes_pages.lua` | Echoes: pages (header, joining, closing, 10 minutes while a friend who takes pages early is online, `/reload`, stale pages, a crash: my pages offered to everyone once on disk, and the logout it didn't write; none closing while the capture waits after a loading screen; a page number used twice: moved, closing above; one that went only early: moved by a safe summary or a relay's holdings, not by a collector's), packing and its fallbacks, what's kept (and what collectors hold of a store, 60 days after it was last heard of), the API for the delivery (my pages not on disk yet going early; a collector's provisional pages: not served, not safe, confirmed by the same hash; when a page came), the receipt (only what the exporter read, its `upto`; provisional pages taken aside; its `early`: never exported, nothing dropped for it; an older exporter; a store it didn't read; the latest arrival kept after the inbox emptied), the launch day, `/lefthy echoes` (how far my recording is safe and when pages ended, what waits; a collector's line per friend: names, counts, up to when, many friends, old ones, broken saved fields), with the capture running; the exporter reading them (a provisional page too) | - |
| `echoes_net.lua` | Beacon's B family; Echoes' delivery: messages, ranges, who gets B (the first build with Delivery), serving within the budget, back-off, collecting, relaying, safe ranges, the probe, switching off; a holder's line (one place per friend, collectors first), page starts not taken, what a relay asks for with many friends, silent holders, bounds on answers and safe summaries, what keeps a store's safe entry, a friend Battle.net lists late, long range lists, a hello right after an answer, a hand-edited saved file; three clients (author, relay, collector) and an older build; an author's crash with the collector online at her next session (her pages close above the lost one's number, never confirmed); two relays and reloads mid-page; a collector who records, a full inbox, 120 pages within the budget; many relays at once spreading over an author's pages; a page of mine moving while I serve it; a WTF folder restored from a backup, and one folder on two computers played by turns (every page reaches the collector, each under one number); early pages to a collector online (provisional: not safe, not served, told only to the author; checked by its start and confirmed after her `/reload`; 10-minute pages; both sides' `/lefthy echoes` along the way, friends' names); an author's crash with the collector offline at her next session (the check shows another hash, the receipt takes the provisional page aside, the other page is fetched: both reach the exporter, nothing is dropped before it's safe); two collectors on one PC sharing the exporter's receipt (a number it has only early is no one's exported); a WTF folder restored while the new page went early to a collector who then crashes (moved, both pages kept); a page that went only early, checked after the author's `/reload` by its start alone or with a part (out, dropped once safe, not moved), and moved by a relay's holdings of its number; a collector's crash right after receiving; early pages and older builds (no `ea`, `en`); a collector's `ea` and checks with friends played by the test (one that stops collecting no longer tells an author its provisional pages); a full inbox (no `e`: one hello each way) | - (its clients are its own) |
| `fixed_errors.lua` | Beacon's error reports already fixed: matching a report's error line (where it happened too), versions (the fix's build, dirty builds, unknown ones), the line each build gets (older ones LTC, newer ones `B2;bf`), once per friend, fix and day, not in my fight or theirs, a friend who updated since, a German report, collecting off, receiving `B2;bf` | `beacon.lua` |
| `settings_window.lua` | LefthyTools' settings window: pages, every kind of row, saved values staying where they are, search, opening in a fight and in gamepad mode, Blizzard's page; changed settings (the dot, the button back for every kind of row, not for a module's switch), a page's reset (asking first, forgetting the question, a module's own reset), "New" tags (none on an install or for players from before, a later build's settings, seen when the page opens, not by a search) | - |
| `gamepad_symbols.lua` | Misc Tweaks' controller symbols: what's set per controller, nothing but the symbols, the default undoing it, not in a fight, a controller connected later, the command | - |
| `ltc_tabs.lua` | LTC's chat tabs: the main window by default, chosen tabs, nothing lost, a closed tab, flashing, the checkbox on Blizzard's page, the command, the colour | `beacon.lua` |
| `recipes_data.lua` | `Data/Recipes.lua`'s shape: the lines, every recipe's fields and reagents, known recipes, names in both languages | - |
| `recipes.lua` | Chronicle's recipes: the data, the lists' encoding, the scan in steps and when it runs, what goes out and when (a skill change sends no list), older builds get none, broken messages, the caps, the setting, pruning and a character with only recipes, `R.People`, `R.Search`, `R.Crafters`; "Craftable by" in item tooltips (`R.Makers` built on the tick, order, names, "+N more", reagents with Shift, kept per revision, new data, the setting, other tooltips); several clients: a friend gets my list, a third friend gets it relayed while I'm offline, only friends of that account | - (its clients are its own) |
| `professions.lua` | Chronicle's Professions tab, with a fake `C.Recipes` (the last section: the real one's data, when it's loaded): the row of tabs, defaults, people, groups and sorting, difficulty, details and the real tooltip, search, gathering, empty states, pools, what's redrawn, names coming in, in a fight, the fallback (last in the suite's order) | - |
| `ltc_more.lua` | LTC: a line that mentions me (case, words of their own, links left alone, the flash, the sound, a tab out of sight, my own lines, the setting); lines a friend missed while offline (kept by the writer and by friends who got them, passed on after an offer and its answer, paced, marked with their time, links rebuilt, shown once when two friends bring them, only from the friend's own friends, 50 per friend, 24 hours, yesterday's); /ltc who (the call, the links, answers changing, answers from friends not asked, the tally redrawn in place or anew, Invite all and a friend already in the group, a call missed as a plain line, the end after 15 minutes); an older build's client (without the new files) gets nothing but plain LTC lines | - (its clients are its own) |
| `margins.lua` | Chronicle's crafting margins: my recipes (the real recipe scan and data), vendor prices (the data's, a merchant's, not for other currencies), one recipe at the auction house (only with it open, what's asked, 0.65 s apart, gear by item level, none listed, no answer, the throttle, a fight), the numbers (cost, both revenues, the cut, profit, time, gold per hour, age), a full scan (one ReplicateItems read over frames, only my recipes' items kept, too soon: by items, stopped: what's left), the window (order, sorting, greyed stale prices, the details, the scan button, the auction house closed), the buttons on the profession window and the auction house, closing mid-scan, idle, the setting, pruning, secret prices | - |
| `gamepad_bags.lua` | Misc Tweaks' bags with a controller: the bag buttons' row, the sections and their order, positions and the bag's height, SmartNavigation (grid off, jumps at shorter rows, Blizzard's jump cleared, told after our moves, the cursor kept in place, jumps gone when the bag closes), the tooltip beside the bag, a fight (nothing placed or called, Blizzard's layout standing, ours after it), a collapsed bag, mouse and keyboard untouched, the setting and its command, opened in a fight | - |

Each file begins with what it tests and a `-- Needs:` line: the files that must run before it
(`-- Needs: beacon.lua, ...`, which run.js reads) or `no other file`, and why. What's left:
`stream.lua` needs `beacon.lua` only for the clock (which floating numbers are up at a check
follows from where Beacon's 0.5 s looks fall), `chronicle.lua` counts what Chronicle kept from
`beacon.lua` (my level-ups, Anna's and Bob's deaths and level-ups), and `mirage.lua` watches the
fade that begins at login, so no file that lets time pass may run before it.

**Several clients at once** (`echoes_net.lua`): each client is a game of its own inside the suite's
Lua state: `mock.lua` and the addon loaded into an environment of their own (a table as their
`_ENV`, `_G` pointing at it; Lua's libraries and functions run.js gives the state are shared), with
their own clock, Battle.net friends (`BN_FRIENDS`), BattleTag, version (`MOCK_VERSION`) and saved
variables, on the release. The harness at the top starts them (`Start`), closes them (`Stop`:
`PLAYER_LOGOUT`, the saved variables copied as the game would write them; friends see them go
offline), reloads them (`Reload`: the next session) and lets time pass for all of them in steps
(`Run`), carrying each one's `SendGameData` to the receiver's `BN_CHAT_MSG_ADDON` after every step
(and logging it). A client can leave a file out (`without`: an older build). Friends can also be
played by the test (`fake`: online, `Say` what they'd send, `Sent` what they got). Every client is
checked when it closes: no errors, no globals leaked. A client is about 0.15 s to start; three
clients for three simulated minutes take a few seconds.

### The release suite

The mock is the beta, like the game today (`MOCK_CLIENT`), so the English and German suites load
the addon on the beta. `tests/release.lua` runs in a Lua state of its own and starts the game
itself, several times (`MockReload()`, then the addon loaded again with the saved variables as
they are): a copy of the beta's saved data on the release (all four tables new, settings back to
their defaults, one chat line, what's new as on a first install), `/reload`s after it (nothing
goes), one table copied again alone, a new install, the beta and an unknown client (nothing goes),
and the beta's data back on the release.

### One module's tests

`npm test -- stream` runs steps 1-3, then helpers.lua, `stream.lua` and what its Needs line names
(`beacon.lua`), in the suite's order, and the last checks. Several names add up
(`npm test -- chronicle levelup`); `german` is the German suite (`npm test -- german`), `release`
the release's. Without names everything runs. Alone a file takes seconds (`echoes_net.lua` about a
minute, `beacon.lua`, `echoes_capture.lua` and `chronicle.lua` 10-20 s); the whole suite takes
longer than its files added up, since each `Advance` step goes over every OnUpdate made so far.
Alone a file can see other random numbers than in the whole suite (`math.random` isn't seeded
yet when `echoes_pages.lua` doesn't run before it).

### Adding a test

- Put it in the module's file, in its section or under a new `section("...")` (a heading in the
  output). Locals as usual: each file is its own chunk, far from Lua's 200.
- Take what you use from helpers.lua at the top of the file
  (`local check, section, ns, LT, lefthy = suite.check, ...`).
- Don't count on what another file left: set up what the test needs (greet the friends it talks
  to, `anna("H2")`; Beacon forgets a friend 65 s after their last message) and put back the mock
  knobs you change (`QUESTS`, `MOBS`, `STATE`, `UnitRace = ...`): later checks share them.
- Time passes for every check after yours: count the kind of message that matters
  (`sentTo(11, mark, "S2;")`), not everything sent in a window, as an added test moves the phase
  of every periodic send after it.
- A new file: add it to `ENGLISH` in run.js where it should run, with a description line and a
  `-- Needs:` line (run.js fails without them, or when a file it needs runs after it). Then
  `npm test -- <name>` must pass.

### Helpers

From helpers.lua (`suite.<name>`): `check(cond, msg)`, `near(a, b, eps)`, `a(frameName)` (its
alpha), `section(title)`; `ns`, `LT`, `lefthy` (`/lefthy`); `printedSince(mark)` (chat lines since
`PRINTED[mark]`); `sentTo(id, from, prefix)` (Beacon messages to a game account since
`GAMEDATA[from]` that start with prefix); `anna(msg)` (a Beacon message from Anna, game account 11;
Bob is 12: `Fire("BN_CHAT_MSG_ADDON", "LTBeacon", msg, "WHISPER", 12)`); `peers()`; `pinOf(id)` (a
friend's world map dot); `tooltipHas(line)`; `afk(on)`; `catchErrors()` (what reaches the error
handler meanwhile).

From the mock (globals):
- `Fire(event, ...)`; `Advance(seconds)` moves the clock in 1/60 s steps (timers, then each
  visible frame's OnUpdate).
- Which client: `MOCK_CLIENT` (`beta`, `test`, `ptr`: what `IsBetaBuild`, `IsTestBuild` and
  `IsPublicTestClient` answer; the beta by default) and `MOCK_BUILD` (`GetBuildInfo`'s build).
  `MockReload()`: a `/reload` for a suite that loads the addon itself (`release.lua`): the frames
  loaded so far get no more events or updates, timers and the settings panel are cleared, the
  saved variables stay.
- `EnterCombat()` / `LeaveCombat()`: a fight the game's way. `PLAYER_REGEN_DISABLED` comes with
  `UnitAffectingCombat` already true but `InCombatLockdown()` still false (the lockdown begins
  after that event; `Fire` keeps it so for anyone firing it); `PLAYER_REGEN_ENABLED` after the
  lockdown ends. `STATE.combat` alone: in a fight without the events.
- `SECRET`, a value the game keeps secret. Like the game's it errors on arithmetic, comparing
  (`<`, `<=`, ...; `==` only against another table), `..`, `#`, indexing, calling and `pairs`;
  `issecretvalue` and `tostring` work. Lua can't catch it as a table key, in `==` with a plain
  value, `type()`, `tonumber()` or `if secret then`: the last checks look for secrets kept as keys.
- Battle.net friends (`BN_FRIENDS`): Anna Brook (11, mage) and Bob Stone (12, warrior) online in
  WoW, Finn Hale (16) on an older LefthyTools, Carl Vale (13) offline, Dora Reed (14) in the app,
  Eve Marsh (15) in another region. As on Forever, Battle.net names carry the surname (Beacon's
  `peer.name` is "Anna Brook"); a journal keys a character by first name and realm ("Anna-Realmy").
- What happened: `PRINTED` (chat), `GAMEDATA` and `GameDataTo(id, from)` (Beacon messages),
  `SENT_CHAT`, `SOUNDS`, `BLOCKED` (protected calls in combat), `ERRORS`, `TOOLTIP`.
- Doing things: `TypeChat(text)` / `TypeChatSpace(text)` (the chat box), `OpenWorldMap(mapID)`,
  `ClickWorldMap()`, `PinsOf(template)`.
- The world: `STATE` (target, cursor, panel, bags, afk, ...), `PLAYER_POS`, `ZONE`, `MOBS`
  (nameplates), `PARTY`, `QUESTS`, `QUESTS_ON_MAP`, `MAP_RECTS`, `ITEMS`, `BAGS`, and `MOCK_*`
  knobs (`MOCK_SEND_RESULT`, `MOCK_ITEM_UNCACHED`, ...): each is described where mock.lua sets it.
- The auction house and merchants: `C_AuctionHouse` (searches answered after `AH_ANSWER_DELAY` with the
  commodity or item event, `ReplicateItems`), fed by `AH_LISTINGS`, `AH_COMMODITY`, `AH_SILENT`,
  `AH_THROTTLED`, `AH_REPLICATE_FILLER`; what was asked in `AH_SEARCHES`, `AH_REPLICATES`. `MERCHANT` (a
  merchant's window: `GetMerchantNumItems`, `GetMerchantItemID`, `C_MerchantFrame.GetItemInfo`),
  `SPELL_CAST_MS` (`C_Spell.GetSpellInfo`'s `castTime`).

## The installer (by hand)

`npm test` only checks that `Update-LefthyTools.cmd` is the current build. To try `install.ps1`
without touching your own game or remembered folder, start it in a child `powershell.exe` with
`LOCALAPPDATA` and `ProgramData` pointed at a temp folder (no remembered folder, no Battle.net
list) and make a fake game: a `...\World of Warcraft` folder with a `.build.info` (the header
`Branch!STRING:0|Active!DEC:1|Build Key!HEX:16|CDN Key!HEX:16|Install Key!HEX:16|IM Size!DEC:4|CDN Path!STRING:0|CDN Hosts!STRING:0|CDN Servers!STRING:0|Tags!STRING:0|Armadillo!STRING:0|Last Activated!STRING:0|Version!STRING:0|KeyRing!HEX:16|Product!STRING:0`
and a row per product, e.g. `eu|1|a|b|||tpr/wow|h|s|t|||1.60.1.70532||wowf`), in it `_forever_`
(an empty `Wow.exe` and a `.flavor.info` of two lines, `Product Flavor!STRING:0` and `wowf`; no
`Interface`, like the release before its first start) and/or `_classic_beta_` (`WowB.exe`,
`wow_classic_beta`, `WTF\Config.wtf`). With that folder in `-GameDir`, or a flavor folder's
path in `<temp>\LefthyTools\game-folder.txt`, `.\install.ps1` installs the checkout without
searching. Without either it searches every fixed and USB drive and finds your real game too, so
try the search only on a copy of the script whose `[IO.DriveInfo]::GetDrives()` is replaced with
fake drives (objects with a `Name` of a temp folder and `DriveType` `Fixed`). Worth a run: beta
only; release only (gets `Interface\AddOns`); both (installs into both, lists both, remembers the
release); a remembered beta with the release next to it (both, no search: a decoy beta on a fake
drive stays untouched); a remembered beta alone (only it); a remembered beta that's uninstalled
(only `Interface` left, `.build.info` without its row: the release only); `_classic_era_`
(`wow_classic_era`, 1.15.x) ignored, and `_classic_beta_` with a 2.x version too; no
`.build.info` (the known names); two betas on two drives (the newer `WTF\Config.wtf` wins);
`-GameDir` with the `World of Warcraft` folder and with one flavor folder (only that one);
`-Link`; `-Download` twice ("already the latest version" for each folder). The `.cmd` puts its
arguments inside a double-quoted `-Command`, so give it a path with spaces in single quotes
(`-GameDir 'C:\...\World of Warcraft'`). A copy of the `.cmd` outside a clone runs the newest
installer from GitHub instead.

## In game

1. `/lefthy` opens Options → AddOns → LefthyTools; module pages sit under it. Change a setting and
   close the panel with gamepad mode off (see the known issue in forever-platform.md).
2. Mirage (switch it on first): `/mirage status` lists a sensible frame count per group; 0 means a
   wrong frame name or a Blizzard module that isn't loaded (`meter` and `cooldowns` can be 0).
   On a German client `/mirage delay 1,5` says "Idle delay set to 1,5 s."
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
   blocked". `/afk`, then `/reload`: the camera doesn't keep circling. While AFK, a Beacon friend
   shows or offers an item, writes in LTC or announces something: each is listed under
   "While you were away"; after an offer, a click brings back its Need / Pass buttons.
   Cinematic flights (Misc Tweaks): take a flight path: the interface fades out, black bars come
   in (the top one lists your Beacon friends, a line each: level, zone, fighting or their quest;
   with three or more, they take turns every 8 s), "Next stop / <place> / <zone>" appears, the bottom bar says "Landing in about m:ss". Each zone
   on the way gets a card (continent, level range, friends there). Get whispered: a subtitle just
   above the bottom bar. The camera stays where you put it and can be dragged. Land: everything
   fades back. Fly the same route again: "Landing in m:ss" counts down exactly. Press M: the
   interface is back; close the map and the film returns 2 s later. The same with the settings
   (`/lefthy`) and the Chronicle window (`/chronicle`). A ready check ends it.
   A Beacon friend Ctrl+right-clicks an item while you fly: "Anna shares [item]" as a subtitle.
   They Ctrl+Shift+right-click one: the interface comes back with Need / Pass; answer, and 2 s
   later the film resumes; the winner ("[item]: Anna wins!") comes as a subtitle.
   Settings, Flights, "What a flight hides" on Chosen elements, untick Chat: on the next flight
   the ticked elements fade out (minimap included, quest areas too), chat stays, other addons stay;
   landing brings everything back at its own opacity. Try with Mirage on and off. With Mirage off
   since login, press Toggle Minimap during that film: the minimap (and its quest areas) stays
   away and is back after landing.
   Per element: set the minimap's slider to 50%: it stays half visible while the rest fades.
9. Watch for Lua errors (`/console scriptErrors 1`), especially "action blocked" taint in combat.
   `/lefthy errors` lists LefthyTools' own errors from all sessions (also with the error display
   off); `/run error("x")` from chat must *not* show up there (not ours).
10. Controller: the bar cluster and legend fade when idle; holding a trigger brings them back
    instantly; HUD mode, the radial menu and open bar flyouts keep them visible.
    Sorted bags (gamepad mode, Misc Tweaks *Sorted bags with a controller* on): open the bags. At the
    top a row of bag buttons (backpack first), below it headers (Gear, Consumables, Trade goods, Quest
    items, Other, Junk, Free slots) with the items sorted under each (best quality first; gear by item
    level). The cursor starts on the backpack's button. D-pad down: into the first section; down and up
    go row by row through the sections (no row skipped, no jump into the wrong column at a section's
    short last row); left and right along a row, wrapping at the ends; up from the first row: the bag
    buttons; up from the backpack's button: the bag menu. On a bag button: its menu (filters, clean-up,
    collapse) works; collapse a bag: its items leave the sections, expand it: they're back. Shoulder
    buttons: jump between the bag buttons (Blizzard's; no section jumps). Select an item: its tooltip
    sits left of the bags at their top, not over them; with *Compare items* on in the backpack's menu,
    gear shows the comparison next to it. With the cursor on an item: use (a potion), equip (gear),
    split a stack (More actions), pick up and drop into a free slot: all as before, no "action blocked".
    At a vendor: sell the first junk item: the cursor moves to the next junk. Loot something: it shows
    up in its section a moment later. Pull a mob with the bags open, loot or use an item in the fight:
    the bags stay as they are (no "Interface action blocked", no Lua error); after the fight they're
    sorted again. Open the bags in a fight: Blizzard's layout; after the fight ours. Switch gamepad mode
    off with the bags open: Blizzard's mouse layout, exactly as before. `/lefthy tweaks padbags off`:
    the headers go, close and open the bags: Blizzard's controller layout as before.
11. Misc Tweaks: player/target bars show `current / max` without hovering; a dragged bag reopens
    where it was left. In a party, finishing a quest objective posts `[Quest]: 10/10 ...` with a
    star icon; finishing the quest posts `quest complete!`.
    Level-up window: `/levelup` (or Settings, Misc Tweaks, Level-ups, *Preview*): the window for
    your level (the corner says "example gains" until your first real level-up, then "Your last
    level-up, once more"), with the red X at the top right next to the pin. Check the look: gold bars that
    grow, round portrait in a gold ring with a glow, the number punching in with a shine, stats
    counting up, spell icons popping in (hover: tooltip; NEW or a rank number), the class quest
    line on its level. Then level up for real: after Blizzard's banner, the real gains (Spirit
    too), the spells your trainer has (compare with the trainer: nothing you know, nothing
    missing), talent point, "Level N took ..." with Chronicle on. Level up in a fight: it waits
    until the fight is over. A fight starting closes it; Escape and the X close it; with the mouse
    on it, it stays, otherwise it goes after 25 s. No talents in the trainer's list (a paladin's
    Templar's Bulwark at 30 shows under talents instead). At 10: "Talents unlocked" with the first
    row of all three trees (hover: tree, row, points); at 15, 20, ...: the next row of the tree
    with the most points. Click the pin: it stays past 25 s; pull a mob: it goes, and comes back
    after the fight. Drag it: pinned too. The arrows: the levels before and after ("Coming up" /
    "Looking back", their spells and talent rows).
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
    Retail unit frames (`/lefthy tweaks retailframes on`): player, target, focus, target of target,
    pet and party frames in retail's art (gold trim, no level circle, the level gold at the top
    right), bars inside the frame's slots, masks shaped to them. Target a mob, an elite, a "minus"
    critter: the frame and its health bar fit each time. In combat switch targets: the bar may sit
    a pixel off until combat ends, then fits. A vehicle, a druid's forms (mana/energy/rage bars),
    `/reload` with it on. Off: a chat line asks for a /reload; after it Forever's frames.
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
    LTC: `/ltc hello` (or `/l`) shows "[LTC] [you]: hello" in your chat and theirs; their `/l`
    lines show in yours. Open the chat box again: it says "LTC:" in orange, and a plain line
    goes to LTC; `/g` (or `/s`, `/p`) switches back, a whisper doesn't. Typing `/l ` with a
    space switches at once. Shift-click an item into a `/l` line: friends get a working link. The
    same with your profession (the link on its window), a spell from the spellbook, a quest and a
    map pin (Ctrl+click the map, then Shift-click the pin): each is clickable in your line and
    theirs (the profession opens its recipe list, the pin sets the waypoint, with its icon). A
    friend's line ticks softly (once for a quick burst); untick "Soft sound for LTC": silent. `/la meet at the flight master` (or `/lefthy announce "..."`): on their screen in the
    middle (where shared items show), with the whisper sound, for 10 s; yours too.
    Error reports: switch on "Collect my friends' error reports" (Beacon settings). Your friend
    types `/lefthy report test`: their chat says "1 report(s) sent to <you>", yours "<friend> sent
    a LefthyTools error report", and `/lefthy reports` shows it with their build, language, realm,
    faction and the last links they clicked (a profession link: whether its window opened).
    A friend clicks your profession link and nothing opens: a report comes by itself with what
    their game said, their server id against yours, whether their client knows you, realm and
    faction. `/lefthy beacon status`: every friend's realm and faction next to yours.
    A friend on a build before 0.7.0-34 whose report says `ADDON_ACTION_FORBIDDEN: IsUserOAuthed()`
    (or a blocked call with Blizzard's settings panel open; before 0.7.0-38 `ADDON_ACTION_BLOCKED:
    UNKNOWN()`): out of a fight, your chat says "told <friend> the error they reported is fixed in
    ...", theirs one LTC line "LefthyTools note: the error you reported (...) is fixed in build ...
    Update with Update-LefthyTools.cmd and restart the game." (German on a German client). The same
    error again that day: nothing. Sent in a fight (yours or theirs): it comes after.
    Level-ups: `/lefthy beacon sound` to try the sounds, `/lefthy beacon ding test` for the message.
    They die: a chat line with zone and what they fought. Alt+click your world map: they get a
    rippling marker on both maps, a chat line and a sound; on a continent map the line names the
    zone under the cursor; clicking the map pin at the end of their line sets their waypoint arrow
    to the spot. Hover your own marker: "Alt+click ... to take it back"; Alt+click it: gone from
    your maps and theirs, no new ping (`/lefthy beacon ping clear` too). A plain click still
    zooms/navigates as before, also in combat.
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
    Invite: hover a friend's world map dot: "Shift+click: invite"; Shift+left click it: they get
    the game's invite, also on another realm, and chat says "Invited <them>." In your group: no line.
    Health in the stream (the fighter on this build; `/lefthy stream me` or a friend's window):
    fight a mob: your "~%" goes down with its hits and the mob's bar in a friend's window too, no
    numbers float, a dodge or miss still says so. A few seconds after the fight your "~%" jumps to
    about what you really have, and the next fight's steps fit better. Kill the same kind alone
    twice: its bar should reach about nothing as it dies. In a group, after a fight:
    `/run for _,c in ipairs(C_DamageMeter.GetCombatSessionFromType(1,0).combatSources) do print(c.isLocalPlayer,c.totalAmount) end`
    should print one line per person, `true` on yours (not tested yet; without it your health isn't set right in groups).
    Professions tab, comparing: hover gear whose slot you wear: "Replaces: <your item>" with stat
    lines as in your bags (rings and trinkets: both of yours); hover the name: its tooltip. Change
    what you wear: the lines follow. A recipe you know: "Show in my profession window" opens yours on
    that recipe, also when another profession or none was open; in a fight it only says so.
    Settings window: /lefthy opens it, also in a fight and with the controller UI; every page, a checkbox, a slider's
    drag and +/-, a dropdown, the level-up text, a button; hover a row for its text; search; Esc closes it. Saved settings as
    before after a /reload. Options > AddOns > LefthyTools has a button to it. Open Blizzard's Social and Audio pages and
    its search: no "blocked" error any more.
    Changed settings: change a checkbox, a slider, a dropdown, the level-up text: a gold dot before the name and the
    undo icon (checkbox: at the row's end; the others: left of the control); its tooltip names the default; click it:
    back, the dot goes. A module's switch never gets one. A page's foot, Reset: "Yes, reset", wait 5 s (asks again), or
    click again (all back, the module stays on). With a controller: move down a page of sliders and through the undo
    column, nothing gets stuck; press Reset twice. "New": after an update that adds a setting, its page says New in the
    sidebar and the row too until the page has been opened; a first install shows none.
    Clean-up button: with a controller none, moving through the slots stays on slots, clean-up is in the bag menu.
    With mouse and keyboard: as ever, left of the search box.
    Controller symbols: Misc Tweaks (or /lefthy tweaks padsymbols playstation): chat says /reload, the Reload button under the setting does it; after it cross,
    circle, square, triangle, buttons and sticks working; still so after a restart; in a fight it waits until
    after. Default and /reload: back. Xbox, then disconnect and reconnect the controller: it stays.
    Professions tab, finding people: search a character's name, then a BattleTag name: a People group above
    the recipes, their professions light up. Hover one: their professions on the right; click one of those: it
    opens with them selected. Settings, Beacon, Sound for LTC: each plays when picked and on friends' lines.
    LTC in its own tab: make a chat tab, right-click it, Settings, Chat page: "LTC" at the top right, ticked on the
    main tab only. Tick it on the new one and untick General: friends' lines and your own go there, /l works
    from any tab, the tab flashes behind General; then write in /g and /say to see that chat still sends, and
    log out and in: it stays. Close the tab: back in the main window. Settings, Beacon, LTC colour: lines
    and the chat box's header follow it, Cancel puts it back.
    Fight stream (both on this build): hover their world map dot: "Click: watch their fight";
    click it: their window at the top left (small; drag it, drag its bottom right corner to
    resize, a second window goes beside it); their map, their arrow turning, the mobs they fight,
    their cast and mana. On your side a tiny red dot with "1" right of the calendar button (hover:
    who). Click the dot again (or the X): closed, and your red dot goes within 12 s at most. They
    untick "Friends can watch my fights": your window closes with a chat line. Take a flight with
    "Cinematic flights" on while they fight: their stream opens by itself; the top bar has
    Watch / Live right of each friend's name; landing closes them. `/lefthy stream me`: what they
    see of you. Watch the traffic in `/lefthy beacon status` while watching (about 2 messages a
    second from them).
15. Chronicle: the book button on the minimap's edge opens and closes the journal (right-click:
    settings; drag it around the edge, it stays there after `/reload`); `/chronicle` too; the zone you're in is "discovered". Kill a few
    mobs, loot a green, turn in a quest, jump, ride: the Statistics page counts them (time and
    distance update every few seconds). Enter a dungeon: "First visit"; kill a boss: one entry.
    Die to a mob: "Died to <mob>", once (also on the Statistics page's death count). `/reload`: the
    session continues (Sessions stays). Characters go by their full name (first name and surname)
    everywhere. Log in a second character: the dropdown at the top left has one entry, "You", with
    both characters and their levels; Statistics adds both up (Characters lists each with its level,
    time AFK shows only in the Martin tracker), the Timeline has both, each line saying whose.
    Friends are in the dropdown once each, by BattleTag, with their characters (picking one opens
    their graphs, "You and <BattleTag>"). No character anywhere twice, or under its first name alone
    next to its full name: the News page has one line per event, Compare and its leaderboard a
    chip, a line and a row per character (BattleTag on a chip's hover), the Friends page a row per
    character with the BattleTag in its column. A friend's character whose journal came from an
    older build shows its first name with a grey "?" on every page (its hover, or a line under the
    News list, says when the surname comes); never a first name alone without it. When that friend
    logs in on it while you're online (any LefthyTools, or none), the "?" goes within 30 s and the
    full name shows; a third friend on this build who holds that journal gets the name from you too
    (theirs loses the "?" after their next sync).
    Graphs: "Time AFK" shows AFK time per day; a friend's page (both on this build) has an AFK tile
    and an AFK row next to yours. With a friend: their level-up
    and a highlight (e.g. a boss) appear under Friends and in chat. `/chronicle session`.
    Traffic in `/lefthy beacon status` stays at a few messages per minute while standing still.
    Friends' journals (needs two friends on this build, A and B): A plays while B is online, then
    logs off; you log in while only B is on: within a few minutes A's level, days and highlights
    show up (Friends: the "Not online" table has A with "last played", Compare has A's lines),
    although you and A were never online together. A minute after logging in a chat
    line says what friends did while you were away. Compare: chips hide and show characters, 7 / 14 /
    30 days (the leaderboard's title and numbers follow), hovering a day lists everyone's value,
    hovering a symbol only that character's moments, a click on a Hall of fame column sorts it,
    Share posts a ranking in LTC (the leaderboard's with its range). The book on
    the minimap gets a blue dot for news; the News tab shows how many. Friends: a row per friend
    online (where, doing) and per character not online (none of a friend who's online); a click on
    a row opens their graphs. First login of a week: last week's leaderboard in chat.
16. The beta or the release (architecture.md). On the beta: `/dump IsBetaBuild(), IsTestBuild(),
    IsPublicTestClient()` (note the answers: at least one should be true) and
    `/dump LefthyTools.world` says "beta"; settings, journal and Bestiary are all still there
    after a `/reload` and a restart, and no chat line about the beta comes. On the release:
    `/dump select(2, GetBuildInfo())` is 70532 or later, the three questions answer false and
    `LefthyTools.world` is "release". A new install: no chat line. With the beta's `WTF` folder
    copied over: one line "LefthyTools: data from the beta was reset; WoW: Forever starts fresh.",
    Mirage off, every setting its default, an empty journal and Bestiary, no what's-new window;
    then `/reload` and a restart: no line, and what you set since stays.
17. Chronicle's Professions tab (`/chronicle`, the leftmost tab; needs recipe lists, so log in on a
    crafter once, and on a friend's build with the same version for their lists). **The real
    tooltip first, it's what the tests can't show:**
    - Hover a piece of gear: the item's real tooltip is inside the right panel, under the name:
      armour, stats, required level, with its border. Not over the window's edge, and nothing
      shows through behind it. If it comes up beside the window instead, the fallback ran: note the
      item and tell.
    - An item with a long text (a set of stats, an "Equip:" line): wider ones are scaled to fit the panel,
      the text still readable. A very tall one is cut at the bottom and "Needs:" stays on screen.
    - A recipe not seen before this session (`/reload` first): the name comes shortly, then the tooltip
      fills in without another hover, and "Needs:" moves down.
    - An enchant: the spell's tooltip in the panel.
    - Open the Bestiary's or Beacon's tooltip lines on an item that has them: those lines show in here too
      (they're added to every item tooltip).
    - Move the window half off the screen: the tooltip stays in its place, doesn't jump. Close the
      window with a recipe clicked and open it: it's still there, tooltip too. Open the What's new window
      or a bag over it: the tooltip doesn't sit above other windows (a tooltip's usual strata would).
    - Controller: click a row (no hovering there): the details stay. No "action blocked" afterwards.

    Then the rest:
    - The tab row: seven tabs fit, "Professions" and in German "Statistiken" aren't cut or touching
      the edges; on Timeline, Statistics and Graphs the dropdown isn't overlapped.
    - Top: every profession's icon and count; the chosen one is in gold, one of yours at first.
    - People: by skill, class colours, grey line with account and level; a list older than three days says
      so. Middle: gear by slot in the sheet's order, with the highest ilvl first, slot names in the client's
      language; potions and such under their types; enchants under their categories (German on deDE);
      headers fold. Dots: compare a recipe you know with the profession window's colour for it.
    - "Needs:": the bag count changes when you loot one, red when short; a reagent hovered: its tooltip.
    - Search "leather": about 0.3 s after you stop typing; matches from all professions, who knows them;
      clear it: back where you were. A nonsense word: "No recipes found".
    - Herbalism: people and skill, "No recipes: gathering".
    - In a fight: all of it still works, no errors. Scrolling a long list (Tailoring, Everyone) is smooth,
      and standing with the tab open costs nothing noticeable (`/lefthy` has no meter: watch the frame rate).
    - Who can craft it: hover something a friend or one of your characters crafts (in the bags, at a vendor
      or the auction house, a quest reward, a chat link): "Craftable by:" with names in class colours,
      profession and skill, best first, at most three and "+N more". Hold Shift over a bag item: the
      reagents line comes within a moment (elsewhere: hover again with Shift held). An item nobody makes:
      no line. Chronicle's setting off: gone. Right after logging in the first hover may have nothing yet.
    - Crafting margins: open your profession window on a recipe that makes an item: a Margins button at the
      top right corner of the recipe (does it cover anything? with a controller, can you reach it and move
      away from it?). Click: the margins window opens right of it on that recipe, "Open the auction house to
      update the prices." Visit a trade-goods vendor: thread, flux, vials now cost what it asks (hover a
      reagent row: Vendor). At the auction house: open your profession window there (does the auction
      house stay open?), click Margins: "Checking...", a second or two, then AH prices with "just now";
      compare a reagent's price with what the auction house shows for one. The auction house's own
      Margins button opens the list; Scan all my recipes: "Asking the auction house for everything...",
      then "Reading the auction house: N of M" without a hitch in the frame rate, then the list, best
      first; Sort switches. Scan again at once: item by item ("Scanning: N of M items"); Stop, then "Go on
      (N left)". Close the auction house mid-scan: it stops. A recipe whose product sells better on the AH
      says AH under Sells. In a fight: no errors, nothing is asked until it's over.
