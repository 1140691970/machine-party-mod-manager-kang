# ADR-004: Documentation organised by language

**English** · [简体中文](../../zh-CN/architecture/ADR-004-language-documentation.md) · [繁體中文](../../zh-TW/architecture/ADR-004-language-documentation.md)

Date: 2026-11-18. Status: accepted.

## Problem

Docs were written only in Traditional Chinese while the app defaults to Simplified Chinese, and some files (`ui-design.md`) accumulated superseding sections instead of being rewritten. Contributors outside Chinese-speaking regions had no entry point.

## Decision

- English is the canonical language for the root `README.md`, `AGENTS.md`, `CONTRIBUTING.md`, `SECURITY.md`, `SUPPORT.md`, `CHANGELOG.md` and `THIRD_PARTY_NOTICES.md`, which GitHub and packaging expect at the root.
- Guides live in `docs/en`, `docs/zh-CN` and `docs/zh-TW` with identical relative paths. Translated homepages live in `docs/readme`. Shared images live in `docs/images`.
- Every translated page starts with a language switcher. Documents describe current state; superseded content is rewritten rather than appended.
- `tests/contracts/documentation.test.mjs` checks matching paths, switchers and relative links.

## Alternatives

Keeping one language lowers maintenance but excludes part of the audience. Translating only the README leaves guides inaccessible.

## Compatibility

Old paths such as `docs/architecture.md` were removed and in-repo links were updated. The issue form for mod submissions stays in Traditional Chinese for now.

## Evidence

The documentation contract test passes.
