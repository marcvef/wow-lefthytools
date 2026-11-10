# Questtree

Quest chains for every zone of WoW: Forever: what a quest needs first, what it leads to, who gives
and takes it and where, and where each quest stands for you and your friends.

| File | What |
|---|---|
| `Modules/Questtree/Data.lua` | the quest data (`LefthyTools_QuestData`): loading it, the accessors, search, learned data |
| `Modules/Questtree/Engine.lua` | a quest's status for me or a friend, what's missing, what it opens, its chain, what's next |
| `LefthyTools_QuestData/` | the data, an add-on of its own (load on demand, GPL v3) |
| `tools/update-quest-data.js` | makes the data |

Every Questtree file starts with `local Q = ns.Questtree or {}; ns.Questtree = Q`, so the order they
load in doesn't matter for the table.

## Data

### Where it comes from

`LefthyTools_QuestData/QuestData.lua` is made by `node tools/update-quest-data.js [build] [--cache
<dir>] [--dump <file>] [--eglink <commit>] [--stats]` (the same output for the same inputs):

- **Classic quests: CMaNGOS Classic DB** (Full_DB z2815, GPL v3, the dump the Bestiary's drop data
  comes from): `quest_template`, `creature_`/`gameobject_questrelation` (givers),
  `..._involvedrelation` (enders), `item_template.startquest`, the spawns (`creature`,
  `creature_spawn_entry`, `gameobject`) and the templates' names and factions.
- **Forever's new quests: EG Link** (`github.com/JIVESCORP/eg-link-output-wowf`, CC BY 4.0: "Data
  from Efficient Games (https://efficient.games), licensed under CC BY 4.0"): `quests.enUS`
  (title, levels, race mask, zone, `nextQuestId`, `startItemId`), `npcs` (who offers and takes each
  quest, their uiMap positions, their side) and `quest_prerequisites` (what every character seen
  taking a quest had done before: `before`, `characters`). The commit used is in `source`.
- **Forever's client tables** (wago.tools): UiMap, UiMapAssignment, AreaTable, Map, QuestSort,
  FactionTemplate, QuestV2, QuestLineXQuest, ItemSparse (StartQuestID, item names), QuestPOIBlob.
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
- **Faction:** races only of one side; else, without races, when every NPC giver is on one side
  (FactionTemplate's groups, EG Link's `side`). Races and classes are classic's bit masks (race ID
  r is bit r, Human 1 ... Troll 8; class Warrior 1, ..., Druid 11); EG Link's 64-bit race mask: its
  low 8 bits.
- **Left out:** classic quests the Forever client doesn't have (not in QuestV2, unless repeatable;
  137, mostly Naxxramas' tier quests), unused ones by title, quests nobody gives or takes; Forever's
  test quests; later classic content (IDs 10000+) no one was seen offered.

Numbers (Forever 1.60.1.70862, EG Link 9fcae73): 5257 quests (4031 classic, 1226 Forever's), 3473
of them in 784 chains, 4312 with a giver on the map or an item; of the 1817 new quests 1213 are in
it, 415 with chain info, 492 with a giver, 808 with a zone; 50 zones, 35 dungeons, 1667 NPCs, 239
objects, 599 items; 0.53 MB.

### Format

```
LefthyToolsQuestData = {
  source, build,
  names = { "Ahn'Qiraj Temple", ... },              -- zoneName, sort and dungeon are indexes into it
  zones = { [uiMap] = "continent|minLevel|maxLevel|name|quest IDs" },
  dungeons = { [names index] = "minLevel|maxLevel|quest IDs" },
  npcs = { [id] = "name|map,x,y;map,x,y/map,x,y" }, objects = (the same), items = { [id] = "name" },
  quests = { [id] = "title|level|minLevel|races|classes|zone|zoneName|sort|dungeon|pre|preAny|
                     preActive|excl|opens|breadcrumbFor|flags|skill|rep|starts|ends" },
}
```

x, y in thousandths; `/` separates a place's alternatives; quest IDs with `,`; flags: `A`/`H`
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
  one table per NPC shared by all its quests. `zoneName`: the area's name, else the zone's, the
  dungeon's or the sort's. The title is English: the UI prefers `C_QuestLog.GetTitleForQuestID`.
- `Q.Zones()`: `{ map, name, continent, minLevel, maxLevel, count }` by continent, then level.
  `Q.Dungeons()`: `{ name, minLevel, maxLevel, count }` by level. `Q.ZoneQuests(map)`,
  `Q.DungeonQuests(name)`: quest IDs, the lowest level first.
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
  a quest needs leads to it (`opens`) without saying so. Learned data and caches go; the callbacks
  run at once.

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
  faction, race (raceID) or raceFile, class (classID) or classFile }`; skill and reputation aren't
  checked for friends.
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
# Questtree design

Quest chains for every zone of WoW: Forever: what a quest needs first, where it starts and ends,
what it leads to, and which friends have done it. The data is a companion add-on
(`LefthyTools_QuestData`, load on demand), loaded the first time a Questtree window opens.

## Module

`Modules/Questtree/Questtree.lua`: the module `questtree`, shown as "Questtree" (never translated),
on by default. Every file of the module starts with `local Q = ns.Questtree or {}; ns.Questtree = Q`,
so the order they load in doesn't matter for the table; `Q.module` is the module.

**Settings** (`LefthyToolsDB.settings.questtree`, the module's defaults table is here):

| Key | Default | What |
|---|---|---|
| `keepPlace` | true | the small window opens where it was left, at its size; off: right of the middle, 320 x 470 |
| `friends` | true | friends' progress in the windows (`Q.Friends`) |
| `learn` | true | learning while playing (Learn.lua reads `M.db.learn`) |
| `small` | `{}` | the small window's `left`, `top`, `width`, `height` (always kept; used while `keepPlace` is on) |

The settings page: Open the small window, Open the quest browser (`Q.ToggleBrowser`, or a chat line
when Browser.lua isn't there), the three checkboxes.

**Commands:** `/questtree` opens or closes the small window, `/questtree <name or ID>` shows a
quest (a quest link works too), `/questtree browse` the quest browser, `/questtree settings`,
`/questtree help`. `/lefthy questtree ...` is the same. Switched off, each says so (settings and
help still work). Chat lines are English.

**Finding a quest by name** (`Q.Find(text)`): a number or a quest link is that quest; otherwise
`Q.Search(text)`'s quests ranked by: the title (the client's or the data's) is the text, starts
with it, or only contains it (or the giver's name does); then my status (in my log, ready to take,
needs one first, level too low, done, not for me); then nearest my level; then the lower ID. When
several match, chat says how many and which is shown.

**What the files share** (Questtree.lua): `Q.When("enable" | "disable" | "settings", fn)` (what a
file does when the module is switched on or off or a setting changes), `Q.Ready()` (the data is
there: loads it on the first call, so only call it when a window opens or draws), `Q.Title(id)`
(`C_QuestLog.GetTitleForQuestID` when it answers, else the data's English title, else
"Quest 1234"), `Q.StatusOf(id, who)` (`Q.Status`, "other" without the engine), `Q.STATUS` (each
status's colour and words), `Q.StatusCode(status)`, `Q.StatusText(status, kind)` (coloured:
the window's line, `"word"` after a quest's name, `"friend"` for a friend's), `Q.LevelText(quest)`
("Level 12 (from 10)"), `Q.MapName(map)`.

Never lags: nothing is loaded, registered or run at login; the data loads when a window opens.

## Small window

`Modules/Questtree/Small.lua`: `Q.ShowQuest(id)`, `Q.ToggleSmall()`, `Q.RedrawSmall(now)` (a
redraw 0.3 s later, several at once: one; `now`: at once; for other parts whose data changed, e.g.
friends' progress arriving), `Q.SmallFrame()` (tests).

One quest at a time, top down: its title, a grey line (level, zone, dungeon, repeatable, new in
WoW: Forever), my status in its colour ("Your level is too low: from level 30" for `level`),
**Needs first:** (`Q.Missing`, numbered, the one to do first at the top; at most 8 lines, then
"and N more"), the **giver** and the **turn-in** (name and zone; an item or object says so, "+2
more" when there are several; not known: says so), the **small map**, **Leads to:** (`Q.Opens`),
and **Friends:** (`Q.Friends`, class-coloured names with their status; setting `friends`). Each
quest line is a button showing that quest (its tooltip: the title, the status, the engine's reason,
"Click: show this quest"); the giver's and turn-in's lines put their zone on the map. The map shows
the giver's zone, or the turn-in's for a quest in my log, unless a line picked one; a person in
several places: the one on my map, else the first. Every giver and turn-in on that zone has a
marker.

Opened on its own (`/questtree`, `Q.ToggleSmall`) it shows `Q.Next()[1]` (none: what it showed
last; nothing: "Nothing up next found"). Buttons at the bottom: **Back** (the quest shown before,
up to 20), **Next up** (`Q.Next()[1]`), **Quest browser** (`Q.OpenBrowser(id)`, else
`Q.ToggleBrowser()`; hidden without Browser.lua). The data add-on missing: the window says so
(run the updater, restart), nothing else. A quest the data doesn't know: its title and that line.

The window: `LT.Window.Create` (`LefthyToolsQuesttreeSmall`: Escape closes it, it counts as an
open window for Mirage, the AFK screen and flights), DIALOG strata, raised when a quest is shown
(the browser's clicks bring it up). Movable, resizable by its corner grip (300-600 x 260-900);
where it is and its size are saved on every drag and resize (`small`). The content is in a scroll
area; its width and the map's follow the window's. Built the first time it opens. While shown it
listens to `QUEST_ACCEPTED`, `QUEST_TURNED_IN`, `QUEST_REMOVED` and `PLAYER_LEVEL_UP` (and
`Q.OnDataChanged`) and redraws 0.3 s later; hidden, no events and no OnUpdate. Nothing protected:
it opens and works in a fight.

**Controller:** every line that does something, the map's markers, the bottom buttons and the
grip are buttons of ours, so SmartNavigation's cursor reaches them (its focus runs OnEnter: the
tooltips show). Nothing of Blizzard's is set on our frames, no Blizzard menu, no panel opening.

**Small map** (`Modules/Questtree/MiniMap.lua`, also for the big window):
`local m = Q.NewMiniMap(parent[, width, height])` (240 x 160 by default), `m.frame`,
`m:Show(map, points[, name])` with `points = { { x, y, kind = "start" | "end", label } }` (0..1 on
that map), `m:SetSize(w, h)`, `m:Hide()`, `m:Markers()` (tests). The zone's art and what you've
explored of it (`LT.MapArt`, as the fight stream's map and the Bestiary ledger's), as large as
fits, on a dark box; the zone's name on a strip over its top. Markers: the gossip `!` for a giver,
`?` for a turn-in; points within 6 px share one marker, its tooltip naming each with what it is
(a giver who's also the turn-in); at most 40; points off the map are left out. No art: "No map of
this zone" with the markers on the dark box. Laid only when the map or the size changes (or you've
explored more); never touches `WorldMapFrame`.

**Tests** (`tests/questtree_small.lua`): the module, settings and commands; the window opened on
its own and by ID, name and link (the best pick), every part of a quest, rows, Back, Next up, the
map and its markers, friends and their setting, an unknown quest, the data missing, the browser
command, events only while shown, place and size kept and the setting off, a fight, buttons for
the controller, switched off; the small map alone. Without Data.lua and Engine.lua in the build it
puts stand-ins of their functions on `ns.Questtree` (and takes them away at its end); with them it
installs its quests through `Q.SetTestData` and checks against the engine's answers.
