"""Verify the loader mounts the resource-tree entry before game autoloads."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "apps/desktop/src-tauri/assets"

with TemporaryDirectory() as temp:
    base = Path(temp)
    # Exercise the template unchanged. Rust substitutes the catalog ID in actual packages.
    fixture_id = "__MOD_ID__"
    mod = base / "mods" / fixture_id
    mod.mkdir(parents=True)
    shutil.copyfile(ASSETS / "recipes/resource_tree.gd", mod / "main.gd")
    (mod / "mod.json").write_text(json.dumps({"id": fixture_id, "entry": "main.gd"}))
    with ZipFile(mod / "overlay.zip", "w") as overlay:
        overlay.writestr("probe.gd", 'extends Node\nfunc _ready():\n\tprint("BROADCAST_FIXTURE_LOADED")\n')
        overlay.writestr("probe.gd.remap", '[remap]\npath="res://probe.gd"\n')
    executable = shutil.which(sys.argv[1])
    assert executable, "Requested Godot binary is missing"
    # Bootstrap discovers mods beside the running executable.
    godot = base / Path(executable).name
    try:
        os.link(executable, godot)
    except OSError:
        shutil.copy2(executable, godot)
    with ZipFile(base / "fixture.zip", "w") as game:
        game.write(ASSETS / "mpm_bootstrap.gd", "bootstrap.gd")
        game.writestr("project.godot", 'config_version=5\n[application]\nrun/main_scene="res://main.tscn"\n'
                      '[autoload]\nModLoader="*res://bootstrap.gd"\nProbe="*res://probe.gd"\n')
        game.writestr("main.tscn", '[gd_scene format=3]\n[node name="Main" type="Node"]\n')
        game.writestr("probe.gd.remap", '[remap]\npath="res://old.gd"\n')
        game.writestr("old.gd", 'extends Node\n')
    run = subprocess.run([godot, "--headless", "--main-pack", str(base / "fixture.zip"),
                          "--quit-after", "2"], cwd=base, capture_output=True, text=True, timeout=20)
    log = run.stdout + run.stderr
    assert run.returncode == 0 and "BROADCAST_FIXTURE_LOADED" in log and "ERROR:" not in log, (run.returncode, log)
