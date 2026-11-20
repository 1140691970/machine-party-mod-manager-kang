import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import test from "node:test";
import { fileURLToPath } from "node:url";

const local = path => fileURLToPath(new URL(path, import.meta.url));
const bundled = local("../../.agent/mod-dev/tools/Godot.app/Contents/MacOS/Godot");
const godot = process.env.GODOT_BIN || (existsSync(bundled) ? bundled : "godot");
const available = !spawnSync(godot, ["--version"]).error;

test("player spotlight tracks only local 3D minigame players and respects toggle and elimination", {skip: !available && "Godot unavailable"}, () => {
  const run = spawnSync(godot, ["--headless", "--path", local("../../mods/player-spotlight"),
    "--script", local("./player_spotlight_test.gd")], {encoding: "utf8", timeout: 10000});
  const output = run.stdout + run.stderr;
  assert.equal(run.status, 0, output);
  assert.doesNotMatch(output, /SCRIPT ERROR|ERROR:/);
  assert.match(output, /Player Spotlight checks passed/);
});
