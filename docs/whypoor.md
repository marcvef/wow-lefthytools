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
  numbers,          -- lines of the working ({ label, value, basis }; value: a text, shown as given)
  items,            -- { { item, n, each, source ("ah","vendor","drop",...), age } }
  place,            -- { map, name, points = { { x, y, r } } } or nil (shown on a small map; "Show on map")
  needs,            -- what it needs that you don't have ("Skinning 1", "level 24")
  warnings,         -- lines ("prices 5 h old", "classic data: Forever may differ")
  oldest }          -- the oldest price used
```

### Goal (`W.Goal`, Goal.lua) and Bags (`W.Bags`, Bags.lua)

```lua
G.Current()   -- { name, cost, have, bags (what the bags would fetch), rate (copper per hour played, Chronicle),
              --   eta (hours), etaLevel, basis } or nil; also key, level, spell, about (the cost isn't the
              --   game's), seen, played/how/xp (what the rate rests on), mounts (seen at vendors)
G.Why()       -- why there's no goal: "class", "done", nil
W.Bags.List() -- { { item, count, best, value, vendor, ah, keep (a reason not to sell) } }, total (entries also:
              -- bound, unit (the AH price for one), price (P.Get's), quality, link); W.Bags.Total()
W.Money(c), W.Age(t) -- "1g 20s", "2 h" (WhyPoor.lua, for every part)
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

(to be written by the ideas part)

### The window, bags, tooltip and goal

**The module** (WhyPoor.lua): the settings page (Window: Open, Minimap button; Bags and tooltips:
`tooltip`, `bagCoins`; Friends: `sharePrices`), `/whypoor` (open or close; `ideas`, `bags`, `market`,
`goal`: the window there; `minimap`, `settings`, `help`) and `/lefthy whypoor ...` (the same), the minimap
button `LefthyToolsWhyPoorMinimapButton` (a coin; `LT.Window.MinimapButton`, so it joins the combined
LefthyTools button; click: the window, right-click: Bags; its tooltip: the goal's line). `W.Money(copper)`
("1g 20s", "35s 2c", "8c"; whole gold from 100g on and without a zero part: "34g", "3s") and `W.Age(t)`
("5 min", "2 h", "3 d") are there for every part.

**The window** (Window.lua, `W.Window`: `Open(tab)`, `Toggle()`, `Shown()`, `GoalLine()`, `View()` for the
tests): `LefthyToolsWhyPoorFrame`, 780 x 480 (scaled down on a small screen), a frame of our own dressed
like Lodestar's companion (`LT.Window.Dress`): "WhyPoor?", the tabs Ideas | Bags | Market and the X in one
26 px row; the goal's strip under it (one line; a click shows the goal's details); a line about the list,
the list (300 px; rows of two lines: icon, title, money at the right; what it rests on and the idea's `sub`,
three dots for its confidence) and the details on the right (scrolling; never empty: nothing picked, the
goal). In UISpecialFrames (Escape) and `LT.Window.Register`ed, DIALOG strata, like Lodestar's big window;
its place and tab are kept (`db.window.left`, `top`, `tab`).
- *Ideas*: `I.Get()` as it comes (its order). Money: `~3g 20s/h` or `12g once`; "~" unless the confidence
  is high and the basis isn't `estimate` or `classic`; grey when `oldest` is older than `P.STALE`; "needs a
  price" without a number. Details: title, `sub`, money, "Confidence: ... · rests on: ..." (the basis in
  words), needs (red), warnings (orange), Why, How, The working (`label: value (basis)`; the value shown as
  Methods wrote it), Items (icon, name x n, `each`, where from, age: orange when old), the place on
  Lodestar's small map (`Q.NewMiniMap`; each point an area of radius `r`) and "Show on map" (`Q.ShowPlace`).
- *Market*: the ideas of kind flip, vendorflip, limited, disenchant; its line: the auction house open, else
  the last scan's age (orange when stale), else "No auction house prices yet: open the auction house".
- *Bags*: `W.Bags.List()`, best first; the line: what the bags would fetch. Details: both ways, the price's
  age, friend, how well it sells (percent), confidence, unstable, the vendor's (or "Vendors don't buy it"),
  the reason to keep.
- Empty and loading: a message in the list ("Working them out...", no ideas, no deals, nothing to sell).
- Costs: built at the first opening. While shown: `I.Request()` when it opens and every 10 s (a child
  frame's OnUpdate); `PLAYER_MONEY`, `BAG_UPDATE_DELAYED` and the auction house's show and close noted and
  drawn on the next frame; `I.Watch` (registered at the first request, once per `W.Ideas`) drawn on the
  next frame. The list lays only the rows in sight (Lodestar's pattern). Hidden: no events, no OnUpdate,
  `I.Watch` only notes. Tabs, rows, the strip, item rows, the map's markers and the buttons are plain
  Buttons (the controller's cursor).
- A "WhyPoor?" button (80 x 20) on the auction house's window, 110 px from its top right (left of
  Margins'), made the first time the auction house opens (`AUCTION_HOUSE_SHOW`, on the next frame): the
  window on Market.

**Lodestar's big map** (`Q.ShowPlace(map, points)`, Browser.lua): opens the big window on the zone page
of the first point (city floors and caves: their zone, `Map.PlaceOfSpot`), the map brought to the points
(one: zoomed in to it), pulsing for three seconds, no quest picked. False without points or the quest data.

**Bags** (Bags.lua): `List()` reads bags 0 to `NUM_TOTAL_EQUIPPED_BAG_SLOTS` (the reagent bag; never the
bank), one entry per item (bound and unbound copies apart), `count` added up. Unbound: `ah` =
`P.AHSale(item, count)`, `best, value` = `P.Best(item, count)`. Bound: no auction house, the vendor's.
Reasons to keep: a quest item whose quest is in your log; any other quest item unless Lodestar's
`Q.ItemMarked` says no quest needs it; soulbound gear you can use (`C_PlayerInfo.CanUseItem` where the
client has it) whose item level isn't below the weaker of what you wear in its slot(s) (an unknown level or
an empty slot: kept). The total adds up the items without a reason. Kept until the bags, your gear, quests,
item data or `P.Revision()` change (the events only bump a counter).

**The tooltip line** (`tooltip`): a TooltipDataProcessor post-call on item tooltips, `GameTooltip` only.
Where it is: the game's tooltip data (`GetProcessingTooltipInfo()`) with the getter `GetBagItem` and a bag
0..5 (another bag is the bank's: nothing); else the owner's `GetBagID()` 0..5; else an owner inside
`AuctionHouseFrame` while it's shown. Nowhere else (chat links, vendors, loot, quest rewards). One line,
for one item: "WhyPoor?: AH 12s (2 h, Anna, sells well) · vendor 3s (each)". The AH part is the unit price
`P.AHSale` assumes, "~" unless its confidence is high and it's stable, then the age, the friend, "sells
well" (`sells` >= 0.6), "sells slowly" (<= 0.25) or "jumps around" (unstable); then "vendor 3s" or "no
vendor"; the better way (`P.Best(item, 1)`) white, the other and an old AH price (`P.STALE`) grey; "(each)"
for a stack. Bound: the vendor part only. Nothing known: no line. Lines are kept per item, bound and stack
until `P.Revision()` or the bags change or the minute turns.

**The coin** (`bagCoins`): Misc Tweaks' sorted bags (GamepadBags.lua) have a small API for corner marks:
`ns.GamepadBagsMark(key, { texture, test(itemID, bag, slot), size, point, x, y, alpha })` (nil removes it)
and `ns.GamepadBagsRefresh()` (asked again on the next frame); the marks are drawn on its frame over
Blizzard's button after each layout, like its quest mark (`ns.GamepadBagsState().corners[key][button]` for
the tests). WhyPoor?'s is the gold coin (`Interface\MoneyFrame\UI-GoldIcon`, 12 px, top right) on items
whose best is the auction house, not kept and not bound (`W.Bags.Coin`: a lookup in `List()`'s result).

**The goal** (Goal.lua): one goal at a time, by the spells known: no riding (Apprentice Riding 33388, the
old racial riding spells 824, 825, 826, 828, 10861, 10906, 10907, 18995, or Forever's Galestrider Riding
1285849, all in Forever's riding skill line 762) is "Mount" (level 40, spell 33388); else, without
Journeyman Riding (33391), "Epic mount" (level 60). Paladins and Warlocks get none (`G.Why()` "class"),
Journeyman known neither ("done").
- *The cost*, best first: what a riding trainer's window showed for that spell (`TRAINER_SHOW` and
  `TRAINER_UPDATE` noted, read on the next frame: `GetTrainerServiceInfo(i)`'s name equal to the spell's
  name from `C_Spell.GetSpellInfo`, `GetTrainerServiceCost(i)`), with its reputation discount already in,
  kept per character (`db.goal[GUID].costs[spell] = { cost, seen }`), basis `forever`; else about what
  guides say for WoW: Forever (100g for Apprentice Riding with the first mount, 1000g for Journeyman;
  method.gg, November 2026): `about`, basis `estimate`, and the details ask you to visit a trainer.
  Mount vendors' prices (`MERCHANT_SHOW`/`UPDATE`: item class 15, subclass 5, for gold) are kept too
  (`mounts[item] = { price, seen, quality }`) and listed in the details (rare ones for the mount, epic
  ones for the epic mount). Forever's item data (ItemSparse, build 1.60.1.70938) has 20g for the level-40
  mounts and 200g for the epic ones before discounts, which the details say.
- *The rate* (`G.Rate()`): Chronicle's days (`daily[day].played`, `.gold`: whole gold at the day's end,
  `.xp`): from today back, each day with the day before it, at most 7, while they have both; the net change
  is the gold now (`GetMoney()`) less the gold at the end of the day before the first (+0.5g: the middle
  of that whole gold), over their time played; it needs 3 hours of play. Else this session's
  (`C.Session()`: money and XP over time played, at least 20 minutes). Else none (and none with Chronicle
  off).
- *When* (`eta`): what's left over the rate, in hours played, only while the rate is above 0. *The level
  then* (`etaLevel`): the XP per hour of the same span through the classic XP table (CMaNGOS
  `player_xp_for_level`, levels 1-59), only while that table's number for your level is the game's
  `UnitXPMax`; rested XP isn't counted; at most the level cap (`GetMaxPlayerLevel`, else 60).
- The strip: "Mount: 34g of ~100g · ~7g 83s/h · at this rate at level 34" (or "at this rate in 8 h
  played" without a level; "you have enough"; "not growing lately"); the details: the cost and where it's
  from, what mounts cost, what you have and what the bags would fetch, what's still to go, the rate and
  how much play it rests on. `G.Current()` is kept a second (and forgotten on money, bag, spell, level,
  trainer and merchant changes).

Not verified in game yet: the riding trainer's service names on Forever (matched by the spell's name),
whether Paladins and Warlocks skip the riding costs, whether the first mount comes with Apprentice Riding,
`GetProcessingTooltipInfo` on Forever's bag tooltips (else the owner check does it), and whether the
auction house's result rows (the tooltips' owners) are inside `AuctionHouseFrame`.
