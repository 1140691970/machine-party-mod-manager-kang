// Exercise the installed Tauri UI inside WebView2 on the Windows release runner.
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {connect, until} from "./windows-webview.mjs";
const config = JSON.parse(await readFile(new URL("../apps/desktop/src-tauri/tauri.conf.json", import.meta.url)));
const {version} = config;
const downloads = new URL("/v1/app-downloads/" + version + "/", config.plugins.updater.endpoints[0]);
const staged = await fetch(new URL("manifest.json", downloads));
assert.equal(staged.status, 200);
const manifest = await staged.json();
assert.equal(manifest.version, version);
assert.deepEqual(Object.keys(manifest.platforms), ["windows-x86_64"]);
assert.equal(manifest.platforms["windows-x86_64"].url, new URL("setup.exe", downloads).href);
assert.ok(manifest.platforms["windows-x86_64"].signature);
const current = 'window.__TAURI__.core.invoke("app_version")';
const old = await until(connect,"Opening installed bootstrap");
assert.equal(await old.evaluate(current),"0.0.1");
await until(()=>old.evaluate('Boolean(document.querySelector("[data-page=settings] .update-dot"))'),"Background update check");
await old.evaluate(`
  localStorage.setItem("upgrade-test","retained");
  const dialog = document.querySelector("dialog");
  if (dialog?.open && !document.querySelector("#dialogTitle").textContent.includes(${JSON.stringify(version)})) dialog.close();
`);
await until(()=>old.evaluate(`Boolean(document.querySelector("dialog")?.open && document.querySelector("#dialogTitle").textContent.includes(${JSON.stringify(version)}))`),"Update dialog opens");
await old.evaluate('document.querySelector("#dialogBody button.btn-primary").click()');
old.close();
await until(async()=>{
  const app=await connect();
  if (!app) return false;
  try {
    if (await app.evaluate(current)!==version) return false;
    assert.equal(await app.evaluate('localStorage.getItem("upgrade-test")'),"retained");
    assert.equal(await app.evaluate('window.__TAURI__.core.invoke("check_app_update")'),null);
    return true;
  } finally {app.close();}
},"Restart into signed release with settings preserved");
console.log("Verified installed 0.0.1 -> " + version + " and preserved WebView settings");
