# frozen_string_literal: true

require "rails/engine"
require "rails_wayback/controller_extensions"
require "rails_wayback/bar_renderer"
require "rails_wayback/bar_middleware"

module RailsWayback
  class Engine < ::Rails::Engine
    isolate_namespace RailsWayback

    # Activation is scoped to a Rails server session. The marker still lets
    # the standalone CLI toggle a running server, but a later server boot
    # always starts with Wayback disabled.
    server do
      RailsWayback.toggle.reset!
    end

    initializer "rails_wayback.controller_extensions" do
      ActiveSupport.on_load(:action_controller_base) do
        include RailsWayback::ControllerExtensions
      end
    end

    initializer "rails_wayback.middleware" do |app|
      app.middleware.use RailsWayback::BarMiddleware
    end

    initializer "rails_wayback.render_instrumentation" do
      ActiveSupport::Notifications.subscribe("render_template.action_view") do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        identifier = event.payload[:identifier].to_s
        next if identifier.empty?

        origin = if identifier.include?("/tmp/rails_wayback/refs/")
                   "SANDBOX"
                 elsif identifier.start_with?("/")
                   "CURRENT"
                 else
                   "OTHER"
                 end
        Rails.logger.info("[rails-wayback] render #{origin}: #{identifier}") if Rails.respond_to?(:logger)

        # Per-request tracker so the middleware can report, in the bar,
        # which templates the current page actually pulled from the
        # sandbox. Middleware clears this at the start of every request.
        tracker = Thread.current[RailsWayback::RENDER_TRACKER_KEY] ||= []
        tracker << identifier
      end
    end

    rake_tasks do
      load File.expand_path("../tasks/rails_wayback.rake", __dir__)
    end
  end
end
