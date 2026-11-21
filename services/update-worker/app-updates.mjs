export default {
  async fetch(request, env) {
    if (!["GET", "HEAD"].includes(request.method)) return new Response(null, {status: 405, headers: {Allow: "GET, HEAD"}});
    const path = new URL(request.url).pathname;
    if (path === "/v1/catalog.json" || path.startsWith("/v1/downloads/") || path.startsWith("/v1/covers/"))
      return env.CATALOG.fetch(request);
    const stable = path === "/v1/app-updates/stable/latest.json";
    const preview = /^\/v1\/app-downloads\/(\d+\.\d+\.\d+-\d+)\/(setup\.exe)$/.exec(path);
    const asset = preview || /^\/v1\/app-downloads\/(\d+\.\d+\.\d+)\/(setup\.exe|MachineParty-aarch64\.app\.tar\.gz|manifest\.json)$/.exec(path);
    if (!stable && !asset) return new Response(null, {status: 404});
    const key = stable ? "app-releases/stable/latest.json" : `app-releases/${asset[1]}/${asset[2]}`;
    const object = request.method === "HEAD" ? await env.RELEASES.head(key) : await env.RELEASES.get(key);
    if (!object) return new Response(null, {status: stable ? 204 : 404, headers: {"Cache-Control":"no-store"}});
    const json = key.endsWith(".json");
    return new Response(request.method === "HEAD" ? null : object.body, {headers:{
      "Content-Type": json ? "application/json" : "application/octet-stream",
      "Content-Length": String(object.size), "ETag":object.httpEtag,
      "Cache-Control": stable ? "no-store" : "public, max-age=86400, immutable"
    }});
  }
};
