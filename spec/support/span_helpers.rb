module SpanHelpers
  RSpec::Matchers.define :have_error do
    match do |span|
      @actual = span.status
      values_match? Datadog::Tracing::Metadata::Ext::Errors::STATUS, @actual
    end

    def description_of(actual)
      "Span with status #{super}"
    end
  end

  def self.define_have_error_tag(tag_name, tag)
    RSpec::Matchers.define "have_error_#{tag_name}" do |*args|
      match do |span|
        expected = args.first

        @tag_name = tag_name
        @actual = span.get_tag(tag)

        if args.empty? && @actual
          # This condition enables the default matcher:
          # expect(foo).to have_error_tag
          return true
        end

        values_match? expected, @actual
      end

      match_when_negated do |span|
        expected = args.first

        @tag_name = tag_name
        @actual = span.get_tag(tag)

        if args.empty? && @actual.nil?
          # This condition enables the default matcher:
          # expect(foo).to_not have_error_tag
          return true
        end

        !values_match?(expected, @actual)
      end

      def description_of(actual) # rubocop:disable Lint/NestedMethodDefinition
        "Span with error #{@tag_name} #{super}"
      end
    end
  end

  define_have_error_tag(:message, Datadog::Tracing::Metadata::Ext::Errors::TAG_MSG)
  define_have_error_tag(:stack, Datadog::Tracing::Metadata::Ext::Errors::TAG_STACK)
  define_have_error_tag(:type, Datadog::Tracing::Metadata::Ext::Errors::TAG_TYPE)

  def test_tag_name(tag)
    if tag.is_a?(Symbol)
      Object.const_get("Datadog::CI::Ext::Test::TAG_#{tag.to_s.upcase}")
    else
      tag
    end
  end

  RSpec::Matchers.define "have_test_tag" do |*args|
    match do |span|
      tag = args.first
      expected = args.last

      @tag_name = test_tag_name(tag)
      @actual = span.get_tag(@tag_name)

      if args.count == 1 && @actual
        # This condition enables the default matcher:
        # expect(foo).to have_test_tag(:framework)
        return true
      end

      values_match? expected, @actual
    end

    match_when_negated do |span|
      tag = args.first
      expected = args.last

      @tag_name = test_tag_name(tag)
      @actual = span.get_tag(@tag_name)

      if args.count == 1 && @actual.nil?
        # This condition enables the default matcher:
        # expect(foo).to_not have_test_tag(:framework)
        return true
      end

      !values_match?(expected, @actual)
    end

    def description_of(actual) # rubocop:disable Lint/NestedMethodDefinition
      "Span with tag #{@tag_name} #{super}"
    end
  end

  RSpec::Matchers.define "have_origin" do |*args|
    match do |span|
      expected = args.first

      @actual = span.get_tag(Datadog::Tracing::Metadata::Ext::Distributed::TAG_ORIGIN)

      if args.empty? && @actual
        # This condition enables the default matcher:
        # expect(foo).to have_origin
        return true
      end

      values_match? expected, @actual
    end

    def description_of(actual) # rubocop:disable Lint/NestedMethodDefinition
      "Span with origin #{super}"
    end
  end

  %w[skip pass fail].each do |status|
    RSpec::Matchers.define "have_#{status}_status" do
      match do |span|
        @actual = span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)
        values_match? status, @actual
      end

      def description_of(actual) # rubocop:disable Lint/NestedMethodDefinition
        "Span with status #{super}"
      end
    end
  end

  RSpec::Matchers.define "have_tag_values_no_order" do |*args|
    match do |spans|
      tag = args.first
      expected = args.last

      @tag_name = test_tag_name(tag)
      @actual = spans.map { |span| span.get_tag(@tag_name) }.sort

      values_match? expected.sort, @actual
    end

    def description_of(actual) # rubocop:disable Lint/NestedMethodDefinition
      "spans with tags #{@tag_name} #{super}"
    end
  end

  RSpec::Matchers.define "have_unique_tag_values_count" do |*args|
    match do |spans|
      tag = args.first
      expected = args.last

      @tag_name = test_tag_name(tag)
      @actual = spans.map { |span| span.get_tag(@tag_name) }.uniq.count

      values_match? expected, @actual
    end

    def description_of(actual) # rubocop:disable Lint/NestedMethodDefinition
      "spans with tags #{@tag_name} #{super}"
    end
  end
end
