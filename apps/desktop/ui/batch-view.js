import {
  BATCH_KINDS, batchConfirmKey, batchDeselect, batchEligible, batchEmptyKey, batchItemAction,
  batchLabelKey, batchRunningKey, batchSelectAll, batchSelectedCount, batchSummary,
  batchTargets, batchToggle, canRunBatch
} from "./batch.js";
import { downloadMod, installMod, setModsEnabled, uninstallMod, updateMod, verifyPackage } from "./bridge.js";
import { FILTER_STATUSES, catalogCategories, inventoryKey, statusCounts, visibleMods } from "./catalog.js";
import { $, button, closeDialog, element, progress, show } from "./dom.js";
import { confirmGameExit } from "./game-exit-dialog.js";
import { applyValidation, syncGameMods } from "./game-folder.js";
import { icon } from "./icons.js";
import { installationProblem } from "./mod-action.js";
import {
  batchRow, cached, isUnlistedDisabled, nameOf, removalEntry, statusRow, unlistedInstalledRows
} from "./mod-helpers.js";
import { ensureDependenciesCached } from "./mod-install-flow.js";
import { render, state, t } from "./state.js";

const BATCH_BUSY = "__batch__";
const BATCH_ICONS = {install: "download", enable: "enable", disable: "disable", uninstall: "close"};
const STATUS_KEYS = {
  all: "filterAll",
  enabled: "filterEnabled",
  disabled: "filterDisabled",
  notInstalled: "filterNotInstalled",
  updatable: "filterUpdatable"
};

let batchStripRefs = null;

export function toggleBatchSelection(id, checked, cardEl) {
  state.selectedMods = batchToggle(state.selectedMods, id, checked);
  cardEl?.classList.toggle("batch-selected", checked);
  syncBatchStrip();
}

export function batchCheckbox(mod, checked) {
  const label = element("label", "", "batch-check");
  label.setAttribute("aria-label", t("batchSelectMod").replace("{mod}", nameOf(mod)));
  label.title = nameOf(mod);
  const input = document.createElement("input");
  input.type = "checkbox";
  input.checked = checked;
  input.disabled = state.batch?.phase === "running";
  input.onchange = () => {
    if (state.batch?.phase === "running") return;
    toggleBatchSelection(mod.id, input.checked, label.closest(".card"));
  };
  label.append(input, element("span", "", "batch-check-box"));
  return {label, input};
}

export function syncBatchStrip() {
  if (!batchStripRefs || !batchStripRefs.strip.isConnected) {
    batchStripRefs = null;
    return;
  }
  const {count, toggleAll, clear, actionButtons, visibleIds} = batchStripRefs;
  const running = state.batch?.phase === "running";
  const selectedSet = new Set(state.selectedMods);
  const allVisibleSelected = visibleIds.length > 0 && visibleIds.every(id => selectedSet.has(id));
  count.textContent = t("batchSelected").replace("{count}", String(state.selectedMods.length));
  toggleAll.textContent = t(allVisibleSelected ? "batchDeselectVisible" : "batchSelectAll");
  toggleAll.disabled = running || visibleIds.length === 0;
  clear.disabled = running || !state.selectedMods.length;
  for (const kind of BATCH_KINDS) {
    const ref = actionButtons.get(kind);
    if (!ref) continue;
    const matched = batchSelectedCount(state.mods, kind, batchRow, state.selectedMods);
    ref.badge.textContent = String(matched);
    ref.btn.disabled = running;
    const activeInstall = kind === "install" && matched > 0;
    const activeToggle = (kind === "enable" || kind === "disable") && matched > 0;
    const activeUninstall = kind === "uninstall" && matched > 0;
    ref.btn.classList.toggle("btn-primary", activeInstall);
    ref.btn.classList.toggle("btn-secondary", activeToggle);
    ref.btn.classList.toggle("batch-op-danger", activeUninstall);
    ref.btn.classList.toggle("batch-op-idle", matched === 0);
  }
}

export function renderCatalogToolbar(content, visible) {
  const running = state.batch?.phase === "running";
  const toolbar = element("section", "", "catalog-toolbar");
  toolbar.setAttribute("role", "region");
  toolbar.setAttribute("aria-label", t("filterStatus"));

  const row = element("div", "", "toolbar-row");
  const filters = element("div", "", "toolbar-filters");

  // Status filter tabs (clean underline style with live counts scoped to search & category)
  const statusGroup = element("div", "", "filter-tabs");
  statusGroup.setAttribute("role", "group");
  statusGroup.setAttribute("aria-label", t("filterStatus"));
  const query = $("#search input")?.value || "";
  const scopedMods = visibleMods(state.mods, {query, category: state.filterCategory});
  const counts = statusCounts(scopedMods, statusRow);
  for (const item of unlistedInstalledRows(query)) {
    counts.all++;
    counts[isUnlistedDisabled(item) ? "disabled" : "enabled"]++;
  }
  for (const status of FILTER_STATUSES) {
    const active = state.filterStatus === status;
    const num = counts[status] ?? 0;
    const tab = element("button", "", "filter-tab" + (active ? " active" : ""));
    tab.type = "button";
    tab.disabled = running;
    tab.setAttribute("aria-pressed", String(active));
    tab.append(element("span", t(STATUS_KEYS[status])));
    const badgeClass = status === "updatable" && num > 0 ? "toolbar-badge toolbar-badge-accent" : "toolbar-count";
    tab.append(element("span", String(num), badgeClass));
    tab.onclick = () => {
      if (state.filterStatus === status) return;
      state.filterStatus = status;
      render();
    };
    statusGroup.append(tab);
  }
  filters.append(statusGroup);

  // Category filter tags (dynamic from catalog)
  const categories = catalogCategories(state.mods);
  if (categories.length > 1) {
    if (state.filterCategory !== "all" && !categories.includes(state.filterCategory)) {
      state.filterCategory = "all";
    }
    const divider = element("span", "", "toolbar-divider");
    divider.setAttribute("aria-hidden", "true");
    filters.append(divider);

    const catGroup = element("div", "", "filter-chips");
    catGroup.setAttribute("role", "group");
    catGroup.setAttribute("aria-label", t("filterCategory"));
    for (const cat of ["all", ...categories]) {
      const active = state.filterCategory === cat;
      const chip = element("button", cat === "all" ? t("filterAllCategories") : (t("category_" + cat) || cat),
        "filter-chip" + (active ? " active" : ""));
      chip.type = "button";
      chip.disabled = running;
      chip.setAttribute("aria-pressed", String(active));
      chip.onclick = () => {
        if (state.filterCategory === cat) return;
        state.filterCategory = cat;
        render();
      };
      catGroup.append(chip);
    }
    filters.append(catGroup);
  }

  // Batch mode toggle on the right of the toolbar
  const actions = element("div", "", "toolbar-actions");
  const modeBtn = state.batchMode
    ? button(t("batchExit"), () => {
      if (running) return;
      state.batchMode = false;
      state.selectedMods = [];
      render();
    }, "secondary")
    : button(t("batchMode"), () => {
      if (running) return;
      state.batchMode = true;
      render();
    }, "ghost", "checklist");
  modeBtn.disabled = running;
  modeBtn.classList.add("btn-sm", "toolbar-batch-toggle");
  if (state.batchMode) modeBtn.classList.add("active");
  actions.append(modeBtn);

  row.append(filters, actions);
  toolbar.append(row);

  if (state.batchMode) {
    const visibleIds = visible.map(mod => mod.id);
    const strip = element("div", "", "batch-strip");
    strip.setAttribute("role", "region");
    strip.setAttribute("aria-label", t("batchActions"));

    const left = element("div", "", "batch-strip-left");
    const count = element("span", "", "batch-count");
    const sep = element("span", "", "batch-sep");
    sep.setAttribute("aria-hidden", "true");
    const toggleAll = element("button", "", "batch-link-btn");
    toggleAll.type = "button";
    toggleAll.onclick = () => {
      if (state.batch?.phase === "running") return;
      const selectedSet = new Set(state.selectedMods);
      const allSelected = visibleIds.length > 0 && visibleIds.every(id => selectedSet.has(id));
      state.selectedMods = allSelected
        ? batchDeselect(state.selectedMods, visibleIds)
        : batchSelectAll(state.selectedMods, visibleIds);
      render();
    };
    const clear = element("button", t("batchClear"), "batch-link-btn");
    clear.type = "button";
    clear.onclick = () => {
      if (state.batch?.phase === "running") return;
      state.selectedMods = [];
      render();
    };
    left.append(count, sep, toggleAll, clear);

    const right = element("div", "", "batch-strip-actions");
    const actionButtons = new Map();
    for (const kind of BATCH_KINDS) {
      const btn = element("button", "", "btn btn-sm batch-op-btn batch-op-idle");
      btn.type = "button";
      btn.dataset.kind = kind;
      const badge = element("span", "0", "batch-btn-count");
      btn.append(icon(BATCH_ICONS[kind]), element("span", t(batchLabelKey(kind))), badge);
      btn.onclick = () => runBatchAction(kind);
      right.append(btn);
      actionButtons.set(kind, {btn, badge});
    }

    strip.append(left, right);
    toolbar.append(strip);
    content.append(toolbar);
    batchStripRefs = {strip, count, toggleAll, clear, actionButtons, visibleIds};
    syncBatchStrip();
  } else {
    batchStripRefs = null;
    content.append(toolbar);
  }
}

function batchNotify(text) {
  show(t("batchActions"), element("p", text), button(t("close"), closeDialog, "primary"));
}

function runBatchAction(kind) {
  if (!BATCH_KINDS.includes(kind) || state.batch?.phase === "running") return;
  if (!state.selectedMods.length) return batchNotify(t("batchNeedSelection"));
  if (!state.game) return batchNotify(t("batchNeedGame"));
  if (state.scan !== "ready") return batchNotify(t("batchScanning"));
  const {queue, filtered} = batchTargets(state.mods, kind, batchRow, state.selectedMods);
  if (!canRunBatch(queue)) return batchNotify(t(batchEmptyKey(kind)));
  confirmBatchRun(kind, queue, filtered);
}

function confirmBatchRun(kind, queue, filtered) {
  const list = element("ul", "", "batch-confirm-list");
  for (const id of queue) {
    const mod = state.mods.find(item => item.id === id);
    list.append(element("li", mod ? nameOf(mod) : id));
  }
  const note = filtered.length
    ? element("p", t("batchFilteredHint").replace("{count}", String(filtered.length)), "panel-note")
    : element("p", t(kind === "enable" || kind === "disable" ? "batchConfirmToggleHint" : "batchConfirmHint"), "panel-note");
  show(t(batchConfirmKey(kind)).replace("{count}", String(queue.length)),
    list, note,
    button(t("batchCancel"), closeDialog, "secondary"),
    button(t("batchConfirm"), () => startBatch(kind, queue), "primary"));
}

async function rescanBatch(path) {
  if (state.game !== path) return;
  try { await syncGameMods(true); } catch { /* scan failures are surfaced by the next recheck */ }
}

async function executeBatchItem(kind, id, path, onProgress, signal, owns) {
  const mod = state.mods.find(item => item.id === id);
  if (!mod || !batchEligible(kind, batchRow(mod))) return "skip";
  if (state.game !== path || !state.pckDir) return "abort";
  const dir = state.pckDir;
  if (!await confirmGameExit(path, dir, () => owns() && state.pckDir === dir)) return "abort";
  if (!owns()) return "abort";
  const latest = state.mods.find(item => item.id === id) || mod;
  const action = batchItemAction(kind, batchRow(latest));
  if (!action) return "skip";
  if (action === "uninstall") {
    const entry = removalEntry(latest);
    if (!entry) return "skip";
    const result = await uninstallMod(path, entry, dir);
    applyValidation(result, path);
    if (result.modStates[entry.id] !== "vanilla") throw result.modStates[entry.id] || "uninstallFailed";
    return "ok";
  }
  if ((action === "install" || action === "updateMod") && latest.requires?.length) {
    const ready = await ensureDependenciesCached(latest, {
      signal,
      owns,
      onProgress: label => onProgress(label)
    });
    if (!ready || !owns()) return "abort";
  }
  if (cached(latest)) {
    onProgress(t("usingCache"));
  } else {
    onProgress(t("working"));
    await downloadMod(latest, pct => onProgress(pct + "%"), signal);
    if (!owns()) return "abort";
    state.packages[latest.id] = latest.package.sha256;
  }
  if (!owns()) return "abort";
  await verifyPackage(latest);
  if (!owns()) return "abort";
  const from = state.inventory[inventoryKey(latest)];
  let result;
  try {
    result = action === "updateMod"
      ? await updateMod(path, latest, from, dir)
      : await installMod(path, latest, false, dir, []);
  } catch (error) {
    if (action === "updateMod" && String(error).startsWith("modUpdatedRescan")) {
      await rescanBatch(path);
      return "ok";
    }
    throw error;
  }
  applyValidation(result, path);
  const problem = installationProblem(result, latest);
  if (problem) throw problem;
  return "ok";
}

function startBatch(kind, queue) {
  if (state.batch?.phase === "running") return;
  const batch = {kind, phase: "running", ids: queue.slice()};
  state.batch = batch;
  state.busyMod = BATCH_BUSY;
  render();
  void runBatchDialog(batch, queue).catch(error => {
    console.error("batch operation failed", error);
    const dialog = $("dialog");
    $("#close").disabled = false;
    if (dialog.open) {
      show(t("failed"), element("p", String(error), "error"),
        button(t("close"), closeDialog, "primary"));
    } else {
      state.busyMod = "";
      state.batch = null;
      render();
    }
  });
}

async function runBatchDialog(batch, queue) {
  const kind = batch.kind;
  const path = state.game;
  const dialog = $("dialog");
  const close = $("#close");
  const controller = new AbortController();
  const preventCancel = event => event.preventDefault();

  const list = element("ol", "", "install-steps batch-steps");
  list.setAttribute("aria-live", "polite");
  const bar = progress();
  const rows = new Map();
  for (const id of queue) {
    const mod = state.mods.find(item => item.id === id);
    const li = element("li");
    const status = element("span", t("batchItemPending"));
    li.append(element("span", mod ? nameOf(mod) : id), status);
    list.append(li);
    rows.set(id, {li, status});
  }
  const owns = () => !controller.signal.aborted && dialog.open && list.isConnected;
  const setStatus = (id, text, tone) => {
    const row = rows.get(id);
    if (!row) return;
    row.status.textContent = text;
    row.li.classList.remove("batch-ok", "batch-fail", "batch-skip");
    if (tone) row.li.classList.add("batch-" + tone);
  };
  const onClose = () => {
    dialog.removeEventListener("close", onClose);
    dialog.removeEventListener("cancel", preventCancel);
    controller.abort();
    close.disabled = false;
    state.busyMod = "";
    state.batch = null;
    batchStripRefs = null;
    render();
  };
  dialog.addEventListener("close", onClose);
  dialog.addEventListener("cancel", preventCancel);
  close.disabled = true;
  show(t(batchRunningKey(kind)), element("p", t("batchWorkingHint")), list, bar.el);

  const results = [];
  let aborted = false;
  if (kind === "enable" || kind === "disable") {
    const targetEnabled = kind === "enable";
    const dir = state.pckDir;
    const outcomeById = new Map();
    if (!path || !dir || state.game !== path
      || !await confirmGameExit(path, dir, () => owns() && state.pckDir === dir) || !owns()) {
      for (const id of queue) {
        setStatus(id, t("batchItemSkipped"), "skip");
        outcomeById.set(id, "skip");
      }
      aborted = true;
    } else {
      const eligible = [];
      for (const id of queue) {
        const mod = state.mods.find(item => item.id === id);
        if (!mod || !batchEligible(kind, batchRow(mod))) {
          setStatus(id, t("batchItemSkipped"), "skip");
          outcomeById.set(id, "skip");
        } else {
          setStatus(id, t("working"));
          eligible.push(id);
        }
      }
      if (eligible.length) {
        try {
          const result = await setModsEnabled(path, eligible, targetEnabled, dir);
          if (!owns()) return;
          applyValidation(result, path);
          for (const id of eligible) {
            const ok = (result.disabledMods || []).includes(id) === !targetEnabled;
            setStatus(id, t(ok ? "done" : "failed"), ok ? "ok" : "fail");
            outcomeById.set(id, ok ? "ok" : "fail");
          }
        } catch (error) {
          if (!owns()) return;
          const [key, ...detail] = String(error).split(": ");
          const msg = [t(key) || key, ...detail].join(" · ");
          for (const id of eligible) {
            setStatus(id, msg, "fail");
            outcomeById.set(id, "fail");
          }
          await rescanBatch(path);
        }
      }
    }
    if (!owns()) return;
    for (const id of queue) results.push(outcomeById.get(id) || "skip");
    bar.set(100);
  } else {
    let completed = 0;
    for (const id of queue) {
      if (!owns()) return;
      setStatus(id, t("working"));
      let outcome;
      try {
        outcome = await executeBatchItem(kind, id, path, pct => setStatus(id, pct), controller.signal, owns);
      } catch (error) {
        outcome = "fail";
        const [key, ...detail] = String(error).split(": ");
        if (["downloadFirst", "packageCorrupt", "downloadFailed"].includes(key)) delete state.packages[id];
        setStatus(id, [t(key) || key, ...detail].join(" · "), "fail");
      }
      if (!owns()) return;
      if (outcome === "abort") {
        setStatus(id, t("batchItemSkipped"), "skip");
        results.push("skip");
        aborted = true;
        break;
      }
      if (outcome === "ok") setStatus(id, t("done"), "ok");
      else if (outcome === "skip") setStatus(id, t("batchItemSkipped"), "skip");
      results.push(outcome);
      completed++;
      bar.set(Math.round(completed / queue.length * 100));
      if (outcome !== "ok") await rescanBatch(path);
    }
  }
  if (!owns()) return;
  batch.phase = "done";
  bar.set(100);
  const okIds = new Set(queue.filter((id, index) => results[index] === "ok"));
  state.selectedMods = state.selectedMods.filter(id => !okIds.has(id));
  render();
  const summary = batchSummary(results);
  const text = t("batchSummary")
    .replace("{ok}", String(summary.ok))
    .replace("{fail}", String(summary.fail))
    .replace("{skip}", String(summary.skip));
  dialog.removeEventListener("cancel", preventCancel);
  close.disabled = false;
  show(aborted ? t("batchAborted") : t("batchDone"),
    element("p", text, "batch-summary"), list, bar.el,
    button(t("close"), closeDialog, "primary"));
}
