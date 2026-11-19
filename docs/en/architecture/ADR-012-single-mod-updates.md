# ADR-012 · Updating one installed mod

**English** · [简体中文](../../zh-CN/architecture/ADR-012-single-mod-updates.md) · [繁體中文](../../zh-TW/architecture/ADR-012-single-mod-updates.md)

Players can update a managed mod independently when its installed version is older than an approved release. Numeric version tags are compared component by component. The Rust backend identifies the game copy and the individual mod from its installation transaction.

The catalog deployment signs the exact UTF-8 catalog bytes prefixed with `machine-party-mod-catalog-v1\n` using the release signing key. Only the complete catalog carries that signature. For known native MPML mods, the manager checks the signature, mod ID, author repository, embedded adapter profile, package size and SHA-256. A stable client requires a verified release. A Windows preview can also accept an explicitly designated preview mod. The existing bundled package can still be used under its original approval. A new version of a converted mod requires a matching conversion rule shipped in the manager.

An uninstall followed by an install could remove the shared loader or leave the old mod unavailable after a failed download. A single update instead stages the verified replacement on the game volume, checks the existing files, records both sets of fingerprints, and renames only the chosen mod directory. The saved transaction is the commit point. Recovery restores the old directory before that point and retains the verified new directory after it. If unknown changes or a running game prevent recovery, the manager retains the recovery record for the next scan.

The release-fixture test upgrades Roller Carnival v0.1.0 to v0.1.1 beside Lobby Bots v0.1.4 on a synthetic game copy. It checks rollback and restart recovery, sibling files and records, the shared loader and PCK fingerprints, and offline uninstall. Windows Steam gameplay acceptance is pending.

[ADR-013 · Installing native mods from the signed catalog](ADR-013-signed-native-installs.md)
