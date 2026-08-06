# frozen_string_literal: true

require "fileutils"
require "json"
require "logger"
require "open3"
require "pathname"
require "tmpdir"
require "uri"

ENV["RAILS_ENV"] = "test"

require "rails"
require "action_controller/railtie"
require "rails_wayback"

module RailsIntegrationSupport
  module_function

  def run!(*command, chdir:)
    stdout, stderr, status = Open3.capture3(*command, chdir: chdir)
    raise "#{command.join(" ")} failed: #{stderr}" unless status.success?

    stdout
  end

  def write(path, contents)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
  end

  def commit(root, message)
    run!("git", "add", ".", chdir: root)
    run!("git", "commit", "--quiet", "-m", message, chdir: root)
    run!("git", "rev-parse", "HEAD", chdir: root).strip
  end

  def exception_messages(error)
    messages = []
    while error
      messages << error.message
      error = error.cause
    end
    messages.join("\n")
  end

  def response_header(response, name)
    response.headers[name] || response.headers[name.downcase]
  end
end

Dir.mktmpdir("rails-wayback-integration-") do |root_string|
  root = Pathname.new(root_string)
  RailsIntegrationSupport.run!("git", "init", "--quiet", "--initial-branch=main", chdir: root)
  RailsIntegrationSupport.run!("git", "config", "user.email", "integration@example.com", chdir: root)
  RailsIntegrationSupport.run!("git", "config", "user.name", "Integration Test", chdir: root)
  RailsIntegrationSupport.run!("git", "config", "commit.gpgsign", "false", chdir: root)

  index_path = root.join("app/views/integration/index.html.erb")
  partial_path = root.join("app/views/integration/_historical.html.erb")
  item_path = root.join("app/views/integration/_item.html.erb")
  layout_path = root.join("app/views/layouts/application.html.erb")

  RailsIntegrationSupport.write(
    index_path,
    <<~ERB
      <h1>Historical view</h1>
      <%= render "integration/historical" %>
      <%= render partial: "integration/item", collection: %w[one two], as: :item %>
    ERB
  )
  RailsIntegrationSupport.write(partial_path, %(<p>Historical partial</p>))
  RailsIntegrationSupport.write(item_path, %(<span><%= item %></span>))
  good_historical_sha = RailsIntegrationSupport.commit(root, "historical compatible view")

  RailsIntegrationSupport.write(index_path, %(<%= helper_removed_from_current_application %>))
  broken_historical_sha = RailsIntegrationSupport.commit(root, "historical incompatible view")

  RailsIntegrationSupport.write(index_path, %(<h1>Current view</h1>))
  RailsIntegrationSupport.write(layout_path, %(<!doctype html><html><body><%= yield %></body></html>))
  current_sha = RailsIntegrationSupport.commit(root, "current view")
  RailsIntegrationSupport.run!("git", "branch", "feature/nested", good_historical_sha, chdir: root)

  RailsWayback.configure do |config|
    config.app_root = root
    config.cache_root = root.join("tmp/rails_wayback")
  end

  application_class = Class.new(Rails::Application) do
    config.root = root
    config.eager_load = false
    config.secret_key_base = "rails-wayback-integration-secret-key-base"
    config.logger = Logger.new(IO::NULL)
    config.hosts.clear
    config.action_dispatch.show_exceptions = :none
    config.action_controller.allow_forgery_protection = false
  end
  Object.const_set(:RailsWaybackIntegrationApplication, application_class)

  controller_class = Class.new(ActionController::Base) do
    layout "application"

    def index
      @current_name = "Current"
    end
  end
  Object.const_set(:IntegrationController, controller_class)

  RailsWaybackIntegrationApplication.initialize!
  RailsWaybackIntegrationApplication.routes.draw do
    get "/integration", to: "integration#index"
    mount RailsWayback::Engine => "/rails-wayback"
  end

  request = Rack::MockRequest.new(RailsWaybackIntegrationApplication)

  disabled_response = request.get(
    "/integration?_wayback_ref=#{good_historical_sha}&_wayback_branch=main"
  )

  RailsWayback.enable!

  branches_response = request.get("/rails-wayback/branches")
  branches_payload = JSON.parse(branches_response.body)
  commits_response = request.get("/rails-wayback/commits/feature/nested")
  commits_payload = JSON.parse(commits_response.body)
  missing_commits_response = request.get("/rails-wayback/commits/missing-branch")
  missing_commits_payload = JSON.parse(missing_commits_response.body)

  broken_error = begin
    request.get(
      "/integration",
      "HTTP_COOKIE" => "rails_wayback_ref=#{broken_historical_sha}; rails_wayback_branch=main"
    )
    nil
  rescue StandardError => error
    error
  end
  broken_view_error = broken_error &&
                      RailsIntegrationSupport.exception_messages(broken_error)
                                             .include?("helper_removed_from_current_application")

  reset_response = request.get(
    "/rails-wayback/reset?return_to=%2Fintegration",
    "HTTP_COOKIE" => "rails_wayback_ref=#{broken_historical_sha}; rails_wayback_branch=main"
  )
  reset_cookies = Array(reset_response.headers["set-cookie"]).join("\n")
  unsafe_reset_response = request.get(
    "/rails-wayback/reset?return_to=https%3A%2F%2Fevil.example%2Fescape"
  )
  unsafe_location = URI.parse(unsafe_reset_response.headers.fetch("location"))

  mixed_response = request.get(
    "/integration?_wayback_ref=#{good_historical_sha}&_wayback_branch=main"
  )
  cookie_response = request.get(
    "/integration",
    "HTTP_COOKIE" => "rails_wayback_ref=#{good_historical_sha}; rails_wayback_branch=main"
  )
  precedence_response = request.get(
    "/integration?_wayback_ref=#{good_historical_sha}&_wayback_branch=main",
    "HTTP_COOKIE" => "rails_wayback_ref=#{broken_historical_sha}; rails_wayback_branch=other"
  )
  unknown_ref_response = request.get("/integration?_wayback_ref=missing-ref")
  live_response = request.get("/integration")

  puts JSON.generate(
    disabled_status: disabled_response.status,
    disabled_uses_current_view: disabled_response.body.include?("Current view"),
    disabled_bar_absent: !disabled_response.body.include?('id="rails-wayback-bar"'),
    disabled_ref_header_absent: RailsIntegrationSupport.response_header(
      disabled_response,
      RailsWayback::ControllerExtensions::RESPONSE_HEADER
    ).nil?,
    branches_status: branches_response.status,
    branches_current_branch: branches_payload["current_branch"],
    branches_current_commit: branches_payload["current_commit"],
    branches_include_main: branches_payload.fetch("branches").include?("main"),
    branches_include_nested: branches_payload.fetch("branches").include?("feature/nested"),
    commits_status: commits_response.status,
    commits_branch: commits_payload["branch"],
    commits_include_historical: commits_payload.fetch("commits").any? do |commit|
      commit["sha"] == good_historical_sha && commit["subject"] == "historical compatible view"
    end,
    missing_commits_status: missing_commits_response.status,
    missing_commits_empty: missing_commits_payload["commits"] == [],
    missing_commits_error: missing_commits_payload["error"].to_s.include?("GitError"),
    broken_view_error: !!broken_view_error,
    reset_status: reset_response.status,
    cleared_ref_cookie: reset_cookies.include?("rails_wayback_ref=") && reset_cookies.include?("max-age=0"),
    cleared_branch_cookie: reset_cookies.include?("rails_wayback_branch=") && reset_cookies.include?("max-age=0"),
    mixed_preview: mixed_response.body.include?('data-preview-mode="mixed"'),
    historical_partial_tracked: mixed_response.body.include?("Historical partial"),
    historical_collection_tracked: mixed_response.body.include?("3 historical templates"),
    current_layout_tracked: mixed_response.body.include?("1 current fallback"),
    query_travel_header: RailsIntegrationSupport.response_header(
      mixed_response,
      RailsWayback::ControllerExtensions::RESPONSE_HEADER
    ) == good_historical_sha,
    cookie_travel_rendered: cookie_response.body.include?("Historical view"),
    cookie_travel_header: RailsIntegrationSupport.response_header(
      cookie_response,
      RailsWayback::ControllerExtensions::RESPONSE_HEADER
    ) == good_historical_sha,
    query_precedes_cookie: precedence_response.body.include?("Historical view") &&
                           RailsIntegrationSupport.response_header(
                             precedence_response,
                             RailsWayback::ControllerExtensions::RESPONSE_HEADER
                           ) == good_historical_sha,
    unknown_ref_status: unknown_ref_response.status,
    unknown_ref_uses_current_view: unknown_ref_response.body.include?("Current view"),
    unknown_ref_header: RailsIntegrationSupport.response_header(
      unknown_ref_response,
      RailsWayback::ControllerExtensions::RESPONSE_HEADER
    ) == "error:RailsWayback::RefNotFoundError",
    external_return_rejected: unsafe_location.host == "example.org" && unsafe_location.path == "/",
    live_status: live_response.status,
    live_uses_current_view: live_response.body.include?("Current view"),
    expected_current_sha: branches_payload["current_commit"] == current_sha
  )
end
