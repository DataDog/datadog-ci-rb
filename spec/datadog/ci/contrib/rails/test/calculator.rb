# frozen_string_literal: true

class Calculator
  def add(a, b)
    Rails.logger.info("Adding #{a} and #{b} #{Datadog::Tracing.log_correlation}")
    a + b
  end

  def subtract(a, b)
    Rails.logger.info("Subtracting #{a} and #{b} #{Datadog::Tracing.log_correlation}")
    a - b
  end

  def multiply(a, b)
    Rails.logger.info("Multiplying #{a} and #{b} #{Datadog::Tracing.log_correlation}")
    a * b
  end

  def divide(a, b)
    Rails.logger.info("Dividing #{a} by #{b} #{Datadog::Tracing.log_correlation}")
    a / b
  end
end
