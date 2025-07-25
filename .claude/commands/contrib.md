# Contrib Integration Generator

Given the name of an external gem, creates a new subfolder in lib/datadog/ci/contrib folder with the name of the external gem. In this subfolder creates files `patcher.rb`, `integration.rb`, `ext.rb`, `configuration/settings.rb`. Creates RBS type definitions for new files. Adds corresponding require in `lib/datadog/ci.rb`.

## Usage

```
/contrib external_gem
```

## Implementation

This command will:

1. Create a new directory structure in `lib/datadog/ci/contrib/{external_gem}`
2. Generate the four required files with appropriate boilerplate code
3. Create corresponding RBS type definitions in `sig/datadog/ci/contrib/{external_gem}`
4. Add the require statement to `lib/datadog/ci.rb`

## Arguments

- `external_gem` (string): The name of the external gem to create integration for

## Files Created

- `lib/datadog/ci/contrib/{external_gem}/patcher.rb` - Patcher module for the integration
- `lib/datadog/ci/contrib/{external_gem}/integration.rb` - Integration class definition
- `lib/datadog/ci/contrib/{external_gem}/ext.rb` - Constants and environment variables
- `lib/datadog/ci/contrib/{external_gem}/configuration/settings.rb` - Configuration settings class
- `sig/datadog/ci/contrib/{external_gem}/patcher.rbs` - Type definitions for patcher
- `sig/datadog/ci/contrib/{external_gem}/integration.rbs` - Type definitions for integration
- `sig/datadog/ci/contrib/{external_gem}/ext.rbs` - Type definitions for constants
- `sig/datadog/ci/contrib/{external_gem}/configuration/settings.rbs` - Type definitions for settings

---

## Task Implementation

Create a new contrib integration for the gem: {{external_gem}}

### Step 1: Create directory structure
```bash
mkdir -p "lib/datadog/ci/contrib/{{external_gem}}/configuration"
mkdir -p "sig/datadog/ci/contrib/{{external_gem}}/configuration"
```

### Step 2: Create patcher.rb
```ruby
# frozen_string_literal: true

require_relative "../patcher"

module Datadog
  module CI
    module Contrib
      module {{external_gem|title}}
        # Patcher enables patching of {{external_gem}} module
        module Patcher
          include Datadog::CI::Contrib::Patcher

          module_function

          def patch
            # TODO: Implement patching logic for {{external_gem}}
          end
        end
      end
    end
  end
end
```

### Step 3: Create integration.rb
```ruby
# frozen_string_literal: true

require_relative "../integration"
require_relative "configuration/settings"
require_relative "patcher"

module Datadog
  module CI
    module Contrib
      module {{external_gem|title}}
        # Description of {{external_gem|title}} integration
        class Integration < Datadog::CI::Contrib::Integration
          MINIMUM_VERSION = Gem::Version.new("0.0.0")

          def version
            Gem.loaded_specs["{{external_gem}}"]&.version
          end

          def loaded?
            !defined?(::{{external_gem|title}}).nil?
          end

          def compatible?
            super && version >= MINIMUM_VERSION
          end

          def new_configuration
            Configuration::Settings.new
          end

          def patcher
            Patcher
          end
        end
      end
    end
  end
end
```

### Step 4: Create ext.rb
```ruby
# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module {{external_gem|title}}
        # Datadog {{external_gem|title}} integration constants
        module Ext
          ENV_ENABLED = "DD_CI_{{external_gem|upper}}_ENABLED"
        end
      end
    end
  end
end
```

### Step 5: Create configuration/settings.rb
```ruby
# frozen_string_literal: true

require_relative "../ext"
require_relative "../../settings"
require_relative "../../../utils/configuration"

module Datadog
  module CI
    module Contrib
      module {{external_gem|title}}
        module Configuration
          # Custom settings for the {{external_gem|title}} integration
          # @public_api
          class Settings < Datadog::CI::Contrib::Settings
            option :enabled do |o|
              o.type :bool
              o.env Ext::ENV_ENABLED
              o.default true
            end
          end
        end
      end
    end
  end
end
```

### Step 6: Create RBS type definitions

Create `sig/datadog/ci/contrib/{{external_gem}}/patcher.rbs`:
```ruby
module Datadog
  module CI
    module Contrib
      module {{external_gem|title}}
        module Patcher
          include Datadog::CI::Contrib::Patcher

          def patch: () -> void
        end
      end
    end
  end
end
```

Create `sig/datadog/ci/contrib/{{external_gem}}/integration.rbs`:
```ruby
module Datadog
  module CI
    module Contrib
      module {{external_gem|title}}
        class Integration < Datadog::CI::Contrib::Integration
          MINIMUM_VERSION: Gem::Version

          def version: () -> untyped

          def loaded?: () -> bool

          def compatible?: () -> bool

          def new_configuration: () -> Configuration::Settings

          def patcher: () -> singleton(Patcher)
        end
      end
    end
  end
end
```

Create `sig/datadog/ci/contrib/{{external_gem}}/ext.rbs`:
```ruby
module Datadog
  module CI
    module Contrib
      module {{external_gem|title}}
        module Ext
          ENV_ENABLED: String
        end
      end
    end
  end
end
```

Create `sig/datadog/ci/contrib/{{external_gem}}/configuration/settings.rbs`:
```ruby
module Datadog
  module CI
    module Contrib
      module {{external_gem|title}}
        module Configuration
          class Settings < Datadog::CI::Contrib::Settings
            def initialize: () ?{ (Settings) -> void } -> void

            def enabled: () -> bool
            def enabled=: (bool) -> bool
          end
        end
      end
    end
  end
end
```

### Step 7: Add require to lib/datadog/ci.rb

Add the following line to `lib/datadog/ci.rb` in the appropriate section with other contrib requires:
```ruby
require_relative "ci/contrib/{{external_gem}}/integration"
```

### Implementation Logic

1. Parse the external_gem argument
2. Create the necessary directory structure
3. Generate each file with proper module names (title case for Ruby modules)
4. Create corresponding RBS type definitions
5. Add the require statement to lib/datadog/ci.rb
6. Use proper string transformations:
   - `{{external_gem|title}}` - Title case for module names
   - `{{external_gem|upper}}` - Upper case for environment variable names
   - `{{external_gem}}` - Original name for gem references

This follows the exact pattern established by the activesupport integration.
