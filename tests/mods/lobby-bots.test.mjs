import {copyFile, mkdir, mkdtemp, rm, writeFile} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {existsSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {spawnSync} from "node:child_process";
import assert from "node:assert/strict";
import test from "node:test";

const local = path => fileURLToPath(new URL(path, import.meta.url));
const bundled = local("../../.agent/mod-dev/tools/Godot.app/Contents/MacOS/Godot");
const godot = process.env.GODOT_BIN || (existsSync(bundled) ? bundled : "godot");
const available = !spawnSync(godot, ["--version"]).error;

test("MPML lobby bot seats, ready state, scores and cleanup", {skip: !available && "Godot unavailable"}, () => {
  const result = spawnSync(godot, ["--headless", "--path", local("../../mods/lobby-bots"),
    "--script", local("./lobby_bots_test.gd")], {encoding: "utf8", timeout: 20000});
  const output = result.stdout + result.stderr;
  assert.equal(result.status, 0, output);
  assert.doesNotMatch(output, /SCRIPT ERROR|ERROR:/);
  assert.match(output, /Lobby Bots checks passed/);
});

const vanilla = process.env.MACHINE_PARTY_SOURCE || local("../../.agent/mod-dev/decompiled");
const pit = join(vanilla, "minigames/escalator_pit");
test("native Escalator Pit settles two rounds with the same bots", {
  skip: !available ? "Godot unavailable" : !existsSync(join(pit, "scripts/escalator_pit.gd")) && "local game source unavailable"
}, async t => {
  const dir = await mkdtemp(join(tmpdir(), "lobby-bots-escalator-"));
  t.after(() => rm(dir, {recursive: true, force: true}));
  const player = "minigames/escalator_pit/components/player";
  await mkdir(join(dir, player, "scripts"), {recursive: true});
  for (const [source, dest] of [
    [join(pit, "scripts/escalator_pit.gd"), "escalator_pit.gd"],
    [join(pit, "states/finished_state.gd"), "finished_state.gd"],
    [join(vanilla, "scripts/scenes/game/states/minigame_playing_state.gd"), "playing.gd"],
    [local("../../mods/lobby-bots/project.godot"), "project.godot"],
    [local("../../mods/lobby-bots/main.gd"), "main.gd"],
    [local("./escalator_player_fixture.gd"), "escalator_player_fixture.gd"],
    [local("./escalator/player.gd"), player + "/scripts/escalator_pit_player.gd"],
    ...["run.gd", "minigame.gd", "state.gd"].map(file => [local("./escalator/" + file), file])
  ]) await copyFile(source, join(dir, dest));
  await writeFile(join(dir, player, "escalator_pit_player.tscn"), `[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://${player}/scripts/escalator_pit_player.gd" id="1"]
[node name="Player" type="Node3D"]
script = ExtResource("1")
`);
  for (const args of [["--editor", "--import"], ["--script", "res://run.gd", "--fixed-fps", "60"]]) {
    const result = spawnSync(godot, ["--headless", "--path", dir, ...args], {encoding: "utf8", timeout: 20000});
    const output = result.stdout + result.stderr;
    assert.equal(result.status, 0, output);
    assert.doesNotMatch(output, /SCRIPT ERROR|ERROR:/);
    if (args.includes("--script")) assert.match(output, /Native Escalator Pit settlement passed/);
  }
});
