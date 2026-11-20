# Product requirements

**English** · [简体中文](../zh-CN/requirements.md) · [繁體中文](../zh-TW/requirements.md)

## Home and search

The home page shows the catalog the team has verified and published. Each entry shows its name, author, purpose, author project page, supported game version, installable version, local state and primary action. When upstream publishes a new release, only versions that pass team verification become installable.

- Search matches any part of a Simplified Chinese, Traditional Chinese or English mod title locally, ignoring case. Clearing the query restores the full catalog. With no results it shows "No matching mods".
- Order depends only on a fixed catalog sequence number. Searches, updates, renames and star counts keep relative order. Whether newest or oldest entries come first will be decided when the home page is final.
- The product has no filters, rankings or GitHub-wide search. Mod information comes from GitHub; the team decides inclusion, compatibility and installable versions.
- The app, search, install and uninstall are free. Mod details link to the author so players can read the original instructions.

## First launch

With exactly one valid Steam copy, actions are available immediately. Without one, players can still browse and the install location shows "Select game folder". With several copies, the candidate paths are offered. Settings show the current path, rescan and manual selection, and remember a valid manual choice.

## One-click management

| Player action or situation | Observable result |
| --- | --- |
| Click "Install" | The app downloads the selected version, verifies it, backs up and installs. Progress is shown; the installed version appears after verification succeeds. |
| Click "Uninstall" | The app removes the mod using its local record and verifies the result, keeping files needed by other mods, shared loaders and the player's own data. |
| Click "Switch" | The conflicting mod that will be replaced is named. The new package is prepared first, then the old mode is restored and the new one installed. The effective state is shown. |
| Game running or data mismatch | The player is asked to close the game and retry, or shown the incompatible version or unknown modification. Writes pause until identification completes. |
| Network loss or mod withdrawn | The cached catalog can be browsed and searched, and mods previously installed by the app can be uninstalled offline. A first offline launch says the catalog has not been downloaded yet. |

## First release acceptance

1. Steam on a non-system drive is detected; a manual choice survives restart and detection reruns only if that path becomes invalid.
2. Using only the app, a player installs verified Overtime, launches from Steam, sees the matching version and completes a round.
3. After one offline uninstall, the original PCK matches its pre-install SHA-256 and the unmodified game starts again.
4. Simulated download failure, interrupted writes and a Steam update all show the real state on next launch, and an old backup never overwrites a newer game.
5. Partial title matches still appear in catalog order. Opening an author page and installing are separate actions.
6. Players in mainland China with no proxy, no app cache and no GitHub access obtain the catalog from the production Worker. Previously synced players can search the cache offline; a first offline launch offers retry and access to local installations. Catalog and package downloads are verified separately following the [three-carrier acceptance plan](catalog/delivery.md).
