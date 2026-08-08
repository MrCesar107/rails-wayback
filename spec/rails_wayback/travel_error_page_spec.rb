# frozen_string_literal: true

require "rails_wayback/travel_error_page"

RSpec.describe RailsWayback::TravelErrorPage do
  it "renders escaped diagnostics and a reset action without host templates" do
    html = described_class.new(
      branch: %(<main>"branch"),
      error: ArgumentError.new(%(<script>alert("unsafe")</script>)),
      ref: "abcdef1234567890",
      reset_url: %(/rails-wayback/reset?return_to=<unsafe>)
    ).render

    expect(html).to include(
      "Historical preview failed",
      "&lt;main&gt;&quot;branch&quot;",
      "abcdef1234567890",
      "ArgumentError",
      "&lt;script&gt;alert(&quot;unsafe&quot;)&lt;/script&gt;",
      "href=\"/rails-wayback/reset?return_to=&lt;unsafe&gt;\""
    )
    expect(html).not_to include("<script>", "<main>")
  end
end
