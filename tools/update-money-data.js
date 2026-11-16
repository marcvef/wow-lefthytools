// Regenerates LefthyTools_MoneyData/MoneyData.lua: what WhyPoor? (Modules/WhyPoor; Data.lua reads it,
// docs/whypoor.md has the contract) needs to know about making money in the world: the creatures worth
// farming and where they are, gathering nodes per zone map, fishing per zone, pickpocketing,
// disenchanting and limited vendor stock. A separate add-on (GPL v3, like its main source), loaded only
// when WhyPoor? needs it. LefthyTools_MoneyData/README.md describes every field for players and readers.
//
// Sources:
// - CMaNGOS Classic DB's full dump (https://github.com/cmangos/classic-db, Full_DB z2815, GPL v3; the same
//   dump as tools/update-drop-data.js and update-quest-data.js): creature_template, creature,
//   creature_spawn_entry, gameobject_template, gameobject, gameobject_spawn_entry, pool_template,
//   pool_creature, pool_gameobject, pool_pool, spawn_group, spawn_group_spawn, spawn_group_entry,
//   game_event_creature, game_event_gameobject, the loot tables (gameobject_, fishing_, pickpocketing_,
//   disenchant_, reference_loot_template), conditions, skill_fishing_base_level, item_template,
//   npc_vendor, npc_vendor_template.
// - WoW: Forever's own client tables (wago.tools exports of the build): UiMap, UiMapAssignment, AreaTable,
//   Map, WorldMapOverlay, UiMapXMapArt (zones and where spawns go on their maps: update-quest-data.js's
//   rules, reused), FactionTemplate, Faction, ChrRaces (how a creature reacts to each side), Lock (the
//   skill a herb, a vein or a locked chest needs), ItemSparse and Item (which items the client knows, vendor
//   prices, disenchanting's item classes), ItemDisenchantLoot (disenchanting's groups and skill).
// - EG Link output for Forever (Efficient Games, https://github.com/JIVESCORP/eg-link-output-wowf, CC BY
//   4.0): the positions players' games recorded with their zone map, only to decide the zone where zones'
//   rectangles overlap (update-quest-data.js's bestBox), and the reactions players saw creatures have
//   (below).
// Not used: Wowhead, Questie, Attune (the project's rule).
//
// Rules:
// - Spawns: a creature's or object's rows in creature / gameobject; a row with id 0 is one of the entries
//   creature_spawn_entry / gameobject_spawn_entry (else spawn_group_entry) lists for it, each as likely
//   (or by its Chance). Left out: spawns only while a game event is on (game_event_*, event > 0) and
//   battlegrounds. How many are up at once (up, an estimate): a pooled spawn's share of its pool's
//   max_limit (min(1, limit / members), times its mother pool's the same way; limit 0: all), a spawn group's
//   MaxCount the same way, a random entry's chance. n: the spawn points.
// - Places: each spawn on the zone map the client has there (update-quest-data.js's places() and its first
//   choice: the smallest zone rectangle holding it, and where rectangles overlap the maps EG Link recorded
//   this creature or object on, players' recorded positions nearby, the zones' explored-area images), then
//   in clusters (update-quest-data.js's clustering: spawns within CLUSTER thousandths of the map's width
//   are one; centre, radius, count), the most spawns first.
// - Creatures (mobs): those with loot, coin, skinning or pickpocketing (creature_template LootId,
//   MaxLootGold, SkinningLootId, PickpocketLootId) and a spawn outside events, not critters (CreatureType 8),
//   totems (11), invisible (ExtraFlags 0x80), not selectable (UnitFlags 0x2000000) or not attackable
//   (UnitFlags 0x2), triggers and unused ones by their name; not the ones friendly to both sides, nor the
//   ones of a faction with reputation that neither side's characters start hostile with (killing them costs
//   standing: Booty Bay's bruisers). Rank: creature_template Rank (0 normal, 1 elite, 2 rare elite, 3 boss,
//   4 rare). Skinning: SkinningLootId (classic has no herb or ore loot from creatures: CreatureTypeFlags
//   0x100 / 0x200 are never set in this dump, and the tool fails if one is). Respawn: the median of its
//   spawns' (spawntimesecsmin + spawntimesecsmax) / 2. Instance: every spawn in a dungeon or raid.
// - Reactions (what the creature does to a character of that side, as the client works it out; CMaNGOS'
//   Relations.cpp, whose functions name their client counterparts): a faction with reputation
//   (Faction.ReputationIndex >= 0) reacts by the character's standing, here the one a new character starts
//   with (Faction.ReputationBase of the first row whose race mask, and class mask if any, has the race):
//   up to -3001 hostile (hated, hostile), -3000..2999 neutral (unfriendly, neutral), 3000 up friendly; else
//   the faction templates' groups and lists (FactionTemplate EnemyGroup / Enemies: hostile; FriendGroup /
//   Friend either way: friendly; else neutral) against the character's template (ChrRaces.FactionID). Each
//   side's every playable race and class; when they differ, the friendliest (printed). Where players' games saw
//   a creature of a faction without reputation react one way to a side (EG Link's reactions: 1-2 hostile, 3-4
//   neutral, 5-8 friendly), that wins (Forever's server; flag A / H): Mesa Buzzards are hostile on Forever,
//   classic-db's faction is neutral. Not for a faction with reputation (it depends on who looked).
// - Gathering nodes: chests (gameobject type 3) whose lock (Lock, by data0) needs Herbalism (LockType 2) or
//   Mining (3): that entry's Skill; treasure chests (a Treasure entry, LockType 6, not quest-only: flags 0x4)
//   with Lockpicking's skill when they're locked (flags 0x2) and their lock has a Pick Lock entry, else 0;
//   fishing schools (type 25: the zone's fishing skill applies). Loot: gameobject_loot_template by data1;
//   times one can be looted: data4..data5 (chests: "min / max successful loot attempts"; at least once),
//   data2..data3 for schools. Only nodes with a spawn on a zone map.
// - Loot (every table): one row drops on its own with its chance; in a group one item of the group drops
//   (rows without a chance share what's left evenly); a reference rolls its table with the row's chance, as
//   many times as maxcount says; an item reached several ways: 1 - the product of (1 - each chance); count
//   min..max (mincountOrRef..maxcount; through a reference rolled k times, up to k times its max). Left out:
//   quest-only rows (negative chance), rows with a condition other than a game event (flag e: only while it's
//   on, e.g. Winter Squid), a side (A, H) or a skill; items the client doesn't know (not in ItemSparse);
//   chances under MIN_CHANCE.
// - Fishing (CMaNGOS' GameObject.cpp): the area's skill_fishing_base_level (the subzone's, else the zone's)
//   is the base; a catch needs skill >= base and succeeds with skill - base + 5 percent, so it's sure from
//   base + 95. Loot: the subzone's fishing_loot_template, else the zone's. Per zone map its zone area; its
//   subzones with their own base or loot apart (fishingAreas).
// - Pickpocketing: pickpocketing_loot_template by PickpocketLootId (the creatures in mobs).
// - Disenchanting: which items and the skill by Forever's client: an item in ItemSparse when its class (Item),
//   quality and item level are in an ItemDisenchantLoot row and it lacks the "can't be disenchanted" flag
//   (Flags_0 0x8000); the skill that row's SkillRequired (at least 1: Enchanting learned). An item ItemSparse
//   lacks: classic-db's DisenchantID, classic's class, quality and level. Results: classic-db's
//   disenchant_loot_template of the item's DisenchantID (numbered otherwise than the client's rows), else of the
//   group 90% or more of the classic items of its client row and inventory type (else row) use.
// - Limited vendor stock: npc_vendor rows with maxcount > 0 (and npc_vendor_template's, by
//   creature_template.VendorTemplateId): stock maxcount, restock incrtime seconds; the vendor's name,
//   reactions (who can buy) and first place on a zone map; the price: Forever's ItemSparse BuyPrice for
//   VendorStackCount items, else classic's BuyPrice / BuyCount (basis c). Before reputation discounts.
//
// Run it again when Forever gets new builds (or a newer dump exists):
//   node tools/update-money-data.js                          the latest Forever build, EG Link's newest
//   node tools/update-money-data.js 1.60.1.70888 --cache <dir>  keep the downloads in <dir>
//   node tools/update-money-data.js --dump <dump.sql[.gz]>   a classic dump you have
//   node tools/update-money-data.js --eglink <sha>           EG Link at that commit
//   node tools/update-money-data.js --stats                  only the numbers, nothing written
// The output is the same for the same inputs (everything sorted). The samples at the end (verify) must hold.
const fs = require("fs");
const path = require("path");
const { rows, byEntry } = require("./update-drop-data");
const { table, latestBuild } = require("./wago");
const { worldMaps, places, sampleIndex, raceModel, readDump, eglink } = require("./update-quest-data");

const DUMP_NAME = "CMaNGOS Classic DB, Full_DB z2815 (github.com/cmangos/classic-db, GPL v3)";
const OUT = path.join(__dirname, "..", "LefthyTools_MoneyData", "MoneyData.lua");
const MIN_CHANCE = 0.0005; // 0.05%: rarer loot is left out
const MAX_DEPTH = 6; // references in references
const CLUSTER = 70; // spawns this close (thousandths of the map's width) are one cluster (as update-quest-data.js)
const ASPECT = 1.5; // a zone map's width over its height
const MOB_CLUSTERS = 5; // clusters kept per creature (all maps)
const NODE_CLUSTERS = 12; // clusters kept per node and map
const CRITTER = 8, TOTEM = 11; // CreatureType
const INVISIBLE = 0x80; // creature_template.ExtraFlags
const NOT_SELECTABLE = 0x2000000, NOT_ATTACKABLE = 0x2; // creature_template.UnitFlags
const UNUSED = /trigger|\bDND\b|only GM can see|\[UNUSED\]|\[PH\]|\bUNUSED\b|<TXT>|\bNYI\b|\(OLD\)|\[DEPRECATED\]/i;
const RANKS = { 0: "n", 1: "e", 2: "R", 3: "b", 4: "r" }; // normal, elite, rare elite, boss, rare
const LOCK_HERB = 2, LOCK_ORE = 3, LOCK_PICK = 1, LOCK_TREASURE = 6; // LockType IDs (LockType.csv)
const NO_DISENCHANT = 0x8000; // item flags (ItemSparse.Flags_0, item_template.Flags)
const GO_LOCKED = 0x2, GO_QUEST = 0x4; // gameobject_template.flags (locked; interact condition: quest objects)
const CLASSES = [1, 2, 3, 4, 5, 7, 8, 9, 11]; // classic's classes (a class mask bit is class - 1)
const FRIENDLIEST = { f: 3, n: 2, h: 1 };

const byNumber = (a, b) => a - b;

// ---------------------------------------------------------------- loot

// What a condition means for a loot row: null (left out), "" (kept), or a flag: "e" a game event's, "A" / "H"
// a side's.
function conditionFlag(conds, id) {
  if (!id) return "";
  const c = conds.get(id);
  if (!c) return null;
  if (c.type === 12) return "e"; // CONDITION_ACTIVE_GAME_EVENT
  if (c.type === 6) return c.value1 === 469 ? "A" : c.value1 === 67 ? "H" : null; // CONDITION_TEAM
  if (c.type === 7) return ""; // CONDITION_SKILL: a profession's recipes (kept, they drop for those who have it)
  return null; // quests, auras, items, areas, instances: a script's or a quest's
}

// A loot table's items: Map(item -> { p (0..1), min, max, flag }).
function lootOf(list, refs, conds, depth = 0, out = new Map()) {
  const add = (item, p, min, max, flag) => {
    if (!(p > 0)) return;
    const was = out.get(item);
    if (was) {
      was.p = 1 - (1 - was.p) * (1 - p);
      was.min = Math.min(was.min, min);
      was.max = Math.max(was.max, max);
      if (!was.flag) was.flag = flag;
    } else out.set(item, { p, min, max, flag });
  };
  const groups = new Map();
  for (const r of list || []) {
    const flag = conditionFlag(conds, r.condition_id);
    if (r.mincountOrRef < 0) {
      if (depth >= MAX_DEPTH || r.ChanceOrQuestChance < 0 || flag === null) continue;
      const inner = lootOf(refs.get(-r.mincountOrRef), refs, conds, depth + 1, new Map());
      const c = r.ChanceOrQuestChance / 100, times = Math.max(1, r.maxcount || 1);
      for (const [item, v] of inner) add(item, 1 - Math.pow(1 - c * v.p, times), v.min, v.max * times, v.flag || flag);
    } else if (!r.groupid) {
      if (r.ChanceOrQuestChance < 0 || flag === null) continue;
      const min = Math.max(1, r.mincountOrRef);
      add(r.item, r.ChanceOrQuestChance / 100, min, Math.max(min, r.maxcount || 1), flag);
    } else {
      if (!groups.has(r.groupid)) groups.set(r.groupid, []);
      groups.get(r.groupid).push(r);
    }
  }
  // (a group as update-drop-data.js: the rows with a chance have it, the others share what's left)
  for (const group of groups.values()) {
    const explicit = group.filter((r) => r.ChanceOrQuestChance !== 0);
    const even = group.filter((r) => r.ChanceOrQuestChance === 0);
    const sum = explicit.reduce((s, r) => s + Math.abs(r.ChanceOrQuestChance), 0);
    const each = even.length ? Math.max(0, 100 - sum) / 100 / even.length : 0;
    for (const r of group) {
      const flag = conditionFlag(conds, r.condition_id);
      if (r.ChanceOrQuestChance < 0 || flag === null) continue;
      const min = Math.max(1, r.mincountOrRef);
      add(r.item, r.ChanceOrQuestChance > 0 ? r.ChanceOrQuestChance / 100 : each, min, Math.max(min, r.maxcount || 1), flag);
    }
  }
  return out;
}

// "item:chance[:count[:flag]]" the likeliest first: chance in hundredths of a percent, count "min[-max]".
// known: the items the client knows; dropped counts what it leaves out.
function encodeLoot(map, known, dropped) {
  return [...map.entries()]
    .filter(([id, v]) => {
      if (v.p < MIN_CHANCE) return false;
      if (!known.has(id)) { dropped.add(id); return false; }
      return true;
    })
    .sort((a, b) => b[1].p - a[1].p || a[0] - b[0])
    .map(([id, v]) => {
      const count = v.max > v.min ? `${v.min}-${v.max}` : `${v.min}`;
      const parts = [id, Math.max(1, Math.round(Math.min(1, v.p) * 10000))];
      if (count !== "1" || v.flag) parts.push(count === "1" ? "" : count);
      if (v.flag) parts.push(v.flag);
      return parts.join(":");
    })
    .join(",");
}

// ---------------------------------------------------------------- spawns

// Where each creature or object spawns: Map(entry -> [{ guid, map, x, y, z, p, respawn }]); p: how likely
// it's up at a time (pools, spawn groups, random entries); respawn in seconds.
function spawnModel(sql, kind) {
  const creature = kind === "creature";
  const spawnRows = rows(sql, kind);
  const entries = new Map(); // guid -> [entry]
  for (const r of rows(sql, creature ? "creature_spawn_entry" : "gameobject_spawn_entry")) {
    (entries.get(r.guid) || entries.set(r.guid, []).get(r.guid)).push(r.entry);
  }
  const eventOnly = new Set(rows(sql, `game_event_${kind}`).filter((r) => r.event > 0).map((r) => r.guid));
  // Pools: a member's share of its pool's limit, times its pool's chance of being up in its mother pool.
  const limit = new Map(rows(sql, "pool_template").map((r) => [r.entry, r.max_limit]));
  const members = new Map();
  const guidPool = new Map();
  for (const r of rows(sql, `pool_${kind}`)) { guidPool.set(r.guid, r.pool_entry); members.set(r.pool_entry, (members.get(r.pool_entry) || 0) + 1); }
  const mother = new Map();
  for (const r of rows(sql, "pool_pool")) { mother.set(r.pool_id, r.mother_pool); members.set(r.mother_pool, (members.get(r.mother_pool) || 0) + 1); }
  const share = (pool) => {
    const l = limit.get(pool) || 0, k = members.get(pool) || 1;
    return l > 0 ? Math.min(1, l / k) : 1;
  };
  const active = (pool, depth = 0) => (mother.has(pool) && depth < 8 ? share(mother.get(pool)) * active(mother.get(pool), depth + 1) : 1);
  // Spawn groups (CMaNGOS' newer grouping): MaxCount over its spawns; random entries for id-0 spawns.
  const groups = new Map(rows(sql, "spawn_group").filter((g) => g.Type === (creature ? 0 : 1)).map((g) => [g.Id, g]));
  const guidGroup = new Map(), groupSize = new Map();
  for (const r of rows(sql, "spawn_group_spawn")) {
    if (!groups.has(r.Id)) continue;
    guidGroup.set(r.Guid, r.Id);
    groupSize.set(r.Id, (groupSize.get(r.Id) || 0) + 1);
  }
  const groupEntries = new Map();
  for (const r of rows(sql, "spawn_group_entry")) if (groups.has(r.Id)) (groupEntries.get(r.Id) || groupEntries.set(r.Id, []).get(r.Id)).push(r);
  const stats = { spawns: spawnRows.length, event: 0, unresolved: 0, pooled: 0 };
  const out = new Map();
  for (const r of spawnRows) {
    if (eventOnly.has(r.guid)) { stats.event++; continue; }
    let p = 1;
    if (guidPool.has(r.guid)) { const pool = guidPool.get(r.guid); p *= share(pool) * active(pool); stats.pooled++; }
    const group = guidGroup.get(r.guid);
    if (group !== undefined && groups.get(group).MaxCount > 0) p *= Math.min(1, groups.get(group).MaxCount / groupSize.get(group));
    // (which entry: its own, else one of the listed ones)
    let list;
    if (r.id) list = [[r.id, 1]];
    else if (entries.has(r.guid)) list = entries.get(r.guid).map((e, i, all) => [e, 1 / all.length]);
    else if (group !== undefined && groupEntries.has(group)) {
      const g = groupEntries.get(group);
      const sum = g.reduce((s, e) => s + (e.Chance > 0 ? e.Chance : 0), 0);
      const even = g.filter((e) => !(e.Chance > 0)).length;
      list = g.map((e) => [e.Entry, e.Chance > 0 ? e.Chance / 100 : Math.max(0, 1 - sum / 100) / even]);
    }
    if (!list) { stats.unresolved++; continue; }
    const respawn = Math.round((Math.max(0, r.spawntimesecsmin) + Math.max(r.spawntimesecsmin, r.spawntimesecsmax)) / 2);
    for (const [entry, q] of list) {
      if (!(q > 0)) continue;
      (out.get(entry) || out.set(entry, []).get(entry)).push({ guid: r.guid, map: r.map, x: r.position_x, y: r.position_y, z: r.position_z, p: p * q, respawn });
    }
  }
  return { spawns: out, stats };
}

// Points ([ui, x, y, p], thousandths) in clusters: [{ ui, x, y, r, n, up }], the most points first, at most
// max: update-quest-data.js's clusters() (the same distance, CLUSTER and radius rule) with each point's
// chance of being up summed (up).
function clusterPoints(points, max) {
  const dist = (c, p) => Math.hypot(c.x - p[1], (c.y - p[2]) / ASPECT);
  const out = [];
  for (const p of points.slice().sort((a, b) => a[0] - b[0] || a[1] - b[1] || a[2] - b[2] || a[3] - b[3])) {
    let c = out.find((k) => k.ui === p[0] && dist(k, p) <= CLUSTER);
    if (!c) { c = { ui: p[0], x: p[1], y: p[2], sx: 0, sy: 0, n: 0, up: 0, members: [] }; out.push(c); }
    c.sx += p[1]; c.sy += p[2]; c.n++; c.up += p[3];
    c.x = c.sx / c.n; c.y = c.sy / c.n;
    c.members.push(p);
  }
  for (const c of out) {
    c.x = Math.round(c.x); c.y = Math.round(c.y);
    c.r = Math.max(15, Math.min(150, Math.round(Math.max(0, ...c.members.map((p) => dist(c, p))) + 10)));
  }
  return out.sort((a, b) => b.n - a.n || a.ui - b.ui || a.x - b.x || a.y - b.y).slice(0, max)
    .map((c) => ({ ui: c.ui, x: c.x, y: c.y, r: c.r, n: c.n, up: c.up }));
}

// "x,y,r,n[,up]": up with one decimal, left out when it's n.
function encodeCluster(c, withMap) {
  const up = Math.round(c.up * 10) / 10;
  const parts = withMap ? [c.ui, c.x, c.y, c.r, c.n] : [c.x, c.y, c.r, c.n];
  if (up !== c.n) parts.push(up < 0.1 ? 0.1 : up);
  return parts.join(",");
}

function median(list) {
  if (!list.length) return 0;
  const s = list.slice().sort(byNumber);
  return s[Math.floor((s.length - 1) / 2)];
}

// ---------------------------------------------------------------- reactions

// How a creature's faction template reacts to a character of each side: react(template) -> { A, H, rep }
// ("h" hostile, "n" neutral, "f" friendly, undefined: unknown template; rep: the faction's ID when it has
// reputation). Also the mixed cases (races or classes of a side that differ) it settled on the friendliest.
function reactionModel(t, races) {
  const templates = new Map(t.FactionTemplate.map((r) => [+r.ID, r]));
  const factions = new Map(t.Faction.map((r) => [+r.ID, r]));
  const chr = new Map(t.ChrRaces.map((r) => [+r.ID, r]));
  const players = { Alliance: [], Horde: [] };
  for (const r of races.list) {
    const tmpl = templates.get(+chr.get(r.id).FactionID);
    if (!tmpl) throw new Error(`no faction template ${chr.get(r.id).FactionID} for the race ${r.name}`);
    players[r.faction].push({ race: r, tmpl });
  }
  const list = (row, name) => [0, 1, 2, 3, 4, 5, 6, 7].map((i) => +row[`${name}_${i}`] || 0).filter(Boolean);
  // CMaNGOS' GetFactionReaction(thisTemplate, otherTemplate), Relations.cpp (the client's own order).
  const byTemplates = (a, b) => {
    if (+b.FactionGroup & +a.EnemyGroup) return "h";
    if (+b.Faction && list(a, "Enemies").includes(+b.Faction)) return "h";
    if (+b.FactionGroup & +a.FriendGroup) return "f";
    if (+b.Faction && list(a, "Friend").includes(+b.Faction)) return "f";
    if (+a.FactionGroup & +b.FriendGroup) return "f";
    if (+a.Faction && list(b, "Friend").includes(+a.Faction)) return "f";
    return "n";
  };
  const hasBit = (lo, hi, bit) => (bit < 32 ? ((lo >>> 0) >>> bit) & 1 : ((hi >>> 0) >>> (bit - 32)) & 1) === 1;
  // A new character's standing (ReputationMgr's base reputation).
  const base = (f, bit, cls) => {
    for (let i = 0; i < 4; i++) {
      const lo = +f[`ReputationRaceMasks${i}_0`] || 0, hi = +f[`ReputationRaceMasks${i}_1`] || 0;
      const classMask = (+f[`ReputationClassMask_${i}`] || 0) >>> 0;
      if (!hasBit(lo, hi, bit)) continue;
      if (classMask && !((classMask >>> (cls - 1)) & 1)) continue;
      return +f[`ReputationBase_${i}`] || 0;
    }
    return 0;
  };
  const rank = (v) => (v <= -3001 ? "h" : v <= 2999 ? "n" : "f");
  const mixed = new Set();
  const cache = new Map();
  const react = (id) => {
    if (cache.has(id)) return cache.get(id);
    const tmpl = templates.get(id);
    let res;
    if (tmpl) {
      const f = factions.get(+tmpl.Faction);
      const rep = f && +f.ReputationIndex >= 0 ? +tmpl.Faction : undefined;
      res = { rep };
      for (const side of ["Alliance", "Horde"]) {
        const seen = new Set();
        for (const p of players[side]) {
          if (rep) for (const cls of CLASSES) seen.add(rank(base(f, p.race.bit, cls)));
          else seen.add(byTemplates(tmpl, p.tmpl));
        }
        const pick = [...seen].sort((a, b) => FRIENDLIEST[b] - FRIENDLIEST[a])[0];
        if (seen.size > 1) mixed.add(`${id} (${side}: ${[...seen].join("/")})`);
        res[side === "Alliance" ? "A" : "H"] = pick;
      }
    }
    cache.set(id, res);
    return res;
  };
  return { react, mixed };
}

// ---------------------------------------------------------------- main

function parseArgs(args) {
  const o = { stats: false };
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === "--cache") o.cache = args[++i];
    else if (a === "--dump") o.dump = args[++i];
    else if (a === "--eglink") o.eglink = args[++i];
    else if (a === "--stats") o.stats = true;
    else o.build = a;
  }
  return o;
}

async function main() {
  const o = parseArgs(process.argv.slice(2));
  if (o.cache) fs.mkdirSync(o.cache, { recursive: true });
  const build = o.build || (await latestBuild());
  if (!build) throw new Error("could not determine the Forever build; pass it as an argument");
  console.log(`WoW: Forever ${build}`);
  const names = ["UiMap", "UiMapAssignment", "AreaTable", "Map", "WorldMapOverlay", "UiMapXMapArt", "FactionTemplate", "Faction",
    "ChrRaces", "Lock", "ItemSparse", "Item", "ItemDisenchantLoot"];
  const t = {};
  for (const name of names) t[name] = await table(name, build, o.cache);
  const eg = await eglink(build, o.eglink, o.cache);
  console.log(`EG Link ${eg.ref.slice(0, 7)} (${eg.build})`);
  const sql = await readDump(o.dump, o.cache);

  // --- the world's maps and where players' games put positions (as update-quest-data.js)
  const world = worldMaps(t);
  world.samples = sampleIndex([
    ...["npcs", "objects", "approached"].flatMap((k) => Object.values(eg.npcs[k] || {}).map((r) => r.positions)),
    ...Object.values(eg.creatures).map((r) => r.positions),
    ...Object.values(eg.loot).map((r) => r.positions),
  ]);
  const egMaps = new Map(); // "n123" / "o123" -> Set(zone uiMaps EG Link recorded it on)
  const egSaw = (key, list) => {
    for (const p of list || []) {
      const u = world.ui.get(p.uiMap);
      if (u && u.type === 3) (egMaps.get(key) || egMaps.set(key, new Set()).get(key)).add(p.uiMap);
    }
  };
  for (const [id, r] of Object.entries(eg.npcs.npcs || {})) egSaw("n" + id, r.positions);
  for (const [id, r] of Object.entries(eg.npcs.objects || {})) egSaw("o" + id, r.positions);
  for (const [id, r] of Object.entries(eg.creatures)) egSaw("n" + id, r.positions);
  for (const [k, r] of Object.entries(eg.loot)) {
    const m = k.match(/^(npc|object):(\d+)/);
    if (m) egSaw((m[1] === "npc" ? "n" : "o") + m[2], r.positions);
  }
  // A spawn's zone map point [ui, x, y] (thousandths), or undefined (no zone map there).
  const zonePoint = (key, s) => {
    const p = places(world, s.map, s.x, s.y, s.z, undefined, egMaps.get(key));
    return p.length && world.ui.get(p[0][0]).type === 3 ? p[0] : undefined;
  };
  const instanceType = (m) => (world.instance.get(m) ? world.instance.get(m).type : 0);
  const races = raceModel(t.ChrRaces);
  const { react, mixed } = reactionModel(t, races);
  const known = new Set(t.Item.map((r) => +r.ID)); // the items Forever's client knows (Item: all of them; ItemSparse lacks many)
  const dropped = new Set(); // loot items left out as the client doesn't know them

  // --- classic-db
  const creatureT = new Map(rows(sql, "creature_template").map((c) => [c.Entry, c]));
  const objectT = new Map(rows(sql, "gameobject_template").map((g) => [g.entry, g]));
  const items = new Map(rows(sql, "item_template").map((i) => [i.entry, i]));
  const conds = new Map(rows(sql, "conditions").map((c) => [c.condition_entry, c]));
  const refs = byEntry(rows(sql, "reference_loot_template"));
  const cs = spawnModel(sql, "creature"), gs = spawnModel(sql, "gameobject");
  console.log(`creature spawns: ${cs.stats.spawns} (${cs.stats.event} only at events, ${cs.stats.pooled} pooled, ${cs.stats.unresolved} without an entry); `
    + `object spawns: ${gs.stats.spawns} (${gs.stats.event} only at events, ${gs.stats.pooled} pooled, ${gs.stats.unresolved} without an entry)`);
  for (const c of creatureT.values()) {
    if (c.CreatureTypeFlags & 0x300) throw new Error(`creature ${c.Entry} ${c.Name} has herb or ore loot (CreatureTypeFlags ${c.CreatureTypeFlags}): add it to skin`);
  }

  // --- creatures
  const mobs = new Map(); // id -> { line parts, spots }
  const zoneMobs = new Map(); // uiMap -> Set(creature)
  let seenSame = 0;
  const seenDiffer = [];
  const why = { kind: 0, nothing: 0, spawns: 0, friendly: 0, rep: 0, unknownReaction: 0, battleground: 0 };
  for (const c of [...creatureT.values()].sort((a, b) => a.Entry - b.Entry)) {
    if (c.CreatureType === CRITTER || c.CreatureType === TOTEM || (c.ExtraFlags & INVISIBLE) || (c.UnitFlags & (NOT_SELECTABLE | NOT_ATTACKABLE))
      || UNUSED.test(c.Name) || c.MaxLevelHealth <= 1) { why.kind++; continue; }
    if (!(c.LootId || c.MaxLootGold > 0 || c.SkinningLootId || c.PickpocketLootId)) { why.nothing++; continue; }
    const all = cs.spawns.get(c.Entry) || [];
    const outdoor = all.filter((s) => instanceType(s.map) === 0), inside = all.filter((s) => instanceType(s.map) === 1 || instanceType(s.map) === 2);
    if (!outdoor.length && !inside.length) { if (all.length) why.battleground++; else why.spawns++; continue; }
    // (worked out from the faction template; for a faction without reputation, what players saw on Forever
    // where they saw one kind for a side: EG Link's reactions, 1-2 hostile, 3-4 neutral, 5-8 friendly)
    const worked = react(c.Faction);
    const r = worked && { ...worked };
    const seenBy = [];
    const e = eg.creatures[c.Entry];
    if (r && !r.rep && e && e.reactions) {
      for (const [side, k] of [["Alliance", "A"], ["Horde", "H"]]) {
        const seen = new Set((e.reactions[side] || []).map((v) => (v <= 2 ? "h" : v <= 4 ? "n" : "f")));
        if (seen.size !== 1) continue;
        const v = [...seen][0];
        if (v === r[k]) seenSame++;
        else { seenDiffer.push(`${c.Entry} ${c.Name} ${side}: ${r[k]}, seen ${v}`); r[k] = v; seenBy.push(k); }
      }
    }
    if (!r) why.unknownReaction++;
    else if (r.A === "f" && r.H === "f") { why.friendly++; continue; }
    else if (r.rep && r.A !== "h" && r.H !== "h") { why.rep++; continue; }
    const points = [];
    for (const s of outdoor) {
      const p = zonePoint("n" + c.Entry, s);
      if (p) points.push([p[0], p[1], p[2], s.p]);
    }
    const spots = clusterPoints(points, MOB_CLUSTERS);
    const flags = (outdoor.length ? "" : "i") + (c.Civilian ? "c" : "") + seenBy.join("");
    mobs.set(c.Entry, {
      c, spots,
      line: [c.Name.replace(/[|;]/g, " ").trim(), RANKS[c.Rank] || "n", c.CreatureType || "", c.SkinningLootId ? "l" : "",
        r ? r.A : "", r ? r.H : "", median([...outdoor, ...inside].map((s) => s.respawn)), flags, r && r.rep ? r.rep : "",
        spots.map((k) => encodeCluster(k, true)).join(";")],
    });
    for (const k of points) (zoneMobs.get(k[0]) || zoneMobs.set(k[0], new Set()).get(k[0])).add(c.Entry);
  }
  console.log(`creatures: ${mobs.size} (${[...mobs.values()].filter((m) => m.spots.length).length} with places on zone maps, `
    + `${[...mobs.values()].filter((m) => !m.spots.length && m.line[7].includes("i")).length} only in dungeons and raids); left out: `
    + `${why.kind} critters, totems, triggers, unattackable or unused, ${why.nothing} with nothing to loot, ${why.spawns} never spawned outside events, `
    + `${why.battleground} only in battlegrounds, ${why.friendly} friendly to both sides, ${why.rep} of a reputation neither side starts hostile with; `
    + `${why.unknownReaction} with a faction template the client lacks (no reactions)`);
  console.log(`reactions mixed within a side (the friendliest taken): ${mixed.size}${mixed.size ? ": " + [...mixed].slice(0, 20).join("; ") : ""}`);
  console.log(`reactions players saw on Forever (EG Link, factions without reputation, one kind seen for a side): ${seenSame} as worked out, `
    + `${seenDiffer.length} taken instead${seenDiffer.length ? ": " + seenDiffer.join("; ") : ""}`);

  // --- gathering nodes
  const locks = new Map(t.Lock.map((r) => [+r.ID, r]));
  const lockEntries = (id) => {
    const l = locks.get(id), out = new Map();
    if (!l) return out;
    for (let i = 0; i < 8; i++) if (+l[`Type_${i}`] === 2 && !out.has(+l[`_Index_${i}`])) out.set(+l[`_Index_${i}`], +l[`Skill_${i}`] || 0);
    return out;
  };
  const goLoot = byEntry(rows(sql, "gameobject_loot_template"));
  const objects = new Map(); // id -> { line }
  const nodes = new Map(); // uiMap -> [{ id, n, up, clusters }]
  const kinds = {};
  for (const g of [...objectT.values()].sort((a, b) => a.entry - b.entry)) {
    let kind, skill = 0, uses;
    if (g.type === 3) {
      const e = lockEntries(g.data0);
      if (e.has(LOCK_HERB)) { kind = "herb"; skill = e.get(LOCK_HERB); } else if (e.has(LOCK_ORE)) { kind = "ore"; skill = e.get(LOCK_ORE); } else if (e.has(LOCK_TREASURE) && !(g.flags & GO_QUEST)) {
        kind = "chest";
        skill = (g.flags & GO_LOCKED) && e.has(LOCK_PICK) ? e.get(LOCK_PICK) : 0;
      }
      uses = [Math.max(1, g.data4), Math.max(1, g.data4, g.data5)];
    } else if (g.type === 25) {
      kind = "fish";
      uses = [Math.max(1, g.data2), Math.max(1, g.data2, g.data3)];
    }
    if (!kind || !g.data1) continue;
    const loot = encodeLoot(lootOf(goLoot.get(g.data1), refs, conds), known, dropped);
    if (!loot) continue;
    const perMap = new Map();
    const all = gs.spawns.get(g.entry) || [];
    for (const s of all) {
      if (instanceType(s.map) !== 0) continue;
      const p = zonePoint("o" + g.entry, s);
      if (p) (perMap.get(p[0]) || perMap.set(p[0], []).get(p[0])).push([p[0], p[1], p[2], s.p]);
    }
    if (!perMap.size) continue;
    kinds[kind] = (kinds[kind] || 0) + 1;
    objects.set(g.entry, {
      kind, skill, loot,
      line: [g.name.replace(/[|;]/g, " ").trim(), kind, skill, median(all.map((s) => s.respawn)), uses[1] > uses[0] ? uses.join("-") : uses[0], loot],
    });
    for (const [ui, points] of perMap) {
      (nodes.get(ui) || nodes.set(ui, []).get(ui)).push({ id: g.entry, n: points.length, up: points.reduce((s, p) => s + p[3], 0), clusters: clusterPoints(points, NODE_CLUSTERS) });
    }
  }
  console.log(`nodes: ${objects.size} kinds of object (${Object.entries(kinds).map(([k, n]) => `${n} ${k}`).join(", ")}) on ${nodes.size} zone maps`);

  // --- fishing
  const baseSkill = new Map(rows(sql, "skill_fishing_base_level").map((r) => [r.entry, r.skill]));
  const fishLoot = byEntry(rows(sql, "fishing_loot_template"));
  const fishText = new Map(); // area -> loot text
  const fishOf = (area) => {
    if (!fishText.has(area)) fishText.set(area, fishLoot.has(area) ? encodeLoot(lootOf(fishLoot.get(area), refs, conds), known, dropped) : "");
    return fishText.get(area);
  };
  const zoneAreas = new Map(); // uiMap -> zone area (a top-level area, its name the map's when there are several)
  for (const a of [...world.areas.values()].sort((x, y) => x.id - y.id)) {
    if (a.parent) continue;
    const ui = world.uiOfArea(a.id);
    if (!ui || world.ui.get(ui).type !== 3) continue;
    const had = zoneAreas.get(ui);
    if (!had || (a.name === world.ui.get(ui).name && world.areas.get(had).name !== world.ui.get(ui).name)) zoneAreas.set(ui, a.id);
  }
  const fishing = new Map(), fishingAreas = new Map();
  const noBase = [];
  for (const [ui, zone] of [...zoneAreas].sort((a, b) => a[0] - b[0])) {
    const loot = fishOf(zone);
    if (!baseSkill.has(zone)) { if (loot) noBase.push(`${world.ui.get(ui).name} (${zone})`); continue; }
    if (!loot) continue;
    fishing.set(ui, `${baseSkill.get(zone)}|${loot}`);
  }
  // Subzones with their own base or loot (any depth below a zone area with fishing).
  const zoneOfArea = (id) => {
    for (let a = world.areas.get(id), n = 0; a && n < 12; a = world.areas.get(a.parent), n++) if (!a.parent) return a.id;
    return undefined;
  };
  const mapOfZone = new Map([...zoneAreas].map(([ui, z]) => [z, ui]));
  for (const area of [...new Set([...baseSkill.keys(), ...fishLoot.keys()])].sort(byNumber)) {
    const a = world.areas.get(area);
    if (!a || !a.parent) continue;
    const zone = zoneOfArea(area), ui = mapOfZone.get(zone);
    if (!ui || !fishing.has(ui)) continue;
    // (the core: the subzone's base, else the zone's; its loot, else the zone's; a subzone's own subzones
    // don't inherit from it)
    const base = baseSkill.has(area) ? baseSkill.get(area) : baseSkill.get(zone);
    const loot = fishOf(area) || fishOf(zone);
    if (base === baseSkill.get(zone) && loot === fishOf(zone)) continue;
    if (!loot) continue;
    fishingAreas.set(area, `${ui}|${a.name.replace(/\|/g, " ")}|${base}|${loot}`);
  }
  console.log(`fishing: ${fishing.size} zone maps, ${fishingAreas.size} subzones of their own; zones with fishing loot but no base skill (left out): ${noBase.join(", ") || "none"}`);

  // --- pickpocketing
  const pickLoot = byEntry(rows(sql, "pickpocketing_loot_template"));
  const pickpocket = new Map();
  for (const [id, m] of mobs) {
    if (!m.c.PickpocketLootId) continue;
    const loot = encodeLoot(lootOf(pickLoot.get(m.c.PickpocketLootId), refs, conds), known, dropped);
    if (loot) pickpocket.set(id, loot);
  }
  console.log(`pickpocketing: ${pickpocket.size} creatures`);

  // --- disenchanting. Which items and the skill: the client's ItemDisenchantLoot rows (class, quality, item level).
  // The results: classic-db's group (DisenchantID, numbered otherwise than the client's rows; classic puts shields
  // and off-hand items with the weapons, the client's rows only know classes), for an item classic-db has none
  // for the group most classic items of its client row and inventory type use (else of its row; when 90% or more
  // of them use it).
  const deLoot = byEntry(rows(sql, "disenchant_loot_template"));
  const itemClass = new Map(t.Item.map((r) => [+r.ID, +r.ClassID]));
  const sparse = new Map(t.ItemSparse.map((r) => [+r.ID, r]));
  const deRow = (cls, q, lvl) => t.ItemDisenchantLoot.find((r) => +r.Class === cls && +r.Subclass === -1 && +r.Quality === q && lvl >= +r.MinLevel && lvl <= +r.MaxLevel);
  // (by the client row and the item's inventory type, else the row alone: "row" or "row:type")
  const rowGroups = new Map(); // key -> Map(classic DisenchantID -> items)
  for (const it of items.values()) {
    const row = it.DisenchantID && deRow(it.class, it.Quality, it.ItemLevel);
    if (!row) continue;
    for (const key of [`${row.ID}`, `${row.ID}:${it.InventoryType}`]) {
      const m = rowGroups.get(key) || rowGroups.set(key, new Map()).get(key);
      m.set(it.DisenchantID, (m.get(it.DisenchantID) || 0) + 1);
    }
  }
  const rowGroup = new Map(); // key -> its classic group (90% of its classic items)
  for (const [key, m] of rowGroups) {
    const list = [...m].sort((a, b) => b[1] - a[1] || a[0] - b[0]);
    if (list[0][1] >= 0.9 * list.reduce((n, x) => n + x[1], 0)) rowGroup.set(key, list[0][0]);
  }
  const groupLoot = new Map(); // classic group -> loot text
  const lootOfGroup = (g) => {
    if (!groupLoot.has(g)) groupLoot.set(g, encodeLoot(lootOf(deLoot.get(g), refs, conds), known, dropped));
    return groupLoot.get(g);
  };
  // Which items: those the client has (ItemSparse) by its class, quality, level and "can't be disenchanted" flag
  // (Flags_0 0x8000, also classic's); the others (not in ItemSparse) by classic-db's DisenchantID and classic's
  // class, quality and level.
  const disenchant = new Map();
  const deStats = { forever: 0, classic: 0, foreverOnly: [], classicOnly: [], noGroup: new Map() };
  for (const id of [...known].sort(byNumber)) {
    const s = sparse.get(id), it = items.get(id);
    let row;
    if (s) {
      if (!(+s.Flags_0 & NO_DISENCHANT)) row = deRow(itemClass.get(id), +s.OverallQualityID, +s.ItemLevel);
      if (row && it && !it.DisenchantID) deStats.foreverOnly.push(`${id} ${it.name}`);
      if (!row && it && it.DisenchantID) deStats.classicOnly.push(`${id} ${it.name}`);
    } else if (it && it.DisenchantID && !(it.Flags & NO_DISENCHANT)) row = deRow(it.class, it.Quality, it.ItemLevel);
    if (!row) continue;
    const group = (it && it.DisenchantID) || (it && rowGroup.get(`${row.ID}:${it.InventoryType}`)) || rowGroup.get(`${row.ID}`);
    if (!group || !lootOfGroup(group)) { deStats.noGroup.set(+row.ID, (deStats.noGroup.get(+row.ID) || 0) + 1); continue; }
    const skill = Math.max(1, +row.SkillRequired || 0);
    disenchant.set(id, skill > 1 ? `${group}:${skill}` : group);
    deStats[s ? "forever" : "classic"]++;
  }
  const disenchantLoot = new Map([...new Set([...disenchant.values()].map((v) => +String(v).split(":")[0]))].map((g) => [g, lootOfGroup(g)]));
  console.log(`disenchanting: ${disenchant.size} items (${deStats.forever} by the client's data, ${deStats.classic} by classic-db's), ${disenchantLoot.size} result groups; `
    + `disenchantable by the client's data but not classic-db's: ${deStats.foreverOnly.length} (e.g. ${deStats.foreverOnly.slice(0, 8).join("; ")}); `
    + `the other way round (left out): ${deStats.classicOnly.length} (${deStats.classicOnly.join("; ")}); without results (client row: items): `
    + `${[...deStats.noGroup].map((x) => x.join(": ")).join(", ") || "none"}; client skill: ${[...new Set(t.ItemDisenchantLoot.map((r) => r.SkillRequired))].join(",")}`);

  // --- limited vendor stock
  const vendorRows = rows(sql, "npc_vendor").filter((r) => r.maxcount > 0);
  const templateRows = byEntry(rows(sql, "npc_vendor_template").filter((r) => r.maxcount > 0));
  const sells = new Map(); // "npc:item" -> row
  for (const r of vendorRows) sells.set(`${r.entry}:${r.item}`, { npc: r.entry, item: r.item, stock: r.maxcount, restock: r.incrtime });
  for (const c of creatureT.values()) {
    for (const r of (c.VendorTemplateId && templateRows.get(c.VendorTemplateId)) || []) {
      if (!sells.has(`${c.Entry}:${r.item}`)) sells.set(`${c.Entry}:${r.item}`, { npc: c.Entry, item: r.item, stock: r.maxcount, restock: r.incrtime });
    }
  }
  const limited = new Map(), vendors = new Map();
  const noPlace = new Set();
  for (const s of [...sells.values()].sort((a, b) => a.item - b.item || a.npc - b.npc)) {
    const c = creatureT.get(s.npc);
    if (!c || !known.has(s.item)) continue;
    const spawns = (cs.spawns.get(s.npc) || []).slice().sort((a, b) => a.guid - b.guid);
    if (!spawns.length) continue; // (stands nowhere outside events)
    if (!vendors.has(s.npc)) {
      let at;
      for (const sp of spawns) { if (instanceType(sp.map) === 0 && (at = zonePoint("n" + s.npc, sp))) break; }
      if (!at) noPlace.add(s.npc);
      const r = react(c.Faction) || {};
      vendors.set(s.npc, `${c.Name.replace(/[|;]/g, " ").trim()}|${r.A || ""}|${r.H || ""}|${at ? at.join(",") : ""}`);
    }
    if (!limited.has(s.item)) {
      const f = sparse.get(s.item), it = items.get(s.item);
      const price = f && +f.BuyPrice > 0 ? [+f.BuyPrice, Math.max(1, +f.VendorStackCount || 1), "f"] : it ? [it.BuyPrice, Math.max(1, it.BuyCount || 1), "c"] : undefined;
      if (!price) continue;
      limited.set(s.item, { head: price.join("|"), list: [] });
    }
    limited.get(s.item).list.push(`${s.npc}:${s.stock}:${s.restock}`);
  }
  console.log(`limited vendor stock: ${limited.size} items at ${vendors.size} vendors (${noPlace.size} without a place on a zone map)`);
  console.log(`loot items left out as Forever's client doesn't know them: ${dropped.size}${dropped.size ? " (" + [...dropped].sort(byNumber).slice(0, 20).join(",") + ")" : ""}`);

  // --- encoding
  const esc = (s) => String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\r?\n/g, " ");
  const trim = (f) => { const a = f.map(String); while (a.length && a[a.length - 1] === "") a.pop(); return a.join("|"); };
  const source = `${DUMP_NAME}; WoW: Forever ${build} client tables (wago.tools); EG Link ${eg.ref.slice(0, 7)} for ${eg.build} (Efficient Games, CC BY 4.0) for zone borders`;
  const sortedKeys = (m) => [...m.keys()].sort(byNumber);
  const lua = [
    `-- Generated by tools/update-money-data.js: don't edit, run the tool again. Sources: ${source}.`,
    "-- README.md has every field's source and rule. x, y, r in 1/1000 of the zone map (r of its width); chances in",
    "-- hundredths of a percent; loot \"item:chance[:count[:flag]]\" (count \"min[-max]\", flag e: only during a game event,",
    "-- A / H: only for that side), the likeliest first; clusters \"x,y,r,n[,up]\" (n spawn points, up how many are up at",
    "-- once, an estimate; left out when it's n), the most spawns first.",
    "-- mobs[creature] = \"name|rank|type|skin|reactA|reactH|respawn|flags|rep|spots\": rank n normal, e elite, r rare,",
    "-- R rare elite, b boss; type creature_template.CreatureType; skin l (Skinning); react h hostile, n neutral,",
    "-- f friendly (a new character of that side); respawn seconds; flags i only in dungeons and raids, c civilian; rep the",
    "-- faction's ID when its reaction is by reputation; spots \"map,x,y,r,n[,up];...\". zones[uiMap] = creatures there.",
    "-- objects[object] = \"name|kind|skill|respawn|uses|loot\": kind herb, ore, chest, fish (a school); skill the",
    "-- Herbalism, Mining or (locked chests) Lockpicking needed; uses \"min[-max]\" times it can be looted.",
    "-- nodes[uiMap] = \"object:n:up=cluster;cluster|object:...\". fishing[uiMap] = \"base|loot\" (catches need skill",
    "-- >= base, sure from base + 95); fishingAreas[area] = \"uiMap|name|base|loot\": subzones that differ.",
    "-- pickpocket[creature] = loot. disenchant[item] = group (\"group:skill\" when Enchanting above 1 is needed);",
    "-- disenchantLoot[group] = loot.",
    "-- limited[item] = \"price|count|basis|npc:stock:restock;...\" (price in copper for count items, basis f Forever's",
    "-- client, c classic; restock seconds); vendors[npc] = \"name|reactA|reactH|map,x,y\".",
    "-- GPL v3 (LICENSE.md); sources and World of Warcraft's copyright: COPYRIGHT.md.",
    "LefthyToolsMoneyData = {",
    `\tsource = "${esc(source)}",`,
    `\tbuild = "${build}",`,
    "\tmobs = {",
    ...sortedKeys(mobs).map((id) => `\t\t[${id}] = "${esc(trim(mobs.get(id).line))}",`),
    "\t},",
    "\tzones = {",
    ...sortedKeys(zoneMobs).map((ui) => `\t\t[${ui}] = "${[...zoneMobs.get(ui)].sort(byNumber).join(",")}",`),
    "\t},",
    "\tobjects = {",
    ...sortedKeys(objects).map((id) => `\t\t[${id}] = "${esc(trim(objects.get(id).line))}",`),
    "\t},",
    "\tnodes = {",
    ...sortedKeys(nodes).map((ui) => `\t\t[${ui}] = "${nodes.get(ui).sort((a, b) => a.id - b.id)
      .map((nd) => `${nd.id}:${nd.n}:${Math.max(0.1, Math.round(nd.up * 10) / 10)}=${nd.clusters.map((c) => encodeCluster(c, false)).join(";")}`).join("|")}",`),
    "\t},",
    "\tfishing = {",
    ...sortedKeys(fishing).map((ui) => `\t\t[${ui}] = "${fishing.get(ui)}",`),
    "\t},",
    "\tfishingAreas = {",
    ...sortedKeys(fishingAreas).map((a) => `\t\t[${a}] = "${esc(fishingAreas.get(a))}",`),
    "\t},",
    "\tpickpocket = {",
    ...sortedKeys(pickpocket).map((id) => `\t\t[${id}] = "${pickpocket.get(id)}",`),
    "\t},",
    "\tdisenchant = {",
    ...sortedKeys(disenchant).map((id) => `\t\t[${id}] = ${disenchant.get(id)},`),
    "\t},",
    "\tdisenchantLoot = {",
    ...sortedKeys(disenchantLoot).map((id) => `\t\t[${id}] = "${disenchantLoot.get(id)}",`),
    "\t},",
    "\tlimited = {",
    ...sortedKeys(limited).map((id) => `\t\t[${id}] = "${limited.get(id).head}|${limited.get(id).list.join(";")}",`),
    "\t},",
    "\tvendors = {",
    ...sortedKeys(vendors).map((id) => `\t\t[${id}] = "${esc(vendors.get(id))}",`),
    "\t},",
    "}",
    "",
  ].join("\n");
  verify(lua, new Map([...items.values()].map((i) => [i.entry, i.name])));
  console.log(`samples verified; ${(Buffer.byteLength(lua) / 1024 / 1024).toFixed(2)} MB`);
  if (o.stats) return;
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, lua, "utf8");
  console.log(`written: ${path.relative(process.cwd(), OUT)}`);
}

// ---------------------------------------------------------------- samples

// Facts checked on the output (known from the game and its client; a failure stops the tool before it writes).
// Reads the generated text back the way the add-on is read: one table's entry at a time.
function verify(lua, itemNames) {
  const entry = (tableName, id) => {
    const block = lua.match(new RegExp(`\\n\\t${tableName} = \\{\\n([\\s\\S]*?)\\n\\t\\},`));
    if (!block) throw new Error(`verify: no table ${tableName}`);
    const m = block[1].match(new RegExp(`\\t\\t\\[${id}\\] = "?([^\\n]*?)"?,(?:\\n|$)`));
    return m ? m[1] : undefined;
  };
  const fail = (what) => { throw new Error(`verify: ${what}`); };
  const lootHas = (loot, item, atLeast) => (loot || "").split(",").some((e) => { const [i, c] = e.split(":"); return +i === item && +c >= atLeast; });
  // Gathering skills (Forever's Lock table) and the herb or ore each node gives.
  for (const [id, name, kind, skill, item] of [
    [1618, "Peacebloom", "herb", 1, 2447], [1617, "Silverleaf", "herb", 1, 765], [1620, "Mageroyal", "herb", 50, 785],
    [1621, "Briarthorn", "herb", 70, 2450], [1731, "Copper Vein", "ore", 1, 2770], [1732, "Tin Vein", "ore", 65, 2771],
    [1733, "Silver Vein", "ore", 75, 2775], [1735, "Iron Deposit", "ore", 125, 2772], [2040, "Mithril Deposit", "ore", 175, 3858],
  ]) {
    const f = (entry("objects", id) || "").split("|");
    if (f[0] !== name || f[1] !== kind || +f[2] !== skill) fail(`${name} (${id}) should be ${kind} at skill ${skill}: ${f.slice(0, 3).join("|")}`);
    if (!lootHas(f[5], item, 9000)) fail(`${name} should give item ${item} nearly always: ${f[5]}`);
  }
  if (!/(^|\|)1731:/.test(entry("nodes", 1429) || "") || !/(^|\|)1618:/.test(entry("nodes", 1429) || "")) fail("Elwynn Forest (1429) should have Copper Veins and Peacebloom");
  // Reactions: city guards are friendly to their own side and hostile to the other; wild animals neutral or hostile to both.
  const mob = (id) => (entry("mobs", id) || "").split("|");
  for (const [id, name, a, h] of [[68, "Stormwind City Guard", "f", "h"], [3296, "Orgrimmar Grunt", "h", "f"], [5595, "Ironforge Guard", "f", "h"],
    [5624, "Undercity Guardian", "h", "f"], [116, "Defias Bandit", "h", "h"]]) {
    const m = mob(id);
    if (m[0] !== name || m[4] !== a || m[5] !== h) fail(`${name} (${id}) should react ${a}/${h}: ${m.slice(0, 6).join("|")}`);
  }
  if (entry("mobs", 4624)) fail("Booty Bay Bruiser (4624) is neutral to both sides by reputation: not a mob to farm");
  if (mob(299)[0] !== "Young Wolf" || !mob(299)[9] || !mob(299)[9].startsWith("1429,")) fail(`Young Wolf (299) should spawn in Elwynn Forest: ${mob(299).join("|")}`);
  if (mob(113)[0] !== "Stonetusk Boar" || mob(113)[3] !== "l" || !(mob(113)[9] || "").startsWith("1429,")) fail(`Stonetusk Boar (113): skinnable, in Elwynn Forest: ${mob(113).join("|")}`);
  // Fishing: Elwynn's base -70 (sure from 25), Stranglethorn's 130 (sure from 225); Elwynn's fish.
  const elwynn = (entry("fishing", 1429) || "").split("|"), stv = (entry("fishing", 1434) || "").split("|");
  if (+elwynn[0] !== -70 || !lootHas(elwynn[1], 6291, 1000) || !lootHas(elwynn[1], 6289, 1000)) fail(`Elwynn Forest's fishing: ${elwynn.join("|")}`);
  if (+stv[0] !== 130) fail(`Stranglethorn Vale's fishing base should be 130: ${stv[0]}`);
  // Pickpocketing: a Defias Pathstalker's pockets (classic's junk and coin purses) are there.
  if (!entry("pickpocket", 116)) fail("Defias Bandit (116) should have pickpocketing loot");
  // Disenchanting: low-level green armour gives Strange Dust mostly, a green weapon Lesser Magic Essence mostly.
  const de = (item) => entry("disenchantLoot", entry("disenchant", item));
  if (!lootHas(de(2303), 10940, 6000)) fail(`Handstitched Leather Pants (2303, green on Forever) should give Strange Dust mostly: ${de(2303)}`);
  if (!lootHas(de(1077), 11083, 6000)) fail(`Defias Mage Ring (1077, green armour ilvl 26) should give Soul Dust mostly: ${de(1077)}`);
  // (a green weapon: an essence mostly, dust the rest)
  const sword = (de(864) || "").split(",").map((e) => e.split(":").map(Number));
  if (!(sword.length >= 2 && sword[0][1] >= 6000 && /Essence/.test(itemNames.get(sword[0][0]) || ""))) fail(`Knightly Longsword (864, green weapon ilvl 38) should give an essence mostly: ${de(864)}`);
  // Limited stock: Tharynn Bouden's Pattern: Blue Linen Vest (one, back after 2.5 hours).
  if (!/(^|;)66:1:9000(;|$)/.test(((entry("limited", 6270) || "").split("|"))[3] || "")) fail(`Pattern: Blue Linen Vest (6270) at Tharynn Bouden (66): ${entry("limited", 6270)}`);
  if (!(entry("vendors", 66) || "").startsWith("Tharynn Bouden|f|h|1429,")) fail(`Tharynn Bouden (66): ${entry("vendors", 66)}`);
}

if (require.main === module) main().catch((e) => { console.error(e); process.exit(1); });
module.exports = { lootOf, encodeLoot, spawnModel, clusterPoints, reactionModel, conditionFlag };
