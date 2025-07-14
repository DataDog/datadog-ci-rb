## [Unreleased]

## [1.21.0] - 2025-07-14

### Added

* Support automated flaky test fixing flow for Github Action jobs with pull_request trigger ([#370][])

## [1.20.2] - 2025-07-04

### Fixed

* Fix autoinstrumenting rspec ([#366][])

## [1.20.1] - 2025-07-04

### Fixed

* Fix autoinstrumenting rspec ([#366][])

## [1.20.0] - 2025-07-03

### Added

* Add Datadog output to RSpec documentation formatter ([#355][])
* Add Drone CI support and update CI envs handling ([#349][])

### Fixed

* FIX: send git.tag when requesting library settings if git.branch is not available ([#359][])

## [1.19.0] - 2025-06-16

### Changed

* Impacted tests detection works with line level granularity ([#335][])

### Fixed

* Fix stdin close in Command.popen_with_stdin ([#339][])

## [1.18.0] - 2025-06-06

### Added

* Report end lines for tests ([#327][])

### Changed

* Impacted tests detection: improve a script to determine the base branch sha ([#329][])

## [1.17.0] - 2025-05-19

### Added

* Impacted tests detection ([#318][])

### Changed

* flaky test management: add sha parameter to the tests_properties request ([#321][])
* Send `attempt_to_fix_passed:false` when attempt_to_fix_validation did not succeed ([#320][])

### Fixed

* fix CODEOWNERS parsing issue where "**" wasn't matching zero folders ([#323][])
* fix webmock compatibility of internal telemetry ([#309][])

## [1.16.0] - 2025-04-15


### Added

* agentless logs submission for tests ([#306][])
* lograge support for agentless logs feature ([#308][])
* semantic_logger instrumentation for agentless logs feature ([#311][])
* retry reason "external" ([#312][])

## [1.15.0] - 2025-03-25


### Added

* parallel tests gem support ([#299][])
* implemented attempt to fix flow V2 ([#298][])

### Fixed

* Fix: prevent test impact analysis from skipping flaky tests that are attempted to be fixed ([#301][])
* Fix git commit message extraction to extract multiline commit messages correctly ([#300][])

## [1.14.0] - 2025-03-11

### Added

* Test impact analysis: add rails parallel testing support ([#294][])
* Add parallel testing support to minitest framework ([#295][])

### Changed

* Test knapsack_pro v8 ([#292][])

## [1.13.0] - 2025-02-25

### Added

* Flaky test management support ([#289][])
* Always request the list of known tests and mark new tests ([#286][])

## [1.12.0] - 2025-01-23

### Added

* Add Datadog RUM integration support for browser tests with cuprite driver ([#283][])

## [1.11.0] - 2025-01-02

### Changed

* bump maximum Ruby version to 3.4 ([#275][])
* Use logical test session name as part of test session span's resource instead of test command ([#271][])

### Fixed

* set the max payload size for events to 4.5MB ([#272][])
* Fix inline comments handling when parsing CODEOWNERS files ([#267][])

## [1.10.0] - 2024-12-05

### Added

* Skip before(:all) context hooks when all examples are skipped ([#262][])

## [1.9.0] - 2024-11-26

### Added

* Auto instrumentation ([#259][])

## [1.8.1] - 2024-10-18


### Fixed
* Make --spec-path option available to skipped-tests-estimate cli command ([#250][])

## [1.8.0] - 2024-10-17

### Added
* Add command line tool to compute a percentage of skippable tests for RSpec ([#194][])

### Changed
* Bump gem datadog dependency to 2.4 and update test dependencies ([#248][])
* Optimise LocalRepository.relative_to_root helper to make test impact analysis faster ([#244][])
* Retry HTTP requests on 429 and 5xx responses ([#243][])
* Use correct monotonic clock time if Timecop.mock_process_clock is set ([#242][])

## [1.7.0] - 2024-09-25

### Added
* Report total lines coverage percentage to Datadog ([#240][])
* add source location info to test suites ([#239][])
* Add pull_request extra tags for GitHub Actions ([#238][])

## [1.6.0] - 2024-09-20


### Added
* support logical names for test sessions ([#235][])
* Send internal vCPU count metric ([#236][])

## [1.5.0] - 2024-09-18

### Added
* Retry new tests - parse remote configuration and fetch unique known tests ([#227][])
* early flake detection support for rspec and minitest ([#229][])
* Early flake detection support for Cucumber ([#231][])

### Fixed
* Minor telemetry fixes ([#226][])

## [1.4.1] - 2024-08-28

### Fixed

* fix datadog_cov crash when doing allocation profiling ([#224][])

## [1.4.0] - 2024-08-26

### Added

* Auto test retries for cucumber ([#212][])
* Auto test retries for RSpec ([#213][])
* Auto test retries for minitest ([#214][])
* implement auto test retries RFC ([#219][])

### Changed

* Skip Before/After hooks in cucumber when scenario is skipped by intelligent test runner ([#211][])
* gem datadog 2.3 is now minimal required version ([#220][])
* Enable agentless telemetry when library is running in agentless mode ([#221][])
* Add Ruby 3.4 to the testing matrix ([#217][])
* add different fallbacks for unshallowing remotes ([#218][])
* make itr_enabled config parameter true by default ([#216][])
* RSpec - don't report test errors if rspec process is quitting ([#215][])

## [1.3.0] - 2024-07-30

### Added

* Add test_session metric ([#207][])
* API metrics ([#206][])
* git commands telemetry ([#205][])
* implement ITR metrics for internal telemetry ([#204][])
* Implement code coverage metrics for internal telemetry ([#203][])
* Implement manual_api_events metric ([#202][])
* HTTP transport metrics and minor telemetry tweaks ([#201][])
* Send event_created and event_finished metrics for internal telemetry ([#200][])

## [1.2.0] - 2024-07-16

### Changed
* Expand test impact analysis with allocation tracing ([#197][])

## [1.1.0] - 2024-07-01

### Added
* Ignore Webmock automatically when making HTTP calls ([#193][])

## [1.0.1] - 2024-06-11

### Fixed
* multi threaded code coverage support for datadog_cov ([#189][])
* code coverage extension fixes and improvements ([#171][])

## [1.0.0] - 2024-06-06


### Changed
* automatically trace with correct time even when time is stubbed by timecop ([#185][])
* depend on gem datadog ~> 2.0 ([#190][])

## [1.0.0.beta6] - 2024-05-29

### Added

* Browser tests support via selenium integration ([#183][])

## [1.0.0.beta5] - 2024-05-23

### Changed

* accept gzipped responses from API ([#170][])

### Fixed

* Fix Knapsack Pro integration ([#180][])

## [1.0.0.beta4] - 2024-05-14

### Added

* Knapsack Pro 7/RSpec 3 support ([#172][])
* add settings option to ignore code coverage for bundled gems location ([#174][])
* log an error message if tracing is disabled but test visibility is enabled ([#175][])

### Removed

* remove deprecated use alias ([#173][])

## [1.0.0.beta3] - 2024-04-30

### Added

- "why this test was skipped" feature ([#165])
- custom configurations tags support for ITR ([#166])
- unskippable tests for ITR ([#167])

### Changed

- additional debug logging, do not skip tests when running in forked processes ([#168])

## [1.0.0.beta2] - 2024-04-23

### Added

- Code coverage events writer ([#150])
- Git tree upload - git command line integration ([#151])
- Add Git::SearchCommits api client ([#152])
- Upload packfiles API client ([#153])
- Git tree uploader ([#154])
- Git repository unshallowing logic ([#155])
- Git upload async worker ([#156])
- Reduce ITR-induced code coverage overhead for default branch ([#157])
- Skippable tests api client ([#158])
- Request skippable tests when configuring ITR ([#159])
- Test skipping implementation ([#160])

## [1.0.0.beta1] - 2024-03-25

### Added

- datadog-cov native extension for per test code coverage ([#137])
- citestcov transport to serialize and send code coverage events ([#148])

### Removed

- Ruby 2.1-2.6 support is dropped

## [0.8.3] - 2024-03-20

### Fixed

- fix: cucumber-ruby 9.2 includes breaking change for Cucumber::Core::Test::Result ([#145][])

### Changed

- remove temporary hack and use Core::Remote::Negotiation's new constructor param ([#142][])
- use filter_basic_auth method from Datadog::Core ([#141][])

## [0.8.2] - 2024-03-19

### Fixed

- assign the single running test suite for a test if none found by test suite name ([#139][])

## [0.8.1] - 2024-03-12

### Fixed

- fix minitest instrumentation with mixins ([#134][])

## [0.8.0] - 2024-03-08

### Added

- gzip agent payloads support via evp_proxy/v4 ([#123][])

### Changed

- Add note to README on using VCR ([#122][])

### Fixed

- use framework name as test module name to make test fingerprints stable ([#131][])

## [0.7.0] - 2024-01-26

### Added

- Source code integration ([#95][])
- CODEOWNERS support ([#98][])
- Cucumber scenarios with examples are treated as parametrized tests ([#100][])
- Deduplicate dynamically generated RSpec examples using test.parameters ([#101][])
- Repository name is used as default test service name ([#104][])
- Cucumber v9 support ([#99][])
- ci-queue runner support for minitest ([#110][])
- ci-queue support for rspec ([#112][])

### Fixed

- do not publish sig folder when publishing this gem to prevent steep errors in client applications ([#114][])
- minitest: fix rails parallel test runner ([#115][])
- Test suites and tests skipped by frameworks are correctly reported as skipped to Datadog ([#113][])

### Changed

- Enable test suite level visibility by default (with killswitch) ([#109][])
- Test suite names are more human-readable now ([#105][])
- Remove span_type method in tracer-related models ([#107][])
- Manual tracing API: convert type parameter to keyword in Datadog::CI.trace, remove internal-only methods from public API ([#108][])

## [0.6.0] - 2024-01-03

### Added

- Test suite level visibility instrumentation for RSpec ([#86][])
- Test suite level visibility instrumentation for Cucumber ([#90][])
- Test suite level visibility instrumentation for Minitest framework ([#92][])

### Fixed

- Do not instantiate TestVisibility::Recorder unless CI visibility is enabled ([#89][])

## [0.5.1] - 2023-12-11

### Fixed

- do not collect environment tags when CI is not enabled ([#87][])

### Changed

- Move private classes and modules deeper in module hierarchy ([#85][])
- update appraisal dependencies ([#84][])

## [0.5.0] - 2023-12-06

### Test suite level visibility

This release includes experimental manual API for [test suite level visibility](https://docs.datadoghq.com/continuous_integration/explorer/?tab=testruns#sessions) in Ruby.

Currently test suite level visibility is not used by our instrumentation: it will be released in v0.6.

### Added

- Test suite level visibility: add test session public API ([#72][])
- Test suite level visibility: test module support ([#76][])
- Test suite level visibility: test suites support ([#77][])
- add YARD documentation ([#82][])
- support validation errors for CI spans ([#78][])

### Changed

- Validate DD_SITE variable ([#79][])
- Document how to use WebMock with datadog-ci ([#80][])

### Fixed

- Datadog::CI.trace_test always starts a new trace ([#74][])
- Skip tracing when CI mode disabled and manual API is used ([#75][])

### Removed

- Deprecate operation name setting, change service_name to service in public API ([#81][])

## [0.4.1] - 2023-11-22

### Fixed

- disable 128-bit trace id generation in CI mode ([#70][])

## [0.4.0] - 2023-11-21

### Added

- Public API for manual test instrumentation ([#64][]) ([#61][])

### Changed

- fix tracing instrumentation example in readme ([#60][])

### Fixed

- Remove user credentials from ssh URLs and from GITHUB_REPO_URL environment variable ([#66][])

### Removed

- Remove _dd.measured tag from spans ([#65][])

## [0.3.0] - 2023-10-25

### Added

- Add AWS CodePipeline support for automatic CI tags extraction ([#54][])
- Support test visibility protocol via Datadog Agent with EVP proxy ([#51][])

### Changed

- Migrate to Net::HTTP adapter from Core module of ddtrace gem ([#49][])

## [0.2.0] - 2023-10-05

### Added

- [CIAPP-2959] Agentless mode ([#33][])

### Fixed

- [CIAPP-4278] Fix an issue with emojis in commit message breaking LocalGit tags provider ([#40][])

## [0.1.1] - 2023-09-14

### Fixed

- Fix circular dependencies warnings ([#31][])

## 0.1.0 - 2023-09-12

### Added

- Add cucumber 8.0.0 support ([#7][])
- Docs: contribution documentation ([#14][], [#28][])
- Dev process: issue templates ([#20][])

### Changed

- Validate customer-supplied git tags ([#15][])

### Fixed

- Fix Datadog::CI::Environment to support the new CI specs ([#11][])

### Removed

- Ruby versions < 2.7 no longer supported ([#8][])

[Unreleased]: https://github.com/DataDog/datadog-ci-rb/compare/v1.21.0...main
[1.21.0]: https://github.com/DataDog/datadog-ci-rb/compare/v1.20.2...v1.21.0
[1.20.2]: https://github.com/DataDog/datadog-ci-rb/compare/v1.20.1...v1.20.2
[1.20.1]: https://github.com/DataDog/datadog-ci-rb/compare/v1.20.0...v1.20.1
[1.20.0]: https://github.com/DataDog/datadog-ci-rb/compare/v1.19.0...v1.20.0
[1.19.0]: https://github.com/DataDog/datadog-ci-rb/compare/v1.18.0...v1.19.0
[1.18.0]: https://github.com/DataDog/datadog-ci-rb/compare/v1.17.0...v1.18.0
[1.17.0]: https://github.com/DataDog/datadog-ci-rb/compare/v1.16.0...v1.17.0
[1.16.0]: https://github.com/DataDog/datadog-ci-rb/compare/v1.15.0...v1.16.0
[1.15.0]: https://github.com/DataDog/datadog-ci-rb/compare/v1.14.0...v1.15.0
[1.14.0]: https://github.com/DataDog/datadog-ci-rb/compare/v1.13.0...v1.14.0
[1.13.0]: https://github.com/DataDog/datadog-ci-rb/compare/v1.12.0...v1.13.0
[1.12.0]: https://github.com/DataDog/datadog-ci-rb/compare/v1.11.0...v1.12.0
[1.11.0]: https://github.com/DataDog/datadog-ci-rb/compare/v1.10.0...v1.11.0
[1.10.0]: https://github.com/DataDog/datadog-ci-rb/compare/v1.9.0...v1.10.0
[1.9.0]: https://github.com/DataDog/datadog-ci-rb/compare/v1.8.1...v1.9.0
[1.8.1]: https://github.com/DataDog/datadog-ci-rb/compare/v1.8.0...v1.8.1
[1.8.0]: https://github.com/DataDog/datadog-ci-rb/compare/v1.7.0...v1.8.0
[1.7.0]: https://github.com/DataDog/datadog-ci-rb/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/DataDog/datadog-ci-rb/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/DataDog/datadog-ci-rb/compare/v1.4.1...v1.5.0
[1.4.1]: https://github.com/DataDog/datadog-ci-rb/compare/v1.4.0...v1.4.1
[1.4.0]: https://github.com/DataDog/datadog-ci-rb/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/DataDog/datadog-ci-rb/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/DataDog/datadog-ci-rb/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/DataDog/datadog-ci-rb/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/DataDog/datadog-ci-rb/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/DataDog/datadog-ci-rb/compare/v1.0.0.beta6...v1.0.0
[1.0.0.beta6]: https://github.com/DataDog/datadog-ci-rb/compare/v1.0.0.beta5...v1.0.0.beta6
[1.0.0.beta5]: https://github.com/DataDog/datadog-ci-rb/compare/v1.0.0.beta4...v1.0.0.beta5
[1.0.0.beta4]: https://github.com/DataDog/datadog-ci-rb/compare/v1.0.0.beta3...v1.0.0.beta4
[1.0.0.beta3]: https://github.com/DataDog/datadog-ci-rb/compare/v1.0.0.beta2...v1.0.0.beta3
[1.0.0.beta2]: https://github.com/DataDog/datadog-ci-rb/compare/v1.0.0.beta1...v1.0.0.beta2
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
[#150]: https://github.com/DataDog/datadog-ci-rb/issues/150
[#151]: https://github.com/DataDog/datadog-ci-rb/issues/151
[#152]: https://github.com/DataDog/datadog-ci-rb/issues/152
[#153]: https://github.com/DataDog/datadog-ci-rb/issues/153
[#154]: https://github.com/DataDog/datadog-ci-rb/issues/154
[#155]: https://github.com/DataDog/datadog-ci-rb/issues/155
[#156]: https://github.com/DataDog/datadog-ci-rb/issues/156
[#157]: https://github.com/DataDog/datadog-ci-rb/issues/157
[#158]: https://github.com/DataDog/datadog-ci-rb/issues/158
[#159]: https://github.com/DataDog/datadog-ci-rb/issues/159
[#160]: https://github.com/DataDog/datadog-ci-rb/issues/160
[#165]: https://github.com/DataDog/datadog-ci-rb/issues/165
[#166]: https://github.com/DataDog/datadog-ci-rb/issues/166
[#167]: https://github.com/DataDog/datadog-ci-rb/issues/167
[#168]: https://github.com/DataDog/datadog-ci-rb/issues/168
[#170]: https://github.com/DataDog/datadog-ci-rb/issues/170
[#171]: https://github.com/DataDog/datadog-ci-rb/issues/171
[#172]: https://github.com/DataDog/datadog-ci-rb/issues/172
[#173]: https://github.com/DataDog/datadog-ci-rb/issues/173
[#174]: https://github.com/DataDog/datadog-ci-rb/issues/174
[#175]: https://github.com/DataDog/datadog-ci-rb/issues/175
[#180]: https://github.com/DataDog/datadog-ci-rb/issues/180
[#183]: https://github.com/DataDog/datadog-ci-rb/issues/183
[#185]: https://github.com/DataDog/datadog-ci-rb/issues/185
[#189]: https://github.com/DataDog/datadog-ci-rb/issues/189
[#190]: https://github.com/DataDog/datadog-ci-rb/issues/190
[#193]: https://github.com/DataDog/datadog-ci-rb/issues/193
[#194]: https://github.com/DataDog/datadog-ci-rb/issues/194
[#197]: https://github.com/DataDog/datadog-ci-rb/issues/197
[#200]: https://github.com/DataDog/datadog-ci-rb/issues/200
[#201]: https://github.com/DataDog/datadog-ci-rb/issues/201
[#202]: https://github.com/DataDog/datadog-ci-rb/issues/202
[#203]: https://github.com/DataDog/datadog-ci-rb/issues/203
[#204]: https://github.com/DataDog/datadog-ci-rb/issues/204
[#205]: https://github.com/DataDog/datadog-ci-rb/issues/205
[#206]: https://github.com/DataDog/datadog-ci-rb/issues/206
[#207]: https://github.com/DataDog/datadog-ci-rb/issues/207
[#211]: https://github.com/DataDog/datadog-ci-rb/issues/211
[#212]: https://github.com/DataDog/datadog-ci-rb/issues/212
[#213]: https://github.com/DataDog/datadog-ci-rb/issues/213
[#214]: https://github.com/DataDog/datadog-ci-rb/issues/214
[#215]: https://github.com/DataDog/datadog-ci-rb/issues/215
[#216]: https://github.com/DataDog/datadog-ci-rb/issues/216
[#217]: https://github.com/DataDog/datadog-ci-rb/issues/217
[#218]: https://github.com/DataDog/datadog-ci-rb/issues/218
[#219]: https://github.com/DataDog/datadog-ci-rb/issues/219
[#220]: https://github.com/DataDog/datadog-ci-rb/issues/220
[#221]: https://github.com/DataDog/datadog-ci-rb/issues/221
[#224]: https://github.com/DataDog/datadog-ci-rb/issues/224
[#226]: https://github.com/DataDog/datadog-ci-rb/issues/226
[#227]: https://github.com/DataDog/datadog-ci-rb/issues/227
[#229]: https://github.com/DataDog/datadog-ci-rb/issues/229
[#231]: https://github.com/DataDog/datadog-ci-rb/issues/231
[#235]: https://github.com/DataDog/datadog-ci-rb/issues/235
[#236]: https://github.com/DataDog/datadog-ci-rb/issues/236
[#238]: https://github.com/DataDog/datadog-ci-rb/issues/238
[#239]: https://github.com/DataDog/datadog-ci-rb/issues/239
[#240]: https://github.com/DataDog/datadog-ci-rb/issues/240
[#242]: https://github.com/DataDog/datadog-ci-rb/issues/242
[#243]: https://github.com/DataDog/datadog-ci-rb/issues/243
[#244]: https://github.com/DataDog/datadog-ci-rb/issues/244
[#248]: https://github.com/DataDog/datadog-ci-rb/issues/248
[#250]: https://github.com/DataDog/datadog-ci-rb/issues/250
[#259]: https://github.com/DataDog/datadog-ci-rb/issues/259
[#262]: https://github.com/DataDog/datadog-ci-rb/issues/262
[#267]: https://github.com/DataDog/datadog-ci-rb/issues/267
[#271]: https://github.com/DataDog/datadog-ci-rb/issues/271
[#272]: https://github.com/DataDog/datadog-ci-rb/issues/272
[#275]: https://github.com/DataDog/datadog-ci-rb/issues/275
[#283]: https://github.com/DataDog/datadog-ci-rb/issues/283
[#286]: https://github.com/DataDog/datadog-ci-rb/issues/286
[#289]: https://github.com/DataDog/datadog-ci-rb/issues/289
[#292]: https://github.com/DataDog/datadog-ci-rb/issues/292
[#294]: https://github.com/DataDog/datadog-ci-rb/issues/294
[#295]: https://github.com/DataDog/datadog-ci-rb/issues/295
[#298]: https://github.com/DataDog/datadog-ci-rb/issues/298
[#299]: https://github.com/DataDog/datadog-ci-rb/issues/299
[#300]: https://github.com/DataDog/datadog-ci-rb/issues/300
[#301]: https://github.com/DataDog/datadog-ci-rb/issues/301
[#306]: https://github.com/DataDog/datadog-ci-rb/issues/306
[#308]: https://github.com/DataDog/datadog-ci-rb/issues/308
[#309]: https://github.com/DataDog/datadog-ci-rb/issues/309
[#311]: https://github.com/DataDog/datadog-ci-rb/issues/311
[#312]: https://github.com/DataDog/datadog-ci-rb/issues/312
[#318]: https://github.com/DataDog/datadog-ci-rb/issues/318
[#320]: https://github.com/DataDog/datadog-ci-rb/issues/320
[#321]: https://github.com/DataDog/datadog-ci-rb/issues/321
[#323]: https://github.com/DataDog/datadog-ci-rb/issues/323
[#327]: https://github.com/DataDog/datadog-ci-rb/issues/327
[#329]: https://github.com/DataDog/datadog-ci-rb/issues/329
[#335]: https://github.com/DataDog/datadog-ci-rb/issues/335
[#339]: https://github.com/DataDog/datadog-ci-rb/issues/339
[#349]: https://github.com/DataDog/datadog-ci-rb/issues/349
[#355]: https://github.com/DataDog/datadog-ci-rb/issues/355
[#359]: https://github.com/DataDog/datadog-ci-rb/issues/359
[#366]: https://github.com/DataDog/datadog-ci-rb/issues/366
[#370]: https://github.com/DataDog/datadog-ci-rb/issues/370