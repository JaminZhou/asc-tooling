# Security Boundaries

- App Store Connect `.p8` keys, JWTs, cookies, account identifiers, and product secrets must never be committed.
- Browser-session helpers are local-only and experimental; do not turn them into shared automation.
- Product-specific assets and release state belong in the consuming product repository.
- Prefer status and dry-run commands before any mutating App Store Connect action.
- App Privacy, first-IAP attachment, and some review confirmation flows may still require manual App Store Connect web UI confirmation.
