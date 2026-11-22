// Runs against the installed Windows app in a disposable Actions user profile.
import {execFileSync} from "node:child_process";
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
  await app.command("Page.enable");
  await until(() => app.evaluate('document.querySelector("article")?.innerText.includes("Overtime")'), "Catalog cards");
  await app.evaluate('document.querySelector("dialog")?.close(); localStorage.setItem("language","zh-TW")');
  await app.command("Page.reload");
  await until(() => app.evaluate('document.documentElement.lang === "zh-TW" && !!document.querySelector("article")'), "Traditional Chinese UI");
  await app.evaluate('document.querySelector("dialog").close()');
  await shot("catalog");
  assert.equal(await app.evaluate('document.querySelector("article .card-actions button").textContent'), "安裝");
  await app.evaluate('document.querySelector("article .card-actions button").click()');
  // Close the real Windows folder picker, then verify cancellation caused no package work.
  execFileSync("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", `
    Add-Type -AssemblyName UIAutomationClient
    $desktop = [System.Windows.Automation.AutomationElement]::RootElement
    $name = [System.Windows.Automation.PropertyCondition]::new(
      [System.Windows.Automation.AutomationElement]::NameProperty, '選擇遊戲目錄')
    for ($i = 0; $i -lt 60; $i++) {
      $picker = $desktop.FindFirst([System.Windows.Automation.TreeScope]::Children, $name)
      if ($picker) {
        $picker.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
        exit 0
      }
      Start-Sleep -Milliseconds 300
    }
    throw 'Native game folder picker did not open on Install'
  `]);
  assert.equal(await app.evaluate('!!document.querySelector("dialog[open] .install-steps")'), false);
  assert.deepEqual(await app.evaluate('window.__TAURI__.core.invoke("cached_packages")'), {});
  // Exercise Rust cancellation on the installed binary before retrying the same package.
  const cancelled = await app.evaluate(`(async () => {
    const {Channel,invoke} = window.__TAURI__.core;
    const progress = new Channel();
    let sent = false;
    progress.onmessage = () => {
      if (!sent) { sent = true; void invoke("cancel_download",{channel:progress.id}); }
    };
    try { await invoke("download_mod",{id:"overtime",version:"v1.7",progress}); }
    catch(error) { return String(error); }
  })()`);
  assert.equal(cancelled, "downloadCancelled");
  assert.deepEqual(await app.evaluate('window.__TAURI__.core.invoke("cached_packages")'), {});
  await app.command("Network.enable");
  await app.command("Network.setBlockedURLs",{urls:["*/v1/catalog.json*"]});
  await app.evaluate('localStorage.removeItem("online-catalog-mpml-v1"); localStorage.removeItem("online-catalog-mpml-v1-proof")');
  await app.command("Page.reload");
  await until(() => app.evaluate('document.querySelector(".list-status button") && !document.querySelector("article")'), "Remote catalog failure");
  await shot("catalog-unavailable");
  await app.command("Network.setBlockedURLs",{urls:[]});
  await app.evaluate('document.querySelector(".list-status button").click()');
  await until(() => app.evaluate('!!document.querySelector("article")'), "Retry remote catalog");
  const copy = JSON.stringify(process.env.PREVIEW_FIXTURE);
  await app.evaluate(`window.__TAURI__.core.invoke("save_game",{path:${copy}})`);
  // Capture the prior record as soon as it renders, before waiting for disk verification.
  const checking = await app.command("Page.addScriptToEvaluateOnNewDocument", {source:
    `new MutationObserver(() => {
      if ([...document.querySelectorAll("article button")].some(b => b.textContent === "檢查中")) window.checkingPainted ??= performance.now();
    }).observe(document, {subtree:true,childList:true});`});
  await app.command("Page.reload");
  await until(() => app.evaluate('window.checkingPainted'), "Startup verification status");
  console.log("Saved record visible after navigation (ms):", await app.evaluate("window.checkingPainted"));
  await app.command("Page.removeScriptToEvaluateOnNewDocument", {identifier:checking.identifier});
  await until(() => app.evaluate('document.querySelector("article .card-actions button")?.textContent === "查看原因"'), "Stale inventory offers details");
  await app.evaluate('document.querySelector("article .card-actions button").click()');
  await until(() => app.evaluate('document.querySelector("dialog[open]")?.innerText.includes("偵測到遊戲已更新或存在未知修改")'), "Unknown PCK is protected despite stale inventory");
  await shot("game-files-changed");
  await app.evaluate('document.querySelector("#close").click()');
  // A user-requested full check updates the status before starting disk I/O.
  await app.evaluate('void import("./game-folder.js").then(m=>m.syncGameMods(true))');
  await shot("checking");
  await app.command("Emulation.setDeviceMetricsOverride",{width:700,height:760,deviceScaleFactor:1.5,mobile:false});
  await shot("narrow-150pct");
  const hash = await app.evaluate('window.__TAURI__.core.invoke("validate_game_mods",{path:localStorage.getItem("game-path")}).then(x=>x.pckSha256)');
  assert.match(hash,/^[0-9a-f]{64}$/);

  // Exercise status filters, card actions and settings modal with one synthetic scan.
  const version = await app.evaluate(`(async () => {
    const {state} = await import("./state.js");
    const {syncGameMods, applyValidation} = await import("./game-folder.js");
    await syncGameMods();
    const mod = state.mods.find(item => item.id === "overtime");
    applyValidation({...state.lastScan, installed:{[mod.repo]:"v1.6"},
      modStates:{...state.lastScan.modStates, [mod.id]:"installed"}}, state.game);
    return mod.version;
  })()`);
  const inspectFilter = async label => app.evaluate(`(() => {
    [...document.querySelectorAll(".filter-tab")].find(el => el.textContent.includes(${JSON.stringify(label)})).click();
    const card = [...document.querySelectorAll("article")].find(el => el.querySelector(".card-title")?.textContent === "Overtime");
    return {
      cards: document.querySelectorAll("article").length,
      actions: card && [...card.querySelectorAll(".card-actions button")].filter(b => b.checkVisibility()).map(b => b.innerText.trim() || b.getAttribute("aria-label")),
      refresh: document.querySelector("#refresh-catalog").checkVisibility(),
      checkUpdates: [...document.querySelectorAll("main button")].some(b => b.checkVisibility() && b.textContent.trim() === "檢查模組更新")
    };
  })()`);
  const allView = await inspectFilter("全部");
  assert.ok(allView.cards >= 2);
  assert.deepEqual(allView.actions, ["更新至 " + version, "解除安裝 · Overtime"]);
  assert.equal(allView.refresh, true);
  assert.equal(allView.checkUpdates, false);
  const installedView = await inspectFilter("已安裝");
  assert.equal(installedView.cards, 1);
  assert.deepEqual(installedView.actions, ["更新至 " + version, "解除安裝 · Overtime"]);
  await inspectFilter("全部");
  await app.evaluate('document.querySelector("#open-settings").click()');
  assert.equal(await app.evaluate('Boolean(document.querySelector("#settings-dialog[open]"))'), true);
  await app.evaluate('document.querySelector("#close-settings").click()');
  assert.equal(await app.evaluate('Boolean(document.querySelector("#settings-dialog[open]"))'), false);
  await app.evaluate('document.querySelector("article .card-title a").click()');
  await app.evaluate('[...document.querySelectorAll("#dialogBody button")].find(b => b.textContent === "解除安裝").click()');
  assert.match(await app.evaluate('document.querySelector("#dialogTitle").innerText'), /解除安裝.*Overtime.*v1\.6/);
  assert.equal(await app.evaluate('document.querySelector("#dialogBody").innerText.includes(localStorage.getItem("game-path"))'), false);
  console.log("Verified native Windows catalog, restart checks and narrow layout");
} catch (error) {
  console.error("WebView state:", await app.evaluate(`({
    game:localStorage.getItem("game-path"), language:document.documentElement.lang,
    firstCard:document.querySelector("article")?.innerText, dialog:document.querySelector("dialog[open]")?.innerText
  })`));
  await shot("failed");
  throw error;
} finally { app.close(); }
