import test from "node:test";
import assert from "node:assert/strict";
import { catalogCategories, dependentsOf, isLibraryMod, resolveDependencies, visibleMods } from "../../apps/desktop/ui/catalog.js";
import { validCatalog } from "../../apps/desktop/ui/online-catalog.js";

test("resolveDependencies orders topological DAG and rejects cycles, missing and old versions", () => {
  const mods = [
    {id: "mpm-core", order: 1, role: "library", version: "v0.2.0", requires: []},
    {id: "mid", order: 2, role: "library", version: "v0.1.0", requires: [{id: "mpm-core", minVersion: "v0.1.0"}]},
    {id: "leaf", order: 3, version: "v0.1.0", requires: [{id: "mid"}, {id: "mpm-core", minVersion: "v0.2.0"}]}
  ];
  assert.equal(isLibraryMod(mods[0]), true);
  assert.equal(isLibraryMod(mods[2]), false);

  const ok = resolveDependencies("leaf", mods);
  assert.equal(ok.error, undefined);
  assert.deepEqual(ok.order.map(m => m.id), ["mpm-core", "mid", "leaf"]);

  assert.equal(resolveDependencies("leaf", mods.slice(1)).error, "dependencyMissing");
  assert.equal(resolveDependencies("leaf", [
    {id: "mpm-core", order: 1, role: "library", version: "v0.1.0", requires: []},
    ...mods.slice(1)
  ]).error, "dependencyVersion");
  assert.equal(resolveDependencies("a", [
    {id: "a", order: 1, version: "v0.1.0", requires: [{id: "b"}]},
    {id: "b", order: 2, version: "v0.1.0", requires: [{id: "a"}]}
  ]).error, "dependencyCycle");
});

test("dependentsOf finds installed mods requiring a library mod", () => {
  const mods = [
    {id: "mpm-core", role: "library", requires: []},
    {id: "game-a", requires: [{id: "mpm-core"}]},
    {id: "game-b", requires: []}
  ];
  assert.deepEqual(dependentsOf("mpm-core", mods, ["mpm-core", "game-a", "game-b"]).map(m => m.id), ["game-a"]);
});

test("validCatalog accepts optional role and requires and rejects malformed entries", () => {
  const base = {
    schema: 1,
    revision: "2026-11-23.test",
    mods: [{
      id: "mpm-core",
      order: 1,
      repo: "JamesGZM/machine-party-mod-manager",
      verified: false,
      role: "library",
      requires: [],
      aliases: ["core"],
      name: {"zh-CN": "核心", "zh-TW": "核心", en: "Core"},
      summary: {"zh-CN": "核心", "zh-TW": "核心", en: "Core"},
      detail: {"zh-CN": "核心", "zh-TW": "核心", en: "Core"}
    }]
  };
  assert.equal(validCatalog(base), true);
  assert.equal(validCatalog({...base, mods: [{...base.mods[0], role: "unknown"}]}), false);
  assert.equal(validCatalog({...base, mods: [{...base.mods[0], requires: [{id: "Bad ID"}]}]}), false);
});

test("visibleMods and catalogCategories hide library mods from player-facing browse views", () => {
  const mods = [
    {id: "mpm-core", role: "library", category: "library", name: {"zh-CN": "核心", "zh-TW": "核心", en: "Core"}},
    {id: "roller-carnival", category: "game", name: {"zh-CN": "滚筒", "zh-TW": "滾筒", en: "Roller"}}
  ];
  assert.deepEqual(catalogCategories(mods), ["game"]);
  assert.deepEqual(visibleMods(mods, {}).map(m => m.id), ["roller-carnival"]);
  assert.deepEqual(visibleMods(mods, {includeLibraries: true}).map(m => m.id), ["mpm-core", "roller-carnival"]);
});
