// The only module that talks to Tauri. Everything else stays testable in a plain browser.
const core = window.__TAURI__?.core;

export const isDesktop = Boolean(core);

const invoke = (command, args) => core.invoke(command, args);

export function appVersion() {
  return isDesktop ? invoke("app_version").catch(() => "") : Promise.resolve("");
}

export const bundledCatalog = () => invoke("catalog");
export const findGames = rescan => invoke("find_games", {rescan});
export const chooseGame = title => invoke("choose_game", {title});
export const saveGame = path => invoke("save_game", {path});
export const installedVersions = path => invoke("installed_versions", {path});
export const validateGameMods = (path, force) => invoke("validate_game_mods", {path, force});
export const gameCopies = path => invoke("game_copies", {path});
export const cachedPackages = () => invoke("cached_packages");

const release = mod => ({id: mod.id, version: mod.version});

export const verifyPackage = mod => invoke("verify_package", release(mod));
export const clearPackage = mod => invoke("clear_package", release(mod));

export async function downloadMod(mod, onProgress, signal) {
  const progress = new core.Channel();
  let registered = false;
  let cancelling = false;
  const cancel = () => {
    if (!registered || cancelling) return;
    cancelling = true;
    invoke("cancel_download", {channel:progress.id}).catch(console.error);
  };
  progress.onmessage = pct => {
    registered = true;
    if (signal.aborted) cancel();
    else onProgress(pct);
  };
  signal.addEventListener("abort", cancel, {once:true});
  try {
    await invoke("download_mod", {...release(mod), progress});
  } finally {
    signal.removeEventListener("abort", cancel);
  }
}

export const installMod = (path, mod, adopt, expectedDir) =>
  invoke("install_mod", {...release(mod), path, adopt, expectedDir, progress: new core.Channel()});
export const uninstallMod = (path, mod, expectedDir) => invoke("uninstall_mod", {...release(mod), path, expectedDir});

export function setAppTitle(title) {
  if (isDesktop) invoke("set_app_title", {title}).catch(console.error);
}

export function openProject(repo) {
  if (isDesktop) return invoke("open_project", {repo});
  window.open("https://github.com/" + repo, "_blank", "noopener");
}

export const checkAppUpdate = () => invoke("check_app_update");

export function installAppUpdate(version, onProgress) {
  const progress = new core.Channel();
  progress.onmessage = onProgress;
  return invoke("install_app_update", {version, progress});
}
