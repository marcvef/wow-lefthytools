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
  one spot). Exceptions, because no tick comes in time: `PLAYER_LEAVING_WORLD` writes its last point
  and the queue (what happened before the loading screen stays where it happened), `PLAYER_LOGOUT`
  its last point, the queue and `o0`, and `LOOT_READY` reads the loot window's slots
  (with auto loot it's gone by the next tick). A poll makes no tables.
- **Secret values** are skipped: a secret kill, cast, loot line, quest or GUID writes nothing (a
  secret killer is unknown, a secret group member one of the others, a secret AFK answer keeps the
  last state).
- **In combat** the silent `/played` (it touches the chat frames), gear, professions and reputation
  wait until the fight is over; the path and the events don't.
- **One heavy check per tick**: the full gear sweep (19 slots), professions, the reputation scan
  and `/played` never run in the same tick. A session's start looks at all four on the ticks after
  its anchor's (in this order: gear, professions, reputation, `/played`), so the same lines come a
  tick or so apart instead of all at once (and the end of a fight releases them the same way).
- **It records with Chronicle, the Bestiary and Beacon switched off.** It keeps its own small cache
  of mobs seen (level, classification, name: target, mouseover, nameplates; the last 200; a mob
  known whole costs one `UnitGUID` when seen again, one at `??` level, -1, or without its name yet
  is read again), and uses
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
- before an event (`E.capture.Spot`, once per tick): a point if you're 3 yd or more from A (however
  far, on a flight path too, unless you jumped since the last poll: more than 50 yd from its sample);
- before a loading screen, logging out or switching off: the last point.

At most a start point and one point per poll; a point on A again (whole yards) is left out, except
the start point.

**Travel modes**, read only on polls where the position changed (or on the two after coming back
to life: in water, standing still, swimming needs both), in this order: `t` flight path
(`UnitOnTaxi`), `g` ghost (`UnitIsGhost`), `c` carried (no transport API: the measured speed more
than 3 yd/s above `GetUnitSpeed`), `s` swimming
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
| the position gone (an anchor without one: the instance's map ID, else the last continent; after a loading screen the continent `GetInstanceInfo` says) or back | what caused it, else `j` |
| released: the ghost at the graveyard (the first poll it moved, at most 1 s after `PLAYER_ALIVE` as a ghost, once per death; polled every tick meanwhile) | `r` |
| a new page that didn't go on from the last (no anchor on the page: `E.Continue` wasn't called) | `c` |

What caused it, from what was noted shortly before (used once, then forgotten): `h` the hearthstone
(your cast of 8690 within 20 s; the spell's field 8690), `p` a teleport spell within 20 s (the
mage's teleports 3561-3567, Astral Recall 556, Teleport: Moonglade 18960, the engineers'
Dimensional Ripper - Everlook 23442 and Ultrasafe Transporter: Gadgetzan 23453; the spell's
field), `u` a summon you accepted within 120 s (a post-hook on `C_SummonInfo.ConfirmSummon`, which the
summon dialog's Accept calls; `CONFIRM_SUMMON` only offers it: one declined or not answered explains
nothing), `r` released (within 20 s). In an instance
(no positions: dungeons, raids) the anchor has none and no points follow until the next anchor with
one; battlegrounds have positions.

**The zone** (`z`): on the zone events and every 10 s, `C_Map.GetBestMapForUnit` and
`GetSubZoneText`, a line when either changed (after a session's anchor always).

**The session** (`o`): `o1` after a session's anchor and zone (login, a `/reload`, switched on);
`o0` at `PLAYER_LOGOUT` and when switched off. `PLAYER_LOGOUT` comes on a `/reload` too and can't be
told from logging out: a `/reload` writes `o0`, then `@...;l` and `o1` a few seconds later. An `o1`
after an anchor with why `l` (not `s`) is a `/reload`: the session goes on (the exporter can join
them). A session whose anchor isn't written yet (waiting for the position) stays one through
another loading screen. A crash or a disconnect writes no `o0`: the page gets `o0;0` at the next
start instead (The open page, below).

### What happens (Events.lua)

| Line | Detection |
|---|---|
| `L` level; played | `PLAYER_LEVEL_UP`; played: the time played (Changes.lua), whole seconds |
| `a` / `Q` / `A` | `QUEST_ACCEPTED`; `QUEST_TURNED_IN` (xp, money); `QUEST_REMOVED`: 1.5 s later, abandoned (`A`) unless it was turned in, or turned in (`Q` without xp and money) when `C_QuestLog.IsQuestFlaggedCompleted` says so. One `Q` per turn-in: a `QUEST_TURNED_IN` up to 60 s before or after its `QUEST_REMOVED` is the same turn-in, whichever wrote the `Q`; a quest turned in again (accepted again, or a repeatable one never in the log) counts again. The title (`=q`) from `C_QuestLog.GetTitleForQuestID`, kept from when it was accepted |
| `D` | `PLAYER_DEAD`, once until alive again (and 10 s after: the game repeats it). Logged in or `/reload`ed dead or a ghost (`UnitIsDeadOrGhost` when recording starts; no `PLAYER_DEAD` comes then): that death was counted before, its release and coming back still are. The killer: your attackable target in the last fight within 15 s (looked at every tick in combat): a creature (`c`, its ID, level, classification; its name `=c`), a player (`p`, class and level, no name; pvp 1); a player's pet, totem or guardian (`UnitPlayerControlled` when it became the foe; a totem's or guardian's GUID is a creature's): a player too (`p`, pvp 1), its owner's class and level when the owner has a nameplate (`UnitIsOwnerOrControllerOfUnit`), else empty; a secret GUID (`-`) |
| `r` | `PLAYER_UNGHOST`: `s` after `CONFIRM_XP_LOSS` (the spirit healer, within 120 s), `p` after `RESURRECT_REQUEST` (within 70 s), else `c`; `PLAYER_ALIVE` alive without having released: `p` or `c`. Then the mode is read again, on two polls (back to life in water, standing still: swimming) |
| `k` | `PARTY_KILL` by me, my pet (`UnitGUID("pet")`) or a group member (`C_PartyInfo.IsGUIDInGroup`), of a creature; each corpse once (the last 64). Level, classification (`n e r x w`; trivial and minus are `n`) and name from the mob cache |
| `l` | `CHAT_MSG_LOOT` through `LT.OwnLoot`, quality 2 and better (an item not cached yet: by the link's colour): item, count, quality, `l` looted or `p` pushed, and the creature whose corpse the last loot window (within 5 s) said it came from; the item's name (`=i`) from the link |
| `h` | `UNIT_SPELLCAST_SUCCEEDED` (player) with Herb Gathering, Mining or Skinning (each rank's ID, other ranks by name: the listed ranks' names, asked when first needed and, while one kind's isn't loaded yet, again after `SPELLS_CHANGED` or at most every 10 s), then `LOOT_READY` within 1.5 s; or `IsFishingLoot()`. The node: the loot source's game object ID (herbs, ore), the creature for skinning, none for fishing (its source is always the bobber, 35591); each node (each cast's bobber) once (the last 32). Then one `item:count` field per item |
| `n` | `NEW_MOUNT_ADDED` (`m`), `NEW_PET_ADDED` (`p`: its species, `C_PetJournal.GetPetInfoByPetID`), `NEW_TOY_ADDED` (`t`), `ACHIEVEMENT_EARNED` (`a`, not one earned before), `NEW_RECIPE_LEARNED` (`r`) |
| `B` | `ENCOUNTER_END` (success) and `BOSS_KILL`: the same encounter within 30 s once |
| `F` | a post-hook on `TakeTaxiNode` (like Flight.lua's): `ns.FlightTime.Pick`'s taxi node IDs, from and to |
| `b` won / lost | `PVP_MATCH_COMPLETE`, else `GetBattlefieldWinner()` every 5 s in a battleground: 0 the Horde, 1 the Alliance against your faction; the match's length (or the time since you entered); once |

### Compared with what was written (Changes.lua)

The baselines are kept per character, `E.data.capture[<GUID>]`, so a `/reload` or the next login
writes only what changed. A session's start looks at everything once.

| Line | Detection | Kept |
|---|---|---|
| `x` | every 60 s, at a session's start, on `PLAYER_UPDATE_RESTING` and level-ups: `UnitLevel`, `UnitXP`, `UnitXPMax`, `GetXPExhaustion` (none: 0), `IsResting`; when one changed. A change only of the rested XP or the resting flag at most every 10 minutes (in an inn or a city the rested XP grows all the time: a night there would write a line a minute); level, XP or max at once | `xp` (the last line's values) |
| `f` | `PLAYER_FLAGS_CHANGED` (player), `UnitIsAFK`; when it changed (a secret answer keeps the last) | |
| `g` | `GROUP_ROSTER_UPDATE`: `GetNumGroupMembers`, the members' GUIDs (`party1-4` or `raid1-40`, not me); a friend is a Beacon peer (`ns.Beacon.peers`, Beacon on) or remembered: `guid:First-Realm` (the realm `GetPlayerInfoByGUID` says, else mine, written the way my own character's key writes a realm: mine as `GetRealmName` has it, whatever form it came in ("RealmName", "Realm-Name" for "Realm Name": compared without spaces and hyphens); another realm as Battle.net shows it, `realmDisplayName` else `realmName`, when it's the same realm; one remembered in another form is rewritten so), sorted; the others counted. Left the group: `g;0;0`. A changed roster is looked at at most every 2 s (`GROUP_ROSTER_UPDATE` comes in bursts, in a raid many a second), in combat only when its size changed (one `GetNumGroupMembers`), else once the fight is over: a line can come a second or two after the change (the site's group moments join intervals up to 2 minutes apart anyway). With others in it and Beacon on, looked at again every 15 s out of combat (Beacon learns of friends a few seconds after login, and a line is written only when it changed) | `group`; `E.data.friends[guid]` = "Anna-Realm" (named while Beacon is off) |
| `G` | `PLAYER_EQUIPMENT_CHANGED` marks a slot, a session's start all 19; out of combat `GetInventoryItemLink`: item, enchant (the link's second field), suffix (seventh), 0 when none; the name `=i`. A worn item whose link isn't there yet (`GetInventoryItemID` says one is worn: at login) isn't taken off: looked at again every second, 10 times, then the item alone (enchant and suffix empty) unless it's the one written before. Taken off (an empty slot): item 0 | `gear[slot]` |
| `R` | `FACTION_STANDING_CHANGED` names a faction; a session's start and `UPDATE_FACTION` (at most every 10 s; once `FACTION_STANDING_CHANGED` came this session, at most every 2 minutes: it names each change itself, the scan is a safety net, and `UPDATE_FACTION` comes with every bit of reputation gained) scan the listed factions (`C_Reputation.GetNumFactions`, `GetFactionDataByIndex`; headers left out); out of combat; the reaction 1-8. A character's first scan is the baseline: no lines; so is a faction a scan lists for the first time (the list leaves out what's under a closed header: opened, its factions would all look new; or one just met). `FACTION_STANDING_CHANGED`'s faction is written even then | `reps[faction]`, `repsKnown` |
| `s` | `SKILL_LINES_CHANGED` and a session's start; out of combat `C_SkillInfo.GetSkillLineInfoByID` for the 12 Classic professions: rank and maximum; unlearned (rank 0): `0;0` | `skills[id]` |
| `H` | `HEARTHSTONE_BOUND` and a session's start: `GetBindLocation()` (a place's name) | `bind` |
| `p` | `PLAYER_PVP_KILLS_CHANGED`: `GetPVPSessionStats()`, the kills since the last line (a session's start is the baseline) | |
| `d` / `b` | after each anchor of a loading screen or a session: in a `party` or `raid` instance (`IsInInstance`, `GetInstanceInfo`: the instance ID, difficulty) `d;e;...`, left `d;x;...`; a `pvp` one `b;<id>;e`, left `b;<id>;x;<seconds>` (left while logged out or switched off: the seconds until it was last seen inside, noted every 5 s, not the time offline). Inside, but the instance ID or the kind not readable (a secret, a failing call): nothing changes (not left), looked at again every 5 s, 6 times. Kept across a `/reload` and logging out | `dungeon` { id, difficulty }, `bg` { id, entered, result written, last seen inside } |

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
`QUEST_TURNED_IN` comes first; `PARTY_KILL` for pets and group members; `UnitPlayerControlled` for an enemy's totems and guardians, and `UnitIsOwnerOrControllerOfUnit` from its owner's nameplate; the gathering spell IDs and
`GetLootSourceInfo`'s game object GUIDs for nodes (and the bobber's for fishing); `PVP_MATCH_COMPLETE`'s winner (0 the
Horde, 1 the Alliance, like `GetBattlefieldWinner`); `NEW_RECIPE_LEARNED`, `NEW_MOUNT_ADDED` and
`FACTION_STANDING_CHANGED` firing (also for a faction under a closed header: a scan no longer
writes those); `C_SkillInfo.GetSkillLineInfoByID` for professions not learned (nil, or rank 0: only
rank 0 is taken as unlearned). Also: `GetInstanceInfo`'s instance ID outside instances (the
continent, 0 or 1); `UnitPosition` at `PLAYER_LEAVING_WORLD` still where you were (the last point
and the queue are written there); `IsPlayerMoving` on a flight path; `GetUnitSpeed` 0 right after
`PLAYER_STOPPED_MOVING`; no `PLAYER_DEAD` at a login while dead, and whether `PLAYER_ALIVE` comes
again for a ghost (after a dungeon's release, say: an `o` anchor then an `r` one); gear right at
login (a worn item's link not there yet: `GetInventoryItemID` gives the item meanwhile); loot links' colours
(`|cff1eff00|Hitem:`, classic's quality colours) for an item the game hasn't cached yet; a summon
accepted (the dialog's Accept going through `C_SummonInfo.ConfirmSummon`: the anchor's why `u`); the
form of a friend's realm from `GetPlayerInfoByGUID` and Battle.net (`realmDisplayName`,
`realmName`): the group line writes it as the friend's own `GetRealmName` would.

### Tests

`tests/echoes_capture.lua` (after `echoes.lua`): a session starting, the store rule (distance,
bends, start and stop, the idle crawl fix, an event's spot, also on a flight path, `UnitPosition`
once a second), every travel mode (swimming's flicker, the carried guess and what isn't carried: a
stop, Blinks, a secret speed; a boat across a loading screen; back to life in water), every segment
and cause (a loading screen to no position, events and a hearthstone just before one, a summon
declined, not answered or accepted), instances (one that can't be told yet), every event kind as its
exact line (quests removed before they're turned in and the other way round, far apart, or turned in
again, a login or `/reload` while dead, a release heard twice, a player's totem or pet as the
killer, loot not cached yet, fishing, gathering ranks known by names that come late, reputation
under closed headers, rested XP in an inn, a battleground left while logged out, gear whose link
comes late, a friend Beacon learns of later, friends' realms in another form), secret values, nothing in combat that must wait, a `/reload`
(`E.capture.Reset`, and one with a loading screen before its anchor), Chronicle, the Bestiary and
Beacon off, the beta, and a whole session read back on a page of its own (times and positions add
up line after line). It leaves `ECHOES_CAPTURE_SESSION` (the page and its times and positions) for a
check with the exporter's parser outside this repo.

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
| `D` | death | level; killer kind c/p/- (p also for a player's pet, totem or guardian: its owner's class and level, if known); creature id or class; killer level; classification; pvp 0/1 |
| `r` | back to life | how: s spirit healer, p player, c corpse |
| `k` | kill | creature; level; classification; who m/p/g |
| `l` | loot | item; count; quality; l looted / p pushed; source creature |
| `g` | group | size; others; then one field per friend: guid:Name-Realm |
| `G` | gear | slot; item (0: taken off); enchant; suffix (both empty: not known) |
| `f` | AFK | 1 start / 0 end |
| `R` | reputation | faction; standing |
| `h` | gathering | kind h/o/s/f; node or creature (empty for fishing); then one field per item: item:count |
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
  top = 215,          -- the highest number of mine friends hold, or given to a moved page (nil: none; numbers used twice, below)
  open = {            -- the page being written (plain text, never shared); nil: none
    n = 214, t0 = 1793452800, char = "Anna-Realm", guid = "Player-...", acct = "1a2b3c4d",
    own = 4,            -- its own lines (header, character, going on): nothing else, it doesn't close by time
    busy = 1793452801,  -- when a line other than its own came (its 30 minutes run from then); nil: none yet
    text = "E1;...\n...\n", -- the lines joined so far
    buffer = { ... },   -- the lines not joined yet: E.buffer itself
    state = { ... },    -- the encoder's state: E.state itself
  },
  mine = {            -- my closed pages
    [211] = { t = 1793449200, e = 1793451000, h = "7a2b9c01", m = "z", z = "eJzt...", s = 40, o = 2 }, -- went only early
    [212] = { t = 1793451000, e = 1793452700, h = "5e1f09aa", m = "z", z = "eJzt...", s = 40, o = 1 },
    [213] = { t = 1793452700, e = 1793454500, m = "t", z = "E1;...", q = 1, s = 41, o = 0 }, -- closed, waiting to be packed
  },
  safeTo = { n = 210, e = 1793449200 },  -- the newest page of mine that went because a collector holds it (/lefthy echoes)
  carry = { ["5e6f7a8b.0c77e1f2"] = { [57] = { t, h, m, z, s = 41, a = 1793450000 } } }, -- friends' pages I relay
  safe = { ["5e6f7a8b.0c77e1f2"] = { ["c011ec70.12345678"] = "1-56" } },              -- collectors' summaries
  heard = { ["5e6f7a8b.0c77e1f2"] = 1793450000 },                                      -- when a store in safe was last heard of first-hand
  inbox = { ["5e6f7a8b.0c77e1f2"] = {                                                  -- a collector's: received
    [58] = { t, h, m, z, s = 41, a = 1793450000 },
    [59] = { t, h, m, z, s = 41, a = 1793450100, p = 1 },                              -- came early: provisional
  } },
  provisional = { ["5e6f7a8b.0c77e1f2"] = { [55] = "3c1d2e4f" } },                     -- a collector's: provisional pages the receipt took
  arrived = 1793450100,                                                                  -- a collector's: the latest arrival (a) given (only grows)
  launched = "YYYY-MM-DD",                                                               -- the launch day whose older pages went (one walk; nil: none yet)
  exported = { ["5e6f7a8b.0c77e1f2"] = "1-50" },                                         -- a collector's: from receipts
  latest = { ["5e6f7a8b.0c77e1f2"] = { n = 59, t = 1793449900 } },                     -- a collector's: the newest page received (/lefthy echoes)
  names = { ["5e6f7a8b.0c77e1f2"] = "Bob" },                                             -- friends' first names by store (/lefthy echoes)
  capture = { ["Player-..."] = { ... } },  -- the capture's baselines per character (Recording)
  friends = { ["Player-..."] = "Bob-Realm" }, -- LefthyTools friends' names (Recording)
}
```

A field that isn't what it should be is made new (a table that isn't one, a store that isn't 8 hex
digits); nothing else is touched, except that a stored page without its text (`z`) goes when the
sizes are counted (when recording starts). A stored page is `{ t, h, m, z }`:

- `t`: its start (the header's t0).
- `e` (mine): when it ended: closed by time or size, then (`E.Now()`); closed as stale at login, its
  last line's time (`open.state.t`). None: from a build before it (its `t` counts instead).
- `m`: how `z` holds it: `z` Base64 of its zlib, `r` Base64 of the text (compressing failed), `t`
  the text (Base64 failed too: kept and exported, never shared).
- `z`: the page. The game never decompresses one (an output without a limit): only the exporter does.
- `h`: `LT.Hash32(z)`, the hash of what's stored (none while it waits).
- `q`: closed, waiting to be packed (`m` is `t` meanwhile).
- `s` (mine): the session it closed in (the session before for a page closed as stale at login
  from the saved text; none: from a build before the rule, on disk; a page moved to a new number:
  the session it moved in); (carry, inbox): the session it came in. `a` (carry, inbox): when it came
  (`E.Now()`; in the inbox at least one more than `arrived`, which becomes it, so every page arrived
  after every page before it, whatever the clock says: the receipt's `upto`; none: from a build
  before it).
- `o` (mine): `0` not out yet (no part of it was ever sent), `1` out (a part went to a friend from
  my disk), `2` parts went only early (to collectors, while it wasn't on my disk: they keep it
  provisional); none: closed by a build before the rule, counts as out (numbers used twice, below).
- `p` (inbox): `1` provisional: it came early, not confirmed yet (early pages, below).

`provisional` (a collector's): `{ ["acct.store"] = { [n] = hash } }`, provisional pages the
exporter's receipt took out of the inbox (the exporter has them) that aren't confirmed yet. Their
numbers aren't in `exported`. Made when first needed.

`arrived` (a collector's): the latest arrival (`a`) given to an inbox page. It only grows: raised
when a page comes and when the sizes are counted (from the inbox), never lowered (the receipt takes
the pages, not the time). Made when the first page comes; broken (not a number from 0 to 10^10):
counted anew from the inbox.

For `/lefthy echoes` (below), noted as pages come and go, one comparison each (made when first
needed, and anew when they aren't tables):

- `safeTo`: `{ n, e }`, the newest page of mine that went because a collector holds it (`E.Store.Safe`
  for my key, or my own exporter's receipt): its number and when it ended (`e`, else its `t`).
  Newest by when it ended, not by its number: a page moved to a new number (numbers used twice,
  below) is an old one.
- `latest` (a collector's): `{ ["acct.store"] = { n, t } }`, the newest page received of each store
  (`E.Store.Put` into the inbox): its number and start, newest by its start. The exporter's receipt
  takes the pages themselves, so it's kept. It goes with the store (the chores: no inbox, `exported`
  or `provisional` entry any more).
- `names`: `{ ["acct.store"] = "Bob" }`, friends' first names (`E.Store.Named`, from Delivery: the
  Battle.net name of a friend whose account is checked, `LT.Names.First`). At most 200 (a new one
  waits for room); the chores drop the ones of stores nothing is kept of any more (in inbox,
  `exported`, `provisional`, `safe` or carry).

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
  part runs there (joining the text, a look for its last session line); it's packed on a later
  tick. It's on disk (offered at once, below) when it's the saved text alone and its last line is
  more than 10 minutes old;
- goes unclosed if it started before the launch day (`LT.BeforeLaunch`), or can't be a page.

**A crash or a disconnect writes no logout** (the game ends without `PLAYER_LOGOUT`, saved as it
was). A page from the saved file whose session never ended (its last session line a login,
`o<dt>;1`, or none and an anchor with why `c`: it went on from the page before) gets it: `o0;0`
(dt 0: at the time of its last line) right before its `.0;l` when it closes, first when it goes on.
Only the text decides, so every load of the same save adds the same line. The exporter reads it as
a logout, and the next session's `o1` (after an anchor with why `s`) as a login.

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
  sees one): `.<dt>;t`; 10 minutes while a friend who takes pages early is online
  (`E.Delivery.EarlyTaker()`, asked only once a page is 10 minutes busy, and then at most every 5 s:
  its answer is kept that long, so one who comes online closes it within 5 s): a closed page goes to that
  collector within minutes (early pages, below), so a crash loses less. Its own lines are the
  header, the character and, on a page that follows one closed mid-session, the going on
  (`open.own` counts them). A page with nothing else on it stays open however long you're away (an
  AFK night is one page, not one every 30 minutes); the stale rule at login still closes it. An
  open page from a build before this rule (no `own`): 30 minutes (or 10) from its start. Never by
  time in combat (`LT.InCombat()`): a page due in a fight closes on the first tick after it, so its
  end (`.<dt>;t`, `e`) is then, not the 30 (or 10) minutes; by size it still closes at once.

Not while the capture waits for its anchor (`E.PageMayClose`: `E.capture.Ready()`; a loading screen
and the position after it, up to 3 s): the next page would go on from where you were before it, at a
time after it. It closes on the first tick the capture is ready again (its anchor written).

`E.Store.Close` keeps it (below), and the next page starts in the same tick: header, character, and
`E.Continue()` (an anchor at the last position, why `c`, the mode and the zone). The tick does
nothing else then.

### Closed pages (Store.lua)

`E.Store.Close(n, t0, text, onDisk, e)` keeps the text in `mine[n]` as it is (`m = "t"`, `q = 1`, `s`
the session, `o = 0`, `e` when it ended: now if nil) and `n` becomes the last closed page's number (a number at or below `E.data.top`,
or kept already: the next one above, its header renumbered; numbers used twice, below). It returns
the number the page is kept under. The tick packs one waiting page at a time,
oldest first, and not in a fight (`LT.InCombat()`): a page closed in one waits as it is (plain text,
`q`: offered to nobody, early or not), the chores wait behind it (the 2 MB cap would count it
unpacked), and the first tick after the fight packs it. A logout in the fight saves it as it is, and
the next load queues it again (`q`) and packs it then; it's on disk by then, so it's offered at once:
nothing waits for it to be packed sooner.

1. `C_EncodingUtil.CompressString(text, Enum.CompressionMethod.Zlib)`, then
   `EncodeBase64(..., Enum.Base64Variant.Standard)`: `m = "z"`;
2. compressing answers nothing or fails: `EncodeBase64(text)`, `m = "r"`;
3. Base64 answers nothing, fails or isn't Base64 (or there's no `C_EncodingUtil`): the text, `m = "t"`.

Then `h = LT.Hash32(z)` and `q` goes. That's about once in 30 minutes (10 with a collector who takes
pages early online): zlib and Base64 in C, the hash over 5-12 KB in Lua (about 1 ms).

**My pages go to everyone once they're on disk, and early to a collector online.** The game writes
the saved file only at a logout or `/reload`; after a crash the next login goes on from the last
save and numbers its pages from there again. A page of the lost session that had already gone out
would then share its id with a different page closed after the crash: a collector who kept the
first (pages never change) would make the author drop the second with its "safe", and relays drop
theirs too: lost. The guard for numbers used twice (below) only partly helps: it moves a page that
never went out, not one that did, and a relay can take the second page before any holder of the
first told the author (the holder offline at the author's next session). So:

- **To everyone, only pages on disk:** `E.Store.Mine`, `E.Store.Held("mine")` and `E.Store.Page`
  for my own key offer only pages closed in an earlier session than this one (`s`; a `/reload`
  starts a new session, `E.data.session`). Relays only ever get those.
- **Early, only to a collector:** my packed pages not on disk yet (`E.Store.Held("early")`,
  `E.Store.Page(acct, store, n, true)`) go in an `ea` of their own, and are served, only to friends
  who collect on a build that keeps them provisional (`e` in their hello; Delivery). The collector
  keeps such a page **provisional** (`p = 1` in its inbox) until a copy from my disk shows the same
  hash (a check, Delivery: Checks): never safe, never served, told (in `es`) only to me. So nobody
  drops anything because of a page that came early.
- **A crash after pages went early:** the collector holds the lost pages provisionally. Online at my
  next session, it tells me their numbers (its `es` to me, `E.Store.Elsewhere`): my next pages close
  above them, and a page of mine with such a number that never went out moves. Offline then, my next
  page with that number goes out as ever (to relays after my `/reload`); back, the collector's check
  shows another hash, and it waits until the exporter's receipt took its provisional page aside
  (Store.lua: the receipt), then fetches mine. The exporter gets both (it keeps every version of a
  number used twice); nobody drops mine before it's safe at the collector. A lost page that is never
  confirmed stays provisional.
- **Clashes wait for the exporter.** The second page with a number is fetched only once the
  exporter's receipt took the provisional one aside. Until then it lives in my `mine` (2 MB at most:
  over it the oldest go) and at relays (30 days). Run the exporter regularly (its autostart does).
- **A page closed as stale at login** is on disk at once (its `s` is the session before): it's the
  saved text and nothing else, and its last line is more than 10 minutes old, so any later load of
  that save, after a crash too, closes it the same way. One closed for another character within
  those 10 minutes waits for the next session (back on the first character, a later load would go
  on with it), and so does one closed after switching Echoes off and on (it has this session's
  lines).
- **The cost:** my pages travel to relays from the next session on (the next login or `/reload`),
  not the evening they're recorded, and to a collector online within minutes (it downloads one again
  only as far as its start, to check it, once it's on my disk). The author keeps every page until a
  collector holds it safely, so nothing is lost by the wait. `/lefthy echoes` says how many wait, and
  how many of those went early to a collector.
- **Left over:** a collector who goes back to a build from before early pages ignores `p`: its
  provisional pages count as safe there (on its disk at its next session, served, in its summary),
  so a page its author lost in a crash makes the author drop another page with that number. Collect
  only on this build or later. And a friend who claims to collect (`c` and `e` in their hello) gets
  my early pages and their hashes, as a collector would; relays aren't authenticated either, as
  before: Echoes trusts Battle.net friends.

**Numbers used twice** (a WTF folder restored from a backup, or copied to a second computer and
played on both). The store id is made once per folder, so a restored folder numbers its pages again
from its old `n`, and two computers with one folder number theirs alike: one id, two pages. Without
a guard the collector keeps the first it gets, its "safe" covers the number, and the author drops
its other page as safe: lost. So each of my pages knows whether it went out (`o`: `E.Store.WentOut`,
called by the delivery when something of it was actually sent; kept in the saved table): `0` never,
`1` out (a part from my disk), `2` only early (parts went to collectors while it wasn't on my disk;
they keep it provisional). An early part makes it `2` only from `0`; a part from my disk makes it `1`,
also from `2`.

- **A page that never went out but whose number friends hold** (a holder's holdings `es`, a
  collector's with the pages of mine it holds provisionally, or a collector's safe summary `ed`,
  direct or passed on: `E.Store.Elsewhere`, `E.Store.Safe` for my key) is another page with that
  number. It isn't dropped: it **moves to a new number**, above every number of mine any friend told
  of, the last closed page's and the open page's (`E.data.top` keeps the highest), and goes out under
  that number from the next session on (like a new page: its new number is on disk then; early to a
  collector before that). Nothing of it went out under the new number (`o = 0`). A page still waiting
  to be packed gets its header renumbered too; a packed one keeps the number it was recorded under in
  its header (the game never unpacks a page), and the exporter files it under the number it's kept
  under (it warns that the header names another).
- **A page that went only early** (`o = 2`) moves too when a collector's **safe summary** covers its
  number, or the holdings of a friend who doesn't collect (a relay) do: neither covers a provisional
  copy (a summary covers what the collector holds from a disk, or exported; a relay holds only pages
  from a disk, and none from mine but a part from my disk, which makes it `1`), so it's another page
  with that number, and the only copy of mine out there is a provisional one (lost if that
  collector's game crashes before it saved it). A collector's holdings don't move it: the one that
  took it early tells me its number (its provisional copy of this very page). Without this, a
  restored or copied folder's new page that went early would be dropped for the old page's summary,
  or go out (to a relay, after my `/reload`) before that summary came.
- **Confirming a page that went early** keeps working: after my `/reload` the collector's check asks
  for it from my disk, and a part of it that goes makes it `1`; so does its start (`eb`) alone when
  it goes to a collector who takes pages early, or whose holdings list that number of mine (its
  check: the start's hash is all it needs to confirm its copy, and it usually stops the page before
  any part goes). Then its summary drops the page, as ever. (Its holdings alone wouldn't do: a
  collector tells them only to friends who collect or relay.)
- **My next pages close above it:** numbers of mine friends hold above my last page raise
  `E.data.top`, and `E.Store.Close` closes a page whose number is at or below it (or kept already)
  above it, its header renumbered (it's still plain text then). `E.data.n` itself only moves when a
  page closes: Pages.lua leaves an open page whose number isn't above it unclosed at the next login.
  Numbers more than 10,000 above my last page aren't believed (a broken client).
- **Not moved:** a page that went out (`o = 1`: the collector may hold this one), one from a build
  before the rule, and one the exporter has from this computer (`exported` of my own key: it read
  this very table). Those go as before once safe.
- Relays tell an author what they hold of its own pages (`es` with the author's key), so this
  works before a collector's summary comes, and with only relays online.
- **Left over:** a page whose `o = 1` wasn't saved (the game crashed after it went out, or a backup
  from before it went out) is moved although it's the same page: the collector gets it twice, under
  both numbers, with the same text. A restored backup's open page closes at login as a page of its
  own, whose lines are the first ones of a page that went out after the backup: those lines come
  twice. (The exporter can tell both: the moved page's header names the other number.) And a relay
  that asks for my never-out page before any holder's summary reached me makes it "out" (`o = 1`),
  though the collector may hold the other page with that number: then it's lost like before (a
  collector that took it early keeps its provisional copy, which its exporter archives). A page that
  went only early and moves for another page's summary: the collector that took it early keeps that
  copy under the old number, provisional, and its exporter archives it too (the same text twice). And
  one whose check got only its start from my disk while that collector's hello no longer said `e`
  (its inbox just went full) and its holdings hadn't reached me stays `2`: its summary then moves it
  although it holds this very page (twice in the archive, nothing lost). Copy a WTF folder only to
  move, not to play on both.

**A BattleTag change** (Blizzard lets a player change it): my account is the hash of my BattleTag,
so it changes with it, and my pages' key with it (the store stays).

- From the next login my key is the new one: `E.MyAccount()` and Delivery's account (read once a
  load) say the new hash, `E.data.acct` keeps it, and friends, whose friend lists show the new
  BattleTag, believe my `eh` with it. The numbering goes on (`E.data.n`, `top`): no number is used
  twice under the new key.
- Every page still in `mine` is offered under the new key, with its number, also the ones recorded
  before: their headers keep the old account (closed pages never change; an open page keeps the
  account it was started with), and the exporter files them under the key they're kept under (it
  warns that the header names another account).
- The old key is no longer anyone's friend's account: nobody takes pages, holdings or summaries of
  it any more (Accounts taken). Copies relays still have of it go after 30 days; summaries of it are
  forgotten after 60 days unheard of. Nothing is lost by that: I keep every page until a collector
  holds it, and send the ones still in `mine` under the new key (except pages that went over my
  2 MB cap because a relay carried them: those were only at the relay, under the old key).
- **The cost:** a page a collector already had under the old key, whose "safe" hadn't reached me
  before the change (it's ignored now), comes to it again under the new key: the exporter gets the
  same text under both keys (its header names the old one). A collector's own pages too: ones its
  exporter read under the old key, but whose receipt is read only after the change, stay in `mine`
  (the receipt names the old key) and are exported again under the new one.

**What's kept** (design section 7):

- **mine:** until a collector holds a page safely (`E.Store.Safe`), at most 2 MB (about 250 hours).
  Over it, after every packed page and at the start, the oldest go, first the ones a relay is known
  to carry (`E.Store.Carried`, this session).
- **carry:** 512 KB in all, 128 KB per author's store (`E.Store.Put` refuses what doesn't fit), 30
  days after a page came (at the start), and dropped once a collector holds it safely.
- **inbox:** dropped only by the exporter's receipt (only the pages it read). At 4 MB one chat line
  a session asks to run the exporter; at 8 MB `E.Store.InboxFull()` says so and the delivery stops
  pulling (a page still on its way is kept), and its hello no longer says `e` (Delivery: authors
  keep their pages to 30 minutes and send none early) until the receipt made room.
- **provisional:** a number and a hash per provisional page the receipt took; it goes when the page
  is confirmed (into `exported`) or the receipt takes a page with that number from a disk. One of a
  page lost in its author's crash is never confirmed: it stays (a few numbers per crash).
- **The launch day:** on the release, once `LT.LAUNCH_DAY` is set, pages that started before it go
  from mine, carry and inbox at the start, and `E.Store.Put` refuses them. That walk over every page
  runs once: `launched` (in the saved table, made then) keeps the day it ran for, and later sessions
  skip it while it's the same day (nothing from before it comes in after it: `Put` refuses those, and
  an open page from before it goes unclosed). While `LT.LAUNCH_DAY` isn't set nothing runs and nothing
  is noted, so the pages from before it still go once it's set. Older builds ignore `launched`.

**The exporter's receipt** (collecting on): once a session, on the tick,
`LoadAddOn("LefthyTools_EchoesReceipt")` (load on demand; a folder that isn't there does nothing, and
a new one needs a game restart), then `LefthyToolsEchoesReceipt.done` (`{ ["acct.store"] = "1-57" }`,
the pages the exporter has a version of from a disk: an author's own, or an inbox page without `p`),
`early` (the same form: the numbers it has only from copies that came early, inbox pages with `p`)
and `upto` (`{ ["<store>"] = <time> }`: per collector's store, the latest inbox arrival `a` of its
saved file the exporter read; it never goes down). For each key and its ranges:

- **Inbox pages in `done`** go if the exporter read them: `a` (none: 0) at most `upto[my store]`
  (a missing store entry: none of my inbox goes). Without `upto` (an older exporter) every one goes,
  as before, except a page from a disk whose number is in `provisional`: it came after the
  provisional page of that number the receipt took, so the receipt may be older than it. A
  provisional page that goes is kept in `provisional` (its number and hash), not in `exported`: the
  exporter has it, but a page with that number from its author's disk (another page, after a crash)
  must still be fetched. Any other page that goes is added to `exported`, and its number leaves
  `provisional` (the page from a disk is archived now).
- **Numbers of `done` without an inbox page** are added to `exported`, unless `provisional` has
  them. Numbers kept in the inbox aren't (the exporter doesn't have that page).
- **`early`:** only provisional inbox pages in it go, by the same rule, into `provisional`. Its
  numbers never go into `exported`, and nothing else goes for them: not a page from a disk in the
  inbox (the exporter would have moved the number into `done`), not carry, not mine. Its author may
  have lost that page in a crash and used the number again for another page, which the exporter
  doesn't have: a collector that never had the early copy (another saved file the exporter reads, or
  this one after its saved data was reset) would take the number as exported, its summary would
  call it safe, and the author and relays would drop the other page before it's archived. A receipt
  without `early` (an exporter from before it) lists those numbers in `done`, as before.
- **carry and mine:** `done` goes, as before.

It lists the full ranges each time, so reading it again is harmless (a page that came since stays,
by its arrival). Arrival times keep it so whatever the clock does: an inbox page arrives after every
one before it (`a` at least one more than `arrived`, the latest one given, which is kept in the saved
data and only grows: also after the receipt emptied the inbox).

**After the start**, one a tick: a waiting page packed, else the next chore (the launch day, old
relayed pages, collectors' summaries of stores not heard of for 60 days with the status's names and
newest pages of stores nothing is kept of, the 2 MB cap, the 4 MB line), else the receipt: read in
one tick, then one of its stores a tick (one whose ranges list nothing is passed over in the same
tick), so a collector's whole inbox never goes in one frame. Each store's pages are its own (taking
one changes nothing of another), so a store taken a few ticks later is as if the receipt had come
that much later: a page that comes meanwhile arrived after what the exporter read (`upto`) and
stays, as ever; without `upto` (an older exporter) the same race was there before, between the
login and the receipt's tick (now longer by a tick per store).

**Costs.** A tick: a few comparisons. A minute: one join. Half an hour (ten minutes with a collector
who takes pages early online): one page packed, never in a fight. Inside event handlers: only the logout's join and, at
login, joining a stale page's text. A page that came early is downloaded once more only as far as
its start (a check), once it's on its author's disk.

### For the delivery: E.Store and E.Ranges

Every change to mine, carry and inbox goes through `E.Store` (it keeps their sizes), and each one
tells the delivery, which caches what I hold: `E.Delivery.PagesChanged()` (if Delivery.lua is
there) when a page closes, is packed (it can be shared now), kept, dropped (the cap, the 30 days,
the launch day, a receipt, `Drop`, `Safe`), confirmed (`Confirm`), when a collector's summary or
what's exported grows, and when the sizes are counted anew. Keys are `"acct.store"`, 8 hex digits
each.

`E.Store.Held` and `E.Store.SafeHere` keep what they work out per store (`held`, `safeHere` in
Store.lua) until something of that store changes: every place in Store.lua that changes mine, carry,
inbox, `provisional` or `exported` marks its store (`Dirty`; my own pages are one entry), counting
the sizes anew forgets all of it, and so does a new saved table (what's on disk goes by the session,
which a load doesn't change). The delivery asks for all of it after every change; on a collector
with thousands of pages only the store that changed is worked out anew (8,000 inbox pages in 100
stores: about 0.2 ms instead of 20 ms). A safety net forgets the stores one at a time, each once in
2 minutes, so a change that didn't go through `E.Store` (which shouldn't happen) is seen before the
delivery's own safety net looks again (every 5 minutes). Held returns a new table each time; the
strings in it are the kept ones.

| Call | What |
|---|---|
| `E.Store.Key(acct, store)` | `"acct.store"`, nil if either isn't 8 hex digits |
| `E.Store.Own()` | my pages' key, nil while my BattleTag isn't known |
| `for n, page in E.Store.Mine()` | my pages I offer: shareable (`z`, `r`, not waiting) and on disk, oldest first |
| `E.Store.Shareable(page)` | packed (`z`) or Base64 of the text (`r`), not waiting |
| `E.Store.Page(acct, store, n[, early])` | a page to serve, and where (`"mine"`, `"inbox"`, `"carry"`); nil if I don't have it (mine: or it isn't offered, unless `early`: then a shareable one not on disk too, for a collector who takes it early; inbox: or it's provisional) |
| `E.Store.Held(where)` | `{ ["acct.store"] = "ranges" }` of `"mine"` (the pages I offer), `"early"` (mine shareable and not on disk yet), `"carry"`, `"inbox"` (provisional pages left out) or `"provisional"` (provisional pages in the inbox and in `provisional`) |
| `E.Store.Put(acct, store, n, page, where[, provisional])` | a friend's page received, `where` `"carry"` or `"inbox"`; `page` = `{ t, h, m, z }`, kept as a copy with `s` and `a` (`provisional`, inbox only: it came early, kept with `p = 1`). `true` (`true, "have"`: had it), or `false` and why: `id`, `mine` (my own store's), `page` (not `z`/`r` Base64), `size` (over 64 KB), `time` (before the launch, more than a day ahead), `hash` (`h` isn't `LT.Hash32(z)`; Put checks it), `exported`, `safe` (relaying a page a collector holds), `full` |
| `E.Store.Provisional(acct, store, n)` | whether this collector holds page `n` provisionally: its hash and where, `"inbox"` or `"provisional"` (the receipt took it); nil if not (also when the inbox has a page `n` from a disk) |
| `E.Store.Confirm(acct, store, n, hash)` | a copy of page `n` from its author's disk has this hash: if it's the provisional one's, it's confirmed (the inbox page loses `p`; one the receipt took goes into `exported`); whether it was |
| `E.Store.Drop(acct, store, ranges, where)` | drops those pages (ranges nil: all; where nil: mine, carry and inbox); the number dropped |
| `E.Store.Safe(acct, store, ranges, collector)` | a collector (its key) holds these safely: merged into `safe` (only grows), dropped from mine (the newest noted in `safeTo`) and carry; of mine, one that never went out or went only early moves to a new number instead (numbers used twice) |
| `E.Store.Elsewhere(acct, store, ranges[, fromDisk])` | a holder offers these (its holdings): for my own key, my next pages close above them and a page of mine among them that never went out moves to a new number (`fromDisk`, a holder that doesn't collect: one that went only early too); the number moved |
| `E.Store.WentOut(n, page[, early, start])` | something of my page `n` was sent (`page`: the one served, if it's still page `n`): a part from my disk, `o = 1` (it keeps its number); `early` (a part while it wasn't on my disk), `o = 2` if it was `0`; `start` (only its start from my disk, to a collector who takes pages early or holds that number provisionally: its check), `o = 1` if it was `2` |
| `E.Store.SafeHere(acct, store)` | ranges this collector holds safely: received in an earlier session (on disk) and not provisional, or exported |
| `E.Store.Carried(acct, store, ranges)` | a relay holds these (not a collector: provisional pages are among its holdings): of mine, they go first over the cap |
| `E.Store.Mentioned(acct, store)` | a friend told of this store first-hand (offers pages of it, or is the collector whose summary it is): what collectors hold of it is kept 60 days from now |
| `E.Store.Named(acct, store, name)` | a friend whose account is checked says hello: their first name, kept for the status (`names`) |
| `E.Store.Fits(acct, store, bytes)` | whether a relayed page of that size fits the cache |
| `E.Store.InboxFull()` | 8 MB collected: stop pulling |
| `E.Store.Bytes(where[, acct, store])` | bytes kept (carry with acct and store: that author's) |
| `E.Store.Trim()`, `E.Store.Recount()`, `E.Store.Pack(text)` | the cap now; the sizes counted anew; packing (`m`, `z`) |

`E.Ranges` (strings like `"1-56,58"`: ascending, merged, from 1 to 999,999,999; never spelled out
number by number): `Parse(ranges)` (a list `{ { 1, 56 }, { 58, 58 } }`; bad parts skipped),
`Format(list)`, `Union(a, b)`, `Minus(a, b)`, `Contains(ranges, n)`, `Of(table[, keep])` (a table's
page numbers). Each takes a string or a parsed list; a string is parsed each time, so a caller that
asks `Contains` for many numbers (one per page) parses once and passes the list (`Contains` is a
binary search).

### /lefthy echoes

`/lefthy echoes` (or `status`) prints, in English (chat lines, kept short), in this order:

- recording or not, the account and store;
- the open page: size, lines, age; whether nothing is on it yet, so it stays open;
- **how far my recording is safe** (`safeTo`): "your recording is safe at a collector up to 21:30
  (page 214)." (the end of the newest of my pages that went because a collector holds it, and its
  number), or "no page of yours has reached a collector yet.";
- **what waits**: "3 pages waiting to reach a collector (215-217), recorded since 21:30; 2 of them
  sent early to a collector, safe once confirmed." (every page in `mine`, the oldest one's start;
  sent early: it went only early, `o = 2`, on disk by now or not: it waits for the confirmation), or
  "none of your pages waits to reach a collector.";
- what's kept of them (when any are, or one moved this session): "my pages: 24.0 KB of 2.0 MB",
  how many wait to be packed, how many are offered from the next session on, how many moved to a new
  number this session;
- relaying (with relaying on or pages kept);
- collecting (with collecting on or anything collected, exported or provisional): the inbox's size,
  then **a line per friend's store** with anything collected, exported or provisional (my own
  account's other computers too, as "you (<store>)"; this computer's own pages are the lines above):
  "Bob: 59 pages (1-59) up to 10:58; 50 exported, 5 on disk, 2 not on disk yet (safe after your
  logout or /reload), 2 sent early (confirmed once Bob's game saved it)."
  - the name from `names`; not known: the account's 8 hex digits; two stores of one name: each
    with its store after it;
  - the pages: all the numbers in `exported`, the inbox and `provisional` (counted from the
    intervals, never spelled out; more than 3 pieces: "1-900 with 11 gaps");
  - "up to": the newest page's start (`latest`, or an inbox page from before it); none known
    (only exported, from a build before `latest`): left out;
  - exported (numbers in `exported`), on disk (inbox, not provisional, an earlier session's), not on
    disk yet (this session's), sent early (provisional: in the inbox with `p`, or in `provisional`
    without an inbox page of that number);
  - sorted by name; more than 10: the 10 whose newest page is newest, then "... and N more."; stores
    whose newest page is more than 30 days old are left out: "(N older not shown: nothing from them
    in 30 days.)".

Times are the realm's clock as this computer shows it: "21:30" today, "Nov 1 21:30" another day,
with ", 3 days ago" when it's more than a day ago. All of it is worked out on the command (the pages
only note `safeTo` and `latest` as they come and go, one comparison each). Other files add to it:

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
  computers, for the exporter; an author online gives it its pages not on disk yet early, which it
  keeps provisional (Pages and storage). A collector doesn't relay.

Delivery runs on Echoes' tick while recording, and only while Beacon is on and my BattleTag is
known. Its state is memory only: a `/reload` starts afresh (pages half-way are asked for again).

### Messages

Beacon's B family (Protocol.lua): `B2;<module letter><word>;...`, module letter `e`. At most 255
bytes, like every Beacon message.

| Message | Format | What |
|---|---|---|
| `eh` hello | `B2;eh;<acct>;<store>;<proto>;<maxBytes>;<flags>` | proto 1, maxBytes 255. Flags: `c` collect, `r` relay, `s` share, `e` takes pages early (sent with `c` while the inbox isn't full: this build keeps them provisional), `a` an answer (none back). Without c, r and s: switched off. Later fields are ignored (room for later builds); older builds look for each letter on its own, so `e` changes nothing for them |
| `es` holdings | `B2;es;<acct>.<store>:<ranges>/...` | pages I can serve (`1-56,58`); to a page's author, while I collect, the ones of theirs I hold provisionally too |
| `ea` early | `B2;ea;<acct>.<store>:<ranges>/...` | my own pages not on my disk yet; only to a friend who collects and takes them early (`c` and `e`), only my own key. Older builds don't read the word, and get none |
| `ed` safe | `B2;ed;<collector acct>;<collector store>;<acct>.<store>:<ranges>/...` | pages safe at that collector; passed on by everyone; only grows |
| `eq` request | `B2;eq;<acct>;<store>;<n>;<offset>` | send me page n from byte offset; offset = its length: stop sending it |
| `eb` page begins | `B2;eb;<x>;<acct>;<store>;<n>;<len>;<hash>;<t0>;<m>` | transfer x (1-99, the sender's), length, `LT.Hash32` of the Base64 text, start, mode (`z` or `r`: the receiver stores it as it is) |
| `ep` part | `B2;ep;<x>;<offset>;<data>` | up to 240 bytes of the page's Base64 text (a substring of the stored string): 255 bytes in all |
| `en` don't have | `B2;en;<acct>;<store>;<n>` | ask someone else |
| `ex` / `ey` probe | `B2;ex;<size>;<padding>` / `B2;ey;<size>;<got>` | the probe (below) and its answer |

Items of `es`, `ea` and `ed` are split over as many messages as they need (a long list of ranges in
pieces); receivers merge them. Every message is read strictly (`D.Read`: fields, sizes, lowercase
hex, Base64 characters; at most 300 intervals in a list, 40 items in a message). What I send of my
saved table is checked the same way: a key that isn't two times 8 lowercase hex digits (a file
edited by hand) stays out of my messages, and an entry of the wrong type is skipped.

### Who gets B

- **Only friends who sent `eh` get B messages.** My own `eh` goes to a friend once Beacon has
  answered their hello (`B.EchoesAnswer`) and their build is known to read B (Beacon's `V2`:
  `LT.CompareVersions` with `ECHOES_SINCE`, the first build with Delivery: `0.6.0-25-g41f011b`;
  0.6.0-24 reads B2 but has no Delivery, and a build without a commit count, like the tagged
  0.6.0, counts as older), or in answer to theirs. A friend on an older build is never sent one (after 60 s without a version that reads
  B, nothing is owed any more). An `eh` without `a` is answered with one with `a`; a friend who
  (re)starts gets everything I hold again, and theirs comes again (what they offered early is
  forgotten: a crash may have lost it); what they asked of me before isn't served any more (gone
  with their session: they ask again). A friend whose hello newly says `e` gets all my early pages
  at once.
- **When my flags change** (a setting; collecting with the inbox at 8 MB, or back under it: `e`
  goes and comes), every friend hears one hello with `a` (no answer back), and everything I hold
  goes to them again. Checked once a second; the inbox only fills as pages come and empties only by
  the exporter's receipt (once a session), so it doesn't flap: one hello per change.
- **Their account**: the account in `eh` must be the one Battle.net says for that friend (the
  friend list's BattleTag hashes, Chronicle's `C.Hash` the same way, whether Chronicle is on or
  not; or `GetAccountInfoByGUID`). Wrong: nothing is exchanged with them. Not known yet: checked
  again every second. Right: their character's first name (Beacon's, `LT.Names.First`) is kept for
  their store (`E.Store.Named`, for the status), then and at each hello after.
- **Accounts taken**: pages, holdings and safe ranges only of my Battle.net friends' accounts and
  my own. The friend list's accounts are read every 30 s, and sooner (at most every 5 s) when it
  may have changed: an account that isn't in it (once per account until the list is read anew: a
  friend just added, or one Battle.net lists late, whose pages a relay offers), or Battle.net says
  a friend came online or the list changed (`BN_FRIEND_ACCOUNT_ONLINE`,
  `BN_FRIEND_LIST_SIZE_CHANGED`: the handlers only note it). Not on `BN_FRIEND_INFO_CHANGED`: it
  fires whenever any friend changes zone; a friend who logged into a game is found anyway, their
  game account not being in the list makes it read again (at most every 5 s). Each BattleTag is
  hashed once, not at every reading. So a friend's holdings that came before Battle.net listed them
  aren't dropped until the next summary.

### Pulling

- **What I hold** (`es`): my own pages (once on disk: Pages and storage), the ones I relay (while
  relaying) and a collector's inbox (not its provisional pages); a friend's own pages too, back to
  them (they learn who holds which of theirs: `E.Store.Carried`, and numbers used twice), and to
  them only, while I collect, the ones of theirs I hold provisionally (so what a friend who doesn't
  collect holds is only ever from a disk). Nobody else hears of provisional pages: no
  relay leaves a page alone for them ("held by an online collector" counts only what's in an `es`),
  no other collector asks for one. To a friend who collects or relays, when it changed (at most
  every 60 s), everything every 5 minutes (each friend's next one up to a quarter sooner, by
  chance: friends met together don't stay in step; at most 3 friends' summaries are made in one
  second, so everyone's after a hello or a change of my settings is spread over the next seconds).
- **My early pages** (`ea`): my own pages not on disk yet, to a friend who collects and takes them
  early (`c` and `e`: verified, online), the same way (when it changed, at most every 60 s,
  everything every 5 minutes). Serving one: only to such a friend; anyone else asking gets `en`.
  `D.EarlyTaker()`: whether one is online (Pages.lua: 10-minute pages); a collector whose inbox is
  full doesn't say `e` (it asks for nothing then). A relay's holdings of my
  pages mark them carried (`E.Store.Carried`, over my cap they go first), a collector's don't (it
  doesn't relay, and its provisional numbers are among them); `E.Store.Elsewhere` takes both (a
  relay's also moves a page of mine that went only early: numbers used twice).
- **A collector** asks for every offered page it lacks (not in its inbox, not exported, not in
  its relay cache), until its inbox reaches 8 MB. Its relay cache (from before it collected)
  moves to the inbox, one page a second and none in a fight (`E.Store.Put` checks its hash again),
  offered or not; an exported one just goes.
  - **Early offers** (`ea`, kept per friend only for their own key, until they restart, switch off
    or say `en`; taken only while collecting): after what friends offer as on a disk, the pages
    there it doesn't have in any way (not in its inbox, provisional or not, nor in `provisional`,
    exported or in its relay cache). They're kept provisional (`p = 1`).
  - **A number it holds provisionally**, offered as on a disk (anyone's `es`): asked for as a check
    (Checks); one whose check showed another hash while the provisional page is still in the inbox
    isn't asked for again this session.
- **A relay** asks for pages of its friends' accounts (not its own) that:
  - no collector holds safely (`safe`),
  - no online friend who collects holds (they'll be safe at its next session),
  - fewer than 2 online friends besides the author hold,
  - fit its cache (`E.Store.Fits`: 512 KB in all, 128 KB per author's store). Too big when it
    begins (`eb`): it asks from the page's end (stops it) and leaves that page alone for 5 minutes.

  What isn't wanted is worked out as ranges per store (the copies by a sweep over friends'
  holdings), and taken out of each holder's offer: however many pages others hold, a
  page still wanted is found (not only among the first 50), and many friends cost little. Pages
  are looked at one by one only to skip the ones already asked for, whole and waiting to be kept,
  or that this holder's copy or my room failed (at most 50 of those a holder).

  A relay starts at a random page among the ones it wants and goes on from there (around to the
  first); a collector takes the oldest first. Many relays coming online with an author at once,
  before what each holds has spread, would otherwise all fetch the same first page from the author
  (`D.Random`: tests make it the first).
- **Kept, not worked out every second**: what isn't wanted of a store and what's wanted of a
  holder's offer are kept while what they're made of stays the same (the same lists of what I hold,
  what's exported or safe: The pages; the same holdings of that store), and friends' offers are
  looked at again only after a change that could make me want another page: what I hold or what's
  safe (`D.PagesChanged`), a friend's holdings (`es`, `ea`, `en`), a friend coming, going,
  restarting or verified, a check that showed another hash, the friend list, my key, my settings
  (a friend's holdings of a store, or a check: only that store's offers are looked at again).
  A Pull (once a second) that found nothing isn't done again until such a change, a request ends,
  or a page that had no room may be asked for again (5 minutes); one that stopped at 50 pages of a
  holder is done again every second (a relay starts somewhere else each time). A test runs friends
  offering, restarting, going and sending pages (whole, broken, too big), my pages and settings
  changing and time passing, and compares every Pull with one worked out anew, nothing kept
  (`D.CheckPull`).
- **Requests**: one open request per holder, 2 pages at once; a page I got part of goes on from
  there. 30 s without progress (counted from when the request went): asked again, from the
  contiguous offset, of the same holder or another; for a minute after that (or until they send a
  part again) that holder is asked last, so holders in a long fight, or silent after a throttle,
  can't hold up both requests while others could answer. Pages never change, so bytes from
  different holders fit together; that's also how a page goes on after a friend went offline.
- **Serving**: a holder keeps 20 requests waiting and serves 2 at once (transfer ids 1-99 by
  turns). One place in the line per friend (they ask one holder for one page at a time): a new
  request from them replaces theirs, being served or waiting, in its place, so a page asked again
  after 30 s keeps its turn and nobody holds two places; the page they're being served, asked
  again, goes on from the new offset. Asked from its end, only that page stops (what of it
  already waits in Beacon's queue still goes, nothing more). Friends who collect go first: a
  free serve takes the first collector's request in the line, and a collector's request that
  finds the line full takes the last relay's place (pages go to the collector; a relay only
  carries them for a while).

### Checks

- Delivery checks who and what was asked for: a page's start (`eb`) only for a page I asked for
  and don't have, of an account I take, at most 64 KB; one I don't take is stopped (asked from
  its end), and its transfer id no longer leads to an earlier page of that friend's; parts only
  in order (one after a gap waits for the request again).
- A whole page goes to `E.Store.Put` (one a tick, none in a fight: Budget), which checks the rest: the hash (`LT.Hash32`), the size, the
  start (not before the launch, not more than a day ahead), exported, safe, room. Refused for its
  hash, size or start: whoever sent parts of it isn't asked for it again this session. No room:
  that page is left alone for 5 minutes. The game never decompresses a page.
- **From a disk or early:** a copy is from a disk when the friend who began it offered that number
  in their `es` (my own on my disk, relayed, a collector's not provisional); one that isn't came
  early (its author's, from an `ea`). A page whose bytes came early (and no holder of the same page
  offered it as on a disk, or it was asked for from an `ea`) is kept provisional (`p = 1`), and only
  by a collector: one that switched collecting off meanwhile lets it go (relays only ever have pages
  from a disk; the author still has it).
- **The check** (`E.Store.Provisional`, `E.Store.Confirm`): a number I hold provisionally is asked
  for when someone offers it as on a disk, and its start (`eb`) says the copy's hash. The same as
  mine: confirmed (the inbox page loses `p`; one the receipt took goes into `exported`), and it's
  stopped (asked from its end): only its start and maybe a part came again. Another hash while my
  provisional page is in the inbox: another page with that number (its author lost mine in a crash
  and closed this one after); stopped, not asked for again this session, and it waits: the inbox has
  no room for it until the receipt took mine aside (nobody drops it meanwhile: a provisional page
  isn't safe). Another hash, the receipt took mine: fetched like any page (into the inbox, from a
  disk; not refused as exported, its number isn't). A start of such a number that isn't the answer
  to my check is stopped.

### Safe at a collector

- A collector's page is safe once it came in an earlier session (on disk now) and isn't
  provisional, or the exporter has it (`E.Store.SafeHere`). A provisional page never is, and its
  number isn't in `exported` either until it's confirmed: so nothing anyone drops ever depends on a
  page that came early. The collector puts its own summary in `safe` and sends `ed` to every
  friend; everyone passes on what they know, when it changed (at most every 60 s, everything every
  30 minutes: it only grows, and friends keep it), and `E.Store.Safe` merges what comes by union.
- Only collectors of a friend's account or my own count, and only about accounts I take; only what
  grows is merged. At most 200 stores and 8 collectors each are kept, and of what friends tell
  at most 300 intervals per collector (more isn't taken as safe: those pages are kept; a
  collector's own summary has no limit).
- **A store's entry goes 60 days after it was last heard of first-hand** (`heard`, at the start,
  one of the chores): a friend offered pages of it (`es`), its collector's own summary came (`ed`
  from the collector itself; my own as a collector too), or pages of it are here (my own while I
  hold any, ones I relay or collected: never dropped then). Summaries passed on don't count: every
  friend passes on every summary, so they'd keep every entry forever, and a broken or hostile
  friend could fill the 200 places for good. By then no page of that store is around (relayed
  pages go after 30 days) to need it. `E.Store.Mentioned(acct, store)` notes it; an entry from
  before the rule gets its 60 days from its first start.
- `E.Store.Safe` drops my own pages (`mine`) and the ones I relay (`carry`) once any collector
  holds them safely; of mine, one that never went out, or went only early, moves to a new number
  instead (Pages and storage: numbers used twice).
- A holder's holdings with my own pages: `E.Store.Carried` (a relay's: over my cap, those go first)
  and `E.Store.Elsewhere` (numbers used twice). A page of mine I serve that moved (or went) stops:
  nothing more of it goes under its old number. A part of my page that was sent: `E.Store.WentOut`.

### Budget (never in the way)

- Everything goes through Beacon's low-priority queue (`B.QueueLow`), and only when nothing but
  Echoes' own waits in any of Beacon's queues (`B.Waiting`): chat, positions, the fight stream,
  journals and everything else first.
- At most 3 of mine waiting there, and one handed over per Echoes tick (so two never go out in the
  same moment); never more than 3 in any second in all, nor 2 to one friend (counted when they
  actually went, the waiting ones included; with the tick that's about 2.4 and 1.6 a second).
- **Summaries** (`es`, `ea`, `ed`) are worked out once per change of the pages or of what's safe
  (`D.PagesChanged`, the safety net every 5 minutes), the same for every friend: the ranges written
  and the messages packed once (only an author's own pages I hold provisionally are added for
  them). A friend is looked at again only after such a change or when their full offer is due:
  while nothing changes, nothing is worked out. A change that leaves a summary as it was (a page
  that came, but nothing told of it changed) keeps it: friends who heard it are passed over, and
  what of a summary didn't change is taken over when it's built anew, not read again.
- **What waits its turn** (`out`: hellos, requests, answers, summaries): hellos, requests and
  answers go first, then summaries and page parts by turns (summaries for many friends don't hold
  up a page). A friend's summary of a kind isn't queued while one of that kind still waits for
  them (what changed meanwhile goes after it); their full offer takes the place of what of it
  still waits. At most 200 wait: past that no summary is queued, and the last one waiting makes
  room for a hello, a request or an answer (what it told is forgotten for that friend: it comes
  again); with none to drop, an answer doesn't wait (they ask again), and hellos and requests
  always do (a few a friend at most: dropping one would leave a friend unknown, or a page asked
  for that never goes).
- **Nothing in combat**: when a fight starts (`PLAYER_REGEN_DISABLED`), what still waits in
  Beacon's queue comes back out (`D.Withdraw`: parts are sent again from where they were, the rest
  goes back in line).
- **Switched off**, my "I'm out" hellos go from a frame of their own (Echoes' events and tick stop
  with it; its `OnUpdate` is set only while some are left): one at a time, handed to Beacon only
  when nothing else waits there, half a second after the one before went (2 a second at most),
  never in a fight: then the one still waiting comes back out, and the rest wait for its end
  (`PLAYER_REGEN_ENABLED`, registered only then). Switched on again before they all went, the rest
  don't go.
- **After a throttle or lockdown** (Beacon's `B.throttledAt`, result 3 or 11): nothing for 30 s;
  the next one right after doubles it, up to 5 minutes; after 10 calm minutes 30 s again. What
  waits comes back out the same way.
- **Receiving**: Beacon hands B messages over (at most 400 a minute from one friend, on top of its
  20 a second); they wait for the tick (at most 600), which handles 60 per tick, and stops after
  2 ms (`debugprofilestop`, where the game has it; at least one a tick): merging a long holdings or
  safe list costs more than another message. What adds nothing to what's known (a holder's full
  offer every 5 minutes, the summaries every friend passes on) isn't merged at all: a walk over both
  lists finds that, nothing made. A whole page waits in memory until it's kept (`E.Store.Put` hashes
  it, up to 64 KB): one a tick, none in a fight, and nobody is asked for it meanwhile; it counts
  like an unfinished one. Unfinished pages
  stay in memory: 256 KB at most, 10 minutes without progress. My answers to one friend (`en`,
  `ey`, a stop) wait at most 8 at a time: a friend asking faster than they go (2 a second) can't
  pile them up; the rest are dropped, and they ask again.

### Message size and the probe

Messages stay at 255 bytes; `maxBytes` in `eh` lets a later build use bigger parts per friend
once a probe on Forever shows what the server takes. `/lefthy echoes probe <friend>`
(`E.Command`; `D.Probe(name)`): to a friend with Echoes, messages of 255, 500, 1000, 2000
and 4000 bytes (`B2;ex;<size>;xxx...`), 2 s apart, out of combat, only when Beacon's queues are
empty, sent directly so each one's result shows; the friend answers each with what arrived
(`B2;ey;<size>;<got>`). Beacon lets a bigger `B2;ex;` through only for this (from a friend it
knows, up to 4100 bytes, 10 a minute). One chat line says per size: refused (the result), no
answer, arrived whole or cut. A throttle (result 3 or 11) stops it and counts like Beacon's own:
`B.Throttled(result)` sets `B.throttledAt` and pauses Beacon's sending, and Echoes is silent at
once (the backoff above).

### Status

`/lefthy echoes` (`E.OnStatus`, `D.Status()`): friends with Echoes online, what they do (collects,
takes early pages, relays) and what they offer; "your pages go to Cedric Vale early (10-minute pages
while a collector is online)." while one who takes them early is online (`D.EarlyTaker()`); pages
coming and served, traffic, a pause after a throttle.

### Check on launch day (delivery)

1. `/lefthy echoes probe <friend>`: which sizes the server takes, and whether bigger ones trip
   the throttle sooner (only then bigger parts per friend, through `maxBytes`).
2. Do B messages arrive during an encounter's lockdown (result 11), or only after it?
3. Battle.net tells a friend's account: the friend list's game accounts or
   `GetAccountInfoByGUID`. Without it no friend's hello is believed and nothing is delivered.
4. The rate in practice (about 2.4 parts a second in all): an evening's pages in well under a
   minute, nothing else of Beacon's slower.
5. Whether `C_BattleNet.SendGameData` returns a result at all (Beacon and the probe take none as
   sent), and with a big group of friends online (relaying is on for everyone) that the
   collector's requests are served first and nobody's line grows long.

### The pages: E.Store

Every change to the pages goes through `E.Store` (Pages and storage): `Page` to serve, `Held`
for what I hold, `Put` for what came, `Drop` (a page I relay that's collected now moves to the
inbox), `Safe` and `SafeHere`, `Provisional` and `Confirm` (checks), `Carried`, `Elsewhere`,
`WentOut`, `Fits`, `InboxFull`, `Own`. Delivery only reads
`exported` and `safe` for its decisions. What it works out of the pages (holdings, what I have
of a store, what's exported or safe) is cached until they change: `E.Store` calls
`D.PagesChanged()` on every change it makes, and only then (a page that came but wasn't kept, or
one it had already, changes nothing; Delivery works it out anew every 5 minutes too, a safety
net, and when my settings change). Even then only what changed is parsed again: the lists are kept
by store with the text they were read from, and the others stay the same lists (what pulling
worked out of them stays valid: Pulling). Its own ranges (`D.Ranges`: `Parse`, `Format`, `Normal`, `Union`,
`Minus`, `Has`, `Covers`) read the wire strictly (a bad part refuses the message, at most 300 intervals)
and do the set arithmetic pulling needs (`Union`, `Minus` and `Covers` each one walk over two sorted
lists); they read and write the same strings as `E.Ranges`.
What's kept here (held, exported, safe) is read with `E.Ranges.Parse`, without a limit: a list
of more than 300 intervals is all of it, not "none".

### Beacon's hooks

`B.ReceiveEchoes(id, word, more)` (every `B2;e...`), `B.ReceiveProbe(id, text)`,
`B.EchoesAnswer(id)` (Beacon answered their hello), `B.EchoesForget(id)` (a friend gone: what
was asked of them goes to someone else, my messages to them still waiting go), `B.EchoesStop()`
(Beacon off).
