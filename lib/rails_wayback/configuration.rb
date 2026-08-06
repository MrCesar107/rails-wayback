# frozen_string_literal: true

require "pathname"

module RailsWayback
  class Configuration
    # Includes the common places where Rails apps put render targets.
    # `app/components` is picked up by the ViewComponent gem;
    # `app/views` is stock Rails.
    DEFAULT_VIEW_PATHS = ["app/views", "app/components"].freeze
    DEFAULT_ASSET_PATHS = ["app/assets", "public"].freeze
    DEFAULT_MAX_COMMITS = 50
    DEFAULT_ALLOWED_ENVIRONMENTS = %w[development test].freeze

    attr_accessor :view_paths, :asset_paths, :max_commits, :allowed_environments,
                  :app_root, :cache_root, :toggle_file

    def initialize
      @view_paths = DEFAULT_VIEW_PATHS.dup
      @asset_paths = DEFAULT_ASSET_PATHS.dup
      @max_commits = DEFAULT_MAX_COMMITS
      @allowed_environments = DEFAULT_ALLOWED_ENVIRONMENTS.dup
      @app_root = nil
      @cache_root = nil
      @toggle_file = nil
    end

    def app_root_path
      Pathname.new(@app_root || RailsWayback.root)
    end

    def cache_root_path
      Pathname.new(@cache_root || app_root_path.join("tmp", "rails_wayback"))
    end

    def toggle_file_path
      Pathname.new(@toggle_file || cache_root_path.join("enabled"))
    end

    def refs_cache_path
      cache_root_path.join("refs")
    end
  end
end
