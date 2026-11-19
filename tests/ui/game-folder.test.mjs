import assert from "node:assert/strict";
import test from "node:test";
import {setImmediate as flush} from "node:timers/promises";

test("a late scan cannot replace a new copy or turn a failed scan into an uninstall action", async () => {
  const scans = new Map();
  let selected = "copy A";
  const storage = new Map();
  globalThis.localStorage = {
    getItem:key => storage.get(key) ?? null,
    setItem:(key,value) => storage.set(key,value),
    removeItem:key => storage.delete(key)
  };
  globalThis.window = {__TAURI__:{core:{invoke:async (command, {path} = {}) => {
    if (command === "find_games") return [selected];
    if (command === "installed_versions") return {[path]:"v1.7"};
    if (command === "validate_game_mods") {
      assert.ok(!scans.has(path), "only one scan per copy");
      const pending = Promise.withResolvers();
      scans.set(path,pending);
      return pending.promise;
    }
  }}}};
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
