module Datadog
  module CI
    module Contrib
      module Knapsack
        class TestExampleDetector < KnapsackPro::TestCaseDetectors::RSpecTestExampleDetector
          def _dd_generate_json_report(rspec_args)
            require "rspec/core"

            cli_format =
              if Gem::Version.new(::RSpec::Core::Version::STRING) < Gem::Version.new("3.6.0")
                require_relative "../formatters/rspec_json_formatter"
                ["--format", ::KnapsackPro::Formatters::RSpecJsonFormatter.to_s]
              else
                ["--format", "json"]
              end

            _dd_ensure_report_dir_exists
            _dd_remove_old_json_report

            args = (rspec_args || "").split
            cli_args_without_formatters = ::KnapsackPro::Adapters::RSpecAdapter.remove_formatters(args)

            # Apply a --format option which overrides formatters from the RSpec custom option files like `.rspec`.
            cli_args = cli_args_without_formatters + cli_format + [
              "--dry-run",
              "--out", _dd_report_path,
              "--default-path", test_dir
            ]

            exit_code = begin
              options = ::RSpec::Core::ConfigurationOptions.new(cli_args)
              ::RSpec::Core::Runner.new(options).run($stderr, $stdout)
            rescue SystemExit => e
              e.status
            end

            return if exit_code.zero?

            command = (["bundle exec rspec"] + cli_args).join(" ")
            Datadog.logger.error("Failed to discover the rspec examples: #{command}")
          end

          def _dd_report_dir
            ".dd/rspec_examples"
          end

          def _dd_report_path
            "#{_dd_report_dir}/rspec_dry_run_report_#{::KnapsackPro::Config::Env.ci_node_index}.json"
          end

          def _dd_ensure_report_dir_exists
            FileUtils.mkdir_p(_dd_report_dir)
          end

          def _dd_remove_old_json_report
            File.delete(_dd_report_path) if File.exist?(_dd_report_path)
          end
        end
      end
    end
  end
end
