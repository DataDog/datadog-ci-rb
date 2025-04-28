# Impacted Tests Detection (ITD) Implementation Todo List

This file breaks down the implementation plan into actionable steps for a coding assistant.

## Phase 1: Configuration & Setup

- [x] **Prompt 1.1:** In `lib/datadog/ci/configuration/settings.rb`, define a new CI setting `impacted_tests_detection_enabled` (boolean, default `false`).
- [x] **Prompt 1.2:** In `lib/datadog/ci/configuration/settings.rb`, ensure the value of `impacted_tests_detection_enabled` is overridden by the environment variable `DD_CIVISIBILITY_IMPACTED_TESTS_DETECTION_ENABLED` if it is set. Parse the env var as a boolean.
- [x] **Prompt 1.3:** Update the remote settings parsing logic in `lib/datadog/ci/remote/library_settings.rb` to recognize and store the `impacted_tests_enabled` (boolean) field from the backend response. This value will be used later to configure the ITD component.
- [x] **Prompt 1.4:** In `lib/datadog/ci/ext/telemetry.rb`, define a new constant `METRIC_IMPACTED_TESTS_IS_MODIFIED = "impacted_tests.is_modified"`.
- [x] **Prompt 1.5:** In `lib/datadog/ci/ext/test.rb`, define a new constant `TAG_TEST_IS_MODIFIED = "test.is_modified"`.

## Phase 2: Git Interaction

- [x] **Prompt 2.1:** Add a `base_commit_sha` method to `datadog/ci/span.rb`. It returns the value of tag `Datadog::CI::Ext::Git::TAG_PULL_REQUEST_BASE_BRANCH_SHA`.
- [x] **Prompt 2.2:** Implement additional_tags method for `datadog/ci/ext/environment/providers/gitlab.rb` similarly to
      Github Actions (`datadog/ci/ext/environment/providers/github_actions.rb`). Use the following env variables available in Gitlab: CI_MERGE_REQUEST_TARGET_BRANCH_NAME, CI_MERGE_REQUEST_TARGET_BRANCH_SHA, CI_MERGE_REQUEST_SOURCE_BRANCH_SHA.
- [x] **Prompt 2.3:** In `lib/datadog/ci/git/local_repository.rb`, add a method `get_changed_files_from_diff(base_commit)`.
  - If `base_commit` is `nil`, return `nil`.
  - Execute the command `git diff -U0 --word-diff=porcelain <base_commit>`.
  - Parse the output using the regex `^diff --git a/(?<file>.+) b/(?<file2>.+)$` to extract modified file paths.
  - Normalize these paths to be relative to the repository root.
  - Handle potential errors during command execution or parsing, returning `nil` if errors occur.
  - Return a `Set` containing the normalized file paths on success.

## Phase 3: Impacted Tests Detection (ITD) Component

- [x] **Prompt 3.1:** Create the directory `lib/datadog/ci/impacted_tests_detection/`.
- [x] **Prompt 3.2:** Create `lib/datadog/ci/impacted_tests_detection/component.rb`. Define `module Datadog::CI::ImpactedTestsDetection` and within it, the class `Component`.
  - Add an initializer that accepts a `enabled:` property (boolean).
  - Initialize instance variables `@enabled = enabled` and `@changed_files = nil`.
- [x] **Prompt 3.3:** In `ImpactedTestsDetection::Component`, implement the `configure(library_settings, test_session)` method:
  - If `library_settings.impacted_tests_enabled?` is false, set `@enabled = false` and return.
  - Obtain the `base_commit_sha` from `test_session.base_commit_sha`.
  - If the base commit is `nil`, log a warning ("ITD disabled: base commit not found") using `Datadog.logger`, set `@enabled = false`, and return.
  - Call `LocalRepository.get_changed_files_from_diff` with the base commit.
  - If the result is `nil`, log a warning ("ITD disabled: could not get changed files"), set `@enabled = false`, and return.
  - If successful, store the returned `Set` in `@changed_files` and set `@enabled = true`.
- [x] **Prompt 3.4:** In `ImpactedTestsDetection::Component`, implement the `enabled?` method to return the value of `@enabled`.
- [x] **Prompt 3.5:** In `ImpactedTestsDetection::Component`, implement the `modified?(test_span)` method where `test_span` is `Datadog::CI::Test`:
  - Return `false` if `!enabled?`.
  - Return `false` if `test_span.source_file` is nil.
  - Check if `test_span.source_file` exists in the `@changed_files` set. Return `true` or `false`.
- [x] **Prompt 3.6:** In `lib/datadog/ci/impacted_tests_detection/null_component.rb`, define `ImpactedTestsDetection::NullComponent` with a no-op `configure` method, an `enabled?` method returning `false`, and a `modified?` method returning `false`, and a `tag_modified_test(test_span)` method doing nothing.
- [ ] **Prompt 3.7:** Create `lib/datadog/ci/impacted_tests_detection/telemetry.rb`. Define `module Datadog::CI::ImpactedTestsDetection::Telemetry`. Add a class method `self.impacted_test_detected` that calls `Datadog::CI::Utils::Telemetry.inc(Datadog::CI::Ext::Telemetry::METRIC_IMPACTED_TESTS_IS_MODIFIED, 1)`.
- [ ] **Prompt 3.8:** In `ImpactedTestsDetection::Component`, implement the `tag_modified_test(test_span)` method where `test_span` is `Datadog::CI::Test`. If `modified?(test_span)` is true, it sets the `test.is_modified` tag (look into Datadog::CI::Ext::Test for a constant) and calls `impacted_test_detected` method on `Datadog::CI::ImpactedTestsDetection::Telemetry`.

## Phase 4: Component Wiring

- [ ] **Prompt 6.1:** Modify `lib/datadog/ci/configuration/components.rb`:
  - Add `require_relative` statements for the new ITD component files (`../impacted_tests_detection/component`, `../impacted_tests_detection/null_component`, `../impacted_tests_detection/telemetry`).
  - Add `impacted_tests_detection` to the `attr_reader` list.
  - In the `initialize` method, instantiate the correct ITD component (`ImpactedTestsDetection::Component` or `NullComponent`) based on the _initial_ value of `settings.ci.impacted_tests_detection_enabled`. Pass the Git repository instance (`Git::LocalRepository.new`) and initial settings as dependencies to the `Component` initializer. Store the instance in `@impacted_tests_detection`.
- [ ] **Prompt 6.2:** Modify `lib/datadog/ci/remote/component.rb`. Find the method responsible for applying library settings after they are fetched from the backend (e.g., a method named `configure` or similar within that component).
  - Inside this method, determine the final enablement state for ITD by checking the `DD_CIVISIBILITY_IMPACTED_TESTS_DETECTION_ENABLED` environment variable first, and then the `impacted_tests_enabled` setting received from the remote configuration.
  - Call the `configure` method on the ITD component instance: `Datadog.components.impacted_tests_detection.configure(enabled_from_remote: final_enabled_state)`.

## Phase 5: Integrate ITD Check into TestVisibility

- [ ] **Prompt 4.1:** Modify `lib/datadog/ci/test_visibility/component.rb`. In the `on_test_started(test)` method, find the section _after_ `mark_test_as_new(test)`. Add the following logic:
  - Get the ITD component instance using the existing `impacted_tests_detection` helper method (`itd = impacted_tests_detection`).
  - Check `if itd.enabled?`.
  - Inside the check, get the test's source file: `source_file = test.get_tag(Datadog::CI::Ext::Test::TAG_SOURCE_FILE)`.
  - If `source_file` is not nil:
    - Call `is_modified = itd.modified?(source_file)`.
    - If `is_modified` is true:
      - Set the tag: `test.set_tag(Datadog::CI::Ext::Test::TAG_TEST_IS_MODIFIED, "true")`.
      - Increment the metric: `Datadog::CI::ImpactedTestsDetection::Telemetry.impacted_test_detected`.

## Phase 6: Test Retries Integration

- [ ] **Prompt 5.1:** Modify `lib/datadog/ci/test_retries/component.rb`. Locate the logic that decides whether to perform Early Flake Detection retries (it currently checks `test.is_new?`).
- [ ] **Prompt 5.2:** Modify the condition from Prompt 5.1. In addition to checking if the test `is_new?`, also check if the test span has the tag `Datadog::CI::Ext::Test::TAG_TEST_IS_MODIFIED` set to `"true"`. The retry should happen if _either_ condition is met (and relevant retry settings are enabled).
