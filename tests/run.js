// Runs LefthyTools inside fengari (Lua 5.3 VM in JS) against mock.lua.
// Files are loaded in the order the TOC lists them, like the game client does.
// `npm test` runs everything. Names run a part of the behavioural tests (3): `npm test -- stream`
// runs tests/stream.lua and the files it needs (its "-- Needs:" line, and theirs) in the suite's
// order; several names add up, "german" is the German suite and "release" the release's (the beta's
// saved data going). A folder is the add-on to test.
const fs = require("fs");
const path = require("path");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");
const luaparse = require("luaparse");

const args = process.argv.slice(2);
const addonArg = args.find((a) => fs.existsSync(a) && fs.statSync(a).isDirectory());
const names = args.filter((a) => a !== addonArg).map((a) => a.replace(/\.lua$/, ""));
const addonDir = addonArg || path.resolve(__dirname, "..", "LefthyTools");
const toc = fs.readFileSync(path.join(addonDir, path.basename(addonDir) + ".toc"), "utf8");
const tocFiles = toc.split(/\r?\n/)
  .map((line) => line.trim())
  .filter((line) => line && !line.startsWith("#"))
  .map((line) => line.replace(/\\/g, "/"));

// 0) Every file the TOC names is there, XML too (the game would only say so in a load error).
const missingFiles = tocFiles.filter((f) => !fs.existsSync(path.join(addonDir, f)));
for (const f of missingFiles) console.log(`MISSING FILE named in the TOC: ${f}`);
if (missingFiles.length) process.exit(1);

const files = tocFiles.filter((f) => f.endsWith(".lua"));
const sources = Object.fromEntries(files.map((f) => [f, fs.readFileSync(path.join(addonDir, f), "utf8")]));

// 1) Syntax check as Lua 5.1 (what WoW runs).
let ok = true;
for (const f of files) {
  try {
    luaparse.parse(sources[f], { luaVersion: "5.1" });
    console.log(`syntax ok (Lua 5.1): ${f}`);
  } catch (e) {
    ok = false;
    console.log(`SYNTAX ERROR in ${f}: ${e.message}`);
  }
}
if (!ok) process.exit(1);

// 2) Translations: every L["..."] used in code has a German entry, and every German
//    entry is still used somewhere (catches typos and leftovers after text changes).
const keyPattern = /L\["((?:[^"\\]|\\.)*)"\]/g;
const localeFiles = files.filter((f) => f.startsWith("Locales/"));
for (const localeFile of localeFiles) {
  const translated = new Set([...sources[localeFile].matchAll(/^L\["((?:[^"\\]|\\.)*)"\]\s*=/gm)].map((m) => m[1]));
  const used = new Set();
  for (const f of files.filter((f) => !f.startsWith("Locales/"))) {
    const code = sources[f].replace(/^\s*--.*$/gm, ""); // usage examples in comments aren't lookups
    for (const m of code.matchAll(keyPattern)) used.add(m[1]);
  }
  const missing = [...used].filter((k) => !translated.has(k));
  const unused = [...translated].filter((k) => !used.has(k));
  for (const k of missing) console.log(`MISSING in ${localeFile}: ${k}`);
  for (const k of unused) console.log(`UNUSED in ${localeFile}: ${k}`);
  if (missing.length || unused.length) ok = false;
  else console.log(`translations ok: ${localeFile} (${translated.size} strings)`);
}
if (!ok) process.exit(1);

// 2a) LT.FILES (Core/Core.lua) names the files the game loads, so a friend updating to this build
//     learns whether a /reload is enough: a hash of the TOC's file lines and saved variables.
const tocLoads = toc.split(/\r?\n/).map((line) => line.trim())
  .filter((line) => (line && !line.startsWith("#")) || /^##\s*SavedVariables/i.test(line));
const filesId = require("crypto").createHash("sha1").update(tocLoads.join("\n")).digest("hex").slice(0, 8);
const filesConst = (sources["Core/Core.lua"].match(/^LT\.FILES = "(\w+)"/m) || [])[1];
if (filesConst !== filesId) {
  console.log(`The TOC's files changed: set LT.FILES = "${filesId}" in Core/Core.lua (it says "${filesConst}")`);
  process.exit(1);
}
console.log(`files ok: LT.FILES = ${filesId}`);

// 2b) The players' one-file installer must be install.ps1 with the batch header (tools/build-installer.js).
if (!addonArg) {
  const installer = require("../tools/build-installer.js");
  const current = fs.existsSync(installer.target) ? fs.readFileSync(installer.target, "utf8") : "";
  if (current !== installer.build()) {
    console.log("Update-LefthyTools.cmd is out of date with install.ps1: run `npm run build-installer`");
    process.exit(1);
  }
  console.log("installer ok: Update-LefthyTools.cmd matches install.ps1");
}

// 3) Behavioural tests, each suite in a fresh Lua state. SOURCES = { { name, src }, ... } in TOC order.
//    The English suite: helpers.lua loads the addon, then the test files run in this order in the
//    same state (the mock's clock and world go on from one to the next), each getting what
//    helpers.lua returns as `...`; its Finish() makes the last checks and prints the count.
const ENGLISH = ["core.lua", "mirage.lua", "tweaks.lua", "beacon.lua", "stream.lua", "flights.lua", "chronicle.lua",
  "levelup.lua", "bestiary.lua", "whatsnew.lua"];

// Every test file is in the list, and says at its top which files it needs before it (they run
// earlier): "-- Needs: beacon.lua, ..." or "-- Needs: no other file."
const NOT_LISTED = ["mock.lua", "helpers.lua", "test_de.lua", "release.lua"];
const needs = {};
for (const f of fs.readdirSync(__dirname).filter((f) => f.endsWith(".lua") && !NOT_LISTED.includes(f))) {
  if (!ENGLISH.includes(f)) {
    console.log(`tests/${f} isn't in run.js's ENGLISH list: add it where it should run`);
    process.exit(1);
  }
}
for (const f of ENGLISH) {
  const line = (fs.readFileSync(path.join(__dirname, f), "utf8").match(/^-- Needs: .*$/m) || [])[0];
  const list = line && line.match(/^-- Needs: (\w+\.lua(?:, \w+\.lua)*)/);
  needs[f] = list ? list[1].split(", ") : [];
  const late = needs[f].filter((n) => !ENGLISH.slice(0, ENGLISH.indexOf(f)).includes(n));
  if (!line || late.length) {
    console.log(line ? `tests/${f} needs ${late.join(", ")}, which don't run before it` : `tests/${f} has no "-- Needs:" line at its top`);
    process.exit(1);
  }
}

// What to run: everything, or the files named and what they need.
const SUITES = ["german", "release"]; // suites of their own (a Lua state each), named like a file
const known = ENGLISH.map((f) => f.replace(/\.lua$/, "")).concat(SUITES);
const unknown = names.filter((n) => !known.includes(n));
if (unknown.length) {
  console.log(`No test file ${unknown.join(", ")}; there are: ${known.join(", ")}`);
  process.exit(1);
}
const picked = new Set();
const pick = (f) => { if (!picked.has(f)) { picked.add(f); needs[f].forEach(pick); } };
names.filter((n) => !SUITES.includes(n)).forEach((n) => pick(n + ".lua"));
const english = names.length ? ENGLISH.filter((f) => picked.has(f)) : ENGLISH;
const german = !names.length || names.includes("german");
const release = !names.length || names.includes("release");

function newState() {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  lua.lua_newtable(L);
  files.forEach((f, i) => {
    lua.lua_newtable(L);
    lua.lua_pushstring(L, to_luastring(f));
    lua.lua_setfield(L, -2, to_luastring("name"));
    lua.lua_pushstring(L, to_luastring(sources[f]));
    lua.lua_setfield(L, -2, to_luastring("src"));
    lua.lua_rawseti(L, -2, i + 1);
  });
  lua.lua_setglobal(L, to_luastring("SOURCES"));
  return L;
}

// Runs a script with the suite table (a registry reference) as its argument; returns its first result.
function run(L, script, suite) {
  const src = fs.readFileSync(path.join(__dirname, script), "utf8");
  if (lauxlib.luaL_loadbuffer(L, to_luastring(src), null, to_luastring("@" + script)) !== lua.LUA_OK) fail(L);
  if (suite !== undefined) lua.lua_rawgeti(L, lua.LUA_REGISTRYINDEX, suite);
  if (lua.lua_pcall(L, suite !== undefined ? 1 : 0, 1, 0) !== lua.LUA_OK) fail(L);
  return lauxlib.luaL_ref(L, lua.LUA_REGISTRYINDEX);
}
function fail(L) {
  console.log("LUA ERROR: " + lua.lua_tojsstring(L, -1));
  process.exit(1);
}

// English client
if (english.length) {
  if (names.length) console.log(`English suite: ${english.join(", ")}`);
  const L = newState();
  run(L, "mock.lua");
  const suite = run(L, "helpers.lua");
  for (const file of english) run(L, file, suite);
  lua.lua_rawgeti(L, lua.LUA_REGISTRYINDEX, suite);
  lua.lua_getfield(L, -1, to_luastring("Finish"));
  if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) fail(L);
}

// German client
if (german) {
  const L = newState();
  run(L, "mock.lua");
  run(L, "test_de.lua");
}

// The release: the beta's saved data going (release.lua starts the game itself, several times)
if (release) {
  const L = newState();
  run(L, "mock.lua");
  run(L, "release.lua");
}
