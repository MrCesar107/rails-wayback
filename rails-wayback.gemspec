# frozen_string_literal: true

require_relative "lib/rails_wayback/version"

Gem::Specification.new do |spec|
  spec.name = "rails-wayback"
  spec.version = RailsWayback::VERSION
  spec.authors = ["MrCesar107"]
  spec.email = ["cesar.rodriguez.lara54@gmail.com"]

  spec.summary = "Preview and compare Rails UI across git branches and commits."
  spec.description = <<~DESC
    rails-wayback is a Rails engine that lets you travel through git history to
    render past versions of your application's views inside the browser. It runs
    inside the same Rails process the developer is already using and can be
    toggled on/off from the terminal so it never gets in the way of normal
    development.
  DESC
  spec.homepage = "https://github.com/MrCesar107/rails-wayback"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir[
    "{app,config,lib,exe}/**/*",
    "MIT-LICENSE",
    "Rakefile",
    "README.md",
    "rails-wayback.gemspec"
  ].reject { |f| File.directory?(f) }

  spec.bindir = "exe"
  spec.executables = ["rails-wayback"]
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", ">= 7.0"

  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "rake", "~> 13.0"
end
