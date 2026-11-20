# Production catalog publishing and mainland China reachability

**English** · [简体中文](../../zh-CN/catalog/delivery.md) · [繁體中文](../../zh-TW/catalog/delivery.md)

**Online mod catalog**　The client reads the Worker snapshot at startup and caches validated data for offline browsing. Each version maps its Release asset ID to the R2 key `packages/sha256/<sha256>.zip`. Only packages cleared for mirroring are served. [ADR-006](../architecture/ADR-006-online-catalog.md)

## How players get the catalog

The desktop app requests `GET /v1/catalog.json?inventory=id&prepare=1` from the project Worker. The Worker reads the approved revision from R2. Earlier clients receive a compatible snapshot. Search, ordering and language switching run locally.

| Item | Catalog behavior |
| --- | --- |
| Snapshot identity | Schema version, catalog revision and mod list. The revision identifies the snapshot. Mod versions follow the upstream tags. |
| Mod data | Stable ID, fixed catalog order, author source, three-language summary and aliases, cover, and approved version data. Installable versions need compatibility conditions, a fixed asset, SHA-256 and an install method the client supports. |
| HTTP response | The Worker supplies an ETag for each catalog variant and returns 304 for a matching `If-None-Match`. |
| Client storage | The desktop client validates the catalog and verifies its signature for online package approvals. It caches the signed document for offline verification and keeps a browsing copy. |

On startup the client displays a valid cache and refreshes in the background. A request times out after 15 seconds. A timeout, connection failure or server error (5xx) gets one retry. If refresh fails, players can browse cached entries and retry manually. The Installed page also uses local records for offline removal.

## Third-party mod downloads in mainland China

The app downloads approved packages from `GET /v1/downloads/{modId}/{version}/{assetId}`. The Worker checks the catalog mapping and mirror approval, then serves the package from the edge cache or private R2. Deployment verifies the size and SHA-256 of each new upstream package before staging it. The client verifies the downloaded package before installation.

Test each approved download with GitHub blocked. Fetch the full package and required loaders, check hashes, and verify behavior after disconnection and withdrawal. For clients that support resuming a partial download, also verify Content-Range, conditional resumption and the hash of the reassembled file.

Licences must be cleared package by package before launch. Overtime's MIT licence covers only the author's original work; the patch keeps game script context. MachineParty+'s MPML loader needs separate testing and separate confirmation of what may be distributed. When a licence is unclear, offer only the author link or a tested direct download. [Overtime licence](https://github.com/DarkJadeStone/MachineParty-Overtime/blob/main/LICENSE) · [MachineParty+ installation requirements](https://github.com/Ghostx10742/MachineParty-Plus#installation)

### Package preparation and compatibility

The one-click installer verifies the original release ZIP against its catalog size and SHA-256. Rust prepares the MPML directory in staging. Overtime uses its CLI payload manifest and retains the upstream load-order, version and vanilla-script checks. Broadcast and Binary1936 use their resource trees. MachineParty+, Roller Carnival and Lobby Bots already ship in loader format. `?inventory=id&prepare=1` · `/v1/downloads/overtime/v1.7/594522625`.

Older clients receive their compatible catalog and download URLs. Existing Overtime MPML installations keep working. Select the migration action in the details of a managed legacy PCK patch to verify the replacement, restore the recorded copy, and install through the loader. Move a manual mods/broadcast-8p folder out of the game first. Unknown file changes stop recovery.

## Who can publish

1. Contributors submit an issue or a PR. A maintainer reviews the selected assets and updates `catalog/mods.json`. The catalog Worker lives in `services/catalog-worker/`. See the [inclusion guide](mods.md).
2. The repository owner publishes by choosing a merged main commit. The deployment job uses the GitHub `production` environment, restricted to main with JamesGZM as required reviewer; a single maintainer may approve their own deployment. The review screen should show the commit SHA, revision and change list. PR validation jobs have no deployment credentials.
3. The Cloudflare deploy token is the environment secret `CLOUDFLARE_API_TOKEN` and the account ID the environment variable `CLOUDFLARE_ACCOUNT_ID`, granted only the permissions needed for the target account. The app reads only public endpoints. [GitHub deployment environments](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments) · [Cloudflare deploys from Actions](https://developers.cloudflare.com/workers/ci-cd/external-cicd/github-actions/)
4. After deployment, read the JSON back from the production domain, compare revision and snapshot hash, and verify sync with the previous client. Record commit, hash, deployed version and result. On problems the owner approves republishing the last good data with a new revision and purges the cache, and confirms ordinary clients recover from the bad version. Before rolling back, check withdrawn mods so downloads are not reopened by accident.

## Accepting mainland reachability

A regular Worker with a custom domain gives a stable service name whose deployment can change behind the same URL. Cross-border connections still depend on location, carrier and time of day. Cloudflare China Network is a separately purchased Enterprise service whose product coverage must be checked; this project's first release is tested on a regular Worker without in-country service. [Cloudflare China Network](https://developers.cloudflare.com/china-network/) · [Available products](https://developers.cloudflare.com/china-network/reference/available-products/)

| Pre-launch test | Suggested first-round pass condition |
| --- | --- |
| Cold start on real networks | Test the production domain on ordinary consumer lines of China Telecom, China Unicom and China Mobile, in at least two provinces or cities, during the day and the evening peak, with VPNs and proxies off. Cold start 10 times per line and period. Suggested pass: at least 9 per group show the correct catalog within 5 seconds and the rest succeed within one automatic retry. Judge each group separately. |
| No GitHub dependency | Block GitHub, raw and its asset domains on the test machine, clear the app cache, and still get the latest revision from the Worker with working search and pages. Also test the title cover when images fail. |
| Versions and failures | Test 200, 304, withdrawal, rollback, DNS failure, TLS failure, timeout and corrupt JSON, from both a first install and an existing cache. Errors must not overwrite a valid cache, and sync must resume after reconnection. |
| End-to-end download | For every version opened to mainland installs, download the full asset on all three carriers and check hashes, plus interrupted retries. Record catalog success and download success separately. |

Record date, city, carrier, time period, client version, revision, success count, time to first screen and failure stage (DNS, TLS, HTTP, parsing or asset download). These are the publisher's own measurements. Retest on the same lines periodically after launch and rerun after domain or routing changes. The thresholds are for first-release acceptance; ongoing service levels need long-term measurement.

**If targets are missed.** Locate the failing stage first, then evaluate a fallback entry on an independent route serving the same approved snapshot; only an entry preconfigured in the client can take over when the main site is unreachable. If in-country delivery is needed, check provider support, qualifications and cost. A fallback must pass the same cold start, update, withdrawal and rollback acceptance before coverage is announced.
