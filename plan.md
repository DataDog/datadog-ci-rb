# Impacted Tests Detection (ITD) Implementation Plan (Revised V2)

This plan outlines the steps to implement the Impacted Tests Detection feature.

**Phase 1: Configuration & Setup**

1.  **Settings:**
    - Define `settings.ci.impacted_tests_detection_enabled` in `lib/datadog/ci/configuration/settings.rb`.
    - Read and prioritize `DD_CIVISIBILITY_IMPACTED_TESTS_DETECTION_ENABLED` env var over the setting.
2.  **Remote Configuration:**
    - Update `lib/datadog/ci/remote/settings.rb` (or relevant parser) to handle the `impacted_tests_enabled` field from the backend settings response, storing the result temporarily before the ITD component is configured.
3.  **Constants:**
    - Define `METRIC_IMPACTED_TESTS_IS_MODIFIED = "impacted_tests.is_modified"` in `lib/datadog/ci/ext/telemetry.rb`.
    - Define `TAG_TEST_IS_MODIFIED = "test.is_modified"` in `lib/datadog/ci/ext/test.rb`.
4.  **RBS & Tests:** Add/update RBS definitions and unit tests for the changes made to `Settings` and `Ext` modules in this phase.

**Phase 2: Git Interaction**

1.  **Enhance Git Module:** Modify `lib/datadog/ci/git/local_repository.rb`.
2.  **CI Environment Detection:** Add logic to detect GitHub Actions and GitLab CI environments based on standard environment variables.
3.  **Base Commit Extraction:** Add methods to retrieve the base commit SHA (e.g., `GITHUB_BASE_REF`, `CI_MERGE_REQUEST_DIFF_BASE_SHA`). If the base commit cannot be determined, return `nil`.
4.  **Changed Files from Diff:**
    - Add a method `get_changed_files_from_diff(base_commit)`.
    - **If `base_commit` is `nil`:** Return `nil` to signal failure.
    - **If `base_commit` is valid:** Execute `git diff -U0 --word-diff=porcelain <base_commit> HEAD`.
    - **Parse Output:** Use the regex `^diff --git a/(?<file>.+) b/(?<file2>.+)$` to extract the `<file>` part for each modified file. Normalize these paths to be relative to the repository root. Store them in a `Set`.
    - Handle potential errors during command execution or parsing, returning `nil` on failure.
    - Return the `Set` of file paths on success.
    - Memoize the result (the `Set` or `nil`) per run based on the `base_commit`.
5.  **RBS & Tests:** Add/update RBS definitions and unit tests for the new Git functionalities implemented in this phase.

**Phase 3: Impacted Tests Detection (ITD) Component**

1.  **Create Module:** Create `lib/datadog/ci/impacted_tests_detection/`.
2.  **Component (`component.rb`):**
    - Define `Datadog::CI::ImpactedTestsDetection::Component`.
    - Inject dependencies: Git repository (`LocalRepository` instance), initial configuration settings.
    - **Initialization:**
      - Store the Git repository dependency.
      - Initialize `@enabled = false`.
      - Initialize `@changed_files = nil`.
    - **Implement `configure(enabled_from_remote:)`:**
      - If `!enabled_from_remote`, set `@enabled = false` and return.
      - Fetch the base commit using the Git module.
      - If base commit is `nil`, log a warning ("ITD disabled: base commit not found") and set `@enabled = false`.
      - Fetch the changed files set by calling `get_changed_files_from_diff(base_commit)`.
      - If changed files set is `nil` (due to error or previous nil base commit), log a warning ("ITD disabled: could not get changed files") and set `@enabled = false`.
      - If successful, store the set in `@changed_files` and set `@enabled = true`.
    - Implement `enabled?`: Returns the value of the internal `@enabled` flag.
    - Implement `modified?(test_file_path)`:
      - Return `false` immediately if `!enabled?` or `@changed_files.nil?`.
      - Normalize the input `test_file_path` to be relative to the repository root.
      - Check if the normalized path exists in the `@changed_files` set. Return `true` or `false`.
    - Implement `Datadog::CI::ImpactedTestsDetection::NullComponent` with `configure` doing nothing, `enabled?` returning `false`, and `modified?` returning `false`.
3.  **Telemetry Helper (`telemetry.rb`):**
    - Create `lib/datadog/ci/impacted_tests_detection/telemetry.rb`.
    - Define `module Telemetry`.
    - Define a class method `self.impacted_test_detected`.
    - Inside the method, call `Utils::Telemetry.inc(Ext::Telemetry::METRIC_IMPACTED_TESTS_IS_MODIFIED, 1)`.
4.  **Settings (`configuration/settings.rb`):** Create this file within the module for potential future ITD-specific settings.
5.  **RBS & Tests:** Add RBS definitions and unit tests for the component, null component, telemetry helper, and configuration settings created/modified in this phase.

**Phase 4: Integrate ITD Check into TestVisibility**

1.  **Modify `lib/datadog/ci/test_visibility/component.rb`:**
    - In the `on_test_started(test)` method, _after_ `Telemetry.event_created(test)` and `mark_test_as_new(test)`:
      - Get the ITD component: `itd = impacted_tests_detection` (using the existing private helper method).
      - Check `if itd.enabled?`.
      - Get the test source file: `source_file = test.get_tag(Ext::Test::TAG_SOURCE_FILE)`.
      - If `source_file` exists:
        - Call `is_modified = itd.modified?(source_file)`.
        - If `is_modified`:
          - Tag the test span: `test.set_tag(Ext::Test::TAG_TEST_IS_MODIFIED, "true")`.
          - Call the telemetry helper: `Datadog::CI::ImpactedTestsDetection::Telemetry.impacted_test_detected`.
2.  **RBS & Tests:** Add/update RBS definitions for `TestVisibility::Component` and integration tests to verify the `test.is_modified` tag is correctly applied based on file modification status and ITD component enablement.

**Phase 5: Test Retries Integration**

1.  **Modify Retry Logic:** Update `lib/datadog/ci/test_retries/component.rb`.
2.  **Check Tag:** In the logic determining if Early Flake Detection retries should run, add a check for the presence and value (`"true"`) of the `Ext::Test::TAG_TEST_IS_MODIFIED` tag on the test span.
3.  **Adjust Condition:** Update the condition to trigger retries if the test `is_new?` OR `is_modified?` (and retries for new/modified tests are enabled via config).
4.  **RBS & Tests:** Update RBS definitions and tests for `TestRetries::Component` to reflect the changes in retry logic.

**Phase 6: Component Wiring & Documentation**

1.  **Wire Component:**
    - Update `lib/datadog/ci/configuration/components.rb`:
      - Require the new component files (`component.rb`, `null_component.rb`, `telemetry.rb`).
      - Add `attr_reader :impacted_tests_detection`.
      - In `initialize`, instantiate `ImpactedTestsDetection::Component` (passing Git module, initial settings) or `NullComponent` based on the _initial_ `settings.ci.impacted_tests_detection_enabled` value. Store it in `@impacted_tests_detection`.
    - Update `lib/datadog/ci/remote/component.rb`:
      - In the method where library configuration is applied after fetching settings (likely `configure` or similar):
        - Determine the final enablement state for ITD (considering `DD_CIVISIBILITY_IMPACTED_TESTS_DETECTION_ENABLED` env var and the `impacted_tests_enabled` remote setting).
        - Call `@impacted_tests_detection.configure(enabled_from_remote: final_enabled_state)`.
2.  **Documentation:** Update `README.md` and potentially add `docs/impacted-tests-detection.md` explaining the feature, configuration, CI provider support, the "best effort" nature if base commit is missing, and limitations.
3.  **RBS:** Update RBS definitions for `Components` and `Remote::Component`.

**Phase 7: Final Checks**

1.  Run `bundle exec standardrb --fix`.
2.  Run `bundle exec rake steep:check` and fix any type errors.
3.  Run `bundle exec rake spec`.
