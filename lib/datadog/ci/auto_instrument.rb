require "datadog/ci"
require "datadog/ci/contrib/contrib"
require "datadog/ci/contrib/kernel"

::Kernel.prepend(Datadog::CI::Contrib::Kernel)
::Kernel.singleton_class.prepend(Datadog::CI::Contrib::Kernel)

Datadog::CI::Contrib.auto_instrument!
