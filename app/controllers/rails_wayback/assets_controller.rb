# frozen_string_literal: true

require "rails_wayback/bar_renderer"

module RailsWayback
  # Serves the toolbar's bundled assets without depending on the host
  # application's asset pipeline.
  class AssetsController < ApplicationController
    CACHE_CONTROL = "public, max-age=31536000, immutable"

    def stylesheet
      render_asset(BarRenderer::STYLES, "text/css")
    end

    def javascript
      render_asset(BarRenderer::SCRIPT, "application/javascript")
    end

    private

    def render_asset(content, content_type)
      response.set_header("Cache-Control", CACHE_CONTROL)
      response.set_header("X-Content-Type-Options", "nosniff")
      render plain: content, content_type: content_type
    end
  end
end
