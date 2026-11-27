# frozen_string_literal: true

# Judges one case of the install test from the probe's JSON and log, and prints one line: PASS or FAIL, what the
# case resolved and how the extension was built. Exits 1 when the case fails.
#
#   ruby check.rb PROBE_JSON PROBE_LOG lines [HEADERS_DIRECTORY]
#   ruby check.rb PROBE_JSON PROBE_LOG none REASON_TEXT
#
# "lines": the extension has line coverage, built with release headers of the running Ruby's minor version (or
# with HEADERS_DIRECTORY), and records the known answer. "none": it has none, records a reason that contains
# REASON_TEXT, and datadog-ci logs an error that names that reason.
require "json"

json_path, log_path, expected, detail = ARGV
failures = []
result =
  begin
    JSON.parse(File.read(json_path))
  rescue => e
    failures << "no probe result (#{e.class}: #{e.message})"
    {}
  end
log = File.exist?(log_path) ? File.read(log_path) : ""
minor = RUBY_VERSION.split(".").first(2).join(".")

case expected
when "lines"
  failures << "no line coverage: #{result["unsupported_reason"].inspect}" unless result["supported"] == true
  directory = result["vm_headers"].to_s[/\Athe (\S+) headers of /, 1].to_s
  release = /\Aruby-#{Regexp.escape(minor)}\.(\d+)-p\d+\z/.match(directory)
  unless release && Gem::Version.new("#{minor}.#{release[1]}") <= Gem::Version.new(RUBY_VERSION)
    failures << "built with #{result["vm_headers"].inspect}, not with release headers of Ruby #{minor}"
  end
  failures << "built with #{directory}, not #{detail}" if detail && directory != detail
  failures << "line coverage did not start" unless result["started"] == true
  failures << "recorded #{JSON.generate(result["tests"])}, not the known answer" unless result["known_answer"] == true
when "none"
  failures << "the extension has line coverage" unless result["supported"] == false
  reason = result["unsupported_reason"].to_s
  failures << "the reason #{reason.inspect} does not contain #{detail.inspect}" unless detail && reason.include?(detail)
  failures << "line coverage started" unless result["started"] == false
  message = "Per-test line coverage is not available: datadog-ci's native extension was built without it, " \
    "because #{reason}."
  unless log.each_line.any? { |line| line.include?("ERROR") && line.include?(message) }
    failures << "the log has no error that names the reason"
  end
else
  abort("usage: ruby check.rb PROBE_JSON PROBE_LOG lines [HEADERS_DIRECTORY] | none REASON_TEXT")
end

built = result["vm_headers"] || "no line coverage: #{result["unsupported_reason"]}"
resolved = "datadog #{result["datadog"]}, datadog-ruby_core_source #{result["datadog-ruby_core_source"]}"
verdict = failures.empty? ? "PASS" : "FAIL (#{failures.join("; ")})"
puts "#{verdict} | Ruby #{RUBY_VERSION} | #{resolved} | #{built}"
exit(failures.empty? ? 0 : 1)
