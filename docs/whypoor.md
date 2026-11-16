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
| `Bags.lua` | each bag item's best sale (the Bags tab, the ideas) | `W.Bags` |
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
                      --   low,    -- the lowest buyout for one at the last scan that covered it, whole copper (nil: none
                      --           -- listed then; 0: under half a copper each); my own listings left out
                      --   qty,    -- how many were listed then
                      --   seen,   -- when that was (time())
                      --   value,  -- the robust price: a time-weighted median of each day's lowest (up to 14 days); nil: too little
                      --   days,   -- how many days that rests on
                      --   sells,  -- 0..1: how many of my own auctions of it sold, of those that sold or expired (the game's
                      --           -- notifications; 3 at least, any price); nil: not known
                      --   perDay, -- about how many leave the auction house a day before they could expire: bought OR taken
                      --           -- back (scans can't tell them apart), from full scans of one session; nil: not known
                      --   confidence, -- "high", "medium", "low" (few days, thin or unstable market, old)
                      --   unstable,   -- true: prices jump around too much to rank on
                      --   friend,     -- the friend's name when the newest data is theirs
                      -- }
P.AHSale(item, n)     -- what selling n on the auction house is expected to bring, after the 5% cut and the
                      -- deposit lost on what doesn't sell: copper, or nil (no price); 2nd: the unit price it assumes;
                      -- 3rd: the sell chance used (nil: not known, so it's what n bring IF they sell, no deposit lost);
                      -- 4th: the deposit counted (nil: none)
P.Best(item, n)       -- the better way to sell n: "vendor" | "ah" | nil (neither known), the copper, and the reason key
P.Deposit(item, n)    -- the deposit for n: the game's when the auction house is open (2nd "game"), else what the game
                      -- said for this item before (2nd "seen"); nil: unknown (no rule of its own)
P.IsOpen()            -- the auction house is open
P.LastScan()          -- when this realm's last full scan was
P.Items()             -- every item with auction house data on this realm and faction (mine or a friend's): a new
                      -- sorted list of item IDs (the ideas' market pass goes over it)
P.Revision()          -- goes up when any price changed (for caches)
P.AH_CUT, P.STALE
-- Also (Margins and tests): P.AHPrice(item) ({ p, q, t }: Margins' old shape), P.ScanItems(items, { front, spell }),
-- P.ScanFull(fallback), P.Status(), P.Cancel(), P.Busy(), P.Refresh(), P.levelHint (a function: gear's item level),
-- P.Decode / P.Encode (an item's saved text), P.Today()
```

### Crafts (`W.Crafts`, Crafts.lua)

```lua
Cr.Cost(item, n, opts) -- the cheapest way to get n: {
                       --   item, n, total, unit, how = "ah" | "vendor" | "craft" | "bags" | "mixed",
                       --   recipe = { spell, line, yield, data } (how == "craft"), crafts (n / yield: may be a
                       --   fraction), parts = { the same for each reagent; one without any way: { item, n,
                       --   complete = false } }, bags = { n, total, way } and rest (the rest's answer) for "bags"/
                       --   "mixed", complete (every part priced; false: total isn't a cost), oldest (oldest AH price
                       --   used), basis (the weakest), friend, seconds (the casts of it and below; 0: bought),
                       --   castKnown, few (an AH-bought part has fewer listed than for 5), q, mayVary (a craft
                       --   making several: the data's count is the middle of a range when it varies)
                       -- } or nil (no way known). opts: { who = the crafter's known spells { [spell] = true }, or
                       -- crafter = an R.People entry (that character's recipes of every profession; default: this
                       -- character's), bags = true (what's in the bags counts at what it would sell for; default
                       -- off), depth = 4 (crafted reagents at most this deep; no loops) }
Cr.Recipe(spell, opts) -- a recipe's numbers like Margins' Compute (cost from Cr.Cost, revenue vendor/AH via
                       -- P.AHSale), plus verdict: "craft" | "sell reagents" | "no" | nil (not known: a price
                       -- missing), reason ("profit", "reagents", "loss", "price") and why (its localized line).
                       -- opts: Cost's, and recipe, line (when the caller has them); r.who = opts.crafter
Cr.Mine(ms)            -- this character's recipes worked out (Cr.Recipe each), best gold per hour first, those
                       -- without a number last; and done: works ms (default 2) a call and goes on at the next
                       -- call; until done it answers the last list (empty the first time) and false. Cached by
                       -- Cr.Revision() (a list waiting for items' data: again 5 s later)
Cr.Revision()          -- the prices' and the recipes' revisions together
Cr.Walk(cost, fn)      -- fn(step, level) for an answer and every step below it
Cr.AHBuy, Cr.VendorBuy, Cr.VendorSell, Cr.AHSale, Cr.SaleValue, Cr.CastTime, Cr.KnownOf(id), Cr.MyId()
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
I.Get()         -- the ideas worked out last, ranked (a list, maybe empty), and ready: a run finished and none is
                -- working now (what they rest on may have changed since: then the next run comes by itself)
I.Progress()    -- { step, steps } while a run works (nil when none), and whether the last run failed
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
              --   eta (hours), etaLevel, basis } or nil; also key, level, spell, about (the cost isn't the
              --   game's), seen, played/how/xp (what the rate rests on), mounts (seen at vendors)
G.Why()       -- why there's no goal: "class", "done", nil
W.Bags.List() -- { { item, count, best, value, vendor, ah, keep (a reason not to sell) } }, total (entries also:
              -- bound, unit (the AH price for one), price (P.Get's), quality, link); W.Bags.Total()
W.Money(c), W.Age(t) -- "1g 20s", "2 h" (WhyPoor.lua, for every part)
```

## Parts

### Prices

`Prices.lua` (`W.Prices`, `P`) is the suite's one auction house engine: Chronicle's Margins reads its prices
from it and asks it to scan (chronicle.md, Crafting margins). It runs while WhyPoor? or Chronicle's `margins`
setting is on (`P.Refresh`, looked at again after every module switch through a post-hook on
`LT:ApplyModuleState`, and by Margins' own switches); off, no event is registered and nothing runs.

**Saved** (`LefthyToolsWhyPoorDB.prices`, account-wide), kept small: an item's history is one string, numbers
in base 36 (`P.B36`, `tonumber(s, 36)`), since the game writes every array element of a saved table on a
line of its own.

- `houses["<realm>-<faction>"]`: each auction house its own. `items[item] = "<seen>,<low>,<qty>;<day>,<low>,<qty>;..."`:
  the last scan that covered it (low empty: none listed), then the lowest for one and how many of each day
  (`day` = `time() / 86400`, newest first, 14 at most); `flow[item]` (listings gone early, below),
  `own[item]` (my auctions sold and expired, per day), `friends[item]` (Friends' prices), `scan` (the last
  full scan read), `friendScan` (the newest friend's data taken).
- `replicated`: when ReplicateItems was last asked (one for all houses: the game's limit isn't documented as
  per realm, so the safe reading).
- `vendor[item]`: what a merchant asked for one, in gold only (`C_MerchantFrame.GetItemInfo`'s `price` for
  `stackCount`, not `hasExtendedCost`), every item a merchant's window showed, any realm. It's the price this
  character was asked: a reputation discount is in it.
- `posted[auctionID]`, `deposit[item]`: below. `imported`: Margins' old prices taken over.

**Margins' old prices** (`LefthyToolsDB.margins`: `ah[house][item] = { p, q, t }`, `vendor`, `replicated`) are
taken over once when the engine first starts (each price as its scan and as a day of history), then
`LefthyToolsDB.margins` goes.

**Which auction house.** My faction's, `"<realm>-<faction>"`; opened in Stranglethorn Vale, Tanaris or
Winterspring (classic uiMapIDs 1434, 1446, 1452, also as a parent of the map I'm on), where classic's three
neutral auction houses are (Booty Bay, Gadgetzan, Everlook), it's `"<realm>-Neutral"` (looked at on the
frame after `AUCTION_HOUSE_SHOW`, and at once by a scan). Neutral prices are kept apart and not used by
`P.Get` (whose cut there is unknown, below).

**Scanning**, only with the auction house open, never in a fight (`LT.InFight`), on the driver frame (hidden
while there's nothing to do):

- Item by item (`P.ScanItems`): `C_AuctionHouse.SendSearchQuery(itemKey, price ascending, true)` one at a time,
  0.65 s apart (the game takes 100 a minute) and only when `IsThrottledMessageSystemReady` isn't false; the
  answer read 0.2 s after its event: the first 50 rows' lowest for one, my own auctions left out
  (`numOwnerItems`, `containsOwnerItem`), and the listed quantity; no rows: none listed; no answer in 3 s: the
  price stays. Gear is searched with its item level (`GetDetailedItemLevelInfo`, else `P.levelHint`: Margins'
  recipe's). Margins' recipe checks and its fallback use this.
- **On opening** (`AUCTION_HOUSE_SHOW` sets `P.autoScan`; the driver's next tick, never in a fight): a whole scan
  (`P.ScanFull()`) when WhyPoor? is on, its setting `autoScan` (on) and the game allows one again; Margins alone
  scans only when its button asks, as before. `P.Status()` says what's going on (`running`, `kind`, `waiting`
  for the game's answer, `done` of `total` rows read, `committing` while it's kept, `nextFull`): the window's line.
- Everything (`P.ScanFull`): `ReplicateItems` when the last one was 15 minutes ago or more (the game's limit,
  saved), then `REPLICATE_ITEM_LIST_UPDATE`, then every row read in a coroutine 2 ms a frame (a look at the
  clock every 50 rows): `GetReplicateItemInfo(i)` (0-based) gives a stack's `count` and `buyoutPrice` (for the
  whole stack), the `owner` and the `itemID`; rows without a buyout (bids only) aren't counted; my own
  (`owner` is my name) count in how many are listed, not in the lowest. Then it's kept, also in slices: every
  item in it, and every item known here that wasn't (none listed); an item not seen for 14 days goes. The
  auction house closing while the rows are read drops the scan; once they're read it's kept. No answer in 30 s
  or no rows: the caller's fallback items, searched one by one.
- A price for one is rounded to whole copper (0: under half a copper each).

**History and judgement** (`P.Get`):

- `value`: the time-weighted median of the daily lows of the last 14 days, each day weighing
  `0.5 ^ (age in days / 7)` (aux's way of judging a price: the daily minimum buyout, a weighted median; the
  weights are ours). One day is enough for a value; `days` says how many it rests on, `confidence` how sure.
- `unstable`: with three or more days, the median distance of the lows from their median is more than half
  of it; with two, one is more than three times the other.
- `confidence`: `"high"` with 4+ days, not unstable, the last scan at most 3 hours old (`P.STALE`) and 3+
  listed; `"medium"` with 2+ days, not unstable, at most a day old; else `"low"`. A friend's data is never high.
- `perDay` (bought **or** taken back: a scan can't tell them apart): two full scans of the same house in one
  session, 15 minutes to 48 hours apart, are compared. A listing (`count`, `buyoutPrice`, `owner`) of the first
  whose time left (`GetReplicateItemTimeLeft`'s band) was at least the time between the scans (the band's
  shortest time, `GetTimeLeftBandInfo`) couldn't have expired; if it's missing from the second, it left early.
  What a named seller lists anew of the item counts against what they had leave (relisting, undercutting), so
  only the rest is gone. Per day the gone quantity and the seconds watched add up (`flow`); `perDay` = gone x
  86400 / seconds once at least 2 hours were watched. The listings of the last full scan are kept in memory
  only (100,000 at most), so it needs two full scans in one session. A buyer taking part of an anonymous
  listing counts it all as gone.
- `sells` (my own auctions, any price): the game's `AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION`
  (`AuctionSold` 4, `AuctionExpired` 5, the item's name, maybe the auction's ID): Blizzard_Game routes it on
  every client of the Mainline family (Forever's too) to the "A buyer has been found..." / "...has expired"
  chat line, so it comes anywhere, not only at the auction house. Matched by the ID to `posted` (my auctions as
  `GetOwnedAuctionInfo` listed them: item, quantity, house; asked for with `QueryOwnedAuctions` after
  `AUCTION_HOUSE_AUCTION_CREATED`, and read on every `OWNED_AUCTIONS_UPDATED`), else by the name to the oldest
  such auction, else by the name to the item (`C_Item.GetItemInfo(name)`, an item the client knows). An owned
  auction listed as `Sold` counts too; each auction once; `AUCTION_CANCELED` ones never. `sells` = sold / (sold
  + expired) over 14 days, from 3 outcomes on. Posted auctions are forgotten after 3 days. Mail subjects and
  chat lines aren't read (the notification is the typed source).

**Selling** (`P.AHSale`): the unit price is the lower of the last scan's lowest and the value (the value alone
when none is listed). With `sells` and the deposit known: `sells x n x unit x 0.95 - (1 - sells) x deposit`
(the deposit comes back when it sells); else `n x unit x 0.95`, and the third result (nil) says it assumed a
sale. `P.Best`: the vendor's `n x sell price` (`C_Item.GetItemInfo`'s 11th) against that: `vendor-more` (a tie
too: certain money), `ah-more`, `vendor-only`, `ah-only`, `ah-unstable` (vendor), `no-price`.

**The deposit** (`P.Deposit`): open, the game's: `CalculateItemDeposit(location, duration, n)` for an item in my
bags that isn't a commodity (`GetItemCommodityStatus`), else `CalculateCommodityDeposit(item, duration, n)`;
the duration is the one last picked in the auction house (its CVar `auctionHouseDurationDropdown`, as Blizzard's
sell frame reads it; 1 when unset), rounded up to silver when `SupportsCopperValues()` is false (as the sell
frame shows it). The game's answer for one and for n is kept per item and duration; closed, that one for the
same n, or scaled when the game's deposit for n was exactly n times the one for one. No rule of our own:
otherwise nil.

**Pruning**: when the engine starts, a job over frames drops items and friends' prices not seen for 14 days,
days older than 14 in `flow` and `own`, posted auctions older than 3 days, broken entries, and houses with
nothing left. It goes over copies of the keys and never alongside a scan.

**Open questions** (not verified in game): the cut at a neutral auction house (classic's 15%? `P.AH_CUT` is
5%, so neutral prices are kept apart); whether `GetReplicateItemInfo` gives `owner` on Forever (without it,
relisting isn't recognised); whether a replicate row's `buyoutPrice` is the stack's on Forever as on retail
(Margins assumed it); whether the notifications carry the auction's ID; whether `ReplicateItems`' 15 minutes
are per account or per realm; random-suffix gear ("of the Monkey") shares one item ID, so its lowest is the
lowest of any suffix.

### Friends' prices

`Share.lua` (`W.Share`): auction house prices between friends over Beacon's B family, WhyPoor?'s letter `w`
(docs/beacon.md has the words). Only to builds from `PRICES_SINCE` on (their `V2`; older builds ignore an
unknown B word anyway, so nothing breaks), only while WhyPoor? is on with `sharePrices` (both ways: off, nothing
goes out and nothing is taken) and Beacon is on. Beacon takes at most 300 a minute from one friend; its tick
hands them to `B.TickPrices`, at most 25 a tick, nothing in a fight.

- **Same realm and faction only.** An auction house is named by `LT.Hash32("<realm>-<faction>")`. My offer
  (`wo`) says only that hash and how old my last full scan is; a friend asks (`wq`) only for their own house's
  hash, and I answer only a request for mine. Battle.net's realm field isn't used (its level was wrong on
  Forever: forever-platform.md). Ages, not times, go over the wire: two computers' clocks differ.
- **When.** After my full scan of my faction's house, an offer to every friend who reads them, at most every 10
  minutes per friend, and once to a friend first seen. A friend is asked when their scan is more than 10
  minutes newer than my newest data (my scan or the last friend's), one friend at a time (the newest), each at
  most every 30 minutes; a request without a message for 2 minutes is given up. A request is answered at most
  every 30 minutes per friend, one friend at a time.
- **What.** Only my own prices (never a friend's passed on): per item value, the last scan's lowest, how many
  were listed, the days the value rests on and whether it's unstable, at most 2000 items (those listed at my
  last scan first), packed into messages of 250 bytes at most, each saying how old its oldest entry is. 4
  messages a second at most, at low priority, only while fewer than 8 wait in Beacon's queues.
- **Taking.** Only from the friend asked, only for my house; an entry is kept only when it's newer than my own
  data of the item and than what a friend gave before, marked with the friend's name and when it came. `P.Get`
  shows the newer of mine and a friend's (with `friend`, confidence never high); my own `sells` and `perDay`
  stay mine. Broken entries are dropped; they go after 14 days like mine.

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

`Crafts.lua` (`W.Crafts`, `Cr`): the cheapest way to get an item, crafting it (and its reagents) yourself included,
and what a recipe brings. Chronicle's margins work their numbers out with it (`Margins.lua`'s `Compute` is
`Cr.Recipe`), so the margins window shows crafted reagents too. Pure arithmetic over prices and recipe data: it keeps
no saved state, runs on no event and no frame of its own.

**The ways to get n of an item** (`Cr.Cost`):

- **ah**: the lowest buyout for one at the last scan that covered it (`P.Get(item).low`), times n. Never seen, or
  none listed at that scan: no AH price. Fewer listed than for 5 times n: `few` (the price for more is higher).
- **vendor**: what a vendor asks for one (`P.VendorBuy`: seen at a merchant, else Data/Recipes.lua's list of
  trade-goods reagents: threads, vials, flux, dyes, spices), times n. On a tie with the AH the vendor wins (it's
  certain). Basis `yours` when a merchant was seen asking it, else `forever` (the client's ItemSparse price).
- **craft**: every recipe the crafter knows that makes the item (`R.RecipeOf` over its known spells, of all its
  professions, Chronicle's record: `R.People` by the character's id). n / what a craft makes crafts, a fraction when
  it doesn't divide (what's left over goes into the next craft: the steady state of crafting again and again, which
  is what profit per craft and gold per hour mean). Its reagents are worked out the same way, at most `depth` (4)
  crafts deep, and never through an item already being worked out above it (the data has circles: Alchemy's
  elemental transmutes, Earth to Water to Air to Fire to Earth; and Goblin Mortar from a Goblin Mortar). Its time:
  each craft's cast (`C_Spell.GetSpellInfo`'s `castTime`, else 3 s and `castKnown` false) plus 0.5 s, of it and of
  every craft below it. An item made by several recipes: the cheapest.
- **bags** (only with `bags = true`): what the bags hold (`C_Item.GetItemCount`), at what it would sell for
  (`P.Best`: what you give up by using it). Only when that sale value is known (an item never seen on the auction
  house that vendors pay nothing for, or whose AH price isn't known, isn't counted from the bags) and when it's
  cheaper than the other ways (a bolt that sells for 95c isn't used when crafting one costs 20c). Partly in the
  bags: the rest another way (`mixed`). Each item in the bags is used once in one answer (a bar wanted by the recipe
  and by its bolts counts once).

The cheapest among the ways with every price known wins; a way missing a price only when there's no other
(`complete` false: `total` is then only what's known, never a cost to show). No price and no recipe: nil.
`oldest` is the oldest AH price used, `basis` the weakest of what it rests on (`yours` > `forever` > `prices`), a
friend's AH price says so (`friend`).

**Yields.** Data/Recipes.lua's `count` is the "create item" effect's base points, the middle of the range when the
craft makes a varying number (Heavy Dynamite: 3 for 1 to 5), and the data doesn't say which ones vary (104 recipes
make more than one). So an answer with a craft making several has `mayVary`, and the margins window says "~".

**Smelting**: Mining's smelting recipes are the recipe data's `smelting` (not a Professions tab line;
`R.Smelting()`, and `R.RecipeOf` knows them as line 186). Chronicle records only the crafting lines, so the ones the
character I play knows are asked of the game (`Cr.MySmelting`: `C_SpellBook.IsSpellKnown`, else `IsPlayerSpell`) and
added to its set (`Cr.KnownOf`, one set per what's known); an alt's smelting isn't known, so its bars are bought.

**Not counted**, said here so nothing pretends otherwise: recipe cooldowns (transmutes like
Arcanite) aren't known, so gold per hour assumes a recipe can be cast again at once; time spent buying isn't counted.

**A recipe** (`Cr.Recipe`): every field Margins' window and tests use (Margins.lua's `Compute` lists them); each
reagent `Cr.Cost(reagent, n)` without the bags (numbers that hold for every craft; `covers` says how many crafts the
bags' reagents hold); revenue at a vendor (`P.Vendor` times what a craft makes) and on the AH (`P.AHSale`: after the
cut, and P's deposit rule); profit the better one minus the cost; time its cast plus 0.5 s plus the sub-crafts'
(`subSeconds`); gold per hour profit / time.

**The verdict:** `reagentsSale` is what the recipe's reagents would sell for instead (`P.Best` each; one without a
known price adds nothing, and `reagentsSaleComplete` is false: it's at least that much).

- "sell reagents" (`reagents`): they sell for more than what the craft makes sells for, the better of vendor and
  AH. Comparing the two is enough, as getting the reagents costs the same either way. Needs the product's AH price
  (else it might fetch more there); holds even with a reagent's price missing (that would only add).
- "craft" (`profit`): a profit, every price known.
- "no" (`loss`): no profit, with the product's AH price known.
- nil (`price`): a price is missing, or a loss at a vendor for a product never priced on the AH.

**This character's recipes** (`Cr.Mine`): the recipes the character I play knows that make an item, each
`Cr.Recipe`, best gold per hour first. Kept until `Cr.Revision()` moves (`P.Revision()` and
`R.Revision()`); worked out at most 2 ms a call (a recipe at a time), going on at the next call, so the ideas'
driver spreads it over frames. A list where an item's data hadn't come yet is worked out again 5 s later.

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
`spell`, `item` (else `recipe.item`), `profit` (a craft's), `complete`, `basis`, `oldest`; asked again each unit
while `Cr.Mine` says it isn't done): the profit of one craft, said so. How many the auction house takes isn't
known (`perDay` counts listings bought or taken back early, so it's shown, never multiplied in); without it, low
confidence. Crafting's real limit is how many sell, so it's not per hour.

**The market** (once, only listings from a scan younger than `P.STALE`, each said to maybe be gone):
**flip** (`flip:<item>`): an item that isn't unstable or low confidence, whose listings go early at least once
a day (`perDay`: bought or taken back, from scans) and, when it's known (my own auctions), sells 0.5 or more;
bought at the lowest listing, listed again at its `value` (what its lowest listing usually is) less the 5% cut,
and the deposit lost on what doesn't sell only when both `sells` and `P.Deposit` are known (else a warning
says it isn't counted); at least 1s and 15% more than it costs. **Every market idea counts one item**: a scan
keeps only the cheapest listing's price, not how many are listed at it (the rest may cost more), and the
reason says so. **Vendorflip** (`vendorflip:<item>`): the cheapest listing at least 20c below what a vendor
pays.
**Disenchant** (`disenchant:<item>`, enchanters): a listing below what disenchanting it gives at your skill
(`Dt.Disenchant`: each result's chance x the middle of its count x its auction house worth, every result
priced there), at least 1s and 15% more, one; and `disenchant:bags`: what in your bags
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

### Crafting margins (Margins.lua, the Crafting tab: Crafting.lua)

Chronicle's until build 0.7.0-193, now WhyPoor?'s (`W.Margins`, `Mg`): no setting of its own (it's on while WhyPoor?
is; Chronicle's old `margins` stays unused in its saved table), no window of its own: the window's **Crafting** tab
(`W.Crafting`, `Cf`, added with `Wn.AddTab`: its own entries, rows, details, the overview when nothing is picked and
its controls on the line above the list: the profession picker, "By gold/h" / "By profit"). Its list is worked out
a few recipes a frame only while the tab shows (`Cf.driver`). The overview has "Scan all my recipes" (`Mg.ScanAll`;
"Go on (N left)" after a stop, "Stop" while it runs). The details: who makes it, each reagent the cheapest way
(`D.Item` with the whole way in its hover; a crafted one's "craft it: ..." line), the numbers, notes, "Check AH"
(`Mg.ScanRecipe`) and "Show in my profession window". The profession window's **Margins** button (setting
`craftButton`, on) opens the tab on its recipe (`Cf.OpenOn`) and checks it at an open auction house; the auction
house has only WhyPoor?'s button. `/chronicle margins` and `/whypoor crafting` open the tab. The window asks for
the ideas only on the Ideas and Market tabs (Crafting and Bags never make them work). What follows is the
section as it was in chronicle.md; the window it names is the tab now.

#### As it was

Setting `margins` (on): what my recipes cost to make and bring, and gold per hour, from auction house and
vendor prices. `Margins.lua` (`C.Margins`, `Mg`) picks what to scan and works the numbers out; the prices and
the scans are WhyPoor?'s price engine's (`Modules/WhyPoor/Prices.lua`, `W.Prices`; whypoor.md, Prices), which
runs while this setting or the WhyPoor? module is on. `MarginsWindow.lua` is the window and the buttons.
Margins itself sends nothing; WhyPoor?'s own setting shares prices with friends (whypoor.md, Friends' prices).

**The client.** WoW: Forever has retail's profession window (`Blizzard_Professions`, `ProfessionsFrame`,
with Camelot overrides; the recipe shown is `ProfessionsFrame.CraftingPage.SchematicForm:GetRecipeInfo()`)
and retail's auction house (`Blizzard_AuctionHouseUI`, `AuctionHouseFrame`, its TOC allows camelot through
a `[Game]` file): `C_AuctionHouse` with `SendSearchQuery` (100 a minute, its documentation says),
`ReplicateItems` (the whole auction house) and `IsThrottledMessageSystemReady`, not classic's
`QueryAuctionItems`. None of the query functions is marked `HasRestrictions` (only buying, bidding and
posting are), so they're called from our driver, not only from a click. Search results: a commodity's rows
have a price for one (`unitPrice`); an item's an auction's `buyoutAmount` for its whole `quantity` (what
`PlaceBid` is given), so one is the buyout divided by the quantity; replicate rows (0-based indexes) have a
stack's `buyoutPrice` and `count`. Merchants: `GetMerchantNumItems`, `GetMerchantItemID`,
`C_MerchantFrame.GetItemInfo(i)` (`price` for `stackCount`, `hasExtendedCost`).

**Prices** (the engine's, `LefthyToolsWhyPoorDB.prices`): `Mg.AHPrice(item)` is `{ p, q, t }` of this realm's and
faction's auction house (the last scan's lowest for one, nil when none is listed; how many; when), `Mg.VendorPrice`
what a merchant asked for one (every item a merchant showed, for gold only), else `Data/Recipes.lua`'s `vendor`
(a hand list of Classic's trade-goods reagents, priced from ItemSparse: Recipe data, below), `Mg.SellPrice` what
a vendor pays. The engine keeps every item it saw (14 days); Margins' own saved prices (`LefthyToolsDB.margins`)
went over to it once and are gone.

**My recipes** (`Mg.MyRecipes`, kept per `R.Revision`): what my characters on this realm know (`R.People`'s
`mine`, the record's `realm`) that makes an item; a recipe two of them know goes by the one I play, else the
best skill. `Mg.Items`: every reagent and product of them (kept) and those the auction house is asked for
(the products and the reagents no vendor sells: threads and the like aren't searched).

**The numbers** (`Mg.Recipe(spell)`, `Mg.Compute(entry)`), worked out by WhyPoor?'s crafting part
(`Modules/WhyPoor/Crafts.lua`, `Cr.Recipe`; docs/whypoor.md, Crafting, has the rules in full):

- a reagent's price: the cheapest way to get it: the AH's (lowest buyout for one, any age), a vendor's (wins a tie),
  or **crafting it** with a recipe the crafter knows (the character the recipe goes by, all its professions; none
  of mine knows the recipe: the character I play), its own reagents worked out the same way, up to 4 crafts deep,
  no circles. None: the recipe has no cost and no profit ("missing a price"). Reagents in my bags count at that
  price too (they could be sold instead); `covers` says how many crafts the bags hold. A reagent bought on the AH
  (also below a crafted one) with fewer listed than for 5 crafts is "few";
- cost: the reagents' prices times how many it needs (a crafted one: its reagents' share, n / what a craft makes);
- revenue: at a vendor `C_Item.GetItemInfo`'s sell price times how many a craft makes (the data's `count`,
  the middle of a range when it varies: "~" in the details); on the AH its price for one times as many, less the 5%
  cut (`P.AHSale` once W.Prices has it; the deposit isn't counted by Margins' own, and the details say so). Both,
  and their profits, are shown;
- profit: the better revenue minus the cost (`best`: vendor on a tie, it's certain);
- time per craft: the spell's `castTime` (`C_Spell.GetSpellInfo`) plus `OVERHEAD` (0.5 s), plus the same for each
  sub-craft of a crafted reagent (`subSeconds`); unknown: 3 s, and the details say so; gold per hour: profit × 3600
  / time;
- `oldest`: the oldest AH price used (the reagents bought there, also below crafted ones, the product when it's sold
  there);
- `verdict`: "craft", "sell reagents" (the reagents sell for more than the product), "no", or nil (not known).

The details show a crafted reagent's source as Craft, with a line under it ("craft it: 1 Bolt of Linen Cloth from 2
Linen Cloth, 1.5 s": the recipe's own numbers and a craft's time; lines that don't fit are left to the hover), the
time spent on sub-crafts beside the time, the whole way down in the reagent's hover, and notes for crafted
reagents, a sub-craft's unknown cast time, a varying yield and "its reagents would sell for more".

**Scanning** is the engine's (whypoor.md, Prices: only with the auction house open, never in a fight, its
pacing and reading); Margins says what:

- One recipe (`Mg.ScanRecipe`: the profession window's button, the details' Check AH): its product, then
  its reagents no vendor sells, item by item (`P.ScanItems`, before what a scan by items has left; during a full
  scan nothing, the full scan has them). Gear without an item level from the game is searched with its
  recipe's (`P.levelHint` = `Mg.LevelHint`).
- Everything (`Mg.ScanAll`, "Scan all my recipes"): a full scan (`P.ScanFull`, every item of the auction house)
  once the last was 15 minutes ago; too soon, no answer in 30 s or nothing in it: by items, the wanted ones
  without a price younger than 30 minutes (`FRESH`), so a scan that stopped goes on where it was (the button
  says "Go on (N left)").
- The auction house closing ends a scan by items; Stop (`Mg.Cancel`) too. `Mg.Status` is the engine's
  (`P.Status`) with what's left of my recipes' items.

**The window** (`LefthyToolsMarginsFrame`, `C.OpenMargins(spell, nextTo)`, `C.ToggleMargins`; `/chronicle
margins`): its own (`LT.Window`), not a page of the journal: it belongs with the auction house and my own
profession window, and opens next to them (right of the window it was opened from, if there's room). On
top a profession to pick (`AddPicker`), the sort (gold per hour, profit per craft) and the scan button with
its state in the bottom bar. Left the list (`C.NewList`, Professions.lua's pool): every recipe of mine with
a profit, a skill-up dot (the character's skill), name, profit, gold per hour, where it sells best, the
prices' age; older than 3 hours (`STALE`) greyed; how many have no price yet. A click shows the details on
the right: the crafter, each reagent (source, its cost, a hover with vendor and AH prices, how many listed,
in the bags), cost, both revenues with their profits, profit, time, gold per hour, the bags, the age, notes
(few on the AH, open the auction house, the deposit, an unknown cast time), Check AH and Show in my
profession window (`C.OpenInMyProfessionWindow`, Professions.lua's). While shown it looks at the scan every
0.25 s and works the list out again a few recipes a frame (2 ms): at once when prices or recipes changed,
at most every 2 s during a scan or for items' data and the bags (`GET_ITEM_INFO_RECEIVED`,
`BAG_UPDATE_DELAYED`, listened to only while it's shown). Hidden: nothing.

**The buttons.** "Margins" on the profession window's recipe (a child of the `SchematicForm`, at its top
right corner; shown for a recipe that makes an item; the form's `Init` is post-hooked to update it, on the
next frame) opens the window on it and checks it at an open auction house. The recipe's ID is the data's
spell; Forever's copies under other IDs go by the name of one of mine. "Margins" on the auction house (a
child of `AuctionHouseFrame`, its top right, left of the close button) opens the window. Both are made after
`ADDON_LOADED` of Blizzard's add-on, on the next frame; children of Blizzard's frames so the controller's
navigation (it collects the panel's descendants) reaches them, at corners where they don't stand between
Blizzard's buttons. Not verified in game yet: whether the profession window and the auction house can be
open together (both are UI panels), and that the corners are free.

### The window, bags, tooltip and goal

**The module** (WhyPoor.lua): the settings page (Window: Open, Minimap button; Crafting: `craftButton`; Auction
house: `autoScan`; Friends: `sharePrices`), `/whypoor` (open or close; `ideas`, `crafting`, `bags`, `market`,
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

**Nothing outside the window** (no extra data on items): no tooltip line and no mark on the bags (both were there in
builds 0.7.0-191 to -193 and went; Misc Tweaks' sorted bags have no corner-mark API any more).

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
