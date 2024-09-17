Feature: When I have flaky test
  Scenario: very flaky scenario
    When flaky
    Then datadog

  Scenario: another flaky scenario
    When flaky
    Then datadog

  Scenario: this scenario just passes
    When datadog
    Then datadog
