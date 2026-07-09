# frozen_string_literal: true

require "digest/sha2"

module Datadog
  module CI
    module SourceCode
      begin
        require "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}"

        ISEQ_HASH_NATIVE_AVAILABLE = respond_to?(:_native_iseq_hash)
      rescue LoadError
        ISEQ_HASH_NATIVE_AVAILABLE = false
      end

      ISEQ_HASH_LENGTH = 16
      ISEQ_SIMPLE_DATA_FORMAT = "YARVInstructionSequence/SimpleDataFormat"
      ISEQ_METADATA_KEYS = %i[arg_size local_size stack_max].freeze

      def self.iseq_hash(target)
        if ISEQ_HASH_NATIVE_AVAILABLE
          native_hash = _native_iseq_hash(target)
          return native_hash if native_hash
        end

        iseq = iseq_for(target)
        return "" unless iseq

        normalized_iseq = normalize_iseq_array(iseq.to_a)

        Digest::SHA256.hexdigest(Marshal.dump(normalized_iseq))[0, ISEQ_HASH_LENGTH].to_s
      rescue => e
        warn_iseq_hash_error(e)
        ""
      end

      def self.iseq_for(target)
        return nil if target.nil?
        return target if target.is_a?(RubyVM::InstructionSequence)

        RubyVM::InstructionSequence.of(target)
      end
      private_class_method :iseq_for

      def self.normalize_iseq_array(iseq_array)
        return normalize_value(iseq_array) unless iseq_array?(iseq_array)

        metadata = iseq_array[4].is_a?(Hash) ? iseq_array[4] : {}

        {
          "format" => iseq_array[0],
          "metadata" => normalize_iseq_metadata(metadata),
          "type" => normalize_value(iseq_array[9]),
          "locals" => normalize_value(iseq_array[10]),
          "params" => normalize_value(iseq_array[11]),
          "catch_table" => normalize_value(iseq_array[12]),
          "body" => normalize_body(iseq_array[13])
        }
      end
      private_class_method :normalize_iseq_array

      def self.iseq_array?(value)
        value.is_a?(Array) && value[0] == ISEQ_SIMPLE_DATA_FORMAT
      end
      private_class_method :iseq_array?

      def self.normalize_iseq_metadata(metadata)
        ISEQ_METADATA_KEYS.each_with_object({}) do |key, normalized_metadata|
          normalized_metadata[key] = normalize_value(metadata[key]) if metadata.key?(key)
        end
      end
      private_class_method :normalize_iseq_metadata

      def self.normalize_body(body)
        return normalize_value(body) unless body.is_a?(Array)

        body.each_with_object([]) do |entry, normalized_body|
          next if entry.is_a?(Integer)

          normalized_body << normalize_value(entry)
        end
      end
      private_class_method :normalize_body

      def self.normalize_value(value)
        case value
        when Array
          iseq_array?(value) ? normalize_iseq_array(value) : value.map { |element| normalize_value(element) }
        when Hash
          value
            .keys
            .sort_by { |key| key.to_s }
            .map { |key| [normalize_value(key), normalize_value(value[key])] }
        when Regexp
          ["Regexp", value.source, value.options]
        when Range
          ["Range", normalize_value(value.begin), normalize_value(value.end), value.exclude_end?]
        when Symbol, String, Numeric, true, false, nil
          value
        else
          [value.class.name, value.inspect]
        end
      end
      private_class_method :normalize_value

      def self.warn_iseq_hash_error(error)
        message = "Unable to compute Ruby ISeq hash"
        message = "#{message}: #{error.class}: #{error.message}"

        warn_iseq_hash_message(message)
      rescue
        warn_iseq_hash_message_fallback(message || "Unable to compute Ruby ISeq hash")
      end
      private_class_method :warn_iseq_hash_error

      def self.warn_iseq_hash_message(message)
        if defined?(Datadog) && Datadog.respond_to?(:logger) && Datadog.logger
          Datadog.logger.warn { message }
        else
          warn_iseq_hash_message_fallback(message)
        end
      end
      private_class_method :warn_iseq_hash_message

      def self.warn_iseq_hash_message_fallback(message)
        Kernel.warn(message)
      rescue
        nil
      end
      private_class_method :warn_iseq_hash_message_fallback
    end
  end
end
