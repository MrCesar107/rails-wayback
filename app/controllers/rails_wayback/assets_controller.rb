# frozen_string_literal: true

require "digest"
require "rack/mime"
require "rails_wayback/bar_renderer"

module RailsWayback
  # Serves the toolbar's bundled assets without depending on the host
  # application's asset pipeline.
  class AssetsController < ApplicationController
    CACHE_CONTROL = "public, max-age=31536000, immutable"

    skip_forgery_protection

    def stylesheet
      render_asset(BarRenderer::STYLES, "text/css")
    end

    def javascript
      render_asset(BarRenderer::SCRIPT, "application/javascript")
    end

    def historical
      selection = RailsWayback::RefPolicy.new.authorize(params[:sha])
      return render_rejection(selection) if selection.rejected?

      source = RailsWayback::ViewSource.new
      resolution = resolve_asset(source, selection.sha, params[:path])
      return head :not_found unless resolution

      set_historical_headers(selection.sha, resolution)
      return head :ok if request.head?

      self.response_body = RailsWayback::HistoricalAssetBody.new(
        sha: selection.sha,
        public_path: resolution.public_path,
        view_source: source
      )
    rescue RailsWayback::Git::GitError, RailsWayback::MaterializationError => e
      render json: { error: e.message }, status: :service_unavailable
    end

    private

    def resolve_asset(source, sha, path)
      resolution = nil
      source.with_materialization(sha) do |root|
        resolution = RailsWayback::HistoricalAssetResolver.new.resolve_public_path(
          root: root,
          public_path: path
        )
      end
      resolution
    end

    def set_historical_headers(sha, resolution)
      content_type = Rack::Mime.mime_type(File.extname(resolution.public_path), "application/octet-stream")
      response.content_type = content_type
      response.set_header("Content-Length", resolution.size_bytes.to_s)
      response.set_header("Cache-Control", CACHE_CONTROL)
      response.set_header("X-Content-Type-Options", "nosniff")
      response.set_header("ETag", %("#{Digest::SHA256.hexdigest("#{sha}:#{resolution.public_path}")}"))
    end

    def render_rejection(selection)
      status = case selection.reason
               when :invalid_format then :bad_request
               when :unknown_ref then :not_found
               else :forbidden
               end
      render json: { error: selection.message }, status: status
    end

    def render_asset(content, content_type)
      response.set_header("Cache-Control", CACHE_CONTROL)
      response.set_header("X-Content-Type-Options", "nosniff")
      render plain: content, content_type: content_type
    end
  end
end
