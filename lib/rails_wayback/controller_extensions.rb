# frozen_string_literal: true

module RailsWayback
  # Auto-included in every `ActionController::Base` subclass through the
  # engine's initializer. Does nothing on ordinary requests. When a
  # request carries `?_wayback_ref=<sha>` and the gem is enabled, it
  # leases the materialised ref and prepends its directories to the view
  # paths so the current controller renders historical templates while
  # keeping its own instance variables intact.
  module ControllerExtensions
    extend ActiveSupport::Concern

    WAYBACK_PARAM = "_wayback_ref"
    WAYBACK_COOKIE = "rails_wayback_ref"
    RESPONSE_HEADER = "X-RailsWayback-Ref"

    included do
      around_action :__rails_wayback_with_views
      helper_method :rails_wayback_active_ref
    end

    def rails_wayback_active_ref
      @__rails_wayback_active_ref
    end

    private

    def __rails_wayback_with_views(&action)
      return action.call unless RailsWayback.enabled?

      ref = __rails_wayback_ref_from_request
      return action.call unless ref

      selection = authorize_wayback_ref(ref)
      return action.call unless selection

      request.env[RailsWayback::RefPolicy::ENV_KEY] = selection
      if selection.rejected?
        reject_wayback_ref(selection)
        return action.call
      end

      render_with_wayback_views(selection, &action)
    end

    def authorize_wayback_ref(ref)
      RailsWayback::RefPolicy.new.authorize(ref)
    rescue RailsWayback::RefNotFoundError, RailsWayback::Git::GitError => e
      handle_wayback_error(e)
      nil
    end

    def render_with_wayback_views(selection, &action)
      action_started = false
      RailsWayback::ViewSource.new.with_view_roots(selection.sha) do |dirs|
        prepend_wayback_views(selection, dirs)
        action_started = true
        action.call
      end
    rescue RailsWayback::RefNotFoundError, RailsWayback::Git::GitError => e
      raise if action_started

      handle_wayback_error(e)
      action.call
    end

    def handle_wayback_error(error)
      log_warning("#{error.class}: #{error.message}")
      write_wayback_header("error:#{error.class}")
    end

    def prepend_wayback_views(selection, dirs)
      if dirs.empty?
        log_warning("no view directories materialised for ref #{selection.sha}")
        write_wayback_header("empty:#{selection.sha}")
        return
      end

      # `prepend_view_path` is the supported cross-version API. It puts
      # the sandbox in front of every other resolver for this request's
      # lookup context.
      dirs.each { |dir| prepend_view_path(dir.to_s) }

      @__rails_wayback_active_ref = selection.sha
      write_wayback_header(selection.sha)

      log_info("prepended #{dirs.size} view path(s) from ref #{selection.sha}")
      log_info("resolver order: #{resolver_summary}")
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

    def reject_wayback_ref(selection)
      response.delete_cookie(WAYBACK_COOKIE, path: "/")
      response.delete_cookie("rails_wayback_branch", path: "/")
      log_warning(selection.message)
      write_wayback_header("rejected:#{selection.reason}")
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
