// Runs LefthyTools inside fengari (Lua 5.3 VM in JS) against mock.lua.
// Files are loaded in the order the TOC lists them, like the game client does.
// `npm test` runs everything. Names run a part of the behavioural tests (3): `npm test -- stream`
// runs tests/stream.lua and the files it needs (its "-- Needs:" line, and theirs) in the suite's
// order; several names add up, "german" is the German suite and "release" the release's (the beta's
// saved data going). A folder is the add-on to test.
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

// A suite of its own in a process of its own: the German and release suites run beside the English
// one (below, "Side suites"). `node tests/run.js --side <job.json>` runs the scripts the job names in
// one Lua state, with the sources the main run read at its start; what it prints goes to its stdout
// (a file the main run prints after the English suite), a failure exits with 1 as in the main run.
if (process.argv[2] === "--side") {
  const job = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
  const L = newState(job.files, job.sources);
  for (const script of job.scripts) run(L, script.name, undefined, script.src);
  return;
}

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
  "levelup.lua", "bestiary.lua", "whatsnew.lua", "echoes.lua", "echoes_capture.lua", "echoes_pages.lua", "echoes_net.lua", "recipes_data.lua", "recipes_data.lua", "recipes.lua", "professions.lua", "ltc_tabs.lua", "gamepad_symbols.lua", "settings_window.lua", "fixed_errors.lua", "ltc_more.lua", "margins.lua", "gamepad_bags.lua", "loot_rolls.lua", "map_overlay.lua", "lodestar_data.lua", "lodestar_small.lua", "lodestar_browser.lua", "lodestar_learn.lua", "lodestar_views.lua", "lodestar_dialog.lua", "lodestar_items.lua"];

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

function newState(files, sources) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  require("./native.js")(L); // C_EncodingUtil with Node's real zlib, MOCK_EXPORTER (tests/native.js)
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
  compileOnce(L);
  return L;
}

// load() compiles a text once per Lua state: the addon is loaded many times (every client in
// echoes_net.lua and recipes.lua, every start in release.lua) from the same SOURCES strings, and
// fengari's compiler is slow. A string load() compiled before (the same Lua string, chunk name and
// a mode that allows text) is loaded again from the bytecode string.dump would give: the same
// function (code, constants, line numbers, chunk name), a new closure with its own upvalues, the
// env argument set as in Lua's load. Everything else (reader functions, binary chunks, a load that
// fails) goes the usual way, so errors read the same.
function compileOnce(L) {
  const T = 0x74, ESC = 0x1b, DEFAULT_NAME = Symbol("the source"); // "t", a binary chunk's first byte, no name given
  const compiled = new WeakMap(); // the source's bytes (one per Lua string) -> Map(chunk name -> bytecode)
  lua.lua_getglobal(L, to_luastring("load"));
  const original = lauxlib.luaL_ref(L, lua.LUA_REGISTRYINDEX);
  lua.lua_pushcfunction(L, (L) => {
    const top = lua.lua_gettop(L);
    const nameType = lua.lua_type(L, 2), modeType = lua.lua_type(L, 3);
    const s = lua.lua_type(L, 1) === lua.LUA_TSTRING ? lua.lua_tolstring(L, 1) : null;
    const mode = modeType === lua.LUA_TSTRING ? lua.lua_tolstring(L, 3) : null;
    if (s === null || s[0] === ESC || !(nameType === lua.LUA_TSTRING || nameType <= lua.LUA_TNIL)
        || !(mode ? mode.includes(T) : modeType <= lua.LUA_TNIL)) {
      lua.lua_rawgeti(L, lua.LUA_REGISTRYINDEX, original); // (the usual way)
      lua.lua_insert(L, 1);
      lua.lua_call(L, top, lua.LUA_MULTRET);
      return lua.lua_gettop(L);
    }
    const name = nameType === lua.LUA_TSTRING ? lua.lua_tolstring(L, 2) : s;
    const key = nameType === lua.LUA_TSTRING ? Buffer.from(name).toString("latin1") : DEFAULT_NAME;
    let byName = compiled.get(s);
    let bytecode = byName && byName.get(key);
    if (bytecode) {
      lauxlib.luaL_loadbufferx(L, bytecode, bytecode.length, name, to_luastring("b"));
    } else {
      if (lauxlib.luaL_loadbufferx(L, s, s.length, name, mode) !== lua.LUA_OK) {
        lua.lua_pushnil(L);
        lua.lua_insert(L, -2);
        return 2; // (nil and the message, as Lua's load answers)
      }
      const parts = [];
      lua.lua_dump(L, (_, b, size) => { parts.push(b.slice(0, size)); return 0; }, null, false);
      bytecode = new Uint8Array(Buffer.concat(parts));
      if (!byName) compiled.set(s, byName = new Map());
      byName.set(key, bytecode);
    }
    if (top >= 4) { // (an env argument, nil too: the first upvalue, like Lua's load)
      lua.lua_pushvalue(L, 4);
      if (!lua.lua_setupvalue(L, -2, 1)) lua.lua_pop(L, 1);
    }
    return 1;
  });
  lua.lua_setglobal(L, to_luastring("load"));
}

// Runs a script (its text: src, or read now) with the suite table (a registry reference) as its
// argument; returns its first result.
function run(L, script, suite, src) {
  if (src === undefined) src = fs.readFileSync(path.join(__dirname, script), "utf8");
  if (lauxlib.luaL_loadbuffer(L, to_luastring(src), null, to_luastring("@" + script)) !== lua.LUA_OK) fail(L);
  if (suite !== undefined) lua.lua_rawgeti(L, lua.LUA_REGISTRYINDEX, suite);
  if (lua.lua_pcall(L, suite !== undefined ? 1 : 0, 1, 0) !== lua.LUA_OK) fail(L);
  return lauxlib.luaL_ref(L, lua.LUA_REGISTRYINDEX);
}
function fail(L) {
  console.log("LUA ERROR: " + lua.lua_tojsstring(L, -1));
  process.exit(1);
}

// Side suites: the German client and the release (the beta's saved data going; release.lua starts
// the game itself, several times) need nothing of the English suite, so each runs in a process of
// its own (`--side`, at the top) while the English suite runs here. Their output is printed after
// the English suite's, in this order, as if they ran after it; the first that fails ends the run.
const side = [];
let sideDir;
function startSide(scripts) {
  sideDir = sideDir || fs.mkdtempSync(path.join(os.tmpdir(), "lefthytools-test-"));
  const n = side.length;
  const job = path.join(sideDir, `job${n}.json`), out = path.join(sideDir, `out${n}.txt`);
  fs.writeFileSync(job, JSON.stringify({ files, sources,
    scripts: scripts.map((name) => ({ name, src: fs.readFileSync(path.join(__dirname, name), "utf8") })) }));
  const fd = fs.openSync(out, "w"); // (a file, not a pipe: this process is busy with the English suite)
  const child = spawn(process.execPath, [__filename, "--side", job], { cwd: process.cwd(), stdio: ["ignore", fd, "inherit"] });
  fs.closeSync(fd);
  side.push({ child, out, done: new Promise((resolve) => child.on("close", (code) => resolve(code))) });
}
process.on("exit", () => {
  for (const s of side) if (s.child.exitCode === null) s.child.kill();
  if (sideDir) try { fs.rmSync(sideDir, { recursive: true, force: true }); } catch (e) { /* (a child still closing) */ }
});
if (german) startSide(["mock.lua", "test_de.lua"]);
if (release) startSide(["mock.lua", "release.lua"]);

// English client
if (english.length) {
  if (names.length) console.log(`English suite: ${english.join(", ")}`);
  const L = newState(files, sources);
  run(L, "mock.lua");
  const suite = run(L, "helpers.lua");
  for (const file of english) run(L, file, suite);
  lua.lua_rawgeti(L, lua.LUA_REGISTRYINDEX, suite);
  lua.lua_getfield(L, -1, to_luastring("Finish"));
  if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) fail(L);
}

(async () => {
  for (const s of side) {
    const code = await s.done;
    process.stdout.write(fs.readFileSync(s.out));
    if (code !== 0) {
      process.exitCode = 1;
      return;
    }
  }
})();
