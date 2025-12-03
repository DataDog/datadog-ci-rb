# frozen_string_literal: true

require "tmpdir"
require "fileutils"

require_relative "../../../../lib/datadog/ci/test_optimisation/dependencies_tracker"

def write_ruby_file(root, relative_path, contents)
  absolute_path = File.join(root, relative_path)
  FileUtils.mkdir_p(File.dirname(absolute_path))
  File.write(absolute_path, contents)
  absolute_path
end

def constants_for(tracker, root, relative_path)
  tracker.constants_used_by_file[File.join(root, relative_path)]
end

RSpec.describe Datadog::CI::TestOptimisation::DependenciesTracker do
  subject(:tracker) { described_class.new(bundle_location: bundle_location) }

  let(:bundle_location) { nil }
  let(:root_path) { "/repo/project" }

  before do
    allow(Datadog::CI::Git::LocalRepository).to receive(:root).and_return(root_path)
  end

  describe "#initialize" do
    context "when bundle_location is within the repo" do
      let(:bundle_location) { "/repo/project/vendor/bundle" }

      it "keeps the relative path" do
        expect(tracker.bundle_location).to eq("/repo/project/vendor/bundle")
      end
    end

    context "when bundle_location is outside of the repo" do
      let(:bundle_location) { "/tmp/custom_bundle" }

      it "ignores the bundle location" do
        expect(tracker.bundle_location).to eq("/tmp/custom_bundle")
      end
    end

    context "when bundle_location is nil" do
      it "keeps bundle_location nil" do
        expect(tracker.bundle_location).to eq(nil)
      end
    end
  end

  describe "#trackable_file?" do
    let(:bundle_location) { "/repo/project/bundle" }

    it "returns true for non-bundle paths" do
      expect(tracker.send(:trackable_file?, "/repo/project/lib/app.rb")).to be true
      expect(tracker.send(:trackable_file?, "/repo/project/spec/app_spec.rb")).to be true
      expect(tracker.send(:trackable_file?, "/repo/project/bundlelib/file.rb")).to be true
    end

    it "returns false when path is nil" do
      expect(tracker.send(:trackable_file?, nil)).to be false
    end

    it "returns false for empty paths" do
      expect(tracker.send(:trackable_file?, "")).to be false
    end

    it "returns false for files under the configured bundle location" do
      expect(tracker.send(:trackable_file?, "/repo/project/bundle")).to be false
      expect(tracker.send(:trackable_file?, "/repo/project/bundle/app.rb")).to be false
      expect(tracker.send(:trackable_file?, "/repo/project/bundle/lib/app.rb")).to be false
    end
  end

  describe "#load" do
    let(:tmp_root) { Dir.mktmpdir }
    let(:root_path) { tmp_root }
    let(:bundle_location) { File.join(root_path, "bundle") }

    before do
      write_ruby_file(
        root_path,
        "lib/token.rb",
        <<~RUBY
          module Token
            NUMBER = "NUMBER"
            PLUS = "PLUS"
          end
        RUBY
      )

      write_ruby_file(
        root_path,
        "lib/tokenizer.rb",
        <<~RUBY
          require_relative "token"

          module Tokenizer
            class Lexer
              def initialize(buffer)
                Token::NUMBER
                Token::PLUS
                ::String
                ::Kernel
              end
            end
          end
        RUBY
      )

      write_ruby_file(
        root_path,
        "lib/ast/nodes.rb",
        <<~RUBY
          module AST
            class Node; end

            class NumberNode < Node
            end

            class BinaryNode < Node
              TYPE = :binary
            end
          end
        RUBY
      )

      write_ruby_file(
        root_path,
        "lib/builders/addition.rb",
        <<~RUBY
          require_relative "../ast/nodes"
          require_relative "../token"

          module Builders
            class Addition
              def initialize
                AST::BinaryNode
                Token::PLUS
                Token::NUMBER
                ::Kernel.warn(nil)
              end
            end
          end
        RUBY
      )

      write_ruby_file(
        root_path,
        "lib/parser.rb",
        <<~RUBY
          require_relative "tokenizer"
          require_relative "builders/addition"
          require_relative "ast/nodes"

          module Parser
            class Engine
              def parse(buffer)
                lexer = Tokenizer::Lexer.new(buffer)
                Builders::Addition.new
                AST::NumberNode
                AST::BinaryNode::TYPE
                ::Math::PI
                ::Kernel.warn(SOME_CONST)
                lexer
              end
            end
          end
        RUBY
      )

      write_ruby_file(root_path, "bundle/ignored.rb", "module Ignored; Ghost::Dependency; end\n")
    end

    after do
      FileUtils.remove_entry(tmp_root)
    end

    it "records constant usage for parser files" do
      tracker.load

      parser_constants = constants_for(tracker, root_path, "lib/parser.rb")
      expect(parser_constants).to include("Tokenizer")
      expect(parser_constants).to include("Tokenizer::Lexer")
      expect(parser_constants).to include("Builders")
      expect(parser_constants).to include("Builders::Addition")
      expect(parser_constants).to include("AST::NumberNode")
      expect(parser_constants).to include("AST::BinaryNode")
      expect(parser_constants).to include("AST::BinaryNode::TYPE")
      expect(parser_constants).to include("::Math::PI")
      expect(parser_constants).to include("::Kernel")
      expect(parser_constants).to include("SOME_CONST")
    end

    it "records constant usage for supporting files" do
      tracker.load

      tokenizer_constants = constants_for(tracker, root_path, "lib/tokenizer.rb")
      expect(tokenizer_constants).to include("Token")
      expect(tokenizer_constants).to include("Token::NUMBER")
      expect(tokenizer_constants).to include("Token::PLUS")
      expect(tokenizer_constants).to include("::String")
      expect(tokenizer_constants).to include("::Kernel")

      builder_constants = constants_for(tracker, root_path, "lib/builders/addition.rb")
      expect(builder_constants).to include("AST::BinaryNode")
      expect(builder_constants).to include("Token::PLUS")
      expect(builder_constants).to include("Token::NUMBER")
      expect(builder_constants).to include("::Kernel")
    end

    it "ignores files under bundle location" do
      tracker.load

      ignored_file = File.join(root_path, "bundle", "ignored.rb")
      expect(tracker.constants_used_by_file).not_to have_key(ignored_file)
    end
  end
end
