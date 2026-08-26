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

The examples below assume the machine-level CLI has been installed using the
current tagged release as documented in the README.

`asc-tooling` is the preferred unified entrypoint:

```bash
asc-tooling commands
asc-tooling --version
asc-tooling review status --bundle-id com.example.app --json
asc-tooling version create --bundle-id com.example.app --version 1.2.0 --platform ios --dry-run
asc-tooling init --client codex --force
```

The focused executable names below remain supported for existing scripts.

### Review

```bash
asc-review status --bundle-id com.example.app --json
asc-review status --bundle-id com.example.app --app-version 1.2.0 --items
asc-review attach-build \
  --bundle-id com.example.app \
  --app-version 1.2.0 \
  --build-number 2026082501 \
  --dry-run
asc-review submit \
  --bundle-id com.example.app \
  --app-version 1.2.0 \
  --build-number 2026082501 \
  --release-type manual
asc-review release --bundle-id com.example.app --app-version 1.2.0
asc-review withdraw --bundle-id com.example.app --app-version 1.2.0
```

`asc-review release` sends the manual release request for a version in
`PENDING_DEVELOPER_RELEASE`. If the version is already processing or live, it
no-ops with a status message.

`asc-review attach-build` requires an explicit `--app-version`, accepts an
optional `--build-number` instead of the latest eligible build, and only links
builds that are both `VALID` and `APP_STORE_ELIGIBLE`. The command supports
`--dry-run` and verifies the attached build by reading the version again after
the mutation. `asc-review submit --build-number ...` uses the same verified
attachment path before creating or submitting the review submission.

Pass `--items` to `asc-review status` when the release needs proof of the exact
App Store version and IAP version items grouped in each review submission. The
same item summaries are included in `--json` output.

`asc-review withdraw` removes a version from App Review by deleting the
`appStoreVersionSubmission`. It supports submitted states such as
`WAITING_FOR_REVIEW`, `IN_REVIEW`, and pending manual release states; after the
withdrawal App Store Connect normally reports the version as
`DEVELOPER_REJECTED`.

### App Version

```bash
asc-version create \
  --bundle-id com.example.app \
  --version 1.2.0 \
  --platform ios \
  --dry-run
```

`asc-version create` creates a new editable App Store version when the product
workflow needs to prepare metadata before attaching a build or submitting for
review.

### Metadata

```bash
asc-metadata status \
  --bundle-id com.example.app \
  --app-version 1.2.0 \
  --locale en-US
asc-metadata apply \
  --bundle-id com.example.app \
  --locale en-US \
  --subtitle "Calm wake control for Mac"
```

`status` can read either an editable or released version and reports its App
Store state. `apply` remains restricted to editable versions.

### Store Setup

```bash
asc-store-setup status \
  --bundle-id com.example.app \
  --app-version 1.0.0 \
  --platform ios \
  --primary-category SHOPPING \
  --age-rating-template 4-plus

asc-store-setup apply \
  --bundle-id com.example.app \
  --app-version 1.0.0 \
  --platform ios \
  --release-type manual \
  --primary-category SHOPPING \
  --age-rating-template 4-plus \
  --free-pricing \
  --review-contact-first-name Jamin \
  --review-contact-last-name Zhou \
  --review-contact-phone "+1 555 0100" \
  --review-contact-email me@example.com \
  --review-notes-file docs/asc-review-notes-v1.0.0.txt \
  --no-demo-account \
  --dry-run
```

`asc-store-setup apply` only changes the fields represented by the options you
pass. Review details require complete App Review contact information before the
tool creates them. Creating a new review detail also requires an explicit demo
account state: pass `--no-demo-account`, or pass `--demo-account-required` with
`--demo-account-name` and `--demo-account-password` when reviewers need a login.
Availability and App Privacy should still be confirmed in App Store Connect for
first-version submissions.
`--free-pricing` creates a free app price schedule only when no price schedule
already exists.

### Availability

```bash
asc-availability status --bundle-id com.example.app

asc-availability apply \
  --bundle-id com.example.app \
  --all-territories \
  --available-in-new-territories \
  --dry-run
```

`asc-availability status` checks the current app availability resource when it
exists and reports missing territory IDs. `asc-availability apply` creates the
app availability resource for all current territories through the
`/v2/appAvailabilities` endpoint. Pass `--no-available-in-new-territories` when
the product should not auto-enable new territories.

### Screenshots

```bash
asc-screenshots status \
  --bundle-id com.example.app \
  --app-version 1.2.0 \
  --locale en-US \
  --display-type APP_DESKTOP

asc-screenshots upload \
  --bundle-id com.example.app \
  --locale en-US \
  --display-type APP_DESKTOP \
  --source-dir build/app-store-screenshots
```

`status` can inspect screenshot sets on editable or released versions and
reports the selected version state. `upload` remains restricted to editable
versions.

### In-App Purchases

```bash
asc-iap status --bundle-id com.example.app

asc-iap prepare \
  --bundle-id com.example.app \
  --review-screenshot build/review-screenshots/iap-review-support-ui.png

asc-iap submit \
  --bundle-id com.example.app \
  --product-id com.example.app.tip.small
```

`asc-iap prepare` currently automates review screenshot upload and availability
setup. `asc-iap status` reports `first_iap_web_submission_required`, and
`asc-iap submit` checks that condition before making any submission request.
Apple's first-IAP exception still requires attaching the IAP to the app version
submission in the App Store Connect web UI. Once the app has a previously
approved IAP, products in `READY_TO_SUBMIT` can use direct CLI submission.

### Beta

```bash
asc-beta status --bundle-id com.example.app

asc-beta add-build \
  --bundle-id com.example.app \
  --group-name Internal \
  --build-number 202603221408 \
  --dry-run

asc-beta add-tester \
  --bundle-id com.example.app \
  --group-name Internal \
  --email tester@example.com \
  --dry-run

asc-beta add-tester \
  --bundle-id com.example.app \
  --group-name Internal \
  --email tester@example.com \
  --first-name Test \
  --last-name User \
  --create-if-missing \
  --dry-run

asc-beta remove-tester \
  --bundle-id com.example.app \
  --group-name Internal \
  --email tester@example.com \
  --dry-run
```

### Sales

```bash
asc-sales report \
  --vendor-number 12345678 \
  --report-date 2026-04-10 \
  --output build/sales-2026-04-10.tsv

asc-sales units \
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
2. Update `CHANGELOG.md`.
3. Create a release branch, open a PR, and merge it to `main` after tests pass.
4. Create and push a tag from the updated `main` branch:

```bash
git tag v0.11.0
git push origin v0.11.0
```

5. Let the Release workflow build the gem artifact and create the GitHub
   release. If manual fallback is needed, authenticate GitHub CLI, build the
   same gem artifact locally, and attach it while creating the release:

```bash
release_tag=v0.11.0
release_version=${release_tag#v}

gh auth status --hostname github.com
gem build asc_tooling.gemspec
gh release create "$release_tag" \
  "asc_tooling-${release_version}.gem" \
  --generate-notes
```

6. Verify that the published release is not a draft or prerelease, contains
   the expected `asc_tooling-X.Y.Z.gem` asset, and summarizes command-surface
   changes plus any consumer migration requirements. Generated PR titles alone
   are not sufficient release notes.

## Post-Release SOP

Publishing the tag and GitHub release does not complete rollout. The supported
product-consumption model is one machine-level `asc-tooling` CLI/gem plus
product-local minimum-version checks. Product repositories should not add an
`asc_tooling` Gemfile pin.

### Install And Verify The Machine-Level CLI

Download the released gem asset before installing it. Passing the GitHub URL
directly to `gem install` is not supported by every RubyGems version.

```bash
release_tag=v0.11.0
release_version=${release_tag#v}
release_download_dir=$(mktemp -d)
release_gem="$release_download_dir/asc_tooling-${release_version}.gem"
machine_cli="$HOME/.local/bin/asc-tooling"

gh auth status --hostname github.com
gh release view "$release_tag" \
  --repo JaminZhou/asc-tooling \
  --json tagName,isDraft,isPrerelease,publishedAt,url,assets
curl --fail --location \
  --output "$release_gem" \
  "https://github.com/JaminZhou/asc-tooling/releases/download/${release_tag}/asc_tooling-${release_version}.gem"

gem install --user-install --bindir "$HOME/.local/bin" --no-document \
  "$release_gem"
test "$("$machine_cli" --version)" = "$release_version"
"$machine_cli" commands >/dev/null

rm "$release_gem"
rmdir "$release_download_dir"
```

If product automation does not inherit `$HOME/.local/bin` on `PATH`, invoke
`$HOME/.local/bin/asc-tooling` explicitly. Use the same Ruby installation for
the gem and generated executable; a version check performed by another Ruby is
not proof that the machine CLI was upgraded.

### Refresh And Verify Installed Skills

Refresh every supported skill destination from the newly installed gem, then
compare each installed `SKILL.md` with the bundled source:

```bash
machine_cli="$HOME/.local/bin/asc-tooling"
skill_reference=$(mktemp)
codex_root=${CODEX_HOME:-$HOME/.codex}
claude_root=${CLAUDE_CONFIG_DIR:-$HOME/.claude}

"$machine_cli" init --client codex --force
"$machine_cli" init --client agents --force
"$machine_cli" init --client claude --force
"$machine_cli" init --print > "$skill_reference"

cmp "$skill_reference" "$codex_root/skills/asc-tooling/SKILL.md"
cmp "$skill_reference" "$HOME/.agents/skills/asc-tooling/SKILL.md"
cmp "$skill_reference" "$claude_root/skills/asc-tooling/SKILL.md"
rm "$skill_reference"
```

### Find Machine-Level Consumers

Rescan `~/Developer` on every release. The primary inventory is product
Makefiles that declare an `asc_tooling` install or minimum version, not
Gemfiles:

```bash
rg -l --glob 'Makefile' \
  'ASC_TOOLING_(VERSION|INSTALL_VERSION|MIN_VERSION)' \
  "$HOME/Developer" \
  | while IFS= read -r consumer_file; do dirname "$consumer_file"; done \
  | sort -u
```

Also scan for legacy Gemfile consumers and migrate any result to the
machine-level model:

```bash
rg -l --glob 'Gemfile' "gem ['\"]asc_tooling['\"]" "$HOME/Developer"
```

### Update Each Consumer Repository

For each machine-level consumer:

1. Read its `AGENTS.md` and release docs, then sync `main`.
2. Confirm which version its ASC commands actually require.
3. While a repository still uses the legacy single
   `ASC_TOOLING_VERSION` variable for both installation and checking, update it
   to the new release so a clean-machine `make setup` cannot install a stale
   tag.
4. Prefer separating `ASC_TOOLING_INSTALL_VERSION` from
   `ASC_TOOLING_MIN_VERSION`: installation selects a reproducible release,
   while the check enforces the lowest version required by that product's
   command surface. The installer must never replace a newer installed CLI
   with an older one.
5. Run `make asc-tooling-check` and the repository's normal validation gates.
   The check proves compatibility only; the machine-level exact-version check
   above proves rollout.
6. Commit the consumer change on a branch such as
   `chore/bump-asc-tooling-v0-11-0`, open a PR, and record any intentionally
   lagging consumer.

Example workflow after choosing one repository from the scan result:

```bash
cd <consumer-repo>
git switch main
git pull --ff-only origin main
git switch -c chore/bump-asc-tooling-v0-11-0

# Update ASC_TOOLING_VERSION or the separated install/minimum variables.
make asc-tooling-check

# Run the repo-specific verification here.

git add Makefile
git commit -m "chore: update asc_tooling to v0.11.0"
git push -u origin HEAD
gh pr create --fill
```

### Verification Checklist

Before considering the release fully rolled out, confirm that:

- the GitHub release and gem asset are published and the release notes describe
  command-surface and migration changes
- the machine-level CLI reports the exact released version
- the Codex, Agent, and Claude skill copies match the released gem
- every machine-level consumer was discovered through its Makefile
- no consumer setup path can install a tag older than the intended global
  release
- every consumer that needs a version change has a PR with its normal gates
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

Potential future App Store Connect API coverage is tracked in
[api-gap-matrix.md](api-gap-matrix.md). New areas should be promoted only when
they solve repeatable product release blockers and preserve the explicit,
status-first, dry-run-friendly safety model.
