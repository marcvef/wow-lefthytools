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
P.Revision()          -- goes up when any price changed (for caches)
P.AH_CUT, P.STALE
-- Also (Margins and tests): P.AHPrice(item) ({ p, q, t }: Margins' old shape), P.ScanItems(items, { front, spell }),
-- P.ScanFull(fallback), P.Status(), P.Cancel(), P.Busy(), P.Refresh(), P.levelHint (a function: gear's item level),
-- P.Decode / P.Encode (an item's saved text), P.Today()
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

(to be written by the data part)

### Crafting

(to be written by the crafting part)

### The ideas

(to be written by the ideas part)

### The window, bags, tooltip and goal

(to be written by the window part)
