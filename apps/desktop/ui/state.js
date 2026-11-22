import { locales, messages, systemLocale } from "./languages.js";

const savedLocale = localStorage.getItem("language");

export const state = {
  locale: locales.includes(savedLocale) ? savedLocale : systemLocale(navigator.language),
  page: "catalog",
  mods: [],
  previewMod: null,
  previewMods: [],
  appRepo: "JamesGZM/machine-party-mod-manager",
  game: localStorage.getItem("game-path") || "",
  pckDir: "",
  inventory: {},
  modStates: {},
  scan: "checking",
  packages: {},
  pinned: [],
  removalMods: [],
  updateTargets: [],
  scanError: "",
  appVersion: "",
  release: undefined,
  checking: false,
  installing: false,
  busyMod: "",
  filterStatus: "all",
  filterCategory: "all",
  batchMode: false,
  // Persistent card selection while batch mode is active, keyed by mod id.
  selectedMods: [],
  // Batch run state: null, or {kind, phase: "running"|"done", ids: string[]}.
  batch: null,
  checkResult: "",
  loaderNote: null
};

export const t = key => messages[key]?.[locales.indexOf(state.locale)];

export function setLocale(locale) {
  state.locale = locale;
  localStorage.setItem("language", locale);
}

let renderer = () => {};
export const onRender = fn => { renderer = fn; };
export const render = () => renderer();
