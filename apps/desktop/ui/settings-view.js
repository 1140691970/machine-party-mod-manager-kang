import { checkApp, showRelease } from "./app-update.js";
import { isDesktop, openProject } from "./bridge.js";
import { $, button, element, tag } from "./dom.js";
import { applyValidation, detectGame, pickGame } from "./game-folder.js";
import { locales } from "./languages.js";
import { formatLoaderNote, runManualLoaderReload } from "./loader-upgrade.js";
import { render, setLocale, state, t } from "./state.js";

import { promptSteamRestore } from "./steam-restore.js";

const languageNames = ["简体中文", "繁體中文", "English"];

function languagePanel(applyLocale) {
  const panel = element("section", "", "panel");
  const row = element("div", "", "panel-row");
  const group = element("div", "", "segmented");
  group.setAttribute("role", "group");
  group.setAttribute("aria-label", t("language"));
  languageNames.forEach((name, index) => {
    const code = locales[index];
    const active = state.locale === code;
    const item = element("button", name, "segment" + (active ? " active" : ""));
    item.type = "button";
    item.setAttribute("aria-pressed", String(active));
    item.onclick = () => {
      if (state.locale === code) return;
      setLocale(code);
      applyLocale();
      render();
      $(".segment.active")?.focus();
    };
    group.append(item);
  });
  row.append(element("h2", t("language")), group);
  panel.append(row);
  return panel;
}

function folderPanel() {
  const panel = element("section", "", "panel");
  const row = element("div", "", "panel-row panel-row-folder");
  const info = element("div", "", "panel-info");
  const heading = element("div", "", "panel-heading");
  heading.append(element("h2", t("folder")));
  if (state.game && state.scan === "ready" && state.lastScan) {
    const baselineMod = state.pinned.find(item =>
      item.adapter?.baseline?.sha256 && item.supportedGameVersions?.length === 1
      && item.adapter.baseline.sha256 === state.lastScan.pckSha256);
    if (baselineMod) {
      const ver = tag(baselineMod.supportedGameVersions[0]);
      ver.classList.add("tag-mono");
      heading.append(ver);
    }
  }
  info.append(heading, element("p", state.game || t("unset"), "panel-value"));
  row.append(info);
  if (isDesktop) {
    const actions = element("div", "", "panel-actions");
    actions.append(button(t("choose"), pickGame, "primary", "folder"),
      button(t("rescan"), () => detectGame(true), "secondary", "refresh"));
    row.append(actions);
  }
  panel.append(row);
  return panel;
}

function appPanel() {
  const panel = element("section", "", "panel");
  const row = element("div", "", "panel-row");
  const repoLink = element("button", "Machine Party " + t("manager"), "project-link");
  repoLink.type = "button";
  repoLink.onclick = () => openProject(state.appRepo);
  row.append(repoLink);
  if (state.appVersion) {
    const ver = element("button", "", "version-btn");
    ver.type = "button";
    ver.disabled = state.checking || state.installing;
    ver.append(element("span", state.appVersion));
    if (state.release) {
      const dot = element("span", "", "update-dot");
      dot.setAttribute("aria-hidden", "true");
      ver.append(dot);
      const tip = t("appUpdate") + " · v" + state.release.version;
      ver.title = tip;
      ver.setAttribute("aria-label", state.appVersion + " · " + tip);
    } else {
      ver.title = t("checkApp");
      ver.setAttribute("aria-label", state.appVersion + " · " + t("checkApp"));
    }
    ver.onclick = () => (state.release ? showRelease() : checkApp(true));
    row.append(ver);
  }
  panel.append(row);
  const note = state.checking ? t("checkingApp") : state.checkResult ? t(state.checkResult) : "";
  if (note) panel.append(element("p", note, "panel-note"));
  return panel;
}

function loaderPanel() {
  const panel = element("section", "", "panel");
  const row = element("div", "", "panel-row");
  const info = element("div", "", "panel-info");
  const heading = element("div", "", "panel-heading");
  heading.append(element("h2", t("loaderTitle")));
  const loader = state.scan === "ready" ? state.lastScan?.loader : null;
  let desc = !state.game
    ? t("unset")
    : state.scan === "failed"
      ? (t(state.scanError) || state.scanError || t("statusUnavailable"))
      : t("checking");
  if (loader) {
    if (loader.kind === "managed") {
      const badgeText = loader.needsUpgrade
        ? `v${loader.installedVersion || "?"} → v${loader.targetVersion}`
        : `v${loader.installedVersion || loader.targetVersion}`;
      const badge = tag(badgeText);
      badge.classList.add("tag-mono");
      heading.append(badge);
      desc = loader.needsUpgrade
        ? formatLoaderNote({key: "loaderNeedsUpgrade", from: loader.installedVersion || "?", to: loader.targetVersion})
        : formatLoaderNote({key: "loaderUpToDate", version: loader.installedVersion || loader.targetVersion});
    } else if (loader.kind === "external") {
      desc = t("loaderExternal");
    } else if (loader.kind === "modified") {
      desc = t("loaderModified");
    } else {
      if (loader.targetVersion) {
        const badge = tag(`v${loader.targetVersion}`);
        badge.classList.add("tag-mono");
        heading.append(badge);
      }
      desc = t("loaderNone");
    }
  }
  info.append(heading, element("p", desc, "panel-value"));
  const action = button(
    t("loaderReload"),
    () => runManualLoaderReload(applyValidation),
    loader?.needsUpgrade ? "primary" : "secondary",
    "refresh"
  );
  action.disabled = !state.game || !loader?.canReload || Boolean(state.busyMod) || state.installing;
  row.append(info, action);
  panel.append(row);
  const note = formatLoaderNote(state.loaderNote);
  if (note) panel.append(element("p", note, "panel-note"));
  return panel;
}

export function renderSettings(content, applyLocale) {
  const page = element("div", "", "settings");
  page.append(languagePanel(applyLocale), folderPanel());
  if (isDesktop) {
    page.append(loaderPanel());
    const panel = element("section", "", "panel");
    const row = element("div", "", "panel-row");
    const info = element("div", "", "panel-info");
    info.append(element("h2", t("steamRestore")), element("p", t("steamRestoreHint"), "panel-value"));
    const action = button(t("steamRestoreStart"), promptSteamRestore);
    action.disabled = !state.game || Boolean(state.busyMod) || state.installing;
    row.append(info, action);
    panel.append(row);
    page.append(panel);
  }
  page.append(appPanel());
  content.append(page);
}
