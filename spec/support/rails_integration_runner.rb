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

  def capture_scenario(results, name)
    results[name] = yield
  rescue StandardError => e
    results[name] = {
      error: {
        class: e.class.name,
        message: e.message,
        backtrace: Array(e.backtrace).first(10)
      }
    }
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
    config.content_security_policy do |policy|
      policy.default_src :none
      policy.style_src :self
      policy.script_src :self
      policy.connect_src :self
    end
    config.content_security_policy_nonce_generator = ->(_request) { "rails-wayback-test-nonce" }
    config.content_security_policy_nonce_directives = %w[script-src style-src]
  end
  Object.const_set(:RailsWaybackIntegrationApplication, application_class)

  controller_class = Class.new(ActionController::Base) do
    layout "application"

    def index
      @current_name = "Current"
    end

    def fragment
      render html: "<span>Fragment response</span>".html_safe, layout: false
    end

    def lazy_html
      response.content_type = "text/html"
      self.response_body = Enumerator.new do |output|
        output << "<html><body>Lazy response</body></html>"
      end
    end
  end
  Object.const_set(:IntegrationController, controller_class)

  RailsWaybackIntegrationApplication.initialize!
  RailsWaybackIntegrationApplication.routes.draw do
    get "/integration", to: "integration#index"
    get "/integration/fragment", to: "integration#fragment"
    get "/integration/lazy", to: "integration#lazy_html"
    mount RailsWayback::Engine => "/rails-wayback"
  end

  request = Rack::MockRequest.new(RailsWaybackIntegrationApplication)

  results = {}

  RailsIntegrationSupport.capture_scenario(results, :disabled_mode) do
    response = request.get(
      "/integration?_wayback_ref=#{good_historical_sha}&_wayback_branch=main"
    )

    {
      status: response.status,
      uses_current_view: response.body.include?("Current view"),
      bar_absent: !response.body.include?('id="rails-wayback-bar"'),
      ref_header_absent: RailsIntegrationSupport.response_header(
        response,
        RailsWayback::ControllerExtensions::RESPONSE_HEADER
      ).nil?
    }
  end

  RailsWayback.enable!

  RailsIntegrationSupport.capture_scenario(results, :csp_assets) do
    response = request.get("/integration")
    stylesheet = request.get("/rails-wayback/assets/bar.css?v=#{RailsWayback::VERSION}")
    javascript = request.get("/rails-wayback/assets/bar.js?v=#{RailsWayback::VERSION}")
    csp_header = RailsIntegrationSupport.response_header(response, "Content-Security-Policy").to_s

    {
      csp_nonce_in_header: csp_header.include?("'nonce-rails-wayback-test-nonce'"),
      csp_nonce_on_asset_tags: response.body.scan('nonce="rails-wayback-test-nonce"').size == 2,
      external_stylesheet: response.body.include?(
        %(/rails-wayback/assets/bar.css?v=#{RailsWayback::VERSION})
      ),
      external_javascript: response.body.include?(
        %(/rails-wayback/assets/bar.js?v=#{RailsWayback::VERSION})
      ),
      inline_styles_absent: !response.body.include?("<style"),
      inline_javascript_absent: !response.body.include?("(function ()"),
      stylesheet_status: stylesheet.status,
      stylesheet_content_type: stylesheet["Content-Type"].to_s.start_with?("text/css"),
      stylesheet_body: stylesheet.body == RailsWayback::BarRenderer::STYLES,
      javascript_status: javascript.status,
      javascript_content_type: javascript["Content-Type"].to_s.start_with?("application/javascript"),
      javascript_body: javascript.body == RailsWayback::BarRenderer::SCRIPT,
      immutable_cache: [stylesheet, javascript].all? do |asset|
        asset["Cache-Control"].to_s.include?("immutable")
      end,
      nosniff: [stylesheet, javascript].all? do |asset|
        asset["X-Content-Type-Options"] == "nosniff"
      end,
      asset_responses_exclude_bar: [stylesheet, javascript].none? do |asset|
        asset.body.include?('id="rails-wayback-bar"')
      end
    }
  end

  RailsIntegrationSupport.capture_scenario(results, :response_safety) do
    head_response = request.request("HEAD", "/integration")
    fragment_response = request.get("/integration/fragment")
    lazy_response = request.get("/integration/lazy")

    {
      head_status: head_response.status,
      head_body_empty: head_response.body.empty?,
      fragment_status: fragment_response.status,
      fragment_preserved: fragment_response.body == "<span>Fragment response</span>",
      fragment_bar_absent: !fragment_response.body.include?('id="rails-wayback-bar"'),
      lazy_status: lazy_response.status,
      lazy_body_preserved: lazy_response.body.include?("Lazy response"),
      lazy_bar_absent: !lazy_response.body.include?('id="rails-wayback-bar"')
    }
  end

  RailsIntegrationSupport.capture_scenario(results, :branch_endpoints) do
    branches_response = request.get("/rails-wayback/branches")
    branches_payload = JSON.parse(branches_response.body)
    commits_response = request.get("/rails-wayback/commits/feature/nested")
    commits_payload = JSON.parse(commits_response.body)
    missing_response = request.get("/rails-wayback/commits/missing-branch")
    missing_payload = JSON.parse(missing_response.body)

    {
      branches_status: branches_response.status,
      current_branch: branches_payload["current_branch"],
      current_commit_matches: branches_payload["current_commit"] == current_sha,
      includes_main: branches_payload.fetch("branches").include?("main"),
      includes_nested: branches_payload.fetch("branches").include?("feature/nested"),
      commits_status: commits_response.status,
      commits_branch: commits_payload["branch"],
      includes_historical_commit: commits_payload.fetch("commits").any? do |commit|
        commit["sha"] == good_historical_sha && commit["subject"] == "historical compatible view"
      end,
      missing_status: missing_response.status,
      missing_commits_empty: missing_payload["commits"] == [],
      missing_error: missing_payload["error"].to_s.include?("GitError")
    }
  end

  RailsIntegrationSupport.capture_scenario(results, :error_recovery) do
    broken_error = begin
      request.get(
        "/integration",
        "HTTP_COOKIE" => "rails_wayback_ref=#{broken_historical_sha}; rails_wayback_branch=main"
      )
      nil
    rescue StandardError => e
      e
    end
    recovery_response = request.get(
      "/integration?_wayback_ref=#{good_historical_sha}&_wayback_branch=main"
    )

    {
      incompatible_view_error: broken_error &&
        RailsIntegrationSupport.exception_messages(broken_error)
                               .include?("helper_removed_from_current_application"),
      subsequent_request_succeeds: recovery_response.status == 200 &&
        recovery_response.body.include?("Historical view")
    }
  end

  RailsIntegrationSupport.capture_scenario(results, :reset_security) do
    reset_response = request.get(
      "/rails-wayback/reset?return_to=%2Fintegration",
      "HTTP_COOKIE" => "rails_wayback_ref=#{broken_historical_sha}; rails_wayback_branch=main"
    )
    reset_cookies = Array(reset_response.headers["set-cookie"]).join("\n")
    unsafe_response = request.get(
      "/rails-wayback/reset?return_to=https%3A%2F%2Fevil.example%2Fescape"
    )
    unsafe_location = URI.parse(unsafe_response.headers.fetch("location"))

    {
      status: reset_response.status,
      clears_ref_cookie: reset_cookies.include?("rails_wayback_ref=") &&
        reset_cookies.include?("max-age=0"),
      clears_branch_cookie: reset_cookies.include?("rails_wayback_branch=") &&
        reset_cookies.include?("max-age=0"),
      rejects_external_return: unsafe_location.host == "example.org" &&
        unsafe_location.path == "/"
    }
  end

  RailsIntegrationSupport.capture_scenario(results, :render_provenance) do
    response = request.get(
      "/integration?_wayback_ref=#{good_historical_sha}&_wayback_branch=main"
    )

    {
      mixed_preview: response.body.include?('data-preview-mode="mixed"'),
      historical_partial_tracked: response.body.include?("Historical partial"),
      historical_collection_tracked: response.body.include?("3 historical templates"),
      current_layout_tracked: response.body.include?("1 current fallback")
    }
  end

  RailsIntegrationSupport.capture_scenario(results, :travel_selection) do
    query_response = request.get(
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
    unknown_response = request.get("/integration?_wayback_ref=missing-ref")

    {
      query_header: RailsIntegrationSupport.response_header(
        query_response,
        RailsWayback::ControllerExtensions::RESPONSE_HEADER
      ) == good_historical_sha,
      cookie_rendered: cookie_response.body.include?("Historical view"),
      cookie_header: RailsIntegrationSupport.response_header(
        cookie_response,
        RailsWayback::ControllerExtensions::RESPONSE_HEADER
      ) == good_historical_sha,
      query_precedes_cookie: precedence_response.body.include?("Historical view") &&
        RailsIntegrationSupport.response_header(
          precedence_response,
          RailsWayback::ControllerExtensions::RESPONSE_HEADER
        ) == good_historical_sha,
      unknown_status: unknown_response.status,
      unknown_uses_current_view: unknown_response.body.include?("Current view"),
      unknown_header: RailsIntegrationSupport.response_header(
        unknown_response,
        RailsWayback::ControllerExtensions::RESPONSE_HEADER
      ) == "error:RailsWayback::RefNotFoundError"
    }
  end

  RailsIntegrationSupport.capture_scenario(results, :live_rendering) do
    response = request.get("/integration")

    {
      status: response.status,
      uses_current_view: response.body.include?("Current view")
    }
  end

  puts JSON.generate(results)
end
