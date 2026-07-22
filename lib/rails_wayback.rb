# frozen_string_literal: true

require "rails_wayback/version"
require "rails_wayback/configuration"
require "rails_wayback/toggle"
require "rails_wayback/git"
require "rails_wayback/view_source"

module RailsWayback
  class Error < StandardError; end
  class DisabledError < Error; end
  class RefNotFoundError < Error; end
  class RenderError < Error; end

  # Thread-local key where the render subscriber accumulates the
  # `identifier` of every template resolved during a single request.
  # The middleware resets this at the start of each request and reads
  # it back to report per-page diff coverage in the bar.
  RENDER_TRACKER_KEY = :rails_wayback_rendered_templates

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

    def enabled?
      toggle.enabled?
    end

    def enable!
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
