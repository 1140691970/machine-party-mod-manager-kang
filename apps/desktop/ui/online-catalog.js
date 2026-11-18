const origin = "https://machineparty.ailaogong.men";
const cacheKey = "online-catalog-v1";
const languages = ["zh-CN", "zh-TW", "en"];
const slug = /^[a-z0-9-]+$/;
const version = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

function validEntry(mod) {
  if (!mod || typeof mod !== "object") return false;
  const pkg = mod.package;
  return typeof mod.id === "string" && slug.test(mod.id)
    && typeof mod.repo === "string" && /^[\w-][\w.-]*\/[\w-][\w.-]*$/.test(mod.repo)
    && Number.isSafeInteger(mod.order) && mod.order > 0 && typeof mod.verified === "boolean"
    && (!mod.image || typeof mod.image === "string" && slug.test(mod.image))
    && (!mod.version || typeof mod.version === "string" && version.test(mod.version))
    && Array.isArray(mod.aliases) && mod.aliases.every(alias => typeof alias === "string")
    && ["name", "summary", "detail"].every(key => languages.every(lang =>
      typeof mod[key]?.[lang] === "string" && mod[key][lang].length))
    && (pkg === undefined || (pkg && mod.version && typeof pkg.assetId === "string"
      && /^\d+$/.test(pkg.assetId) && typeof pkg.sha256 === "string" && /^[a-f0-9]{64}$/.test(pkg.sha256)
      && Number.isSafeInteger(pkg.size) && pkg.size > 0 && typeof pkg.mirrorApproved === "boolean"
      && typeof pkg.filename === "string" && /^[\w.-]+\.zip$/i.test(pkg.filename)));
}

export function validCatalog(data) {
  return data?.schema === 1 && typeof data.revision === "string" && data.revision.length > 0
    && Array.isArray(data.mods) && data.mods.every(validEntry)
    && ["id", "repo", "order"].every(key => new Set(data.mods.map(mod => mod[key])).size === data.mods.length);
}

export function cachedCatalog(storage) {
  try {
    const data = JSON.parse(storage.getItem(cacheKey));
    return validCatalog(data) ? data : null;
  } catch { return null; }
}

export async function loadCatalog(storage, request = fetch) {
  const response = await request(origin + "/v1/catalog.json", {
    cache: "no-cache", credentials: "omit", signal: AbortSignal.timeout(5000)
  });
  if (!response.ok) throw Error("catalogUnavailable");
  const catalog = await response.json();
  if (!validCatalog(catalog)) throw Error("catalogUnavailable");
  try { storage.setItem(cacheKey, JSON.stringify(catalog)); } catch { /* Storage may be full. */ }
  return catalog;
}

export function downloadUrl(mod) {
  return origin + `/v1/downloads/${mod.id}/${mod.version}/${mod.package.assetId}`;
}
