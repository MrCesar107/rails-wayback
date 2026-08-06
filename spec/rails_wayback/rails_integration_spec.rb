# frozen_string_literal: true

require "json"
require "rbconfig"

RSpec.describe "RailsWayback Rails integration" do
  it "recovers from a broken historical view and reports mixed render provenance" do
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
      "broken_view_error" => true,
      "reset_status" => 302,
      "cleared_ref_cookie" => true,
      "cleared_branch_cookie" => true,
      "mixed_preview" => true,
      "historical_partial_tracked" => true,
      "historical_collection_tracked" => true,
      "current_layout_tracked" => true,
      "external_return_rejected" => true,
      "live_status" => 200
    )
  end
end
