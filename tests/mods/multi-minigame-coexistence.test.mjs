import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { copyFile, mkdir, mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const local = p => fileURLToPath(new URL(p, import.meta.url));
const bundled = local("../../.agent/mod-dev/tools/Godot.app/Contents/MacOS/Godot");
const godot = process.env.GODOT_BIN || (existsSync(bundled) ? bundled : "godot");

test("multiple custom minigame mods coexist in hub registry, playlist, and scenes", {
  skip: !!spawnSync(godot, ["--version"]).error && "Godot unavailable"
}, async t => {
  const project = await mkdtemp(path.join(os.tmpdir(), "multi-minigame-hub-"));
  t.after(() => rm(project, { recursive: true, force: true }));

  await mkdir(path.join(project, "mods/roller-carnival"), { recursive: true });
  await mkdir(path.join(project, "mods/bubble-blitz"), { recursive: true });
  await mkdir(path.join(project, "mods/spike-ring"), { recursive: true });
  for (const modId of ["roller-carnival", "bubble-blitz", "spike-ring"]) {
    const srcDir = local(`../../mods/${modId}`);
    for (const name of await readdir(srcDir)) {
      if (name.endsWith(".gd") || name === "mod.json") {
        await copyFile(path.join(srcDir, name), path.join(project, "mods", modId, name));
      }
    }
  }

  await mkdir(path.join(project, "scripts/resources"), { recursive: true });
  await mkdir(path.join(project, "scripts/scenes/game"), { recursive: true });
  await mkdir(path.join(project, "scenes/local_game/script"), { recursive: true });
  await mkdir(path.join(project, "scenes/lobby/components"), { recursive: true });
  await mkdir(path.join(project, "minigames/intermission_new/components"), { recursive: true });

  const fixtures = {
    "project.godot": [
      "config_version=5",
      "[application]",
      'config/name="MultiMinigameTest"',
      'config/features=PackedStringArray("4.5")',
      "[autoload]",
      'Globals="*res://globals.gd"',
      'GameManager="*res://manager.gd"',
      'PlayerManager="*res://players.gd"',
      'DecalManager="*res://decal_manager.gd"',
      'PropManager="*res://prop_manager.gd"',
      'NetworkManager="*res://network_manager.gd"',
    ].join("\n") + "\n",
    "globals.gd": [
      "extends Node",
      "enum MinigameIdentifier { ChiselGauntlet, ExplodingCollarRace, EscalatorPit, ManufactureGun, SmokeBreak, DiscoDodge, ShapeCutter, KnifeAtTheOffice, ScavangerChairs, TrainRace, DuckHunt, GreenPea, DvdRoomba, JunkPlatform, SpineBreaker, MemorizePath, ForkliftCertified, BurnRecycle, CutsceneTest, CutsceneGame02, EMPTY }",
      "const CustomMinigamesWhitelist: Array[MinigameIdentifier] = [MinigameIdentifier.ChiselGauntlet, MinigameIdentifier.DiscoDodge]",
      "const CutsceneMinigameIdentifiers: Array[MinigameIdentifier] = [MinigameIdentifier.CutsceneTest]",
      "const CutsceneGlitchedPickerMinigameIdentifiers: Array[MinigameIdentifier] = [MinigameIdentifier.CutsceneGame02]",
      "const MinigamePaths: Dictionary[MinigameIdentifier, String] = { MinigameIdentifier.ShapeCutter: \"res://minigames/shape_cutter/shape_cutter.tscn\", MinigameIdentifier.ScavangerChairs: \"res://minigames/scavenger_chairs/scavenger_chairs.tscn\", MinigameIdentifier.BurnRecycle: \"res://minigames/burn_recycle/burn_recycle.tscn\" }",
      "const MinigameIconPaths: Dictionary[MinigameIdentifier, String] = { MinigameIdentifier.BurnRecycle: \"res://minigames/intermission_new/minigame_icons/minigame icon_burn recycle.png\" }",
      "var default_playlist: Array = []",
      "var session_playlist: Array = []",
      "var all_minigames_finished: bool = false",
      "var current_minigame_identifier: MinigameIdentifier = MinigameIdentifier.EMPTY",
    ].join("\n") + "\n",
    "scripts/resources/minigame_list_resource.gd": [
      "extends Resource",
      "class_name MinigameListResource",
      "var game_identifier: int = 0",
      "var total_rounds: int = 1",
      "static func create(id: int, rounds: int = 1) -> MinigameListResource:",
      "\tvar r := MinigameListResource.new()",
      "\tr.game_identifier = id",
      "\tr.total_rounds = rounds",
      "\treturn r",
    ].join("\n") + "\n",
    "manager.gd": "extends Node\nsignal minigame_loaded(id)\nvar can_set_cursor := true\nvar custom_game := false\nvar arcade_game := false\nvar custom_shuffled := false\nvar current_minigame_identifier := 0\n",
    "players.gd": "extends Node\nvar player_presences: Dictionary = {}\n",
    "decal_manager.gd": "extends Node\n@rpc func clear_rpc(): pass\n",
    "prop_manager.gd": "extends Node\n@rpc func clear_rpc(): pass\n",
    "network_manager.gd": "extends Node\nvar active_backend := {\"self_data\": {}}\n",
    "state.gd": "extends Node\nclass_name State\n",
    "state_machine.gd": "extends Node\nclass_name StateMachine\nvar initial_state: NodePath\n",
    "minigame_list_item.gd": "extends Node\nclass_name MinigameListItem\nenum BehaviourType { All, Selected }\nvar minigame_identifier: int = 0\nvar name_label := Label.new()\nvar minigame_icon := TextureRect.new()\nfunc set_inactive(_v: bool): pass\nfunc set_rounds(_r: int): pass\n",
    "input_icon_mapping.gd": "extends Node\nclass_name InputIconMapping\nenum InputAction { KeyboardW, KeyboardS, KeyboardSpace, ControllerFaceSouth, ControllerFaceEast, ControllerLeftStick }\n",
    "intermission_icon_resource.gd": "extends Resource\nclass_name Intermission_IconResource\nvar identifier: int = 0\nvar icon_texture: Texture2D = null\nvar brief_instructions_header_pages: Array = []\nvar brief_instructions_content_pages: Array = []\nvar controls_data: Array = []\n",
    "intermission_control_input_label_data.gd": "extends Resource\nclass_name IntermissionControlInputLabelData\nvar control_text: String = \"\"\nvar controller_text: String = \"\"\nvar keyboard_icons: Array[InputIconMapping.InputAction] = []\nvar controller_icons: Array[InputIconMapping.InputAction] = []\n",
    "minigame.gd": [
      "extends Node", "class_name Minigame", "signal host_loaded(skip_intro)", "signal minigame_loaded(id)",
      "signal minigame_ready(id)", "signal minigame_finished(id)", "signal player_scored(id, s)",
      "signal player_scores_finalized(scores)", "signal debug_player_specifics_initialized",
      "signal before_player_marker_show", "var round_number := 0", "var total_rounds := 0",
      "var players_loaded: Array[int]", "var is_all_player_loaded := false",
      "@rpc func cleanup_rpc(): pass",
    ].join("\n") + "\n",
    "scripts/scenes/game/game.gd": [
      "extends Node",
      "var debug_no_shuffle := true",
      "var total_games_count := 0",
      "var session_current_minigame_round := 0",
      "var session_current_minigame_max_rounds := 0",
      "var minigame: Minigame = null",
      "var minigame_parent: Node = null",
      "var debug_player_handler = null",
      "var session_minigame_list: Array[Globals.MinigameIdentifier] = []",
      "var session_minigame_rounds: Dictionary[Globals.MinigameIdentifier, int] = {}",
      "func generate_session_playlist() -> void: pass",
      "func load_minigame(_id, _is_round, _total_rounds = -1): pass",
      "func _on_host_minigame_loaded(): pass",
      "func _on_minigame_loaded(_id): pass",
      "func _on_minigame_ready(_id): pass",
      "func _on_minigame_player_scored(_id, _s): pass",
      "func _on_minigame_player_score_finalized(_s): pass",
      "func _on_debug_specifics_initialized(): pass",
    ].join("\n") + "\n",
    "scenes/local_game/script/local_game.gd": [
      "extends Node",
      "var debug_no_shuffle := true",
      "var total_games_count := 0",
      "var session_current_minigame_round := 0",
      "var session_current_minigame_max_rounds := 0",
      "var minigame: Minigame = null",
      "var minigame_parent: Node = null",
      "var session_minigame_list: Array[Globals.MinigameIdentifier] = []",
      "var session_minigame_rounds: Dictionary[Globals.MinigameIdentifier, int] = {}",
      "func generate_session_playlist() -> void: pass",
      "func load_minigame(_id, _is_round, _total_rounds = -1): pass",
      "func _on_minigame_loaded(_id): pass",
      "func _on_minigame_ready(_id): pass",
      "func _on_minigame_player_scored(_id, _s): pass",
      "func _on_minigame_player_score_finalized(_s): pass",
    ].join("\n") + "\n",
    "scenes/lobby/components/playlist_handler.gd": "extends Node\nvar all_minigames_list_items: Array = []\nvar selected_minigames_list_items: Array = []\nfunc _ready(): pass\nfunc add_minigame_button(_b, _id, _r = 1): pass\nfunc load_current_playlist(): pass\nfunc _on_reset_button_pressed(): pass\nfunc _on_minigame_add_pressed(_b, _s): pass\n",
    "minigames/intermission_new/components/intermission_game_picker.gd": "extends Node\nvar intermission_manager = null\nvar minigame_icon_spawn_parent = null\nvar active_icons: Array = []\nvar debug_active_identifier := 0\nvar next_minigame_label = null\nvar next_minigame_label_higher = null\nfunc _ready(): pass\n@rpc func setup_icons_from_data_rpc(_a, _b, _c, _d): pass\nfunc debug_update(): pass\nfunc pick_next_game(_i, _r): pass\nfunc set_viewfinder_for_briefing_screen(_id): pass\n",
  };
  for (const [rel, content] of Object.entries(fixtures)) {
    await writeFile(path.join(project, rel), content);
  }

  const scan = spawnSync(godot, ["--headless", "--editor", "--import", "--path", project], { encoding: "utf8", timeout: 30000 });
  assert.equal(scan.status, 0, scan.stdout + scan.stderr);

  const run = spawnSync(godot, ["--headless", "--path", project, "--script", local("./multi_minigame_coexistence_test.gd")], {
    encoding: "utf8",
    timeout: 15000,
  });
  const log = run.stdout + run.stderr;
  assert.equal(run.status, 0, log);
  assert.doesNotMatch(log, /SCRIPT ERROR|ERROR:/);
  assert.match(log, /MULTI_MINIGAME_COEXISTENCE_PASSED/);
});
