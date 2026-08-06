# frozen_string_literal: true

require "json"
require "rbconfig"

RSpec.describe "RailsWayback Rails integration" do
  it "covers endpoints, travel selection, rendering provenance, and recovery" do
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

    result = JSON.parse(stdout.lines.last)
    expect(result).to include(
      "disabled_status" => 200,
      "disabled_uses_current_view" => true,
      "disabled_bar_absent" => true,
      "disabled_ref_header_absent" => true,
      "branches_status" => 200,
      "branches_current_branch" => "main",
      "branches_include_main" => true,
      "branches_include_nested" => true,
      "commits_status" => 200,
      "commits_branch" => "feature/nested",
      "commits_include_historical" => true,
      "missing_commits_status" => 200,
      "missing_commits_empty" => true,
      "missing_commits_error" => true,
      "broken_view_error" => true,
      "reset_status" => 302,
      "cleared_ref_cookie" => true,
      "cleared_branch_cookie" => true,
      "mixed_preview" => true,
      "historical_partial_tracked" => true,
      "historical_collection_tracked" => true,
      "current_layout_tracked" => true,
      "query_travel_header" => true,
      "cookie_travel_rendered" => true,
      "cookie_travel_header" => true,
      "query_precedes_cookie" => true,
      "unknown_ref_status" => 200,
      "unknown_ref_uses_current_view" => true,
      "unknown_ref_header" => true,
      "external_return_rejected" => true,
      "live_status" => 200,
      "live_uses_current_view" => true,
      "expected_current_sha" => true
    )
  end
end
