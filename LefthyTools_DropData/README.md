# LefthyTools Drop Data

What each kind of mob can drop and how likely, for LefthyTools' Bestiary, and how much health it
has, for Beacon's fight stream. The Bestiary shows the drops beside your own kills: the database's
chance on each of your drops, and what you haven't had yet, faded. The fight stream turns what a mob
lost into numbers with its health (and knows an elite's health before the first kill). It's an
add-on of its own (load on demand: LefthyTools loads it the first time one of them needs it)
because it's under a different license from LefthyTools.

## Where it comes from

`Drops.lua` is generated from the loot tables and creature templates of
[CMaNGOS Classic DB](https://github.com/cmangos/classic-db), the Full_DB dump
`ClassicDB_1_12_1_z2815.sql.gz` (the updates after that milestone aren't applied). It's a classic
(1.12) world database. WoW: Forever is classic content with the same mob and item IDs, but its own
additions aren't in there and its drop rates and health may differ, so the Bestiary never mixes it
into your own numbers, and the fight stream prefers what it measured itself on Forever (from two
kills of a kind on).

How the chances are worked out (in detail in `tools/update-drop-data.js`):

- a loot row on its own drops with its chance; in a group one item of the group drops (rows without
  a chance share what's left evenly);
- a reference to another table rolls that table with the row's chance, as many times as it says;
- an item reached several ways: 1 − the product of (1 − each way's chance);
- a negative chance is a quest item's (it drops only while you're on the quest): marked;
- world loot is left out: the level-based world drop tables (random gear of every quality, bags,
  scrolls, recipes, potions) and a dungeon's shared zone drops. That covers what is reached only
  through references and doesn't bind on pickup, when it's gear or the reference is shared by 8 or
  more loot tables. A boss's own loot stays (Ragnaros's tier legs at 21% each);
- chances under 0.05% are left out.

Health comes from `creature_template`: `MinLevelHealth` and `MaxLevelHealth`, a creature's health
at its lowest and highest level (`MinLevel`, `MaxLevel`), with its `HealthMultiplier` already in;
LefthyTools takes a level between in a straight line. Also for creatures without loot, but
not for what no one fights: 1 health or less, totems, triggers and other invisible helpers, and the
unused ones.

Format: `LefthyToolsDropData.mobs[creature ID] = "<item>:<quality>:<chance>[q],...;s=<skinning, the
same>;g=<min copper>-<max copper>;h=<min level>-<max level>:<health at the min level>-<at the max
level>"`, chances in hundredths of a percent, the likeliest first; each part only when there is one,
the second level or health only when it differs (`h=60:3052`).

## Making it again

From the LefthyTools repository:

```
node tools/update-drop-data.js                       downloads CMaNGOS Classic DB's full dump
node tools/update-drop-data.js <dump.sql[.gz]>       a dump you have (another milestone, a server's own)
node tools/update-drop-data.js <dump> --source "..." with a different name for where it comes from
node tools/update-drop-data.js <dump> --stats        only the numbers, nothing written
```

Any MaNGOS-style world database with the same tables works (creature_template,
creature_loot_template, skinning_loot_template, reference_loot_template, item_template). When
better data for Forever exists (a dump, or numbers collected from play), it's a matter of feeding it
to the tool, or a converter writing the same format.

## License

GPL v3, like its source: see [LICENSE.md](LICENSE.md). World of Warcraft content and materials are
trademarks and copyrights of Blizzard or its licensors: see [COPYRIGHT.md](COPYRIGHT.md) (CMaNGOS's
notice, kept as it is). LefthyTools itself is under the BSD 2-Clause License; this folder is the
only part under the GPL.
