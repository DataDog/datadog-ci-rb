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
            expectation_call_index = final_expectation_call_index(body)
            return nil unless expectation_call_index

            call_data = body[expectation_call_index][1]
            return nil unless call_data[:orig_argc].to_i == 1

            matcher_expression = render_expression_ending_at(body, expectation_call_index - 1)
            return nil unless matcher_expression

            method_name = call_data[:mid]
            return nil if EXPECTATION_METHODS.key?(method_name) && !expectation_receiver_at?(body, matcher_expression[1])

            name_prefix = EXPECTATION_METHODS[method_name] || SHOULD_METHODS[method_name]
            "#{name_prefix} #{matcher_expression[0]}"
          end
          private_class_method :render_iseq

          def self.final_expectation_call_index(body)
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
          private_class_method :final_expectation_call_index

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

          # Render the expression that produced the stack value at `index`.
          #
          # YARV bytecode is stack-based: matcher arguments are pushed before the
          # final `to`/`not_to` call consumes them. We walk backwards from the
          # producer instruction, render only shapes we understand, and return the
          # previous instruction index so callers can continue rendering earlier
          # stack values without evaluating user code.
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

          # `newarray` consumes N already-pushed stack values. Render those values
          # backwards, then restore source order so matcher names read like Ruby.
          def self.render_new_array_expression(body, index)
            expression = render_expression_list_ending_at(body, index - 1, body[index][1].to_i)
            return nil unless expression

            [render_array_literal(expression[0]), expression[1]]
          end
          private_class_method :render_new_array_expression

          # `newhash` consumes alternating key/value stack entries. We render the
          # pairs instead of inspecting a runtime Hash, keeping generated names
          # deterministic even when the original values are local variables.
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

          # Ruby 4's optimized constructor bytecode places the receiver before
          # `putnil`, `swap`, and `opt_new`. Find that receiver so the outer `pop`
          # handler can render `Object.new` as the stable class name `Object`.
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

          # Method calls consume arguments first and the receiver last. Render that
          # stack shape backwards, then format the send as matcher-style text when
          # it belongs to RSpec's expectation DSL.
          def self.render_send_expression(body, index, instruction)
            call_data = instruction[1]
            return nil unless call_data.is_a?(Hash)

            arguments_expression = render_expression_list_ending_at(body, index - 1, call_data[:orig_argc].to_i)
            return nil unless arguments_expression

            arguments = arguments_expression[0]
            receiver_end_index = arguments_expression[1]

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

          # Render `count` adjacent stack expressions ending at `index`.
          # Arguments appear on the stack left-to-right, but because we scan from
          # the end, each rendered value is written back into its original slot.
          def self.render_expression_list_ending_at(body, index, count)
            return [EMPTY_ARGUMENTS, index] if count <= 0

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

          # Instruction sequence bodies also contain labels and events. Only array
          # entries are executable instructions for the subset we render here.
          def self.previous_instruction_index(body, index)
            while index >= 0
              return index if body[index].is_a?(Array)

              index -= 1
            end

            nil
          end
          private_class_method :previous_instruction_index

          # Handle compact Ruby opcodes that are common in tiny matcher arguments.
          # Locals are intentionally rendered as `local`; reading their runtime
          # values would make names unstable and could execute user code.
          def self.render_special_expression(index, instruction)
            opcode = instruction[0].to_s

            if opcode.start_with?("putobject_INT2FIX_")
              [opcode.delete_prefix("putobject_INT2FIX_").delete_suffix("_"), index - 1]
            elsif opcode.start_with?("getlocal")
              ["local", index - 1]
            end
          end
          private_class_method :render_special_expression

          # Convert a rendered send into the text users expect from an RSpec
          # generated description. For constructor calls on constants, keep only
          # the class name so `Object.new` does not introduce object identity.
          def self.render_send(receiver, method_name, arguments, block_iseq)
            if receiver == SELF_VALUE && arguments.empty? && !block_iseq
              return render_method_name(receiver, method_name, arguments, block_iseq)
            end

            return receiver if method_name == :new && arguments.empty? && constant_name?(receiver)

            render_method_call(receiver, method_name, arguments, block_iseq)
          end
          private_class_method :render_send

          # Format non-trivial sends. Matcher calls and matcher chains use RSpec's
          # human-readable style (`include "x"`, `change by 1`); ordinary nested
          # sends keep Ruby-ish receiver syntax (`local.to_s`) for clarity.
          def self.render_method_call(receiver, method_name, arguments, block_iseq)
            matcher_chain = MATCHER_CHAIN_METHODS.key?(method_name)
            method_text = render_method_name(receiver, method_name, arguments, block_iseq)
            argument_text = arguments.join(", ")
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

          # RSpec generated descriptions turn matcher-like method names into prose
          # only when the send is part of matcher DSL text. Keep ordinary nested
          # Ruby calls (`local.to_s`) untouched.
          def self.render_method_name(receiver, method_name, arguments, block_iseq)
            method_text = method_name.to_s
            return method_text unless humanize_method_name?(receiver, method_name, method_text, arguments, block_iseq)

            method_text.tr("_", " ")
          end
          private_class_method :render_method_name

          def self.humanize_method_name?(receiver, method_name, method_text, arguments, block_iseq)
            return false unless receiver == SELF_VALUE || MATCHER_CHAIN_METHODS.key?(method_name) || block_iseq

            pretty_matcher_method?(method_name, method_text) || !arguments.empty? || block_iseq
          end
          private_class_method :humanize_method_name?

          # RSpec turns many matcher method names into words in generated example
          # descriptions. Mirror that only for known matcher methods/prefixes.
          def self.pretty_matcher_method?(method_name, method_text)
            PRETTY_MATCHER_METHODS.key?(method_name) ||
              PRETTY_MATCHER_PREFIXES.any? { |prefix| method_text.start_with?(prefix) }
          end
          private_class_method :pretty_matcher_method?

          # Literal operands are embedded in bytecode and safe to read. For any
          # object-like value, use the class name instead of `inspect` so memory
          # addresses cannot leak into test identities.
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

          # Keep array literals readable while recursively applying the same stable
          # rendering rules to their elements.
          def self.render_array_literal(value)
            return "[]" unless value.is_a?(Array)

            "[#{value.map { |element| render_literal(element) }.join(", ")}]"
          end
          private_class_method :render_array_literal

          # Sort hash keys so equivalent literal hashes render consistently across
          # Ruby versions and construction paths.
          def self.render_hash_literal(value)
            return "{}" unless value.is_a?(Hash)

            pairs = value.keys.sort_by(&:to_s).map do |key|
              "#{render_literal(key)} => #{render_literal(value[key])}"
            end

            "{#{pairs.join(", ")}}"
          end
          private_class_method :render_hash_literal

          # `opt_getconstant_path` stores constants as path parts. Join them into a
          # Ruby-looking constant name without resolving the constant at runtime.
          def self.render_constant_path(value)
            return "constant" unless value.is_a?(Array)

            value.compact.join("::")
          end
          private_class_method :render_constant_path

          # Used when collapsing zero-argument constructor calls; only collapse
          # real constant paths, not arbitrary receiver text.
          def self.constant_name?(value)
            value.is_a?(String) && value.match?(/\A[A-Z]\w*(?:::[A-Z]\w*)*\z/)
          end
          private_class_method :constant_name?

          # Block matchers carry the block body as an embedded instruction
          # sequence. Its presence changes matcher wording, but rendering the
          # block body would risk pulling subject code into the name.
          def self.iseq_array?(value)
            value.is_a?(Array) && value[0] == ISEQ_SIMPLE_DATA_FORMAT
          end
          private_class_method :iseq_array?

          # Bound rendered values and names so unusually large literals do not
          # create oversized span names.
          def self.trim(value, max_length)
            return value if value.length <= max_length

            "#{value[0, max_length - 3]}..."
          end
          private_class_method :trim

          def self.warn_anonymous_example_name_error(error)
            Datadog.logger.warn { "Unable to compute RSpec anonymous example name: #{error.class}: #{error.message}" }

            nil
          end
          private_class_method :warn_anonymous_example_name_error
        end
      end
    end
  end
end
