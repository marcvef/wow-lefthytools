// Runs LefthyTools inside fengari (Lua 5.3 VM in JS) against mock.lua.
// Files are loaded in the order the TOC lists them, like the game client does.
const fs = require("fs");
const path = require("path");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");
const luaparse = require("luaparse");

const addonDir = process.argv[2] || path.resolve(__dirname, "..", "LefthyTools");
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
if (!process.argv[2]) {
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
const ENGLISH = ["core.lua", "mirage.lua", "tweaks.lua", "beacon.lua", "stream.lua", "flights.lua", "questmap.lua",
  "chronicle.lua", "leaving.lua", "levelup.lua", "bestiary.lua", "aggro.lua", "whatsnew.lua", "mirageoff.lua", "guard.lua"];

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
let L = newState();
run(L, "mock.lua");
const suite = run(L, "helpers.lua");
for (const file of ENGLISH) run(L, file, suite);
lua.lua_rawgeti(L, lua.LUA_REGISTRYINDEX, suite);
lua.lua_getfield(L, -1, to_luastring("Finish"));
if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) fail(L);

// German client
L = newState();
run(L, "mock.lua");
run(L, "test_de.lua");
