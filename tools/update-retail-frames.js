// Regenerates LefthyTools/Data/RetailUnitFrames.lua: retail's art for the unit frames, for Misc
// Tweaks' "Retail unit frames" (Modules/Tweaks/RetailFrames.lua).
//
// The client's atlases come in sets (UiTextureAtlas.UiTextureAtlasSetID): set 0 is retail's art, set
// 1 Forever's own ("c60", classic-styled since build 1.60.1.70425). An atlas name in set 1 overrides
// the same name in set 0, and there's no API to pick a set, but set 0's definitions are still in the
// client: a texture can be pointed at them by file, texture coordinates and size.
//
// Source: wago.tools exports of UiTextureAtlas (file, size, set, canvas: 1 = 1x art, 2 = 2x),
// UiTextureAtlasMember (a name's pixel rectangle on that file, its size) and UiTextureAtlasElement
// (the names). Kept: unit frame names ("unitframe") that set 1 overrides and set 0 defines; the 2x
// art (sharper), its size in interface units from the 1x member (else half the 2x one).
// Status bar fills can't be pointed at part of a file (the bar crops its texture itself), so they
// get another atlas name with retail's art that set 1 doesn't override (BARS below).
// Run it when Forever gets new builds:
//   node tools/update-retail-frames.js                      the latest Forever build
//   node tools/update-retail-frames.js 1.60.1.70425
//   node tools/update-retail-frames.js --cache <dir>        keep the downloads in <dir>
const fs = require("fs");
const path = require("path");

// A bar fill's retail stand-in, by the end of its name: the player frame's "portrait off" bars
// (same art family; a status bar stretches its fill to its own size anyway).
const BARS = [
  [/-bar-health$/i, "UI-HUD-UnitFrame-Player-PortraitOff-Bar-Health"],
  [/-bar-(health|mana)-status$/i, "UI-HUD-UnitFrame-Player-PortraitOff-Bar-Health-Status"],
  [/-bar-mana$/i, "UI-HUD-UnitFrame-Player-PortraitOff-Bar-Mana"],
  [/-bar-energy$/i, "UI-HUD-UnitFrame-Player-PortraitOff-Bar-Energy"],
  [/-bar-focus$/i, "UI-HUD-UnitFrame-Player-PortraitOff-Bar-Focus"],
  [/-bar-rage$/i, "UI-HUD-UnitFrame-Player-PortraitOff-Bar-Rage"],
  [/-bar-runicpower$/i, "UI-HUD-UnitFrame-Player-PortraitOff-Bar-RunicPower"],
];

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

// Every atlas name: { name, set: { [setID]: { [canvasID]: member } } }.
function atlasSets(atlas, element, member) {
  const atlasById = Object.fromEntries(atlas.map((a) => [a.ID, a]));
  const elementById = Object.fromEntries(element.map((e) => [e.ID, e]));
  const names = {};
  for (const m of member) {
    const a = atlasById[m.UiTextureAtlasID];
    if (!a) continue;
    const e = elementById[m.UiTextureAtlasElementID];
    const name = (e && e.Name) || m.CommittedName;
    if (!name) continue;
    const entry = names[name.toLowerCase()] = names[name.toLowerCase()] || { name, set: {} };
    const set = entry.set[a.UiTextureAtlasSetID] = entry.set[a.UiTextureAtlasSetID] || {};
    set[a.UiCanvasID] = { file: +a.FileDataID, W: +a.AtlasWidth, H: +a.AtlasHeight, l: +m.CommittedLeft, r: +m.CommittedRight,
      t: +m.CommittedTop, b: +m.CommittedBottom, w: +m.Width, h: +m.Height };
  }
  return names;
}

const num = (n) => String(Math.round(n * 1e6) / 1e6);

async function main() {
  const args = process.argv.slice(2);
  const cacheAt = args.indexOf("--cache");
  const cache = cacheAt >= 0 ? args.splice(cacheAt, 2)[1] : null;
  if (cache) fs.mkdirSync(cache, { recursive: true });
  const build = args[0] || await latestBuild();
  console.log(`WoW: Forever ${build}`);
  const [atlas, element, member] = await Promise.all(["UiTextureAtlas", "UiTextureAtlasElement", "UiTextureAtlasMember"]
    .map((name) => table(name, build, cache)));
  const names = atlasSets(atlas, element, member);
  const overridden = (key) => !!(names[key] && names[key].set["1"]);

  const art = [], bars = [];
  for (const key of Object.keys(names).sort()) {
    const entry = names[key];
    if (!/unitframe/.test(key) || !entry.set["1"] || !entry.set["0"]) continue;
    const retail = entry.set["0"];
    const best = retail["2"] || retail["1"];
    const size = retail["1"] ? [retail["1"].w, retail["1"].h] : [best.w / 2, best.h / 2];
    art.push(`\t["${key}"] = { ${best.file}, ${num(best.l / best.W)}, ${num(best.r / best.W)}, ${num(best.t / best.H)}, ${num(best.b / best.H)}, `
      + `${num(size[0])}, ${num(size[1])} },`);
    const bar = BARS.find(([pattern]) => pattern.test(key));
    if (bar && !overridden(bar[1].toLowerCase()) && names[bar[1].toLowerCase()]) {
      bars.push(`\t["${key}"] = "${bar[1]}",`);
    }
  }
  const out = [
    `-- Generated by tools/update-retail-frames.js from wago.tools exports of WoW: Forever ${build}.`,
    "-- Retail's art (atlas set 0) for the unit frame atlases Forever's own art set overrides:",
    "-- [atlas name, lowercase] = { file, left, right, top, bottom (texture coordinates), width, height }.",
    "-- BARS: a status bar fill's stand-in, an atlas with retail's art that Forever doesn't override.",
    "local _, ns = ...",
    "",
    "ns.RETAIL_FRAME_ART = {",
    ...art,
    "}",
    "",
    "ns.RETAIL_FRAME_BARS = {",
    ...bars,
    "}",
    "",
  ];
  const target = path.join(__dirname, "..", "LefthyTools", "Data", "RetailUnitFrames.lua");
  fs.writeFileSync(target, out.join("\r\n"));
  console.log(`${art.length} atlases, ${bars.length} bar fills -> ${path.relative(process.cwd(), target)}`);
}

main().catch((e) => { console.error(e); process.exit(1); });
