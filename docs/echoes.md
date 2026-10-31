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
| `Store.lua` | the closed pages (`E.Store`: packing, what's kept, the API for the delivery), range strings (`E.Ranges`), the exporter's receipt, `/lefthy echoes` (`E.Command`, `E.OnStatus`) |
| `Pages.lua` | the open page: starting, joining, closing, going on after a `/reload`; my account (`E.MyAccount`) and character (`E.Character`) |
| `Delivery.lua` | pages from friends to the collector through Beacon (`E.Delivery`): the `B2;e...` messages, pulling, relaying, collecting, what's safe, the budget, the probe (Delivery, below) |

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

**Settings** (`LefthyToolsDB.settings.echoes`), for the delivery (Delivery, below):

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
guess can be a knockback or a Blink: a change to or from `s` or `c` needs the same answer on two
polls in a row (not to `t` or `g`; a poll standing still, which doesn't read the mode, breaks the
row). The stop's poll never guesses `c` (the game's speed is 0 by then, however far it came since
the last poll). An anchor's mode is read as it is then (never `c`).

**Segments.** A new one (an anchor) starts:

| When | Why |
|---|---|
| a session starts: login, switched on | `s` |
| a loading screen ends (`PLAYER_LEAVING_WORLD` writes the last point, the next tick after `PLAYER_ENTERING_WORLD` the anchor, as soon as the game says where you are, at most 3 s later) | what caused it, else `i` (an instance entered), `o` (left), `l`; a `/reload`: `l` |
| a jump of more than 50 + 40 * seconds yd between two polls (the seconds at most 5) | what caused it, else `j` |
| another continent | what caused it, else `j` |
| the position gone (an anchor without one: the instance's map ID, else the last continent) or back | what caused it, else `j` |
| released: the ghost at the graveyard (the first poll it moved, at most 1 s after `PLAYER_ALIVE` as a ghost, once per death; polled every tick meanwhile) | `r` |
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
| `D` | `PLAYER_DEAD`, once until alive again (and 10 s after: the game repeats it). Logged in or `/reload`ed dead or a ghost (`UnitIsDeadOrGhost` when recording starts; no `PLAYER_DEAD` comes then): that death was counted before, its release and coming back still are. The killer: your attackable target in the last fight within 15 s (looked at every tick in combat): a creature (`c`, its ID, level, classification; its name `=c`), a player (`p`, class and level, no name; pvp 1), a player's pet or a secret GUID (`-`) |
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
  whole yards (either one nil or not a readable number: an anchor without a position; a secret
  continent is empty). The next points count from it.
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
  open = {            -- the page being written (plain text, never shared); nil: none
    n = 214, t0 = 1793452800, char = "Anna-Realm", guid = "Player-...", acct = "1a2b3c4d",
    own = 4,            -- its own lines (header, character, going on): nothing else, it doesn't close by time
    busy = 1793452801,  -- when a line other than its own came (its 30 minutes run from then); nil: none yet
    text = "E1;...\n...\n", -- the lines joined so far
    buffer = { ... },   -- the lines not joined yet: E.buffer itself
    state = { ... },    -- the encoder's state: E.state itself
  },
  mine = {            -- my closed pages
    [212] = { t = 1793451000, h = "5e1f09aa", m = "z", z = "eJzt...", s = 40 },
    [213] = { t = 1793452700, m = "t", z = "E1;...", q = 1, s = 41 }, -- closed, waiting to be packed
  },
  carry = { ["5e6f7a8b.0c77e1f2"] = { [57] = { t, h, m, z, s = 41, a = 1793450000 } } }, -- friends' pages I relay
  safe = { ["5e6f7a8b.0c77e1f2"] = { ["c011ec70.12345678"] = "1-56" } },              -- collectors' summaries
  inbox = { ["5e6f7a8b.0c77e1f2"] = { [58] = { t, h, m, z, s = 41 } } },                 -- a collector's: received
  exported = { ["5e6f7a8b.0c77e1f2"] = "1-50" },                                         -- a collector's: from receipts
  capture = { ["Player-..."] = { ... } },  -- the capture's baselines per character (Recording)
  friends = { ["Player-..."] = "Bob-Realm" }, -- LefthyTools friends' names (Recording)
}
```

A field that isn't what it should be is made new (a table that isn't one, a store that isn't 8 hex
digits); nothing else is touched, except that a stored page without its text (`z`) goes when the
sizes are counted (when recording starts). A stored page is `{ t, h, m, z }`:

- `t`: its start (the header's t0).
- `m`: how `z` holds it: `z` Base64 of its zlib, `r` Base64 of the text (compressing failed), `t`
  the text (Base64 failed too: kept and exported, never shared).
- `z`: the page. The game never decompresses one (an output without a limit): only the exporter does.
- `h`: `LT.Hash32(z)`, the hash of what's stored (none while it waits).
- `q`: closed, waiting to be packed (`m` is `t` meanwhile).
- `s` (mine): the session it closed in (the session before for a page closed as stale at login
  from the saved text; none: from a build before the rule, on disk); (carry, inbox): the session
  it came in. `a` (carry): when it came.

**Files.** `Store.lua` (the closed pages, what's kept, the receipt, `/lefthy echoes`) loads before
`Pages.lua` (the open page). Both load after the capture's files, so at logout and when switched off
the capture's handlers write their last lines before the pages join them. The header still comes
first: the capture writes nothing when recording starts (its first line comes on the first tick).

### The open page (Pages.lua)

The page id is `<acct>.<store>.<n>`: my account, this WTF folder's store, and `n`, one more than the
last closed page's (`E.data.n`), so they're dense and holdings are ranges like `1-56,58`.

**When recording starts** (login, `/reload`, switched on), the open page from before:

- goes on if it's this character's (key and GUID) and its last line (`state.t`) is at most 10
  minutes old: its unjoined lines are joined, `E.state` is put back, `E.bytes` and `E.count` go on;
- closes as it was otherwise: `.0;l` (stale at login, at the time of its last line). Only the cheap
  part runs there (joining the text); it's packed on a later tick. It's on disk (offered at once,
  below) when it's the saved text alone and its last line is more than 10 minutes old;
- goes unclosed if it started before the launch day (`LT.BeforeLaunch`), or can't be a page.

Then, if none is open, a new page starts: the header (`E.Raw`) and the character line. Its first
anchor is the capture's (why `s` at login, `l` after a loading screen).

- **Header:** `E1;acct;store;n;t0;locale;build;addon` (`GetLocale()`, the build from
  `GetBuildInfo()`, `LT.version`).
- **Character:** `C0;key;full name;GUID;class;race;sex;level;faction`. The key is `Name-Realm` (first
  name, `GetRealmName()`); the full name has the surname from `UnitName`, else Chronicle's record of
  it (`LefthyToolsChronicleDB.chars[key].full`), else it's the first name; class and race are the
  file names (`MAGE`, `Scourge`), the faction English.
- **Account** (`E.MyAccount()`): `LT.Hash32` of my lowercased BattleTag (`BNGetInfo`), Chronicle's
  account hash, Chronicle switched on or not. `E.data.acct` keeps the last known. While neither is
  known the header's account is empty (`E1;;9f3a61c2;...`); the tick asks again every 5 s and puts it
  into the open page's header once it's known. A page closed before keeps the empty one (closed pages
  never change); the exporter files my pages under `E.data.acct` anyway. Recording doesn't wait for
  it: Battle.net almost always answers at login, and lines must not wait for a header.

**Joining.** Lines go into `E.buffer` (one string each). The tick joins them into `open.text` every
60 s, and `PLAYER_LOGOUT` does: one concatenation a minute, never one per line. `open.buffer` is
`E.buffer` itself and `open.state` is `E.state`, so whatever is written after the logout's join (a
logout line from a handler after Echoes') is saved too, and a `/reload` goes on with the same page:
no line lost or doubled, each line's `dt` counting from the one before the reload.

**Closing**, on the tick only (never inside an event handler):

- 32 KB of text or 2,000 lines: `.<dt>;s`;
- 30 minutes after its first line other than its own (`open.busy`, noted on the tick that first
  sees one): `.<dt>;t`. Its own lines are the header, the character and, on a page that follows
  one closed mid-session, the going on (`open.own` counts them). A page with nothing else on it
  stays open however long you're away (an AFK night is one page, not one every 30 minutes); the
  stale rule at login still closes it. An open page from a build before this rule (no `own`): 30
  minutes from its start.

`E.Store.Close` keeps it (below), and the next page starts in the same tick: header, character, and
`E.Continue()` (an anchor at the last position, why `c`, the mode and the zone). The tick does
nothing else then.

### Closed pages (Store.lua)

`E.Store.Close(n, t0, text, onDisk)` keeps the text in `mine[n]` as it is (`m = "t"`, `q = 1`, `s` the
session) and `n` becomes the last closed page's number. The tick packs one waiting page at a time,
oldest first:

1. `C_EncodingUtil.CompressString(text, Enum.CompressionMethod.Zlib)`, then
   `EncodeBase64(..., Enum.Base64Variant.Standard)`: `m = "z"`;
2. compressing answers nothing or fails: `EncodeBase64(text)`, `m = "r"`;
3. Base64 answers nothing, fails or isn't Base64 (or there's no `C_EncodingUtil`): the text, `m = "t"`.

Then `h = LT.Hash32(z)` and `q` goes. That's about once in 30 minutes: zlib and Base64 in C, the hash
over 5-12 KB in Lua (about 1 ms).

**My pages go out once they're on disk.** The game writes the saved file only at a logout or
`/reload`; after a crash the next login goes on from the last save and numbers its pages from there
again. A page of the lost session that had already gone to friends would then share its id with a
different page closed after the crash: the collector keeps the first (pages never change), and its
"safe" makes the author drop the second, which is lost. So `E.Store.Mine`, `E.Store.Held("mine")`
and `E.Store.Page` for my own key offer only pages on disk: closed in an earlier session than this
one (`s`; a `/reload` starts a new session, `E.data.session`).

- **A page closed as stale at login** is on disk at once (its `s` is the session before): it's the
  saved text and nothing else, and its last line is more than 10 minutes old, so any later load of
  that save, after a crash too, closes it the same way. One closed for another character within
  those 10 minutes waits for the next session (back on the first character, a later load would go
  on with it), and so does one closed after switching Echoes off and on (it has this session's
  lines).
- **The cost:** my pages travel from the next session on (the next login or `/reload`), not the
  evening they're recorded; the author keeps every page until a collector holds it, so nothing is
  lost by the wait. `/lefthy echoes` says how many wait.
- **What's still possible:** a WTF folder copied to a second computer and played on both keeps one
  store id (it's made once per folder), so both number their pages alike and the same ids carry
  different pages. Copy a WTF folder only to move, not to play on both.

**What's kept** (design section 7):

- **mine:** until a collector holds a page safely (`E.Store.Safe`), at most 2 MB (about 250 hours).
  Over it, after every packed page and at the start, the oldest go, first the ones a relay is known
  to carry (`E.Store.Carried`, this session).
- **carry:** 512 KB in all, 128 KB per author's store (`E.Store.Put` refuses what doesn't fit), 30
  days after a page came (at the start), and dropped once a collector holds it safely.
- **inbox:** dropped only by the exporter's receipt. At 4 MB one chat line a session asks to run the
  exporter; at 8 MB `E.Store.InboxFull()` says so and the delivery stops pulling (a page still on its
  way is kept).
- **The launch day:** on the release, once `LT.LAUNCH_DAY` is set, pages that started before it go
  from mine, carry and inbox at the start, and `E.Store.Put` refuses them.

**The exporter's receipt** (collecting on): once a session, on the tick,
`LoadAddOn("LefthyTools_EchoesReceipt")` (load on demand; a folder that isn't there does nothing, and
a new one needs a game restart), then `LefthyToolsEchoesReceipt.done` (`{ ["acct.store"] = "1-57" }`):
those pages go from inbox, carry and mine, and are added to `exported`. It lists the full ranges each
time, so reading it again is harmless.

**After the start**, one a tick: a waiting page packed, else the next chore (the launch day, old
relayed pages, the 2 MB cap, the 4 MB line), else the receipt.

**Costs.** A tick: a few comparisons. A minute: one join. Half an hour: one page packed. Inside
event handlers: only the logout's join and, at login, joining a stale page's text.

### For the delivery: E.Store and E.Ranges

Every change to mine, carry and inbox goes through `E.Store` (it keeps their sizes), and each one
tells the delivery, which caches what I hold: `E.Delivery.PagesChanged()` (if Delivery.lua is
there) when a page closes, is packed (it can be shared now), kept, dropped (the cap, the 30 days,
the launch day, a receipt, `Drop`, `Safe`), when a collector's summary or what's exported grows,
and when the sizes are counted anew. Keys are `"acct.store"`, 8 hex digits each.

| Call | What |
|---|---|
| `E.Store.Key(acct, store)` | `"acct.store"`, nil if either isn't 8 hex digits |
| `E.Store.Own()` | my pages' key, nil while my BattleTag isn't known |
| `for n, page in E.Store.Mine()` | my pages I offer: shareable (`z`, `r`, not waiting) and on disk, oldest first |
| `E.Store.Shareable(page)` | packed (`z`) or Base64 of the text (`r`), not waiting |
| `E.Store.Page(acct, store, n)` | a page to serve, and where (`"mine"`, `"inbox"`, `"carry"`); nil if I don't have it (mine: or it isn't offered) |
| `E.Store.Held(where)` | `{ ["acct.store"] = "ranges" }` of `"mine"` (the pages I offer), `"carry"` or `"inbox"` |
| `E.Store.Put(acct, store, n, page, where)` | a friend's page received, `where` `"carry"` or `"inbox"`; `page` = `{ t, h, m, z }`, kept as a copy with `s` (and `a`). `true` (`true, "have"`: had it), or `false` and why: `id`, `mine` (my own store's), `page` (not `z`/`r` Base64), `size` (over 64 KB), `time` (before the launch, more than a day ahead), `hash` (`h` isn't `LT.Hash32(z)`; Put checks it), `exported`, `safe` (relaying a page a collector holds), `full` |
| `E.Store.Drop(acct, store, ranges, where)` | drops those pages (ranges nil: all; where nil: mine, carry and inbox); the number dropped |
| `E.Store.Safe(acct, store, ranges, collector)` | a collector (its key) holds these safely: merged into `safe` (only grows), dropped from mine and carry |
| `E.Store.SafeHere(acct, store)` | ranges this collector holds safely: received in an earlier session (on disk) or exported |
| `E.Store.Carried(acct, store, ranges)` | a relay holds these: of mine, they go first over the cap |
| `E.Store.Fits(acct, store, bytes)` | whether a relayed page of that size fits the cache |
| `E.Store.InboxFull()` | 8 MB collected: stop pulling |
| `E.Store.Bytes(where[, acct, store])` | bytes kept (carry with acct and store: that author's) |
| `E.Store.Trim()`, `E.Store.Recount()`, `E.Store.Pack(text)` | the cap now; the sizes counted anew; packing (`m`, `z`) |

`E.Ranges` (strings like `"1-56,58"`: ascending, merged, from 1 to 999,999,999; never spelled out
number by number): `Parse(ranges)` (a list `{ { 1, 56 }, { 58, 58 } }`; bad parts skipped),
`Format(list)`, `Union(a, b)`, `Contains(ranges, n)`, `Of(table[, keep])` (a table's page numbers).
Each takes a string or a parsed list.

### /lefthy echoes

`/lefthy echoes` (or `status`) prints, in English: recording or not, the account and store, the
open page (size, lines, age; whether nothing is on it yet, so it stays open), my pages (numbers, size of 2 MB, how many wait to be packed, how many are offered from the next session on), relaying
(with relaying on or pages kept) and collecting (with collecting on or anything collected or
exported). Other files add to it:

- `E.OnStatus(fn)`: `fn(add)` while the status prints; `add(text)` prints one more line.
- `E.Command(word, fn, help)`: `/lefthy echoes <word> ...` runs `fn(rest)`; `help` is its line in the
  list that anything else prints.

## Delivery

`Delivery.lua` (`E.Delivery`, `D` below): pages go from their author to whoever collects them,
through Beacon. Battle.net messages only reach friends online right now, so every client offers
the pages it holds and friends pass them on: a page gets from its author to the collector also
when the two are never online together.

**Roles** (each client can be several):

- **Author**: every client while Echoes records. There is no consent step: sharing follows the
  module being on (switched off, nothing is recorded or sent). Plain-text pages (`m = "t"`) never
  travel.
- **Relay** (`relay`, on): keeps friends' pages for a while and passes them on.
- **Collector** (`collect`, off): gathers friends' pages, and my own account's from my other
  computers, for the exporter. A collector doesn't relay.

Delivery runs on Echoes' tick while recording, and only while Beacon is on and my BattleTag is
known. Its state is memory only: a `/reload` starts afresh (pages half-way are asked for again).

### Messages

Beacon's B family (Protocol.lua): `B2;<module letter><word>;...`, module letter `e`. At most 255
bytes, like every Beacon message.

| Message | Format | What |
|---|---|---|
| `eh` hello | `B2;eh;<acct>;<store>;<proto>;<maxBytes>;<flags>` | proto 1, maxBytes 255. Flags: `c` collect, `r` relay, `s` share, `a` an answer (none back). Without c, r and s: switched off. Later fields are ignored (room for later builds) |
| `es` holdings | `B2;es;<acct>.<store>:<ranges>/...` | pages I can serve (`1-56,58`) |
| `ed` safe | `B2;ed;<collector acct>;<collector store>;<acct>.<store>:<ranges>/...` | pages safe at that collector; passed on by everyone; only grows |
| `eq` request | `B2;eq;<acct>;<store>;<n>;<offset>` | send me page n from byte offset; offset = its length: stop sending it |
| `eb` page begins | `B2;eb;<x>;<acct>;<store>;<n>;<len>;<hash>;<t0>;<m>` | transfer x (1-99, the sender's), length, `LT.Hash32` of the Base64 text, start, mode (`z` or `r`: the receiver stores it as it is) |
| `ep` part | `B2;ep;<x>;<offset>;<data>` | up to 240 bytes of the page's Base64 text (a substring of the stored string): 255 bytes in all |
| `en` don't have | `B2;en;<acct>;<store>;<n>` | ask someone else |
| `ex` / `ey` probe | `B2;ex;<size>;<padding>` / `B2;ey;<size>;<got>` | the probe (below) and its answer |

Items of `es` and `ed` are split over as many messages as they need (a long list of ranges in
pieces); receivers merge them. Every message is read strictly (`D.Read`: fields, sizes, lowercase
hex, Base64 characters; at most 300 intervals in a list, 40 items in a message).

### Who gets B

- **Only friends who sent `eh` get B messages.** My own `eh` goes to a friend once Beacon has
  answered their hello (`B.EchoesAnswer`) and their build is known to read B (Beacon's `V2`:
  `LT.CompareVersions` with `ECHOES_SINCE`, the first build with Delivery), or in answer to
  theirs. A friend on an older build is never sent one (after 60 s without a version that reads
  B, nothing is owed any more). An `eh` without `a` is answered with one with `a`; a friend who
  (re)starts gets everything I hold again, and theirs comes again.
- **Their account**: the account in `eh` must be the one Battle.net says for that friend (the
  friend list's BattleTag hashes, Chronicle's `C.Hash` the same way, whether Chronicle is on or
  not; or `GetAccountInfoByGUID`). Wrong: nothing is exchanged with them. Not known yet: checked
  again every second.
- **Accounts taken**: pages, holdings and safe ranges only of my Battle.net friends' accounts and
  my own.

### Pulling

- **What I hold** (`es`): my own pages (once on disk: Pages and storage), the ones I relay (while relaying) and a collector's inbox;
  never a friend's own pages back to them. To a friend who collects or relays, when it changed (at
  most every 60 s), everything every 5 minutes.
- **A collector** asks for every offered page it lacks (not in its inbox, not exported), until
  its inbox reaches 8 MB. One it relays already just moves to the inbox.
- **A relay** asks for pages of its friends' accounts (not its own) that:
  - no collector holds safely (`safe`),
  - no online friend who collects holds (they'll be safe at its next session),
  - fewer than 2 online friends besides the author hold,
  - fit its cache (`E.Store.Fits`: 512 KB in all, 128 KB per author's store). Too big when it
    begins (`eb`): it asks from the page's end (stops it) and leaves that page alone for 5 minutes.
- **Requests**: one open request per holder, 2 pages at once; a page I got part of goes on from
  there. 30 s without progress (counted from when the request went): asked again, from the
  contiguous offset, of the same holder or another. Pages never change, so bytes from different
  holders fit together; that's also how a page goes on after a friend went offline.
- **Serving**: a holder keeps 20 requests waiting and serves 2 at once (transfer ids 1-99 by
  turns); the same page asked again goes on from the new offset.

### Checks

- Delivery checks who and what was asked for: a page's start (`eb`) only for a page I asked for
  and don't have, of an account I take, at most 64 KB; parts only in order (one after a gap waits
  for the request again).
- A whole page goes to `E.Store.Put`, which checks the rest: the hash (`LT.Hash32`), the size, the
  start (not before the launch, not more than a day ahead), exported, safe, room. Refused for its
  hash, size or start: whoever sent parts of it isn't asked for it again this session. No room:
  that page is left alone for 5 minutes. The game never decompresses a page.

### Safe at a collector

- A collector's page is safe once it came in an earlier session (on disk now) or the exporter
  has it (`E.Store.SafeHere`). The collector puts its own summary in `safe` and sends `ed` to every
  friend; everyone passes on what they know, when it changed (at most every 60 s, everything every
  5 minutes), and `E.Store.Safe` merges what comes by union.
- Only collectors of a friend's account or my own count, and only about accounts I take; only what
  grows is merged. At most 200 stores and 8 collectors each are kept.
- `E.Store.Safe` drops my own pages (`mine`) and the ones I relay (`carry`) once any collector
  holds them safely.
- A relay's holdings with my own pages: `E.Store.Carried` (over my cap, those go first).

### Budget (never in the way)

- Everything goes through Beacon's low-priority queue (`B.QueueLow`), and only when nothing but
  Echoes' own waits in any of Beacon's queues (`B.Waiting`): chat, positions, the fight stream,
  journals and everything else first.
- At most 3 of mine waiting there; never more than 3 in any second in all, nor 2 to one friend
  (counted when they actually went, the waiting ones included; with the tick that's about 2.4 and
  1.6 a second).
- **Nothing in combat**: when a fight starts (`PLAYER_REGEN_DISABLED`), what still waits in
  Beacon's queue comes back out (`D.Withdraw`: parts are sent again from where they were, the rest
  goes back in line).
- **After a throttle or lockdown** (Beacon's `B.throttledAt`, result 3 or 11): nothing for 30 s;
  the next one right after doubles it, up to 5 minutes; after 10 calm minutes 30 s again. What
  waits comes back out the same way.
- **Receiving**: Beacon hands B messages over (at most 400 a minute from one friend, on top of its
  20 a second); they wait for the tick (at most 600), which handles 60 per tick. Unfinished pages
  stay in memory: 256 KB at most, 10 minutes without progress.

### Message size and the probe

Messages stay at 255 bytes; `maxBytes` in `eh` lets a later build use bigger parts per friend
once a probe on Forever shows what the server takes. `/lefthy echoes probe <friend>`
(`E.Command`; `D.Probe(name)`): to a friend with Echoes, messages of 255, 500, 1000, 2000
and 4000 bytes (`B2;ex;<size>;xxx...`), 2 s apart, out of combat, only when Beacon's queues are
empty, sent directly so each one's result shows; the friend answers each with what arrived
(`B2;ey;<size>;<got>`). Beacon lets a bigger `B2;ex;` through only for this (from a friend it
knows, up to 4100 bytes, 10 a minute). One chat line says per size: refused (the result), no
answer, arrived whole or cut. A throttle stops it and counts like Beacon's.

### Status

`/lefthy echoes` (`E.OnStatus`, `D.Status()`): friends with Echoes online and what they offer,
pages coming and served, traffic, a pause after a throttle.

### Check on launch day (delivery)

1. `/lefthy echoes probe <friend>`: which sizes the server takes, and whether bigger ones trip
   the throttle sooner (only then bigger parts per friend, through `maxBytes`).
2. Do B messages arrive during an encounter's lockdown (result 11), or only after it?
3. Battle.net tells a friend's account: the friend list's game accounts or
   `GetAccountInfoByGUID`. Without it no friend's hello is believed and nothing is delivered.
4. The rate in practice (about 2.4 parts a second in all): an evening's pages in well under a
   minute, nothing else of Beacon's slower.

### The pages: E.Store

Every change to the pages goes through `E.Store` (Pages and storage): `Page` to serve, `Held`
for what I hold, `Put` for what came, `Drop` (a page I relay that's collected now moves to the
inbox), `Safe` and `SafeHere`, `Carried`, `Fits`, `InboxFull`, `Own`. Delivery only reads
`exported` and `safe` for its decisions. What it works out of the pages (holdings, what I have
of a store, what's exported or safe) is cached until they change: `D.PagesChanged()` (also every
30 s, and when `n` moves). Its own ranges (`D.Ranges`: `Parse`, `Format`, `Normal`, `Union`,
`Minus`, `Has`) read the wire strictly (a bad part refuses the message) and do the set
arithmetic pulling needs; they read and write the same strings as `E.Ranges`.

### Beacon's hooks

`B.ReceiveEchoes(id, word, more)` (every `B2;e...`), `B.ReceiveProbe(id, text)`,
`B.EchoesAnswer(id)` (Beacon answered their hello), `B.EchoesForget(id)` (a friend gone: what
was asked of them goes to someone else, my messages to them still waiting go), `B.EchoesStop()`
(Beacon off).
