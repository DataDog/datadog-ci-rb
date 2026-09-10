# frozen_string_literal: true

root "../.."
source "lib/**/*.rb"

# A component's Component and NullComponent classes are its front door.
# Code outside the component can use those classes and call their public methods,
# but references to any other constant under the component directory are private.
Dir.glob(File.join(__dir__, "../../lib/datadog/ci/*/component.rb")).sort.each do |component_file|
  name = File.basename(File.dirname(component_file))
  path = "lib/datadog/ci/#{name}"

  component(name, in: "#{path}/**/*.rb").public_api(
    "#{path}/component.rb",
    "#{path}/null_component.rb",
    because: "components collaborate through their public component interface"
  )
end
