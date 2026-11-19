import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import assert from "node:assert/strict";
import test from "node:test";

const local = path => fileURLToPath(new URL(path, import.meta.url));
const bundled = local("../../.agent/mod-dev/tools/Godot.app/Contents/MacOS/Godot");
const godot = process.env.GODOT_BIN || (existsSync(bundled) ? bundled : "godot");

const missing = spawnSync(godot, ["--version"]).error?.code === "ENOENT";
test("Broadcast MPML pack replaces exported resources before the next autoload", {
  skip: missing && !process.env.GODOT_BIN && "Godot unavailable",
}, () => {
  const result = spawnSync("python3", ["-B", local("./broadcast_mount.py"), godot], { encoding: "utf8" });
  assert.equal(result.status, 0, result.error?.message || result.stdout + result.stderr);
});
