# ADR-010 · Independent install keys for mods sharing a repository

**English** · [简体中文](../../zh-CN/architecture/ADR-010-shared-repository-mods.md) · [繁體中文](../../zh-TW/architecture/ADR-010-shared-repository-mods.md)

Roller Carnival and Lobby Bots share one GitHub project. A repository alone cannot identify both installed versions. New entries may select their existing catalog ID as the install key with `inventoryById: true`. The author link still uses `repo`. A global ID migration would require rewriting player records. The full online catalog uses the existing endpoint with `?inventory=id`; clients using the original URL receive entries compatible with repository keys. Catalog contracts cover coexistence, legacy responses and separate cache validators.

Roller Carnival now uses its catalog ID for local installations. Its bundled `legacyInventoryRepos` lists the repository keys used by previews 5 and 6–8, newest first. When reading one game copy, the manager merges those keys into its ID. An existing ID takes precedence, and a verified transaction supplies the installed version. Uninstall verifies the recorded files and removes the keys for that copy. Older clients continue to read the original `inventoryById` flag from the Worker. Give each additional mod in this repository a unique catalog ID and set `inventoryById: true`.
