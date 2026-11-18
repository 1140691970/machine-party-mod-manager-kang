import assert from "node:assert/strict";
import test from "node:test";
import worker from "../../services/update-worker/app-updates.mjs";

const host = "https://machineparty.ailaogong.men";
const stable = "/v1/app-updates/stable/latest.json";
function fixture(body) {
  const reads = [];
  const reader = method => async key => {
    reads.push([method,key]);
    return body && {body,size:Buffer.byteLength(body),httpEtag:'"123"'};
  };
  const env = {RELEASES:{get:reader("get"),head:reader("head")}};
  return {reads,fetch:(path,method="GET")=>worker.fetch(new Request(host+path,{method}),env)};
}
test("an empty stable channel returns 204 without caching",async()=>{
  const worker=fixture(null), res=await worker.fetch(stable);
  assert.equal(res.status,204);
  assert.equal(res.headers.get("Cache-Control"),"no-store");
  assert.deepEqual(worker.reads,[["get","app-releases/stable/latest.json"]]);
});
test("only exposes stable metadata and versioned installer/manifest objects",async()=>{
  const worker=fixture("data");
  assert.equal(await (await worker.fetch(stable)).text(),"data");
  const path="/v1/app-downloads/1.2.3/setup.exe";
  const res=await worker.fetch(path,"HEAD");
  assert.equal(await res.text(),"");
  assert.equal(res.headers.get("Content-Length"),"4");
  assert.match(res.headers.get("Cache-Control"),/immutable/);
  assert.equal((await worker.fetch("/v1/app-downloads/1.2.3/manifest.json")).headers.get("Content-Type"),"application/json");
  assert.equal((await worker.fetch(path,"PUT")).status,405);
  assert.equal((await worker.fetch("/v1/app-downloads/1.2.3/secret")).status,404);
  assert.deepEqual(worker.reads.map(read=>read[1]),["app-releases/stable/latest.json","app-releases/1.2.3/setup.exe","app-releases/1.2.3/manifest.json"]);
});

test("serves the Apple Silicon update archive from its versioned R2 key",async()=>{
  const worker=fixture("archive");
  const file="MachineParty-aarch64.app.tar.gz";
  const response=await worker.fetch("/v1/app-downloads/0.1.1/"+file);
  assert.equal(await response.text(),"archive");
  assert.deepEqual(worker.reads,[["get","app-releases/0.1.1/"+file]]);
});
