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

test("prompts once to close the game when auto-upgrade hits gameRunning, then completes reload on confirmation", async () => {
  const calls = [];
  let running = true;
  const path = "D:/Game2";
  const dir = path + "/Machine Party_Windows";
  const makeScan = (installedVersion, needsUpgrade) => ({
    installed: {},
    modStates: {},
    pckDir: dir,
    loader: {
      kind: "managed",
      installedVersion,
      targetVersion: "6",
      needsUpgrade,
      canReload: true
    }
  });

  function makeNode(tag) {
    return {
      tag,
      className: "",
      textContent: "",
      children: [],
      open: false,
      get childElementCount() { return this.children.length; },
      matches: sel => (sel === ".btn" && tag === "button") || (sel === ".btn-link" && false),
      append(...items) { this.children.push(...items); },
      replaceChildren(...items) { this.children = items; },
      querySelector() { return {focus() {}}; },
      setAttribute() {},
      addEventListener() {},
      showModal() { this.open = true; },
      close() { this.open = false; },
      remove() {}
    };
  }

  const mainDialog = makeNode("dialog");
  const titleEl = makeNode("h2");
  const bodyEl = makeNode("div");
  const body = makeNode("body");
  globalThis.document = {
    body,
    createElement: makeNode,
    querySelector: sel => {
      if (sel === "#dialogTitle") return titleEl;
      if (sel === "#dialogBody") return bodyEl;
      if (sel === "dialog[open]") return mainDialog.open ? mainDialog : null;
      if (sel === "dialog") return mainDialog;
      return null;
    }
  };

  window.__TAURI__.core.invoke = async (command, args) => {
    calls.push({command, args});
    if (command === "reload_loader") {
      if (running) throw "gameRunning";
      return makeScan("6", false);
    }
    if (command === "game_process") {
      if (args.action === "close") running = false;
      return running;
    }
    throw new Error("unexpected command: " + command);
  };

  const {state} = await import("../../apps/desktop/ui/state.js");
  const {applyValidation} = await import("../../apps/desktop/ui/game-folder.js");
  state.game = path;
  state.pckDir = dir;
  state.busyMod = "";
  state.installing = false;

  // 1. Auto-upgrade sees gameRunning -> opens guidance dialog once.
  applyValidation(makeScan("5", true), path);
  await flush();
  await flush();
  assert.equal(mainDialog.open, true);
  assert.match(titleEl.textContent, /升级|升級|update/i);
  const actionsRow = bodyEl.children.at(-1);
  assert.equal(actionsRow.children.length, 2);

  // 2. Clicking "Close game and upgrade" opens confirmGameExit; confirming closes game and upgrades to v6.
  const confirmPromise = actionsRow.children[1].onclick();
  await flush();
  assert.equal(mainDialog.open, false);
  const exitModal = body.children.at(-1);
  assert.ok(exitModal?.open);
  const exitButtons = exitModal.children[1].children[1].children;
  await exitButtons[1].onclick();
  await confirmPromise;

  assert.equal(state.lastScan.loader.installedVersion, "6");
  assert.equal(state.lastScan.loader.needsUpgrade, false);
  assert.equal(state.loaderNote?.key, "loaderReloadDone");
  assert.ok(calls.some(c => c.command === "game_process" && c.args.action === "close"));

  // 3. Re-scanning the same version pair while game is running won't re-open the prompt.
  running = true;
  applyValidation(makeScan("5", true), path);
  await flush();
  await flush();
  assert.equal(mainDialog.open, false);
});
