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

        values_match? expected, @actual
      end

      def description_of(actual) # rubocop:disable Lint/NestedMethodDefinition
        "Span with error #{@tag_name} #{super}"
      end
    end
  end

  define_have_error_tag(:message, Datadog::Tracing::Metadata::Ext::Errors::TAG_MSG)
  define_have_error_tag(:stack, Datadog::Tracing::Metadata::Ext::Errors::TAG_STACK)
  define_have_error_tag(:type, Datadog::Tracing::Metadata::Ext::Errors::TAG_TYPE)

  RSpec::Matchers.define :a_span_with do |expected|
    match do |actual|
      actual.instance_of?(Datadog::Tracing::Span) &&
        expected.all? do |key, value|
          actual.__send__(key) == value
        end
    end
  end
end
