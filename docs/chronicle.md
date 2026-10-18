# Chronicle design

A journal per character, kept automatically, plus statistics and a feed of what friends with
LefthyTools did, also while they (or you) weren't online. Recorded per character; a character
belongs to an account (a Battle.net account: a BattleTag), shown beside it, never mixed with it (see
Characters and accounts). Files, in load order: `Modules/Chronicle/Chronicle.lua` (recording,
session, settings, `/chronicle`, formatting helpers), `Live.lua` (friends live through Beacon: E2
highlights, D2/K2 days, the feed), `Characters.lua` (who is who:
accounts, names, matching; the characters, accounts and news every page uses), `Sync.lua` (friends'
journals: publishing, passing on), `Recap.lua` (chat: catch-up, weekly recap, sharing; the
leaderboards), `Canvas.lua` (the pages' drawing kit: a pooled canvas, cards, bars, tables),
`Graphs.lua` (the Graphs page, a friend's too), `Compare.lua` (the Compare page), `Window.lua` (the
window) and `MinimapButton.lua`. They share `ns.Chronicle` (`C`).

## Data

`LefthyToolsChronicleDB` (account-wide saved variable, so every character's journal can be
browsed from any character):

- `chars["Name-Realm"]`: `name` (the key's: the first name), `full` (the name the game shows: first
  name and surname, from `UnitName`'s two returns), `guid`, `realm, classFile, race, level, first`
  (when Chronicle first saw it), `events` (the timeline, oldest first, at most 1000), `stats` (counters, below),
  `zoneTime[zone]`, `killers[name]`, `levelTimes[level]`, `fastestLevel`, `levelStart`,
  `levelCounts[level] = { kills, quests }` (during that level; `levelFrom` holds the counters at
  the level's start), `professions[name]`, `seen = { zones, dungeons, bosses, rares }` (rares by GUID: one spawn
  counts once), `days[YYYY-MM-DD]`, `session = { start, stats, money }`, `playedTotal` (what
  `/played` last said; Chronicle never asks itself, that would print in chat).
- `friends`: the feed, `{ t, name, classFile, acct, k, ... }`, oldest first (`name`: the full name
  Battle.net gives, `acct`: their account, see Characters and accounts). Each kind keeps a share of
  its own, 300 in all (`FEED_KEEP` in Live.lua): quests turned in 80, coming online and going
  offline 50, zones 40, level-ups 30, deaths 30, the highlights (bosses, rares, dungeons, loot,
  mounts, achievements, milestones, professions) 70; a new entry pushes out the oldest of its kind
  only. One list of 300 let a busy quest day push out a boss kill (a real feed held 126 quests of
  300). A feed saved before is cut down to the shares when Chronicle starts, oldest first.

For the graphs: `daily["YYYY-MM-DD"] = { played, xp, quests, kills, deaths, levels, afk, bosses, rares,
runs, jumps, dist, level, gold }` (kept 60 days; `Add` fills today's bucket for the counters in
`DAILY` (stat -> day key: `dungeonRuns` -> `runs`), `TrackTravel` adds `dist` (yards), the tick sets
`level` and `gold` (whole gold held) to where the day ends), and `session.series`, a point
`{ played, xp, money }` per minute of play (at most 240: when full, every other point goes and the
step doubles). `sync` (Sync.lua): the character's highlight counter and its days' and profile's
stamps. `store.book`: friends' journals (below); `store.lastSeenAt`, `feedSeenAt`, `recapWeek`,
`myU`, `sharedAlts`, `identity` (1: the saved data's characters have been matched once, below).

**The record's key** is the first name and realm (`UnitName`'s first return, as friends' builds
have always known it), unless another character of mine has that first name on the realm (its
`guid`, or a different `full` name, says so): then this one's key is its full name ("Cara
Brightwater-Realm"), and so is its `name`. A new character takes the first name's key. `full` is
set at every login; a surname known from before stays when `UnitName` doesn't give one that time.

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
| `death` (zone, subzone, foe, level) | `PLAYER_DEAD`; foe = your last attackable target while in combat, if within 15 s (the tick notes it). Once per death: the game can fire it again within seconds, so it counts again only after the tick has seen you alive (`UnitIsDeadOrGhost`), 10 s at the earliest (`DEATH_REPEAT`; a /reload while dead isn't another). Deaths saved twice before (mine, friends' journals) are shown once: the Timeline, News and Compare's symbols leave out a character's death within 10 s of the one before |
| `zone` (first visit) | tick after `ZONE_CHANGED_NEW_AREA` / `PLAYER_ENTERING_WORLD`, `GetRealZoneText` |
| `dungeon` (first visit; every entry counts as a run) | same, `IsInInstance` party/raid + `GetInstanceInfo` |
| `boss` (first kill of each; every kill counted) | `ENCOUNTER_END` with success, or `BOSS_KILL`; the same name within 30 s counts once |
| `rare` | your target is rare/rareelite/worldboss, not a player, dead and not someone else's tap (`UnitIsTapDenied`), checked on the tick; also `PARTY_KILL` on your target |
| `loot` (blue and better; with the item's icon) | `CHAT_MSG_LOOT` matched against `LOOT_ITEM_SELF(_MULTIPLE)` and `LOOT_ITEM_PUSHED_SELF(_MULTIPLE)` turned into patterns, so only your own loot, in any client language; quality from `C_Item.GetItemQualityByID`, else the link's `|cnIQ<n>:` (`LT.OwnLoot` in Core.lua, shared with the fight stream) |
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
driver hidden. The driver resets its timer before the tick, so an error in it can't make it run
every frame; the other files' hooks (`C.ShareDays`, `C.SyncTick`, `C.ShareHighlights`,
`C.OnTick`) go through `LT.Guard` (architecture.md): one that fails is reported once and rests,
and the rest of the tick goes on. A redraw that failed keeps its page marked for the next one.

## Friends and sharing (Live.lua)

Highlights go to friends through Beacon (`ns.Beacon.ShareHighlight`, on the tick, only with
Beacon on and `share` on) as `E2;<kind>;<a>;<b>`: boss (name, instance), rare (name, zone),
dungeon (name), loot (name, quality; epic and better only), mount (name), achievement (name),
quests (count), gold (amount), profession (name, level), and for the feed only (no chat line)
quest (every quest turned in: its title) and zone (first visit). Pets, toys and blue loot stay
private. Beacon accepts at most 10 highlights per friend per minute and only known kinds, and
passes them on as `B.Notify("highlight", peer, { kind, a, b })`. Chronicle's listener puts them,
and Beacon's `level`, `death`, `online` and `offline` events, into the feed (with the friend's
account, `C.PeerAccount`, so the window finds the character in their journal), and prints a chat
line for highlights except quest and zone (English, `friendsChat`). Friends' level-ups and deaths
already have their own lines. `online`: a friend's name became known more than a minute after
Beacon started (friends already online at login aren't news); `offline`: a known friend was
forgotten (went offline, silent for 65 s, or switched Beacon off).

## Window

`LefthyToolsChronicleFrame` (Core/Window.lua's template, 780 x 620), opened with `/chronicle`,
`/lefthy chronicle`, the settings button, the key binding `LEFTHYTOOLS_CHRONICLE_TOGGLE` or the
minimap button (`C.Open(page)` opens it on a page). Six pages: Timeline, Statistics, Graphs,
Compare, News, Friends (tabs right to left from the top right corner, 80 px each, so six fit
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
**Characters and accounts.** A character is shown once, by the name the game shows ("Anna Brook":
first name and surname, see Characters and accounts below), and an account (a Battle.net account,
a BattleTag) by its own name ("You", a friend's BattleTag's name), never by one of its characters'.
Graphs, leaderboards, the hall of fame, records and the lists of friends go by character (the
BattleTag beside it where it matters: a column on the Friends page, a chip's hover); the dropdown,
your Statistics, Timeline and Graphs and a friend's graphs go by account (all its characters added
up, the characters named in it). Only what a character has on its own stays per character there:
its level and class colour, its time per level, and the session going on now (the character you
play). Mine: `C.Totals()` (Chronicle.lua: every record in `store.chars` as one: counters added up,
the longest session, longest AFK and most gold the best of them, time per zone and deadly foes added
up, zones, dungeons and days played joined, each day's counters added up; `current` the character
I play, `chars` all of them, it first, then by time played). Friends': `C.Accounts()` (below).

A dropdown at the top left (`LT.Window.AddPicker`, our own: a Blizzard menu opened from addon code
taints gamepad mode, see forever-platform.md) picks the account, one entry each: "You" with your
characters and their levels ("You  Cara Moss 20, Alty 12", key `me`), then "Friends": everyone from
`C.Accounts()` by their BattleTag's name with their characters, the one they play most first
("Annie  Anna Brook 20, Annalt 12", key `acct:<hash>`; a character whose BattleTag isn't known:
"Anna Brook 20  (friend)", its character key), the picked one ticked. Picking a friend opens the Graphs
page, the only one friends have. The list is built when it opens; a refresh only sets the button's
text. A click elsewhere closes it. Hidden on the News, Friends and Compare pages. Then the pages,
the open one's button greyed out:

- **Timeline:** all your characters' journals in one, newest first, a heading per day
  (`L["%Y-%m-%d"]`: German `%d.%m.%Y`), time, an inline icon (the item's or achievement's own where
  known), whose it is ("Alty Moss: ", once there's more than one character with entries) and the
  localized text. At most 250 entries drawn (only each character's newest 250 are merged), the rest
  summarized in one line.
- **Statistics** (yours, `C.Totals()`): sections This session (the session going on), Characters
  (a row per character: its full name in its class colour, other realms named, and its level: what only a
  character has), Time (time played since Chronicle; `/played` added up once every character has
  said it; days played, sessions, longest session, fastest level, average per level), Quests,
  Exploring, Combat, Travel (distance, by foot/riding/swimming/flight, jumps), Gold and loot (gold
  now: the character you play's plus where the others' last day ended), Collections, and the Martin
  tracker (AFK time `stats.afk`, `afkTimes`, `longestAfk`, counted on the tick from
  `UnitIsAFK("player")`; its share of the time played and a verdict: under 5% "Always there", 15%
  "Takes a break now and then", 30% "Coffee enthusiast", above "Practically Martin"; the only place
  time AFK shows). Labels and values are two font strings with the same number of lines (values
  right-aligned), so the columns line up. Times as `1h 12m`/`4d 4h` (`C.Duration`; a day is `T` in
  German, `4T 4h`, through `L["%dd %dh"]`; chat lines, which stay English, ask for `d`), distance in
  km, gold with `GetMoneyString`.
- **Graphs** (`Graphs.lua`, yours: `C.Totals()`): cards on the scroll content. Last 14 days (bars
  per day from the added-up `daily`, buttons switch between time, XP, quests, killing blows and time
  AFK; today in gold; hover shows the date and value), This session (the session curve: a line with
  a gradient fill, plus XP per hour), Time per level: <the character you play> (a bar per level from
  its `levelTimes`, up to 20, green = fast to red = slow), Favourite zones and Deadliest foes
  (horizontal bars, top 5), On the road and Loot by quality (one split bar each, with a legend).
  Drawn with plain textures (`SetGradient` for the bars), line objects (`CreateLine`) and font
  strings from pools (`G.NewCanvas`, Canvas.lua): a redraw reuses everything, nothing is created after the first
  draw. A hover area's tooltip (`Canvas:Hover`, every page on the canvas) lets a long line wrap
  (`AddLine(..., true)`), so the tooltip keeps a readable width instead of growing with its longest line.
  A redraw keeps an open tooltip: hiding the area under the mouse closed it (its owner gone), and the
  game opens it again only when the mouse moves, so the Friends page's redraw every 5 s closed it
  under a resting mouse. The page draws start with `Canvas:Reset(true)`, which leaves the area whose
  tooltip is open (`GameTooltip:IsOwned`) shown, and the window calls `Canvas:Done()` after the draw:
  the tooltip shows the area now under the mouse (`IsMouseOver`: the same row, unless the rows
  moved), filled from its new lines, or closes; the old area goes if the draw didn't use it. A
  hover area's `OnLeave` closes only its own tooltip. Nothing extra while no tooltip of ours is open.
- **Friends' graphs:** a friend picked in the dropdown (other pages fall back to you): their
  account from `C.Accounts()`, compared with mine from there (both all characters), named by the
  account (their BattleTag's name). Last 14 days (the same bars from their days), Last 7 days
  (seven tiles: time, XP, levels, quests, killing blows, deaths, time AFK), You and <account> (two
  bars per number: time, XP, quests, kills, time AFK; you in gold, them in blue), You and
  <account>, all time (from their profiles) and Latest news (the last 6 feed entries of any of
  their characters, with date; the character's name when they have more than one).
- **News:** "What they did": `C.FriendNews()` (synced highlights and live news, see below), as
  "Name: text" (the character's full name), one line per event, newest first by day, with a hint
  about what will appear while it's empty. Showing
  it marks the news seen (`C.MarkFeedSeen`): the tab's blue count and the book's blue dot
  (`C.UnseenCount`: news that came after `store.feedSeenAt`) go. Redrawn when the feed changes (at
  most every 3 s). (Once one page with who's online, who isn't and the news; the user had to scroll
  too far to reach the news, so they're separate now.)
- **Friends:** everyone at a glance, two tables (`G.DrawTables` in Canvas.lua: a card each, a
  header row, a row per entry with faint alternate stripes; a cell is text, cut to its width, or an
  icon and text; a row's hover shows all of it, a click opens their account's graphs through
  `Select` when it has any). A row per character, by its full name, its account's BattleTag in a
  column of its own. **Online now**: Beacon's friends (`B.FriendList`, `B.FriendStatus` in
  Alerts.lua): Name (class colour, <AFK>), Level (and progress), BattleTag (`C.PeerChar`: their
  account from Battle.net), Where (zone - subzone, distance), Doing (dead or fighting, else the
  quest they track, else "In your group"); the hover is `B.FriendLines` (the AFK screen's lines)
  plus the BattleTag and that character's latest highlight. Beacon off or nobody online: a line
  says so. **Not online**: a row per friend's character (`C.Characters()`) whose account has none
  online (someone playing one character isn't listed again with the others), most recently played
  first: Name, Level, BattleTag, Last played ("3 h ago"), This week (its time played in 7 days),
  Latest news (icon, text, how long ago); the hover adds the realm, the account's characters with
  their levels (up to three on one line; more one per line, the most played first, at most 10 and
  "... and N more": one line of them made the tooltip very wide) and the highlight's date. The corners count friends online and characters not
  online. Redrawn every 5 s (who's online and where changes all the time) and on feed changes (at
  most every 3 s); a row's tooltip stays open through it (see Graphs: a redraw keeps an open tooltip).
- **Compare** (`G.DrawCompare`, Compare.lua): characters (`C.Characters()`, see below), yours and every
  friend's, in every graph, by character names only. A toolbar: 7 / 14 / 30 days, and a chip per
  character (its colour: the class colour, a second of the same class lighter, a third darker;
  yours marked "(you)"; hover: level, BattleTag name, online or last played; click: hidden from
  every graph and table, `compareState.hidden`).
  Then the big chart (full width): an icon per thing it can show above it (level, time played,
  XP, quests, killing blows, deaths, gold, distance, bosses and rares, time AFK, jumps;
  `compareState.big`, level at first), "Adding up" or "Per day" for the counted ones
  (`compareState.perDay`; level and gold are where the day ended, carried over days not played)
  and "Symbols": each character's most notable highlight of the day as an icon on its line (no line
  that day: at the bottom). The kinds, most notable first (`G.MARK_KINDS`): death, boss, level
  (every tenth only), first dungeon visit, rare, epic loot, achievement, mount, gold milestone;
  from my characters' journals and `C.FriendNews()` (each entry knows its character's key;
  `compareState.marks`, built in `Window.lua` on each draw). Two kinds of tooltip (one listing
  everything was far too big): a symbol's own (a raised hover area, `Canvas:Hover(..., raised)`,
  above the day's): that character's moments of the day only (two of a kind, five at most, "and N
  more"; symbols within 8 px of each other share one); the day's: a line per character with the value
  and up to three small icons, one per kind, and "Hover a symbol for what happened." The symbols
  switch's tooltip is the legend; off: `compareState.noMarks`. A click on a day of a small chart shows that chart
  big, scrolled to the top. The
  Leaderboard over the range picked, like the charts (7, 14 or 30 days, `compareState.range`; the
  title says which; `C.Leaderboard`: nine categories, top three each, gold, silver, bronze; the
  Martin award; characters hidden by their chip left out, also when shared), a grid of line charts (time played, XP, quests, killing blows per day;
  deaths, bosses and rares, jumps adding up over the range; gold where the day ended; distance and
  time AFK per day): a line per character (yours thicker), points while the range is 14 days or less,
  the leader in the card's corner, a hover per day with everyone's value, sorted. The Hall of fame
  (lifetime numbers from profiles: level, time, quests, kills, deaths, zones, dungeons, bosses,
  rares, distance, jumps; click a column header to sort; the best of each in gold) and Records
  (fastest level, longest session, most gold, most deaths, most time AFK, everyone's nemesis).
  "Share" on each chart and on the leaderboard posts the ranking in LTC (`C.ShareLine`:
  Beacon's `B.SendChat`; printed locally when LTC is off). Toolbar chips, column headers
  and Share are the canvas's hover areas with a click (`Canvas:Hover(..., onClick)`); a click
  redraws the page. Redrawn like Graphs (on changes at most every 10 s, else every 30 s).

Redrawn on the tick only while open, and only the open page when its own data changed:
`C.eventsDirty` for the timeline (a kill only changes a counter, so it doesn't rebuild 250
lines), `C.feedDirty` for Friends (at most every 3 s, like the book's blue dot: while journals
stream in the feed changes every second), `C.dirty` (counters) for Statistics, which also refreshes
every 5 s for the time and distance. Graphs: a change is remembered and drawn at most every 10 s,
otherwise every 30 s (the session curve). A redraw keeps the scroll position.

## Days for friends' graphs (Live.lua)

Battle.net messages only arrive while both are online, so each friend's own Chronicle sends its
numbers: `D2;<YYYYMMDD>;<minutes played>;<xp>;<quests>;<kills>;<deaths>;<levels>` (about 45
bytes), and after it `K2;<YYYYMMDD>;<minutes AFK>` when that day had any AFK time (its own
message: builds before it reject a `D2` with another field and ignore kinds they don't know).
`StoreFriendDay` merges them, by the full name Battle.net gives (`store.friendStats[name]`): a `K2`
sets only the day's `afk`, a `D2` keeps it. It also keeps the sender's account as `acct`
(`C.PeerAccount`: the hash of the BattleTag Battle.net gives for the peer's GUID) and their `guid`,
so the window finds the character in their journal and counts those days for it, where the journal
has none (older builds keep the fields and ignore them). When Beacon
reports a friend as `known` (their name became known), they get my last 7 days; every 5 minutes
today's and yesterday's go to them again if they changed (each message compared on its own). Only
friends whose build needs them get these (`NeedsDays`): builds from 0.5.0-80 on (94d1d36,
`JOURNALS_SINCE`) sync journals and get my days as "d" records with my journal (Sync.lua), so the
old messages only go to builds before it, which read nothing else; a friend whose version hasn't
come yet (Beacon's `peer.version`, V2), or whose build doesn't say its commit count
(`0.5.0-g1a2b3c4`: `LT.CompareVersions` can't tell), gets them as before, and so does everyone
while my own journal can't be offered (my BattleTag not known). (Before, every /reload of mine sent
every friend 7 days again, journal or not.) Both
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
  AFK, epics, levels, XP), the deadliest foe and favourite zone, class, level, when last played;
- with the profile's stamp, the character's full name and GUID (an "a" record, below).

A character goes by its record's key (`<Name-Realm>`: the first name's, see Data) in every record,
as every build has known it.

Every record has a stamp `u` from its author (`NextU`: `time()`, always above the last one,
`store.myU`). Stamps: a highlight when recorded (`C.Stamp` from `Record`); a day when its numbers
(as text) changed, checked every 60 s for today and yesterday (`StampChar`); the profile every
5 min (its text includes the full name and GUID: a new one is stamped too). After an update,
highlights from before get numbers with their own time (`Upgrade`), and
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
bytes each), `J2;a;<acct>;<Name-Realm>;<u>;<full name>;<guid>` (with the profile's stamp; older
builds ignore words they don't know, and don't keep or pass it on; kept as the book character's
`full`, `guid`, `aliasU` when its first name is the key's, newer stamps replacing older; a holder
passes it on with the rest; one that only reached me through an older build comes with the next
profile stamp, or Battle.net tells the name when that character is online),
`J2;l;<acct>;<Name-Realm>;<full name>;<guid>` a full name I learned, not from its author
(Battle.net, an older build's days; no stamp: no author made it), with every answer about that
account whatever it asked since (counted in its `c`), and to the account's owner when they say
hello (`Learned`); both only to builds that read it (0.5.0-176 on, ba4dbad, `NAMES_SINCE`; one
whose version isn't known yet or has no commit count gets it as before; older builds' answers
count without it); taken only by a character that doesn't know its surname yet, never instead of
one it knows (`StoreName`): a friend's journal's, or an alt of mine (not the one I play), which
then sends it on as its own, with a new profile stamp (builds before it ignore the word; those that
count an answer's records count it too, so the count matches), `J2;c;<acct>;<count>` the answer
had count records (just before its end; older
builds don't send it and ignore it), `J2;e;<acct>;<u>` that's all: complete up to u. A summary with a friend's account I
hold less of starts a request (one friend at a time per account; 90 s without a record: it can go
to another). An answer is at most 400 records, oldest first (records with the same stamp as the
last one go along, so the cut never splits a stamp); its end says how far it got, so the
rest comes on the next round. The end completes the account only when as many records came as
the count said (else it's asked again on the next offer) and its stamp is plausible (at most a
week ahead). Records are checked (fields, sizes, kinds, 30 days, not tomorrow; numbers of at most 10
digits, a level of at most 3, a day's minutes played or AFK at most 1440; a character key without
escape codes or control characters, `ValidKey`: pages show it as a name) and kept only for my
friends' accounts, newer stamps replacing older. Requests are queued
(`serves`, at most 50, a repeat replaces the waiting one) and answered on the tick, two per
second, never inside the event. Everything is offered again every 5 minutes (`FULL_OFFER`: an
offer missed or an answer cut short). `relay` off: I don't pass on what I hold of others (a
request gets an empty end). Beacon accepts 700 J messages per friend per minute.

**Keeping the book small:** a minute after starting (the friend list is known by then), accounts
that are no longer my Battle.net friends go, and characters with nothing in the last 60 days
(`BOOK_DAYS`). An account keeps at most 30 characters (`CHARS_KEPT`), the most recently played
(its profile's last played, else its latest day or highlight): a real account has a handful within
60 days (the most in a real book: 6), so this only stops a broken or hostile client from filling
the saved data with characters. Checked when a record brings a character new to the account (the
new one goes if it's the least recent), and on start for what was saved before. One that went comes
back with its next records (its older ones aren't asked for again: the account is complete up to
its stamp). An account's stamp that can't be real (more than a week ahead) is reset to 0 on
start: everything is asked again. My own last stamp that far ahead (`store.myU`: the clock was wrong
once; friends drop records stamped beyond a week, and new stamps would go on from it) restamps
everything of mine from now on start. With "all my characters" off, playing another character than
last time restamps its records, so friends who hold the other one ask for it.

**Known limit:** one stamp per account. Playing the same Battle.net account on two PCs (two
SavedVariables) makes two authors: a friend who already holds the newer stamps of one PC won't
ask for the older ones of the other until they change again.

**While you were away** (`catchUp`): when Chronicle starts more than 5 minutes after its last tick
(`store.lastSeenAt`), 75 s later (up to 4 minutes while journals still come in) a chat line per
friend's character with what it did since, up to when Chronicle started (what came after came live,
with its own chat line): the most notable three (level-ups first), zones and deaths
counted ("died 3 times"), "+N more". **Weekly recap** (`weeklyRecap`): 2 minutes after starting,
once per week (`store.recapWeek`, the week's Monday): last week's leading character of each
category, if characters of at least two accounts played. Both in English like all chat output.

## Characters and accounts

A character in WoW: Forever has a first name and a surname. `UnitName` gives them apart (the
surname as its second return: Blizzard's `NameUtil.FormatUnitNameForDisplay` joins them with a
space), the game shows them together ("Anna Brook"), and so does Battle.net (`characterName`, so
Beacon's `peer.name`). Journals have always gone by the first name and realm ("Anna-Realm", the key
every build sends), while Beacon's live news (`store.friends`) and older builds' days
(`store.friendStats`) go by the full name: the same character arrived under two names, and showed
up twice (news twice, its days counted twice, a row each, an account's row next to its own).

So every character has one identity: mine its `store.chars` key (`me:<key>`), a friend's its
journal's (`book:<acct>:<Name-Realm>`), and one only known from live days its name
(`friend:<full name>`). Characters.lua matches a full name from Battle.net (with the friend's account,
class and GUID where known) to a journal's character (`FindBook`): by GUID; else by the full name
(the journal's own from its author's `a` record, or learned); else by the first name while the
journal doesn't know the full one, within their account, if exactly one character fits and its
class is the same. A match that isn't unique isn't made: two characters are never taken for one (an
alt of the same account with another first name, "Anna" and "Annabel", stays apart). A match
teaches the journal what it didn't know (`Learn`: the GUID, and the name the game shows, also one
without a surname, which is then all of it; one it knows, its author's or learned, only changes to
one that adds the surname, or on a GUID match, a rename, and never to one without a surname). Without
the account, only GUID and full name count.

**Battle.net tells it** (`Meet`, on the tick every 30 s, the first 10 s after starting): a walk over
the friend list (`C_BattleNet.GetFriendAccountInfo`, `GetFriendNumGameAccounts`,
`GetFriendGameAccountInfo`: every game account of each friend, so also one they play on besides
the one Battle.net shows first) takes every character a friend is online on in WoW: Forever (online,
the WoW client, the current region, `WOW_PROJECT_ID`), whatever they run (an older LefthyTools, none,
Beacon off), and matches it within their account (their BattleTag's hash) to the journals I hold
(`FindBook`, `Learn`). Beacon's friends teach it too (`C.PeerChar`, when a page asks), but only
those with LefthyTools. Each game account is read under `pcall`: one Battle.net keeps secret is skipped.
What I learned this way goes on to friends who hold that journal, and to its owner (`J2;l`, below):
an alt they haven't played since their update gets its surname from whoever saw it online, and
their journal sends it on as its own.

**A name not known in full.** A journal from an older build only ever says the first name (the
key's), so a character of it that Battle.net hasn't shown online since, and an alt of mine not played
since this build, have no `full` (`C.Partial`; one keyed by its full name, see Data, has its surname
in the key: not partial, and no learned name replaces it). Every place that shows a character shows it by its
first name with a muted mark (`C.Mark`: a grey "?" after it; " (?)" in LTC, which can't colour),
never as if that were all of it (in Forever every character has a surname): the Friends page, Compare
(chips, charts, leaderboard, hall of fame, records), News, the dropdown, a friend's latest news, my
Timeline and Statistics, the catch-up and the weekly recap. A hover says when the surname comes
(`C.PartialHint`: a friend's when they play it while I'm online, or with an up-to-date LefthyTools,
naming their BattleTag; mine when I log in on it); text pages say it in a line under the list when a
marked name is on them. `C.Characters()` and `C.FriendNews()` entries carry `partial`.

`C.Characters()` lists every character once, by the name the game shows (`C.NameOf`: `full`, else
`name`): mine (days, numbers from `C.ProfileNumbers`, the one I play first), then my friends', by
name: from their journals (last played from the profile or the latest day played, joined by their
live days where the journal has no day), then characters only known from live days (with their
account when known). Each has `online` (a Beacon friend plays it: `C.PeerChar(peer)`) and
`accountOnline` (one of its account's characters is), `acct` and `account` (its BattleTag's
name). Compare, the leaderboards, the recap and the Friends page use it. `C.Accounts()`: the same per
Battle.net account (me: all of `store.chars`; friends: their account's characters; a character
whose account isn't known: on its own), each day's activity added up over the account's characters
(time, XP, quests, kills, deaths, levels, AFK, distance, bosses, rares, runs, jumps), the level of
the character played most that day, gold summed over each character's last known; lifetime numbers
summed where they add up, else the best (zones, dungeons, most gold, longest session; fastest level
the lowest); named after the account ("You", the BattleTag's name; a lone character whose account
isn't known by its own name), the class colour, foe and zone of the character played most in 30
days (mine: the one I play). The dropdown and a friend's graphs use it. `C.FriendNews()`: every
synced highlight plus the live feed (Beacon's level-ups, deaths, online and offline, E2
highlights), oldest first, each with its character's key and full name; a live entry that a synced
one of the same character repeats (same kind and first field within 15 minutes) is left out.
Rebuilt only when something changed (a name learned counts).

**Saved data from before** (`JoinCharacters`, once: `store.identity`): older builds' days saved
without their account are matched over all the journals kept (also before the friend list is known
at login) by the same rules, and only where the days both have agree too (the live day, sent while
it went on, is never more than the journal's day, and on some day about the same); then the feed's
entries, by the full names that taught the journals. The account is noted with them (`acct`) and the
journal learns the full name. Nothing is deleted or moved.

## Cost, and what goes over the network

The 1-second tick is local only: a few cheap API reads (position, target), adding up counters,
and a session point per minute; every 30 s a walk over the Battle.net friend list (`Meet`, a few
calls per friend online). Nothing is sent from it except highlights, which are rare (a few
per hour at most) and go through Beacon's rate limiter like everything else. The AFK screen shows a session line
(`ns.AFKScreen.sections`).
