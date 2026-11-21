# ADR-016: Optional R2-hosted mod cover images

**English** · [简体中文](../../zh-CN/architecture/ADR-016-r2-mod-covers.md) · [繁體中文](../../zh-TW/architecture/ADR-016-r2-mod-covers.md)

## Problem

Previously, the desktop manager loaded mod card covers from `apps/desktop/ui/images/<image>.png` bundled directly into the desktop installer. This created three problems:

1. Adding a new mod or refreshing a mod's cover required shipping a new desktop app release, even though the catalog and mod packages already update dynamically through Cloudflare R2 and `services/catalog-worker`.
2. Bundling high-resolution PNG screenshots inflated the desktop installer by ~5.8 MB and grew linearly with every new mod.
3. The cover convention was implicit rather than part of the catalog & mod specification.

## Decision

1. **No built-in mod cover images**: Remove all mod cover files from `apps/desktop/ui/images/`, leaving only app chrome assets (`logo.svg`). Contract tests enforce that no mod covers are bundled into `apps/desktop/ui/images/`.
2. **Optional `cover` specification**: Mod covers are optional. When provided, source images live under `catalog/covers/<id>.<ext>` (`.png`, `.webp`, or `.jpg`, recommended `1280×720` 16:9, max 4 MiB) and are declared in `catalog/mods.json` as:
   ```json
   "cover": {
     "filename": "spike-ring.png",
     "contentType": "image/png",
     "size": 832988,
     "sha256": "<64-hex>"
   }
   ```
   Omitting `cover` is valid; the UI renders the card title fallback (`cover-title`).
3. **Content-addressed R2 storage and Worker delivery**:
   - CI (`.github/workflows/catalog-worker.yml`) verifies each declared cover's local size and SHA-256 and uploads immutable objects to R2 under `covers/sha256/<sha256>.<ext>`.
   - `services/update-worker` forwards `/v1/covers/*` to `services/catalog-worker`.
   - `services/catalog-worker` serves only covers declared in the deployed catalog at `GET|HEAD /v1/covers/<modId>/<sha256>.<ext>`, validating R2 object size and setting `Cache-Control: public, max-age=86400, s-maxage=604800, immutable`, `X-Content-Type-Options: nosniff`, and edge caching.
4. **Desktop UI & CSP**:
   - `tauri.conf.json` allows `https://machineparty.ailaogong.men` in `img-src`.
   - `online-catalog.js` validates `cover` metadata and computes `coverUrl(mod)`; `catalog-view.js` loads the cover lazily and falls back to the title placeholder on error or offline cache miss.

## Alternatives considered

- **Keep bundling covers in the desktop app**: Simplest offline behavior, but blocks dynamic catalog updates and bloats every installer.
- **Public R2 bucket or GitHub raw URLs**: GitHub raw URLs fail in mainland China; a public R2 bucket bypasses catalog allowlisting and size/type verification.

## Compatibility

- Older desktop clients (v0.2.3 and earlier) ignore unknown fields like `cover` and accept entries without `image`, showing the clean title fallback until they auto-update to v0.2.4.
- `online-catalog.js` continues to tolerate optional legacy `image` slugs in cached snapshots so upgrades from older caches remain seamless.

## Evidence

- `tests/contracts/catalog.test.mjs` verifies that `apps/desktop/ui/images/` contains only `logo.svg`, no catalog entry uses legacy `image`, and every declared `cover` matches `catalog/covers/<filename>` in size, SHA-256, content type, and 4 MiB cap.
- `tests/contracts/online-catalog.test.mjs` verifies gateway forwarding, Worker R2 key resolution, edge caching, headers, error codes, and malformed `cover` rejection.
- `.github/workflows/catalog-worker.yml` stages covers to R2 and verifies every live `HEAD /v1/covers/<modId>/<sha256>.<ext>` response.
