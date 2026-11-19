import { inventoryKey } from "./catalog.js";

export function modAction({managed, verified, game, scan, disk}) {
  if (!managed || !verified) return "review";
  if (!game) return "install";
  if (scan === "checking") return "checking";
  if (scan === "failed") return "retryCheck";
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
