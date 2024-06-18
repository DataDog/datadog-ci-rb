require "datadog/ci"

module FileHelpers
  # this helper returns the absolute path of a file when given
  # path relative to the current __dir__
  def absolute_path(path)
    callstack_top = caller_locations(1, 1)[0]
    caller_dir = File.dirname(callstack_top.absolute_path)
    File.join(caller_dir, path)
  end
end
