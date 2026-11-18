// Enforces the directory boundaries described in AGENTS.md and the architecture ADRs.
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const excluded = new Set(["node_modules", "target", "gen", "dist", "icons", "images"]);
const roots = ["apps", "services", "scripts", "tests"];
const ui = "apps/desktop/ui/";
const rustSrc = "apps/desktop/src-tauri/src/";
const tauriFree = ["catalog.rs", "game.rs", "inventory.rs", "preferences.rs"].map(name => rustSrc + name);

export function checkSource(file, source) {
  const errors = [];
  const report = message => errors.push(`${file}: ${message}`);
  const imports = [...source.matchAll(/\b(?:import|export)\s+(?:[^;]*?\s+from\s*)?["']([^"']+)["']|\bimport\(\s*["']([^"']+)["']\s*\)/g)]
    .map(match => match[1] || match[2]);
  for (const specifier of imports) {
    const target = specifier.startsWith(".")
      ? path.posix.normalize(path.posix.join(path.posix.dirname(file), specifier))
      : specifier;
    if (target.startsWith("../")) report(`import escapes the repository: ${specifier}`);
    if (file.startsWith(ui) && (/^node:/.test(target) || !target.startsWith(ui))) report(`desktop UI imports ${specifier}`);
    if (file.startsWith("services/") && target.startsWith("apps/")) report(`service imports app code ${specifier}`);
  }
  if (file.startsWith(ui) && !file.endsWith("/bridge.js") && /__TAURI__/.test(source)) report("Tauri access must go through bridge.js");
  if (tauriFree.includes(file) && /\btauri(?:_plugin_\w+)?::|crate::commands\b/.test(source)) report("domain module depends on Tauri");
  if (file === rustSrc + "main.rs" && /#\[tauri::command\]/.test(source)) report("commands belong in commands.rs or their owning adapter");
  if (file.startsWith("tests/") && /readFile/.test(source) && /\.(?:replace|replaceAll)\s*\(/.test(source)) report("tests must not rewrite production source");
  return errors;
}

async function walk(directory) {
  const found = [];
  for (const item of await fs.readdir(path.join(root, directory), {withFileTypes: true})) {
    if (excluded.has(item.name)) continue;
    const relative = path.posix.join(directory, item.name);
    if (item.isDirectory()) found.push(...await walk(relative));
    else if (/\.(?:m?js|rs)$/.test(item.name)) found.push(relative);
  }
  return found;
}

export async function checkArchitecture() {
  const files = (await Promise.all(roots.map(walk))).flat()
    .filter(file => file !== "scripts/check_architecture.mjs" && !file.startsWith("tests/architecture/"));
  const errors = [];
  for (const file of files) errors.push(...checkSource(file, await fs.readFile(path.join(root, file), "utf8")));
  return {files: files.length, errors};
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const result = await checkArchitecture();
  if (result.errors.length) {
    process.stderr.write(result.errors.join("\n") + "\n");
    process.exitCode = 1;
  } else {
    process.stdout.write(`Architecture boundaries passed (${result.files} source files).\n`);
  }
}
