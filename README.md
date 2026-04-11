# asc-tooling

Reusable App Store Connect automation tooling extracted from product repositories.

Current command surface:

- `asc-review`
- `asc-metadata`
- `asc-beta`
- `asc-sales`
- `asc-screenshots`
- `asc-iap`

Current implementation status:

- `asc-review`: implemented
- `asc-metadata`: implemented
- `asc-beta`: implemented
- `asc-sales`: implemented
- `asc-screenshots`: implemented
- `asc-iap`: implemented

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

Consume the gem from a private Git repository in a product `Gemfile`:

```ruby
gem "asc_tooling",
  git: "git@github.com:JaminZhou/asc-tooling.git",
  tag: "v0.5.0"
```

Then install and run through Bundler:

```bash
bundle install
bundle exec asc-review status --bundle-id com.example.app
bundle exec asc-review release --bundle-id com.example.app --app-version 1.2.0
```

Example local usage from a checkout:

```bash
./exe/asc-review status --bundle-id com.example.app
./exe/asc-metadata status --bundle-id com.example.app --locale en-US
./exe/asc-beta status --bundle-id com.example.app
./exe/asc-sales units --bundle-id com.example.app --vendor-number 12345678 --report-date 2026-04-10
./exe/asc-screenshots status --bundle-id com.example.app --locale en-US --display-type APP_DESKTOP
./exe/asc-iap status --bundle-id com.example.app
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

For a fuller usage guide and the release flow, see
[docs/release-and-usage.md](docs/release-and-usage.md).

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
