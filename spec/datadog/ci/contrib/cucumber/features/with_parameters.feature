Feature: Datadog integration for parametrized tests

  Scenario Outline: scenario with examples
    Given datadog
    When I add <num1> and <num2>
    Then the result should be <total>

  Examples:
    | num1 | num2 | total |
    | 0    | 1    | 1     |
    | 1    | 2    | 3     |
    | 2    | 3    | 5     |