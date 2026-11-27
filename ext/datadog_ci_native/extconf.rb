if RUBY_ENGINE != "ruby" || Gem.win_platform?
  warn(
    "WARN: Skipping build of code coverage native extension because of unsupported platform."
  )

  File.write("Makefile", "all install clean: # dummy makefile that does nothing")
  exit
end

require "mkmf"
require "shellwords"
require_relative "line_coverage_headers"

# Tag the native extension library with the Ruby version and Ruby platform.
# This makes it easier for development (avoids "oops I forgot to rebuild when I switched my Ruby") and ensures that
# the wrong library is never loaded.
# When requiring, we need to use the exact same string, including the version and the platform.
EXTENSION_NAME = "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}".freeze

# Line coverage reads private VM structures, so it compiles against headers from the
# running Ruby's sources, which the datadog-ruby_core_source gem packages. When it
# cannot use them, the extension builds without line coverage: the install never fails
# because of it. The extension records the headers it used, or why it has none, and
# datadog-ci logs the reason at run time.
#
# Returns [the compiler flags for line coverage, the headers] or [nil, the reason].
def line_coverage_build
  if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.2")
    return [nil, "it needs Ruby 3.2 or later"]
  end

  begin
    require "datadog/ruby_core_source"
  rescue LoadError => e
    return [nil, "the datadog-ruby_core_source gem could not be loaded (#{e.message})"]
  end

  gem_version = Datadog::RubyCoreSource::VERSION
  gem_file = $LOADED_FEATURES.find { |path| path.end_with?("/datadog/ruby_core_source.rb") }
  return [nil, "datadog-ruby_core_source #{gem_version} did not load from a file"] unless gem_file

  packaged_directory = File.join(File.dirname(gem_file), "ruby_core_source")
  directory_names =
    if File.directory?(packaged_directory)
      Dir.children(packaged_directory).select { |name| File.directory?(File.join(packaged_directory, name)) }
    else
      []
    end
  release = RUBY_PATCHLEVEL >= 0
  exact_directory_name =
    release ? "ruby-#{RUBY_VERSION}-p#{RUBY_PATCHLEVEL}" : Datadog::RubyCoreSource.extract_beta_ruby_version
  headers = Datadog::CI::NativeBuild::LineCoverageHeaders
  name = headers.choose(
    directory_names, ruby_version: RUBY_VERSION, release: release, exact_directory_name: exact_directory_name
  )
  unless name
    reason = headers.missing_reason(
      directory_names, gem_version: gem_version, ruby_version: RUBY_VERSION, release: release
    )
    return [nil, reason]
  end

  description = "the #{name} headers of datadog-ruby_core_source #{gem_version}"
  flags = [
    "-I#{Shellwords.escape(File.join(packaged_directory, name))}",
    "-DDD_CI_LINE_COVERAGE",
    "-DHAVE_RB_EXECUTION_CONTEXT_STORAGE"
  ]
  options = flags.join(" ")
  found = have_header("vm_core.h", nil, options) && have_header("iseq.h", nil, options) &&
    (RUBY_VERSION < "3.3" || have_header("ractor_core.h", nil, options))
  return [nil, "#{description} lack vm_core.h, iseq.h or ractor_core.h"] unless found

  # Headers that fit by name can still differ from what line_coverage.c expects, as for
  # a Ruby newer than this version of datadog-ci.
  unless try_compile(File.read(File.join(__dir__, "line_coverage.c")), options)
    return [nil, "line_coverage.c does not compile against #{description}"]
  end

  [flags, description]
rescue => e
  [nil, "choosing the headers failed: #{e.class}: #{e.message}"]
end

# A C string literal of printable ASCII.
def c_string(text)
  "\"#{text.gsub(/[^ -~]/, "?").gsub(/["\\]/) { |character| "\\#{character}" }}\""
end

line_coverage_flags, line_coverage_note = line_coverage_build
if line_coverage_flags
  append_cppflags(line_coverage_flags)
  build_record = "#define DD_CI_LINE_COVERAGE_VM_HEADERS #{c_string(line_coverage_note)}\n"
else
  warn("WARN: building without per-test line coverage: #{line_coverage_note}")
  build_record = "#define DD_CI_LINE_COVERAGE_UNSUPPORTED_REASON #{c_string(line_coverage_note)}\n"
end
# line_coverage.c includes the record from the build directory.
File.write("line_coverage_build.h", build_record)
append_cppflags("-DDD_CI_LINE_COVERAGE_BUILD_RECORD")

create_makefile(EXTENSION_NAME)
