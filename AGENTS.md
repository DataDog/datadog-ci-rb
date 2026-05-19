# AGENTS.md

This is Datadog's Test Optimization library for Ruby, which instruments tests to provide visibility into CI pipelines and optimize test runs.

## Development Commands

### Setting up Development Environment

```bash
# Install dependencies
bundle install

# Install test dependencies
bundle exec appraisal install
```

### Running Tests

If new files in the repository are created, run `git add -A` before running tests (otherwise `release_gem_spec.rb` will fail).
Make sure that dependencies are installed (bundle exec appraisal install) before running tests!

```bash
# Run all tests (as CI does)
bundle exec rake ci

# Run core library tests only
bundle exec rake test:main

# run a specific test file
bundle exec rspec "relative path to the file"

# Run specific integration tests (e.g., RSpec integration)
bundle exec rake test:rspec

# Run single test or tests matching a pattern
bundle exec rake test:minitest'[--example hooks]'
```

### Working with Appraisals

```bash
# List available appraisal groups
bundle exec appraisal list

# Install dependencies for specific group
APPRAISAL_GROUP=cucumber-8 bundle exec appraisal install

# Generate gemfiles from Appraisals definitions
bundle exec appraisal generate
```

### Type checking

```bash
# verify type correctness
bundle exec rake steep:check

# make sure that there are no unnecessary RBS files
bundle exec rake rbs:clean
```

### Code Quality Checks

```bash
# Run code style checks
bundle exec standardrb

# Run typing checks
bundle exec rake steep:check
```

### Compile Native Extensions

```bash
# Compile the C extension for test impact analysis
bundle exec rake compile_ext
```

## Architecture Overview

The library uses a component-based architecture. 
The folder structure in `lib/datadog/ci` roughly corresponds to available components.

## Framework Integrations

The library supports various test frameworks, test runners, and other libraries through contrib modules.

Each integration is in `lib/datadog/ci/contrib/<framework_name>/`

## Integration Pattern

Each framework integration follows a common pattern:

1. `patcher.rb` - Modifies framework behavior
2. `integration.rb` - Describes the integration
3. `ext.rb` - Constants specific to the integration
4. `configuration/settings.rb` - Integration-specific settings

## Native Extensions

The library uses native extensions for code coverage tracking for test impact analysis which requires using Ruby C API.

The native extension is in `ext/` directory and compiled for each Ruby version.

## Ruby usage

- We use Ruby 2.7 syntax
- Use exceptions for exceptional cases, not for control flow.
- Implement proper error logging and user-friendly messages.

## Code Quality

- standardrb tool is used for code style enforcement
- Run `bundle exec standardrb` to check code quality
- Ensure all code passes style checks before submitting

## Type Checking

- Always add RBS definitions for your changes, if not sure run `bundle exec rake steep:check` to see if there are type issues now
- RBS is used for static type checking
- Type definitions are in the `sig/` directory
- Update type definitions when modifying code
- Always run `bundle exec rake steep:check` after any update to RBS files
- Avoid using `untyped` type, use it only when it is not feasible to derive the correct type
- Do not write types like `(nil | Type)`, use `Type?` instead
- See `docs/StaticTypingGuide.md` for details

## Testing

- All changes should be covered by corresponding tests
- Place tests in the `spec/datadog/ci` folder
- Do not use `instance_variable_set` and `instance_variable_get` in tests, use mocking when needed
- Do not make changes to `release_gem_spec.rb` if not asked
- Do not use focused tests feature (fit, fdescribe)
- New contrib folders should have a corresponding Rake task in `Rakefile`
- New test tasks should be added to the test matrix in `TEST_METADATA`
- CI runs tests against multiple Ruby versions (2.7, 3.0, 3.1, 3.2, 3.3, 3.4)
- Always add tests for your changes

## Memories

- `lib/datadog/ci/configuration/settings.rb` file is an exception from RBS typing - these options are not defined anywhere in RBS files
- Always run tests after adding or changing them
- Always run `bundle exec rake steep:check` and fix typing issues after code changes
- Never commit or push changes automatically - all git operations must be reviewed and approved by the user
