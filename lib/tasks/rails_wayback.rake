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
end
