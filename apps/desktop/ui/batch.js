// Pure helpers for the catalog's batch operations. No DOM, state or Tauri access here.
// A "row" describes one card as {ready, action, removable}:
//   ready     - a game copy is selected and its scan finished successfully
//   action    - the card's single-mod action (from currentAction)
//   removable - the manager holds an uninstall transaction for this mod

export const BATCH_KINDS = ["install", "enable", "disable", "uninstall"];

const LABELS = {
  install: "batchInstall",
  enable: "batchEnable",
  disable: "batchDisable",
  uninstall: "batchUninstall"
};

const CONFIRMS = {
  install: "batchConfirmInstall",
  enable: "batchConfirmEnable",
  disable: "batchConfirmDisable",
  uninstall: "batchConfirmUninstall"
};

const cap = kind => kind.charAt(0).toUpperCase() + kind.slice(1);

// i18n keys for the button label, the "in progress" dialog title and the empty-state hint.
export const batchLabelKey = kind => LABELS[kind] || "";
export const batchRunningKey = kind => LABELS[kind] ? "batchRunning" + cap(kind) : "";
export const batchEmptyKey = kind => LABELS[kind] ? "batchEmpty" + cap(kind) : "";
export const batchConfirmKey = kind => CONFIRMS[kind] || "";

// Whether a card's current state matches an operation, independent of scan readiness.
// "install" covers both fresh installs and approved updates so players have one action.
export function batchMatches(kind, row) {
  if (!row) return false;
  if (kind === "install") return (row.action === "install" && !row.removable) || row.action === "updateMod";
  const removable = Boolean(row.removable) && row.action !== "checking" && row.action !== "retryCheck";
  if (kind === "uninstall") return removable;
  const toggleable = row.toggleable === undefined ? removable : (removable && Boolean(row.toggleable));
  if (kind === "enable") return toggleable && Boolean(row.disabled);
  if (kind === "disable") return toggleable && !row.disabled;
  return false;
}

// A card can be executed only when the game scan is ready AND its state matches.
export function batchEligible(kind, row) {
  return Boolean(row && row.ready && batchMatches(kind, row));
}

// Resolves the concrete single-mod action to run for one item.
export function batchItemAction(kind, row) {
  if (!batchMatches(kind, row)) return "";
  if (kind === "uninstall" || kind === "enable" || kind === "disable") return kind;
  return row.action === "updateMod" ? "updateMod" : "install";
}

export function batchSelectable(mods, kind, rowOf) {
  return mods.filter(mod => batchEligible(kind, rowOf(mod))).map(mod => mod.id);
}

// Action badge: how many of the *ticked* cards match this operation.
// Never derived from all eligible cards - the number follows the selection.
export function batchSelectedCount(mods, kind, rowOf, selected) {
  const chosen = new Set(selected || []);
  return mods.filter(mod => chosen.has(mod.id) && batchMatches(kind, rowOf(mod))).length;
}

// Split the live selection into an executable queue (catalog order) and the
// ticked cards that no longer match the operation. Nothing outside the
// selection can ever enter the queue.
export function batchTargets(mods, kind, rowOf, selected) {
  const chosen = new Set(selected || []);
  const eligible = new Set(batchSelectable(mods, kind, rowOf));
  const queue = [];
  const filtered = [];
  for (const mod of mods) {
    if (!chosen.has(mod.id)) continue;
    if (eligible.has(mod.id)) queue.push(mod.id);
    else filtered.push(mod.id);
  }
  return {queue, filtered};
}

export function canRunBatch(selected) {
  return Boolean(selected && selected.length);
}

export function batchSummary(results) {
  const summary = {ok: 0, fail: 0, skip: 0};
  for (const result of results) {
    if (result === "ok") summary.ok++;
    else if (result === "skip") summary.skip++;
    else summary.fail++;
  }
  return summary;
}

// Selection is keyed by mod id, so sorting, searching and filtering never shift it.
export function batchToggle(selected, id, checked) {
  const set = new Set(selected || []);
  if (checked) set.add(id);
  else set.delete(id);
  return [...set];
}

export function batchSelectAll(selected, ids) {
  return [...new Set([...(selected || []), ...(ids || [])])];
}

export function batchDeselect(selected, ids) {
  const drop = new Set(ids || []);
  return (selected || []).filter(id => !drop.has(id));
}

// Only entries that are still eligible at run time are executed, in catalog order.
export function batchQueue(ids, selected) {
  const chosen = new Set(selected || []);
  return (ids || []).filter(id => chosen.has(id));
}
