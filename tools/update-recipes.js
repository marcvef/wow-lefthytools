// Regenerates LefthyTools/Data/Recipes.lua: every profession's recipes with what they make and need,
// for Chronicle's Professions tab (Modules/Chronicle/Recipes.lua reads it; docs/chronicle.md, Recipe data).
//
// Source: wago.tools exports of SkillLineAbility (a line's spells, the skill where they turn yellow
// and grey, their category), SpellReagents (what a spell uses), SpellEffect (what it makes),
// ItemSparse (the item's slot, level and quality; only about 85% of crafted items are in it),
// SkillLine and TradeSkillCategory (names, in English and German, the lines' icons, the child lines).
// A recipe is a spell of a crafting line with reagents, so the lines' own ranks ("Leatherworking",
// "Armorsmith") and the recipes the client no longer has reagents for are left out; the gathering
// lines have no recipes here, though Mining's smelting would count as such.
//
// What the rows mean:
// - A spell can be under a line twice (rows the same): one is kept. Under two lines (Synthetic Gordok
//   Ogre Suit): it's a recipe of both.
// - The count made is the "create item" effect's EffectBasePointsF, which is 0 where a recipe makes
//   one (the oils, Enchanting's wands and relics, Engineering's newer gadgets) and the middle of the
//   range when Variance says it varies (Heavy Dynamite: 3 for 1 to 5).
// - The reagent columns can have a gap (White Wedding Dress).
// - Enchanting mostly enchants, so most of its recipes make no item.
// `vendor` is what Chronicle's margins (Modules/Chronicle/Margins.lua) count a vendor-sold reagent at
// until the client has seen a merchant sell it: the client has no table of what vendors sell, so the
// items are a hand list (VENDOR, below), each priced by ItemSparse's BuyPrice per VendorStackCount
// (copper for one), and only those some recipe uses.
// Run it when Forever gets new builds:
//   node tools/update-recipes.js                      the latest Forever build
//   node tools/update-recipes.js 1.60.1.70790
//   node tools/update-recipes.js --cache <dir>        keep the downloads in <dir>
const fs = require("fs");
const path = require("path");
const { table, options } = require("./wago");

const ORDER = [171, 164, 333, 202, 165, 197, 185, 129]; // crafting, in the tab's order
const GATHERING = [182, 186, 393, 356]; // Herbalism, Mining, Skinning, Fishing
const CREATE_ITEM = "24"; // SpellEffect.Effect
const REAGENTS = 8; // Reagent_0..7, ReagentCount_0..7
// Reagents Classic's trade-goods vendors sell. Forever's own new reagents aren't here: nothing tells
// whether a vendor has them, so they're learned from merchants in game.
const VENDOR = [
  2320, 2321, 4291, 8343, 14341, // threads: coarse, fine, silken, heavy silken, rune
  2880, 3466, 18567, // flux: weak, strong, elemental
  3371, 3372, 8925, 18256, // vials: empty, leaded, crystal, imbued
  2324, 2604, 2605, 6260, 4340, 4341, 2325, 6261, 4342, 10290, // bleach and the dyes
  4289, 2678, 2692, 3713, // salt; mild, hot and soothing spices
  159, 1179, 2596, 2894, 4536, // spring water, ice cold milk, dwarven stout, rhapsody malt, shiny red apple
  6217, 4470, 11291, 4399, 4400, 10647, 10648, // copper rod, simple and star wood, wooden and heavy stock, engineer's ink, blank parchment
];

const lua = (text) => `"${text.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
const pair = (en, de) => `{ ${lua(en)}, ${lua(de || en)} }`;
const byId = (rows) => Object.fromEntries(rows.map((r) => [r.ID, r]));

// `item*n+item*n` of a SpellReagents row, "" when it has none.
function reagents(row) {
  const out = [];
  for (let i = 0; row && i < REAGENTS; i++) {
    if (+row[`Reagent_${i}`] > 0 && +row[`ReagentCount_${i}`] > 0) out.push(`${row[`Reagent_${i}`]}*${row[`ReagentCount_${i}`]}`);
  }
  return out.join("+");
}

async function main() {
  const { build, cache } = await options();
  console.log(`WoW: Forever ${build}`);
  const [abilities, reagentRows, effects, sparse, lines, linesDe, categories, categoriesDe] = await Promise.all([
    table("SkillLineAbility", build, cache), table("SpellReagents", build, cache), table("SpellEffect", build, cache),
    table("ItemSparse", build, cache), table("SkillLine", build, cache), table("SkillLine", build, cache, "deDE"),
    table("TradeSkillCategory", build, cache), table("TradeSkillCategory", build, cache, "deDE"),
  ]);

  const line = byId(lines), lineDe = byId(linesDe), category = byId(categories), categoryDe = byId(categoriesDe);
  const item = byId(sparse);
  const all = ORDER.concat(GATHERING);
  for (const id of all) {
    if (!line[id] || !lineDe[id]) throw new Error(`no skill line ${id} in ${build}`);
  }
  // wago.tools could stop honouring the locale and hand out English: that shouldn't go unnoticed.
  if (all.every((id) => lineDe[id].DisplayName_lang === line[id].DisplayName_lang)) {
    throw new Error("the German SkillLine export is in English");
  }

  const reagentsOf = {};
  for (const r of reagentRows) reagentsOf[r.SpellID] = reagentsOf[r.SpellID] || r;
  const createOf = {};
  for (const e of effects) {
    if (e.Effect !== CREATE_ITEM) continue;
    const had = createOf[e.SpellID];
    if (!had || +e.EffectIndex < +had.EffectIndex) createOf[e.SpellID] = e;
  }

  const recipes = {}, seen = new Set(), usedCategories = new Set();
  for (const a of abilities) {
    const id = +a.SkillLine;
    if (!ORDER.includes(id) || seen.has(`${id}:${a.Spell}`)) continue;
    seen.add(`${id}:${a.Spell}`);
    const needs = reagents(reagentsOf[a.Spell]);
    if (!needs) continue;
    const create = createOf[a.Spell];
    const it = create && item[create.EffectItemType];
    const cat = +a.TradeSkillCategoryID || "";
    if (cat && !category[cat]) throw new Error(`no category ${cat} (spell ${a.Spell}) in ${build}`);
    if (cat) usedCategories.add(cat);
    (recipes[id] = recipes[id] || []).push({ spell: +a.Spell, text: [
      a.Spell,
      create ? create.EffectItemType : "",
      create ? Math.max(1, Math.round(+create.EffectBasePointsF)) : "",
      it ? it.InventoryType : "",
      it ? it.ItemLevel : "",
      it ? it.OverallQualityID : "",
      a.TrivialSkillLineRankLow,
      a.TrivialSkillLineRankHigh,
      cat,
      needs,
    ].join(":") });
  }

  // Every reagent some recipe uses, and what a vendor asks for one of them.
  const used = new Set();
  for (const id of ORDER) {
    for (const r of recipes[id] || []) for (const m of r.text.split(":")[9].matchAll(/(\d+)\*/g)) used.add(+m[1]);
  }
  const unitPrice = (id) => {
    const row = item[id];
    if (!row || !(+row.BuyPrice > 0)) throw new Error(`no buy price for the vendor reagent ${id} in ${build}`);
    return Math.round((+row.BuyPrice / Math.max(1, +row.VendorStackCount)) * 100) / 100;
  };

  const parents = lines.filter((l) => all.includes(+l.ParentSkillLineID)).sort((a, b) => a.ID - b.ID);
  const out = [
    "local _, ns = ...",
    "",
    `-- Generated by tools/update-recipes.js from wago.tools exports of WoW: Forever ${build}: don't edit by hand.`,
    "-- recipes[line]: \"recipe;recipe;...\", parsed only when needed. A recipe is",
    "-- spell:item:count:slot:ilvl:quality:low:high:cat:reagents, reagents being item*n+item*n: what it makes",
    "-- (empty when no item; count: the middle of the range when it varies), the item's InventoryType, ItemLevel",
    "-- and OverallQualityID (empty when ItemSparse doesn't have it), the skill where it turns yellow and grey",
    "-- (0: no such skill), its category (empty when none). names, categories: { English, German }. vendor[item]:",
    "-- what a trade-goods vendor asks for one of a reagent, in copper (a hand list of items, VENDOR in the tool).",
    "ns.RecipeData = {",
    `\tbuild = ${lua(build)},`,
    `\torder = { ${ORDER.join(", ")} },`,
    `\tgathering = { ${GATHERING.join(", ")} },`,
    "\tparents = {",
    ...parents.map((l) => `\t\t[${l.ID}] = ${l.ParentSkillLineID},`),
    "\t},",
    "\tnames = {",
    ...all.map((id) => `\t\t[${id}] = ${pair(line[id].DisplayName_lang, lineDe[id].DisplayName_lang)},`),
    "\t},",
    "\ticons = {",
    ...all.map((id) => `\t\t[${id}] = ${line[id].SpellIconFileID},`),
    "\t},",
    "\tcategories = {",
    ...[...usedCategories].sort((a, b) => a - b).map((c) => `\t\t[${c}] = ${pair(category[c].Name_lang, categoryDe[c] && categoryDe[c].Name_lang)},`),
    "\t},",
    "\tvendor = {",
    ...VENDOR.filter((id) => used.has(id)).sort((a, b) => a - b).map((id) => `\t\t[${id}] = ${unitPrice(id)},`),
    "\t},",
    "\trecipes = {",
    ...ORDER.map((id) => `\t\t[${id}] = "${(recipes[id] || []).sort((a, b) => a.spell - b.spell).map((r) => r.text).join(";")}",`),
    "\t},",
    "}",
    "",
  ];
  const target = path.join(__dirname, "..", "LefthyTools", "Data", "Recipes.lua");
  fs.writeFileSync(target, out.join("\r\n"));
  for (const id of ORDER) console.log(`  ${line[id].DisplayName_lang}: ${(recipes[id] || []).length}`);
  const count = ORDER.reduce((sum, id) => sum + (recipes[id] || []).length, 0);
  console.log(`${count} recipes, ${usedCategories.size} categories, ${fs.statSync(target).size} bytes -> ${path.relative(process.cwd(), target)}`);
}

main().catch((e) => { console.error(e); process.exit(1); });
