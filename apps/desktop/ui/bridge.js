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
export const validateGameMods = (path, mods) => invoke("validate_game_mods", {path, mods});

export function installMod(path, modEntry, mods, onProgress) {
  const progress = new core.Channel();
  progress.onmessage = onProgress;
  return invoke("install_mod", {path, modEntry, mods, progress});
}

export const uninstallMod = (path, modEntry, mods) => invoke("uninstall_mod", {path, modEntry, mods});

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
