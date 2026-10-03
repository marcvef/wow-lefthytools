# LefthyTools

A collection of small interface tools for WoW: Forever, in one addon. Each tool is a
module you can switch on or off.

| Module | What it does |
|---|---|
| [Mirage](#mirage) | Fades the interface away when you're out of combat and not using it, like Dune: Awakening's Dynamic HUD. **Off by default**: switch it on on the overview page |
| [Misc Tweaks](#misc-tweaks) | Small fixes, each switchable: always-visible health/power values, combo points on the personal resource display, movable bags, quest progress in party chat, markers for quests new in WoW: Forever |
| [Beacon](#beacon) | Battle.net friends who also use LefthyTools see each other on the world map and minimap, with status and level-up messages, without needing a group |

## Settings

Open **Options → AddOns → LefthyTools**, click LefthyTools in the minimap's addon
compartment, or type `/lefthy` (short: `/lt`).

- **LefthyTools** (overview): a switch for each module, and an **Info** section with your
  version and whether a newer one is out. LefthyTools can't go online itself, so it knows about
  updates from Battle.net friends who run it (Beacon).
- One page per module below it, e.g. **LefthyTools → Mirage**.

```
/lefthy                            open settings
/lefthy modules                    list modules and whether they're on
/lefthy enable | disable <module>  switch a module, e.g. /lefthy disable mirage
/lefthy <module> ...               module commands, e.g. /lefthy mirage status
```

Key bindings are under Options → Keybindings → AddOns → LefthyTools.

**Language:** the settings pages and Beacon's tooltips follow the game client's language. They're
available in English and German (German on a `deDE` client). Chat commands and chat messages stay
English, except what others see or what's meant for everyone: the quest announcements your party
reads and the default level-up message.

## Install and update (Windows)

1. Download [Update-LefthyTools.cmd](https://github.com/marcvef/wow-lefthytools/raw/main/Update-LefthyTools.cmd)
   (if the browser shows the text instead: right-click the link → *Save link as*) and keep it,
   e.g. on your desktop.
2. Double-click it. It finds your WoW: Forever folder, downloads the latest LefthyTools from
   this page and installs it. If Windows asks whether to run it, choose *Run* (or *More info* →
   *Run anyway*). If it can't find the game, it asks for your `World of Warcraft` folder once.
3. In game, type `/reload`.

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
| Mark quests that are new in WoW: Forever | Forever adds over a thousand quests to the Classic world. They get a **NEW** right after their name in the quest log (hover the quest for an explanation), in the quest details and in the quest window when you accept or turn one in. The list of these quests comes from the game's own quest tables (about 1,800 quests). | `/lefthy tweaks newquests on\|off` |
| Movable bags | Drag a bag by its title bar or any empty spot. It reopens where you left it. A plain click on the title still opens the bag menu. | `/lefthy tweaks bags on\|off` |
| Announce quest progress in party chat | Like Questie: when you finish a quest objective, your character posts it in party chat, e.g. `[Kobold Camp Cleanup]: 10/10 Kobold Vermin slain`. When that completes the whole quest, you get one `[Quest]: quest complete!` line instead. Posts in party chat (instance chat in dungeon groups), never solo or in raids. Quests already done when accepted stay quiet. | `/lefthy tweaks quests on\|off` |

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
  ghost on the way back), a **red pulsing ring** means they're in combat. On the minimap
  the dots glide smoothly; friends out of range wait faded at the edge, so you see which
  way they are.
- **Hover a dot** for name (with AFK/DND), BattleTag, level, zone and subzone, who
  they're fighting, and how far away they are and in which direction ("240 yd north-east").
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
| Update interval (while moving) | 3 s | `/lefthy beacon interval <1-10>` |
| Show friends on the world map | on | |
| Show friends on the minimap | on | |
| Keep far-away friends at the minimap edge | on | |
| Show friends in my group too | on | |
| Tell my friends when I level up | on | |
| Level-up message (`{name}` and `{level}` are filled in) | empty: default text | `/lefthy beacon ding <text>`, `ding reset` |
| Test your message: **Preview** | | `/lefthy beacon ding test` |
| Show my friends' level-ups | on | |
| Play a sound | on | |
| Level-up sound: boss defeated fanfare, world quest complete, legendary loot, epic loot, scenario complete or a gentle chime. Picking one plays it | boss defeated fanfare | `/lefthy beacon sound [<number>]` |

`/lefthy beacon status` lists friends with LefthyTools online, their LefthyTools version,
when their last position arrived, and how many messages were sent and received per minute.
**Update notice:** if a friend runs a newer LefthyTools than you, you're told once per login,
with how to update. Friends on a much older LefthyTools (before 0.3.0) can't see you at all
and are listed with a hint to update. Switching Beacon off on the overview page stops
everything and removes your dot from your friends' maps.

---

## Mirage

Fades the interface away when you're out of combat and not using it, and brings it
back the moment you are.

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
| Faded opacity | 0% | `/mirage alpha <0-100>` |
| Hide quest areas at: minimap opacity at which the minimap and its quest overlay are hidden | 0% | `/mirage overlay <0-100>` |

Other commands:

```
/mirage on | off | toggle     switch the module (same as the overview checkbox)
/mirage groups                list element groups
/mirage group <name> on|off   fade (or stop fading) one group, e.g. /mirage group chat off
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
