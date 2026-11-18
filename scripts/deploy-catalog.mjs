import {readFile} from "node:fs/promises";

const read = path => readFile(new URL(path, import.meta.url), "utf8");
const config = JSON.parse(await read("../services/catalog-worker/wrangler.json"));
const account = "/accounts/" + process.env.CLOUDFLARE_ACCOUNT_ID;
async function api(path, options = {}) {
  const response = await fetch("https://api.cloudflare.com/client/v4" + path, {
    ...options, headers: {...options.headers, Authorization: "Bearer " + process.env.CLOUDFLARE_API_TOKEN}
  });
  const data = await response.json();
  if (!data.success) throw Error(data.errors.map(error => error.code + " " + error.message).join(", "));
  return data.result;
}

const snapshot = await read("../catalog/mods.json");
const form = new FormData();
form.set("metadata", JSON.stringify({
  main_module: config.main, compatibility_date: config.compatibility_date,
  bindings: config.r2_buckets.map(({binding, bucket_name}) => ({type: "r2_bucket", name: binding, bucket_name}))
}));
// JSON modules are bundled by Wrangler locally. Upload the same snapshot as a JS module via the API.
const source = (await read("../services/catalog-worker/" + config.main))
  .replace('from "../../catalog/mods.json" with {type: "json"}', 'from "./snapshot.mjs"');
for (const [name, contents] of [[config.main, source], ["snapshot.mjs", "export default " + snapshot]]) {
  form.set(name, new Blob([contents], {type: "application/javascript+module"}), name);
}
await api(account + "/workers/scripts/" + config.name, {method: "PUT", body: form});
console.log("Uploaded catalog Worker");
