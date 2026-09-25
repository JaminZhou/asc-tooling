# Migrating to upstream asc

`asc-tooling` is retired. Use [rorkai/App-Store-Connect-CLI](https://github.com/rorkai/App-Store-Connect-CLI) and its maintained skills. The migration baseline is `asc 5.5.0`.

```sh
brew install asc
asc version
asc install-skills
```

This is a workflow migration, not a drop-in executable rename. Product repositories retain their build, screenshot generation, release evidence and acceptance rules, and call upstream commands directly. No replacement shared API library is introduced.

## Credentials

Continue using the existing App Store Connect API key. Authenticate directly with `asc auth login`, which stores the credential in the system keychain; use `asc auth login --help` for setup and `asc auth status --validate` to verify it. Native `asc` commands use this profile without a Make wrapper or a sourced Xcode env file.

Product archive/upload targets separately load the existing private env file for Xcode authentication and retain `ASC_KEY_PATH`. If native `asc` needs environment-based authentication instead of a keychain profile, it expects `ASC_PRIVATE_KEY_PATH`; set that explicitly. Product Makefiles no longer translate these variables for native CLI commands. Keep the `.p8` file and env file outside repositories. No new Apple key, browser session, or keychain export is needed for JWT operations.

## Main changes

| Retired surface | Upstream workflow |
| --- | --- |
| `asc-tooling review status` | `asc review status` |
| `asc-tooling version create` | `asc versions create` |
| Per-field metadata flags | `asc metadata pull`, edit canonical JSON, validate, `push --dry-run`, then push |
| Screenshot upload | `asc screenshots upload` with a localization ID or locale-directory tree; preview replacement before confirming |
| TestFlight operations | `asc testflight groups/testers`, `asc builds add-groups`, `asc builds test-notes` |
| Review submission | `asc review submit` with an exact version and build ID |
| Withdraw / manual release | `asc submit cancel` / `asc versions release` with an explicit version ID |
| Store setup | Native `app-setup`, `age-rating`, `review details-*`, pricing and availability commands |
| IAP submission | Versioned IAPs and review submission items; follow current Apple first-of-type rules |
| Sales summary | Native report download / insights; keep product-specific output formatting with its consumer |

Use `--help` on the installed command before use. Native `--dry-run` is command-specific: supply it explicitly where supported, and use `--confirm` where required. The former `make asc-*`, `make asc ARGS=...` and `ASC_APPLY` interfaces have been removed. Do not invent a `--dry-run` flag for commands that do not expose it.

## Consumer guides

- [Rouse](https://github.com/JaminZhou/Rouse/blob/main/docs/asc-migration.md)
- [CalcBird / GarlicBird](https://github.com/JaminZhou/GarlicBird/blob/main/docs/asc-migration.md)
- [Hushtrail](https://github.com/JaminZhou/hushtrail/blob/main/docs/asc-migration.md)
- [Trailglass](https://github.com/JaminZhou/Trailglass/blob/main/docs/asc-migration.md)

Each guide records its app ID, platform, authentication and product-specific release inputs. Build, screenshot generation and required product release checks remain in the consuming repository; generic App Store Connect operations use native `asc` and upstream skills directly. Historical version notes remain historical; use the current guide for commands.

## Retiring the old installation

After migrating all consumers, remove installed `asc-tooling` skills from the active Codex/Agents/Claude skill directories and uninstall the old `asc_tooling` gem if nothing else requires it. Preserve keys and product assets. The upstream skills installed by `asc install-skills` replace the old bundled skill; do not copy or continue maintaining it.

The retirement and migration do not authorize uploading a build, changing product metadata, submitting App Review, or publishing an app. Verify the integration with local tests and read-only ASC calls first; exercise real writes as part of the next explicitly authorized product release.
