---
name: asc-tooling
description: Use asc_tooling for App Store Connect release automation through explicit local CLI commands. Trigger when the user asks about App Store Connect review submission, metadata, screenshots, TestFlight beta, in-app purchases, app version creation, territory availability, store setup, Sales and Trends reports, or reusable ASC release workflows. Keep product-specific assets and secrets outside this repository.
---

# asc-tooling

Use this skill when working with `asc_tooling`, the reusable App Store Connect CLI toolkit.

## Safety Rules

- Never ask the user to paste `.p8` key contents, JWTs, cookies, App Store Connect account data, or unpublished product secrets.
- Keep product-specific screenshot generation, review notes, metadata files, and release state in the consuming product repository.
- Treat `experimental/` browser-session helpers as local-only and unsupported; do not use them in CI or shared release scripts.
- Mutating commands must be explicit. Prefer `--dry-run` before actions that create or update App Store Connect state.
- If Apple API behavior is uncertain, report what was verified and what still needs manual App Store Connect confirmation.

## CLI Entrypoints

Prefer the unified CLI when available:

```bash
asc-tooling commands
asc-tooling review status --bundle-id com.example.app
asc-tooling review status --bundle-id com.example.app --app-version 1.2.0 --items
asc-tooling review attach-build --bundle-id com.example.app --app-version 1.2.0 --build-number 2026082501 --dry-run
asc-tooling metadata status --bundle-id com.example.app --app-version 1.2.0 --locale en-US
asc-tooling beta status --bundle-id com.example.app
asc-tooling sales units --bundle-id com.example.app --vendor-number 12345678 --report-date 2026-04-10
asc-tooling screenshots status --bundle-id com.example.app --app-version 1.2.0 --locale en-US --display-type APP_DESKTOP
asc-tooling iap status --bundle-id com.example.app
asc-tooling version create --bundle-id com.example.app --version 1.2.0 --platform ios --dry-run
asc-tooling availability status --bundle-id com.example.app
asc-tooling store-setup status --bundle-id com.example.app --app-version 1.0.0 --platform ios
```

Metadata and screenshot status commands may read an explicitly selected
editable or released App Store version. Metadata apply and screenshot upload
must continue to target editable versions only.

Review build attachment requires an explicit App Store version, only accepts a
`VALID`, `APP_STORE_ELIGIBLE` build, and verifies the relationship after a real
mutation. Use review status with `--items` when the exact App and IAP version
items in a review submission need to be confirmed.

IAP status reports when Apple's first-IAP exception requires the App Store
Connect web UI. IAP submit must run that preflight before any submission
mutation and must not represent the browser-only joint submission as complete.

The legacy executable names remain supported:

- `asc-review`
- `asc-metadata`
- `asc-beta`
- `asc-sales`
- `asc-screenshots`
- `asc-iap`
- `asc-version`
- `asc-availability`
- `asc-store-setup`

## Environment

Most commands require App Store Connect API credentials:

```bash
export ASC_KEY_ID=...
export ASC_ISSUER_ID=...
export ASC_KEY_PATH=~/.config/appstoreconnect/AuthKey_XXXX.p8
```

`asc-sales` also needs `ASC_VENDOR_NUMBER` unless passed as `--vendor-number`.

## Workflow

1. Identify the product repository and command surface: review, metadata, beta, sales, screenshots, IAP, version, availability, or store setup.
2. Read product-local release docs or scripts first; keep product-specific values there.
3. Use status or dry-run commands before mutating commands.
4. Summarize the command run, inputs used, source of truth, and any App Store Connect web UI confirmation still required.
5. Never save secrets or browser session exports into the repository.

## Skill Installation

Install or update this skill through the bundled CLI:

```bash
asc-tooling init --client codex --force
asc-tooling init --client agents --force
asc-tooling init --client claude --force
asc-tooling init --print
```

`--client codex` installs under `$CODEX_HOME/skills` or `~/.codex/skills`.
`--client agents` installs under the open Agent Skills user folder,
`~/.agents/skills`.
`--client claude` installs under `$CLAUDE_CONFIG_DIR/skills` or
`~/.claude/skills`.
