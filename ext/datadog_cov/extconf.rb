require "mkmf"

# Tag the native extension library with the Ruby version and Ruby platform.
# This makes it easier for development (avoids "oops I forgot to rebuild when I switched my Ruby") and ensures that
# the wrong library is never loaded.
# When requiring, we need to use the exact same string, including the version and the platform.
EXTENSION_NAME = "datadog_cov.#{RUBY_VERSION}_#{RUBY_PLATFORM}".freeze

create_makefile(EXTENSION_NAME)
