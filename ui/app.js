import { locales, messages, systemLocale } from "./languages.js";
import { versionState } from "./versions.js";

const mods = [
  {name:"Overtime", repo:"DarkJadeStone/MachineParty-Overtime", image:"overtime", version:"v1.7", text:"overtime", aliases:"加班 八人 八人联机 八人聯機 8p 本機"},
  {name:"MachineParty+", repo:"Ghostx10742/MachineParty-Plus", image:"plus", version:"v2.1.0", text:"plus", aliases:"plus mpml"},
  {name:"Broadcast 8P Freecam", repo:"Lnksoul/MachineParty_Broadcast8P_Freecam_Patcher", text:"cast", aliases:"直播 导播 導播 觀戰 八人"},
  {repo:"Binary1936/machine-party-8p", version:"v1.5", text:"eight", aliases:"8p 八人聯機 多人"}
];
const savedLocale = localStorage.getItem("language");
let locale = locales.includes(savedLocale) ? savedLocale : systemLocale(navigator.language);
const t = key => messages[key][locales.indexOf(locale)];
const nameOf = mod => mod.name || t("eight");
let inventory = {}, inventoryFailed = false;
const $ = s => document.querySelector(s);
const invoke = window.__TAURI__?.core.invoke;
let page = "catalog", game = "", candidates = [];
function element(tag, text, cls) {
  const el = document.createElement(tag);
  if (text) el.textContent = text;
  if (cls) el.className = cls;
  return el;
}
function button(text, action, cls) {
  const el = element("button", text, cls);
  el.onclick = async () => { try { await action(); } catch(error) { show(t("failed"), element("p", messages[String(error)] ? t(String(error)) : String(error),"error")); } };
  return el;
}
function show(title,...items) {
  $("#dialogTitle").textContent = title;
  $("#dialogBody").replaceChildren(...items);
  if (!$("dialog").open) $("dialog").showModal();
}
function project(mod) {
  const url = "https://github.com/" + mod.repo;
  return button(mod.repo.split("/")[0]+" ↗", () => invoke ? invoke("open_project",{repo:mod.repo}) : window.open(url,"_blank","noopener"));
}
function details(mod) {
  const local = inventory[mod.repo];
  const state = versionState(local,mod.version,mod.verified);
  const parts = [element("p", t(mod.text+"Detail")), element("p", t("release")+" · "+(mod.version || t("unlisted")))];
  if (local !== undefined) {
    parts.push(element("p", t("local")+" · "+local), element("p",t(state)));
    if (state === "waiting" || state === "newer")
      parts.push(element("p",t(state === "waiting" ? "hold" : "noDowngrade")));
  }
  parts.push(project(mod));
  show(nameOf(mod),...parts);
}

function card(mod) {
  const name = nameOf(mod);
  const local = inventory[mod.repo];
  const state = inventoryFailed ? "review" : versionState(local,mod.version,mod.verified);
  const item = element("article"), cover = element("div","","cover");
  const fallback = element("strong",name);
  cover.append(fallback);
  if(mod.image) {
    const img = element("img");
    img.alt = "";
    img.onerror = () => img.replaceWith(fallback);
    img.src = "images/"+mod.image+".png";
    fallback.replaceWith(img);
  }
  const tags = element("div","","tags");
  tags.append(element("span",mod.version || t("unlisted"),"version-tag"),
    element("span",t(state),"state-tag "+state));
  cover.append(tags);
  const copy = element("div","","copy"), heading = element("h2");
  const link = element("a",name);
  link.href = "#"+encodeURIComponent(mod.repo);
  link.onclick = event => {event.preventDefault(); details(mod);};
  heading.append(link);
  copy.append(heading,element("p",t(mod.text+"Summary")));
  if (local !== undefined) {
    const versions = element("div","","comparison");
    versions.append(element("span",t("local")+" · "+local),
      element("span",t("release")+" · "+(mod.version || t("unlisted"))));
    copy.append(versions);
  }
  const footer = element("div","","actions");
  let action = "install";
  if (state === "review") action = "review";
  else if (state === "available" || state === "waiting") action = "update";
  else if (local !== undefined) action = "uninstall";
  footer.append(button(t(action), () => {
    if (action === "review") return details(mod);
    const note = action === "update" && state === "waiting" ? "hold"
      : action === "install" && !mod.verified ? "installPending" : "enginePending";
    show(t(action)+" · "+name, element("p",t(note)));
  }, action === "uninstall" || action === "review" ? "secondary" : "primary"));
  item.append(cover,copy,footer);
  return item;
}

async function loadGame(path) {
  game = path;
  inventory = {};
  inventoryFailed = false;
  try { inventory = await invoke("installed_versions",{path}); }
  catch { inventoryFailed = true; }
  render();
}
async function selectPath(path) {
  await invoke("save_game",{path});
  $("dialog").close();
  await loadGame(path);
}
async function pick() {
  const path = await invoke("choose_game",{title:t("choose")});
  if(path) await selectPath(path);
}
async function detect(rescan=false) {
  candidates = await invoke("find_games",{rescan});
  if(candidates.length===1) { 
    if(rescan) await selectPath(candidates[0]);
    else await loadGame(candidates[0]);
    return; 
  }
  game = "";
  inventory = {};
  inventoryFailed = false;
  render();
  show(t("choose"),element("p",t(candidates.length ? "multiple" : "missing")),
    ...candidates.map(path=>button(path,()=>selectPath(path),"control")),
    button(t("choose"),pick,"control primary"),button(t("later"),()=>$("dialog").close(),"control"));
}

function applyLocale() {
  document.documentElement.lang = locale;
  document.title = "Machine Party " + t("manager");
  if (invoke) invoke("set_app_title",{title:document.title}).catch(console.error);
  $(".brand").setAttribute("aria-label",document.title);
  $(".brand small").textContent=t("manager");
  $("input").placeholder=t("search");
  $("input").setAttribute("aria-label",t("search"));
  $("#close").setAttribute("aria-label",t("close"));
  for (const el of document.querySelectorAll("[data-page]")) {
    el.title=t(el.dataset.page);
    el.setAttribute("aria-label",el.title);
    el.querySelector("span").textContent=el.title;
  }
}
function languagePicker() {
  const label=element("label",t("language"),"language");
  const select=element("select");
  ["简体中文","繁體中文","English"].forEach((name,index)=>{
    const option=element("option",name);
    option.value=locales[index];
    select.append(option);
  });
  select.value=locale;
  select.onchange=()=>{
    locale=select.value;
    localStorage.setItem("language",locale);
    applyLocale();
    render();
    $("select").focus();
  };
  label.append(select);
  return label;
}
function render() {
  document.querySelectorAll("[data-page]").forEach(el=>{
    el.classList.toggle("active",el.dataset.page===page);
    if(el.dataset.page===page) el.setAttribute("aria-current","page"); else el.removeAttribute("aria-current");
  });
  $("h1").textContent=t(page);
  $("#subtitle").textContent=page==="settings" ? "" : t(page+"Sub");
  $("#search").hidden=page!=="catalog";
  const content=$("#content");
  content.replaceChildren();
  content.className="";
  if(page==="settings") {
    const box=element("div","","box");
    box.append(languagePicker(),element("h2",t("folder")),element("p",game||t("unset")));
    if(invoke) box.append(button(t("choose"),pick,"control primary"),button(t("rescan"),()=>detect(true),"control"));
    content.append(box);
    return;
  }
  if(inventoryFailed) content.append(element("p",t("inventoryError"),"empty error"));
  const query=$("input").value.trim().toLowerCase();
  const matches=mods.filter(m=>page==="installed" ? Object.hasOwn(inventory,m.repo)
    : [m.name, m.repo, m.aliases, ...messages[m.text+"Summary"], ...(m.name ? [] : messages.eight)].join(" ").toLowerCase().includes(query));
  if(matches.length){
    const grid=element("div","","grid");
    grid.append(...matches.map(card));
    content.append(grid);
  } else if (!inventoryFailed || page==="catalog") content.append(element("p",t(page==="installed" ? "noMods" : "noMatch"),"empty"));
}
document.querySelectorAll("[data-page]").forEach(el=>el.onclick=()=>{page=el.dataset.page;render();});
$("input").oninput=render;
$("#close").onclick=()=>$("dialog").close();
applyLocale();
render();
if(invoke) detect().catch(error=>show(t("failed"),element("p",String(error)),button(t("choose"),pick,"control")));
