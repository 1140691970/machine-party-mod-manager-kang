import assert from "node:assert/strict";
import test from "node:test";
import {setImmediate as flush} from "node:timers/promises";

const storage = new Map();
globalThis.localStorage = {
  getItem: key => storage.get(key) ?? null,
  setItem: (key, value) => storage.set(key, value),
  removeItem: key => storage.delete(key)
};
globalThis.document = {querySelector: () => null};
globalThis.window = {__TAURI__: {core: {}}};

test("auto-upgrades outdated loader on scan, defers cleanly when game is running, and supports manual reload", async () => {
  const calls = [];
  let failRunning = true;
  const makeScan = (installedVersion, needsUpgrade) => ({
    installed: {},
    modStates: {},
    pckDir: "C:/Game",
    loader: {
      kind: "managed",
      installedVersion,
      targetVersion: "5",
      needsUpgrade,
      canReload: true
    }
  });

  window.__TAURI__.core.invoke = async (command, args) => {
    calls.push({command, args});
    if (command === "reload_loader") {
      if (failRunning) throw "gameRunning";
      return makeScan("5", false);
    }
    throw new Error("unexpected command: " + command);
  };

  const {state} = await import("../../apps/desktop/ui/state.js");
  const {applyValidation} = await import("../../apps/desktop/ui/game-folder.js");
  const {formatLoaderNote, runManualLoaderReload} = await import("../../apps/desktop/ui/loader-upgrade.js");

  state.game = "C:/Game";
  state.busyMod = "";
  state.installing = false;

  // 1. Outdated loader while game is running: defers politely without closing the game.
  applyValidation(makeScan("4", true), "C:/Game");
  await flush();
  await flush();
  assert.equal(calls.length, 1);
  assert.equal(calls[0].command, "reload_loader");
  assert.equal(calls[0].args.force, false);
  assert.equal(state.loaderNote?.key, "loaderWaitingGameClose");
  assert.equal(state.lastScan.loader.installedVersion, "4");

  // 2. Game closes and a subsequent scan arrives: auto-upgrades to v5 automatically.
  failRunning = false;
  applyValidation(makeScan("4", true), "C:/Game");
  await flush();
  await flush();
  assert.equal(calls.length, 2);
  assert.equal(calls[1].args.force, false);
  assert.equal(state.lastScan.loader.installedVersion, "5");
  assert.equal(state.lastScan.loader.needsUpgrade, false);
  assert.equal(state.loaderNote?.key, "loaderAutoUpgraded");
  assert.match(formatLoaderNote(state.loaderNote), /v5/);

  // 3. Manual reload forces a clean rewrite even when already up to date.
  await runManualLoaderReload(applyValidation);
  assert.equal(calls.length, 3);
  assert.equal(calls[2].args.force, true);
  assert.equal(state.loaderNote?.key, "loaderReloadDone");
  assert.match(formatLoaderNote(state.loaderNote), /v5/);
});
