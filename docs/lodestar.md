# Lodestar

Quest chains for every zone of WoW: Forever: what a quest needs first, what it leads to, who gives
and takes it and where, and where each quest stands for you and your friends.

| File | What |
|---|---|
| `Modules/Lodestar/Data.lua` | the quest data (`LefthyTools_QuestData`): loading it, the accessors, search, learned data |
| `Modules/Lodestar/Engine.lua` | a quest's status for me or a friend, what's missing, what it opens, its chain, what's next |
| `LefthyTools_QuestData/` | the data, an add-on of its own (load on demand, GPL v3) |
| `tools/update-quest-data.js` | makes the data |
| `Modules/Lodestar/Lodestar.lua` | the module: settings, `/lodestar`, shared helpers (status and difficulty colours, titles, distances, the map pin, the quest log's objectives matched to the data), NPC tooltip lines, the quest log hook |
| `Modules/Lodestar/MiniMap.lua` | the small zone map (our own frame, the zone's map art uncovered, the game's quest icons, drop and objective areas, zoom, your arrow) |
| `Modules/Lodestar/Small.lua` | the small window, the companion: the quest you're on (its objectives' areas on the small map) and what to pick up next nearby; any quest looked at |
| `Modules/Lodestar/Browser.lua` | the big window: zones; a zone's large map (pins, the quest picked's objective areas and way, zoom, my arrow); the right pane: the zone's or chain's briefing (its chains' cards, its steps), a quest's details (steps, objectives, giver and turn-in, rewards); a chain opened (cards, lines, joins, stubs, the way to a locked quest); a quest list; filters (my levels by default); search; tabs for views other files register |
| `Modules/Lodestar/Views.lua` | the big window's other views: my quests (the quest log, organised; the storylines to go on with), the level path (where to go next) |
| `Modules/Lodestar/Learn.lua` | learning givers, enders and prerequisites while playing |
| `Modules/Lodestar/Dialog.lua` | in the game's quest UI: the panel beside the quest dialog, chain steps on the quest log's lines, Alt-click there |
| `Modules/Lodestar/Items.lua` | quest items: item tooltips (which quest it's for, where that stands, whether to discard it), `Q.ItemDone` and the sorted bags' mark |
| `Modules/Beacon/QuestShare.lua` | friends' progress and learned records over Beacon (`B2;q…`, from 0.7.0-70) |
| `Modules/Lodestar/Route.lua` | a suggested route for the plan's stops (only when asked), yards between two spots |

Every Lodestar file starts with `local Q = ns.Lodestar or {}; ns.Lodestar = Q`, so the order they
load in doesn't matter for the table.

## Data

### Where it comes from

`LefthyTools_QuestData/QuestData.lua` is made by `node tools/update-quest-data.js [build] [--cache
<dir>] [--dump <file>] [--eglink <commit>] [--stats]` (the same output for the same inputs):

- **Classic quests: CMaNGOS Classic DB** (Full_DB z2815, GPL v3, the dump the Bestiary's drop data
  comes from): `quest_template`, `creature_`/`gameobject_questrelation` (givers),
  `..._involvedrelation` (enders), `item_template.startquest`, the spawns (`creature`,
  `creature_spawn_entry`, `gameobject`), the templates' names, factions and loot IDs, and
  `creature_`/`gameobject_`/`reference_loot_template` (where items that start quests or are collected
  for one drop), and `quest_template`'s objectives (`ReqCreatureOrGOId1-4`/`Count`, `ReqItemId1-4`/
  `Count`, `SrcItemId`) and rewards (`RewChoiceItemId1-6`/`Count`, `RewItemId1-4`/`Count`,
  `RewOrReqMoney` above 0, `RewMoneyMaxLevel` for the experience), and the game events (`game_event`,
  `game_event_quest`, `game_event_creature`/`_gameobject`: the holidays' quests, who stands only then),
  `creature_template`'s `MinLevel`/`MaxLevel` (the mobs' levels), `UnitFlags`/`ExtraFlags` (triggers) and
  `quest_template.Type` (elite, dungeon, raid).
- **Forever's new quests: EG Link** (`github.com/JIVESCORP/eg-link-output-wowf`, CC BY 4.0: "Data
  from Efficient Games (https://efficient.games), licensed under CC BY 4.0"): `quests.enUS`
  (title, levels, race mask, zone, `nextQuestId`, `startItemId`), `npcs` (who offers and takes each
  quest, their uiMap positions, their side), `quest_prerequisites` (what every character seen
  taking a quest had done before: `before`, `characters`), `loot` (what players looted from which
  NPC or object, and where), `creatures` (names, where players met them), `object_details` (objects'
  names), and for every quest it has seen (classic's too) its `objectives` (type, ID, amount, storage
  index), `rewards` (choices, items, money, XP difficulty and multiplier) and `turn_ins` (the money
  players got, and their side). The quests' `objectivesText` and `description` (whom a quest is for) and
  `creatures`' `reactions` (how a creature met each side) for Forever's quests without a side. The
  quests' `questInfoId` (elite 1, dungeon 81, raid 62, as classic-db's `Type`) and `creatures`' `levels`
  (the levels players saw a creature at). Every position it has with its uiMap (`npcs`, `creatures`,
  `loot`: 9703) tells which zone's map a spot is on where zones' rectangles overlap (Places). The
  commit used is in `source`.
- **Forever's client tables** (wago.tools): UiMap, UiMapAssignment, AreaTable, Map, QuestSort,
  FactionTemplate, QuestV2, QuestLineXQuest, ItemSparse (StartQuestID, item names), QuestPOIBlob,
  ChrRaces (the playable races, their race-mask bits and sides), QuestXP (a quest's experience by its
  level and XP difficulty), WorldMapOverlay with UiMapXMapArt (the explored-area images of a zone's
  map: where its own areas are, for places). Forever's client has no QuestObjective table (wago.tools: "Table not
  found" for 1.60.1.70862 and 70888, the locale exports too): objectives come from EG Link and
  classic-db.
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
- **Places:** each spawn's world x/y on a zone (or dungeon floor, by height) rectangle of
  UiMapAssignment holding it: `mapX = (maxY - y) / (maxY - minY)`, `mapY = (maxX - x) / (maxX -
  minX)`, then into the assignment's `UiMin`..`UiMax` (Marshal Dughan comes out at 42.1, 65.9, as in
  game). Which rectangle: the client takes the one of the area the position is in (the terrain's
  area; the smallest only among that area's), and the data has no areas. Zones' rectangles overlap
  a lot: the Barrens' holds all of Mulgore's and most of Durotar's and Dustwallow's, so "the
  smallest" would be right for only 45% of the spawns where rectangles overlap (the old rule put
  the Barrens' Stormsnout and Kolkar on Mulgore's and Durotar's maps). The tool (`bestBox`) decides
  by what the data has of the areas, each spawn on its own, the first step that decides:
  - **A city's rectangle** (it lies inside its zone's but holds some of the zone around it: Skull
    Rock outside Orgrimmar's gate, Silverpine's coast west of the Undercity): the map EG Link
    recorded this NPC or creature on, if exactly one of them; the nearest position players' games
    recorded (EG Link's `npcs`, `creatures` and `loot` positions with their uiMap: the client's own
    answer there) within 150 yards; on its zone's explored-area images (WorldMapOverlay's hit
    rectangles, not the city's own drawn on its zone's map): the zone; else the city. Each step
    is right for every EG Link position in a city's rectangle it decides (the city alone: 87.5%).
  - **Zones whose rectangles overlap:** on the explored-area images (their bounds; the zone's own
    areas) of exactly one of them; a recorded position within 150 yards; the one map EG Link
    recorded this NPC or creature on; 25 yards inside exactly one zone's images' hit rectangles;
    a recorded position within 400 yards when every other of the zones' nearest is 1.5 times as
    far (not across a river where only one bank was played: the Valley of Trials has no recorded
    positions, the Barrens' bank 400 yards off has); inside exactly one's hit rectangles; the zone
    nearest its images and their hit rectangles (both distances added, negative inside); for zones
    without images the NPC's quests' zones (the most quests), then the nearest rectangle centre
    (relative to its size). On this data's spawns where rectangles overlap and a recorded position
    within 100 yards tells the zone: 99.9% right, 98.5% not using the positions within 100 yards,
    96.9% not those within 600 (as where nobody played). The quests' zones alone would be right for
    85% (a quest's mobs are often across its zone's border), so they come last.
  - Dungeon floors: the smallest (by height, then size), unless one of the NPC's quests' holds it.

  A drop source's or objective target's places are the same for every quest and item that uses it.
  An NPC's or object's other zones of about the same size whose rectangles hold the spot are stored
  as alternatives (a zone at most 4 times the other's size; a city and the zone around it never),
  and Data.lua asks the client (`C_Map.GetMapInfoAtPosition` on the continent) which one it is when
  it reads the NPC, keeping the tool's choice if the answer is none of them. Up to 5 places per NPC,
  1% apart. No spawn: EG Link's positions; none at all: no points (event NPCs). On a map EG Link
  recorded the same NPC or creature on: givers' and enders' first places 307 of 307 (96% with the
  old rule), drop and objective clusters 525 of 532 (64%; the rest at borders: the Southfury's
  crocolisks, Hillsbrad and Alterac).
- **Races:** Forever's playable races are ChrRaces' rows with a `PlayableRaceBit` and the playable
  flags classic's eight have (`0x600000`): Human 1 ... Troll 8 (bits 0-7, as in classic), High Order
  Skyborne 95 (bit 32, Alliance) and Windshaper Skyborne 96 (bit 33, Horde). A race mask has bit
  `PlayableRaceBit` per race (numbers up to 2^33: no bit operators, `HasBit` divides). **The race
  rule:** a mask with every classic race of a side gets every race of that side (classic-db knows
  only the eight: an Alliance quest, 77, becomes 77 + 2^32); a mask with every playable race is
  none (all). EG Link's 64-bit masks (hex) keep the playable races' bits, then the same rule
  (Forever's own quests for Skyborne only, or Tauren and Windshaper, stay as recorded).
- **Faction:** races only of one side; else, without races, when every NPC giver is on one side
  (FactionTemplate's groups, EG Link's `side`); else, with no NPC giver (an item, an object, none seen),
  when the enders with a side are all on one (Owen Thadd's books in Undercity). **Forever's own quests**
  with none of that (EG Link's `raceMask` is all bits for them: the server leaves it to the giver's side;
  quest_scan's `factions` only says which clients saw the quest), no giver or ender on a side: (a) an NPC
  their objectives text (else description) names, "for <Name>", "to <Name>", "with <Name>", "<Name>
  at/in ...", found by its exact name among classic-db's creatures, EG Link's NPCs and its creatures seen
  friendly by one side and hostile by the other, every one of that name on the same side, a kill
  objective's creature never ("...for Foreman Oslow in Redridge": Alther's Mill, the Alliance's); (b) else
  their zone when it's a side's own: the Alliance's Elwynn Forest, Westfall, Redridge Mountains, Duskwood,
  Loch Modan, Dun Morogh, Teldrassil, Darkshore, Stormwind City, Ironforge, Darnassus, the Horde's
  Durotar, Mulgore, Tirisfal Glades, Silverpine Forest, Orgrimmar, Thunder Bluff, Undercity (by UiMap
  name; no contested zone). Never a side whose other side's players EG Link saw turning the quest in
  (`turn_ins`: Eagle's Fist in Loch Modan, a treasure both sides find). Classic's quests keep classic-db's
  word: a neutral giver in an Alliance zone gives to both (Captain Grayson in Westfall). Classes are
  classic's bit mask (class ID c is bit c - 1: Warrior 1, ..., Druid 11).
- **Events** (flag `e`): a holiday's quest sort (QuestSort's name: Seasonal, Lunar Festival, Midsummer,
  Darkmoon Faire, Invasion, ...; classic-db's `ZoneOrSort`, EG Link's `categoryId`), a holiday's quest in
  `game_event_quest`, or one whose every giver stands only while a holiday is on (`game_event_creature`
  / `_gameobject`, the fishing contest's too); then what needs one of those, or is given by someone who
  stands nowhere and gives one (Children's Week's orphans), when no giver stands outside it. A holiday:
  a `game_event` with a `holiday`, linked to one, or named like one.
- **Item drops:** for each item that starts a quest, every creature (`LootId`) and chest or fishing
  hole (gameobject type 3 or 25, `data1`) whose loot has it, through references, with its chance
  (the Bestiary's drop-data rules: groups, references rolled `maxcount` times; world loot isn't
  left out here). Items classic-db has no source of: EG Link's `loot` (`npc:<id>`/`object:<id>`
  sources, chance = drops / loot windows). The 3 likeliest sources with places (then without), each
  with its spawns (else EG Link's loot spots, else its NPC's places) put on zone maps as for givers
  and clustered: a spawn within 7% of the map's width of a cluster's centre (heights counted 1.5
  times, a zone map being 3:2) joins it; the 3 clusters with the most spawns, each a centre and a
  radius (its farthest spawn plus 1%, 1.5% to 15%).
- **Objectives:** EG Link's for a quest it has (Forever's server's: it changed some of classic's
  counts, Thistlefur's 8 to 12), in its storage order, only `monster` (kill), `gameObject` (use or
  loot) and `item` (collect) ones; else classic-db's: `ReqCreatureOrGOId` (above 0 a creature, below
  0 an object) then `ReqItemId`, with their counts. Forever's own quests EG Link hasn't described
  have none. An item that is the quest's `SrcItemId` is handed over by the giver (`provided`). The
  places: a creature's or object's spawns (else where players met it, EG Link's `creatures`, else its
  NPC record's positions) in clusters as for drops (each spawn on its zone as for places), shared
  with the drop sources; an item's sources as for items that start quests, with
  places first, then in its quests' zones, then the likeliest. Not kept: area triggers, talking to
  someone, criteria (Forever's scenario steps) and spells.
- **Rewards:** EG Link's for a quest it has (Forever added a choice to many classic quests, Hogger's
  270000), else classic-db's: choices, items (with counts), money (EG Link's; when it has none, what
  players got on turn-in below level 60, the most often seen; else classic-db's `RewOrReqMoney`).
  **Experience:** EG Link's quests: the QuestXP row of its level at `xpDifficulty`, times
  `xpMultiplier`, floored, then the game's rounding (to 5 up to 100, 10 up to 500, 25 up to 1000,
  else 50): 425 of 482 turn-ins seen got exactly that, the other 57 exactly 3% more (a bonus).
  Classic-db's: `RewMoneyMaxLevel / 0.6` put on the nearest value of its level's QuestXP row (within
  5%), rounded the same way: 97% of the quests both have get Forever's value; none for dungeon, raid and PvP quests
  (`Type` 81, 62, 41: Forever multiplies those).
- **Levels:** EG Link's level and minimum level for a quest it has (Forever changed 95 of classic's:
  Grove of the Ancients 11 to 17), else classic-db's. A level of -1 or 0 scales to the player: flag
  `s`, no level.
- **Mob levels** (field `mobs`, `min[:max]`): the levels of what a quest's objectives make you fight.
  A creature's levels: classic-db's `MinLevel`..`MaxLevel`; EG Link's `creatures` (the levels players saw
  it at, -1 a boss's "??" left out) where classic-db doesn't have it, or where players saw it outside
  classic-db's range (Forever changed it: Silithid Swarm 1 to 21-22). Not a trigger (`UnitFlags`
  not selectable `0x2000000`, `ExtraFlags` invisible `0x80`) nor a friend of the quest's side (one of
  both sides' for a quest without a side: FactionTemplate's groups; EG Link's reactions for its own).
  The targets: each kill objective's creature; for an item to collect, the easiest of the creatures it
  drops from often enough (all its sources with 20% or more, or a quarter of the likeliest one's
  chance, that stand somewhere: not summoned ones), none when an object is among those (it can be
  gathered), when it drops from more than 40 creatures and objects (cloth, herbs, Green Hills of
  Stranglethorn's pages: from whatever is around) or when its likeliest source has under 5% (made,
  bought); objects to use have no level. `min`: the highest of the targets' lowest levels (what you
  have to fight at least), `max`: the highest level of any. Mobs more than 10 levels above the quest's
  own aren't its (a source elsewhere: The Dormant Shade's candle from the Hinterlands, the only one).
- **Group** (flag `g`): the quest's type elite (1), dungeon (81) or raid (62): EG Link's `questInfoId`
  for a quest it has (Forever's server's: it made The Defias Brotherhood 155, classic's elite escort,
  a normal quest), else classic-db's `Type`.
- **Who gives what:** each NPC's and object's quests it starts and ends (`npcQuests`,
  `objectQuests`), and per zone the quests given there (a giver's first place) that are listed
  elsewhere: a dungeon's quests at its town, another zone's.
- **Left out:** classic quests the Forever client doesn't have (not in QuestV2, unless repeatable;
  137, mostly Naxxramas' tier quests), unused ones by title, quests nobody gives or takes; Forever's
  test quests; later classic content (IDs 10000+) no one was seen offered.

Numbers (Forever 1.60.1.70862, EG Link 9fcae73): 5257 quests (4031 classic, 1226 Forever's), 3473
of them in 784 chains, 4312 with a giver on the map or an item; of the 1817 new quests 1213 are in
it, 415 with chain info, 492 with a giver, 808 with a zone; 49 zones (Deadwind Pass had only a
Duskwood quest, by a giver put on the wrong map), 35 dungeons, 1667 NPCs (789 places with
alternatives), 239 objects, 3434 items (599 start quests; 1602 with drop sources, 45 of them from EG
Link; 2834 sources of drops and objectives, 2074 with places); 3786 quests with objectives (5699, 2556 quests'
from EG Link), 727 with a choice of rewards, 1266 with reward items, 1058 with money, 4016 with
experience; 95 quests with Forever's levels instead of classic's, 12 that scale; 3372 quests with a
race mask, 3010 of them with a Skyborne bit; 3515 of one side (69 given one by the rules for quests
without: 8 by their ender, 37 by an NPC their text names, 24 by their zone; 1728 left without races or a
side), 232 event quests; 1259 quests with mob levels (229 of them above the quest's own level: 49 by 1,
62 by 2, 118 by 3 or more, mostly raids' bosses at 63), 991 for a group; 0.99 MB (1,037,581 bytes; 1,037,544 before
places by the zones' areas; 0.98 MB,
1,029,989, before mob levels and the group flag; 0.63 MB before objectives and rewards).
Forever's own quests' objectives mostly have no places (1064 of 1212: its new items' drops and
creatures aren't in classic-db, and EG Link's loot has no quest items).

### Format

```
LefthyToolsQuestData = {
  source, build,
  races = { [raceID] = "bit|A or H|name[|c]" },     -- Forever's playable races, c: classic's
  names = { "Ahn'Qiraj Temple", ... },              -- zoneName, sort and dungeon are indexes into it
  zones = { [uiMap] = "continent|minLevel|maxLevel|name|quest IDs|given here, listed elsewhere" },
  dungeons = { [names index] = "minLevel|maxLevel|quest IDs" },
  npcs = { [id] = "name|map,x,y;map,x,y/map,x,y" }, objects = (the same),
  items = { [id] = "name|n<NPC>:chance,o<object>:chance" },  -- where it drops, 1/100 %: starters, objectives
  dropNpcs = { [id] = "name|map,x,y,r;..." }, dropObjects = (the same), -- drop sources' and objectives' clusters
  npcQuests = { [id] = "quests it starts|quests it ends" }, objectQuests = (the same),
  quests = { [id] = "title|level|minLevel|races|classes|zone|zoneName|sort|dungeon|pre|preAny|
                     preActive|excl|opens|breadcrumbFor|flags|skill|rep|starts|ends|
                     objectives|choice|items|money|xp|mobs" },
}
```

x, y in thousandths, r (a cluster's radius) in thousandths of the map's width; `/` separates a
place's alternatives; races a number (bit b = 2^b); quest IDs with `,`; flags: `A`/`H`
faction, `r` repeatable, `n` new in Forever, `f` from Forever's data, `s` its level scales to the
player, `e` an event's (only while its holiday is on), `g` for a group (elite, dungeon, raid); skill
`line:value`, rep `faction:min`; starts and ends `n<NPC>`, `o<object>`, `i<item>`;
objectives `k<creature>`, `o<object>`, `i<item>` with `:count` when more than one and `p` for an
item the giver hands over (`k6:10,i745p`); choice and items `item[:count]`; money in copper; xp the
experience at the quest's level; mobs `min[:max]` (`22:24`, `11`: both the same) the levels of the mobs its
objectives make you fight (The rules). Fields 21-25 are read only by `Q.Objectives` and `Q.Rewards`;
`mobs` with the quest (`Q.Quest`'s `mobMin`, `mobMax`). A zone's quests are in level order;
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
  starts, ends, source = "classic"|"forever"|"learned", new, scales, event, group, mobMin, mobMax }`
  (`scales`: its level is the player's, `level` nil; `event`: only while its holiday is on; `group`: an
  elite, dungeon or raid quest; `mobMin`, `mobMax`: its mobs' levels, nil when none is known: `Q.MobLevels`
  in the Engine reads them). The lists are always tables (maybe
  empty). `starts`/`ends`: `{ kind = "npc"|"object"|"item", id, name, points = { { map, x, y } } }`,
  one table per NPC shared by all its quests. An item's (`kind = "item"`, no points) has `drops`:
  `{ { kind = "npc"|"object", id, name, chance (0..100), points = { { map, x, y, r } } } }`, the
  likeliest first (at most 3; empty when nothing's known), `points` the source's spawn clusters
  (centre, `r` the radius as a share of the map's width; the most spawns first), shared by every item
  of that source. `zoneName`: the area's name, else the zone's, the dungeon's or the sort's. The
  title is English: the UI prefers `C_QuestLog.GetTitleForQuestID`. `races`: the mask with the race
  rule applied (Data, The rules); `Q.RaceAllowed` (Engine) reads it.
- `Q.Objectives(id)`: what the quest asks for, `{ { kind = "kill"|"item"|"object", id, name, count,
  sources = { { kind = "npc"|"object", id, name, chance (0..100, items only), points = { { map, x,
  y, r } } } }, provided } }`, empty when none (a shared empty table without data). kill: the creature
  itself with its spawn clusters; item: where it drops (the item's `drops`, shared with a starter's:
  at most 3, up to 3 clusters each), `provided` when the giver hands it over (then no sources); object:
  the object's spawn clusters. Names are the data's English ones (the UI can ask the client). The
  source tables (`kind`, `id`, `name`, `points`) are shared with the drops. Read from the quest's
  string the first time it's asked and kept until the data changes (`Q.dataGen`); a test or learned
  quest's own `objectives` list.
- `Q.Rewards(id)`: `{ choice = { { id, count } }, items = { { id, count } }, money = copper or nil, xp
  = number or nil }` or nil when nothing's known; item IDs only (names and icons: `GetItemInfo` /
  `C_Item`, async). Kept like the objectives; a test or learned quest's own `rewards`.
- `Q.Ends(id)`: where it's turned in, the quest's `ends` (`{ kind, id, name, points }`, shared; an
  empty shared table for an unknown quest).
- `Q.Zones()`: `{ map, name, continent, minLevel, maxLevel, count }` by continent, then level.
  `Q.Dungeons()`: `{ name, minLevel, maxLevel, count }` by level. `Q.ZoneQuests(map)`,
  `Q.DungeonQuests(name)`: quest IDs, the lowest level first. `Q.ZoneGiven(map)`: quests given in
  the zone that are listed elsewhere (the Deadmines' at Sentinel Hill), the lowest level first.
- `Q.Races()`: Forever's playable races, `{ { id, bit, faction, name, classic } }` by ID (the data's;
  without it the ten known when this was written); `Q.RaceInfo(id)`: one of them or nil.
- `Q.ItemQuests(item)`: the quests an item is for, `{ { id = questID, role = "objective" | "provided" |
  "starts" } }` (collected for it, handed over by its giver, starts it), objectives first, then by
  quest ID; an empty shared list for an item of no quest; nil while the index isn't made. Shared,
  never written by callers. The index is made the first time it's asked after the data is loaded,
  over the next frames (300 quests a frame at most, and no longer than 3 ms where `debugprofilestop`
  answers: the real data's 5257 quests take about 18 frames): from each quest's raw string, only
  those with an item in it (`i<digits>`), only its `starts` (field 19) and `objectives` (field 21):
  no quest is parsed. A test quest's table (`Q.SetTestData`) gives its `starts` and `objectives`.
  Quests changed by learning (`Q.AddLearned`: an item that starts one) go over the data's per
  `Q.dataGen` (the lists they change are copies). New data (another table): made again. `Q.itemGen`
  goes up when it's made. Needs the data loaded: it doesn't load it.
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
  `starts` and `ends`; an item's `drops` as given; `objectives` and `rewards` (as `Q.Objectives` and
  `Q.Rewards` answer) as given; `group`, `mobMin`, `mobMax` as given (`mobMax` defaults to `mobMin`);
  `Q.Races()` the known ten; `Q.ZoneGiven` empty.
  Learned data and caches go; the callbacks run at once. `Q.SetTestRawData(data)`: a table in the
  add-on's own format (`LefthyToolsQuestData`, strings) used as if it had just been loaded.

## Engine

- **My progress:** completed quests from `C_QuestLog.GetAllCompletedQuestIDs`, read once and kept
  until the next loading screen (`PLAYER_ENTERING_WORLD`, `PLAYER_LOGIN`); a quest turned in
  (`QUEST_TURNED_IN`) is added at once and kept until then, as the server's list may not have it
  yet. The quest log (`C_QuestLog.GetInfo`, and `C_QuestLog.IsComplete` for each: ready to turn in) is
  read again after `QUEST_ACCEPTED`/`REMOVED`/`LOG_UPDATE`. The events are registered with the first
  question (nothing runs before a window opens), and the handlers only note what changed.
  `Q.progressGen` goes up with a change of progress (a quest taken, dropped, ready, turned in), level,
  skill or reputation.
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
  those without a giver there; without a position the nearest my level first (a level that scales
  counts as mine, here and in `Q.Next` and `Q.Missing`'s best of several). Kept per data,
  progress and map; the order for the last position asked (1% steps).
- `Q.InRange(id)`: within my levels, what the windows show unless asked for all levels: a quest in
  my log; else one I can take now by its levels and that's worth doing now: its `minLevel` at most my
  level, its tier (`Q.Tier`) `easy`, `fair` or `difficult` (not grey, not red: orange stays in range,
  as hard); never an event quest (`Q.IsEvent`) that isn't in my log (its holiday may not be on: "All
  levels" shows them). A level that scales (-1, 0, `scales`) counts as mine; no level: its minimum
  level; neither (Forever's untitled hidden quests): out of range; my level not known: in range.
  Levels only: what else stands in its way is `Q.Status`'s (a red quest is still `"available"`, so is
  an event's). Quests coming up (a minimum level above mine) are out (`Q.RANGE_ABOVE` is gone).
- `Q.IsEvent(id)`: an event's quest (the data's flag `e`: a holiday's, the Darkmoon Faire's, ...).
- `Q.ForMyLevel(id)`: "for your level" as every count says it: in my log (`"active"`), or `"available"`,
  `Q.InRange` and its tier `easy` or `fair`; not a hard one (orange), a quest that needs another first
  (`"locked"`, within my levels or not), one too high, grey or red, nor an event's. `Q.IsHard(id)`:
  `"available"`, `Q.InRange` and its tier `difficult`: counted apart ("N for your level · M hard").
- `Q.LevelColor(level[, questID])` → `{ r, g, b, hex = "ffrrggbb", key }` (shared, `Q.DIFFICULTY`):
  the game's quest difficulty colours against my level. With a quest ID the client's own answer
  first (`C_PlayerInfo.GetContentDifficultyQuestForPlayer`, `Enum.RelativeContentDifficulty`);
  else by level: 5 or more above me `impossible` (red, ff1a1a), 3-4 `difficult` (orange, ff8040),
  2 below to 2 above `fair` (yellow), above classic's grey level `easy` (green), else `trivial`
  (grey; grey up to level - 5 - level/10 until 39, level - 1 - level/5 until 59, then level - 9; none
  up to level 5). No level, or -1 / 0: `fair`. `Q.Difficulty(id)`: a quest's key (the client's, else
  `fair` for a level that scales, else its level, without one its minimum level): its own level only;
  `Q.IsTrivial(id)`: grey for me (the game's grey "!" rather than the yellow one): its tier `trivial`.
- **Tiers:** `Q.Tier(id)` → how hard a quest is for me, one of the keys above: `"trivial"` (grey),
  `"easy"` (green), `"fair"` (yellow), `"difficult"` (orange), `"impossible"` (red); nil for a quest the
  data doesn't know. By its effective level: `Q.Difficulty` (the client's for a quest in my log, else its
  own level's), made harder when its mobs are (the same colour rule for `Q.MobLevels`' min; not for a
  quest that scales: its mobs do too), then a group quest (`Q.Group`) one tier harder (easy to fair,
  fair to difficult, difficult to impossible; grey stays grey). Never easier than `Q.Difficulty`. Kept
  per data and progress change (my level is progress). The words: `Q.TIER_WORD` (Lodestar.lua: Trivial,
  Easy, Fair, Hard, Too hard; German Trivial, Leicht, Passend, Schwer, Zu schwer). `Q.TierColor(tier)` →
  the colour table (`{ r, g, b, hex, key }`, shared; nil for another key; not Lodestar.lua's
  `Q.DIFFICULTY`, which has the quest log's keys). `Q.TierCode(id)` → `"|cffrrggbb"` of the quest's tier
  (yellow for an unknown quest). `Q.Group(id)`: an elite, dungeon or raid quest (the data's `g`).
  `Q.MobLevels(id)` → `min, max` of the objective mobs' levels (min: what I have to fight at least, the
  highest of the targets' lowest levels; max: the highest of any), nil when none is known.
  `Q.EffectiveLevel(id)`: the higher of its own level (one that scales: mine; none: its minimum level)
  and its mobs' min, nil without either.
- **The one order:** `Q.Compare(a, b)` → true when quest a goes before b, for `table.sort` everywhere a
  list of quests is shown: by `Q.StatusRank(id)` (1 ready to turn in, 2 in my log, 3 for my level, 4
  hard, 5 available otherwise: grey, red, an event's, no level; 6 coming up `"level"`, 7 needs another
  first `"locked"`, 8 done, 9 not for me `"other"` or unknown), then the effective level (the lowest
  first, none last), then the title (the client's, else the data's, any case), then the ID. Each
  quest's keys are kept per data and progress change: sorting a few hundred is cheap, on a change,
  never per frame. A list that is a chain's steps keeps the chain's order.
- `Q.Missing(id, who)` → `{ { id, status, reason } }`: what's missing, walked back through the chain
  across zones, the first one to do first. `reason`: `"done"` (must be completed), `"any"` (one of
  several: the best one, in the log, then available, then for me, the lowest level), `"log"` (must
  be in the quest log).
- `Q.WowheadURL(id)`: its Classic Wowhead page (the client's language: `de/` for a German one; nil
  for one new in WoW: Forever), `Q.ShowWowhead(id)` shows it to copy (`LT.Window.ShowLink`: a small
  window of ours, the link selected; Ctrl+C or Escape closes it): the details' **Wowhead** button
  (beside Map pin and Companion; greyed for a Forever quest) and the companion's quest view's last line.
- `Q.PartOf(id)`: a quest that's a **part** of another (The Warsong Reports' three updates, The Green
  Hills of Stranglethorn's chapters, Field Duty's papers: 16 in the data): taken only while the other
  is in my log (`preActive`) and giving an item the other asks for (`Q.Rewards` against its
  `Q.Objectives`); its main quest's ID. `Q.Parts(id)` a quest's parts, `Q.PartGiving(id, item)` the
  part that gives an objective's item (the details say "from the quest [21] Warsong Scout Update").
  A part isn't a step after its main quest: not in `Q.Opens`, not linked in `Q.Chain`.
- `Q.Opens(id)`: what it leads to (its parts left out). `Q.Chain(id)`: every quest connected to it (needs, opens,
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
whether a holiday is on now (an event's quest is `"available"`, out of my levels unless in my log).

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

`Modules/Lodestar/Lodestar.lua`: the module `lodestar`, shown as "Lodestar" (never translated),
on by default. Every file of the module starts with `local Q = ns.Lodestar or {}; ns.Lodestar = Q`,
so the order they load in doesn't matter for the table; `Q.module` is the module.

**Settings** (`LefthyToolsDB.settings.lodestar`, the module's defaults table is here):

| Key | Default | What |
|---|---|---|
| `keepPlace` | true | the small window opens where it was left; off: right of the middle |
| `followLog` | true | while the small window is open, a quest opened in the quest log (or clicked in the objective tracker) becomes its "Now" |
| `tooltips` | true | "Lodestar: starts ..." lines in NPC tooltips (below); the data loads a few seconds after the loading screen for them |
| `itemTooltips` | true | quest items: "Lodestar: for <quest> ..." in item tooltips, the sorted bags' mark (Quest items); the data loads for it as for `tooltips` |
| `itemTooltipsLow` | false | quest items' tooltips also list quests not taken yet that are grey for me (Quest items) |
| `friends` | true | friends' progress in the windows (`Q.Friends`) |
| `learn` | true | learning while playing (Learn.lua reads `M.db.learn`) |
| `autoHide` | true | the companion hides itself when it has nothing to show, and comes back (Small window) |
| `collapsed` | false | the companion is one line (the button left of its X does the same) |
| `stepsOpen` | false | the companion's chain steps unfolded (its "Steps (7)" line; no checkbox) |
| `smallTab` | "now" | the companion's tab: "now", "next" or "plan" (Plan without a plan shows Now; no checkbox; the quest log followed switches to Now) |
| `dialog` | true | the panel beside the quest dialog (In the game's quest UI) |
| `logBadges` | true | "2/4" on the quest log's lines, the chain in their tooltip, Alt-click to open one in Lodestar |
| `small` | `{}` | the small window's `left`, `top` (always kept; used while `keepPlace` is on; a `width`, `height` from before it fitted itself stays unused) |

The settings page: Open the small window, Open the quest browser (`Q.ToggleBrowser`, or a chat line
when Browser.lua isn't there), the checkboxes under Window (with `autoHide` and `collapsed`), "In the
game's quest UI" (`dialog`, `logBadges`), Tooltips (`tooltips`, `itemTooltips`), Friends and Learning.

**The minimap button** (a star; click: the quest browser, right-click: the companion): its tooltip says
"Elwynn Forest: 3 to pick up" once the data is loaded (a hover never loads it): `Q.Available` in my zone
within my levels (`Q.InRange`: not grey, red or an event's).

**Commands:** `/lodestar` opens or closes the small window (on "Now"), `/lodestar <name or ID>`
shows a quest (a quest link works too), `/lodestar browse` the quest browser, `/lodestar settings`,
`/lodestar help`. `/lefthy lodestar ...` is the same. Switched off, each says so (settings and
help still work). Chat lines are English.

**Finding a quest by name** (`Q.Find(text)`): a number or a quest link is that quest; otherwise
`Q.Search(text)`'s quests ranked by: the title (the client's or the data's) is the text, starts
with it, or only contains it (or the giver's name does); then my status (in my log, ready to take,
needs one first, level too low, done, not for me); then nearest my level; then the lower ID. When
several match, chat says how many and which is shown.

**What the files share** (Lodestar.lua):

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
- `Q.LogObjectives(id)` → `{ { text, name, have, need, done, kind, data } }`: a quest of my log's
  objectives (`C_QuestLog.GetQuestObjectives`, secret texts left out; `{}` when it isn't in my log),
  `name` the text without its count (the game's own formats `QUEST_MONSTERS_KILLED`,
  `QUEST_ITEMS_NEEDED`, `QUEST_OBJECTS_FOUND` made into patterns, positional ones too, so "Defias
  Bandit slain: 3/10" is "Defias Bandit" on any client; else the "3/10" cut off), `have`/`need` the
  client's numbers (else the text's), `data` what the data knows of it (`Q.Objectives`, Data.lua): the
  n-th objective of a kind (`monster` kill, `item`, `object`) is the data's n-th of that kind, else the
  one whose name is in the text, else the same place when both have as many.
- `Q.ObjectiveSpot(id, map, x, y)` → point, objective: where to go for a quest: of its objectives not
  done (my log's; a quest not in it: the data's), the area (`sources[].points`) nearest my spot on that
  map, else the first area known; nil when none is.

**NPC tooltips** (setting `tooltips`): a `TooltipDataProcessor` post-call on `Unit` tooltips, as
Chronicle's "Craftable by" and Questie's: `GameTooltip` only (not forbidden), the primary data block
only (an appended one isn't the unit pointed at), nothing in an instance (the data is secret there),
nothing for a secret GUID; the NPC from `data.guid` (`LT.CreatureOf`). Lines: "Lodestar: ends
[12] <title>" for a quest in my log it takes back, "Lodestar: starts [12] <title> (step 2 of 5)" for
one I can take, "Lodestar: starts [14] <title> at level 12" in grey for one my level is too low for
(the level and title in the quest's difficulty colour, `Q.LevelTitle`), at most 4,
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
opens the quest in Lodestar on the next frame (In the game's quest UI). Blizzard's own click is
untouched: Alt is a modifier its title buttons don't use (Shift tracks or links, a right click opens its
menu), so the details open as with any left click. Not done, and why: a "Show in Lodestar" button in
the quest details (the quest log is part of `WorldMapFrame`: a button of ours in it becomes part of that
panel for SmartNavigation, whose focus and confirm then run our scripts from Blizzard's code, the taint
chain in forever-platform.md; a button over it parented to UIParent wouldn't be reachable with a
controller), and a tracker-only Alt-click (an Alt-click on a tracker line opens the details too, so
the hook sees it the same way; nothing of the tracker is hooked).

Never lags: nothing is loaded, registered or run at login, except the tooltips' one load a few
seconds after it (setting `tooltips` or `itemTooltips`; a second later the NPC index and, for
`itemTooltips`, the start of the item index); the windows load the data when they open.

## Small window

`Modules/Lodestar/Small.lua`: `Q.ToggleSmall()`, `Q.ShowQuest(id)`, `Q.RedrawSmall(now)` (a
redraw 0.3 s later, several at once: one; `now`: at once; for other parts whose data changed, e.g.
friends' progress arriving), `Q.IsSmallShown()`, `Q.SmallFollow(id)` (the quest log's hook),
`Q.SmallFrame()` (tests: also `planMap`, `planMarks`, `planLines`, `tabs` (the tabs' buttons by
key), `tab` (the tab drawn; nil while a quest is looked at)).

The companion: it follows what you're doing without being asked. A slim dark frame of its own, the
Bestiary's small window's look (`LT.Window.Dress`, shared with the Bestiary: no title bar, no inset,
no scroll bar), 260 px wide and as tall as what it shows. Along its top **small tabs** (our own
Buttons: a word each, the one shown gold with a gold line under it, the others grey; tooltips say
what each holds; a thin gold rule under the row): **Now**, **Next** and **Plan** (only while the
plan has a stop not done). At the top right, right to left: a small X (`UIPanelCloseButtonNoScripts`,
24 px, like the Bestiary's), **one line** (`QuestLog-icon-shrink` / `QuestLog-icon-Expand`, setting
`collapsed`) and **the big window** (Lodestar's star, `Spell_Arcane_StarFire` as on the minimap:
`Q.OpenBrowser` on the quest looked at or Now's, else `Q.ToggleBrowser()`; hidden without Browser.lua,
the data, or in one line). The tab picked is kept (setting `smallTab`: "now", "next" or "plan"; Plan
kept without a plan shows Now, and comes back with the next plan). Each tab fits without scrolling:
its lists stop at a few lines with **"and N more"** (a Button: the big window, `Q.OpenBrowser` on the
first left out; the plan's: the big window's Plan tab, `Q.ShowBrowserView("plan")`). Two modes: **a
tab** (what `/lodestar` opens) and **a quest looked at** (a click on any quest, `/lodestar <name>`,
`Q.ShowQuest`, the big window's clicks): it takes the tab's place, the tabs stay (none lit), a click
on one goes back to its lines.

Each tab shows only what to do now and how far along (the guides' "this now, then those"); what's
secondary is in the lines' tooltips or behind a click.

- **Plan** (the tab only while the plan, below, has a stop not done): **"Stop 2 of 14: Pick up
  Wanted: Hogger at Marshal Dughan"** (`Q.PlanNext`, `Q.PlanStopText`) with how far and which way when
  it's on my zone's map (`Q.TowardText`), else that zone's name; a click shows the stop on the big
  window's map (`Q.ShowOnMap(quest, spot)`; without it `Q.OpenBrowser`), Shift-click the game's map pin
  there (in chat too). Beside it **Skip** (`Q.PlanSkip`: done for now, until the next /reload or
  logout; the next one comes up). Under it the plan's **own small map** (a second `Q.NewMiniMap`, made
  the first time): the next stop's zone with the next stops on it (up to five, the plan's numbers, the
  next one a gold disc, the others dark with gold numbers) joined by a gold line in their order; a
  number is a Button (its tooltip "4. Pick up ...", a click `Q.ShowOnMap` of that stop). The numbers and
  lines are a layer of ours over the map's art (`m.Map`), laid again when the art is (its
  `OnSizeChanged`: zooming). Under the map **the next stops** (up to four not done after it, any zone):
  "4. Turn in ... at ..." numbered as on the map (the stop's index in `Q.PlanStops()`), what it is in
  front (the gossip "!" to pick up, "?" to turn in, a dot for an objective, as on the map), how far
  and which way (another zone: its name); a click as the first line's; then "and N more" (the big
  window's Plan tab). Redrawn when the plan changes (`Q.OnPlanChanged`) and with the companion's own
  redraws; it keeps the companion from hiding itself (`autoHide`).

- **Now** (the tab): the quest I'm on is the last one I
  did something with while the window was open (accepted: `QUEST_ACCEPTED`; super-tracked:
  `SUPER_TRACKING_CHANGED`; opened in the quest log: the hook, also while closed) while it's in my
  log; a quest super-tracked since I last looked counts as new; else the super-tracked quest, else
  the first on the tracker (`C_QuestLog.GetQuestIDForQuestWatchIndex`), else one of my log in this
  zone (its zone or its turn-in here), else the first of my log; none: "No quest in your log: Next
  has what to pick up." Then: "[18] Title" in its difficulty colour (large; why that quest at its
  right, grey: "just accepted", "tracked", "opened in your quest log", "on your tracker", "in this
  zone", "in your quest log"; a click shows everything about it; its tooltip says what it leads to: "Leads to: [19] Title - giver, zone", `Q.Opens`, "+N more"),
  "Step 3 of 7 · <first quest>" and a green bar (the chain is `Q.Chain` without the quests not for
  me), friends on one line only when there are any ("Friends: 2 of 5 done" with a dot in the class
  colour of each who did it; its tooltip names each with their status; setting `friends`), its
  objectives (`Q.LogObjectives`, at most 6, done ones ticked; one not done whose areas the data knows
  is a line that lights its areas on the small map while hovered, says how far the nearest is, has
  "Where: Young Wolf (40%), ..." in its tooltip and sets the map pin at the nearest on a click) or, when it's complete
  (`C_QuestLog.IsComplete`), "Ready to turn in" instead, **Turn-in:** on one line (name, zone, how far
  and which way when it's in my zone; a click sets the map pin), and **"Steps (7)"**: a line (a plus or
  minus icon) that unfolds and folds the chain's steps, folded at first, kept in the setting
  `stepsOpen`; unfolded, the steps around this one (from two before, at most 6, "... N before/more"):
  done ones ticked in green, this one bold with an arrow, the rest numbered in grey; a click shows
  that step.
- **The small map** (Now's, under its lines): not ready, with areas known for its objectives not done (`Q.Objectives`' points,
  Questie's and pfQuest's objective areas): those areas as soft gold circles (each objective a group of
  its own), on my zone when one is there, else the nearest's zone, and no turn-in; else the turn-in's
  zone (my zone when the turn-in is in it, else the first turn-in's), else my zone: the turn-in ("?"
  yellow when ready, the in-progress icon when not). Then the turn-ins of my other quests and the givers
  of what I can pick up on that map, and my arrow.
- **Next** (the tab; "Pick up next": a grey line with my zone and its count, `Q.ZoneCount`:
  "Elwynn Forest · 12 of 40 done"), in two groups like Quest Herald's (each quest a row: icon, "[level] Title" in its difficulty
  tier's colour, `Q.TierCode`, a grey second line, how far and which way at the right). Each group is in
  the one order of quests, `Q.Compare` (round 6, the player asked for level order: ready first, then for
  my level before hard ones, each by level, then title); how far the giver is stays on the line, it no
  longer orders it.
  - *In progress*: my other quests (at most 3, then "and N more"): "ready to turn in · <ender>" or "in
    your log · <ender>".
  - *Available now*, only quests for my levels (`Q.InRange`: my level reached, easy, fair or difficult):
    follow-ups of the quest I just turned in (while the window was open), `Q.Next()`'s that I can take
    ("after <the quest it follows>") and the zone's (`Q.AvailableIn`), all of them in the one order, the
    first 3 shown, "and N more" for the rest; the second line: the giver (and their
    zone when it's another) and its step in its chain. A hard one (`Q.IsHard`: orange) comes after the
    ones for my level and its second line starts with "Hard" in orange (", mobs up to 23" when its
    objectives' mobs, `Q.MobLevels`, are above its level), its tooltip too; its giver's marker on the
    small map is the game's "!" on an orange ring. What Now leads to isn't listed again.
  None at all: "Nothing to pick up nearby. The quest browser has every zone." What's coming up later
  (level too low) or blocked (needs another first) isn't here: the big window has it.

  **How a line looks** (the guides' step lists: this now, then those): a verb icon first (`Q.Icon`,
  the game's own: `QuestTurnin` "?" for one ready to turn in, `SideInProgressquesticon` for one in
  progress, `QuestNormal` "!" to pick up, `QuestDaily` repeatable). The first line of Next is
  full size (`GameFontHighlight`, a 16 px icon, the title in its tier's colour): what to do now;
  the rest are smaller (13 px) with only "[level]" in its colour and the title grey (`bebebe`). The
  second line of Available now also says what taking it closes ("closes <title>" in orange,
  `Q.Closes`: its exclusive quests, at most 2 named; the tooltip: "Taking it closes: ... Only one of
  them can be done."); what a quest opens isn't on the line. Groups have small gold headings (no
  section rules: the tab says what it is). Done steps are ticked with
  `UI-QuestTracker-Tracker-Check` in the research's green.

  **Status words say the real reason** (a quest looked at, its lists, the tooltips): a quest "other"
  for me that another closed (`Q.WhyOther` "closed") is "Skipped", with "You took <title> instead"
  (for a lead-in: "No longer needed: you have <title>"); not for my race, class or side "Not for your
  race" / "class" / "faction"; a profession I don't have "Needs <profession>"; a locked one blocked by
  a reputation or a profession's rank (`Q.Needs`) "Needs Friendly with Stormwind" / "Needs Alchemy
  100" (the game's names: `FACTION_STANDING_LABEL<n>`, `C_Reputation`, `C_TradeSkillUI`; else
  English ones, as the big window's), by a quest "Needs <the first of `Q.Missing`>". After a quest's
  name the same with a small first letter ("needs Start"). The other statuses keep their words.

**One line** (setting `collapsed`, or the button left of the X, `QuestLog-icon-shrink` /
`QuestLog-icon-Expand`): the window shrinks to a line beside its X and that button (28 px high; the
tabs, the lines and the big window's star hidden): the quest I'm on with its verb icon, "[18] Title · 3/7" (`Q.ChainFor`) and how far its turn-in is,
else the first thing to pick up with how far its giver is, else "Nothing to pick up nearby."; a quest
looked at: that quest. A click on the line (or the button again) shows the whole companion, as tall
as its tab. It follows the same events as the whole window.

**Hiding itself** (setting `autoHide`): when a redraw after an event finds nothing to show (no quest
I'm on, nothing in Next, no stop of the plan: any tab's, not only the one shown), the companion hides; while hidden like that it listens only to
`QUEST_ACCEPTED`, `SUPER_TRACKING_CHANGED`, `PLAYER_LEVEL_UP` and `ZONE_CHANGED_NEW_AREA` (rare), and
0.3 s after one of them it opens again where it was if there's something now. Opened by me
(`/lodestar`, a quest shown, a tab clicked) it never hides itself in that draw: "No quest in your
log" / "Nothing to pick up nearby" stays. Closed by me (its X, `/lodestar`) it stays closed and listens to nothing. Switching the
setting off while it's hidden brings it back.

**A quest looked at**: at the top "« Back to now" or, after clicking from one quest to another,
"« Back to <the quest before>" (up to 20 back) and "Back to now" side by side. Then its "[level]
Title", its step in its chain and bar, a grey line (level, zone, dungeon, repeatable, new in WoW:
Forever), my status with its real reason ("Your level is too low: from level 30", "Ready to turn in",
"Skipped" and under it "You took <title> instead", "Needs Friendly with Stormwind"), **Requires:** (what it needs
first from other chains, by their names), **Needs first:** (`Q.Missing`, numbered, the one to do
first at the top; at most 5, "and N more": the big window on it), **Quest giver:** and **Turn-in:** (name, zone, how far;
an item or object says so, "+2 more"; not known: says so), for an item that starts it **Drops
from:** "Defias Pillager (12%), ..." (the item's `drops`), the **small map** (the giver's zone, the
turn-in's for a quest in my log, where the item drops for a quest that only an item starts, unless a
line picked one; every giver, turn-in and drop spot on it, a person in several places: the spot on
my map, else the first), **Leads to:** (`Q.Opens`, at most 5 as Needs first), **"Steps (7)"** (folded or not as in Now) and
**Friends:**. Each quest line is a button showing that quest (its tooltip: the title, the status and
its reason, "Click: show this quest"); a giver's or turn-in's line puts its side on the map and sets the game's map pin at
its spot nearest me (`Q.Waypoint`; Shift-click: its link in chat too).

The data add-on missing: the window says so (run the updater, restart), nothing else. A quest the
data doesn't know: its title and that line.

**What it costs.** The window: a frame of our own (`LefthyToolsLodestarSmall`, `CreateFrame` on
`UIParent`, not `LT.Window.Create`), like the Bestiary's small window: not in `UISpecialFrames`, so
Escape doesn't close it, and not `LT.Window.Register`ed, so it doesn't count as an open window for
Mirage, the AFK screen and flights; its X, the binding or `/lodestar` close it. MEDIUM strata with the
game's panels (as the Bestiary's), toplevel and raised whenever it opens or shows a quest; opened
while the big window (DIALOG) is open (`Q.BrowserShown`), DIALOG, so a quest clicked there shows above
it (MEDIUM again the next time it opens without it). Movable by dragging (an empty spot of it), its
top left corner saved on every drag (`small.left`, `small.top`; it grows down from there); at first
(or with `keepPlace` off) its top left right of the screen's middle. No resizing: 260 px wide, as tall
as the tab row (30 px), the tab's lines and an 8 px edge, at most 640 px (less on a small screen: its
height less 60); the lines are in a plain frame that clips its children, so what doesn't fit is cut
at its edge, never past it. A `small.width` / `small.height` kept from before it fitted itself stays
unused. Built the first time it opens; rows and texts are pooled. While
shown it listens to `QUEST_ACCEPTED`, `QUEST_TURNED_IN`, `QUEST_REMOVED`, `QUEST_LOG_UPDATE`,
`QUEST_WATCH_LIST_CHANGED`, `SUPER_TRACKING_CHANGED`, `PLAYER_LEVEL_UP`, `ZONE_CHANGED`,
`ZONE_CHANGED_INDOORS`, `ZONE_CHANGED_NEW_AREA` (and `Q.OnDataChanged`); the handlers note what
happened and redraw 0.3 s later. A child frame looks every 2 s whether I moved (2% of the map, or
another zone) and redraws then (the distances). Hidden: no events, no OnUpdate. Nothing protected:
it opens and works in a fight.

**Controller:** every line that does something, the map's markers, the tabs, the X and the two
buttons beside it are buttons of ours, so SmartNavigation's cursor reaches them (its focus runs OnEnter: the tooltips
show; its button clicks: a quest shows, a marker sets the pin). Nothing of Blizzard's is set on our
frames, no Blizzard menu, no panel opening.

**Small map** (`Modules/Lodestar/MiniMap.lua`, also for the big window):
`local m = Q.NewMiniMap(parent[, width, height])` (240 x 160 by default), `m.frame`,
`m:Show(map, points[, name])` with `points = { { x, y, kind, label [, note, look, grey, chance,
radius, group, hard] } }` (0..1 on that map), `m:SetSize(w, h)`, `m:Hide()`, `m:ShowPlayer(on)`,
`m:Zoom(factor[, x, y])`, `m:Light(group)`, `m:Markers()` (tests).

- The zone's art and what you've explored of it (`LT.MapArt`: the art tiles of
  `C_Map.GetMapArtLayerTextures` and the explored overlays of `C_MapExplorationInfo`, as Attune's
  detail map and the fight stream's), as large as fits, on a dark box that clips it; the zone's name
  on a strip over its top, "wheel: zoom" / "right-click: whole zone" at its right.
- Markers: the game's own map icons, solid (full alpha), 22 px on a dark copy of themselves (an
  outline that reads on any ground): `kind` "start" a giver, "end" a turn-in, "drop" where an item
  drops. `look`: "available" (`QuestNormal`, yellow !), "repeatable" (`QuestDaily`), "trivial" (the !
  paler), "locked" (the ! grey), "turnin" (`QuestTurnin`), "repeatturnin" (`QuestRepeatableTurnin`),
  "progress" (`SideInProgressquesticon`); without `look` a start is "available", an end "turnin",
  `grey` makes them "locked" / "progress"; `hard` (a hard quest's giver) makes the dark outline an orange
  ring (`ff8040`, 95%), the icon stays the game's. The atlas missing: the gossip window's icon. A drop: a
  soft orange spot (`Spells\GenericGlow64` added) at least 34 px, as big as its `radius` (0..1 of the
  map's width, at most 140 px); the likeliest (`chance`) says "drops here (12%)" beside it. An
  objective's area (`kind` "area"): a soft blue circle (the game's quest areas' blue) the same way (70%, no dot) over a plain blue
  disc 0.7 of its size (`Fill`, 30%: the glow alone, drawn added, all but vanished on light ground),
  `group` the objective it belongs to; `m:Light(group)` lights that objective's areas (full, the fill
  45%) and dims the others' (20%, the fill 8%), `m:Light()` puts them back (only alphas; kept when the map is laid again, gone with another
  map).
- Points within 8 px share one marker (drops only with drops, an objective's areas only with the
  same objective's), its tooltip naming each with what it is and its `note` (the quest, or the
  objective); at most 40; points off the map are left out. Drops and areas are under the icons. A click
  sets the game's map pin at the marker (`Q.Waypoint`), Shift-click puts it in chat too.
- The mouse wheel zooms by 1.35 a step around the cursor (1 to 8 times), dragging moves the zoomed
  map (an OnUpdate only while the button is held), a right-click shows the whole zone again; another
  map starts whole.
- My arrow (`Interface\Minimap\MinimapArrow`, turned by `GetPlayerFacing`) where I am when I'm on that
  map (`Q.PlayerAt`), moved ten times a second by an OnUpdate on a frame of the map (hidden: it
  doesn't run); `m:ShowPlayer(false)` leaves it out.
- No art: "No map of this zone" with the markers on the dark box. Laid only when the map, the size
  or the zoom changes (or you've explored more); never touches `WorldMapFrame`.

**Tests** (`tests/lodestar_small.lua`): the module, settings and commands; difficulty colours;
the lines' verb icons, the first full size and the rest grey, no "opens", exclusive quests closing each
other, Available now only for my levels and at most three in the one order (by level, then title), a hard
one after them (orange, "Hard, mobs up to 22", its tooltip, its giver's orange ring on the small map),
nothing for later, one line (the button,
the line's click, the setting), hiding itself and coming back and staying closed when I closed it,
Alt-click in the quest log (through the hook); the status words (skipped and by which, not for my
class or side, a profession missing or too low, a reputation, the quest first; as a word after a
name);
Now (why that quest, its step and bar, objectives, turn-in, what it leads to in the title's
tooltip, the steps folded and unfolded and kept, the map and its markers) and Next (the two
groups, by level with distance and direction, the zone's count, "and N more" opening the big window);
the frame (no title bar, inset, scroll frame or grip, 260 wide, MEDIUM, the small X; as tall as its
lines, cut at a small screen's height; DIALOG and raised while the big window is open), the tabs
(Now and Next, Plan only with a plan, lit, kept over a close, a click leaving a quest looked at; the
quest log's hook switching to Now);
following super tracking, the quest log's hook and its setting, accepting and turning in (the
follow-up in the one order, saying what it follows); a quest looked at ("« Back to", "Back to now", an item's drops and their map, too
low, done); the map pin from a giver's line and a marker (Shift: chat); friends' dots and their
setting; an unknown quest, the data missing, the search, the browser command; the NPC tooltip lines
(giver, turn-in, too low, done, kept, other frames, instance, setting, data not loaded); events only
while shown, moving; its place kept (an old size kept harmless) and the setting off; a fight; buttons for the controller;
without the data part's new calls; switched off; the small map alone (icons, one marker for one
spot, the arrow, zoom, objective areas by radius and objective, lit and dimmed); Now's objective
areas (not the done one's, not the turn-in; its line lights them, says where, pins the nearest); the plan
(no Plan tab without one, its tab after Next with how far, its own map with the stops numbered and joined
where the art is, also zoomed, the next stops listed under it (numbered, ! or ?, how far, a click), "and N
more" opening the big window's Plan tab, a click and a number on the map going to the big window's map,
Shift-click the pin, Skip, another zone's stop, the tab gone when cleared (Now shown, Plan kept and back
with the next plan); `Q.ShowOnMap` and `Q.ShowBrowserView` record).
Data.lua's `Q.ChainStep`, `Q.Available`, `Q.LevelColor`, `Q.ZoneCount` and
`Q.GiverQuests` get stand-ins only while they're missing, round 6's contract (`Q.Tier`, `Q.Compare` and
the rest, as in the views' tests) while `Q.Tier` and `Q.Compare` are, `Q.Objectives` while Now's areas are
checked; the mock's map pin API and the quest log's
`QuestMapFrame_ShowQuestDetails` are made for it and put back at its end.

## In the game's quest UI (Dialog.lua)

Lodestar where players already look: the quest dialog and the quest log. Built from established
add-ons' ways (BtWQuests and QuestWeaver open from the quest log, Wowhead's numbered "Series" box with
the current quest bold), with our own frames and post-hooks only.

### Beside the quest dialog (setting `dialog`)

When an NPC offers a quest (`QUEST_DETAIL`), asks for it (`QUEST_PROGRESS`), rewards it
(`QUEST_COMPLETE`) or lists several (`QUEST_GREETING`), a panel of ours (`LefthyToolsLodestarDialog`,
250 px wide, a dark background with a thin gold edge) sits right of `QuestFrame`, its top at the
dialog's top:

- **"Part 2 of 4 · <chain>"** (gold, `GameFontNormal`): the quest's place in `Q.ChainFor` and the
  chain's first quest's title (the client's when it knows it).
- **The level line**: "Level 23 (from 18) · Hard, mobs up to 26 · 1,400 XP" in the quest's difficulty
  tier's colour (`Q.TierCode`; a quest that scales "Your level"): "Hard" (orange) or "Too hard" (red) when
  its tier (`Q.Tier`) is difficult or impossible, "mobs up to 26" when its objectives' mobs
  (`Q.MobLevels`) are above its level, "a group quest" for one (`Q.Group`); a grey, green or yellow one
  only its colour. Under the chain's heading, or under the title of a quest in no chain.
- **The steps**, numbered, in a window of four: one before this one, this one, two after (fewer
  before it at the chain's start, more at its end), "... N before" and "... N more" for the rest;
  done ones ticked green, this one bold (`GameFontHighlight`) with an arrow, the rest grey; each a
  line that opens that quest in Lodestar.
- **Leads to: [7] Title** when it opens one quest that isn't one of the steps listed (the next step
  usually is); when it opens several, **Opens 3 quests** alone (their names in the line's tooltip; a
  click opens this quest in Lodestar, where they're listed).
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
- **Open in Lodestar** (a button at the bottom): `Q.OpenBrowser(id)`, else `Q.ShowQuest(id)`.

The greeting lists each of the NPC's quests the data knows (at most 8), in the one order of quests
(`Q.Compare`: ready, in my log, for my level, hard, the rest, each by level; not the NPC's order): "[12]
Title" in its tier's colour with its verb icon and "Part 2 of 4 · <chain>" (or "opens N") under it, a
hard one's line starting "Hard" (or "Too hard"), a click opens it; no button. Nothing to tell
(no chain of two or more, nothing it leads to or closes, no lead-in, no friends): no panel at all.

**Events and cost.** The five events (`QUEST_FINISHED` too) are listened to while Lodestar and the
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
  is never changed. The hook is made a second after Lodestar is switched on, so it runs after Misc
  Tweaks' and knows where its label is. Each "2/4" is kept per data and progress change: a redraw of
  the log is a table lookup per line. Data not loaded yet: loaded once on the next frame, out of a
  fight, then the open log is marked.
- **The tooltip**: one `HookScript("OnEnter")` per title button (as Misc Tweaks'): when the game's
  tooltip is the line's, it adds "Lodestar: Part 2 of 4 · <chain>", at most 5 steps from one before
  this one, windowed as the panel's ("... N before", "... N more"; this one white with the arrow, done
  ones ticked green, the rest grey), "Leads to: ..." and "Alt-click: open it in Lodestar".
- **Alt-click** a quest there: Lodestar.lua's post-hook on `QuestMapFrame_ShowQuestDetails` (Module,
  The quest log) calls `Q.LogAltClick(id)`, which opens it on the next frame (`Q.OpenBrowser`, else
  `Q.ShowQuest`) from a timer of ours, not inside Blizzard's click. A click on the "2/4" itself would
  need a frame of ours (a Button) inside the quest log, which is part of `WorldMapFrame`: SmartNavigation
  would take it into the map's panel and run its scripts from its own code, the gamepad taint in
  forever-platform.md. So the badge is a font string (no mouse), its tooltip is the line's, and the
  click is the line's with Alt. Without a keyboard (gamepad mode) there's no Alt: the tooltip and the
  companion's following of the quest log are the way there.
- The setting off: the open log loses its "2/4" at once, the tooltip lines and Alt-click stop.

`Q.DialogView()` gives the tests the panel, its strings, the quest shown, the page and the labels.

**Tests** (`tests/lodestar_dialog.lua`; round 6's contract as in the views' tests): nothing built before a
dialog; the level line (three levels above me orange "Hard"; a grey one only its colour; too hard, its
mobs higher, a group quest); the greeting in the one order with the hard one marked; the offered page drawn on the
next frame, not in the event (heading, the steps' window with done ticked and this one bold and "... 2
more", what it leads to when it isn't listed, a need that's a step listed not said again, what taking
it closes, the button and a step's line opening Lodestar); a frame of ours on UIParent anchored beside
the dialog, nothing written into `QuestFrame` or its scripts; closed by `QUEST_FINISHED` and without it;
a quest with nothing to tell; a lead-in; the progress and reward pages (the chain without the quest
taking it closed; what it leads to listed as the next step); two it opens (the count, the names in its
tooltip) and a need far down the chain (Requires); friends (who did it or is on it, three, "+1"; asked
for once); a greeting; the setting off; the data not loaded in a fight. The quest log: "2/5" on a chain
quest's line (the title unchanged), nothing on one in no chain, left of Misc Tweaks' NEW, kept until
progress changes, the tooltip (a long chain: five steps from one before), Alt-click on the next frame,
the setting off and on again.

## Quest items (Items.lua)

Which quests an item in your bags is for and where they stand, so you know what to keep and what to
discard (setting `itemTooltips`).

**Item tooltips**: a `TooltipDataProcessor` post-call on `Item` tooltips, as Chronicle's "Craftable
by": `GameTooltip` and `ItemRefTooltip` (chat links) only, not forbidden ones; so bags, the bank, loot,
vendors, chat links (not the comparison tooltips). Nothing for a secret item ID or data. Lines, for
each quest of `Q.ItemQuests(item)` with my status (`Q.Status`):

- collected for it (or handed over by its giver): "Lodestar: for <title> · in your log (3/8)" (my
  progress: the quest log's objective the data names, `Q.LogObjectives`, else the one with the item's
  name), "· ready to turn in" (`C_QuestLog.IsComplete`), "· not taken yet: you can take it" / "...: from
  level 40" / "...: needs another quest first", "· done", "· skipped" (`Q.WhyOther` "closed": an
  exclusive one taken), "· not for you";
- an item that starts it: "Lodestar: starts the quest <title> · you can start it" / "· in your log" /
  "· from level 30" / "· needs another quest first" / "· already done: you can discard it";
- a quest not taken yet (I can take it, from level N, needs another first) has its level before its
  title: "Lodestar: for [24] <title> · not taken yet: you can take it" (its own level, none for one that
  scales); such a quest that's grey for me (`Q.Tier` "trivial") is left out unless `itemTooltipsLow`
  is on (the lines' cache key has the setting);
- the quests that still need it first, then the rest, each by status (ready, in my log, to take, coming
  up, blocked, done) and then in the one order of quests (`Q.Compare`: for my level, hard, ...; by level
  and title; a quest of my log the data doesn't have after those it has, by its ID), at most 4, then
  "Lodestar: and N more";
- last: "No quest needs it any more: you can discard it" (green-grey) when none does (not under a
  single starter's line, which says it already), "Only low-level quests need it: you can discard it"
  when only left-out grey ones do, or "Still needed for <title> [and N more]" when only some do.
  (`Q.ItemDone` and the bags' mark don't change with it: they count every quest.)

A quest needs the item unless it's done or "other" (skipped, not for me); one it starts also not
when it's in my log. Quests the data doesn't have with the item (Forever's own quests EG Link hasn't
described): a quest of my log whose objective names it, by the item's name from the client
(`C_Item.GetItemInfo`, so in the client's language: "Leinenstoffbündel: 1/4" matches on a German
client), its name exactly or inside the objective's text: "Lodestar: for <title> · in your log (1/4)".
An item the client hasn't loaded yet gets those on a later hover.

**Cost**: only once the quest data is loaded (Module, NPC tooltips: a few seconds after the loading
screen, the item index started a second later); a hover never loads it. An item's lines are made the
first time it's hovered and kept until `Q.dataGen`, `Q.progressGen`, `Q.itemGen` or the quest log
changes (`QUEST_LOG_UPDATE`, `QUEST_ACCEPTED`, `QUEST_REMOVED`, `QUEST_TURNED_IN`, only counted, and
only while the setting is on): a hover is a table lookup. While the index is being made (the first
frames), nothing, and nothing kept. The quest log's item objectives are read once per change, for
all items.

**`Q.ItemDone(item)`**: true when the data ties the item to quests and none needs it any more (as
above: each done, skipped or not for me, and nothing it starts I can still take); false when one
does; nil for an item of no quest the data knows, or before the data or its index is there. Kept per
data, progress and quest log change. `Q.ItemMarked(item)`: the same with Lodestar and `itemTooltips`
on (false otherwise).

**The sorted bags** (Misc Tweaks' `gamepadBags`/`mouseBags`, GamepadBags.lua): an item of the quest
items section with `Q.ItemMarked` gets a small dim red x (`Interface\RaidFrame\ReadyCheck-NotReady`,
14 px, 75%) in its top left corner, a texture of ours on Blizzard's item button (as Beacon's reserved
border, kept in a table of ours, nothing written into the button), at `OVERLAY` 7. Only there: a trade
good that was some done quest's objective (Linen Cloth) is still worth keeping. Set with each layout
and each sort that keeps the order (an item moved, a quest done meanwhile); hidden when ours goes. The
top left corner is free on a quest item (Blizzard's junk coin and upgrade arrow are for grey items and
gear). Nothing taints: a texture on the button isn't protected and no Blizzard code reads it.

**Tests** (`tests/lodestar_items.lua`; round 6's contract as in the views' tests): the index (nil at the first question, made on the next frame;
objectives, the giver's items, starters; an item of no quest; shared lists; a learned quest's item on
top; the real data over 17 frames or more, Hogger's claw, Furlbrow's Deed); each tooltip line (in my
log with progress, ready, done and skipped: discard, a starter's three, many quests in the one order:
four and "and 1 more", "Still needed for ..."); quests of my log by the item's name, a German one; kept until the log
or progress changes; ItemRefTooltip, another tooltip, a secret ID, the setting; nothing before the data
is loaded and no load; `Q.ItemDone`; the bags' mark (marked, not marked, moved with its item, the
setting off).

## Big window (Browser.lua)

`Q.ToggleBrowser()` opens or closes it; `Q.OpenBrowser()` opens it as it was, `Q.OpenBrowser(id)` is
`Q.ShowOnMap(id)`; `Q.ShowOnMap(id[, spot])` opens it on a quest (its zone or dungeon on the left, on the
Zone tab its zone's map with the quest picked on it, found and pulsing, a dungeon's quest list, its details
on the right; a spot `{ map, x, y[, r] }`: zoomed in to that spot; true when it's shown: **Finding a quest
on the map**, below); `Q.ShowDetails(id)` opens it on the tab it shows with the quest picked, its details
on the right (no other tab, the map not moved; true when shown); `Q.SelectZone(map)` opens it on a zone's page (a
uiMapID, a city's floor or a cave counting as its zone, or a dungeon's name; nothing picked, its
briefing on the right; false when there's no such place); `Q.OpenChain(id)` opens it on a quest's chain
(the quest's zone on the Zone tab, the quest picked, its chain in the middle with its card in sight: what a
chain badge does, My quests' too; a quest in no chain opens as `Q.OpenBrowser(id)`; true when its chain
shows); `Q.HideBrowser()` closes it (the module switched off); `Q.BrowserShown()` says whether it's open. Other files add tabs with
`Q.RegisterBrowserView` and open them with `Q.ShowBrowserView` (below). With the module off it doesn't
open (one chat line says how to switch it on). `Q.BrowserView()` gives the tests its frames, state and
views.

The look follows what players know from the quest add-ons researched for it (BtWQuests' and
ForeverQuestChain's cards, BeautifulAttune's flat cards and lines, EQ's gutters and hover lighting,
pfQuest's colour per quest and its spawn areas, Questie's map highlight and objective glow, map add-ons'
zoom where the cursor is, Blizzard's map icons and story headers), built from our own frames. Each
surface shows at a glance what to do now and how far along (Guidelime's and BtWQuests' "this now, then
those"); the rest is in tooltips or behind a click. By default it shows what's within my levels (the
filters, below).

**Status words** (`Rule.Reason`) always say the real reason, everywhere (tooltips, the quest list, the
details, the pins): "Completed", "In your quest log" ("Ready to turn in" in the details when it's done),
"Available"; level too low: "Needs level 12"; locked: "Needs Friendly with Stormwind" / "Needs
Leatherworking 50" (`Q.Needs`: a reputation or a profession's rank), else "Needs <the first of
`Q.Missing`>"; not for me (`Q.WhyOther`): "Not for your race" / "class" / "faction", "Needs <profession>"
(one I don't have), and "Skipped" for one closed by another (an exclusive one I took, or a lead-in whose
quest I have): its tooltip says "You took <title> instead" / "No longer needed: you have <title>". A
skipped quest is grouped with the done ones and shown in its chain, not with "not for you". Friends'
statuses keep the plain words. Without `Q.WhyOther`, every "other" is "Not for you".

**Size.** Worked out when it's built (`Make.Size`, from `GetScreenWidth`/`GetScreenHeight`, UI units): at
least 1400 x 760; where the screen has room (its width less 80) wider in steps of 20 up to 1700, the
right pane 400 instead of 360 from 1560 on, the height what the map needs (its 3:2 under the tab bar and
the line under it), as long as that fits the screen's height less 100 (1920 x 1080: 1700 x 868; the
default UI's 1366 x 768: 1400 x 760). `LT.Window.Create` (`LefthyToolsLodestarBrowser`, in
`UISpecialFrames` so Escape closes it, movable), scaled down to fit when the screen is smaller than that
plus 40 x 80. In the band under the title: "Search all zones:" with its box on the left and right of it
**"Current zone"** (below), the two **filters** on the right (below). Under it, on an 8 px grid:

- **Left (240 px): places.** `Q.Zones()` grouped by continent in the order it gives them (a header per
  continent, its name from `C_Map.GetMapInfo`; a click folds it), each continent's zones **alphabetical**
  by the client's names (`C_Map.GetMapInfo(map).name`, else the data's: on a German client the German
  ones; case-insensitive, a German umlaut sorted as its vowel, "Ödland" with the O's, ß as ss: `Rule.SortKey`,
  worked out once with the list), then a "Dungeons" header and `Q.Dungeons()`, alphabetical too. A zone's
  name everywhere in the window is that client's name. Each row: the name, the level range, "done of total" and a thin bar under it (green
  when all are done). The count is `Q.ZoneCount(map)` (a dungeon: `Q.ZoneCount(name)`): every quest for
  me, any level, only "not for me" left out; without `Q.ZoneCount` it's counted here the same way over
  `Q.ZoneQuests` / `Q.DungeonQuests`. A dash when none is for me. A place far from my level (its top
  below my level - 10, or its bottom above my level + 5) has its name dimmed, its count kept. The first
  time it opens, the zone I'm in is chosen (`C_Map.GetBestMapForUnit`, then its parents), else the first
  zone on the left. A click shows that place, nothing picked.
- **Middle (the rest; 752 px at 1400, 1012 at 1700):** the **tab bar** (our own Buttons): **Zone** (the
  zone's map, a chain opened from it, a dungeon's quest list), **Quest list** (its key is still
  "overview"), then each registered view, on the Zone tab **the switch** right after the tabs (below),
  and at its right "Back to the search results" during a search. The zone's map sits right under it; a
  chain's page, the quest list and the search have the **head** under it: the chain's colour, the title
  (`GameFontNormalLarge`), a grey line under it, "x of y done" with a bar, and the chain's zoom (-, the
  zoom, +, Fit), a gold divider under it. Under a chain's page one short line on its lines (below); under a dungeon's list that its
  quests are given in many places. The tab is kept.
- **Right (360 px, 400 on a wide window): never empty.** The details of the quest picked; nothing
  picked, the briefing of what the middle shows (an opened chain's, else the place's).

**The switch "Map | Chain".** Players missed that a chain opens at all (only its card, a stub or the details'
"Open the chain" did it). On the Zone tab, always at the same spot (on the tab bar right after the last tab,
so it doesn't move between the map and a chain's page), a segmented control of two Buttons of ours in a thin
gold frame: **Map** (a dungeon: **Quests**, its list) and **Chain: Elwynn's Kobolds 3/7** (the name cut short
to the room there is, beside "Back to the search results" too; the quests without a chain opened: "Quests
without a chain 0/2"). The chain it offers: the one opened; else the picked quest's (a chain of more than one
quest, `Rule.Step`); nothing picked, the one left last for the map (so it switches both ways with one click;
another place forgets it). The half shown now is lit (gold, a line under it, "Shown now" in its tooltip); the
other has a hover light and its tooltip says what a click does ("Click: back to the map" / "Click: open the
chain" with how far along); one click switches (Map: the chain's page goes, the quest picked stays, on the
map; Chain: the chain's page, the quest picked in it, its card in sight). When no chain applies (nothing
picked and none left, or the quest picked is in none) the Chain half is greyed (no hover light, a click does
nothing) and its tooltip says why: "Pick a quest of a chain (on the map or on the right): its chain opens
here." / "Wolves Across the Border is in no quest chain." Picking another quest changes its label. It's the
way back from a chain to the map (the head's "< Elwynn Forest" is gone; the Zone tab clicked again does it
too). Hidden on the quest list, the views and the search results.

**Chain badges.** A quest of a chain has its badge on its row: "2/4" (its step, counted as the details count
it: `Q.ChainFor`, the steps as I can do them; else `Q.ChainStep`), amber on a faint gold pill with a thin
edge, a Button of its own on the row (the controller reaches it), lit when hovered; its tooltip: the chain's
name, "Step 2 of 4", "Click: open the chain". A click opens that chain in the middle on the Zone tab, the quest
picked, its card in sight (on that chain's page already: picked there; a step in another place: that place,
the chain there; `Side.ShowChain`). On the quest list's (and the search results') rows left of the right
column, on the right pane's rows (Turn in now and In progress here: at the right of the title line; a chain's
steps: left of the giver or reason), and on My quests' (Views.lua, through `Q.OpenChain`). A click on the row
elsewhere does what every quest row's does (below); the row's tooltip names both ("Click: show it on the map ·
Right-click: its chain", "Click 2/4: open the chain").

**"Current zone"** (`view.Here`, a Button of ours right of the search box, the player's arrow and the word): on
the Zone tab, the quest list and the search's results (not on another file's view, not without the data). A
click shows the place I'm in on the left (`Rule.Here`: a dungeon I'm in, by `GetInstanceInfo`'s name, else
`C_Map.GetBestMapForUnit` walked up from a city's floor or a cave to the zone the left lists, as
`Q.SelectZone` does): its continent unfolds, the list scrolls to it, its page shows, nothing picked (the
quest list stays the quest list; during a search it's shown inside the search). Its tooltip names the place
("Click: show Elwynn Forest"); in none of the left's places it's greyed, its tooltip says "You're in no zone
with quests known." and a click does nothing. Looked at when the middle is drawn and after
`ZONE_CHANGED_NEW_AREA`.

**A quest's row clicked** (the quest list's and the search results' rows, the right pane's rows: Turn in
now, In progress here, a chain's or the quests without a chain's steps; the details' steps around it,
Needs first and Leads to; a chain card's "next" line; `Side.Click`), round 7 (the players: "first the details
in the pane with the small map, then a button for the big map"): **where the zone's map is in sight** (the
Zone tab's map page) a click shows it on the map; **elsewhere** (the quest list, the search's results, a
chain's page, another file's view) **its details come first**: the quest picked, its details on the right with
the small map, the middle as it is (`Side.Details`); **Ctrl-click** shows it on the map there too (the
controller: the details' **"Show on map"**). A right-click: its chain, as its badge does (`Side.ShowChain`,
`Q.OpenChain`'s way); a quest in no chain: the map. Showing it on the map (`Side.ShowOnMap`): the Zone tab's
map with the quest picked (its pins ringed, its objectives' areas and way, its details on the right), never
the chain's page: on that map already only picked (found, below), else as **going to a quest** (below) on
the Zone tab, the chain's page left (kept for the switch's Chain), the quest list, a view or the results
giving way (the search stays, "Back to the search results"); a dungeon's quest: its Zone tab, its list.
Their tooltips say "Click: details · Ctrl-click: show it on the map · Right-click: its chain" (in no chain:
"Click: details · Ctrl-click: show it on the map"); on the map page "Click: show it on the map ·
Right-click: its chain" (in no chain: "Click: show it on the map"). The map's pins keep theirs (a click
picks, a right-click or Shift-click the game's map pin, Alt-click the plan: below), so do the stubs; a
chain's cards on its page: a click picks it there (details, small map), Ctrl-click the map (their tooltip:
"Click: details", "Ctrl-click: show it on the map"). **The controller has no right-click**: its ways to a
chain are the "2/4" badge on every row of a chain's quest, the details' "Open the chain >" and the switch's
Chain (and a chain's card in the briefing).

A zone's pages show its quests (`Q.ZoneQuests`) and those given there but listed elsewhere
(`Q.ZoneGiven(map)`: the Deadmines' quests at Sentinel Hill); its count stays its own quests'.

### The zone page: the map

Every quest of the place goes through `Q.Chain(id)` once; a chain of more than one quest is a group,
ordered by the lowest level of its quests in this place; the quests without a chain are a group of their
own. Who leads to whom: each quest's `pre`, `preAny`, `preActive` and `Q.Opens`, only from an earlier
quest in the chain's order to a later one (a loop in the data is cut). Each chain has **a colour of its
own**: its first quest's ID times the golden ratio as a hue (HSV 0.6 / 0.95), the same in every zone and
every session; the quests without a chain are light grey (gold on the map for the quest picked).

**The map fills the middle** (its width, 3:2: 1012 x 674 on a 1700 window), right under the tab bar. The
zone's art (`LT.MapArt`: the world map's tiles, every area uncovered, as the small map) in a clipping
frame of ours. On a dark strip over its top: the zone's name and levels, and at its right **-, + and Fit**
(Buttons of ours: the controller's way to zoom) with the zoom when it's above 100%. A pin per spot of a
quest giver of the place's quests as the filters show them (within my levels by default; done ones too,
as dim dots; `starts[].points` on that map), a quest in my log at its turn-in's (`ends`), in the game's
own map icons on a dark disc: `QuestNormal` "!" (24 px) to pick up, **in its difficulty's colour**
(`marker.tier`, `Rule.Tier`: the icon desaturated and tinted with `Rule.TierRgb`, a little brighter: green
easy, orange hard, red far too hard; right for me the game's own yellow, untouched), `QuestDaily` for a
repeatable one (blue; a **hard** one, `Rule.IsHard`: an orange ring around its disc, `marker.Edge`, as its
colour can't say it),
`TrivialQuests` for one that's grey for me (`Q.IsTrivial`), `QuestTurnin` "?" when it's ready to turn in
(`C_QuestLog.IsComplete`; `QuestRepeatableTurnin` for a repeatable one), the same "?" grey while it's in
progress, a grey "!" (18 px) for one my level is too low for and a smaller, darker one for one that needs
another first, dim dots for done and not-for-me ones; where an item that starts a quest drops
(`starts[].drops[].points`) a soft gold circle ("Wolf Fang drops here (12%)", sized by the point's `r`).
Spots within 8 px are one pin (drop areas only with drop areas): its look the most urgent one's, **a
count badge** (the quests still to do there, from two), its tooltip the giver and each quest in its
status's colour with what the pin is ("[4] Brotherhood of Thieves · repeatable": ready to turn in, in
progress, low level, repeatable, a hard one's "Hard · Group quest · Mobs up to level 26" (`Rule.TierNote`),
or the reason it can't be taken yet, `ZonePage.PinNote`, asked only when
the tooltip shows; there's no legend under the map), then what a click does (a pin of one quest of a chain:
also "Then Chain above the map: its quest chain").

- **Hovering a pin** (the mouse, or the controller's cursor) lights its chains: their threads at full
  colour, their pins, every other pin dim (30%), and their cards in the briefing (below).
- **A click** picks its quest; a pin with several quests opens **a small list of ours beside it**
  (`LT.Window.PopupList`, on the zone page so the map doesn't clip it; left of the pin near the map's
  right edge): the giver on top, each quest with its icon, "[4] Title" in its status's colour and what
  it is, the one picked ticked, at most 12 ("... and N more"; the pin's quests by their look, then in
  `Q.Compare`'s order); a row clicked picks that one; the pin
  clicked again, a click elsewhere, zooming or dragging closes it.
- **Right-click or Shift-click**: the game's own map pin there (`Q.Waypoint`, a chat line says so).
- **The wheel zooms where the cursor is** (x 1.35 a step, up to 8: the map's spot under the cursor stays
  under it), -, + zoom around the middle, Fit shows the whole zone; dragging moves it; a pin the
  controller's cursor moves to out of sight brings the map to it, and a quest picked is found on it
  (**Finding a quest on the map**, below). Another zone starts whole.
- **My arrow** (`Interface\Minimap\MinimapArrow`, turned by `GetPlayerFacing`) where I am when I'm on that
  map (`Q.PlayerAt`), moved ten times a second by an OnUpdate on a frame of the map that's shown only
  while I'm on it (off it, or in an instance: hidden, nothing runs; looked at again after
  `ZONE_CHANGED_NEW_AREA`).

**Threads.** Each chain's quests on the map, in the chain's colour, as thin lines from giver to turn-in and
from a turn-in (else the giver) to the next quest's giver, the spots on this map; at most 500 a zone,
pooled `Line`s under the pins. A thread shows only while its chain's card or one of its pins is hovered
(3.5 px, full colour) or while the quest picked is of that chain (`map.keep`: 2 px, 70%, a done step's
25%; both 60% of that while the quest's own way shows); the others are hidden.

**The quest picked on the map** (`ZonePage.PickOn`, `Map.SetPick`): its pin ringed in gold; its
**objectives' areas** (`Q.Objectives`' points on this map: a kill's spawn clusters, where an item drops,
an object's spots) as soft blue circles, the game's quest areas' blue (`Map.AREA_C`, `Q.AREA_BLUE`: a
flat disc at 22% and an added glow around it, `Spells\GenericGlow64`, sized by the point's `r`, at
least 28 px); a quest **in my log** whose areas the game knows on this map (`Q.HasBlob`:
`C_QuestLog.GetQuestsOnMap`) gets **the game's own shape** instead (`Q.NewBlob`, `Q.DrawBlob`: a
`QuestPOIFrame` over the whole map art, set up as Blizzard's quest blob pin, drawn again with every
lay, so it scales with the zoom; `m.blob`), the circles hidden. Each area has a small button at its
middle (its tooltip: the objective, where it drops; a click: the game's map pin there); an objective my
quest log says is done stays faint, ticked; its **giver and turn-in** where no pin of it is (a ringed "!"
or "?", grey while it isn't done); and **its way**: a dashed line in its colour from the giver to each
objective's area nearest the last spot in turn, then to the turn-in. Hovering an objective's line in the
details (or its area's button) lights its areas (42%) and dims the others (7%).

**Under the map**, one line with only what's there of "1 ready to turn in · 5 for your level · 2 hard"
(the place's quests in my log ready to turn in (`C_QuestLog.IsComplete`), gold; **for my level**
(`Rule.ForMyLevel`: `Q.ForMyLevel`, in my log, or to take now and easy or fair for me), amber; apart
**the hard ones** (`Rule.IsHard`: `Q.IsHard`, to take now within my levels but orange for me), orange;
how far along is in the briefing), at its right how the map works ("Wheel: zoom ·
drag: move · right-click a pin: map pin"); with none for my level to take here (hard ones aside): "Nothing for you to pick up here right
now." and a button "Redridge Mountains has 9 for your level >" (`Q.SelectZone`): the zone whose level
range is within 3 of mine with the most quests for my level (its quests in my log or to take now within
my levels, as the level path counts them), kept until a status changes.

A dungeon has no map: its Zone tab is its quest list (as the Quest list tab), the line under it says each
quest's details show where it's given; its chains' cards are in its briefing.

### The right pane

**The briefing** (nothing picked; a scroll area of ours). A place's: its name (`GameFontNormalLarge`), "Level
1-10 · Eastern Kingdoms" (a dungeon: "Dungeon"), "12 of 40 done" with a bar across, "6 for your level ·
2 to pick up now · 1 hard" (its quests in my log or to take now and easy or fair for me, `Rule.ForMyLevel`
as `Q.ForMyLevel`: not one that needs another first, not a hard one; of them what I can take now; apart,
in orange, the hard ones, `Rule.IsHard`; each only when there are any; none at all: "Nothing for
your level."); then, only when there are any, **Turn in now (N)** (my quests ready to turn in
that are the place's, or whose turn-in or an objective's area is on its map: `C_QuestLog`'s quest log;
each a row: the "?", "[12] Title" and its chain badge, "Turn in at <ender>" under it, its zone when that's
another) and **In progress here (N)** (the rest of those: the first line of my progress not done yet, "3/10
Kobold Vermin slain", else "In your quest log"), at most 6 each, in `Q.Compare`'s order (the lowest level
first); then **Quest chains**: the
chains with a quest of this place not done yet within my levels (`Q.InRange`; all levels: any the filters
show) **in order** (`ZonePage.SortCards`): those with a quest in my log first, then those whose next step is
for my level, then those whose next step is hard, then the rest; the first three by their next steps
(`Q.Compare`: the lowest level first), the rest by their lowest level here; never a "Next: ..." before an
"In your log: ...". Then the quests without a chain, then a **"Completed (N)"** row for the chains with every quest
for me done (folded at first, a click opens it: their cards under it), and when the level filter left
chains out, a quiet line at the end: "2 more outside your levels · Show all levels" (a click turns the
filter on). A card (a Button, 48 px, 8 apart, as wide as the pane), two lines: a dot in the chain's
colour, its name (gold; grey when done: `Q.ChainStep`'s chain title, else the first quest's), "3/7" with
a check when done and a thin bar; then in grey what's next ("In your log: ...": of its quests in my log the
first in `Q.Compare`'s order, ready to turn in first; else "Next: <title> · <giver>": of those I can take
the first in that order, one for my level before a hard one, the lowest level first, a hard one with an
orange "· Hard"; else "Coming up: ..." (the first in the chain); else "All done"; the quests without a
chain: "2 to pick up now", for my level), and a dot per friend who's done some of it (`Q.Friends`, at
most 5, class colours). Its tooltip: how far along, what's next, its levels ("Level 5-12"), "Doing it
opens 4 more of the chain" (how many of its quests not done yet come after the next one), "2 steps
elsewhere" (its steps for me in other places) and each friend's "3 of 7", "Click: open the chain" (**it's
a chain, not a quest**: a click on the card opens the chain in the middle) and "Click the next step's
line: show it on the map". **The next step's line** is a Button of its own on the card (`NextBtn`): a
quest's row (above: a click the map with it picked, a right-click its chain), its tooltip the quest's;
hovering it lights the chain as the card does. Nothing to show: "No quests known here yet." or "Nothing
to show with these filters.". A row clicked shows its quest on the map (picked; a right-click: its chain).

An opened chain's briefing: its colour and name, "Level 1-10 · 9 quests · 1 steps elsewhere", "2 of 9
steps done" with a bar, what's next; **Steps**: every step shown (the filters'), a row each, "[12] Title"
in its status's colour, a tick when done, its badge "3/9", at its right the giver for one I can take or
have, else its reason (a hard one: an orange "Hard · " before it); in the chain's order (the quests without a
chain: in `Q.Compare`'s); at most 60 ("... and N more"); **Friends** ("Anna 3 of 9") when any. A row
clicked shows it on the zone's map (the chain kept for the switch's Chain); right-clicked, it's picked on
the chain's page.

**Lighting the other side.** Hovering a chain's card (the mouse, or the controller's cursor: its focus runs
OnEnter) lights its pins and thread and dims every other pin (30%). Hovering a pin lights the cards of its
quests' chains (gold edge and glow) and dims the others (40%); when none of them is in sight, the
briefing scrolls to the first. Leaving puts it back. The card of the picked quest's chain has a gold edge.
Only alphas, line widths and which thread shows change: nothing is laid again.

**The details** (a quest picked). On top, fixed: **"< Elwynn Forest"** (the chain's name on a chain's
page), back to the briefing (nothing picked). Then in a scroll area, on the 8 px grid:

- Its icon (32 px: the start's "!" by my status, the "?" when it's ready, an item's own), beside it the
  title ("[12] Title", in its tier's colour, the client's title when it answers) and one status line
  with its reason (above; a skipped one: what I took instead), what makes it harder than its level says
  (`Rule.TierNote`, in its tier's colour, not for a done one: "Hard · Group quest · Mobs up to level 26",
  only what applies: the word for an orange or red one, `Q.Group`, `Q.MobLevels`' highest above its level)
  and the tags after it (new in WoW: Forever, repeatable, learned while playing).
- **"Step 3 of 7 · <the chain>"** (a section heading; the steps as I can do them, `Q.ChainFor`, else the
  place's chain without what isn't for me), a bar of the steps done under it, **"Open the chain >"** at its
  right (the chain in the middle, the quest in sight), and the steps around it as links: one before, this
  one (white, an arrow, marked), two after (more at the chain's ends), "... N before" / "... and N more";
  done ones ticked; a step is a quest's row: a click shows it on the map, a right-click its chain (on
  that chain's page: picked there).
- **Objectives** (`Q.Objectives`): a line each, "Kill 10 x Kobold Vermin", "Collect 8 x Gold Dust" (the
  client's item name when it has it) with its likeliest source under it ("from Kobold Miner, 32%"), "Use
  Wanted Poster"; for a quest in my log the quest log's own lines with my progress
  (`C_QuestLog.GetQuestObjectives`: "Kobold Vermin slain: 3/10"), matched to the data's by the name in the
  line, else by the order of their kind, else by their place; done ones ticked and grey. A dot in the map's
  colour when it has an area on the map in sight; hovering lights its areas there (its tooltip: every
  source with its chance and zone), a click puts the game's map pin at its area. No objectives known (or
  no `Q.Objectives`): no section.
- **Quest giver and turn-in**: a line each (`GameFontHighlight`), "Marshal Dughan · Elwynn Forest" with
  the "!", the ender with the "?" (grey until it's done); objects and items said so; an item: its icon,
  and its best drop under it ("Drops from Young Wolf (12%) · Elwynn Forest"; an object "In ... (x%)"). A
  line is a Button: its tooltip has the spot and the rest (the other drops, "Starts at" the other givers,
  "Turn in at" the other enders, three each, "... and N more"), a click puts **a map pin** there and finds
  it on the map (round 7, below; so does an objective's line: its area).
- The small map (the same widget as the zone page's, not zoomable), only when the zone page's map isn't in
  sight (a chain's page, the quest list, another tab, the search): for a quest in my log the map of its
  objectives (else its turn-in's), else its first giver's map (else a drop's, else the first ender's),
  with every giver, ender and drop area and the quest's own areas and way on it; a click on a pin puts the
  map pin there; a pin hovered or clicked pulses. A giver's, turn-in's, drop's or objective's line clicked
  shows that spot's map here (another zone's too) and pulses the spot.
- **Rewards** (`Q.Rewards`): "Choose one of:" and its items, "You get:" (or "You also get:" after a
  choice) and its items: the game's icons (36 px, `C_Item.GetItemIconByID`), the count, a border in the
  quality's colour (`C_Item.GetItemQualityByID`, not for a common one; an item the client doesn't know yet
  is asked for, `C_Item.RequestLoadItemDataByID`, and drawn again when `ITEM_DATA_LOAD_RESULT` says it
  came), nine a row; hovering one: the game's item tooltip (`GameTooltip:SetItemByID`), a modified click
  the game's (`HandleModifiedItemClick`: Shift links it, Ctrl tries it on); then the money
  (`GetCoinTextureString`) and "1250 XP". None known (or no `Q.Rewards`): no section.
- **Requirements**, only those not met: for a quest not for me the one that keeps me from it (faction,
  races: a mask with all of one side's classic races is "every Horde race", as the engine counts it for
  the new ones too, else each race whose bit is set, named by `Q.Races()`' `{ id, bit, name }` /
  `Q.RaceInfo(id)`, the game's `C_CreatureInfo.GetRaceInfo`, classic's names; classes; a profession), for a
  locked one the reputation or profession rank `Q.Needs` names, and what taking it closes while it can
  still be taken (without `Q.WhyOther` all of a not-for-me quest's).
- **Needs first:** only the first of `Q.Missing` ("... and N more") and **Leads to:** (`Q.Opens` in
  `Q.Compare`'s order, at most three), a button per quest, its zone named when it isn't the place shown (a
  click: as the steps').
- **Friends** only when any (`Q.Friends`: at most three names in class colour with their status, "+N").

At the bottom, outside the scroll area: **Map pin** (the game's map pin where to go next: the turn-in when
it's ready, in my log the first objective not done yet that has an area, else the turn-in; not taken yet
its giver, an item's best drop; greyed without a spot; its tooltip says where) and **Companion** (the
quest in the small window, `Q.ShowQuest`). On top, right of the way back, **"Show on map"** (round 7, a
Button with the map icon: the controller's Ctrl-click): the quest on the Zone tab's map, found and pulsing
(`Side.ShowPicked`); after a giver's, turn-in's, drop's or objective's line was clicked, that spot instead,
zoomed in (its tooltip says which). The title line has the plan's **"+"** at its right (below).

### A chain opened

Its head: the chain's colour, its name, "3 of 7 steps done" and a bar, what's next (the way back to the
zone's map is the switch's Map above it, which stays where it was). An opened chain shows **every level** of its steps (cutting steps out would break
it): only what isn't for me is left out, with its filter off (a skipped one stays). The page is a canvas
of its own (below) with the chain's quests as **cards** (170
x 48, Buttons) from top to bottom, **a row per stage** (a quest's stage: one more than the latest of what
leads to it), the quests of a stage side by side, each stage centred in the page's width; a stage's order
follows where what leads to them is (the average of their slots above), the first stage the chain's
order (ForeverQuestChain's and BtWQuests' layout). A card: a flat background in Attune's tones (done
green, available amber, in my log blue, the rest dark grey with a grey edge), a 3 px strip in its status's
colour on the left, the start (32 px: the giver's `QuestNormal` "!" (`QuestDaily` when repeatable,
`TrivialQuests` when grey for me), bright only when I can take it, `SideInProgressquesticon` in my log, the
item's icon (`C_Item.GetItemIconByID`), an object's note), a check (`common-icon-checkmark`) when done,
"[12] Title" (the level in its difficulty colour, the client's title when it knows the quest), and under
it the giver in grey (in another zone the zone's name). No words on the cards: a lead-in (a breadcrumb)
is a bit dimmer and its line dashed, its tooltip says it isn't needed for what comes after; what taking it
closes (`excl`) and friends are in its tooltip. Not for me, or skipped: dimmed.
The quest picked: a gold edge and glow. **The next step pulses once** (a gold glow in and out) when the
chain is opened from its card, and is brought into sight. The right pane: the quest picked, else the
chain's briefing (its steps). A card clicked picks it there (its details, the small map), Ctrl-clicked:
the quest on the zone's map (round 7).

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

**Joins.** Where two or more lines lead into a quest and any one of them is enough (two or more are its
`preAny`), a small amber label **"one of"** sits on them just above it. Where each is needed the lines just
meet.

**Under the page** one short grey line: "dashed: lead-in · one of: any one is enough · orange: the way to a
locked quest" (not for the quests without a chain, which have no lines).

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

**Difficulty colour** (`LevelRgb`): the quest's **tier** (`Q.TierCode(id)`: its effective level, the higher
of its own and its mobs', a group quest one tier harder, the client's own for a quest in my log; kept until
a status changes), on every "[12]" of every title (cards, rows, links, pins' tooltips, the details);
without it `Q.LevelColor(level, id)` (a table `{ r, g, b }`, three numbers or a
colour code), else the game's `C_PlayerInfo.GetContentDifficultyQuestForPlayer` for a quest the client
knows, else Blizzard's thresholds against my level (5 above: red, 3: orange, down to 4 below: yellow,
within `UnitQuestTrivialLevelRange` (classic's green range without it): green, else grey); without a tier
repeatable quests blue.

**How hard** (`Rule.Tier`, `Rule.ForMyLevel`, `Rule.IsHard`, kept until a status changes): `Q.Tier(id)`
("trivial" grey, "easy" green, "fair" yellow, "difficult" orange, "impossible" red; without it
`Q.Difficulty`), `Q.ForMyLevel(id)` (in my log, or to take now and easy or fair), `Q.IsHard(id)` (to take
now within my levels but orange); the words are `Q.TIER_WORD`'s (else "Hard", "Too hard"). **For my level**
counts only those; the hard ones are counted apart ("· 2 hard", orange), listed after the ones that fit,
marked ("Hard · <giver>" in orange at a row's right, "· Hard" after a chain card's next step, an orange
ring on a pin); red ones only with All levels (`Q.InRange` leaves them out). Without this round's
functions the engine's of before count (a "difficult" one by `Q.Difficulty` still apart).

**The order** (`Rule.Compare` / `Rule.Sort`): every list of quests in `Q.Compare(a, b)`'s order (ready to
turn in, in my log, for my level, hard, other ones I could take, coming up, blocked, done, not for me; then
the effective level, no level last; the client's title; the ID): the quest list's sections, the search's
results (a quest's ID first), the briefing's Turn in now and In progress here, the quests without a
chain (their briefing and their page), Leads to, a pin's quests (after their look), what a chain card
calls next. A list that IS a chain keeps the chain's order (a chain's Steps, its page, the details' steps
around it). Without `Q.Compare` (or when it fails) the same order worked out here (`Rule.Before`, with
`Q.StatusRank` when it's there); a title for the order is the client's when it knows it, else the data's
(nothing is asked of the client for a sort). Sorted when a list is made (a status, the filters or the
data changed, a place or tab shown), never per frame.

### Quest list

The tab "Quest list" (key "overview"), and a dungeon's Zone tab: the place's quests within my levels (all
levels: every one) in groups (a pooled list, the left's rows): In progress, Available now, Coming up (level
too low), Blocked (needs something first), Completed (folded at first; the skipped ones in it too,
"Skipped" at their right), Not for you (only with that filter, only race, class, faction or a profession I
don't have), each with how many, **each in `Q.Compare`'s order** (ready to turn in first; the ones for my
level, then the hard ones, then the rest; by level; a folded group isn't sorted); then, when the level filter left some out, a quiet line "5 more outside
your levels · Show all levels" (a click turns the filter on). A row: the start's icon, "[12] title" (level
in its tier's colour, title in its status's colour), at the right the giver (a hard one: "Hard · " before it, orange), or for a blocked, later or not-for-me one
its reason ("Needs Investigate Echo Ridge", "Needs level 7", "Not for your faction"), left of it a quest of
a chain's badge ("5/9": a click opens the chain on the Zone tab), at its left the plan's "+" (round 7). A
click elsewhere on the row picks it: its details on the right with the small map, the list staying;
Ctrl-click: the quest on the Zone tab's map, picked (a right-click: its chain).

### Views other files add

`Q.RegisterBrowserView(key, label, build)` adds a tab after Zone and Quest list (in the order registered;
a view registered after the window was built gets its tab at once). `build(parent)` is called the
first time the tab is shown, with a frame of ours under the tab bar, between the zones and the right
pane (the middle's width and its height under the tab bar: 752 x 634 at 1400 x 760, 1012 x 742 at
1700 x 868; the head and the legend are hidden for it), and returns `{ frame, Refresh =
function(self) end, OnShow = function(self) end, OnHide = function(self) end }` (each optional; a frame
without points fills the parent; `self` is that table). OnShow runs when its tab is shown, OnHide when
another tab is or the window closes; Refresh each time it's shown and while it's shown when quests change
(the window's events, on the next frame) or the data changes. Errors in them go to the error handler (the
error window) and don't break the window; a build that fails leaves "This view couldn't be built." `key`
must be a string other than "zone", "overview" and "results", `build` a function; the same key again
replaces its label and build (a view already built stays). Returns true when registered. The right pane
shows the briefing of the place shown (or the quest picked) beside it.

`Q.ShowBrowserView(key)` opens the window (if it isn't) on that tab: "zone" (the zone's page), "overview"
(the quest list) or a registered view's key; false for an unknown one. From a view, `Q.ShowDetails(questID)`
picks the quest beside it (its details on the right, the view stays), `Q.ShowOnMap(questID[, spot])` (and
`Q.OpenBrowser(questID)`, the same) goes to the quest (its zone's map, picked, found) and
`Q.SelectZone(map)` to a zone's page (both on the Zone tab).

### Filters

Two checkboxes of ours (Buttons with the game's checkbox art; a third, **Plan on map**, `planMap`, on by
default, only with the plan: **The plan in the big window**, below), kept in the module's settings
(`browser = { allLevels, showOther, planMap, tab }`, made when first needed; a tab of the version before, "chains" or
"map", becomes "zone"; the earlier `hideDone` and `onlyAvailable` are just ignored):

- **All levels** (off): off, the zone page (pins, threads, the line under the map) and the briefing (its
  chains' cards) and the quest list show only what's within my levels: `Q.InRange(id)` (a quest in my log;
  else what I can take now and is worth it: its `minLevel` at most mine, not grey for me, its level at most
  `Q.RANGE_RED`, 4, above mine (red: far too hard; a level of -1 / 0 counts as mine); done and skipped ones
  always; without `Q.InRange` everything), kept per status change. A chain's card is listed when one of its
  quests here not done yet is within my levels; what's left out is counted in a quiet line at the end of
  the list ("N more outside your levels · Show all levels", a click turns this on). "N for your level" in
  the briefing counts what's in my log or to take now and easy or fair for me (the hard ones apart) whatever the filter. An opened chain and the search always show every
  level.
- **Show quests not for you** (off): off, quests for another race, class, faction or a profession I don't
  have are left out everywhere (a skipped one isn't "not for you": it stays, with the done ones); on,
  they're shown, dimmed. A hidden quest in a chain is passed through: what came before it leads to what
  comes after (a fainter line), and the stages close up. A chain with nothing left to show has no card
  either.

The done ones are folded instead of hidden ("Completed (N)" in the briefing, the Completed group in the
quest list). The search and the counts aren't filtered.

### Going to a quest, the search

**Going to a quest** (a link Ctrl-clicked, a stub, a chain badge, `Q.ShowOnMap(id)` (`Q.OpenBrowser(id)`), `Q.OpenChain(id)`): it stays in the place shown
if that place lists it (its own quests and those given there), else goes to the quest's zone if that
zone lists it, else its dungeon, else its zone. Its continent unfolds, the left list scrolls to the place
when it changed, and on the Zone tab its zone's map shows it picked (a dungeon: its list; a stub, a badge
or a right-click: its chain opened there, its card in the middle). A quest's row clicked shows its details
first where the zone's map isn't in sight (above: **a quest's row clicked**). A click on a quest (a card, a
row, a pin, a link) also shows it in the small window when that's open (`Q.IsSmallShown()`; without it
this is skipped; not for the calls of other files). A click on a place on the left shows its page with nothing picked (the quest list stays
the quest list; a registered view goes back to Zone).

**Search.** Typed into the box, searched 0.3 s after the last key: a quest ID finds that quest, two
letters or more go to `Q.Search(text)` (titles, the client's too, and givers). The results replace the
page (a list, each with its zone, in `Q.Compare`'s order, a quest's ID first). A click on a result picks
it (its details, the results stay); Ctrl-click shows it on its zone's map (above; a right-click: its
chain), with "Back to the search
results" in the tab bar; a click on a place or a tab does the same with that place. The search stays (the
box keeps its text) until it's emptied (the box's X, or deleting it), which goes back to the place, the
quest in the details in sight. One letter: "Type at least two letters." Closed before a search was due,
it runs when the window opens again.

**No data.** `Q.Load()` (it loads `LefthyTools_QuestData` the first time) not true, or no `Q.Load`: the
window says the data isn't there (missing or switched off in the AddOns list), without panes, search or
filters.

### Finding a quest on the map (round 7)

The players: "it should also go to the place and highlight it ... sometimes I click on the quest and can't
find where it actually is on the map." A quest picked on the Zone tab's map (a pin, a row, a link,
`Q.ShowOnMap`; not `Q.ShowDetails`, which leaves the map as it is) is **found** (`ZonePage.Find`): its pins
(giver, turn-in, an item's drops), its giver and turn-in where no pin of it is, and its objectives' areas
(`Map.PickItems`) are brought into sight when they aren't all (`Map.Bring`: moved into the middle, zoomed
**out** as far as they need, 24 px kept free; never zoomed in, so one pin never zooms) and **pulse**
(`Map.Flash`): a gold glow and a ring of ours (18 `Line`s) around each pin, a brighter gold outline (a ring
3 px outside) and a softer glow on each area, all on one frame of ours over the art and the areas, under the
pins, whose alpha an `AnimationGroup` takes in and out three times (0.25 s in, 0.45 s each way, 0.9 s out:
3 s) and which is hidden when it's done (`OnFinished`); the quest picked keeps its gold ring. At most 24
things pulse; zoomed meanwhile, they're laid again; another map, the window closed: stopped.

**A spot** (`Q.ShowOnMap(id, { map, x, y[, r] })`, a giver's, turn-in's, drop's or objective's line in the
details, "Show on map" after one): its zone's page (`Map.PlaceOfSpot`: the zone of the left whose map it is,
or the one above a city's floor or a cave, `C_Map.GetMapRectOnMap` walking up; on no zone's map: the quest
as above), the quest picked, zoomed **in** to it (300%, `Map.FOCUS`; an area with `r` only as far as it
fits), in the middle, pulsing; the spot is kept (`state.spot`) for "Show on map" until another quest is
picked. With the zone's map not in sight the line's click leaves the middle as it is: the details' small
map shows the spot's map (another zone's too: `Details.MapSpots`' force) and pulses it. A pin of the small
map pulses when hovered or clicked.

### The plan in the big window (round 7)

The plan (Plan.lua: `Q.PlanHas`, `Q.PlanToggle`, `Q.PlanStops`, `Q.PlanRev`, `Q.PlanNext`; without them
nothing of this shows):

- **"+"** (`Make.NewPlus`, a Button of its own, 16 px, `UI-PlusButton-Up`; the check `common-icon-checkmark`
  when the quest is in the plan) at the left of every quest's row of the quest list and the search's
  results, of the right pane's rows (Turn in now, In progress here, a chain's Steps), on the details' title
  line, and at the right of a pin's list's rows (a pin of several quests). Its tooltip: "Add to plan" / "In
  your plan", the quest, what a click does. A click: `Q.PlanToggle` (only when the plan still is what the
  button showed: changed elsewhere meanwhile, it's only drawn again), then what shows the plan is drawn
  again. A pin of one quest, and every quest's row (`Side.Click`: the quest list, the results, the
  details' links and steps; a chain's cards): **Alt-click** adds it or takes it out (its tooltip says
  which). A quest's tooltip says "In your plan".
- **The plan on the map** (`Stops`): the zone page's map shows the plan's stops not done that are on it
  (`Q.PlanStops`' `spot`, a city's floor or a cave moved onto its zone), each a numbered disc of ours (its
  place in `Q.PlanStops`; a Button, up and left of the spot so the quest's own pin stays clickable), the
  next one (`Q.PlanNext`) gold and larger, joined by a line in the plan's order (3 px, light blue, under the
  pins); a stop in another zone: the line goes to the map's edge toward it (the world's coordinates,
  `C_Map.GetWorldPosFromMapPos`; another continent: no line) and says "to Westfall (4)" there ("from
  Westfall (3)" for the way back in). A disc's tooltip: "4. Pick up Wanted: Hogger · Marshal Dughan" ("Kill
  10 x Kobold Vermin · Wanted: Hogger", "Turn in ... · <ender>"), "Next stop" for the next; a click picks
  its quest and pulses the stop, a right-click puts the game's map pin there. Worked out (`Stops.For`) only
  when `Q.PlanRev` or the map shown changes, laid again when the map is zoomed. **Plan on map** (a filter,
  on by default, kept as `planMap`) switches it off. Each disc has its stop's kind at its top right
  (`Stops.SetKind`: the game's "!" a pick-up, "?" a turn-in, a small white dot an objective), and the line
  under the map (`zp.Hint`) says what they are while any is on it ("Teal numbers: your plan (gold: next) ·
  ! pick up · ? turn in · dot: objective"). The numbers stay the stops' places in `Q.PlanStops`, done
  ones counted: the map's first number can be 3 (the pane on the right shows the 1 and 2, ticked).
- **The plan on the right** (`Stops.BuildSwitch`, `Stops.BuildPane`): over the right pane a switch of
  two halves (`Make.NewHalf`'s look): **Quest** (nothing picked: the place's name; the details or the
  briefing) | **Plan** with "3 to go"; only with the plan (`Q.PlanStops`). The pane is 26 px lower for
  it. `state.side = "plan"` shows the plan instead: "Your plan", "3 quests · 7 stops · 4 to go" (a route
  in use: "· Suggested route"), what the numbers are, the chips **Suggest a route** / **Back to my
  order** (as the Plan tab's) and **Plan tab** (the middle's), then in my order each quest's row (a grip,
  "1. [12] Title", remove at its right; dragged: `Q.PlanMove`, a gold line where it lands, the pane
  scrolling near its edges; a click its details, Ctrl-click the map, a right-click its chain, Alt-click
  out of the plan) with its stops under it, or with a route in use its stops in the route's order. A
  stop's row: its kind (done: ticked), its number as on the map, what it is (`Q.PlanStopText`), its
  zone; the next one on a gold band. Hovering it lights its disc on the map (`LockHighlight`, one pulse);
  a click goes there (`Side.ShowSpot` with `how = "plan"`: the pane stays, the stop lit), Ctrl-click its
  quest's details, a right-click or Shift-click the map pin, Alt-click its quest out of the plan. A disc
  on the map clicked while the plan shows: it stays, that stop lit. Any other pick (a pin, a row, the
  quest list) gives way to its details (`Pick` clears `state.side` unless `how` is "plan").
- **When the plan changed** (`Stops.Check`: `Q.PlanRev` against the one drawn last): after a "+" clicked,
  with the quest log's updates (an objective done changes the stops), when the middle is drawn, and when
  Plan.lua tells (`Q.OnPlanChanged(fn)`, if it has it: on the next frame): the rows' "+", the right pane, a
  pin's list and the map's stops are drawn again; nothing is asked per frame.

### What it costs

Built the first time it opens; nothing at login. A place's chains (`Q.Chain`, who leads to whom) are
worked out once and kept until the data changes; a chain's progress (its card, its head), a chain page's
cards and lines, a zone's pins and threads, why a quest isn't for me (`Q.WhyOther`) and whether it's within
my levels (`Q.InRange`), its tier, colour, for my level and hard (`Rule.Tier`, `Rule.ForMyLevel`, `Rule.IsHard`), the zone to suggest when the filters or a status change (an event), or the window
opens; what a pin is only when its tooltip shows; a place's count once, until a quest of it is turned in (or
one is taken or dropped: that can close others). Statuses are read for the place's quests when its page is
drawn and for the cards near sight when they're filled. The quest picked's areas and way
(`Q.Objectives`, Data.lua's cache) when it's picked or the map is drawn. The lists (left, quest list,
results) are pools of the rows in sight plus 2 above and below; entry i always has row `(i - 1) % pool + 1`;
the briefing's rows and cards, the details' lines and reward buttons are pools too (a zone has tens of
chains; a chain's briefing at most 60 steps), each row's chain badge with it (its step from `Q.ChainFor`,
which the engine keeps until my progress changes). The switch is set when the middle is drawn and when a
quest is picked, from what's kept (the place's chains, `Chains.Info`): nothing is worked out for it.
Hovering only sets alphas and line widths. While it's open it
listens to `QUEST_TURNED_IN`, `QUEST_ACCEPTED`, `QUEST_REMOVED`, `PLAYER_LEVEL_UP`, `QUEST_DATA_LOAD_RESULT` (a
title asked for with `C_QuestLog.RequestLoadQuestByID`, once per quest a session, came),
`ITEM_DATA_LOAD_RESULT` (a reward asked for came), `QUEST_LOG_UPDATE` and `ZONE_CHANGED_NEW_AREA` (looked at
a second later at most: if a quest in my log got ready to turn in, only the map's pins and the line under
it are drawn again; if what the right pane shows of my quest log changed (`Side.LogKey`: the details'
quest's lines, the briefing's quests in progress), only the right pane and the quest's areas; my arrow
placed again); the handlers only note it, the window redraws on the next frame (an OnUpdate set only while
something is due), at most every 0.5 s for statuses, 0.2 s after titles and items. `Q.OnDataChanged`: open,
everything worked out goes and it's drawn again on the next frame; closed, when it opens. Dragging (the
canvas, the map) runs an OnUpdate only while the button is held; my arrow's only while I'm on the map
shown. Closed: no events, no OnUpdate. Round 7: finding a quest is worked out once per click (its spots on
the map, one zoom), the pulse is an `AnimationGroup` (nothing of ours per frame); the plan's stops on the map
once per `Q.PlanRev` and map, its "+" read (`Q.PlanHas`) when a row is filled.

### Controller and taint

Our frames only; nothing protected, so it opens in a fight and in gamepad mode. No Blizzard menu (a pin's
list of quests is `LT.Window.PopupList`, ours), no Blizzard panel opened (not the world map either: the
zone map is our own frame with `LT.MapArt`'s textures; no data provider, no pins on `WorldMapFrame`; the
map pin is `C_Map.SetUserWaypoint`). `GameTooltip:SetItemByID` on our own buttons. Every card, chain card,
pin, objective area, the map's -, + and Fit, list row, the briefing's rows, every chain badge, the details'
lines, steps, objectives and rewards, tab, the switch's two halves, filter, zoom button, link, place line,
the ways back, Map pin, Companion, the suggestion, "Current zone" and a chain card's next-step line are plain Buttons, so SmartNavigation finds them as the panel's descendants (its focus runs
OnEnter: the tooltips show, a chain's card or a pin lights the other side, an objective's line its areas,
as with the mouse). The briefing and the details are ScrollFrames (SmartNavigation scrolls them); the
chain's canvas and the map aren't (SmartNavigation only scrolls those up and down, and only takes their
buttons in sight): their buttons are the panel's own, and a card or pin the cursor moves to out of sight
(its middle outside, in gamepad mode or without the mouse over it) moves the view to it; -, + and Fit zoom
the map. A right-click or Shift has no controller button: on a pin the details' Map pin does it; on a
quest's row (its chain) the row's "2/4" badge, the details' "Open the chain >" and the switch's Chain do
(and "Current zone", the chain cards' next-step lines are Buttons too). Ctrl-click (a quest on the map
from a row elsewhere) has the details' "Show on map"; the plan's "+" (rows, details, a pin's list), its
discs on the map and "Plan on map" are Buttons; Alt-click on a pin has its details' "+". The canvas and the
map have no OnMouseDown/OnMouseUp (they'd be buttons to SmartNavigation), only the wheel and dragging.
Nothing of Blizzard's (navigation flags, mixins, Backdrop) is set on our frames. A registered view's frames
are its own file's: the same rules apply.

Tests: `tests/lodestar_browser.lua`, with stand-ins for every `Q.*` it calls (the data, the engine, the
iterations' `Q.ZoneCount`, `Q.ChainStep`, `Q.LevelColor`, `Q.Races`, `Q.ZoneGiven`, `Q.Available`,
`Q.IsTrivial`, `Q.InRange` (this round's meaning), `Q.WhyOther`, `Q.Needs`, this round's `Q.Objectives` and
`Q.Rewards` (the shared contract's shapes: Data.lua makes them in parallel), the small window), put back at
the end; this round's shared contract (`Q.Tier`, `Q.TierColor`, `Q.TierCode`, `Q.TIER_WORD`, `Q.Group`,
`Q.MobLevels`, `Q.ForMyLevel`, `Q.IsHard`, `Q.StatusRank`, `Q.Compare`: Data.lua and Engine.lua make them in
parallel) as stand-ins with its meaning (tiers from the test's sets HARD, TRIVIAL, FAR, mobs from MOBS, a
group from GROUP); it also checks the window without `Q.ZoneCount`, `Q.ChainStep`, `Q.LevelColor`,
`Q.TierCode`, `Q.Objectives`, `Q.Rewards`, without `Q.Tier`, `Q.ForMyLevel`, `Q.IsHard`, `Q.TIER_WORD` (Q.Difficulty's
tier) and without `Q.Compare` and `Q.StatusRank` (the same order), the size for four screens, and registers views of its own (removed at its end); the mock's
map pin API and `GameTooltip:SetItemByID` are made for it and put back. The switch (its spot, greyed with
its reason, one click each way, the label following the quest picked, the chain left kept, a dungeon's
Quests, cut short beside the way back to the results, nothing worked out for it) and the chain badges (the
quest list's, the right pane's, a step's on its chain, a step elsewhere, the rows' tooltips, `Q.OpenChain`)
have sections of their own, and so do "Current zone" and the left's order (a city's floor, a dungeon,
nowhere, the quest list, a search, German names), how hard (the counts, the order, the marks, the pins'
rings, the tooltips and details, red only with all levels) and the order everywhere (a zone of chains in my
log, for my level, hard and coming up; what each card calls next; the quest list, the briefing, the search;
a chain's steps; the clicks on rows, the next step's line and the cards). Round 7: the plan's functions
(Plan.lua's, made in parallel) are missing until its sections, then stand-ins of the shared contract
(Plan.lua's put back at the end); sections for finding a quest (nothing moves when it's in sight, moved and
zoomed out only as far as it needs, the pulse's rings and AnimationGroup, a spot zoomed in to, a large
area, a city's floor, another zone, no zone; the details' lines on the map page and with the small map,
"Show on map"), the details first (`Q.ShowDetails` on the quest list, the map, another file's view, closed;
a chain's cards, Ctrl-click), the plan's "+" (none without it, the rows' room, tooltips, a click, the
details', the briefing's, drawn again only on `Q.PlanRev`, a stale one, Alt-click, a pin's list) and the
plan on the map (numbers, the next one, the lines, toward another zone and from it, tooltips, zoomed,
clicks, a stop done, another zone's page, the toggle, the kinds, the line under the map, without it) and
on the right (the switch and its count, every stop numbered with the done ones ticked, the next one, the
kinds, hovering lights the disc, a click there with the pane staying, a disc clicked, Ctrl-click the
details, a quest dragged, a pick elsewhere giving way).

### Open questions (in game)

- That the canvas's anchor offsets count in its own (zoomed) units, so zooming and scrolling line up.
- That SmartNavigation's cursor moves onto a card or pin that's clipped out of sight (it's visible to it)
  and runs its OnEnter, so the view follows; and onto the briefing's rows and cards inside its ScrollFrame,
  and a pin's list of quests (a PopupList at FULLSCREEN_DIALOG strata) when a pin's click opened it.
- The atlases `TrivialQuests`, `QuestRepeatableTurnin`, `SideInProgressquesticon`,
  `QuestDaily`, `common-icon-checkmark`, `Options_HorizontalDivider` on Forever (each falls back when
  missing).
- That a desaturated `QuestTurnin` reads as the game's grey "?".
- That `Line` objects on the map frame (OVERLAY) draw over `LT.MapArt`'s tiles (ARTWORK) and under the pins;
  that `Spells\GenericGlow64` added in a chain's colour reads as a soft area on every zone's art.
- That `C_Map.SetUserWaypoint` from addon code doesn't taint anything in gamepad mode.
- That `GetCursorPosition` over `GetLeft`/`GetTop` of the map box gives the cursor's spot at any window
  scale (the wheel's zoom keeps it under the cursor).
- That `GameTooltip:SetItemByID` shows a reward's tooltip for an item the client hasn't seen yet (it asks
  the server itself), and `C_Item.GetItemQualityByID` answers after `ITEM_DATA_LOAD_RESULT`.
- Whether the quest log's objective lines (`C_QuestLog.GetQuestObjectives`) come in the data's order on a
  German client (the names there are German: matched by kind and order).
- Round 7: that an `AnimationGroup` on the pulse's frame fades its `Line`s and textures together and
  `OnFinished` runs (else it stays at alpha 0, shown); that `Spells\GenericGlow64` in gold reads around a
  pin on every zone's art; that `C_Map.GetMapRectOnMap` gives a city's floor's place on its zone (Stormwind
  on Elwynn Forest) and `C_Map.GetWorldPosFromMapPos` a sensible direction to the next zone for the plan's
  line; that SmartNavigation reaches the "+" inside a row (a Button in a Button) and inside a pin's list.

## Views (Views.lua)

Three more views of the big window, each a tab of its own: registered with the window's registry
(`Q.RegisterBrowserView(key, label, build)`; `build(parent)` gives `{ frame, Refresh, OnShow, OnHide }`)
when it's there: at load (Browser.lua comes before this file in the TOC), else when the module is
switched on (`Q.When("enable")`); without a registry nothing is registered and nothing breaks. Keys and
tabs, in this order: `myquests` "My quests", `plan` "Plan" (Plan, below), `levelpath` "Level path" (a window that kept the tab `storylines` of the
builds before opens on the zone page: the window's own rule for a tab it doesn't know). A view is built
by the window when its tab is first shown (`Q.BuildView(key, parent)` makes one; the tests use it),
fills its parent, and lays itself out again when the parent's size changes. They jump with
`Q.ShowDetails(id)` (round 7: the quest's details on the right, the tab staying; without it
`Q.OpenBrowser`), `Q.ShowOnMap(id[, spot])` (the Zone tab's map with the quest, or that spot, in sight;
without it `Q.OpenBrowser(id)`), `Q.OpenChain(id)` (a chain badge: the quest's chain, its card in sight;
without it `Q.OpenBrowser`) and `Q.SelectZone(map)` (a zone; without it the zone's first quest).

Each view: a bar on top (a headline and chips), the list on a darker panel (a scroll frame of ours; only
the rows near sight exist, pooled, each kept on its entry while it stays near, so the controller's
cursor stays on it), a footer (the level path's legend) and, while counting, "Counting quests... 40%".
No data (`Q.Ready()` not true): the window's line that the data add-on is missing.

The **Continents** view (a tile per zone) and the **Storylines** grid (every chain of every zone as a
card, filtered and sorted by what it's worth) of earlier builds are gone: the zone list on the window's
left shows each zone's progress, and the players didn't know what the storylines were for; the chains
that matter now (those I'm on) are in My quests.

**For my levels** is the engine's `Q.InRange(id)` (round 6: a quest in my log; else my level reached
(`minLevel`), its difficulty tier (`Q.Tier`) easy, fair or difficult, not an event's, a level known).
Quests "coming up" (my level too low) are out of it. Without `Q.InRange` everything counts as in range.
**"N for your level · M hard"** (the level path, the zone's briefing, the suggestion under the map): N is
`Q.ForMyLevel` (in my log, or one I can take now that's easy or fair), M apart `Q.IsHard` (one I can take
now within my levels that's orange); a quest that needs another first is in neither yet. Without them: N is
in my log or `"available"` and `Q.InRange`, M none. An event's quest not in my log is counted apart
(`event`).

**Difficulty and order** (round 6, the players' "the addon should treat those differently" and "I hate it
when stuff is out of order"): every quest title is in its tier's colour (`Q.TierCode`: the engine's
`Q.Tier`, the quest's effective level, its objectives' mobs' when higher, a group quest one harder; without
it the level's colour, `Q.LevelCode`), "[12] Title" (`V.Title`). Every list of quests is in the one order
`Q.Compare` (ready to turn in, in my log, for my level, hard, the rest; then by effective level, title, ID;
without it by ID), a list that is a chain in its steps' order. Hard ones are marked with the tier's word
("Hard", `Q.TIER_WORD`) beside the colour. `V.Tier`, `V.TierRGB` (`Q.TierColor`), `V.TierWord`,
`V.ForMyLevel`, `V.IsHard` and `V.Before` guard the calls (Views.lua's fallbacks when the engine's are
missing).

### My quests

The quest log, organised the way quest log add-ons and guides do it (Questie's and the guides' "turn
in, then what's near, then the rest"; QuestGuru's and the game's zone headings; the guides' one line
per step):

- On top: "12 quests in your log · 3 ready to turn in"; at the right **Sort:** Zone (the default),
  Level, Storyline (chips; kept: `views.mySort`, "zone" at first; the `show` and `sort` of the
  storylines before are left alone).
- **Ready to turn in** first, whatever the sort: every zone's, in the one order (by level).
- Then **by zone** (the quest's zone in the data, else its dungeon, else the quest log's heading
  above it, else "Other quests"): my zone first ("you're here"), then the other zones by their lowest
  quest level. **By level**: one group "In progress". **By storyline**: a group per chain (`Q.ChainFor`:
  its first quest's title and "1/5", the steps done of all for me), its quests in step order; the quests
  in no chain last ("Not in a storyline"). Within every other group (ready ones too) the one order,
  `Q.Compare` (by level, then title): no longer the nearest first, the distance stays on the line.
- A group's heading: its name in gold, "(3)" and the rest in grey, a thin gold rule.
- **A quest** (one line, 24 px, a Button): at its left the plan's **"+"** (Plan.lua's `Q.NewPlanButton`, a
  Button of its own: "Add to plan"; a check when it's in the plan, "In your plan", a click takes it out;
  `Q.PlanToggle`), its verb icon (`QuestTurnin` when ready, else
  `SideInProgressquesticon`), "[12] Title" (in its difficulty tier's colour, `Q.TierCode`), its
  chain's "2/4" (`Q.ChainFor`, in progress gold: a badge, below), its first objective not done with its progress
  ("2/10 Defias Looter", from `Q.LogObjectives`: the client's numbers and the name without its count),
  how far its area is when it's in my zone (" · 170 yd N"), or "Ready to turn in" in green; at the right
  the turn-in's icon and name, with its zone when it isn't the quest's own (or, ready, isn't mine), and
  how far when ready in my zone. Columns: the title 38% of the width, the badge 40 px, the objective
  30%, the turn-in the rest.
- **Where I have to go** (for the distance and the map pin): ready: the turn-in's spot
  nearest me; else `Q.ObjectiveSpot` (the nearest area of an objective not done, `Q.Objectives`); else
  the turn-in.
- Its tooltip: "[12] Title", ready or "In your quest log", its zone, "Step 2 of 5 · <chain>", every
  objective from the quest log (done ones ticked, grey; an item's "(from Oat Sack, 100%)": the data's
  likeliest source), "Turn in: <name>, <zone>", "Click: its details", "Ctrl-click: show it on the map",
  "Right-click (or 2/5): open the chain" (in a chain), "Shift-click: map pin at <the objective, or the
  turn-in's name>".
- **Clicks** (round 7, details first: the player asked for the quest's details with the small map before
  the big map): a click `Q.ShowDetails(id)` (its details on the right, My quests staying in the middle);
  Ctrl-click `Q.ShowOnMap(id)` (its zone's map, the quest picked and in sight: what a click did before;
  the controller's way there is the details' "Show on map"); a right-click its chain (`Q.OpenChain`; a
  quest in no chain: as a click); Shift-click the game's map pin there (`Q.Waypoint`; Shift-right-click:
  its link in chat too). The plan changing (`Q.OnPlanChanged`) draws the views again (the "+" or check).
- **Its badge** ("2/5", a Button of its own on the row, a faint gold pill lit when hovered; its tooltip
  the chain's name, "Step 2 of 5", "Click: open the chain"): a click opens the quest's chain in the big
  window, the quest picked, its card in sight (`Q.OpenChain(id)`; without it `Q.OpenBrowser`). The row's
  own click stays as it is.
- An empty log: "Your quest log is empty. The Zone tab has what you can pick up here."

**Continue your storylines** (a heading, "started, the next step for your level" in grey): the chains I've
started (a step done or in my log, not all done) whose next step I can take now: the first of the chain
(in `Q.Chain`'s order) that's "available" and `Q.InRange` (so a step too high or one that needs the step
in my log isn't listed). In the one order of those next steps (`Q.Compare`: for my level first, then hard
ones, each by level); at most 8. A line: the `QuestNormal` "!", "<chain> - next: [13] <title>, <giver>
(<zone>)" (the chain's name gold, the step in its tier's colour; a hard one "(Hard)" in orange after it),
"1/2" (its steps done) at the right, a badge as the quests' (its tooltip: the chain, "1 of 2 steps done",
"Click: open the chain"; a click: `Q.OpenChain` on that step). Its tooltip: the chain, "1 of 2 steps
done", "Next: ...", "Hard" for a hard one, "From <giver>, <zone>", the clicks. The plan's "+" at its left
(that step). A click: `Q.ShowDetails` of that step, Ctrl-click `Q.ShowOnMap`; a right-click:
`Q.OpenChain`; Shift-click: the map pin at its giver (nearest me). It comes
from the counts (below): while they're made, "Looking through your storylines..." (the log above shows at
once); none: "No storyline you've started has a next step for your level now."

### Level path ("where to go next")

The zones of my side (a zone with quests for me: 5 or more, or a quarter of its quests) that have
something for my levels (a quest not done that's `Q.InRange`: with iteration 5's meaning nothing my
level is too low for, nothing red) or a friend there (Beacon's, with the
module's `friends` setting, whose zone, Battle.net's `area` matched to the zone's name, the client's or
the data's, it is); the chip **All zones** at the top right shows every zone of my side (kept:
`views.allZones`). A row (26 px) has only: the name (a faint blue band for the zone I'm in,
`Q.HereZone`), a bar across the levels 1-60 (more if a zone goes higher; ticks every ten and "You (12)"
on top) from the zone's lowest to its highest level, shaded per level: done (all its quests done:
a thin light line, 2 px), else the difficulty tier most of that level's quests not done have for me
(`Q.Tier`, as many: the harder): easy green, fair yellow, difficult orange, impossible red, trivial grey
(round 6: the level path in the quest log's colours); a level without quests takes the shade before it,
quests outside the zone's range count at its ends (their level is the quest's own; the tier is the
effective one); a gold line at my level; at the right "7 for your level · 2 hard" (`Q.ForMyLevel`, and
apart `Q.IsHard` in orange; not one that needs another first, nor an event's), else "All done", else
nothing. Sorted by the first count, then the second, then the zones my level is in, then the nearest; a
zone with only hard ones is listed too. On top: "Best next: Westfall, 7 quests for your level", "Only hard
ones for your level: Redridge Mountains has 3.", or "Nothing for your level. Next up: Redridge Mountains,
from level 15." No zone left: "No zone has quests for your level." and a button that shows all zones. The
tooltip has the rest: levels, done, for my level, hard, what I can take now, in my log, later, "Left to do,
by difficulty:" (each tier's count of the quests not done, the easiest first, grey last, in its colour),
each run of levels with its tier's word ("Level 12-15: Fair"), friends there (name, level), "You're
here.". A click: `Q.SelectZone`. The legend: each tier's colour and word, done's thin line, my level's
line.

### What it costs

The counts are made once and kept: every zone's quests by status (`Q.Status`), level, tier (`Q.Tier`, each
level's and the zone's), for my level and hard (`Q.ForMyLevel`, `Q.IsHard`), every chain's (`Q.Chain`: done, in the log, available, levels, its next step I can take
within my levels), 200 quests a frame on a frame of ours that's shown only while counting
(5257 quests, 3473 of them in chains: well under a second, no hitch), and only while a view is shown.
They're for a data, progress and level (`Q.dataGen`, `Q.progressGen`, `UnitLevel`): made again when one
changed (checked when a view shows or draws; `Q.Status(0)` first, so a quest taken while no view was
shown is read), or after `QUEST_TURNED_IN`, `QUEST_ACCEPTED`, `QUEST_REMOVED`, `PLAYER_LEVEL_UP` or
`Q.OnDataChanged`; the last counts stay drawn meanwhile. The sorts (`Q.Compare`: the log's 25, the
storylines' next steps) run when a view draws (an event, a move, a click), never per frame. My quests reads the quest log (at most 25 quests:
their objectives, `Q.Objectives` cached by the data part) when it draws, `QUEST_LOG_UPDATE` only draws
again (it doesn't count). Events are registered only while a view is shown; they're noted and drawn half
a second later (several: once; in a fight, where every kill updates the log, the same). While My quests
is shown a child frame of it looks every 2 s whether I moved (2% of the map, or another zone) and draws
it again then (the distances, the nearest first). Friends' answers (`Q.OnFriendProgress`) draw again.
Friends' places are read when a view draws. A view's `Refresh` (the window's) draws on the next frame.
Hidden: no events, no OnUpdate.

### Controller and taint

Our own frames only, nothing protected (it works in a fight), no Blizzard menu. Every quest and storyline
row, its chain badge, its plan "+", zone row, chip (the level path's toggle too, the plan's Suggest a route
and Clear), the plan's up, down and remove and the empty state's button is a Button, so
SmartNavigation reaches them (its focus runs OnEnter: the tooltips). A controller has no right-click and no
Shift: **its way to a chain is the row's "2/4" badge** (a Button of its own beside the title, the cursor
stops on it; Continue's "1/2" too), and the map pin is the big window's "Map pin" in the quest's details
(a click opens them); the group headings and notes are plain frames it
skips; the lists are scroll frames (it scrolls them); nothing of Blizzard's is set on our frames.

Tests: `tests/lodestar_views.lua` (the real Data.lua and Engine.lua through `Q.SetTestData`; the
registry is a stand-in that records, the real one put back after; `Q.OpenBrowser`, `Q.ShowDetails`,
`Q.ShowOnMap` (the big window's part makes them in parallel), `Q.OpenChain`, `Q.SelectZone` and
`Q.Waypoint` record; `Q.Objectives` and `Q.InRange` are stand-ins with the contract's meaning, the data
part's own tests check theirs; round 6's contract, `Q.Tier`, `Q.TierColor`, `Q.TierCode`, `Q.TIER_WORD`,
`Q.Group`, `Q.MobLevels`, the new `Q.InRange` and `Q.ForMyLevel`, `Q.IsHard`, `Q.StatusRank` and
`Q.Compare`, get stand-ins with the contract's meaning while `Q.Tier` and `Q.Compare` are missing, else the
real ones run): `Q.LogObjectives` (the name without its count in the game's and a German
client's format, the numbers from the text, the data's objective by kind and by name) and
`Q.ObjectiveSpot`; My quests (the log at once while the storylines are counted, the groups and their
order (`Q.Compare` within each group), a line's columns and tooltip, a click (its details, never the chain;
without `Q.ShowDetails` the map), Ctrl-click (the map), a right-click (the chain; in no chain: as a click),
Shift-click (the map pin), the plan's "+" (a Button at the left, its tooltip, in and out, drawn again with the
check), the chain badges (theirs and
the rows' tooltips, a click: `Q.OpenChain`), Continue (a hard next step after the one for my level,
orange, marked) and what it leaves out, the three sorts kept, the storylines' old settings, events,
walking (the distance drawn again, the order kept), turning in, an empty log); the level path (the bands
in the tiers' colours, done a thin line, "1 for your level · 1 hard", the tooltip's counts by tier, the
order by both counts);
hidden and shown again; a full log and 300 storylines with only the rows in sight; no data, the
controller, a fight.

### Open questions (in game)

- That the registry's parent has its size when a view is shown (else the view lays itself out again
  on `OnSizeChanged`).
- How long the counting takes with the real data, and whether "Counting quests" is seen at all.
- Battle.net's `areaName` for a friend's zone on a German client (matched to the client's zone names).
- That `C_QuestLog.GetQuestObjectives` gives `type` ("monster", "item", "object") and the numbers on
  Forever, and that `QUEST_MONSTERS_KILLED` and the others are the formats of its texts (else the name
  keeps "slain" and the data's objective is found by its name or place).
- Whether SmartNavigation's second button is a right-click on our rows (else the map pin is the big
  window's "Map pin" button for a controller).

## Plan (Plan.lua, the Plan tab in Views.lua)

Round 7, the players' "plan mode": pick the quests you want to do, in the order you want, and Lodestar says
"first go here, then there", with a shorter route only when you ask for it ("I don't want to present people
with 'here is the best route for all the quests in your range'"). The "+" on a quest's row adds it at the
end (the quest list, the search results, the right pane's rows and the details' title line in the big
window, Browser.lua; My quests here; Alt-click on a map pin); the Plan tab orders it; the companion shows
the next stop on top (Small window, Plan); the big window draws it on the zone map (`Q.PlanStops`,
Browser.lua).

### The data (Plan.lua)

**Kept per character**, as the addon keeps other per-character choices (Beacon's chat tabs: by the GUID):
`LefthyToolsDB.lodestar.plans[GUID] = { list = { questID, ... }, route = { keys, spots, before, after } }`
(made with the first quest added; a broken one made sane once: only quest IDs, each once; without saved
variables or a GUID: a plan for this session).

- `Q.PlanList()` (the quests in order, a copy), `Q.PlanHas(id)`, `Q.PlanAdd(id)` (at the end; true when
  added), `Q.PlanRemove(id)`, `Q.PlanToggle(id)` (returns whether it's in now), `Q.PlanMove(id, index)` (1
  the first; beyond the ends: the end), `Q.PlanClear()`.
- `Q.PlanRev()`: a number that changes whenever the plan or its stops change (compare it when you draw;
  never poll it per frame). `Q.OnPlanChanged(fn)`: `fn()` on the next frame after an edit, a skip, a
  route or a quest leaving it (several: once).
- **A quest turned in leaves the plan** by itself (`QUEST_TURNED_IN`; a route in use stays), and one done
  some other way (`Q.Status` "done", not a repeatable one) when the stops are made next.
- `Q.PlanStops()` → **the stops**, in order: the route's when one is in use, else each quest's in the plan's
  order. A stop: `{ quest, kind = "start" | "objective" | "end", index (an objective's place in
  Q.Objectives), label ("Marshal Dughan", "Kill 10 x Kobold Vermin"), spots = { { map, x, y }, ... }, spot,
  done, key ("7001:objective:1"), have, need (an objective's progress in my log) }`. A quest not taken: its
  giver (`starts`' points; an item that starts it: where it drops, "Dusty Letter (drops from Defias
  Pillager)"), each objective with an area (`Q.Objectives`' sources' points; not one the giver provides),
  its turn-in (`ends`); taken (`"active"`): the giver done, each objective done as my quest log says
  (`Q.LogObjectives`, matched to the data's), ready (`C_QuestLog.IsComplete`): all of them done. Done stops
  stay in the list (so "Stop 2 of 14" counts the whole way); the windows don't draw them. A stop without any
  spot is left out; a quest the data doesn't know has none (it stays listed). **The spot**: the route's
  choice, else of its candidates the nearest to the stop before it (the first stop not done: to me;
  `Q.RouteYards` when Route.lua has it, else on one map its width counted 1.5 times), else the first; the
  label then that spot's person (a turn-in in two places: the nearer one). The spots are the data's own
  point tables (shared: callers don't write into them).
- `Q.PlanNext()` → the first stop not done and its place. `Q.PlanSkip(stop)`: done for now (until a
  /reload or logout: kept in this session only), the next one comes up.
- **A suggested route**: `Q.PlanSuggest()` asks Route.lua's `Q.SuggestRoute(stops, here)` (the stops in the
  quest order, `here` my zone and spot, `Q.HereZone`), keeps its order (the stops' keys) and each stop's
  chosen spot (`"1429:0.4200:0.6600"`) and its yards (`before`, `after`) in the saved plan; nil when it
  can't (an error in it goes to the error handler; what was in use stays). The stops the route doesn't name
  (done ones) come first. `Q.PlanUseOrder()`: back to the quest order. **Any edit** (add, remove, move)
  drops the route back to the quest order and says so (`dropped`). `Q.PlanRouteInfo()` → `{ active,
  before, after, saves, good (saves less than 50 yards or 5%: "Your order is already a good one"), dropped }`.
- Words: `Q.PlanStopText(stop[, withQuest])` ("Pick up Wanted: Hogger at Marshal Dughan", "Kill 10 x Kobold
  Vermin", "Turn in at Gryan Stoutmantle"; withQuest: "Turn in Wanted: Hogger at ...", "Kill ... · Wanted:
  Hogger"), `Q.PlanBriefing()` → `{ title = "Your plan", lines = { "Stop 2 of 14: ... · Elwynn Forest",
  "Zones: Elwynn Forest, Westfall", "5 quests · 14 stops" } }` (for a briefing: the big window's right pane
  can show it beside the Plan tab).
- `Q.NewPlanButton(parent[, size])`: the "+" (a Button of ours, 16 px: `UI-PlusButton-Up`; in the plan the
  check, `common-icon-checkmark`, else the ready check's; tooltip "Add to plan" / "In your plan", "Click:
  remove it from your plan"); `b:SetQuest(id)` (nil: hidden); a click toggles it.

**What it costs.** The stops are made when asked and kept until the plan, my quest log, the data or my
progress changes (`Q.dataGen`, `Q.progressGen`, a count the events move); the rev moves only when they
look different (keys, done, spots). `QUEST_TURNED_IN`, `QUEST_LOG_UPDATE`, `QUEST_ACCEPTED` and
`QUEST_REMOVED` are listened to only while the plan has quests and Lodestar is on (from the first loading
screen); the handlers only note them (a turn-in also takes the quest out). Nothing runs per frame; the data
is never loaded for it (no stops until a window loaded it).

### The Plan tab (Views.lua)

After My quests. On top **"5 quests · 14 stops"** and at the right **Suggest a route** (only with
Route.lua's `Q.SuggestRoute`; in use: **Back to my order**) and **Clear** (asks first, our own: "Clear your
whole plan?" with **Clear it** and **Cancel** in the bar, not a Blizzard popup); under it one line: "Your
order: drag a quest to move it. Ctrl-click: see it on the map.", "Suggested route · Saves about 1200 yards" (rounded to 50,
from 1000 to 100) or "Your order is already a good one", "The plan changed: back to your order." (an edit
dropped the route), "No route: there's nothing left to go to, or no place is known.".

- **Your order** (no route in use): first the next stop as a row ("Stop 2 of 14: Pick up ...", its zone, a
  gold band), the zones it covers (`Q.PlanBriefing`), then a heading and the quests, numbered: "1." in gold,
  "[12] Title" in its tier's colour, its chain's "2/4" (a badge: the chain), where it stands ("Pick up at
  Marshal Dughan · Elwynn Forest", "3/10 Kobold Vermin", "Ready: turn in at Gryan Stoutmantle · Westfall",
  "Your level is too low: from level 20", "Needs <the quest first>"), a grip at its left and at the right
  **remove** ("Remove from plan", a Button). **Dragged** (the left button held, `RegisterForDrag`): the row
  dims, a gold line between the rows shows where it would land (above the row whose middle the cursor is
  above; below the last: the end), the list scrolls near its top and bottom (24 px, 300 px a second); let
  go: `Q.PlanMove` there (where it was: nothing). The drag's every frame is `inst.Dragger`'s OnUpdate (a
  child of the view: hidden, the drag is given up, nothing moved; the button let go elsewhere, the row
  pooled away meanwhile: dropped). Only my order's quests drag (a route's stops are its order). Its
  tooltip: the title, where it stands, its step, each of its stops (done ones ticked), the clicks
  (Alt-click, Drag).
- **A route in use**: its stops, numbered in the route's order ("Pick up X at Y", "Kill 10 x ... · [12]
  Title", "Turn in at Z · [12] Title"), each with its zone at the right; the next one with an arrow and a
  gold band, done ones ticked and grey.
- **Clicks** (a quest or a stop): a click `Q.ShowDetails` (the details on the right with their small map,
  the Plan tab staying), Ctrl-click `Q.ShowOnMap` (a stop: its spot), a right-click its chain, Shift-click
  the game's map pin at its next stop (a stop: there), Alt-click `Q.PlanToggle` (out of the plan; the same
  `QuestClick` as My quests', where it puts one in).
- Empty: "Your plan is empty. Add quests with the + beside them: in the Quest list, My quests and a quest's
  details, or Alt-click a quest giver on the map."
- The right pane is the window's (Browser.lua): the details of the quest picked; `Q.PlanBriefing()` is
  there for its briefing of the plan.

It doesn't use the views' counts (`noCensus`: shown alone, nothing is counted); it's drawn when shown, on
the views' events and when the plan changes. Rows are pooled as the other views'.

**Tests** (`tests/lodestar_plan.lua`, the real Data.lua and Engine.lua through `Q.SetTestData`;
`Q.Objectives` a stand-in; `Q.ShowDetails`, `Q.ShowOnMap`, `Q.OpenChain`, `Q.Waypoint` record;
`Q.SuggestRoute` stand-ins, `Q.RouteYards` none): the list (in order, each once, nonsense not, a copy, the
callbacks once on the next frame, kept per character, another character's own, a broken saved plan made
sane, toggle, move, remove); the stops (a quest not taken, an objective, a turn-in in two places: the
nearer, an item's two areas, kept, in words; taken: the giver done, my progress; the rev the same when
nothing changed and moving when an objective's done; ready; skipped; turned in: leaves, the callbacks; done
meanwhile: leaves when the stops are made; an item that starts it; a quest the data doesn't know; the
briefing); a route (none without Route.lua; asked with every stop and where I am; in use, what it saves, the
order with the done ones first, the chosen spots kept and saved, made again the same; back to the order;
an edit drops it and says so; a quest turned in keeps it; good already; none possible; an error reported);
the "+" button; the events only with a plan and Lodestar on; the Plan tab (empty, nothing counted, drawn
when the plan changes, the next stop, the zones, a quest's row and its status, why one can't be taken,
dragged to the top, below the last, given up, let go where it was, above another, remove, Alt-click, the clicks and the tooltip, Suggest a route only with Route.lua, the route's stops numbered
with the next one marked, a stop's Ctrl-click with its spot, an edit dropping it, back to my order, Clear
asking first, Cancel, the controller, hidden: nothing runs). The companion's part: `tests/lodestar_small.lua`.

### Open questions (in game)

- `common-icon-checkmark`, `UI-PlusButton-Up`, `UI-GroupLoot-Pass-Up` and the scroll bar's arrows as the
  plan's buttons on Forever, and how the "+" reads beside a row's verb icon.
- That `Line`s on a layer of ours over the companion's map art draw above the art and below the numbers.
- That `UnitGUID("player")` answers at the first loading screen (else the plan's events wait for the next
  edit).

## Learning and friends

Files: `Modules/Lodestar/Learn.lua` (learning while playing) and `Modules/Beacon/QuestShare.lua`
(friends' progress and learned data over Beacon; its words are in [beacon.md](beacon.md), "Lodestar").

### Learning (Learn.lua)

Only while the Lodestar module is on with its `learn` setting, and only for quests the data
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

**Kept** account-wide in `LefthyToolsDB.lodestar.learned[questID]` = `{ u, t, l, s, e, p, x, f }`
(stamp, title, level, giver, ender, prerequisites, proven not, the friend's account whose record
changed it last); giver and ender `{ k = "n" | "o" | "i", i, n, m, x, y }`. At most 1500 records:
over that, the oldest changes go, down to 1350. At most 4 prerequisites and 8 proven-not per
quest. `LefthyToolsDB.lodestar.share = { seq, epoch, got }`: the store's change counter (each
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
at most 40) go to every friend on a build from `LODESTAR_SINCE` on, at most one request every 2 s
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

## Route (Route.lua)

A shorter order for the plan's stops, only when the player asks for it ("Suggest a route" on the
Plan tab): never a route over every quest in range. Pure logic: no frames, no events, no saved data.

- `Q.SuggestRoute(stops, here)` -> `{ order = { stop, ... }, before = yards, after = yards }` or nil.
  `stops`: `Q.PlanStops()`'s (`{ quest, kind = "start"|"objective"|"end", index, label, spots = {
  { map, x, y }, ... }, spot, done }`); `here`: `{ map, x, y }` of the player, or nil (the route
  then starts wherever it's shortest). `order` holds the same stop tables, each with `.spot` set to
  the spot chosen of its `spots`; done stops and stops without a spot are left out. `before`: the
  given order's yards (each stop's own `.spot`, else its spot nearest the stop before), `after`: the
  route's, from `here` when given, whole yards. nil when no stop is left (or no table).
- `Q.RouteYards(a, b)` -> the yards between two spots (`{ map, x, y }`, 0..1 on that map) as the
  route counts them, and true as a second value for another continent; nil without both.

**What's kept:** a quest's start before its objectives (in any order) before its end; a quest in my
log has no start (its objectives, then its end). A quest that needs another one of the plan
(`Q.Missing`: `"done"` and `"any"`) starts after that one's end (its start when it has no end stop);
one that needs another in the log (`"log"`, `preActive`) starts after that one's start and before
its end. Without `Q.Missing` (no engine), the quest's own `pre`, `preAny` and `preActive`. When the
needs make a loop (bad data) they're all left out; each quest's own order always stays.

**Travel:** straight-line yards in world coordinates (`C_Map.GetWorldPosFromMapPos`, as `Q.Toward`
counts them); another continent a fixed 10000 yards (a boat, a zeppelin or a portal, and the wait).
A map the game gives no world position for (an instance's): its own size (`C_Map.GetMapWorldSize`,
else 3000 x 2000 yards) on the same map, a fixed 5000 yards to any other. Flight paths aren't
counted: `Data/FlightPaths.lua` has the paths' lengths between taxi nodes but not where the flight
masters stand, and which ones I know is only seen at a flight master's map.

**How:** precedence-feasible nearest neighbour from `here` (each stop's spot nearest the last;
ties: the plan's order), or the given order when it keeps the constraints and is as short (a good
order stays as it is); then rounds of local improvement: 2-opt (a stretch reversed, only when no
constraint lies inside it) and or-opt (one to three stops moved elsewhere, within the window their
constraints leave, tried right after one of the head's 8 nearest stops, right before one of the
tail's, or first), each move saving at least half a yard; between rounds each stop's spot is
picked best for the order (a Viterbi pass over the candidates: exact for that order), until a
round saves nothing (8 rounds at most). The yards between two places are counted once per call; the
table of yards between the stops is made again only for stops whose spot changed. Deterministic (no randomness, ties by
the plan's order). 80 stops with 1-3 spots each take about 75 ms in the tests' Lua VM (fengari,
several times slower than the game's): about 10 ms in game, once per click. More than 200 stops:
nearest neighbour and the spots only.

**Tests** (`tests/lodestar_route.lua`): the yards (world, continent, maps without positions);
nothing to do; a zig-zag order fixed (3100 -> 900 yards) and a good order kept; the constraints
(a far giver first, a needed quest's end before the start, `"log"`, a loop in the needs); the spot
by the route chosen; another continent visited once; done stops dropped; the same answer twice;
80 stops in time with every constraint kept.
