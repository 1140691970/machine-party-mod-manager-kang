import assert from "node:assert/strict";
import test from "node:test";

test("closing before or after the server acknowledges cancels that download only", async () => {
  let bridge;
  globalThis.window = {__TAURI__:{core:{Channel:class {id = 17;},invoke:(...args)=>bridge(...args)}}};
  const {downloadMod} = await import("../../apps/desktop/ui/bridge.js");
  for (const closeEarly of [true,false]) {
    const pending = Promise.withResolvers();
    const cancels = [];
    const updates = [];
    let channel;
    bridge = async (name, args) => {
      if (name === "download_mod") { channel = args.progress; return pending.promise; }
      assert.equal(name,"cancel_download");
      cancels.push(args.channel);
      pending.reject("downloadCancelled");
    };
    const controller = new AbortController();
    const result = downloadMod({id:"example",version:"1"}, pct=>updates.push(pct), controller.signal);
    if (closeEarly) controller.abort();
    channel.onmessage(0);
    controller.abort();
    channel.onmessage(1);
    await assert.rejects(result, e=>e === "downloadCancelled");
    assert.deepEqual(cancels,[17]);
    assert.deepEqual(updates,closeEarly ? [] : [0]);
  }
});
