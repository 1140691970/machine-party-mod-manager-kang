import { locales, messages, systemLocale } from "./languages.js";

const savedLocale = localStorage.getItem("language");

export const state = {
  locale: locales.includes(savedLocale) ? savedLocale : systemLocale(navigator.language),
  page: "catalog",
  mods: [],
  previewMod: null,
  game: localStorage.getItem("game-path") || "",
  pckDir: "",
  inventory: {},
  modStates: {},
  inventoryFailed: false,
  appVersion: "",
  release: undefined,
  checking: false,
  installing: false,
  busyMod: "",
  checkResult: ""
};

export const t = key => messages[key][locales.indexOf(state.locale)];

export function setLocale(locale) {
  state.locale = locale;
  localStorage.setItem("language", locale);
}

let renderer = () => {};
export const onRender = fn => { renderer = fn; };
export const render = () => renderer();
