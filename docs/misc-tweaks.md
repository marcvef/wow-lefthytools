# Misc Tweaks design

`Modules/Tweaks/Tweaks.lua` holds a list of independent tweaks (`TWEAKS`), each with an
`apply(on)` function, a setting and a slash command word. `Reconcile()` compares what's wanted
(module enabled and the tweak's setting on) with what's active, and runs on the next frame via
`C_Timer.After(0)`. All tweaks default to on.

## statusText: always show health and power values

Sets the CVars `statusTextDisplay = "NUMERIC"` and `statusText = "1"`, exactly what Blizzard's
Options > Interface > Status Text does (`Blizzard_SettingsDefinitions_Frame/Interface.lua`).
TextStatusBar shows the text permanently when `GetCVar(self.cvar) == "1"` and `textLockable`; the
player, target, pet, party and focus bars use `cvar = "statusText"`. The previous CVar values are
stored in `savedStatusText` and restored when switched off. **Don't use `bar:SetForceShow()` or
write fields on Blizzard bars:** health is secret in Forever, and a tainted field read makes
Blizzard's secret comparisons in `UpdateTextStringWithValues` error.

## movableBags

Blizzard re-anchors every shown bag in the global `UpdateContainerFrameAnchors()` (open/close,
bank, panel layout); a `hooksecurefunc` post-hook re-applies saved positions. Drag handles: the
bag frame itself and the title bar's invisible router button (child with
`routeToSibling == "PortraitButton"`, from `ContainerFramePortraitButtonRouterTemplate`), which
opens the bag menu on mouse down; dragging closes that menu (`Menu.GetManager():CloseMenus()`).
Positions are stored per bag key (`combined` / `bag<id>`) as TOPLEFT in UIParent units
(`GetLeft() * GetScale()`), because Blizzard rescales bags. `SetUserPlaced(false)` keeps the
client layout cache out of it. Moving is skipped in combat if the frame is protected.

A gamepad sort button was tried and dropped: controller mode already has "Clean Up Bags" in the
backpack's menu (`Gamepad_SetupMenuOptions`), and `ContainerFrameMixin:UpdateSearchBox()` hides
`BagItemAutoSortButton` in gamepad mode, where `GamepadBagBar` covers its spot.

## questAnnounce: quest progress in party chat

Modelled on Questie's `Modules/QuestieAnnounce.lua`: an objective is announced only when it goes
from unfinished to finished, prefixed with the `{rt1}` star icon. `questState[questID]` holds
`complete` plus per-objective `finished` (`C_QuestLog.GetQuestObjectives`/`IsComplete`), rescanned
0.3 s after quest events (`QUEST_LOG_UPDATE`, `QUEST_WATCH_UPDATE`, `UNIT_QUEST_LOG_CHANGED`, …).
New quests are added silently (already done on first sight or at login = no news). Known quests
are re-read by ID, so collapsed quest log headers don't hide progress; a quest is dropped when
`GetLogIndexForQuestID` returns nil. Completing the last objective sends one
`L["%s: quest complete!"]` line instead. Channel: `PARTY`, or `INSTANCE_CHAT` in an instance group;
nothing solo or in a raid. Sent via `C_ChatInfo.SendChatMessage`; messages queue while
`C_ChatInfo.InChatMessagingLockdown()` is true, retried every second (no event when it ends).
These lines go through `L` because party members read them.

## comboPoints: combo points on the personal resource display (ComboPoints.lua)

The personal resource display has no class resource in Forever (see
[forever-platform.md](forever-platform.md)). We add our own child row instead of touching its
`ClassFrameContainer` (Blizzard's `UpdateFrameHeight` / `UpdateAdditionalBarAnchors` read it).

- **Placement:** centred TOP to the display's BOTTOM, `GetBarPadding()` + 2 apart. Blizzard sizes
  the frame's height to the visible bars (`UpdateFrameHeight`), so hidden health/power bars are
  handled for free, and its width to the Edit Mode bar width (`UpdateBarWidth`); the row shrinks
  (`SetScale`) when the bars are narrower than the points. A `HookScript("OnSizeChanged")` on the
  display and `EDIT_MODE_LAYOUTS_UPDATED` re-lay it out. As a child it moves, scales, hides and
  fades (Mirage) with the display.
- **Data:** `GetComboPoints("player", "target")` (target-bound, as `ComboFrame` reads them), max
  `UnitPowerMax("player", Enum.PowerType.ComboPoints)` (up to 10). A secret value hides the row.
  `UNIT_POWER_FREQUENT` fires for every energy tick, so only `powerToken == "COMBO_POINTS"`
  schedules a redraw. Rogues always; druids when their power type is energy (Cat Form).
- **Look:** retail's `RogueComboPointTemplate` rebuilt in Lua (Camelot doesn't load
  `RogueComboPointBar.xml`): 20 px points, 2 px gaps; layers `uf-roguecp-bg-shadow`, `-bg-dis`
  (empty socket), `-bg` (lit socket and glow), `-icon-red` (gem), `-fx-red` (spend burst),
  `-frame-glow`, `-slash-red` (43x43 flipbook, 3x6 grid, 17 frames, 0.57 s). Gain and spend
  animations copy the timings of `unchargedEmptyToUnchargedFull` / `unchargedFullToUnchargedEmpty`.
  At full points every gem's frame glow breathes (BOUNCE 0.15-0.7, 0.6 s). The first draw, a row
  coming back (shapeshift) and new sockets don't animate. If
  `C_Texture.GetAtlasInfo("uf-roguecp-icon-red")` fails, the classic target-frame gems are used
  (`Interface\ComboFrame\ComboPoint`: socket 0-0.375, gem 0.375-0.5625, shine 0.5625-1 with ADD,
  like `ComboPointTemplate`) at 1.25x with the same logic.
- **Colour by count** (`comboColors`, its own tweak entry): green (0.15, 1, 0.15) at one point →
  yellow (1, 0.9, 0) → red (1, 0.1, 0.05) at full, over `(points - 1) / (max - 1)`. The art is red,
  so the coloured layers are `SetDesaturated(true)` + `SetVertexColor`d; empty socket and shadow
  keep their look. A desaturated red gem is dark grey and vertex colours can't exceed 1, so
  `IconBoost`, an ADD-blended copy of the gem with the same tint and alpha animation, brightens
  it; glows/burst/slash switch to ADD while tinted; the plain gem and lit socket get their tint
  lifted 25% towards white (`LIGHTEN`). Recoloured before the gain animation plays; at 0 points
  the colour stays for the burst.

## foreverQuests: mark quests that are new in WoW: Forever (ForeverQuests.lua)

- **Which quests:** the client has no flag for them (no quest tag, classification or Camelot UI
  marker; Camelot only overrides titles with levels). `Data/ForeverQuests.lua` lists them,
  generated by `tools/update-forever-quests.ps1` from wago.tools exports of the clients' `QuestV2`
  table (one row per quest that owns a completion bit). Two lists:
  - `FOREVER_QUEST_IDS`, new in Forever: in Forever's table, not in Classic Era's, ID >= 86000
    (about 1,800). The ID floor drops the few low IDs missing from Era's table that are original
    Classic quests (3382, 8193, 8249).
  - `LATER_CLASSIC_QUEST_IDS`: in both tables with ID >= 10000 (about 1,050). Original Classic's
    quests all have IDs below 10000; Era's client also carries the content added since (Season of
    Discovery, Hardcore, Anniversary: IDs 55296 to 91889), and so does Forever's. Players never saw
    those in original Classic, and some are given out in Forever, so they get the marker too. The
    first version marked only the first list, and players met unmarked quests they didn't know.

  Both get the same marker; the tooltip line tells them apart ("New in WoW: Forever" or "Not in
  the original Classic"). `ns.IsForeverQuest` is the first list only (Chronicle counts those).
  Forever builds are listed under a beta product on wago.tools (version 1.60.x); the script picks
  the newest one. Regenerate the lists when Forever gets new builds. Stored as comma-separated IDs
  and ranges, parsed on first use. Caveat: quests without a completion bit aren't in `QuestV2`, so
  a few new quests may be missing.
- **Marker:** a coloured `NEW_CAPS` ("NEW", "NEU" on German clients) right after the quest's name,
  as part of the title text. A first version put a glowing badge left of the quest log titles; it
  covered the icon there and wasn't in the quest details, so it was replaced.
- **Quest log:** Forever uses the Mainline quest log (`QuestMapFrame`, title buttons from
  `QuestScrollFrame.titleFramePool`, template `QuestLogTitleTemplate`). A post-hook on
  `QuestLogQuests_Update` appends the marker to each new quest's `button.Text`. Blizzard sizes the
  entry (`8 + button.Text:GetHeight()`) before the hook runs, so the marker is only appended if
  `GetNumLines()` stays the same; otherwise our own small label goes to the right end of the entry,
  in front of the track checkbox, where Forever never shows the quest type icon
  (`QuestUtilsOverrides.questTagIconHidden`). Blizzard rewrites every title on each update and the
  hook re-marks the pooled buttons right away; switching off strips the marker. Each title button
  gets one `HookScript("OnEnter")` that adds "New in WoW: Forever" (or "Not in the original
  Classic (from its later seasons)") to the quest tooltip.
- **Quest details and quest window:** a post-hook on `QuestInfo_Display` (it fills the shared
  `QuestInfoTitleHeader` for the log details and the quest window's accept and reward pages; the
  quest is `C_QuestLog.GetSelectedQuest()` or `GetQuestID()`) and a `HookScript("OnShow")` on
  `QuestFrameProgressPanel` (its own `QuestProgressTitleText`) append the marker. These titles
  may wrap: the elements below are anchored to them.
- Not marked (yet): the gossip/greeting quest lists of NPCs with several quests, and the
  objective tracker.

## afkScreen: the AFK screen (AFK.lua)

While the player is AFK (`UnitIsAFK("player")`; `/afk` or the auto-AFK), the
interface disappears and a panel shows the character (`PlayerModel` with `SetUnit("player")`),
time away, clock, zone, level progress and rested XP, whispers since then, friends' level-ups and
deaths while away (a `ns.Beacon.listeners` entry), and lines other modules add through
`ns.AFKScreen.sections` (Chronicle's session). The camera circles with `MoveViewLeftStart(0.03)`
(setting `afkSpin`). Beacon friends (up to 5, by name) get up to three lines each, all from what
Beacon already knows (nothing extra is sent): name (`<AFK>` from Battle.net), level and level
progress, "In your group"; zone - subzone (`B.WhereText`) and distance and direction
(`B.DistanceText`); and what they're doing: dead/ghost or fighting X (and N more, from `C2`), and
their tracked quest with its progress or "Ready to turn in", in or out of combat.

- **Hiding:** `UIParent:SetAlpha(0)`, restored to the previous alpha. Not `Hide()`: Hide/Show on
  UIParent is blocked in combat, SetAlpha never is, so leaving always works. The panel
  (`LefthyToolsAFKFrame`) has no parent (stays visible), sits in `FULLSCREEN_DIALOG` and takes
  mouse clicks, so nothing invisible can be clicked; a click leaves (on the next frame).
- **Leaving:** the AFK flag goes, combat, moving, typing (keyboard focus), a window or bag
  opening, death, or an event that needs the player (ready check, party invite, LFG proposal,
  trade, duel, summon, resurrect, cinematic). Leaving while still flagged AFK keeps the screen
  away until the next AFK. Not shown in combat, dead or with a window open. Switching the tweak
  (or Misc Tweaks) off clears that, so the next AFK after switching it on shows it again.
- **History:** it started as part of Mirage; `M:OnInitialize` moves a saved `afkScreen`/`afkSpin`
  from Mirage's settings once. It reuses Mirage's window lists (`ns.MirageData`) to tell whether a
  window is open, which works with Mirage off too.
- **Cost:** nothing while not AFK: the driver frame is hidden; `PLAYER_FLAGS_CHANGED` shows it
  for one check on the next frame. While the screen is up it checks 4x a second whether to leave
  and updates the texts once a second (remainder carried over, times rounded).
- **Reload mid-circle:** `db.afkSpinning` is set while the camera circles; `AFK.Enable` (the tweak being
  applied at login) stops the camera if it's still set.
