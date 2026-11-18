# Project development rules

Read the [architecture](docs/en/architecture/README.md) and [development guide](docs/en/development/README.md) before structural changes. Explicit user instructions take precedence.

## Repository responsibilities

- `apps/desktop/src-tauri`: Tauri shell. `main.rs` only assembles plugins and commands; `commands.rs` decodes and validates IPC, resolves platform paths and delegates. `game`, `inventory`, `preferences` and `catalog` are Tauri-free domain modules with unit tests beside them. `app_updates.rs` owns the signed updater.
- `apps/desktop/ui`: native ES modules without a build step. Only `bridge.js` touches `window.__TAURI__`. `catalog.js` and `versions.js` stay pure; views render from `state.js`; UI strings live in `languages.js` in all three languages.
- `catalog/mods.json`: the single source of mod identity, order, version, translations and aliases. The Rust author-page allowlist and the UI both read it.
- `services/update-worker`: read-only Cloudflare Worker serving signed app releases from R2. It never imports app code.
- `scripts`: release, deployment, acceptance and repository checks. `tests`: Node suites grouped as `ui`, `contracts` and `architecture`.
- `docs/en`, `docs/zh-CN`, `docs/zh-TW`: the same guide paths in each language ([ADR-004](docs/en/architecture/ADR-004-language-documentation.md)).

## Architecture rules

- Entry points authorize and decode, then delegate. Do not add `#[tauri::command]` to `main.rs` or Tauri types to domain modules.
- Command errors that the UI translates are message keys present in `languages.js` (for example `invalidGame`, `inventoryError`).
- Add a mod or change its text only in `catalog/mods.json`; do not hard-code repositories in Rust or JavaScript ([ADR-002](docs/en/architecture/ADR-002-catalog-source.md)).
- Preserve `installations.json`, `game-path.json`, command names, the updater public key, identifier and stable endpoint unless the user explicitly approves a migration ([ADR-003](docs/en/architecture/ADR-003-desktop-updates.md)).
- Share only behaviour used by several consumers. Do not add frameworks, bundlers or workspaces speculatively ([ADR-001](docs/en/architecture/ADR-001-project-boundaries.md)).
- Tests inject paths and data. Do not copy or rewrite production source to change behaviour in tests.

## Game files are the player's data

- Never write to a game copy before checking that the game is closed, fingerprinting the files that will change and keeping a restorable backup for that copy.
- Only install assets whose upstream release, size and SHA-256 are recorded in the catalog. Verify before applying and read back after.
- Leave unknown modifications, shared loaders and files owned by other mods untouched. When the disk state does not match the record, stop and explain instead of overwriting ([ADR-005](docs/en/architecture/ADR-005-install-transactions.md)).

## Changes and verification

- Before editing, identify affected files and state a 3–6 bullet plan. Keep changes focused and preserve uncommitted user work.
- Run the fastest relevant check first, then before handing off:
  - `npm run check:architecture` and `npm test`
  - `npm run lint:rust` and `npm run test:rust` when Rust changed
- UI changes need a screenshot. Releases, Windows installs and game restoration need physical evidence; a successful build does not prove them.
- Architecture or ownership changes need a short ADR in all three languages: problem, decision, alternatives, compatibility and evidence. `docs/*/architecture/README.md` is the one current architecture document.
- Update user-facing documentation and translations together. Report changed files, checks run and what remains unverified.

## Privacy and local-only material

- No telemetry, analytics or new network endpoints without explicit user instruction. Never commit credentials, signing keys, personal paths or player data; use synthetic fixtures.
- `.agent`, `.cursor`, `.codegraph`, `target`, `gen` and `dist` are local-only. Do not commit or delete user-local material as cleanup.
- No UI redesign, stack migration, release or unrelated behaviour change as part of structural work.
