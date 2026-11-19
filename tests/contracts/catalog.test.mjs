import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { searchText, sortMods, visibleMods } from "../../apps/desktop/ui/catalog.js";
import { locales } from "../../apps/desktop/ui/languages.js";
import { packMod } from "../../scripts/pack-mod.mjs";

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

test("every catalog mod declares a valid Windows adapter profile", () => {
  assert.equal(catalog.repo, "JamesGZM/machine-party-mod-manager");
  for (const mod of catalog.mods) {
    assert.equal(mod.windowsPreview, "0.1.2-5", mod.id);
    assert.deepEqual(mod.adapter.platforms, ["windows"], mod.id);
    assert.equal(mod.adapter.target, "pckDir", mod.id);
    assert.ok(mod.adapter.exclusive, mod.id);
    if (mod.adapter.kind === "upstream-cli") {
      assert.ok(mod.adapter.forbiddenArgs.includes("--force"), mod.id);
      assert.ok(!mod.adapter.run.common.includes("--force"), mod.id);
      assert.ok(!mod.adapter.actions.install.includes("--force"), mod.id);
    } else {
      assert.equal(mod.adapter.kind, "loader-files", mod.id);
      assert.deepEqual(mod.adapter.touches, ["mods"], mod.id);
    }
  }
  const overtime = catalog.mods.find(mod => mod.id === "overtime");
  assert.equal(overtime.adapter.kind, "upstream-cli");
  assert.equal(overtime.adapter.exclusive, "pck");
  assert.equal(overtime.adapter.run.interpreter, "exe");
  assert.equal(overtime.adapter.run.program, "overtime_install.exe");

  const roller = catalog.mods.find(mod => mod.id === "roller-carnival");
  assert.equal(roller.firstParty, true);
  assert.equal(roller.package.filename, "roller-carnival-0.1.0.zip");
  assert.equal(roller.package.mirrorApproved, true);
  assert.equal(roller.adapter.kind, "loader-files");
  assert.equal(roller.adapter.autoLoader, true);
});

test("every first-party mod has matching manifest, README and deterministic ZIP package", async () => {
  for (const mod of catalog.mods.filter(item => item.firstParty)) {
    const manifestUrl = new URL(`../../mods/${mod.id}/mod.json`, import.meta.url);
    const manifest = JSON.parse(await readFile(manifestUrl, "utf8"));
    assert.equal(manifest.id, mod.id, `${mod.id}: mod.json id mismatch`);
    assert.equal(`v${manifest.version}`, mod.version, `${mod.id}: mod.json version mismatch`);
    assert.equal(typeof manifest.entry, "string", `${mod.id}: mod.json entry missing`);
    assert.ok(manifest.entry.length > 0, `${mod.id}: mod.json entry empty`);
    await readFile(new URL(`../../mods/${mod.id}/${manifest.entry}`, import.meta.url), "utf8");

    const readme = await readFile(new URL(`../../mods/${mod.id}/README.md`, import.meta.url), "utf8");
    assert.ok(readme.trim().length > 0, `${mod.id}: README.md must not be empty`);

    const packed = await packMod(mod.id);
    assert.equal(packed.filename, mod.package.filename, `${mod.id}: ZIP filename mismatch`);
    assert.equal(packed.size, mod.package.size, `${mod.id}: ZIP size mismatch`);
    assert.equal(packed.sha256, mod.package.sha256, `${mod.id}: ZIP sha256 mismatch`);
    assert.deepEqual([...mod.adapter.requiredFiles].sort(), [...packed.files].sort(), `${mod.id}: requiredFiles mismatch`);
  }
});

test("the preview displays exactly the remotely supplied catalog rows and metadata", () => {
  const preview = catalog.mods.find(mod => mod.windowsPreview === "0.1.2-5");
  const live = {...preview, name:{...preview.name,en:"Updated online"}};
  assert.equal(sortMods({mods:[live]})[0], live);
  assert.deepEqual(sortMods({mods:[]}), []);
});
