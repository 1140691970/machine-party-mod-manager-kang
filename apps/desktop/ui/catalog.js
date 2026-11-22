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

export const FILTER_STATUSES = ["all", "installed", "notInstalled", "updatable"];

export function catalogCategories(mods) {
  const seen = new Set();
  const list = [];
  for (const mod of mods || []) {
    if (mod.category && !seen.has(mod.category)) {
      seen.add(mod.category);
      list.push(mod.category);
    }
  }
  return list;
}

export function modFilterStatus({action, removable, installed} = {}) {
  if (action === "updateMod") return "updatable";
  if (removable || installed || action === "uninstall") return "installed";
  return "notInstalled";
}

export function matchesStatusFilter(filter, row) {
  if (!filter || filter === "all") return true;
  const status = modFilterStatus(row);
  if (filter === "updatable") return status === "updatable";
  if (filter === "installed") return status === "installed" || status === "updatable";
  if (filter === "notInstalled") return status === "notInstalled";
  return true;
}

export function statusCounts(mods, statusOf) {
  const counts = {all: 0, installed: 0, notInstalled: 0, updatable: 0};
  for (const mod of mods || []) {
    counts.all++;
    const status = modFilterStatus(statusOf ? statusOf(mod) : undefined);
    if (status === "updatable") {
      counts.updatable++;
      counts.installed++;
    } else if (status === "installed") {
      counts.installed++;
    } else {
      counts.notInstalled++;
    }
  }
  return counts;
}

export function visibleMods(mods, {query = "", category = "all", status = "all", statusOf} = {}) {
  const term = query.trim().toLowerCase();
  return mods.filter(mod => {
    if (term && !locales.some(locale => mod.name[locale].toLowerCase().includes(term))) return false;
    if (category && category !== "all" && mod.category !== category) return false;
    if (status && status !== "all" && statusOf && !matchesStatusFilter(status, statusOf(mod))) return false;
    return true;
  });
}
