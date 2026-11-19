# ADR-010 · Independent install keys for mods sharing a repository

**English** · [简体中文](../../zh-CN/architecture/ADR-010-shared-repository-mods.md) · [繁體中文](../../zh-TW/architecture/ADR-010-shared-repository-mods.md)

Roller Carnival and Lobby Bots share one GitHub project. A repository alone cannot identify both installed versions. New entries may select their existing catalog ID as the install key with `inventoryById: true`. The author link still uses `repo`. Existing records retain their original keys. A global ID migration would require rewriting player records. The full online catalog uses the existing endpoint with `?inventory=id`; clients using the original URL receive entries compatible with repository keys. Catalog contracts cover coexistence, legacy responses and separate cache validators.
