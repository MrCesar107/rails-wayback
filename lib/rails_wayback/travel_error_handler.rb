# frozen_string_literal: true

require "cgi"
require "rails_wayback/engine_mount"
require "rails_wayback/travel_error_page"

module RailsWayback
  # Converts only errors originating from a materialized historical template
  # into a recoverable 500 response. Exceptions from the host controller,
  # models, or current templates continue through Rails unchanged.
  class TravelErrorHandler
    ERROR_HEADER = "X-RailsWayback-Error"
    ERROR_VALUE = "historical_template_error"
    REF_HEADER = "X-RailsWayback-Ref"

    def self.call(controller:, root:, selection:, &)
      new(controller: controller, root: root, selection: selection).call(&)
    end

    def initialize(controller:, root:, selection:)
      @controller = controller
      @root = File.expand_path(root.to_s)
      @selection = selection
    end

    def call
      yield
    rescue StandardError => e
      raise unless historical_template_error?(e)

      render(e)
    end

    private

    attr_reader :controller, :root, :selection

    def historical_template_error?(error)
      return false unless defined?(ActionView::Template::Error)

      candidate = error
      seen = {}.compare_by_identity
      while candidate && !seen[candidate]
        seen[candidate] = true
        return true if historical_template_path?(candidate)

        candidate = candidate.cause
      end
      false
    end

    def historical_template_path?(error)
      return false unless error.is_a?(ActionView::Template::Error)

      paths = [error.file_name]
      paths << error.template.identifier if error.respond_to?(:template) && error.template
      paths.compact.any? do |path|
        expanded = File.expand_path(path.to_s)
        expanded == root || expanded.start_with?("#{root}#{File::SEPARATOR}")
      end
    rescue StandardError
      false
    end

    def render(error)
      log(error)
      response = controller.response
      response.set_header(REF_HEADER, selection.sha)
      response.set_header(ERROR_HEADER, ERROR_VALUE)
      response.set_header("Cache-Control", "no-store")
      response.set_header("Content-Type", "text/html; charset=utf-8")
      response.status = 500
      controller.response_body = TravelErrorPage.new(
        branch: active_branch,
        error: error,
        ref: selection.sha,
        reset_url: reset_url
      ).render
    end

    def active_branch
      from_params = controller.params["_wayback_branch"].to_s
      return from_params unless from_params.empty?

      controller.request.cookie_jar["rails_wayback_branch"].to_s
    end

    def reset_url
      query = controller.request.query_parameters.except("_wayback_ref", "_wayback_branch").to_query
      return_to = controller.request.path
      return_to = "#{return_to}?#{query}" unless query.empty?
      "#{RailsWayback::EngineMount.path}/reset?return_to=#{CGI.escape(return_to)}"
    end

    def log(error)
      return unless defined?(Rails) && Rails.respond_to?(:logger)

      Rails.logger&.warn(
        "[rails-wayback] historical preview failed for #{selection.sha}: " \
        "#{error.full_message(highlight: false)}"
      )
    end
  end
end
