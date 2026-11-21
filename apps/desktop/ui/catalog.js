// Pure helpers over catalog/mods.json entries.
import { locales } from "./languages.js";

export const inventoryKey = mod => (mod.inventoryById || mod.legacyInventoryRepos?.length) ? mod.id : mod.repo;

export function releaseNotesFor(mod, locale) {
  const notes = mod.releaseNotes;
  if (!notes || notes.version !== mod.version) return "";
  const text = notes[locale];
  return typeof text === "string" ? text.trim() : "";
}

export function sortMods(catalog, bundled = []) {
  // Disk records use the identity rules shipped with this desktop build, even offline.
  const pinned = new Map(bundled.map(mod => [mod.id, mod]));
  return catalog.mods.map(mod => {
    const local = pinned.get(mod.id);
    if (local?.legacyInventoryRepos?.length && inventoryKey(mod) !== local.id)
      return {...mod, legacyInventoryRepos: local.legacyInventoryRepos};
    return mod;
  }).sort((a, b) => a.order - b.order);
}

export function installedRows(inventory, online, bundled) {
  const byRepo = new Map([...bundled, ...online].map(mod => [inventoryKey(mod), mod]));
  return Object.entries(inventory)
    .map(([repo, version]) => ({repo, version, mod:byRepo.get(repo)}))
    .sort((a, b) => (a.mod?.order ?? Infinity) - (b.mod?.order ?? Infinity) || a.repo.localeCompare(b.repo));
}

export function visibleMods(mods, {query}) {
  const term = query.trim().toLowerCase();
  return mods.filter(mod => locales.some(locale => mod.name[locale].toLowerCase().includes(term)));
}

// The signed online catalog is authoritative, but the desktop binary also ships a
// built-in catalog (catalog/mods.json compiled into the executable). A mod that
// exists only locally -- e.g. a newly developed minigame not yet published to the
// catalog worker -- must still be visible in the manager. The online entries win
// on conflicts, built-in-only entries are appended, and the whole built-in list
// is used as an offline fallback when no signed catalog is available.
export function mergeBundled(catalog, bundled) {
  const builtIn = bundled && Array.isArray(bundled.mods) ? bundled : null;
  if (!builtIn) return catalog;
  if (!catalog || !Array.isArray(catalog.mods)) return builtIn;
  const known = new Set(catalog.mods.map(mod => mod.id));
  const extra = builtIn.mods.filter(mod => !known.has(mod.id));
  return extra.length ? {...catalog, mods: [...catalog.mods, ...extra]} : catalog;
}
