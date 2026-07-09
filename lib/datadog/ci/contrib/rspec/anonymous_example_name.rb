# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module RSpec
        module AnonymousExampleName
          ISEQ_SIMPLE_DATA_FORMAT = "YARVInstructionSequence/SimpleDataFormat"

          SELF_VALUE = :__datadog_rspec_self__
          EMPTY_ARGUMENTS = [].freeze
          MINIMUM_RUBY_VERSION = Gem::Version.new("3.2")

          EXPECTATION_METHODS = {
            to: "is expected to",
            not_to: "is expected not to",
            to_not: "is expected not to"
          }.freeze
          SHOULD_METHODS = {
            should: "is expected to",
            should_not: "is expected not to"
          }.freeze
          OPERATOR_METHODS = %i[== != === =~ !~ < <= > >= + - * / %].each_with_object({}) { |method_name, methods|
            methods[method_name] = true
          }.freeze
          MATCHER_CHAIN_METHODS = %i[
            and
            at_least
            at_most
            by
            by_at_least
            by_at_most
            exactly
            from
            of
            once
            or
            times
            to
            twice
            with
            within
          ].each_with_object({}) { |method_name, methods|
            methods[method_name] = true
          }.freeze
          PRETTY_MATCHER_PREFIXES = %w[be_ have_ raise_ respond_ yield_ start_ end_].freeze
          PRETTY_MATCHER_METHODS = %i[
            be
            change
            contain_exactly
            eq
            eql
            equal
            exist
            include
            match
            output
            raise_error
            satisfy
            throw_symbol
          ].each_with_object({}) { |method_name, methods|
            methods[method_name] = true
          }.freeze
          MAX_RENDERED_VALUE_LENGTH = 80
          MAX_RENDERED_NAME_LENGTH = 180

          def self.supported?
            return false unless defined?(RubyVM::InstructionSequence)
            return false unless RUBY_ENGINE == "ruby"

            Gem::Version.new(RUBY_VERSION) >= MINIMUM_RUBY_VERSION
          end

          def self.call(target)
            return nil if target.nil?
            return nil unless supported?

            iseq = iseq_for(target)
            return nil unless iseq

            rendered_name = render_iseq(iseq)
            trim(rendered_name, MAX_RENDERED_NAME_LENGTH) if rendered_name
          rescue => e
            warn_anonymous_example_name_error(e)
            nil
          end

          def self.iseq_for(target)
            return target if target.is_a?(RubyVM::InstructionSequence)

            RubyVM::InstructionSequence.of(target)
          end
          private_class_method :iseq_for

          def self.render_iseq(iseq)
            body = iseq.to_a[13]
            return nil unless body.is_a?(Array)

            # Most anonymous RSpec examples end with `<expectation>.to <matcher>`.
            # Render only that known shape by walking backwards from the final matcher call:
            # it avoids simulating unrelated subject code, so dynamic values do not
            # leak into the name and dangerous user code is not evaluated.
            finish_index = last_name_finish_index(body)
            return nil unless finish_index

            call_data = body[finish_index][1]
            return nil unless call_data[:orig_argc].to_i == 1

            matcher_expression = render_expression_before(body, finish_index)
            return nil unless matcher_expression

            method_name = call_data[:mid]
            return nil if EXPECTATION_METHODS.key?(method_name) && !expectation_receiver_at?(body, matcher_expression[1])

            name_prefix = EXPECTATION_METHODS[method_name] || SHOULD_METHODS[method_name]
            "#{name_prefix} #{matcher_expression[0]}"
          end
          private_class_method :render_iseq

          def self.last_name_finish_index(body)
            index = body.length - 1

            while index >= 0
              entry = body[index]

              if entry.is_a?(Array)
                call_data = entry[1]
                if call_data.is_a?(Hash)
                  method_name = call_data[:mid]
                  return index if EXPECTATION_METHODS.key?(method_name) || SHOULD_METHODS.key?(method_name)
                end
              end

              index -= 1
            end

            nil
          end
          private_class_method :last_name_finish_index

          def self.expectation_receiver_at?(body, index)
            index = previous_instruction_index(body, index)
            return false unless index

            instruction = body[index]
            call_data = instruction[1]
            return false unless call_data.is_a?(Hash)

            method_name = call_data[:mid]
            method_name == :expect || method_name == :is_expected
          end
          private_class_method :expectation_receiver_at?

          def self.render_expression_before(body, index)
            expression_index = previous_instruction_index(body, index - 1)
            render_expression_ending_at(body, expression_index)
          end
          private_class_method :render_expression_before

          def self.render_expression_ending_at(body, index)
            return nil unless index

            index = previous_instruction_index(body, index)
            return nil unless index

            instruction = body[index]
            opcode = instruction[0]

            case opcode
            when :putself
              [SELF_VALUE, index - 1]
            when :putnil
              ["nil", index - 1]
            when :putobject, :putchilledstring, :putstring
              [render_literal(instruction[1]), index - 1]
            when :duparray
              [render_array_literal(instruction[1]), index - 1]
            when :duphash
              [render_hash_literal(instruction[1]), index - 1]
            when :newarray
              render_new_array_expression(body, index)
            when :newhash
              render_new_hash_expression(body, index)
            when :opt_getconstant_path
              [render_constant_path(instruction[1]), index - 1]
            when :pop
              render_optimized_new_expression(body, index)
            when :send, :opt_send_without_block, :opt_plus, :opt_minus, :opt_mult, :opt_div,
              :opt_mod, :opt_eq, :opt_neq, :opt_lt, :opt_le, :opt_gt, :opt_ge
              render_send_expression(body, index, instruction)
            else
              render_special_expression(index, instruction)
            end
          end
          private_class_method :render_expression_ending_at

          def self.render_new_array_expression(body, index)
            expression = render_expression_list_ending_at(body, index - 1, body[index][1].to_i)
            return nil unless expression

            [render_array_literal(expression[0]), expression[1]]
          end
          private_class_method :render_new_array_expression

          def self.render_new_hash_expression(body, index)
            expression = render_expression_list_ending_at(body, index - 1, body[index][1].to_i)
            return nil unless expression

            values = expression[0]
            pairs = values.each_slice(2).map { |key, value| "#{key} => #{value}" }
            ["{#{pairs.join(", ")}}", expression[1]]
          end
          private_class_method :render_new_hash_expression

          def self.render_optimized_new_expression(body, index)
            # Ruby 4 compiles zero-argument `Class.new` with `opt_new` followed by
            # constructor bookkeeping and a final `pop`. Collapse that whole shape
            # back to the receiver class so `Object.new` renders as stable `Object`.
            swap_index = previous_instruction_index(body, index - 1)
            return nil unless swap_index
            return nil unless body[swap_index][0] == :swap

            receiver_index = optimized_new_receiver_index(body, swap_index - 1)
            return nil unless receiver_index

            receiver_expression = render_expression_ending_at(body, receiver_index)
            return nil unless receiver_expression

            [render_send(receiver_expression[0], :new, EMPTY_ARGUMENTS, nil), receiver_expression[1]]
          end
          private_class_method :render_optimized_new_expression

          def self.optimized_new_receiver_index(body, index)
            while index >= 0
              entry = body[index]

              if entry.is_a?(Array) && entry[0] == :opt_new
                call_data = entry[1]
                if call_data.is_a?(Hash) && call_data[:mid] == :new && call_data[:orig_argc].to_i.zero?
                  swap_index = previous_instruction_index(body, index - 1)
                  return nil unless swap_index
                  return nil unless body[swap_index][0] == :swap

                  nil_index = previous_instruction_index(body, swap_index - 1)
                  return nil unless nil_index
                  return nil unless body[nil_index][0] == :putnil

                  return previous_instruction_index(body, nil_index - 1)
                end
              end

              index -= 1
            end

            nil
          end
          private_class_method :optimized_new_receiver_index

          def self.render_send_expression(body, index, instruction)
            call_data = instruction[1]
            return nil unless call_data.is_a?(Hash)

            argument_count = call_data[:orig_argc].to_i
            if argument_count.zero?
              arguments = EMPTY_ARGUMENTS
              receiver_end_index = index - 1
            else
              arguments_expression = render_expression_list_ending_at(body, index - 1, argument_count)
              return nil unless arguments_expression

              arguments = arguments_expression[0]
              receiver_end_index = arguments_expression[1]
            end

            receiver_index = previous_instruction_index(body, receiver_end_index)
            return nil unless receiver_index

            receiver_instruction = body[receiver_index]
            if receiver_instruction[0] == :putself
              receiver = SELF_VALUE
              previous_index = receiver_index - 1
            else
              receiver_expression = render_expression_ending_at(body, receiver_index)
              return nil unless receiver_expression

              receiver = receiver_expression[0]
              previous_index = receiver_expression[1]
            end

            block_iseq = instruction[2] if iseq_array?(instruction[2])
            rendered_send = render_send(receiver, call_data[:mid], arguments, block_iseq)

            [rendered_send, previous_index]
          end
          private_class_method :render_send_expression

          def self.render_expression_list_ending_at(body, index, count)
            return [[], index] if count <= 0

            arguments = Array.new(count)
            argument_index = count - 1

            while argument_index >= 0
              expression = render_expression_ending_at(body, index)
              return nil unless expression

              arguments[argument_index] = expression[0]
              index = expression[1]
              argument_index -= 1
            end

            [arguments, index]
          end
          private_class_method :render_expression_list_ending_at

          def self.previous_instruction_index(body, index)
            while index >= 0
              return index if body[index].is_a?(Array)

              index -= 1
            end

            nil
          end
          private_class_method :previous_instruction_index

          def self.render_special_expression(index, instruction)
            opcode = instruction[0].to_s

            if opcode.start_with?("putobject_INT2FIX_")
              [opcode.delete_prefix("putobject_INT2FIX_").delete_suffix("_"), index - 1]
            elsif opcode.start_with?("getlocal")
              ["local", index - 1]
            end
          end
          private_class_method :render_special_expression

          def self.render_send(receiver, method_name, arguments, block_iseq)
            if receiver == SELF_VALUE && arguments.empty? && !block_iseq
              method_text = method_name.to_s
              return pretty_matcher_method?(method_name, method_text) ? method_text.tr("_", " ") : method_text
            end

            return receiver if method_name == :new && arguments.empty? && constant_name?(receiver)

            render_method_call(receiver, method_name, arguments, block_iseq)
          end
          private_class_method :render_send

          def self.render_method_call(receiver, method_name, arguments, block_iseq)
            method_text = method_name.to_s
            matcher_chain = MATCHER_CHAIN_METHODS.key?(method_name)

            if (receiver == SELF_VALUE || matcher_chain || block_iseq) &&
                (pretty_matcher_method?(method_name, method_text) || !arguments.empty? || block_iseq)
              method_text = method_text.tr("_", " ")
            end

            argument_text = arguments.compact.join(", ")
            receiver_text = (receiver == SELF_VALUE) ? "self" : receiver.to_s

            if OPERATOR_METHODS.key?(method_name)
              return "#{receiver_text} #{method_name} #{argument_text}".strip
            end

            if receiver == SELF_VALUE
              return argument_text.empty? ? method_text : "#{method_text} #{argument_text}"
            end

            if matcher_chain
              return argument_text.empty? ? "#{receiver} #{method_text}" : "#{receiver} #{method_text} #{argument_text}"
            end

            argument_suffix = argument_text.empty? ? "" : "(#{argument_text})"
            "#{receiver_text}.#{method_name}#{argument_suffix}"
          end
          private_class_method :render_method_call

          def self.pretty_matcher_method?(method_name, method_text)
            PRETTY_MATCHER_METHODS.key?(method_name) ||
              PRETTY_MATCHER_PREFIXES.any? { |prefix| method_text.start_with?(prefix) }
          end
          private_class_method :pretty_matcher_method?

          def self.render_literal(value)
            rendered_value =
              case value
              when nil
                "nil"
              when true
                "true"
              when false
                "false"
              when Symbol
                value.inspect
              when String
                value.inspect
              when Numeric
                value.to_s
              when Regexp
                value.inspect
              when Array
                render_array_literal(value)
              when Hash
                render_hash_literal(value)
              else
                value.class.name || "value"
              end

            trim(rendered_value, MAX_RENDERED_VALUE_LENGTH)
          end
          private_class_method :render_literal

          def self.render_array_literal(value)
            return "[]" unless value.is_a?(Array)

            "[#{value.map { |element| render_literal(element) }.join(", ")}]"
          end
          private_class_method :render_array_literal

          def self.render_hash_literal(value)
            return "{}" unless value.is_a?(Hash)

            pairs = value.keys.sort_by(&:to_s).map do |key|
              "#{render_literal(key)} => #{render_literal(value[key])}"
            end

            "{#{pairs.join(", ")}}"
          end
          private_class_method :render_hash_literal

          def self.render_constant_path(value)
            return "constant" unless value.is_a?(Array)

            value.compact.join("::")
          end
          private_class_method :render_constant_path

          def self.constant_name?(value)
            value.is_a?(String) && value.match?(/\A[A-Z]\w*(?:::[A-Z]\w*)*\z/)
          end
          private_class_method :constant_name?

          def self.iseq_array?(value)
            value.is_a?(Array) && value[0] == ISEQ_SIMPLE_DATA_FORMAT
          end
          private_class_method :iseq_array?

          def self.trim(value, max_length)
            return value if value.length <= max_length

            "#{value[0, max_length - 3]}..."
          end
          private_class_method :trim

          def self.warn_anonymous_example_name_error(error)
            message = "Unable to compute RSpec anonymous example name: #{error.class}: #{error.message}"

            if defined?(Datadog) && Datadog.respond_to?(:logger) && Datadog.logger
              Datadog.logger.warn { message }
            else
              Kernel.warn(message)
            end

            nil
          rescue
            nil
          end
          private_class_method :warn_anonymous_example_name_error
        end
      end
    end
  end
end
