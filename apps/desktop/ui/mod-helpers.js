import { isDesktop } from "./bridge.js";
import { installedRows, inventoryKey } from "./catalog.js";
import { catalogAction, uninstallEntry } from "./mod-action.js";
import { state, t } from "./state.js";

export const nameOf = mod => mod.name[state.locale];

export const cached = mod => Boolean(mod.package && state.packages[mod.id] === mod.package.sha256);
export const matchesMod = (item, mod) => item.id === mod.id && item.version === mod.version
  && item.package?.sha256 === mod.package?.sha256;
export const pinnedOf = mod => state.pinned.find(item => matchesMod(item, mod));
export const isPreview = mod => [...state.previewMods, ...(state.previewMod ? [state.previewMod] : [])].some(item => matchesMod(item, mod));
export const support = mod => {
  const versions = mod.supportedGameVersions?.length ? mod.supportedGameVersions : pinnedOf(mod)?.supportedGameVersions;
  return versions?.length ? t("supportedGame") + " · " + versions.join(", ") : t("supportUnknown");
};
export const trustedPackage = mod => isDesktop && Boolean(mod.package?.mirrorApproved) && Boolean(pinnedOf(mod));

export const signedPackage = mod => isDesktop && state.updateTargets.some(item => matchesMod(item, mod));
export const removalEntry = mod => uninstallEntry(mod.id, state.modStates[mod.id], [...state.pinned, ...state.removalMods, ...state.updateTargets]);
export const isDisabled = mod => state.disabledMods.includes(mod.id);
export const modAdapter = mod => mod.adapter || pinnedOf(mod)?.adapter;
export const canToggle = mod => state.modStates[mod.id] === "installed" && (!modAdapter(mod) || modAdapter(mod).kind === "loader-files");
export const approvedUpdate = mod => isDesktop && (signedPackage(mod)
  || (trustedPackage(mod) && (pinnedOf(mod).verified || isPreview(mod))));

export function conflictingMods(mod) {
  const adapter = mod.adapter || pinnedOf(mod)?.adapter;
  if (!adapter) return [];
  return state.mods.filter(other => {
    if (state.modStates[other.id] === "legacyInstalled") return true;
    if (other.id === mod.id) return false;
    const isInstalled = state.modStates[other.id] === "installed" || state.inventory[inventoryKey(other)] !== undefined;
    if (!isInstalled) return false;
    const otherAdapter = other.adapter || pinnedOf(other)?.adapter;
    return adapter.exclusive === "pck" || !otherAdapter || otherAdapter.exclusive !== adapter.exclusive || Boolean(adapter.conflictGroup && adapter.conflictGroup === otherAdapter.conflictGroup);
  });
}

export function conflictNames(mod) {
  const sep = state.locale === "en" ? ", " : "、";
  return conflictingMods(mod).map(nameOf).join(sep);
}

export function currentAction(mod) {
  return catalogAction({
    page: state.page, disk: state.modStates[mod.id], scan: state.scan, game: state.game,
    installed: removalEntry(mod), approved: approvedUpdate(mod), bundled: trustedPackage(mod),
    local: state.inventory[inventoryKey(mod)], version: mod.version
  });
}

export const statusRow = mod => ({
  action: currentAction(mod),
  removable: Boolean(removalEntry(mod)),
  installed: state.modStates[mod.id] === "installed" || state.inventory[inventoryKey(mod)] !== undefined,
  disabled: isDisabled(mod)
});

export const batchRow = mod => ({
  ready: Boolean(state.game) && state.scan === "ready",
  action: currentAction(mod),
  removable: Boolean(removalEntry(mod)),
  toggleable: canToggle(mod),
  disabled: isDisabled(mod)
});

export function unlistedInstalledRows(query) {
  if (state.filterCategory !== "all") return [];
  const listed = new Set(state.mods.map(mod => inventoryKey(mod)));
  const term = query.trim().toLowerCase();
  return installedRows(state.inventory, state.mods, [...state.removalMods, ...state.pinned])
    .filter(({repo, mod}) => !listed.has(repo) && (!term || repo.toLowerCase().includes(term) || (mod && nameOf(mod).toLowerCase().includes(term))));
}

export const isUnlistedDisabled = ({repo, mod}) => state.disabledMods.includes(mod ? mod.id : repo);
