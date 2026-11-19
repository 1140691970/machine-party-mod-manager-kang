# ADR-006 · Online mod catalog

**English** · [简体中文](../../zh-CN/architecture/ADR-006-online-catalog.md) · [繁體中文](../../zh-TW/architecture/ADR-006-online-catalog.md)

The client needs an independently updatable catalog.

The client reads the Worker snapshot at startup and caches validated data for offline browsing. Each version maps its Release asset ID to the R2 key `packages/sha256/<sha256>.zip`. Only packages cleared for mirroring are served. The Worker reads the released catalog from the immutable R2 object `catalog/revisions/<revision>.json`. Deployment verifies the object before switching the Worker to its revision.

Bundling the list requires a new desktop release for each catalog edit. Listing bucket contents would expose staged files.

Existing installation records, IPC and signed updates keep their existing formats. The online catalog contract tests cover refresh, cache, package lookup and download gates.

The public gateway forwards catalog and download requests to `machine-party-catalog` via the `CATALOG` binding. Deploy the catalog service before binding it on a new account.
