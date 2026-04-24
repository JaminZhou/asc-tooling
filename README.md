# asc-tooling

Reusable App Store Connect automation tooling extracted from product repositories.

`asc_tooling` packages the repeatable parts of an App Store Connect release
workflow into small JWT-based CLI commands. It is intended for local automation
and product repositories that need a stable way to manage review, metadata,
screenshots, beta distribution, in-app purchases, and sales reports.

## What It Covers

- app review submission and release actions
- metadata inspection and updates
- screenshot inspection and upload
- TestFlight group and tester management
- in-app purchase readiness helpers
- app territory availability checks
- Sales and Trends report download plus unit summaries

## Commands

- `asc-review`
- `asc-metadata`
- `asc-beta`
- `asc-sales`
- `asc-screenshots`
- `asc-iap`
- `asc-availability`

Current implementation status:

- `asc-review`: implemented
- `asc-metadata`: implemented
- `asc-beta`: implemented
- `asc-sales`: implemented
- `asc-screenshots`: implemented
- `asc-iap`: implemented
- `asc-availability`: implemented

Product-specific assets such as screenshot renderers should stay in each app
repository.

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
  tag: "v0.5.1"
```

Then install and run through Bundler:

```bash
bundle install
bundle exec asc-review status --bundle-id com.example.app
bundle exec asc-review release --bundle-id com.example.app --app-version 1.2.0
```

If you prefer to work from a local checkout while iterating on the tool itself:

```bash
bundle install
./exe/asc-review status --bundle-id com.example.app
```

Example local usage from a checkout:

```bash
./exe/asc-review status --bundle-id com.example.app
./exe/asc-metadata status --bundle-id com.example.app --locale en-US
./exe/asc-beta status --bundle-id com.example.app
./exe/asc-sales units --bundle-id com.example.app --vendor-number 12345678 --report-date 2026-04-10
./exe/asc-screenshots status --bundle-id com.example.app --locale en-US --display-type APP_DESKTOP
./exe/asc-iap status --bundle-id com.example.app
./exe/asc-availability status --bundle-id com.example.app
```

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
Store Connect territory and reports any missing territory IDs.

For a fuller usage guide and the release flow, see
[docs/release-and-usage.md](docs/release-and-usage.md).

## Support boundaries

The formal, supported workflow in this repository is the JWT-based command set:

- `asc-review`
- `asc-metadata`
- `asc-beta`
- `asc-sales`
- `asc-screenshots`
- `asc-iap`
- `asc-availability`

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
