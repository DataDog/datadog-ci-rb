if RUBY_ENGINE != "ruby" || Gem.win_platform?
  warn(
    "WARN: Skipping build of code coverage native extension because of unsupported platform."
  )

  File.write("Makefile", "all install clean: # dummy makefile that does nothing")
  exit
end

require "mkmf"

# Tag the native extension library with the Ruby version and Ruby platform.
# This makes it easier for development (avoids "oops I forgot to rebuild when I switched my Ruby") and ensures that
# the wrong library is never loaded.
# When requiring, we need to use the exact same string, including the version and the platform.
EXTENSION_NAME = "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}".freeze

# Line coverage reads private VM structures. Their headers come from the
# datadog-ruby_core_source gem, a dependency of the datadog gem, the same way the
# datadog profiler builds. Without them the extension builds without line coverage.
def private_vm_headers_dir
  require "datadog/ruby_core_source"

  ruby_dir =
    if RUBY_PATCHLEVEL < 0
      Datadog::RubyCoreSource.extract_beta_ruby_version
    else
      "ruby-#{RUBY_VERSION}-p#{RUBY_PATCHLEVEL}"
    end
  dir = Datadog::RubyCoreSource.deduce_packaged_source_dir(ruby_dir)
  (dir && File.directory?(dir)) ? dir : nil
rescue LoadError, StandardError => e
  warn("WARN: building without line coverage: #{e.class}: #{e.message}")
  nil
end

headers_dir = private_vm_headers_dir
if headers_dir
  line_coverage = with_cppflags("-I#{headers_dir}") do
    have_header("vm_core.h") && have_header("iseq.h") && (RUBY_VERSION < "3.3" || have_header("ractor_core.h"))
  end
  if line_coverage
    append_cppflags("-I#{headers_dir}")
    append_cppflags("-DDD_CI_LINE_COVERAGE")
    append_cppflags("-DHAVE_RB_EXECUTION_CONTEXT_STORAGE") if RUBY_VERSION >= "3.2"
  end
end

create_makefile(EXTENSION_NAME)
