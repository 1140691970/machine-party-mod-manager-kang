// Pure helpers over catalog/mods.json entries.
import { locales } from "./languages.js";
import { versionState } from "./versions.js";

export const inventoryKey = mod => (mod.inventoryById || mod.legacyInventoryRepos?.length) ? mod.id : mod.repo;
export const isLibraryMod = mod => mod?.role === "library";

export function resolveDependencies(targetId, mods) {
  const byId = new Map((mods || []).map(mod => [mod.id, mod]));
  const state = new Map();
  const order = [];
  const visit = (id, minVersion) => {
    const mod = byId.get(id);
    if (!mod) return {error: "dependencyMissing", id};
    if (minVersion) {
      const cmp = mod.version ? versionState(mod.version, minVersion, true) : "review";
      if (cmp !== "same" && cmp !== "newer") return {error: "dependencyVersion", id};
    }
    const mark = state.get(id);
    if (mark === 1) return {error: "dependencyCycle", id};
    if (mark === 2) return null;
    state.set(id, 1);
    for (const req of mod.requires || []) {
      const depId = typeof req === "string" ? req : req?.id;
      const depMin = typeof req === "string" ? undefined : req?.minVersion;
      const err = visit(depId, depMin);
      if (err) return err;
    }
    state.set(id, 2);
    order.push(mod);
    return null;
  };
  const err = visit(targetId);
  return err ? {order: [], error: err.error, missingId: err.id} : {order};
}

export function dependentsOf(modId, mods, installedIds) {
  const installed = installedIds instanceof Set ? installedIds : new Set(installedIds || []);
  return (mods || []).filter(mod =>
    mod.id !== modId && installed.has(mod.id)
    && (mod.requires || []).some(req => (typeof req === "string" ? req : req?.id) === modId));
}

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

export const FILTER_STATUSES = ["all", "enabled", "disabled", "notInstalled", "updatable"];

export function catalogCategories(mods) {
  const seen = new Set();
  const list = [];
  for (const mod of mods || []) {
    if (isLibraryMod(mod)) continue;
    if (mod.category && !seen.has(mod.category)) {
      seen.add(mod.category);
      list.push(mod.category);
    }
  }
  return list;
}

export function modFilterStatus({action, removable, installed, disabled} = {}) {
  if (!(removable || installed || action === "uninstall" || action === "updateMod")) return "notInstalled";
  return disabled ? "disabled" : "enabled";
}

export function matchesStatusFilter(filter, row) {
  if (!filter || filter === "all") return true;
  if (filter === "updatable") return row?.action === "updateMod";
  const status = modFilterStatus(row);
  if (filter === "enabled") return status === "enabled";
  if (filter === "disabled") return status === "disabled";
  if (filter === "notInstalled") return status === "notInstalled";
  return true;
}

export function statusCounts(mods, statusOf) {
  const counts = {all: 0, enabled: 0, disabled: 0, notInstalled: 0, updatable: 0};
  for (const mod of mods || []) {
    counts.all++;
    const row = statusOf ? statusOf(mod) : undefined;
    const status = modFilterStatus(row);
    counts[status]++;
    if (row?.action === "updateMod") counts.updatable++;
  }
  return counts;
}

export function visibleMods(mods, {query = "", category = "all", status = "all", statusOf, includeLibraries = false} = {}) {
  const term = query.trim().toLowerCase();
  return mods.filter(mod => {
    if (!includeLibraries && isLibraryMod(mod)) return false;
    if (term && !locales.some(locale => mod.name[locale].toLowerCase().includes(term))) return false;
    if (category && category !== "all" && mod.category !== category) return false;
    if (status && status !== "all" && statusOf && !matchesStatusFilter(status, statusOf(mod))) return false;
    return true;
  });
}
