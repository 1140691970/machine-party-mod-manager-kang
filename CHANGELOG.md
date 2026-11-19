# Changelog

**English** · [简体中文](docs/zh-CN/CHANGELOG.md) · [繁體中文](docs/zh-TW/CHANGELOG.md)

Notable changes for players and contributors. Versions follow the desktop app version.

## 0.1.2-8 — 2026-11-19

Windows preview 0.1.2-8 verifies the restored PCK before removing the last managed mod, preserves shared loaders for linked mods, and checks that the game is closed immediately before replacing its PCK.

## 0.1.2-7 — 2026-11-19

Windows preview with six online mods, verified source-to-MPML conversion, and confirmation of the mods removed during switching.

## 0.1.2-6 — 2026-11-19

Removed special `firstParty` UI badges and catalog overrides so every mod packaged into R2 (`roller-carnival v0.1.0` included) follows the exact same catalog schema, R2 Worker download flow, and UI presentation.

## 0.1.2-5 — 2026-11-19

Windows preview `0.1.2-5` enables `v2.1.2` test installation across all five catalogued mods (`Overtime v1.7`, `MachineParty+ v2.1.0`, `Broadcast 8P Freecam v0.91`, `Binary1936 eight-player mod v1.5`, and `Roller Carnival v0.1.0`), adding `loader-files`, PowerShell, and bundled-Python support, mutual-exclusion conflict checks, and the manager's clean-room PCK auto-loader (`pck_loader.rs` + `mpm_bootstrap.gd`) with lossless vanilla restoration.

### Added

- Deterministically package mods under `mods/<id>/` (`roller-carnival v0.1.0`) via `scripts/pack-mod.mjs` into R2 + `services/catalog-worker`, downloading and verifying via SHA-256 identically to all other catalog entries.

## 0.1.2-4 — 2026-11-19

The Windows preview tests unified installation and uninstallation outcome headings, one automatic retry for catalog timeouts or transient network failures, and explicitly unsigned preview installers when no code-signing identity is configured.

### Changed

- Uninstall now runs a structured step-by-step dialog with read-back verification and retry; rescanning keeps an existing valid game folder if detection finds zero or multiple copies.
- Settings use a three-button segmented language switcher, right-aligned game folder controls showing only the root path and version tag (removing the redundant full-recheck button), and a unified manager row linking to GitHub on the left with the version number and update indicator dot on the right.
- Replaced the top update banner button with a non-forcing update dialog that opens automatically once per release (queuing behind active dialogs) and displays release notes when available.

## 0.1.2-3 — 2026-11-19

Closing a download cancels the transfer and frees the install button. Packages can be served from the existing mirror’s edge cache. The list uses remote entries and offers a retry on sync failure. Offline copies of the last successful catalog are labeled.

## 0.1.2-2 — 2026-11-19

The Windows preview supports Overtime v1.7 on the pinned v2.1.2 game build. Choose Install once. If the game folder is missing, select a copy before the download starts. The dialog downloads the package if needed, verifies it and installs it. Cached packages can be installed offline. Close the game before modifying a copy. Other catalog entries list compatibility as unconfirmed until a supported build is documented.

## 0.1.2-1 — 2026-11-19

Windows x64 preview for testing the refreshed interface, online mod catalog, game folder detection and per-copy status. This preview enables installation and offline restoration of the bundled Overtime v1.7 profile on Windows for testing.

### Changed

- Reorganised the repository into `apps/desktop`, `services/update-worker` and `catalog`. The mod list now comes from a single `catalog/mods.json`. No visible change for players.
- Documentation is available in English, Simplified Chinese and Traditional Chinese, with architecture decision records.

### Added

- Contributor guide, security and support policies, issue and pull request templates, and source checks on every push.

## 0.1.1 — 2026-11-18

### Added

- Apple Silicon Mac build with signed in-app updates sharing the Windows stable channel.

## 0.1.0 — 2026-11-18

### Added

- First prototype: bundled catalog of four candidate mods with search, details and author links in three languages.
- Steam game detection, manual folder selection and per-copy version comparison.
- Signed in-app updates for Windows x64, served through the project's update Worker.
