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
