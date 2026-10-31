// What the mock can't do in Lua, from Node, put into each test Lua state before mock.lua (run.js):
//
// C_EncodingUtil: the game's compression and Base64, backed by Node's real zlib, so Echoes' pages
//   really round-trip and a program outside the game can read them. CompressString(source, method,
//   level) and DecompressString(source, method): method 0 (or none) raw deflate, 1 zlib, 2 gzip
//   (Enum.CompressionMethod: Deflate, Zlib, Gzip); EncodeBase64(source, variant) and
//   DecodeBase64(source, variant): variant 0 (or none) standard, 1 URL-safe (Enum.Base64Variant).
//   A source that isn't a string is an error, like the game's; DecompressString of bad data
//   answers nothing. Strings are bytes both ways.
//
// MOCK_EXPORTER(text): the Echoes exporter's own readers run on a saved-variables file's text (as
//   the game writes LefthyTools.lua), when the environment variable ECHOES_EXPORTER names the
//   exporter's folder (the one with lib/sv.js, lib/pages.js, lib/run.js and lib/archive.js). It
//   archives every page into a temporary folder the way the exporter does and answers
//   { new, same, provisional, bad, hashBad, warnings = { ... }, pages = { ["acct.store.n"] = text },
//   open = { ["acct.store.n"] = text }, parsed = { ["acct.store.n"] = { ok, end, acct, store, n,
//   t0, chars, events, segs, unknown } } }, or a string saying why it couldn't. Without
//   ECHOES_EXPORTER it is nil (the cross-check is skipped).
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const zlib = require("zlib");
const { lua, lauxlib, to_luastring } = require("fengari");

const COMPRESS = { 0: zlib.deflateRawSync, 1: zlib.deflateSync, 2: zlib.gzipSync };
const DECOMPRESS = { 0: zlib.inflateRawSync, 1: zlib.inflateSync, 2: zlib.gunzipSync };

// The bytes of argument i (a Lua string), or an error like the game's.
function bytes(L, i, name) {
  if (lua.lua_type(L, i) !== lua.LUA_TSTRING) lauxlib.luaL_error(L, to_luastring(`${name}: bad argument #${i} (string expected)`));
  return Buffer.from(lua.lua_tolstring(L, i));
}
function method(L, i) {
  return lua.lua_isnoneornil(L, i) ? 0 : lua.lua_tointeger(L, i);
}

// A JS value as a Lua value on the stack: strings (as UTF-8) and Buffers (as bytes), numbers
// (whole ones as integers), booleans, arrays and plain objects as tables.
function push(L, v) {
  if (v === null || v === undefined) lua.lua_pushnil(L);
  else if (typeof v === "boolean") lua.lua_pushboolean(L, v);
  else if (typeof v === "number") {
    if (Number.isInteger(v) && Math.abs(v) < 2 ** 53) lua.lua_pushinteger(L, v);
    else lua.lua_pushnumber(L, v);
  } else if (typeof v === "string") lua.lua_pushstring(L, to_luastring(v));
  else if (Buffer.isBuffer(v)) lua.lua_pushstring(L, new Uint8Array(v));
  else if (Array.isArray(v)) {
    lua.lua_createtable(L, v.length, 0);
    v.forEach((x, i) => { push(L, x); lua.lua_rawseti(L, -2, i + 1); });
  } else {
    lua.lua_newtable(L);
    for (const [k, x] of Object.entries(v)) {
      if (x === undefined) continue;
      push(L, x);
      lua.lua_setfield(L, -2, to_luastring(k));
    }
  }
}

function fn(L, name, f) {
  lua.lua_pushjsfunction(L, (L2) => {
    const out = f(L2);
    if (out === null || out === undefined) return 0;
    push(L2, out);
    return 1;
  });
  lua.lua_setfield(L, -2, to_luastring(name));
}

// The exporter's readers on a saved-variables text (see the top).
function exporterCheck(text) {
  const dir = process.env.ECHOES_EXPORTER;
  if (!dir) return null;
  const lib = (name) => path.join(path.resolve(dir), "lib", name);
  if (!fs.existsSync(lib("run.js"))) return `ECHOES_EXPORTER (${dir}) has no lib/run.js`;
  const { parseSV } = require(lib("sv.js"));
  const { decodePage, parsePage } = require(lib("pages.js"));
  const { exportDB } = require(lib("run.js"));
  const { Archive } = require(lib("archive.js"));
  const db = parseSV(text).LefthyToolsEchoesDB;
  if (!db) return "no LefthyToolsEchoesDB in the text";
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "echoes-check-"));
  try {
    const archive = new Archive(root);
    const res = exportDB(db, archive, { hash: "lt32", hashPolicy: "strict" });
    const out = { new: res.new, same: res.same, provisional: res.provisional, bad: res.bad, hashBad: res.hashBad,
      warnings: res.warnings, pages: {}, open: {}, parsed: {} };
    for (const page of archive.list()) {
      const id = `${page.store}.${page.n}`;
      const body = archive.read(page);
      (page.provisional ? out.open : out.pages)[id] = body;
      const p = parsePage(body);
      out.parsed[id] = { ok: p.ok, end: p.end, acct: p.acct, store: p.store, n: p.n, t0: p.t0, chars: Object.keys(p.chars).length,
        events: p.events.length, segs: p.segs.length, unknown: Object.keys(p.unknown).join(","), bad: p.bad };
    }
    out.decodes = typeof decodePage === "function";
    return out;
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
}

module.exports = function install(L) {
  lua.lua_newtable(L);
  fn(L, "CompressString", (L2) => {
    const compress = COMPRESS[method(L2, 2)];
    const source = bytes(L2, 1, "CompressString");
    return compress ? compress(source) : null;
  });
  fn(L, "DecompressString", (L2) => {
    const decompress = DECOMPRESS[method(L2, 2)];
    const source = bytes(L2, 1, "DecompressString");
    try { return decompress ? decompress(source) : null; } catch { return null; }
  });
  fn(L, "EncodeBase64", (L2) => {
    const url = method(L2, 2) === 1;
    const out = bytes(L2, 1, "EncodeBase64").toString(url ? "base64url" : "base64");
    return Buffer.from(out, "latin1");
  });
  fn(L, "DecodeBase64", (L2) => Buffer.from(bytes(L2, 1, "DecodeBase64").toString("latin1"), method(L2, 2) === 1 ? "base64url" : "base64"));
  lua.lua_setglobal(L, to_luastring("C_EncodingUtil"));

  lua.lua_pushjsfunction(L, (L2) => {
    const text = bytes(L2, 1, "MOCK_EXPORTER");
    let out;
    try {
      out = exporterCheck(text);
    } catch (e) {
      out = `the exporter failed: ${e.stack || e.message}`;
    }
    if (out === null) return 0;
    push(L2, out);
    return 1;
  });
  lua.lua_setglobal(L, to_luastring("MOCK_EXPORTER"));
};
