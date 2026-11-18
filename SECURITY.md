# Security policy

**English** · [简体中文](docs/zh-CN/SECURITY.md) · [繁體中文](docs/zh-TW/SECURITY.md)

## Supported versions

Only the latest release on the stable update channel receives security fixes. Installed clients update themselves from Settings or the startup prompt.

## Reporting a vulnerability

Please do not open a public issue for security problems. Report them privately through [GitHub security advisories](https://github.com/JamesGZM/machine-party-mod-manager/security/advisories/new).

Include the affected version and platform, the steps to reproduce, the impact you observed and any suggested fix. Do not include real credentials or other players' data. You will receive an acknowledgement as soon as the maintainer can review it; please allow time for a fix and a signed release before disclosing publicly.

## Scope

In scope:

- The desktop app, including IPC commands, file handling in game folders and configuration files, and the signed update path.
- The update Worker in `services/update-worker` and the release workflows.
- Anything that could make the app install an unsigned build or an unverified mod package, write outside the selected game copy, or open arbitrary URLs.

Out of scope: vulnerabilities in the game itself or in third-party mods, which should be reported to their authors, and issues that require an already compromised machine.
