# ADR-007: Mod adapters and macOS simulation

**English** · [简体中文](../../zh-CN/architecture/ADR-007-mod-adapters.md) · [繁體中文](../../zh-TW/architecture/ADR-007-mod-adapters.md)

Date: 2026-11-18 (updated 2026-11-19). Status: proposed; both `upstream-cli` (`exe`, `bundled-python`, `powershell`) and `loader-files` (verified Worker/R2 ZIP packages with optional `autoLoader` PCK loader setup) are implemented in `installer.rs` and configured in `catalog/mods.json` for all five `v2.1.2` Windows preview mods (`Overtime`, `MachineParty+`, `Broadcast 8P Freecam`, `Binary1936 eight-player mod`, and `Roller Carnival`), awaiting full physical Windows acceptance ([ADR-005](ADR-005-install-transactions.md)).

## Problem

Upstream mod packages are distributed as unmodified original archives that install through different mechanisms:

1. Overtime v1.7 (MPML package `Machine-Party-Overtime-1.7-MPML.zip`): an MPML API v2 loader package (`mod.json`, `main.gd`, `vanilla_md5.json`, `overtime_overlay.zip`) extracted to `mods/overtime/`, enabling coexistence with other loader mods (`MachineParty+`, `Roller Carnival`) via the built-in `autoLoader` (`autoload/ModLoader` running `_discover_and_init_mods()` in `_init()` before game singletons load).
2. Binary1936 eight-player v1.5: a Python patcher (`install.py`, bundled with `python/python.exe` for Windows) that rebuilds `Machine Party.pck` without keeping any backup.
3. Broadcast 8P Freecam v0.91: a PowerShell patcher (`patcher.ps1`) that rebuilds `Machine Party.pck` and creates a full-file backup (`Machine Party.pck.broadcast_backup`).
4. MachineParty+ v2.1.0 & Roller Carnival v0.1.0: loader mod archives placed into `mods/<id>/` and powered by `autoLoader: true`.

Hard-coding imperative Rust install flows for every mod makes onboarding new mods expensive. Conversely, executing arbitrary adapter scripts fetched from the online catalog would introduce a remote code execution risk and violate [ADR-005](ADR-005-install-transactions.md). Furthermore, Machine Party on Steam is Windows-only, so development on macOS needs structured simulation tiers before physical Windows verification.

## Proposed decision

### 1. Transaction engine, built-in adapter factory and declarative profiles

Keep `catalog/mods.json` as the single catalog source ([ADR-002](ADR-002-catalog-source.md)) by adding an optional declarative `adapter` object to each installable mod entry. Profiles are pure data, never executable scripts.

A Tauri-free Rust transaction engine owns all cross-mod safety guarantees:

- **Game layout resolution**: maps the saved Steam game root (used as the key in `installations.json`, such as `.../party project`) to the inner directory that actually holds `Machine Party.pck` (such as `Machine Party_Windows`).
- **Process and file locks**: confirms the game is not running and acquires an exclusive file lock before any write.
- **Staging and integrity**: downloads packages in Rust from the existing Worker origin (`https://machineparty.ailaogong.men/v1/downloads/{id}/{version}/{assetId}`) into staging, verifies outer ZIP byte size and SHA-256 against the catalog entry, extracts without modifying upstream files, and checks inner manifests (`SHA256SUMS.txt` and/or preflight command).
- **Pre-install checks, conflict isolation and one-click switching**: computes baseline `size` and `sha256` fingerprints for `Machine Party.pck` and declared `touches` files; enforces mutual exclusion across `exclusive` groups (`loader` mods coexist with one another under `mods/<id>/`, while direct PCK patchers share `"exclusive": "pck"` and conflict with both other `pck` patchers and loader mode); distinguishes manager-owned `modConflict` (eligible for one-click `switch_from_zip`, which stages the target package first, uninstalls conflicting manager-installed mods, verifies vanilla PCK restoration, and installs the target mod) from `loaderConflict` (external `MachinePartyModLoader.exe` or unmanaged folders in `mods/`); writes a `pending` transaction journal, performs post-write read-back verification (also checking that no undeclared files in the game directory changed), commits `committed` / `rolled_back`, and reconciles state on startup.

The adapter factory dispatches on built-in Rust adapter kinds:

- `upstream-cli`: runs an allowlisted interpreter (`exe`, `bundled-python`, `powershell`) against a relative binary or script inside the verified package directory, using fixed action argument lists (`preflight`, `status`, `install`, `uninstall`), engine-supplied placeholders only (`{gameDir}`), `SystemRunner` writing a single `y\n` confirmation line then closing `stdin` (satisfying single directory-confirmation prompts such as Binary1936 `install.py` without `--force`, while EOF aborts unexpected prompts), non-interactive flags (such as `--no-pause`), a forbidden-argument guard (`--force` is always rejected), regex/exit-code matchers (`run_status_cmd` evaluates `installed`/`vanilla`/`older` regexes before rejecting non-zero exit codes such as `install.py --verify` returning `1` on `NOT PATCHED`), and cleanup of declared `touches` sidecars (such as `Machine Party.pck.broadcast_backup`) on full-backup uninstall.
- `loader-files`: normalizes optional single-subfolder archive layouts (such as `overtime/` inside `Machine-Party-Overtime-1.7-MPML.zip`), copies declared mod files from a verified Worker/R2 ZIP package into `mods/<id>`, records per-file SHA-256 `owned_files` fingerprints in the transaction record, refuses uninstallation if files were tampered with, preserves sibling mod folders under `mods/`, and enforces mutual exclusion against `pck` patchers and external MPML markers. When `autoLoader: true` is set, `pck_loader.rs` (`ensure_loader_installed` / `restore_managed_loader`) backs up the vanilla PCK under `_mpm_loader`, patches `res://project.binary` and embeds `assets/mpm_bootstrap.gd` (upgrading older manager-owned bootstraps seamlessly and recording state in `Machine Party.pck.modloader.json`), and automatically restores the vanilla PCK on uninstall once no other managed loader mods remain. Because `autoLoader` alters `project.binary` and the GDPC index (breaking PCK patcher vanilla SHA-256 checks) while direct PCK patchers alter `.gdc` hashes and rebuild `Machine Party.pck` (breaking MPML `vanilla_md5.json` checks and stripping `autoload/ModLoader`), the two loading modes remain strictly mutually exclusive and are bridged by one-click switching.

Onboarding a future mod that fits an existing adapter kind requires only a declarative `adapter` profile in `catalog/mods.json` and physical acceptance; introducing a new adapter kind requires Rust implementation and an ADR.

```json
"adapter": {
  "kind": "loader-files",
  "platforms": ["windows"],
  "target": "pckDir",
  "touches": ["mods"],
  "exclusive": "loader",
  "autoLoader": true,
  "baseline": {"file": "Machine Party.pck", "size": 634798100, "sha256": "326cc3988d3ac554d1f288bed89b1f89d450f78ec9d4470f88558975753dfa8e"},
  "requiredFiles": ["BUILDINFO.json", "main.gd", "mod.json", "overtime_overlay.zip", "vanilla_md5.json"],
  "upstreamUninstall": false
}
```

### 2. Tiered app-managed backup strategy

Backups cannot be left solely to upstream tools because backup behaviour differs across mods and some upstream installers retain no backup.

- Always compute and record the pre-install `Machine Party.pck` byte size and SHA-256 before modifying game files.
- **Delta-capable installers** (such as Overtime, which writes `overtime_restore.dat` with original length, baseline SHA-256 and original/patched index records): mirror `overtime_restore.dat` and the verified uninstall executable (`overtime_install.exe`) into the app's per-copy storage so offline uninstallation succeeds even if staging or the game-directory record is missing.
- **Non-delta installers or fallback** (`"upstreamUninstall": false`, such as Binary1936 `install.py`): store a verified full `Machine Party.pck` backup (~605 MB) in per-copy storage before patching and restore it directly on uninstall.
- **Pre-existing manual installs**: when `status` reports an installed mod without a matching `installations.json` record, surface it clearly in the UI; allow adoption or uninstallation only if the restore record's baseline SHA-256 matches the verified vanilla PCK fingerprint (`326cc3988d3ac554d1f288bed89b1f89d450f78ec9d4470f88558975753dfa8e` for v2.1.2). Unverified backups are never treated as vanilla.

### 3. Windows game target and three-tier macOS simulation

Machine Party (Steam App ID 4108000) is a Windows-only Steam release; playing the game on macOS is out of scope. On macOS, the desktop client supports browsing, catalog verification and development simulation, while normal Windows mod installation stays disabled in production UI.

Development verification on macOS proceeds in three simulation tiers before physical Windows acceptance (P2):

- **L1 (Unit and contract tests)**: `FakeRunner` + synthetic Godot PCK generator (a few KB with valid `GDPC` magic, header and `res://` directory index) + fault injection (interrupted download, mid-write process crash, Steam update replacing the PCK, unknown third-party modification, locked or running game).
- **L2 (Real subprocess tests)**: `ProcessRunner` executing a cross-platform fake CLI script matching Overtime's exact flags and `State:` output, plus running real cross-platform upstream scripts (Binary1936 `install.py` under `python3`) against synthetic PCKs.
- **L3 (Local vanilla PCK + Mono verification)**: local-only developer verification on macOS using an uncommitted copy of the Windows vanilla `Machine Party.pck` (v2.1.2, `634,798,100` bytes, SHA-256 `326cc3988d3ac554d1f288bed89b1f89d450f78ec9d4470f88558975753dfa8e`) and Mono to run the real `overtime_install.exe` through `--verify-package`, `--status`, install, post-install `--status`, `--uninstall` and byte-for-byte SHA-256 restoration check.

## Alternatives

- **Executable per-mod scripts in the online catalog**: rejected due to remote code execution risk and violation of [ADR-005](ADR-005-install-transactions.md).
- **Rewriting every PCK patcher in Rust**: rejected because it duplicates upstream logic and breaks whenever upstream payload formats change.
- **Separate `catalog/adapters/*.json` files**: rejected to avoid splitting the single catalog source ([ADR-002](ADR-002-catalog-source.md)) prematurely; can be generated later if per-mod files are introduced.
- **Always copying the 605 MB PCK for every mod**: rejected as the primary Overtime path because verified delta restore takes a few KB and verifies the full vanilla SHA-256, while full-PCK backup stays mandatory for non-delta installers.

## Compatibility

- `catalog/mods.json` stays `schema: 1`; the optional `adapter` field is additive and ignored by older clients.
- `installations.json`, `game-path.json`, existing Tauri command names and updater configuration ([ADR-003](ADR-003-desktop-updates.md)) remain unchanged.

## Evidence needed

On macOS, L1/L2/L3 unit and integration tests cover all four mod adapters (`loader-files`, `powershell`, `bundled-python`, and L3 real Overtime v1.7 via Mono on the uncommitted Windows v2.1.2 `Machine Party.pck` with byte-for-byte restoration), alongside local verification of `binary1936-8p/install.py` and `broadcast-8p-freecam` overlay paths against the vanilla v2.1.2 PCK. Full physical Windows Steam v2.1.2 acceptance remains required: install each mod on Windows, launch from Steam, verify in-game behaviour (including PowerShell `patcher.ps1`, bundled Windows `python.exe` + `install.py`, and MPML + `MachineParty+`), then disconnect from the network, uninstall once, and verify the restored game copy matches the vanilla baseline as listed in [requirements](../requirements.md) and the [development guide](../development/README.md).
