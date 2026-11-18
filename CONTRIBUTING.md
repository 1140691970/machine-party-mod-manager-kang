# Contributing to Machine Party Mod Manager

**English** · [简体中文](docs/zh-CN/CONTRIBUTING.md) · [繁體中文](docs/zh-TW/CONTRIBUTING.md)

Bug reports, Windows test results, mod recommendations, translations, documentation and code are welcome. This guide explains how to prepare changes that are easy to review.

## Before you start

- For usage questions read [SUPPORT.md](SUPPORT.md). Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).
- Search [existing issues](https://github.com/JamesGZM/machine-party-mod-manager/issues) first, then use a template.
- To recommend a mod or a new mod version, use the [mod submission form](https://github.com/JamesGZM/machine-party-mod-manager/issues/new?template=mod-submission.yml). You do not need to edit JSON.
- Open an issue before large features, new install methods or architecture changes. Small fixes and documentation corrections can go straight to a pull request.

Issues and pull requests are welcome in English, Simplified Chinese or Traditional Chinese.

## Development setup

Fork the repository, branch from `main` and follow the [development guide](docs/en/development/README.md) for prerequisites, layout and commands.

Keep each pull request focused on one problem. Avoid unrelated formatting, generated files or refactors. Add a regression test when fixing behaviour and update documentation in all three languages when users or contributors are affected.

## Engineering rules

The full rules are in [AGENTS.md](AGENTS.md). In short:

- Respect the boundaries in the [current architecture](docs/en/architecture/README.md): `main.rs` assembles, `commands.rs` validates, domain modules stay free of Tauri, and only `ui/bridge.js` reaches Tauri.
- Mods are added or changed only in `catalog/mods.json`, with text in all three languages.
- UI strings live in `apps/desktop/ui/languages.js` with all three languages updated together; keep keyboard access, progress and error feedback.
- Never write to a player's game files without a verified package, a fingerprinted backup and a way back. Leave unknown modifications and other mods' files untouched.
- Propose new network services, analytics or telemetry before adding them. Source, tests and diagnostics must not contain credentials, signing keys or personal data.

Significant ownership or contract decisions need a short ADR in `docs/en/architecture/` and its translations: problem, decision, alternatives, compatibility and evidence.

## Verification

Run the smallest relevant check while developing, and all of these before submitting:

```sh
npm run check:architecture
npm test
npm run lint:rust
npm run test:rust
```

Attach screenshots for UI changes. For install, uninstall or update behaviour, state the Windows version, Steam game version, mod version, what you did and what happened. If you could not test on real hardware, say so; a successful build does not prove the game was restored.

For documentation-only changes, check links, commands and consistency between languages, and say which checks you ran.

## Pull request contents

1. The user-visible problem and the resulting behaviour.
2. Key implementation decisions and trade-offs.
3. Automated tests, manual checks and conditions that remain unverified.
4. Related issues, compatibility and documentation changes.

Do not attach private logs, credentials, identifying screenshots or local backups. Build output, caches, editor indexes and `.agent` notes stay out of the repository. Maintainers may ask for changes or for a PR to be split. Merging does not mean an immediate release; see [Releasing](docs/en/development/releasing.md).

## Community conduct

Be respectful, give actionable feedback about the work and welcome people of every experience level. Harassment, discrimination, threats and publishing others' private information are not allowed. Maintainers may moderate or close disruptive discussions; violations of GitHub's terms can be reported with GitHub's tools.

## Licence and attribution

Contributions are licensed under the project's [GPL-3.0-only licence](LICENSE). Submit only content you have the right to contribute, keep copyright notices and record adapted third-party code in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). No contributor licence agreement is required.

Third-party mods remain the work of their authors under their own licences. Catalogue entries link to the author; this repository does not relicense or claim their work.
