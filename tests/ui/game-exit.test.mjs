import test from "node:test";
import assert from "node:assert/strict";
import { awaitGameExit } from "../../apps/desktop/ui/game-exit.js";

function scenario(results, choices) {
  const calls = [];
  const run = awaitGameExit({
    process: async action => { calls.push(action); assert.ok(results.length); return results.shift(); },
    choose: async stage => { calls.push(stage + "?"); assert.ok(choices.length); return choices.shift(); },
    waiting() {}, active: () => true, pause: async () => {}, polls: 1
  });
  return {run, calls};
}
for (const [name, results, choices, continued, expected] of [
  ["idle copy", [false], [], true, ["check"]],
  ["cancel before close", [true], ["cancel"], false, ["check","close?"]],
  ["normal exit", [true,true,false], ["close"], true, ["check","close?","close","check"]],
  ["wait longer", [true,true,true,false], ["close","wait"], true, ["check","close?","close","check","stillRunning?","check"]],
  ["cancel after timeout", [true,true,true], ["close","cancel"], false, ["check","close?","close","check","stillRunning?"]],
  ["force only on confirmation", [true,true,true,true,false], ["close","force"], true, ["check","close?","close","check","stillRunning?","force","check"]]
]) {
  test(name, async () => {
    const {run, calls} = scenario(results, choices);
    assert.equal(await run, continued);
    assert.deepEqual(calls, expected);
  });
}

test("a rejected normal close stops before polling or offering force quit", async () => {
  const choices = [];
  await assert.rejects(awaitGameExit({
    process: async action => {
      if (action === "check") return true;
      assert.equal(action, "close");
      throw Error("gameCloseFailed");
    },
    choose: async stage => { choices.push(stage); return "close"; },
    active: () => true, waiting() {}, pause: () => assert.fail("unexpected poll")
  }), /gameCloseFailed/);
  assert.deepEqual(choices, ["close"]);
});
