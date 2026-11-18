import snapshot from "../../catalog/mods.json" with {type: "json"};

const headers = {"Access-Control-Allow-Origin": "*", "Cache-Control": "no-cache"};
const catalog = JSON.stringify(snapshot);
const etag = '"' + snapshot.revision + '"';
const packages = new Map(snapshot.mods.filter(mod => mod.package).map(mod =>
  [`/v1/downloads/${mod.id}/${mod.version}/${mod.package.assetId}`, mod]));

export default {
  async fetch(request, env) {
    const head = request.method === "HEAD";
    if (!head && request.method !== "GET")
      return new Response(null, {status: 405, headers: {...headers, Allow: "GET, HEAD"}});
    const path = new URL(request.url).pathname;
    if (path === "/v1/catalog.json") {
      const metadata = {...headers, ETag: etag, "Content-Type": "application/json; charset=utf-8"};
      if (request.headers.get("If-None-Match") === etag)
        return new Response(null, {status: 304, headers: metadata});
      return new Response(head ? null : catalog, {headers: metadata});
    }
    const mod = packages.get(path);
    if (!mod) return new Response(null, {status: 404, headers});
    const pkg = mod.package;
    if (!pkg.mirrorApproved) return new Response(null, {status: 403, headers});
    const key = "packages/sha256/" + pkg.sha256 + ".zip";
    const object = head ? await env.PACKAGES.head(key) : await env.PACKAGES.get(key);
    if (!object || object.size !== pkg.size) return new Response(null, {status: 503, headers});
    return new Response(head ? null : object.body, {headers: {...headers,
      "Content-Type": "application/zip", "Content-Length": String(pkg.size),
      "Content-Disposition": `attachment; filename="${pkg.filename}"`,
      ...(pkg.noticeFile && {Link: `<https://raw.githubusercontent.com/${mod.repo}/${mod.version}/${pkg.noticeFile}>; rel="describedby"`})
    }});
  }
};
