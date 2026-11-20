import { isDesktop, reloadLoader } from "./bridge.js";
import { $ } from "./dom.js";
import { confirmGameExit } from "./game-exit-dialog.js";
import { render, state, t } from "./state.js";

const attempted = new Set();

export function formatLoaderNote(note) {
  if (!note) return "";
  const template = t(note.key);
  if (!template) return note.raw || note.key || "";
  return template
    .replace("{version}", note.version ?? "")
    .replace("{from}", note.from ?? "")
    .replace("{to}", note.to ?? "");
}

function errorKey(error) {
  return String(error?.message ?? error ?? "");
}

export async function maybeAutoUpgradeLoader(validation, path, applyValidation) {
  const loader = validation?.loader;
  if (!isDesktop || !loader?.needsUpgrade || state.game !== path) return;
  if (state.busyMod || state.installing || $("dialog[open]")) return;
  const key = `${path}|${loader.installedVersion ?? ""}->${loader.targetVersion ?? ""}`;
  if (attempted.has(key)) return;
  attempted.add(key);
  state.busyMod = "loader-upgrade";
  state.loaderNote = {key: "loaderReloading"};
  render();
  try {
    const updated = await reloadLoader(path, validation.pckDir, false);
    state.busyMod = "";
    if (state.game === path) {
      state.loaderNote = {key: "loaderAutoUpgraded", version: updated.loader?.targetVersion || loader.targetVersion};
      applyValidation(updated, path);
    } else {
      render();
    }
  } catch (error) {
    state.busyMod = "";
    const code = errorKey(error);
    if (code === "gameRunning") {
      // Allow retrying automatically once the player closes the game and returns to the app.
      attempted.delete(key);
      if (state.game === path) state.loaderNote = {key: "loaderWaitingGameClose"};
    } else if (state.game === path) {
      state.loaderNote = {key: code, raw: code};
    }
    render();
  }
}

export async function runManualLoaderReload(applyValidation) {
  const path = state.game;
  const dir = state.pckDir;
  const loader = state.lastScan?.loader;
  if (!isDesktop || !path || !loader?.canReload || state.busyMod || state.installing) return;
  const attempt = async () => {
    state.busyMod = "loader-upgrade";
    state.loaderNote = {key: "loaderReloading"};
    render();
    try {
      const updated = await reloadLoader(path, dir, true);
      state.busyMod = "";
      if (state.game === path) {
        state.loaderNote = {key: "loaderReloadDone", version: updated.loader?.targetVersion || loader.targetVersion};
        applyValidation(updated, path);
      } else {
        render();
      }
      return true;
    } catch (error) {
      state.busyMod = "";
      const code = errorKey(error);
      if (code === "gameRunning") return "gameRunning";
      if (state.game === path) state.loaderNote = {key: code, raw: code};
      render();
      return false;
    }
  };
  const first = await attempt();
  if (first !== "gameRunning") return;
  const current = () => state.game === path && state.pckDir === dir;
  if (!await confirmGameExit(path, dir, current) || !current()) {
    state.loaderNote = {key: "loaderWaitingGameClose"};
    render();
    return;
  }
  await attempt();
}
