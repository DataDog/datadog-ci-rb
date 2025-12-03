Ruby = Steep::Diagnostic::Ruby

target :lib do
  signature "sig"

  check "lib"

  ignore "lib/datadog/ci/configuration/settings.rb"

  library "pathname"
  library "find"
  library "json"
  library "logger"
  library "date"
  library "minitest"
  library "net-http"
  library "zlib"
  library "securerandom"
  library "tmpdir"
  library "fileutils"
  library "socket"
  library "optparse"
  library "prism"

  repo_path "vendor/rbs"
  library "ddtrace"
  library "gem"
  library "open3"
  library "rspec"
  library "cucumber"
  library "msgpack"
  library "ci_queue"
  library "knapsack_pro"
  library "bundler"
  library "selenium-webdriver"
  library "capybara"
  library "timecop"
  library "webmock"
  library "simplecov"
  library "cuprite"
  library "parallel_tests"
  library "rails"
  library "lograge"
  library "semantic_logger"

  configure_code_diagnostics(Ruby.default) do |hash|
    # This check asks you to type every empty collection used in
    # local variables with an inline type annotation (e.g. `ret = {} #: Hash[Symbol,untyped]`).
    # This pollutes the code base, and demands seemingly unnecessary typing of internal variables.
    # Ideally, these empty collections automatically assume a signature based on its usage inside its method.
    # @see https://github.com/soutaro/steep/pull/1338
    hash[Ruby::UnannotatedEmptyCollection] = :hint

    hash[Ruby::FallbackAny] = :hint
    hash[Ruby::UnreachableBranch] = :hint
  end
end
