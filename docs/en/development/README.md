# Development guide

**English** · [简体中文](../../zh-CN/development/README.md) · [繁體中文](../../zh-TW/development/README.md)

## Prerequisites

- Rust stable 1.88 or newer (edition 2024 with let-chains), with `rustfmt` and `clippy`.
- Node.js 22 or newer. No npm dependencies are installed; Node runs tests and scripts only.
- Windows: Microsoft C++ Build Tools and WebView2 (preinstalled on Windows 11). macOS: Xcode Command Line Tools.
- Packaging installers additionally uses `npx @tauri-apps/cli@2.12.5`, as in the release workflow.

## Repository layout

| Path | Contents |
| --- | --- |
| `apps/desktop/src-tauri` | Rust crate, `tauri.conf.json`, capabilities and icons |
| `apps/desktop/ui` | HTML, CSS and ES modules loaded directly by the WebView |
| `catalog/mods.json` | Mod catalog shipped with the app |
| `mods/<id>/` | First-party GDScript mods packaged into `.zip` archives by `scripts/pack-mod.mjs` for R2 + catalog Worker delivery |
| `services/update-worker` | Cloudflare Worker for app updates |
| `scripts` | Release, deployment, upgrade acceptance and `check_architecture.mjs` |
| `tests` | Node tests: `ui`, `contracts`, `architecture` |

See the [current architecture](../architecture/README.md) for responsibilities and [AGENTS.md](../../../AGENTS.md) for the rules every change follows.

## Run

```sh
npm run dev
```

This runs `cargo run` for the desktop app. Steam detection and game-folder actions work on any platform, but installation targets Windows.

To preview the UI in a browser without Tauri, serve the repository root and open the UI page. Desktop-only actions are hidden.

```sh
python3 -m http.server 8000
# open http://127.0.0.1:8000/apps/desktop/ui/index.html
```

## Verify

Run the fastest relevant check first, then all of these before opening a pull request:

```sh
npm run check:architecture
npm test
npm run lint:rust
npm run test:rust
```

The **Source checks** workflow runs the same commands on every push and pull request. UI changes need a screenshot. Builds do not prove Windows installs, game restoration or updates; describe what was tested physically.

## Simulating mod installation on macOS

Machine Party on Steam is Windows-only, so playing the game on macOS is out of scope. Before physical Windows verification (P2), installation logic is verified on macOS across three simulation tiers ([ADR-007](../architecture/ADR-007-mod-adapters.md)):

- **L1 (Unit and contract tests)**: `FakeRunner` with a synthetic Godot PCK (a few KB with valid `GDPC` header and `res://` index) and fault injection for interrupted downloads, crashed writes, Steam updates, unknown modifications and locked files.
- **L2 (Real subprocess tests)**: `ProcessRunner` executing a cross-platform fake CLI script matching Overtime's flags and `State:` output, plus cross-platform upstream scripts such as `install.py` under `python3` against synthetic PCKs.
- **L3 (Local vanilla PCK + Mono)**: local-only verification with Mono running `overtime_install.exe` against an uncommitted copy of the Windows vanilla `Machine Party.pck` (v2.1.2, SHA-256 `326cc3988d3ac554d1f288bed89b1f89d450f78ec9d4470f88558975753dfa8e`). Never commit game files (`Machine Party.pck`) to the repository.

## Common changes

- **Add or edit a mod**: change `catalog/mods.json` only. Provide `name`, `summary` and `detail` in all three languages, keep `id` and `repo` stable, and add a cover to `apps/desktop/ui/images/{image}.png` if `image` is set. Inclusion follows the [mod catalog guide](../catalog/mods.md).
- **Add a first-party mod**: follow the [first-party mod specification](mod-development.md) (`mods/<id>/` with `README.md`, `mod.json` matching `^[a-z0-9-]+$`, and GDScript sources), run `node scripts/pack-mod.mjs <id>` (`scripts/pack-mod.mjs` excludes `project.godot`, `*_scene.tscn`, `*.sh`, and `*.md`), add a `firstParty: true` + `package` + `adapter.kind: "loader-files"` (`autoLoader: true`) entry in `catalog/mods.json`, and run Godot syntax/self-tests plus `npm run test:rust` and `npm test` ([ADR-009](../architecture/ADR-009-bundled-first-party-mods.md)).
- **Add UI text**: add one key with Simplified Chinese, Traditional Chinese and English values to `apps/desktop/ui/languages.js`.
- **Add a command**: implement the logic in a Tauri-free module with a unit test, expose it in `commands.rs`, register it in `main.rs`, and call it only from `bridge.js`.
- **Change architecture**: add an ADR in `docs/en`, `docs/zh-CN` and `docs/zh-TW` and update the current architecture page.

Releases are described in [Releasing](releasing.md).
