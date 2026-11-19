// Pure helpers over catalog/mods.json entries.

export const inventoryKey = mod => mod.inventoryById ? mod.id : mod.repo;

export function sortMods(catalog) {
  return [...catalog.mods].sort((a, b) => a.order - b.order);
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
