# Architecture

LefthyTools is one addon made of switchable modules: **Mirage** (fades the HUD when idle),
**Misc Tweaks** (small fixes) and **Beacon** (Battle.net friends on the map). User-facing docs are
in the [README](../README.md); this file covers how the code is organised.

## Layout

```
LefthyTools/                 the addon (copied or junctioned into Interface\AddOns)
  LefthyTools.toc            Interface 16001, SavedVariables LefthyToolsDB; every file in load order
  Bindings.xml               LEFTHYTOOLS_MIRAGE_TOGGLE, LEFTHYTOOLS_MIRAGE_PEEK (hold)
  Core/Locale.lua            ns.L localization table (English keys, falls back to English)
  Locales/deDE.lua           German settings texts (loaded only on a deDE client)
  Core/Core.lua              module registry, saved settings, enable/disable lifecycle
  Core/Options.lua           settings panel (overview + one page per module), option builder, /lefthy
  Core/Options.xml           text field row for the settings list (Builder:TextInput)
  Modules/Mirage/Groups.lua  frame names per group, window list, chat events (edit to add frames)
  Modules/Mirage/Mirage.lua  engine: frame adoption + alpha hooks, visibility, fading, events
  Modules/Mirage/Options.lua settings page, /mirage, keybinding labels
  Modules/Tweaks/Tweaks.lua  Misc Tweaks: status text, movable bags, quest announcements
  Modules/Tweaks/ComboPoints.lua  combo points on the personal resource display
  Modules/Tweaks/ForeverQuests.lua  NEW badges for quests that are new in WoW: Forever
  Data/ForeverQuests.lua     generated list of those quests (tools/update-forever-quests.ps1)
  Modules/Beacon/Beacon.lua  Beacon: protocol, rate limiter, friend tracking, settings, /lefthy beacon
  Modules/Beacon/Dots.lua    dot look, tooltip, world map provider, minimap pins
  Modules/Beacon/Ding.lua    level-up messages and the on-screen toast
  Modules/Beacon/Beacon.xml  world map pin template (LefthyToolsBeaconPinTemplate)
tests/                       fengari (Lua VM in JS) harness, see testing.md
tools/update-forever-quests.ps1  regenerates Data/ForeverQuests.lua from wago.tools
install.ps1                  installer/updater: players (download from GitHub) and devs (checkout, -Link)
Update-LefthyTools.cmd       double-click wrapper for players: runs the current install.ps1 from GitHub
```

## Installing, updating, versions

`install.ps1` is both the players' installer/updater and the dev installer:

- **Players** run it through `Update-LefthyTools.cmd` (double-click; the `.cmd` never changes: it
  runs `irm https://raw.githubusercontent.com/marcvef/wow-lefthytools/main/install.ps1 | iex`) or
  that one-liner. With no checkout next to the script it downloads the repo:
  `api.github.com/repos/.../commits/main` for the commit, `codeload.github.com/.../zip/<sha>` for
  the files (if the API is unavailable, `zip/refs/heads/main`; git archive stores the commit id
  as the zip comment), and `compare/v<base>...<sha>` for the commit count. No GitHub releases
  and no login; unauthenticated API calls are limited to 60 per hour per IP, two per update.
- **From a clone:** installs the checkout (`-Link`: junction for live editing, `-Download`: the
  GitHub version), version from `git describe --tags --long --dirty --match v[0-9]*`.
- It finds WoW: Forever (`World of Warcraft\_classic_beta_`) via a remembered path
  (`%LOCALAPPDATA%\LefthyTools\game-folder.txt`), Battle.net's `product.db`, then common folders
  on every drive, else asks; `-GameDir` overrides it. It replaces `Interface\AddOns\LefthyTools`
  (settings live in `WTF`, untouched), removes the old standalone `Mirage` addon, and skips the
  install if that exact version is already there (`-Force` reinstalls).
- Everything runs inside a script block, so `irm | iex` in someone's PowerShell window leaves no
  variables or preference changes behind. TLS 1.2 is enabled for old Windows PowerShell setups;
  the progress bar is off (it slows downloads a lot in PowerShell 5). `.gitattributes` keeps the
  `.cmd` byte-for-byte with CRLF, also when downloaded raw.

**Versions** (Lustre style): the repo's TOC holds the base version `X.Y.Z`, tagged `vX.Y.Z`
(lightweight tag, pushed with `git push --tags`). Bump the patch for fixes, the minor for
features, then tag that commit. Between tags a build is `X.Y.Z-N-gHASH` (N commits after the
tag), written into the installed TOC by the installer; `X.Y.Z-gHASH` when N is unknown.
`LT.version` reads it, `LT.CompareVersions` orders builds, `/lefthy version` shows it, and Beacon
tells friends on older builds to update.

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
- **Saved variables:** `LefthyToolsDB = { modules = { <key> = bool }, settings = { <key> = {...} } }`.
  Defaults are merged on load; `defaultEnabled` only applies when no on/off choice is saved
  (Mirage defaults to off, the others to on). `LT:ResetModuleSettings(m)` resets in place,
  keeping the same tables, because the settings panel holds references to them.
- **Module switch:** single source of truth `LefthyToolsDB.modules[key]`. `LT:SetModuleEnabled`
  goes through the switch's setting object, so the overview checkbox stays in sync when a
  keybinding or slash command flips it. `LT:ApplyModuleState` is idempotent and only runs after
  `PLAYER_LOGIN`.
- `/lefthy` and `/lt`: open settings, `modules`, `enable|disable|toggle <key>`, `<key> ...`
  forwarded to the module. Modules may add an alias (Mirage keeps `/mirage`).

## Settings panel

Blizzard's official pattern (`Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua`):
`RegisterVerticalLayoutCategory("LefthyTools")` for the overview, `RegisterVerticalLayoutSubcategory`
per module, and only the parent goes to `RegisterAddOnCategory`. Setting variables are
`LefthyTools_<module>_<id>`; module switches are `LefthyTools_module_<key>`.

Every setting the builder registers is kept in `module.settings[id]`. Code that changes a setting
(slash commands) uses `LT:SetModuleSetting(m, id, value)`, which goes through the setting object
like a click would: an open settings page shows the new value and `OnSettingChanged` runs. Writing
`m.db` directly would leave the panel showing the old value.

The builder handed to `BuildOptions` has `Header`, `Checkbox`, `Slider`, `Dropdown`
(`{ { value, label }, ... }` via `Settings.CreateControlTextContainer`), `Button` (wraps
`CreateSettingsButtonInitializer`; its `addSearchTags` argument is asserted non-nil) and
`TextInput`. Blizzard's list has no text control, so `TextInput` uses `Core/Options.xml`'s
`LefthyToolsSettingsTextTemplate` (inherits `SettingsListElementTemplate`, mixin built on
`SettingsControlMixin`, an `InputBoxTemplate` EditBox) through `Settings.CreateSettingInitializer`.
It commits on focus loss, Escape reverts, and `SetValue` updates the box when the value changes
elsewhere (e.g. a slash command).

## Localization

- `Core/Locale.lua` creates `ns.L`, keyed by the English text; missing translations fall back to
  the key. `Locales/deDE.lua` returns early unless `GetLocale() == "deDE"` and sets
  `ns.DECIMAL_COMMA` (used by `LT.Options.Seconds`: "1,5 s"). Both load first in the TOC.
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
  add the German line to `Locales/deDE.lua`. `npm test` fails if a used key has no German entry or
  a German entry is unused, and on any runtime fallback in the German run (`ns.L_MISSING`).
- **Adding a language:** `Locales/<locale>.lua` like `deDE.lua`, listed in the TOC after
  `Core/Locale.lua`.

## Rule for all modules: no frame work inside event handlers

Almost every WoW event is a `SynchronousEvent`: the engine fires it from inside its own code.
Handlers and settings callbacks only record state; frame work (alpha, Show/Hide, anchoring,
sending messages) happens on the next frame, in an OnUpdate driver or `C_Timer.After(0)`.
Blizzard's `PlayerMovementFrameFader.lua` follows the same rule. Drivers that only need to run
after a change are shown for one frame and hide themselves, so they cost nothing while idle.
