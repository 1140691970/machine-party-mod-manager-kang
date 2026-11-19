import { chooseGame, gameCopies, findGames, installedVersions, saveGame, validateGameMods } from "./bridge.js";
import { button, closeDialog, element, show } from "./dom.js";
import { render, state, t } from "./state.js";

let generation = 0;
let selection = 0;
let active;

export function applyValidation(validation, path) {
  if (state.game !== path) return;
  generation++;
  active = null;
  state.inventory = validation.installed;
  state.modStates = validation.modStates;
  state.pckDir = validation.pckDir;
  state.lastScan = validation;
  state.scan = "ready";
  render();
}

export function syncGameMods(force = false) {
  const path = state.game;
  if (!path) return;
  if (active?.path === path && active.targets === state.updateTargets) return active.promise;
  const token = ++generation;
  state.scan = "checking";
  state.scanError = "";
  render();
  const promise = (async () => {
    try {
      const previous = await installedVersions(path);
      if (generation !== token) return;
      state.inventory = previous;
      render();
      const result = await validateGameMods(path, force);
      if (generation === token) applyValidation(result, path);
    } catch (error) {
      if (generation !== token) return;
      state.lastScan = null;
      state.modStates = {};
      state.scan = "failed";
      state.scanError = String(error);
      render();
    } finally {
      if (generation === token) active = null;
    }
  })();
  active = {path, targets:state.updateTargets, promise};
  return promise;
}

async function loadGame(path) {
  localStorage.setItem("game-path", path);
  localStorage.removeItem("game-prompt-dismissed");
  if (state.game !== path) {
    generation++;
    active = null;
    state.inventory = {};
    state.modStates = {};
    state.pckDir = "";
    state.lastScan = null;
  }
  state.game = path;
  await syncGameMods();
}

async function selectPath(path, selected) {
  await saveGame(path);
  closeDialog();
  await loadGame(path);
  if (selected && state.game === path && state.scan === "ready") return selected();
}

export async function pickGame(selected) {
  const request = ++selection;
  const path = await chooseGame(t("choose"));
  if (!path || request !== selection) return;
  const copies = await gameCopies(path);
  if (request !== selection) return;
  if (copies.length <= 1) return selectPath(path, selected);
  return chooseCopy(copies, selected);
}

function chooseCopy(copies, selected) {
  show(t("choose"), element("p", t("multiple")),
    ...copies.map(copy => button(copy, () => selectPath(copy, selected), "secondary", "folder")));
}

export async function withGameCopy(selected) {
  const path = state.game;
  if (!path) return pickGame(selected);
  const request = ++selection;
  const copies = await gameCopies(path);
  if (request !== selection || state.game !== path) return;
  if (!copies.length) return pickGame(selected);
  if (copies.length > 1) return chooseCopy(copies, selected);
  await syncGameMods();
  if (request === selection && state.game === path && state.scan === "ready") return selected();
}

export async function detectGame(rescan = false) {
  const request = ++selection;
  const candidates = await findGames(rescan);
  if (request !== selection) return;
  if (!rescan && state.game && !candidates.length) {
    const saved = state.game;
    const copies = await gameCopies(saved);
    if (request !== selection) return;
    if (copies.length === 1) return loadGame(saved);
  }
  if (candidates.length === 1) {
    if (rescan) await saveGame(candidates[0]);
    await loadGame(candidates[0]);
    return;
  }
  const keepCurrent = rescan && state.game && (await gameCopies(state.game)).length === 1;
  if (request !== selection) return;
  if (!keepCurrent) {
    localStorage.removeItem("game-path");
    state.game = "";
    state.inventory = {};
    state.modStates = {};
    state.pckDir = "";
    generation++;
    active = null;
    state.scan = "idle";
    render();
  }
  if (!rescan && candidates.length === 0 && localStorage.getItem("game-prompt-dismissed")) return;
  show(t("choose"), element("p", t(candidates.length ? "multiple" : "missing")),
    ...candidates.map(path => button(path, () => selectPath(path), "secondary", "folder")),
    button(t("choose"), pickGame, "primary"),
    button(t("later"), () => {
      if (candidates.length === 0 && !keepCurrent) localStorage.setItem("game-prompt-dismissed", "1");
      closeDialog();
    }, "ghost"));
}
