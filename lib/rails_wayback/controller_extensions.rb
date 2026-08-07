# frozen_string_literal: true

module RailsWayback
  # Auto-included in every `ActionController::Base` subclass through the
  # engine's initializer. Does nothing on ordinary requests. When a
  # request carries `?_wayback_ref=<sha>` and the gem is enabled, it
  # materialises the ref and prepends the sandbox to the view paths so
  # the current controller renders historical templates while keeping
  # its own instance variables intact.
  module ControllerExtensions
    extend ActiveSupport::Concern

    WAYBACK_PARAM = "_wayback_ref"
    WAYBACK_COOKIE = "rails_wayback_ref"
    RESPONSE_HEADER = "X-RailsWayback-Ref"

    included do
      before_action :__rails_wayback_prepend_views
      helper_method :rails_wayback_active_ref
    end

    def rails_wayback_active_ref
      @__rails_wayback_active_ref
    end

    private

    def __rails_wayback_prepend_views
      return unless RailsWayback.enabled?

      ref = __rails_wayback_ref_from_request
      return unless ref

      dirs = RailsWayback::ViewSource.new.view_root_for(ref)

      if dirs.empty?
        log_warning("no view directories materialised for ref #{ref}")
        write_wayback_header("empty:#{ref}")
        return
      end

      # `prepend_view_path` is the supported cross-version API. It puts
      # the sandbox in front of every other resolver for this request's
      # lookup context.
      dirs.each { |dir| prepend_view_path(dir.to_s) }

      @__rails_wayback_active_ref = ref
      write_wayback_header(ref)

      log_info("prepended #{dirs.size} view path(s) from ref #{ref}")
      log_info("resolver order: #{resolver_summary}")
    rescue RailsWayback::RefNotFoundError, RailsWayback::Git::GitError => e
      log_warning("#{e.class}: #{e.message}")
      write_wayback_header("error:#{e.class}")
    end

    # Params take precedence for one-off overrides (e.g. a shared URL);
    # cookies keep the travel session alive across normal internal
    # navigations so clicking a link on a traveled page keeps rendering
    # from the historical ref.
    def __rails_wayback_ref_from_request
      from_params = params[WAYBACK_PARAM].to_s
      return from_params unless from_params.empty?

      cookies[WAYBACK_COOKIE].to_s.then { |v| v.empty? ? nil : v }
    end

    def resolver_summary
      lookup_context.view_paths.to_a.map { |r| resolver_path(r) }.join(" | ")
    rescue StandardError
      "(unavailable)"
    end

    def resolver_path(resolver)
      return resolver.to_path if resolver.respond_to?(:to_path)
      return resolver.path    if resolver.respond_to?(:path)

      resolver.class.name
    end

    def write_wayback_header(value)
      response&.set_header(RESPONSE_HEADER, value)
    rescue StandardError
      nil
    end

    def log_info(msg)
      Rails.logger.info("[rails-wayback] #{msg}") if defined?(Rails) && Rails.respond_to?(:logger)
    end

    def log_warning(msg)
      Rails.logger.warn("[rails-wayback] #{msg}") if defined?(Rails) && Rails.respond_to?(:logger)
    end
  end
end
