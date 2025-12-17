# frozen_string_literal: true

require "spec_helper"

# Load fixtures - must be loaded before running tests so ISeqs exist
fixture_base = File.expand_path("static_dependencies/fixtures", __dir__)

# Load constant definitions first
require "#{fixture_base}/constants/base_constant"
require "#{fixture_base}/constants/another_constant"
require "#{fixture_base}/constants/standalone_class"
require "#{fixture_base}/constants/module_with_mixin"
require "#{fixture_base}/constants/nested/deeply_nested_constant"

# Load ignored directory constants
require "#{fixture_base}/ignored/ignored_constant"

# Load consumers that reference these constants
require "#{fixture_base}/consumers/fully_qualified_consumer"
require "#{fixture_base}/consumers/unqualified_consumer"
require "#{fixture_base}/consumers/mixed_consumer"
require "#{fixture_base}/consumers/no_deps_consumer"
require "#{fixture_base}/consumers/inheritance_consumer"
require "#{fixture_base}/consumers/multi_deps_consumer"
require "#{fixture_base}/consumers/nonexistent_const_consumer"
require "#{fixture_base}/consumers/builtin_const_consumer"
require "#{fixture_base}/consumers/uses_ignored_consumer"
require "#{fixture_base}/consumers/cross_reference_consumer"
require "#{fixture_base}/consumers/mixin_consumer"
require "#{fixture_base}/consumers/lambda_consumer"
require "#{fixture_base}/consumers/conditional_consumer"
require "#{fixture_base}/consumers/rescue_consumer"
require "#{fixture_base}/consumers/constant_assignment_consumer"
require "#{fixture_base}/ignored/ignored_consumer"

RSpec.describe Datadog::CI::SourceCode::StaticDependencies do
  let(:fixture_base) { File.expand_path("static_dependencies/fixtures", __dir__) }
  let(:root_path) { fixture_base }
  let(:ignored_path) { nil }

  def absolute_fixture_path(relative_path)
    File.join(fixture_base, relative_path)
  end

  describe "::STATIC_DEPENDENCIES_AVAILABLE" do
    it "is a boolean" do
      expect([true, false]).to include(described_class::STATIC_DEPENDENCIES_AVAILABLE)
    end
  end

  # Skip all native extension tests if not available
  context "when static dependencies tracking is available", skip: !Datadog::CI::SourceCode::StaticDependencies::STATIC_DEPENDENCIES_AVAILABLE do
    describe ".populate!" do
      subject(:populate) { described_class.populate!(root_path, ignored_path) }

      context "with valid root_path" do
        it "returns a Hash" do
          expect(populate).to be_a(Hash)
        end

        it "populates @dependencies_map instance variable" do
          populate
          expect(described_class.instance_variable_get(:@dependencies_map)).to be_a(Hash)
        end

        it "includes consumer files in the map" do
          result = populate

          # The consumer files should be keys in the map
          expect(result.keys).to include(
            absolute_fixture_path("consumers/fully_qualified_consumer.rb")
          )
        end

        it "maps consumer files to their constant dependencies" do
          result = populate
          consumer_path = absolute_fixture_path("consumers/fully_qualified_consumer.rb")
          deps = result[consumer_path]

          expect(deps).to be_a(Hash)
          # fully_qualified_consumer.rb references Constants::BaseConstant, Constants::Nested::DeeplyNestedConstant, etc.
          expect(deps.keys).to include(
            absolute_fixture_path("constants/base_constant.rb")
          )
        end

        it "includes deeply nested constant paths" do
          result = populate
          consumer_path = absolute_fixture_path("consumers/fully_qualified_consumer.rb")
          deps = result[consumer_path]

          expect(deps.keys).to include(
            absolute_fixture_path("constants/nested/deeply_nested_constant.rb")
          )
        end

        it "includes multiple dependencies for multi_deps_consumer" do
          result = populate
          consumer_path = absolute_fixture_path("consumers/multi_deps_consumer.rb")
          deps = result[consumer_path]

          expect(deps.keys).to include(
            absolute_fixture_path("constants/base_constant.rb"),
            absolute_fixture_path("constants/another_constant.rb"),
            absolute_fixture_path("constants/nested/deeply_nested_constant.rb"),
            absolute_fixture_path("constants/standalone_class.rb")
          )
        end

        it "handles files with no project constant references" do
          result = populate
          consumer_path = absolute_fixture_path("consumers/no_deps_consumer.rb")

          # File might be in the map with empty deps or not in the map at all
          if result.key?(consumer_path)
            deps = result[consumer_path]
            # Should not have any dependencies pointing to fixture files
            fixture_deps = deps.keys.select { |k| k.start_with?(fixture_base) }
            expect(fixture_deps).to be_empty
          end
        end

        it "handles cross-file references to other consumers" do
          result = populate
          consumer_path = absolute_fixture_path("consumers/cross_reference_consumer.rb")
          deps = result[consumer_path]

          # CrossReferenceConsumer references NoDepsConsumer and FullyQualifiedConsumer
          expect(deps.keys).to include(
            absolute_fixture_path("consumers/no_deps_consumer.rb"),
            absolute_fixture_path("consumers/fully_qualified_consumer.rb")
          )
        end

        it "handles mixed qualified and unqualified references" do
          result = populate
          consumer_path = absolute_fixture_path("consumers/mixed_consumer.rb")
          deps = result[consumer_path]

          expect(deps.keys).to include(
            absolute_fixture_path("constants/base_constant.rb"),
            absolute_fixture_path("constants/standalone_class.rb")
          )
        end

        it "gracefully handles non-existent constant references" do
          # NonexistentConstConsumer references NonExistentModule::NonExistentClass
          # This should not raise an error
          expect { populate }.not_to raise_error
        end

        it "resets the map on subsequent calls" do
          first_result = described_class.populate!(root_path, ignored_path)
          first_keys = first_result.keys.dup

          # Second call with same args
          second_result = described_class.populate!(root_path, ignored_path)

          expect(second_result.keys).to eq(first_keys)
        end
      end

      context "with root_path as subdirectory" do
        let(:root_path) { absolute_fixture_path("consumers") }

        it "only includes files under the subdirectory" do
          result = populate

          result.keys.each do |file_path|
            expect(file_path).to start_with(root_path)
          end
        end

        it "does not include constants directory files as source files" do
          result = populate

          # The keys (source files) should only be under consumers/
          result.keys.each do |file_path|
            expect(file_path).not_to include("/constants/")
          end
        end

        it "still resolves dependencies to files outside root_path" do
          result = populate
          consumer_path = absolute_fixture_path("consumers/fully_qualified_consumer.rb")

          if result.key?(consumer_path)
            deps = result[consumer_path]
            # Dependencies can point to files outside root_path (constants/)
            constant_deps = deps.keys.select { |k| k.include?("/constants/") }
            # These would be filtered out by is_path_included check
            expect(constant_deps).to be_empty
          end
        end
      end

      context "with deeply nested root_path that has no files" do
        # Use a path that won't prefix-match any existing files
        # (C code uses strncmp prefix matching)
        let(:root_path) { absolute_fixture_path("does_not_exist/deeply/nested") }

        it "returns empty hash without error" do
          expect(populate).to eq({})
        end
      end

      context "argument validation" do
        it "raises ArgumentError when root_path is not a String" do
          expect { described_class.populate!(nil, nil) }.to raise_error(ArgumentError)
          expect { described_class.populate!(123, nil) }.to raise_error(ArgumentError)
          expect { described_class.populate!([], nil) }.to raise_error(ArgumentError)
        end
      end
    end

    describe "ignored_path handling" do
      subject(:populate) { described_class.populate!(root_path, ignored_path) }

      context "when ignored_path is nil" do
        let(:ignored_path) { nil }

        it "does not exclude any files" do
          result = populate

          # Should include files from ignored/ directory
          expect(result.keys).to include(
            absolute_fixture_path("ignored/ignored_consumer.rb")
          )
        end
      end

      context "when ignored_path is empty string" do
        let(:ignored_path) { "" }

        it "does not exclude any files" do
          result = populate

          # Should include files from ignored/ directory
          expect(result.keys).to include(
            absolute_fixture_path("ignored/ignored_consumer.rb")
          )
        end
      end

      context "when ignored_path is set to ignored directory" do
        let(:ignored_path) { absolute_fixture_path("ignored") }

        it "excludes files under ignored_path" do
          result = populate

          result.keys.each do |file_path|
            expect(file_path).not_to start_with(ignored_path)
          end
        end

        it "does not include ignored_consumer.rb" do
          result = populate

          expect(result.keys).not_to include(
            absolute_fixture_path("ignored/ignored_consumer.rb")
          )
        end

        it "does not include dependencies pointing to ignored files" do
          result = populate
          consumer_path = absolute_fixture_path("consumers/uses_ignored_consumer.rb")

          if result.key?(consumer_path)
            deps = result[consumer_path]
            deps.keys.each do |dep_path|
              expect(dep_path).not_to start_with(ignored_path)
            end
          end
        end
      end

      context "when ignored_path equals root_path" do
        let(:ignored_path) { root_path }

        it "excludes all files (empty result)" do
          result = populate
          expect(result).to be_empty
        end
      end

      context "when ignored_path is a subdirectory of root_path" do
        let(:ignored_path) { absolute_fixture_path("constants/nested") }

        it "excludes only nested directory files" do
          result = populate

          result.keys.each do |file_path|
            expect(file_path).not_to start_with(ignored_path)
          end

          # Other constants should still be included
          expect(result.keys).to include(
            absolute_fixture_path("consumers/fully_qualified_consumer.rb")
          )
        end

        it "does not include nested constant file dependencies" do
          result = populate

          result.each_value do |deps|
            deps.keys.each do |dep_path|
              expect(dep_path).not_to start_with(ignored_path)
            end
          end
        end
      end

      context "when ignored_path is outside root_path" do
        let(:ignored_path) { "/some/other/path" }

        it "does not affect the results (nothing to exclude)" do
          result = populate

          # Should have same results as when ignored_path is nil
          expect(result.keys).to include(
            absolute_fixture_path("consumers/fully_qualified_consumer.rb")
          )
        end
      end
    end

    describe ".fetch_static_dependencies" do
      before do
        # Populate the map first
        described_class.populate!(root_path, ignored_path)
      end

      context "when file exists in the map" do
        let(:file_path) { absolute_fixture_path("consumers/fully_qualified_consumer.rb") }

        it "returns the dependencies hash for the file" do
          result = described_class.fetch_static_dependencies(file_path)

          expect(result).to be_a(Hash)
          expect(result.keys).to include(
            absolute_fixture_path("constants/base_constant.rb")
          )
        end
      end

      context "when file does not exist in the map" do
        let(:file_path) { "/nonexistent/file.rb" }

        it "returns empty hash" do
          result = described_class.fetch_static_dependencies(file_path)
          expect(result).to eq({})
        end
      end

      context "when file is nil" do
        it "returns empty hash" do
          result = described_class.fetch_static_dependencies(nil)
          expect(result).to eq({})
        end
      end

      context "when @dependencies_map is nil" do
        before do
          described_class.instance_variable_set(:@dependencies_map, nil)
        end

        it "returns empty hash" do
          result = described_class.fetch_static_dependencies(absolute_fixture_path("consumers/fully_qualified_consumer.rb"))
          expect(result).to eq({})
        end
      end
    end
  end

  context "when native extension is NOT available" do
    before do
      stub_const("Datadog::CI::SourceCode::StaticDependencies::STATIC_DEPENDENCIES_AVAILABLE", false)
    end

    describe ".fetch_static_dependencies" do
      it "returns empty hash" do
        result = described_class.fetch_static_dependencies("/any/file.rb")
        expect(result).to eq({})
      end

      it "returns empty hash even with valid file" do
        result = described_class.fetch_static_dependencies(
          absolute_fixture_path("consumers/fully_qualified_consumer.rb")
        )
        expect(result).to eq({})
      end
    end
  end

  describe "constant name pattern coverage" do
    before do
      skip unless Datadog::CI::SourceCode::StaticDependencies::STATIC_DEPENDENCIES_AVAILABLE
      described_class.populate!(root_path, ignored_path)
    end

    context "fully qualified constant names (opt_getconstant_path)" do
      it "resolves Constants::BaseConstant" do
        deps = described_class.fetch_static_dependencies(
          absolute_fixture_path("consumers/fully_qualified_consumer.rb")
        )
        expect(deps.keys).to include(
          absolute_fixture_path("constants/base_constant.rb")
        )
      end

      it "resolves Constants::Nested::DeeplyNestedConstant" do
        deps = described_class.fetch_static_dependencies(
          absolute_fixture_path("consumers/fully_qualified_consumer.rb")
        )
        expect(deps.keys).to include(
          absolute_fixture_path("constants/nested/deeply_nested_constant.rb")
        )
      end

      it "resolves Constants::AnotherConstant" do
        deps = described_class.fetch_static_dependencies(
          absolute_fixture_path("consumers/fully_qualified_consumer.rb")
        )
        expect(deps.keys).to include(
          absolute_fixture_path("constants/another_constant.rb")
        )
      end
    end

    context "root-level constant access with ::" do
      it "resolves ::StandaloneClass" do
        deps = described_class.fetch_static_dependencies(
          absolute_fixture_path("consumers/mixed_consumer.rb")
        )
        expect(deps.keys).to include(
          absolute_fixture_path("constants/standalone_class.rb")
        )
      end
    end

    context "constants in lambdas and blocks" do
      it "resolves constants referenced inside lambdas" do
        deps = described_class.fetch_static_dependencies(
          absolute_fixture_path("consumers/lambda_consumer.rb")
        )

        expect(deps.keys).to include(
          absolute_fixture_path("constants/base_constant.rb")
        )
      end

      it "resolves constants referenced inside blocks" do
        deps = described_class.fetch_static_dependencies(
          absolute_fixture_path("consumers/lambda_consumer.rb")
        )

        expect(deps.keys).to include(
          absolute_fixture_path("constants/another_constant.rb")
        )
      end

      it "resolves constants referenced inside Proc.new blocks" do
        deps = described_class.fetch_static_dependencies(
          absolute_fixture_path("consumers/lambda_consumer.rb")
        )

        expect(deps.keys).to include(
          absolute_fixture_path("constants/standalone_class.rb")
        )
      end
    end

    context "constants in conditional statements" do
      it "resolves constants in if/else branches" do
        deps = described_class.fetch_static_dependencies(
          absolute_fixture_path("consumers/conditional_consumer.rb")
        )

        expect(deps.keys).to include(
          absolute_fixture_path("constants/base_constant.rb"),
          absolute_fixture_path("constants/another_constant.rb")
        )
      end

      it "resolves constants in case/when statements" do
        deps = described_class.fetch_static_dependencies(
          absolute_fixture_path("consumers/conditional_consumer.rb")
        )

        expect(deps.keys).to include(
          absolute_fixture_path("constants/nested/deeply_nested_constant.rb"),
          absolute_fixture_path("constants/standalone_class.rb")
        )
      end
    end

    context "constants in rescue/ensure blocks" do
      it "resolves constants in begin/rescue/ensure" do
        deps = described_class.fetch_static_dependencies(
          absolute_fixture_path("consumers/rescue_consumer.rb")
        )

        expect(deps.keys).to include(
          absolute_fixture_path("constants/base_constant.rb"),
          absolute_fixture_path("constants/another_constant.rb"),
          absolute_fixture_path("constants/standalone_class.rb")
        )
      end
    end

    context "constants assigned to local variables" do
      it "resolves constants assigned to variables" do
        deps = described_class.fetch_static_dependencies(
          absolute_fixture_path("consumers/constant_assignment_consumer.rb")
        )

        expect(deps.keys).to include(
          absolute_fixture_path("constants/base_constant.rb"),
          absolute_fixture_path("constants/another_constant.rb"),
          absolute_fixture_path("constants/standalone_class.rb")
        )
      end
    end
  end

  describe "edge cases and error handling" do
    before do
      skip unless Datadog::CI::SourceCode::StaticDependencies::STATIC_DEPENDENCIES_AVAILABLE
    end

    it "handles rapid consecutive populate! calls" do
      10.times do
        result = described_class.populate!(root_path, nil)
        expect(result).to be_a(Hash)
      end
    end

    it "survives GC after populate!" do
      described_class.populate!(root_path, nil)
      GC.start(full_mark: true, immediate_sweep: true)

      result = described_class.fetch_static_dependencies(
        absolute_fixture_path("consumers/fully_qualified_consumer.rb")
      )
      expect(result).to be_a(Hash)
    end

    it "handles populate! with trailing slash in root_path" do
      result = described_class.populate!("#{root_path}/", nil)
      # Files don't have double slashes, so this might affect matching
      # The implementation should handle this gracefully
      expect(result).to be_a(Hash)
    end

    it "handles populate! with different ignored_path types gracefully" do
      # Empty string - should not crash
      expect { described_class.populate!(root_path, "") }.not_to raise_error

      # Very long string - should not crash
      expect { described_class.populate!(root_path, "a" * 10000) }.not_to raise_error
    end
  end

  describe "integration with actual Ruby code execution" do
    before do
      skip unless Datadog::CI::SourceCode::StaticDependencies::STATIC_DEPENDENCIES_AVAILABLE
      described_class.populate!(root_path, nil)
    end

    it "tracks dependencies from code that can actually run" do
      # Verify the fixtures work at runtime
      consumer = FullyQualifiedConsumer.new
      expect(consumer.use_base).to eq("base")
      expect(consumer.use_nested).to eq("deeply_nested")
      expect(consumer.use_another).to eq("another")

      # And verify dependencies are tracked
      deps = described_class.fetch_static_dependencies(
        absolute_fixture_path("consumers/fully_qualified_consumer.rb")
      )
      expect(deps).not_to be_empty
    end
  end

  # ============================================================================
  # KNOWN LIMITATIONS
  # ============================================================================
  #
  # The StaticDependencies native extension analyzes Ruby bytecode (ISeqs) to
  # find constant references. It has the following known limitations:
  #
  # 1. CLASS-LEVEL CONSTANT RESOLUTION NOT TRACKED
  #    The extension scans method body bytecode only. Class-level operations
  #    like inheritance (`class Foo < Bar`) and module inclusion
  #    (`include SomeModule`) happen at class definition time and are not
  #    captured in method ISeqs.
  #
  # 2. UNQUALIFIED CONSTANT NAMES NOT RESOLVED
  #    When constants are referenced without full qualification (e.g., `BaseConstant`
  #    instead of `Constants::BaseConstant`), the `getconstant` instruction only
  #    contains the symbol name. `Object.const_source_location("BaseConstant")`
  #    cannot resolve it to `Constants::BaseConstant`.
  #
  # 3. CONSTANTS DEFINED IN C EXTENSIONS
  #    Built-in Ruby constants (String, Array, Hash, etc.) and constants from
  #    C extensions have no source location and are not tracked.
  #
  # 4. TOP-LEVEL ISEQS MAY BE GC'D
  #    ISeqs from top-level file code may be garbage collected, so constants
  #    referenced only at file load time might not be captured. Method ISeqs
  #    typically survive longer.
  #
  # ============================================================================

  describe "known limitations" do
    before do
      skip unless Datadog::CI::SourceCode::StaticDependencies::STATIC_DEPENDENCIES_AVAILABLE
      described_class.populate!(root_path, nil)
    end

    context "class-level constant resolution" do
      it "does not track inheritance patterns (class Foo < Bar)" do
        deps = described_class.fetch_static_dependencies(
          absolute_fixture_path("consumers/inheritance_consumer.rb")
        ) || {}

        # InheritanceConsumer < Constants::BaseConstant is a class-level operation
        # The native extension scans method body bytecode, not class definition bytecode
        expect(deps.keys).not_to include(
          absolute_fixture_path("constants/base_constant.rb")
        )
      end

      it "does not track module mixin patterns (include SomeModule)" do
        deps = described_class.fetch_static_dependencies(
          absolute_fixture_path("consumers/mixin_consumer.rb")
        ) || {}

        # include Constants::Mixable is a class-level operation
        expect(deps.keys).not_to include(
          absolute_fixture_path("constants/module_with_mixin.rb")
        )
      end

      it "inheritance still works at runtime despite not being tracked" do
        # Verify the code runs correctly at runtime even though static analysis doesn't track it
        expect(InheritanceConsumer.extended_value).to eq("base_extended")
      end

      it "module inclusion still works at runtime despite not being tracked" do
        # Verify the code runs correctly at runtime even though static analysis doesn't track it
        consumer = MixinConsumer.new
        expect(consumer.use_mixin).to eq("from_mixin")
      end
    end

    context "unqualified constant names" do
      it "does not resolve unqualified constant names within module scope" do
        deps = described_class.fetch_static_dependencies(
          absolute_fixture_path("consumers/unqualified_consumer.rb")
        )

        # The getconstant instruction for unqualified names like BaseConstant
        # passes just the symbol name to const_source_location.
        # Object.const_source_location("BaseConstant") won't find
        # Constants::BaseConstant, so these are NOT resolved.
        expect(deps.keys).not_to include(
          absolute_fixture_path("constants/base_constant.rb")
        )
      end
    end

    context "built-in and C extension constants" do
      it "does not include built-in Ruby constants as dependencies" do
        deps = described_class.fetch_static_dependencies(
          absolute_fixture_path("consumers/builtin_const_consumer.rb")
        ) || {}

        # Built-in constants like String, Array, Hash, File, Dir have no source location
        # and should not appear as dependencies
        deps.keys.each do |dep_path|
          expect(dep_path).not_to match(/ruby.*lib/)
        end
      end
    end
  end
end
