Feature: Datadog integration

  Scenario: cucumber scenario
    Given datadog
    And datadog
    Then datadog

  Scenario: undefined scenario
    Given datadog
    And undefined
    Then undefined

  Scenario: pending scenario
    Given datadog
    Then pending

  Scenario: skipped scenario
    Given datadog
    And skip
    Then datadog
