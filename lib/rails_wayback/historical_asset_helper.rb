# frozen_string_literal: true

module RailsWayback
  module HistoricalAssetHelper
    MATERIALIZATION_ROOT_ENV = "rails_wayback.materialization_root"

    def compute_asset_path(source, options = {})
      resolve_historical_asset(source, options) || track_current_asset(source) { super }
    end

    def public_compute_asset_path(source, options = {})
      resolve_historical_asset(source, options) || track_current_asset(source) { super }
    end

    def compute_asset_host(source = "", options = {})
      if historical_asset_url?(source)
        return request.base_url if options[:protocol] == :request

        return nil
      end

      super
    end

    private

    def resolve_historical_asset(source, options)
      context = historical_asset_context
      return unless context

      sha, root = context
      resolution = RailsWayback::HistoricalAssetResolver.new.resolve(
        root: root,
        source: source,
        type: options[:type]
      )
      return unless resolution

      RailsWayback::AssetProvenance.record(
        origin: :historical,
        identifier: "public/#{resolution.public_path}"
      )
      RailsWayback::HistoricalAssetResolver.url(
        sha: sha,
        public_path: resolution.public_path
      )
    end

    def track_current_asset(source)
      result = yield
      RailsWayback::AssetProvenance.record(origin: :current, identifier: source.to_s) if historical_asset_context
      result
    end

    def historical_asset_context
      return unless respond_to?(:rails_wayback_active_ref)

      sha = rails_wayback_active_ref.to_s
      root = request.env[MATERIALIZATION_ROOT_ENV]
      [sha, root] unless sha.empty? || !root
    end

    def historical_asset_url?(source)
      sha = respond_to?(:rails_wayback_active_ref) ? rails_wayback_active_ref.to_s : ""
      !sha.empty? && RailsWayback::HistoricalAssetResolver.historical_url?(source, sha: sha)
    end
  end
end
