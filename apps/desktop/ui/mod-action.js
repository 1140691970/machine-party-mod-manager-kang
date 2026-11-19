import { inventoryKey } from "./catalog.js";

export function uninstallEntry(id, disk, bundled) {
  if (!["installed", "legacyInstalled", "needsRepair"].includes(disk)) return undefined;
  return bundled.find(item => item.id === id && item.adapter);
}

export function modAction({managed, verified, game, scan, disk, update}) {
  if (!managed || !verified) return "review";
  if (!game) return "install";
  if (scan === "checking") return "checking";
  if (scan === "failed") return "retryCheck";
  if (disk === "installed" && update) return "updateMod";
  if (disk === "installed" || disk === "legacyInstalled") return "uninstall";
  if (disk === "manualInstall") return "adoptManual";
  if (disk === "identifyPending") return "identify";
  if (disk === "modConflict") return "switch";
  if (disk === "vanilla") return "install";
  return "review";
}

export function installationProblem(result, mod) {
  const disk = result.modStates[mod.id];
  if (disk === "installed" && result.installed[inventoryKey(mod)] === mod.version) return null;
  if (disk === "needsRepair" || disk === "gameUpdatedOrModified") return disk;
  return "statusUnavailable";
}
