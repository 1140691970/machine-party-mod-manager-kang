import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { copyFile, mkdir, mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const local = path => fileURLToPath(new URL(path, import.meta.url));
const bundled = local("../../.agent/mod-dev/tools/Godot.app/Contents/MacOS/Godot");
const godot = process.env.GODOT_BIN || (existsSync(bundled) ? bundled : "godot");
test("roller recovers after early compilation failure and registers in preloaded scenes", {
  skip: !!spawnSync(godot, ["--version"]).error && "Godot unavailable"
}, async t => {
  const project = await mkdtemp(path.join(os.tmpdir(), "roller-registration-"));
  t.after(() => rm(project, {recursive:true, force:true}));
  const mod = local("../../mods/roller-carnival");
  for (const name of await readdir(mod)) {
    if (name.endsWith(".gd") || name === "project.godot") await copyFile(path.join(mod, name), path.join(project, name));
  }
  const components = path.join(project, "scenes/lobby/components");
  await mkdir(components, {recursive:true});
  await writeFile(path.join(components, "playlist_handler.gd"),
    "extends Node\n@export var rounds := 1\nvar listed := false\n");
  const run = spawnSync(godot, ["--headless", "--path", project,
    "--script", local("./roller_registration_test.gd")], {encoding:"utf8", timeout:10000});
  const log = run.stdout + run.stderr;
  assert.equal(run.status, 0, log);
  assert.doesNotMatch(log, /SCRIPT ERROR|ERROR:/);
  assert.match(log, /Roller registration checks passed/);
});
