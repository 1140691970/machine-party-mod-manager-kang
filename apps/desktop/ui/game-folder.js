import { chooseGame, findGames, installedVersions, saveGame, validateGameMods } from "./bridge.js";
import { button, closeDialog, element, show } from "./dom.js";
import { render, state, t } from "./state.js";

export function applyValidation(validation) {
  state.inventory = validation.installed || {};
  state.modStates = validation.modStates || {};
  state.pckDir = validation.pckDir || "";
  state.inventoryFailed = false;
  render();
}

export async function syncGameMods() {
  if (!state.game) return;
  state.inventoryFailed = false;
  try {
    const mods = state.mods.length ? state.mods : null;
    applyValidation(await validateGameMods(state.game, mods));
  } catch {
    try {
      state.inventory = await installedVersions(state.game);
      state.modStates = {};
    } catch {
      state.inventory = {};
      state.modStates = {};
      state.inventoryFailed = true;
    }
    render();
  }
}

async function loadGame(path) {
  localStorage.setItem("game-path", path);
  localStorage.removeItem("game-prompt-dismissed");
  state.game = path;
  state.inventory = {};
  state.modStates = {};
  state.pckDir = "";
  state.inventoryFailed = false;
  await syncGameMods();
}

async function selectPath(path) {
  await saveGame(path);
  closeDialog();
  await loadGame(path);
}

export async function pickGame() {
  const path = await chooseGame(t("choose"));
  if (path) await selectPath(path);
}

export async function detectGame(rescan = false) {
  const candidates = await findGames(rescan);
  if (candidates.length === 1) {
    if (rescan) await saveGame(candidates[0]);
    await loadGame(candidates[0]);
    return;
  }
  localStorage.removeItem("game-path");
  state.game = "";
  state.inventory = {};
  state.modStates = {};
  state.pckDir = "";
  state.inventoryFailed = false;
  render();
  if (!rescan && candidates.length === 0 && localStorage.getItem("game-prompt-dismissed")) return;
  show(t("choose"), element("p", t(candidates.length ? "multiple" : "missing")),
    ...candidates.map(path => button(path, () => selectPath(path), "secondary", "folder")),
    button(t("choose"), pickGame, "primary"),
    button(t("later"), () => {
      if (candidates.length === 0) localStorage.setItem("game-prompt-dismissed", "1");
      closeDialog();
    }, "ghost"));
}
