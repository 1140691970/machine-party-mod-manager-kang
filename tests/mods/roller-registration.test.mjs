import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { appendFile, copyFile, mkdir, mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
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
  await appendFile(path.join(project, "project.godot"),
    '\n[autoload]\nEarlyLoader="*res://early.gd"\nGameManager="*res://manager.gd"\nPlayerManager="*res://players.tscn"\n');
  const fixtures = {
    "early.gd": [
      "extends Node", "func _init():", "\tvar wrapper := GDScript.new()",
      '\twrapper.source_code = FileAccess.get_file_as_string("res://official_minigame.gd")',
      '\tif wrapper.reload() == OK: print("Early wrapper compilation passed")'
    ].join("\n") + "\n",
    "manager.gd": "extends Node\nvar can_set_cursor := true\n",
    "players.gd": "extends Node\nvar player_presences: Dictionary = {}\n",
    "players.tscn": '[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://players.gd" id="1"]\n[node name="PlayerManager" type="Node"]\nscript = ExtResource("1")\n',
    "state.gd": "extends Node\nclass_name State\n",
    "state_machine.gd": "extends Node\nclass_name StateMachine\nvar initial_state: NodePath\n",
    "minigame.gd": [
      "extends Node", "class_name Minigame", "signal host_loaded(skip_intro)", "signal minigame_ready(id)",
      "signal minigame_finished(id)", "signal player_scores_finalized(scores)", "var round_number := 0",
      "var total_rounds := 0", "var players_loaded: Array[int]", "var is_all_player_loaded := false"
    ].join("\n") + "\n"
  };
  for (const [name, contents] of Object.entries(fixtures)) await writeFile(path.join(project, name), contents);
  const scan = spawnSync(godot, ["--headless", "--editor", "--import", "--path", project], {encoding:"utf8", timeout:30000});
  assert.equal(scan.status, 0, scan.stdout + scan.stderr);
  const run = spawnSync(godot, ["--headless", "--path", project,
    "--script", local("./roller_registration_test.gd")], {encoding:"utf8", timeout:10000});
  const log = run.stdout + run.stderr;
  assert.equal(run.status, 0, log);
  assert.doesNotMatch(log, /SCRIPT ERROR|ERROR:/);
  assert.match(log, /Early wrapper compilation passed/);
  assert.match(log, /Roller registration checks passed/);
});
