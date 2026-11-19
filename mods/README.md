# First-Party Mods (`mods/`)

This directory holds first-party GDScript mods authored and maintained inside `machine-party-mod-manager`. Every mod under `mods/<id>/` is deterministically packaged by [`scripts/pack-mod.mjs`](../scripts/pack-mod.mjs), hosted on Cloudflare R2 (`packages/sha256/<sha256>.zip`), served through `services/catalog-worker`, and installed into `<pckDir>/mods/<id>/` using the built-in clean-room loader (`mpm_bootstrap.gd` + `pck_loader.rs`).

## Specification & architecture

- **Mod Development, Testing, Integration & Packaging Spec**:
  [English](../docs/en/development/mod-development.md) · [简体中文](../docs/zh-CN/development/mod-development.md) · [繁體中文](../docs/zh-TW/development/mod-development.md)
- **Architecture Decision Record**: [ADR-009: First-party mods, deterministic R2 packaging, and self-managed loader](../docs/en/architecture/ADR-009-bundled-first-party-mods.md)

## Included mods

| ID | Name | Version | Package ZIP | Game Compatibility | Windows Verification | Documentation |
| --- | --- | --- | --- | --- | --- | --- |
| `roller-carnival` | Roller Carnival (滾筒嘉年華) | `0.1.0` | `roller-carnival-0.1.0.zip` | Steam `v2.1.2` | Pending physical Windows test | [mods/roller-carnival/README.md](roller-carnival/README.md) |

## Deterministic ZIP packaging rules

- [`scripts/pack-mod.mjs`](../scripts/pack-mod.mjs) discovers every subdirectory `mods/<id>/` containing `mod.json` and builds a reproducible `ZIP_STORED` archive (`<id>-<version>.zip`).
- Development, documentation, and local preview files are automatically excluded from release packages: hidden entries (`.*`), symlinks, `project.godot`, `*_scene.tscn`, `*.sh`, and `*.md`.
- `.github/workflows/catalog-worker.yml` stages generated ZIPs into R2 (`packages/sha256/<sha256>.zip`) and contract tests verify `catalog/mods.json` parity (`size`, `sha256`, `filename`, `requiredFiles`).
