# ADR-013 · Installing native mods from the signed catalog

**English** · [简体中文](../../zh-CN/architecture/ADR-013-signed-native-installs.md) · [繁體中文](../../zh-TW/architecture/ADR-013-signed-native-installs.md)

A preview could display a newly published mod while requiring a new desktop build to install it. The manager now accepts new first-party IDs from the signed catalog when the author repository, ID-based inventory and native loader profile match the bundled rules. Only the package file list may vary within that profile. Preview builds accept preview releases; stable builds require verified releases. Converted packages keep their bundled conversion rules.

Fresh installs, upgrades and disk scans use the same authorized release. The first signed description of an online-only ID is retained and reverified for offline inspection and removal. Only the active approvals authorize installing that online package. Existing installation records and backups remain compatible.

Refresh the mod list in Mod catalog. A newer compatible release shows **Update to**; the confirmation shows both versions and includes release notes when the signed catalog supplies them for the target version and the player’s language. Cancel closes the dialog before any download. Catalog tests cover a new ID and rejected adapters. Transaction tests cover replacement and recovery.
