# Changelog

**English** · [简体中文](docs/zh-CN/CHANGELOG.md) · [繁體中文](docs/zh-TW/CHANGELOG.md)

Notable changes for players and contributors. Versions follow the desktop app version.

## Unreleased

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
