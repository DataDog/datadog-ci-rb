# Impacted Tests Detection (ITD) Implementation Todo List

This file breaks down the implementation plan into actionable steps for a coding assistant.

## Phase 1: Configuration & Setup

- [x] **Prompt 1.1:** In `lib/datadog/ci/configuration/settings.rb`, define a new CI setting `impacted_tests_detection_enabled` (boolean, default `false`).
- [x] **Prompt 1.2:** In `lib/datadog/ci/configuration/settings.rb`, ensure the value of `impacted_tests_detection_enabled` is overridden by the environment variable `DD_CIVISIBILITY_IMPACTED_TESTS_DETECTION_ENABLED` if it is set. Parse the env var as a boolean.
- [ ] **Prompt 1.3:** Update the remote settings parsing logic (likely in `lib/datadog/ci/remote/settings.rb` or a related file) to recognize and store the `impacted_tests_enabled` (boolean) field from the backend response. This value will be used later to configure the ITD component.
- [ ] **Prompt 1.4:** In `lib/datadog/ci/ext/telemetry.rb`, define a new constant `METRIC_IMPACTED_TESTS_IS_MODIFIED = "impacted_tests.is_modified"`.
- [ ] **Prompt 1.5:** In `lib/datadog/ci/ext/test.rb`, define a new constant `TAG_TEST_IS_MODIFIED = "test.is_modified"`.

## Phase 2: Git Interaction

- [ ] **Prompt 2.1:** In `lib/datadog/ci/git/local_repository.rb`, add logic to detect if running within GitHub Actions or GitLab CI by checking standard environment variables (e.g., `GITHUB_ACTIONS`, `GITLAB_CI`).
- [ ] **Prompt 2.2:** In `lib/datadog/ci/git/local_repository.rb`, add a method `base_commit_sha` that attempts to retrieve the base commit SHA for the current PR/MR from GitHub Actions (`GITHUB_BASE_REF`) or GitLab (`CI_MERGE_REQUEST_DIFF_BASE_SHA`). Return the SHA string if found, otherwise return `nil`.
- [ ] **Prompt 2.3:** In `lib/datadog/ci/git/local_repository.rb`, add a method `get_changed_files_from_diff(base_commit)`.
  - If `base_commit` is `nil`, return `nil`.
  - Execute the command `git diff -U0 --word-diff=porcelain <base_commit>`.
  - Parse the output using the regex `^diff --git a/(?<file>.+) b/(?<file2>.+)$` to extract modified file paths.
  - Normalize these paths to be relative to the repository root.
  - Handle potential errors during command execution or parsing, returning `nil` if errors occur.
  - Return a `Set` containing the normalized file paths on success.
- [ ] **Prompt 2.4:** Add memoization to the `get_changed_files_from_diff` method, caching the result based on the `base_commit` argument for the duration of the object's lifetime.

## Phase 3: Impacted Tests Detection (ITD) Component

- [ ] **Prompt 3.1:** Create the directory `lib/datadog/ci/impacted_tests_detection/`.
- [ ] **Prompt 3.2:** Create `lib/datadog/ci/impacted_tests_detection/component.rb`. Define `module Datadog::CI::ImpactedTestsDetection` and within it, the class `Component`.
  - Add an initializer that accepts a git repository instance (`Datadog::CI::Git::LocalRepository`) and initial settings.
  - Store the git repository dependency.
  - Initialize instance variables `@enabled = false` and `@changed_files = nil`.
- [ ] **Prompt 3.3:** In `ImpactedTestsDetection::Component`, implement the `configure(enabled_from_remote:)` method:
  - If `enabled_from_remote` is false, set `@enabled = false` and return.
  - Call the `base_commit_sha` method from the Git repository instance.
  - If the base commit is `nil`, log a warning ("ITD disabled: base commit not found") using `Datadog.logger`, set `@enabled = false`, and return.
  - Call `get_changed_files_from_diff` with the base commit.
  - If the result is `nil`, log a warning ("ITD disabled: could not get changed files"), set `@enabled = false`, and return.
  - If successful, store the returned `Set` in `@changed_files` and set `@enabled = true`.
- [ ] **Prompt 3.4:** In `ImpactedTestsDetection::Component`, implement the `enabled?` method to return the value of `@enabled`.
- [ ] **Prompt 3.5:** In `ImpactedTestsDetection::Component`, implement the `modified?(test_file_path)` method:
  - Return `false` if `!enabled?` or `@changed_files.nil?`.
  - Normalize the input `test_file_path` (which might be absolute) to be relative to the Git repository root (similar to how paths are stored in `@changed_files`). You might need access to the Git repository root path for this.
  - Check if the normalized path exists in the `@changed_files` set. Return `true` or `false`.
- [ ] **Prompt 3.6:** In `lib/datadog/ci/impacted_tests_detection/null_component.rb`, define `ImpactedTestsDetection::NullComponent` with a no-op `configure` method, an `enabled?` method returning `false`, and a `modified?` method returning `false`.
- [ ] **Prompt 3.7:** Create `lib/datadog/ci/impacted_tests_detection/telemetry.rb`. Define `module Datadog::CI::ImpactedTestsDetection::Telemetry`. Add a class method `self.impacted_test_detected` that calls `Datadog::CI::Utils::Telemetry.inc(Datadog::CI::Ext::Telemetry::METRIC_IMPACTED_TESTS_IS_MODIFIED, 1)`.
- [ ] **Prompt 3.8:** Create an empty file `lib/datadog/ci/impacted_tests_detection/configuration/settings.rb`.

## Phase 4: Integrate ITD Check into TestVisibility

- [ ] **Prompt 4.1:** Modify `lib/datadog/ci/test_visibility/component.rb`. In the `on_test_started(test)` method, find the section _after_ `mark_test_as_new(test)`. Add the following logic:
  - Get the ITD component instance using the existing `impacted_tests_detection` helper method (`itd = impacted_tests_detection`).
  - Check `if itd.enabled?`.
  - Inside the check, get the test's source file: `source_file = test.get_tag(Datadog::CI::Ext::Test::TAG_SOURCE_FILE)`.
  - If `source_file` is not nil:
    - Call `is_modified = itd.modified?(source_file)`.
    - If `is_modified` is true:
      - Set the tag: `test.set_tag(Datadog::CI::Ext::Test::TAG_TEST_IS_MODIFIED, "true")`.
      - Increment the metric: `Datadog::CI::ImpactedTestsDetection::Telemetry.impacted_test_detected`.

## Phase 5: Test Retries Integration

- [ ] **Prompt 5.1:** Modify `lib/datadog/ci/test_retries/component.rb`. Locate the logic that decides whether to perform Early Flake Detection retries (it currently checks `test.is_new?`).
- [ ] **Prompt 5.2:** Modify the condition from Prompt 5.1. In addition to checking if the test `is_new?`, also check if the test span has the tag `Datadog::CI::Ext::Test::TAG_TEST_IS_MODIFIED` set to `"true"`. The retry should happen if _either_ condition is met (and relevant retry settings are enabled).

## Phase 6: Component Wiring & Documentation

- [ ] **Prompt 6.1:** Modify `lib/datadog/ci/configuration/components.rb`:
  - Add `require_relative` statements for the new ITD component files (`../impacted_tests_detection/component`, `../impacted_tests_detection/null_component`, `../impacted_tests_detection/telemetry`).
  - Add `impacted_tests_detection` to the `attr_reader` list.
  - In the `initialize` method, instantiate the correct ITD component (`ImpactedTestsDetection::Component` or `NullComponent`) based on the _initial_ value of `settings.ci.impacted_tests_detection_enabled`. Pass the Git repository instance (`Git::LocalRepository.new`) and initial settings as dependencies to the `Component` initializer. Store the instance in `@impacted_tests_detection`.
- [ ] **Prompt 6.2:** Modify `lib/datadog/ci/remote/component.rb`. Find the method responsible for applying library settings after they are fetched from the backend (e.g., a method named `configure` or similar within that component).
  - Inside this method, determine the final enablement state for ITD by checking the `DD_CIVISIBILITY_IMPACTED_TESTS_DETECTION_ENABLED` environment variable first, and then the `impacted_tests_enabled` setting received from the remote configuration.
  - Call the `configure` method on the ITD component instance: `Datadog.components.impacted_tests_detection.configure(enabled_from_remote: final_enabled_state)`.
- [ ] **Prompt 6.3:** Update documentation:
  - Add a section to `README.md` explaining the Impacted Tests Detection feature, the `DD_CIVISIBILITY_IMPACTED_TESTS_DETECTION_ENABLED` environment variable, and the corresponding remote setting `impacted_tests_enabled`. Mention supported CI providers and the fallback behavior if the base commit cannot be determined.
  - _(Optional)_ Create a more detailed `docs/impacted-tests-detection.md` if needed.

## Phase 7: Final Checks

- [ ] **Prompt 7.1:** Run `bundle exec standardrb --fix` to ensure code style compliance. Address any reported issues.
- [ ] **Prompt 7.2:** Run `bundle exec rake steep:check` to verify type correctness. Address any reported type errors.
- [ ] **Prompt 7.3:** Run `bundle exec rake spec` to execute the test suite. Ensure all tests pass. Address any failures.
