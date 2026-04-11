# Browser Session Resolution Center Helper

This helper is intentionally **experimental** and **local-only**.

Use it when you need the human reviewer message from Resolution Center and the
official JWT App Store Connect API does not expose that text.

It is **not** part of the formal `asc_tooling` release flow:

- it depends on an existing local browser login session
- it reads cookies from a local Chrome profile
- it bootstraps a temporary Python virtual environment with `browser_cookie3`
- it should never be checked into the repository or wired into CI

## Scope

This helper is useful for:

- reading the latest rejection message
- inspecting Resolution Center threads for a known submission

It should **not** be wired into CI or product release commands.

## Handling expectations

Prefer the regular JWT-based commands first. Reach for this helper only when
you specifically need Resolution Center text that the public API does not
return.

If you run `experimental/export_browser_asc_session.py` directly, write the
output to a temporary file outside the repository and delete it as soon as you
are done. That JSON contains live browser cookies and should be treated like a
short-lived secret.

## Requirements

- a local Chrome profile already logged into App Store Connect
- Bundler dependencies installed for this repo
- if you want to resolve a submission from a bundle id, either export
  `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY_PATH`, or pass
  `--key-id`, `--issuer-id`, and `--key-path`

## Usage

### By bundle id

```bash
./experimental/asc-resolution-center \
  --bundle-id com.example.app
```

You can also pass the ASC API key details explicitly instead of relying on ENV:

```bash
./experimental/asc-resolution-center \
  --bundle-id com.example.app \
  --key-id "$ASC_KEY_ID" \
  --issuer-id "$ASC_ISSUER_ID" \
  --key-path "$ASC_KEY_PATH"
```

### By explicit review submission id

```bash
./experimental/asc-resolution-center \
  --submission-id d7669691-6e8b-491c-858c-838668c88090
```

### JSON output

```bash
./experimental/asc-resolution-center \
  --bundle-id com.example.app \
  --json
```

## Chrome profile

By default this helper reads:

- `~/Library/Application Support/Google/Chrome/Profile 1/Cookies`

To use a different profile, set:

```bash
export ASC_BROWSER_PROFILE_NAME="Default"
```
