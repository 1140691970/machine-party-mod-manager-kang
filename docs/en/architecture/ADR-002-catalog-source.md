# ADR-002: Single source for the mod catalog

**English** · [简体中文](../../zh-CN/architecture/ADR-002-catalog-source.md) · [繁體中文](../../zh-TW/architecture/ADR-002-catalog-source.md)

Date: 2026-11-18. Status: accepted.

## Problem

Mod entries existed in three places: an array in `ui/app.js`, summaries and details in `ui/languages.js`, and a repository allowlist in Rust for opening author pages. Adding a mod meant editing all three and they could drift.

## Decision

`catalog/mods.json` (schema 1) is the single source. It records the manager's own top-level `repo` alongside each mod entry's stable `id`, fixed `order`, `repo`, optional `image` and `version`, `verified`, `supportedGameVersions`, `windowsPreview`, `name`, `summary` and `detail` in `zh-CN`, `zh-TW` and `en`, search `aliases`, and optional declarative `adapter` profiles.

- Rust embeds the file at compile time. The `catalog` command returns it to the UI and `open_project` only accepts the top-level manager `repo` or repositories listed in `mods`.
- The UI loads it through `bridge.js` and sorts by `order`. In a plain browser preview it is fetched from the repository.
- `tests/contracts/catalog.test.mjs` checks unique IDs, order and repositories, valid top-level `repo`, manifest/README/ZIP parity for mods under `mods/`, Windows preview metadata and `adapter` profiles, complete translations and shipped cover images; Rust tests check parsing and the allowlist.

## Alternatives

One JSON file per mod (`catalog/mods/*.json`), as planned in the [catalog delivery plan](../catalog/delivery.md), scales better for submission PRs. It can be introduced later by generating the same snapshot; the current four entries do not justify it yet. Fetching the catalog online is part of that plan and will keep this schema as its offline fallback.

## Compatibility

Displayed text, order and search behaviour are unchanged. Installation records keep `owner/repo` keys, so `repo` must not change for an existing entry.

## Evidence

Contract and Rust tests pass. Browser comparison showed identical search results for names, aliases and other-language summaries.
