import {existsSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {spawnSync} from "node:child_process";
import assert from "node:assert/strict";
import test from "node:test";

const local = path => fileURLToPath(new URL(path, import.meta.url));
const bundled = local("../../.agent/mod-dev/tools/Godot.app/Contents/MacOS/Godot");
const godot = process.env.GODOT_BIN || (existsSync(bundled) ? bundled : "godot");
const available = !spawnSync(godot, ["--version"]).error;

test("team-party lobby assignment, nametags, spotlight compat, shove filter, early team win and squad scores", {
  skip: !available && "Godot unavailable"
}, () => {
  const result = spawnSync(godot, [
    "--headless",
    "--path",
    local("../../mods/team-party"),
    "--script",
    local("./team_party_test.gd")
  ], {encoding: "utf8", timeout: 25000});
  const output = result.stdout + result.stderr;
  assert.equal(result.status, 0, output);
  assert.doesNotMatch(output, /SCRIPT ERROR|ERROR:/);
  assert.match(output, /Team Party checks passed/);
});

test("team-party sandbox verifies untouched BubbleBlitz, SpikeRing, RollerCarnival, LobbyBots and PlayerSpotlight together", {
  skip: !available && "Godot unavailable"
}, () => {
  const result = spawnSync(godot, [
    "--headless",
    "--path",
    local("../../mods/team-party"),
    "--script",
    local("./team_party_sandbox.gd"),
    "--",
    "--sandbox-test"
  ], {encoding: "utf8", timeout: 30000});
  const output = result.stdout + result.stderr;
  assert.equal(result.status, 0, output);
  assert.doesNotMatch(output, /SCRIPT ERROR|ERROR:/);
  assert.match(output, /TEAM_SANDBOX_ALL_MODS_VERIFIED/);
  assert.match(output, /SELF_TEST_PASSED/);
});
