// All actions return whether the selected copy is still running.
export async function awaitGameExit({process, choose, waiting, active, pause, polls = 8}) {
  if (!active()) return false;
  if (!await process("check")) return active();
  let stage = "close";
  while (active()) {
    const action = await choose(stage);
    if (!active() || action === "cancel") return false;
    waiting();
    if (action !== "wait" && !await process(action)) return active();
    for (let i = 0; i < polls && active(); i++) {
      await pause();
      if (active() && !await process("check")) return active();
    }
    stage = "stillRunning";
  }
  return false;
}
