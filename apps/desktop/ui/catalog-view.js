import { downloadUrl } from "./online-catalog.js";
import { modAction } from "./mod-action.js";
import { clearPackage, downloadMod, installMod, verifyPackage, isDesktop, openProject, uninstallMod } from "./bridge.js";
import { visibleMods } from "./catalog.js";
import { $, button, closeDialog, element, progress, show, tag } from "./dom.js";
import { applyValidation, syncGameMods, withGameCopy } from "./game-folder.js";
import { render, state, t } from "./state.js";
import { versionState } from "./versions.js";

const nameOf = mod => mod.name[state.locale];

const cached = mod => Boolean(mod.package && state.packages[mod.id] === mod.package.sha256);
const isPreview = mod => mod.id === state.previewMod?.id && mod.version === state.previewMod.version
  && mod.package?.sha256 === state.previewMod.package?.sha256;
const support = mod => mod.supportedGameVersions?.length
  ? t("supportedGame") + " · " + mod.supportedGameVersions.join(", ") : t("supportUnknown");
const trustedPackage = mod => isDesktop && mod.package?.mirrorApproved && state.pinned.some(item =>
  item.id === mod.id && item.version === mod.version && item.package?.sha256 === mod.package.sha256);

const statusTone = {
  pending: "", release: "", waiting: "", same: "success",
  available: "accent", newer: "warning", review: "warning"
};

function project(mod) {
  return button(mod.repo.split("/")[0], () => openProject(mod.repo), "link", "external");
}

function details(mod) {
  const local = state.inventory[mod.repo];
  const status = versionState(local, mod.version, mod.verified);
  const modState = state.modStates[mod.id];
  const parts = [
    element("p", mod.detail[state.locale]),
    element("p", support(mod)),
    element("p", t("release") + " · " + (mod.version || t("unlisted")))
  ];
  if (local !== undefined) {
    parts.push(element("p", t("local") + " · " + local), element("p", t(status)));
    if (status === "waiting" || status === "newer")
      parts.push(element("p", t(status === "waiting" ? "hold" : "noDowngrade")));
  }
  if (modState === "manualInstall") parts.push(element("p", t("manualDetected")));
  else if (modState === "gameUpdatedOrModified" || modState === "needsRepair")
    parts.push(element("p", t(modState), "error"));
  if (state.scan === "failed") parts.push(element("p", t(state.scanError) || t("statusUnavailable"), "error"));
  if (!mod.verified && !isPreview(mod)) parts.push(element("p", t("installPending")));
  if (state.lastScan?.pckPath) parts.push(element("p", state.lastScan.pckPath, "file-detail"));
  if (state.lastScan?.pckSha256 === mod.adapter?.baseline?.sha256 && mod.adapter && mod.supportedGameVersions?.length === 1)
    parts.push(element("p", t("detectedVersion") + " · " + mod.supportedGameVersions[0]));
  if (state.lastScan?.pckSha256) parts.push(element("p", "SHA-256 · " + state.lastScan.pckSha256, "file-detail"));
  const repair = state.lastScan?.repair?.[mod.id];
  if (repair) parts.push(element("p", t("backup") + " · " + repair[0], "file-detail"));
  if (repair?.[1]) parts.push(element("p", t(repair[1]) || repair[1]));
  if (["restoreResidue", "identifyPending", "loaderConflict"].includes(modState)) parts.push(element("p", t(modState)));
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
    if (!state.pckDir || currentAction(mod) !== action) return details(mod);
    return installDialog(mod, action);
  });
}

async function installDialog(mod, action) {
  if (state.busyMod) return;
  const path = state.game;
  const target = state.pckDir;
  const title = t(action) + " · " + nameOf(mod) + " " + mod.version;
  const steps = element("ol", "", "install-steps");
  const lastStep = action === "identify" ? "identify" : action === "adoptManual" ? "adoptManual" : "installStep";
  const rows = ["downloadStep", "verifyStep", lastStep].map(key => {
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
  show(title, steps, location, bar.el);
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
    stage = 2;
    if (path !== state.game || target !== state.pckDir) throw "statusUnavailable";
    rows[stage].textContent = t("working");
    close.disabled = true;
    dialog.addEventListener("cancel", preventCancel);
    if (action === "identify") {
      await syncGameMods(true);
      if (state.scan !== "ready") throw state.scanError || "statusUnavailable";
      rows[stage].textContent = t("disk_" + state.modStates[mod.id]);
      if (state.modStates[mod.id] === "manualInstall") {
        show(title, steps, location, button(t("adoptManual"), () => startInstall(mod, "adoptManual"), "primary"));
        return;
      }
    } else {
      applyValidation(await installMod(path, mod, action === "adoptManual", target), path);
      rows[stage].textContent = t("done");
    }
    show(title, steps, location, button(t("close"), closeDialog));
  } catch (error) {
    if (!ownsDialog()) return;
    const [key, ...detail] = String(error).split(": ");
    if (["downloadFirst", "packageCorrupt"].includes(key)) delete state.packages[mod.id];
    rows[stage].textContent = t("failed");
    let retryButton;
    if (ownsDialog()) {
      const message = element("p", [t(key) || key, ...detail].join(" · "), "error");
      const retry = ["downloadFailed", "packageCorrupt", "downloadFirst", "gameRunning", "gamePermissionDenied", "diskSpace"].includes(key);
      if (retry) {
        retryButton = button(t("retry"), () => startInstall(mod, action), "primary");
        retryButton.disabled = true;
      }
      show(title, steps, location, message, ...(retryButton ? [retryButton] : []));
    }
    if (stage === 2 && path && path === state.game) await syncGameMods(true);
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
  return modAction({managed:trustedPackage(mod), verified:mod.verified || isPreview(mod),
    game:state.game, scan:state.scan, disk:state.modStates[mod.id]});
}

function primaryAction(mod, name) {
  const action = currentAction(mod);
  const el = button(t(action === "review" ? "viewReason" : action), () => {
    if (action === "review") return details(mod);
    if (action === "retryCheck") return syncGameMods(true);
    if (action !== "uninstall") return startInstall(mod, action);
    const path = state.game;
    const target = state.pckDir;
    show(t(action) + " · " + name, element("p", state.lastScan?.pckPath || target, "file-detail"), button(t(action), async () => {
      if (state.busyMod || path !== state.game || target !== state.pckDir) return;
      state.busyMod = mod.id;
      render();
      show(t(action) + " · " + name, element("p", t("uninstallingMod")));
      try {
        applyValidation(await uninstallMod(path, mod, target), path);
        closeDialog();
      } catch (error) {
        if (state.game === path) await syncGameMods(true);
        throw error;
      } finally {
        state.busyMod = "";
        render();
      }
    }, "primary"));
  }, ["review", "uninstall", "checking"].includes(action) ? "secondary" : "primary");
  el.disabled = Boolean(state.busyMod) || action === "checking";
  el.classList.add("btn-block");
  return el;
}

function card(mod, index) {
  const name = nameOf(mod);
  const local = state.inventory[mod.repo];
  const status = state.scan === "failed" ? "review" : versionState(local, mod.version, mod.verified);
  const item = element("article", "", "card");
  item.style.setProperty("--i", String(index));

  const body = element("div", "", "card-body");
  const heading = element("h2", "", "card-title");
  const link = element("a", name);
  link.href = "#" + encodeURIComponent(mod.repo);
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
  footer.append(primaryAction(mod, name));
  item.append(cover(mod, name, status), body, footer);
  return item;
}

export function renderModList(content) {
  if (state.scan === "failed") content.append(button(t("retryCheck"), () => syncGameMods(true), "secondary", "refresh"));
  const query = $("input").value.trim().toLowerCase();
  const matches = visibleMods(state.mods, {page: state.page, query, inventory: state.inventory});
  if (matches.length) {
    const grid = element("div", "", "grid");
    grid.append(...matches.map(card));
    content.append(grid);
  } else if (state.page === "installed" && state.scan === "checking") {
    content.append(element("p", t("checking"), "empty"));
  } else if (state.scan !== "failed" || state.page === "catalog") {
    content.append(element("p", t(state.page === "installed" ? "noMods" : "noMatch"), "empty"));
  }
}
