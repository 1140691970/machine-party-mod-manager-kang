import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { lintAllMods, lintModSource } from "../../scripts/mod-lint.mjs";

const ROOT = path.resolve(fileURLToPath(new URL("../../", import.meta.url)));

test("lintModSource flags get_property_list() inside hot-path functions only", () => {
  const bad = [
    "extends RefCounted",
    "func _ready() -> void:",
    "\tvar ok := get_property_list()",
    "func _process(_delta: float) -> void:",
    "\tvar bad := get_property_list()",
    "func _physics_process(_delta: float) -> void:",
    "\tvar bad2 = node.get_property_list()",
    "func _node_added(n: Node) -> void:",
    "\tvar bad3 = n.get_property_list()"
  ].join("\n");

  const issues = lintModSource("mods/demo/main.gd", bad);
  assert.equal(issues.length, 3);
  assert.deepEqual(issues.map(i => i.line), [5, 7, 9]);
  assert.ok(issues.every(i => i.rule === "no-hot-path-property-list"));
});

test("lintModSource flags untyped := with Variant-returning calls unless cast or compared", () => {
  const src = [
    "func test(obj: Object, d: Dictionary, n: Node) -> void:",
    "\tvar a := obj.call(\"foo\")",
    "\tvar b := d.get(\"k\")",
    "\tvar c := n.get_meta(\"m\")",
    "\tvar ok1 := d.get(\"k\") as Node3D",
    "\tvar ok2: Dictionary = obj.call(\"foo\")",
    "\tvar ok3 := int(d.get(\"k\", 0)) == 1",
    "\tvar ok4 := d.get(\"flag\") == true"
  ].join("\n");

  const issues = lintModSource("mods/demo/main.gd", src);
  assert.equal(issues.length, 3);
  assert.deepEqual(issues.map(i => i.line), [2, 3, 4]);
  assert.ok(issues.every(i => i.rule === "no-variant-infer-assign"));
});

test("lintModSource flags preload(\"res://...gd\") in non-override scripts only", () => {
  const src = 'var Helper := preload("res://helper.gd")\n';

  const mainIssues = lintModSource("mods/demo/main.gd", src);
  assert.equal(mainIssues.length, 1);
  assert.equal(mainIssues[0].rule, "no-mod-preload");

  const overrideIssues = lintModSource("mods/demo/override_game.gd", src);
  assert.equal(overrideIssues.length, 0);
});

test("lintAllMods flags duplicate TARGET_SLOT_ID and invalid mod.json manifests", async () => {
  const tmp = await mkdtemp(path.join(os.tmpdir(), "mpm-lint-"));
  try {
    await mkdir(path.join(tmp, "mods", "alpha"), { recursive: true });
    await mkdir(path.join(tmp, "mods", "beta"), { recursive: true });
    await mkdir(path.join(tmp, "mods", "broken"), { recursive: true });

    await writeFile(path.join(tmp, "mods", "alpha", "mod.json"), JSON.stringify({
      id: "alpha",
      version: "0.1.0",
      entry: "main.gd"
    }));
    await writeFile(path.join(tmp, "mods", "alpha", "main.gd"), "const TARGET_SLOT_ID := 17\n# mpm_local_player\n");

    await writeFile(path.join(tmp, "mods", "beta", "mod.json"), JSON.stringify({
      id: "beta",
      version: "0.1.0",
      entry: "main.gd"
    }));
    await writeFile(path.join(tmp, "mods", "beta", "main.gd"), "const TARGET_SLOT_ID := 17\n");

    await writeFile(path.join(tmp, "mods", "broken", "mod.json"), JSON.stringify({
      id: "wrong-id",
      version: "",
      entry: "missing.gd"
    }));

    const res = await lintAllMods(tmp);
    const rules = res.issues.map(i => i.rule);
    assert.ok(rules.includes("unique-target-slot-id"));
    assert.ok(rules.includes("minigame-local-player-meta"));
    assert.ok(rules.filter(r => r === "valid-mod-manifest").length >= 3);
  } finally {
    await rm(tmp, { recursive: true, force: true });
  }
});

test("lintAllMods passes cleanly across all shipped first-party mods", async () => {
  const res = await lintAllMods(ROOT);
  assert.ok(res.modCount >= 8, `expected >= 8 mods, got ${res.modCount}`);
  assert.deepEqual(res.issues, []);
});
