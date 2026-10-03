# Chronicle design

A journal per character, kept automatically, plus statistics and a feed of what friends with
LefthyTools did. Files: `Modules/Chronicle/Chronicle.lua` (recording, sharing, session,
settings, `/chronicle`) and `Window.lua` (the window). They share `ns.Chronicle` (`C`).

## Data

`LefthyToolsChronicleDB` (account-wide saved variable, so every character's journal can be
browsed from any character):

- `chars["Name-Realm"]`: `name, realm, classFile, race, level, first` (when Chronicle first saw
  it), `events` (the timeline, oldest first, at most 1000), `stats` (counters, below),
  `zoneTime[zone]`, `killers[name]`, `levelTimes[level]`, `fastestLevel`, `levelStart`,
  `professions[name]`, `seen = { zones, dungeons, bosses, rares }` (rares by GUID: one spawn
  counts once), `days[YYYY-MM-DD]`, `session = { start, stats, money }`, `playedTotal` (what
  `/played` last said; Chronicle never asks itself, that would print in chat).
- `friends`: the feed, `{ t, name, classFile, k, ... }`, oldest first, at most 300.

For the graphs: `daily["YYYY-MM-DD"] = { played, xp, quests, kills, deaths }` (kept 60 days;
`Add` and the tick fill today's bucket), and `session.series`, a point `{ played, xp, money }` per
minute of play (at most 240: when full, every other point goes and the step doubles).

`C.Fill` completes a record (records from older versions lack newer stats); every record is
filled before it's shown.

## Recording

Handlers only count or append; nothing in them draws or sends.

| Entry (`k`) | Source |
|---|---|
| `level` (+ how long the level took, in time played) | `PLAYER_LEVEL_UP` |
| `death` (zone, subzone, foe, level) | `PLAYER_DEAD`; foe = your last attackable target while in combat, if within 15 s (the tick notes it) |
| `zone` (first visit) | tick after `ZONE_CHANGED_NEW_AREA` / `PLAYER_ENTERING_WORLD`, `GetRealZoneText` |
| `dungeon` (first visit; every entry counts as a run) | same, `IsInInstance` party/raid + `GetInstanceInfo` |
| `boss` (first kill of each; every kill counted) | `ENCOUNTER_END` with success, or `BOSS_KILL`; the same name within 30 s counts once |
| `rare` | your target is rare/rareelite/worldboss, not a player, dead and not someone else's tap (`UnitIsTapDenied`), checked on the tick; also `PARTY_KILL` on your target |
| `loot` (blue and better; with the item's icon) | `CHAT_MSG_LOOT` matched against `LOOT_ITEM_SELF(_MULTIPLE)` and `LOOT_ITEM_PUSHED_SELF(_MULTIPLE)` turned into patterns, so only your own loot, in any client language; quality from `C_Item.GetItemQualityByID`, else the link's `|cnIQ<n>:` |
| `mount`, `pet`, `toy` | `NEW_MOUNT_ADDED`, `NEW_PET_ADDED`, `NEW_TOY_ADDED` |
| `achievement` | `ACHIEVEMENT_EARNED` (not `alreadyEarned`) |
| `quests` milestones (10, 25, 50, 100, 250, ...) | `QUEST_TURNED_IN` |
| `gold` milestones (1, 10, 50, 100, 250, ... gold held at once) | `PLAYER_MONEY` |
| `profession` (learned; 75/150/225/300) | tick after `SKILL_LINES_CHANGED`, `GetProfessions`/`GetProfessionInfo`; the first scan is a baseline |

Counters (`stats`): played (the tick), sessions, levels, quests, foreverQuests
(`ns.IsForeverQuest`), questXP, xp (`PLAYER_XP_UPDATE` deltas, also across a level-up), kills
(`PARTY_KILL` with you as the attacker), rares, bosses, dungeonRuns, deaths, moneyIn/moneyOut/
maxMoney, loot2/3/4 (green/blue/epic+, counts included), jumps (post-hook on
`JumpOrAscendStart`, not while swimming or flying), walked/ridden/swum/flown (the tick:
`UnitPosition` distance since the last tick, by `UnitOnTaxi`, `IsSwimming`, `IsMounted`; more than
150 yd in a second is a teleport and not counted; nothing in instances), flights, mounts, pets,
toys, achievements, longestSession. Secret values (GUIDs, names, chat text in an encounter) are
skipped.

**Session:** starts at a real login (`PLAYER_ENTERING_WORLD` with `isInitialLogin`), or when a
character has none yet (then the login's PEW doesn't start a second one); a `/reload` continues
it. A snapshot of the counters and the gold at the start gives the session's numbers
(`C.Session`): time, XP, levels, quests, kills, deaths, gold change, distance.

## Cost

One driver, 1 tick per second while the module is on: time played and per zone, one
`UnitPosition`, the target check, the zone/profession re-checks only when flagged, sharing, and
`C.OnTick` for the window (returns at once unless it's open). Switched off: events unregistered,
driver hidden.

## Friends and sharing

Highlights go to friends through Beacon (`ns.Beacon.ShareHighlight`, on the tick, only with
Beacon on and `share` on) as `E2;<kind>;<a>;<b>`: boss (name, instance), rare (name, zone),
dungeon (name), loot (name, quality; epic and better only), mount (name), achievement (name),
quests (count), gold (amount), profession (name, level), and for the feed only (no chat line)
quest (every quest turned in: its title) and zone (first visit). Pets, toys and blue loot stay
private. Beacon accepts at most 10 highlights per friend per minute and only known kinds, and
passes them on as `B.Notify("highlight", peer, { kind, a, b })`. Chronicle's listener puts them,
and Beacon's `level`, `death`, `online` and `offline` events, into the feed, and prints a chat
line for highlights except quest and zone (English, `friendsChat`). Friends' level-ups and deaths
already have their own lines. `online`: a friend's name became known more than a minute after
Beacon started (friends already online at login aren't news); `offline`: a known friend was
forgotten (went offline, silent for 65 s, or switched Beacon off).

## Window

`LefthyToolsChronicleFrame` (Core/Window.lua's template), opened with `/chronicle`,
`/lefthy chronicle`, the settings button or the key binding `LEFTHYTOOLS_CHRONICLE_TOGGLE`.
A character switcher (this one first, then the others by name), and three pages, the open one's
button greyed out:

- **Timeline:** newest first, a heading per day (`L["%Y-%m-%d"]`: German `%d.%m.%Y`), time, an
  inline icon (the item's or achievement's own where known) and the localized text. At most 250
  entries drawn, the rest summarized in one line.
- **Statistics:** sections This session (current character only), Character, Quests, Exploring,
  Combat, Travel, Gold and loot, Collections. Labels and values are two font strings with the
  same number of lines (values right-aligned), so the columns line up. Times as `1h 12m`/`4d 4h`,
  distance in km, gold with `GetMoneyString`.
- **Graphs** (`Graphs.lua`): cards on the scroll content. Last 14 days (bars per day from
  `daily`, buttons switch between time, XP, quests and killing blows; today in gold; hover shows
  the date and value), This session (the session curve: a line with a gradient fill, plus XP per
  hour; current character only), Time per level (a bar per level from `levelTimes`, up to 20,
  green = fast to red = slow), Favourite zones and Deadliest foes (horizontal bars, top 5), On
  the road and Loot by quality (one split bar each, with a legend). Drawn with plain textures
  (`SetGradient` for the bars), line objects (`CreateLine`) and font strings from pools
  (`G.NewCanvas`): a redraw reuses everything, nothing is created after the first draw.
- **Friends' graphs:** on the Graphs page the arrows go on past your own characters to every
  friend who sent their days (`store.friendStats[name]`; other pages fall back to your own
  character). Their page: Last 14 days (the same bars from their days), Last 7 days (six tiles:
  time, XP, levels, quests, killing blows, deaths), You and <name> (two bars per number, you in
  gold, them in blue) and Latest news (their last 6 feed entries with date).
- **Friends:** "Online now" first: every Beacon friend in up to three lines (`B.FriendLines` in
  Beacon's `Alerts.lua`, shared with the AFK screen: name, AFK, level and progress, group; zone
  and distance; what they're fighting and their quest), then "What they did": the feed, as
  "Name: text", with a hint about what will appear while it's empty. Redrawn when the feed
  changes and every 5 s (the online part changes all the time).

Redrawn on the tick only while open, and only the open page when its own data changed:
`C.eventsDirty` for the timeline (a kill only changes a counter, so it doesn't rebuild 250
lines), `C.feedDirty` for Friends, `C.dirty` (counters) for Statistics, which also refreshes
every 5 s for the time and distance. Graphs: a change is remembered and drawn at most every 10 s,
otherwise every 30 s (the session curve). A redraw keeps the scroll position.

## Days for friends' graphs

Battle.net messages only arrive while both are online, so each friend's own Chronicle sends its
numbers: `D2;<YYYYMMDD>;<minutes played>;<xp>;<quests>;<kills>;<deaths>;<levels>` (about 45
bytes). When Beacon reports a friend as `known` (their name became known), they get my last 7
days; every 5 minutes today's and yesterday's go to everyone if they changed. Both go through
Beacon's low-priority queue (`B.QueueLow`): sent only when no message, state or answer waits,
so they never delay live data. Beacon accepts up to 20 days per friend per minute and checks the
ranges (minutes at most 1440); Chronicle keeps 30 days per friend in `store.friendStats`. Covered
by the "Share highlights with friends" setting.

## Cost, and what goes over the network

The 1-second tick is local only: a few cheap API reads (position, target), adding up counters,
and a session point per minute. Nothing is sent from it except highlights, which are rare (a few
per hour at most) and go through Beacon's rate limiter like everything else. The AFK screen shows a session line
(`ns.AFKScreen.sections`).
