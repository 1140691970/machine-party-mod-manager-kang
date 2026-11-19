// Exercise the installed Tauri UI inside WebView2 on the Windows release runner.
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {connect, until} from "./windows-webview.mjs";
const version = JSON.parse(await readFile(new URL("../apps/desktop/src-tauri/tauri.conf.json", import.meta.url))).version;
const current = 'window.__TAURI__.core.invoke("app_version")';
const old = await until(connect,"Opening installed bootstrap");
assert.equal(await old.evaluate(current),"0.0.1");
await until(()=>old.evaluate('document.querySelector("#appRelease")?.hidden === false'),"Background update check");
await old.evaluate(`document.querySelector("dialog").close(); localStorage.setItem("upgrade-test","retained"); document.querySelector("#appRelease").click()`);
assert.ok((await old.evaluate('document.querySelector("#dialogTitle").textContent')).includes(version));
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
