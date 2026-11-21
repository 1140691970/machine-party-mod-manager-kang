# Third-party notices

**English** · [简体中文](docs/zh-CN/THIRD_PARTY_NOTICES.md) · [繁體中文](docs/zh-TW/THIRD_PARTY_NOTICES.md)

Machine Party Mod Manager is licensed under GPL-3.0-only. The following material belongs to others and keeps its own terms.

## Game

Machine Party and its assets belong to their developer and publisher. This project is not affiliated with them and does not redistribute game files.

## Catalogued mods

Mods listed in `catalog/mods.json` are the work of their authors. The manager shows each author and links to the original repository; licences are summarised in the [candidate list](docs/en/catalog/mods.md). No third-party mod package is bundled with the app. First-party gameplay mods under `mods/` (including `mods/roller-carnival/`) and the built-in loader bootstrap (`apps/desktop/src-tauri/assets/mpm_bootstrap.gd` and `apps/desktop/src-tauri/src/pck_loader.rs`) are authored in this repository under GPL-3.0-only.

## Cover images

| File | Source | Owner |
| --- | --- | --- |
| `catalog/covers/overtime.png` | [Overtime screenshot](https://github.com/DarkJadeStone/MachineParty-Overtime/blob/main/images/03_smoke_break_bench.png) | DarkJadeStone, MIT ([licence](https://github.com/DarkJadeStone/MachineParty-Overtime/blob/main/LICENSE)), showing game content owned by the game's developer |
| `catalog/covers/machineparty-plus.png` | [MachineParty+ banner](https://github.com/Ghostx10742/MachineParty-Plus/blob/main/assets/banner.png) | Ghostx10742, MIT |
| `catalog/covers/roller-carnival.png` | Self-captured preview screenshot from `mods/roller-carnival/` | Project contributors, GPL-3.0-only (rendered scene uses local game assets owned by the game's developer) |

## Software dependencies

The desktop app is built with [Tauri](https://tauri.app/) and Rust crates listed in `apps/desktop/src-tauri/Cargo.lock`, including `serde`, `serde_json`, `rfd`, `steamlocate` and `tauri-plugin-updater`. Each crate is distributed under its own licence, mostly MIT or Apache-2.0. The Windows build uses Microsoft WebView2.

The Overtime v1.7 conversion includes the author's MPML entry script, manifest and vanilla script fingerprint list under the [upstream MIT license](apps/desktop/src-tauri/assets/recipes/overtime/LICENSE). The gameplay payload comes from the verified CLI release. Binary1936 conversions include the [upstream v1.5 notice](apps/desktop/src-tauri/assets/recipes/binary1936/NOTICE.md).
