// Regenerates LefthyTools_DropData/Drops.lua: what each kind of mob can drop and how likely, for the
// Bestiary's comparison with your own kills (Modules/Bestiary), and its health, for the fight
// stream's estimate of mobs' health (Modules/Beacon/StreamSense.lua). A separate add-on (GPL v3, like
// its source), loaded only when one of them needs it.
//
// Source: a classic world database's loot tables and creatures, by default CMaNGOS Classic DB's
// full dump (https://github.com/cmangos/classic-db, Full_DB, GPL v3; World of Warcraft content
// belongs to Blizzard). WoW: Forever is built on classic content: its mobs and items have classic
// IDs, but its own additions aren't in there, and its rates may be tuned. Run this again when
// there's a newer dump (or one closer to Forever):
//   node tools/update-drop-data.js                          download CMaNGOS Classic DB's full dump
//   node tools/update-drop-data.js <dump.sql[.gz]> [--source "name"]   a dump you have
//   node tools/update-drop-data.js --stats                  numbers only, nothing written
//
// From the tables creature_template (LootId, SkinningLootId, MinLootGold, MaxLootGold),
// creature_loot_template, skinning_loot_template, reference_loot_template and item_template:
//   * a row with groupid 0 drops on its own with its chance; in a group (groupid > 0) one item of
//     the group drops: rows with a chance have it, rows with 0 share what's left of 100% evenly;
//   * a negative chance is a quest item's (it drops only while you have the quest): marked "q";
//   * a reference (mincountOrRef < 0) is another table, rolled with the row's chance, maxcount
//     times: an item in it drops with 1 - (1 - chance * its chance there) ^ times;
//   * an item reached more than one way: 1 - the product of (1 - each way's chance);
//   * world loot is left out (the world drop tables are references: grey, white, green, blue and
//     purple gear by level, bags, scrolls, recipes, potions, a dungeon's zone drops): what's reached
//     only through references and doesn't bind on pickup, when it's gear (a weapon or armour that can
//     be worn) or the reference is shared by SHARED loot tables or more. A boss's own references
//     (Ragnaros's tier legs) stay. The Bestiary keeps world drops apart anyway, and they'd add some
//     200 items at 0.2% to every mob;
//   * chances under MIN_CHANCE are left out.
// Health, from creature_template (MinLevel, MaxLevel, MinLevelHealth, MaxLevelHealth): what it has at
// its lowest and its highest level, the HealthMultiplier already in (93% of them are exactly
// creature_template_classlevelstats' BaseHealthExp0 times HealthMultiplier, what the emulator gives
// a creature at a level; the rest set by hand); the add-on takes a level between in a straight line
// (close to the emulator's per-level stats: most creatures span a level or two). Also for creatures
// without loot, but not for what no one fights: 1 health or less, totems (CreatureType 11), triggers
// (invisible, ExtraFlags 0x80; "Trigger", "DND" or "Only GM can see it" in the name; not selectable,
// UnitFlags 0x2000000, and friendly to all, faction 35), and the unused ones ("[UNUSED]", "[PH]" in
// the name). Not selectable alone isn't enough: Nefarian starts so.
// Output: LefthyToolsDropData = { source, mobs = { [creature ID] = "<item>:<quality>:<chance>[q],...
// [;s=<skinning in the same form>][;g=<min copper>-<max copper>][;h=<min level>[-<max level>]:<health
// at the min level>[-<at the max level>]]" } }, chances in hundredths of a percent (4785 = 47.85%), the
// likeliest first; the quality (0 grey ... 5 legendary) so grey items can be left out and edged before
// the client knows an item; the second level or health only when it differs. Strings: the Bestiary
// reads only the mobs it shows (and the fight stream the mobs it sees); builds before the health skip
// the "h" part.
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const DEFAULT_URL = "https://raw.githubusercontent.com/cmangos/classic-db/master/Full_DB/ClassicDB_1_12_1_z2815.sql.gz";
const DEFAULT_SOURCE = "CMaNGOS Classic DB, Full_DB z2815 (github.com/cmangos/classic-db, GPL v3)";
const OUT = path.join(__dirname, "..", "LefthyTools_DropData", "Drops.lua");
const MIN_CHANCE = 0.0005; // 0.05%
const MAX_DEPTH = 6;       // references in references
const SHARED = 8;          // a reference used by this many loot tables or more is world loot (levels, zones)

// The column names of a table, from its CREATE TABLE.
function columns(sql, table) {
  const m = sql.match(new RegExp("CREATE TABLE `" + table + "` \\(([\\s\\S]*?)\\n\\) ENGINE"));
  if (!m) throw new Error(`no table ${table} in the dump`);
  return m[1].split("\n").filter((l) => /^\s+`/.test(l)).map((l) => l.trim().match(/^`([^`]+)`/)[1]);
}

// Every row of a table's INSERT statements, as objects (numbers as numbers).
function rows(sql, table) {
  const names = columns(sql, table);
  const out = [];
  const head = "INSERT INTO `" + table + "` VALUES ";
  let at = 0;
  while ((at = sql.indexOf(head, at)) >= 0) {
    let i = at + head.length;
    let row = null, value = "", quoted = false, inValue = false, isString = false;
    for (; i < sql.length; i++) {
      const c = sql[i];
      if (quoted) {
        if (c === "\\") { value += sql[++i]; continue; }
        if (c === "'") { quoted = false; continue; }
        value += c;
        continue;
      }
      if (c === "(") { row = []; value = ""; inValue = true; isString = false; continue; }
      if (c === "'") { quoted = true; isString = true; continue; }
      if (c === "," && inValue) { row.push(isString ? value : value === "NULL" ? null : Number(value)); value = ""; isString = false; continue; }
      if (c === ")" && inValue) {
        row.push(isString ? value : value === "NULL" ? null : Number(value));
        out.push(Object.fromEntries(names.map((n, k) => [n, row[k]])));
        inValue = false;
        continue;
      }
      if (c === ";" && !inValue) break;
      if (inValue) value += c;
    }
    at = i;
  }
  return out;
}

function byEntry(list) {
  const map = new Map();
  for (const r of list) {
    if (!map.has(r.entry)) map.set(r.entry, []);
    map.get(r.entry).push(r);
  }
  return map;
}

// How many loot tables use each reference.
function referenceUsers(...tables) {
  const users = new Map();
  for (const list of tables) for (const r of list) if (r.mincountOrRef < 0) users.set(-r.mincountOrRef, (users.get(-r.mincountOrRef) || 0) + 1);
  return users;
}

// A loot table's items: item -> { p (0-1), quest, viaRef, viaShared } (viaRef, viaShared: reached only
// through references, through one shared by SHARED tables or more).
function chances(list, refs, users, depth, out = new Map(), viaRef = false, viaShared = false) {
  const add = (item, p, quest, ref, shared) => {
    if (p <= 0) return;
    const was = out.get(item);
    if (was) {
      was.p = 1 - (1 - was.p) * (1 - p);
      was.quest = was.quest || quest;
      was.viaRef = was.viaRef && ref;
      was.viaShared = was.viaShared && shared;
    } else out.set(item, { p, quest, viaRef: ref, viaShared: shared });
  };
  const groups = new Map();
  for (const r of list || []) {
    const chance = r.ChanceOrQuestChance;
    if (r.mincountOrRef < 0) {
      // References are rolled on their own, in a group or not (as the cores do).
      if (depth >= MAX_DEPTH) continue;
      const ref = -r.mincountOrRef, shared = viaShared || (users.get(ref) || 0) >= SHARED;
      const inner = chances(refs.get(ref), refs, users, depth + 1, new Map(), true, shared);
      const c = Math.abs(chance) / 100, times = Math.max(1, r.maxcount || 1);
      for (const [item, v] of inner) add(item, 1 - Math.pow(1 - c * v.p, times), v.quest || chance < 0, true, v.viaShared);
    } else if (!r.groupid) {
      add(r.item, Math.abs(chance) / 100, chance < 0, viaRef, viaShared);
    } else {
      if (!groups.has(r.groupid)) groups.set(r.groupid, []);
      groups.get(r.groupid).push(r);
    }
  }
  for (const group of groups.values()) {
    const explicit = group.filter((r) => r.ChanceOrQuestChance !== 0);
    const even = group.filter((r) => r.ChanceOrQuestChance === 0);
    const sum = explicit.reduce((s, r) => s + Math.abs(r.ChanceOrQuestChance), 0);
    for (const r of explicit) add(r.item, Math.abs(r.ChanceOrQuestChance) / 100, r.ChanceOrQuestChance < 0, viaRef, viaShared);
    if (even.length) for (const r of even) add(r.item, Math.max(0, 100 - sum) / 100 / even.length, false, viaRef, viaShared);
  }
  return out;
}

// Loot that isn't the mob's own: reached only through references, and gear (a weapon or armour that can
// be worn) that doesn't bind on pickup, or anything not bound on pickup from a shared reference.
function worldLoot(v, item) {
  if (!v.viaRef || !item || item.bonding === 1) return false;
  return v.viaShared || ((item.class === 2 || item.class === 4) && item.InventoryType > 0);
}

// "id:quality:chance[q],..." the likeliest first, without world loot, the unlikely and items that
// don't exist.
function encode(map, items) {
  return [...map.entries()]
    .filter(([id, v]) => items.has(id) && v.p >= MIN_CHANCE && !worldLoot(v, items.get(id)))
    .sort((a, b) => b[1].p - a[1].p || a[0] - b[0])
    .map(([id, v]) => `${id}:${items.get(id).Quality}:${Math.max(1, Math.round(Math.min(1, v.p) * 10000))}${v.quest ? "q" : ""}`)
    .join(",");
}

// A creature's health, "<min level>[-<max level>]:<health at the min level>[-<at the max level>]", or ""
// for what no one fights (see the top).
function health(c) {
  if (c.MaxLevelHealth <= 1 || c.CreatureType === 11 || (c.ExtraFlags & 0x80)
    || ((c.UnitFlags & 0x2000000) && c.Faction === 35) || /trigger|\bDND\b|only GM can see|\[UNUSED\]|\[PH\]/i.test(c.Name)) return "";
  const low = Math.min(c.MinLevel, c.MaxLevel), high = Math.max(c.MinLevel, c.MaxLevel);
  const lowHealth = Math.max(1, Math.min(c.MinLevelHealth, c.MaxLevelHealth)), highHealth = Math.max(c.MinLevelHealth, c.MaxLevelHealth);
  return (high > low ? `${low}-${high}` : `${low}`) + ":" + (highHealth > lowHealth ? `${lowHealth}-${highHealth}` : `${lowHealth}`);
}

async function readDump(arg) {
  if (arg) {
    const data = fs.readFileSync(arg);
    return arg.endsWith(".gz") ? zlib.gunzipSync(data).toString("utf8") : data.toString("utf8");
  }
  console.log(`downloading ${DEFAULT_URL}`);
  const response = await fetch(DEFAULT_URL);
  if (!response.ok) throw new Error(`download failed: ${response.status}`);
  return zlib.gunzipSync(Buffer.from(await response.arrayBuffer())).toString("utf8");
}

async function main() {
  const args = process.argv.slice(2);
  const stats = args.includes("--stats");
  const sourceAt = args.indexOf("--source");
  const source = sourceAt >= 0 ? args[sourceAt + 1] : DEFAULT_SOURCE;
  const dump = args.find((a, i) => !a.startsWith("--") && args[i - 1] !== "--source");
  const sql = await readDump(dump);

  const creatures = rows(sql, "creature_template");
  const lootRows = rows(sql, "creature_loot_template"), refRows = rows(sql, "reference_loot_template");
  const skinRows = rows(sql, "skinning_loot_template");
  const loot = byEntry(lootRows), skin = byEntry(skinRows), refs = byEntry(refRows);
  const users = referenceUsers(lootRows, skinRows, refRows);
  const items = new Map(rows(sql, "item_template").map((i) => [i.entry, i]));
  console.log(`${creatures.length} creatures, ${loot.size} loot tables, ${skin.size} skinning tables, ${refs.size} references, ${items.size} items`);

  const mobs = [];
  let entries = 0, longest = 0, looted = 0, healthy = 0;
  for (const c of creatures) {
    const drops = c.LootId ? encode(chances(loot.get(c.LootId), refs, users, 0), items) : "";
    const skins = c.SkinningLootId ? encode(chances(skin.get(c.SkinningLootId), refs, users, 0), items) : "";
    const coin = c.MaxLootGold > 0 ? `${c.MinLootGold}-${c.MaxLootGold}` : "";
    const life = health(c);
    if (!drops && !skins && !coin && !life) continue;
    let text = drops;
    if (skins) text += `;s=${skins}`;
    if (coin) text += `;g=${coin}`;
    if (life) text += `;h=${life}`;
    const count = (drops ? drops.split(",").length : 0) + (skins ? skins.split(",").length : 0);
    entries += count;
    longest = Math.max(longest, count);
    if (drops || skins || coin) looted++;
    if (life) healthy++;
    mobs.push([c.Entry, text]);
  }
  mobs.sort((a, b) => a[0] - b[0]);
  const lines = mobs.map(([id, text]) => `\t[${id}] = "${text}",`);
  const lua = [
    `-- Generated by tools/update-drop-data.js from ${source}. Don't edit: run the tool again.`,
    "-- What each kind of mob can drop (creature ID): \"<item>:<quality>:<chance in hundredths of a percent>[q for",
    "-- a quest item],...[;s=<skinning, the same>][;g=<min copper>-<max copper>][;h=<min level>[-<max level>]:<its",
    "-- health at the min level>[-<at the max level>]]\", the likeliest first; world loot left out.",
    "-- GPL v3 (LICENSE.md); World of Warcraft content and names belong to Blizzard (COPYRIGHT.md).",
    "LefthyToolsDropData = {",
    `\tsource = ${JSON.stringify(source)},`,
    "\tmobs = {",
    ...lines.map((l) => "\t" + l),
    "\t},",
    "}",
    "",
  ].join("\n");
  console.log(`${mobs.length} mobs: ${looted} with loot, ${entries} drops (at most ${longest} for one); ${healthy} with health; ${(lua.length / 1024 / 1024).toFixed(2)} MB`);
  if (stats) return;
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, lua, "utf8");
  console.log(`written: ${path.relative(process.cwd(), OUT)}`);
}

if (require.main === module) main().catch((e) => { console.error(e.message); process.exit(1); });
module.exports = { rows, byEntry, referenceUsers, chances, worldLoot, encode, health };
