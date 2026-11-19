import { downloadUrl } from "./online-catalog.js";
import { installationProblem, catalogAction, uninstallEntry } from "./mod-action.js";
import { clearPackage, downloadMod, installMod, verifyPackage, isDesktop, openProject, uninstallMod, updateMod } from "./bridge.js";
import { inventoryKey, installedRows, visibleMods } from "./catalog.js";
import { $, button, closeDialog, element, progress, show, tag } from "./dom.js";
import { applyValidation, syncGameMods, withGameCopy } from "./game-folder.js";
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
const approvedUpdate = mod => isDesktop && (signedPackage(mod)
  || (trustedPackage(mod) && (pinnedOf(mod).verified || isPreview(mod))));

const statusTone = {
  pending: "", release: "", waiting: "", same: "success",
  available: "accent", newer: "warning", review: "warning"
};

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

function cover(mod, name, status) {
  const box = element("div", "", "cover");
  const fallback = element("strong", name, "cover-title");
  box.append(fallback);
  if (mod.image) {
    const img = element("img", "", "loading");
    img.alt = "";
    box.classList.add("skeleton");
    img.onload = () => { img.classList.remove("loading"); box.classList.remove("skeleton"); };
    img.onerror = () => { img.replaceWith(fallback); box.classList.remove("skeleton"); };
    img.src = "images/" + mod.image + ".png";
    fallback.replaceWith(img);
  }
  const tags = element("div", "", "cover-tags");
  const version = tag(mod.version || t("unlisted"));
  if (mod.version) version.classList.add("tag-mono");
  const label = isPreview(mod) && status === "pending" ? "testRelease" : status;
  tags.append(version, tag(t(label), statusTone[status]));
  box.append(tags);
  return box;
}

function startInstall(mod, action) {
  return withGameCopy(() => {
    const migrate = action === "switch" && state.modStates[mod.id] === "legacyInstalled";
    if (!state.pckDir || (!migrate && currentAction(mod) !== action)) return details(mod);
    if (action === "updateMod") {
      const path = state.game;
      const dir = state.pckDir;
      const from = state.inventory[inventoryKey(mod)];
      return show(t("updateMod") + " · " + nameOf(mod),
        element("p", from + " → " + mod.version),
        element("p", state.lastScan?.pckPath || dir, "file-detail"),
        button(t("cancelModUpdate"), closeDialog),
        button(t("confirmModUpdate"), () => {
          const latest = state.mods.find(item => item.id === mod.id);
          if (state.game !== path || state.pckDir !== dir || !latest || !matchesMod(latest, mod)
              || state.inventory[inventoryKey(mod)] !== from || currentAction(latest) !== action)
            return show(t("releaseChanged"), button(t("close"), closeDialog));
          return installDialog(latest, action);
        }, "primary"));
    }
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
  const location = element("p", state.lastScan?.pckPath || path, "file-detail");
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
  show(title(action), ...(notice ? [notice] : []), steps, location, bar.el);
  state.busyMod = mod.id;
  render();
  try {
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
    close.disabled = true;
    dialog.addEventListener("cancel", preventCancel);
    if (action === "identify") {
      await syncGameMods(true);
      if (state.scan !== "ready") throw state.scanError || "statusUnavailable";
      rows[stage].textContent = t("disk_" + state.modStates[mod.id]);
      if (state.modStates[mod.id] === "manualInstall") {
        show(title("identifySuccess"), steps, location, button(t("adoptManual"), () => startInstall(mod, "adoptManual"), "primary"));
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
    show(title(action + "Success"), steps, location);
  } catch (error) {
    if (!ownsDialog()) return;
    const [key, ...detail] = String(error).split(": ");
    if (["downloadFirst", "packageCorrupt"].includes(key)) delete state.packages[mod.id];
    if (action === "updateMod" && key === "modUpdatedRescan") {
      rows[stage].textContent = t("done");
      show(title("updateModSuccess"), steps, element("p", t(key)), location);
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
      show(title(action + "Failure"), message, steps, location, ...(retryButton ? [retryButton] : []));
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
    disk:state.modStates[mod.id], scan:state.scan, game:state.game,
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
  const location = element("p", state.lastScan?.pckPath || target, "file-detail");
  const dialog = $("dialog");
  const close = $("#close");
  const preventCancel = event => event.preventDefault();

  const run = async () => {
    if (state.busyMod || path !== state.game || target !== state.pckDir) return;
    state.busyMod = mod.id;
    status.textContent = t("working");
    close.disabled = true;
    dialog.addEventListener("cancel", preventCancel);
    show(title("uninstall"), steps, location);
    render();
    try {
      const result = await uninstallMod(path, mod, target);
      applyValidation(result, path);
      if (result.modStates[mod.id] !== "vanilla") {
        throw result.modStates[mod.id] || "uninstallFailed";
      }
      status.textContent = t("done");
      show(title("uninstallSuccess"), steps, location);
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
      show(title("uninstallFailure"), message, steps, location, ...(retryButton ? [retryButton] : []));
      if (state.game === path) await syncGameMods(true);
      if (retryButton) retryButton.disabled = false;
    } finally {
      dialog.removeEventListener("cancel", preventCancel);
      close.disabled = false;
      state.busyMod = "";
      render();
    }
  };

  show(title("uninstall"), steps, location, button(t("uninstall"), run, "primary"));
}

function primaryAction(mod) {
  const action = currentAction(mod);
  const label = action === "updateMod" ? t("updateModTo").replace("{version}", mod.version) : t(action === "review" ? "viewReason" : action);
  const el = button(label, () => {
    if (action === "review") return details(mod);
    if (action === "retryCheck") return syncGameMods(true);
    if (action !== "uninstall") return startInstall(mod, action);
    return withGameCopy(() => currentAction(mod) === "uninstall" ? uninstallDialog(mod) : details(mod));
  }, ["review", "uninstall", "checking"].includes(action) ? "secondary" : "primary");
  el.disabled = Boolean(state.busyMod) || action === "checking";
  el.classList.add("btn-block");
  return el;
}

function card(mod, index) {
  const name = nameOf(mod);
  const local = state.inventory[inventoryKey(mod)];
  const status = state.scan === "failed" ? "review" : versionState(local, mod.version, mod.verified || approvedUpdate(mod));
  const item = element("article", "", "card");
  item.style.setProperty("--i", String(index));

  const body = element("div", "", "card-body");
  const heading = element("h2", "", "card-title");
  const link = element("a", name);
  link.href = "#" + encodeURIComponent(inventoryKey(mod));
  link.onclick = event => { event.preventDefault(); details(mod); };
  heading.append(link);
  body.append(heading, element("p", mod.summary[state.locale], "card-summary"));
  body.append(element("p", support(mod), "panel-note"));
  const disk = state.modStates[mod.id];
  const label = !state.game ? "" : state.scan === "checking" ? "checking" : state.scan === "failed" ? "retryCheck" : disk;
  const summary = [cached(mod) && t("cached"), label && t("disk_" + label)].filter(Boolean);
  if (summary.length) body.append(element("p", summary.join(" · "), "panel-note"));
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
  item.append(cover(mod, name, status), body, footer);
  return item;
}

export function renderModList(content) {
  if (state.scan === "failed") content.append(button(t("retryCheck"), () => syncGameMods(true), "secondary", "refresh"));
  const cards = state.page === "installed"
    ? installedRows(state.inventory, state.mods, [...state.removalMods, ...state.pinned]).map(({repo, version, mod}, index) => {
      if (mod) return card(mod, index);
      const row = element("article", "", "card");
      const body = element("div", "", "card-body");
      body.append(element("h2", repo, "card-title"), element("p", t("local") + " · " + version));
      row.append(body);
      return row;
    })
    : visibleMods(state.mods, {query:$("input").value.trim().toLowerCase()}).map(card);
  if (cards.length) {
    const grid = element("div", "", "grid");
    grid.append(...cards);
    content.append(grid);
  } else if (state.page === "installed" && state.scan === "checking") {
    content.append(element("p", t("checking"), "empty"));
  } else if (state.scan !== "failed" || state.page === "catalog") {
    content.append(element("p", t(state.page === "installed" ? "noMods" : "noMatch"), "empty"));
  }
}
