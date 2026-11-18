# frozen_string_literal: true

require "json"
require "set"
require "pathname"
require "tempfile"
require "uri"
require "zlib"
require_relative "local_git"
require_relative "local_map"

module Datadog
  module CI
    module TestImpactAnalysis
      module Coverage
        class LocalStore
          def initialize(path:, root:, repository:, framework:, variant: nil, git: LocalGit.new(root))
            @path = File.expand_path(path, root)
            @scope = {"repository" => repository_id(repository), "framework" => framework}
            raise ArgumentError, "missing test framework" if framework.nil? || framework.empty?
            @scope["variant"] = variant if variant
            @git = git
            @pid = Process.pid
            @mutex = Mutex.new
            @records = {}
            @collecting = false
            @map = nil
            @base_commit = nil
            if File.exist?(@path)
              document = JSON.parse(Zlib.gunzip(File.binread(@path)))
              map = LocalMap.new(document, scope: @scope)
              map.select(@git.changed_files(map.base_commit))
              @map = map
            else
              base_commit = @git.head
              @base_commit = base_commit
              raise "Collect local coverage from a clean Git checkout" unless @git.changed_files(base_commit).empty?
              @collecting = true
            end
          end

          def collecting?
            @collecting && Process.pid == @pid
          end

          def skippable?(test)
            skippable_identity?(test.test_suite_name, test.name, test.parameters)
          end

          def skippable_identity?(suite, name, parameters)
            return false if Process.pid != @pid
            identity = LocalMap.identity(suite, name, parameters)
            map = @map
            !identity.nil? && !map.nil? && map.skippable?(identity)
          rescue => error
            warn_failure(error)
            false
          end

          def record(test, files)
            return unless collecting? && test.passed?
            identity = LocalMap.identity(test.test_suite_name, test.name, test.parameters)
            return unless identity

            @mutex.synchronize do
              dependencies = (@records[identity] ||= Set.new)
              files.each { |path| dependencies.add(Pathname.new(path).cleanpath.to_s) }
            end
          rescue => error
            @collecting = false
            warn_failure(error)
          end

          def finish
            return unless collecting?
            @collecting = false
            base_commit = @base_commit
            return if base_commit.nil? || @records.empty?
            unless @git.head == base_commit && @git.changed_files(base_commit).empty?
              raise "Checkout changed during local coverage collection"
            end
            # @type var records: Array[LocalMap::record]
            records = @mutex.synchronize do
              @records.map do |identity, files|
                {"suite" => identity[0], "name" => identity[1], "parameters" => identity[2], "files" => files.to_a.sort}
              end
            end
            # @type var document: LocalMap::document
            document = {"version" => 1, "scope" => @scope, "base_commit" => base_commit, "tests" => records}
            LocalMap.new(document, scope: @scope)
            Tempfile.create([".local-coverage-", ".json.gz"], File.dirname(@path)) do |file|
              file.binmode
              file.write(Zlib.gzip(JSON.pretty_generate(document) + "\n"))
              file.flush
              file.fsync
              File.link(file.path, @path)
            end
          rescue => error
            warn_failure(error)
          end

          private

          def repository_id(repository)
            raise ArgumentError, "missing repository URL" if repository.nil? || repository.empty?
            value = repository.sub(/\A[^\/@]+@([^:]+):/, 'https://\1/')
            uri = URI.parse(value)
            raise ArgumentError, "repository URL must include a host" if uri.host.nil?
            "#{uri.host.downcase}#{uri.path}".sub(/\.git\/?\z/, "").sub(/\/\z/, "")
          end

          def warn_failure(error)
            Datadog.logger.warn("Local TIA coverage: #{error.class}: #{error.message}")
          rescue
            nil
          end
        end
      end
    end
  end
end
