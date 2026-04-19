# Release And Usage

## Environment

All commands require these environment variables:

```bash
export ASC_KEY_ID=YOUR_KEY_ID
export ASC_ISSUER_ID=YOUR_ISSUER_ID
export ASC_KEY_PATH=~/.config/appstoreconnect/AuthKey_xxx.p8
export ASC_VENDOR_NUMBER=YOUR_VENDOR_NUMBER
```

## Commands

### Review

```bash
bundle exec asc-review status --bundle-id com.example.app --json
bundle exec asc-review submit --bundle-id com.example.app --release-type manual
bundle exec asc-review release --bundle-id com.example.app --app-version 1.2.0
bundle exec asc-review withdraw --bundle-id com.example.app
```

`asc-review release` sends the manual release request for a version in
`PENDING_DEVELOPER_RELEASE`. If the version is already processing or live, it
no-ops with a status message.

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

### Sales

```bash
bundle exec asc-sales report \
  --vendor-number 12345678 \
  --report-date 2026-04-10 \
  --output build/sales-2026-04-10.tsv

bundle exec asc-sales units \
  --bundle-id com.example.app \
  --vendor-number 12345678 \
  --report-date 2026-04-10 \
  --json
```

`asc-sales report` downloads the raw Sales and Trends report from App Store
Connect and saves or prints the decompressed TSV content.

`asc-sales units` uses the Summary Sales Report to aggregate app units for the
app's Apple identifier, including download, redownload, and update rows. This
is a lightweight wrapper over `GET /v1/salesReports`; App Analytics report
generation is still out of scope for now.

## Release Flow

1. Update the gem version in `lib/asc_tooling/version.rb`.
2. Create a release branch, open a PR, and merge it to `main` after tests pass.
3. Create and push a tag from the updated `main` branch:

```bash
git tag v0.5.1
git push origin v0.5.1
```

4. Create a GitHub release for the tag:

```bash
gh release create v0.5.1 --generate-notes
```

## Post-Release SOP

After the tag and GitHub release are live, update each local product
repository that consumes `asc_tooling`.

### Find Local Consumers

Before each release, rescan `~/Developer` instead of maintaining a static
consumer list:

```bash
rg -l --glob 'Gemfile' "gem ['\"]asc_tooling['\"]" ~/Developer | xargs -n1 dirname
```

This keeps the rollout checklist current when new product repositories are
added later.

### Update Each Consumer Repository

For each repository returned by the scan:

1. Sync `main` and create a release follow-up branch such as
   `chore/bump-asc-tooling-v0-5-1`.
2. Update the `tag:` in `Gemfile` to the newly released version.
3. Run `bundle update asc_tooling` to refresh `Gemfile.lock`.
4. Run the repository's normal validation commands.
5. Commit, push, and open a PR.

Example workflow after choosing one repository from the scan result:

```bash
cd <consumer-repo>
git switch main
git pull --ff-only origin main
git switch -c chore/bump-asc-tooling-v0-5-1

# Update Gemfile tag from the previous version to v0.5.1.
bundle update asc_tooling

# Run the repo-specific verification here.

git add Gemfile Gemfile.lock
git commit -m "chore: update asc_tooling to v0.5.1"
git push -u origin HEAD
gh pr create --fill
```

### Verification Checklist

Before considering the release fully rolled out, confirm that:

- every local consumer repository has a PR for the new `asc_tooling` tag
- every updated `Gemfile.lock` resolves to the expected `asc_tooling` version
- any lagging consumer is explicitly noted for follow-up

## Scope

`asc-tooling` should stay focused on reusable App Store Connect operations:

- review submission
- metadata updates
- sales report download and unit summaries
- screenshot upload and inspection
- in-app purchase screenshot, availability, and readiness helpers
- beta group and tester management

Product-specific screenshot rendering, copy generation, and UI state setup
should remain in each app repository.
