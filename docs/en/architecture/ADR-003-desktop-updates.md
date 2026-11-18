# ADR-003: Signed desktop updates

**English** · [简体中文](../../zh-CN/architecture/ADR-003-desktop-updates.md) · [繁體中文](../../zh-TW/architecture/ADR-003-desktop-updates.md)

Date: 2026-11-18. Status: accepted; records the chain shipped in v0.1.1.

## Problem

Players need to receive manager updates without visiting GitHub, including from mainland China, and an update must never install unsigned or unexpected binaries.

## Decision

- Windows x64 and Apple Silicon clients use `tauri-plugin-updater` with `requireSignedVersion` and a built-in public key. They poll `https://machineparty.ailaogong.men/v1/app-updates/stable/latest.json`.
- `services/update-worker` is read-only and only serves the stable manifest and `app-downloads/{version}/{setup.exe|MachineParty-aarch64.app.tar.gz|manifest.json}` from the private R2 bucket. Versioned objects are immutable.
- The **Release desktop app** workflow builds both platforms, signs them in the `production` environment, stages versioned objects, installs an old Windows client and upgrades it through the Worker, publishes the GitHub Release, and only then promotes the stable manifest.

Maintainer steps are in [Releasing](../development/releasing.md).

## Alternatives

GitHub Releases as the update endpoint are unreachable for many players in mainland China. Updating the stable manifest before end-to-end acceptance risks shipping a broken release.

## Compatibility

Installed clients trust the current public key, identifier and endpoint. Changing any of them strands existing installations, so `tests/contracts/release-config.test.mjs` pins them. The signing private key must stay in an offline backup.

## Evidence

Release run 44264743654 published v0.1.1 with darwin-aarch64 and windows-x86_64. An Apple Silicon Mac upgraded 0.1.0 to 0.1.1 through the UI and the binary matched the GitHub artifact byte for byte; Windows upgrade acceptance passed in CI.
