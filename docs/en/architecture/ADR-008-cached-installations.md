# ADR-008 · Cached downloads, startup checks and verified restoration

**English** · [简体中文](../../zh-CN/architecture/ADR-008-cached-installations.md) · [繁體中文](../../zh-TW/architecture/ADR-008-cached-installations.md)

On restart a saved installation can briefly appear absent while the manager hashes the PCK. A leftover delta file can also resemble a manual install. Each catalog release now has an independent package cache. Rust resolves pinned release inputs, verifies the ZIP before use and checks the selected copy again before writing.

The manager initially displays its saved records. Metadata of the relevant files determines whether a previous observation can be reused for display. A changed copy or a forced check triggers one complete PCK fingerprint pass. A manual candidate needs the matching package for a read-only upstream status check. Adoption also requires a successful trial restore in disposable storage. A pristine PCK with an unexpected restore file is reported as residue.

New installations keep a verified full backup. A successful uninstall requires the original PCK hash and the expected absence of created sidecars. Reconciliation at startup does not delete backups. Download cache removal preserves the per-copy backups. Existing install records, chosen paths and legacy delta transactions remain readable. Hashing the full PCK on every startup would add unnecessary disk I/O; metadata alone would be insufficient before writes.

Rust fixtures cover a warm restart, forced check, residue, modified copies and interrupted operations. The Windows prerelease still requires a Steam gameplay and offline restore test on a player’s copy.
