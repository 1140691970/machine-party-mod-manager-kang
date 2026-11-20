import {copyFile, mkdtemp, rm, writeFile} from "node:fs/promises";
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

test("built-in loader de-conflicts overlapping lobby mod UI without touching vanilla buttons", {
  skip: !available && "Godot unavailable"
}, async t => {
  const dir = await mkdtemp(join(tmpdir(), "loader-lobby-ui-"));
  t.after(() => rm(dir, {recursive: true, force: true}));
  await writeFile(join(dir, "project.godot"), 'config_version=5\n\n[application]\nconfig/name="LoaderLobbyUITest"\n');
  await copyFile(local("../../apps/desktop/src-tauri/assets/mpm_bootstrap.gd"), join(dir, "mpm_bootstrap.gd"));
  const result = spawnSync(godot, ["--headless", "--path", dir, "--script", local("./loader_lobby_ui_test.gd")], {
    encoding: "utf8",
    timeout: 20000
  });
  const output = result.stdout + result.stderr;
  assert.equal(result.status, 0, output);
  assert.doesNotMatch(output, /SCRIPT ERROR|ERROR:/);
  assert.match(output, /Loader lobby UI checks passed/);
});
