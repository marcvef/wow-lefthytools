// What the data tools share for reading WoW: Forever's client on wago.tools: the latest Forever
// build, a client table (a DB2 export as CSV, optionally kept in a cache folder) and the arguments
// of the tools that read tables. Used by update-class-spells.js, update-spell-schools.js and
// update-retail-frames.js (tables), and update-minimap-tiles.js (the latest build). Not a tool
// itself: the tools require it.
const fs = require("fs");
const path = require("path");

// CSV text as rows, { [column]: value } (all text). A quoted field can hold commas, line breaks and
// doubled quotes; a row with another number of fields than the header is left out.
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

// The latest WoW: Forever build on wago.tools ("1.60.1.70532"), undefined if there's none.
async function latestBuild() {
  const builds = await (await fetch("https://wago.tools/api/builds")).json();
  // WoW: Forever is the product wowf on wago.tools (the release client, any version), and version
  // 1.60.x under other products too (the beta's wow_classic_beta): the newest of all of them.
  const all = Object.entries(builds)
    .flatMap(([product, list]) => list.filter((b) => product === "wowf" || /^1\.60\./.test(b.version)))
    .map((b) => b.version);
  const key = (v) => v.split(".").map((n) => n.padStart(8, "0")).join(".");
  return all.sort((a, b) => (key(a) < key(b) ? 1 : -1))[0];
}

// A client table of a build, as rows (parseCsv). With a cache folder, the export is kept there as
// <name>-<build>.csv and read from there the next time. Fewer than 10 rows is an error: a failed
// or cut-off export.
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

// The arguments of the tools that read tables: [<build>] [--cache <dir>], in any order. Without a
// build, the latest Forever build; the cache folder is made if it's missing.
async function options(args = process.argv.slice(2)) {
  let cache, build;
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--cache") cache = args[++i];
    else build = args[i];
  }
  if (cache) fs.mkdirSync(cache, { recursive: true });
  build = build || (await latestBuild());
  if (!build) throw new Error("could not determine the Forever build; pass it as an argument");
  return { build, cache };
}

module.exports = { parseCsv, latestBuild, table, options };
