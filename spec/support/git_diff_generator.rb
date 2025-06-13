# frozen_string_literal: true

module GitDiffGenerator
  def generate_git_diff_output(changed_files_set)
    return "" if changed_files_set.empty?

    changed_files_set.map do |file_info|
      if file_info.include?(":")
        # Parse format like "file1.rb:2:5" (file:start_line:end_line)
        parts = file_info.split(":")
        filename = parts[0]
        start_line = parts[1].to_i
        end_line = parts[2].to_i

        generate_diff_for_file_with_lines(filename, start_line, end_line)
      else
        # Fallback for old format (just filename)
        generate_diff_for_file(file_info)
      end
    end.join("\n")
  end

  private

  def generate_diff_for_file_with_lines(filename, start_line, end_line)
    line_count = end_line - start_line + 1

    <<~DIFF
      diff --git a/#{filename} b/#{filename}
      index 1234567..abcdefg 100644
      --- a/#{filename}
      +++ b/#{filename}
      @@ -#{start_line},#{line_count} +#{start_line},#{line_count + 1} @@
      #{generate_context_lines(start_line, end_line)}
    DIFF
  end

  def generate_diff_for_file(filename)
    <<~DIFF
      diff --git a/#{filename} b/#{filename}
    DIFF
  end

  def generate_context_lines(start_line, end_line)
    lines = []

    # Add some context before the change
    if start_line > 1
      lines << " line #{start_line - 1}"
    end

    # Add the changed lines (simulate changes)
    (start_line..end_line).each do |line_num|
      lines << " existing line #{line_num}"
      lines << "+modified line #{line_num}"
    end

    # Add some context after the change
    lines << " line #{end_line + 1}"

    lines.join("\n")
  end
end
