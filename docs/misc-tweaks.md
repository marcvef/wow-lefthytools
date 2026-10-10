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

## gamepadBagSort: the bags' clean-up button

Since 1.60.1.70291 the bags' clean-up button (`BagItemAutoSortButton`) no longer shows, with mouse
and keyboard or in gamepad mode (seen in game; before, `ContainerFrameMixin:UpdateSearchBox`
hid it in gamepad mode only, where the gamepad bag bar, `GamepadBagBar`, offered clean-up in each
bag's menu; 70291 also stopped showing that bar on the bags). So nobody had a way to clean up. A
`hooksecurefunc` on each bag frame's `UpdateSearchBox` and a `HookScript("OnShow")` (in case that
function isn't called any more; `ContainerFrames()`: the combined bags and every
`ContainerFrameN`) show the button on the backpack or the combined bags, at the left end of the search row: where
the search box starts (Blizzard's TOPLEFT point, "x - 4, y + 3"), the search box moved right by 32 px
and made as much narrower (its width and place as Blizzard set them are told apart from ours,
`lefthyWidth` and `lefthyX`, so repeated updates don't shrink it again, and opening the bags
without Blizzard placing it again, after Alt+Z for one, doesn't move it twice). Blizzard's old spot (TOPRIGHT -9, -34) collides with something of
Forever's frame art. If the search box isn't anchored that way: left of it; without one: TOPLEFT
38, -34. Above the frame. Blizzard's click handler is untouched
(`C_Container.SortBags`). A client without `BagItemAutoSortButton` gets ours
(`LefthyToolsBagSortButton`: the `bags-button-autosort-up` atlas, the sorting sound,
`C_Container.SortBags`). Off: the search box's width and place back (also with the bags closed),
`UpdateSearchBox` again (as Blizzard has it), ours hidden and taken off the bag. The key
still says gamepad (it began there).

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

## Combo points (ComboPoints.lua): colour by count, and a dot on the target's nameplate

Since build 1.60.1.70291 Blizzard's personal resource display shows combo points itself: the
Camelot override of `GetClassFrameInfo()` builds retail's `RogueComboPointBarTemplate` (rogues) and
`DruidComboPointBarTemplate` (druids, shown in Cat Form), both with `TargetBoundComboPointBarMixin`
(`GetComboPoints("player", "target")`, updated on target and `COMBO_TARGET_CHANGED`), and retail's
`RogueComboPointTemplate` points in `classFrame.classResourceButtonTable`. Our own row under the
display (the old `comboPoints` tweak) is gone; its saved value is simply no longer read.

- **Colour by count** (`comboColors`, on): green (0.15, 1, 0.15) at one point -> yellow (1, 0.9, 0)
  -> red (1, 0.1, 0.05) at full, over `(points - 1) / (max - 1)`, on Blizzard's points. A
  `hooksecurefunc` on the display's `SetupClassBar` finds the bar, one on the bar's `UpdatePower`
  recolours after each of Blizzard's updates. The red parts (`BGActive`, `BGGlow`, `IconUncharged`,
  `FXUncharged`, `FrameGlow`, `SlashFBUncharged`) are `SetDesaturated(true)` + `SetVertexColor`d;
  the empty socket (`BGInactive`) and `BGShadow` keep their look. A desaturated red gem is dark grey
  and vertex colours can't exceed 1, so each point gets our own ADD-blended copy of the gem
  (`LefthyToolsBoost`, same tint) whose alpha follows Blizzard's `IconUncharged` for a second after
  each update (its gain and spend animations are shorter); glows, burst and slash switch to ADD
  while tinted; the plain gem and the lit socket get their tint lifted 25% towards white. At 0
  points the colour stays for the burst. Off: Blizzard's colours and blending back.
- **Nameplate gem** (`comboNameplate`, on): one gem in the personal display's look, copied from a
  point of Blizzard's bar when the display has one (`PartsFromDisplay`: every texture of the point
  with an atlas, by its key on the point, except effects: keys with FX, Slash, Glow, Charged but not
  Uncharged; its atlas, draw layer and sublevel, size and CENTER offset kept as parts of the point's
  size), so the socket with its border looks exactly like the display's; built again from the display
  once its bar exists if the gem came first. Without a bar: retail's layers (`uf-roguecp-bg-shadow`,
  `-bg-dis`, `-bg`, `-icon-red`); without those atlases: a round dot. Tinted exactly like the
  display's (gem and lit socket desaturated with the count's colour lifted 25% towards white, an
  additive copy of the gem in the full colour; the rest untouched; colouring off: Blizzard's red, no
  copy). The number (`NumberFontNormalSmall`) at its top right corner. Size and place: sliders
  `comboNameplateSize` (6-30 px, default 12; the display's are 20), `comboNameplateX` (-60..60,
  default 2) and `comboNameplateY` (-40..40, default -6: below the level's middle, clear of the
  buffs and debuffs above the bar), from LEFT at the RIGHT of `PlayerLevelDiffFrame` (Camelot's level
  box right of the health bars) when that shows, else of `HealthBarsContainer`. Moving a slider
  shows the gem on the target for 5 s (full points if there are none: `ns.PreviewComboNameplate`).
  **Trial mode** (`ns.ComboTrial`: the settings' *Try it* button, `/lefthy tweaks combopos`): a small
  window (FULLSCREEN_DIALOG, movable, Escape closes it) with a stand-in nameplate: a name, a health
  bar and a level box, at the target's nameplate's scale and level box size when there is one. The
  gem sits on it as configured (full points, coloured): drag it (follows the cursor, saved on
  release, through `LT:SetModuleSetting` so an open settings page shows it), the mouse wheel over it
  changes the size, arrow and +/- buttons nudge a pixel (also for controllers), Reset, Done. While
  it's open the target's real nameplate shows the gem too, also without points.
  Our own frame, parented to the plate's `UnitFrame` (it shows, fades and scales with it), frame
  level above the level frame (50). Only while there are points; found again on target, nameplate
  added/removed, combo and power changes (next frame). A forbidden or missing nameplate, or secret
  points: no gem.

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

## levelUp: the level-up window (LevelUp.lua)

A moment after `PLAYER_LEVEL_UP` (1.5 s, then it waits while `EventToastManagerFrame`, Blizzard's
level-up banner, is shown, at most 8 s; never in combat: `PLAYER_REGEN_ENABLED` brings it 1 s
after the fight) a window in the middle of the screen (`LefthyToolsLevelUpFrame`, `DIALOG`
strata, a child of UIParent) shows:

- **Header:** the portrait (`SetPortraitTexture`, round through `TempPortraitAlphaMask`, in a gold
  ring of two masked circles, a breathing `GarrLanding-CircleGlow` behind), "LEVEL" and the new
  level in the quest font (64), which punches in (scale 1.9 to 1) with a `challenges-bannershine`
  sweep, name in class colour, race and class, and Chronicle's `C.LevelReport(level)`: how long the
  level before took, its kills and quests, "your fastest level yet" (of at least three timed).
- **Stats gained:** health and power (`healthDelta` / `powerDelta` from the event: maximum health
  is a secret value, so only the gain), then Strength to Spirit as "old > new +gain", counting up
  one after another. The gains are the base stats (`UnitStat`'s first value) against a snapshot
  from the level before (taken when the tweak is applied, 1 s after `PLAYER_ENTERING_WORLD` and
  after each level-up), which also covers Spirit (the event has no Spirit); without a matching
  snapshot, or if the base stats haven't moved yet, the event's Strength to Intellect.
- **New at your class trainer:** `ns.CLASS_SPELLS[class][level]` (Data/ClassSpells.lua, made by
  `tools/update-class-spells.js` from the client's SkillLineAbility, SpellLevels, Talent and
  TalentTab tables on wago.tools) minus spells the player knows (`C_SpellBook.IsSpellKnown`,
  `IsPlayerSpell`), spells for other races (`CLASS_SPELL_RACES`, bit `raceID - 1`), higher
  ranks of classic talents the player doesn't have (`CLASS_SPELL_NEEDS`), and, from the live
  talent tree (below), every talent's own spell (Forever's new talents, like Templar's Bulwark,
  sit in the class skill lines too) and spells named like a talent the player doesn't have (its
  higher ranks). Icons (up to 16, 8 a row) pop
  in after the stats; new ones have a gold border and NEW above, upgrades their rank number
  (`CLASS_SPELL_RANK`); hovering shows `GameTooltip:SetSpellByID`. The generator keeps
  trainable spells (AcquireMethod 0) from level 2 and counts the starting ones (AcquireMethod 2)
  for the ranks; it leaves out talents, multi-rank talents' effects (same name), "... Effect" /
  "... Passive" spells, three talent procs without a named talent, Season of Discovery runes
  (IDs 395000-469999; Forever's own spells have new IDs) and a second spell of the same name at
  the same level (a spell and its channel). Forever adds spells of its own (Ice Lance, Penance,
  Lava Burst, ...), and they're in.
- **Talents:** Forever has classic's trees on retail's trait system: the active config
  (`C_ClassTalents.GetActiveConfigID`, else `C_SpecializationInfo.GetCombatConfigIDForSpecGroup`),
  its tree (`C_Traits.GetConfigInfo().treeIDs[1]`), one node group per talent tree
  (`C_Traits.GetGroupDisplayInfoByTreeID`: name, icon, order) with its spent points
  (`C_Traits.GetGroupCurrencyInfo`), and nodes (`GetTreeNodes`, `GetNodeInfo`: `posX`, `posY`,
  `groupIDs`, `maxRanks`, `ranksPurchased`; entries to definitions to `spellID`). A tree's rows
  are its distinct `posY`, top first; row N needs 5 * (N - 1) points in that tree, so it opens at
  level 10 + 5 * (N - 1) if every point goes there. On those levels a section shows the row's
  talents: at 10 the first row of every tree, later the new row of the tree(s) with the most
  points (none while nothing is spent), per tree its icon and name and the talents (blue border,
  the number of ranks in the corner; hover: the spell, "Talent in Fire, row 5: up to 5 points").
  Read when the window is filled, not kept.
- **Also unlocked:** talent points (the event's `numNewTalents`; "Talents unlocked" at 10), a
  class quest from a short hand-made list of classic's (`CLASS_QUESTS`: warrior stances, the
  hunter's pet, rogue poisons, shaman totems, warlock demons, druid forms, paladin Redemption, the
  60 epic mounts; "your class trainer can point you to it"), and new dungeons
  (`C_PlayerInfo.GetInstancesUnlockedAtLevel` and `GetLFGDungeonInfo`, where the client has
  them).
- **Footer:** Beacon friends with their levels (up to four, highest first) and a thin gold line
  that shrinks until the window closes by itself (25 s; it stays while the mouse is on it). It
  fades out; Escape (`UISpecialFrames`) and the X close it at once, a fight starting
  (`PLAYER_REGEN_DISABLED`) fast.
- **Pinned** (the pin next to the X, or dragging the window; closing unpins): no timer, it stays
  until closed. A fight starting hides it (`stepAside`, so it stays pinned) and it comes back 1 s
  after `PLAYER_REGEN_ENABLED`, without the intro.
- **Browsing:** the arrows beside the level (the spell book's page arrows) show what another
  level brings (2 to 60, or your level if higher): its trainer spells (all of them, known ones
  greyed out), its talent row, class quest and dungeons; no stats, except your own level with
  your last gains. The corner says "Coming up" or "Looking back". Browsing pins the window.
- It counts as an open window (`LT.Window.Register`): a cinematic flight pauses for it, Mirage
  keeps the interface up.

The last real gains are kept per character (`levelUps["Name-Realm"]`); `/levelup`, the *Preview*
button and `/lefthy tweaks levelup test` show the window for the current level with them ("Your
last level-up, once more" in the corner), or with example gains (said in the corner) when the
last level-up was to another level. They list every spell of the level, known ones greyed out.

- **Cost:** nothing until a level-up: the events only note the numbers and start a timer. The
  window's OnUpdate (fade, count-ups, the close timer) runs only while it's on screen; the glow,
  bars, punch and shine are animation groups.
- **Unverified in game:** that Forever's payload is retail's (`level, healthDelta, powerDelta,
  numNewTalents, numNewPvpTalentSlots, strength, agility, stamina, intellect`), the atlases,
  whether Forever's trainers still teach exactly what the client's tables say, and the trait
  calls on Forever's talent tree (row order by `posY`, the group IDs on the nodes).

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
with a fade: an OnUpdate only while fading), black letterbox bars (7% of the screen each) fade in
(the bars show what Beacon friends are doing, setting `flightFriends`: `B.FriendRows` per friend in
three lines, who and where, their quest, fighting or dead; three side by side in the top bar, a
fourth to sixth in the bottom one, whose time left then moves to its right end (220 px kept for
it); more than six: pages of six every 8 s; refreshed every 2 s while the film is shown),
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
  gets no card of its own. After a `/reload` mid-flight the current zone's card stands in. Landing
  (`PLAYER_CONTROL_GAINED`) drops a pick the film never used, so a flight not taken from the taxi
  map (a quest's) doesn't get the last one's name and time.
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
  window lists: Blizzard's, the settings panel, and LefthyTools' own windows such as Chronicle,
  which add themselves with `LT.Window.Register`), typing in chat, or a friend's item offer waiting for my Need or Pass
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
- **Links in subtitles** (shared items, links in Lefthy chat): the subtitles sit in a frame of their
  own (`SubtitleFrame`, `SetHyperlinksEnabled`) that takes the mouse only while a line has a link,
  so camera drags go through everywhere else. Hovering a link shows our own tooltip
  (`LefthyToolsFlightTooltip`, a `GameTooltipTemplate` on the film at TOOLTIP strata: the game's
  `GameTooltip` sits on the hidden interface); links without a tooltip (map pins) show none. A click
  pauses the film (the interface is back) and opens the link like a chat link (`SetItemRef`; an item
  with a modifier through Beacon's `B.ModifiedItemClick`: no dressing room from addon code in
  gamepad mode). In gamepad mode not `SetItemRef` at all (it opens `ItemRefTooltip` with
  `ShowUIPanel`, which from addon code taints the focus manager): an item's tooltip is shown
  directly, other links do nothing. The film waits while `ItemRefTooltip` shows (the dressing room
  counts as a window) and resumes 2 s after.
- **Friends' fight streams** (Beacon setting `streamFlights`, see beacon.md "Fight stream"): at
  takeoff (`Start`) `B.StreamFlightStart()` opens one friend's stream (the busiest, else a random
  one who can be watched); in the top bar, right of each such friend's name, a small button
  (`column.Watch`: grey dot "Watch", red dot "Live") opens or closes theirs; the windows float
  above the film (no parent, `FULLSCREEN_DIALOG`) and don't pause it. When the film ends
  (`EndFilm`), `B.StreamFlightEnd()` closes the ones opened on the flight.
- **Leaving:** landing (`UnitOnTaxi` false; `PLAYER_CONTROL_GAINED` wakes the driver) fades
  everything back. Combat or a popup that needs you (ready check, invite, LFG, duel, summon,
  cinematic) brings the interface back at once and keeps it for the rest of that flight (the
  driver only goes on checking for the landing, to time the flight).
- **Cost:** nothing on the ground: `PLAYER_CONTROL_LOST` and `PLAYER_ENTERING_WORLD` show the
  driver, which looks for the taxi 4x a second for 3 s and hides itself. In the air it checks 4x a
  second (landing, leaving, zone cards, subtitles, the time left); the bars and cards fade by
  animation.
