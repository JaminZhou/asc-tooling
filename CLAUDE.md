# Project Instructions

## Release Process

1. Bump `VERSION` in `lib/asc_tooling/version.rb`.
2. Create PR from feature branch, squash merge to main.
3. Tag: `git tag v<version> && git push origin v<version>`.
4. GitHub release: `gh release create v<version>` with changelog notes.

## PR Workflow

- Create feature branch from main (`feat/`, `fix/`, etc.).
- Push branch, create PR with `gh pr create`.
- After bot review comments: fix, push, then resolve threads via GraphQL API.
- Squash merge with `gh pr merge --squash --delete-branch`.

## Testing

- Run tests: `bundle exec ruby -Itest -e 'Dir["test/*_test.rb"].each { |f| load f }'`
- Run lint: `bundle exec rubocop`
- Both must pass before merging.
