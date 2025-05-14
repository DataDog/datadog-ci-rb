# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is Datadog's Test Optimization library for Ruby, which instruments tests to provide visibility into CI pipelines and optimize test runs. The library includes features like:

- Test visibility (metrics and results collection)
- Test impact analysis (selectively running tests affected by code changes)
- Flaky test management
- Auto test retries
- Early flake detection
- Code coverage tracking

## Development Commands

### Setting up Development Environment

```bash
# Install dependencies
bundle install

# Install test dependencies
bundle exec appraisal install
```

### Running Tests

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
- The C extension in `ext/datadog_cov` for performance-critical code coverage
- Multi-threading safety for background workers and data collection
- Compatibility across different Ruby versions and testing frameworks
