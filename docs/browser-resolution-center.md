# Browser Session Resolution Center Helper

This helper is intentionally **experimental** and **local-only**.

Use it when you need the human reviewer message from Resolution Center and the
official JWT App Store Connect API does not expose that text.

It is **not** part of the formal `asc_tooling` release flow:

- it depends on an existing local browser login session
- it reads cookies from a local Chrome profile
- it bootstraps a temporary Python virtual environment with `browser_cookie3`

## Scope

This helper is useful for:

- reading the latest rejection message
- inspecting Resolution Center threads for a known submission

It should **not** be wired into CI or product release commands.

## Requirements

- a local Chrome profile already logged into App Store Connect
- Bundler dependencies installed for this repo
- `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY_PATH` exported if you want to
  resolve a submission from a bundle id

## Usage

### By bundle id

```bash
./experimental/asc-resolution-center \
  --bundle-id com.example.app
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
