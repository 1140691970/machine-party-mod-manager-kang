import { checkApp, showRelease } from "./app-update.js";
import { appVersion, bundledCatalog, cachedPackages, isDesktop, setAppTitle } from "./bridge.js";
import { sortMods } from "./catalog.js";
import { renderModList } from "./catalog-view.js";
import { $, button, closeDialog, element, hydrateIcons, show } from "./dom.js";
import { detectGame, pickGame } from "./game-folder.js";
import { icon } from "./icons.js";
import { renderSettings } from "./settings-view.js";
import { onRender, state, t } from "./state.js";

import { cachedCatalog, loadCatalog } from "./online-catalog.js";

let catalogStatus = "catalogLoading";
let catalogError = "";
let shownPage = "";

function applyLocale() {
  document.documentElement.lang = state.locale;
  document.title = "Machine Party " + t("manager");
  setAppTitle(document.title);
  $(".brand").setAttribute("aria-label", document.title);
  $(".brand small").textContent = t("manager");
  $("input").placeholder = t("search");
  $("input").setAttribute("aria-label", t("search"));
  $("#close").setAttribute("aria-label", t("close"));
  for (const el of document.querySelectorAll("[data-page]")) {
    el.title = t(el.dataset.page);
    el.setAttribute("aria-label", el.title);
    el.querySelector(".nav-label").textContent = el.title;
  }
}

function render() {
  document.querySelectorAll("[data-page]").forEach(el => {
    const active = el.dataset.page === state.page;
    el.classList.toggle("active", active);
    if (active) el.setAttribute("aria-current", "page");
    else el.removeAttribute("aria-current");
  });
  const banner = $("#appRelease");
  banner.hidden = !state.release;
  if (state.release) banner.replaceChildren(icon("download"), t("appUpdate") + " · v" + state.release.version);
  banner.onclick = showRelease;
  $("h1").textContent = t(state.page);
  $("#subtitle").textContent = state.page === "settings" ? "" : t(state.page + "Sub");
  $("#search").hidden = state.page !== "catalog";
  const content = $("#content");
  content.replaceChildren();
  content.className = state.page === shownPage ? "" : "entering";
  shownPage = state.page;
  if (state.page === "settings") renderSettings(content, applyLocale);
  else {
    if (catalogStatus && state.page === "catalog") {
      const status = element("section", "", "list-status" + (state.mods.length ? " compact" : ""));
      status.setAttribute("role", "status");
      status.append(icon(catalogStatus === "catalogLoading" ? "refresh" : "catalog"), element("p", [t(catalogStatus), t(catalogError) || catalogError].filter(Boolean).join(" · ")));
      if (catalogStatus !== "catalogLoading") status.append(button(t("retryCatalog"), refreshCatalog, "link", "refresh"));
      content.append(status);
    }
    if (!catalogStatus || state.mods.length || state.page === "installed") renderModList(content);
  }
}

onRender(render);
state.appVersion = await appVersion();
const cached = cachedCatalog(localStorage);
const bundled = isDesktop ? await bundledCatalog() : {mods: []};
state.pinned = bundled.mods;
state.previewMod = bundled.previewMod ?? null;
state.mods = cached ? sortMods(cached) : [];

async function refreshCatalog() {
  catalogStatus = "catalogLoading";
  catalogError = "";
  render();
  try {
    state.mods = sortMods(await loadCatalog(localStorage));
    catalogStatus = "";
  } catch (error) {
    catalogError = error.message;
    catalogStatus = cachedCatalog(localStorage) ? "catalogCached" : "catalogUnavailable";
  }
  render();

}

hydrateIcons();
document.querySelectorAll("[data-page]").forEach(el => el.onclick = () => {
  state.page = el.dataset.page;
  render();
});
$("input").oninput = render;
$("#close").onclick = closeDialog;
applyLocale();
void refreshCatalog();
if (isDesktop) {
  cachedPackages().then(result => { state.packages = {...result, ...state.packages}; render(); }).catch(() => {});
  detectGame().catch(error => show(t("failed"), element("p", String(error)), button(t("choose"), pickGame, "primary")));
  void checkApp(false);
}
