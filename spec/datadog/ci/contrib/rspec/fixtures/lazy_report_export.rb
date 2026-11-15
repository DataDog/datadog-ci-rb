# frozen_string_literal: true

module FileDependencyFixtures
  class LazyReportExport
    def initialize(path)
      @path = path
    end

    def to_path
      File.write(@path, "item,total\nbook,12\n") unless File.exist?(@path)
      @path
    end
  end
end
