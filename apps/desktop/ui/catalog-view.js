import { batchCheckbox, renderCatalogToolbar, toggleBatchSelection } from "./batch-view.js";
import { installedRows, inventoryKey, visibleMods } from "./catalog.js";
import { $, button, element, tag } from "./dom.js";
import { withGameCopy } from "./game-folder.js";
import { details, primaryAction, uninstallDialog } from "./mod-dialogs.js";
import {
  canToggle, currentAction, isDisabled, isUnlistedDisabled, nameOf, removalEntry, statusRow,
  support, unlistedInstalledRows
} from "./mod-helpers.js";
import { toggleModEnabled } from "./mod-install-flow.js";
import { coverUrl } from "./online-catalog.js";
import { render, state, t } from "./state.js";

function cover(mod, name) {
  const box = element("div", "", "cover");
  const fallback = element("strong", name, "cover-title");
  box.append(fallback);
  const src = coverUrl(mod);
  if (src) {
    const img = element("img", "", "loading");
    img.alt = "";
    img.decoding = "async";
    img.loading = "lazy";
    box.classList.add("skeleton");
    img.onload = () => { img.classList.remove("loading"); box.classList.remove("skeleton"); };
    img.onerror = () => { img.replaceWith(fallback); box.classList.remove("skeleton"); };
    img.src = src;
    fallback.replaceWith(img);
  }
  const tags = element("div", "", "cover-tags");
  if (canToggle(mod) && isDisabled(mod)) tags.append(tag(t("modDisabled"), "disabled"));
  const version = tag(mod.version || t("unlisted"));
  if (mod.version) version.classList.add("tag-mono");
  tags.append(version);
  const category = t("category_" + mod.category);
  if (category) tags.append(tag(category));
  box.append(tags);
  return box;
}

function toggleSwitch(mod) {
  const disabled = isDisabled(mod);
  const label = element("label", "", "mod-switch");
  label.title = t(disabled ? "enableMod" : "disableMod");
  const input = document.createElement("input");
  input.type = "checkbox";
  input.setAttribute("role", "switch");
  input.setAttribute("aria-label", t("toggleModAria").replace("{mod}", nameOf(mod)));
  input.checked = !disabled;
  input.disabled = Boolean(state.busyMod) || state.scan !== "ready" || (state.page === "catalog" && state.batchMode);
  input.onchange = () => {
    void toggleModEnabled(mod, input.checked, false, details);
  };
  label.append(input, element("span", "", "mod-switch-track"));
  return label;
}

function card(mod, index) {
  const name = nameOf(mod);
  const local = state.inventory[inventoryKey(mod)];
  const item = element("article", "", "card");
  if (canToggle(mod) && isDisabled(mod)) item.classList.add("card-disabled");
  item.style.setProperty("--i", String(index));

  const body = element("div", "", "card-body");
  const heading = element("h2", "", "card-title");
  const link = element("a", name);
  link.href = "#" + encodeURIComponent(inventoryKey(mod));
  link.onclick = event => { event.preventDefault(); details(mod); };
  heading.append(link);
  body.append(heading, element("p", mod.summary[state.locale], "card-summary"));
  body.append(element("p", support(mod), "panel-note"));
  if (local !== undefined) {
    const versions = element("div", "", "comparison");
    versions.append(
      element("span", t("local") + " · " + local),
      element("span", t("release") + " · " + (mod.version || t("unlisted")))
    );
    body.append(versions);
  }

  const footer = element("div", "", "card-actions");
  footer.append(primaryAction(mod));
  if (canToggle(mod)) footer.append(toggleSwitch(mod));
  if (state.page === "catalog" && currentAction(mod) === "updateMod" && removalEntry(mod)) {
    const removeBtn = button("", () => withGameCopy(() => removalEntry(mod) ? uninstallDialog(mod) : details(mod)), "secondary", "close");
    removeBtn.classList.add("card-remove-btn");
    removeBtn.title = t("uninstall");
    removeBtn.setAttribute("aria-label", t("uninstall") + " · " + name);
    removeBtn.disabled = Boolean(state.busyMod) || state.batchMode;
    footer.append(removeBtn);
  }
  const coverBox = cover(mod, name);
  if (state.page === "catalog" && state.batchMode) {
    const checked = state.selectedMods.includes(mod.id);
    item.classList.add("batch-card");
    item.classList.toggle("batch-selected", checked);
    const {label, input} = batchCheckbox(mod, checked);
    coverBox.append(label);
    item.addEventListener("click", event => {
      if (state.batch?.phase === "running") return;
      if (event.target.closest("a, button, input, label")) return;
      input.checked = !input.checked;
      toggleBatchSelection(mod.id, input.checked, item);
    });
  }
  item.append(coverBox, body, footer);
  return item;
}

function filteredCatalogMods() {
  return visibleMods(state.mods, {
    query: $("#search input")?.value || "",
    category: state.filterCategory,
    status: state.filterStatus,
    statusOf: statusRow
  });
}

function unlistedInstalledCards(query) {
  if (!["all", "enabled", "disabled"].includes(state.filterStatus)) return [];
  return unlistedInstalledRows(query)
    .filter(item => state.filterStatus === "all" || (state.filterStatus === "disabled") === isUnlistedDisabled(item))
    .map(({repo, version, mod}, index) => {
      if (mod) return card(mod, state.mods.length + index);
      const row = element("article", "", "card");
      const body = element("div", "", "card-body");
      body.append(element("h2", repo, "card-title"), element("p", t("local") + " · " + version));
      row.append(body);
      return row;
    });
}

export function renderModList(content) {
  if (state.scan === "failed") content.append(button(t("retryCheck"), () => withGameCopy(undefined, true), "secondary", "refresh"));
  const query = $("#search input")?.value || "";
  const visible = state.page === "catalog" ? filteredCatalogMods() : [];
  if (state.page === "catalog") renderCatalogToolbar(content, visible);
  const cards = state.page === "installed"
    ? installedRows(state.inventory, state.mods, [...state.removalMods, ...state.pinned]).map(({repo, version, mod}, index) => {
      if (mod) return card(mod, index);
      const row = element("article", "", "card");
      const body = element("div", "", "card-body");
      body.append(element("h2", repo, "card-title"), element("p", t("local") + " · " + version));
      row.append(body);
      return row;
    })
    : [...visible.map(card), ...unlistedInstalledCards(query)];
  if (cards.length) {
    const grid = element("div", "", "grid");
    grid.append(...cards);
    content.append(grid);
  } else if (state.page === "installed" && state.scan === "checking") {
    content.append(element("p", t("checking"), "empty"));
  } else if (state.scan !== "failed" || state.page === "catalog") {
    const hasFilter = state.page === "catalog" && (state.filterStatus !== "all" || state.filterCategory !== "all");
    if (hasFilter) {
      const box = element("div", "", "empty empty-filtered");
      box.append(
        element("p", t("noMatch")),
        button(t("filterReset"), () => {
          state.filterStatus = "all";
          state.filterCategory = "all";
          render();
        }, "secondary")
      );
      content.append(box);
    } else {
      content.append(element("p", t(state.page === "installed" ? "noMods" : "noMatch"), "empty"));
    }
  }
}
