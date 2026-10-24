# Architecture

LefthyTools is one addon made of switchable modules: **Mirage** (fades the HUD when idle),
**Misc Tweaks** (small fixes), **Beacon** (Battle.net friends on the map), **Chronicle** (a
journal per character) and **Bestiary** (what mobs drop). User-facing docs are
in the [README](../README.md); this file covers how the code is organised.

## Layout

```
LefthyTools/                 the addon (copied or junctioned into Interface\AddOns)
  LefthyTools.toc            Interface 16001, SavedVariables LefthyToolsDB, LefthyToolsChronicleDB,
                             LefthyToolsBestiaryDB; every file in load order
  Bindings.xml               LEFTHYTOOLS_MIRAGE_TOGGLE, LEFTHYTOOLS_MIRAGE_PEEK (hold),
                             LEFTHYTOOLS_CHRONICLE_TOGGLE
  Core/Locale.lua            ns.L localization table (English keys, falls back to English)
  Locales/deDE.lua           German settings texts (loaded only on a deDE client)
  Core/Core.lua              module registry, saved settings, enable/disable lifecycle, versions,
                             shared helpers (secret values, combat, text, names, your own loot)
  Core/Window.lua            small movable windows (ButtonFrameTemplate): text, copy box, buttons,
                             our own popup list and dropdown (PopupList, AddPicker), minimap
                             buttons (MinimapButton), class colours, how many windows are open
  Core/MapArt.lua            a zone's map from the world map's art with what you've explored (LT.MapArt:
                             the Bestiary ledger's kill map, the fight stream's map without minimap tiles)
  Core/Errors.lua            error catcher: our Lua errors kept in LefthyToolsDB.errors, /lefthy errors
  Core/WhatsNew.lua          what's-new window after an update, /lefthy news (entries: Data/Changelog.lua)
  Core/Options.lua           settings panel (overview + one page per module), option builder, /lefthy
  Core/Options.xml           text field row for the settings list (Builder:TextInput)
  Modules/Mirage/Groups.lua  frame names per group, window list, chat events (edit to add frames)
  Modules/Mirage/Mirage.lua  engine: frame adoption + alpha hooks, visibility, fading, events
  Modules/Mirage/Options.lua settings page, /mirage, keybinding labels
  Modules/Tweaks/Tweaks.lua  Misc Tweaks: settings, the tweak list and switching, /lefthy tweaks, status text, hiding the interface
  Modules/Tweaks/Bags.lua    movable bags, the bags' clean-up button
  Modules/Tweaks/QuestAnnounce.lua  quest progress in party chat
  Modules/Tweaks/ComboPoints.lua  combo points: coloured by count, dots on the target's nameplate
  Modules/Tweaks/Aggro.lua   who has aggro, on enemy nameplates (role colours, role check); also the fight stream's tags
  Modules/Tweaks/RetailFrames.lua  retail unit frames (a tweak): retail's art and layout on
                             Forever's player, target, focus, party and pet frames
  Modules/Tweaks/ForeverQuests.lua  NEW badges for quests that are new in WoW: Forever
  Modules/Tweaks/AFK.lua     AFK screen (a tweak): interface hidden, camera circling, a panel with news
  Modules/Tweaks/FlightTime.lua  cinematic flights' time left: the route picked, flight path lengths, flights kept
  Modules/Tweaks/Flight.lua  cinematic flights (a tweak): letterbox, title cards, subtitles, friends in the bars
  Modules/Tweaks/LevelUp.lua  level-up window (a tweak): what a level brings (stat gains, trainer spells, talents, class quests), when it shows
  Modules/Tweaks/LevelUpWindow.lua  the level-up window itself: drawing, count-ups, pin, arrows
  Modules/Tweaks/QuestMap.lua  quests on continent and world maps: icons and areas (world map provider)
  Modules/Tweaks/QuestMap.xml  its world map pin templates (quest icon, quest area)
  Data/Changelog.lua         what's new: one entry per player-visible change, English and German
  Data/ForeverQuests.lua     generated list of those quests (tools/update-forever-quests.ps1)
  Data/FlightPaths.lua       generated length of every flight path (tools/update-flight-paths.ps1)
  Data/ClassSpells.lua       generated trainer spells per class and level (tools/update-class-spells.js)
  Data/SpellSchools.lua      generated magic school of the class spells (tools/update-spell-schools.js)
  Data/MinimapTiles.lua      generated minimap tile file IDs (tools/update-minimap-tiles.js)
  Data/RetailUnitFrames.lua  generated retail unit frame atlases (tools/update-retail-frames.js)
  Modules/Beacon/Beacon.lua  Beacon: transport (rate limiter, queues), finding friends, receiving, the tick
  Modules/Beacon/Protocol.lua  every message kind, B.Parse, highlights
  Modules/Beacon/Sharing.lua  what I tell friends about myself (state, quest, progress, level-ups)
  Modules/Beacon/Updates.lua  a friend's newer build, the what's-new exchange
  Modules/Beacon/Options.lua  Beacon's settings page, /lefthy beacon
  Modules/Beacon/Dots.lua    dot look, tooltip, world map provider, minimap pins
  Modules/Beacon/Ding.lua    level-up messages and the on-screen toast
  Modules/Beacon/Alerts.lua  death alerts
  Modules/Beacon/Pings.lua   map pings: Alt+click, markers on both maps
  Modules/Beacon/Items.lua   showing and offering items (Need / Pass, the roll)
  Modules/Beacon/Handover.lua  tooltip reminder for won items until traded or mailed
  Modules/Beacon/Chat.lua    LTC, LefthyTools chat (/ltc, /l) and announcements (/lefthy announce)
  Modules/Beacon/Reports.lua error reports to friends who collect them (/lefthy report, /lefthy reports)
  Modules/Beacon/Stream.lua  fight stream: asking the game, the test, /lefthy stream
  Modules/Beacon/StreamHealth.lua  fight stream: health, estimated (yours and the mobs')
  Modules/Beacon/StreamSense.lua  fight stream: what's around you (learning mob directions)
  Modules/Beacon/StreamBattle.lua fight stream: the battle row (the one shown and the mobs they fight)
  Modules/Beacon/StreamMoments.lua fight stream: what happens to them in a window (numbers, loot, the fight's line)
  Modules/Beacon/StreamView.lua   fight stream windows (yours, the preview, friends')
  Modules/Beacon/StreamMap.lua    fight stream: the map under a window's radar
  Modules/Beacon/StreamPreview.lua fight stream: the preview's made-up fight
  Modules/Beacon/StreamNet.lua    fight stream between friends (kind O), the being-watched dot
  Modules/Beacon/StreamButton.lua the spyglass minimap button: friends to watch
  Modules/Beacon/Beacon.xml  world map pin templates (friend dot, ping)
  Modules/Chronicle/Chronicle.lua  Chronicle: recording, statistics, session, /chronicle
  Modules/Chronicle/Live.lua       friends live through Beacon: highlights (E2), days (D2/K2), the feed
  Modules/Chronicle/Characters.lua  who is who: accounts, names, matching; characters, accounts, news
  Modules/Chronicle/Sync.lua       friends' journals passed on between friends (kind J)
  Modules/Chronicle/Recap.lua      in chat: catch-up, weekly recap, sharing; the leaderboards
  Modules/Chronicle/Canvas.lua     the pages' drawing kit: pooled canvas (bars, lines, text), cards, tables
  Modules/Chronicle/Graphs.lua     the Graphs page (yours, a friend's)
  Modules/Chronicle/Compare.lua    the Compare page: everyone in every graph, leaderboard, hall of fame
  Modules/Chronicle/Window.lua     the journal window (timeline, statistics, graphs, friends)
  Modules/Chronicle/MinimapButton.lua  the book button on the minimap's edge
  Modules/Bestiary/Bestiary.lua    Bestiary: the module, shared helpers, reading records (LefthyToolsBestiaryDB), /bestiary
  Modules/Bestiary/Classic.lua     the classic drop database (LefthyTools_DropData), mob health
  Modules/Bestiary/Quests.lua      quest drops while questing
  Modules/Bestiary/Wishes.lua      the wish list and dry streak
  Modules/Bestiary/Recording.lua   counting kills and loot, XP and time per kill, the log
  Modules/Bestiary/Format.lua      how numbers and lines are written
  Modules/Bestiary/Cells.lua       drop cells, item tooltips
  Modules/Bestiary/Window.lua      its window (your target's drops), the minimap button
  Modules/Bestiary/Card.lua        the card beside the mouse
  Modules/Bestiary/LedgerMap.lua   the ledger's kill map
  Modules/Bestiary/Ledger.lua      the ledger: every mob, its statistics and drops, fuzzy search over mobs and items
LefthyTools_DropData/        the Bestiary's classic drop database (and mobs' health, for the fight stream), an add-on of its own (load on demand), GPL v3
  Drops.lua                  generated (tools/update-drop-data.js); LICENSE.md, COPYRIGHT.md, README.md
tests/                       fengari (Lua VM in JS) harness, see testing.md
tools/update-forever-quests.ps1  regenerates Data/ForeverQuests.lua from wago.tools
tools/update-flight-paths.ps1    regenerates Data/FlightPaths.lua from wago.tools
tools/update-class-spells.js     regenerates Data/ClassSpells.lua from wago.tools (node)
tools/update-spell-schools.js    regenerates Data/SpellSchools.lua from wago.tools (node)
tools/update-minimap-tiles.js    regenerates Data/MinimapTiles.lua from wago.tools (node)
tools/update-retail-frames.js    regenerates Data/RetailUnitFrames.lua from wago.tools (node)
tools/wago.js                    shared by the four node tools above: latest Forever build, tables (CSV, --cache), arguments
tools/update-drop-data.js    regenerates LefthyTools_DropData/Drops.lua from a classic world DB dump (node)
tools/build-installer.js     builds Update-LefthyTools.cmd from install.ps1 (npm run build-installer)
install.ps1                  installer/updater: players (download from GitHub) and devs (checkout, -Link)
Update-LefthyTools.cmd       players' one-file installer: batch header + install.ps1 (generated)
```

## Installing, updating, versions

`install.ps1` is both the players' installer/updater and the dev installer:

- **Players** double-click `Update-LefthyTools.cmd`, a standalone copy of `install.ps1` that can
  be passed around on its own, or run
  `irm https://raw.githubusercontent.com/marcvef/wow-lefthytools/main/install.ps1 | iex`.
  The `.cmd` is a batch/PowerShell hybrid built by `tools/build-installer.js`: cmd.exe reads
  `<# :` as a label and runs only the batch header, which loads the whole file into PowerShell as
  a script block; PowerShell skips the header as a `<# ... #>` comment. The header passes the
  file's folder in `LEFTHYTOOLS_INSTALLER_DIR` (a script block has no `$PSScriptRoot`). After
  editing `install.ps1`, run `npm run build-installer`; `npm test` fails while the `.cmd` is out
  of date, and the build fails on non-ASCII text in `install.ps1` (cmd.exe reads the file in the
  console code page). Copies of an older `.cmd` keep working, they only run the code they carry.
  **It updates itself** (since 0.5.0-136; the user: "I dont want to repeatetly send them new
  installers"): started from a `.cmd` (`LEFTHYTOOLS_INSTALLER` set, not a clone, not `-Link`), it
  first fetches the newest `.cmd` (`raw.githubusercontent.com/.../<sha>/Update-LefthyTools.cmd`,
  the sha from the commits API so no CDN cache is in the way). Different: it runs that one in the
  same process (`[ScriptBlock]::Create`, the same arguments; `LEFTHYTOOLS_SELF_UPDATED` stops it
  from doing it again) and writes it over the file, but only when the batch header up to `#>` is
  the same bytes: cmd.exe re-reads the batch file by offset after PowerShell returns, so a header
  of another length would make it run garbage. Keep `HEADER` in `tools/build-installer.js` as it
  is. No GitHub: the local code carries on. Copies from before 0.5.0-136 don't have this and need
  one new file.
  With no checkout next to the script it downloads the repo:
  `api.github.com/repos/.../commits/main` for the commit, `codeload.github.com/.../zip/<sha>` for
  the files (if the API is unavailable, `zip/refs/heads/main`; git archive stores the commit id
  as the zip comment), and `compare/v<base>...<sha>` for the commit count. No GitHub releases
  and no login; unauthenticated API calls are limited to 60 per hour per IP, two per update.
- **From a clone:** installs the checkout (`-Link`: junction for live editing, `-Download`: the
  GitHub version), version from `git describe --tags --long --dirty --match v[0-9]*`.
- It finds WoW: Forever by what the game says, not by folder name. A `World of Warcraft` folder
  holds a `_name_` folder per flavor and a `.build.info`: a `|`-separated table, a header of typed
  column names (`Branch!STRING:0|...|Version!STRING:0|KeyRing!HEX:16|Product!STRING:0`, looked
  up by name) and a row per installed product. A `_name_` folder whose `.flavor.info` product
  (its second line: `wowf`, `wow_classic_beta`) has a `Version` starting with `1.6` there is
  Forever (its client line is 1.60.x; Classic Era is 1.15.x, the other flavors 2.x and up), so a
  renamed folder still counts and a reused beta name with another version doesn't. Without a
  `.build.info` (or the product in it) the known names count: `_forever_` (the release, `wowf`,
  `Wow.exe`) and `_classic_beta_` (the beta, `WowB.exe`). The game must be there (`Wow.exe`,
  `WowB.exe` or `.flavor.info`, not just a leftover `Interface`); the release has no `Interface`
  or `WTF` until its first start, so the installer makes `Interface\AddOns`.
  **Release and beta** are kinds (a product, else folder name, with `beta`, `ptr`, `alpha` or
  `test` is the beta kind, anything else the release). It installs into one folder of each kind:
  until launch everyone plays the beta and the release can't start, after it the release, so
  while both are installed one update keeps both current (the output lists both, then each
  folder's install and check). Several copies of one kind: the one played most recently (newest
  of `WTF\Config.wtf`, `Logs`, `WTF\Account`, `Cache`), the others listed.
  Where it looks: the remembered folder (`%LOCALAPPDATA%\LefthyTools\game-folder.txt`) alone
  while the game is still in it and its `World of Warcraft` folder's `.build.info` (one small
  read; without one, the known names next to it) shows no other Forever product; with one (the
  release next to a remembered beta, or the beta still next to the release), every Forever folder
  in that `World of Warcraft` folder, without searching further. It remembers the release's
  folder when there is one. Otherwise it searches the remembered folder's parent, Battle.net's
  `product.db` and common folders on every fixed and USB drive, else asks; `-GameDir` overrides
  it (a `World of Warcraft` folder: the same choice inside it; a flavor folder: only that one,
  also an unrecognised folder with an `Interface` folder). Network drives aren't searched (their
  `DriveType` is known without touching them; a disconnected one held each look for ~20 s), and
  every drive or share a candidate is on is first asked on a thread-pool task
  (`DirectoryInfo.Exists`) that gets 10 s, all drives at once, so a dead one can't hold it up;
  what was left out is listed ("Not searched: ..."). The registry's WoW path isn't used (on some
  PCs it belongs to another launcher). In each folder it replaces `Interface\AddOns\LefthyTools`
  (settings live in `WTF`, untouched) and the add-ons that come with it (`$Companions`: folders
  next to `LefthyTools/` in the repo, `LefthyTools_DropData`; checked the same way, not stamped
  with a version; a new one means "restart the game"), removes the old standalone `Mirage` addon,
  and skips the install if that exact version is already there and nothing is missing (`-Force`
  reinstalls). "/reload" or "restart the game" is said once at the end, a restart if any folder
  needs one.
- Everything runs inside a script block, so `irm | iex` in someone's PowerShell window leaves no
  variables or preference changes behind. TLS 1.2 is enabled for old Windows PowerShell setups;
  the progress bar is off (it slows downloads a lot in PowerShell 5). `.gitattributes` keeps the
  `.cmd` byte-for-byte with CRLF, also when downloaded raw.

**Versions** (Lustre style): the repo's TOC holds the base version `X.Y.Z`, tagged `vX.Y.Z`
(lightweight tag, pushed with `git push --tags`). A version exists only once it's tagged, and only
when the player who owns the project asks for one (patch for fixes, minor for features, their
call); never pick the next version number in advance. Between tags the builds are just
`X.Y.Z-N-gHASH`. The release commit bumps the TOC and gives the changelog entries since the last
tag that version; until then they have none. Between tags a build is `X.Y.Z-N-gHASH` (N commits after the
tag), written into the installed TOC by the installer; `X.Y.Z-gHASH` when N is unknown.
`LT.version` reads it, `LT.CompareVersions` orders builds, `/lefthy version` shows it, and Beacon
tells friends on older builds to update. Beacon also reports every friend's build to
`LT:NoteFriendVersion`, which keeps the newest one above ours in `LT.newerVersion`: addons can't go
online, so friends are the only source. The overview settings page has an Info section with two
read-only rows (`LefthyToolsSettingsInfoTemplate` in `Core/Options.xml`, a list element built on
`SettingsListElementMixin` whose `Init` reads the value each time the row is shown): Version, and
Updates (`Options.UpdateStatus`: newer version available / up to date compared with N friends /
unknown, no friend with LefthyTools online or Beacon off). The Updates row's tooltip is a
function (`Options.UpdateTooltip`; `Settings.InitTooltip` calls a function tooltip each time it
opens): your build, then every Beacon friend's build marked newer / same / older.

**Reload or restart:** the game reads a TOC only at startup, so an update that adds or removes
files (or saved variables) needs a restart; everything else a `/reload`. `LT.FILES`
(`Core/Core.lua`) is a hash of the TOC's file lines and `## SavedVariables` lines (SHA-1, first 8
hex digits); `npm test` fails with the right value when the TOC changed, so set it then. Beacon
sends it (`F2`) before every `V2`; `LT:NoteFriendVersion(version, files)` keeps the newest
build's files in `LT.newerFiles`, and `LT.UpdateHint(files)` words the advice: restart when they
differ from ours, `/reload` when they match, "or restart if the updater says so" when the friend's
build doesn't send them. The friend notice, `/lefthy version` and the Updates row use it.
`install.ps1` independently says "restart" when an update adds files, saved variables or a
companion add-on (comparing the installed TOC with the new one).

## Error catcher (Core/Errors.lua)

Every Lua error goes through Blizzard's handler (`Blizzard_ScriptErrors`: `HandleLuaError`, which
only Blizzard code may extend with `AddLuaErrorHandler`) to
`ScriptErrorsFrame:DisplayMessageInternal(message, messageType, stack, locals)`, also with "Show
Lua errors" off. A `hooksecurefunc` post-hook there sees each error with its stack, without
replacing the error handler. Errors whose message or stack contains `AddOns/LefthyTools/` are kept
in `LefthyToolsDB.errors` (at most 25, the same message counted instead of repeated, with the
build and first/last time), and so are `ADDON_ACTION_BLOCKED`/`FORBIDDEN` events naming
LefthyTools. Secret messages are skipped; locals are never kept (they can hold chat text). The
hook body runs in `pcall`, so it can't cause errors itself. Errors before the saved variables load
wait in a list; the first one per session prints one chat line, on the next frame (never from
inside the error handler). `/lefthy errors` shows a plain-text report (build, client, every error
newest first) in a read-only edit box to copy; `/lefthy errors clear` (or the window's Clear)
empties it; the overview's Info section shows the count, with a Show button that opens the report
while there is one (info rows take an optional `button = { text, onClick, shown }`). Core parts that aren't modules hook in through `LT.onLoad` (saved
variables ready) and `LT.onLogin`.

## What's new (Core/WhatsNew.lua, Data/Changelog.lua)

`ns.CHANGELOG` lists every change players notice: `{ id, version, module, en = { title,
sentence }, de = { title, sentence } }`, ids 1, 2, 3, ... in order; module is `mirage`, `tweaks`,
`beacon`, `chronicle`, `bestiary` or `general` (the tests check all of that, and titles stay short). The
window groups them: per version (newest first) a large gold heading with a divider, then a
section per module in a fixed order (Mirage, Misc Tweaks, Beacon, Chronicle, Bestiary, General; module
names untranslated), then each entry as a bullet with its title and, below it in grey, the
sentence; wrapped lines stay under the text. Drawn with pooled font strings (`Render`);
`WhatsNew.Text` gives the same as plain text. Ids instead of versions, because
builds between releases (`0.4.0-12-g...`) have news too. `LefthyToolsDB.changelogSeen` is the
highest id shown: a fresh install (`LT.freshInstall`: no saved variables before) starts with
everything seen, an older install without the field sees every entry once. Three seconds after
login (later if in combat) the window lists the unseen entries and marks them seen. Entries
without a version (made after the last tag) come first, under the installed build
(`LefthyTools 0.5.0-4-g1a2b3c4`); the release commit gives them the new version. "All
changes", `/lefthy news` and the overview's What's new button show the whole list. **Add an
entry, in English and German, with every change players notice.**

## Module framework (Core/)

- A module is `LT:NewModule(key, { title, description, defaults, defaultEnabled })` plus any of
  `OnInitialize` (once, `module.db` ready), `OnEnable` (at PLAYER_LOGIN if on, or when switched
  on), `OnDisable`, `BuildOptions(builder)`, `OnSettingChanged` and `OnSlashCommand(msg)`
  (`/lefthy <key> ...`). Lifecycle calls go through `pcall` + `geterrorhandler()`, so one broken
  module can't take down the others.
- **Adding a module:** create `Modules/<Name>/`, register with `ns.LT:NewModule` in its first
  file, add the files to the TOC after the Core files. It gets a switch on the overview page, a
  settings sub-page (with `BuildOptions`), saved settings and `/lefthy` routing. Keybindings go
  in `Bindings.xml` as `LEFTHYTOOLS_<MODULE>_<ACTION>` with `BINDING_NAME_...` globals.
- **Saved variables:** `LefthyToolsDB = { modules = { <key> = bool }, settings = { <key> = {...} } }`,
  plus Core's `errors` and `changelogSeen` and a few top-level keys of modules' own (data, not
  settings); Chronicle and Bestiary keep their data in `LefthyToolsChronicleDB` and
  `LefthyToolsBestiaryDB`. Core parts that aren't modules get the table through `LT.onLoad`.
  Defaults are merged on load; `defaultEnabled` only applies when no on/off choice is saved
  (Mirage defaults to off, the others to on). `LT:ResetModuleSettings(m)` resets in place,
  keeping the same tables, because the settings panel holds references to them.
- **Module switch:** single source of truth `LefthyToolsDB.modules[key]`. `LT:SetModuleEnabled`
  goes through the switch's setting object, so the overview checkbox stays in sync when a
  keybinding or slash command flips it. `LT:ApplyModuleState` is idempotent and only runs after
  `PLAYER_LOGIN`.
- `/lefthy` and `/lt`: open settings, `modules`, `enable|disable|toggle <key>`, `<key> ...`
  forwarded to the module (`OnSlashCommand`). A module's file can add a word of its own with
  `LT:AddCommand(word, run, help, after)` (`Core/Options.lua`): `/lefthy <word> ...` runs
  `run(rest)`, and `help` is its line in `/lefthy`'s list, right after the line of the word `after`
  (Beacon's `announce`, `report`, `reports` and `stream`; Core's own words are registered the same
  way). Words are registered when the file loads, so they answer while their module is off too.
  Modules may add an alias (Mirage keeps `/mirage`).
- **Shared helpers** (`Core/Core.lua`), for code in any module. One copy each: a module keeps at
  most a short local name for one (`local issecret = LT.IsSecret`, `B.CutUTF8`, `C.Ago`), never a
  copy of its own. `LT.Print(msg, source)`; secret values (forever-platform.md) with
  `LT.IsSecret(v)`, `LT.Readable(v)` (there and not a secret) and `LT.Value(f, ...)` (a call's
  first answer if the call works and the answer isn't a secret, else nil, always one value: for
  APIs that may be missing, broken or hidden); `LT.InCombat()` (the combat lockdown or the moment
  before it, inside `PLAYER_REGEN_DISABLED`; never a secret); text: `LT.CutUTF8(text, maxBytes)`
  (a byte limit cut on a whole UTF-8 letter), `LT.Decimal(text, english)` (a number's decimal
  point as the client writes it, "4,5" in German; `english` keeps the point for chat lines),
  `LT.Ago(t)` ("just now", "5 min ago", ..., localized); names with Forever's surnames in
  `LT.Names`: `First` ("Anna" of "Anna Brook" or "Anna-Realm"), `HasSurname`, `Same` (the same
  character however typed), `Mine` (my name as the game shows it, then the first name and the
  surname) and `IsMine`; `LT.SafeCall(m, method, ...)`; `LT.OwnLoot(text)` (your own loot from a
  `CHAT_MSG_LOOT` line); versions (`LT.ParseVersion`, `LT.CompareVersions`). UI building blocks
  are in `Core/Window.lua` (`LT.Window`), with `LT.Window.OpenCount()`: how many windows are open
  (Blizzard's panels, the bags, Mirage's window lists with ours), for Mirage, the AFK screen and
  flights.

## Settings panel

Blizzard's official pattern (`Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua`):
`RegisterVerticalLayoutCategory("LefthyTools")` for the overview, `RegisterVerticalLayoutSubcategory`
per module, and only the parent goes to `RegisterAddOnCategory`. Setting variables are
`LefthyTools_<module>_<id>`; module switches are `LefthyTools_module_<key>`.

Every setting the builder registers is kept in `module.settings[id]`. Code that changes a setting
(slash commands) uses `LT:SetModuleSetting(m, id, value)`, which goes through the setting object
like a click would: an open settings page shows the new value and `OnSettingChanged` runs. Writing
`m.db` directly would leave the panel showing the old value. The value is always what the db
keeps, for a `Choice` too: its slider works with positions, and the builder keeps the lookup from
value to position in `module.choices[id]` (a value that isn't one of the choices changes nothing).

The builder handed to `BuildOptions` has `Header`, `Checkbox`, `Slider`, `CheckboxSlider` (both in
one row, Blizzard's `CreateSettingsCheckboxSliderInitializer`), `Choice` (one of
`{ { value, label }, ... }` as a slider whose label names it: a proxy setting maps the db's value
to the slider's position; not a dropdown, see forever-platform.md on gamepad mode), `Button` (wraps
`CreateSettingsButtonInitializer`; its `addSearchTags` argument is asserted non-nil) and
`TextInput`. Blizzard's list has no text control, so `TextInput` uses `Core/Options.xml`'s
`LefthyToolsSettingsTextTemplate` (inherits `SettingsListElementTemplate`, mixin built on
`SettingsControlMixin`, an `InputBoxTemplate` EditBox) through `Settings.CreateSettingInitializer`.
It commits on focus loss, Escape reverts, and `SetValue` updates the box when the value changes
elsewhere (e.g. a slash command).

## Localization

- `Core/Locale.lua` creates `ns.L`, keyed by the English text; missing translations fall back to
  the key. `Locales/deDE.lua` returns early unless `GetLocale() == "deDE"` and sets
  `ns.DECIMAL_COMMA` (read by `LT.Decimal`: "1,5 s"). Both load first in the TOC.
- **Scope:** everything in the settings panel (titles, descriptions, headers, labels, tooltips,
  Mirage group labels, keybinding names) and Beacon's tooltips. Chat commands and chat output
  stay English, except texts other players or the toast show: party quest announcements and
  the default level-up message. Module keys, setting variables and command words never change.
- **German style:** write the way German WoW players talk, not Blizzard's formal translations.
  Keep the English terms players use: Interface, Minimap, Buffs/Debuffs, Cooldown Manager,
  Swing-Timer, Raid, Mouseover, Pet, HP, Damage Meter, Quest-Tracker, Unitframes, EP, Level-Up.
  **Never translate module or addon names** (Mirage, Misc Tweaks, Beacon, LefthyTools); titles
  are plain strings, not `L[...]`. `tests/test_de.lua` fails on formal terms (Minikarte,
  Oberfläche, Schlachtzug, …) and on translated module names.
- **Adding a text:** write `L["English text"]` (one literal per key, `%s` for variable parts) and
  add the German line to `Locales/deDE.lua`, under its module's heading (the blocks go in module
  order; a text several modules use sits with one of them). `npm test` fails if a used key has no
  German entry or a German entry is unused, and on any runtime fallback in the German run
  (`ns.L_MISSING`).
- **Adding a language:** `Locales/<locale>.lua` like `deDE.lua`, listed in the TOC after
  `Core/Locale.lua`.

## Rule for all modules: no frame work inside event handlers

Almost every WoW event is a `SynchronousEvent`: the engine fires it from inside its own code.
Handlers and settings callbacks only record state; frame work (alpha, Show/Hide, anchoring,
sending messages) happens on the next frame, in an OnUpdate driver or `C_Timer.After(0)`.
Blizzard's `PlayerMovementFrameFader.lua` follows the same rule. Drivers that only need to run
after a change are shown for one frame and hide themselves, so they cost nothing while idle.

A driver resets its timer before its tick, so an error in the tick can't make it run every
frame. A tick that calls other files' hooks (Beacon's, Chronicle's) calls each through
`LT.Guard(name, fn, ...)` (`Core/Core.lua`): in `xpcall`, so one that fails doesn't stop the rest
of the tick (Beacon's sending, say). Its error goes to the error handler, and so to the error
catcher with the stack where it happened, once per message and session; then that hook rests:
skipped for 1 s, twice as long each time it fails again (at most a minute), until a call works.
`LT.Guard` returns true and the hook's answers if it ran and worked, nothing if it failed, rested
or isn't there (a file not loaded: `fn` nil). It makes no garbage, so it's fine for every frame.
