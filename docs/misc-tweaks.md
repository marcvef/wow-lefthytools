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
    Discovery, Hardcore, Anniversary: IDs 55296 to 91354), and so does Forever's. Players never saw
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

## questMap: quests on continent and world maps (QuestMap.lua)

Blizzard's world map draws the quests in your log on zone maps only
(`MapUtil.ShouldMapTypeShowQuests` is false for World, Continent and Cosmic): `QuestDataProvider`
an icon per quest, `QuestBlobDataProvider` the area ("blob") of the selected (super-tracked),
hovered or focused quest. On a continent map it shows only the selected quest's icon, on the world
map nothing. A `MapCanvasDataProviderMixin` provider on `WorldMapFrame` adds them, per zoom level:
`questMapContinent` and `questMapWorld` ("off", "icons", "areas", "both"; default both) and
`questMapZone` ("blizzard", or "areas": every quest's area), and `questMapClick` (a checkbox). The
choices are `Builder:Choice` sliders (no dropdowns, see forever-platform.md).

- **Which quests, where:** `C_QuestLog.GetQuestsOnMap(zone)` for every zone on the shown map
  (`C_Map.GetMapChildrenInfo(map, Zone, true)`), the same list the zone map draws; each spot is
  carried over with the zone's rectangle on the shown map (`C_Map.GetMapRectOnMap`, kept per pair:
  maps don't move). If a map has no direct rectangle on the shown one (a zone on the world map),
  it's composed through its parents. A zone reports quests of zones inside it (a city) too, with
  that map's `mapID`: those are taken from the inner zone only. Filters as Blizzard's
  `ShouldShowQuest`: no map indicator, world or bonus quests; with a quest's details open
  (`QuestMapFrame_GetFocusedQuestID`) only that one. The selected quest's icon is left out on
  continent maps (Blizzard draws it there), its area on zone maps. The map's own filter (CVar
  `questPOI`, "quest objectives") switches everything off, like Blizzard's.
- **Icons:** pins from `LefthyToolsQuestMapPinTemplate` (QuestMap.xml), Blizzard's art from
  `POIButton.lua` at 80%: `UI-QuestPoi-QuestNumber` (`-SuperTracked` for the selected quest) behind
  `Quest-In-Progress-Icon-yellow` or `UI-QuestIcon-TurnIn-Normal`; frame levels
  `PIN_FRAME_LEVEL_ACTIVE_QUEST` / `_SUPER_TRACKED_QUEST`. Icons that would cover each other are
  spread with Blizzard's `WorldMapPOIQuantizerMixin` (75 cells high, as on zone maps). Tooltip:
  title (with level and difficulty colour through `SetQuestTitleLevelAndDifficultyColor`, as the
  map's options say), zone, unfinished objectives or "Ready to turn in". With icons only, hovering
  one draws its area until the mouse leaves, and the selected quest's area is always drawn (zone
  maps show it too).
- **Clicks** (`questMapClick`, on): a left click does what `POIButtonMixin:OnClick` does on zone
  maps: select the quest (`C_SuperTrack.SetSuperTrackedQuestID`, tracked with
  `C_QuestLog.AddQuestWatch` if it wasn't), unselect the selected one (`ClearAllSuperTracked`),
  Shift-click on a tracked quest stops tracking it, and with the chat box open the quest link goes
  in (`ChatFrameUtil.TryInsertQuestLinkForQuestID`); then the map redraws on the next frame. The
  template takes clicks (`enableMouse`, so `AcquirePin` wires `OnMouseUp` to `OnClick`, which calls
  `OnMouseClickAction`); `OnAcquired` sets `OnMouseClickAction` and `SetMouseClickEnabled` from
  the setting, so with it off clicks reach the map and it zooms in. Right-clicks pass through
  (`SetPassThroughButtons("RightButton")` in `CheckMouseButtonPassthrough`, once and only out of
  combat: it's protected in combat). **Not in gamepad mode:** the controller's button calls
  `ClickHoveredPins` from `WorldMapMixin:GamepadMapClick`, which then navigates the map; our action
  running inside it would leave that navigation (and the pins it acquires, with protected
  `SetPassThroughButtons`) tainted, so there the pins take no clicks and the button zooms in.
- **Areas:** the engine draws quest blobs into a `QuestPOIFrame` for one `uiMapID` (`SetMapID`,
  `DrawBlob(questID, true)`), filling the frame. `LefthyToolsQuestAreaPinTemplate` is one, set up
  like Blizzard's `QuestBlobPinMixin` (blob textures, fill 128, border 192); each zone with quests
  gets its own, set to that zone, sized to the zone's rectangle on the canvas
  (`DenormalizeHorizontalSize`) and centred on it. No mouse.
- **Cost:** nothing while the map is closed: the provider registers its events (`QUEST_LOG_UPDATE`,
  `QUEST_POI_UPDATE`, `QUEST_WATCH_LIST_CHANGED`, `SUPER_TRACKING_CHANGED`, `CVAR_UPDATE`) in
  `OnShow` and drops them in `OnHide`. While it's open an event queues one redraw 0.5 s later; a
  burst of events makes one. A redraw asks each zone once (about 25 on a continent).
- **Unverified in game:** whether `QuestPOIFrame` draws a zone's blob correctly in a frame that
  small, and how thick the border looks there (`SetBorderScalar`).

## afkScreen: the AFK screen (AFK.lua)

While the player is AFK (`UnitIsAFK("player")`; `/afk` or the auto-AFK), the
interface disappears and a panel shows the character (`PlayerModel` with `SetUnit("player")`),
time away, clock, zone, level progress and rested XP, whispers since then, friends' news while
away (a `ns.Beacon.listeners` entry: level-ups, deaths, and, because their notices are hidden with
the interface, items shown or offered, Lefthy chat lines and announcements, the text cut at 90
bytes; the newest 6), and lines other modules add through
`ns.AFKScreen.sections` (Chronicle's session). The camera circles with `MoveViewLeftStart(0.03)`
(setting `afkSpin`). Beacon friends (up to 5, by name) get up to three lines each, all from what
Beacon already knows (nothing extra is sent): name (`<AFK>` from Battle.net), level and level
progress, "In your group"; zone - subzone (`B.WhereText`) and distance and direction
(`B.DistanceText`); and what they're doing: dead/ghost or fighting X (and N more, from `C2`), and
their tracked quest with its progress or "Ready to turn in", in or out of combat.

- **Hiding:** `UIParent:SetAlpha(0)` through `ns.HideInterface("afk", ...)` (Tweaks.lua, shared
  with cinematic flights: the interface comes back, to the alpha it had, only when no owner wants
  it hidden). Not `Hide()`: Hide/Show on UIParent is blocked in combat, SetAlpha never is, so
  leaving always works. The panel
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

## cinematicFlights: flights like a film (Flight.lua)

On a flight path (`UnitOnTaxi("player")`) the interface fades out over 1.5 s (`ns.HideInterface`
with a fade: an OnUpdate only while fading), thin black letterbox bars (5% of the screen each) fade in,
and a title card in the upper middle names where you're going: header "Next stop", the place in
the quest font (`Fonts\MORPHEUS.TTF`, 46, shadowed), a thin gold line, the zone below. Every new
zone on the way (`ZONE_CHANGED_NEW_AREA`) gets a card: the continent (walking `parentMapID` up
to a continent map) as header, the zone name, and below its level range (`C_Map.GetMapLevels`,
when known) and the Beacon friends who are in that zone (Battle.net `areaName`). Cards fade in,
hold, fade out and drift slightly closer (one animation group, `SetToFinalAlpha`). The bottom bar
shows the time left to landing; whispers, Battle.net whispers and party chat show as subtitles
just above it, over the picture (the last two, 8 s each; secret texts are skipped). The camera is
left alone (a first version pulled it back and circled; that was removed).

- **Destination:** a post-hook on `TakeTaxiNode(slot)` (the flight map and the old taxi window
  both call it) keeps `TaxiNodeName(slot)` ("Sentinel Hill, Westfall"). The zone you take off in
  gets no card of its own. After a `/reload` mid-flight the current zone's card stands in.
- **Time left:** the game doesn't tell. The same hook reads the taxi map (`GetTaxiMapID`,
  `C_TaxiMap.GetAllTaxiNodes`): the node you're at (state `Current`) names the route ("From >
  To"), and each slot's `nodeID`. Best first:
  1. A route flown before: each flight that lands is timed (10 s to 30 min, also when the film
     was ended early) and kept per route in `LefthyToolsDB.flightTimes`; the next flight on it
     counts down exactly ("Landing in 1:42").
  2. Its length along the real flight path: the flight's legs (`GetNumRoutes(slot)`,
     `TaxiGetNodeSlot(slot, leg, isSource)`, what the old taxi window draws), each looked up as
     `"<from nodeID>><to nodeID>"` in `Data/FlightPaths.lua`, generated by
     `tools/update-flight-paths.ps1` from the client's TaxiPath / TaxiPathNode tables (waypoint
     to waypoint, 3D, plus the waypoints' Delay). Time = yards x `LefthyToolsDB.flightPathPace` +
     waits; the pace starts at 1/29.9 s per yard (measured: Undercity > Tarren Mill 4222 yd in
     141 s, The Sepulcher > Undercity 3345 yd in 112 s) and learns from landed flights within 25%
     of it (70/30 running average). Some of Forever's own paths fly faster (Tarren Mill > The
     Sepulcher, 2989 yd in 74 s): they don't move the pace, their own time is kept after one flight.
  3. Only if a leg isn't in the data: the straight distance between the two nodes
     (`C_Map.GetMapWorldSize`) at `LefthyToolsDB.flightPace` (learned the same way; 1.15/30
     before the first), shown as "Landing in about 2:10".

  Past it: "Landing any moment". Without a picked route (a `/reload` mid-flight) nothing is shown.
  The text is set only when the second changes.
- **Your camera:** the screen doesn't take clicks, so dragging the camera works as always.
  `Flight.Enable` puts back once what the first version may have left after a `/reload` mid-flight
  (`db.flightOrbit`, `db.flightZoom`, `db.flightMaxZoom`: circling, zoom, zoom limit) and drops
  those keys and the old `flightCamera` setting.
- **Pausing:** a window or bag opening (more open than the fewest this flight, from Mirage's
  window lists), typing in chat, or a friend's item offer waiting for my Need or Pass
  (`ns.Beacon.AwaitingAnswer()`: its buttons are on the hidden interface) brings the interface
  back at once; 2 s after it's closed, done or answered, the film fades back in (a zone crossed
  meanwhile gets its card then).
- **What it hides** (`flightHide`, a `Builder:Choice`): "all", the whole interface through
  `ns.HideInterface` (UIParent's alpha: other addons too), or "chosen", only the elements ticked in
  `flightGroups` (one checkbox per Mirage group, all ticked by default) through
  `Mirage:HideGroups("flight", set, fade)`, so the rest (other addons too) stays. Both are undone
  on giving back, whatever the setting says by then.
- **Beacon's item news:** the notices sit on the interface, so `Flight.Subtitle(text)` lets
  Items.lua add a friend's share ("[icon] Anna shares [item]") and an offer's outcome ("[item]:
  Bob wins!", "Nobody needs it.") to the subtitles, like whispers.
- **Leaving:** landing (`UnitOnTaxi` false; `PLAYER_CONTROL_GAINED` wakes the driver) fades
  everything back. Combat or a popup that needs you (ready check, invite, LFG, duel, summon,
  cinematic) brings the interface back at once and keeps it for the rest of that flight (the
  driver only goes on checking for the landing, to time the flight).
- **Cost:** nothing on the ground: `PLAYER_CONTROL_LOST` and `PLAYER_ENTERING_WORLD` show the
  driver, which looks for the taxi 4x a second for 3 s and hides itself. In the air it checks 4x a
  second (landing, leaving, zone cards, subtitles, the time left); the bars and cards fade by
  animation.
