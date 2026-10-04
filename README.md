# LefthyTools

A collection of small interface tools for WoW: Forever, in one addon. Each tool is a
module you can switch on or off.

| Module | What it does |
|---|---|
| [Mirage](#mirage) | Fades the interface away when you're out of combat and not using it, like Dune: Awakening's Dynamic HUD. **Off by default**: switch it on on the overview page |
| [Misc Tweaks](#misc-tweaks) | Small fixes, each switchable: always-visible health/power values, combo points on the personal resource display, movable bags, quest progress in party chat, markers for quests new in WoW: Forever, your quests on continent and world maps |
| [Beacon](#beacon) | Battle.net friends who also use LefthyTools see each other on the world map and minimap, with status and level-up messages, without needing a group |
| [Chronicle](#chronicle) | A journal for each character that writes itself: level-ups, deaths, dungeons, bosses, rares, loot, mounts and milestones, lots of statistics, and what your friends did |

## Settings

Open **Options → AddOns → LefthyTools**, click LefthyTools in the minimap's addon
compartment, or type `/lefthy` (short: `/lt`).

- **LefthyTools** (overview): a switch for each module, and an **Info** section with your
  version, whether a newer one is out, and LefthyTools errors. LefthyTools can't go online
  itself, so it knows about updates from Battle.net friends who run it (Beacon).
- One page per module below it, e.g. **LefthyTools → Mirage**.

```
/lefthy                            open settings
/lefthy modules                    list modules and whether they're on
/lefthy enable | disable <module>  switch a module, e.g. /lefthy disable mirage
/lefthy <module> ...               module commands, e.g. /lefthy mirage status
/lefthy errors [clear]             LefthyTools' own errors, ready to copy
/lefthy news                       what's new (also opens by itself once after an update)
```

**If something breaks:** LefthyTools keeps its own Lua errors, also across sessions and with
Blizzard's error display off, and says so once in chat. Type `/lefthy errors`, click into the
text, press Ctrl+A and Ctrl+C, and send it to whoever gave you LefthyTools.

Key bindings are under Options → Keybindings → AddOns → LefthyTools.

**Language:** the settings pages and Beacon's tooltips follow the game client's language. They're
available in English and German (German on a `deDE` client). Chat commands and chat messages stay
English, except what others see or what's meant for everyone: the quest announcements your party
reads and the default level-up message.

## Install and update (Windows)

1. Download [Update-LefthyTools.cmd](https://github.com/marcvef/wow-lefthytools/raw/main/Update-LefthyTools.cmd)
   (if the browser shows the text instead: right-click the link → *Save link as*) and keep it,
   e.g. on your desktop. It's the whole installer in one file, so you can pass it on to
   friends as it is.
2. Double-click it. It finds your WoW: Forever folder, downloads the latest LefthyTools from
   this page, installs it and checks every installed file against the download. If Windows asks
   whether to run it, choose *Run* (or *More info* → *Run anyway*). If it can't find the game, it
   asks for your `World of Warcraft` folder once. If it finds Forever in more than one place, it
   uses the one you played most recently and lists the others.
3. In game, type `/reload`. If the installer says the update adds files, restart the game instead.
   `/lefthy version` should then show the version the installer printed.

To **update**, double-click it again: it installs the latest version, or tells you that you
already have it. Your settings are kept. `/lefthy version` shows what you're running, and Beacon
tells you when a friend has a newer one.

Without the file, the same in PowerShell:

```powershell
irm https://raw.githubusercontent.com/marcvef/wow-lefthytools/main/install.ps1 | iex
```

**Versions** look like `0.4.0` (a release) or `0.4.0-3-g1a2b3c4`: three changes after 0.4.0,
at commit `1a2b3c4`.

### From a clone of this repo

```powershell
.\install.ps1            # install this checkout (version stamped from git)
.\install.ps1 -Link      # dev mode: junction to this folder, so edits only need /reload
.\install.ps1 -Download  # install the latest version from GitHub instead
.\install.ps1 -GameDir "D:\...\World of Warcraft\_classic_beta_"   # if it isn't found
```

The installer also removes the old standalone `Mirage` addon, which is now part of
LefthyTools. How it works inside (for developers): see [docs/](docs/architecture.md).

## Known limitations (Forever beta)

- **Closing the settings panel can freeze the game in gamepad mode.** With the
  controller UI enabled, closing Options after changing a setting hangs the client.
  Turn gamepad mode off while changing settings.

---

## Misc Tweaks

Small annoyances fixed. Each tweak has its own checkbox under **Options → AddOns →
LefthyTools → Misc Tweaks**, and all are on by default.

| Tweak | What it does | Command |
|---|---|---|
| Always show health & power values | Health and power bars show `current / max` all the time, not only on mouseover. This applies to every unit frame (player, target, focus, pet, party). It's the same as Blizzard's Options → Interface → Status Text set to Numeric. Switching it off restores your previous Status Text setting. | `/lefthy tweaks statustext on\|off` |
| Combo points on the personal resource display | Forever's personal resource display (the bars under your character) leaves combo points out. This adds them under its bars in retail's style: red gems in sockets, with Blizzard's slash-and-glow animation when you gain a point and a burst when you spend them. At full points the gems breathe: finisher ready. It moves, scales, hides and fades with the display and follows its Edit Mode settings. Rogues, and druids in Cat Form. | `/lefthy tweaks combo on\|off` |
| Colour combo points by count | The gems change colour with the number of points: green with one, through yellow and orange, to red at full. Off: retail's red. | `/lefthy tweaks combocolors on\|off` |
| Mark quests that are new in WoW: Forever | Forever adds over a thousand quests to the Classic world, plus quests from Classic's later seasons (Season of Discovery and the like) that original Classic never had. They get a **NEW** right after their name in the quest log (hover the quest to see which kind it is), in the quest details and in the quest window when you accept or turn one in. The lists come from the game's own quest tables (about 1,800 new in Forever and 1,050 from the later seasons). | `/lefthy tweaks newquests on\|off` |
| Quests on continent and world maps | Blizzard's map shows your quests only on zone maps. This shows them on continent maps and the world map too: Blizzard's quest icon where to go (hover it for the objectives) and the area where the mobs and items are. Choose what each zoom level shows: *On continent maps* and *On the world map*: nothing, icons, areas, or both (the default). With icons only, hovering one shows its area. *Click an icon to select its quest* (on): as on zone maps, a click selects the quest (waypoint arrow and its area; tracked if it wasn't), a second click unselects it, Shift-click stops tracking it; off, a click zooms into the zone (with a controller the button always does). *Quest areas on zone maps*: the selected quest's area (Blizzard's) or every quest's, like Questie. The map's own filter for quest objectives hides them too. | `/lefthy tweaks questmap on\|off` |
| Movable bags | Drag a bag by its title bar or any empty spot. It reopens where you left it. A plain click on the title still opens the bag menu. | `/lefthy tweaks bags on\|off` |
| Announce quest progress in party chat | Like Questie: when you finish a quest objective, your character posts it in party chat, e.g. `[Kobold Camp Cleanup]: 10/10 Kobold Vermin slain`. When that completes the whole quest, you get one `[Quest]: quest complete!` line instead. Posts in party chat (instance chat in dungeon groups), never solo or in raids. Quests already done when accepted stay quiet. | `/lefthy tweaks quests on\|off` |
| AFK screen | While you're AFK, the interface disappears, the camera slowly circles your character (*Circle the camera*, on), and a panel shows your character, how long you've been away, the time, your level progress, whispers and friends' news since then, your session (with Chronicle on) and your Beacon friends: where they are, what they're doing and which quest they're on. Moving, combat, a ready check or invite, opening a window, or a click brings everything back. Works without Mirage. | `/lefthy tweaks afk on\|off` |
| Cinematic flights | On a flight path the interface fades out, thin black bars slide in like in a film, and a title card names your destination and every zone you fly into, with its level range and the friends who are there. The bottom bar shows the time left to landing (from the game's own flight path data, and exact once you've flown a route), and whispers, party chat and items your Beacon friends show (and who won an offer) appear as subtitles. You can still move the camera; opening a window, typing in chat or a friend's offer waiting for your Need or Pass pauses it until you're done. Landing brings everything back. | `/lefthy tweaks flights on\|off` |

```
/lefthy tweaks             open the Misc Tweaks settings
/lefthy tweaks status      list tweaks and whether they're active
/lefthy tweaks resetbags   move all bags back to Blizzard's spot
```

The commands work in controller mode, so you don't need the settings panel, which
can freeze in gamepad mode (see Known limitations).

---

## Beacon

Your Battle.net friends who also run LefthyTools show up as dots on your world map and
minimap, and you on theirs, without being in a group.

- **Dots** are in the friend's class colour. A **skull** means they're dead (faded: a
  ghost on the way back), a **red pulsing ring** means they're in combat, and a **number**
  how many enemies are on them (counted from the nameplates they see). Friends on the same
  spot move slightly apart so every dot shows, and hovering one shows all of them. On the minimap
  the dots glide smoothly; friends out of range wait faded at the edge, so you see which
  way they are.
- **Hover a dot** for name (with AFK/DND), BattleTag, level and progress on it ("Level 20
  (64%)"), zone and subzone, who
  they're fighting, the quest they're tracking with their progress (and whether you have it
  too), and how far away they are and in which direction ("240 yd north-east").
- **Death alerts:** a chat line when a friend dies, with where and what they were fighting
  ("Anna died in Duskwood - Raven Hill, fighting Stitches.").
- **Show an item:** **Ctrl+right-click** any item (bags, bank, character, loot, chat links) and
  your friends see "Anna shares [item]" at the top of the screen with the whisper sound (hover it
  for the item's tooltip), plus a clickable link in chat.
- **Offer an item:** **Ctrl+Shift+right-click** an item you can trade (not soulbound), and they
  get **Need** and **Pass** buttons under it. One Need gets it; several Needs are rolled out, with a drumroll, whirling
  numbers and the winner popping up in gold letters with a fanfare. Until you trade or mail it
  to the winner, the item is reserved for them: its tooltip says "Won by Anna: still to hand
  over", its bag slot has an orange border, a vendor asks before selling it, a trade with them
  reminds you in chat, and attaching it to a mail fills in their name (`/lefthy beacon handover`
  lists what you still owe). (For gear, Ctrl+click also opens the
  game's preview, as always.)
- **Without a click:** `/lefthy beacon show` or `/lefthy beacon offer`, then Shift-click the
  item into the chat box, for when a click doesn't reach it (some bag addons, gamepad). If an
  item can't be shared, chat always says why.
- **Map pings:** **Alt+click** on the world map shows your friends a spot ("meet here"): a
  rippling marker on their world map and minimap for a minute, a chat line and a ping sound.
  `/lefthy beacon ping` pings where you stand.
- **Level-ups:** when you level up, your friends get your own message in big letters
  with a sound, e.g. `{name} hit {level}, drinks on me!`. Leave it empty and they see
  "Anna reached level 21!" in their own language.
- **No server needed:** everything goes through the game's own Battle.net addon
  messages. Each player's LefthyTools sends their own position and status to friends
  who have the addon.
- **Light on the connection:** your position is only sent when you move (every 3 s
  by default) or your status changes. Standing still sends one tiny message every
  20 seconds. All messages go through a rate limit.
- **Who sees you:** only Battle.net friends who also run LefthyTools 0.3.0 or newer
  with Beacon on. Friends without the addon never get more than a short hello.
- **Friends in your group** keep their dot, with a **blue ring**, right on top of the game's
  own group dot, and the tooltip says "In your group" (switch this off to see only the
  game's dot).
- **Not shown:**
  - anyone in a dungeon or raid (the game hides positions there),
  - friends on another continent than the map you're looking at,
  - health: the game keeps health hidden from addons in Forever.

| Setting | Default | Command |
|---|---|---|
| Share my position | on | |
| Share the quest I'm tracking | on | |
| Update interval (while moving) | 3 s | `/lefthy beacon interval <1-10>` |
| Show friends on the world map | on | |
| Show friends on the minimap | on | |
| Keep far-away friends at the minimap edge | on | |
| Show friends in my group too | on | |
| Tell me when a friend dies | on | |
| Show items to friends (Ctrl+right-click) | on | |
| Map pings (Alt+click on the world map) | on | `/lefthy beacon ping` |
| Tell my friends when I level up | on | |
| Level-up message (`{name}` and `{level}` are filled in) | empty: default text | `/lefthy beacon ding <text>`, `ding reset` |
| Test your message: **Preview** | | `/lefthy beacon ding test` |
| Show my friends' level-ups | on | |
| Play a sound | on | |
| Level-up sound: boss defeated fanfare, world quest complete, legendary loot, epic loot, scenario complete or a gentle chime. Picking one plays it | boss defeated fanfare | `/lefthy beacon sound [<number>]` |

`/lefthy beacon status` lists friends with LefthyTools online, their LefthyTools version,
when their last position arrived, and how many messages were sent and received per minute.
**Update notice:** if a friend runs a newer LefthyTools than you, you're told once per login,
with how to update, whether a `/reload` is enough or the game needs a restart, and what's
coming: one line per change (the newest eight). This needs both of you on 0.5.0 or newer.
Friends on a much older LefthyTools (before 0.3.0) can't see you at all
and are listed with a hint to update. Switching Beacon off on the overview page stops
everything and removes your dot from your friends' maps.

---

## Chronicle

A journal for each of your characters that writes itself. Open it with the **book button on the
minimap** (drag it along the edge; right-click for the settings; `/chronicle minimap` hides it),
`/chronicle`, the button on its settings page, or a key binding (*Chronicle: open or close the
journal*).

- **Timeline**, newest first, by day: level-ups (and how long each level took), deaths (where,
  and what killed you), zones discovered, first visits to dungeons, bosses defeated, rare
  elites killed, blue and better loot, new mounts, pets and toys, achievements, professions
  learned and their milestones, and milestones for quests (10, 25, 50, 100, ...) and gold
  (1, 10, 50, 100, ...).
- **Statistics**, for this session and the character: time played, days played, sessions,
  fastest and average level, quests (and how many were new in WoW: Forever), experience,
  zones discovered and your favourite zone, dungeon runs, killing blows, rare elites, bosses,
  deaths and your deadliest foe, distance on foot, riding, swimming and on flight paths, jumps,
  gold earned, spent and the most you ever had, loot by quality, mounts, pets, toys and
  achievements. And the **Martin tracker**: how long you've been AFK, its share of your play
  time, how often and the longest stretch, with a verdict from "Always there" to "Practically
  Martin".
- **Graphs:** the last 14 days (time played, XP, quests or kills per day), this session's XP
  curve with XP per hour, how long each level took (green fast, red slow), your favourite zones
  and deadliest foes, how you travel, and your loot by quality. Hover a bar for its value.
  Pick one of your **friends** in the dropdown at the top: their last 14 days, their week in
  numbers, you and them side by side, and their latest news, also for the time you weren't online.
- **Friends:** what your Battle.net friends with LefthyTools did: their level-ups, deaths and
  highlights (bosses, rares, first dungeon visits, epic loot, mounts, achievements and
  milestones). Your own highlights go to them the same way (needs Beacon).
- **All your characters:** pick one in the dropdown at the top.
- `/chronicle session` prints this session in one line; the AFK screen shows it too.

Everything counts from when Chronicle first saw a character. It's recorded in the background
once a second, so it costs nothing you'd notice.

| Setting | Default |
|---|---|
| Share highlights with friends | on |
| Show friends' highlights in chat | on |

---

## Mirage

Fades the interface away when you're out of combat and not using it, and brings it
back the moment you are. (The AFK screen is a [Misc Tweak](#misc-tweaks) and works without
Mirage.)

### What fades

Each element group fades as a unit and can be switched off individually:

| Group | Frames |
|---|---|
| `actionbars` | Main bar, extra bars 2–8, stance, pet, possess and totem bars |
| `controller` | The controller action bar cluster and its button-prompt legend |
| `reticle` | The controller aiming reticle (**off by default**: you aim interactions with it) |
| `unitframes` | Player, pet, target, focus, personal resource display |
| `party` | Party and raid frames |
| `cooldowns` | Cooldown Manager, swing timer |
| `buffs` | Buffs and debuffs |
| `minimap` | Minimap cluster |
| `objectives` | Quest / objective tracker |
| `menu` | Micro menu and bag bar |
| `xpbars` | Experience and reputation bars |
| `meter` | Built-in damage meter |
| `chat` | Chat windows, tabs, buttons |
| `misc` | Durability figure, vehicle seat indicator |

**Minimap quest areas** are drawn by the game engine and ignore transparency. Once the
minimap has faded down to the "Hide quest areas at" opacity, Mirage hides the minimap
entirely so the quest areas go with it, and shows it again as soon as it fades back
in. This only happens at 0% faded opacity, and you can turn it off ("Also hide
minimap quest areas"). If you turn the minimap off yourself with the Toggle Minimap
key, it stays off.

Popups, loot rolls, the cast bar, the extra action button, the breath timer and the
loss-of-control alert are never faded.

### What keeps it visible

The whole interface stays visible while any of these is true, and fades once none
has been true for the **idle delay**:

- in combat (and for the idle delay afterwards)
- casting or channeling, or using an ability
- a living target is selected (optionally: attackable targets only)
- a window is open: bags, map, character sheet, vendor, quest dialog, settings, …
- something is on the cursor (dragging a spell or item)
- Edit Mode is open
- on a controller: a trigger or shoulder modifier is held, or HUD mode, the radial
  menu, the action bar editor or a bar flyout is open
- in a vehicle, or dead / a ghost
- while moving (off by default, so running around counts as idle)

Some elements also reveal on their own for a few seconds:

- **Mouseover:** hovering over where a faded element sits reveals that group.
- **Player frame:** stays visible while health or mana regenerates.
- **Chat:** new whisper, party, raid, guild or instance messages reveal it; it also stays visible while you type.
- **Quest tracker:** shown when quest objectives progress.
- **XP bar:** shown when you gain experience or reputation.
- **Minimap:** shown when you enter a new zone.

### Mirage settings

**Options → AddOns → LefthyTools → Mirage**, or `/mirage`.

| Setting | Default | Command |
|---|---|---|
| Idle delay: inactivity before fading starts | 5 s | `/mirage delay <seconds>` |
| Fade-out duration: how long the fade takes | 1.5 s | `/mirage fade <seconds>` |
| Fade-in duration | 0.25 s | `/mirage fadein <seconds>` |
| Faded opacity: sets every element at once | 0% | `/mirage alpha <0-100>` |
| Elements to fade: per element a switch and its own faded opacity, e.g. minimap only down to 50% | on, 0% | `/mirage group <name> on\|off\|<0-100>` |
| Hide quest areas at: minimap opacity at which the minimap and its quest overlay are hidden (only when the minimap fades to 0%) | 0% | `/mirage overlay <0-100>` |

Other commands:

```
/mirage on | off | toggle     switch the module (same as the overview checkbox)
/mirage groups                list element groups and how far each fades
/mirage group <name> on|off   fade (or stop fading) one group, e.g. /mirage group chat off
/mirage group <name> <0-100>  how visible one group stays when faded, e.g. /mirage group minimap 50
/mirage status                what's currently keeping the interface visible
/mirage reset                 restore defaults
/mirage help
```

**Key bindings** (Keybindings → AddOns → LefthyTools):
- *Mirage: toggle interface fading*: switches the module on or off. Off fades
  everything back in and stops Mirage completely.
- *Mirage: show interface (hold)*: shows everything while the key is held.

### Mirage limitations

- **No "show when damaged".** Health is a secret value for addons in Forever, so
  Mirage can't compare health to maximum. It uses the health-changed event instead,
  which covers regeneration and taking damage.
- Faded elements can still be clicked, just like mouseover bars in other addons.
  Hovering reveals them first.
