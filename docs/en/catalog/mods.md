# Candidate mods and inclusion rules

**English** · [简体中文](../../zh-CN/catalog/mods.md) · [繁體中文](../../zh-TW/catalog/mods.md)

## Inclusion guide

**Current state**　The repository has a [submission form](../../../.github/ISSUE_TEMPLATE/mod-submission.yml) that appears under New issue once merged to the default branch. Release selection and R2 staging are manual. The catalog Worker publishes the reviewed snapshot.

[Online mod catalog](../architecture/ADR-006-online-catalog.md)

| Step | Who | What happens and what it produces |
| --- | --- | --- |
| 1. Submit | Anyone, including maintainers | Under Issues → New issue choose the mod submission form and give the author repository, release and purpose. A mod without a Release can still be a candidate. Submitters never edit Markdown or JSON. |
| 2. Triage and asset selection | Maintainer + automation | After a maintainer accepts the recommendation, automation lists the Release's asset names, sizes and sources and flags duplicates. The maintainer selects the files and loaders to integrate. For Overtime v1.7 the direct-patch path uses the CLI ZIP; the regular and MPML packages serve different purposes. |
| 3. Generate the draft | Automation | Download the selected assets to staging, compute SHA-256, record upstream tag, asset ID and length, and create or update a single draft PR. The only structured source today is `catalog/mods.json`; once the flow exists it may be split into one `catalog/mods/*.json` per mod that generates the same snapshot format. Mods without release files stay candidates. Automation only reads submitted data and packages and never executes submitted content. |
| 4. Verify for publishing | Maintainer | Record the licence and Windows tests using the checklist below, confirming game compatibility, install, uninstall and offline restore. Check each dependency. Add results to the draft; CI validates fields, hashes, dependencies and duplicate IDs. Without evidence the entry stays a candidate. |
| 5. Approve | Repository owner | After merging the draft, choose a specific main commit and approve the additions, updates and withdrawals in the production environment. Merging and production deployment are separate. |
| 6. Distribute and verify | Release automation | Re-verify originals against approved hashes, write storable packages to private R2 (identical hashes are reused), deploy the Worker catalog only once assets are readable, then check revision and downloads from the production entry. If upstream replaced a file or assets are incomplete, stop and keep the old catalog. Players see the new version on their next refresh. |

**Routine maintenance.** New versions keep the existing mod ID and catalog order and repeat selection and acceptance; the published version stays in effect until the new one passes. Withdrawals go through the same owner approval, removing catalog eligibility and the old download entry while keeping local uninstall. If verification fails after deployment, follow the [rollback process](delivery.md). The first release can collect submissions through the form before automatic PR generation is enabled; per-mod Markdown research is kept for background and does not take part in publishing.

## Game baseline

Machine Party (Steam App ID 4108000) officially supports 2–4 players, online co-op, shared/split screen and Remote Play Together. The game uses Godot; community mods either patch the PCK directly or load external mods through a community loader. Entry descriptions should separate the base game's multiplayer abilities, what the mod adds, and the install requirements for each multiplayer setup. [Steam store](https://store.steampowered.com/app/4108000/Machine_Party/) · [Developer announcements](https://steamcommunity.com/app/4108000/announcements/) · [MPML](https://github.com/Krunk-theduck/MachinePartyModLoader)

## Candidates

As of 2026-11-18 the following come from documentation and upstream code research and await team testing on real hardware. Download counts are historical snapshots of the named GitHub Release files, used to gauge demand.

| Candidate | Features and downloads | Integration and licence to-dos |
| --- | --- | --- |
| [Overtime](https://github.com/DarkJadeStone/MachineParty-Overtime) | Eight players online and locally. v1.7 regular package 2,855, CLI package 1,215 downloads. | Test Steam game v2.1.2 with the v1.7 CLI first. Confirm restore records and offline uninstall; direct patching and the MPML path are mutually exclusive. MIT covers only the author's original work. [Install docs](https://github.com/DarkJadeStone/MachineParty-Overtime/blob/main/docs/INSTALL.md) · [Licence](https://github.com/DarkJadeStone/MachineParty-Overtime/blob/main/LICENSE) |
| [MachineParty+](https://github.com/Ghostx10742/MachineParty-Plus) | Public lobbies, voice and text chat. v2.1.0 mod ZIP 1,917 downloads. | The mod is MIT; separately check the [MPML](https://github.com/Krunk-theduck/MachinePartyModLoader) version, first install flow and relaying licence. Test room codes and unmodded players joining; voice chat needs both sides installed. |
| [Binary1936 eight-player mod](https://github.com/Binary1936/machine-party-8p) | Eight players online. v1.5 mod ZIP 5,297 downloads. | Upstream relies on Steam verification to restore; test the app's own backup, restore and unknown-copy detection. The files covered by MIT follow the author's [NOTICE](https://github.com/Binary1936/machine-party-8p/blob/main/NOTICE.md). |
| [Broadcast 8P Freecam](https://github.com/Lnksoul/MachineParty_Broadcast8P_Freecam_Patcher) | One director and eight contestants with rotating teams and a free camera. Downloads unverified. | The script has install, verify and uninstall entries. Focus on existing backups; confirm per-file licensing before deciding on relaying. No explicit open-source licence is visible on the repository home page. [Patcher source](https://github.com/Lnksoul/MachineParty_Broadcast8P_Freecam_Patcher/blob/main/patcher.ps1) |

## Acceptance checklist (per version)

- Mod ID, author page, pinned release file, commit or tag, SHA-256, licence scope and the direct/relay decision.
- Test date, Windows and Steam game versions, original PCK fingerprint, mod and loader versions.
- Results for clean install, launch from Steam, feature check, recognition after restart, offline uninstall and restore verification.
- Supported multiplayer combinations, known conflicts, and results for game updates, download failure, interrupted install and recovery.
- Installable versions are published only after maintainer confirmation; withdrawn mods keep local uninstall for existing users. Only new mods get a catalog order number.
- At listing, attach the mainland three-carrier download records, tested asset hashes and final delivery path. If only browsing is possible, record the download restriction separately. See the [catalog delivery plan](delivery.md) for the method.
- Record the upstream Release, asset ID, file name, size and SHA-256 of the main package and every required loader, with the direct, relay or storage method each allows. Changed content under the same tag and file name is a new candidate; a failed hash check stops installation until it is re-verified and approved by the owner.
