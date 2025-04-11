# frozen_string_literal: true

RSpec.shared_context "Rails test app" do
  subject { RailsTest::Application }
  let(:controllers) { [] }
  let(:routes) { {} }
  let(:devnull) { File.open(File::NULL, "w") }

  after do
    # Unsubscribe log subscription to prevent flaky specs due to multiple subscription
    # after several test cases.
    ::Lograge::LogSubscribers::ActionController.detach_from :action_controller

    Rails.application = nil
    Rails.logger = nil
    Rails.app_class = nil
    Rails.cache = nil
  end

  let(:logger) do
    Logger.new(devnull).tap do |l|
      l.formatter = ::ActiveSupport::Logger::SimpleFormatter.new
    end
  end

  let(:rails_test_application) do
    stub_const("RailsTest::Application", rails_base_application)
  end

  let(:app) do
    # Initialize the application and stub Rails with the test app
    rails_test_application.test_initialize!

    rails_test_application.instance
  end

  let(:rails_base_application) do
    local_logger = logger

    klass = Class.new(Rails::Application)

    klass.send(:define_method, :initialize) do |*args|
      super(*args)
      redis_cache =
        if Gem.loaded_specs["redis-activesupport"]
          [:redis_store, {url: ENV["REDIS_URL"]}]
        else
          [:redis_cache_store, {url: ENV["REDIS_URL"]}]
        end
      file_cache = [:file_store, "/tmp/datadog-rb/cache/"]

      config.load_defaults "7.0"
      config.secret_key_base = "f624861242e4ccf20eacb6bb48a886da"
      config.active_record.cache_versioning = false if Gem.loaded_specs["redis-activesupport"]
      config.cache_store = ENV["REDIS_URL"] ? redis_cache : file_cache
      config.eager_load = false
      config.consider_all_requests_local = true
      config.hosts.clear # Allow requests for any hostname during tests
      config.active_support.remove_deprecated_time_with_zone_name = false
      config.active_support.to_time_preserves_timezone = :zone

      config.logger = local_logger
      # Not to use ANSI color codes when logging information
      config.colorize_logging = false

      if config.respond_to?(:lograge)
        # `keep_original_rails_log` is important to prevent monkey patching from `lograge`
        #  which leads to flaky spec in the same test process
        config.lograge.keep_original_rails_log = true
        config.lograge.logger = config.logger

        config.lograge.enabled = true
      end
    end

    before_test_init = before_test_initialize_block
    after_test_init = after_test_initialize_block

    klass.send(:define_method, :test_initialize!) do
      # instrument rails for test app
      Datadog.configure do |c|
        c.tracing.instrument :rails
      end

      before_test_init.call
      initialize!
      after_test_init.call
    end
    Class.new(klass)
  end

  let(:before_test_initialize_block) do
    proc do
      append_routes!
    end
  end

  let(:after_test_initialize_block) do
    proc do
      append_controllers!

      # Skip default Rails exception page rendering.
      # This avoid polluting the trace under test
      # with render and partial_render templates for the
      # error page.
      #
      # We could completely disable the {DebugExceptions} middleware,
      # but that affects Rails' internal error propagation logic.
      # render_for_browser_request(request, wrapper)
      allow_any_instance_of(::ActionDispatch::DebugExceptions).to receive(:render_exception) do |this, env, exception|
        wrapper = ::ActionDispatch::ExceptionWrapper.new(env, exception)

        this.send(:render, wrapper.status_code, "Test error response body", "text/plain")
      end
    end
  end

  around do |example|
    reset_rails_configuration!

    example.run
  ensure
    reset_rails_configuration!
  end

  def append_routes!
    # Make sure to load controllers first
    # otherwise routes won't draw properly.
    test_routes = routes

    rails_test_application.instance.routes.append do
      test_routes.each do |k, v|
        if k.is_a?(Array)
          send(k.first, k.last => v)
        else
          get k => v
        end
      end
    end
  end

  def append_controllers!
    controllers
  end

  # Rails leaves a bunch of global class configuration on Rails::Railtie::Configuration in class variables
  # We need to reset these so they don't carry over between example runs
  def reset_rails_configuration!
    # Reset autoloaded constants
    ActiveSupport::Dependencies.clear if Rails.application

    # TODO: Remove this side-effect on missing log entries
    Lograge.remove_existing_log_subscriptions if defined?(::Lograge)

    reset_class_variable(ActiveRecord::Railtie::Configuration, :@@options) if Module.const_defined?(:ActiveRecord)

    ActiveSupport::Dependencies.autoload_paths = []
    ActiveSupport::Dependencies.autoload_once_paths = []
    ActiveSupport::Dependencies._eager_load_paths = Set.new
    ActiveSupport::Dependencies._autoloaded_tracked_classes = Set.new

    Rails::Railtie::Configuration.class_variable_set(:@@eager_load_namespaces, nil)
    Rails::Railtie::Configuration.class_variable_set(:@@watchable_files, nil)
    Rails::Railtie::Configuration.class_variable_set(:@@watchable_dirs, nil)
    if Rails::Railtie::Configuration.class_variable_defined?(:@@app_middleware)
      Rails::Railtie::Configuration.class_variable_set(:@@app_middleware, Rails::Configuration::MiddlewareStackProxy.new)
    end
    Rails::Railtie::Configuration.class_variable_set(:@@app_generators, nil)
    Rails::Railtie::Configuration.class_variable_set(:@@to_prepare_blocks, nil)
  end
end
