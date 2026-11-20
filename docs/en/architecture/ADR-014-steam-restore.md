# ADR-014 · Steam verification before managed mod cleanup

**English** · [简体中文](../../zh-CN/architecture/ADR-014-steam-restore.md) · [繁體中文](../../zh-TW/architecture/ADR-014-steam-restore.md)

Steam opens verification asynchronously. A window focus event or an already installed game cannot establish that this request succeeded.

The manager resolves the selected copy against Steam’s library registration, obtains consent to close the game, and backs up the affected files and ownership records. While holding the inventory lock it watches new content log entries for this app’s validation start, verification phase, fully installed state and successful scheduler result. Cancellation, unreadable or rotated logs and timeout end the wait. If Steam changes its log format, the manager keeps the mods.

Before cleanup, the manager rechecks the target directory, game process, supported vanilla PCK fingerprint and managed file fingerprints. It removes recorded files and its own inactive loader marker, keeping manual mods and external loaders. Existing transaction and inventory formats remain compatible. Tests use synthetic Steam events, a patched game copy and managed and manual mods. Live Steam verification on Windows remains pending.

A per-directory cleanup journal is written after verification and before deleting files. Scans and mod operations resume only the recorded cleanup after checking the vanilla fingerprint and remaining ownership records. Directory identity selects the physical copy across path aliases, while inventory changes use the original installation keys.
