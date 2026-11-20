import previous from "../../catalog/legacy-adapters.json" with {type: "json"};
import assert from "node:assert/strict";
import test from "node:test";
import gateway from "../../services/update-worker/app-updates.mjs";
import worker from "../../services/catalog-worker/catalog.mjs";
import snapshot from "../../catalog/mods.json" with {type: "json"};
import {cachedCatalog, downloadUrl, loadCatalog, restoreCatalog, validCatalog} from "../../apps/desktop/ui/online-catalog.js";

const compatibleSnapshot = () => ({...snapshot,mods:snapshot.mods.map(m=>({...m,...previous[m.id]}))});
const catalogStore = {PACKAGES:{get:async key => {
  assert.equal(key, "catalog/revisions/" + snapshot.revision + ".json");
  return {body:JSON.stringify(snapshot)};
}}};
const serve = (url, env = catalogStore, init) => worker.fetch(new Request(url, init), env);
const catalogUrl = "https://machineparty.ailaogong.men/v1/catalog.json?inventory=id&prepare=1";

test("all remote catalogs omit Broadcast 8P and Eight-player multiplayer", async () => {
  for (const query of ["", "?inventory=id", "?inventory=id&prepare=1"]) {
    const response = await serve(catalogUrl.split("?")[0] + query);
    const {mods} = await response.json();
    assert.ok(mods.some(mod => mod.id === "overtime"));
    assert.ok(mods.every(mod => !["broadcast-8p-freecam", "binary1936-8p"].includes(mod.id)));
  }
});

test("the client loads the Worker snapshot and retains it across failed refreshes", async () => {
  const storage = {getItem() {return this.data;}, setItem(_, value) {this.data = value;}};
  assert.equal(cachedCatalog(storage), null);
  assert.deepEqual(await loadCatalog(storage, url => serve(url)), snapshot);
  const corrupt = structuredClone(snapshot);
  corrupt.mods[0].package.sha256 = "invalid";
  await assert.rejects(loadCatalog(storage, () => Response.json(corrupt)));
  assert.deepEqual(cachedCatalog(storage), snapshot);
  assert.ok(!validCatalog({...snapshot, mods: [...snapshot.mods, snapshot.mods[0]]}));
  const response = await serve(catalogUrl);
  assert.equal((await serve(catalogUrl, {}, {headers: {"If-None-Match":response.headers.get("etag")}})).status, 304);
});

test("offline desktop release notes come from the document that was reverified", async () => {
  const key = "online-catalog-mpml-v1";
  const old = structuredClone(snapshot);
  old.mods[0].releaseNotes = {version:old.mods[0].version, en:"Outdated notes for the same package"};
  const document = JSON.stringify(snapshot);
  const cache = new Map([[key, JSON.stringify(old)],
    [key + "-proof", JSON.stringify({document, signature:"test-signature"})]]);
  const storage = {getItem:k => cache.get(k) ?? null};
  const verify = (raw, signature) => {
    assert.equal(raw, document);
    assert.equal(signature, "test-signature");
  };
  assert.deepEqual(await restoreCatalog(storage, verify), snapshot);
  cache.delete(key);
  assert.deepEqual(await restoreCatalog(storage, verify), snapshot);
  cache.set(key, JSON.stringify(old));
  const reject = () => { throw Error("catalogInvalid"); };
  for (const proof of [cache.get(key + "-proof"), null, "bad JSON"]) {
    cache.set(key + "-proof", proof);
    const fallback = await restoreCatalog(storage, reject);
    assert.deepEqual(fallback.mods.map(m => m.id), snapshot.mods.map(m => m.id));
    assert.ok(fallback.mods.every(m => !("releaseNotes" in m)));
  }
  assert.deepEqual(await restoreCatalog(storage), old);
});

test("a desktop refresh without a signature keeps browsing available without release notes", async () => {
  const catalog = await loadCatalog({}, () => Response.json(snapshot), (_, signature) => assert.equal(signature, ""));
  assert.equal(catalog.mods.length, snapshot.mods.length);
  assert.ok(catalog.mods.every(m => !("releaseNotes" in m)));
});

test("each download resolves only its approved version and R2 key", async () => {
  for (const mod of snapshot.mods.filter(entry => entry.package)) {
    const pkg = mod.package;
    const env = {PACKAGES: {head: async key => {
      assert.ok(pkg.mirrorApproved);
      assert.equal(key, "packages/sha256/" + pkg.sha256 + ".zip");
      return {size: pkg.size};
    }}};
    const url = downloadUrl(mod);
    const result = await serve(url, env, {method: "HEAD"});
    assert.equal(result.status, pkg.mirrorApproved ? 200 : 403);
    if (pkg.mirrorApproved) {
      assert.equal(result.headers.get("content-length"), String(pkg.size));
      assert.equal((await serve(url, {PACKAGES: {get: async () => null}})).status, 503);
      const bytes = new Uint8Array(pkg.size);
      const get = await serve(url, {PACKAGES: {get: async () => ({size: bytes.length, body: bytes})}});
      assert.deepEqual(new Uint8Array(await get.arrayBuffer()), bytes);
    }
    assert.equal((await serve(url + "/other")).status, 404);
    assert.equal((await serve(url, env, {method: "PUT"})).status, 405);
  }
});

test("the public gateway forwards catalog requests to the catalog service", async () => {
  const env = {CATALOG: {fetch: request => worker.fetch(request, catalogStore)}};
  const response = await gateway.fetch(new Request(catalogUrl), env);
  assert.deepEqual(await response.json(), snapshot);
  for (const mod of snapshot.mods.filter(entry => entry.package)) {
    const service = {PACKAGES: {head: async () => ({size: mod.package.size})}};
    const bindings = {CATALOG: {fetch: request => worker.fetch(request, service)}};
    const request = new Request(downloadUrl(mod), {method: "HEAD"});
    assert.equal((await gateway.fetch(request, bindings)).status, 200, mod.id);
  }
});

test("validCatalog rejects unsafe adapter profiles", () => {
  const snapshot = compatibleSnapshot();
  snapshot.mods.push({...snapshot.mods[0], ...previous["binary1936-8p"], id:"legacy-cli", order:99, repo:"test/legacy-cli"});
  assert.ok(validCatalog(snapshot));
  const cliIdx = snapshot.mods.findIndex(mod => mod.adapter?.kind === "upstream-cli");
  assert.ok(cliIdx >= 0);

  const forced = structuredClone(snapshot);
  forced.mods[cliIdx].adapter.actions.install.push("--force");
  assert.equal(validCatalog(forced), false);

  const badInterp = structuredClone(snapshot);
  badInterp.mods[cliIdx].adapter.run.interpreter = "bash";
  assert.equal(validCatalog(badInterp), false);

  const badPath = structuredClone(snapshot);
  badPath.mods[cliIdx].adapter.touches.push("../evil.txt");
  assert.equal(validCatalog(badPath), false);

  const badAutoLoader = structuredClone(snapshot);
  badAutoLoader.mods[cliIdx].adapter.autoLoader = true;
  assert.equal(validCatalog(badAutoLoader), false);
});

test("a second approved GET uses the edge copy and HEAD does not prime an empty body", async () => {
  const mod = snapshot.mods.find(m => m.package.mirrorApproved);
  const values = new Map();
  let reads = 0;
  const cache = {match:async key => values.get(key)?.clone(), put:async (key,res) => values.set(key,res)};
  const original = globalThis.caches;
  globalThis.caches = {default:cache};
  const pkg = {size:mod.package.size,body:new Uint8Array(mod.package.size)};
  const env = {PACKAGES:{get:async () => { reads++; return pkg; },head:async () => pkg}};
  const pending = [];
  const get = method => worker.fetch(new Request(downloadUrl(mod), {method}),env,{waitUntil:p=>pending.push(p)});
  try {
    await get("HEAD");
    assert.equal(values.size, 0);
    assert.equal((await get("GET")).headers.get("x-package-cache"), "MISS");
    await Promise.all(pending);
    const hit = await get("GET");
    assert.equal(hit.headers.get("x-package-cache"), "HIT");
    assert.equal((await hit.arrayBuffer()).byteLength, pkg.size);
    assert.equal(reads, 1);
  } finally {
    if (original === undefined) delete globalThis.caches;
    else globalThis.caches = original;
  }
});

test("a slow or interrupted catalog request retries the same Worker endpoint", async () => {
  const urls = [];
  const data = await loadCatalog({}, async url => {
    urls.push(url);
    if (urls.length === 1) throw new DOMException("timeout", "TimeoutError");
    return Response.json(snapshot);
  });
  assert.deepEqual(data, snapshot);
  assert.deepEqual(urls,[catalogUrl,catalogUrl]);
  await assert.rejects(loadCatalog({},()=>new Response(null,{status:403})),/HTTP 403/);
  await assert.rejects(loadCatalog({},()=>{throw TypeError("fetch failed");}),/catalogConnection/);
  const absent = await serve(catalogUrl,{PACKAGES:{get:async()=>null}});
  assert.equal(absent.status,503);
});

test("legacy clients retain their original catalog without shared-repository key collisions", async () => {
  const legacy = await serve(catalogUrl.split("?")[0]);
  assert.deepEqual((await legacy.json()).mods, compatibleSnapshot().mods.filter(mod => !mod.inventoryById));
  const full = await serve(catalogUrl, catalogStore, {headers: {"If-None-Match": legacy.headers.get("etag")}});
  assert.equal(full.status, 200);
  assert.ok((await full.json()).mods.some(mod => mod.id === "lobby-bots"));
});

test("inventory-aware older apps receive the previous packages and can download Overtime offline-cache inputs", async () => {
  const old = await serve(catalogUrl.replace("&prepare=1", ""));
  const compat = await old.json();
  assert.deepEqual(compat, compatibleSnapshot());
  assert.ok(compat.mods.some(m => m.id === "lobby-bots"));
  const overtime = compat.mods.find(m => m.id === "overtime");
  const response = await serve(downloadUrl(overtime), {PACKAGES:{head:async key => {
    assert.equal(key, "packages/sha256/" + overtime.package.sha256 + ".zip");
    return {size:overtime.package.size};
  }}}, {method:"HEAD"});
  assert.equal(response.status, 200);
  assert.notEqual(old.headers.get("etag"), (await serve(catalogUrl)).headers.get("etag"));
});

test("previous Roller Carnival download still serves the published v0.1.0 package", async () => {
  const response = await serve("https://machineparty.ailaogong.men/v1/downloads/roller-carnival/v0.1.0/1001", {
    PACKAGES: {head: async key => {
      assert.equal(key, "packages/sha256/ec10da25ecd98ac6e9179d81c2188f82ae752baf4783058c87f93ea020802ca4.zip");
      return {size:138033};
    }}
  }, {method:"HEAD"});
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-length"), "138033");
});

test("only the full catalog carries the proof for its exact bytes, including over the gateway", async () => {
  const env = {...catalogStore, CATALOG_SIGNATURE:"example-signature"};
  for (const suffix of ["", "?inventory=id", "?prepare=1"]) {
    const result = await serve("https://machineparty.ailaogong.men/v1/catalog.json" + suffix, env);
    assert.equal(result.headers.get("X-Mod-Catalog-Signature"), null);
  }
  const raw = JSON.stringify(snapshot, null, 2) + "\n";
  env.PACKAGES = {get:async () => ({body:raw})};
  const storage = new Map();
  const local = {setItem:(k,v) => storage.set(k,v), getItem:k => storage.get(k)};
  const request = url => gateway.fetch(new Request(url), {CATALOG:{fetch:req => worker.fetch(req, env)}});
  let called = 0;
  const authorize = (document, signature) => {
    assert.equal(document, raw);
    assert.equal(signature, env.CATALOG_SIGNATURE);
    called++;
  };
  assert.deepEqual(await loadCatalog(local, request, authorize), snapshot);
  assert.deepEqual(await restoreCatalog(local, authorize), snapshot);
  assert.equal(called, 2);
  const prior = new Map(storage);
  await assert.rejects(loadCatalog(local, request, () => { throw Error("catalogInvalid"); }), /catalogInvalid/);
  assert.deepEqual(storage, prior);
});
