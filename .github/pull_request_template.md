## Summary

- 

## Type

- [ ] Bug fix
- [ ] Feature
- [ ] Documentation
- [ ] Refactor / maintenance
- [ ] Release

## Scope and safety

- [ ] No App Store Connect keys, `.p8` files, cookies, tokens, account data, or product secrets are committed
- [ ] Product-specific logic and release state remain outside this repository
- [ ] Mutating App Store Connect behavior is explicit in command names/help text
- [ ] `--dry-run` behavior is present or intentionally not applicable for mutating flows
- [ ] README/docs are updated when command behavior changes

## Verification

- [ ] `bundle exec ruby -Itest -e 'Dir["test/*_test.rb"].each { |f| load f }'`
- [ ] `bundle exec rubocop`
- [ ] `gem build asc_tooling.gemspec`

## Notes

