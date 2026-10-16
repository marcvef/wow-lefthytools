# Bestiary design

What the mobs you kill drop: a database of your own per kind of mob, a window for your target, and
(a setting) a card beside the mouse over an enemy. Files: `Modules/Bestiary/Bestiary.lua` (the
module, recording, `ns.Bestiary` = `Bt`) and `Modules/Bestiary/Window.lua` (the window, the card,
the minimap button). Nothing goes over the network (the user: "just your own, I want to limit
traffic").

## The database

`LefthyToolsBestiaryDB` (its own saved variable, account-wide: every character adds to it):

```
mobs = { [creature ID] = { name, level, class (UnitClassification), kills, money (copper, all
         kills), last (time()), items = { [item ID] = { drops, count, quality } } } }
```

The creature ID comes from the GUID (`Creature-0-<server>-<instance>-<zone>-<ID>-<spawn>`, also
`Vehicle-`; `Bt.CreatureOf`). `drops` is how many corpses it came from, `count` how many in all.
Drop chance = drops / kills; per drop = count / drops (`Bt.Chance`). `Bt.Drops(mob, showPoor)`:
the likeliest first, the better quality first when even, grey ones only with `showPoor`.

Name, level and kind come from units seen (`Bt.Look`: target, mouseover, nameplates; the last 200
GUIDs remembered) and are written to a kind's record as last seen.

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

## The window

`LefthyToolsBestiaryFrame`, 236 px wide, its height fits the drops; dark with thin gold edges
(like the fight stream's windows), not Blizzard's template (that one closes with Escape). It
**stays open**: not in `UISpecialFrames`, closed by its X, the minimap button or `/bestiary`;
whether it's open and where it is are kept (`db.window`: shown, left, top). Not registered with
`LT.Window.Register`: it may stay open all the time, so it mustn't keep Mirage from fading or pause
flights.

- **Header**: a still portrait (`PlayerModel:SetCreature`, portrait zoom 1, `RefreshCamera` and
  paused once loaded; a question mark before any mob), the name (gold), level and kind ("Level 16
  Elite"), then "34 kills · 12s 40c each" (`GetCoinTextureString`).
- **Drops**: 6 per row, at most 4 rows; each a 30 px icon edged in its quality's colour, how many you
  got in its corner, the drop chance under it ("35%", "3.4%", "<0.1%") in the quality's colour.
  Hover: the item's tooltip (`SetHyperlink`) plus "Dropped in 9 of 34 kills: 26%" and, for stacks,
  "12 in all, 1.3 each time". Shift-click links it (`HandleModifiedItemClick`). More than fit: the
  last place says "+N", its tooltip lists the rest with their chances.
- **A line under it** when there's something to say: target a mob, no kills yet, nothing (or only
  grey items) dropped yet, in a group nothing is counted.
- **It follows your target**: a mob you can attack or a dead one (not a vendor); clearing the
  target keeps the last.

## The card beside the mouse

Setting `hoverCard` (off by default). Over an enemy (attackable or dead) you've killed: "34 kills ·
12s each" and its 6 likeliest drops (22 px, chance under each), at the cursor's lower right,
`TOOLTIP` strata, no mouse. An OnUpdate while it's shown follows the cursor and hides it once the
mouseover is gone or another unit.

## Minimap button and settings

`LT.Window.MinimapButton` (a loot bag, angle `minimapAngle`, 150: upper left), a gold dot while the
window is open; click toggles the window, right-click opens the settings, its tooltip says how many
kinds and kills are known. Settings: open the window, minimap button (on), drops beside the mouse
(off), grey items (on). `/bestiary` (`open`, `minimap`, `settings`).

## Cost

Event handlers only: `PARTY_KILL`, `LOOT_READY`, `LOOT_CLOSED`, the player's
`UNIT_SPELLCAST_SUCCEEDED`, target/mouseover changes, nameplates added. The window redraws when its
mob's record changes or the target does; the card's OnUpdate runs only while it's shown.

## To check in game

- `GetLootSourceInfo` and `CanLootUnit` answer (and aren't secret), and `CanLootUnit` says "no
  loot" for an empty corpse of yours.
- The portrait's look; the coin attribution with auto loot.
