Feature: All scenarios are skipped

  Scenario: undefined scenario
    Given datadog
    And undefined
    Then undefined

  Scenario: skipped scenario
    Given datadog
    And skip
    Then datadog
