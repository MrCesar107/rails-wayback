# frozen_string_literal: true

require "rails_wayback"

module RailsWayback
  # Small CLI powering the `rails-wayback` executable.
  #
  #   rails-wayback on      # enable the engine in the host app
  #   rails-wayback off     # disable it
  #   rails-wayback status  # print current state
  #   rails-wayback clean   # remove the ref cache under tmp/
  class CLI
    COMMANDS = %w[on off status cache prune clean doctor help].freeze
    DOCTOR_LABELS = { ok: "OK", warning: "WARN", error: "ERROR" }.freeze

    def self.start(argv, stdout: $stdout, stderr: $stderr)
      new(stdout: stdout, stderr: stderr).run(argv)
    end

    def initialize(stdout: $stdout, stderr: $stderr)
      @stdout = stdout
      @stderr = stderr
    end

    def run(argv)
      command = (argv.first || "help").to_s
      case command
      when "on"     then cmd_on
      when "off"    then cmd_off
      when "status" then cmd_status
      when "cache"  then cmd_cache
      when "prune"  then cmd_prune
      when "clean"  then cmd_clean
      when "doctor" then cmd_doctor
      when "help", "--help", "-h" then cmd_help
      else
        @stderr.puts "Unknown command: #{command}"
        cmd_help
        1
      end
    end

    private

    def cmd_on
      RailsWayback.enable!
      @stdout.puts "rails-wayback: enabled for this server session (mounted at /rails-wayback on the next request)"
      0
    rescue RailsWayback::DisabledError => e
      @stderr.puts "rails-wayback: cannot enable: #{e.message}"
      1
    end

    def cmd_off
      RailsWayback.disable!
      @stdout.puts "rails-wayback: disabled"
      0
    end

    def cmd_status
      if RailsWayback.environment_allowed?
        @stdout.puts "rails-wayback: #{RailsWayback.toggle.status}"
      else
        environment = RailsWayback.current_environment.inspect
        @stdout.puts "rails-wayback: unavailable (environment #{environment} is not allowed)"
      end
      0
    end

    def cmd_clean
      RailsWayback::ViewSource.new.cleanup!
      @stdout.puts "rails-wayback: ref cache removed"
      0
    end

    def cmd_cache
      snapshot = RailsWayback::ViewSource.new.cache_snapshot
      @stdout.puts cache_summary(snapshot)
      0
    rescue RailsWayback::MaterializationError => e
      @stderr.puts "rails-wayback: cannot inspect cache: #{e.message}"
      1
    end

    def cmd_prune
      result = RailsWayback::ViewSource.new.prune!
      @stdout.puts "rails-wayback: pruned #{result.removed.size} ref(s), " \
                   "freed #{format_bytes(result.removed_size_bytes)}"
      @stdout.puts cache_summary(result.snapshot)
      result.limits_satisfied? ? 0 : 1
    rescue RailsWayback::MaterializationError => e
      @stderr.puts "rails-wayback: cannot prune cache: #{e.message}"
      1
    end

    def cmd_doctor
      result = RailsWayback::Doctor.new.call
      @stdout.puts "rails-wayback doctor"
      result.checks.each do |check|
        @stdout.puts "[#{DOCTOR_LABELS.fetch(check.status)}] #{check.name}: #{check.message}"
      end
      @stdout.puts(result.ready? ? "Result: ready" : "Result: not ready")
      result.exit_status
    end

    def cmd_help
      @stdout.puts <<~HELP
        Usage: rails-wayback <command>

        Commands:
          on       Enable the wayback UI in this Rails app
          off      Disable the wayback UI
          status   Print whether the UI is currently enabled
          cache    Print ref cache usage and configured limits
          prune    Remove least-recently-used refs until limits are satisfied
          clean    Remove the tmp/rails_wayback ref cache
          doctor   Check dependencies and host application readiness
          help     Show this help
      HELP
      0
    end

    def cache_summary(snapshot)
      config = RailsWayback.configuration
      count_limit = config.max_cached_refs.nil? ? "unlimited" : config.max_cached_refs
      byte_limit = config.max_cache_bytes.nil? ? "unlimited" : format_bytes(config.max_cache_bytes)
      "rails-wayback cache: #{snapshot.ref_count} ref(s), #{format_bytes(snapshot.size_bytes)}, " \
        "#{snapshot.file_count} file(s); limits: #{count_limit} refs / #{byte_limit}"
    end

    def format_bytes(value)
      bytes = Integer(value)
      return "#{bytes} B" if bytes < 1024

      units = %w[KiB MiB GiB TiB]
      amount = bytes / 1024.0
      unit = units.shift
      while amount >= 1024 && units.any?
        amount /= 1024
        unit = units.shift
      end
      format("%<amount>.1f %<unit>s", amount: amount, unit: unit)
    end
  end
end
