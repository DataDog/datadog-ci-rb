# Datadog Test Optimization for Ruby

[![Gem Version](https://badge.fury.io/rb/datadog-ci.svg)](https://badge.fury.io/rb/datadog-ci)
[![YARD documentation](https://img.shields.io/badge/YARD-documentation-blue)](https://datadoghq.dev/datadog-ci-rb/)

Datadog's Ruby Library for instrumenting your tests.
Learn more on our [official website](https://docs.datadoghq.com/tests/) and check out our [documentation for this library](https://docs.datadoghq.com/tests/setup/ruby/?tab=cloudciprovideragentless).

## Features

- [Test Visibility](https://docs.datadoghq.com/tests/) - collect metrics and results for your tests
- [Flaky test management](https://docs.datadoghq.com/tests/flaky_management/) - track, triage, and remediate flaky tests across your organization. Quarantine or disable problematic tests to keep known flakes from breaking builds, and create cases and Jira issues to track work toward fixes.
- [Auto test retries](https://docs.datadoghq.com/tests/flaky_tests/auto_test_retries/?tab=ruby) - retrying failing tests up to N times to avoid failing your build due to flaky tests
- [Early flake detection](https://docs.datadoghq.com/tests/flaky_tests/early_flake_detection/?tab=ruby) - Datadog’s test flakiness solution that identifies flakes early by running newly added tests multiple times
- [Test impact analysis](https://docs.datadoghq.com/tests/test_impact_analysis/) - save time by selectively running only tests affected by code changes
- [Test Health](https://docs.datadoghq.com/tests/test_health) - The Test Health dashboard provides analytics to help teams manage and optimize their testing in CI. This includes sections showing the current impact of test flakiness and how Test Optimization is mitigating these problems.
- [Inspect your tests' logs in Datadog](https://docs.datadoghq.com/tests/correlate_logs_and_tests)
- [Enhance developer workflows](https://docs.datadoghq.com/tests/developer_workflows)
- [Add custom measures to your tests](https://docs.datadoghq.com/tests/guides/add_custom_measures/?tab=ruby)
- [Browser tests integration with Datadog RUM](https://docs.datadoghq.com/tests/browser_tests)

## Setup

- [Test visibility setup](https://docs.datadoghq.com/tests/setup/ruby/?tab=cloudciprovideragentless)
- [Test impact analysis setup](https://docs.datadoghq.com/tests/test_impact_analysis/setup/ruby/?tab=cloudciprovideragentless) (test visibility setup is required before setting up test impact analysis)

## Upgrade from ddtrace v1.x

If you used [test visibility for Ruby](https://docs.datadoghq.com/tests/setup/ruby/) with [ddtrace](https://github.com/datadog/dd-trace-rb) gem, check out our [upgrade guide](/docs/UpgradeGuide.md).

## Contributing

See [development guide](/docs/DevelopmentGuide.md), [static typing guide](docs/StaticTypingGuide.md) and [contributing guidelines](/CONTRIBUTING.md).

## Code of Conduct

Everyone interacting in the `Datadog::CI` project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](/CODE_OF_CONDUCT.md).
