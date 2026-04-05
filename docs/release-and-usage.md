# Release And Usage

## Environment

All commands require these environment variables:

```bash
export ASC_KEY_ID=YOUR_KEY_ID
export ASC_ISSUER_ID=YOUR_ISSUER_ID
export ASC_KEY_PATH=~/.config/appstoreconnect/AuthKey_xxx.p8
```

## Commands

### Review

```bash
bundle exec asc-review status --bundle-id com.example.app --json
bundle exec asc-review submit --bundle-id com.example.app --release-type manual
bundle exec asc-review withdraw --bundle-id com.example.app
```

### Metadata

```bash
bundle exec asc-metadata status --bundle-id com.example.app --locale en-US
bundle exec asc-metadata apply \
  --bundle-id com.example.app \
  --locale en-US \
  --subtitle "Calm wake control for Mac"
```

### Screenshots

```bash
bundle exec asc-screenshots status \
  --bundle-id com.example.app \
  --locale en-US \
  --display-type APP_DESKTOP

bundle exec asc-screenshots upload \
  --bundle-id com.example.app \
  --locale en-US \
  --display-type APP_DESKTOP \
  --source-dir build/app-store-screenshots
```

### In-App Purchases

```bash
bundle exec asc-iap status --bundle-id com.example.app

bundle exec asc-iap prepare \
  --bundle-id com.example.app \
  --review-screenshot build/review-screenshots/iap-review-support-ui.png

bundle exec asc-iap submit \
  --bundle-id com.example.app \
  --product-id com.example.app.tip.small
```

`asc-iap prepare` currently automates review screenshot upload and availability
setup. If Apple returns `FIRST_IAP_MUST_BE_SUBMITTED_ON_VERSION`, the app's
first IAP still needs to be attached to the app version submission in the App
Store Connect web UI before that version is submitted.

### Beta

```bash
bundle exec asc-beta status --bundle-id com.example.app

bundle exec asc-beta add-build \
  --bundle-id com.example.app \
  --group-name Internal \
  --build-number 202603221408 \
  --dry-run

bundle exec asc-beta add-tester \
  --bundle-id com.example.app \
  --group-name Internal \
  --email tester@example.com \
  --dry-run

bundle exec asc-beta remove-tester \
  --bundle-id com.example.app \
  --group-name Internal \
  --email tester@example.com \
  --dry-run
```

## Release Flow

1. Update the gem version in `lib/asc_tooling/version.rb`.
2. Commit and push the version bump to `main`.
3. Create and push a tag:

```bash
git tag v0.2.0
git push origin v0.2.0
```

4. In each consuming product repository:

```bash
bundle update asc_tooling
git add Gemfile.lock
git commit -m "Update asc_tooling to v0.2.0"
```

## Scope

`asc-tooling` should stay focused on reusable App Store Connect operations:

- review submission
- metadata updates
- screenshot upload and inspection
- in-app purchase screenshot, availability, and readiness helpers
- beta group and tester management

Product-specific screenshot rendering, copy generation, and UI state setup
should remain in each app repository.
