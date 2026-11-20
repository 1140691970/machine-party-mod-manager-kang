import { checkAppUpdate, installAppUpdate, isDesktop } from "./bridge.js";
import { $, button, closeDialog, element, progress, show } from "./dom.js";
import { render, state, t } from "./state.js";

const dismissKey = "dismissed-app-update";
let activeClose;
let queuedPrompt;

function displayRelease() {
  if (!state.release || state.installing) return;
  const selected = state.release;
  const dialog = $("dialog");
  if (dialog && activeClose) {
    dialog.removeEventListener("close", activeClose);
    activeClose = null;
  }
  let started = false;
  const onClose = () => {
    activeClose = null;
    if (!started) localStorage.setItem(dismissKey, selected.version);
  };
  if (dialog) {
    activeClose = onClose;
    dialog.addEventListener("close", onClose, { once: true });
  }
  const body = selected.notes?.trim()
    ? element("p", selected.notes.trim(), "release-notes")
    : element("p", t("appUpdatePrompt"));
  show(t("appUpdate") + " · v" + selected.version, body,
    button(t("installApp"), async () => {
      if (state.installing) return;
      started = true;
      if (dialog && activeClose) {
        dialog.removeEventListener("close", activeClose);
        activeClose = null;
      }
      state.installing = true;
      const status = element("p", t("loadingApp"));
      const bar = progress();
      show(t("installApp"), status, bar.el);
      try {
        await installAppUpdate(selected.version, pct => {
          status.textContent = t("loadingApp") + " · " + pct + "%";
          bar.set(pct);
        });
      } finally {
        state.installing = false;
      }
    }, "primary", "download"),
    button(t("laterUpdate"), () => {
      localStorage.setItem(dismissKey, selected.version);
      closeDialog();
    }, "ghost"));
}

function queueReleasePrompt(manual) {
  if (!state.release || state.installing) return;
  if (!manual && localStorage.getItem(dismissKey) === state.release.version) return;
  if (queuedPrompt) {
    queuedPrompt.manual ||= manual;
    return;
  }
  const dialog = $("dialog[open]");
  if (dialog) {
    queuedPrompt = {manual};
    dialog.addEventListener("close", () => {
      const pending = queuedPrompt;
      queuedPrompt = undefined;
      queueReleasePrompt(pending.manual);
    }, { once: true });
    return;
  }
  displayRelease();
}

export function showRelease() {
  queueReleasePrompt(true);
}

export async function checkApp(manual) {
  if (!isDesktop || state.checking || state.installing) return;
  state.checking = true;
  if (manual) {
    state.checkResult = "";
    render();
  }
  let found = null;
  try {
    found = await checkAppUpdate();
    state.release = found;
    if (manual && !found) state.checkResult = "latestApp";
  } catch (error) {
    if (manual) {
      state.checkResult = String(error) === "unsupportedPlatform" ? "unsupportedPlatform" : "appNetwork";
    }
  } finally {
    state.checking = false;
    render();
  }
  if (found) queueReleasePrompt(manual);
}
