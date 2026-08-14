# frozen_string_literal: true

module RailsWayback
  class ApplicationController < ::ActionController::Base
    protect_from_forgery with: :exception
    layout false

    before_action :ensure_enabled!

    private

    def ensure_enabled!
      return if RailsWayback.enabled?

      render json: { error: "rails-wayback is disabled" }, status: :service_unavailable
    end

    def git
      @git ||= RailsWayback::Git.new
    end

    def safe_git_call(context, &)
      failure_boundary.capture(
        context,
        fallback: nil,
        rescue_errors: [RailsWayback::Git::GitError],
        &
      )
    end

    def failure_boundary
      @failure_boundary ||= RailsWayback::FailureBoundary.new
    end

    def reference_json(reference)
      {
        full_name: reference.full_name,
        name: reference.name,
        type: reference.kind,
        label: reference.label
      }
    end
  end
end
