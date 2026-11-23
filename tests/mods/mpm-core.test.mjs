import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(fileURLToPath(new URL("../../", import.meta.url)));
const bundled = path.join(ROOT, ".agent/mod-dev/tools/Godot.app/Contents/MacOS/Godot");
const GODOT = process.env.GODOT_BIN || (existsSync(bundled) ? bundled : "godot");
const missing = spawnSync(GODOT, ["--version"]).error?.code === "ENOENT";

test("mpm-core upgrades Hub v2, runs event_bus, locale_utils, and lobby_ui_coordinator v2", {
  skip: missing && !process.env.GODOT_BIN && "Godot unavailable"
}, () => {
  const res = spawnSync(GODOT, [
    "--headless", "--path", path.join(ROOT, "mods/mpm-core"),
    "--script", path.join(ROOT, "tests/mods/mpm_core_test.gd")
  ], { encoding: "utf8", timeout: 20000 });
  assert.equal(res.status, 0, res.stdout + res.stderr);
  assert.match(res.stdout, /MPM Core checks passed/);
});
