## [Unreleased]

## [1.0.0.beta1] - 2024-03-25

### Added

* datadog-cov native extension for per test code coverage ([#137])
* citestcov transport to serialize and send code coverage events ([#148])

### Removed

* Ruby 2.1-2.6 support is dropped

## [0.8.3] - 2024-03-20

### Fixed

* fix: cucumber-ruby 9.2 includes breaking change for Cucumber::Core::Test::Result ([#145][])

### Changed

* remove temporary hack and use Core::Remote::Negotiation's new constructor param ([#142][])
* use filter_basic_auth method from Datadog::Core ([#141][])

## [0.8.2] - 2024-03-19

### Fixed

* assign the single running test suite for a test if none found by test suite name ([#139][])

## [0.8.1] - 2024-03-12

### Fixed

* fix minitest instrumentation with mixins ([#134][])

## [0.8.0] - 2024-03-08

### Added

* gzip agent payloads support via evp_proxy/v4 ([#123][])

### Changed

* Add note to README on using VCR ([#122][])

### Fixed

* use framework name as test module name to make test fingerprints stable ([#131][])

## [0.7.0] - 2024-01-26

### Added

* Source code integration ([#95][])
* CODEOWNERS support ([#98][])
* Cucumber scenarios with examples are treated as parametrized tests ([#100][])
* Deduplicate dynamically generated RSpec examples using test.parameters ([#101][])
* Repository name is used as default test service name ([#104][])
* Cucumber v9 support ([#99][])
* ci-queue runner support for minitest ([#110][])
* ci-queue support for rspec ([#112][])

### Fixed

* do not publish sig folder when publishing this gem to prevent steep errors in client applications ([#114][])
* minitest: fix rails parallel test runner ([#115][])
* Test suites and tests skipped by frameworks are correctly reported as skipped to Datadog ([#113][])

### Changed

* Enable test suite level visibility by default (with killswitch) ([#109][])
* Test suite names are more human-readable now ([#105][])
* Remove span_type method in tracer-related models ([#107][])
* Manual tracing API: convert type parameter to keyword in Datadog::CI.trace, remove internal-only methods from public API ([#108][])

## [0.6.0] - 2024-01-03

### Added

* Test suite level visibility instrumentation for RSpec ([#86][])
* Test suite level visibility instrumentation for Cucumber ([#90][])
* Test suite level visibility instrumentation for Minitest framework ([#92][])

### Fixed

* Do not instantiate TestVisibility::Recorder unless CI visibility is enabled ([#89][])

## [0.5.1] - 2023-12-11

### Fixed

* do not collect environment tags when CI is not enabled ([#87][])

### Changed

* Move private classes and modules deeper in module hierarchy ([#85][])
* update appraisal dependencies ([#84][])

## [0.5.0] - 2023-12-06

### Test suite level visibility

This release includes experimental manual API for [test suite level visibility](https://docs.datadoghq.com/continuous_integration/explorer/?tab=testruns#sessions) in Ruby.

Currently test suite level visibility is not used by our instrumentation: it will be released in v0.6.

### Added

* Test suite level visibility: add test session public API ([#72][])
* Test suite level visibility: test module support ([#76][])
* Test suite level visibility: test suites support ([#77][])
* add YARD documentation ([#82][])
* support validation errors for CI spans ([#78][])

### Changed

* Validate DD_SITE variable ([#79][])
* Document how to use WebMock with datadog-ci ([#80][])

### Fixed

* Datadog::CI.trace_test always starts a new trace ([#74][])
* Skip tracing when CI mode disabled and manual API is used ([#75][])

### Removed

* Deprecate operation name setting, change service_name to service in public API ([#81][])

## [0.4.1] - 2023-11-22

### Fixed

* disable 128-bit trace id generation in CI mode ([#70][])

## [0.4.0] - 2023-11-21

### Added

* Public API for manual test instrumentation ([#64][]) ([#61][])

### Changed

* fix tracing instrumentation example in readme ([#60][])

### Fixed

* Remove user credentials from ssh URLs and from GITHUB_REPO_URL environment variable ([#66][])

### Removed

* Remove _dd.measured tag from spans ([#65][])

## [0.3.0] - 2023-10-25

### Added

* Add AWS CodePipeline support for automatic CI tags extraction ([#54][])
* Support test visibility protocol via Datadog Agent with EVP proxy ([#51][])

### Changed

* Migrate to Net::HTTP adapter from Core module of ddtrace gem ([#49][])

## [0.2.0] - 2023-10-05

### Added

* [CIAPP-2959] Agentless mode ([#33][])

### Fixed

* [CIAPP-4278] Fix an issue with emojis in commit message breaking LocalGit tags provider ([#40][])

## [0.1.1] - 2023-09-14

### Fixed

* Fix circular dependencies warnings ([#31][])

## 0.1.0 - 2023-09-12

### Added

* Add cucumber 8.0.0 support ([#7][])
* Docs: contribution documentation ([#14][], [#28][])
* Dev process: issue templates ([#20][])

### Changed

* Validate customer-supplied git tags ([#15][])

### Fixed

* Fix Datadog::CI::Environment to support the new CI specs ([#11][])

### Removed

* Ruby versions < 2.7 no longer supported ([#8][])

[Unreleased]: https://github.com/DataDog/datadog-ci-rb/compare/v0.8.3...main
[1.0.0.beta1]: https://github.com/DataDog/datadog-ci-rb/compare/v0.8.3...v1.0.0.beta1
[0.8.3]: https://github.com/DataDog/datadog-ci-rb/compare/v0.8.2...v0.8.3
[0.8.2]: https://github.com/DataDog/datadog-ci-rb/compare/v0.8.1...v0.8.2
[0.8.1]: https://github.com/DataDog/datadog-ci-rb/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/DataDog/datadog-ci-rb/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/DataDog/datadog-ci-rb/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/DataDog/datadog-ci-rb/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/DataDog/datadog-ci-rb/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/DataDog/datadog-ci-rb/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/DataDog/datadog-ci-rb/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/DataDog/datadog-ci-rb/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/DataDog/datadog-ci-rb/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/DataDog/datadog-ci-rb/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/DataDog/datadog-ci-rb/compare/v0.1.0...v0.1.1

<!--- The following link definition list is generated by PimpMyChangelog --->
[#7]: https://github.com/DataDog/datadog-ci-rb/issues/7
[#8]: https://github.com/DataDog/datadog-ci-rb/issues/8
[#11]: https://github.com/DataDog/datadog-ci-rb/issues/11
[#14]: https://github.com/DataDog/datadog-ci-rb/issues/14
[#15]: https://github.com/DataDog/datadog-ci-rb/issues/15
[#20]: https://github.com/DataDog/datadog-ci-rb/issues/20
[#28]: https://github.com/DataDog/datadog-ci-rb/issues/28
[#31]: https://github.com/DataDog/datadog-ci-rb/issues/31
[#33]: https://github.com/DataDog/datadog-ci-rb/issues/33
[#40]: https://github.com/DataDog/datadog-ci-rb/issues/40
[#49]: https://github.com/DataDog/datadog-ci-rb/issues/49
[#51]: https://github.com/DataDog/datadog-ci-rb/issues/51
[#54]: https://github.com/DataDog/datadog-ci-rb/issues/54
[#60]: https://github.com/DataDog/datadog-ci-rb/issues/60
[#61]: https://github.com/DataDog/datadog-ci-rb/issues/61
[#64]: https://github.com/DataDog/datadog-ci-rb/issues/64
[#65]: https://github.com/DataDog/datadog-ci-rb/issues/65
[#66]: https://github.com/DataDog/datadog-ci-rb/issues/66
[#70]: https://github.com/DataDog/datadog-ci-rb/issues/70
[#72]: https://github.com/DataDog/datadog-ci-rb/issues/72
[#74]: https://github.com/DataDog/datadog-ci-rb/issues/74
[#75]: https://github.com/DataDog/datadog-ci-rb/issues/75
[#76]: https://github.com/DataDog/datadog-ci-rb/issues/76
[#77]: https://github.com/DataDog/datadog-ci-rb/issues/77
[#78]: https://github.com/DataDog/datadog-ci-rb/issues/78
[#79]: https://github.com/DataDog/datadog-ci-rb/issues/79
[#80]: https://github.com/DataDog/datadog-ci-rb/issues/80
[#81]: https://github.com/DataDog/datadog-ci-rb/issues/81
[#82]: https://github.com/DataDog/datadog-ci-rb/issues/82
[#84]: https://github.com/DataDog/datadog-ci-rb/issues/84
[#85]: https://github.com/DataDog/datadog-ci-rb/issues/85
[#86]: https://github.com/DataDog/datadog-ci-rb/issues/86
[#87]: https://github.com/DataDog/datadog-ci-rb/issues/87
[#89]: https://github.com/DataDog/datadog-ci-rb/issues/89
[#90]: https://github.com/DataDog/datadog-ci-rb/issues/90
[#92]: https://github.com/DataDog/datadog-ci-rb/issues/92
[#95]: https://github.com/DataDog/datadog-ci-rb/issues/95
[#98]: https://github.com/DataDog/datadog-ci-rb/issues/98
[#99]: https://github.com/DataDog/datadog-ci-rb/issues/99
[#100]: https://github.com/DataDog/datadog-ci-rb/issues/100
[#101]: https://github.com/DataDog/datadog-ci-rb/issues/101
[#104]: https://github.com/DataDog/datadog-ci-rb/issues/104
[#105]: https://github.com/DataDog/datadog-ci-rb/issues/105
[#107]: https://github.com/DataDog/datadog-ci-rb/issues/107
[#108]: https://github.com/DataDog/datadog-ci-rb/issues/108
[#109]: https://github.com/DataDog/datadog-ci-rb/issues/109
[#110]: https://github.com/DataDog/datadog-ci-rb/issues/110
[#112]: https://github.com/DataDog/datadog-ci-rb/issues/112
[#113]: https://github.com/DataDog/datadog-ci-rb/issues/113
[#114]: https://github.com/DataDog/datadog-ci-rb/issues/114
[#115]: https://github.com/DataDog/datadog-ci-rb/issues/115
[#122]: https://github.com/DataDog/datadog-ci-rb/issues/122
[#123]: https://github.com/DataDog/datadog-ci-rb/issues/123
[#131]: https://github.com/DataDog/datadog-ci-rb/issues/131
[#134]: https://github.com/DataDog/datadog-ci-rb/issues/134
[#137]: https://github.com/DataDog/datadog-ci-rb/issues/137
[#139]: https://github.com/DataDog/datadog-ci-rb/issues/139
[#141]: https://github.com/DataDog/datadog-ci-rb/issues/141
[#142]: https://github.com/DataDog/datadog-ci-rb/issues/142
[#145]: https://github.com/DataDog/datadog-ci-rb/issues/145
[#148]: https://github.com/DataDog/datadog-ci-rb/issues/148
