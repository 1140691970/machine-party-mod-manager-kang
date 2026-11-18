import { checkAppUpdate, installAppUpdate, isDesktop } from "./bridge.js";
import { button, closeDialog, element, show } from "./dom.js";
import { render, state, t } from "./state.js";

export function showRelease() {
  if (!state.release || state.installing) return;
  const selected = state.release;
  show(t("appUpdate") + " · v" + selected.version, element("p", selected.notes || ""),
    button(t("installApp"), async () => {
      if (state.installing) return;
      state.installing = true;
      const status = element("p", t("loadingApp"));
      show(t("installApp"), status);
      try {
        await installAppUpdate(selected.version, pct => {
          status.textContent = t("loadingApp") + " · " + pct + "%";
        });
      } finally {
        state.installing = false;
      }
    }, "control primary"),
    button(t("close"), closeDialog, "control"));
}

export async function checkApp(manual) {
  if (!isDesktop || state.checking || state.installing) return;
  state.checking = true;
  state.checkResult = "";
  if (manual) render();
  try {
    state.release = await checkAppUpdate();
    state.checkResult = state.release ? "" : "latestApp";
  } catch (error) {
    state.checkResult = String(error) === "unsupportedPlatform" ? "unsupportedPlatform" : "appNetwork";
  } finally {
    state.checking = false;
    render();
  }
}
