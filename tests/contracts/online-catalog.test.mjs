import assert from "node:assert/strict";
import test from "node:test";
import gateway from "../../services/update-worker/app-updates.mjs";
import worker from "../../services/catalog-worker/catalog.mjs";
import snapshot from "../../catalog/mods.json" with {type: "json"};
import {cachedCatalog, downloadUrl, loadCatalog, validCatalog} from "../../apps/desktop/ui/online-catalog.js";

const serve = (url, env, init) => worker.fetch(new Request(url, init), env);
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
  for (const mod of snapshot.mods) {
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
  const env = {CATALOG: {fetch: request => worker.fetch(request, {})}};
  const response = await gateway.fetch(new Request(catalogUrl), env);
  assert.deepEqual(await response.json(), snapshot);
  for (const mod of snapshot.mods) {
    const service = {PACKAGES: {head: async () => ({size: mod.package.size})}};
    const bindings = {CATALOG: {fetch: request => worker.fetch(request, service)}};
    const request = new Request(downloadUrl(mod), {method: "HEAD"});
    assert.equal((await gateway.fetch(request, bindings)).status, 200, mod.id);
  }
});
