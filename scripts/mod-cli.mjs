import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { access, chmod, mkdir, readdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { formatModLintIssues, lintAllMods, lintModDirectory } from "./mod-lint.mjs";
import { packMod } from "./pack-mod.mjs";

const DEFAULT_ROOT = fileURLToPath(new URL("../", import.meta.url));
const DEFAULT_GODOT_REL = ".agent/mod-dev/tools/Godot.app/Contents/MacOS/Godot";
const VALID_TEMPLATES = new Set(["tool", "minigame", "graphics"]);

function toTitleCase(id) {
  return id
    .split("-")
    .filter(Boolean)
    .map(part => part[0].toUpperCase() + part.slice(1))
    .join(" ");
}

function toSnakeCase(id) {
  return id.replace(/-/g, "_");
}

function buildProjectGodot(name) {
  return [
    "; Engine configuration file.",
    "config_version=5",
    "",
    "[application]",
    `config/name="${name}"`,
    "",
    "[display]",
    "window/size/viewport_width=1280",
    "window/size/viewport_height=720",
    ""
  ].join("\n");
}

function buildToolMainGd(id) {
  return `extends RefCounted

const MOD_ID := "${id}"

var _loader = null

func apply(loader) -> void:
\tif not loader.has_api(2):
\t\tpush_warning("[%s] requires MPM Loader API v2+" % MOD_ID)
\t\treturn
\t_loader = loader
\tloader.on_scene_script("res://scenes/lobby/lobby.gd", Callable(self, "_on_lobby"))
\tloader.note("%s: initialized" % MOD_ID)

func _on_lobby(lobby: Node) -> void:
\tif lobby == null:
\t\treturn
\t# Register lobby UI or hooks via loader.registry.get("mpm_core/lobby_ui", null) when available.

func unload() -> void:
\t_loader = null
`;
}

function buildGraphicsMainGd(id) {
  return `extends RefCounted

const MOD_ID := "${id}"

var _loader = null

func apply(loader) -> void:
\tif not loader.has_api(2):
\t\tpush_warning("[%s] requires MPM Loader API v2+" % MOD_ID)
\t\treturn
\t_loader = loader
\tloader.on_node_added(Callable(self, "_on_node_added"))
\tloader.note("%s: graphics hook ready" % MOD_ID)

func _on_node_added(node: Node) -> void:
\tif node == null:
\t\treturn
\t# Keep _on_node_added fast: check node is Camera3D / WorldEnvironment without get_property_list().

func unload() -> void:
\t_loader = null
`;
}

function buildMinigameMainGd(id, snakeId, slotId) {
  if (slotId != null) {
    return `extends RefCounted

const MOD_ID := "${id}"
const TARGET_SLOT_ID := ${slotId}

var _loader = null
var _game_script: Script = null

func apply(loader) -> void:
\tif not loader.has_api(2):
\t\tpush_warning("[%s] requires MPM Loader API v2+" % MOD_ID)
\t\treturn
\t_loader = loader
\tvar mod_dir: String = loader.dir_of(self)
\t_game_script = loader.compile(mod_dir.path_join("${snakeId}_game.gd"))
\tloader.note("%s: minigame slot %d registered" % [MOD_ID, TARGET_SLOT_ID])

func unload() -> void:
\t_game_script = null
\t_loader = null
`;
  }

  return `extends RefCounted

const MOD_ID := "${id}"

var _loader = null
var _game_script: Script = null
var _slot_id: int = -1

func apply(loader) -> void:
\tif not loader.has_api(2):
\t\tpush_warning("[%s] requires MPM Loader API v2+" % MOD_ID)
\t\treturn
\t_loader = loader
\tvar mod_dir: String = loader.dir_of(self)
\t_game_script = loader.compile(mod_dir.path_join("${snakeId}_game.gd"))
\tif Engine.has_meta(&"mpm_core"):
\t\tvar core: Dictionary = Engine.get_meta(&"mpm_core") as Dictionary
\t\tvar sdk = core.get("minigame_sdk", null)
\t\tif sdk != null and sdk.has_method("register_minigame"):
\t\t\tvar res: Dictionary = sdk.register_minigame({
\t\t\t\t"mod_id": MOD_ID,
\t\t\t\t"display_name": "${toTitleCase(id)}"
\t\t\t}, loader) as Dictionary
\t\t\t_slot_id = int(res.get("slot_id", -1))
\tloader.note("%s: minigame registered (slot=%d)" % [MOD_ID, _slot_id])

func unload() -> void:
\tif Engine.has_meta(&"mpm_core"):
\t\tvar core: Dictionary = Engine.get_meta(&"mpm_core") as Dictionary
\t\tvar sdk = core.get("minigame_sdk", null)
\t\tif sdk != null and sdk.has_method("unregister_minigame"):
\t\t\tsdk.unregister_minigame(MOD_ID, _loader)
\t_game_script = null
\t_loader = null
`;
}

function buildMinigameGameGd(id) {
  return `extends SceneTree

const MOD_ID := "${id}"

func _init() -> void:
\tvar args: PackedStringArray = OS.get_cmdline_user_args()
\tif args.has("--self-test"):
\t\tprint("%s: SELF_TEST_PASSED" % MOD_ID)
\t\tquit(0)

static func mark_local_player(actor: Node) -> void:
\tif actor == null:
\t\treturn
\tactor.add_to_group(&"mpm_local_player")
\tactor.set_meta(&"mpm_local_player", true)
`;
}

function buildRunMacSh(snakeId) {
  return `#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
GODOT_BIN="\${GODOT_BIN:-$ROOT_DIR/${DEFAULT_GODOT_REL}}"

if [[ ! -x "$GODOT_BIN" ]]; then
  echo "Godot binary not found at $GODOT_BIN" >&2
  exit 1
fi

exec "$GODOT_BIN" --headless --path "$SCRIPT_DIR" --script "$SCRIPT_DIR/${snakeId}_game.gd" -- --self-test
`;
}

function buildReadme(id, template) {
  return `# ${toTitleCase(id)}

Scaffolded with \`npm run mod -- new ${id} --template ${template}\`.

## Checks

\`\`\`bash
npm run mod -- check ${id}
npm run mod -- catalog-sync ${id}
\`\`\`
`;
}

export async function scaffoldMod({ id, template = "tool", rootDir = DEFAULT_ROOT, slotId = null }) {
  assert.match(id, /^[a-z0-9-]+$/, `Invalid mod id '${id}': use lowercase letters, digits, and hyphens.`);
  assert.ok(VALID_TEMPLATES.has(template), `Unknown template '${template}'. Expected: tool | minigame | graphics.`);

  const modDir = path.join(rootDir, "mods", id);
  try {
    await access(modDir);
    throw new Error(`Mod directory already exists: mods/${id}`);
  } catch (err) {
    if (err.code !== "ENOENT") throw err;
  }

  await mkdir(modDir, { recursive: true });

  const name = toTitleCase(id);
  const snakeId = toSnakeCase(id);
  const numericSlotId = slotId == null ? null : Number(slotId);
  if (numericSlotId != null) {
    assert.ok(Number.isInteger(numericSlotId) && numericSlotId > 0, `Invalid slotId '${slotId}'.`);
  }

  const manifest = {
    id,
    name,
    version: "0.1.0",
    entry: "main.gd",
    priority: 0,
    ...(template === "minigame" || template === "tool"
      ? { requires: ["mpm-core"] }
      : {})
  };

  const createdFiles = ["mod.json", "main.gd", "project.godot", "README.md"];

  await writeFile(path.join(modDir, "mod.json"), JSON.stringify(manifest, null, 2) + "\n", "utf8");
  await writeFile(path.join(modDir, "project.godot"), buildProjectGodot(name), "utf8");
  await writeFile(path.join(modDir, "README.md"), buildReadme(id, template), "utf8");

  if (template === "tool") {
    await writeFile(path.join(modDir, "main.gd"), buildToolMainGd(id), "utf8");
  } else if (template === "graphics") {
    await writeFile(path.join(modDir, "main.gd"), buildGraphicsMainGd(id), "utf8");
  } else {
    await writeFile(path.join(modDir, "main.gd"), buildMinigameMainGd(id, snakeId, numericSlotId), "utf8");
    const gameFile = `${snakeId}_game.gd`;
    await writeFile(path.join(modDir, gameFile), buildMinigameGameGd(id), "utf8");
    createdFiles.push(gameFile);

    const runSh = path.join(modDir, "run_mac.sh");
    await writeFile(runSh, buildRunMacSh(snakeId), "utf8");
    await chmod(runSh, 0o755);
    createdFiles.push("run_mac.sh");
  }

  return { id, template, modDir, files: createdFiles };
}

async function cleanupGeneratedUids(dir) {
  let entries = [];
  try {
    entries = await readdir(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const entry of entries) {
    if (entry.name.startsWith(".") || entry.isSymbolicLink()) continue;
    const abs = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      await cleanupGeneratedUids(abs);
    } else if (entry.isFile() && entry.name.endsWith(".gd.uid")) {
      await rm(abs, { force: true });
    }
  }
}

async function resolveGodotBinary(rootDir, godotPath) {
  const candidates = [godotPath, process.env.GODOT_BIN, path.join(rootDir, DEFAULT_GODOT_REL)].filter(Boolean);
  for (const candidate of candidates) {
    try {
      await access(candidate);
      return candidate;
    } catch {
      // Try next candidate.
    }
  }
  return null;
}

export async function checkMod({
  id,
  rootDir = DEFAULT_ROOT,
  godotPath = null,
  runGodot = true,
  runSelfTest = false
}) {
  assert.match(id, /^[a-z0-9-]+$/, `Invalid mod id '${id}'.`);

  const modRes = await lintModDirectory(id, rootDir);
  const allRes = await lintAllMods(rootDir);
  const slotIssues = allRes.issues.filter(
    issue => issue.rule === "unique-target-slot-id" && issue.file === `mods/${id}/main.gd`
  );
  const lintIssues = [...modRes.issues, ...slotIssues];
  if (lintIssues.length > 0) {
    const formatted = formatModLintIssues(lintIssues).join("\n");
    throw new Error(`Mod lint failed for '${id}':\n${formatted}`);
  }

  const packed = await packMod(id, rootDir);
  const modDir = path.join(rootDir, "mods", id);
  const manifest = JSON.parse(await readFile(path.join(modDir, "mod.json"), "utf8"));

  let godotChecked = false;
  let selfTestPassed = false;
  let godotOutput = "";
  if (runGodot) {
    const bin = await resolveGodotBinary(rootDir, godotPath);
    if (bin) {
      const entryAbs = path.join(modDir, manifest.entry);
      const res = spawnSync(
        bin,
        ["--headless", "--path", modDir, "--check-only", "--script", entryAbs],
        { encoding: "utf8", timeout: 20000 }
      );
      await cleanupGeneratedUids(modDir);
      godotChecked = true;
      godotOutput = `${res.stdout || ""}${res.stderr || ""}`.trim();
      if (res.status !== 0) {
        throw new Error(`Godot check failed for '${id}' (exit ${res.status}):\n${godotOutput}`);
      }

      if (runSelfTest) {
        const selfTestScript = path.join(modDir, `${toSnakeCase(id)}_game.gd`);
        try {
          const scriptText = await readFile(selfTestScript, "utf8");
          if (/extends\s+SceneTree/.test(scriptText) && scriptText.includes("--self-test")) {
            const stRes = spawnSync(
              bin,
              ["--headless", "--path", modDir, "--script", selfTestScript, "--", "--self-test"],
              { encoding: "utf8", timeout: 20000 }
            );
            await cleanupGeneratedUids(modDir);
            const stOut = `${stRes.stdout || ""}${stRes.stderr || ""}`.trim();
            if (stRes.status !== 0 || !stOut.includes("SELF_TEST_PASSED")) {
              throw new Error(`Godot self-test failed for '${id}' (exit ${stRes.status}):\n${stOut}`);
            }
            selfTestPassed = true;
          }
        } catch (err) {
          if (err.code !== "ENOENT") throw err;
        }
      }
    }
  }

  return {
    ok: true,
    id,
    lintIssues,
    packed: {
      filename: packed.filename,
      size: packed.size,
      sha256: packed.sha256,
      files: packed.files
    },
    godotChecked,
    selfTestPassed,
    godotOutput
  };
}

export async function syncCatalogMod({ id, rootDir = DEFAULT_ROOT }) {
  assert.match(id, /^[a-z0-9-]+$/, `Invalid mod id '${id}'.`);
  const packed = await packMod(id, rootDir);
  const catalogPath = path.join(rootDir, "catalog", "mods.json");
  const catalog = JSON.parse(await readFile(catalogPath, "utf8"));
  const entry = Array.isArray(catalog.mods) ? catalog.mods.find(item => item.id === id) : null;
  if (!entry) {
    throw new Error(`Mod '${id}' not found in catalog/mods.json.`);
  }

  const catalogVersion = packed.version.startsWith("v") ? packed.version : `v${packed.version}`;
  entry.version = catalogVersion;
  entry.package = {
    ...(entry.package || {}),
    filename: packed.filename,
    size: packed.size,
    sha256: packed.sha256
  };
  entry.adapter = {
    ...(entry.adapter || {}),
    requiredFiles: packed.files
  };

  await writeFile(catalogPath, JSON.stringify(catalog, null, 2) + "\n", "utf8");
  return {
    id,
    version: packed.version,
    filename: packed.filename,
    size: packed.size,
    sha256: packed.sha256,
    fileCount: packed.files.length
  };
}

function parseFlags(args) {
  const flags = {};
  const positional = [];
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--no-godot") {
      flags.noGodot = true;
    } else if (arg === "--self-test") {
      flags.selfTest = true;
    } else if (arg === "--template" && i + 1 < args.length) {
      flags.template = args[++i];
    } else if (arg === "--slot-id" && i + 1 < args.length) {
      flags.slotId = args[++i];
    } else if (arg === "--help" || arg === "-h") {
      flags.help = true;
    } else {
      positional.push(arg);
    }
  }
  return { flags, positional };
}

function printUsage() {
  console.log([
    "Usage:",
    "  npm run mod -- new <id> [--template tool|minigame|graphics] [--slot-id <n>]",
    "  npm run mod -- check <id> [--no-godot] [--self-test]",
    "  npm run mod -- catalog-sync <id>"
  ].join("\n"));
}

async function main() {
  const [command, ...rest] = process.argv.slice(2);
  if (!command || command === "--help" || command === "-h") {
    printUsage();
    return;
  }
  const { flags, positional } = parseFlags(rest);
  if (flags.help) {
    printUsage();
    return;
  }

  const id = positional[0];
  if (!id) {
    printUsage();
    process.exitCode = 1;
    return;
  }

  if (command === "new") {
    const res = await scaffoldMod({
      id,
      template: flags.template || "tool",
      slotId: flags.slotId ?? null,
      rootDir: DEFAULT_ROOT
    });
    console.log(`Scaffolded mods/${res.id} (${res.template}): ${res.files.join(", ")}`);
    return;
  }

  if (command === "check") {
    const res = await checkMod({
      id,
      rootDir: DEFAULT_ROOT,
      runGodot: !flags.noGodot,
      runSelfTest: Boolean(flags.selfTest)
    });
    console.log(
      `Check passed for ${res.id}: ${res.packed.filename} (${res.packed.size} bytes, ${res.packed.files.length} files, godot=${res.godotChecked}, selfTest=${res.selfTestPassed})`
    );
    return;
  }

  if (command === "catalog-sync") {
    const res = await syncCatalogMod({ id, rootDir: DEFAULT_ROOT });
    console.log(
      `Synced catalog/mods.json for ${res.id}@${res.version}: ${res.filename} (${res.size} bytes, sha256=${res.sha256})`
    );
    return;
  }

  console.error(`Unknown subcommand '${command}'.`);
  printUsage();
  process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(err => {
    console.error(err.message || err);
    process.exitCode = 1;
  });
}
