import previous from "../../catalog/legacy-adapters.json" with {type: "json"};
import snapshot from "../../catalog/mods.json" with {type: "json"};

const headers = {"Access-Control-Allow-Origin": "*", "Cache-Control": "no-cache"};
const coverExt = {"image/png": "png", "image/webp": "webp", "image/jpeg": "jpg"};
const catalogKey = "catalog/revisions/" + snapshot.revision + ".json";
const fullEtag = '"' + snapshot.revision + '"';
const compatible = mod => previous[mod.id] ? {...mod, ...previous[mod.id]} : mod;
const packages = new Map([...snapshot.mods.map(compatible), ...snapshot.mods].filter(mod => mod.package).map(mod =>
  [`/v1/downloads/${mod.id}/${mod.version}/${mod.package.assetId}`, mod]));
const covers = new Map(snapshot.mods.filter(mod => mod.cover && coverExt[mod.cover.contentType]).map(mod => {
  const ext = coverExt[mod.cover.contentType];
  return [`/v1/covers/${mod.id}/${mod.cover.sha256}.${ext}`, {...mod.cover, ext}];
}));

export default {
  async fetch(request, env, ctx) {
    const head = request.method === "HEAD";
    if (!head && request.method !== "GET")
      return new Response(null, {status: 405, headers: {...headers, Allow: "GET, HEAD"}});
    const path = new URL(request.url).pathname;
    if (path === "/v1/catalog.json") {
      const legacy = new URL(request.url).searchParams.get("inventory") !== "id";
      const prepared = new URL(request.url).searchParams.get("prepare") === "1" && !legacy;
      const etag = !legacy && !prepared ? '"' + snapshot.revision + '-native"' : legacy ? '"' + snapshot.revision + '-legacy"' : fullEtag;
      const metadata = {...headers, ETag: etag, "Content-Type": "application/json; charset=utf-8"};
      if (prepared && env.CATALOG_SIGNATURE) {
        metadata["X-Mod-Catalog-Signature"] = env.CATALOG_SIGNATURE;
        metadata["Access-Control-Expose-Headers"] = "X-Mod-Catalog-Signature";
      }
      if (request.headers.get("If-None-Match") === etag)
        return new Response(null, {status: 304, headers: metadata});
      const object = head ? await env.PACKAGES.head(catalogKey) : await env.PACKAGES.get(catalogKey);
      if (!object) return new Response(null, {status:503, headers});
      if (!prepared && !head) {
        const catalog = await new Response(object.body).json();
        catalog.mods = catalog.mods.filter(mod => !legacy || !mod.inventoryById).map(compatible);
        return Response.json(catalog, {headers:metadata});
      }
      return new Response(head ? null : object.body, {headers:metadata});
    }
    const cover = covers.get(path);
    if (cover) {
      const key = `covers/sha256/${cover.sha256}.${cover.ext}`;
      const cache = globalThis.caches?.default;
      const cacheKey = new URL(request.url);
      cacheKey.search = "";
      const hit = cache && await cache.match(cacheKey.href);
      if (hit) {
        const response = new Response(head ? null : hit.body, hit);
        response.headers.set("X-Cover-Cache", "HIT");
        return response;
      }
      const object = head ? await env.PACKAGES.head(key) : await env.PACKAGES.get(key);
      if (!object || object.size !== cover.size) return new Response(null, {status: 503, headers});
      const response = new Response(head ? null : object.body, {headers: {...headers,
        "Cache-Control": "public, max-age=86400, s-maxage=604800, immutable",
        "X-Cover-Cache": "MISS",
        "X-Content-Type-Options": "nosniff",
        "Content-Type": cover.contentType,
        "Content-Length": String(cover.size)
      }});
      if (!head && cache && ctx) ctx.waitUntil(cache.put(cacheKey.href, response.clone()));
      return response;
    }
    const mod = packages.get(path);
    if (!mod) return new Response(null, {status: 404, headers});
    const pkg = mod.package;
    if (!pkg.mirrorApproved) return new Response(null, {status: 403, headers});
    const key = "packages/sha256/" + pkg.sha256 + ".zip";
    const cache = globalThis.caches?.default;
    const cacheKey = new URL(request.url);
    cacheKey.search = "?sha256=" + pkg.sha256;
    const hit = cache && await cache.match(cacheKey.href);
    if (hit) {
      const response = new Response(head ? null : hit.body, hit);
      response.headers.set("X-Package-Cache", "HIT");
      return response;
    }
    const object = head ? await env.PACKAGES.head(key) : await env.PACKAGES.get(key);
    if (!object || object.size !== pkg.size) return new Response(null, {status: 503, headers});
    const response = new Response(head ? null : object.body, {headers: {...headers,
      "Cache-Control": "public, max-age=0, s-maxage=86400",
      "X-Package-Cache": "MISS",
      "Content-Type": "application/zip", "Content-Length": String(pkg.size),
      "Content-Disposition": `attachment; filename="${pkg.filename}"`,
      ...(pkg.noticeFile && {Link: `<https://raw.githubusercontent.com/${mod.repo}/${mod.version}/${pkg.noticeFile}>; rel="describedby"`})
    }});
    if (!head && cache && ctx) ctx.waitUntil(cache.put(cacheKey.href, response.clone()));
    return response;
  }
};
