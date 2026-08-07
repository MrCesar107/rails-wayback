# frozen_string_literal: true

require "json"
require "rbconfig"

RSpec.describe "RailsWayback Rails integration" do
  before(:context) do
    project_root = File.expand_path("../..", __dir__)
    runner = File.join(project_root, "spec/support/rails_integration_runner.rb")

    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      "-I#{File.join(project_root, "lib")}",
      runner,
      chdir: project_root
    )

    expect(status).to be_success, <<~MESSAGE
      Rails integration runner failed.
      stdout:
      #{stdout}
      stderr:
      #{stderr}
    MESSAGE

    @integration_result = JSON.parse(stdout.lines.last)
  end

  def scenario(name)
    result = @integration_result.fetch(name)
    expect(result["error"]).to be_nil, <<~MESSAGE
      Rails integration scenario #{name.inspect} failed.
      #{JSON.pretty_generate(result.fetch("error", {}))}
    MESSAGE
    result
  end

  it "leaves current rendering untouched while disabled" do
    expect(scenario("disabled_mode")).to include(
      "status" => 200,
      "uses_current_view" => true,
      "bar_absent" => true,
      "ref_header_absent" => true
    )
  end

  it "serves external toolbar assets that work with Rails CSP nonces" do
    expect(scenario("csp_assets")).to include(
      "csp_nonce_in_header" => true,
      "csp_nonce_on_asset_tags" => true,
      "external_stylesheet" => true,
      "external_javascript" => true,
      "inline_styles_absent" => true,
      "inline_javascript_absent" => true,
      "stylesheet_status" => 200,
      "stylesheet_content_type" => true,
      "stylesheet_body" => true,
      "javascript_status" => 200,
      "javascript_content_type" => true,
      "javascript_body" => true,
      "immutable_cache" => true,
      "nosniff" => true,
      "asset_responses_exclude_bar" => true
    )
  end

  it "preserves HEAD, fragment, and lazy enumerable responses" do
    expect(scenario("response_safety")).to include(
      "head_status" => 200,
      "head_body_empty" => true,
      "fragment_status" => 200,
      "fragment_preserved" => true,
      "fragment_bar_absent" => true,
      "lazy_status" => 200,
      "lazy_body_preserved" => true,
      "lazy_bar_absent" => true
    )
  end

  it "serves branch and commit endpoints, including nested and missing branches" do
    expect(scenario("branch_endpoints")).to include(
      "branches_status" => 200,
      "current_branch" => "main",
      "current_commit_matches" => true,
      "includes_main" => true,
      "includes_nested" => true,
      "commits_status" => 200,
      "commits_branch" => "feature/nested",
      "includes_historical_commit" => true,
      "missing_status" => 200,
      "missing_commits_empty" => true,
      "missing_error" => true
    )
  end

  it "recovers request state after an incompatible historical view" do
    expect(scenario("error_recovery")).to include(
      "incompatible_view_error" => true,
      "subsequent_request_succeeds" => true
    )
  end

  it "clears travel cookies and rejects external reset destinations" do
    expect(scenario("reset_security")).to include(
      "status" => 302,
      "clears_ref_cookie" => true,
      "clears_branch_cookie" => true,
      "rejects_external_return" => true
    )
  end

  it "reports mixed historical and current rendering provenance" do
    expect(scenario("render_provenance")).to include(
      "mixed_preview" => true,
      "historical_partial_tracked" => true,
      "historical_collection_tracked" => true,
      "current_layout_tracked" => true
    )
  end

  it "selects travel refs from query parameters and cookies" do
    expect(scenario("travel_selection")).to include(
      "query_header" => true,
      "cookie_rendered" => true,
      "cookie_header" => true,
      "query_precedes_cookie" => true,
      "unknown_status" => 200,
      "unknown_uses_current_view" => true,
      "unknown_header" => true
    )
  end

  it "renders the current view without a travel ref" do
    expect(scenario("live_rendering")).to include(
      "status" => 200,
      "uses_current_view" => true
    )
  end
end
