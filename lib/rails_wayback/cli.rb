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
    COMMANDS = %w[on off status clean help].freeze

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
      when "clean"  then cmd_clean
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
        @stdout.puts "rails-wayback: unavailable (environment #{RailsWayback.current_environment.inspect} is not allowed)"
      end
      0
    end

    def cmd_clean
      RailsWayback::ViewSource.new.cleanup!
      @stdout.puts "rails-wayback: ref cache removed"
      0
    end

    def cmd_help
      @stdout.puts <<~HELP
        Usage: rails-wayback <command>

        Commands:
          on       Enable the wayback UI in this Rails app
          off      Disable the wayback UI
          status   Print whether the UI is currently enabled
          clean    Remove the tmp/rails_wayback ref cache
          help     Show this help
      HELP
      0
    end
  end
end
