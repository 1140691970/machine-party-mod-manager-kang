import { openProject } from "./bridge.js";
import { visibleMods } from "./catalog.js";
import { $, button, element, show } from "./dom.js";
import { state, t } from "./state.js";
import { versionState } from "./versions.js";

const nameOf = mod => mod.name[state.locale];

function project(mod) {
  return button(mod.repo.split("/")[0] + " ↗", () => openProject(mod.repo));
}

function details(mod) {
  const local = state.inventory[mod.repo];
  const status = versionState(local, mod.version, mod.verified);
  const parts = [
    element("p", mod.detail[state.locale]),
    element("p", t("release") + " · " + (mod.version || t("unlisted")))
  ];
  if (local !== undefined) {
    parts.push(element("p", t("local") + " · " + local), element("p", t(status)));
    if (status === "waiting" || status === "newer")
      parts.push(element("p", t(status === "waiting" ? "hold" : "noDowngrade")));
  }
  parts.push(project(mod));
  show(nameOf(mod), ...parts);
}

function cover(mod, name, status) {
  const box = element("div", "", "cover");
  const fallback = element("strong", name);
  box.append(fallback);
  if (mod.image) {
    const img = element("img");
    img.alt = "";
    img.onerror = () => img.replaceWith(fallback);
    img.src = "images/" + mod.image + ".png";
    fallback.replaceWith(img);
  }
  const tags = element("div", "", "tags");
  tags.append(
    element("span", mod.version || t("unlisted"), "version-tag"),
    element("span", t(status), "state-tag " + status)
  );
  box.append(tags);
  return box;
}

function primaryAction(mod, name, local, status) {
  let action = "install";
  if (status === "review") action = "review";
  else if (status === "available" || status === "waiting") action = "update";
  else if (local !== undefined) action = "uninstall";
  return button(t(action), () => {
    if (action === "review") return details(mod);
    const note = action === "update" && status === "waiting" ? "hold"
      : action === "install" && !mod.verified ? "installPending" : "enginePending";
    show(t(action) + " · " + name, element("p", t(note)));
  }, action === "uninstall" || action === "review" ? "secondary" : "primary");
}

function card(mod) {
  const name = nameOf(mod);
  const local = state.inventory[mod.repo];
  const status = state.inventoryFailed ? "review" : versionState(local, mod.version, mod.verified);
  const item = element("article");

  const copy = element("div", "", "copy");
  const heading = element("h2");
  const link = element("a", name);
  link.href = "#" + encodeURIComponent(mod.repo);
  link.onclick = event => { event.preventDefault(); details(mod); };
  heading.append(link);
  copy.append(heading, element("p", mod.summary[state.locale]));
  if (local !== undefined) {
    const versions = element("div", "", "comparison");
    versions.append(
      element("span", t("local") + " · " + local),
      element("span", t("release") + " · " + (mod.version || t("unlisted")))
    );
    copy.append(versions);
  }

  const footer = element("div", "", "actions");
  footer.append(primaryAction(mod, name, local, status));
  item.append(cover(mod, name, status), copy, footer);
  return item;
}

export function renderModList(content) {
  if (state.inventoryFailed) content.append(element("p", t("inventoryError"), "empty error"));
  const query = $("input").value.trim().toLowerCase();
  const matches = visibleMods(state.mods, {page: state.page, query, inventory: state.inventory});
  if (matches.length) {
    const grid = element("div", "", "grid");
    grid.append(...matches.map(card));
    content.append(grid);
  } else if (!state.inventoryFailed || state.page === "catalog") {
    content.append(element("p", t(state.page === "installed" ? "noMods" : "noMatch"), "empty"));
  }
}
