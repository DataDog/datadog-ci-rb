require "stringio"

require "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}"

RSpec.describe "RSpec instrumentation with per-test line coverage" do
  let(:line_coverage) { Datadog::CI::TestImpactAnalysis::Coverage::LineCoverage }
  let(:fixture_path) { File.join(__dir__, "fixtures/line_coverage/geometry.rb") }
  let(:fixture_file) { Datadog::CI::Git::LocalRepository.relative_to_root(fixture_path) }

  before do
    skip "per-test line coverage is not supported on this Ruby" unless line_coverage.supported?
  end

  after do
    line_coverage.stop_collector
  end

  include_context "CI mode activated" do
    let(:integration_name) { :rspec }
    let(:itr_enabled) { true }
    let(:code_coverage_enabled) { true }
    let(:line_coverage_enabled) { true }
  end

  def run_rspec
    with_new_rspec_environment do
      yield

      options = ::RSpec::Core::ConfigurationOptions.new(%w[--pattern none])
      ::RSpec::Core::Runner.new(options).run(StringIO.new, StringIO.new)
    end
  end

  def lines_of(event, file = fixture_file)
    event&.inspect_coverage&.fetch(file, nil)
  end

  def test_span_named(name)
    test_spans.find { |span| span.get_tag("test.name").end_with?(name) }
  end

  def shared_events
    test_impact_analysis_component.shutdown!
    fetch_coverage_events.grep(Datadog::CI::TestImpactAnalysis::Coverage::SharedEvent)
  end

  # Lines of geometry.rb that run while it loads: module and class bodies and def lines.
  let(:init_lines) { [2, 3, 4, 8, 12, 19, 21, 25, 31, 34] }

  it "reports the lines each test ran, with the initialiser lines of the files it touched" do
    path = fixture_path
    run_rspec do
      load path

      RSpec.describe "Square" do
        it "computes the area" do
          expect(LineCoverageGeometry::Square.new(3).area).to eq(9)
        end

        it "describes itself" do
          expect(LineCoverageGeometry::Square.new(3).describe(:short)).to eq("square")
        end

        it "runs no fixture code" do
          expect(1 + 1).to eq(2)
        end
      end
    end

    expect(test_spans).to have(3).items

    area = find_coverage_for_test(test_span_named("computes the area"))
    expect(lines_of(area)).to eq((init_lines + [5, 6, 9, 10]).sort)

    describe = lines_of(find_coverage_for_test(test_span_named("describes itself")))
    expect(describe).to include(5, 6, 13, 16)
    expect(describe).not_to include(9, 14)

    expect(lines_of(find_coverage_for_test(test_span_named("runs no fixture code")))).to be_nil
  end

  it "treats as initialiser code only the class bodies nested in a file through class bodies" do
    path = File.join(__dir__, "fixtures/line_coverage/nesting.rb")
    file = Datadog::CI::Git::LocalRepository.relative_to_root(path)
    run_rspec do
      load path

      RSpec.describe "Nesting" do
        it "opens a singleton class in a method" do
          expect(LineCoverageNesting.open_singleton(Object.new)).to eq(:tagged)
        end

        it "defines a class in an eval string" do
          expect(LineCoverageNesting.eval_class).to eq(7)
        end

        it "calls a method defined in a nested class body" do
          expect(LineCoverageNesting.answer).to eq(42)
        end
      end
    end

    # The top level, the module body, its rescue clause and the singleton class body in it.
    init_lines = [2, 3, 4, 9, 10, 11, 12, 15, 24, 34]
    expect(lines_of(find_coverage_for_test(test_span_named("opens a singleton class in a method")), file))
      .to eq((init_lines + [16, 17, 18, 19, 21, 22]).sort)
    expect(lines_of(find_coverage_for_test(test_span_named("defines a class in an eval string")), file))
      .to eq((init_lines + [25, 26, 27, 28, 29, 30, 32, 33]).sort)
    # Runs after the class bodies above, which are not initialiser code, so it does not get their lines.
    expect(lines_of(find_coverage_for_test(test_span_named("calls a method defined in a nested class body")), file))
      .to eq((init_lines + [5, 6]).sort)

    init = shared_events.find { |event| event.part == "init" }
    expect(init.inspect_coverage.fetch(file)).to eq(init_lines)
  end

  it "credits code that a test runs on another thread to the test" do
    path = fixture_path
    run_rspec do
      load path

      RSpec.describe "Threads" do
        it "waits for a thread" do
          expect(LineCoverageGeometry.in_thread).to eq(42)
        end
      end
    end

    expect(lines_of(find_coverage_for_test(first_test_span))).to include(26, 27, 28)
  end

  it "credits before(:context) code to every test of the group, and after(:context) code to no test" do
    path = fixture_path
    run_rspec do
      load path

      RSpec.describe "Fixtures" do
        before(:context) { LineCoverageGeometry.setup_value }
        after(:context) { LineCoverageGeometry.teardown_value }

        it "first" do
          expect(1).to eq(1)
        end

        it "second" do
          expect(2).to eq(2)
        end
      end
    end

    expect(test_spans).to have(2).items
    test_spans.each do |span|
      lines = lines_of(find_coverage_for_test(span))
      expect(lines).to include(22)
      expect(lines).not_to include(32)
    end

    parts = shared_events.to_h { |event| [event.part, event.inspect_coverage.fetch(fixture_file, [])] }
    expect(parts.fetch("suiteSetup")).to include(22)
    expect(parts.fetch("unowned")).to include(32)
    expect(parts.fetch("init")).to eq(init_lines)
  end

  it "sends no record for a test skipped before it starts, and the lines that ran for one that skips itself" do
    path = fixture_path
    run_rspec do
      load path

      RSpec.describe "Skips" do
        before(:context) { LineCoverageGeometry.setup_value }

        xit "is skipped by its declaration" do
          LineCoverageGeometry::Square.new(2).area
        end

        it "is skipped by its metadata", skip: "not today" do
          LineCoverageGeometry::Square.new(2).area
        end

        it "skips itself" do
          LineCoverageGeometry::Square.new(2).area
          skip "not today"
        end
      end
    end

    expect(test_spans).to have(3).items
    expect(find_coverage_for_test(test_span_named("is skipped by its declaration"))).to be_nil
    expect(find_coverage_for_test(test_span_named("is skipped by its metadata"))).to be_nil
    expect(lines_of(find_coverage_for_test(test_span_named("skips itself")))).to include(5, 6, 9, 22)
  end

  it "sends line bitmaps, and shared records without a span id" do
    path = fixture_path
    run_rspec do
      load path

      RSpec.describe "Payload" do
        it "computes the area" do
          expect(LineCoverageGeometry::Square.new(2).area).to eq(4)
        end
      end
    end

    payload = MessagePack.unpack(MessagePack.pack(find_coverage_for_test(first_test_span)))
    entry = payload.fetch("files").find { |file| file["filename"] == fixture_file }
    expect(entry.fetch("bitmap").encoding).to eq(Encoding::BINARY)
    expect(Datadog::CI::TestImpactAnalysis::Coverage::LineFiles.lines(entry.fetch("bitmap"))).to include(5, 9)
    expect(payload.fetch("span_id")).to eq(first_test_span.id)

    shared = shared_events.map { |event| MessagePack.unpack(MessagePack.pack(event)) }
    expect(shared.map { |record| record.fetch("shared") }).to include("init")
    expect(shared).to all(include("test_session_id" => test_session_span.id))
    expect(shared).to all(satisfy { |record| !record.key?("span_id") })
  end

  it "keeps the test result and logs a warning when the test's coverage cannot be written" do
    expect(Datadog.logger).to receive(:warn).with(/Failed to write the line coverage of a test: TypeError/)

    path = fixture_path
    run_rspec do
      load path

      RSpec.describe "Square" do
        it "computes the area" do
          Datadog::CI.active_test.add_impacted_files([nil])
          expect(LineCoverageGeometry::Square.new(3).area).to eq(9)
        end
      end
    end

    expect(test_spans).to have(1).item
    expect(first_test_span).to have_pass_status
    expect(find_coverage_for_test(first_test_span)).to be_nil
  end

  context "when the library settings turn code coverage off" do
    let(:code_coverage_enabled) { false }

    it "stops the collector and sends no coverage" do
      path = fixture_path
      run_rspec do
        load path

        RSpec.describe "Square" do
          it "computes the area" do
            expect(LineCoverageGeometry::Square.new(3).area).to eq(9)
          end
        end
      end

      expect(test_spans).to have(1).item
      expect(coverage_events).to be_empty
      expect(shared_events).to be_empty
    end
  end
end
