# Agent Instructions

## Communication

- Keep `README.md` as the default English entrypoint.
- Keep `README.zh.md` conceptually aligned when public-facing behavior, commands, installation, or support boundaries change.
- Use Chinese by default when Jamin asks in Chinese.

## Project Scope

- This repository contains reusable App Store Connect tooling, not product-specific release state.
- Product-specific screenshot generation, review notes, metadata files, App Store Connect keys, and release decisions belong in consuming product repositories.
- The supported surface is the JWT-based CLI command set plus the bundled `asc-tooling` skill installer.
- Product repositories consume one machine-level `asc-tooling` CLI/gem and enforce product-local minimum versions; do not reintroduce per-product Gemfile pins.
- `experimental/` helpers are local-only and unsupported public interfaces.

## Security Boundaries

- Do not commit `.p8` keys, API credentials, `.env` files, browser session exports, cookies, tokens, App Store Connect account data, or product secrets.
- Do not add hidden side effects. Mutating App Store Connect operations must be explicit in CLI names and help text.
- Prefer `--dry-run` support for mutating commands where practical.
- Browser-session helpers must stay experimental, local-only, and out of CI/shared automation.

## Required Checks

Before submitting changes that touch Ruby code, command behavior, package metadata, docs, release flow, or GitHub automation, run:

```bash
bundle exec ruby -Itest -e 'Dir["test/*_test.rb"].each { |f| load f }'
bundle exec rubocop
gem build asc_tooling.gemspec
```

When `skills/` changes, also run the skill validator if available:

```bash
ruby .github/scripts/validate_skill.rb
```

If local Bundler selects an old incompatible version, use the current Bundler explicitly, for example:

```bash
ruby -S bundle _4.0.11_ install
ruby -S bundle _4.0.11_ exec ruby -Itest -e 'Dir["test/*_test.rb"].each { |f| load f }'
ruby -S bundle _4.0.11_ exec rubocop
```

## Release Notes

- Version bumps live in `lib/asc_tooling/version.rb`.
- User-visible changes should be recorded in `CHANGELOG.md`.
- Tags use `vX.Y.Z`.
- The release workflow builds a gem artifact and creates a GitHub release for `vX.Y.Z` tags.
- GitHub releases should summarize command-surface changes and any consumer migration notes.
- A tag and GitHub release are not the end of rollout. Follow the Post-Release SOP to update and verify the machine-level CLI, refresh installed skills, inventory Makefile consumers, and record lagging consumers.
