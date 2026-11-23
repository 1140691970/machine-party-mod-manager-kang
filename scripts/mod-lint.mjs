import { access, readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const DEFAULT_ROOT = fileURLToPath(new URL("../", import.meta.url));
const HOT_PATH_FUNCS = new Set(["_process", "_physics_process", "_node_added"]);

function stripCommentOutsideQuotes(line) {
  let quote = null;
  let escaped = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (quote) {
      if (ch === "\\") {
        escaped = true;
      } else if (ch === quote) {
        quote = null;
      }
      continue;
    }
    if (ch === '"' || ch === "'") {
      quote = ch;
    } else if (ch === "#") {
      return line.slice(0, i);
    }
  }
  return line;
}

function isVariantInferAssign(codeLine) {
  const m = codeLine.match(/^\s*var\s+[A-Za-z_]\w*\s*:=\s*(.+)$/);
  if (!m) return false;
  const rhs = m[1].trim();
  if (!/^(?:[\w.]+\.)?(?:call|callv|get|get_meta)\s*\(/.test(rhs)) {
    return false;
  }
  if (/\bas\s+[A-Za-z_]\w*\s*$/.test(rhs)) {
    return false;
  }
  if (/(?:==|!=|>=|<=|>|<|\band\b|\bor\b|\bis\b)/.test(rhs)) {
    return false;
  }
  return true;
}

export function lintModSource(relPath, source) {
  const issues = [];
  const normalizedPath = relPath.split(path.sep).join("/");
  const baseName = path.basename(normalizedPath);
  const isOverrideScript = baseName.startsWith("override_");
  const lines = source.split(/\r?\n/);

  let currentFunc = null;
  let currentFuncIndent = 0;

  for (let i = 0; i < lines.length; i++) {
    const rawLine = lines[i];
    const code = stripCommentOutsideQuotes(rawLine);
    const trimmed = code.trim();
    const lineNo = i + 1;

    if (!trimmed) continue;

    const indent = rawLine.match(/^(\s*)/)?.[1].length ?? 0;
    const funcMatch = code.match(/^(\s*)(?:static\s+)?func\s+([A-Za-z_]\w*)\s*\(/);
    if (funcMatch) {
      currentFunc = funcMatch[2];
      currentFuncIndent = funcMatch[1].length;
    } else if (currentFunc !== null && indent <= currentFuncIndent && !/^\s*(?:@|#|func\b|static\s+func\b)/.test(code)) {
      currentFunc = null;
      currentFuncIndent = 0;
    }

    if (currentFunc && HOT_PATH_FUNCS.has(currentFunc) && /\bget_property_list\s*\(/.test(code)) {
      issues.push({
        file: normalizedPath,
        line: lineNo,
        rule: "no-hot-path-property-list",
        message: `Avoid calling get_property_list() inside ${currentFunc}(); cache or use direct property lookup.`
      });
    }

    if (isVariantInferAssign(code)) {
      issues.push({
        file: normalizedPath,
        line: lineNo,
        rule: "no-variant-infer-assign",
        message: "Do not use ':=' with Variant-returning .call/.callv/.get/.get_meta; add an explicit type or 'as Type'."
      });
    }

    if (!isOverrideScript && /\bpreload\s*\(\s*["']res:\/\/[^"']+\.gd["']\s*\)/.test(code)) {
      issues.push({
        file: normalizedPath,
        line: lineNo,
        rule: "no-mod-preload",
        message: "Avoid preload(\"res://...gd\") in non-override mod scripts; use loader.compile(dir.path_join(...)) or load()."
      });
    }
  }

  return issues;
}

async function collectGdFiles(dir) {
  const entries = await readdir(dir, { withFileTypes: true });
  entries.sort((a, b) => a.name.localeCompare(b.name, "en"));
  const found = [];
  for (const entry of entries) {
    if (entry.name.startsWith(".") || entry.isSymbolicLink()) continue;
    const abs = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      found.push(...(await collectGdFiles(abs)));
    } else if (entry.isFile() && entry.name.endsWith(".gd")) {
      found.push(abs);
    }
  }
  return found;
}

export async function lintModDirectory(modId, rootDir = DEFAULT_ROOT) {
  const issues = [];
  const modDir = path.join(rootDir, "mods", modId);
  const manifestRel = `mods/${modId}/mod.json`;
  const manifestPath = path.join(modDir, "mod.json");

  let manifest = null;
  try {
    const raw = await readFile(manifestPath, "utf8");
    manifest = JSON.parse(raw);
  } catch (err) {
    issues.push({
      file: manifestRel,
      line: 1,
      rule: "valid-mod-manifest",
      message: `Invalid or missing mod.json for '${modId}': ${err.message}`
    });
  }

  if (manifest && typeof manifest === "object") {
    if (manifest.id !== modId) {
      issues.push({
        file: manifestRel,
        line: 1,
        rule: "valid-mod-manifest",
        message: `mod.json id '${manifest.id}' does not match directory '${modId}'.`
      });
    }
    if (typeof manifest.version !== "string" || manifest.version.trim().length === 0) {
      issues.push({
        file: manifestRel,
        line: 1,
        rule: "valid-mod-manifest",
        message: "mod.json must define a non-empty string 'version'."
      });
    }
    if (typeof manifest.entry !== "string" || manifest.entry.trim().length === 0) {
      issues.push({
        file: manifestRel,
        line: 1,
        rule: "valid-mod-manifest",
        message: "mod.json must define a non-empty string 'entry'."
      });
    } else {
      try {
        await access(path.join(modDir, manifest.entry));
      } catch {
        issues.push({
          file: manifestRel,
          line: 1,
          rule: "valid-mod-manifest",
          message: `mod.json entry '${manifest.entry}' does not exist.`
        });
      }
    }
  }

  let gdFiles = [];
  try {
    gdFiles = await collectGdFiles(modDir);
  } catch {
    return { modId, fileCount: 0, issues };
  }

  let hasTargetSlot = false;
  let hasLocalPlayerMeta = false;
  for (const abs of gdFiles) {
    const rel = path.relative(rootDir, abs).split(path.sep).join("/");
    const source = await readFile(abs, "utf8");
    issues.push(...lintModSource(rel, source));
    if (path.basename(abs) === "main.gd" && (/^\s*const\s+TARGET_SLOT_ID\b/m.test(source) || /\bregister_minigame\s*\(/.test(source))) {
      hasTargetSlot = true;
    }
    if (/\bmpm_local_player\b/.test(source)) {
      hasLocalPlayerMeta = true;
    }
  }

  if (hasTargetSlot && !hasLocalPlayerMeta) {
    issues.push({
      file: `mods/${modId}/main.gd`,
      line: 1,
      rule: "minigame-local-player-meta",
      message: "Minigame mod defines TARGET_SLOT_ID but no script sets 'mpm_local_player' group/meta for player-spotlight."
    });
  }

  return { modId, fileCount: gdFiles.length, issues };
}

export async function lintAllMods(rootDir = DEFAULT_ROOT) {
  const modsDir = path.join(rootDir, "mods");
  let dirents = [];
  try {
    dirents = await readdir(modsDir, { withFileTypes: true });
  } catch {
    return { modCount: 0, fileCount: 0, issues: [] };
  }

  dirents.sort((a, b) => a.name.localeCompare(b.name, "en"));
  const modIds = dirents
    .filter(d => d.isDirectory() && !d.name.startsWith(".") && !d.name.startsWith("_"))
    .map(d => d.name);

  const issues = [];
  let fileCount = 0;
  const slotOwners = new Map();

  for (const modId of modIds) {
    const res = await lintModDirectory(modId, rootDir);
    fileCount += res.fileCount;
    issues.push(...res.issues);

    const mainRel = `mods/${modId}/main.gd`;
    const mainAbs = path.join(modsDir, modId, "main.gd");
    try {
      const mainSrc = await readFile(mainAbs, "utf8");
      const lines = mainSrc.split(/\r?\n/);
      for (let i = 0; i < lines.length; i++) {
        const code = stripCommentOutsideQuotes(lines[i]);
        const m = code.match(/^\s*const\s+TARGET_SLOT_ID\b[^=\n]*=\s*(\d+)/);
        if (m) {
          const slotId = m[1];
          const prev = slotOwners.get(slotId);
          if (prev) {
            issues.push({
              file: mainRel,
              line: i + 1,
              rule: "unique-target-slot-id",
              message: `TARGET_SLOT_ID ${slotId} is already claimed by ${prev.modId} (${prev.file}:${prev.line}).`
            });
          } else {
            slotOwners.set(slotId, { modId, file: mainRel, line: i + 1 });
          }
          break;
        }
      }
    } catch {
      // Optional main.gd handled by valid-mod-manifest if it is the entry.
    }
  }

  return { modCount: modIds.length, fileCount, issues };
}

export function formatModLintIssues(issues) {
  return issues.map(issue => `${issue.file}:${issue.line}: [${issue.rule}] ${issue.message}`);
}

async function main() {
  const target = process.argv[2];
  if (target) {
    const res = await lintModDirectory(target, DEFAULT_ROOT);
    if (res.issues.length > 0) {
      for (const line of formatModLintIssues(res.issues)) {
        console.error(line);
      }
      process.exitCode = 1;
      return;
    }
    console.log(`mod-lint OK: ${res.modId} (${res.fileCount} .gd files)`);
    return;
  }

  const res = await lintAllMods(DEFAULT_ROOT);
  if (res.issues.length > 0) {
    for (const line of formatModLintIssues(res.issues)) {
      console.error(line);
    }
    process.exitCode = 1;
    return;
  }
  console.log(`mod-lint OK (${res.modCount} mods, ${res.fileCount} .gd files)`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(err => {
    console.error(err);
    process.exitCode = 1;
  });
}
