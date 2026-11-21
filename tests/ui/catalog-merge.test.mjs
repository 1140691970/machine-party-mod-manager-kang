import test from "node:test";
import assert from "node:assert/strict";
import { mergeBundled, sortMods, visibleMods } from "../../apps/desktop/ui/catalog.js";

const entry = (id, order, name = id, version = "v0.1.0") => ({
  id, order, repo: `JamesGZM/${id}`, version, verified: false, aliases: [],
  name: {"zh-CN": name, "zh-TW": name, "en": name},
  summary: {"zh-CN": name, "zh-TW": name, "en": name},
  detail: {"zh-CN": name, "zh-TW": name, "en": name},
});
const catalog = mods => ({schema: 1, revision: "remote", mods});

test("a built-in-only mod is appended and becomes visible in the manager", () => {
  const remote = catalog([entry("bubble-blitz", 1, "泡泡爆破")]);
  const bundled = catalog([entry("bubble-blitz", 1, "泡泡爆破"), entry("spike-ring", 10, "尖刺圆环")]);
  const merged = mergeBundled(remote, bundled);
  assert.deepEqual(merged.mods.map(mod => mod.id), ["bubble-blitz", "spike-ring"]);
  // remote entries must not be replaced by built-in copies
  assert.equal(merged.mods[0], remote.mods[0]);
  const rows = sortMods(merged, bundled.mods);
  assert.deepEqual(rows.map(mod => mod.id), ["bubble-blitz", "spike-ring"]);
  assert.equal(visibleMods(rows, {query: "尖刺圆环"}).length, 1);
  assert.equal(visibleMods(rows, {query: "圆环"}).length, 1);
});

test("online entry wins when both catalogs contain the same id", () => {
  const remote = catalog([entry("spike-ring", 10, "尖刺圆环", "v0.2.0")]);
  const bundled = catalog([entry("spike-ring", 10, "尖刺圆环", "v0.1.0")]);
  const merged = mergeBundled(remote, bundled);
  assert.equal(merged.mods.length, 1);
  assert.equal(merged.mods[0].version, "v0.2.0");
});

test("built-in catalog is the offline fallback when no signed catalog exists", () => {
  const bundled = catalog([entry("spike-ring", 10, "尖刺圆环")]);
  assert.equal(mergeBundled(null, bundled), bundled);
  assert.equal(mergeBundled(undefined, bundled), bundled);
  assert.deepEqual(sortMods(mergeBundled(null, bundled), bundled.mods).map(m => m.id), ["spike-ring"]);
});

test("a built-in catalog already covered by the online one is returned unchanged", () => {
  const remote = catalog([entry("bubble-blitz", 1), entry("spike-ring", 10)]);
  const bundled = catalog([entry("bubble-blitz", 1), entry("spike-ring", 10)]);
  assert.equal(mergeBundled(remote, bundled), remote);
});
