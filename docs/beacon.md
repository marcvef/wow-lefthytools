# Beacon design

Battle.net friends who also run LefthyTools see each other on the world map and minimap, with
status (dead/ghost, in combat, who they're fighting), and get each other's level-ups. Only
Battle.net friends; each player writes their own level-up message.

Files: `Beacon.lua` (module, protocol, rate limiter, settings, `/lefthy beacon`), `Dots.lua` (dot
look, tooltip, world map provider, minimap pins), `Ding.lua` (level-up messages, toast, sounds),
`Alerts.lua` (death alerts), `Pings.lua` (map pings), `Beacon.xml` (world map pin templates). They share state through `ns.Beacon` (`B`): `B.peers`,
`B.Clean`, `B.QueueToPeers`, `B.MyWorldPosition`, and hooks the other files set (`B.RefreshMaps`,
`B.UpdateMinimap`, `B.Attach`/`B.Detach`, `B.ShowDing`, `B.AnnounceLevel`, `B.OnSettingChanged`).

## Transport and protocol

- Addons have no network access, so there's no server. Messages go through
  `C_BattleNet.SendGameData(gameAccountID, "LTBeacon", data)` and the `BN_CHAT_MSG_ADDON` event
  (prefix, text, channel, senderID = sender's gameAccountID); the prefix is registered with
  `C_ChatInfo.RegisterAddonMessagePrefix`. Results `AddonMessageThrottle` (3) and
  `AddOnMessageLockdown` (11) pause sending for 2 s and keep the message (so a level-up isn't
  lost); other failures (e.g. `TargetOffline`) drop it (the next state or heartbeat covers it).
- **Protocol v2** (`;`-separated; the digit after the kind is the version): `H2` hello,
  `S2;<flags>;<continent>;<north>;<west>;<subzone>;<target>` state (flags D dead, G ghost,
  C combat; position empty in instances or with sharing off; target only in combat),
  `L2;<level>;<text>` level-up, `V2;<version>` the sender's LefthyTools build (`LT.version`),
  `P2;<continent>;<north>;<west>;<uiMapID>` map ping,
  `T2;<questID>;<done>;<title>;<objective>` tracked quest, `E2;<kind>;<a>;<b>` a Chronicle
  highlight (see [chronicle.md](chronicle.md); at most 6 per friend per minute, known kinds only),
  `C2;<count>` enemies on them in combat, `X2;<percent>` progress on their level, `Q2` switched
  off. A build that doesn't
  know a kind ignores it (`Parse` returns nil before the sender is registered), so new kinds
  don't break older friends. A hello is answered with the version and the state (at most every 5 s per friend);
  if a friend's build is newer (`LT.CompareVersions`), the player gets one chat notice per login
  telling them to run `Update-LefthyTools.cmd`. Builds before 0.4.0 ignore `V2`. A message
  with another version marks the sender in `otherVersion` (shown by `/lefthy beacon status`)
  instead of making them a peer; v1 (0.2.0) and v2 can't see each other. `Parse` validates the
  whole message *before* touching state, so a malformed message doesn't register its sender.
  Free text (subzone, target, level-up text) goes through `B.Clean`: colour codes, `|`, `;` and
  control characters removed, cut at a UTF-8 boundary.

## Finding friends

`Sweep` greets online WoW game accounts (`clientProgram == BNET_CLIENT_WOW`, `isInCurrentRegion`,
`wowProjectID == WOW_PROJECT_ID`) via `BNGetNumFriends` / `C_BattleNet.GetFriendGameAccountInfo`,
once a minute and at most every 10 s after `BN_FRIEND_ACCOUNT_ONLINE`; the same friend at most
every 120 s. Forever reports `WOW_PROJECT_ID == 1` like retail, which is why the handshake exists.
`Validate` re-reads only the known peers (`GetGameAccountInfoByID`) every 15 s and, coalesced to
once a second, after `BN_FRIEND_INFO_CHANGED`/`BN_FRIEND_ACCOUNT_OFFLINE`; offline peers are
dropped at once. `BN_FRIEND_INFO_CHANGED` fires whenever *any* friend changes zone in any game, so
it must never trigger a full friend-list walk.

## Traffic (never lag the client)

Values that only matter in their newest form (tracked quest `T2`, enemy count `C2`, level
progress `X2`) replace a message of the same kind still waiting in the queue for that friend
instead of lining up behind it (`B.QueueToPeers(message, true)`), so a busy fight or a throttle
can't build a backlog in front of position updates.

The state is checked every `interval` s (1-10, default 3) and only sent when it changed, plus a
heartbeat every 20 s; status events (combat, death, target, zone) send early but at most once a
second. Standing still out of combat costs one ~30-byte message per friend per 20 s. All sends go
through one token bucket (10/s, burst 10). Incoming: at most 20 messages per second per friend
(flood guard), level-ups at most one per 10 s per friend. Peers silent for 65 s (three
heartbeats) are forgotten. `/lefthy beacon status` prints sent/received per minute and throttle
hits.

## Positions

Each client can only read its own (`C_Map.GetPlayerMapPosition` works for the player and party
only; nil in instances). The sender converts map coordinates with `C_Map.GetWorldPosFromMapPos`;
a world vector is (north, west) in yards (as in HereBeDragons, and `UnitPosition` returns north,
west, z, instanceID). The receiver converts back with `C_Map.GetMapPosFromWorldPos(continent,
vector, openMapID)`. The minimap needs the own position every frame: `UnitPosition("player")`
doesn't allocate and is used once it has been seen to agree (same continent, < 2 yd) with the map
route; until then the map route is used.

## World map

A `MapCanvasDataProviderMixin` provider on `WorldMapFrame` with pins from the
`LefthyToolsBeaconPinTemplate` XML template. `AcquirePin` pools by template name, calls the
mixin's `OnLoad` once for new pins and wires `OnMouseEnter`/`OnMouseLeave`; the template must not
define OnEnter/OnLeave scripts (the canvas asserts). `enableMouseMotion` only, so clicks pass
through. Provider code still runs as addon code (also from our own refresh), so it must not call
protected functions: `AcquirePin` calls `pin:CheckMouseButtonPassthrough`, whose base version
uses the protected `SetPassThroughButtons` (blocked in combat), so the pin mixin replaces it with
an empty function (as HereBeDragons-Pins does). Pins are
kept per friend and updated in place (`RemovePin` only when a friend disappears), so a hovered dot
keeps its tooltip. Refreshed at most twice a second, only while the map is open.

## Minimap

Plain frames parented to `Minimap` (so Mirage's fade/hide applies), placed with
`SetPoint("CENTER", Minimap, "CENTER", x, y)`: yards to pixels via `C_Minimap.GetViewRadius()` and
`Minimap:GetWidth() / 2`; with CVar `rotateMinimap`, rotated by `GetPlayerFacing()`
(x' = e·cos f + n·sin f, y' = n·cos f − e·sin f, as HereBeDragons-Pins). Forever's minimap is
round (Camelot `Skin.lua`); `GetMinimapShape() == "SQUARE"` clamps to a square. Out of range:
clamped to the edge at 60% alpha, or hidden with `minimapEdge` off. Dots glide from the previous
report to the latest over the time between reports (snap on jumps > 300 yd). The per-frame update
returns at once unless the own position, facing, zoom, a glide or the data changed
(`B.minimapDirty`), and only calls `SetPoint` when the offset changed. Hover via
`SetMouseMotionEnabled(true)` / `SetMouseClickEnabled(false)`, so minimap pings still work.

## Dots on top of each other

Friends standing together would hide each other's dot, and only the top one could be hovered.
`B.Spread` groups dots whose centres are closer than 0.8 x the dot size, measured in screen
pixels (world map: map units x canvas width/height x the canvas' effective scale, dot size =
14 x the pin's effective scale, so it holds at every zoom; minimap: its own pixel offsets, dot
size 10). Each group is spread around its middle: two side by side (0.4 x the size from the
middle), more in a small ring; the order is by gameAccountID, so dots don't swap. Each pin keeps
its group (`pin.group`); hovering any of them shows all of them in one tooltip (the hovered
friend first, the others below with their name as a line), and an open tooltip is rebuilt when
anyone in it changes (`Signature`: the revs of everyone in it). World map: the spread is
recomputed on every refresh and on zoom (`OnCanvasScaleChanged`); friends in my group keep the
offset on their live position (`pin.fanX/fanY`). Minimap: the per-frame update first checks for
any overlap without making tables (`AnyOverlap`) and only then groups; the per-dot records are
reused.

## Dots and tooltip

- **Look** (both maps): black ring + class-colour dot (`C_ClassColor.GetClassColor`), masked round
  with `Interface\CharacterFrame\TempPortraitAlphaMask`; dead: the skull
  `Interface\TargetingFrame\UI-TargetingFrame-Skull` (60% for ghosts); in combat: red ring with a
  BOUNCE alpha animation. Restyled only when the friend's `rev` changed.
- **Friends in my group** (`showGroup`, on by default): Blizzard draws its own group dot for them
  (one engine `UnitPositionFrame`, `GroupMembersDataProvider`, frame level
  `PIN_FRAME_LEVEL_GROUP_MEMBER`). Ours stays on top of it: our pins use
  `PIN_FRAME_LEVEL_VEHICLE_ABOVE_GROUP_MEMBER`, the next level up, with a blue ring (combat red
  and the skull still win) and "In your group" in the tooltip. `peer.groupUnit` (party1-4 /
  raid1-40, matched by `UnitGUID` against the friend's `playerGuid`, checked with
  `C_PartyInfo.IsGUIDInGroup`) is refreshed on the tick after `GROUP_ROSTER_UPDATE` and after
  each Battle.net check. Their position is live, not the last Beacon report:
  `C_Map.GetPlayerMapPosition(mapID, unit)` (works for group members) on the world map, updated
  every frame while the map is open (`B.UpdateWorldMapGroupPins`), and `UnitPosition(unit)` on the
  minimap. Off: they're left to Blizzard's dot as before.
- **Tooltip:** name in class colour (+ `<AFK>`/`<DND>`), BattleTag without the number (from
  `C_BattleNet.GetAccountInfoByGUID`, which also gives the current level and zone), level, zone -
  subzone, dead/ghost, in combat / fighting X, tracked quest, and distance + 8-way direction (German: "m" and
  "nördlich" etc.). No race/class (the colour says it). Health can't be shared (secret);
  a secret target name becomes "".

## Death alerts and listeners

`ApplyState` notices a friend going from alive to dead or ghost (only after a first state from
them, so someone already dead when first heard of isn't announced) and returns whom they were
fighting: the target of their *previous* state if it was a combat state. A long fight sends no
new state, so the time since then doesn't matter; dying out of combat (a fall) has no killer. At
most one alert per friend per 10 s (kept in the inbox guard, so `Q2` can't reset it). On the next
tick `Alerts.lua` prints "<skull> Anna died in Duskwood - Raven Hill, fighting Stitches." (English,
like all chat output; zone from Battle.net, subzone from the state) when `deathAlert` is on.

`B.Notify(kind, peer, data)` tells other modules about friends' events on the driver tick:
`"level"` (`{ level }`), `"death"` (`{ where, foe, level }`) and `"highlight"` (`{ kind, a, b }`),
also when the chat line or toast is switched off. Register with `table.insert(ns.Beacon.listeners, fn)`.

## How many enemies

In combat the sender counts the enemies that have them on their threat list: nameplate units
(kept in a set from `NAME_PLATE_UNIT_ADDED`/`REMOVED`, the handlers only touch the set) that
`UnitCanAttack` and for which `UnitThreatSituation("player", unit)` isn't nil. Once a second at
most, only in combat and with `share` on; `C2;<count>` goes out when the number changes (a fight
starts at 0, so a fight without nameplates sends nothing). If the game keeps threat secret
(`SecretWhenUnitThreatStateRestricted`, e.g. in some instances) there's no count. Limits: only
mobs with a nameplate (enemy nameplates on, in nameplate range) are counted. Receivers keep
`peer.mobs` until a state without the combat flag clears it; the dot shows the number at its
bottom right, the tooltip "Fighting Hogger and 2 more" / "In combat with 3 enemies".

## Level progress

`X2;<percent>`: whole percent of the current level (`UnitXP / UnitXPMax`, at most 99), empty at
max level (`IsPlayerAtEffectiveMaxLevel`) or with `share` off. `PLAYER_XP_UPDATE` and
`PLAYER_LEVEL_UP` only set a flag; the tick checks at most every 2 s and sends only when the
message differs (a kill rarely moves the whole percent). Hellos are answered with it. Tooltip:
"Level 20 (64%)", or just the level without it.

## Tracked quest

The quest a friend is on, for the tooltip: the super-tracked one (`C_SuperTrack.
GetSuperTrackedQuestID`, the arrow), else the first on the tracker
(`C_QuestLog.GetQuestIDForQuestWatchIndex(1)`), as `T2;<questID>;<done>;<title>;<objective>`:
done 1 = ready to turn in (`C_QuestLog.IsComplete`), objective = the first unfinished one's text,
title and objective cleaned to 64 bytes; `T2;0;;;` = none, or `shareQuest` off. Its own message
rather than more `S2` fields: older builds parse `S2` strictly and would drop the whole state.
`QUEST_LOG_UPDATE` (which fires often), `QUEST_WATCH_LIST_CHANGED` and `SUPER_TRACKING_CHANGED`
only set a flag; the tick builds the message at most every 2 s and sends it only when it
differs from the last one. A hello is answered with it too. Tooltip: "Quest: <title>" in gold,
then the objective or "Ready to turn in", and "You have this quest too" when it's in my log
(`C_QuestLog.GetLogIndexForQuestID`).

## Map pings

Alt+click on the world map (or `/lefthy beacon ping` for where you stand) sends
`P2;<continent>;<north>;<west>;<uiMapID>` to every peer: the world position as in the state
message, and the zone for its name (`C_Map.GetMapInfoAtPosition` picks the zone under the cursor
on a continent map; receivers name it with `C_Map.GetMapInfo` in their own language). The click
is caught with `WorldMapFrame.ScrollContainer:HookScript("OnMouseDown")`: a post-hook, so
Blizzard's click handling (canvas click handlers, navigation, zoom) runs first and untainted;
mouse *down* because mouse up may zoom into the zone and move what's under the cursor. Not a
canvas click handler: those run inside Blizzard's click code, which would carry on tainted.
Own pings at most every 1.5 s; received ones at most one per friend per 2 s, malformed ones
dropped by `Parse`.

Every ping (`B.pings[gameAccountID or "me"]`, a newer one from the same sender replaces it) shows
for 60 s on the world map (own data provider, `LefthyToolsBeaconPingPinTemplate`) and the minimap
(frames placed by `Dots.lua`'s minimap update through `B.MinimapOffset`, the same projection and
edge rule as the dots): the game's "look here" ping icon (`Ping_Marker_Icon_NonThreat`; a plain
round marker if the atlas is missing) over a ripple in the sender's class colour (scale + alpha
animation, first 10 s), fading out over the last 10 s. Hover: whose, how old, zone, distance.
Receiving prints "Anna pinged a spot in Elwynn Forest: see your map." and plays
`SOUNDKIT.MAP_PING`. `B.UpdatePings` on the driver tick expires and fades them and redraws the open
map when the list changed. Setting `pings` switches sending, showing and the Alt+click off (the
hook stays, it checks the setting).

## Level-ups

`PLAYER_LEVEL_UP` → `L2` to every peer with the own `dingText` (empty = each receiver's localized
default "{name} reached level {level}!"; the text is edited in a settings text field or with
`/lefthy beacon ding`). Receiving: a toast (own frame, `GameFontNormalHuge`, top centre, 5 s +
1.5 s fade), a chat line, and the sound picked in the "Level-up sound" dropdown (`dingSoundKit`),
falling back to 18019 (`UI_BNET_TOAST`) if `PlaySound` returns false. `{name}` becomes the
class-coloured name. Sounds offered are ones Forever's own UI plays, so the client has them: boss
defeated fanfare 50111 (default; `BossBannerToast.lua`), world quest complete 73277, legendary
loot 63971, epic loot 31578, scenario complete 31754, garrison follower chime 46893. Not offered:
the level-up fanfare 888, which sounds like the player levelled. Picking one plays it on the next
frame.

## Open questions (check in game)

- The settings text field (custom list element), `SendGameData` limits, and whether
  `UnitPosition` agrees with the map route on Forever (otherwise the minimap uses the slower map
  route every frame).
