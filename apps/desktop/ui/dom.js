import { messages } from "./languages.js";
import { t } from "./state.js";

export const $ = selector => document.querySelector(selector);

export function element(tag, text, cls) {
  const el = document.createElement(tag);
  if (text) el.textContent = text;
  if (cls) el.className = cls;
  return el;
}

export function show(title, ...items) {
  $("#dialogTitle").textContent = title;
  $("#dialogBody").replaceChildren(...items);
  if (!$("dialog").open) $("dialog").showModal();
}

export const closeDialog = () => $("dialog").close();

// Commands reject with message keys where possible; anything else is shown verbatim.
export function button(text, action, cls) {
  const el = element("button", text, cls);
  el.onclick = async () => {
    try {
      await action();
    } catch (error) {
      const key = String(error);
      show(t("failed"), element("p", messages[key] ? t(key) : key, "error"));
    }
  };
  return el;
}
