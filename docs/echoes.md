# Echoes design

A recorder: the way you travel and what happens on it (level-ups, quests, kills, loot, deaths and
more), written as lines of text and cut into pages that are kept in `LefthyToolsEchoesDB`, for a
program outside the game (an exporter) to read. Friends' clients can carry pages to whoever
collects them, through Beacon. Nothing shows in game.

## Overview

- **On by default; the module's switch is the recording's.** Switched off, nothing is recorded and
  nothing runs (no driver, no events).
- **Data from the beta never counts.** On the beta (`LT.world == "beta"`) Echoes stays switched on
  but idle: `E.recording` is false, the driver is hidden and no event is registered. On the release,
  or when it isn't known which client this is, it records. Its saved table is in Core's `SAVED`
  list, so the beta's table goes on the release (architecture.md, The beta and the release).
- **Never lags the client.** Event handlers only note things or append a few numbers; the driver's
  tick does the rest, and each subscriber throttles itself. Nothing runs per frame, and nothing
  that touches Blizzard frames runs in combat.
- **Its own event frame.** Chronicle, the Bestiary and Beacon unregister their events when switched
  off; Echoes records anyway. It reuses Core's plain helpers, which work whatever is switched on:
  `LT.Position`, `LT.CreatureOf`, `LT.OwnLoot`, `LT.Hash32`, `LT.Names`, `LT.Value`, and Misc
  Tweaks' `ns.FlightTime.Pick`.
- **Secret values** are skipped, never stored.

Files, in `Modules/Echoes/`, in the order they load (the TOC):

| File | What |
|---|---|
| `Echoes.lua` | the module (`ns.Echoes` = `E`), its settings, the saved table, its events (`E.On`), its driver (`E.OnTick`), starting and stopping (`E.When`) |
| `Lines.lua` | the line encoder: every recorded thing as one line (`E.Line`, `E.Anchor`, `E.Point`, `E.Mode`, `E.Zone`, `E.Name`), the pages' side of it (`E.PageStart`, `E.Raw`, `E.Continue`, `E.OnLine`, `E.Take`), the clock (`E.Now`) |
| `Path.lua` | the capture's path: polls, the store rule, travel modes, segments and their causes, the zone, the session lines; what the capture files share (`E.capture`) |
| `Events.lua` | the capture's events: level-ups, quests, deaths, kills, loot, gathering, collections, bosses, flights |
| `Changes.lua` | what the capture compares with what it wrote before: XP, AFK, group, gear, reputation, professions, the hearthstone, honor, dungeons and battlegrounds, /played |

What the files share (`E`):

- `E.recording`: whether Echoes records right now (switched on, not on the beta).
- `E.On(event, handler[, unit])`: `handler(...)` runs for `event` on Echoes' own frame, after the
  handlers added before it, each through `LT.Guard` (one that fails is reported once and rests; the
  others still run). With `unit`, a unit event for that unit only. Registered while recording (one
  added while recording at once); an event the client doesn't know is skipped quietly.
- `E.OnTick(fn)`: `fn(now)` on every tick of the driver, 4 a second while recording (`now` =
  `GetTime()`), each through `LT.Guard`. Subscribers throttle themselves. The driver resets its timer
  before the tick, so an error can't make it run every frame.
- `E.When("start" | "stop", fn)`: `fn()` once recording has started (login with Echoes on, or
  switched on: events registered, driver running), or just before it stops (switched off; still
  recording, so it can write its last lines), through `LT.Guard`.
- `E.data`: `LefthyToolsEchoesDB` (below); `E.driver`: the driver frame (for tests).

**Settings** (`LefthyToolsDB.settings.echoes`), for the delivery (not built yet):

| Setting | Default | What |
|---|---|---|
| `relay` | on | Relay friends' recordings: keep Battle.net friends' pages for a while and pass them on to whoever collects them |
| `collect` | off | Collect recordings: gather friends' pages (and your own from other computers) for the exporter |

## Recording

The capture writes everything through the line encoder (Line format): `Path.lua` the path and the
session, `Events.lua` what happens, `Changes.lua` what's compared with what was written before.
They share `E.capture`: `Spot()` (before an event: the path brought up to now), `NoteCause(why,
spell)`, `CheckMode()`, `Ready()` (the session's anchor is written), `Cap()` (this character's
saved baselines), `Flush()` (Events.lua's queue), `Instance()`, `Reset()` (what a `/reload`
forgets; for tests).

- **Never lags the client.** Handlers only note things: a flag, a slot, or a few values in
  Events.lua's queue (flat arrays, written on the tick in the order they came, each tick's events at
  one spot). Exceptions, because no tick comes in time: `PLAYER_LEAVING_WORLD` writes its last point,
  `PLAYER_LOGOUT` its last point, the queue and `o0`, and `LOOT_READY` reads the loot window's slots
  (with auto loot it's gone by the next tick). A poll makes no tables.
- **Secret values** are skipped: a secret kill, cast, loot line, quest or GUID writes nothing (a
  secret killer is unknown, a secret group member one of the others, a secret AFK answer keeps the
  last state).
- **In combat** the silent `/played` (it touches the chat frames), gear, professions and reputation
  wait until the fight is over; the path and the events don't.
- **It records with Chronicle, the Bestiary and Beacon switched off.** It keeps its own small cache
  of mobs seen (level, classification, name: target, mouseover, nameplates; the last 200), and uses
  Beacon only to know which group members are LefthyTools friends.

### The path (Path.lua)

**Polls.** `LT.Position()` every 0.5 s while moving (`IsPlayerMoving`, or 0.5 yd since the last
poll), every 1 s standing still or on a flight path (boats and teleports fire no movement events).
`PLAYER_STARTED_MOVING` and `PLAYER_STOPPED_MOVING` make the next tick poll; the poll after a stop is
the stop, however far it came since the last. Standing still that's one `UnitPosition` a second.

**The store rule**, from A, the last point written (`E.state.north`, `west`):

- distance: a point at 25 yd from A, 100 yd on a flight path;
- bend: if a sample since A lies more than 3 yd off the line from A to here (6 carried, 10 on a
  flight path), the sample before this one is stored (8 samples kept);
- start: moving again after standing still, the old spot once more, now (`dt,0,0`): else the
  site's dot would crawl from it through the whole time you stood there;
- stop: the spot where you stopped;
- a travel mode change: a point (unless you're still on A), then the `m` line;
- before an event (`E.capture.Spot`, once per tick): a point if you're 3 yd or more from A;
- before a loading screen, logging out or switching off: the last point.

At most a start point and one point per poll; a point on A again (whole yards) is left out, except
the start point.

**Travel modes**, read only on polls where the position changed (or once after coming back to
life), in this order: `t` flight path (`UnitOnTaxi`), `g` ghost (`UnitIsGhost`), `c` carried (no
transport API: the measured speed more than 3 yd/s above `GetUnitSpeed`), `s` swimming
(`IsSwimming`), `m` mounted (`IsMounted`), `v` Travel Form or Ghost Wolf (`GetShapeshiftFormID` 3 or
16; Aquatic Form shows as swimming), `f` on foot. Swimming flickers at the surface and the carried
guess can be a knockback: a change to or from `s` or `c` needs the same answer on two polls in a
row (not to `t` or `g`). An anchor's mode is read as it is then (never `c`).

**Segments.** A new one (an anchor) starts:

| When | Why |
|---|---|
| a session starts: login, switched on | `s` |
| a loading screen ends (`PLAYER_LEAVING_WORLD` writes the last point, the next tick after `PLAYER_ENTERING_WORLD` the anchor, as soon as the game says where you are, at most 3 s later) | what caused it, else `i` (an instance entered), `o` (left), `l`; a `/reload`: `l` |
| a jump of more than 50 + 40 * seconds yd between two polls (the seconds at most 5) | what caused it, else `j` |
| another continent | what caused it, else `j` |
| the position gone (an anchor without one: the instance's map ID, else the last continent) or back | what caused it, else `j` |
| released: the ghost at the graveyard (the first poll it moved, at most 1 s after `PLAYER_ALIVE` as a ghost; polled every tick meanwhile) | `r` |
| a new page that didn't go on from the last (no anchor on the page: `E.Continue` wasn't called) | `c` |

What caused it, from what was noted shortly before (used once, then forgotten): `h` the hearthstone
(your cast of 8690 within 20 s; the spell's field 8690), `p` a teleport spell within 20 s (the
mage's teleports 3561-3567, Astral Recall 556, Teleport: Moonglade 18960, the engineers'
Dimensional Ripper - Everlook 23442 and Ultrasafe Transporter: Gadgetzan 23453; the spell's
field), `u` a summon (`CONFIRM_SUMMON` within 120 s), `r` released (within 20 s). In an instance
(no positions: dungeons, raids) the anchor has none and no points follow until the next anchor with
one; battlegrounds have positions.

**The zone** (`z`): on the zone events and every 10 s, `C_Map.GetBestMapForUnit` and
`GetSubZoneText`, a line when either changed (after a session's anchor always).

**The session** (`o`): `o1` after a session's anchor and zone (login, a `/reload`, switched on);
`o0` at `PLAYER_LOGOUT` and when switched off. `PLAYER_LOGOUT` comes on a `/reload` too and can't be
told from logging out: a `/reload` writes `o0`, then `@...;l` and `o1` a few seconds later. An `o1`
after an anchor with why `l` (not `s`) is a `/reload`: the session goes on (the exporter can join
them).

### What happens (Events.lua)

| Line | Detection |
|---|---|
| `L` level; played | `PLAYER_LEVEL_UP`; played: the time played (Changes.lua), whole seconds |
| `a` / `Q` / `A` | `QUEST_ACCEPTED`; `QUEST_TURNED_IN` (xp, money); `QUEST_REMOVED`: 1.5 s later, abandoned (`A`) unless it was turned in, or turned in (`Q` without xp and money) when `C_QuestLog.IsQuestFlaggedCompleted` says so. The title (`=q`) from `C_QuestLog.GetTitleForQuestID`, kept from when it was accepted |
| `D` | `PLAYER_DEAD`, once until alive again (and 10 s after: the game repeats it). The killer: your attackable target in the last fight within 15 s (looked at every tick in combat): a creature (`c`, its ID, level, classification; its name `=c`), a player (`p`, class and level, no name; pvp 1), a player's pet or a secret GUID (`-`) |
| `r` | `PLAYER_UNGHOST`: `s` after `CONFIRM_XP_LOSS` (the spirit healer, within 120 s), `p` after `RESURRECT_REQUEST` (within 70 s), else `c`; `PLAYER_ALIVE` alive without having released: `p` or `c`. Then the mode is read again |
| `k` | `PARTY_KILL` by me, my pet (`UnitGUID("pet")`) or a group member (`C_PartyInfo.IsGUIDInGroup`), of a creature; each corpse once (the last 64). Level, classification (`n e r x w`; trivial and minus are `n`) and name from the mob cache |
| `l` | `CHAT_MSG_LOOT` through `LT.OwnLoot`, quality 2 and better: item, count, quality, `l` looted or `p` pushed, and the creature whose corpse the last loot window (within 5 s) said it came from; the item's name (`=i`) from the link |
| `h` | `UNIT_SPELLCAST_SUCCEEDED` (player) with Herb Gathering, Mining or Skinning (each rank's ID, other ranks by name), then `LOOT_READY` within 1.5 s; or `IsFishingLoot()`. The node: the loot source's game object ID (herbs, ore, fishing), the creature for skinning; each node once (the last 32). Then one `item:count` field per item |
| `n` | `NEW_MOUNT_ADDED` (`m`), `NEW_PET_ADDED` (`p`: its species, `C_PetJournal.GetPetInfoByPetID`), `NEW_TOY_ADDED` (`t`), `ACHIEVEMENT_EARNED` (`a`, not one earned before), `NEW_RECIPE_LEARNED` (`r`) |
| `B` | `ENCOUNTER_END` (success) and `BOSS_KILL`: the same encounter within 30 s once |
| `F` | a post-hook on `TakeTaxiNode` (like Flight.lua's): `ns.FlightTime.Pick`'s taxi node IDs, from and to |
| `b` won / lost | `PVP_MATCH_COMPLETE`, else `GetBattlefieldWinner()` every 5 s in a battleground: 0 the Horde, 1 the Alliance against your faction; the match's length (or the time since you entered); once |

### Compared with what was written (Changes.lua)

The baselines are kept per character, `E.data.capture[<GUID>]`, so a `/reload` or the next login
writes only what changed. A session's start looks at everything once.

| Line | Detection | Kept |
|---|---|---|
| `x` | every 60 s, at a session's start, on `PLAYER_UPDATE_RESTING` and level-ups: `UnitLevel`, `UnitXP`, `UnitXPMax`, `GetXPExhaustion` (none: 0), `IsResting`; when one changed | `xp` (the last line's values) |
| `f` | `PLAYER_FLAGS_CHANGED` (player), `UnitIsAFK`; when it changed (a secret answer keeps the last) | |
| `g` | `GROUP_ROSTER_UPDATE`: `GetNumGroupMembers`, the members' GUIDs (`party1-4` or `raid1-40`, not me); a friend is a Beacon peer (`ns.Beacon.peers`, Beacon on) or remembered: `guid:First-Realm` (the realm `GetPlayerInfoByGUID` says, else mine), sorted; the others counted. Left the group: `g;0;0` | `group`; `E.data.friends[guid]` = "Anna-Realm" (named while Beacon is off) |
| `G` | `PLAYER_EQUIPMENT_CHANGED` marks a slot, a session's start all 19; out of combat `GetInventoryItemLink`: item, enchant (the link's second field), suffix (seventh), 0 when none; taken off: item 0; the name `=i` | `gear[slot]` |
| `R` | `FACTION_STANDING_CHANGED` names a faction; a session's start and `UPDATE_FACTION` (at most every 10 s) scan the listed factions (`C_Reputation.GetNumFactions`, `GetFactionDataByIndex`; headers left out); out of combat; the reaction 1-8. A character's first scan is the baseline: no lines | `reps[faction]`, `repsKnown` |
| `s` | `SKILL_LINES_CHANGED` and a session's start; out of combat `C_SkillInfo.GetSkillLineInfoByID` for the 12 Classic professions: rank and maximum; unlearned (rank 0): `0;0` | `skills[id]` |
| `H` | `HEARTHSTONE_BOUND` and a session's start: `GetBindLocation()` (a place's name) | `bind` |
| `p` | `PLAYER_PVP_KILLS_CHANGED`: `GetPVPSessionStats()`, the kills since the last line (a session's start is the baseline) | |
| `d` / `b` | after each anchor of a loading screen or a session: in a `party` or `raid` instance (`IsInInstance`, `GetInstanceInfo`: the instance ID, difficulty) `d;e;...`, left `d;x;...`; a `pvp` one `b;<id>;e`, left `b;<id>;x;<seconds>`. Kept across a `/reload` and logging out | `dungeon` { id, difficulty }, `bg` { id, entered, result written } |

**The time played** (`played`, seconds): asked once per login (`PLAYER_ENTERING_WORLD` with
`isInitialLogin`), out of combat, silently: the chat frames that show `TIME_PLAYED_MSG`
(`ChatFrame1-10`, `IsEventRegistered`) don't get it until the answer is in (at most 10 s, then out
of combat again). Between answers, and when the request isn't answered, the ticks add up the time
recorded. A `/played` you type sets it too.

### The pages' side

- The capture writes its first line on the first tick after recording starts (or after a loading
  screen). A page's header and character line go before it: write them when recording starts
  (`E.When("start")`) or at load, not on a tick.
- At a new page, `E.Continue()` goes on from the last point written (the capture's A, so its
  points go on from it). Without it, the capture's next poll writes an anchor itself (why `c`).
- At `PLAYER_LOGOUT` (and switching off) the capture writes its last point, what it still holds and
  `o0` in its handler (`E.On`, added at load): a page's handler that takes the buffer must be added
  after it (a file loaded after `Changes.lua`, or `E.When("stop")` hooks added after it).

### Check on launch day

Whether `GetShapeshiftFormID` is 3 and 16 for the travel forms; the carried guess on a boat and a
zeppelin; whether the silent `/played` stays silent; which of `QUEST_REMOVED` and
`QUEST_TURNED_IN` comes first; `PARTY_KILL` for pets and group members; the gathering spell IDs and
`GetLootSourceInfo`'s game object GUIDs for nodes and fishing; `PVP_MATCH_COMPLETE`'s winner (0 the
Horde, 1 the Alliance, like `GetBattlefieldWinner`); `NEW_RECIPE_LEARNED`, `NEW_MOUNT_ADDED` and
`FACTION_STANDING_CHANGED` firing; `C_SkillInfo.GetSkillLineInfoByID` for professions not learned
(nil, or rank 0: only rank 0 is taken as unlearned).

### Tests

`tests/echoes_capture.lua` (after `echoes.lua`): a session starting, the store rule (distance,
bends, start and stop, the idle crawl fix, an event's spot, `UnitPosition` once a second), every
travel mode (swimming's flicker, the carried guess), every segment and cause, instances, every
event kind as its exact line, secret values, nothing in combat that must wait, a `/reload`
(`E.capture.Reset`), Chronicle, the Bestiary and Beacon off, the beta, and a whole session read back
(times and positions add up line after line). It leaves `ECHOES_CAPTURE_SESSION` (the page and its
times and positions) for a check with the exporter's parser outside this repo.

## Line format

The recording is cut into **pages** (Pages and storage). A page is immutable once closed; it is the
unit that is stored, sent, relayed, acknowledged and exported.

- One record per line, UTF-8.
- A line starting with a digit is a path point. Any other line is `<kind><dt>;<field>;...`.
- Time is cumulative: each line's time is the previous line's time plus its `dt`, and the header
  sets the start. Times are whole seconds of the realm's clock (`GetServerTime()`, the same for
  every friend, so all of them fit on one timeline).
- Coordinates in points are deltas from the previous position, in whole yards.
- Events carry no coordinates: their spot is the path position at that moment (the capture stores a
  point first if the last one is stale).
- Each page stands alone. It starts with the header, the character, an `@` anchor and the current
  zone, and repeats every name it uses.

```
E1;1a2b3c4d;9f3a61c2;214;1793452800;deDE;70532;0.7.0-12-gabc1234   header: format, acct, store, n, t0, locale, build, addon
C0;Anna-Realm;Anna Brook;Player-1234-0ABCDEF0;MAGE;Human;2;12;Alliance   character: key, full name, GUID, class, race, sex, level, faction
@0;0;-9046;-160;f;s                anchor: dt; continent; north; west; mode; why[; spell]
z0;1429;Goldshire                  zone: uiMapID; subzone text
2,-5,-13                           point: dt,dnorth,dwest
2,-8,-11
=9;c;327;Kobold Vermin             name: namespace (c creature, q quest, i item); id; text
k0;327;5;n;m                       kill: creature; level; classification; who
m3;m                               mode change
Q12;7;250;40                       quest turned in: id; xp; money
@5;0;-8950;-60;f;h;8690            hearthstone: new segment, no line drawn
@3;36;;;f;i                        instance entered: no position until the next @
!0;1793452830                      clock set (only when the clock went back)
.1;t                               page end: reason t time, s size, l stale at login
```

The header's `E1` is the format (1), not a kind with a `dt`; it is always the page's first line.
`t0` is the page's start, the header's time.

**Lines every page has**

| Line | Meaning | Fields |
|---|---|---|
| `E` | header (first line; `E` and the format) | acct; store; n; t0; locale; build; addon version |
| `C` | the character | key (first name-realm); full name; GUID; class; race; sex; level; faction |
| `@` | anchor: a new segment of the path, no line drawn from the point before | continent (the instance map ID: 0 Eastern Kingdoms, 1 Kalimdor, a dungeon's); north; west (whole yards, empty where there is no position: no points until the next anchor with one); mode; why; spell |
| `z` | zone | uiMapID; subzone text (the client's language: pages carry the locale) |
| (digit) | path point | `dt,dnorth,dwest` |
| `=` | a name, once per page for each namespace and id | namespace (c creature, q quest, i item); id; text |
| `m` | travel mode changed | mode |
| `!` | clock set: the time is this, absolute (the encoder writes it when the clock went back) | time |
| `.` | page end | reason: t time, s size, l stale at login |

**Travel modes** (the `@` and `m` lines): t flight path, g ghost, c carried (boat, zeppelin), s
swimming, m mounted, v travel form, f on foot.

**Why a segment starts** (the `@` line's `why`):

| Code | Cause |
|---|---|
| h | hearthstone (field: spell) |
| p | teleport spell (field: spell) |
| u | summon |
| r | release to graveyard |
| i | instance entered |
| o | instance left |
| s | login |
| l | loading screen |
| j | other jump (someone else's portal, say) |
| c | continued: the first anchor of a new page, at the last page's last position (the path goes on) |

**Event kinds** (letters can still change while they're being built):

| Line | Meaning | Fields |
|---|---|---|
| `L` | level-up | level; played seconds |
| `x` | XP | level; xp; max; rested; resting 0/1 |
| `a` / `Q` / `A` | quest accepted / turned in / abandoned | id (/ xp; money) |
| `D` | death | level; killer kind c/p/-; creature id or class; killer level; classification; pvp 0/1 |
| `r` | back to life | how: s spirit healer, p player, c corpse |
| `k` | kill | creature; level; classification; who m/p/g |
| `l` | loot | item; count; quality; l looted / p pushed; source creature |
| `g` | group | size; others; then one field per friend: guid:Name-Realm |
| `G` | gear | slot; item; enchant; suffix |
| `f` | AFK | 1 start / 0 end |
| `R` | reputation | faction; standing |
| `h` | gathering | kind h/o/s/f; node or creature; then one field per item: item:count |
| `p` / `b` | honorable kills / battleground | count / instance; e entered, x left, w won, l lost; duration |
| `n` | new collection item | kind m/p/t/a/r (mount, pet, toy, achievement, recipe); id |
| `s` | profession | skill; rank; max |
| `H` | hearthstone bound | place |
| `F` | flight | from node; to node |
| `d` / `B` | dungeon / boss | e entered or x left; instance; difficulty / encounter id |
| `o` | session | 1 login, 0 logout |

**Readers must**
- skip unknown kinds but still add their `dt`, so new kinds never break an older exporter;
- ignore extra fields and treat missing ones as empty.

**Fields**
- WoW's markup is removed first: textures (`|T...|t`), atlases (`|A...|a`), colours (`|cAARRGGBB`,
  `|cn<name>:`, `|r`); a link (`|H...|h[text]|h`) becomes its text without the brackets. The capture
  stores links as ids.
- Then `%`, `;`, `,`, `|` and bytes below 0x20 are written as `%XX` (upper-case hex). Everything else
  stays as it is, UTF-8 letters too.
- Numbers: whole ones as integers (`-9046`, `1793452800`, never `-0` or `1e+10`), others with at
  most two decimals (`3.25`); not-a-number and infinity are empty. `true` is 1, `false` 0.
- nil, a secret and anything else are empty; empty fields at the end of a line are left out.

Second-order deltas (velocity changes) were tested and saved only 3% after compression, so points
stay plain deltas.

**The encoder** (`Lines.lua`). Nothing is written while Echoes doesn't record (switched off, or the
beta): the writers return nil (`E.Name` false).

- `E.Now()`: the time lines are written in, `GetServerTime()` (the computer's `time()` if it's
  missing), whole seconds.
- `E.Line(kind, ...)`: writes `kind .. dt .. ";" .. fields` and returns the line. `kind` is one
  letter or `@ = ! .` (anything else is an error). `dt` is the seconds since the last line; if the
  clock went back (or no line has a time yet), `!0;<now>` goes first and the line gets `dt` 0.
- `E.Anchor(continent, north, west, mode, why, spell)`: an `@` line; north and west are rounded to
  whole yards (both nil: an anchor without a position). The next points count from it.
- `E.Point(north, west)`: a point, `dt,dnorth,dwest` from the last position (whole yards). Nothing
  before the page's first anchor, after an anchor without a position, or for a position that isn't
  a readable number.
- `E.Mode(mode)`, `E.Zone(uiMapID, subzone)`: the `m` and `z` lines.
- `E.Name(namespace, id, text)`: an `=` line once per page per namespace and id; true if written
  now (false: already named, or no text or id). `E.ResetNames()` names everything again.
- For the pages: `E.PageStart(t0)` (the next line's `dt` counts from `t0`, now if nil; names
  again; points wait for an anchor; `E.bytes` and `E.count` start at 0), `E.Raw(line)` (a line as
  it is: the header), `E.Continue()` (an `@` line with why `c` at the last position known, the mode
  and the zone again; false and nothing written when nothing is known yet), `E.OnLine(fn)`
  (`fn(line, kind)` after every line, through `LT.Guard`; `kind` nil for points and raw lines;
  hooks only note things, a page is closed on the tick), `E.Take()` (the lines not taken yet as text,
  each ending in `\n`, and the buffer emptied).
- `E.buffer`: the lines not taken yet (strings without `\n`: no concatenation per point);
  `E.bytes` / `E.count`: bytes (with each `\n`) and lines since the page started.
- `E.state`: what the encoder keeps, a plain table every function reads anew (the pages may keep it
  with an open page and put it back after a `/reload`): `t` (the last line's time), `anchored`,
  `continent`, `north`, `west` (the last position written), `mode`, `map`, `sub` (the last zone),
  `names` (`"c:327" = true`).

## Pages and storage

`LefthyToolsEchoesDB`, account-wide, made at load (`LT.onLoad`, after Core's stamp):

```lua
LefthyToolsEchoesDB = {
  world = "release",  -- Core's stamp
  v = 1,              -- the layout
  store = "9f3a61c2", -- 8 random lowercase hex digits, made once: this WTF folder's
  acct = "1a2b3c4d",  -- my BattleTag's hash (LT.Hash32 of the lowercased BattleTag), filled in later
  session = 41,       -- +1 at every load (a /reload too): what came this session, what's on disk
  n = 213,            -- the last closed page's number (0: none yet)
  open = nil,         -- the page being written (plain text, never shared); nil: none
  mine = {},          -- my closed pages
  carry = {},         -- friends' pages I relay
  safe = {},          -- what collectors hold safely
  inbox = {},         -- a collector's: pages received
  exported = {},      -- a collector's: pages the exporter has
}
```

A field that isn't what it should be is made new (a table that isn't one, a store that isn't 8 hex
digits); nothing else is touched. Pages themselves are not built yet.

## Delivery

Not built yet: the `B2;e...` messages through Beacon, pulling, relaying and collecting, driven by
the settings above.
