import { cancelSteamRestore, restoreSteamGame, steamRestoreDir } from "./bridge.js";
import { $, button, closeDialog, element, show } from "./dom.js";
import { confirmGameExit } from "./game-exit-dialog.js";
import { applyValidation } from "./game-folder.js";
import { render, state, t } from "./state.js";

export async function promptSteamRestore() {
  const path = state.game;
  if (!path || state.busyMod) return;
  const dir = await steamRestoreDir(path);
  if (path !== state.game || state.busyMod || $("dialog[open]")) return;
  show(t("steamRestore"), element("p", t("steamRestoreHint")), element("p", dir, "panel-value"),
    button(t("cancelModUpdate"), closeDialog), button(t("steamRestoreStart"), async () => {
      const dialog = $("dialog");
      if (state.busyMod || state.game !== path) return;
      state.busyMod = "steam-restore";
      render();
      const close = $("#close");
      const previousClose = close.onclick;
      let stop;
      let finished = false;
      const onCancel = event => { event.preventDefault(); stop?.click(); };
      try {
        const active = () => dialog.open && state.game === path;
        if (!await confirmGameExit(path, dir, active) || !active()) return;
        close.disabled = true;
        close.onclick = () => stop?.click();
        dialog.addEventListener("cancel", onCancel);
        show(t("steamRestore"), element("p", t("steamRestoreWaiting")));
        const result = await restoreSteamGame(path, dir, phase => {
          if (finished) return;
          if (phase === "waiting") {
            stop = button(t("steamRestoreStop"), async () => {
              if (!stop || stop.disabled) return;
              stop.disabled = true;
              await cancelSteamRestore();
            });
            close.disabled = false;
            show(t("steamRestore"), element("p", t("steamRestoreWaiting")), stop);
          } else if (phase === "cleaning") {
            stop = null;
            close.disabled = true;
            show(t("steamRestore"), element("p", t("steamRestoreCleaning")));
          }
        });
        applyValidation(result, path);
        show(t("steamRestore"), element("p", t("steamRestoreDone")));
      } catch (error) {
        if (String(error) !== "steamRestoreCancelled") throw error;
        closeDialog();
      } finally {
        finished = true;
        dialog.removeEventListener("cancel", onCancel);
        close.onclick = previousClose;
        close.disabled = false;
        state.busyMod = "";
        render();
      }
    }, "primary"));
}
