// Regenerates LefthyTools_QuestData/QuestData.lua: every quest's chain (what it needs first, what it
// leads to), its levels, who it's for, its zone, and who gives and takes it and where they stand, for
// the Lodestar module (Modules/Lodestar/Data.lua reads it; docs/lodestar.md, Data). A separate
// add-on (GPL v3, like its main source), loaded only when a Lodestar window opens.
//
// Sources:
// - Classic quests: CMaNGOS Classic DB's full dump (https://github.com/cmangos/classic-db, Full_DB
//   z2815, GPL v3; the same dump as tools/update-drop-data.js): quest_template, creature_ and
//   gameobject_questrelation / involvedrelation (givers, enders), item_template.startquest (items
//   that start a quest), creature and gameobject (where they stand), creature_template and
//   gameobject_template (names, factions, loot), creature_ / gameobject_ / reference_loot_template
//   (where the items that start quests drop), quest_template's objectives (ReqCreatureOrGOId, ReqItemId and
//   their counts) and rewards (RewChoiceItemId, RewItemId, RewOrReqMoney, RewMoneyMaxLevel), game_event,
//   game_event_quest and game_event_creature / _gameobject (the holidays' quests and who stands only then).
// - WoW: Forever's own quests (new since classic): EG Link output (Efficient Games,
//   https://github.com/JIVESCORP/eg-link-output-wowf, CC BY 4.0: what players' games recorded on
//   Forever): quests.enUS (title, levels, races, zone, the next quest, the item that starts it),
//   npcs (who offers and takes each quest, where they stand), quest_prerequisites (what every
//   character had done before taking it) and loot (what players looted from what, and where: for
//   the items that start quests classic-db has no source of), the quests' objectives and rewards (what
//   Forever's server says: for every quest it has, classic's too) and turn_ins (the money players got, their
//   side), creatures (where players met Forever's own creatures, how they reacted to each side), the quests'
//   objectivesText and description (whom a quest is for, below). Selected and converted, not changed otherwise.
// - Forever's client tables (wago.tools exports of the build): UiMap, UiMapAssignment (zones and
//   their world rectangles), AreaTable, Map, QuestSort (names), FactionTemplate (which side an NPC
//   is on), ChrRaces (Forever's playable races: their race-mask bits, sides), QuestV2 (the quests the client knows), QuestLineXQuest (Forever's quest
//   lines), ItemSparse (StartQuestID, names), QuestPOIBlob (a quest's map, when nothing else says) and
//   QuestXP (a quest's experience by its level and XP difficulty). The client has no QuestObjective table
//   (wago.tools: "Table not found" for Forever's builds): objectives come from EG Link and classic-db.
// - Data/ForeverQuests.lua (tools/update-forever-quests.ps1): which quests are new in Forever.
// Not used: Wowhead and anything taken from Questie (the project's rule), ForeverCore's sniffs
// (GPL-2.0 without "or later", so not combinable with the GPL v3 here, and it credits Questie).
//
// Rules (MaNGOS' meaning of the columns, as the core checks them):
// - A quest's previous quests: its PrevQuestId (> 0: done first; < 0: in the log) and every quest
//   whose NextQuestId names it (> 0 / < 0 the same). Any one of the positive ones done is enough
//   (preAny), with one exception: one in an ExclusiveGroup < 0 needs the whole group done (pre).
//   One previous quest alone: pre. In the log: preActive.
// - ExclusiveGroup > 0: the quests of the group close each other (excl).
// - NextQuestInChain and BreadcrumbForQuestId lead to a quest without being needed (opens only).
// - opens: the reverse of all of that, every quest this one leads to.
// - Positions: a spawn's world x/y on its map, put on the smallest zone (or dungeon floor) rectangle
//   of UiMapAssignment holding it (mapX = (maxY - y) / (maxY - minY), mapY = (maxX - x) / (maxX -
//   minX), then into the assignment's UiMin..UiMax). Rectangles of two zones overlap at their
//   borders: the zone of the NPC's own quests wins, and the others go with the point as
//   alternatives ("/"), which Data.lua checks with the client's own map (C_Map.GetMapInfoAtPosition).
// - Faction: the races' (only Alliance or only Horde), else the givers' side (FactionTemplate's
//   groups, EG Link's "side"), when every giver is on the same one; else, with no NPC giver, the enders'.
//   Forever's own quests with none of that (EG Link's raceMask is all bits for them): an NPC their text
//   names ("for Foreman Oslow in Redridge"), else their zone when it's a side's own (HOME_ZONES); never
//   a side whose other side's players were seen turning it in (sideFromText).
// - Events (flag e): the holidays' quests (QuestSort Seasonal, Lunar Festival, Midsummer, Darkmoon Faire,
//   ...; game_event_quest; givers that stand only while a holiday is on), and what needs one of them with
//   no giver standing outside it (markEvents).
// - Races: Forever's playable races (ChrRaces: classic's eight and the ones with their playable
//   flags, the Skyborne), each by its PlayableRaceBit. A quest open to every classic race of a side
//   is open to every race of that side (classic-db knows only the eight); open to all: no mask.
// - Items that start a quest: where they drop (classic-db's creature and gameobject loot, through
//   references; else EG Link's loot): the likeliest sources (MAX_SOURCES), each with its spawns in
//   up to MAX_CLUSTERS clusters (centre and radius).
// - Objectives: EG Link's (kill a creature, use or loot an object, collect an item; by storage index)
//   for the quests it has, else classic-db's (ReqCreatureOrGOId: a creature, negative an object; then
//   ReqItemId). Each objective's target has a place: a creature's and an object's spawns in clusters
//   (dropNpcs, dropObjects, as drop sources), an item where it drops (items, as for starters).
// - Rewards: EG Link's (choices, items, money, XP difficulty) for the quests it has, else classic-db's.
//   XP: the client's QuestXP row of the quest's level at its difficulty, times the multiplier, the game's
//   rounding (as players got it on turn-in: 425 of 482 exactly, the rest a 3% bonus); classic-db's
//   RewMoneyMaxLevel / 0.6 put on the nearest value of that row, rounded (97% of Forever's for normal quests;
//   none for dungeon, raid and PvP quests, which Forever multiplies).
// - Levels: EG Link's for the quests it has (Forever changed some of classic's); a level of -1 or 0
//   scales to the player (flag s, no level).
// - Mob levels (mobs): what a quest's objectives make you fight: kill targets, and for an item to collect the
//   easiest of the creatures it's likely to drop from (itemFight); each creature's levels classic-db's
//   creature_template MinLevel..MaxLevel, EG Link's creatures (the levels players saw) where classic-db hasn't
//   it or Forever changed it (creatureLevels). Not triggers or friends of the quest's side.
// - Group (flag g): quest type elite (1), dungeon (81) or raid (62): EG Link's questInfoId for the quests it
//   has (Forever's server's), else classic-db's Type.
// - Who starts and ends what (npcQuests, objectQuests) and the quests given in a zone that are
//   listed elsewhere (a dungeon's, a city's): for tooltips and "what's here" without reading all.
// - Left out: quests the client doesn't know (not in QuestV2, unless repeatable: those have no
//   completion bit), unused ones by their title, quests nobody gives or takes.
//
// Run it again when Forever gets new builds or EG Link has more:
//   node tools/update-quest-data.js                         the latest Forever build, EG Link's newest
//   node tools/update-quest-data.js 1.60.1.70862 --cache <dir>   keep the downloads in <dir>
//   node tools/update-quest-data.js --dump <dump.sql[.gz]>  a classic dump you have
//   node tools/update-quest-data.js --eglink <sha>          EG Link at that commit (default: main's newest)
//   node tools/update-quest-data.js --stats                 only the numbers, nothing written
// The output is the same for the same inputs (everything sorted).
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");
const { rows, byEntry, referenceUsers, chances } = require("./update-drop-data");
const { table, latestBuild } = require("./wago");

const DUMP_URL = "https://raw.githubusercontent.com/cmangos/classic-db/master/Full_DB/ClassicDB_1_12_1_z2815.sql.gz";
const DUMP_NAME = "CMaNGOS Classic DB, Full_DB z2815 (github.com/cmangos/classic-db, GPL v3)";
const EG_REPO = "JIVESCORP/eg-link-output-wowf";
const OUT = path.join(__dirname, "..", "LefthyTools_QuestData", "QuestData.lua");
const FOREVER_QUESTS = path.join(__dirname, "..", "LefthyTools", "Data", "ForeverQuests.lua");

const CLASSIC_RACES = 255; // classic's race bits (race ID r: bit r - 1)
const PLAYABLE_FLAGS = 0x600000; // ChrRaces.Flags every playable race of Forever has (classic's eight, the Skyborne)
const MAX_SOURCES = 3; // drop sources kept per item
const MAX_CLUSTERS = 3; // clusters of a drop source's spawns kept
const CLUSTER = 70; // spawns this close (thousandths of the map's width) are one cluster
const ASPECT = 1.5; // a zone map's width over its height
const MAX_POINTS = 5; // spawns kept per NPC or object (a 1% grid apart)
const SIMILAR = 4; // zones' rectangles at most this many times the other's size can be a place's alternative
const UNUSED = /\[UNUSED\]|<UNUSED>|UNUSED |<NYI>|\bNYI\b|<TXT>|\[PH\]|<CHANGE TO GOSSIP>|^ZZOLD|\(OLD\)|<TEST>|\bTEST\b|^Test |^REUSE|\[DEPRECATED\]|<DEPRECATED>|Deprecated/;
const ZONE_TYPES = { 3: 0, 4: 1 }; // UiMap types a position goes on (zone, dungeon floor), in that order of preference
const OBJECTIVE_KINDS = { monster: "k", gameObject: "o", item: "i" }; // EG Link's objective types kept (kill, object, item)
const XP_UNKNOWN = new Set([41, 62, 81]); // quest types (PvP, raid, dungeon) whose XP Forever multiplies: no classic formula
const GROUP_TYPES = new Set([1, 62, 81]); // quest types (classic-db's Type, EG Link's questInfoId) for a group: elite, raid, dungeon
const NOT_SELECTABLE = 0x2000000; // creature_template.UnitFlags: a trigger nobody can target
const INVISIBLE = 0x80; // creature_template.ExtraFlags (CMaNGOS' CREATURE_EXTRA_FLAG_INVISIBLE)
const MANY_SOURCES = 40; // an item dropping from more creatures and objects than this: a world drop, not a mob's level
const RARE_CHANCE = 0.05; // an item's likeliest drop below this: made or bought, not a mob's level
const MOB_GAP = 10; // mobs more levels than this above a quest's own aren't its (a drop source elsewhere)
const MIN_CHANCE = 0.2; // a creature that drops an item this often (or a quarter as often as the likeliest one) is where you get it
// Quest sorts and classic-db game events of holidays (and the Darkmoon Faire, the weekly fishing contest).
const HOLIDAY = /Seasonal|Lunar Festival|Love is in the Air|Noblegarden|Children's Week|Midsummer|Brewfest|Hallow's End|Harvest Festival|Pilgrim's Bounty|Winter Veil|New Year|Darkmoon Faire|Fishing Extravaganza|Day of the Dead|Pirates' Day|Scourge Invasion|^Invasion$/;
// Each side's own zones (UiMap names): a Forever quest there with nothing else saying its side is that side's.
const HOME_ZONES = {
  Alliance: ["Elwynn Forest", "Westfall", "Redridge Mountains", "Duskwood", "Loch Modan", "Dun Morogh", "Teldrassil", "Darkshore",
    "Stormwind City", "Ironforge", "Darnassus"],
  Horde: ["Durotar", "Mulgore", "Tirisfal Glades", "Silverpine Forest", "Orgrimmar", "Thunder Bluff", "Undercity"],
};

const byNumber = (a, b) => a - b;
const uniq = (list) => [...new Set(list)];

// ---------------------------------------------------------------- downloads (kept in --cache)

async function fetchBuffer(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${url}: HTTP ${response.status}`);
  return Buffer.from(await response.arrayBuffer());
}

// A download, read from the cache folder when it's there (file: its name there).
async function cached(cache, file, url) {
  const at = cache && path.join(cache, file);
  if (at && fs.existsSync(at)) return fs.readFileSync(at);
  console.log(`downloading ${url}`);
  const data = await fetchBuffer(url);
  if (at) fs.writeFileSync(at, data);
  return data;
}

async function readDump(file, cache) {
  const data = file ? fs.readFileSync(file) : await cached(cache, path.basename(DUMP_URL), DUMP_URL);
  return (file && !file.endsWith(".gz") ? data : zlib.gunzipSync(data)).toString("utf8");
}

// EG Link's files of a build, at a commit (its sha: main's newest unless given).
async function eglink(build, ref, cache) {
  if (!ref) {
    const response = await fetch(`https://api.github.com/repos/${EG_REPO}/commits/main`);
    if (!response.ok) throw new Error(`EG Link: HTTP ${response.status} for the newest commit; pass --eglink <sha>`);
    ref = (await response.json()).sha;
  }
  const base = `https://raw.githubusercontent.com/${EG_REPO}/${ref}/data/`;
  const index = JSON.parse(await cached(cache, `eglink-${ref}-index.json`, base + "index.json"));
  // The build's own folder, else the newest build before it with quests.
  const builds = Object.keys(index.products.wowf || {}).filter((b) => index.products.wowf[b]["quests.enUS"]);
  const key = (v) => v.split(".").map((n) => n.padStart(8, "0")).join(".");
  const use = builds.includes(build) ? build : builds.filter((b) => key(b) <= key(build)).sort((a, b) => (key(a) < key(b) ? 1 : -1))[0];
  if (!use) throw new Error(`EG Link has no quests for ${build}`);
  const get = async (name) => {
    if (!index.products.wowf[use][name]) return null;
    return JSON.parse(await cached(cache, `eglink-${ref}-${use}-${name}.json`, `${base}wowf/${use}/${name}.json`));
  };
  return {
    ref, build: use,
    quests: (await get("quests.enUS")).quests,
    npcs: (await get("npcs")) || {},
    prerequisites: ((await get("quest_prerequisites")) || {}).quests || {},
    loot: ((await get("loot")) || {}).sources || {},
    creatures: ((await get("creatures")) || {}).creatures || {},
    turnIns: ((await get("turn_ins")) || {}).quests || {},
    objects: ((await get("object_details.enUS")) || {}).objects || {},
  };
}

// ---------------------------------------------------------------- helpers

// The quest IDs of a list in Data/ForeverQuests.lua ("86574,86576-86577,...").
function foreverIds(name) {
  const text = fs.readFileSync(FOREVER_QUESTS, "utf8");
  const m = text.match(new RegExp(name.replace(/\./g, "\\.") + " = table\\.concat\\(\\{([\\s\\S]*?)\\}\\)"));
  if (!m) throw new Error(`no ${name} in ${FOREVER_QUESTS}`);
  const ids = new Set();
  for (const part of [...m[1].matchAll(/"([^"]*)"/g)].map((x) => x[1]).join("").split(",")) {
    if (!part) continue;
    const [a, b] = part.split("-").map(Number);
    for (let i = a; i <= (b || a); i++) ids.add(i);
  }
  return ids;
}

// The world's maps: zones, their names and continents, the rectangles positions go on.
function worldMaps(t) {
  // (city: a zone map without flag 2, Stormwind City, Orgrimmar, ...: never another zone's alternative)
  const ui = new Map(t.UiMap.map((r) => [+r.ID, { id: +r.ID, name: r.Name_lang, parent: +r.ParentUiMapID, type: +r.Type, city: (+r.Flags & 2) === 0 }]));
  const continentOf = (id) => {
    for (let at = ui.get(id), n = 0; at && n < 10; at = ui.get(at.parent), n++) if (at.type === 2) return at.id;
    return id;
  };
  const boxes = [], continentBoxes = [];
  const areaToUi = new Map();
  for (const r of t.UiMapAssignment) {
    const u = ui.get(+r.UiMapID);
    if (!u) continue;
    const box = {
      map: +r.MapID, ui: u.id, type: u.type, city: u.city,
      minX: +r.Region_0, minY: +r.Region_1, minZ: +r.Region_2, maxX: +r.Region_3, maxY: +r.Region_4, maxZ: +r.Region_5,
      u0: +r.UiMin_0, v0: +r.UiMin_1, u1: +r.UiMax_0, v1: +r.UiMax_1, order: +r.OrderIndex,
    };
    box.size = (box.maxX - box.minX) * (box.maxY - box.minY);
    if (u.type in ZONE_TYPES && box.size > 0) boxes.push(box);
    if (u.type === 2 && box.size > 0) continentBoxes.push(box);
    // An area's map: a zone before a dungeon floor before anything else, the first floor.
    const area = +r.AreaID;
    if (area) {
      const rank = (b) => (b.type === 3 ? 0 : b.type === 4 ? 1 : 2) * 1000 + b.order;
      const had = areaToUi.get(area);
      if (!had || rank(box) < rank(had)) areaToUi.set(area, box);
    }
  }
  boxes.sort((a, b) => ZONE_TYPES[a.type] - ZONE_TYPES[b.type] || a.size - b.size || a.ui - b.ui);
  const areas = new Map(t.AreaTable.map((r) => [+r.ID, { id: +r.ID, name: r.AreaName_lang, parent: +r.ParentAreaID, map: +r.ContinentID }]));
  const instance = new Map(t.Map.map((r) => [+r.ID, { name: r.MapName_lang, type: +r.InstanceType }]));
  // An instance's own area (Blackrock Depths' area is on Eastern Kingdoms' map in AreaTable).
  const instanceArea = new Map(t.Map.filter((r) => +r.AreaTableID).map((r) => [+r.AreaTableID, instance.get(+r.ID)]));
  // An area's uiMap (itself or a parent area's), or nil.
  const uiOfArea = (id) => {
    for (let a = id, n = 0; a && n < 12; n++) {
      const box = areaToUi.get(a);
      if (box) return box.ui;
      a = areas.get(a) ? areas.get(a).parent : 0;
    }
    return undefined;
  };
  return { ui, boxes, continentBoxes, areas, instance, instanceArea, continentOf, uiOfArea };
}

// A point (0..1) on a rectangle's uiMap for world x, y.
function onBox(b, x, y) {
  const fx = (b.maxY - y) / (b.maxY - b.minY), fy = (b.maxX - x) / (b.maxX - b.minX);
  return [b.u0 + fx * (b.u1 - b.u0), b.v0 + fy * (b.v1 - b.v0)];
}
const inBox = (b, m, x, y, z) => b.map === m && x >= b.minX && x <= b.maxX && y >= b.minY && y <= b.maxY
  && (z === undefined || !(b.maxZ - b.minZ < 1e5) || (z >= b.minZ - 5 && z <= b.maxZ + 5));
// b inside a (a rectangle of another map holding it whole: a city in its zone).
const inside = (b, a) => b.map === a.map && b.minX >= a.minX && b.maxX <= a.maxX && b.minY >= a.minY && b.maxY <= a.maxY;

// The places of a spawn: the best rectangle first, then the zones whose rectangles only overlap it
// there (borders), [] where no zone has it. prefer: uiMaps to pick when they hold it (the NPC's
// quests' zones, most quests first).
function places(world, m, x, y, z, prefer) {
  const hits = world.boxes.filter((b) => inBox(b, m, x, y, z));
  if (!hits.length) return [];
  let best = hits[0];
  for (const want of prefer || []) {
    const hit = hits.find((b) => b.ui === want);
    // (not a city's zone over the city)
    if (hit && (hit === hits[0] || (hit.city === hits[0].city && !inside(hits[0], hit)))) { best = hit; break; }
  }
  // Others: zones of about the same size whose rectangles overlap it here (a city and its zone aren't).
  const others = hits.filter((b) => b !== best && b.type === best.type && b.city === best.city && b.ui !== best.ui && !inside(best, b) && !inside(b, best)
    && Math.max(b.size, best.size) < SIMILAR * Math.min(b.size, best.size));
  const seen = new Set([best.ui]);
  const out = [best];
  for (const b of others) if (!seen.has(b.ui)) { seen.add(b.ui); out.push(b); }
  return out.map((b) => {
    const [px, py] = onBox(b, x, y);
    return [b.ui, Math.max(0, Math.min(999, Math.round(px * 1000))), Math.max(0, Math.min(999, Math.round(py * 1000)))];
  });
}

// Which side an NPC is on by its faction template: "Alliance", "Horde" or undefined (both, neither).
function sideOf(templates, id) {
  const t = templates.get(id);
  if (!t) return undefined;
  const group = +t.FactionGroup, friend = +t.FriendGroup, enemy = +t.EnemyGroup;
  const alliance = ((group | friend) & 2) !== 0 && (enemy & 2) === 0;
  const horde = ((group | friend) & 4) !== 0 && (enemy & 4) === 0;
  if (alliance && !horde) return "Alliance";
  if (horde && !alliance) return "Horde";
  if ((enemy & 4) && !(enemy & 2)) return "Alliance"; // hostile to the Horde only
  if ((enemy & 2) && !(enemy & 4)) return "Horde";
  return undefined;
}

// Forever's playable races (ChrRaces' rows) and race masks. Masks are numbers with bits above 31 (the
// Skyborne's 32 and 33), so no bit operators: bit b is 2^b.
function raceModel(rows) {
  const list = rows
    .filter((r) => +r.PlayableRaceBit >= 0 && (+r.Flags & PLAYABLE_FLAGS) === PLAYABLE_FLAGS && (+r.Alliance === 0 || +r.Alliance === 1))
    .map((r) => ({ id: +r.ID, bit: +r.PlayableRaceBit, faction: +r.Alliance === 0 ? "Alliance" : "Horde", name: r.Name_lang, classic: +r.ID <= 8 }))
    .sort((a, b) => a.id - b.id);
  if (list.filter((r) => r.classic && r.bit === r.id - 1).length !== 8) throw new Error("ChrRaces: classic's eight races aren't there as before");
  const has = (mask, bit) => Math.floor(mask / 2 ** bit) % 2 === 1;
  const sum = (races) => races.reduce((m, r) => m + 2 ** r.bit, 0);
  const all = sum(list);
  // Every classic race of a side: every race of that side. Only playable races' bits; all: undefined.
  const expand = (mask) => {
    let m = sum(list.filter((r) => has(mask || 0, r.bit)));
    for (const side of ["Alliance", "Horde"]) {
      if (list.filter((r) => r.classic && r.faction === side).every((r) => has(m, r.bit))) {
        m = sum(list.filter((r) => has(m, r.bit) || r.faction === side));
      }
    }
    return m && m !== all ? m : undefined;
  };
  // A 64-bit mask in hex (EG Link's raceMask), only the playable races' bits.
  const fromHex = (hex) => {
    if (!hex || !/^[0-9a-fA-F]+$/.test(hex)) return 0;
    const big = BigInt("0x" + hex);
    return sum(list.filter((r) => ((big >> BigInt(r.bit)) & 1n) === 1n));
  };
  // "Alliance" or "Horde" when every race of the mask is of that side.
  const faction = (mask) => {
    if (!mask) return undefined;
    const sides = uniq(list.filter((r) => has(mask, r.bit)).map((r) => r.faction));
    return sides.length === 1 ? sides[0] : undefined;
  };
  return { list, all, has, expand, fromHex, faction };
}

// Points ([ui, x, y], thousandths) in clusters: [{ ui, x, y, r, n }] the most points first, at most
// MAX_CLUSTERS. r: the farthest point from the centre plus a margin, in thousandths of the map's width.
function clusters(points) {
  const dist = (c, p) => Math.hypot(c.x - p[1], (c.y - p[2]) / ASPECT);
  const out = [];
  for (const p of points.slice().sort((a, b) => a[0] - b[0] || a[1] - b[1] || a[2] - b[2])) {
    let c = out.find((k) => k.ui === p[0] && dist(k, p) <= CLUSTER);
    if (!c) { c = { ui: p[0], x: p[1], y: p[2], sx: 0, sy: 0, n: 0, members: [] }; out.push(c); }
    c.sx += p[1]; c.sy += p[2]; c.n++;
    c.x = c.sx / c.n; c.y = c.sy / c.n;
    c.members.push(p);
  }
  for (const c of out) {
    c.x = Math.round(c.x); c.y = Math.round(c.y);
    c.r = Math.max(15, Math.min(150, Math.round(Math.max(0, ...c.members.map((p) => dist(c, p))) + 10)));
  }
  return out.sort((a, b) => b.n - a.n || a.ui - b.ui || a.x - b.x || a.y - b.y).slice(0, MAX_CLUSTERS)
    .map((c) => ({ ui: c.ui, x: c.x, y: c.y, r: c.r, n: c.n }));
}

// The game's rounding of quest experience (to 5, 10, 25 or 50 by its size).
function roundXp(xp) {
  if (xp <= 100) return 5 * Math.floor((xp + 2) / 5);
  if (xp <= 500) return 10 * Math.floor((xp + 5) / 10);
  if (xp <= 1000) return 25 * Math.floor((xp + 12) / 25);
  return 50 * Math.floor((xp + 25) / 50);
}

// A creature's levels, [min, max], for the quests that make you fight it (levelOf(id, side): side the quest's,
// "Alliance" or "Horde", or undefined): classic-db's creature_template MinLevel..MaxLevel; EG Link's (the levels players
// saw it at on Forever) where classic-db doesn't have it, or where players saw it at a level outside classic-db's
// range (Forever changed it: Silithid Swarm 1 to 21-22); EG Link's -1 (a boss's "??") isn't a level. None for one you
// don't fight: a trigger (not selectable, invisible), a friend of the quest's side (one of both sides' without a side).
function creatureLevels(creatureT, egCreatures, templates) {
  const friendly = (factionId, side) => {
    const t = templates.get(factionId);
    if (!t) return false;
    const of = (bit) => ((+t.FactionGroup | +t.FriendGroup) & bit) !== 0 && (+t.EnemyGroup & bit) === 0;
    return side === "Alliance" ? of(2) : side === "Horde" ? of(4) : of(2) && of(4);
  };
  return (id, side) => {
    const c = creatureT.get(id), e = egCreatures[id];
    const seen = Object.keys((e && e.levels) || {}).map(Number).filter((l) => l > 0);
    if (c) {
      if ((c.UnitFlags & NOT_SELECTABLE) || (c.ExtraFlags & INVISIBLE) || friendly(c.Faction, side)) return undefined;
      if (!(c.MinLevel > 0)) return undefined;
      const lo = c.MinLevel, hi = Math.max(c.MinLevel, c.MaxLevel);
      if (seen.length && seen.some((l) => l < lo || l > hi)) return [Math.min(...seen), Math.max(...seen)];
      return [lo, hi];
    }
    if (!seen.length) return undefined;
    const r = (e && e.reactions) || {};
    const friend = (s) => (r[s] || []).some((v) => v >= 5);
    if (side ? friend(side) : friend("Alliance") && friend("Horde")) return undefined;
    return [Math.min(...seen), Math.max(...seen)];
  };
}

// A quest's mob levels from its targets' ([[min, max]]): [the highest of their lowest levels (what you have to fight
// at least), the highest level of any], undefined without any.
function mobLevelsOf(list) {
  if (!list.length) return undefined;
  return [Math.max(...list.map((l) => l[0])), Math.max(...list.map((l) => l[1]))];
}

// A quest's objectives: [{ kind: "k" (kill) | "o" (object) | "i" (item), id, count }]. EG Link's (e, by
// storage index) when it lists them, else classic-db's (c: creatures and objects, then items).
function objectivesOf(e, c) {
  if (e && Array.isArray(e.objectives)) {
    return e.objectives.filter((o) => OBJECTIVE_KINDS[o.type] && o.objectId > 0)
      .sort((a, b) => (a.storageIndex || 0) - (b.storageIndex || 0) || (a.id || 0) - (b.id || 0))
      .map((o) => ({ kind: OBJECTIVE_KINDS[o.type], id: o.objectId, count: Math.max(1, o.amount || 1) }));
  }
  const out = [];
  if (!c) return out;
  for (let i = 1; i <= 4; i++) {
    const id = c["ReqCreatureOrGOId" + i];
    if (id) out.push({ kind: id > 0 ? "k" : "o", id: Math.abs(id), count: Math.max(1, c["ReqCreatureOrGOCount" + i] || 1) });
  }
  for (let i = 1; i <= 4; i++) {
    if (c["ReqItemId" + i]) out.push({ kind: "i", id: c["ReqItemId" + i], count: Math.max(1, c["ReqItemCount" + i] || 1) });
  }
  return out;
}

// A quest's rewards: { choice: [[item, count]], items: [[item, count]], money (copper), xp } (undefined
// where none). EG Link's (e) for the quests it has, else classic-db's (c). xpRow(level): the client's
// QuestXP row; paid: money players got on turn-in below level 60 (EG Link's turn_ins), or undefined.
function rewardsOf(e, c, xpRow, paid) {
  const pairs = (list) => (list || []).filter((x) => x.itemId > 0).map((x) => [x.itemId, Math.max(1, x.count || 1)]);
  const out = {};
  if (e && e.rewards) {
    const r = e.rewards;
    out.choice = pairs(r.choices);
    out.items = pairs(r.items);
    if (r.money > 0) out.money = r.money;
    else if (paid !== undefined) out.money = paid > 0 ? paid : undefined;
    else if (c && c.RewOrReqMoney > 0) out.money = c.RewOrReqMoney;
    const row = e.level > 0 && xpRow(e.level);
    const base = row && +row["Difficulty_" + r.xpDifficulty];
    if (base > 0) out.xp = roundXp(Math.floor(base * (r.xpMultiplier > 0 ? r.xpMultiplier : 1)));
  } else if (c) {
    out.choice = [], out.items = [];
    for (let i = 1; i <= 6; i++) if (c["RewChoiceItemId" + i]) out.choice.push([c["RewChoiceItemId" + i], Math.max(1, c["RewChoiceItemCount" + i] || 1)]);
    for (let i = 1; i <= 4; i++) if (c["RewItemId" + i]) out.items.push([c["RewItemId" + i], Math.max(1, c["RewItemCount" + i] || 1)]);
    if (c.RewOrReqMoney > 0) out.money = c.RewOrReqMoney;
    // (classic's experience is RewMoneyMaxLevel / 0.6; Forever's the nearest of its level's QuestXP row)
    const row = c.QuestLevel > 0 && c.RewMoneyMaxLevel > 0 && !XP_UNKNOWN.has(c.Type) && xpRow(c.QuestLevel);
    if (row) {
      const want = c.RewMoneyMaxLevel / 0.6;
      let best;
      for (let d = 1; d <= 9; d++) {
        const v = +row["Difficulty_" + d];
        if (v > 0 && (best === undefined || Math.abs(v - want) < Math.abs(best - want))) best = v;
      }
      if (best !== undefined && Math.abs(best - want) <= want * 0.05) out.xp = roundXp(best);
    }
  }
  return out;
}

// A Forever quest with no race mask, no faction and no giver or ender on a side (EG Link's raceMask is
// all bits for them: the server leaves it to the giver's faction, which players' games don't record
// when they took it from a giver EG Link didn't see): (a) an NPC its objectives text (else its
// description) names, "for <Name>", "to <Name>", "<Name> at/in ...", found by its exact name among
// classic-db's creatures and EG Link's NPCs and creatures, all of that name on the same side
// (FactionTemplate, EG Link's side, players' reactions on both sides); a kill objective's creature
// isn't one; (b) else its zone when it's one side's own (HOME_ZONES). Classic quests keep classic-db's
// word: neutral givers there give to both sides (Captain Grayson in Westfall).
function sideFromText(quests, eg, actors, creatureT, egNpc, templates, world) {
  const nameSides = new Map(); // name -> Set of sides ("" for neither)
  const addName = (name, side) => {
    if (!name) return;
    (nameSides.get(name) || nameSides.set(name, new Set()).get(name)).add(side || "");
  };
  for (const c of creatureT.values()) addName(c.Name, sideOf(templates, c.Faction));
  for (const [k, r] of egNpc) if (k[0] === "n") addName(r.name, r.side === "Alliance" || r.side === "Horde" ? r.side : "");
  for (const [id, c] of Object.entries(eg.creatures)) {
    if (creatureT.has(+id) || egNpc.has("n" + id) || !c.reactions) continue;
    const friendly = (side) => (c.reactions[side] || []).some((v) => v >= 5);
    const hostile = (side) => (c.reactions[side] || []).some((v) => v <= 2);
    addName(c.name, friendly("Alliance") && hostile("Horde") ? "Alliance" : friendly("Horde") && hostile("Alliance") ? "Horde" : "");
  }
  const sideOfName = (name) => {
    const set = nameSides.get(name);
    return set && set.size === 1 && [...set][0] ? [...set][0] : undefined;
  };
  const creatureName = (id) => (creatureT.get(id) && creatureT.get(id).Name) || (eg.creatures[id] && eg.creatures[id].name)
    || (egNpc.get("n" + id) && egNpc.get("n" + id).name);
  const WORD = "[A-Z][A-Za-z'\u2019-]*";
  const NAME = `${WORD}(?:\\s+(?:${WORD}|of|the|de|von|van))*`;
  const AFTER = new RegExp(`\\b(?:for|to|with|from)\\s+(${NAME})`, "g");
  const BEFORE = new RegExp(`(${NAME})\\s+(?:at|in)\\s`, "g");
  // The sides of the NPCs a text names (each candidate: whole, then without leading, then trailing words).
  const named = (text, skip) => {
    const found = [];
    for (const re of [AFTER, BEFORE]) {
      for (const m of String(text || "").replace(/\$\w+/g, " ").matchAll(re)) {
        const words = m[1].split(/\s+/);
        const tries = [];
        for (let i = 0; i < words.length; i++) tries.push(words.slice(i).join(" "));
        for (let j = words.length - 1; j >= 1; j--) tries.push(words.slice(0, j).join(" "));
        for (const name of tries) {
          if (skip.has(name)) continue;
          const side = sideOfName(name);
          if (side) { found.push([name, side]); break; }
        }
      }
    }
    return found;
  };
  const allianceMaps = new Set(), hordeMaps = new Set();
  for (const u of world.ui.values()) {
    if (u.type !== 3) continue;
    if (HOME_ZONES.Alliance.includes(u.name)) allianceMaps.add(u.id);
    if (HOME_ZONES.Horde.includes(u.name)) hordeMaps.add(u.id);
  }
  const missing = [...HOME_ZONES.Alliance, ...HOME_ZONES.Horde].filter((n) => ![...world.ui.values()].some((u) => u.type === 3 && u.name === n));
  if (missing.length) throw new Error(`UiMap has no zone named ${missing.join(", ")}`);
  console.log(`home zones: Alliance ${[...allianceMaps].sort(byNumber).join(",")}; Horde ${[...hordeMaps].sort(byNumber).join(",")}`);
  const byEnder = [], byText = [], byZone = [], both = [];
  // (a side players of the other one were seen turning it in can't be: EG Link's turn_ins)
  const turnedIn = (q, side) => (eg.turnIns[q.id] || []).some((r) => r.faction === side);
  const give = (q, side, list, line) => {
    if (turnedIn(q, side === "Alliance" ? "Horde" : "Alliance")) { both.push(`${q.id} ${q.title}`); return; }
    q.faction = side;
    list.push(line);
  };
  for (const q of [...quests.values()].sort((a, b) => a.id - b.id)) {
    if (q.races || q.faction) continue;
    // (no NPC gives it, an item or an object does or nobody seen: the side of whom it's turned in to)
    const enders = uniq(q.ends.map((k) => actors.get(k) && actors.get(k).side).filter(Boolean));
    if (!q.starts.some((k) => k[0] === "n") && enders.length === 1) {
      give(q, enders[0], byEnder, `${q.id} ${q.title} (${q.source}: ${q.ends.map((k) => actors.get(k).name).join(", ")}, ${enders[0]})`);
      continue;
    }
    if (q.source !== "forever" || q.starts.concat(q.ends).some((k) => actors.get(k) && actors.get(k).side)) continue;
    const e = eg.quests[q.id] || {};
    const skip = new Set(q.objectives.filter((o) => o.kind === "k").map((o) => creatureName(o.id)).filter(Boolean));
    let found = named(e.objectivesText, skip);
    if (!found.length) found = named(e.description, skip);
    const sides = uniq(found.map((f) => f[1]));
    if (sides.length === 1) {
      give(q, sides[0], byText, `${q.id} ${q.title}: ${uniq(found.map((f) => f[0])).join(", ")} (${sides[0]})`);
    } else if (!sides.length && q.zone && (allianceMaps.has(q.zone) || hordeMaps.has(q.zone))) {
      const side = allianceMaps.has(q.zone) ? "Alliance" : "Horde";
      give(q, side, byZone, `${q.id} ${q.title} (${world.ui.get(q.zone).name}: ${side})`);
    }
  }
  console.log(`left to both sides as players of the other one turned them in (EG Link's turn_ins): ${both.length}${both.length ? ": " + both.join("; ") : ""}`);
  console.log(`side from the ender (no NPC giver): ${byEnder.length} (${byEnder.filter((s) => s.endsWith("Alliance)")).length} Alliance, ${byEnder.filter((s) => s.includes("(classic:")).length} classic), e.g. ${byEnder.slice(0, 12).join("; ")}`);
  console.log(`side from an NPC named in the text: ${byText.length} (${byText.filter((s) => s.endsWith("(Alliance)")).length} Alliance), e.g. ${byText.slice(0, 12).join("; ")}`);
  console.log(`side from the zone: ${byZone.length} (${byZone.filter((s) => s.endsWith("Alliance)")).length} Alliance), e.g. ${byZone.slice(0, 12).join("; ")}`);
  return { byEnder, byText, byZone, both };
}

// Quests only takeable while their holiday or event is on (Q.IsEvent, flag e): a holiday's quest sort
// (QuestSort's name: Seasonal, Lunar Festival, Midsummer, Darkmoon Faire, ...; classic-db's ZoneOrSort,
// EG Link's categoryId), a holiday's quest in classic-db's game_event_quest, or one whose every giver
// stands only while a holiday is on (game_event_creature / _gameobject); then a quest that needs one of
// those and whose givers stand only then or nowhere (Children's Week's orphans).
function markEvents(quests, eg, sql, sortName, creatures) {
  const holidaySort = (id) => id > 0 && HOLIDAY.test(sortName.get(id) || "");
  const events = new Map(rows(sql, "game_event").map((e) => [e.entry, e]));
  const holiday = (id) => {
    const e = events.get(id);
    if (!e) return false;
    if (e.holiday > 0 || HOLIDAY.test(e.description || "")) return true;
    return e.linkedTo > 0 && events.has(e.linkedTo) && (events.get(e.linkedTo).holiday > 0 || HOLIDAY.test(events.get(e.linkedTo).description || ""));
  };
  const eventQuests = new Set(rows(sql, "game_event_quest").filter((r) => holiday(r.event)).map((r) => r.quest));
  // Every spawn of each giver: false when one stands outside a holiday.
  const spawnEvent = new Map(); // guid key -> event
  for (const r of rows(sql, "game_event_creature")) spawnEvent.set("n" + r.guid, r.event);
  for (const r of rows(sql, "game_event_gameobject")) spawnEvent.set("o" + r.guid, r.event);
  const onlyHoliday = new Map(); // "n123" -> true (every spawn a holiday's) / false
  const note = (key, guid) => {
    const ev = spawnEvent.get(key[0] + guid);
    const yes = ev > 0 && holiday(ev);
    onlyHoliday.set(key, (onlyHoliday.has(key) ? onlyHoliday.get(key) : true) && yes);
  };
  const byGuid = new Map(creatures.map((r) => [r.guid, r]));
  for (const r of creatures) if (r.id) note("n" + r.id, r.guid);
  for (const r of rows(sql, "creature_spawn_entry")) if (byGuid.has(r.guid)) note("n" + r.entry, r.guid);
  for (const r of rows(sql, "gameobject")) note("o" + r.id, r.guid);
  const why = { sort: [], event: [], giver: [], follow: [] };
  const mark = (q, kind) => { q.event = true; why[kind].push(`${q.id} ${q.title}`); };
  const givers = (q) => q.starts.filter((k) => k[0] !== "i");
  for (const q of [...quests.values()].sort((a, b) => a.id - b.id)) {
    const e = eg.quests[q.id];
    if (holidaySort(-q.zoneOrSort) || (e && holidaySort(e.categoryId))) mark(q, "sort");
    else if (eventQuests.has(q.id)) mark(q, "event");
    else if (givers(q).length && givers(q).every((k) => onlyHoliday.get(k) === true)) mark(q, "giver");
  }
  // What needs an event quest, with no giver standing outside it; what a giver that stands nowhere
  // (summoned: an orphan) gives besides an event quest.
  const gives = new Map(); // giver -> its quests
  for (const q of quests.values()) for (const k of givers(q)) (gives.get(k) || gives.set(k, []).get(k)).push(q);
  const isEvent = (id) => quests.has(id) && quests.get(id).event;
  for (let changed = true; changed;) {
    changed = false;
    for (const q of [...quests.values()].sort((a, b) => a.id - b.id)) {
      if (q.event || q.source !== "classic" || givers(q).some((k) => onlyHoliday.get(k) === false)) continue;
      const needs = (q.pre || []).some(isEvent) || (q.preAny && q.preAny.length && q.preAny.every(isEvent));
      const summoned = givers(q).length && givers(q).every((k) => !onlyHoliday.has(k) && gives.get(k).some((o) => o.event));
      if (!needs && !summoned) continue;
      mark(q, "follow");
      changed = true;
    }
  }
  const n = Object.values(why).reduce((s, l) => s + l.length, 0);
  console.log(`event quests: ${n} (holiday sorts ${why.sort.length}, game_event_quest ${why.event.length}, givers only at a holiday ${why.giver.length}, follow-ups ${why.follow.length})`);
  for (const kind of ["event", "giver", "follow"]) console.log(`  ${kind}: ${why[kind].slice(0, 40).join("; ")}`);
  return why;
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
  const tables = ["UiMap", "UiMapAssignment", "AreaTable", "Map", "QuestSort", "FactionTemplate", "QuestV2",
    "QuestLineXQuest", "ItemSparse", "QuestPOIBlob", "ChrRaces", "QuestXP"];
  const t = {};
  for (const name of tables) t[name] = await table(name, build, o.cache);
  const eg = await eglink(build, o.eglink, o.cache);
  console.log(`EG Link ${eg.ref.slice(0, 7)} (${eg.build}): ${Object.keys(eg.quests).length} quests`);
  const sql = await readDump(o.dump, o.cache);

  const world = worldMaps(t);
  const races = raceModel(t.ChrRaces);
  console.log(`races: ${races.list.map((r) => `${r.name} (${r.id}, bit ${r.bit}, ${r.faction})`).join(", ")}`);
  const NEW = foreverIds("ns.FOREVER_QUEST_IDS");
  const clientQuests = new Set(t.QuestV2.map((r) => +r.ID));
  const sortName = new Map(t.QuestSort.map((r) => [+r.ID, r.SortName_lang]));
  const templates = new Map(t.FactionTemplate.map((r) => [+r.ID, r]));
  const itemName = new Map(), itemStarts = new Map();
  for (const r of t.ItemSparse) {
    itemName.set(+r.ID, r.Display_lang);
    if (+r.StartQuestID) itemStarts.set(+r.StartQuestID, (itemStarts.get(+r.StartQuestID) || []).concat(+r.ID));
  }

  // --- classic-db
  const qt = rows(sql, "quest_template");
  const cq = new Map(qt.map((q) => [q.entry, q]));
  const creatureT = new Map(rows(sql, "creature_template").map((c) => [c.Entry, c]));
  const objectT = new Map(rows(sql, "gameobject_template").map((g) => [g.entry, g]));
  const relations = (name, kind, into) => {
    for (const r of rows(sql, name)) {
      if (!into.has(r.quest)) into.set(r.quest, []);
      into.get(r.quest).push(kind + r.id);
    }
  };
  const starts = new Map(), ends = new Map();
  relations("creature_questrelation", "n", starts);
  relations("gameobject_questrelation", "o", starts);
  relations("creature_involvedrelation", "n", ends);
  relations("gameobject_involvedrelation", "o", ends);
  for (const it of rows(sql, "item_template")) {
    if (it.startquest) {
      if (!starts.has(it.startquest)) starts.set(it.startquest, []);
      starts.get(it.startquest).push("i" + it.entry);
    }
    if (!itemName.has(it.entry)) itemName.set(it.entry, it.name);
  }
  const spawns = new Map(); // "n123" / "o123" -> [[map, x, y, z]]
  const addSpawn = (key, r) => {
    if (!spawns.has(key)) spawns.set(key, []);
    spawns.get(key).push([r.map, r.position_x, r.position_y, r.position_z]);
  };
  const creatures = rows(sql, "creature");
  const byGuid = new Map(creatures.map((r) => [r.guid, r]));
  for (const r of creatures) if (r.id) addSpawn("n" + r.id, r);
  for (const r of rows(sql, "creature_spawn_entry")) if (byGuid.has(r.guid)) addSpawn("n" + r.entry, byGuid.get(r.guid));
  for (const r of rows(sql, "gameobject")) addSpawn("o" + r.id, r);
  console.log(`classic: ${cq.size} quests, ${creatures.length} creature spawns`);

  // --- which quests
  const quests = new Map(); // id -> the fields below
  const dropped = { unused: 0, client: 0, nobody: 0 };
  let levelsChanged = 0;
  for (const q of qt) {
    const id = q.entry;
    if (UNUSED.test(q.Title)) { dropped.unused++; continue; }
    if (!clientQuests.has(id) && !(q.SpecialFlags & 1)) { dropped.client++; continue; }
    if (!starts.has(id) && !ends.has(id)) { dropped.nobody++; continue; }
    // (levels: Forever's server's where EG Link has the quest; -1 and 0 scale to the player)
    const e = eg.quests[id];
    const level = e && Number.isInteger(e.level) ? e.level : q.QuestLevel;
    if (e && (e.level !== q.QuestLevel || (e.minLevel > 0 && e.minLevel !== q.MinLevel))) levelsChanged++;
    quests.set(id, {
      id, title: q.Title.trim(), level: level > 0 ? level : undefined, scales: level <= 0,
      minLevel: (e && e.minLevel > 0 ? e.minLevel : q.MinLevel) || undefined,
      races: races.expand(q.RequiredRaces & CLASSIC_RACES), classes: q.RequiredClasses || undefined,
      zoneOrSort: q.ZoneOrSort, skill: q.RequiredSkill ? `${q.RequiredSkill}:${q.RequiredSkillValue}` : undefined,
      rep: q.RequiredMinRepFaction ? `${q.RequiredMinRepFaction}:${q.RequiredMinRepValue}` : undefined,
      repeatable: (q.SpecialFlags & 1) !== 0, isNew: NEW.has(id), source: "classic",
      starts: uniq(starts.get(id) || []), ends: uniq(ends.get(id) || []),
      breadcrumbFor: q.BreadcrumbForQuestId || undefined,
    });
  }

  // --- Forever's quests (EG Link and the client), for what classic-db doesn't have
  const egOffers = new Map(), egTakes = new Map(), egNpc = new Map();
  for (const [kind, letter] of [["npcs", "n"], ["objects", "o"]]) {
    for (const [nid, r] of Object.entries(eg.npcs[kind] || {})) {
      egNpc.set(letter + nid, r);
      for (const qid of Object.keys(r.offers || {})) egOffers.set(+qid, (egOffers.get(+qid) || []).concat(letter + nid));
      for (const qid of Object.keys(r.takes || {})) egTakes.set(+qid, (egTakes.get(+qid) || []).concat(letter + nid));
    }
  }
  const lineOf = new Map(); // quest -> [line, order]
  const lines = new Map();
  for (const r of t.QuestLineXQuest) {
    const line = +r.QuestLineID;
    if (!lines.has(line)) lines.set(line, []);
    lines.get(line).push([+r.OrderIndex, +r.QuestID]);
  }
  for (const list of lines.values()) list.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  const poiMap = new Map(); // quest -> uiMap (the most blobs)
  {
    const count = new Map();
    for (const r of t.QuestPOIBlob) {
      const u = world.ui.get(+r.UiMapID);
      if (!u || u.type !== 3) continue;
      const k = `${r.QuestID}:${r.UiMapID}`;
      count.set(k, (count.get(k) || 0) + 1);
    }
    for (const [k, n] of [...count.entries()].sort()) {
      const [q, u] = k.split(":").map(Number);
      const had = poiMap.get(q);
      if (!had || n > had[1] || (n === had[1] && u < had[0])) poiMap.set(q, [u, n]);
    }
  }
  let foreverCount = 0;
  for (const [sid, e] of Object.entries(eg.quests).sort((a, b) => a[0] - b[0])) {
    const id = +sid;
    if (quests.has(id) || cq.has(id)) continue; // classic-db's
    const offered = egOffers.has(id) || egTakes.has(id);
    if (!NEW.has(id) && !offered) continue; // later classic content nobody was seen being offered
    if (!e.title || UNUSED.test(e.title) || /\(\d+\)aa$/.test(e.title)) continue;
    const flags = Number(e.flags) || 0;
    const startList = (egOffers.get(id) || []).slice();
    if (e.startItemId) startList.push("i" + e.startItemId);
    for (const item of itemStarts.get(id) || []) startList.push("i" + item);
    quests.set(id, {
      id, title: e.title.trim(), level: e.level > 0 ? e.level : undefined, scales: Number.isInteger(e.level) && e.level <= 0,
      minLevel: e.minLevel > 0 ? e.minLevel : undefined,
      races: races.expand(races.fromHex(String(e.raceMask || ""))), classes: undefined,
      zoneOrSort: e.zoneAreaId || (e.categoryId ? -e.categoryId : 0), poi: poiMap.has(id) ? poiMap.get(id)[0] : undefined,
      repeatable: (flags & 0x1000) !== 0 || (flags & 0x8000) !== 0, isNew: NEW.has(id), source: "forever",
      starts: uniq(startList), ends: uniq(egTakes.get(id) || []),
      egNext: e.nextQuestId || undefined,
    });
    foreverCount++;
  }
  // New quests EG Link hasn't described, which the client puts in a quest line or starts with an item.
  for (const list of lines.values()) for (const [, id] of list) lineOf.set(id, list);
  for (const id of [...NEW].sort(byNumber)) {
    if (quests.has(id)) continue;
    const items = itemStarts.get(id);
    if (!lineOf.has(id) && !items) continue;
    quests.set(id, {
      id, title: undefined, zoneOrSort: 0, poi: poiMap.has(id) ? poiMap.get(id)[0] : undefined, isNew: true, source: "forever",
      starts: uniq((items || []).map((i) => "i" + i)), ends: [], repeatable: false,
    });
    foreverCount++;
  }
  // Classic quests nobody in classic-db gives or takes, which players were seen being offered.
  for (const q of quests.values()) {
    if (q.source !== "classic") continue;
    if (!q.starts.length && egOffers.has(q.id)) q.starts = uniq(egOffers.get(q.id));
    if (!q.ends.length && egTakes.has(q.id)) q.ends = uniq(egTakes.get(q.id));
  }

  // --- zones, sorts, dungeons
  const zoneQuests = new Map(); // uiMap -> quest ids
  for (const q of quests.values()) {
    const zs = q.zoneOrSort;
    if (zs > 0) {
      const area = world.areas.get(zs);
      const inst = world.instanceArea.get(zs) || (area && world.instance.get(area.map));
      if (inst && inst.type >= 1 && inst.type <= 3) {
        q.dungeon = inst.name;
      } else {
        q.zone = world.uiOfArea(zs);
        if (!q.zone && area) q.zoneName = area.name;
      }
    } else if (zs < 0) {
      q.sort = sortName.get(-zs);
    }
    if (!q.zone && !q.dungeon && q.poi) q.zone = q.poi;
  }

  // --- the NPCs, objects and items in the data, with their places
  const used = new Set();
  for (const q of quests.values()) for (const k of q.starts.concat(q.ends)) used.add(k);
  const preferOf = new Map(); // NPC -> its quests' zones, the most first
  for (const q of quests.values()) {
    if (!q.zone) continue;
    for (const k of q.starts.concat(q.ends)) {
      if (!preferOf.has(k)) preferOf.set(k, new Map());
      preferOf.get(k).set(q.zone, (preferOf.get(k).get(q.zone) || 0) + 1);
    }
  }
  const actors = new Map(); // key -> { name, points: [[[ui, x, y], alternatives...]], side }
  let ambiguous = 0;
  for (const key of [...used].sort()) {
    const kind = key[0], id = +key.slice(1);
    const actor = { name: undefined, points: [] };
    if (kind === "i") {
      actor.name = itemName.get(id);
    } else {
      const tmpl = kind === "n" ? creatureT.get(id) : objectT.get(id);
      const egr = egNpc.get(key);
      actor.name = tmpl ? (kind === "n" ? tmpl.Name : tmpl.name) : egr && egr.name;
      if (kind === "n") actor.side = tmpl ? sideOf(templates, tmpl.Faction) : undefined;
      if (!actor.side && egr && (egr.side === "Alliance" || egr.side === "Horde")) actor.side = egr.side;
      const prefer = [...(preferOf.get(key) || new Map()).entries()].sort((a, b) => b[1] - a[1] || a[0] - b[0]).map((e) => e[0]);
      const grid = new Set();
      const add = (list) => {
        if (actor.points.length >= MAX_POINTS) return;
        const k = `${list[0][0]}:${Math.floor(list[0][1] / 10)}:${Math.floor(list[0][2] / 10)}`;
        if (grid.has(k)) return;
        grid.add(k);
        actor.points.push(list);
        if (list.length > 1) ambiguous++;
      };
      const sp = (spawns.get(key) || []).slice().sort((a, b) => a[0] - b[0] || a[1] - b[1] || a[2] - b[2]);
      for (const [m, x, y, z] of sp) {
        const p = places(world, m, x, y, z, prefer);
        if (p.length) add(p);
      }
      if (!actor.points.length && egr) {
        for (const pos of (egr.positions || []).slice().sort((a, b) => a.uiMap - b.uiMap || a.mapX - b.mapX || a.mapY - b.mapY)) {
          const u = world.ui.get(pos.uiMap);
          if (!u || !(u.type in ZONE_TYPES)) continue;
          add([[pos.uiMap, Math.round(pos.mapX * 1000), Math.round(pos.mapY * 1000)]]);
        }
      }
    }
    actors.set(key, actor);
  }

  // Zones, faction for quests without one, from their givers. A Forever quest filed under a city (its
  // server's quest log header) where neither its giver nor its ender stands goes to its giver's zone
  // (Never Coming Back: given and done in Ashenvale, filed under Thunder Bluff). One filed under a zone
  // stays: a city's quest for that zone (Beasts of Thunder Ridge, given in Orgrimmar) is that zone's.
  let moved = 0;
  for (const q of quests.values()) {
    if (q.source === "forever" && q.zone && world.ui.get(q.zone) && world.ui.get(q.zone).city) {
      const zonesOf = (keys) => keys.flatMap((k) => (actors.get(k) ? actors.get(k).points : []).flat().map((p) => p[0]));
      const giver = zonesOf(q.starts.filter((k) => k[0] !== "i")), ender = zonesOf(q.ends);
      if (giver.length && !giver.includes(q.zone) && !ender.includes(q.zone)) {
        q.zone = giver[0];
        moved++;
      }
    }
    if (!q.zone && !q.dungeon) {
      for (const k of q.starts.concat(q.ends)) {
        const a = actors.get(k);
        if (a && a.points.length) { q.zone = a.points[0][0][0]; break; }
      }
    }
    q.faction = races.faction(q.races);
    if (!q.faction && !q.races) {
      const sides = uniq(q.starts.filter((k) => k[0] === "n").map((k) => actors.get(k).side));
      if (sides.length === 1 && sides[0]) q.faction = sides[0];
    }
  }
  console.log(`Forever quests moved to their giver's zone: ${moved}`);

  // --- objectives and rewards (EG Link's, what Forever's server says, for the quests it has; else classic-db's)
  const xpRows = new Map(t.QuestXP.map((r) => [+r.ID, r]));
  // (the money players got on turn-in below level 60, the most often seen; at 60 experience is paid as money)
  const paidOf = (id) => {
    const seen = new Map();
    for (const r of eg.turnIns[id] || []) if (r.level < 60 && Number.isFinite(r.money)) seen.set(r.money, (seen.get(r.money) || 0) + 1);
    return [...seen].sort((a, b) => b[1] - a[1] || a[0] - b[0]).map((x) => x[0])[0];
  };
  for (const q of quests.values()) {
    const e = eg.quests[q.id], c = q.source === "classic" ? cq.get(q.id) : undefined;
    q.objectives = objectivesOf(e, c);
    // (an item the giver hands over to bring somewhere: classic's SrcItemId)
    for (const o of q.objectives) if (o.kind === "i" && c && c.SrcItemId === o.id) o.provided = true;
    q.rewards = rewardsOf(e, c, (level) => xpRows.get(level), e ? paidOf(q.id) : undefined);
  }

  // --- where the items that start quests or are collected for one drop
  const starterZones = new Map(); // item -> its quests' zones (where its sources' spawns are preferred)
  const addItemZone = (item, zone) => {
    if (!starterZones.has(item)) starterZones.set(item, new Set());
    if (zone) starterZones.get(item).add(zone);
  };
  let starterItems = 0;
  for (const q of quests.values()) {
    for (const k of q.starts) if (k[0] === "i") addItemZone(+k.slice(1), q.zone);
  }
  starterItems = starterZones.size;
  for (const q of quests.values()) {
    for (const o of q.objectives) {
      if (o.kind !== "i") continue;
      addItemZone(o.id, q.zone);
      if (!actors.has("i" + o.id)) actors.set("i" + o.id, { name: itemName.get(o.id), points: [] });
    }
  }
  const dropsOf = new Map(); // item -> Map(source key -> chance 0..1)
  const addDrop = (item, key, p) => {
    if (!(p > 0)) return;
    if (!dropsOf.has(item)) dropsOf.set(item, new Map());
    const m = dropsOf.get(item);
    m.set(key, Math.max(m.get(key) || 0, p));
  };
  {
    const lootRows = rows(sql, "creature_loot_template"), objectRows = rows(sql, "gameobject_loot_template");
    const refRows = rows(sql, "reference_loot_template");
    const refs = byEntry(refRows), users = referenceUsers(lootRows, objectRows, refRows);
    const owners = (templates, lootOf) => {
      const m = new Map();
      for (const [id, tmpl] of templates) {
        const loot = lootOf(tmpl);
        if (loot > 0) (m.get(loot) || m.set(loot, []).get(loot)).push(id);
      }
      return m;
    };
    // (chests and fishing holes keep their loot in data1)
    for (const [letter, list, byLoot] of [
      ["n", lootRows, owners(creatureT, (c) => c.LootId)],
      ["o", objectRows, owners(objectT, (g) => (g.type === 3 || g.type === 25 ? g.data1 : 0))],
    ]) {
      for (const [loot, entries] of byEntry(list)) {
        const who = byLoot.get(loot);
        if (!who || !entries.some((r) => r.mincountOrRef < 0 || starterZones.has(r.item))) continue;
        for (const [item, v] of chances(entries, refs, users, 0)) {
          if (starterZones.has(item)) for (const id of who) addDrop(item, letter + id, Math.min(1, v.p));
        }
      }
    }
  }
  // EG Link's loot, for items classic-db has no source of (Forever's own): "npc:<id>[|...]".
  const egLootPoints = new Map(); // source key -> [[ui, x, y]]
  const egItems = new Set();
  {
    const egDrops = new Map(); // item -> Map(key -> [drops, windows])
    for (const [skey, s] of Object.entries(eg.loot).sort((a, b) => (a[0] < b[0] ? -1 : 1))) {
      const m = skey.match(/^(npc|object):(\d+)/);
      if (!m) continue;
      const key = (m[1] === "npc" ? "n" : "o") + m[2];
      for (const [sitem, v] of Object.entries(s.items || {})) {
        const item = +sitem;
        if (!starterZones.has(item) || dropsOf.has(item)) continue;
        if (!egDrops.has(item)) egDrops.set(item, new Map());
        const had = egDrops.get(item).get(key) || [0, 0];
        egDrops.get(item).set(key, [had[0] + (Number(v.drops) || 0), had[1] + (Number(s.windows) || 0)]);
        for (const pos of s.positions || []) {
          const u = world.ui.get(pos.uiMap);
          if (!u || !(u.type in ZONE_TYPES)) continue;
          (egLootPoints.get(key) || egLootPoints.set(key, []).get(key)).push([pos.uiMap, Math.round(pos.mapX * 1000), Math.round(pos.mapY * 1000)]);
        }
      }
    }
    for (const [item, m] of egDrops) for (const [key, [drops, windows]] of m) addDrop(item, key, windows > 0 ? Math.min(1, drops / windows) : 0);
    for (const item of egDrops.keys()) if (dropsOf.has(item)) egItems.add(item);
  }
  // The sources' places: their spawns (EG Link's loot spots, its NPCs' places), in clusters.
  const sources = new Map(); // key -> { name, points: [{ ui, x, y, r }], spawns }
  const sourceOf = (key, prefer) => {
    if (sources.has(key)) return sources.get(key);
    const kind = key[0], id = +key.slice(1);
    const tmpl = kind === "n" ? creatureT.get(id) : objectT.get(id);
    const egr = egNpc.get(key);
    const name = tmpl ? (kind === "n" ? tmpl.Name : tmpl.name) : (egr && egr.name) || (kind === "n" && eg.creatures[id] && eg.creatures[id].name)
      || (kind === "o" && eg.objects[id] && eg.objects[id].name) || undefined;
    let pts = [];
    for (const [m, x, y, z] of spawns.get(key) || []) {
      const p = places(world, m, x, y, z, prefer);
      if (p.length) pts.push(p[0]);
    }
    if (!pts.length) pts = egLootPoints.get(key) || [];
    // (where players met Forever's own creatures)
    if (!pts.length && kind === "n" && eg.creatures[id]) {
      for (const pos of eg.creatures[id].positions || []) {
        const u = world.ui.get(pos.uiMap);
        if (u && u.type in ZONE_TYPES) pts.push([pos.uiMap, Math.round(pos.mapX * 1000), Math.round(pos.mapY * 1000)]);
      }
    }
    if (!pts.length && egr) {
      for (const pos of egr.positions || []) {
        const u = world.ui.get(pos.uiMap);
        if (u && u.type in ZONE_TYPES) pts.push([pos.uiMap, Math.round(pos.mapX * 1000), Math.round(pos.mapY * 1000)]);
      }
    }
    // (spawned: it stands somewhere, on a map or in an instance without one)
    const s = { name, points: clusters(pts), spawns: pts.length, spawned: pts.length > 0 || (spawns.get(key) || []).length > 0 };
    sources.set(key, s);
    return s;
  };
  const itemDrops = new Map(); // item -> [[key, chance 0..1]]
  for (const [item, m] of [...dropsOf].sort((a, b) => a[0] - b[0])) {
    const prefer = [...starterZones.get(item)].sort(byNumber);
    // (with places first, then those in its quests' zones, then the likeliest)
    const here = (s) => s.points.some((c) => prefer.includes(c.ui));
    const list = [...m].map(([key, p]) => ({ key, p, s: sourceOf(key, prefer) }))
      .sort((a, b) => (b.s.spawns > 0) - (a.s.spawns > 0) || here(b.s) - here(a.s) || b.p - a.p || b.s.spawns - a.s.spawns || (a.key < b.key ? -1 : 1))
      .slice(0, MAX_SOURCES);
    itemDrops.set(item, list.map((d) => [d.key, d.p]));
  }
  const usedSources = new Set();
  for (const list of itemDrops.values()) for (const [key] of list) usedSources.add(key);
  // Creatures to kill and objects to use: their spawns, as drop sources' (shared with them).
  for (const q of [...quests.values()].sort((a, b) => a.id - b.id)) {
    for (const o of q.objectives) {
      if (o.kind === "i") continue;
      const key = (o.kind === "k" ? "n" : "o") + o.id;
      sourceOf(key, q.zone ? [q.zone] : []);
      usedSources.add(key);
    }
  }

  // --- the levels of what a quest makes you fight (field mobs), whether it's for a group (flag g)
  const levelOfCreature = creatureLevels(creatureT, eg.creatures, templates);
  // An item to collect: the easiest of the creatures it's likely to drop from (of all its sources, those with
  // MIN_CHANCE or more, or a quarter of the likeliest one's chance; that stand somewhere, not summoned ones); none when
  // an object is among them (it can be gathered), it drops from very many
  // (MANY_SOURCES: cloth, herbs, a world drop's pages: from whatever is around) or rarely (made, bought).
  const itemFight = (item, side, zone) => {
    const all = dropsOf.get(item);
    if (!all || all.size > MANY_SOURCES) return undefined;
    const best = Math.max(0, ...all.values());
    let likely = [...all].filter(([, p]) => p >= Math.min(best / 4, MIN_CHANCE));
    if (best < RARE_CHANCE || likely.some(([key]) => key[0] !== "n")) return undefined;
    likely = likely.filter(([key]) => sourceOf(key, zone ? [zone] : []).spawned);
    let easiest;
    for (const [key] of likely) {
      const lv = levelOfCreature(+key.slice(1), side);
      if (lv && (!easiest || lv[0] < easiest[0] || (lv[0] === easiest[0] && lv[1] < easiest[1]))) easiest = lv;
    }
    return easiest;
  };
  const mobStats = { quests: 0, above: [0, 0, 0], group: 0, far: 0 };
  for (const q of quests.values()) {
    const fight = [];
    for (const o of q.objectives) {
      const lv = o.kind === "k" ? levelOfCreature(o.id, q.faction) : o.kind === "i" && !o.provided ? itemFight(o.id, q.faction, q.zone) : undefined;
      if (lv) fight.push(lv);
    }
    q.mobs = mobLevelsOf(fight);
    // (mobs far above the quest's own level aren't its: a drop source somewhere else, The Dormant Shade's candle)
    if (q.mobs && q.level && q.mobs[0] > q.level + MOB_GAP) { q.mobs = undefined; mobStats.far++; }
    if (q.mobs) {
      mobStats.quests++;
      if (q.level && q.mobs[0] > q.level) mobStats.above[Math.min(3, q.mobs[0] - q.level) - 1]++;
    }
    // (EG Link's type for a quest it has: Forever's server's; else classic-db's)
    const e = eg.quests[q.id], c = q.source === "classic" ? cq.get(q.id) : undefined;
    q.group = GROUP_TYPES.has(e ? Number(e.questInfoId) || 0 : c ? c.Type : 0);
    if (q.group) mobStats.group++;
  }
  console.log(`mob levels: ${mobStats.quests} quests, their mobs above their level by 1: ${mobStats.above[0]}, 2: ${mobStats.above[1]}, 3 or more: ${mobStats.above[2]}, more than ${MOB_GAP} (left out): ${mobStats.far}; for a group: ${mobStats.group}`);

  // --- the chains
  const prev = new Map(); // quest -> signed previous quests
  const addPrev = (q, p) => { if (!prev.has(q)) prev.set(q, []); if (!prev.get(q).includes(p)) prev.get(q).push(p); };
  const groups = new Map();
  for (const c of qt) {
    if (!quests.has(c.entry)) continue;
    if (c.PrevQuestId && quests.has(Math.abs(c.PrevQuestId))) addPrev(c.entry, c.PrevQuestId);
    if (c.NextQuestId && quests.has(Math.abs(c.NextQuestId))) addPrev(Math.abs(c.NextQuestId), c.NextQuestId < 0 ? -c.entry : c.entry);
    if (c.ExclusiveGroup) {
      if (!groups.has(c.ExclusiveGroup)) groups.set(c.ExclusiveGroup, []);
      groups.get(c.ExclusiveGroup).push(c.entry);
    }
  }
  const leads = new Map(); // quest -> quests it leads to without being needed
  const addLead = (a, b) => { if (!leads.has(a)) leads.set(a, new Set()); leads.get(a).add(b); };
  for (const c of qt) {
    if (!quests.has(c.entry)) continue;
    if (c.NextQuestInChain && quests.has(c.NextQuestInChain)) addLead(c.entry, c.NextQuestInChain);
    if (c.BreadcrumbForQuestId && quests.has(c.BreadcrumbForQuestId)) addLead(c.entry, c.BreadcrumbForQuestId);
  }
  // Forever's: EG Link's next quest (the ender offers it: needed, unless the next one's record of what
  // every character had done before says otherwise), quest lines, and a lone earlier quest of the
  // same zone in that record.
  let egPre = 0, linePre = 0, beforePre = 0;
  const before = (id) => {
    const p = eg.prerequisites[id];
    return p && p.characters >= 2 ? new Set(p.before) : null;
  };
  for (const q of [...quests.values()].sort((a, b) => a.id - b.id)) {
    if (q.source !== "forever" || !q.egNext || !quests.has(q.egNext) || q.egNext === q.id) continue;
    addLead(q.id, q.egNext);
    const next = quests.get(q.egNext);
    if (next.source !== "forever" || prev.has(next.id) && prev.get(next.id).some((p) => quests.get(Math.abs(p)).source === "classic")) continue;
    const b = before(next.id);
    if (!b || b.has(q.id)) { addPrev(next.id, q.id); egPre++; }
  }
  for (const list of [...lines.values()]) {
    for (let i = 1; i < list.length; i++) {
      const a = list[i - 1][1], b = list[i][1];
      if (!quests.has(a) || !quests.has(b) || a === b) continue;
      addLead(a, b);
      if (!prev.has(b)) { addPrev(b, a); linePre++; }
    }
  }
  for (const q of [...quests.values()].sort((a, b) => a.id - b.id)) {
    if (q.source !== "forever" || prev.has(q.id)) continue;
    const p = eg.prerequisites[q.id];
    if (!p || p.characters < 3) continue;
    const zone = (id) => quests.has(id) && (quests.get(id).zone || quests.get(id).dungeon);
    let cand = p.before.filter((b) => b !== q.id && NEW.has(b) && quests.has(b) && zone(b) && zone(b) === zone(q.id));
    // Only the latest of them: one another of them needed first isn't direct.
    cand = cand.filter((c) => !cand.some((d) => d !== c && eg.prerequisites[d] && eg.prerequisites[d].before.includes(c)));
    if (cand.length === 1) { addPrev(q.id, cand[0]); addLead(cand[0], q.id); beforePre++; }
  }

  const groupOf = new Map();
  for (const [g, list] of groups) for (const id of list) groupOf.set(id, g);
  for (const q of quests.values()) {
    const list = prev.get(q.id) || [];
    const pos = list.filter((p) => p > 0).sort(byNumber), neg = list.filter((p) => p < 0).map((p) => -p).sort(byNumber);
    const allOf = (p) => (groupOf.get(p) < 0 ? groups.get(groupOf.get(p)).filter((x) => quests.has(x)).sort(byNumber) : [p]);
    if (pos.length === 1) q.pre = allOf(pos[0]);
    else if (pos.length > 1) {
      const g = groupOf.get(pos[0]);
      if (g < 0 && pos.every((p) => groupOf.get(p) === g)) q.pre = allOf(pos[0]);
      else q.preAny = pos;
    }
    if (neg.length) q.preActive = neg[0];
    const g = groupOf.get(q.id);
    if (g > 0) {
      const others = groups.get(g).filter((x) => x !== q.id && quests.has(x)).sort(byNumber);
      if (others.length) q.excl = others;
    }
  }
  // opens: the reverse of what each quest needs, and what it leads to.
  const opens = new Map();
  const addOpen = (a, b) => { if (a !== b && quests.has(a) && quests.has(b)) { if (!opens.has(a)) opens.set(a, new Set()); opens.get(a).add(b); } };
  for (const q of quests.values()) {
    for (const p of (q.pre || []).concat(q.preAny || [], q.preActive ? [q.preActive] : [])) addOpen(p, q.id);
  }
  for (const [a, set] of leads) for (const b of set) addOpen(a, b);
  const levelOf = (id) => quests.get(id).level || quests.get(id).minLevel || 0;
  for (const [a, set] of opens) quests.get(a).opens = [...set].sort((x, y) => levelOf(x) - levelOf(y) || x - y);

  // --- the side of Forever's quests nothing else gives one (after their objectives: a creature to kill isn't the giver)
  const textSides = sideFromText(quests, eg, actors, creatureT, egNpc, templates, world);

  // --- event quests: only takeable while their holiday is on (flag e)
  markEvents(quests, eg, sql, sortName, creatures);

  // --- names, zones, dungeons
  const names = new Set();
  for (const q of quests.values()) {
    if (q.sort) names.add(q.sort);
    if (q.dungeon) names.add(q.dungeon);
    if (!q.zone && q.zoneName) names.add(q.zoneName);
  }
  const nameList = [...names].sort();
  const nameIndex = new Map(nameList.map((n, i) => [n, i + 1]));
  const sortQ = (list) => list.sort((a, b) => levelOf(a) - levelOf(b) || a - b);
  // A zone's levels: its own quests' (not class or profession quests), the lowest and highest tenth left
  // out (a city's few quests for level 60).
  const range = (ids) => {
    const own = ids.filter((id) => !quests.get(id).sort && !quests.get(id).event);
    const levels = (own.length ? own : ids).map(levelOf).filter((l) => l > 0).sort(byNumber);
    if (!levels.length) return [0, 0];
    const cut = levels.length >= 10 ? Math.floor(levels.length / 10) : 0;
    return [levels[cut], levels[levels.length - 1 - cut]];
  };
  for (const q of quests.values()) if (q.zone) (zoneQuests.get(q.zone) || zoneQuests.set(q.zone, []).get(q.zone)).push(q.id);
  const dungeonQuests = new Map();
  for (const q of quests.values()) if (q.dungeon) (dungeonQuests.get(q.dungeon) || dungeonQuests.set(q.dungeon, []).get(q.dungeon)).push(q.id);
  // Quests given in a zone that are listed elsewhere (a dungeon's at its town, another zone's).
  const givenIn = new Map();
  for (const q of quests.values()) {
    const maps = new Set();
    for (const k of q.starts) if (k[0] !== "i") for (const list of actors.get(k).points) maps.add(list[0][0]);
    for (const m of maps) if (zoneQuests.has(m) && q.zone !== m) (givenIn.get(m) || givenIn.set(m, []).get(m)).push(q.id);
  }
  // Who starts and ends what.
  const questsOf = new Map(); // "n123" -> [[starts], [ends]]
  const role = (k, i, id) => (questsOf.get(k) || questsOf.set(k, [[], []]).get(k))[i].push(id);
  for (const id of [...quests.keys()].sort(byNumber)) {
    for (const k of quests.get(id).starts) if (k[0] !== "i") role(k, 0, id);
    for (const k of quests.get(id).ends) if (k[0] !== "i") role(k, 1, id);
  }

  // --- encoding
  const esc = (s) => String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\r?\n/g, " ");
  const ids = (list) => (list && list.length ? list.join(",") : "");
  const questLine = (q) => {
    const flags = (q.faction === "Alliance" ? "A" : q.faction === "Horde" ? "H" : "") + (q.repeatable ? "r" : "") + (q.isNew ? "n" : "") + (q.source === "forever" ? "f" : "")
      + (q.scales ? "s" : "") + (q.event ? "e" : "") + (q.group ? "g" : "");
    const r = q.rewards || {};
    const counted = (list) => (list || []).map(([id, n]) => (n > 1 ? `${id}:${n}` : `${id}`)).join(",");
    const f = [
      q.title ? q.title.replace(/\|/g, "/") : "", // (the first field: only "|" separates it)
      q.level || "", q.minLevel || "", q.races || "", q.classes || "",
      q.zone || "", !q.zone && q.zoneName ? nameIndex.get(q.zoneName) : "", q.sort ? nameIndex.get(q.sort) : "",
      q.dungeon ? nameIndex.get(q.dungeon) : "",
      ids(q.pre), ids(q.preAny), q.preActive || "", ids(q.excl), ids(q.opens), q.breadcrumbFor && quests.has(q.breadcrumbFor) ? q.breadcrumbFor : "",
      flags, q.skill || "", q.rep || "", q.starts.join(","), q.ends.join(","),
      (q.objectives || []).map((o) => `${o.kind}${o.id}${o.count > 1 ? ":" + o.count : ""}${o.provided ? "p" : ""}`).join(","),
      counted(r.choice), counted(r.items), r.money || "", r.xp || "",
      q.mobs ? (q.mobs[0] === q.mobs[1] ? `${q.mobs[0]}` : `${q.mobs[0]}:${q.mobs[1]}`) : "",
    ].map(String);
    while (f.length && f[f.length - 1] === "") f.pop();
    return f.join("|");
  };
  const cleanName = (name) => (name ? name.replace(/[|;]/g, " ") : "");
  const actorLine = (a) => `${cleanName(a.name)}|${a.points.map((list) => list.map((p) => p.join(",")).join("/")).join(";")}`;
  const sortedIds = [...quests.keys()].sort(byNumber);
  const zoneIds = [...zoneQuests.keys()].sort((a, b) => world.continentOf(a) - world.continentOf(b) || a - b);
  const actorKeys = (kind) => [...actors.keys()].filter((k) => k[0] === kind).sort((a, b) => +a.slice(1) - +b.slice(1));
  const source = `${DUMP_NAME}; EG Link ${eg.ref.slice(0, 7)} for ${eg.build} (Efficient Games, CC BY 4.0); WoW: Forever ${build} client tables (wago.tools)`;
  const lua = [
    `-- Generated by tools/update-quest-data.js: don't edit, run the tool again. Sources: ${source}.`,
    "-- quests[id] = \"title|level|minLevel|races|classes|zone|zoneName|sort|dungeon|pre|preAny|preActive|excl|opens|",
    "-- breadcrumbFor|flags|skill|rep|starts|ends|objectives|choice|items|money|xp|mobs\" (empty fields left empty, the",
    "-- last ones left out): races and classes as bit masks; zone a uiMap; zoneName, sort, dungeon an index into names;",
    "-- pre, preAny, excl, opens quest IDs (\",\"); flags: A/H faction, r repeatable, n new in WoW: Forever, f from Forever's",
    "-- data (not classic's), s its level scales to the player, e an event's (only while its holiday is on), g for a group",
    "-- (elite, dungeon, raid); mobs \"min[:max]\": the levels of the mobs its objectives make you fight (min: the highest of",
    "-- each target's lowest level, max: the highest of any); skill",
    "-- \"skill line:value\", rep \"faction:min\"; starts, ends: n<NPC>, o<object>, i<item> (\",\"); objectives k<creature",
    "-- to kill>, o<object to use>, i<item to collect>,",
    "-- \":count\" when more than one, \"p\" an item the giver hands over (the creatures' and objects' places in dropNpcs,",
    "-- dropObjects; the items' in items); choice (one of them) and items (all of them) rewards item[:count]; money in",
    "-- copper; xp the experience at the quest's level.",
    "-- npcs[id], objects[id] = \"name|map,x,y;map,x,y/map,x,y\": places (x, y in 1/1000 of the uiMap), \"/\" alternatives",
    "-- for a place where zones' rectangles overlap (the first is the best guess); items[id] = \"name|drops\": where it",
    "-- drops, \"n<NPC>:chance,o<object>:chance\" (hundredths of a percent, at most 3: with places, in its quests' zones,",
    "-- the likeliest first), the sources' and the objectives' creatures' and objects' places in dropNpcs[id],",
    "-- dropObjects[id] = \"name|map,x,y,r;...\" (clusters of spawns: centre, radius r in 1/1000 of the map's",
    "-- width, the most spawns first). npcQuests[id], objectQuests[id] = \"quests it starts|quests it ends\".",
    "-- zones[uiMap] = \"continent|minLevel|maxLevel|name|quest IDs|quests given here but listed elsewhere\";",
    "-- dungeons[names index] = \"minLevel|maxLevel|quest IDs\". races[raceID] = \"race-mask bit|A or H|name|c (classic's)\":",
    "-- Forever's playable races (a quest open to all of a side's classic races is open to all of that side's).",
    "-- GPL v3 (LICENSE.md); sources and World of Warcraft's copyright: COPYRIGHT.md.",
    "LefthyToolsQuestData = {",
    `\tsource = "${esc(source)}",`,
    `\tbuild = "${build}",`,
    "\traces = {",
    ...races.list.map((r) => `\t\t[${r.id}] = "${r.bit}|${r.faction === "Alliance" ? "A" : "H"}|${esc(r.name)}${r.classic ? "|c" : ""}",`),
    "\t},",
    "\tnames = {",
    ...nameList.map((n) => `\t\t"${esc(n)}",`),
    "\t},",
    "\tzones = {",
    ...zoneIds.map((z) => {
      const list = sortQ(zoneQuests.get(z));
      const [lo, hi] = range(list);
      const given = givenIn.has(z) ? "|" + sortQ(uniq(givenIn.get(z))).join(",") : "";
      return `\t\t[${z}] = "${world.continentOf(z)}|${lo}|${hi}|${esc(world.ui.get(z).name)}|${list.join(",")}${given}",`;
    }),
    "\t},",
    "\tdungeons = {",
    ...[...dungeonQuests.keys()].sort((a, b) => nameIndex.get(a) - nameIndex.get(b)).map((d) => {
      const list = sortQ(dungeonQuests.get(d));
      const [lo, hi] = range(list);
      return `\t\t[${nameIndex.get(d)}] = "${lo}|${hi}|${list.join(",")}",`;
    }),
    "\t},",
    "\tnpcs = {",
    ...actorKeys("n").map((k) => `\t\t[${k.slice(1)}] = "${esc(actorLine(actors.get(k)))}",`),
    "\t},",
    "\tobjects = {",
    ...actorKeys("o").map((k) => `\t\t[${k.slice(1)}] = "${esc(actorLine(actors.get(k)))}",`),
    "\t},",
    "\titems = {",
    ...actorKeys("i").map((k) => {
      const drops = (itemDrops.get(+k.slice(1)) || []).map(([key, p]) => `${key}:${Math.max(1, Math.round(p * 10000))}`).join(",");
      return `\t\t[${k.slice(1)}] = "${esc(cleanName(actors.get(k).name))}${drops ? "|" + drops : ""}",`;
    }),
    "\t},",
    ...[["dropNpcs", "n"], ["dropObjects", "o"]].flatMap(([name, letter]) => [
      `\t${name} = {`,
      ...[...usedSources].filter((k) => k[0] === letter).sort((a, b) => +a.slice(1) - +b.slice(1)).map((k) => {
        const s = sources.get(k);
        return `\t\t[${k.slice(1)}] = "${esc(cleanName(s.name))}|${s.points.map((c) => `${c.ui},${c.x},${c.y},${c.r}`).join(";")}",`;
      }),
      "\t},",
    ]),
    ...[["npcQuests", "n"], ["objectQuests", "o"]].flatMap(([name, letter]) => [
      `\t${name} = {`,
      ...[...questsOf.keys()].filter((k) => k[0] === letter).sort((a, b) => +a.slice(1) - +b.slice(1)).map((k) => {
        const [s, e] = questsOf.get(k);
        return `\t\t[${k.slice(1)}] = "${s.join(",")}${e.length ? "|" + e.join(",") : ""}",`;
      }),
      "\t},",
    ]),
    "\tquests = {",
    ...sortedIds.map((id) => `\t\t[${id}] = "${esc(questLine(quests.get(id)))}",`),
    "\t},",
    "}",
    "",
  ].join("\n");

  // --- numbers
  const all = [...quests.values()];
  const chained = all.filter((q) => q.pre || q.preAny || q.preActive || q.opens);
  const comps = (() => {
    const parent = new Map();
    const find = (a) => { while (parent.has(a) && parent.get(a) !== a) a = parent.get(a); return a; };
    const join = (a, b) => { const x = find(a), y = find(b); if (x !== y) parent.set(x, y); };
    for (const q of chained) { parent.set(q.id, parent.get(q.id) || q.id); for (const o of q.opens || []) { if (!parent.has(o)) parent.set(o, o); join(q.id, o); } }
    return new Set([...parent.keys()].map(find)).size;
  })();
  const withGiver = all.filter((q) => q.starts.some((k) => actors.get(k) && (k[0] === "i" || actors.get(k).points.length))).length;
  const newOnes = all.filter((q) => q.isNew);
  console.log(`dropped from classic-db: ${dropped.unused} unused, ${dropped.client} not in the client, ${dropped.nobody} nobody gives or takes`);
  console.log(`${quests.size} quests (${all.filter((q) => q.source === "classic").length} classic, ${foreverCount} Forever's), ${chained.length} in ${comps} chains, ${withGiver} with a giver on the map or an item`);
  console.log(`new in Forever: ${newOnes.length} of ${NEW.size}; with chain info ${newOnes.filter((q) => q.pre || q.preAny || q.opens).length} (EG next ${egPre}, quest lines ${linePre}, earlier quests ${beforePre}); with a giver ${newOnes.filter((q) => q.starts.length).length}, a zone ${newOnes.filter((q) => q.zone || q.dungeon).length}`);
  console.log(`${zoneQuests.size} zones, ${dungeonQuests.size} dungeons, ${actorKeys("n").length} NPCs, ${actorKeys("o").length} objects, ${actorKeys("i").length} items; ${ambiguous} places with alternatives`);
  const withObjectives = all.filter((q) => q.objectives.length);
  console.log(`objectives: ${withObjectives.length} quests (${withObjectives.filter((q) => eg.quests[q.id] && Array.isArray(eg.quests[q.id].objectives)).length} EG Link's), ${all.reduce((n, q) => n + q.objectives.length, 0)} objectives; rewards: ${all.filter((q) => q.rewards.choice && q.rewards.choice.length).length} with choices, ${all.filter((q) => q.rewards.items && q.rewards.items.length).length} with items, ${all.filter((q) => q.rewards.money).length} money, ${all.filter((q) => q.rewards.xp).length} XP; levels from EG Link: ${levelsChanged} changed; scaling: ${all.filter((q) => q.scales).length}`);
  console.log(`items that start quests: ${starterItems}, with objective items ${starterZones.size}, ${itemDrops.size} with drop sources (${egItems.size} from EG Link), ${usedSources.size} sources (${[...usedSources].filter((k) => sources.get(k).points.length).length} with places)`);
  console.log(`races with a mask: ${all.filter((q) => q.races).length} (${all.filter((q) => q.races && races.list.some((r) => !r.classic && races.has(q.races, r.bit))).length} with a new race)`);
  console.log(`sides: ${all.filter((q) => q.faction).length} quests one side's (${textSides.byEnder.length} by their ender, ${textSides.byText.length} by an NPC their text names, ${textSides.byZone.length} by their zone), ${all.filter((q) => !q.faction && !q.races).length} without races or a side; events: ${all.filter((q) => q.event).length}`);
  console.log(`no zone: ${all.filter((q) => !q.zone && !q.dungeon).length}; ${(Buffer.byteLength(lua) / 1024 / 1024).toFixed(2)} MB`);
  if (o.stats) return;
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, lua, "utf8");
  console.log(`written: ${path.relative(process.cwd(), OUT)}`);
}

if (require.main === module) main().catch((e) => { console.error(e); process.exit(1); });
module.exports = { worldMaps, places, onBox, sideOf, raceModel, clusters };
