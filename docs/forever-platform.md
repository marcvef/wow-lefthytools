# WoW: Forever as an addon platform

Facts verified against client builds 1.60.1.70009 and 1.60.1.70170.

## Client and API

- Forever is Classic content on the **retail (Midnight 12.x) client and API**, including Edit
  Mode, the Cooldown Manager, a built-in damage meter and swing timer, and Midnight's addon
  restrictions.
- **Mail:** the recipient is the full name, "Anna Brook"; a realm suffix doesn't work (seen on the release).
- **Controller symbols:** a config's `labelStyle` picks them; a config holding only that keeps the game's
  mappings (`docs/misc-tweaks.md`).
- **Hits and health:** `UNIT_COMBAT`'s amount has been secret since 1.60.1.70755, and addons can't read live
  health in any other way; `C_DamageMeter` gives exact totals once out of combat. `docs/beacon.md`, "When the
  game hides what a hit takes", has what was tested.
- **Friends' levels:** `C_BattleNet`'s `characterLevel` was 0 on the release (build 1.60.1.70790) and wrong
  since: the name, class and zone are right, the level isn't. Beacon's friends tell theirs themselves (`B2;bl`).
- **TOC:** `## Interface: 16001` (version 1.60.1). The flavor suffix is `_Camelot`, but a plain
  `<Addon>.toc` loads fine. The game type "camelot" is part of the **Mainline family**: in
  Blizzard TOCs `[Family]` resolves to `Mainline` and `[Game]` to `Camelot`. Frame names are the
  retail ones (`MainActionBar`, `MicroMenuContainer`, `MinimapCluster`, ...), not `MainMenuBar`.
- Install folders: the release in `World of Warcraft\_forever_` (`.flavor.info` = `wowf`,
  executable `Wow.exe`, from build 1.60.1.70532), the beta in `World of Warcraft\_classic_beta_`
  (`wow_classic_beta`, `WowB.exe`). The installer finds either by `.build.info` (docs/architecture.md),
  and LefthyTools tells them apart in game with `IsBetaBuild()` / `IsTestBuild()` /
  `IsPublicTestClient()` (`LT.WhichWorld`).
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
- The personal resource display (`PersonalResourceDisplayFrame`) shows combo points since
  1.60.1.70291: `Camelot/Blizzard_PersonalResourceDisplay.lua`'s `GetClassFrameInfo()` gives rogues
  `RogueComboPointBarTemplate` and druids `DruidComboPointBarTemplate` (before, it returned nil).
  Combo points are target-bound like Classic (`GetComboPoints("player", "target")`, Camelot's
  `TargetBoundComboPointBarMixin`) and also shown on the target frame (`ComboFrame`).

## Known client issue: hang when closing the settings panel in gamepad mode

With **gamepad mode (controller UI) enabled**, the client hangs ("not responding", no Lua error,
no crash report) when the settings panel is closed after changing an option. It happens with
every version of the addon and never with gamepad mode off; whether it also happens without any
addons is still open. With gamepad mode on, the close path goes through
`SettingsPanelMixin:OnHide` (SmartNavigation callbacks unregistered) and
`TransitionBackOpeningPanel` → `ToggleGameMenu()`. LefthyTools' settings aren't in that panel any
more (`docs/architecture.md`, Settings window), so this is only about Blizzard's own pages now.

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
popup) are blocked. LefthyTools therefore uses its own dropdown (`LT.Window.AddPicker`) and its own
settings window, never Blizzard's panel from addon code.

## The world map: never AddDataProvider or AcquirePin on WorldMapFrame

The world map is Lua (`Blizzard_MapCanvas`, `Blizzard_WorldMap`) that the controller UI runs from
Blizzard's code, so a value an addon wrote into the map's tables is run there as the addon's. Seen
as 130+ `ADDON_ACTION_FORBIDDEN: SetPreferredGamepadInteractTarget()` after closing the map with
a controller, then `SpellStopCasting`, `SpellStopTargeting`, `ClearTarget`, `TargetNearestFriend`
forbidden on B (the same chain hit Questie #7899, GatherLite #197, Offhand-DualMonitor #84):

- An addon's data provider and the pins it acquires (`AcquirePin`, `RemovePin`) write the map's
  shared state: `pinPools[template]`, the pins' scripts, `ScrollContainer.currentScale` through
  `MarkCanvasDirty`.
- In gamepad mode the map's cursor (`MapCanvasMixin:UpdateGamepadCursor` → `CheckPinDistance` over
  every pin → `currentPoIPins` → `EnterMapPin` / `ExitMapPin`) runs those pins' `OnMouseEnter` /
  `OnMouseLeave` from its own code, and keeps them in its list.
- `WorldMapMixin:OnHide` then runs tainted → `ClearBindings` → `InputBindingManager`
  (`currentCoreBindingActive` tainted) → every later `SetPreferredGamepadInteractTarget` of the
  action bars (the interact icons) is forbidden, and B runs the close chain tainted. In combat
  Blizzard's own Button pins then hit `Button:SetPassThroughButtons()` blocked.
- `Blizzard_GamepadSmartNavigation` hooks `CreateFrame`: a frame made with a parent inside an open
  panel (the map's canvas) makes it rebuild that panel's button list in the caller's code. As it
  focuses the map it takes a Button, an EditBox or a frame with an `OnMouseDown` or `OnMouseUp`
  script for a button and reads that script back (`GetScript`).

**The rule** (LefthyTools' `Core/MapOverlay.lua`, the technique Polestar uses): no data provider,
no `AcquirePin`, no hook on a map method, no map method that writes. Frames of our own are made
with no parent (`CreateFrame(type, nil, nil, template)`) and then `SetParent(WorldMapFrame:GetCanvas())`
(`SetParent` isn't hooked; the canvas clips them, they show and hide with the map). The map is only
read: `GetMapID`, `GetCanvas`, `GetCanvasScale`, `HasZoomLevels`, `GetCanvasZoomPercent`,
`GetGlobalPinScale`, `GetPinFrameLevelsManager():GetValidFrameLevel(type, index)`,
`GetNormalizedCursorPosition`, `IsCanvasMouseFocus`, the canvas's size, `GetLeft`, `GetTop` and
`GetEffectiveScale` (not `GetViewRect`, which caches). A pin's look is copied:
`scale = Lerp(start, end, Saturate(zoom)) / canvasScale * globalPinScale` (as
`MapCanvasPinMixin:ApplyCurrentScale` for `SetScalingLimits(1, start, end)`), placed with
`SetPoint("CENTER", canvas, "TOPLEFT", w * x / scale, -h * y / scale)`. One watcher frame on the
canvas compares those values each frame while the map is shown (nothing while it's closed) and
redraws on a change. None of the frames is a button to SmartNavigation: mouse motion or
`EnableMouse` with `OnEnter` / `OnLeave` only; clicks come from `GLOBAL_MOUSE_DOWN` /
`GLOBAL_MOUSE_UP` (registered while the map is open). Right-clicks pass through with
`SetPassThroughButtons("RightButton")`, protected in combat: once per frame, out of combat.

**The controller's map cursor** no longer sees these frames (it walks only the map's pins), so
the overlay looks for it: every 0.05 s while `SoftCursor:IsShown()`, the nearest frame within 12 UI
units (the map's own reach), from the cursor's `GetCenter()` times its effective scale and the
frame's map position on the canvas, shows its tooltip on a `GameTooltip`-template frame of our own
(Questie found that `GameTooltip` from there taints the gamepad UI). The controller's button stays
the map's (it zooms in or changes the zone): our frames take no controller clicks.

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
