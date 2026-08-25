# Changelog

All notable changes to this project are documented here.

This project follows semantic versioning for Git tags. Release notes should
summarize command-surface changes, packaging changes, and any migration notes
for product repositories that consume `asc_tooling`.

## Unreleased

### Added

- Added `asc-review attach-build` for explicitly linking a selected valid,
  App Store-eligible build to an editable App Store version, with dry-run and
  post-mutation read-back verification.
- Added `asc-review status --items` to include App Store version and in-app
  purchase version items for each review submission in text or JSON output.

### Changed

- Added an IAP status signal and preflight guard for the app's first IAP so
  `asc-iap submit` stops before mutation when Apple requires the App Store
  Connect web UI joint-submission flow.
- Restricted explicit review build selection to builds that are both `VALID`
  and `APP_STORE_ELIGIBLE`.

## 0.10.0 - 2026-07-22

### Added

- Added an App Store Connect API gap matrix to track future probe candidates
  without expanding the supported CLI surface preemptively.
- Added `asc-tooling --version` and bare `asc-tooling version` output for
  machine-level CLI version checks.

### Fixed

- Allowed metadata and screenshot status commands to read released App Store
  versions, with matching-state app info for metadata reads, while keeping
  metadata apply and screenshot upload restricted to editable versions.

## 0.9.3 - 2026-07-01

### Fixed

- Updated public installation examples and issue template placeholders to point
  at the current `v0.9.3` release tag.

## 0.9.2 - 2026-07-01

### Fixed

- Fixed `asc-availability apply` cache invalidation so a reused process can
  re-fetch newly created app availability before reporting status.

## 0.9.1 - 2026-06-30

### Changed

- Updated GitHub Actions workflow dependencies for checkout, artifact upload,
  and GitHub release creation.

## 0.9.0 - 2026-06-30

### Added

- Added `asc-tooling` as a unified CLI entrypoint for command discovery,
  command delegation, and bundled skill installation.
- Added the bundled `asc-tooling` Agent/Codex/Claude skill.
- Added Chinese documentation, agent instructions, community templates,
  Dependabot, release automation, and repository-local skill validation.

### Changed

- Documented `asc-tooling` as the preferred entrypoint while keeping the
  legacy executable names supported for existing scripts.
- Added package metadata and CI checks so the bundled skill and gem package are
  validated before merge.

## 0.8.6

- Current released baseline before the unified CLI and bundled skill surface.
