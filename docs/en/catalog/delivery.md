# Production catalog publishing and mainland China reachability

**English** · [简体中文](../../zh-CN/catalog/delivery.md) · [繁體中文](../../zh-TW/catalog/delivery.md)

**Status**　First-release design. The current client still ships `catalog/mods.json` in the bundle ([ADR-002](../architecture/ADR-002-catalog-source.md)). The production domain, Worker, publishing workflow and carrier acceptance results are not in place yet.

## How players get the catalog

The Windows app requests `GET /v1/catalog.json` over HTTPS from a Worker on a project-owned domain chosen at deployment. The first release deploys the approved full JSON snapshot together with the Worker, so reading the catalog never goes back to GitHub and needs no database, player account or API token. Search, ordering and language switching run locally. A failed cover falls back to a title cover so images never slow down the catalog. Author project links open only when the player clicks them.

| Contract | First-release design |
| --- | --- |
| Snapshot identity | Format version, catalog revision, publish time and mod list. The revision identifies the whole snapshot; mod versions keep upstream tags. |
| Mod data | Stable ID, fixed catalog order, author source, three-language summary and aliases, cover, and approved version data. Installable versions need compatibility conditions, a fixed asset, SHA-256 and an install method the client supports. |
| HTTP response | Success returns JSON with a content ETag; identical content with a matching If-None-Match returns 304. Cache the latest catalog for at most about 5 minutes and purge that path for emergency withdrawals. |
| Client storage | After a 200, validate format version, required fields, unique IDs and asset data, then atomically replace the local snapshot and ETag through a temporary file. A 304 keeps the valid snapshot; a missing or corrupt local file triggers an unconditional request. Error pages, truncated content and unsupported formats keep the previous valid snapshot. |

**Startup and refresh.** With a cache the catalog appears immediately and a background check looks for updates. A first install without a cache asks the Worker with a suggested 4-second timeout, retries transient network errors once and then offers manual retry. If the first sync fails, "Online catalog not available yet" is shown with retry, while Settings and local installation records stay usable. With a cache, "Using cached catalog" and the last successful sync time are shown. The Installed page merges local records with the catalog, so withdrawn mods remain visible and can be uninstalled offline. Publication status is reconfirmed before install or update; if it cannot be confirmed the existing installation stays.

## Third-party mod downloads in mainland China

The first release offers a same-domain download entry for verified packages that may be relayed, suggested as `GET /v1/downloads/{modId}/{version}/{assetId}`. The app fetches only from this URL. The Worker looks up the asset in the approved snapshot and fetches the author's pinned Release file server-side. If GitHub redirects to its release-asset host, the Worker follows the redirect, checks that the final host is an allowed upstream and streams the body to the app. Handing a 302 or the author's URL to the player would still require the player to reach GitHub. The endpoint accepts only catalogued identifiers. [Workers streams](https://developers.cloudflare.com/workers/runtime-apis/streams/)

| Condition for each release file | Delivery |
| --- | --- |
| Verified, licence allows relaying | The app always downloads from the Worker. Stream from upstream only when relaying is allowed but storage is not, and confirm the applicable service terms. Verify the published size and SHA-256 before installing. |
| Approved pinned version that may be stored and redistributed | Prefer a private R2 package store from the first release. Upload the verified original at publish time keyed by SHA-256; the Worker reads it through a binding. Players use the same download entry. |
| Author-direct only, or redistribution unconfirmed | Show the author source and the direct-download restriction. Mark direct download as usable only after testing on the three mainland carriers. Never use relaying or mirrors to change licence terms. |

On withdrawal, remove the download mapping and purge that file's public cache first; new requests check publication status before reading cache or R2. A missing upstream file reports the package as temporarily unavailable. First-release acceptance blocks GitHub and its release-asset domains on a test machine, then downloads the full package and every required loader from the production Worker domain, confirms there is no external redirect and checks hashes. It also tests upstream failure, disconnection and requests after withdrawal, on all three carriers, recording catalog and package results separately.

### Delivery path research, 2026-11-18

The CLI ZIP of [Overtime v1.7](https://github.com/DarkJadeStone/MachineParty-Overtime/releases/tag/v1.7) was fetched. GitHub responded with a 302 to release-assets.githubusercontent.com; 854,623 bytes were downloaded with SHA-256 `f98b51526c9ba38167adc0578f24d2d998f6d2f4df51e6146580df27b589245c`, matching the Release API digest. The package contains the installer and a payload ZIP. Only bytes and packaging were checked.

| Local Miniflare / workerd test | Full GET | Range: bytes=0-1023 |
| --- | --- | --- |
| Worker streaming the real GitHub Release | 200, 854,623 bytes, same hash | 206, 1,024 bytes, byte-identical |
| Worker reading the same object from simulated private R2 | 200, 854,623 bytes, same hash | 206, 1,024 bytes, byte-identical |

Partial reads only prove that range data is correct; the production endpoint still needs Content-Range, conditional resume, full reassembly and interruption recovery tests. These tests exclude the production Cloudflare edge, Windows game installation and mainland routes.

The two other candidates have package sizes of 94,946 bytes for [MachineParty+ v2.1.0](https://github.com/Ghostx10742/MachineParty-Plus/releases/tag/v2.1.0) and 32,387,456 bytes for [Binary1936 v1.5](https://github.com/Binary1936/machine-party-8p/releases/tag/v1.5) in the GitHub Release API. The three total about 33.34 MB before loaders and multiple versions. At this size, redistributable originals can go to private R2 first, so a fixed snapshot removes the dependency on upstream availability. R2 Standard includes 10 GB-month storage, one million Class A and ten million Class B operations free per month, and egress directly from R2 is free; Worker requests are billed separately. Cloudflare CDN has service terms for large file delivery that must be checked against the actual account plan; the proxy is not an unlimited file distribution service. [R2 pricing](https://developers.cloudflare.com/r2/pricing/) · [Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/) · [CDN service terms](https://www.cloudflare.com/service-specific-terms-application-services/)

Licences must be cleared package by package before launch. Overtime's MIT licence covers only the author's original work; the patch keeps game script context. MachineParty+'s MPML loader needs separate testing and separate confirmation of what may be distributed. When a licence is unclear, offer only the author link or a tested direct download. [Overtime licence](https://github.com/DarkJadeStone/MachineParty-Overtime/blob/main/LICENSE) · [MachineParty+ installation requirements](https://github.com/Ghostx10742/MachineParty-Plus#installation)

## Who can publish

1. The community recommends mods through the repository's issue form; after the maintainer selects assets, automation opens a draft PR. Contributors familiar with the data format can open a PR directly. Full steps are in the [inclusion guide](mods.md). Catalog data lives in `catalog/`; the catalog Worker is planned under `services/` beside the existing `services/update-worker`. PR CI checks format, duplicate IDs, versions and asset data and builds a previewable snapshot. Merging only updates the repository.
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

## Implementation order

Define the snapshot format and validation samples in the repository first. Then build the Worker, deployment review and production domain, verifying that the owner can publish, withdraw and roll back. Next, make the Rust client read, cache and refresh the catalog and run the three-carrier cold start acceptance. Finally, together with the Overtime Windows install and restore test, verify the first downloadable version.
