# frozen_string_literal: true

require "rails_wayback/cli"

namespace :wayback do
  desc "Enable the rails-wayback UI"
  task on: :environment do
    RailsWayback::CLI.start(["on"])
  end

  desc "Disable the rails-wayback UI"
  task off: :environment do
    RailsWayback::CLI.start(["off"])
  end

  desc "Print the current rails-wayback state"
  task status: :environment do
    RailsWayback::CLI.start(["status"])
  end

  desc "Remove the rails-wayback ref cache under tmp/"
  task clean: :environment do
    RailsWayback::CLI.start(["clean"])
  end

  desc "Print rails-wayback ref cache usage"
  task cache: :environment do
    RailsWayback::CLI.start(["cache"])
  end

  desc "Prune least-recently-used refs to the configured limits"
  task prune: :environment do
    status = RailsWayback::CLI.start(["prune"])
    raise "rails-wayback cache remains over its configured limits" unless status.zero?
  end

  desc "Check rails-wayback dependencies and host application readiness"
  task doctor: :environment do
    status = RailsWayback::CLI.start(["doctor"])
    raise "rails-wayback doctor found critical problems" unless status.zero?
  end
end
