# Changelog

All notable changes to this project are documented here.

This project follows semantic versioning for Git tags. Release notes should
summarize command-surface changes, packaging changes, and any migration notes
for product repositories that consume `asc_tooling`.

## Unreleased

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
