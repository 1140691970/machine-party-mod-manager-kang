import assert from "node:assert/strict";
import test from "node:test";
import {
  BATCH_KINDS, batchConfirmKey, batchDeselect, batchEligible, batchEmptyKey, batchItemAction,
  batchLabelKey, batchMatches, batchQueue, batchRunningKey, batchSelectAll, batchSelectable,
  batchSelectedCount, batchSummary, batchTargets, batchToggle, canRunBatch
} from "../../apps/desktop/ui/batch.js";
import {
  FILTER_STATUSES, catalogCategories, matchesStatusFilter, modFilterStatus, statusCounts, visibleMods
} from "../../apps/desktop/ui/catalog.js";

const row = (overrides = {}) => ({ready: true, action: "install", removable: false, disabled: false, ...overrides});

const mods = [
  {id: "a", category: "expansion", name: {"zh-CN": "加班", "zh-TW": "加班", en: "Overtime"}, action: "install", removable: false, disabled: false},
  {id: "b", category: "game", name: {"zh-CN": "滚筒", "zh-TW": "滾筒", en: "Roller"}, action: "updateMod", removable: true, disabled: false},
  {id: "c", category: "game", name: {"zh-CN": "泡泡", "zh-TW": "泡泡", en: "Bubble"}, action: "uninstall", removable: true, disabled: true},
  {id: "d", category: "tool", name: {"zh-CN": "机器人", "zh-TW": "機器人", en: "Bots"}, action: "review", removable: false, disabled: false},
  {id: "e", category: "graphics", name: {"zh-CN": "高清", "zh-TW": "高清", en: "HD"}, action: "adoptManual", removable: false, disabled: false}
];
const rowOf = mod => row({action: mod.action, removable: mod.removable, disabled: mod.disabled});

test("batch operations merge install and update alongside enable, disable and uninstall", () => {
  assert.deepEqual(BATCH_KINDS, ["install", "enable", "disable", "uninstall"]);
  assert.equal(batchItemAction("install", row()), "install");
  assert.equal(batchItemAction("install", row({action: "updateMod", removable: true})), "updateMod");
  assert.equal(batchItemAction("install", row({action: "uninstall", removable: true})), "");
  assert.equal(batchItemAction("enable", row({action: "uninstall", removable: true, disabled: true})), "enable");
  assert.equal(batchItemAction("enable", row({action: "uninstall", removable: true, disabled: false})), "");
  assert.equal(batchItemAction("disable", row({action: "uninstall", removable: true, disabled: false})), "disable");
  assert.equal(batchItemAction("disable", row({action: "uninstall", removable: true, disabled: true})), "");
  assert.equal(batchItemAction("uninstall", row({action: "uninstall", removable: true})), "uninstall");
  assert.equal(batchItemAction("uninstall", row({action: "updateMod", removable: true})), "uninstall");
  assert.equal(batchItemAction("unknown", row()), "");
});

test("state matching is independent of scan readiness", () => {
  assert.equal(batchMatches("install", row()), true);
  assert.equal(batchMatches("install", row({ready: false})), true);
  assert.equal(batchMatches("install", row({action: "updateMod", removable: true})), true, "approved updates are handled by install");
  assert.equal(batchMatches("install", row({removable: true})), false, "up-to-date managed installs are not reinstalled");
  assert.equal(batchMatches("install", row({action: "uninstall", removable: true})), false);
  assert.equal(batchMatches("install", row({action: "review"})), false);
  assert.equal(batchMatches("install", row({action: "adoptManual"})), false);
  assert.equal(batchMatches("install", row({action: "switch"})), false);
  assert.equal(batchMatches("bogus", row()), false);
  assert.equal(batchMatches("install", null), false);
});

test("uninstall matches every installed mod, including ones with an available update", () => {
  assert.equal(batchMatches("uninstall", row({action: "uninstall", removable: true})), true);
  assert.equal(batchMatches("uninstall", row({action: "updateMod", removable: true})), true);
  assert.equal(batchMatches("uninstall", row({action: "review", removable: true})), true);
  assert.equal(batchMatches("uninstall", row({action: "install", removable: true})), true);
  assert.equal(batchMatches("uninstall", row({action: "checking", removable: true})), false);
  assert.equal(batchMatches("uninstall", row({action: "retryCheck", removable: true})), false);
  assert.equal(batchMatches("uninstall", row()), false);
});

test("enable and disable match installed mods according to disabled state and toggleability", () => {
  assert.equal(batchMatches("enable", row({action: "uninstall", removable: true, disabled: true})), true);
  assert.equal(batchMatches("enable", row({action: "updateMod", removable: true, disabled: true})), true);
  assert.equal(batchMatches("enable", row({action: "uninstall", removable: true, disabled: false})), false);
  assert.equal(batchMatches("enable", row({action: "uninstall", removable: true, disabled: true, toggleable: false})), false);
  assert.equal(batchMatches("enable", row({action: "checking", removable: true, disabled: true})), false);
  assert.equal(batchMatches("disable", row({action: "uninstall", removable: true, disabled: false})), true);
  assert.equal(batchMatches("disable", row({action: "updateMod", removable: true, disabled: false})), true);
  assert.equal(batchMatches("disable", row({action: "uninstall", removable: true, disabled: true})), false);
  assert.equal(batchMatches("disable", row({action: "uninstall", removable: true, disabled: false, toggleable: false})), false);
  assert.equal(batchMatches("disable", row({action: "retryCheck", removable: true, disabled: false})), false);
  assert.equal(batchMatches("disable", row()), false);
});

test("eligibility additionally requires a finished game scan", () => {
  for (const kind of BATCH_KINDS) {
    assert.equal(batchEligible(kind, row({ready: false})), false, kind);
    assert.equal(batchEligible(kind, row({ready: false, action: "updateMod", removable: true})), false, kind);
    assert.equal(batchEligible(kind, null), false, kind);
  }
  assert.equal(batchEligible("bogus", row()), false);
  assert.equal(batchEligible("install", row()), true);
  assert.equal(batchEligible("install", row({action: "updateMod", removable: true})), true);
});

test("selectable ids keep catalog order and ignore ineligible rows", () => {
  assert.deepEqual(batchSelectable(mods, "install", rowOf), ["a", "b"]);
  assert.deepEqual(batchSelectable(mods, "enable", rowOf), ["c"]);
  assert.deepEqual(batchSelectable(mods, "disable", rowOf), ["b"]);
  assert.deepEqual(batchSelectable(mods, "uninstall", rowOf), ["b", "c"]);
  assert.deepEqual(batchSelectable(mods, "install", () => row({ready: false})), []);
});

test("badges follow ticked selection, not the whole catalog", () => {
  assert.equal(batchSelectedCount(mods, "install", rowOf, ["a"]), 1);
  assert.equal(batchSelectedCount(mods, "uninstall", rowOf, ["a"]), 0);
  assert.equal(batchSelectedCount(mods, "install", rowOf, ["a", "b", "c"]), 2);
  assert.equal(batchSelectedCount(mods, "enable", rowOf, ["a", "b", "c"]), 1);
  assert.equal(batchSelectedCount(mods, "disable", rowOf, ["a", "b", "c"]), 1);
  assert.equal(batchSelectedCount(mods, "uninstall", rowOf, ["a", "b", "c"]), 2);
  assert.equal(batchSelectedCount(mods, "uninstall", rowOf, ["z"]), 0);
});

test("batch targets only contain ticked cards and report filtered ones", () => {
  assert.deepEqual(batchTargets(mods, "install", rowOf, ["a", "b", "c", "d"]),
    {queue: ["a", "b"], filtered: ["c", "d"]});
  assert.deepEqual(batchTargets(mods, "enable", rowOf, ["a", "b", "c", "d"]),
    {queue: ["c"], filtered: ["a", "b", "d"]});
  assert.deepEqual(batchTargets(mods, "disable", rowOf, ["a", "b", "c", "d"]),
    {queue: ["b"], filtered: ["a", "c", "d"]});
  assert.deepEqual(batchTargets(mods, "uninstall", rowOf, ["a", "b", "c", "d"]),
    {queue: ["b", "c"], filtered: ["a", "d"]});
  assert.deepEqual(batchTargets(mods, "install", rowOf, []), {queue: [], filtered: []});
  assert.deepEqual(batchTargets(mods, "install", rowOf, ["c", "a"]),
    {queue: ["a"], filtered: ["c"]});
  assert.deepEqual(batchTargets(mods, "install", () => row({ready: false}), ["a"]),
    {queue: [], filtered: ["a"]});
});

test("running requires at least one checked mod and summary separates outcomes", () => {
  assert.equal(canRunBatch([]), false);
  assert.equal(canRunBatch(null), false);
  assert.equal(canRunBatch(["a"]), true);
  assert.deepEqual(batchSummary([]), {ok: 0, fail: 0, skip: 0});
  assert.deepEqual(batchSummary(["ok", "ok", "downloadFailed", "skip"]), {ok: 2, fail: 1, skip: 1});
});

test("i18n keys are only produced for supported operations", () => {
  assert.equal(batchLabelKey("install"), "batchInstall");
  assert.equal(batchLabelKey("enable"), "batchEnable");
  assert.equal(batchLabelKey("disable"), "batchDisable");
  assert.equal(batchRunningKey("install"), "batchRunningInstall");
  assert.equal(batchRunningKey("disable"), "batchRunningDisable");
  assert.equal(batchEmptyKey("enable"), "batchEmptyEnable");
  assert.equal(batchEmptyKey("uninstall"), "batchEmptyUninstall");
  assert.equal(batchConfirmKey("install"), "batchConfirmInstall");
  assert.equal(batchConfirmKey("enable"), "batchConfirmEnable");
  assert.equal(batchLabelKey("update"), "");
  assert.equal(batchLabelKey("bogus"), "");
  assert.equal(batchConfirmKey(""), "");
});

test("selection helpers toggle, select visible, deselect visible and preserve order", () => {
  assert.deepEqual(batchToggle(["a", "b"], "c", true), ["a", "b", "c"]);
  assert.deepEqual(batchToggle(["a", "b"], "a", false), ["b"]);
  assert.deepEqual(batchSelectAll(["a"], ["b", "c"]), ["a", "b", "c"]);
  assert.deepEqual(batchDeselect(["a", "b", "c"], ["a", "c"]), ["b"]);
  assert.deepEqual(batchQueue(["a", "b", "c"], ["c", "a"]), ["a", "c"]);
});

test("catalog categories are extracted in order without duplicates", () => {
  assert.deepEqual(catalogCategories(mods), ["expansion", "game", "tool", "graphics"]);
  assert.deepEqual(catalogCategories([]), []);
});

test("status and category filters compose with search queries", () => {
  assert.deepEqual(FILTER_STATUSES, ["all", "enabled", "disabled", "notInstalled", "updatable"]);
  assert.equal(modFilterStatus({action: "updateMod", removable: true, disabled: false}), "enabled");
  assert.equal(modFilterStatus({action: "updateMod", removable: true, disabled: true}), "disabled");
  assert.equal(modFilterStatus({action: "uninstall", removable: true, disabled: false}), "enabled");
  assert.equal(modFilterStatus({action: "uninstall", removable: true, disabled: true}), "disabled");
  assert.equal(modFilterStatus({action: "install", removable: false}), "notInstalled");
  assert.equal(matchesStatusFilter("enabled", {action: "updateMod", removable: true, disabled: false}), true);
  assert.equal(matchesStatusFilter("disabled", {action: "updateMod", removable: true, disabled: true}), true);
  assert.equal(matchesStatusFilter("updatable", {action: "updateMod", removable: true, disabled: true}), true);
  assert.equal(matchesStatusFilter("updatable", {action: "uninstall", removable: true, disabled: false}), false);

  const statusOf = mod => ({action: mod.action, removable: mod.removable, installed: mod.removable, disabled: mod.disabled});
  assert.deepEqual(statusCounts(mods, statusOf), {all: 5, enabled: 1, disabled: 1, notInstalled: 3, updatable: 1});
  assert.deepEqual(visibleMods(mods, {query: "", category: "game"}).map(m => m.id), ["b", "c"]);
  assert.deepEqual(visibleMods(mods, {query: "", status: "enabled", statusOf}).map(m => m.id), ["b"]);
  assert.deepEqual(visibleMods(mods, {query: "", status: "disabled", statusOf}).map(m => m.id), ["c"]);
  assert.deepEqual(visibleMods(mods, {query: "", status: "updatable", statusOf}).map(m => m.id), ["b"]);
  assert.deepEqual(visibleMods(mods, {query: "", status: "notInstalled", statusOf}).map(m => m.id), ["a", "d", "e"]);
  assert.deepEqual(visibleMods(mods, {query: "roller", category: "game", status: "updatable", statusOf}).map(m => m.id), ["b"]);
  assert.deepEqual(visibleMods(mods, {query: "roller", category: "tool", status: "all", statusOf}).map(m => m.id), []);
});
