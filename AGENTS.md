# AGENTS.md

## Guardrails

- Use Ruby 2.7-compatible syntax.
- Instrumentation must never raise internal errors into customer test processes. Log failures at `warn` or `error` level and degrade gracefully.
- Use exceptions for exceptional conditions, not control flow.
- Do not use `instance_variable_get` or `instance_variable_set`; add explicit APIs instead.
- Do not change `spec/datadog/ci/release_gem_spec.rb` unless explicitly asked.
- Never commit or push automatically. Git operations must be reviewed and approved by the user.

## Component boundaries

- Components may collaborate through the public methods exposed by their `Component` or `NullComponent` classes.
- Code outside a component must not reference other constants defined inside that component's directory.
- Run `bundle exec rake archspec` after changes and fix every architecture violation. Do not suppress or baseline violations unless explicitly approved.

## Types

- Add or update RBS definitions for Ruby changes. `lib/datadog/ci/configuration/settings.rb` is the exception; its options are intentionally not represented in RBS.
- Avoid `untyped` unless a precise type is not feasible.
- Write optional types as `Type?`, not `(nil | Type)`.
- Run `bundle exec rake steep:check` after code or RBS changes and fix all errors.

## Tests

- Cover behavior changes with tests and run the relevant tests after every code change.
- Never monkey-patch production code in tests, including with `prepend`, reopened production classes or modules, or replaced singleton methods. Exercise normal interfaces instead.
- Do not use `instance_variable_get` or `instance_variable_set` in tests; use mocks or explicit APIs.
- Do not use focused specs such as `fit` or `fdescribe`.
- A new contrib folder must have a corresponding Rake task, and every new test task must be included in `TEST_METADATA`.
- Stage newly created files before running the full test suite; `release_gem_spec.rb` validates files through `git ls-files`.

## Required validation

- Run `bundle exec standardrb` and fix all offenses before handing off changes.
- Run the architecture, type, and relevant test checks required above.
