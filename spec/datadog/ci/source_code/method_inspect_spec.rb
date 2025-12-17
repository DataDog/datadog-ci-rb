# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/source_code/method_inspect"
require "spec_helper"

RSpec.describe Datadog::CI::SourceCode::MethodInspect do
  let(:dummy_class) do
    Class.new do
      def foo
        "foo"
      end
    end
  end

  let(:foo_method) { dummy_class.instance_method(:foo) }
  let(:foo_proc) {
    proc {
      "foo"
    }
  }

  describe ".last_line" do
    subject { described_class.last_line(target) }

    context "when LAST_LINE_AVAILABLE" do
      before { skip if PlatformHelpers.jruby? }

      before do
        stub_const("Datadog::CI::SourceCode::MethodInspect::LAST_LINE_AVAILABLE", true)
      end

      context "with a method" do
        let(:target) { foo_method }
        it "returns the last line number" do
          expect(subject).to eq(11)
        end
      end

      context "with a Proc" do
        let(:target) { foo_proc }
        it "returns the last line number" do
          expect(subject).to eq(19)
        end
      end

      context "with arbitrary thing" do
        let(:target) { 42 }

        it "returns nil" do
          expect(subject).to eq(nil)
        end
      end
    end

    context "when LAST_LINE_AVAILABLE is false" do
      before do
        stub_const("Datadog::CI::SourceCode::MethodInspect::LAST_LINE_AVAILABLE", false)
      end

      let(:target) { foo_proc }
      it "returns nil" do
        expect(subject).to be_nil
      end
    end
  end
end
