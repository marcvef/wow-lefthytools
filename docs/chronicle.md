# Chronicle design

A journal per character, kept automatically, plus statistics and a feed of what friends with
LefthyTools did, also while they (or you) weren't online. Files: `Modules/Chronicle/Chronicle.lua`
(recording, sharing, session, settings, `/chronicle`), `Sync.lua` (friends' journals: publishing,
passing on, the people and news for the window, catch-up, weekly recap, leaderboards),
`Graphs.lua` (the Graphs and Compare pages), `Window.lua` (the window) and `MinimapButton.lua`.
They share `ns.Chronicle` (`C`).

## Data

`LefthyToolsChronicleDB` (account-wide saved variable, so every character's journal can be
browsed from any character):

- `chars["Name-Realm"]`: `name, realm, classFile, race, level, first` (when Chronicle first saw
  it), `events` (the timeline, oldest first, at most 1000), `stats` (counters, below),
  `zoneTime[zone]`, `killers[name]`, `levelTimes[level]`, `fastestLevel`, `levelStart`,
  `levelCounts[level] = { kills, quests }` (during that level; `levelFrom` holds the counters at
  the level's start), `professions[name]`, `seen = { zones, dungeons, bosses, rares }` (rares by GUID: one spawn
  counts once), `days[YYYY-MM-DD]`, `session = { start, stats, money }`, `playedTotal` (what
  `/played` last said; Chronicle never asks itself, that would print in chat).
- `friends`: the feed, `{ t, name, classFile, k, ... }`, oldest first, at most 300.

For the graphs: `daily["YYYY-MM-DD"] = { played, xp, quests, kills, deaths, levels, afk, bosses, rares,
runs, jumps, dist, level, gold }` (kept 60 days; `Add` fills today's bucket for the counters in
`DAILY` (stat -> day key: `dungeonRuns` -> `runs`), `TrackTravel` adds `dist` (yards), the tick sets
`level` and `gold` (whole gold held) to where the day ends), and `session.series`, a point
`{ played, xp, money }` per minute of play (at most 240: when full, every other point goes and the
step doubles). `sync` (Sync.lua): the character's highlight counter and its days' and profile's
stamps. `store.book`: friends' journals (below); `store.lastSeenAt`, `feedSeenAt`, `recapWeek`,
`myU`, `sharedAlts`.

`C.Fill` completes a record (records from older versions lack newer stats); every record is
filled before it's shown.

`C.LevelReport(level)` gives the level-up window (Misc Tweaks) the level before `level`:
`{ took, kills, quests, fastest }` from `levelTimes` and `levelCounts`, or nil while Chronicle is
off or that level wasn't timed.

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
character has none yet, or when Chronicle is switched on more than 5 minutes after its session's
last tick (`session.last`, stamped every tick: Chronicle was off at login and switched on later);
in those cases the login's PEW doesn't start a second one. A `/reload`, or switching it off and on,
continues it. A snapshot of the counters and the gold at the start gives the session's numbers
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

`LefthyToolsChronicleFrame` (Core/Window.lua's template, 780 x 620), opened with `/chronicle`,
`/lefthy chronicle`, the settings button, the key binding `LEFTHYTOOLS_CHRONICLE_TOGGLE` or the
minimap button (`C.Open(page)` opens it on a page). Six pages: Timeline, Statistics, Graphs,
Compare, Friends, Offline (tabs right to left from the top right corner, 80 px each, so six fit
right of the dropdown).

**Minimap button** (`MinimapButton.lua`, setting `minimapButton`, on by default; `/chronicle
minimap` switches it), made by `LT.Window.MinimapButton` (Core/Window.lua, shared with Beacon's
stream button): a child of `Minimap` (so it hides and fades with it) in the usual addon
look (`MiniMap-TrackingBorder`, `UI-Minimap-Background`, a book icon), `Minimap:GetWidth() / 2 + 5`
from the centre at the saved `minimapAngle` (degrees, 210 = lower left; square minimaps: on the
square's edge). Click toggles the journal, right-click opens the settings, the tooltip shows this
session and how much is new from friends. A small blue dot while there's news from friends the
journal hasn't shown yet (`C.UpdateNewDot`, on feed changes). Dragging sets an `OnUpdate` that turns
the cursor position into the angle and removes it on drop. Created on first use; Chronicle's
enable/disable and the setting update it on the next frame.
A dropdown at the top left (`LT.Window.AddPicker`, our own: a Blizzard menu opened from addon code
taints gamepad mode, see forever-platform.md): "Characters" (this one first, then the others by
name, "Name  Level 20", other realms named), then "Friends": every friend's character from
`C.People()` (synced journals, with their BattleTag's name; older builds' days: "(friend)"), the
picked one ticked. Picking a friend opens the Graphs page, the only one friends have. The list is
built when it opens; a refresh only sets the button's text. A click elsewhere closes it. Hidden on the Friends, Compare and Offline pages. Then the pages,
the open one's button greyed out:

- **Timeline:** newest first, a heading per day (`L["%Y-%m-%d"]`: German `%d.%m.%Y`), time, an
  inline icon (the item's or achievement's own where known) and the localized text. At most 250
  entries drawn, the rest summarized in one line.
- **Statistics:** sections This session (current character only), Character, Quests, Exploring,
  Combat, Travel, Gold and loot, Collections (the picked character), then All your characters
  (what means little per character: their count, time played, quests, killing blows, deaths,
  distance, jumps, added up over every character in `store.chars`) and the Martin tracker (all your
  characters too: AFK time `stats.afk`, `afkTimes`, `longestAfk`, counted on the tick from
  `UnitIsAFK("player")`; its share of the time played, this session's, and a verdict: under 5%
  "Always there", 15% "Takes a break now and then", 30% "Coffee enthusiast", above "Practically
  Martin"). Labels and values are two font strings with the
  same number of lines (values right-aligned), so the columns line up. Times as `1h 12m`/`4d 4h`,
  distance in km, gold with `GetMoneyString`.
- **Graphs** (`Graphs.lua`): cards on the scroll content. Last 14 days (bars per day from
  `daily`, buttons switch between time, XP, quests and killing blows (time AFK and jumps go per
  account: Compare); today in gold; hover shows the date and value), This session (the session curve: a line with a gradient fill, plus XP per
  hour; current character only), Time per level (a bar per level from `levelTimes`, up to 20,
  green = fast to red = slow), Favourite zones and Deadliest foes (horizontal bars, top 5), On
  the road and Loot by quality (one split bar each, with a legend). Drawn with plain textures
  (`SetGradient` for the bars), line objects (`CreateLine`) and font strings from pools
  (`G.NewCanvas`): a redraw reuses everything, nothing is created after the first draw.
- **Friends' graphs:** the dropdown lists every friend's character (`C.People()`; other pages fall
  back to your own character). Their page: Last 14 days (the same bars from their days), Last 7
  days (six tiles: time, XP, levels, quests, killing blows, deaths), You and <name> (two bars per
  number: time, XP, quests, kills; you in gold, them in blue), You and <name>, all time (from their
  profile) and Latest news (their last 6 feed entries with date).
- **Friends:** "Online now" first: every Beacon friend in up to three lines (`B.FriendLines` in
  Beacon's `Alerts.lua`, shared with the AFK screen: name, AFK, level and progress, group; zone
  and distance; what they're fighting and their quest), one grey line "Not online: N (Offline
  tab)" when there are any, then "What they did" right away (the user had to scroll past the
  offline friends to reach it):
  `C.FriendNews()` (synced highlights and live news, see below), as "Name: text", with a hint
  about what will appear while it's empty. Showing it marks the news seen (`C.MarkFeedSeen`): the
  tab's blue count and the book's blue dot (`C.UnseenCount`: news that came after
  `store.feedSeenAt`) go. Redrawn when the feed changes (at most every 3 s) and every 5 s.
- **Offline** (`G.DrawAway`, on the canvas): friends' characters not online (`C.People()`), most
  recently played first, as a table in one card ("Not online", the count in its corner): Name (class
  colour), Level, BattleTag (blue), Last played ("3 h ago"), This week (time played in 7 days),
  Latest news (icon, text, how long ago; cut to its cell). Rows alternate faintly; hovering one
  shows all of it (level and realm, BattleTag, last played, this week, the latest highlight with
  its date); a click opens their graphs (`Select`). Redrawn like Graphs (on changes at most every
  10 s, else every 30 s).
- **Compare** (`G.DrawCompare`): people, not characters (`C.Accounts()`, see below): you and every
  friend in every graph. A toolbar: 7 / 14 / 30 days, and a chip per person (their colour: the class colour, a
  second of the same class lighter, a third darker; you marked "(you)"; hover: level, BattleTag
  name, all their characters, online or last played; click: hidden from every graph and table,
  `compareState.hidden`).
  Then the big chart (full width): an icon per thing it can show above it (level, time played,
  XP, quests, killing blows, deaths, gold, distance, bosses and rares, time AFK, jumps;
  `compareState.big`, level at first), "Adding up" or "Per day" for the counted ones
  (`compareState.perDay`; level and gold are where the day ended, carried over days not played)
  and "Symbols": each person's most notable highlight of the day as an icon on their line (no line
  that day: at the bottom). The kinds, most notable first (`G.MARK_KINDS`): death, boss, level
  (every tenth only), first dungeon visit, rare, epic loot, achievement, mount, gold milestone;
  from my characters' journals and `C.FriendNews()` (matched to accounts by character name;
  `compareState.marks`, built in `Window.lua` on each draw). The day's tooltip lists everyone's
  value and highlights (two of a kind, six at most, "and N more"). The symbols switch's tooltip
  is the legend; off: `compareState.noMarks`. A click on a day of a small chart shows that chart
  big, scrolled to the top. The
  Leaderboard of the last 7 days (`C.Leaderboard`: nine categories, top three each, gold, silver,
  bronze; the Martin award), a grid of line charts (time played, XP, quests, killing blows per day;
  deaths, bosses and rares, jumps adding up over the range; gold where the day ended; distance and
  time AFK per day): a line per person (yours thicker), points while the range is 14 days or less,
  the leader in the card's corner, a hover per day with everyone's value, sorted. The Hall of fame
  (lifetime numbers from profiles: level, time, quests, kills, deaths, zones, dungeons, bosses,
  rares, distance, jumps; click a column header to sort; the best of each in gold) and Records
  (fastest level, longest session, most gold, most deaths, most time AFK, everyone's nemesis).
  "Share" on each chart and on the leaderboard posts the ranking in Lefthy chat (`C.ShareLine`:
  Beacon's `B.SendChat`; printed locally when Lefthy chat is off). Toolbar chips, column headers
  and Share are the canvas's hover areas with a click (`Canvas:Hover(..., onClick)`); a click
  redraws the page. Redrawn like Graphs (on changes at most every 10 s, else every 30 s).

Redrawn on the tick only while open, and only the open page when its own data changed:
`C.eventsDirty` for the timeline (a kill only changes a counter, so it doesn't rebuild 250
lines), `C.feedDirty` for Friends (at most every 3 s, like the book's blue dot: while journals
stream in the feed changes every second), `C.dirty` (counters) for Statistics, which also refreshes
every 5 s for the time and distance. Graphs: a change is remembered and drawn at most every 10 s,
otherwise every 30 s (the session curve). A redraw keeps the scroll position.

## Days for friends' graphs

Battle.net messages only arrive while both are online, so each friend's own Chronicle sends its
numbers: `D2;<YYYYMMDD>;<minutes played>;<xp>;<quests>;<kills>;<deaths>;<levels>` (about 45
bytes), and after it `K2;<YYYYMMDD>;<minutes AFK>` when that day had any AFK time (its own
message: builds before it reject a `D2` with another field and ignore kinds they don't know).
`StoreFriendDay` merges them: a `K2` sets only the day's `afk`, a `D2` keeps it. When Beacon
reports a friend as `known` (their name became known), they get my last 7 days; every 5 minutes
today's and yesterday's go to everyone if they changed (each message compared on its own). Both
go through Beacon's low-priority queue (`B.QueueLow`): sent only when no message, state or answer
waits, so they never delay live data. Beacon accepts up to 30 day messages per friend per minute
and checks the ranges (minutes at most 1440); Chronicle keeps 30 days per friend in
`store.friendStats`. Covered by the "Share highlights with friends" setting.

## Friends' journals, also when they're offline (Sync.lua)

Battle.net messages only reach friends who are online at the same time. So every client keeps
what it learned about friends (`store.book`) and passes it on: whoever is online brings the news of
whoever isn't. Journals go per Battle.net account, named by a hash of its BattleTag (`C.Hash`: two
rolling 32-bit hashes of the lowercased BattleTag folded into 8 hex digits; the BattleTag itself
is never sent). A client only asks for, and only keeps, accounts whose hash matches one of its own
Battle.net friends (`C_BattleNet.GetFriendAccountInfo(i).battleTag`, online or not, cached 30 s):
nobody gets the journal of someone who isn't their friend. My own account: `BNGetInfo()`'s
BattleTag.

**What I publish** (setting `share`; `shareAlts`: all my characters, else the one I play):
- days: 30 days, `played, xp, quests, kills, deaths, levels, afk, level, gold, dist, bosses, rares,
  runs, jumps` (played and AFK in minutes on the way, seconds when kept);
- highlights: timeline entries of the kinds friends may see (`C.Shareable`: level, death, zone,
  dungeon, boss, rare, epic loot, mount, achievement, quests and gold milestones, profession; no
  pets, toys, blue loot or single quests), numbered per character (`e.n`), 30 days, at most 150;
- a profile: lifetime numbers (time, sessions, quests, kills, deaths, zones, dungeons, runs,
  bosses, rares, distance, jumps, mounts, achievements, most gold, fastest level, longest session,
  AFK, epics, levels, XP), the deadliest foe and favourite zone, class, level, when last played.

Every record has a stamp `u` from its author (`NextU`: `time()`, always above the last one,
`store.myU`). Stamps: a highlight when recorded (`C.Stamp` from `Record`); a day when its numbers
(as text) changed, checked every 60 s for today and yesterday (`StampChar`); the profile every
5 min. After an update, highlights from before get numbers with their own time (`Upgrade`), and
every character's days and profile get stamps. Switching `shareAlts` restamps everything, so
friends ask again.

**Messages** (Beacon kind `J`, older builds ignore it; low priority except requests):
`J2;h;<acct>` I sync (with every answer to a hello, and to everyone when Chronicle is switched on),
`J2;s;<acct>,<u>/...` what I hold (per account: complete up to u; ten per message; to a friend
who syncs when it grew since they last heard it, at most every 60 s, everything the first time;
their own account left out), `J2;q;<acct>;<since>` send me that account's records newer than since,
`J2;p;<acct>;<Name-Realm>;<u>;<class>;<level>;<last>;<21 numbers>;<foe>;<zone>` (foe and zone left
out if it wouldn't fit 250 bytes), `J2;d;<acct>;<Name-Realm>;<u>;<YYYYMMDD>;<14 numbers>`,
`J2;n;<acct>;<Name-Realm>;<u>;<n>;<t>;<kind>;<a>;<b>` (the two text fields like Beacon's E2, 60
bytes each), `J2;c;<acct>;<count>` the answer had count records (just before its end; older
builds don't send it and ignore it), `J2;e;<acct>;<u>` that's all: complete up to u. A summary with a friend's account I
hold less of starts a request (one friend at a time per account; 90 s without a record: it can go
to another). An answer is at most 400 records, oldest first (records with the same stamp as the
last one go along, so the cut never splits a stamp); its end says how far it got, so the
rest comes on the next round. The end completes the account only when as many records came as
the count said (else it's asked again on the next offer) and its stamp is plausible (at most a
week ahead). Records are checked (fields, sizes, kinds, 30 days, not tomorrow)
and kept only for my friends' accounts, newer stamps replacing older. Requests are queued
(`serves`, at most 50, a repeat replaces the waiting one) and answered on the tick, two per
second, never inside the event. Everything is offered again every 5 minutes (`FULL_OFFER`: an
offer missed or an answer cut short). `relay` off: I don't pass on what I hold of others (a
request gets an empty end). Beacon accepts 700 J messages per friend per minute.

**Keeping the book small:** a minute after starting (the friend list is known by then), accounts
that are no longer my Battle.net friends go, and characters with nothing in the last 60 days
(`BOOK_DAYS`). An account's stamp that can't be real (more than a week ahead) is reset to 0 on
start: everything is asked again. With "all my characters" off, playing another character than
last time restamps its records, so friends who hold the other one ask for it.

**Known limit:** one stamp per account. Playing the same Battle.net account on two PCs (two
SavedVariables) makes two authors: a friend who already holds the newer stamps of one PC won't
ask for the older ones of the other until they change again.

**People and news for the window** (`C.People()`): me (the character I play: its days, numbers
from `C.ProfileNumbers`), then every friend's character from the book (`book:<acct>:<Name-Realm>`;
last played from the profile or the latest day played; online if a Beacon peer has that name),
then friends on older builds from the days they sent (`store.friendStats`, `friend:<Name>`), by
name. `C.Accounts()`: the same per Battle.net account (me: all of `store.chars`; friends: their
account's characters; older builds: one character each), each day's activity added up over the
account's characters (time, XP, quests, kills, deaths, levels, AFK, distance, bosses, rares, runs,
jumps), the level of the character played most that day, gold summed over each character's last
known; lifetime numbers summed where they add up, else the best (zones, dungeons, most gold,
longest session; fastest level the lowest); named after the character played most in 30 days (mine:
the one I play), its class colour, foe and zone. Compare, the leaderboards and the recap use it.
`C.FriendNews()`: every synced highlight plus the live feed (`store.friends`: Beacon's
level-ups, deaths, online and offline, E2 highlights), oldest first; a live entry that a synced
one repeats (same name, kind and first field within 15 minutes) is left out. Rebuilt only when
something changed.

**While you were away** (`catchUp`): when Chronicle starts more than 5 minutes after its last tick
(`store.lastSeenAt`), 75 s later (up to 4 minutes while journals still come in) a chat line per
friend with what they did since: the most notable three (level-ups first), zones and deaths
counted ("died 3 times"), "+N more". **Weekly recap** (`weeklyRecap`): 2 minutes after starting,
once per week (`store.recapWeek`, the week's Monday): last week's leader of each category, if at
least two people played. Both in English like all chat output.

## Cost, and what goes over the network

The 1-second tick is local only: a few cheap API reads (position, target), adding up counters,
and a session point per minute. Nothing is sent from it except highlights, which are rare (a few
per hour at most) and go through Beacon's rate limiter like everything else. The AFK screen shows a session line
(`ns.AFKScreen.sections`).
