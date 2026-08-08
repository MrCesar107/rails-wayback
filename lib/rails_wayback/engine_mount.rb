# frozen_string_literal: true

module RailsWayback
  module EngineMount
    module_function

    def path
      RailsWayback::Engine.routes.default_url_options[:script_name] ||
        RailsWayback::Engine.routes.find_script_name({}) ||
        "/rails-wayback"
    rescue StandardError
      "/rails-wayback"
    end
  end
end
