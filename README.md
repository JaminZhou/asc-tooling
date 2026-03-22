# asc-tooling

Reusable App Store Connect automation tooling extracted from product repositories.

Current command surface:

- `asc-review`
- `asc-metadata`
- `asc-beta`
- `asc-screenshots`

Current implementation status:

- `asc-review`: implemented
- `asc-metadata`: implemented
- `asc-beta`: scaffold only
- `asc-screenshots`: implemented

Product-specific assets such as screenshot renderers should stay in each app
repository.

Example local usage from a checkout:

```bash
./exe/asc-review status --bundle-id com.example.app
./exe/asc-metadata status --bundle-id com.example.app --locale en-US
./exe/asc-screenshots status --bundle-id com.example.app --locale en-US --display-type APP_DESKTOP
```
