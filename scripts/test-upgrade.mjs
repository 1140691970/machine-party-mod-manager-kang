// Exercise the installed Tauri UI inside WebView2 on the Windows release runner.
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {setTimeout as delay} from "node:timers/promises";
const version = JSON.parse(await readFile(new URL("../apps/desktop/src-tauri/tauri.conf.json", import.meta.url))).version;
async function until(action, description) {
  const end = Date.now() + 120_000;
  let last;
  while (Date.now() < end) {
    try {
      const result = await action();
      if (result) return result;
    } catch (err) { last = err.message; }
    await delay(700);
  }
  throw Error(description + " timed out. " + (last ?? ""));
}
async function connect() {
  const tabs = await (await fetch("http://127.0.0.1:9222/json/list")).json();
  const tab = tabs.find(t => t.type === "page" && t.url.includes("tauri.localhost"));
  if (!tab) return;
  const socket = new WebSocket(tab.webSocketDebuggerUrl);
  await new Promise((resolve,reject) => { socket.onopen=resolve; socket.onerror=reject; });
  let id = 0;
  return {close:()=>socket.close(), evaluate(expression) {
    return new Promise((resolve,reject) => {
      const request = ++id;
      const timer = setTimeout(()=>{socket.removeEventListener("message", receive);reject(Error("CDP timeout"));},8000);
      function receive(event) {
        const reply=JSON.parse(event.data);
        if (reply.id!==request) return;
        clearTimeout(timer);
        socket.removeEventListener("message",receive);
        const result=reply.result;
        if (!result || result.exceptionDetails) reject(Error(result?.exceptionDetails?.exception?.description || "Evaluation failed"));
        else resolve(result.result.value);
      }
      socket.addEventListener("message",receive);
      socket.send(JSON.stringify({id:request,method:"Runtime.evaluate",params:{expression,awaitPromise:true,returnByValue:true}}));
    });
  }};
}
const current = 'window.__TAURI__.core.invoke("app_version")';
const old = await until(connect,"Opening installed bootstrap");
assert.equal(await old.evaluate(current),"0.0.1");
await until(()=>old.evaluate('document.querySelector("#appRelease")?.hidden === false'),"Background update check");
await old.evaluate(`document.querySelector("dialog").close(); localStorage.setItem("upgrade-test","retained"); document.querySelector("#appRelease").click()`);
assert.ok((await old.evaluate('document.querySelector("#dialogTitle").textContent')).includes(version));
await old.evaluate('document.querySelector("#dialogBody button.primary").click()');
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
