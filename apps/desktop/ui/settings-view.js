import { checkApp } from "./app-update.js";
import { isDesktop } from "./bridge.js";
import { $, button, element } from "./dom.js";
import { detectGame, pickGame } from "./game-folder.js";
import { locales } from "./languages.js";
import { render, setLocale, state, t } from "./state.js";

const languageNames = ["简体中文", "繁體中文", "English"];

function languagePicker(applyLocale) {
  const label = element("label", t("language"), "language");
  const select = element("select");
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
  label.append(select);
  return label;
}

export function renderSettings(content, applyLocale) {
  const box = element("div", "", "box");
  box.append(languagePicker(applyLocale), element("h2", t("folder")), element("p", state.game || t("unset")));
  if (isDesktop) {
    box.append(button(t("choose"), pickGame, "control primary"),
      button(t("rescan"), () => detectGame(true), "control"));
    const check = button(t(state.checking ? "checkingApp" : "checkApp"), () => checkApp(true), "control");
    check.disabled = state.checking || state.installing;
    box.append(element("h2", t("manager") + " " + state.appVersion), check);
    if (state.checkResult) box.append(element("p", t(state.checkResult)));
  }
  content.append(box);
}
