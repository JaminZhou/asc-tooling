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

### Beta

```bash
bundle exec asc-beta status --bundle-id com.example.app

bundle exec asc-beta add-build \
  --bundle-id com.example.app \
  --group Internal \
  --build-number 202603221408 \
  --dry-run

bundle exec asc-beta add-tester \
  --bundle-id com.example.app \
  --group Internal \
  --email tester@example.com \
  --dry-run

bundle exec asc-beta remove-tester \
  --bundle-id com.example.app \
  --group Internal \
  --email tester@example.com \
  --dry-run
```

## Release Flow

1. Update the gem version in `lib/asc_tooling/version.rb`.
2. Commit and push the version bump to `main`.
3. Create and push a tag:

```bash
git tag v0.1.2
git push origin v0.1.2
```

4. In each consuming product repository:

```bash
bundle update asc_tooling
git add Gemfile.lock
git commit -m "Update asc_tooling to v0.1.2"
```

## Scope

`asc-tooling` should stay focused on reusable App Store Connect operations:

- review submission
- metadata updates
- screenshot upload and inspection
- beta group and tester management

Product-specific screenshot rendering, copy generation, and UI state setup
should remain in each app repository.
