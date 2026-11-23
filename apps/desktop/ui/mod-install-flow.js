import { downloadMod, installMod, setModsEnabled, updateMod, verifyPackage } from "./bridge.js";
import { inventoryKey, resolveDependencies } from "./catalog.js";
import { $, button, closeDialog, element, progress, show } from "./dom.js";
import { confirmGameExit } from "./game-exit-dialog.js";
import { applyValidation, syncGameMods, withGameCopy } from "./game-folder.js";
import { installationProblem } from "./mod-action.js";
import { cached, canToggle, conflictNames, conflictingMods, currentAction, nameOf } from "./mod-helpers.js";
import { render, state, t } from "./state.js";
import { versionState } from "./versions.js";

export function startInstall(mod, action, {onDetails, onConfirmUpdate} = {}) {
  return withGameCopy(() => {
    const migrate = action === "switch" && state.modStates[mod.id] === "legacyInstalled";
    if (!state.pckDir || (!migrate && currentAction(mod) !== action)) return onDetails?.(mod);
    if (action === "updateMod") return onConfirmUpdate?.(mod);
    if (action === "switch") {
      const removals = conflictingMods(mod);
      if (!removals.length) return onDetails?.(mod);
      const path = state.game;
      const dir = state.pckDir;
      const names = removals.map(nameOf).join(state.locale === "en" ? ", " : "、");
      return show(nameOf(mod), element("p", t("switchNotice").replace("{mods}", names)),
        button(t("switch"), () => {
          if (state.game !== path || state.pckDir !== dir) return onDetails?.(mod);
          return installDialog(mod, action, removals.map(item => item.id), {onDetails, onConfirmUpdate});
        }, "primary"));
    }
    return installDialog(mod, action, [], {onDetails, onConfirmUpdate});
  });
}

export async function ensureDependenciesCached(mod, {onProgress, signal, owns} = {}) {
  if (!mod?.requires?.length) return true;
  const resolved = resolveDependencies(mod.id, state.mods);
  if (resolved.error) throw resolved.error;
  for (const dep of resolved.order.slice(0, -1)) {
    const localDep = state.inventory[inventoryKey(dep)];
    const minReq = mod.requires.find(r => (typeof r === "string" ? r : r?.id) === dep.id)?.minVersion;
    const depMissing = state.modStates[dep.id] !== "installed"
      || (minReq && localDep && versionState(localDep, minReq, true) === "available");
    if (!depMissing) continue;
    if (!cached(dep)) {
      onProgress?.(t("working"), null);
      await downloadMod(dep, pct => onProgress?.(pct + "%", pct), signal);
      if (owns && !owns()) return false;
      state.packages[dep.id] = dep.package.sha256;
    }
    await verifyPackage(dep);
    if (owns && !owns()) return false;
  }
  return true;
}

export async function installDialog(mod, action, removals = [], callbacks = {}) {
  if (state.busyMod) return;
  const path = state.game;
  const target = state.pckDir;
  const from = state.inventory[inventoryKey(mod)];
  const title = key => t(key) + " · " + nameOf(mod) + " " + (action === "updateMod" ? from + " → " : "") + mod.version;
  const steps = element("ol", "", "install-steps");
  const lastStep = action === "identify" ? "identify"
    : action === "adoptManual" ? "adoptManual"
    : action === "switch" ? "switchStep"
    : action === "updateMod" ? "updateModStep" : "installStep";
  const stepKeys = ["downloadStep", "verifyStep", lastStep];
  const names = action === "switch" ? conflictNames(mod) : "";
  const notice = names ? element("p", t("switchNotice").replace("{mods}", names)) : null;
  const rows = stepKeys.map(key => {
    const row = element("li");
    const status = element("span");
    row.append(element("span", t(key)), status);
    steps.append(row);
    return status;
  });
  steps.setAttribute("aria-live", "polite");
  const bar = progress();
  const dialog = $("dialog");
  const close = $("#close");
  let stage = 0;
  const installStage = stepKeys.length - 1;
  const preventCancel = event => event.preventDefault();
  const controller = new AbortController();
  const ownsDialog = () => !controller.signal.aborted && dialog.open && steps.isConnected;
  const onClose = () => {
    if ((dialog.open && steps.isConnected) || close.disabled) return;
    dialog.removeEventListener("close", onClose);
    controller.abort();
    state.busyMod = "";
    render();
  };
  dialog.addEventListener("close", onClose);
  show(title(action), ...(notice ? [notice] : []), steps, bar.el);
  state.busyMod = mod.id;
  render();
  try {
    if (action !== "identify" && !await confirmGameExit(path, target, () => ownsDialog() && state.pckDir === target)) {
      if (ownsDialog()) closeDialog();
      return;
    }
    if ((action === "install" || action === "updateMod" || action === "switch") && mod.requires?.length) {
      const ready = await ensureDependenciesCached(mod, {
        signal: controller.signal,
        owns: ownsDialog,
        onProgress: (label, pct) => {
          rows[0].textContent = label;
          if (pct != null) bar.set(pct);
        }
      });
      if (!ready) return;
    }
    if (cached(mod)) {
      rows[0].textContent = t("usingCache");
    } else {
      rows[0].textContent = t("working");
      await downloadMod(mod, pct => { rows[0].textContent = pct + "%"; bar.set(pct); }, controller.signal);
      if (!ownsDialog()) return;
      state.packages[mod.id] = mod.package.sha256;
      rows[0].textContent = t("done");
    }
    if (!ownsDialog()) return;
    stage = 1;
    bar.el.hidden = true;
    rows[stage].textContent = t("working");
    await verifyPackage(mod);
    rows[stage].textContent = t("done");
    if (!ownsDialog()) return;
    stage = installStage;
    if (path !== state.game || target !== state.pckDir) throw "statusUnavailable";
    rows[stage].textContent = t("working");
    if (action !== "identify" && !await confirmGameExit(path, target, () => ownsDialog() && state.pckDir === target)) {
      if (ownsDialog()) closeDialog();
      return;
    }
    close.disabled = true;
    dialog.addEventListener("cancel", preventCancel);
    if (action === "identify") {
      await syncGameMods(true);
      if (state.scan !== "ready") throw state.scanError || "statusUnavailable";
      rows[stage].textContent = t("disk_" + state.modStates[mod.id]);
      if (state.modStates[mod.id] === "manualInstall") {
        show(title("identifySuccess"), steps, button(t("adoptManual"), () => startInstall(mod, "adoptManual", callbacks), "primary"));
        return;
      }
    } else {
      const result = action === "updateMod" ? await updateMod(path, mod, from, target)
        : await installMod(path, mod, action === "adoptManual", target, removals);
      applyValidation(result, path);
      const problem = installationProblem(result, mod);
      if (problem) throw problem;
      rows[stage].textContent = t("done");
    }
    show(title(action + "Success"), steps);
  } catch (error) {
    if (!ownsDialog()) return;
    const [key, ...detail] = String(error).split(": ");
    if (["downloadFirst", "packageCorrupt"].includes(key)) delete state.packages[mod.id];
    if (action === "updateMod" && key === "modUpdatedRescan") {
      rows[stage].textContent = t("done");
      show(title("updateModSuccess"), steps, element("p", t(key)));
      if (state.game === path) await syncGameMods(true);
      return;
    }
    rows[stage].textContent = t("failed");
    let retryButton;
    if (ownsDialog()) {
      const message = element("p", [t(key) || key, ...detail].join(" · "), "error");
      const retry = ["downloadFailed", "packageCorrupt", "downloadFirst", "gameRunning", "gamePermissionDenied", "diskSpace"].includes(key);
      if (retry) {
        retryButton = button(t("retry"), () => startInstall(mod, action, callbacks), "primary");
        retryButton.disabled = true;
      }
      show(title(action + "Failure"), message, steps, ...(retryButton ? [retryButton] : []));
    }
    if (stage === installStage && path && path === state.game) await syncGameMods(true);
    if (retryButton) retryButton.disabled = false;
  } finally {
    dialog.removeEventListener("close", onClose);
    dialog.removeEventListener("cancel", preventCancel);
    if (!controller.signal.aborted) {
      close.disabled = false;
      state.busyMod = "";
      render();
    }
  }
}

export async function toggleModEnabled(mod, enabled, fromDetails = false, onDetails) {
  if (state.busyMod) return;
  await withGameCopy(async () => {
    if (state.busyMod || !state.pckDir || !canToggle(mod)) return;
    const path = state.game;
    const dir = state.pckDir;
    state.busyMod = mod.id;
    render();
    let succeeded = false;
    try {
      if (!await confirmGameExit(path, dir, () => state.game === path && state.pckDir === dir)) {
        return;
      }
      if (state.game !== path || state.pckDir !== dir) return;
      const result = await setModsEnabled(path, [mod.id], enabled, dir);
      state.busyMod = "";
      applyValidation(result, path);
      succeeded = true;
    } catch (error) {
      const [key, ...detail] = String(error).split(": ");
      show(t("failed"), element("p", [t(key) || key, ...detail].join(" · "), "error"), button(t("close"), closeDialog, "primary"));
      if (state.game === path) await syncGameMods(true);
    } finally {
      state.busyMod = "";
      render();
      if (succeeded && fromDetails && $("dialog")?.open) {
        const latest = state.mods.find(item => item.id === mod.id) || mod;
        onDetails?.(latest);
      }
    }
  });
  render();
}
