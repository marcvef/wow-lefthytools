# Questtree

Quest chains for every zone of WoW: Forever: what a quest needs first, what it leads to, who gives
and takes it and where, and where each quest stands for you and your friends.

| File | What |
|---|---|
| `Modules/Questtree/Data.lua` | the quest data (`LefthyTools_QuestData`): loading it, the accessors, search, learned data |
| `Modules/Questtree/Engine.lua` | a quest's status for me or a friend, what's missing, what it opens, its chain, what's next |
| `LefthyTools_QuestData/` | the data, an add-on of its own (load on demand, GPL v3) |
| `tools/update-quest-data.js` | makes the data |
| `Modules/Questtree/Questtree.lua` | the module: settings, `/questtree`, shared helpers (status colours, titles) |
| `Modules/Questtree/MiniMap.lua` | the small zone map (our own frame, the zone's map art) |
| `Modules/Questtree/Small.lua` | the small window: one quest, what it needs, giver and turn-in on the small map |
| `Modules/Questtree/Browser.lua` | the big window: zones, chains as a tree, details, search |
| `Modules/Questtree/Learn.lua` | learning givers, enders and prerequisites while playing |
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
## Big window (Browser.lua)

`Q.ToggleBrowser()` opens or closes it, `Q.OpenBrowser(id)` opens it on a quest (its zone or dungeon on
the left, its group unfolded, its row in the middle of sight, its details), `Q.HideBrowser()` closes it
(the module switched off), `Q.BrowserShown()` says whether it's open. With the module off it doesn't open
(one chat line says how to switch it on).

**Size.** 1200 x 760 (`LT.Window.Create`, `LefthyToolsQuesttreeBrowser`, in `UISpecialFrames` so Escape
closes it, movable), scaled down to fit when the screen (`GetScreenWidth`/`GetScreenHeight`, UI units) is
smaller than that plus 40 x 80. In the band under the title: "Search all zones:" with its box, and a
legend of the status colours on the right. Under it three panes in the inset:

- **Left (270 px): places.** `Q.Zones()` grouped by continent in the order it gives them (a header per
  continent, its name from `C_Map.GetMapInfo`; a click folds it), then a "Dungeons" header and
  `Q.Dungeons()`. Each row: the name, the level range, "done of total": `Q.Status` over
  `Q.ZoneQuests(map)` / `Q.DungeonQuests(name)`, quests whose status is `other` (another race, class or
  faction) not counted, in green when all are done, a dash when none is for me. The first time it opens, the zone I'm in is chosen
  (`C_Map.GetBestMapForUnit`, then its parents), else the first zone.
- **Middle (500 px): the tree.** A title (the place, its levels, done of total), then a group per chain:
  every quest of the place goes through `Q.Chain(id)` once; a chain of more than one quest is a group
  (its header: the first quest's title, done/total of the whole chain, a click folds it), ordered by the
  lowest level of its quests in this place. Inside, the rows are a tree: who leads to whom is each
  quest's `pre`, `preAny` and `preActive` and `Q.Opens`, inside the chain; the first quests are those
  nothing in the chain leads to. A quest that leads to one other has it under it in the same column, one
  that leads to several has them one column (14 px) further in, each with a line from it (a vertical
  line through the rows between, a short stub to the row), like a file tree; columns stop at the tenth.
  A quest two earlier ones lead to is drawn once, under the first one visited (the details' "Needs
  first" names the rest). Steps of the chain in another zone are shown with that zone at the right.
  The quests without a chain come last, under "Quests without a chain", by level. Each row: a dot in the
  status's colour (a lock for locked), "[level] title" in that colour: done green, in my log yellow,
  available white, locked grey, level too low orange, not for me dim. Hover: a tooltip (title, status,
  zone); a click: the details.
- **Right: the details** of the quest clicked, in a scroll area: the title (the client's,
  `C_QuestLog.GetTitleForQuestID`, when it answers, else the data's), its status (level too low: which
  level it needs), level and minimum level, its zone, which step of its chain it is, tags (new in WoW:
  Forever, repeatable, learned while playing); "Requirements": faction, races and classes (the masks'
  bits, names from `C_CreatureInfo.GetRaceInfo` and `GetClassInfo` when they answer), skill
  (`C_TradeSkillUI.GetTradeSkillDisplayName`), reputation (`C_Reputation.GetFactionDataByID` and the
  standing's `FACTION_STANDING_LABEL<n>`), what it's a breadcrumb to, what taking it closes; "Starts at"
  and "Turn in at" (up to three each, objects and items said so, the zone of the first spot); the small
  map (`Q.NewMiniMap(box)` made once into a box under them; `m:Show(map, points)` with the first giver's
  map, else the first ender's, and every start and end spot on that map, at most 20 of each; no
  `Q.NewMiniMap`, or one that fails: no map); "Needs first:" (`Q.Missing(id)`) and "Leads to:"
  (`Q.Opens(id)`), a button per quest (at most 12 each, "... and N more"), in its status's colour, its zone
  named when it isn't the place shown; friends (`Q.Friends(id)`: names in class colour, their status;
  at most 12); and at the bottom, outside the scroll area, "Show in the small window" (`Q.ShowQuest`).

**Going to a quest** (a link, a search result, `Q.OpenBrowser(id)`): it stays in the place shown if that
place's tree has it (a chain reaching into it), else goes to the quest's zone if that zone lists it, else
its dungeon if that lists it, else its zone. Its continent and its group unfold, the left list scrolls to
the place when it changed. A click on a quest (a row or a link) also shows it in the small window when
that's open (`Q.IsSmallShown()`, the small window's part; without it this is skipped).

**Search.** Typed into the box, searched 0.3 s after the last key: a quest ID finds that quest, two letters
or more go to `Q.Search(text)` (titles, the client's too, and givers). The results replace the tree, each
with its zone. A click on a result goes to it (above), with "Back to the search results" as the first
row; a click on a place does the same with that place. The search stays (the box keeps its text) until
it's emptied (the box's X, or deleting it), which goes back to the tree where it is, the quest in the
details in sight. One letter: "Type at least two letters." Closed before a search was due, it runs when
the window opens again.

**No data.** `Q.Load()` (it loads `LefthyTools_QuestData` the first time) not true, or no `Q.Load`: the
window says the data isn't there (missing or switched off in the AddOns list), without panes, search or
legend.

**What it costs.** Built the first time it opens; nothing at login. Both lists are pools of the rows in
sight plus 2 above and below (a controller's cursor finds the next row; Blizzard's SmartNavigation then
scrolls it to the middle), and entry i always has row `(i - 1) % pool + 1`, so a row keeps its quest while
the list scrolls under it (only rows whose entry changed are moved). A place's tree is worked out once and
kept; a place's count once, until a quest of it is turned in. Statuses are read for the rows in sight and
the open place's group headers. While it's open it listens to `QUEST_TURNED_IN` (that quest's places
counted again), `QUEST_ACCEPTED`, `QUEST_REMOVED`, `PLAYER_LEVEL_UP` and `QUEST_DATA_LOAD_RESULT` (a title
asked for with `C_QuestLog.RequestLoadQuestByID`, once per quest a session, came); the handlers only note
it, the window redraws on the next frame (an OnUpdate set only while something is due), at most every
0.5 s for statuses, 0.2 s after titles. `Q.OnDataChanged` (registered when the window is first built):
open, everything worked out goes and it's drawn again on the next frame; closed, when it opens. Closed:
no events, no OnUpdate. Opening again draws what's true now (counts counted again).

**Controller and taint.** Our frames only; nothing protected, so it opens in a fight and in gamepad
mode. No Blizzard menu. Every row, link, the clear button and the small window's button are plain Buttons
(SmartNavigation finds them as the panel's descendants); nothing of Blizzard's (navigation flags, mixins)
is set on our frames.

Tests: `tests/questtree_browser.lua`, with stand-ins for every `Q.*` it calls (the data, the engine, the
small window, the small map), put back at the end.

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
