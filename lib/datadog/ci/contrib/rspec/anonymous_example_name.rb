# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module RSpec
        module AnonymousExampleName
          ISEQ_SIMPLE_DATA_FORMAT = "YARVInstructionSequence/SimpleDataFormat"

          SELF_VALUE = :__datadog_rspec_self__
          EXPECTATION_VALUE = :__datadog_rspec_expectation__
          EXAMPLE_NAME_VALUE = :__datadog_rspec_example_name__
          EMPTY_ARGUMENTS = [].freeze

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

          def self.call(target)
            return nil if target.nil?

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

            rendered_name = render_fast_matcher_name(body)
            return rendered_name if rendered_name

            render_stack_matcher_name(body)
          end
          private_class_method :render_iseq

          def self.render_fast_matcher_name(body)
            finish_index = last_name_finish_index(body)
            return nil unless finish_index

            finish_instruction = body[finish_index]
            call_data = finish_instruction[1]
            return nil unless call_data.is_a?(Hash)

            method_name = call_data[:mid]
            return nil unless call_data[:orig_argc].to_i == 1

            name_prefix = EXPECTATION_METHODS[method_name]
            unless name_prefix
              name_prefix = SHOULD_METHODS[method_name]
              return nil unless name_prefix
            end

            matcher_expression = render_expression_before(body, finish_index)
            return nil unless matcher_expression
            return nil if EXPECTATION_METHODS.key?(method_name) && !expectation_receiver_at?(body, matcher_expression[1])

            "#{name_prefix} #{matcher_expression[0]}"
          end
          private_class_method :render_fast_matcher_name

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

          def self.render_stack_matcher_name(body)
            matcher_body = scan_anonymous_matcher_body(body)
            return nil unless matcher_body

            expect_index = (matcher_body == true) ? nil : matcher_body
            stack = expect_index ? [EXPECTATION_VALUE] : []
            start_index = expect_index ? expect_index + 1 : 0
            index = start_index

            while index < body.length
              entry = body[index]
              index += 1
              next unless entry.is_a?(Array)

              return nil unless process_instruction(stack, entry)
            end

            name_value?(stack.last) ? stack.last[1] : nil
          end
          private_class_method :render_stack_matcher_name

          def self.scan_anonymous_matcher_body(body)
            matcher_body = false
            expect_index = nil
            index = 0

            while index < body.length
              method_name = instruction_method_name(body[index])

              if method_name
                matcher_body ||= EXPECTATION_METHODS.key?(method_name) || SHOULD_METHODS.key?(method_name)
                expect_index ||= index if method_name == :expect
              end

              index += 1
            end

            matcher_body && (expect_index || true)
          end
          private_class_method :scan_anonymous_matcher_body

          def self.instruction_method_name(instruction)
            return nil unless instruction.is_a?(Array)

            call_data = instruction[1]
            call_data[:mid] if call_data.is_a?(Hash)
          end
          private_class_method :instruction_method_name

          def self.process_instruction(stack, instruction)
            opcode = instruction[0]

            case opcode
            when :putself
              stack << SELF_VALUE
              true
            when :putnil
              stack << "nil"
              true
            when :putobject, :putchilledstring, :putstring
              stack << render_literal(instruction[1])
              true
            when :duparray
              stack << render_array_literal(instruction[1])
              true
            when :duphash
              stack << render_hash_literal(instruction[1])
              true
            when :newarray
              stack << render_array_literal(pop_values(stack, instruction[1]))
              true
            when :newhash
              stack << render_new_hash(stack, instruction[1])
              true
            when :opt_getconstant_path
              stack << render_constant_path(instruction[1])
              true
            when :send, :opt_send_without_block, :opt_plus, :opt_minus, :opt_mult, :opt_div,
              :opt_mod, :opt_eq, :opt_neq, :opt_lt, :opt_le, :opt_gt, :opt_ge
              process_send(stack, instruction)
            when :leave, :nop
              true
            when :pop
              stack.pop
              true
            when :dup
              stack << stack.last
              true
            when :swap
              stack[-1], stack[-2] = stack[-2], stack[-1] if stack.length >= 2
              true
            else
              process_special_instruction(stack, instruction)
            end
          end
          private_class_method :process_instruction

          def self.process_special_instruction(stack, instruction)
            opcode = instruction[0].to_s

            if opcode.start_with?("putobject_INT2FIX_")
              stack << opcode.delete_prefix("putobject_INT2FIX_").delete_suffix("_")
              true
            elsif opcode.start_with?("getlocal")
              stack << "local"
              true
            else
              false
            end
          end
          private_class_method :process_special_instruction

          def self.process_send(stack, instruction)
            call_data = instruction[1]
            return false unless call_data.is_a?(Hash)

            method_name = call_data[:mid]
            argument_count = call_data[:orig_argc].to_i
            arguments = pop_values(stack, argument_count)
            receiver = stack.pop || SELF_VALUE
            block_iseq = instruction[2] if iseq_array?(instruction[2])

            stack << render_send(receiver, method_name, arguments, block_iseq)
            true
          end
          private_class_method :process_send

          def self.render_send(receiver, method_name, arguments, block_iseq)
            if method_name == :expect
              return EXPECTATION_VALUE
            end

            if method_name == :is_expected && receiver == SELF_VALUE
              return EXPECTATION_VALUE
            end

            if EXPECTATION_METHODS.key?(method_name) && receiver == EXPECTATION_VALUE && arguments.length == 1
              return example_name("#{EXPECTATION_METHODS[method_name]} #{arguments.first}")
            end

            if SHOULD_METHODS.key?(method_name) && arguments.length == 1
              return example_name("#{SHOULD_METHODS[method_name]} #{arguments.first}")
            end

            if receiver == SELF_VALUE && arguments.empty? && !block_iseq
              return render_self_method_name(method_name)
            end

            return receiver if method_name == :new && arguments.empty? && constant_name?(receiver)

            render_method_call(receiver, method_name, arguments, block_iseq)
          end
          private_class_method :render_send

          def self.render_self_method_name(method_name)
            method_text = method_name.to_s
            pretty_matcher_method?(method_name, method_text) ? method_text.tr("_", " ") : method_text
          end
          private_class_method :render_self_method_name

          def self.render_method_call(receiver, method_name, arguments, block_iseq)
            method_text = render_method_name(method_name, receiver, arguments, block_iseq)
            argument_text = render_arguments(arguments)

            if OPERATOR_METHODS.key?(method_name)
              return "#{render_receiver(receiver)} #{method_name} #{argument_text}".strip
            end

            if receiver == SELF_VALUE
              return argument_text.empty? ? method_text : "#{method_text} #{argument_text}"
            end

            if matcher_chain_method?(method_name)
              return argument_text.empty? ? "#{receiver} #{method_text}" : "#{receiver} #{method_text} #{argument_text}"
            end

            argument_suffix = argument_text.empty? ? "" : "(#{argument_text})"
            "#{render_receiver(receiver)}.#{method_name}#{argument_suffix}"
          end
          private_class_method :render_method_call

          def self.render_method_name(method_name, receiver, arguments, block_iseq)
            method_text = method_name.to_s
            return method_text unless receiver == SELF_VALUE || matcher_chain_method?(method_name) || block_iseq
            return method_text unless pretty_matcher_method?(method_name, method_text) || !arguments.empty? || block_iseq

            method_text.tr("_", " ")
          end
          private_class_method :render_method_name

          def self.pretty_matcher_method?(method_name, method_text)
            PRETTY_MATCHER_METHODS.key?(method_name) ||
              PRETTY_MATCHER_PREFIXES.any? { |prefix| method_text.start_with?(prefix) }
          end
          private_class_method :pretty_matcher_method?

          def self.matcher_chain_method?(method_name)
            MATCHER_CHAIN_METHODS.key?(method_name)
          end
          private_class_method :matcher_chain_method?

          def self.render_arguments(arguments)
            arguments.compact.join(", ")
          end
          private_class_method :render_arguments

          def self.render_receiver(receiver)
            (receiver == SELF_VALUE) ? "self" : receiver.to_s
          end
          private_class_method :render_receiver

          def self.pop_values(stack, count)
            return [] if count <= 0

            stack.pop(count) || []
          end
          private_class_method :pop_values

          def self.render_new_hash(stack, count)
            values = pop_values(stack, count)
            pairs = values.each_slice(2).map do |key, value|
              "#{key} => #{value}"
            end

            "{#{pairs.join(", ")}}"
          end
          private_class_method :render_new_hash

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

          def self.example_name(value)
            [EXAMPLE_NAME_VALUE, value]
          end
          private_class_method :example_name

          def self.name_value?(value)
            value.is_a?(Array) && value[0] == EXAMPLE_NAME_VALUE
          end
          private_class_method :name_value?

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
