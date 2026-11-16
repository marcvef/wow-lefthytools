# WhyPoor?

Ideas for making money with the character you play, at its level, class, professions and place, and
roughly how much each brings. **Informational only**: it never buys, sells, bids or posts (auxForever
and Auctioneer for Forever do that); it tells you what's worth your time, and it must not tell you
anything wrong.

> This file starts as the design and the contracts between the module's parts (built in parallel);
> each part's section is filled in by whoever builds it and then describes what is there, like the
> other docs.

## Files

| File | What | Global |
|---|---|---|
| `WhyPoor.lua` | the module, its settings page, `/whypoor` and `/lefthy whypoor`, the minimap button, `W.DB()` | `ns.WhyPoor` = `W`, `W.module` |
| `Prices.lua` | auction house and vendor prices for every item, their history, how sure they are, how well an item sells; the auction house scans (taking over Margins'), Margins reads its prices from here | `W.Prices` = `P` |
| `Share.lua` | friends' prices over Beacon (a new message kind) and ours to them | `W.Share` |
| `Data.lua` | the money data add-on `LefthyTools_MoneyData` (load on demand), read into tables | `W.Data` = `Dt` |
| `Crafts.lua` | the cheapest way to get an item, also crafting it (and its reagents) yourself; what a recipe brings, "sell the reagents instead"; Margins uses it | `W.Crafts` = `Cr` |
| `Context.lua` | who I am now | `W.Context()` |
| `Methods.lua` | the ideas: each way of making money worked out and ranked | `W.Ideas` = `I` |
| `Goal.lua` | the money goal (the mount) | `W.Goal` = `G` |
| `Bags.lua` | each bag item's best sale, the tooltip line, the coin in the sorted bags | `W.Bags` |
| `Window.lua` | the window (Lodestar's style): Ideas, Bags, Market, the goal's strip | `W.Window` |

Data add-on: `LefthyTools_MoneyData/` (GPL v3 like its source, CMaNGOS Classic DB, as
LefthyTools_DropData and LefthyTools_QuestData), made by `tools/update-money-data.js`; the installer
copies it as a companion. Saved: `LefthyToolsWhyPoorDB` (account-wide; `prices`, `goal`, `ui`).

## Rules for every part

- **Never wrong.** A number is shown only with what it rests on, and only when it rests on something:
  - `basis`: `"yours"` (your own kills, loot, sales: Bestiary, Chronicle, your auctions), `"prices"`
    (auction house scans; with their age), `"forever"` (Forever's own data: client tables, EG Link),
    `"classic"` (the classic world database: Forever is classic content but may differ, so it's said),
    `"estimate"` (worked out from rules, e.g. kills per hour for a mob you never fought).
  - Your own numbers win over the database's; the database's are labelled as such.
  - No price, no number: an idea missing a price it needs is not ranked with a made-up one (it may be
    listed as "needs a price: open the auction house").
  - Prices carry their age; old prices (more than 3 hours: `P.STALE`) are greyed and lower an idea's
    confidence; prices from a friend say so.
  - What isn't sure is said ("~", "about", "estimate"), never rounded into certainty.
- **Never lag.** Nothing runs idle; events only note; work happens on a driver a few ms a frame
  (Margins' and Lodestar's patterns, docs/architecture.md's rule). A full auction house scan is read
  in slices. Ranking all ideas is done in steps, cached by revision, and only while the window or
  something that shows it is open.
- Lua 5.1: under 200 locals per chunk and 60 upvalues per function: keep a file's functions in its
  table.
- Secret values: `LT.Value`, `LT.IsSecret` (docs/forever-platform.md).
- Every user-visible text `L["..."]` with German (German gamer words), in `Locales/deDE.lua` under
  the WhyPoor? heading of its part (the headings are there).

## Contracts

All money in copper, times as `time()`, per hour as copper per hour of play.

### Prices (`W.Prices`, Prices.lua)

```lua
P.Vendor(item)        -- what a vendor pays for one (copper; 0: vendors don't buy it), nil while the client doesn't know it yet (asked for)
P.VendorBuy(item)     -- what a vendor asks for one: seen at a merchant, else Data/Recipes.lua's list; nil: not sold by vendors we know; 2nd: seen
P.Get(item)           -- nil: never seen on the auction house of this realm and faction; else {
                      --   low,    -- the lowest buyout for one at the last scan that covered it (nil: none listed then)
                      --   qty,    -- how many were listed then
                      --   seen,   -- when that was (time())
                      --   value,  -- the robust price: a time-weighted median of each day's lowest (up to 14 days); nil: too little
                      --   days,   -- how many days that rests on
                      --   sells,  -- 0..1: how likely a listing near value sells (from scans: listings gone before they could
                      --           -- expire, quantity going down; and my own sold/expired auctions); nil: not known
                      --   perDay, -- about how many sell a day; nil: not known
                      --   confidence, -- "high", "medium", "low" (few days, thin or unstable market, old)
                      --   unstable,   -- true: prices jump around too much to rank on
                      --   friend,     -- the friend's name when the newest data is theirs
                      -- }
P.AHSale(item, n)     -- what selling n on the auction house is expected to bring, after the 5% cut and the
                      -- deposit lost on what doesn't sell: copper, or nil (no price); 2nd: the unit price it assumes
P.Best(item, n)       -- the better way to sell n: "vendor" | "ah" | nil (neither known), the copper, and the reason key
P.Deposit(item, n)    -- the deposit for n (the game's when the auction house is open, else the rule), nil: unknown
P.IsOpen()            -- the auction house is open
P.LastScan()          -- when this realm's last full scan was
P.Items()             -- every item with auction house data on this realm and faction: a list of item IDs (the
                      -- ideas' flips go over it; shared, never written by callers)
P.Revision()          -- goes up when any price changed (for caches)
P.AH_CUT, P.STALE
```

### Crafts (`W.Crafts`, Crafts.lua)

```lua
Cr.Cost(item, n, opts) -- the cheapest way to get n: {
                       --   total, unit, how = "ah" | "vendor" | "craft" | "bags" | "mixed",
                       --   recipe = { spell, line } (how == "craft"), parts = { the same for each reagent },
                       --   complete (every part priced), oldest (oldest price used), basis
                       -- } or nil (no way known). opts: { who = the crafter's known spells (default: this
                       -- character's), bags = true (what's in the bags counts at what it would sell for),
                       -- depth = 4 (crafted reagents at most this deep; no loops) }
Cr.Recipe(spell, opts) -- a recipe's numbers like Margins' Compute (cost from Cr.Cost, revenue vendor/AH via
                       -- P.AHSale), plus verdict: "craft" | "sell reagents" | "no" and the reason
Cr.Mine()              -- this character's recipes worked out, best gold per hour first (for Methods)
```

### Money data (`W.Data`, Data.lua; the add-on's format in its README)

```lua
Dt.Load()               -- true when LefthyTools_MoneyData is loaded (loads it the first time)
Dt.Mob(creature)        -- { name, rank ("normal","elite","rare","rareelite","boss"), type ("Humanoid","Beast",...),
                        --   skin = "leather"|"herb"|"ore"|nil, reactA, reactH ("hostile","neutral","friendly"),
                        --   respawn (seconds), instance (true: in a dungeon or raid) } or nil
                        -- (drops, coin, levels, health: the drop data's, Bt.Known(creature))
Dt.Spots(creature)      -- { { map = uiMapID, x, y, r, n }, ... }: where it spawns, in clusters (x, y 0..1 on that map,
                        -- r its radius 0..1 of the map's width, n spawns); nil: nowhere outdoors known
Dt.MobsOn(map)          -- creature IDs that spawn on that zone map
Dt.Nodes(map)           -- gathering nodes on a zone map: { { object, kind = "herb"|"ore"|"chest"|"other", skill (needed),
                        --   loot = { { item, chance, min, max } }, spots = { clusters }, n }, ... }
Dt.Fishing(map)         -- { skill (needed to fish there without getaways), loot = { { item, chance } } } or nil
Dt.Pickpocket(creature) -- { { item, chance, min, max } } or nil
Dt.Disenchant(item)     -- { skill, results = { { item, chance, min, max } } } or nil
Dt.Limited(item)        -- vendors selling it in limited stock: { { npc, name, map, x, y, stock, restock, price } } or nil
Dt.LimitedItems()       -- every item some vendor sells in limited stock
-- (every chance in these lists is 0..1, as Bt.Known's: the ideas read them so)
```

### Context (`W.Context()`, Context.lua)

```lua
{ level, class (classFile), race (raceFile), faction ("Alliance"|"Horde"), gold (copper), map (uiMapID now),
  professions = { [skillLine] = rank }, -- gathering and crafting, Fishing, First Aid, Cooking, Lockpicking
  recipes = { [spell] = true },         -- this character's known recipes (Chronicle's record)
  canSkin, canHerb, canMine, canFish, canPick (rogue), canDisenchant,
  group (how many in my group, 1 alone), grouped, primaries (primary professions), freePrimary (fewer than two) }
```

### Ideas (`W.Ideas`, Methods.lua)

```lua
I.Get()         -- the ideas worked out last, ranked (a list, maybe empty), and whether they're up to date
I.Request()     -- (re)work them out for W.Context() if anything they rest on changed (prices, data, level,
                -- professions, place, recipes, your kills): on a driver a few ms a frame, never at once
I.Watch(fn)     -- fn() runs (on the next frame) whenever I.Get()'s list changed; the window redraws then
I.Revision()
-- an idea:
{ key,              -- stable ("grind:1234", "gather:herb:1439", "craft:3275", "sell:bags", ...)
  kind,             -- "grind" | "gather" | "fish" | "pickpocket" | "quest" | "craft" | "flip" | "vendorflip"
                    -- | "limited" | "disenchant" | "sell" | "learn" | "saving"
  title, sub,       -- localized one-liners
  perHour, once,    -- copper per hour (repeatable) or once (a one-off); one of them
  confidence,       -- "high" | "medium" | "low"
  basis,            -- the weakest basis it rests on (see Rules)
  why, how,         -- lists of localized lines: why it's here, what to do
  numbers,          -- lines of the working ({ label, value (text, "~" when not sure), basis, copper (money's) })
  items,            -- { { item, n (an hour for per-hour ideas, else how many), each, source ("ah","vendor","drop",...), age } }
  place,            -- { map, name, points = { { x, y, r } } } or nil (shown on a small map; "Show on map")
  needs,            -- what it needs that you don't have ("Skinning 1", "level 24")
  warnings,         -- lines ("prices 5 h old", "classic data: Forever may differ")
  oldest,           -- the oldest price used
  missing }         -- items it needs a price for (then it has neither perHour nor once: listed, not ranked)
```

### Goal (`W.Goal`, Goal.lua) and Bags (`W.Bags`, Bags.lua)

```lua
G.Current()   -- { name, cost, have, bags (what the bags would fetch), rate (copper per hour played, Chronicle),
              --   eta (hours), etaLevel, basis } or nil
W.Bags.List() -- { { item, count, best, value, vendor, ah, keep (a reason not to sell) } }, total
```

## Parts

### Prices

(to be written by the prices part)

### Friends' prices

(to be written by the prices part)

### The money data

(to be written by the data part)

### Crafting

(to be written by the crafting part)

### The ideas

`Context.lua` (`W.Context()`, its rules in `W.ContextParts`) and `Methods.lua` (`W.Ideas` = `I`, its parts
in `I.parts` for the tests). Every number below is a named constant at the top of Methods.lua.

**Who I am** (`W.Context()`, read from the game when asked, nothing kept): level, class and race files,
side, gold, the zone (`C_Map.GetBestMapForUnit`, a cave or city floor taken up to its zone), professions
(`C_SkillInfo.GetSkillLineInfoByID` for the money-making lines, Lockpicking too; without an answer the game's
`GetProfessions` list, a child line counted as its base), known recipes (Chronicle's record of this
character: `R.People`), the group (`GetNumGroupMembers`, else `IsInGroup`), how many primary professions
(two at most: Herbalism, Mining, Skinning and the six crafts) and so whether one is free; `canPick`:
Pick Pocket known (`C_SpellBook.IsSpellKnown(921)`), a rogue of level 4 or more when the game doesn't say.
A secret value is left out.

**The bases.** Each idea's `basis` is the weakest of what its number rests on, strongest first:
`yours`, `forever`, `prices`, `classic`, `estimate`. A vendor's sell price is the client's own fact
(`P.Vendor`): its number line says `forever`, but it doesn't weaken an idea (so your own kills valued at
vendor prices stay `yours`); an auction house price makes it `prices` (with its confidence and age). The
fixed rest between kills (below) doesn't weaken it either: it's said as its own number line (`estimate`)
and keeps every grinding idea at medium confidence or lower. Confidence starts high and only goes down:
classic data medium, an estimated pace low, a price's own confidence, a price older than `P.STALE` one
step (and a warning with the oldest price's age), a friend's price said, an item without any price one step
and a warning. A part worth less than 5% of an idea doesn't weigh on it. Numbers that rest on classic data
or estimates are written with "~" and two digits.

**No price, no number.** An item's worth is the better of a vendor (`P.Vendor`) and the auction house
(`P.AHSale(item, 1)`: after the cut and the deposit lost), the auction house only with a robust `value`
that isn't `unstable` or of low confidence. An item with neither counts as nothing and is said; when such
items make up a quarter or more of an idea's chances (or a craft's reagents aren't all priced, `complete
== false`), the idea gets `missing` (those items) and no `perHour`/`once`: listed after the others, not
ranked.

**Grind** (`grind:<creature>`), from `Dt.MobsOn` of the zone maps in `X.ZONES` (outdoor zones, no
capitals; a zone is looked at only when its quest levels, from Lodestar's data, come within 8 levels of
the window):

- *Which mobs*: not in an instance; hostile to your side (`reactA`/`reactH`), or neutral and a beast (a
  neutral humanoid may be a town's); not a critter, totem, pet or gas cloud; rank `normal` (`elite` only in
  a group, and then only with your own pace on it: a group's speed isn't guessed; never rares or bosses);
  its levels (the classic database's `health` range, else the Bestiary's) within the **window**: from one
  above classic's grey level (Lodestar's rule: such mobs still give experience) to one above yours (from
  two above, classic mobs miss you less, hit harder and resist more, so an even fight's pace no longer
  holds). Level 5: 1-6, 25: 19-26, 45: 36-46, 60: 52-61. At least 8 spawns on the map (`Dt.Spots`); the
  map where most of it spawns is its place (its three biggest clusters).
- *Worth per kill*: with 30 kills of your own (the Bestiary), yours: coin over kills, each item's count over
  kills, quest items (the database's flag) and greens or better the database doesn't list for that mob
  (world drops) left out. Else the classic database's (`Bt.Known`): the middle of its coin range (the drop
  data's `g=min-max`), each drop's chance once (the data has no stack sizes: said), quest items left out;
  world drops aren't in it (said on every grinding idea). Skinning when you have the line the corpse needs
  (`Dt.Mob().skin`: leather Skinning, herb Herbalism, ore Mining) and your skill reaches its highest level
  (classic's rule: below 100 skill (level - 10) x 10, from 100 on level x 5; skill 150 skins level 30, 300
  level 60): yours with 10 skinnings, else the database's chances.
- *Kills per hour* = 3600 / (fight + 20 s between kills + 2 s when skinning). The fight: your own pace on
  that mob (`Bt.Pace`, 5 timed kills at least, at your level or up to 3 below: you've only got stronger;
  the Bestiary is account-wide, so another character's counts); else its health at its middle level
  over your damage per second (the health of the mobs you killed at those levels over the time they took,
  10 timed kills at least: an estimate, said); else 35 s (an estimate on the slow side, said). Capped by the
  spawns: spawns x 3600 / respawn (said when it caps).
- In a group: said (loot shared, kills faster: the numbers are for playing alone).

**Pickpocket** (`pickpocket:<creature>`, rogues who can): a grinding mob's `Dt.Pickpocket` loot (chance x
the middle of its count), as many pockets an hour as its kills. Coin from pockets isn't counted (no rule
in the data for it: said).

**Learn** (`learn:<line>`), only with a free primary slot: Skinning, from the grinding mob whose skins add
the most an hour (kills slowed by the skinning), `needs` the skill its level takes; Herbalism or Mining,
from the zone whose nodes are worth the most at any skill, `needs` the highest node skill counted. One
idea per line, the best one.

**Gather** (`gather:herb|ore:<map>`) and **fish** (`fish:<map>`), only in zones whose quests start at
most two levels above yours (safe enough) and with the money data loaded: a node's worth is its loot's
chance x the middle of its count x the item's worth (a vein mined more than once isn't counted), averaged
over the zone's nodes at your skill weighted by how many there are, 20 nodes at least. Nothing measures
nodes an hour, so per hour uses 15 nodes (an estimate, low confidence, said). Fishing only where your
skill is at least the zone's (`Dt.Fishing().skill`: no getaways), 120 catches an hour (an estimate, said).

**Quest** (`quest:<id>`, once): Lodestar's quests open to you (`Q.Status` available or active, `Q.InRange`),
from every zone's list, with `Q.Rewards`: the money, the reward choice worth the most, and every reward
item; the basis `forever` for Forever's own quests, else `classic` (the money may be EG Link's, the data
doesn't say which). The place is the giver's (the ender's for one in your log); a group quest is said; at
level 60 it's said that a quest's money for its experience isn't counted. Needs Lodestar switched on: its
data add-on is loaded (`Q.Load`) on the first run, as Lodestar's own windows do. Which quests are open is
kept while Lodestar's data, your progress and level stay.

**Craft** (`craft:<spell>`, once): `Cr.Mine()`'s entries with `verdict == "craft"` and a profit (read:
`spell`, `item` (else `recipe.item`), `profit` (a craft's), `complete`, `basis`, `oldest`): the profit times
how many sell a day (`P.Get(item).perDay`, at least one); unknown: one, low confidence, said. Crafting's
real limit is how many sell, so it's not per hour.

**The market** (once, only listings from a scan younger than `P.STALE`, each said to maybe be gone):
**flip** (`flip:<item>`): an item that isn't unstable or low confidence, sells (`sells` 0.5 or more, one a
day or more), whose `P.AHSale` brings at least 1s and 15% more than the lowest listing; `P.AHSale`'s 2nd
answer (the unit price it assumes) must be above that listing. How many: those listed, at most a day's
sales. **Vendorflip** (`vendorflip:<item>`): listings at least 20c below what a vendor pays.
**Disenchant** (`disenchant:<item>`, enchanters): a listing below what disenchanting it gives at your skill
(`Dt.Disenchant`: each result's chance x the middle of its count x its auction house worth, every result
priced there), at least 1s and 15% more, five at most; and `disenchant:bags`: what in your bags
(`W.Bags.List()`, not kept) is worth more disenchanted than its sale (`value` / `count`).
**Limited** (`limited:<item>`): `Dt.Limited` vendors not hostile to your side (`Dt.Mob(npc)`), the vendor's
price (a merchant's seen price, `P.VendorBuy`'s 2nd answer, wins), at least 1s and 15% under its
auction house sale; how many: the stock, at most a day's sales; its place the vendor's.

**Sell** (`sell:bags`, once): `W.Bags.List()`'s total and its five most valuable entries (an entry's
`value` taken as the whole stack's).

**Ranking.** Ideas with `perHour` first, by perHour x 1 (high), 0.75 (medium) or 0.5 (low); then the
once-ideas the same way; then those that need a price. At most 6 grind, 3 gather, 2 fish, 3 pickpocket,
8 quest, 5 craft, 6 flip, 5 vendorflip, 5 limited, 4 disenchant, 4 learn, 1 sell. `idea.rank`, `score`
and `group` (1, 2, 3) say where it stands. An idea whose place is in your zone says so first in `why`.

**The driver.** Nothing runs before the first `I.Request()`; then its events (level, skills, zone, group,
spells learned; bags and item names apart) and the Bestiary's changes only count. A request shows a
driver frame; on the next frame it compares the key of what the list rests on (those counts, `P.Revision`,
Chronicle's recipes, Lodestar's data and progress) with the published list's: nothing changed, it hides
again. Else a run starts (one that only prices or bags moved waits until 5 s after the last start, with
one timer, hidden meanwhile; a level, a skill, the zone or the group start it at once). A run is phases of
units (a Bestiary record, a zone's mob, a zone, a quest, an auction house item), as many a frame as fit in
3 ms (`debugprofilestop`; 30 where there's none), through `LT.Guard`: an error is reported once and drops
the run. The grinding candidates (the zone scan) are kept while your level, side, group, the money data
and the number of kinds in the Bestiary stay. When the run's list differs from the last (keys, numbers,
confidence, basis, texts, warnings), `I.Revision()` goes up and `I.Watch` callbacks run on the next frame;
then the frame hides. The window calls `I.Request()` when it opens and whenever it redraws or refreshes
while it shows the ideas: it costs nothing when nothing changed.

Open questions (in game, and data not verifiable here): whether every kill drops coin uniformly between
the data's min and max (CMaNGOS's loot code does); classic's skinning rule on Forever; Forever's fishing
skill per zone; the estimates (20 s between kills, 35 s a fight, 15 nodes and 120 catches an hour) against
real play; quest money at level 60.

### The window, bags, tooltip and goal

(to be written by the window part)
