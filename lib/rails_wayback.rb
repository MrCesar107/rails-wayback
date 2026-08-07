# frozen_string_literal: true

require "rails_wayback/version"
require "rails_wayback/configuration"
require "rails_wayback/render_provenance"
require "rails_wayback/toggle"
require "rails_wayback/git"
require "rails_wayback/view_source"

module RailsWayback
  class Error < StandardError; end
  class DisabledError < Error; end
  class RefNotFoundError < Error; end
  class MaterializationError < Error; end
  class RenderError < Error; end

  # Thread-local key where the render subscriber accumulates the
  # `identifier` of every template resolved during a single request.
  # The middleware resets this at the start of each request and reads
  # it back to report per-page diff coverage in the bar.
  RENDER_TRACKER_KEY = :rails_wayback_rendered_templates
  RENDER_EVENTS = %w[
    render_template.action_view
    render_partial.action_view
    render_layout.action_view
    render_collection.action_view
  ].freeze

  class << self
    def configure
      yield configuration if block_given?
      configuration
    end

    def configuration
      @configuration ||= Configuration.new
    end

    def reset_configuration!
      @configuration = Configuration.new
      @toggle = nil
    end

    def toggle
      @toggle ||= Toggle.new(configuration)
    end

    def current_environment
      if defined?(Rails) && Rails.respond_to?(:env) && Rails.env
        Rails.env.to_s
      else
        ENV["RAILS_ENV"] || ENV.fetch("RACK_ENV", nil)
      end
    end

    def environment_allowed?
      environment = current_environment.to_s
      return true if environment.empty?

      configuration.allowed_environments.map(&:to_s).include?(environment)
    end

    def enabled?
      environment_allowed? && toggle.enabled?
    end

    def enable!
      unless environment_allowed?
        allowed = configuration.allowed_environments.join(", ")
        raise DisabledError,
              "environment #{current_environment.inspect} is not allowed " \
              "(allowed: #{allowed})"
      end

      toggle.enable!
    end

    def disable!
      toggle.disable!
    end

    def root
      return Rails.root if defined?(Rails) && Rails.respond_to?(:root) && Rails.root

      Pathname.new(Dir.pwd)
    end
  end
end

require "rails_wayback/engine" if defined?(Rails::Engine)
