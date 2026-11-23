import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { checkArchitecture, checkSharedModParity, checkSource } from "../../scripts/check_architecture.mjs";
import { SHARED_MOD_SYNC_SPEC, syncSharedModFiles } from "../../scripts/pack-mod.mjs";

test("the repository satisfies its boundaries", async () => {
  const result = await checkArchitecture();
  assert.deepEqual(result.errors, []);
  assert.ok(result.files > 10);
});

test("only bridge.js may reach Tauri from the UI", () => {
  assert.equal(checkSource("apps/desktop/ui/bridge.js", "window.__TAURI__.core").length, 0);
  assert.match(checkSource("apps/desktop/ui/app.js", "window.__TAURI__.core.invoke('x')")[0], /bridge\.js/);
});

test("the UI cannot import outside its directory or Node built-ins", () => {
  assert.equal(checkSource("apps/desktop/ui/app.js", 'import { t } from "./state.js";').length, 0);
  assert.match(checkSource("apps/desktop/ui/app.js", 'import w from "../../../services/update-worker/app-updates.mjs";')[0], /desktop UI imports/);
  assert.match(checkSource("apps/desktop/ui/app.js", 'import fs from "node:fs";')[0], /desktop UI imports/);
});

test("domain modules stay independent of Tauri", () => {
  assert.equal(checkSource("apps/desktop/src-tauri/src/game.rs", "use std::fs;").length, 0);
  assert.match(checkSource("apps/desktop/src-tauri/src/inventory.rs", "use tauri::Manager;")[0], /depends on Tauri/);
  assert.match(checkSource("apps/desktop/src-tauri/src/installer/zip.rs", "use tauri::Manager;")[0], /depends on Tauri/);
  assert.match(checkSource("apps/desktop/src-tauri/src/pck_loader/gdpc.rs", "use tauri_plugin_updater::UpdaterExt;")[0], /depends on Tauri/);
  assert.match(checkSource("apps/desktop/src-tauri/src/installer/update.rs", "use crate::commands;")[0], /depends on Tauri/);
  assert.equal(checkSource("apps/desktop/src-tauri/src/commands.rs", "use tauri::AppHandle;").length, 0);
  assert.equal(checkSource("apps/desktop/src-tauri/src/app_updates.rs", "use tauri::AppHandle;").length, 0);
  assert.match(checkSource("apps/desktop/src-tauri/src/main.rs", "#[tauri::command]\nfn x() {}")[0], /commands belong/);
});

test("tests may not patch and run production source", () => {
  const patched = 'const s = await readFile("x.js"); await writeFile("y.js", s.replace("a", "b"));';
  assert.match(checkSource("tests/ui/x.test.mjs", patched)[0], /rewrite production source/);
  const evaluated = 'const s = await readFile("x.js"); new Function(s.replace("a", "b"))();';
  assert.match(checkSource("tests/ui/x.test.mjs", evaluated)[0], /rewrite production source/);
  const parsing = 'const s = (await readFile("README.md")).replace(/```/g, "");';
  assert.equal(checkSource("tests/contracts/docs.test.mjs", parsing).length, 0);
});

test("shared mod files match canonical mods/_shared sources and sync cleanly", async t => {
  assert.deepEqual(await checkSharedModParity(), []);
  const tmp = await mkdtemp(path.join(os.tmpdir(), "shared-mod-parity-"));
  t.after(() => rm(tmp, {recursive: true, force: true}));
  for (const {source, targets} of SHARED_MOD_SYNC_SPEC) {
    await mkdir(path.dirname(path.join(tmp, source)), {recursive: true});
    await writeFile(path.join(tmp, source), "extends RefCounted\n");
    for (const target of targets) {
      await mkdir(path.dirname(path.join(tmp, target)), {recursive: true});
      await writeFile(path.join(tmp, target), "extends RefCounted\n");
    }
  }
  assert.deepEqual(await checkSharedModParity(tmp), []);
  await writeFile(path.join(tmp, SHARED_MOD_SYNC_SPEC[0].targets[0]), "drifted\n");
  assert.match((await checkSharedModParity(tmp))[0], /out of sync/);
  const updated = await syncSharedModFiles(tmp);
  assert.deepEqual(updated, [SHARED_MOD_SYNC_SPEC[0].targets[0]]);
  assert.deepEqual(await checkSharedModParity(tmp), []);
});
