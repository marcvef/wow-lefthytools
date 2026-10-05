// Regenerates LefthyTools/Data/ClassSpells.lua: what each class can learn at its trainer, per level.
// The level-up window (Modules/Tweaks/LevelUp.lua) lists the spells of the new level that the
// player doesn't know yet.
//
// Source: wago.tools exports of the client's SkillLineAbility (spells of each class skill line),
// SpellLevels (the level a spell is learned at), SpellName, SkillLine, SkillRaceClassInfo (which
// class a skill line belongs to), Talent and TalentTab tables. Kept: spells of a class's own skill
// lines that are learned (AcquireMethod 0) at level 2 or later; the ones every character starts
// with (AcquireMethod 2) count only for the rank numbers. Left out: talents, effects of
// multi-rank talents (they share the talent's name), unnamed spells, Season of Discovery runes
// (IDs 395000-469999; Forever's own versions have new IDs), pets, mounts, companions and runes.
// Higher ranks of a talent spell (Pyroblast) are listed with the talent they need.
// Run it when Forever gets new builds:
//   node tools/update-class-spells.js                      the latest Forever build
//   node tools/update-class-spells.js 1.60.1.70205
//   node tools/update-class-spells.js --cache <dir>        keep the downloads in <dir>
const fs = require("fs");
const path = require("path");

const CLASSES = { 1: "WARRIOR", 2: "PALADIN", 3: "HUNTER", 4: "ROGUE", 5: "PRIEST", 7: "SHAMAN", 8: "MAGE", 9: "WARLOCK", 11: "DRUID" };
const SKIPPED_LINES = /^(Pet - |Mounts$|Companions$|Engraving$|Runes$|Meditation$|Explorer Imp$|Beast Training$)/;
const SOD_IDS = [395000, 470000];
// Parts of other spells (a trap's effect, a stance's passive) and talent procs whose talent has no
// spell name in the export.
const EFFECTS = /( Effect| Passive| \(Passive\d*\))$/;
const PROCS = new Set(["Clearcasting", "Pyroclasm", "Lightwell Renew"]);

function parseCsv(text) {
  const rows = [];
  let field = "", row = [], quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; } else quoted = false;
      } else field += c;
    } else if (c === '"') quoted = true;
    else if (c === ",") { row.push(field); field = ""; }
    else if (c === "\n") { row.push(field.replace(/\r$/, "")); rows.push(row); row = []; field = ""; }
    else field += c;
  }
  if (field || row.length) { row.push(field); rows.push(row); }
  const head = rows.shift();
  return rows.filter((r) => r.length === head.length).map((r) => Object.fromEntries(head.map((h, i) => [h, r[i]])));
}

async function latestBuild() {
  const builds = await (await fetch("https://wago.tools/api/builds")).json();
  // WoW: Forever is version 1.60.x (listed under a beta product on wago.tools).
  const all = Object.values(builds).flat().map((b) => b.version).filter((v) => /^1\.60\./.test(v));
  const key = (v) => v.split(".").map((n) => n.padStart(8, "0")).join(".");
  return all.sort((a, b) => (key(a) < key(b) ? 1 : -1))[0];
}

async function table(name, build, cache) {
  const file = cache && path.join(cache, `${name}-${build}.csv`);
  let text;
  if (file && fs.existsSync(file)) {
    text = fs.readFileSync(file, "utf8");
  } else {
    const response = await fetch(`https://wago.tools/db2/${name}/csv?build=${build}`);
    if (!response.ok) throw new Error(`${name}: HTTP ${response.status}`);
    text = await response.text();
    if (file) fs.writeFileSync(file, text);
  }
  const rows = parseCsv(text);
  if (rows.length < 10) throw new Error(`${name} for ${build} looks incomplete (${rows.length} rows)`);
  return rows;
}

// RaceMasks_0 is the low 32 bits of the race mask, signed.
const unsigned = (n) => (Number(n) >>> 0);

async function main() {
  const args = process.argv.slice(2);
  let cache, build;
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--cache") cache = args[++i];
    else build = args[i];
  }
  if (cache) fs.mkdirSync(cache, { recursive: true });
  build = build || (await latestBuild());
  if (!build) throw new Error("could not determine the Forever build; pass it as an argument");
  console.log(`WoW: Forever ${build}`);

  const [skillLines, abilities, levels, names, raceClass, talents, tabs] = await Promise.all(
    ["SkillLine", "SkillLineAbility", "SpellLevels", "SpellName", "SkillRaceClassInfo", "Talent", "TalentTab"]
      .map((t) => table(t, build, cache)));

  const nameOf = {};
  for (const r of names) nameOf[r.ID] = r.Name_lang;
  const levelOf = {};
  for (const r of levels) if (r.DifficultyID === "0") levelOf[r.SpellID] = Number(r.BaseLevel) || Number(r.SpellLevel);
  const classLines = {};
  for (const r of skillLines) if (r.CategoryID === "7" && !SKIPPED_LINES.test(r.DisplayName_lang)) classLines[r.ID] = 0;
  for (const r of raceClass) if (r.SkillID in classLines) classLines[r.SkillID] |= Number(r.ClassMask);

  // Talents per class: every rank's spell, and the names of multi-rank ones (their effects share them).
  const tabClass = {};
  for (const t of tabs) tabClass[t.ID] = Number(t.ClassMask);
  const talentSpell = {}, singleRank = {}, multiRankNames = {};
  for (const t of talents) {
    const mask = tabClass[t.TabID] || 0;
    const ranks = [];
    for (let i = 0; i < 9; i++) if (Number(t["SpellRank_" + i])) ranks.push(t["SpellRank_" + i]);
    for (const id of ranks) talentSpell[id] = true;
    if (!ranks.length) continue;
    for (const classID of Object.keys(CLASSES)) {
      if (!(mask & (1 << (classID - 1)))) continue;
      const name = nameOf[ranks[0]];
      if (!name) continue;
      if (ranks.length === 1) (singleRank[classID] = singleRank[classID] || {})[name] = ranks[0];
      else (multiRankNames[classID] = multiRankNames[classID] || {})[name] = true;
    }
  }

  const out = {}, needs = {}, races = {}, rank = {};
  let total = 0;
  for (const classID of Object.keys(CLASSES)) {
    const bit = 1 << (classID - 1);
    const seen = {};
    const list = [];
    for (const r of abilities) {
      // Trained (0) and the ones every character starts with (2: rank 1 of Fireball, Stealth, ...),
      // which only count for the ranks.
      if (!(r.SkillLine in classLines) || (r.AcquireMethod !== "0" && r.AcquireMethod !== "2")) continue;
      const mask = Number(r.ClassMask) || classLines[r.SkillLine];
      if (!(mask & bit)) continue;
      const id = Number(r.Spell);
      const name = nameOf[r.Spell];
      const level = levelOf[r.Spell] || 0;
      if (seen[id] || !name || level < 1 || talentSpell[id]) continue;
      if (id >= SOD_IDS[0] && id < SOD_IDS[1]) continue;
      if (EFFECTS.test(name) || PROCS.has(name) || (multiRankNames[classID] || {})[name]) continue;
      seen[id] = true;
      const raceMask = unsigned(r.RaceMasks_0);
      const listed = r.AcquireMethod === "0" && level >= 2;
      list.push({ id, name, level, raceMask, listed, need: (singleRank[classID] || {})[name] });
    }
    // Ranks: per name (and race), in level order; a talent spell is rank 1 of its chain. Two spells
    // of one name at one level (a spell and its channel, or two ranks at once): the first one.
    list.sort((a, b) => a.level - b.level || a.id - b.id);
    const count = {}, atLevel = {};
    for (const s of list) {
      const key = s.name + "/" + s.raceMask;
      if (atLevel[key] === s.level) continue;
      atLevel[key] = s.level;
      count[key] = (count[key] || (s.need ? 1 : 0)) + 1;
      if (!s.listed) continue;
      if (count[key] > 1) rank[s.id] = count[key];
      if (s.need) needs[s.id] = Number(s.need);
      if (s.raceMask) races[s.id] = s.raceMask;
      const byLevel = (out[CLASSES[classID]] = out[CLASSES[classID]] || {});
      (byLevel[s.level] = byLevel[s.level] || []).push(s.id);
      total++;
    }
  }

  const lines = [
    "local _, ns = ...",
    "",
    "-- What each class learns at its trainer: [class] = { [level] = { spell IDs } }.",
    `-- Generated by tools/update-class-spells.js from wago.tools exports of WoW: Forever ${build}.`,
    `-- ${total} spells. NEEDS: higher ranks of a talent spell, listed only for players who know the`,
    "-- talent. RACES: spells only some races learn (race mask, bit raceID - 1). RANK: rank 2 and up.",
    "ns.CLASS_SPELLS = {",
  ];
  for (const file of Object.keys(out).sort()) {
    lines.push(`\t${file} = {`);
    for (const level of Object.keys(out[file]).map(Number).sort((a, b) => a - b)) {
      lines.push(`\t\t[${level}] = { ${out[file][level].join(", ")} },`);
    }
    lines.push("\t},");
  }
  lines.push("}");
  const map = (title, t, hex) => {
    lines.push(`ns.${title} = {`);
    const ids = Object.keys(t).map(Number).sort((a, b) => a - b);
    for (let i = 0; i < ids.length; i += 8) {
      lines.push("\t" + ids.slice(i, i + 8).map((id) => `[${id}] = ${hex ? "0x" + t[id].toString(16) : t[id]},`).join(" "));
    }
    lines.push("}");
  };
  map("CLASS_SPELL_NEEDS", needs);
  map("CLASS_SPELL_RACES", races, true);
  map("CLASS_SPELL_RANK", rank);

  const target = path.resolve(__dirname, "..", "LefthyTools", "Data", "ClassSpells.lua");
  fs.writeFileSync(target, lines.join("\r\n") + "\r\n");
  console.log(`${total} spells written to ${path.relative(process.cwd(), target)}`);
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
