# ADR-001: Project boundaries, keeping Tauri and native JS

**English** · [简体中文](../../zh-CN/architecture/ADR-001-project-boundaries.md) · [繁體中文](../../zh-TW/architecture/ADR-001-project-boundaries.md)

Date: 2026-11-18. Status: accepted.

## Problem

The prototype kept the Cargo crate, frontend and Worker at the repository root. Every Tauri command, Steam detection, preference and inventory code lived in `main.rs`; the mod list was hard-coded in `ui/app.js` and again as an allowlist in Rust; the UI called `window.__TAURI__` from anywhere; CSS was minified by hand. There was no check on push, so boundaries could not be enforced.

## Decision

- Keep Tauri 2, Rust and native ES modules without a bundler. Organise by owner: `apps/desktop/src-tauri`, `apps/desktop/ui`, `services/update-worker`, `catalog`, `scripts`, `tests`, `docs`.
- `main.rs` assembles; `commands.rs` validates IPC and resolves platform paths; `game`, `inventory`, `preferences` and `catalog` take plain paths and stay free of Tauri so they are unit-testable.
- `ui/bridge.js` is the only JavaScript that reaches Tauri. Pure helpers (`catalog.js`, `versions.js`) are tested under Node.
- `scripts/check_architecture.mjs` and the Source checks workflow enforce these rules alongside `cargo fmt`, `clippy` and tests.
- Rules for contributors and coding agents live in `AGENTS.md`.

## Reference

The layout follows [miband-agent-buddy](https://github.com/JamesGZM/miband-agent-buddy) by the same maintainer (apps/services split, `AGENTS.md`, ADRs per language, boundary checker). Its multi-runtime structure, shared protocol package and build generation are not needed here.

## Alternatives

Keeping a flat layout and only splitting `main.rs` was cheaper but would leave release scripts and tests coupled to root paths as services are added. A frontend framework or bundler would help a later redesign but is a stack change to be decided with that work.

## Compatibility

Command names, `installations.json`, `game-path.json`, the updater identifier, public key and stable endpoint are unchanged. Release workflows now build in `apps/desktop/src-tauri` and write artifacts to the root `dist/`. Local builds put output in `apps/desktop/src-tauri/target`.

## Evidence

`cargo test`, `clippy -D warnings`, `npm test` and `npm run check:architecture` pass. The old and new UI were loaded side by side in a browser; screenshots, search results, the details dialog, settings and the installed page matched. The macOS desktop build launched. The release workflow has not yet run with the new paths.
