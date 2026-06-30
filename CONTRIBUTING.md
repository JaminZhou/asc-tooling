# Contributing

Thanks for taking a look at `asc_tooling`.

Please follow the [Code of Conduct](CODE_OF_CONDUCT.md) when participating in
this project.

## Scope

This repository is intended for reusable App Store Connect automation helpers.
Keep product-specific logic, screenshot rendering, and app-specific release
state in the consuming product repository.

The supported surface area is the JWT-based CLI workflow:

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

The `experimental/` helpers are intentionally local-only and should not be
treated as stable public interfaces.

## Local setup

1. Install Ruby and Bundler.
2. Install dependencies:

```bash
bundle install
```

3. Run the test suite:

```bash
bundle exec ruby -Itest test/*_test.rb
```

4. Run lint:

```bash
bundle exec rubocop
```

5. Validate the bundled skill when skill files or package metadata change:

```bash
ruby .github/scripts/validate_skill.rb
```

## Pull requests

- Keep changes focused and small where possible.
- Add or update tests when behavior changes.
- Update `README.md`, `README.zh.md`, or docs when the command surface changes.
- Do not commit local secrets, `.env` files, App Store Connect keys, or browser
  session exports.
- Keep mutating App Store Connect operations explicit in CLI naming and add
  `--dry-run` support where practical.
