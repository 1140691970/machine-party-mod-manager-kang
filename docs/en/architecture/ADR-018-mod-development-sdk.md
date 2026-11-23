# ADR-018: MPM Mod Development SDK & Tooling Architecture

**English** · [简体中文](../../zh-CN/architecture/ADR-018-mod-development-sdk.md) · [繁體中文](../../zh-TW/architecture/ADR-018-mod-development-sdk.md)

- **Status**: Implemented & Verified (Headless tests + Windows Steam `v2.1.2` physical test passed)
- **Date**: 2026-11-23
- **Related**: [ADR-001](ADR-001-project-boundaries.md), [ADR-009](ADR-009-bundled-first-party-mods.md), [ADR-015](ADR-015-multi-minigame-hub.md), [ADR-017](ADR-017-modular-boundaries-and-core-runtime.md), [Mod SDK Reference](../development/mod-sdk.md)

## Context

Following [ADR-017](ADR-017-modular-boundaries-and-core-runtime.md) Phases 1–3, the repository has clean Rust/UI module boundaries, shared `mods/_shared/` templates, declarative `requires` dependency management, and the [`mpm-core`](../../../mods/mpm-core/README.md) (`v0.1.0`, `priority: -100`) runtime library. However, authoring a fourth first-party minigame or opening modding to external contributors still suffers from four developer-experience gaps:

1. **Per-mod boilerplate (~250–350 lines)**: Each minigame duplicates `_register_mod_scripts`, `_register_into_hub`, `_install_hub_overrides`, `_apply_cached_override`, `official_minigame.gd`, and pool warmup boilerplate.
2. **Manual authoring & catalog chores**: Creating a new mod requires manually authoring 7–10 files, picking unused `order` / `assetId` / `TARGET_SLOT_ID` numbers, syncing `catalog/mods.json`, and updating 4 README tables.
3. **Duplicated Godot test fixtures**: Each test under `tests/mods/` reimplements its own `MockLoader`, `PlayerManager`, `GameManager`, `Minigame`, `LobbyScene`, `1280×720` headless window setup, and `.gd.uid` cleanup.
4. **Hardcoded vanilla enum slots & manual red-line enforcement**: Current minigames borrow unused `MinigameIdentifier` slots (6, 8, 17), which will collide once mods scale; performance/compile red lines (no `get_property_list()` in `_process`, no untyped `:=` on dynamic returns, no hardcoded `preload("res://...")`) are documented in [mod-development.md](../development/mod-development.md) but not statically checked.

## Open-Source Ecosystem References

Rather than inventing an SDK from scratch, we adapt proven patterns from mature open-source modding ecosystems while preserving [ADR-001](ADR-001-project-boundaries.md) (zero third-party JS/Cargo build frameworks):

| Ecosystem / Project | What we adopt | What we intentionally omit |
| --- | --- | --- |
| **GodotModding / `godot-mod-loader`** (Brotato, Dome Keeper) | Godot 4 manifest conventions, `ModLoaderHookChain`-style method hooks, structured mod logging (`user://modloader.log`), and author dev tooling | Heavy editor plugin UI; our desktop manager + headless Godot CLI already covers packaging and validation |
| **SMAPI** (`Pathoschild/SMAPI`, Stardew Valley) | Unified mod helper facade (`Events`, `i18n`, `Registry`), explicit compatibility contracts, and static analyzers that catch unsafe patterns before runtime | C#/.NET assembly rewriting; MPML operates on GDScript `take_over_path` and `compile` |
| **Fabric Loader + Fabric API** (`FabricMC/fabric`) | Minimal, rarely updated bootstrap loader (`mpm_bootstrap.gd`) cleanly separated from an independently versioned library mod (`mpm-core`) plus official template scaffolding | Separate external repository split (deferred per ADR-017 Phase 5) |
| **Thunderstore CLI (`tcli`)** | Single-command `new` / `check` / `pack` CLI workflow with strict manifest & deterministic ZIP verification | External registry upload (we publish to R2 + `services/catalog-worker`) |
| **tModLoader** | Declarative content registration with dynamic ID allocation instead of claiming hardcoded vanilla enum IDs | Binary asset compilation pipeline |

## Decision

Introduce a **Four-Layer Lightweight MPM Mod SDK** built strictly on Node 22 built-ins, `mpm-core`, and GDScript:

1. **Layer 1 — Runtime SDK (`mods/mpm-core/`)**:
   - Provide `MpmMinigamePlugin` / `core.register_minigame(spec)` so a minigame `main.gd` declares metadata, trilingual briefing/controls, and stage script without copying hub glue.
   - Provide reusable `MpmFxPool` (persistent pool + in-frustum warmup) and `MpmTeamSupport` bridges alongside `event_bus`, `locale`, and `lobby_ui` Coordinator v2.
   - Extend Hub v2 to allocate dynamic high-ID slots (`>= 1000`) mapped by `mod_id`, eliminating hardcoded `MinigameIdentifier` slot collisions.
2. **Layer 2 — Zero-Dependency Dev CLI (`scripts/mod-cli.mjs`, `npm run mod -- <cmd>`)**:
   - `mod new <id> --template minigame|tool|graphics`: scaffolds `mod.json`, `main.gd`, `README.md`, `project.godot`, `run_mac.sh`, and starter `--self-test`.
   - `mod check <id>`: runs Godot `--check-only`, `--self-test`, static mod linter, and `pack-mod` parity in one command.
   - `mod catalog-sync <id>`: updates deterministic `filename`, `size`, `sha256`, and `requiredFiles` in `catalog/mods.json`.
3. **Layer 3 — Shared Godot Test Harness (`tests/mods/_harness/`)**:
   - Extract reusable `MockLoader` (API v2 compliant), `MockGameEnv` (`PlayerManager`, `GameManager`, `Minigame`, `LobbyScene`, `1280×720` headless viewport, `.gd.uid` teardown), and a parameterized minigame contract test (cold-start compile → preloaded scene registration → FFA → native `team-party` → multi-mod coexistence → leak-free exit).
4. **Layer 4 — Static Mod Linter & Formal SDK Contract**:
   - Add static GDScript checks to `check_architecture.mjs` / `mod check`: flag `get_property_list()` inside `_process` / `_physics_process`, untyped `:=` on dynamic `keys()` / `.call()`, hardcoded `preload("res://...")` in MPML-loaded scripts, duplicate `TARGET_SLOT_ID`, and missing `mpm_local_player` metadata on minigame local actors.
   - Publish and maintain a versioned public contract in [Mod SDK Reference](../development/mod-sdk.md) distinguishing **Stable Public Contracts** from **Internal Implementation**.

## Phased Rollout

| Phase | Scope | Risk / Prerequisite |
| --- | --- | --- |
| **SDK-1** | Formal API contract (`mod-sdk.md`) + Static Mod Linter (`scripts/mod-lint.mjs` in `check:architecture`) | **Completed & Verified** (`tests/architecture/mod-lint.test.mjs`, `npm run check:architecture`) |
| **SDK-2** | Shared Godot Test Harness (`tests/mods/_harness/`) + `scripts/mod-cli.mjs` (`new` / `check` / `catalog-sync`) | **Completed & Verified** (`tests/contracts/mod-cli.test.mjs`, `tests/mods/harness.test.mjs`) |
| **SDK-3** | `mpm-core` Runtime SDK (`register_minigame(spec)`, `MpmFxPool`, Hub v2 dynamic slots `>= 1000`) | **Completed & Verified** (`tests/mods/mpm-core.test.mjs`; Windows Steam `v2.1.2` physical test pending) |
| **SDK-4** | Method-level hook chain (`hook_chain.gd` in `mpm-core`) + first-party minigame `mpm-core` migration | **Completed & Headless Verified** (`tests/mods/mpm-core.test.mjs`, `roller-carnival` / `bubble-blitz` / `spike-ring` declare `requires: ["mpm-core"]`) |

## Alternatives Considered

- **Adopt an external JS/TS CLI framework or TypeScript SDK**: Rejected per [ADR-001](ADR-001-project-boundaries.md); Node 22 built-ins keep `node_modules` empty and CI fast.
- **Embed the entire SDK inside `mpm_bootstrap.gd`**: Rejected per [ADR-017](ADR-017-modular-boundaries-and-core-runtime.md); every SDK improvement would force a signed desktop release instead of a lightweight `mpm-core` catalog update.
- **Force immediate migration of all 3 existing minigames onto `MpmMinigamePlugin`**: Rejected; existing minigames stay stable until `mpm-core` (`requires`) passes physical Windows verification.

## Compatibility

- Preserves `catalog/mods.json` `schema: 1`, existing MPML API v2 (`API_VERSION = 2`), `MachinePartyModLoader.exe` coexistence, and existing `mods/<id>/` layouts.
- Existing Hub v1 (`TARGET_SLOT_ID` 6, 8, 17) mods remain valid alongside dynamic Hub v2 (`>= 1000`) slots.

## Verification Gates

- **SDK-1**: `node --test tests/contracts/documentation.test.mjs`, `npm run check:architecture`, and linter unit tests in `tests/architecture/`.
- **SDK-2**: Scaffolding a temporary mod passes `mod check`, contract tests, and deterministic `pack-mod --verify-catalog`.
- **SDK-3 & SDK-4**: Full Godot 4.5.2 coexistence & `team-party` suite + physical Windows Steam `v2.1.2` verification.
