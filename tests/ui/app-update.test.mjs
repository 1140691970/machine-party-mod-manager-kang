import assert from "node:assert/strict";
import test from "node:test";

const storage = new Map();
globalThis.localStorage = {
  getItem: key => storage.get(key) ?? null,
  setItem: (key, value) => storage.set(key, value),
  removeItem: key => storage.delete(key)
};
globalThis.window = {__TAURI__: {core: {}}};

function makeDom() {
  const listeners = new Map();
  const makeNode = (tag = "div") => ({
    tag,
    className: "",
    textContent: "",
    type: "",
    children: [],
    get childElementCount() { return this.children.length; },
    matches: sel => sel === ".btn" && tag === "button",
    append(...items) { this.children.push(...items); },
    prepend(...items) { this.children.unshift(...items); },
    replaceChildren(...items) { this.children = items; },
    setAttribute() {},
    onclick: null
  });
  const title = makeNode("h2");
  const body = makeNode("div");
  const dialog = {
    open: false,
    showModal() { this.open = true; },
    close() {
      if (!this.open) return;
      this.open = false;
      for (const fn of [...(listeners.get("close") ?? [])]) fn();
    },
    addEventListener(type, fn, opts = {}) {
      if (!listeners.has(type)) listeners.set(type, []);
      const wrapped = opts.once ? () => {
        this.removeEventListener(type, wrapped);
        fn();
      } : fn;
      wrapped._orig = fn;
      listeners.get(type).push(wrapped);
    },
    removeEventListener(type, fn) {
      const list = listeners.get(type);
      if (!list) return;
      listeners.set(type, list.filter(item => item !== fn && item._orig !== fn));
    }
  };
  globalThis.document = {
    querySelector: sel => sel === "dialog" ? dialog : sel === "#dialogTitle" ? title : sel === "#dialogBody" ? body : makeNode(),
    createElement: makeNode,
    createElementNS: () => makeNode("svg")
  };
  return {dialog, title, body};
}

test("background check opens a non-forcing update dialog once per version and respects manual open", async () => {
  const {dialog, title, body} = makeDom();
  let release = {version: "0.2.0", notes: "Fix bug\nImprove speed"};
  window.__TAURI__.core.invoke = async command => {
    assert.equal(command, "check_app_update");
    return release;
  };
  const {state} = await import("../../apps/desktop/ui/state.js");
  const {checkApp, showRelease} = await import("../../apps/desktop/ui/app-update.js");
  state.locale = "en";

  await checkApp(false);
  assert.equal(dialog.open, true);
  assert.match(title.textContent, /0\.2\.0/);
  assert.equal(body.children[0].textContent, "Fix bug\nImprove speed");
  const buttons = body.children[1].children;
  assert.equal(buttons.length, 2);
  buttons[1].onclick();
  assert.equal(dialog.open, false);
  assert.equal(storage.get("dismissed-app-update"), "0.2.0");

  await checkApp(false);
  assert.equal(dialog.open, false);

  showRelease();
  assert.equal(dialog.open, true);
  dialog.close();

  release = {version: "0.2.1", notes: ""};
  await checkApp(false);
  assert.equal(dialog.open, true);
  assert.match(title.textContent, /0\.2\.1/);
  assert.match(body.children[0].textContent, /Settings/);
  dialog.close();
  assert.equal(storage.get("dismissed-app-update"), "0.2.1");

  await checkApp(true);
  assert.equal(dialog.open, true);
  dialog.close();
});

test("queued background update waits until an active dialog closes", async () => {
  storage.clear();
  const {dialog, title} = makeDom();
  dialog.open = true;
  window.__TAURI__.core.invoke = async () => ({version: "0.3.0", notes: "Queued release"});
  const {state} = await import("../../apps/desktop/ui/state.js");
  const {checkApp} = await import("../../apps/desktop/ui/app-update.js");
  state.locale = "zh-TW";
  state.release = null;

  await checkApp(false);
  assert.equal(dialog.open, true);
  assert.equal(title.textContent, "");

  dialog.close();
  assert.equal(dialog.open, true);
  assert.match(title.textContent, /0\.3\.0/);
  dialog.close();
});
