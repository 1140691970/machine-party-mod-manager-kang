# ADR-007: Mod adapters and macOS simulation

**English** · [简体中文](../../zh-CN/architecture/ADR-007-mod-adapters.md) · [繁體中文](../../zh-TW/architecture/ADR-007-mod-adapters.md)

Date: 2026-11-18. Status: proposed; to be finalised with [ADR-005](ADR-005-install-transactions.md) after Overtime acceptance on Windows (P2).

## Problem

Upstream mod packages are distributed as unmodified original archives that install through different mechanisms:

1. Overtime v1.7: a `.NET` console executable (`overtime_install.exe` with `overtime_payload.zip`) that appends patched scripts to `Machine Party.pck`, rewrites its index, and writes a few-KB delta restore record (`overtime_restore.dat`).
2. Binary1936 eight-player v1.5: a Python patcher (`install.py`, bundled with `python/python.exe` for Windows) that rebuilds `Machine Party.pck` without keeping any backup.
3. Broadcast 8P Freecam v0.91: a PowerShell patcher (`patcher.ps1`) that rebuilds `Machine Party.pck` and creates a full-file backup (`Machine Party.pck.broadcast_backup`).
4. MachineParty+ v2.1.0: a loader mod archive (`mod.json`, `main.gd`, scripts and translations) placed into MPML's `mods/` directory.

Hard-coding imperative Rust install flows for every mod makes onboarding new mods expensive. Conversely, executing arbitrary adapter scripts fetched from the online catalog would introduce a remote code execution risk and violate [ADR-005](ADR-005-install-transactions.md). Furthermore, Machine Party on Steam is Windows-only, so development on macOS needs structured simulation tiers before physical Windows verification.

## Proposed decision

### 1. Transaction engine, built-in adapter factory and declarative profiles

Keep `catalog/mods.json` as the single catalog source ([ADR-002](ADR-002-catalog-source.md)) by adding an optional declarative `adapter` object to each installable mod entry. Profiles are pure data, never executable scripts.

A Tauri-free Rust transaction engine owns all cross-mod safety guarantees:

- **Game layout resolution**: maps the saved Steam game root (used as the key in `installations.json`, such as `.../party project`) to the inner directory that actually holds `Machine Party.pck` (such as `Machine Party_Windows`).
- **Process and file locks**: confirms the game is not running and acquires an exclusive file lock before any write.
- **Staging and integrity**: downloads packages in Rust from the existing Worker origin (`https://machineparty.ailaogong.men/v1/downloads/{id}/{version}/{assetId}`) into staging, verifies outer ZIP byte size and SHA-256 against the catalog entry, extracts without modifying upstream files, and checks inner manifests (`SHA256SUMS.txt` and/or preflight command).
- **Pre-install checks and journaling**: computes baseline `size` and `sha256` fingerprints for `Machine Party.pck` and declared `touches` files, enforces mutual exclusion across `exclusive` groups (all direct PCK patchers share `"exclusive": "pck"` and conflict with MPML), writes a `pending` transaction journal, performs post-write read-back verification (also checking that no undeclared files in the game directory changed), commits `committed` / `rolled_back`, and reconciles state on startup.

The adapter factory dispatches on built-in Rust adapter kinds:

- `upstream-cli`: runs an allowlisted interpreter (`exe`, `bundled-python`, `powershell`) against a relative binary or script inside the verified package directory, using fixed action argument lists (`preflight`, `status`, `install`, `uninstall`), engine-supplied placeholders only (`{gameDir}`), closed `stdin`, non-interactive flags (such as `--no-pause`), a forbidden-argument guard (`--force` is always rejected), and regex/exit-code matchers for `installed`, `vanilla` and `older` states.
- `loader-files` (for P3): copies and removes declared mod files inside a loader directory such as MPML `mods/<id>`.

Onboarding a future mod that fits an existing adapter kind requires only a declarative `adapter` profile in `catalog/mods.json` and physical acceptance; introducing a new adapter kind requires Rust implementation and an ADR.

```json
"adapter": {
  "kind": "upstream-cli",
  "platforms": ["windows"],
  "target": "pckDir",
  "touches": ["Machine Party.pck", "overtime_restore.dat"],
  "exclusive": "pck",
  "baseline": {"file": "Machine Party.pck", "size": 634798100, "sha256": "326cc3988d3ac554d1f288bed89b1f89d450f78ec9d4470f88558975753dfa8e"},
  "verifyFiles": "SHA256SUMS.txt",
  "run": {"interpreter": "exe", "program": "overtime_install.exe", "common": ["--game", "{gameDir}", "--lang", "en", "--no-pause"]},
  "actions": {"preflight": ["--verify-package"], "status": ["--status"], "install": [], "uninstall": ["--uninstall"]},
  "status": {"installed": "^State:\\s+Overtime overtime-1\\.7 installed", "vanilla": "^State:\\s+vanilla", "older": "^State:\\s+Overtime .* installed \\(this program"},
  "forbiddenArgs": ["--force"]
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

Passing L1, L2 and L3 verification on macOS, followed by physical Windows Steam v2.1.2 acceptance (P2): install Overtime v1.7, launch from Steam and finish a round, then disconnect from the network, uninstall once and verify the restored `Machine Party.pck` matches the vanilla SHA-256, as listed in the [requirements](../requirements.md) and [development guide](../development/README.md).
