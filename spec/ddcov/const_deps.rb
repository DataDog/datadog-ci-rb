# const_deps.rb
# gem install prism
require "prism"
require "set"

module ConstDeps
  PROJECT_ROOT = File.expand_path("./calculator", __dir__)

  module Storage
    # file_path => Set["Foo::Bar", "::Top::Level", ...]
    CONST_REFS_BY_FILE = Hash.new { |h, k| h[k] = Set.new }
    # file_path => Set[required_file_path]
    REQUIRES_BY_FILE = Hash.new { |h, k| h[k] = Set.new }

    # file_path => { "Foo::Bar" => { owner: Module, name: :Bar, def_loc: [file, line] } }
    RESOLVED_BY_FILE = Hash.new { |h, k| h[k] = {} }
  end

  module Filters
    def self.project_file?(path)
      return false unless path && path.end_with?(".rb")
      full = File.expand_path(path)
      return false unless full.start_with?(PROJECT_ROOT)
      # Skip vendored/gems; tweak for your repo
      return false if full.include?("/vendor/") || full.include?("/gems/")
      File.file?(full)
    end
  end

  # ---- Prism pass: collect constant uses & requires ---------------------------------
  module PrismScan
    module_function

    def scan_file(path)
      src = File.read(path)
      result = Prism.parse(src)
      return unless result.success?

      walk(result.value, src: src, file_path: path) do |evt|
        case evt[:type]
        when :const
          ConstDeps::Storage::CONST_REFS_BY_FILE[path] << evt[:full]
        when :require
          ConstDeps::Storage::REQUIRES_BY_FILE[path] << evt[:target]
        end
      end
    rescue => e
      warn "[const_deps] Prism scan failed for #{path}: #{e.class}: #{e.message}"
    end

    # Thread both src and file_path through the traversal so we never touch protected APIs.
    def walk(node, src:, file_path:, &blk)
      return unless node

      case node
      when Prism::ConstantReadNode
        # If you want a "file:line:col" string, compute it from location:
        # loc = node.location
        # line = loc.start_line; col = loc.start_column
        # loc_str = "#{file_path}:#{line}:#{col}"
        yield type: :const, full: node.name.to_s

      when Prism::ConstantPathNode
        parts = []
        cursor = node
        absolute = cursor.absolute?
        while cursor.is_a?(Prism::ConstantPathNode)
          parts.unshift(cursor.name.to_s)
          cursor = cursor.parent
        end
        parts.unshift(cursor.name.to_s) if cursor.is_a?(Prism::ConstantReadNode)
        parts.unshift("") if absolute # leading "" means ::Foo
        yield type: :const, full: parts.join("::")

      when Prism::CallNode
        # Handle: require("foo"), require_relative("bar/baz")
        if (meth = node.name) && (meth == :require || meth == :require_relative)
          arg = node.arguments&.arguments&.first
          if arg.is_a?(Prism::StringNode)
            lit = begin
              # Prefer unescaped if present; fall back to raw content
              arg.respond_to?(:unescaped) ? arg.unescaped : arg.content
            rescue
              nil
            end

            if lit && !lit.empty?
              target =
                if meth == :require_relative
                  base = File.dirname(file_path)
                  File.expand_path("#{lit}.rb", base)
                else
                  lit # leave bare; resolve against $LOAD_PATH later if you wish
                end
              yield type: :require, target: target
            end
          end
        end
      end

      # Recurse
      node.child_nodes.each { |child| walk(child, src: src, file_path: file_path, &blk) if child }
    end
  end

  # ---- Runtime resolution (lightweight, post-boot) ----------------------------------
  module Resolver
    module_function

    # Resolve "Foo::Bar" (or "::Foo::Bar") into [owner_module, :Bar, [file, line]] or nil
    def resolve_const_ref(ref)
      absolute = ref.start_with?("::")
      parts = ref.split("::").reject(&:empty?) # drop leading "" for absolute
      return nil if parts.empty?

      owner = absolute ? Object : Object # You can refine lexical owners if needed
      # Walk owners for nested path, stopping before the final name
      parts[0...-1].each do |seg|
        return nil unless safe_const_defined?(owner, seg)
        owner = safe_const_get(owner, seg)
        return nil unless owner.is_a?(Module)
      end

      name = parts.last.to_sym
      return nil unless safe_const_defined?(owner, name)

      begin
        loc = owner.const_source_location(name) # => [file, line] or nil
      rescue NameError
        loc = nil
      end
      [owner, name, loc]
    rescue => _
      nil
    end

    def safe_const_defined?(mod, name)
      mod.const_defined?(name, true)
    rescue => _
      false
    end

    def safe_const_get(mod, name)
      mod.const_get(name)
    rescue => _
      nil
    end

    def run!
      Storage::CONST_REFS_BY_FILE.each do |file, refs|
        refs.each do |ref|
          resolved = resolve_const_ref(ref)
          next unless resolved
          owner, name, loc = resolved
          Storage::RESOLVED_BY_FILE[file][ref] = {owner: owner, name: name, def_loc: loc}
        end
      end
    end
  end

  # ---- Public API -------------------------------------------------------------------
  module API
    module_function

    def dependency_edges
      # { "from_file.rb" => Set["to_file.rb", ...] }
      edges = Hash.new { |h, k| h[k] = Set.new }
      Storage::RESOLVED_BY_FILE.each do |from, m|
        m.each_value do |info|
          file, _line = info[:def_loc]
          edges[from] << File.expand_path(file) if file
        end
      end
      edges
    end

    def print_summary(io = $stdout)
      io.puts "[const_deps] ---- Constant uses (static) ----"
      Storage::CONST_REFS_BY_FILE.each do |file, refs|
        io.puts("#{short(file)}:")
        refs.to_a.sort.each { |r| io.puts("  - #{r}") }
      end

      io.puts "\n[const_deps] ---- Resolved definitions (runtime confirm) ----"
      Storage::RESOLVED_BY_FILE.each do |file, refs|
        io.puts("#{short(file)}:")
        refs.sort.each do |ref, info|
          fileline = info[:def_loc] ? info[:def_loc].join(":") : "unknown"
          io.puts("  - #{ref} -> #{fileline}")
        end
      end

      io.puts "\n[const_deps] ---- Dependency edges (file -> file) ----"
      dependency_edges.each do |from, tos|
        io.puts("#{short(from)}:")
        tos.to_a.sort.each { |t| io.puts("  -> #{short(t)}") }
      end
    end

    def short(path)
      path.sub(/^#{Regexp.escape(PROJECT_ROOT)}\//o, "")
    end
  end
  # ---- TracePoint wiring -------------------------------------------------------------
  SCRIPT_COMPILED = TracePoint.new(:script_compiled) do |tp|
    path = tp.path
    next unless Filters.project_file?(path)
    PrismScan.scan_file(path)
  end

  def self.enable!
    SCRIPT_COMPILED.enable
  end

  def self.disable!
    SCRIPT_COMPILED.disable
  end
end

# Enable immediately on require
ConstDeps.enable!

# After your app boots (representative load), do a single confirmation sweep.
# You can also flip this to a custom trigger in your app when "boot is done".
at_exit do
  ConstDeps::Resolver.run!
  ConstDeps::API.print_summary($stderr)
end
