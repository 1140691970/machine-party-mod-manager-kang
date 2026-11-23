import test from "node:test";
import assert from "node:assert/strict";
import { access, mkdtemp, mkdir, readdir, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { checkMod, scaffoldMod, syncCatalogMod } from "../../scripts/mod-cli.mjs";
import { lintModDirectory } from "../../scripts/mod-lint.mjs";

const ROOT = path.resolve(fileURLToPath(new URL("../../", import.meta.url)));
const BUNDLED_GODOT = path.join(ROOT, ".agent/mod-dev/tools/Godot.app/Contents/MacOS/Godot");

async function hasBundledGodot() {
  try {
    await access(BUNDLED_GODOT);
    return true;
  } catch {
    return false;
  }
}

test("scaffoldMod generates lint-clean tool, minigame, and graphics templates", async () => {
  const tmp = await mkdtemp(path.join(os.tmpdir(), "mpm-cli-scaffold-"));
  try {
    const toolRes = await scaffoldMod({ id: "sample-tool", template: "tool", rootDir: tmp });
    const miniRes = await scaffoldMod({ id: "sample-mini", template: "minigame", slotId: 77, rootDir: tmp });
    const dynMiniRes = await scaffoldMod({ id: "sample-dyn", template: "minigame", rootDir: tmp });
    const gfxRes = await scaffoldMod({ id: "sample-gfx", template: "graphics", rootDir: tmp });

    assert.ok(toolRes.files.includes("main.gd"));
    assert.ok(miniRes.files.includes("sample_mini_game.gd"));
    assert.ok(dynMiniRes.files.includes("sample_dyn_game.gd"));
    assert.ok(miniRes.files.includes("run_mac.sh"));
    assert.ok(gfxRes.files.includes("mod.json"));

    for (const id of ["sample-tool", "sample-mini", "sample-dyn", "sample-gfx"]) {
      const lint = await lintModDirectory(id, tmp);
      assert.deepEqual(lint.issues, [], `expected 0 lint issues for ${id}`);
      const check = await checkMod({ id, rootDir: tmp, runGodot: false });
      assert.equal(check.ok, true);
      assert.equal(check.packed.filename, `${id}-0.1.0.zip`);
      assert.ok(check.packed.size > 0);
    }

    const miniMain = await readFile(path.join(tmp, "mods", "sample-mini", "main.gd"), "utf8");
    assert.match(miniMain, /const TARGET_SLOT_ID := 77/);
    const dynMain = await readFile(path.join(tmp, "mods", "sample-dyn", "main.gd"), "utf8");
    assert.match(dynMain, /register_minigame/);
  } finally {
    await rm(tmp, { recursive: true, force: true });
  }
});

test("syncCatalogMod updates version, package hash/size, and requiredFiles in catalog/mods.json", async () => {
  const tmp = await mkdtemp(path.join(os.tmpdir(), "mpm-cli-sync-"));
  try {
    await scaffoldMod({ id: "sync-demo", template: "tool", rootDir: tmp });
    await mkdir(path.join(tmp, "catalog"), { recursive: true });
    await writeFile(
      path.join(tmp, "catalog", "mods.json"),
      JSON.stringify({
        schemaVersion: 1,
        mods: [
          {
            id: "sync-demo",
            version: "0.0.1",
            package: { filename: "old.zip", size: 1, sha256: "0".repeat(64) },
            adapter: { requiredFiles: ["old.gd"] }
          }
        ]
      }, null, 2) + "\n"
    );

    const synced = await syncCatalogMod({ id: "sync-demo", rootDir: tmp });
    assert.equal(synced.version, "0.1.0");
    assert.equal(synced.filename, "sync-demo-0.1.0.zip");

    const updated = JSON.parse(await readFile(path.join(tmp, "catalog", "mods.json"), "utf8"));
    const entry = updated.mods[0];
    assert.equal(entry.version, "v0.1.0");
    assert.equal(entry.package.filename, "sync-demo-0.1.0.zip");
    assert.equal(entry.package.size, synced.size);
    assert.equal(entry.package.sha256, synced.sha256);
    assert.deepEqual(entry.adapter.requiredFiles, ["main.gd", "mod.json"]);
  } finally {
    await rm(tmp, { recursive: true, force: true });
  }
});

test("checkMod runs Godot headless --check-only on scaffolded mod and cleans .gd.uid files", async t => {
  if (process.platform !== "darwin" || !(await hasBundledGodot())) {
    t.skip("Bundled macOS Godot binary not present");
    return;
  }

  const tmp = await mkdtemp(path.join(os.tmpdir(), "mpm-cli-godot-"));
  try {
    await scaffoldMod({ id: "godot-demo", template: "tool", rootDir: tmp });
    const res = await checkMod({ id: "godot-demo", rootDir: tmp, godotPath: BUNDLED_GODOT, runGodot: true });
    assert.equal(res.godotChecked, true);
    assert.equal(res.ok, true);

    await scaffoldMod({ id: "godot-mini", template: "minigame", slotId: 88, rootDir: tmp });
    const miniRes = await checkMod({
      id: "godot-mini",
      rootDir: tmp,
      godotPath: BUNDLED_GODOT,
      runGodot: true,
      runSelfTest: true
    });
    assert.equal(miniRes.godotChecked, true);
    assert.equal(miniRes.selfTestPassed, true);

    const entries = await readdir(path.join(tmp, "mods", "godot-demo"));
    assert.equal(entries.some(name => name.endsWith(".gd.uid")), false);
  } finally {
    await rm(tmp, { recursive: true, force: true });
  }
});
