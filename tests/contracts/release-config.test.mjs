import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import test from "node:test";

const read = file => readFile(new URL("../../" + file, import.meta.url), "utf8");
const tauri = JSON.parse(await read("apps/desktop/src-tauri/tauri.conf.json"));

test("package, crate and Tauri versions stay in step", async () => {
  const cargo = /^version\s*=\s*"([^"]+)"/m.exec(await read("apps/desktop/src-tauri/Cargo.toml"))[1];
  const npm = JSON.parse(await read("package.json")).version;
  assert.equal(cargo, tauri.version);
  assert.equal(npm, tauri.version);
});

test("installed clients keep the signed stable update channel", () => {
  assert.equal(tauri.identifier, "community.machineparty.modmanager");
  const updater = tauri.plugins.updater;
  assert.equal(updater.requireSignedVersion, true);
  assert.deepEqual(updater.endpoints, ["https://machineparty.ailaogong.men/v1/app-updates/stable/latest.json"]);
  assert.match(updater.pubkey, /^dW50cnVzdGVkIGNvbW1lbnQ6IG1pbmlzaWduIHB1YmxpYyBrZXk6IDdFMTY3NEI5RkRCNDJCRUMK/);
});

test("the bundled frontend directory exists", async () => {
  await access(new URL("../../apps/desktop/src-tauri/" + tauri.build.frontendDist + "/index.html", import.meta.url));
});
