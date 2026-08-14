# frozen_string_literal: true

require "json"
require "open3"
require "rails_wayback/bar_renderer"

RSpec.describe RailsWayback::BarRenderer do
  let(:test_script) { File.expand_path("../support/javascript/bar_renderer_controller_test.js", __dir__) }
  let(:controller_module) { File.expand_path("../../lib/rails_wayback/bar_renderer.js", __dir__) }
  let(:search_module) { File.expand_path("../../lib/rails_wayback/bar_search.js", __dir__) }
  let(:combobox_module) { File.expand_path("../../lib/rails_wayback/bar_combobox.js", __dir__) }

  def run_controller_test
    stdout, stderr, status = Open3.capture3(
      "node", test_script, controller_module, search_module, combobox_module
    )
    expect(status).to be_success, stderr

    JSON.parse(stdout)
  rescue Errno::ENOENT
    skip "Node.js is required to exercise the packaged toolbar controller"
  end

  it "drives searchable dropdowns and safely manages their lifecycle" do
    expect(run_controller_test).to eq(
      "errorsAndEmptyResults" => true,
      "searchableDropdowns" => true,
      "keyboardSelection" => true,
      "lifecycle" => true,
      "navigationAndTrust" => true,
      "reconnect" => true,
      "staleResponseIgnored" => true
    )
  end
end
