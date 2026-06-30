# Agent Instructions

## Communication

- Keep `README.md` as the default English entrypoint.
- Keep `README.zh.md` conceptually aligned when public-facing behavior, commands, installation, or support boundaries change.
- Use Chinese by default when Jamin asks in Chinese.

## Project Scope

- This repository contains reusable App Store Connect tooling, not product-specific release state.
- Product-specific screenshot generation, review notes, metadata files, App Store Connect keys, and release decisions belong in consuming product repositories.
- The supported surface is the JWT-based CLI command set plus the bundled `asc-tooling` skill installer.
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
python3 /path/to/skill-creator/scripts/quick_validate.py skills/asc-tooling
```

If local Bundler selects an old incompatible version, use the current Bundler explicitly, for example:

```bash
ruby -S bundle _4.0.11_ install
ruby -S bundle _4.0.11_ exec ruby -Itest -e 'Dir["test/*_test.rb"].each { |f| load f }'
ruby -S bundle _4.0.11_ exec rubocop
```

## Release Notes

- Version bumps live in `lib/asc_tooling/version.rb`.
- Tags use `vX.Y.Z`.
- GitHub releases should summarize command-surface changes and any consumer migration notes.
