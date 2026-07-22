# frozen_string_literal: true

module RailsWayback
  class ApplicationController < ::ActionController::API
    before_action :ensure_enabled!

    private

    def ensure_enabled!
      return if RailsWayback.enabled?

      render json: { error: "rails-wayback is disabled" }, status: :service_unavailable
    end

    def git
      @git ||= RailsWayback::Git.new
    end
  end
end
