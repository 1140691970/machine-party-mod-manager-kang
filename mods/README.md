# Repository Mods (`mods/`)

This directory holds GDScript mods authored in `machine-party-mod-manager`. Every mod under `mods/<id>/` is deterministically packaged by [`scripts/pack-mod.mjs`](../scripts/pack-mod.mjs), uploaded to Cloudflare R2 (`packages/sha256/<sha256>.zip`), served through `services/catalog-worker`, and treated identically to every other catalog mod.

## Specification & architecture

- **Mod Development, Testing, Integration & Packaging Spec**:
  [English](../docs/en/development/mod-development.md) · [简体中文](../docs/zh-CN/development/mod-development.md) · [繁體中文](../docs/zh-TW/development/mod-development.md)
- **Architecture Decision Record**: [ADR-009: Deterministic R2 packaging and self-managed loader](../docs/en/architecture/ADR-009-bundled-first-party-mods.md)

## Included mods

| ID | Name | Version | Package ZIP | Game Compatibility | Windows Verification | Documentation |
| --- | --- | --- | --- | --- | --- | --- |
| `roller-carnival` | Roller Carnival (滾筒嘉年華) | `0.1.7` | `roller-carnival-0.1.7.zip` | Steam `v2.1.2` | Verified (`v0.1.7` Lobby Bots AI) | [mods/roller-carnival/README.md](roller-carnival/README.md) |
| `lobby-bots` | Lobby Bots (房間機器人) | `0.2.2` | `lobby-bots-0.2.2.zip` | Steam `v2.1.2` | Pending physical Windows test | [Lobby Bots](lobby-bots/README.md) |
| `standalone-hd` | Standalone HD (獨立高清) | `0.1.2` | `standalone-hd-0.1.2.zip` | Steam `v2.1.2` | Pending physical Windows test | [Standalone HD](standalone-hd/README.md) |
| `player-spotlight` | Player Spotlight (玩家聚光燈) | `0.1.1` | `player-spotlight-0.1.1.zip` | Steam `v2.1.2` | Pending physical Windows test | [Player Spotlight](player-spotlight/README.md) |
| `bubble-blitz` | Bubble Blitz (泡泡爆破) | `0.1.1` | `bubble-blitz-0.1.1.zip` | Steam `v2.1.2` | Verified on Windows Steam | [Bubble Blitz](bubble-blitz/README.md) |

## Deterministic ZIP packaging rules

- [`scripts/pack-mod.mjs`](../scripts/pack-mod.mjs) discovers every subdirectory `mods/<id>/` containing `mod.json` and builds a reproducible `ZIP_STORED` archive (`<id>-<version>.zip`).
- Development, documentation, and local preview files are automatically excluded from release packages: hidden entries (`.*`), symlinks, `project.godot`, `*_scene.tscn`, `*.sh`, and `*.md`.
- `.github/workflows/catalog-worker.yml` stages generated ZIPs into R2 (`packages/sha256/<sha256>.zip`) and contract tests verify `catalog/mods.json` parity (`size`, `sha256`, `filename`, `requiredFiles`).
