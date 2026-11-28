# frozen_string_literal: true

module Datadog
  module CI
    module Utils
      # Formats the stack that a span records for an exception, as the tracer does, without
      # the frames that datadog-ci's own methods add on top of a call they observe, such as
      # File.read through the file access instrumentation.
      module ErrorStack
        # Frames of files loaded by require_relative carry their real path; the others carry
        # the path they were required by.
        LIBRARY_DIRECTORIES = [__dir__, File.dirname(__FILE__)].compact.map do |directory|
          File.join(File.expand_path("..", directory), "")
        end.uniq.freeze

        FRAME_LOCATION = /\A.+?:\d+(?=:in )/
        FRAME_LABEL = /:in .*\z/m

        # @param exception [Exception]
        # @return [String] the stack, causes included, in the format of
        #   Exception#full_message(highlight: false, order: :top)
        def self.full_message(exception)
          stack = +""
          append(exception, stack)

          causes = {exception => true}
          cause = exception
          while (cause = cause.cause) && !causes.key?(cause)
            append(cause, stack)
            causes[cause] = true
          end

          stack
        end

        # Removes the datadog-ci frames at the top of a backtrace. The frame that raised takes
        # the location of the first frame below them, as it has when no datadog-ci method sits
        # between the caller and the method that raised.
        #
        # @param backtrace [Array<String>]
        # @return [Array<String>]
        def self.without_library_frames(backtrace)
          first_outside = backtrace.index { |frame| !library_frame?(frame) }
          return backtrace if first_outside.nil? || first_outside.zero?

          rest = backtrace.drop(first_outside)
          relocated = relocate(backtrace[0], backtrace[first_outside])
          relocated ? [relocated] + rest : rest
        end

        def self.library_frame?(frame)
          LIBRARY_DIRECTORIES.any? { |directory| frame.start_with?(directory) }
        end

        def self.relocate(frame, caller_frame)
          location = caller_frame[FRAME_LOCATION]
          label = frame[FRAME_LABEL]
          location + label if location && label
        end

        def self.append(exception, stack)
          trace = exception.backtrace
          return unless trace

          trace = without_library_frames(trace)
          if trace[0]
            stack << trace[0] << ": " << exception.message.to_s << " (" << exception.class.to_s << ")"
          end
          trace.drop(1).each { |frame| stack << "\n\tfrom " << frame }
          stack << "\n"
        end

        private_class_method :library_frame?, :relocate, :append
      end
    end
  end
end
