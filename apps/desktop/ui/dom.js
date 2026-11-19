import { icon } from "./icons.js";
import { messages } from "./languages.js";
import { t } from "./state.js";

export const $ = selector => document.querySelector(selector);

export function element(tag, text, cls) {
  const el = document.createElement(tag);
  if (text) el.textContent = text;
  if (cls) el.className = cls;
  return el;
}

// Buttons are collected into the dialog's action row; everything else is body content.
export function show(title, ...items) {
  $("#dialogTitle").textContent = title;
  const actions = element("div", "", "dialog-actions");
  const content = items.filter(item => !item.matches(".btn") || item.matches(".btn-link"));
  actions.append(...items.filter(item => !content.includes(item)));
  $("#dialogBody").replaceChildren(...content, ...(actions.childElementCount ? [actions] : []));
  if (!$("dialog").open) $("dialog").showModal();
}

export const closeDialog = () => $("dialog").close();

// Commands reject with message keys where possible; anything else is shown verbatim.
export function button(text, action, variant = "secondary", iconName) {
  const el = element("button", "", "btn btn-" + variant);
  if (iconName) el.append(icon(iconName));
  el.append(text);
  el.onclick = async () => {
    try {
      await action();
    } catch (error) {
      const [key, ...detail] = String(error).split(": ");
      show(t("failed"), element("p", [messages[key] ? t(key) : key, ...detail].join(" · "), "error"));
    }
  };
  return el;
}

export const tag = (text, tone = "") => element("span", text, "tag" + (tone ? " tag-" + tone : ""));

export function progress() {
  const el = element("div", "", "progress");
  el.setAttribute("role", "progressbar");
  el.setAttribute("aria-valuemin", "0");
  el.setAttribute("aria-valuemax", "100");
  el.append(element("span"));
  const set = pct => {
    el.style.setProperty("--value", pct + "%");
    el.setAttribute("aria-valuenow", String(pct));
  };
  set(0);
  return { el, set };
}

export function hydrateIcons(root = document) {
  for (const el of root.querySelectorAll("[data-icon]")) el.prepend(icon(el.dataset.icon));
}
