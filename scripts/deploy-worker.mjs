import {readFile} from "node:fs/promises";
const config = JSON.parse(await readFile(new URL("../worker/wrangler.json", import.meta.url)));
const api = "https://api.cloudflare.com/client/v4";
const account = "/accounts/" + process.env.CLOUDFLARE_ACCOUNT_ID;
async function request(path, options = {}) {
  const res = await fetch(api + path, {...options, headers: {Authorization: "Bearer " + process.env.CLOUDFLARE_API_TOKEN, ...options.headers}});
  const data = await res.json();
  if (!data.success) throw Error(path + " " + JSON.stringify(data.errors));
  return data.result;
}
const form = new FormData();
form.set("metadata", JSON.stringify({
  main_module: config.main, compatibility_date: config.compatibility_date,
  bindings: config.r2_buckets.map(bucket => ({type:"r2_bucket",name:bucket.binding,bucket_name:bucket.bucket_name}))
}));
form.set(config.main,new Blob([await readFile(new URL("../worker/"+config.main, import.meta.url))],{type:"application/javascript+module"}),config.main);
await request(account + "/workers/scripts/" + config.name, {method:"PUT",body:form});
console.log("Uploaded Worker");
const hostname = "machineparty.ailaogong.men";
const domains = await request(account + "/workers/domains");
const current = domains.find(domain => domain.hostname === hostname);
if (current && current.service !== config.name) throw Error("Hostname already assigned to another Worker");
if (!current) {
  const zone = process.env.CLOUDFLARE_ZONE_ID || domains.find(d => d.zone_name === "ailaogong.men")?.zone_id || (await request("/zones?name=ailaogong.men"))[0]?.id;
  if (!zone) throw Error("Set production variable CLOUDFLARE_ZONE_ID for ailaogong.men");
  await request(account + "/workers/domains",{method:"PUT",headers:{"Content-Type":"application/json"},body:JSON.stringify({hostname,zone_id:zone,service:config.name,environment:"production"})});
}
console.log("Bound " + hostname);
