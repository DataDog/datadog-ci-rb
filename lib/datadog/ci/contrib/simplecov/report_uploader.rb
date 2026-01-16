# frozen_string_literal: true

require_relative "ext"

module Datadog
  module CI
    module Contrib
      module Simplecov
        # Module that hooks into SimpleCov.process_results_and_report_error to upload coverage reports
        module ReportUploader
          def self.included(base)
            base.singleton_class.prepend(ClassMethods)
          end

          module ClassMethods
            def process_results_and_report_error(*args)
              result = super

              upload_coverage_report

              result
            end

            private

            def upload_coverage_report
              return unless datadog_configuration[:enabled]

              code_coverage = ::Datadog.send(:components).code_coverage
              return unless code_coverage.enabled

              serialized_report = read_coverage_result
              return if serialized_report.nil?

              code_coverage.upload(serialized_report: serialized_report, format: Ext::COVERAGE_FORMAT)
            rescue => e
              Datadog.logger.warn("Failed to upload coverage report: #{e.message}")
            end

            def read_coverage_result
              coverage_file = File.join(::SimpleCov.coverage_path, ".resultset.json")

              unless File.exist?(coverage_file)
                Datadog.logger.debug { "Coverage result file not found at #{coverage_file}" }
                return nil
              end

              File.read(coverage_file)
            end

            def datadog_configuration
              Datadog.configuration.ci[:simplecov]
            end
          end
        end
      end
    end
  end
end
