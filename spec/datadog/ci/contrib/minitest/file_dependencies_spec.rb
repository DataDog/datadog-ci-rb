# frozen_string_literal: true

require "minitest"
require_relative "../../../../support/contexts/framework_file_dependencies"

RSpec.describe "Minitest file dependencies" do
  include_context "framework file dependencies"
  let(:integration_name) { :minitest }

  def run_framework
    reader = read_fixtures
    test_class = Class.new(Minitest::Test) do
      define_method(:test_reads_fixtures) { reader.call }
      define_method(:test_does_not_read_fixtures) {}
    end
    stub_const("FileDependencyMinitest", test_class)
    # Use the real runner while keeping unrelated classes in this RSpec process
    # out of the run, including classes declared by other integration examples.
    allow(Minitest::Runnable).to receive(:runnables).and_return([test_class])
    expect(Minitest.run(["--seed", "1"])).to be(true)
  end

  it_behaves_like "file dependencies from the framework runner"
end
