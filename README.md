# asc-tooling

[![CI](https://github.com/JaminZhou/asc-tooling/actions/workflows/ci.yml/badge.svg)](https://github.com/JaminZhou/asc-tooling/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/JaminZhou/asc-tooling?sort=semver)](https://github.com/JaminZhou/asc-tooling/releases)
[![Ruby](https://img.shields.io/badge/ruby-3.1--3.3-red.svg)](.github/workflows/ci.yml)
[![Status](https://img.shields.io/badge/status-production%20local%20tooling-2563eb.svg)](CHANGELOG.md)
[![Agent Skill](https://img.shields.io/badge/Agent%20skill-Codex%20%2F%20Claude-111827.svg)](skills/asc-tooling/SKILL.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Language: English | [中文](README.zh.md)

Reusable App Store Connect automation tooling extracted from product repositories.

`asc_tooling` packages the repeatable parts of an App Store Connect release
workflow into a unified CLI, focused subcommands, and a bundled Agent/Codex/
Claude skill. It is intended for local automation and product repositories that
need a stable way to manage review, metadata, store setup, screenshots, beta
distribution, in-app purchases, app versions, availability, and sales reports.

> Important boundary: this is an independent project, not an official Apple
> tool. It uses App Store Connect API credentials supplied by the caller,
> performs explicit App Store Connect actions only through named CLI commands,
> and must never store `.p8` keys, browser cookies, product secrets, or
> app-specific release state in this repository.

## What It Covers

- app review submission and release actions
- app version creation
- metadata inspection and updates
- store setup checks and updates for categories, age ratings, release type, and
  App Review details
- screenshot inspection and upload
- TestFlight group and tester management
- in-app purchase readiness helpers
- app territory availability checks and global new-territory enablement
- Sales and Trends report download plus unit summaries

## Commands

- `asc-tooling`
- `asc-review`
- `asc-metadata`
- `asc-beta`
- `asc-sales`
- `asc-screenshots`
- `asc-iap`
- `asc-version`
- `asc-availability`
- `asc-store-setup`

Current implementation status:

- `asc-tooling`: implemented as the unified CLI and skill installer
- `asc-review`: implemented
- `asc-metadata`: implemented
- `asc-beta`: implemented
- `asc-sales`: implemented
- `asc-screenshots`: implemented
- `asc-iap`: implemented
- `asc-version`: implemented
- `asc-availability`: implemented
- `asc-store-setup`: implemented

Product-specific assets such as screenshot renderers should stay in each app
repository.

Potential future API areas are tracked in
[docs/api-gap-matrix.md](docs/api-gap-matrix.md). That matrix is a discovery
backlog, not a commitment to wrap the full App Store Connect API.

## Requirements

Set these environment variables before running any command:

- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `ASC_KEY_PATH`

For `asc-sales`, also set:

- `ASC_VENDOR_NUMBER`

## Installation

`asc_tooling` is currently distributed through GitHub tags rather than
RubyGems.

Install it from the public repository in a product `Gemfile`:

```ruby
gem "asc_tooling",
  git: "https://github.com/JaminZhou/asc-tooling.git",
  tag: "v0.9.3"
```

Then install and run through Bundler:

```bash
bundle install
bundle exec asc-tooling commands
bundle exec asc-tooling review status --bundle-id com.example.app
bundle exec asc-review status --bundle-id com.example.app
bundle exec asc-review release --bundle-id com.example.app --app-version 1.2.0
bundle exec asc-review withdraw --bundle-id com.example.app --app-version 1.2.0
```

If you prefer to work from a local checkout while iterating on the tool itself:

```bash
bundle install
./exe/asc-tooling commands
./exe/asc-review status --bundle-id com.example.app
```

## Unified CLI And Skill

`asc-tooling` is the preferred entrypoint for new automation. It delegates to
the existing command implementations while giving agents and humans one stable
surface to discover commands and install the bundled skill.
The commands in this section require `v0.9.0` or newer.

```bash
bundle exec asc-tooling commands
bundle exec asc-tooling --version
bundle exec asc-tooling review status --bundle-id com.example.app
bundle exec asc-tooling version create --bundle-id com.example.app --version 1.2.0 --platform ios --dry-run
bundle exec asc-tooling availability status --bundle-id com.example.app
```

Install the bundled skill for Codex-compatible agents or Claude:

```bash
bundle exec asc-tooling init --client codex --force    # $CODEX_HOME/skills, or ~/.codex/skills
bundle exec asc-tooling init --client agents --force   # ~/.agents/skills
bundle exec asc-tooling init --client claude --force   # $CLAUDE_CONFIG_DIR/skills, or ~/.claude/skills
bundle exec asc-tooling init --print
```

Use `--client codex` for Codex-native installs that follow Codex's own
`CODEX_HOME` convention. Use `--client agents` for the open Agent Skills user
folder shared by compatible agents. Use `--client claude` for Claude Code
installs that follow `CLAUDE_CONFIG_DIR` when it is set.

The legacy executable names remain supported for existing scripts:

```bash
./exe/asc-review status --bundle-id com.example.app
./exe/asc-review withdraw --bundle-id com.example.app --app-version 1.2.0 --dry-run
./exe/asc-metadata status --bundle-id com.example.app --locale en-US
./exe/asc-beta status --bundle-id com.example.app
./exe/asc-sales units --bundle-id com.example.app --vendor-number 12345678 --report-date 2026-04-10
./exe/asc-screenshots status --bundle-id com.example.app --locale en-US --display-type APP_DESKTOP
./exe/asc-iap status --bundle-id com.example.app
./exe/asc-version create --bundle-id com.example.app --version 1.2.0 --platform ios --dry-run
./exe/asc-availability status --bundle-id com.example.app
./exe/asc-availability apply --bundle-id com.example.app --all-territories --available-in-new-territories --dry-run
./exe/asc-store-setup status --bundle-id com.example.app --app-version 1.0.0 --platform ios
```

`asc-metadata status` and `asc-screenshots status` can read a specific editable
or released version with `--app-version`. Their mutating counterparts,
`asc-metadata apply` and `asc-screenshots upload`, continue to require an
editable App Store version.

`asc-sales` wraps the App Store Connect Sales and Trends report download endpoint.
The `units` command fetches a Summary Sales Report and aggregates app download,
redownload, and update units for the app's Apple identifier. `report` downloads
and prints or saves the raw TSV report.

`asc-iap` currently covers IAP status, review screenshot upload, availability
sync, and submission attempts. If Apple returns
`FIRST_IAP_MUST_BE_SUBMITTED_ON_VERSION`, the app's first IAP still needs to be
attached to the app version in the App Store Connect web UI before that version
is submitted.

`asc-availability` checks whether the app is available in every current App
Store Connect territory, reports any missing territory IDs, and can create app
availability for all current territories through the App Store Connect API.

`asc-store-setup` checks and optionally applies repeatable App Store Connect
store setup fields such as release type, categories, age rating templates,
free app pricing, and App Review details. App Privacy remains a web
confirmation item.

For a fuller usage guide and the release flow, see
[docs/release-and-usage.md](docs/release-and-usage.md).

## Support boundaries

The formal, supported workflow in this repository is the JWT-based command set:

- `asc-tooling`
- `asc-review`
- `asc-metadata`
- `asc-beta`
- `asc-sales`
- `asc-screenshots`
- `asc-iap`
- `asc-version`
- `asc-availability`
- `asc-store-setup`

These commands are the part of `asc_tooling` intended for repeatable local
workflows and CI-friendly automation.

## Experimental local helper

There is also an unsupported, local-only Resolution Center helper for fetching
reviewer messages through an existing browser session:

- [docs/browser-resolution-center.md](docs/browser-resolution-center.md)

This helper is intentionally separate from the formal JWT-based release
workflow:

- it requires an existing local App Store Connect browser login
- it reads cookies from a local Chrome profile
- it should not be used in CI, automation, or shared release scripts
- any exported cookie JSON should stay outside the repository and be deleted
  immediately after use

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the current contribution workflow.
Release history is tracked in [CHANGELOG.md](CHANGELOG.md).
