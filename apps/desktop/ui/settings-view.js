import { checkApp } from "./app-update.js";
import { isDesktop } from "./bridge.js";
import { $, button, element } from "./dom.js";
import { detectGame, pickGame } from "./game-folder.js";
import { locales } from "./languages.js";
import { render, setLocale, state, t } from "./state.js";

const languageNames = ["简体中文", "繁體中文", "English"];

function languagePanel(applyLocale) {
  const panel = element("section", "", "panel");
  const row = element("label", "", "panel-row");
  const select = element("select", "", "select");
  languageNames.forEach((name, index) => {
    const option = element("option", name);
    option.value = locales[index];
    select.append(option);
  });
  select.value = state.locale;
  select.onchange = () => {
    setLocale(select.value);
    applyLocale();
    render();
    $("select").focus();
  };
  row.append(element("h2", t("language")), select);
  panel.append(row);
  return panel;
}

function folderPanel() {
  const panel = element("section", "", "panel");
  panel.append(element("h2", t("folder")), element("p", state.game || t("unset"), "panel-value"));
  if (isDesktop) {
    const actions = element("div", "", "panel-actions");
    actions.append(button(t("choose"), pickGame, "primary", "folder"),
      button(t("rescan"), () => detectGame(true), "secondary", "refresh"));
    panel.append(actions);
  }
  return panel;
}

function managerPanel() {
  const panel = element("section", "", "panel");
  const row = element("div", "", "panel-row");
  const check = button(t(state.checking ? "checkingApp" : "checkApp"), () => checkApp(true), "secondary", "refresh");
  check.disabled = state.checking || state.installing;
  row.append(element("h2", t("manager") + " " + state.appVersion), check);
  panel.append(row);
  if (state.checkResult) panel.append(element("p", t(state.checkResult), "panel-note"));
  return panel;
}

export function renderSettings(content, applyLocale) {
  const page = element("div", "", "settings");
  page.append(languagePanel(applyLocale), folderPanel());
  if (isDesktop) page.append(managerPanel());
  content.append(page);
}
