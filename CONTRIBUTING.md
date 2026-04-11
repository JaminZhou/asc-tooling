# Contributing

Thanks for taking a look at `asc_tooling`.

## Scope

This repository is intended for reusable App Store Connect automation helpers.
Keep product-specific logic, screenshot rendering, and app-specific release
state in the consuming product repository.

The supported surface area is the JWT-based CLI workflow:

- `asc-review`
- `asc-metadata`
- `asc-beta`
- `asc-sales`
- `asc-screenshots`
- `asc-iap`

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

## Pull requests

- Keep changes focused and small where possible.
- Add or update tests when behavior changes.
- Update `README.md` or docs when the command surface changes.
- Do not commit local secrets, `.env` files, App Store Connect keys, or browser
  session exports.
