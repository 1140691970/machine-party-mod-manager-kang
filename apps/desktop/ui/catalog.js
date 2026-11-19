// Pure helpers over catalog/mods.json entries.

export const inventoryKey = mod => (mod.inventoryById || mod.legacyInventoryRepos?.length) ? mod.id : mod.repo;

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

export function searchText(mod) {
  return [...Object.values(mod.name), mod.repo, ...mod.aliases, ...Object.values(mod.summary)]
    .join(" ")
    .toLowerCase();
}

export function installedRows(inventory, online, bundled) {
  const byRepo = new Map([...bundled, ...online].map(mod => [inventoryKey(mod), mod]));
  return Object.entries(inventory)
    .map(([repo, version]) => ({repo, version, mod:byRepo.get(repo)}))
    .sort((a, b) => (a.mod?.order ?? Infinity) - (b.mod?.order ?? Infinity) || a.repo.localeCompare(b.repo));
}

export function visibleMods(mods, {query}) {
  return mods.filter(mod => searchText(mod).includes(query));
}
