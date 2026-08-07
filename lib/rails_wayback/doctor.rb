# frozen_string_literal: true

require "fileutils"
require "open3"
require "pathname"
require "tempfile"

module RailsWayback
  # Performs explicit, non-destructive readiness checks for the host app.
  class Doctor
    Check = Struct.new(:name, :status, :message, keyword_init: true) do
      def error?
        status == :error
      end
    end

    Result = Struct.new(:checks, keyword_init: true) do
      def ready?
        checks.none?(&:error?)
      end

      def exit_status
        ready? ? 0 : 1
      end
    end

    def initialize(configuration: RailsWayback.configuration, git: nil,
                   environment: RailsWayback.current_environment, capture3: nil)
      @configuration = configuration
      @git = git || Git.new(root: configuration.app_root_path)
      @environment = environment.to_s
      @capture3 = capture3 || Open3.method(:capture3)
    end

    def call
      root_check = app_root_check
      checks = [environment_check, root_check]
      git_check = executable_check("Git", "git")
      checks << git_check
      checks << repository_check unless git_check.error? || root_check.error?
      checks << executable_check("tar", "tar", version_optional: true)
      checks << if root_check.error?
                  check("Cache directory", :error, "not checked because the application root is missing")
                else
                  cache_check
                end
      checks << configured_paths_check
      Result.new(checks: checks)
    end

    private

    attr_reader :configuration, :git, :environment, :capture3

    def environment_check
      allowed = Array(configuration.allowed_environments).map(&:to_s)
      return check("Rails environment", :warning, "not detected; allowed: #{allowed.join(", ")}") if environment.empty?
      return check("Rails environment", :ok, "#{environment} (allowed)") if allowed.include?(environment)

      check("Rails environment", :error, "#{environment} is not allowed; allowed: #{allowed.join(", ")}")
    end

    def app_root_check
      root = configuration.app_root_path
      return check("Application root", :ok, root.to_s) if root.directory?

      check("Application root", :error, "directory does not exist: #{root}")
    end

    def executable_check(label, executable, version_optional: false)
      stdout, stderr, status = capture3.call(executable, "--version")
      details = [stdout, stderr].map(&:strip).find { |value| !value.empty? }
      return check(label, :ok, details || "available") if status.success?
      return check(label, :warning, "available, but `#{executable} --version` is unsupported") if version_optional

      check(label, :error, "#{executable} --version exited with status #{status.exitstatus}")
    rescue Errno::ENOENT
      check(label, :error, "required executable `#{executable}` was not found in PATH")
    rescue SystemCallError => e
      check(label, :error, "could not execute `#{executable}`: #{e.message}")
    end

    def repository_check
      return check("Git repository", :ok, git.root.to_s) if git.repository?

      check("Git repository", :error, "no Git work tree found at #{git.root}")
    end

    def cache_check
      root = configuration.cache_root_path
      FileUtils.mkdir_p(root)
      Tempfile.create(".rails-wayback-doctor-", root) { |file| file.write("ok") }
      check("Cache directory", :ok, "writable: #{root}")
    rescue SystemCallError => e
      check("Cache directory", :error, "not writable at #{root}: #{e.message}")
    end

    def configured_paths_check
      paths = (Array(configuration.view_paths) + Array(configuration.asset_paths)).map(&:to_s).uniq
      invalid = paths.select { |path| unsafe_relative_path?(path) }
      return check("Configured paths", :error, "must be safe relative paths: #{invalid.join(", ")}") if invalid.any?

      existing, missing = paths.partition { |path| configuration.app_root_path.join(path).directory? }
      message = "#{existing.size}/#{paths.size} exist"
      message = "#{message}; absent paths are skipped: #{missing.join(", ")}" if missing.any?
      status = existing.empty? ? :warning : :ok
      check("Configured paths", status, message)
    end

    def unsafe_relative_path?(value)
      return true if value.empty?

      path = Pathname.new(value)
      path.absolute? || path.cleanpath.each_filename.first == ".."
    rescue ArgumentError
      true
    end

    def check(name, status, message)
      Check.new(name: name, status: status, message: message)
    end
  end
end
