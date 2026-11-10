# Misc Tweaks design

`Modules/Tweaks/Tweaks.lua` is the module: its settings (defaults, the settings page),
`/lefthy tweaks`, the small `statusText` tweak, `ns.HideInterface` (shared by the AFK screen and
cinematic flights), `ns.TweakUtil` (what several tweaks ask: in combat, typing, how many windows
are open, "1:05", a unit's nameplate and its health bar) and the list of independent tweaks
(`TWEAKS`), each with a setting, a slash command word and an `apply(on)` function, which calls
the tweak's file (`ns.ApplyMovableBags`, ...). `Reconcile()` compares what's wanted (module enabled
and the tweak's setting on) with what's active, and runs on the next frame via `C_Timer.After(0)`.
All tweaks default to on, except `retailFrames`. The other files, in load order: `Bags.lua`
(`movableBags`, `gamepadBagSort`), `GamepadBags.lua` (`gamepadBags`), `QuestAnnounce.lua`, `ComboPoints.lua`, `Aggro.lua`,
`RetailFrames.lua`, `ForeverQuests.lua`, `AFK.lua`, `FlightTime.lua` and `Flight.lua`, `LevelUp.lua` and
`LevelUpWindow.lua`, `QuestMap.lua`.

## statusText: always show health and power values

Sets the CVars `statusTextDisplay = "NUMERIC"` and `statusText = "1"`, exactly what Blizzard's
Options > Interface > Status Text does (`Blizzard_SettingsDefinitions_Frame/Interface.lua`).
TextStatusBar shows the text permanently when `GetCVar(self.cvar) == "1"` and `textLockable`; the
player, target, pet, party and focus bars use `cvar = "statusText"`. The previous CVar values are
stored in `savedStatusText` and restored when switched off. **Don't use `bar:SetForceShow()` or
write fields on Blizzard bars:** health is secret in Forever, and a tainted field read makes
Blizzard's secret comparisons in `UpdateTextStringWithValues` error.

## movableBags (Bags.lua)

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

## gamepadSymbols: the controller's button symbols

A controller's config has a `labelStyle`, which picks the prompts' symbols: `Generic` and `Letters` (Xbox),
`Shapes` (PlayStation), `Reverse`. Blizzard's `InputDeviceIconSetManager` reads it from
`C_GamePad.GetDeviceMappedState`. `GetConfig` returns nil for the game's built-in configs, so there's nothing
to copy; but a config of ours with only `labelStyle` and empty lists works: the game keeps the
built-in mappings beside it (in game, a Steam Controller, 10462:4866: `Shapes`, 32 buttons, 10 axes, all
working). Blizzard's prompts read the symbols once, so a change shows after a `/reload`: changing the
setting says so, and a button under it reloads. `SetConfig`, `ApplyConfigs` and `DeleteConfig` are marked `HasRestrictions` but
answer from addon code out of combat. Set per controller (vendor and product, `GetDeviceRawState`) when
the setting changes, at login, on `GAME_PAD_CONNECTED`; in combat it waits for `PLAYER_REGEN_ENABLED`. Ours
are remembered in `padSymbolConfigs`, and "default" deletes them. It wrote no file in `WTF` that a look found, so
it's applied again at each login. `/lefthy tweaks padsymbols` does the same.

## gamepadBagSort: the bags' clean-up button (Bags.lua)

With the controller UI (`InputUtil.IsGamepadUIEnabled`) there's no button and the search box stays as Blizzard put
it: the controller's bag menu has clean-up, and `SmartNavigationMixin:GetButtonInfoInDirection` goes to the nearest
valid button, so at the top of a bag this one got in the way of moving through the slots (seen in game).

Since 1.60.1.70291 the bags' clean-up button (`BagItemAutoSortButton`) no longer shows, with mouse
and keyboard or in gamepad mode (seen in game; before, `ContainerFrameMixin:UpdateSearchBox`
hid it in gamepad mode only, where the gamepad bag bar, `GamepadBagBar`, offered clean-up in each
bag's menu; 70291 seemed to stop showing that bar on the bags, but later builds show its buttons in the
controller's item grid again, see gamepadBags). So nobody had a way to clean up. A
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

## gamepadBags: the bags with a controller (GamepadBags.lua)

With mouse and keyboard (`mouseBags`, on by default; `Active()` asks the one for the mode the interface
is in) the same sections, columns and folded free slots, without the "Bags" header and its row (the bag
buttons sit on the main bar), without SmartNavigation's jumps and with the tooltip where Blizzard puts it.
Switched off there, Blizzard's grid comes back at once (`UpdateItemLayout`). The reagent bag has its own window
with mouse and keyboard (the combined bag holds bags 0 to `ENDING_BAG_INDEX`, 4 then; a global we leave alone): its
item buttons are reparented into ours (`Adopt`) and sorted with the rest, its window stays open for Blizzard (so it
keeps updating them) but at alpha 0 with its mouse off, close button and portrait too (`Hush`). They go back
(`GiveBack`, its own `UpdateItemLayout`) when ours goes or that window closes.

By default the bag buttons' row is folded away under a "Bags (5)" header: our own button on the bag, so the
controller lands on it too. The cursor landing there (`FocusEnter` runs its OnEnter) opens the row for as long
as the cursor stays up there (`peeking`); moving down into the items folds it (SmartNavigation's outgoing-down
callbacks on the header and the bag buttons, `SmartNavigation_RegisterOutgoingDirNavCallback`, which keep their
own taint). A mouse click flips `gamepadBagButtons` (open for good; its checkbox follows). A on the header does
nothing: the bag's A ("Select") only takes an item or a bag button, and passing the header off as one (setting its
`buttonContext` and `isBag`) had Blizzard's bindings read our values while the cursor was on it: B there then ran
the close chain tainted (`SpellStopCasting`, `SpellStopTargeting`, `ClearTarget` forbidden). One free slot (the first in the bags' order) stands for all, with the count on
it and in its header ("Free slots (12)"); `gamepadBagAllFree` brings every one back. The others are hidden
(`Tuck`) and shown again whenever ours goes (`Untuck`), so Blizzard's own layout always has them all.

Columns: `gamepadBagColumns` (a slider, 6 to 24, default 10 like Blizzard's grid). Our layout sets the bag's
width for them (`Columns`, after Blizzard's `UpdateFrameSize` too); Blizzard's own width comes back when ours goes.

With the controller UI (`InputUtil.IsGamepadUIEnabled`) Blizzard's combined bag puts each bag's button
(`GamepadBagBar:GetBagButton(bagID)`, Camelot's `MainMenuBarBagButtons.xml`) into the item grid:
`ContainerFrameMixin:UpdateItemLayout` adds them to the items, `UpdateItemSort` sorts by bag (the bag's
button before its slots) and `AnchorUtil.GridLayout` lays them out from the bottom right, so the bag reads
"bag, its slots, next bag, its slots". This tweak (on by default) places the same buttons anew; with mouse
and keyboard nothing changes.

**The layout.** The bag buttons in a row at the top (backpack first, the key ring last, as Blizzard orders
them; they still open their bag menu, collapse their bag, and the shoulder buttons still jump between
them: Blizzard's `Gamepad_SetCursorToBag`). Below it the items in sections, each with a small gold header
and a line: Gear (weapons and armour that are worn: `GetItemInfoInstant`'s class 2 or 4 with an
`equipLoc`, not bags, quivers or ammo), Consumables (class 0 and projectiles), Trade goods (trade goods,
reagents, gems, enhancements), Quest items (`C_Container.GetContainerItemQuestInfo`, or the quest class),
Other, Junk (grey quality, gear too), then the free slots (by bag and slot; slots of an unsecured account
last). In a section: best quality first, then item level (gear, `C_Item.GetDetailedItemLevelInfo`), the
name (from the link), the bigger stack, the bag's order. A bag collapsed in its menu (`isCollapsed`) keeps
its slots out, as Blizzard does. Everything is anchored like Blizzard's grid (`BOTTOMRIGHT` at
`GetInitialItemAnchor()`, the money frame, 37 px buttons 5 apart, `GetColumns()` 10), worked out from the
top. The bag's height is Blizzard's (`CalculateHeight()`) with its grid's rows (`GetRows()`, which in
gamepad mode keeps room for `NUM_CONTAINER_FRAMES` more buttons) taken out and ours put in;
`UpdateContainerFrameAnchors` runs right after Blizzard's layout, so it places and scales the bag with it.
The headers are font strings on a frame of ours made without a parent and then put on the bag:
SmartNavigation hooks `CreateFrame` and refreshes the panel a frame is made on (from addon code that's
refused in combat). They aren't buttons, so the cursor never stops on them.

**When it runs.** Post-hooks only (`hooksecurefunc` on the bag frame's methods; Blizzard calls them as
`self:...`): `UpdateItemLayout` (opening the bag, a bag collapsed, a bag changed, gamepad mode switched:
ours right after Blizzard's, in the same frame, so there's no flicker), `UpdateFrameSize` (Blizzard sizing
the bag without laying it out, a currency watched: our height kept) and `UpdateItems` (Blizzard redrew the
items after `BAG_UPDATE`: sorted again on the next frame, moved only if the order or the sections changed).
Selling or using up the selected item: the cursor goes to the button now in its place
(`SetTargetButtonForFrame`), so selling junk goes on to the next junk instead of jumping to the free slots.
An item used up while another window has the cursor (a clam opened: its loot window takes it) works the same:
back in the bag SmartNavigation picks its `lastButton` first (only Blizzard's code may change it), the emptied slot,
so a post-hook on `SmartNavigation:SelectButton` moves the cursor on to the item in its place on the next frame.

**Navigation.** `ContainerFrameCombinedBagsMixin:SmartNavPanelInfoAdded` turns on SmartNavigation's grid
mode, which sorts the buttons into columns by their x and moves by index within a column
(`GetButtonInDirectionGrid`, with `SetGridHeightCompensation` assuming columns differ only at the top): with
sections whose last rows are part-filled, left and right would land a row off. So while ours is shown the
bag's panel goes by direction (`SetUseGridNavigation(bag, false)`: `GetButtonInfoInDirection`, the nearest
button within 45 degrees, positions read live), with Blizzard's wrapping kept: down and up go row by row
through the sections, across the headers' gaps, up from the first row into the bag buttons, up from the
backpack's button to the bag menu (Blizzard's jump), and wrapping at the edges as before. A shorter row's
last button is outside those 45 degrees from two columns or more away (down would skip a section of one or
two items), so where the row below or above is shorter a jump goes to its last button
(`SmartNavigation_AddJumpNavigationOverride`, values SmartNavigation keeps securely; on items up and down,
on the bag buttons only down). Blizzard's jump from the top left item up to the bag menu
(`ApplySmartNavOverrideForLeftmostButton`) is cleared on our items
(`SmartNavigation_ClearJumpNavigationOverridesInDirection`), since the bag buttons are above it now. Our
jumps are set with each layout of ours and cleared when the bag closes, when ours goes, or after the fight
they couldn't be cleared in; a bag closed and opened again in the same fight can still have them on
Blizzard's layout until the fight ends (a few D-pad moves at its short rows go somewhere odd; no error).
The panel is made anew each time the bag opens (and dropped when it closes), so grid mode is turned off
from a post-hook on the bag's `smartNavPanelInfoAddedCallback` (the field Blizzard's
`SetSmartNavPanelInfoAddedCallback` sets; hooked again if Blizzard sets it again) and on
`ApplySmartNavOverrideForLeftmostButton` (the frame after opening). After our own moves (not Blizzard's
layout calls) `RefreshButtonGroups(bag)`. Other panels: as before (the bag wraps; switching panels is
Blizzard's input).

These SmartNavigation calls are the ones it lets addon code make (`SecureHelper:WrapFunction` and its
registered keys): run securely through an attribute handler, but only while
`C_RestrictedActions.IsAddOnRestrictionActive(Combat)` is off; in combat they're refused with Blizzard's
"Interface action blocked". Bag item buttons and the combined bag aren't protected (no secure templates in
`ContainerFrame.xml`), so **ours is placed in a fight too** (new loot sorted in, the bag opened in a fight
sorted at once); only SmartNavigation isn't told then (`NavLater`): at `PLAYER_REGEN_ENABLED` it hears of
the layout (grid mode off, its buttons, our jumps). Till then the controller's cursor may go by Blizzard's
grid. (Holding the whole layout back in fights, as the first version did, put Blizzard's bag back in every
fight, which nothing required.) Were the bag or its buttons ever protected in a fight (`Locked`), Blizzard's
layout would stand until it ends.

**Shoulder buttons to jump between sections: not done.** The bag's shoulder buttons are Blizzard's
binding group (`navigateCombinedBagsFrame`: `GAMEPAD_SHOULDER_LEFT/RIGHT` to `Gamepad_SetCursorToBag`),
and `GamepadMode.CreateBindingGroup`/`ActivateBindingGroup` have no guard for addon code: a group of ours
would write the binding manager's stack and its `nextBindingGroupId` upvalue tainted, which every later
controller input reads (item use through SmartNavigation's click included). Replacing Blizzard's binding
isn't a post-hook. So the shoulder buttons keep jumping between the bag buttons.

**The tooltip.** A post-hook on `GameTooltip:SetBagItem` (Blizzard calls it on selecting an item, as its
`OnEnter`, and on each tooltip refresh, `UpdateTooltip`): for our items it moves the tooltip beside the bag
(left of it, at its top; right of it when the bag is on the left half of the screen), where it doesn't
cover the grid. The comparison with what's worn comes from Blizzard as with the mouse (with *Compare items*
on in the backpack's menu, `alwaysCompareItems`, or the modifier) and follows the tooltip. Nothing runs per
frame: the tooltip only moves when Blizzard sets it up.

**Off** (`/lefthy tweaks padbags off`): the headers go at once; Blizzard's layout comes with its next one
(the bag opened again), and its new panel is in grid mode again. Our layout code never calls Blizzard's
`UpdateItemLayout` itself.

## movableLootRolls: the loot roll window where you drag it (LootRolls.lua)

Like the movable bags: drag it, it comes up there from then on; `/lefthy tweaks resetloot` puts it back.

- **Controller UI:** rolls show in `GamepadGroupLootRollFrame`. Blizzard gave it `OnDragStart` / `OnDragStop`
  (StartMoving, StopMovingOrSizing) but never `SetMovable` or `RegisterForDrag`: that's all this adds, plus its spot
  (`lootRollPadPos`, left and top in UIParent units) kept and put back whenever it shows.
- **Mouse and keyboard:** the Need / Greed windows (`GroupLootFrame1..4`) sit in `GroupLootContainer`, one of the
  bottom managed frames (`BottomManagedFrameTemplate`) laid out with the action bars. The container stays (taking it
  out of that stack from addon code would touch the action bars' layout, protected in a fight); its roll windows are
  placed anew right after Blizzard places them (a post-hook on `GroupLootContainer_Update`), stacked up from an
  anchor of ours, 100 apart like Blizzard's. Dragging any of them moves the anchor (the first drag starts it where
  that window's stack is; `lootRollPos`). The roll windows aren't protected, so it works in fights.

(The first version also had a placing preview and buttons in the settings; with the controller it did nothing,
since it only knew the mouse-and-keyboard windows. Taken out: dragging the window is all it needs.)

## questAnnounce: quest progress in party chat (QuestAnnounce.lua)

Lines go at once, in fights too: an ordinary fight doesn't restrict party chat, only the client's chat
lockdown does (`C_ChatInfo.InChatMessagingLockdown`: encounters, challenge modes, PvP), which they wait out.
(0.7.0-37 to -62 held them through every fight, on a wrong guess about a friend's blocked action.)

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
- **Nameplate dots** (`comboNameplate`, on): small round dots in the middle of the target's health
  bar (the bar itself: `healthBar`, else `HealthBarsContainer.healthBar`, else the container, whose
  height can differ; the row's CENTER on the bar's, so any dot size stays centred; it sat on the
  bottom edge at first; centred now), one per point the bar can hold (`UnitPowerMax`
  for combo points, 5 if unknown or secret), centred horizontally too. Lit ones in the count's colour (colouring off: Blizzard's red), the rest dark sockets
  (grey 0.22 at 75%); each sits on a black ring (85%) a pixel wider all round, so it reads on a red
  bar too. Round through a mask (`TempPortraitAlphaMask`, like Beacon's map dots). Size: slider
  `comboDotSize` (4-12 px, default 6, the ring included), gap half the size (at least 2 px). They
  take no room of their own: nothing above the bar (buffs, debuffs) or beside it (the level) moves.
  This replaced a gem in the personal display's look beside the level, which looked stuck on; its
  settings (`comboNameplateX/Y/Size`) are no longer read. Moving the slider shows the dots on the
  target for 5 s (full points if there are none: `ns.PreviewComboNameplate`).
  **Preview** (`ns.ComboTrial`: the settings' *Try it* button, `/lefthy tweaks combopos`): a small
  window (FULLSCREEN_DIALOG, movable, Escape closes it) with a stand-in nameplate (a name, a health
  bar, the level) whose dots count up from one to full every 0.8 s, again and again (an OnUpdate only
  while it's open); - and + change the size (saved through `LT:SetModuleSetting`, so an open settings
  page shows it), Reset, Done. While it's open the target's real nameplate shows the dots too, also
  without points.
  Our own frame, parented to the plate's `UnitFrame` (it shows, fades and scales with it), 10 frame
  levels above the bar. Only while there are points. Found again on the next frame after target,
  combo points, max points or combo target changes; a nameplate added only matters while points
  wait for the target's (no dots up), one removed only while dots are up, so crowds bringing
  nameplates all the time cost nothing. A forbidden or missing nameplate, or secret points: no dots.
  The colouring's copies follow Blizzard's gems only after its own updates (its `UpdatePower`), not
  after every event.

## aggroNameplate: who has aggro, on enemy nameplates (Aggro.lua)

For tanks and healers: at the very left of the health bar, like the combo points, it tells you who
has aggro of that mob: `>YOU<` when it's you, otherwise the first three letters of the other
player's name in the colour of their role. People will mostly look for the colour first.

- **The tag**: our own frame on the plate's `UnitFrame` (it shows, fades and scales with it; kept
  in a weak table by unit frame, nothing written into Blizzard's frames), at the health bar's left
  end (`LEFT`, 1 px in; the bar found like the combo dots'), 10 levels above it: the text in 8 px,
  outlined with a black shadow (1, -1), no backing (no black background, a shadow
  instead), so the colour reads on the red bar. `>YOU<` (deDE `>DU<`, in capitals) or the
  first three letters of the name, whole UTF-8 letters ("Ölrik" -> "Ölr"). Colours: tank (0.35,
  0.62, 1), healer (0.3, 0.95, 0.4), damage (1, 0.32, 0.26), no role (0.92 white), pet (0.85, 0.72,
  0.45), outside the group (0.6 grey). Takes no room: nothing on the nameplate moves.
- **When**: in a group (`IsInGroup`), on an enemy (`UnitCanAttack`, not a player, not dead) that's
  in combat (`UnitAffectingCombat`). Solo nothing (it's meant for groups).
- **Who** (`Holder`): the mob's target (`UnitGUID(<plate>target)`) when it's in the group and its
  `UnitThreatSituation(member, mob)` isn't 0 or 1 (tanking, or not readable); else whoever is
  tanking it (status 3, else 2) over the group, pets included (a spell at the healer while you
  tank it: you); else the target anyway; else someone outside the group by name (an escort). The
  API docs mark threat and unit identity "secret when restricted": a secret value counts as not
  readable, and with nothing readable there's no tag (not a wrong one).
- **Roles** (`Role`): `UnitGroupRolesAssigned` (the dungeon finder or a role check), else
  `GetPartyAssignment("MAINTANK")`, else a guess: Bear Form, Dire Bear Form, Righteous Fury
  (`C_UnitAuras.GetAuraDataBySpellName` or `AuraUtil.FindAuraByName`, names from the spell IDs) and
  your own Defensive Stance (`GetShapeshiftFormInfo` spell 71). Forever's UI has Blizzard's role
  check window (`RolePoll.lua`) but no way to start one, and `InitiateRolePoll` isn't restricted:
  **Start a role check** (`/lefthy tweaks rolecheck`, leader or assistant) starts it, and everyone
  picks in Blizzard's window, LefthyTools or not.
- **Cost**: the roster (GUID -> unit, name, role; player, pet, party1-4 or raid1-40 and their pets)
  is read again only on roster, role, pet and form changes and when combat starts or ends (forms
  are up by then), not on threat changes. `UNIT_THREAT_LIST_UPDATE`, `UNIT_TARGET` and
  `UNIT_FLAGS` mark that nameplate, `UNIT_THREAT_SITUATION_UPDATE` all of them; one OnUpdate looks
  at the marked ones on the next frame. While you're in combat in a group it also looks at every
  enemy nameplate every 0.5 s (1 s in a raid), in case an event was missed; otherwise it stops.
  Combat comes from `PLAYER_REGEN_DISABLED` / `_ENABLED` themselves: the combat lockdown begins
  only after the first, so `InCombatLockdown()` is still false inside it.
- **Try it** (`/lefthy tweaks aggrotest`): for 10 s each enemy nameplate in sight shows an example
  (you as tank, a healer, a damage dealer, someone without a role).
- **The fight stream** shows the same tag on its battle row's foes (beacon.md, "Who has aggro"), so
  the reading and the look are shared: `ns.AggroHolder(unit)` (in a group: the holder's role, a
  member's or `PET` / `OUTSIDER`, their name and whether it's you; nil when solo or nobody's known),
  `ns.AggroTag(role, name, you)` (text and colour; the nameplates' tag goes through it too, with
  `RoleOf(holder)`) and `ns.AggroShort` (the three letters). The stream's sensor reads them also
  with this tweak or Misc Tweaks off: while it runs, `ns.AggroWatch(true)` registers the roster
  events (`ROSTER_EVENTS`, the same as the tweak's) on a frame of its own, which only mark the
  roster to be read again at the next look.
- To check in game: whether threat and a mob's target are readable in dungeons (or secret), and
  whether Forever's groups have roles.

## retailFrames: retail unit frames (RetailFrames.lua)

Off by default (friends may like Forever's look). Build 1.60.1.70425 drew the player, target,
focus, party, pet and target of target frames in a classic style. How it's done in the client:

- **Atlas sets.** `UiTextureAtlas.UiTextureAtlasSetID`: set 0 is retail's art, set 1 Forever's own
  ("c60": `uiunitframec60.blp`, `uiunitframe2xc60.blp`, ...). An atlas name defined in set 1
  overrides the same name in set 0; 70425 moved 87 unit frame atlases into set 1 (and rebuilt set
  1's files, so the earlier c60 look is gone for good). There's no API to choose a set, but set 0's
  definitions are still in the client (`uiunitframe2x.blp` 4642466 and friends), so a texture can be
  pointed at them by file, texture coordinates and size. Not changed: nameplate atlases (only the
  level box moved a little in Forever's `NameplateLevelFrame`).
- **Camelot layout code.** `Camelot/PlayerFrame.lua` replaces the globals `PlayerFrame_Update*Visuals`
  (retail's versions are gone at runtime: same names, loaded later), `Camelot/TargetFrame.lua`
  `TargetFrameMixin:OnLoad` / `UpdateHealthBarVisuals` and `TargetOfTargetMixin:OnLoad`,
  `Camelot/PetFrame.lua` `PetFrameMixin:OnLoad`, `Camelot/PartyMemberFrame.lua` the party frames'
  `ArtLayoutInfo.Player` / `.Character`; the Camelot templates put the level in a circle
  (`LevelBackgroundCircle`, `WhiteLargeNumberFont`).

`Data/RetailUnitFrames.lua` (generated by `tools/update-retail-frames.js` from wago.tools'
UiTextureAtlas / Member / Element exports: unit frame names in set 1 that set 0 defines; the 2x
file and coordinates, the 1x size): `ns.RETAIL_FRAME_ART[name] = { file, l, r, t, b, w, h }`, and
`ns.RETAIL_FRAME_BARS[name]` for status bar fills: a bar crops its fill texture itself, so a fill
can't point at part of a file; it gets another atlas with retail's art that set 1 doesn't override
(the player frame's "PortraitOff" bars: health, its white "Status" variant, mana, energy, focus,
rage, runic power). Rerun the tool when Forever's art changes again.

Switched on (`ns.ApplyRetailFrames`):
- **Art:** walks PlayerFrame, PetFrame, TargetFrame, FocusFrame, both ToT frames, PartyFrame and the
  boss frames (children, 10 levels): every texture and mask texture gets a `hooksecurefunc` on its
  `SetAtlas`, every status bar on its `SetStatusBarTexture` (its fill is marked); textures showing
  one of the atlases now: retail's file and coordinates, the size too if it was sized by the atlas
  (its size equals the current atlas's), masks retail's mask file (`CLAMPTOBLACKADDITIVE`); bar
  fills the stand-in atlas. Later `SetAtlas` / `SetStatusBarTexture` calls (classification,
  power type, vehicle) are handled in the hooks. Forever's level circles (no retail art) are hidden.
- **Layout:** retail's values from Blizzard's retail Lua and XML, applied after Forever's code
  (post-hooks on `PlayerFrame_UpdatePlayerNameTextAnchor`, `_UpdateLevel` (gold level),
  `_UpdateFlashTextureVisuals`, `_UpdateStatusTextureVisuals`, `_UpdateHealthBarVisuals`,
  `_UpdateManaBarVisuals`; the target's and focus's `UpdateHealthBarVisuals`; each party member's
  `ToPlayerArt`, `ToCharacterStyleArt`, `UpdateNameTextAnchors`) and once on switching on (target
  and focus: name, reputation colour, level, skull, flash, mana bar and its text; ToT and pet: name,
  bars, masks). Bars and their containers inherit `SecureFrameParentPropagationTemplate`
  (protected): moved only out of combat, else marked and done on `PLAYER_REGEN_ENABLED` (Forever's
  target code places the health bar again on every new target, also in combat: until combat ends it
  sits a pixel or two off). Textures, masks and font strings any time. The events only note the
  work (`GROUP_ROSTER_UPDATE`: new party member frames get their hooks and art; the end of combat:
  the marked layout); a driver does it on the next frame, once for a burst (a raid forming sends
  many roster events a second).
- **Off:** the hooks do nothing any more; a chat line says a /reload brings Forever's frames back
  (nothing is undone piece by piece).

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
  Forever builds are listed under the release product `wowf` on wago.tools and, as version 1.60.x,
  under the beta's `wow_classic_beta`; the script picks the newest one. Regenerate the lists when Forever gets new builds. Stored as comma-separated IDs
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
map nothing. Frames of our own on the map's canvas add them (`LT.MapOverlay`, `Core/MapOverlay.lua`:
no data provider, no `AcquirePin`, nothing written into the map; forever-platform.md, "The world
map", has why), per zoom level: `questMapContinent` and `questMapWorld` ("off", "icons", "areas",
"both"; default both) and `questMapZone` ("blizzard", or "areas": every quest's area), and
`questMapClick` (a checkbox). The choices are `Builder:Choice` sliders (no dropdowns, see
forever-platform.md).

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
- **Icons:** plain frames (not Buttons), made with no parent and then put on the canvas, the i-th
  icon of a draw always the i-th frame; scaled like a map pin with `SetScalingLimits(1, 1.0, 1.2)`
  and placed again on zoom. Blizzard's art from `POIButton.lua` at 80%: `UI-QuestPoi-QuestNumber`
  (`-SuperTracked` for the selected quest) behind `Quest-In-Progress-Icon-yellow` or
  `UI-QuestIcon-TurnIn-Normal`; the frame levels the map gives `PIN_FRAME_LEVEL_ACTIVE_QUEST` /
  `_SUPER_TRACKED_QUEST` (`GetValidFrameLevel`, a read). Icons that would cover each other are
  spread with Blizzard's `WorldMapPOIQuantizerMixin` (an object of our own, 75 cells high, as on
  zone maps). Tooltip: title (with level and difficulty colour through
  `SetQuestTitleLevelAndDifficultyColor`, as the map's options say), zone, unfinished objectives or
  "Ready to turn in". With icons only, hovering one draws its area (a frame of its own) until the
  mouse leaves, and the selected quest's area is always drawn (zone maps show it too). The
  controller's map cursor shows the tooltip (and the area) too, on the overlay's own tooltip
  (beacon.md, "World map").
- **Clicks** (`questMapClick`, on): a left click does what `POIButtonMixin:OnClick` does on zone
  maps: select the quest (`C_SuperTrack.SetSuperTrackedQuestID`, tracked with
  `C_QuestLog.AddQuestWatch` if it wasn't), unselect the selected one (`ClearAllSuperTracked`),
  Shift-click on a tracked quest stops tracking it, and with the chat box open the quest link goes
  in (`ChatFrameUtil.TryInsertQuestLinkForQuestID`); then the map redraws on the next frame. The
  icons take the mouse (`EnableMouse`) with `OnEnter` / `OnLeave` only: a frame with an
  `OnMouseDown`, `OnMouseUp` or `OnClick` script is a button to the controller's navigation, which
  reads the script back from Blizzard's code. So a click is a `GLOBAL_MOUSE_DOWN` and a
  `GLOBAL_MOUSE_UP` of one button on the hovered icon (`Overlay.OnMouse`, only while the map is
  open). With the setting off the icons take no clicks (`SetMouseClickEnabled(false)`): they reach
  the map and it zooms in. Right-clicks pass through (`SetPassThroughButtons("RightButton")`, once
  per icon and only out of combat: it's protected in combat; an icon made in a fight gets it on the
  frame after `PLAYER_REGEN_ENABLED`, until then a right-click on it doesn't zoom out). **Not in
  gamepad mode:** the controller's button is the map's (`WorldMapMixin:GamepadMapClick`: it zooms
  in or changes the zone), so there the icons take no clicks.
- **Areas:** the engine draws quest blobs into a `QuestPOIFrame` for one `uiMapID` (`SetMapID`,
  `DrawBlob(questID, true)`), filling the frame. Ours are `CreateFrame("QuestPOIFrame")` (no parent,
  then the canvas), set up like Blizzard's `QuestBlobPinMixin` (blob textures, fill 128, border
  192), at `PIN_FRAME_LEVEL_QUEST_BLOB`'s level; each zone with quests gets its own, set to that zone,
  sized to the zone's rectangle in canvas units (`Overlay.PlaceRect`: they zoom with the map) and
  centred on it. No mouse.
- **Cost:** nothing while the map is closed: its events (`QUEST_LOG_UPDATE`, `QUEST_POI_UPDATE`,
  `QUEST_WATCH_LIST_CHANGED`, `SUPER_TRACKING_CHANGED`, `CVAR_UPDATE`) are registered when the map
  opens (the overlay's `"show"`) and dropped when it closes. While it's open an event queues one
  redraw 0.5 s later; a burst of events makes one. A redraw asks each zone once (about 25 on a
  continent); zooming only places the icons again.
- **Unverified in game:** whether `QuestPOIFrame` draws a zone's blob correctly in a frame that
  small, and how thick the border looks there (`SetBorderScalar`).

## levelUp: the level-up window (LevelUp.lua, LevelUpWindow.lua)

`LevelUp.lua` knows what a level brings (`Collect`: trainer spells, talent row, class quest,
dungeons, friends) and when the window comes (the events, the stat snapshot, `Preview`,
`Browse`); `LevelUpWindow.lua` draws it (`LevelUp.Show`, `Close`, `SetPinned`) and steps aside for
fights (`LevelUp.StepAside` / `ComeBack`).

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
the interface, items shown or offered, LTC lines and announcements, the text cut at 90
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

## cinematicFlights: flights like a film (Flight.lua, FlightTime.lua)

On a flight path (`UnitOnTaxi("player")`) the interface fades out over 1.5 s (`ns.HideInterface`
with a fade: an OnUpdate only while fading), black letterbox bars (7% of the screen each) fade in
(the bars show what Beacon friends are doing, setting `flightFriends`: `B.FriendRows` per friend in
three lines, who (with their health, when known) and where, their quest, fighting or dead; three side by side in the top bar, a
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
  map (a quest's) doesn't get the last one's name and time; so does a takeoff more than 10 s
  after the pick (a pick that never took off: not enough money, say).
- **Time left** (`FlightTime.lua`: `Pick` on the taxi map, `Trip` at takeoff, `Record` on
  landing, `Left` / `Text` for the bottom bar): the game doesn't tell. The same hook reads the
  taxi map (`GetTaxiMapID`, `C_TaxiMap.GetAllTaxiNodes`): the node you're at (state `Current`)
  names the route ("From > To"), and each slot's `nodeID`. `Pick` also returns the node IDs of
  where you are and of the destination, after the route (for other modules; the film doesn't use
  them). Best first:
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
- **Links in subtitles** (shared items, links in LTC): the subtitles sit in a frame of their
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
