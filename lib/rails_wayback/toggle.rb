# frozen_string_literal: true

require "fileutils"

module RailsWayback
  # Shares the current server session's state between the CLI and Rails.
  #
  # The flag is a plain file inside `tmp/rails_wayback/enabled` (ignored by
  # git). We keep it as a file so the CLI, rake tasks and running Rails
  # process all agree on the same state without booting extra services. The
  # engine clears stale state whenever a new Rails server session starts.
  class Toggle
    def initialize(configuration = RailsWayback.configuration)
      @configuration = configuration
    end

    def enabled?
      configuration.toggle_file_path.exist?
    end

    def enable!
      FileUtils.mkdir_p(configuration.toggle_file_path.dirname)
      FileUtils.touch(configuration.toggle_file_path)
      touch_routes_reload_marker
      true
    end

    def disable!
      FileUtils.rm_f(configuration.toggle_file_path)
      touch_routes_reload_marker
      true
    end

    # Start a new server session disabled. Unlike `disable!`, this does not
    # touch routes: Rails is already loading them as part of server boot.
    def reset!
      FileUtils.rm_f(configuration.toggle_file_path)
      true
    end

    def status
      enabled? ? :on : :off
    end

    private

    attr_reader :configuration

    # Rails reloads routes in development when config/routes.rb changes.
    # After toggling we bump its mtime so the next request picks up the
    # conditional `mount` immediately, without asking the developer to
    # touch files manually.
    def touch_routes_reload_marker
      routes_file = configuration.app_root_path.join("config", "routes.rb")
      FileUtils.touch(routes_file) if routes_file.file?
    rescue StandardError
      # Best-effort: never fail toggling because of a filesystem hiccup.
      nil
    end
  end
end
