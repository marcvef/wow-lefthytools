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
  the player's own toggle wins.
- **Health workaround:** health can't be read, but `UNIT_HEALTH` only fires while it changes, so a
  pulse on each event ("regen hold" = 3 s, ticks come about every 2 s) keeps the player frame
  visible until full. Mana uses `UNIT_POWER_UPDATE` with `powerType == "MANA"`.
- **Fading:** per group `from/to/t/dur` with smoothstep easing. Duration scales with the distance
  to cover, so an interrupted fade takes proportionally less time.
- **Controller UI:** see [forever-platform.md](forever-platform.md); Mirage polls the "in use"
  signals.

## Ideas

- Per-group settings: faded alpha per group; keep minimap/objectives semi-visible.
- Non-goal: nameplates. They belong to WorldFrame, not UIParent, and are forbidden in instances.
