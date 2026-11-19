import { downloadUrl } from "./online-catalog.js";
import { modAction } from "./mod-action.js";
import { clearPackage, downloadMod, installMod, isDesktop, openProject, uninstallMod } from "./bridge.js";
import { visibleMods } from "./catalog.js";
import { $, button, closeDialog, element, progress, show, tag } from "./dom.js";
import { applyValidation, pickGame, syncGameMods } from "./game-folder.js";
import { render, state, t } from "./state.js";
import { versionState } from "./versions.js";

const nameOf = mod => mod.name[state.locale];

const cached = mod => Boolean(mod.package && state.packages[mod.id] === mod.package.sha256);
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
  if (!mod.verified && mod !== state.previewMod) parts.push(element("p", t("installPending")));
  if (state.pckDir) parts.push(element("p", state.pckDir));
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
    const link = element("a", t(mod.package.mirrorApproved ? "downloadPackage" : "authorRelease"), "btn btn-link");
    if (mod.package.mirrorApproved) {
      link.href = downloadUrl(mod);
      link.download = mod.package.filename;
    } else {
      link.href = `https://github.com/${mod.repo}/releases/tag/${mod.version}`;
      link.target = "_blank";
      link.rel = "noopener noreferrer";
    }
    parts.push(link);
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
  const label = mod === state.previewMod && status === "pending" ? "testRelease" : status;
  tags.append(version, tag(t(label), statusTone[status]));
  box.append(tags);
  return box;
}

async function perform(mod, action, path, expectedDir) {
  if (state.busyMod || (path && (path !== state.game || expectedDir !== state.pckDir))) return;
  state.busyMod = mod.id;
  render();
  const bar = progress();
  show(t(action) + " · " + nameOf(mod), action === "download" ? bar.el : element("p", t(action === "uninstall" ? "uninstallingMod" : "installingMod")));
  try {
    if (action === "download") {
      await downloadMod(mod, pct => bar.set(pct));
      state.packages[mod.id] = mod.package.sha256;
      if (state.scan === "failed" || state.modStates[mod.id] === "identifyPending") await syncGameMods(true);
    } else {
      const validation = action === "uninstall" ? await uninstallMod(path, mod, expectedDir)
        : await installMod(path, mod, action === "adoptManual", expectedDir);
      applyValidation(validation, path);
    }
    closeDialog();
  } catch (error) {
    if (["downloadFirst", "packageCorrupt"].includes(String(error))) delete state.packages[mod.id];
    if (path && path === state.game) await syncGameMods(true);
    if (String(error).startsWith("internalPackage:")) throw String(error) + " · " + mod.version;
    throw error;
  } finally {
    state.busyMod = "";
    render();
  }
}

function primaryAction(mod, name, local) {
  const action = modAction({managed: trustedPackage(mod), verified: mod.verified || mod === state.previewMod,
    cached: cached(mod), game: state.game, scan: state.scan, disk: state.modStates[mod.id], local});
  const el = button(t(action === "review" ? "viewReason" : action), () => {
    if (action === "review") return details(mod);
    if (action === "choose") return pickGame();
    if (action === "retryCheck") return syncGameMods(true);
    if (action === "download") return perform(mod, action, "");
    const path = state.game;
    const target = state.pckDir;
    show(t(action) + " · " + name, element("p", target), button(t(action), () => perform(mod, action, path, target), "primary"));
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
  footer.append(primaryAction(mod, name, local));
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
