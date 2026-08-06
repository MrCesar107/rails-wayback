# frozen_string_literal: true

require "rails/generators"
require "generators/rails_wayback/install/install_generator"

RSpec.describe RailsWayback::Generators::InstallGenerator do
  it "installs the initializer, conditional route, and cache ignore entry idempotently" do
    Dir.mktmpdir("rails-wayback-generator-") do |directory|
      root = Pathname.new(directory)
      FileUtils.mkdir_p(root.join("config"))
      root.join("config/routes.rb").write(<<~RUBY)
        Rails.application.routes.draw do
        end
      RUBY
      root.join(".gitignore").write("/log/*.log\n")

      2.times do
        described_class.start(["--force"], destination_root: root.to_s)
      end

      initializer = root.join("config/initializers/rails_wayback.rb")
      routes = root.join("config/routes.rb").read
      gitignore = root.join(".gitignore").read

      expect(initializer).to exist
      expect(initializer.read).to include("RailsWayback.configure")
      expect(routes.scan("mount RailsWayback::Engine").size).to eq(1)
      expect(routes).to include(
        'if defined?(RailsWayback) && RailsWayback.enabled?'
      )
      expect(gitignore.scan("/tmp/rails_wayback/").size).to eq(1)
      expect(gitignore).to include("/log/*.log")
    end
  end
end
