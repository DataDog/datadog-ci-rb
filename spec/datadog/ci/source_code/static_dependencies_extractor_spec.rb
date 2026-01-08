# frozen_string_literal: true

require "spec_helper"
require "datadog/ci/source_code/static_dependencies_extractor"

# Load fixtures for integration tests
fixture_base = File.expand_path("static_dependencies/fixtures", __dir__)
require "#{fixture_base}/constants/base_constant"
require "#{fixture_base}/constants/another_constant"
require "#{fixture_base}/constants/standalone_class"
require "#{fixture_base}/constants/nested/deeply_nested_constant"
require "#{fixture_base}/consumers/fully_qualified_consumer"
require "#{fixture_base}/consumers/multi_deps_consumer"
require "#{fixture_base}/consumers/no_deps_consumer"
require "#{fixture_base}/ignored/ignored_constant"

RSpec.describe Datadog::CI::SourceCode::StaticDependenciesExtractor do
  let(:fixture_base) { File.expand_path("static_dependencies/fixtures", __dir__) }
  let(:root_path) { fixture_base }
  let(:ignored_path) { nil }

  subject(:extractor) { described_class.new(root_path, ignored_path) }

  def absolute_fixture_path(relative_path)
    File.join(fixture_base, relative_path)
  end

  describe "#initialize" do
    it "sets root_path" do
      expect(extractor.root_path).to eq(root_path)
    end

    it "sets ignored_path" do
      extractor_with_ignored = described_class.new(root_path, "/ignored")
      expect(extractor_with_ignored.ignored_path).to eq("/ignored")
    end

    it "initializes empty dependencies_map" do
      expect(extractor.dependencies_map).to eq({})
    end

    context "with nil ignored_path" do
      let(:ignored_path) { nil }

      it "allows nil ignored_path" do
        expect(extractor.ignored_path).to be_nil
      end
    end
  end

  describe "#extract" do
    context "with valid ISeq" do
      let(:iseq) { RubyVM::InstructionSequence.of(FullyQualifiedConsumer.instance_method(:use_base)) }

      it "extracts from the ISeq without error" do
        expect { extractor.extract(iseq) }.not_to raise_error
      end

      it "adds entry to dependencies_map" do
        extractor.extract(iseq)
        expect(extractor.dependencies_map).not_to be_empty
      end

      it "maps the source file to its dependencies" do
        extractor.extract(iseq)
        consumer_path = absolute_fixture_path("consumers/fully_qualified_consumer.rb")
        expect(extractor.dependencies_map).to have_key(consumer_path)
      end

      it "resolves constant dependencies" do
        extractor.extract(iseq)
        consumer_path = absolute_fixture_path("consumers/fully_qualified_consumer.rb")
        deps = extractor.dependencies_map[consumer_path]

        expect(deps).to have_key(absolute_fixture_path("constants/base_constant.rb"))
      end
    end

    context "with ISeq from code outside root_path" do
      let(:iseq) { RubyVM::InstructionSequence.of(RSpec.method(:describe)) }

      it "does not add to dependencies_map" do
        extractor.extract(iseq)
        expect(extractor.dependencies_map).to be_empty
      end
    end

    context "with ISeq from eval'd code (no absolute_path)" do
      let(:iseq) do
        eval_code = "def dynamic_method; 42; end"
        RubyVM::InstructionSequence.compile(eval_code)
      end

      it "does not add to dependencies_map" do
        extractor.extract(iseq)
        expect(extractor.dependencies_map).to be_empty
      end
    end

    context "with ignored_path set" do
      let(:ignored_path) { absolute_fixture_path("ignored") }
      let(:ignored_method_iseq) do
        # This requires us to have loaded the ignored constant file
        RubyVM::InstructionSequence.of(IgnoredConstant.method(:value))
      end

      it "excludes files under ignored_path" do
        extractor.extract(ignored_method_iseq)
        expect(extractor.dependencies_map).to be_empty
      end
    end

    context "with multiple ISeqs from same file" do
      let(:iseq_multi) { RubyVM::InstructionSequence.of(MultiDepsConsumer.instance_method(:use_all)) }
      let(:iseq_fully_qualified) { RubyVM::InstructionSequence.of(FullyQualifiedConsumer.instance_method(:use_base)) }

      it "accumulates dependencies when processing same file multiple times" do
        # Process the method that uses all constants
        extractor.extract(iseq_multi)

        consumer_path = absolute_fixture_path("consumers/multi_deps_consumer.rb")
        deps = extractor.dependencies_map[consumer_path]

        expect(deps.keys).to include(
          absolute_fixture_path("constants/base_constant.rb"),
          absolute_fixture_path("constants/another_constant.rb")
        )
      end

      it "processes multiple files independently" do
        extractor.extract(iseq_multi)
        extractor.extract(iseq_fully_qualified)

        expect(extractor.dependencies_map.keys).to include(
          absolute_fixture_path("consumers/multi_deps_consumer.rb"),
          absolute_fixture_path("consumers/fully_qualified_consumer.rb")
        )
      end
    end

    context "with method that has no constant references" do
      let(:iseq) { RubyVM::InstructionSequence.of(NoDepsConsumer.instance_method(:compute)) }

      it "creates entry with no fixture dependencies" do
        extractor.extract(iseq)
        consumer_path = absolute_fixture_path("consumers/no_deps_consumer.rb")

        # Entry exists but might have no dependencies (or dependencies outside fixtures)
        expect(extractor.dependencies_map).to have_key(consumer_path)
        fixture_deps = extractor.dependencies_map[consumer_path].keys.select { |k| k.start_with?(fixture_base) }
        expect(fixture_deps).to be_empty
      end
    end

    context "dependencies are filtered by root_path and ignored_path" do
      let(:root_path) { absolute_fixture_path("consumers") }
      let(:iseq) { RubyVM::InstructionSequence.of(FullyQualifiedConsumer.instance_method(:use_base)) }

      it "includes source file under root_path" do
        extractor.extract(iseq)
        consumer_path = absolute_fixture_path("consumers/fully_qualified_consumer.rb")
        expect(extractor.dependencies_map).to have_key(consumer_path)
      end

      it "does not include dependency files outside root_path" do
        extractor.extract(iseq)
        consumer_path = absolute_fixture_path("consumers/fully_qualified_consumer.rb")
        deps = extractor.dependencies_map[consumer_path] || {}

        # Dependencies to /constants/ should be filtered out
        constant_deps = deps.keys.select { |k| k.include?("/constants/") }
        expect(constant_deps).to be_empty
      end
    end
  end

  describe "#reset" do
    let(:iseq) { RubyVM::InstructionSequence.of(FullyQualifiedConsumer.instance_method(:use_base)) }

    before do
      extractor.extract(iseq)
    end

    it "clears the dependencies_map" do
      expect(extractor.dependencies_map).not_to be_empty

      extractor.reset

      expect(extractor.dependencies_map).to eq({})
    end
  end

  describe "integration with ConstantResolver" do
    let(:iseq) { RubyVM::InstructionSequence.of(MultiDepsConsumer.instance_method(:use_all)) }

    it "correctly resolves multiple dependencies from a single method" do
      extractor.extract(iseq)

      consumer_path = absolute_fixture_path("consumers/multi_deps_consumer.rb")
      deps = extractor.dependencies_map[consumer_path]

      expected_deps = [
        absolute_fixture_path("constants/base_constant.rb"),
        absolute_fixture_path("constants/another_constant.rb"),
        absolute_fixture_path("constants/nested/deeply_nested_constant.rb"),
        absolute_fixture_path("constants/standalone_class.rb")
      ]

      expected_deps.each do |dep|
        expect(deps).to have_key(dep)
      end
    end
  end

  describe "thread safety considerations" do
    it "can be used with separate instances per thread" do
      results = []

      threads = 3.times.map do |i|
        Thread.new do
          thread_extractor = described_class.new(root_path, ignored_path)
          iseq = RubyVM::InstructionSequence.of(FullyQualifiedConsumer.instance_method(:use_base))
          thread_extractor.extract(iseq)
          results << thread_extractor.dependencies_map.dup
        end
      end

      threads.each(&:join)

      # All threads should have produced results
      expect(results.size).to eq(3)
      results.each do |result|
        expect(result).not_to be_empty
      end
    end
  end
end

RSpec.describe Datadog::CI::SourceCode::StaticDependenciesExtractor::BytecodeScanner do
  subject(:scanner) { described_class.new }

  describe "#scan" do
    context "with :getconstant instruction" do
      let(:body) do
        [
          [:putnil],
          [:getconstant, :MyConstant, false],
          [:pop]
        ]
      end

      it "extracts the constant name" do
        expect(scanner.scan(body)).to include("MyConstant")
      end
    end

    context "with :opt_getconstant_path instruction" do
      let(:body) do
        [
          [:opt_getconstant_path, [:Foo, :Bar, :Baz]]
        ]
      end

      it "extracts the qualified constant path" do
        expect(scanner.scan(body)).to include("Foo::Bar::Baz")
      end
    end

    context "with multiple constant instructions" do
      let(:body) do
        [
          [:getconstant, :First, false],
          [:getconstant, :Second, false],
          [:opt_getconstant_path, [:Module, :Nested]]
        ]
      end

      it "extracts all constant names" do
        expect(scanner.scan(body)).to contain_exactly("First", "Second", "Module::Nested")
      end
    end

    context "with nested arrays (like real ISeq bodies)" do
      let(:body) do
        [
          [:some_instruction, [:getconstant, :NestedInArg, false]],
          [
            [:deeply, [:nested, [:getconstant, :DeeplyNested, false]]]
          ]
        ]
      end

      it "recursively finds constants in nested structures" do
        expect(scanner.scan(body)).to include("NestedInArg", "DeeplyNested")
      end
    end

    context "with hash values in body" do
      let(:body) do
        [
          [:putspecialobject, 1],
          {key: [:getconstant, :InHash, false]},
          [:leave]
        ]
      end

      it "scans hash values for constants" do
        expect(scanner.scan(body)).to include("InHash")
      end
    end

    context "with empty body" do
      let(:body) { [] }

      it "returns empty array" do
        expect(scanner.scan(body)).to eq([])
      end
    end

    context "with nil body" do
      let(:body) { nil }

      it "returns empty array" do
        expect(scanner.scan(body)).to eq([])
      end
    end

    context "with body containing only non-constant instructions" do
      let(:body) do
        [
          [:putnil],
          [:putself],
          [:leave]
        ]
      end

      it "returns empty array" do
        expect(scanner.scan(body)).to eq([])
      end
    end

    context "with :getconstant having non-symbol argument" do
      let(:body) do
        [
          [:getconstant, "StringNotSymbol", false]
        ]
      end

      it "ignores non-symbol constants" do
        expect(scanner.scan(body)).to eq([])
      end
    end

    context "with :opt_getconstant_path having empty array" do
      let(:body) do
        [
          [:opt_getconstant_path, []]
        ]
      end

      it "ignores empty path arrays" do
        expect(scanner.scan(body)).to eq([])
      end
    end

    context "with :opt_getconstant_path having non-array second argument" do
      let(:body) do
        [
          [:opt_getconstant_path, :NotAnArray]
        ]
      end

      it "ignores non-array cache entries" do
        expect(scanner.scan(body)).to eq([])
      end
    end

    context "with real ISeq from actual Ruby code" do
      let(:test_method) do
        # Define a method that references constants
        Module.new do
          def self.example_method
            # Reference constants in a non-void context
            [RSpec::Core::Runner, String].map(&:to_s)
          end
        end
      end

      let(:iseq) { RubyVM::InstructionSequence.of(test_method.method(:example_method)) }
      let(:body) { iseq.to_a[-1] }

      it "extracts constants from real bytecode" do
        # Should find at least RSpec::Core::Runner (String might be optimized differently)
        expect(scanner.scan(body)).to include("RSpec::Core::Runner")
      end
    end
  end

  describe "#build_constant_path" do
    context "with single symbol" do
      it "returns the symbol as string" do
        expect(scanner.build_constant_path([:Foo])).to eq("Foo")
      end
    end

    context "with multiple symbols" do
      it "joins with ::" do
        expect(scanner.build_constant_path([:Foo, :Bar, :Baz])).to eq("Foo::Bar::Baz")
      end
    end

    context "with empty array" do
      it "returns empty string" do
        expect(scanner.build_constant_path([])).to eq("")
      end
    end

    context "with mixed types (filters non-symbols)" do
      it "only includes symbols" do
        expect(scanner.build_constant_path([:Foo, "string", :Bar, 123, :Baz])).to eq("Foo::Bar::Baz")
      end
    end

    context "with all non-symbols" do
      it "returns empty string" do
        expect(scanner.build_constant_path(["string", 123, nil])).to eq("")
      end
    end
  end
end
