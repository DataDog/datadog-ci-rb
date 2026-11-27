# frozen_string_literal: true

module Datadog
  module CI
    module NativeBuild
      # Chooses the private VM headers that line coverage compiles against, among the
      # header directories that datadog-ruby_core_source packages, such as
      # "ruby-3.3.5-p100" or "ruby-4.1.0-preview1". Used by extconf.rb only.
      module LineCoverageHeaders
        RELEASE_DIRECTORY = /\Aruby-(\d+)\.(\d+)\.(\d+)-p\d+\z/

        # Returns the directory name, or nil when no packaged headers fit. The headers
        # named for the running Ruby fit. For a release Ruby, so do the newest headers of
        # a release with the same major and minor version that is not newer than it. The
        # headers of another minor version or of a pre-release can describe other VM
        # structures: the extension would compile against them and record no lines, or
        # fail to compile.
        def self.choose(directory_names, ruby_version:, release:, exact_directory_name:)
          return exact_directory_name if directory_names.include?(exact_directory_name)
          return nil unless release

          running = Gem::Version.new(ruby_version)
          candidates = release_directories(directory_names, minor_version(ruby_version))
            .select { |_name, version| version <= running }
          name, _version = candidates.max_by { |_name, version| version }
          name
        end

        # Why #choose found nothing, for the build record.
        def self.missing_reason(directory_names, gem_version:, ruby_version:, release:)
          minor = minor_version(ruby_version)
          same_minor = directory_names.select { |name| name.start_with?("ruby-#{minor}.") }.sort
          packaged = same_minor.empty? ? "none" : same_minor.join(", ")
          unless release
            return "Ruby #{ruby_version} is not a release, and datadog-ruby_core_source #{gem_version} has no " \
              "headers named for it (its #{minor} headers: #{packaged})"
          end

          "datadog-ruby_core_source #{gem_version} has no headers of a Ruby #{minor} release up to " \
            "#{ruby_version} (its #{minor} headers: #{packaged})"
        end

        def self.release_directories(directory_names, minor)
          directory_names.filter_map do |name|
            match = RELEASE_DIRECTORY.match(name)
            next unless match && "#{match[1]}.#{match[2]}" == minor

            [name, Gem::Version.new("#{match[1]}.#{match[2]}.#{match[3]}")]
          end
        end

        def self.minor_version(ruby_version)
          ruby_version.split(".").first(2).join(".")
        end
      end
    end
  end
end
