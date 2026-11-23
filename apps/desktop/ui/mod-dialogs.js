import { clearPackage, openProject, uninstallMod } from "./bridge.js";
import { inventoryKey, isLibraryMod, releaseNotesFor } from "./catalog.js";
import { $, button, closeDialog, element, show } from "./dom.js";
import { confirmGameExit } from "./game-exit-dialog.js";
import { applyValidation, syncGameMods, withGameCopy } from "./game-folder.js";
import {
  approvedUpdate, cached, canToggle, conflictNames, currentAction, isDisabled, isPreview,
  matchesMod, nameOf, pinnedOf, removalEntry, support, trustedPackage
} from "./mod-helpers.js";
import { installDialog, startInstall, toggleModEnabled } from "./mod-install-flow.js";
import { downloadUrl } from "./online-catalog.js";
import { render, state, t } from "./state.js";
import { versionState } from "./versions.js";

const flowCallbacks = () => ({onDetails: details, onConfirmUpdate: confirmModUpdate});

function project(mod) {
  return button(mod.repo.split("/")[0], () => openProject(mod.repo), "link", "external");
}

export function details(mod) {
  const local = state.inventory[inventoryKey(mod)];
  const status = versionState(local, mod.version, mod.verified || approvedUpdate(mod));
  const modState = state.modStates[mod.id];
  const parts = [
    element("p", mod.detail[state.locale]),
    ...(isLibraryMod(mod) ? [element("p", t("roleLibrary"))] : []),
    ...(mod.requires?.length ? [element("p", t("requiresMods") + " · " + mod.requires.map(req => {
      const id = typeof req === "string" ? req : req?.id;
      const found = state.mods.find(item => item.id === id);
      const label = found ? nameOf(found) : id;
      return req?.minVersion ? `${label} (>= ${req.minVersion})` : label;
    }).join(state.locale === "en" ? ", " : "、"))] : []),
    element("p", support(mod)),
    element("p", t("release") + " · " + (mod.version || t("unlisted")))
  ];
  if (local !== undefined) {
    parts.push(element("p", t("local") + " · " + local), element("p", t(status)));
    const bundled = state.pinned.find(item => item.id === mod.id);
    if (bundled && !pinnedOf(mod) && (bundled.adapter?.sourceRule || mod.adapter?.sourceRule)
        && versionState(bundled.version, mod.version, true) === "available")
      parts.push(element("p", t("updateManagerForMod")));
    else if (status === "waiting" || status === "newer")
      parts.push(element("p", t(status === "waiting" ? "hold" : "noDowngrade")));
  }
  if (modState === "installed" && currentAction(mod) === "updateMod") {
    parts.push(primaryAction(mod), button(t("uninstall"), () => uninstallDialog(mod), "secondary"));
  }
  if (canToggle(mod)) {
    const disabled = isDisabled(mod);
    const primary = disabled && currentAction(mod) !== "updateMod";
    parts.push(
      element("p", t("modStateHint").replace("{state}", t(disabled ? "modDisabled" : "modEnabled"))),
      button(t(disabled ? "enableMod" : "disableMod"), () => toggleModEnabled(mod, disabled, true, details),
        primary ? "primary" : "secondary", disabled ? "enable" : "disable")
    );
  }
  if (modState === "needsRepair" && state.lastScan?.repair?.[mod.id] && removalEntry(mod)) parts.push(button(t("uninstall"), () => uninstallDialog(mod), "secondary"));
  if (modState === "legacyInstalled" && trustedPackage(mod) && (mod.verified || isPreview(mod))) parts.push(button(t("migrateLoader"), () => startInstall(mod, "switch", flowCallbacks()), "primary"));
  if (modState === "manualInstall") parts.push(element("p", t("manualDetected")));
  else if (modState === "gameUpdatedOrModified" || modState === "needsRepair")
    parts.push(element("p", t(modState), "error"));
  if (state.scan === "failed") parts.push(element("p", t(state.scanError) || t("statusUnavailable"), "error"));
  if (!mod.verified && !isPreview(mod) && !approvedUpdate(mod)) parts.push(element("p", t("installPending")));
  if (state.lastScan?.pckPath) parts.push(element("p", state.lastScan.pckPath, "file-detail"));
  const adapter = mod.adapter || pinnedOf(mod)?.adapter;
  const versions = mod.supportedGameVersions?.length ? mod.supportedGameVersions : pinnedOf(mod)?.supportedGameVersions;
  if (state.lastScan?.pckSha256 === adapter?.baseline?.sha256 && adapter && versions?.length === 1)
    parts.push(element("p", t("detectedVersion") + " · " + versions[0]));
  if (state.lastScan?.pckSha256) parts.push(element("p", "SHA-256 · " + state.lastScan.pckSha256, "file-detail"));
  const repair = state.lastScan?.repair?.[mod.id];
  if (repair) parts.push(element("p", t("backup") + " · " + repair[0], "file-detail"));
  if (repair?.[1]) {
    const [key, ...detail] = repair[1].split(": ");
    parts.push(element("p", [t(key) || key, ...detail].join(" · ")));
  }
  if (modState === "modConflict") {
    const names = conflictNames(mod);
    parts.push(element("p", names ? t("modConflictWith").replace("{mods}", names) : t("modConflict")));
  } else if (["manualBroadcastConflict", "restoreResidue", "identifyPending", "loaderConflict"].includes(modState)) {
    parts.push(element("p", t(modState)));
  }
  if (cached(mod)) parts.push(button(t("clearCache"), async () => {
    await clearPackage(mod);
    delete state.packages[mod.id];
    closeDialog();
    render();
  }));
  if (mod.package) {
    parts.push(element("p", mod.package.filename));
    if (mod.package.mirrorApproved) {
      const link = element("a", t("downloadPackage"), "btn btn-link");
      link.href = downloadUrl(mod);
      link.download = mod.package.filename;
      parts.push(link);
    }
  }
  parts.push(project(mod));
  show(nameOf(mod), ...parts);
}

export function confirmModUpdate(mod, revised = false) {
  const path = state.game;
  const dir = state.pckDir;
  const from = state.inventory[inventoryKey(mod)];
  const notes = releaseNotesFor(mod, state.locale);
  show(t("updateMod") + " · " + nameOf(mod),
    element("p", from + " → " + mod.version),
    ...(notes ? [
      element("strong", t(revised ? "modReleaseNotesChanged" : "modReleaseNotes")),
      element("p", notes, "release-notes")
    ] : []),
    button(t("cancelModUpdate"), closeDialog),
    button(t("confirmModUpdate"), () => {
      const latest = state.mods.find(item => item.id === mod.id);
      if (state.game !== path || state.pckDir !== dir || !latest || !matchesMod(latest, mod)
          || state.inventory[inventoryKey(latest)] !== from)
        return show(t("releaseChanged"), button(t("close"), closeDialog));
      const latestNotes = releaseNotesFor(latest, state.locale);
      if (latestNotes && latestNotes !== notes) return confirmModUpdate(latest, true);
      if (currentAction(latest) !== "updateMod")
        return show(t("releaseChanged"), button(t("close"), closeDialog));
      return installDialog(latest, "updateMod", [], flowCallbacks());
    }, "primary"));
}

export function uninstallDialog(cardMod) {
  const mod = removalEntry(cardMod);
  if (!mod) return details(cardMod);
  const path = state.game;
  const target = state.pckDir;
  const name = nameOf(cardMod);
  const installedVersion = state.inventory[inventoryKey(mod)];
  const title = key => t(key) + " · " + name + (installedVersion ? " " + installedVersion : "");
  const steps = element("ol", "", "install-steps");
  const row = element("li");
  const status = element("span");
  row.append(element("span", t("restoreStep")), status);
  steps.append(row);
  steps.setAttribute("aria-live", "polite");
  const dialog = $("dialog");
  const close = $("#close");
  const preventCancel = event => event.preventDefault();

  const run = async () => {
    if (state.busyMod || path !== state.game || target !== state.pckDir) return;
    state.busyMod = mod.id;
    status.textContent = t("working");
    close.disabled = true;
    dialog.addEventListener("cancel", preventCancel);
    show(title("uninstall"), steps);
    render();
    try {
      if (!await confirmGameExit(path, target, () => dialog.open && steps.isConnected && state.pckDir === target)) {
        closeDialog();
        return;
      }
      const result = await uninstallMod(path, mod, target);
      applyValidation(result, path);
      if (result.modStates[mod.id] !== "vanilla") {
        throw result.modStates[mod.id] || "uninstallFailed";
      }
      status.textContent = t("done");
      show(title("uninstallSuccess"), steps);
    } catch (error) {
      status.textContent = t("failed");
      const [key, ...detail] = String(error).split(": ");
      const message = element("p", [t(key) || key, ...detail].join(" · "), "error");
      const retry = ["gameRunning", "gamePermissionDenied", "diskSpace"].includes(key);
      let retryButton;
      if (retry) {
        retryButton = button(t("retry"), run, "primary");
        retryButton.disabled = true;
      }
      show(title("uninstallFailure"), message, steps, ...(retryButton ? [retryButton] : []));
      if (state.game === path) await syncGameMods(true);
      if (retryButton) retryButton.disabled = false;
    } finally {
      dialog.removeEventListener("cancel", preventCancel);
      close.disabled = false;
      state.busyMod = "";
      render();
    }
  };

  show(title("uninstall"), steps, button(t("uninstall"), run, "primary"));
}

export function primaryAction(mod) {
  const action = currentAction(mod);
  const label = action === "updateMod" ? t("updateModTo").replace("{version}", mod.version) : t(action === "review" ? "viewReason" : action);
  const el = button(label, () => {
    if (action === "review") return details(mod);
    if (action === "retryCheck") return withGameCopy(undefined, true);
    if (action !== "uninstall") return startInstall(mod, action, flowCallbacks());
    return withGameCopy(() => currentAction(mod) === "uninstall" ? uninstallDialog(mod) : details(mod));
  }, ["review", "uninstall", "checking"].includes(action) ? "secondary" : "primary");
  el.disabled = Boolean(state.busyMod) || action === "checking" || (state.page === "catalog" && state.batchMode);
  el.classList.add("btn-block");
  return el;
}
