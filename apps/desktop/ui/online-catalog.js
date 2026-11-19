const origin = "https://machineparty.ailaogong.men";
const cacheKey = "online-catalog-mpml-v1";
const languages = ["zh-CN", "zh-TW", "en"];
const slug = /^[a-z0-9-]+$/;
const version = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const sha256Hex = /^[a-f0-9]{64}$/;
const safeFilename = name => typeof name === "string" && name.length > 0 && !name.includes("..") && !/[\\/]/.test(name);
const stringArray = value => Array.isArray(value) && value.every(item => typeof item === "string");

function validAdapter(adapter) {
  if (!adapter || typeof adapter !== "object") return false;
  if (!["upstream-cli", "loader-files"].includes(adapter.kind)) return false;
  if (!Array.isArray(adapter.platforms) || !adapter.platforms.length
    || !adapter.platforms.every(p => p === "windows")) return false;
  if (adapter.target !== "pckDir") return false;
  if (!Array.isArray(adapter.touches) || !adapter.touches.length || !adapter.touches.every(safeFilename)) return false;
  if (typeof adapter.exclusive !== "string" || !adapter.exclusive.length) return false;
  const base = adapter.baseline;
  if (!base || !safeFilename(base.file) || !Number.isSafeInteger(base.size) || base.size <= 0
    || typeof base.sha256 !== "string" || !sha256Hex.test(base.sha256)) return false;
  if (adapter.verifyFiles !== undefined && !safeFilename(adapter.verifyFiles)) return false;
  if (adapter.upstreamUninstall !== undefined && typeof adapter.upstreamUninstall !== "boolean") return false;
  if (adapter.autoLoader !== undefined && typeof adapter.autoLoader !== "boolean") return false;
  if (adapter.sourceRule !== undefined && (adapter.kind !== "loader-files" ||
      !["overtime-manifest-v1", "binary-tree-v1", "broadcast-tree-v1"].includes(adapter.sourceRule))) return false;
  if (adapter.kind === "loader-files") return true;
  if (adapter.autoLoader) return false;
  const run = adapter.run;
  const actions = adapter.actions;
  const status = adapter.status;
  if (!run || !["exe", "bundled-python", "powershell"].includes(run.interpreter)
    || !safeFilename(run.program) || !stringArray(run.common)) return false;
  if (!actions || !["preflight", "status", "install", "uninstall"].every(k => stringArray(actions[k]))) return false;
  if (!status || typeof status.installed !== "string" || !status.installed.length
    || typeof status.vanilla !== "string" || !status.vanilla.length
    || (status.older !== undefined && (typeof status.older !== "string" || !status.older.length))) return false;
  if (!Array.isArray(adapter.forbiddenArgs) || !adapter.forbiddenArgs.includes("--force")
    || !adapter.forbiddenArgs.every(arg => typeof arg === "string" && arg.length > 0)) return false;
  const allArgs = [...run.common, ...actions.preflight, ...actions.status, ...actions.install, ...actions.uninstall];
  return allArgs.every(arg => !adapter.forbiddenArgs.includes(arg));
}

function validEntry(mod) {
  if (!mod || typeof mod !== "object") return false;
  const pkg = mod.package;
  return typeof mod.id === "string" && slug.test(mod.id)
    && (mod.inventoryById === undefined || typeof mod.inventoryById === "boolean")
    && (mod.legacyInventoryRepos === undefined || stringArray(mod.legacyInventoryRepos))
    && typeof mod.repo === "string" && /^[\w-][\w.-]*\/[\w-][\w.-]*$/.test(mod.repo)
    && Number.isSafeInteger(mod.order) && mod.order > 0 && typeof mod.verified === "boolean"
    && (!mod.image || typeof mod.image === "string" && slug.test(mod.image))
    && (!mod.version || typeof mod.version === "string" && version.test(mod.version))
    && (mod.supportedGameVersions === undefined || stringArray(mod.supportedGameVersions))
    && Array.isArray(mod.aliases) && mod.aliases.every(alias => typeof alias === "string")
    && ["name", "summary", "detail"].every(key => languages.every(lang =>
      typeof mod[key]?.[lang] === "string" && mod[key][lang].length))
    && (pkg === undefined || (pkg && mod.version && typeof pkg.assetId === "string"
      && /^\d+$/.test(pkg.assetId) && typeof pkg.sha256 === "string" && sha256Hex.test(pkg.sha256)
      && Number.isSafeInteger(pkg.size) && pkg.size > 0 && typeof pkg.mirrorApproved === "boolean"
      && typeof pkg.filename === "string" && /^[\w.-]+\.zip$/i.test(pkg.filename)))
    && (mod.adapter === undefined || (Boolean(pkg) && validAdapter(mod.adapter)));
}

export function validCatalog(data) {
  return data?.schema === 1 && typeof data.revision === "string" && data.revision.length > 0
    && Array.isArray(data.mods) && data.mods.every(validEntry)
    && new Set(data.mods.map(mod => mod.inventoryById ? mod.id : mod.repo)).size === data.mods.length
    && ["id", "order"].every(key => new Set(data.mods.map(mod => mod[key])).size === data.mods.length);
}

export function cachedCatalog(storage) {
  try {
    const data = JSON.parse(storage.getItem(cacheKey));
    return validCatalog(data) ? data : null;
  } catch { return null; }
}

export async function loadCatalog(storage, request = fetch, authorize) {
  let catalog;
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const response = await request(origin + "/v1/catalog.json?inventory=id&prepare=1", {
        cache: "no-cache", credentials: "omit", signal: AbortSignal.timeout(15000)
      });
      if (!response.ok) throw Error("HTTP " + response.status);
      const document = await response.text();
      catalog = JSON.parse(document);
      if (!validCatalog(catalog)) throw Error("catalogInvalid");
      if (authorize) {
        const signature = response.headers.get("X-Mod-Catalog-Signature") || "";
        await authorize(document, signature);
        try { storage.setItem(cacheKey + "-proof", JSON.stringify({document,signature})); } catch { /* Optional offline cache. */ }
      }
      break;
    } catch (error) {
      const timedOut = ["TimeoutError", "AbortError"].includes(error.name);
      const network = error instanceof TypeError;
      if (attempt === 0 && (timedOut || network || /^HTTP 5/.test(error.message))) continue;
      if (timedOut) throw Error("catalogTimeout");
      if (network) throw Error("catalogConnection");
      if (error instanceof SyntaxError) throw Error("catalogInvalid");
      throw error;
    }
  }
  try { storage.setItem(cacheKey, JSON.stringify(catalog)); } catch { /* Storage may be full. */ }
  return catalog;
}

export function downloadUrl(mod) {
  return origin + `/v1/downloads/${mod.id}/${mod.version}/${mod.package.assetId}`;
}

export async function restoreCatalogProof(storage, authorize) {
  const proof = JSON.parse(storage.getItem(cacheKey + "-proof") || "null");
  if (proof?.signature) await authorize(proof.document, proof.signature);
}
