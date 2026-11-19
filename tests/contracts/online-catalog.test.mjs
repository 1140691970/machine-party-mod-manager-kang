import assert from "node:assert/strict";
import test from "node:test";
import gateway from "../../services/update-worker/app-updates.mjs";
import worker from "../../services/catalog-worker/catalog.mjs";
import snapshot from "../../catalog/mods.json" with {type: "json"};
import {cachedCatalog, downloadUrl, loadCatalog, validCatalog} from "../../apps/desktop/ui/online-catalog.js";

const catalogStore = {PACKAGES:{get:async key => {
  assert.equal(key, "catalog/revisions/" + snapshot.revision + ".json");
  return {body:JSON.stringify(snapshot)};
}}};
const serve = (url, env = catalogStore, init) => worker.fetch(new Request(url, init), env);
const catalogUrl = "https://machineparty.ailaogong.men/v1/catalog.json";

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
