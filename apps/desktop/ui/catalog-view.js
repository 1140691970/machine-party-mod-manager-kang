import { downloadUrl } from "./online-catalog.js";
import { installMod, isDesktop, openProject, uninstallMod } from "./bridge.js";
import { visibleMods } from "./catalog.js";
import { $, button, closeDialog, element, progress, show, tag } from "./dom.js";
import { applyValidation, pickGame } from "./game-folder.js";
import { render, state, t } from "./state.js";
import { versionState } from "./versions.js";

const nameOf = mod => mod.name[state.locale];

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

async function runInstall(mod, name, action) {
  if (state.busyMod || state.installing) return;
  state.busyMod = mod.id;
  render();
  const statusEl = element("p", t("installingMod"));
  const bar = progress();
  show(t(action) + " · " + name, statusEl, bar.el);
  try {
    const validation = await installMod(state.game, mod, state.mods, pct => {
      statusEl.textContent = t("installingMod") + " · " + pct + "%";
      bar.set(pct);
    });
    applyValidation(validation);
    closeDialog();
  } finally {
    state.busyMod = "";
    render();
  }
}

async function runUninstall(mod, name) {
  if (state.busyMod || state.installing) return;
  state.busyMod = mod.id;
  render();
  show(t("uninstall") + " · " + name, element("p", t("uninstallingMod")));
  try {
    applyValidation(await uninstallMod(state.game, mod, state.mods));
    closeDialog();
  } finally {
    state.busyMod = "";
    render();
  }
}

function primaryAction(mod, name, local, status) {
  const modState = state.modStates[mod.id];
  const canInstall = mod.verified || mod === state.previewMod;
  let action = "install";
  if (status === "review" || modState === "gameUpdatedOrModified" || modState === "needsRepair")
    action = "review";
  else if (status === "available" || status === "waiting") action = "update";
  else if (local !== undefined) action = "uninstall";
  else if (modState === "manualInstall" && canInstall) action = "adoptManual";
  const el = button(t(action), () => {
    if (action === "review") return details(mod);
    if (action === "update" && status === "waiting")
      return show(t(action) + " · " + name, element("p", t("hold")));
    if ((action === "install" || action === "adoptManual") && !canInstall)
      return show(t(action) + " · " + name, element("p", t("installPending")));
    if (!isDesktop || !mod.adapter)
      return show(t(action) + " · " + name, element("p", t("enginePending")));
    if (!state.game) return pickGame();
    if (action === "uninstall") return runUninstall(mod, name);
    return runInstall(mod, name, action);
  }, action === "uninstall" || action === "review" ? "secondary" : "primary");
  el.disabled = Boolean(state.busyMod);
  el.classList.add("btn-block");
  return el;
}

function card(mod, index) {
  const name = nameOf(mod);
  const local = state.inventory[mod.repo];
  const status = state.inventoryFailed ? "review" : versionState(local, mod.version, mod.verified);
  const item = element("article", "", "card");
  item.style.setProperty("--i", String(index));

  const body = element("div", "", "card-body");
  const heading = element("h2", "", "card-title");
  const link = element("a", name);
  link.href = "#" + encodeURIComponent(mod.repo);
  link.onclick = event => { event.preventDefault(); details(mod); };
  heading.append(link);
  body.append(heading, element("p", mod.summary[state.locale], "card-summary"));
  if (local !== undefined) {
    const versions = element("div", "", "comparison");
    versions.append(
      element("span", t("local") + " · " + local),
      element("span", t("release") + " · " + (mod.version || t("unlisted")))
    );
    body.append(versions);
  }

  const footer = element("div", "", "card-actions");
  footer.append(primaryAction(mod, name, local, status));
  item.append(cover(mod, name, status), body, footer);
  return item;
}

export function renderModList(content) {
  if (state.inventoryFailed) content.append(element("p", t("inventoryError"), "empty error"));
  const query = $("input").value.trim().toLowerCase();
  const matches = visibleMods(state.mods, {page: state.page, query, inventory: state.inventory});
  if (matches.length) {
    const grid = element("div", "", "grid");
    grid.append(...matches.map(card));
    content.append(grid);
  } else if (!state.inventoryFailed || state.page === "catalog") {
    content.append(element("p", t(state.page === "installed" ? "noMods" : "noMatch"), "empty"));
  }
}
