# frozen_string_literal: true

module DatadogCiArchitecture
  # Ensures that enabled and disabled implementations remain substitutable.
  class ComponentApiParityRule
    IGNORED_METHODS = [:initialize].freeze

    def initialize(component_pairs)
      @component_pairs = component_pairs
    end

    def id
      "components.api_parity"
    end

    def evaluate(graph)
      @component_pairs.flat_map do |component_name, null_component_name|
        component_methods = public_instance_method_definitions(graph, component_name, [component_name])
        null_component_methods = public_instance_method_definitions(
          graph,
          null_component_name,
          [component_name, null_component_name]
        )

        missing_from_null = component_methods.keys - null_component_methods.keys
        missing_from_component = null_component_methods.keys - component_methods.keys

        missing_diagnostics(graph, null_component_name, component_name, missing_from_null) +
          missing_diagnostics(graph, component_name, null_component_name, missing_from_component) +
          incompatible_signature_diagnostics(component_name, null_component_name, component_methods, null_component_methods)
      end
    end

    private

    def public_instance_method_definitions(graph, constant_name, owners)
      definitions, = graph.effective_method_definitions(constant_name, :instance)
      definitions
        .select { |definition| definition.visibility == :public && owners.include?(definition.owner) }
        .reject { |definition| IGNORED_METHODS.include?(definition.name) }
        .group_by(&:name)
    end

    def missing_diagnostics(graph, target_name, source_name, methods)
      target = graph.constants_named(target_name).find(&:class?)
      return [] unless target

      methods.sort.map do |method_name|
        ArchSpec::Diagnostic.new(
          rule: id,
          message: "#{target_name} must expose ##{method_name} to match #{source_name}",
          location: target.location,
          evidence: "#{source_name} exposes ##{method_name}, but #{target_name} does not"
        )
      end
    end

    def incompatible_signature_diagnostics(component_name, null_component_name, component_methods, null_component_methods)
      (component_methods.keys & null_component_methods.keys).sort.filter_map do |method_name|
        component_signatures = component_methods.fetch(method_name).flat_map(&:signatures)
        null_component_definitions = null_component_methods.fetch(method_name)
        null_component_signatures = null_component_definitions.flat_map(&:signatures)
        next if component_signatures.empty? || null_component_signatures.empty?
        next if component_signatures.all? do |component_signature|
          null_component_signatures.any? do |null_component_signature|
            accepts_all_calls?(null_component_signature, component_signature)
          end
        end

        ArchSpec::Diagnostic.new(
          rule: id,
          message: "#{null_component_name}##{method_name} must accept every call supported by #{component_name}",
          location: null_component_definitions.first.location,
          evidence: "#{component_name} accepts #{describe(component_signatures)}; " \
            "#{null_component_name} accepts #{describe(null_component_signatures)}"
        )
      end
    end

    def accepts_all_calls?(target, source)
      return true if target.forward
      return false if source.forward
      return false if target.required > source.required
      return false if maximum_positional(target) < maximum_positional(source)
      return false unless target.keywords.all? { |keyword| source.keywords.include?(keyword) }
      return false if source.keyword_rest && !target.keyword_rest
      return true if target.keyword_rest

      source_keywords = source.keywords | source.optional_keywords
      target_keywords = target.keywords | target.optional_keywords
      source_keywords.all? { |keyword| target_keywords.include?(keyword) }
    end

    def maximum_positional(signature)
      signature.rest ? Float::INFINITY : signature.required + signature.optional
    end

    def describe(signatures)
      signatures.map(&:describe).uniq.join(" or ")
    end
  end
end
