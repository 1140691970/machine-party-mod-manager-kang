import assert from "node:assert/strict";
import test from "node:test";
import { checkArchitecture, checkSource } from "../../scripts/check_architecture.mjs";

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
