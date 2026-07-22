# frozen_string_literal: true

require "rails/generators"

module RailsWayback
  module Generators
    class InstallGenerator < ::Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def copy_initializer
        template "initializer.rb.tt", "config/initializers/rails_wayback.rb"
      end

      def mount_engine
        route_snippet = <<~ROUTE
          mount RailsWayback::Engine => "/rails-wayback" if defined?(RailsWayback) && RailsWayback.enabled?
        ROUTE

        routes_file = "config/routes.rb"

        if File.file?(routes_file) && File.read(routes_file).include?("RailsWayback::Engine")
          say_status :skip, "RailsWayback::Engine mount already present in #{routes_file}"
        else
          route route_snippet.strip
        end
      end

      def update_gitignore
        gitignore = ".gitignore"
        entry = "/tmp/rails_wayback/\n"
        if File.file?(gitignore) && !File.read(gitignore).include?("tmp/rails_wayback")
          append_to_file(gitignore, entry)
        elsif !File.file?(gitignore)
          create_file(gitignore, entry)
        end
      end
    end
  end
end
