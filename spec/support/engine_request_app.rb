# frozen_string_literal: true

require "logger"
require "rails"
require "action_controller/railtie"
require "rack/mock"

project_root = File.expand_path("../..", __dir__)
require File.join(project_root, "app/controllers/rails_wayback/application_controller")
require File.join(project_root, "app/controllers/rails_wayback/references_controller")
require File.join(project_root, "app/controllers/rails_wayback/commits_controller")
require File.join(project_root, "app/controllers/rails_wayback/travels_controller")

module EngineRequestApp
  class Application < Rails::Application
    config.root = File.expand_path("request_app", __dir__)
    config.eager_load = false
    config.secret_key_base = "rails-wayback-request-spec-secret-key-base"
    config.logger = Logger.new(IO::NULL)
    config.hosts.clear
    if Rails::VERSION::MAJOR == 8 && Rails::VERSION::MINOR.zero?
      config.active_support.to_time_preserves_timezone = :zone
    end
    config.action_controller.allow_forgery_protection = false
    config.action_dispatch.show_exceptions = :none
  end

  Application.initialize!
  Application.routes.draw do
    get "/rails-wayback/references", to: RailsWayback::ReferencesController.action(:index)
    get "/rails-wayback/commits", to: RailsWayback::CommitsController.action(:index)
    post "/rails-wayback/travel", to: RailsWayback::TravelsController.action(:create)
    delete "/rails-wayback/travel", to: RailsWayback::TravelsController.action(:destroy)
  end

  module_function

  def request
    Rack::MockRequest.new(Application)
  end
end
