import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import test from "node:test";
import { fileURLToPath } from "node:url";

const local = path => fileURLToPath(new URL(path, import.meta.url));
const bundled = local("../../.agent/mod-dev/tools/Godot.app/Contents/MacOS/Godot");
const godot = process.env.GODOT_BIN || (existsSync(bundled) ? bundled : "godot");
const available = !spawnSync(godot, ["--version"]).error;

test("standalone HD profiles preserve the lobby and camera", {skip: !available && "Godot unavailable"}, () => {
  for (const flags of [[], ["--party-hd-120"], ["--party-hd-2x"], ["--party-hd-no-vsync"], ["--party-hd-1440"],
    ["--party-hd-1440", "--party-hd-120", "--party-hd-internal"], ["--test-broadcast"], ["--test-legacy-broadcast"]]) {
    const run = spawnSync(godot, ["--headless", "--path", local("../../mods/standalone-hd"),
      "--script", local("./standalone_hd_test.gd"), "--", ...flags], {encoding: "utf8", timeout: 10000});
    const output = run.stdout + run.stderr;
    assert.equal(run.status, 0, output);
    assert.doesNotMatch(output, /SCRIPT ERROR|ERROR:/);
    assert.match(output, /Standalone HD checks passed/);
  }
});
