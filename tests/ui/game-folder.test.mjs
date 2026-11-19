import assert from "node:assert/strict";
import test from "node:test";
import {setImmediate as flush} from "node:timers/promises";

const storage = new Map();
globalThis.localStorage = {
  getItem:key => storage.get(key) ?? null,
  setItem:(key,value) => storage.set(key,value),
  removeItem:key => storage.delete(key)
};
globalThis.window = {__TAURI__:{core:{}}};

test("a late scan cannot replace a new copy or turn a failed scan into an uninstall action", async () => {
  const scans = new Map();
  let selected = "copy A";
  window.__TAURI__.core.invoke = async (command, {path} = {}) => {
    if (command === "find_games") return [selected];
    if (command === "installed_versions") return {[path]:"v1.7"};
    if (command === "validate_game_mods") {
      assert.ok(!scans.has(path), "only one scan per copy");
      const pending = Promise.withResolvers();
      scans.set(path,pending);
      return pending.promise;
    }
  };
  const {state} = await import("../../apps/desktop/ui/state.js");
  const {detectGame,syncGameMods} = await import("../../apps/desktop/ui/game-folder.js");
  const a = detectGame();
  await flush();
  assert.deepEqual(state.inventory, {"copy A":"v1.7"});
  assert.equal(state.scan,"checking");
  const repeat = syncGameMods();
  selected = "copy B";
  const b = detectGame();
  await flush();
  scans.get("copy B").reject(Error("fileReadError"));
  await b;
  scans.get("copy A").resolve({installed:{},pckDir:"A",modStates:{overtime:"manualInstall"}});
  await Promise.all([a,repeat]);
  assert.equal(state.game,"copy B");
  assert.equal(state.scan,"failed");
  assert.deepEqual(state.inventory, {"copy B":"v1.7"});
  assert.deepEqual(state.modStates,{});
});

test("an install resolves its game copy before continuing and cancellation does no package work", async () => {
  const {state} = await import("../../apps/desktop/ui/state.js");
  const {withGameCopy} = await import("../../apps/desktop/ui/game-folder.js");
  const calls = [];
  let picked = null;
  const copy = "Steam/中文 遊戲";
  const matches = [copy];
  const dialog = {close() {}};
  globalThis.document = {querySelector:() => dialog};
  window.__TAURI__.core.invoke = async (command, {path} = {}) => {
    calls.push(command);
    if (command === "choose_game") return picked;
    if (command === "game_copies") return path === "missing" ? [] : matches;
    if (command === "validate_game_mods") return {installed:{},modStates:{overtime:"vanilla"},pckDir:copy};
    if (command === "installed_versions") return {};
    assert.equal(command, "save_game");
  };
  const install = () => { assert.equal(state.pckDir, copy); calls.push("install"); };
  state.game = "";
  await withGameCopy(install);
  assert.deepEqual(calls.splice(0), ["choose_game"]);
  picked = copy;
  await withGameCopy(install);
  assert.deepEqual(calls.splice(0), ["choose_game","game_copies","save_game","installed_versions","validate_game_mods","install"]);
  await withGameCopy(install);
  assert.deepEqual(calls.splice(0), ["game_copies","installed_versions","validate_game_mods","install"]);
  state.game = "missing";
  picked = null;
  await withGameCopy(install);
  assert.deepEqual(calls, ["game_copies","choose_game"]);
});

test("an open app rechecks a reinstalled Steam copy before using its old action", async () => {
  const {state} = await import("../../apps/desktop/ui/state.js");
  const {withGameCopy} = await import("../../apps/desktop/ui/game-folder.js");
  const path = "Steam/Machine Party";
  const pckDir = path + "/Machine Party_Windows";
  Object.assign(state, {game:path, pckDir, scan:"ready", modStates:{roller:"installed"}});
  let disk = "vanilla";
  window.__TAURI__.core.invoke = async command => {
    if (command === "game_copies") return [pckDir];
    if (command === "installed_versions") return {roller:"v1"};
    assert.equal(command, "validate_game_mods");
    if (!disk) throw "statusUnavailable";
    return {pckDir, installed:{}, modStates:{roller:disk}};
  };
  let actions = 0;
  await withGameCopy(() => { actions++; assert.equal(state.modStates.roller, "vanilla"); });
  assert.deepEqual(state.inventory, {});
  disk = null;
  await withGameCopy(() => { actions++; });
  assert.equal(actions, 1);
  assert.equal(state.scan, "failed");
});

test("reload restores inventory for a valid saved copy when Steam detection returns no candidates", async () => {
  const {state} = await import("../../apps/desktop/ui/state.js");
  const {detectGame} = await import("../../apps/desktop/ui/game-folder.js");
  state.game = "saved/copy";
  const installed = {"author/project":"v1"};
  window.__TAURI__.core.invoke = async command => {
    if (command === "find_games") return [];
    if (command === "game_copies") return [state.game];
    if (command === "installed_versions") return installed;
    assert.equal(command, "validate_game_mods");
    return {installed, pckDir:state.game, modStates:{project:"installed"}};
  };
  await detectGame();
  assert.deepEqual(state.inventory, installed);
  assert.equal(state.scan, "ready");
});

test("rescan preserves an existing valid game folder when no Steam installs are detected", async () => {
  const {state} = await import("../../apps/desktop/ui/state.js");
  const {detectGame} = await import("../../apps/desktop/ui/game-folder.js");
  const existing = "D:/Games/Machine Party";
  state.game = existing;
  state.pckDir = existing + "/Machine Party_Windows";
  state.scan = "ready";
  localStorage.setItem("game-path", existing);
  const dialog = {open: false, showModal() { this.open = true; }, close() { this.open = false; }};
  const nodes = new Map([["dialog", dialog], ["#dialogTitle", {}], ["#dialogBody", {replaceChildren() {}}]]);
  const makeNode = tag => ({
    tag, className: "", textContent: "", children: [],
    matches: sel => sel === ".btn" && tag === "button",
    append(...items) { this.children.push(...items); },
    prepend(...items) { this.children.unshift(...items); },
    setAttribute() {}
  });
  globalThis.document = {
    querySelector: sel => nodes.get(sel) ?? makeNode("div"),
    createElement: makeNode,
    createElementNS: () => makeNode("svg")
  };
  window.__TAURI__.core.invoke = async (command, {path} = {}) => {
    if (command === "find_games") return [];
    if (command === "game_copies") return path === existing ? [state.pckDir] : [];
  };
  await detectGame(true);
  assert.equal(state.game, existing);
  assert.equal(localStorage.getItem("game-path"), existing);
  assert.equal(dialog.open, true);
});
