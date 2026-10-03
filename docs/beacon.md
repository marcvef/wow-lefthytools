# Beacon design

Battle.net friends who also run LefthyTools see each other on the world map and minimap, with
status (dead/ghost, in combat, who they're fighting), and get each other's level-ups. Only
Battle.net friends; each player writes their own level-up message.

Files: `Beacon.lua` (module, protocol, rate limiter, settings, `/lefthy beacon`), `Dots.lua` (dot
look, tooltip, world map provider, minimap pins), `Ding.lua` (level-up messages, toast, sounds),
`Beacon.xml` (world map pin template). They share state through `ns.Beacon` (`B`): `B.peers`,
`B.Clean`, `B.QueueToPeers`, `B.MyWorldPosition`, and hooks the other files set (`B.RefreshMaps`,
`B.UpdateMinimap`, `B.Attach`/`B.Detach`, `B.ShowDing`, `B.AnnounceLevel`, `B.OnSettingChanged`).

## Transport and protocol

- Addons have no network access, so there's no server. Messages go through
  `C_BattleNet.SendGameData(gameAccountID, "LTBeacon", data)` and the `BN_CHAT_MSG_ADDON` event
  (prefix, text, channel, senderID = sender's gameAccountID); the prefix is registered with
  `C_ChatInfo.RegisterAddonMessagePrefix`. Result `AddonMessageThrottle` (3) pauses sending for
  2 s and keeps the message; other failures drop it (the next state or heartbeat covers it).
- **Protocol v2** (`;`-separated; the digit after the kind is the version): `H2` hello,
  `S2;<flags>;<continent>;<north>;<west>;<subzone>;<target>` state (flags D dead, G ghost,
  C combat; position empty in instances or with sharing off; target only in combat),
  `L2;<level>;<text>` level-up, `Q2` switched off. A hello is answered with the state. A message
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

## Dots and tooltip

- **Look** (both maps): black ring + class-colour dot (`C_ClassColor.GetClassColor`), masked round
  with `Interface\CharacterFrame\TempPortraitAlphaMask`; dead: the skull
  `Interface\TargetingFrame\UI-TargetingFrame-Skull` (60% for ghosts); in combat: red ring with a
  BOUNCE alpha animation. Restyled only when the friend's `rev` changed. Group members are skipped
  on both maps (`IsGUIDInGroup(playerGuid)`); Blizzard draws them.
- **Tooltip:** name in class colour (+ `<AFK>`/`<DND>`), BattleTag without the number (from
  `C_BattleNet.GetAccountInfoByGUID`, which also gives the current level and zone), level, zone -
  subzone, dead/ghost, in combat / fighting X, and distance + 8-way direction (German: "m" and
  "nördlich" etc.). No race/class (the colour says it). Health can't be shared (secret);
  a secret target name becomes "".

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
