// Pure helpers over catalog/mods.json entries.

export function sortMods(catalog, preview = null) {
  const entries = preview ? [...catalog.mods.filter(mod => mod.id !== preview.id), preview] : [...catalog.mods];
  return entries.sort((a, b) => a.order - b.order);
}

export function searchText(mod) {
  return [...Object.values(mod.name), mod.repo, ...mod.aliases, ...Object.values(mod.summary)]
    .join(" ")
    .toLowerCase();
}

export function visibleMods(mods, {page, query, inventory}) {
  if (page === "installed") return mods.filter(mod => Object.hasOwn(inventory, mod.repo));
  return mods.filter(mod => searchText(mod).includes(query));
}
