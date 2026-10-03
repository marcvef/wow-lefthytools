# WoW: Forever as an addon platform

Facts verified against client builds 1.60.1.70009 and 1.60.1.70170.

## Client and API

- Forever is Classic content on the **retail (Midnight 12.x) client and API**, including Edit
  Mode, the Cooldown Manager, a built-in damage meter and swing timer, and Midnight's addon
  restrictions.
- **TOC:** `## Interface: 16001` (version 1.60.1). The flavor suffix is `_Camelot`, but a plain
  `<Addon>.toc` loads fine. The game type "camelot" is part of the **Mainline family**: in
  Blizzard TOCs `[Family]` resolves to `Mainline` and `[Game]` to `Camelot`. Frame names are the
  retail ones (`MainActionBar`, `MicroMenuContainer`, `MinimapCluster`, ...), not `MainMenuBar`.
- Install folder: `World of Warcraft\_classic_beta_` (`.flavor.info` = `wow_classic_beta`,
  executable `WowB.exe`).
- `WOW_PROJECT_ID == 1` (the retail value). Libraries that branch on Classic project IDs
  misdetect it.
- **Secret values:** `UnitHealth`, `UnitHealthMax`, `UnitHealthPercent` and `UnitHealthMissing`
  always return secrets (no arithmetic or comparisons). `UnitPower*`, `GetComboPoints` and
  `UnitCastingInfo` are secret only while restricted (power types flagged never-secret, like
  combo points, stay readable). `UnitName` can be secret (`SecretWhenUnitNameIdentityRestricted`).
  Check with `issecretvalue(v)`; `CHAT_MSG_*` payloads are secret during chat lockdown.
- **Frame API:** `SetAlpha` is *not* protected (usable on secure frames in combat, also with
  secret args); `GetAlpha`/`GetEffectiveAlpha` can return secrets; `SetAlphaFromBoolean` exists;
  `SetIgnoreParentScale` is protected.
- Removed globals: `GetItemInfo`, `GetSpellInfo`, `UnitBuff`/`UnitDebuff`, talent-tab APIs and
  more. Secure snippets are broken (`loadstring_untainted` is missing).
- **SavedVariables:** early beta builds wrote but didn't load them on a fresh launch; current
  builds keep settings across restarts.
- **Controller UI** (`Blizzard_Gamepad`, `Blizzard_GamepadActionBars`, `Blizzard_GamepadTargeting`,
  all `AllowLoadGameType: camelot`) is *not* an Edit Mode system, so players can't move or resize
  it. The roots are plain UIParent children: `GamepadMainActionBarFrame` (bar cluster; its
  `PageUnit` child is dimmed to `FLYOUT_INACTIVE_ALPHA` while a flyout is open, and flyout popups
  use `SetIgnoreParentAlpha`), `GamepadPersistentInputLegend` (button prompts; Blizzard toggles
  its child groups, not the root) and `GamepadReticle` (the aiming dot). Blizzard never sets
  alpha on these roots. "In use" signals: `GamepadMode.IsHUDBindingModifierDown()`,
  `GamepadMode.IsTargetingModifierDown()` (no arg = any), and `GamepadHudMode`, `GamepadRadial`,
  `GamepadActionBarEditFrame` and the `Gamepad*Flyout` frames being shown. Poll these instead of
  registering `GamepadMode.Register*` callbacks, so addon code never runs inside Blizzard's
  execution path. `InputUtil.IsGamepadUIEnabled()` tells whether the controller UI is active.
- The personal resource display (`PersonalResourceDisplayFrame`) leaves class resources out:
  `Camelot/Blizzard_PersonalResourceDisplay.lua` overrides `GetClassFrameInfo()` to return nil.
  Combo points are target-bound like Classic (`GetComboPoints("player", "target")`) and shown on
  the target frame (`ComboFrame`).

## Known client issue: hang when closing the settings panel in gamepad mode

With **gamepad mode (controller UI) enabled**, the client hangs ("not responding", no Lua error,
no crash report) when the settings panel is closed after changing an option. It happens with
every version of the addon and never with gamepad mode off; whether it also happens without any
addons is still open. With gamepad mode on, the close path goes through
`SettingsPanelMixin:OnHide` (SmartNavigation callbacks unregistered) and
`TransitionBackOpeningPanel` → `ToggleGameMenu()`. Workaround: change settings with gamepad mode
off, or use the slash commands.

## Gamepad mode and taint: no Blizzard menus, no panel opening from addon code

Seen as `ADDON_ACTION_BLOCKED: UnitSetRoleEnum()` (a role check's Accept, `RolePoll.lua`). In
gamepad mode the focus manager (`Blizzard_GamepadSharedUtility/FrameControlsManager.lua`) keeps
state about what's on screen, fed by `EventRegistry` callbacks that run in the caller's
execution:

- `MenuProxy.OnShow` / `OnClose` (`Blizzard_Menu`): any Blizzard menu opening. A menu opened from
  an addon's dropdown (an addon-made `WowStyle1DropdownTemplate`, or a settings dropdown with an
  addon's options) runs tainted, even though `Blizzard_Menu` calls the generator through
  `securecallfunction`: the click already read the addon's fields.
- `UIParentPanelManager.ShowUIPanel` / `HideUIPanel`: `ShowUIPanel` broadcasts it outside the
  secure delegate, so `Settings.OpenToCategory` called by addon code taints it too.

`FrameShown` returns at once unless `InputUtil.IsGamepadUIEnabled()`, so only gamepad mode is
affected. Once tainted, protected clicks routed through the manager later (gamepad confirm on a
popup) are blocked. LefthyTools therefore: uses its own dropdown (`LT.Window.AddPicker`), shows
choices in settings as named sliders (`Builder:Choice`, a proxy setting), and in gamepad mode
`LT:OpenSettings` prints the way through the game menu instead of opening the panel.

## Getting the real UI source

The community mirror has a `forever` branch matching the live build (`version.txt`):

```
git clone --depth 1 --branch forever --filter=blob:none https://github.com/Gethe/wow-ui-source
```

`Interface/AddOns/Blizzard_APIDocumentationGenerated/*.lua` lists every function and event with
flags such as `IsProtectedFunction`, `SecretReturns`, `SecretWhenUnit...Restricted` and
`SecretArguments`. Grep it before relying on any API. A blobless clone fetches file contents on
demand, so a repo-wide `git grep` is slow; check out the folders you need with
`git sparse-checkout` instead.

## Sources

- https://wowforeverbuilds.com/news/what-the-wow-forever-beta-breaks-for-addons-secret-health-values-dead-secure-sni
- https://realmlist.org/resources/guides/wow-forever-beta-addons-what-works/
- https://github.com/Adaptvx/Interaction/pull/95 (Interface 16001, `_Camelot` TOC, `WOW_PROJECT_ID`)
- https://github.com/Spotnick2/Apotheca/issues/3 (removed APIs, SavedVariables)
- https://github.com/Gethe/wow-ui-source/tree/forever
