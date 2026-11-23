import { coverUrl, downloadUrl } from "./online-catalog.js";
import {
  BATCH_KINDS, batchConfirmKey, batchDeselect, batchEligible, batchEmptyKey, batchItemAction,
  batchLabelKey, batchRunningKey, batchSelectAll, batchSelectedCount, batchSummary,
  batchTargets, batchToggle, canRunBatch
} from "./batch.js";
import { installationProblem, catalogAction, uninstallEntry } from "./mod-action.js";
import { clearPackage, downloadMod, installMod, verifyPackage, isDesktop, openProject, setModsEnabled, uninstallMod, updateMod } from "./bridge.js";
import { confirmGameExit } from "./game-exit-dialog.js";
import { FILTER_STATUSES, catalogCategories, inventoryKey, installedRows, releaseNotesFor, statusCounts, visibleMods } from "./catalog.js";
import { $, button, closeDialog, element, progress, show, tag } from "./dom.js";
import { applyValidation, syncGameMods, withGameCopy } from "./game-folder.js";
import { icon } from "./icons.js";
import { render, state, t } from "./state.js";
import { versionState } from "./versions.js";

const nameOf = mod => mod.name[state.locale];

const cached = mod => Boolean(mod.package && state.packages[mod.id] === mod.package.sha256);
const matchesMod = (item, mod) => item.id === mod.id && item.version === mod.version
  && item.package?.sha256 === mod.package?.sha256;
const pinnedOf = mod => state.pinned.find(item => matchesMod(item, mod));
const isPreview = mod => [...state.previewMods, ...(state.previewMod ? [state.previewMod] : [])].some(item => matchesMod(item, mod));
const support = mod => {
  const versions = mod.supportedGameVersions?.length ? mod.supportedGameVersions : pinnedOf(mod)?.supportedGameVersions;
  return versions?.length ? t("supportedGame") + " · " + versions.join(", ") : t("supportUnknown");
};
const trustedPackage = mod => isDesktop && Boolean(mod.package?.mirrorApproved) && Boolean(pinnedOf(mod));

const signedPackage = mod => isDesktop && state.updateTargets.some(item => matchesMod(item, mod));
const removalEntry = mod => uninstallEntry(mod.id, state.modStates[mod.id], [...state.pinned, ...state.removalMods, ...state.updateTargets]);
const isDisabled = mod => state.disabledMods.includes(mod.id);
const modAdapter = mod => mod.adapter || pinnedOf(mod)?.adapter;
const canToggle = mod => state.modStates[mod.id] === "installed" && (!modAdapter(mod) || modAdapter(mod).kind === "loader-files");
const approvedUpdate = mod => isDesktop && (signedPackage(mod)
  || (trustedPackage(mod) && (pinnedOf(mod).verified || isPreview(mod))));

function project(mod) {
  return button(mod.repo.split("/")[0], () => openProject(mod.repo), "link", "external");
}

function conflictingMods(mod) {
  const adapter = mod.adapter || pinnedOf(mod)?.adapter;
  if (!adapter) return [];
  return state.mods.filter(other => {
    if (state.modStates[other.id] === "legacyInstalled") return true;
    if (other.id === mod.id) return false;
    const isInstalled = state.modStates[other.id] === "installed" || state.inventory[inventoryKey(other)] !== undefined;
    if (!isInstalled) return false;
    const otherAdapter = other.adapter || pinnedOf(other)?.adapter;
    return adapter.exclusive === "pck" || !otherAdapter || otherAdapter.exclusive !== adapter.exclusive || Boolean(adapter.conflictGroup && adapter.conflictGroup === otherAdapter.conflictGroup);
  });
}

function conflictNames(mod) {
  const sep = state.locale === "en" ? ", " : "、";
  return conflictingMods(mod).map(nameOf).join(sep);
}

function details(mod) {
  const local = state.inventory[inventoryKey(mod)];
  const status = versionState(local, mod.version, mod.verified || approvedUpdate(mod));
  const modState = state.modStates[mod.id];
  const parts = [
    element("p", mod.detail[state.locale]),
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
      button(t(disabled ? "enableMod" : "disableMod"), () => toggleModEnabled(mod, disabled, true),
        primary ? "primary" : "secondary", disabled ? "enable" : "disable")
    );
  }
  if (modState === "needsRepair" && state.lastScan?.repair?.[mod.id] && removalEntry(mod)) parts.push(button(t("uninstall"), () => uninstallDialog(mod), "secondary"));
  if (modState === "legacyInstalled" && trustedPackage(mod) && (mod.verified || isPreview(mod))) parts.push(button(t("migrateLoader"), () => startInstall(mod, "switch"), "primary"));
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

function cover(mod, name) {
  const box = element("div", "", "cover");
  const fallback = element("strong", name, "cover-title");
  box.append(fallback);
  const src = coverUrl(mod);
  if (src) {
    const img = element("img", "", "loading");
    img.alt = "";
    img.decoding = "async";
    img.loading = "lazy";
    box.classList.add("skeleton");
    img.onload = () => { img.classList.remove("loading"); box.classList.remove("skeleton"); };
    img.onerror = () => { img.replaceWith(fallback); box.classList.remove("skeleton"); };
    img.src = src;
    fallback.replaceWith(img);
  }
  const tags = element("div", "", "cover-tags");
  if (canToggle(mod) && isDisabled(mod)) tags.append(tag(t("modDisabled"), "disabled"));
  const version = tag(mod.version || t("unlisted"));
  if (mod.version) version.classList.add("tag-mono");
  tags.append(version);
  const category = t("category_" + mod.category);
  if (category) tags.append(tag(category));
  box.append(tags);
  return box;
}

function confirmModUpdate(mod, revised = false) {
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
      return installDialog(latest, "updateMod");
    }, "primary"));
}

function startInstall(mod, action) {
  return withGameCopy(() => {
    const migrate = action === "switch" && state.modStates[mod.id] === "legacyInstalled";
    if (!state.pckDir || (!migrate && currentAction(mod) !== action)) return details(mod);
    if (action === "updateMod") return confirmModUpdate(mod);
    if (action === "switch") {
      const removals = conflictingMods(mod);
      if (!removals.length) return details(mod);
      const path = state.game;
      const dir = state.pckDir;
      const names = removals.map(nameOf).join(state.locale === "en" ? ", " : "、");
      return show(nameOf(mod), element("p", t("switchNotice").replace("{mods}", names)),
        button(t("switch"), () => {
          if (state.game !== path || state.pckDir !== dir) return details(mod);
          return installDialog(mod, action, removals.map(item => item.id));
        }, "primary"));
    }
    return installDialog(mod, action);
  });
}

async function installDialog(mod, action, removals = []) {
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
        show(title("identifySuccess"), steps, button(t("adoptManual"), () => startInstall(mod, "adoptManual"), "primary"));
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
        retryButton = button(t("retry"), () => startInstall(mod, action), "primary");
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

function currentAction(mod) {
  return catalogAction({
    page:state.page, disk:state.modStates[mod.id], scan:state.scan, game:state.game,
    installed:removalEntry(mod), approved:approvedUpdate(mod), bundled:trustedPackage(mod),
    local:state.inventory[inventoryKey(mod)], version:mod.version
  });
}

function uninstallDialog(cardMod) {
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

async function toggleModEnabled(mod, enabled, fromDetails = false) {
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
        details(latest);
      }
    }
  });
  render();
}

function toggleSwitch(mod) {
  const disabled = isDisabled(mod);
  const label = element("label", "", "mod-switch");
  label.title = t(disabled ? "enableMod" : "disableMod");
  const input = document.createElement("input");
  input.type = "checkbox";
  input.setAttribute("role", "switch");
  input.setAttribute("aria-label", t("toggleModAria").replace("{mod}", nameOf(mod)));
  input.checked = !disabled;
  input.disabled = Boolean(state.busyMod) || state.scan !== "ready" || (state.page === "catalog" && state.batchMode);
  input.onchange = () => {
    void toggleModEnabled(mod, input.checked);
  };
  label.append(input, element("span", "", "mod-switch-track"));
  return label;
}

function primaryAction(mod) {
  const action = currentAction(mod);
  const label = action === "updateMod" ? t("updateModTo").replace("{version}", mod.version) : t(action === "review" ? "viewReason" : action);
  const el = button(label, () => {
    if (action === "review") return details(mod);
    if (action === "retryCheck") return withGameCopy(undefined, true);
    if (action !== "uninstall") return startInstall(mod, action);
    return withGameCopy(() => currentAction(mod) === "uninstall" ? uninstallDialog(mod) : details(mod));
  }, ["review", "uninstall", "checking"].includes(action) ? "secondary" : "primary");
  el.disabled = Boolean(state.busyMod) || action === "checking" || (state.page === "catalog" && state.batchMode);
  el.classList.add("btn-block");
  return el;
}

function card(mod, index) {
  const name = nameOf(mod);
  const local = state.inventory[inventoryKey(mod)];
  const item = element("article", "", "card");
  if (canToggle(mod) && isDisabled(mod)) item.classList.add("card-disabled");
  item.style.setProperty("--i", String(index));

  const body = element("div", "", "card-body");
  const heading = element("h2", "", "card-title");
  const link = element("a", name);
  link.href = "#" + encodeURIComponent(inventoryKey(mod));
  link.onclick = event => { event.preventDefault(); details(mod); };
  heading.append(link);
  body.append(heading, element("p", mod.summary[state.locale], "card-summary"));
  body.append(element("p", support(mod), "panel-note"));
  if (local !== undefined) {
    const versions = element("div", "", "comparison");
    versions.append(
      element("span", t("local") + " · " + local),
      element("span", t("release") + " · " + (mod.version || t("unlisted")))
    );
    body.append(versions);
  }

  const footer = element("div", "", "card-actions");
  footer.append(primaryAction(mod));
  if (canToggle(mod)) footer.append(toggleSwitch(mod));
  if (state.page === "catalog" && currentAction(mod) === "updateMod" && removalEntry(mod)) {
    const removeBtn = button("", () => withGameCopy(() => removalEntry(mod) ? uninstallDialog(mod) : details(mod)), "secondary", "close");
    removeBtn.classList.add("card-remove-btn");
    removeBtn.title = t("uninstall");
    removeBtn.setAttribute("aria-label", t("uninstall") + " · " + name);
    removeBtn.disabled = Boolean(state.busyMod) || state.batchMode;
    footer.append(removeBtn);
  }
  const coverBox = cover(mod, name);
  if (state.page === "catalog" && state.batchMode) {
    const checked = state.selectedMods.includes(mod.id);
    item.classList.add("batch-card");
    item.classList.toggle("batch-selected", checked);
    const {label, input} = batchCheckbox(mod, checked);
    coverBox.append(label);
    item.addEventListener("click", event => {
      if (state.batch?.phase === "running") return;
      if (event.target.closest("a, button, input, label")) return;
      input.checked = !input.checked;
      toggleBatchSelection(mod.id, input.checked, item);
    });
  }
  item.append(coverBox, body, footer);
  return item;
}

// ---- Catalog filters & batch operations -------------------------------
const BATCH_BUSY = "__batch__";
const BATCH_ICONS = {install: "download", enable: "enable", disable: "disable", uninstall: "close"};
const STATUS_KEYS = {
  all: "filterAll",
  enabled: "filterEnabled",
  disabled: "filterDisabled",
  notInstalled: "filterNotInstalled",
  updatable: "filterUpdatable"
};

const statusRow = mod => ({
  action: currentAction(mod),
  removable: Boolean(removalEntry(mod)),
  installed: state.modStates[mod.id] === "installed" || state.inventory[inventoryKey(mod)] !== undefined,
  disabled: isDisabled(mod)
});

const batchRow = mod => ({
  ready: Boolean(state.game) && state.scan === "ready",
  action: currentAction(mod),
  removable: Boolean(removalEntry(mod)),
  toggleable: canToggle(mod),
  disabled: isDisabled(mod)
});

function filteredCatalogMods() {
  return visibleMods(state.mods, {
    query: $("#search input")?.value || "",
    category: state.filterCategory,
    status: state.filterStatus,
    statusOf: statusRow
  });
}

let batchStripRefs = null;

function toggleBatchSelection(id, checked, cardEl) {
  state.selectedMods = batchToggle(state.selectedMods, id, checked);
  cardEl?.classList.toggle("batch-selected", checked);
  syncBatchStrip();
}

function batchCheckbox(mod, checked) {
  const label = element("label", "", "batch-check");
  label.setAttribute("aria-label", t("batchSelectMod").replace("{mod}", nameOf(mod)));
  label.title = nameOf(mod);
  const input = document.createElement("input");
  input.type = "checkbox";
  input.checked = checked;
  input.disabled = state.batch?.phase === "running";
  input.onchange = () => {
    if (state.batch?.phase === "running") return;
    toggleBatchSelection(mod.id, input.checked, label.closest(".card"));
  };
  label.append(input, element("span", "", "batch-check-box"));
  return {label, input};
}

function syncBatchStrip() {
  if (!batchStripRefs || !batchStripRefs.strip.isConnected) {
    batchStripRefs = null;
    return;
  }
  const {count, toggleAll, clear, actionButtons, visibleIds} = batchStripRefs;
  const running = state.batch?.phase === "running";
  const selectedSet = new Set(state.selectedMods);
  const allVisibleSelected = visibleIds.length > 0 && visibleIds.every(id => selectedSet.has(id));
  count.textContent = t("batchSelected").replace("{count}", String(state.selectedMods.length));
  toggleAll.textContent = t(allVisibleSelected ? "batchDeselectVisible" : "batchSelectAll");
  toggleAll.disabled = running || visibleIds.length === 0;
  clear.disabled = running || !state.selectedMods.length;
  for (const kind of BATCH_KINDS) {
    const ref = actionButtons.get(kind);
    if (!ref) continue;
    const matched = batchSelectedCount(state.mods, kind, batchRow, state.selectedMods);
    ref.badge.textContent = String(matched);
    ref.btn.disabled = running;
    const activeInstall = kind === "install" && matched > 0;
    const activeToggle = (kind === "enable" || kind === "disable") && matched > 0;
    const activeUninstall = kind === "uninstall" && matched > 0;
    ref.btn.classList.toggle("btn-primary", activeInstall);
    ref.btn.classList.toggle("btn-secondary", activeToggle);
    ref.btn.classList.toggle("batch-op-danger", activeUninstall);
    ref.btn.classList.toggle("batch-op-idle", matched === 0);
  }
}

function renderCatalogToolbar(content, visible) {
  const running = state.batch?.phase === "running";
  const toolbar = element("section", "", "catalog-toolbar");
  toolbar.setAttribute("role", "region");
  toolbar.setAttribute("aria-label", t("filterStatus"));

  const row = element("div", "", "toolbar-row");
  const filters = element("div", "", "toolbar-filters");

  // Status filter tabs (clean underline style with live counts scoped to search & category)
  const statusGroup = element("div", "", "filter-tabs");
  statusGroup.setAttribute("role", "group");
  statusGroup.setAttribute("aria-label", t("filterStatus"));
  const query = $("#search input")?.value || "";
  const scopedMods = visibleMods(state.mods, {query, category: state.filterCategory});
  const counts = statusCounts(scopedMods, statusRow);
  for (const item of unlistedInstalledRows(query)) {
    counts.all++;
    counts[isUnlistedDisabled(item) ? "disabled" : "enabled"]++;
  }
  for (const status of FILTER_STATUSES) {
    const active = state.filterStatus === status;
    const num = counts[status] ?? 0;
    const tab = element("button", "", "filter-tab" + (active ? " active" : ""));
    tab.type = "button";
    tab.disabled = running;
    tab.setAttribute("aria-pressed", String(active));
    tab.append(element("span", t(STATUS_KEYS[status])));
    const badgeClass = status === "updatable" && num > 0 ? "toolbar-badge toolbar-badge-accent" : "toolbar-count";
    tab.append(element("span", String(num), badgeClass));
    tab.onclick = () => {
      if (state.filterStatus === status) return;
      state.filterStatus = status;
      render();
    };
    statusGroup.append(tab);
  }
  filters.append(statusGroup);

  // Category filter tags (dynamic from catalog)
  const categories = catalogCategories(state.mods);
  if (categories.length > 1) {
    if (state.filterCategory !== "all" && !categories.includes(state.filterCategory)) {
      state.filterCategory = "all";
    }
    const divider = element("span", "", "toolbar-divider");
    divider.setAttribute("aria-hidden", "true");
    filters.append(divider);

    const catGroup = element("div", "", "filter-chips");
    catGroup.setAttribute("role", "group");
    catGroup.setAttribute("aria-label", t("filterCategory"));
    for (const cat of ["all", ...categories]) {
      const active = state.filterCategory === cat;
      const chip = element("button", cat === "all" ? t("filterAllCategories") : (t("category_" + cat) || cat),
        "filter-chip" + (active ? " active" : ""));
      chip.type = "button";
      chip.disabled = running;
      chip.setAttribute("aria-pressed", String(active));
      chip.onclick = () => {
        if (state.filterCategory === cat) return;
        state.filterCategory = cat;
        render();
      };
      catGroup.append(chip);
    }
    filters.append(catGroup);
  }

  // Batch mode toggle on the right of the toolbar
  const actions = element("div", "", "toolbar-actions");
  const modeBtn = state.batchMode
    ? button(t("batchExit"), () => {
      if (running) return;
      state.batchMode = false;
      state.selectedMods = [];
      render();
    }, "secondary")
    : button(t("batchMode"), () => {
      if (running) return;
      state.batchMode = true;
      render();
    }, "ghost", "checklist");
  modeBtn.disabled = running;
  modeBtn.classList.add("btn-sm", "toolbar-batch-toggle");
  if (state.batchMode) modeBtn.classList.add("active");
  actions.append(modeBtn);

  row.append(filters, actions);
  toolbar.append(row);

  if (state.batchMode) {
    const visibleIds = visible.map(mod => mod.id);
    const strip = element("div", "", "batch-strip");
    strip.setAttribute("role", "region");
    strip.setAttribute("aria-label", t("batchActions"));

    const left = element("div", "", "batch-strip-left");
    const count = element("span", "", "batch-count");
    const sep = element("span", "", "batch-sep");
    sep.setAttribute("aria-hidden", "true");
    const toggleAll = element("button", "", "batch-link-btn");
    toggleAll.type = "button";
    toggleAll.onclick = () => {
      if (state.batch?.phase === "running") return;
      const selectedSet = new Set(state.selectedMods);
      const allSelected = visibleIds.length > 0 && visibleIds.every(id => selectedSet.has(id));
      state.selectedMods = allSelected
        ? batchDeselect(state.selectedMods, visibleIds)
        : batchSelectAll(state.selectedMods, visibleIds);
      render();
    };
    const clear = element("button", t("batchClear"), "batch-link-btn");
    clear.type = "button";
    clear.onclick = () => {
      if (state.batch?.phase === "running") return;
      state.selectedMods = [];
      render();
    };
    left.append(count, sep, toggleAll, clear);

    const right = element("div", "", "batch-strip-actions");
    const actionButtons = new Map();
    for (const kind of BATCH_KINDS) {
      const btn = element("button", "", "btn btn-sm batch-op-btn batch-op-idle");
      btn.type = "button";
      btn.dataset.kind = kind;
      const badge = element("span", "0", "batch-btn-count");
      btn.append(icon(BATCH_ICONS[kind]), element("span", t(batchLabelKey(kind))), badge);
      btn.onclick = () => runBatchAction(kind);
      right.append(btn);
      actionButtons.set(kind, {btn, badge});
    }

    strip.append(left, right);
    toolbar.append(strip);
    content.append(toolbar);
    batchStripRefs = {strip, count, toggleAll, clear, actionButtons, visibleIds};
    syncBatchStrip();
  } else {
    batchStripRefs = null;
    content.append(toolbar);
  }
}

function batchNotify(text) {
  show(t("batchActions"), element("p", text), button(t("close"), closeDialog, "primary"));
}

function runBatchAction(kind) {
  if (!BATCH_KINDS.includes(kind) || state.batch?.phase === "running") return;
  if (!state.selectedMods.length) return batchNotify(t("batchNeedSelection"));
  if (!state.game) return batchNotify(t("batchNeedGame"));
  if (state.scan !== "ready") return batchNotify(t("batchScanning"));
  const {queue, filtered} = batchTargets(state.mods, kind, batchRow, state.selectedMods);
  if (!canRunBatch(queue)) return batchNotify(t(batchEmptyKey(kind)));
  confirmBatchRun(kind, queue, filtered);
}

function confirmBatchRun(kind, queue, filtered) {
  const list = element("ul", "", "batch-confirm-list");
  for (const id of queue) {
    const mod = state.mods.find(item => item.id === id);
    list.append(element("li", mod ? nameOf(mod) : id));
  }
  const note = filtered.length
    ? element("p", t("batchFilteredHint").replace("{count}", String(filtered.length)), "panel-note")
    : element("p", t(kind === "enable" || kind === "disable" ? "batchConfirmToggleHint" : "batchConfirmHint"), "panel-note");
  show(t(batchConfirmKey(kind)).replace("{count}", String(queue.length)),
    list, note,
    button(t("batchCancel"), closeDialog, "secondary"),
    button(t("batchConfirm"), () => startBatch(kind, queue), "primary"));
}

async function rescanBatch(path) {
  if (state.game !== path) return;
  try { await syncGameMods(true); } catch { /* scan failures are surfaced by the next recheck */ }
}

async function executeBatchItem(kind, id, path, onProgress, signal, owns) {
  const mod = state.mods.find(item => item.id === id);
  if (!mod || !batchEligible(kind, batchRow(mod))) return "skip";
  if (state.game !== path || !state.pckDir) return "abort";
  const dir = state.pckDir;
  if (!await confirmGameExit(path, dir, () => owns() && state.pckDir === dir)) return "abort";
  if (!owns()) return "abort";
  const latest = state.mods.find(item => item.id === id) || mod;
  const action = batchItemAction(kind, batchRow(latest));
  if (!action) return "skip";
  if (action === "uninstall") {
    const entry = removalEntry(latest);
    if (!entry) return "skip";
    const result = await uninstallMod(path, entry, dir);
    applyValidation(result, path);
    if (result.modStates[entry.id] !== "vanilla") throw result.modStates[entry.id] || "uninstallFailed";
    return "ok";
  }
  if (cached(latest)) {
    onProgress(t("usingCache"));
  } else {
    onProgress(t("working"));
    await downloadMod(latest, pct => onProgress(pct + "%"), signal);
    if (!owns()) return "abort";
    state.packages[latest.id] = latest.package.sha256;
  }
  if (!owns()) return "abort";
  await verifyPackage(latest);
  if (!owns()) return "abort";
  const from = state.inventory[inventoryKey(latest)];
  let result;
  try {
    result = action === "updateMod"
      ? await updateMod(path, latest, from, dir)
      : await installMod(path, latest, false, dir, []);
  } catch (error) {
    if (action === "updateMod" && String(error).startsWith("modUpdatedRescan")) {
      await rescanBatch(path);
      return "ok";
    }
    throw error;
  }
  applyValidation(result, path);
  const problem = installationProblem(result, latest);
  if (problem) throw problem;
  return "ok";
}

function startBatch(kind, queue) {
  if (state.batch?.phase === "running") return;
  const batch = {kind, phase: "running", ids: queue.slice()};
  state.batch = batch;
  state.busyMod = BATCH_BUSY;
  render();
  void runBatchDialog(batch, queue).catch(error => {
    console.error("batch operation failed", error);
    const dialog = $("dialog");
    $("#close").disabled = false;
    if (dialog.open) {
      show(t("failed"), element("p", String(error), "error"),
        button(t("close"), closeDialog, "primary"));
    } else {
      state.busyMod = "";
      state.batch = null;
      render();
    }
  });
}

async function runBatchDialog(batch, queue) {
  const kind = batch.kind;
  const path = state.game;
  const dialog = $("dialog");
  const close = $("#close");
  const controller = new AbortController();
  const preventCancel = event => event.preventDefault();

  const list = element("ol", "", "install-steps batch-steps");
  list.setAttribute("aria-live", "polite");
  const bar = progress();
  const rows = new Map();
  for (const id of queue) {
    const mod = state.mods.find(item => item.id === id);
    const li = element("li");
    const status = element("span", t("batchItemPending"));
    li.append(element("span", mod ? nameOf(mod) : id), status);
    list.append(li);
    rows.set(id, {li, status});
  }
  const owns = () => !controller.signal.aborted && dialog.open && list.isConnected;
  const setStatus = (id, text, tone) => {
    const row = rows.get(id);
    if (!row) return;
    row.status.textContent = text;
    row.li.classList.remove("batch-ok", "batch-fail", "batch-skip");
    if (tone) row.li.classList.add("batch-" + tone);
  };
  const onClose = () => {
    dialog.removeEventListener("close", onClose);
    dialog.removeEventListener("cancel", preventCancel);
    controller.abort();
    close.disabled = false;
    state.busyMod = "";
    state.batch = null;
    batchStripRefs = null;
    render();
  };
  dialog.addEventListener("close", onClose);
  dialog.addEventListener("cancel", preventCancel);
  close.disabled = true;
  show(t(batchRunningKey(kind)), element("p", t("batchWorkingHint")), list, bar.el);

  const results = [];
  let aborted = false;
  if (kind === "enable" || kind === "disable") {
    const targetEnabled = kind === "enable";
    const dir = state.pckDir;
    const outcomeById = new Map();
    if (!path || !dir || state.game !== path
      || !await confirmGameExit(path, dir, () => owns() && state.pckDir === dir) || !owns()) {
      for (const id of queue) {
        setStatus(id, t("batchItemSkipped"), "skip");
        outcomeById.set(id, "skip");
      }
      aborted = true;
    } else {
      const eligible = [];
      for (const id of queue) {
        const mod = state.mods.find(item => item.id === id);
        if (!mod || !batchEligible(kind, batchRow(mod))) {
          setStatus(id, t("batchItemSkipped"), "skip");
          outcomeById.set(id, "skip");
        } else {
          setStatus(id, t("working"));
          eligible.push(id);
        }
      }
      if (eligible.length) {
        try {
          const result = await setModsEnabled(path, eligible, targetEnabled, dir);
          if (!owns()) return;
          applyValidation(result, path);
          for (const id of eligible) {
            const ok = (result.disabledMods || []).includes(id) === !targetEnabled;
            setStatus(id, t(ok ? "done" : "failed"), ok ? "ok" : "fail");
            outcomeById.set(id, ok ? "ok" : "fail");
          }
        } catch (error) {
          if (!owns()) return;
          const [key, ...detail] = String(error).split(": ");
          const msg = [t(key) || key, ...detail].join(" · ");
          for (const id of eligible) {
            setStatus(id, msg, "fail");
            outcomeById.set(id, "fail");
          }
          await rescanBatch(path);
        }
      }
    }
    if (!owns()) return;
    for (const id of queue) results.push(outcomeById.get(id) || "skip");
    bar.set(100);
  } else {
    let completed = 0;
    for (const id of queue) {
      if (!owns()) return;
      setStatus(id, t("working"));
      let outcome;
      try {
        outcome = await executeBatchItem(kind, id, path, pct => setStatus(id, pct), controller.signal, owns);
      } catch (error) {
        outcome = "fail";
        const [key, ...detail] = String(error).split(": ");
        if (["downloadFirst", "packageCorrupt", "downloadFailed"].includes(key)) delete state.packages[id];
        setStatus(id, [t(key) || key, ...detail].join(" · "), "fail");
      }
      if (!owns()) return;
      if (outcome === "abort") {
        setStatus(id, t("batchItemSkipped"), "skip");
        results.push("skip");
        aborted = true;
        break;
      }
      if (outcome === "ok") setStatus(id, t("done"), "ok");
      else if (outcome === "skip") setStatus(id, t("batchItemSkipped"), "skip");
      results.push(outcome);
      completed++;
      bar.set(Math.round(completed / queue.length * 100));
      if (outcome !== "ok") await rescanBatch(path);
    }
  }
  if (!owns()) return;
  batch.phase = "done";
  bar.set(100);
  const okIds = new Set(queue.filter((id, index) => results[index] === "ok"));
  state.selectedMods = state.selectedMods.filter(id => !okIds.has(id));
  render();
  const summary = batchSummary(results);
  const text = t("batchSummary")
    .replace("{ok}", String(summary.ok))
    .replace("{fail}", String(summary.fail))
    .replace("{skip}", String(summary.skip));
  dialog.removeEventListener("cancel", preventCancel);
  close.disabled = false;
  show(aborted ? t("batchAborted") : t("batchDone"),
    element("p", text, "batch-summary"), list, bar.el,
    button(t("close"), closeDialog, "primary"));
}

function unlistedInstalledRows(query) {
  if (state.filterCategory !== "all") return [];
  const listed = new Set(state.mods.map(mod => inventoryKey(mod)));
  const term = query.trim().toLowerCase();
  return installedRows(state.inventory, state.mods, [...state.removalMods, ...state.pinned])
    .filter(({repo, mod}) => !listed.has(repo) && (!term || repo.toLowerCase().includes(term) || (mod && nameOf(mod).toLowerCase().includes(term))));
}

const isUnlistedDisabled = ({repo, mod}) => state.disabledMods.includes(mod ? mod.id : repo);

function unlistedInstalledCards(query) {
  if (!["all", "enabled", "disabled"].includes(state.filterStatus)) return [];
  return unlistedInstalledRows(query)
    .filter(item => state.filterStatus === "all" || (state.filterStatus === "disabled") === isUnlistedDisabled(item))
    .map(({repo, version, mod}, index) => {
      if (mod) return card(mod, state.mods.length + index);
      const row = element("article", "", "card");
      const body = element("div", "", "card-body");
      body.append(element("h2", repo, "card-title"), element("p", t("local") + " · " + version));
      row.append(body);
      return row;
    });
}

export function renderModList(content) {
  if (state.scan === "failed") content.append(button(t("retryCheck"), () => withGameCopy(undefined, true), "secondary", "refresh"));
  const query = $("#search input")?.value || "";
  const visible = state.page === "catalog" ? filteredCatalogMods() : [];
  if (state.page === "catalog") renderCatalogToolbar(content, visible);
  const cards = state.page === "installed"
    ? installedRows(state.inventory, state.mods, [...state.removalMods, ...state.pinned]).map(({repo, version, mod}, index) => {
      if (mod) return card(mod, index);
      const row = element("article", "", "card");
      const body = element("div", "", "card-body");
      body.append(element("h2", repo, "card-title"), element("p", t("local") + " · " + version));
      row.append(body);
      return row;
    })
    : [...visible.map(card), ...unlistedInstalledCards(query)];
  if (cards.length) {
    const grid = element("div", "", "grid");
    grid.append(...cards);
    content.append(grid);
  } else if (state.page === "installed" && state.scan === "checking") {
    content.append(element("p", t("checking"), "empty"));
  } else if (state.scan !== "failed" || state.page === "catalog") {
    const hasFilter = state.page === "catalog" && (state.filterStatus !== "all" || state.filterCategory !== "all");
    if (hasFilter) {
      const box = element("div", "", "empty empty-filtered");
      box.append(
        element("p", t("noMatch")),
        button(t("filterReset"), () => {
          state.filterStatus = "all";
          state.filterCategory = "all";
          render();
        }, "secondary")
      );
      content.append(box);
    } else {
      content.append(element("p", t(state.page === "installed" ? "noMods" : "noMatch"), "empty"));
    }
  }
}
