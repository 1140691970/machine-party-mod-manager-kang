import {setTimeout as delay} from "node:timers/promises";
export async function until(action, description) {
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
export async function connect() {
  const tabs = await (await fetch("http://127.0.0.1:9222/json/list")).json();
  const tab = tabs.find(t => t.type === "page" && t.url.includes("tauri.localhost"));
  if (!tab) return;
  const socket = new WebSocket(tab.webSocketDebuggerUrl);
  await new Promise((resolve,reject) => { socket.onopen=resolve; socket.onerror=reject; });
  let id = 0;
  return {close:()=>socket.close(), evaluate(expression) {
    return this.command("Runtime.evaluate", {expression,awaitPromise:true,returnByValue:true}).then(result => {
      if (result.exceptionDetails) throw Error(result.exceptionDetails.exception?.description || "Evaluation failed");
      return result.result.value;
    });
  }, command(method, params = {}) {
    return new Promise((resolve,reject) => {
      const request = ++id;
      const timer = setTimeout(()=>{socket.removeEventListener("message", receive);reject(Error("CDP timeout"));},8000);
      function receive(event) {
        const reply=JSON.parse(event.data);
        if (reply.id!==request) return;
        clearTimeout(timer);
        socket.removeEventListener("message",receive);
        const result=reply.result;
        if (!result) reject(Error(reply.error?.message || "CDP failed"));
        else resolve(result);
      }
      socket.addEventListener("message",receive);
      socket.send(JSON.stringify({id:request,method,params}));
    });
  }};
}
