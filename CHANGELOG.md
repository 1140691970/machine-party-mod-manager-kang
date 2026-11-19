# Changelog

**English** · [简体中文](docs/zh-CN/CHANGELOG.md) · [繁體中文](docs/zh-TW/CHANGELOG.md)

Notable changes for players and contributors. Versions follow the desktop app version.

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
