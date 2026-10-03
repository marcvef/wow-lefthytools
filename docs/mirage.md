# Mirage design

Mirage fades the default HUD when the player is out of combat and idle (like Dune: Awakening's
"Dynamic HUD"). Frame lists live in `Modules/Mirage/Groups.lua`; the engine in `Mirage.lua`.

- **Only top-level containers get faded.** Blizzard alpha-manages many children itself (party
  range fade, aura blinking, micro button states, chat tab fade). Alpha is inherited, so fading
  the parent is enough. `Rebuild()` drops any listed frame whose ancestor is also listed, which
  avoids squared alpha (e.g. docked chat tabs under `GeneralDockManager`).
- **Never fade a frame whose own alpha Blizzard animates or reads back.** The XP/rep containers
  (`Main/SecondaryStatusTrackingBarContainer`) start at XML `alpha="0"`, fade with their own
  `setToFinalAlpha` animations, and branch on `self:GetAlpha()` in
  `SetShownBar`/`FadeIn`/`FadeOut`; fading them made the XP bar disappear for good. The `xpbars`
  group therefore fades their parent `StatusTrackingBarManager` and lists the containers under
  `hover`, since Edit Mode can move them outside the parent's rect. Before adding a frame to
  `Groups.lua`, grep its module for `<Alpha` animations targeting it and for `GetAlpha()` checks.
- **Mirage multiplies instead of overwriting.** Edit Mode applies its "Opacity" settings with
  `SetAlpha` (unit frames, auras, Cooldown Manager, swing timer, personal resource display), and
  chat fades its tabs with `UIFrameFadeIn/Out`. A `hooksecurefunc(frame, "SetAlpha")` post-hook
  records anything that isn't Mirage's own call as the frame's *base* alpha; Mirage draws the
  frame at `base * groupAlpha`, guarded by an `applying` flag. A frame with a secret alpha is left
  alone until a normal `SetAlpha` arrives.
- **Animation drift safety net (`SyncBase`):** animations change alpha engine-side without
  calling `SetAlpha`, so the hook can't see them. Before every apply, if a frame's alpha differs
  from what Mirage last set (`lastSet`), the new value becomes the base. Otherwise a base captured
  mid-animation (e.g. 0) would hide the frame forever. An **enforce pass** re-applies faded alpha
  every second for the same reason.
- **Deferred work:** event handlers call `RequestEvaluate()` / `RequestRebuild()` (state only);
  the OnUpdate driver runs `Rebuild`, `Evaluate`, fades and `SyncMinimap`. "While moving" is
  polled via `IsPlayerMoving()`; `PLAYER_STARTED_MOVING` is not registered.
- Apart from the minimap (below), frames are never shown, hidden or moved, so there are no
  combat-lockdown or Edit Mode taint issues.
- **Visibility:** `Evaluate()` runs every 0.1 s. `GlobalReason()` (combat, Edit Mode, controller,
  cursor, casting, vehicle, dead, target, window, moving) refreshes `lastActivity`; everything
  stays visible until `now - lastActivity >= db.delay`. Per group, `holdUntil` handles mouseover
  linger and event pulses (chat, regen, quest, XP, zone). Condition checks are `pcall`-wrapped so
  a changed beta API reports once instead of throwing every frame.
- **Enable/disable:** `OnEnable` registers events, re-adopts frames (`Rebuild`) and starts the
  driver. `OnDisable` unregisters events and fades everything to 1; `FinishStopping` releases
  every frame to its base alpha, re-shows the minimap and removes the OnUpdate script. `SetAlpha`
  hooks can't be removed, but with no owner they only keep tracking the base alpha.
- **Minimap quest areas ("blobs")** are engine-drawn inside `Minimap` and ignore frame alpha.
  `Minimap:Set{Quest,Task,Arch}Blob{Inside,Outside,Ring}Alpha` exist and aren't protected, but have
  no getters and no defaults anywhere in Lua or XML, so they can't be restored exactly. Instead the
  minimap fades like everything else, and `SyncMinimap` hides the `Minimap` frame once the group's
  alpha reaches `db.minimapHideAt` (slider "Hide quest areas at", `/mirage overlay <0-100>`,
  default 0 in `defaults.minimapHideAt`, 0-1 scale), then shows it as soon as it fades back in.
  Only applies when `fadedAlpha == 0`. `Minimap` isn't protected, and Blizzard's `ToggleMinimap()`
  does the same Show/Hide; Mirage only re-shows a minimap it hid itself (`minimapHiddenByUs`), so
  the player's own toggle wins. A post-hook on `ToggleMinimap` catches the case where the player
  presses the key while Mirage has the minimap hidden: Blizzard then shows it (it looks hidden),
  but the player saw a faded minimap and meant "off", so the driver hides it again as the
  player's choice and clears `minimapHiddenByUs`.
- **Health workaround:** health can't be read, but `UNIT_HEALTH` only fires while it changes, so a
  pulse on each event ("regen hold" = 3 s, ticks come about every 2 s) keeps the player frame
  visible until full. Mana uses `UNIT_POWER_UPDATE` with `powerType == "MANA"`.
- **Fading:** per group `from/to/t/dur` with smoothstep easing. Duration scales with the distance
  to cover, so an interrupted fade takes proportionally less time.
- **Controller UI:** see [forever-platform.md](forever-platform.md); Mirage polls the "in use"
  signals.

- **Fade strength per element:** each group fades to its own `db.groupAlpha[key]`. The settings
  page shows each group as one row with Blizzard's `CreateSettingsCheckboxSliderInitializer`
  (checkbox = `groups[key]`, slider = `groupAlpha[key]`, greyed out while unticked;
  `Builder:CheckboxSlider`). The general "Faded opacity" (`db.fadedAlpha`) sets every group:
  `OnSettingChanged` notices it changed (`lastFadedAlpha`) and writes each group through its
  setting object, so an open page follows. Older settings are migrated once
  (`groupAlphaMigrated`): every group starts at the old `fadedAlpha`. The minimap's quest-area
  hiding needs the *minimap's* own value at 0.

## AFK screen (AFK.lua)

While the player is AFK (`UnitIsAFK("player")`; `/afk` or the auto-AFK) and Mirage is on, the
interface disappears and a panel shows the character (`PlayerModel` with `SetUnit("player")`),
time away, clock, zone, level progress and rested XP, whispers since then, friends' level-ups and
deaths while away (a `ns.Beacon.listeners` entry), Beacon friends online with level, zone and
status, and lines other modules add through `ns.MirageAFK.sections` (Chronicle's session). The
camera circles with `MoveViewLeftStart(0.03)` (setting `afkSpin`).

- **Hiding:** `UIParent:SetAlpha(0)`, restored to the previous alpha. Not `Hide()`: Hide/Show on
  UIParent is blocked in combat, SetAlpha never is, so leaving always works. The panel
  (`LefthyToolsAFKFrame`) has no parent (stays visible), sits in `FULLSCREEN_DIALOG` and takes
  mouse clicks, so nothing invisible can be clicked; a click leaves (on the next frame).
- **Leaving:** the AFK flag goes, combat, moving, typing (keyboard focus), a window or bag
  opening, death, or an event that needs the player (ready check, party invite, LFG proposal,
  trade, duel, summon, resurrect, cinematic). Leaving while still flagged AFK keeps the screen
  away until the next AFK. Not shown in combat, dead or with a window open.
- **Cost:** nothing while not AFK: the driver frame is hidden; `PLAYER_FLAGS_CHANGED` shows it
  for one check on the next frame. While the screen is up it checks 4x a second whether to leave
  and updates the texts once a second (remainder carried over, times rounded).
- **Reload mid-circle:** `db.afkSpinning` is set while the camera circles; `AFK.Enable` (Mirage's
  `OnEnable`) stops the camera if it's still set.

## Ideas

- Non-goal: nameplates. They belong to WorldFrame, not UIParent, and are forbidden in instances.
