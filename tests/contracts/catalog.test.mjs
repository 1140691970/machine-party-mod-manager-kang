import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { searchText, sortMods, visibleMods } from "../../apps/desktop/ui/catalog.js";
import { locales } from "../../apps/desktop/ui/languages.js";

const catalog = JSON.parse(await readFile(new URL("../../catalog/mods.json", import.meta.url), "utf8"));

test("every catalog entry has a stable identity and complete translations", () => {
  assert.equal(catalog.schema, 1);
  const unique = key => new Set(catalog.mods.map(mod => mod[key])).size === catalog.mods.length;
  assert.ok(unique("id") && unique("order") && unique("repo"));
  for (const mod of catalog.mods) {
    assert.match(mod.id, /^[a-z0-9-]+$/);
    assert.match(mod.repo, /^[\w.-]+\/[\w.-]+$/);
    assert.ok(Number.isInteger(mod.order) && mod.order > 0);
    assert.equal(typeof mod.verified, "boolean");
    assert.ok(Array.isArray(mod.aliases));
    for (const field of ["name", "summary", "detail"])
      assert.deepEqual(Object.keys(mod[field]).sort(), [...locales].sort(), `${mod.id}.${field}`);
  }
});

test("images referenced by the catalog ship with the UI", async () => {
  for (const mod of catalog.mods.filter(mod => mod.image))
    await readFile(new URL(`../../apps/desktop/ui/images/${mod.image}.png`, import.meta.url));
});

test("search keeps catalog order and matches names, aliases and every language", () => {
  const mods = sortMods(catalog);
  const ids = (query, inventory = {}) =>
    visibleMods(mods, {page: "catalog", query, inventory}).map(mod => mod.id);
  assert.deepEqual(ids(""), mods.map(mod => mod.id));
  assert.deepEqual(ids("mpml"), ["machineparty-plus"]);
  assert.deepEqual(ids("eight-player"), ["binary1936-8p"]);
  assert.deepEqual(ids("直播"), ["broadcast-8p-freecam"]);
  assert.deepEqual(ids("nothing-matches"), []);
  assert.ok(searchText(mods[0]).includes("darkjadestone"));
});

test("the installed page lists only mods recorded for the selected copy", () => {
  const mods = sortMods(catalog);
  const inventory = {"Ghostx10742/MachineParty-Plus": "v2.0.0"};
  const shown = visibleMods(mods, {page: "installed", query: "ignored", inventory});
  assert.deepEqual(shown.map(mod => mod.id), ["machineparty-plus"]);
});

test("overtime declares a valid upstream-cli adapter profile", () => {
  const overtime = catalog.mods.find(mod => mod.id === "overtime");
  assert.equal(overtime.adapter.kind, "upstream-cli");
  assert.deepEqual(overtime.adapter.platforms, ["windows"]);
  assert.equal(overtime.adapter.target, "pckDir");
  assert.equal(overtime.adapter.exclusive, "pck");
  assert.equal(overtime.adapter.run.interpreter, "exe");
  assert.equal(overtime.adapter.run.program, "overtime_install.exe");
  assert.ok(overtime.adapter.forbiddenArgs.includes("--force"));
  assert.ok(!overtime.adapter.run.common.includes("--force"));
  assert.ok(!overtime.adapter.actions.install.includes("--force"));
});
