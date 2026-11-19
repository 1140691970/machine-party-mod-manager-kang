export function modAction({managed, verified, game, scan, disk}) {
  if (!managed || !verified) return "review";
  if (!game) return "install";
  if (scan === "checking") return "checking";
  if (scan === "failed") return "retryCheck";
  if (disk === "installed") return "uninstall";
  if (disk === "manualInstall") return "adoptManual";
  if (disk === "identifyPending") return "identify";
  if (disk === "vanilla") return "install";
  return "review";
}
