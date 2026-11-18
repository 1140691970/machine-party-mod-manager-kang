import { chooseGame, findGames, installedVersions, saveGame } from "./bridge.js";
import { button, closeDialog, element, show } from "./dom.js";
import { render, state, t } from "./state.js";

async function loadGame(path) {
  state.game = path;
  state.inventory = {};
  state.inventoryFailed = false;
  try { state.inventory = await installedVersions(path); }
  catch { state.inventoryFailed = true; }
  render();
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
    if (rescan) await selectPath(candidates[0]);
    else await loadGame(candidates[0]);
    return;
  }
  state.game = "";
  state.inventory = {};
  state.inventoryFailed = false;
  render();
  show(t("choose"), element("p", t(candidates.length ? "multiple" : "missing")),
    ...candidates.map(path => button(path, () => selectPath(path), "control")),
    button(t("choose"), pickGame, "control primary"),
    button(t("later"), closeDialog, "control"));
}
