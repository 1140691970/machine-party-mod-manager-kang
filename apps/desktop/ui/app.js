import { checkApp } from "./app-update.js";
import { authorizeUpdates, appVersion, bundledCatalog, cachedPackages, isDesktop, setAppTitle } from "./bridge.js";
import { sortMods } from "./catalog.js";
import { renderModList } from "./catalog-view.js";
import { $, button, closeDialog, element, hydrateIcons, show } from "./dom.js";
import { detectGame, pickGame, syncGameMods, syncGameModsOnFocus } from "./game-folder.js";
import { icon } from "./icons.js";
import { renderSettings } from "./settings-view.js";
import { onRender, state, t } from "./state.js";

import { loadCatalog, restoreCatalog } from "./online-catalog.js";

let catalogStatus = "catalogLoading";
let catalogError = "";
let entered = false;

function applyLocale() {
  document.documentElement.lang = state.locale;
  document.title = "Machine Party " + t("manager");
  setAppTitle(document.title);
  $(".brand").setAttribute("aria-label", document.title);
  $(".brand small").textContent = t("manager");
  $("#search input").placeholder = t("search");
  $("#search input").setAttribute("aria-label", t("search"));
  const refresh = $("#refresh-catalog");
  refresh.title = t("refreshCatalog");
  refresh.setAttribute("aria-label", refresh.title);
  const settingsBtn = $("#open-settings");
  settingsBtn.title = t("settings");
  settingsBtn.setAttribute("aria-label", settingsBtn.title);
  $("#settingsTitle").textContent = t("settings");
  $("#close").setAttribute("aria-label", t("close"));
  $("#close-settings").setAttribute("aria-label", t("close"));
}

function renderSettingsDialog() {
  const dialog = $("#settings-dialog");
  if (!dialog?.open) return;
  const body = $("#settingsBody");
  body.replaceChildren();
  renderSettings(body, applyLocale);
}

function openSettings() {
  if (state.batch?.phase === "running") return;
  const dialog = $("#settings-dialog");
  if (!dialog) return;
  $("#settingsTitle").textContent = t("settings");
  const body = $("#settingsBody");
  body.replaceChildren();
  renderSettings(body, applyLocale);
  if (!dialog.open) dialog.showModal();
}

function closeSettings() {
  const dialog = $("#settings-dialog");
  if (dialog?.open) dialog.close();
}

function render() {
  const settingsBtn = $("#open-settings");
  const existingDot = settingsBtn?.querySelector(".update-dot");
  if (state.release && settingsBtn && !existingDot) {
    const dot = element("span", "", "update-dot");
    dot.setAttribute("aria-hidden", "true");
    settingsBtn.append(dot);
  } else if (!state.release && existingDot) {
    existingDot.remove();
  }
  const busyBatch = state.batch?.phase === "running";
  $("#search input").disabled = busyBatch;
  settingsBtn.disabled = busyBatch;
  const refresh = $("#refresh-catalog");
  const loading = catalogStatus === "catalogLoading";
  refresh.disabled = loading || Boolean(state.busyMod) || busyBatch;
  refresh.setAttribute("aria-busy", String(loading));
  const content = $("#content");
  content.replaceChildren();
  content.className = entered ? "" : "entering";
  entered = true;
  if (catalogStatus) {
    const isLoading = catalogStatus === "catalogLoading";
    const status = element("section", "", [
      "list-status",
      state.mods.length ? "compact" : "",
      isLoading ? "is-loading" : "is-warning"
    ].filter(Boolean).join(" "));
    status.setAttribute("role", "status");
    status.append(
      icon(isLoading ? "refresh" : "catalog"),
      element("p", [t(catalogStatus), t(catalogError) || catalogError].filter(Boolean).join(" · "))
    );
    if (!isLoading) {
      const retry = button(t("retryCatalog"), refreshCatalog, "secondary", "refresh");
      retry.classList.add("btn-sm");
      status.append(retry);
    }
    content.append(status);
  }
  if (!catalogStatus || state.mods.length) renderModList(content);
  renderSettingsDialog();
}

if (isDesktop) document.addEventListener("contextmenu", event => event.preventDefault());
onRender(render);
state.appVersion = await appVersion();
const bundled = isDesktop ? await bundledCatalog() : {mods: []};
state.pinned = bundled.mods;
state.removalMods = bundled.removalMods ?? [];
state.previewMod = bundled.previewMod ?? null;
state.previewMods = bundled.previewMods ?? (bundled.previewMod ? [bundled.previewMod] : []);
state.appRepo = bundled.repo || state.appRepo;

async function authorize(document, signature) {
  state.updateTargets = await authorizeUpdates(document, signature);
  const known = new Set([...state.pinned, ...state.removalMods].map(mod => mod.id));
  const approved = new Set(state.updateTargets.map(mod => mod.id));
  state.removalMods.push(...JSON.parse(document).mods.filter(mod => approved.has(mod.id) && !known.has(mod.id)));
}
const verifyCatalog = isDesktop ? authorize : undefined;
let catalog = await restoreCatalog(localStorage, verifyCatalog);
state.mods = catalog ? sortMods(catalog, state.pinned) : [];

async function refreshCatalog() {
  catalogStatus = "catalogLoading";
  catalogError = "";
  render();
  try {
    catalog = await loadCatalog(localStorage, fetch, verifyCatalog);
    state.mods = sortMods(catalog, state.pinned);
    catalogStatus = "";
    if (isDesktop && state.game) void syncGameMods();
  } catch (error) {
    catalogError = error.message || String(error);
    catalogStatus = catalog ? "catalogCached" : "catalogUnavailable";
  }
  render();
}

hydrateIcons();
$("#search input").oninput = render;
$("#refresh-catalog").onclick = refreshCatalog;
$("#open-settings").onclick = openSettings;
$("#close-settings").onclick = closeSettings;
$("#settings-dialog").addEventListener("click", event => {
  if (event.target === event.currentTarget) closeSettings();
});
$("#close").onclick = closeDialog;
applyLocale();
void refreshCatalog();
if (isDesktop) {
  window.addEventListener("focus", syncGameModsOnFocus);
  cachedPackages().then(result => { state.packages = {...result, ...state.packages}; render(); }).catch(() => {});
  detectGame().catch(error => show(t("failed"), element("p", String(error)), button(t("choose"), pickGame, "primary")));
  void checkApp(false);
}
