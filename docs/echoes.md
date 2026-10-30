# Echoes design

A recorder: the way you travel and what happens on it (level-ups, quests, kills, loot, deaths and
more), written as lines of text and cut into pages that are kept in `LefthyToolsEchoesDB`, for a
program outside the game (an exporter) to read. Friends' clients can carry pages to whoever
collects them, through Beacon. Nothing shows in game.

## Overview

- **On by default; the module's switch is the recording's.** Switched off, nothing is recorded and
  nothing runs (no driver, no events).
- **Data from the beta never counts.** On the beta (`LT.world == "beta"`) Echoes stays switched on
  but idle: `E.recording` is false, the driver is hidden and no event is registered. On the release,
  or when it isn't known which client this is, it records. Its saved table is in Core's `SAVED`
  list, so the beta's table goes on the release (architecture.md, The beta and the release).
- **Never lags the client.** Event handlers only note things or append a few numbers; the driver's
  tick does the rest, and each subscriber throttles itself. Nothing runs per frame, and nothing
  that touches Blizzard frames runs in combat.
- **Its own event frame.** Chronicle, the Bestiary and Beacon unregister their events when switched
  off; Echoes records anyway. It reuses Core's plain helpers, which work whatever is switched on:
  `LT.Position`, `LT.CreatureOf`, `LT.OwnLoot`, `LT.Hash32`, `LT.Names`, `LT.Value`, and Misc
  Tweaks' `ns.FlightTime.Pick`.
- **Secret values** are skipped, never stored.

Files, in `Modules/Echoes/`, in the order they load (the TOC):

| File | What |
|---|---|
| `Echoes.lua` | the module (`ns.Echoes` = `E`), its settings, the saved table, its events (`E.On`), its driver (`E.OnTick`), starting and stopping (`E.When`) |
| `Lines.lua` | the line encoder: every recorded thing as one line (`E.Line`, `E.Anchor`, `E.Point`, `E.Mode`, `E.Zone`, `E.Name`), the pages' side of it (`E.PageStart`, `E.Raw`, `E.Continue`, `E.OnLine`, `E.Take`), the clock (`E.Now`) |

What the files share (`E`):

- `E.recording`: whether Echoes records right now (switched on, not on the beta).
- `E.On(event, handler[, unit])`: `handler(...)` runs for `event` on Echoes' own frame, after the
  handlers added before it, each through `LT.Guard` (one that fails is reported once and rests; the
  others still run). With `unit`, a unit event for that unit only. Registered while recording (one
  added while recording at once); an event the client doesn't know is skipped quietly.
- `E.OnTick(fn)`: `fn(now)` on every tick of the driver, 4 a second while recording (`now` =
  `GetTime()`), each through `LT.Guard`. Subscribers throttle themselves. The driver resets its timer
  before the tick, so an error can't make it run every frame.
- `E.When("start" | "stop", fn)`: `fn()` once recording has started (login with Echoes on, or
  switched on: events registered, driver running), or just before it stops (switched off; still
  recording, so it can write its last lines), through `LT.Guard`.
- `E.data`: `LefthyToolsEchoesDB` (below); `E.driver`: the driver frame (for tests).

**Settings** (`LefthyToolsDB.settings.echoes`), for the delivery (not built yet):

| Setting | Default | What |
|---|---|---|
| `relay` | on | Relay friends' recordings: keep Battle.net friends' pages for a while and pass them on to whoever collects them |
| `collect` | off | Collect recordings: gather friends' pages (and your own from other computers) for the exporter |

## Recording

Not built yet: the path sampler and the event detection (`Path.lua`, `Events.lua`) write through
the line encoder (Line format).

## Line format

The recording is cut into **pages** (Pages and storage). A page is immutable once closed; it is the
unit that is stored, sent, relayed, acknowledged and exported.

- One record per line, UTF-8.
- A line starting with a digit is a path point. Any other line is `<kind><dt>;<field>;...`.
- Time is cumulative: each line's time is the previous line's time plus its `dt`, and the header
  sets the start. Times are whole seconds of the realm's clock (`GetServerTime()`, the same for
  every friend, so all of them fit on one timeline).
- Coordinates in points are deltas from the previous position, in whole yards.
- Events carry no coordinates: their spot is the path position at that moment (the capture stores a
  point first if the last one is stale).
- Each page stands alone. It starts with the header, the character, an `@` anchor and the current
  zone, and repeats every name it uses.

```
E1;1a2b3c4d;9f3a61c2;214;1793452800;deDE;70532;0.7.0-12-gabc1234   header: format, acct, store, n, t0, locale, build, addon
C0;Anna-Realm;Anna Brook;Player-1234-0ABCDEF0;MAGE;Human;2;12;Alliance   character: key, full name, GUID, class, race, sex, level, faction
@0;0;-9046;-160;f;s                anchor: dt; continent; north; west; mode; why[; spell]
z0;1429;Goldshire                  zone: uiMapID; subzone text
2,-5,-13                           point: dt,dnorth,dwest
2,-8,-11
=9;c;327;Kobold Vermin             name: namespace (c creature, q quest, i item); id; text
k0;327;5;n;m                       kill: creature; level; classification; who
m3;m                               mode change
Q12;7;250;40                       quest turned in: id; xp; money
@5;0;-8950;-60;f;h;8690            hearthstone: new segment, no line drawn
@3;36;;;f;i                        instance entered: no position until the next @
!0;1793452830                      clock set (only when the clock went back)
.1;t                               page end: reason t time, s size, l stale at login
```

The header's `E1` is the format (1), not a kind with a `dt`; it is always the page's first line.
`t0` is the page's start, the header's time.

**Lines every page has**

| Line | Meaning | Fields |
|---|---|---|
| `E` | header (first line; `E` and the format) | acct; store; n; t0; locale; build; addon version |
| `C` | the character | key (first name-realm); full name; GUID; class; race; sex; level; faction |
| `@` | anchor: a new segment of the path, no line drawn from the point before | continent (the instance map ID: 0 Eastern Kingdoms, 1 Kalimdor, a dungeon's); north; west (whole yards, empty where there is no position: no points until the next anchor with one); mode; why; spell |
| `z` | zone | uiMapID; subzone text (the client's language: pages carry the locale) |
| (digit) | path point | `dt,dnorth,dwest` |
| `=` | a name, once per page for each namespace and id | namespace (c creature, q quest, i item); id; text |
| `m` | travel mode changed | mode |
| `!` | clock set: the time is this, absolute (the encoder writes it when the clock went back) | time |
| `.` | page end | reason: t time, s size, l stale at login |

**Travel modes** (the `@` and `m` lines): t flight path, g ghost, c carried (boat, zeppelin), s
swimming, m mounted, v travel form, f on foot.

**Why a segment starts** (the `@` line's `why`):

| Code | Cause |
|---|---|
| h | hearthstone (field: spell) |
| p | teleport spell (field: spell) |
| u | summon |
| r | release to graveyard |
| i | instance entered |
| o | instance left |
| s | login |
| l | loading screen |
| j | other jump (someone else's portal, say) |
| c | continued: the first anchor of a new page, at the last page's last position (the path goes on) |

**Event kinds** (letters can still change while they're being built):

| Line | Meaning | Fields |
|---|---|---|
| `L` | level-up | level; played seconds |
| `x` | XP | level; xp; max; rested; resting 0/1 |
| `a` / `Q` / `A` | quest accepted / turned in / abandoned | id (/ xp; money) |
| `D` | death | level; killer kind c/p/-; creature id or class; killer level; classification; pvp 0/1 |
| `r` | back to life | how: s spirit healer, p player, c corpse |
| `k` | kill | creature; level; classification; who m/p/g |
| `l` | loot | item; count; quality; l looted / p pushed; source creature |
| `g` | group | size; others; guid:name,... |
| `G` | gear | slot; item; enchant; suffix |
| `f` | AFK | 1 start / 0 end |
| `R` | reputation | faction; standing |
| `h` | gathering | kind h/o/s/f; node or creature; item:count,... |
| `p` / `b` | honorable kills / battleground | count / instance; e entered, x left, w won, l lost; duration |
| `n` | new collection item | kind m/p/t/a/r (mount, pet, toy, achievement, recipe); id |
| `s` | profession | skill; rank; max |
| `H` | hearthstone bound | place |
| `F` | flight | from node; to node |
| `d` / `B` | dungeon / boss | e entered or x left; instance; difficulty / encounter id |
| `o` | session | 1 login, 0 logout |

**Readers must**
- skip unknown kinds but still add their `dt`, so new kinds never break an older exporter;
- ignore extra fields and treat missing ones as empty.

**Fields**
- WoW's markup is removed first: textures (`|T...|t`), atlases (`|A...|a`), colours (`|cAARRGGBB`,
  `|cn<name>:`, `|r`); a link (`|H...|h[text]|h`) becomes its text without the brackets. The capture
  stores links as ids.
- Then `%`, `;`, `,`, `|` and bytes below 0x20 are written as `%XX` (upper-case hex). Everything else
  stays as it is, UTF-8 letters too.
- Numbers: whole ones as integers (`-9046`, `1793452800`, never `-0` or `1e+10`), others with at
  most two decimals (`3.25`); not-a-number and infinity are empty. `true` is 1, `false` 0.
- nil, a secret and anything else are empty; empty fields at the end of a line are left out.

Second-order deltas (velocity changes) were tested and saved only 3% after compression, so points
stay plain deltas.

**The encoder** (`Lines.lua`). Nothing is written while Echoes doesn't record (switched off, or the
beta): the writers return nil (`E.Name` false).

- `E.Now()`: the time lines are written in, `GetServerTime()` (the computer's `time()` if it's
  missing), whole seconds.
- `E.Line(kind, ...)`: writes `kind .. dt .. ";" .. fields` and returns the line. `kind` is one
  letter or `@ = ! .` (anything else is an error). `dt` is the seconds since the last line; if the
  clock went back (or no line has a time yet), `!0;<now>` goes first and the line gets `dt` 0.
- `E.Anchor(continent, north, west, mode, why, spell)`: an `@` line; north and west are rounded to
  whole yards (both nil: an anchor without a position). The next points count from it.
- `E.Point(north, west)`: a point, `dt,dnorth,dwest` from the last position (whole yards). Nothing
  before the page's first anchor, after an anchor without a position, or for a position that isn't
  a readable number.
- `E.Mode(mode)`, `E.Zone(uiMapID, subzone)`: the `m` and `z` lines.
- `E.Name(namespace, id, text)`: an `=` line once per page per namespace and id; true if written
  now (false: already named, or no text or id). `E.ResetNames()` names everything again.
- For the pages: `E.PageStart(t0)` (the next line's `dt` counts from `t0`, now if nil; names
  again; points wait for an anchor; `E.bytes` and `E.count` start at 0), `E.Raw(line)` (a line as
  it is: the header), `E.Continue()` (an `@` line with why `c` at the last position known, the mode
  and the zone again; false and nothing written when nothing is known yet), `E.OnLine(fn)`
  (`fn(line, kind)` after every line, through `LT.Guard`; `kind` nil for points and raw lines;
  hooks only note things, a page is closed on the tick), `E.Take()` (the lines not taken yet as text,
  each ending in `\n`, and the buffer emptied).
- `E.buffer`: the lines not taken yet (strings without `\n`: no concatenation per point);
  `E.bytes` / `E.count`: bytes (with each `\n`) and lines since the page started.
- `E.state`: what the encoder keeps, a plain table every function reads anew (the pages may keep it
  with an open page and put it back after a `/reload`): `t` (the last line's time), `anchored`,
  `continent`, `north`, `west` (the last position written), `mode`, `map`, `sub` (the last zone),
  `names` (`"c:327" = true`).

## Pages and storage

`LefthyToolsEchoesDB`, account-wide, made at load (`LT.onLoad`, after Core's stamp):

```lua
LefthyToolsEchoesDB = {
  world = "release",  -- Core's stamp
  v = 1,              -- the layout
  store = "9f3a61c2", -- 8 random lowercase hex digits, made once: this WTF folder's
  acct = "1a2b3c4d",  -- my BattleTag's hash (LT.Hash32 of the lowercased BattleTag), filled in later
  session = 41,       -- +1 at every load (a /reload too): what came this session, what's on disk
  n = 213,            -- the last closed page's number (0: none yet)
  open = nil,         -- the page being written (plain text, never shared); nil: none
  mine = {},          -- my closed pages
  carry = {},         -- friends' pages I relay
  safe = {},          -- what collectors hold safely
  inbox = {},         -- a collector's: pages received
  exported = {},      -- a collector's: pages the exporter has
}
```

A field that isn't what it should be is made new (a table that isn't one, a store that isn't 8 hex
digits); nothing else is touched. Pages themselves are not built yet.

## Delivery

Not built yet: the `B2;e...` messages through Beacon, pulling, relaying and collecting, driven by
the settings above.
