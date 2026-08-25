# App Store Connect API Gap Matrix

This document tracks App Store Connect API areas that are not currently part of
`asc_tooling`'s supported CLI surface. It is a discovery backlog, not a product
roadmap. A gap should become a CLI feature only when it removes a repeatable
release blocker in a consuming product repository and can follow this project's
safety model: explicit command names, status-first behavior, dry-run support for
mutating operations, no product secrets, and clear web-confirmation boundaries.

## Source Baseline

- Primary reference: Apple App Store Connect API documentation and the official
  OpenAPI specification download.
- Snapshot checked: official OpenAPI 4.4.1 zip downloaded on 2026-08-25.
- Local command surface checked: `review`, `metadata`, `beta`, `sales`,
  `screenshots`, `iap`, `version`, `availability`, and `store-setup`.

## Promotion Rules

Promote an API area from "candidate" to implementation only when all of these
are true:

1. A real product release workflow needs it more than once.
2. The Apple API shape is known from official docs or a read-only probe.
3. The command can expose `status` or another non-mutating inspection path.
4. Mutating paths can support `--dry-run`, or the documentation clearly states
   why dry-run is not possible.
5. Product-specific values, assets, credentials, screenshots, review notes, and
   release decisions stay in the consuming product repository.

## Candidate Matrix

| Area | Current support | Official API signal | Priority | Recommended next probe |
| --- | --- | --- | --- | --- |
| App Privacy | Web confirmation only. Metadata commands cover privacy policy URLs, not App Privacy nutrition-label declarations. | No direct privacy-detail path is present in OpenAPI 4.4.1. | High to monitor, blocked to implement until a stable endpoint is confirmed. | Re-check the latest OpenAPI spec before each major release. If a privacy declaration resource appears, start with a read-only status command and keep web confirmation in release docs until verified against a real app. |
| IAP version review submissions | Legacy IAP readiness and direct submission helpers are supported. First-IAP preflight is supported, but creating and grouping `inAppPurchaseVersions` into a review submission is not yet exposed. | OpenAPI 4.4.1 includes `inAppPurchaseVersions` and `reviewSubmissionItems.inAppPurchaseVersion`. Apple explicitly excludes the app's first IAP from this API submission path. | High. It removes repeatable web work after the first IAP is approved. | Add status and dry-run-first commands for IAP draft versions, then add explicit review-submission item creation for subsequent IAPs. Keep the first-IAP web boundary as a hard preflight. |
| Accessibility Declarations | Not supported. | The checked OpenAPI spec includes `/v1/accessibilityDeclarations`, `/v1/accessibilityDeclarations/{id}`, and app relationships. | Medium-high. It is release-facing and could become a repeatable checklist item. | Add a read-only probe that lists declarations for an app and compares expected device families. Consider mutating support only after a product has a stable accessibility declaration template. |
| Phased Release | Partially adjacent. `asc-review release` handles manual release requests, but not phased release setup or pause/resume. | The spec includes `/v1/appStoreVersionPhasedReleases` and app-store-version relationships. | Medium. Useful for controlled production rollout, but not every product needs it. | Prototype `phased-release status` first. Then evaluate `create`, `pause`, `resume`, and `complete` commands with dry-run output. |
| Analytics Reports | Not supported. `asc-sales` covers Sales and Trends only. | The spec includes analytics report requests, reports, instances, and segments. | Medium-low. Useful for reporting, but separate from core release automation. | Start with a read-only/report-download spike outside the main CLI. Promote only if a product needs recurring post-release metrics that Sales and Trends cannot answer. |
| Customer Reviews | Not supported. The experimental Resolution Center helper is browser-session based and should remain separate. | The spec includes app and version customer review reads plus customer review response resources. | Medium-low. Useful for support workflows, but not necessary for app submission. | Keep separate from App Review Resolution Center. If needed, add `reviews status` or `reviews export` before any response-writing command. |
| Subscriptions | Not supported beyond existing non-subscription IAP helpers. | The spec has a large subscription surface: groups, localizations, offers, prices, screenshots, availability, and submissions. | Product-triggered only. | Do not build generic subscription automation preemptively. If a product adds subscriptions, map the exact launch checklist first and implement the smallest status/prepare helpers. |
| Webhooks | Not supported. | The spec includes app webhooks, deliveries, pings, and marketplace webhook resources. | Low for local CLI, potentially high for hosted infrastructure. | Keep out of `asc_tooling` unless there is a clear local setup or verification workflow. A hosted receiver belongs in a separate project. |
| App Encryption Declarations | Not supported. | The spec includes app encryption declarations, documents, build relationships, and creation endpoints. | Medium. Can block builds or submissions for some apps. | Add a read-only `encryption status` spike if a product release needs export-compliance automation. Treat document upload and build linking as mutating operations with dry-run-first design. |

## Current Non-Goals

- Do not wrap the full App Store Connect API just because an endpoint exists.
- Do not move product-specific release state into this repository.
- Do not automate browser-only or account-session flows as supported public
  commands.
- Do not mix Customer Reviews with App Review Resolution Center until Apple
  exposes a stable JWT-based Resolution Center API.
- Do not automate agreement acceptance, App Privacy declaration publishing, or
  Apple silicon Mac availability and compatibility verification as supported
  commands while those workflows remain absent from the official OpenAPI spec.

## Recently Promoted

- Review build attachment is available through `asc-review attach-build`, with
  dry-run, eligibility checks, and read-back verification.
- Review submission item inspection is available through
  `asc-review status --items`, including App Store version and IAP version
  linkages.
- First-IAP direct-submission detection is a status signal and a pre-mutation
  guard in `asc-iap submit`; the required web joint-submission step remains a
  documented Apple API boundary.

## Review Cadence

Refresh this matrix when:

- Apple publishes a new App Store Connect API version or OpenAPI snapshot.
- A product repository hits a release blocker that still requires web UI work.
- A supported command accumulates repeated manual confirmation notes that could
  be replaced by a safe read-only API probe.
