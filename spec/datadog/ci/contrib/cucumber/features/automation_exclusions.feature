Feature: Test automation exclusions
  @datadog_prevent_failure_suppression @datadog_no_auto_retry
  Scenario: protected failure
    Then a test automation exclusion failure occurs

  @datadog_prevent_failure_suppression @datadog_no_auto_retry
  Scenario Outline: protected outline <value>
    Then a test automation exclusion failure occurs
    Examples:
      | value |
      | first |
      | second |
