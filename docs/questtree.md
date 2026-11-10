# Questtree

Quest chains for every zone of WoW: Forever: what a quest needs first, what it leads to, who gives
and takes it and where, and where each quest stands for you and your friends.

| File | What |
|---|---|
| `Modules/Questtree/Data.lua` | the quest data (`LefthyTools_QuestData`): loading it, the accessors, search, learned data |
| `Modules/Questtree/Engine.lua` | a quest's status for me or a friend, what's missing, what it opens, its chain, what's next |
| `LefthyTools_QuestData/` | the data, an add-on of its own (load on demand, GPL v3) |
| `tools/update-quest-data.js` | makes the data |
| `Modules/Questtree/Questtree.lua` | the module: settings, `/questtree`, shared helpers (status and difficulty colours, titles, distances, the map pin), NPC tooltip lines, the quest log hook |
| `Modules/Questtree/MiniMap.lua` | the small zone map (our own frame, the zone's map art, the game's quest icons, drop areas, zoom, your arrow) |
| `Modules/Questtree/Small.lua` | the small window, the companion: the quest you're on and what to pick up next nearby; any quest looked at |
| `Modules/Questtree/Questtree.lua` | the module: settings, `/questtree`, shared helpers (status colours, titles) |
| `Modules/Questtree/MiniMap.lua` | the small zone map (our own frame, the zone's map art) |
| `Modules/Questtree/Small.lua` | the small window: one quest, what it needs, giver and turn-in on the small map |
| `Modules/Questtree/Browser.lua` | the big window: zones; a zone's map beside its chains' cards; a chain opened (cards, lines, joins, stubs, the way to a locked quest); an overview; details; filters; search; tabs for views other files register |
| `Modules/Questtree/Browser.lua` | the big window: zones, chains as cards and lines, an overview, the zone map, details, filters, search |
| `Modules/Questtree/Views.lua` | the big window's other views: storylines (every chain), the level path (where to go next) |
| `Modules/Questtree/Learn.lua` | learning givers, enders and prerequisites while playing |
| `Modules/Questtree/Dialog.lua` | in the game's quest UI: the panel beside the quest dialog, chain steps on the quest log's lines, Alt-click there |
| `Modules/Beacon/QuestShare.lua` | friends' progress and learned records over Beacon (`B2;q…`, from 0.7.0-70) |

Every Questtree file starts with `local Q = ns.Questtree or {}; ns.Questtree = Q`, so the order they
load in doesn't matter for the table.

## Data

### Where it comes from

`LefthyTools_QuestData/QuestData.lua` is made by `node tools/update-quest-data.js [build] [--cache
<dir>] [--dump <file>] [--eglink <commit>] [--stats]` (the same output for the same inputs):

- **Classic quests: CMaNGOS Classic DB** (Full_DB z2815, GPL v3, the dump the Bestiary's drop data
  comes from): `quest_template`, `creature_`/`gameobject_questrelation` (givers),
  `..._involvedrelation` (enders), `item_template.startquest`, the spawns (`creature`,
  `creature_spawn_entry`, `gameobject`), the templates' names, factions and loot IDs, and
  `creature_`/`gameobject_`/`reference_loot_template` (where items that start quests drop).
- **Forever's new quests: EG Link** (`github.com/JIVESCORP/eg-link-output-wowf`, CC BY 4.0: "Data
  from Efficient Games (https://efficient.games), licensed under CC BY 4.0"): `quests.enUS`
  (title, levels, race mask, zone, `nextQuestId`, `startItemId`), `npcs` (who offers and takes each
  quest, their uiMap positions, their side), `quest_prerequisites` (what every character seen
  taking a quest had done before: `before`, `characters`), `loot` (what players looted from which
  NPC or object, and where) and `creatures` (names). The commit used is in `source`.
- **Forever's client tables** (wago.tools): UiMap, UiMapAssignment, AreaTable, Map, QuestSort,
  FactionTemplate, QuestV2, QuestLineXQuest, ItemSparse (StartQuestID, item names), QuestPOIBlob,
  ChrRaces (the playable races, their race-mask bits and sides).
- `Data/ForeverQuests.lua`: which quests are new in Forever (the `new` flag).

Not used: Wowhead and anything taken from Questie (the project's rule), and ForeverCore's sniffs
(advocaite/Karrz1 TrinityCore `forever`: GPL-2.0 without "or later", which can't go into a GPL v3
file, and it credits Questie for quest data).

### The rules

- **Previous quests** (as MaNGOS' core checks them): a quest's `PrevQuestId` and every quest whose
  `NextQuestId` names it. Positive: completed first; any one of them is enough (`preAny`), except
  one in an `ExclusiveGroup` below 0, whose whole group is needed (`pre`); one alone is `pre`.
  Negative: in the quest log (`preActive`).
- `ExclusiveGroup` above 0: the group's quests close each other (`excl`).
- `NextQuestInChain` (the ender offers the next) and `BreadcrumbForQuestId` lead on without being
  needed: only in `opens`. `opens` is the reverse of everything a quest needs, plus those.
- **Forever's quests:** EG Link's `nextQuestId` leads on (`opens`) and is needed by the next one
  unless that one's `before` record (two characters or more) lacks it, or classic-db already says
  what it needs (classic's data checks 87% of `NextQuestInChain` links that way). Forever's quest
  lines (QuestLineXQuest, by `OrderIndex`) give the same where nothing else does. Last, a quest
  with nothing else whose `before` (three characters or more) has exactly one new quest of the same
  zone that isn't before another of them: that one.
- **Zones:** `ZoneOrSort` above 0 is an area: a dungeon, raid or battleground (the instance's own
  area, `Map.AreaTableID`, or an area on an instance map) gives `dungeon`; otherwise the area's
  uiMap (UiMapAssignment by area, else its parent areas'). Below 0 it's a QuestSort (class,
  profession, Seasonal, Camping, ...): `sort`, and the zone is the first giver's. Forever's quests:
  EG Link's area or category, QuestPOIBlob's map, the giver's zone.
- **Places:** each spawn's world x/y on the smallest zone (or dungeon floor, by height) rectangle of
  UiMapAssignment holding it: `mapX = (maxY - y) / (maxY - minY)`, `mapY = (maxX - x) / (maxX -
  minX)`, then into the assignment's `UiMin`..`UiMax` (Marshal Dughan comes out at 42.1, 65.9, as in
  game). Rectangles of neighbouring zones overlap at the borders: the zone of the NPC's own quests
  wins there and the others are stored as alternatives (a zone at most 4 times the other's size; a
  city and the zone around it never: a city's spawn stays in the city). Data.lua asks the client
  (`C_Map.GetMapInfoAtPosition` on the continent) which one it is when it reads the NPC, and keeps
  the guess if the answer is none of them. Up to 5 places per NPC, 1% apart. No spawn: EG Link's
  positions; none at all: no points (event NPCs).
- **Races:** Forever's playable races are ChrRaces' rows with a `PlayableRaceBit` and the playable
  flags classic's eight have (`0x600000`): Human 1 ... Troll 8 (bits 0-7, as in classic), High Order
  Skyborne 95 (bit 32, Alliance) and Windshaper Skyborne 96 (bit 33, Horde). A race mask has bit
  `PlayableRaceBit` per race (numbers up to 2^33: no bit operators, `HasBit` divides). **The race
  rule:** a mask with every classic race of a side gets every race of that side (classic-db knows
  only the eight: an Alliance quest, 77, becomes 77 + 2^32); a mask with every playable race is
  none (all). EG Link's 64-bit masks (hex) keep the playable races' bits, then the same rule
  (Forever's own quests for Skyborne only, or Tauren and Windshaper, stay as recorded).
- **Faction:** races only of one side; else, without races, when every NPC giver is on one side
  (FactionTemplate's groups, EG Link's `side`). Classes are classic's bit mask (class ID c is bit
  c - 1: Warrior 1, ..., Druid 11).
- **Item drops:** for each item that starts a quest, every creature (`LootId`) and chest or fishing
  hole (gameobject type 3 or 25, `data1`) whose loot has it, through references, with its chance
  (the Bestiary's drop-data rules: groups, references rolled `maxcount` times; world loot isn't
  left out here). Items classic-db has no source of: EG Link's `loot` (`npc:<id>`/`object:<id>`
  sources, chance = drops / loot windows). The 3 likeliest sources with places (then without), each
  with its spawns (else EG Link's loot spots, else its NPC's places) put on zone maps as for givers
  and clustered: a spawn within 7% of the map's width of a cluster's centre (heights counted 1.5
  times, a zone map being 3:2) joins it; the 3 clusters with the most spawns, each a centre and a
  radius (its farthest spawn plus 1%, 1.5% to 15%).
- **Who gives what:** each NPC's and object's quests it starts and ends (`npcQuests`,
  `objectQuests`), and per zone the quests given there (a giver's first place) that are listed
  elsewhere: a dungeon's quests at its town, another zone's.
- **Left out:** classic quests the Forever client doesn't have (not in QuestV2, unless repeatable;
  137, mostly Naxxramas' tier quests), unused ones by title, quests nobody gives or takes; Forever's
  test quests; later classic content (IDs 10000+) no one was seen offered.

Numbers (Forever 1.60.1.70862, EG Link 9fcae73): 5257 quests (4031 classic, 1226 Forever's), 3473
of them in 784 chains, 4312 with a giver on the map or an item; of the 1817 new quests 1213 are in
it, 415 with chain info, 492 with a giver, 808 with a zone; 50 zones, 35 dungeons, 1667 NPCs, 239
objects, 599 items (104 with drop sources, 7 of them from EG Link; 143 sources, 108 with places);
3372 quests with a race mask, 3010 of them with a Skyborne bit; 0.63 MB.

### Format

```
LefthyToolsQuestData = {
  source, build,
  races = { [raceID] = "bit|A or H|name[|c]" },     -- Forever's playable races, c: classic's
  names = { "Ahn'Qiraj Temple", ... },              -- zoneName, sort and dungeon are indexes into it
  zones = { [uiMap] = "continent|minLevel|maxLevel|name|quest IDs|given here, listed elsewhere" },
  dungeons = { [names index] = "minLevel|maxLevel|quest IDs" },
  npcs = { [id] = "name|map,x,y;map,x,y/map,x,y" }, objects = (the same),
  items = { [id] = "name|n<NPC>:chance,o<object>:chance" },  -- where it drops, 1/100 %
  dropNpcs = { [id] = "name|map,x,y,r;..." }, dropObjects = (the same), -- drop sources' clusters
  npcQuests = { [id] = "quests it starts|quests it ends" }, objectQuests = (the same),
  quests = { [id] = "title|level|minLevel|races|classes|zone|zoneName|sort|dungeon|pre|preAny|
                     preActive|excl|opens|breadcrumbFor|flags|skill|rep|starts|ends" },
}
```

x, y in thousandths, r (a cluster's radius) in thousandths of the map's width; `/` separates a
place's alternatives; races a number (bit b = 2^b); quest IDs with `,`; flags: `A`/`H`
faction, `r` repeatable, `n` new in Forever, `f` from Forever's data; skill `line:value`, rep
`faction:min`; starts and ends `n<NPC>`, `o<object>`, `i<item>`. A zone's quests are in level order;
a zone's levels are its own quests' (not class or profession quests) without the lowest and highest
tenth (a city's level-60 quests). Strings, so loading is quick and only the quests asked for are
read.

### Loading and the accessors (`Q.*`)

- `Q.Load()`: loads `LefthyTools_QuestData` with `C_AddOns.LoadAddOn` the first time a window asks
  (never at login); true when the data is there. Asked once; if someone loads the add-on later it's
  taken. `Q.HasData()`: loaded, or installed and loadable (`C_AddOns.GetAddOnInfo`), without loading.
  `Q.DataProblem()`: why not (`MISSING`, `DISABLED`, ...). `Q.DataInfo()`: `{ source, build, quests }`.
- `Q.Quest(id)`: the quest table, read from its string the first time and kept (shared: callers
  never write into it):
  `{ id, title, level, minLevel, races, classes, faction, zone, zoneName, sort, dungeon, skill = { id,
  value }, rep = { faction, min }, pre, preAny, preActive, excl, opens, breadcrumbFor, repeatable,
  starts, ends, source = "classic"|"forever"|"learned", new }`. The lists are always tables (maybe
  empty). `starts`/`ends`: `{ kind = "npc"|"object"|"item", id, name, points = { { map, x, y } } }`,
  one table per NPC shared by all its quests. An item's (`kind = "item"`, no points) has `drops`:
  `{ { kind = "npc"|"object", id, name, chance (0..100), points = { { map, x, y, r } } } }`, the
  likeliest first (at most 3; empty when nothing's known), `points` the source's spawn clusters
  (centre, `r` the radius as a share of the map's width; the most spawns first), shared by every item
  of that source. `zoneName`: the area's name, else the zone's, the dungeon's or the sort's. The
  title is English: the UI prefers `C_QuestLog.GetTitleForQuestID`. `races`: the mask with the race
  rule applied (Data, The rules); `Q.RaceAllowed` (Engine) reads it.
- `Q.Zones()`: `{ map, name, continent, minLevel, maxLevel, count }` by continent, then level.
  `Q.Dungeons()`: `{ name, minLevel, maxLevel, count }` by level. `Q.ZoneQuests(map)`,
  `Q.DungeonQuests(name)`: quest IDs, the lowest level first. `Q.ZoneGiven(map)`: quests given in
  the zone that are listed elsewhere (the Deadmines' at Sentinel Hill), the lowest level first.
- `Q.Races()`: Forever's playable races, `{ { id, bit, faction, name, classic } }` by ID (the data's;
  without it the ten known when this was written); `Q.RaceInfo(id)`: one of them or nil.
- `Q.GiverQuests(id[, kind])`: the quests an NPC (`"npc"`, the default) or object (`"object"`) starts
  and ends, two lists of quest IDs (shared), learned ones added; for tooltips: no quest is read. Needs
  the data loaded (`Q.IsLoaded()`): it doesn't load it.
- `Q.Search(text)`: quest IDs whose title (English, or the client's when it knows the quest) or
  giver's or ender's name contains the text, any case; title matches first, then by level. The
  index is made by the first search after a change (all quests' titles and people, one
  `GetTitleForQuestID` each).
- `Q.AddLearned(id, fields)`: learned data fills gaps and never replaces the data: values only
  where the quest has none; lists of quests (`pre`, `preAny`, `excl`, `opens`) only for quests not
  from classic-db (its lists, empty ones too, are what the core checks), and what a quest needs then
  leads to it (`opens` of the other); givers and enders: places for a known one without any, new
  ones only where classic-db has none or the quest isn't classic's. An unknown ID becomes a quest
  with `source = "learned"`, listed in its zone. Before the data is loaded the calls wait and are
  applied when it loads. `Q.OnDataChanged(fn)`: called once on the next frame after changes.
- `Q.dataGen` goes up with every change (the engine's caches read it).
- **Test hook** `Q.SetTestData(quests, zones)`: replaces the data with quest tables (a list, or by
  ID; `source` defaults to `"classic"`) and zones (`{ { map, name, continent [, minLevel, maxLevel]
  } }`; levels and counts from the quests when not given; dungeons from the quests' `dungeon`). What
  a quest needs leads to it (`opens`) without saying so; `Q.GiverQuests` answers from the quests'
  `starts` and `ends`; an item's `drops` as given; `Q.Races()` the known ten; `Q.ZoneGiven` empty.
  Learned data and caches go; the callbacks run at once.

## Engine

- **My progress:** completed quests from `C_QuestLog.GetAllCompletedQuestIDs`, read once and kept
  until the next loading screen (`PLAYER_ENTERING_WORLD`, `PLAYER_LOGIN`); a quest turned in
  (`QUEST_TURNED_IN`) is added at once and kept until then, as the server's list may not have it
  yet. The quest log (`C_QuestLog.GetInfo`) is read again after `QUEST_ACCEPTED`/`REMOVED`/
  `LOG_UPDATE`. The events are registered with the first question (nothing runs before a window
  opens), and the handlers only note what changed. `Q.progressGen` goes up with a change of
  progress, level, skill or reputation.
- `Q.Status(id, who)` → `"done"` (completed), `"active"` (in the log), `"other"` (not for this
  character: race, class, faction, profession skill, reputation; or closed by another: an exclusive
  one done or taken, or the quest a breadcrumb leads to done or taken), `"locked"` (something it
  needs isn't done: all of `pre`, one of `preAny`, `preActive` in the log), `"level"` (below its
  `minLevel`), `"available"`; nil for a quest the data doesn't know. Mine are kept per data and
  progress change. What isn't known (no race, a reputation the client doesn't answer) counts as
  met. A friend's progress table (`who`): `{ done = { [id] = true }, active = { [id] = true }, level,
  faction, race (raceID, or the race's name: English or the client's, as Battle.net gives it) or
  raceFile, class (classID) or classFile }`; skill and reputation aren't checked for friends.
- `Q.RaceAllowed(quest, race)` (a quest table or ID; a race ID, nil: mine, `select(3,
  UnitRace("player"))`; the file `"Skyborne"` is 95 or 96 by my side): the mask's bit for that race;
  a race new in Forever (not classic's) also when the mask has every classic race of its side (the
  race rule again, for data made before it and learned quests). No mask, or a race that isn't
  playable or isn't known: true. `Q.Status` uses it.
- `Q.ZoneCount(map)` → `done, total`: a zone's quests (a dungeon by its name) that are for me, every
  level (low ones too), only `"other"` left out; kept per data and progress change.
- `Q.ChainStep(id)` → `step, total, chainTitle, firstID`: which column of its chain the quest is in
  (one more than the longest way to it inside `Q.Chain`, so quests side by side share a step), the
  last column, and the chain's first quest's (English) title and ID; a quest on its own `1, 1`; nil
  for one the data doesn't know. Kept per data change.
- `Q.Available(map[, x, y])`: quest IDs I can take now (`"available"`) in a zone: `Q.ZoneQuests`
  and `Q.ZoneGiven` (a cave or a city's floor without quests counts as its zone, the position put on
  it with `C_Map.GetMapRectOnMap`); not quests only an item starts. Grey ones (`Q.IsTrivial`) last;
  with my position on that map (0..1) the nearest giver on it first (widths counted 1.5 times), then
  those without a giver there; without a position the nearest my level first. Kept per data,
  progress and map; the order for the last position asked (1% steps).
- `Q.LevelColor(level[, questID])` → `{ r, g, b, hex = "ffrrggbb", key }` (shared, `Q.DIFFICULTY`):
  the game's quest difficulty colours against my level. With a quest ID the client's own answer
  first (`C_PlayerInfo.GetContentDifficultyQuestForPlayer`, `Enum.RelativeContentDifficulty`);
  else by level: 5 or more above me `impossible` (red, ff1a1a), 3-4 `difficult` (orange, ff8040),
  2 below to 2 above `fair` (yellow), above classic's grey level `easy` (green), else `trivial`
  (grey; grey up to level - 5 - level/10 until 39, level - 1 - level/5 until 59, then level - 9; none
  up to level 5). No level: `fair`. `Q.Difficulty(id)`: a quest's key (its level or the client's);
  `Q.IsTrivial(id)`: grey for me (the game's grey "!" rather than the yellow one).
- `Q.Missing(id, who)` → `{ { id, status, reason } }`: what's missing, walked back through the chain
  across zones, the first one to do first. `reason`: `"done"` (must be completed), `"any"` (one of
  several: the best one, in the log, then available, then for me, the lowest level), `"log"` (must
  be in the quest log).
- `Q.Opens(id)`: what it leads to. `Q.Chain(id)`: every quest connected to it (needs, opens,
  exclusive ones, breadcrumbs; at most 400), each after what it needs, the lowest level first where
  there's a choice (a loop in the data: the lowest of the rest next); kept per data change, one list
  for all quests of a chain.
- `Q.Next()`: what the quests I finished or have in my log lead to that are `"available"` or
  `"locked"`: in my zone first (`C_Map.GetBestMapForUnit`, up to its zone), then by level, then the
  ones I can take. Kept until the data, progress, zone or level changes.
- `Q.Friends(id)`: `{ { name, classFile, status } }` by name for the friends in `Q.friends`
  (`{ [key] = progress table with name and classFile }`, kept by Learn.lua), `{}` without any.
  Learn.lua may define its own.

Not checked: `RequiredCondition` (classic's conditions table), `MaxLevel`, maximum reputation,
classic's seasonal events (Seasonal quests are listed but not marked as event-only).

### Open questions (in game)

- That `C_Map.GetMapInfoAtPosition` on a continent answers the zone at a border spot (Durotar or
  The Barrens), and `GetMapRectOnMap` gives the zone's rectangle there.
- That `C_QuestLog.GetAllCompletedQuestIDs` answers on Forever, and QUEST_TURNED_IN's quest ID.
- How long the first search takes (one `GetTitleForQuestID` per quest).
- That `UnitRace("player")` gives 96 (95) for a Windshaper (High Order) Skyborne, and whether the
  High Order Skyborne is playable (ChrRaces gives it the playable flags and the Alliance's bit 32;
  EG Link's Alliance masks have it).
- That `C_PlayerInfo.GetContentDifficultyQuestForPlayer` answers for quests not in my log on
  Forever, and with the same colours as the quest log.

## Module

`Modules/Questtree/Questtree.lua`: the module `questtree`, shown as "Questtree" (never translated),
on by default. Every file of the module starts with `local Q = ns.Questtree or {}; ns.Questtree = Q`,
so the order they load in doesn't matter for the table; `Q.module` is the module.

**Settings** (`LefthyToolsDB.settings.questtree`, the module's defaults table is here):

| Key | Default | What |
|---|---|---|
| `keepPlace` | true | the small window opens where it was left, at its size; off: right of the middle, 340 x 580 |
| `followLog` | true | while the small window is open, a quest opened in the quest log (or clicked in the objective tracker) becomes its "Now" |
| `tooltips` | true | "Questtree: starts ..." lines in NPC tooltips (below); the data loads a few seconds after the loading screen for them |
| `friends` | true | friends' progress in the windows (`Q.Friends`) |
| `learn` | true | learning while playing (Learn.lua reads `M.db.learn`) |
| `autoHide` | true | the companion hides itself when it has nothing to show, and comes back (Small window) |
| `collapsed` | false | the companion is one line (its title bar's button does the same) |
| `stepsOpen` | false | the companion's chain steps unfolded (its "Steps (7)" line; no checkbox) |
| `dialog` | true | the panel beside the quest dialog (In the game's quest UI) |
| `logBadges` | true | "2/4" on the quest log's lines, the chain in their tooltip, Alt-click to open one in Questtree |
| `small` | `{}` | the small window's `left`, `top`, `width`, `height` (always kept; used while `keepPlace` is on; one line doesn't change the height kept) |

The settings page: Open the small window, Open the quest browser (`Q.ToggleBrowser`, or a chat line
when Browser.lua isn't there), the checkboxes under Window (with `autoHide` and `collapsed`), "In the
game's quest UI" (`dialog`, `logBadges`), Tooltips, Friends and Learning.

**Commands:** `/questtree` opens or closes the small window (on "Now"), `/questtree <name or ID>`
shows a quest (a quest link works too), `/questtree browse` the quest browser, `/questtree settings`,
`/questtree help`. `/lefthy questtree ...` is the same. Switched off, each says so (settings and
help still work). Chat lines are English.

**Finding a quest by name** (`Q.Find(text)`): a number or a quest link is that quest; otherwise
`Q.Search(text)`'s quests ranked by: the title (the client's or the data's) is the text, starts
with it, or only contains it (or the giver's name does); then my status (in my log, ready to take,
needs one first, level too low, done, not for me); then nearest my level; then the lower ID. When
several match, chat says how many and which is shown.

**What the files share** (Questtree.lua):

- `Q.When("enable" | "disable" | "settings", fn)` (what a file does when the module is switched on or
  off or a setting changes), `Q.Ready()` (the data is there: loads it on the first call, so only call
  it when a window opens or draws), `Q.Title(id)` (`C_QuestLog.GetTitleForQuestID` when it answers,
  else the data's English title, else "Quest 1234"), `Q.StatusOf(id, who)` (`Q.Status`, "other"
  without the engine), `Q.STATUS` (each status's colour and words), `Q.StatusCode(status)`,
  `Q.StatusText(status, kind)` (coloured: the window's line, `"word"` after a quest's name,
  `"friend"` for a friend's), `Q.LevelText(quest)` ("Level 12 (from 10)"), `Q.MapName(map)`.
- **Difficulty colours**: `Q.DIFFICULTY` (the game's QuestDifficultyColors: trivial grey, standard
  green, difficult yellow, very difficult orange, impossible red, and blue for repeatable),
  `Q.DifficultyKey(id, quest, level)` (Data.lua's `Q.LevelColor(level, id)` when it's there; else the
  game's `C_PlayerInfo.GetContentDifficultyQuestForPlayer` for a quest the client knows; else the
  level difference as the game's quest log: 5 or more above impossible, 3 or more very difficult,
  down to 4 below difficult, within `UnitQuestTrivialLevelRange` standard, else trivial),
  `Q.LevelCode(...)` (its `|cff` code), `Q.LevelTitle(id)` ("[12] Title" in it, as the quest log).
- `Q.StepOf(id)` → step, total, chain name: Data.lua's `Q.ChainStep` when it's there, else the quest's
  place in `Q.Chain`.
- `Q.ChainFor(id)` → list, at: the chain as I can do it (`Q.Chain` without the quests that are `"other"`
  for me, the quest itself kept) and the quest's place in it; nil for none of two or more. What the
  windows number ("step 3 of 7", "Part 2 of 4", the quest log's "2/4"). Kept per `Q.dataGen` and
  `Q.progressGen` (the engine is asked first, so a change of progress it notices moves the key).
- **The look** (the research's, checked against Forever's atlas list): `Q.COLOR` (`|cff` codes: done
  `5fba46`, in progress `d99b00`, locked `737373`, grey, light grey, gold, what closes `ff8040`),
  `Q.Icon(kind[, size])` (markup of the game's quest icons, 14 px by default, the atlas when the client
  has it, else the gossip window's file: `available` `QuestNormal`, `repeatable` `QuestDaily`, `trivial`
  `TrivialQuests`, `level` `QuestNormal` dimmed (`150:150:150`), `locked`
  `questlog-questtypeicon-lock`, `turnin` `QuestTurnin`, `progress` `SideInProgressquesticon`, `done`
  `UI-QuestTracker-Tracker-Check`, `here` the chat's arrow; made once per kind and size),
  `Q.QuestIcon(id[, status, size])` (a quest's by my status: in my log ready `turnin`, else `progress`;
  available: repeatable, trivial or not; locked; else `level`), `Q.Closes(id)` (its `excl` quests that
  aren't done or closed: what taking it closes).
- **Where I am**: `Q.PlayerAt(map)` (my spot 0..1, nil off it or in an instance), `Q.HereZone()` (my
  zone map, walked up from a city floor or cave, and my spot on it), `Q.Toward(map, fx, fy, x, y)`
  (yards from `C_Map.GetWorldPosFromMapPos`, and the compass direction), `Q.TowardText(...)`
  ("170 yd SW", "right here"), `Q.NearestPoint(people, map, x, y)`, `Q.AvailableIn(map, x, y)`
  (Data.lua's `Q.Available` when it's there, else the zone's quests whose status is `available`,
  the nearest giver first).
- `Q.Waypoint(map, x, y, share)`: the game's own map pin (`C_Map.SetUserWaypoint` with a `UiMapPoint`,
  `C_SuperTrack.SetSuperTrackedUserWaypoint(true)`: the arrow on screen and the minimap; the world map
  shows it when opened), `share`: its link (`C_Map.GetUserWaypointHyperlink`) into the chat box. The
  world map is never opened or touched (`OpenWorldMap` from addon code is `ShowUIPanel`: the gamepad
  taint in forever-platform.md).
- `Q.GiverLists(npcID)` → the quests an NPC starts and ends (Data.lua's `Q.GiverQuests`, its shapes
  normalized to two lists of IDs).

**NPC tooltips** (setting `tooltips`): a `TooltipDataProcessor` post-call on `Unit` tooltips, as
Chronicle's "Craftable by" and Questie's: `GameTooltip` only (not forbidden), the primary data block
only (an appended one isn't the unit pointed at), nothing in an instance (the data is secret there),
nothing for a secret GUID; the NPC from `data.guid` (`LT.CreatureOf`). Lines: "Questtree: ends
<title>" for a quest in my log it takes back, "Questtree: starts <title> (step 2 of 5)" for one I can
take, "Questtree: starts <title> at level 12" in grey for one my level is too low for, at most 4,
then "and N more". An NPC's lines are made the first time and kept until `Q.dataGen`,
`Q.progressGen` or the quest log's size changes: a hover is a table lookup. A hover never loads the
data: with the setting on, it loads once, 5 s after the first loading screen (or after the module
or the setting is switched on), out of a fight (in one: a few seconds after it), only when the data
add-on is installed (`Q.HasData`), and Data.lua's NPC index a second later (`Q.GiverQuests(0)`).
Before that (or without Data.lua's `Q.GiverQuests`) the tooltips get nothing. Objects: the game's
object tooltips carry no ID (Questie's findings on Forever), so they get nothing.

**The quest log** (setting `followLog`): a post-hook (`hooksecurefunc`) on the global
`QuestMapFrame_ShowQuestDetails(questID)`, as Misc Tweaks' quest markers hook `QuestLogQuests_Update`.
It runs when a quest's details open in the quest log, and when a quest is clicked in the objective
tracker (its click opens them). The hook only hands the ID to `Q.SmallFollow` (it becomes "Now",
redrawn a moment later in our own code); nothing of the quest log's frames is touched or read.
With Alt held the same hook hands the ID to Dialog.lua's `Q.LogAltClick` (setting `logBadges`), which
opens the quest in Questtree on the next frame (In the game's quest UI). Blizzard's own click is
untouched: Alt is a modifier its title buttons don't use (Shift tracks or links, a right click opens its
menu), so the details open as with any left click. Not done, and why: a "Show in Questtree" button in
the quest details (the quest log is part of `WorldMapFrame`: a button of ours in it becomes part of that
panel for SmartNavigation, whose focus and confirm then run our scripts from Blizzard's code, the taint
chain in forever-platform.md; a button over it parented to UIParent wouldn't be reachable with a
controller), and a tracker-only Alt-click (an Alt-click on a tracker line opens the details too, so
the hook sees it the same way; nothing of the tracker is hooked).

Never lags: nothing is loaded, registered or run at login, except the tooltips' one load a few
seconds after it (setting `tooltips`); the windows load the data when they open.

## Small window

`Modules/Questtree/Small.lua`: `Q.ToggleSmall()`, `Q.ShowQuest(id)`, `Q.RedrawSmall(now)` (a
redraw 0.3 s later, several at once: one; `now`: at once; for other parts whose data changed, e.g.
friends' progress arriving), `Q.IsSmallShown()`, `Q.SmallFollow(id)` (the quest log's hook),
`Q.SmallFrame()` (tests).

The companion: it follows what you're doing without being asked. Two modes: **Now** (what
`/questtree` opens) and **a quest looked at** (a click on any quest, `/questtree <name>`,
`Q.ShowQuest`, the big window's clicks).

**Now**, top down: only what to do now and how far along (the guides' "this now, then those");
what's secondary is in the lines' tooltips or behind a click.

- **Now** (a gold heading with why that quest, a rule under it): the quest I'm on is the last one I
  did something with while the window was open (accepted: `QUEST_ACCEPTED`; super-tracked:
  `SUPER_TRACKING_CHANGED`; opened in the quest log: the hook, also while closed) while it's in my
  log; a quest super-tracked since I last looked counts as new; else the super-tracked quest, else
  the first on the tracker (`C_QuestLog.GetQuestIDForQuestWatchIndex`), else one of my log in this
  zone (its zone or its turn-in here), else the first of my log; none: "No quest in your log. Pick
  one up below." Then: "[18] Title" in its difficulty colour (large; a click shows everything about
  it; its tooltip says what it leads to: "Leads to: [19] Title - giver, zone", `Q.Opens`, "+N more"),
  "Step 3 of 7 · <first quest>" and a green bar (the chain is `Q.Chain` without the quests not for
  me), friends on one line only when there are any ("Friends: 2 of 5 done" with a dot in the class
  colour of each who did it; its tooltip names each with their status; setting `friends`), its
  objectives (`C_QuestLog.GetQuestObjectives`, at most 6, done ones ticked) or, when it's complete
  (`C_QuestLog.IsComplete`), "Ready to turn in" instead, **Turn-in:** on one line (name, zone, how far
  and which way when it's in my zone; a click sets the map pin), and **"Steps (7)"**: a line (a plus or
  minus icon) that unfolds and folds the chain's steps, folded at first, kept in the setting
  `stepsOpen`; unfolded, the steps around this one (from two before, at most 8, "... N before/more"):
  done ones ticked in green, this one bold with an arrow, the rest numbered in grey; a click shows
  that step.
- **The small map**: the turn-in's zone (my zone when the turn-in is in it, else the first turn-in's),
  else my zone: the turn-in ("?" yellow when ready, the in-progress icon when not), the turn-ins of
  my other quests and the givers of what I can pick up on that map, and my arrow.
- **Pick up next** (a heading with my zone and its count, `Q.ZoneCount`: "Elwynn Forest · 12 of 40
  done"), in two groups like Quest Herald's (each quest a row: icon, "[level] Title" in its difficulty
  colour, a grey second line, how far and which way at the right):
  - *In progress*: my other quests, ready ones first, then those turned in in this zone (at most 3):
    "ready to turn in · <ender>" or "in your log · <ender>".
  - *Available now*, only quests for my levels (`Q.InRange`: not grey, at most 2 levels above me):
    follow-ups of the quest I just turned in (while the window was open) first, then `Q.Next()`'s
    that I can take ("after <the quest it follows>"), then the zone's (`Q.AvailableIn`: the nearest
    giver first), at most 3 with "N more here: the quest browser"; the second line: the giver (and
    their zone when it's another) and its step in its chain. What Now leads to isn't listed again.
  None at all: "Nothing to pick up nearby. The quest browser has every zone." What's coming up later
  (level too low) or blocked (needs another first) isn't here: the big window has it.

  **How a line looks** (the guides' step lists: this now, then those): a verb icon first (`Q.Icon`,
  the game's own: `QuestTurnin` "?" for one ready to turn in, `SideInProgressquesticon` for one in
  progress, `QuestNormal` "!" to pick up, `QuestDaily` repeatable). The first line of Pick up next is
  full size (`GameFontHighlight`, a 16 px icon, the title in its difficulty colour): what to do now;
  the rest are smaller (13 px) with only "[level]" in its colour and the title grey (`bebebe`). The
  second line of Available now also says what taking it closes ("closes <title>" in orange,
  `Q.Closes`: its exclusive quests, at most 2 named; the tooltip: "Taking it closes: ... Only one of
  them can be done."); what a quest opens isn't on the line. Section rules are the game's
  `Options_HorizontalDivider` tinted gold (a gold line without the atlas). Done steps are ticked with
  `UI-QuestTracker-Tracker-Check` in the research's green.

  **Status words say the real reason** (a quest looked at, its lists, the tooltips): a quest "other"
  for me that another closed (`Q.WhyOther` "closed") is "Skipped", with "You took <title> instead"
  (for a lead-in: "No longer needed: you have <title>"); not for my race, class or side "Not for your
  race" / "class" / "faction"; a profession I don't have "Needs <profession>"; a locked one blocked by
  a reputation or a profession's rank (`Q.Needs`) "Needs Friendly with Stormwind" / "Needs Alchemy
  100" (the game's names: `FACTION_STANDING_LABEL<n>`, `C_Reputation`, `C_TradeSkillUI`; else
  English ones, as the big window's), by a quest "Needs <the first of `Q.Missing`>". After a quest's
  name the same with a small first letter ("needs Start"). The other statuses keep their words.

**One line** (setting `collapsed`, or the button left of the close button in the title bar,
`QuestLog-icon-shrink` / `QuestLog-icon-Expand`): the window shrinks to its title bar and a line
(54 px high, its height fixed then; the scroll area, its inset, the grip and the bottom button hidden):
the quest I'm on with its verb icon, "[18] Title · 3/7" (`Q.ChainFor`) and how far its turn-in is,
else the first thing to pick up with how far its giver is, else "Nothing to pick up nearby."; a quest
looked at: that quest. A click on the line (or the button again) shows the whole companion at the
height kept in `small`. It follows the same events as the whole window.

**Hiding itself** (setting `autoHide`): when a redraw after an event finds nothing to show (no quest
I'm on, nothing in Pick up next), the companion hides; while hidden like that it listens only to
`QUEST_ACCEPTED`, `SUPER_TRACKING_CHANGED`, `PLAYER_LEVEL_UP` and `ZONE_CHANGED_NEW_AREA` (rare), and
0.3 s after one of them it opens again where it was if there's something now. Opened by me
(`/questtree`, a quest shown) it never hides itself in that draw: "Nothing to pick up nearby" stays.
Closed by me (Escape, its X, `/questtree`) it stays closed and listens to nothing. Switching the
setting off while it's hidden brings it back.

**A quest looked at**: at the top "« Back to now" or, after clicking from one quest to another,
"« Back to <the quest before>" (up to 20 back) and "Back to now" side by side. Then its "[level]
Title", its step in its chain and bar, a grey line (level, zone, dungeon, repeatable, new in WoW:
Forever), my status with its real reason ("Your level is too low: from level 30", "Ready to turn in",
"Skipped" and under it "You took <title> instead", "Needs Friendly with Stormwind"), **Requires:** (what it needs
first from other chains, by their names), **Needs first:** (`Q.Missing`, numbered, the one to do
first at the top; at most 8, "and N more"), **Quest giver:** and **Turn-in:** (name, zone, how far;
an item or object says so, "+2 more"; not known: says so), for an item that starts it **Drops
from:** "Defias Pillager (12%), ..." (the item's `drops`), the **small map** (the giver's zone, the
turn-in's for a quest in my log, where the item drops for a quest that only an item starts, unless a
line picked one; every giver, turn-in and drop spot on it, a person in several places: the spot on
my map, else the first), **Leads to:** (`Q.Opens`), **"Steps (7)"** (folded or not as in Now) and
**Friends:**. Each quest line is a button showing that quest (its tooltip: the title, the status and
its reason, "Click: show this quest"); a giver's or turn-in's line puts its side on the map and sets the game's map pin at
its spot nearest me (`Q.Waypoint`; Shift-click: its link in chat too).

The data add-on missing: the window says so (run the updater, restart), nothing else. A quest the
data doesn't know: its title and that line. At the bottom: **Quest browser** (`Q.OpenBrowser` on the
quest looked at or Now's, else `Q.ToggleBrowser()`; hidden without Browser.lua).

**What it costs.** The window: `LT.Window.Create` (`LefthyToolsQuesttreeSmall`: Escape closes it, it
counts as an open window for Mirage, the AFK screen and flights), DIALOG strata, raised when a quest
is shown. Movable, resizable by its corner grip (300-600 x 300-950); where it is and its size are
saved on every drag and resize (`small`). The content is in a scroll area; its width and the map's
follow the window's. Built the first time it opens; rows, texts and header rules are pooled. While
shown it listens to `QUEST_ACCEPTED`, `QUEST_TURNED_IN`, `QUEST_REMOVED`, `QUEST_LOG_UPDATE`,
`QUEST_WATCH_LIST_CHANGED`, `SUPER_TRACKING_CHANGED`, `PLAYER_LEVEL_UP`, `ZONE_CHANGED`,
`ZONE_CHANGED_INDOORS`, `ZONE_CHANGED_NEW_AREA` (and `Q.OnDataChanged`); the handlers note what
happened and redraw 0.3 s later. A child frame looks every 2 s whether I moved (2% of the map, or
another zone) and redraws then (the distances). Hidden: no events, no OnUpdate. Nothing protected:
it opens and works in a fight.

**Controller:** every line that does something, the map's markers, the bottom button and the grip
are buttons of ours, so SmartNavigation's cursor reaches them (its focus runs OnEnter: the tooltips
show; its button clicks: a quest shows, a marker sets the pin). Nothing of Blizzard's is set on our
frames, no Blizzard menu, no panel opening.

**Small map** (`Modules/Questtree/MiniMap.lua`, also for the big window):
`local m = Q.NewMiniMap(parent[, width, height])` (240 x 160 by default), `m.frame`,
`m:Show(map, points[, name])` with `points = { { x, y, kind, label [, note, look, grey, chance,
radius] } }` (0..1 on that map), `m:SetSize(w, h)`, `m:Hide()`, `m:ShowPlayer(on)`,
`m:Zoom(factor[, x, y])`, `m:Markers()` (tests).

- The zone's art and what you've explored of it (`LT.MapArt`: the art tiles of
  `C_Map.GetMapArtLayerTextures` and the explored overlays of `C_MapExplorationInfo`, as Attune's
  detail map and the fight stream's), as large as fits, on a dark box that clips it; the zone's name
  on a strip over its top, "wheel: zoom" / "right-click: whole zone" at its right.
- Markers: the game's own map icons, solid (full alpha), 22 px on a dark copy of themselves (an
  outline that reads on any ground): `kind` "start" a giver, "end" a turn-in, "drop" where an item
  drops. `look`: "available" (`QuestNormal`, yellow !), "repeatable" (`QuestDaily`), "trivial" (the !
  paler), "locked" (the ! grey), "turnin" (`QuestTurnin`), "repeatturnin" (`QuestRepeatableTurnin`),
  "progress" (`SideInProgressquesticon`); without `look` a start is "available", an end "turnin",
  `grey` makes them "locked" / "progress". The atlas missing: the gossip window's icon. A drop: a
  soft orange spot (`Spells\GenericGlow64` added) at least 34 px, as big as its `radius` (0..1 of the
  map's width, at most 140 px); the likeliest (`chance`) says "drops here (12%)" beside it.
- Points within 8 px share one marker (drops only with drops), its tooltip naming each with what it
  is and its `note` (the quest); at most 40; points off the map are left out. A click sets the game's
  map pin at the marker (`Q.Waypoint`), Shift-click puts it in chat too.
- The mouse wheel zooms by 1.35 a step around the cursor (1 to 8 times), dragging moves the zoomed
  map (an OnUpdate only while the button is held), a right-click shows the whole zone again; another
  map starts whole.
- My arrow (`Interface\Minimap\MinimapArrow`, turned by `GetPlayerFacing`) where I am when I'm on that
  map (`Q.PlayerAt`), moved ten times a second by an OnUpdate on a frame of the map (hidden: it
  doesn't run); `m:ShowPlayer(false)` leaves it out.
- No art: "No map of this zone" with the markers on the dark box. Laid only when the map, the size
  or the zoom changes (or you've explored more); never touches `WorldMapFrame`.

**Tests** (`tests/questtree_small.lua`): the module, settings and commands; difficulty colours;
the lines' verb icons, the first full size and the rest grey, no "opens", exclusive quests closing each
other, Available now only for my levels and at most three, nothing for later, one line (the button,
the line's click, the setting), hiding itself and coming back and staying closed when I closed it,
Alt-click in the quest log (through the hook); the status words (skipped and by which, not for my
class or side, a profession missing or too low, a reputation, the quest first; as a word after a
name);
Now (why that quest, its step and bar, objectives, turn-in, what it leads to in the title's
tooltip, the steps folded and unfolded and kept, the map and its markers) and Pick up next (the two
groups, nearest first with distance and direction, the zone's count);
following super tracking, the quest log's hook and its setting, accepting and turning in (the
follow-up first); a quest looked at ("« Back to", "Back to now", an item's drops and their map, too
low, done); the map pin from a giver's line and a marker (Shift: chat); friends' dots and their
setting; an unknown quest, the data missing, the search, the browser command; the NPC tooltip lines
(giver, turn-in, too low, done, kept, other frames, instance, setting, data not loaded); events only
while shown, moving; place and size kept and the setting off; a fight; buttons for the controller;
without the data part's new calls; switched off; the small map alone (icons, one marker for one
spot, the arrow, zoom). Data.lua's `Q.ChainStep`, `Q.Available`, `Q.LevelColor`, `Q.ZoneCount` and
`Q.GiverQuests` get stand-ins only while they're missing; the mock's map pin API and the quest log's
`QuestMapFrame_ShowQuestDetails` are made for it and put back at its end.

## In the game's quest UI (Dialog.lua)

Questtree where players already look: the quest dialog and the quest log. Built from established
add-ons' ways (BtWQuests and QuestWeaver open from the quest log, Wowhead's numbered "Series" box with
the current quest bold), with our own frames and post-hooks only.

### Beside the quest dialog (setting `dialog`)

When an NPC offers a quest (`QUEST_DETAIL`), asks for it (`QUEST_PROGRESS`), rewards it
(`QUEST_COMPLETE`) or lists several (`QUEST_GREETING`), a panel of ours (`LefthyToolsQuesttreeDialog`,
250 px wide, a dark background with a thin gold edge) sits right of `QuestFrame`, its top at the
dialog's top:

- **"Part 2 of 4 · <chain>"** (gold, `GameFontNormal`): the quest's place in `Q.ChainFor` and the
  chain's first quest's title (the client's when it knows it).
- **The steps**, numbered, in a window of four: one before this one, this one, two after (fewer
  before it at the chain's start, more at its end), "... N before" and "... N more" for the rest;
  done ones ticked green, this one bold (`GameFontHighlight`) with an arrow, the rest grey; each a
  line that opens that quest in Questtree.
- **Leads to: [7] Title** when it opens one quest that isn't one of the steps listed (the next step
  usually is); when it opens several, **Opens 3 quests** alone (their names in the line's tooltip; a
  click opens this quest in Questtree, where they're listed).
- **Requires: <title> (for <the next step>)**: what the quests it leads to need besides this one
  (`Q.Missing` of each, at most 3) that isn't done and isn't one of the steps listed, in the locked
  colour; its tooltip says the next step needs it too. (Every quest's prerequisites are part of its
  `Q.Chain`, so "outside the chain" is "not in sight": a need listed as a step isn't said again.)
- Offered only (`QUEST_DETAIL`): **"Taking it closes: ..."** (`Q.Closes`, orange) and for a lead-in
  "A lead-in: <quest> can be taken without it." (`breadcrumbFor`).
- **Friends:** on one line (no wrapping), those who did it (a tick) or are on it (the in-progress
  icon), in class colours, at most 3 named, then "+2" (`Q.Friends`, setting `friends`; their progress
  asked for once per quest while the dialog is open, `Q.RequestFriendProgress`; their answers redraw
  it, `Q.OnFriendProgress`).
- **Open in Questtree** (a button at the bottom): `Q.OpenBrowser(id)`, else `Q.ShowQuest(id)`.

The greeting lists each of the NPC's quests that's in a chain or leads on: "[12] Title" with its verb
icon and "Part 2 of 4 · <chain>" (or "opens N") under it, a click opens it; no button. Nothing to tell
(no chain of two or more, nothing it leads to or closes, no lead-in, no friends): no panel at all.

**Events and cost.** The five events (`QUEST_FINISHED` too) are listened to while Questtree and the
setting are on; each only notes the page and draws on the next frame (`C_Timer.After(0)`: the dialog
shows itself in its own handler first). The data is loaded for it only out of a fight, when the add-on
is there (usually the tooltips loaded it already); in a fight before that: no panel. `QUEST_FINISHED`
hides it; while shown it also looks twice a second whether `QuestFrame` is still visible (a dialog can
close without that event reaching us first). Hidden: nothing runs.

**Taint and the controller.** The panel is a frame of ours on `UIParent`, only anchored to
`QuestFrame` (`TOPLEFT` to its `TOPRIGHT`, its strata and a level above it, clamped to the screen);
it's never a child of it. So it isn't part of the dialog's panel for SmartNavigation (which collects a
panel's descendants when `ShowUIPanel` opens it, and rebuilds them when a frame is made with a parent
inside it): the controller's cursor stays on Blizzard's Accept, Decline and Complete, nothing of ours
runs from Blizzard's code, and the controller can't get caught on our lines. That's the taint-free
choice; the price is that the panel's lines and button are for the mouse only (with a controller the
companion follows the quest once accepted). Nothing is written into `QuestFrame`, none of its scripts is
hooked; no Blizzard template but the button's `UIPanelButtonTemplate`, no Backdrop, no navigation values.

### The quest log (setting `logBadges`)

- **"2/4"** at the right end of each chain quest's line (in the research's in-progress gold), as Misc
  Tweaks' NEW does it (misc-tweaks.md, foreverQuests): a post-hook on `QuestLogQuests_Update` puts a
  font string of ours on each pooled title button (`QuestScrollFrame.titleFramePool`) whose quest is
  in a chain, at `RIGHT` of the track checkbox's `LEFT` - 4 (where Forever never shows the quest type
  icon), or left of Misc Tweaks' own NEW label when that one is there (a long title). The title's text
  is never changed. The hook is made a second after Questtree is switched on, so it runs after Misc
  Tweaks' and knows where its label is. Each "2/4" is kept per data and progress change: a redraw of
  the log is a table lookup per line. Data not loaded yet: loaded once on the next frame, out of a
  fight, then the open log is marked.
- **The tooltip**: one `HookScript("OnEnter")` per title button (as Misc Tweaks'): when the game's
  tooltip is the line's, it adds "Questtree: Part 2 of 4 · <chain>", at most 5 steps from one before
  this one, windowed as the panel's ("... N before", "... N more"; this one white with the arrow, done
  ones ticked green, the rest grey), "Leads to: ..." and "Alt-click: open it in Questtree".
- **Alt-click** a quest there: Questtree.lua's post-hook on `QuestMapFrame_ShowQuestDetails` (Module,
  The quest log) calls `Q.LogAltClick(id)`, which opens it on the next frame (`Q.OpenBrowser`, else
  `Q.ShowQuest`) from a timer of ours, not inside Blizzard's click. A click on the "2/4" itself would
  need a frame of ours (a Button) inside the quest log, which is part of `WorldMapFrame`: SmartNavigation
  would take it into the map's panel and run its scripts from its own code, the gamepad taint in
  forever-platform.md. So the badge is a font string (no mouse), its tooltip is the line's, and the
  click is the line's with Alt. Without a keyboard (gamepad mode) there's no Alt: the tooltip and the
  companion's following of the quest log are the way there.
- The setting off: the open log loses its "2/4" at once, the tooltip lines and Alt-click stop.

`Q.DialogView()` gives the tests the panel, its strings, the quest shown, the page and the labels.

**Tests** (`tests/questtree_dialog.lua`): nothing built before a dialog; the offered page drawn on the
next frame, not in the event (heading, the steps' window with done ticked and this one bold and "... 2
more", what it leads to when it isn't listed, a need that's a step listed not said again, what taking
it closes, the button and a step's line opening Questtree); a frame of ours on UIParent anchored beside
the dialog, nothing written into `QuestFrame` or its scripts; closed by `QUEST_FINISHED` and without it;
a quest with nothing to tell; a lead-in; the progress and reward pages (the chain without the quest
taking it closed; what it leads to listed as the next step); two it opens (the count, the names in its
tooltip) and a need far down the chain (Requires); friends (who did it or is on it, three, "+1"; asked
for once); a greeting; the setting off; the data not loaded in a fight. The quest log: "2/5" on a chain
quest's line (the title unchanged), nothing on one in no chain, left of Misc Tweaks' NEW, kept until
progress changes, the tooltip (a long chain: five steps from one before), Alt-click on the next frame,
the setting off and on again.

## Big window (Browser.lua)

`Q.ToggleBrowser()` opens or closes it; `Q.OpenBrowser(id)` opens it on a quest (its zone or dungeon on
the left, its chain opened with its card in the middle of sight, its details; true when it's open with
the data); `Q.SelectZone(map)` opens it on a zone's page (a uiMapID, a city's floor or a cave counting as
its zone, or a dungeon's name; false when there's no such place); `Q.HideBrowser()` closes it (the module
switched off); `Q.BrowserShown()` says whether it's open. Other files add tabs with
`Q.RegisterBrowserView` and open them with `Q.ShowBrowserView` (below). With the module off it doesn't
open (one chat line says how to switch it on). `Q.BrowserView()` gives the tests its frames, state and
views.

The look follows what players know from the quest add-ons researched for it (BtWQuests' and
ForeverQuestChain's cards, BeautifulAttune's flat cards and lines, EQ's gutters and hover lighting,
pfQuest's colour per quest, Questie's map highlight, Blizzard's map icons and story headers), built from
our own frames.

**Size.** 1400 x 820 (`LT.Window.Create`, `LefthyToolsQuesttreeBrowser`, in `UISpecialFrames` so Escape
closes it, movable), scaled down to fit when the screen (`GetScreenWidth`/`GetScreenHeight`, UI units) is
smaller than that plus 40 x 80. In the band under the title: "Search all zones:" with its box on the
left, the three **filters** on the right (below). Under it, on an 8 px grid:

- **Left (240 px): places.** `Q.Zones()` grouped by continent in the order it gives them (a header per
  continent, its name from `C_Map.GetMapInfo`; a click folds it), then a "Dungeons" header and
  `Q.Dungeons()`. Each row: the name, the level range, "done of total" and a thin bar under it (green
  when all are done). The count is `Q.ZoneCount(map)` (a dungeon: `Q.ZoneCount(name)`): every quest for
  me, any level, only "not for me" left out; without `Q.ZoneCount` it's counted here the same way over
  `Q.ZoneQuests` / `Q.DungeonQuests`. A dash when none is for me. The first time it opens, the zone I'm in
  is chosen (`C_Map.GetBestMapForUnit`, then its parents), else the first zone.
- **Middle (782 px):** the **tab bar** (our own Buttons): **Zone** (the zone page, or a chain opened from
  it), **Overview**, then each registered view, and at its right "Back to the search results" during a
  search. Under it the **head** (except for a registered view): a chain's way back to its zone, the
  chain's colour, the title (`GameFontNormalLarge`), a grey line under it, "x of y done" with a bar, and
  the zoom (-, the zoom, +, Fit: the zone map's or the chain's), a gold divider under it. Under the page a
  legend of the status colours (a chain's page: "- - not needed first" too). The tab is kept.
- **Right (330 px): the details** of the quest picked.

A zone's pages show its quests (`Q.ZoneQuests`) and those given there but listed elsewhere
(`Q.ZoneGiven(map)`: the Deadmines' quests at Sentinel Hill); its count stays its own quests'.

### The zone page

Every quest of the place goes through `Q.Chain(id)` once; a chain of more than one quest is a group,
ordered by the lowest level of its quests in this place; the quests without a chain are a group of their
own. Who leads to whom: each quest's `pre`, `preAny`, `preActive` and `Q.Opens`, only from an earlier
quest in the chain's order to a later one (a loop in the data is cut). Each chain has **a colour of its
own**: its first quest's ID times the golden ratio as a hue (HSV 0.6 / 0.95), the same in every zone and
every session; the quests without a chain are light grey.

The head: the zone's name, "Level 1-10 · 3 to pick up now · 2 chains", "12 of 40 done" and its bar.

**The map (left, 432 x 288, the zone's 3:2).** The zone's art (`LT.MapArt`: the world map's tiles and what
I've explored, as the small map) in a clipping frame of ours. A pin per spot of a quest giver of the
place's quests as the filters show them (`starts[].points` on that map), a quest in my log at its
turn-in's (`ends`), in the game's own map icons on a dark disc: `QuestNormal` "!" (24 px) to pick up,
`QuestDaily` for a repeatable one, `TrivialQuests` for one that's grey for me (`Q.IsTrivial`),
`QuestTurnin` "?" when it's ready to turn in (`C_QuestLog.IsComplete`; `QuestRepeatableTurnin` for a
repeatable one), the same "?" grey while it's in progress, a grey "!" (18 px) for one my level is too low
for and a smaller, darker one for one that needs another first, dim dots for done and not-for-me ones;
where an item that starts a quest drops (`starts[].drops[].points`) a soft gold circle ("Wolf Fang drops
here (12%)", sized by the point's `r`). Spots within 8 px are one pin (drop areas only with drop areas):
its look the most urgent one's, **a count badge** (the quests still to do there, from two), its tooltip
the giver and each quest ("[4] Brotherhood of Thieves") in its status's colour; a click shows its most
urgent quest, the next click the next one; the quest picked has a gold ring. Me as a blue dot when I'm on
that map. The wheel zooms (x 1.35, up to 8), dragging moves it, "-", "+", "Fit" too; a pin the
controller's cursor moves to out of sight brings the map to it.

**Threads.** Each chain's quests shown, in the chain's colour, as thin lines (2 px, 70%; a done step's
25%) from giver to turn-in and from a turn-in (else the giver) to the next quest's giver, the spots on this
map; at most 500 a zone, pooled `Line`s under the pins.

**Under the map:** "1 in progress 3 available 1 coming up 3 blocked 2 done" (the place's quests, in their
status colours), and with none to take here: "Nothing for you to pick up here right now." and a button
"Redridge Mountains has 9 for your level >" (`Q.SelectZone`): the zone whose level range is within 3 of
mine with the most quests I can take now (`Q.Available`, else counted from the statuses), kept until a
status changes. Then a divider and what the pins mean.

**The chains' cards (right, on a darker panel; a pooled list, 64 px cards 8 px apart):** those with
something the filters show, done chains after the rest, the quests without a chain last. A card (a
Button): a 4 px strip in what's to do in it (in my log blue, to take amber, later orange, locked grey,
done green), a dot in the chain's colour, its name (gold; grey when done: `Q.ChainStep`'s chain title,
else the first quest's), "3/7" with a check when done and a bar, what's next ("In your log: ...", else
"Next: ... - <giver>", else "Coming up: ...", else "All done"; the quests without a chain: "2 to pick up
now"), a grey line ("Level 5-12 · opens 4 · 2 steps elsewhere": how many of the chain's quests not done
yet come after the next one, its steps for me in other places), and a dot per friend who's shared
progress on it (`Q.Friends`, at most 5, class colours, dim while they've done none). Its tooltip adds each
friend's "3 of 7". A click opens the chain. Nothing to show: "No quests known here yet." or "Nothing to
show with these filters.".

**Lighting the other side.** Hovering a chain's card (the mouse, or the controller's cursor: its focus runs
OnEnter) lights its pins and thread (the thread 3.5 px, full colour) and dims every other pin (30%) and
thread (8%). Hovering a pin lights the cards of its quests' chains (gold edge and glow) and dims the
others (40%); when none of them is in sight, the list scrolls to the first. Leaving puts it back. The
card of the picked quest's chain has a gold edge. Only alphas and line widths change: nothing is laid
again.

A dungeon has no map: a line says each quest's details show where; its chains' cards as for a zone.

### A chain opened

Its head: "< Elwynn Forest" (back to the zone's page), the chain's colour, its name, "3 of 7 steps done"
and a bar, what's next. The page is a canvas of its own (below) with the chain's quests as **cards** (170
x 48, Buttons) from top to bottom, **a row per stage** (a quest's stage: one more than the latest of what
leads to it), the quests of a stage side by side, each stage centred in the page's width; a stage's order
follows where what leads to them is (the average of their slots above), the first stage the chain's
order (ForeverQuestChain's and BtWQuests' layout). A card: a flat background in Attune's tones (done
green, available amber, in my log blue, the rest dark grey with a grey edge), a 3 px strip in its status's
colour on the left, the start (32 px: the giver's `QuestNormal` "!" (`QuestDaily` when repeatable,
`TrivialQuests` when grey for me), bright only when I can take it, `SideInProgressquesticon` in my log, the
item's icon (`C_Item.GetItemIconByID`), an object's note), a check (`common-icon-checkmark`) when done, the
title (the client's when it knows the quest), "[12] Marshal Dughan" (the level in its difficulty colour,
the giver; in another zone the zone's name), "1/2" friends who've done it (`Q.Friends`), and at the bottom
right "lead-in" (a breadcrumb: also a bit dimmer, its tooltip says it isn't needed for what comes after)
or "closes" (taking it closes another of the chain: `excl`; its tooltip names them). Not for me: dimmed.
The quest picked: a gold edge and glow. **The next step pulses once** (a gold glow in and out) when the
chain is opened from its card, and is brought into sight.

**Lines** (`CreateLine`, 2 px): down from a card, across the gap, down into the next; green when both are
done, amber from a done, available or in-log one, grey otherwise (the lit ones on a higher sublevel). A
line that passes a stage has a narrow slot of its own in it (a dummy, as in layered graph drawing), so
**no line runs through a card**. **Lanes** (EQ's gutters): in each gap the lines into one quest share a
height of their own, apart from the others' whose stretch across would overlap, so lines that aren't
joined never share a stretch; lines that meet at a quest share one (they join there), and so do a fork's
(one quest to several, each from it alone). A line into a quest right under another quest it doesn't come
from comes in 9 px to the side (a passing slot moves within itself), so it never looks like that quest's.
A line to a quest that doesn't need the one before it (a breadcrumb's, or a quest the ender offers next
that isn't in its `pre`/`preAny`/`preActive`) is **dashed** (5 on, 4 off) and dim; a hidden quest passed
through is fainter. Corners overlap by half a line.

**Joins.** Where two or more lines lead into a quest, a small label sits on them just above it: **"one of"**
(amber: two or more of them are its `preAny`) or **"all of"** (grey: two or more are its `pre` or
`preActive`).

**Stubs.** A quest of the chain in another place shows only next to a quest of this place (what leads to
it or what it leads to), as a stub: a dark card with the map icon, that place's name in gold and "[10] The
People's Militia" in grey; the rest of the other places' quests are passed through like hidden ones. A
click on a stub goes there: that place, the chain opened there, the quest picked.

**Why it's locked.** A locked quest picked in its chain lights the way back to it (`Q.Missing`, across
zones): each quest it needs first gets an orange edge and a number (1: do it first), the lines between
them turn orange and thicker, the rest of the cards dim (40%) and the other lines too; a stub lights up
when its quest is on the way or the way has quests in its place; the head says "To take it, do 3 quests
first, 2 of them in other zones". Another quest picked puts it back.

**The canvas.** A clipping frame of ours with the canvas inside (no ScrollFrame): the mouse wheel scrolls
a stage, Shift sideways, Ctrl zooms (50 to 100 %), dragging moves it; "-", "+" and "Fit" (the whole width
as far as the zoom goes) in the head; thin gold bars show where it is. A canvas smaller than sight is
centred. **Pools:** only the cards, lines and labels within 190 units of sight exist; a card stays on its
quest while it's near (a controller's cursor stays on it), the rest go back to the pool. They're laid
again only when the view moved half a card or more (or something changed).

The quests without a chain open the same way: their cards in rows.

**Difficulty colour** (`LevelRgb`): `Q.LevelColor(level, id)` (a table `{ r, g, b }`, three numbers or a
colour code), else the game's `C_PlayerInfo.GetContentDifficultyQuestForPlayer` for a quest the client
knows, else Blizzard's thresholds against my level (5 above: red, 3: orange, down to 4 below: yellow,
within `UnitQuestTrivialLevelRange` (classic's green range without it): green, else grey); repeatable
quests blue.

### Overview

The place's quests in groups (a pooled list, the left's rows): In progress, Available now, Coming up
(level too low), Blocked (needs another first), Completed (folded at first), Not for you (only with that
filter), each with how many. A row: the start's icon, "[12] title" (level coloured, title in its status's
colour), at the right the giver, "needs <the first of `Q.Missing`>" or "from level N". A click shows the
quest in the details; a link there keeps the overview.

### Views other files add

`Q.RegisterBrowserView(key, label, build)` adds a tab after Zone and Overview (in the order registered;
a view registered after the window was built gets its tab at once). `build(parent)` is called the
first time the tab is shown, with a frame of ours under the tab bar, between the zones and the details
(782 x 694: the head and the legend are hidden for it), and returns `{ frame, Refresh = function(self)
end, OnShow = function(self) end, OnHide = function(self) end }` (each optional; a frame without points
fills the parent; `self` is that table). OnShow runs when its tab is shown, OnHide when another tab is or
the window closes; Refresh each time it's shown and while it's shown when quests change (the window's
events, on the next frame) or the data changes. Errors in them go to the error handler (the error window)
and don't break the window; a build that fails leaves "This view couldn't be built." `key` must be a
string other than "zone", "overview" and "results", `build` a function; the same key again replaces its
label and build (a view already built stays). Returns true when registered.

`Q.ShowBrowserView(key)` opens the window (if it isn't) on that tab: "zone" (the zone's page), "overview"
or a registered view's key; false for an unknown one. From a view, `Q.OpenBrowser(questID)` goes to the
quest's chain and `Q.SelectZone(map)` to a zone's page (both on the Zone tab).

### Details

In a scroll area: the title ("[12] Title", in its difficulty colour, the client's title when it
answers), its status (level too low: which level it needs), level (coloured), zone, "Step 3 of 7 - <the
chain>" (`Q.ChainStep`, else its place in `Q.Chain`), tags (new in WoW: Forever, repeatable, learned
while playing); **Starts at** and **Turn in at** (gold headers with a divider): a line per giver and ender
(up to three each, objects and items said so, the zone of the first spot), and for an item each place it
drops from ("Drops from Young Wolf (12%) - Elwynn Forest", an object "In ... (x%)", up to three). Each line
is a Button: its tooltip has the spot, a click puts **a map pin** there (`C_Map.SetUserWaypoint` with
`UiMapPoint.CreateFromCoordinates`, when `C_Map.CanSetUserWaypointOnMap` allows it, then
`C_SuperTrack.SetSuperTrackedUserWaypoint(true)`; a chat line says so; the world map isn't opened or
touched). Then the small map (the same widget as the zone page's, not zoomable): the first giver's map
(else a drop's, else the first ender's) with every giver, ender and drop area on it; **Requirements**:
faction, races (a mask with all of one side's classic races is "every Horde race", as the engine counts it
for the new ones too; else each race whose bit is set, named by `Q.Races()`' `{ id, bit, name }` /
`Q.RaceInfo(id)`, the game's `C_CreatureInfo.GetRaceInfo`, classic's names), classes, skill, reputation,
what it's a breadcrumb to, what taking it closes; **Needs first:** (`Q.Missing`) and **Leads to:**
(`Q.Opens`), a button per quest (at most 12 each, "... and N more"), its zone named when it isn't the
place shown; **Friends** (`Q.Friends`: names in class colour and their status; at most 12); and at the
bottom, outside the scroll area, "Show in the small window" (`Q.ShowQuest`).

### Filters

Three checkboxes of ours (Buttons with the game's checkbox art), kept in the module's settings
(`browser = { hideDone, onlyAvailable, showOther, tab }`, made when first needed; a tab of the version
before, "chains" or "map", becomes "zone"): **Hide done**, **Only available now** (status `available`),
**Show quests not for you** (off: those are left out). They act on the chains' cards, the pins and threads,
a chain's page and the overview. A hidden quest in a chain is passed through: what came before it leads
to what comes after (a fainter line), and the stages close up. A chain with nothing left to show has no
card either. The search and the counts aren't filtered.

### Going to a quest, the search

**Going to a quest** (a link, a search result, a stub, `Q.OpenBrowser(id)`): it stays in the place shown
if that place lists it (its own quests and those given there), else goes to the quest's zone if that
zone lists it, else its dungeon, else its zone. Its continent unfolds, the left list scrolls to the place
when it changed, and its chain opens on the Zone tab with its card in the middle (the Overview stays the
Overview). A click on a quest (a card, a row, a pin, a link) also shows it in the small window when
that's open (`Q.IsSmallShown()`; without it this is skipped). A click on a place on the left shows its
page (the Overview stays the Overview; a registered view goes back to Zone).

**Search.** Typed into the box, searched 0.3 s after the last key: a quest ID finds that quest, two
letters or more go to `Q.Search(text)` (titles, the client's too, and givers). The results replace the
page (a list, each with its zone). A click on a result goes to it (above), with "Back to the search
results" in the tab bar; a click on a place or a tab does the same with that place. The search stays (the
box keeps its text) until it's emptied (the box's X, or deleting it), which goes back to the place, the
quest in the details in sight. One letter: "Type at least two letters." Closed before a search was due,
it runs when the window opens again.

**No data.** `Q.Load()` (it loads `LefthyTools_QuestData` the first time) not true, or no `Q.Load`: the
window says the data isn't there (missing or switched off in the AddOns list), without panes, search or
filters.

### What it costs

Built the first time it opens; nothing at login. A place's chains (`Q.Chain`, who leads to whom) are
worked out once and kept until the data changes; a chain's progress (its card, its head), a chain page's
cards and lines, a zone's pins and threads, the zone to suggest when the filters or a status change (an
event), or the window opens; a place's count once, until a quest of it is turned in (or one is taken or
dropped: that can close others). Statuses are read for the place's quests when its page is drawn and for
the cards near sight when they're filled. The lists (left, chain cards, overview, results) are pools of
the rows in sight plus 2 above and below; entry i always has row `(i - 1) % pool + 1`. Hovering only sets
alphas and line widths. While it's open it listens to `QUEST_TURNED_IN`, `QUEST_ACCEPTED`,
`QUEST_REMOVED`, `PLAYER_LEVEL_UP`, `QUEST_DATA_LOAD_RESULT` (a title asked for with
`C_QuestLog.RequestLoadQuestByID`, once per quest a session, came) and `QUEST_LOG_UPDATE` (only while the
zone page shows, looked at a second later at most: if a quest in my log got ready to turn in, only the
map's pins are drawn again); the handlers only note it, the window redraws on the next frame (an OnUpdate
set only while something is due), at most every 0.5 s for statuses, 0.2 s after titles. `Q.OnDataChanged`:
open, everything worked out goes and it's drawn again on the next frame; closed, when it opens. Dragging
(the canvas, the map) runs an OnUpdate only while the button is held. Closed: no events, no OnUpdate.

### Controller and taint

Our frames only; nothing protected, so it opens in a fight and in gamepad mode. No Blizzard menu, no
Blizzard panel opened (not the world map either: the zone map is our own frame with `LT.MapArt`'s
textures; no data provider, no pins on `WorldMapFrame`). Every card, chain card, pin, list row, tab,
filter, zoom button, link, place line, the head's way back and the suggestion are plain Buttons, so
SmartNavigation finds them as the panel's descendants (its focus runs OnEnter: the tooltips show, and a
chain's card lights its pins as with the mouse). The chain cards' list is a ScrollFrame (SmartNavigation
scrolls it); the chain's canvas and the map aren't (SmartNavigation only scrolls those up and down, and
only takes their buttons in sight): their buttons are the panel's own, and a card or pin the cursor moves
to out of sight (its middle outside, in gamepad mode or without the mouse over it) moves the view to it.
The canvas and the map have no OnMouseDown/OnMouseUp (they'd be buttons to SmartNavigation), only the
wheel and dragging. Nothing of Blizzard's (navigation flags, mixins, Backdrop) is set on our frames. A
registered view's frames are its own file's: the same rules apply.

Tests: `tests/questtree_browser.lua`, with stand-ins for every `Q.*` it calls (the data, the engine, the
iterations' `Q.ZoneCount`, `Q.ChainStep`, `Q.LevelColor`, `Q.Races`, `Q.ZoneGiven`, `Q.Available`,
`Q.IsTrivial`, the small window), put back at the end; it also checks the window without `Q.ZoneCount`,
`Q.ChainStep` and `Q.LevelColor`, and registers views of its own (removed at its end).

### Open questions (in game)

- That the canvas's anchor offsets count in its own (zoomed) units, so zooming and scrolling line up.
- That SmartNavigation's cursor moves onto a card or pin that's clipped out of sight (it's visible to it)
  and runs its OnEnter, so the view follows; and onto the chain cards' rows inside their ScrollFrame.
- The atlases `TrivialQuests`, `QuestRepeatableTurnin`, `SideInProgressquesticon`,
  `QuestDaily`, `common-icon-checkmark`, `Options_HorizontalDivider` on Forever (each falls back when
  missing), and the `|A:...|a` icons in the map's legend.
- That a desaturated `QuestTurnin` reads as the game's grey "?".
- That `Line` objects on the map frame (OVERLAY) draw over `LT.MapArt`'s tiles (ARTWORK) and under the pins.
- That `C_Map.SetUserWaypoint` from addon code doesn't taint anything in gamepad mode.

## Views (Views.lua)

Two more views of the big window, each a tab of its own: registered with the window's registry
(`Q.RegisterBrowserView(key, label, build)`; `build(parent)` gives `{ frame, Refresh, OnShow, OnHide }`)
when it's there: at load (Browser.lua comes before this file in the TOC), else when the module is
switched on (`Q.When("enable")`); without a registry nothing is registered and nothing breaks. Keys and
tabs: `storylines` "Storylines", `levelpath` "Level path". A view is built by the window when its tab is
first shown (`Q.BuildView(key, parent)` makes one; the tests use it), fills its parent, and lays itself
out again when the parent's size changes. They jump with `Q.OpenBrowser(id)` (a quest: its zone and
chain) and `Q.SelectZone(map)` (a zone; without it the zone's first quest).

Each view: a bar on top (chips or a headline), the list on a darker panel (a scroll frame of ours; only
the rows near sight exist, pooled, each kept on its entry while it stays near, so the controller's
cursor stays on it), a footer (the level path's legend) and, while counting, "Counting quests... 40%".
No data (`Q.Ready()` not true): the window's line that the data add-on is missing.

The **Continents** view of earlier builds (a tile per zone by continent with its percentage done,
what's available and ready, friends' progress as a second bar) is gone: the zone list on the window's
left already shows each zone's progress.

**For my levels** is the engine's `Q.InRange(id)` (a quest in my log; else not grey for me and its
minimum level at most `Q.RANGE_ABOVE`, 2, above mine); without it everything counts as in range.

### Storylines

Every chain for me in every zone (`Q.Chain` of every zone's and dungeon's quests; 2 or more quests that
aren't "not for me"), as cards in rows (as many 280 px or wider as fit), each of three lines (58 px):
the chain's title (its first quest's, the client's when it has it) and "3/7" (green when done); its
zone (where most of its quests are) and levels "[10-18]" in difficulty colours; its next step: "Turn
in: [7] ..." (a quest of it ready in my log), "In your log: ...", "Next: ...", "Coming up: ...", "All
done". At the left the status strip (the big window's tones: ready to turn in gold, in my log blue,
available amber, done green, later grey) and the icon (`QuestTurnin`, `SideInProgressquesticon`,
`QuestNormal`, a lock, a check; the gossip icons without the atlases); a thin green bar of the steps
done along its bottom. No colour legend. The tooltip: every zone it's in, steps done, the next step and
its giver, what it's worth, friends who did the next step (`Q.Friends`), "Click: open this storyline". A
click: `Q.OpenBrowser` on the quest to turn in, else the next step, else the first.

- **Filters** (chips with counts, one at a time): **For your level** (the default: its next step is
  `Q.InRange`, not all done), In progress (a step done or in my log, not all done), Ready to turn in,
  Done, All. Nothing left: "No storyline matches this filter." and a button that shows them all.
- **Sort**: Worth (Quest Chain Helper's idea, "is it worth it"): the quests left in it for me, each
  counted by its level, a grey one a tenth, one whose level is too high for me (or more than 4 above
  mine) half; or Level: the next step's level, the lowest first. Done chains last either way.
- Kept in the module's settings: `views = { show, sort, allZones }` (made when first needed; `show` the
  filter, "level" at first; the key `filter` of the builds before is ignored, so the new default wins
  once).

### Level path ("where to go next")

The zones of my side (a zone with quests for me: 5 or more, or a quarter of its quests) that have
something for my levels (a quest not done that's `Q.InRange`) or a friend there (Beacon's, with the
module's `friends` setting, whose zone, Battle.net's `area` matched to the zone's name, the client's or
the data's, it is); the chip **All zones** at the top right shows every zone of my side (kept:
`views.allZones`). A row (26 px) has only: the name (a faint blue band for the zone I'm in,
`Q.HereZone`), a bar across the levels 1-60 (more if a zone goes higher; ticks every ten and "You (12)"
on top) from the zone's lowest to its highest level, shaded per level: done (all its quests done,
green), quests to take (one I can take or have, amber), later (grey); a level without quests takes the
shade before it, quests outside the zone's range count at its ends; a gold line at my level; at the
right "7 for your level" (its quests `Q.InRange` not done), else "All done", else nothing. Sorted by that
count, then the zones my level is in, then the nearest. On top: "Best next: Westfall, 7 quests for your
level", or "Nothing for your level. Next up: Redridge Mountains, from level 15." No zone left: "No zone
has quests for your level." and a button that shows all zones. The tooltip has the rest: levels, done,
for my level, what I can take now, in my log, later, each run of levels, friends there (name, level),
"You're here.". A click: `Q.SelectZone`. The legend: done, quests to take, later, my level's line.

### What it costs

The counts are made once and kept: every zone's quests by status (`Q.Status`), level and range
(`Q.InRange`), every chain's (`Q.Chain`: done, in the log, available, levels, zones, next step and
whether it's in range, worth), 200 quests a frame on a frame of ours that's shown only while counting
(5257 quests, 3473 of them in chains: well under a second, no hitch), and only while a view is shown.
They're for a data, progress and level (`Q.dataGen`, `Q.progressGen`, `UnitLevel`): made again when one
changed (checked when a view shows or draws; `Q.Status(0)` first, so a quest taken while no view was
shown is read), or after `QUEST_TURNED_IN`, `QUEST_ACCEPTED`, `QUEST_REMOVED`, `PLAYER_LEVEL_UP` or
`Q.OnDataChanged`; the last counts stay drawn meanwhile. What's ready to turn in is read from the quest
log when a view draws (`QUEST_LOG_UPDATE` only draws again, it doesn't count). Events are registered
only while a view is shown; they're noted and drawn half a second later (several: once); friends'
answers (`Q.OnFriendProgress`) draw again. Friends' places are read when a view draws. A view's
`Refresh` (the window's) draws on the next frame. Hidden: no events, no OnUpdate.

### Controller and taint

Our own frames only, nothing protected (it works in a fight), no Blizzard menu. Every card, row, chip
(the level path's toggle too) and the empty state's button is a Button, so SmartNavigation reaches them
(its focus runs OnEnter: the tooltips); the lists are scroll frames (it scrolls them); nothing of
Blizzard's is set on our frames.

Tests: `tests/questtree_views.lua` (the real Data.lua and Engine.lua through `Q.SetTestData`; the
registry is a stand-in that records, the real one put back after; `Q.OpenBrowser` and `Q.SelectZone`
record the jumps).

### Open questions (in game)

- That the registry's parent has its size when a view is shown (else the view lays itself out again
  on `OnSizeChanged`).
- How long the counting takes with the real data, and whether "Counting quests" is seen at all.
- Battle.net's `areaName` for a friend's zone on a German client (matched to the client's zone names).

## Learning and friends

Files: `Modules/Questtree/Learn.lua` (learning while playing) and `Modules/Beacon/QuestShare.lua`
(friends' progress and learned data over Beacon; its words are in [beacon.md](beacon.md), "Questtree").

### Learning (Learn.lua)

Only while the Questtree module is on with its `learn` setting, and only for quests the data
doesn't know fully. A quest I already have a record of is kept whole: my records are merged into
the data's tables (`Q.AddLearned`), so those can't tell what came from where. The data is asked
(`Q.Quest`) only once it's loaded (`Q.IsLoaded()`, Data.lua): asking must never load it, that's
for the windows. Without the data add-on (or before a window loaded it) everything is kept.

What it reads, all read-only (no Blizzard frames, nothing that could taint):

- **Who:** `UnitGUID("npc")`: a creature (`LT.CreatureOf`) or a `GameObject-...-<id>-...`; a
  player sharing a quest, or a secret GUID, gives nothing. The name from `UnitName("npc")`. A
  quest from an item: `QUEST_DETAIL`'s `questStartItemID`. **Where:** my spot
  (`C_Map.GetBestMapForUnit("player")`, `C_Map.GetPlayerMapPosition`), rounded to thousandths; in
  an instance the map only. Secret values are left out, never stored.
- **Givers:** the quests offered in a gossip (`GOSSIP_SHOW`, `C_GossipInfo.GetAvailableQuests`:
  title, level) or a greeting (`QUEST_GREETING`, `GetAvailableQuestInfo`'s fifth return,
  `GetAvailableTitle`, `GetAvailableLevel`), a quest dialog (`QUEST_DETAIL`, `GetQuestID`,
  `GetTitleText`) and accepting (`QUEST_ACCEPTED`: the dialog's giver if it was the same quest in
  the last 120 s, else whoever I talk to). The level from the quest log once accepted
  (`C_QuestLog.GetInfo(index).level`).
- **Enders:** the active quests of a gossip or greeting (an NPC lists the quests that end with it),
  and turning in (`QUEST_COMPLETE`'s dialog, `QUEST_TURNED_IN`).
- **Prerequisites** (`p`: 2 strong, 1 weak). Each NPC's last full list of offers is remembered
  (this session, 40 NPCs), and the last 5 turn-ins. A quest an NPC offers now that it didn't
  offer the last time I looked (at the same level: a level-up may be what opened it), after
  exactly one turn-in since (or exactly one at that NPC), has that turn-in before it: strong. At
  an NPC whose list I never saw: a quest offered within 3 s of a turn-in there is its follow-up
  (strong, the game's own chain), within 60 s only a hint (weak). Strong ones are fed as `pre`
  (and the earlier quest's `opens`), weak ones only as `opens`. **Proven wrong** (`x`): a quest
  offered while one of its prerequisites isn't completed (`C_QuestLog.IsQuestFlaggedCompleted`
  false: another character of the account, or a friend's record) didn't need it. Known limit: a
  quest that needs one of several (the data's `preAny`) loses the one this character skipped.

**Never lags:** the handlers read the dialog (it's gone later) into a note; a frame of our own,
shown only while notes wait, stores them, infers and feeds on the next frame, then hides.

**Kept** account-wide in `LefthyToolsDB.questtree.learned[questID]` = `{ u, t, l, s, e, p, x, f }`
(stamp, title, level, giver, ender, prerequisites, proven not, the friend's account whose record
changed it last); giver and ender `{ k = "n" | "o" | "i", i, n, m, x, y }`. At most 1500 records:
over that, the oldest changes go, down to 1350. At most 4 prerequisites and 8 proven-not per
quest. `LefthyToolsDB.questtree.share = { seq, epoch, got }`: the store's change counter (each
change stamps its record with the next), a random id made with the store, and how far I hold each
friend's (below). Broken records are dropped at load; a stamp above `seq` is stamped anew.
**Fed** into `Q.AddLearned(id, fields)` at login (50 a frame, not in a fight, once the module is on;
`Q.FeedLearned()` again when it's switched on later) and with each change: `title`, `level`, `zone`
(the giver's map, not for items), `starts` / `ends` (`{ { kind = "npc" | "object" | "item", id, name,
points = { { map, x, y } } } }`), `pre`; the earlier quest of each prerequisite gets `opens`.

For QuestShare.lua and the windows: `Q.LearnedStore()`, `Q.LearnedMeta()`, `Q.Learned(id)`,
`Q.MergeLearned(id, rec, fromAccount)` (true if it taught me something: only gaps are filled, a place
with a point beats one without, prerequisites keep the strongest, proven-not wins), `Q.LearnText`.

### Friends' progress (QuestShare.lua)

A window showing a quest calls `Q.RequestFriendProgress(id)` (false when no friend's build can
answer, or the module's `friends` setting is off): the quest and its chain (`Q.Chain`, Engine.lua;
at most 40) go to every friend on a build from `QUESTTREE_SINCE` on, at most one request every 2 s
(the latest wins), the same quest again only after 20 s. A friend answers the latest of mine at most
once a second: a letter per quest, from `C_QuestLog` (done, ready to turn in, in the log, none); or
nothing when their `friends` setting is off ("not shared"). Answers count for 60 s and only from
friends asked. They fill **`Q.friends[gameAccountID]`**, the table Engine.lua reads (its `Q.Friends(id)`,
`Q.Status(id, progress)`, `Q.Missing(id, progress)`), in memory, dropped when Beacon forgets the friend:

- `{ done = { [questID] = true }, active = { [questID] = true }, name, classFile, class, level, faction,
  race, gameAccountID }` (who they are from Beacon's peer: level as they told it; faction and race from
  Battle.net's game account info, the race localized), plus `ready` (in the log and ready to turn in,
  also in `active`), `known` (asked and answered: in neither set means not done and not in the log),
  `n`, `at`, `shares` (false: not shared). At most 400 quests per friend, then the oldest answers go.
  `Q.friends` is looked up at each use, so Engine.lua may make the table itself.
- `Q.FriendProgress(gameAccountID)` -> that table or nil; `Q.FriendProgress()` -> `Q.friends`.
- `Q.FriendStatus(gameAccountID, id)` -> "done", "ready", "active", "none" or nil (not known).
- After answers came (on Beacon's tick): `Q.RedrawSmall(now)` when the small window has it (the
  request's first quest is the one a window shows), and every `Q.OnFriendProgress(fn)`.

### Learned data between friends (QuestShare.lua)

Like Chronicle's recipes, but simpler: every holder serves its own store (which holds what it
learned from others too), so a record goes on from friend to friend. To every friend on a
reading build, at low priority: what I hold (my account, the store's epoch and `seq`), after
their build is known, again when it grew (at most once a minute) and every 10 minutes. A friend
whose offer is beyond what I hold of their store (`got[account] = { epoch, seq }`, saved; another
epoch: from 0) is asked for what changed since, one friend at a time (given up after 120 s
without a record, asked again after 30 s). The answer: at most 100 records in stamp order, then
the end with how far it got; the end counts only if every record came, then the rest is asked
for at once. Records go 4 a second at most and only while fewer than 8 messages wait in Beacon's
queues. A record whose last change came from the asking friend's account isn't sent back to them,
and one that teaches nothing isn't stamped anew: each record goes once each way.
Merged with `Q.MergeLearned` (from the asked friend only), and so fed into `Q.AddLearned`.

Nothing of it in a fight (`LT.InFight`): friends' messages wait (300 at most; a request for
records that lost one isn't counted complete), one request per friend waits, nothing is sent.
Older builds get nothing (their `V2`; before it's known, nothing either).
