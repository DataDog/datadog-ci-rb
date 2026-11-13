# AGENTS.md

## Guardrails

- Use Ruby 2.7-compatible syntax.
- All instrumentation of customer code MUST only observe and MUST be side effect free.
- Instrumentation must never raise internal errors into customer test processes. Log failures at `warn` or `error` level. Let customer tests continue.
- Use exceptions for exceptional conditions, not control flow.
- Do not use `instance_variable_get` or `instance_variable_set`. Add explicit APIs instead.
- Do not change `spec/datadog/ci/release_gem_spec.rb` unless explicitly asked.
- Do not add `CHANGELOG.md` entries for individual changes. The release process compiles the changelog.

## Component boundaries

- Components can work together through the public methods of their `Component` or `NullComponent` classes.
- Code outside a component must not reference other constants defined inside that component's directory.
- You MUST NOT access `ENV` directly.
- You MUST define all settings in `lib/datadog/ci/configuration/settings.rb`. You MUST inject them into every component through `lib/datadog/ci/configuration/components.rb`.
- After changes, run `bundle exec rake archspec`. Fix every architecture violation. Without explicit approval, do not suppress or baseline violations.

## Types

- Add or update RBS definitions for Ruby changes. The options in `lib/datadog/ci/configuration/settings.rb` intentionally have no RBS definitions.
- Avoid `untyped` unless a precise type is not feasible.
- Write optional types as `Type?`, not `(nil | Type)`.
- After code or RBS changes, run `bundle exec rake steep:check`. Fix all errors.

## Tests

- Cover behavior changes with tests. After every code change, run the relevant tests.
- Never monkey-patch production code in tests. Do not use `prepend` on production code, reopen production classes or modules, or replace production singleton methods. Use normal interfaces instead.
- Do not use `instance_variable_get` or `instance_variable_set` in tests. Use mocks or explicit APIs.
- If in-memory state can show the behavior, avoid `puts` and assertions on stdout in tests.
- Do not use focused specs such as `fit` or `fdescribe`.
- Add a corresponding Rake task for each new contrib folder. Include every new test task in `TEST_METADATA`.
- Before running the full test suite, stage newly created files. `release_gem_spec.rb` uses `git ls-files` to validate files.

## Required validation

- Before handing off changes, run `bundle exec standardrb`. Fix all offenses.
- Run the architecture, type, and relevant test checks required above.
