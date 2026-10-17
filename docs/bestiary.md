# Bestiary design

What the mobs you kill drop: a database of your own per kind of mob, a window for your target,
(settings) a card beside the mouse over an enemy and drop chances in item tooltips, and a ledger
of every mob with a fuzzy search. Files: `Modules/Bestiary/Bestiary.lua` (the module, recording,
the drop database, `ns.Bestiary` = `Bt`), `Modules/Bestiary/Window.lua` (the window, the card, item
tooltips, the minimap button) and `Modules/Bestiary/Ledger.lua` (the ledger). Nothing goes over the
network (the user: "just your own, I want to limit traffic"). Beside your own numbers: a classic
drop database, an add-on of its own (`LefthyTools_DropData`, below).

## The database

`LefthyToolsBestiaryDB` (its own saved variable, account-wide: every character adds to it):

```
mobs = { [creature ID] = { name, level, class (UnitClassification), kills, money (copper, all
         kills), first, last (time()), items = { [item ID] = { drops, count, quality, name } },
         skinned, skins = { [item ID] = { times, count, quality, name } },
         pace = { your level, kills with XP, XP, kills timed, seconds } } }
log = { { time, creature, what, items, check }, ... } (the last 12)
wishes = { [item ID] = { pinned (time()), kills since, expected drops in them, name, quality } }
         (the wish list; only while there's one)
```

Fields added later (`pace`) are simply missing from older records, and everything reads them as
"not known".

The creature ID comes from the GUID (`Creature-0-<server>-<instance>-<zone>-<ID>-<spawn>`, also
`Vehicle-`; `Bt.CreatureOf`). `drops` is how many corpses it came from, `count` how many in all.
Drop chance = drops / kills; per drop = count / drops (`Bt.Chance`; skinning: out of skinnings).
`Bt.Drops(mob, showPoor)`: the drops, the likeliest first, the better quality first when even, then
the same for skinning (`skin = true`); grey ones only with `showPoor`. Use `Bt.Part(mob, skin)` for
a kind's drops or skinnings: `skin and mob.skins or mob.items` falls back to the drops when there
are no skinnings (that listed every drop twice once). Item names are kept as looted (the search
needs them; a client may not know an item yet). `Bt.Sources(itemID)`: where an item comes from,
the likeliest first, built over the whole database when first asked after a change.

**World drops** (`Bt.IsWorldDrop`): random green and better gear drops from any mob of about its
level, so with one mob it says nothing about that mob (the user: a random BoE "forever stuck to that
mob's loot window"). An item is one when it's gear (`C_Item.GetItemInfoInstant`: class 2 weapon or
4 armour, worn somewhere) of green or better that doesn't bind on pickup (`GetItemInfo`'s bind type
1 = a mob's own; not known yet: taken as a world drop), or when it came from 3 or more kinds of mobs
(`Bt.Sources`). They're still counted per mob, but `Bt.Drops` gathers them in one entry at the end
(`group`): in the window a single place with a map icon, how many and "world"; its tooltip explains
and lists them with their chances. In the ledger they're a section of their own under the mob's
drops, each a normal drop with its item tooltip (the user: a list in a tooltip can't show an item's
own tooltip). The ledger's tiny "best drops" leave them out; item tooltips add "A world drop:
random gear from mobs of its level, anywhere."

**Skinning** is kept apart (`skins`, `skinned`): after Skinning (any rank: by ID or its name) a
corpse's loot window is what skinning gave, each corpse once (`skinnedCorpse`), also in a group
(what you skin is yours). It's marked with Skinning's own icon (`Bt.SKIN_ICON`,
`INV_Misc_Pelt_Wolf_01`) everywhere.

Name, level and kind come from units seen (`Bt.Look`: target, mouseover, nameplates; the last 200
GUIDs remembered) and are written to a kind's record as last seen.

## The classic drop database (LefthyTools_DropData)

The user wanted to "compare my mob against what it can drop". Wowhead has no API and doesn't allow
scraping; the classic emulator databases have the loot tables. `LefthyTools_DropData/` (a folder of
its own in the repo, next to `LefthyTools/`) is generated from CMaNGOS Classic DB's full dump by
`tools/update-drop-data.js` and is **GPL v3** like its source (its `LICENSE.md` and `COPYRIGHT.md`
must go with it); the rest of the repo stays BSD-2. Its README says how the chances are worked out
(groups, references, quest items) and how to make it again; the user: "we may want to rerun the
emulator or something when we have more access to forever data". World loot is left out (the level
world drop tables, bags, scrolls, recipes, zone drops: reached only through a reference and not
bound on pickup, gear or a reference shared by 8+ tables), so a mob's list is its own loot: 11
items for a Defias Bandit, 27 for Ragnaros, 69 at most; 5046 mobs with loot. It also has each
kind's health, for Beacon's fight stream (below): 9791 of them; 9921 creatures in all, 0.93 MB.

- **Loading**: `## LoadOnDemand: 1`. `DropData()` calls `C_AddOns.LoadAddOn` the first time
  something asks (`Bt.Known`: the window, the ledger, the card, or the fight stream's sensor and
  battle row through `Bt.Health`), once; when the setting `dropData` (on) changes it's tried again
  (and off means nothing reads it). A one-off moment when it's first needed, not at login for
  everyone who never needs it. `/bestiary data` says whether it's there (LoadAddOn's reason if
  not: `MISSING`, `DISABLED`) and what it holds (kinds of mobs, how many with their health).
- **Format**: `LefthyToolsDropData = { source, mobs = { [creature] = "<item>:<quality>:<chance in
  1/100 %>[q],...;s=<skinning>;g=<min>-<max copper>;h=<min level>-<max level>:<health at the min
  level>-<at the max>" } }` (each part only when there is one; the second level or health only when
  it differs: `h=63:1099230`): strings, so only mobs shown are read (`Bt.Known(creature)`: `{ items
  = { [id] = { chance 0-1, quality, quest } }, skins, coin, health = { min level, max level, min
  health, max health } }`, cached; read again when the database is another table). The quality is in
  there so grey items can be left out (`showPoor`) and edged before the client knows an item. A part
  of a kind the parser doesn't know is skipped: builds before the health read the same drops from
  the new strings (checked over the whole file). A creature with its health only (no loot in
  classic) is known with no drops: your drops of it say "Not in the classic database".
- **Health** (`Bt.Health(creature, level)`): `MinLevelHealth` / `MaxLevelHealth` of
  creature_template, the health at its lowest and highest level with its `HealthMultiplier` already
  in (93% of them are exactly `creature_template_classlevelstats`' BaseHealthExp0 times the
  multiplier, which is what the emulator gives a creature at a level; the rest set by hand); a
  level between in a straight line, rounded down (close to the emulator's per-level stats: most
  kinds span a level or two). Outside its levels: the nearest end's, with that level as the second
  value (the fight stream scales it); level not known (nil, -1 for "??"): its highest. nil while
  the Bestiary or `dropData` is off (nothing is loaded then). Left out by the tool: 1 health or
  less, totems, triggers and other invisible helpers, the unused ones. How the fight stream weighs
  it against what it learns: [beacon.md](beacon.md), "Mobs' health, estimated".
- **Beside your drops** (`Bt.Drops(mob, showPoor, creature)`): each entry's `classic` is the
  database's chance (`false`: it knows the mob but not this drop, `nil`: it doesn't know the mob),
  `quest` when it's a quest item. Tooltips: "Classic database: 30%" under your numbers, "Not in the
  classic database" (Forever's own, or a change), "only while on its quest"; the cell gets a "!".
- **Not seen yet** (`Bt.Compare(creature, mob, showPoor[, countOnly])`): the database's drops
  you've never had (the likeliest first, then skinning: entries with `unseen = true`), how many of
  its drops you have had and of how many. Skinning only counts when you know Skinning (any rank) or
  have skinned that kind: else every beast's leather would wait there forever. Shown as cells like the others but grey and faded (the
  icon desaturated at 50%, a dim edge, no count, the chance in grey), in colour while hovered. Their
  tooltip: the database's chance, then "Not seen in your 34 kills (about 10 expected)" in red-ish
  when you'd have expected 1.5 or more (bad luck, or Forever differs), else "Not seen yet in your 5
  kills", or "You haven't killed one yet."
- **Never mixed in**: your chances, the ledger's totals, the rarest find, item tooltips and the
  search are your kills only.

## Counting (so the chances hold)

- **A kill counts once its corpse is looted, or once the game says it's empty.** After a killing
  blow (`PARTY_KILL` with you or your pet as the attacker) the corpse waits; `CanLootUnit(guid)`
  is asked 2 s and 6 s after (loot can take a moment to show): no loot both times, a kill without
  drops. One that has loot counts when it's looted; left lying for 5 minutes, it's forgotten. A
  corpse left lying would otherwise look like a kill that dropped nothing. In game `CanLootUnit`
  said "no loot" for a corpse that had two items (perhaps it was too far away): a corpse counted
  as empty that's looted after all adds its items to that kill (not a second one).
- **Any corpse you loot was yours**: it counts even without your killing blow (a guard's).
- **On your own only** (`IsInGroup()`): in a group the loot goes round, so you'd see only part of
  it. The window says so while you're in one.
- **A corpse's loot once**: the first time its window opens (`LOOT_READY`, before anything is
  taken: auto loot happens in the client, Blizzard's loot frame takes nothing itself; if its slots
  aren't there yet, `LOOT_OPENED` looks again). Not when Skinning, Pick Pocket, Mining or Herb
  Gathering went off in the 1.5 s before (`UNIT_SPELLCAST_SUCCEEDED`, by spell ID or the name of
  one: other ranks); any other spell doesn't matter (the first version skipped the loot after any
  spell, so a quick loot after an instant killing blow was lost). Nor fishing (`IsFishingLoot`),
  nor what isn't a creature's (herbs, ore, chests and a bag's contents have object or item GUIDs).
- **The corpse**: `GetLootSourceInfo(slot)` (one source; several at once aren't told apart). When
  that says nothing: your dead target, else the one kill waiting from the last minute.
- **The log** (`/bestiary log`, `LefthyToolsBestiaryDB.log`, the last 12): each loot window and
  each empty kill with what was made of it (looted, said empty, looted after being said empty,
  looted before, skinning or pickpocket, group, no corpse, not a mob), how many items and what
  `CanLootUnit` answered ("hasLoot/canLoot"), to see why something wasn't counted.
- **Items**: `GetLootSlotType` 1, `GetLootSlotLink` (the item ID), `GetLootSlotInfo` (quantity,
  quality). **Coin** (type 2): the slot doesn't say how much, so it's what `GetMoney()` grew by
  between `LOOT_READY` and `LOOT_CLOSED`.

## The pace: XP and time per kill

To compare leveling spots (the user: "85 XP, 14 s per kill, about 21k XP per hour"). Recorded with
each kill of yours that counts (a `PARTY_KILL` of yours, then looted or said empty; a corpse looted
without your killing blow seen has none), into `pace`:

- **XP**: what `UnitXP` grew by (`PLAYER_XP_UPDATE`) within 1.5 s of its `PARTY_KILL`, either way
  round (the XP can come first: it waits that long for its kill). Several kills at once take the
  XP in order. A level-up in between wraps (the rest of the old level plus what's in the new one,
  as Chronicle counts it). A kill without any XP gave 0 (a grey mob), unless kills give no XP at
  all (the XP bar's own rule: `IsPlayerAtEffectiveMaxLevel()` or `IsXPUserDisabled()`): then it
  says nothing about XP. XP that comes after the kill was already counted (a quick loot) is added
  then. Rested bonus is part of what you got.
- **Time**: from when the fight began (`PLAYER_REGEN_DISABLED`), or from your previous kill in the
  same fight, to the kill: several mobs in one fight share its length, so their times add up to
  it. Not timed when the fight's start wasn't seen (a `/reload` in it) or the kill came more than
  2 s after the fight ended. Kept to a tenth of a second.
- **Per level**: XP per kill depends on your level, so `pace` is for one level, the one you were at
  when it died; a kill at another level starts it again (time too: you fight faster as you level).
  Shown for another level, it says so: "(level 12)", "At level 12: ...".
- `Bt.Pace(mob)`: XP per kill, seconds per kill, XP per hour of fighting (XP per kill over seconds
  per kill: the time between fights isn't counted, and the text says so) and the level.

## The window

`LefthyToolsBestiaryFrame`, 236 px wide, its height fits the drops; dark with thin gold edges
(like the fight stream's windows), not Blizzard's template (that one closes with Escape). It
**stays open**: not in `UISpecialFrames`, closed by its X, the minimap button or `/bestiary`;
whether it's open and where it is are kept (`db.window`: shown, left, top). Not registered with
`LT.Window.Register`: it may stay open all the time, so it mustn't keep Mirage from fading or pause
flights.

- **Header**: a still portrait (`PlayerModel:SetCreature`, portrait zoom 1, `RefreshCamera` and
  paused once loaded; a question mark before any mob), the name (gold), level and kind ("Level 16
  Elite"), then "34 kills · 12s 40c each" (`GetCoinTextureString`; the coin on average over all
  its kills, "no coin" for beasts) and, when skinned, the pelt and how often. A small book left of
  the X opens the ledger on this mob. When its pace is known, one more small grey line under the
  portrait, the window wide (`PaceText`): "Per kill: 85 XP · 14 s", only the parts known, "(level
  12)" when that's not your level; the header grows by it. Hovering it shows the same in full
  with the XP per hour of fighting.
- **Drops**: 6 per row, at most 4 rows; each a 30 px icon edged in its quality's colour, how many you
  got in its corner, the drop chance under it ("35%", "3.4%", "<0.1%") in the quality's colour.
  Hover: the item's tooltip (`SetHyperlink`) plus "Dropped in 9 of 34 kills: 26%" and, for stacks,
  "12 in all, 1.3 each time". Shift-click links it (`HandleModifiedItemClick`). More than fit: the
  last place says "+N", its tooltip lists the rest with their chances.
- **Not seen yet** (the drop database; setting `windowUnseen`, off: the user wanted the window
  without it, the ledger always has it): under your drops a heading "Not seen yet" with a thin rule
  and "6 of 11 found" on the right, then the database's drops you haven't had, 22 px, 7 per row, at
  most 2 rows ("+N" for the rest, its tooltip greyed). A mob you haven't killed: "What it can
  drop", "classic database". All found: a tick and "All 11 drops of the classic database found."
- **A line under it** when there's something to say: target a mob, no kills yet, nothing (or only
  grey items) dropped yet, in a group nothing is counted.
- **It follows your target**: a mob you can attack or a dead one (not a vendor); clearing the
  target keeps the last.

## The card beside the mouse

Setting `hoverCard` (off by default). Over an enemy (attackable or dead) you've killed: "34 kills ·
12s each" (no coin: nothing said, unlike the window's "no coin") and its 6 likeliest drops (22 px, chance under each), at the cursor's lower right,
`TOOLTIP` strata, no mouse. An OnUpdate while it's shown follows the cursor and hides it once the
mouseover is gone or another unit. **Small on purpose** (the user: it mustn't be "too large and
intrusive"): one line and one row of 6, never more (a quest's line, below, the only one more). **Not in combat** (setting `cardHideInCombat`,
on; the user: not "infight"): `InCombatLockdown()`, checked when the mouseover changes and in its
OnUpdate (it goes when a fight starts); `PLAYER_REGEN_ENABLED` looks at the mouseover again, so it
comes back if the mouse is still over an enemy. A mob killed before shows only your drops (no
database cells on top); one you haven't killed, with the setting `cardUnseen` (off, like the
window's `windowUnseen`: the user wanted neither by default), shows the database's 6 likeliest,
faded, under "Not killed yet: classic database"; without it, no card.

## Quest drops

While a quest wants an item a mob can drop, the window and the card say so (the user: "Gnoll Paw:
3/8, 40% each, about 12 more kills").

- **What your quests want**: `C_QuestLog.GetQuestObjectives` of each quest in the log (`GetInfo`;
  one under a collapsed header isn't listed, so quests seen once are remembered until
  `GetLogIndexForQuestID` no longer finds them, like the quest announcements). Name and counts from
  the text, "Gnoll Paw: 3/8" (classic) or "3/8 Gnoll Paw" (the modern client), a "(Complete)" behind
  it dropped; `numFulfilled` and `numRequired` instead when the client gives them. Done: `finished`
  or have >= need. Two quests wanting the same item: the bigger need.
- **Matched by name**: an objective doesn't say which item it is, so a mob's possible drops (its
  record's and the classic database's) are matched by the item's name, case ignored: the name as
  looted, else `C_Item.GetItemInfo` (kept; one the client doesn't know is asked for once,
  `RequestLoadItemDataByID`, and `GET_ITEM_INFO_RECEIVED`, listened to only then, redraws half a
  second later).
- **The numbers** (`Bt.QuestDrops(creature, mob)`, `Bt.ChanceOf`): the chance per kill is the
  classic database's (for a quest item its chance while on the quest), else yours (drops / kills);
  about how many more kills = what's left / (chance x how many come per drop: yours, 1 before you've
  had one), at least 1. No chance known: only the counts.
- **When**: `QUEST_LOG_UPDATE` and `BAG_UPDATE_DELAYED` (they come often) only mark the objectives
  old; whatever looks next reads them again. Half a second after the first of a burst, if the window
  or the card is up and what the quests want changed (compared as text), they redraw, once.
- **The window**: a line each under the header (at most 3), the quest's "!" in front, the ones still
  wanted first; done: a tick, grey. The drops move down under them.
- **The card**: one more small line, the first still wanted ("+1" when another wants more of its
  drops), cut at 250 px; done ones aren't shown. It also comes up over a mob you haven't killed when
  a quest wants its drop, without `cardUnseen`: "Not killed yet: classic database" and the quest's
  line, no icons.

## The wish list

Items you're after (the user: "Pin an item ... Mobs that drop it get a small mark on the card. When
it finally drops, a quiet line says 'after 87 kills (expected about 40)'"). Your own only, like the
rest.

- **Pinning**: Alt-click on a drop in the window or the ledger (also one not seen yet), or
  `/bestiary wish <item link or ID>` (an ID `GetItemInfoInstant` doesn't know: said so); the same
  again takes it off. A chat line says which. `/bestiary wishes` lists them in chat: kills since
  and where each comes from likeliest. Tooltips can't be clicked, so there's no pinning from bags.
- **Saved** as `wishes` (above): when, the kills since, the chances of those kills added up, and
  name and quality as known then (the ledger's strip before the client knows the item). The table
  is only there while it has a wish (old saved data without it works as before).
- **Counting** (`WishKill`, per counted kill: looted, or said empty): a kill counts for a wish when
  its kind drops the item, by the classic database or your own record (`Bt.ChanceOf`, the same
  chance as quest drops), and adds that chance. Skinning doesn't count. A kill said empty and looted
  after all isn't counted again, its items are still looked at.
- **When it drops** (an item of a counted kill's loot): one chat line, no sound, no popup:
  "Bestiary: [item] after 87 kills (about 40 expected); off your wish list." Expected = kills /
  the chances added up (1 / its chance when it's all one kind of mob), at least 1; none known: left
  out. It comes off the list.
- **The star** (`Bt.STAR`, the raid marker's star): on wished drops in the window, the ledger and
  the card (top right corner; on the world drops' place when one of them is wished), after the name
  in drop lists.
- **The card** puts wished items the mob drops first: yours (also from among its world drops), else
  the classic database's, faded (not had yet). That also brings up the card over a mob you haven't
  killed, with only those.
- **Item tooltips**: "On your Bestiary wish list (37 kills since you pinned it)" with the star,
  also with `itemTooltip` off.
- **The ledger's strip** (top right, at most 8 icons, the first pinned leftmost, "+N" beside "Wish
  list" for more; empty: "Wish list: Alt-click a drop to pin it"). Hover (`Bt.WishSources`): the
  item, kills since, and where it drops: your own drops (your chance and kills) and the classic
  database's (its chance). The database has creature IDs but no names, so only mobs the Bestiary
  knows are named (a record, or seen this session: target, mouseover, nameplates); the rest are
  counted ("and 3 more in the classic database"). At most 8 named. Click: searches for it (its
  name); Alt-click: off the list; Shift-click: links it.
- **The database's sources** (`Bt.KnownSources`): a plain `find` for "<item>:" over every mob's
  text, then the drops part (before ";s=") of the ones found matched exactly; nothing more is read
  or kept but the list, per item, until a setting changes. A few milliseconds once per item.

## Item tooltips

Setting `itemTooltip` (on). A post-call on item tooltips (`TooltipDataProcessor`, only
`GameTooltip` and `ItemRefTooltip`: bags, chat links, anywhere) adds, under a blank line,
"Bestiary · drop chance (kills)" and the 3 likeliest sources (`Bt.Sources`): "Defias Bandit (9)
50% (4)", skinning with the pelt in front; more: "and N more (the Bestiary's ledger)". Not on the
window's own drop tooltips (they show the numbers already: `ownTooltip` while they're set).

## The ledger (Ledger.lua)

`LefthyToolsBestiaryLedger`, 640 x 470, same look; Escape closes it (it's for looking things up),
registered with `LT.Window.Register`. Opened by the window's book, Ctrl-click on the minimap button,
the settings or `/bestiary ledger [search]`.

- **At the top**: "2 mobs · 7 kills · 5 items · 12s coin, 1s 76c per kill" (the coin per kill over
  all kills), and the **rarest find**: the looted item with the lowest chance among mobs with at
  least 5 kills, its icon, chance and mob. On the right the wish list's strip (above).
- **The list** (left, scrolling): a row per mob with kills or skinnings: name (found letters in
  gold), level, Elite/Rare, kills on the right, its best drops as tiny icons (best quality first).
  Sorted by most kills, name, level, coin per kill, XP per kill, XP per hour (of fighting) or last
  killed (a picker of our own).
- **The picked mob** (right): its whole model turning slowly (an OnUpdate while open), name, kind,
  kills, coin each and in all (or "no coin"), first and last kill ("2 h ago"), skinnings, the drop
  database's coin ("Classic database: 8c to 15c each") and "6 of its 11 drops found". Under the
  model, the pane wide, what a kill pays when known: "85 XP and 14 s per kill" ("At level 12:
  ..."), "About 21k XP per hour of fighting (the time between fights not counted)"; the drops start
  under it. Then its drops in a scrolling area (all of them, 8 per row, no "+N"): "Drops (N)"
  (skinning marked), "Not seen yet (N), classic database" (faded, as in the window) and "World
  drops (N)" when it has any.
- **A row** also says "6/11 found" (the drop database; not while it shows what the search found).
  Sorted by coin, XP per kill or XP per hour, it says that instead ("85 XP", "21k XP/h").
- **The search** (fuzzy, `Bt.Fuzzy`): the query's letters in order, not necessarily together, case
  and spaces ignored ("dfbnd" finds Defias Bandit); letters together, at a word's start and early
  score more, a shorter text a little more. Over mob names and the names of all their drops and
  skinnings (an item found counts 0.95 of its score). Results best first; typing picks the best
  match. A row found by an item shows that item, its chance (and "+N" more found); the picked
  mob's found drops stand out, the others fade to 35%. Names the client doesn't know yet are asked
  for (`RequestLoadItemDataByID`); `GET_ITEM_INFO_RECEIVED` (listened to only while open) redraws
  once, half a second later.

## Minimap button and settings

`LT.Window.MinimapButton` (a loot bag, angle `minimapAngle`, 150: upper left), a gold dot while the
window is open; click toggles the window, Shift-click switches the card beside the mouse (a chat
line says which), Ctrl-click opens or closes the ledger, right-click opens the settings; its tooltip
says how many kinds and kills are known and all of that. Settings: open the window, open the
ledger, minimap button (on), drops beside the mouse (off), hidden in combat (on), drop chances in
item tooltips (on), grey
items (on), compare with a drop database (on), not seen yet in the window (off), mobs not killed
yet beside the mouse (off). `/bestiary`
(`open`, `ledger [search]`, `wish <item link or ID>`, `wishes`, `log`,
`data`, `minimap`, `settings`).

## Cost

Event handlers only: `PARTY_KILL`, `LOOT_READY`, `LOOT_CLOSED`, the player's
`UNIT_SPELLCAST_SUCCEEDED`, target/mouseover changes, nameplates added, entering and leaving
combat (a time stamp), `PLAYER_XP_UPDATE` (three numbers read, the last 8 kills looked at), and
`QUEST_LOG_UPDATE`/`BAG_UPDATE_DELAYED` (a flag, then one look half a second later). The window
redraws when its mob's record changes or the target does; the card's OnUpdate runs only while
it's shown.

## To check in game

- `GetLootSourceInfo` and `CanLootUnit` answer (and aren't secret), and `CanLootUnit` says "no
  loot" for an empty corpse of yours.
- The portrait's look; the coin attribution with auto loot.
- `PLAYER_XP_UPDATE` comes within 1.5 s of `PARTY_KILL` (either order), and `UnitLevel` has the
  new level at a level-up's update; `IsPlayerAtEffectiveMaxLevel` answers on Forever.
- `LoadAddOn` of the load-on-demand drop database works on Forever, and its first load (0.93 MB of
  strings) is only a moment, also when the fight stream asks for it in a fight.
- How close the classic database's health is to Forever's (the fight stream's learned ratio from
  two kills on tells).
- How Forever writes item objectives ("Gnoll Paw: 3/8" or "3/8 Gnoll Paw") and whether it gives
  `numFulfilled`/`numRequired`; that they update while looting.
- The wish list's star (`UI-RaidTargetingIcon_1`) on cells and in text; Alt-click on a drop.
