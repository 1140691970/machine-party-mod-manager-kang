import { gameProcess } from "./bridge.js";
import { button, element } from "./dom.js";
import { awaitGameExit } from "./game-exit.js";
import { state, t } from "./state.js";

export async function confirmGameExit(path, dir, ownerActive) {
  const modal = element("dialog", "", "dialog");
  modal.setAttribute("aria-label", t("runningTitle"));
  const head = element("div", "", "dialog-head");
  head.append(element("h2", t("runningTitle")));
  const body = element("div", "", "dialog-body");
  modal.append(head, body);
  let cancelled = false;
  let finishChoice;
  function cancel() {
    cancelled = true;
    finishChoice?.("cancel");
  }
  modal.addEventListener("cancel", event => { event.preventDefault(); cancel(); });
  function actions(...items) {
    const row = element("div", "", "dialog-actions");
    row.append(button(t("cancelModUpdate"), cancel), ...items);
    return row;
  }
  function choose(stage) {
    if (!modal.open) {
      document.body.append(modal);
      modal.showModal();
    }
    return new Promise(resolve => {
      finishChoice = resolve;
      const stalled = stage === "stillRunning";
      const buttons = stalled
        ? [button(t("waitGame"), () => resolve("wait"), "primary"), button(t("forceGame"), () => resolve("force"))]
        : [button(t("closeGameContinue"), () => resolve("close"), "primary")];
      body.replaceChildren(element("p", t(stalled ? "gameCloseStalled" : "gameClosePrompt")), actions(...buttons));
      body.querySelector("button").focus();
    });
  }
  try {
    return await awaitGameExit({
      process: action => gameProcess(path, dir, action), choose,
      active: () => !cancelled && ownerActive() && state.game === path,
      waiting: () => body.replaceChildren(element("p", t("waitingGameExit")), actions()),
      pause: () => new Promise(resolve => setTimeout(resolve, 1000))
    });
  } finally {
    if (modal.open) modal.close();
    modal.remove();
  }
}
