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
Dt.Load()               -- true when LefthyTools_MoneyData is loaded (loads it the first time; the others load it too)
Dt.Mob(creature)        -- { name, rank ("normal","elite","rare","rareelite","boss"), type ("Humanoid","Beast",...),
                        --   skin = "leather"|"herb"|"ore"|nil, reactA, reactH ("hostile","neutral","friendly": to a new
                        --   character of that side; nil unknown), respawn (seconds), instance (true: only in a dungeon or
                        --   raid), civilian, rep (its faction's ID when it reacts by reputation: killing it costs
                        --   standing; never suggest one that isn't hostile), seenA/seenH (that reaction is what players
                        --   saw on Forever), basis = "classic" } or nil
                        -- (drops, coin, levels, health: the drop data's, Bt.Known(creature))
Dt.Spots(creature)      -- { { map = uiMapID, x, y, r, n, up }, ... }: where it spawns, in clusters (x, y 0..1 on that map,
                        -- r its radius 0..1 of the map's width, n spawn points, up about how many are up at once:
                        -- pools); nil: nowhere outdoors known
Dt.MobsOn(map)          -- creature IDs that spawn on that zone map
Dt.Nodes(map)           -- gathering nodes on a zone map: { { object, name, kind = "herb"|"ore"|"chest"|"fish" (a school),
                        --   skill (needed: Herbalism, Mining, a locked chest's Lockpicking, 0 anyone; a school: the
                        --   zone's fishing), respawn, uses = { min, max } (times one node can be looted),
                        --   loot = { { item, chance, min, max } }, spots = { { x, y, r, n, up } }, n, up, basis }, ... }
Dt.Object(object)       -- one of those objects: { name, kind, skill, respawn, uses, loot } or nil
Dt.Fishing(map)         -- { skill (to fish there without getaways: base + 95), low (the least that catches anything),
                        --   base, loot = { { item, chance, min, max } }, areas = { { area, name, skill, low, base, loot } }
                        --   (subzones that differ), basis } or nil
Dt.Pickpocket(creature) -- { { item, chance, min, max } } or nil
Dt.Disenchant(item)     -- { skill (Enchanting), results = { { item, chance, min, max } }, basis } or nil
Dt.Limited(item)        -- vendors selling it in limited stock: { { npc, name, map, x, y, reactA, reactH, stock,
                        --   restock (seconds), price (copper for count items), count, basis ("forever"|"classic") } } or nil
Dt.LimitedItems()       -- every item some vendor sells in limited stock (sorted)
Dt.IsLoaded(), Dt.Problem() (why it isn't there: "MISSING", ...), Dt.Info() ({ source, build })
-- loot entries may carry event = true (only while a game event is on) or side = "Alliance"|"Horde" (only for it)
```

### Context (`W.Context()`, Context.lua)

```lua
{ level, class (classFile), race (raceFile), faction ("Alliance"|"Horde"), gold (copper), map (uiMapID now),
  professions = { [skillLine] = rank }, -- gathering and crafting, Fishing, First Aid, Cooking, Lockpicking
  recipes = { [spell] = true },         -- this character's known recipes (Chronicle's record)
  canSkin, canHerb, canMine, canFish, canPick (rogue), canDisenchant, ... }
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
  numbers,          -- lines of the working ({ label, value, basis })
  items,            -- { { item, n, each, source ("ah","vendor","drop",...), age } }
  place,            -- { map, name, points = { { x, y, r } } } or nil (shown on a small map; "Show on map")
  needs,            -- what it needs that you don't have ("Skinning 1", "level 24")
  warnings,         -- lines ("prices 5 h old", "classic data: Forever may differ")
  oldest }          -- the oldest price used
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

`LefthyTools_MoneyData` (GPL v3, made by `tools/update-money-data.js`; its README has every field's
source and rule) holds what the drop data doesn't: the creatures worth farming with their reactions and
spawns, gathering nodes per zone map, fishing per zone, pickpocketing, disenchanting and limited vendor
stock. About 0.7 MB; its tables stay strings.

- **Loading.** `Data.lua` loads it with `C_AddOns.LoadAddOn` the first time any accessor is asked (never
  at login; asked once: a missing or disabled add-on gives `Dt.Problem()`, the game's reason; one loaded
  meanwhile by someone else is taken). Each entry is read when first asked and kept (`Dt.cache`, per
  table); nothing walks the whole data but `Dt.LimitedItems()` (once, ~300 items) and `Dt.Fishing`'s
  subzones (once per map, ~80 rows). `Dt.Use(data)` is the tests' hook.
- **What rests on what.** Everything is classic-db's (`basis = "classic"`), except: zone maps and
  positions (Forever's client tables, the quest data's placement rules), gathering skills (Forever's
  `Lock` table), which items can be disenchanted and the skill (Forever's `ItemDisenchantLoot`, item
  quality, level and flags), prices with `basis = "forever"` (Forever's ItemSparse), and reactions with
  `seenA` / `seenH` (what players' games saw on Forever, EG Link). Respawn times, loot chances, pools
  and fishing rules are classic's: Forever may differ.
- **Reactions.** Worked out as the client does (faction templates, or by reputation from a new
  character's standing, every race and class of the side, the friendliest when they differ); where
  players saw a creature of a faction without reputation react one way, that wins (4 creatures in this
  build: the Mesa Buzzards are hostile to the Horde on Forever). EG Link agrees with the worked-out
  reaction for 674 creatures. A creature of a faction with reputation (`rep`) costs standing: such a creature is
  in the data only when it's hostile to one side, and the ideas must not suggest killing one that isn't
  hostile to the player's side (a city's guards are hostile to the other side, and dangerous).
- **Counts.** A cluster's `n` is spawn points, `up` how many are up at once (classic's pools: herbs and
  veins are pooled, Elwynn Forest has 81 Silverleaf spawn points, about 12 up). For an estimate of nodes
  or mobs per hour, `up` is the number to use.
- **Fishing.** CMaNGOS' rule: skill ≥ base catches with (skill − base + 5)%, sure from base + 95.
- **Disenchanting.** Forever's client asks no Enchanting skill beyond knowing it (SkillRequired 0 in
  every row); Forever made some classic white items green, which can be disenchanted there.
- **Left out** (each counted when the tool runs): critters, totems, triggers, unattackable and unused
  creatures, ones with nothing to loot, ones only at events or in battlegrounds, ones friendly to both
  sides; loot of quests and scripts, items the client doesn't know; Forever's own creatures and items
  that classic-db doesn't have.
- **Checks.** The tool checks samples before it writes (Peacebloom and Silverleaf Herbalism 1,
  Mageroyal 50, Briarthorn 70, Copper 1, Tin 65, Silver 75, Iron 125, Mithril 175; Stormwind and
  Ironforge guards friendly to the Alliance and hostile to the Horde, Orgrimmar Grunts and Undercity
  Guardians the other way round; Booty Bay's bruisers left out; Elwynn's and Stranglethorn's fishing;
  disenchanting results; a limited pattern at its vendor), and `tests/whypoor_data.lua` reads every entry
  of the real file into the contract's shapes and checks the same facts through `W.Data`, plus a small
  fixture through every accessor.

### Crafting

(to be written by the crafting part)

### The ideas

(to be written by the ideas part)

### The window, bags, tooltip and goal

(to be written by the window part)
