// Runs against the installed Windows app in a disposable Actions user profile.
import assert from "node:assert/strict";
import {mkdir, writeFile} from "node:fs/promises";
import path from "node:path";
import {connect, until} from "./windows-webview.mjs";

const app = await until(connect, "Opening installed manager");
const output = "dist/windows-ui";
await mkdir(output, {recursive:true});
const shot = async name => {
  const {data} = await app.command("Page.captureScreenshot", {format:"png"});
  await writeFile(path.join(output, name + ".png"), Buffer.from(data, "base64"));
};
try {
  await until(() => app.evaluate('document.querySelector("article")?.innerText.includes("Overtime")'), "Catalog cards");
  await app.evaluate('document.querySelector("dialog")?.close(); localStorage.setItem("language","zh-TW")');
  await app.command("Page.reload");
  await until(() => app.evaluate('document.documentElement.lang === "zh-TW" && !!document.querySelector("article")'), "Traditional Chinese UI");
  await app.evaluate('document.querySelector("dialog").close()');
  await shot("catalog");
  const copy = JSON.stringify(process.env.PREVIEW_FIXTURE);
  await app.evaluate(`window.__TAURI__.core.invoke("save_game",{path:${copy}})`);
  // Capture the prior record as soon as it renders, before waiting for disk verification.
  const checking = await app.command("Page.addScriptToEvaluateOnNewDocument", {source:
    `new MutationObserver(() => {
      if ([...document.querySelectorAll("article button")].some(b => b.textContent === "檢查中")) window.checkingPainted = true;
    }).observe(document, {subtree:true,childList:true});`});
  await app.command("Page.reload");
  await until(() => app.evaluate('window.checkingPainted'), "Startup verification status");
  await app.command("Page.removeScriptToEvaluateOnNewDocument", {identifier:checking.identifier});
  await until(() => app.evaluate('document.querySelector("article")?.innerText.includes("需要修復")'), "Stale inventory is not adoptable");
  await shot("needs-repair");
  // A user-requested full check updates the status before starting disk I/O.
  await app.evaluate('void import("./game-folder.js").then(m=>m.syncGameMods(true))');
  await shot("checking");
  await app.command("Emulation.setDeviceMetricsOverride",{width:700,height:760,deviceScaleFactor:1.5,mobile:false});
  await shot("narrow-150pct");
  const hash = await app.evaluate('window.__TAURI__.core.invoke("validate_game_mods",{path:localStorage.getItem("game-path")}).then(x=>x.pckSha256)');
  assert.match(hash,/^[0-9a-f]{64}$/);
  console.log("Verified native Windows catalog, restart checks and narrow layout");
} finally { app.close(); }
