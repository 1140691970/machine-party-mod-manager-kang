// Download availability belongs to a release; disk status belongs to the selected copy.
export function modAction({managed, verified, cached, game, scan, disk, local}) {
  if (local && game && scan === "checking") return "checking";
  if (managed && !cached && !local && disk !== "installed") return "download";
  if (!managed || !verified) return "review";
  if (!game) return "choose";
  if (scan === "checking") return "checking";
  if (scan === "failed") return "retryCheck";
  if (disk === "installed") return "uninstall";
  if (disk === "manualInstall") return "adoptManual";
  if (disk === "vanilla") return cached ? "install" : "download";
  return "review";
}
