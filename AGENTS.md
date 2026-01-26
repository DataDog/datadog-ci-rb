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

If new files in the repository are created, run `git add -A` before running tests (otherwise `release_gem_spec.rb` will fail)

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

The library uses a component-based architecture with several key systems:

1. **Test Instrumentation System**:

   - Hooks into different test frameworks (RSpec, Minitest, Cucumber, etc.)
   - Tracks test execution, results, and metadata
   - Exposes spans and metrics for each test

2. **Test Impact Analysis**:

   - Uses git operations to identify changed files between commits
   - Tracks code coverage via a native C extension
   - Correlates tests with code they execute
   - Enables skipping tests not impacted by code changes

3. **Transport Layer**:

   - Sends test data to Datadog backend
   - Uses compression and batching for efficiency
   - Supports different CI environments

4. **Configuration System**:
   - Provides flexible settings for all features
   - Supports remote configuration via Datadog backend
   - Detects CI providers automatically

When working with this codebase, pay special attention to:

- Integration with testing frameworks, which often use dynamic patching
- The C extension in `ext/datadog_ci_native` for performance-critical code coverage and for accessing end lines info from compiled iseqs
- Multi-threading safety for background workers and data collection
- Compatibility across different Ruby versions and testing frameworks

### Project Structure

- `lib/datadog/ci` - implementation of the library
- `lib/datadog/ci.rb` - Main entry point and public API
- `lib/datadog/ci/auto_instrument.rb` - Automated instrumentation entry point
- `lib/datadog/ci/datadog-ci.gemspec` - Gem specification
- `spec/` - Library test suite
- `ext/` - Native extension for test impact analysis
- `docs/` - Developer documentation

### Core data model

- `lib/datadog/ci/span.rb` - base class for core models
- `lib/datadog/ci/concurrent_span.rb` - Thread-safe base model class
- `lib/datadog/ci/test.rb` - Represents a single test execution
- `lib/datadog/ci/test_suite.rb` - represents a test suite
- `lib/datadog/ci/test_module.rb` - Logical component of a test session (currently aligns fully with a test session)
- `lib/datadog/ci/test_session.rb` - Represents an entire testing session
- `lib/datadog/ci/contrib` - Framework-specific integrations

### Library components

- `lib/datadog/ci/configuration/components.rb` - Centralized library entry point for initializing configuration and components
- `lib/datadog/ci/configuration` - Configuration management
- `lib/datadog/ci/ext` - Constants for tags and attributes
- `lib/datadog/ci/ext/environment` - Extractors for environment information from CI providers and git
- `lib/datadog/ci/transport` - Manages communication with Datadog backend services
- `lib/datadog/ci/test_visibility` - Core component tracing test execution details
- `lib/datadog/ci/remote` - Retrieves remote settings from Datadog backend
- `lib/datadog/ci/git` - Collects Git repository details and uploads commit information to Datadog for test impact analysis
- `lib/datadog/ci/test_impact_analysis` - Determines skippable tests from backend information (actual skipping handled by framework integrations)
- `lib/datadog/ci/test_retries` - Marks tests for automatic retries or early flake detection
- `lib/datadog/ci/test_management` - Manages test statuses (quarantined, disabled) fetched from backend
- `lib/datadog/ci/logs` - Forwards Ruby logging output to Datadog Logs

## Framework Integrations

The library supports various test frameworks, test runners, and other libraries through contrib modules, such as:

- RSpec
- Minitest
- Cucumber
- ActiveSupport
- Selenium, etc

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
- CI runs tests against multiple Ruby versions (2.7, 3.0, 3.1, 3.2, 3.3, 3.4, jruby-9)
- Always add tests for your changes

## Memories

- `lib/datadog/ci/configuration/settings.rb` file is an exception from RBS typing - these options are not defined anywhere in RBS files
- Always run tests after adding or changing them
- Always run `bundle exec rake steep:check` and fix typing issues after code changes
- Never commit or push changes automatically - all git operations must be reviewed and approved by the user
