# frozen_string_literal: true

require_relative "component_api_parity_rule"

root "../.."
source "lib/**/*.rb"

composition_root = "lib/datadog/ci/configuration/components.rb"
component_pairs = []

# A component's Component and NullComponent classes are its front door.
# Code outside the component can use those classes and call their public methods,
# but references to any other constant under the component directory are private.
Dir.glob(File.join(__dir__, "../../lib/datadog/ci/*/component.rb")).sort.each do |component_file|
  name = File.basename(File.dirname(component_file))
  path = "lib/datadog/ci/#{name}"
  namespace = name.split("_").map(&:capitalize).join
  component_name = "Datadog::CI::#{namespace}::Component"
  null_component_name = "Datadog::CI::#{namespace}::NullComponent"

  component(name, in: "#{path}/**/*.rb").public_api(
    "#{path}/component.rb",
    "#{path}/null_component.rb",
    because: "components collaborate through their public component interface"
  )

  # A component's public factory may invoke its own constructor. All other
  # construction belongs to the configuration composition root.
  construction_callers = component(
    "#{name}_construction_callers",
    in: "lib/**/*.rb",
    except: [composition_root, "#{path}/component.rb"]
  )
  construction_callers.cannot_call(
    :new,
    receiver: component_name,
    because: "components are assembled in the configuration composition root"
  )

  null_component_file = File.join(__dir__, "../../#{path}/null_component.rb")
  next unless File.exist?(null_component_file)

  construction_callers.cannot_call(
    :new,
    receiver: null_component_name,
    because: "components are assembled in the configuration composition root"
  )
  component_pairs << [component_name, null_component_name]
end

rule DatadogCiArchitecture::ComponentApiParityRule.new(component_pairs),
  because: "enabled and disabled components must be substitutable"

# Contrib integrations are isolated from one another. Their integration class is
# the public entry point; the RSpec constants below are shared intentionally by
# integrations implemented on top of RSpec.
each_directory "lib/datadog/ci/contrib/*" do |name, path|
  public_api = ["#{path}/integration.rb"]
  public_api.concat(["#{path}/ext.rb", "#{path}/runner.rb"]) if name == "rspec"

  component("contrib_#{name}", in: "#{path}/**/*.rb").public_api(
    *public_api,
    because: "contrib integrations expose only explicit integration contracts"
  )
end
